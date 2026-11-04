import Foundation

// MARK: - Isolation precautions suggested by the history (1.9, Ben, Nov 3)
//
// One-tap suggestions with their CDC source, never filed by themselves: C. difficile → contact; tuberculosis and
// COVID-19 → airborne; URI and pneumonia → droplet (for the organisms the CDC lists).
//
// Sources (cdc.gov was not reachable in the 1.9 session: the captions follow the sources as the 1.9 spec summarizes
// them, to verify against cdc.gov):
//   - Siegel JD, Rhinehart E, Jackson M, Chiarello L; Healthcare Infection Control Practices Advisory Committee. 2007
//     Guideline for Isolation Precautions: Preventing Transmission of Infectious Agents in Healthcare Settings (updated
//     2019), Appendix A, Type and duration of precautions recommended for selected infections and conditions:
//     Clostridioides difficile, contact; tuberculosis, pulmonary or laryngeal, confirmed or suspected, airborne, and
//     latent infection, standard; droplet for specific respiratory organisms (influenza, rhinovirus, Mycoplasma
//     pneumoniae, group A streptococcus, Neisseria meningitidis, adenovirus with contact, pertussis), and standard
//     precautions for most adult bacterial pneumonia and adult acute respiratory infection.
//   - CDC, Infection Control Guidance: SARS-CoV-2 (healthcare settings): an N95 or higher-level respirator, gown, gloves
//     and eye protection for a patient with suspected or confirmed infection, and an airborne infection isolation room
//     for aerosol-generating procedures.

/// One precaution the history suggests, with the items that suggest it and the source's words.
struct PrecautionSuggestion: Identifiable, Hashable {
    /// "contact", "droplet", "airborne".
    var precaution: String
    /// The history items, as their pages name them ("C. difficile").
    var from: [String]
    /// The caption: what the CDC recommends, and the citation.
    var source: String
    var id: String { precaution }

    /// "Contact precautions: C. difficile — add?"
    var prompt: String {
        (PatientPrecautions.kinds.first { $0.id == precaution }?.label ?? precaution.capitalized) + " precautions: " + from.joined(separator: ", ") + " — add?"
    }
}

enum PatientPrecautions {
    static let kinds: [(id: String, label: String)] = [("contact", "Contact"), ("droplet", "Droplet"), ("airborne", "Airborne")]

    static let hicpac = "CDC/HICPAC 2007 Guideline for Isolation Precautions, Appendix A (updated 2019)"
    static let contactSource = "C. difficile: contact precautions for the duration of illness (" + hicpac + ")."
    static let tbSource = "Pulmonary or laryngeal TB, confirmed or suspected: airborne precautions; latent TB: standard precautions (" + hicpac + ")."
    static let covidSource = "SARS-CoV-2, suspected or confirmed: an N95 or higher-level respirator, gown, gloves and eye protection; an airborne infection isolation room for aerosol-generating procedures (CDC infection control guidance for SARS-CoV-2)."
    static let dropletSource = "Droplet precautions for specific organisms: influenza, rhinovirus, Mycoplasma, group A streptococcus, meningococcus, pertussis, and adenovirus (with contact). Most adult bacterial pneumonia and adult acute respiratory infection need standard precautions only (" + hicpac + ")."

    /// What the history suggests that the Isolation precautions item does not say yet, grouped by precaution, in the
    /// order contact, droplet, airborne.
    static func suggestions(_ r: PatientRecord) -> [PrecautionSuggestion] {
        func label(_ id: String) -> String { PatientCatalog.problem(id)?.label ?? id }
        var from: [String: [String]] = [:]
        var sources: [String: [String]] = [:]
        func add(_ p: String, _ item: String, _ source: String) {
            from[p, default: []].append(item)
            if !(sources[p] ?? []).contains(source) { sources[p, default: []].append(source) }
        }
        if r.has("c-diff") { add("contact", label("c-diff"), contactSource) }
        for id in ["uri", "pneumonia"] where r.has(id) { add("droplet", label(id), dropletSource) }
        if r.has("tb"), r.hx.tbStatus != "latent" { add("airborne", label("tb"), tbSource) }
        if r.has("covid-recent"), r.hx.covidStatus != "recent" { add("airborne", label("covid-recent"), covidSource) }
        return kinds.compactMap { k -> PrecautionSuggestion? in
            guard let items = from[k.id], !r.hx.precautions.contains(k.id) else { return nil }
            return PrecautionSuggestion(precaution: k.id, from: items, source: (sources[k.id] ?? []).joined(separator: " "))
        }
    }

    /// Accepting one: the Isolation precautions item, with the precaution.
    static func accept(_ s: PrecautionSuggestion, _ r: inout PatientRecord) {
        r.noHistory = false
        r.problems.insert("isolation")
        r.hx.precautions.insert(s.precaution)
    }
}
