import XCTest
@testable import PeriopSignal

/// An independent clinical-safety review of the quick-add bar (QuickAdd, 1.8): shorthand clinicians really type, each
/// test stating what clinically should happen. All lines are synthetic; no real patient data.
final class QuickAddReviewTests: XCTestCase {
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
    /// The values of the intraoperative set the line adds.
    private func setValues(_ q: QuickAddReading) -> [String: Double] { applied(q).intraopLabs.first?.values ?? [:] }
    /// What the line says, everywhere a person sees it or it is filed: findings' labels and the "Not read" text.
    private func shown(_ q: QuickAddReading) -> String { (q.findings.map(\.label) + [q.unread] + q.skipped).joined(separator: " | ") }

    // MARK: Blood products

    /// "PRBC 3 FFP 2" (product first, no commas) is typed constantly in the OR. Each count belongs to the product
    /// before it; reading "3 FFP" first gives the PRBC count to the plasma and the FFP count to the red cells.
    func testProductFirstWithoutCommasKeepsEachCountWithItsProduct() {
        for line in ["PRBC 3 FFP 2", "PRBC x3 FFP x2", "PRBC 3u FFP 2u"] {
            let r = applied(read(line, .intraop))
            XCTAssertEqual(r.fluids["prbc"], 3, line)
            XCTAssertEqual(r.fluids["plasma"], 2, line)
        }
        let swapped = applied(read("FFP 2 PRBC 1", .intraop))
        XCTAssertEqual(swapped.fluids["plasma"], 2)
        XCTAssertEqual(swapped.fluids["prbc"], 1)
    }

    /// "cryo 10 FFP 2": ten units of cryoprecipitate and two of plasma, not ten units of plasma.
    func testCryoCountIsNotGivenToTheNextProduct() {
        let r = applied(read("cryo 10 FFP 2", .intraop))
        XCTAssertNotEqual(r.fluids["plasma"], 10, "10 is the cryo count")
        XCTAssertEqual(r.fluids["cryo"], 10)
    }

    /// Negation after the product ("not given", "held", "declined") means it was not given.
    func testBloodNegatedAfterTheProductIsNotGiven() {
        for line in ["2 PRBC not given", "2 FFP held", "PRBC x2 declined by family"] {
            let r = applied(read(line, .intraop))
            XCTAssertTrue(r.fluids.isEmpty, line + " → \(r.fluids)")
        }
    }

    /// Planned or conditional blood is not blood given.
    func testPlannedOrConditionalBloodIsNotGiven() {
        for line in ["plan 2 PRBC", "will give 2 FFP", "2 PRBC if Hb < 7", "2 PRBC pending"] {
            let r = applied(read(line, .intraop))
            XCTAssertTrue(r.fluids.isEmpty, line + " → \(r.fluids)")
        }
    }

    /// "PRBC 3rd unit" is the third unit (one more), not three more.
    func testOrdinalUnitIsNotAUnitCount() {
        let r = applied(read("PRBC 3rd unit hanging", .intraop))
        XCTAssertNotEqual(r.fluids["prbc"], 3, "an ordinal, not a count")
    }

    /// A running total restated ("4 PRBC total") must not be added on top of the total already recorded.
    func testCumulativeTotalIsNotAddedToTheTotal() {
        var given = PatientRecord()
        given.fluids["prbc"] = 2
        let r = applied(read("4 PRBC total", .intraop, record: given), to: given)
        XCTAssertNotEqual(r.fluids["prbc"], 6, "the case total is 4, not 6")
    }

    /// Cell saver volume processed is not the volume returned to the patient.
    func testCellSaverProcessedIsNotReturned() {
        let r = applied(read("cell saver: 800 mL processed, 350 mL returned", .intraop))
        XCTAssertNotEqual(r.fluids["cellSaver"], 800, "800 mL was processed; 350 mL was given back")
    }

