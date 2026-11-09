import XCTest
@testable import PeriopSignal

/// My Patient 1.6: past operations, echo and catheterization findings, the current airway and the tabs' lines.
final class PatientWorkupTests: XCTestCase {

    func testMonthYear() {
        XCTAssertEqual(PatientMonthYear.parse("03/2019"), PatientMonthYear(month: 3, year: 2019))
        XCTAssertEqual(PatientMonthYear.parse("3/2019"), PatientMonthYear(month: 3, year: 2019))
        XCTAssertEqual(PatientMonthYear.parse("2019"), PatientMonthYear(year: 2019))
        XCTAssertEqual(PatientMonthYear.parse("Mar 2019"), PatientMonthYear(month: 3, year: 2019))
        XCTAssertEqual(PatientMonthYear.parse("03/19")?.year, 2019)
        XCTAssertNil(PatientMonthYear.parse("13/2019"))
        XCTAssertNil(PatientMonthYear.parse("soon"))
        XCTAssertEqual(PatientMonthYear(month: 3, year: 2019).text, "03/2019")
        XCTAssertEqual(PatientMonthYear(year: 2015).text, "2015")
        XCTAssertEqual(PatientMonthYear().text, "")
    }

    func testSurgeryText() {
        XCTAssertEqual(PatientSurgery(name: "Total knee arthroplasty", side: "right", date: PatientMonthYear(month: 3, year: 2019)).text, "Right total knee arthroplasty (03/2019)")
        XCTAssertEqual(PatientSurgery(name: "CABG ×3", date: PatientMonthYear(year: 2015)).text, "CABG ×3 (2015)")
        XCTAssertEqual(PatientSurgery(name: "Inguinal hernia repair", side: "bilateral").text, "Bilateral inguinal hernia repair")
        var r = PatientRecord()
        r.surgeries = [PatientSurgery(name: "CABG ×3", intrathoracic: true), PatientSurgery(name: "Appendectomy")]
        r.intrathoracic = [PatientSurgery(name: "Right VATS wedge", intrathoracic: true)]
        XCTAssertEqual(r.allIntrathoracic.map(\.name), ["CABG ×3", "Right VATS wedge"], "the history's chest operations and those added in the evaluation")
    }

    func testEchoSummary() {
        var e = PatientEcho()
        XCTAssertTrue(e.isEmpty)
        e.study = "TEE"; e.date = PatientMonthYear(month: 6, year: 2026)
        e.lv = .moderate; e.lvef = 35
        e.rv = .mild
        e.mitral = EchoValve(regurgitation: .severe, stenosis: .normal)
        e.aortic = EchoValve(stenosis: .severe, prosthesis: "")
        e.tricuspid = EchoValve(prosthesis: "Repair or ring")
        e.aortaIntact = true
        XCTAssertEqual(e.summary, "TEE 06/2026: LV EF 35%, moderately reduced; RV function mildly reduced; Severe MR; Tricuspid repair or ring; Severe AS; Aorta intact")
        var lvOnly = PatientEcho(); lvOnly.lv = .normal
        XCTAssertEqual(lvOnly.summary, "LV function normal")
        var aorta = PatientEcho(); aorta.aortaIntact = false; aorta.aorta = "ascending 4.6 cm"
        XCTAssertEqual(aorta.phrases, ["Aorta: ascending 4.6 cm"])
    }

    func testCathSummaries() {
        var l = PatientLHC()
        XCTAssertTrue(l.isEmpty)
        l.dominance = "right"; l.stenosis = ["lad": 90, "rca": 70, "lcx": 30]; l.date = PatientMonthYear(month: 5, year: 2026)
        XCTAssertEqual(l.summary, "LHC 05/2026, right dominant: LAD 90%, RCA 70%; LCx 30%")
        var r = PatientRecord()
        r.rhc.ra = 12; r.rhc.pasp = 52; r.rhc.padp = 24; r.rhc.pcwp = 22; r.rhc.co = 3.8
        XCTAssertEqual(PatientSummary.rhcText(r), "RA 12, PA 52/24, PCWP 22, CO 3.8")
        r.rhc.pam = 33
        XCTAssertEqual(PatientSummary.rhcText(r), "RA 12, PA 52/24 (mean 33), PCWP 22, CO 3.8")
        XCTAssertNil(PatientSummary.rhcText(PatientRecord()))
    }

