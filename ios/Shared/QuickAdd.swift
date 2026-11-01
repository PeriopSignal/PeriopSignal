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
    /// Ambiguous abbreviations whose meaning must be confirmed for its value ("levo 0.1"): the value, by choice key,
    /// and the keys whose choice was made for another value.
    var valueKeys: [String: String] = [:]
    var stale: Set<String> = []
    /// Lab keys already read, with the value filed (a second, different value is asked about).
    var labs: Set<String> = []
    var labValues: [String: Double] = [:]

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

/// A drip whose rate, written without a unit, gets one "by size": the Reference table's unit for a number in its
/// usual range; the weight-based unit for one that fits only that; none for one that could be either (added as
/// written); and nothing at all for one that fits no unit. Ranges are tried in that order, so a shared boundary goes
/// to the earlier one ("epi 2" is 2 mcg/min, "epi 1" is added as written).
struct QuickDrip {
    enum Fit: Equatable { case unit(String), asTyped, none }

    /// As the record names it ("epinephrine").
    let drug: String
    /// Its InfusionDrug id in reference.json.
    let reference: String
    /// The Reference table's unit ("mcg/min"), for a number in `usual`.
    let unit: String
    let usual: ClosedRange<Double>
    /// Numbers that could be in either unit, or that are larger than usual but could be another rate: as written.
    let overlap: ClosedRange<Double>?
    /// Numbers that fit only the weight-based unit (`unit` per kg).
    let perKg: ClosedRange<Double>?
    /// Read with a bare number; the others need "gtt", "drip", "infusion", "at" or "@".
    let bare: Bool
    /// The meaning an ambiguous alias must be read as, and whether the context or the user must have chosen it.
    let meaning: String?
    let confirm: Bool
    /// Group 1 the alias, group 2 the word that marks an infusion, group 3 the rate (with no unit after it).
    let rx: NoteRx

