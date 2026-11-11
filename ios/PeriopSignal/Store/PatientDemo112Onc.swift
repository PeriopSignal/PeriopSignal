import Foundation

#if DEBUG
/// Helper F's demo patients for the malignancy screenshots (-ps.patient <seed>; seeds start with "demo-112-onc"). Start
/// from an existing demo (PatientDemo.record ...) and change what the shot needs.
enum PatientDemo112Onc {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        default: return nil
        }
    }
}
#endif
