import Foundation

#if DEBUG
/// Demo patients for the Nov 12 follow-up helpers M (seeds "demo-112-m...") and N (seeds "demo-112-n..."); each helper adds
/// only its own seeds, in its own switch case block. Start from an existing demo (PatientDemo.record ...) and change what
/// the shot needs.
enum PatientDemo112More {
    static func record(_ seed: String) -> PatientRecord? {
        if let r = historySeeds(seed) { return r }
        return deviceSeeds(seed)
    }

    /// Helper M: heparin-induced thrombocytopenia, heparin resistance, PVCs.
    static func historySeeds(_ seed: String) -> PatientRecord? {
        switch seed {
        default: return nil
        }
    }

    /// Helper N: the new Lines & Devices items.
    static func deviceSeeds(_ seed: String) -> PatientRecord? {
        switch seed {
        default: return nil
        }
    }
}
#endif
