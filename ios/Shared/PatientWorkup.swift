import Foundation

// MARK: - My Patient workup records
//
// Past operations, echo findings, catheterization, the ECG and the patient's current airway support: what the
// preoperative tab records beyond the problem lists. Every type decodes with a fallback for each field, like
// PatientRecord, so a patient saved by an older version (or sent from one) still opens.

/// Month and year, as a chart gives them ("03/2019", or "2019" alone).
struct PatientMonthYear: Codable, Hashable {
    var month: Int?
    var year: Int?

    init(month: Int? = nil, year: Int? = nil) { self.month = month; self.year = year }

    var isEmpty: Bool { month == nil && year == nil }
    var text: String {
        guard let y = year else { return "" }
        guard let m = month, (1...12).contains(m) else { return String(y) }
        return String(format: "%02d/%d", m, y)
    }

    private static let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

    /// A two-digit year: 20YY when that is no later than next year, else 19YY ("26" is 2026 and "28" is 1928 in 2026).
    static func fullYear(twoDigit yy: Int, now: Date = Date()) -> Int {
        let this = Calendar.current.component(.year, from: now)
        return 2000 + yy <= this + 1 ? 2000 + yy : 1900 + yy
    }

    private static func isDigits(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isWholeNumber } }

    private static func separator(_ c: Character) -> Bool { c == "/" || c == "-" || c == "." || c == " " || c == "," }

    /// Reads a month and year however it is typed (1.8.3, Ben: no "/" needed): "03/2019", "3/19", "6 2026", "6-2026",
    /// "6.2026", "2026-06", "2019", "Mar 2019", "June 26", and digits alone: "0626" and "062026" (MMYY, MMYYYY), "626"
    /// and "62026" (M YY, M YYYY). A two-digit year is 20YY when that is no later than next year, else 19YY.
    static func parse(_ s: String, now: Date = Date()) -> PatientMonthYear? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return nil }
        func year(_ digits: String) -> Int? {
            guard let y = Int(digits) else { return nil }
            switch digits.count {
            case 4: return (1900...2100).contains(y) ? y : nil
            case 2: return fullYear(twoDigit: y, now: now)
            default: return nil
            }
        }
        func month(_ digits: String) -> Int? {
            guard digits.count <= 2, let m = Int(digits), (1...12).contains(m) else { return nil }
            return m
        }
        let parts = t.split(whereSeparator: { separator($0) }).map(String.init)
        if parts.count == 1 {
            let p = parts[0]
            guard isDigits(p) else { return nil }
            switch p.count {
            case 2: return year(p).map { PatientMonthYear(year: $0) }
            case 4:
                if let y = year(p) { return PatientMonthYear(year: y) }
                if let m = month(String(p.prefix(2))), let y = year(String(p.suffix(2))) { return PatientMonthYear(month: m, year: y) }
                return nil
            case 3:
                if let m = month(String(p.prefix(1))), let y = year(String(p.suffix(2))) { return PatientMonthYear(month: m, year: y) }
                return nil
            case 5:
                if let m = month(String(p.prefix(1))), let y = year(String(p.suffix(4))) { return PatientMonthYear(month: m, year: y) }
                return nil
            case 6:
                if let m = month(String(p.prefix(2))), let y = year(String(p.suffix(4))) { return PatientMonthYear(month: m, year: y) }
                return nil
            default: return nil
            }
        }
        if parts.count == 2 {
            let a = parts[0], b = parts[1]
            if isDigits(a), isDigits(b) {
                if let m = month(a), let y = year(b) { return PatientMonthYear(month: m, year: y) }
                // "2026-06"
                if a.count == 4, let y = year(a), let m = month(b) { return PatientMonthYear(month: m, year: y) }
                return nil
            }
            if a.count >= 3, a.allSatisfy({ $0.isLetter }), isDigits(b), let y = year(b),
               let m = monthNames.firstIndex(where: { $0.hasPrefix(a) }) {
                return PatientMonthYear(month: m + 1, year: y)
            }
        }
        return nil
    }

    /// The text as it is typed into a month and year field: a "/" goes in by itself after the month ("06" becomes "06/",
    /// "6" becomes "06/", "062026" becomes "06/2026"), and a "-", "." or space typed after the month becomes it. A year
    /// alone ("2019", "1999") is left to be typed. Deleting from the end never adds anything, so Backspace goes back through the "/".
    /// `old` is the text before the change.
    static func typing(_ new: String, was old: String) -> String {
        // Deleting from the end (or nothing changed): as it is. Replacing a selection is typing.
        if old.hasPrefix(new) { return new }
        guard new.allSatisfy({ ($0.isASCII && $0.isWholeNumber) || separator($0) }) else { return new }
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        // Pasted digits that read as a whole date ("62026", "0626"): the date.
        if isDigits(trimmed), new.count - old.count > 1, let v = parse(trimmed) { return v.text }
        func pad(_ m: String) -> String { m.count == 1 ? "0" + m : m }
        let chars = Array(new)
        var head = ""
        var i = 0
        while i < chars.count, chars[i].isASCII, chars[i].isWholeNumber { head.append(chars[i]); i += 1 }
        let rest = chars[i...]
        if !rest.isEmpty {
            // A separator after the month's digits.
            guard !head.isEmpty, head.count <= 2, let m = Int(head), (1...12).contains(m) else { return new }
            let year = String(rest.filter { $0.isASCII && $0.isWholeNumber }.prefix(4))
            return pad(head) + "/" + year
        }
        let d = Array(head)
        guard let d0 = d.first else { return new }
        // How many leading digits are the month; nil: still a year being typed ("1", "19", "20", "2026").
        var k: Int?
        switch d0 {
        case "0":
            guard d.count >= 2 else { return new }
            if d[1] == "0" { return new }
            k = 2
        case "1":
            if d.count == 1 { return new }
            if d[1] == "9" { k = nil } else if d[1] == "0" || d[1] == "1" || d[1] == "2" { k = 2 } else { k = 1 }
        case "2":
            if d.count == 1 { return new }
            k = d[1] == "0" ? nil : 1
        default:
            k = 1
        }
        guard let k else { return d.count > 4 ? String(d.prefix(4)) : new }
        let month = String(d.prefix(k))
        let year = String(d.dropFirst(k).prefix(4))
        return pad(month) + "/" + year
    }

    /// The date a field being typed holds once it is settled; nil while it is still being typed (a trailing "/", a year
    /// of one or three digits, "20"), so a half-typed text never changes the value.
    static func parseTyped(_ s: String, now: Date = Date()) -> PatientMonthYear? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = t.last, last.isLetter || last.isWholeNumber else { return nil }
        let parts = t.split(whereSeparator: { separator($0) }).map(String.init)
        if parts.count == 1, isDigits(parts[0]), parts[0].count != 4 { return nil }
        if parts.count == 2, isDigits(parts[1]), parts[1].count != 2, parts[1].count != 4 { return nil }
        return parse(t, now: now)
    }
}

