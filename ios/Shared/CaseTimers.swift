import Foundation

// MARK: - Intraoperative case timers
//
// What was given and measured, stamped with its time, kept in the case's record (PatientRecord.timers), so Undo, case
// switching and the archive treat it like any other entry. Everything shown — the next redose, the ACT due, the
// protamine suggestion and its limits, the lab checks — is read back from that log and the numbers in reference.json
// "caseTimers" (CaseTimerData), so deleting a mistaken entry corrects everything that depends on it. Nothing here
// orders a dose: the reminders and suggestions are checks against the cited sources.
//
// 1.10 (Ben, Nov 7): several antibiotics at once, each with its own redose interval (institutional policy); every
// timer has a start time and a "recurring every" interval chosen from four chips (the last one "Other", in 5-minute
// steps); a running timer can be snoozed or stopped; ACT goals are i-STAT values; the heparin dose is shown as a flat
// dose ("300–400 U/kg ≈ 24,000–32,000 U"); protamine is suggested by a fixed ratio on the INITIAL heparin dose, with a
// cap (method (c)), next to the current ACT.
//
// 1.12 follow-up (Ben, Nov 12): Heparin & ACT is one editable timeline (baseline ACTs, heparin doses, ACT samples and
// protamine, each with a time the user can set and change), and the ACT reminder is ONE switch whose countdown runs from
// the last ACT sample (`CaseTimerEngine.actDue`, the one due-time function every reader uses). A heparin dose starts no
// countdown of its own. (Later the same day: no dose, the first included, turns the switch on any more; it changes only by its
// own switch, and Intraoperative Medications' "+ Heparin" writes to this same log.)
//
// 1.12 follow-up (Ben, Nov 12, "just add antibiotic and heparin to intraop meds without using timer"): an antibiotic course
// can be recorded only (`AntibioticCourse.reminders` false): its doses and times are kept, and it produces no reminder of
// any kind. `CaseTimerEngine.reminders` is the one producer every reader goes through (the running list, the strip, the
// notifications, the lock-screen activity), so skipping it there is skipping it everywhere.
//
// Sources for the anticoagulation numbers, and what was read (Nov 7, 2026):
//
// • STS/SCA/AmSECT 2018, anticoagulation during CPB (Shore-Lesserson L, et al. Ann Thorac Surg 2018;105:650–662;
//   Anesth Analg 2018;126:413–424; J Extra Corpor Technol 2018;50:5–18, PMC5850589). Its full text could not be opened
//   in this session (PubMed Central and the publishers' hosts are blocked; the PubMed tool returns the abstract only).
//   The numbers rest on (a) the 1.9 review doc's source check of the Ann Thorac Surg PDF (Nov 4): "ACT >480 s on
//   bypass; >400 s on maximally activated or microcuvette ACT — Confirmed, IIa/C"; "Protamine under 2.6 mg per 100 U —
//   Confirmed, IIa/C. Heparin basis not stated"; protamine titrated to the heparin in the blood IIa/B; rebound
//   infusion IIb/C; a clotting time before and during bypass I/C; and (b) the full text of the SCA survey by
//   Sniecinski, Bennett-Guerrero and Shore-Lesserson (Anesth Analg 2019;129:e41–e44, PMC6629168), which restates the
//   guideline: "Guidance on minimal acceptable activated clotting time values is given as either >480 or >400 seconds
//   when whole blood is maximally activated or microcuvette technology is used." The guideline's own wording on a
//   reduced protamine-to-heparin ratio was not re-read; the ratio below 1:1 is cited to EACTS 2024 instead.
// • EACTS/EACTAIC/EBCP 2024 cardiopulmonary bypass guideline (PMC11826095), full text read (its recommendation tables
//   do not come through in the PMC text, so no class or level is quoted from it), §9.3.1: "The current practice for
//   anticoagulation during CPB procedures indicates that an ACT value of >480 s is considered an appropriate threshold.
//   Therefore, an ACT above 480 s during CPB should be considered in CPB with uncoated equipment and cardiotomy
//   suction." and "The RCT with 269 patients showed that there was no difference in the bleeding rate when comparing
//   groups with higher (450 IU/kg) and lower heparin doses (300 IU/kg)". §9.3.2: "The protamine dose for reversal of
//   heparin has traditionally been calculated either on the initial heparin dose or on the total amount of heparin
//   administered during CPB" … "Additional doses of protamine may instead lead to overdosing and worsen the
//   coagulopathy." … "Two recent reviews of the available evidence indicate that the protamine-to-heparin ratio should
//   be kept below 1.0, but the exact ratio and monitoring method remain to be determined." … "it is important to
//   discontinue the cardiotomy suction with the start of the administration of protamine" … "Other investigators used
//   stepwise titration of protamine doses in a small RCT (n = 138), resulting in a reduced protamine-to-heparin ratio
//   of 1.30 ± 0.10 (control) and 0.81 ± 0.22 (treatment)" … "The optimal protamine-to-heparin ratio should be below
//   1.0."
// • Bypass 300–400 U/kg (default 300): the 1.9 review, signed off by Ben (G: STS 2018, EACTS 2024; the EACTS sentence
//   above is the one read in full this time).
// • TAVR 70–100 U/kg, ACT 250–300 s: ten Berg J, et al. Eur Heart J 2021;42:2265–2269 (ESC Working Group on
//   Thrombosis / EAPCI consensus). Not re-opened in this session (abstract only, no numbers); the 1.9 review tagged the
//   ACT goal G (checked against the document) and the dose range P (practice). The goal shown is the lower bound.
// • OCAB (off-pump CABG) 100–200 U/kg, default 200, ACT goal 300 s: practice (P), Ben's decisions of Nov 2 and Nov 4.
// • Vascular/TEVAR 50–100 U/kg (often 5,000 IU flat), no preset ACT goal: the 1.9 review (P; ESVS 2023 not verified)
//   and ACTION-1 (Eur J Vasc Endovasc Surg 2025), where 100 U/kg titrated to an ACT of 200 s did worse than a 5,000 IU
//   bolus — so no goal is preset; the user may set one, labelled practice only.
// • ECMO cannulation 50–100 U/kg, no preset goal: ELSO 2021 (abstract only, no numbers); Ben, Nov 2: the goal varies
//   by centre, the user sets it.
// • Protamine label (FDA): 1 mg neutralizes at least 100 U of heparin; no more than 50 mg in any 10 minutes.
// • i-STAT: Ben, Nov 7 ("ACT goals should be based on I-STAT machines only"). The STS 400-s alternative is for
//   maximally activated or microcuvette ACTs and is no longer offered.

struct CaseTimers: Codable, Equatable {
    /// 1.10: several at once, one course per drug (by AntibioticDef id).
    var antibiotics: [AntibioticCourse] = []
    var heparin: HeparinCourse?
    /// By LabCheckDef id ("abg", "glucose", "coag").
    var checks: [String: LabCheckCourse] = [:]
    /// Snoozed or stopped reminders, by CaseReminder.id. Each holds the due time it applied to, so a new dose or check
    /// (a new due time) brings the reminder back by itself.
    var snoozes: [String: ReminderSnooze] = [:]

    init() {}

    enum CodingKeys: String, CodingKey { case antibiotics, antibiotic, heparin, checks, snoozes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        antibiotics = (try? c.decodeIfPresent([AntibioticCourse].self, forKey: .antibiotics)) ?? []
        // 1.9 kept one course under "antibiotic".
        if antibiotics.isEmpty, let one = try? c.decodeIfPresent(AntibioticCourse.self, forKey: .antibiotic) {
            antibiotics = [one]
        }
        heparin = try? c.decodeIfPresent(HeparinCourse.self, forKey: .heparin)
        checks = (try? c.decodeIfPresent([String: LabCheckCourse].self, forKey: .checks)) ?? [:]
        snoozes = (try? c.decodeIfPresent([String: ReminderSnooze].self, forKey: .snoozes)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !antibiotics.isEmpty { try c.encode(antibiotics, forKey: .antibiotics) }
        try c.encodeIfPresent(heparin, forKey: .heparin)
        if !checks.isEmpty { try c.encode(checks, forKey: .checks) }
        if !snoozes.isEmpty { try c.encode(snoozes, forKey: .snoozes) }
    }

    /// The first course, as 1.9 had one; setting it replaces the list.
    var antibiotic: AntibioticCourse? {
        get { antibiotics.first }
        set { antibiotics = newValue.map { [$0] } ?? [] }
    }

