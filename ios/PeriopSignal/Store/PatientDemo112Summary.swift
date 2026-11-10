import Foundation

#if DEBUG
/// Helper B's demo patients for the 1.12 screenshots (-ps.patient <seed>). Start from an existing demo
/// (PatientDemo.record, PatientDemo.cardiac ...) and change what the shot needs.
enum PatientDemo112Summary {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        default: return nil
        }
    }
}
#endif
