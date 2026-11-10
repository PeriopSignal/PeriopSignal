import Foundation

/// The preprocedure chest X-ray: normal, an effusion (side and size), and findings as typed.
/// 1.12 groundwork: an empty shell. Helper E1 owns this file and gives it its fields. Every field must have a default
/// and be read with a fallback in `init(from:)`, so a record saved by an older version still opens.
struct PatientChestXray: Codable, Hashable {
    init() {}

    init(from decoder: Decoder) throws {
        // let c = try decoder.container(keyedBy: CodingKeys.self)
        // field = (try? c.decodeIfPresent(T.self, forKey: .field)) ?? fallback
    }

    var isEmpty: Bool { true }
}
