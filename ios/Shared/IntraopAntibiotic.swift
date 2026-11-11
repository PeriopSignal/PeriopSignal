import Foundation

// MARK: - An antibiotic given during the case (1.12 follow-up, Ben's note "Vancomycin not recognized in medications and
// interventions. Is recognized in case timer.")
//
// Ben asked for one place to hold an antibiotic: Case Timers. What Antibiotics & Notable Medications (the Intraoperative
// tab's row and page, the handoff's Antibiotics line) shows is read from `PatientRecord.timers.antibiotics`, so two things
// were missing:
//
// 1. The quick-add bar had no finding for an antibiotic given in the case. "vanc 1 g at 0810" typed on the Intraoperative
//    tab now reads as a dose logged in Case Timers (the review says so in its label), which is exactly what Case Timers'
//    own Start (a new course) or "Redose given" (a dose added to the course) does, so the redose reminders run from it.
// 2. A drug picked in Case Timers was only pending (view state) until "Start timer" was tapped, and for a drug with no
//    routine redose (vancomycin, ceftriaxone, ertapenem, metronidazole, gentamicin, ciprofloxacin, levofloxacin) the
//    button read as if there were nothing to start. Its words now say what it does, and leaving with a pick still pending
//    asks first.
//
// The dose AS TYPED ("1 g", "2g", "15 mg/kg") is kept with the dose entry (TimedEntry.given) and shown as typed; it is never
// computed, converted or corrected, and no dose check blocks it. Names come from Case Timers' own list (reference.json
// "caseTimers", ids and names) and the medication catalog's brands and short forms; five drugs the catalog does not carry
// get the few unambiguous names below. Whole words only. Nothing is filed from an allergy or a reaction, a level or a lab,
// a resistance, a home or preoperative medicine, a negation, a plan, an infusion, a topical use, or a dosing schedule: the
// reader declines and the line is read as it was before.

/// One antibiotic dose read from the quick-add bar (PatientNoteChange.antibioticDose).
struct IntraopAntibioticDose: Hashable {
    /// The Case Timers drug id ("vancomycin").
    var drug: String
    /// The dose as typed ("1 g"); nil when none was typed.
    var given: String?
    /// When it was given: the time typed (resolved as Case Timers' start time is) or now.
    var time: Date
    /// "redose" was typed.
    var redose: Bool
}

enum IntraopAntibiotic {
    /// A dose already logged within this many seconds of the time is the same dose (typing a line twice files it once).
    static let sameDoseWithin: TimeInterval = 120

    // MARK: Names

    struct Form: Hashable {
        var words: [String]
        var drug: String
    }

    /// Names the catalog does not carry for a drug of Case Timers' list: unambiguous brands and short forms only. Not "amp"
    /// (an ampule), not "metro", not "levo" (levophed, levothyroxine). The catalog's own (ancef, kefzol, vanc, vanco, zosyn,
    /// flagyl, cipro, levaquin, cleocin, rocephin, invanz, ceftin ...) are taken from MedicationCatalog.
    private static let extraNames: [String: [String]] = [
        "cefoxitin": ["mefoxin"],
        "cefotetan": ["cefotan"],
        "ampicillin-sulbactam": ["unasyn"],
        "piperacillin-tazobactam": ["piptazo"],
        "aztreonam": ["azactam"],
        "clindamycin": ["clinda"],
        "gentamicin": ["gent", "gentamycin", "garamycin"],
    ]

    /// Every name that reads as a drug of Case Timers' list, longest first. A one-word name shorter than four letters is
    /// never one.
    static func forms(_ d: CaseTimerData) -> [Form] {
        var out: [Form] = []
        var seen = Set<[String]>()
        for def in d.antibiotics {
            var texts = [def.id, def.name] + (extraNames[def.id] ?? [])
            if let e = MedicationCatalog.entry(id: def.id) { texts += [e.name] + e.aliases }
            for t in texts {
                let w = CatalogText.words(t).map(\.key)
                guard !w.isEmpty, !(w.count == 1 && w[0].count < 4), seen.insert(w).inserted else { continue }
                out.append(Form(words: w, drug: def.id))
            }
        }
        return out.sorted { $0.words.count > $1.words.count }
    }

