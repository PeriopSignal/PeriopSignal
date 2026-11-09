import Foundation

// MARK: - Labs for My Patient
//
// What the Labs screens need, kept here so the tests can reach it: the catalog (key, label, unit, group, adult
// reference range, decimals, plausible input range), each value's flag (normal, low, high), a condensed summary with
// a fishbone, the liver scores (MELD 3.0, MELD-Na, Child-Turcotte-Pugh) with a short perioperative reading, and the
// arithmetic of a right heart catheterization with the 2022 ESC/ERS haemodynamic definitions. US conventional units
// throughout. Keys already stored in PatientRecord.labs keep their names, so records saved before this file still read.
//
// Reference ranges are typical adult ranges and only a guide: every laboratory sets its own, and the range on the
// patient's report wins. Sources: the ABIM Laboratory Test Reference Ranges, January 2026, for every range below
// unless its entry says otherwise; INR, MedlinePlus (NLM, A.D.A.M. encyclopedia, "Prothrombin time", reviewed
// February 3, 2025: 0.8 to 1.1 without blood thinners; ABIM lists the PT in seconds only); GFR, the KDIGO criterion
// of decreased GFR, under 60 mL/min/1.73 m² for more than 3 months (as the National Kidney Foundation states the
// criteria); BNP, NT-proBNP and troponin, the 2024 AHA/ACC thresholds that PatientFunctional reads (Figure 1,
// footnote §: BNP over 92, NT-proBNP 300 or more, troponin above the assay's 99th percentile).

enum LabFlag: String, Codable, Hashable {
    case normal, low, high

    var isAbnormal: Bool { self != .normal }

    /// "L", "H" or "": the mark a lab report prints beside the value.
    var mark: String {
        switch self {
        case .normal: return ""
        case .low: return "L"
        case .high: return "H"
        }
    }
}

enum LabGroup: String, CaseIterable, Codable, Hashable {
    /// Always on the screen.
    case main
    /// BNP, NT-proBNP, troponin and its assay's 99th percentile, behind an add button.
    case cardiac
    /// AST, ALT, alkaline phosphatase; albumin and total bilirubin are in main, beside the other MELD inputs.
    case liver
    case thyroid

    var title: String {
        switch self {
        case .main: return "Labs"
        case .cardiac: return "Cardiac"
        case .liver: return "Liver"
        case .thyroid: return "Thyroid"
        }
    }
}

/// A reference interval: a value below `low` is low, above `high` is high (and at `high` itself when
/// `highInclusive`, as for NT-proBNP 300 or more). A nil side is never flagged.
struct LabRange: Hashable {
    var low: Double?
    var high: Double?
    var highInclusive: Bool

    init(_ low: Double?, _ high: Double?, highInclusive: Bool = false) {
        self.low = low
        self.high = high
        self.highInclusive = highInclusive
    }

    func flag(_ v: Double) -> LabFlag {
        if let l = low, v < l { return .low }
        if let h = high, highInclusive ? v >= h : v > h { return .high }
        return .normal
    }

    /// The normal interval in words: "136–145", "60 or more", "92 or less", "under 300".
    var text: String {
        switch (low, high) {
        case (let l?, let h?): return NumText.short(l) + "–" + NumText.short(h)
        case (let l?, nil): return NumText.short(l) + " or more"
        case (nil, let h?): return highInclusive ? "under " + NumText.short(h) : NumText.short(h) + " or less"
        default: return ""
        }
    }
}

/// One row of the lab catalog.
struct LabTest: Hashable, Identifiable {
    var key: String
    var label: String
    /// The fishbone's and the summary line's name: "Hb", "Plt", "HCO₃".
    var short: String
    var unit: String
    var group: LabGroup
    /// The range for everyone, when it does not differ by sex. Nil with `female` and `male` nil: never flagged by a
    /// fixed range (troponin is read against its assay's 99th percentile).
    var range: LabRange?
    var female: LabRange?
    var male: LabRange?
    /// The most decimals shown; trailing zeros are dropped, as NumText.short does, down to `minimumDecimals`.
    var decimals: Int
    /// The fewest decimals shown, padded with zeros: creatinine "1.00", INR "1.0" (Ben, Nov 3). A value typed with more
    /// decimals keeps them, up to `decimals`.
    var minimumDecimals: Int
    /// Values outside this are almost certainly a typing error (input validation, not a clinical limit).
    var plausible: ClosedRange<Double>
    var note: String?

    var id: String { key }

    init(_ key: String, _ label: String, short: String, unit: String, group: LabGroup, range: LabRange? = nil,
         female: LabRange? = nil, male: LabRange? = nil, decimals: Int, minimumDecimals: Int = 0, plausible: ClosedRange<Double>,
         note: String? = nil) {
        self.key = key
        self.label = label
        self.short = short
        self.unit = unit
        self.group = group
        self.range = range
        self.female = female
        self.male = male
        self.decimals = decimals
        self.minimumDecimals = minimumDecimals
        self.plausible = plausible
        self.note = note
    }

    /// The range for this sex. With the sex unknown and the ranges differing by sex, only a value outside both is
    /// flagged (Hb 12–18 g/dL).
    func reference(for sex: PatientSex?) -> LabRange? {
        switch sex {
        case .female?: return female ?? range
        case .male?: return male ?? range
        case nil:
            guard let f = female, let m = male else { return range ?? female ?? male }
            let low: Double? = (f.low != nil && m.low != nil) ? Swift.min(f.low ?? 0, m.low ?? 0) : nil
            let high: Double? = (f.high != nil && m.high != nil) ? Swift.max(f.high ?? 0, m.high ?? 0) : nil
            return LabRange(low, high)
        }
    }

    /// "12–16" for a woman's hemoglobin; nil when there is no fixed range.
    func rangeText(for sex: PatientSex?) -> String? { reference(for: sex)?.text }

    /// Has a fixed range to flag against.
    var isRated: Bool { range != nil || female != nil || male != nil }

    /// The value for reading: at most `decimals` places, trailing zeros dropped ("9.8", "1.42", "142"), then padded to
    /// `minimumDecimals` ("Cr 1.00", "INR 1.0").
    func format(_ v: Double) -> String { NumText.padded(NumText.short(v, places: decimals), minimumDecimals) }

    /// The existing number-field type, for screens built on it.
    var field: PatientField { PatientField(key, label, unit) }
}

/// One value entered, as the summary shows it.
struct LabValue: Hashable, Identifiable {
    var key: String
    /// The short name ("Hb").
    var label: String
    var value: Double
    /// The value formatted ("9.8").
    var text: String
    var unit: String
    var flag: LabFlag
    /// False when there was nothing to judge it by (a troponin without its assay's 99th percentile).
    var rated: Bool
    var group: LabGroup
    var note: String?
    /// Estimated from the other of hemoglobin and hematocrit (PatientLabs.estimate): shown, never saved, flagged or
    /// read by a rule.
    var estimated = false

    var id: String { key }

    /// "Hb 9.8 L", "K 4.1", "Hct ~29 (est.)".
    var compact: String {
        if estimated { return label + " ~" + text + " (est.)" }
        return label + " " + text + (flag.mark.isEmpty ? "" : " " + flag.mark)
    }
}

