import XCTest
@testable import PeriopSignal

/// The MTP tally (1.9): ratio, calcium and lab prompts, cryo fibrinogen and 4F-PCC, against reference.json "mtp".
final class MtpTests: XCTestCase {
    private func data() throws -> MtpData {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        return try XCTUnwrap(ReferenceLoader.decode(try Data(contentsOf: url)).mtp, "mtp decodes")
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testDraftUntilReviewed() throws {
        let d = try data()
        XCTAssertNil(d.reviewed)
        XCTAssertEqual(d.cryoPool.default, 5)
        XCTAssertFalse(d.product("fibrinogen")?.citrated ?? true, "factor concentrates don't count toward calcium")
        XCTAssertTrue(d.product("cryo")?.citrated ?? false)
    }

    func testPlateletDoseReadsOneToOneToOne() throws {
        let d = try data()
        var s = MtpState(started: t0, data: d)
        for i in 0..<6 {
            _ = s.add("prbc", at: t0.addingTimeInterval(Double(i)))
            _ = s.add("plasma", at: t0.addingTimeInterval(Double(i)))
        }
        _ = s.add("platelets", at: t0.addingTimeInterval(10))
        XCTAssertEqual(MtpCalc.ratio(s).text, "1 : 1 : 1")
        s.plateletUnits = 4
        XCTAssertEqual(MtpCalc.ratio(s).text, "1 : 1 : 0.7")
    }

    func testCalciumWithTheFirstUnitThenEveryFour() throws {
        let d = try data()
        var s = MtpState(started: t0, data: d)
        XCTAssertFalse(MtpCalc.calcium(s, data: d).due)
        _ = s.add("prbc", at: t0.addingTimeInterval(1))
        XCTAssertTrue(MtpCalc.calcium(s, data: d).due, "with the first citrated unit")
        _ = s.add("calcium", detail: "chloride", at: t0.addingTimeInterval(2))
        XCTAssertFalse(MtpCalc.calcium(s, data: d).due)
        _ = s.add("plasma", at: t0.addingTimeInterval(3))
        _ = s.add("cryo", at: t0.addingTimeInterval(4))          // a pool counts as 1
        _ = s.add("fibrinogen", qty: 4, at: t0.addingTimeInterval(5))  // a concentrate doesn't count
        _ = s.add("platelets", at: t0.addingTimeInterval(6))
        XCTAssertEqual(MtpCalc.calcium(s, data: d).since, 3)
        XCTAssertFalse(MtpCalc.calcium(s, data: d).due)
        let wb = s.add("wholeBlood", at: t0.addingTimeInterval(7))
        XCTAssertTrue(MtpCalc.calcium(s, data: d).due, "4 citrated units since the last dose")
        s.remove(wb.id)
        XCTAssertFalse(MtpCalc.calcium(s, data: d).due, "removing a tap corrects the count")
    }

    func testIcaLevels() throws {
        let d = try data()
        XCTAssertEqual(MtpCalc.ica(1.15, data: d), .give)
        XCTAssertEqual(MtpCalc.ica(0.85, data: d), .urgent)
        XCTAssertEqual(MtpCalc.ica(1.25, data: d), .normal)
    }

    func testLabsAfterFourRbcOrThirtyMinutes() throws {
        let d = try data()
        var s = MtpState(started: t0, data: d)
        for i in 0..<3 { _ = s.add("prbc", at: t0.addingTimeInterval(Double(i))) }
        XCTAssertFalse(MtpCalc.labs(s, data: d, now: t0.addingTimeInterval(600)).due)
        _ = s.add("prbc", at: t0.addingTimeInterval(4))
        XCTAssertTrue(MtpCalc.labs(s, data: d, now: t0.addingTimeInterval(600)).due)
        _ = s.add("labs", at: t0.addingTimeInterval(700))
        XCTAssertFalse(MtpCalc.labs(s, data: d, now: t0.addingTimeInterval(800)).due)
        XCTAssertTrue(MtpCalc.labs(s, data: d, now: t0.addingTimeInterval(700 + 1800)).due)
    }

    func testCryoFibrinogenFollowsThePoolSize() throws {
        let d = try data()
        var s = MtpState(started: t0, data: d)
        _ = s.add("cryo", at: t0)
        XCTAssertEqual(MtpCalc.cryoFibrinogenGrams(s, data: d), 0.75, accuracy: 0.001)
        s.cryoPool = 10
        XCTAssertEqual(MtpCalc.cryoFibrinogenGrams(s, data: d), 1.5, accuracy: 0.001)
        // Rossaint 2023: 3–4 g ≈ 15–20 single-donor units at 150–200 mg each; at the 150 mg minimum, 4 g is 27.
        XCTAssertEqual(MtpCalc.cryoUnits(forGrams: 3, data: d), 20)
    }

    func testPccBandsAndWeightCap() throws {
        let d = try data()
        XCTAssertNil(MtpCalc.pcc(inr: 1.8, weightKg: 80, data: d))
        XCTAssertEqual(MtpCalc.pcc(inr: 3, weightKg: 80, data: d)?.iu, 2000)
        XCTAssertEqual(MtpCalc.pcc(inr: 6, weightKg: 80, data: d)?.iuPerKg, 35)
        XCTAssertEqual(MtpCalc.pcc(inr: 7, weightKg: 120, data: d)?.iu, 5000)
        XCTAssertEqual(MtpCalc.pcc(inr: 7, weightKg: 120, data: d)?.capped, true)
    }

    func testTxaLateAfterThreeHours() throws {
        let d = try data()
        var s = MtpState(started: t0, data: d)
        s.injury = t0
        XCTAssertFalse(MtpCalc.txaLate(s, data: d, now: t0.addingTimeInterval(2 * 3600)))
        XCTAssertTrue(MtpCalc.txaLate(s, data: d, now: t0.addingTimeInterval(3.5 * 3600)))
        s.txaContext = "obstetric"
        XCTAssertFalse(MtpCalc.txaLate(s, data: d, now: t0.addingTimeInterval(3.5 * 3600)))
    }

    func testStateSurvivesEncoding() throws {
        let d = try data()
        var s = MtpState(started: t0, data: d)
        _ = s.add("prbc", at: t0)
        s.ica = 1.05
        let back = try JSONDecoder().decode(MtpState.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }
}