    /// The drug a typed word or phrase names, by the same names the bar reads ("ancef" is cefazolin); nil for none.
    static func drug(named s: String, in d: CaseTimerData) -> String? {
        let w = CatalogText.words(s).map(\.key)
        guard !w.isEmpty else { return nil }
        return forms(d).first { $0.words == w }?.drug
    }

    struct NameHit: Hashable {
        var drug: String
        var range: NSRange
    }

    /// Where the line names a drug, whole words only ("gentle" is not "gent"). The words of a name are joined by spaces, a
    /// hyphen or a slash only.
    static func nameHits(in text: String, forms: [Form]) -> [NameHit] {
        let toks = CatalogText.words(text)
        var out: [NameHit] = []
        var i = 0
        while i < toks.count {
            var took = 0
            var drug = ""
            for f in forms where i + f.words.count <= toks.count {
                guard (0..<f.words.count).allSatisfy({ toks[i + $0].key == f.words[$0] }) else { continue }
                var joined = true
                if f.words.count > 1 {
                    for k in 1..<f.words.count {
                        let gap = text[toks[i + k - 1].range.upperBound..<toks[i + k].range.lowerBound]
                        if !gap.allSatisfy({ " -–—/".contains($0) }) { joined = false }
                    }
                }
                if joined { took = f.words.count; drug = f.drug; break }
            }
            if took > 0 {
                let lo = toks[i].range.lowerBound, hi = toks[i + took - 1].range.upperBound
                out.append(NameHit(drug: drug, range: NSRange(lo..<hi, in: text)))
                i += took
            } else {
                i += 1
            }
        }
        return out
    }

    // MARK: Clauses and guards

