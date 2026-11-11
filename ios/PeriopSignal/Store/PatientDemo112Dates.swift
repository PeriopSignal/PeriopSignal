import Foundation

#if DEBUG
/// Helper G's demo patients for the dates and Type & Screen expiration screenshots (-ps.patient <seed>; seeds start with
/// "demo-112-dates"). Start from an existing demo (PatientDemo.record ...) and change what the shot needs.
enum PatientDemo112Dates {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        default: return nil
        }
    }
}
#endif
