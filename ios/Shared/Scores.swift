import Foundation

// MARK: - Score calculators
//
// Each calculator is data: items worth points, bands that interpret the total, and the paper the
// numbers come from. The arithmetic lives in `ScoreDefinition.total` and `band(for:)` so it can be
// unit-tested without a view. Values are transcribed from the primary publications cited in `source`
// and `rateSource`; keep them in step with reference.json's review dates.

struct ScoreOption: Hashable, Identifiable {
    var id: String { label }
    let label: String
    let points: Int
}

struct ScoreItem: Hashable, Identifiable {
    enum Input: Hashable {
        /// Yes/no worth `points`.
        case toggle(points: Int)
        /// One of several bands.
        case choice([ScoreOption])
    }
    let id: String
    let label: String
    /// Definition shown under the label (what counts).
    let detail: String?
    let input: Input

    static func toggle(_ id: String, _ label: String, _ detail: String? = nil, points: Int = 1) -> ScoreItem {
        ScoreItem(id: id, label: label, detail: detail, input: .toggle(points: points))
    }
    static func choice(_ id: String, _ label: String, _ detail: String? = nil, _ options: [(String, Int)]) -> ScoreItem {
        ScoreItem(id: id, label: label, detail: detail, input: .choice(options.map { ScoreOption(label: $0.0, points: $0.1) }))
    }
}

struct ScoreBand: Hashable {
    enum Tone: Hashable { case low, moderate, high }
    let range: ClosedRange<Int>
    let label: String
    /// Outcome rate or meaning for the band ("6.0% major cardiac complications").
    let detail: String
    let tone: Tone
}

struct ScoreNext: Hashable {
    let label: String
    let quickref: String
}

struct ScoreDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    /// Short name for tiles ("RCRI").
    let short: String
    /// One line on what it predicts.
    let blurb: String
    let icon: String
    let items: [ScoreItem]
    let bands: [ScoreBand]
    /// How to read the result, shown above the bands.
    let readout: String
    let source: RefSource
    /// Where the outcome rates come from when that is a different paper.
    let rateSource: RefSource?
    let notes: [String]
    var keywords: [String] = []
    /// Where the score leads next (a quick reference opened from the result card).
    var next: ScoreNext? = nil

    var maxScore: Int {
        items.reduce(0) { total, item in
            switch item.input {
            case .toggle(let p): return total + p
            case .choice(let options): return total + (options.map(\.points).max() ?? 0)
            }
        }
    }

    /// Points for a selection: toggles map to `true`, choices to the chosen option's label.
    func total(_ selection: ScoreSelection) -> Int {
        items.reduce(0) { total, item in
            switch item.input {
            case .toggle(let p): return total + (selection.on.contains(item.id) ? p : 0)
            case .choice(let options):
                guard let chosen = selection.choices[item.id] else { return total + (options.first?.points ?? 0) }
                return total + (options.first { $0.label == chosen }?.points ?? 0)
            }
        }
    }

    func band(for score: Int) -> ScoreBand? { bands.first { $0.range.contains(score) } }

    /// Count of positive answers (STOP-Bang style scores are read as counts, not weighted points).
    func count(_ selection: ScoreSelection) -> Int { total(selection) }

    var searchText: String { ([name, short, blurb] + keywords + items.map(\.label)).joined(separator: " ").lowercased() }
}

/// A user's answers: toggles that are on, and the chosen option label per choice item.
struct ScoreSelection: Hashable {
    var on: Set<String> = []
    var choices: [String: String] = [:]
    var isEmpty: Bool { on.isEmpty && choices.isEmpty }
}

// MARK: - Definitions

enum Scores {
    static let all: [ScoreDefinition] = [rcri, ariscat, stopBang, aldrete, apfel]
    static func byID(_ id: String) -> ScoreDefinition? { all.first { $0.id == id } }

