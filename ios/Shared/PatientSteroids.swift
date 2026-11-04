import Foundation

// MARK: - Stress-dose steroids (1.9, Ben, Nov 3)
//
// From the Endocrine page's Adrenal insufficiency or chronic steroids item: who needs perioperative glucocorticoid
// cover, and what, following Woodcock T, Barker P, Daniel S, et al. Guidelines for the management of glucocorticoids
// during the peri-operative period for patients with adrenal insufficiency: Guidelines from the Association of
// Anaesthetists, the Royal College of Physicians and the Society for Endocrinology UK. Anaesthesia 2020;75:654–663.
// doi:10.1111/anae.14963 (PMID 32017012), with the corrections published in Anaesthesia 2020 (doi:10.1111/anae.15210:
// Table 2's major surgery row, and dexamethasone 8 mg equating to 200 mg hydrocortisone).
//
// Read from the full text (1.9, through Wiley's full-text search; tables as published, after the correction):
//   - Who: "Patients taking physiological replacement doses of corticosteroids for either primary or secondary adrenal
//     insufficiency are at significant risk of adrenal crisis and must be given stress doses of hydrocortisone"
//     (abstract). "Daily doses of prednisolone of 5 mg or greater in adults and 10–15 mg.m⁻² hydrocortisone equivalent
//     or greater in children may result in hypothalamo–pituitary–adrenal axis suppression if administered for 1 month
//     or more by oral, inhaled, intranasal, intra-articular or topical routes" (abstract). "If in doubt about the need
//     for glucocorticoids, they should be given" (recommendation 2). Stress dosing "is in addition to usual steroid
//     treatment" (abstract).
//   - Adults with adrenal insufficiency (Table 1), surgery under general or regional anaesthesia, including joint
//     reduction, endoscopy and IVF egg extraction: hydrocortisone 100 mg IV on induction, then a continuous infusion of
//     200 mg/24 h while nil by mouth or vomiting (alternatively 50 mg IM every 6 h); then double oral hydrocortisone
//     for 48 h, or up to a week after major surgery (24 h with rapid recovery). Labour and vaginal delivery: 100 mg IV
//     at the onset of labour, then 200 mg/24 h (or 100 mg IM, then 50 mg IM every 6 h). Caesarean section: as surgery.
//   - Adults on glucocorticoid treatment (Table 2): major surgery, hydrocortisone 100 mg IV at induction then
//     200 mg/24 h by infusion (dexamethasone 6–8 mg IV, if used, suffices for 24 h); 200 mg/24 h IV while nil by mouth
//     (or 50 mg IM every 6 h); then double the presurgical dose by mouth for 48 h if uncomplicated, otherwise for up to a
//     week. Body surface and intermediate surgery: the same at induction; double the regular dose for 48 h. Bowel
//     procedures needing laxatives or enema: continue the usual dose (IV equivalent if nil by mouth for long).
//   - Dexamethasone has no mineralocorticoid activity and is not adequate cover in primary adrenal insufficiency
//     (recommendation 6).
//   - Children (Table 3): hydrocortisone 2 mg/kg at induction; after major surgery 2 mg/kg every 4 h IV or IM, or an
//     infusion by weight (up to 10 kg 25 mg/24 h; 11–20 kg 50 mg/24 h; over 20 kg 100 mg/24 h prepubertal, 150 mg/24 h
//     pubertal); then double oral doses for 48 h.
// The Wiley text renders dashes and "≥" without the sign ("dexamethasone 68mg"); "6–8 mg" is read from it and from
// the guideline's own sentence that 8 mg dexamethasone covers 24 h.
//
// Prednisolone equivalence. The guideline says only that "10 mg hydrocortisone is roughly equivalent to 2.0 mg
// prednisolone and to 0.1 mg dexamethasone", which disagrees with its own corrected statement that 8 mg dexamethasone
// equates to 200 mg hydrocortisone (1 mg to 25 mg). The conversions here are the equivalence table of Liu D, Ahmet A,
// Ward L, et al. A practical guide to the monitoring and management of the complications of systemic corticosteroid
// therapy. Allergy Asthma Clin Immunol 2013;9:30 (Table 3, adapted from NICE 2012; doi:10.1186/1710-1492-9-30, PMID
// 23947590), oral or IV: hydrocortisone 20 mg, cortisone 25, prednisone 5, prednisolone 5, methylprednisolone 4,
// triamcinolone 4, dexamethasone 0.75, betamethasone 0.6. For hydrocortisone this is the more cautious of the two
// (20 mg rather than 25 mg reaches the 5 mg threshold), as the guideline's "if in doubt, give" asks. Inhaled, topical,
// intranasal and intra-articular doses count too (Woodcock) but are not converted here.

