import XCTest
@testable import PeriopSignal

/// 1.12 helper L (Ben, Nov 12): "for ___" typed in the Preoperative bar fills the planned procedure. Before this, "for" gave the
/// procedure only after a heading, a planning word, the patient ("68M for", "male for", "yo for", "pt for") or at the start of the
/// line; "73M with HF for ECMO cannulation", "HTN, DM2, for TAVR", "68M, HTN, for lap chole", "68yoM for lap chole",
/// "male 68 for TKA", "pt is for CABG" and "here for AVR" gave none.
final class L112Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 8))! }

    private func read(_ s: String, _ tab: QuickAddTab = .preop, record: PatientRecord = PatientRecord()) -> QuickAddReading {
        QuickAdd.read(s, record: record, tab: tab, now: now)
    }
    private func change(_ q: QuickAddReading) -> PatientNoteChange? { q.findings.first { $0.id == "procedure" }?.change }
    private func procedureChip(_ q: QuickAddReading, record: PatientRecord = PatientRecord()) -> QuickAddChip? {
        QuickAdd.chips(q, record: record).first { $0.destination == "Procedure" }
    }
    /// The record after the line is typed and Add is tapped.
    private func added(_ s: String, record: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = record
        PatientNote.apply(QuickAdd.changes(QuickAdd.chips(read(s, record: record), record: record)), to: &r)
        return r
    }
    private func ids(_ r: PatientRecord) -> [String] { r.procedures.compactMap(\.catalogID) }

    // MARK: Lines that did not fill the procedure

    func testAForInTheMiddleOfTheLineFillsAProcedureFromTheList() {
        let lines: [(String, String)] = [
            ("73M with HF for ECMO cannulation", "ecmo"),
            ("73 yo man, HTN, DM for CABG x3", "cabg"),
            ("68M, HTN, for lap chole", "lap-chole"),
            ("HTN, DM2, for TAVR", "tavr"),
            ("68yoM for lap chole", "lap-chole"),
            ("male 68 for TKA", "tka"),
            ("pt is for CABG", "cabg"),
            ("here for AVR", "avr"),
            ("73M with HF for Axillary Impella insertion", "axillary-impella"),
        ]
        for (line, id) in lines {
            let q = read(line)
            XCTAssertNotNil(change(q), line)
            let chip = procedureChip(q)
            XCTAssertNotNil(chip, line)
            XCTAssertNil(chip?.statusText, line + ": a new procedure")
            let r = added(line)
            XCTAssertEqual(ids(r).first, id, line + ": the box shows the list's procedure")
            XCTAssertFalse(r.procedure.isEmpty, line)
        }
        // The risk-score inputs fill from the list as they do for "68M for lap chole".
        XCTAssertTrue(added("68M, HTN, for lap chole").highRiskSurgery)
        XCTAssertEqual(added("73 yo man, HTN, DM for CABG x3").procedures.first?.detail, "×3")
    }

    func testTheSpacedAndSplitFormsThatWorkedBeforeStillWork() {
        // Read before this change as well (the patient word is right before "for").
        for (line, id) in [("68M for lap chole", "lap-chole"), ("68 M for lap chole", "lap-chole"), ("68 yo male for TKA", "tka"),
                           ("pt here for AVR", "avr"), ("for lap chole", "lap-chole"), ("for ECMO reconfiguration", "ecmo-reconfiguration"),
                           ("for VA to VV", "ecmo-reconfiguration"), ("for Impella insertion", "mcs-insertion"),
                           ("for robotic prostatectomy tomorrow", "ralp"), ("for EGD with MAC", "egd")] {
            XCTAssertEqual(ids(added(line)).first, id, line)
        }
        XCTAssertEqual(change(read("68M for R TKA under spinal")), .procedure("R TKA"))
        XCTAssertEqual(added("68M for R TKA under spinal").procedures.first?.side, "right")
        XCTAssertEqual(ids(added("for redo sternotomy AVR")).sorted(), ["avr", "redo-sternotomy"])
    }

    func testTheProcedureNamesOfARecievedCase() {
        XCTAssertEqual(ids(added("for Axillary Impella insertion")), ["axillary-impella"])
        XCTAssertEqual(ids(added("73M with HF for ECMO cannulation")), ["ecmo"])
        XCTAssertEqual(ids(added("73M, HF, on milrinone, for ECMO cannulation")), ["ecmo"], "a comma ends the piece that says what he is on")
    }

    /// After a mid-line "for", only a procedure from the list is read; the words before it in the piece are not the patient.
    func testAMidLineForReadsOnlyWhatTheListKnows() {
        for line in ["73M with HF for frobnication", "HTN, DM2, for frobnication", "68M, HTN, for something odd"] {
            XCTAssertNil(change(read(line)), line)
        }
        // Right after the patient the words are kept as typed, as "68M for" has always done.
        XCTAssertEqual(change(read("68yoM for frobnication")), .procedure("frobnication"))
        XCTAssertEqual(change(read("pt is for frobnication")), .procedure("frobnication"))
    }

    func testAMidLineForIsNotReadOnTheIntraoperativeTab() {
        XCTAssertNil(change(read("73M with HF for ECMO cannulation", .intraop)), "a mid-line for is read on the Preoperative tab only")
    }

    // MARK: A second procedure line

    func testAProcedureAlreadyRecordedIsReplacedAndTheChipSaysSo() {
        var r = PatientRecord()
        r.setProcedures(PlannedProcedure.parse("lap chole"), fillAnesthetic: false)
        XCTAssertEqual(r.procedure, "Laparoscopic cholecystectomy")
        for line in ["for TAVR", "73M with HF for TAVR", "HTN, DM2, for TAVR"] {
            let chip = procedureChip(read(line, record: r), record: r)
            XCTAssertEqual(chip?.statusText, "replaces Laparoscopic cholecystectomy", line)
            XCTAssertEqual(chip?.canAdd, true, line)
            let after = added(line, record: r)
            XCTAssertEqual(ids(after), ["tavr"], line + ": replaced, not added to")
        }
        // The same procedure again is recorded already.
        XCTAssertEqual(procedureChip(read("HTN, for lap chole", record: r), record: r)?.statusText, "already recorded")
    }

    // MARK: Guards: a "for" that gives a reason, a length of time or a past operation

    func testForThatIsNotTheOperationReadsNoProcedure() {
        for line in ["68M on apixaban for AF", "on CPAP for OSA", "steroids for asthma", "antibiotics for UTI", "admitted for chest pain",
                     "NPO for 8 hours", "for 3 days", "68M for 3 days", "follows with cardiology for HF", "s/p CABG for 3-vessel disease",
                     "had a TAVR for severe AS", "allergic to penicillin for rash", "73M on heparin for ECMO", "HTN, on ASA for CAD"] {
            XCTAssertNil(change(read(line)), line)
            XCTAssertTrue(added(line).procedures.isEmpty, line)
        }
        // A procedure told as past, or an allergy, right after the "for" is not planned.
        XCTAssertNil(change(read("HF, for CABG 2015")), "a past operation")
        XCTAssertNil(change(read("73M with HF for PCN allergy")))
    }

    func testAnIndicationAfterAProcedureAlreadyReadIsNotASecondProcedure() {
        let q = read("68M for CABG for 3VD")
        XCTAssertEqual(change(q), .procedure("CABG"))
        XCTAssertEqual(ids(added("68M for CABG for 3VD")), ["cabg"])
        XCTAssertEqual(ids(added("73M with HF for CABG for 3VD")), ["cabg"])
    }

    /// What "for TEE" and "for cardioversion" did before, they still do: the words after a leading "for" are the procedure.
    func testForTEEAndForCardioversionAreAsBefore() {
        XCTAssertEqual(change(read("for TEE")), .procedure("TEE"))
        XCTAssertEqual(change(read("for cardioversion")), .procedure("cardioversion"))
        XCTAssertEqual(change(read("73M for TEE")), .procedure("TEE"))
    }

    // MARK: Words the list reads only by their beginning

    /// The procedure search offers the list's procedure for words it does not read whole ("axillary imp"); the bar files it, so the
    /// box shows the list's procedure and not the typed words.
    func testWordsThatBeginAListedNameFillTheListedProcedure() {
        XCTAssertEqual(ids(added("for axillary imp")), ["axillary-impella"])
        XCTAssertEqual(procedureChip(read("for axillary imp"))?.value, "Axillary Impella insertion")
        // After other words only a procedure the list reads whole is taken, so cut-short words are not.
        XCTAssertNil(change(read("73M with HF for axillary imp")))
        // One word, or words that begin no listed name, stay as typed.
        XCTAssertTrue(ids(added("68M for frobnication")).isEmpty)
        XCTAssertTrue(ids(added("68M for frobnic ation")).isEmpty)
    }

    func testThePatternsCompile() {
        for p in QuickAdd.allPatterns { XCTAssertNotNil(p.re, p.pattern) }
    }
}
