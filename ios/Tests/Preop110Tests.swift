import XCTest
import UIKit
@testable import PeriopSignal

/// 1.10 Preprocedure tab (Ben, Nov 7 chat): the code-status chips (DNR and DNI both selectable, no DNR/DNI chip), the second tap
/// that clears a Yes / No answer, the compact chip labels, the single-line chip rows at 375 and 393 pt, and the risk-score
/// inputs link's line.
final class Preop110Tests: XCTestCase {

    // MARK: Code status chips

    func testThereIsNoDnrDniChipAndDnrAndDniAreTwoChips() {
        XCTAssertEqual(CodeStatus.chips.map(\.id), ["full", "dnr", "dni", "limited", "notDiscussed"])
        XCTAssertFalse(CodeStatus.chips.contains { $0.label == "DNR/DNI" })
        XCTAssertEqual(CodeStatus.chips.map(\.label), ["Full code", "DNR", "DNI", "Limited", "Not discussed"])
    }

    func testDnrThenDniIsBothAndEitherCanComeOff() {
        var s: CodeStatus?
        s = CodeStatus.tapped("dnr", from: s)
        XCTAssertEqual(s, .dnr)
        s = CodeStatus.tapped("dni", from: s)
        XCTAssertEqual(s, .dnrDni, "both selected")
        XCTAssertEqual(s?.chipIDs, ["dnr", "dni"])
        s = CodeStatus.tapped("dnr", from: s)
        XCTAssertEqual(s, .dni, "DNR off leaves DNI")
        s = CodeStatus.tapped("dni", from: s)
        XCTAssertNil(s, "the last one off clears the status")
        s = CodeStatus.tapped("dni", from: s)
        s = CodeStatus.tapped("dnr", from: s)
        XCTAssertEqual(s, .dnrDni, "in either order")
        s = CodeStatus.tapped("dni", from: s)
        s = CodeStatus.tapped("dnr", from: s)
        XCTAssertNil(s)
    }

    func testFullCodeLimitedAndNotDiscussedStayExclusive() {
        for chip in ["full", "limited", "notDiscussed"] {
            let status = CodeStatus(rawValue: chip)
            XCTAssertEqual(CodeStatus.tapped(chip, from: nil), status)
            XCTAssertNil(CodeStatus.tapped(chip, from: status), "a second tap clears \(chip)")
            XCTAssertEqual(CodeStatus.tapped(chip, from: .dnrDni), status, "\(chip) replaces both orders")
            XCTAssertEqual(CodeStatus.tapped(chip, from: .dnr), status)
        }
        XCTAssertEqual(CodeStatus.tapped("dnr", from: .full), .dnr, "DNR replaces Full code")
        XCTAssertEqual(CodeStatus.tapped("dni", from: .limited), .dni, "DNI replaces Limited")
        XCTAssertEqual(CodeStatus.tapped("dni", from: .notDiscussed), .dni)
        XCTAssertEqual(CodeStatus.full.chipIDs, ["full"])
        XCTAssertEqual(CodeStatus.notDiscussed.chipIDs, ["notDiscussed"])
        XCTAssertEqual(CodeStatus.limited.chipIDs, ["limited"])
    }

    func testOrdersOfTheTwoSwitches() {
        XCTAssertEqual(CodeStatus.orders(dnr: true, dni: true), .dnrDni)
        XCTAssertEqual(CodeStatus.orders(dnr: true, dni: false), .dnr)
        XCTAssertEqual(CodeStatus.orders(dnr: false, dni: true), .dni)
        XCTAssertNil(CodeStatus.orders(dnr: false, dni: false))
        XCTAssertTrue(CodeStatus.dnrDni.hasDNR && CodeStatus.dnrDni.hasDNI)
        XCTAssertTrue(CodeStatus.dnr.hasDNR && !CodeStatus.dnr.hasDNI)
        XCTAssertFalse(CodeStatus.full.hasDNR || CodeStatus.limited.hasDNI)
    }

