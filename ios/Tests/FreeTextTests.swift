import XCTest
@testable import PeriopSignal

/// 1.8.3 (Ben): free-text entries start with a capital, on the screen's summaries, the handoff and the History list, and
/// when typed.
final class FreeTextTests: XCTestCase {
    // MARK: The function

    func testCapitalizesTheFirstLetter() {
        XCTAssertEqual(FreeText.cap("metoprolol"), "Metoprolol")
        XCTAssertEqual(FreeText.cap("  adhesive tape"), "Adhesive tape")
        XCTAssertEqual(FreeText.cap("s/p CABG"), "S/p CABG")
        XCTAssertEqual(FreeText.cap("metoprolol/HCTZ"), "Metoprolol/HCTZ")
        XCTAssertEqual(FreeText.cap("- aspirin"), "- Aspirin", "leading punctuation is skipped")
        XCTAssertEqual(FreeText.cap("(rash) to penicillin"), "(Rash) to penicillin")
        XCTAssertEqual(FreeText.cap("stroke 2019. residual weakness"), "Stroke 2019. residual weakness", "only the first letter of a note")
        XCTAssertEqual(FreeText.cap("pre-op echo"), "Pre-op echo")
    }

    func testLeavesWhatIsAlreadyRightOrMeaningful() {
        for s in ["eGFR 45", "pH 7.2", "iCa low", "3 vessel disease", "mL/kg", "NTproBNP high", "iPad", "On levetiracetam", "Metoprolol", "",
                  "mg daily", "mcg/kg/min", "kg", "dL", "mmHg", "q6h prn", "q4-6h", "x3 weeks", "\"urgent\" case", "~29 ml", "<5 mm", "  ", "ΔEF 10",
                  // A micro sign must not become a capital mu, which reads as mg or Mg (1.8.3 re-check).
                  "µg/kg/min", "μg/kg/min"] {
            XCTAssertEqual(FreeText.cap(s), s, "'\(s)' stays")
        }
    }

    func testItemsInAList() {
        XCTAssertEqual(FreeText.capItems("amlodipine, metoprolol, aspirin"), "Amlodipine, Metoprolol, Aspirin")
        XCTAssertEqual(FreeText.capItems("penicillin (rash, hives); latex"), "Penicillin (rash, hives); Latex", "a comma inside parentheses is no break")
        XCTAssertEqual(FreeText.capItems("metformin 1,000 mg, eGFR 45"), "Metformin 1,000 mg, eGFR 45")
        XCTAssertEqual(FreeText.capItems("cefazolin 2 g 08:10; dexamethasone 4 mg", separators: [";"]), "Cefazolin 2 g 08:10; Dexamethasone 4 mg")
        XCTAssertEqual(FreeText.capJoined("lap chole + hernia repair"), "Lap chole + Hernia repair")
        XCTAssertEqual(FreeText.picked("Atrial fibrillation", from: ["Atrial fibrillation"]), "Atrial fibrillation")
        XCTAssertEqual(FreeText.picked("paced, left axis", from: ["Atrial fibrillation"]), "Paced, left axis")
        XCTAssertEqual(FreeText.picked("sVT", from: ["Atrial fibrillation"]), "sVT")
    }

    // MARK: On the summary and the handoff

