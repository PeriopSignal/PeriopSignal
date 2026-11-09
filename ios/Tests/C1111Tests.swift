import XCTest
import SwiftUI
@testable import PeriopSignal

/// 1.11, helper C1 (P1-5, P1-6, P1-8; Ben's Q1, Q3, Q7): the jump bar's short labels and the current-section rule, the
/// "My Patient" title menu, the section titles and the caption rule, the box order inside Examination & Workup, the chip
/// grammar (ChipStyle), the ink-filled Yes/No pills, the alert paths in PS.red, and the style gallery.
final class C1111Tests: XCTestCase {

    // MARK: P1-5 — jump bar

    func testJumpChipsReadShortAndKeepTheFullNameForVoiceOver() {
        let preop = PreopSection.allCases.map { PatientJumpItem(section: $0) }
        XCTAssertEqual(preop.map(\.title), ["Procedure", "Demographics", "Exam & Workup", "Medications", "Risk Scores", "Summary"])
        XCTAssertEqual(preop.map(\.fullTitle), ["Planned Procedure & Anesthetic", "Demographics & History", "Examination & Workup",
                                                "Current Medications", "Risk Scores & Checks", "Preprocedure Summary"])
        let intraop = IntraopSection.allCases.map { PatientJumpItem(intraop: $0) }
        XCTAssertEqual(intraop.map(\.title), ["Airway", "Lines", "Meds", "Fluids", "Other"])
        XCTAssertEqual(intraop.map(\.fullTitle), ["Airway Course", "Lines & Devices", "Medications & Infusions", "Fluids & Blood", "Other Intraoperative Details"])
    }

    /// The chip rows measured (an honest fit, as proposed): the five Intraoperative chips come within a phone's width
    /// (375 pt less the 20-pt margins, give or take the last chip's edge), the six Preoperative chips need more than any
    /// phone, so that row scrolls and the filled chip says where you are; both rows are far narrower than with the
    /// full names, and no single chip is wider than a third of the row's room.
    func testJumpRowsAreMeasured() {
        let scale = PS.textScale
        PS.textScale = 1
        defer { PS.textScale = scale }
        let room: CGFloat = 375 - 40
        let intraop = PatientJumpLabels.rowWidth(IntraopSection.allCases.map { PatientJumpLabels.short($0) })
        let intraopFull = PatientJumpLabels.rowWidth(IntraopSection.allCases.map(\.title))
        XCTAssertLessThanOrEqual(intraop, room + 30, "Airway · Lines · Meds · Fluids · Other: \(intraop) pt")
        XCTAssertLessThan(intraop, intraopFull - 100, "the full names ran to \(intraopFull) pt")
        let preop = PatientJumpLabels.rowWidth(PreopSection.allCases.map { PatientJumpLabels.short($0) })
        let preopFull = PatientJumpLabels.rowWidth(PreopSection.allCases.map(\.sectionTitle))
        XCTAssertGreaterThan(preop, room, "six chips do not fit a phone: the row scrolls (\(preop) pt)")
        XCTAssertLessThan(preop, preopFull - 150, "the full names ran to \(preopFull) pt")
        for s in PreopSection.allCases { XCTAssertLessThanOrEqual(PatientJumpLabels.rowWidth([PatientJumpLabels.short(s)]), room / 2.5, s.rawValue) }
        for s in IntraopSection.allCases { XCTAssertLessThanOrEqual(PatientJumpLabels.rowWidth([PatientJumpLabels.short(s)]), room / 3, s.rawValue) }
    }