    func course(_ drug: String) -> AntibioticCourse? { antibiotics.first { $0.drug == drug } }

    var isEmpty: Bool { antibiotics.isEmpty && heparin == nil && checks.isEmpty }

    /// Something here runs, or is set up to run, a timer: a timed antibiotic, a lab check, or a heparin course that is more than
    /// recorded doses. The strip on the Intraoperative tab shows only then (1.12, Nov 12): an antibiotic or a heparin dose recorded
    /// without a timer puts no card on the tab.
    var hasTimers: Bool {
        antibiotics.contains { $0.reminders } || !checks.isEmpty || (heparin.map { !$0.isRecordOnly } ?? false)
    }
}

struct TimedEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var time: Date
    /// Units of heparin, mg of protamine, seconds of ACT, mg/dL of glucose; nil for a check done without a value.
    var value: Double?
    /// The blood loss recorded when an antibiotic dose was given (mL), for the 1,500 mL rule.
    var ebl: Double?
    /// An ACT drawn before any heparin.
    var baseline: Bool?
    /// 1.12: an antibiotic dose as it was typed in the quick-add bar ("1 g"), kept as typed and never computed or converted;
    /// nil for a dose logged in Case Timers (a record saved before 1.12 decodes it as nil).
    var given: String?

    init(time: Date, value: Double? = nil, ebl: Double? = nil, baseline: Bool? = nil, given: String? = nil) {
        self.time = time; self.value = value; self.ebl = ebl; self.baseline = baseline; self.given = given
    }
}

struct AntibioticCourse: Codable, Equatable, Identifiable {
    var drug: String
    var doses: [TimedEntry] = []
    /// 1.10: the redose interval chosen for this case (min): nil = the drug's sourced interval (every 1.9 course);
    /// 0 = no redose timer; otherwise the interval (institutional policy).
    var everyMinutes: Double? = nil
    /// 1.12 (Ben, Nov 12): false = recorded only. The doses are kept as for any course, but no redose, long-case or blood-loss
    /// reminder is made, so no notification, no lock-screen countdown and no row in the running list or the strip. A course
    /// saved before this existed has the reminders it had (decode default true).
    var reminders: Bool = true

    var id: String { drug }
    var last: TimedEntry? { doses.max { $0.time < $1.time } }
    var recordOnly: Bool { !reminders }

    /// The redose reminder's switch. On: an ordinary timed course at the drug's default interval, counted from its last dose
    /// (a custom interval is not kept across the switch). Off: recorded only again; the doses stay.
    mutating func setReminders(_ on: Bool) {
        reminders = on
        if on { everyMinutes = nil }
    }

    enum CodingKeys: String, CodingKey { case drug, doses, everyMinutes, reminders }
}

extension AntibioticCourse {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        drug = try c.decode(String.self, forKey: .drug)
        doses = (try? c.decodeIfPresent([TimedEntry].self, forKey: .doses)) ?? []
        everyMinutes = try? c.decodeIfPresent(Double.self, forKey: .everyMinutes)
        reminders = (try? c.decodeIfPresent(Bool.self, forKey: .reminders)) ?? true
    }

    /// As it was written before, plus `reminders` only when it is false: a timed course reads back byte for byte the same.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(drug, forKey: .drug)
        try c.encode(doses, forKey: .doses)
        try c.encodeIfPresent(everyMinutes, forKey: .everyMinutes)
        if !reminders { try c.encode(false, forKey: .reminders) }
    }
}

struct HeparinCourse: Codable, Equatable {
    var purpose: String
    /// The ACT goal in force (s): the purpose's preset or one the user set; nil for none.
    var goal: Double?
    /// The goal was set by the user (where none is preset, shown with the purpose's "practice only" label).
    var userGoal = false
    /// 1.9: maximally activated or microcuvette ACT (bypass: the >400 s goal). Read from saved cases; 1.10 offers
    /// i-STAT goals only (Ben, Nov 7), so it is no longer set.
    var deviceAlt = false
    /// Minutes between ACT checks.
    var actEvery: Double = 30
    var doses: [TimedEntry] = []
    var acts: [TimedEntry] = []
    var protamine: [TimedEntry] = []
    var bypassOn: Date?
    var bypassOff: Date?
    /// The ACT reminder's switch was last turned on at this time (1.10: "Start timer"; 1.12: the switch; a dose never turns it
    /// on). The first check falls due `actEvery` after the later of this and the last ACT.
    var actStart: Date?
    /// The ACT reminder's switch was turned off (1.10: "Stop the ACT timer"). Turning it on again clears this.
    var actOff = false

    init(purpose: String, goal: Double?, actEvery: Double) {
        self.purpose = purpose; self.goal = goal; self.actEvery = actEvery
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        purpose = (try? c.decodeIfPresent(String.self, forKey: .purpose)) ?? "other"
        goal = try? c.decodeIfPresent(Double.self, forKey: .goal)
        userGoal = (try? c.decodeIfPresent(Bool.self, forKey: .userGoal)) ?? false
        deviceAlt = (try? c.decodeIfPresent(Bool.self, forKey: .deviceAlt)) ?? false
        actEvery = (try? c.decodeIfPresent(Double.self, forKey: .actEvery)) ?? 30
        doses = (try? c.decodeIfPresent([TimedEntry].self, forKey: .doses)) ?? []
        acts = (try? c.decodeIfPresent([TimedEntry].self, forKey: .acts)) ?? []
        protamine = (try? c.decodeIfPresent([TimedEntry].self, forKey: .protamine)) ?? []
        bypassOn = try? c.decodeIfPresent(Date.self, forKey: .bypassOn)
        bypassOff = try? c.decodeIfPresent(Date.self, forKey: .bypassOff)
        actStart = try? c.decodeIfPresent(Date.self, forKey: .actStart)
        actOff = (try? c.decodeIfPresent(Bool.self, forKey: .actOff)) ?? false
        // A retired preset reads as the purpose's current one: 1.9's bypass preset was 450 s (reference.json 1.9.0);
        // 1.10 presets 480 s (Ben, Nov 7: "Make ACT goes 480 sec based off STS"; STS 2018 and EACTS 2024: >480 s). Only
        // a preset is moved: a goal the user set, and the 1.9 device goal (deviceAlt, its own caption), stay as saved.
        if !userGoal, !deviceAlt, let g = goal, let retired = Self.retiredPresets[purpose], abs(g - retired.old) < 0.5 {
            goal = retired.now
        }
    }

    /// Presets an earlier version saved, by purpose id, and the preset that replaces each.
    static let retiredPresets: [String: (old: Double, now: Double)] = ["bypass": (450, 480)]

    /// The ACT reminder's switch is on: turned on (actStart) or, in a case saved before 1.12, a bolus was logged, until it
    /// is turned off. A baseline ACT alone does not turn it on: the reminders and the switch row read this one rule. (A course
    /// whose first dose is logged now is pinned off by `logDose`, so the saved-case rule never reaches it.) The saved-case rule
    /// ends with protamine, as it did in build 39 (its recurring ACT check stopped once protamine was logged): a case saved
    /// there after protamine does not start reminding again on its own; a switch turned on runs until it is turned off.
    var actRunning: Bool { !actOff && (actStart != nil || (!doses.isEmpty && protamine.isEmpty)) }

    /// A log begun by recording a dose (the Medications page's "+ Heparin", a typed dose) has the purpose "Other" because none
    /// was chosen: the purpose can still be chosen, and the log is kept. Any other purpose is fixed once something is logged.
    var purposeOpen: Bool { isBlank || purpose == "other" }

    /// This log under the purpose chosen for it: the entries, the bypass times and the reminder stay; the goal becomes the
    /// purpose's preset unless the user set one, and the interval the purpose's first unless the reminder is running.
    func choosing(_ p: HeparinPurpose) -> HeparinCourse {
        var c = self
        c.purpose = p.id
        if !c.userGoal { c.goal = p.goal }
        if !c.actRunning, let every = p.actEvery.first { c.actEvery = every }
        return c
    }

    /// When the switch was turned on: actStart, or for a case saved by build 39 (a bolus started its timer, nothing was
    /// stamped) the first dose. nil while the switch is off.
    var reminderSince: Date? { actRunning ? (actStart ?? sortedDoses.first?.time) : nil }

