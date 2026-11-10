import Foundation

/// The Intraoperative tab's notable medications as chips, each with an optional dose (Milrinone bolus, Inhaled
/// milrinone, TXA, Amicar, PCC, fibrinogen concentrate, factor VIIa, Cyanokit, methylene blue).
/// 1.12 groundwork: an empty shell. Helper D owns this file and gives it its fields. Every field must have a default
/// and be read with a fallback in `init(from:)`, so a record saved by an older version still opens.
struct PatientNotableMeds: Codable, Hashable {
    init() {}

    init(from decoder: Decoder) throws {
        // let c = try decoder.container(keyedBy: CodingKeys.self)
        // field = (try? c.decodeIfPresent(T.self, forKey: .field)) ?? fallback
    }

    var isEmpty: Bool { true }
}