    func testAirwayAndOxygen() {
        var r = PatientRecord()
        XCTAssertNil(r.currentAirwayText)
        r.currentAirway = "ett"; r.ettSize = "7.5"; r.ettDepth = "23 cm at the lip"
        XCTAssertTrue(r.arrivesWithAirway)
        XCTAssertEqual(r.currentAirwayText, "ETT 7.5 at 23 cm at the lip")
        r.vent.mode = "AC/VC"; r.vent.vt = 450; r.vent.rr = 16; r.vent.peep = 8; r.vent.fio2 = 40
        XCTAssertEqual(r.vent.text, "AC/VC 450 × 16, PEEP 8, FiO₂ 40%")
        let lines = PatientSummary.airwayLines(r)
        XCTAssertEqual(lines.first?.text, "ETT 7.5 at 23 cm at the lip")
        XCTAssertTrue(lines.contains { $0.label == "Ventilator" && $0.text.hasPrefix("AC/VC") })
        XCTAssertEqual(PatientSummary.intraopPartLines(r, "airway").first?.text, "ETT 7.5 at 23 cm at the lip on arrival", "no airway course for a secured airway")
        r.airwayAtEnd = "extubated"
        // 1.11 (P1-10): how the airway is left is the airway part's line, not the events part's (the Events page lost
        // its airway buttons; the handoff text is unchanged).
        XCTAssertTrue(PatientSummary.intraopPartLines(r, "airway").contains { $0.label == "At handoff" && $0.text == "Extubated" })
        XCTAssertFalse(PatientSummary.intraopPartLines(r, "events").contains { $0.text == "Extubated" })
        XCTAssertTrue(HandoffWriter.shortText(r).contains("Airway: ETT 7.5 at 23 cm at the lip on arrival; AC/VC 450 × 16, PEEP 8, FiO₂ 40%; at handoff: extubated"), HandoffWriter.shortText(r))

        var nc = PatientRecord()
        nc.currentAirway = "natural"; nc.oxygen = PatientOxygen(device: "nc", flow: 2)
        XCTAssertFalse(nc.arrivesWithAirway)
        XCTAssertEqual(nc.oxygen.text, "Nasal cannula 2 L/min")
        XCTAssertTrue(PatientSummary.airwayLines(nc).contains { $0.label == "Oxygen" && $0.text == "Nasal cannula 2 L/min" })
        XCTAssertEqual(PatientOxygen(device: "hfnc", flow: 40, fio2: 50).text, "High-flow nasal 40 L/min, FiO₂ 50%")

        var trach = PatientRecord()
        trach.currentAirway = "trach"; trach.trachType = "Shiley 8 cuffed"; trach.oxygen = PatientOxygen(device: "trachCollar", flow: 10, fio2: 35)
        XCTAssertEqual(trach.currentAirwayText, "Tracheostomy (Shiley 8 cuffed)")
        XCTAssertTrue(PatientSummary.airwayLines(trach).contains { $0.label == "Oxygen" }, "a trach collar shows its oxygen")
    }

