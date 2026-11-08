import XCTest
import CoreGraphics
import SwiftUI
import UIKit
@testable import PeriopSignal

/// 1.10 regression review against the approved 1.9.0 screenshots (the Preoperative group): an emergency urgency keeps its
/// alert style on the collapsed row; a chosen toggle chip in a one-line row keeps a cue that is not colour alone; the Past
/// Surgical History bar reports an aside it did not read and files the history an operation implies (once); the
/// quick-add plan caption names the Planned Procedure & Anesthetic box.
final class Review110ShotsTests_regress_preop: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 8))! }

    // MARK: 103/131: Emergency on the collapsed urgency row

    func testEmergencyIsTheOnlyUrgencyDrawnInTheAlertStyle() throws {
        var r = PatientRecord()
        for u in PatientUrgency.allCases {
            r.urgency = u
            let parts = try XCTUnwrap(PatientPreop110.urgencyCollapsedParts(r))
            XCTAssertEqual(parts.title, "Urgency: " + u.label)
            XCTAssertEqual(parts.action, "Change")
            XCTAssertEqual(parts.alert, u == .emergency, "\(u): 1.9 drew only \"Emergency\" in the alert style (alert: r.emergency)")
        }
        r.urgency = nil
        XCTAssertNil(PatientPreop110.urgencyCollapsedParts(r))
    }

    // MARK: 223/224, 315–334: a chosen toggle chip is not shown by colour alone

    /// A chip row inside a group at 375 pt: the page's 20-pt margins and the row's 14.
    private let row375: CGFloat = 375 - 40 - 28

    func testToggleRowsTryEveryOneLineFormWithTheCheckSlotFirst() {
        let toggle = ChipMetrics.forms(choice: false)
        let n = ChipMetrics.order.count
        XCTAssertTrue(toggle.prefix(n).allSatisfy(\.check), "the forms with the ✓ slot first")
        XCTAssertEqual(toggle.prefix(n).map(\.density), ChipMetrics.order.map(\.density))
        XCTAssertEqual(toggle.prefix(n).map(\.short), ChipMetrics.order.map(\.short))
        let fallback = Array(toggle.dropFirst(n))
        XCTAssertFalse(fallback.contains(where: \.check), "then the forms without it, before wrapping")
        XCTAssertEqual(fallback.map(\.density), [.tight, .tight, .dense, .dense], "the tighter ones (the usual padding is never narrower)")
        XCTAssertEqual(ChipMetrics.forms(choice: false, compact: true).filter(\.check).count, ChipMetrics.compactOrder.count)
        // A choice chip is filled solid with inverted text when chosen: no slot, the forms as before.
        XCTAssertFalse(ChipMetrics.forms(choice: true).contains(where: \.check))
        XCTAssertEqual(ChipMetrics.forms(choice: true).map(\.density), ChipMetrics.order.map(\.density))
    }

    /// Every form is a whole row ViewThatFits keeps (the system pages opened late on the CI simulator when a toggle row
    /// kept twelve): a row without short words keeps no more forms than 1.10 did.
    func testARowWithoutShortWordsKeepsNoMoreFormsThanBefore() {
        let plain = ChipMetrics.forms(choice: false, shorts: false)
        XCTAssertLessThanOrEqual(plain.count, ChipMetrics.order.count)
        XCTAssertFalse(plain.contains(where: \.short))
        XCTAssertEqual(plain.map(\.check), [true, true, true, false, false])
        XCTAssertEqual(ChipMetrics.forms(choice: true, shorts: false).map(\.density), [.regular, .tight, .dense])
        // The same fits: the short forms of a row without short words are the full ones.
        let options = [ChipChoice("a", "Heparin"), ChipChoice("b", "Warfarin"), ChipChoice("c", "Enoxaparin"), ChipChoice("d", "Other")]
        for w in stride(from: CGFloat(200), through: 420, by: 5) {
            let fit = ChipMetrics.lineFit(options, choice: true, in: w)
            let full = ChipMetrics.order.first { !$0.short && w >= ChipMetrics.width(options.map(\.label), density: $0.density, choice: true) }
            XCTAssertEqual(fit?.density, full?.density, "\(w)")
        }
    }

    func testTheCheckSlotIsCountedInEveryChipSoATapNeverWidensIt() {
        let labels = ["Heparin", "Warfarin", "Enoxaparin", "Other"]
        XCTAssertGreaterThanOrEqual(ChipMetrics.checkWidth, 8, "the ✓ glyph at the chip's check size")
        for d in [ChipMetrics.Density.regular, .tight, .dense, .compact] {
            let plain = ChipMetrics.width(labels, density: d, choice: false)
            let checked = ChipMetrics.width(labels, density: d, choice: false, check: true)
            XCTAssertEqual(checked - plain, CGFloat(labels.count) * (ChipMetrics.checkWidth + ChipMetrics.checkGap), accuracy: 0.01, "\(d)")
        }
    }

    func testWithMassEffectAloneInItsRowKeepsItsCheck() throws {
        // 1.9's "✓ With mass effect" under Intracranial bleed (shot 223/224).
        let fit = try XCTUnwrap(ChipMetrics.lineFit([ChipChoice("ich-mass", "With mass effect")], choice: false, in: row375))
        XCTAssertTrue(fit.check)
        XCTAssertFalse(fit.short)
        XCTAssertEqual(fit.density, .regular)
    }

    func testSystemPageRowsKeepTheirCheckAt375() {
        // Rows from the 1.9 shots whose chosen chips read "✓ Fistula" (315) and the respiratory infection chips.
        let rows: [[ChipChoice]] = [
            HistorySections.dialysisAccesses.map { ChipChoice($0.0, $0.1) },
            [ChipChoice("uri", "URI"), ChipChoice("pneumonia", "Pneumonia"), ChipChoice("other", "Other")],
        ]
        for options in rows {
            XCTAssertEqual(ChipMetrics.lineFit(options, choice: false, in: row375)?.check, true, options.map(\.label).joined(separator: ", "))
        }
        // Heparin, Warfarin, Enoxaparin, Other (321) does not fit one line at 375 pt with the slot: it stays on one line
        // without it (no new wrap), its chosen chips with the heavier outline.
        let anticoagulants = HistorySections.anticoagulantKinds.map { ChipChoice($0.0, $0.1) }
        let fit = ChipMetrics.lineFit(anticoagulants, choice: false, in: row375)
        XCTAssertEqual(fit?.check, false)
        XCTAssertNotNil(ChipMetrics.lineFit(anticoagulants, choice: false, in: 402 - 40 - 28), "one line at 402 pt")
    }

    func testARowThatFitsOnlyWithoutTheSlotStaysOnOneLine() throws {
        // No new wraps: a row that fit one line in 1.10 still does, without the slot (its chosen chip then has the heavier
        // outline); it wraps only where 1.10 wrapped it.
        let options = [ChipChoice("a", "Pacemaker"), ChipChoice("b", "ICD"), ChipChoice("c", "Pacer dependent"), ChipChoice("d", "Leadless")]
        let narrowest = ChipMetrics.width(options.map(\.shown), density: .dense, choice: false)
        let fit = try XCTUnwrap(ChipMetrics.lineFit(options, choice: false, in: narrowest))
        XCTAssertFalse(fit.check)
        XCTAssertEqual(fit.density, .dense)
        XCTAssertNil(ChipMetrics.lineFit(options, choice: false, in: narrowest - 1), "narrower: it wraps, as in 1.10")
        // Wide enough for the slot at the usual padding: the ✓ form is used.
        let wide = ChipMetrics.width(options.map(\.label), density: .regular, choice: false, check: true)
        XCTAssertEqual(ChipMetrics.lineFit(options, choice: false, in: wide)?.check, true)
        XCTAssertEqual(ChipMetrics.lineFit(options, choice: false, in: wide)?.density, .regular)
        XCTAssertGreaterThan(ChipMetrics.heavyEdge, 1, "a heavier edge than an unchosen chip's 1 pt")
    }

    // MARK: 315: a labelled toggle row keeps its title on the chips' line

    /// The height of a view drawn at `width`.
    @MainActor private func height<V: View>(_ view: V, width: CGFloat) -> CGFloat {
        let r = ImageRenderer(content: view.frame(width: width))
        r.proposedSize = ProposedViewSize(width: width, height: nil)
        r.scale = 3
        return r.uiImage?.size.height ?? -1
    }

    /// Renal's "Access  ✓ Fistula  Dialysis catheter" (1.9 and the 1.10 candidate on one line; the ✓ slot stacked it).
    @MainActor private func accessRow() -> some View {
        InlineChoices {
            Text("Access").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
        } choices: {
            PatientChips(options: HistorySections.dialysisAccesses.map { PatientFlag($0.0, $0.1) }, selection: .constant(["fistula"]))
        }
    }

    /// Between a title and its choices on one line, at the least: the 1.10 HStack's 10 pt, its spacer's 8, 10 pt.
    private let titleGap: CGFloat = 10 + 8 + 10

    @MainActor func testALabelledToggleRowStaysOnOneLineWhereTheCandidateDid() {
        let labels = HistorySections.dialysisAccesses.map { $0.1 }
        let title = ("Access" as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: (13 * PS.textScale).rounded(toPlaces: 1), weight: .semibold)]).width
        let plain = ChipMetrics.width(labels, density: .regular, choice: false)
        let checked = ChipMetrics.width(labels, density: .regular, choice: false, check: true)
        XCTAssertGreaterThan(checked - plain, 20, "the ✓ slot in both chips")
        let chips = PatientChips(options: HistorySections.dialysisAccesses.map { PatientFlag($0.0, $0.1) }, selection: .constant(["fistula"]))
        // Room for the title and the chips as the 1.10 candidate measured them, not for the widest ✓ form: one line.
        let fits = title + titleGap + plain + 4
        XCTAssertLessThan(fits, title + titleGap + checked, "the widest ✓ form does not fit beside the title")
        let line = height(chips, width: fits)
        XCTAssertGreaterThan(line, 0)
        XCTAssertEqual(height(accessRow(), width: fits), line, accuracy: 1, "\"Access\" stays on its chips' line, as in 1.9 and 1.10")
        // Where the candidate stacked it, it still stacks (no new layout either way).
        let stacks = title + titleGap + plain - 8
        XCTAssertGreaterThan(height(accessRow(), width: stacks), line + 10, "the title above the chips, as 1.10 drew it")
    }

    func testTheRowIsMeasuredAsTheCandidateMeasuredIt() {
        XCTAssertEqual(InlineChoicesLayout.gap, titleGap, "the same room between the title and the choices")
        XCTAssertTrue(InlineChoicesLayout.inline(title: 40, choices: 200, in: 268))
        XCTAssertFalse(InlineChoicesLayout.inline(title: 40, choices: 200, in: 267.5))
        XCTAssertTrue(InlineChoicesLayout.inline(title: 40, choices: 2000, in: nil), "no limit: one line")
    }

    // MARK: 421: the Past Surgical History bar

    private static let line421 = "PSH: CABG x3 2019, TEVAR 08/2022, appendectomy 2010 under GA"

    private func psh(_ line: String, record: PatientRecord = PatientRecord()) -> QuickAddReading {
        QuickAdd.read(line, record: record, tab: .preop, now: now, surgicalHistory: true)
    }

    private func applied(_ q: QuickAddReading, to record: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = record
        PatientNote.apply(QuickAdd.changes(QuickAdd.chips(q, record: record)), to: &r)
        return r
    }

    private func isPastSurgery(_ f: PatientNoteFinding) -> Bool {
        if case .pastSurgery = f.change { return true }
        return false
    }

    func testAnAsideAfterAPastOperationIsReportedAsNotRead() {
        let q = psh(Self.line421)
        XCTAssertEqual(q.unread, "under GA", "1.9's \"Not read: under GA\"")
        let r = applied(q)
        XCTAssertEqual(r.surgeries.count, 3)
        XCTAssertFalse(r.surgeries.contains { $0.text.lowercased().contains("under ga") }, "the aside is not read twice")
        // Two operations under the same anesthetic: reported once.
        XCTAssertEqual(psh("appendectomy 2010 under GA, cholecystectomy 2015 under GA").unread, "under GA")
        // Nothing to report: nothing shown.
        XCTAssertEqual(psh("appendectomy 2010").unread, "")
    }

    func testTheHistoryAnOperationImpliesIsFiledOnceWithOnePastSurgeryEntry() throws {
        let q = psh(Self.line421)
        XCTAssertEqual(q.findings.filter(isPastSurgery).count, 3, q.findings.map(\.label).joined(separator: "; "))
        XCTAssertTrue(q.findings.contains { $0.change == .problem("cabg") }, "Prior CABG, as 1.9 and the note reader file it")
        XCTAssertTrue(q.findings.contains { $0.change == .problem("tevar") }, "Prior TEVAR")
        XCTAssertFalse(q.findings.contains { if case .procedure = $0.change { return true }; return false }, "never the procedure")
        XCTAssertFalse(q.findings.contains { if case .cardiacSurgery = $0.change { return true }; return false })
        let r = applied(q)
        XCTAssertEqual(r.surgeries.count, 3, "one Past surgical history entry per operation, no double post")
        let cabg = try XCTUnwrap(r.surgeries.first { $0.procedures.first?.catalogID == "cabg" })
        XCTAssertEqual(r.hx.cardiacSurgeryID, cabg.id, "the cardiovascular page's Previous cardiac surgery is that entry")
        XCTAssertTrue(r.has("cabg"))
        XCTAssertTrue(PatientRules.prefill("rcri", r).on.contains("ihd"), "a prior CABG answers the RCRI's ischemic heart disease, as in 1.9")
        // The note reader's "PSH:" section files the same history.
        let note = PatientNote.read(Self.line421, now: now)
        XCTAssertTrue(note.findings.contains { $0.change == .problem("cabg") })
        // Added again: nothing doubles.
        XCTAssertEqual(applied(psh(Self.line421, record: r), to: r).surgeries.count, 3)
    }

    func testAnOperationWithNoHistoryFilesOnlyItsEntry() {
        let q = psh("appendectomy 2010")
        XCTAssertEqual(q.findings.count, 1)
        XCTAssertTrue(q.findings.allSatisfy(isPastSurgery))
        XCTAssertTrue(QuickAdd.impliedHistory(.problem("cabg")))
        XCTAssertFalse(QuickAdd.impliedHistory(.pastSurgery("CABG", PatientMonthYear(year: 2019))))
        XCTAssertFalse(QuickAdd.impliedHistory(.procedure("CABG")))
    }

    // MARK: 433: the quick-add plan caption

    func testThePlanCaptionNamesTheBoxOnTheTab() {
        XCTAssertEqual(QuickAdd.planNote, "The usual plan for the procedure, as the Planned Procedure & Anesthetic box fills it.")
        XCTAssertFalse(QuickAdd.planNote.contains("Procedure editor"), "the Procedure card is gone from the tab in 1.10")
    }
}
