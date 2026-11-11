import XCTest
@testable import PeriopSignal

/// 1.9 screenshot harness fixes: the deep-link keys My Patient opens (shots 340, 393 and 394 showed the tab instead of
/// their page) and the jump anchors (444 and 445 landed the History chips box 70 pt low).
final class PatientDeepLink19Tests: XCTestCase {

    // MARK: Deep-link keys

    func testEditorsOpenByName() {
        XCTAssertEqual(PatientDeepLink.parse("medications"), .editor(.medications), "quick add and saved links open the Medications & Allergies editor")
        XCTAssertEqual(PatientDeepLink.parse("medications")?.editor, .medications)
        XCTAssertEqual(PatientDeepLink.parse("details"), .editor(.details))
        XCTAssertEqual(PatientDeepLink.parse("procedure"), .editor(.procedure))
        XCTAssertEqual(PatientDeepLink.parse("demographics"), .editor(.demographics))
        XCTAssertEqual(PatientDeepLink.parse("history"), .editor(.history))
        XCTAssertEqual(PatientDeepLink.parse("assessment"), .editor(.assessment))
        XCTAssertEqual(PatientDeepLink.parse("intraop"), .editor(.intraop))
        XCTAssertEqual(PatientDeepLink.parse("plan"), .editor(.plan))
        // The editor, not the reference page: a box's "airway" link resolves the reference route before this.
        XCTAssertEqual(PatientDeepLink.parse("airway"), .editor(.airway))
    }

    func testPagesOpenByPrefix() {
        XCTAssertEqual(PatientDeepLink.parse("workup:tee"), .editor(.workup("tee")), "shots 340 and 341")
        XCTAssertEqual(PatientDeepLink.parse("workup:surgeries"), .editor(.workup("surgeries")))
        XCTAssertEqual(PatientDeepLink.parse("intraop:lines"), .editor(.intraopPart("lines")))
        XCTAssertEqual(PatientDeepLink.parse("devices:support"), .editor(.devices("support")))
        XCTAssertEqual(PatientDeepLink.parse("system:cardio"), .editor(.system("cardio")))
        // A prefix with nothing after it names no page.
        XCTAssertNil(PatientDeepLink.parse("workup:"))
        XCTAssertNil(PatientDeepLink.parse("system:"))
    }

    func testReferenceRoutesAndTheRest() {
        XCTAssertEqual(PatientDeepLink.parse("score:rcri"), .route(.score("rcri")))
        XCTAssertEqual(PatientDeepLink.parse("neuraxial"), .route(.neuraxial))
        XCTAssertNil(PatientDeepLink.parse("score:rcri")?.editor, "a reference route is not an editor")
        XCTAssertEqual(PatientDeepLink.parse("handoff"), .summary)
        XCTAssertEqual(PatientDeepLink.parse("note"), .note)
        XCTAssertEqual(PatientDeepLink.parse("receive"), .receive)
        XCTAssertNil(PatientDeepLink.parse(""), "no key: nothing opens")
        XCTAssertNil(PatientDeepLink.parse("nonsense"))
    }

    /// The push is tried again while the path is still empty: soon after the first frame, and late enough for a slow
    /// launch, but before the shortest open-key shot (12 s) takes its picture.
    func testOpenRetriesFitTheShotWait() {
        let delays = PatientView.openRetryDelays
        XCTAssertGreaterThanOrEqual(delays.count, 3)
        XCTAssertEqual(delays, delays.sorted())
        XCTAssertLessThanOrEqual(delays[0], 0.5, "the first push comes right after the stack's first frame")
        XCTAssertGreaterThanOrEqual(delays.last ?? 0, 3.0, "the last retry waits out a slow launch")
        XCTAssertLessThanOrEqual(delays.reduce(0, +), 9.0, "all within the shortest open-key shot's wait, with time to draw")
    }

    // MARK: Jump anchors

    func testJumpAnchorClearsThePinnedBarOnly() {
        let scale = PS.textScale
        defer { PS.textScale = scale }
        PS.textScale = 1
        // The pinned bar is about 54 pt (8 pt padding, a 13.5 pt chip, 8 pt padding, the hairline); the anchor clears
        // it and a small margin, not the 44 pt inline title the scroll view's content is already under. 1.12 (note 10): the
        // slim row of cases and tabs (about 44 pt) is pinned above the chips once the tab has scrolled, so the anchor
        // clears both (was 54 to 70; C112Tests.testAJumpClearsTheRowAndTheChipBar).
        XCTAssertGreaterThanOrEqual(PatientJumpID.clearance, 54 + 44)
        XCTAssertLessThanOrEqual(PatientJumpID.clearance, 70 + 44)
        PS.textScale = 1.25
        XCTAssertGreaterThan(PatientJumpID.clearance, 56 * 1.2 + 44, "a larger text size makes the bar taller, so the anchor grows with it")
    }
}
