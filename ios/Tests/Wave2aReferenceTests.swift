import XCTest
import SwiftUI
import UIKit
@testable import PeriopSignal

/// 1.8.1 wave 2a (Reference tools): short one-line titles on the quick references and OB tabs, protocol notes behind
/// ⓘ with every "not recommended" sentence kept in view, and the other moves that must not lose a caution.
final class Wave2aReferenceTests: XCTestCase {
    private func bundled() throws -> ReferenceBundle {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        return try ReferenceLoader.decode(try Data(contentsOf: url))
    }

    /// The width of a title in ToolHeader's font (New York semibold 25 at the default text size).
    private func titleWidth(_ s: String) -> CGFloat {
        let base = UIFont.systemFont(ofSize: 25, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 25) } ?? base
        return (s as NSString).size(withAttributes: [.font: font]).width
    }

    /// The narrowest phone in use (375 points) less the page's 20-point margins.
    private let line: CGFloat = 335
    /// ToolHeader's ⓘ after the title: 8 points of spacing and the 15-point symbol.
    private let info: CGFloat = 26

    // MARK: Titles (S5)

    @MainActor func testQuickRefTitlesFitOneLineWithoutShrinking() throws {
        let b = try bundled()
        for ref in b.quickrefs {
            XCTAssertNotNil(QuickRefView.headers[ref.id], "\(ref.id) has a short header")
            let h = QuickRefView.header(for: ref)
            let room = line - (ref.isEmergency ? 0 : info)
            print("wave2a title width", ref.id, h.title, titleWidth(h.title), "room", room)
            XCTAssertLessThanOrEqual(titleWidth(h.title), room, "\(ref.id): “\(h.title)” fits one line at full size")
            XCTAssertLessThanOrEqual(h.eyebrow.split(separator: " ").count, 2, "\(ref.id): the eyebrow is one or two words")
            XCTAssertFalse(h.eyebrow.contains(String(ref.year ?? 0)), "\(ref.id): the year moved to the sources")
        }
        XCTAssertEqual(QuickRefView.header(for: try XCTUnwrap(b.quickrefs.first { $0.id == "asra-last" })).title, "LAST")
    }

    @MainActor func testObTitlesFitOneLineWithoutShrinking() throws {
        let ob = try XCTUnwrap(try bundled().obEmergency)
        for ev in ob.events {
            let t = ObEmergencyView.title(for: ev)
            print("wave2a title width OB", ev.id, t, titleWidth(t), "room", line)
            XCTAssertLessThanOrEqual(titleWidth(t), line, "OB \(ev.id): “\(t)” fits one line at full size")
            XCTAssertFalse((ev.summary ?? "").isEmpty, "OB \(ev.id) keeps a summary in view")
        }
    }

    // MARK: ACLS protocol notes

    @MainActor func testAclsProtocolNotesKeepEveryNotRecommendedSentenceInView() throws {
        let acls = try XCTUnwrap(try bundled().acls)
        for m in acls.modes {
            guard let n = m.note else { continue }
            let parts = AclsView.splitProtocolNote(n)
            // Nothing is lost or reworded: the kept and the hidden sentences hold every sentence of the note.
            let all = AclsView.sentences(n)
            XCTAssertEqual(all.joined(separator: " "), n, "\(m.id): the sentences rebuild the note exactly")
            XCTAssertEqual(Set(parts.kept + AclsView.sentences(parts.hidden)), Set(all), "\(m.id): every sentence is kept or behind ⓘ")
            for s in all where s.lowercased().contains("not recommended") || s.lowercased().contains("not routine") {
                XCTAssertTrue(parts.kept.contains(s), "\(m.id): “\(s)” stays in view")
                XCTAssertFalse(parts.hidden.contains(s), "\(m.id): “\(s)” is not behind ⓘ")
            }
        }
        let cals = try XCTUnwrap(acls.modes.first { $0.id == "cals" }?.note)
        XCTAssertTrue(AclsView.splitProtocolNote(cals).kept.contains("Full-dose epinephrine and atropine are not routine."))
        let arrest = try XCTUnwrap(acls.modes.first { $0.id == "arrest" }?.note)
        XCTAssertEqual(AclsView.splitProtocolNote(arrest).kept.count, 2, "the adult and the child not-recommended sentences")
        XCTAssertTrue(AclsView.splitProtocolNote(arrest).hidden.hasPrefix("AHA 2025: one shock at a time"))
    }

    @MainActor func testAclsWeightPromptAndClearNote() {
        XCTAssertEqual(AclsView.weightClearNote, "Cleared when the code ends.")
    }

    // MARK: Neuraxial guide and regional finder

    @MainActor func testNeuraxialLevelKeepsAtLeastInView() throws {
        let rg = try XCTUnwrap(try bundled().regional)
        let n = try XCTUnwrap(rg.neuraxial)
        for p in n.procedures {
            guard let t = p.levelText else { continue }
            let s = NeuraxialGuideView.splitLevelText(t)
            if p.id == "cesarean" {
                XCTAssertEqual(s.shown, "At least T4")
                XCTAssertEqual(s.shown + " " + (s.hidden ?? ""), t, "the rest is behind ⓘ, unchanged")
            } else if !t.hasPrefix("At least ") {
                XCTAssertEqual(s.shown, t, "\(p.id): the level text stays in view whole")
                XCTAssertNil(s.hidden)
            }
        }
    }

    @MainActor func testRegionalFinderPromptIsOneLine() {
        XCTAssertEqual(RegionalFinderView.prompt, "Tap or drag over the operative area.")
        XCTAssertEqual(RegionalFinderView.emptyState, "Mark an area to see options.")
    }

    // MARK: Infusions

    @MainActor func testInfusionsPumpCautionComesFromTheFooter() {
        XCTAssertEqual(InfusionsView.pumpCaution, "Check your pump's concentration before programming a rate.")
    }

    // MARK: ABG

    @MainActor func testAbgNarrativeBehindInfoExceptEmptyAndNormalCaveat() throws {
        let d = try XCTUnwrap(try bundled().abg)
        let empty = AbgCalc.read(ph: nil, paco2: nil, hco3: nil, data: d)
        let normal = AbgCalc.read(ph: 7.40, paco2: 40, hco3: 24, data: d)
        let acid = AbgCalc.read(ph: 7.28, paco2: 30, hco3: 14, data: d)
        XCTAssertEqual(AbgView.explanationParts(empty).kept, empty.explanation, "the empty gas keeps its instruction")
        XCTAssertNil(AbgView.explanationParts(empty).hidden)
        let n = AbgView.explanationParts(normal)
        XCTAssertEqual(n.kept, "A metabolic acidosis and alkalosis that cancel out can still hide behind a normal gas.")
        XCTAssertEqual(n.hidden, "pH, PaCO₂ and HCO₃ are all in the normal range.")
        let a = AbgView.explanationParts(acid)
        XCTAssertNil(a.kept)
        XCTAssertEqual(a.hidden, acid.explanation, "the whole narrative is behind ⓘ, unchanged")
        XCTAssertFalse(acid.steps.isEmpty, "the steps stay in view under the strip")
    }

    // MARK: Coordinator fixes (population cautions in view)

    @MainActor func testFastingScopeAndDifficultAirwaySummaryStayInView() throws {
        let b = try bundled()
        let fasting = try XCTUnwrap(b.quickrefs.first { $0.id == "asa-fasting" })
        let scope = try XCTUnwrap(QuickRefView.scopeLines[fasting.id])
        XCTAssertTrue(fasting.summary.lowercased().contains(scope.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))),
                      "the scope line is the summary's own words")
        XCTAssertFalse(QuickRefView.summaryInView(fasting))
        let airway = try XCTUnwrap(b.quickrefs.first { $0.id == "asa-difficult-airway" })
        XCTAssertTrue(QuickRefView.summaryInView(airway), "Difficult Airway keeps its summary in view")
        XCTAssertEqual(LocalAnestheticView.volumePlaceholder, "Volume")
    }
}
