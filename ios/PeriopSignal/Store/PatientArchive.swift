import Foundation
import Observation

// MARK: - The case archive
//
// Ending a case keeps a read-only summary on this phone for a while: the full handoff and the procedure line, from
// PatientSummary and HandoffWriter. Inside a hospital a room and a time can point to one patient, so an entry keeps
// only the date the case ended: no time and no room. Times the app writes (the handoff's footer, the last solids and
// clear fluids) are left out, clock times typed in notes become "--:--", and the room's name and phone are taken out
// of the text. Entries are deleted automatically after the retention period (7 days unless changed), and Delete All
// removes them at once. The file has complete protection and is excluded from iCloud and computer backups.

/// One ended case, as the archive keeps it.
struct PatientArchiveEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    /// The day the case ended, "2026-10-31": a date with no time.
    var day: String
    /// "Laparoscopic sigmoid colectomy · Elective · General": the procedure line.
    var procedure: String
    /// The full handoff.
    var text: String

    init(day: String, procedure: String, text: String) {
        self.day = day
        self.procedure = procedure
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        day = (try? c.decodeIfPresent(String.self, forKey: .day)) ?? ""
        procedure = (try? c.decodeIfPresent(String.self, forKey: .procedure)) ?? ""
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
    }

    func date(calendar: Calendar = .current) -> Date? { PatientArchiveWriter.date(day, calendar: calendar) }

    /// Kept for at least the retention period, then deleted at the first midnight after it (only the date is known).
    func expires(retentionDays: Int, calendar: Calendar = .current) -> Date? {
        guard let start = date(calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: retentionDays + 1, to: start)
    }

    func isExpired(now: Date, retentionDays: Int, calendar: Calendar = .current) -> Bool {
        guard let e = expires(retentionDays: retentionDays, calendar: calendar) else { return true }
        return now >= e
    }

    /// The patient in one line, for the archive list. A 1.9 entry is the 1.9 handoff, whose first line is its header
    /// ("67 yo M (96 kg, 178 cm) had Laparoscopic sigmoid colectomy"); with no header it starts with a labelled block
    /// ("Allergies: NKDA"), which is no one-liner. An older entry starts with the "ANESTHESIA HANDOFF" heading and has
    /// its one-liner ("67-year-old man · 96 kg · 178 cm") on the line after it.
    var oneLiner: String {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first else { return "" }
        if first.hasPrefix("ANESTHESIA HANDOFF") { return lines.count > 1 ? lines[1] : "" }
        let line = first.trimmingCharacters(in: .whitespaces)
        let labelled = Self.blockLabels.contains { line == $0 + ":" || line.hasPrefix($0 + ": ") || line.hasPrefix($0 + " (") }
        return labelled ? "" : line
    }

    /// The labels of the handoff's blocks ("Code status", "Case", "Allergies", "PMH", ...); the header has none.
    private static let blockLabels: [String] = PatientBriefs.slots(.handoff, PatientRecord()).compactMap(\.label)
}

/// Writes an ended case's archive entry.
enum PatientArchiveWriter {
    static let clockTime = #"(?<![\d:.])(?:[01]?\d|2[0-3]):[0-5]\d(?![\d:]|[.,]\d)"#

    private static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// "2026-10-31" in this phone's calendar.
    static func day(_ d: Date, calendar: Calendar = .current) -> String { dayFormatter(calendar).string(from: d) }

    /// The start of that day.
    static func date(_ day: String, calendar: Calendar = .current) -> Date? {
        guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let d = dayFormatter(calendar).date(from: day) else { return nil }
        return calendar.startOfDay(for: d)
    }

