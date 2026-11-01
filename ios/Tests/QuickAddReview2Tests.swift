import XCTest
@testable import PeriopSignal

/// The second independent clinical-safety review of the quick-add bar (1.8, after the first review's fixes): variants
/// of the fixed lines, regressions from the new guards, the new behaviors (units by size, question chips, the planned
/// anesthetic, 90 or older), and the full-note path (PatientNote.read, as the full-note sheet reads a long paste or Fill
/// from a note). Each test states what clinically should happen. All lines are synthetic; no real patient data.
final class QuickAddReview2Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))! }

    private func read(_ s: String, _ tab: QuickAddTab = .preop, record: PatientRecord = PatientRecord(),
                      choices: [String: String] = [:]) -> QuickAddReading {
        QuickAdd.read(s, record: record, tab: tab, now: now, choices: choices)
    }
    private func ids(_ q: QuickAddReading) -> Set<String> { Set(q.findings.map(\.id)) }
    private func change(_ q: QuickAddReading, _ id: String) -> PatientNoteChange? { q.findings.first { $0.id == id }?.change }
    private func applied(_ q: QuickAddReading, to base: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = base
        PatientNote.apply(q.findings.map(\.change), to: &r)
        return r
    }
    private func setValues(_ q: QuickAddReading) -> [String: Double] { applied(q).intraopLabs.first?.values ?? [:] }
    private func drips(_ q: QuickAddReading) -> [String] { applied(q).infusions.map(\.drug) }
    /// The full-note path: what the full-note sheet reads.
    private func note(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func change(_ n: PatientNoteReading, _ id: String) -> PatientNoteChange? { n.findings.first { $0.id == id }?.change }

    // MARK: Blood: regressions from the broad guards

    /// "ready", "pending" or "planned" elsewhere in the piece says nothing about blood already given.
    func testBloodGuardWordsElsewhereInThePieceDoNotDropGivenBlood() {
        let ready = applied(read("2 PRBC given and 2 FFP ready", .intraop))
        XCTAssertEqual(ready.fluids["prbc"], 2, "the PRBC were given; only the FFP is ready")
        XCTAssertNil(ready.fluids["plasma"])
        // Review 3 ("ask when unsure"): "pending" in the clause makes each product a question chip; nothing is filed
        // until the user answers, and answering "given" files them.
        let line = "2 PRBC 2 FFP repeat TEG pending"
        let asked = read(line, .intraop)
        XCTAssertTrue(applied(asked).fluids.isEmpty, "nothing filed until the user answers: \(applied(asked).fluids)")
        XCTAssertEqual(Set(asked.ambiguous.map(\.id).filter { $0.hasPrefix(QuickAdd.bloodQuestion) }),
                       [QuickAdd.bloodQuestion + "prbc", QuickAdd.bloodQuestion + "plasma"])
        let answers = [QuickAdd.bloodQuestion + "prbc": QuickAdd.bloodGiven, QuickAdd.bloodQuestion + "plasma": QuickAdd.bloodGiven]
        let pending = applied(read(line, .intraop, choices: answers))
        XCTAssertEqual(pending.fluids["prbc"], 2, "the TEG is pending, not the blood")
        XCTAssertEqual(pending.fluids["plasma"], 2)
        XCTAssertEqual(applied(read("2 PRBC given as planned", .intraop)).fluids["prbc"], 2)
    }

    /// A total in parentheses after a count ("2 PRBC (total 4)"): 2 more, to 4. Read as a total of 2, it adds nothing.
    func testCountWithItsTotalIsNotUndercounted() {
        var given = PatientRecord()
        given.fluids["prbc"] = 2
        for line in ["2 PRBC (total 4)", "PRBC x2 (4 total)"] {
            let r = applied(read(line, .intraop, record: given), to: given)
            XCTAssertEqual(r.fluids["prbc"], 4, line + ": 2 more, 4 in all")
        }
    }

    /// Variants of "not given" after the product.
    func testNotGivenVariants() {
        for line in ["2 PRBC never given", "2 FFP returned to blood bank unused"] {
            let r = applied(read(line, .intraop))
            XCTAssertTrue(r.fluids.isEmpty, line + " → \(r.fluids)")
        }
        for line in ["2 PRBC not hung", "2 FFP cancelled", "PRBC x2 wasted"] {
            XCTAssertTrue(applied(read(line, .intraop)).fluids.isEmpty, line)
        }
    }

    /// "unit 3 of PRBC" is the third unit, not three units.
    func testUnitNumberIsNotACount() {
        XCTAssertNotEqual(applied(read("unit 3 of PRBC hanging", .intraop)).fluids["prbc"], 3)
    }

    /// The product-first fix on longer and mixed lines.
    func testProductFirstVariants() {
        let r = applied(read("PRBC 3 FFP 2 cryo 10 plt 1", .intraop))
        XCTAssertEqual(r.fluids["prbc"], 3)
        XCTAssertEqual(r.fluids["plasma"], 2)
        XCTAssertEqual(r.fluids["cryo"], 10)
        XCTAssertEqual(r.fluids["platelets"], 1)
        let mixed = applied(read("3 PRBC FFP 2", .intraop))
        XCTAssertEqual(mixed.fluids["prbc"], 3)
        XCTAssertEqual(mixed.fluids["plasma"], 2)
        let cs = applied(read("Cell saver: 1200 mL suctioned, 450 mL reinfused", .intraop))
        XCTAssertEqual(cs.fluids["cellSaver"], 450)
    }

    // MARK: Labs: regressions and variants

    /// A dose word elsewhere in the piece does not make a lab value a dose.
    func testDoseWordsDoNotDropLabValues() {
        XCTAssertEqual(setValues(read("gave CaCl 1 g for iCa 0.98", .intraop))["ica"], 0.98, "the iCa is a level")
        XCTAssertEqual(setValues(read("K 6.4 given insulin and calcium", .intraop))["k"], 6.4, "a K of 6.4 is a level")
        XCTAssertEqual(setValues(read("after 500 mL bolus Hb 8.4", .intraop))["hb"], 8.4)
    }

    /// A trend's next number must be the same test's value, not a dose: "then 2 PRBC", "then 1 amp".
    func testTrendDoesNotTakeADoseAsTheValue() {
        XCTAssertNotEqual(change(read("Hb 6.9 then 2 PRBC"), "lab:hb"), .lab("hb", 2), "a hemoglobin of 2 filed")
        XCTAssertNotEqual(setValues(read("K 6.4 then 1 amp CaCl", .intraop))["k"], 1, "a potassium of 1 filed")
    }

    /// "old" in "68-year-old" and "prior" in "prior CABG" do not make a lab value an earlier one.
    func testAgeAndHistoryWordsDoNotDropLabValues() {
        XCTAssertEqual(change(read("68-year-old man HTN K 5.4"), "lab:k"), .lab("k", 5.4))
        XCTAssertEqual(change(read("72 year old male Cr 1.6"), "lab:cr"), .lab("cr", 1.6))
        XCTAssertEqual(change(read("prior CABG K 4.1"), "lab:k"), .lab("k", 4.1))
    }

    /// A venous gas named without the word "gas".
    func testVenousValuesWithoutTheWordGas() {
        let q = read("venous pH 7.28 pCO2 55", .intraop)
        XCTAssertNil(setValues(q)["ph"], "\(setValues(q))")
        XCTAssertNil(setValues(q)["paco2"])
    }

    /// iCa from 3 to 7: nothing filed until mg/dL is chosen; outside both units, nothing.
    func testIonizedCalciumQuestion() {
        let asked = read("iCa 4.6", .intraop)
        XCTAssertNil(setValues(asked)["ica"])
        XCTAssertTrue(asked.ambiguous.contains { $0.id == QuickAdd.icaQuestion })
        XCTAssertNil(setValues(read("iCa 4.6", .intraop, choices: [QuickAdd.icaQuestion: MedAbbreviations.asWritten]))["ica"], "left out")
        XCTAssertEqual(setValues(read("iCa 4.6", .intraop, choices: [QuickAdd.icaQuestion: QuickAdd.icaAnswer]))["ica"], 1.15)
        XCTAssertNil(setValues(read("iCa 2.8", .intraop))["ica"])
        XCTAssertEqual(setValues(read("iCa 1.12", .intraop))["ica"], 1.12)
    }

    // MARK: Drips: induction, codes and guard regressions

    /// An induction sequence is boluses (mg and mcg), not infusions.
    func testInductionSequenceIsNotInfusions() {
        for line in ["prop 200, roc 50, fent 100", "induction: propofol 150, sux 100", "prop 200 roc 50 fent 100"] {
            XCTAssertTrue(drips(read(line, .intraop)).isEmpty, line + " → \(applied(read(line, .intraop)).infusions.map(\.text))")
        }
    }

    /// Epinephrine in a code is 1 mg boluses, not a drip.
    func testCodeEpinephrineIsNotADrip() {
        for line in ["code: epi 1, CPR, shock 200 J", "VF arrest, epi 1 q3min"] {
            XCTAssertTrue(drips(read(line, .intraop)).isEmpty, line + " → \(applied(read(line, .intraop)).infusions.map(\.text))")
        }
    }

    /// Two drips written together, or beside a balloon pump ratio, are both read.
    func testDripGuardsDoNotDropRealDrips() {
        for line in ["norepi 0.1 with epi 0.03", "milrinone 0.25 w/ epi 0.02", "IABP 1:1 epi 0.05 milrinone 0.25"] {
            let d = drips(read(line, .intraop))
            XCTAssertTrue(d.contains("Epinephrine"), line + " → \(d)")
            XCTAssertEqual(d.count, 2, line + " → \(d)")
        }
        XCTAssertEqual(applied(read("home milrinone 0.375 x 6 months via PICC")).homeInfusions.map(\.drug), ["Milrinone"],
                       "a home infusion running for six months")
    }

    /// Carbidopa-levodopa written without the hyphen.
    func testLevodopaVariants() {
        for line in ["PD on L dopa 3 times daily"] {
            XCTAssertTrue(applied(read(line)).homeInfusions.isEmpty, line + " → \(applied(read(line)).homeInfusions.map(\.text))")
        }
    }

    // MARK: Airway variants

    /// The mask grade written other ways is still not the view grade.
    func testMaskGradeVariants() {
        for line in ["easy mask (grade 1), DL grade 3, 7.5 ETT", "mask: grade 1, DL: grade 3, 7.0 ETT",
                     "Mask ventilation: grade 1; laryngoscopy: grade 3; 7.5 ETT"] {
            XCTAssertNotEqual(applied(read(line, .intraop)).laryngoscopyGrade, "1", line + ": the mask grade filed as the view")
        }
    }

    /// One attempt with each of two laryngoscopes is two attempts.
    func testOneAttemptEachIsTwoAttempts() {
        XCTAssertNotEqual(applied(read("DL 1 attempt failed, VL 1 attempt success, 7.0 ETT", .intraop)).attempts, 1)
    }

    /// A backup named in the same phrase does not hide the laryngoscope used.
    func testBackupInTheSamePhrase() {
        XCTAssertEqual(applied(read("DL grade 1 with VL backup, 7.5 ETT", .intraop)).airwayDevice, "Direct laryngoscope")
    }

    /// Two laryngoscopies: nothing about either is filed until one is chosen; the tube still is.
    func testLaryngoscopyQuestionFilesNothingUntilAnswered() {
        let line = "DL grade 3, VL grade 1, 7.0 ETT"
        let q = read(line, .intraop)
        XCTAssertTrue(q.ambiguous.contains { $0.id == QuickAdd.laryngoscopyQuestion })
        let r = applied(q)
        XCTAssertNil(r.airwayDevice)
        XCTAssertNil(r.laryngoscopyGrade)
        XCTAssertEqual(r.tube, "7.0 ETT")
        let left = applied(read(line, .intraop, choices: [QuickAdd.laryngoscopyQuestion: MedAbbreviations.asWritten]))
        XCTAssertNil(left.airwayDevice)
        XCTAssertNil(left.laryngoscopyGrade)
    }

    // MARK: Tabs

    /// A dental injury or stridor in the OR is not the preoperative airway exam.
    func testIntraoperativeAirwayEventsAreNotThePreopExam() {
        let q = read("DL grade 2b, chipped tooth, stridor after extubation", .intraop)
        XCTAssertFalse(q.findings.contains { if case .dentition = $0.change { return true }; return false }, "\(q.findings.map(\.label))")
        XCTAssertFalse(q.findings.contains { if case .airwaySign = $0.change { return true }; return false }, "\(q.findings.map(\.label))")
    }

    // MARK: New behaviors

    /// SpO₂ without room air: nothing filed until answered, and nothing when left out.
    func testRoomAirQuestionFilesNothingUntilAnswered() {
        let q = read("BP 120/80 HR 70 SpO2 95%")
        XCTAssertNil(change(q, "vital:spo2"))
        XCTAssertTrue(q.ambiguous.contains { $0.id == QuickAdd.roomAirQuestion })
        XCTAssertNil(change(read("BP 120/80 HR 70 SpO2 95%", choices: [QuickAdd.roomAirQuestion: MedAbbreviations.asWritten]), "vital:spo2"))
        XCTAssertNil(change(read("BP 120/80 HR 70 SpO2 95%", choices: [QuickAdd.roomAirQuestion: QuickAdd.oxygenAnswer]), "vital:spo2"))
        XCTAssertEqual(change(read("sats 95 on room air"), "vital:spo2"), .vital("spo2", 95))
    }

    /// The usual plan is filled only when no technique is named.
    func testPlannedAnestheticNotFilledOverANamedTechnique() {
        for line in ["72F for L TKA under block", "72F for L TKA with ACB and GA"] {
            let q = read(line)
            XCTAssertFalse(q.findings.contains { $0.id.hasPrefix(QuickAdd.planPrefix + "neuraxial") },
                           line + ": the usual plan proposed over the one written → \(q.findings.map(\.label))")
        }
    }

    /// 90 or older wherever the age comes from.
    func testNinetyOrOlder() {
        let q = read("95 yo F for hip fracture")
        XCTAssertEqual(change(q, "age"), .age(90))
        XCTAssertEqual(q.findings.first { $0.id == "age" }?.label, "Age 90 or older")
        var r = PatientRecord()
        r.ageYears = 97
        r.sex = .female
        XCTAssertEqual(r.ageYears, 90)
        XCTAssertEqual(r.person, "Woman, 90 or older")
        XCTAssertEqual(change(note("aged 93, HTN"), "age"), .age(90))
    }

    /// "Tmax 101F" is a temperature, not a 101-year-old woman.
    func testFahrenheitIsNotAgeAndSex() {
        let q = read("febrile, Tmax 101F, WBC 14")
        XCTAssertNil(change(q, "age"), "\(q.findings.map(\.label))")
        XCTAssertNil(change(q, "sex"))
        let n = note("Febrile overnight, Tmax 101F. WBC 14.")
        XCTAssertNil(change(n, "age"), "full-note path: \(n.findings.map(\.label))")
        XCTAssertNil(change(n, "sex"))
    }

    // MARK: Planned lines (both paths)

    /// A plan that starts with the technique, or a plan word after the list, still makes the lines planned.
    func testPlannedLineVariants() {
        func planned(_ fs: [PatientNoteFinding]) -> [String] {
            fs.compactMap { f -> String? in
                guard case .devices(let ds) = f.change, ds.contains(where: { $0.kind == .arterial || $0.kind == .pac }) else { return nil }
                return f.label
            }
        }
        for line in ["72M for AVR, plan GA/ETT, A-line, PAC", "Access: 18G PIV; A-line, PAC planned"] {
            XCTAssertTrue(planned(read(line).findings).isEmpty, line + " → \(planned(read(line).findings))")
            XCTAssertTrue(planned(note(line).findings).isEmpty, "full-note path: " + line + " → \(planned(note(line).findings))")
        }
    }

    // MARK: The full-note path (PatientNote.read)

    /// A trend or an earlier value: the current value, not the first number.
    func testFullNoteTrendsFileTheCurrentValue() {
        XCTAssertNotEqual(change(note("Cr 0.9 → 1.6"), "lab:cr"), .lab("cr", 0.9))
        XCTAssertNotEqual(change(note("baseline Cr 1.1, now 1.6"), "lab:cr"), .lab("cr", 1.1))
        XCTAssertNotEqual(change(note("Hb 11 -> 7.8"), "lab:hb"), .lab("hb", 11))
    }

    /// Fixed in the note reader for both paths: a venous saturation before the number, a hemolyzed potassium, names.
    func testFullNoteFixesHold() {
        XCTAssertNil(change(note("mixed venous sat 58%"), "vital:spo2"))
        XCTAssertNotNil(note("K 6.1 hemolyzed").findings.first { $0.id == "lab:k" }?.note)
        XCTAssertTrue(note("Name: Jane Doe, 68F for lap chole").identifiers.contains("a name"))
        XCTAssertTrue(note("Mrs O'Brien 70F HTN").identifiers.contains("a name"))
        XCTAssertEqual(change(note("92F for hip fracture"), "age"), .age(90))
    }

    /// A venous saturation written after the number.
    func testFullNoteVenousSaturationAfterTheNumber() {
        XCTAssertNil(change(note("sat 58% (mixed venous)"), "vital:spo2"))
        XCTAssertNil(change(read("sat 58% (mixed venous)"), "vital:spo2"))
    }

    /// The full-note sheet adds "Other conditions" by default when no identifier is flagged: a name or date of birth
    /// it does not recognize would be filed there.
    func testFullNoteUnflaggedIdentifiersAreNotFiledAsOtherConditions() {
        for text in ["Patient: Jane Doe\n68F for lap chole, HTN", "born 4 March 1950, 72M HTN"] {
            let n = note(text)
            XCTAssertTrue(!n.identifiers.isEmpty || !(n.other.contains("Jane") || n.other.contains("1950")),
                          "filed into Other conditions by default: " + n.other)
        }
    }

    /// The full-note path files a saturation as room air without asking (the bar now asks).
    func testFullNoteSaturationWithoutRoomAir() {
        let f = note("SpO2 92%").findings.first { $0.id == "vital:spo2" }
        XCTAssertTrue(f == nil || f?.note != nil, "filed into SpO₂ on room air with no caution")
    }
}
