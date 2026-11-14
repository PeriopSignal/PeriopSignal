import Foundation

// MARK: - 1.12 (Ben's note 17): a box collapses once it is filled in
//
// The boxes edited in place on the Preoperative and Intraoperative tabs (Demographics, Allergies, Problems by System,
// Current Medications & Infusions, Flagged medications, Cardiopulmonary evaluation, ASA & functional capacity; Airway
// course, Infusions, Fluids & Blood) fold to a title row and a short summary once they hold a value, to shorten the
// scroll. The rules, as settled with Ben:
//   - a box that holds a value collapses when the user taps into another box, expands another box, or taps its own Done;
//     never while one of its fields has the keyboard, and never because of scrolling alone;
//   - an empty box never collapses; when a saved patient opens, boxes that hold values start collapsed;
//   - collapsed, a box shows the lines the Preprocedure Summary / handoff use for that part (at most two lines for an
//     ordinary line; every alert line and abnormal value in full).
// This file is the logic (which box holds what, and the state machine); the views are in PatientBoxCards.swift.

/// The ten boxes that collapse.
enum PatientBox: String, CaseIterable, Hashable {
    case demographics, allergies, problems, medications, flagged, cardio, asa
    case airway, infusions, fluids

    /// The box sits directly under a section title that says the same words ("Current Medications & Infusions", "Airway
    /// Course", "Fluids & Blood"), so its folded card does not repeat them.
    var repeatsSectionTitle: Bool { self == .medications || self == .airway || self == .fluids }

    var title: String {
        switch self {
        case .demographics: return "Demographics"
        case .allergies: return "Allergies"
        case .problems: return "Problems by System"
        case .medications: return "Current Medications & Infusions"
        case .flagged: return "Flagged medications"
        case .cardio: return "Cardiopulmonary evaluation"
        case .asa: return "ASA & functional capacity"
        case .airway: return "Airway course"
        case .infusions: return "Infusions"
        case .fluids: return "Fluids & Blood"
        }
    }

    /// The box a jump anchor of the Preoperative tab scrolls to (PatientJumpID(anchor:)), if it is one of these.
    static func forAnchor(_ anchor: String) -> PatientBox? {
        switch anchor {
        case "demographics": return .demographics
        case "allergies": return .allergies
        case "problems": return .problems
        case "homemeds", "infusions": return .medications
        case "flagged": return .flagged
        case "cardio", "preopworkup": return .cardio
        case "asa": return .asa
        default: return nil
        }
    }

    /// The box a jump id's key names ("preop-box:allergies", PatientJumpID.key), if it is one of these.
    static func forJump(_ key: String) -> PatientBox? {
        let prefix = "preop-box:"
        return key.hasPrefix(prefix) ? forAnchor(String(key.dropFirst(prefix.count))) : nil
    }

    /// How many lines a collapsed summary line may take: two for an ordinary line; none cut for an alert, or for a line
    /// that carries a value marked abnormal (a flagged value is never behind an ellipsis).
    static func lineLimit(_ l: PatientSummary.Line) -> Int? { l.alert || !l.marks.isEmpty ? nil : 2 }

    /// Screenshot runs pass -ps.patient <seed>; collapsing is off in them unless -ps.patient.collapse 1, so the shots that
    /// predate it keep showing the expanded boxes. Everywhere else (the app, the tests) it is on.
    static func collapsingEnabled(patientSeed: String, collapseFlag: Bool) -> Bool { patientSeed.isEmpty || collapseFlag }
}

/// What a box holds: the lines for its collapsed form.
struct PatientBoxSummary: Equatable {
    /// What the user has entered in the box. The box collapses only when there is at least one.
    var entered: [PatientSummary.Line] = []
    /// What the app works out from other boxes' entries and the summaries still say (the TEE screen's contraindications):
    /// shown when the box is collapsed so it is never hidden, but never what makes a box count as filled in.
    var derivedAlerts: [PatientSummary.Line] = []

    var holdsValue: Bool { !entered.isEmpty }
    var lines: [PatientSummary.Line] { entered + derivedAlerts }
}

extension PatientBox {
    /// The box's entries as the summaries word them (PatientSummary, PatientBriefs), for its collapsed form and for the
    /// question "does it hold a value".
    func summary(_ r: PatientRecord, now: Date = Date()) -> PatientBoxSummary {
        switch self {
        case .demographics: return PatientBoxSummary(entered: Self.demographicsLines(r))
        case .allergies: return PatientBoxSummary(entered: PatientAllergyText.line(r).map { [$0] } ?? [])
        case .problems: return PatientBoxSummary(entered: Self.problemLines(r))
        case .medications: return PatientBoxSummary(entered: Self.medicationLines(r))
        case .flagged: return PatientBoxSummary(entered: Self.flaggedLines(r))
        case .cardio: return Self.cardioSummary(r, now: now)
        case .asa: return PatientBoxSummary(entered: Self.asaLines(r))
        case .airway: return PatientBoxSummary(entered: Self.airwayLines(r))
        case .infusions: return PatientBoxSummary(entered: Self.infusionLines(r))
        case .fluids: return PatientBoxSummary(entered: PatientSummary.intraopPartLines(r, "fluids"))
        }
    }