    /// "Today", "Yesterday", "Thu 29 Oct", "29 Oct 2025".
    static func label(_ day: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let d = date(day, calendar: calendar) else { return day }
        if calendar.isDate(d, inSameDayAs: now) { return "Today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: y) { return "Yesterday" }
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = calendar.isDate(d, equalTo: now, toGranularity: .year) ? "EEE d MMM" : "d MMM yyyy"
        return f.string(from: d)
    }

    /// The summary of an ended case: the procedure line and the full handoff, without the room or any time.
    static func entry(for c: PatientCase, now: Date = Date(), calendar: Calendar = .current) -> PatientArchiveEntry {
        var r = c.record
        // The times the app itself writes.
        r.updated = nil
        r.lastSolids = nil
        r.lastClears = nil
        for k in r.scores.keys { r.scores[k]?.date = nil }
        let procedure = PatientSummary.procedureLines(r).filter { $0.label == nil }.map(\.text).joined(separator: " · ")
        // The 1.9 handoff, as it was handed over: with the user's edits to its blocks (r.handoffEdits).
        var lines = PatientBriefs.plainText(PatientBriefs.handoff(r, now: now)).components(separatedBy: "\n")
        // The archive's footer says only the date.
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty || last.hasPrefix("Prepared with Periop Signal") {
            lines.removeLast()
        }
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        lines.append("")
        lines.append("Archived in Periop Signal, " + f.string(from: now) + ". Check against the chart.")
        let title = scrub(procedure, room: c.room, phone: c.roomPhone)
        return PatientArchiveEntry(day: day(now, calendar: calendar),
                                   procedure: title.isEmpty ? "Case" : title,
                                   text: scrub(lines.joined(separator: "\n"), room: c.room, phone: c.roomPhone))
    }

    /// Takes the room, its phone and clock times out of text typed into the case.
    static func scrub(_ text: String, room: String, phone: String) -> String {
        var s = text
        let r = room.trimmingCharacters(in: .whitespacesAndNewlines)
        // A room with a letter in it ("OR 12", "EP 2"); a bare number would match doses and values.
        if r.count >= 2, r.contains(where: \.isLetter) {
            let tokens = r.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
            let pattern = #"(?<![\p{L}\p{N}])"# + tokens.joined(separator: #"\s*"#) + #"(?![\p{L}\p{N}])"#
            s = s.replacingOccurrences(of: pattern, with: "[room]", options: [.regularExpression, .caseInsensitive])
        }
        let digits = phone.filter { $0.isASCII && $0.isNumber }
        if digits.count >= 4 {
            let pattern = #"(?<!\d)\(?"# + digits.map(String.init).joined(separator: #"[\s().\-]*"#) + #"(?!\d)"#
            s = s.replacingOccurrences(of: pattern, with: "[room phone]", options: .regularExpression)
        }
        return s.replacingOccurrences(of: clockTime, with: "--:--", options: .regularExpression)
    }
}

/// The archive on this phone: ended cases' summaries, deleted after the retention period.
@MainActor
@Observable
final class PatientArchive {
    /// Retention choices in days: 24 h, 3 days, 7 days, 30 days.
    static let retentionChoices = [1, 3, 7, 30]
    static let defaultRetention = 7
    static let maxEntries = 500
    static let retentionKey = "ps.archive.retentionDays"
    static let lockKey = "ps.archive.lock"

    private(set) var entries: [PatientArchiveEntry] = []
    private(set) var retentionDays = 7
    /// Face ID or the passcode to open the archive; off unless turned on.
    private(set) var lockEnabled = false
    /// The file has been read (not while the phone is locked); writes wait for it so nothing is lost.
    private(set) var loaded = false

    private let url: URL?
    private let defaults: UserDefaults
    @ObservationIgnored private var dirty = false

    init(url: URL?, entries seed: [PatientArchiveEntry]? = nil, defaults: UserDefaults = .standard) {
        self.url = url
        self.defaults = defaults
        let saved = defaults.integer(forKey: PatientArchive.retentionKey)
        retentionDays = PatientArchive.retentionChoices.contains(saved) ? saved : PatientArchive.defaultRetention
        lockEnabled = defaults.bool(forKey: PatientArchive.lockKey)
        if let seed {
            entries = seed
            loaded = true
            return
        }
        reload()
        prune()
    }

    static func retentionLabel(_ days: Int) -> String { days == 1 ? "24 h" : "\(days) days" }

    func setRetention(_ days: Int, now: Date = Date()) {
        guard PatientArchive.retentionChoices.contains(days), days != retentionDays else { return }
        retentionDays = days
        defaults.set(days, forKey: PatientArchive.retentionKey)
        prune(now: now)
    }

    func setLock(_ on: Bool) {
        lockEnabled = on
        defaults.set(on, forKey: PatientArchive.lockKey)
    }

    func add(_ entry: PatientArchiveEntry, now: Date = Date()) {
        if !loaded { reload() }
        entries.insert(entry, at: 0)
        if entries.count > PatientArchive.maxEntries { entries.removeLast(entries.count - PatientArchive.maxEntries) }
        prune(now: now, force: true)
    }

    func delete(_ id: UUID) {
        if !loaded { reload() }
        entries.removeAll { $0.id == id }
        save()
    }

    func deleteAll() {
        entries = []
        loaded = true
        save()
    }

    /// Deletes what has passed the retention period (at launch, when the app becomes active and when the archive opens).
    func prune(now: Date = Date(), force: Bool = false) {
        if !loaded { reload() }
        let before = entries.count
        entries.removeAll { $0.isExpired(now: now, retentionDays: retentionDays) }
        if force || dirty || entries.count != before { save() }
    }

