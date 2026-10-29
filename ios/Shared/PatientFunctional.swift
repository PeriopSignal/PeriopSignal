import Foundation

// MARK: - Assessment content for My Patient: ASA definitions, functional capacity (METs, DASI), the stepwise cardiac
// evaluation, perioperative medication notes and the airway exam's method. Wording is ours; the facts and cutoffs
// are the sources' (see each note). The 2024 AHA/ACC recommendations were read from the guideline's text and the
// AHA's official slide set, and the stepwise approach from its Figure 1 (Thompson A, et al. Circulation
// 2024;150:e351–e442; reaffirmed unchanged in September 2026).

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
    static let metsNote = "Under 4 METs is poor functional capacity. Climbing two flights of stairs is over 4 METs; being unable to climb one or two flights, or to walk on level ground at 3 mph, is under 4 (2024 AHA/ACC). A structured measure such as the DASI is preferred (class 2a): the clinician's own estimate did not predict outcomes."

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

    // The 2024 AHA/ACC "Stepwise Approach to Perioperative Cardiac Assessment" (Figure 1, p e371), checked against the
    // figure itself; each recommendation's wording and class against the guideline's text.

    /// Figure 1's acute conditions, which stop elective surgery for management (ACS: §6.1.1, class 1).
    static let activeCardiac: [PatientFlag] = [
        PatientFlag("acs", "Acute coronary syndrome"),
        PatientFlag("decomp-hf", "Decompensated heart failure"),
        PatientFlag("arrhythmia", "Unstable arrhythmia"),
    ]

    /// Active symptoms and signs of cardiovascular disease (§4.1's footnote), with §4.2.1's signs of heart failure.
    static let cardiacSymptomFlags: [PatientFlag] = [
        PatientFlag("chest-pain", "Chest pain"),
        PatientFlag("dyspnea", "New or worsening dyspnea"),
        PatientFlag("palpitations", "Undiagnosed palpitations"),
        PatientFlag("tachycardia", "Tachycardia"),
        PatientFlag("syncope", "Syncope"),
        PatientFlag("murmur", "Murmur"),
        PatientFlag("hf-signs", "Signs of heart failure"),
    ]

    static let cardiacNote = "Follows the 2024 AHA/ACC stepwise approach (Figure 1): cardiovascular risk factors, disease or symptoms; urgency; acute cardiac conditions; the risk estimate and the conditions that add risk; functional capacity; then natriuretic peptides. Routine testing has no benefit."

    /// The acute conditions recorded: the flags, and decompensated heart failure from the problem list.
    static func acuteConditions(_ r: PatientRecord) -> [String] {
        var out = activeCardiac.filter { r.activeCardiac.contains($0.id) }.map(\.label)
        if r.has("hf-decomp"), !out.contains("Decompensated heart failure") { out.append("Decompensated heart failure") }
        return out
    }

    /// Known heart, vascular or cerebrovascular disease (§4.1: coronary disease, significant arrhythmia, peripheral
    /// arterial disease, cerebrovascular disease or other significant structural heart disease).
    static let cvdProblems: Set<String> = [
        "cad", "pci", "pci-recent", "cad-recent", "cabg", "ischemia", "hf", "hf-decomp", "ef-moderate", "ef-severe",
        "valve-severe", "as", "mr", "prosthetic-valve", "af", "arrhythmia", "pacemaker", "icd", "pulm-htn", "pulm-htn-severe",
        "pvd", "chd", "chd-elevated", "cva", "cva-recent", "peripartum-cm",
    ]

    static func knownCVD(_ r: PatientRecord) -> Bool { !r.problems.isDisjoint(with: cvdProblems) }

    /// Figure 1's cardiovascular risk factors that the record shows (its footnote: hypertension, smoking, high
    /// cholesterol, diabetes, women over 65, men over 55, obesity, family history of premature CAD). A raised blood
    /// pressure reading counts here, so that it never ends the evaluation at the first question.
    static func riskFactors(_ r: PatientRecord) -> [String] {
        var out: [String] = []
        if r.has("htn") || r.has("htn-poor") || (r.vitals["sbp"] ?? 0) >= 140 || (r.vitals["dbp"] ?? 0) >= 90 { out.append("hypertension") }
        if r.smoking == "current" { out.append("smoking") }
        if r.has("hyperlipidemia") { out.append("high cholesterol") }
        if r.has("dm") || r.has("dm-poor") || r.has("insulin") { out.append("diabetes") }
        if let age = r.ageYears, age > (r.sex == .female ? 65 : 55) {
            out.append(r.sex == .female ? "woman over 65" : (r.sex == .male ? "man over 55" : "over 55"))
        }
        if let b = r.bmi, b >= 30 { out.append("obesity") }
        if r.has("fh-cad") { out.append("family history of premature CAD") }
        return out
    }

    /// Figure 1's first question answered no: only when the record can answer it (age, height and weight, and smoking
    /// recorded) and shows no risk factor, heart or vascular disease, symptom, tachycardia or acute condition.
    static func noCardiacRisk(_ r: PatientRecord) -> Bool {
        guard r.ageYears != nil, r.bmi != nil, r.smoking != nil else { return false }
        return riskFactors(r).isEmpty && !knownCVD(r) && r.cardiacSymptoms.isEmpty && acuteConditions(r).isEmpty
            && (r.vitals["hr"] ?? 0) <= 100
    }

    /// The RCRI: a saved result, else what the record answers.
    static func rcri(_ r: PatientRecord) -> Int { r.scores["rcri"]?.points ?? PatientRules.prefill("rcri", r).on.count }

    /// Elevated calculated risk: RCRI over 1, the figure's traditional threshold (its footnote †).
    static func elevated(_ r: PatientRecord) -> Bool { rcri(r) > 1 }

    /// Figure 1's risk modifiers, the conditions that add risk beyond the calculators, from what is recorded.
    static func riskModifiers(_ r: PatientRecord) -> [String] {
        var out: [String] = []
        if r.has("valve-severe") { out.append("severe valve disease") }
        if r.has("pulm-htn-severe") { out.append("severe pulmonary hypertension") }
        if r.has("chd-elevated") { out.append("elevated-risk congenital heart disease") }
        let stent = r.has("pci") || r.has("pci-recent")
        if stent || r.has("cabg") {
            out.append(stent && r.has("cabg") ? "prior stent and CABG" : (stent ? (r.has("pci-recent") ? "coronary stent within 3 months" : "prior coronary stent") : "prior CABG"))
        }
        if r.has("cva-recent") { out.append("stroke or TIA within 3 months") }
        if r.has("pacemaker") || r.has("icd") { out.append(r.has("icd") ? "implanted defibrillator" : "pacemaker") }
        if r.frail { out.append("frailty") }
        return out
    }

    /// The figure's boxes between the risk estimate and functional capacity, for a patient who goes on to that step:
    /// elevated calculated risk, or a condition that adds risk at any calculated risk. ECG: §4.1; echo: §4.2.1, §6.4.
    static func branchAdvice(_ r: PatientRecord) -> [String] {
        guard !r.emergency, !noCardiacRisk(r), acuteConditions(r).isEmpty else { return [] }
        let mods = riskModifiers(r)
        guard elevated(r) || !mods.isEmpty else { return [] }
        var out: [String] = []
        if !mods.isEmpty { out.append("Consider team-based consultation on the timing of surgery and on perioperative testing and management.") }
        if knownCVD(r) || !r.cardiacSymptoms.isEmpty {
            out.append("A resting 12-lead ECG is reasonable with known heart, vascular or cerebrovascular disease or cardiac symptoms (class 2a).")
        } else if elevated(r) {
            out.append("A baseline 12-lead ECG may be considered without known cardiovascular disease or symptoms (class 2b).")
        }
        if !mods.isEmpty {
            out.append("An echo is recommended for suspected moderate or severe valve stenosis or regurgitation, new dyspnea, or suspected new or worsening ventricular dysfunction (class 1; class 2a when known heart failure worsens).")
        }
        out.append("Consider starting guideline-directed medical therapy for long-term cardiovascular risk reduction, as applicable.")
        return out
    }

    /// What each recorded condition calls for on its own, whatever the stepwise result (2024 AHA/ACC).
    static func conditionAdvice(_ r: PatientRecord) -> [String] {
        var out: [String] = []
        if r.has("cad-recent") {
            out.append("Recent MI or ACS: after an acute coronary syndrome, revascularization as appropriate and deferral of elective surgery are recommended (class 1).")
        }
        if r.has("pci-recent") {
            out.append("Stent within 3 months: within 30 days of any stent, elective surgery that stops an antiplatelet is potentially harmful (class 3: harm); flag the P2Y12 inhibitor under Medications for the timing rules.")
        }
        if r.has("cva-recent") { out.append("Stroke or TIA within 3 months: delaying elective surgery until 3 months or more after it is reasonable (class 2a).") }
        if r.has("valve-severe") { out.append("Severe valve disease: severe aortic or mitral stenosis should be evaluated for valve intervention before elective surgery (class 1).") }
        if (r.has("as") || r.has("mr")) && !r.has("valve-severe") { out.append("Valve disease: echo before surgery if moderate or severe stenosis or regurgitation is suspected (class 1).") }
        if r.has("chd") || r.has("chd-elevated") { out.append("Congenital heart disease: for intermediate- or elevated-risk lesions, an adult congenital heart disease specialist consult before elective surgery is recommended (class 1).") }
        if r.has("pulm-htn-severe") { out.append("Severe pulmonary hypertension: continue targeted therapy (class 1); before elevated-risk surgery, referral to a pulmonary hypertension center is reasonable (class 2a).") }
        if r.has("pacemaker") || r.has("icd") { out.append("Pacemaker or ICD: a device management plan before surgery when electromagnetic interference is expected (class 1).") }
        if r.has("pci"), !r.has("pci-recent"), !r.medFlags.contains("p2y12") {
            out.append("Prior stent: if surgery will stop an antiplatelet, the stent-timing rules apply (flag the P2Y12 inhibitor under Medications); continue aspirin if possible (class 1).")
        }
        let sbp = r.vitals["sbp"] ?? 0, dbp = r.vitals["dbp"] ?? 0
        if r.has("htn-poor") || sbp >= 180 || dbp >= 110 {
            out.append("Blood pressure 180/110 or higher before elective elevated-risk surgery: deferring surgery may be considered (class 2b).")
        }
        let hf = r.has("hf") || r.has("ef-moderate") || r.has("ef-severe")
        if hf {
            out.append("Heart failure: assess LV function if dyspnea is new or heart failure signs appear (class 1), or if known heart failure has worsened (class 2a).")
        } else if r.cardiacSymptoms.contains("dyspnea") || r.cardiacSymptoms.contains("hf-signs") {
            out.append("New dyspnea or signs of heart failure: assessing LV function before surgery is recommended (class 1).")
        }
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
        var step = stepBeforeSurgery(r)
        if !conditionAdvice(r).isEmpty, step.title.hasSuffix("proceed") {
            step.detail += " The condition-specific steps below still apply."
        }
        if r.urgency == .urgent {
            // §4.5: CCTA "is contraindicated and may be harmful" when surgery is urgent or emergent.
            step.detail = "Urgent surgery: evaluate only as time allows; CT coronary angiography is contraindicated. " + step.detail
        }
        return step
    }

    private static func stepBeforeSurgery(_ r: PatientRecord) -> CardiacStep {
        if noCardiacRisk(r) {
            return CardiacStep(title: "No cardiovascular risk factors, disease or symptoms: proceed", detail: "None recorded: hypertension, smoking, high cholesterol, diabetes, age over 65 in women or 55 in men, obesity, a family history of premature coronary disease, known heart or vascular disease, or cardiac symptoms.", alert: false)
        }
        let active = acuteConditions(r)
        if !active.isEmpty {
            return CardiacStep(title: "Acute cardiac condition: manage it first", detail: active.joined(separator: "; ") + ": treat the condition, and discuss with the team deferring surgery, noninvasive treatment or palliation. With an acute coronary syndrome, revascularization as appropriate and deferral of elective surgery are recommended (class 1).", alert: true)
        }
        let score = rcri(r)
        let riskText = "RCRI " + String(score) + (r.scores["rcri"] != nil ? "" : " from the record (open the RCRI to confirm)")
        let modifiers = riskModifiers(r)
        let modText = modifiers.isEmpty ? "" : "; adds risk: " + modifiers.joined(separator: ", ")
        if !elevated(r) && modifiers.isEmpty {
            return CardiacStep(title: "Low estimated risk: proceed", detail: riskText + ", and nothing recorded that adds risk. Routine testing has no benefit at low risk.", alert: false)
        }
        let why = riskText + (elevated(r) ? " (elevated: over 1)" : " (low)") + modText
        // The DASI is the structured measure the guideline prefers, so it decides when it is recorded.
        let d = dasi(r)
        let good = d.map { $0 > dasiCutoff } ?? (r.mets == "ge4")
        if good {
            let fc = d.map { "DASI " + NumText.short($0) } ?? "4 METs or more"
            return CardiacStep(title: "Good functional capacity: proceed", detail: why + ". " + fc + "; proceed if cardiac symptoms are stable.", alert: false)
        }
        let poorOrUnknown = d != nil || r.mets == "lt4" || r.mets == "unknown"
        guard poorOrUnknown else {
            return CardiacStep(title: "Assess functional capacity", detail: why + ". Record METs or, better, the DASI for the next step.", alert: true)
        }
        let fc = d.map { "DASI " + NumText.short($0) + " (34 or less)" } ?? (r.mets == "lt4" ? "under 4 METs" : "functional capacity unknown")
        switch peptideRaised(r) {
        case .some(false):
            return CardiacStep(title: "Natriuretic peptide normal: proceed", detail: why + "; " + fc + ". " + peptideText(r) + ".", alert: false)
        case .some(true):
            return CardiacStep(title: "Natriuretic peptide raised", detail: why + "; " + fc + ". " + peptideText(r) + ". Discuss with the team the risks and benefits of more cardiac evaluation. If it is pursued, consider an echo, and stress testing or CT coronary angiography (class 2b); with low-risk findings, proceed. With high-risk findings (left main or multivessel disease), or without more evaluation: consider deferring surgery, noninvasive or invasive treatment, or palliation, or proceed; postoperative troponin surveillance may be considered (class 2b).", alert: true)
        case .none:
            return CardiacStep(title: "Poor or unknown functional capacity", detail: why + "; " + fc + ". If more testing would not change management, proceed, or consider deferring surgery, noninvasive treatment or palliation. If it would: before elevated-risk surgery, BNP or NT-proBNP is reasonable (class 2a) with known cardiovascular disease, age 65 or older, or 45 or older with symptoms; troponin may be considered (class 2b). Abnormal: BNP over 92 or NT-proBNP 300 or more (ng/L), troponin above the assay's 99th percentile. Add a result under Labs.", alert: true)
        }
    }

    // MARK: Medications

    /// The 2024 AHA/ACC recommendations for the flagged medications (class of recommendation in brackets), checked
    /// against the guideline's text.
    static let medNotes: [String: String] = [
        "sglt2": "Hold 3 to 4 days before surgery when feasible (class 1): canagliflozin, dapagliflozin and empagliflozin 3 days or more, ertugliflozin 4 days or more.",
        "betablocker": "Continue through surgery (class 1). Without an immediate need, don't start one on the day of surgery (class 3: harm); a new one is best started more than 7 days before (class 2b).",
        "acei": "In selected patients with controlled blood pressure taking it for hypertension, omitting it 24 h before elevated-risk surgery may limit hypotension (class 2b); for heart failure with reduced EF, continuing is reasonable (class 2a).",
        "aspirin": "After PCI, continue aspirin 75–100 mg if possible (class 1).",
        "p2y12": "If elective surgery will stop an antiplatelet: wait at least 14 days after balloon angioplasty (class 1), 12 months after a drug-eluting stent for ACS (class 1) and 6 months after one for stable disease (class 2a); 3 months may be considered when surgery is time-sensitive (class 2b). Within 30 days of any stent it is potentially harmful (class 3: harm).",
        "anticoagulant": "Plan a time-based interruption with the team (class 1). Routine bridging is not recommended (class 3: harm); on a VKA at high thrombotic risk, heparin bridging can be effective (class 2a).",
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
