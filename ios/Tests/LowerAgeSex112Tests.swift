import XCTest
@testable import PeriopSignal

/// Ben, Nov 13: "68m should = 68 year old male and 26f = 26 year old female in free text spot in preop." Until now only the
/// capitals were read (68M, 26F), because a lowercase m or f after a number is also meters, minutes, months, French and
/// Fahrenheit. The lowercase forms are read where they can only be the patient: opening the typed line, with "yo" between,
/// after words that introduce the patient, or opening a comma-separated item right before "for" and a procedure. Two
/// independent checks ran several hundred lines each through earlier versions; every line they raised (a duration after a
/// diagnosis, a French size after a device, an age written out beside a lowercase duration, a duration after a full stop) is
/// in the lists below.
final class LowerAgeSex112Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 8))! }

    private func bar(_ s: String, _ tab: QuickAddTab = .preop, record: PatientRecord = PatientRecord(), handoff: Bool = false) -> QuickAddReading {
        QuickAdd.read(s, record: record, tab: tab, now: now, handoff: handoff)
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
    /// The lowercase reading of a whole typed text, worked out as `PatientNote.read` does: an age or a sex written out anywhere
    /// leaves only the "yo" form, and only the first clause of a line opens it.
    private func lower(_ text: String) -> (age: Double, sex: PatientSex)? {
        let clauses = PatientNote.clausesWithOpening(text)
        let explicit = clauses.contains { PatientNote.statesAgeOrSex($0.clause) }
        for item in clauses {
            if let low = PatientNote.lowerAgeSex(item.clause, opensLine: item.opensLine, explicitElsewhere: explicit) { return (low.age, low.sex) }
        }
        return nil
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
            ("diabetic 61f with ESRD", 61, .female),
            ("Patient is a 44f for lap chole", 44, .female),
            ("- 68m for lap chole", 68, .male),
            ("5m for tonsillectomy", 5, .male),
            ("68m w/ HF for ECMO cannulation", 68, .male),
            ("68m presenting for CABG", 68, .male),
            ("elderly 88f here for hip fx", 88, .female),
            ("68m on apixaban for AF", 68, .male),
            ("26f in labor for epidural", 26, .female),
            ("68m, HTN, for lap chole", 68, .male),
            ("71f s/p TAVR", 71, .female),
            ("pt is 68m for TKA", 68, .male),
            ("Patient: 44f", 44, .female),
            ("68m 82kg for CABG", 68, .male),
            ("26f 160cm 55kg", 26, .female),
            ("26f 38 weeks for c-section", 26, .female),
            ("68m 3VD for CABG", 68, .male),
            ("68m/HTN/DM", 68, .male),
            ("Pt: 68m for CABG", 68, .male),
            ("pt is a 68m for TKA under spinal", 68, .male),
            ("healthy 26f for lap appy under GA", 26, .female),
            ("68m HTN DM2 CAD for CABG", 68, .male),
            ("CAD s/p CABG, 68m for redo sternotomy", 68, .male),
            ("68m.", 68, .male),
            ("5m, URI last week", 5, .male),
            ("26f", 26, .female),
            ("pt 68m for CABG", 68, .male),
            ("this is a 73m for AVR", 73, .male),
            ("A healthy 34f for lap chole", 34, .female),
            ("68m for CABG\nHTN, DM2", 68, .male),
            ("HTN, DM2\n68m for CABG", 68, .male),
            ("Pt is a 68m for CABG, ex tol poor, 50m with cane", 68, .male),
            ("Pt is a 72f with severe AS, 36m with syncope", 72, .female),
            ("this is a 62f for AVR, poor ex tol, 50m with cane", 62, .female),
            ("Ht 1.68m, 68m for CABG", 68, .male),
        ]
        for (line, years, s) in lines {
            let read = lower(line)
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
            "recent MI, 3m s/p PCI",
            "NSTEMI, 3m s/p DES",
            "angina, 2m with exertion",
            "SOB, 6m with exertion",
            "cough, 2m with hemoptysis",
            "on Eliquis, 3m for PE",
            "on Plavix, 12m for DES",
            "CVA, 6m s/p",
            "68 yo male w/ NSTEMI, 3m s/p DES, here for CABG",
            "68 yo male, 6m s/p CVA",
            "68 year old male with angina, 2m with exertion",
            "72 yo female, CAD, 12m s/p stent",
            "TURP, 22f",
            "foley, 16f for retention",
            "ECMO, 21f cannula",
            "Impella, 14f",
            "IABP, 8f",
            "chest tube, 28f",
            "DLT, 37f",
            "PICC, 5f",
            "CVC, 7f",
            "LHC via R radial, 6f",
            "pigtail, 8f",
            "NG, 14f",
            "6m s/p stent",
            "68 yo male, 3m post stent",
            "68yo male, 30m case",
            "age 45, 2f daughter at home",
            "62 yo, 6m post MI",
            "68 yo female, 3m post DES",
            "68 yo woman, 6m post stent, HTN",
            "6m-old girl for hernia repair",
            "3m-old",
            "fever, 99f for 2 days",
            "chest pain, 5m for each episode",
            "Plavix, 12m for DAPT",
            "45 yo f/u visit",
            "ECMO 21f arterial, 25f venous",
            "2 chest tubes, 19f Blake",
            "28f chest tube",
            "pt 3m s/p CABG",
            "patient 6m s/p MI",
            "patient 2m with chest pain",
            "CVA, 18m s/p",
            "on Plavix, 24m for DES",
            "CPB, 95m with",
            "cross-clamp, 45m with DHCA",
            "3m s/p DES to LAD",
            "12m s/p stent",
            "HTN, 12f",
            "O2, 4f via NC",
            "hypothermic, 94f with shivering",
            "able to walk a 50m with a cane",
            "pump run, 90m",
            "tourniquet, 60m",
            "apnea, 30m with bradycardia",
            "On Plavix; 12m for DES",
            "DAPT; 12m for DES",
            "Quit smoking; 6m.",
            "Prior stent. 6m, no angina",
            "DVT. 3m, on apixaban",
            "Hx MI; 24m s/p DES",
            "HTN; DM2; 24m s/p DES",
            "Chest pain, 30m with diaphoresis",
            "CP, 40m with SOB",
            "Syncope, 30m with prodrome",
            "Seizure, 30m with postictal confusion",
            "CPR, 30m with ROSC",
            "Poor ex tol, 50m with cane",
            "Limited exercise tolerance, 60m with rest stops",
            "NYHA III, 50m with SOB",
            "Claudication, 50m with walking",
            "Walks slowly, 50m, then SOB",
            "CABG 2018, 60m with patent grafts",
            "HIV, 30m with undetectable VL",
            "Dialysis, 36m with fistula",
            "Rewarm, 40m",
            "PACU, 30m with pain",
            "Chest pain, 30m with diaphoresis. 68M for CABG",
            "Hx MI; 24m s/p DES; 72F for AVR",
            "Plavix; 12m for DES. 68 yo M for CABG",
            "72 yo with CAD, HTN. 24m s/p DES, here for CABG",
            "68 yo, CAD. 30m s/p CABG",
            "Age 55, HTN, DM2. 30m s/p stent",
            "Female with PPCM. 30m s/p ICD",
            "Placed a 14f for drainage",
            "Inserted a 12f for decompression",
            "Needs a 7f for access",
            "Has a 12f for pleural effusion",
            "Replaced with a 20f for irrigation",
            "Upsized to a 20f with good flow",
            "MT 32f, PT 28f",
            "PT 28f",
            "Chest tubes MT 32f, PT 28f",
            "Foley placed. 16f.",
            "Chest tube placed. 28f with 400 out",
            "PICC placed. 5f.",
            "Impella placed. 14f",
            "Sheath placed. 7f",
            "Pericardial effusion. 14f for drainage",
            "Bile leak. 10f for drainage",
            "Extubated. 30m s/p, stable",
            "Spinal at 0830. 30m",
            "Rewarm. 40m with",
            "ACT 480. 40m",
            "Back from OR. 30m with",
            "Operative time 180m. 40m in PACU",
            "Protamine 300. 20m",
            "Pt intubated 45m, then extubated",
            "pt intubated 40m with difficulty",
            "Known 60m s/p MI",
            "24m s/p DES. 68 yo female for CABG",
            "30m s/p stent; 72 yo F",
            "chest pain, 45m with diaphoresis",
            "NSTEMI, 30m s/p DES",
            "pt 24m s/p CABG",
            "patient 36m s/p stent",
            "TIA, 30m with resolution",
            "ambulation, 50m with cane",
            "able to walk a 50m with a cane",
            "angina, 30m for 2 days",
            "CP, 30m for 3 days",
            "A 62f for AVR, poor ex tol, 50m with cane",
        ]
        for line in lines { XCTAssertNil(lower(line), line) }
    }

    func testOnlyTheFirstClauseOfALineOpensIt() {
        XCTAssertNotNil(PatientNote.lowerAgeSex("30m s/p stent", opensLine: true), "an adult opening the typed line is read as it stands")
        XCTAssertNil(PatientNote.lowerAgeSex("30m s/p stent", opensLine: false), "after a full stop or a semicolon it is a duration")
        XCTAssertNil(PatientNote.lowerAgeSex("68m for CABG", explicitElsewhere: true), "an age written out elsewhere is the patient's")
        XCTAssertEqual(PatientNote.lowerAgeSex("68 yo m for CABG", explicitElsewhere: true)?.age, 68, "the yo form is itself an age written out")
        let parts = PatientNote.clausesWithOpening("68m for CABG. HTN; DM2\nNo allergies. 30m walk")
        XCTAssertEqual(parts.map(\.clause), ["68m for CABG", "HTN", "DM2", "No allergies", "30m walk"])
        XCTAssertEqual(parts.map(\.opensLine), [true, false, false, true, false])
    }

    func testTheTokenIsFoundOnItsOwn() {
        XCTAssertEqual(PatientNote.standalone("68m", in: "Ht 1.68m, 68m for CABG"), NSRange(location: 10, length: 3))
        XCTAssertNil(PatientNote.standalone("68m", in: "Ht 1.68m"))
        XCTAssertNil(PatientNote.standalone("68m", in: "168mg"))
        XCTAssertEqual(PatientNote.standalone("68m", in: "68m"), NSRange(location: 0, length: 3))
    }

    // MARK: In the Preoperative bar

    func testTheBarReadsLowercaseAsItReadsCapitals() {
        let lines: [(String, Double, PatientSex)] = [("68m for lap chole", 68, .male), ("26f for lap appy", 26, .female), ("HTN, DM, 68m for CABG", 68, .male),
                                                     ("pt is a 68m for TKA", 68, .male), ("68yom for TAVR", 68, .male), ("26f, asthma", 26, .female), ("68m", 68, .male),
                                                     ("pt is a 68m for TKA under spinal", 68, .male), ("68m 82kg for CABG", 68, .male),
                                                     ("68m HTN DM2 CAD for CABG", 68, .male), ("BP 120/70, 55m for TKA", 55, .male)]
        for (line, years, s) in lines {
            let f = bar(line).findings
            XCTAssertEqual(age(f), years, line)
            XCTAssertEqual(sex(f), s, line)
        }
        // An age and a sex written out are the patient's: a lowercase duration beside them is not, in the same sentence or another.
        let explicit = bar("68 yo male w/ NSTEMI, 3m s/p DES, here for CABG").findings
        XCTAssertEqual(age(explicit), 68); XCTAssertEqual(sex(explicit), .male)
        let woman = bar("68 yo female, 3m post DES").findings
        XCTAssertEqual(age(woman), 68); XCTAssertEqual(sex(woman), .female)
        let later = bar("Chest pain, 30m with diaphoresis. 68M for CABG").findings
        XCTAssertEqual(age(later), 68); XCTAssertEqual(sex(later), .male)
        // The same lines in capitals read as they did.
        XCTAssertEqual(age(bar("68M for lap chole").findings), 68)
        XCTAssertEqual(sex(bar("68M for lap chole").findings), .male)
        XCTAssertEqual(sex(bar("26F for lap appy").findings), .female)
    }

    func testTheBarDoesNotReadADistanceOrATemperatureAsThePatient() {
        for line in ["walks 100m with walker", "walks 50m for exercise", "temp 101f with chills", "7f sheath in R groin", "seen 6m ago with chest pain",
                     "recent MI, 3m s/p PCI", "Impella, 14f", "on Plavix, 12m for DES", "ECMO 21f arterial, 25f venous", "Hgb 8.2 20m post transfusion",
                     "Chest pain, 30m with diaphoresis", "Poor ex tol, 50m with cane", "On Plavix; 12m for DES", "MT 32f, PT 28f"] {
            let f = bar(line).findings
            XCTAssertNil(age(f), line)
            XCTAssertNil(sex(f), line)
        }
    }

    /// Where the case is told, a number and an m is a time: the lowercase forms are the patient on the Preoperative bar only.
    func testTheLowercaseFormsAreNotReadOnTheBarsWhereTheCaseIsTold() {
        for line in ["40m in, norepi 0.05", "45m s/p incision", "68m for CABG"] {
            XCTAssertNil(age(bar(line, .intraop).findings), line)
            XCTAssertNil(sex(bar(line, .intraop).findings), line)
            XCTAssertNil(age(bar(line, .preop, handoff: true).findings), line + " (Summary & Handoff)")
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
        // After the other lowercase forms too.
        for (text, word) in [("Pt is a 68m for TKA.", "tka"), ("26 y/o f here for c-section.", "c-section")] {
            let r = PatientNote.read(text, now: now)
            XCTAssertNotNil(age(r.findings), text)
            if case .procedure(let p)? = r.findings.first(where: { $0.id == "procedure" })?.change {
                XCTAssertTrue(p.lowercased().contains(word), p)
            } else {
                XCTFail("no procedure read from: " + text)
            }
        }
        // An age written out wins over a lowercase duration, in the same sentence or another.
        let both = PatientNote.read("68 yo female, CAD, 12m s/p stent.", now: now)
        XCTAssertEqual(age(both.findings), 68); XCTAssertEqual(sex(both.findings), .female)
        let after = PatientNote.read("24m s/p DES. 68 yo female for CABG.", now: now)
        XCTAssertEqual(age(after.findings), 68); XCTAssertEqual(sex(after.findings), .female)
        // A temperature, a duration or a tube size is not a patient and a procedure, after a comma or a full stop.
        for text in ["Fever, 99f for 2 days.", "On Plavix, 12m for DAPT.", "Chest pain, 5m for each episode.", "Walks 50m for exercise daily.",
                     "Foley placed. 16f.", "Pericardial effusion. 14f for drainage.", "Extubated. 30m s/p, stable."] {
            let r = PatientNote.read(text, now: now)
            XCTAssertNil(age(r.findings), text); XCTAssertNil(sex(r.findings), text)
            XCTAssertNil(r.findings.first { $0.id == "procedure" }, text)
        }
    }
}
