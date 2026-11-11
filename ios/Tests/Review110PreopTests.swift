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
        XCTAssertEqual(PatientFunctional.cardiacSurgeryNote, "Cardiac surgery: the 2024 AHA/ACC stepwise evaluation, the RCRI and the guideline's valve notes are not shown, as they are for noncardiac surgery; its other notes by condition are kept.")
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

    /// A planned AVR with "severe aortic stenosis" typed in the one-liner: the guideline's "evaluate for valve intervention
    /// before elective surgery" note is not shown, on the screen or in the briefs, as the operation is that intervention;
    /// the lesion itself still is. The same patient having a lobectomy keeps the note.
    func testValveNotesAreNotShownForPlannedCardiacSurgery() {
        let severeNote = { (r: PatientRecord) -> Bool in PatientFunctional.conditionAdvice(r).contains { $0.hasPrefix("Severe valve disease:") } }
        let echoNote = { (r: PatientRecord) -> Bool in PatientFunctional.conditionAdvice(r).contains { $0.hasPrefix("Valve disease: echo before surgery") } }
        func typed(_ procedure: String, _ line: String) -> PatientRecord {
            var r = patient(procedure)
            PatientNote.apply(PatientNote.read(line).findings.map(\.change), to: &r)
            PatientHistoryDetails.sync(&r)
            return r
        }

        let avr = typed("AVR", "severe aortic stenosis")
        XCTAssertTrue(PatientRules.cardiacSurgery(avr))
        XCTAssertTrue(avr.has("valve-severe"), "the one-liner records the lesion")
        XCTAssertFalse(severeNote(avr), "\(PatientFunctional.conditionAdvice(avr))")
        let briefs = PatientSummary.assessmentLines(avr).map(\.text).joined(separator: " | ")
        XCTAssertFalse(briefs.contains("valve intervention"), briefs)
        XCTAssertTrue(PatientFunctional.conditionAdvice(avr).contains { $0.hasPrefix("Pacemaker or ICD") }, "the other notes stay")
        let history = PatientSummary.historyLines(avr).map(\.text).joined(separator: " | ")
        XCTAssertTrue(history.localizedCaseInsensitiveContains("aortic stenosis"), "the lesion is still in the briefs: \(history)")

        let demo = PatientDemo.echo110Severe
        XCTAssertTrue(demo.has("valve-severe"), "the shots' demo (598-599) records the lesion")
        XCTAssertFalse(severeNote(demo))

        let lobe = typed("VATS lobectomy", "severe aortic stenosis")
        XCTAssertTrue(severeNote(lobe), "noncardiac surgery keeps it")

        // An ungraded or moderate lesion: the echo reminder, likewise, only for noncardiac surgery.
        var cabg = patient("CABG"); cabg.hx.valves["mitral"] = PatientValve(regurgitation: true, regurgitationGrade: "moderate")
        PatientHistoryDetails.sync(&cabg)
        XCTAssertTrue(PatientRules.cardiacSurgery(cabg))
        XCTAssertFalse(echoNote(cabg))
        var lobe2 = patient("VATS lobectomy"); lobe2.hx.valves = cabg.hx.valves
        PatientHistoryDetails.sync(&lobe2)
        XCTAssertTrue(echoNote(lobe2))

        // The congenital heart disease consult is kept for cardiac surgery (the conservative choice).
        var asd = patient("AVR"); asd.problems.insert("chd")
        XCTAssertTrue(PatientFunctional.conditionAdvice(asd).contains { $0.hasPrefix("Congenital heart disease") })
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
        XCTAssertNil(BriefLabs.make(r, withIntraop: false, now: Date()).caption)
        XCTAssertNil(BriefLabs.make(r, withIntraop: true, now: Date()).caption)
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
