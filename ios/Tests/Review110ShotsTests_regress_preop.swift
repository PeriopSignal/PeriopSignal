import XCTest
import CoreGraphics
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
        XCTAssertEqual(toggle.count, 2 * ChipMetrics.order.count)
        XCTAssertTrue(toggle.prefix(ChipMetrics.order.count).allSatisfy(\.check), "the forms with the ✓ slot first")
        XCTAssertFalse(toggle.suffix(ChipMetrics.order.count).contains(where: \.check), "then the 1.10 forms, before wrapping")
        XCTAssertEqual(toggle.prefix(ChipMetrics.order.count).map(\.density), ChipMetrics.order.map(\.density))
        XCTAssertEqual(toggle.suffix(ChipMetrics.order.count).map(\.density), ChipMetrics.order.map(\.density))
        XCTAssertEqual(ChipMetrics.forms(choice: false, compact: true).count, 2 * ChipMetrics.compactOrder.count)
        // A choice chip is filled solid with inverted text when chosen: no slot, the forms as before.
        XCTAssertFalse(ChipMetrics.forms(choice: true).contains(where: \.check))
        XCTAssertEqual(ChipMetrics.forms(choice: true).map(\.density), ChipMetrics.order.map(\.density))
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
