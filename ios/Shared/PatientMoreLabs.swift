import Foundation

/// Preprocedure results that are not a number in `PatientRecord.labs`: the pregnancy test (negative, or an hCG value as
/// typed), urinalysis and blood cultures (negative, or findings).
/// 1.12 groundwork: an empty shell. Helper A owns this file and gives it its fields. Every field must have a default
/// and be read with a fallback in `init(from:)`, so a record saved by an older version still opens.
struct PatientMoreLabs: Codable, Hashable {
    init() {}

    init(from decoder: Decoder) throws {
        // let c = try decoder.container(keyedBy: CodingKeys.self)
        // field = (try? c.decodeIfPresent(T.self, forKey: .field)) ?? fallback
    }

    var isEmpty: Bool { true }
}
