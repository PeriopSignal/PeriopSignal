import Foundation

// MARK: - Assessment content for My Patient: ASA definitions, functional capacity (METs, DASI), the stepwise cardiac
// evaluation, and the airway exam's method. Wording is ours; the facts and cutoffs are the sources' (see each note).

struct CardiacStep: Hashable {
    var title: String
    var detail: String
    var alert: Bool
}

enum PatientFunctional {
    // MARK: ASA

    /// The ASA Physical Status Classification System's definitions (last amended December 13, 2020).
    static func asaDefinition(_ c: Int) -> String {
        switch c {
        case 1: return "ASA I: a normal healthy patient."
        case 2: return "ASA II: a patient with mild systemic disease."
        case 3: return "ASA III: a patient with severe systemic disease."
        case 4: return "ASA IV: a patient with severe systemic disease that is a constant threat to life."
        case 5: return "ASA V: a moribund patient who is not expected to survive without the operation."
        default: return "ASA VI: a declared brain-dead patient whose organs are being removed for donor purposes."
        }
    }

    // MARK: Functional capacity

    static let metsNote = "4 METs is about climbing a flight of stairs or walking up a hill, walking on level ground at 4 mph, or heavy work around the house. The DASI below turns the answers into a score."

    /// Duke Activity Status Index (Hlatky MA, et al. Am J Cardiol 1989;64:651–654): the activities, in our words,
    /// with their published weights.
    static let dasiItems: [PatientDasiItem] = [
        PatientDasiItem("self-care", "Takes care of themselves: eating, dressing, bathing, toilet", 2.75),
        PatientDasiItem("walk-indoors", "Walks indoors, around the house", 1.75),
        PatientDasiItem("walk-blocks", "Walks a block or two on level ground", 2.75),
        PatientDasiItem("stairs", "Climbs a flight of stairs or walks up a hill", 5.50),
        PatientDasiItem("run", "Runs a short distance", 8.00),
        PatientDasiItem("light-housework", "Light housework: dusting, washing dishes", 2.70),
        PatientDasiItem("moderate-housework", "Moderate housework: vacuuming, sweeping, carrying groceries", 3.50),
        PatientDasiItem("heavy-housework", "Heavy housework: scrubbing floors, lifting or moving heavy furniture", 8.00),
        PatientDasiItem("yardwork", "Yard work: raking leaves, weeding, pushing a power mower", 4.50),
        PatientDasiItem("sex", "Sexual relations", 5.25),
        PatientDasiItem("moderate-sport", "Moderate recreation: golf, bowling, dancing, doubles tennis, throwing a ball", 6.00),
        PatientDasiItem("strenuous-sport", "Strenuous sports: swimming, singles tennis, football, basketball, skiing", 7.50),
    ]

    /// The DASI score (0–58.2) and its estimated METs (peak VO₂ = 0.43 × DASI + 9.6 mL/kg/min; 1 MET = 3.5), when any
    /// activity is ticked.
    static func dasi(_ r: PatientRecord) -> (score: Double, mets: Double)? {
        guard !r.dasi.isEmpty else { return nil }
        let score = dasiItems.filter { r.dasi.contains($0.id) }.reduce(0) { $0 + $1.weight }
        return (score, (0.43 * score + 9.6) / 3.5)
    }

    static let dasiNote = "In the METS study a DASI above 34 went with a lower risk of death or myocardial injury after major noncardiac surgery; the guideline uses it to judge functional capacity."

    // MARK: Cardiac evaluation

    static let activeCardiac: [PatientFlag] = [
        PatientFlag("acs", "Acute coronary syndrome or unstable angina"),
        PatientFlag("decomp-hf", "Decompensated heart failure"),
        PatientFlag("arrhythmia", "Significant arrhythmia", "High-grade AV block, symptomatic or uncontrolled arrhythmia"),
        PatientFlag("severe-valve", "Severe or symptomatic valve disease"),
    ]

    static let cardiacNote = "ACC/AHA stepwise approach for noncardiac surgery: urgency, active cardiac conditions, the risk estimate, then functional capacity; further testing only when the result would change management."

    /// Where the patient sits in the stepwise approach, from what is recorded.
    static func cardiacStep(_ r: PatientRecord) -> CardiacStep {
        if r.emergency {
            return CardiacStep(title: "Emergency surgery: proceed", detail: "Testing should not delay an emergency operation; manage the cardiac risk during and after surgery.", alert: false)
        }
        let active = activeCardiac.filter { r.activeCardiac.contains($0.id) }.map(\.label)
        if !active.isEmpty {
            return CardiacStep(title: "Active cardiac condition", detail: active.joined(separator: "; ") + ": evaluate and treat before elective surgery.", alert: true)
        }
        let rcri = r.scores["rcri"]?.points ?? PatientRules.prefill("rcri", r).on.count
        let fromSaved = r.scores["rcri"] != nil
        let riskText = "RCRI " + String(rcri) + (fromSaved ? "" : " from the record (open the RCRI to confirm)")
        if rcri <= 1 {
            return CardiacStep(title: "Low estimated risk: proceed", detail: riskText + ". No further cardiac testing is needed on this basis.", alert: false)
        }
        let d = dasi(r)
        if r.mets == "ge4" || (d.map { $0.score > 34 } ?? false) {
            return CardiacStep(title: "Elevated risk, good functional capacity: proceed", detail: riskText + "; 4 METs or more" + (d.map { ", DASI " + PedsCalc.fmt($0.score) } ?? "") + ".", alert: false)
        }
        if r.mets == "lt4" || r.mets == "unknown" || d != nil {
            return CardiacStep(title: "Elevated risk, poor or unknown functional capacity", detail: riskText + ". Consider BNP or NT-proBNP, and further testing only if it would change management.", alert: true)
        }
        return CardiacStep(title: "Elevated risk: assess functional capacity", detail: riskText + ". Record METs or the DASI to take the next step.", alert: true)
    }

    // MARK: Airway

    static let mallampatiHow = "Sitting, head neutral, mouth open as wide as possible and the tongue out as far as possible, without phonation; tap the view you see (modified Mallampati, Samsoon and Young)."

    static let echoPhrases = [
        "Normal LV size and function", "Reduced LV systolic function", "RV dysfunction", "New regional wall-motion abnormality",
        "Pericardial effusion", "Significant valve lesion", "Underfilled LV", "No intracardiac thrombus",
    ]
}

struct PatientDasiItem: Hashable, Identifiable {
    var id: String
    var label: String
    var weight: Double
    init(_ id: String, _ label: String, _ weight: Double) { self.id = id; self.label = label; self.weight = weight }
}
