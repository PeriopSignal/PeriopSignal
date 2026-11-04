import XCTest
import CoreGraphics
import SwiftUI
@testable import PeriopSignal

/// Fixes for what the 1.9 screenshots showed: figure labels cut mid-glyph, a steroid equivalence that compared a drug
/// with itself, a drip offered twice under the infusion field, and a limb-alert reason whose case changed between pages.
final class Shots19FixTests: XCTestCase {

    // MARK: The figure's labels fit

    private func columnLabel(_ text: String, left: Bool, y: CGFloat = 150) -> DiagramItem {
        DiagramItem(id: text, anchor: CGPoint(x: left ? 60 : 140, y: y), color: .red, label: text, labelLeft: left,
                    labelAt: CGPoint(x: left ? -2 : 202, y: y))
    }

    func testShortLabelsKeepTheFixedMargin() {
        let items = [columnLabel("CVL", left: true), columnLabel("PPM", left: false), columnLabel("A-line", left: false)]
        for k: CGFloat in [0.5, 0.8, 1.2, 2] {
            let m = PatientDiagramCanvas.margins(items, figureWidth: 200, k: k)
            XCTAssertEqual(m.left, PatientDiagramCanvas.margin * k, accuracy: 0.001)
            XCTAssertEqual(m.right, PatientDiagramCanvas.margin * k, accuracy: 0.001)
        }
        // So the drawing is laid out as before: the figure as large as the height allows, centered.
        let size = CGSize(width: 342, height: 445)
        let (k, ox) = PatientDiagramCanvas.layout(items, figureWidth: 200, figureHeight: 420, in: size)
        XCTAssertEqual(k, 445 / 420, accuracy: 0.001)
        XCTAssertEqual(ox, (342 - 296 * k) / 2 + 48 * k, accuracy: 0.01)
    }

    func testLongLabelsWidenTheirSideSoNoneIsCut() {
        let items = [columnLabel("CVL", left: true), columnLabel("PPM", left: false, y: 120),
                     columnLabel("Epi wires A+V", left: false, y: 140), columnLabel("Chest tube 28", left: false, y: 160)]
        // The editor's figure (height-bound), the shared image (360 wide) and the handoff card's small figure.
        for size in [CGSize(width: 342, height: 445), CGSize(width: 360, height: 511), CGSize(width: 246, height: 350), CGSize(width: 180, height: 200)] {
            let (k, ox) = PatientDiagramCanvas.layout(items, figureWidth: 200, figureHeight: 420, in: size)
            XCTAssertGreaterThan(k, 0)
            XCTAssertLessThanOrEqual(k * 420, size.height + 0.01, "\(size): never taller than the drawing")
            let m = PatientDiagramCanvas.margins(items, figureWidth: 200, k: k)
            XCTAssertGreaterThan(m.right, PatientDiagramCanvas.margin * k, "\(size): the long labels widen the right side")
            XCTAssertEqual(m.left, PatientDiagramCanvas.margin * k, accuracy: 0.001, "\(size): the left side, with CVL only, is as before")
            for item in items where !item.labelLeft {
                let end = ox + 202 * k + PatientDiagramCanvas.labelWidth(item.label, k: k)
                XCTAssertLessThanOrEqual(end, size.width - PatientDiagramCanvas.labelAir + 0.5, "\(size): \(item.label) ends inside the drawing")
            }
            XCTAssertGreaterThanOrEqual(ox - 2 * k - PatientDiagramCanvas.labelWidth("CVL", k: k), 0, "\(size): the left label too")
        }
    }

    func testLabelFontNeverUnderSevenPoints() {
        XCTAssertEqual(PatientDiagramCanvas.fontSize(0.6), 7)
        XCTAssertEqual(PatientDiagramCanvas.fontSize(2), 11.2, accuracy: 0.001)
        XCTAssertGreaterThan(PatientDiagramCanvas.labelWidth("Epi wires A+V", k: 1), PatientDiagramCanvas.labelWidth("PPM", k: 1))
    }

    // MARK: Steroid equivalence

