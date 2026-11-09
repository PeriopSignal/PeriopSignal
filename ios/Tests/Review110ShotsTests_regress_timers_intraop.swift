import XCTest
import UIKit
@testable import PeriopSignal

/// 1.10 screenshot review, regressions against 1.9 (Case Timers and the Intraoperative tab): the running timer rows show
/// what each timer is for (ACT goal, antibiotic dose and interval, check interval) under the title again, with the
/// countdown and due line kept (301/302, 500/501); the arm and limb alerts open the Lines & Devices cards, above the figure
/// (113, 378).
final class Review110ShotsRegressTimersIntraopTests: XCTestCase {
    private func data() throws -> CaseTimerData {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        return try XCTUnwrap(ReferenceLoader.decode(try Data(contentsOf: url)).caseTimers, "caseTimers decodes")
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func adult() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 60; r.sex = .male; r.heightCm = 178; r.weightKg = 80
        return r
    }

    // MARK: Running timers (301, 302, 500, 501)

    func testRunningRowsShowTheGoalDoseAndIntervalWithTheDueLine() throws {
        let d = try data()
        var r = adult()
        var t = CaseTimers()
        t.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0, ebl: 0)], everyMinutes: 240)]
        t.checks["glucose"] = LabCheckCourse(every: 30, started: t0)
        var h = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
        h.doses = [TimedEntry(time: t0, value: 32000)]
        t.heparin = h
        var rem = CaseTimerEngine.reminders(t, record: r, data: d)

        // ACT: Ben named stating the ACT goal as an important point; it shows on the running row, not only in the section.
        let act = try XCTUnwrap(rem.first { $0.kind == .act })
        let actText = CaseTimersView.runningText(act, state: .waiting)
        let actDetail = try XCTUnwrap(actText.detail, "the ACT row states its goal")
        XCTAssertTrue(actDetail.contains("Goal ≥ 480 s"), actDetail)
        XCTAssertTrue(actDetail.contains("every 30 min"), actDetail)
        XCTAssertTrue(actText.due.hasPrefix("Due at "), actText.due)
        XCTAssertFalse(actText.due.contains("Goal"), "the due line stays the due time only: \(actText.due)")

        // Overdue keeps its own line; the goal is still there.
        let overdue = CaseTimersView.runningText(act, state: .overdue)
        XCTAssertTrue(overdue.due.hasPrefix("Overdue · due at "), overdue.due)
        XCTAssertEqual(overdue.detail, actText.detail)

        // Antibiotic: the dose and interval, as 1.9's Next list read ("2 g · every 4 h from the last dose").
        let cef = try XCTUnwrap(rem.first { $0.id == "antibiotic.cefazolin" })
        let cefDetail = try XCTUnwrap(CaseTimersView.runningText(cef, state: .waiting).detail)
        XCTAssertTrue(cefDetail.contains("2 g"), cefDetail)
        XCTAssertTrue(cefDetail.contains("every 4 h"), cefDetail)

        // A check: its interval.
        let glucose = try XCTUnwrap(rem.first { $0.kind == .glucose })
        XCTAssertEqual(CaseTimersView.runningText(glucose, state: .waiting).detail, "Every 30 min")

        // Blood loss has no due time: its detail is its one line, not shown twice.
        r.fluids["ebl"] = 1600
        rem = CaseTimerEngine.reminders(t, record: r, data: d)
        let loss = try XCTUnwrap(rem.first { $0.kind == .bloodLoss })
        let lossText = CaseTimersView.runningText(loss, state: .due)
        XCTAssertNil(lossText.detail)
        XCTAssertEqual(lossText.due, loss.detail)
    }

    // MARK: Lines & Devices (113, 378)

    func testIntraopLinesCardPutsTheArmAndLimbAlertsAboveTheFigure() throws {
        // The cardiac demo (shot 113): a planned left radial harvest with a PIV on that arm.
        let demo = PatientDemo.cardiac
        let s = IntraopDevicesCard.sections(demo)
        XCTAssertFalse(s.aboveFigure.isEmpty, "the harvest cautions open the card")
        XCTAssertTrue(s.aboveFigure.allSatisfy(\.alert), "only alerts go above the figure: \(s.aboveFigure.map(\.text))")
        XCTAssertTrue(s.aboveFigure.contains { $0.label == "Arms" && $0.text.contains("radial harvest") }, s.aboveFigure.map(\.text).joined(separator: " | "))
        XCTAssertFalse(s.belowFigure.contains { $0.label == "Arms" || $0.label == "Limb alert" }, "not repeated after the figure")
        XCTAssertEqual(IntraopDevicesCard.lines(demo), s.aboveFigure + s.belowFigure, "nothing lost")

        // A limb alert and a harvest together: both above, the limb alert first; the placed lines follow the figure.
        var r = PatientRecord()
        r.radial.harvest = "left"
        r.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "Lymphedema")]
        r.lines = [PatientLine(kind: "Peripheral IV", site: "R hand", size: "18 G")]
        let both = IntraopDevicesCard.sections(r)
        XCTAssertEqual(both.aboveFigure.first?.label, "Limb alert")
        XCTAssertTrue(both.aboveFigure.contains { $0.label == "Arms" })
        XCTAssertTrue(both.belowFigure.contains { $0.text.contains("18 G") }, both.belowFigure.map(\.text).joined(separator: " | "))
        XCTAssertFalse(both.aboveFigure.contains { $0.text.contains("18 G") })
    }

    func testPreopLinesCardPutsTheLimbAlertsAboveTheFigure() {
        let card = PatientDiagramCard.preopCard(PatientDemo.dialysis)
        XCTAssertEqual(card.parts, [.limbAlerts, .figure], "the limb alerts open the preop card too")
        XCTAssertEqual(card.phase, .preop)
        // The handoff's figure lists no limb alerts of its own (its text has them).
        XCTAssertEqual(PatientDiagramCard(record: PatientRecord(), phase: .all, listsLimbAlerts: false).parts, [.figure])
    }

    // MARK: The Lines & Devices card's figure (660, 661)

    /// The rect a column label is drawn in at scale k, in points from the figure's origin (its font's line height high).
    private func labelRect(_ item: DiagramItem, k: CGFloat) -> CGRect? {
        guard let la = item.labelAt, !item.label.isEmpty else { return nil }
        let w = PatientDiagramCanvas.labelWidth(item.label, k: k), h = PatientDiagramCanvas.labelHeight(k)
        return CGRect(x: item.labelLeft ? la.x * k - w : la.x * k, y: la.y * k - h / 2, width: w, height: h)
    }

    /// The rect a line of the cart's text is drawn in.
    private func textRect(_ text: String, size: CGFloat, weight: UIFont.Weight, center: CGPoint) -> CGRect {
        let f = UIFont.systemFont(ofSize: size, weight: weight)
        let w = ceil((text as NSString).size(withAttributes: [.font: f]).width)
        return CGRect(x: center.x - w / 2, y: center.y - f.lineHeight / 2, width: w, height: f.lineHeight)
    }

    func testCardFigureLabelsNeverOverlapAndTheCartHoldsItsText() throws {
        // The cardiac demo (shots 660/661): VA ECMO, an IABP, a PAC, an A-line, a PIV and a Foley.
        let m = PatientDiagramModel.items(PatientDemo.cardiac, phase: .all)
        let cart = try XCTUnwrap(m.cart)
        // The 260-point card, the handoff's small figure, the shared picture and the editor (430 points high).
        for height: CGFloat in [200, 260, 292, 350, 430, 511] {
            let k = height / 420
            let items = PatientDiagramCanvas.laidOut(m.items, cart: m.cart, k: k)
            let labelled = items.filter { $0.labelAt != nil && !$0.label.isEmpty }
            XCTAssertGreaterThanOrEqual(labelled.count, 5, "height \(height)")
            for (i, a) in labelled.enumerated() {
                let ra = try XCTUnwrap(labelRect(a, k: k))
                for b in labelled.dropFirst(i + 1) {
                    let rb = try XCTUnwrap(labelRect(b, k: k))
                    XCTAssertFalse(ra.insetBy(dx: 0, dy: 0.01).intersects(rb.insetBy(dx: 0, dy: 0.01)),
                                   "height \(height): '\(a.label)' \(ra) and '\(b.label)' \(rb) overlap")
                }
            }
            // The cart's box holds its two lines, and no label is drawn on it.
            let cl = PatientDiagramCanvas.cartLayout(cart, k: k)
            let title = textRect(cart.title, size: cl.titleSize, weight: .bold, center: cl.title)
            let detail = textRect(cart.detail, size: cl.detailSize, weight: .medium, center: cl.detail)
            XCTAssertTrue(cl.box.contains(title), "height \(height): title \(title) outside the box \(cl.box)")
            XCTAssertTrue(cl.box.contains(detail), "height \(height): detail \(detail) outside the box \(cl.box)")
            XCTAssertFalse(title.insetBy(dx: 0, dy: 0.01).intersects(detail.insetBy(dx: 0, dy: 0.01)), "height \(height)")
            for item in labelled {
                let r = try XCTUnwrap(labelRect(item, k: k))
                XCTAssertFalse(r.insetBy(dx: 0, dy: 0.01).intersects(cl.box), "height \(height): '\(item.label)' on the cart")
            }
            // The drawing keeps the box inside its right margin.
            let margins = PatientDiagramCanvas.margins(items, figureWidth: 200, k: k, cart: m.cart)
            XCTAssertLessThanOrEqual(cl.box.maxX, 200 * k + margins.right)
        }
        // The editor's figure keeps the model's gap and the cart's usual box, so it looks as it did.
        let editor: CGFloat = 430 / 420
        XCTAssertEqual(PatientDiagramCanvas.labelGap(editor), PatientDiagramModel.labelGap)
        XCTAssertEqual(PatientDiagramCanvas.laidOut(m.items, cart: m.cart, k: editor).map(\.labelAt), m.items.map(\.labelAt))
        XCTAssertEqual(PatientDiagramCanvas.cartLayout(cart, k: editor).box.height, 24 * editor, accuracy: 0.001)
        XCTAssertEqual(PatientDiagramCanvas.cartLayout(cart, k: editor).title.y, (cart.at.y - 4) * editor, accuracy: 0.001)
        // The card's figure spreads its labels: a 7-point label is taller than the model's 8.5 units at k 0.62.
        XCTAssertGreaterThan(PatientDiagramCanvas.labelGap(260 / 420), PatientDiagramModel.labelGap)
    }
}