    /// Restatements are counted once.
    func testRestatedDosesAreCountedOnce() {
        XCTAssertEqual(applied(read("1 pool cryo (5 u)", .intraop)).fluids["cryo"], 5)
        XCTAssertEqual(applied(read("cryo 10 (2 pools)", .intraop)).fluids["cryo"], 10)
        XCTAssertEqual(applied(read("PRBC x2 (2 units)", .intraop)).fluids["prbc"], 2)
        let ml = applied(read("2 PRBC (600 mL)", .intraop))
        XCTAssertEqual(ml.fluids["prbc"], 2)
        XCTAssertNil(ml.fluids["cellSaver"])
        XCTAssertNil(applied(read("350 mL PRBC", .intraop)).fluids["prbc"], "a volume, not 350 units")
    }

    /// Blood given before the case is not part of this case's intraoperative total.
    func testBloodGivenBeforeTheCaseIsNotTheCases() {
        XCTAssertNil(applied(read("2 PRBC yesterday", .intraop)).fluids["prbc"])
    }

    /// A platelet count and a platelet dose.
    func testPlateletCountIsNotADose() {
        let q = read("plt 45, Hb 7.9", .intraop)
        XCTAssertNil(applied(q).fluids["platelets"])
        XCTAssertEqual(setValues(q)["plt"], 45)
    }

    // MARK: Labs

    /// Ionized calcium is often reported in mg/dL in the US (normal about 4.6–5.3 mg/dL = 1.15–1.33 mmol/L). "iCa 3.9"
    /// is hypocalcemia in mg/dL (0.97 mmol/L); read as 3.9 mmol/L it is flagged high, the opposite.
    func testIonizedCalciumInMilligramsIsNotReadAsMillimoles() {
        let q = read("iCa 3.9", .intraop)
        XCTAssertNil(setValues(q)["ica"], "3.9 is not a physiological ionized calcium in mmol/L")
        XCTAssertNil(setValues(read("iCa 4.6", .intraop))["ica"])
        XCTAssertEqual(setValues(read("iCa 1.02", .intraop))["ica"], 1.02)
    }

    /// "CBC 7.4/11/180" (WBC/Hb/Plt) on the Intraoperative tab is not a blood gas of pH 7.40, PaCO₂ 11, PaO₂ 180.
    func testSlashedCBCIsNotABloodGas() {
        let q = read("CBC 7.4/11/180", .intraop)
        XCTAssertNil(setValues(q)["ph"], "\(setValues(q))")
        XCTAssertNil(setValues(q)["paco2"])
    }

    /// A venous gas typed by name: its PO₂ is not a PaO₂ and its PCO₂ is not a PaCO₂.
    func testVenousGasByNameIsNotArterial() {
        let q = read("VBG pH 7.31 pCO2 48 pO2 40", .intraop)
        XCTAssertNil(setValues(q)["pao2"], "a venous PO₂ filed as PaO₂ 40 (flagged low)")
        XCTAssertNil(setValues(q)["paco2"])
    }

    /// A trend ("0.9 → 1.6") ends on the current value: filing the first number files the old one.
    func testTrendFilesTheCurrentValue() {
        XCTAssertNotEqual(change(read("Cr 0.9 → 1.6"), "lab:cr"), .lab("cr", 0.9), "baseline filed as the current creatinine")
        XCTAssertNotEqual(setValues(read("Hb 11 -> 7.8", .intraop))["hb"], 11, "the pre-bleed hemoglobin filed as now")
        XCTAssertNotEqual(setValues(read("ABG 7.21/55/68 → 7.32/42/180", .intraop))["ph"], 7.21, "the earlier gas filed as now")
    }

    /// "in fib 130s": a rhythm and a rate, not a fibrinogen of 130 mg/dL.
    func testFibrillationRateIsNotAFibrinogen() {
        XCTAssertNil(setValues(read("in fib 130s, amio 150", .intraop))["fibrinogen"])
    }