/// One planned procedure: from the procedure list (with its side when it has one) or typed, plus any details
/// ("×3", "possible open conversion").
struct PlannedProcedure: Codable, Hashable, Identifiable {
    var id = UUID()
    /// The procedure list's id; nil when typed.
    var catalogID: String?
    var name = ""
    /// "left", "right", "bilateral".
    var side: String?
    var detail = ""

    init(catalogID: String? = nil, name: String = "", side: String? = nil, detail: String = "") {
        self.catalogID = catalogID; self.name = name; self.side = side; self.detail = detail
    }

    init(_ p: Procedure, side: String? = nil, detail: String = "") {
        catalogID = p.id; name = p.name; self.side = p.lateral ? side : nil; self.detail = detail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        catalogID = try? c.decodeIfPresent(String.self, forKey: .catalogID)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        side = try? c.decodeIfPresent(String.self, forKey: .side)
        detail = (try? c.decodeIfPresent(String.self, forKey: .detail)) ?? ""
    }

    var catalog: Procedure? { catalogID.flatMap { ProcedureCatalog.byID($0) } }
    /// The one more choice its procedure asks (a bare Bentall: which valve), while unanswered.
    var ask: ProcedureAsk? { catalog?.ask }

    /// This item as the chosen procedure (an option of `ask`), with its side and details; nil for another id.
    func answering(_ id: String) -> PlannedProcedure? {
        guard let ask, ask.options.contains(where: { $0.id == id }), let p = ProcedureCatalog.byID(id) else { return nil }
        var x = self
        x.catalogID = p.id
        x.name = p.name
        x.side = p.lateral ? side : nil
        return x
    }
    /// The procedure has a side and none was picked.
    var needsSide: Bool { catalog?.needsSide(side) ?? false }

    /// "Left total knee arthroplasty", without the details.
    var title: String {
        if let p = catalog { return p.displayName(side: side) }
        guard let side, !side.isEmpty else { return name }
        return side.capitalized + " " + name.lowercasedFirst
    }

    /// "Coronary artery bypass grafting ×3".
    var text: String {
        let d = detail.trimmingCharacters(in: .whitespaces)
        return d.isEmpty ? title : title + " " + d
    }

    /// The planned procedures read from free text ("CABG x3 + AVR", "lap chole, possible open", "L TKA"). Words
    /// between procedures become the details of the one before ("×3", "possible open"); a procedure the patient is
    /// on or has had ("on VA ECMO", "s/p CABG") is kept as words, not planned. Words before the first procedure
    /// become a typed procedure of their own, and text the list does not know at all stays as typed.
    static func parse(_ text: String) -> [PlannedProcedure] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        let matches = ProcedureCatalog.parse(t)
            .filter { $0.range.upperBound <= t.endIndex }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
        var items: [PlannedProcedure] = []
        // Words before the first recognized procedure: a typed procedure, and any history told before it.
        var lead: [String] = []
        var leadHistory: [String] = []
        var afterContext = false
        var cursor = t.startIndex
        func attach(_ ws: [String], history: Bool = false) {
            guard !ws.isEmpty else { return }
            if items.isEmpty {
                if history || afterContext { leadHistory += ws } else { lead += ws }
                return
            }
            let d = items[items.count - 1].detail
            items[items.count - 1].detail = ((d.isEmpty ? [] : [d]) + ws).joined(separator: " ")
        }
        for m in matches where m.range.lowerBound >= cursor {
            let gap = words(t[cursor..<m.range.lowerBound])
            if let last = gap.last, contextWords.contains(last.lowercased()) {
                attach(Array(gap.dropLast()))
                attach([last, String(t[m.range])], history: true)
                afterContext = true
            } else {
                attach(gap)
                items.append(PlannedProcedure(m.procedure, side: m.side))
                afterContext = false
            }
            cursor = m.range.upperBound
        }
        attach(words(t[cursor...]))
        let typed = lead.joined(separator: " ")
        let history = leadHistory.joined(separator: " ")
        if items.isEmpty {
            return [typed.isEmpty ? PlannedProcedure(name: t) : PlannedProcedure(name: typed, detail: history)]
        }
        if typed.filter(\.isLetter).count >= 3 {
            items.insert(PlannedProcedure(name: typed, detail: history), at: 0)
        } else if !history.isEmpty {
            items[0].detail = ([history] + (items[0].detail.isEmpty ? [] : [items[0].detail])).joined(separator: " ")
        }
        return items
    }

    /// A procedure after one of these is one the patient is on or has had.
    private static let contextWords: Set<String> = ["on", "s/p", "sp", "post", "h/o", "hx", "after", "prior", "previous",
                                                    "in", "known", "existing", "has", "had", "history"]
    /// Joining words and the urgency (recorded on its own) are dropped.
    private static let fillerWords: Set<String> = ["and", "with", "w/", "w", "plus", "then", "&", "+", "/", "-",
        "emergency", "emergent", "urgent", "elective", "stat", "planned", "scheduled", "for"]

    /// The words of a gap, without joining words, with a count written "×3".
    private static func words(_ s: Substring) -> [String] {
        let trim = CharacterSet(charactersIn: ",;:+&()").union(.whitespaces)
        var out: [String] = []
        for raw in s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            let w = String(raw).trimmingCharacters(in: trim)
            guard !w.isEmpty, !fillerWords.contains(w.lowercased()) else { continue }
            if let n = count(w) { out.append("×" + n) } else { out.append(w) }
        }
        // A "×" written apart from its number ("× 3").
        var merged: [String] = []
        for w in out {
            if let prev = merged.last, prev == "×" || prev == "x", w.allSatisfy(\.isNumber) { merged[merged.count - 1] = "×" + w } else { merged.append(w) }
        }
        return merged
    }

    /// "x3", "X3", "×3" → "3".
    private static func count(_ w: String) -> String? {
        guard let f = w.first, f == "x" || f == "X" || f == "×" else { return nil }
        let n = w.dropFirst()
        return !n.isEmpty && n.allSatisfy(\.isNumber) ? String(n) : nil
    }
}

