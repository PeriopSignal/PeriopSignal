import XCTest
@testable import PeriopSignal

/// 1.8.3, Ben: the ECG findings and the Cardiovascular history fill each other. ECG → history always; history → ECG only
/// where the history says the rhythm is ongoing, else a suggestion; taking one off never takes the other off, except a
/// finding the history put on the ECG itself.
final class PatientECGLink183Tests: XCTestCase {
    private func empty() -> PatientRecord { PatientRecord() }

    // MARK: The mapping

    func testMappingUsesExistingIdsAndLabels() throws {
        let cv = try XCTUnwrap(PatientCatalog.systems.first { $0.id == "cv" })
        let ids = Set(cv.problems.map(\.id))
        for (finding, e) in PatientECGLink.establishes {
            XCTAssertTrue(PatientECG.findings.contains(finding), finding + " is an ECG finding")
            XCTAssertTrue(ids.contains(e.problem), e.problem + " is a Cardiovascular item")
        }
        for f in PatientECGLink.notLinked {
            XCTAssertTrue(PatientECG.findings.contains(f), f)
            XCTAssertNil(PatientECGLink.establishes[f], f + " has no item of its own")
        }
    }

    // MARK: ECG → history, always

    func testECGFindingFilesTheDiagnosis() {
        var r = empty()
        r.noHistory = true
        PatientECGLink.add("Atrial fibrillation", to: &r)
        XCTAssertEqual(r.ecg, ["Atrial fibrillation"])
        XCTAssertTrue(r.has("af"))
        XCTAssertFalse(r.noHistory)
        var flutter = empty()
        PatientECGLink.add("Atrial flutter", to: &flutter)
        XCTAssertTrue(flutter.has("af"), "AF/flutter is one item")
        for f in ["Paced rhythm (atrial)", "Paced rhythm (ventricular)", "Paced rhythm (AV)"] {
            var p = empty()
            PatientECGLink.add(f, to: &p)
            XCTAssertTrue(p.has("pacemaker"), f)
        }
        var svt = empty()
        PatientECGLink.add("SVT", to: &svt)
        XCTAssertTrue(svt.has("arrhythmia"))
        XCTAssertEqual(svt.hx.arrhythmiaType, "SVT")
        PatientECGLink.add("Complete heart block", to: &svt)
        XCTAssertEqual(svt.hx.arrhythmiaType, "SVT, complete heart block", "added to what is typed")
        PatientECGLink.add("SVT", to: &svt)
        XCTAssertEqual(svt.hx.arrhythmiaType, "SVT, complete heart block", "not written twice")
        var mobitz = empty()
        mobitz.problems = ["arrhythmia"]; mobitz.hx.arrhythmiaType = "third-degree AV block"
        PatientECGLink.add("Complete heart block", to: &mobitz)
        XCTAssertEqual(mobitz.hx.arrhythmiaType, "third-degree AV block", "already said in other words")
        PatientECGLink.add("Mobitz II", to: &mobitz)
        XCTAssertEqual(mobitz.hx.arrhythmiaType, "third-degree AV block, Mobitz II")
    }

    func testAlreadyInTheHistoryChangesNothingThere() {
        var r = empty()
        r.problems = ["af", "htn"]
        PatientECGLink.add("Atrial fibrillation", to: &r)
        XCTAssertEqual(r.problems, ["af", "htn"])
    }

    func testAPacemakerIsNotAddedBesideAnICD() {
        var r = empty()
        r.problems = ["icd"]
        PatientECGLink.add("Paced rhythm (ventricular)", to: &r)
        XCTAssertFalse(r.has("pacemaker"))
        XCTAssertEqual(r.ecg, ["Paced rhythm (ventricular)"])
    }

    func testConductionFindingsWithoutAnItemFileNothing() {
        for f in PatientECGLink.notLinked {
            var r = empty()
            PatientECGLink.add(f, to: &r)
            XCTAssertEqual(r.ecg, [f])
            XCTAssertTrue(r.problems.isEmpty, f)
            XCTAssertTrue(r.hx.arrhythmiaType.isEmpty, f)
        }
        var r = empty()
        PatientECGLink.add("Normal sinus rhythm", to: &r)
        XCTAssertTrue(r.problems.isEmpty)
    }

