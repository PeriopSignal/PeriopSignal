import Foundation

// MARK: - Assessment content for My Patient: ASA definitions, functional capacity (METs, DASI), the stepwise cardiac
// evaluation, perioperative medication notes and the airway exam's method. Wording is ours; the facts and cutoffs
// are the sources' (see each note). The 2024 AHA/ACC recommendations were read from the guideline's text and the
// AHA's official slide set (Thompson A, et al. Circulation 2024;150:e351–e442; reaffirmed unchanged in September 2026).

struct CardiacStep: Hashable {
    var title: String
    var detail: String
    var alert: Bool
}

enum PatientFunctional {
    // MARK: ASA

    /// How the ASA's adult examples open for classes II and III: the line between them is functional limitation.
    static func asaExampleLead(_ c: Int) -> String? {
        switch c {
        case 2: return "ASA examples: mild diseases only, without substantive functional limitations."
        case 3: return "ASA examples: substantive functional limitations; one or more moderate to severe diseases."
        default: return nil
        }
    }

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

    /// 2024 AHA/ACC, Sections 3.2 and 4.3.
    static let metsNote = "Under 4 METs is poor functional capacity. Climbing two flights of stairs is over 4 METs; being unable to climb one or two flights, or to walk on level ground at 3 mph, is under 4 (2024 AHA/ACC). The DASI below is the structured version."

    /// Duke Activity Status Index (Hlatky MA, et al. Am J Cardiol 1989;64:651–654; the original items as reproduced by
    /// Coutinho-Myrrha MA, Hlatky MA, et al. Arq Bras Cardiol 2014, and reprinted in the 2024 AHA/ACC guideline's
    /// Table 5): the activities in our words, with the published weights.
    static let dasiItems: [PatientDasiItem] = [
        PatientDasiItem("self-care", "Takes care of themselves: eating, dressing, bathing, toilet", 2.75),
        PatientDasiItem("walk-indoors", "Walks indoors, around the house", 1.75),
        PatientDasiItem("walk-blocks", "Walks a block or two on level ground", 2.75),
        PatientDasiItem("stairs", "Climbs a flight of stairs or walks up a hill", 5.50),
        PatientDasiItem("run", "Runs a short distance", 8.00),
        PatientDasiItem("light-housework", "Light housework: dusting, washing dishes", 2.70),
        PatientDasiItem("moderate-housework", "Moderate housework: vacuuming, sweeping floors, carrying in groceries", 3.50),
        PatientDasiItem("heavy-housework", "Heavy housework: scrubbing floors, lifting or moving heavy furniture", 8.00),
        PatientDasiItem("yardwork", "Yard work: raking leaves, weeding, pushing a power mower", 4.50),
        PatientDasiItem("sex", "Sexual relations", 5.25),
        PatientDasiItem("moderate-sport", "Moderate recreation: golf, bowling, dancing, doubles tennis, throwing a baseball or football", 6.00),
        PatientDasiItem("strenuous-sport", "Strenuous sports: swimming, singles tennis, football, basketball, skiing", 7.50),
    ]

    /// The DASI score (0–58.2), the sum of the ticked activities' weights; nil until one is ticked.
    static func dasi(_ r: PatientRecord) -> Double? {
        guard !r.dasi.isEmpty else { return nil }
        return dasiItems.filter { r.dasi.contains($0.id) }.reduce(0) { $0 + $1.weight }
    }

    /// The 2024 AHA/ACC cutoff: a DASI of 34 or less is poor functional capacity.
    static let dasiCutoff = 34.0

    /// "DASI 40.25 of 58.2 · above 34".
    static func dasiText(_ score: Double) -> String {
        "DASI " + NumText.short(score) + " of 58.2 · " + (score > dasiCutoff ? "above 34" : "34 or less: poor")
    }

    static let dasiNote = "The 2024 AHA/ACC guideline counts a DASI of 34 or less as poor functional capacity. In a multicentre cohort, scores above 34 went with lower odds of 30-day death or myocardial injury (Wijeysundera 2020)."

    // MARK: Cardiac evaluation

    /// Acute conditions that stop elective surgery for evaluation and treatment.
    static let activeCardiac: [PatientFlag] = [
        PatientFlag("acs", "Acute coronary syndrome"),
        PatientFlag("decomp-hf", "Decompensated heart failure"),
        PatientFlag("arrhythmia", "Unstable arrhythmia"),
    ]

    static let cardiacNote = "2024 AHA/ACC stepwise approach: urgency, acute cardiac conditions, the risk estimate and conditions that add risk, functional capacity, then natriuretic peptides. Further testing only when the result would change management."

    /// Conditions that add risk beyond the calculators (the figure's risk modifiers), from what is recorded.
    static func riskModifiers(_ r: PatientRecord) -> [String] {
        var out: [String] = []
        if r.has("valve-severe") { out.append("severe valve disease") }
        if r.has("pulm-htn-severe") { out.append("severe pulmonary hypertension") }
        if r.has("chd") { out.append("congenital heart disease") }
        if r.has("pci") || r.has("cabg") { out.append(r.has("pci") && r.has("cabg") ? "prior stent and CABG" : (r.has("pci") ? "prior coronary stent" : "prior CABG")) }
        if r.has("cva-recent") { out.append("stroke or TIA within 3 months") }
        if r.has("pacemaker") || r.has("icd") { out.append(r.has("icd") ? "implanted defibrillator" : "pacemaker") }
        if r.frail { out.append("frailty") }
        return out
    }