extension PatientRecord {
    /// Replaces the planned procedures, keeps `procedure` (the joined text) in step and, when the recognized
    /// procedures or their sides change, fills the risk-score inputs from them. Typed procedures add nothing.
    mutating func setProcedures(_ list: [PlannedProcedure], fillAnesthetic: Bool = true) {
        func key(_ l: [PlannedProcedure]) -> [String] { l.compactMap { p in p.catalogID.map { $0 + "|" + (p.side ?? "") } } }
        let changed = key(procedures) != key(list) || procedures.isEmpty
        procedures = list
        procedure = list.map(\.text).filter { !$0.isEmpty }.joined(separator: " + ")
        // Typing a detail or a typed procedure's name keeps any input the clinician changed.
        let picked = list.compactMap { p in p.catalog.map { (procedure: $0, side: p.side) } }
        guard changed, !picked.isEmpty else { return }
        let risk = ProcedureCatalog.risk(picked: picked)
        if fillAnesthetic {
            risk.apply(to: &self)
        } else {
            highRiskSurgery = risk.highRisk
            incision = risk.incision
            duration = risk.duration
        }
    }

    /// The planned procedures the list recognizes: from the items, or read from the text in an older save.
    var recognizedProcedures: [Procedure] { plannedItems.compactMap(\.catalog) }

    /// The planned procedures as items: the record's own, or read from the text in an older save (so "s/p CABG" and
    /// "on LVAD" stay details, not planned procedures).
    var plannedItems: [PlannedProcedure] { procedures.isEmpty ? PlannedProcedure.parse(procedure) : procedures }

    /// The names of the typed procedures, without details: what keyword rules may read. A recognized procedure has
    /// its own flags, and details ("s/p CABG", "in an LVAD patient") are history, not the operation.
    var typedProcedureNames: String { plannedItems.filter { $0.catalogID == nil }.map(\.name).joined(separator: " + ") }
}

/// One past operation: from the procedure list or typed, with the side and the month and year.
struct PatientSurgery: Codable, Hashable, Identifiable {
    var id = UUID()
    /// The operation as one line ("Aortic valve replacement + Coronary artery bypass grafting ×3"); kept in step with
    /// `procedures` for older readers. In a save from before 1.7 it is the name as typed.
    var name = ""
    /// The first procedure's list id, kept for older readers.
    var procedureID: String?
    /// "left", "right", "bilateral" (the first procedure's side).
    var side: String?
    /// The procedures done in this operation (1.7): several on one date (AVR and CABG together), each picked from the
    /// list or typed, with its side and details.
    var procedures: [PlannedProcedure] = []
    var date = PatientMonthYear()
    /// A cardiac or thoracic operation (a previous sternotomy or thoracotomy), for the cardiac evaluation.
    var intrathoracic = false

    init(name: String = "", procedureID: String? = nil, side: String? = nil, date: PatientMonthYear = PatientMonthYear(), intrathoracic: Bool = false) {
        self.name = name; self.procedureID = procedureID; self.side = side; self.date = date; self.intrathoracic = intrathoracic
        procedures = PatientSurgery.migrated(name: name, procedureID: procedureID, side: side)
    }

    init(procedures: [PlannedProcedure], date: PatientMonthYear = PatientMonthYear(), intrathoracic: Bool = false) {
        self.date = date; self.intrathoracic = intrathoracic
        setProcedures(procedures)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        procedureID = try? c.decodeIfPresent(String.self, forKey: .procedureID)
        side = try? c.decodeIfPresent(String.self, forKey: .side)
        date = (try? c.decodeIfPresent(PatientMonthYear.self, forKey: .date)) ?? PatientMonthYear()
        intrathoracic = (try? c.decodeIfPresent(Bool.self, forKey: .intrathoracic)) ?? false
        let items = (try? c.decodeIfPresent([PlannedProcedure].self, forKey: .procedures)) ?? nil
        procedures = items ?? PatientSurgery.migrated(name: name, procedureID: procedureID, side: side)
    }

    /// A save from before 1.7: its one name becomes one procedure, linked to the procedure list when the name is that
    /// procedure's own name ("Total knee arthroplasty"), keeping its side; any other wording stays as typed.
    private static func migrated(name: String, procedureID: String?, side: String?) -> [PlannedProcedure] {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return [] }
        if let id = procedureID, ProcedureCatalog.byID(id) != nil { return [PlannedProcedure(catalogID: id, name: n, side: side)] }
        let read = PlannedProcedure.parse(n)
        if read.count == 1, let p = read[0].catalog, read[0].detail.isEmpty, p.name.caseInsensitiveCompare(n) == .orderedSame {
            return [PlannedProcedure(p, side: side ?? read[0].side)]
        }
        return [PlannedProcedure(name: n, side: side)]
    }

    /// Replaces the procedures, keeps the older fields in step, and marks the operation cardiac or thoracic when a
    /// procedure from the list entered the chest (it is never unmarked here: the clinician may know better). 1.10 (Ben:
    /// "Past surgical history should only flag previous intrathoracic procedure when appropriate"): a transcatheter heart
    /// procedure (TAVR, TEER, a Watchman, a PVL plug) or peripheral ECMO is `cardiac` in the list but did not open the
    /// chest, so it no longer marks the operation; every open heart operation is Intrathoracic in the list.
    mutating func setProcedures(_ list: [PlannedProcedure]) {
        procedures = list
        name = list.map(\.text).filter { !$0.isEmpty }.joined(separator: " + ")
        procedureID = list.first?.catalogID
        side = list.first?.side
        if list.contains(where: { p in p.catalog?.incision == "Intrathoracic" }) { intrathoracic = true }
    }

    /// "Left total knee arthroplasty (03/2019)"; several procedures joined with " + ".
    var text: String {
        let what = procedures.map(\.text).filter { !$0.isEmpty }.joined(separator: " + ")
        return date.isEmpty || what.isEmpty ? what : what + " (" + date.text + ")"
    }
}

