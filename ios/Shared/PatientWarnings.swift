import Foundation

// MARK: - Warnings from the history (1.9, Ben's Wanted Changes)
//
// Short labels Ben asked for beside history items and on the summary: "Aspiration risk" (history of gastric bypass,
// dysphagia or an esophageal disorder, hiatal hernia, gastroparesis, a full stomach or bowel obstruction) and "Heparin
// caution" (GI bleed). Each label's source is cited where it is defined.

enum PatientWarnings {
    // Aspiration risk, Ben's list (Nov 3). The ASA Practice Guidelines for Preoperative Fasting (Anesthesiology
    // 2017;126:376–393, doi:10.1097/ALN.0000000000001452, PMID 28045707) apply to healthy patients having elective
    // procedures and name coexisting diseases or conditions that can affect gastric emptying or fluid volume, which may
    // call for modified fasting: pregnancy, obesity, diabetes, hiatal hernia, gastroesophageal reflux disease, ileus or
    // bowel obstruction, emergency care and enteral tube feeding. (The guideline's full text was not reachable in this
    // session: this list is as a secondary source quotes it, Ogg MJ, AORN J 2017;106:552–559,
    // doi:10.1016/j.aorn.2017.10.004, the same examples as the 1999 edition.) The Scandinavian guideline on anaesthesia
    // for emergencies counts ileus, bowel obstruction, hiatal hernia and reflux as a high risk of aspiration (Jensen AG,
    // et al. Acta Anaesthesiol Scand 2010;54:922–950, Table 4).
    //   In the ASA list by name: hiatal hernia; full stomach or bowel obstruction (ileus or bowel obstruction,
    //   emergency care).
    //   Within its wording but not named: gastroparesis (a condition that affects gastric emptying).
    //   Ben's additions beyond it: history of gastric bypass, dysphagia, esophageal disorder (a review lists
    //   esophageal pathology, dysphagia and recent upper GI surgery among aspiration risks: Dunn D, AORN J
    //   2022;115:423–436, doi:10.1002/aorn.13666; not a society guideline).
    // Reflux/GERD, named by the ASA, is not on Ben's list and carries no label here (a question for Ben).
    static let aspiration: [(id: String, words: String)] = [
        ("gastric-bypass", "gastric bypass"), ("dysphagia", "dysphagia"), ("esophageal-disorder", "esophageal disorder"),
        ("hiatal-hernia", "hiatal hernia"), ("gastroparesis", "gastroparesis"), ("full-stomach", "full stomach or bowel obstruction"),
    ]
    static let aspirationLabel = "Aspiration risk"

    // Heparin caution, Ben's list (Nov 3): a GI bleed. Heparin is contraindicated with an uncontrolled active bleeding
    // state, except when due to DIC (Heparin Sodium Injection, USP, US prescribing information, Contraindications; to
    // verify against the current label). A resolved bleed keeps the caution without "active".
    static let heparinLabel = "Heparin caution"

    /// The warning labels for one history item, shown beside it on its page ("Aspiration risk").
    static func tags(_ problemId: String, _ r: PatientRecord) -> [String] {
        if aspiration.contains(where: { $0.id == problemId }) { return [aspirationLabel] }
        if problemId == "gi-bleed" { return [r.hx.giBleedStatus == "active" ? heparinLabel + " (active bleed)" : heparinLabel] }
        return []
    }

    /// "active upper GI bleed", "GI bleed".
    static func giBleedWords(_ r: PatientRecord) -> String {
        let status = r.hx.giBleedStatus == "active" ? "active " : ""
        let site = r.hx.giBleedSite.map { $0 == "upper" || $0 == "lower" ? $0 + " " : "" } ?? ""
        return status + site + "GI bleed"
    }

    /// The record's warnings as summary lines ("Aspiration risk: hiatal hernia, gastroparesis"), after the systems.
    static func lines(_ r: PatientRecord) -> [PatientSummary.Line] {
        var out: [PatientSummary.Line] = []
        let asp = aspiration.filter { r.has($0.id) }.map(\.words)
        if !asp.isEmpty { out.append(PatientSummary.Line(aspirationLabel, asp.joined(separator: ", "), alert: true)) }
        if r.has("gi-bleed") { out.append(PatientSummary.Line(heparinLabel, giBleedWords(r), alert: true)) }
        return out
    }
}