    /// BNP above 92 or NT-proBNP of 300 or more (pg/mL, the same as ng/L): the figure's abnormal thresholds.
    static func peptideRaised(_ r: PatientRecord) -> Bool? {
        let bnp = r.labs["bnp"], nt = r.labs["ntprobnp"]
        guard bnp != nil || nt != nil else { return nil }
        return (bnp.map { $0 > 92 } ?? false) || (nt.map { $0 >= 300 } ?? false)
    }

    private static func peptideText(_ r: PatientRecord) -> String {
        [r.labs["bnp"].map { "BNP " + NumText.short($0) + " (abnormal over 92)" }, r.labs["ntprobnp"].map { "NT-proBNP " + NumText.short($0) + " (abnormal 300 or more)" }]
            .compactMap { $0 }.joined(separator: "; ")
    }

    /// Where the patient sits in the stepwise approach, from what is recorded.
    static func cardiacStep(_ r: PatientRecord) -> CardiacStep {
        if r.emergency {
            return CardiacStep(title: "Emergency surgery: proceed", detail: "Testing should not delay an emergency operation; manage the cardiac risk during and after surgery.", alert: false)
        }
        let active = activeCardiac.filter { r.activeCardiac.contains($0.id) }.map(\.label)
        if !active.isEmpty {
            return CardiacStep(title: "Acute cardiac condition: defer elective surgery", detail: active.joined(separator: "; ") + ": evaluate and treat first. With an acute coronary syndrome, revascularization as appropriate and deferral of elective surgery are recommended.", alert: true)
        }
        let rcri = r.scores["rcri"]?.points ?? PatientRules.prefill("rcri", r).on.count
        let riskText = "RCRI " + String(rcri) + (r.scores["rcri"] != nil ? "" : " from the record (open the RCRI to confirm)")
        let modifiers = riskModifiers(r)
        let modText = modifiers.isEmpty ? "" : "; adds risk: " + modifiers.joined(separator: ", ")
        // The guideline's footnote: elevated risk is traditionally RCRI > 1 (or a calculated MACE risk above 1%).
        if rcri <= 1 && modifiers.isEmpty {
            return CardiacStep(title: "Low estimated risk: proceed", detail: riskText + ", and nothing recorded that adds risk. No further cardiac testing on this basis.", alert: false)
        }
        let why = riskText + (rcri <= 1 ? " (low)" : " (elevated: over 1)") + modText
        // The DASI is the structured measure, so it decides when it is recorded.
        let d = dasi(r)
        let good = d.map { $0 > dasiCutoff } ?? (r.mets == "ge4")
        if good {
            let fc = d.map { "DASI " + NumText.short($0) } ?? "4 METs or more"
            return CardiacStep(title: "Good functional capacity: proceed", detail: why + ". " + fc + ".", alert: false)
        }
        let poorOrUnknown = d != nil || r.mets == "lt4" || r.mets == "unknown"
        guard poorOrUnknown else {
            return CardiacStep(title: "Assess functional capacity", detail: why + ". Record METs or the DASI for the next step.", alert: true)
        }
        let fc = d.map { "DASI " + NumText.short($0) + " (34 or less)" } ?? (r.mets == "lt4" ? "under 4 METs" : "functional capacity unknown")
        switch peptideRaised(r) {
        case .some(false):
            return CardiacStep(title: "Natriuretic peptide normal: proceed", detail: why + "; " + fc + ". " + peptideText(r) + ".", alert: false)
        case .some(true):
            return CardiacStep(title: "Natriuretic peptide raised", detail: why + "; " + fc + ". " + peptideText(r) + ". Discuss with the team; stress testing or CT coronary angiography may be considered only when the result would change management, and routine testing is not recommended.", alert: true)
        case .none:
            return CardiacStep(title: "Poor or unknown functional capacity", detail: why + "; " + fc + ". Before elevated-risk surgery, BNP or NT-proBNP is reasonable (class 2a) and troponin may be considered (class 2b). Add a result under Labs.", alert: true)
        }
    }

    // MARK: Medications

    /// The 2024 AHA/ACC recommendations for the flagged medications (class of recommendation in brackets).
    static let medNotes: [String: String] = [
        "sglt2": "Hold 3 to 4 days before surgery when feasible (class 1): canagliflozin, dapagliflozin and empagliflozin 3 days or more, ertugliflozin 4 days or more.",
        "betablocker": "Continue through surgery (class 1). Don't start one on the day of surgery (class 3: harm).",
        "acei": "For hypertension, omitting it 24 h before elevated-risk surgery may help limit hypotension (class 2b); for heart failure with reduced EF, continuing is reasonable (class 2a).",
        "aspirin": "After PCI, continue aspirin 75–100 mg if possible (class 1).",
        "p2y12": "Elective surgery that stops an antiplatelet waits at least 14 days after balloon angioplasty, 12 months after a drug-eluting stent for ACS, and 6 months after one for stable disease (3 months if time-sensitive). Within 30 days of any stent it is potentially harmful (class 3: harm).",
        "anticoagulant": "Plan a time-based interruption with the team (class 1). Routine bridging is not recommended (class 3: harm); heparin bridging can help on a VKA at high thrombotic risk (class 2a).",
    ]

    // MARK: Airway

    /// The modified test as usually done (seated, mouth fully open, tongue out, no phonation); phonation changes the
    /// class (Tham 1992; Oates 1990); used alone it has limited accuracy (Lee A, et al. Anesth Analg 2006).
    static let mallampatiHow = "Sitting, mouth open as wide as possible, tongue out as far as possible, without phonation; saying \u{201C}ah\u{201D} improves the view, so examine the same way each time. Tap the view you see (Samsoon and Young's four classes). Used alone, the Mallampati has limited accuracy."

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