extension String {
    /// "Total knee" → "total knee", keeping acronyms ("CABG", "TAVR") as written.
    var lowercasedFirst: String {
        guard let f = first else { return self }
        let second = dropFirst().first
        if let s = second, s.isUppercase { return self }
        return f.lowercased() + dropFirst()
    }
}

/// Grades for chamber function and valve lesions, as the ASE tools name them. Trivial (trace) is for regurgitation
/// only (1.8.1, Ben): chamber function and stenosis are graded without it (`severities`).
enum EchoGrade: String, Codable, CaseIterable, Hashable {
    case normal, trivial, mild, moderate, severe
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The grades for regurgitation: none, trivial, mild, moderate, severe.
    static let regurgitation: [EchoGrade] = allCases
    /// The grades for chamber function and stenosis: without trivial.
    static let severities: [EchoGrade] = allCases.filter { $0 != .trivial }
}

/// One valve: regurgitation and stenosis grades (nil = not recorded; .normal = none) and any prosthesis or repair.
struct EchoValve: Codable, Hashable {
    var regurgitation: EchoGrade?
    var stenosis: EchoGrade?
    /// "Mechanical", "Bioprosthetic", "Repair or ring", "Transcatheter" (TAVR or TEER), or free text.
    var prosthesis = ""
    /// The prosthesis or repair in the user's words, optional, offered once a kind is chosen (1.10, Ben): "29 Magna".
    var prosthesisDetail = ""
    /// Free text for the valve (1.10, Ben: on every valve and chamber of the intraoperative exams).
    var notes = ""

    init(regurgitation: EchoGrade? = nil, stenosis: EchoGrade? = nil, prosthesis: String = "", prosthesisDetail: String = "", notes: String = "") {
        self.regurgitation = regurgitation; self.stenosis = stenosis; self.prosthesis = prosthesis
        self.prosthesisDetail = prosthesisDetail; self.notes = notes
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        regurgitation = try? c.decodeIfPresent(EchoGrade.self, forKey: .regurgitation)
        stenosis = try? c.decodeIfPresent(EchoGrade.self, forKey: .stenosis)
        prosthesis = (try? c.decodeIfPresent(String.self, forKey: .prosthesis)) ?? ""
        prosthesisDetail = (try? c.decodeIfPresent(String.self, forKey: .prosthesisDetail)) ?? ""
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
    }
    var isEmpty: Bool { regurgitation == nil && stenosis == nil && prosthesis.isEmpty && prosthesisDetail.isEmpty && notes.isEmpty }

    static let prostheses = ["Mechanical", "Bioprosthetic", "Repair or ring", "Transcatheter"]

    /// The kinds whose detail box shows (Ben: "When Mechanical, Bioprosthetic, Repair or ring are selected a free text
    /// box should appear"); a transcatheter valve has a model and size too, so it gets the box as well.
    static func takesDetail(_ kind: String) -> Bool { !kind.isEmpty }

    /// The prosthesis as the summary says it: a replacement by its abbreviation ("AVR bioprosthetic", "MVR mechanical"),
    /// a repair or a transcatheter valve by the valve ("Mitral repair or ring"), then the detail ("AVR bioprosthetic:
    /// 29 Magna"). Empty without a kind; a detail alone reads after the valve's name.
    func prosthesisPhrase(name: String, replacement: String) -> String? {
        let kind = prosthesis.trimmingCharacters(in: .whitespaces)
        let detail = prosthesisDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind.isEmpty { return detail.isEmpty ? nil : name + " prosthesis: " + detail }
        let head = (kind == "Mechanical" || kind == "Bioprosthetic") ? replacement + " " + kind.lowercased() : name + " " + kind.lowercasedFirst
        return detail.isEmpty ? head : head + ": " + detail
    }
}

/// A chamber's size on echo (1.10, Ben: "Normal size and dilated for the LV and RV").
enum EchoSize: String, Codable, CaseIterable, Hashable {
    case normal, dilated
    var label: String { self == .normal ? "Normal" : "Dilated" }
}