    private static let separator = NoteRx(#"(?<!\d),|,(?!\d)|;|\n|(?<!\d)\.(?=\s|$)|\s[+&]\s|\b(?:and|then|plus)\b"#)

    /// The pieces of a line between its separators (a comma, a semicolon, a full stop, "and", "+").
    static func clauses(_ text: String) -> [NSRange] {
        let ns = text as NSString
        var out: [NSRange] = []
        var start = 0
        for m in separator.all(text) {
            out.append(NSRange(location: start, length: max(0, m.range.location - start)))
            start = m.range.location + m.range.length
        }
        out.append(NSRange(location: start, length: max(0, ns.length - start)))
        return out
    }

    /// Words that make a clause something other than a dose given now: an allergy or a reaction, a level or a lab, a
    /// resistance, a home or preoperative medicine and its schedule, a negation, a plan, an infusion, a use that is not an
    /// intravenous dose (powder, irrigation, cement).
    private static let rejectRx = NoteRx(
        #"\b(?:allerg\w*|anaphyla\w*|reactions?|reacted|rash|hives|urticaria|angioedema|red[- ]man|flushing|itch\w*|prurit\w*|intoleran\w*"#
        + #"|sensitiv\w*|susceptib\w*|resistan\w*|vre|mrsa|mssa|enterococc\w*"#
        + #"|levels?|troughs?|peaks?|random|auc|concentrations?|mcg|ug|µg|mg/l|mg/dl|mcg/ml"#
        + #"|home|pta|outpatient|chronic|pre-?op(?:erative)?|prior to admission|endocarditis|osteomyelitis|po|oral|tabs?|tablets?|capsules?"#
        + #"|no|not|never|nil|without|denies|denied|declined?|refus\w*|held|hold|holding|withh\w*|omit\w*|skip\w*|cancel\w*|discontinu\w*|stopp\w*|stop|avoid\w*"#
        + #"|didn['’]?t|wasn['’]?t|isn['’]?t|haven['’]?t|hasn['’]?t|none|deferred|dc['’]?d|d/c"#
        + #"|will|won['’]?t|going to|gonna|plan\w*|to (?:be|give|start|redose|re-?dose)|due|next|scheduled|sched|needs?|needed|should|consider\w*|would|ask\w*|order\w*"#
        + #"|pending|later|remind\w*|if|when|once|until|want\w*|can|could|may|might|tbd|todo|requested?"#
        + #"|infusions?|drips?|gtts?|running|continuous|pump"#
        + #"|powder|paste|irrigat\w*|cement|beads?|topical|local|wash|soak\w*|sponge|ointment|cream|drops)\b|\?"#)

    /// The word before the name that makes it something else: "after vanc" (a reaction, the events reader's), "on vanc" (a
    /// medicine the patient takes), "switched to".
    private static let leadRx = NoteRx(
        #"\b(?:after|following|post|during|to|from|on|taking|takes|continued?|continues|secondary to|due to|r/t)\s*[:\-–]?\s*(?:the\s+)?$"#)

    static func rejected(clause: String, before: String) -> Bool {
        rejectRx.first(clause) != nil || QuickAdd.eventRx.first(clause) != nil || QuickAdd.scheduleCue.first(clause) != nil
            || leadRx.first(before) != nil
    }

    // MARK: What follows (or leads) the name

    private static let unit = #"(?:mg\s*/\s*kg|mg|gm|grams?|g)"#
    private static let number = #"(?:\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)"#
    private static let doseAfter = NoteRx(#"\s*[(:\-–=]?\s*("# + number + #"\s*"# + unit + #")(?![A-Za-z0-9/])\)?"#)
    private static let atTime = NoteRx(
        #"\s*\(?\s*(?:at|@)\s*(\d{1,2}:\d{2}|\d{3,4})(?:\s*(am|pm|a\.m\.|p\.m\.))?(?![\d:.]|\s*(?:mg|g|gm|mcg|ml|units?|kg)\b)\)?"#)
    private static let atHour = NoteRx(#"\s*\(?\s*(?:at|@)\s*(\d{1,2})\s*(am|pm|a\.m\.|p\.m\.)(?![A-Za-z])\)?"#)
    private static let bareTime = NoteRx(
        #"\s*\(?\s*(\d{1,2}:\d{2}|[01]\d{3}|2[0-3]\d{2})(?:\s*(am|pm|a\.m\.|p\.m\.))?(?![\d:.]|\s*(?:mg|g|gm|mcg|ml|units?|kg|mmhg|%)\b)\)?"#)
    private static let redoseAfter = NoteRx(#"\s*\(?\s*(re[- ]?dos(?:e|ed|ing))\b\)?"#)
    private static let fillerAfter = NoteRx(#"\s*\(?\s*(?:given|gave|dose|doses|dosed|iv|ivp|ivpb|push|pushed|now|just|administered)\b\)?"#)

    private static let redoseBefore = NoteRx(#"re[- ]?dos(?:e|ed|ing)\s*[:\-–]?\s*$"#)
    private static let fillerBefore = NoteRx(#"\b(?:gave|given|administered|dose|abx|antibiotics?)\s*[:\-–]?\s*$"#)
    private static let doseBefore = NoteRx(#"(?:^|[\s(:])("# + number + #"\s*"# + unit + #")\s*(?:of\s+)?\)?\s*$"#)
    private static let leadOnly = NoteRx(#"^(?:\s|abx|antibiotics?|gave|given|administered|dose|re[- ]?dos\w*|[:\-–(])*$"#)

    private static func anchored(_ rx: NoteRx, _ ns: NSString, at loc: Int, to end: Int) -> NSTextCheckingResult? {
        guard let re = rx.re, loc < end else { return nil }
        return re.firstMatch(in: ns as String, options: [.anchored], range: NSRange(location: loc, length: end - loc))
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ ns: NSString) -> String? {
        guard i < m.numberOfRanges else { return nil }
        let r = m.range(at: i)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }

    /// Hour and minute of "0810", "810", "8:10", "8" with "am" or "pm"; nil when it is not a time of day.
    static func hourMinute(_ digits: String, _ ampm: String?) -> (hour: Int, minute: Int)? {
        var h: Int, m: Int
        if digits.contains(":") {
            let p = digits.split(separator: ":").map(String.init)
            guard p.count == 2, let a = Int(p[0]), let b = Int(p[1]) else { return nil }
            h = a; m = b
        } else if digits.count <= 2 {
            guard let a = Int(digits) else { return nil }
            h = a; m = 0
        } else {
            guard let n = Int(digits) else { return nil }
            h = n / 100; m = n % 100
        }
        guard m < 60 else { return nil }
        if let ap = ampm?.lowercased().replacingOccurrences(of: ".", with: "") {
            guard (1...12).contains(h) else { return nil }
            if ap == "pm" && h < 12 { h += 12 }
            if ap == "am" && h == 12 { h = 0 }
        }
        guard h < 24 else { return nil }
        return (h, m)
    }

    /// The moment a typed clock time names, as Case Timers resolves a start time picked on a clock: the time today, a
    /// time more than 12 h ahead being yesterday's.
    static func moment(hour: Int, minute: Int, now: Date) -> Date? {
        guard let today = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        return CaseTimerRecurrence.resolveStart(today, now: now)
    }

    // MARK: Reading

    struct Reading {
        var findings: [PatientNoteFinding] = []
        /// What the findings were read from, to take out of the line for the other readers.
        var ranges: [NSRange] = []
    }

    /// The antibiotic doses a line gives (the bar on the Intraoperative tab and the intraoperative pages only). `text` is the
    /// line as the other readers left it. A hit that is not a dose given now is declined and its words stay in the line.
    static func read(_ text: String, record r: PatientRecord, now: Date, data: CaseTimerData? = CaseAntibiotics.current) -> Reading {
        var out = Reading()
        guard let d = data else { return out }
        let hits = nameHits(in: text, forms: forms(d))
        guard !hits.isEmpty else { return out }
        let ns = text as NSString
        let cl = clauses(text)
        var floor = 0
        for (k, h) in hits.enumerated() {
            guard let clause = cl.first(where: { NSLocationInRange(h.range.location, $0) }) else { continue }
            let clauseEnd = clause.location + clause.length
            let before = ns.substring(with: NSRange(location: clause.location, length: h.range.location - clause.location))
            guard !rejected(clause: ns.substring(with: clause), before: before) else { continue }
            let nextName = hits.dropFirst(k + 1).first { NSLocationInRange($0.range.location, clause) }?.range.location ?? clauseEnd
            var given: String?
            var clock: (hour: Int, minute: Int)?
            var redose = false
            var invalid = false
            var pos = h.range.location + h.range.length
            // After the name: a dose, a time, "redose", and the small words a dose is told with, in any order.
            var progressed = true
            while progressed, pos < nextName {
                progressed = false
                if given == nil, let m = anchored(doseAfter, ns, at: pos, to: nextName), let g = group(m, 1, ns) {
                    given = g.trimmingCharacters(in: .whitespaces)
                    pos = m.range.location + m.range.length
                    progressed = true
                } else if clock == nil, !invalid, let m = anchored(atTime, ns, at: pos, to: nextName) ?? anchored(bareTime, ns, at: pos, to: nextName),
                          let g = group(m, 1, ns) {
                    if let hm = hourMinute(g, group(m, 2, ns)) { clock = hm } else { invalid = true }
                    pos = m.range.location + m.range.length
                    progressed = true
                } else if clock == nil, !invalid, let m = anchored(atHour, ns, at: pos, to: nextName), let g = group(m, 1, ns) {
                    if let hm = hourMinute(g, group(m, 2, ns)) { clock = hm } else { invalid = true }
                    pos = m.range.location + m.range.length
                    progressed = true
                } else if let m = anchored(redoseAfter, ns, at: pos, to: nextName) {
                    redose = true
                    pos = m.range.location + m.range.length
                    progressed = true
                } else if let m = anchored(fillerAfter, ns, at: pos, to: nextName) {
                    pos = m.range.location + m.range.length
                    progressed = true
                }
            }
            // Before the name: "redose", a lead word, and a dose that opens the clause ("2 g cefazolin").
            let winStart = max(clause.location, floor)
            var start = h.range.location
            progressed = true
            while progressed, start > winStart {
                progressed = false
                let sub = ns.substring(with: NSRange(location: winStart, length: start - winStart))
                if let m = redoseBefore.first(sub) {
                    redose = true
                    start = winStart + m.range.location
                    progressed = true
                } else if let m = fillerBefore.first(sub) {
                    start = winStart + m.range.location
                    progressed = true
                } else if given == nil, let m = doseBefore.first(sub), m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
                    let g = m.range(at: 1)
                    let rest = (sub as NSString).substring(to: g.location)
                    if leadOnly.first(rest) != nil {
                        given = (sub as NSString).substring(with: g).trimmingCharacters(in: .whitespaces)
                        start = winStart + g.location
                        progressed = true
                    }
                }
            }
            // A time that is not a time of day ("at 2575"): nothing is guessed.
            guard !invalid else { continue }
            var time = now
            var key = "now"
            if let c = clock {
                guard let t = moment(hour: c.hour, minute: c.minute, now: now) else { continue }
                time = t
                key = String(format: "%02d%02d", c.hour, c.minute)
            }
            let dose = IntraopAntibioticDose(drug: h.drug, given: given, time: time, redose: redose)
            let id = "abx:" + h.drug + ":" + key + ":" + (given ?? "").lowercased().filter { !$0.isWhitespace }
            out.findings.append(PatientNoteFinding(id: id, section: QuickAdd.intraop, label: label(dose, record: r, data: d, now: now),
                                                   change: .antibioticDose(dose), note: note(r)))
            out.ranges.append(NSRange(location: start, length: pos - start))
            floor = pos
        }
        return out
    }

    // MARK: The review's words

    /// The drug's name in Case Timers' list, or the id capitalized.
    static func name(_ drug: String, in d: CaseTimerData?) -> String { d?.antibiotic(drug)?.name ?? drug.capitalized }

    /// What filing it will do, exactly: "Vancomycin 1 g: dose logged in Case Timers at 08:10"; "Cefazolin: redose logged in
    /// Case Timers at 12:05, next due 16:05" (the redose interval Case Timers holds for the drug, or its sourced one).
    static func label(_ dose: IntraopAntibioticDose, record r: PatientRecord, data: CaseTimerData?, now: Date) -> String {
        let def = data?.antibiotic(dose.drug)
        let course = r.timers.course(dose.drug)
        var s = name(dose.drug, in: data) + (dose.given.map { " " + $0 } ?? "") + ": "
        s += (course != nil || dose.redose ? "redose" : "dose") + " logged in Case Timers at " + PatientSummary.time(dose.time, now: now)
        let minutes: Double? = {
            if let c = course, let def { return CaseTimerRecurrence.redoseMinutes(c, def: def) }
            return def?.redoseHours.map { $0 * 60 }
        }()
        if let m = minutes, m > 0 { s += ", next due " + PatientSummary.time(dose.time.addingTimeInterval(m * 60), now: now) }
        return s
    }

    /// A child's Case Timers holds no antibiotic doses (adult defaults only); a dose typed is still kept as typed.
    static func note(_ r: PatientRecord) -> String? {
        CaseTimerEngine.isChild(r) ? "Adult defaults only: not for children. The dose is logged as typed." : nil
    }

    // MARK: Status and filing

    static func status(_ dose: IntraopAntibioticDose, in r: PatientRecord) -> PatientNoteStatus {
        guard let c = r.timers.course(dose.drug) else { return .new }
        return c.doses.contains { abs($0.time.timeIntervalSince(dose.time)) <= sameDoseWithin } ? .recorded : .new
    }

    /// What Case Timers does for a dose: a new course for a drug not in it (the drug's sourced interval, none for a drug
    /// without one), else a dose added to the course ("Redose given"); snoozes on the drug's reminders cleared. A dose
    /// within two minutes of one already there is not added again.
    static func apply(_ dose: IntraopAntibioticDose, to r: inout PatientRecord) {
        guard status(dose, in: r) != .recorded else { return }
        let entry = TimedEntry(time: dose.time, ebl: r.fluids["ebl"] ?? 0, given: dose.given)
        if let i = r.timers.antibiotics.firstIndex(where: { $0.drug == dose.drug }) {
            r.timers.antibiotics[i].doses.append(entry)
        } else {
            r.timers.antibiotics.append(AntibioticCourse(drug: dose.drug, doses: [entry], everyMinutes: nil))
        }
        r.timers.clearAntibioticSnoozes(dose.drug)
    }

    // MARK: Case Timers' antibiotic card

    /// The button under the pending antibiotics: it says what it does. "Start timer" while nothing is pending or changed.
    static func buttonTitle(pending: Bool, anyInterval: Bool, onlyChanges: Bool) -> String {
        if pending { return anyInterval ? "Log dose & start timer" : "Log dose" }
        return onlyChanges ? "Update timer" : "Start timer"
    }

    static func buttonHint(pending: Bool, anyInterval: Bool, onlyChanges: Bool) -> String {
        if pending {
            return anyInterval ? "Logs the dose at the start time and starts the redose timer"
                               : "Logs the dose at the start time. No redose timer starts, because no interval is chosen"
        }
        return onlyChanges ? "Saves the new redose intervals" : "Logs the dose at the start time and starts the redose timer"
    }

    /// The line under the button while an antibiotic is picked and not logged: guidance, not an alert.
    static func pendingNote(buttonTitle: String) -> String { "Not recorded until you tap \(buttonTitle)." }

    /// The question when the page is left with an antibiotic still pending: "Log Vancomycin at 08:10?".
    static func leaveTitle(names: [String], at time: String) -> String {
        let list: String
        switch names.count {
        case 0: list = "the antibiotic"
        case 1: list = names[0]
        default: list = names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
        return "Log \(list) at \(time)?"
    }

    /// "given: 1 g" beside the last dose when it was typed in the bar and says something other than the dose Case Timers
    /// computes; nil otherwise.
    static func givenNote(last: TimedEntry?, computed: String) -> String? {
        guard let g = last?.given?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty else { return nil }
        func plain(_ s: String) -> String { s.lowercased().filter { !$0.isWhitespace } }
        return plain(g) == plain(computed) ? nil : "given: " + g
    }

    // MARK: Medications & Interventions page

    static let noneCharted = "None charted"
    static let addLink = "+ Antibiotic"
    static let addLinkMore = "+ Antibiotic or redose"
    static let barExample = "vanc 1 g at 0810"

    /// The page's group is shown whenever Case Timers is (an empty one says how to add), and while it has antibiotics.
    static func pageShowsGroup(hasAntibiotics: Bool, caseTimersShown: Bool) -> Bool { hasAntibiotics || caseTimersShown }

    /// The link under the list: none where Case Timers is hidden or holds no antibiotic doses (a child).
    static func pageLink(hasAntibiotics: Bool, caseTimersShown: Bool, child: Bool) -> String? {
        guard caseTimersShown, !child else { return nil }
        return hasAntibiotics ? addLinkMore : addLink
    }
}