/// The advice for this record: whether the patient is at risk of adrenal insufficiency, a one-line headline, the dosing
/// lines, and the citation.
struct SteroidAdvice: Hashable {
    var atRisk: Bool
    var headline: String
    var lines: [String]
    var source: String
}

enum PatientSteroids {
    /// Quick picks for the drug; anything else can be typed.
    static let drugs: [String] = ["Prednisolone", "Prednisone", "Hydrocortisone", "Methylprednisolone", "Dexamethasone"]
    /// hx.steroidDuration: the guideline's threshold is 1 month.
    static let durations: [(id: String, label: String)] = [("lt1m", "Under 1 month"), ("ge1m", "1 month or more")]

    static let source = "Woodcock T, et al. Guidelines for the management of glucocorticoids during the peri-operative period for patients with adrenal insufficiency (Association of Anaesthetists, RCP, Society for Endocrinology UK). Anaesthesia 2020;75:654–663. doi:10.1111/anae.14963. Equivalent doses: Liu D, et al. Allergy Asthma Clin Immunol 2013;9:30 (Table 3)."

    /// The guideline's adult threshold, prednisolone-equivalent mg a day.
    static let thresholdMg = 5.0
    /// Its children's threshold, hydrocortisone-equivalent mg/m² a day: "10–15", the lower bound taken.
    static let childThresholdMgM2 = 10.0

    /// mg of each drug equivalent to 5 mg prednisolone (Liu 2013, Table 3), matched on the typed name, longest first so
    /// "methylprednisolone" is not read as "prednisolone" and "hydrocortisone" not as "cortisone".
    static let equivalents: [(words: [String], name: String, mg: Double)] = [
        (["methylprednisolone", "medrol", "solu-medrol", "solumedrol"], "methylprednisolone", 4),
        (["hydrocortisone", "cortef", "solu-cortef", "solucortef"], "hydrocortisone", 20),
        (["prednisolone"], "prednisolone", 5),
        (["prednisone"], "prednisone", 5),
        (["dexamethasone", "decadron"], "dexamethasone", 0.75),
        (["triamcinolone"], "triamcinolone", 4),
        (["betamethasone"], "betamethasone", 0.6),
        (["cortisone"], "cortisone", 25),
    ]

    /// Names that hold a table drug's name but are not in the table: fludrocortisone (a mineralocorticoid whose
    /// glucocorticoid potency is not cortisone's) would otherwise be read as cortisone.
    static let notConverted: [String] = ["fludrocortisone", "fludrocort", "florinef"]

    /// The typed drug's daily dose as prednisolone (mg/day), or nil when the drug is not in the table.
    static func prednisoloneEquivalent(drug: String, mg: Double) -> Double? {
        let d = drug.lowercased()
        guard mg.isFinite, mg >= 0, !notConverted.contains(where: { d.contains($0) }),
              let e = equivalents.first(where: { $0.words.contains { d.contains($0) } }) else { return nil }
        return mg * 5 / e.mg
    }

    private static func mgText(_ v: Double) -> String { NumText.short((v * 10).rounded() / 10) }

    /// The typed drug is the reference drug (prednisolone) or its 1:1 equivalent prednisone: the equivalence line would
    /// compare the dose with itself ("10 mg prednisolone a day ≈ 10 mg prednisolone a day"), so it is left out.
    static func isReferenceDrug(_ drug: String) -> Bool {
        let d = drug.lowercased()
        guard !notConverted.contains(where: { d.contains($0) }),
              let e = equivalents.first(where: { $0.words.contains { d.contains($0) } }) else { return false }
        return e.name == "prednisolone" || e.name == "prednisone"
    }