    var sortedDoses: [TimedEntry] { doses.sorted { $0.time < $1.time } }
    var initialUnits: Double? { sortedDoses.first?.value }
    var totalUnits: Double { doses.compactMap(\.value).reduce(0, +) }
    var protamineMg: Double { protamine.compactMap(\.value).reduce(0, +) }
    var baselineACT: TimedEntry? { acts.filter { $0.baseline == true }.max { $0.time < $1.time } }
    var lastACT: TimedEntry? { acts.filter { $0.baseline != true }.max { $0.time < $1.time } }
    var lastDose: TimedEntry? { doses.max { $0.time < $1.time } }
    var lastProtamine: TimedEntry? { protamine.max { $0.time < $1.time } }
    /// Bypass started and not yet ended.
    var onBypass: Bool { bypassOn != nil && (bypassOff == nil || bypassOff! < bypassOn!) }
    var reversed: Bool { !protamine.isEmpty }
    /// Nothing logged yet: the purpose can still be changed or cleared.
    var isBlank: Bool { doses.isEmpty && acts.isEmpty && protamine.isEmpty && actStart == nil }

    /// Only heparin doses are recorded: no ACT, no protamine, no bypass time, and the ACT reminder is off (1.12, Nov 12: what "+ Heparin"
    /// on the Medications page, or a typed dose, leaves).
    var isRecordOnly: Bool { !doses.isEmpty && acts.isEmpty && protamine.isEmpty && bypassOn == nil && !actRunning }
}

// MARK: - The Heparin & ACT timeline (1.12 follow-up, Ben, Nov 12)

/// One row of "Heparin & ACT log": a baseline ACT, a heparin dose, an ACT sample or a protamine dose, read from the course's
/// own lists (`HeparinCourse` keeps doses, acts and protamine as it always did, so a case saved by build 39 lists every
/// entry at its logged time).
struct HeparinEvent: Identifiable, Hashable {
    /// The order of events that share a minute: the baseline first, then the dose, the ACT, the protamine.
    enum Kind: Int, Hashable { case baseline, heparin, act, protamine }

    var id: UUID
    var kind: Kind
    var time: Date
    /// Seconds (an ACT), units (heparin) or mg (protamine).
    var value: Double?
    /// An ACT that is not a baseline, against the goal in force: true at or above it, false below, nil where no label is
    /// shown (`CaseTimerEngine.goalMet`).
    var goalMet: Bool?
}

extension HeparinCourse {
    /// Every entry in time order, oldest first (it reads down like the anesthesia record).
    var timeline: [HeparinEvent] {
        var out: [HeparinEvent] = []
        for e in doses { out.append(HeparinEvent(id: e.id, kind: .heparin, time: e.time, value: e.value, goalMet: nil)) }
        for e in acts {
            out.append(HeparinEvent(id: e.id, kind: e.baseline == true ? .baseline : .act, time: e.time, value: e.value,
                                    goalMet: CaseTimerEngine.goalMet(e, in: self)))
        }
        for e in protamine { out.append(HeparinEvent(id: e.id, kind: .protamine, time: e.time, value: e.value, goalMet: nil)) }
        return out.sorted {
            if $0.time != $1.time { return $0.time < $1.time }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// Today's rule for "Baseline ACT" (1.10): an ACT logged while no heparin dose is in the log is a baseline.
    var offersBaseline: Bool { doses.isEmpty }

    /// Logs a heparin dose at `time` (a back-timed one is allowed; the caller refuses the future). A dose, the first included,
    /// never turns the ACT reminder on (Ben, Nov 12: "reminder off unless he turns it on"): the switch changes only by its own
    /// control. So that a course that has never had the switch touched reads OFF with a dose in it (the rule for a case saved
    /// before 1.12 is that a bolus implied the timer, `actRunning`), the first dose of such a course records "off"; a switch
    /// turned on before the dose, or turned off, is left as it is. A dose starts no countdown of its own. `now` is kept for the
    /// callers that pass it; nothing reads it.
    mutating func logDose(units: Double, at time: Date, now: Date) {
        let first = doses.isEmpty
        doses.append(TimedEntry(time: time, value: units))
        if first, actStart == nil { actOff = true }
    }

    /// Logs an ACT (`.act`, or `.baseline`; an `.act` while no dose is logged is a baseline, `offersBaseline`). It moves the
    /// ACT reminder's countdown through `CaseTimerEngine.actDue`, by its time; nothing else changes.
    mutating func logACT(seconds: Double, at time: Date, kind: HeparinEvent.Kind) {
        let baseline = kind == .baseline || (kind == .act && offersBaseline)
        acts.append(TimedEntry(time: time, value: seconds, baseline: baseline ? true : nil))
    }

    mutating func logProtamine(mg: Double, at time: Date) {
        protamine.append(TimedEntry(time: time, value: mg))
    }

    /// Changes one entry's time and value (a nil value leaves it); false when the id is not in the log.
    @discardableResult
    mutating func updateEntry(_ id: UUID, time: Date, value: Double?) -> Bool {
        Self.change(&doses, id, time, value) || Self.change(&acts, id, time, value) || Self.change(&protamine, id, time, value)
    }

    private static func change(_ list: inout [TimedEntry], _ id: UUID, _ time: Date, _ value: Double?) -> Bool {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return false }
        list[i].time = time
        if let value { list[i].value = value }
        return true
    }

    mutating func removeEntry(_ id: UUID) {
        doses.removeAll { $0.id == id }
        acts.removeAll { $0.id == id }
        protamine.removeAll { $0.id == id }
    }

    /// The course without one entry (the checks on an edited value run against the rest of the log).
    func removing(_ id: UUID) -> HeparinCourse {
        var c = self
        c.removeEntry(id)
        return c
    }

    /// The ACT reminder's switch. On: the countdown runs from `now` or the last ACT, whichever is later; off: the reminder
    /// stops everywhere and the log stays. Turning it on while it is on changes nothing.
    mutating func setReminder(_ on: Bool, now: Date) {
        if on {
            guard !actRunning else { return }
            actOff = false
            actStart = now
        } else {
            actOff = true
        }
    }
}

/// The words, the clock and the checks of the timeline's rows.
enum HeparinTimeline {
    static let futureText = "That time is in the future."

    static func label(_ k: HeparinEvent.Kind) -> String {
        switch k {
        case .baseline: return "Baseline ACT"
        case .heparin: return "Heparin"
        case .act: return "ACT"
        case .protamine: return "Protamine"
        }
    }

    /// "128 s", "26,000 U", "70 mg".
    static func valueText(_ e: HeparinEvent) -> String {
        guard let v = e.value else { return "" }
        switch e.kind {
        case .heparin: return CaseTimerEngine.grouped(v) + " U"
        case .protamine: return CaseTimerEngine.fmt(v) + " mg"
        case .baseline, .act: return "\(Int(v.rounded())) s"
        }
    }

    /// "at goal" or "below goal" (the wording of "Last ACT 271 s at 01:41 · at goal"); nil: no label.
    static func goalText(_ met: Bool?) -> String? {
        met.map { $0 ? "at goal" : "below goal" }
    }

    /// "09:41" today; "11/11/26 23:50" on another day (as the app writes times).
    static func timeText(_ d: Date, now: Date, calendar: Calendar = .current) -> String {
        calendar.isDate(d, inSameDayAs: now) ? PatientDates.clock(d, calendar: calendar) : PatientDates.dayTime(d, calendar: calendar)
    }

    /// One row read aloud and compared in tests: "09:41 ACT 545 s at goal".
    static func rowText(_ e: HeparinEvent, now: Date, calendar: Calendar = .current) -> String {
        var s = timeText(e.time, now: now, calendar: calendar) + " " + label(e.kind)
        let v = valueText(e)
        if !v.isEmpty { s += " " + v }
        if e.kind != .baseline, let g = goalText(e.goalMet) { s += " " + g }
        return s
    }

    private static func floorMinute(_ d: Date, _ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .minute, for: d)?.start ?? d
    }

    /// A new entry's time: now until a time is picked; a picked clock time is resolved as the antibiotic Start time resolves
    /// it (the nearest such moment, so 23:50 picked just after midnight is yesterday's), to the minute. nil: in the future,
    /// which is not accepted.
    static func resolved(picked: Date?, now: Date, calendar: Calendar = .current) -> Date? {
        guard let picked else { return now }
        let t = floorMinute(CaseTimerRecurrence.resolveStart(picked, now: now), calendar)
        return t <= now ? t : nil
    }

