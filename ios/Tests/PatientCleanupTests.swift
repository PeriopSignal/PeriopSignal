import XCTest
@testable import PeriopSignal

/// 1.8.1's cleaner My Patient: the row of cases shows only when it earns its place, the first-time tips step through,
/// skip and are remembered (and come back from ⋯ → Show Tips), and Clear still leaves Undo in the bar.
final class PatientCleanupTests: XCTestCase {

    // MARK: The row of cases

    func testOneCaseWithoutARoomHidesTheRow() {
        XCTAssertFalse(PatientCaseBook().showsCaseRow, "a first-time user's one empty case")
        let filled = PatientCaseBook(cases: [PatientCase(record: PatientDemo.record)])
        XCTAssertFalse(filled.showsCaseRow, "a patient alone is no reason for the row")
        var spaces = PatientCaseBook()
        spaces.setRoom("   ", phone: " ")
        XCTAssertFalse(spaces.showsCaseRow, "spaces are not a room or a phone")
    }

    func testOneCaseWithARoomOrPhoneShowsTheRow() {
        var room = PatientCaseBook()
        room.setRoom("OR 12", phone: "")
        XCTAssertEqual(room.cases.count, 1)
        XCTAssertTrue(room.showsCaseRow)
        var phone = PatientCaseBook()
        phone.setRoom("", phone: "216-555-0112")
        XCTAssertTrue(phone.showsCaseRow, "a phone alone: its chip carries Call and Text")
    }

    func testTwoCasesShowTheRow() {
        var book = PatientCaseBook()
        book.add()
        XCTAssertEqual(book.cases.count, 2)
        XCTAssertTrue(book.showsCaseRow, "two unnamed cases: Case 1 and Case 2")
        book.remove(book.current.id)
        XCTAssertEqual(book.cases.count, 1)
        XCTAssertFalse(book.showsCaseRow, "back to one case without a room")
        XCTAssertTrue(PatientDemo.rooms().book.showsCaseRow, "the screenshot rooms")
    }

    @MainActor func testTheStoreShowsTheRowAsItsCasesChange() {
        let store = PatientStore(url: nil)
        XCTAssertFalse(store.showsCaseRow)
        store.addCase()
        XCTAssertTrue(store.showsCaseRow)
        store.endCase(keepSummary: false)
        XCTAssertFalse(store.showsCaseRow)
        store.setRoom("CVOR 3", phone: "216-555-0103")
        XCTAssertTrue(store.showsCaseRow)
        store.setRoom("", phone: "")
        XCTAssertFalse(store.showsCaseRow)
    }

    // MARK: First-time tips

    func testTheFourSteps() {
        XCTAssertEqual(PatientTips.steps.map(\.target), [.quickAdd, .tabs, .more, .shield])
        XCTAssertEqual(PatientTips.steps.map { $0.target.inScrollView }, [true, true, false, false])
        XCTAssertTrue(PatientTips.steps[0].text.hasPrefix("Type the patient in one line"))
        XCTAssertTrue(PatientTips.steps[1].text.contains("Summary & Handoff"))
        XCTAssertTrue(PatientTips.steps[2].text.contains("End case"))
        XCTAssertTrue(PatientTips.steps[3].text.contains("No names, record numbers or dates of birth"))
        for s in PatientTips.steps { XCTAssertLessThan(s.text.count, 160, "short enough for a card: \(s.text)") }
        XCTAssertEqual(PatientTips.seenKey, "ps.tips.patient.v1")
    }

    func testTheFirstTimeTheyStepThroughToDone() {
        var t = PatientTips()
        XCTAssertFalse(t.isShowing)
        t.appear(storedSeen: false)
        XCTAssertEqual(t.step, 0)
        XCTAssertEqual(t.current?.target, .quickAdd)
        XCTAssertEqual(t.progress, "1 of 4")
        XCTAssertFalse(t.isLast)
        t.next()
        XCTAssertEqual(t.current?.target, .tabs)
        t.appear(storedSeen: false)
        XCTAssertEqual(t.step, 1, "coming back to the tab keeps the step")
        t.next()
        XCTAssertEqual(t.current?.target, .more)
        t.next()
        XCTAssertEqual(t.current?.target, .shield)
        XCTAssertTrue(t.isLast)
        XCTAssertEqual(t.progress, "4 of 4")
        XCTAssertFalse(t.seen, "not seen until Done or Skip")
        t.next()   // Done
        XCTAssertFalse(t.isShowing)
        XCTAssertNil(t.current)
        XCTAssertTrue(t.seen)
        t.appear(storedSeen: true)
        XCTAssertFalse(t.isShowing, "not again on their own")
        t.next()
        XCTAssertFalse(t.isShowing, "Next with nothing showing does nothing")
    }

