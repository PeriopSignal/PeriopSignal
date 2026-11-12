import Foundation

// MARK: - Heparin given during the case, recorded without a timer (1.12 follow-up, Ben, Nov 12)
//
// "Have option to just add antibiotic and heparin to intraop meds without using timer." Heparin has ONE log, Case Timers'
// "Heparin & ACT" timeline (`HeparinCourse.doses`); the Intraoperative medications page, the Intraoperative tab's row and the
// handoff list the doses from it, and "+ Heparin" on the page and a line typed in the quick-add bar write to it. Recording a
// dose starts no ACT reminder: the reminder is a switch in Case Timers and changes only by that switch (`HeparinCourse.logDose`).
//
// A course that does not exist yet is created with the purpose the app already has for "not chosen": Case Timers makes no
// course until a purpose is picked, and every reader of a course needs a purpose it can look up, so the existing "Other"
// (no preset goal, no dose range) is used; nothing is invented. A typed dose is kept as asserted ("heparin 26000", "heparin
// 26,000 units at 0810", "5000 u heparin"), never computed or corrected; a dose entered on the page is checked the way Case
// Timers checks it (`CaseTimerEngine.entryIssues`: the weight, the plausibility rules; a blocked dose is refused).
//
// The bar reads only a dose given now: not an infusion or a rate ("heparin gtt", "heparin at 500 units/h" stay what they were),
// not subcutaneous or prophylactic heparin, a resistance, HIT, a flush or a lock, a negation or a plan, an allergy line, a
// level or a lab, a home medicine. A typed ACT is not read here.

/// One heparin dose read from the quick-add bar (PatientNoteChange.heparinDose).
struct IntraopHeparinDose: Hashable {
    var units: Double
    var time: Date
}

enum IntraopHeparin {
    /// The same dose again within this many seconds (typing a line twice files it once).
    static let sameDoseWithin: TimeInterval = 120
    /// A dose in units: a number below this is not read as one ("heparin 5" is not 5 U), and an unlabelled number below the second
    /// is not either ("heparin 500").
    static let minUnits: Double = 100
    static let minBareUnits: Double = 1000
    static let maxUnits: Double = 100_000
    /// The purpose of a course made by recording a dose before one was chosen (reference.json "heparinPurposes": Other).
    static let purposeNotChosen = "other"
    /// The ACT interval such a course starts with (Other's first interval; Case Timers' pickPurpose does `actEvery.first ?? 30`).
    static let defaultActEvery: Double = 30

    // MARK: Reading

