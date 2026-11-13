import XCTest
@testable import PeriopSignal

/// Ben, Nov 13: "68m should = 68 year old male and 26f = 26 year old female in free text spot in preop." Until now only the
/// capitals were read (68M, 26F), because a lowercase m or f after a number is also meters, minutes, months, French and
/// Fahrenheit. The lowercase forms are read where they can only be the patient (Ben's choice): opening the line or a
/// comma-separated item, with "yo" between, or after words that introduce the patient and before for / with / w/ / s/p / here.
final class LowerAgeSex112Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 8))! }

    private func bar(_ s: String, _ tab: QuickAddTab = .preop, record: PatientRecord = PatientRecord()) -> QuickAddReading {
        QuickAdd.read(s, record: record, tab: tab, now: now)
    }
    private func age(_ fs: [PatientNoteFinding]) -> Double? {
        for f in fs { if case .age(let v) = f.change { return v } }
        return nil
    }
    private func sex(_ fs: [PatientNoteFinding]) -> PatientSex? {
        for f in fs { if case .sex(let s) = f.change { return s } }
        return nil
    }
    private func added(_ s: String) -> PatientRecord {
        var r = PatientRecord()
        PatientNote.apply(QuickAdd.changes(QuickAdd.chips(bar(s), record: r)), to: &r)
        return r
    }

    // MARK: The rule itself

    func testLowercaseIsTheAgeAndSexWhereItCanOnlyBeThePatient() {
        let lines: [(String, Double, PatientSex)] = [
            ("68m for lap chole", 68, .male),
            ("26f for lap appy", 26, .female),
            ("68m", 68, .male),
            ("26f, G2P1", 26, .female),
            ("HTN, DM, 68m for CABG", 68, .male),
            ("68m with HTN, DM2", 68, .male),
            ("pt is a 68m for TKA", 68, .male),
            ("healthy 26f for wisdom teeth", 26, .female),
            ("68yom for TAVR", 68, .male),
            ("68 yo m with CAD", 68, .male),
            ("26 y/o f here for c-section", 26, .female),
            ("this 73m s/p CABG for redo sternotomy", 73, .male),
            ("diabetic 61f with ESRD", 61, .female),
            ("Patient is a 44f for lap chole", 44, .female),
            ("- 68m for lap chole", 68, .male),
            ("5m for tonsillectomy", 5, .male),
            ("68m w/ HF for ECMO cannulation", 68, .male),
            ("HTN; 54f for hysterectomy", 54, .female),
            ("68m presenting for CABG", 68, .male),
            ("elderly 88f here for hip fx", 88, .female),
            ("a 68m for TKA today", 68, .male),
            ("68m on apixaban for AF", 68, .male),
            ("pt is a 68m        ", 68, .male),
            ("pt is a 68m       , HTN", 68, .male),
            ("pt is 68m for TKA", 68, .male),
            ("pt is 68m        ", 68, .male),
            ("Patient 44f", 44, .female),
            ("healthy 26f      , no meds", 26, .female),
            ("26f in labor for epidural", 26, .female),
            ("68m, HTN, for lap chole", 68, .male),
            ("71f s/p TAVR", 71, .female),
        ]
        for (line, years, s) in lines {
            let read = PatientNote.lowerAgeSex(line)
            XCTAssertEqual(read?.age, years, line)
            XCTAssertEqual(read?.sex, s, line)
        }
        // The range is the "68m" itself, whatever stood before it.
        XCTAssertEqual(PatientNote.lowerAgeSex("HTN, DM, 68m for CABG")?.range, NSRange(location: 9, length: 3))
        XCTAssertEqual(PatientNote.lowerAgeSex("68 yo m with CAD")?.range, NSRange(location: 0, length: 7))
    }

    func testADistanceATimeATemperatureOrATubeSizeIsNotThePatient() {
        let lines = [
            "walks 100m with walker",
            "walks 50m for exercise",
            "climbs 2 flights, 100m walk without stopping",
            "6m walk test 300m",
            "seen 6m ago with chest pain",
            "temp 101f with chills",
            "tmax 99f for 2 days",
            "7f sheath in R groin",
            "R femoral, 7f sheath",
            "in 30m with pain",
            "NPO for 8m",
            "apnea for 20m with desat",
            "ran 5m with no symptoms",
            "x 3m for back pain",
            "98.6f for now",
            "K 5.4, 30m ago",
            "about 20m for induction",
            "dose 5m for pain",
            "every 6m with cardiology",
            "last 3m with worsening",
            "HTN, 2m of stairs",
            "EF 55m",
            "CABG 2019, 6m ago",
            "5m prior with syncope",
            "12f foley, with clots",
            "12f Foley in place",
            "apnea was 20m, then resolved",
            "duration is 30m.",
            "after the 30m, improved",
            "walked a 50m, then stopped x",
            "took 30m.",
            "HR was 88f",
            "groin, 7f Sheath",
            "6m Walk test",
            "gave 2m for hypotension",
            "MAC 40m for case",
            "took 30m with difficulty",
            "fever, 99f with rigors",
            "sats 88f for unclear reasons",
        ]
        for line in lines { XCTAssertNil(PatientNote.lowerAgeSex(line), line) }
    }

    // MARK: In the Preoperative bar

    func testTheBarReadsLowercaseAsItReadsCapitals() {
        let lines: [(String, Double, PatientSex)] = [("68m for lap chole", 68, .male), ("26f for lap appy", 26, .female), ("HTN, DM, 68m for CABG", 68, .male),
                                                     ("pt is a 68m for TKA", 68, .male), ("68yom for TAVR", 68, .male), ("26f, asthma", 26, .female), ("68m", 68, .male)]
        for (line, years, s) in lines {
            let f = bar(line).findings
            XCTAssertEqual(age(f), years, line)
            XCTAssertEqual(sex(f), s, line)
        }
        // The same lines in capitals read as they did.
        XCTAssertEqual(age(bar("68M for lap chole").findings), 68)
        XCTAssertEqual(sex(bar("68M for lap chole").findings), .male)
        XCTAssertEqual(sex(bar("26F for lap appy").findings), .female)
    }

    func testTheBarDoesNotReadADistanceOrATemperatureAsThePatient() {
        for line in ["walks 100m with walker", "walks 50m for exercise", "temp 101f with chills", "7f sheath in R groin", "seen 6m ago with chest pain"] {
            let f = bar(line).findings
            XCTAssertNil(age(f), line)
            XCTAssertNil(sex(f), line)
        }
    }

    func testAddedItFillsAgeSexAndTheProcedure() {
        let r = added("68m for lap chole")
        XCTAssertEqual(r.ageYears, 68)
        XCTAssertEqual(r.sex, .male)
        XCTAssertEqual(r.procedures.first?.catalogID, "lap-chole")
        let f = added("26f for lap appy")
        XCTAssertEqual(f.ageYears, 26)
        XCTAssertEqual(f.sex, .female)
        XCTAssertFalse(f.procedure.isEmpty)
    }

    // MARK: In a pasted note

    func testAPastedNoteReadsLowercaseToo() {
        let note = PatientNote.read("68m for lap chole under GA. HTN, DM2.", now: now)
        XCTAssertEqual(age(note.findings), 68)
        XCTAssertEqual(sex(note.findings), .male)
        let procedure = note.findings.first { $0.id == "procedure" }
        XCTAssertNotNil(procedure, "the procedure after a lowercase 68m for")
        if case .procedure(let p)? = procedure?.change { XCTAssertTrue(p.lowercased().contains("lap chole"), p) }
        // Not a patient and a procedure.
        let walk = PatientNote.read("Walks 50m for exercise daily.", now: now)
        XCTAssertNil(age(walk.findings)); XCTAssertNil(sex(walk.findings))
        XCTAssertNil(walk.findings.first { $0.id == "procedure" })
    }
}