    /// A hemolyzed potassium is spurious: not filed as is, or filed with a caution.
    func testHemolyzedPotassiumIsNotFiledAsIs() {
        let f = read("K 6.1 hemolyzed").findings.first { $0.id == "lab:k" }
        XCTAssertTrue(f == nil || f?.note != nil, "K 6.1 H filed with no word of the hemolysis")
    }

    /// Other orders people type are not read into the wrong cells.
    func testOtherPanelOrdersAreNotMisread() {
        XCTAssertTrue(read("138/4.1/102/24/18/1.1/162/9.2").findings.isEmpty, "an eighth value (calcium): not the 7-value BMP")
        XCTAssertNotEqual(change(read("PT/INR 14/1.2"), "lab:inr"), .lab("inr", 14))
        XCTAssertTrue(read("Coags 14/35/1.2").findings.isEmpty)
        XCTAssertTrue(read("138/102/18/162/4.1/24/1.1").findings.isEmpty, "top row then bottom row: not this order")
    }

    /// A drug given is not a lab value: "bicarb 1 amp" is 50 mEq of sodium bicarbonate, not a bicarbonate of 1 mmol/L;
    /// "K 10 IV" is a potassium rider, not a potassium of 10.
    func testDrugDosesAreNotLabValues() {
        XCTAssertNil(setValues(read("bicarb 1 amp, CaCl 1 g", .intraop))["hco3a"], "a bicarbonate of 1 filed")
        XCTAssertNil(setValues(read("bicarb 50 given", .intraop))["hco3a"], "a bicarbonate of 50 filed")
        XCTAssertNil(setValues(read("K 10 IV over 1 hr", .intraop))["k"], "a potassium of 10 filed")
    }

    /// A value the line marks as earlier (baseline, preop) is not the current one.
    func testEarlierValuesAreNotCurrent() {
        XCTAssertNotEqual(change(read("baseline Cr 1.1, now 1.6"), "lab:cr"), .lab("cr", 1.1))
        XCTAssertNotEqual(setValues(read("preop Hb 12.1, now 8.2", .intraop))["hb"], 12.1, "a preop value filed in a set stamped now")
    }

    /// Units: conventional units read; SI values and doses not.
    func testLabUnits() {
        XCTAssertEqual(change(read("Hb 9.1 g/dL"), "lab:hb"), .lab("hb", 9.1))
        XCTAssertEqual(change(read("K 4.1 mEq/L"), "lab:k"), .lab("k", 4.1))
        XCTAssertNil(change(read("Hb 91 g/L"), "lab:hb"))
        XCTAssertNil(change(read("Cr 110 umol/L"), "lab:cr"))
        XCTAssertNil(change(read("Glu 7.2 mmol/L"), "lab:glucose"))
        XCTAssertNil(change(read("albumin 5% 250 mL"), "lab:albumin"), "5% albumin is a fluid")
        XCTAssertTrue(applied(read("KCl 10 mEq IV")).labs.isEmpty)
    }

    // MARK: Vital signs

    /// °F to °C, labeled, bare and in the note reader's path.
    func testFahrenheitConversions() {
        XCTAssertEqual(change(read("BP 120/80 HR 70 T 100.4"), "vital:temp"), .vital("temp", 38))
        XCTAssertEqual(change(read("BP 120/80 HR 70 T 96.8F"), "vital:temp"), .vital("temp", 36))
        XCTAssertEqual(change(read("BP 120/80 HR 70 36.4"), "vital:temp"), .vital("temp", 36.4))
        XCTAssertEqual(change(read("T 101.3"), "vital:temp"), .vital("temp", 38.5))
        XCTAssertEqual(change(read("Temp 38.4"), "vital:temp"), .vital("temp", 38.4))
        XCTAssertNil(change(read("BP 120/80 HR 70 T 50"), "vital:temp"), "neither °C nor °F")
    }

