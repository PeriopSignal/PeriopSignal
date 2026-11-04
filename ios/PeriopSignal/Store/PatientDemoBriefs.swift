import Foundation

// Made-up patients for the 1.9 brief screenshots (-ps.patient demo-briefs | demo-briefs-on | demo-briefs-edit): Ben's example
// (a 76-year-old man, 80 kg, 180 cm, for a laparoscopic cholecystectomy) with enough recorded for every block of the
// preprocedure summary and of the handoff.

extension PatientDemo {
    static var briefs: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 76; r.sex = .male; r.heightCm = 180; r.weightKg = 80
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.allergyList = AllergyCatalog.parse("penicillin mild, latex anaphylaxis")
        r.problems = ["htn", "cad", "af", "dm", "insulin", "copd", "gerd", "hiatal-hernia", "esrd-dialysis", "mdro", "isolation"]
        r.hx.afType = "permanent"
        r.hx.ckdStage = "5"
        r.hx.dialysisSchedule = "mwf"
        r.hx.dialysisAccess = ["fistula", "catheter"]
        r.hx.fistulaSite = "left forearm"
        r.hx.dialysisCatheterSite = "right IJ tunneled"
        r.hx.precautions = ["contact"]
        r.homeMeds = MedicationCatalog.parse("metoprolol 50 mg bid, atorvastatin 40 mg qhs, apixaban 5 mg bid, insulin glargine 20 units qhs")
        r.medFlags = MedicationCatalog.flags(for: r.homeMeds)
        r.surgeries = [PatientSurgery(name: "Total knee arthroplasty", side: "right", date: PatientMonthYear(month: 3, year: 2019)),
                       PatientSurgery(name: "Appendectomy", date: PatientMonthYear(year: 1998))]
        r.mets = "lt4"
        r.mallampati = 2
        r.airwaySigns = ["neck40"]
        r.dentition = "Upper partial denture"
        r.ecg = ["Atrial fibrillation"]
        var echo = PatientEcho()
        echo.study = "TTE"; echo.date = PatientMonthYear(month: 8, year: 2026); echo.lv = .mild; echo.lvef = 45; echo.rv = .normal
        r.echoFindings = echo
        r.labs = ["hb": 10.8, "hct": 33, "wbc": 7.2, "plt": 210, "pt": 12.1, "inr": 1.0, "ptt": 30, "na": 138, "k": 5.6, "cl": 102,
                  "hco3": 22, "bun": 48, "cr": 6.2, "glucose": 162, "albumin": 3.4]
        r.typeScreen = PatientTypeScreen(type: "A+", screen: .negative, crossmatched: 2)
        r.infections = PatientInfections(results: ["mrsa": .positive, "covid": .negative])
        r.lastSolids = PatientDemo.today(0, 0)
        r.lastClears = PatientDemo.today(5, 0)
        r.asaClass = 4
        r.scores["rcri"] = PatientScore(points: 3, max: 6, label: "Class IV", answers: nil, date: Date())
        r.scores["stopbang"] = PatientScore(points: 5, max: 8, label: "High risk", answers: nil, date: Date())
        r.scores["ariscat"] = PatientScore(points: 34, max: nil, label: "Intermediate", answers: nil, date: Date())
        r.devices = ["18g R forearm"].compactMap { PatientDevices.parse($0)?.device(placedIntraop: false) }
            + ["20g R radial art line"].compactMap { PatientDevices.parse($0)?.device(placedIntraop: true) }
        PatientDeviceFills.apply(before: PatientRecord(), after: &r)
        // The case.
        r.currentAirway = "natural"
        r.mask = "easy"; r.intubation = "easy"; r.airwayDevice = "Video laryngoscope"; r.laryngoscopyGrade = "1"; r.attempts = 1
        r.tube = "7.5 ETT, 23 cm at the lip"
        r.airwayAtEnd = "extubated"
        r.regional = [PatientRegional(technique: "TAP block", side: "Bilateral", drug: "ropivacaine 0.25% 20 mL each side")]
        r.infusions = [PatientInfusion(drug: "Phenylephrine", rate: "0.3 mcg/kg/min")]
        r.fluids = ["crystalloid": 800, "ebl": 50, "uop": 0]
        r.medsGiven = "Cefazolin 2 g 08:10; dexamethasone 4 mg; ondansetron 4 mg"
        r.events = "Hypotension after induction, phenylephrine ×2; no arrhythmia"
        var tee = PatientEcho()
        tee.study = "TEE"; tee.lv = .mild; tee.lvef = 45
        r.intraopEcho = tee
        r.intraopLabs = [IntraopLabSet(time: PatientDemo.today(10, 40), values: ["ph": 7.33, "lactate": 1.4, "hb": 10.2, "k": 4.9, "na": 139, "ica": 1.14, "glucose": 192])]
        r.considerations = ["positioning"]
        r.considerationsNote = "Reverse Trendelenburg; left arm padded, no BP cuff or IV on the fistula arm"
        r.disposition = "PACU"
        r.todos = "Hemodialysis tomorrow; check potassium on arrival; resume apixaban per surgery"
        r.codeStatus = .full
        return r
    }

    /// The same patient with the preprocedure summary generated.
    static var briefsOn: PatientRecord {
        var r = briefs
        r.preopSummaryOn = true
        return r
    }

    /// The preprocedure summary and the handoff each with a block the user rewrote.
    static var briefsEdited: PatientRecord {
        var r = briefsOn
        r.preopSummaryEdits = ["allergies": "Penicillin (mild, rash); latex (anaphylaxis, throat swelling 2019)"]
        r.handoffEdits = ["events": "Hypotension after induction, treated with phenylephrine ×2; no arrhythmia; stable since 09:30"]
        return r
    }
}