    func testSkipClosesThemSeen() {
        var t = PatientTips()
        t.appear(storedSeen: false)
        t.next()
        t.skip()
        XCTAssertFalse(t.isShowing)
        XCTAssertTrue(t.seen)
        t.appear(storedSeen: false)
        XCTAssertFalse(t.isShowing, "skipped in this launch: not again")
    }

    func testTheSeenFlagIsRememberedOnThisPhone() {
        let name = "PatientCleanupTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var first = PatientTips()
        first.appear(storedSeen: defaults.bool(forKey: PatientTips.seenKey))
        XCTAssertTrue(first.isShowing, "never seen on this phone")
        first.skip()
        defaults.set(first.seen, forKey: PatientTips.seenKey)   // what My Patient's @AppStorage keeps

        var next = PatientTips()
        next.appear(storedSeen: defaults.bool(forKey: PatientTips.seenKey))
        XCTAssertFalse(next.isShowing, "the next launch")
        XCTAssertTrue(next.seen)
    }

    func testShowTipsAgainFromTheMenu() {
        var t = PatientTips(seen: true)
        t.appear(storedSeen: true)
        XCTAssertFalse(t.isShowing)
        t.showAgain()
        XCTAssertEqual(t.step, 0)
        t.next()
        t.next()
        t.showAgain()
        XCTAssertEqual(t.step, 0, "from the start again")
        t.skip()
        XCTAssertTrue(t.seen)
        XCTAssertFalse(t.isShowing)
    }

    func testScreenshotRunsShowThemOnlyWhenAsked() {
        var plain = PatientTips()
        plain.appear(storedSeen: false, launch: .screenshot)
        XCTAssertFalse(plain.isShowing, "every other shot stays uncovered")

        var asked = PatientTips()
        asked.appear(storedSeen: true, launch: .forced(step: 2))
        XCTAssertEqual(asked.step, 2, "-ps.tips 1 -ps.tips.step 3, seen or not")
        XCTAssertEqual(asked.current?.target, .more)
        asked.skip()
        asked.appear(storedSeen: true, launch: .forced(step: 2))
        XCTAssertFalse(asked.isShowing, "once per launch")

        var high = PatientTips()
        high.appear(storedSeen: false, launch: .forced(step: 9))
        XCTAssertEqual(high.step, PatientTips.steps.count - 1, "clamped to the last step")
        var low = PatientTips()
        low.appear(storedSeen: false, launch: .forced(step: -3))
        XCTAssertEqual(low.step, 0)
    }

    @MainActor func testTheArrowEndsAtItsTarget() {
        let p = PatientTipsOverlay.arrowPath(from: CGPoint(x: 50, y: 200), to: CGPoint(x: 40, y: 120))
        let box = p.boundingRect
        XCTAssertEqual(box.minY, 120, accuracy: 0.5, "the head is at the target")
        XCTAssertEqual(box.maxY, 200, accuracy: 0.5)
        XCTAssertFalse(p.isEmpty)
    }

    // MARK: Clear and Undo

    @MainActor func testClearingStillOffersUndoInTheBar() {
        let store = PatientStore(url: nil)
        store.update(discrete: true) { $0.ageYears = 58; $0.weightKg = 81 }
        XCTAssertFalse(store.isEmpty)
        store.clear()
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(store.canUndoClear, "Clear keeps the patient for Undo")
        XCTAssertTrue(store.canUndo, "the ↩ in the bar shows (the banner is gone)")
        store.undo()
        XCTAssertEqual(store.ageYears, 58)
        XCTAssertEqual(store.weightKg, 81)
        XCTAssertFalse(store.canUndoClear)
        XCTAssertFalse(store.isEmpty)
    }
}
