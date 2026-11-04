import Foundation

// MARK: - Intraoperative case timers
//
// What was given and measured, stamped with its time, kept in the case's record (PatientRecord.timers), so Undo, case
// switching and the archive treat it like any other entry. Everything shown — the next redose, the ACT due, the
// protamine suggestion and its limits, the lab checks — is read back from that log and the numbers in reference.json
// "caseTimers" (CaseTimerData), so deleting a mistaken entry corrects everything that depends on it. Nothing here
// orders a dose: the reminders and suggestions are checks against the cited sources.

struct CaseTimers: Codable, Equatable {
    var antibiotic: AntibioticCourse?
    var heparin: HeparinCourse?
    /// By LabCheckDef id ("abg", "glucose").
    var checks: [String: LabCheckCourse] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        antibiotic = try? c.decodeIfPresent(AntibioticCourse.self, forKey: .antibiotic)
        heparin = try? c.decodeIfPresent(HeparinCourse.self, forKey: .heparin)
        checks = (try? c.decodeIfPresent([String: LabCheckCourse].self, forKey: .checks)) ?? [:]
    }

    var isEmpty: Bool { antibiotic == nil && heparin == nil && checks.isEmpty }
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

    init(time: Date, value: Double? = nil, ebl: Double? = nil, baseline: Bool? = nil) {
        self.time = time; self.value = value; self.ebl = ebl; self.baseline = baseline
    }
}

struct AntibioticCourse: Codable, Equatable {
    var drug: String
    var doses: [TimedEntry] = []
    var last: TimedEntry? { doses.max { $0.time < $1.time } }
}

struct HeparinCourse: Codable, Equatable {
    var purpose: String
    /// The ACT goal in force (s): the purpose's preset, the device alternative, or one the user set; nil for none.
    var goal: Double?
    /// The goal was set by the user where none is preset (shown with the purpose's "practice only" label).
    var userGoal = false
    /// Maximally activated or microcuvette ACT (bypass: the >400 s goal).
    var deviceAlt = false
    /// Minutes between ACT checks.
    var actEvery: Double = 30
    var doses: [TimedEntry] = []
    var acts: [TimedEntry] = []
    var protamine: [TimedEntry] = []
    var bypassOn: Date?
    var bypassOff: Date?

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
    }

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
}

struct LabCheckCourse: Codable, Equatable {
    var every: Double
    var started: Date
    var done: [TimedEntry] = []
    var last: TimedEntry? { done.max { $0.time < $1.time } }
}

// MARK: - Reminders

struct CaseReminder: Identifiable, Hashable {
    enum Kind: String, Hashable { case antibiotic, longCase, bloodLoss, act, protamineACT, abg, glucose }
    enum State: Hashable { case waiting, due, overdue }

    var kind: Kind
    var title: String
    var detail: String
    /// When it falls due; nil: due now (the blood-loss rule).
    var due: Date?
    var id: String { kind.rawValue }

