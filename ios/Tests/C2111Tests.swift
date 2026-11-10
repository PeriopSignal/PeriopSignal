import XCTest
import UIKit
import SwiftUI
@testable import PeriopSignal

/// 1.11 helper C2 (P1-7, P1-9, P1-10 items 4–8, P1-11; Ben's Q18 and Q19): the three add looks, the empty-state diet, say
/// it once, and the Airway Examination card with Exam normal and the Mallampati class on it.
final class C2111Tests: XCTestCase {

    // MARK: P1-10 (4), Q18: the airway card's lines are findings

    func testAirwayCardShortensMallampatiAndMaskLinesToTheFinding() {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = 96
        r.problems = ["osa"]
        r.mallampati = 3
        r.airwaySigns = ["neck40", "thick-neck"]
        r.dentition = "Upper partial denture, removed"
        r.currentAirway = "natural"; r.oxygen = PatientOxygen(device: "ra")
        let card = PatientSummary.airwayCardLines(r)
        let page = PatientSummary.airwayLines(r)
        XCTAssertEqual(card.count, page.count, "every line stays, shortened")
        XCTAssertTrue(card.contains { $0.text == "Mallampati III" && $0.alert }, card.map(\.text).joined(separator: " | "))
        XCTAssertFalse(card.contains { $0.text.contains("base of the uvula") }, "the definition stays on the page")
        XCTAssertTrue(page.contains { $0.text == "Mallampati III: soft palate and the base of the uvula visible" }, "the page and the brief keep it")
        XCTAssertTrue(card.contains { $0.text == "Difficult mask ventilation: 2 of 5 predictors" && $0.alert }, card.map(\.text).joined(separator: " | "))
        XCTAssertTrue(card.contains { $0.text == "Impossible mask ventilation: 3 of 5 predictors" && $0.alert })
        XCTAssertFalse(card.contains { $0.text.contains("Langeron") || $0.text.contains("Kheterpal") }, "the names stay on the page")
        XCTAssertTrue(page.contains { $0.text.contains("Langeron") } && page.contains { $0.text.contains("Kheterpal") })
        // The other lines are unchanged (teeth, the current airway), and only the findings are red.
        XCTAssertTrue(card.contains { $0.label == "Teeth" && $0.text == "Upper partial denture, removed" && !$0.alert })
        XCTAssertTrue(card.contains { $0.label == "Current airway" && !$0.alert })
    }

    func testMallampatiTwoIsNotAnAlertOnTheCardAndMaskShortFormOnlyForMaskLines() {
        var r = PatientRecord()
        r.mallampati = 2
        let card = PatientSummary.airwayCardLines(r)
        XCTAssertEqual(card.map(\.text), ["Mallampati II"])
        XCTAssertFalse(card[0].alert)
        XCTAssertEqual(PatientSummary.maskRiskShort("Difficult mask ventilation: 3 of 5 Langeron predictors (age over 55, BMI over 26, snoring); 2 or more predicted it."),
                       "Difficult mask ventilation: 3 of 5 predictors")
        XCTAssertNil(PatientSummary.maskRiskShort("Teeth intact"))
        XCTAssertNil(PatientSummary.maskRiskShort("Mallampati III: soft palate and the base of the uvula visible"))
    }

    // MARK: P1-11: Exam normal and the class on the card

    func testClassChipsAreOneToFourAndATapSetsOrClearsTheClass() {
        XCTAssertEqual(PreopAirwayCard.classChips.map(\.id), ["1", "2", "3", "4"])
        XCTAssertEqual(PreopAirwayCard.classChips.map(\.label), ["I", "II", "III", "IV"])
        var r = PatientRecord()
        PreopAirwayCard.tapClass("3", &r)
        XCTAssertEqual(r.mallampati, 3)
        PreopAirwayCard.tapClass("3", &r)
        XCTAssertNil(r.mallampati, "a second tap clears it")
        PreopAirwayCard.tapClass("x", &r)
        XCTAssertNil(r.mallampati)
    }

    func testAClassAfterExamNormalLeavesThePresetUnappliedAndTheRestOfTheExamRecorded() {
        var r = PatientRecord()
        PatientAirway.applyNormalExam(&r)
        XCTAssertTrue(PatientAirway.isNormalExam(r))
        PreopAirwayCard.tapClass("3", &r)
        XCTAssertFalse(PatientAirway.isNormalExam(r), "the record never contradicts itself")
        XCTAssertEqual(r.mallampati, 3)
        XCTAssertEqual(r.dentition, PatientAirway.intactTeeth, "the teeth and the reviewed signs stay as recorded")
        XCTAssertTrue(r.airwayExamReviewed)
        PreopAirwayCard.tapClass("2", &r)
        XCTAssertTrue(PatientAirway.isNormalExam(r), "class II again reads as the normal exam")
    }

