import Foundation

// MARK: - Cases by room
//
// My Patient holds several cases at once, one per operating or procedure room, for the anesthesiologist covering
// more than one. Each case is a PatientRecord plus the room ("OR 12", "CVOR 3", "EP 2") and the room's phone. One
// case is current: PatientStore.record and update() read and change it, so the editors are unchanged. All the cases
// are saved together in My Patient's one protected file on this phone (PatientStore). A record saved by 1.6 opens as
// the first case, with no room.

struct PatientCase: Codable, Equatable, Identifiable {
    var id = UUID()
    /// "Case 2" while no room is set: numbered as cases are added, and kept when another case ends.
    var number = 1
    var record = PatientRecord()
    /// The operating or procedure room ("OR 12"): hospital data, never a patient detail.
    var room = ""
    /// The room's phone, for Call and Text.
    var roomPhone = ""
    var created = Date()
    var updated = Date()

    init(number: Int = 1, record: PatientRecord = PatientRecord(), room: String = "", roomPhone: String = "", now: Date = Date()) {
        self.number = number
        self.record = record
        self.room = room
        self.roomPhone = roomPhone
        created = now
        updated = now
    }

    /// Every field read with a fallback, like PatientRecord, so a newer or damaged file still opens.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        number = (try? c.decodeIfPresent(Int.self, forKey: .number)) ?? 1
        record = (try? c.decodeIfPresent(PatientRecord.self, forKey: .record)) ?? PatientRecord()
        room = (try? c.decodeIfPresent(String.self, forKey: .room)) ?? ""
        roomPhone = (try? c.decodeIfPresent(String.self, forKey: .roomPhone)) ?? ""
        created = (try? c.decodeIfPresent(Date.self, forKey: .created)) ?? Date()
        updated = (try? c.decodeIfPresent(Date.self, forKey: .updated)) ?? created
    }

    /// The room, or "Case 2" when none is set.
    var label: String {
        let r = room.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.isEmpty ? "Case \(number)" : r
    }

    var hasRoom: Bool { !room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasPhone: Bool { PatientPhone.callURL(roomPhone) != nil }

    /// The first planned procedure, else the one-liner ("67-year-old man"): the second line of the case's tab.
    var detail: String {
        if let p = record.procedures.first?.title, !p.isEmpty { return p }
        let typed = record.procedure.components(separatedBy: " + ").first?.trimmingCharacters(in: .whitespaces) ?? ""
        if !typed.isEmpty { return typed }
        return record.person
    }

    /// Nothing entered, and no room or phone.
    var isBlank: Bool {
        record.isEmpty && !hasRoom && roomPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// All the cases on this phone and which one is current; what My Patient's file holds from 1.7.
struct PatientCaseBook: Codable, Equatable {
    static let kind = "org.periopsignal.cases"
    static let currentFormat = 1
    /// More rooms than anyone covers at once.
    static let maxCases = 12

    var kind = PatientCaseBook.kind
    var format = PatientCaseBook.currentFormat
    private(set) var cases: [PatientCase]
    private(set) var currentID: UUID

    init() {
        let c = PatientCase()
        cases = [c]
        currentID = c.id
    }

    /// A record saved by 1.6 (one patient) becomes the first case, with no room.
    init(migrating r: PatientRecord, now: Date = Date()) {
        self.init()
        guard !r.isEmpty else { return }
        var c = PatientCase(number: 1, record: r, now: r.updated ?? now)
        c.updated = r.updated ?? now
        cases = [c]
        currentID = c.id
    }

    init(cases list: [PatientCase], current: UUID? = nil) {
        self.init()
        guard !list.isEmpty else { return }
        cases = list
        currentID = current.flatMap { id in list.contains { $0.id == id } ? id : nil } ?? list[0].id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard (try? c.decode(String.self, forKey: .kind)) == PatientCaseBook.kind else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Not My Patient's cases")
        }
        let list = (try? c.decode([PatientCase].self, forKey: .cases)) ?? []
        let current = try? c.decodeIfPresent(UUID.self, forKey: .currentID)
        self.init(cases: list, current: current)
        format = (try? c.decodeIfPresent(Int.self, forKey: .format)) ?? PatientCaseBook.currentFormat
    }

    /// The file's contents: the cases as saved from 1.7, or one record saved by 1.6.
    static func decode(_ data: Data) -> PatientCaseBook? {
        if let b = try? JSONDecoder().decode(PatientCaseBook.self, from: data) { return b }
        // A file that holds cases but did not read is not a 1.6 record: don't take it for an empty patient.
        if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], o["cases"] != nil || o["kind"] != nil { return nil }
        if let r = try? JSONDecoder().decode(PatientRecord.self, from: data) { return PatientCaseBook(migrating: r) }
        return nil
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    var current: PatientCase { cases.first { $0.id == currentID } ?? cases[0] }
    private var currentIndex: Int { cases.firstIndex { $0.id == currentID } ?? 0 }

    /// The current case's record; changing it stamps the case as updated.
    var currentRecord: PatientRecord {
        get { current.record }
        set {
            let i = currentIndex
            guard cases[i].record != newValue else { return }
            cases[i].record = newValue
            cases[i].updated = newValue.updated ?? Date()
        }
    }

    /// One case with nothing in it: there is nothing to keep, so the file is removed.
    var isEmpty: Bool { cases.count == 1 && cases[0].isBlank }
    var canAdd: Bool { cases.count < PatientCaseBook.maxCases }
    private var nextNumber: Int { (cases.map(\.number).max() ?? 0) + 1 }

    /// Adds a case (optionally in a room) and makes it current.
    @discardableResult
    mutating func add(room: String = "", phone: String = "", now: Date = Date()) -> UUID? {
        guard canAdd else { return nil }
        let c = PatientCase(number: nextNumber, room: room.trimmingCharacters(in: .whitespacesAndNewlines),
                            roomPhone: phone.trimmingCharacters(in: .whitespacesAndNewlines), now: now)
        cases.append(c)
        currentID = c.id
        return c.id
    }

    mutating func select(_ id: UUID) {
        if cases.contains(where: { $0.id == id }) { currentID = id }
    }

    /// Sets a case's room and phone (the current case when no id is given).
    mutating func setRoom(_ room: String, phone: String, for id: UUID? = nil, now: Date = Date()) {
        guard let i = cases.firstIndex(where: { $0.id == (id ?? currentID) }) else { return }
        let r = room.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cases[i].room != r || cases[i].roomPhone != p else { return }
        cases[i].room = r
        cases[i].roomPhone = p
        cases[i].updated = now
    }

    /// Replaces a case with an empty one in the same room, with the same phone, in its place in the list, and makes
    /// it current: the next patient in that room.
    @discardableResult
    mutating func next(after id: UUID, now: Date = Date()) -> PatientCase? {
        guard let i = cases.firstIndex(where: { $0.id == id }) else { return nil }
        let gone = cases[i]
        let c = PatientCase(number: nextNumber, room: gone.room, roomPhone: gone.roomPhone, now: now)
        cases[i] = c
        currentID = c.id
        return gone
    }

    /// Removes a case; the next one becomes current, and a fresh Case 1 takes the place of the last.
    @discardableResult
    mutating func remove(_ id: UUID, now: Date = Date()) -> PatientCase? {
        guard let i = cases.firstIndex(where: { $0.id == id }) else { return nil }
        let gone = cases.remove(at: i)
        if cases.isEmpty {
            let c = PatientCase(number: 1, now: now)
            cases = [c]
            currentID = c.id
        } else if currentID == id {
            currentID = cases[min(i, cases.count - 1)].id
        }
        return gone
    }
}

// MARK: - Phone

/// A room's phone as the Phone and Messages apps take it.
enum PatientPhone {
    /// "216-555-0142 ext 4512" → ("2165550142", "4512"); a leading + is kept. Nil under 3 digits.
    static func parts(_ s: String) -> (number: String, ext: String)? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        var main = t
        var ext = ""
        if let r = t.range(of: #"\s*(?:ext\.?|extension|x|,|;|#)\s*"#, options: [.regularExpression, .caseInsensitive]),
           t[t.startIndex..<r.lowerBound].contains(where: \.isNumber) {
            main = String(t[t.startIndex..<r.lowerBound])
            ext = String(t[r.upperBound...].filter(\.isNumber))
        }
        let digits = main.filter { $0.isASCII && $0.isNumber }
        guard digits.count >= 3 else { return nil }
        let plus = main.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        return ((plus ? "+" : "") + digits, ext)
    }

    /// tel: for Call; an extension follows a pause.
    static func callURL(_ s: String) -> URL? {
        guard let p = parts(s) else { return nil }
        return URL(string: "tel:" + p.number + (p.ext.isEmpty ? "" : "," + p.ext))
    }

    /// sms: for Text (the number without the extension).
    static func textURL(_ s: String) -> URL? {
        guard let p = parts(s) else { return nil }
        return URL(string: "sms:" + p.number)
    }
}

// MARK: - The cases in the store

extension PatientStore {
    var cases: [PatientCase] { book.cases }
    var currentCase: PatientCase { book.current }
    var canAddCase: Bool { book.canAdd }

    /// Adds a case and opens it.
    func addCase(room: String = "", phone: String = "") {
        updateBook { $0.add(room: room, phone: phone) }
    }

    func selectCase(_ id: UUID) {
        updateBook { $0.select(id) }
    }

    /// The current case's room and phone; with `remember`, the room directory keeps them for the next case there.
    func setRoom(_ room: String, phone: String, remember: Bool = false) {
        updateBook { $0.setRoom(room, phone: phone) }
        if remember { rooms.save(name: room, phone: phone) }
    }

    /// Ends a case (the current one by default): its summary goes to the archive, with the date only (no time and no
    /// room), unless nothing was entered or `keepSummary` is false; then the case is removed from the phone. With
    /// `nextInRoom`, an empty case takes its place in the same room, with the same phone, for the next patient.
    @discardableResult
    func endCase(_ id: UUID? = nil, keepSummary: Bool = true, nextInRoom: Bool = false, now: Date = Date()) -> PatientArchiveEntry? {
        var entry: PatientArchiveEntry?
        updateBook(immediately: true) { b in
            let target = id ?? b.current.id
            guard let c = b.cases.first(where: { $0.id == target }) else { return }
            if keepSummary && !c.record.isEmpty { entry = PatientArchiveWriter.entry(for: c, now: now) }
            if nextInRoom { b.next(after: target, now: now) } else { b.remove(target, now: now) }
        }
        if let entry { archive.add(entry, now: now) }
        return entry
    }

    nonisolated static func fileURL(_ name: String, near url: URL?) -> URL? {
        url?.deletingLastPathComponent().appendingPathComponent(name)
    }

    #if DEBUG
    /// Screenshot runs: -ps.patient demo-rooms opens three made-up cases in OR 12, CVOR 3 and EP 2 (-ps.patient.case 2
    /// opens the second) with one archived summary and two saved rooms; the other -ps.patient seeds open one case.
    /// Nothing is read from or written to disk.
    static func debugCases() -> PatientDemo.Seed? {
        if LaunchSeed.string("ps.patient") == "demo-rooms" {
            return PatientDemo.rooms(select: LaunchSeed.int("ps.patient.case", default: 1))
        }
        guard let r = debugSeed() else { return nil }
        return PatientDemo.Seed(book: PatientCaseBook(cases: [PatientCase(record: r)]), archived: [], rooms: [])
    }
    #endif
}

// MARK: - Made-up cases for screenshots and tests

extension PatientDemo {
    struct Seed {
        var book: PatientCaseBook
        var archived: [PatientArchiveEntry]
        var rooms: [PatientRoom]
    }

    /// A made-up electrophysiology case.
    static var ep: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 71; r.sex = .female; r.heightCm = 163; r.weightKg = 70
        r.setProcedures(PlannedProcedure.parse("Pulmonary vein isolation"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.problems = ["htn", "af"]
        r.medications = "Apixaban (held 48 h), metoprolol"
        r.nkda = true
        r.asaClass = 3
        return r
    }

    /// A made-up case that ended, for the archive.
    static var archivedCase: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 45; r.sex = .female; r.heightCm = 165; r.weightKg = 74
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.nkda = true
        r.asaClass = 2
        r.mask = "easy"; r.intubation = "easy"; r.airwayDevice = "Video laryngoscope"; r.laryngoscopyGrade = "1"; r.attempts = 1
        r.airwayAtEnd = "extubated"
        r.medsGiven = "Cefazolin 2 g 07:55; dexamethasone 4 mg; ondansetron 4 mg"
        r.noEvents = true
        r.disposition = "PACU"
        r.painPlan = "Acetaminophen; ketorolac; hydromorphone as needed"
        return r
    }

    static func rooms(select: Int = 1, now: Date = Date()) -> Seed {
        let list = [
            PatientCase(number: 1, record: PatientDemo.record, room: "OR 12", roomPhone: "216-555-0112", now: now),
            PatientCase(number: 2, record: PatientDemo.cardiac, room: "CVOR 3", roomPhone: "216-555-0103", now: now),
            PatientCase(number: 3, record: PatientDemo.ep, room: "EP 2", roomPhone: "", now: now),
        ]
        let pick = list[max(0, min(list.count - 1, select - 1))].id
        let ended = PatientCase(number: 4, record: archivedCase, room: "OR 7", roomPhone: "216-555-0107", now: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        return Seed(book: PatientCaseBook(cases: list, current: pick),
                    archived: [PatientArchiveWriter.entry(for: ended, now: yesterday)],
                    rooms: [PatientRoom(name: "OR 12", phone: "216-555-0112"), PatientRoom(name: "CVOR 3", phone: "216-555-0103"),
                            PatientRoom(name: "OR 7", phone: "216-555-0107")])
    }
}
