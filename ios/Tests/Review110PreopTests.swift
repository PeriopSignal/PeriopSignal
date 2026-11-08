import XCTest
import UIKit
@testable import PeriopSignal

/// 1.10 review, Preprocedure: the 2024 AHA/ACC noncardiac evaluation kept off planned cardiac surgery, the "+ Urgency" link
/// (Ben's evening answer 2) and the compact, optional labs "Drawn" row (Ben's evening answer 1).
final class Review110PreopTests: XCTestCase {

    /// A 67-year-old man with coronary disease on insulin, a pacemaker and poor functional capacity: the noncardiac
    /// evaluation has an RCRI over 1, a risk modifier, branch advice and condition notes for him.
    private func patient(_ procedure: String) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male
        r.problems = ["cad", "insulin", "pacemaker"]
        r.mets = "lt4"
        r.setProcedures(PlannedProcedure.parse(procedure))
        r.highRiskSurgery = true
        r.cardiacSymptoms = ["dyspnea"]
        return r
    }

    private func labels(_ r: PatientRecord) -> [String?] { PatientSummary.assessmentLines(r).map(\.label) }

    // MARK: Cardiac evaluation and cardiac surgery

    func testLobectomyKeepsTheStepwiseEvaluation() {
        let r = patient("VATS lobectomy")
        XCTAssertFalse(PatientRules.cardiacSurgery(r))
        XCTAssertTrue(PatientFunctional.stepwiseApplies(r))
        XCTAssertEqual(PatientFunctional.evaluationNote(r), PatientFunctional.cardiacNote)
        XCTAssertTrue(labels(r).contains("Cardiac evaluation"), "the verdict goes into the briefs")
        XCTAssertTrue(PatientFunctional.cardiacStep(r).detail.contains("RCRI"))
        XCTAssertFalse(PatientFunctional.branchAdvice(r).isEmpty)
        XCTAssertTrue(PatientFunctional.conditionAdvice(r).contains { $0.hasPrefix("Elevated-risk surgery with known cardiovascular disease") },
                      "troponin surveillance reads the RCRI")
        XCTAssertTrue(labels(r).contains("Cardiac symptoms"))
    }

    func testAorticValveReplacementGetsNoNoncardiacVerdictOrRCRI() {
        let r = patient("AVR")
        XCTAssertTrue(PatientRules.cardiacSurgery(r))
        XCTAssertFalse(PatientFunctional.stepwiseApplies(r))
        XCTAssertEqual(PatientFunctional.evaluationNote(r), PatientFunctional.cardiacSurgeryNote)
        XCTAssertEqual(PatientFunctional.cardiacSurgeryNote, "Cardiac surgery: the 2024 AHA/ACC stepwise evaluation and the RCRI are not shown, as both are for noncardiac surgery.")
        // No verdict and no figure boxes in the briefs.
        XCTAssertFalse(labels(r).contains("Cardiac evaluation"), "\(labels(r))")
        XCTAssertTrue(PatientFunctional.branchAdvice(r).isEmpty)
        let briefs = PatientSummary.assessmentLines(r).map(\.text).joined(separator: " | ")
        XCTAssertFalse(briefs.contains("RCRI"), briefs)
        XCTAssertFalse(briefs.contains("proceed"), briefs)
        // The RCRI-based condition notes go; the others stay (conservative: nothing safety-relevant hidden).
        let advice = PatientFunctional.conditionAdvice(r)
        XCTAssertFalse(advice.contains { $0.hasPrefix("Elevated-risk surgery with known cardiovascular disease") })
        XCTAssertFalse(advice.contains { $0.contains("RCRI") })
        XCTAssertTrue(advice.contains { $0.hasPrefix("Pacemaker or ICD") }, "\(advice)")
        XCTAssertTrue(advice.contains { $0.hasPrefix("Heart failure") || $0.hasPrefix("New dyspnea") }, "\(advice)")
        // The symptoms and acute-condition answers are still recorded and carried.
        XCTAssertTrue(labels(r).contains("Cardiac symptoms"))
        var acute = r
        acute.activeCardiac = ["arrhythmia"]
        XCTAssertTrue(labels(acute).contains("Acute cardiac conditions"))
    }

    func testABloodPressureDeferralNeedsTheRCRISoNotForCardiacSurgery() {
        var lobe = patient("VATS lobectomy")
        lobe.problems.insert("htn-180")
        lobe.urgency = .elective
        XCTAssertTrue(PatientFunctional.conditionAdvice(lobe).contains { $0.hasPrefix("A recent history of SBP ≥180") })
        var avr = patient("AVR")
        avr.problems.insert("htn-180")
        avr.urgency = .elective
        XCTAssertFalse(PatientFunctional.conditionAdvice(avr).contains { $0.hasPrefix("A recent history of SBP ≥180") })
    }

    func testUnder18NoteIsUnchanged() {
        var child = PatientRecord()
        child.ageYears = 12
        child.setProcedures(PlannedProcedure.parse("AVR"))
        XCTAssertEqual(PatientFunctional.evaluationNote(child), PatientFunctional.cardiacAdultOnly)
        XCTAssertFalse(PatientFunctional.stepwiseApplies(child))
    }

    // MARK: + Urgency

    func testUrgencyLinkReadsUrgencyThenCollapsesWithChange() {
        var r = PatientRecord()
        XCTAssertEqual(PatientPreop110.urgencyLinkTitle(r), "Urgency", "\"+ Urgency\", renamed from \"+ Procedure urgency\"")
        XCTAssertNil(PatientPreop110.urgencyCollapsedParts(r))
        r.urgency = .elective
        let parts = PatientPreop110.urgencyCollapsedParts(r)
        XCTAssertEqual(parts?.title, "Urgency: Elective")
        XCTAssertEqual(parts?.action, "Change")
        r.urgency = nil
        XCTAssertEqual(PatientPreop110.urgencyLinkTitle(r), "Urgency", "cleared, the link again")
    }

    // MARK: Labs drawn: small and optional

    func testNothingIsShownWhenNoDrawnTimeIsEntered() {
        var r = PatientRecord()
        r.labs = ["k": 4.1, "na": 138]
        XCTAssertNil(BriefLabs.make(r, withIntraop: false, now: Date()).labs.caption)
        XCTAssertNil(BriefLabs.make(r, withIntraop: true, now: Date()).labs.caption)
        XCTAssertFalse(PatientBriefs.plainText(PatientBriefs.preop(r)).contains("Preop labs"))
    }

    func testTheDrawnRowIsOneCompactLine() {
        // A caption-size line: the text's line height and the row's padding (the old Drawn row was a 14.5 pt label with
        // 9 pt above and below, about 36 pt; a lab row is about 58 pt).
        let empty = UIFont.systemFont(ofSize: LabsDrawnRow.fontSize).lineHeight + 2 * LabsDrawnRow.verticalPadding
        XCTAssertLessThanOrEqual(empty, 24, "one compact row while empty")
        XCTAssertLessThanOrEqual(LabsDrawnRow.fontSize, 12.5)
        XCTAssertLessThanOrEqual(LabsDrawnRow.verticalPadding, 5)
    }
}
