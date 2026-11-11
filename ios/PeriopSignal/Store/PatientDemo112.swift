import Foundation

#if DEBUG
/// The 1.12 demo patients for screenshots, one file per area (each helper owns its own): -ps.patient demo-<name>.
enum PatientDemo112 {
    static func record(_ seed: String) -> PatientRecord? {
        PatientDemo112Labs.record(seed) ?? PatientDemo112Summary.record(seed) ?? PatientDemo112Layout.record(seed)
            ?? PatientDemo112Meds.record(seed) ?? PatientDemo112Devices.record(seed) ?? PatientDemo112Valves.record(seed)
            ?? PatientDemo112Onc.record(seed)
    }
}
#endif
