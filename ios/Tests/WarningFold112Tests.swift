import XCTest
@testable import PeriopSignal

/// Ben, Nov 13 (with a picture of the red "Assess functional capacity" row): "Have this default collapsed (and all warnings)".
/// That row was the one warning in My Patient that opened by itself; it now starts as its one red line. And a folded
/// Cardiopulmonary box, which showed nothing of it, keeps that red line in view.
final class WarningFold112Tests: XCTestCase {

    private func adult(_ procedure: String, problems: Set<String>) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 70; r.sex = .male
        r.setProcedures(PlannedProcedure.parse(procedure))
        r.problems = problems
        return r
    }

    func testTheResultRowStartsClosedAndOpensOnlyWhenChosen() {
        XCTAssertFalse(PatientFunctional.resultRowOpen(chosen: nil), "a warning no longer opens itself")
        XCTAssertTrue(PatientFunctional.resultRowOpen(chosen: true))
        XCTAssertFalse(PatientFunctional.resultRowOpen(chosen: false))
    }

    func testAFoldedCardiopulmonaryBoxKeepsAWarningResultInViewAsOneRedLine() throws {
        let records = [adult("Open abdominal aortic aneurysm repair", problems: ["cad", "hf", "ckd", "dm"]),
                       adult("Laparoscopic cholecystectomy", problems: ["copd", "htn", "dm"]),
                       adult("Cataract surgery", problems: [])]
        var warnings = 0
        for r in records {
            let step = PatientFunctional.cardiacStep(r)
            let summary = PatientBox.cardio.summary(r)
            let line = summary.derivedAlerts.first { $0.text == step.title }
            if step.alert {
                warnings += 1
                let shown = try XCTUnwrap(line, step.title)
                XCTAssertTrue(shown.alert)
                XCTAssertNil(shown.label)
                XCTAssertNil(PatientBox.lineLimit(shown), "a red line is never cut")
                XCTAssertTrue(summary.lines.contains(shown))
            } else {
                XCTAssertNil(line, "a result that is not a warning is not carried: " + step.title)
                XCTAssertNil(PatientFunctional.foldedResultLine(r))
            }
            // Worked out, not entered: it never makes the box count as filled in.
            XCTAssertFalse(summary.entered.contains { $0.text == step.title })
        }
        XCTAssertGreaterThan(warnings, 0, "one of these records has a warning result")
    }

    func testTheResultIsNotCarriedWhereTheStepwiseApproachDoesNotApply() {
        var child = adult("Tonsillectomy", problems: [])
        child.ageYears = 6
        XCTAssertNil(PatientFunctional.foldedResultLine(child))
        let cardiac = adult("Coronary artery bypass grafting", problems: ["cad", "hf"])
        XCTAssertFalse(PatientFunctional.stepwiseApplies(cardiac))
        XCTAssertNil(PatientFunctional.foldedResultLine(cardiac))
        XCTAssertFalse(PatientBox.cardio.summary(cardiac).derivedAlerts.contains { $0.text.contains("functional capacity") })
    }
}
