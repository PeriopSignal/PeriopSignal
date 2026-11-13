import Foundation

#if DEBUG
/// Demo patients for the Nov 12 follow-up helpers M (seeds "demo-112-m...") and N (seeds "demo-112-n..."); each helper adds
/// only its own seeds, in its own switch case block. Start from an existing demo (PatientDemo.record ...) and change what
/// the shot needs.
enum PatientDemo112More {
    static func record(_ seed: String) -> PatientRecord? {
        if let r = historySeeds(seed) { return r }
        if let r = foldSeeds(seed) { return r }
        return deviceSeeds(seed)
    }

    /// Ben, Nov 13 (the cardiac result row starts as its one red line; a folded Cardiopulmonary box keeps it in view).
    ///
    ///   demo-112-fold   the cholecystectomy patient of demo-cardio111-chole with coronary disease, heart failure and COPD
    ///                   and no functional capacity recorded, so the stepwise result is a warning ("Assess functional
    ///                   capacity"); the ECG and the stress test are entered, so the box folds
    static func foldSeeds(_ seed: String) -> PatientRecord? {
        guard seed == "demo-112-fold" else { return nil }
        var r = PatientDemo.cardio111Chole
        r.problems = ["htn", "dm", "cad", "hf", "copd"]
        r.mets = nil
        PatientHistoryDetails.sync(&r)
        return r
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
