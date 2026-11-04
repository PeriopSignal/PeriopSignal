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
    /// Needs attention (a contraindication on the TEE screen, mechanical support).
    var alert = false
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

    // MARK: Cardiac workup

    /// The nine tests behind "+ Add Preprocedure Cardiac Workup", in Ben's order (ECG, echo, left and right heart cath,
    /// carotid and radial artery ultrasound, pulmonary function tests, TEE screen, mechanical support), each with its
    /// one-line summary when it holds data. The summaries are the ones the assessment page and the handoff use.
    static func workup(_ r: PatientRecord) -> [PreopWorkupItem] {
        let c = r.capitalized
        let tee = PatientTEE.evaluate(r)
        let support = PatientSummary.supportLines(r).map(\.text)
        return [
            PreopWorkupItem(id: "ecg", title: "ECG", icon: "waveform.path.ecg", key: "workup:ecg", summary: PatientSummary.ecgText(r)),
            PreopWorkupItem(id: "echo", title: "Echo", icon: "heart.text.square", key: "workup:echo", summary: r.echoFindings.isEmpty ? nil : c.echoFindings.summary),
            PreopWorkupItem(id: "lhc", title: "Left heart cath", icon: "heart", key: "workup:lhc", summary: r.lhc.isEmpty ? nil : c.lhc.summary),
            PreopWorkupItem(id: "rhc", title: "Right heart cath", icon: "heart.circle", key: "workup:rhc", summary: PatientSummary.rhcText(r)),
            PreopWorkupItem(id: "carotid", title: "Carotid US", icon: "waveform.path", key: "workup:carotid", summary: r.carotid.isEmpty ? nil : c.carotid.summary),
            PreopWorkupItem(id: "radial", title: "Radial artery US", icon: "hand.raised", key: "workup:radial", summary: r.radial.isEmpty ? nil : c.radial.summary),
            PreopWorkupItem(id: "pft", title: "Pulmonary function tests", icon: "lungs", key: "workup:pft", summary: r.pft.isEmpty ? nil : c.pft.summary(copd: r.has("copd"))),
            PreopWorkupItem(id: "tee", title: "TEE screen", icon: tee.level == .none ? "checkmark.shield" : "exclamationmark.triangle", key: "workup:tee",
                            summary: tee.screened ? PatientTEE.status(r) : nil, alert: tee.level != .none),
            PreopWorkupItem(id: "support", title: "Mechanical support", icon: "heart.circle", key: "devices:support",
                            summary: support.isEmpty ? nil : support.joined(separator: "; "), alert: !support.isEmpty),
        ]
    }

    /// Once any is filled, the workup shows open.
    static func workupHasData(_ r: PatientRecord) -> Bool { workup(r).contains { $0.filled } }

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

    // MARK: Summary

    /// The Preprocedure Summary button is offered once the record holds anything.
    static func summaryAvailable(_ r: PatientRecord) -> Bool { !r.isEmpty }
}