    /// The current chip: the last section whose anchor has reached the pinned bar (within the tolerance), else the first.
    func testCurrentSectionIsTheLastOneThatReachedThePinnedBar() {
        let a = PatientJumpID(section: .procedure), b = PatientJumpID(section: .demographics), c = PatientJumpID(section: .workup)
        let order = [a, b, c]
        let pinY: CGFloat = 100
        // At the top of the tab nothing has reached the bar: the first section.
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: [a.key: 300, b.key: 900, c.key: 1600], pinY: pinY), a)
        // Demographics jumped to: its anchor lands about 8 pt above the chips.
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: [a.key: -500, b.key: 92, c.key: 800], pinY: pinY), b)
        // A title directly under the bar (its anchor within the tolerance below the chips) counts.
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: [a.key: -500, b.key: -200, c.key: pinY + PatientJumpCurrent.tolerance], pinY: pinY), c)
        // One just past the tolerance does not.
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: [a.key: -500, b.key: -200, c.key: pinY + PatientJumpCurrent.tolerance + 1], pinY: pinY), b)
        // Scrolled past everything: the last.
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: [a.key: -900, b.key: -600, c.key: -100], pinY: pinY), c)
        // A section not laid out yet is skipped, not current.
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: [a.key: -500], pinY: pinY), a)
        // Before the pinned bar has measured itself, the first.
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: [a.key: -500, b.key: -100], pinY: -.infinity), a)
        XCTAssertNil(PatientJumpCurrent.current(order: [], tops: [:], pinY: pinY))
    }

    func testOnlySectionsReportTheirAnchors() {
        XCTAssertTrue(PatientJumpID(section: .workup).isSection)
        XCTAssertTrue(PatientJumpID(intraop: .fluids).isSection)
        XCTAssertFalse(PatientJumpID(anchor: "cardio").isSection)
        XCTAssertFalse(PatientJumpID(.airway).isSection)
        var merged: [String: CGFloat] = ["a": 1]
        PatientJumpAnchorKey.reduce(value: &merged) { ["b": 2, "a": 3] }
        XCTAssertEqual(merged, ["a": 3, "b": 2])
    }

    func testTitleMenuListsTheTabsSectionsWithTheirFullNames() {
        XCTAssertEqual(PatientTitleMenu.sections(for: .preop).map(\.fullTitle).first, "Planned Procedure & Anesthetic")
        XCTAssertEqual(PatientTitleMenu.sections(for: .preop).count, 6)
        XCTAssertEqual(PatientTitleMenu.sections(for: .intraop).map(\.fullTitle), IntraopSection.allCases.map(\.title))
        XCTAssertTrue(PatientTitleMenu.sections(for: .summary).isEmpty, "Summary & Handoff has no jump bar")
    }

    // MARK: Q3, Q1, P1-6 — titles, box order, captions

    func testTheFirstSectionIsTitledPlannedProcedureAndAnestheticAndItsChipStaysProcedure() {
        XCTAssertEqual(PreopSection.procedure.sectionTitle, "Planned Procedure & Anesthetic")
        XCTAssertEqual(PatientJumpLabels.short(.procedure), "Procedure")
        for s in PreopSection.allCases where s != .procedure { XCTAssertEqual(s.sectionTitle, s.title) }
    }

    func testExaminationAndWorkupBoxesRunAirwayLabsLinesCardiopulmonaryASA() {
        XCTAssertEqual(PatientView.workupOrder, ["airway", "labs", "devices", "cardio", "asa"])
    }

    func testACaptionIsDrawnOnlyWhereTheSectionTitleDoesNotSayIt() {
        XCTAssertTrue(PatientGroup<EmptyView>.showsCaption(title: "Allergies", hidden: false))
        XCTAssertFalse(PatientGroup<EmptyView>.showsCaption(title: "Demographics", hidden: true), "the first box under Demographics & History")
        XCTAssertFalse(PatientGroup<EmptyView>.showsCaption(title: nil, hidden: false))
        XCTAssertFalse(BriefPanel.showsEyebrow(.preop), "the Preprocedure Summary title says it")
        XCTAssertTrue(BriefPanel.showsEyebrow(.handoff), "the Summary & Handoff tab has no section title")
    }

    // MARK: P1-8, Q7 — one chip grammar, red for alerts only

    func testChipGrammarHasFourLooks() {
        XCTAssertEqual(ChipStyle.allCases, [.choice, .toggle, .preset, .add])
        // Single choice: ink when chosen, never a hue.
        XCTAssertEqual(ChipStyle.choice.look(on: true), ChipStyle.Look(fill: .ink, text: .inverted, edge: .clear, mark: nil))
        XCTAssertEqual(ChipStyle.choice.look(on: false), ChipStyle.Look(fill: .neutral, text: .secondary, edge: .line, mark: nil))
        // Toggle: the action tint and a ✓ when on.
        XCTAssertEqual(ChipStyle.toggle.look(on: true), ChipStyle.Look(fill: .action, text: .ink, edge: .action, mark: "checkmark"))
        XCTAssertEqual(ChipStyle.toggle.look(on: false), ChipStyle.choice.look(on: false))
        // Preset: a green outline, ✓ once applied.
        XCTAssertEqual(ChipStyle.preset.look(on: false).edge, .green)
        XCTAssertNil(ChipStyle.preset.look(on: false).mark)
        XCTAssertEqual(ChipStyle.preset.look(on: true), ChipStyle.Look(fill: .green, text: .ink, edge: .green, mark: "checkmark"))
        // Add: a grey outline with a "+", on or off.
        XCTAssertEqual(ChipStyle.add.look(on: false), ChipStyle.Look(fill: .neutral, text: .secondary, edge: .line, mark: "plus"))
        XCTAssertEqual(ChipStyle.add.look(on: true).mark, "plus")
        XCTAssertTrue(ChipStyle.toggle.checks && ChipStyle.preset.checks && !ChipStyle.choice.checks && !ChipStyle.add.checks)
        XCTAssertTrue(ChipStyle.add.alwaysMarked && ChipStyle.choice.isChoice)
        // No look uses red: red is a clinical alert, never a chip's state.
        for style in ChipStyle.allCases {
            for on in [true, false] {
                let l = style.look(on: on)
                for tone in [l.fill, l.text, l.edge] { XCTAssertNotEqual(String(describing: tone), "red", "\(style) on=\(on)") }
            }
        }
    }

    func testYesNoPillsAreInkFilledNotGreenOrRed() {
        XCTAssertEqual(YesNoPills.style, .choice)
        XCTAssertEqual(YesNoPills.look(on: true).fill, .ink)
        XCTAssertEqual(YesNoPills.look(on: true).text, .inverted)
        XCTAssertEqual(YesNoPills.look(on: false).fill, .neutral)
        for on in [true, false] {
            let l = YesNoPills.look(on: on)
            XCTAssertNotEqual(l.fill, .green); XCTAssertNotEqual(l.fill, .action)
        }
    }

    func testActionAndAlertTokens() {
        XCTAssertEqual(PS.action, PS.accent2, "actions take the app's blue")
        XCTAssertNotEqual(PS.action, PS.accent, "the brand red stays on the tab bar's selection")
        XCTAssertEqual(PatientLineText.alertColor, PS.red, "an alert summary line is red, not the brand colour")
        XCTAssertNotEqual(PatientLineText.alertColor, PS.accent)
        XCTAssertEqual(ChipStyle.color(.action, tint: PS.action), PS.action)
        XCTAssertEqual(ChipStyle.color(.ink, tint: PS.action), PS.fg)
        XCTAssertEqual(ChipStyle.color(.inverted, tint: PS.action), PS.bg)
        XCTAssertEqual(ChipStyle.color(.green, tint: PS.action), PS.green)
    }

    /// The gallery the CI shoots in light and dark shows every chip look, the pills and the jump chips.
    func testStyleGalleryShowsEveryVariant() {
        for style in ChipStyle.allCases { XCTAssertTrue(PatientStyleGallery.variants.contains(style.rawValue), style.rawValue) }
        for v in ["yesno", "quietlink", "collapsed", "addchip", "filledrow-alert", "line-alert", "section-title", "jump", "tokens"] {
            XCTAssertTrue(PatientStyleGallery.variants.contains(v), v)
        }
    }

    // MARK: Saved records

    /// A record saved by 1.10 (its keys as 1.10 wrote them, none of 1.11's) still loads, and nothing in this release's
    /// layout changed what it holds.
    func testARecordSavedBy110StillDecodes() throws {
        let json = #"""
        {"version":1,"ageYears":68,"sex":"male","heightCm":178,"weightKg":96,"procedure":"Laparoscopic cholecystectomy",
         "urgency":"elective","anesthetic":["ga","regional"],"highRiskSurgery":false,"codeStatus":"dnr","mallampati":3,
         "homeInfusions":[{"id":"8C9B7A6E-1111-4F3A-9B1D-000000000001","drug":"Norepinephrine","rate":"0.05 mcg/kg/min"}],
         "infusions":[],"preopSummaryOn":true,"airwayAtEnd":"extubated","disposition":"PACU","todos":"Check K at 14:00"}
        """#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.ageYears, 68)
        XCTAssertEqual(r.sex, .male)
        XCTAssertEqual(r.urgency, .elective)
        XCTAssertEqual(r.anesthetic, ["ga", "regional"])
        XCTAssertEqual(r.codeStatus, .dnr)
        XCTAssertEqual(r.mallampati, 3)
        XCTAssertEqual(r.homeInfusions.first?.drug, "Norepinephrine")
        XCTAssertNil(r.homeInfusions.first?.fromPreop, "a 1.10 drip has no 1.11 provenance")
        XCTAssertTrue(r.preopSummaryOn)
        XCTAssertEqual(r.disposition, "PACU")
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
        _ = try JSONDecoder().decode(PatientRecord.self, from: Data("{}".utf8))
    }
}