    /// Revised Cardiac Risk Index. Lee TH et al. Circulation 1999;100:1043-9; updated event rates from
    /// the 2017 CCS perioperative guideline's systematic review (Duceppe E et al. Can J Cardiol 2017).
    static let rcri = ScoreDefinition(
        id: "rcri", name: "Revised Cardiac Risk Index", short: "RCRI",
        blurb: "Risk of major cardiac complications after non-cardiac surgery",
        icon: "heart.text.square",
        items: [
            .toggle("surgery", "High-risk surgery", "Intraperitoneal, intrathoracic or suprainguinal vascular"),
            .toggle("ihd", "Ischemic heart disease", "Prior MI, positive stress test, current ischemic chest pain, nitrate use, or Q waves"),
            .toggle("hf", "History of heart failure", "Pulmonary edema, paroxysmal nocturnal dyspnea, S3 or rales, or CXR pulmonary vascular redistribution"),
            .toggle("cva", "Cerebrovascular disease", "Prior stroke or transient ischemic attack"),
            .toggle("insulin", "Insulin therapy for diabetes"),
            .toggle("creatinine", "Creatinine > 2.0 mg/dL", "> 177 µmol/L preoperatively"),
        ],
        bands: [
            ScoreBand(range: 0...0, label: "Class I · 0 predictors", detail: "3.9% (95% CI 2.8–5.4) · Lee 1999 validation cohort 0.4%", tone: .low),
            ScoreBand(range: 1...1, label: "Class II · 1 predictor", detail: "6.0% (4.9–7.4) · Lee 0.9%", tone: .low),
            ScoreBand(range: 2...2, label: "Class III · 2 predictors", detail: "10.1% (8.1–12.6) · Lee 6.6%", tone: .moderate),
            ScoreBand(range: 3...6, label: "Class IV · 3 or more", detail: "15.0% (11.1–20.0) · Lee 11.0%", tone: .high),
        ],
        readout: "First figure: pooled 30-day risk of MI, cardiac arrest or death from the 2017 CCS guideline's external validation studies. Second: Lee's 1999 validation cohort (in-hospital MI, pulmonary edema, VF or cardiac arrest, complete heart block).",
        source: RefSource(title: "Derivation and prospective validation of a simple index for prediction of cardiac risk of major noncardiac surgery", citation: "Lee TH, et al. Circulation. 1999;100:1043–1049.", url: "https://doi.org/10.1161/01.CIR.100.10.1043", doi: "10.1161/01.CIR.100.10.1043"),
        rateSource: RefSource(title: "Canadian Cardiovascular Society guidelines on perioperative cardiac risk assessment and management for patients who undergo noncardiac surgery", citation: "Duceppe E, et al. Can J Cardiol. 2017;33:17–32.", url: "https://doi.org/10.1016/j.cjca.2016.09.008", doi: "10.1016/j.cjca.2016.09.008"),
        notes: ["Derived in patients ≥ 50 years having elective major non-cardiac surgery; emergency surgery and low-risk procedures were excluded.",
                "The CCS guideline pairs RCRI ≥ 1 (or age ≥ 65, or 45–64 with significant cardiovascular disease) with preoperative NT-proBNP/BNP measurement."],
        keywords: ["cardiac risk", "lee index", "preoperative evaluation", "noncardiac surgery", "mace"])

    /// ARISCAT. Canet J et al. Anesthesiology 2010;113:1338-50.
    static let ariscat = ScoreDefinition(
        id: "ariscat", name: "ARISCAT", short: "ARISCAT",
        blurb: "Risk of postoperative pulmonary complications",
        icon: "lungs",
        items: [
            .choice("age", "Age", nil, [("≤ 50", 0), ("51–80", 3), ("> 80", 16)]),
            .choice("spo2", "Preoperative SpO₂", "Room air, supine", [("≥ 96%", 0), ("91–95%", 8), ("≤ 90%", 24)]),
            .toggle("infection", "Respiratory infection in the last month", "Upper or lower respiratory infection within the previous month", points: 17),
            .toggle("anemia", "Preoperative anemia", "Hemoglobin ≤ 10 g/dL", points: 11),
            .choice("incision", "Surgical incision", nil, [("Peripheral", 0), ("Upper abdominal", 15), ("Intrathoracic", 24)]),
            .choice("duration", "Duration of surgery", nil, [("≤ 2 h", 0), ("> 2–3 h", 16), ("> 3 h", 23)]),
            .toggle("emergency", "Emergency procedure", nil, points: 8),
        ],
        bands: [
            ScoreBand(range: 0...25, label: "Low risk · < 26 points", detail: "1.6% pulmonary complications in the development sample", tone: .low),
            ScoreBand(range: 26...44, label: "Intermediate · 26–44", detail: "13.3%", tone: .moderate),
            ScoreBand(range: 45...123, label: "High · ≥ 45", detail: "42.1%", tone: .high),
        ],
        readout: "In-hospital postoperative pulmonary complications (respiratory infection or failure, bronchospasm, atelectasis, pleural effusion, pneumothorax, aspiration pneumonitis); 5% overall in the 2,464-patient cohort.",
        source: RefSource(title: "Prediction of postoperative pulmonary complications in a population-based surgical cohort", citation: "Canet J, et al. Anesthesiology. 2010;113:1338–1350.", url: "https://doi.org/10.1097/ALN.0b013e3181fc6e0a", doi: "10.1097/ALN.0b013e3181fc6e0a"),
        rateSource: nil,
        notes: ["Derived from 2,464 patients in 59 Catalan hospitals having non-obstetric surgery under general, neuraxial or regional anesthesia; AUC 0.90 (development) and 0.88 (validation).",
                "External validation (PERISCOPE, 2014) found higher observed rates in the low and intermediate classes than predicted."],
        keywords: ["pulmonary complications", "ppc", "respiratory risk", "canet"])

