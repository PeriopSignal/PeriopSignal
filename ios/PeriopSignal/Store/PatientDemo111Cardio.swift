import Foundation

// Made-up patients for the 1.11 Cardiopulmonary, code-status and infusion screenshots (-ps.patient demo-cardio111 and
// demo-cardio111-chole, shots 760–779). Nothing here is written to disk.

extension PatientDemo {
    /// A 72-year-old man for a CABG ×3: the planned procedure answers "Intrathoracic procedure: Yes (from the procedure)";
    /// DNR without a perioperative plan yet (the red caption under the inline plan chips); vitals and a last intake set;
    /// a positive dobutamine stress test among the workup; two drips running before the case and none started in the
    /// room, so the Intraoperative tab lists them "from preop".
    static var cardio111: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 72; r.sex = .male; r.heightCm = 175; r.weightKg = 82
        r.setProcedures(PlannedProcedure.parse("CABG x3"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.problems = ["htn", "hld", "dm", "cad"]
        r.vitals = ["sbp": 142, "dbp": 78, "hr": 64, "spo2": 96]
        r.lastSolids = PatientRecord.npoMidnight()
        r.lastClears = today(5, 0)
        r.codeStatus = .dnr
        r.ecg = ["Normal sinus rhythm"]
        r.stressTest = PatientStressTest(kind: .dobutamine, result: .positive, date: PatientMonthYear(month: 9, year: 2026),
                                         findings: "inferior and inferolateral hypokinesis at peak dose")
        r.homeInfusions = [PatientInfusion(drug: "Nitroglycerin", rate: "0.5 mcg/kg/min"), PatientInfusion(drug: "Heparin", rate: "1200 units/h")]
        // What the planned procedure fills, as the store's cross-fill would on the first change.
        PatientPreop.syncIntrathoracic(before: PatientRecord(), after: &r)
        return r
    }

    /// A 61-year-old woman for a laparoscopic cholecystectomy: "Intrathoracic procedure: No (from the procedure)"; the
    /// cardiac questions answered None in one tap; a negative exercise stress test; the stepwise conclusion as one row.
    static var cardio111Chole: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 61; r.sex = .female; r.heightCm = 163; r.weightKg = 70
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.problems = ["htn", "dm"]
        r.mets = "ge4"
        r.codeStatus = .full
        PatientPreop.setCardiacNone(true, &r)
        r.ecg = ["Normal sinus rhythm"]
        r.stressTest = PatientStressTest(kind: .exercise, result: .negative, date: PatientMonthYear(month: 6, year: 2026),
                                         findings: "no ischemia at 10 METs")
        PatientPreop.syncIntrathoracic(before: PatientRecord(), after: &r)
        return r
    }
}