    init(_ drug: String, _ reference: String, _ aliases: String, unit: String, usual: ClosedRange<Double>, overlap: ClosedRange<Double>? = nil,
         perKg: ClosedRange<Double>? = nil, bare: Bool = true, meaning: String? = nil, confirm: Bool = false) {
        self.drug = drug
        self.reference = reference
        self.unit = unit
        self.usual = usual
        self.overlap = overlap
        self.perKg = perKg
        self.bare = bare
        self.meaning = meaning
        self.confirm = confirm
        rx = NoteRx(#"(?<![A-Za-z0-9])(?<![A-Za-z]-)("# + aliases + #")(?![A-Za-z0-9])\s*(?:((?:gtt|drip|infusion)s?\b\s*(?:(?:running at|at|of)\b|@)?|at\b|@)\s*|[=:]\s*)?(\d*\.\d+|\d+)(?![\d.:]|,\d|\s*[-–]\s*\d|\s*(?:mcg|mg|ug|µg|units?|u|ml|%|g|meq|ng|mmol)\b|\s*(?:kg|lbs?|cm|mm|mmhg|cc|l|lpm|bpm|yo|y/o|years?|yrs?|wks?|weeks?|days?|d|h|hrs?|hours?|mins?|minutes?|s|secs?|amps?|ampules?|vials?)\b|\s*[x×](?!\s*\d+\s*(?:days?|d|weeks?|wks?|months?|mos?|years?|yrs?|hours?|hrs?|h)\b)|\s*/)"#)
    }

    /// The weight-based unit: "mcg/min" per kg is "mcg/kg/min".
    var perKgUnit: String { unit.replacingOccurrences(of: "/min", with: "/kg/min") }

    /// The units a number in the overlap could be.
    var overlapUnits: [String] { perKg == nil ? [unit] : [unit, perKgUnit] }

    func fit(_ v: Double) -> Fit {
        if usual.contains(v) { return .unit(unit) }
        if let o = overlap, o.contains(v) { return .asTyped }
        if let k = perKg, k.contains(v) { return .unit(perKgUnit) }
        return .none
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

        // The note reader on what is left; a meaning chosen for another value ("levo" chosen at 0.1, now 0.2) is not used.
        let fresh = choices.filter { !out.stale.contains($0.key) }
        if tab == .intraop { for m in placedTiming.all(s.text) { s.mask(m.range) } }
        let note = PatientNote.read(s.text, now: now, abbreviations: user, choices: fresh, askRoomAir: false)
        let mine = Set(out.findings.map(\.id))
        for f in note.findings where !mine.contains(f.id) && !inferred(f) { route(f, one, c, &out) }
        // Its questions about two values of a lab ("Cr: 0.9 or 1.6?"), unless one is asked here already.
        for q in note.ambiguous where q.id.hasPrefix(PatientNote.labQuestionPrefix) && !out.questions.contains(where: { $0.id == q.id }) {
            out.questions.append(q)
        }
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
        reading.ambiguous = out.questions + MedAbbreviations.ambiguous(asked, in: base).map { a in
            var x = a
            if let v = out.valueKeys[a.id] { x.valueKey = v }
            return x
        }
        reading.unread = asTyped([note.other, note.previous].filter { !$0.isEmpty }.joined(separator: "; "), s.text,
                                 user: user, choices: fresh)
        return reading
    }

    /// Every pattern, for the test that each one compiles.
    static var allPatterns: [NoteRx] {
        var out = [recordTail, dateTail, nameTail, surnameTail, titleRx, roomAirWords, pieceNegation, vitaminBefore, fibBefore, bmpRx, cbcRx,
                   gasRx, gasWord, venousGas, gasLabel, bpRx, notBPBefore, vHR, vSpO2, vPercent, vRoomAir, vOxygen, vRR, vTemp, vBareTemp, vBare,
                   bloodBefore, bloodAfter, cellSaverAfter, cellSaverBefore, notGiven, offAfter, plannedLead, lineLead, lastFor, urgencyWord,
                   pastWords, detailWord, tubeRx, dltRx, gradeRx, gradeNotBefore, airwayContext, maskGradeRx, maskEaseRx, intubationEaseRx,
                   attemptsRx, inductionTiming, placedTiming, bolusCue, notDrip, ordinalAfter, ordinalBefore, notGivenAfter, beforeCase, totalWord, cellSaverWord,
                   cellSaverReturned, processedAfter, givenWord, unsureCue, clauseEnd, ofAfter, ofBefore, unitWordBefore, bloodJoin,
                   bloodHarmlessPhrase, asPlanned, bloodToken, doseAfter, doseBefore, trendAfter, earlierBefore, preopBefore, nowAfter, hemolyzed, cbcLabel,
                   gasTrend, gradeNotAfter, standbyAfter, standbyBefore, viewAfter, phraseEnd, scoreBefore, laryngoscopeAfter, laryngoscopeWord, maskCue, scheduleCue, codeCue, inductionCue, tivaCue, trendStop, venousWord, unitNumber,
                   productWord, countWord, totalBefore, totalAfter, statedTotal, techniqueWord]
        out += labAliases.map(\.rx) + dripUnits.map(\.rx) + airwayDevices.map { $0.0 }
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
                // A date already whole, or "born" to the end of the clause: nothing more.
                case "a date": tail = matched.first?.isNumber == true || matched.last?.isNumber == true || matched.lowercased().hasPrefix("born") ? nil : dateTail
                // "Mr Smith": one more name; "name is", "patient name": the name after it; a header ("Patient - Jane Doe")
                // already holds the words after it.
                case "a name":
                    if titleRx.first(matched) != nil {
                        tail = surnameTail
                    } else {
                        tail = ["name is", "named", "patient name", "pt name"].contains(matched.lowercased()) ? nameTail : nil
                    }
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
    private static let dateTail = NoteRx(#"^[\s:=]*(?:\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}|\d{4}-\d{1,2}-\d{1,2}|[A-Za-z]{3,9}\.?\s+\d{1,2},?\s+\d{2,4}|\d{1,2}(?:st|nd|rd|th)?\s+[A-Za-z]{3,9}\.?,?\s+\d{2,4})"#)
    /// After "name is": a word, and up to two more that are capitalized (not an abbreviation such as "HTN").
    private static let nameTail = NoteRx(#"^[\s:=]*[A-Za-z][A-Za-z'’-]*(?:\s+[A-Z][a-z'’-]+){0,2}"#, caseSensitive: true)
    /// After "Mr Smith": one more name ("Mr John Smith").
    private static let surnameTail = NoteRx(#"^\s+[A-Z][A-Za-z'’-]*[a-z][A-Za-z'’-]*"#, caseSensitive: true)
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
    static let historyElsewhere = "History, exam, symptoms and home medicines · on the Preop tab"

    /// The preoperative history, assessment and home medicines: never filed from what happens in the OR ("new AF after
    /// bypass", "metoprolol 5 mg IV").
    private static func preoperativeOnly(_ change: PatientNoteChange) -> Bool {
        switch change {
        case .problem, .noHistory, .smoking, .medFlag, .medications, .symptom, .acute, .mets, .frail, .otherHistory, .anesthesiaHistory,
             .anesthesiaNotes, .dentition, .airwaySign, .mallampati:
            return true
        default:
            return false
        }
    }

    private static func route(_ f: PatientNoteFinding, _ line: String, _ c: QuickContext, _ out: inout QuickOut) {
        var f = f
        if c.tab == .intraop, preoperativeOnly(f.change) { return out.skip(historyElsewhere) }
        switch f.change {
        case .procedure:
            // The bar reads the planned procedure itself.
            return
        case .vital(let k, let v):
            guard c.tab == .preop else { return out.skip(vitalsElsewhere) }
            if k == "spo2" {
                if f.note == PatientNote.roomAirUnstated {
                    f.note = nil
                    return addSpO2(f, v, roomAir: roomAirStated(line, c), c, &out)
                }
                if f.note != nil { return out.skip(oxygenNotice(v)) }
                return addSpO2(f, v, roomAir: true, c, &out)
            }
            out.add(f)
        case .lab(let k, let v):
            addLab(k, v, c, &out)
        case .infusion(let drug, let rate):
            // Written as an infusion without a unit ("phenylephrine infusion at 50"): the unit by size, else as written.
            if let d = dripUnits.first(where: { $0.drug == drug }), let r = dripRate(rate, d, marked: true) {
                return out.add(infusionFinding(drug, r.rate, c, note: r.note))
            }
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
    /// ("SpO₂ 95% · room air?"); the answer is kept in `choices` under this id, with the value it was given for.
    static let roomAirQuestion = PatientNote.roomAirQuestion
    static let roomAirAnswer = PatientNote.roomAirAnswer
    static let oxygenAnswer = PatientNote.oxygenAnswer

    private static func oxygenNotice(_ v: Double) -> String { "SpO₂ " + NumText.short(v) + "% on oxygen · the field is SpO₂ on room air" }

    /// The field is SpO₂ on room air: filed when the line says room air, or once the user answers room air. On oxygen,
    /// or not answered, nothing goes into it.
    private static func addSpO2(_ f: PatientNoteFinding, _ v: Double, roomAir: Bool, _ c: QuickContext, _ out: inout QuickOut) {
        if roomAir { return out.add(f) }
        let asked = PatientNote.roomAir(v, c.choices)
        let answer = asked.answer
        if !out.questions.contains(where: { $0.id == roomAirQuestion }) { out.questions.append(asked.question) }
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
    private static func addLab(_ key: String, _ v: Double, _ c: QuickContext, _ out: inout QuickOut, note: String? = nil) {
        let k = c.tab == .intraop && key == "hco3" ? "hco3a" : key
        guard PatientLabs.isPlausible(k, v), PatientLabs.test(k) != nil else { return }
        if out.labs.contains(k) {
            // A second value for the same test (a panel and a name, or the name twice): asked, nothing filed until then.
            guard let old = out.labValues[k] else { return askLab(k, [v], c, &out) }
            guard old != v else { return }
            return askLab(k, [old, v], c, &out)
        }
        out.labs.insert(k)
        out.labValues[k] = v
        fileLab(k, v, c, &out, note: note)
    }

    /// Two values of a test, neither marked current: "Cr: 0.9 or 1.6?", filed once one is chosen.
    private static func askLab(_ k: String, _ values: [Double], _ c: QuickContext, _ out: inout QuickOut) {
        // A test this tab does not file: the notice, no question.
        guard c.tab == .preop ? preopLabKeys.contains(k) : IntraopLabs.keys.contains(k) else {
            if let v = values.first { fileLab(k, v, c, &out, note: nil) }
            return
        }
        let id = PatientNote.labQuestionPrefix + k
        var all = out.questions.first(where: { $0.id == id }).map { q in q.options.compactMap { Double($0.text) } } ?? []
        if let filed = out.labValues[k], !all.contains(filed) { all.append(filed) }
        for v in values where !all.contains(v) { all.append(v) }
        out.labs.insert(k)
        out.labValues[k] = nil
        out.questions.removeAll { $0.id == id }
        out.findings.removeAll { $0.id == "lab:" + k || $0.id == "intraop-lab:" + k }
        let asked = PatientNote.labChoice(k, all, c.choices)
        out.questions.append(asked.question)
        if let v = asked.value { fileLab(k, v, c, &out, note: nil) }
    }

    private static func fileLab(_ k: String, _ v: Double, _ c: QuickContext, _ out: inout QuickOut, note: String?) {
        guard let t = PatientLabs.test(k) else { return }
        switch c.tab {
        case .preop:
            guard preopLabKeys.contains(k) else { return out.skip(t.short + " " + t.format(v) + " · an intraoperative lab, on the Intraop tab") }
            out.add(PatientNoteFinding(id: "lab:" + k, section: PatientNote.Part.labs, label: labLabel(t, v), change: .lab(k, v), note: note))
        case .intraop:
            guard IntraopLabs.keys.contains(k) else { return out.skip(t.short + " " + t.format(v) + " · not an intraoperative lab") }
            var set = IntraopLabSet(time: c.now, values: [k: v])
            set.id = c.setID
            out.add(PatientNoteFinding(id: "intraop-lab:" + k, section: intraop, label: labLabel(t, v), change: .intraopLabs(set), note: note))
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
    /// "a fib", "in fib 130s", "AF": a rhythm, not a fibrinogen.
    private static let fibBefore = NoteRx(#"\b(?:a|af|in|atrial|v|vent|ventricular|rapid|new|fast|slow|paroxysmal|persistent|permanent|coarse|fine)[- ]?$"#)
    /// A dose given, not a lab value, said right next to the number: "bicarb 1 amp", "bicarb 50 given", "K 10 IV", "gave
    /// bicarb 50". "K 6.4 given insulin" is a potassium: "given" goes with the insulin.
    private static let doseAfter = NoteRx(#"^\s*(?:amps?\b|ampules?\b|ampoules?\b|vials?\b|iv\b|ivp\b|ivpb\b|im\b|po\b|sq\b|push(?:ed)?\b|meq\b(?!\s*/)|[x×]\s?\d|(?:given|gave)\b\s*(?:$|[,;.)]|iv\b|ivp\b|im\b|po\b|over\b|at\b|x\s?\d|now\b))"#)
    private static let doseBefore = NoteRx(#"\b(?:gave|give|giving|given|administered|push(?:ed)?|bolused|replete[ds]?\s+with)\s*$"#)
    /// After a trend's next number: a dose or blood, not the test's value ("Hb 6.9 then 2 PRBC", "K 6.4 then 1 amp").
    private static let trendStop = NoteRx(#"^\s*(?:[x×]\s?\d|runs?\b|amps?\b|ampules?\b|vials?\b|units?\b|u\b|mg\b|mcg\b|g\b|gm\b|meq\b|ml\b|cc\b|iv\b|im\b|po\b|bags?\b|doses?\b|tabs?\b|"# + product + #"(?![A-Za-z]))"#)
    /// The next value of a trend ("0.9 → 1.6", "11 -> 7.8", "0.9 to 1.6", "3.1 then 4.2").
    private static let trendAfter = NoteRx(#"^[\s,)\]]*(?:-+>|→|⟶|➝|=>|\bto\b|\bthen\b)\s*([-−]?\d+(?:\.\d+)?)(?!\d|\.\d|\s*/\s*\d|\s*(?:mg|mcg|ug|units?|u|meq|g|gm|ml|cc)\b(?!\s*/))"#)
    /// A value marked as earlier ("baseline Cr 1.1"); "now 1.6" after it is the current one. On the Intraoperative
    /// tab a preoperative value is earlier too.
    private static let earlierBefore = NoteRx(#"\b(?:baseline|prior|previous(?:ly)?|admission|admit|initial|outside|osh|historical|(?<!year )(?<!years )(?<!yr )(?<!-)old|yesterday(?:'s)?|last\s+(?:month|week|year)(?:'s)?)[\s:()\[\]]*$"#)
    private static let preopBefore = NoteRx(#"\b(?:pre-?op(?:erative)?|preoperative)[\s:()\[\]]*$"#)
    /// "venous" or "central venous" on the line: gas values read by name are not arterial ("venous pH 7.28 pCO2 55").
    private static let venousWord = NoteRx(#"\b(?:vbg|venous|capillary)\b(?!\s*(?:catheter|cath|line|access|sheath|cannula|pressure|thrombo\w*|duplex|insufficiency|stasis))"#)
    private static let nowAfter = NoteRx(#"^[\s,;()\[\]]*(?:now|currently|current|today|repeat|latest|new)\b[\s:()\[\]]*([-−]?\d+(?:\.\d+)?)(?!\d|\.\d|\s*/\s*\d)"#)
    private static let hemolyzed = NoteRx(#"\bh(?:a)?emoly[sz](?:ed|is)\b"#)
    static let hemolyzedNote = "Hemolyzed: may be falsely high."

    /// Ionized calcium in mmol/L is about 0.3 to 2.5; 3 to 7 is likely mg/dL (4.6–5.3 mg/dL is normal), asked as the
    /// SpO₂ is ("iCa 3.9 · mg/dL = 0.97 mmol/L?") and filed in mmol/L only once chosen.
    static let icaQuestion = "quick:ica"
    static let icaAnswer = "ica-mgdl"

    private static func askICa(_ v: Double, _ c: QuickContext, _ out: inout QuickOut) {
        let mmol = (v / 4.008 * 100).rounded() / 100
        let reading = "mg/dL = " + NumText.short(mmol) + " mmol/L"
        let asked = PatientNote.question(icaQuestion, "iCa " + NumText.short(v), value: NumText.short(v),
                                         options: [AbbreviationMeaning(reading, id: icaAnswer)], usual: icaAnswer, c.choices)
        let answer = asked.answer
        if !out.questions.contains(where: { $0.id == icaQuestion }) { out.questions.append(asked.question) }
        if answer == icaAnswer { addLab("ica", mmol, c, &out, note: "Read as " + NumText.short(v) + " " + reading + ".") }
    }

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
        var venousShown = false
        /// The value as filed: platelets and white cells in thousands, a base deficit as a negative base excess.
        func normal(_ key: String, _ v: Double) -> Double? {
            switch key {
            case "plt": return v >= 10_000 ? v / 1000 : v
            case "wbc": return v >= 1000 ? v / 1000 : v
            case "bd": return v >= 0 ? -v : nil
            default: return v
            }
        }
        for (key, m) in hits {
            guard !taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) else { continue }
            let before = ns.substring(to: m.range.location)
            let rest = ns.substring(from: m.range.location + m.range.length)
            if key == "k", vitaminBefore.first(before) != nil { continue }
            if key == "fibrinogen", fibBefore.first(before) != nil || rest.hasPrefix("s") { continue }
            if key == "glucose", !c.means("bs-sugar", at: m.range) { continue }
            guard group(m, 1, text) == nil, let first = number(m, 2, text) else { continue }
            if group(m, 3, text) != nil && key != "plt" && key != "wbc" { continue }
            if group(m, 4, text) != nil && key != "a1c" && key != "hct" { continue }
            guard var v = normal(key, first) else { continue }
            let k = key == "bd" ? "be" : (key == "co2" ? "hco3" : key)
            var r = m.range
            let p = around(m.range, in: text)
            func leave(_ why: String) {
                taken.append(r)
                s.mask(r)
                out.skip((s.original as NSString).substring(with: m.range).trimmingCharacters(in: .whitespaces) + " · " + why)
            }
            // A dose given is not a lab value.
            if doseAfter.first(rest) != nil || doseBefore.first(before) != nil {
                leave("a dose, not a lab value")
                continue
            }
            // A venous gas's values are not arterial ones.
            if ["ph", "paco2", "pao2"].contains(k), venousGas.first(text) != nil || venousWord.first(text) != nil {
                taken.append(r)
                s.mask(r)
                if !venousShown { out.skip("Venous gas · not an arterial gas, not added") }
                venousShown = true
                continue
            }
            // A goal or a threshold ("goal Hb 8 to 10") is no value.
            if PatientNote.labGoal.first(before) != nil {
                leave("a goal, not a value")
                continue
            }
            func cut(_ t: String, _ n: Int) -> String { (t as NSString).substring(from: n) }
            // The values written for the test: the first, with its marks before it ("baseline Cr", "now Hb"), then each
            // after it ("now 1.6" is current; after an arrow, "to" or "then", current only as the last word), and the
            // marks after each, in brackets or not ("Cr 1.1 (baseline)", "K 3.1 on admit", "Cr 1.6 now"). A
            // preoperative value is an earlier one on the Intraoperative tab only.
            let preopEarlier = c.tab == .intraop
            var values: [(v: Double, current: Bool, earlier: Bool)] = [
                (v, PatientNote.labCurrentBefore.first(before) != nil,
                 earlierBefore.first(before) != nil || (preopEarlier && preopBefore.first(before) != nil)),
            ]
            var later = rest
            while true {
                let last = values.count - 1
                if let e = PatientNote.labEarlierAfter.first(later) {
                    let word = (later as NSString).substring(with: e.range).lowercased()
                    if preopEarlier || !(word.contains("preop") || word.contains("pre-op")) { values[last].earlier = true }
                    r.length += e.range.length
                    later = cut(later, e.range.length)
                }
                if let n = PatientNote.labCurrentAfter.first(later) {
                    values[last].current = true
                    r.length += n.range.length
                    later = cut(later, n.range.length)
                }
                if let t = nowAfter.first(later), let next = number(t, 1, later).flatMap({ normal(key, $0) }) {
                    values.append((next, true, false))
                    r.length += t.range.length
                    later = cut(later, t.range.length)
                } else if let t = trendAfter.first(later), let next = number(t, 1, later).flatMap({ normal(key, $0) }),
                          trendStop.first(cut(later, t.range.location + t.range.length)) == nil {
                    values.append((next, PatientNote.labEnd.first(cut(later, t.range.location + t.range.length)) != nil, false))
                    r.length += t.range.length
                    later = cut(later, t.range.length)
                } else {
                    break
                }
            }
            // One value: filed unless marked earlier. Two or more: the one marked current, if exactly one is; otherwise
            // asked ("Cr: 1.1 or 1.6?"), and nothing filed until chosen.
            var distinct: [Double] = []
            for x in values where !distinct.contains(x.v) { distinct.append(x.v) }
            var current: [Double] = []
            for x in values where x.current && !x.earlier && !current.contains(x.v) { current.append(x.v) }
            let rk = c.tab == .intraop && k == "hco3" ? "hco3a" : k
            if values.allSatisfy({ $0.earlier }) {
                leave(distinct.count == 1 ? "an earlier value, not added" : "earlier values, not added")
                continue
            } else if distinct.count == 1 {
                v = distinct[0]
            } else if current.count == 1 {
                v = current[0]
            } else {
                taken.append(r)
                s.mask(r)
                let plausible = distinct.filter { PatientLabs.isPlausible(rk, $0) }
                if plausible.count > 1 {
                    askLab(rk, plausible, c, &out)
                } else if let only = plausible.first {
                    addLab(k, only, c, &out)
                } else {
                    out.skip((s.original as NSString).substring(with: r).trimmingCharacters(in: .whitespaces) + " · not a plausible value, not added")
                }
                continue
            }
            var note: String?
            if values.count > 1, v != values[0].v { note = "Was " + NumText.short(values[0].v) + (values[0].earlier ? " earlier" : "") + ": the current value is added." }
            if k == "k", hemolyzed.first(p.before + " " + p.after) != nil { note = hemolyzedNote }
            // Ionized calcium: mmol/L, or mg/dL once chosen, or nothing.
            if k == "ica", c.tab == .intraop || preopLabKeys.contains("ica"), !(0.3...2.5).contains(v) {
                taken.append(r)
                s.mask(r)
                if (3...7).contains(v) {
                    askICa(v, c, &out)
                } else {
                    out.skip("iCa " + NumText.short(v) + " · neither mmol/L nor mg/dL, not added")
                }
                continue
            }
            guard PatientLabs.isPlausible(rk, v) else {
                if r.length > m.range.length { leave("not a plausible value, not added") }
                continue
            }
            taken.append(r)
            s.mask(r)
            addLab(k, v, c, &out, note: note)
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
    /// A slashed count panel ("CBC 7.4/11/180") is not a gas.
    private static let cbcLabel = NoteRx(#"\b(?:cbc|h/h|h&h|hgb/hct|hb/hct|wbc)\b"#)
    /// Between two gases in a trend ("7.21/55/68 → 7.32/42/180"): the later one is the current one.
    private static let gasTrend = NoteRx(#"^\s*,?\s*(?:-+>|→|⟶|➝|=>|\bto\b|\bthen\b|\bnow\b|\brepeat(?:ed)?\b)\s*:?\s*(?:(?:abg|gas)\s*:?\s*)?$"#)

    private static func readGas(_ s: inout QuickScan, _ c: QuickContext, _ out: inout QuickOut) {
        // On the Intraoperative tab, or wherever "ABG" or "gas" is written; never a venous gas (its PO₂ is not a PaO₂).
        guard c.tab == .intraop || gasWord.first(s.text) != nil else { return }
        if venousGas.first(s.text) != nil || venousWord.first(s.text) != nil {
            // "venous 7.28/55/40", "central venous 7.30/50/38": left out, so no part of it is read as anything else.
            for m in gasRx.all(s.text) {
                s.mask(m.range)
                out.skip("Venous gas · not an arterial gas, not added")
            }
            return
        }
        let text = s.text
        let ns = text as NSString
        let all = gasRx.all(text)
        guard let firstGas = all.first, cbcLabel.first(around(firstGas.range, in: text).before) == nil else { return }
        // A trend: the last gas of the chain.
        var last = 0
        while last + 1 < all.count {
            let end = all[last].range.location + all[last].range.length
            guard gasTrend.first(ns.substring(with: NSRange(location: end, length: all[last + 1].range.location - end))) != nil else { break }
            last += 1
        }
        let m = all[last]
        guard let ph = number(m, 1, text), let co2 = number(m, 2, text), let o2 = number(m, 3, text),
              PatientLabs.isPlausible("ph", ph), PatientLabs.isPlausible("paco2", co2), PatientLabs.isPlausible("pao2", o2) else { return }
        // A PaCO₂ that low at a pH near normal is no gas.
        guard co2 >= 15 || ph < 7.3 else { return }
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
        var r = NSRange(location: firstGas.range.location, length: m.range.location + m.range.length - firstGas.range.location)
        if let label = gasLabel.first((text as NSString).substring(to: r.location)) {
            r = NSRange(location: label.range.location, length: r.location + r.length - label.range.location)
        }
        s.mask(r)
        let earlier = last > 0 ? "Earlier gas " + ns.substring(with: firstGas.range) + " left out: the last is added." : nil
        guard c.tab == .intraop else {
            return out.skip("Blood gas " + (text as NSString).substring(with: m.range) + " · on the Intraop tab")
        }
        var values: [(String, Double)] = [("ph", ph), ("paco2", co2), ("pao2", o2)]
        if let h = hco3 { values.append(("hco3a", h)) }
        if let b = be { values.append(("be", b)) }
        for (i, kv) in values.enumerated() { addLab(kv.0, kv.1, c, &out, note: i == 0 ? earlier : nil) }
    }

    // MARK: Vital signs

    /// A blood pressure: "BP 148/86", or a bare pair that a heart rate must follow to count.
    static let bpRx = NoteRx(#"(?<![\d./|<>:])(?:\b(bp|nibp|abp|art|blood pressure)\s*:?\s*)?(\d{2,3})\s*/\s*(\d{2,3})(?![\d./|<>%:])"#)
    /// Other pressures written as a pair (PA, RV, ventilator) are not the blood pressure.
    private static let notBPBefore = NoteRx(#"\b(?:pa|pap|pas|rv|lv|cvp|pcwp|wedge|mpap|swan|peep|ps|pip|vt|tv|bipap|cpap|niv|fio2|aug|augmentation)(?:\s+(?:pressures?|press|systolic|sys))?\s*(?:of|is|was|:|=)?\s*$"#)
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
    static let bloodAfter = NoteRx(#"(?<![A-Za-z])"# + product + #"\s*(?:[x×+:]\s*)?(\d{1,3})(?:\s*(u|units?|pools?|doses?|bags?)\b)?(?![\d.]|(?:st|nd|rd|th)\b|\s*(?:k\b|%|ml|mg|mcg))"#)
    static let cellSaverAfter = NoteRx(#"(?<![A-Za-z])(?:cell\s*-?\s*sav(?:er|ed)|cellsaver|cell\s*salvage|salvaged blood)(?:\s+(?:returned|given|back))?\s*:?\s*\+?\s*(\d{2,4})\s*(?:ml|cc)?(?![\d.])"#)
    static let cellSaverBefore = NoteRx(#"(?<![\w.])(\d{2,4})\s*(?:ml|cc)\s+(?:of\s+)?(?:cell\s*-?\s*sav(?:er|ed)|cellsaver|cell\s*salvage|salvaged blood)"#)
    /// Blood that is ordered or waiting, not given.
    private static let notGiven = NoteRx(#"\b(?:available|in (?:the )?room|cross-?matched|crossmatch|x-?matched|type and cross|t&c|ready|on hold|ordered|requested|consented|if needed|if|prn|standby|(?<!as )plan(?:ned|ning)?|pending|will (?:give|transfuse|hang|need|get|start)|to (?:give|transfuse|hang)|consider(?:ing)?|may need|might need|anticipated?)\b"#)

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
    /// "PRBC 3rd unit", "3rd unit of PRBC": one more unit, not three.
    static let ordinalAfter = NoteRx(#"(?<![A-Za-z])"# + product + #"\s*(?:#\s*)?(\d{1,2})(?:st|nd|rd|th)\b(?:\s+(unit|bag|pool)s?\b)?"#)
    static let ordinalBefore = NoteRx(#"(?<![\w.])(\d{1,2})(?:st|nd|rd|th)\s+(?:(unit|bag|pool)s?\s+(?:of\s+)?)?"# + product + #"(?![A-Za-z])"#)
    /// "unit 3 of PRBC": the third unit, one more.
    static let unitNumber = NoteRx(#"(?<![A-Za-z])(unit|bag)\s*#?\s*(\d{1,2})\s+(?:of\s+)?"# + product + #"(?![A-Za-z])"#)
    /// A product named anywhere, for the words around it to go with the nearest one.
    static let productWord = NoteRx(#"(?<![A-Za-z])"# + product + #"(?![A-Za-z])"#)
    /// Between a product and a word about it, only a count ("2 PRBC available", "PRBC x2 declined").
    private static let countWord = NoteRx(#"^(?:[+x×]?\d+(?:\.\d+)?(?:u|units?)?|x|×|u|units?|bags?|pools?|of|the|apheresis|doses?|were|was|is|are|been|now|just|already|all|[()#:,.-])$"#)
    /// Not given, said after the product: "2 PRBC not given", "2 FFP held", "PRBC x2 declined".
    private static let notGivenAfter = NoteRx(#"\b(?:not\s+(?:given|transfused|hung|started|needed|used)|never\s+(?:given|transfused|hung|used)|returned\s+to\s+(?:the\s+)?(?:(?:blood\s+)?bank|(?-i:BB))|sent\s+back|unused|held|holding|on hold|declined|refused|cancell?ed|wasted|deferred|discontinued|stopped)\b"#)
    /// Said to be given, next to the product ("2 PRBC given", "gave 2 FFP", "PRBC 3 of 4 hanging"); not "to be given".
    private static let givenWord = NoteRx(#"(?<!\bbe )(?<!\bto )\b(?:given|gave|transfused|transfusing|hung|hanging|running|infusing|infused|received|administered)\b"#)
    /// Blood that may not have been given yet, anywhere in the clause: the product is asked about unless said given.
    private static let unsureCue = NoteRx(#"\b(?:available|in (?:the )?room|cross-?matched|crossmatch|x-?matched|type and (?:cross|screen)|t&c|ready|on hold|ordered|requested|consented|if|prn|standby|(?<!as )plan(?:ned|ning|s)?|pending|will|to (?:give|transfuse|hang)|consider(?:ing)?|may need|might need|anticipated?|returned to|sent back|send back|blood bank|(?-i:BB)|cooler|on the way|coming)\b"#)
    /// Where a clause ends: a full stop, a semicolon or a new line.
    private static let clauseEnd = NoteRx(#"[;\n]|\.(?=\s|$)"#)
    /// "PRBC 3 of 4": the third unit of four, one more. "3 of 4 PRBC" could be that or three of the four: not read.
    static let ofAfter = NoteRx(#"(?<![A-Za-z])"# + product + #"\s*(?:#\s*)?(\d{1,2})(?:\s+of\s+|\s*/\s*)(\d{1,2})(?![\d./])"#)
    static let ofBefore = NoteRx(#"(?<![\w.+×/])(\d{1,2})(?:\s+of\s+(?:the\s+)?|\s*/\s*)(\d{1,2})\s+(?:(?:units?|bags?)\s+(?:of\s+)?)?"# + product + #"(?![A-Za-z])"#)
    /// Blood files without a question only when the rest of its part of the piece (split at "and", "&", "plus") is
    /// counts, products, units, "given" wording or a connector; any other word asks "given?". The words and phrases
    /// allowed, and how the rest is cut into words.
    private static let bloodJoin = NoteRx(#"\band\b|&|\bplus\b"#)
    private static let bloodHarmlessPhrase = NoteRx(#"\b(?:so far|to date|in total)\b"#)
    private static let asPlanned = NoteRx(#"\bas planned\b"#)
    private static let bloodToken = NoteRx(#"[A-Za-z]+|\d+(?:\.\d+)?[A-Za-z]*|\?"#)
    private static let bloodWords: Set<String> = [
        "u", "unit", "units", "bag", "bags", "pool", "pools", "dose", "doses", "apheresis", "of", "the", "x", "total", "cumulative",
        "ml", "cc", "given", "gave", "transfused", "transfusing", "hung", "hanging", "running", "infused", "infusing", "received",
        "administered", "and", "also", "then", "now", "more", "another", "additional", "were", "was", "been", "all",
        "prbc", "prbcs", "rbc", "rbcs", "red", "blood", "cells", "cell", "packed", "ffp", "plasma", "plt", "plts", "platelet",
        "platelets", "cryo", "cryoprecipitate", "whole", "ltowb", "saver", "cellsaver",
    ]
    private static let bloodNumberSuffixes: Set<String> = ["", "u", "unit", "units", "st", "nd", "rd", "th", "ml", "cc"]
    private static let unitWordBefore = NoteRx(#"\b(?:unit|bag)\s*#?\s*$"#)
    static let bloodQuestion = "quick:blood:"
    static let bloodGiven = "blood-given"
    static let bloodNotYet = "blood-not-given"

    private static func clauseRange(_ r: NSRange, in text: String) -> NSRange {
        var lo = 0
        var hi = (text as NSString).length
        for m in clauseEnd.all(text) {
            if m.range.location + m.range.length <= r.location {
                lo = Swift.max(lo, m.range.location + m.range.length)
            } else if m.range.location >= r.location + r.length {
                hi = Swift.min(hi, m.range.location)
                break
            }
        }
        return NSRange(location: lo, length: Swift.max(0, hi - lo))
    }

    /// Given before the case or somewhere else: not this case's.
    private static let beforeCase = NoteRx(#"\b(?:yesterday|overnight|last night|pre-?op(?:eratively)?|preoperative(?:ly)?|before (?:the )?(?:case|surgery|or|induction)|prior to (?:the )?(?:case|surgery|arrival|induction)|in (?:the )?(?:icu|ed|er|pacu|floor|ward|cath lab)|icu|osh|outside hospital|on the floor|days? ago)\b"#)
    /// A running total restated ("4 PRBC total"): the total, not more. A count is the total only with "total" right next
    /// to it; "2 PRBC (total 4)" is 2 more, with the total written beside it.
    private static let totalWord = NoteRx(#"\b(?:total|in total|cumulative|so far|to date)\b"#)
    private static let totalBefore = NoteRx(#"\b(?:total(?:\s+of)?|in total|cumulative)\s*:?\s*$"#)
    private static let totalAfter = NoteRx(#"^\s*(?:total|in total|so far|to date|cumulative)\b(?!\s*:?\s*\(?\d)"#)
    private static let statedTotal = NoteRx(#"\(?\s*(?:\btotal(?:\s+of)?\s*:?\s*(\d{1,3})|(\d{1,3})\s*(?:units?\s+)?total\b)\s*\)?"#)
    static let cellSaverWord = NoteRx(#"\b(?:cell\s*-?\s*sav(?:er|ed)|cellsaver|cell\s*salvage|salvaged blood)\b"#)
    /// The cell saver volume given back ("350 mL returned"), which is what is filed.
    static let cellSaverReturned = NoteRx(#"(?<![\d.])(\d{2,4})\s*(?:ml|cc)?\s*(?:returned|reinfused|re-infused|given back|back to (?:the )?patient)\b"#)
    /// The volume processed or collected, not given back.
    private static let processedAfter = NoteRx(#"^\s*(?:ml|cc)?\s*(?:processed|collected|suctioned|salvaged|spun|washed|in (?:the )?reservoir)\b"#)

    /// Each mention is its own finding ("cryo 10, 1 pool cryo": Cryo +10 and Cryo +5 (1 pool)), so either can be left
    /// out; the chips put the running total on the last one. Each count belongs to its product: a piece written product
    /// first ("PRBC 3 FFP 2") gives the number after a product to it, one written count first ("2 PRBC 3 FFP") the number
    /// before.
    private static func readBlood(_ s: inout QuickScan, _ c: QuickContext, _ out: inout QuickOut) {
        /// The line as blood reading starts: what earlier readers took (a gas, vital signs) is already blanked.
        let typed = s.text
        var mentions: [(key: String, n: Double, pools: Double, at: Int, total: Bool, ordinal: String?, stated: Double?, ask: Bool, typed: String)] = []
        /// The words of a kind ("ready", "not given", "yesterday") that go with the product at the range: those whose
        /// nearest product it is, with nothing but a count between ("2 PRBC given and 2 FFP ready": only the FFP is
        /// ready; "2 PRBC 2 FFP repeat TEG pending": the TEG is pending).
        func about(_ rx: NoteRx, _ r: NSRange, _ text: String) -> [NSRange] {
            let ns = text as NSString
            let piece = pieceRange(r, in: text)
            let pieceText = ns.substring(with: piece)
            let products = productWord.all(pieceText).map { shifted($0.range, piece.location) }
            func gap(_ p: NSRange, _ g: NSRange) -> Int {
                g.location >= p.location + p.length ? g.location - (p.location + p.length) : Swift.max(0, p.location - (g.location + g.length))
            }
            var found: [NSRange] = []
            for m in rx.all(pieceText) {
                let g = shifted(m.range, piece.location)
                guard let nearest = products.min(by: { gap($0, g) < gap($1, g) }), NSIntersectionRange(nearest, r).length > 0 else { continue }
                let lo = Swift.min(nearest.location + nearest.length, g.location + g.length)
                let hi = Swift.max(nearest.location, g.location)
                let between = hi > lo ? ns.substring(with: NSRange(location: lo, length: hi - lo)) : ""
                let real = between.split(whereSeparator: { $0.isWhitespace }).filter { countWord.first(String($0)) == nil }
                if real.isEmpty { found.append(g) }
            }
            return found
        }
        /// The words in the product's clause that it may not be given yet: in its piece, in a piece before it ("plan: 2
        /// PRBC, 2 FFP", "if Hb < 7, give 2 PRBC"), or ending the list of blood it is in ("2 PRBC, 2 FFP ready"). Looked
        /// for as typed, so a word masked for one product still counts for the next.
        func unsureCues(_ r: NSRange) -> [NSRange] {
            let ns = s.original as NSString
            let clause = clauseRange(r, in: s.original)
            var pieces: [NSRange] = []
            var start = clause.location
            let end = clause.location + clause.length
            for i in clause.location..<end where ns.character(at: i) == 44 {
                pieces.append(NSRange(location: start, length: i - start))
                start = i + 1
            }
            pieces.append(NSRange(location: start, length: end - start))
            guard let at = pieces.firstIndex(where: { NSLocationInRange(r.location, $0) }) else { return [] }
            func cues(_ p: NSRange) -> [NSRange] { unsureCue.all(ns.substring(with: p)).map { shifted($0.range, p.location) } }
            var found = pieces[..<at].flatMap { cues($0) } + cues(pieces[at])
            for p in pieces[(at + 1)...] {
                let c = cues(p)
                found += c
                if !c.isEmpty || productWord.first(ns.substring(with: p)) == nil { break }
            }
            return found
        }
        /// The product's part of its piece: the piece, within its sentence, cut at "and", "&" or "plus" ("2 PRBC given
        /// and 2 FFP ready").
        func segment(_ r: NSRange) -> NSRange {
            let piece = NSIntersectionRange(pieceRange(r, in: typed), clauseRange(r, in: typed))
            var lo = piece.location
            var hi = piece.location + piece.length
            for m in bloodJoin.all((typed as NSString).substring(with: piece)) {
                let at = shifted(m.range, piece.location)
                if at.location + at.length <= r.location {
                    lo = Swift.max(lo, at.location + at.length)
                } else if at.location >= r.location + r.length {
                    hi = Swift.min(hi, at.location)
                    break
                }
            }
            return NSRange(location: lo, length: Swift.max(0, hi - lo))
        }
        /// The words in its part besides counts, products, units, "given" wording and connectors ("to be given",
        /// "thawing", "in OR", "for Hb 6.8"): any one of them makes the product a question.
        func otherWords(_ r: NSRange, _ seg: NSRange) -> [String] {
            let blanked = (typed as NSString).replacingCharacters(in: r, with: String(repeating: " ", count: r.length)) as NSString
            var rest = blanked.substring(with: seg)
            let said = givenWord.first(rest) != nil
            let phrases = said ? [bloodHarmlessPhrase, asPlanned] : [bloodHarmlessPhrase]
            for rx in phrases {
                rest = rx.re?.stringByReplacingMatches(in: rest, options: [], range: NSRange(location: 0, length: (rest as NSString).length), withTemplate: " ") ?? rest
            }
            return bloodToken.all(rest).compactMap { m -> String? in
                let w = (rest as NSString).substring(with: m.range).lowercased()
                if let first = w.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) {
                    let suffix = String(w.drop { $0.isNumber || $0 == "." })
                    return bloodNumberSuffixes.contains(suffix) ? nil : w
                }
                return bloodWords.contains(w) ? nil : w
            }
        }
        /// Whether the product at the range was given in this case. Said not given, or given before the case: masked and
        /// shown. Any word in its part of the piece that is not a count, a unit, "given" wording or a connector: asked,
        /// and filed only once answered given. Otherwise, said given: given; a word earlier in the clause or ending its
        /// list that it may not be given yet ("plan:", "if", "ready"): asked. The cell saver is never asked.
        enum Status { case given, notGiven, ask }
        func status(_ r: NSRange, _ text: String, asks: Bool = true) -> Status {
            let p = around(r, in: text)
            if pieceNegation.first(p.before) != nil { return .notGiven }
            /// Leaves the product out, masking it and the words of that kind in its piece (shown, not left as unread text).
            func leave(_ rx: NoteRx, _ why: String) -> Status {
                s.mask(r)
                let piece = pieceRange(r, in: text)
                for m in rx.all((text as NSString).substring(with: piece)) { s.mask(shifted(m.range, piece.location)) }
                out.skip(why)
                return .notGiven
            }
            if about(notGivenAfter, r, text).contains(where: { $0.location >= r.location + r.length }) {
                return leave(notGivenAfter, "Blood products not given · not added")
            }
            if !about(beforeCase, r, text).isEmpty { return leave(beforeCase, "Blood given before the case or elsewhere · not this case's, not added") }
            guard asks else {
                if !about(notGiven, r, text).isEmpty { return leave(notGiven, "Blood products ordered, planned or available · not given, not added") }
                return .given
            }
            let seg = segment(r)
            if !otherWords(r, seg).isEmpty {
                for m in unsureCue.all((typed as NSString).substring(with: seg)) { s.mask(shifted(m.range, seg.location)) }
                return .ask
            }
            if givenWord.first((typed as NSString).substring(with: seg)) != nil { return .given }
            let cues = unsureCues(r)
            guard !cues.isEmpty else { return .given }
            for m in cues { s.mask(m) }
            return .ask
        }
        func given(_ r: NSRange, _ text: String) -> Bool { status(r, text, asks: false) == .given }
        func add(_ key: String, _ n: Double, _ r: NSRange, _ text: String, pools: Double = 0, ordinal: String? = nil, ask: Bool = false) {
            let p = around(r, in: text)
            let ns = text as NSString
            let piece = pieceRange(r, in: text)
            let counted = ordinal == nil && key != BloodProducts.cellSaver
            let total = counted && (totalBefore.first(p.before) != nil || totalAfter.first(p.after) != nil)
            var stated: Double?
            s.mask(r)
            if total {
                for m in totalWord.all(ns.substring(with: piece)) { s.mask(shifted(m.range, piece.location)) }
            } else if counted {
                // A total written beside the count ("2 PRBC (total 4)"): kept to check, and not left as unread text.
                for m in statedTotal.all(ns.substring(with: piece)) {
                    let at = shifted(m.range, piece.location)
                    guard NSIntersectionRange(at, r).length == 0, let v = number(m, 1, ns.substring(with: piece)) ?? number(m, 2, ns.substring(with: piece))
                    else { continue }
                    stated = v
                    s.mask(at)
                    break
                }
            }
            let typed = (s.original as NSString).substring(with: r).trimmingCharacters(in: .whitespaces)
            mentions.append((key: key, n: n, pools: pools, at: r.location, total: total, ordinal: ordinal, stated: stated, ask: ask, typed: typed))
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
        /// Reads one mention; true when it used the range (added, or shown as not given), so no other reading takes it.
        func entry(_ key: String, _ n: Double, unit: String?, _ r: NSRange, _ text: String) -> Bool {
            guard n == n.rounded() else { return false }
            let st = status(r, text)
            guard st != .notGiven else { return (s.text as NSString).substring(with: r).trimmingCharacters(in: .whitespaces).isEmpty }
            let u = (unit ?? "").lowercased()
            if key == "cryo" {
                if u.hasPrefix("pool") {
                    guard (1...5).contains(n) else { return false }
                    add(key, n * 5, r, text, pools: n, ask: st == .ask)
                    return true
                }
                // "2 cryo" could be units or pools: not read.
                if n < 5 {
                    s.mask(r)
                    out.skip("Cryo " + NumText.short(n) + " · units or pools? Write “2 pools cryo” or “cryo 10”")
                    return true
                }
            }
            guard plausible(key, n) else { return false }
            add(key, n, r, text, ask: st == .ask)
            return true
        }

        // "PRBC 3rd unit": one more.
        var text = s.text
        for (rx, n, w, u) in [(ordinalAfter, 2, 1, 3), (ordinalBefore, 1, 3, 2), (unitNumber, 2, 3, 1)] {
            text = s.text
            for m in rx.all(text) {
                guard let o = group(m, n, text), let v = Int(o), (1...30).contains(v), let word = group(m, w, text) else { continue }
                let key = productKey(word)
                let matched = (text as NSString).substring(with: m.range)
                let suffix = matched.range(of: #"(?<=\d)(?:st|nd|rd|th)"#, options: [.regularExpression, .caseInsensitive])
                    .map { String(matched[$0]).lowercased() } ?? "th"
                let unit = (group(m, u, text) ?? "unit").lowercased()
                let ordinal = rx.pattern == unitNumber.pattern ? unit + " " + o : o + suffix + " " + unit
                let st = status(m.range, text)
                guard st != .notGiven else { continue }
                if key == "cryo" {
                    s.mask(m.range)
                    out.skip("Cryo " + ordinal + " · units or pools? Write “1 pool cryo” or “cryo 5”")
                    continue
                }
                guard key != BloodProducts.cellSaver else { continue }
                add(key, 1, m.range, text, ordinal: ordinal, ask: st == .ask)
            }
        }
        // "PRBC 3 of 4", "PRBC 3/4": unit 3 of 4, one more. "3 of 4 PRBC": unit 3, or three of the four? Not read.
        text = s.text
        for m in ofAfter.all(text) {
            guard let word = group(m, 1, text), let o = group(m, 2, text), let all = group(m, 3, text), let v = Int(o), let t = Int(all),
                  (1...30).contains(v), v <= t else { continue }
            let key = productKey(word)
            let st = status(m.range, text)
            guard st != .notGiven else { continue }
            if key == "cryo" {
                s.mask(m.range)
                out.skip("Cryo unit " + o + " of " + all + " · units or pools? Write “1 pool cryo” or “cryo 5”")
                continue
            }
            add(key, 1, m.range, text, ordinal: "unit " + o + " of " + all, ask: st == .ask)
        }
        text = s.text
        for m in ofBefore.all(text) {
            guard let o = group(m, 1, text), let all = group(m, 2, text), let word = group(m, 3, text) else { continue }
            // "unit 3 of 4 PRBC": the unit, one more.
            if let u = unitWordBefore.first((text as NSString).substring(to: m.range.location)), let v = Int(o), let t = Int(all), v <= t,
               productKey(word) != "cryo" {
                let r = NSRange(location: u.range.location, length: m.range.location + m.range.length - u.range.location)
                let st = status(r, text)
                guard st != .notGiven else { continue }
                add(productKey(word), 1, r, text, ordinal: "unit " + o + " of " + all, ask: st == .ask)
                continue
            }
            s.mask(m.range)
            let name = BloodProducts.units.first(where: { $0.id == productKey(word) })?.short ?? word
            out.skip(o + " of " + all + " " + name + " · unit " + o + ", or " + o + " units? Write “" + name + " +1” or “" + name + " +" + o + "”")
        }

        text = s.text
        let candidates: [(m: NSTextCheckingResult, after: Bool)] = bloodBefore.all(text).map { (m: $0, after: false) }
            + bloodAfter.all(text).map { (m: $0, after: true) }
        func productRange(_ c: (m: NSTextCheckingResult, after: Bool)) -> NSRange { c.m.range(at: c.after ? 1 : 4) }
        /// Written product first: the piece's first product has no count before it.
        func productFirst(_ piece: NSRange) -> Bool {
            let inPiece = candidates.filter { NSLocationInRange(productRange($0).location, piece) }
            guard let at = inPiece.map({ productRange($0).location }).min() else { return false }
            return !inPiece.contains { !$0.after && productRange($0).location == at }
        }
        var taken: [NSRange] = []
        for preferred in [true, false] {
            for cand in candidates.sorted(by: { $0.m.range.location < $1.m.range.location }) {
                let m = cand.m
                guard (productFirst(pieceRange(m.range, in: text)) == cand.after) == preferred,
                      !taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) else { continue }
                // Both patterns: the count is group 2 and the unit or pool word group 3; the product is 1 after, 4 before.
                guard let word = group(m, cand.after ? 1 : 4, text), let n = number(m, 2, text) else { continue }
                let unit = group(m, 3, text)
                let key = productKey(word)
                // "plt 96" is a count: a platelet dose is written 1 to 4.
                if cand.after, key == "platelets", n > 4 { continue }
                if entry(key, n, unit: unit, m.range, text) { taken.append(m.range) }
            }
        }

        // Cell saver: the volume returned, not the volume processed.
        for rx in [cellSaverBefore, cellSaverAfter] {
            text = s.text
            for m in rx.all(text) {
                guard let n = number(m, 1, text), (25...5000).contains(n) else { continue }
                let rest = (text as NSString).substring(from: m.range.location + m.range.length)
                if let p = processedAfter.first(rest) {
                    s.mask(NSRange(location: m.range.location, length: m.range.length + p.range.length))
                    out.skip("Cell saver " + NumText.short(n) + " mL processed · the volume returned is what is added")
                    continue
                }
                guard given(m.range, text) else { continue }
                add(BloodProducts.cellSaver, n, m.range, text)
            }
        }
        if cellSaverWord.first(s.original) != nil {
            text = s.text
            for m in cellSaverReturned.all(text) {
                guard let n = number(m, 1, text), (25...5000).contains(n), given(m.range, text) else { continue }
                add(BloodProducts.cellSaver, n, m.range, text)
            }
        }

        var running: [String: Double] = [:]
        var counts: [String: Int] = [:]
        var asked: [String: Int] = [:]
        for m in mentions.sorted(by: { $0.at < $1.at }) {
            // Maybe not given yet: "2 PRBC given?", filed only once answered given.
            if m.ask {
                let q = (asked[m.key] ?? 0) + 1
                asked[m.key] = q
                let a = PatientNote.question(bloodQuestion + m.key + (q > 1 ? ":" + String(q) : ""), m.typed,
                                             value: NumText.short(m.n) + (m.ordinal.map { " " + $0 } ?? ""),
                                             options: [AbbreviationMeaning("given", id: bloodGiven), AbbreviationMeaning("not given yet", id: bloodNotYet)],
                                             usual: bloodGiven, c.choices)
                out.questions.append(a.question)
                guard a.answer == bloodGiven else { continue }
            }
            let isCellSaver = m.key == BloodProducts.cellSaver
            let name = isCellSaver ? "Cell saver" : (BloodProducts.units.first(where: { $0.id == m.key })?.short ?? m.key)
            let have = (c.record.fluids[m.key] ?? 0) + (running[m.key] ?? 0)
            var n = m.n
            var note: String?
            if m.total {
                // The total written: only what it adds to what is recorded.
                n = m.n - have
                guard n > 0 else {
                    let why = n == 0 ? "already recorded" : "the record has " + NumText.short(have) + "; change it on the Fluids card"
                    out.skip(name + " total " + NumText.short(m.n) + " · " + why)
                    continue
                }
                note = "Written as the total, " + NumText.short(m.n) + ": adds " + NumText.short(n) + " to the " + NumText.short(have) + " recorded."
            }
            guard have + n <= (isCellSaver ? 20000 : 199) else { continue }
            running[m.key] = (running[m.key] ?? 0) + n
            let k = (counts[m.key] ?? 0) + 1
            counts[m.key] = k
            var label = name + " +" + NumText.short(n) + (isCellSaver ? " mL" : "")
            if m.pools > 0 {
                label += " (" + NumText.short(m.pools) + " pool" + (m.pools == 1 ? "" : "s") + ")"
                note = poolNote
            }
            if let o = m.ordinal {
                label += " (" + o + ")"
                note = (o.hasPrefix("unit") || o.hasPrefix("bag") ? "U" + o.dropFirst() : "The " + o) + ": one more."
            }
            if let stated = m.stated, stated != have + n {
                note = "The line says " + NumText.short(stated) + " in all; with this, the record has " + NumText.short(have + n) + "."
            }
            out.add(PatientNoteFinding(id: "blood:" + m.key + (k > 1 ? ":" + String(k) : ""), section: intraop, label: label,
                                       change: .blood(m.key, n), note: note))
        }
    }

    // MARK: Drips

    /// Drips and the unit their rate gets "by size" (QuickDrip). The eight on top are read with a bare rate ("epi 0.05");
    /// the others only when written as an infusion ("NTG gtt 50", "remi @ 0.1"). "levo" is read only once its meaning
    /// is chosen (levothyroxine 0.1 mg is a dose). The units are the Reference infusion table's (reference.json), and
    /// QuickAddTests checks them against it; the ranges are its label ranges.
    static let dripUnits: [QuickDrip] = [
        QuickDrip("epinephrine", "epinephrine", #"epinephrine|adrenaline|epi"#, unit: "mcg/min", usual: 2...40, overlap: 1...2, perKg: 0.01...1,
                  meaning: "epi-epinephrine"),
        QuickDrip("norepinephrine", "norepinephrine", #"norepinephrine|noradrenaline|norepi|levophed|(?-i:NE)"#, unit: "mcg/min", usual: 2...40,
                  overlap: 1...2, perKg: 0.01...1),
        QuickDrip("norepinephrine", "norepinephrine", #"levo"#, unit: "mcg/min", usual: 2...40, overlap: 1...2, perKg: 0.01...1,
                  meaning: "levo-norepinephrine", confirm: true),
        QuickDrip("phenylephrine", "phenylephrine", #"phenylephrine|neo-?synephrine|phenyl|neo"#, unit: "mcg/min", usual: 5...300, overlap: 2...5,
                  perKg: 0.1...2, meaning: "neo-phenylephrine"),
        QuickDrip("propofol", "propofol", #"propofol|diprivan|prop"#, unit: "mcg/kg/min", usual: 5...300, overlap: 0.01...5),
        // Vasopressin and milrinone outside their infusion range are not read as drips ("vaso 1", "milrinone 50" are boluses).
        QuickDrip("vasopressin", "vasopressin", #"vasopressin|vasostrict|vaso"#, unit: "units/min", usual: 0.01...0.2),
        QuickDrip("milrinone", "milrinone", #"milrinone|milri"#, unit: "mcg/kg/min", usual: 0.1...1),
        QuickDrip("dobutamine", "dobutamine", #"dobutamine|dobuta|dobut"#, unit: "mcg/kg/min", usual: 1...40),
        QuickDrip("dopamine", "dopamine", #"dopamine|dopa"#, unit: "mcg/kg/min", usual: 1...50),
        QuickDrip("nitroglycerin", "nitroglycerin", #"nitroglycerin|ntg|tng|nitro"#, unit: "mcg/min", usual: 5...200, bare: false),
        QuickDrip("nitroprusside", "nitroprusside", #"nitroprusside|nipride|snp"#, unit: "mcg/kg/min", usual: 0.3...10, bare: false),
        QuickDrip("esmolol", "esmolol", #"esmolol|brevibloc"#, unit: "mcg/kg/min", usual: 50...300, bare: false),
        QuickDrip("remifentanil", "remifentanil", #"remifentanil|ultiva|remi"#, unit: "mcg/kg/min", usual: 0.025...2, bare: false),
        QuickDrip("dexmedetomidine", "dexmedetomidine", #"dexmedetomidine|precedex|dexmed|dex"#, unit: "mcg/kg/h", usual: 0.2...1, bare: false,
                  meaning: "dex-dexmedetomidine"),
        QuickDrip("nicardipine", "nicardipine", #"nicardipine|cardene|nicard"#, unit: "mg/h", usual: 3...15, bare: false),
        QuickDrip("clevidipine", "clevidipine", #"clevidipine|cleviprex|clevi"#, unit: "mg/h", usual: 1...32, bare: false),
    ]
    private static let offAfter = NoteRx(#"^\s*(?:off|stopped|weaned|held|d/c'?d|discontinued)\b"#)
    /// A bolus, not a drip: "gave neo 100", "epi 10 push", "neo 100 x2", "prn", a route a drip does not take.
    static let bolusCue = NoteRx(#"\b(?:bolus(?:es|ed)?|push(?:es|ed)?|gave|given|give|prn|im|ivp|sq|subq|sc)\b|(?<![A-Za-z])[x×]\s?\d+(?!\d)(?!\s*(?:days?|d|weeks?|wks?|months?|mos?|years?|yrs?|hours?|hrs?|h)\b)|\d\s?[x×](?![A-Za-z])"#)
    /// A dose by the clock or a schedule, not a drip: "q3min", "tid", "3 times daily".
    static let scheduleCue = NoteRx(#"\b(?:tid|bid|qid|qhs|qd|qam|qpm|daily|nightly|weekly|times\s+(?:a\s+|per\s+)?(?:day|daily|week)|q\s?\d+\s*(?:h|hr|hrs|hours?|min|mins|minutes?))\b"#)
    /// A code: epinephrine and vasopressin are 1 mg and 40 unit boluses, not drips (ROSC is not a cue: infusions follow it).
    static let codeCue = NoteRx(#"(?-i:\b(?:VF|VT|PEA|ACLS|CPR|AED)\b)|(?<!full )(?<!no )\bcode(?:\s+blue)?\b(?!\s*status)|\b(?:arrest(?:ed)?|asystole|asystolic|v-?fib|vfib|v-?tach|pulseless|compressions|defib(?:rillat\w*)?)\b|\bshock(?:ed)?\s*(?:x\s*\d+\s*)?(?:at\s*)?\d+\s*j\b"#)
    /// An induction: a bare propofol number is the induction dose, not a drip ("prop 200, roc 50, fent 100").
    static let inductionCue = NoteRx(#"\b(?:induction|induced?|rsi|roc(?:uronium)?|vec(?:uronium)?|cis(?:atracurium)?|sux|succ(?:inylcholine)?|fent(?:anyl)?|sufent(?:anil)?|etomidate|etom|ketamine|midaz(?:olam)?|versed)\b|\blido(?:caine)?\s*\d+(?:\.\d+)?\s*(?:mg\b)?"#)
    static let tivaCue = NoteRx(#"\btiva\b"#)
    static let noUnitNote = "No unit written: added as written, without one."
    /// Not a drip in this piece: levodopa ("L-dopa", "L dopa"), or a local anesthetic (with its epinephrine:
    /// "lidocaine 1% with epi 1:200,000").
    static let notDrip = NoteRx(#"\b(?:levodopa|carbidopa|l[- ]?dopa|sinemet|rytary|lido(?:caine)?|ropi(?:vacaine)?|bupi(?:vacaine)?|marcaine|sensorcaine|naropin|chloroprocaine|mepivacaine|articaine|prilocaine)\b"#)

    private static func infusionFinding(_ drug: String, _ rate: String, _ c: QuickContext, note: String?) -> PatientNoteFinding {
        let label = "Infusion: " + drug + (rate.isEmpty ? "" : " at " + rate)
        if c.tab == .intraop {
            return PatientNoteFinding(id: "intraop-infusion:" + drug, section: intraop, label: label, change: .intraopInfusion(drug, rate), note: note)
        }
        return PatientNoteFinding(id: "infusion:" + drug, section: PatientNote.Part.meds, label: label, change: .infusion(drug, rate), note: note)
    }

    /// A rate written without a unit, with the unit it gets by size and the line saying so; nil when the number fits
    /// no unit. `marked`: written as an infusion ("gtt", "@"), so a number that fits none is kept as written.
    static func dripRate(_ rate: String, _ d: QuickDrip, marked: Bool) -> (rate: String, note: String)? {
        guard let v = num(rate) else { return nil }
        let typed = rate.hasPrefix(".") ? "0" + rate : rate
        switch d.fit(v) {
        case .unit(let u):
            return (typed + " " + u, "No unit written: read as " + u + ".")
        case .asTyped:
            let units = d.overlapUnits
            return (typed, units.count > 1 ? "No unit written: " + typed + " could be " + units.joined(separator: " or ") + ", so it is added as written."
                                          : noUnitNote)
        case .none:
            return marked ? (typed, noUnitNote) : nil
        }
    }

    private static func readDrips(_ s: inout QuickScan, _ c: QuickContext, _ out: inout QuickOut) {
        for d in dripUnits {
            let text = s.text
            for m in d.rx.all(text) {
                guard let rate = group(m, 3, text), num(rate) != nil else { continue }
                let marked = m.range(at: 2).location != NSNotFound
                if !d.bare && !marked { continue }
                if let meaning = d.meaning {
                    // A meaning confirmed for another value ("levo" chosen at 0.1, now 0.2) is asked again.
                    let key = c.abbreviation(at: m.range(at: 1))?.choiceKey ?? ""
                    if d.confirm, !key.isEmpty {
                        out.valueKeys[key] = rate
                        if let tied = c.choices[key + "@value"], tied != rate {
                            out.stale.insert(key)
                            continue
                        }
                    }
                    if !c.means(meaning, at: m.range(at: 1), confirmed: d.confirm) { continue }
                }
                let p = around(m.range, in: text)
                let piece = p.before + " " + p.after
                if pieceNegation.first(p.before) != nil || offAfter.first(p.after) != nil || bolusCue.first(piece) != nil
                    || notDrip.first(piece) != nil || scheduleCue.first(piece) != nil {
                    continue
                }
                // An induction sequence's propofol, and a code's epinephrine or vasopressin, are boluses.
                if d.drug == "propofol", !marked, tivaCue.first(s.original) == nil, inductionCue.first(s.original) != nil { continue }
                // In a code, only an infusion-sized number is read: epinephrine of weight-based size (code doses are 1 mg,
                // push-dose epinephrine 10–20 mcg) or vasopressin in units/min.
                if d.drug == "epinephrine" || d.drug == "vasopressin", codeCue.first(s.original) != nil, let v = num(rate),
                   d.fit(v) != .unit(d.drug == "epinephrine" ? d.perKgUnit : d.unit) { continue }
                s.mask(m.range)
                if let r = dripRate(rate, d, marked: marked) {
                    out.add(infusionFinding(d.drug, r.rate, c, note: r.note))
                } else {
                    let typed = (s.original as NSString).substring(with: m.range).trimmingCharacters(in: .whitespaces)
                    out.skip("“" + typed + "” · fits no usual rate without a unit, not added")
                }
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
    /// A technique written in shorthand ("under block", "ACB", "TIVA", "LMA"): the plan is the user's, not filled.
    static let techniqueWord = NoteRx(#"(?-i:\b(?:GA|GETA|MAC|ACB|TAP|ESP|PENG|QL|ISB|SCB|FNB|SAB|CSE|LMA|TIVA)\b)|\b(?:blocks?|regional|spinal|epidural|neuraxial|sedation|ipack)\b"#)
    static let planNote = "The usual plan for the procedure, as the Procedure editor fills it."

    private static func isAnesthetic(_ f: PatientNoteFinding) -> Bool {
        if case .anesthetic = f.change { return true }
        return false
    }

    /// The planned anesthetic the Procedure editor fills from procedures on the list, when the record has none and the
    /// line names no technique (even one the reader did not take, as in "TKA, spinal"). A plan already set is never
    /// replaced.
    private static func readPlan(_ line: String, _ c: QuickContext, _ out: inout QuickOut) {
        let techniques = [PatientNote.gaRx, PatientNote.neuraxialRx, PatientNote.macRx, PatientNote.regionalRx, techniqueWord]
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
    /// A score's grade, never the airway's ("Mallampati 3", "ASA 3").
    private static let scoreBefore = NoteRx(#"\b(?:mallampati|mp|asa|nyha|ckd|ulbt)\s*$"#)
    /// A laryngoscope right after a grade ("gr 3 DL", "grade 2a with VL"), and one named later in its piece.
    private static let laryngoscopeAfter = NoteRx(#"^\s*(?:(?:on|with|via|by)\s+)?(?:(?-i:DL|VL)\b|mac\s*#?\s*[1-5]\b|miller\b|glide\s*scope|glidescope|glide\b|c-?mac\b|mcgrath\b|(?:video|direct)\s*laryngoscop\w*|laryngoscop\w*)"#)
    private static let laryngoscopeWord = NoteRx(#"(?-i:\b(?:DL|VL)\b)|\b(?:mac\s*#?\s*[1-5]|miller|glide\s*scope|glidescope|glide|c-?mac|mcgrath|(?:video|direct)\s*laryngoscop\w*|laryngoscop\w*)\b"#)
    private static let gradeNotBefore = NoteRx(#"\b(?:mask|mv|bmv|han|mallampati|mp|asa|nyha|ckd|ulbt|ventilation)\s*$"#)
    private static let airwayContext = NoteRx(#"(?-i:\b(?:VL|DL)\b)|\b(?:ett|et tube|endotracheal|intubat\w*|laryngoscop\w*|glide ?scope|glide|c-?mac|mcgrath|miller|mac\s*#?\s*[1-5]|view|cormack|lma|i-?gel|dlt|bougie|fob)\b"#)
    private static let maskGradeRx = NoteRx(#"\b(?:(?:bag[- ])?mask|mv|bmv)(?:\s+ventilation)?\s+(?:grade|gr\.?)\s*:?\s*([1-4])\b|\bhan\s*(?:grade)?\s*:?\s*([1-4])\b|\b(?:grade|gr\.?)\s*:?\s*([1-4])\s+(?:bag[- ])?(?:mask|mv|bmv)\b"#)
    /// After a grade: the mask, not the laryngoscopy ("grade 1 mask").
    private static let gradeNotAfter = NoteRx(#"^\s*(?:bag[- ])?(?:mask|mv|bmv|ventilation)\b"#)
    /// A device that was there but not used, said right next to it: "VL in room", "glidescope available", "backup LMA",
    /// "DL grade 1 with VL backup" (the VL).
    private static let standbyAfter = NoteRx(#"^\s*(?:(?:is|was|as|on)\s+)?(?:in (?:the )?room|available|avail|backup|back-?up|back up|standby|on standby|ready|at (?:the )?bedside|on hand|if needed|prn)\b"#)
    private static let standbyBefore = NoteRx(#"\b(?:backup|back-?up|back up|standby|available|spare)\s*:?\s*$"#)
    /// "view" right after a grade, and where a phrase ends.
    private static let viewAfter = NoteRx(#"^\s*view\b"#)
    private static let phraseEnd = NoteRx(#"\.(?:\s|$)|;|/"#)
    /// The mask named in a phrase, for a grade after it.
    private static let maskCue = NoteRx(#"\b(?:(?:bag[- ])?mask(?:ing)?|mv|bmv|ventilation)\b"#)
    /// The questions when two laryngoscopies are named, or one with two grades; the answer is kept in `choices` under the
    /// id, with the value it was given for.
    static let laryngoscopyQuestion = "quick:laryngoscopy"
    static let gradeQuestion = "quick:grade"
    /// A grade only a mask phrase points to, in a line that names a laryngoscope and no other grade: mask or view?
    static let gradeKindQuestion = "quick:gradekind"
    static let gradeKindMask = "gradekind-mask"
    static let gradeKindView = "gradekind-view"
    private static let maskEaseRx = NoteRx(#"\b(easy|difficult|diff)\s+(?:(?:bag[- ])?mask(?:ing)?|mv|bmv)(?:\s+ventilation)?\b|\b(?:(?:bag[- ])?mask(?:ing)?|mv|bmv)(?:\s+ventilation)?\s+(?:was\s+)?(easy|difficult|diff)\b"#)
    private static let intubationEaseRx = NoteRx(#"\b(easy|difficult|diff)\s+(?:intubation|(?-i:DL|VL)|laryngoscopy)\b|\bintubation\s+(?:was\s+)?(easy|difficult)\b"#)
    private static let attemptsRx = NoteRx(#"(?<![\w])(?:[x×]\s?([1-9])\s+attempts?|([1-9])\s+attempts?|(first|1st)[- ](?:attempt|pass)|(second|2nd)[- ]attempt|(third|3rd)[- ]attempt)\b"#)
    static let inductionTiming = NoteRx(#"\b(?:pre|post)-?\s?induction\b|\b(?:before|after)\s+induction\b"#)
    /// The other timing words that make a device list planned on the Preoperative tab; on the Intraoperative tab they
    /// say when it went in. Masked only for the note reader, after blood is read ("2 PRBC in the OR" is still asked).
    static let placedTiming = NoteRx(#"\b(?:before|after)\s+intubation\b|\bin the or\b|\bonce asleep\b"#)

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
        // The mask grade: "mask grade 2", "Han 2", "grade 1 mask", or a grade whose phrase names the mask before it with
        // no laryngoscopy between ("easy mask (grade 1)", "mask: grade 1", "Mask ventilation: grade 1").
        text = s.text
        let whole = NSRange(location: 0, length: (text as NSString).length)
        var maskGrade: (value: String, range: NSRange)?
        // A laryngoscope right after the grade makes it the view grade ("easy mask gr 3 DL").
        func scopeNext(_ r: NSRange) -> Bool {
            laryngoscopeAfter.first((text as NSString).substring(from: r.location + r.length)) != nil
        }
        if let m = maskGradeRx.first(text), let g = group(m, 1, text) ?? group(m, 2, text) ?? group(m, 3, text), !negated(m.range, text),
           !scopeNext(m.range) {
            maskGrade = (g, m.range)
        }
        func maskPhrase(_ text: String) -> Bool {
            // The phrase ends at a full stop, a semicolon or a slash ("Easy mask. Grade 3 view", "easy BMV/grade 3").
            let before = phraseEnd.all(text).last.map { (text as NSString).substring(from: $0.range.location + $0.range.length) } ?? text
            guard let mask = maskCue.all(before).last else { return false }
            guard let scope = airwayContext.all(before).last else { return true }
            return scope.range.location < mask.range.location
        }
        let context = airwayContext.first(text) != nil
        let grades = ["1": "1", "i": "1", "2a": "2a", "2b": "2b", "3": "3", "3a": "3", "3b": "3", "iii": "3", "4": "4", "iv": "4"]
        // The view grades, each with its range (nil for a bare "2", which needs 2a or 2b).
        var views: [(value: String?, range: NSRange)] = []
        let allGrades = gradeRx.all(text).filter { m in maskGrade.map { NSIntersectionRange($0.range, m.range).length == 0 } ?? true }
        for m in allGrades {
            guard let g = group(m, 1, text)?.lowercased() else { continue }
            let p = around(m.range, in: text)
            guard scoreBefore.first(p.before) == nil else { continue }
            // "Grade 3 view" and "gr 3 DL" are the view, whatever came before them.
            let view = viewAfter.first(p.after) != nil || scopeNext(m.range)
            if !view {
                guard gradeNotBefore.first(p.before) == nil else { continue }
                if gradeNotAfter.first(p.after) != nil || maskPhrase(p.before) {
                    guard maskGrade == nil, ["1", "2", "3", "4"].contains(g), !negated(m.range, text) else {
                        s.mask(m.range)
                        continue
                    }
                    // Only the phrase says mask, a laryngoscope follows later in the piece, and the line gives no other
                    // grade ("easy mask (grade 3) DL"): mask or view? Asked, filed once chosen.
                    if gradeNotAfter.first(p.after) == nil, laryngoscopeWord.first(p.after) != nil, allGrades.count == 1 {
                        let asked = PatientNote.question(gradeKindQuestion, "Grade " + g, value: g,
                                                         options: [AbbreviationMeaning("mask", id: gradeKindMask), AbbreviationMeaning("view", id: gradeKindView)],
                                                         usual: gradeKindView, c.choices)
                        out.questions.append(asked.question)
                        if asked.answer == gradeKindMask {
                            maskGrade = (g, m.range)
                        } else if asked.answer == gradeKindView {
                            views.append((value: grades[g], range: m.range))
                        } else {
                            s.mask(m.range)
                        }
                        continue
                    }
                    maskGrade = (g, m.range)
                    continue
                }
            }
            if context { views.append((value: grades[g], range: m.range)) }
        }
        if let mg = maskGrade {
            put("maskGrade", mg.value, "Mask grade " + mg.value, mg.range)
            s.mask(mg.range)
        }
        // Laryngoscopes in the order written; one said to be in the room, available or a backup was not used.
        var scopes: [(device: String, range: NSRange, certain: Bool)] = []
        for (rx, device) in airwayDevices {
            for m in rx.all(text) {
                let t = (text as NSString).substring(with: m.range).lowercased()
                if t.hasPrefix("mac"), !c.means("mac-blade", at: m.range) { continue }
                let after = (text as NSString).substring(from: m.range.location + m.range.length)
                if standbyAfter.first(after) != nil || standbyBefore.first((text as NSString).substring(to: m.range.location)) != nil { continue }
                scopes.append((device: device, range: m.range, certain: device == "Direct laryngoscope" && t.hasPrefix("mac")))
            }
        }
        scopes.sort { $0.range.location < $1.range.location }
        func grade(in span: NSRange) -> (value: String?, range: NSRange)? { views.first { NSLocationInRange($0.range.location, span) } }
        func file(_ g: (value: String?, range: NSRange)) {
            if let v = g.value {
                put("grade", v, "View grade " + v, g.range)
            } else {
                s.mask(g.range)
                out.skip("View grade 2 · choose 2a or 2b in the airway course")
            }
        }
        let none = NSRange(location: NSNotFound, length: 0)
        let short = ["Video laryngoscope": "VL", "Direct laryngoscope": "DL", "Flexible scope": "Flexible scope", "Supraglottic airway": "SGA"]
        var devices: [String] = []
        for sc in scopes where !devices.contains(sc.device) { devices.append(sc.device) }
        if devices.count > 1 {
            // Two laryngoscopies ("DL grade 3, VL grade 1"): each grade goes with its own device, and the user chooses
            // which one goes in; nothing is filed until then.
            var pairs: [(device: String, grade: String?)] = []
            for (i, sc) in scopes.enumerated() {
                let end = i + 1 < scopes.count ? scopes[i + 1].range.location : whole.length
                let g = grade(in: NSRange(location: sc.range.location, length: end - sc.range.location))
                if let g { s.mask(g.range) }
                if let g, g.value == nil { out.skip("View grade 2 · choose 2a or 2b in the airway course") }
                s.mask(sc.range)
                if !pairs.contains(where: { $0.device == sc.device }) { pairs.append((device: sc.device, grade: g?.value)) }
            }
            for v in views { s.mask(v.range) }
            if !c.record.arrivesWithAirway {
                let options = pairs.enumerated().map { i, pair in
                    AbbreviationMeaning((short[pair.device] ?? pair.device) + (pair.grade.map { ", grade " + $0 } ?? ""), id: "laryngoscopy-" + String(i))
                }
                let asked = PatientNote.question(laryngoscopyQuestion, "Laryngoscopy", value: options.map(\.text).joined(separator: " | "),
                                                 options: options, usual: options.last?.id ?? "", c.choices)
                out.questions.append(asked.question)
                if let answer = asked.answer, let i = options.firstIndex(where: { $0.id == answer }) {
                    put("device", pairs[i].device, pairs[i].device, none)
                    if let g = pairs[i].grade { put("grade", g, "View grade " + g, none) }
                }
            }
        } else {
            if let first = scopes.first {
                put("device", first.device, first.device, first.range, certain: first.certain)
                for sc in scopes.dropFirst() { s.mask(sc.range) }
            }
            // One laryngoscopy with two view grades ("DL grade 1, grade 3"): asked, nothing filed until then.
            var values: [String] = []
            for v in views { if let x = v.value, !values.contains(x) { values.append(x) } }
            if values.count > 1 {
                for v in views { s.mask(v.range) }
                if !c.record.arrivesWithAirway {
                    let options = values.map { AbbreviationMeaning("grade " + $0, id: "grade-" + $0) }
                    let asked = PatientNote.question(gradeQuestion, "View grade", value: values.joined(separator: ","), options: options,
                                                     usual: options.last?.id ?? "", c.choices)
                    out.questions.append(asked.question)
                    if let answer = asked.answer, let v = values.first(where: { "grade-" + $0 == answer }) { put("grade", v, "View grade " + v, none) }
                }
            } else if let g = views.first(where: { $0.value != nil }) ?? views.first {
                file(g)
                for v in views where v.range.location != g.range.location { s.mask(v.range) }
            }
        }
        if let m = maskEaseRx.first(text), let w = (group(m, 1, text) ?? group(m, 2, text))?.lowercased(), !negated(m.range, text) {
            let v = w == "easy" ? "easy" : "difficult"
            put("mask", v, "Mask " + v, m.range)
        }
        if let m = intubationEaseRx.first(text), let w = (group(m, 1, text) ?? group(m, 2, text))?.lowercased(), !negated(m.range, text) {
            let v = w == "easy" ? "easy" : "difficult"
            put("intubation", v, "Intubation " + v, m.range)
        }
        // Attempts: the highest ordinal ("1st attempt DL failed, 2nd attempt VL" is 2); counts with each of two
        // laryngoscopes add up ("DL 1 attempt failed, VL 1 attempt success" is 2).
        let ordinals = ["first": 1, "1st": 1, "second": 2, "2nd": 2, "third": 3, "3rd": 3]
        var highest = 0
        var perDevice: [String: Int] = [:]
        var attemptRanges: [NSRange] = []
        for m in attemptsRx.all(text) {
            attemptRanges.append(m.range)
            if let n = (group(m, 1, text) ?? group(m, 2, text)).flatMap({ Int($0) }) {
                let piece = pieceRange(m.range, in: text)
                if let sc = scopes.first(where: { NSLocationInRange($0.range.location, piece) }) {
                    perDevice[sc.device] = Swift.max(perDevice[sc.device] ?? 0, n)
                } else {
                    highest = Swift.max(highest, n)
                }
            } else if let n = (group(m, 3, text) ?? group(m, 4, text) ?? group(m, 5, text)).flatMap({ ordinals[$0.lowercased()] }) {
                highest = Swift.max(highest, n)
            }
        }
        let counted = Swift.max(highest, perDevice.values.reduce(0, +))
        if counted > 0, let r = attemptRanges.first {
            let n = counted
            put("attempts", String(n), n == 1 ? "1 attempt" : "\(n) attempts", r)
            for x in attemptRanges.dropFirst() { s.mask(x) }
        }
        for r in ranges { s.mask(r) }
        guard !found.isEmpty else { return }
        if c.record.arrivesWithAirway { return out.skip("Airway course · the patient arrives with an airway (Preop tab)") }
        for f in found {
            out.add(PatientNoteFinding(id: "intraop-airway:" + f.key, section: intraop, label: f.label, change: .intraopAirway(f.key, f.value)))
        }
    }

    // MARK: The full note on a tab

    /// A note read in the full-note sheet (a long paste, the pencil), routed for the tab it was opened from. On the
    /// Preoperative tab it is the note reader's reading as it is. On the Intraoperative tab each finding goes where the
    /// bar files it (labs to a new intraoperative set, drips to the case's infusions, lines placed in the OR); what
    /// belongs before the case (history, the exam, home medicines, the vital-sign baseline, the airway on arrival) is left
    /// out, and nothing goes to Other conditions.
    static func forTab(_ note: PatientNoteReading, tab: QuickAddTab, record: PatientRecord, now: Date = Date()) -> PatientNoteReading {
        guard tab == .intraop else { return note }
        let c = QuickContext(tab: .intraop, record: record, now: now, abbreviations: [], choices: [:], setID: UUID())
        var out = QuickOut()
        for f in note.findings where !inferred(f) {
            if case .procedure = f.change {
                out.add(f)
            } else {
                route(f, "", c, &out)
            }
        }
        var r = note
        r.findings = out.findings
        r.other = ""
        r.previous = ""
        r.ambiguous = note.ambiguous.filter { $0.id != PatientNote.roomAirQuestion }
        return r
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