    private func onSteroid(_ drug: String, _ mg: Double, _ duration: String = "ge1m") -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 55; r.sex = .female
        r.problems = ["adrenal"]
        r.hx.adrenalKinds = ["steroids"]
        r.hx.steroidDrug = drug; r.hx.steroidDailyMg = mg; r.hx.steroidDuration = duration
        return r
    }

    func testNoEquivalenceLineForTheReferenceDrug() throws {
        XCTAssertTrue(PatientSteroids.isReferenceDrug("Prednisolone"))
        XCTAssertTrue(PatientSteroids.isReferenceDrug("prednisone 10 mg"))
        XCTAssertFalse(PatientSteroids.isReferenceDrug("Methylprednisolone"))
        XCTAssertFalse(PatientSteroids.isReferenceDrug("Hydrocortisone"))
        XCTAssertFalse(PatientSteroids.isReferenceDrug("Fludrocortisone"))
        for drug in ["Prednisolone", "Prednisone"] {
            // At risk, and below the threshold: neither carries the tautology.
            let risk = try XCTUnwrap(PatientSteroids.advice(onSteroid(drug, 10)))
            XCTAssertTrue(risk.atRisk)
            XCTAssertFalse(risk.lines.contains { $0.contains(" a day ≈ ") }, drug + ": " + risk.lines.joined(separator: " | "))
            XCTAssertTrue(risk.lines.contains { $0.contains("hydrocortisone 100 mg IV at induction") }, "the dosing lines stay")
            let low = try XCTUnwrap(PatientSteroids.advice(onSteroid(drug, 4)))
            XCTAssertFalse(low.atRisk)
            XCTAssertFalse(low.lines.contains { $0.contains(" a day ≈ ") })
            XCTAssertEqual(low.lines.first?.hasPrefix("At risk of adrenal suppression"), true, "the rule is the first line then")
        }
    }

    func testEquivalenceLineKeptForOtherDrugs() throws {
        let m = try XCTUnwrap(PatientSteroids.advice(onSteroid("Methylprednisolone", 8)))
        XCTAssertEqual(m.lines.first, "8 mg methylprednisolone a day ≈ 10 mg prednisolone a day.")
        let d = try XCTUnwrap(PatientSteroids.advice(onSteroid("Dexamethasone", 0.5)))
        XCTAssertEqual(d.lines.first, "0.5 mg dexamethasone a day ≈ 3.3 mg prednisolone a day.")
        XCTAssertFalse(d.atRisk)
        // A child's line converts to hydrocortisone per m², never a tautology, so it stays for prednisolone too.
        var c = onSteroid("Prednisolone", 2)
        c.ageYears = 8; c.heightCm = 128; c.weightKg = 26
        XCTAssertEqual(try XCTUnwrap(PatientSteroids.advice(c)).lines.first?.contains("mg/m² of hydrocortisone a day"), true)
    }

    // MARK: Infusion typeahead

    func testADrugAlreadyReadIsNotSuggestedAgain() {
        // "fent" is fentanyl's alias: its chip is shown, so no suggestion repeats it.
        let typed = "norepi 0.05 vaso 0.04 epi 0.02 fent"
        XCTAssertEqual(InfusionEntry.read(typed).items.map(\.drugID), ["norepinephrine", "vasopressin", "epinephrine", "fentanyl"])
        XCTAssertTrue(InfusionEntry.suggestions(typed).isEmpty, InfusionEntry.suggestions(typed).map(\.id).joined(separator: ","))
        // Nothing read yet (two letters): the suggestions speak.
        XCTAssertEqual(InfusionEntry.suggestions("fe").first?.id, "fentanyl")
        // A word that names one drug outright but starts others: the others are offered, that drug is the chip.
        let epi = InfusionEntry.suggestions("epi")
        XCTAssertEqual(InfusionEntry.read("epi").items.map(\.drugID), ["epinephrine"])
        XCTAssertFalse(epi.contains { $0.id == "epinephrine" })
        XCTAssertTrue(epi.contains { $0.id == "iepo" || $0.id == "epoprostenol-iv" || $0.id == "eptifibatide" }, epi.map(\.id).joined(separator: ","))
        // Never the same drug under the field twice, whatever the last piece reads as.
        for text in ["nor", "fent", "dex", "epi", "mag", "roc", "levo", "calcium", "norepi 0.05 va", "norepi 0.05, prop"] {
            let chips = Set(InfusionEntry.read(text).items.map(\.drugID))
            let offered = InfusionEntry.suggestions(text).map(\.id)
            XCTAssertEqual(Set(offered).count, offered.count, text + ": no suggestion twice")
            XCTAssertTrue(chips.isDisjoint(with: offered), text + ": chips \(chips) and suggestions \(offered) overlap")
        }
    }

    func testDripListHasNoDuplicateEntriesOrAliases() {
        let ids = InfusionEntry.drugs.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "every drip once")
        let names = InfusionEntry.drugs.map { InfusionEntry.fold($0.name) }
        XCTAssertEqual(Set(names).count, names.count)
        var seen: [String: String] = [:]
        for d in InfusionEntry.drugs {
            for a in d.aliases {
                if let other = seen[a], other != d.id { XCTFail("alias \"\(a)\" names both \(other) and \(d.id)") }
                seen[a] = d.id
                if let named = InfusionEntry.drugs.first(where: { InfusionEntry.fold($0.name) == a }), named.id != d.id {
                    XCTFail("alias \"\(a)\" of \(d.id) is the name of \(named.id)")
                }
            }
        }
    }

    // MARK: Limb-alert case

    func testLimbAlertReasonReadsWithItsCapitalEverywhere() throws {
        var r = PatientRecord()
        r.ageYears = 60; r.sex = .female
        r.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "prior axillary lymph node dissection")]
        let shown = "R arm — Prior axillary lymph node dissection"
        XCTAssertEqual(PatientDeviceFills.limbAlertGroups(r).map(\.text), [shown], "the cards' caption")
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), shown, "the handoff")
        XCTAssertEqual(PatientSummary.limbAlertLines(r).first?.text, shown, "the summary")
        XCTAssertEqual(r.capitalized.limbAlerts.first?.reason, "Prior axillary lymph node dissection", "the editor's list, as the record reads on a summary")
        let item = try XCTUnwrap(PatientDiagramModel.items(r, phase: .all).items.first { $0.marker == .alert })
        XCTAssertEqual(item.spoken, "Limb alert, right arm: Prior axillary lymph node dissection")
        // An acronym keeps its case; an automatic reason is as the diagram names it.
        r.limbAlerts = [PatientLimbAlert(limb: "leg-left", reason: "AV graft revision")]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), "L leg — AV graft revision")
    }
}