/// The classic lab shorthand: CBC (WBC, Hb, Hct, Plt), BMP (Na, K, Cl, HCO₃, BUN, Cr, glucose) and coagulation
/// (INR, fibrinogen). A value not entered is nil, so the drawing can leave its place empty.
struct LabFishbone: Hashable {
    var wbc: LabValue?
    var hb: LabValue?
    var hct: LabValue?
    var plt: LabValue?
    var na: LabValue?
    var k: LabValue?
    var cl: LabValue?
    var hco3: LabValue?
    var bun: LabValue?
    var cr: LabValue?
    var glucose: LabValue?
    var inr: LabValue?
    var fibrinogen: LabValue?
    /// Prothrombin time and aPTT in seconds (1.9); the PT is never flagged.
    var pt: LabValue?
    var ptt: LabValue?
    /// 1.11 (Ben, Nov 9): the hepatic figure (Ca | AST, protein | ALT, albumin | alk phos, bilirubin at the point)
    /// and the two minerals beside it.
    var ca: LabValue?
    var ast: LabValue?
    var alt: LabValue?
    var alp: LabValue?
    var protein: LabValue?
    var albumin: LabValue?
    var tbili: LabValue?
    var mg: LabValue?
    var phos: LabValue?
    /// Hemoglobin or hematocrit estimated from the other, for the cell left empty (LabValue.estimated).
    var estimate: LabValue?

    /// WBC, Hb, Hct, Plt.
    var cbc: [LabValue?] { [wbc, hb, hct, plt] }
    /// Na, Cl, BUN on the top row; K, HCO₃, Cr below; glucose at the end.
    var bmp: [LabValue?] { [na, k, cl, hco3, bun, cr, glucose] }
    var coags: [LabValue?] { [pt, inr, ptt, fibrinogen] }
    /// Ca, protein, albumin down the left; AST, ALT, alk phos down the right; bilirubin at the point.
    var hepatic: [LabValue?] { [ca, protein, albumin, ast, alt, alp, tbili] }
    var minerals: [LabValue?] { [mg, phos] }

    var hasCBC: Bool { cbc.contains { $0 != nil } }
    var hasBMP: Bool { bmp.contains { $0 != nil } }
    var hasCoags: Bool { coags.contains { $0 != nil } }
    var hasHepatic: Bool { hepatic.contains { $0 != nil } }
    var hasMinerals: Bool { minerals.contains { $0 != nil } }
    var isEmpty: Bool { !hasCBC && !hasBMP && !hasCoags && !hasHepatic && !hasMinerals }
}

struct LabSummary: Hashable {
    /// Every value entered, in catalog order. The troponin's 99th percentile is not a patient value, so it is shown
    /// in the troponin's note rather than as an item.
    var items: [LabValue]
    var fishbone: LabFishbone
    /// Hemoglobin or hematocrit estimated from the other when only one was entered; not among the items.
    var estimate: LabValue? = nil

    var abnormal: [LabValue] { items.filter { $0.flag.isAbnormal } }
    var isEmpty: Bool { items.isEmpty }

    /// The items with the estimate in its catalog place (Hct after Hb; Hb before Hct).
    var shown: [LabValue] {
        guard let e = estimate else { return items }
        var out = items
        if e.key == "hct", let i = out.firstIndex(where: { $0.key == "hb" }) { out.insert(e, at: i + 1) }
        else if e.key == "hb", let i = out.firstIndex(where: { $0.key == "hct" }) { out.insert(e, at: i) }
        return out
    }

    /// "Hb 9.8 L · Hct ~29 (est.) · Plt 98 L · INR 1.6 H · Na 131 L": the condensed line, for the handoff and a compact view.
    var line: String { shown.map(\.compact).joined(separator: " · ") }
}

// MARK: - Liver function testing (MELD & CTP)

/// Child-Turcotte-Pugh ascites (1, 2, 3 points).
enum LiverAscites: String, CaseIterable, Codable, Hashable {
    case absent, slight, moderate

    var label: String {
        switch self {
        case .absent: return "None"
        case .slight: return "Slight, or controlled with diuretics"
        case .moderate: return "Moderate to severe"
        }
    }

    var points: Int {
        switch self {
        case .absent: return 1
        case .slight: return 2
        case .moderate: return 3
        }
    }
}

/// Child-Turcotte-Pugh hepatic encephalopathy (1, 2, 3 points).
enum LiverEncephalopathy: String, CaseIterable, Codable, Hashable {
    case absent, grade1to2, grade3to4

    var label: String {
        switch self {
        case .absent: return "None"
        case .grade1to2: return "Grade 1–2, or controlled with medication"
        case .grade3to4: return "Grade 3–4, or refractory"
        }
    }

    var points: Int {
        switch self {
        case .absent: return 1
        case .grade1to2: return 2
        case .grade3to4: return 3
        }
    }
}

enum ChildPughClass: String, Hashable {
    case a = "A", b = "B", c = "C"

    /// A 5–6 points, B 7–9, C 10–15.
    init(points: Int) { self = points <= 6 ? .a : (points <= 9 ? .b : .c) }

    var range: String {
        switch self {
        case .a: return "5–6"
        case .b: return "7–9"
        case .c: return "10–15"
        }
    }
}

/// The Child-Turcotte-Pugh points per component; nil where the input is missing.
struct ChildPughPoints: Hashable {
    var bilirubin: Int?
    var albumin: Int?
    var inr: Int?
    var ascites: Int?
    var encephalopathy: Int?

    var total: Int? {
        guard let b = bilirubin, let a = albumin, let i = inr, let s = ascites, let e = encephalopathy else { return nil }
        return b + a + i + s + e
    }
}

struct LiverInput: Hashable {
    var sex: PatientSex?
    /// Total bilirubin, mg/dL.
    var bilirubin: Double?
    /// mmol/L (the same number as mEq/L).
    var sodium: Double?
    var inr: Double?
    /// mg/dL.
    var creatinine: Double?
    /// g/dL.
    var albumin: Double?
    /// Two or more dialysis treatments, or 24 hours of CVVHD, in the 7 days before the creatinine (OPTN).
    var dialysis: Bool
    var ascites: LiverAscites?
    var encephalopathy: LiverEncephalopathy?
    /// Emergency surgery, for the reading.
    var emergency: Bool

    init(sex: PatientSex? = nil, bilirubin: Double? = nil, sodium: Double? = nil, inr: Double? = nil, creatinine: Double? = nil,
         albumin: Double? = nil, dialysis: Bool = false, ascites: LiverAscites? = nil, encephalopathy: LiverEncephalopathy? = nil,
         emergency: Bool = false) {
        self.sex = sex
        self.bilirubin = bilirubin
        self.sodium = sodium
        self.inr = inr
        self.creatinine = creatinine
        self.albumin = albumin
        self.dialysis = dialysis
        self.ascites = ascites
        self.encephalopathy = encephalopathy
        self.emergency = emergency
    }

    /// The record's sex, labs ("tbili", "na", "inr", "cr", "albumin") and urgency; dialysis, ascites and
    /// encephalopathy are asked on the calculator.
    init(record r: PatientRecord, dialysis: Bool = false, ascites: LiverAscites? = nil, encephalopathy: LiverEncephalopathy? = nil) {
        self.init(sex: r.sex, bilirubin: r.labs["tbili"], sodium: r.labs["na"], inr: r.labs["inr"], creatinine: r.labs["cr"],
                  albumin: r.labs["albumin"], dialysis: dialysis, ascites: ascites, encephalopathy: encephalopathy,
                  emergency: r.urgency == .emergency)
    }
}

