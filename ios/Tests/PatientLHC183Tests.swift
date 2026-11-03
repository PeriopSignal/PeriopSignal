import XCTest
@testable import PeriopSignal

/// 1.8.3, Ben: "Non-obstructive" as an option on the Left Heart Catheterization page, below Dominance.
final class PatientLHC183Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 8))! }
    private func read(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    /// The result a typed line gives: "non-obstructive", "no-cad", or nil.
    private func typed(_ s: String) -> String? {
        if case .lhcResult(let v)? = read(s).findings.first(where: { $0.id == "lhc:result" })?.change { return v }
        return nil
    }

    private func lhc(_ result: String? = "non-obstructive") -> PatientLHC {
        var l = PatientLHC()
        l.dominance = "right"; l.date = PatientMonthYear(month: 6, year: 2026); l.result = result
        return l
    }

    // MARK: The line

    func testTheLineReadsNonObstructiveCAD() {
        XCTAssertEqual(lhc().summary, "LHC 06/2026, right dominant: non-obstructive CAD")
        XCTAssertEqual(lhc("no-cad").summary, "LHC 06/2026, right dominant: no CAD")
        XCTAssertEqual(lhc(nil).summary, "LHC 06/2026, right dominant")
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
        for note in ["No CAD", "normal coronaries", "No coronary artery disease"] {
            var l = lhc("no-cad")
            l.notes = note
            XCTAssertEqual(l.summary, "LHC 06/2026, right dominant: " + note, note)
        }
        var other = lhc("no-cad")
        other.notes = "Non-obstructive"
        XCTAssertEqual(other.summary, "LHC 06/2026, right dominant: no CAD; Non-obstructive", "different words: both print")
    }

    func testTheOptionAloneIsAnEntry() {
        var l = PatientLHC()
        XCTAssertTrue(l.isEmpty)
        l.result = "non-obstructive"
        XCTAssertFalse(l.isEmpty)
        XCTAssertEqual(l.summary, "LHC: non-obstructive CAD")
        l.result = "no-cad"
        XCTAssertEqual(l.summary, "LHC: no CAD")
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
        XCTAssertEqual(back.lhc.result, "non-obstructive")
        XCTAssertEqual(back.lhc, r.lhc)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        var inner = try XCTUnwrap(json["lhc"] as? [String: Any])
        inner.removeValue(forKey: "result")
        json["lhc"] = inner
        let old = try JSONDecoder().decode(PatientRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.lhc.result)
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
        PatientNote.apply([.lhcResult("non-obstructive")], to: &typed)
        var expected = base
        expected.lhc.result = "non-obstructive"
        XCTAssertEqual(typed, expected)
        PatientNote.apply([.lhcResult("no-cad")], to: &typed)
        expected.lhc.result = "no-cad"
        XCTAssertEqual(typed, expected, "only the cath's result changed: no history, no vessel")
        var withVessels = with
        withVessels.lhc.stenosis = ["lad": 30]
        PatientNote.apply([.lhcResult("no-cad")], to: &withVessels)
        XCTAssertEqual(withVessels.lhc.stenosis, ["lad": 30], "no vessel value is changed")
        XCTAssertEqual(PatientRules.asaSuggestion(with.lhc.result == nil ? base : with)?.level, PatientRules.asaSuggestion(base)?.level)
    }

    // MARK: The two chips

    func testOneAtATime() {
        // The row's binding is the one field: choosing one replaces the other, choosing it again clears it.
        var l = PatientLHC()
        XCTAssertEqual(PatientLHC.resultOptions.map(\.id), ["non-obstructive", "no-cad"])
        XCTAssertEqual(PatientLHC.resultOptions.map(\.label), ["Non-obstructive", "No CAD"])
        l.result = "non-obstructive"
        l.result = "no-cad"
        XCTAssertEqual(l.result, "no-cad")
        XCTAssertEqual(l.summary, "LHC: no CAD", "the first is gone")
        l.result = nil
        XCTAssertTrue(l.isEmpty)
        // A note that reads the other one replaces the first, as a change.
        var r = PatientRecord()
        r.lhc.result = "non-obstructive"
        let f = PatientNoteFinding(id: "lhc:result", section: PatientNote.Part.assessment, label: "x", change: .lhcResult("no-cad"))
        XCTAssertEqual(PatientNote.status(f, in: r), .replaces("non-obstructive"))
        PatientNote.apply([f.change], to: &r)
        XCTAssertEqual(r.lhc.result, "no-cad")
        XCTAssertEqual(PatientNote.status(f, in: r), .recorded)
    }

    // MARK: Typing

    func testNonObstructiveWithACathWord() {
        for s in ["LHC non-obstructive", "cath: nonobstructive CAD", "non-obstructive coronary disease on cath", "LHC 06/2026 right dominant, non obstructive",
                  "Coronary angiogram showed nonobstructive disease", "Left heart cath: non-obstructive", "cath showed no obstructive CAD",
                  "LHC: mild non-obstructive disease"] {
            XCTAssertEqual(typed(s), "non-obstructive", s)
        }
    }

    func testNoCADWithACathWord() {
        for s in ["cath: normal coronaries", "angiographically normal coronary arteries on LHC", "LHC clean coronaries", "cath: no CAD",
                  "LHC showed no coronary artery disease", "Coronary angiogram: normal coronary arteries"] {
            XCTAssertEqual(typed(s), "no-cad", s)
        }
    }

    func testAmbiguousSetsNeither() {
        XCTAssertNil(typed("cath: no significant CAD"))
        XCTAssertNil(typed("LHC with no significant coronary artery disease"))
        XCTAssertNil(typed("cath: normal coronaries, nonobstructive plaque"), "a sentence that says both")
    }

    func testNeverWithoutACathWord() {
        for s in ["non-obstructive CAD", "CCTA: nonobstructive CAD", "CT showed non-obstructive plaque", "PA cath in place, nonobstructive CAD on CT",
                  "Cath done. Non-obstructive CAD on CT.", "normal coronaries", "no CAD", "CTA: normal coronary arteries", "No coronary artery disease on CT"] {
            XCTAssertNil(typed(s), s)
        }
    }

    func testTheCADItemIsNotFiledFromIt() {
        let r = read("cath: nonobstructive CAD")
        XCTAssertFalse(r.findings.contains { $0.id == "problem:cad" }, "the cath's result is not the history item")
        XCTAssertEqual(typed("cath: nonobstructive CAD"), "non-obstructive")
        XCTAssertTrue(r.other.isEmpty, "and nothing is left over: " + r.other)
        for s in ["cath: no CAD", "LHC normal coronaries"] {
            XCTAssertFalse(read(s).findings.contains { $0.id.hasPrefix("problem:") }, s)
        }
        // A CAD told apart from it is still read.
        XCTAssertTrue(read("CAD with stents. LHC non-obstructive.").findings.contains { $0.id == "problem:cad" || $0.id == "problem:pci" })
    }

    func testFilesThroughTheNoteAndTheBar() {
        var r = PatientRecord()
        let reading = read("68M. LHC non-obstructive, right dominant.")
        let f = reading.findings.first { $0.id == "lhc:result" }
        XCTAssertEqual(f?.change, .lhcResult("non-obstructive"))
        XCTAssertEqual(f.map { PatientNote.status($0, in: r) }, .new)
        PatientNote.apply(reading.findings.map(\.change), to: &r)
        XCTAssertEqual(r.lhc.result, "non-obstructive")
        XCTAssertEqual(f.map { PatientNote.status($0, in: r) }, .recorded)
        let q = QuickAdd.read("cath: normal coronaries", record: PatientRecord(), tab: .preop, now: now)
        XCTAssertEqual(q.findings.first { $0.id == "lhc:result" }?.change, .lhcResult("no-cad"))
        let intra = QuickAdd.read("LHC non-obstructive", record: PatientRecord(), tab: .intraop, now: now)
        XCTAssertFalse(intra.findings.contains { $0.id == "lhc:result" }, "not filed from the OR")
    }

    func testPatternsCompile() {
        for rx in PatientLHC.patterns { XCTAssertNotNil(rx.re, rx.pattern) }
    }
}
