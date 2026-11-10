import Foundation

/// Preprocedure imaging findings, as typed (1.12, Ben: "+ Preprocedure Imaging" under Problems by System: free text for
/// a CT scan, an MRI and other imaging). Shown in a summary only when chosen under "+ Add other input data into
/// Handoff" (`PatientRecord.handoffExtras`: "imaging:ct", "imaging:mri", "imaging:other"). Helper B owns this file.
struct PatientImaging: Codable, Hashable {
    var ct = ""
    var mri = ""
    var other = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ct = (try? c.decodeIfPresent(String.self, forKey: .ct)) ?? ""
        mri = (try? c.decodeIfPresent(String.self, forKey: .mri)) ?? ""
        other = (try? c.decodeIfPresent(String.self, forKey: .other)) ?? ""
    }

    var isEmpty: Bool { [ct, mri, other].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}