struct LiverResult: Hashable {
    /// MELD 3.0 as the OPTN allocates with it: rounded to the nearest whole number, 6 to 40.
    var meld3: Int? = nil
    /// MELD 3.0 after the input bounds, before rounding and the 6–40 limits.
    var meld3Exact: Double? = nil
    /// MELD-Na as the OPTN calculated it from 2016 until July 2023: rounded, at most 40.
    var meldNa: Int? = nil
    /// The policy's initial MELD(i), rounded to the tenth and multiplied by 10; sodium is added only above 11.
    var meldInitial: Int? = nil
    var childPugh: Int? = nil
    var childPughClass: ChildPughClass? = nil
    var points = ChildPughPoints()
    var missingMeld3: [String] = []
    var missingMeldNa: [String] = []
    var missingChildPugh: [String] = []
    /// The bounds that changed an input or a score ("Creatinine over 3.0 counted as 3.0 for MELD 3.0.").
    var adjustments: [String] = []
    /// One or two sentences each, with their sources.
    var interpretation: [String] = []

    /// Every input still missing for any of the three scores, in the calculator's order.
    var missing: [String] {
        let all = Set(missingMeld3 + missingMeldNa + missingChildPugh)
        return PatientLabs.liverFields.filter { all.contains($0) }
    }
}

// MARK: - Right heart catheterization

struct RightHeartInput: Hashable {
    /// Right atrial pressure, mmHg.
    var ra: Double?
    /// PA systolic and diastolic, mmHg.
    var pasp: Double?
    var padp: Double?
    /// Measured PA mean, mmHg; without it the mean is estimated.
    var mpap: Double?
    /// Wedge pressure (PAWP in the ESC/ERS guideline), mmHg.
    var pcwp: Double?
    /// Cardiac output, L/min.
    var co: Double?
    /// Body surface area, m², for the indexed values.
    var bsa: Double?

    init(ra: Double? = nil, pasp: Double? = nil, padp: Double? = nil, mpap: Double? = nil, pcwp: Double? = nil,
         co: Double? = nil, bsa: Double? = nil) {
        self.ra = ra
        self.pasp = pasp
        self.padp = padp
        self.mpap = mpap
        self.pcwp = pcwp
        self.co = co
        self.bsa = bsa
    }
}

/// The haemodynamic definitions of the 2022 ESC/ERS guideline (Table 5; "unclassified PH" in its text).
enum PHHemodynamics: String, Hashable {
    case noPH, preCapillary, isolatedPostCapillary, combined, unclassified

    var label: String {
        switch self {
        case .noPH: return "No pulmonary hypertension at rest"
        case .preCapillary: return "Pre-capillary pulmonary hypertension"
        case .isolatedPostCapillary: return "Isolated post-capillary pulmonary hypertension"
        case .combined: return "Combined post- and pre-capillary pulmonary hypertension"
        case .unclassified: return "Unclassified pulmonary hypertension"
        }
    }

    var short: String {
        switch self {
        case .noPH: return "No PH"
        case .preCapillary: return "Pre-capillary PH"
        case .isolatedPostCapillary: return "IpcPH"
        case .combined: return "CpcPH"
        case .unclassified: return "Unclassified PH"
        }
    }

    var criteria: String {
        switch self {
        case .noPH: return "mPAP 20 mmHg or less"
        case .preCapillary: return "mPAP over 20 mmHg, PAWP 15 mmHg or less, PVR over 2 WU"
        case .isolatedPostCapillary: return "mPAP over 20 mmHg, PAWP over 15 mmHg, PVR 2 WU or less"
        case .combined: return "mPAP over 20 mmHg, PAWP over 15 mmHg, PVR over 2 WU"
        case .unclassified: return "mPAP over 20 mmHg, PAWP 15 mmHg or less, PVR 2 WU or less"
        }
    }

    var isPH: Bool { self != .noPH }
}

/// A published PAPI cut-off, with the patients it was derived in.
struct PAPIThreshold: Hashable, Identifiable {
    var id: String
    var cutoff: Double
    /// True: at or below the cut-off counts; false: below it.
    var inclusive: Bool
    var context: String
    var finding: String
    var citation: String

    func applies(_ papi: Double) -> Bool { inclusive ? papi <= cutoff : papi < cutoff }

    /// "Acute inferior MI from proximal RCA occlusion: PAPI 0.9 or less ... (Korabathina 2012)."
    var text: String { context + ": " + finding + " (" + citation + ")." }
}

struct RightHeartResult: Hashable {
    /// mmHg: measured, or (PASP + 2 × PADP) / 3.
    var mpap: Double? = nil
    var mpapEstimated = false
    /// Transpulmonary gradient, mPAP − PCWP, mmHg.
    var tpg: Double? = nil
    /// Diastolic pressure gradient, PADP − PCWP, mmHg.
    var dpg: Double? = nil
    /// Wood units, TPG / CO.
    var pvr: Double? = nil
    /// (PASP − PADP) / RA.
    var papi: Double? = nil
    /// L/min/m².
    var ci: Double? = nil
    /// WU·m², PVR × BSA (the same as TPG / CI).
    var pvri: Double? = nil
    var ph: PHHemodynamics? = nil
    /// "Combined post- and pre-capillary pulmonary hypertension: mPAP over 20 mmHg, ... (2022 ESC/ERS)."
    var phText: String? = nil
    /// The published PAPI cut-offs this value falls under.
    var papiBelow: [PAPIThreshold] = []
    var notes: [String] = []
    /// Inputs still needed for the rest of the results (BSA, for the indexed values, is optional and not listed).
    var missing: [String] = []
}

// MARK: - The arithmetic

enum PatientLabs {
    // MARK: Catalog

