import XCTest
import CoreGraphics
@testable import PeriopSignal

/// 1.11 helper B (Ben's notes 2, 3, 4, 5; the layout review's P1-2, P1-3, P1-4, P1-10 items 1–3; Q5, Q6, Q21): the
/// Intrathoracic answer from the planned procedure, the code status as a quiet link with the inline plan, the three
/// stacked links' texts, the BMI line without weight and height, the Suggested ASA that hides once chosen, the two cardiac
/// questions as one None row, the stress test in the workup and the briefs, and the intraop infusion list that carries the
/// preop drips "from preop" with no Carry-over button.
final class B111Tests: XCTestCase {

    private func with(_ procedure: String) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 66; r.sex = .male
        r.setProcedures(PlannedProcedure.parse(procedure))
        return r
    }

    private func typed(_ name: String) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 66; r.sex = .male
        r.setProcedures([PlannedProcedure(name: name)])
        return r
    }

    /// The store's path: the change, then the cross-fill that follows every change.
    private func change(_ r: inout PatientRecord, _ edit: (inout PatientRecord) -> Void) {
        let before = r
        edit(&r)
        PatientCrossFill.apply(before: before, after: &r)
    }

    // MARK: Intrathoracic from the procedure (note 3)

    func testTheCatalogAnswersIntrathoracicForKnownProcedures() {
        XCTAssertEqual(PatientPreop.intrathoracicFromProcedure(with("CABG x3")), true, "cardiac surgery opens the chest")
        XCTAssertEqual(PatientPreop.intrathoracicFromProcedure(with("Laparoscopic cholecystectomy")), false, "a known non-thoracic procedure")
        XCTAssertNil(PatientPreop.intrathoracicFromProcedure(typed("Zorblatt procedure")), "an unknown procedure keeps the pills")
        XCTAssertNil(PatientPreop.intrathoracicFromProcedure(PatientRecord()), "no procedure keeps the pills")
        var mixed = with("CABG x3")
        mixed.setProcedures(mixed.procedures + [PlannedProcedure(name: "Zorblatt procedure")])
        XCTAssertEqual(PatientPreop.intrathoracicFromProcedure(mixed), true, "any known intrathoracic procedure answers Yes")
        var unsure = with("Laparoscopic cholecystectomy")
        unsure.setProcedures(unsure.procedures + [PlannedProcedure(name: "Zorblatt procedure")])
        XCTAssertNil(PatientPreop.intrathoracicFromProcedure(unsure), "a typed procedure beside a known non-thoracic one: not answered for the user")
    }

    func testAPlannedCabgAnswersYesFromTheProcedureWhenUnset() {
        var r = PatientRecord()
        r.ageYears = 66
        change(&r) { $0.setProcedures(PlannedProcedure.parse("CABG x3")) }
        XCTAssertEqual(r.intrathoracicProcedure, true)
        XCTAssertEqual(r.fills.intrathoracic, true, "tracked as the procedure's")
        XCTAssertEqual(PatientPreop.intrathoracicDerived(r), true)
        XCTAssertEqual(PatientPreop.intrathoracicDerivedLine(r), "Intrathoracic procedure: Yes (from the procedure)")
        XCTAssertEqual(r.incision, "Intrathoracic", "the 1.9 cascade: the ARISCAT incision")
    }

    func testALapCholeAnswersNoFromTheProcedure() {
        var r = PatientRecord()
        r.ageYears = 66
        change(&r) { $0.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy")) }
        XCTAssertEqual(r.intrathoracicProcedure, false)
        XCTAssertEqual(r.fills.intrathoracic, false)
        XCTAssertEqual(PatientPreop.intrathoracicDerivedLine(r), "Intrathoracic procedure: No (from the procedure)")
        XCTAssertEqual(r.incision, "Upper abdominal", "No sets nothing else; the procedure's own fill stands")
    }

    func testAnUnknownProcedureLeavesTheQuestionUnanswered() {
        var r = PatientRecord()
        change(&r) { $0.setProcedures([PlannedProcedure(name: "Zorblatt procedure")]) }
        XCTAssertNil(r.intrathoracicProcedure)
        XCTAssertNil(r.fills.intrathoracic)
        XCTAssertNil(PatientPreop.intrathoracicDerivedLine(r))
    }

    func testTheUsersOwnAnswerAlwaysWinsAndIsNeverOverwritten() {
        // Answered before the procedure was chosen: the procedure does not overwrite it.
        var r = PatientRecord()
        change(&r) { PatientPreop.setIntrathoracic(false, &$0) }
        change(&r) { $0.setProcedures(PlannedProcedure.parse("CABG x3")) }
        XCTAssertEqual(r.intrathoracicProcedure, false, "the user's No stands under a CABG")
        XCTAssertNil(r.fills.intrathoracic)
        XCTAssertNil(PatientPreop.intrathoracicDerivedLine(r), "the pills show the user's answer")

        // Derived, then changed by the user: theirs from then on, through any procedure change.
        var s = PatientRecord()
        change(&s) { $0.setProcedures(PlannedProcedure.parse("CABG x3")) }
        change(&s) { PatientPreop.setIntrathoracic(false, &$0) }
        XCTAssertEqual(s.intrathoracicProcedure, false)
        XCTAssertNil(s.fills.intrathoracic, "no longer the procedure's")
        change(&s) { $0.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy")) }
        XCTAssertEqual(s.intrathoracicProcedure, false)
        change(&s) { $0.setProcedures([]) }
        XCTAssertEqual(s.intrathoracicProcedure, false, "a user's answer survives the procedure going")

        // A 1.10 save with the user's Yes and a CABG: untouched.
        var t = with("CABG x3")
        t.intrathoracicProcedure = true
        change(&t) { $0.ageYears = 70 }
        XCTAssertEqual(t.intrathoracicProcedure, true)
        XCTAssertNil(t.fills.intrathoracic)
    }

    func testADerivedAnswerFollowsTheProcedureAndGoesWithIt() {
        var r = PatientRecord()
        change(&r) { $0.setProcedures(PlannedProcedure.parse("CABG x3")) }
        change(&r) { $0.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy")) }
        XCTAssertEqual(r.intrathoracicProcedure, false, "the procedure changed, so did its answer")
        XCTAssertEqual(r.fills.intrathoracic, false)
        change(&r) { $0.setProcedures([]) }
        XCTAssertNil(r.intrathoracicProcedure, "cleared when the procedure goes")
        XCTAssertNil(r.fills.intrathoracic)
    }

    func testClearingADerivedAnswerKeepsTheProceduresAnswer() {
        var r = PatientRecord()
        change(&r) { $0.setProcedures(PlannedProcedure.parse("CABG x3")) }
        change(&r) { PatientPreop.setIntrathoracic(nil, &$0) }
        XCTAssertEqual(r.intrathoracicProcedure, true, "the procedure still says so; the line says where it came from")
        XCTAssertEqual(r.fills.intrathoracic, true)
    }

    func testAUnsetSavedRecordTakesTheProceduresAnswerOnItsFirstChange() {
        var r = with("CABG x3")
        XCTAssertNil(r.intrathoracicProcedure, "a 1.10 save never asked")
        change(&r) { $0.weightKg = 80 }
        XCTAssertEqual(r.intrathoracicProcedure, true)
        XCTAssertEqual(r.fills.intrathoracic, true)
    }

    func testTheIntrathoracicLineIsNotTheRiskInputsLine() {
        // P1-10 item 3: the "Incision: Intrathoracic" sub-line is no longer drawn under the pills; the function 1.9 tests
        // stays for the risk-inputs link, which still reads it.
        var r = with("CABG x3")
        change(&r) { $0.ageYears = 70 }
        XCTAssertNotNil(PatientPreop110.riskInputsLine(r))
        XCTAssertTrue(PatientPreop110.riskInputsLine(r)?.contains("Intrathoracic incision") ?? false)
    }

    // MARK: Code status (note 2, Q5)

    func testCodeStatusRowReadsEachState() {
        var r = PatientRecord()
        XCTAssertNil(PatientPreop.codeStatusRow(r), "nothing chosen: the box shows + Add code status")
        XCTAssertEqual(PatientPreop.codeStatusLinkTitle, "Add code status")
        r.codeStatus = .full
        XCTAssertEqual(PatientPreop.codeStatusRow(r)?.text, "Code status: Full")
        XCTAssertEqual(PatientPreop.codeStatusRow(r)?.alert, false)
        r.codeStatus = .notDiscussed
        XCTAssertEqual(PatientPreop.codeStatusRow(r)?.text, "Code status: Not discussed")
        r.codeStatus = .dnrDni
        XCTAssertEqual(PatientPreop.codeStatusRow(r)?.text, "Code status: DNR · DNI")
        r.codeStatus = .dnr
        r.polst = true
        XCTAssertEqual(PatientPreop.codeStatusRow(r)?.text, "Code status: DNR · POLST on file")
        r.codeStatus = .limited
        r.codeStatusLimits = "no compressions"
        XCTAssertEqual(PatientPreop.codeStatusRow(r)?.text, "Code status: Limited: no compressions · POLST on file")
    }

    func testAPolstWithoutAStatusIsNeverHiddenBehindTheLink() {
        var r = PatientRecord()
        r.polst = true
        let row = PatientPreop.codeStatusRow(r)
        XCTAssertNotNil(row)
        XCTAssertTrue(row?.alert ?? false)
        XCTAssertTrue(row?.text.contains("POLST on file") ?? false)
    }

    func testThePlanIsAskedInlineUnderALimitingStatusWithTheRedCaptionUntilChosen() {
        var r = PatientRecord()
        XCTAssertFalse(PatientPreop.asksCodeStatusPlan(r))
        r.codeStatus = .full
        XCTAssertFalse(PatientPreop.asksCodeStatusPlan(r), "a full code has no plan to ask")
        XCTAssertNil(PatientPreop.codeStatusPlanCaption(r))
        for s in [CodeStatus.dnr, .dni, .dnrDni, .limited] {
            r.codeStatus = s
            r.codeStatusPlan = nil
            XCTAssertTrue(PatientPreop.asksCodeStatusPlan(r), "\(s)")
            let cap = PatientPreop.codeStatusPlanCaption(r)
            XCTAssertEqual(cap?.alert, true, "\(s): red while not discussed")
            XCTAssertTrue(cap?.text.hasPrefix("Plan not yet discussed") ?? false)
        }
        r.codeStatus = .dnr
        r.codeStatusPlan = .maintained
        XCTAssertEqual(PatientPreop.codeStatusPlanCaption(r)?.text, CodeStatusPlan.maintained.inView, "Maintained's instruction stays in view")
        XCTAssertEqual(PatientPreop.codeStatusPlanCaption(r)?.alert, false)
        r.codeStatusPlan = .modified
        XCTAssertNil(PatientPreop.codeStatusPlanCaption(r), "the chosen chip says it")
        r.codeStatusPlan = .suspended
        XCTAssertNil(PatientPreop.codeStatusPlanCaption(r))
    }

    func testTheHandoffsCodeStatusWordingIsUnchanged() {
        var r = PatientRecord()
        r.codeStatus = .dnrDni
        r.codeStatusPlan = .modified
        r.codeStatusPlanNote = "accepts intubation"
        r.polst = true
        XCTAssertEqual(PatientCodeStatus.text(r), "DNR/DNI (POLST on file); modified for the procedure: accepts intubation")
    }

    // MARK: The three stacked links

    func testTheVitalsAndIntakeLinksCollapseToTheirValues() {
        var r = PatientRecord()
        XCTAssertNil(PatientPreop.vitalsRow(r))
        XCTAssertNil(PatientPreop.intakeRow(r))
        XCTAssertEqual(PatientPreop.vitalsLinkTitle, "Add preoperative vitals")
        XCTAssertEqual(PatientPreop.intakeLinkTitle, "Last intake")
        r.vitals = ["sbp": 148, "dbp": 86, "hr": 72, "spo2": 95]
        XCTAssertEqual(PatientPreop.vitalsRow(r), "Vitals: " + PatientSummary.vitalsLine(r)!)
        XCTAssertTrue(PatientPreop.vitalsRow(r)?.contains("BP 148/86") ?? false)
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now)
        r.lastSolids = midnight
        r.lastClears = Calendar.current.date(byAdding: .hour, value: 5, to: midnight)
        let line = PatientPreop.intakeRow(r, now: now)
        XCTAssertTrue(line?.hasPrefix("Last intake: Solids ") ?? false, line ?? "nil")
        XCTAssertTrue(line?.contains(" · clears ") ?? false, line ?? "nil")
    }

    // MARK: Say it once (P1-10 items 1 and 2)

    func testTheBodyLineDropsTheWeightAndHeightTheFieldsShow() {
        var r = PatientRecord()
        XCTAssertNil(PatientPreop.derivedBodyLine(r))
        r.sex = .male; r.heightCm = 178; r.weightKg = 96
        let full = PatientSummary.bodyLine(r)
        XCTAssertTrue(full.hasPrefix("96 kg · 178 cm · BMI "), full)
        let derived = PatientPreop.derivedBodyLine(r)
        XCTAssertEqual(derived, full.components(separatedBy: " · ").dropFirst(2).joined(separator: " · "))
        XCTAssertTrue(derived?.hasPrefix("BMI 30.3 · BSA ") ?? false, derived ?? "nil")
        XCTAssertTrue(derived?.contains("IBW 73 kg") ?? false)
        XCTAssertFalse(derived?.contains("96 kg") ?? true)
        XCTAssertFalse(derived?.contains("178 cm") ?? true)
    }

    func testTheSuggestedAsaHidesOnceThatClassIsChosen() {
        var r = PatientDemo.record
        let s = PatientRules.asaSuggestion(r)
        XCTAssertNotNil(s)
        r.asaClass = nil
        XCTAssertTrue(PatientPreop.showsAsaSuggestion(r), "shown while none is chosen")
        r.asaClass = s!.level
        XCTAssertFalse(PatientPreop.showsAsaSuggestion(r), "the chosen class is the suggestion: the chips say it")
        r.asaClass = s!.level == 2 ? 3 : 2
        XCTAssertTrue(PatientPreop.showsAsaSuggestion(r), "shown while they differ")
        XCTAssertFalse(PatientPreop.showsAsaSuggestion(PatientRecord()), "nothing to suggest")
    }

    // MARK: One None row for the two cardiac questions

    func testBothCardiacQuestionsAreOneRowUntilOneIsAnswered() {
        var r = PatientRecord()
        XCTAssertEqual(PatientPreop.cardiacNone(r), false, "both unanswered: the row with None not applied")
        PatientPreop.setCardiacNone(true, &r)
        XCTAssertEqual(r.cardiacSymptomsAnswer, false)
        XCTAssertEqual(r.activeCardiacAnswer, false)
        XCTAssertEqual(PatientPreop.cardiacNone(r), true, "None applied")
        PatientPreop.setCardiacNone(false, &r)
        XCTAssertNil(r.cardiacSymptomsAnswer)
        XCTAssertNil(r.activeCardiacAnswer)
        XCTAssertEqual(PatientPreop.cardiacNone(r), false, "a second tap clears both")

        r.cardiacSymptomsAnswer = false
        XCTAssertNil(PatientPreop.cardiacNone(r), "one answered: the two rows")
        r.cardiacSymptomsAnswer = nil
        r.cardiacSymptoms = ["chest-pain"]
        XCTAssertNil(PatientPreop.cardiacNone(r), "a Yes by its chips: the two rows")
        PatientPreop.setCardiacNone(true, &r)
        XCTAssertTrue(r.cardiacSymptoms.isEmpty, "None clears the chips too")
        r.activeCardiacAnswer = true
        XCTAssertNil(PatientPreop.cardiacNone(r))
    }

    func testNoneWritesWhatTwoNoTapsWrote() {
        var byNone = PatientRecord()
        PatientPreop.setCardiacNone(true, &byNone)
        var byTaps = PatientRecord()
        PatientPreop110.tapYesNo(false, answer: \.cardiacSymptomsAnswer, chips: \.cardiacSymptoms, in: &byTaps)
        PatientPreop110.tapYesNo(false, answer: \.activeCardiacAnswer, chips: \.activeCardiac, in: &byTaps)
        XCTAssertEqual(byNone, byTaps)
    }

    // MARK: Stress test (note 4, Q21)

    private func stressed(_ kind: PatientStressTest.Kind?, _ result: PatientStressTest.Result?, date: PatientMonthYear = PatientMonthYear(month: 3, year: 2025), findings: String = "") -> PatientRecord {
        var r = with("Laparoscopic cholecystectomy")
        r.stressTest = PatientStressTest(kind: kind, result: result, date: date, findings: findings)
        return r
    }

    func testTheWorkupHasAStressTestChipThatFillsFromTheRecord() {
        let empty = PatientPreop.workup(with("Laparoscopic cholecystectomy")).first { $0.id == "stress" }
        XCTAssertNotNil(empty)
        XCTAssertEqual(empty?.title, "Stress test")
        XCTAssertEqual(empty?.key, "workup:stress")
        XCTAssertFalse(empty?.filled ?? true)
        XCTAssertNotNil(PatientEditor(preopKey: "workup:stress"))
        XCTAssertEqual(PatientEditor.workup("stress").title, "Stress Test")

        let r = stressed(.dobutamine, .negative, findings: "no ischemia at peak dose")
        let item = PatientPreop.workup(r).first { $0.id == "stress" }
        XCTAssertEqual(item?.summary, "Dobutamine stress test (03/2025): negative, no ischemia; no ischemia at peak dose")
        XCTAssertFalse(item?.alert ?? true)
        XCTAssertTrue(PatientPreop.workupHasData(r))
        let pos = PatientPreop.workup(stressed(.exercise, .positive)).first { $0.id == "stress" }
        XCTAssertTrue(pos?.alert ?? false, "a positive test is marked for attention")
    }

    func testTheStressLineForTheBriefs() {
        XCTAssertNil(PatientPreop.stressLine(with("Laparoscopic cholecystectomy")))
        var l = PatientPreop.stressLine(stressed(.dobutamine, .negative, findings: "no ischemia at peak dose"))
        XCTAssertEqual(l?.label, "Stress test")
        XCTAssertEqual(l?.text, "Dobutamine, 03/2025: negative, no ischemia; No ischemia at peak dose")
        XCTAssertFalse(l?.alert ?? true)
        l = PatientPreop.stressLine(stressed(.exercise, .positive, date: PatientMonthYear()))
        XCTAssertEqual(l?.text, "Exercise: positive for ischemia")
        XCTAssertTrue(l?.alert ?? false)
        l = PatientPreop.stressLine(stressed(nil, .equivocal, date: PatientMonthYear()))
        XCTAssertEqual(l?.text, "equivocal")
        l = PatientPreop.stressLine(stressed(.other, nil, date: PatientMonthYear(year: 2024), findings: "nuclear perfusion study, small fixed inferior defect"))
        XCTAssertEqual(l?.text, "Other, 2024: Nuclear perfusion study, small fixed inferior defect")
    }

    func testTheStressTestReadsInThePreopSummaryAndTheHandoffWorkupBlock() {
        var r = stressed(.dobutamine, .positive, findings: "inferior wall ischemia")
        r.ecg = ["Normal sinus rhythm"]
        r.lhc.dominance = "right"; r.lhc.result = "non-obstructive"
        for blocks in [PatientBriefs.preop(r), PatientBriefs.handoff(r)] {
            let w = blocks.first { $0.key == "workup" }
            XCTAssertNotNil(w)
            let lines = w?.text.components(separatedBy: "\n") ?? []
            let stress = lines.firstIndex { $0.hasPrefix("Stress test: Dobutamine, 03/2025: positive for ischemia; Inferior wall ischemia") }
            let ecg = lines.firstIndex { $0.hasPrefix("ECG:") }
            let cor = lines.firstIndex { $0.hasPrefix("Coronaries:") }
            XCTAssertNotNil(stress, w?.text ?? "")
            XCTAssertNotNil(ecg); XCTAssertNotNil(cor)
            XCTAssertTrue(ecg! < stress! && stress! < cor!, "after the ECG and echo, before the catheterizations: \(lines)")
            XCTAssertTrue(w?.alert ?? false, "a positive test marks the block")
            XCTAssertTrue(w?.marks.contains("positive for ischemia") ?? false)
        }
        let none = PatientBriefs.preop(with("Laparoscopic cholecystectomy")).first { $0.key == "workup" }
        XCTAssertFalse(none?.text.contains("Stress test") ?? false, "nothing without a test (the block itself may be absent)")
    }

    func testTheStressResultAndTypeChipsFitOneLineAt375() {
        // A row straight inside a group on a 375-pt phone: the margins and the row's 14-pt insets (ChipChecks110Tests).
        let width: CGFloat = 375 - 40 - 28
        XCTAssertNotNil(ChipMetrics.lineFit(PatientStressTestEditor.results, choice: true, in: width), "Negative · Positive · Equivocal")
        XCTAssertNotNil(ChipMetrics.lineFit(PatientStressTestEditor.kinds, choice: true, in: width), "Exercise · Dobutamine · Other")
        XCTAssertEqual(PatientStressTestEditor.results.map(\.label), ["Negative/normal", "Positive/ischemia", "Equivocal/nondiagnostic"], "the full words for VoiceOver")
        let plan = CodeStatusPlan.allCases.map { ChipChoice($0.rawValue, $0.label, short: $0.rawValue.capitalized) }
        XCTAssertNotNil(ChipMetrics.lineFit(plan, choice: true, in: width), "Maintained · Modified · Suspended under the status row")
    }

    func testTheWorkupLinkIsNamedForWhatItHolds() {
        XCTAssertEqual(PatientPreop.workupLinkTitle, "Add Preprocedure Cardiac Workup (ECG, Echo, LHC)")
        XCTAssertEqual(PatientPreop.cardiacNoneTitle, "Cardiac symptoms or acute conditions")
    }

    // MARK: Infusions (note 5, Q6)

    private func withDrips() -> PatientRecord {
        var r = PatientRecord()
        r.homeInfusions = [PatientInfusion(drug: "Epinephrine", rate: "0.05 mcg/kg/min"), PatientInfusion(drug: "Norepinephrine", rate: "0.1 mcg/kg/min")]
        return r
    }

    func testThePreopDripsAreInTheIntraopListFromTheStartTaggedFromPreop() {
        let r = withDrips()
        let rows = IntraopInfusionList.rows(r)
        XCTAssertEqual(rows.map(\.drug), ["Epinephrine", "Norepinephrine"])
        XCTAssertEqual(rows.map(\.rate), ["0.05 mcg/kg/min", "0.1 mcg/kg/min"])
        XCTAssertTrue(rows.allSatisfy(\.fromPreop))
        XCTAssertTrue(rows.allSatisfy(\.preopOnly))
        XCTAssertEqual(rows.map(\.id), r.homeInfusions.map(\.id), "the row is the preop drip's until it is edited")
        XCTAssertTrue(r.infusions.isEmpty, "nothing written until the user edits one")
        XCTAssertEqual(IntraopInfusionList.fromPreopCaption, "from preop")
    }

    func testEditingARateWritesTheCasesOwnCopyAndTheTagGoes() {
        var r = withDrips()
        let epi = r.homeInfusions[0]
        IntraopInfusionList.setRate(epi.id, "0.08 mcg/kg/min", in: &r)
        XCTAssertEqual(r.infusions.count, 1)
        XCTAssertEqual(r.infusions[0].fromPreop, epi.id, "tagged with the preop drip")
        XCTAssertEqual(r.infusions[0].id, epi.id, "the same row keeps its focus")
        XCTAssertEqual(r.infusions[0].drug, "Epinephrine")
        XCTAssertEqual(r.infusions[0].rate, "0.08 mcg/kg/min")
        XCTAssertEqual(r.homeInfusions[0].rate, "0.05 mcg/kg/min", "the preop record is untouched")
        let rows = IntraopInfusionList.rows(r)
        XCTAssertEqual(rows.count, 2, "nothing doubles")
        XCTAssertEqual(rows[0].rate, "0.08 mcg/kg/min")
        XCTAssertFalse(rows[0].fromPreop, "edited in the room: the tag goes")
        XCTAssertFalse(rows[0].preopOnly)
        XCTAssertTrue(rows[1].fromPreop)
        // Typed back to the preop rate: it reads as the preop drip again.
        IntraopInfusionList.setRate(epi.id, "0.05 mcg/kg/min", in: &r)
        XCTAssertTrue(IntraopInfusionList.rows(r)[0].fromPreop)
        XCTAssertEqual(r.infusions.count, 1, "edited in place, not copied again")
    }

    func testChangingTheDrugWritesTheCopyToo() {
        var r = withDrips()
        IntraopInfusionList.setDrug(r.homeInfusions[1].id, "Vasopressin", in: &r)
        XCTAssertEqual(r.infusions.map(\.drug), ["Vasopressin"])
        XCTAssertEqual(IntraopInfusionList.rows(r).map(\.drug), ["Epinephrine", "Vasopressin"])
        XCTAssertEqual(r.homeInfusions.map(\.drug), ["Epinephrine", "Norepinephrine"])
    }

    func testDeletingARowTakesItOutOfTheCasesListOnly() {
        var r = withDrips()
        let epi = r.homeInfusions[0]
        IntraopInfusionList.remove(epi.id, in: &r)
        XCTAssertEqual(IntraopInfusionList.rows(r).map(\.drug), ["Norepinephrine"], "gone from the room's list")
        XCTAssertEqual(r.homeInfusions.map(\.drug), ["Epinephrine", "Norepinephrine"], "the preop record survives")
        XCTAssertEqual(r.infusions.count, 1)
        XCTAssertTrue(IntraopInfusionList.isTombstone(r.infusions[0]))
        XCTAssertTrue(r.infusions.map(\.text).allSatisfy(\.isEmpty), "an empty text, left out of every summary")
        // The handoff keeps the "running before the case" line for it.
        let block = PatientBriefs.handoff(r).first { $0.key == "infusions" }
        XCTAssertTrue(block?.text.contains("running before the case") ?? false, block?.text ?? "")
        XCTAssertTrue(block?.text.contains("Epinephrine at 0.05 mcg/kg/min") ?? false)
        XCTAssertFalse(block?.text.contains("Infusions: ;") ?? true)

        // A copy already edited, then deleted: the same.
        var s = withDrips()
        IntraopInfusionList.setRate(s.homeInfusions[0].id, "0.1 mcg/kg/min", in: &s)
        IntraopInfusionList.remove(s.homeInfusions[0].id, in: &s)
        XCTAssertEqual(IntraopInfusionList.rows(s).map(\.drug), ["Norepinephrine"])
        XCTAssertEqual(s.homeInfusions.count, 2)

        // A drip started in the room is simply removed.
        var t = PatientRecord()
        t.infusions = [PatientInfusion(drug: "Insulin", rate: "4 units/h")]
        IntraopInfusionList.remove(t.infusions[0].id, in: &t)
        XCTAssertTrue(t.infusions.isEmpty)
    }

    func testASavedCarryOverIsMergedByDrugSoNothingDoubles() {
        // 1.10's Carry-over button copied the drips without a tag.
        var r = withDrips()
        r.infusions = r.homeInfusions.map { PatientInfusion(drug: $0.drug, rate: $0.rate) }
        let rows = IntraopInfusionList.rows(r)
        XCTAssertEqual(rows.map(\.drug), ["Epinephrine", "Norepinephrine"])
        XCTAssertTrue(rows.allSatisfy { !$0.fromPreop && !$0.preopOnly }, "the case's own copies")
        XCTAssertEqual(rows.map(\.id), r.infusions.map(\.id))
        // A drip typed in the room with the same name as a preop one: one row, the room's.
        var s = withDrips()
        s.infusions = [PatientInfusion(drug: "epinephrine", rate: "0.1 mcg/kg/min"), PatientInfusion(drug: "Insulin", rate: "4 units/h")]
        let more = IntraopInfusionList.rows(s)
        XCTAssertEqual(more.map(\.drug), ["epinephrine", "Norepinephrine", "Insulin"])
        XCTAssertEqual(more.map(\.fromPreop), [false, true, false])
    }

    func testThePreopDripsStillReadBeforeTheCaseInThePreopSummary() {
        let r = withDrips()
        let hist = PatientSummary.historyLines(r)
        XCTAssertTrue(hist.contains { $0.label == "Current infusions" && $0.text.contains("Epinephrine") })
    }

    // MARK: A 1.10 record keeps decoding

    func testAOneTenRecordDecodesWithTheNewFieldsAtTheirDefaults() throws {
        var r = withDrips()
        r.ageYears = 70; r.setProcedures(PlannedProcedure.parse("CABG x3"))
        r.infusions = [PatientInfusion(drug: "Insulin", rate: "4 units/h")]
        r.stressTest = PatientStressTest(kind: .exercise, result: .negative)
        r.fills.intrathoracic = true
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        // What a 1.10 build wrote: none of the 1.11 keys.
        json["stressTest"] = nil
        var fills = try XCTUnwrap(json["fills"] as? [String: Any])
        fills["intrathoracic"] = nil
        json["fills"] = fills
        for key in ["infusions", "homeInfusions"] {
            var list = try XCTUnwrap(json[key] as? [[String: Any]])
            for i in list.indices { list[i]["fromPreop"] = nil }
            json[key] = list
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        let back = try JSONDecoder().decode(PatientRecord.self, from: data)
        XCTAssertTrue(back.stressTest.isEmpty)
        XCTAssertNil(back.fills.intrathoracic)
        XCTAssertTrue(back.infusions.allSatisfy { $0.fromPreop == nil })
        XCTAssertEqual(back.infusions.map(\.drug), ["Insulin"])
        XCTAssertEqual(back.homeInfusions.map(\.drug), ["Epinephrine", "Norepinephrine"])
        XCTAssertEqual(back.procedure, r.procedure)
        XCTAssertEqual(IntraopInfusionList.rows(back).map(\.drug), ["Epinephrine", "Norepinephrine", "Insulin"])
    }

    func testTheNewFieldsRoundTrip() throws {
        var r = PatientRecord()
        r.stressTest = PatientStressTest(kind: .dobutamine, result: .equivocal, date: PatientMonthYear(month: 1, year: 2026), findings: "limited windows")
        r.fills.intrathoracic = false
        r.homeInfusions = [PatientInfusion(drug: "Heparin", rate: "1200 units/h")]
        IntraopInfusionList.setRate(r.homeInfusions[0].id, "1400 units/h", in: &r)
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
        XCTAssertEqual(back.infusions[0].fromPreop, r.homeInfusions[0].id)
    }

    // MARK: The demo patients behind the screenshots

    @MainActor func testTheDemoPatientsShowWhatTheirShotsClaim() {
        let cabg = PatientDemo.cardio111
        XCTAssertEqual(PatientPreop.intrathoracicDerivedLine(cabg), "Intrathoracic procedure: Yes (from the procedure)")
        XCTAssertEqual(PatientPreop.codeStatusRow(cabg)?.text, "Code status: DNR")
        XCTAssertEqual(PatientPreop.codeStatusPlanCaption(cabg)?.alert, true)
        XCTAssertNotNil(PatientPreop.vitalsRow(cabg))
        XCTAssertNotNil(PatientPreop.intakeRow(cabg))
        XCTAssertTrue(PatientPreop.workup(cabg).first { $0.id == "stress" }?.filled ?? false)
        XCTAssertEqual(IntraopInfusionList.rows(cabg).map(\.fromPreop), [true, true])
        let chole = PatientDemo.cardio111Chole
        XCTAssertEqual(PatientPreop.intrathoracicDerivedLine(chole), "Intrathoracic procedure: No (from the procedure)")
        XCTAssertEqual(PatientPreop.cardiacNone(chole), true)
        XCTAssertTrue(PatientFunctional.stepwiseApplies(chole))
        XCTAssertFalse(PatientFunctional.cardiacStep(chole).alert)
        XCTAssertEqual(PatientPreop.codeStatusRow(chole)?.text, "Code status: Full")
        XCTAssertNotNil(PatientStore.debugSeed("demo-cardio111"))
        XCTAssertNotNil(PatientStore.debugSeed("demo-cardio111-chole"))
    }
}
