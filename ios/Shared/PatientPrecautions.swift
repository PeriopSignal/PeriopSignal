import Foundation

// MARK: - Isolation precautions suggested by the history (1.9, Ben, Nov 3)
//
// One-tap suggestions with their CDC source, never filed by themselves: C. difficile → contact; tuberculosis and
// COVID-19 → airborne; URI and pneumonia → droplet (for the organisms the CDC lists).

/// One precaution the history suggests, with the items that suggest it and the source's words.
struct PrecautionSuggestion: Identifiable, Hashable {
    /// "contact", "droplet", "airborne".
    var precaution: String
    /// The history items, as their pages name them ("C. difficile").
    var from: [String]
    /// The caption: what the CDC recommends, and the citation.
    var source: String
    var id: String { precaution }
}

enum PatientPrecautions {
    static let kinds: [(id: String, label: String)] = [("contact", "Contact"), ("droplet", "Droplet"), ("airborne", "Airborne")]

    /// What the history suggests that the Isolation precautions item does not say yet.
    static func suggestions(_ r: PatientRecord) -> [PrecautionSuggestion] { [] }

    /// Accepting one: the Isolation precautions item, with the precaution.
    static func accept(_ s: PrecautionSuggestion, _ r: inout PatientRecord) {
        r.noHistory = false
        r.problems.insert("isolation")
        r.hx.precautions.insert(s.precaution)
    }
}
