import XCTest
@testable import PeriopSignal

/// 1.9 review (integration): where two branches' fixes meet. The labs' Anemia and a child's age, the device fills beside
/// a record saved by 1.8.3 and a fistula drawn with no place, the vertebral caution beside a limb alert, a denied
/// anaphylaxis in typed allergies, a current smoker and "No significant medical history", and a Lines & devices block
/// the user emptied.
final class Review19IntegrationTests: XCTestCase {

    /// One change as PatientStore.update makes it: the change, then the fills.
    private func change(_ r: inout PatientRecord, _ body: (inout PatientRecord) -> Void) {
        let before = r
        body(&r)
        PatientCrossFill.apply(before: before, after: &r)
    }

    // MARK: Anemia and a child's age

    /// A lab-filled Anemia, then an age under 15 typed: nothing is checked by itself under 15, so the labs' Anemia is
    /// set aside (and "No significant medical history" given back); correcting the Hb then leaves nothing behind.
    func testALabFilledAnemiaIsNotKeptForAChild() {
        var r = PatientRecord()
        r.sex = .female
        r.noHistory = true
        change(&r) { $0.labs["hb"] = 11 }
        XCTAssertTrue(r.has("anemia"), "below 12 with no age yet")
        XCTAssertFalse(r.noHistory)
        change(&r) { $0.ageYears = 8 }
        XCTAssertFalse(r.has("anemia"), "a child of 8: not checked by itself")
        XCTAssertFalse(r.labProblems.contains("anemia"))
        XCTAssertTrue(r.noHistory, "given back with the Anemia")
        change(&r) { $0.labs["hb"] = 13 }
        XCTAssertFalse(r.has("anemia"))
        XCTAssertTrue(r.noHistory)
        XCTAssertEqual(r.fills, PatientFills())

        // A record already holding the labs' Anemia beside a child's age: a Hb typed again takes it back.
        var old = PatientRecord()
        old.sex = .female; old.ageYears = 8; old.labs["hb"] = 11
        old.problems = ["anemia"]; old.labProblems = ["anemia"]
        change(&old) { $0.labs["hb"] = 13 }
        XCTAssertFalse(old.has("anemia"))

        // An adult age typed digit by digit still keeps the fill's Anemia, and the user's own Anemia is never touched.
        var a = PatientRecord()
        a.sex = .female; a.ageYears = 45; a.problems = ["htn"]
        change(&a) { $0.labs["hb"] = 10.5 }
        for age in [4.0, 46.0] { change(&a) { $0.ageYears = age } }
        XCTAssertTrue(a.has("anemia"))
        XCTAssertTrue(a.labProblems.contains("anemia"))
        XCTAssertFalse(a.fills.anemiaAside)
        var u = PatientRecord()
        u.sex = .female; u.ageYears = 45; u.problems = ["anemia"]
        change(&u) { $0.labs["hb"] = 10.5 }
        change(&u) { $0.ageYears = 8 }
        XCTAssertTrue(u.has("anemia"), "the user's")
        // Set aside for a child, then Anemia recorded by the user: an adult age later does not double or claim it.
        var s = PatientRecord()
        s.sex = .female; s.ageYears = 45; s.problems = ["htn"]
        change(&s) { $0.labs["hb"] = 10.5 }
        change(&s) { $0.ageYears = 8 }
        XCTAssertTrue(s.fills.anemiaAside)
        change(&s) { _ = $0.problems.insert("anemia") }
        XCTAssertFalse(s.fills.anemiaAside)
        change(&s) { $0.ageYears = 46 }
        XCTAssertTrue(s.has("anemia"))
        XCTAssertFalse(s.labProblems.contains("anemia"), "the user's, not the labs'")
    }
}