/// Echo findings in the order of a report: LV, RV, mitral, tricuspid, aortic valve, aorta, other.
struct PatientEcho: Codable, Hashable {
    var lv: EchoGrade?
    var lvef: Double?
    var rv: EchoGrade?
    /// 1.10 (Ben): the LV and RV size, normal or dilated, and free text for each chamber (shown in the intraoperative
    /// exams).
    var lvSize: EchoSize?
    var rvSize: EchoSize?
    var lvNotes = ""
    var rvNotes = ""
    var mitral = EchoValve()
    var tricuspid = EchoValve()
    var aortic = EchoValve()
    /// true: intact; false: see `aorta`.
    var aortaIntact: Bool?
    var aorta = ""
    var other = ""
    /// "TTE" or "TEE".
    var study: String?
    var date = PatientMonthYear()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lv = try? c.decodeIfPresent(EchoGrade.self, forKey: .lv)
        lvef = try? c.decodeIfPresent(Double.self, forKey: .lvef)
        rv = try? c.decodeIfPresent(EchoGrade.self, forKey: .rv)
        lvSize = try? c.decodeIfPresent(EchoSize.self, forKey: .lvSize)
        rvSize = try? c.decodeIfPresent(EchoSize.self, forKey: .rvSize)
        lvNotes = (try? c.decodeIfPresent(String.self, forKey: .lvNotes)) ?? ""
        rvNotes = (try? c.decodeIfPresent(String.self, forKey: .rvNotes)) ?? ""
        mitral = (try? c.decodeIfPresent(EchoValve.self, forKey: .mitral)) ?? EchoValve()
        tricuspid = (try? c.decodeIfPresent(EchoValve.self, forKey: .tricuspid)) ?? EchoValve()
        aortic = (try? c.decodeIfPresent(EchoValve.self, forKey: .aortic)) ?? EchoValve()
        aortaIntact = try? c.decodeIfPresent(Bool.self, forKey: .aortaIntact)
        aorta = (try? c.decodeIfPresent(String.self, forKey: .aorta)) ?? ""
        other = (try? c.decodeIfPresent(String.self, forKey: .other)) ?? ""
        study = try? c.decodeIfPresent(String.self, forKey: .study)
        date = (try? c.decodeIfPresent(PatientMonthYear.self, forKey: .date)) ?? PatientMonthYear()
    }

    var isEmpty: Bool { self == PatientEcho() }

    /// What Echo normal sets, shown under its button.
    static let normalCaption = "Sets LV and RV function normal, and no regurgitation or stenosis at the mitral, tricuspid and aortic valves. Change anything after."

    /// What Echo normal sets when the EF typed is below normal: everything but the LV.
    static func keepingLVCaption(ef: Double) -> String {
        "EF " + NumText.short(ef) + "% recorded: LV left as is. Sets RV function normal, and no regurgitation or stenosis at the mitral, tricuspid and aortic valves. Change anything after."
    }

    /// The caption for this study: the LV is left as it is when its EF is below normal.
    func normalCaption(keepingLV: Bool) -> String {
        if keepingLV, let ef = lvef { return PatientEcho.keepingLVCaption(ef: ef) }
        return PatientEcho.normalCaption
    }

    /// The lower limit of a normal LVEF when the reference data is not to hand: Lang 2015, Table 4, as the echo tools
    /// grade it (52% for men, 54% for women).
    static let lvefLowerLimit: [PatientSex: Double] = [.male: 52, .female: 54]

    /// The EF typed is below the normal range by the ASE grading the echo tools use (the reference data's LVEF row, or
    /// Lang 2015's limits without it): under 52% for a man, under 54% for a woman, and under 52%, below both, when the
    /// sex is not recorded.
    static func efBelowNormal(_ ef: Double?, measure: EchoMeasure? = nil, sex: PatientSex?) -> Bool {
        guard let ef, ef.isFinite else { return false }
        let s: EchoSex = sex == .female ? .female : .male
        if let m = measure, let g = EchoCalc.grade(m, s, ef) { return g >= 1 }
        return ef < (lvefLowerLimit[sex == .female ? .female : .male] ?? 52)
    }

    /// One tap for a normal study: LV and RV function normal, no regurgitation or stenosis at any valve. With
    /// `keepingLV` (an EF below normal was typed) the LV function and the EF are left as they are. The EF,
    /// prostheses, aorta, other findings, study and date are never changed.
    mutating func applyNormal(keepingLV: Bool = false) {
        if !keepingLV { lv = .normal }
        rv = .normal
        for kp in [\PatientEcho.mitral, \PatientEcho.tricuspid, \PatientEcho.aortic] {
            self[keyPath: kp].regurgitation = .normal
            self[keyPath: kp].stenosis = .normal
        }
    }

    /// The study shows what Echo normal sets.
    var isNormalPreset: Bool { isNormalPreset(keepingLV: false) }

    func isNormalPreset(keepingLV: Bool) -> Bool {
        (keepingLV || lv == .normal) && rv == .normal && noValveDisease
    }

    /// No regurgitation or stenosis recorded at all three valves (each graded none), and no prosthesis.
    var noValveDisease: Bool {
        [mitral, tricuspid, aortic].allSatisfy { $0.regurgitation == .normal && $0.stenosis == .normal && $0.prosthesis.isEmpty }
    }

    /// Function words for a chamber grade: "normal", "mildly reduced"…
    static func function(_ g: EchoGrade) -> String {
        switch g {
        case .normal, .trivial: return "normal"
        case .mild: return "mildly reduced"
        case .moderate: return "moderately reduced"
        case .severe: return "severely reduced"
        }
    }

    /// The findings as short phrases, in report order: "LV EF 35%, moderately reduced", "Severe AS", "Mitral repair".
    /// 1.10: a chamber's size after its function ("LV EF 35%, moderately reduced, dilated"; alone "LV dilated", "RV size
    /// normal"); a prosthesis with its detail ("AVR bioprosthetic: 29 Magna"); a section's free text after its findings
    /// ("LV: new anterior hypokinesis", "Mitral: …").
    var phrases: [String] {
        var out: [String] = []
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        func size(_ z: EchoSize?) -> String? { z.map { $0 == .dilated ? "dilated" : "normal size" } }
        if lv != nil || lvef != nil || lvSize != nil {
            var s = "LV"
            if let ef = lvef { s += " EF " + NumText.short(ef) + "%" }
            if let g = lv { s += (lvef == nil ? " function " : ", ") + PatientEcho.function(g) }
            if let z = lvSize {
                if lv == nil && lvef == nil { s += z == .dilated ? " dilated" : " size normal" } else { s += ", " + (size(z) ?? "") }
            }
            out.append(s)
        }
        if !clean(lvNotes).isEmpty { out.append("LV: " + clean(lvNotes)) }
        if rv != nil || rvSize != nil {
            var s = "RV"
            if let g = rv { s += " function " + PatientEcho.function(g) }
            if let z = rvSize {
                if rv == nil { s += z == .dilated ? " dilated" : " size normal" } else { s += ", " + (size(z) ?? "") }
            }
            out.append(s)
        }
        if !clean(rvNotes).isEmpty { out.append("RV: " + clean(rvNotes)) }
        if noValveDisease { out.append("No significant valve disease") }
        func valve(_ v: EchoValve, _ letter: String, _ name: String, _ replacement: String) {
            if let g = v.stenosis, g != .normal { out.append(g.label + " " + letter + "S") }
            if let g = v.regurgitation, g != .normal { out.append(g.label + " " + letter + "R") }
            if let p = v.prosthesisPhrase(name: name, replacement: replacement) { out.append(p) }
            if !clean(v.notes).isEmpty { out.append(name + ": " + clean(v.notes)) }
        }
        valve(mitral, "M", "Mitral", "MVR")
        valve(tricuspid, "T", "Tricuspid", "TVR")
        valve(aortic, "A", "Aortic", "AVR")
        if aortaIntact == true { out.append("Aorta intact") }
        if aortaIntact == false || !aorta.isEmpty { out.append(aorta.isEmpty ? "Aorta abnormal" : "Aorta: " + aorta) }
        if !other.isEmpty { out.append(other) }
        return out
    }

    /// The post-bypass exam started from the pre-bypass one (1.10): its findings, without the study and date.
    func copiedForPostBypass() -> PatientEcho {
        var e = self
        e.study = nil
        e.date = PatientMonthYear()
        return e
    }

    /// The intraoperative TEE in its exams (1.10, Ben's notes-img3): with a post-bypass exam, "Pre: …" and "Post: …"; with
    /// the pre-bypass exam alone, its findings as before 1.10 (a case without bypass has one exam, which needs no label).
    /// Only what is entered. The study word ("TEE:") the summary opens with is left out: the block's label says it.
    static func intraopParts(pre: PatientEcho, post: PatientEcho) -> [(label: String?, text: String)] {
        func body(_ e: PatientEcho) -> String {
            let s = e.summary
            return s.hasPrefix("TEE: ") ? String(s.dropFirst(5)) : s
        }
        if post.isEmpty { return pre.isEmpty ? [] : [(nil, body(pre))] }
        var out: [(label: String?, text: String)] = []
        if !pre.isEmpty { out.append(("Pre", body(pre))) }
        out.append(("Post", body(post)))
        return out
    }

    /// "TTE 03/2026: LV EF 55%, normal; moderate MR".
    var summary: String {
        let head = [study, date.isEmpty ? nil : date.text].compactMap { $0 }.joined(separator: " ")
        let body = phrases.joined(separator: "; ")
        if body.isEmpty { return head }
        return head.isEmpty ? body : head + ": " + body
    }
}

