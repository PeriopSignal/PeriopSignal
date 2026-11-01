import XCTest
@testable import PeriopSignal

/// My Patient 1.8, phase 1: Undo on every tab and editor (PatientUndoHistory in PatientStore).
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
}
