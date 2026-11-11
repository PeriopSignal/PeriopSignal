import XCTest
import UIKit
@testable import PeriopSignal

/// 1.9 briefs (Ben, Nov 3): the generated, editable preprocedure summary and the single handoff, as blocks; the fishbone's
/// values and its copied line; edits that stick and Regenerate; Status & Plan's chips; PT and aPTT in the labs.
final class Briefs19Tests: XCTestCase {
    private func block(_ blocks: [SummaryBlock], _ key: String, file: StaticString = #filePath, line: UInt = #line) throws -> SummaryBlock {
        try XCTUnwrap(blocks.first { $0.key == key }, "no \(key) block in \(blocks.map(\.key))", file: file, line: line)
    }

    private func has(_ blocks: [SummaryBlock], _ key: String) -> Bool { blocks.contains { $0.key == key } }

    private var cholecystectomy: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 76; r.sex = .male; r.weightKg = 80; r.heightCm = 180
        r.procedure = "laparoscopic cholecystectomy"
        return r
    }

    // MARK: 1. Header

    func testHeaderFormats() {
        let r = cholecystectomy
        XCTAssertEqual(PatientBriefs.header(r, verb: "for"), "76 yo M (80 kg, 180 cm) for Laparoscopic cholecystectomy")
        XCTAssertEqual(PatientBriefs.header(r, verb: "had"), "76 yo M (80 kg, 180 cm) had Laparoscopic cholecystectomy")
        XCTAssertEqual(PatientBriefs.preop(r).first?.text, "76 yo M (80 kg, 180 cm) for Laparoscopic cholecystectomy")
        XCTAssertEqual(PatientBriefs.handoff(r).first?.text, "76 yo M (80 kg, 180 cm) had Laparoscopic cholecystectomy")
    }

    func testHeaderAgeForInfantsAndTheOldest() {
        var r = cholecystectomy
        r.ageYears = 4.0 / 12.0; r.sex = .female; r.weightKg = 6.2; r.heightCm = 62
        XCTAssertEqual(PatientBriefs.header(r, verb: "for"), "4 mo F (6.2 kg, 62 cm) for Laparoscopic cholecystectomy", "months for an infant")
        r.ageYears = 93
        XCTAssertTrue(PatientBriefs.header(r, verb: "for")?.hasPrefix("90+ yo F (6.2 kg") ?? false, "90 or older is 90+ (HIPAA)")
        XCTAssertEqual(PatientBriefs.ageText(1), "1 yo")
        XCTAssertEqual(PatientBriefs.ageText(17.9), "17 yo")
        XCTAssertEqual(PatientBriefs.ageText(0.01), "<1 mo")
        XCTAssertEqual(PatientBriefs.ageText(90), "90+ yo")
    }

    func testHeaderDropsMissingPartsGracefully() {
        var r = PatientRecord()
        XCTAssertNil(PatientBriefs.header(r, verb: "for"))
        r.ageYears = 76
        XCTAssertEqual(PatientBriefs.header(r, verb: "for"), "76 yo")
        r.sex = .male
        XCTAssertEqual(PatientBriefs.header(r, verb: "for"), "76 yo M")
        r.weightKg = 80
        XCTAssertEqual(PatientBriefs.header(r, verb: "for"), "76 yo M (80 kg)")
        r.weightKg = nil; r.heightCm = 180
        XCTAssertEqual(PatientBriefs.header(r, verb: "for"), "76 yo M (180 cm)")
        r.procedure = "laparoscopic cholecystectomy"
        XCTAssertEqual(PatientBriefs.header(r, verb: "had"), "76 yo M (180 cm) had Laparoscopic cholecystectomy")
        var onlyProcedure = PatientRecord()
        onlyProcedure.procedure = "laparoscopic cholecystectomy"
        XCTAssertEqual(PatientBriefs.header(onlyProcedure, verb: "for"), "For Laparoscopic cholecystectomy")
        var noAge = PatientRecord()
        noAge.sex = .female; noAge.weightKg = 70
        XCTAssertEqual(PatientBriefs.header(noAge, verb: "for"), "F (70 kg)")
    }

    // MARK: 2. Each block's present / absent rule

    func testAnEmptyRecordHasNoBlocks() {
        XCTAssertTrue(PatientBriefs.preop(PatientRecord()).isEmpty)
        XCTAssertTrue(PatientBriefs.handoff(PatientRecord()).isEmpty)
    }

    func testTheFullDemoHasEveryBlockInBensOrder() {
        let r = PatientDemo.briefs
        XCTAssertEqual(PatientBriefs.handoff(r).map(\.key),
                       ["header", "case", "allergies", "pmh", "psh", "airway", "workup", "tee", "labs", "meds", "infusions", "io", "lines", "regional",
                        "events", "risk", "concerns"])
        XCTAssertEqual(PatientBriefs.preop(r).map(\.key),
                       ["header", "allergies", "pmh", "psh", "airway", "workup", "labs", "meds", "intake", "lines", "risk"])
        let labels = PatientBriefs.handoff(r).map { $0.label ?? "" }
        XCTAssertEqual(labels[2], "Allergies")
        XCTAssertTrue(labels[3].hasPrefix("PMH"))
        XCTAssertEqual(Array(labels[4...6]), ["PSH", "Airway course", "Preprocedure cardiac workup"])
        XCTAssertEqual(Array(labels[7...9]), ["Intraoperative TEE", "Labs", "Home medications"])
        XCTAssertEqual(Array(labels[10...13]), ["Current infusions & intraop medications", "Intake & output", "Lines & devices", "Regional performed"])
        XCTAssertEqual(Array(labels[14...]), ["Intraoperative events", "Risk scores", "Concerns/Considerations"])
    }

    func testEachBlockAppearsOnlyWithContent() throws {
        var r = PatientRecord()
        r.ageYears = 60
        XCTAssertEqual(PatientBriefs.handoff(r).map(\.key), ["header"])
        r.nkda = true
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "allergies").text, "No known drug allergies")
        r.surgeries = [PatientSurgery(name: "Appendectomy", date: PatientMonthYear(year: 1998))]
        XCTAssertTrue(try block(PatientBriefs.preop(r), "psh").text.contains("1998"))
        // The cardiac workup, the intraoperative TEE, the regional, the events: nothing entered, no block.
        XCTAssertFalse(has(PatientBriefs.handoff(r), "workup"))
        XCTAssertFalse(has(PatientBriefs.handoff(r), "tee"))
        XCTAssertFalse(has(PatientBriefs.handoff(r), "regional"))
        XCTAssertFalse(has(PatientBriefs.handoff(r), "events"))
        r.ecg = ["Atrial fibrillation"]
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "workup").text, "ECG: Atrial fibrillation")
        XCTAssertEqual(try block(PatientBriefs.preop(r), "workup").text, "ECG: Atrial fibrillation")
        var echo = PatientEcho()
        echo.study = "TEE"; echo.lv = .mild; echo.lvef = 45
        r.intraopEcho = echo
        XCTAssertTrue(try block(PatientBriefs.handoff(r), "tee").text.contains("45"))
        XCTAssertFalse(try block(PatientBriefs.handoff(r), "tee").text.hasPrefix("TEE: "), "the label says it")
        XCTAssertFalse(has(PatientBriefs.preop(r), "tee"), "the preprocedure summary has no intraoperative TEE")
        r.regional = [PatientRegional(technique: "TAP block", side: "Bilateral", drug: "ropivacaine 0.25% 20 mL each side")]
        XCTAssertTrue(try block(PatientBriefs.handoff(r), "regional").text.contains("TAP block"))
        r.noEvents = true
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "events").text, "No notable events")
        r.noEvents = false; r.events = "hypotension after induction"
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "events").text, "Hypotension after induction")
        XCTAssertTrue(try block(PatientBriefs.handoff(r), "events").alert)
    }

    func testPMHCarriesTheASAClassAndTheSystemWords() throws {
        var r = PatientRecord()
        r.problems = ["htn", "copd"]
        XCTAssertEqual(try block(PatientBriefs.preop(r), "pmh").label, "PMH")
        r.asaClass = 3
        XCTAssertEqual(try block(PatientBriefs.preop(r), "pmh").label, "PMH (ASA III)")
        r.noHistory = true; r.problems = []
        XCTAssertEqual(try block(PatientBriefs.preop(r), "pmh").text, "No significant medical history")
        // Every system's words are in the paragraph.
        let demo = PatientDemo.briefs
        let pmh = try block(PatientBriefs.preop(demo), "pmh").text
        let own: Set<String> = ["Allergies", "Past surgical history", "Medications", "Medication alerts", "Current infusions", "Last intake", "Labs", "Liver"]
        for l in PatientSummary.historyLines(demo) where !own.contains(l.label ?? "") {
            XCTAssertTrue(pmh.contains(l.text), "PMH leaves out \(l.label ?? ""): \(l.text)")
        }
        XCTAssertFalse(pmh.contains("\n"), "one paragraph")
    }

    func testAirwayExamIsOneLineAndAirwayCourseEndsWithHowThePatientLeaves() throws {
        let demo = PatientDemo.record
        let exam = try block(PatientBriefs.preop(demo), "airway")
        XCTAssertEqual(exam.label, "Airway exam")
        XCTAssertTrue(exam.text.contains("Mallampati III"), exam.text)
        XCTAssertFalse(exam.text.contains("\n"))
        var r = PatientRecord()
        r.mask = "easy"; r.intubation = "easy"; r.airwayDevice = "Video laryngoscope"; r.laryngoscopyGrade = "1"; r.attempts = 1
        r.tube = "7.5 ETT, 23 cm at the lip"
        r.airwayAtEnd = "extubated"
        let course = try block(PatientBriefs.handoff(r), "airway")
        XCTAssertEqual(course.label, "Airway course")
        // 1.12 (Ben, Nov 10): the short form (B112Tests has the rules): no grade 1 and no single attempt on an easy airway.
        XCTAssertEqual(course.text, "Easy Mask, Easy VL Intubation, ETT 7.5 at 23 cm (lip). Extubated")
        r.airwayAtEnd = "intubated"; r.ventilation = "AC/VC 450 × 16, PEEP 8"
        XCTAssertTrue(try block(PatientBriefs.handoff(r), "airway").text.hasSuffix("Remains intubated, AC/VC 450 × 16, PEEP 8"))
        XCTAssertFalse(try block(PatientBriefs.handoff(r), "airway").text.contains("\n"), "one line")
        XCTAssertNotEqual(PatientBriefs.preop(r).first { $0.key == "airway" }?.label, "Airway course", "the preprocedure summary has the exam")
    }

    func testMedicationsAndInfusions() throws {
        let demo = PatientDemo.cardiac
        let pre = try block(PatientBriefs.preop(demo), "meds")
        XCTAssertTrue(pre.text.contains("Infusions: "), "the infusions running before the case: \(pre.text)")
        XCTAssertTrue(pre.alert)
        let hand = PatientBriefs.handoff(demo)
        let infusions = try block(hand, "infusions")
        XCTAssertTrue(infusions.text.contains("Epinephrine"), "arriving on infusions: \(infusions.text)")
        XCTAssertTrue(infusions.text.contains("PCC 1500 units"), "factors join the intraop medications")
        var r = PatientRecord()
        r.infusions = [PatientInfusion(drug: "Phenylephrine", rate: "0.3 mcg/kg/min")]
        r.medsGiven = "Cefazolin 2 g 08:10; Dexamethasone 4 mg"
        r.factors = "PCC 1500 units"
        let t = try block(PatientBriefs.handoff(r), "infusions").text
        XCTAssertEqual(t.components(separatedBy: "\n").count, 2)
        XCTAssertTrue(t.hasPrefix("Infusions: Phenylephrine"))
        XCTAssertTrue(t.hasSuffix("Intraop medications: Cefazolin 2 g 08:10; Dexamethasone 4 mg; PCC 1500 units"), t)
    }

    func testIntakeAndOutputInBensOrder() throws {
        var r = PatientRecord()
        r.fluids = ["crystalloid": 1800, "colloid": 250, "prbc": 2, "plasma": 1, "ebl": 250, "uop": 320, "cellSaver": 450]
        let t = try block(PatientBriefs.handoff(r), "io").text
        XCTAssertEqual(t, "Crystalloid 1800 mL · Colloid 250 mL · PRBC 2 units · FFP 1 unit · EBL 250 mL · Urine output 320 mL · Cell saver 450 mL")
    }

    func testRiskScoresAreBrieflyListedAndTheRCRIIsNotForCardiacSurgery() throws {
        var r = PatientRecord()
        r.scores["stopbang"] = PatientScore(points: 5, max: 8, label: "High risk")
        r.scores["rcri"] = PatientScore(points: 2, max: 6, label: "Class III")
        r.scores["ariscat"] = PatientScore(points: 34, max: nil, label: "Intermediate")
        XCTAssertEqual(try block(PatientBriefs.preop(r), "risk").text, "RCRI 2 (Class III) · STOP-BANG 5 (High risk) · ARISCAT 34 (Intermediate)")
        r.setProcedures(PlannedProcedure.parse("CABG x3"))
        XCTAssertTrue(PatientRules.cardiacSurgery(r))
        XCTAssertEqual(try block(PatientBriefs.preop(r), "risk").text, "STOP-BANG 5 (High risk) · ARISCAT 34 (Intermediate)")
    }

    // MARK: 3. Lines and devices: (Pre) and (Intra)

    func testLinesCarryPreAndIntraInTheHandoffOnly() throws {
        var r = PatientRecord()
        r.devices = ["18g R forearm"].compactMap { PatientDevices.parse($0)?.device(placedIntraop: false) }
            + ["20g L radial art line"].compactMap { PatientDevices.parse($0)?.device(placedIntraop: true) }
        XCTAssertEqual(r.devices.count, 2)
        let hand = try block(PatientBriefs.handoff(r), "lines")
        XCTAssertEqual(hand.lines.count, 2)
        XCTAssertTrue(hand.lines[0].hasSuffix("(Pre)"), hand.text)
        XCTAssertTrue(hand.lines[1].hasSuffix("(Intra)"), hand.text)
        XCTAssertEqual(hand.figure, .diagram(arrivalOnly: false))
        XCTAssertEqual(hand.joiner, "; ")
        let pre = try block(PatientBriefs.preop(r), "lines")
        XCTAssertEqual(pre.lines.count, 1, "only what is there on arrival")
        XCTAssertFalse(pre.text.contains("(Pre)") || pre.text.contains("(Intra)"))
        XCTAssertEqual(pre.figure, .diagram(arrivalOnly: true))
    }

    func testLimbAlertsAndTheHarvestArmStayInLinesAndDevices() throws {
        var r = PatientRecord()
        r.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "Prior axillary lymph node dissection")]
        let lines = try block(PatientBriefs.handoff(r), "lines")
        XCTAssertTrue(lines.text.hasPrefix("Limb alert: R arm"), lines.text)
        XCTAssertTrue(lines.alert)
        XCTAssertTrue(lines.marks.contains("R arm"))
        let cardiac = try block(PatientBriefs.handoff(PatientDemo.cardiac), "lines")
        XCTAssertTrue(cardiac.text.contains("Arms: "), "the planned radial harvest arm: \(cardiac.text)")
        let dialysis = PatientBriefs.handoff(PatientDemo.dialysis)
        XCTAssertTrue(try block(dialysis, "lines").text.contains("Limb alert: "), "a fistula's arm")
    }

    // MARK: 4. Labs: the latest intraoperative values, with a time
    //
    // 1.12 (Ben's note 8): the labs block is two columns, Preop and Intraop, not a fishbone with starred values. The
    // 1.9 tests of the starred values, the fishbone's plain line and the side list were rewritten for it here; the new
    // rules have their own tests in A112Tests.

    func testIntraopLabsAreTheirOwnColumnWithTheLatestSetOfEachValue() throws {
        var r = PatientRecord()
        r.labs = ["k": 5.6, "hb": 10.8, "na": 138, "cr": 6.2, "inr": 1.0]
        r.intraopLabs = [IntraopLabSet(time: PatientDemo.today(9, 15), values: ["k": 4.0, "inr": 1.9]),
                         IntraopLabSet(time: PatientDemo.today(10, 40), values: ["k": 4.9, "hco3a": 21, "lactate": 1.4])]
        guard case .fishbone(let labs)? = try block(PatientBriefs.handoff(r), "labs").figure else { return XCTFail("no labs figure") }
        // The preop values stay in the Preop column, whatever the case found (no value is replaced and starred any more).
        XCTAssertTrue(labs.preop.flatMap(\.items).contains { $0.text == "K 5.6" })
        XCTAssertTrue(labs.preop.flatMap(\.items).contains { $0.text == "INR 1.0" })
        // The Intraop column: the newest gas with its lactate, then the newest coags.
        XCTAssertEqual(labs.gas?.slash.compactMap { $0 }.map(\.key), ["hco3a"])
        XCTAssertEqual(labs.gas?.lactate?.text, "1.4")
        XCTAssertEqual(labs.intraop.last?.items.map(\.text), ["INR 1.9"], "an older set's value when the newest has none")
        XCTAssertEqual(labs.caption, "Intraop 09:15", "the gas's own time is on its figure")
        XCTAssertFalse(try block(PatientBriefs.handoff(r), "labs").text.contains("*"))
        // The preprocedure summary is the preoperative labs alone.
        guard case .fishbone(let pre)? = try block(PatientBriefs.preop(r), "labs").figure else { return XCTFail("no labs figure") }
        XCTAssertFalse(pre.hasIntraop)
        XCTAssertNil(pre.caption)
        // An intraoperative set only: the Intraop column alone.
        var only = PatientRecord()
        only.intraopLabs = [IntraopLabSet(time: PatientDemo.today(10, 40), values: ["k": 4.9])]
        XCTAssertNil(PatientBriefs.handoff(only).first { $0.key == "labs" }, "a potassium alone is neither the gas nor the coags: it is a chip")
    }

    func testLabsPlainText() throws {
        var r = PatientRecord()
        r.labs = ["na": 138, "k": 4.1, "cl": 102, "hco3": 24, "bun": 18, "cr": 1.1, "glucose": 110, "wbc": 7.2, "hb": 13.1, "hct": 39, "plt": 210,
                  "pt": 12.1, "inr": 1.0, "ptt": 30]
        // Only what is in Ben's lists: CMP (Na, K, BUN, Cr, glucose) and Heme (Hb, Plt, PTT, INR); Cl, HCO₃, WBC, Hct and PT are chips.
        let expected = "Labs: Preop: CMP: Na 138, K 4.1, BUN 18, Cr 1.10, Glu 110; Heme: Hb 13.1, Plt 210, PTT 30, INR 1.0"
        XCTAssertEqual(PatientBriefs.plainText(PatientBriefs.handoff(r)), expected)
        XCTAssertEqual(PatientBriefs.plainText(PatientBriefs.preop(r)), expected)
        // Only what was entered; abnormal values carry their H or L; no estimated Hct.
        var partial = PatientRecord()
        partial.labs = ["k": 5.9, "hb": 12, "inr": 1.6]
        XCTAssertEqual(PatientBriefs.plainText(PatientBriefs.preop(partial)), "Labs: Preop: CMP: K 5.9 H; Heme: Hb 12, INR 1.6 H")
        // The case's values are their own paragraph, with plain digits and the times on a line of their own.
        var withCase = PatientRecord()
        withCase.labs = ["k": 4.5, "na": 138]
        withCase.intraopLabs = [IntraopLabSet(time: PatientDemo.today(10, 40), values: ["ph": 7.4, "hco3a": 24])]
        XCTAssertEqual(PatientBriefs.plainText(PatientBriefs.handoff(withCase)), "Labs:\n  Preop: CMP: Na 138, K 4.5\n  Intraop: ABG (10:40): pH 7.4 / HCO3 24")
    }

    func testOtherLabsAreListedUnderOther() throws {
        var r = PatientRecord()
        r.labs = ["k": 4.1, "albumin": 3.9, "lactate": 1.4]
        r.typeScreen = PatientTypeScreen(type: "A+", screen: .negative, crossmatched: 2)
        let t = try block(PatientBriefs.preop(r), "labs")
        XCTAssertTrue(t.text.contains("Other: Lactate 1.4"), t.text)
        XCTAssertFalse(t.text.contains("Alb 3.9"), "the albumin is a chip under + Add other input data into Handoff")
        XCTAssertTrue(t.text.contains("Heme: T&S A+, screen neg, 2 u crossmatched"), t.text)
        XCTAssertEqual(PatientBriefs.plainText([t]).components(separatedBy: "\n").count, 1, "one line in the copied text")
        XCTAssertTrue(PatientBriefs.plainText([t]).hasPrefix("Labs: Preop: CMP: K 4.1; Heme: T&S"), PatientBriefs.plainText([t]))
    }

    func testPTAndPTTAreLabFields() {
        XCTAssertEqual(PatientLabs.test("pt")?.unit, "s")
        XCTAssertNil(PatientLabs.test("pt")?.range, "no reference range for the PT: it depends on the laboratory's reagent")
        XCTAssertEqual(PatientLabs.flag("pt", 40, sex: nil), .normal)
        XCTAssertEqual(PatientLabs.flag("ptt", 40, sex: nil), .high, "the aPTT keeps the ABIM range the intraoperative set uses")
        XCTAssertEqual(PatientLabs.test("ptt")?.range, IntraopLabs.ptt.range)
        XCTAssertTrue(PatientLabs.tests(.main).map(\.key).contains("pt"))
        XCTAssertTrue(PatientLabs.tests(.main).map(\.key).contains("ptt"))
        let s = PatientLabs.summary(["pt": 12.1, "ptt": 52, "inr": 1.0], sex: nil)
        XCTAssertEqual(s.fishbone.pt?.text, "12.1")
        XCTAssertEqual(s.fishbone.ptt?.flag, .high)
        XCTAssertTrue(s.fishbone.hasCoags)
        XCTAssertEqual(s.line, "PT 12.1 · INR 1.0 · PTT 52")
    }

    // MARK: 5. Safety content the old handoff carried

    func testCodeStatusWhenNotFullIsAtTheTop() throws {
        var r = cholecystectomy
        r.codeStatus = .full
        XCTAssertFalse(has(PatientBriefs.handoff(r), "code"))
        r.codeStatus = .dnrDni
        r.codeStatusPlan = .modified
        r.codeStatusPlanNote = "accepts intubation and vasopressors"
        let blocks = PatientBriefs.handoff(r)
        XCTAssertEqual(blocks.map(\.key).prefix(2), ["header", "code"], "after the header")
        let code = try block(blocks, "code")
        XCTAssertTrue(code.text.contains("DNR/DNI"), code.text)
        XCTAssertTrue(code.text.contains("accepts intubation"), code.text)
        XCTAssertTrue(code.alert)
        XCTAssertTrue(has(PatientBriefs.preop(r), "code"))
    }

    func testPositiveInfectiousResultsAndIsolationAreKept() throws {
        var r = PatientRecord()
        r.infections = PatientInfections(results: ["mrsa": .positive, "covid": .negative, "cdiff": .pending])
        r.problems = ["mdro", "isolation"]
        let labs = try block(PatientBriefs.handoff(r), "labs")
        XCTAssertTrue(labs.text.contains("MRSA pos"), labs.text)
        XCTAssertTrue(labs.text.contains("C. diff pending"), labs.text)
        XCTAssertFalse(labs.text.contains("COVID neg"), "the handoff lists the positive and the pending")
        XCTAssertTrue(labs.marks.contains("MRSA pos"))
        // 1.12 (Ben's note 8): the Preop column lists the MRSA screen and what needs telling; a negative COVID test is a chip
        // under + Add other input data into Handoff, in the preprocedure summary as in the handoff.
        XCTAssertFalse(try block(PatientBriefs.preop(r), "labs").text.contains("COVID neg"))
        XCTAssertTrue(HandoffExtras.preopCandidates(r).map(\.key).contains("preop:covid"))
        XCTAssertTrue(try block(PatientBriefs.preop(r), "labs").text.contains("MRSA pos"))
        let pmh = try block(PatientBriefs.handoff(r), "pmh")
        XCTAssertTrue(pmh.text.localizedCaseInsensitiveContains("isolation"), pmh.text)
    }

    func testWarningsAreInThePMH() throws {
        var r = PatientRecord()
        r.problems = ["hiatal-hernia", "gi-bleed"]
        let pmh = try block(PatientBriefs.handoff(r), "pmh")
        XCTAssertTrue(pmh.text.contains(PatientWarnings.aspirationLabel), pmh.text)
        XCTAssertTrue(pmh.text.contains(PatientWarnings.heparinLabel), pmh.text)
        XCTAssertTrue(pmh.marks.contains { $0.hasPrefix(PatientWarnings.aspirationLabel) })
    }

    func testTEEContraindicationsAreInTheWorkupOfBothBriefs() throws {
        let r = PatientDemo.links
        XCTAssertNotNil(PatientTEE.line(r))
        for blocks in [PatientBriefs.preop(r), PatientBriefs.handoff(r)] {
            let w = try block(blocks, "workup")
            XCTAssertTrue(w.text.contains("TEE screen: "), w.text)
            XCTAssertTrue(w.alert)
        }
    }

    func testCarotidCautionsAndMechanicalSupportInThePreprocedureWorkup() throws {
        let r = PatientDemo.cardiac
        let pre = try block(PatientBriefs.preop(r), "workup")
        XCTAssertTrue(pre.text.contains("Carotid ultrasound: "), pre.text)
        XCTAssertTrue(pre.text.contains("Caution: "), pre.text)
        XCTAssertTrue(pre.text.contains("Mechanical support: "), pre.text)
        let hand = try block(PatientBriefs.handoff(r), "workup")
        XCTAssertFalse(hand.text.contains("Mechanical support: "), "in the handoff the support is in the lines and devices")
        let support = try block(PatientBriefs.handoff(r), "lines").text
        XCTAssertTrue(support.contains("ECMO") || support.contains("IABP"), support)
    }

    func testDifficultAirwayIsInTheAirwayCourse() throws {
        var r = PatientRecord()
        r.intubation = "difficult"; r.laryngoscopyGrade = "3"; r.airwayAtEnd = "extubated"
        // 1.10 (Ben, Nov 7): the difficult-airway follow-up is gone from the airway and the handoff; a saved one is ignored.
        r.airwayFollowUp = ["told"]
        let course = try block(PatientBriefs.handoff(r), "airway")
        XCTAssertTrue(course.alert)
        // 1.12: "Difficult Intubation, grade 3" (the grade stays on a difficult airway), in red.
        XCTAssertTrue(course.text.contains("Difficult Intubation, grade 3"), course.text)
        XCTAssertFalse(course.text.contains("follow-up"), course.text)
        XCTAssertTrue(course.text.hasSuffix("Extubated"), "it still ends with how the patient leaves: \(course.text)")
        XCTAssertFalse(course.text.contains("\n"))
    }

    func testConcernsHoldTheDispositionConsiderationsAndWhatIsToBeDone() throws {
        var r = PatientRecord()
        r.disposition = "ICU"
        r.considerations = ["difficult-airway", "pressors"]
        r.considerationsNote = "Norepinephrine rising"
        r.todos = "Check potassium on arrival"
        r.painPlan = "TAP blocks; acetaminophen"
        r.callIf = "SBP under 90"
        let c = try block(PatientBriefs.handoff(r), "concerns")
        XCTAssertEqual(c.label, "Concerns/Considerations")
        XCTAssertEqual(c.lines, ["Disposition: ICU", "Considerations: Difficult airway; Hemodynamic instability on pressors; Norepinephrine rising",
                                 "To do & concerns: Check potassium on arrival", "Pain plan: TAP blocks; acetaminophen", "Call if: SBP under 90"])
        XCTAssertTrue(c.alert)
        r.todos = ""; r.painPlan = ""; r.callIf = ""; r.considerations = []; r.considerationsNote = ""
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "concerns").lines, ["Disposition: ICU"])
        r.disposition = nil
        XCTAssertFalse(has(PatientBriefs.handoff(r), "concerns"))
    }

    func testHomeMedicationAlertsAreKept() throws {
        let r = PatientDemo.meds
        let meds = try block(PatientBriefs.handoff(r), "meds")
        XCTAssertEqual(meds.label, "Home medications")
        XCTAssertTrue(meds.text.contains("Alerts: "), meds.text)
        XCTAssertTrue(meds.alert)
    }

    func testCaseBlockCarriesUrgencyAndTheAnesthetic() throws {
        var r = cholecystectomy
        r.anesthetic = ["ga"]
        r.urgency = .elective
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "case").text, "General")
        r.urgency = .emergency
        XCTAssertTrue(try block(PatientBriefs.handoff(r), "case").text.hasPrefix("Emergency"))
        XCTAssertFalse(has(PatientBriefs.preop(r), "case"))
    }

    // MARK: 6. Edits stick; Regenerate clears

    func testAnEditIsShownMarkedAndSticksAsTheRecordChanges() throws {
        var r = PatientDemo.briefs
        PatientBriefs.setEdit(&r, .handoff, key: "allergies", text: "Penicillin (rash); latex (anaphylaxis, throat swelling)")
        XCTAssertEqual(r.handoffEdits, ["allergies": "Penicillin (rash); latex (anaphylaxis, throat swelling)"])
        XCTAssertTrue(r.preopSummaryEdits.isEmpty, "the other brief is its own")
        var allergies = try block(PatientBriefs.handoff(r), "allergies")
        XCTAssertEqual(allergies.text, "Penicillin (rash); latex (anaphylaxis, throat swelling)")
        XCTAssertTrue(allergies.edited)
        XCTAssertFalse(try block(PatientBriefs.preop(r), "allergies").edited)
        // The record changes: the edit stays, even with nothing in the record for the block any more.
        r.allergyList = []
        allergies = try block(PatientBriefs.handoff(r), "allergies")
        XCTAssertEqual(allergies.text, "Penicillin (rash); latex (anaphylaxis, throat swelling)")
        XCTAssertTrue(allergies.edited)
        XCTAssertFalse(has(PatientBriefs.preop(r), "allergies"), "the preprocedure summary has no allergies now")
        // The blocks that were not edited follow the record.
        r.ageYears = 80
        XCTAssertTrue(try block(PatientBriefs.handoff(r), "header").text.hasPrefix("80 yo M"))
        XCTAssertFalse(try block(PatientBriefs.handoff(r), "header").edited)
    }

    func testEditingTheSameWordsAsTheRecordGeneratesIsNoEdit() throws {
        var r = PatientDemo.briefs
        let generated = try block(PatientBriefs.handoff(r), "events").text
        PatientBriefs.setEdit(&r, .handoff, key: "events", text: generated)
        XCTAssertTrue(r.handoffEdits.isEmpty)
        PatientBriefs.setEdit(&r, .handoff, key: "events", text: "Nothing happened")
        XCTAssertEqual(r.handoffEdits["events"], "Nothing happened")
        PatientBriefs.setEdit(&r, .handoff, key: "events", text: generated)
        XCTAssertTrue(r.handoffEdits.isEmpty, "back to the generated words: the edit is gone")
    }

    func testEmptyingABlockRemovesItUntilRegenerate() throws {
        var r = PatientDemo.briefs
        PatientBriefs.setEdit(&r, .preop, key: "psh", text: "")
        XCTAssertFalse(has(PatientBriefs.preop(r), "psh"))
        XCTAssertTrue(has(PatientBriefs.handoff(r), "psh"), "the handoff's own")
        PatientBriefs.regenerate(&r, .preop)
        XCTAssertTrue(has(PatientBriefs.preop(r), "psh"))
    }

    func testRegenerateClearsOnlyThatBriefsEdits() throws {
        var r = PatientDemo.briefsEdited
        XCTAssertFalse(r.preopSummaryEdits.isEmpty)
        XCTAssertFalse(r.handoffEdits.isEmpty)
        PatientBriefs.regenerate(&r, .handoff)
        XCTAssertTrue(r.handoffEdits.isEmpty)
        XCTAssertFalse(r.preopSummaryEdits.isEmpty)
        XCTAssertFalse(try block(PatientBriefs.handoff(r), "events").edited)
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "events").text, "Hypotension after induction, phenylephrine ×2; no arrhythmia")
        PatientBriefs.regenerate(&r, .preop)
        XCTAssertTrue(r.preopSummaryEdits.isEmpty)
    }

    @MainActor func testEditsAndRegenerateGoThroughTheStoreAndUndo() throws {
        let store = PatientStore(url: nil)
        store.update(discrete: true) { $0 = PatientDemo.briefs }
        store.update(discrete: true) { PatientBriefs.setEdit(&$0, .handoff, key: "events", text: "Stable") }
        XCTAssertEqual(store.record.handoffEdits["events"], "Stable")
        store.update(discrete: true) { PatientBriefs.regenerate(&$0, .handoff) }
        XCTAssertTrue(store.record.handoffEdits.isEmpty)
        XCTAssertTrue(store.canUndo)
        store.undo()
        XCTAssertEqual(store.record.handoffEdits["events"], "Stable", "Undo brings the edits back")
        store.update(discrete: true) { $0.preopSummaryOn = true }
        XCTAssertTrue(store.record.preopSummaryOn)
        XCTAssertEqual(store.record.handoffEdits["events"], "Stable", "other changes leave the edits")
    }

    // MARK: 7. Copied text

    func testPlainTextFormat() throws {
        let t = PatientBriefs.plainText(PatientBriefs.handoff(PatientDemo.briefs))
        let lines = t.components(separatedBy: "\n")
        XCTAssertTrue(lines.first?.hasPrefix("76 yo M (80 kg, 180 cm) had ") ?? false, lines.first ?? "")
        XCTAssertTrue(lines.first?.localizedCaseInsensitiveContains("cholecystectomy") ?? false, lines.first ?? "")
        XCTAssertTrue(lines.contains { $0.hasPrefix("Allergies: ") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("PMH (ASA IV): ") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("PSH: ") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("Airway course: ") && $0.hasSuffix("Extubated") })
        // 1.12 (Ben's note 8): two labelled paragraphs under the label, not a fishbone line.
        XCTAssertTrue(lines.contains("Labs:"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("  Preop: CMP: ") && $0.contains("; Heme: ") && $0.contains("PTT 30, INR 1.0") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("  Intraop: ") })
        XCTAssertTrue(lines.contains("Current infusions & intraop medications:"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("  Infusions: ") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("  Intraop medications: ") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("Lines & devices: ") && $0.contains("(Pre)") && $0.contains("(Intra)") && $0.contains("; ") })
        XCTAssertTrue(lines.contains("Concerns/Considerations:"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("  Disposition: PACU") })
        XCTAssertFalse(t.contains("HCO₃"), "plain digits for the subscripts")
        // No blank blocks, no stray punctuation.
        XCTAssertFalse(lines.contains(""))
        XCTAssertFalse(t.contains(": \n"))
    }

    func testRichTextIsTheSameWordsWithBoldLabels() throws {
        let blocks = PatientBriefs.handoff(PatientDemo.briefs)
        let plain = PatientBriefs.plainText(blocks)
        let rich = HandoffShare.richText(blocks)
        XCTAssertEqual(rich.string, plain)
        func traits(_ needle: String) throws -> (bold: Bool, underlined: Bool) {
            let r = try XCTUnwrap(plain.range(of: needle))
            let a = rich.attributes(at: NSRange(r, in: plain).location, effectiveRange: nil)
            let font = try XCTUnwrap(a[.font] as? UIFont)
            return (font.fontDescriptor.symbolicTraits.contains(.traitBold), (a[.underlineStyle] as? Int ?? 0) != 0)
        }
        let header = try traits("76 yo")
        XCTAssertTrue(header.bold && header.underlined)
        let label = try traits("Allergies:")
        XCTAssertTrue(label.bold && !label.underlined)
        let words = try traits("Penicillin")
        XCTAssertTrue(!words.bold && !words.underlined)
        let sub = try traits("Infusions:")
        XCTAssertTrue(sub.bold, "the label of a line under a block is bold too")
        let item = HandoffShare.pasteboardItem(plain, rich: rich)
        XCTAssertEqual(item["public.utf8-plain-text"] as? String, plain)
        XCTAssertNotNil(item["public.rtf"])
    }

    @MainActor func testShareItemsAreTheTextThenThePictures() throws {
        let blocks = PatientBriefs.handoff(PatientDemo.briefs)
        let items = HandoffShare.briefItems(blocks, record: PatientDemo.briefs, figure: nil)
        XCTAssertTrue(items.first is HandoffShare.TextItem, "the text first")
        XCTAssertGreaterThanOrEqual(items.count, 2, "the fishbone picture follows")
        XCTAssertTrue(items.dropFirst().allSatisfy { $0 is UIImage })
        guard case .fishbone(let labs)? = try block(blocks, "labs").figure else { return XCTFail("no fishbone") }
        let image = try XCTUnwrap(HandoffShare.fishboneImage(labs))
        XCTAssertGreaterThan(image.size.width, 100)
        XCTAssertNil(HandoffShare.fishboneImage(BriefLabs()), "no values, no picture")
        let several = HandoffShare.items(text: "t", images: [image, image])
        XCTAssertEqual(several.count, 3)
        XCTAssertTrue(several[0] is HandoffShare.TextItem)
        XCTAssertTrue(several[1] is UIImage && several[2] is UIImage)
        XCTAssertEqual(HandoffShare.items(text: "t", images: []).count, 1)
        XCTAssertNil(HandoffShare.linesImage(PatientDemo.briefs, lines: [], marks: [], arrivalOnly: false, figure: nil), "no figure loaded, no picture")
    }

    // MARK: 8. Status & Plan

    func testDispositionChipsAndLegacyValues() {
        XCTAssertNil(StatusPlanCard.dispositionChip(nil))
        XCTAssertNil(StatusPlanCard.dispositionChip("  "))
        for c in ["Fast track", "PACU", "ICU"] {
            XCTAssertEqual(StatusPlanCard.dispositionChip(c), c)
            XCTAssertEqual(StatusPlanCard.otherText(c), "")
        }
        // Saved before 1.9: Ward, Same-day discharge and Other show as Other, with their words.
        XCTAssertEqual(StatusPlanCard.dispositionChip("Ward"), "Other")
        XCTAssertEqual(StatusPlanCard.otherText("Ward"), "Ward")
        XCTAssertEqual(StatusPlanCard.dispositionChip("Same-day discharge"), "Other")
        XCTAssertEqual(StatusPlanCard.otherText("Same-day discharge"), "Same-day discharge")
        XCTAssertEqual(StatusPlanCard.dispositionChip("Other"), "Other")
        XCTAssertEqual(StatusPlanCard.otherText("Other"), "", "the bare word is not text")
        XCTAssertEqual(StatusPlanCard.dispositionChip("Step-down unit"), "Other")
        // The handoff shows what was stored.
        var r = PatientRecord()
        r.disposition = "Ward"
        XCTAssertEqual(PatientBriefs.handoff(r).first { $0.key == "concerns" }?.text, "Disposition: Ward")
    }

    func testAirwayChipsKeepASavedSgaOrNaturalUntilChanged() {
        XCTAssertEqual(StatusPlanCard.airwayOptions(nil).map(\.id), ["intubated", "extubated"])
        XCTAssertEqual(StatusPlanCard.airwayOptions("extubated").map(\.id), ["intubated", "extubated"])
        XCTAssertEqual(StatusPlanCard.airwayOptions("sga").map(\.id), ["intubated", "extubated", "sga"])
        XCTAssertEqual(StatusPlanCard.airwayOptions("sga").last?.label, "Supraglottic airway in")
        XCTAssertEqual(StatusPlanCard.airwayOptions("natural").last?.label, "Never instrumented")
    }

    // MARK: 9. Saved records

    func testBriefFieldsDecodeWithFallbacksAndRoundTrip() throws {
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data("{}".utf8))
        XCTAssertFalse(old.preopSummaryOn)
        XCTAssertTrue(old.preopSummaryEdits.isEmpty)
        XCTAssertTrue(old.handoffEdits.isEmpty)
        let withLabs = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"labs":{"pt":12.1,"ptt":30,"inr":1.0}}"#.utf8))
        XCTAssertEqual(withLabs.labs["pt"], 12.1)
        XCTAssertEqual(withLabs.labs["ptt"], 30)
        var r = PatientDemo.briefsEdited
        r.preopSummaryOn = true
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.preopSummaryEdits, r.preopSummaryEdits)
        XCTAssertEqual(back.handoffEdits, r.handoffEdits)
        XCTAssertTrue(back.preopSummaryOn)
        XCTAssertEqual(PatientBriefs.plainText(PatientBriefs.handoff(back)), PatientBriefs.plainText(PatientBriefs.handoff(r)))
    }

    // MARK: 10. The old handoff's content has a place in the new one

    func testNothingTheOldFullHandoffCarriedIsLostForTheDemoPatients() {
        // The words of every line the old handoff wrote about the history, the airway course, the lines and the plan are in
        // one block or another of the new handoff (the placeholders and the preprocedure-only lines excepted, listed in the
        // report).
        for r in [PatientDemo.record, PatientDemo.cardiac, PatientDemo.links, PatientDemo.briefs] {
            let all = PatientBriefs.handoff(r).map { $0.text + "\n" + ($0.label ?? "") }.joined(separator: "\n")
            for l in PatientSummary.historyLines(r) {
                guard !["Labs", "Liver", "Last intake", "Current infusions"].contains(l.label ?? "") else { continue }
                XCTAssertTrue(all.contains(l.text), "history line \(l.label ?? "?") is not in the handoff: \(l.text)")
            }
            // 1.12: the airway course is the short line (PatientAirwayLine); the longer sentences stay on the cards.
            if PatientSummary.airwayCourse(r) != nil, r.airwayAtEnd != nil, let line = PatientAirwayLine.course(r) {
                XCTAssertTrue(all.contains(line.text), "airway course: \(line.text)")
            }
            for d in PatientDevices.labels(r.currentDevices().filter { PatientDevice.lineKinds.contains($0.kind) || PatientDevice.supportKinds.contains($0.kind) }) {
                XCTAssertTrue(all.contains(d), "device \(d)")
            }
            if let k = IntraopConsiderations.text(r) { XCTAssertTrue(all.contains(k), "considerations") }
            if !r.todos.isEmpty { XCTAssertTrue(all.contains(r.todos), "to do") }
            if let t = PatientTEE.line(r) { XCTAssertTrue(all.contains(t.text), "TEE screen") }
            if let a = PatientDeviceFills.limbAlertText(r) { XCTAssertTrue(all.contains(a), "limb alerts") }
        }
    }

    // MARK: 11. Previous cardiac surgery is posted once (review 1.10, shots 529/530)

    func testPreviousCardiacSurgeryIsNamedInThePSHOnly() throws {
        var r = cholecystectomy
        r.problems = ["htn"]
        r.surgeries = [PatientSurgery(name: "Appendectomy")]
        PatientHistoryDetails.setCardiacSurgery("Aortic valve replacement", &r)
        XCTAssertNotNil(r.hx.cardiacSurgeryID, "the cardiovascular page's item is a PSH entry")
        for blocks in [PatientBriefs.preop(r), PatientBriefs.handoff(r)] {
            let pmh = try block(blocks, "pmh").text
            let psh = try block(blocks, "psh").text
            XCTAssertTrue(pmh.contains("previous cardiac surgery"), pmh)
            XCTAssertFalse(pmh.contains("Aortic valve replacement"), "not posted twice: \(pmh)")
            XCTAssertTrue(psh.contains("Aortic valve replacement"), psh)
            XCTAssertTrue(psh.contains("Appendectomy"), psh)
        }
        // The summary's history: the Cardiovascular line says it, the past surgical history names it.
        let hist = PatientSummary.historyLines(r)
        let cv = try XCTUnwrap(hist.first { $0.label == "Cardiovascular" }?.text)
        XCTAssertTrue(cv.hasSuffix("previous cardiac surgery"), cv)
        XCTAssertTrue(try XCTUnwrap(hist.first { $0.label == "Past surgical history" }?.text).contains("Aortic valve replacement"))
        // The cardiovascular page's own words, with no PSH beside them, keep the operation.
        XCTAssertTrue(HistorySections.cvItems(r).contains("previous cardiac surgery: Aortic valve replacement"), HistorySections.cvItems(r).joined(separator: "; "))
        // Nothing linked: nothing about it in the PMH (as before).
        var none = r
        PatientHistoryDetails.setCardiacSurgery("", &none)
        XCTAssertFalse(try block(PatientBriefs.handoff(none), "pmh").text.contains("previous cardiac surgery"))
    }
}
