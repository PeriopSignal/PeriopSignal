import Foundation

#if DEBUG
/// Helper T's demo patients for cardiopulmonary test findings typed into the text bars (-ps.patient <seed>; seeds start with
/// "demo-112-cardiotext"), shots 1240-1279. Nothing here is written to disk.
///   demo-112-cardiotext-blank: a 68-year-old man for an aortic valve replacement, hypertension and diabetes, no study recorded
///     (the Preoperative tab's bar, and what the Cardiopulmonary Evaluation shows after the findings are added).
///   demo-112-cardiotext-recorded: the same man with studies already recorded (a TTE with an EF of 50%, a left heart cath with a LAD
///     of 70%, a normal chest X-ray, a right carotid of 50-69%): a typed value that differs is "replaces", the same is "already recorded".
enum PatientDemo112CardioText {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-cardiotext-blank": return blank()
        case "demo-112-cardiotext-recorded": return recorded()
        default: return nil
        }
    }

    private static func blank() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 68; r.sex = .male; r.heightCm = 178; r.weightKg = 86
        r.setProcedures(PlannedProcedure.parse("AVR"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.problems = ["htn", "dm"]
        return r
    }

    private static func recorded() -> PatientRecord {
        var r = blank()
        r.echoFindings.study = "TTE"
        r.echoFindings.date = PatientMonthYear(month: 3, year: 2025)
        r.echoFindings.lvef = 50
        r.echoFindings.rv = .mild
        r.lhc.dominance = "left"
        r.lhc.date = PatientMonthYear(month: 3, year: 2025)
        r.lhc.stenosis = ["lad": 70]
        r.chestXray = PatientChestXray(result: .normal)
        r.carotid.right.stenosis = "50-69"
        return r
    }
}
#endif
