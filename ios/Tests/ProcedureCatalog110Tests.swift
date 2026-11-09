import XCTest
@testable import PeriopSignal

/// 1.10 (Ben, Nov 7): aortic root replacement and the transcatheter cardiovascular procedures in the list, planned and past,
/// with the flags the list's rules give them (header of ProcedureCatalog.swift): a transcatheter heart procedure is
/// `cardiac` and echo first, like TAVR (the RCRI is hidden), but neither intrathoracic nor RCRI high risk.
final class ProcedureCatalog110Tests: XCTestCase {
    private func proc(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> Procedure {
        guard let p = ProcedureCatalog.byID(id) else {
            XCTFail("no procedure \(id)", file: file, line: line)
            return ProcedureCatalog.all[0]
        }
        return p
    }

    private func ids(_ text: String) -> [String] { ProcedureCatalog.parse(text).map(\.procedure.id) }

    // MARK: Aortic root

    func testAorticRootReplacementIsItsOwnEntry() {
        let root = proc("aortic-root")
        XCTAssertEqual(root.name, "Aortic root replacement")
        XCTAssertEqual(root.specialty, "Cardiac")
        XCTAssertTrue(root.cardiac && root.echoFirst)
        XCTAssertEqual(root.incision, "Intrathoracic")
        XCTAssertEqual(root.duration, "> 3 h")
        XCTAssertEqual(root.anesthetic, ["ga"])
        XCTAssertNil(root.ask, "a root replacement whose technique is not given asks nothing")
        for (q, id) in [("aortic root replacement", "aortic-root"), ("root replacement", "aortic-root"),
                        ("VSRR", "valve-sparing-root"), ("David procedure", "valve-sparing-root"),
                        ("valve sparing root replacement", "valve-sparing-root"), ("bio-Bentall", "bentall-bio"),
                        ("mechanical Bentall", "bentall-mech"), ("aortic root replacement with composite graft", "bentall")] {
            XCTAssertEqual(ids(q), [id], "parse \(q)")
        }
        XCTAssertEqual(ProcedureCatalog.search("aortic root replacement").first?.id, "aortic-root")
        XCTAssertEqual(ProcedureCatalog.search("VSRR").first?.id, "valve-sparing-root")
        XCTAssertEqual(ProcedureCatalog.onReturn("aortic root replacement").map(\.catalogID), ["aortic-root"])
        // The general Bentall still asks its valve, under its own name now.
        XCTAssertEqual(proc("bentall").name, "Bentall (composite valve graft)")
        XCTAssertNotNil(proc("bentall").ask)
        // Planned: cardiac surgery, the RCRI hidden.
        var r = PatientRecord()
        r.setProcedures(PlannedProcedure.parse("aortic root replacement"))
        XCTAssertTrue(PatientRules.cardiacSurgery(r))
        XCTAssertEqual(r.incision, "Intrathoracic")
        // Past: an intrathoracic, cardiac operation.
        var s = PatientSurgery()
        s.setProcedures(PlannedProcedure.parse("aortic root replacement"))
        XCTAssertTrue(s.intrathoracic)
        XCTAssertTrue(PastSurgeryNote.isCardiac(s))
    }

    // MARK: Transcatheter

    func testTranscatheterEntriesHaveTheTAVRFlags() {
        let tavr = proc("tavr")
        for id in ["teer", "teer-mitral", "teer-tricuspid", "pvl-closure", "pvl-closure-aortic", "pvl-closure-mitral", "laao",
                   "tmvr", "ttvr", "structural-closure", "alcohol-septal-ablation"] {
            let p = proc(id)
            XCTAssertEqual(p.cardiac, tavr.cardiac, id)
            XCTAssertTrue(p.echoFirst, id + ": TEE is usual")
            XCTAssertFalse(p.highRisk, id + ": not RCRI high risk (catheter, not intrathoracic)")
            XCTAssertEqual(p.incision, "Peripheral", id + ": ARISCAT, catheter procedure")
            XCTAssertNil(p.ask, id)
        }
        for id in ["teer-mitral", "teer-tricuspid", "pvl-closure-aortic", "pvl-closure-mitral"] {
            XCTAssertEqual(proc(id).anesthetic, ["ga"], id)
            XCTAssertEqual(proc(id).duration, "> 2–3 h", id)
        }
        XCTAssertEqual(proc("teer-mitral").specialty, "Cardiac")
        XCTAssertEqual(proc("pvl-closure-mitral").specialty, "Cardiac cath & EP")
    }

    func testTranscatheterNamesAndAbbreviations() {
        let expected: [(String, String)] = [
            ("MitraClip", "teer-mitral"), ("mitral TEER", "teer-mitral"), ("M-TEER", "teer-mitral"), ("mitral clip", "teer-mitral"),
            ("TriClip", "teer-tricuspid"), ("tricuspid TEER", "teer-tricuspid"), ("T-TEER", "teer-tricuspid"),
            ("TEER", "teer"), ("PASCAL", "teer"), ("transcatheter edge-to-edge repair", "teer"),
            ("LAAO", "laao"), ("LAAC", "laao"), ("Watchman", "laao"), ("Amulet", "laao"), ("LAA closure", "laao"),
            ("left atrial appendage occlusion device", "laao"),
            ("PVL closure", "pvl-closure"), ("PVL plug", "pvl-closure"), ("paravalvular leak closure", "pvl-closure"),
            ("aortic PVL closure", "pvl-closure-aortic"), ("aortic paravalvular leak plug", "pvl-closure-aortic"),
            ("mitral PVL closure", "pvl-closure-mitral"), ("mitral PVL plug", "pvl-closure-mitral"),
            ("Mitral paravalvular leak closure", "pvl-closure-mitral"),
            ("TMVR", "tmvr"), ("mitral ViV", "tmvr"), ("mitral valve in valve", "tmvr"), ("TTVR", "ttvr"), ("tricuspid ViV", "ttvr"),
            ("TAVR", "tavr"), ("ViV TAVR", "tavr"), ("PFO closure", "structural-closure"), ("ASD closure", "structural-closure"),
            ("alcohol septal ablation", "alcohol-septal-ablation"), ("LARIAT", "lariat"),
        ]
        for (q, id) in expected {
            XCTAssertEqual(ProcedureCatalog.search(q).first?.id, id, "search \(q)")
            XCTAssertEqual(ids(q), [id], "parse \(q)")
        }
        // Several in one line.
        XCTAssertEqual(ids("MitraClip + TriClip"), ["teer-mitral", "teer-tricuspid"])
        XCTAssertEqual(ids("TAVR paravalvular leak closure"), ["pvl-closure-aortic"])
    }

    /// 1.8.3: a diagnosis stays a diagnosis. The leak, the PFO and the valve lesion are not procedures.
    func testDiagnosesAreNotProcedures() {
        for d in ["PVL", "paravalvular leak", "PFO", "LAA thrombus"] {
            XCTAssertEqual(ids(d), [], d)
        }
    }

    func testTranscatheterPlannedHidesTheRCRIAndIsNotIntrathoracic() {
        for text in ["MitraClip", "TriClip", "Watchman", "aortic PVL closure", "TMVR"] {
            var r = PatientRecord()
            r.setProcedures(PlannedProcedure.parse(text))
            XCTAssertTrue(PatientRules.cardiacSurgery(r), text + ": the RCRI is hidden, as for TAVR")
            XCTAssertFalse(r.highRiskSurgery, text)
            XCTAssertEqual(r.incision, "Peripheral", text)
            XCTAssertTrue(PatientRules.echoFirst(r), text)
        }
    }

    /// Past: a transcatheter procedure is not a previous intrathoracic operation, nor previous cardiac surgery.
    func testTranscatheterPastIsNotIntrathoracic() {
        for text in ["MitraClip", "TriClip", "Watchman", "mitral PVL plug", "TAVR", "TMVR", "PFO closure"] {
            var s = PatientSurgery()
            s.setProcedures(PlannedProcedure.parse(text))
            XCTAssertFalse(s.intrathoracic, text)
            XCTAssertFalse(PastSurgeryNote.isCardiac(s), text)
        }
        for text in ["CABG", "AVR", "VSRR", "Bentall", "VATS lobectomy"] {
            var s = PatientSurgery()
            s.setProcedures(PlannedProcedure.parse(text))
            XCTAssertTrue(s.intrathoracic, text)
        }
    }

    /// A note's past surgery reads the new names (with their dates), and the planned ones as planned.
    func testNotesReadTheNewNames() {
        func applied(_ note: String) -> PatientRecord {
            var r = PatientRecord()
            PatientNote.apply(PatientNote.read(note).findings.map(\.change), to: &r)
            return r
        }
        let past = applied("PSH: MitraClip 2022, Watchman 2023, aortic root replacement 2015")
        XCTAssertEqual(past.surgeries.compactMap { $0.procedures.first?.catalogID }, ["teer-mitral", "laao", "aortic-root"])
        XCTAssertEqual(past.surgeries.map(\.date.year), [2022, 2023, 2015])
        XCTAssertEqual(past.surgeries.map(\.intrathoracic), [false, false, true])
        XCTAssertEqual(past.hx.cardiacSurgeryID, past.surgeries.last?.id, "the root replacement is previous cardiac surgery")
        XCTAssertTrue(past.procedures.isEmpty, "nothing planned")
        XCTAssertEqual(applied("s/p TriClip 2024").surgeries.first?.procedures.first?.catalogID, "teer-tricuspid")
        XCTAssertEqual(applied("h/o TriClip").surgeries.count, 1, "an operation name after a history lead")
        let planned = PatientNote.read("78F scheduled for MitraClip.").findings.first { $0.id == "procedure" }
        XCTAssertEqual(planned?.change, .procedure("MitraClip"))
    }
}