    // MARK: P1-10 (6): the airway at handoff is said once

    func testAtHandoffLineMovedFromTheEventsPartToTheAirwayPartAndTheHandoffIsUnchanged() {
        // Arrived with a tube: the airway part says how it leaves; the events part no longer does.
        var tube = PatientRecord()
        tube.currentAirway = "ett"; tube.ettSize = "7.5"; tube.ettDepth = "23 cm at the lip"
        tube.airwayAtEnd = "intubated"
        XCTAssertTrue(tube.arrivesWithAirway)
        XCTAssertTrue(PatientSummary.intraopPartLines(tube, "airway").contains { $0.label == "At handoff" && $0.text == "Remains intubated" })
        XCTAssertFalse(PatientSummary.intraopPartLines(tube, "events").contains { $0.label == "At handoff" })
        // A course recorded: the course sentence carries it, so the airway part does not add a second line.
        var course = PatientRecord()
        course.mask = "easy"; course.intubation = "easy"; course.airwayAtEnd = "extubated"
        let airway = PatientSummary.intraopPartLines(course, "airway")
        XCTAssertEqual(airway.count, 1)
        XCTAssertTrue(airway[0].text.hasSuffix("At handoff: extubated."), airway[0].text)
        XCTAssertFalse(PatientSummary.intraopPartLines(course, "events").contains { $0.label == "At handoff" })
        // Only the airway at handoff, no course: the course sentence carries it, and the airway part says it once.
        var only = PatientRecord()
        only.airwayAtEnd = "sga"
        XCTAssertEqual(PatientSummary.intraopPartLines(only, "airway").map(\.text), ["At handoff: supraglottic airway in."])
        XCTAssertTrue(PatientSummary.intraopPartLines(only, "events").isEmpty)
        XCTAssertEqual(PatientSummary.atHandoffText("extubated"), "Extubated")
        XCTAssertEqual(PatientSummary.atHandoffText("intubated"), "Remains intubated")
        // The handoff text is what it was: the course with "At handoff" in the Airway section.
        let text = HandoffWriter.text(course)
        XCTAssertTrue(text.contains("Course: Mask ventilation easy. Intubation easy. At handoff: extubated."), text)
        XCTAssertTrue(PatientSummary.intraopLines(course).contains { $0.label == "Airway" && $0.text.hasSuffix("At handoff: extubated.") })
    }

    // MARK: P1-10 (5): limb alerts once on the intraop lines card

    func testIntraopLinesCardSaysALimbAlertOnceThroughTheFigure() {
        let r = PatientDemo.add111
        XCTAssertFalse(PatientSummary.limbAlertLines(r).isEmpty, "the demo has limb alerts")
        let s = IntraopDevicesCard.sections(r)
        XCTAssertFalse(s.aboveFigure.contains { $0.label == "Limb alert" }, "no red text line above the figure")
        XCTAssertFalse(s.belowFigure.contains { $0.label == "Limb alert" })
        XCTAssertEqual(IntraopDevicesCard.lines(r).first?.label, "Limb alert", "the card's lines (for the handoff) still lead with it")
        XCTAssertTrue(IntraopDevicesCard.hasContent(r))
        // The figure lists them above itself, once, as the Preoperative card does.
        let card = PatientDiagramCard(record: r, phase: .all, height: 260, limbAlertsAbove: true)
        XCTAssertEqual(card.parts, [.limbAlerts, .figure])
        XCTAssertEqual(PatientDeviceFills.limbAlertGroups(r).count, 2, "the fistula arm and the typed alert")
        XCTAssertFalse(IntraopDevicesCard.hasContent(PatientRecord()), "an empty record shows the hint")
    }

    // MARK: P1-10 (8): link rows truncate to two lines, alerts never