    /// A pulmonary artery pressure written with a word between ("PA pressure 55/30") is not the blood pressure.
    func testPAPressureWithAWordIsNotTheBloodPressure() {
        let q = read("PA pressure 55/30, HR 80")
        XCTAssertNil(change(q, "vital:sbp"), "filed BP 55/30")
        XCTAssertNil(change(read("PA pressures 60/25 HR 90"), "vital:sbp"))
    }

    /// A mixed venous saturation is not the SpO₂.
    func testMixedVenousSaturationIsNotSpO2() {
        XCTAssertNil(change(read("RHC: PCWP 25, CI 1.9, mixed venous sat 58%"), "vital:spo2"))
    }

    // MARK: Drips

    /// Epinephrine in a local anesthetic (1:200,000) is not an epinephrine infusion at "1".
    func testLocalAnestheticWithEpinephrineIsNotADrip() {
        for line in ["lidocaine 1% with epi 1:200,000 10 mL", "ropi 0.5% w/ epi 1:200k"] {
            let r = applied(read(line, .intraop))
            XCTAssertTrue(r.infusions.isEmpty, line + " → \(r.infusions.map(\.text))")
        }
    }

    /// A code dose ("epi 1 amp") is a bolus, not a drip at 1.
    func testCodeDoseIsNotADrip() {
        let r = applied(read("epi 1 amp x2", .intraop))
        XCTAssertTrue(r.infusions.isEmpty, "\(r.infusions.map(\.text))")
    }

    /// Carbidopa-levodopa ("L-dopa") is not a dopamine infusion.
    func testLevodopaIsNotDopamine() {
        let r = applied(read("PD on L-dopa 3x daily"))
        XCTAssertTrue(r.homeInfusions.isEmpty, "\(r.homeInfusions.map(\.text))")
    }

    /// A drip with its unit is read with it.
    func testDripWithItsUnit() {
        XCTAssertEqual(applied(read("epi 0.05 mcg/kg/min", .intraop)).infusions.first?.rate, "0.05 mcg/kg/min")
        XCTAssertTrue(applied(read("heparin 30000 units", .intraop)).infusions.isEmpty, "a bolus")
    }

    // MARK: The intraoperative airway

    /// "grade 1 mask, DL grade 3": a Han mask grade 1 and a Cormack–Lehane view grade 3. Filing grade 1 as the view
    /// records a difficult laryngoscopy as an easy one.
    func testMaskGradeIsNotTheViewGrade() {
        let r = applied(read("grade 1 mask, DL grade 3, bougie, 7.5 ETT", .intraop))
        XCTAssertNotEqual(r.laryngoscopyGrade, "1", "the mask grade filed as the view")
    }

    /// A laryngoscope in the room is not the one used.
    func testDeviceOnStandbyIsNotTheDeviceUsed() {
        let r = applied(read("DL grade 1, VL in room, 7.5 ETT", .intraop))
        XCTAssertNotEqual(r.airwayDevice, "Video laryngoscope")
    }

    /// DL grade 3 then VL grade 1: a device and a grade from different laryngoscopies must not be paired.
    func testTwoLaryngoscopiesKeepTheirGrades() {
        let r = applied(read("DL grade 3, VL grade 1, 7.0 ETT", .intraop))
        XCTAssertFalse(r.airwayDevice == "Video laryngoscope" && r.laryngoscopyGrade == "3", "VL recorded as grade 3")
        XCTAssertFalse(r.airwayDevice == "Direct laryngoscope" && r.laryngoscopyGrade == "1", "DL recorded as grade 1")
    }

    /// A failed first attempt and a second one is two attempts.
    func testAttemptsCountEveryAttempt() {
        let r = applied(read("1st attempt DL failed, 2nd attempt VL, 7.0 ETT", .intraop))
        XCTAssertNotEqual(r.attempts, 1, "two attempts recorded as one")
    }

    // MARK: Tabs

