import XCTest
import SwiftUI
@testable import PeriopSignal

/// 1.12 helper C: wayfinding and layout. Note 10 (the case and the tabs pinned at the top once the tab has scrolled; the
/// case under every page's title) and note 17 (a box folds once it is filled in).
final class C112Tests: XCTestCase {
    // MARK: - Records

    /// A record with something in every box that folds.
    private func filled() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = 96
        r.setProcedures(PlannedProcedure.parse("Laparoscopic sigmoid colectomy"))
        r.problems = ["htn", "copd"]
        r.nkda = true
        r.homeMeds = [PatientMed(name: "Metoprolol", dose: "25 mg twice daily")]
        r.medFlags = ["statin"]
        r.cardiacSymptomsAnswer = false
        r.ecg = ["Normal sinus rhythm"]
        r.asaClass = 3
        r.mask = "easy"; r.intubation = "easy"; r.airwayAtEnd = "extubated"
        r.infusions = [PatientInfusion(drug: "Phenylephrine", rate: "0.3 mcg/kg/min")]
        r.fluids = ["crystalloid": 1000]
        return r
    }

    private let allBoxes = PatientBox.allCases

    // MARK: - Note 17: which box holds a value

    func testAnEmptyRecordHoldsNothingInAnyBox() {
        for box in allBoxes { XCTAssertFalse(box.summary(PatientRecord()).holdsValue, "\(box)") }
    }

    func testEveryBoxOfTheFilledRecordHoldsAValue() {
        let r = filled()
        for box in allBoxes { XCTAssertTrue(box.summary(r).holdsValue, "\(box)") }
    }

    func testEachBoxHoldsOnlyItsOwnEntries() {
        var r = PatientRecord()
        r.nkda = true
        XCTAssertTrue(PatientBox.allergies.summary(r).holdsValue)
        for box in allBoxes where box != .allergies { XCTAssertFalse(box.summary(r).holdsValue, "\(box) is not filled by an allergy answer") }
        r = PatientRecord()
        r.medFlags = ["anticoagulant"]
        XCTAssertTrue(PatientBox.flagged.summary(r).holdsValue)
        r = PatientRecord()
        r.fluids = ["ebl": 300]
        XCTAssertTrue(PatientBox.fluids.summary(r).holdsValue)
        XCTAssertFalse(PatientBox.infusions.summary(r).holdsValue)
    }

    func testAWorkedOutLineDoesNotMakeABoxFilled() {
        // An adult having an operation gets a worked-out cardiac evaluation line, and a suggested ASA class: neither is an entry.
        var r = PatientRecord()
        r.ageYears = 67
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        r.problems = ["copd", "htn", "dm"]
        XCTAssertFalse(PatientBox.cardio.summary(r).holdsValue, "the stepwise result is not entered")
        XCTAssertFalse(PatientBox.asa.summary(r).holdsValue, "a suggested class is not a chosen one")
    }

    func testTheAirwayBoxIsFilledByTheCourseOrByHowTheAirwayIsLeft() {
        var r = PatientRecord()
        r.airwayAtEnd = "extubated"
        XCTAssertTrue(PatientBox.airway.summary(r).holdsValue)
        r = PatientRecord()
        r.mask = "easy"
        XCTAssertTrue(PatientBox.airway.summary(r).holdsValue)
        // An airway the patient arrives with is not a course in the room.
        r = PatientRecord()
        r.currentAirway = "ett"
        XCTAssertFalse(PatientBox.airway.summary(r).holdsValue)
    }

    func testThePreopDripsAreInTheInfusionsBoxAsItListsThem() {
        var r = PatientRecord()
        r.homeInfusions = [PatientInfusion(drug: "Norepinephrine", rate: "0.05 mcg/kg/min")]
        let s = PatientBox.infusions.summary(r)
        XCTAssertTrue(s.holdsValue)
        XCTAssertTrue(s.lines.contains { $0.text.contains("Norepinephrine") })
        // ... and as the medications box does.
        XCTAssertTrue(PatientBox.medications.summary(r).lines.contains { $0.text.contains("Norepinephrine") })
    }

    // MARK: - Note 17: the collapsed summary

    func testAlertsAndAbnormalValuesAreNeverTruncated() {
        XCTAssertNil(PatientBox.lineLimit(PatientSummary.Line("Allergies", "Latex (anaphylaxis)", alert: true)))
        XCTAssertNil(PatientBox.lineLimit(PatientSummary.Line(nil, "Hb 8.1 L", marks: ["Hb 8.1 L"])))
        XCTAssertEqual(PatientBox.lineLimit(PatientSummary.Line("Cardiovascular", "hypertension; CAD")), 2)
    }

    func testTheDemoPatientsAlertsFoldIntoRedLinesThatAreNotCut() {
        let r = PatientDemo112Layout.layout
        let allergies = PatientBox.allergies.summary(r).lines
        XCTAssertTrue(allergies.allSatisfy { $0.alert && PatientBox.lineLimit($0) == nil }, "an allergy is an alert")
        XCTAssertTrue(allergies.contains { $0.text.contains("Latex (anaphylaxis)") })
        let drips = PatientBox.medications.summary(r).lines.first { $0.label == "Current infusions" }
        XCTAssertNotNil(drips)
        XCTAssertNil(PatientBox.lineLimit(try! XCTUnwrap(drips)), "a drip before the case is an alert line")
        let symptoms = PatientBox.cardio.summary(r).lines.first { $0.label == "Cardiac symptoms" }
        XCTAssertEqual(symptoms?.alert, true)
        let airway = PatientBox.airway.summary(r).lines
        XCTAssertEqual(airway.count, 1)
        XCTAssertTrue(airway[0].alert, "a difficult airway is red")
        XCTAssertNil(PatientBox.lineLimit(airway[0]))
    }

    func testTheFlaggedBoxMarksTheFlagsThatNeedAnAction() throws {
        var r = PatientRecord()
        r.medFlags = ["statin", "anticoagulant"]
        let line = try XCTUnwrap(PatientBox.flagged.summary(r).lines.first)
        let anticoagulant = try XCTUnwrap(PatientCatalog.medFlags.first { $0.id == "anticoagulant" }).label
        let statin = try XCTUnwrap(PatientCatalog.medFlags.first { $0.id == "statin" }).label
        XCTAssertTrue(line.text.contains(anticoagulant) && line.text.contains(statin))
        XCTAssertEqual(line.marks, [anticoagulant], "only the flag that needs action is marked, so the line is not cut")
        XCTAssertNil(PatientBox.lineLimit(line))
    }

    func testTheCardioBoxCarriesTheStressTestAndAPositiveOneIsAnAlert() throws {
        var r = PatientRecord()
        r.stressTest = PatientStressTest(kind: .dobutamine, result: .positive)
        let lines = PatientBox.cardio.summary(r).lines
        let stress = try XCTUnwrap(lines.first { $0.label == "Stress test" })
        XCTAssertTrue(stress.alert)
        XCTAssertNil(PatientBox.lineLimit(stress))
    }

    func testTheAsaBoxHasTheChosenClassAndTheFunctionalCapacity() {
        var r = PatientRecord()
        r.asaClass = 3
        r.mets = "lt4"
        let lines = PatientBox.asa.summary(r).lines
        XCTAssertTrue(lines.contains { $0.label == "ASA physical status" && $0.text.contains("ASA III") })
        let fc = lines.first { $0.label == "Functional capacity" }
        XCTAssertEqual(fc?.alert, true, "under 4 METs is flagged")
    }

    func testALineLabelledLikeTheBoxLosesItsLabelAndKeepsItsAlert() {
        let line = PatientSummary.Line("Allergies", "Latex (anaphylaxis)", alert: true, marks: ["Latex (anaphylaxis)"])
        let drawn = PatientBoxSummaryCard.drawn(title: "Allergies", lines: [line, PatientSummary.Line("Code status", "Full code")])
        XCTAssertNil(drawn[0].label)
        XCTAssertTrue(drawn[0].alert)
        XCTAssertEqual(drawn[0].marks, ["Latex (anaphylaxis)"])
        XCTAssertEqual(drawn[1].label, "Code status", "another label stays")
    }

    func testTheSpokenLabelNamesTheBoxAndItsLines() {
        let said = PatientBoxSummaryCard.spokenLabel(title: "Allergies", lines: [PatientSummary.Line("Allergies", "Latex (anaphylaxis)", alert: true)])
        XCTAssertEqual(said, "Allergies, collapsed. Allergies: Latex (anaphylaxis)")
    }

    // MARK: - Note 17: when a box folds

    func testASavedPatientOpensWithItsFilledBoxesFoldedAndAnEmptyOneOpen() {
        let r = filled()
        var s = PatientBoxCollapse()
        s.start(r)
        for box in allBoxes { XCTAssertTrue(s.isCollapsed(box, r), "\(box)") }

        var half = PatientRecord()
        half.nkda = true
        half.fluids = ["ebl": 200]
        var t = PatientBoxCollapse()
        t.start(half)
        XCTAssertTrue(t.isCollapsed(.allergies, half))
        XCTAssertTrue(t.isCollapsed(.fluids, half))
        XCTAssertFalse(t.isCollapsed(.demographics, half), "an empty box stays open")

        var empty = PatientBoxCollapse()
        empty.start(PatientRecord())
        for box in allBoxes { XCTAssertFalse(empty.isCollapsed(box, PatientRecord()), "a new patient starts expanded") }
    }

    func testAnEmptyBoxNeverCollapses() {
        var s = PatientBoxCollapse()
        s.start(filled())
        // The record loses the allergy answer (Undo): the box is open though it was folded.
        var r = filled()
        r.nkda = false
        XCTAssertFalse(s.isCollapsed(.allergies, r))
        // Done on an empty box does nothing.
        var t = PatientBoxCollapse()
        t.done(.allergies, r)
        XCTAssertFalse(t.isCollapsed(.allergies, r))
        XCTAssertFalse(t.isCollapsed(.allergies, filled()))
    }

    func testTappingIntoAnotherBoxFoldsTheFilledOnesAndNotTheEmptyOnes() {
        var r = PatientRecord()
        r.nkda = true
        r.fluids = ["ebl": 200]
        var s = PatientBoxCollapse()
        s.touched(.demographics, r)     // an empty box is touched: the filled ones fold
        XCTAssertTrue(s.isCollapsed(.allergies, r))
        XCTAssertTrue(s.isCollapsed(.fluids, r))
        XCTAssertFalse(s.isCollapsed(.demographics, r))
        XCTAssertFalse(s.isCollapsed(.cardio, r), "an empty box never folds")
    }

    func testExpandingABoxFoldsTheOthersAndOpensIt() {
        let r = filled()
        var s = PatientBoxCollapse()
        s.start(r)
        s.touched(.problems, r)
        XCTAssertFalse(s.isCollapsed(.problems, r))
        for box in allBoxes where box != .problems { XCTAssertTrue(s.isCollapsed(box, r), "\(box)") }
        // Another one: the first folds again.
        s.touched(.cardio, r)
        XCTAssertFalse(s.isCollapsed(.cardio, r))
        XCTAssertTrue(s.isCollapsed(.problems, r))
    }

    func testTheBoxesOwnDoneFoldsItAlone() {
        let r = filled()
        var s = PatientBoxCollapse()
        s.touched(.allergies, r)        // the others fold, allergies open
        s.touched(.asa, r)              // asa open, allergies folded
        XCTAssertFalse(s.isCollapsed(.asa, r))
        s.done(.asa, r)
        XCTAssertTrue(s.isCollapsed(.asa, r))
        XCTAssertTrue(s.isCollapsed(.allergies, r), "Done changes no other box")
    }

    func testNothingFoldsWhileAKeyboardIsUpAndItFoldsWhenTheKeyboardGoes() {
        let r = filled()
        var s = PatientBoxCollapse()
        s.keyboardChanged(up: true)
        s.touched(.allergies, r)
        for box in allBoxes where box != .allergies { XCTAssertFalse(s.isCollapsed(box, r), "\(box) waits for the keyboard") }
        s.keyboardChanged(up: false)
        for box in allBoxes where box != .allergies { XCTAssertTrue(s.isCollapsed(box, r), "\(box)") }
        XCTAssertFalse(s.isCollapsed(.allergies, r))
    }

    func testTheKeyboardsOwnerWaitsAndTheRestFoldOnceItIsKnown() {
        let r = filled()
        var s = PatientBoxCollapse()
        s.keyboardChanged(up: true)
        s.touched(.demographics, r)
        s.keyboardOwner(.allergies)     // the field with the keyboard is in the allergies box
        XCTAssertFalse(s.isCollapsed(.allergies, r), "the box with the keyboard does not fold under it")
        XCTAssertTrue(s.isCollapsed(.problems, r))
        XCTAssertFalse(s.isCollapsed(.demographics, r))
        s.keyboardChanged(up: false)
        XCTAssertTrue(s.isCollapsed(.allergies, r), "it folds once the keyboard has gone")
        // A field outside the boxes (the quick-add bar's): every box waiting folds.
        var q = PatientBoxCollapse()
        q.keyboardChanged(up: true)
        q.touched(.demographics, r)
        q.keyboardOwner(nil)
        XCTAssertTrue(q.isCollapsed(.allergies, r))
    }

    func testScrollingChangesNothing() {
        let r = filled()
        var s = PatientBoxCollapse()
        s.start(r)
        s.touched(.demographics, r)
        let before = s
        // The state machine has no scroll input: the same record read again, as it is while the tab scrolls, is the same state.
        for box in allBoxes { _ = s.isCollapsed(box, r) }
        XCTAssertEqual(s, before)
    }

    func testCollapsingIsOffInTheScreenshotRunsThatPredateItUnlessAsked() {
        XCTAssertTrue(PatientBox.collapsingEnabled(patientSeed: "", collapseFlag: false), "the app and the tests")
        XCTAssertFalse(PatientBox.collapsingEnabled(patientSeed: "demo", collapseFlag: false), "a screenshot run keeps the expanded boxes")
        XCTAssertTrue(PatientBox.collapsingEnabled(patientSeed: "demo", collapseFlag: true), "-ps.patient.collapse 1")
    }

    func testAJumpToABoxNamesIt() {
        XCTAssertEqual(PatientBox.forAnchor("allergies"), .allergies)
        XCTAssertEqual(PatientBox.forAnchor("homemeds"), .medications)
        XCTAssertEqual(PatientBox.forAnchor("infusions"), .medications)
        XCTAssertEqual(PatientBox.forJump(PatientJumpID(anchor: "cardio").key), .cardio)
        XCTAssertNil(PatientBox.forJump(PatientJumpID(section: .workup).key), "a section is not a box")
        XCTAssertNil(PatientBox.forAnchor("labs"), "a card that opens a page does not fold")
    }

    // MARK: - Note 17: the screen's boxes

    @MainActor func testTheScreenFoldsAndOpensBoxesAsTheRulesSay() {
        let r = filled()
        let boxes = PatientBoxes(enabled: true)
        boxes.start(r)
        XCTAssertTrue(boxes.isCollapsed(.allergies, r))
        boxes.touch(.allergies, r)
        XCTAssertFalse(boxes.isCollapsed(.allergies, r))
        XCTAssertTrue(boxes.isCollapsed(.demographics, r))
        boxes.done(.allergies, r)
        XCTAssertTrue(boxes.isCollapsed(.allergies, r))
        // A jump to a box opens it.
        boxes.expand(.cardio, r)
        XCTAssertFalse(boxes.isCollapsed(.cardio, r))
    }

    @MainActor func testTheScreenOpensAfterAJumpOnlyOnce() {
        let r = filled()
        let boxes = PatientBoxes(enabled: true)
        boxes.startOnce(r)
        boxes.touch(.problems, r)
        boxes.startOnce(r)      // the tab appears again (back from a page): the boxes stay as they are
        XCTAssertFalse(boxes.isCollapsed(.problems, r))
        boxes.start(r)          // another case, or a patient received: as a patient opening
        XCTAssertTrue(boxes.isCollapsed(.problems, r))
    }

    @MainActor func testTurnedOffTheBoxesNeverCollapse() {
        let r = filled()
        let boxes = PatientBoxes(enabled: false)
        boxes.start(r)
        boxes.touch(.allergies, r)
        for box in allBoxes { XCTAssertFalse(boxes.isCollapsed(box, r)) }
    }

    @MainActor func testTheTouchedBoxStaysWhereItWasWhenABoxAboveItFolds() async {
        let r = filled()
        let boxes = PatientBoxes(enabled: true)
        let scrolled = expectation(description: "scrolled")
        var calls: [(id: String, anchor: UnitPoint)] = []
        boxes.scroll = { id, anchor in calls.append((id, anchor)); scrolled.fulfill() }
        boxes.viewport = { (top: 100, bottom: 900) }
        boxes.frames = [.demographics: CGRect(x: 0, y: 150, width: 335, height: 300), .allergies: CGRect(x: 0, y: 500, width: 335, height: 200)]
        boxes.start(PatientRecord())            // nothing folded yet: both boxes are open
        boxes.touch(.allergies, r)              // demographics, above it, folds
        await fulfillment(of: [scrolled], timeout: 3)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.id, PatientBoxes.pinID(.allergies))
        XCTAssertEqual(Double(calls.first?.anchor.y ?? -1), (500.0 - 100.0) / 800.0, accuracy: 0.0001)
    }

    @MainActor func testNothingScrollsWhenOnlyBoxesBelowFold() async throws {
        let r = filled()
        let boxes = PatientBoxes(enabled: true)
        var calls = 0
        boxes.scroll = { _, _ in calls += 1 }
        boxes.viewport = { (top: 100, bottom: 900) }
        boxes.frames = [.allergies: CGRect(x: 0, y: 200, width: 335, height: 200), .problems: CGRect(x: 0, y: 450, width: 335, height: 300)]
        boxes.start(PatientRecord())
        boxes.touch(.allergies, r)              // problems, below it, folds: allergies does not move
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(calls, 0)
    }

    // MARK: - Note 10: the pinned row

    func testTheRowPinsOnceTheCaseRowAndTheTabControlHaveGoneUnderTheBar() {
        let pinY: CGFloat = 108
        let row = PatientPinned.rowHeight
        // At the top: the control is well below the bar.
        XCTAssertEqual(PatientPinned.flags(tabsBottom: 160, barY: 330, pinY: pinY, rowHeight: row).tabs, false)
        // Its bottom edge passes the bar: the row shows.
        XCTAssertEqual(PatientPinned.flags(tabsBottom: 100, barY: 270, pinY: pinY, rowHeight: row).tabs, true)
        // Before anything has been measured nothing is pinned.
        let unmeasured = PatientPinned.flags(tabsBottom: .infinity, barY: .infinity, pinY: -.infinity, rowHeight: row)
        XCTAssertFalse(unmeasured.tabs)
        XCTAssertFalse(unmeasured.chips)
    }

    func testTheChipsPinUnderTheRowAndNotBeforeTheirBarReachesIt() {
        let pinY: CGFloat = 108
        let row = PatientPinned.rowHeight
        // The row is pinned; the chip bar is still below the room the row takes: the chips stay in the page.
        XCTAssertEqual(PatientPinned.flags(tabsBottom: 100, barY: pinY + row + 4, pinY: pinY, rowHeight: row).chips, false)
        // Its bar has reached that room: the chips pin, so they do not jump.
        XCTAssertEqual(PatientPinned.flags(tabsBottom: 100, barY: pinY + row - 4, pinY: pinY, rowHeight: row).chips, true)
        // With no row (the tab control still showing) the chips pin at the top as before 1.12.
        XCTAssertEqual(PatientPinned.flags(tabsBottom: 200, barY: pinY - 4, pinY: pinY, rowHeight: row).chips, true)
        XCTAssertEqual(PatientPinned.flags(tabsBottom: 200, barY: pinY + 4, pinY: pinY, rowHeight: row).chips, false)
    }

    func testTheRowIsAboutFortyFourPointsAndGrowsALittleWithTheText() {
        let scale = PS.textScale
        defer { PS.textScale = scale }
        PS.textScale = 1
        XCTAssertEqual(PatientPinned.rowHeight, 44)
        PS.textScale = 1.5
        XCTAssertGreaterThan(PatientPinned.rowHeight, 44)
        XCTAssertLessThan(PatientPinned.rowHeight, 60)
    }

    func testAJumpClearsTheRowAndTheChipBar() {
        let scale = PS.textScale
        defer { PS.textScale = scale }
        PS.textScale = 1
        XCTAssertEqual(PatientJumpID.clearance, 56 + 44, "the anchor clears the 54-pt chip bar and the 44-pt row")
        PS.textScale = 1.25
        XCTAssertGreaterThan(PatientJumpID.clearance, 56 * 1.25 + 44)
    }

    func testTheTabButtonsSayPreopIntraopSummaryAndVoiceOverTheFullNames() {
        XCTAssertEqual(PatientTab.allCases.map(\.pinnedTitle), ["Preop", "Intraop", "Summary"])
        XCTAssertEqual(PatientTab.allCases.map(\.title), ["Preoperative", "Intraoperative", "Summary & Handoff"])
    }

    func testTwoCasesShowAsChipsWithTheOpenOneMarked() {
        let a = PatientCase(number: 1, record: filled(), room: "OR 66")
        let b = PatientCase(number: 2, room: "OR 67")
        let chips = PatientPinned.caseChips(cases: [a, b], currentID: a.id, showsRow: true)
        XCTAssertEqual(chips.map(\.label), ["OR 66", "OR 67"])
        XCTAssertEqual(chips.map(\.open), [true, false])
        XCTAssertTrue(chips[0].spoken.hasPrefix("OR 66, "), "VoiceOver hears the room and the procedure")
        XCTAssertEqual(chips[1].spoken, "OR 67")
        XCTAssertNil(PatientPinned.singleLabel(current: a, showsRow: true))
    }

    func testOneCaseWithoutARoomShowsTheSingleLabel() {
        let only = PatientCase(number: 1)
        XCTAssertTrue(PatientPinned.caseChips(cases: [only], currentID: only.id, showsRow: false).isEmpty)
        XCTAssertEqual(PatientPinned.singleLabel(current: only, showsRow: false), "Case 1")
    }

    @MainActor func testACaseChipOpensTheCaseAsTheFullRowDoes() {
        let store = PatientStore(url: nil)
        store.update { $0.ageYears = 50 }
        let first = store.currentCase.id
        store.addCase(room: "OR 12")
        let second = store.currentCase.id
        PatientRoomsUI.shared.ended = "OR 7"
        defer { PatientRoomsUI.shared.ended = nil }
        let target = try! XCTUnwrap(store.cases.first { $0.id == first })
        PatientRoomsBar.open(target, in: store)
        XCTAssertEqual(store.currentCase.id, first)
        XCTAssertNil(PatientRoomsUI.shared.ended, "the banner for a case just ended goes, as on the full row")
        XCTAssertEqual(store.ageYears, 50)
        // The open case again: nothing happens.
        PatientRoomsUI.shared.ended = "OR 9"
        PatientRoomsBar.open(target, in: store)
        XCTAssertEqual(PatientRoomsUI.shared.ended, "OR 9")
        XCTAssertNotEqual(first, second)
    }

    @MainActor func testTheCaptionUnderAPageTitleNamesTheOpenCase() {
        let store = PatientStore(url: nil)
        XCTAssertEqual(PatientPageTitle.caption(store.currentCase), "Case 1", "one case and no room reads Case 1")
        store.setRoom("OR 66", phone: "")
        XCTAssertEqual(PatientPageTitle.caption(store.currentCase), "OR 66")
        store.addCase(room: "OR 67")
        XCTAssertEqual(PatientPageTitle.caption(store.currentCase), "OR 67", "the caption follows the open case")
        XCTAssertLessThanOrEqual(PatientPageTitle.captionSize, 12, "small")
    }

    // MARK: - A record saved by 1.11 still opens

    func testARecordSavedBy111OpensAndFoldsItsFilledBoxes() throws {
        let json = #"{"ageYears":71,"sex":"female","nkda":true,"problems":["htn"],"mets":"ge4","asaClass":2,"infusions":[{"drug":"Phenylephrine","rate":"0.2 mcg/kg/min"}]}"#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        var s = PatientBoxCollapse()
        s.start(r)
        XCTAssertTrue(s.isCollapsed(.demographics, r))
        XCTAssertTrue(s.isCollapsed(.allergies, r))
        XCTAssertTrue(s.isCollapsed(.problems, r))
        XCTAssertTrue(s.isCollapsed(.asa, r))
        XCTAssertTrue(s.isCollapsed(.infusions, r))
        XCTAssertFalse(s.isCollapsed(.cardio, r))
        XCTAssertFalse(s.isCollapsed(.fluids, r))
    }
}