    /// nil when there is nothing to advise on yet (no adrenal insufficiency and no dose recorded).
    static func advice(_ r: PatientRecord) -> SteroidAdvice? {
        guard r.has("adrenal") else { return nil }
        let kinds = r.hx.adrenalKinds
        let child = r.isChild
        if kinds.contains("insufficiency") {
            return SteroidAdvice(atRisk: true, headline: "Adrenal insufficiency: give stress-dose hydrocortisone, in addition to the usual dose",
                                 lines: child ? childLines(r) : insufficiencyLines(r), source: source)
        }
        guard kinds.contains("steroids") else { return nil }
        let drug = r.hx.steroidDrug.trimmingCharacters(in: .whitespacesAndNewlines)
        let threshold = child ? "10–15 mg/m² a day of hydrocortisone or its equivalent" : "prednisolone 5 mg a day or its equivalent"
        let rule = "At risk of adrenal suppression: " + threshold + " or more, for 1 month or more, by any route (oral, inhaled, intranasal, intra-articular or topical)."
        guard let mg = r.hx.steroidDailyMg, !drug.isEmpty, let duration = r.hx.steroidDuration else {
            return SteroidAdvice(atRisk: false, headline: "Record the drug, daily dose and how long to see the advice", lines: [rule], source: source)
        }
        guard let peq = prednisoloneEquivalent(drug: drug, mg: mg) else {
            return SteroidAdvice(atRisk: false, headline: "Check the dose against the threshold: \u{201C}" + drug + "\u{201D} is not converted here",
                                 lines: [rule, ifInDoubt], source: source)
        }
        let reached: Bool
        // The dose as the threshold's drug; none when the typed drug is that drug already (adults: prednisolone).
        let doseLine: [String]
        if child {
            let hc = peq * 4
            guard let bsa = r.bsa, bsa > 0 else {
                return SteroidAdvice(atRisk: false, headline: "Add height and weight to compare the dose with the children's threshold",
                                     lines: [rule, ifInDoubt], source: source)
            }
            let perM2 = hc / bsa
            reached = perM2 >= childThresholdMgM2
            doseLine = [mgText(mg) + " mg " + drug.lowercased() + " a day ≈ " + mgText(perM2) + " mg/m² of hydrocortisone a day (BSA " + String(format: "%.2f", bsa) + " m²)."]
        } else {
            reached = peq >= thresholdMg
            doseLine = isReferenceDrug(drug) ? [] : [mgText(mg) + " mg " + drug.lowercased() + " a day ≈ " + mgText(peq) + " mg prednisolone a day."]
        }
        let longEnough = duration == "ge1m"
        if reached && longEnough {
            return SteroidAdvice(atRisk: true, headline: "At risk of adrenal insufficiency: give stress-dose hydrocortisone, in addition to the usual dose",
                                 lines: doseLine + (child ? childLines(r) : steroidLines(r)), source: source)
        }
        let why = !reached ? "Below the guideline's threshold" : "Under 1 month, below the guideline's threshold"
        return SteroidAdvice(atRisk: false, headline: why + ": no stress dose by the dose and duration alone",
                             lines: doseLine + [rule, ifInDoubt], source: source)
    }

    static let ifInDoubt = "If in doubt, give: there are no long-term adverse consequences of short-term glucocorticoid administration."

    /// Adults on replacement for adrenal insufficiency (Table 1).
    static func insufficiencyLines(_ r: PatientRecord) -> [String] {
        var out = [
            "Surgery under general or regional anesthesia (including endoscopy): hydrocortisone 100 mg IV at induction, then 200 mg/24 h by continuous IV infusion while nil by mouth or vomiting (or 50 mg IM every 6 h).",
            "Then double the usual oral hydrocortisone for 48 h, for up to a week after major surgery, or for 24 h with a rapid recovery.",
            "Dexamethasone has no mineralocorticoid activity: not adequate cover in primary adrenal insufficiency.",
        ]
        if r.has("pregnant") { out.append("Labor and vaginal delivery: hydrocortisone 100 mg IV at the onset of labor, then 200 mg/24 h IV (or 50 mg IM every 6 h); cesarean delivery as surgery.") }
        return out
    }

    /// Adults on glucocorticoid treatment (Table 2).
    static func steroidLines(_ r: PatientRecord) -> [String] {
        var out = [
            "Major, intermediate or body surface surgery: hydrocortisone 100 mg IV at induction, then 200 mg/24 h by IV infusion; dexamethasone 6–8 mg IV, if given, suffices for 24 h.",
            "After major surgery: 200 mg/24 h IV while nil by mouth (or 50 mg IM every 6 h), then double the usual dose by mouth for 48 h if uncomplicated, otherwise for up to a week.",
            "After intermediate or body surface surgery: double the usual dose for 48 h.",
            "Bowel preparation alone: continue the usual dose (its IV equivalent if nil by mouth for long).",
        ]
        if r.has("pregnant") { out.append("Labor and vaginal delivery: hydrocortisone 100 mg IV at the onset of labor, then 200 mg/24 h IV (or 50 mg IM every 6 h); cesarean delivery as major surgery.") }
        return out
    }

    /// Children (Table 3), with 2 mg/kg worked out when the weight is known.
    static func childLines(_ r: PatientRecord) -> [String] {
        let dose = r.weightKg.map { " (" + mgText(2 * $0) + " mg at " + NumText.short($0) + " kg)" } ?? ""
        return [
            "Hydrocortisone 2 mg/kg IV at induction" + dose + ", for minor or major surgery under general anesthesia.",
            "After major surgery: 2 mg/kg every 4 h IV or IM, or an infusion by weight: up to 10 kg 25 mg/24 h; 11–20 kg 50 mg/24 h; over 20 kg 100 mg/24 h prepubertal, 150 mg/24 h pubertal.",
            "Once stable, double the usual oral hydrocortisone for 48 h, then back to the usual dose over up to a week; after minor surgery, double doses for 24 h.",
            "Check blood glucose hourly if fasting exceeds 4 h and after surgery until eating again.",
        ]
    }
}