    static let catalog: [LabTest] = [
        // Main. Fibrinogen follows INR and GFR follows creatinine, the order the screen lists them in.
        LabTest("hb", "Hemoglobin", short: "Hb", unit: "g/dL", group: .main,
                female: LabRange(12, 16), male: LabRange(14, 18), decimals: 1, plausible: 1...25),
        LabTest("hct", "Hematocrit", short: "Hct", unit: "%", group: .main,
                female: LabRange(37, 47), male: LabRange(42, 50), decimals: 1, plausible: 5...75),
        // ABIM: 4000–11,000/µL.
        LabTest("wbc", "White cell count", short: "WBC", unit: "×10³/µL", group: .main,
                range: LabRange(4.0, 11.0), decimals: 1, plausible: 0.1...500),
        // ABIM: 150,000–450,000/µL.
        LabTest("plt", "Platelets", short: "Plt", unit: "×10³/µL", group: .main,
                range: LabRange(150, 450), decimals: 0, plausible: 1...3000),
        // 1.9: the prothrombin time and the aPTT, for the coagulation cells of the preprocedure summary and the handoff.
        // The PT has NO reference range here: its seconds depend on the laboratory's reagent and instrument (the reason
        // the INR exists), so any fixed range would flag normal results of another laboratory. Read it against the range
        // on the report. The aPTT is the intraoperative set's own entry (ABIM, 25–35 s).
        LabTest("pt", "Prothrombin time", short: "PT", unit: "s", group: .main, decimals: 1, plausible: 5...300,
                note: "Not flagged: the PT in seconds depends on the laboratory's reagent and instrument. Read it against the range on the report, or use the INR."),
        LabTest("inr", "INR", short: "INR", unit: "", group: .main,
                range: LabRange(0.8, 1.1), decimals: 2, minimumDecimals: 1, plausible: 0.5...20,
                note: "Range without anticoagulants (MedlinePlus)."),
        IntraopLabs.ptt,
        LabTest("fibrinogen", "Fibrinogen", short: "Fib", unit: "mg/dL", group: .main,
                range: LabRange(200, 400), decimals: 0, plausible: 10...2000),
        LabTest("na", "Sodium", short: "Na", unit: "mmol/L", group: .main,
                range: LabRange(136, 145), decimals: 0, plausible: 90...200),
        LabTest("k", "Potassium", short: "K", unit: "mmol/L", group: .main,
                range: LabRange(3.5, 5.0), decimals: 1, plausible: 1...12),
        LabTest("cl", "Chloride", short: "Cl", unit: "mmol/L", group: .main,
                range: LabRange(98, 106), decimals: 0, plausible: 50...160),
        LabTest("hco3", "Bicarbonate", short: "HCO₃", unit: "mmol/L", group: .main,
                range: LabRange(23, 28), decimals: 0, plausible: 1...60),
        LabTest("bun", "BUN", short: "BUN", unit: "mg/dL", group: .main,
                range: LabRange(8, 20), decimals: 0, plausible: 1...300),
        LabTest("cr", "Creatinine", short: "Cr", unit: "mg/dL", group: .main,
                female: LabRange(0.5, 1.1), male: LabRange(0.7, 1.3), decimals: 3, minimumDecimals: 2,
                plausible: 0.1...30),
        // KDIGO's decreased GFR is under 60 (with more than 3 months, a CKD criterion); no upper limit is flagged.
        LabTest("gfr", "GFR", short: "GFR", unit: "mL/min/1.73 m²", group: .main,
                range: LabRange(60, nil), decimals: 0, plausible: 1...200,
                note: "Under 60 is decreased GFR (KDIGO); for more than 3 months it meets the CKD criterion."),
        LabTest("glucose", "Glucose", short: "Glu", unit: "mg/dL", group: .main,
                range: LabRange(70, 180), decimals: 0, plausible: 10...3000,
                note: "Perioperative range: high above 180 mg/dL (ADA Standards of Care, Diabetes Care in the Hospital: 100–180 mg/dL within 4 h of surgery); low below 70 (hypoglycemia). The fasting reference range is 70–99."),
        LabTest("a1c", "HbA1c", short: "HbA1c", unit: "%", group: .main,
                range: LabRange(4.0, 5.6), decimals: 1, plausible: 3...25),
        LabTest("albumin", "Albumin", short: "Alb", unit: "g/dL", group: .main,
                range: LabRange(3.5, 5.5), decimals: 1, plausible: 0.5...7),
        // ABIM 0.3–1.0; a low bilirubin means nothing, so only a high one is flagged.
        LabTest("tbili", "Total bilirubin", short: "T bili", unit: "mg/dL", group: .main,
                range: LabRange(nil, 1.0), decimals: 1, plausible: 0.1...80),
        // 1.11 (Ben, Nov 9, the hepatic fishbone and the minerals beside it). ABIM Laboratory Test Reference Ranges,
        // January 2026: calcium, serum 8.6–10.2 mg/dL; protein, total, serum 5.5–9.0 g/dL; magnesium, serum 1.6–2.6
        // mg/dL; phosphorus, inorganic, serum 3.0–4.5 mg/dL (the 2.5–4.5 of the general textbooks and MedlinePlus is
        // not used: the whole catalog follows the ABIM list). Total calcium, as the chemistry panel reports it (the
        // ionized calcium is the blood gas's own entry, IntraopLabs "ica").
        LabTest("ca", "Calcium", short: "Ca", unit: "mg/dL", group: .main,
                range: LabRange(8.6, 10.2), decimals: 1, plausible: 3...20,
                note: "Total serum calcium; the ionized calcium is on the blood gas."),
        LabTest("protein", "Total protein", short: "Prot", unit: "g/dL", group: .main,
                range: LabRange(5.5, 9.0), decimals: 1, plausible: 1...15),
        LabTest("mg", "Magnesium", short: "Mg", unit: "mg/dL", group: .main,
                range: LabRange(1.6, 2.6), decimals: 1, plausible: 0.2...15),
        LabTest("phos", "Phosphorus", short: "PO₄", unit: "mg/dL", group: .main,
                range: LabRange(3.0, 4.5), decimals: 1, plausible: 0.2...30),

        // Cardiac, behind the add button: the 2024 AHA/ACC thresholds (Figure 1, footnote §).
        LabTest("bnp", "BNP", short: "BNP", unit: "pg/mL", group: .cardiac,
                range: LabRange(nil, 92), decimals: 0, plausible: 0...50000,
                note: "Abnormal over 92 pg/mL before noncardiac surgery (2024 AHA/ACC)."),
        LabTest("ntprobnp", "NT-proBNP", short: "NT-proBNP", unit: "pg/mL", group: .cardiac,
                range: LabRange(nil, 300, highInclusive: true), decimals: 0, plausible: 0...100000,
                note: "Abnormal at 300 pg/mL or more before noncardiac surgery (2024 AHA/ACC)."),
        LabTest("troponin", "Troponin", short: "Troponin", unit: "ng/L", group: .cardiac,
                decimals: 1, plausible: 0...1000000,
                note: "Abnormal above the assay's 99th percentile, so it is flagged only with that percentile recorded."),
        LabTest("troponin99", "Troponin, assay's 99th percentile", short: "99th percentile", unit: "ng/L", group: .cardiac,
                decimals: 1, plausible: 1...1000),

        // Liver. ABIM 10–40 U/L for AST and ALT; only a high value is flagged.
        LabTest("ast", "AST", short: "AST", unit: "U/L", group: .liver,
                range: LabRange(nil, 40), decimals: 0, plausible: 1...30000),
        LabTest("alt", "ALT", short: "ALT", unit: "U/L", group: .liver,
                range: LabRange(nil, 40), decimals: 0, plausible: 1...30000),
        LabTest("alp", "Alkaline phosphatase", short: "Alk phos", unit: "U/L", group: .liver,
                range: LabRange(30, 120), decimals: 0, plausible: 5...5000),

        // Thyroid.
        LabTest("tsh", "TSH", short: "TSH", unit: "mIU/L", group: .thyroid,
                range: LabRange(0.5, 4.0), decimals: 2, plausible: 0.001...500),
        LabTest("ft4", "Free T4", short: "Free T4", unit: "ng/dL", group: .thyroid,
                range: LabRange(0.8, 1.8), decimals: 2, plausible: 0.05...15),
        LabTest("ft3", "Free T3", short: "Free T3", unit: "pg/mL", group: .thyroid,
                range: LabRange(2.3, 4.2), decimals: 1, plausible: 0.5...50),

        // Lactate (1.8.3), last on the labs line and at the foot of the main labs: the intraoperative gas's own entry
        // (unit, range and source note), named without "arterial" because a preoperative sample may be venous.
        LabTest("lactate", "Lactate", short: IntraopLabs.lactate.short, unit: IntraopLabs.lactate.unit, group: .main,
                range: IntraopLabs.lactate.range, decimals: IntraopLabs.lactate.decimals, plausible: IntraopLabs.lactate.plausible,
                note: IntraopLabs.lactate.note),
    ]

    /// The catalog and the intraoperative tests (IntraopLabs.added), which the preoperative screens do not list.
    /// Lactate is in both: the catalog's entry (named "Lactate") wins here; IntraopLabs.tests keeps "Lactate, arterial".
    private static let byKey: [String: LabTest] = {
        var out = Dictionary(uniqueKeysWithValues: catalog.map { ($0.key, $0) })
        for t in IntraopLabs.added where out[t.key] == nil { out[t.key] = t }
        return out
    }()