    /// Overdue five minutes after it falls due.
    func state(at now: Date) -> State {
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

enum CaseTimerEngine {

    // MARK: Reminders

    /// Everything that is timed or due for this case, soonest first.
    static func reminders(_ t: CaseTimers, record r: PatientRecord, data d: CaseTimerData) -> [CaseReminder] {
        var out: [CaseReminder] = []
        let purpose = t.heparin.flatMap { d.purpose($0.purpose) }
        let onBypass = t.heparin?.onBypass ?? false

        if let a = t.antibiotic, let def = d.antibiotic(a.drug), let last = a.last {
            let skipOnBypass = def.id == "gentamicin" && (onBypass || purpose?.isBypass == true)
            if let h = def.redoseHours, !skipOnBypass {
                out.append(CaseReminder(kind: .antibiotic, title: "\(def.name) redose",
                                        detail: "\(antibioticDose(def, record: r).text) · every \(fmt(h)) h from the last dose",
                                        due: last.time.addingTimeInterval(h * 3600)))
            }
            if def.redoseHours == nil, !skipOnBypass, let h = d.antibioticRules.longCaseHours, h > 0 {
                out.append(CaseReminder(kind: .longCase, title: "\(def.name): long case",
                                        detail: d.antibioticRules.longCase ?? d.antibioticRules.noRedose,
                                        due: last.time.addingTimeInterval(h * 3600)))
            }
            if !skipOnBypass, let ebl = r.fluids["ebl"], ebl - (last.ebl ?? 0) >= d.antibioticRules.bloodLossML {
                out.append(CaseReminder(kind: .bloodLoss, title: "\(def.name) redose: blood loss",
                                        detail: d.antibioticRules.bloodLoss, due: nil))
            }
        }

        if let h = t.heparin, !h.doses.isEmpty {
            let p = d.protamine
            if let prot = h.lastProtamine {
                let end = protamineEnd(prot, rules: p)
                if (h.lastACT?.time ?? .distantPast) < end {
                    let base = h.baselineACT?.value.map { "baseline \(Int($0)) s" } ?? "baseline not logged"
                    out.append(CaseReminder(kind: .protamineACT, title: "ACT after protamine",
                                            detail: "Compare with the \(base)",
                                            due: end.addingTimeInterval(p.postActMinutes * 60)))
                }
            } else if let bolus = h.lastDose {
                let goal = h.goal.map { "Goal >\(Int($0)) s" } ?? "No preset goal"
                let due: Date
                if let act = h.lastACT, act.time >= bolus.time {
                    due = act.time.addingTimeInterval(h.actEvery * 60)
                } else {
                    due = bolus.time.addingTimeInterval(d.heparinRules.firstActMinutes * 60)
                }
                out.append(CaseReminder(kind: .act, title: "ACT check", detail: goal, due: due))
            }
        }

        for def in d.checks {
            guard let c = t.checks[def.id] else { continue }
            let from = c.last?.time ?? c.started
            let kind: CaseReminder.Kind = def.id == "glucose" ? .glucose : .abg
            out.append(CaseReminder(kind: kind, title: "\(def.name) check", detail: "Every \(fmt(c.every)) min",
                                    due: from.addingTimeInterval(c.every * 60)))
        }

        return out.sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
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

    /// The suggested first bolus for the purpose and weight, rounded to 1,000 U (500 U under 10,000).
    static func suggestedBolus(_ p: HeparinPurpose, weightKg w: Double?) -> Double? {
        guard let w, w > 0, let perKg = p.doseDefault else { return nil }
        let u = perKg * w
        let step: Double = u >= 10000 ? 1000 : 500
        return (u / step).rounded() * step
    }

    /// "300–400 U/kg = 24,000–32,000 U".
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
            out.append(DoseIssue(level: .confirm, text: "\(perKgText) is a bypass-size dose, and the purpose is \(p.name.lowercased())."))
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

    /// Checks on an ACT goal the user sets.
    static func goalIssues(_ goal: Double?, purpose p: HeparinPurpose, rules: HeparinRules) -> [DoseIssue] {
        guard let g = goal else { return [] }
        if p.isBypass && g < rules.bypassMinGoal {
            return [DoseIssue(level: .confirm, text: "A bypass ACT goal under \(Int(rules.bypassMinGoal)) s.")]
        }
        return []
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

    static func status(_ h: HeparinCourse, record r: PatientRecord) -> HeparinStatus {
        let act = h.lastACT
        let afterBolus = act.map { a in h.lastDose.map { a.time >= $0.time } ?? true } ?? false
        let met: Bool? = (h.goal != nil && afterBolus) ? (act?.value ?? 0) > h.goal! : nil
        let perKg = h.initialUnits.flatMap { u in r.weightKg.map { u / $0 } }
        return HeparinStatus(initialUnits: h.initialUnits, totalUnits: h.totalUnits, initialPerKg: perKg,
                             lastACT: act?.value, lastACTTime: act?.time, goal: h.goal, goalMet: met)
    }

    // MARK: Protamine

    struct ProtamineSuggestion: Hashable {
        /// The heparin the ratios are read against: the initial bolus on bypass (review doc), the total given otherwise.
        var basisUnits: Double
        var basisIsInitial: Bool
        var totalUnits: Double
        /// The suggested range (mg), bypass only.
        var lowMg: Double?
        var highMg: Double?
        /// The label's upper bound without bypass: 1 mg per 100 U given.
        var labelMaxMg: Double?
        var givenMg: Double
    }

    static func protamineSuggestion(_ h: HeparinCourse, purpose p: HeparinPurpose, rules pr: ProtamineRules) -> ProtamineSuggestion? {
        guard let initial = h.initialUnits, initial > 0 else { return nil }
        let total = h.totalUnits
        if p.isBypass {
            return ProtamineSuggestion(basisUnits: initial, basisIsInitial: true, totalUnits: total,
                                       lowMg: round10(initial / 100 * pr.ratioLow), highMg: round10(initial / 100 * pr.ratioHigh),
                                       labelMaxMg: nil, givenMg: h.protamineMg)
        }
        return ProtamineSuggestion(basisUnits: total, basisIsInitial: false, totalUnits: total, lowMg: nil, highMg: nil,
                                   labelMaxMg: round10(total / 100), givenMg: h.protamineMg)
    }

    /// mg of protamine per 100 U of the basis, counting what was already given.
    static func protamineRatio(addingMg mg: Double, _ s: ProtamineSuggestion) -> Double {
        guard s.basisUnits > 0 else { return 0 }
        return (s.givenMg + mg) / (s.basisUnits / 100)
    }

    /// Checks on a protamine dose before it is logged: the STS 2018 ceiling (flag above 1.3, block above 2.6 mg per
    /// 100 U), the EACTS <1:1 target, bypass still running, and the label's rate.
    static func protamineIssues(mg: Double, course h: HeparinCourse, purpose p: HeparinPurpose, rules pr: ProtamineRules) -> [DoseIssue] {
        guard mg > 0 else { return [DoseIssue(level: .block, text: "Enter the dose in mg.")] }
        guard let s = protamineSuggestion(h, purpose: p, rules: pr) else {
            return [DoseIssue(level: .block, text: "Log the heparin first.")]
        }
        var out: [DoseIssue] = []
        let ratio = protamineRatio(addingMg: mg, s)
        let basis = s.basisIsInitial ? "of the initial bolus" : "of heparin given"
        let ratioText = String(format: "%.1f", ratio)
        if ratio > pr.blockAbove {
            out.append(DoseIssue(level: .block, text: "\(ratioText) mg per 100 U \(basis): over the STS 2018 ceiling of \(fmt(pr.blockAbove))."))
        } else if ratio > pr.flagAbove {
            out.append(DoseIssue(level: .confirm, text: "\(ratioText) mg per 100 U \(basis): over \(fmt(pr.flagAbove))."))
        } else if p.isBypass && ratio > pr.ratioHigh {
            out.append(DoseIssue(level: .soft, text: "\(ratioText) mg per 100 U: above 1:1. \(pr.ratioNote)"))
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