    /// The summaries of one day.
    struct Day: Identifiable, Equatable {
        var day: String
        var entries: [PatientArchiveEntry]
        var id: String { day }
    }

    /// By day, newest first.
    var byDay: [Day] {
        var order: [String] = []
        var groups: [String: [PatientArchiveEntry]] = [:]
        for e in entries {
            if groups[e.day] == nil { order.append(e.day) }
            groups[e.day, default: []].append(e)
        }
        return order.sorted(by: >).map { Day(day: $0, entries: groups[$0] ?? []) }
    }

    // MARK: Storage

    private struct File: Codable {
        var kind = "org.periopsignal.archive"
        var format = 1
        var entries: [PatientArchiveEntry]
    }

    /// Reads the file; entries added before it could be read (phone locked) are kept as well.
    private func reload() {
        guard let url else { loaded = true; return }
        if !FileManager.default.fileExists(atPath: url.path) { loaded = true; return }
        guard let data = try? Data(contentsOf: url) else { return }
        let saved = (try? JSONDecoder().decode(File.self, from: data))?.entries ?? []
        let ids = Set(saved.map(\.id))
        entries = entries.filter { !ids.contains($0.id) } + saved
        loaded = true
    }

    private func save() {
        dirty = true
        guard loaded else { return }
        guard let url else { dirty = false; return }
        if entries.isEmpty {
            try? FileManager.default.removeItem(at: url)
            dirty = false
            return
        }
        guard let data = try? JSONEncoder().encode(File(entries: entries)) else { return }
        if PatientFiles.write(data, to: url) { dirty = false }
    }
}

// MARK: - Room directory

/// A room and its phone, saved so the number is typed once: hospital data, never a patient detail.
struct PatientRoom: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var phone: String

    init(name: String, phone: String) {
        self.name = name
        self.phone = phone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        phone = (try? c.decodeIfPresent(String.self, forKey: .phone)) ?? ""
    }

    /// "or 12" for "OR  12": names compare without case or extra spaces.
    static func key(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// The rooms saved on this phone, most recently used first. No dates are kept with them.
@MainActor
@Observable
final class PatientRoomDirectory {
    static let maxRooms = 40

    private(set) var rooms: [PatientRoom] = []
    private(set) var loaded = false
    private let url: URL?

    init(url: URL?, rooms seed: [PatientRoom]? = nil) {
        self.url = url
        if let seed {
            rooms = seed
            loaded = true
            return
        }
        reload()
    }

    func room(named name: String) -> PatientRoom? {
        let k = PatientRoom.key(name)
        guard !k.isEmpty else { return nil }
        return rooms.first { PatientRoom.key($0.name) == k }
    }

    /// Saved rooms whose name holds what is typed (all of them when nothing is).
    func matches(_ text: String) -> [PatientRoom] {
        let k = PatientRoom.key(text)
        guard !k.isEmpty else { return rooms }
        return rooms.filter { PatientRoom.key($0.name).contains(k) }
    }

    /// Saves a room, or updates its phone; it moves to the top. An empty phone keeps the one saved.
    func save(name: String, phone: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        if !loaded { reload() }
        var room = PatientRoom(name: n, phone: p)
        if let i = rooms.firstIndex(where: { PatientRoom.key($0.name) == PatientRoom.key(n) }) {
            room = rooms.remove(at: i)
            room.name = n
            if !p.isEmpty { room.phone = p }
        }
        rooms.insert(room, at: 0)
        if rooms.count > PatientRoomDirectory.maxRooms { rooms.removeLast(rooms.count - PatientRoomDirectory.maxRooms) }
        save()
    }

    func remove(_ id: UUID) {
        if !loaded { reload() }
        rooms.removeAll { $0.id == id }
        save()
    }

    func refresh() { if !loaded { reload() } }

    private func reload() {
        guard let url else { loaded = true; return }
        if !FileManager.default.fileExists(atPath: url.path) { loaded = true; return }
        guard let data = try? Data(contentsOf: url) else { return }
        let saved = (try? JSONDecoder().decode([PatientRoom].self, from: data)) ?? []
        let keys = Set(rooms.map { PatientRoom.key($0.name) })
        rooms = rooms + saved.filter { !keys.contains(PatientRoom.key($0.name)) }
        loaded = true
    }

    private func save() {
        guard loaded, let url else { return }
        if rooms.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(rooms) else { return }
        _ = PatientFiles.write(data, to: url)
    }
}

// MARK: - Files

enum PatientFiles {
    /// Writes with complete protection (unreadable while the phone is locked) and keeps the file out of iCloud and
    /// computer backups.
    @discardableResult
    static func write(_ data: Data, to url: URL) -> Bool {
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var u = url
            try? u.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }
}