    static func test(_ key: String) -> LabTest? { byKey[key] }

    static func tests(_ group: LabGroup) -> [LabTest] { catalog.filter { $0.group == group } }

    /// The CBC (WBC, Hb, Hct, Plt) and the BMP (Na, K, Cl, HCO₃, BUN, Cr, glucose) as the fishbone groups them.
    static let fishboneOrder = ["wbc", "hb", "hct", "plt", "na", "k", "cl", "hco3", "bun", "cr", "glucose"]

    // MARK: The fishbone slots (1.11, Ben's note 1: labs are typed into the fishbone)

    /// The hepatic figure's slots in the order Next walks them: down the left column (Ca, protein, albumin), down the
    /// right (AST, ALT, alk phos), then the bilirubin at the point; the same column-wise order as the BMP's.
    static let hepaticOrder = ["ca", "protein", "albumin", "ast", "alt", "alp", "tbili"]
    /// Magnesium and phosphorus, beside the hepatic figure.
    static let mineralOrder = ["mg", "phos"]
    /// The main labs without a place on Ben's figures, as a row of plain slots after them.
    static let otherSlotOrder = ["gfr", "a1c", "lactate"]

    /// Every slot on the Labs page, in the order Next walks the figures: the BMP column by column (Na, K; Cl, HCO₃;
    /// BUN, Cr; glucose at the point), the CBC (WBC, Hb, Hct, Plt), the coagulation figure (PT, PTT, INR at the point,
    /// then fibrinogen), the hepatic figure, Mg and PO₄, then GFR, HbA1c and lactate. Every main lab has one slot.
    static let slotOrder = ["na", "k", "cl", "hco3", "bun", "cr", "glucose", "wbc", "hb", "hct", "plt", "pt", "ptt", "inr", "fibrinogen"]
        + hepaticOrder + mineralOrder + otherSlotOrder

    /// The keys drawn on a figure (the page's and the brief's): the summary's other values are listed as a line.
    static let figureKeys = Set(slotOrder)

    /// The faint hint inside an empty slot: the catalog's reference range for this sex ("136–145"), the range the
    /// value is flagged against; nil where the catalog has none (the PT, read against the report's own range).
    /// Q20 (Ben, Nov 9): the app's sourced ranges stay; Ben's drawn textbook ranges appear only where they agree with
    /// the catalog, which is what showing the catalog's range does. Where his drawing differs the catalog wins: Na
    /// 136–145 (drawn 135–145), Cl 98–106 (95–105), HCO₃ 23–28 (22–28), BUN 8–20 (7–18), Cr by sex (0.6–1.2),
    /// glucose 70–180 perioperative (70–115), WBC 4.0–11.0 (4.5–11), Hb 14–18 M (13.5–17.5), Hct 42–50 M / 37–47 F
    /// (39–49 / 35–45), PT unflagged (11–13.5), Ca 8.6–10.2 (8.4–10.2), AST and ALT 40 or less (0–35), protein
    /// 5.5–9.0 (6–8), albumin 3.5–5.5 (4–6), Mg 1.6–2.6 (1.5–2.5), PO₄ 3.0–4.5 (3.5–4.5), pH 7.38–7.44 (7.35–7.45),
    /// PaCO₂ 38–42 (35–45), PaO₂ 75 or more (80–100), arterial HCO₃ 23–26 (22–28). They agree on K, Plt, PTT, INR,
    /// alk phos and bilirubin.
    static func slotHint(_ key: String, sex: PatientSex?) -> String? { test(key)?.rangeText(for: sex) }

    /// The group as the Labs editor lists it, which is the order Next walks: the main labs start with the fishbone's
    /// CBC and BMP, then the rest in catalog order; the other groups keep the catalog's order.
    static func entryOrder(_ group: LabGroup) -> [LabTest] {
        let all = tests(group)
        guard group == .main else { return all }
        let first = fishboneOrder.compactMap { k in all.first { $0.key == k } }
        return first + all.filter { !fishboneOrder.contains($0.key) }
    }

    /// Something entered in the group, so its section opens without the add button.
    static func entered(_ group: LabGroup, in labs: [String: Double]) -> Bool { tests(group).contains { labs[$0.key] != nil } }

    /// A number that could be real: finite and inside the entry's plausible range (unknown keys pass).
    static func isPlausible(_ key: String, _ value: Double) -> Bool {
        guard value.isFinite else { return false }
        return test(key)?.plausible.contains(value) ?? true
    }

    // MARK: Flags

    /// Normal, low or high against the adult reference range (the sex's, where it differs). A troponin is read
    /// against its assay's 99th percentile, so without `troponin99` it is not flagged.
    static func flag(_ key: String, _ value: Double, sex: PatientSex?, troponin99: Double? = nil) -> LabFlag {
        guard value.isFinite else { return .normal }
        if key == "troponin" {
            guard let p = troponin99, p.isFinite, p > 0 else { return .normal }
            return value > p ? .high : .normal
        }
        return test(key)?.reference(for: sex)?.flag(value) ?? .normal
    }

    // MARK: Summary

    static func summary(_ r: PatientRecord) -> LabSummary { summary(r.labs, sex: r.sex) }

    static func summary(_ labs: [String: Double], sex: PatientSex?) -> LabSummary {
        let p99: Double? = labs["troponin99"].flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        var items: [LabValue] = []
        for t in catalog where t.key != "troponin99" {
            guard let v = labs[t.key], v.isFinite else { continue }
            var rated = t.isRated
            var note: String? = nil
            if t.key == "troponin" {
                rated = p99 != nil
                if let p = p99 {
                    note = "assay's 99th percentile " + NumText.short(p, places: 1) + " ng/L"
                } else {
                    note = "not flagged without the assay's 99th percentile"
                }
            }
            items.append(LabValue(key: t.key, label: t.short, value: v, text: t.format(v), unit: t.unit,
                                  flag: flag(t.key, v, sex: sex, troponin99: p99), rated: rated, group: t.group, note: note))
        }
        func cell(_ k: String) -> LabValue? { items.first { $0.key == k } }
        var fb = LabFishbone()
        fb.wbc = cell("wbc")
        fb.hb = cell("hb")
        fb.hct = cell("hct")
        fb.plt = cell("plt")
        fb.na = cell("na")
        fb.k = cell("k")
        fb.cl = cell("cl")
        fb.hco3 = cell("hco3")
        fb.bun = cell("bun")
        fb.cr = cell("cr")
        fb.glucose = cell("glucose")
        fb.inr = cell("inr")
        fb.fibrinogen = cell("fibrinogen")
        fb.pt = cell("pt")
        fb.ptt = cell("ptt")
        fb.ca = cell("ca")
        fb.ast = cell("ast")
        fb.alt = cell("alt")
        fb.alp = cell("alp")
        fb.protein = cell("protein")
        fb.albumin = cell("albumin")
        fb.tbili = cell("tbili")
        fb.mg = cell("mg")
        fb.phos = cell("phos")
        let est = estimate(labs)
        fb.estimate = est
        return LabSummary(items: items, fishbone: fb, estimate: est)
    }

    // MARK: Hemoglobin and hematocrit, one from the other

