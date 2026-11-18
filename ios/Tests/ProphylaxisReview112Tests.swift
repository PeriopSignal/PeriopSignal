import XCTest
@testable import PeriopSignal

/// The Surgical Prophylaxis calculator after its independent review (Nov 16): a weight outside Case Timers' plausible range works out
/// no number, a recorded tolerance is not an allergy, a section with nothing to choose never hides the quick reference, a result can
/// say what a bare table cell would not, and a result line is read aloud with its dose.
final class ProphylaxisReview112Tests: XCTestCase {

    private var bundleFile: ReferenceBundle!
    private var d: ProphylaxisData { bundleFile.prophylaxis! }
    private var t: CaseTimerData { bundleFile.caseTimers! }

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        bundleFile = try ReferenceLoader.decode(try Data(contentsOf: url))
    }

    override func tearDown() {
        ProphylaxisGate.available = true
    }

    private func adult(_ kg: Double?) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = kg
        return r
    }

    /// The standalone screen's record: the typed weight and nothing else.
    private func typed(_ kg: Double?) -> PatientRecord {
        var r = PatientRecord()
        r.weightKg = kg
        return r
    }

    private func cabg(allergy: Bool, record: PatientRecord) -> ProphylaxisAnswer {
        var i = ProphylaxisInput()
        i.chooseGroup("cardiac", data: d)
        i.chooseProcedure("cabg", data: d)
        i.betaLactamAllergy = allergy
        return ProphylaxisEngine.answer(i, record: record, data: d, timers: t)
    }

    private func line(_ a: ProphylaxisAnswer, _ agent: String) throws -> ProphylaxisLine {
        try XCTUnwrap(a.allLines.first { $0.agent == agent }, agent)
    }

    // MARK: The weight

    func testAWeightOutsideCaseTimersRangeWorksOutNoNumber() throws {
        XCTAssertEqual(t.weightFlag, [35, 200], "the range Case Timers itself flags")
        // 9 typed for 90: no "135 mg", the written rule and a line that says why.
        let slip = cabg(allergy: true, record: typed(9))
        XCTAssertEqual(try line(slip, "vancomycin").dose, "15 mg/kg")
        XCTAssertEqual(try line(slip, "vancomycin").needs, "Check the weight", "a weight was typed: never \"Weight needed\" beside it")
        XCTAssertEqual(slip.weightLine, "9 kg is outside 35–200 kg: check the weight. Doses are shown as written, not worked out for this weight.")
        XCTAssertEqual(try line(cabg(allergy: false, record: typed(9)), "cefazolin").dose, "2 g; 3 g if ≥120 kg")
        // A child's weight typed into the adult tool (the scratch record has no age) gets the same treatment.
        XCTAssertNotNil(cabg(allergy: false, record: typed(28)).weightLine)
        // Above the range too, and on a case's own record.
        let heavy = cabg(allergy: true, record: adult(400))
        XCTAssertEqual(try line(heavy, "vancomycin").dose, "15 mg/kg")
        XCTAssertEqual(heavy.weightLine?.hasPrefix("400 kg is outside 35–200 kg"), true)
        // In range, at both ends: worked out as before, no line.
        for kg in [35.0, 90, 200] {
            let a = cabg(allergy: true, record: typed(kg))
            XCTAssertNil(a.weightLine, "\(kg)")
            XCTAssertEqual(try line(a, "vancomycin").dose, CaseTimerEngine.antibioticDose(try XCTUnwrap(t.antibiotic("vancomycin")), record: typed(kg)).text)
            XCTAssertNil(try line(a, "vancomycin").needs)
        }
        XCTAssertEqual(try line(cabg(allergy: false, record: typed(125)), "cefazolin").dose, "3 g")
        // No weight at all is not "outside the range".
        XCTAssertNil(cabg(allergy: true, record: typed(nil)).weightLine)
        // The patient's weight is never changed.
        let r = adult(400)
        XCTAssertNil(ProphylaxisEngine.dosingRecord(r, timers: t).record.weightKg)
        XCTAssertEqual(r.weightKg, 400)
    }

    func testAnAbsurdlyLargeWeightDoesNotCrash() throws {
        // 20 digits typed or pasted into the weight field used to reach Int(...) inside the dose text and trap.
        for kg in [1e20, 99999999999999999999.0, Double.greatestFiniteMagnitude, 100000] {
            let a = cabg(allergy: true, record: typed(kg))
            XCTAssertEqual(try line(a, "vancomycin").dose, "15 mg/kg", "\(kg)")
            XCTAssertEqual(a.weightLine?.contains("check the weight"), true)
        }
        XCTAssertEqual(cabg(allergy: true, record: typed(1e20)).weightLine?.hasPrefix("This weight is outside 35–200 kg"), true)
        XCTAssertEqual(cabg(allergy: true, record: typed(99999)).weightLine?.hasPrefix("99,999 kg is outside"), true)
    }

    func testAChildOnTheCaseKeepsTheAdultOnlyLineAndGetsNoWeightLine() throws {
        var r = PatientRecord()
        r.ageYears = 8; r.weightKg = 28
        let a = cabg(allergy: false, record: r)
        XCTAssertNotNil(a.childLine)
        XCTAssertNil(a.weightLine, "one reason is enough: the child line already says no dose is shown")
        XCTAssertNil(try line(a, "cefazolin").dose)
    }

    // MARK: A recorded tolerance

    private func allergic(_ typed: String) -> PatientRecord {
        var r = adult(90)
        r.allergyList = AllergyCatalog.parse(typed)
        return r
    }

    func testARecordedToleranceDoesNotSetTheAllergy() throws {
        for typed in ["cefazolin tolerated", "PCN tolerated", "cefazolin - tolerated", "ceftriaxone (tolerates)", "amoxicillin well tolerated"] {
            let r = allergic(typed)
            XCTAssertFalse(ProphylaxisEngine.prefill(record: r, data: d).betaLactamAllergy, typed)
            XCTAssertNil(ProphylaxisEngine.prefill(record: r, data: d).allergyCaption, typed)
        }
        // A reaction, or a tolerance of ANOTHER drug written with a real reaction, is still the allergy.
        for typed in ["PCN - rash", "cefazolin anaphylaxis", "PCN (hives; tolerated cefazolin)", "penicillin"] {
            XCTAssertTrue(ProphylaxisEngine.prefill(record: allergic(typed), data: d).betaLactamAllergy, typed)
        }
        XCTAssertTrue(ProphylaxisAllergy.isTolerance(PatientAllergy(name: "Cefazolin", reaction: "tolerated")))
        XCTAssertFalse(ProphylaxisAllergy.isTolerance(PatientAllergy(name: "Cefazolin", reaction: "rash, later tolerated")))
        XCTAssertFalse(ProphylaxisAllergy.isTolerance(PatientAllergy(name: "Cefazolin", severity: "anaphylaxis", reaction: "tolerated")),
                       "a recorded severity is never read away")
        XCTAssertFalse(ProphylaxisAllergy.isTolerance(PatientAllergy(name: "Cefazolin", reaction: "")))
    }

    // MARK: The gate

    func testASectionWithNothingToChooseNeverHidesTheQuickReference() throws {
        XCTAssertTrue(d.isUsable)
        var empty = bundleFile!
        empty.prophylaxis = try JSONDecoder().decode(ProphylaxisData.self, from: Data(#"{"reviewed":"2026-11-12","groups":[]}"#.utf8))
        XCTAssertEqual(empty.prophylaxis?.isUsable, false)
        ProphylaxisGate.update(from: empty)
        XCTAssertFalse(ProphylaxisGate.available)
        XCTAssertEqual(RefRoute.prophylaxis.listed, .quickref("ashp-surgical-prophylaxis"), "the table is listed again")
        // A section whose groups did not decode (one of them is not an object) reads as no group, not as a failed bundle.
        let broken = try JSONDecoder().decode(ProphylaxisData.self, from: Data(#"{"groups":[{"id":"g","name":"G","procedures":[]}, 7]}"#.utf8))
        XCTAssertFalse(broken.isUsable)
        ProphylaxisGate.update(from: bundleFile)
        XCTAssertTrue(ProphylaxisGate.available)
        XCTAssertEqual(RefRoute.quickref("ashp-surgical-prophylaxis").listed, .prophylaxis)
    }

    // MARK: What a result shows in place of a bare cell

    func testAResultCanSayWhatTheBareCellWouldNot() throws {
        let shown = try JSONDecoder().decode(ProphylaxisResult.self, from: Data(#"{"text":"None","kind":"text","display":"No alternative agent listed"}"#.utf8))
        XCTAssertEqual(shown.display, "No alternative agent listed")
        XCTAssertEqual(shown.text, "None")
        let plain = try JSONDecoder().decode(ProphylaxisResult.self, from: Data(#"{"text":"A cell","kind":"text"}"#.utf8))
        XCTAssertNil(plain.display)
        // In the data only the ophthalmic row's alternative uses it, and every "none" result's cell really is "None".
        var withDisplay: [String] = []
        for g in d.groups { for p in g.procedures { for v in p.variants {
            for res in [v.recommended, v.allergy].compactMap({ $0 }) {
                if res.display != nil { withDisplay.append(g.id + "/" + p.id) }
                if res.kind == .none { XCTAssertEqual(res.text, "None", g.id + "/" + p.id) }
                if res.kind == .none { XCTAssertEqual(v.recommended?.kind, ProphylaxisResult.Kind.none, "no prophylaxis is never shown beside recommended agents: " + g.id + "/" + p.id) }
            }
        } } }
        XCTAssertEqual(withDisplay, ["ophthalmic/ophthalmic"])
    }

    // MARK: How a combination reads

    func testOrIsSaidOnlyBetweenWholeOptions() {
        // A slot that offers several agents is led by "one of"; a single agent by "plus"; the first slot by nothing unless it is a choice.
        XCTAssertNil(SurgicalProphylaxisView.joinerWord(optional: false, choices: 1, first: true))
        XCTAssertEqual(SurgicalProphylaxisView.joinerWord(optional: false, choices: 2, first: true), "one of")
        XCTAssertEqual(SurgicalProphylaxisView.joinerWord(optional: false, choices: 1, first: false), "plus")
        XCTAssertEqual(SurgicalProphylaxisView.joinerWord(optional: false, choices: 4, first: false), "plus one of")
        XCTAssertEqual(SurgicalProphylaxisView.joinerWord(optional: true, choices: 1, first: false), "with or without")
        XCTAssertEqual(SurgicalProphylaxisView.joinerWord(optional: true, choices: 2, first: false), "with or without one of")
        XCTAssertEqual(SurgicalProphylaxisView.joinerWord(optional: true, choices: 1, first: true), "with or without")
    }

    func testWithNoWeightAtAllItStillSaysWeightNeeded() throws {
        XCTAssertEqual(try line(cabg(allergy: true, record: typed(nil)), "vancomycin").needs, "Weight needed")
    }

    // MARK: Read aloud

    func testAResultLineIsReadWithItsDose() throws {
        let a = cabg(allergy: true, record: typed(90))
        XCTAssertEqual(SurgicalProphylaxisView.spoken(try line(a, "clindamycin")), "Clindamycin, 900 mg, Redose every 6 h")
        XCTAssertEqual(SurgicalProphylaxisView.spoken(try line(a, "vancomycin")),
                       "Vancomycin, 1,350 mg (15 mg/kg × 90 kg), No routine redose, Start within 120 min of incision.")
    }
}