    func testLinkRowLinesTruncateToTwoLinesExceptAlerts() {
        XCTAssertEqual(IntraopLinkRow.lineLimit(PatientSummary.Line("Pre-bypass", "LV EF 60%, normal, dilated; RV function normal")), 2)
        XCTAssertNil(IntraopLinkRow.lineLimit(PatientSummary.Line(nil, "Difficult airway; Massive transfusion", alert: true)), "an alert is never cut")
        XCTAssertNil(IntraopLinkRow.lineLimit(PatientSummary.Line("Last labs", "pH 7.29 L · PaCO₂ 41 · K 5.4 H", marks: ["pH 7.29 L", "K 5.4 H"])), "nor is a line with an abnormal value")
        let echo = PatientSummary.intraopPartLines(PatientDemo.echo110, "echo")
        XCTAssertGreaterThanOrEqual(echo.count, 2, "the pre- and post-bypass exams")
        XCTAssertTrue(echo.allSatisfy { IntraopLinkRow.lineLimit($0) == 2 })
        let considerations = PatientSummary.intraopPartLines(PatientDemo.record, "considerations")
        XCTAssertFalse(considerations.isEmpty)
        XCTAssertTrue(considerations.allSatisfy { IntraopLinkRow.lineLimit($0) == nil })
    }

    // MARK: P1-9: one-phrase hints that fit one line

    func testEmptyHintsAreOnePhraseThatFitsOneLineAt375() {
        let font = UIFont.systemFont(ofSize: PreopEmptyHints.hintFontSize)
        func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
        XCTAssertEqual(Set(PreopEmptyHints.intraop.keys), ["meds", "echo", "labs", "regional", "events", "considerations"])
        for (part, hint) in PreopEmptyHints.intraop {
            XCTAssertLessThanOrEqual(width(hint), PreopEmptyHints.hintRoomAt375, "\(part): \(hint) runs to a second line at 375 pt")
            XCTAssertFalse(hint.hasSuffix("."), "a phrase, not a sentence: \(hint)")
        }
        let cardFont = UIFont.systemFont(ofSize: 13.5)
        for hint in [PreopEmptyHints.airway, PreopEmptyHints.lines, PreopEmptyHints.intraopLines] {
            XCTAssertLessThanOrEqual((hint as NSString).size(withAttributes: [.font: cardFont]).width, 375 - 40 - 32, hint)
            XCTAssertFalse(hint.hasSuffix("."))
        }
        XCTAssertEqual(PreopEmptyHints.airway, "Mallampati, difficult-airway signs, teeth")
        XCTAssertEqual(PreopEmptyHints.lines, "Lines and devices on arrival")
    }

    func testCaseTimersRowHasAScrollIdForTheShotThatShowsItsRunningTimers() {
        // The row is the last on the tab; the shot reaches it by its id (-ps.patient.scroll casetimers), not by the
        // section header, whose top-anchored scroll left the row under the tab bar.
        XCTAssertEqual(IntraopOtherDetails.caseTimersScrollID, "casetimers")
    }

    func testCaseTimersRowReadsAddWhileNoneRuns() {
        XCTAssertEqual(IntraopOtherDetails.caseTimersTitle(running: 0), "+ Case timers")
        XCTAssertEqual(IntraopOtherDetails.caseTimersTitle(running: 2), "Case timers")
    }

    // MARK: P1-9: the empty tiles, the summary and the flags

    func testEmptyTileIsOneLineAndAFilledTileKeepsItsRoom() {
        XCTAssertLessThan(PreopProblemsBox.emptyTileHeight, PreopProblemsBox.filledTileHeight)
        XCTAssertLessThanOrEqual(PreopProblemsBox.emptyTileHeight, 48)
        XCTAssertEqual(PreopProblemsBox.filledTileHeight, 66, "as in 1.10")
        // The tile's words: empty for a system with nothing recorded (so the tile draws its name only).
        let r = PatientRecord()
        let cv = PatientCatalog.allSystems.first { $0.id == "cv" }!
        XCTAssertEqual(PatientPreop.tileWords(cv, r), "")
        XCTAssertFalse(PatientPreop.tileWords(cv, PatientDemo.record).isEmpty)
    }

    func testPreprocedureSummaryIsOfferedOnlyOnceTheRecordHasAnAgeOrAProcedure() {
        var r = PatientRecord()
        XCTAssertFalse(PreprocedureSummaryView.offersSummary(r), "nothing drawn for an empty record: no disabled button")
        r.allergyList = AllergyCatalog.parse("latex anaphylaxis")
        XCTAssertFalse(PreprocedureSummaryView.offersSummary(r), "an allergy alone is not enough to summarize")
        r.ageYears = 67
        XCTAssertTrue(PreprocedureSummaryView.offersSummary(r))
        var p = PatientRecord()
        p.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        XCTAssertTrue(PreprocedureSummaryView.offersSummary(p))
        var on = PatientRecord()
        on.preopSummaryOn = true
        XCTAssertTrue(PreprocedureSummaryView.offersSummary(on), "a summary already on stays on")
    }

