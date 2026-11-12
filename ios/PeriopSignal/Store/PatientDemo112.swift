import Foundation

#if DEBUG
/// The 1.12 demo patients for screenshots, one file per area (each helper owns its own): -ps.patient demo-<name>.
enum PatientDemo112 {
    static func record(_ seed: String) -> PatientRecord? {
        // A list, not a chain of ??: nine of them in one expression was more than the type checker would solve in time.
        let sources: [(String) -> PatientRecord?] = [
            PatientDemo112Labs.record, PatientDemo112Summary.record, PatientDemo112Layout.record,
            PatientDemo112Meds.record, PatientDemo112Devices.record, PatientDemo112Valves.record,
            PatientDemo112Onc.record, PatientDemo112Dates.record, PatientDemo112Abx.record, PatientDemo112More.record, PatientDemo112Heparin.record,
        ]
        for source in sources {
            if let r = source(seed) { return r }
        }
        return nil
    }
}
#endif
