import XCTest
@testable import PeriopSignal

/// 1.12 groundwork: the record's new fields decode from a record saved before them and survive a round trip.
final class Groundwork112Tests: XCTestCase {
    func testARecordSavedBefore112StillOpens() throws {
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"procedure":"Lap chole","labs":{"k":4.1}}"#.utf8))
        XCTAssertEqual(old.procedure, "Lap chole")
        XCTAssertEqual(old.labs["k"], 4.1)
        XCTAssertTrue(old.imaging.isEmpty)
        XCTAssertEqual(old.handoffExtras, [])
        XCTAssertEqual(old.moreLabs, PatientMoreLabs())
        XCTAssertEqual(old.notableMeds, PatientNotableMeds())
        XCTAssertEqual(old.chestXray, PatientChestXray())
    }

    func testTheNewFieldsRoundTrip() throws {
        var r = PatientRecord()
        r.imaging.ct = "CT chest 10/2026: 4.8 cm ascending aorta"
        r.handoffExtras = ["imaging:ct", "preop:alb"]
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again.imaging.ct, "CT chest 10/2026: 4.8 cm ascending aorta")
        XCTAssertEqual(again.handoffExtras, ["imaging:ct", "preop:alb"])
        XCTAssertEqual(again, r)
        XCTAssertFalse(r.isEmpty)
    }
}