    /// STOP-Bang. Chung F et al. Anesthesiology 2008;108:812-21; Chest 2016;149:631-8.
    static let stopBang = ScoreDefinition(
        id: "stopbang", name: "STOP-Bang", short: "STOP-Bang",
        blurb: "Screening for obstructive sleep apnea",
        icon: "zzz",
        items: [
            .toggle("snoring", "Snoring", "Loud enough to be heard through a closed door, or a bed partner elbows you"),
            .toggle("tired", "Tired", "Often tired, fatigued or sleepy during the day"),
            .toggle("observed", "Observed apnea", "Anyone has seen you stop breathing or choke/gasp during sleep"),
            .toggle("pressure", "Pressure", "Treated or untreated high blood pressure"),
            .toggle("bmi", "BMI > 35 kg/m²"),
            .toggle("age", "Age > 50 years"),
            .toggle("neck", "Neck circumference > 40 cm", "About 16 in, measured at the laryngeal prominence (the Toronto form uses ≥ 43 cm for men and ≥ 41 cm for women)"),
            .toggle("gender", "Male"),
        ],
        bands: [
            ScoreBand(range: 0...2, label: "Low risk · 0–2", detail: "Moderate-to-severe OSA unlikely", tone: .low),
            ScoreBand(range: 3...4, label: "Intermediate · 3–4", detail: "A score ≥ 3 is 93% sensitive for AHI > 15 and 100% for AHI > 30; specificity is modest, so weigh BMI, neck size and sex", tone: .moderate),
            ScoreBand(range: 5...8, label: "High risk · 5–8", detail: "High probability of moderate-to-severe OSA", tone: .high),
        ],
        readout: "Count of yes answers. The 2016 update also classes yes to ≥ 2 of the STOP questions plus male sex, BMI > 35 or neck > 40 cm as high risk.",
        source: RefSource(title: "STOP questionnaire: a tool to screen patients for obstructive sleep apnea", citation: "Chung F, et al. Anesthesiology. 2008;108:812–821.", url: "https://doi.org/10.1097/ALN.0b013e31816d83e4", doi: "10.1097/ALN.0b013e31816d83e4"),
        rateSource: RefSource(title: "STOP-Bang questionnaire: a practical approach to screen for obstructive sleep apnea", citation: "Chung F, Abdullah HR, Liao P. Chest. 2016;149:631–638.", url: "https://doi.org/10.1378/chest.15-0903", doi: "10.1378/chest.15-0903"),
        notes: ["Validated against polysomnography in surgical patients; the probability of moderate-to-severe OSA rises steadily with the score."],
        keywords: ["osa", "sleep apnea", "screening", "airway"])

