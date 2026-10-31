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
        XCTAssertTrue(PatientSummary.intraopPartLines(r, "events").contains { $0.text == "Extubated" })
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
        XCTAssertEqual(h.first { $0.label == "Smoking & Substances" }?.text, "Current smoker; Social alcohol use", "smoking leads the substance line")
        XCTAssertEqual(h.first { $0.label == "Past surgical history" }?.text, "Appendectomy (2001)")
        XCTAssertEqual(h.first { $0.label == "Current infusions" }?.text, "Heparin at 1200 units/h")
        XCTAssertEqual(h.first { $0.label == "Anesthetic complications" }?.alert, true, "malignant hyperthermia is flagged")
        XCTAssertNil(h.first { $0.label == "Smoking" }, "no separate smoking line")
        r.ecg = ["Atrial fibrillation"]; r.ecgNotes = "rate 88"
        r.echoFindings.lvef = 55
        let a = PatientSummary.assessmentLines(r)
        XCTAssertEqual(a.first { $0.label == "ECG" }?.text, "Atrial fibrillation; rate 88")
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
}