    func testTakingTheECGFindingOffNeverTakesTheDiagnosisOff() {
        var r = empty()
        PatientECGLink.add("Atrial fibrillation", to: &r)
        PatientECGLink.add("Paced rhythm (AV)", to: &r)
        r.ecg.removeAll()
        PatientECGLink.sync(&r)
        XCTAssertTrue(r.has("af"))
        XCTAssertTrue(r.has("pacemaker"))
    }

    // MARK: History → ECG, only when ongoing

    func testHistoryAloneFilesNothingOnTheECG() {
        var r = empty()
        r.problems = ["af", "pacemaker", "icd", "arrhythmia"]
        r.hx.arrhythmiaType = "SVT, heart block"
        PatientECGLink.sync(&r)
        XCTAssertTrue(r.ecg.isEmpty, "paroxysmal AF in sinus rhythm, or a pacemaker not pacing, is not an ECG finding")
        XCTAssertNil(PatientSummary.ecgText(r), "and the handoff says nothing of it")
        XCTAssertTrue(PatientECGLink.ongoing(r).isEmpty)
    }

    func testSuggestionsOfferWhatTheHistoryHolds() {
        var r = empty()
        r.problems = ["af", "pacemaker"]
        let s = PatientECGLink.suggestions(r)
        XCTAssertEqual(s.map(\.from), ["AF/flutter", "pacemaker"])
        XCTAssertEqual(s[0].findings, ["Atrial fibrillation", "Atrial flutter"])
        XCTAssertEqual(s[0].prompt, "From history: AF/flutter — add?")
        XCTAssertEqual(s[1].findings, ["Paced rhythm (atrial)", "Paced rhythm (ventricular)", "Paced rhythm (AV)"])
        // Tapping one files it as seen, and the suggestion goes.
        PatientECGLink.add("Atrial flutter", to: &r)
        XCTAssertEqual(PatientECGLink.suggestions(r).map(\.from), ["pacemaker"])
        XCTAssertTrue(r.ecgFromHistory.isEmpty, "chosen by hand, so not the history's")
        // Other arrhythmia names a finding in its type.
        var o = empty()
        o.problems = ["arrhythmia"]; o.hx.arrhythmiaType = "SVT, heart block"
        XCTAssertEqual(PatientECGLink.suggestions(o).map(\.from), ["SVT"], "\"heart block\" alone names no grade")
        o.hx.arrhythmiaType = "complete heart block"
        XCTAssertEqual(PatientECGLink.suggestions(o).first?.findings, ["Complete heart block"])
        // Nothing to offer when the ECG says it already.
        o.ecg = ["Complete heart block"]
        XCTAssertTrue(PatientECGLink.suggestions(o).isEmpty)
        // Not stored: the record is as it was.
        var q = empty(); q.problems = ["af"]
        let before = q
        _ = PatientECGLink.suggestions(q)
        XCTAssertEqual(q, before)
    }

    func testPacemakerDependenceIsOngoing() {
        for text in ["dependent", "Pacemaker dependent, Medtronic", "dependent; magnet response unknown", "PM-dependent"] {
            XCTAssertTrue(PatientECGLink.dependent(text), text)
        }
        for text in ["not dependent", "non-dependent", "nondependent", "independent", "not pacemaker dependent", "Medtronic", "", "magnet response"] {
            XCTAssertFalse(PatientECGLink.dependent(text), text)
        }
        var r = empty()
        r.problems = ["pacemaker"]; r.hx.deviceDetails = "dependent"
        XCTAssertEqual(PatientECGLink.ongoing(r), ["Paced rhythm (ventricular)"])
        r.problems = ["icd"]
        XCTAssertTrue(PatientECGLink.ongoing(r).isEmpty, "details of an ICD say nothing of pacing")
    }

