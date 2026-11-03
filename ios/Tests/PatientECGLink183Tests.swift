import XCTest
@testable import PeriopSignal

/// 1.8.3, Ben: the ECG findings and the Cardiovascular history are linked. ECG → history is automatic (a paced rhythm adds a
/// pacemaker only where it surely is one); history → ECG is never automatic, only a one-tap suggestion; taking one off never
/// takes the other off.
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
        for f in PatientECGLink.pacedFindings { XCTAssertTrue(PatientECG.findings.contains(f), f) }
        for f in PatientECGLink.notLinked {
            XCTAssertTrue(PatientECG.findings.contains(f), f)
            XCTAssertNil(PatientECGLink.establishes[f], f + " has no item of its own")
        }
        for rx in PatientECGLink.patterns { XCTAssertNotNil(rx.re, rx.pattern) }
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
        for f in PatientECGLink.pacedFindings {
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
        XCTAssertTrue(r.has("af"))
        XCTAssertTrue(r.has("pacemaker"))
    }

    // MARK: A paced rhythm and the pacemaker

    func testTemporaryOrEpicardialWiresAreNotAPermanentPacemaker() {
        for words in ["epicardial wires, paced", "temporary pacing wires", "temp wires in place", "transvenous pacing", "external pacing", "post-op pacing"] {
            var r = empty()
            r.ecgNotes = words
            PatientECGLink.add("Paced rhythm (ventricular)", to: &r)
            XCTAssertEqual(r.ecg, ["Paced rhythm (ventricular)"], words)
            XCTAssertFalse(r.has("pacemaker"), words)
            XCTAssertTrue(PatientECGLink.pacemakerSuggested(r), words + ": offered instead")
        }
        // The wires named elsewhere in the record.
        var viaProcedure = empty()
        viaProcedure.procedure = "CABG, epicardial pacing wires"
        PatientECGLink.add("Paced rhythm (AV)", to: &viaProcedure)
        XCTAssertFalse(viaProcedure.has("pacemaker"))
        var viaDevice = empty()
        viaDevice.devices = [PatientDevice(kind: .other, detail: "temporary pacing wire")]
        PatientECGLink.add("Paced rhythm (atrial)", to: &viaDevice)
        XCTAssertFalse(viaDevice.has("pacemaker"))
        var viaHistory = empty()
        viaHistory.otherHistory = "Epicardial wires after the valve"
        PatientECGLink.add("Paced rhythm (ventricular)", to: &viaHistory)
        XCTAssertFalse(viaHistory.has("pacemaker"))
    }

    func testAnICDOrCRTIsNotGivenASecondDevice() {
        var icd = empty()
        icd.problems = ["icd"]
        PatientECGLink.add("Paced rhythm (ventricular)", to: &icd)
        XCTAssertFalse(icd.has("pacemaker"))
        XCTAssertTrue(PatientECGLink.pacemakerSuggested(icd))
        for details in ["CRT-D", "CRT-P, Medtronic", "biventricular pacemaker", "resynchronization", "AICD"] {
            var r = empty()
            r.hx.deviceDetails = details
            PatientECGLink.add("Paced rhythm (ventricular)", to: &r)
            XCTAssertFalse(r.has("pacemaker"), details)
        }
    }

    func testThePacemakerSuggestionAddsIt() {
        var r = empty()
        r.problems = ["icd"]
        PatientECGLink.add("Paced rhythm (ventricular)", to: &r)
        XCTAssertTrue(PatientECGLink.pacemakerSuggested(r))
        PatientECGLink.addPacemaker(to: &r)
        XCTAssertTrue(r.has("pacemaker"))
        XCTAssertFalse(PatientECGLink.pacemakerSuggested(r), "added: nothing more to offer")
        // Nothing offered without a paced rhythm, or when it was added by itself.
        var plain = empty()
        plain.ecgNotes = "epicardial wires"
        XCTAssertFalse(PatientECGLink.pacemakerSuggested(plain))
        var added = empty()
        PatientECGLink.add("Paced rhythm (AV)", to: &added)
        XCTAssertFalse(PatientECGLink.pacemakerSuggested(added))
    }

    // MARK: History → ECG: a suggestion, never filed

    func testHistoryNeverFilesAnythingOnTheECG() {
        var r = empty()
        r.problems = ["af", "pacemaker", "icd", "arrhythmia"]
        r.hx.arrhythmiaType = "SVT, heart block"
        r.hx.deviceDetails = "dependent"
        XCTAssertTrue(r.ecg.isEmpty)
        XCTAssertNil(PatientSummary.ecgText(r), "the handoff says nothing of it")
        for text in ["dependent", "not PPM dependent", "not device dependent", "pacer dependent: no", "pacemaker dependent"] {
            var p = empty()
            p.problems = ["pacemaker"]; p.hx.deviceDetails = text
            XCTAssertTrue(p.ecg.isEmpty, text)
            XCTAssertEqual(PatientECGLink.suggestions(p).map(\.from), ["pacemaker"], text + ": the same one-tap suggestion; the words are not read")
        }
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

    func testRemovingTheHistoryNeverTouchesTheECG() {
        var r = empty()
        PatientECGLink.add("Atrial fibrillation", to: &r)
        PatientECGLink.add("Paced rhythm (ventricular)", to: &r)
        r.problems.removeAll()
        XCTAssertEqual(Set(r.ecg), ["Atrial fibrillation", "Paced rhythm (ventricular)"], "what someone saw stays")
    }

    // MARK: Saved records

    func testRecordsRoundTripWithNoNewFields() throws {
        var r = empty()
        PatientECGLink.add("Atrial fibrillation", to: &r)
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again, r)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        XCTAssertNil(json["ecgFromHistory"])
        XCTAssertNil(json["ecgHistoryImplied"])
    }
}
