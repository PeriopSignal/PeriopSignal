import Foundation

// MARK: - The reorganized Preprocedure tab (1.9, Ben's Wanted Changes): the logic behind it that is not view code.
//
// Sections, in order: Procedure; Demographics & History; Examination & Workup; Current Medications; Risk Scores &
// Checks; Preprocedure Summary. Views are in PatientPreopViews.swift.

/// One test or study the "+ Add Preprocedure Cardiac Workup" chip offers, with its one-line summary once it holds data.
struct PreopWorkupItem: Hashable, Identifiable {
    var id: String
    /// The chip's words: "ECG", "Echo", "Left heart cath".
    var title: String
    /// SF Symbol.
    var icon: String
    /// Where it opens, in PatientView.open's keys: "workup:ecg", "devices:support".
    var key: String
    /// The one-line summary when it holds data, nil while empty (the chip then reads "+ ECG").
    var summary: String?
    /// Needs attention (a contraindication on the TEE screen, mechanical support, a carotid or vertebral caution).
    var alert = false
    /// A warning shown in red under the summary: the carotid and vertebral cautions (subclavian steal, femoral arterial
    /// access), as the Assessment card listed them before 1.9.
    var caution: String?
    var filled: Bool { summary != nil }
}

enum PatientPreop {

    // MARK: Intrathoracic procedure

    /// Cardiopulmonary Evaluation's "Intrathoracic procedure" Yes / No (Ben, Nov 3). Yes also sets the ARISCAT incision to
    /// Intrathoracic and the RCRI's high-risk surgery (intrathoracic is one of its high-risk surgeries) when they are
    /// still unset; nothing already chosen is overwritten, and No sets nothing else. A false high-risk switch is "unset"
    /// (the record cannot tell a deliberate No from never asked). A cardiac operation keeps the answer too; the RCRI is
    /// hidden for it by PatientRules.cardiacSurgery, not by this answer (a noncardiac thoracic case, such as a lobectomy,
    /// keeps the RCRI with intrathoracic surgery as its high-risk item).
    static func setIntrathoracic(_ answer: Bool?, _ r: inout PatientRecord) {
        r.intrathoracicProcedure = answer
        guard answer == true else { return }
        if r.incision == nil { r.incision = "Intrathoracic" }
        if !r.highRiskSurgery { r.highRiskSurgery = true }
    }