    /// A record saved with the old DNR/DNI chip loads as both DNR and DNI: both chips on, and the summary, the handoff and the
    /// plan link read it as both orders.
    func testSavedDnrDniReadsAsBothEverywhere() throws {
        let json = #"{"codeStatus":"dnrDni","codeStatusPlan":"modified","codeStatusPlanNote":"accepts intubation","polst":true}"#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.codeStatus, .dnrDni)
        XCTAssertEqual(r.codeStatus?.chipIDs, ["dnr", "dni"], "both chips on")
        let text = try XCTUnwrap(PatientCodeStatus.text(r))
        XCTAssertTrue(text.hasPrefix("DNR/DNI"), text)
        XCTAssertTrue(text.contains("modified for the procedure: accepts intubation"), text)
        let handoff = PatientBriefs.handoff(r)
        XCTAssertTrue(handoff.contains { $0.key == "code" && $0.text.contains("DNR/DNI") && $0.alert })
        let link = PatientPreop.codeStatusLink(r)
        XCTAssertEqual(link.text, "Plan: Modified for the procedure · POLST on file")
        XCTAssertFalse(link.alert)
        // The same record round-trips.
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again.codeStatus, .dnrDni)
    }

    /// The perioperative plan is asked for every combination that limits resuscitation, and for none that does not.
    func testPlanIsAskedForEveryOrderCombination() {
        for s in [CodeStatus.dnr, .dni, .dnrDni, .limited] {
            var r = PatientRecord(); r.codeStatus = s
            XCTAssertTrue(s.limits, "\(s)")
            XCTAssertTrue(PatientCodeStatus.text(r)?.hasSuffix("perioperative plan not yet discussed") ?? false, "\(s)")
            XCTAssertEqual(PatientPreop.codeStatusLink(r).text, "Perioperative plan not yet discussed")
            XCTAssertTrue(PatientPreop.codeStatusLink(r).alert)
            r.codeStatusPlan = .suspended
            XCTAssertTrue(PatientCodeStatus.text(r)?.contains("suspended for the procedure; when the orders resume: not recorded") ?? false)
        }
        for s in [CodeStatus.full, .notDiscussed] {
            var r = PatientRecord(); r.codeStatus = s
            XCTAssertFalse(s.limits)
            XCTAssertEqual(PatientCodeStatus.text(r), s.label)
            XCTAssertEqual(PatientPreop.codeStatusLink(r).text, "Plan details & POLST")
        }
        // Tapping DNR then DNI keeps the plan chosen.
        var r = PatientRecord(); r.codeStatus = .dnr; r.codeStatusPlan = .maintained
        r.codeStatus = CodeStatus.tapped("dni", from: r.codeStatus)
        XCTAssertEqual(r.codeStatus, .dnrDni)
        XCTAssertEqual(r.codeStatusPlan, .maintained)
        XCTAssertEqual(PatientPreop.codeStatusLink(r).text, "Plan: Maintained as is")
    }

    // MARK: Second tap clears

    func testSecondTapOnYesOrNoClears() {
        XCTAssertEqual(PatientPreop110.tapped(true, from: nil), true)
        XCTAssertNil(PatientPreop110.tapped(true, from: true))
        XCTAssertEqual(PatientPreop110.tapped(true, from: false), true, "Yes replaces No")
        XCTAssertEqual(PatientPreop110.tapped(false, from: true), false)
        XCTAssertNil(PatientPreop110.tapped(false, from: false))
    }

    func testCardiacSymptomRowsClearOnASecondTap() {
        var answer: Bool?
        var chips: Set<String> = []
        PatientPreop110.tapYesNo(true, answer: &answer, chips: &chips)
        XCTAssertEqual(answer, true)
        chips = ["chest-pain"]
        PatientPreop110.tapYesNo(false, answer: &answer, chips: &chips)
        XCTAssertEqual(answer, false, "No replaces Yes and clears the chips")
        XCTAssertTrue(chips.isEmpty)
        PatientPreop110.tapYesNo(false, answer: &answer, chips: &chips)
        XCTAssertNil(answer, "a second tap on No clears")
        PatientPreop110.tapYesNo(true, answer: &answer, chips: &chips)
        PatientPreop110.tapYesNo(true, answer: &answer, chips: &chips)
        XCTAssertNil(answer, "a second tap on Yes clears")
        // Yes shown only because a chip is picked (no answer recorded): a tap on Yes clears the chips and the answer.
        answer = nil; chips = ["dyspnea"]
        PatientPreop110.tapYesNo(true, answer: &answer, chips: &chips)
        XCTAssertNil(answer)
        XCTAssertTrue(chips.isEmpty)
    }

    func testTheRecordKeyPathFormClearsToo() {
        var r = PatientRecord()
        r.cardiacSymptoms = ["chest-pain"]
        PatientPreop110.tapYesNo(true, answer: \.cardiacSymptomsAnswer, chips: \.cardiacSymptoms, in: &r)
        XCTAssertNil(r.cardiacSymptomsAnswer)
        XCTAssertTrue(r.cardiacSymptoms.isEmpty)
    }

    func testIntrathoracicClearsToUnanswered() {
        var r = PatientRecord()
        PatientPreop.setIntrathoracic(true, &r)
        XCTAssertEqual(r.intrathoracicProcedure, true)
        PatientPreop.setIntrathoracic(nil, &r)
        XCTAssertNil(r.intrathoracicProcedure, "what Yes set stays: it is the clinician's to change")
    }

    // MARK: Compact labels

    func testShortLabelsKeepFullWordsForVoiceOver() {
        XCTAssertEqual(PatientPreop110.mets.map(\.shown), ["≥4 METs", "<4 METs", "Unknown"])
        XCTAssertEqual(PatientPreop110.mets.map(\.label), ["4 METs or more", "Under 4 METs", "Unknown"])
        XCTAssertEqual(PatientPreop110.mets.map(\.id), ["ge4", "lt4", "unknown"], "the stored ids do not change")
        XCTAssertEqual(PatientPreop110.anesthetics.map(\.shown), ["GA", "MAC", "PNB", "Neuraxial"])
        XCTAssertEqual(PatientPreop110.anesthetics.map(\.label), ["General", "Sedation (MAC)", "Peripheral nerve block", "Neuraxial"])
        XCTAssertEqual(Set(PatientPreop110.anesthetics.map(\.id)), Set(PatientCatalog.anesthetics.map(\.id)), "the catalog's ids")
        XCTAssertEqual(PatientPreop110.incisions.map(\.shown), ["Peripheral", "Upper abd", "Intrathoracic"])
        XCTAssertEqual(PatientPreop110.incisions.map(\.id), ["Peripheral", "Upper abdominal", "Intrathoracic"])
        XCTAssertEqual(PatientPreop110.durations.map(\.id), ProcedureCatalog.durations)
        XCTAssertEqual(CodeStatus.chips.first?.short, "Full")
        XCTAssertEqual(CodeStatus.chips.first?.label, "Full code")
    }

    // MARK: Single-line rows

    /// The width of a chip row inside a group on a phone: the page's 20-pt margins and the row's 14.
    private func rowWidth(_ screen: CGFloat) -> CGFloat { screen - 40 - 28 }

    private func fit(_ options: [ChipChoice], choice: Bool, screen: CGFloat) -> String {
        guard let f = ChipMetrics.lineFit(options, choice: choice, in: rowWidth(screen)) else {
            var w: [Int] = []
            for o in ChipMetrics.order {
                let labels = options.map { o.short ? $0.shown : $0.label }
                w.append(Int(ChipMetrics.width(labels, density: o.density, choice: choice)))
            }
            return "wraps (one-line widths \(w) for \(Int(rowWidth(screen))))"
        }
        return (f.short ? "short" : "full") + "/" + "\(f.density)"
    }

    private func assertOneLine(_ name: String, _ options: [ChipChoice], choice: Bool, screens: [CGFloat], file: StaticString = #filePath, line: UInt = #line) {
        for screen in screens {
            XCTAssertNotNil(ChipMetrics.lineFit(options, choice: choice, in: rowWidth(screen)), "\(name) on one line at \(screen) pt: \(fit(options, choice: choice, screen: screen))", file: file, line: line)
        }
    }

    func testRowsThatFitGoOnOneLineOnTheNarrowestPhones() {
        let urgency = PatientUrgency.allCases.map { ChipChoice($0.rawValue, $0.label) }
        let code = CodeStatus.chips.map { ChipChoice($0.id, $0.label, short: $0.short) }
        assertOneLine("functional capacity", PatientPreop110.mets, choice: true, screens: [375, 393, 402])
        assertOneLine("planned anesthetic", PatientPreop110.anesthetics, choice: false, screens: [375, 393, 402])
        assertOneLine("incision", PatientPreop110.incisions, choice: true, screens: [375, 393, 402])
        assertOneLine("duration", PatientPreop110.durations, choice: true, screens: [375, 393, 402])
        assertOneLine("sex", PatientPreop110.sexes, choice: true, screens: [375, 393, 402])
        assertOneLine("urgency", urgency, choice: true, screens: [402])
        assertOneLine("code status", code, choice: true, screens: [402])
        // Reported, not asserted: where the two long rows land (the report says which phones they fit).
        print("urgency 375:", fit(urgency, choice: true, screen: 375), "| 393:", fit(urgency, choice: true, screen: 393), "| 402:", fit(urgency, choice: true, screen: 402))
        print("code status 375:", fit(code, choice: true, screen: 375), "| 393:", fit(code, choice: true, screen: 393), "| 402:", fit(code, choice: true, screen: 402))
    }

    /// At a larger in-app text size the rows that no longer fit wrap, and the font is never shrunk.
    func testLargeTextFallsBackToWrapping() {
        let saved = PS.textScale
        defer { PS.textScale = saved }
        PS.textScale = 1.25
        XCTAssertEqual(ChipMetrics.fontSize, 16.9, accuracy: 0.05, "the font follows the in-app text size, never below it")
        let urgency = PatientUrgency.allCases.map { ChipChoice($0.rawValue, $0.label) }
        XCTAssertNil(ChipMetrics.lineFit(urgency, choice: true, in: rowWidth(393)), "urgency wraps at the large text size")
        XCTAssertNil(ChipMetrics.lineFit(CodeStatus.chips.map { ChipChoice($0.id, $0.label, short: $0.short) }, choice: true, in: rowWidth(393)))
    }

    // MARK: Risk-score inputs link

    func testRiskInputsLineIsEmptyUntilAnyIsFilled() {
        var r = PatientRecord()
        XCTAssertNil(PatientPreop110.riskInputsLine(r))
        r.incision = "Upper abdominal"
        XCTAssertEqual(PatientPreop110.riskInputsLine(r), "Upper abdominal incision")
        r.highRiskSurgery = true
        r.duration = "> 2–3 h"
        XCTAssertEqual(PatientPreop110.riskInputsLine(r), "High-risk surgery · Upper abdominal incision · Over 2 to 3 h")
        r.duration = "> 3 h"
        XCTAssertEqual(PatientPreop110.riskInputsLine(r), "High-risk surgery · Upper abdominal incision · Over 3 h")
    }

    func testIntrathoracicYesFillsTheLink() {
        var r = PatientRecord()
        PatientPreop.setIntrathoracic(true, &r)
        XCTAssertEqual(PatientPreop110.riskInputsLine(r), "High-risk surgery · Intrathoracic incision")
    }

    func testBoxKeysAreDistinctFromTheSections() {
        for s in PreopSection.allCases {
            XCTAssertNotEqual(PatientJumpID(section: s), PatientJumpID(anchor: PatientPreop110.riskInputsAnchor))
        }
    }
}