/// Left heart catheterization: dominance and the worst stenosis in each vessel.
struct PatientLHC: Codable, Hashable {
    /// "right", "left", "codominant".
    var dominance: String?
    /// Percent stenosis by vessel id ("lm", "lad", "lcx", "rca", "pda").
    var stenosis: [String: Double] = [:]
    var notes = ""
    var date = PatientMonthYear()
    /// The cath's result in a word (1.8.3, Ben): "non-obstructive" or "no-cad", one at a time. Nothing derives from it: it
    /// sets no CAD history and changes no score; the vessel percentages stay (a non-obstructive cath can list a 30% LAD).
    var result: String?
    static let resultOptions: [(id: String, label: String)] = [("non-obstructive", "Non-obstructive"), ("no-cad", "No CAD")]

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        result = try? c.decodeIfPresent(String.self, forKey: .result)
        dominance = try? c.decodeIfPresent(String.self, forKey: .dominance)
        stenosis = (try? c.decodeIfPresent([String: Double].self, forKey: .stenosis)) ?? [:]
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        date = (try? c.decodeIfPresent(PatientMonthYear.self, forKey: .date)) ?? PatientMonthYear()
    }

    static let vessels: [(id: String, label: String)] = [("lm", "LM"), ("lad", "LAD"), ("lcx", "LCx"), ("rca", "RCA"), ("pda", "PDA")]

    var isEmpty: Bool { self == PatientLHC() }

    /// Words in the notes that already say the cath's result.
    static let nonObstructiveWords = NoteRx(#"non[- ]?obstructive|no obstructive"#)
    static let noCADWords = NoteRx(#"\bno[- ]?cad\b|\bno coronary (?:artery )?disease|\b(?:normal|clean) coronar"#)

    /// "LHC 05/2026, right dominant: LAD 90%, RCA 70%; LM, LCx, PDA no significant disease". Non-obstructive reads first
    /// ("LHC 06/2026, right dominant: non-obstructive CAD", or "...: no CAD"; then the vessels and the notes), unless the
    /// notes say it already.
    var summary: String {
        var head = "LHC"
        if !date.isEmpty { head += " " + date.text }
        if let d = dominance { head += ", " + (d == "codominant" ? "codominant" : d + " dominant") }
        let named = PatientLHC.vessels.filter { stenosis[$0.id] != nil }
        let severe = named.filter { (stenosis[$0.id] ?? 0) >= 50 }.map { "\($0.label) \(NumText.short(stenosis[$0.id] ?? 0))%" }
        let mild = named.filter { (stenosis[$0.id] ?? 0) < 50 }
        var parts: [String] = []
        if result == "non-obstructive", PatientLHC.nonObstructiveWords.first(notes) == nil { parts.append("non-obstructive CAD") }
        if result == "no-cad", PatientLHC.noCADWords.first(notes) == nil { parts.append("no CAD") }
        if !severe.isEmpty { parts.append(severe.joined(separator: ", ")) }
        if !mild.isEmpty { parts.append(mild.map { "\($0.label) \(NumText.short(stenosis[$0.id] ?? 0))%" }.joined(separator: ", ")) }
        if !notes.isEmpty { parts.append(notes) }
        return parts.isEmpty ? head : head + ": " + parts.joined(separator: "; ")
    }
}

/// Right heart catheterization: the measured pressures (mmHg) and cardiac output (L/min).
struct PatientRHC: Codable, Hashable {
    var ra: Double?
    var pasp: Double?
    var padp: Double?
    /// Measured mean PA pressure, when given; otherwise it is estimated.
    var pam: Double?
    var pcwp: Double?
    var co: Double?
    var date = PatientMonthYear()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ra = try? c.decodeIfPresent(Double.self, forKey: .ra)
        pasp = try? c.decodeIfPresent(Double.self, forKey: .pasp)
        padp = try? c.decodeIfPresent(Double.self, forKey: .padp)
        pam = try? c.decodeIfPresent(Double.self, forKey: .pam)
        pcwp = try? c.decodeIfPresent(Double.self, forKey: .pcwp)
        co = try? c.decodeIfPresent(Double.self, forKey: .co)
        date = (try? c.decodeIfPresent(PatientMonthYear.self, forKey: .date)) ?? PatientMonthYear()
    }

    var isEmpty: Bool { self == PatientRHC() }
}