    /// An edited entry's time: unchanged until a time is picked; a picked one keeps the day the control showed (the entry's
    /// own), to the minute. nil: in the future.
    static func resolvedEdit(picked: Date?, original: Date, now: Date, calendar: Calendar = .current) -> Date? {
        guard let picked else { return original }
        let t = floorMinute(picked, calendar)
        return t <= now ? t : nil
    }

    /// The check on a time that resolved to nil.
    static func timeIssue(_ resolved: Date?) -> DoseIssue? {
        resolved == nil ? DoseIssue(level: .block, text: futureText) : nil
    }
}

struct LabCheckCourse: Codable, Equatable {
    /// Minutes between checks.
    var every: Double
    var started: Date
    var done: [TimedEntry] = []
    var last: TimedEntry? { done.max { $0.time < $1.time } }
}

/// A reminder pushed back (Snooze) or put away (Stop) for the due time it had then.
struct ReminderSnooze: Codable, Equatable {
    var due: Date?
    /// .distantFuture: stopped.
    var until: Date
    var stopped: Bool { until == .distantFuture }

    /// Whether this applies to a reminder now due at `due` (the same due time, to the second).
    func applies(to due: Date?) -> Bool {
        switch (self.due, due) {
        case (nil, nil): return true
        case let (a?, b?): return abs(a.timeIntervalSince(b)) < 1
        default: return false
        }
    }
}

// MARK: - Reminders

struct CaseReminder: Identifiable, Hashable {
    enum Kind: String, Hashable { case antibiotic, longCase, bloodLoss, act, protamineACT, abg, glucose, lab }
    enum State: Hashable { case waiting, due, overdue }

    var kind: Kind
    var title: String
    var detail: String
    /// When it falls due; nil: due now (the blood-loss rule).
    var due: Date?
    /// The antibiotic or lab check it belongs to, where a case can have several ("cefazolin", "coag").
    var ref: String? = nil
    /// Snoozed to `due` (its own due time had passed).
    var snoozed = false
    /// For a rule due now (no `due`): the dose it runs from (blood loss since the last dose), so a snooze or stop
    /// applies to this occurrence only and a new dose brings the reminder back.
    var since: Date? = nil
    var id: String { ref.map { kind.rawValue + "." + $0 } ?? kind.rawValue }
    /// What a snooze or stop is matched against: the due time, or for a due-now rule the dose it runs from.
    var occurrence: Date? { due ?? since }

    /// Overdue five minutes after it falls due.
    func state(at now: Date) -> State { Self.state(due: due, at: now) }

    /// The same rule for a bare due time (the ACT reminder's switch row colours "Next ACT due" by it).
    static func state(due: Date?, at now: Date) -> State {
        guard let due else { return .due }
        if now < due { return .waiting }
        return now.timeIntervalSince(due) > 300 ? .overdue : .due
    }
}

/// A check on a dose before it is logged. `.confirm` needs a second tap; `.block` cannot be logged.
struct DoseIssue: Hashable, Identifiable {
    enum Level: Int, Comparable, Hashable {
        case note, soft, confirm, block
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    var level: Level
    var text: String
    var id: String { "\(level.rawValue):\(text)" }
}

extension Array where Element == DoseIssue {
    var worst: DoseIssue.Level? { map(\.level).max() }
    var blocks: Bool { contains { $0.level == .block } }
    var needsConfirm: Bool { contains { $0.level == .confirm } }
}

// MARK: - Chips and recurrence (1.10)

/// A single-choice chip row's rule: a tap selects, a second tap on the selected chip clears it (Ben, Nov 7: "Chips in
/// case timers should be able to be de-selected").
enum ChipToggle {
    static func tap<T: Equatable>(_ current: T?, _ tapped: T) -> T? { current == tapped ? nil : tapped }
}

/// "Recurring every": three interval chips and "Other", which opens a picker in 5-minute steps.
struct RecurrencePick: Equatable {
    /// The interval (min); nil: none chosen.
    var minutes: Double?
    /// The value came from the Other picker.
    var other = false

    init(minutes: Double? = nil, other: Bool = false) { self.minutes = minutes; self.other = other }

    /// The pick that shows a running interval: its chip when there is one, Other otherwise.
    init(running minutes: Double?, chips: [Double]) {
        guard let m = minutes, m > 0 else { self.init(); return }
        self.init(minutes: m, other: !chips.contains(m))
    }

    func chipOn(_ m: Double) -> Bool { !other && minutes == m }

    mutating func tapChip(_ m: Double) {
        if chipOn(m) { minutes = nil } else { minutes = m; other = false }
    }

    /// Other: opens the picker at `preselect`; a second tap closes it and clears the choice.
    mutating func tapOther(preselect: Double) {
        if other { other = false; minutes = nil } else { other = true; minutes = preselect }
    }

    mutating func setOther(_ m: Double) { other = true; minutes = m }
}

enum CaseTimerRecurrence {
    static let otherStep: Double = 5

    /// Antibiotic redose chips (min): the drug's sourced interval with an hour either side (institutional policies
    /// differ, Ben, Nov 7); a drug with no routine redose offers 4, 6 and 8 h, none selected.
    static func antibioticChips(_ def: AntibioticDef) -> [Double] {
        guard let h = def.redoseHours, h > 0 else { return [240, 360, 480] }
        var out: [Double] = []
        for m in [max(60, h * 60 - 60), h * 60, h * 60 + 60] where !out.contains(m) { out.append(m) }
        return out
    }

    /// Lab check chips: 30, 60 and 90 min (Ben: "Check every: 30 min, 60 min, Custom").
    static func labChips(_ def: LabCheckDef) -> [Double] {
        let every = (def.every ?? []).filter { $0 > 0 }
        return every.count >= 3 ? Array(every.prefix(3)) : [30, 60, 90]
    }

    /// ACT recheck chips: the purpose's intervals (30 and 20 min, signed off in 1.9) and 60 min.
    static func actChips(_ p: HeparinPurpose?) -> [Double] {
        Array(Set((p?.actEvery ?? [30, 20]) + [60])).sorted().prefix(3).map { $0 }
    }

    /// The Other picker's values, in 5-minute steps: up to 12 h for an antibiotic, 4 h for a lab, 2 h for the ACT.
    static func otherValues(maxMinutes: Double) -> [Double] {
        Array(stride(from: otherStep, through: maxMinutes, by: otherStep))
    }

    static let antibioticMax: Double = 720
    static let labMax: Double = 240
    static let actMax: Double = 120

    /// The Other chip's label: "Other", then the chosen value once picked, short enough that the row stays on one line
    /// at 375 pt (coordinator decision: every chip row that fits goes on one line; review 1.10: "Other · 45 min"
    /// wrapped the lab rows). "45 min", "2 h", "1h 45m"; VoiceOver reads the full interval (otherChipA11y).
    static func otherChipLabel(_ pick: RecurrencePick) -> String {
        guard pick.other, let v = pick.minutes, v > 0 else { return "Other" }
        let m = Int(v.rounded())
        if m < 60 || m % 60 == 0 { return CaseTimerEngine.interval(v) }
        return "\(m / 60)h \(m % 60)m"
    }

    static func otherChipA11y(_ pick: RecurrencePick) -> String {
        guard pick.other, let v = pick.minutes, v > 0 else { return "Other interval" }
        return "Other interval, " + CaseTimerEngine.interval(v)
    }

    /// The value the Other picker opens at: the current choice, else the item's own default, on the 5-minute grid.
    static func otherPreselect(current: Double?, preferred: Double, maxMinutes: Double) -> Double {
        let v = (current ?? 0) > 0 ? current! : preferred
        let snapped = (v / otherStep).rounded() * otherStep
        return min(max(otherStep, snapped), maxMinutes)
    }

    /// The default the Other picker preselects for an antibiotic: its interval, or the long-case reminder (8 h).
    static func antibioticPreferred(_ def: AntibioticDef, rules: AntibioticRules) -> Double {
        if let h = def.redoseHours, h > 0 { return h * 60 }
        return (rules.longCaseHours ?? 8) * 60
    }

    /// The chip preselected when an antibiotic is added: its sourced interval; none for a drug without one.
    static func antibioticDefault(_ def: AntibioticDef) -> Double? { def.redoseHours.map { $0 * 60 } }