    func testActiveFlagsAreTheRecordsFlagsInCatalogOrderWhetherTypedOrHandSet() {
        var r = PatientDemo.meds
        let fromList = PreopFlaggedBox.activeFlags(r).map(\.id)
        XCTAssertEqual(Set(fromList), r.medFlags)
        XCTAssertTrue(fromList.contains("anticoagulant") && fromList.contains("glp1"), fromList.joined(separator: ","))
        r.medFlags.insert("maoi")
        let withHand = PreopFlaggedBox.activeFlags(r).map(\.id)
        XCTAssertTrue(withHand.contains("maoi"), "a hand-set flag shows too")
        XCTAssertEqual(withHand, PatientCatalog.medFlags.map(\.id).filter { r.medFlags.contains($0) }, "in the catalog's order")
        XCTAssertTrue(PreopFlaggedBox.activeFlags(PatientRecord()).isEmpty)
        // Taking a flag off is the record's own set.
        r.medFlags.remove("maoi")
        XCTAssertFalse(PreopFlaggedBox.activeFlags(r).contains { $0.id == "maoi" })
    }

    // MARK: P1-10 (7): one-line medication rows

    func testMedicationRowFlagsHaveShortWordsAndTheDoseFieldIsNarrower() {
        XCTAssertEqual(HomeMedRowStyle.shortFlag(PatientFlag("glp1", "GLP-1 receptor agonist")), "GLP-1")
        XCTAssertEqual(HomeMedRowStyle.shortFlag(PatientFlag("acei", "ACE inhibitor or ARB")), "ACEi/ARB")
        XCTAssertEqual(HomeMedRowStyle.shortFlag(PatientFlag("aspirin", "Aspirin")), "Aspirin", "a short label keeps its words")
        for f in PatientCatalog.medFlags {
            XCTAssertLessThanOrEqual(HomeMedRowStyle.shortFlag(f).count, 10, f.id)
        }
        XCTAssertLessThan(HomeMedRowStyle.doseWidth, 128, "1.9's dose field")
        // The name, a flag pill and the dose field share one line at 375 pt: the pill keeps its words and the dose its
        // field, so with the widest pill, the dose field, × and the spacing, at least 85 pt is left for the name (a
        // typical name fits whole; a longer one is never shrunk or cut: its pill goes under it, HomeMedRow), and the
        // longest demo dose fits its field.
        let name = UIFont.systemFont(ofSize: 14.5, weight: .semibold)
        let pill = UIFont.systemFont(ofSize: 10.5, weight: .semibold)
        let dose = UIFont.systemFont(ofSize: HomeMedRowStyle.doseFontSize)
        let widestPill = PatientCatalog.medFlags.map { (HomeMedRowStyle.shortFlag($0) as NSString).size(withAttributes: [.font: pill]).width + 12 }.max() ?? 0
        let room: CGFloat = 375 - 40 - 28
        let nameRoom = room - (8 + widestPill + 8 + HomeMedRowStyle.doseWidth + 8 + 28)
        XCTAssertGreaterThanOrEqual(nameRoom, 85, "pill \(widestPill)")
        let typical = ("Lisinopril" as NSString).size(withAttributes: [.font: name]).width
        XCTAssertLessThanOrEqual(typical, nameRoom)
        let longestDose = PatientDemo.meds.homeMeds.map { ($0.dose as NSString).size(withAttributes: [.font: dose]).width }.max() ?? 0
        XCTAssertLessThanOrEqual(longestDose + 16, HomeMedRowStyle.doseWidth, "longest dose \(longestDose)")
    }

    // MARK: P1-7: the quiet link and the allergies type line

    func testQuietLinkAndValueRowBuild() {
        // The views build with their words (a smoke test of the grammar's two forms).
        _ = PreopQuietLink(title: "Other conditions") {}
        _ = PreopQuietValueRow(title: "Urgency", value: "Elective") {}
        _ = PreopHideButton {}
        XCTAssertEqual(PreopEmptyHints.caseTimersNone, "+ Case timers")
    }

