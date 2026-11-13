import Foundation

#if DEBUG
/// Helper R's demo patients for the antibiotic's dose and a logged dose's time in Case Timers (-ps.patient <seed>; seeds
/// start with "demo-112-abxdose"), shots 1175-1189. Nothing here is written to disk.
enum PatientDemo112AbxDose {
    static func record(_ seed: String) -> PatientRecord? {
        nil
    }
}
#endif
