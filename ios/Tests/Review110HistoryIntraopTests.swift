import SwiftUI
import XCTest
@testable import PeriopSignal

/// 1.10 review fixes: past surgical history and the Intraoperative tab (a repeat operation kept, the echo link's pre- and
/// post-bypass exams, the LMA's size, "placed" in the quick-add bar, a saved Han grade, and the Intraop chip rows).
final class Review110HistoryIntraopTests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 8))! }

    private func surgery(_ id: UUID, _ r: PatientRecord) throws -> PatientSurgery {
        try XCTUnwrap(r.surgeries.first { $0.id == id }, "the row \(id) was removed")
    }

    // MARK: A repeat operation is not merged into the earlier one while its date is still empty

    func testARedoOperationPickedBeforeItsDateIsKept() throws {
        var r = PatientRecord()
        var first = PatientSurgery()
        first.setProcedures(PlannedProcedure.parse("AVR"))
        first.date = PatientMonthYear(year: 2005)
        r.surgeries = [first]
        // "Add another operation", then the procedure first (the row's prompt), then its date.
        r.surgeries.append(PatientSurgery())
        var redo = r.surgeries[1]
        redo.setProcedures(PlannedProcedure.parse("AVR"))
        PatientHistoryDetails.editSurgery(redo, &r)
        XCTAssertEqual(r.surgeries.count, 2, "the redo row stays while its date is empty")
        redo = try surgery(redo.id, r)
        redo.date = PatientMonthYear(year: 2020)
        PatientHistoryDetails.editSurgery(redo, &r)
        XCTAssertEqual(r.surgeries.map { $0.date.year }, [2005, 2020], "two previous aortic valve operations")
        XCTAssertEqual(PatientPreop.previousCardiacSurgery(r).count, 2, "both count as previous intrathoracic surgery")

        // Clearing an entry's date to retype it keeps the entry.
        var edited = r.surgeries[0]
        edited.date = PatientMonthYear()
        PatientHistoryDetails.editSurgery(edited, &r)
        XCTAssertEqual(r.surgeries.count, 2, "an entry whose date is being retyped is not taken away")
        edited = try surgery(edited.id, r)
        edited.date = PatientMonthYear(year: 2006)
        PatientHistoryDetails.editSurgery(edited, &r)
        XCTAssertEqual(r.surgeries.map { $0.date.year }, [2006, 2020])

        // The same operation entered twice, with the same date: still one entry (Ben: "not double post").
        r.surgeries.append(PatientSurgery())
        var again = try XCTUnwrap(r.surgeries.last)
        again.setProcedures(PlannedProcedure.parse("AVR"))
        PatientHistoryDetails.editSurgery(again, &r)
        XCTAssertEqual(r.surgeries.count, 3, "no date yet beside dated entries")
        again = try surgery(again.id, r)
        again.date = PatientMonthYear(year: 2020)
        PatientHistoryDetails.editSurgery(again, &r)
        XCTAssertEqual(r.surgeries.map { $0.date.year }, [2006, 2020], "its date says it is the 2020 entry")
    }

    func testASecondCesareanBesideADatedOneIsKept() {
        var r = PatientRecord()
        var first = PatientSurgery()
        first.setProcedures(PlannedProcedure.parse("C-section"))
        first.date = PatientMonthYear(year: 2018)
        r.surgeries = [first, PatientSurgery()]
        var second = r.surgeries[1]
        second.setProcedures(PlannedProcedure.parse("C-section"))
        PatientHistoryDetails.editSurgery(second, &r)
        XCTAssertEqual(r.surgeries.count, 2)
        XCTAssertEqual(r.surgeries.map(\.id), [first.id, second.id])
    }

    // MARK: The echo link shows the pre- and post-bypass exams

    func testTheEchoLinkShowsBothExams() {
        var r = PatientRecord()
        var pre = PatientEcho()
        pre.study = "TEE"
        pre.lv = .normal; pre.lvef = 60
        pre.aortic = EchoValve(regurgitation: .moderate, stenosis: .severe)
        r.intraopEcho = pre
        // The pre-bypass exam alone reads as "Echo", as before.
        XCTAssertEqual(PatientSummary.intraopPartLines(r, "echo").map(\.label), [nil])
        var post = pre.copiedForPostBypass()
        post.aortic = EchoValve(regurgitation: .normal, stenosis: .normal, prosthesis: "Bioprosthetic")
        r.intraopEchoPost = post
        r.echo = "No new wall motion abnormality"
        let card = PatientSummary.intraopPartLines(r, "echo")
        XCTAssertEqual(card.map(\.label), ["Pre-bypass", "Post-bypass", "Echo notes"], card.map(\.text).joined(separator: " | "))
        XCTAssertTrue(card[0].text.hasPrefix("LV EF 60%"), card[0].text)
        XCTAssertTrue(card[1].text.hasPrefix("LV EF 60%"), card[1].text)
        // A post-bypass exam alone shows too.
        r.intraopEcho = PatientEcho(); r.echo = ""
        XCTAssertEqual(PatientSummary.intraopPartLines(r, "echo").map(\.label), ["Post-bypass"])
        // The full intraoperative lines keep their labels.
        XCTAssertTrue(PatientSummary.intraopLines(r).contains { $0.label == "Echo, post-bypass" })
    }

    // MARK: Clearing the LMA clears its size

    func testDeselectingAQuickAddedLMAClearsItsSize() {
        var r = PatientRecord()
        r.airwayDevice = "Supraglottic airway"; r.tube = "LMA 4"
        XCTAssertTrue(PatientAirway.lmaChosen(r))
        XCTAssertTrue(PatientAirway.tubeIsLMA(r), "the LMA section shows the size")
        PatientAirway.setLMA(false, &r)
        XCTAssertFalse(PatientAirway.lmaChosen(r))
        XCTAssertFalse(PatientAirway.intubationChosen(r), "the LMA's size does not turn Intubation on")
        XCTAssertEqual(r.tube, "")
        XCTAssertNil(PatientBriefs.airwayCourse(r)?.text.range(of: "LMA 4"))
        // An intubation's tube stays when the LMA is cleared.
        var both = PatientRecord()
        both.intubation = "easy"; both.airwayDevice = "Supraglottic airway"; both.tube = "7.0 ETT"; both.sga = "easy"
        XCTAssertFalse(PatientAirway.tubeIsLMA(both))
        PatientAirway.setLMA(false, &both)
        XCTAssertEqual(both.tube, "7.0 ETT")
        XCTAssertTrue(PatientAirway.intubationChosen(both))
    }

    // MARK: "placed" is no ease recorded in the quick-add bar

    func testQuickAddDoesNotReplacePlaced() throws {
        var r = PatientRecord()
        PatientAirway.setIntubation(true, &r)
        XCTAssertEqual(r.intubation, PatientAirway.placed)
        let q = QuickAdd.read("easy intubation", record: r, tab: .intraop, now: now, choices: [:])
        let f = try XCTUnwrap(q.findings.first { $0.id == "intraop-airway:intubation" }, "\(q.findings.map(\.id))")
        XCTAssertEqual(PatientNote.status(f, in: r), .new, "not \"replaces placed\"")
        XCTAssertNil(r.intraopAirway("intubation"))
        r.intubation = "difficult"
        XCTAssertEqual(PatientNote.status(f, in: r), .replaces("difficult"), "a recorded ease is still replaced")
    }

    // MARK: A saved Han grade 3-4 reads as a difficult mask

    func testASavedHanGradeIsReadAsTheMaskItMeant() throws {
        func load(_ json: String) throws -> PatientRecord { try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8)) }
        // 1.9 quick-add "mask grade 4, VL grade 1": the grade alone.
        let four = try load(#"{"maskGrade":4,"intubation":"easy","airwayDevice":"Video laryngoscope","laryngoscopyGrade":"1"}"#)
        XCTAssertEqual(four.mask, "difficult")
        XCTAssertNil(four.maskGrade, "the grade is not kept once read")
        XCTAssertTrue(PatientSummary.difficultAirway(four), "the difficult-airway alert, as in 1.9")
        let course = PatientBriefs.airwayCourse(four)?.text ?? ""
        XCTAssertTrue(course.contains("Difficult Mask (Han grade 4, unable to mask ventilate)"), course)
        XCTAssertEqual(PatientBriefs.airwayCourse(four)?.alert, true)
        let handoff = PatientBriefs.handoff(four).first { $0.key == "airway" }?.text ?? ""
        XCTAssertTrue(handoff.contains("unable to mask ventilate"), handoff)
        // Grade 3 with a note keeps the note; an "easy" saved beside it is the difficult mask 1.9 alerted on.
        let three = try load(#"{"maskGrade":3,"mask":"easy","maskNote":"Beard"}"#)
        XCTAssertEqual(three.mask, "difficult")
        XCTAssertEqual(three.maskNote, "Han grade 3; Beard")
        // A mask already difficult, or "none", is left as saved.
        XCTAssertEqual(try load(#"{"maskGrade":4,"mask":"difficult","maskNote":"Beard"}"#).maskNote, "Beard")
        XCTAssertEqual(try load(#"{"maskGrade":4,"mask":"none"}"#).mask, "none")
        // Grades 1-2: an empty mask reads as easy; nothing else changes.
        XCTAssertEqual(try load(#"{"maskGrade":2}"#).mask, "easy")
        XCTAssertEqual(try load(#"{"maskGrade":1,"mask":"difficult"}"#).mask, "difficult")
        // Read again: unchanged (the note is not added twice).
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(three))
        XCTAssertEqual(again.maskNote, "Han grade 3; Beard")
        XCTAssertEqual(again.mask, "difficult")
    }

    func testATypedHanGradeOfThreeOrFourIsADifficultMask() {
        func applied(_ s: String) -> PatientRecord {
            let q = QuickAdd.read(s, record: PatientRecord(), tab: .intraop, now: now, choices: [:])
            var r = PatientRecord()
            PatientNote.apply(q.findings.map(\.change), to: &r)
            return r
        }
        let four = applied("mask grade 4, VL grade 1, 7.5 ETT")
        XCTAssertEqual(four.mask, "difficult")
        XCTAssertNil(four.maskGrade, "the grade itself is not recorded")
        XCTAssertEqual(four.laryngoscopyGrade, "1")
        XCTAssertEqual(applied("Han 3").mask, "difficult")
        XCTAssertNil(applied("mask grade 2, VL grade 1").mask, "grades 1-2 add nothing")
        XCTAssertEqual(applied("easy mask grade 2, VL grade 1").mask, "easy")
    }

    // MARK: A migrated Han grade is not kept, so a later edit of the mask stays

    func testAMaskEditedAfterTheHanGradeIsReadStaysEdited() throws {
        let coder = JSONEncoder()
        func load(_ data: Data) throws -> PatientRecord { try JSONDecoder().decode(PatientRecord.self, from: data) }
        var r = try load(Data(#"{"maskGrade":4}"#.utf8))
        XCTAssertEqual(r.mask, "difficult")
        XCTAssertEqual(r.maskNote, "Han grade 4, unable to mask ventilate")
        XCTAssertNil(r.maskGrade, "read once into the mask, then dropped")
        XCTAssertFalse(String(decoding: try coder.encode(r), as: UTF8.self).contains("maskGrade"), "the next save does not carry it")
        // The clinician taps Easy and deletes the note: the next load (a relaunch) keeps that.
        r.mask = "easy"; r.maskNote = ""
        var back = try load(try coder.encode(r))
        XCTAssertEqual(back.mask, "easy")
        XCTAssertEqual(back.maskNote, "")
        // Deselected: no mask comes back.
        back.mask = nil
        XCTAssertNil(try load(try coder.encode(back)).mask)
        // Grades 1-2: a deselected mask does not come back as easy.
        var two = try load(Data(#"{"maskGrade":2}"#.utf8))
        XCTAssertEqual(two.mask, "easy")
        two.mask = nil
        XCTAssertNil(try load(try coder.encode(two)).mask)
    }

    // MARK: A typed Han grade 3-4 files a difficult mask with the grade in its note

    func testATypedHanGradeKeepsWhatItSaysInTheNote() throws {
        func read(_ s: String, _ r: PatientRecord = PatientRecord()) -> QuickAddReading {
            QuickAdd.read(s, record: r, tab: .intraop, now: now, choices: [:])
        }
        func applied(_ s: String, to start: PatientRecord = PatientRecord()) -> PatientRecord {
            var r = start
            PatientNote.apply(read(s, start).findings.map(\.change), to: &r)
            return r
        }
        let four = applied("Han 4")
        XCTAssertEqual(four.mask, "difficult")
        XCTAssertEqual(four.maskNote, "Han grade 4, unable to mask ventilate", "as a saved grade 4 reads")
        XCTAssertNil(four.maskGrade)
        // "easy mask, Han 4": the grade is not dropped; the difficult mask it says is filed (conservative, as on decode).
        let both = read("easy mask, Han 4")
        XCTAssertNil(both.findings.first { $0.id == "intraop-airway:mask" }, "\(both.findings.map(\.label))")
        let f = try XCTUnwrap(both.findings.first { $0.id == "intraop-airway:maskGrade" }, "\(both.findings.map(\.id))")
        XCTAssertEqual(f.label, "Mask difficult: Han grade 4, unable to mask ventilate")
        XCTAssertEqual(applied("easy mask, Han 4").mask, "difficult")
        // Against a recorded mask: an easy one is replaced; once filed it is recorded.
        var easy = PatientRecord(); easy.mask = "easy"
        XCTAssertEqual(PatientNote.status(f, in: easy), .replaces("easy"))
        XCTAssertEqual(PatientNote.status(f, in: PatientRecord()), .new)
        let filed = applied("Han 4", to: easy)
        XCTAssertEqual(PatientNote.status(f, in: filed), .recorded)
        // A note already there is kept after the grade; a later grade replaces the earlier one rather than adding a second.
        var beard = PatientRecord(); beard.mask = "difficult"; beard.maskNote = "Beard"
        let three = applied("Han 3", to: beard)
        XCTAssertEqual(three.maskNote, "Han grade 3; Beard")
        XCTAssertEqual(applied("mask grade 4", to: three).maskNote, "Han grade 4, unable to mask ventilate; Beard")
    }

    // MARK: The Intraop tab's chips keep their width when chosen

    func testAChosenIntraopChipIsNotBolderOnOneLine() {
        XCTAssertEqual(IntraopChoiceLine.weight(on: true, wrapped: false), .medium, "a tap would widen the chip and move the row")
        XCTAssertEqual(IntraopChoiceLine.weight(on: false, wrapped: false), .medium)
        XCTAssertEqual(IntraopChoiceLine.weight(on: true, wrapped: true), .semibold, "bold only where the row wraps, as ChipSet")
    }
}