    func testHistoryAndAssessmentLines() {
        var r = PatientRecord()
        r.smoking = "current"
        r.problems = ["alcohol-social"]
        r.surgeries = [PatientSurgery(name: "Appendectomy", date: PatientMonthYear(year: 2001))]
        r.homeInfusions = [PatientInfusion(drug: "Heparin", rate: "1200 units/h")]
        r.anesthesiaHistory = ["mh"]
        let h = PatientSummary.historyLines(r)
        // 1.9: Smoking & Substances is an expanding page; its words are lowercase like the other pages', and smoking is
        // its first item (HistorySections.socialItems) rather than a line the summary adds.
        XCTAssertEqual(h.first { $0.label == "Smoking & Substances" }?.text, "current smoker; social alcohol use", "smoking leads the substance line")
        XCTAssertEqual(h.first { $0.label == "Past surgical history" }?.text, "Appendectomy (2001)")
        XCTAssertEqual(h.first { $0.label == "Current infusions" }?.text, "Heparin at 1200 units/h")
        XCTAssertEqual(h.first { $0.label == "Anesthetic complications" }?.alert, true, "malignant hyperthermia is flagged")
        XCTAssertNil(h.first { $0.label == "Smoking" }, "no separate smoking line")
        r.ecg = ["Atrial fibrillation"]; r.ecgNotes = "rate 88"
        r.echoFindings.lvef = 55
        let a = PatientSummary.assessmentLines(r)
        XCTAssertEqual(a.first { $0.label == "ECG" }?.text, "Atrial fibrillation; Rate 88")
        XCTAssertEqual(a.first { $0.label == "Echo" }?.text, "LV EF 55%")
    }

    func testProcedureAndDemographicsLines() {
        let demo = PatientDemo.record
        let p = PatientSummary.procedureLines(demo)
        XCTAssertEqual(p.first?.text, "Laparoscopic sigmoid colectomy")
        XCTAssertTrue(p.contains { $0.label == "Risk-score inputs" && $0.text.contains("High-risk surgery (RCRI)") })
        let d = PatientSummary.demographicsLines(demo)
        XCTAssertEqual(d.first?.text, "67-year-old man")
        XCTAssertTrue(d.contains { $0.label == "Preprocedure vitals" })
        XCTAssertTrue(PatientSummary.procedureLines(PatientRecord()).isEmpty)
    }

    func testEchoFirst() {
        var r = PatientRecord()
        for p in ["CABG ×3", "Mitral valve repair", "TAVR", "Orthotopic liver transplant", "Liver transplant", "EVAR", "Type A aortic dissection repair", "HeartMate 3 LVAD"] {
            r.procedure = p
            XCTAssertTrue(PatientRules.echoFirst(r), p)
        }
        for p in ["Laparoscopic cholecystectomy", "Roux-en-Y gastric bypass", "Axillary lymph node dissection", "Cerebral aneurysm clipping", "Kidney transplant", ""] {
            r.procedure = p
            XCTAssertFalse(PatientRules.echoFirst(r), p)
        }
    }

    /// Cardiac surgery hides the RCRI (derived for noncardiac surgery).
    func testCardiacSurgeryHidesRCRI() {
        var r = PatientDemo.record
        r.procedures = []
        XCTAssertTrue(PatientRules.prompts(r).contains { $0.id == "rcri" })
        for p in ["CABG ×3", "Aortic valve replacement", "TAVR", "Redo sternotomy, MVR", "Bentall"] {
            r.procedure = p
            XCTAssertTrue(PatientRules.cardiacSurgery(r), p)
            XCTAssertFalse(PatientRules.prompts(r).contains { $0.id == "rcri" }, p)
        }
        for p in ["Laparoscopic sigmoid colectomy", "Carotid endarterectomy", "Liver transplant",
                  "Lap chole s/p CABG", "Ex lap on LVAD", "EGD in LVAD patient", "Endobronchial valve placement", "Hip fracture, prior AVR"] {
            r.procedure = p
            XCTAssertFalse(PatientRules.cardiacSurgery(r), p)
            r.setProcedures(PlannedProcedure.parse(p))
            XCTAssertFalse(PatientRules.cardiacSurgery(r), p + " (as items)")
            XCTAssertTrue(PatientRules.prompts(r).contains { $0.id == "rcri" }, p)
            r.procedures = []
        }
        XCTAssertEqual(PlannedProcedure.parse("EGD in LVAD patient").map(\.catalogID).compactMap { $0 }.contains("lvad"), false)
        for p in ["Watchman", "Balloon aortic valvuloplasty", "Impella CP insertion", "PFO closure"] {
            r.procedure = p
            XCTAssertTrue(PatientRules.cardiacSurgery(r), p + ": transcatheter heart procedures are treated alike")
        }
    }

