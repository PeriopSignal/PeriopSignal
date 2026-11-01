import Foundation

// MARK: - Quick add
//
// One line, typed or pasted the way a clinician presents a patient ("68M for lap chole, HTN DM2 on insulin, K 5.4 Cr
// 1.6, A-line L radial 20G"), read on the phone into findings to confirm before they are filed. The core is the note
// reader (PatientNote.read); around it this file reads the shorthand a one-liner uses and a note does not: vital signs
// in a row, labs by name and the EMR fishbones, the blood gas, blood products, drips with a bare rate, the planned
// procedure and the intraoperative airway. It routes by tab: on the Intraoperative tab labs become a new intraoperative
// set, drips go to the case's infusions, lines are marked placed in the OR and the airway goes to the airway course; on
// the Preoperative tab the same words go where the note reader puts them.
//
// Safety: a value is read only when the line states it and it is plausible (the LabTest ranges and the note reader's
// vital-sign ranges, with the gas and the panels checked against themselves); what could mean two things is left
// unread. Identifiers are masked before anything is read, so nothing is filed from them. The note reader's inferences
// (an airway from oxygen or a ventilator, diabetes from insulin, sleep apnea from CPAP) are left out: the bar files only
// what the line says. Nothing leaves the phone.

enum QuickAddTab: String, CaseIterable, Hashable {
    case preop, intraop
}

/// What a line gives: findings to file, and what is shown but never filed.
struct QuickAddReading: Hashable {
    var findings: [PatientNoteFinding] = []
    /// Recognized but not filed from this tab, with why ("Vital signs · on the Preop tab").
    var skipped: [String] = []
    /// Kinds of identifier found ("a record number"): masked before reading, so nothing is filed from them.
    var identifiers: [String] = []
    /// Ambiguous abbreviations read by their usual meaning or the user's choice (one the context settled is not asked),
    /// after the reader's own questions (QuickAdd.roomAirQuestion), which add nothing until answered.
    var ambiguous: [AmbiguousAbbreviation] = []
    var unknown: [UnknownAbbreviation] = []
    /// What nothing was read from.
    var unread = ""

    var isEmpty: Bool {
        findings.isEmpty && skipped.isEmpty && identifiers.isEmpty && ambiguous.isEmpty && unknown.isEmpty && unread.isEmpty
    }
}

/// One preview chip: a finding (or both halves of a blood pressure), where it goes and what it writes.
struct QuickAddChip: Identifiable, Hashable {
    /// The finding ids and the value: stable while the same value is typed.
    var id: String
    var findings: [PatientNoteFinding]
    /// "History", "Labs", "Intraop".
    var destination: String
    /// "Hypertension, well controlled", "K 5.4 H", "PRBC +2".
    var value: String
    var status: PatientNoteStatus
    var note: String?

    var text: String { destination + " · " + value }
    var canAdd: Bool { status.canAdd }
    /// "replaces 1.1", "already recorded", or why it cannot be added.
    var statusText: String? {
        switch status {
        case .new: return nil
        case .recorded: return "already recorded"
        case .replaces(let old): return "replaces " + old
        case .conflicts(let why): return why
        }
    }
}

/// The line as it is read: what each reader takes is masked with spaces, lengths kept, so every range stays put.
private struct QuickScan {
    let original: String
    private(set) var text: String
    /// Ranges a reader read for certain: an abbreviation inside one is not asked about ("7.5 ETT" is a tube).
    var certain: [NSRange] = []

    init(_ s: String) {
        original = s
        text = s
    }

    mutating func mask(_ r: NSRange) {
        let ns = text as NSString
        guard r.location != NSNotFound, r.location >= 0, r.length > 0, r.location + r.length <= ns.length else { return }
        text = ns.replacingCharacters(in: r, with: String(repeating: " ", count: r.length))
    }
}

/// What the readers found.
private struct QuickOut {
    var findings: [PatientNoteFinding] = []
    var skipped: [String] = []
    /// Questions asked the way an ambiguous abbreviation is (SpO₂ without room air written).
    var questions: [AmbiguousAbbreviation] = []
    /// Lab keys already read: the first value of a test wins.
    var labs: Set<String> = []

    mutating func add(_ f: PatientNoteFinding) {
        guard !findings.contains(where: { $0.id == f.id }) else { return }
        findings.append(f)
    }

    mutating func skip(_ s: String) {
        if !skipped.contains(s) { skipped.append(s) }
    }
}

private struct QuickContext {
    var tab: QuickAddTab
    var record: PatientRecord
    var now: Date
    var abbreviations: [AbbreviationMatch]
    var choices: [String: String]
    /// The intraoperative lab set this line's labs go into.
    var setID: UUID

    func abbreviation(at r: NSRange) -> AbbreviationMatch? {
        abbreviations.first { NSIntersectionRange($0.range, r).length > 0 }
    }

    /// Whether an ambiguous abbreviation at the range is read as this meaning (true where there is none). With
    /// `confirmed`, the context or the user must have picked it: its usual meaning alone is not enough ("levo").
    func means(_ id: String, at r: NSRange, confirmed: Bool = false) -> Bool {
        guard let a = abbreviation(at: r), a.isAmbiguous else { return !confirmed }
        guard a.meaning?.id == id else { return false }
        return !confirmed || a.fromContext || choices[a.choiceKey ?? ""] != nil
    }
}

enum QuickAdd {
    /// The review group for what goes to the case itself: intraoperative labs, blood, drips and the airway course.
    static let intraop = "Intraoperative"
    static let sections = PatientNote.sections + [intraop]

