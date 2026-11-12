import Foundation

#if DEBUG
/// Helper O's demo patients for the reworked Heparin & ACT timeline (-ps.patient <seed>; seeds start with
/// "demo-112-hep"). Start from an existing demo (PatientDemo.record ...) and set `timers.heparin` as the shot needs.
enum PatientDemo112Heparin {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        default: return nil
        }
    }
}
#endif