    // MARK: Preoperative boxes

    /// The history lines that belong to other boxes or other cards.
    private static let notProblems: Set<String> = ["Allergies", "Past surgical history", "Medications", "Medication alerts", "Current infusions",
                                                   "Anesthetic complications", "Last intake", "Labs", "Liver"]

    /// The one-liner, body size and vitals (the Demographics card's lines), the code status, and the last intake.
    private static func demographicsLines(_ r: PatientRecord) -> [PatientSummary.Line] {
        var out = PatientSummary.demographicsLines(r)
        if let c = PatientCodeStatus.line(r) { out.append(c) }
        if let i = PatientSummary.historyLines(r).first(where: { $0.label == "Last intake" }) { out.append(i) }
        return out
    }

    /// The history's system lines, its warnings and the other conditions: what the Problems box holds.
    private static func problemLines(_ r: PatientRecord) -> [PatientSummary.Line] {
        PatientSummary.historyLines(r).filter { !notProblems.contains($0.label ?? "") }
    }

    /// The medication list, its alerts and the drips running before the case. With no list typed the summaries let the flags
    /// stand for it; they are entered in the Flagged medications box, so they do not fill this one.
    private static func medicationLines(_ r: PatientRecord) -> [PatientSummary.Line] {
        let listed = r.homeMeds.contains { !$0.text.isEmpty } || !r.medications.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return PatientSummary.historyLines(r).filter { l in
            switch l.label ?? "" {
            case "Medications": return listed
            case "Medication alerts", "Current infusions": return true
            default: return false
            }
        }
    }

    /// The active flags in the catalog's order, as one line; the ones that need an action before or after surgery are marked.
    private static func flaggedLines(_ r: PatientRecord) -> [PatientSummary.Line] {
        let active = PatientCatalog.medFlags.filter { r.medFlags.contains($0.id) }
        guard !active.isEmpty else { return [] }
        let watched = active.filter { PatientSummary.watchFlags.contains($0.id) }.map(\.label)
        return [PatientSummary.Line(nil, active.map(\.label).joined(separator: ", "), marks: watched)]
    }

    /// What the Cardiopulmonary box shows: the symptoms and acute conditions, previous intrathoracic surgery, and the
    /// workup (ECG, echo, stress test, catheterizations, carotid and radial ultrasound, PFTs, the cautions, the TEE screen)
    /// as the Preprocedure Summary's cardiac-workup block says it; a line that block carries and the assessment does not
    /// know (the chest X-ray) is carried too. The guideline advice is worked out, not entered, and the summaries do not carry
    /// it, so the folded box does not either (it is in the box when it is open). The stepwise result is worked out too, but
    /// when it is a warning its red title line stays in view on the folded box (1.12, Ben, Nov 13: a folded box always shows
    /// its red alerts); like the TEE screen's line it never makes the box count as filled in.
    private static func cardioSummary(_ r: PatientRecord, now: Date = Date()) -> PatientBoxSummary {
        // The box is inside the app, so its lines carry a full date (`.app`); the summary's block is made with `.summary(now:)`
        // (a day only within 90 days), so the same study reads differently there. To drop what the box already says, the
        // lines are compared as the SUMMARY would word them (the same lines, made again in the summary's date style).
        let out = cardioEntered(r, dates: .app)
        // The TEE screen is worked out from the history and the studies, so it never fills the box, but it stays in view.
        let tee = PatientTEE.line(r)
        var known = Set(out.map(Self.joined))
        known.formUnion(cardioEntered(r, dates: .summary(now: now)).map(Self.joined))
        if let tee { known.insert(Self.joined(tee)) }
        var all = out
        if let block = PatientBriefs.slots(.preop, r, now: now).first(where: { $0.key == "workup" }) {
            for text in block.lines where !known.contains(text) && !text.hasPrefix("Mechanical support") {
                all.append(PatientSummary.Line(nil, text, marks: block.marks.filter { !$0.isEmpty && text.contains($0) }))
            }
        }
        var derived = tee.map { [$0] } ?? []
        if let result = PatientFunctional.foldedResultLine(r) { derived.append(result) }
        return PatientBoxSummary(entered: all, derivedAlerts: derived)
    }

