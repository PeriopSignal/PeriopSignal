import XCTest
@testable import PeriopSignal

/// The 1.9 tools' first-time tips: their own seen-keys, allowed on their tools, and never on the MTP screen.
final class Tips19Tests: XCTestCase {
    func testTeeAndMcsTipsHaveTheirOwnKeysAndAreAllowed() {
        let keys = [TipSet.tour.seenKey, TipSet.referenceSeenKey, TipSet.patient.seenKey, TipSet.tee.seenKey, TipSet.mcs.seenKey]
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(TipSet.allowed(onRouteKey: RefRoute.tee.key))
        XCTAssertTrue(TipSet.allowed(onRouteKey: RefRoute.mcs.key))
        XCTAssertEqual(TipSet.tee.steps.count, 1)
        XCTAssertEqual(TipSet.mcs.steps.count, 1)
    }

    func testNoTipOnTheMtpScreen() {
        XCTAssertFalse(TipSet.allowed(onRouteKey: RefRoute.mtp.key), "MTP is an emergency tool")
    }

    func testTheSetsAreForcedOnlyWhenAsked() {
        XCTAssertEqual(Tips.launch(for: "tee", args: ["ps.tips": "1", "ps.tips.set": "tee"]), .forced(step: 0))
        XCTAssertEqual(Tips.launch(for: "mcs", args: ["ps.tips": "1", "ps.tips.set": "tee"]), .screenshot)
        XCTAssertEqual(Tips.launch(for: "tee", args: [:]), .normal)
    }
}
