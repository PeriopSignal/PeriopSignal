import Foundation

// MARK: - Stress-dose steroids (1.9, Ben, Nov 3)
//
// From the Endocrine page's Adrenal insufficiency or chronic steroids item: who needs perioperative glucocorticoid
// cover, and what, following Woodcock T, Barker P, Daniel S, et al. Guidelines for the management of glucocorticoids
// during the peri-operative period for patients with adrenal insufficiency: Guidelines from the Association of
// Anaesthetists, the Royal College of Physicians and the Society for Endocrinology UK. Anaesthesia 2020;75:654–663.
// doi:10.1111/anae.14963 (PMID 32017012).

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

    /// nil when there is nothing to advise on yet (no adrenal insufficiency and no dose recorded).
    static func advice(_ r: PatientRecord) -> SteroidAdvice? { nil }
}