    // Hct (%) ≈ 3 × Hb (g/dL), and Hb ≈ Hct ÷ 3 (Ben, Nov 3: "HCT and hb can be calculated from either variable").
    // By definition MCHC = Hb ÷ Hct × 100, so Hct ÷ Hb = 100 ÷ MCHC: the ratio is about 3 when the MCHC is about
    // 33 g/dL (arithmetic, not a finding of the papers below). The threefold rule held in a pooled malaria cohort:
    // Lee SJ, Stepniewska K, Anstey N, et al. The relationship between the haemoglobin concentration and the haematocrit
    // in Plasmodium falciparum malaria. Malar J 2008;7:149 (doi:10.1186/1475-2875-7-149; PMID 18673575): 3,254 paired
    // measurements from 1,810 patients pooled from 85 antimalarial drug trials, best fit Hct = 5.62 + 2.60 × Hb, and
    // "the commonly used threefold conversion is also valid" (abstract). Its limits: Quintó L, Aponte JJ, Menéndez C,
    // et al. Trop Med Int Health 2006;11:1295–1302 (doi:10.1111/j.1365-3156.2006.01679.x; PMID 16903892): in young
    // children the ratio differed from 3 and varied with age, tending to 3, too loose to derive one from the other for
    // defining anemia. So the estimate is only shown, marked as such: never saved, never in place of a measured value,
    // never flagged and never read by a rule (the anemia rule reads the measured Hb).
    static let estimateCaption = "Estimated as Hct ≈ 3 × Hb (Hb ≈ Hct ÷ 3). Hct ÷ Hb = 100 ÷ MCHC, so the ratio is about 3 when MCHC is about 33 g/dL; the threefold rule held in a pooled malaria cohort (Lee SJ et al., Malar J 2008). Only measured values are saved."

