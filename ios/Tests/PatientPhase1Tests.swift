import XCTest
@testable import PeriopSignal

/// My Patient 1.8, phase 1: Undo on every tab and editor (PatientUndoHistory in PatientStore); Exam normal, Echo
/// normal and "not assessed" in the full handoff; number fields in the order Previous and Next walk.
final class PatientPhase1Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Undo

    @MainActor func testUndoCoalescesABurstOfTyping() {
        let store = PatientStore(url: nil)
        XCTAssertFalse(store.canUndo, "nothing to undo yet")
        // "6", "67", then the weight, each less than a second after the last: one step.
        store.update(now: t0) { $0.ageYears = 6 }
        store.update(now: t0.addingTimeInterval(0.4)) { $0.ageYears = 67 }
        store.update(now: t0.addingTimeInterval(0.9)) { $0.weightKg = 96 }
        XCTAssertTrue(store.canUndo)
        store.undo()
        XCTAssertNil(store.ageYears, "one Undo takes back the whole burst")
        XCTAssertNil(store.weightKg)
        XCTAssertFalse(store.canUndo)

        // A pause of more than a second starts a new step.
        store.update(now: t0.addingTimeInterval(10)) { $0.ageYears = 67 }
        store.update(now: t0.addingTimeInterval(11.5)) { $0.weightKg = 96 }
        store.undo()
        XCTAssertEqual(store.ageYears, 67)
        XCTAssertNil(store.weightKg)
        store.undo()
        XCTAssertNil(store.ageYears)

        // The burst is measured from the last change, so steady typing stays one step.
        for i in 0..<8 { store.update(now: t0.addingTimeInterval(20 + Double(i) * 0.6)) { $0.allergies = String(repeating: "x", count: i + 1) } }
        store.undo()
        XCTAssertEqual(store.record.allergies, "")
        XCTAssertFalse(store.canUndo)
    }

    @MainActor func testDiscreteActionsAreStepsOfTheirOwn() {
        let store = PatientStore(url: nil)
        // Two chip taps a fraction of a second apart: two steps.
        store.update(discrete: true, now: t0) { $0.problems.insert("htn") }
        store.update(discrete: true, now: t0.addingTimeInterval(0.2)) { $0.problems.insert("dm") }
        // Typing right after a tap starts its own step, and does not join the tap's.
        store.update(now: t0.addingTimeInterval(0.4)) { $0.allergies = "P" }
        store.update(now: t0.addingTimeInterval(0.6)) { $0.allergies = "Pen" }
        // A tap right after typing is its own step too.
        store.update(discrete: true, now: t0.addingTimeInterval(0.8)) { $0.mallampati = 2 }
        // A binding marked just before it is written (a chip, toggle or stepper) counts as discrete.
        store.markDiscrete(now: t0.addingTimeInterval(1.0))
        store.update(now: t0.addingTimeInterval(1.0)) { $0.attempts = 1 }
        store.markDiscrete(now: t0.addingTimeInterval(1.1))
        store.update(now: t0.addingTimeInterval(1.1)) { $0.attempts = 2 }

        store.undo()
        XCTAssertEqual(store.record.attempts, 1, "each stepper tap is a step")
        store.undo()
        XCTAssertNil(store.record.attempts)
        XCTAssertEqual(store.record.mallampati, 2)
        store.undo()
        XCTAssertNil(store.record.mallampati)
        XCTAssertEqual(store.record.allergies, "Pen")
        store.undo()
        XCTAssertEqual(store.record.allergies, "", "the typing was one step")
        XCTAssertEqual(store.record.problems, ["htn", "dm"])
        store.undo()
        XCTAssertEqual(store.record.problems, ["htn"])
        store.undo()
        XCTAssertTrue(store.record.problems.isEmpty)
        XCTAssertFalse(store.canUndo)

        // A mark lapses when no change follows within a second (a control that edited something else).
        store.markDiscrete(now: t0.addingTimeInterval(30))
        store.update(now: t0.addingTimeInterval(32)) { $0.allergies = "L" }
        store.update(now: t0.addingTimeInterval(32.3)) { $0.allergies = "Latex" }
        store.undo()
        XCTAssertEqual(store.record.allergies, "", "the stale mark did not split the burst")
    }

    @MainActor func testUndoStepsAreKeptPerCase() {
        let store = PatientStore(url: nil)
        store.update(discrete: true) { $0.ageYears = 50 }
        store.update(discrete: true) { $0.weightKg = 80 }
        let first = store.currentCase.id
        XCTAssertTrue(store.canUndo)

        store.addCase(room: "OR 3")
        XCTAssertFalse(store.canUndo, "a new case has nothing to undo, and never the other case's steps")
        store.update(discrete: true) { $0.ageYears = 71 }
        store.undo()
        XCTAssertNil(store.ageYears, "Undo changes only the current case")
        store.selectCase(first)
        XCTAssertEqual(store.ageYears, 50)
        XCTAssertEqual(store.weightKg, 80, "the first case is as it was left")
        XCTAssertFalse(store.canUndo, "switching cases ends Undo for the case left")

        // Ending a case drops its steps; the next patient in the room starts with none.
        store.update(discrete: true) { $0.heightCm = 180 }
        XCTAssertTrue(store.canUndo)
        store.endCase(keepSummary: false, nextInRoom: true)
        XCTAssertFalse(store.canUndo)
        store.undo()
        XCTAssertTrue(store.isEmpty, "Undo after ending a case brings nothing back into the next one")

        // Ending another case leaves the current case's steps alone.
        let current = store.currentCase.id
        store.update(discrete: true) { $0.ageYears = 33 }
        let other = store.cases.first { $0.id != current }!.id
        store.endCase(other, keepSummary: false)
        XCTAssertEqual(store.currentCase.id, current)
        XCTAssertTrue(store.canUndo)
        store.undo()
        XCTAssertNil(store.ageYears)
    }

    @MainActor func testUndoKeepsFiftySteps() {
        let store = PatientStore(url: nil)
        for i in 1...60 { store.update(discrete: true) { $0.attempts = i } }
        var undone = 0
        while store.canUndo { store.undo(); undone += 1 }
        XCTAssertEqual(undone, PatientUndoHistory.limit)
        XCTAssertEqual(PatientUndoHistory.limit, 50)
        XCTAssertEqual(store.record.attempts, 10, "the oldest steps were dropped")

        var h = PatientUndoHistory()
        let id = UUID()
        var r = PatientRecord()
        for i in 0..<75 { h.willChange(r, case: id, discrete: true, now: t0); r.attempts = i }
        XCTAssertEqual(h.depth(id), 50)
        XCTAssertEqual(h.top(id)?.attempts, 73)
    }

    @MainActor func testClearAndReceiveAreUndoSteps() {
        let store = PatientStore(url: nil)
        store.update(discrete: true) { $0.ageYears = 40 }
        store.clear()
        XCTAssertTrue(store.canUndoClear)
        XCTAssertTrue(store.canUndo)
        store.undo()
        XCTAssertEqual(store.ageYears, 40, "the toolbar's Undo brings a cleared patient back")
        XCTAssertFalse(store.canUndoClear, "and the banner goes")

        store.receive(PatientDemo.record)
        XCTAssertEqual(store.ageYears, 67)
        store.undo()
        XCTAssertEqual(store.ageYears, 40)
        XCTAssertFalse(store.canUndoReceive)

        // The banner's Undo and the toolbar's share one history: no step is left behind to undo twice.
        store.receive(PatientDemo.record)
        store.undoReceive()
        XCTAssertEqual(store.ageYears, 40)
        store.undo()
        XCTAssertNil(store.ageYears, "the next Undo goes on to the step before the patient was received")
    }

    func testHistoryJoinsOnlyTheSameCase() {
        var h = PatientUndoHistory()
        let a = UUID(), b = UUID()
        var r = PatientRecord()
        h.willChange(r, case: a, discrete: false, now: t0)
        r.ageYears = 1
        h.willChange(r, case: b, discrete: false, now: t0.addingTimeInterval(0.1))
        h.willChange(r, case: a, discrete: false, now: t0.addingTimeInterval(0.2))
        XCTAssertEqual(h.depth(a), 2, "a change to another case in between ends the burst")
        XCTAssertEqual(h.depth(b), 1)
        h.keep(only: [a])
        XCTAssertFalse(h.canUndo(b))
        h.clear(a)
        XCTAssertFalse(h.canUndo(a))
        XCTAssertNil(h.pop(a))
    }
    // MARK: One-tap normals

    func testExamNormalSetsWhatItsCaptionSays() throws {
        var r = PatientRecord()
        r.ageYears = 50
        r.mallampati = 4
        r.airwaySigns = ["mouth", "tmd", "neck", "edentulous", "beard"]
        r.dentition = "Loose upper incisor"
        XCTAssertFalse(PatientAirway.isNormalExam(r))
        PatientAirway.applyNormalExam(&r)
        XCTAssertEqual(r.mallampati, 2)
        XCTAssertEqual(r.airwaySigns, ["beard"], "the signs it rules out go; the others stay")
        XCTAssertEqual(r.dentition, "Intact")
        XCTAssertTrue(r.airwayExamReviewed)
        XCTAssertTrue(PatientAirway.isNormalExam(r))
        for word in ["Mallampati II", "mouth opening", "thyromental distance", "neck range of motion", "intact teeth"] {
            XCTAssertTrue(PatientAirway.normalExamCaption.contains(word), word)
        }
        let lines = PatientSummary.airwayLines(r)
        XCTAssertTrue(lines.contains { $0.text.hasPrefix("Mallampati II") })
        XCTAssertEqual(lines.first { $0.label == "Exam" }?.text, "Mouth opening and thyromental distance adequate; full neck range of motion")
        XCTAssertEqual(lines.first { $0.label == "Teeth" }?.text, "Intact")

        // Editable after: a sign ticked later replaces its normal finding.
        r.airwaySigns.insert("neck")
        XCTAssertEqual(PatientAirway.reviewedNormals(r), "Mouth opening and thyromental distance adequate")
        r.airwaySigns.insert("mouth")
        XCTAssertEqual(PatientAirway.reviewedNormals(r), "Thyromental distance adequate")
        XCTAssertFalse(PatientAirway.isNormalExam(r))
        r.airwayExamReviewed = false
        XCTAssertNil(PatientAirway.reviewedNormals(r))

        // The new field reads from a record saved before it, and round-trips.
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data("{\"mallampati\": 2}".utf8))
        XCTAssertFalse(old.airwayExamReviewed)
        var reviewed = PatientRecord(); reviewed.airwayExamReviewed = true
        let back = try JSONDecoder().decode(PatientRecord.self, from: try JSONEncoder().encode(reviewed))
        XCTAssertTrue(back.airwayExamReviewed)
        XCTAssertFalse(reviewed.isEmpty)
    }

    func testEchoNormalSetsWhatItsCaptionSays() {
        var e = PatientEcho()
        e.lvef = 60
        e.aortic.prosthesis = ""
        e.applyNormal()
        XCTAssertEqual(e.lv, .normal)
        XCTAssertEqual(e.rv, .normal)
        for v in [e.mitral, e.tricuspid, e.aortic] {
            XCTAssertEqual(v.regurgitation, .normal)
            XCTAssertEqual(v.stenosis, .normal)
        }
        XCTAssertEqual(e.lvef, 60, "the EF typed stays")
        XCTAssertTrue(e.isNormalPreset)
        XCTAssertEqual(e.summary, "LV EF 60%, normal; RV function normal; No significant valve disease")
        XCTAssertTrue(PatientEcho.normalCaption.contains("LV and RV function normal"))

        // Editable after: a valve graded later shows, and the summary no longer says there is none.
        e.mitral.regurgitation = .moderate
        XCTAssertFalse(e.isNormalPreset)
        XCTAssertEqual(e.phrases, ["LV EF 60%, normal", "RV function normal", "Moderate MR"])
        var noneGraded = PatientEcho()
        noneGraded.lv = .normal
        XCTAssertFalse(noneGraded.noValveDisease, "valves not graded are not called normal")
    }

    @MainActor func testPresetsAreOneUndoStep() {
        let store = PatientStore(url: nil)
        store.update(discrete: true) { $0.ageYears = 50 }
        store.update(discrete: true) { PatientAirway.applyNormalExam(&$0) }
        store.update(discrete: true) { $0.intraopEcho.applyNormal() }
        store.undo()
        XCTAssertTrue(store.record.intraopEcho.isEmpty)
        XCTAssertEqual(store.record.mallampati, 2)
        store.undo()
        XCTAssertNil(store.record.mallampati)
        XCTAssertFalse(store.record.airwayExamReviewed)
        XCTAssertEqual(store.ageYears, 50)
    }

    func testFullHandoffSaysNotAssessed() throws {
        var r = PatientRecord()
        r.ageYears = 50; r.sex = .female
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        let full = HandoffWriter.text(r)
        XCTAssertTrue(full.contains("Echo: not assessed"), full)
        XCTAssertTrue(full.contains("Airway exam: not assessed"), full)
        let assessment = try XCTUnwrap(full.range(of: "ASSESSMENT"))
        let airway = try XCTUnwrap(full.range(of: "AIRWAY"))
        XCTAssertLessThan(assessment.lowerBound, try XCTUnwrap(full.range(of: "Echo: not assessed")).lowerBound)
        XCTAssertLessThan(airway.lowerBound, try XCTUnwrap(full.range(of: "Airway exam: not assessed")).lowerBound)
        XCTAssertEqual(full.components(separatedBy: "not assessed").count, 3, "no intraoperative echo is expected for a cholecystectomy")
        XCTAssertFalse(HandoffWriter.shortText(r).contains("not assessed"), "the short handoff stays short")

        // Touched, even by one sign or the presets: no longer "not assessed".
        var touched = r
        touched.airwaySigns = ["beard"]
        touched.echoFindings.applyNormal()
        let t = HandoffWriter.text(touched)
        XCTAssertFalse(t.contains("not assessed"), t)
        XCTAssertTrue(t.contains("Echo: LV function normal; RV function normal; No significant valve disease"), t)
        var normal = r
        PatientAirway.applyNormalExam(&normal)
        XCTAssertTrue(HandoffWriter.text(normal).contains("Exam: Mouth opening and thyromental distance adequate; full neck range of motion"))
        XCTAssertFalse(HandoffWriter.text(normal).contains("Airway exam: not assessed"))

        // With an ETT in place the exam is not asked, so it is not called missing.
        var ett = r
        ett.currentAirway = "ett"
        XCTAssertFalse(HandoffWriter.text(ett).contains("Airway exam: not assessed"))

        // Cardiac surgery expects an intraoperative echo.
        let cardiac = HandoffWriter.text(PatientDemo.cardiac)
        let intraop = try XCTUnwrap(cardiac.range(of: "INTRAOPERATIVE"))
        let echo = try XCTUnwrap(cardiac.range(of: "Echo: not assessed", range: intraop.upperBound..<cardiac.endIndex))
        XCTAssertLessThan(intraop.lowerBound, echo.lowerBound)
        var recorded = PatientDemo.cardiac
        recorded.intraopEcho.lv = .severe
        XCTAssertFalse(HandoffWriter.text(recorded).contains("Echo: not assessed"))

        // The demo patient has both: nothing changes, and the short handoff is still one screen.
        XCTAssertFalse(HandoffWriter.text(PatientDemo.record).contains("not assessed"))
        XCTAssertLessThanOrEqual(HandoffWriter.shortText(PatientDemo.record).components(separatedBy: "\n").count, 14)
    }
    // MARK: Number entry

    func testLabEntryOrderFollowsTheFishbone() {
        let keys = PatientLabs.entryOrder(.main).map(\.key)
        XCTAssertEqual(Array(keys.prefix(4)), ["wbc", "hb", "hct", "plt"], "WBC → Hb → Hct → Plt")
        XCTAssertEqual(Array(keys.dropFirst(4).prefix(7)), ["na", "k", "cl", "hco3", "bun", "cr", "glucose"], "Na → K → Cl → HCO₃ → BUN → Cr → Glu")
        XCTAssertEqual(keys.count, PatientLabs.tests(.main).count, "every main lab once")
        XCTAssertEqual(Set(keys), Set(PatientLabs.tests(.main).map(\.key)))
        XCTAssertEqual(PatientLabs.entryOrder(.cardiac), PatientLabs.tests(.cardiac), "the other groups keep the catalog's order")
        XCTAssertEqual(PatientLabs.summary(PatientDemo.record).items.map(\.key), ["hb", "plt", "k", "cr", "glucose"], "the summary keeps the catalog's order")
    }

    @MainActor func testIntraopLabsChainTheNewestSet() {
        var r = PatientRecord()
        XCTAssertTrue(IntraopLabsEditor.fieldOrder(r).isEmpty, "no set, no fields")
        r.intraopLabs = [IntraopLabSet(time: Date())]
        let order = IntraopLabsEditor.fieldOrder(r)
        XCTAssertEqual(order.first, "iop.ph")
        XCTAssertTrue(order.contains("iop.be"), "base excess keeps its place, beside its ± button")
        XCTAssertEqual(order.last, "iop.act")
        XCTAssertEqual(Set(order).count, order.count, "every field once")
    }
}