    func testOngoingHistoryFilesOnTheECGAndTheHistoryTakesItOff() {
        var r = empty()
        r.problems = ["pacemaker"]
        PatientECGLink.sync(&r)
        XCTAssertTrue(r.ecg.isEmpty, "a pacemaker alone")
        r.hx.deviceDetails = "dependent"
        PatientECGLink.sync(&r)
        XCTAssertEqual(r.ecg, ["Paced rhythm (ventricular)"])
        XCTAssertEqual(r.ecgFromHistory, ["Paced rhythm (ventricular)"])
        XCTAssertNotNil(PatientSummary.ecgText(r))
        // Syncing again changes nothing.
        let once = r
        PatientECGLink.sync(&r)
        XCTAssertEqual(r, once)
        // The history goes: the finding it put there goes.
        r.hx.deviceDetails = ""
        PatientECGLink.sync(&r)
        XCTAssertTrue(r.ecg.isEmpty)
        XCTAssertTrue(r.ecgFromHistory.isEmpty)
        // Or the pacemaker is taken off.
        r.hx.deviceDetails = "dependent"
        PatientECGLink.sync(&r)
        XCTAssertEqual(r.ecg, ["Paced rhythm (ventricular)"])
        r.problems.remove("pacemaker")
        PatientECGLink.sync(&r)
        XCTAssertTrue(r.ecg.isEmpty)
    }

    func testAFindingSomeoneSawIsNeverTakenOffWithTheHistory() {
        var r = empty()
        r.problems = ["pacemaker"]
        PatientECGLink.add("Paced rhythm (ventricular)", to: &r)
        r.hx.deviceDetails = "dependent"
        PatientECGLink.sync(&r)
        XCTAssertEqual(r.ecg, ["Paced rhythm (ventricular)"])
        XCTAssertTrue(r.ecgFromHistory.isEmpty, "it was there already: not the history's")
        r.hx.deviceDetails = ""
        r.problems.remove("pacemaker")
        PatientECGLink.sync(&r)
        XCTAssertEqual(r.ecg, ["Paced rhythm (ventricular)"], "removing the history removes only what the history added")
        // Added by hand after the history put one there: it is the reader's now.
        var s = empty()
        s.problems = ["pacemaker"]; s.hx.deviceDetails = "dependent"
        PatientECGLink.sync(&s)
        XCTAssertEqual(s.ecgFromHistory.count, 1)
        PatientECGLink.add("Paced rhythm (ventricular)", to: &s)
        XCTAssertTrue(s.ecgFromHistory.isEmpty)
        s.problems.remove("pacemaker")
        PatientECGLink.sync(&s)
        XCTAssertEqual(s.ecg, ["Paced rhythm (ventricular)"])
    }

    func testAFindingTakenOffByHandStaysOff() {
        var r = empty()
        r.problems = ["pacemaker"]; r.hx.deviceDetails = "dependent"
        PatientECGLink.sync(&r)
        r.ecg.removeAll()
        PatientECGLink.sync(&r)
        XCTAssertTrue(r.ecg.isEmpty, "the history is as it was: it is not put back")
        XCTAssertTrue(r.ecgFromHistory.isEmpty)
        // A change in the history is a new reading.
        r.hx.deviceDetails = ""
        PatientECGLink.sync(&r)
        r.hx.deviceDetails = "dependent"
        PatientECGLink.sync(&r)
        XCTAssertEqual(r.ecg, ["Paced rhythm (ventricular)"])
    }

    func testAnAutoAddedRhythmDoesNotReplaceAnotherRhythm() {
        var r = empty()
        PatientECGLink.add("Atrial fibrillation", to: &r)
        r.problems.insert("pacemaker"); r.hx.deviceDetails = "dependent"
        PatientECGLink.sync(&r)
        XCTAssertEqual(Set(r.ecg), ["Atrial fibrillation", "Paced rhythm (ventricular)"], "ventricular pacing sits beside the atrial rhythm")
    }

    // MARK: Saved records

    func testARecordSavedBeforeTheLinkOpensUnchanged() throws {
        var r = empty()
        r.problems = ["pacemaker", "af"]; r.hx.deviceDetails = "dependent"
        let data = try JSONEncoder().encode(r)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "ecgFromHistory")
        json.removeValue(forKey: "ecgHistoryImplied")
        let old = try JSONSerialization.data(withJSONObject: json)
        var back = try JSONDecoder().decode(PatientRecord.self, from: old)
        XCTAssertTrue(back.ecg.isEmpty)
        let before = back
        PatientECGLink.sync(&back)
        XCTAssertEqual(back, before, "nothing appears on the ECG of an existing patient")
        // And a current record round-trips.
        PatientECGLink.sync(&r)
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again, r)
        XCTAssertEqual(again.ecgFromHistory, ["Paced rhythm (ventricular)"])
    }

    func testAnEmptyPatientStaysEmpty() {
        var r = empty()
        PatientECGLink.sync(&r)
        XCTAssertTrue(r.isEmpty)
    }
}