    /// What Intrathoracic procedure: Yes has set, for the quiet line under it: "Incision: Intrathoracic · High-risk surgery".
    static func intrathoracicSetLine(_ r: PatientRecord) -> String? {
        guard r.intrathoracicProcedure == true else { return nil }
        var parts: [String] = []
        if let i = r.incision { parts.append("Incision: " + i) }
        if r.highRiskSurgery, !PatientRules.cardiacSurgery(r) { parts.append("High-risk surgery") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The RCRI's rule under Intrathoracic procedure: Yes, for a planned cardiac operation. Only under 18: for an adult the
    /// same card's one quiet cardiac-surgery line (PatientFunctional.cardiacSurgeryNote, in PatientCardiacEvaluationContent)
    /// already says the RCRI is not shown, and two notes saying it were one too many (review 1.10).
    static func intrathoracicRcriNote(_ r: PatientRecord) -> String? {
        guard r.intrathoracicProcedure == true, PatientRules.cardiacSurgery(r), !r.isAdult else { return nil }
        return PatientRules.rcriHiddenNote
    }

    // MARK: Cardiac workup

    /// The nine tests behind "+ Add Preprocedure Cardiac Workup", in Ben's order (ECG, echo, left and right heart cath,
    /// carotid and radial artery ultrasound, pulmonary function tests, TEE screen, mechanical support), each with its
    /// one-line summary when it holds data. The summaries are the ones the assessment page and the handoff use.
    static func workup(_ r: PatientRecord) -> [PreopWorkupItem] {
        let c = r.capitalized
        let tee = PatientTEE.evaluate(r)
        let support = PatientSummary.supportLines(r).map(\.text)
        // The radial-harvest cautions are told with the lines; the carotid and vertebral ones belong to this study.
        let cautions = PatientStudies.cautions(r).filter { !$0.id.hasPrefix("harvest") }.map(\.text)
        return [
            PreopWorkupItem(id: "ecg", title: "ECG", icon: "waveform.path.ecg", key: "workup:ecg", summary: PatientSummary.ecgText(r)),
            PreopWorkupItem(id: "echo", title: "Echo", icon: "heart.text.square", key: "workup:echo", summary: r.echoFindings.isEmpty ? nil : c.echoFindings.summary),
            // 1.11 (Ben's note 4): the stress test, noninvasive, before the catheterizations.
            PreopWorkupItem(id: "stress", title: "Stress test", icon: "figure.run", key: "workup:stress", summary: r.stressTest.summary,
                            alert: r.stressTest.result == .positive),
            PreopWorkupItem(id: "lhc", title: "Left heart cath", icon: "heart", key: "workup:lhc", summary: r.lhc.isEmpty ? nil : c.lhc.summary),
            PreopWorkupItem(id: "rhc", title: "Right heart cath", icon: "heart.circle", key: "workup:rhc", summary: PatientSummary.rhcText(r)),
            PreopWorkupItem(id: "carotid", title: "Carotid US", icon: "waveform.path", key: "workup:carotid", summary: r.carotid.isEmpty ? nil : c.carotid.summary,
                            alert: !cautions.isEmpty, caution: cautions.isEmpty ? nil : cautions.joined(separator: " ")),
            PreopWorkupItem(id: "radial", title: "Radial artery US", icon: "hand.raised", key: "workup:radial", summary: r.radial.isEmpty ? nil : c.radial.summary),
            PreopWorkupItem(id: "pft", title: "Pulmonary function tests", icon: "lungs", key: "workup:pft", summary: r.pft.isEmpty ? nil : c.pft.summary(copd: r.has("copd"))),
            PreopWorkupItem(id: "tee", title: "TEE screen", icon: tee.level == .none ? "checkmark.shield" : "exclamationmark.triangle", key: "workup:tee",
                            summary: tee.screened ? PatientTEE.status(r) : nil, alert: tee.level != .none),
            PreopWorkupItem(id: "support", title: "Mechanical support", icon: "heart.circle", key: "devices:support",
                            summary: support.isEmpty ? nil : support.joined(separator: "; "), alert: !support.isEmpty),
        ]
    }

    /// The operations "Previous cardiac surgery" lists: the cardiac ones among those marked cardiac or thoracic (the CV
    /// page's own entry, or one the catalog or its words make cardiac), so a lobectomy or a VATS wedge is not called
    /// cardiac surgery.
    static func previousCardiacSurgery(_ r: PatientRecord) -> [PatientSurgery] {
        r.capitalized.allIntrathoracic.filter { $0.id == r.hx.cardiacSurgeryID || PastSurgeryNote.isCardiac($0) }
    }

    /// The small link under the code status chips to its page (the plan for the procedure and the POLST), for every
    /// status: the plan when the status limits resuscitation (red while not discussed), else whether a POLST is on file.
    static func codeStatusLink(_ r: PatientRecord) -> (text: String, alert: Bool) {
        if r.codeStatus?.limits == true {
            if let plan = r.codeStatusPlan { return ("Plan: " + plan.label + (r.polst ? " · POLST on file" : ""), false) }
            return ("Perioperative plan not yet discussed", true)
        }
        return (r.polst ? "POLST on file" : "Plan details & POLST", false)
    }

    /// Once any is filled, the workup shows open.
    static func workupHasData(_ r: PatientRecord) -> Bool { workup(r).contains { $0.filled } }

    /// 1.11 (Ben's note 4): the link that reveals the workup chips, with the three most asked for named.
    static let workupLinkTitle = "Add Preprocedure Cardiac Workup (ECG, Echo, LHC)"

    // MARK: 1.11 — Intrathoracic procedure from the planned procedure (Ben's note 3)

    /// What the planned procedure says about "Intrathoracic procedure": true when any recognized procedure enters the
    /// chest (the catalog's ARISCAT incision is Intrathoracic: cardiac, thoracic, esophageal), false when every planned
    /// item is a catalog procedure and none does (a transcatheter heart procedure is No too: the chest is not opened),
    /// nil with no procedure or with one the catalog does not know (the No / Yes pills then stay).
    static func intrathoracicFromProcedure(_ r: PatientRecord) -> Bool? {
        let items = r.plannedItems.filter { $0.catalogID != nil || !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !items.isEmpty else { return nil }
        let known = items.compactMap(\.catalog)
        if known.contains(where: { $0.incision == "Intrathoracic" }) { return true }
        return known.count == items.count ? false : nil
    }

    /// Keeps the derived answer in step with the procedure (PatientCrossFill, on every change). The derived answer is
    /// tracked in `fills.intrathoracic`; a user's own answer (one that differs from what was derived) is never
    /// overwritten and stays when the procedure changes; a derived answer follows the procedure and is cleared when the
    /// procedure goes; an unanswered question takes the procedure's answer. Clearing an answer with a second tap puts the
    /// procedure's answer back: the row then says where it came from.
    static func syncIntrathoracic(before: PatientRecord, after r: inout PatientRecord) {
        let derived = intrathoracicFromProcedure(r)
        if let d = r.fills.intrathoracic {
            if let a = r.intrathoracicProcedure, a != d {
                r.fills.intrathoracic = nil
                return
            }
            if derived != d {
                r.intrathoracicProcedure = derived
                r.fills.intrathoracic = derived
                if derived == true { cascadeIntrathoracic(&r) }
            } else if r.intrathoracicProcedure == nil {
                r.intrathoracicProcedure = d
            }
        } else if r.intrathoracicProcedure == nil, let derived {
            r.intrathoracicProcedure = derived
            r.fills.intrathoracic = derived
            if derived { cascadeIntrathoracic(&r) }
        }
    }

    /// The 1.9 cascade of a Yes: the ARISCAT incision and the RCRI's high-risk surgery, only when unset.
    private static func cascadeIntrathoracic(_ r: inout PatientRecord) {
        if r.incision == nil { r.incision = "Intrathoracic" }
        if !r.highRiskSurgery { r.highRiskSurgery = true }
    }

    /// The answer as derived from the procedure (nil when the user answered, or nothing is derived).
    static func intrathoracicDerived(_ r: PatientRecord) -> Bool? {
        guard let d = r.fills.intrathoracic, r.intrathoracicProcedure == d else { return nil }
        return d
    }

    /// The quiet line that replaces the pills while the answer is the procedure's: "Intrathoracic procedure: Yes (from
    /// the procedure)"; the control beside it reads "Change".
    static func intrathoracicDerivedLine(_ r: PatientRecord) -> String? {
        intrathoracicDerived(r).map { "Intrathoracic procedure: " + ($0 ? "Yes" : "No") + " (from the procedure)" }
    }

    // MARK: 1.11 — Code status as a quiet link (Ben's note 2; Q5)

    /// The collapsed code-status row once a status is chosen: "Code status: DNR · DNI · POLST on file". Nil while none is
    /// (the box shows "+ Add code status"); a POLST on file with no status reads as the summary does, in red, so it is
    /// never hidden behind the link.
    static func codeStatusRow(_ r: PatientRecord) -> (text: String, alert: Bool)? {
        guard let s = r.codeStatus else {
            return r.polst ? ("Code status: " + PatientCodeStatus.polstOnly, true) : nil
        }
        var words: String
        switch s {
        case .full: words = "Full"
        case .dnrDni: words = "DNR · DNI"
        default: words = s.label
        }
        let limits = r.codeStatusLimits.trimmingCharacters(in: .whitespacesAndNewlines)
        if s == .limited, !limits.isEmpty { words += ": " + limits }
        if r.polst { words += " · POLST on file" }
        return ("Code status: " + words, false)
    }

    /// Under the row, while the orders limit resuscitation, the perioperative plan chips (Maintained · Modified ·
    /// Suspended) are asked inline (Q5). This is the caption under them: red "Plan not yet discussed" while none is
    /// chosen, Maintained's instruction to the clinician when it is, nothing otherwise.
    static func codeStatusPlanCaption(_ r: PatientRecord) -> (text: String, alert: Bool)? {
        guard r.codeStatus?.limits == true else { return nil }
        guard let p = r.codeStatusPlan else { return ("Plan not yet discussed: review the orders with the patient or surrogate before the anesthetic.", true) }
        return p.inView.map { ($0, false) }
    }

    /// The plan chips are shown under the status row.
    static func asksCodeStatusPlan(_ r: PatientRecord) -> Bool { r.codeStatus?.limits == true }

    static let codeStatusLinkTitle = "Add code status"
    static let vitalsLinkTitle = "Add preoperative vitals"
    static let intakeLinkTitle = "Last intake"

    /// "Vitals: BP 148/86 · HR 72 · SpO₂ 95%" for the collapsed vitals link.
    static func vitalsRow(_ r: PatientRecord) -> String? { PatientSummary.vitalsLine(r).map { "Vitals: " + $0 } }

    /// "Last intake: Solids 00:00 · clears 05:00" (the day too when it is not today) for the collapsed intake link.
    static func intakeRow(_ r: PatientRecord, now: Date = Date()) -> String? {
        intakeText(r, now: now).map { "Last intake: " + $0 }
    }

    /// "Solids 00:00 · clears 05:00", as the 1.9 chip read it.
    static func intakeText(_ r: PatientRecord, now: Date = Date()) -> String? {
        func when(_ d: Date) -> String {
            Calendar.current.isDate(d, inSameDayAs: now) ? d.formatted(date: .omitted, time: .shortened) : PatientDates.day(d) + " " + d.formatted(date: .omitted, time: .shortened)
        }
        var parts: [String] = []
        if let d = r.lastSolids { parts.append("Solids " + when(d)) }
        if let d = r.lastClears { parts.append((parts.isEmpty ? "Clears " : "clears ") + when(d)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: 1.11 — Say it once (P1-10)

    /// The derived body-size line without the weight and height, which the fields above it already show: "BMI 30.3 ·
    /// BSA 2.14 m² · IBW 73 kg · LBW 67 kg". Nil without a BMI. The briefs keep PatientSummary.bodyLine.
    static func derivedBodyLine(_ r: PatientRecord) -> String? {
        guard let b = r.bmi else { return nil }
        var parts = ["BMI " + String(format: "%.1f", b)]
        if let s = r.bsa { parts.append("BSA " + String(format: "%.2f", s) + " m²") }
        if let i = r.ibw { parts.append("IBW " + NumText.short(i.rounded()) + " kg") }
        if let l = r.lbw { parts.append("LBW " + NumText.short(l.rounded()) + " kg") }
        return parts.joined(separator: " · ")
    }

    /// The ASA suggestion and its Use button show while there is one and it differs from the class chosen; once the
    /// chosen class is the suggestion the line goes (the class chips say it).
    static func showsAsaSuggestion(_ r: PatientRecord) -> Bool {
        guard let s = PatientRules.asaSuggestion(r) else { return false }
        return r.asaClass != s.level
    }

    // MARK: 1.11 — Cardiac symptoms and acute conditions in one row

    /// While both questions are unanswered with no chip, or both are No, they show as one row with a None preset: false
    /// is the row with None not applied, true the row with None applied (both No), nil means the two rows show as before
    /// (one answered, or a Yes).
    static func cardiacNone(_ r: PatientRecord) -> Bool? {
        guard r.cardiacSymptoms.isEmpty, r.activeCardiac.isEmpty else { return nil }
        let a = r.cardiacSymptomsAnswer, b = r.activeCardiacAnswer
        if a == nil && b == nil { return false }
        if a == false && b == false { return true }
        return nil
    }

    /// None: both answers No, their chips cleared, in one step; off again: both unanswered.
    static func setCardiacNone(_ on: Bool, _ r: inout PatientRecord) {
        if on {
            r.cardiacSymptomsAnswer = false
            r.activeCardiacAnswer = false
            r.cardiacSymptoms = []
            r.activeCardiac = []
        } else {
            r.cardiacSymptomsAnswer = nil
            r.activeCardiacAnswer = nil
        }
    }

    static let cardiacNoneTitle = "Cardiac symptoms or acute conditions"
    static let cardiacNoneCaption = "Sets Cardiac symptoms or signs: No and Acute cardiac conditions: No. Undo or a second tap clears both."

    // MARK: 1.11 — Stress test (Ben's note 4)

    /// The stress test's line in the briefs' Preprocedure cardiac workup block, after the label "Stress test": "Dobutamine,
    /// 03/2025: negative, no ischemia; inferior wall ischemia at 7 METs". A positive test is marked for attention.
    static func stressLine(_ r: PatientRecord) -> PatientSummary.Line? {
        let t = r.stressTest
        guard !t.isEmpty else { return nil }
        var head: [String] = []
        if let k = t.kind { head.append(k == .other ? "Other" : k.label) }
        if !t.date.isEmpty { head.append(t.date.text) }
        var tail: [String] = []
        if let res = t.result { tail.append(res.text) }
        let f = FreeText.cap(t.findings.trimmingCharacters(in: .whitespacesAndNewlines))
        if !f.isEmpty { tail.append(f) }
        let text: String
        if tail.isEmpty { text = head.joined(separator: ", ") }
        else if head.isEmpty { text = tail.joined(separator: "; ") }
        else { text = head.joined(separator: ", ") + ": " + tail.joined(separator: "; ") }
        let positive = t.result == .positive
        return PatientSummary.Line("Stress test", text, alert: positive, marks: positive ? [PatientStressTest.Result.positive.text] : [])
    }

    static let stressNote = "Type, result, date and one line of findings, as the report summarizes them. The result is what the report concluded (negative for ischemia, positive for ischemia, or equivocal or nondiagnostic); the app grades nothing from it."

    // MARK: Problems by system

    /// The systems that get a tile: the pediatric one first for a child; the Obstetric one for a woman or when the sex is
    /// not recorded, and for a man only if that page holds something (a saved record).
    static func tileSystems(_ r: PatientRecord) -> [PatientSystem] {
        PatientCatalog.systems(for: r).filter { s in
            guard s.id == "ob", r.sex == .male else { return true }
            return !tileWords(s, r).isEmpty
        }
    }

    /// What a system tile says: the page's summary words, then what was typed under Other [system] disorders and Other
    /// details, as the History list did; first letter capitalized. Empty when nothing is recorded.
    static func tileWords(_ s: PatientSystem, _ r: PatientRecord) -> String {
        let typed = [r.systemOther[s.id], r.systemNotes[s.id]].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let picked = (HistorySections.items(s, r) + typed).enumerated().map { $0.offset == 0 ? $0.element.prefix(1).uppercased() + $0.element.dropFirst() : $0.element }
        return picked.joined(separator: "; ")
    }

    // MARK: Notes the boxes share with the editors

    /// The ASA box's explanations, for its title's ⓘ: how the suggestion works, then (a child with nothing to suggest from)
    /// where to tick problems, then the chosen class's definition. Moved here from the Assessment editor, unchanged, so the
    /// editor and the tab say the same.
    static func asaNote(_ r: PatientRecord) -> String {
        var parts = ["The suggestion is the highest class among the ASA's published examples (adult, pediatric under 18, and obstetric) that match what is recorded; the class is a clinical judgment, so it counts only once you choose it."]
        if PatientRules.asaSuggestion(r) == nil && r.isChild {
            parts.append("Tick problems under History, including the Pediatric list, or mark no significant history, for a suggestion from the ASA's pediatric examples.")
        }
        if let c = r.asaClass {
            parts.append(PatientFunctional.asaDefinition(c) + (PatientFunctional.asaExampleLead(c).map { " " + $0 } ?? ""))
        }
        return parts.joined(separator: "\n\n")
    }

    /// How the body-size line is worked out, for the Demographics title's ⓘ once there is a line.
    static func bodySizeNote(_ r: PatientRecord) -> String? {
        r.bmi == nil ? nil : "BSA by DuBois and DuBois, as in the echo tools; ideal body weight by Devine (from 152 cm); lean body weight by Janmahasatian."
    }

    /// The AHA/ACC "Before surgery" notes for the flagged medications that have one, in the flags' order.
    static func beforeSurgery(_ r: PatientRecord) -> [(label: String, note: String)] {
        PatientCatalog.medFlags.filter { r.medFlags.contains($0.id) }.compactMap { f in PatientFunctional.medNotes[f.id].map { (label: f.label, note: $0) } }
    }

    // MARK: Summary

    /// The Preprocedure Summary button is offered once the record holds anything.
    static func summaryAvailable(_ r: PatientRecord) -> Bool { !r.isEmpty }
}

// MARK: - 1.11 — The intraoperative infusion list with the preop drips in it (Ben's note 5, Q6)

/// One row of the intraoperative infusions: an entry of the case's list, or a drip running before the case that has no
/// entry yet (shown "from preop"; the first edit of its rate or drug writes the case's own copy, tagged with the preop
/// drip's id through PatientInfusion.fromPreop).
struct IntraopInfusionRow: Hashable, Identifiable {
    /// The intraop entry's id, or the preop drip's while only that exists.
    var id: UUID
    var drug: String
    var rate: String
    /// Shown with the grey "from preop" caption: the preop drip, not yet changed in the room.
    var fromPreop: Bool
    /// Only the preop record holds it so far.
    var preopOnly: Bool
    /// "Norepinephrine at 0.05 mcg/kg/min", as PatientInfusion.text writes it.
    var text: String { [drug, rate].filter { !$0.isEmpty }.joined(separator: " at ") }
}

enum IntraopInfusionList {
    /// An intraop copy emptied by 🗑: it keeps that preop drip out of the room's list, while the preop record and the
    /// handoff's "running before the case" line keep it. Never shown, and empty text is left out of every summary.
    static func isTombstone(_ i: PatientInfusion) -> Bool {
        i.fromPreop != nil && i.drug.trimmingCharacters(in: .whitespaces).isEmpty && i.rate.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func sameDrug(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String { s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let x = norm(a), y = norm(b)
        return !x.isEmpty && x == y
    }

    /// The rows, merged by drug on read so nothing doubles: for each preop drip its intraop copy (by fromPreop, or by
    /// drug for a 1.10 carry-over) or the drip itself; then the drips started in the room.
    static func rows(_ r: PatientRecord) -> [IntraopInfusionRow] {
        var used = Set<UUID>()
        var out: [IntraopInfusionRow] = []
        for h in r.homeInfusions where !h.drug.isEmpty || !h.rate.isEmpty {
            if let t = r.infusions.first(where: { $0.fromPreop == h.id }) {
                used.insert(t.id)
                if isTombstone(t) { continue }
                out.append(IntraopInfusionRow(id: t.id, drug: t.drug, rate: t.rate, fromPreop: t.drug == h.drug && t.rate == h.rate, preopOnly: false))
            } else if let m = r.infusions.first(where: { !isTombstone($0) && !used.contains($0.id) && sameDrug($0.drug, h.drug) }) {
                used.insert(m.id)
                out.append(IntraopInfusionRow(id: m.id, drug: m.drug, rate: m.rate, fromPreop: false, preopOnly: false))
            } else {
                out.append(IntraopInfusionRow(id: h.id, drug: h.drug, rate: h.rate, fromPreop: true, preopOnly: true))
            }
        }
        for i in r.infusions where !used.contains(i.id) && !isTombstone(i) {
            out.append(IntraopInfusionRow(id: i.id, drug: i.drug, rate: i.rate, fromPreop: false, preopOnly: false))
        }
        return out
    }

    /// The index of the intraop entry a row edits, written from the preop drip when only that exists.
    @discardableResult
    static func materialize(_ rowID: UUID, in r: inout PatientRecord) -> Int? {
        if let i = r.infusions.firstIndex(where: { $0.id == rowID }) { return i }
        guard let h = r.homeInfusions.first(where: { $0.id == rowID }) else { return nil }
        // The copy keeps the drip's id, so the row being typed into stays the same row (its focus with it).
        var copy = PatientInfusion(drug: h.drug, rate: h.rate, fromPreop: h.id)
        copy.id = h.id
        r.infusions.append(copy)
        return r.infusions.count - 1
    }

    static func setRate(_ rowID: UUID, _ rate: String, in r: inout PatientRecord) {
        if let i = materialize(rowID, in: &r) { r.infusions[i].rate = rate }
    }

    static func setDrug(_ rowID: UUID, _ drug: String, in r: inout PatientRecord) {
        if let i = materialize(rowID, in: &r) { r.infusions[i].drug = drug }
    }

    /// 🗑 on a row: the intraop copy goes; a preop drip stays in the preop record (a tombstone keeps it out of this list).
    static func remove(_ rowID: UUID, in r: inout PatientRecord) {
        if let i = r.infusions.firstIndex(where: { $0.id == rowID }) {
            if let p = r.infusions[i].fromPreop, r.homeInfusions.contains(where: { $0.id == p }) {
                r.infusions[i].drug = ""
                r.infusions[i].rate = ""
            } else {
                r.infusions.remove(at: i)
            }
        } else if let h = r.homeInfusions.first(where: { $0.id == rowID }) {
            var stone = PatientInfusion(drug: "", rate: "", fromPreop: h.id)
            stone.id = h.id
            r.infusions.append(stone)
        }
    }

    static let fromPreopCaption = "from preop"
}