    /// What happens in the OR is not the patient's preoperative history, risk assessment or home medications.
    func testIntraoperativeEventsAreNotPreoperativeHistory() {
        let af = read("new AF w RVR after bypass, amio 150", .intraop)
        XCTAssertFalse(ids(af).contains("problem:af"), "intraoperative AF filed as a history of AF")
        XCTAssertFalse(ids(af).contains { $0.hasPrefix("acute:") }, "an acute cardiac condition added to the preop assessment")
        let tachy = read("tachycardic to 140s, esmolol 20", .intraop)
        XCTAssertFalse(ids(tachy).contains { $0.hasPrefix("symptom:") }, "a cardiac symptom added to the preop assessment")
        let given = read("heparin 30000 u, metoprolol 5 mg IV", .intraop)
        XCTAssertFalse(given.findings.contains { if case .medFlag = $0.change { return true }; return false },
                       "drugs given in the OR filed as home medicine flags: \(given.findings.map(\.label))")
        XCTAssertFalse(given.findings.contains { if case .medications = $0.change { return true }; return false },
                       "drugs given in the OR filed as the home medication list")
    }

    /// Planned lines are not lines in place.
    func testPlannedLinesAreNotPresent() {
        for line in ["68M for CABG, plan A-line, PAC", "Plan: A-line, PAC, TEE"] {
            let q = read(line)
            XCTAssertFalse(q.findings.contains { $0.id.hasPrefix("device:") }, line + " → \(q.findings.map(\.label))")
        }
    }

    // MARK: Identifiers

    /// "Name: Jane Doe" is a name.
    func testNameAfterAColonIsMasked() {
        let q = read("Name: Jane Doe, 68F for lap chole")
        XCTAssertTrue(q.identifiers.contains("a name"))
        XCTAssertFalse(shown(q).contains("Jane") || shown(q).contains("Doe"), shown(q))
        XCTAssertNotNil(change(q, "procedure"), "the rest is still read")
    }

    /// The whole surname is masked.
    func testWholeSurnameIsMasked() {
        let mc = read("Mr McDonald 68M HTN")
        XCTAssertFalse(shown(mc).contains("Donald"), shown(mc))
        let ob = read("Mrs O'Brien 70F HTN")
        XCTAssertTrue(ob.identifiers.contains("a name"))
        XCTAssertFalse(shown(ob).contains("Brien"), shown(ob))
    }

    /// A date of birth written day first with the month in words.
    func testDayFirstDateOfBirthIsMasked() {
        let q = read("DOB 4 March 1950, 72M HTN")
        XCTAssertFalse(shown(q).contains("1950") || shown(q).contains("March"), shown(q))
        XCTAssertEqual(change(q, "age"), .age(72))
    }

    /// Identifiers in common forms are masked and nothing is filed from them.
    func testCommonIdentifiersAreMaskedAndNotFiled() {
        let lines = ["DOB 03/04/1950 72M HTN", "72M HTN, call (216) 555-0100", "MRN: 00123456 72M HTN", "acct 4455667 72M HTN",
                     "BP 120/80 HR 72, cell 216-555-0100"]
        for line in lines {
            let q = read(line)
            XCTAssertFalse(q.identifiers.isEmpty, line)
            for digits in ["1950", "555", "00123456", "4455667"] {
                XCTAssertFalse(shown(q).contains(digits), line + " → " + shown(q))
            }
        }
        XCTAssertEqual(change(read("BP 120/80 HR 72, cell 216-555-0100"), "vital:hr"), .vital("hr", 72))
    }

    /// HIPAA Safe Harbor: ages over 89 are identifiers unless aggregated as 90 or older.
    func testAgeOverEightyNineIsAggregated() throws {
        try XCTSkipIf(true, "Waiting on Ben's decision on ages over 89 (shown as 90 or older); not implemented yet.")
        XCTAssertNotEqual(change(read("92F for hip fracture"), "age"), .age(92))
    }
}
