import XCTest
@testable import PeriopSignal

/// 1.8.3, Ben: "Non-obstructive" as an option on the Left Heart Catheterization page, below Dominance.
final class PatientLHC183Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 8))! }
    private func read(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func has(_ s: String) -> Bool { read(s).findings.contains { $0.id == "lhc:nonobstructive" } }

    private func lhc(_ nonObstructive: Bool = true) -> PatientLHC {
        var l = PatientLHC()
        l.dominance = "right"; l.date = PatientMonthYear(month: 6, year: 2026); l.nonObstructive = nonObstructive
        return l
    }

    // MARK: The line

    func testTheLineReadsNonObstructiveCAD() {
        XCTAssertEqual(lhc().summary, "LHC 06/2026, right dominant: non-obstructive CAD")
        XCTAssertEqual(lhc(false).summary, "LHC 06/2026, right dominant")
        var l = lhc()
        l.notes = "collaterals from the RCA"
        XCTAssertEqual(l.summary, "LHC 06/2026, right dominant: non-obstructive CAD; collaterals from the RCA", "notes follow it")
        l.stenosis = ["lad": 30]
        XCTAssertEqual(l.summary, "LHC 06/2026, right dominant: non-obstructive CAD; LAD 30%; collaterals from the RCA", "the vessels stay")
    }

    func testNotesThatSayItAreNotRepeated() {
        for note in ["Non-obstructive", "nonobstructive disease", "Non obstructive CAD, no stents"] {
            var l = lhc()
            l.notes = note
            XCTAssertEqual(l.summary, "LHC 06/2026, right dominant: " + note, note)
        }
        // Ben's current way: typed in Notes, nothing else on.
        var typed = PatientLHC()
        typed.dominance = "right"; typed.notes = "Non-obstructive"
        XCTAssertEqual(typed.summary, "LHC, right dominant: Non-obstructive")
    }

    func testTheOptionAloneIsAnEntry() {
        var l = PatientLHC()
        XCTAssertTrue(l.isEmpty)
        l.nonObstructive = true
        XCTAssertFalse(l.isEmpty)
        XCTAssertEqual(l.summary, "LHC: non-obstructive CAD")
    }

    func testItShowsInTheAssessmentAndTheHandoff() {
        var r = PatientRecord()
        r.lhc = lhc()
        XCTAssertEqual(PatientSummary.assessmentLines(r).first { $0.label == "Coronaries" }?.text, "LHC 06/2026, right dominant: non-obstructive CAD")
    }

    func testSavedRecordsOpenAndRoundTrip() throws {
        var r = PatientRecord()
        r.lhc = lhc()
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertTrue(back.lhc.nonObstructive)
        XCTAssertEqual(back.lhc, r.lhc)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        var inner = try XCTUnwrap(json["lhc"] as? [String: Any])
        inner.removeValue(forKey: "nonObstructive")
        json["lhc"] = inner
        let old = try JSONDecoder().decode(PatientRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(old.lhc.nonObstructive)
        XCTAssertEqual(old.lhc.dominance, "right")
    }

    // MARK: No clinical rule changes

    func testItSetsNoHistoryAndChangesNoScore() {
        var base = PatientRecord()
        base.ageYears = 68
        base.problems = ["htn"]
        var with = base
        with.lhc = lhc()
        XCTAssertEqual(with.problems, base.problems, "no CAD item")
        XCTAssertFalse(with.has("cad"))
        XCTAssertEqual(PatientRules.asaSuggestion(with)?.level, PatientRules.asaSuggestion(base)?.level)
        XCTAssertEqual(PatientRules.cardiacSurgery(with), PatientRules.cardiacSurgery(base))
        XCTAssertEqual(PatientHistoryDetails.cardiacSurgeryText(with), PatientHistoryDetails.cardiacSurgeryText(base))
        // Applying the typed reading changes only the cath.
        var typed = base
        PatientNote.apply([.lhcNonObstructive], to: &typed)
        XCTAssertTrue(typed.lhc.nonObstructive)
        var expected = base
        expected.lhc.nonObstructive = true
        XCTAssertEqual(typed, expected)
    }

    // MARK: Typing

    func testReadWithACathWord() {
        for s in ["LHC non-obstructive", "cath: nonobstructive CAD", "non-obstructive coronary disease on cath", "LHC 06/2026 right dominant, non obstructive",
                  "Coronary angiogram showed nonobstructive disease", "Left heart cath: non-obstructive"] {
            XCTAssertTrue(has(s), s)
        }
    }

    func testNeverWithoutOne() {
        for s in ["non-obstructive CAD", "CCTA: nonobstructive CAD", "CT showed non-obstructive plaque", "PA cath in place, nonobstructive CAD on CT",
                  "Cath done. Non-obstructive CAD on CT."] {
            XCTAssertFalse(has(s), s)
        }
    }

    func testTheCADItemIsNotFiledFromIt() {
        let r = read("cath: nonobstructive CAD")
        XCTAssertFalse(r.findings.contains { $0.id == "problem:cad" }, "the cath's result is not the history item")
        XCTAssertTrue(r.findings.contains { $0.id == "lhc:nonobstructive" })
        XCTAssertTrue(r.other.isEmpty, "and nothing is left over: " + r.other)
        // A CAD told apart from it is still read.
        XCTAssertTrue(read("CAD with stents. LHC non-obstructive.").findings.contains { $0.id == "problem:cad" || $0.id == "problem:pci" })
    }

    func testFilesThroughTheNoteAndTheBar() {
        var r = PatientRecord()
        let reading = read("68M. LHC non-obstructive, right dominant.")
        let f = reading.findings.first { $0.id == "lhc:nonobstructive" }
        XCTAssertEqual(f?.change, .lhcNonObstructive)
        XCTAssertEqual(f.map { PatientNote.status($0, in: r) }, .new)
        PatientNote.apply(reading.findings.map(\.change), to: &r)
        XCTAssertTrue(r.lhc.nonObstructive)
        XCTAssertEqual(f.map { PatientNote.status($0, in: r) }, .recorded)
        let q = QuickAdd.read("LHC non-obstructive", record: PatientRecord(), tab: .preop, now: now)
        XCTAssertTrue(q.findings.contains { $0.id == "lhc:nonobstructive" })
        let intra = QuickAdd.read("LHC non-obstructive", record: PatientRecord(), tab: .intraop, now: now)
        XCTAssertFalse(intra.findings.contains { $0.id == "lhc:nonobstructive" }, "not filed from the OR")
    }

    func testPatternsCompile() {
        for rx in PatientLHC.patterns { XCTAssertNotNil(rx.re, rx.pattern) }
    }
}