    /// What to store on a new course from the pick: 0 when none is chosen (no redose timer).
    static func storedInterval(_ pick: RecurrencePick) -> Double { pick.minutes ?? 0 }

    /// The redose interval in force (min), or nil for none.
    static func redoseMinutes(_ course: AntibioticCourse, def: AntibioticDef) -> Double? {
        if let m = course.everyMinutes { return m > 0 ? m : nil }
        return def.redoseHours.map { $0 * 60 }
    }

    /// A start time picked on a clock (hour and minute only) resolved to the nearest such moment: a time more than 12 h
    /// ahead was yesterday's, one more than 12 h back is tomorrow's.
    static func resolveStart(_ picked: Date, now: Date) -> Date {
        let d = picked.timeIntervalSince(now)
        if d > 12 * 3600 { return picked.addingTimeInterval(-86400) }
        if d < -12 * 3600 { return picked.addingTimeInterval(86400) }
        return picked
    }
}

/// A Start timer's "Start time" (Ben, Nov 7: "defaulted to current time"): nil until the user picks one, so it is the
/// current time when the picker shows and when Start is tapped, however long the section has been open.
struct StartTimePick: Equatable {
    var picked: Date?

    init(picked: Date? = nil) { self.picked = picked }

    /// What the picker shows.
    func shown(now: Date) -> Date { picked ?? now }

    /// The start logged on Start: the picked clock time resolved to the nearest such moment, or now.
    func resolved(now: Date) -> Date { picked.map { CaseTimerRecurrence.resolveStart($0, now: now) } ?? now }
}

enum CaseTimerEngine {

    // MARK: Reminders

    /// Everything that is timed or due for this case, soonest first (a due-now rule first), snoozes applied and
    /// stopped reminders left out.
    static func reminders(_ t: CaseTimers, record r: PatientRecord, data d: CaseTimerData) -> [CaseReminder] {
        var out: [CaseReminder] = []
        let purpose = t.heparin.flatMap { d.purpose($0.purpose) }
        let onBypass = t.heparin?.onBypass ?? false

        for a in t.antibiotics {
            // A course recorded only (1.12) makes no reminder of any kind: not the redose, the long case or the blood loss.
            guard a.reminders, let def = d.antibiotic(a.drug), let last = a.last else { continue }
            let skipOnBypass = def.id == "gentamicin" && (onBypass || purpose?.isBypass == true)
            if skipOnBypass { continue }
            if let m = CaseTimerRecurrence.redoseMinutes(a, def: def) {
                out.append(CaseReminder(kind: .antibiotic, title: "\(def.name) redose",
                                        detail: "\(antibioticDose(def, record: r).text) · every \(interval(m)) from the last dose",
                                        due: last.time.addingTimeInterval(m * 60), ref: def.id))
            } else if def.redoseHours == nil, let h = d.antibioticRules.longCaseHours, h > 0 {
                out.append(CaseReminder(kind: .longCase, title: "\(def.name): long case",
                                        detail: d.antibioticRules.longCase ?? d.antibioticRules.noRedose,
                                        due: last.time.addingTimeInterval(h * 3600), ref: def.id))
            }
            if let ebl = r.fluids["ebl"], ebl - (last.ebl ?? 0) >= d.antibioticRules.bloodLossML {
                // Short enough for the running list (Ben, Nov 7: "Blood loss over 1,50…" was cut off); the rule's full
                // sentence stays in reference.json. Bratzler 2013: redose after blood loss over 1,500 mL.
                out.append(CaseReminder(kind: .bloodLoss, title: "\(def.name) redose: blood loss",
                                        detail: "EBL ≥ \(grouped(d.antibioticRules.bloodLossML)) mL since the last dose",
                                        due: nil, ref: def.id, since: last.time))
            }
        }

        if let h = t.heparin {
            let p = d.protamine
            if let prot = h.lastProtamine {
                let end = protamineEnd(prot, rules: p)
                if (h.lastACT?.time ?? .distantPast) < end {
                    let base = h.baselineACT?.value.map { "baseline \(Int($0)) s" } ?? "baseline not logged"
                    out.append(CaseReminder(kind: .protamineACT, title: "ACT after protamine",
                                            detail: "Compare with the \(base)",
                                            due: end.addingTimeInterval(p.postActMinutes * 60)))
                }
            }
            // 1.12: the ACT reminder is its own switch; it runs after protamine too until it is turned off (Ben: "it can be turned
            // off (for example after protamine)"), next to the one-time ACT after protamine.
            if let due = actDue(h) {
                let goal = h.goal.map { "Goal ≥ \(Int($0)) s" } ?? "No preset goal"
                out.append(CaseReminder(kind: .act, title: "ACT check", detail: goal + " · every \(interval(h.actEvery))", due: due))
            }
        }

        for def in d.checks {
            guard let c = t.checks[def.id], c.every > 0 else { continue }
            let from = c.last?.time ?? c.started
            let kind: CaseReminder.Kind = def.id == "glucose" ? .glucose : (def.id == "abg" ? .abg : .lab)
            out.append(CaseReminder(kind: kind, title: "\(def.name) check", detail: "Every \(interval(c.every))",
                                    due: from.addingTimeInterval(c.every * 60), ref: kind == .lab ? def.id : nil))
        }

        // Snoozed and stopped.
        out = out.compactMap { rem in
            guard let s = t.snoozes[rem.id], s.applies(to: rem.occurrence) else { return rem }
            if s.stopped { return nil }
            var r = rem
            r.due = s.until
            r.snoozed = true
            return r
        }

        return sortedByDue(out)
    }

    /// Soonest first; a reminder due now (no time) first; ties by title.
    static func sortedByDue(_ items: [CaseReminder]) -> [CaseReminder] {
        items.sorted {
            let a = $0.due ?? .distantPast, b = $1.due ?? .distantPast
            return a != b ? a < b : $0.title < $1.title
        }
    }

    /// When the next ACT falls due (1.12, Ben's answers 2 to 4): `actEvery` after the LATEST ACT sample in the log (a baseline
    /// counts, by its logged time), or after the moment the switch was turned on if that is later or there is no sample.
    /// Logging or editing an ACT moves it; a heparin or protamine dose does not (a dose starts no countdown of its own);
    /// back-timing an ACT earlier than the latest one does not. nil while the switch is off. This is the one due-time
    /// function: the running list, the notification, the lock-screen activity, the strip on My Patient and the switch row
    /// all read it through `reminders`.
    static func actDue(_ h: HeparinCourse) -> Date? {
        guard let on = h.reminderSince else { return nil }
        let anchor = max(on, h.acts.map(\.time).max() ?? on)
        return anchor.addingTimeInterval(h.actEvery * 60)
    }

    /// The moment a logged protamine dose ends at the label's fastest rate (50 mg per 10 min), from its start.
    static func protamineEnd(_ e: TimedEntry, rules p: ProtamineRules) -> Date {
        e.time.addingTimeInterval(minimumMinutes(mg: e.value ?? 0, rules: p) * 60)
    }

    /// The shortest time the label allows for a dose: no more than 50 mg in any 10 minutes.
    static func minimumMinutes(mg: Double, rules p: ProtamineRules) -> Double {
        guard mg > 0, p.maxMgPer10Min > 0 else { return 0 }
        return (mg / p.maxMgPer10Min * 10).rounded(.up)
    }

