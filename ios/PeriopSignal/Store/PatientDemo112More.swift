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
    ///   demo-112-n-cardiac  a 72-year-old man for a CABG with an arterial line and a right IJ introducer on arrival, an ETT, and in
    ///                       the room epicardial wires (atrial and ventricular), cerebral oximetry, SedLine, a TEE probe, Zoll pads
    ///                       and a left Arndt bronchial blocker (the diagram, the list and the handoff for all five new items)
    static func deviceSeeds(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-n-cardiac":
            var r = PatientDemo.cardio111
            r.intubation = "easy"
            r.tube = "8.0 cuffed ETT (23 cm)"
            func put(_ text: String, intra: Bool) {
                if let p = PatientDevices.parse(text) { r.devices += p.devices(placedIntraop: intra) }
            }
            put("R radial art line 20g", intra: false)
            put("RIJ introducer 9 Fr", intra: false)
            put("epicardial wires A and V", intra: true)
            put("cerebral oximetry", intra: true)
            put("SedLine", intra: true)
            put("TEE probe in", intra: true)
            put("Zoll pads on", intra: true)
            put("Arndt blocker left", intra: true)
            return r
        default: return nil
        }
    }
}
#endif
