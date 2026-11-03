import Foundation

// MARK: - Past surgical history from a typed note (1.8.3, Ben)
//
// "In typed history, past surgical history should also be populated if entered." A note (or the quick-add bar) that
// gives a surgical history fills Past surgical history, one entry per operation, with its date when the note gives one:
//
//   - a section: "PSH: ...", "PSHx", "Past surgical history: ...", "Surgical history: ..." (items split at commas and
//     semicolons, and at "and" after a date; a header with nothing after it takes the bulleted lines that follow);
//   - "s/p ...", "status post ...", "h/o ...", "hx of ...", "history of ...", "prior ...", "previous ..." before an
//     operation (and the operations listed after it: "s/p CABG 2019, appendectomy 2010").
//
// "A + B + C 06/2025" is one operation with three procedures. Each procedure is matched to the procedure list when it
// can be; otherwise it stays as typed. An anesthetic remark ("under GA") is left for the anesthesia-history details.
// The planned procedure ("Procedure: ...", "scheduled for ...", "presents for ...") is never past surgery.
enum PastSurgeryNote {
    struct Operation: Hashable {
        /// The operation as written, without its date and any anesthetic remark ("CABG ×3").
        var text: String
        var date: PatientMonthYear
        /// An anesthetic remark that went with it ("under GA"), kept for the anesthesia-history details.
        var aside: String
        /// Where the item was read in the sentence.
        var range: NSRange
    }

    /// Carried from one sentence to the next: a "PSH:" header with bulleted lines after it.
    struct State {
        var open = false
        /// The header had nothing after it, so the lines that follow are its items.
        var bodyEmpty = false
    }

    struct Reading {
        var operations: [Operation] = []
    }

    // MARK: Patterns

