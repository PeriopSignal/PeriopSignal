import XCTest
import CoreGraphics
@testable import PeriopSignal

/// 1.10 screenshot review fixes (the Preoperative and Intraoperative shots): the lines figure's ETT tag keeps the tube's
/// depth, the spelled-out AVR with supracoronary ascending aorta replacement is one procedure, an intubated arrival is
/// not offered "Never instrumented", one cardiac-surgery line on the Cardiopulmonary Evaluation, urgency's full words on
/// one line at 375 pt, the intraop demo's lines and Hb, and the screenshot open key watched for the whole shot.
final class Review110ShotsTests_preop: XCTestCase {

    // MARK: 562: the ETT tag from the typed Tube field

    func testTubeWithItsDepthInParenthesesKeepsTheDepthInTheTag() {
        XCTAssertEqual(PatientDiagramModel.ettLabel(tube: "8.0 cuffed ETT (23 cm)"), "ETT 8.0 @23")
        XCTAssertEqual(PatientDiagramModel.ettLabel(tube: "7.5 ETT, 23 cm at the lip"), "ETT 7.5 @23")
        XCTAssertEqual(PatientDiagramModel.ettLabel(tube: "ETT 7.0 at 21cm"), "ETT 7.0 @21")
        XCTAssertEqual(PatientDiagramModel.ettLabel(tube: "DLT 37 Fr L"), "DLT 37")
        XCTAssertEqual(PatientDiagramModel.ettLabel(tube: "(22 cm)"), "ETT @22")
        XCTAssertEqual(PatientDiagramModel.ettLabel(tube: "reinforced"), "reinforced")
    }

    func testIntraopDemoAirwayTagFitsTheColumnUncut() throws {
        let items = PatientDiagramModel.items(PatientDemo.intraop110, phase: .intraop).items
        let ett = try XCTUnwrap(items.first { $0.id == "airway-ett" })
        XCTAssertEqual(ett.label, "ETT 8.0 @23")
        XCTAssertFalse(ett.label.hasSuffix("…"))
        XCTAssertLessThanOrEqual(ett.label.count, 15)
    }

    func testAnLMASizeInTheTubeFieldStillReadsAsTyped() {
        var r = PatientRecord()
        r.airwayDevice = "Supraglottic airway"
        r.tube = "LMA 4"
        XCTAssertTrue(PatientAirway.tubeIsLMA(r))
        let item = PatientDiagramModel.items(r, phase: .intraop).items.first { $0.id == "airway-ett" }
        if let item { XCTAssertEqual(item.label, "LMA 4") }
    }

    // MARK: 575, 576: AVR with supracoronary ascending aorta replacement

    func testSpelledOutAVRWithSupracoronaryAortaIsOneProcedure() throws {
        for text in ["Aortic valve replacement and supracoronary ascending aorta replacement",
                     "aortic valve replacement with supracoronary ascending aorta replacement",
                     "AVR and supracoronary ascending aorta replacement"] {
            let p = PlannedProcedure.parse(text)
            XCTAssertEqual(p.count, 1, "\(text): \(p.map(\.text))")
            XCTAssertEqual(p.first?.catalog?.id, "wheat", text)
            XCTAssertEqual(p.first?.detail, "", "\(text): no \"supracoronary\" left as the AVR's detail")
        }
        let demo = PatientDemo.intraop110
        XCTAssertEqual(demo.procedures.count, 1)
        XCTAssertFalse(demo.procedures.map(\.text).joined().lowercased().contains("replacement supracoronary"))
    }

    // MARK: 578: an intubated arrival is not offered "Never instrumented"

    func testArrivalWithATubeIsNotOfferedNeverInstrumented() {
        var r = PatientRecord()
        r.currentAirway = "ett"
        XCTAssertEqual(PatientCatalog.airwayAtEndChoices(r).map(\.id), ["extubated", "intubated", "sga"])
        r.currentAirway = "trach"
        XCTAssertFalse(PatientCatalog.airwayAtEndChoices(r).map(\.id).contains("natural"))
        // A saved older value keeps showing.
        r.airwayAtEnd = "natural"
        XCTAssertTrue(PatientCatalog.airwayAtEndChoices(r).map(\.id).contains("natural"))
        // Others keep every choice.
        var natural = PatientRecord()
        natural.currentAirway = "natural"
        XCTAssertEqual(PatientCatalog.airwayAtEndChoices(natural).map(\.id), PatientCatalog.airwayAtEnd.map(\.id))
    }

