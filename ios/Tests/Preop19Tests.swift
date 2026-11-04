import XCTest
@testable import PeriopSignal

/// 1.9 (Ben's Wanted Changes, the Preprocedure tab): the Cardiopulmonary Evaluation's Intrathoracic procedure answer, the
/// RCRI hidden for cardiac surgery only, the cardiac workup chips, and the problem tiles.
final class Preop19Tests: XCTestCase {

    private func adult() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male
        return r
    }

    private func hasRCRI(_ r: PatientRecord) -> Bool { PatientRules.prompts(r).contains { $0.id == "rcri" } }

    // MARK: RCRI and cardiac surgery

    /// The predicate is the procedure catalog's own `cardiac` flag (for a recognized procedure) or a keyword in a typed
    /// procedure's name; it hides the RCRI prompt. A noncardiac thoracic operation keeps it.
    func testLobectomyKeepsRCRI() {
        var r = adult()
        r.setProcedures(PlannedProcedure.parse("VATS lobectomy"))
        XCTAssertFalse(r.recognizedProcedures.isEmpty, "a lobectomy is in the procedure list")
        XCTAssertFalse(r.recognizedProcedures.contains(where: \.cardiac), "the catalog does not flag a lung resection cardiac")
        XCTAssertFalse(PatientRules.cardiacSurgery(r))
        XCTAssertTrue(hasRCRI(r))
        // The catalog sets the incision and high-risk surgery for it, so the RCRI opens with the surgery ticked.
        XCTAssertEqual(r.incision, "Intrathoracic")
        XCTAssertTrue(r.highRiskSurgery)
        XCTAssertTrue(PatientRules.prefill("rcri", r).on.contains("surgery"))
        // The answer changes none of that.
        PatientPreop.setIntrathoracic(true, &r)
        XCTAssertFalse(PatientRules.cardiacSurgery(r))
        XCTAssertTrue(hasRCRI(r))
        XCTAssertEqual(PatientPreop.intrathoracicSetLine(r), "Incision: Intrathoracic · High-risk surgery")
    }

    func testCardiacSurgeryHidesRCRI() {
        for p in ["CABG", "AVR", "Aortic valve replacement", "MVR", "TAVR"] {
            var r = adult()
            r.setProcedures(PlannedProcedure.parse(p))
            XCTAssertTrue(PatientRules.cardiacSurgery(r), p)
            XCTAssertFalse(hasRCRI(r), p)
            // The other adult scores stay.
            XCTAssertTrue(PatientRules.prompts(r).contains { $0.id == "ariscat" }, p)
            XCTAssertTrue(PatientRules.prompts(r).contains { $0.id == "stopbang" }, p)
            // The answer does not bring it back.
            PatientPreop.setIntrathoracic(true, &r)
            XCTAssertFalse(hasRCRI(r), p + " with Intrathoracic procedure: Yes")
        }
        // A typed cardiac operation, not in the catalog, is read by its words.
        var t = adult()
        t.procedure = "Redo sternotomy, MVR"
        XCTAssertTrue(PatientRules.cardiacSurgery(t))
        XCTAssertFalse(hasRCRI(t))
        // A previous cardiac operation in the history does not hide it: the RCRI is for those patients.
        var h = adult()
        h.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        h.surgeries = [PatientSurgery(name: "CABG", intrathoracic: true)]
        XCTAssertFalse(PatientRules.cardiacSurgery(h))
        XCTAssertTrue(hasRCRI(h))
    }

    // MARK: Intrathoracic procedure

    func testIntrathoracicYesSetsOnlyWhatIsUnset() {
        var r = adult()
        PatientPreop.setIntrathoracic(true, &r)
        XCTAssertEqual(r.intrathoracicProcedure, true)
        XCTAssertEqual(r.incision, "Intrathoracic")
        XCTAssertTrue(r.highRiskSurgery)

        // An incision already chosen stays; high-risk surgery is set.
        var a = adult()
        a.incision = "Upper abdominal"
        PatientPreop.setIntrathoracic(true, &a)
        XCTAssertEqual(a.incision, "Upper abdominal")
        XCTAssertTrue(a.highRiskSurgery)

        // High-risk surgery already on, incision unset.
        var b = adult()
        b.highRiskSurgery = true
        PatientPreop.setIntrathoracic(true, &b)
        XCTAssertEqual(b.incision, "Intrathoracic")
        XCTAssertTrue(b.highRiskSurgery)
    }

    func testIntrathoracicNoAndClearSetNothingElse() {
        var r = adult()
        PatientPreop.setIntrathoracic(false, &r)
        XCTAssertEqual(r.intrathoracicProcedure, false)
        XCTAssertNil(r.incision)
        XCTAssertFalse(r.highRiskSurgery)
        XCTAssertNil(PatientPreop.intrathoracicSetLine(r))

        // Yes, then No: the inputs it set stay for the clinician to change (nothing is taken back silently).
        PatientPreop.setIntrathoracic(true, &r)
        PatientPreop.setIntrathoracic(false, &r)
        XCTAssertEqual(r.intrathoracicProcedure, false)
        XCTAssertEqual(r.incision, "Intrathoracic")
        PatientPreop.setIntrathoracic(nil, &r)
        XCTAssertNil(r.intrathoracicProcedure)
    }

    func testIntrathoracicAnswerSurvivesSaving() throws {
        var r = adult()
        PatientPreop.setIntrathoracic(true, &r)
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.intrathoracicProcedure, true)
        let none = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(adult()))
        XCTAssertNil(none.intrathoracicProcedure)
    }

    // MARK: Cardiac workup chips

    func testWorkupChipsAreInBensOrderAndEmptyAtFirst() {
        let items = PatientPreop.workup(adult())
        XCTAssertEqual(items.map(\.title), ["ECG", "Echo", "Left heart cath", "Right heart cath", "Carotid US", "Radial artery US",
                                           "Pulmonary function tests", "TEE screen", "Mechanical support"])
        XCTAssertTrue(items.allSatisfy { !$0.filled })
        XCTAssertFalse(PatientPreop.workupHasData(adult()))
        XCTAssertEqual(items.map(\.key), ["workup:ecg", "workup:echo", "workup:lhc", "workup:rhc", "workup:carotid", "workup:radial",
                                         "workup:pft", "workup:tee", "devices:support"])
    }

    func testWorkupChipsShowTheirSummaryOnceFilled() {
        var r = adult()
        r.ecg = ["Atrial fibrillation"]
        var echo = PatientEcho()
        echo.study = "TTE"; echo.lv = .mild; echo.lvef = 50
        r.echoFindings = echo
        var rhc = PatientRHC()
        rhc.ra = 12; rhc.co = 3.8
        r.rhc = rhc
        let items = PatientPreop.workup(r)
        func item(_ id: String) -> PreopWorkupItem { items.first { $0.id == id }! }
        XCTAssertEqual(item("ecg").summary, "Atrial fibrillation")
        XCTAssertTrue(item("echo").filled)
        XCTAssertEqual(item("rhc").summary, "RA 12, CO 3.8")
        XCTAssertFalse(item("lhc").filled)
        XCTAssertFalse(item("tee").filled, "an unscreened TEE screen reads + TEE screen")
        XCTAssertTrue(PatientPreop.workupHasData(r), "once any is filled the workup shows open")
    }

    func testTEEScreenAndSupportChipsFlagWhatNeedsAttention() {
        var r = adult()
        r.teeScreen.set("dysphagia", true)
        let tee = PatientPreop.workup(r).first { $0.id == "tee" }!
        XCTAssertTrue(tee.filled)
        XCTAssertTrue(tee.alert)
        XCTAssertEqual(tee.summary, PatientTEE.status(r))

        var s = adult()
        s.devices = ["L fem IABP 7.5 Fr 1:1"].flatMap { PatientDevices.parse($0)?.devices(placedIntraop: false) ?? [] }
        let support = PatientPreop.workup(s).first { $0.id == "support" }!
        XCTAssertTrue(support.filled)
        XCTAssertTrue(support.alert)
    }

    // MARK: Problem tiles

    func testTilesLeadWithPediatricForAChildAndHideObstetricForAMan() {
        var r = adult()
        XCTAssertEqual(PatientPreop.tileSystems(r).first?.id, "cv")
        XCTAssertFalse(PatientPreop.tileSystems(r).contains { $0.id == "ob" }, "a man gets no Obstetric tile")
        r.sex = .female
        XCTAssertTrue(PatientPreop.tileSystems(r).contains { $0.id == "ob" })
        r.sex = nil
        XCTAssertTrue(PatientPreop.tileSystems(r).contains { $0.id == "ob" }, "shown while the sex is not recorded")
        r.sex = .male
        r.systemOther["ob"] = "Prior cesarean"
        XCTAssertTrue(PatientPreop.tileSystems(r).contains { $0.id == "ob" }, "kept when the page holds something")
        var c = PatientRecord()
        c.ageYears = 6; c.sex = .female
        XCTAssertEqual(PatientPreop.tileSystems(c).first?.id, "peds")
    }

    func testTileWordsAreTheHistorysSentence() {
        var r = adult()
        let cv = PatientCatalog.systems.first { $0.id == "cv" }!
        XCTAssertEqual(PatientPreop.tileWords(cv, r), "")
        r.problems = ["htn"]
        r.systemNotes["cv"] = "DES to LAD 2023"
        let words = PatientPreop.tileWords(cv, r)
        XCTAssertTrue(words.hasPrefix(String(HistorySections.items(cv, r).first!.prefix(1)).uppercased()), words)
        XCTAssertTrue(words.hasSuffix("DES to LAD 2023"), words)
        r.systemOther["cv"] = "Marfan features"
        XCTAssertTrue(PatientPreop.tileWords(cv, r).contains("Marfan features"))
    }

    func testSummaryIsOfferedOnceSomethingIsRecorded() {
        XCTAssertFalse(PatientPreop.summaryAvailable(PatientRecord()))
        XCTAssertTrue(PatientPreop.summaryAvailable(adult()))
    }
}