    private static let nameRx = NoteRx(#"(?<![A-Za-z0-9])heparin(?![A-Za-z0-9])"#)
    private static let number = #"(?:\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)"#
    /// A dose after the name: a number, then an optional unit. The unit group cannot give a letter back ("5000 u/hr" is a rate and
    /// is declined, it does not become 5000 with "u/hr" left over).
    private static let doseAfter = NoteRx(
        #"\s*[(:\-–=]?\s*("# + number + #")(?:\s*(units?|u|iu)(?![A-Za-z]))?+(?![A-Za-z0-9/%])(?!\s*(?:/|mg\b|mcg\b|ml\b|cc\b|g\b|gm\b|kg\b|meq\b|%|mmhg|sec|min\b|hrs?\b|hours?\b))\)?"#)
    private static let doseBefore = NoteRx(#"(?:^|[\s(:])("# + number + #")\s*(?:units?|u|iu)(?![A-Za-z])\s*(?:of\s+)?\)?\s*$"#)
    private static let fillerAfter = NoteRx(#"\s*\(?\s*(?:given|gave|dose|doses|dosed|iv|ivp|push|pushed|bolus|now|just|administered|units?)\b\)?"#)
    private static let fillerBefore = NoteRx(#"\b(?:gave|given|administered|dose|bolus|iv|ivp|push|pushed)\s*[:\-–]?\s*$"#)
    private static let leadOnly = NoteRx(#"^(?:\s|gave|given|administered|dose|bolus|iv|ivp|push|pushed|[:\-–(])*$"#)

    /// Words that make a clause something other than a dose given now (see the header).
    private static let rejectRx = NoteRx(
        #"\b(?:allerg\w*|anaphyla\w*|reactions?|reacted|intoleran\w*|sensitiv\w*|resistan\w*|induced|antibod\w*|pf4|thrombocytopeni\w*"#
        + #"|flush\w*|lock\w*|saline|irrigat\w*"#
        + #"|sq|sc|subq|sub-?q|subcut\w*|subcutaneous|prophyla\w*|ppx|dvt|vte|molecular|lmwh|enoxaparin|lovenox"#
        + #"|q\s?\d+\s?(?:h|hr|hrs)?|bid|tid|qd|daily|prn|every"#
        + #"|infusions?|drips?|gtts?|running|continuous|pump|titrat\w*|rate"#
        + #"|home|pta|outpatient|chronic|pre-?op(?:erative)?|prior to admission"#
        + #"|no|not|never|nil|without|denies|denied|declined?|refus\w*|held|hold|holding|withh\w*|omit\w*|skip\w*|cancel\w*|discontinu\w*|stopp\w*|stop|avoid\w*|off"#
        + #"|didn['’]?t|wasn['’]?t|isn['’]?t|haven['’]?t|hasn['’]?t|none|deferred|dc['’]?d|d/c"#
        + #"|will|won['’]?t|going to|gonna|plan\w*|give|to (?:be|start)|due|next|scheduled|sched|needs?|needed|should|consider\w*|would|ask\w*|order\w*"#
        + #"|pending|later|remind\w*|if|when|once|until|want\w*|can|could|may|might|tbd|todo|requested?"#
        + #"|levels?|anti-?xa|aptt|ptt|inr|act|reversal|reverse\w*|protamine)\b|\?"#)

    /// Heparin-induced thrombocytopenia anywhere in the line.
    private static let hitRx = NoteRx(#"(?-i:\bHIT\b)|heparin[- ]induced"#)

    /// The word before the name that makes it something else ("on heparin", "after heparin").
    private static let leadRx = NoteRx(
        #"\b(?:after|following|post|during|to|from|on|taking|takes|continued?|continues|secondary to|due to|r/t)\s*[:\-–]?\s*(?:the\s+)?$"#)

    static func rejected(clause: String, before: String) -> Bool {
        rejectRx.first(clause) != nil || QuickAdd.eventRx.first(clause) != nil || QuickAdd.scheduleCue.first(clause) != nil
            || leadRx.first(before) != nil
    }

    /// The units a number names ("26,000", "26000"); nil when it is not a dose: leading zero ("0810" is a time), a fraction of a
    /// unit, or outside the range. A labelled number may be smaller than a bare one.
    static func units(_ digits: String, labelled: Bool) -> Double? {
        let t = digits.replacingOccurrences(of: ",", with: "")
        guard !t.hasPrefix("0"), let v = Double(t), v == v.rounded() else { return nil }
        guard v >= (labelled ? minUnits : minBareUnits), v <= maxUnits else { return nil }
        return v
    }

    /// The heparin doses a line gives (the bar on the Intraoperative tab and the intraoperative pages only). `text` is the line as the
    /// other readers left it. A hit that is not a dose given now is declined and its words stay in the line for the other readers.
    static func read(_ text: String, record r: PatientRecord, now: Date) -> IntraopAntibiotic.Reading {
        var out = IntraopAntibiotic.Reading()
        let hits = nameRx.all(text)
        // HIT anywhere in the line (capitals only: "hit" is a word): a heparin dose beside it is for the clinician to settle, not a
        // line to file.
        guard !hits.isEmpty, hitRx.first(text) == nil else { return out }
        let ns = text as NSString
        let cl = IntraopAntibiotic.clauses(text)
        var floor = 0
        for (k, h) in hits.enumerated() {
            guard let clause = cl.first(where: { NSLocationInRange(h.range.location, $0) }) else { continue }
            let clauseEnd = clause.location + clause.length
            let before = ns.substring(with: NSRange(location: clause.location, length: h.range.location - clause.location))
            guard !rejected(clause: ns.substring(with: clause), before: before) else { continue }
            let nextName = hits.dropFirst(k + 1).first { NSLocationInRange($0.range.location, clause) }?.range.location ?? clauseEnd
            var given: Double?
            var clock: (hour: Int, minute: Int)?
            var invalid = false
            var pos = h.range.location + h.range.length
            var progressed = true
            while progressed, pos < nextName {
                progressed = false
                if given == nil, let m = IntraopAntibiotic.anchored(doseAfter, ns, at: pos, to: nextName),
                   let g = IntraopAntibiotic.group(m, 1, ns) {
                    let labelled = IntraopAntibiotic.group(m, 2, ns) != nil
                    pos = m.range.location + m.range.length
                    progressed = true
                    guard let v = units(g, labelled: labelled) else { invalid = true; break }
                    given = v
                } else if clock == nil, !invalid,
                          let m = IntraopAntibiotic.anchored(IntraopAntibiotic.atTime, ns, at: pos, to: nextName)
                              ?? IntraopAntibiotic.anchored(IntraopAntibiotic.bareTime, ns, at: pos, to: nextName),
                          let g = IntraopAntibiotic.group(m, 1, ns) {
                    if let hm = IntraopAntibiotic.hourMinute(g, IntraopAntibiotic.group(m, 2, ns)) { clock = hm } else { invalid = true }
                    pos = m.range.location + m.range.length
                    progressed = true
                } else if clock == nil, !invalid, let m = IntraopAntibiotic.anchored(IntraopAntibiotic.atHour, ns, at: pos, to: nextName),
                          let g = IntraopAntibiotic.group(m, 1, ns) {
                    if let hm = IntraopAntibiotic.hourMinute(g, IntraopAntibiotic.group(m, 2, ns)) { clock = hm } else { invalid = true }
                    pos = m.range.location + m.range.length
                    progressed = true
                } else if let m = IntraopAntibiotic.anchored(fillerAfter, ns, at: pos, to: nextName) {
                    pos = m.range.location + m.range.length
                    progressed = true
                }
            }
            // Before the name: a lead word, and a labelled dose that opens the clause ("5000 u heparin").
            let winStart = max(clause.location, floor)
            var start = h.range.location
            progressed = true
            while progressed, start > winStart {
                progressed = false
                let sub = ns.substring(with: NSRange(location: winStart, length: start - winStart))
                if let m = fillerBefore.first(sub) {
                    start = winStart + m.range.location
                    progressed = true
                } else if given == nil, let m = doseBefore.first(sub), m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
                    let g = m.range(at: 1)
                    let rest = (sub as NSString).substring(to: g.location)
                    if leadOnly.first(rest) != nil {
                        guard let v = units((sub as NSString).substring(with: g), labelled: true) else { invalid = true; break }
                        given = v
                        start = winStart + g.location
                        progressed = true
                    }
                }
            }
            guard !invalid, let amount = given else { continue }
            var time = now
            var key = "now"
            if let c = clock {
                guard let t = IntraopAntibiotic.moment(hour: c.hour, minute: c.minute, now: now) else { continue }
                time = t
                key = String(format: "%02d%02d", c.hour, c.minute)
            }
            let dose = IntraopHeparinDose(units: amount, time: time)
            out.findings.append(PatientNoteFinding(id: "hep:" + key + ":" + String(Int(amount)), section: QuickAdd.intraop,
                                                   label: label(dose, now: now), change: .heparinDose(dose), note: note(r)))
            out.ranges.append(NSRange(location: start, length: pos - start))
            floor = pos
        }
        return out
    }

    // MARK: The review's words

    /// "26,000 U".
    static func unitsText(_ u: Double) -> String { CaseTimerEngine.grouped(u) + " U" }

    /// What filing it will do: "Heparin 26,000 U: recorded at 08:10". Recorded in the Heparin & ACT log; the ACT reminder is not touched.
    static func label(_ dose: IntraopHeparinDose, now: Date) -> String {
        "Heparin " + unitsText(dose.units) + ": recorded at " + PatientSummary.time(dose.time, now: now)
    }

    /// A child's Heparin & ACT holds no doses (adult defaults only); a dose typed is still kept as typed.
    static func note(_ r: PatientRecord) -> String? {
        CaseTimerEngine.isChild(r) ? "Adult defaults only: not for children. The dose is recorded as typed." : nil
    }

    // MARK: Status and filing

    static func status(_ dose: IntraopHeparinDose, in r: PatientRecord) -> PatientNoteStatus {
        guard let h = r.timers.heparin else { return .new }
        return h.doses.contains { $0.value == dose.units && abs($0.time.timeIntervalSince(dose.time)) <= sameDoseWithin } ? .recorded : .new
    }

    /// The log a dose goes to: the open case's, made with the purpose "Other" when there is none (no goal, reminder off).
    static func course(_ r: PatientRecord) -> HeparinCourse {
        r.timers.heparin ?? HeparinCourse(purpose: purposeNotChosen, goal: nil, actEvery: defaultActEvery)
    }

    /// Filing a typed dose: one more dose in Heparin & ACT's log, at its time. The ACT reminder is left exactly as it is (a new
    /// course starts with it off). A dose within two minutes of the same one is not added again.
    static func apply(_ dose: IntraopHeparinDose, to r: inout PatientRecord) {
        guard status(dose, in: r) != .recorded else { return }
        record(units: dose.units, at: dose.time, in: &r)
    }

    /// Adds a dose to the log (the page's "+ Heparin", and a typed dose). One call is one Undo step for the caller.
    static func record(units: Double, at time: Date, in r: inout PatientRecord) {
        var h = course(r)
        h.logDose(units: units, at: time, now: time)
        r.timers.heparin = h
    }

    // MARK: The page's own entry ("+ Heparin")

    static let addLink = "+ Heparin"
    static let openLink = "Open Heparin & ACT"
    static let groupTitle = "Heparin"
    static let groupNote = "One log with Heparin & ACT in Case Timers. Recording a dose here starts no ACT reminder; switch it on in Case Timers."

    /// The checks on a dose entered on the page, as Case Timers makes them: the weight and the plausibility rules of its purpose
    /// (the course's, else "Other"), and the time (`time` is the resolved time, nil when it is in the future). A block refuses the dose.
    /// The page never asks for a purpose, so Case Timers' "a bypass-size dose, and the purpose is Other" second tap (which names a purpose
    /// nobody chose here) is not made for "Other": the weight, the unit and the dose-size checks still are.
    static func pageIssues(units: Double?, time: Date?, record r: PatientRecord, data d: CaseTimerData) -> [DoseIssue] {
        let h = r.timers.heparin
        guard let p = d.purpose(h?.purpose ?? purposeNotChosen) else { return [DoseIssue(level: .block, text: "")] }
        let c = h ?? HeparinCourse(purpose: p.id, goal: p.goal, actEvery: defaultActEvery)
        var rules = d
        rules.heparinRules.hardConfirmExempt = (d.heparinRules.hardConfirmExempt ?? ["bypass"]) + [purposeNotChosen]
        return CaseTimerEngine.entryIssues(kind: .heparin, value: units, course: c, purpose: p, record: r, data: rules)
            + (HeparinTimeline.timeIssue(time).map { [$0] } ?? [])
    }
}

// MARK: - What the tab, the page and the handoff say

/// The heparin doses of the open case's one log, read-only: "Heparin 26,000 U 08:10; 5,000 U 08:46 (31,000 U total)". One dose has no
/// total. The doses are listed in time order, each with its time ("11/11/26 23:50" when it was given on another day). The ACT and
/// protamine entries of the same log are Case Timers' (the handoff prints neither today).
enum CaseHeparin {
    static func text(_ r: PatientRecord, now: Date = Date()) -> String? {
        guard let h = r.timers.heparin else { return nil }
        let doses = h.sortedDoses.filter { ($0.value ?? 0) > 0 }
        guard !doses.isEmpty else { return nil }
        let parts = doses.map { IntraopHeparin.unitsText($0.value ?? 0) + " " + PatientSummary.time($0.time, now: now) }
        var s = "Heparin " + parts.joined(separator: "; ")
        if doses.count > 1 { s += " (" + IntraopHeparin.unitsText(doses.reduce(0) { $0 + ($1.value ?? 0) }) + " total)" }
        return s
    }
}
