import Foundation

// Made-up patients for the 1.9 line-diagram screenshots (-ps.patient demo-wires | demo-dialysis | demo-chesttube). Each
// is built the way the app builds it: the history entries are set and the device fills run, so the diagram shows what
// the pages would have drawn.

extension PatientDemo {
    /// Back to the room for bleeding after an aortic valve replacement: epicardial atrial and ventricular wires, a right IJ
    /// introducer and a left radial arterial line on arrival, and the pacemaker the Cardiovascular page records on the left.
    static var wires: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 71; r.sex = .male; r.heightCm = 176; r.weightKg = 84
        r.setProcedures(PlannedProcedure.parse("Re-exploration for bleeding after AVR"))
        r.urgency = .elective
        r.problems = ["htn", "af", "pacemaker"]
        r.hx.ciedSide = "left"
        r.hx.deviceDetails = "Dual chamber, pacer dependent"
        r.hx.pacerDependent = true
        r.devices = ["epicardial wires A+V DDD 80 bpm", "RIJ introducer", "L radial art line"].compactMap { PatientDevices.parse($0)?.device(placedIntraop: false) }
        PatientDeviceFills.apply(before: PatientRecord(), after: &r)
        return r
    }

    /// A hemodialysis patient (Monday, Wednesday, Friday) for a cholecystectomy: a left forearm fistula and a tunneled right
    /// IJ catheter from the Renal page, and a limb alert typed for the right arm.
    static var dialysis: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 58; r.sex = .female; r.heightCm = 165; r.weightKg = 71
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        r.urgency = .elective
        r.problems = ["htn", "dm", "esrd-dialysis"]
        r.hx.dialysisSchedule = "mwf"
        r.hx.dialysisAccess = ["fistula", "catheter"]
        r.hx.fistulaSite = "left forearm (radiocephalic)"
        r.hx.dialysisCatheterSite = "right IJ tunneled"
        r.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "Prior axillary lymph node dissection")]
        r.disposition = "PACU"
        PatientDeviceFills.apply(before: PatientRecord(), after: &r)
        return r
    }

    /// A left empyema drained by a chest tube, for a decortication: the tube is drawn from the Respiratory page's answer.
    static var chestTube: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 64; r.sex = .male; r.heightCm = 180; r.weightKg = 88
        r.setProcedures(PlannedProcedure.parse("VATS decortication"))
        r.urgency = .elective
        r.problems = ["copd", "pleural-effusion"]
        r.hx.pleuralSide = "left"
        r.hx.pleuralFluid = "unspecified"
        r.hx.pleuralDrained = true
        r.hx.chestTube = true
        r.hx.chestTubeSides = ["left"]
        r.devices = ["18g R forearm"].compactMap { PatientDevices.parse($0)?.device(placedIntraop: false) }
        PatientDeviceFills.apply(before: PatientRecord(), after: &r)
        if let i = r.devices.firstIndex(where: { $0.kind == .chestTube }) { r.devices[i].size = "28" }
        return r
    }
}