/// Ventilator settings, for a patient who arrives intubated or on a tracheostomy.
struct PatientVent: Codable, Hashable {
    /// "AC/VC", "AC/PC", "PRVC", "SIMV", "PSV", "APRV", or free text.
    var mode = ""
    var vt: Double?
    var rr: Double?
    var peep: Double?
    var fio2: Double?
    var ps: Double?

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? ""
        vt = try? c.decodeIfPresent(Double.self, forKey: .vt)
        rr = try? c.decodeIfPresent(Double.self, forKey: .rr)
        peep = try? c.decodeIfPresent(Double.self, forKey: .peep)
        fio2 = try? c.decodeIfPresent(Double.self, forKey: .fio2)
        ps = try? c.decodeIfPresent(Double.self, forKey: .ps)
    }

    var isEmpty: Bool { self == PatientVent() }
    static let modes = ["AC/VC", "AC/PC", "PRVC", "SIMV", "PSV", "APRV"]

    /// "AC/VC 450 × 16, PEEP 8, FiO₂ 40%".
    var text: String {
        var parts: [String] = []
        var head = mode
        if let v = vt { head += (head.isEmpty ? "" : " ") + NumText.short(v) + (rr.map { " × " + NumText.short($0) } ?? "") }
        else if let r = rr { head += (head.isEmpty ? "" : " ") + "rate " + NumText.short(r) }
        if !head.isEmpty { parts.append(head) }
        if let p = ps { parts.append("PS " + NumText.short(p)) }
        if let p = peep { parts.append("PEEP " + NumText.short(p)) }
        if let f = fio2 { parts.append("FiO₂ " + NumText.short(f) + "%") }
        return parts.joined(separator: ", ")
    }
}

/// Supplemental oxygen for a patient breathing on their own (or on a trach collar).
struct PatientOxygen: Codable, Hashable {
    /// "ra" room air, "nc" nasal cannula, "mask", "venturi", "nrb" non-rebreather, "hfnc" high-flow, "niv" CPAP or
    /// BiPAP, "trachCollar".
    var device: String?
    var flow: Double?
    var fio2: Double?

    init(device: String? = nil, flow: Double? = nil, fio2: Double? = nil) { self.device = device; self.flow = flow; self.fio2 = fio2 }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        device = try? c.decodeIfPresent(String.self, forKey: .device)
        flow = try? c.decodeIfPresent(Double.self, forKey: .flow)
        fio2 = try? c.decodeIfPresent(Double.self, forKey: .fio2)
    }

    static let devices: [(id: String, label: String)] = [("ra", "Room air"), ("nc", "Nasal cannula"), ("mask", "Face mask"), ("venturi", "Venturi"),
                                                         ("nrb", "Non-rebreather"), ("hfnc", "High-flow nasal"), ("niv", "CPAP or BiPAP"), ("trachCollar", "Trach collar")]
    /// Devices that take a flow, and those that take an FiO₂.
    static let flowDevices: Set<String> = ["nc", "mask", "nrb", "hfnc", "trachCollar", "venturi"]
    static let fio2Devices: Set<String> = ["venturi", "hfnc", "niv", "trachCollar"]

    var isEmpty: Bool { device == nil && flow == nil && fio2 == nil }

    /// "Nasal cannula 2 L/min", "High-flow nasal 40 L/min, FiO₂ 50%", "Room air".
    var text: String {
        guard let d = device else { return "" }
        let name = PatientOxygen.devices.first { $0.id == d }?.label ?? d
        var parts = [name + (flow.map { " " + NumText.short($0) + " L/min" } ?? "")]
        if let f = fio2 { parts.append("FiO₂ " + NumText.short(f) + "%") }
        return parts.joined(separator: ", ")
    }
}

/// ECG findings offered on the typeable list; anything else is typed in.
enum PatientECG {
    static let nsr = "Normal sinus rhythm"
    /// The atrial rhythms, of which one is recorded at a time. Ventricular pacing is not among them: it sits beside
    /// sinus rhythm (atrial-sensed ventricular pacing), atrial fibrillation or flutter (AHA/ACCF/HRS ECG statements,
    /// Mason 2007).
    static let rhythms: Set<String> = ["Normal sinus rhythm", "Sinus bradycardia", "Sinus tachycardia", "Atrial fibrillation", "Atrial flutter",
                                       "SVT", "Paced rhythm (atrial)", "Paced rhythm (AV)"]
    /// Blocks that "normal" sinus rhythm (1:1 conduction) cannot sit beside.
    static let notWithNSR: Set<String> = ["Complete heart block", "Mobitz II"]

    /// The findings after adding one: a rhythm replaces the rhythm recorded before it, and NSR and a high-grade
    /// block replace each other.
    static func adding(_ f: String, to ecg: [String]) -> [String] {
        guard !ecg.contains(f) else { return ecg }
        var out = rhythms.contains(f) ? ecg.filter { !rhythms.contains($0) } : ecg
        if f == nsr { out.removeAll { notWithNSR.contains($0) } }
        if notWithNSR.contains(f) { out.removeAll { $0 == nsr } }
        if f == nsr { out.insert(f, at: 0) } else { out.append(f) }
        return out
    }

    static let findings = [
        "Normal sinus rhythm", "Sinus bradycardia", "Sinus tachycardia", "Atrial fibrillation", "Atrial flutter", "SVT",
        "Paced rhythm (atrial)", "Paced rhythm (ventricular)", "Paced rhythm (AV)", "First-degree AV block", "Mobitz I (Wenckebach)",
        "Mobitz II", "Complete heart block", "Right bundle branch block", "Left bundle branch block", "Left anterior fascicular block",
        "Bifascicular block", "Left ventricular hypertrophy", "Right ventricular hypertrophy", "Q waves (old infarct)",
        "ST depression", "ST elevation", "T-wave inversion", "Prolonged QTc", "Short PR (pre-excitation)", "PVCs", "PACs",
        "Nonspecific ST-T changes", "Low voltage", "Right axis deviation", "Left axis deviation",
    ]
}

