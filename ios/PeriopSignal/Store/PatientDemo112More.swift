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
    ///
    ///   demo-112-m-hit   anemia, HIT and heparin resistance chosen on the Heme & Oncology page (and hypertension), the
    ///                    Preprocedure Summary on: the page, the tile and the PMH line
    ///   demo-112-m-hit-page  HIT and heparin resistance chosen and nothing that opens above them (no anemia, no anticoagulation
    ///                    details), so both rows sit on the first screen of the page whatever the scroll did (run 645's light shot)
    ///   demo-112-m-pvc   hypertension and Other arrhythmia with "PVCs" as its detail: the Cardiovascular page
    static func historySeeds(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-m-hit":
            var r = PatientDemo.record
            r.problems = ["htn", "anemia", "hit", "anticoagulation", "heparin-resistance"]
            r.hx.anticoagulants = ["heparin": PatientAnticoagulant(intensity: "therapeutic")]
            r.medFlags.remove("insulin")
            r.asaClass = nil
            r.preopSummaryOn = true
            PatientHistoryDetails.sync(&r)
            return r
        case "demo-112-m-hit-page":
            var r = PatientDemo.record
            r.problems = ["htn", "hit", "heparin-resistance"]
            r.medFlags.remove("insulin")
            r.asaClass = nil
            r.preopSummaryOn = true
            PatientHistoryDetails.sync(&r)
            return r
        case "demo-112-m-pvc":
            var r = PatientDemo.record
            r.problems = ["htn", "arrhythmia"]
            r.hx.arrhythmiaType = "PVCs"
            r.medFlags.remove("insulin")
            r.asaClass = nil
            r.preopSummaryOn = true
            PatientHistoryDetails.sync(&r)
            return r
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