    /// Modified Aldrete score. Aldrete JA. J Clin Anesth 1995;7:89-91.
    static let aldrete = ScoreDefinition(
        id: "aldrete", name: "Modified Aldrete score", short: "Aldrete",
        blurb: "Readiness to leave the recovery room",
        icon: "bed.double",
        items: [
            .choice("activity", "Activity", "Voluntary or on command", [("Moves 4 extremities", 2), ("Moves 2 extremities", 1), ("Moves 0 extremities", 0)]),
            .choice("respiration", "Respiration", nil, [("Breathes deeply and coughs freely", 2), ("Dyspnea, shallow or limited breathing", 1), ("Apneic", 0)]),
            .choice("circulation", "Circulation", "Blood pressure versus the pre-anesthetic level", [("Within ± 20%", 2), ("± 20–49%", 1), ("± 50% or more", 0)]),
            .choice("consciousness", "Consciousness", nil, [("Fully awake", 2), ("Arousable on calling", 1), ("Not responding", 0)]),
            .choice("oxygen", "Oxygen saturation", nil, [("> 92% on room air", 2), ("Needs O₂ to keep > 90%", 1), ("< 90% even with O₂", 0)]),
        ],
        bands: [
            ScoreBand(range: 0...8, label: "Not ready · < 9", detail: "Continue phase I recovery", tone: .high),
            ScoreBand(range: 9...10, label: "Ready · 9–10", detail: "Meets the discharge criterion for phase I recovery", tone: .low),
        ],
        readout: "Total 0–10; a score of 9 or more is the usual criterion for discharge from phase I recovery.",
        source: RefSource(title: "The post-anesthesia recovery score revisited", citation: "Aldrete JA. J Clin Anesth. 1995;7:89–91.", url: "https://doi.org/10.1016/0952-8180(94)00001-K", doi: "10.1016/0952-8180(94)00001-K"),
        rateSource: nil,
        notes: ["The 1995 revision replaced the 1970 score's color criterion (pink / pale or dusky / cyanotic) with pulse oximetry."],
        keywords: ["pacu", "recovery", "discharge criteria", "phase i"])

    /// Apfel simplified PONV score. Apfel CC et al. Anesthesiology 1999;91:693-700; prophylaxis per the
    /// Fourth Consensus Guidelines (Gan TJ et al. Anesth Analg 2020;131:411-48).
    static let apfel = ScoreDefinition(
        id: "apfel", name: "Apfel PONV score", short: "Apfel",
        blurb: "Risk of postoperative nausea and vomiting, with the consensus prophylaxis",
        icon: "pills",
        items: [
            .toggle("female", "Female sex"),
            .toggle("nonsmoker", "Non-smoker"),
            .toggle("history", "History of PONV or motion sickness"),
            .toggle("opioids", "Postoperative opioids expected"),
        ],
        bands: [
            ScoreBand(range: 0...0, label: "0 factors · 10%", detail: "Low risk. Fifth consensus (2025): two prophylactic interventions for adults at any risk", tone: .low),
            ScoreBand(range: 1...1, label: "1 factor · 21%", detail: "Medium risk: two interventions (e.g. dexamethasone + a 5-HT₃ antagonist)", tone: .low),
            ScoreBand(range: 2...2, label: "2 factors · 39%", detail: "Medium risk: two interventions", tone: .moderate),
            ScoreBand(range: 3...3, label: "3 factors · 61%", detail: "High risk: three to four interventions from different classes, plus risk reduction (TIVA, opioid-sparing, regional)", tone: .high),
            ScoreBand(range: 4...4, label: "4 factors · 79%", detail: "High risk: three to four interventions, plus risk reduction", tone: .high),
        ],
        readout: "Incidence of PONV within 24 h in Apfel's 1999 cohorts (inhalational anesthesia, no prophylaxis). Rescue uses a class not already given; a same-class repeat within 6 h adds nothing.",
        source: RefSource(title: "A simplified risk score for predicting postoperative nausea and vomiting", citation: "Apfel CC, et al. Anesthesiology. 1999;91:693–700.", url: "https://doi.org/10.1097/00000542-199909000-00022", doi: "10.1097/00000542-199909000-00022"),
        rateSource: RefSource(title: "Fifth Consensus Guidelines for the Management of Postoperative Nausea and Vomiting: Executive Summary", citation: "Gan TJ, Jin Z, Ayad S, et al. Anesth Analg. 2025; published online ahead of print.", url: "https://doi.org/10.1213/ANE.0000000000007816", doi: "10.1213/ANE.0000000000007816"),
        notes: ["See the PONV quick reference for agents, doses and timing.", "The Fifth consensus (2025) supersedes the 2020 Fourth: it counts 0 factors as low, 1–2 as medium and ≥ 3 as high risk, adds IV aprepitant and IV amisulpride, and no longer recommends metoclopramide for prophylaxis."],
        keywords: ["ponv", "nausea", "vomiting", "antiemetic", "prophylaxis"],
        next: ScoreNext(label: "Prophylaxis plan", quickref: "ponv-consensus"))
}