    private func lowercaseRecord() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 60; r.sex = .male
        r.setProcedures([PlannedProcedure(name: "bowel resection thing")])
        r.problems = ["seizure"]
        r.systemNotes = ["neuro": "on levetiracetam", "cv": "followed by cardiology"]
        r.otherHistory = "hereditary angioedema"
        r.allergies = "adhesive tape (rash, itching); latex"
        r.medications = "amlodipine, metoprolol, aspirin"
        r.anesthesiaNotes = "prolonged emergence after the last case"
        r.labNotes = "tsh normal"
        r.surgeries = [PatientSurgery(procedures: [PlannedProcedure(name: "cyst removal")], date: PatientMonthYear(year: 2015))]
        r.ecg = ["Atrial fibrillation", "left axis"]
        r.ecgNotes = "rate controlled"
        var echo = PatientEcho(); echo.lv = .mild; echo.lvef = 50; echo.other = "small pericardial effusion"
        r.echoFindings = echo
        r.lhc.stenosis = ["lad": 90]; r.lhc.notes = "stent to the proximal LAD"
        r.currentAirway = "natural"
        r.airwayNotes = "grade 2 view last time"
        r.dentition = "loose upper incisor"
        r.mask = "easy"; r.intubation = "easy"; r.tube = "7.0 ETT"
        r.infusions = [PatientInfusion(drug: "phenylephrine", rate: "0.3 mcg/kg/min")]
        r.medsGiven = "cefazolin 2 g 08:10; dexamethasone 4 mg"
        r.factors = "fibrinogen concentrate 2 g"
        r.events = "hypotension after induction"
        r.echo = "new wall motion change"
        r.intraopLabs = [IntraopLabSet(time: nil, values: ["hb": 9], viscoelastic: "extem normal", other: "mg 1.6")]
        r.infections.other = [PatientInfectiousOther(name: "scabies", result: .positive)]
        r.painPlan = "tap blocks and acetaminophen"
        r.callIf = "sbp under 90"
        r.todos = "check glucose on arrival"
        r.codeStatus = .full
        return r
    }

    private func line(_ lines: [PatientSummary.Line], _ label: String) -> String {
        lines.first { $0.label == label }?.text ?? "(no \(label) line)"
    }

    func testSummaryLinesStartTheirTypedEntriesWithACapital() {
        let r = lowercaseRecord()
        let history = PatientSummary.historyLines(r)
        XCTAssertEqual(line(history, "Neurologic"), "seizure disorder; On levetiracetam", "the catalog's words stay as they are")
        XCTAssertEqual(line(history, "Cardiovascular"), "Followed by cardiology")
        XCTAssertEqual(line(history, "Other conditions"), "Hereditary angioedema")
        XCTAssertEqual(line(history, "Allergies"), "Adhesive tape (rash, itching); Latex")
        XCTAssertEqual(line(history, "Medications"), "Amlodipine, Metoprolol, Aspirin")
        XCTAssertTrue(line(history, "Anesthetic complications").hasPrefix("Prolonged emergence"), line(history, "Anesthetic complications"))
        XCTAssertTrue(line(history, "Labs").contains("Tsh normal"), line(history, "Labs"))
        XCTAssertTrue(line(history, "Labs").contains("Scabies pos"), line(history, "Labs"))
        XCTAssertEqual(line(history, "Past surgical history"), "Cyst removal (2015)")
        let assess = PatientSummary.assessmentLines(r)
        XCTAssertEqual(line(assess, "ECG"), "Atrial fibrillation; Left axis; Rate controlled")
        XCTAssertTrue(line(assess, "Echo").contains("Small pericardial effusion"), line(assess, "Echo"))
        XCTAssertTrue(line(assess, "Coronaries").contains("Stent to the proximal LAD"), line(assess, "Coronaries"))
        let intraop = PatientSummary.intraopLines(r)
        XCTAssertEqual(line(intraop, "Infusions"), "Phenylephrine at 0.3 mcg/kg/min")
        XCTAssertEqual(line(intraop, "Medications & interventions"), "Cefazolin 2 g 08:10; Dexamethasone 4 mg")
        XCTAssertEqual(line(intraop, "Factor concentrates & other products"), "Fibrinogen concentrate 2 g")
        XCTAssertEqual(line(intraop, "Events"), "Hypotension after induction")
        XCTAssertEqual(line(intraop, "Echo"), "New wall motion change")
        XCTAssertTrue(line(intraop, "Airway").contains("7.0 ETT"), line(intraop, "Airway"))
        let plan = PatientSummary.planLines(r)
        XCTAssertEqual(line(plan, "Pain plan"), "Tap blocks and acetaminophen")
        XCTAssertEqual(line(plan, "Call if"), "Sbp under 90")
        XCTAssertEqual(line(plan, "To do & concerns"), "Check glucose on arrival")
        XCTAssertEqual(line(PatientSummary.airwayLines(r), "Airway notes"), "Grade 2 view last time")
        XCTAssertEqual(line(PatientSummary.airwayLines(r), "Teeth"), "Loose upper incisor")
        XCTAssertTrue(PatientSummary.procedureLines(r).first?.text.hasPrefix("Bowel resection thing") ?? false)
    }

    func testHandoffAndShortHandoffCapitalizeToo() {
        let r = lowercaseRecord()
        let full = HandoffWriter.text(r)
        for s in ["Medications: Amlodipine, Metoprolol, Aspirin", "Allergies: Adhesive tape (rash, itching); Latex", "Events: Hypotension after induction",
                  "Call if: Sbp under 90", "On levetiracetam", "Past surgical history: Cyst removal (2015)"] {
            XCTAssertTrue(full.contains(s), "\(s)\n\(full)")
        }
        let short = HandoffWriter.shortText(r)
        XCTAssertTrue(short.contains("Allergies: Adhesive tape (rash, itching); Latex"), short)
        XCTAssertTrue(short.contains("Events: Hypotension after induction"), short)
        XCTAssertTrue(short.contains("Plan: Call if sbp under 90."), "mid-sentence the first word is lower case again\n\(short)")
        XCTAssertTrue(short.contains("Drips: Phenylephrine at 0.3 mcg/kg/min"), short)
        // A positive typed infectious result is still marked in bold red, with the capital.
        XCTAssertTrue(HandoffWriter.marks(r).contains("Scabies pos"), "\(HandoffWriter.marks(r))")
    }

    func testTheSavedRecordKeepsWhatWasTyped() {
        let r = lowercaseRecord()
        _ = HandoffWriter.text(r)
        XCTAssertEqual(r.medications, "amlodipine, metoprolol, aspirin")
        XCTAssertEqual(r.events, "hypotension after induction")
        XCTAssertEqual(r.capitalized.capitalized, r.capitalized, "idempotent")
    }

    func testAnOlderLowercaseSaveDisplaysCapitalized() throws {
        let data = try JSONEncoder().encode(lowercaseRecord())
        let opened = try JSONDecoder().decode(PatientRecord.self, from: data)
        XCTAssertEqual(opened.medications, "amlodipine, metoprolol, aspirin", "the save is as it was")
        XCTAssertEqual(line(PatientSummary.historyLines(opened), "Medications"), "Amlodipine, Metoprolol, Aspirin")
        XCTAssertTrue(HandoffWriter.text(opened).contains("Medications: Amlodipine, Metoprolol, Aspirin"))
    }

    func testCatalogItemsAndAlreadyStyledTextAreNotTouched() {
        let demo = PatientDemo.record
        let before = PatientSummary.historyLines(demo).map(\.text)
        XCTAssertEqual(before, PatientSummary.historyLines(demo.capitalized).map(\.text))
        let neuro = PatientSummary.historyLines(PatientDemo.neuro)
        XCTAssertTrue(line(neuro, "Neurologic").contains("; On levetiracetam"), line(neuro, "Neurologic"))
        XCTAssertTrue(line(neuro, "Neurologic").hasPrefix("stroke or TIA within 3 months"), "catalog items keep their lower case: \(line(neuro, "Neurologic"))")
    }

    // MARK: Where it is typed

    func testTypedEntriesAreCapitalizedWhenCommitted() {
        // The typeahead (ECG findings): a pick keeps its words, a typed finding gets a capital.
        XCTAssertEqual(FreeText.picked("Paced rhythm (AV)", from: PatientECG.findings), "Paced rhythm (AV)")
        XCTAssertEqual(PatientECG.adding(FreeText.picked("left axis, borderline", from: PatientECG.findings), to: ["Normal sinus rhythm"]), ["Normal sinus rhythm", "Left axis, borderline"])
        // A typed procedure.
        XCTAssertEqual(PlannedProcedure(name: FreeText.cap("bowel thing")).name, "Bowel thing")
    }
}
