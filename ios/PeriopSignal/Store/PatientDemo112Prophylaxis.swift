import Foundation

#if DEBUG
/// Helper S's demo patients for the Surgical Prophylaxis calculator opened from a case (-ps.patient <seed>; seeds start
/// with "demo-112-proph"), shots 1200-1239. Nothing here is written to disk.
enum PatientDemo112Prophylaxis {
    static func record(_ seed: String) -> PatientRecord? {
        nil
    }
}
#endif