    /// The other of hemoglobin and hematocrit when only one is entered: Hct to the whole %, Hb to 0.1 g/dL.
    static func estimate(_ labs: [String: Double]) -> LabValue? {
        func valid(_ k: String) -> Double? { labs[k].flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
        let hb = valid("hb"), hct = valid("hct")
        if let b = hb, hct == nil, let t = test("hct") {
            let v = (3 * b).rounded()
            return LabValue(key: "hct", label: t.short, value: v, text: NumText.short(v, places: 0), unit: t.unit, flag: .normal,
                            rated: false, group: t.group, note: nil, estimated: true)
        }
        if let h = hct, hb == nil, let t = test("hb") {
            let v = (h / 3 * 10).rounded() / 10
            return LabValue(key: "hb", label: t.short, value: v, text: NumText.short(v, places: 1), unit: t.unit, flag: .normal,
                            rated: false, group: t.group, note: nil, estimated: true)
        }
        return nil
    }

    // MARK: MELD 3.0

    // Kim WR, Mannalithara A, Heimbach JK, et al. MELD 3.0: the Model for End-Stage Liver Disease updated for the
    // modern era. Gastroenterology 2021;161:1887–1895.e4 (doi:10.1053/j.gastro.2021.08.050; PMID 34481845), as the
    // OPTN adopted it (Policy 9.1.D; "Improving Liver Allocation: MELD, PELD, Status 1A, Status 1B", board approved
    // June 27, 2022), the adult formula (18 or older at registration):
    //   1.33 (if female) + 4.56 ln(bilirubin) + 0.82 (137 − Na) − 0.24 (137 − Na) ln(bilirubin) + 9.09 ln(INR)
    //   + 11.14 ln(creatinine) + 1.85 (3.5 − albumin) − 1.83 (3.5 − albumin) ln(creatinine) + 6.
    // Bilirubin, INR and creatinine under 1.0 count as 1.0; sodium is bounded to 125–137 mmol/L and albumin to
    // 1.5–3.5 g/dL; creatinine over 3.0 mg/dL, two or more dialysis treatments or 24 hours of CVVHD in the 7 days
    // before the creatinine count as 3.0. The score is rounded to the nearest whole number; the minimum is 6 and the
    // maximum 40 (the paper itself set no cap of 40).

    static func meld3(sex: PatientSex, bilirubin: Double, sodium: Double, inr: Double, creatinine: Double, albumin: Double,
                      dialysis: Bool) -> (exact: Double, score: Int) {
        let b = Swift.max(bilirubin, 1)
        let i = Swift.max(inr, 1)
        let c = dialysis ? 3.0 : clamp(creatinine, 1, 3)
        let n = clamp(sodium, 125, 137)
        let a = clamp(albumin, 1.5, 3.5)
        let lnB = log(b)
        let lnC = log(c)
        let dNa: Double = 137 - n
        let dAlb: Double = 3.5 - a
        var s: Double = 6
        if sex == .female { s += 1.33 }
        s += 4.56 * lnB
        s += 0.82 * dNa
        s -= 0.24 * dNa * lnB
        s += 9.09 * log(i)
        s += 11.14 * lnC
        s += 1.85 * dAlb
        s -= 1.83 * dAlb * lnC
        let score = Swift.min(Swift.max(Int(s.rounded()), 6), 40)
        return (s, score)
    }

    // MARK: MELD-Na

    // The OPTN formula used for allocation from January 2016 until MELD 3.0 (Policy 9.1.D as it stood before the 2022
    // change; the board adopted the sodium term on November 11, 2013, with a worked example: creatinine 1.9,
    // bilirubin 4.2, INR 1.2, sodium 127 gives MELD(i) 20 and MELD 27):
    //   MELD(i) = 0.957 ln(creatinine) + 0.378 ln(bilirubin) + 1.120 ln(INR) + 0.643, rounded to the tenth decimal
    //   place and multiplied by 10; for an initial MELD over 11,
    //   MELD = MELD(i) + 1.32 (137 − Na) − 0.033 MELD(i) (137 − Na).
    // Values under 1.0 count as 1.0; creatinine over 4.0 mg/dL, two or more dialysis treatments or 24 hours of CVVHD in
    // the prior 7 days count as 4.0; sodium is bounded to 125–137 mmol/L; the maximum is 40. The result is rounded to
    // the nearest whole number (Kim 2021).

    static func meldNa(bilirubin: Double, sodium: Double, inr: Double, creatinine: Double,
                       dialysis: Bool) -> (initial: Int, exact: Double, score: Int) {
        let b = Swift.max(bilirubin, 1)
        let i = Swift.max(inr, 1)
        let c = dialysis ? 4.0 : clamp(creatinine, 1, 4)
        var raw: Double = 0.643
        raw += 0.957 * log(c)
        raw += 0.378 * log(b)
        raw += 1.120 * log(i)
        let initial = Int((raw * 10).rounded())
        guard initial > 11 else { return (initial, Double(initial), Swift.min(initial, 40)) }
        let m = Double(initial)
        let d: Double = 137 - clamp(sodium, 125, 137)
        let value = m + 1.32 * d - 0.033 * m * d
        return (initial, value, Swift.min(Int(value.rounded()), 40))
    }

    // MARK: Child-Turcotte-Pugh

    // Pugh RN, Murray-Lyon IM, Dawson JL, et al. Br J Surg 1973;60:646–649 (doi:10.1002/bjs.1800600817; PMID 4541913).
    // Bilirubin under 2, 2–3, over 3 mg/dL and albumin over 3.5, 2.8–3.5, under 2.8 g/dL as the FDA's guidance on
    // pharmacokinetics in hepatic impairment reproduces the table (May 2003, appendix); the INR in place of the
    // prothrombin time, under 1.7, 1.7–2.3, over 2.3, and the wording of the ascites and encephalopathy grades, from
    // the AASLD-IDSA HCV Guidance, Table 4 (updated January 5, 2025). Class A 5–6, B 7–9, C 10–15.

    static func childPughPoints(bilirubin: Double?, albumin: Double?, inr: Double?, ascites: LiverAscites?,
                                encephalopathy: LiverEncephalopathy?) -> ChildPughPoints {
        var p = ChildPughPoints()
        if let v = bilirubin, v.isFinite { p.bilirubin = v < 2 ? 1 : (v <= 3 ? 2 : 3) }
        if let v = albumin, v.isFinite { p.albumin = v > 3.5 ? 1 : (v >= 2.8 ? 2 : 3) }
        if let v = inr, v.isFinite { p.inr = v < 1.7 ? 1 : (v <= 2.3 ? 2 : 3) }
        p.ascites = ascites?.points
        p.encephalopathy = encephalopathy?.points
        return p
    }

    // MARK: Liver: all three, with the reading

    /// The names `missing` uses, in the calculator's order.
    static let liverFields = ["sex", "bilirubin", "sodium", "INR", "creatinine", "albumin", "ascites", "encephalopathy"]

    // The reading. Each sentence's numbers were checked against the source named in it:
    // Mansour A, Watson W, Shayani V, Pickleman J. Surgery 1997;122:730–735 (doi:10.1016/s0039-6060(97)90080-5;
    //   PMID 9347849): 92 abdominal operations in cirrhosis; mortality 10% in Child class A, 30% in B, 82% in C; 50%
    //   after emergent and 18% after elective operations (abstract).
    // Teh SH, Nagorney DM, Stevens SR, et al. Gastroenterology 2007;132:1261–1269 (doi:10.1053/j.gastro.2007.01.040;
    //   PMID 17408652): 772 major digestive, orthopedic or cardiovascular operations; 30-day mortality from 5.7% (MELD
    //   under 8) to more than 50% (over 20); MELD, ASA class and age predicted mortality independently of the type of
    //   surgery (abstract). That was the MELD of the time; MELD 3.0 was rescaled so that a number means a similar risk
    //   (Kim 2021).
    // Abbas N, Fallowfield J, Patch D, et al. (BSG and BASL) Frontline Gastroenterol 2023;14:359–370
    //   (doi:10.1136/flgastro-2023-102381; PMID 37581186): risk highest in CTP B and C; deferring elective surgery until
    //   after transplantation, particularly in decompensated cirrhosis; CTP and MELD can overestimate surgical risk
    //   (full text).
    // Mahmud N, Fricker ZP, McElroy LM, et al. ACG Clinical Guideline: Perioperative Risk Assessment and Management in
    //   Patients With Cirrhosis. Am J Gastroenterol 2025;120:1968–1984 (doi:10.14309/ajg.0000000000003616; PMID
    //   40899690): emphasis on cirrhosis-specific calculators such as VOCAL-Penn (abstract).
    // Mahmud N, Fricker Z, Hubbard RA, et al. Hepatology 2021;73:204–218 (doi:10.1002/hep.31558; PMID 32939786):
    //   VOCAL-Penn's predictors, and better discrimination and calibration than MELD, MELD-Na, CTP and the Mayo risk
    //   score (abstract).

    static let ctpReading = "In a classic series of abdominal operations in cirrhosis, mortality was 10% in class A, 30% in class B and 82% in class C (Mansour 1997)."
    static let meldReading = "After major digestive, orthopedic or cardiovascular surgery in cirrhosis, 30-day mortality ranged from 5.7% with a MELD under 8 to over 50% with a MELD over 20, and MELD, ASA class and age predicted it whatever the operation (Teh 2007)."
    static let decompensatedReading = "Risk is highest in CTP class B and C; with decompensated cirrhosis, consider deferring elective surgery until after liver transplantation where applicable, after multidisciplinary review (BSG/BASL 2023)."
    static let emergencyReading = "Emergency surgery adds risk: in a classic series of abdominal operations in cirrhosis, mortality was 50% after emergency and 18% after elective operations (Mansour 1997)."
    static let calculatorReading = "CTP and MELD can overestimate surgical risk (BSG/BASL 2023), and the 2025 ACG guideline emphasizes cirrhosis-specific calculators such as VOCAL-Penn. VOCAL-Penn uses age, albumin, bilirubin, platelets, surgery type, emergency, fatty liver disease, ASA class and obesity, and predicted postoperative mortality better than MELD, MELD-Na, CTP or the Mayo risk score (Mahmud 2021)."

    static func liver(_ x: LiverInput) -> LiverResult {
        func given(_ v: Double?) -> Double? { v.flatMap { $0.isFinite ? $0 : nil } }
        let bili = given(x.bilirubin), na = given(x.sodium), inr = given(x.inr), cr = given(x.creatinine), alb = given(x.albumin)
        var r = LiverResult()

        var m3: [String] = []
        if x.sex == nil { m3.append("sex") }
        if bili == nil { m3.append("bilirubin") }
        if na == nil { m3.append("sodium") }
        if inr == nil { m3.append("INR") }
        if cr == nil && !x.dialysis { m3.append("creatinine") }
        if alb == nil { m3.append("albumin") }
        r.missingMeld3 = m3
        if m3.isEmpty, let s = x.sex, let b = bili, let n = na, let i = inr, let a = alb {
            let m = meld3(sex: s, bilirubin: b, sodium: n, inr: i, creatinine: cr ?? 3, albumin: a, dialysis: x.dialysis)
            r.meld3 = m.score
            r.meld3Exact = m.exact
            if m.exact > 40 { r.adjustments.append("MELD 3.0 over 40 is reported as 40, the OPTN maximum.") }
        }

        var mNa: [String] = []
        if bili == nil { mNa.append("bilirubin") }
        if na == nil { mNa.append("sodium") }
        if inr == nil { mNa.append("INR") }
        if cr == nil && !x.dialysis { mNa.append("creatinine") }
        r.missingMeldNa = mNa
        if mNa.isEmpty, let b = bili, let n = na, let i = inr {
            let m = meldNa(bilirubin: b, sodium: n, inr: i, creatinine: cr ?? 4, dialysis: x.dialysis)
            r.meldNa = m.score
            r.meldInitial = m.initial
            if m.exact > 40 { r.adjustments.append("MELD-Na over 40 is reported as 40, the OPTN maximum.") }
        }

        r.points = childPughPoints(bilirubin: bili, albumin: alb, inr: inr, ascites: x.ascites, encephalopathy: x.encephalopathy)
        var mCtp: [String] = []
        if r.points.bilirubin == nil { mCtp.append("bilirubin") }
        if r.points.inr == nil { mCtp.append("INR") }
        if r.points.albumin == nil { mCtp.append("albumin") }
        if r.points.ascites == nil { mCtp.append("ascites") }
        if r.points.encephalopathy == nil { mCtp.append("encephalopathy") }
        r.missingChildPugh = mCtp
        if let t = r.points.total {
            r.childPugh = t
            r.childPughClass = ChildPughClass(points: t)
        }

        // The bounds worth saying aloud; the routine ones (a normal sodium or albumin above the cap, values under 1.0)
        // are not listed.
        if x.dialysis {
            r.adjustments.insert("Dialysis: creatinine counted as 3.0 for MELD 3.0 and 4.0 for MELD-Na.", at: 0)
        } else if let c = cr, c > 3 {
            r.adjustments.insert(c > 4 ? "Creatinine counted as 3.0 for MELD 3.0 and 4.0 for MELD-Na, their caps." : "Creatinine over 3.0 counted as 3.0 for MELD 3.0.", at: 0)
        }
        if let n = na, n < 125 { r.adjustments.append("Sodium under 125 counted as 125.") }
        if let a = alb, a < 1.5 { r.adjustments.append("Albumin under 1.5 counted as 1.5 for MELD 3.0.") }

        var lines: [String] = []
        if let cls = r.childPughClass {
            lines.append("Child-Turcotte-Pugh class " + cls.rawValue + " (" + cls.range + " points). " + ctpReading)
        }
        if r.meld3 != nil || r.meldNa != nil { lines.append(meldReading) }
        let classBC = r.childPughClass.map { $0 != .a } ?? false
        let ascites = x.ascites.map { $0 != .absent } ?? false
        let enceph = x.encephalopathy.map { $0 != .absent } ?? false
        if classBC || ascites || enceph { lines.append(decompensatedReading) }
        if !lines.isEmpty {
            if x.emergency { lines.append(emergencyReading) }
            lines.append(calculatorReading)
        }
        r.interpretation = lines
        return r
    }

    // MARK: Right heart catheterization

    // Definitions: Humbert M, Kovacs G, Hoeper MM, et al. 2022 ESC/ERS Guidelines for the diagnosis and treatment of
    // pulmonary hypertension. Eur Heart J 2022;43:3618–3731 (doi:10.1093/eurheartj/ehac237; PMID 36017548), read in the
    // simultaneous Eur Respir J version, 2023;61:2200879 (doi:10.1183/13993003.00879-2022): Table 5 (PH, mPAP over 20
    // mmHg; pre-capillary, PAWP 15 or less and PVR over 2 WU; isolated post-capillary, PAWP over 15 and PVR 2 or less;
    // combined, PAWP over 15 and PVR over 2), "unclassified PH" for mPAP over 20 with PVR 2 or less and PAWP 15 or
    // less (text), and "e.g. PVR >5 WU" for a severe pre-capillary component in left heart disease with CpcPH
    // (recommendations). The DPG is not part of the definitions. TPG, DPG, PVR, PAPI, CI and PVRI are the standard
    // formulas; the mean is estimated as (PASP + 2 × PADP) / 3 when not measured.

    /// PAPI cut-offs as published. Kang's abstract gives the threshold without saying whether 2.0 itself counts, so
    /// it is read as below 2.0.
    static let papiThresholds: [PAPIThreshold] = [
        // Korabathina R, Heffernan KS, Paruchuri V, et al. Catheter Cardiovasc Interv 2012;80:593–600
        // (doi:10.1002/ccd.23309; PMID 21954053).
        PAPIThreshold(id: "inferior-mi", cutoff: 0.9, inclusive: true,
                      context: "Acute inferior MI from proximal RCA occlusion",
                      finding: "PAPI 0.9 or less identified in-hospital death or need for percutaneous RV support (sensitivity 100%, specificity 98.3%)",
                      citation: "Korabathina 2012"),
        // Morine KJ, Kiernan MS, Pham DT, et al. J Card Fail 2016;22:110–116 (doi:10.1016/j.cardfail.2015.10.019;
        // PMID 26564619). RV failure: unplanned RVAD, or inotropes for 14 days or more.
        PAPIThreshold(id: "lvad-morine", cutoff: 1.85, inclusive: false,
                      context: "Before a continuous-flow LVAD",
                      finding: "PAPI under 1.85 identified RV failure after implantation, defined as an unplanned RVAD or inotropes for 14 days or more (sensitivity 94%, specificity 81%)",
                      citation: "Morine 2016"),
        // Kang G, Ha R, Banerjee D. J Heart Lung Transplant 2016;35:67–73 (doi:10.1016/j.healun.2015.06.009;
        // PMID 26212656).
        PAPIThreshold(id: "lvad-kang", cutoff: 2.0, inclusive: false,
                      context: "Before a continuous-flow LVAD",
                      finding: "a PAPI threshold of 2.0 gave the best sensitivity and specificity for RV failure and RVAD need, and a higher PAPI was independently associated with less RVAD placement",
                      citation: "Kang 2016"),
    ]

    static let mpapEstimateNote = "mPAP estimated as (PA systolic + 2 × PA diastolic) / 3, as no measured mean was entered."
    static let dpgNote = "The DPG is shown for reference; the 2022 ESC/ERS definitions use mPAP, PAWP and PVR."
    static let severePVRNote = "PVR over 5 WU: the guideline's example of a severe pre-capillary component in left heart disease with CpcPH (2022 ESC/ERS)."

    static func rightHeart(_ x: RightHeartInput) -> RightHeartResult {
        func given(_ v: Double?) -> Double? { v.flatMap { $0.isFinite ? $0 : nil } }
        let ra = given(x.ra), sys = given(x.pasp), dia = given(x.padp), wedge = given(x.pcwp)
        let co = given(x.co).flatMap { $0 > 0 ? $0 : nil }
        let bsa = given(x.bsa).flatMap { $0 > 0 ? $0 : nil }
        var r = RightHeartResult()

        // PA pulse pressure, only when systolic is not below diastolic.
        var pulse: Double? = nil
        if let s = sys, let d = dia {
            if s >= d {
                pulse = s - d
            } else {
                r.notes.append("PA systolic is below PA diastolic: check the values.")
            }
        }

        if let m = given(x.mpap) {
            r.mpap = m
        } else if pulse != nil, let s = sys, let d = dia {
            r.mpap = (s + 2 * d) / 3
            r.mpapEstimated = true
            r.notes.append(mpapEstimateNote)
        }
        if let m = r.mpap, let w = wedge { r.tpg = m - w }
        if let d = dia, let w = wedge { r.dpg = d - w }
        if let t = r.tpg, let c = co { r.pvr = t / c }
        if let p = pulse, let a = ra {
            if a > 0 {
                r.papi = p / a
            } else {
                r.notes.append("PAPI needs an RA pressure above 0 mmHg.")
            }
        }
        if let c = co, let b = bsa { r.ci = c / b }
        if let v = r.pvr, let b = bsa { r.pvri = v * b }

        if let m = r.mpap {
            if m <= 20 {
                r.ph = .noPH
            } else if let w = wedge, let v = r.pvr {
                if w <= 15 {
                    r.ph = v > 2 ? .preCapillary : .unclassified
                } else {
                    r.ph = v > 2 ? .combined : .isolatedPostCapillary
                }
            }
        }
        if let ph = r.ph {
            r.phText = ph.label + ": " + ph.criteria + " (2022 ESC/ERS)."
            // The definitions use a measured mean; within 5 mmHg of the 20 mmHg cut-off an estimate can change the class.
            if r.mpapEstimated, let m = r.mpap, abs(m - 20) < 5 {
                r.phText = (r.phText ?? "") + " The mean PA is estimated and near the cut-off: confirm with a measured mean."
            }
        }
        if r.ph == .combined, let v = r.pvr, v > 5 { r.notes.append(severePVRNote) }
        if let p = r.papi { r.papiBelow = papiThresholds.filter { $0.applies(p) } }

        if ra == nil { r.missing.append("RA") }
        if sys == nil { r.missing.append("PA systolic") }
        if dia == nil { r.missing.append("PA diastolic") }
        if wedge == nil { r.missing.append("PCWP") }
        if co == nil { r.missing.append("cardiac output") }
        return r
    }

    // MARK: Helpers

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(v, lo), hi) }
}