    func testAllergiesTypeLineFilesAnAllergyAndTakesNkdaOff() {
        // The type line is always there: a line typed with No known allergies on files the allergy and clears NKDA, as
        // the box's file() does.
        var r = PatientRecord()
        r.nkda = true
        let items = AllergyCatalog.reading("PCN - rash").map(\.allergy)
        XCTAssertFalse(items.isEmpty)
        AllergyCatalog.apply(items, to: &r.allergyList)
        r.nkda = false
        XCTAssertEqual(r.allergyList.count, 1)
        XCTAssertFalse(r.nkda)
        XCTAssertEqual(AllergiesBox.placeholder, "e.g. PCN - rash, latex anaphylaxis")
    }

    // MARK: Saved records keep decoding

    func testA110RecordDecodesWithTheFieldsTheseViewsRead() throws {
        // A 1.10 record (fields as 1.10 wrote them): the airway exam, the flags, the medication list, a limb alert, the
        // airway at the end, the summary switch. Nothing C2 touched changed the model; this guards the views' reads.
        let json = """
        {"version":1,"ageYears":67,"sex":"male","mallampati":3,"airwaySigns":["neck40","thick-neck"],"dentition":"Upper partial denture, removed",
         "airwayExamReviewed":false,"medFlags":["anticoagulant","insulin"],"homeMeds":[{"id":"7E9D4C2A-1B3F-4D5E-8F6A-0B1C2D3E4F5A","name":"apixaban","dose":"5 mg bid"}],
         "limbAlerts":[{"id":"8E9D4C2A-1B3F-4D5E-8F6A-0B1C2D3E4F5B","limb":"arm-right","reason":"Lymphedema"}],
         "airwayAtEnd":"extubated","mask":"easy","intubation":"easy","preopSummaryOn":false,"nkda":false,
         "allergyList":[{"id":"9E9D4C2A-1B3F-4D5E-8F6A-0B1C2D3E4F5C","name":"penicillin","severity":"mild","reaction":"rash"}]}
        """
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.mallampati, 3)
        XCTAssertEqual(PreopFlaggedBox.activeFlags(r).map(\.id), ["anticoagulant", "insulin"])
        XCTAssertEqual(r.homeMeds.first?.name, "apixaban")
        XCTAssertEqual(r.limbAlerts.first?.limb, "arm-right")
        XCTAssertTrue(PatientSummary.airwayCardLines(r).contains { $0.text == "Mallampati III" })
        XCTAssertTrue(PatientSummary.intraopPartLines(r, "airway").first?.text.hasSuffix("At handoff: extubated.") ?? false)
        XCTAssertTrue(PreprocedureSummaryView.offersSummary(r))
        XCTAssertEqual(r.allergyList.first?.severity, "mild")
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again.mallampati, 3)
        XCTAssertEqual(again.limbAlerts.count, 1)
    }

    // MARK: The demo patient and its screenshots

    @MainActor func testTheAdd111DemoHasWhatItsShotsShow() {
        let r = PatientDemo.add111
        XCTAssertEqual(r.homeMeds.count, 7, "seven one-line medication rows")
        XCTAssertEqual(r.allergyList.count, 3)
        XCTAssertFalse(PreopFlaggedBox.activeFlags(r).isEmpty)
        XCTAssertEqual(r.mallampati, 3)
        XCTAssertTrue(PatientSummary.airwayCardLines(r).contains { $0.text == "Impossible mask ventilation: 3 of 5 predictors" })
        XCTAssertTrue(r.devices.contains { $0.kind == .avFistula && !$0.placedIntraop })
        XCTAssertEqual(PatientDeviceFills.limbAlertGroups(r).map(\.limb), ["arm-left", "arm-right"])
        // Nothing is left in a limb the card warns about: the base demo's left forearm cannula and right radial A-line are
        // not carried into the fistula arm or the alerted one (shot 818 listed "PIV 18 G L forearm" beside "AV fistula
        // L forearm").
        XCTAssertFalse(PatientDemo.meds.devices.filter { PatientDemo.limb(of: $0) != nil }.isEmpty, "the base demo has limb lines to drop")
        let alerted = Set(PatientDeviceFills.limbAlerts(r).map(\.limb))
        for d in r.devices where d.kind != .avFistula {
            if let limb = PatientDemo.limb(of: d) { XCTAssertFalse(alerted.contains(limb), "\(d.kind) at \(d.site) sits in an alerted limb") }
        }
        XCTAssertEqual(PatientDemo.limb(of: PatientDevices.parse("PIV 18 G L forearm")!.device()), "arm-left")
        XCTAssertEqual(PatientStore.debugSeed("demo-add111")?.homeMeds.count, 7, "registered in the demo switch")
    }
}