    static let headerRx = NoteRx(#"\b(?:(?:psh|pshx)\b\s*[:\-–]?|(?:past surgical (?:history|hx)|surgical (?:history|hx)|prior surgeries|previous surgeries|past surgeries)\s*[:\-–])\s*"#)
    static let leadRx = NoteRx(#"\b(?:s/p|status post|h/o|hx of|history of|prior|previous)\s+(?:an?\s+|the\s+)?"#)
    static let bulletRx = NoteRx(#"^\s*(?:[-•*–·]|\d+[.)])\s*"#)
    /// Another section's header at the start of a line closes the surgical history.
    static let otherHeaderRx = NoteRx(#"^\s*[A-Za-z][A-Za-z/&\s]{1,28}:"#)
    static let andAfterDateRx = NoteRx(#"((?:19|20)\d\d|\d{1,2}/\d\d)\)?\s+(?:and|&)\s+"#)
    /// What ends an item that runs on into the rest of the sentence ("s/p CABG 2019 now presenting for ...").
    static let cutRx = NoteRx(#"\s+(?:presents?|presenting|presented|now|here|who|scheduled|booked|planned|admitted|but|which|that|due to|secondary to|c/b|complicated|undergoing|to have|will)\b"#)
    static let plannedRx = NoteRx(#"\b(?:scheduled|booked|planned|presents?|presenting|presented|here for|admitted|undergoing|candidate|now for|to have|will)\b"#)
    static let asideRx = NoteRx(#"\s+(?:under|with|w/|using|via|had|received)\s+(?:general|ga\b|spinal|epidural|mac\b|local|regional|sedation|an(?:a)?esthesia|nerve block)[^,;]*$"#)
    static let commentaryRx = NoteRx(#"^(?:no|none|nil|denies|denied|negative|neg|n/a|na|noncontributory|non-contributory|unremarkable|noted|see|per|otherwise|unknown|unsure|not|ga|mac)\b|\b(?:complications?|an(?:a)?esthe\w*|difficult (?:airway|intubation)|ponv|malignant hyperthermia|uneventful|tolerated|problems?|issues?|reactions?)\b"#)
    static let surgicalRx = NoteRx(#"(?:ectomy|otomy|ostomy|plasty|oscopy|pexy|orrhaphy|desis)\b|\b(?:repair|surgery|resection|replacement|bypass|fusion|transplant\w*|fixation|orif|graft(?:ing)?|implant\w*|excision|c-?section|cesarean|ligation|amputation|biopsy|decompression|reconstruction|ablation|tka|tha|tkr|thr)\b"#)
    static let chestRx = NoteRx(#"\b(?:thoracotomy|sternotomy|vats|thoracoscopic|lobectomy|pneumonectomy|segmentectomy|esophagectomy|open[- ]heart|cardiac surgery|heart surgery)\b"#)
    static let monthYearRx = NoteRx(#"(?:\bin\s+|\(\s*|\b(?:on|dated|at)\s+)?\b((?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?,?\s+(?:19|20)\d\d)\b\s*\)?"#)
    static let numericRx = NoteRx(#"(?:\bin\s+|\(\s*)?(?<![\w/.\-])((?:0?[1-9]|1[0-2])\s*(?:[/.\-]\s*(?:19|20)\d\d|/\s*\d\d))(?![\d/])\s*\)?"#)
    static let yearRx = NoteRx(#"(?:\bin\s+|\(\s*)?(?<![\w/.\-])((?:19|20)\d\d)(?![\w/])\s*\)?"#)

    static let cardiacWordsRx = NoteRx(PatientNote.cardiacOpWords)

    static var allPatterns: [NoteRx] {
        [cardiacWordsRx, headerRx, leadRx, bulletRx, otherHeaderRx, andAfterDateRx, cutRx, plannedRx, asideRx, commentaryRx, surgicalRx, chestRx, monthYearRx, numericRx, yearRx]
    }

    // MARK: Reading a sentence

    /// The operations a sentence gives. `state` carries a header across lines; `skip` holds the stretches already read as
    /// something else (Previous cardiac surgery), which are not read again.
    static func read(_ c: String, state: inout State, skip: [NSRange] = []) -> Reading {
        let ns = c as NSString
        var out = Reading()
        func clear(_ r: NSRange) -> Bool { !skip.contains { NSIntersectionRange($0, r).length > 0 } }

        // Lines after a header.
        if state.open {
            if let b = bulletRx.first(c) {
                let start = b.range.location + b.range.length
                let ops = items(ns, NSRange(location: start, length: ns.length - start), strict: false)
                out.operations = ops.filter { clear($0.range) }
                state.open = true
                return out
            }
            let numberOnly = c.trimmingCharacters(in: .whitespaces).allSatisfy { $0.isNumber || $0 == "." || $0 == ")" }
            if numberOnly { return out }
            if state.bodyEmpty, otherHeaderRx.first(c) == nil, headerRx.first(c) == nil {
                let ops = items(ns, NSRange(location: 0, length: ns.length), strict: true)
                if !ops.isEmpty {
                    out.operations = ops.filter { clear($0.range) }
                    return out
                }
            }
            state.open = false
        }

        var sectionStart = ns.length
        if let h = headerRx.first(c) {
            sectionStart = h.range.location
            let start = h.range.location + h.range.length
            let body = NSRange(location: start, length: ns.length - start)
            let text = ns.substring(with: body).trimmingCharacters(in: .whitespacesAndNewlines)
            state.open = true
            state.bodyEmpty = text.isEmpty
            out.operations += items(ns, body, strict: false).filter { clear($0.range) }
        }

        // "s/p ...", "h/o ...": the operation after it, and the operations listed after that.
        var covered = NSRange(location: 0, length: 0)
        for m in leadRx.all(c) where m.range.location < sectionStart && m.range.location >= covered.location + covered.length {
            if PatientNote.negated(c, at: m.range.location) || PatientNote.familyContext(c, at: m.range.location) { continue }
            let start = m.range.location + m.range.length
            let end = min(sectionStart, ns.length)
            guard start < end else { continue }
            let found = leadItems(ns, NSRange(location: start, length: end - start))
            if found.isEmpty { continue }
            out.operations += found.filter { clear($0.range) }
            if let last = found.last { covered = NSRange(location: m.range.location, length: last.range.location + last.range.length - m.range.location) }
        }
        return out
    }

    /// The operation right after a lead, then the items after it while each one is an operation too.
    private static func leadItems(_ ns: NSString, _ range: NSRange) -> [Operation] {
        var out: [Operation] = []
        for (i, p) in split(ns, range).enumerated() {
            var stopped = false
            let op = operation(ns, p, strict: true, stopped: &stopped)
            if let op {
                if !op.text.isEmpty {
                    out.append(op)
                } else if var last = out.popLast(), last.date.isEmpty {
                    // A bare date after a comma belongs to the operation before it.
                    last.date = op.date
                    last.range = NSUnionRange(last.range, op.range)
                    out.append(last)
                } else {
                    break
                }
            } else if i == 0 || out.isEmpty {
                return []
            } else {
                break
            }
            if stopped { break }
        }
        return out
    }

    /// The items of a section body.
    private static func items(_ ns: NSString, _ range: NSRange, strict: Bool) -> [Operation] {
        var out: [Operation] = []
        for p in split(ns, range) {
            var stopped = false
            if let op = operation(ns, p, strict: strict, stopped: &stopped) {
                if !op.text.isEmpty {
                    out.append(op)
                } else if var last = out.popLast(), last.date.isEmpty {
                    // A date on its own ("CABG x3, 2019").
                    last.date = op.date
                    last.range = NSUnionRange(last.range, op.range)
                    out.append(last)
                }
            }
            if stopped { break }
        }
        return out
    }

    /// Splits at commas, semicolons and line breaks outside brackets, and at "and" after a date.
    private static func split(_ ns: NSString, _ range: NSRange) -> [NSRange] {
        var parts: [NSRange] = []
        var depth = 0
        var i = range.location
        let end = range.location + range.length
        var start = i
        while i < end {
            let ch = ns.character(at: i)
            if ch == 40 || ch == 91 { depth += 1 }
            if (ch == 41 || ch == 93) && depth > 0 { depth -= 1 }
            if depth == 0 && (ch == 44 || ch == 59 || ch == 10) {
                if i > start { parts.append(NSRange(location: start, length: i - start)) }
                start = i + 1
            }
            i += 1
        }
        if end > start { parts.append(NSRange(location: start, length: end - start)) }
        var out: [NSRange] = []
        for r in parts {
            var s = r.location
            let piece = ns.substring(with: r)
            for m in andAfterDateRx.all(piece) {
                let g = m.range(at: 1)
                let dateEnd = r.location + g.location + g.length
                let next = r.location + m.range.location + m.range.length
                if dateEnd > s { out.append(NSRange(location: s, length: dateEnd - s)) }
                s = next
            }
            if r.location + r.length > s { out.append(NSRange(location: s, length: r.location + r.length - s)) }
        }
        return out
    }

    /// One item as an operation; nil when it is not one. An item that is only a date has empty text. `stopped` is set when
    /// the item runs on into the rest of the sentence ("... now presenting for ..."): nothing after it is read.
    private static func operation(_ ns: NSString, _ range: NSRange, strict: Bool, stopped: inout Bool) -> Operation? {
        var t = ns.substring(with: range)
        if let b = bulletRx.first(t) { t = (t as NSString).substring(from: b.range.length) }
        if let l = leadRx.first(t), l.range.location == 0 { t = (t as NSString).substring(from: l.range.length) }
        if let cut = cutRx.first(t), cut.range.location > 0 {
            t = (t as NSString).substring(to: cut.range.location)
            stopped = true
        } else if plannedRx.first(t) != nil {
            stopped = true
            return nil
        }
        t = tidy(t)
        guard !t.isEmpty else { return nil }
        var aside = ""
        if let a = asideRx.first(t) {
            aside = tidy((t as NSString).substring(from: a.range.location))
            t = tidy((t as NSString).substring(to: a.range.location))
        }
        let (rest, date) = extractDate(t)
        t = rest
        if t.isEmpty { return date.isEmpty ? nil : Operation(text: "", date: date, aside: aside, range: range) }
        if commentaryRx.first(t) != nil { return nil }
        if strict {
            guard isOperation(t) else { return nil }
        } else {
            guard t.filter(\.isLetter).count >= 3 else { return nil }
        }
        return Operation(text: t, date: date, aside: aside, range: range)
    }

    private static func tidy(_ s: String) -> String {
        var t = s.trimmingCharacters(in: CharacterSet(charactersIn: " \t:;,.-–•*").union(.whitespacesAndNewlines))
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        for tail in [" in", " on", " from", " at", " (", " of"] where t.lowercased().hasSuffix(tail) { t = String(t.dropLast(tail.count)) }
        if t.hasSuffix("(") { t = String(t.dropLast()) }
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " \t:;,.-–").union(.whitespacesAndNewlines))
    }

    /// The text without its (first) date, and the date: "TEVAR 08/2022", "CABG x3 in 2019", "(June 2015)".
    static func extractDate(_ text: String) -> (String, PatientMonthYear) {
        for rx in [monthYearRx, numericRx, yearRx] {
            guard let m = rx.first(text), m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { continue }
            let ns = text as NSString
            guard let d = PatientMonthYear.parse(ns.substring(with: m.range(at: 1))) else { continue }
            let rest = ns.replacingCharacters(in: m.range, with: " ")
            return (tidy(rest), d)
        }
        return (text, PatientMonthYear())
    }

    /// A recognized operation: in the procedure list, or named like one.
    static func isOperation(_ t: String) -> Bool {
        PlannedProcedure.parse(t).contains { $0.catalogID != nil } || surgicalRx.first(t) != nil || chestRx.first(t) != nil
    }

    // MARK: Entries

    private static let modifiers: Set<String> = ["mechanical", "bioprosthetic", "tissue", "redo", "repeat", "mini", "hybrid", "emergent", "urgent", "elective",
                                                 "staged", "on-pump", "off-pump", "minimally", "invasive", "total", "partial"]
    /// Words that an approach in a procedure's name must be backed by in the note ("appendectomy" is not "laparoscopic").
    private static let approaches = ["laparoscopic", "robotic", "minimally", "thoracoscopic", "arthroscopic", "endoscopic"]
    private static let approachStems = ["lap", "robot", "scop", "vats", "minimal", "mini", "thoracosc", "tecab", "midcab"]

    /// The procedures of one piece of an operation, from the procedure list when it knows them, else as typed. A procedure
    /// whose list name adds an approach the note did not write stays as typed.
    private static func procedures(for piece: String) -> [PlannedProcedure] {
        let p = piece.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return [] }
        var parsed = PlannedProcedure.parse(p)
        let lower = p.lowercased()
        for item in parsed {
            guard let c = item.catalog else { continue }
            let n = c.name.lowercased()
            if approaches.contains(where: { n.contains($0) }), !approachStems.contains(where: { lower.contains($0) }) {
                return [typed(p)]
            }
        }
        // "mechanical MVR": the modifier is a detail of the procedure after it, not a procedure.
        if parsed.count >= 2, parsed[0].catalogID == nil {
            let words = parsed[0].name.lowercased().split(separator: " ").map(String.init)
            if !words.isEmpty, words.allSatisfy({ modifiers.contains($0) }) {
                let lead = parsed[0].name
                parsed.removeFirst()
                parsed[0].detail = ([lead] + (parsed[0].detail.isEmpty ? [] : [parsed[0].detail])).joined(separator: " ")
            }
        }
        return parsed.map { $0.catalogID == nil ? typed($0.name, detail: $0.detail, side: $0.side) : $0 }
    }

    private static func typed(_ name: String, detail: String = "", side: String? = nil) -> PlannedProcedure {
        var n = name
        if let f = n.first, f.isLowercase, n.dropFirst().first.map({ !$0.isUppercase }) ?? true { n = f.uppercased() + n.dropFirst() }
        return PlannedProcedure(name: n, side: side, detail: detail)
    }

    /// The entry for an operation: its procedures ("A + B" are two), the date, and the chest flag.
    static func surgery(_ text: String, _ date: PatientMonthYear) -> PatientSurgery {
        let pieces = text.replacingOccurrences(of: " plus ", with: " + ").components(separatedBy: "+")
        var list: [PlannedProcedure] = []
        for piece in pieces { list += procedures(for: piece) }
        if list.isEmpty { list = [typed(text)] }
        var s = PatientSurgery(procedures: list, date: date)
        if chestRx.first(text) != nil { s.intrathoracic = true }
        return s
    }

    /// Whether a cardiac operation (for the cardiac page's Previous cardiac surgery).
    static func isCardiac(_ s: PatientSurgery) -> Bool {
        s.procedures.contains { $0.catalog?.cardiac ?? false } || cardiacWordsRx.first(s.name) != nil
    }

    // MARK: Matching what the record has

    private static func ids(_ s: PatientSurgery) -> Set<String> {
        var out = Set(s.procedures.compactMap(\.catalogID))
        if out.isEmpty { out = Set(ProcedureCatalog.parse(s.name).map(\.procedure.id)) }
        return out
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The dates are compatible: one is empty, or the years agree and the months agree or one is missing.
    private static func compatible(_ a: PatientMonthYear, _ b: PatientMonthYear) -> Bool {
        if a.isEmpty || b.isEmpty { return true }
        guard a.year == b.year else { return false }
        return a.month == nil || b.month == nil || a.month == b.month
    }

    /// The same operation: the same procedures from the list (with no different side), or the same words, on dates that
    /// do not differ.
    static func same(_ a: PatientSurgery, _ b: PatientSurgery) -> Bool {
        guard compatible(a.date, b.date) else { return false }
        let x = ids(a), y = ids(b)
        if !x.isEmpty, !y.isEmpty {
            guard x == y else { return false }
            let sa = a.procedures.compactMap(\.side), sb = b.procedures.compactMap(\.side)
            return sa.isEmpty || sb.isEmpty || Set(sa) == Set(sb)
        }
        let na = normalized(a.name), nb = normalized(b.name)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        return na == nb || na.contains(nb) || nb.contains(na)
    }

    static func index(of s: PatientSurgery, in r: PatientRecord) -> Int? {
        r.surgeries.firstIndex { same($0, s) }
    }

    static func isRecorded(_ text: String, _ date: PatientMonthYear, in r: PatientRecord) -> Bool {
        index(of: surgery(text, date), in: r) != nil
    }

    /// Adds the operation to Past surgical history unless it is there. A cardiac operation also becomes the cardiac page's
    /// Previous cardiac surgery when that is empty. Returns the entry's index.
    @discardableResult
    static func add(_ text: String, _ date: PatientMonthYear, cardiac: Bool = false, to r: inout PatientRecord) -> Int {
        var s = surgery(text, date)
        if cardiac { s.intrathoracic = true }
        let i: Int
        if let found = index(of: s, in: r) {
            i = found
            if cardiac { r.surgeries[i].intrathoracic = true }
        } else {
            r.surgeries.append(s)
            i = r.surgeries.count - 1
        }
        if (cardiac || isCardiac(r.surgeries[i])), r.hx.cardiacSurgeryID == nil { r.hx.cardiacSurgeryID = r.surgeries[i].id }
        return i
    }

    /// Previous cardiac surgery as the note reader gives it ("CABG x3 2015; mechanical MVR"): each operation its own entry.
    static func addCardiac(_ text: String, to r: inout PatientRecord) {
        for part in text.components(separatedBy: "; ") {
            let (rest, date) = extractDate(tidy(part))
            let t = rest.isEmpty ? tidy(part) : rest
            guard !t.isEmpty else { continue }
            add(t, date, cardiac: true, to: &r)
        }
    }

    static func cardiacRecorded(_ text: String, in r: PatientRecord) -> Bool {
        let parts = text.components(separatedBy: "; ")
        for part in parts {
            let (rest, date) = extractDate(tidy(part))
            let t = rest.isEmpty ? tidy(part) : rest
            if t.isEmpty { continue }
            if !isRecorded(t, date, in: r) { return false }
        }
        return !parts.isEmpty
    }
}
