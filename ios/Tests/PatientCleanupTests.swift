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

    /// Run 207, shots 182 and 183: the ⋯ and shield spotlights sat 62 pt under their buttons, over the tabs. They go on
    /// the bar's row: where the item reported itself, or 22 pt under the safe area's top, at the bar's margins.
    @MainActor func testTheBarItemSpotlightsSitOnTheBarsRow() {
        let screen = CGRect(x: 0, y: 0, width: 402, height: 874)
        let more = PatientTipsOverlay.barSpot(.more, reported: nil, safeTop: 62, screen: screen)
        XCTAssertEqual(more.rect.midX, 362.5, accuracy: 0.5)
        XCTAssertEqual(more.rect.midY, 84, accuracy: 0.5, "the middle of the 44 pt bar under the status bar")
        XCTAssertEqual(more.rect.width, 54, accuracy: 0.5, "5 pt clear of the 44 pt glass button")
        let shield = PatientTipsOverlay.barSpot(.shield, reported: nil, safeTop: 62, screen: screen)
        XCTAssertEqual(shield.rect.midX, 38.5, accuracy: 0.5)
        XCTAssertEqual(shield.rect.midY, 84, accuracy: 0.5)

        // Where the item reported itself, when that is on the row and on its side.
        let reported = PatientTipsOverlay.barSpot(.shield, reported: CGRect(x: 25, y: 70, width: 30, height: 30), safeTop: 62, screen: screen)
        XCTAssertEqual(reported.rect.midX, 40, accuracy: 0.5)
        XCTAssertEqual(reported.rect.midY, 85, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(reported.radius, 27)

        // A frame off the row (relative to the item's own host, or run 207's place) or on the wrong side is not used.
        for f in [CGRect(x: 0, y: 0, width: 30, height: 30), CGRect(x: 349, y: 124, width: 44, height: 44),
                  CGRect(x: 10, y: 62, width: 44, height: 44)] {
            let s = PatientTipsOverlay.barSpot(.more, reported: f, safeTop: 62, screen: screen)
            XCTAssertEqual(s.rect.midX, 362.5, accuracy: 0.5, "\(f)")
            XCTAssertEqual(s.rect.midY, 84, accuracy: 0.5, "\(f)")
        }
        XCTAssertFalse(PatientTipsOverlay.plausibleBarItem(CGRect(x: 300, y: 62, width: 90, height: 44), target: .more, safeTop: 62, screen: screen),
                       "Undo and ⋯ together are not the ⋯")
    }

    // MARK: Screenshot seeds stay off the disk

    /// Run 207: a shot that edited the demo patient saved it, and later shots without a seed opened it. A seeded store
    /// neither reads nor writes the file.
    @MainActor func testASeededStoreLeavesTheFileAlone() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("seeded-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("patient.json")

        // Nothing on the phone: a seeded edit, add, room and clear write nothing.
        let seeded = PatientStore(url: url, seed: PatientDemo.Seed(book: PatientCaseBook(cases: [PatientCase(record: PatientDemo.record)]), archived: [], rooms: []))
        XCTAssertEqual(seeded.ageYears, 67)
        seeded.update(discrete: true) { PatientAirway.applyNormalExam(&$0) }
        seeded.setRoom("OR 12", phone: "216-555-0112", remember: true)
        seeded.refresh()
        try await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "the edited demo patient is not saved")
        seeded.clear()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [], "no patient, archive or rooms file")

        // A patient on the phone: an empty seed starts clean and leaves it as it was.
        var kept = PatientCaseBook()
        kept.currentRecord = PatientDemo.ep
        let saved = try kept.encoded()
        try saved.write(to: url)
        XCTAssertEqual(PatientStore(url: url).ageYears, 71, "an unseeded store opens the file")
        let empty = PatientStore(url: url, seed: PatientDemo.Seed(book: PatientCaseBook(), archived: [], rooms: []))
        XCTAssertTrue(empty.isEmpty, "the first-open state, whatever is on the phone")
        XCTAssertFalse(empty.showsCaseRow)
        empty.update(discrete: true) { $0.ageYears = 40 }
        try await Task.sleep(nanoseconds: 900_000_000)
        empty.clear()
        XCTAssertEqual(try Data(contentsOf: url), saved, "the file is untouched")
    }

    #if DEBUG
    @MainActor func testTheEmptySeed() {
        let seed = PatientStore.debugCases("empty")
        XCTAssertNotNil(seed, "-ps.patient empty is a seed")
        XCTAssertEqual(seed?.book.cases.count, 1)
        XCTAssertEqual(seed?.book.current.record.isEmpty, true)
        XCTAssertEqual(seed?.archived.count, 0)
        XCTAssertEqual(PatientStore.debugCases("demo")?.book.current.record.ageYears, 67)
        XCTAssertEqual(PatientStore.debugCases("demo-rooms", select: 2)?.book.cases.count, 3)
        XCTAssertNil(PatientStore.debugCases(""), "no seed: the file")
    }
    #endif

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