    // MARK: 590: one quiet cardiac-surgery line

    func testAdultCardiacSurgeryHasOneCardiacSurgeryLine() {
        var r = PatientRecord()
        r.ageYears = 68
        r.setProcedures(PlannedProcedure.parse("AVR with supracoronary ascending aorta replacement"))
        PatientPreop.setIntrathoracic(true, &r)
        XCTAssertTrue(PatientRules.cardiacSurgery(r))
        XCTAssertNil(PatientPreop.intrathoracicRcriNote(r), "the card's cardiac-surgery line already says the RCRI is not shown")
        // The one line the card keeps (PatientCardiacEvaluationContent shows it for an adult's cardiac operation).
        XCTAssertTrue(r.isAdult && !PatientFunctional.stepwiseApplies(r))
        XCTAssertTrue(PatientFunctional.cardiacSurgeryNote.contains("RCRI"))
        // Under 18 the card has no such line, so the RCRI note stays under Yes.
        r.ageYears = 12
        XCTAssertEqual(PatientPreop.intrathoracicRcriNote(r), PatientRules.rcriHiddenNote)
        // Not cardiac surgery, or not Yes: no note.
        r.ageYears = 68
        PatientPreop.setIntrathoracic(nil, &r)
        XCTAssertNil(PatientPreop.intrathoracicRcriNote(r))
    }

    // MARK: 550: urgency's full words on one line at 375 pt

    func testUrgencyFullWordsFitOneLineAt375InThePlannedBox() {
        let saved = PS.textScale
        defer { PS.textScale = saved }
        PS.textScale = 1
        let urgency = PatientUrgency.allCases.map { ChipChoice($0.rawValue, $0.label) }
        XCTAssertTrue(urgency.allSatisfy { $0.shown == $0.label }, "full words, no short labels")
        // The box's row at 375 pt: the page's 20-pt margins, the row's 14-pt inset less the urgency outset.
        let row = 375 - 40 - 2 * (14 - PatientPreop110.urgencyRowOutset)
        let fit = ChipMetrics.lineFit(urgency, choice: true, in: row, compact: true)
        XCTAssertNotNil(fit, "urgency on one line at 375 pt: \(ChipMetrics.width(urgency.map(\.label), density: .compact, choice: true)) for \(row)")
        XCTAssertEqual(fit?.short, false)
        // The font is the chip font, and rows that do not opt in keep their order.
        XCTAssertEqual(ChipMetrics.fontSize, 13.5)
        XCTAssertEqual(ChipMetrics.compactOrder.prefix(ChipMetrics.order.count).map(\.density), ChipMetrics.order.map(\.density))
        XCTAssertFalse(ChipMetrics.order.contains { $0.density == .compact })
        // A larger text size still wraps.
        PS.textScale = 1.25
        XCTAssertNil(ChipMetrics.lineFit(urgency, choice: true, in: row, compact: true))
    }

    // MARK: 562, 567: the intraop demo

    func testIntraopDemoLinesAndHbArePlausible() throws {
        let r = PatientDemo.intraop110
        XCTAssertFalse(r.devices.contains { $0.kind == .pac }, "a SLIC goes through the introducer in place of a PA catheter")
        XCTAssertTrue(r.devices.contains { $0.detail.localizedCaseInsensitiveContains("SLIC") || $0.settings.values.contains { $0.localizedCaseInsensitiveContains("SLIC") } }
                      || PatientDevices.parse("RIJ SLIC 9 Fr") != nil)
        let hb = try XCTUnwrap(r.intraopLabs.compactMap { $0.values["hb"] }.first)
        XCTAssertLessThan(hb, 11, "after bypass and 2 units of PRBC")
        XCTAssertGreaterThan(hb, 7)
    }

    // MARK: 531, 575, 576: the open key is watched for the whole shot

    func testOpenKeyIsWatchedPastTheLongestShotWait() {
        let delays = PatientView.openLookDelays
        XCTAssertEqual(Array(delays.prefix(PatientView.openRetryDelays.count)), PatientView.openRetryDelays)
        XCTAssertGreaterThanOrEqual(delays.reduce(0, +), 24, "looks until past the longest open-key shot's 24 s wait")
        XCTAssertLessThanOrEqual(delays.dropFirst(PatientView.openRetryDelays.count).max() ?? 0, 1.0, "a late write-over is put back within a second")
    }
}