    /// Longer than a line (over about 200 characters, or several lines): the full review reads it instead.
    static func isLong(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: { $0.isNewline }).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return text.count > 200 || lines.count > 1
    }

    static func placeholder(_ tab: QuickAddTab) -> String {
        tab == .intraop ? "2 PRBC, ABG 7.29/41/168, epi 0.05" : "68M for lap chole, HTN, K 5.4, A-line"
    }

    // MARK: Reading

    /// The findings a line gives on a tab. `record` is the patient as it stands (for the intraoperative airway and
    /// the blood totals); `abbreviations` and `choices` are the user's own and the meanings chosen, as for a note.
    static func read(_ line: String, record: PatientRecord, tab: QuickAddTab, now: Date = Date(),
                     abbreviations user: [String: String] = [:], choices: [String: String] = [:]) -> QuickAddReading {
        let one = line.components(separatedBy: .newlines).joined(separator: " ")
        var s = QuickScan(one)
        var reading = QuickAddReading()
        reading.identifiers = PatientNote.identifiers(one)
        for r in identifierRanges(one) { s.mask(r) }
        let base = s.text
        let abbreviations = MedAbbreviations.scan(base, user: user, choices: choices)
        let c = QuickContext(tab: tab, record: record, now: now, abbreviations: abbreviations, choices: choices, setID: UUID())
        var out = QuickOut()

        if tab == .intraop {
            readAirway(&s, c, &out)
            // "A-line pre-induction" on the Intraoperative tab says when it went in, not that it is still to come.
            for m in inductionTiming.all(s.text) { s.mask(m.range) }
        }
        readFishbone(&s, c, &out)
        readGas(&s, c, &out)
        readCBC(&s, c, &out)
        readVitals(&s, c, &out)
        if tab == .intraop { readBlood(&s, c, &out) }
        readLabs(&s, c, &out)
        readDrips(&s, c, &out)
        readProcedure(&s, c, &out)

        // The note reader on what is left.
        let note = PatientNote.read(s.text, now: now, abbreviations: user, choices: choices)
        let mine = Set(out.findings.map(\.id))
        for f in note.findings where !mine.contains(f.id) && !inferred(f) { route(f, one, c, &out) }
        readPlan(base, c, &out)

        var rank: [String: Int] = [:]
        for (i, sec) in sections.enumerated() { rank[sec] = i }
        reading.findings = Array(out.findings.enumerated()).sorted { a, b in
            let ra = rank[a.element.section] ?? 99
            let rb = rank[b.element.section] ?? 99
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        reading.skipped = out.skipped
        reading.unknown = note.unknown
        let certain = s.certain
        let asked = abbreviations.filter { m in
            m.isAmbiguous && !certain.contains(where: { NSIntersectionRange($0, m.range).length > 0 })
                && (!m.fromContext || choices[m.choiceKey ?? ""] != nil)
        }
        reading.ambiguous = out.questions + MedAbbreviations.ambiguous(asked, in: base)
        reading.unread = asTyped([note.other, note.previous].filter { !$0.isEmpty }.joined(separator: "; "), s.text,
                                 user: user, choices: choices)
        return reading
    }

    /// Every pattern, for the test that each one compiles.
    static var allPatterns: [NoteRx] {
        var out = [recordTail, dateTail, nameTail, surnameTail, titleRx, roomAirWords, pieceNegation, vitaminBefore, fibBefore, bmpRx, cbcRx,
                   gasRx, gasWord, venousGas, gasLabel, bpRx, notBPBefore, vHR, vSpO2, vPercent, vRoomAir, vOxygen, vRR, vTemp, vBareTemp, vBare,
                   bloodBefore, bloodAfter, cellSaverAfter, cellSaverBefore, notGiven, offAfter, plannedLead, lineLead, lastFor, urgencyWord,
                   pastWords, detailWord, tubeRx, dltRx, gradeRx, gradeNotBefore, airwayContext, maskGradeRx, maskEaseRx, intubationEaseRx,
                   attemptsRx, inductionTiming]
        out += labAliases.map(\.rx) + drips.map(\.rx) + airwayDevices.map { $0.0 }
        return out
    }

    // MARK: Identifiers

    /// Where the identifiers PatientNote.identifiers warns about sit in the line, with the value after a cue ("MRN
    /// 12345", "DOB 1/2/1950", "name is Jane Doe"), so the reading can mask them.
    static func identifierRanges(_ text: String) -> [NSRange] {
        let ns = text as NSString
        var out: [NSRange] = []
        for (kind, rx) in PatientNote.identifierRules {
            for m in rx.all(text) {
                var r = m.range
                let matched = ns.substring(with: r)
                let tail: NoteRx?
                switch kind {
                case "a record number": tail = matched.allSatisfy(\.isNumber) ? nil : recordTail
                case "a date": tail = matched.first?.isNumber == true ? nil : dateTail
                case "a name": tail = titleRx.first(matched) != nil ? surnameTail : nameTail
                default: tail = nil
                }
                if let tail, let t = tail.first(ns.substring(from: r.location + r.length)) {
                    r.length += t.range.length
                }
                out.append(r)
            }
        }
        return out
    }

    private static let recordTail = NoteRx(#"^[\s:#=.]*[A-Za-z]{0,3}[-\d]{3,}"#)
    private static let dateTail = NoteRx(#"^[\s:=]*(?:\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}|\d{4}-\d{1,2}-\d{1,2}|[A-Za-z]{3,9}\.?\s+\d{1,2},?\s+\d{2,4})"#)
    /// After "name is": a word, and up to two more that are capitalized (not an abbreviation such as "HTN").
    private static let nameTail = NoteRx(#"^[\s:=]*[A-Za-z][A-Za-z'’-]*(?:\s+[A-Z][a-z'’-]+){0,2}"#, caseSensitive: true)
    /// After "Mr Smith": one more name ("Mr John Smith").
    private static let surnameTail = NoteRx(#"^\s+[A-Z][a-z'’-]+"#, caseSensitive: true)
    private static let titleRx = NoteRx(#"^(?:Mr|Mrs|Ms|Miss|Mx)\b"#, caseSensitive: true)

    // MARK: The note reader's findings

    /// Findings the note reader infers rather than reads, left out of the bar.
    private static func inferred(_ f: PatientNoteFinding) -> Bool {
        guard let n = f.note else { return false }
        switch f.id {
        case "problem:insulin", "problem:osa": return n.hasPrefix("From the ")
        case "airway": return n.hasPrefix("From the ") || n == "On room air." || n == "Breathing on their own with oxygen."
        default: return false
        }
    }

    static let vitalsElsewhere = "Vital signs · the preoperative baseline, on the Preop tab"
    static let arrivalElsewhere = "Airway, ventilator and oxygen on arrival · on the Preop tab"

    private static func route(_ f: PatientNoteFinding, _ line: String, _ c: QuickContext, _ out: inout QuickOut) {
        var f = f
        switch f.change {
        case .procedure:
            // The bar reads the planned procedure itself.
            return
        case .vital(let k, let v):
            guard c.tab == .preop else { return out.skip(vitalsElsewhere) }
            if k == "spo2" {
                if f.note != nil { return out.skip(oxygenNotice(v)) }
                return addSpO2(f, v, roomAir: roomAirStated(line, c), c, &out)
            }
            out.add(f)
        case .lab(let k, let v):
            addLab(k, v, c, &out)
        case .infusion(let drug, let rate):
            out.add(c.tab == .intraop ? infusionFinding(drug, rate, c, note: f.note) : f)
        case .devices(let ds):
            if c.tab == .intraop {
                f.change = .devices(ds.map { d -> PatientDevice in
                    var x = d
                    x.placedIntraop = true
                    return x
                })
            }
            out.add(f)
        case .currentAirway, .vent, .oxygen:
            guard c.tab == .preop else { return out.skip(arrivalElsewhere) }
            out.add(f)
        default:
            out.add(f)
        }
    }

    private static let roomAirWords = NoteRx(#"\broom air\b"#)

    private static func roomAirStated(_ line: String, _ c: QuickContext) -> Bool {
        roomAirWords.first(line) != nil || c.abbreviations.contains(where: { $0.key == "RA" && $0.meaning?.id == "ra-air" })
    }

    /// The question a saturation without "room air" or "RA" is asked, in the menu an ambiguous abbreviation has
    /// ("SpO₂ 95% · room air?"); the answer is kept in `choices` under this id.
    static let roomAirQuestion = "quick:spo2"
    static let roomAirAnswer = "spo2-room-air"
    static let oxygenAnswer = "spo2-oxygen"

    private static func oxygenNotice(_ v: Double) -> String { "SpO₂ " + NumText.short(v) + "% on oxygen · the field is SpO₂ on room air" }

    /// The field is SpO₂ on room air: filed when the line says room air, or once the user answers room air. On oxygen,
    /// or not answered, nothing goes into it.
    private static func addSpO2(_ f: PatientNoteFinding, _ v: Double, roomAir: Bool, _ c: QuickContext, _ out: inout QuickOut) {
        if roomAir { return out.add(f) }
        let value = "SpO₂ " + NumText.short(v) + "%"
        let answer = c.choices[roomAirQuestion]
        if !out.questions.contains(where: { $0.id == roomAirQuestion }) {
            let options = [AbbreviationMeaning("room air", id: roomAirAnswer), AbbreviationMeaning("on oxygen", id: oxygenAnswer)]
            out.questions.append(AmbiguousAbbreviation(id: roomAirQuestion, abbreviation: value, options: options, defaultID: roomAirAnswer,
                                                       fromContext: false, chosenID: answer ?? roomAirAnswer, context: value))
        }
        if answer == roomAirAnswer {
            out.add(f)
        } else if answer == oxygenAnswer {
            out.skip(oxygenNotice(v))
        }
    }

    /// What nothing was read from, as typed: an ambiguous abbreviation that neither the context nor the user settled
    /// is shown as written, not as the meaning the note reader tried ("levo 0.1", not "norepinephrine 0.1").
    private static func asTyped(_ leftover: String, _ text: String, user: [String: String], choices: [String: String]) -> String {
        guard !leftover.isEmpty else { return leftover }
        var out = leftover
        let typed = text.lowercased()
        for m in MedAbbreviations.scan(text, user: user, choices: choices) {
            guard m.isAmbiguous, !m.fromContext, choices[m.choiceKey ?? ""] == nil, let reading = m.meaning?.reading,
                  !typed.contains(reading.lowercased()) else { continue }
            let rx = NoteRx(#"(?<![A-Za-z])"# + NSRegularExpression.escapedPattern(for: reading) + #"(?![A-Za-z])"#)
            guard let hit = rx.first(out) else { continue }
            out = (out as NSString).replacingCharacters(in: hit.range, with: m.token)
        }
        return out
    }

    // MARK: Helpers

    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String? {
        guard i < m.numberOfRanges else { return nil }
        let r = m.range(at: i)
        guard r.location != NSNotFound else { return nil }
        return (s as NSString).substring(with: r)
    }

    private static func number(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> Double? {
        group(m, i, s).flatMap { num($0) }
    }

    /// A typed number: "1.1", "96,000", "−6".
    static func num(_ t: String) -> Double? {
        var v = t.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: " ", with: "")
        if v.range(of: #"^-?\d{1,3}(?:,\d{3})+$"#, options: .regularExpression) != nil { v = v.replacingOccurrences(of: ",", with: "") }
        guard let d = Double(v), d.isFinite else { return nil }
        return d
    }

    private static func shifted(_ r: NSRange, _ by: Int) -> NSRange { NSRange(location: r.location + by, length: r.length) }

    /// The text with a pattern's matches taken out, trimmed.
    private static func stripped(_ rx: NoteRx, _ s: String) -> String {
        let out = rx.re?.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "") ?? s
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// The comma- or semicolon-separated part of the line around a range.
    private static func pieceRange(_ r: NSRange, in s: String) -> NSRange {
        let ns = s as NSString
        var a = r.location
        var b = r.location + r.length
        while a > 0, ns.character(at: a - 1) != 44, ns.character(at: a - 1) != 59 { a -= 1 }
        while b < ns.length, ns.character(at: b) != 44, ns.character(at: b) != 59 { b += 1 }
        return NSRange(location: a, length: b - a)
    }

    /// The part of its piece before a range, and after it.
    private static func around(_ r: NSRange, in s: String) -> (before: String, after: String) {
        let ns = s as NSString
        let p = pieceRange(r, in: s)
        let before = ns.substring(with: NSRange(location: p.location, length: r.location - p.location))
        let end = r.location + r.length
        let after = ns.substring(with: NSRange(location: end, length: p.location + p.length - end))
        return (before, after)
    }

    /// "no", "held", "off" before a value in its piece: not read.
    private static let pieceNegation = NoteRx(#"\b(?:no|not|non|denies|without|w/o|never|held|holding|off|stopped|weaned|d/c'?d|discontinued|declined|refused)\b"#)

    // MARK: Labs

    /// The preoperative labs screen's keys (the troponin's 99th percentile is not a patient value).
    private static let preopLabKeys = Set(PatientLabs.catalog.map(\.key)).subtracting(["troponin99", "troponin"])

    /// "K 5.4 H", "Hb 9.1 L", "pH 7.29 L": a value as the summary shows it.
    static func labText(_ key: String, _ v: Double, sex: PatientSex?) -> String {
        guard let t = PatientLabs.test(key) else { return key + " " + NumText.short(v) }
        let mark = PatientLabs.flag(key, v, sex: sex).mark
        return t.short + " " + t.format(v) + (mark.isEmpty ? "" : " " + mark)
    }

    private static func labLabel(_ t: LabTest, _ v: Double) -> String {
        t.label + " " + t.format(v) + (t.unit.isEmpty ? "" : (t.unit == "%" ? "%" : " " + t.unit))
    }

    /// A lab value read from the line, to the record's labs (Preop) or a new intraoperative set (Intraop).
    private static func addLab(_ key: String, _ v: Double, _ c: QuickContext, _ out: inout QuickOut) {
        let k = c.tab == .intraop && key == "hco3" ? "hco3a" : key
        guard PatientLabs.isPlausible(k, v), let t = PatientLabs.test(k) else { return }
        guard !out.labs.contains(k) else { return out.skip(t.short + " " + t.format(v) + " · a second value; the first is added") }
        out.labs.insert(k)
        switch c.tab {
        case .preop:
            guard preopLabKeys.contains(k) else { return out.skip(t.short + " " + t.format(v) + " · an intraoperative lab, on the Intraop tab") }
            out.add(PatientNoteFinding(id: "lab:" + k, section: PatientNote.Part.labs, label: labLabel(t, v), change: .lab(k, v)))
        case .intraop:
            guard IntraopLabs.keys.contains(k) else { return out.skip(t.short + " " + t.format(v) + " · not an intraoperative lab") }
            var set = IntraopLabSet(time: c.now, values: [k: v])
            set.id = c.setID
            out.add(PatientNoteFinding(id: "intraop-lab:" + k, section: intraop, label: labLabel(t, v), change: .intraopLabs(set)))
        }
    }

    /// Labs by name, each alias with the key it fills. "co2" is the bicarbonate of a preoperative panel; "bd" a base
    /// deficit, read as a negative base excess.
    private static let labAliases: [(key: String, rx: NoteRx)] = labAliasList.map { (key: $0.0, rx: NoteRx(#"(?<![A-Za-z0-9])(?:"# + $0.1 + #")(?![A-Za-z0-9])"# + labValue)) }

    private static let labAliasList: [(String, String)] = [
        ("ntprobnp", #"nt[- ]?pro[- ]?bnp"#), ("bnp", #"bnp"#), ("a1c", #"hba1c|hgba1c|a1c|h(?:a)?emoglobin a1c"#),
        ("hb", #"hgb|hb|h(?:a)?emoglobin"#), ("hct", #"hct|h(?:a)?ematocrit"#), ("wbc", #"wbc|wcc|white (?:blood )?(?:cell )?count"#),
        ("plt", #"platelet count|platelets?|plts?"#), ("inr", #"inr"#), ("fibrinogen", #"fibrinogen|fib|fbg"#),
        ("na", #"(?-i:Na)\+?|sodium"#), ("k", #"(?-i:K)\+?|potassium"#), ("cl", #"(?-i:Cl|CL)-?|chloride"#),
        ("hco3", #"hco3-?|hco₃|bicarbonate|bicarb|tco2"#), ("bun", #"bun"#), ("cr", #"creatinine|creat|scr|cr"#), ("gfr", #"e?gfr"#),
        ("glucose", #"glucose|gluc|glu|fsbg|fsbs|bgl|bg|cbg|(?-i:BS)|poc glucose|blood (?:sugar|glucose)|sugar"#),
        ("albumin", #"albumin|alb"#), ("tbili", #"total bilirubin|bilirubin|t\.? ?bili|tbili|bili"#),
        ("ast", #"(?-i:AST)|sgot"#), ("alt", #"(?-i:ALT)|sgpt"#), ("alp", #"alkaline phosphatase|alk ?phos|alp"#), ("tsh", #"tsh"#),
        ("lactate", #"lactate|lactic acid|lac"#), ("ica", #"ionized ca(?:lcium)?|ionised ca(?:lcium)?|i-ca|ica"#), ("ph", #"(?-i:pH)"#),
        ("paco2", #"paco2|pco2|paco₂|pco₂"#), ("pao2", #"pao2|po2|pao₂|po₂"#), ("be", #"(?-i:BE)|base excess"#), ("bd", #"(?-i:BD)|base deficit"#),
        ("ptt", #"aptt|ptt"#), ("act", #"(?-i:ACT)|activated clotting time"#), ("co2", #"co2|co₂"#),
    ]

    /// After the name: "of", ":" or "=", an inequality (left unread), the number, "k" written onto it (platelets) or
    /// "%" (HbA1c, hematocrit), and no dose unit after it ("K 20 mEq" is a dose).
    private static let labValue = #"\s*(?:of|is|was|:|=)?\s*([<>≤≥]\s*)?([-−]?\d{1,3}(?:,\d{3})+|[-−]?\d+(?:\.\d+)?)(?:(k)(?![A-Za-z0-9])|\s*(%))?(?![\d.]|\s*/\s*\d|\s*(?:mg|mcg|ug|units?|u|meq|g|gm|cm|mm|ml|cc|kg|lb|mins?|hrs?)\b(?!\s*/))"#

    private static let vitaminBefore = NoteRx(#"\bvit(?:amin)?\.?\s*$"#)
    private static let fibBefore = NoteRx(#"\ba[- ]?$"#)

    private static func readLabs(_ s: inout QuickScan, _ c: QuickContext, _ out: inout QuickOut) {
        let text = s.text
        let ns = text as NSString
        var hits: [(key: String, m: NSTextCheckingResult)] = []
        for (key, rx) in labAliases {
            if key == "co2" && c.tab == .intraop { continue }
            for m in rx.all(text) { hits.append((key, m)) }
        }
        hits.sort { $0.m.range.location != $1.m.range.location ? $0.m.range.location < $1.m.range.location : $0.m.range.length > $1.m.range.length }
        var taken: [NSRange] = []
        for (key, m) in hits {
            guard !taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) else { continue }
            let before = ns.substring(to: m.range.location)
            if key == "k", vitaminBefore.first(before) != nil { continue }
            if key == "fibrinogen", fibBefore.first(before) != nil { continue }
            if key == "glucose", !c.means("bs-sugar", at: m.range) { continue }
            guard group(m, 1, text) == nil, var v = number(m, 2, text) else { continue }
            if group(m, 3, text) != nil && key != "plt" && key != "wbc" { continue }
            if group(m, 4, text) != nil && key != "a1c" && key != "hct" { continue }
            var k = key
            switch key {
            case "plt": if v >= 10_000 { v /= 1000 }
            case "wbc": if v >= 1000 { v /= 1000 }
            case "bd":
                guard v >= 0 else { continue }
                k = "be"
                v = -v
            case "co2": k = "hco3"
            default: break
            }
            let rk = c.tab == .intraop && k == "hco3" ? "hco3a" : k
            guard PatientLabs.isPlausible(rk, v) else { continue }
            taken.append(m.range)
            s.mask(m.range)
            addLab(k, v, c, &out)
        }
    }

    // MARK: Panels and the blood gas

    /// The BMP fishbone in its order, Na K Cl HCO₃ BUN Cr glucose: "138/4.1/102/24/18/1.1/162" or "138|4.1|102|24|18|1.1<162".
    static let bmpRx = NoteRx(#"(?<![\d./|<>])(\d{2,3})\s*[/|]\s*(\d{1,2}(?:\.\d{1,2})?)\s*[/|]\s*(\d{2,3})\s*[/|]\s*(\d{1,2}(?:\.\d)?)\s*[/|]\s*(\d{1,3})\s*[/|]\s*(\d{1,2}(?:\.\d{1,2})?)\s*[/|<]\s*(\d{2,4})(?![\d./|<>])"#)
    private static let bmpKeys = ["na", "k", "cl", "hco3", "bun", "cr", "glucose"]

    private static func readFishbone(_ s: inout QuickScan, _ c: QuickContext, _ out: inout QuickOut) {
        for m in bmpRx.all(s.text) {
            let vs = (1...7).compactMap { number(m, $0, s.text) }
            guard vs.count == 7, zip(bmpKeys, vs).allSatisfy({ PatientLabs.isPlausible($0.0, $0.1) }) else { continue }
            // Sodium above chloride and an anion gap that can be real: the values are in the panel's order.
            let gap = vs[0] - vs[2] - vs[3]
            guard vs[0] > vs[2], (-2...45).contains(gap) else { continue }
            s.mask(m.range)
            for (k, v) in zip(bmpKeys, vs) { addLab(k, v, c, &out) }
        }
    }

    /// The CBC fishbone: WBC > Hb / Hct < Plt.
    static let cbcRx = NoteRx(#"(?<![\d.>])(\d{1,3}(?:\.\d{1,2})?)\s*>\s*(\d{1,2}(?:\.\d)?)\s*/\s*(\d{1,2}(?:\.\d)?)\s*<\s*(\d{1,4})(?![\d.<])"#)
    private static let cbcKeys = ["wbc", "hb", "hct", "plt"]

    private static func readCBC(_ s: inout QuickScan, _ c: QuickContext, _ out: inout QuickOut) {
        for m in cbcRx.all(s.text) {
            let vs = (1...4).compactMap { number(m, $0, s.text) }
            guard vs.count == 4, zip(cbcKeys, vs).allSatisfy({ PatientLabs.isPlausible($0.0, $0.1) }) else { continue }
            // The hematocrit runs about three times the hemoglobin: the two are in their places.
            guard vs[1] > 0, (2.0...4.5).contains(vs[2] / vs[1]) else { continue }
            s.mask(m.range)
            for (k, v) in zip(cbcKeys, vs) { addLab(k, v, c, &out) }
        }
    }

    /// pH / PaCO₂ / PaO₂, then optionally / HCO₃ / BE: "7.29/41/168/19/-6".
    static let gasRx = NoteRx(#"(?<![\d./|<>])([67]\.\d{1,2})\s*/\s*(\d{1,3}(?:\.\d)?)\s*/\s*(\d{1,3}(?:\.\d)?)(?:\s*/\s*(\d{1,2}(?:\.\d)?)(?:\s*/\s*([-−–+]?\s?\d{1,2}(?:\.\d)?))?)?(?![\d./|<>])"#)
    static let gasWord = NoteRx(#"\b(?:abg|arterial (?:blood )?gas|blood gas|gas)\b"#)
    static let venousGas = NoteRx(#"\b(?:vbg|venous (?:blood )?gas|capillary (?:blood )?gas|mixed venous)\b"#)
    private static let gasLabel = NoteRx(#"(?:\babg|\barterial (?:blood )?gas|\bblood gas|\bgas)\s*[:\-]?\s*$"#)

    private static func readGas(_ s: inout QuickScan, _ c: QuickContext, _ out: inout QuickOut) {
        // On the Intraoperative tab, or wherever "ABG" or "gas" is written; never a venous gas (its PO₂ is not a PaO₂).
        guard c.tab == .intraop || gasWord.first(s.text) != nil, venousGas.first(s.text) == nil else { return }
        let text = s.text
        guard let m = gasRx.first(text), let ph = number(m, 1, text), let co2 = number(m, 2, text), let o2 = number(m, 3, text),
              PatientLabs.isPlausible("ph", ph), PatientLabs.isPlausible("paco2", co2), PatientLabs.isPlausible("pao2", o2) else { return }
        let hco3 = number(m, 4, text)
        let be = number(m, 5, text)
        // Henderson–Hasselbalch: the bicarbonate the pH and PaCO₂ imply. A gas out of order (PaO₂ where the PaCO₂ goes)
        // implies an impossible one, and a bicarbonate or base excess given must agree with it.
        let implied = 0.0307 * co2 * pow(10, ph - 6.1)
        guard (3...60).contains(implied) else { return }
        if let h = hco3, !(PatientLabs.isPlausible("hco3a", h) && Swift.abs(h - implied) <= Swift.max(4, implied * 0.2)) { return }
        if let b = be {
            let expected = 0.93 * ((hco3 ?? implied) - 24.4 + 14.8 * (ph - 7.4))
            guard PatientLabs.isPlausible("be", b), Swift.abs(b - expected) <= 5 else { return }
        }
        var r = m.range
        if let label = gasLabel.first((text as NSString).substring(to: r.location)) {
            r = NSRange(location: label.range.location, length: r.location + r.length - label.range.location)
        }
        s.mask(r)
        guard c.tab == .intraop else {
            return out.skip("Blood gas " + (text as NSString).substring(with: m.range) + " · on the Intraop tab")
        }
        var values: [(String, Double)] = [("ph", ph), ("paco2", co2), ("pao2", o2)]
        if let h = hco3 { values.append(("hco3a", h)) }
        if let b = be { values.append(("be", b)) }
        for (k, v) in values { addLab(k, v, c, &out) }
    }

    // MARK: Vital signs

    /// A blood pressure: "BP 148/86", or a bare pair that a heart rate must follow to count.
    static let bpRx = NoteRx(#"(?<![\d./|<>:])(?:\b(bp|nibp|abp|art|blood pressure)\s*:?\s*)?(\d{2,3})\s*/\s*(\d{2,3})(?![\d./|<>%:])"#)
    /// Other pressures written as a pair (PA, RV, ventilator) are not the blood pressure.
    private static let notBPBefore = NoteRx(#"\b(?:pa|pap|pas|rv|lv|cvp|pcwp|wedge|mpap|swan|peep|ps|pip|vt|tv|bipap|cpap|niv|fio2|aug|augmentation)\s*:?\s*$"#)
    private static let vSep = #"^[\s,;|]*"#
    private static let noUnit = #"(?![\d.%/])(?!\s*(?:g|ga|gauge|fr|f|mg|mcg|kg|cm|mm|ml|l|lpm|units?|u|mmhg)\b)"#
    private static let vHR = NoteRx(vSep + #"(?:hr|heart rate|pulse|p)\s*:?\s*(\d{2,3})"# + noUnit + #"(?:\s*(?:bpm|/min)\b)?"#)
    private static let vSpO2 = NoteRx(vSep + #"(?:spo2|spo₂|sats?|o2 sat|sao2|pulse ox)\s*:?\s*(\d{2,3})(?![\d.])\s*%?"#)
    private static let vPercent = NoteRx(vSep + #"(\d{2,3})\s*%"#)
    private static let vRoomAir = NoteRx(vSep + #"(?:on\s+)?(ra|room air)\b"#)
    private static let vOxygen = NoteRx(vSep + #"(?:on\s+)?(?:\d{1,2}(?:\.\d)?\s*(?:l|lpm|l/min|liters?)\b(?:\s*(?:nc|o2|oxygen))?|nc\b|nasal cannula|fm\b|face ?mask|nrb\b|non-?rebreather|hfnc\b|high[- ]flow|bipap\b|cpap\b|niv\b|o2\b|oxygen)"#)
    private static let vRR = NoteRx(vSep + #"(?:rr|resps|respirations|resp(?:iratory)? rate|resp|r)\s*:?\s*(\d{1,2})"# + noUnit + #"(?:\s*/min\b)?"#)
    private static let vTemp = NoteRx(vSep + #"(?:temperature|tmax|temp|t)\s*:?\s*(\d{2,3}(?:\.\d{1,2})?)\s*(?:°\s*)?([cf])?(?![\d%/.A-Za-z])"#)
    private static let vBareTemp = NoteRx(vSep + #"(\d{2,3}\.\d)\s*(?:°\s*)?([cf])?(?![\d%/.A-Za-z])"#)
    private static let vBare = NoteRx(vSep + #"(\d{1,3})"# + noUnit + #"(?:\s*(?:bpm|/min)\b)?"#)

    private static func readVitals(_ s: inout QuickScan, _ c: QuickContext, _ out: inout QuickOut) {
        let text = s.text
        let ns = text as NSString
        guard let m = bpRx.all(text).first(where: { m in
            m.range(at: 1).location != NSNotFound || notBPBefore.first(ns.substring(to: m.range.location)) == nil
        }), let sbp = number(m, 2, text), let dbp = number(m, 3, text) else { return }
        let labeled = m.range(at: 1).location != NSNotFound
        guard (50...260).contains(sbp), (20...160).contains(dbp), sbp > dbp else { return }

        var taken: [NSRange] = [m.range]
        var hr: Double?, rr: Double?, spo2: Double?, temp: Double?
        var fahrenheit: Double?
        var roomAir = false, onOxygen = false, afterSpO2 = false
        var at = m.range.location + m.range.length
        var first = true
        while at < ns.length {
            let rest = ns.substring(from: at)
            func step(_ t: NSTextCheckingResult, take: Bool = true) {
                if take { taken.append(shifted(t.range, at)) }
                at += t.range.length
            }
            var matched = true
            if hr == nil, let t = vHR.first(rest) {
                guard let v = number(t, 1, rest), (20...220).contains(v) else { break }
                hr = v
                step(t)
                afterSpO2 = false
            } else if spo2 == nil, let t = vSpO2.first(rest) ?? vPercent.first(rest) {
                guard let v = number(t, 1, rest), (50...100).contains(v) else { break }
                spo2 = v
                step(t)
                afterSpO2 = true
            } else if afterSpO2, let t = vRoomAir.first(rest),
                      c.means("ra-air", at: shifted(t.range(at: 1), at)) {
                roomAir = true
                step(t)
                afterSpO2 = false
            } else if afterSpO2, let t = vOxygen.first(rest) {
                // The oxygen is left for the note reader; the saturation on it is not SpO₂ on room air.
                onOxygen = true
                step(t, take: false)
                afterSpO2 = false
            } else if rr == nil, let t = vRR.first(rest) {
                guard let v = number(t, 1, rest), (4...60).contains(v) else { break }
                rr = v
                step(t)
                afterSpO2 = false
            } else if temp == nil, let t = vTemp.first(rest) ?? vBareTemp.first(rest) {
                guard var v = number(t, 1, rest) else { break }
                let unit = group(t, 2, rest)?.lowercased()
                let bare = vTemp.first(rest) == nil
                if unit == "f" || (unit == nil && (bare ? (93...108).contains(v) : (86...110).contains(v))) {
                    fahrenheit = v
                    v = ((v - 32) * 5 / 9 * 10).rounded() / 10
                } else if unit == nil && bare && !(34...42.5).contains(v) {
                    break
                }
                guard (30...43).contains(v) else { break }
                temp = v
                step(t)
                afterSpO2 = false
            } else if let t = vBare.first(rest), let v = number(t, 1, rest) {
                if hr == nil, (20...220).contains(v) {
                    hr = v
                } else if hr != nil, rr == nil, (4...60).contains(v) {
                    rr = v
                } else {
                    break
                }
                step(t)
                afterSpO2 = false
            } else {
                matched = false
            }
            if !matched { break }
            // A bare pair is a blood pressure only with a heart rate right after it.
            if first && !labeled && hr == nil { return }
            first = false
        }
        guard labeled || hr != nil else { return }
        for r in taken { s.mask(r) }
        guard c.tab == .preop else { return out.skip(vitalsElsewhere) }
        func finding(_ key: String, _ v: Double, note: String? = nil) -> PatientNoteFinding? {
            guard let f = PatientCatalog.vitals.first(where: { $0.id == key }) else { return nil }
            let unit = f.unit.hasPrefix("/") || f.unit == "%" ? f.unit : " " + f.unit
            return PatientNoteFinding(id: "vital:" + key, section: PatientNote.Part.vitals, label: f.label + " " + NumText.short(v) + unit,
                                      change: .vital(key, v), note: note)
        }
        func add(_ key: String, _ v: Double, note: String? = nil) {
            if let f = finding(key, v, note: note) { out.add(f) }
        }
        add("sbp", sbp)
        add("dbp", dbp)
        if let v = hr { add("hr", v) }
        if let v = spo2 {
            if onOxygen {
                out.skip(oxygenNotice(v))
            } else if let f = finding("spo2", v) {
                addSpO2(f, v, roomAir: roomAir || roomAirStated(s.original, c), c, &out)
            }
        }
        if let v = rr { add("rr", v) }
        if let v = temp { add("temp", v, note: fahrenheit.map { "Read as " + NumText.short($0) + " °F." }) }
    }

    // MARK: Blood products

    private static let product = #"(prbcs?|rbcs?|red (?:blood )?cells?|packed (?:red )?cells|ffp|plasma|plts?|platelets?|cryo(?:precipitate)?|whole blood|ltowb)"#
    /// "2 PRBC", "+2 FFP", "2u PRBC", "1 pool cryo", "1 apheresis plt".
    static let bloodBefore = NoteRx(#"(?<![\w.+×])([+x×]\s*)?(\d{1,3})\s*(?:(?:u|units?)\s+)?(?:(pools?|apheresis|bags?|doses?)\s+)?(?:(?:units?|bags?)\s+)?(?:of\s+)?"# + product + #"(?![A-Za-z])"#)
    /// "PRBC x2", "cryo 10", "plt 1", "FFP 2u".
    static let bloodAfter = NoteRx(#"(?<![A-Za-z])"# + product + #"\s*(?:[x×+:]\s*)?(\d{1,3})(?:\s*(u|units?|pools?|doses?|bags?)\b)?(?![\d.]|\s*(?:k\b|%|ml|mg|mcg))"#)
    static let cellSaverAfter = NoteRx(#"(?<![A-Za-z])(?:cell\s*-?\s*sav(?:er|ed)|cellsaver|cell\s*salvage|salvaged blood)(?:\s+(?:returned|given|back))?\s*:?\s*\+?\s*(\d{2,4})\s*(?:ml|cc)?(?![\d.])"#)
    static let cellSaverBefore = NoteRx(#"(?<![\w.])(\d{2,4})\s*(?:ml|cc)\s+(?:of\s+)?(?:cell\s*-?\s*sav(?:er|ed)|cellsaver|cell\s*salvage|salvaged blood)"#)
    /// Blood that is ordered or waiting, not given.
    private static let notGiven = NoteRx(#"\b(?:available|in (?:the )?room|cross-?matched|crossmatch|x-?matched|type and cross|t&c|ready|on hold|ordered|requested|consented|if needed|prn|standby)\b"#)

    private static func productKey(_ word: String) -> String {
        let w = word.lowercased()
        if w.hasPrefix("ffp") || w.hasPrefix("plasma") { return "plasma" }
        if w.hasPrefix("pl") { return "platelets" }
        if w.hasPrefix("cryo") { return "cryo" }
        if w.hasPrefix("whole") || w == "ltowb" { return "wholeBlood" }
        return "prbc"
    }

    static let poolNote = "A pool read as 5 units, as the Fluids +5 button counts it; change it there if your pools differ."

    /// Each mention is its own finding ("cryo 10, 1 pool cryo": Cryo +10 and Cryo +5 (1 pool)), so either can be left
    /// out; the chips put the running total on the last one.
    private static func readBlood(_ s: inout QuickScan, _ c: QuickContext, _ out: inout QuickOut) {
        var mentions: [(key: String, n: Double, pools: Double, at: Int)] = []
        func given(_ r: NSRange, _ text: String) -> Bool {
            let p = around(r, in: text)
            if pieceNegation.first(p.before) != nil { return false }
            if notGiven.first(p.before + " " + p.after) != nil {
                // Recognized and left out on purpose: shown as such, not as text nothing read (the product and the
                // word that says it was not given).
                s.mask(r)
                let piece = pieceRange(r, in: text)
                for m in notGiven.all((text as NSString).substring(with: piece)) { s.mask(shifted(m.range, piece.location)) }
                out.skip("Blood products ordered or available · not given, not added")
                return false
            }
            return true
        }
        func add(_ key: String, _ n: Double, _ r: NSRange, pools: Double = 0) {
            mentions.append((key: key, n: n, pools: pools, at: r.location))
            s.mask(r)
        }
        // Units per entry that can be real; cryoprecipitate in units comes 5 or more at a time.
        func plausible(_ key: String, _ n: Double) -> Bool {
            switch key {
            case "prbc", "plasma": return (1...20).contains(n)
            case "platelets": return (1...6).contains(n)
            case "wholeBlood": return (1...10).contains(n)
            case "cryo": return (5...50).contains(n)
            default: return false
            }
        }
        func entry(_ key: String, _ n: Double, unit: String?, _ r: NSRange, _ text: String) {
            guard n == n.rounded(), given(r, text) else { return }
            let u = (unit ?? "").lowercased()
            if key == "cryo" {
                if u.hasPrefix("pool") {
                    guard (1...5).contains(n) else { return }
                    return add(key, n * 5, r, pools: n)
                }
                // "2 cryo" could be units or pools: not read.
                if n < 5 {
                    s.mask(r)
                    return out.skip("Cryo " + NumText.short(n) + " · units or pools? Write “2 pools cryo” or “cryo 10”")
                }
            }
            guard plausible(key, n) else { return }
            add(key, n, r)
        }
        var text = s.text
        for m in bloodBefore.all(text) {
            guard let n = number(m, 2, text), let word = group(m, 4, text) else { continue }
            entry(productKey(word), n, unit: group(m, 3, text), m.range, text)
        }
        text = s.text
        for m in bloodAfter.all(text) {
            guard let word = group(m, 1, text), let n = number(m, 2, text) else { continue }
            let key = productKey(word)
            // "plt 96" is a count: a platelet dose is written 1 to 4.
            if key == "platelets", n > 4 { continue }
            entry(key, n, unit: group(m, 3, text), m.range, text)
        }
        for rx in [cellSaverBefore, cellSaverAfter] {
            text = s.text
            for m in rx.all(text) {
                guard let n = number(m, 1, text), (25...5000).contains(n), given(m.range, text) else { continue }
                add(BloodProducts.cellSaver, n, m.range)
            }
        }
        var running: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for m in mentions.sorted(by: { $0.at < $1.at }) {
            let isCellSaver = m.key == BloodProducts.cellSaver
            let sum = (running[m.key] ?? 0) + m.n
            guard (c.record.fluids[m.key] ?? 0) + sum <= (isCellSaver ? 20000 : 199) else { continue }
            running[m.key] = sum
            let k = (counts[m.key] ?? 0) + 1
            counts[m.key] = k
            let name = isCellSaver ? "Cell saver" : (BloodProducts.units.first(where: { $0.id == m.key })?.short ?? m.key)
            var label = name + " +" + NumText.short(m.n) + (isCellSaver ? " mL" : "")
            var note: String?
            if m.pools > 0 {
                label += " (" + NumText.short(m.pools) + " pool" + (m.pools == 1 ? "" : "s") + ")"
                note = poolNote
            }
            out.add(PatientNoteFinding(id: "blood:" + m.key + (k > 1 ? ":" + String(k) : ""), section: intraop, label: label,
                                       change: .blood(m.key, m.n), note: note))
        }
    }

    // MARK: Drips

    /// Drips read with a bare rate ("epi 0.05"), each with the rates that can only be a rate (a bolus is never written
    /// that way). Others need "gtt", "drip" or a unit per minute or hour, which the note reader reads. "levo" is
    /// read only once its meaning is chosen (levothyroxine 0.1 mg is a dose).
    private static let drips: [(drug: String, rx: NoteRx, rates: ClosedRange<Double>, meaning: String?, confirm: Bool)] = dripList.map {
        (drug: $0.0, rx: NoteRx(#"(?<![A-Za-z0-9])("# + $0.1 + #")(?![A-Za-z0-9])\s*(?:(?:gtt|drip|infusion)s?\s*)?(?:at\s+|@\s*|=\s*|:\s*)?(\d*\.\d+|\d+)(?![\d.]|\s*(?:mcg|mg|ug|µg|units?|u|ml|%|g|meq|ng|mmol)\b|\s*/)"#),
         rates: $0.2, meaning: $0.3, confirm: $0.4)
    }

    private static let dripList: [(String, String, ClosedRange<Double>, String?, Bool)] = [
        ("epinephrine", #"epinephrine|adrenaline|epi"#, 0.01...1.0, "epi-epinephrine", false),
        ("norepinephrine", #"norepinephrine|noradrenaline|norepi|levophed|(?-i:NE)"#, 0.01...1.0, nil, false),
        ("norepinephrine", #"levo"#, 0.01...1.0, "levo-norepinephrine", true),
        ("vasopressin", #"vasopressin|vaso"#, 0.01...0.1, nil, false),
        ("milrinone", #"milrinone|milri"#, 0.1...1.0, nil, false),
        ("dobutamine", #"dobutamine|dobuta|dobut"#, 1.0...20.0, nil, false),
        ("dopamine", #"dopamine|dopa"#, 1.0...20.0, nil, false),
    ]
    private static let offAfter = NoteRx(#"^\s*(?:off|stopped|weaned|held|d/c'?d|discontinued)\b"#)
    static let noUnitNote = "No unit written: added as written, without one."

    private static func infusionFinding(_ drug: String, _ rate: String, _ c: QuickContext, note: String?) -> PatientNoteFinding {
        let label = "Infusion: " + drug + (rate.isEmpty ? "" : " at " + rate)
        if c.tab == .intraop {
            return PatientNoteFinding(id: "intraop-infusion:" + drug, section: intraop, label: label, change: .intraopInfusion(drug, rate), note: note)
        }
        return PatientNoteFinding(id: "infusion:" + drug, section: PatientNote.Part.meds, label: label, change: .infusion(drug, rate), note: note)
    }

    private static func readDrips(_ s: inout QuickScan, _ c: QuickContext, _ out: inout QuickOut) {
        for d in drips {
            let text = s.text
            for m in d.rx.all(text) {
                guard var rate = group(m, 2, text), let v = num(rate), d.rates.contains(v) else { continue }
                if let meaning = d.meaning, !c.means(meaning, at: m.range(at: 1), confirmed: d.confirm) { continue }
                let p = around(m.range, in: text)
                if pieceNegation.first(p.before) != nil || offAfter.first(p.after) != nil { continue }
                if rate.hasPrefix(".") { rate = "0" + rate }
                s.mask(m.range)
                out.add(infusionFinding(d.drug, rate, c, note: noUnitNote))
            }
        }
    }

    // MARK: The planned procedure

    /// Planned without "for": "planned lap chole", "Plan: L TKA" (a procedure from the list must follow).
    private static let plannedLead = NoteRx(#"(?:^|[,;.]\s*)(?:planned|plan|scheduled|booked|posted)\s*:?\s+(?!for\b)"#)
    /// The start of the line, past the age and sex ("68M", "72 yo F").
    private static let lineLead = NoteRx(#"^\s*(?:\d{1,3}\s*(?:yo|y/o|y\.o\.?|-?year-old|yrs?)?\s*(?:M|F|male|female|man|woman)\b\s*[,:\-–]?\s*)?"#)
    private static let lastFor = NoteRx(#"\bfor\b"#)
    private static let urgencyWord = NoteRx(#"\b(?:elective|urgent|emergent|emergency|semi-?urgent|stat|time[- ]sensitive)\b"#)
    /// A procedure from the past, not planned ("CABG 2015", "s/p", "years ago").
    private static let pastWords = NoteRx(#"\b(?:19|20)\d\d\b|\bago\b|\b(?:s/p|status post|prior|previous|history|hx|h/o|remote)\b"#)
    /// Words that join procedures or detail one: "×3", "+", "possible open", "L4-5".
    private static let detailWord = NoteRx(#"^(?:x\d{1,2}|×\d{1,2}|×|x|\d{1,2}|\+|&|and|/|with|w/|plus|possible|poss|open|conversion|converted|to|redo|re-do|robotic|robot|robot-assisted|assisted|lap|laparoscopic|minimally|invasive|mini|left|right|bilateral|l|r|lt|rt|bilat|b/l|elective|urgent|emergent|emergency|stat|staged|single|double|triple|quadruple|vessel|level|levels|[a-z]\d{1,2}(?:-[a-z]?\d{1,2})?)$"#)

    private static func readProcedure(_ s: inout QuickScan, _ c: QuickContext, _ out: inout QuickOut) {
        let text = s.text
        let ns = text as NSString
        // "for …" after the patient, "scheduled for …", "Procedure: …", or a line that opens with "for": the note
        // reader's own patterns.
        let contexts: [(NoteRx, Bool)] = [(PatientNote.procedureHeaderRx, false), (PatientNote.procedureRx, false),
                                          (PatientNote.procedurePersonRx, true), (PatientNote.procedureLeadRx, false)]
        for (rx, person) in contexts {
            guard let m = rx.first(text), m.numberOfRanges > 1 else { continue }
            let g = m.range(at: 1)
            guard g.location != NSNotFound, let p = segment(g, in: text, typed: true) else { return }
            // The intro goes with it ("scheduled for", "Procedure:"), but not the patient ("68M") nor the urgency.
            let introStart: Int
            if person, let f = lastFor.all(ns.substring(with: NSRange(location: m.range.location, length: g.location - m.range.location))).last {
                introStart = m.range.location + f.range.location
            } else {
                introStart = m.range.location
            }
            let intro = NSRange(location: introStart, length: g.location - introStart)
            let urgency = urgencyWord.all(ns.substring(with: intro)).map { shifted($0.range, introStart) }
            var cut = introStart
            for u in urgency {
                s.mask(NSRange(location: cut, length: u.location - cut))
                cut = u.location + u.length
            }
            s.mask(NSRange(location: cut, length: g.location - cut))
            return take(p, &s, c, &out)
        }
        if let m = plannedLead.first(text) {
            let g = NSRange(location: m.range.location + m.range.length, length: ns.length - m.range.location - m.range.length)
            if let p = segment(g, in: text, typed: false) {
                s.mask(NSRange(location: m.range.location, length: g.location - m.range.location))
                return take(p, &s, c, &out)
            }
        }
        // A procedure from the list opening the line, on the Preoperative tab (not lines and devices, a header such as
        // "TEE:", nor one from the past).
        // The line as typed decides what opens it: text another reader took is not an opening.
        guard c.tab == .preop, let m = lineLead.first(s.original) else { return }
        let lead = m.range.location + m.range.length
        let g = NSRange(location: lead, length: ns.length - lead)
        guard g.length > 0, let p = segment(g, in: text, typed: false),
              stripped(urgencyWord, (s.original as NSString).substring(with: NSRange(location: lead, length: p.range.location - lead))).isEmpty
        else { return }
        let named = ns.substring(with: p.range)
        let next = p.range.location + p.range.length < ns.length ? ns.substring(with: NSRange(location: p.range.location + p.range.length, length: 1)) : ""
        let rest = ns.substring(with: pieceRange(p.range, in: text))
        guard PatientNote.deviceCue.first(named) == nil, PatientNote.tubeCue.first(named) == nil, next != ":",
              pastWords.first(rest) == nil else { return }
        take(p, &s, c, &out)
    }

    /// The procedure in a stretch of the line: cut where the note reader cuts it, then kept to the procedures from the
    /// list and the words that join or detail them ("lap chole HTN" is a cholecystectomy). Words before the first one
    /// are kept only after "for" (a procedure as typed), and text the list does not know only then.
    private static func segment(_ g: NSRange, in text: String, typed: Bool) -> (range: NSRange, text: String)? {
        let ns = text as NSString
        var seg = ns.substring(with: g)
        if let cut = PatientNote.procedureCut.first(seg) { seg = (seg as NSString).substring(to: cut.range.location) }
        let matches = ProcedureCatalog.parse(seg).filter { $0.range.upperBound <= seg.endIndex }.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var lo = seg.startIndex
        var hi = seg.endIndex
        if let first = matches.first {
            if !typed {
                // From the list, and opening the stretch: before it only the urgency (left for the note reader) or words
                // that detail it ("redo", "robotic"; a side written before it is part of the match).
                var start: String.Index?
                for (w, r) in words(seg, from: seg.startIndex, to: first.range.lowerBound) {
                    if start == nil, urgencyWord.first(w) != nil { continue }
                    guard detailWord.first(w.lowercased()) != nil else { return nil }
                    if start == nil { start = r.lowerBound }
                }
                lo = start ?? first.range.lowerBound
            }
            var end = first.range.upperBound
            var k = 1
            while true {
                let nextStart = k < matches.count ? matches[k].range.lowerBound : seg.endIndex
                var detailEnd = end
                var clean = true
                for (w, r) in words(seg, from: end, to: nextStart) {
                    if detailWord.first(w.lowercased()) != nil { detailEnd = r.upperBound } else { clean = false; break }
                }
                if k < matches.count && clean {
                    end = matches[k].range.upperBound
                    k += 1
                    continue
                }
                end = detailEnd
                break
            }
            hi = end
        } else if !typed {
            return nil
        }
        let t = String(seg[lo..<hi]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;-"))
        guard t.filter(\.isLetter).count >= 3, t.count <= 120, let r = seg.range(of: t, range: lo..<hi) else { return nil }
        return (shifted(NSRange(r, in: seg), g.location), t)
    }

    /// The words between two places in a string, each without the punctuation around it, with its range.
    private static func words(_ s: String, from: String.Index, to: String.Index) -> [(String, Range<String.Index>)] {
        var out: [(String, Range<String.Index>)] = []
        var i = from
        while i < to {
            while i < to, s[i].isWhitespace { i = s.index(after: i) }
            guard i < to else { break }
            let start = i
            while i < to, !s[i].isWhitespace { i = s.index(after: i) }
            let w = String(s[start..<i]).trimmingCharacters(in: CharacterSet(charactersIn: "(),.:;"))
            if !w.isEmpty { out.append((w, start..<i)) }
        }
        return out
    }

    private static func take(_ p: (range: NSRange, text: String), _ s: inout QuickScan, _ c: QuickContext, _ out: inout QuickOut) {
        s.mask(p.range)
        let items = PlannedProcedure.parse(p.text)
        let known = items.contains { $0.catalogID != nil }
        out.add(PatientNoteFinding(id: "procedure", section: PatientNote.Part.procedure, label: "Procedure: " + p.text, change: .procedure(p.text),
                                   note: known ? "Fills the risk-score inputs from the procedure list." : nil))
    }

    // MARK: The planned anesthetic

    static let planPrefix = "plan-anesthetic:"
    static let planNote = "The usual plan for the procedure, as the Procedure editor fills it."

    private static func isAnesthetic(_ f: PatientNoteFinding) -> Bool {
        if case .anesthetic = f.change { return true }
        return false
    }

    /// The planned anesthetic the Procedure editor fills from procedures on the list, when the record has none and the
    /// line names no technique (even one the reader did not take, as in "TKA, spinal"). A plan already set is never
    /// replaced.
    private static func readPlan(_ line: String, _ c: QuickContext, _ out: inout QuickOut) {
        let techniques = [PatientNote.gaRx, PatientNote.neuraxialRx, PatientNote.macRx, PatientNote.regionalRx]
        guard c.record.anesthetic.isEmpty, !out.findings.contains(where: isAnesthetic),
              !techniques.contains(where: { $0.first(line) != nil }),
              let p = out.findings.first(where: { $0.id == "procedure" }), case .procedure(let text) = p.change,
              PatientNote.status(p, in: c.record).canAdd else { return }
        let picked = PlannedProcedure.parse(text).compactMap { i in i.catalog.map { (procedure: $0, side: i.side) } }
        guard !picked.isEmpty else { return }
        let plan = ProcedureCatalog.risk(picked: picked).anesthetic
        for a in PatientCatalog.anesthetics where plan.contains(a.id) {
            out.add(PatientNoteFinding(id: planPrefix + a.id, section: PatientNote.Part.procedure, label: "Planned anesthetic: " + a.label.lowercased(),
                                       change: .anesthetic(a.id), note: planNote))
        }
    }

    // MARK: The intraoperative airway

    static let tubeRx = NoteRx(#"(?<![\d.])(?:(\d{1,2}(?:\.\d)?)\s*(?:mm\s*)?(?:cuffed\s+)?(?:ett|et tube|endotracheal tube)\b|\b(?:ett|et tube|endotracheal tube)\s*#?\s*(\d{1,2}(?:\.\d)?))(?![\d.])(?:\s*(?:@|at)?\s*(\d{2})(?:\s*cm\b|(?=\s*(?:$|[,;]|at\b|@))))?(?:\s*(?:at|@)?\s*(?:the\s+)?(lips?|teeth|incisors|gums|nares?)\b)?"#)
    static let dltRx = NoteRx(#"(?<![\w.])(?:(left|right|l|r)\s*)?(\d{2})\s*(?:fr|f)?\s*(?:(left|right|l|r)\s+)?(?:dlt|double[- ]lumen(?:\s+(?:tube|ett))?)\b"#)
    private static let airwayDevices: [(NoteRx, String)] = [
        (NoteRx(#"(?-i:\bVL\b)|\bvideo ?laryngoscop\w*|\bglide ?scope\b|\bglide\b|\bc-?mac\b|\bmcgrath\b"#), "Video laryngoscope"),
        (NoteRx(#"(?-i:\bDL\b)|\bdirect laryngoscop\w*|\b(?:mac|macintosh)\s*#?\s*[1-5]\b|\bmiller\s*#?\s*[0-4]\b"#), "Direct laryngoscope"),
        (NoteRx(#"\b(?:fob|foi|afoi)\b|\bfib(?:er|re) ?optic\w*|\bflexible (?:scope|bronchoscop\w*)"#), "Flexible scope"),
        (NoteRx(#"\b(?:lma|i-?gel|sga)\b|\bsupraglottic\b|\blaryngeal mask\b"#), "Supraglottic airway"),
    ]
    private static let gradeRx = NoteRx(#"\b(?:grade|gr\.?|cl|c/l|cormack(?:[- ]lehane)?)\s*:?\s*(2a|2b|3a|3b|iv|iii|ii|i|[1-4])\b"#)
    private static let gradeNotBefore = NoteRx(#"\b(?:mask|mv|bmv|han|mallampati|mp|asa|nyha|ckd|ulbt|ventilation)\s*$"#)
    private static let airwayContext = NoteRx(#"(?-i:\b(?:VL|DL)\b)|\b(?:ett|et tube|endotracheal|intubat\w*|laryngoscop\w*|glide ?scope|glide|c-?mac|mcgrath|miller|mac\s*#?\s*[1-5]|view|cormack|lma|i-?gel|dlt|bougie|fob)\b"#)
    private static let maskGradeRx = NoteRx(#"\b(?:(?:bag[- ])?mask|mv|bmv)(?:\s+ventilation)?\s+(?:grade|gr\.?)\s*:?\s*([1-4])\b|\bhan\s*(?:grade)?\s*:?\s*([1-4])\b"#)
    private static let maskEaseRx = NoteRx(#"\b(easy|difficult|diff)\s+(?:(?:bag[- ])?mask(?:ing)?|mv|bmv)(?:\s+ventilation)?\b|\b(?:(?:bag[- ])?mask(?:ing)?|mv|bmv)(?:\s+ventilation)?\s+(?:was\s+)?(easy|difficult|diff)\b"#)
    private static let intubationEaseRx = NoteRx(#"\b(easy|difficult|diff)\s+(?:intubation|(?-i:DL|VL)|laryngoscopy)\b|\bintubation\s+(?:was\s+)?(easy|difficult)\b"#)
    private static let attemptsRx = NoteRx(#"(?<![\w])(?:[x×]\s?([1-9])\s+attempts?|([1-9])\s+attempts?|(first|1st)[- ](?:attempt|pass)|(second|2nd)[- ]attempt|(third|3rd)[- ]attempt)\b"#)
    static let inductionTiming = NoteRx(#"\b(?:pre|post)-?\s?induction\b|\b(?:before|after)\s+induction\b"#)

    /// The airway fields the bar fills, as PatientRecord.intraopAirway names them.
    static let airwayFields = ["device", "grade", "maskGrade", "mask", "intubation", "attempts", "tube"]

    private static func readAirway(_ s: inout QuickScan, _ c: QuickContext, _ out: inout QuickOut) {
        var found: [(key: String, value: String, label: String)] = []
        var ranges: [NSRange] = []
        func put(_ key: String, _ value: String, _ label: String, _ r: NSRange, certain: Bool = false) {
            guard !found.contains(where: { $0.key == key }) else { return }
            found.append((key, value, label))
            ranges.append(r)
            if certain { s.certain.append(r) }
        }
        func negated(_ r: NSRange, _ text: String) -> Bool { pieceNegation.first(around(r, in: text).before) != nil }
        var text = s.text

        // The tube: "7.5 ETT 23 cm", "ETT 8.0 @ 22 at the teeth", "37 Fr L DLT".
        if let m = tubeRx.first(text), let size = group(m, 1, text) ?? group(m, 2, text), let v = num(size),
           (2...10).contains(v), (v * 2).rounded() == v * 2, !negated(m.range, text) {
            let ett = (text as NSString).range(of: "ett", options: .caseInsensitive, range: m.range)
            if ett.location == NSNotFound || c.means("ett-tube", at: ett) {
                var tube = NumText.short(v, places: 1)
                if v == v.rounded() { tube += ".0" }
                tube += " ETT"
                if let d = number(m, 3, text), (8...35).contains(d) {
                    tube += ", " + NumText.short(d) + " cm"
                    if let at = group(m, 4, text)?.lowercased() {
                        let place = at.hasPrefix("lip") ? "lip" : (at.hasPrefix("gum") ? "gums" : (at.hasPrefix("nare") ? "nare" : "teeth"))
                        tube += " at the " + place
                    }
                }
                put("tube", tube, tube, m.range, certain: true)
            }
        } else if let m = dltRx.first(text), let v = number(m, 2, text), (26...41).contains(v), !negated(m.range, text) {
            let side = (group(m, 1, text) ?? group(m, 3, text))?.lowercased()
            let word = side.map { $0.hasPrefix("l") ? " left" : " right" } ?? ""
            let tube = NumText.short(v) + " Fr" + word + " DLT"
            put("tube", tube, tube, m.range, certain: true)
        }
        text = s.text
        for (rx, device) in airwayDevices {
            guard let m = rx.first(text) else { continue }
            let t = (text as NSString).substring(with: m.range).lowercased()
            if t.hasPrefix("mac"), !c.means("mac-blade", at: m.range) { continue }
            put("device", device, device, m.range, certain: device == "Direct laryngoscope" && t.hasPrefix("mac"))
            break
        }
        let context = airwayContext.first(text) != nil
        for m in gradeRx.all(text) where context {
            guard let g = group(m, 1, text)?.lowercased(), gradeNotBefore.first(around(m.range, in: text).before) == nil else { continue }
            let map = ["1": "1", "i": "1", "2a": "2a", "2b": "2b", "3": "3", "3a": "3", "3b": "3", "iii": "3", "4": "4", "iv": "4"]
            if let grade = map[g] {
                put("grade", grade, "View grade " + grade, m.range)
            } else {
                s.mask(m.range)
                out.skip("View grade 2 · choose 2a or 2b in the airway course")
            }
            break
        }
        if let m = maskGradeRx.first(text), let g = group(m, 1, text) ?? group(m, 2, text), !negated(m.range, text) {
            put("maskGrade", g, "Mask grade " + g, m.range)
        }
        if let m = maskEaseRx.first(text), let w = (group(m, 1, text) ?? group(m, 2, text))?.lowercased(), !negated(m.range, text) {
            let v = w == "easy" ? "easy" : "difficult"
            put("mask", v, "Mask " + v, m.range)
        }
        if let m = intubationEaseRx.first(text), let w = (group(m, 1, text) ?? group(m, 2, text))?.lowercased(), !negated(m.range, text) {
            let v = w == "easy" ? "easy" : "difficult"
            put("intubation", v, "Intubation " + v, m.range)
        }
        if let m = attemptsRx.first(text) {
            let ordinals = ["first": 1, "1st": 1, "second": 2, "2nd": 2, "third": 3, "3rd": 3]
            let digits: Int? = (group(m, 1, text) ?? group(m, 2, text)).flatMap { Int($0) }
            let n: Int? = digits ?? (group(m, 3, text) ?? group(m, 4, text) ?? group(m, 5, text)).flatMap { ordinals[$0.lowercased()] }
            if let n { put("attempts", String(n), n == 1 ? "1 attempt" : "\(n) attempts", m.range) }
        }
        for r in ranges { s.mask(r) }
        guard !found.isEmpty else { return }
        if c.record.arrivesWithAirway { return out.skip("Airway course · the patient arrives with an airway (Preop tab)") }
        for f in found {
            out.add(PatientNoteFinding(id: "intraop-airway:" + f.key, section: intraop, label: f.label, change: .intraopAirway(f.key, f.value)))
        }
    }

    // MARK: Chips

    /// The chips for a reading, in its order: a blood pressure's two halves are one chip, and so is the planned
    /// anesthetic. `dropped` (chip ids left out) decides what the others show: the running blood total counts only the
    /// chips left on, and the planned anesthetic goes in only with its procedure.
    static func chips(_ q: QuickAddReading, record r: PatientRecord, dropped: Set<String> = []) -> [QuickAddChip] {
        let sbp = q.findings.first { $0.id == "vital:sbp" }
        let dbp = q.findings.first { $0.id == "vital:dbp" }
        let plan = q.findings.filter { $0.id.hasPrefix(planPrefix) }
        var out: [QuickAddChip] = []
        for f in q.findings {
            if f.id == "vital:dbp", sbp != nil { continue }
            if f.id.hasPrefix(planPrefix) {
                guard f.id == plan.first?.id else { continue }
                let names = plan.compactMap { p -> String? in
                    guard case .anesthetic(let a) = p.change else { return nil }
                    return PatientCatalog.anesthetics.first(where: { $0.id == a })?.label
                }
                let value = names.joined(separator: " + ") + " (usual plan)"
                out.append(QuickAddChip(id: "plan-anesthetic|" + value, findings: plan, destination: "Anesthetic", value: value, status: .new,
                                        note: f.note))
                continue
            }
            if f.id == "vital:sbp", let d = dbp, case .vital(_, let s) = f.change, case .vital(_, let dv) = d.change {
                let a = PatientNote.status(f, in: r)
                let b = PatientNote.status(d, in: r)
                let status: PatientNoteStatus
                if case .recorded = a, case .recorded = b {
                    status = .recorded
                } else if r.vitals["sbp"] != nil || r.vitals["dbp"] != nil, a != .new || b != .new {
                    status = .replaces((r.vitals["sbp"].map { NumText.short($0) } ?? "–") + "/" + (r.vitals["dbp"].map { NumText.short($0) } ?? "–"))
                } else {
                    status = .new
                }
                let value = "BP " + NumText.short(s) + "/" + NumText.short(dv)
                out.append(QuickAddChip(id: "vital:bp|" + value, findings: [f, d], destination: "Vitals", value: value, status: status, note: nil))
                continue
            }
            let (destination, value) = describe(f, r)
            out.append(QuickAddChip(id: f.id + "|" + value, findings: [f], destination: destination, value: value,
                                    status: PatientNote.status(f, in: r), note: f.note))
        }
        func on(_ c: QuickAddChip) -> Bool { c.canAdd && !dropped.contains(c.id) }
        // The planned anesthetic goes in only with the procedure it comes from.
        if let i = out.firstIndex(where: { $0.id.hasPrefix("plan-anesthetic|") }),
           !out.contains(where: { c in c.findings.contains(where: { $0.id == "procedure" }) && on(c) }) {
            out[i].status = .conflicts("needs the procedure")
        }
        // Blood: the running total on the last chip left on for each product, so it is what the chips add.
        var keys: [String] = []
        for c in out { if let b = blood(c), !keys.contains(b.key) { keys.append(b.key) } }
        for k in keys {
            let kept = out.indices.filter { blood(out[$0])?.key == k && on(out[$0]) }
            let before = r.fluids[k] ?? 0
            guard let last = kept.last, before > 0 || kept.count > 1 else { continue }
            let total = kept.reduce(before) { $0 + (blood(out[$1])?.n ?? 0) }
            out[last].value += " (total " + NumText.short(total) + (k == BloodProducts.cellSaver ? " mL" : "") + ")"
        }
        return out
    }

    private static func blood(_ c: QuickAddChip) -> (key: String, n: Double)? {
        guard c.findings.count == 1, case .blood(let k, let n) = c.findings[0].change else { return nil }
        return (k, n)
    }

    /// The changes of the chips to file: those not dropped, that can be added.
    static func changes(_ chips: [QuickAddChip], dropped: Set<String> = []) -> [PatientNoteChange] {
        chips.filter { $0.canAdd && !dropped.contains($0.id) }.flatMap { $0.findings.map(\.change) }
    }

    private static let destinations: [String: String] = [
        PatientNote.Part.patient: "Patient", PatientNote.Part.procedure: "Procedure", PatientNote.Part.vitals: "Vitals",
        PatientNote.Part.history: "History", PatientNote.Part.meds: "Meds", PatientNote.Part.anesthesia: "Anesthesia history",
        PatientNote.Part.intake: "NPO", PatientNote.Part.labs: "Labs", PatientNote.Part.assessment: "Assessment",
        PatientNote.Part.airway: "Airway", PatientNote.Part.devices: "Lines", PatientNote.Part.support: "Support", intraop: "Intraop",
    ]
    private static let labelPrefixes = ["Infusion: ", "Procedure: ", "Allergies: ", "Planned anesthetic: ", "Timing: ", "Cardiac symptom: ",
                                        "Acute cardiac condition: "]

    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// Where a finding goes and what it writes, for its chip.
    private static func describe(_ f: PatientNoteFinding, _ r: PatientRecord) -> (String, String) {
        let destination = destinations[f.section] ?? f.section
        switch f.change {
        case .vital(let k, let v):
            let names = ["hr": "HR ", "spo2": "SpO₂ ", "rr": "RR ", "temp": "T "]
            let units = ["spo2": "%", "temp": " °C"]
            return (destination, (names[k] ?? k + " ") + NumText.short(v) + (units[k] ?? ""))
        case .lab(let k, let v):
            return (destination, labText(k, v, sex: r.sex))
        case .intraopLabs(let set):
            let keys = IntraopLabs.keys.filter { set.values[$0] != nil }
            return (destination, keys.compactMap { k in set.values[k].map { labText(k, $0, sex: r.sex) } }.joined(separator: ", "))
        case .blood:
            // The total goes on in chips(), from the chips left on.
            return (destination, f.label)
        case .infusion(let drug, let rate), .intraopInfusion(let drug, let rate):
            let unit = rate.contains(where: { $0.isLetter })
            return (f.section == PatientNote.Part.meds ? "Infusions" : destination,
                    capitalized(drug) + (rate.isEmpty ? "" : " " + rate) + (rate.isEmpty || unit ? "" : " (no unit)"))
        case .procedure(let p):
            let items = PlannedProcedure.parse(p).map(\.text).filter { !$0.isEmpty }
            return (destination, items.isEmpty ? p : items.joined(separator: " + "))
        case .nkda:
            return ("Allergies", "NKDA")
        case .allergies(let a):
            return ("Allergies", a)
        case .devices(let ds):
            return (destination, f.label + (ds.allSatisfy(\.placedIntraop) && !ds.isEmpty ? " (placed in the OR)" : ""))
        default:
            var label = f.label
            for p in labelPrefixes where label.hasPrefix(p) { label = String(label.dropFirst(p.count)) }
            return (destination, capitalized(label))
        }
    }
}

// MARK: - The intraoperative airway fields

extension PatientRecord {
    /// The intraoperative airway course by QuickAdd.airwayFields' names; nil when not recorded.
    func intraopAirway(_ key: String) -> String? {
        switch key {
        case "mask": return mask
        case "maskGrade": return maskGrade.map { String($0) }
        case "intubation": return intubation
        case "device": return airwayDevice
        case "grade": return laryngoscopyGrade
        case "attempts": return attempts.map { String($0) }
        case "tube": return tube.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : tube
        default: return nil
        }
    }

    mutating func setIntraopAirway(_ key: String, _ value: String) {
        switch key {
        case "mask": mask = value
        case "maskGrade": maskGrade = Int(value)
        case "intubation": intubation = value
        case "device": airwayDevice = value
        case "grade": laryngoscopyGrade = value
        case "attempts": attempts = Int(value)
        case "tube": tube = value
        default: break
        }
    }
}