    /// The entered lines of the Cardiopulmonary box (assessment lines plus the stress test), dates worded in `dates`.
    private static func cardioEntered(_ r: PatientRecord, dates: PatientDateStyle) -> [PatientSummary.Line] {
        let assess = PatientSummary.assessmentLines(r, dates: dates)
        let entered: Set<String> = ["Cardiac symptoms", "Acute cardiac conditions", "Previous intrathoracic surgery", "ECG", "Echo", "Coronaries",
                                    "Right heart cath", "Carotid ultrasound", "Radial artery ultrasound", "Pulmonary function tests", "Caution"]
        var out = assess.filter { entered.contains($0.label ?? "") }
        if let s = PatientPreop.stressLine(r, dates: dates) {
            let at = out.firstIndex { ["Coronaries", "Right heart cath", "Carotid ultrasound", "Radial artery ultrasound", "Pulmonary function tests", "Caution"].contains($0.label ?? "") } ?? out.count
            out.insert(s, at: at)
        }
        return out
    }

    private static func joined(_ l: PatientSummary.Line) -> String { (l.label.map { $0 + ": " } ?? "") + l.text }

    /// The ASA class chosen (a suggestion is not a value), functional capacity and frailty.
    private static func asaLines(_ r: PatientRecord) -> [PatientSummary.Line] {
        let labels: Set<String> = ["Functional capacity", "Frailty"]
        return PatientSummary.assessmentLines(r).filter { l in
            if l.label == "ASA physical status" { return PatientRules.asaText(r) != nil }
            return labels.contains(l.label ?? "")
        }
    }

    // MARK: Intraoperative boxes

    /// The airway course as the handoff words it (a difficult one in red); a value only once something of the course in the
    /// room, or how the airway is left, is recorded (an airway on arrival and the examination's notes are not the box's).
    private static func airwayLines(_ r: PatientRecord) -> [PatientSummary.Line] {
        let recorded = !PatientSummary.airwayCourseSentences(r).isEmpty || r.airwayAtEnd != nil
        guard recorded, let c = PatientBriefs.airwayCourse(r) else { return [] }
        return [PatientSummary.Line(nil, c.text, alert: c.alert, marks: c.alert ? ["DIFFICULT"] : [])]
    }

    /// The drips in the room's list (the ones running before the case included, as the box lists them).
    private static func infusionLines(_ r: PatientRecord) -> [PatientSummary.Line] {
        let drips = IntraopInfusionList.rows(r).map(\.text).filter { !$0.isEmpty }
        return drips.isEmpty ? [] : [PatientSummary.Line("Infusions", drips.joined(separator: "; "))]
    }
}

// MARK: - The state

/// Which boxes are folded, and the rules that fold them. A value: the views read it, the tests drive it.
struct PatientBoxCollapse: Equatable {
    /// The boxes folded. A box counts as folded only while it holds a value (`isCollapsed`), so an emptied box is open.
    private(set) var collapsed: Set<PatientBox> = []
    /// Boxes asked to fold while a keyboard was up: they fold when it goes, or once its field is known not to be theirs.
    private(set) var pending: Set<PatientBox> = []
    private(set) var keyboardUp = false

    /// A saved patient opens: the boxes that hold values start folded. An empty patient starts with everything open.
    mutating func start(_ r: PatientRecord) {
        pending = []
        collapsed = Set(PatientBox.allCases.filter { $0.summary(r).holdsValue })
    }

    func isCollapsed(_ box: PatientBox, _ r: PatientRecord) -> Bool {
        collapsed.contains(box) && box.summary(r).holdsValue
    }

    /// The user taps into `box` or expands it: it is open, and every other box that holds a value folds (those that
    /// are open already; one with a keyboard up waits for it, `keyboardChanged`, `keyboardOwner`).
    mutating func touched(_ box: PatientBox, _ r: PatientRecord) {
        collapsed.remove(box)
        pending.remove(box)
        for other in PatientBox.allCases where other != box && !collapsed.contains(other) && other.summary(r).holdsValue {
            if keyboardUp { pending.insert(other) } else { collapsed.insert(other) }
        }
    }

    /// The box's own Done: it folds (the keyboard goes with it) if it holds a value.
    mutating func done(_ box: PatientBox, _ r: PatientRecord) {
        pending.remove(box)
        if box.summary(r).holdsValue { collapsed.insert(box) }
    }

    /// The keyboard came up or went. When it goes, what waited for it folds.
    mutating func keyboardChanged(up: Bool) {
        keyboardUp = up
        if !up { flush() }
    }

    /// The box whose field has the keyboard (nil: a field outside the boxes, the quick-add bar's for one): the others that
    /// waited fold now; that one waits on.
    mutating func keyboardOwner(_ owner: PatientBox?) {
        for p in pending where p != owner { collapsed.insert(p) }
        pending = owner.map { pending.intersection([$0]) } ?? []
    }

    private mutating func flush() {
        collapsed.formUnion(pending)
        pending = []
    }
}
