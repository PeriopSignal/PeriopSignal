import XCTest
import SwiftUI
import UIKit
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

    /// A short last section cannot reach the pinned bar: a section jumped to keeps its chip until it is scrolled back
    /// down by hand, and at the end of the tab the last section is current (1.11 review).
    func testAJumpedToSectionAndTheEndOfTheTab() {
        let a = PatientJumpID(section: .procedure), b = PatientJumpID(section: .demographics), c = PatientJumpID(section: .workup)
        let order = [a, b, c]
        let pinY: CGFloat = 100
        // The tab ended with the last section's anchor 300 pt below the bar: by the bar's rule the second is current.
        let end: [String: CGFloat] = [a.key: -900, b.key: -200, c.key: 400]
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: end, pinY: pinY), b)
        // Jumped to: it holds the chip, from the tap (its anchor still far below) to where the scroll ends.
        XCTAssertTrue(PatientJumpCurrent.holds(order: order, tops: [a.key: -100, b.key: 600, c.key: 1200], pinY: pinY, held: c, heldMinTop: .infinity))
        XCTAssertTrue(PatientJumpCurrent.holds(order: order, tops: end, pinY: pinY, held: c, heldMinTop: 400))
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: end, pinY: pinY, atEnd: false, held: c, heldMinTop: 400), c)
        // Scrolled back down by hand, past the slack: the chip lets go.
        let back: [String: CGFloat] = [a.key: -840, b.key: -140, c.key: 400 + PatientJumpCurrent.holdSlack + 1]
        XCTAssertFalse(PatientJumpCurrent.holds(order: order, tops: back, pinY: pinY, held: c, heldMinTop: 400))
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: back, pinY: pinY, atEnd: false, held: c, heldMinTop: 400), b)
        // A section that reached the bar, or an earlier one, needs no hold: the bar's rule says where the tab is.
        XCTAssertFalse(PatientJumpCurrent.holds(order: order, tops: [a.key: -500, b.key: 92, c.key: 800], pinY: pinY, held: b, heldMinTop: 92))
        XCTAssertFalse(PatientJumpCurrent.holds(order: order, tops: end, pinY: pinY, held: a, heldMinTop: .infinity))
        // At the end of the tab without a jump: the last section laid out. A jump made there still wins.
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: end, pinY: pinY, atEnd: true, held: nil, heldMinTop: .infinity), c)
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: [a.key: -900, b.key: -200], pinY: pinY, atEnd: true, held: nil, heldMinTop: .infinity), b)
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: end, pinY: pinY, atEnd: false, held: nil, heldMinTop: .infinity), b)
        XCTAssertEqual(PatientJumpCurrent.current(order: order, tops: end, pinY: -.infinity, atEnd: true, held: nil, heldMinTop: .infinity), a)
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

    /// A tab switch clears the current chip (the new tab's first section until its anchors report); a tap on the tab
    /// already showing keeps it. Decided from the tab showing, before the switch is applied.
    func testATabSwitchClearsTheCurrentChipAndARetapKeepsIt() {
        let workup = PatientJumpID(section: .workup)
        XCTAssertNil(PatientView.jumpAfterSelecting(.intraop, showing: .preop, current: workup))
        XCTAssertNil(PatientView.jumpAfterSelecting(.summary, showing: .preop, current: workup))
        XCTAssertEqual(PatientView.jumpAfterSelecting(.preop, showing: .preop, current: workup), workup)
        XCTAssertNil(PatientView.jumpAfterSelecting(.preop, showing: .preop, current: nil))
    }

    /// A page's only box draws no caption that says the page title again (ECG / ECG FINDINGS, the catheterizations,
    /// Anesthetic complications); a caption that carries the box's ⓘ stays, since a page has no title line for it.
    func testPageCaptionsThatRepeatThePageTitleGo() {
        XCTAssertNil(PatientPageCaption.caption("ECG findings", page: PatientEditor.workup("ecg").title))
        XCTAssertNil(PatientPageCaption.caption("Left heart catheterization", page: PatientEditor.workup("lhc").title))
        XCTAssertNil(PatientPageCaption.caption("Right heart catheterization", page: PatientEditor.workup("rhc").title))
        XCTAssertNil(PatientPageCaption.caption("Anesthetic complications", page: PatientEditor.workup("anesthetic").title))
        XCTAssertEqual(PatientPageCaption.caption("Study", page: "Echo Findings"), "Study")
        XCTAssertEqual(PatientPageCaption.caption("Preprocedure vital signs", page: "Demographics"), "Preprocedure vital signs")
        XCTAssertEqual(PatientPageCaption.caption("Past surgical history", page: "Past Surgical History", note: "Also under Previous intrathoracic surgery."),
                       "Past surgical history", "the caption carries the ⓘ")
        XCTAssertTrue(PatientPageCaption.restates("ECG FINDINGS", "ECG"))
        XCTAssertFalse(PatientPageCaption.restates("Findings", "ECG"))
        XCTAssertFalse(PatientPageCaption.restates("Demographics", "Demographics & History"))
    }

    /// NSR on the ECG page is a preset (green outline, ✓ once applied), drawn by ChipSet from ChipStyle.preset, not a
    /// filled green button.
    func testNSRIsAPresetChip() {
        XCTAssertEqual(ECGQuickRow.style, .preset)
        XCTAssertEqual(ECGQuickRow.chips.map(\.label), ["NSR"])
        XCTAssertEqual(ECGQuickRow.style.look(on: false).edge, .green)
        XCTAssertEqual(ECGQuickRow.style.look(on: true).mark, "checkmark")
        XCTAssertNotEqual(ECGQuickRow.style.look(on: true).fill, .ink, "a preset is not a choice")
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

    /// The gallery's parts cover every variant once, and each part below the first screen can be brought up for its
    /// shot (-ps.gallery.scroll); a name that is not a part scrolls nowhere.
    func testStyleGalleryPartsCoverEveryVariantAndCanBeScrolledTo() {
        XCTAssertEqual(PatientStyleGallery.sections, ["tokens", "chips", "links", "lines", "headings", "buttons"])
        XCTAssertEqual(Set(PatientStyleGallery.sectionVariants.keys), Set(PatientStyleGallery.sections))
        let drawn = PatientStyleGallery.sections.flatMap { PatientStyleGallery.sectionVariants[$0] ?? [] }
        XCTAssertEqual(drawn.sorted(), PatientStyleGallery.variants.sorted(), "every variant in one part, once")
        for part in ["links", "lines", "headings", "buttons"] { XCTAssertEqual(PatientStyleGallery.scrollTarget(part), part) }
        XCTAssertNil(PatientStyleGallery.scrollTarget(""))
        XCTAssertNil(PatientStyleGallery.scrollTarget("nowhere"))
    }

    // MARK: P1-6 — Regenerate on the title line; the screenshot names

    /// "Preprocedure Summary · Regenerate" on the title line: the preoperative brief draws no header row of its own, and
    /// the title carries Regenerate only once the summary is showing. The handoff keeps its eyebrow row.
    func testRegenerateSitsOnThePreprocedureSummaryTitleLine() {
        XCTAssertTrue(BriefPanel.regenerateOnTitleLine(.preop))
        XCTAssertFalse(BriefPanel.regenerateOnTitleLine(.handoff), "the handoff has no section title: eyebrow and Regenerate on one row")
        var r = PatientRecord()
        r.ageYears = 70
        XCTAssertFalse(PatientView.summaryTitleHasRegenerate(r), "nothing to regenerate before the summary is generated")
        r.preopSummaryOn = true
        XCTAssertTrue(PatientView.summaryTitleHasRegenerate(r))
    }

    /// The screenshot names: "demographics" is the first box (as before), "demographics-title" the section title above
    /// it, the same target as the jump chip's.
    func testTheDemographicsTitleIsAScreenshotTarget() {
        XCTAssertEqual(PatientView.shotTargetKey("demographics-title"), PatientJumpID(section: .demographics).key)
        XCTAssertEqual(PatientView.shotTargetKey("demographics"), PatientJumpID(anchor: "demographics").key)
        XCTAssertNotEqual(PatientView.shotTargetKey("demographics-title"), PatientView.shotTargetKey("demographics"))
        XCTAssertEqual(PatientView.shotTargetKey("summary"), PatientJumpID(section: .summary).key)
    }

    // MARK: P1-8 — filled capsules that act are the action colour; the title line's narrower Regenerate

    /// "Add N" on the quick-add bar is an action, so its capsule is filled with the action colour. The bar and the
    /// gallery's sample read one constant, so the gallery cannot show a colour the bar does not draw.
    @MainActor func testQuickAddsAddCapsuleIsTheActionColour() {
        XCTAssertEqual(QuickAddBar.addButtonColor, PS.action)
        XCTAssertNotEqual(QuickAddBar.addButtonColor, PS.accent, "the brand red is the tab bar's selection only")
    }

    /// My Patient's other filled capsules (Done, Save, Generate preprocedure summary, Save to My Patient) take the same
    /// colour through one style, with the label colour that reads on it. The style's own default is untouched: Feed
    /// and Reference keep the brand red.
    @MainActor func testMyPatientsFilledCapsulesAreTheActionColourAndTheSharedDefaultIsUnchanged() {
        let style = CapsuleButtonStyle.patientAction()
        XCTAssertEqual(style.color, PS.action)
        XCTAssertTrue(style.prominent)
        XCTAssertEqual(style.onColor, PS.accentFg, "white in light, near-black in dark: both read on the action blue")
        XCTAssertEqual(style.color, QuickAddBar.addButtonColor, "the same fill as Add N")
        XCTAssertFalse(CapsuleButtonStyle.patientAction(prominent: false).prominent, "Update on the echo save bar stays the quiet capsule")
        XCTAssertEqual(CapsuleButtonStyle().color, PS.accent, "the shared default stays as Feed and Reference draw it")
        XCTAssertTrue(CapsuleButtonStyle().prominent)
    }

    /// The line under a TEE item saying what in the record raised it ("Outside the reference range: platelets 96
    /// ×10³/µL, INR 1.8.") is a clinical flag and cannot be tapped: alert red, never the action blue.
    @MainActor func testTheTEEScreensReasonLineIsAnAlertNotAnAction() {
        XCTAssertEqual(TEEScreenStyle.reasonColor, PS.red)
        XCTAssertNotEqual(TEEScreenStyle.reasonColor, PS.action)
        // The line it colours, for a low platelet count (the app's own reference range decides "low").
        var r = PatientRecord()
        r.labs["plt"] = 20
        let why = PatientTEE.evaluate(r).suggestions.first { $0.item.id == "coagulopathy" }?.why ?? ""
        XCTAssertTrue(why.hasPrefix("Outside the reference range: platelets 20"), why)
    }

    /// Regenerate is spoken the same in all three of its forms, and the narrower two are what they say.
    @MainActor func testRegenerateHasThreeFormsWithOneSpokenName() {
        XCTAssertEqual(BriefRegenerateButton.LabelForm.allCases, [.full, .word, .icon])
        XCTAssertEqual(BriefRegenerateButton.spokenName, "Regenerate")
        XCTAssertEqual(BriefRegenerateButton(kind: .preop).form, .full, "the handoff's eyebrow row keeps the full capsule")
    }

    @MainActor private func titleHeight(_ width: CGFloat, forms: [BriefRegenerateButton.LabelForm]) -> CGFloat {
        let store = PatientStore(url: nil)
        func control(_ i: Int) -> AnyView? {
            i < forms.count ? AnyView(BriefRegenerateButton(kind: .preop, form: forms[i]).environment(store)) : nil
        }
        let view = PreopSectionTitle(text: PreopSection.summary.sectionTitle, trailing: control(0), trailingCompact: control(1),
                                     trailingMinimal: control(2))
        let r = ImageRenderer(content: view.frame(width: width))
        r.proposedSize = ProposedViewSize(width: width, height: nil)
        return r.uiImage?.size.height ?? -1
    }

    /// "Preprocedure Summary" keeps Regenerate on its own line on a 375-point phone at the default text size (335
    /// points between the page's margins): where the full capsule does not fit, a narrower form does. Only where not
    /// even the icon fits beside the title does the control take a second row, and then it is the full capsule.
    @MainActor func testRegenerateStaysOnTheTitleLineOnANarrowPhone() {
        let was = PS.textScale
        PS.textScale = 1
        defer { PS.textScale = was }
        let all: [BriefRegenerateButton.LabelForm] = [.full, .word, .icon]
        let title = (PreopSection.summary.sectionTitle as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 19, weight: .bold)]).width
        let oneLine = titleHeight(900, forms: all)
        XCTAssertGreaterThan(oneLine, 0)
        // A second row adds the gap (8) and the title's own line (about 23).
        let secondRow: CGFloat = 20

        XCTAssertLessThanOrEqual(titleHeight(335, forms: all), oneLine + 8, "one line on a 375-point phone")
        // Room for the title and the icon capsule (44), not for the word (about 99) or the full capsule (about 119).
        let iconOnly = title + 8 + 62
        XCTAssertLessThanOrEqual(titleHeight(iconOnly, forms: all), oneLine + 8, "the icon alone still shares the title's line")
        XCTAssertGreaterThan(titleHeight(iconOnly, forms: [.full]), oneLine + secondRow, "without the narrower forms the capsule drops to its own row")
        XCTAssertGreaterThan(titleHeight(iconOnly, forms: [.full, .word]), oneLine + secondRow, "the word alone does not fit there either")
        // No room beside the title even for the icon: two rows, nothing clipped.
        XCTAssertGreaterThan(titleHeight(title + 24, forms: all), oneLine + secondRow)
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