    /// The ASE valve and chamber tools write their grades into the echo findings.
    func testEchoFromTools() {
        var e = PatientEcho()
        e.apply(.as_, .severe)
        e.apply(.mr, .moderate)
        e.apply(.tr, .mild)
        XCTAssertEqual(e.aortic.stenosis, .severe)
        XCTAssertEqual(e.mitral.regurgitation, .moderate)
        XCTAssertEqual(e.tricuspid.regurgitation, .mild)
        XCTAssertEqual(e.grade(for: .as_), .severe)
        XCTAssertNil(e.grade(for: .ms))
        XCTAssertEqual(e.phrases, ["Moderate MR", "Mild TR", "Severe AS"])
        XCTAssertEqual(EchoGrade(chamber: 0), .normal)
        XCTAssertEqual(EchoGrade(chamber: -1), .normal, "outside the range on the harmless side is normal function")
        XCTAssertEqual(EchoGrade(chamber: 2), .moderate)
        XCTAssertNil(EchoGrade(chamber: 4), "a single cutoff names no severity")
    }

    /// Lines saved before 1.6 move into the devices on the diagram.
    func testOldLinesBecomeDevices() throws {
        let json = #"{"version":1,"lines":[{"kind":"Peripheral IV","site":"left forearm","size":"18 G"},{"kind":"Arterial line","site":"right radial","size":"20 G"}]}"#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        XCTAssertTrue(r.lines.isEmpty)
        XCTAssertEqual(r.devices.map(\.kind), [.piv, .arterial])
        XCTAssertTrue(r.devices.allSatisfy(\.placedIntraop), "old lines were the intraoperative ones")
        XCTAssertEqual(r.devices.first?.site, "forearm-left")
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again.devices.count, 2, "no second migration once devices are saved")
    }

    /// The cardiac demo: an ETT, lines, a PA catheter, VA ECMO to its cart and an IABP, all drawn and handed off.
    func testDiagramAndHandoffForDevices() {
        let r = PatientDemo.cardiac
        XCTAssertTrue(r.mechanicalSupport.contains { $0.kind == .iabp })
        XCTAssertTrue(r.mechanicalSupport.contains { $0.kind.isECMO })
        let m = PatientDiagramModel.items(r, phase: .preop)
        XCTAssertTrue(m.items.contains { $0.id == "airway-ett" }, "arrived intubated")
        XCTAssertEqual(m.cart?.title, "VA ECMO")
        XCTAssertTrue(m.items.contains { $0.label.hasPrefix("PAC") })
        XCTAssertTrue(m.items.contains { $0.label.hasPrefix("IABP") })
        var extubated = r; extubated.airwayAtEnd = "extubated"
        XCTAssertFalse(PatientDiagramModel.items(extubated, phase: .all).items.contains { $0.id == "airway-ett" }, "extubated takes the ETT off the diagram")
        XCTAssertTrue(PatientDiagramModel.items(extubated, phase: .preop).items.contains { $0.id == "airway-ett" }, "the arrival picture keeps it")
        let support = PatientSummary.supportLines(r).map(\.text)
        XCTAssertTrue(support.contains { $0.contains("VA ECMO") }, support.joined(separator: " | "))
        let full = HandoffWriter.text(r)
        XCTAssertTrue(full.contains("LINES & DEVICES"), full)
        XCTAssertTrue(full.contains("IABP"), full)
        XCTAssertTrue(HandoffWriter.shortText(r).contains("Support: "), HandoffWriter.shortText(r))
        let demo = PatientDemo.record
        XCTAssertTrue(PatientSummary.intraopPartLines(demo, "lines").first?.text.contains("PIV 18 G") ?? false, PatientSummary.intraopPartLines(demo, "lines").map(\.text).joined())
        XCTAssertTrue(PatientSummary.arrivalDeviceLines(demo).isEmpty, "the demo's lines went in during the case")
    }

    /// Labs: abnormal values marked for bold red, and the liver line once its section is open.
    func testLabsAndLiverLines() {
        var r = PatientRecord()
        r.sex = .male
        r.labs = ["hb": 9.8, "plt": 210, "k": 5.9, "cr": 1.9, "tbili": 4.2, "inr": 1.2, "na": 127, "albumin": 2.6]
        let l = PatientSummary.labsLine(r)
        XCTAssertNotNil(l)
        XCTAssertTrue(l?.marks.contains("Hb 9.8 L") ?? false, l?.marks.joined(separator: ", ") ?? "")
        XCTAssertTrue(l?.marks.contains("K 5.9 H") ?? false, l?.marks.joined(separator: ", ") ?? "")
        XCTAssertFalse(l?.marks.contains { $0.hasPrefix("Plt") } ?? true, "a normal value is not marked")
        XCTAssertNil(PatientSummary.liverLine(r), "the liver line waits for its section")
        r.labSections = ["liver"]; r.ascites = .slight; r.encephalopathy = .absent
        let liver = PatientSummary.liverLine(r)
        XCTAssertTrue(liver?.text.contains("MELD-Na 27") ?? false, liver?.text ?? "nil")
        XCTAssertTrue(liver?.text.contains("Child-Pugh") ?? false, liver?.text ?? "nil")
    }

    /// A patient saved before 1.6 opens with the new fields empty.
    func testOldSaveDecodes() throws {
        let json = #"{"version":1,"ageYears":70,"procedure":"TKA","problems":["htn"],"smoking":"former"}"#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.ageYears, 70)
        XCTAssertTrue(r.surgeries.isEmpty)
        XCTAssertTrue(r.echoFindings.isEmpty)
        XCTAssertTrue(r.lhc.isEmpty && r.rhc.isEmpty)
        XCTAssertNil(r.currentAirway)
        XCTAssertTrue(r.vent.isEmpty && r.oxygen.isEmpty)
        var full = PatientDemo.record
        full.rhc.co = 4.2; full.currentAirway = "ett"; full.vent.peep = 5
        let round = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(round, full, "every new field survives a save")
    }

    // MARK: Planned procedures

    func testPlannedProceduresFromText() {
        let ecmo = PlannedProcedure.parse("Emergency CABG ×3 on VA ECMO")
        XCTAssertEqual(ecmo.map(\.catalogID), ["cabg"], "on VA ECMO is the patient's state, not a planned cannulation")
        XCTAssertEqual(ecmo.first?.text, "Coronary artery bypass grafting ×3 on VA ECMO")

        let two = PlannedProcedure.parse("CABGx3 + AVR")
        XCTAssertEqual(two.map(\.catalogID), ["cabg", "avr"])
        XCTAssertEqual(two.first?.detail, "×3")

        let knee = PlannedProcedure.parse("L TKA")
        XCTAssertEqual(knee.first?.catalogID, "tka")
        XCTAssertEqual(knee.first?.title, "Left total knee arthroplasty")
        XCTAssertFalse(knee.first?.needsSide ?? true)

        let hernia = PlannedProcedure.parse("inguinal hernia repair")
        XCTAssertTrue(hernia.first?.needsSide ?? false, "a sided procedure with no side asks for it")

        XCTAssertTrue(PlannedProcedure.parse("").isEmpty)
        XCTAssertEqual(PlannedProcedure.parse("zzqx plication").first?.name, "zzqx plication", "unknown text stays as typed")
    }

    func testPlannedProceduresFillRiskInputs() {
        var r = PatientRecord()
        r.setProcedures(PlannedProcedure.parse("lap chole"))
        XCTAssertEqual(r.procedure, "Laparoscopic cholecystectomy")
        XCTAssertTrue(r.highRiskSurgery)
        XCTAssertEqual(r.incision, "Upper abdominal")
        XCTAssertTrue(r.anesthetic.contains("ga"))

        // A clinician's change survives typing a detail, but not a change of procedure.
        r.duration = "> 3 h"
        var list = r.procedures
        list[0].detail = "with cholangiogram"
        r.setProcedures(list)
        XCTAssertEqual(r.duration, "> 3 h")
        XCTAssertEqual(r.procedure, "Laparoscopic cholecystectomy with cholangiogram")
        r.setProcedures(list + PlannedProcedure.parse("L TKA"))
        XCTAssertEqual(r.procedure, "Laparoscopic cholecystectomy with cholangiogram + Left total knee arthroplasty")
        XCTAssertNotEqual(r.duration, nil)

        // Typed procedures leave the inputs alone.
        var t = PatientRecord()
        t.incision = "Peripheral"
        t.setProcedures([PlannedProcedure(name: "zzqx plication")])
        XCTAssertEqual(t.incision, "Peripheral")
        XCTAssertEqual(t.procedure, "zzqx plication")
    }

    func testPlannedProceduresDriveRules() {
        var r = PatientRecord()
        r.setProcedures(PlannedProcedure.parse("AVR"))
        XCTAssertTrue(PatientRules.cardiacSurgery(r))
        XCTAssertTrue(PatientRules.echoFirst(r))
        XCTAssertFalse(PatientRules.prompts(r).contains { $0.id == "rcri" })
        XCTAssertFalse(PatientSummary.procedureLines(r).contains { $0.text.contains("RCRI") })

        var h = PatientRecord()
        h.setProcedures(PlannedProcedure.parse("inguinal hernia repair"))
        XCTAssertFalse(PatientRules.cardiacSurgery(h))
        XCTAssertTrue(PatientSummary.procedureLines(h).contains { $0.label == "Side not set" && $0.alert })

        // A note's procedure becomes items and fills the inputs, but leaves the anesthetic to the note.
        var n = PatientRecord()
        n.anesthetic = ["mac"]
        PatientNote.apply([.procedure("lap chole")], to: &n)
        XCTAssertEqual(n.procedures.first?.catalogID, "lap-chole")
        XCTAssertTrue(n.highRiskSurgery)
        XCTAssertEqual(n.anesthetic, ["mac"])
    }

    func testPlannedProcedureOldSave() throws {
        let json = #"{"procedure":"Right TKA","anesthetic":[]}"#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        XCTAssertTrue(r.procedures.isEmpty)
        XCTAssertEqual(r.recognizedProcedures.map(\.id), ["tka"], "older text is still read for the rules")
        let item = try JSONDecoder().decode(PlannedProcedure.self, from: Data(#"{"name":"x"}"#.utf8))
        XCTAssertEqual(item.detail, "")
    }

    func testSurgeryPickedFromList() {
        var s = PatientSurgery()
        let p = try! XCTUnwrap(ProcedureCatalog.byID("cabg"))
        s.setProcedures([PlannedProcedure(p)])
        XCTAssertTrue(s.intrathoracic, "a cardiac procedure marks the operation")
        XCTAssertEqual(s.text, "Coronary artery bypass grafting")
        XCTAssertEqual(s.procedureID, "cabg")
    }

    /// Several procedures on one date (AVR and CABG together), and saves from before 1.7.
    func testSurgeryWithSeveralProcedures() throws {
        var s = PatientSurgery(date: PatientMonthYear(month: 10, year: 2020))
        s.setProcedures(PlannedProcedure.parse("AVR + CABG x2"))
        XCTAssertEqual(s.procedures.map(\.catalogID), ["avr", "cabg"])
        XCTAssertEqual(s.text, "Aortic valve replacement + Coronary artery bypass grafting ×2 (10/2020)")
        XCTAssertTrue(s.intrathoracic)
        XCTAssertEqual(s.name, "Aortic valve replacement + Coronary artery bypass grafting ×2", "older readers see the whole operation")

        var r = PatientRecord()
        r.surgeries = [s, PatientSurgery(name: "Appendectomy", date: PatientMonthYear(year: 2001))]
        XCTAssertEqual(PatientSummary.historyLines(r).first { $0.label == "Past surgical history" }?.text,
                       "Aortic valve replacement + Coronary artery bypass grafting ×2 (10/2020); Appendectomy (2001)")
        let round = try JSONDecoder().decode(PatientSurgery.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round, s)

        let old = try JSONDecoder().decode(PatientSurgery.self, from: Data(#"{"name":"Total knee arthroplasty","side":"right","procedureID":"tka","date":{"month":3,"year":2019}}"#.utf8))
        XCTAssertEqual(old.procedures.count, 1)
        XCTAssertEqual(old.text, "Right total knee arthroplasty (03/2019)")
    }

    func testECGRhythms() {
        XCTAssertTrue(PatientECG.findings.contains(PatientECG.nsr))
        XCTAssertTrue(PatientECG.rhythms.isSubset(of: Set(PatientECG.findings)))
        XCTAssertFalse(PatientECG.rhythms.contains("Left bundle branch block"), "a conduction finding sits beside the rhythm")
        XCTAssertEqual(PatientECG.adding(PatientECG.nsr, to: ["Atrial fibrillation", "Paced rhythm (ventricular)", "Q waves (old infarct)"]),
                       ["Normal sinus rhythm", "Paced rhythm (ventricular)", "Q waves (old infarct)"], "ventricular pacing stays with sinus rhythm")
        XCTAssertEqual(PatientECG.adding("Atrial fibrillation", to: ["Normal sinus rhythm", "Left bundle branch block"]),
                       ["Left bundle branch block", "Atrial fibrillation"], "a rhythm added later replaces NSR too")
        XCTAssertEqual(PatientECG.adding("Complete heart block", to: ["Normal sinus rhythm"]), ["Complete heart block"])
    }

    /// Many lines: labels never overlap (each column is spaced), and lines to the same vessels run side by side.
    func testDiagramLayoutKeepsLinesAndLabelsApart() {
        var r = PatientDemo.cardiac
        r.devices += ["R IJ triple lumen", "L IJ introducer", "R subclavian CVC", "L brachial PICC", "R fem CVC", "18 rue", "18 lue", "20 lfa"]
            .flatMap { PatientDevices.parse($0)?.devices(placedIntraop: false) ?? [] }
        let m = PatientDiagramModel.items(r, phase: .preop)
        for left in [true, false] {
            let ys = m.items.filter { !$0.label.isEmpty && $0.labelLeft == left }.compactMap { $0.labelAt?.y }.sorted()
            for (a, b) in zip(ys, ys.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 8.4, "labels in the \(left ? "left" : "right") column overlap") }
        }
        XCTAssertTrue(m.items.filter { !$0.label.isEmpty }.allSatisfy { $0.labelAt != nil }, "every label has a place")
        let central = m.items.filter { $0.course.count > 0 && $0.course.contains { abs($0.y - PatientDiagramModel.svc.y) < 0.5 } }
        let ends = Set(central.compactMap { $0.course.first.map { Int(($0.x * 10).rounded()) } })
        XCTAssertEqual(ends.count, central.count, "each line to the SVC has its own lane")
        if let cart = m.cart {
            let right = m.items.filter { !$0.labelLeft }.compactMap(\.labelAt)
            XCTAssertFalse(right.contains { abs($0.y - cart.at.y) < 17 }, "no label under the ECMO cart")
        }
    }
}