// MARK: - From the ASE tools

extension EchoGrade {
    init(_ g: ValveGrade) {
        switch g {
        case .mild: self = .mild
        case .moderate: self = .moderate
        case .severe: self = .severe
        }
    }

    /// The chamber tool's grade (EchoCalc.grade): -1 and 0 normal, 1–3 mild to severe; nil for "abnormal" with one
    /// cutoff, which names no severity.
    init?(chamber g: Int) {
        switch g {
        case -1, 0: self = .normal
        case 1: self = .mild
        case 2: self = .moderate
        case 3: self = .severe
        default: return nil
        }
    }
}

extension PatientEcho {
    /// A grade from the ASE valve severity tool, written into the matching valve.
    mutating func apply(_ lesion: ValveLesion, _ grade: ValveGrade) {
        let g = EchoGrade(grade)
        switch lesion {
        case .as_: aortic.stenosis = g
        case .ar: aortic.regurgitation = g
        case .mr: mitral.regurgitation = g
        case .ms: mitral.stenosis = g
        case .tr: tricuspid.regurgitation = g
        }
    }

    func grade(for lesion: ValveLesion) -> EchoGrade? {
        switch lesion {
        case .as_: return aortic.stenosis
        case .ar: return aortic.regurgitation
        case .mr: return mitral.regurgitation
        case .ms: return mitral.stenosis
        case .tr: return tricuspid.regurgitation
        }
    }
}

// MARK: - Device groups

extension PatientDevice {
    /// The handoff's Lines: the Foley goes with them (1.8.1); so do the 1.9 kinds (epicardial wires, pacemaker/ICD generator, AV fistula, hemodialysis catheter, chest tube), which before were entered as "other".
    static let lineKinds: Set<DeviceKind> = [.piv, .arterial, .cvc, .pac, .picc, .intraosseous, .foley, .epicardialWires, .cied, .avFistula, .dialysisCatheter, .chestTube, .other]
    static let supportKinds: Set<DeviceKind> = [.ecmoDrainage, .ecmoReturn, .lvad, .iabp, .impella, .protekDuo]
}

// MARK: - The cath's result, from a typed note (1.8.3)

extension PatientLHC {
    private static let nonObstructiveRx = NoteRx(#"\b(?:non[- ]?obstructive|no obstructive)\b"#)
    private static let noCADRx = NoteRx(#"\b(?:(?:angiographically |grossly )?normal coronar(?:y|ies)(?: arter(?:y|ies))?|clean coronar(?:y|ies)|no (?:cad|coronary (?:artery )?disease))\b"#)
    /// A coronary cath: "LHC" or "left heart cath" (coronary by themselves), "cath" (not a PA, arterial or central catheter),
    /// or a coronary angiogram, which is not a CT or MR one. A mesenteric, leg or cerebral angiogram is none of these.
    private static let lhcRx = NoteRx(#"\b(?:lhc|left heart cath(?:eterization|eterisation)?)\b"#)
    private static let cathRx = NoteRx(#"(?<!\bpa )(?<!\bart )(?<!arterial )(?<!venous )(?<!central )(?<!foley )(?<!urinary )(?<!\bpa )(?<!\bhd )(?<!dialysis )(?<!tunneled )(?<!tunnelled )(?<!swan )(?<!swan-ganz )(?<!\bpicc )(?<!\bcvc )(?<!suprapubic )(?<!epidural )(?<!\bpd )\bcath(?:eterization|eterisation)?\b|(?<!\bct )(?<!\bcta )(?<!\bccta )(?<!\bmr )(?<!\bmra )\bcoronary angiogra(?:m|phy)\b"#)
    private static let coronaryWordsRx = NoteRx(#"\b(?:cad|coronar(?:y|ies)|coronary artery disease)\b"#)
    /// Not coronary disease.
    private static let notCoronaryRx = NoteRx(#"\b(?:hcm|hocm|hypertrophic|cardiomyopath\w*|lvot)\b"#)
    /// "CAD" or "coronary (artery) disease" right after "non-obstructive".
    private static let cadAfterRx = NoteRx(#"^\s*(?:cad|coronary (?:artery )?disease)\b"#)
    static var patterns: [NoteRx] { [nonObstructiveRx, noCADRx, lhcRx, cathRx, coronaryWordsRx, notCoronaryRx, cadAfterRx] }

    /// The cath's result as typed, when a cath word is in the same sentence (without one it may be a CT result, so nothing
    /// is read): "LHC non-obstructive", "cath: nonobstructive CAD", "non-obstructive coronary disease on cath" are
    /// "non-obstructive"; "normal coronaries", "clean coronaries", "no CAD" on a cath are "no-cad". A cath that is not
    /// "LHC" or "left heart cath" also needs a CAD or coronary word ("cath: non-obstructive" alone is not read), and a
    /// sentence about HCM or a cardiomyopathy is not read. "No significant CAD" says neither; a sentence that says both is
    /// not read. `cadWords`: the "CAD" right after "non-obstructive", which belongs to the result.
    static func readResult(_ c: String) -> (result: String, phrase: NSRange, cath: NSRange, cadWords: NSRange?)? {
        let ns = c as NSString
        guard notCoronaryRx.first(c) == nil else { return nil }
        let lhc = lhcRx.first(c)
        guard let k = lhc ?? cathRx.first(c) else { return nil }
        let non = nonObstructiveRx.first(c), none = noCADRx.first(c)
        if let m = non, none == nil {
            guard lhc != nil || coronaryWordsRx.first(c) != nil else { return nil }
            let end = m.range.location + m.range.length
            let after = ns.substring(from: end)
            let cad = cadAfterRx.first(after).map { NSRange(location: end + $0.range.location, length: $0.range.length) }
            return ("non-obstructive", m.range, k.range, cad)
        }
        if let m = none, non == nil { return ("no-cad", m.range, k.range, nil) }
        return nil
    }
}
