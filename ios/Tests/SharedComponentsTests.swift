import XCTest
import SwiftUI
@testable import PeriopSignal

/// 1.8.1 wave 1 (shared components): explanations sit behind ⓘ on the header they explain, so the closed views take
/// no extra room for them, and a tool's title stays on one line. Measured by rendering at a phone's width.
final class SharedComponentsTests: XCTestCase {
    private static let width: CGFloat = 350

    @MainActor private func height<V: View>(_ view: V) -> CGFloat {
        let r = ImageRenderer(content: view.frame(width: Self.width))
        r.proposedSize = ProposedViewSize(width: Self.width, height: nil)
        return r.uiImage?.size.height ?? -1
    }

    private let longNote = "The suggestion is the highest class among the ASA's published examples (adult, pediatric under 18, and obstetric) that match what is recorded; the class is a clinical judgment, so it counts only once you choose it."

    // MARK: ToolHeader (S5)

    @MainActor func testToolHeaderTitleStaysOnOneLine() {
        let short = height(ToolHeader(eyebrow: "Emergency checklist", title: "LAST", summary: "Stop the injection.", infoSummary: true))
        let long = height(ToolHeader(eyebrow: "Emergency checklist", title: "Local Anesthetic Systemic Toxicity Management", summary: "Stop the injection.", infoSummary: true))
        XCTAssertGreaterThan(short, 0)
        // Shrinking to 80% can make the line a little shorter; a second line would add about 30 points.
        XCTAssertLessThanOrEqual(long, short + 1, "a long title shrinks or truncates on one line instead of wrapping")
    }

    @MainActor func testToolHeaderSummaryBehindInfoUnlessEmergency() {
        let bare = height(ToolHeader(eyebrow: "Regional", title: "Fasting", summary: nil))
        let behind = height(ToolHeader(eyebrow: "Regional", title: "Fasting", summary: longNote, infoSummary: true))
        let shown = height(ToolHeader(eyebrow: "Emergency checklist", title: "MH", summary: longNote, infoSummary: false))
        XCTAssertEqual(behind, bare, accuracy: 2, "the summary is hidden behind ⓘ until tapped")
        XCTAssertGreaterThan(shown, bare + 30, "an emergency checklist keeps its summary in view")
    }

    // MARK: SectionHeader (S1) and PatientGroup (S2)

    @MainActor func testSectionHeaderWithoutInfoIsThePlainEyebrow() {
        let plain = height(SectionHeader(title: "Mallampati", info: nil))
        let empty = height(SectionHeader(title: "Mallampati", info: ""))
        let closed = height(SectionHeader(title: "Mallampati", info: longNote))
        XCTAssertEqual(empty, plain, accuracy: 0.5)
        // The ⓘ may stand a point or two taller than the eyebrow's text; an open note would add several lines.
        XCTAssertLessThan(closed, plain + 6, "the explanation stays closed until the ⓘ is tapped")
    }

    @MainActor func testPatientGroupNoteAddsNoRowUnderTheCard() {
        let row = { Text("ASA III").padding(14) }
        let without = height(PatientGroup(title: "ASA physical status", content: row))
        let with = height(PatientGroup(title: "ASA physical status", note: longNote, content: row))
        XCTAssertLessThan(with, without + 6, "the note sits behind the title's ⓘ, not on an Explanation & Evidence row")
        // Untitled groups have no header to carry the ⓘ, so they keep the row under the card.
        let untitled = height(PatientGroup(title: nil, content: row))
        let untitledNote = height(PatientGroup(title: nil, note: longNote, content: row))
        XCTAssertGreaterThan(untitledNote, untitled + 10)
    }

    // MARK: PatientPresetRow (S3)

    @MainActor func testPresetCaptionIsBehindInfo() {
        let shortCaption = height(PatientPresetRow(title: "Exam normal", caption: "Sets the exam.", applied: false) {})
        let longCaption = height(PatientPresetRow(title: "Exam normal", caption: longNote, applied: false) {})
        XCTAssertEqual(longCaption, shortCaption, accuracy: 2, "what the preset sets opens from its ⓘ")
    }

    // MARK: WeightField (S4)

    func testWeightNotesStayShort() {
        // The per-kg prompt is a safety line that must fit one phone line; the clearing note moved behind ⓘ.
        XCTAssertLessThanOrEqual(WeightField.perKgPrompt.count, 48)
        XCTAssertTrue(WeightField.perKgPrompt.contains("per kg"))
        XCTAssertFalse(WeightField.clearNote.isEmpty)
    }
}
