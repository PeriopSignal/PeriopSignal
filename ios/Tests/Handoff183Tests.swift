import XCTest
import UIKit
@testable import PeriopSignal

/// 1.8.3 handoff (Ben): no preoperative airway examination in it, bold and underlined headers with bold labels (on the
/// screen, in shared and copied rich text), and the lines diagram as a picture after the shared text.
final class Handoff183Tests: XCTestCase {
    private var demo: PatientRecord { PatientDemo.record }

    // MARK: 1. The airway examination stays out

    func testHandoffLeavesOutTheAirwayExamination() {
        var r = demo
        r.dentition = "Upper partial denture, removed"
        r.airwaySigns = ["mouth", "tmd", "neck40", "thick-neck"]
        r.mask = "easy"
        XCTAssertFalse(PatientAirway.maskRisk(r).isEmpty, "the demo has mask-ventilation predictors on the airway page")
        for (name, t) in [("full", HandoffWriter.text(r)), ("short", HandoffWriter.shortText(r))] {
            for gone in ["Mallampati", "Langeron", "Teeth", "partial denture", "Difficult-airway signs", "Exam:", "Airway exam", "Mouth opening", "thyromental", "Difficult mask"] {
                XCTAssertFalse(t.localizedCaseInsensitiveContains(gone), "\(name) handoff leaves out \(gone)\n\(t)")
            }
        }
        // The course in the room and the airway now stay.
        let full = HandoffWriter.text(r)
        XCTAssertTrue(full.contains("Current airway: Own airway"), full)
        XCTAssertTrue(full.contains("Course: Mask ventilation easy. Intubation easy: video laryngoscope, grade 1, 1 attempt; 7.5 ETT, 23 cm at the lip."), full)
        XCTAssertTrue(HandoffWriter.shortText(r).contains("Airway: Mask ventilation easy. Intubation easy: video laryngoscope, grade 1, 1 attempt"), HandoffWriter.shortText(r))
        // An airway in place on arrival keeps its support line.
        let icu = HandoffWriter.text(PatientDemo.cardiac)
        XCTAssertTrue(icu.contains("Current airway: "), icu)
        XCTAssertTrue(icu.contains("Ventilator: "), icu)
        // The exam is still on the airway page and in the preop card.
        let page = PatientSummary.airwayLines(r)
        XCTAssertTrue(page.contains { $0.text.hasPrefix("Mallampati III") })
        XCTAssertTrue(page.contains { $0.label == "Teeth" })
    }

    func testAirwayHeaderGoesWhenNothingIsLeftUnderIt() {
        var r = PatientRecord()
        r.ageYears = 50; r.sex = .female
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        r.mallampati = 3
        r.airwaySigns = ["neck40"]
        r.dentition = "Loose upper incisor"
        let lines = HandoffWriter.text(r).components(separatedBy: "\n")
        XCTAssertFalse(lines.contains("AIRWAY"), "an examination only: no Airway section")
        XCTAssertFalse(HandoffWriter.text(r).contains("Mallampati"))
        r.currentAirway = "natural"
        XCTAssertTrue(HandoffWriter.text(r).components(separatedBy: "\n").contains("AIRWAY"))
    }

    // MARK: 2. Headers and labels

    private func marked(_ text: String) -> (headers: [String], labels: [String]) {
        let spans = HandoffStyle.spans(text)
        return (spans.filter { $0.kind == .header }.map { String(text[$0.range]) }, spans.filter { $0.kind == .label }.map { String(text[$0.range]) })
    }

    func testStylingMarksHeadersAndLabelsAndNeverATime() {
        let t = """
        ANESTHESIA HANDOFF
        CABG
        67-year-old man
        Baseline: BP 148/86 · HR 72

        LINES & DEVICES (NOW)
        Line: PIV 18 G L AC
        08:20 Induction: propofol
        Events at 08:20: hypotension
        Time: 08:20 started
        3 Nov 09:00: PRBC
        00:00: nothing
        A label that is far too long to be one, really: x
        no colon here
        Plain: 12:30 ok: second colon stays plain

        NPO: solids 8 h
        Note:no space after the colon

        Prepared with Periop Signal, 09:41. Check against the chart.
        """
        let m = marked(t)
        XCTAssertEqual(m.headers, ["ANESTHESIA HANDOFF", "LINES & DEVICES (NOW)"])
        XCTAssertEqual(m.labels, ["Baseline:", "Line:", "Time:", "Plain:", "NPO:"])
    }

    func testStylingOnTheRealHandoffs() {
        let full = HandoffWriter.text(PatientDemo.cardiac)
        let f = marked(full)
        for h in ["ANESTHESIA HANDOFF", "HISTORY", "ASSESSMENT", "AIRWAY", "INTRAOPERATIVE", "PLAN"] where full.contains("\n" + h + "\n") || h == "ANESTHESIA HANDOFF" {
            XCTAssertTrue(f.headers.contains(h), "\(h) is a header")
        }
        XCTAssertTrue(f.headers.contains("LINES & DEVICES"))
        XCTAssertTrue(f.labels.contains("Current airway:"))
        XCTAssertTrue(f.labels.contains("Baseline:") || f.labels.contains("Code status:"))
        XCTAssertFalse(f.labels.contains { $0.first?.isNumber == true }, "no label starts with a digit")
        let short = marked(HandoffWriter.shortText(demo))
        XCTAssertEqual(short.headers, ["ANESTHESIA HANDOFF (SHORT)"])
        XCTAssertTrue(short.labels.contains("Allergies:"))
        XCTAssertTrue(short.labels.contains("Airway:"))
        XCTAssertTrue(short.labels.contains("Plan:"))
    }