    /// "01h:23m:45s" to the due time; past it, the time overdue.
    static func countdown(to due: Date?, now: Date) -> String {
        guard let due else { return "00h:00m:00s" }
        let s = Int(abs(due.timeIntervalSince(now)).rounded(.down))
        return String(format: "%02dh:%02dm:%02ds", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// "45 min", "4 h", "3 h 25 min".
    static func interval(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }

    // MARK: Antibiotics

    struct AntibioticDose: Hashable {
        var text: String
        /// "Weight needed", "Height and sex needed for the dosing weight".
        var needs: String?
    }

    /// The adult dose for this patient, from the drug's rule; the written dose when the weight is missing.
    static func antibioticDose(_ def: AntibioticDef, record r: PatientRecord) -> AntibioticDose {
        if let g = def.doseG {
            guard let w = r.weightKg, w > 0 else { return AntibioticDose(text: def.dose, needs: nil) }
            if let heavy = def.heavyKg, let hg = def.heavyDoseG, w >= heavy { return AntibioticDose(text: "\(fmt(hg)) g") }
            return AntibioticDose(text: "\(fmt(g)) g")
        }
        if let perKg = def.mgPerKg {
            guard let w = r.weightKg, w > 0 else { return AntibioticDose(text: def.dose, needs: "Weight needed") }
            var kg = w
            var how = "\(fmt(perKg)) mg/kg"
            if def.dosingWeight == true {
                guard let dw = dosingWeight(actual: w, ibw: r.ibw) else {
                    return AntibioticDose(text: def.dose, needs: "Height and sex needed for the dosing weight")
                }
                kg = dw.kg
                how += dw.adjusted ? " × dosing weight \(fmt(dw.kg.rounded())) kg" : " × \(fmt(w.rounded())) kg"
            } else {
                how += " × \(fmt(w.rounded())) kg"
            }
            let mg = (perKg * kg / 10).rounded() * 10
            return AntibioticDose(text: "\(grouped(mg)) mg (\(how))")
        }
        return AntibioticDose(text: def.dose)
    }

    /// Bratzler 2013 for gentamicin: above 120% of ideal body weight, IBW + 0.4 × (actual − IBW); otherwise the actual
    /// weight. nil without an ideal body weight (height and sex).
    static func dosingWeight(actual: Double, ibw: Double?) -> (kg: Double, adjusted: Bool)? {
        guard let ibw, ibw > 0, actual > 0 else { return nil }
        if actual > 1.2 * ibw { return (ibw + 0.4 * (actual - ibw), true) }
        return (actual, false)
    }

    /// Renal dysfunction on the record (dialysis or chronic kidney disease): a caution, never a changed interval.
    static func renalCaution(_ r: PatientRecord) -> Bool { r.dialysis || r.problems.contains("ckd") }

    // MARK: Who may use the dosing

    /// Children are locked out of every weight-based suggestion: the defaults are for adults.
    static func isChild(_ r: PatientRecord) -> Bool { (r.ageYears ?? 18) < 18 }

    /// Problems with the weight before any U/kg is shown.
    static func weightIssues(_ r: PatientRecord, data d: CaseTimerData) -> [DoseIssue] {
        if isChild(r) { return [DoseIssue(level: .block, text: "Adult defaults only: not for children.")] }
        guard let w = r.weightKg, w > 0 else { return [DoseIssue(level: .block, text: "Enter the weight first.")] }
        if let lim = d.weightFlag, lim.count == 2, w < lim[0] || w > lim[1] {
            return [DoseIssue(level: .confirm, text: "\(fmt(w.rounded())) kg is outside \(fmt(lim[0]))–\(fmt(lim[1])) kg: check the weight.")]
        }
        return []
    }

    // MARK: Heparin

    /// Heparin in whole units the way it is drawn up: to 1,000 U at 10,000 U or more, 500 U below (Ben, Nov 4).
    static func roundUnits(_ u: Double) -> Double {
        let step: Double = u >= 10000 ? 1000 : 500
        return (u / step).rounded() * step
    }

    /// The suggested first bolus for the purpose and weight, rounded as drawn up.
    static func suggestedBolus(_ p: HeparinPurpose, weightKg w: Double?) -> Double? {
        guard let w, w > 0, let perKg = p.doseDefault else { return nil }
        return roundUnits(perKg * w)
    }

    /// The flat dose for this weight (Ben, Nov 7: "Only give heparin flat dose … use ≈"): "300–400 U/kg ≈ 24,000–32,000
    /// U"; one number when both ends round alike; a purpose with a flat-dose habit adds it ("or 5,000 U flat"). nil
    /// without a weight (the view asks for it) or without a range (Other).
    static func flatDose(_ p: HeparinPurpose, weightKg w: Double?) -> String? {
        guard let lo = p.doseLow, let hi = p.doseHigh, let w, w > 0 else { return nil }
        let a = roundUnits(lo * w), b = roundUnits(hi * w)
        var s = "\(fmt(lo))–\(fmt(hi)) U/kg ≈ " + (a == b ? "\(grouped(a)) U" : "\(grouped(a))–\(grouped(b)) U")
        if let flat = p.flatUnits { s += ", or \(grouped(flat)) U flat" }
        return s
    }

    /// "300–400 U/kg = 24,000–32,000 U" (1.9 text, kept for the dose checks' "usual" wording).
    static func usualRange(_ p: HeparinPurpose, weightKg w: Double?) -> String? {
        guard let lo = p.doseLow, let hi = p.doseHigh else { return nil }
        var s = "\(fmt(lo))–\(fmt(hi)) U/kg"
        if let w, w > 0 { s += " = \(grouped((lo * w / 100).rounded() * 100))–\(grouped((hi * w / 100).rounded() * 100)) U" }
        if let flat = p.flatUnits { s += ", or \(grouped(flat)) U flat" }
        return s
    }

    /// Checks on a heparin dose before it is logged (the review doc's safety rules).
    static func heparinIssues(units u: Double, course: HeparinCourse?, purpose p: HeparinPurpose, record r: PatientRecord,
                              data d: CaseTimerData) -> [DoseIssue] {
        var out = weightIssues(r, data: d)
        if out.blocks { return out }
        guard u > 0 else { return [DoseIssue(level: .block, text: "Enter the dose in units.")] }
        let rules = d.heparinRules
        let first = course?.doses.isEmpty ?? true
        if u < rules.unitsCheckBelow {
            out.append(DoseIssue(level: .confirm, text: "\(grouped(u)) U is very small: heparin is entered in units, not thousands or mg. Did you mean \(grouped(u * 1000)) U?"))
        }
        guard let w = r.weightKg, w > 0 else { return out }
        let perKg = u / w
        let perKgText = "\(fmt(perKg.rounded())) U/kg"
        if !(rules.hardConfirmExempt ?? ["bypass"]).contains(p.id) && perKg >= rules.hardConfirmNonBypassUPerKg {
            out.append(DoseIssue(level: .confirm, text: "\(perKgText) is a bypass-size dose, and the purpose is \(p.name)."))
        }
        if first {
            if p.isBypass && perKg < rules.bypassMinUPerKg {
                out.append(DoseIssue(level: .confirm, text: "\(perKgText) is under the bypass dose (usual \(usualRange(p, weightKg: nil) ?? "300–400 U/kg"))."))
            } else if let lo = p.doseLow, let hi = p.doseHigh {
                let pct = rules.outOfRangePct / 100
                if perKg < lo * (1 - pct) || perKg > hi * (1 + pct) {
                    let src = d.sources(p.sources ?? []).first.map { " (\(shortLabel($0.label)))" } ?? " (practice)"
                    out.append(DoseIssue(level: .soft, text: "\(perKgText): usual \(fmt(lo))–\(fmt(hi)) U/kg\(src)."))
                }
            }
        }
        return out
    }

    /// An ACT is entered in seconds; the same plausibility rule 1.10 had (nothing under 30 s is logged).
    static func actIssues(seconds: Double?) -> [DoseIssue] {
        guard let s = seconds else { return [DoseIssue(level: .block, text: "")] }
        return s < 30 ? [DoseIssue(level: .block, text: "An ACT is entered in seconds (30 or more).")] : []
    }

    /// The checks on a timeline entry before it is logged or an edit is saved: the dose checks, the ACT check and the protamine
    /// checks as each had them. `course` is the log the entry joins (for an edit, the log without that entry).
    static func entryIssues(kind: HeparinEvent.Kind, value: Double?, course: HeparinCourse, purpose p: HeparinPurpose,
                            record r: PatientRecord, data d: CaseTimerData) -> [DoseIssue] {
        let empty = DoseIssue(level: .block, text: "")
        switch kind {
        case .heparin:
            guard let u = value else { return weightIssues(r, data: d).filter { $0.level == .block } + [empty] }
            return heparinIssues(units: u, course: course, purpose: p, record: r, data: d)
        case .baseline, .act:
            return actIssues(seconds: value)
        case .protamine:
            guard let mg = value else { return [empty] }
            return protamineIssues(mg: mg, course: course, purpose: p, rules: d.protamine)
        }
    }

    /// Checks on an ACT goal the user sets.
    static func goalIssues(_ goal: Double?, purpose p: HeparinPurpose, rules: HeparinRules) -> [DoseIssue] {
        guard let g = goal else { return [] }
        if g < 100 || g > 999 { return [DoseIssue(level: .block, text: "An ACT goal is entered in seconds (100–999).")] }
        if p.isBypass && g < rules.bypassMinGoal {
            return [DoseIssue(level: .confirm, text: "A bypass ACT goal under \(Int(rules.bypassMinGoal)) s.")]
        }
        return []
    }

    /// The goal a purpose starts with: its preset, or none.
    static func presetGoal(_ p: HeparinPurpose) -> Double? { p.goal }

    /// The course with the user's goal: a goal equal to the preset is the preset again; nil clears a user goal back to
    /// the preset.
    static func settingGoal(_ h: HeparinCourse, to goal: Double?, purpose p: HeparinPurpose) -> HeparinCourse {
        var c = h
        if let g = goal, g != p.goal {
            c.goal = g; c.userGoal = true
        } else {
            c.goal = p.goal; c.userGoal = false
        }
        c.deviceAlt = false
        return c
    }

    struct HeparinStatus: Hashable {
        var initialUnits: Double?
        var totalUnits: Double
        var initialPerKg: Double?
        var lastACT: Double?
        var lastACTTime: Date?
        var goal: Double?
        /// nil: no goal or no ACT since the last bolus.
        var goalMet: Bool?
    }

    /// The caption under the ACT goal: the device once, then where the number comes from ("i-STAT · STS 2018 and
    /// EACTS 2024: above 480 s"). A purpose text that already starts with the device (reference.json 1.10.0 wrote
    /// "i-STAT; STS 2018 …") is not prefixed again.
    static func goalCaption(_ h: HeparinCourse, _ p: HeparinPurpose, device: String) -> String {
        if h.userGoal { return "Your goal, \(device). " + (p.goal.map { "Preset ≥ \(Int($0)) s." } ?? (p.userGoalText.map { "Usual: \($0)." } ?? "")) }
        if h.deviceAlt { return "Set in 1.9 for a maximally activated or microcuvette ACT." }
        if h.goal == nil { return device + (p.userGoalText.map { ". If you set one: \($0)." } ?? ". Set one if you use one.") }
        guard var text = p.goalText?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return device }
        if !device.isEmpty, text.lowercased().hasPrefix(device.lowercased()) {
            text = String(text.dropFirst(device.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ;·:,"))
        }
        return text.isEmpty ? device : device + " · " + text
    }

    /// The ⓘ under Heparin & ACT (Ben's answer 4, Nov 7; i-STAT only, Ben, Nov 7).
    static func actGoalInfo(device: String) -> String { "ACT goals assume \(device) values." }

    /// The ⓘ under Protamine (Ben's answer 4, Nov 7): method (c) in one line. On bypass EACTS 2024 §9.3.2 (dose on the
    /// initial heparin; ratio below 1.0; "Additional doses of protamine may instead lead to overdosing"); without
    /// bypass the label's 1 mg per 100 U is the cap and there is no lower bound.
    static func protamineInfo(bypass: Bool, rules pr: ProtamineRules) -> String {
        if bypass {
            return "Suggested from the initial heparin dose (\(fmt(pr.ratioLow))–\(fmt(pr.ratioHigh)) mg per 100 U, capped at \(fmt(pr.ratioHigh)) mg per 100 U), not the total given; later doses do not change it (EACTS 2024)."
        }
        return "Capped at \(fmt(pr.ratioHigh)) mg per 100 U of the initial heparin dose (label), not the total given; later doses do not change it."
    }

    /// The goal is reached at the goal value or above (Ben, Nov 7: "≥ 480"; STS 2018 and EACTS 2024 write ">480 s"). The one
    /// comparison behind "Last ACT … · at goal" (status) and every timeline row's label (goalMet).
    static func atGoal(_ value: Double, goal: Double) -> Bool { value >= goal }

    /// One ACT sample against the goal in force, for its row in the timeline (1.12): true at or above the goal, false below.
    /// nil: a baseline (never labelled), no goal, no value, or no heparin dose logged by the time it was drawn (an ACT before
    /// any heparin says nothing about the goal).
    static func goalMet(_ act: TimedEntry, in h: HeparinCourse) -> Bool? {
        guard act.baseline != true, let goal = h.goal, let value = act.value else { return nil }
        guard h.doses.contains(where: { $0.time <= act.time }) else { return nil }
        return atGoal(value, goal: goal)
    }

    static func status(_ h: HeparinCourse, record r: PatientRecord) -> HeparinStatus {
        let act = h.lastACT
        let afterBolus = act.map { a in h.lastDose.map { a.time >= $0.time } ?? true } ?? false
        let met: Bool? = (h.goal != nil && afterBolus) ? atGoal(act?.value ?? 0, goal: h.goal!) : nil
        let perKg = h.initialUnits.flatMap { u in r.weightKg.map { u / $0 } }
        return HeparinStatus(initialUnits: h.initialUnits, totalUnits: h.totalUnits, initialPerKg: perKg,
                             lastACT: act?.value, lastACTTime: act?.time, goal: h.goal, goalMet: met)
    }

    // MARK: Protamine

    /// Method (c) (Ben, Nov 7): a fixed ratio on the INITIAL heparin dose, never the running total, with a cap; the
    /// current ACT beside it. On bypass 0.8–1.0 mg per 100 U of the initial dose (EACTS 2024: "should be kept below
    /// 1.0"; the 0.8 floor is practice, signed off in 1.9; EACTS cites a titrated ratio of 0.81), capped at 1.0 mg per
    /// 100 U. Without bypass the label's 1 mg per 100 U of the initial dose is the cap and there is no lower bound
    /// (titrate to the ACT). Later top-up doses never raise the suggestion (EACTS: "Additional doses of protamine may
    /// instead lead to overdosing").
    struct ProtamineSuggestion: Hashable {
        /// The initial heparin dose (U), the basis of every ratio here.
        var basisUnits: Double
        var basisIsInitial: Bool { true }
        var totalUnits: Double
        /// The suggested range (mg), bypass only.
        var lowMg: Double?
        var highMg: Double?
        /// The cap (mg): ratioHigh mg per 100 U of the initial dose.
        var capMg: Double
        /// 1.9 name for the cap without bypass.
        var labelMaxMg: Double? { lowMg == nil ? capMg : nil }
        var givenMg: Double
        /// Left under the cap (mg), never negative.
        var remainingMg: Double { max(0, capMg - givenMg) }
        var lastACT: Double?
        var lastACTTime: Date?
        var baselineACT: Double?
    }

    static func protamineSuggestion(_ h: HeparinCourse, purpose p: HeparinPurpose, rules pr: ProtamineRules) -> ProtamineSuggestion? {
        guard let initial = h.initialUnits, initial > 0 else { return nil }
        let per100 = initial / 100
        // A cap never rounds up past ratioHigh mg per 100 U: down to 5 mg, which is exact for doses drawn in 500-U
        // steps (7,500 U → 75 mg, not 80). The low end is rounded to 10 mg and never above the cap.
        let cap = floor5(per100 * pr.ratioHigh)
        let act = h.lastACT
        return ProtamineSuggestion(basisUnits: initial, totalUnits: h.totalUnits,
                                   lowMg: p.isBypass ? min(round10(per100 * pr.ratioLow), cap) : nil,
                                   highMg: p.isBypass ? cap : nil,
                                   capMg: cap, givenMg: h.protamineMg,
                                   lastACT: act?.value, lastACTTime: act?.time, baselineACT: h.baselineACT?.value)
    }

    /// mg of protamine per 100 U of the initial dose, counting what was already given.
    static func protamineRatio(addingMg mg: Double, _ s: ProtamineSuggestion) -> Double {
        guard s.basisUnits > 0 else { return 0 }
        return (s.givenMg + mg) / (s.basisUnits / 100)
    }

    /// mg of protamine per 100 U of all the heparin given, counting what was already given.
    static func protamineRatioOfTotal(addingMg mg: Double, _ s: ProtamineSuggestion) -> Double {
        let units = max(s.totalUnits, s.basisUnits)
        guard units > 0 else { return 0 }
        return (s.givenMg + mg) / (units / 100)
    }

    /// Checks on a protamine dose before it is logged: the STS 2018 ceiling (block above 2.6 mg per 100 U), a second
    /// tap above 1.3 mg per 100 U of the initial dose, the cap at 1:1 (EACTS: below 1.0), bypass still running, and the
    /// label's rate.
    ///
    /// The ceiling's basis is the one 1.9 used: on bypass the INITIAL bolus (the 1.9 review doc; EACTS 2024 doses on
    /// the initial heparin), so top-ups never relax the block there; off bypass all the heparin given, because STS 2018
    /// does not state its heparin basis (source note above) and large top-ups after a small first bolus are common in
    /// long vascular and TAVR cases. Method (c)'s initial-dose basis (Ben, Nov 7) applies to the suggestion, its cap
    /// and the 1.3 second tap for every purpose.
    static func protamineIssues(mg: Double, course h: HeparinCourse, purpose p: HeparinPurpose, rules pr: ProtamineRules) -> [DoseIssue] {
        guard mg > 0 else { return [DoseIssue(level: .block, text: "Enter the dose in mg.")] }
        guard let s = protamineSuggestion(h, purpose: p, rules: pr) else {
            return [DoseIssue(level: .block, text: "Log the heparin first.")]
        }
        var out: [DoseIssue] = []
        let ratio = protamineRatio(addingMg: mg, s)
        let ofTotal = protamineRatioOfTotal(addingMg: mg, s)
        let ratioText = String(format: "%.1f", ratio)
        let topUps = s.totalUnits > s.basisUnits
        // On bypass the ceiling stays on the initial bolus (1.9); off bypass it reads on everything given.
        let ceiling = p.isBypass ? ratio : ofTotal
        let ceilingBasis = p.isBypass ? "of the initial dose" : "of the heparin given"
        if ceiling > pr.blockAbove {
            out.append(DoseIssue(level: .block, text: "\(String(format: "%.1f", ceiling)) mg per 100 U \(ceilingBasis): over the STS 2018 ceiling of \(fmt(pr.blockAbove))."))
        } else if ratio > pr.flagAbove {
            // Two decimals for the total, so a value just under the threshold never reads as the threshold itself
            // (140 mg / 11,000 U is 1.27, not "1.3").
            let total = topUps ? "; \(String(format: "%.2f", ofTotal)) per 100 U of all \(grouped(s.totalUnits)) U given" : ""
            out.append(DoseIssue(level: .confirm, text: "\(ratioText) mg per 100 U of the initial dose, over \(fmt(pr.flagAbove))\(total)."))
        } else if ratio > pr.ratioHigh + 0.001 {
            out.append(DoseIssue(level: .soft, text: "\(ratioText) mg per 100 U: above the cap of 1:1. \(pr.ratioNote)"))
        }
        if h.onBypass {
            out.append(DoseIssue(level: .confirm, text: pr.onBypass))
        }
        if mg > pr.maxMgPer10Min {
            out.append(DoseIssue(level: .note, text: "Over at least \(fmt(minimumMinutes(mg: mg, rules: pr))) min: \(pr.rate.lowercasedFirst)"))
        }
        return out
    }

    // MARK: Lab checks

    /// A glucose outside the alert range: "High", "Low", or nil.
    static func glucoseAlert(_ v: Double, def: LabCheckDef) -> String? {
        if let hi = def.high, v > hi { return "High: above \(fmt(hi)) \(def.unit ?? "")" }
        if let lo = def.low, v < lo { return "Low: below \(fmt(lo)) \(def.unit ?? "")" }
        return nil
    }

    // MARK: Text

    /// "Bratzler 2013, ASHP/…" → "Bratzler 2013".
    static func shortLabel(_ s: String) -> String { s.components(separatedBy: ",").first ?? s }

    static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    static func grouped(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? fmt(v)
    }

    static func round10(_ v: Double) -> Double { (v / 10).rounded() * 10 }

    /// Down to 5 (a cap); a hair of tolerance so 75.0000001 or 74.9999999 read as 75.
    static func floor5(_ v: Double) -> Double { ((v + 1e-6) / 5).rounded(.down) * 5 }
}

// MARK: - Done, snooze and stop

extension CaseTimers {
    /// Snooze a reminder: it comes back `minutes` from now, or from its due time when that is later.
    mutating func snooze(_ rem: CaseReminder, minutes: Double = 5, now: Date) {
        let from = rem.snoozed ? now : max(now, rem.due ?? now)
        snoozes[rem.id] = ReminderSnooze(due: originalDue(rem), until: from.addingTimeInterval(minutes * 60))
    }

    /// A new dose of an antibiotic: its redose, long-case and blood-loss reminders run from it, so a snooze or stop put on
    /// them before is cleared (markDone, and the quick-add bar's dose, IntraopAntibiotic.apply).
    mutating func clearAntibioticSnoozes(_ drug: String) {
        for k in [CaseReminder.Kind.antibiotic, .longCase, .bloodLoss] { snoozes[k.rawValue + "." + drug] = nil }
    }

    /// The redose reminder's switch on an antibiotic course (1.12): on makes it an ordinary timed course at the drug's default
    /// interval, counted from its last dose (it needs that interval: `hasInterval`); off returns it to recorded only, doses kept.
    /// The snoozes put on its reminders before are cleared either way.
    mutating func setAntibioticReminders(_ on: Bool, drug: String, hasInterval: Bool) {
        guard let i = antibiotics.firstIndex(where: { $0.drug == drug }) else { return }
        if on, !hasInterval { return }
        guard antibiotics[i].reminders != on else { return }
        antibiotics[i].setReminders(on)
        clearAntibioticSnoozes(drug)
    }

    /// The due time a reminder had before any snooze (for a due-now rule, the dose it runs from).
    private func originalDue(_ rem: CaseReminder) -> Date? { rem.snoozed ? snoozes[rem.id]?.due : rem.occurrence }

    /// Stop a reminder: the timer behind it ends (an antibiotic's redose timer, a lab check, the ACT timer); a rule's
    /// reminder (long case, blood loss, ACT after protamine) is put away until its due time changes, or for blood loss
    /// until another dose is logged (the 1,500 mL then counts from it).
    mutating func stop(_ rem: CaseReminder) {
        switch rem.kind {
        case .antibiotic:
            if let i = antibiotics.firstIndex(where: { $0.drug == rem.ref }) { antibiotics[i].everyMinutes = 0 }
        case .abg: checks["abg"] = nil
        case .glucose: checks["glucose"] = nil
        case .lab: if let ref = rem.ref { checks[ref] = nil }
        case .act: heparin?.actOff = true
        case .longCase, .bloodLoss, .protamineACT:
            snoozes[rem.id] = ReminderSnooze(due: originalDue(rem), until: .distantFuture)
            return
        }
        snoozes[rem.id] = nil
    }

    /// Done from the running list, where it needs no value: a redose given, a lab sent. false: the reminder needs a
    /// value (an ACT, a glucose) and the view opens its section instead.
    @discardableResult
    mutating func markDone(_ rem: CaseReminder, now: Date, ebl: Double?) -> Bool {
        switch rem.kind {
        case .antibiotic, .longCase, .bloodLoss:
            guard let i = antibiotics.firstIndex(where: { $0.drug == rem.ref }) else { return false }
            antibiotics[i].doses.append(TimedEntry(time: now, ebl: ebl ?? 0))
            // A new dose: every reminder of this drug runs from it now.
            clearAntibioticSnoozes(antibiotics[i].drug)
        case .abg: checks["abg"]?.done.append(TimedEntry(time: now))
        case .lab:
            guard let ref = rem.ref else { return false }
            checks[ref]?.done.append(TimedEntry(time: now))
        case .glucose, .act, .protamineACT:
            return false
        }
        snoozes[rem.id] = nil
        return true
    }
}

// MARK: - Every case's reminders, for notifications and the lock screen

struct CaseTimerItem: Hashable, Identifiable {
    var caseID: UUID
    /// "OR 12" or "Case 2": hospital data, never a patient detail.
    var caseLabel: String
    var reminder: CaseReminder
    var id: String { caseID.uuidString + "." + reminder.id }
}

enum CaseTimerSchedule {
    /// Every case's reminders, soonest first.
    static func items(_ cases: [(id: UUID, label: String, record: PatientRecord)], data: CaseTimerData) -> [CaseTimerItem] {
        cases.flatMap { c in
            CaseTimerEngine.reminders(c.record.timers, record: c.record, data: data)
                .map { CaseTimerItem(caseID: c.id, caseLabel: c.label, reminder: $0) }
        }
        .sorted { ($0.reminder.due ?? .distantPast) < ($1.reminder.due ?? .distantPast) }
    }
}
