import Foundation

// MARK: - Home medications and allergies as items (1.9, Ben's Wanted Changes)
//
// "Need large reference list of common home medications so the user does not need to type everything to the last
// letter. Should be smart enough to list multiple medications with a space or comma break … Flagged medications should
// autoselect if added to home medications." The catalog gives each common outpatient drug its generic name, brand names
// and abbreviations, and the medication flags it raises (PatientCatalog.medFlags ids: "anticoagulant", "p2y12",
// "aspirin", "insulin", "glp1", "sglt2", "betablocker", "acei", "statin", "steroid", "opioid", "maoi").

/// One drug the list knows.
struct MedEntry: Hashable, Identifiable {
    var id: String
    /// The generic name as the list shows it: "Metoprolol succinate".
    var name: String
    /// Brand names and abbreviations that find it, lowercased ("toprol xl", "toprol").
    var aliases: [String]
    /// The medication flags it raises.
    var flags: Set<String>
    /// Its class, for the list's second line: "Beta-blocker".
    var drugClass: String
}

enum MedicationCatalog {
    static let entries: [MedEntry] = []

    /// The entries a typed prefix finds, best first.
    static func search(_ q: String, limit: Int = 8) -> [MedEntry] { [] }

    /// A line of several medications ("metoprolol 25 bid, lisinopril 10 daily atorvastatin"), as items.
    static func parse(_ line: String) -> [PatientMed] { [] }

    static func entry(id: String) -> MedEntry? { entries.first { $0.id == id } }

    /// The flags a medication list raises.
    static func flags(for meds: [PatientMed]) -> Set<String> { [] }
}

/// One allergy (1.9): the allergen as picked or typed, its severity, and the reaction as typed.
struct PatientAllergy: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = ""
    /// "mild", "severe", "anaphylaxis"; nil not recorded.
    var severity: String?
    var reaction = ""

    init(id: UUID = UUID(), name: String = "", severity: String? = nil, reaction: String = "") {
        self.id = id; self.name = name; self.severity = severity; self.reaction = reaction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        severity = try? c.decodeIfPresent(String.self, forKey: .severity)
        reaction = (try? c.decodeIfPresent(String.self, forKey: .reaction)) ?? ""
    }

    static let severities: [(id: String, label: String)] = [("mild", "Mild"), ("severe", "Severe"), ("anaphylaxis", "Anaphylaxis")]

    /// "Penicillin (mild)", "Latex (anaphylaxis)".
    var text: String {
        let label = PatientAllergy.severities.first { $0.id == severity }?.label.lowercased()
        let extra = [label, reaction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reaction.trimmingCharacters(in: .whitespacesAndNewlines)].compactMap { $0 }
        return name + (extra.isEmpty ? "" : " (" + extra.joined(separator: ", ") + ")")
    }
}