    func testStyledTextIsTheSameWords() {
        for t in [HandoffWriter.text(PatientDemo.cardiac), HandoffWriter.shortText(demo), HandoffWriter.text(demo)] {
            XCTAssertEqual(String(handoffStyled(t, marks: []).characters), t)
            XCTAssertEqual(HandoffShare.richText(t).string, t)
        }
    }

    func testRichTextBoldAndUnderline() throws {
        let t = HandoffWriter.shortText(demo)
        let rich = HandoffShare.richText(t)
        func attrs(_ s: String) throws -> (bold: Bool, underlined: Bool) {
            let r = try XCTUnwrap(t.range(of: s))
            let a = rich.attributes(at: NSRange(r, in: t).location, effectiveRange: nil)
            let font = try XCTUnwrap(a[.font] as? UIFont)
            return (font.fontDescriptor.symbolicTraits.contains(.traitBold), (a[.underlineStyle] as? Int ?? 0) != 0)
        }
        let header = try attrs("ANESTHESIA HANDOFF (SHORT)")
        XCTAssertTrue(header.bold && header.underlined, "a header is bold and underlined")
        let label = try attrs("Allergies:")
        XCTAssertTrue(label.bold && !label.underlined, "a label is bold, not underlined")
        let body = try attrs("Penicillin")
        XCTAssertTrue(!body.bold && !body.underlined, "the words after a label are plain")
    }

    // MARK: 3. Copy and share

    func testCopyPutsRichAndPlainOnThePasteboard() throws {
        let t = HandoffWriter.shortText(demo)
        let item = HandoffShare.pasteboardItem(t)
        XCTAssertEqual(item["public.utf8-plain-text"] as? String, t, "the plain text is today's text")
        let rtf = try XCTUnwrap(item["public.rtf"] as? Data)
        let s = String(decoding: rtf, as: UTF8.self)
        XCTAssertTrue(s.hasPrefix("{\\rtf"), "RTF")
        XCTAssertTrue(s.contains("\\ul"), "the headers are underlined")
        XCTAssertTrue(s.contains("\\b"), "and bold")
    }

    func testShareSheetGetsRichForMailAndNotesAndPlainForTheRest() throws {
        let t = HandoffWriter.shortText(demo)
        let item = HandoffShare.TextItem(t)
        let vc = UIActivityViewController(activityItems: [], applicationActivities: nil)
        XCTAssertEqual(item.activityViewControllerPlaceholderItem(vc) as? String, t)
        for rich in [UIActivity.ActivityType.mail, .copyToPasteboard, UIActivity.ActivityType("com.apple.mobilenotes.SharingExtension")] {
            XCTAssertEqual((item.activityViewController(vc, itemForActivityType: rich) as? NSAttributedString)?.string, t, rich.rawValue)
        }
        for plain in [UIActivity.ActivityType.message, .airDrop, .print, UIActivity.ActivityType("com.example.unknown")] {
            XCTAssertEqual(item.activityViewController(vc, itemForActivityType: plain) as? String, t, plain.rawValue)
        }
        XCTAssertEqual(item.activityViewController(vc, itemForActivityType: nil) as? String, t)
    }

    private func figure() throws -> RegionalFigure {
        let json = """
        {"figure": {"box": [200, 420], "outline": "M10 10 L190 10 L190 410 L10 410 Z", "head": {"cx": 100, "cy": 30, "rx": 17, "ry": 22}, "landmarks": {},
          "regions": [{"id": "chest", "name": "Anterior chest and breast", "views": {}}]},
         "blocks": [], "map": {"chest": {"blocks": []}}}
        """
        return try JSONDecoder().decode(RegionalData.self, from: Data(json.utf8)).figure
    }

    func testShareItemsAreTheTextThenTheImage() throws {
        let t = HandoffWriter.text(PatientDemo.cardiac)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }
        let both = HandoffShare.items(text: t, image: image)
        XCTAssertEqual(both.count, 2)
        XCTAssertTrue(both[0] is HandoffShare.TextItem, "the text first")
        XCTAssertTrue(both[1] is UIImage, "then the picture")
        let textOnly = HandoffShare.items(text: t, image: nil)
        XCTAssertEqual(textOnly.count, 1)
        XCTAssertTrue(textOnly[0] is HandoffShare.TextItem)
    }

    @MainActor func testDiagramImageOnlyWhenSomethingIsDrawn() throws {
        let fig = try figure()
        XCTAssertNil(HandoffShare.diagramImage(PatientRecord(), figure: fig), "nothing on the diagram: no picture")
        XCTAssertNil(HandoffShare.diagramImage(PatientDemo.cardiac, figure: nil), "no figure loaded: no picture")
        let image = try XCTUnwrap(HandoffShare.diagramImage(PatientDemo.cardiac, figure: fig))
        XCTAssertEqual(image.size.width, 384, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 584, accuracy: 0.5)
        // White at the edge, whatever the phone's appearance.
        let cg = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(cg.dataProvider?.data)
        let bytes = CFDataGetBytePtr(data)!
        XCTAssertGreaterThan(Int(bytes[0]) + Int(bytes[1]) + Int(bytes[2]), 3 * 250, "a white corner")
    }
}
