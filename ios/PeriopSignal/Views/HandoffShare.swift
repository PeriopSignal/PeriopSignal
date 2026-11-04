import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What leaves the phone when the handoff is shared or copied (1.8.3, Ben): the text with its headers and labels styled
/// for the apps that keep formatting, the same text plain for the apps that do not, and the lines diagram as a picture
/// after the text.
enum HandoffShare {
    // MARK: Text

    private static let size: CGFloat = 14

    /// The handoff with its section headers bold and underlined and its labels bold (HandoffStyle); the words are the
    /// plain text's, unchanged.
    static func richText(_ text: String) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: size)])
        let bold = UIFont.boldSystemFont(ofSize: size)
        for s in HandoffStyle.spans(text) {
            let r = NSRange(s.range, in: text)
            out.addAttribute(.font, value: bold, range: r)
            if s.kind == .header { out.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
        }
        return out
    }

    /// The pasteboard entry for Copy: rich text and plain text together, so a rich editor keeps the styling and a
    /// plain field gets the plain text.
    static func pasteboardItem(_ text: String) -> [String: Any] {
        var item: [String: Any] = [UTType.utf8PlainText.identifier: text]
        let rich = richText(text)
        if let rtf = try? rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            item[UTType.rtf.identifier] = rtf
        }
        return item
    }

    static func copy(_ text: String) {
        UIPasteboard.general.setItems([pasteboardItem(text)], options: [:])
    }

    // MARK: The 1.9 briefs (preprocedure summary and handoff)

    /// The brief's rich text: the header line bold and underlined, each block's label (and the label of each line under
    /// it) bold; the words are PatientBriefs.plainText's, unchanged.
    static func richText(_ blocks: [SummaryBlock]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let regular = UIFont.systemFont(ofSize: size)
        let bold = UIFont.boldSystemFont(ofSize: size)
        var first = true
        for b in blocks {
            for line in PatientBriefs.plainLines(b) {
                if !first { out.append(NSAttributedString(string: "\n", attributes: [.font: regular])) }
                let start = out.length
                out.append(NSAttributedString(string: line, attributes: [.font: regular]))
                let indent = line.prefix { $0 == " " }.count
                if b.key == "header" {
                    let r = NSRange(location: start, length: (line as NSString).length)
                    out.addAttribute(.font, value: bold, range: r)
                    out.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
                } else {
                    let body = String(line.dropFirst(indent))
                    if let r = HandoffStyle.labelRange(Substring(body)) {
                        let ns = NSRange(r, in: body)
                        out.addAttribute(.font, value: bold, range: NSRange(location: start + indent + ns.location, length: ns.length))
                    }
                }
                first = false
            }
        }
        return out
    }

    /// Copy: the plain text (the fishbone as one line) with the rich text beside it.
    static func copy(blocks: [SummaryBlock]) {
        UIPasteboard.general.setItems([pasteboardItem(PatientBriefs.plainText(blocks), rich: richText(blocks))], options: [:])
    }

    static func pasteboardItem(_ text: String, rich: NSAttributedString) -> [String: Any] {
        var item: [String: Any] = [UTType.utf8PlainText.identifier: text]
        if let rtf = try? rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            item[UTType.rtf.identifier] = rtf
        }
        return item
    }

    /// What the share sheet is given for a brief: the text (rich for the apps that keep it), then the fishbone as a
    /// picture and the lines diagram with its list as a picture, when the brief has them.
    @MainActor static func briefItems(_ blocks: [SummaryBlock], record: PatientRecord, figure: RegionalFigure?) -> [Any] {
        var out: [Any] = [TextItem(plain: PatientBriefs.plainText(blocks), rich: richText(blocks))]
        out += briefImages(blocks, record: record, figure: figure) as [Any]
        return out
    }

    @MainActor static func briefImages(_ blocks: [SummaryBlock], record: PatientRecord, figure: RegionalFigure?) -> [UIImage] {
        var out: [UIImage] = []
        for b in blocks {
            switch b.figure {
            case .fishbone(let labs)?:
                if let i = fishboneImage(labs) { out.append(i) }
            case .diagram(let arrivalOnly)?:
                if let i = linesImage(record, lines: b.lines, marks: b.marks, arrivalOnly: arrivalOnly, figure: figure) { out.append(i) }
            case nil:
                break
            }
        }
        return out
    }

    /// The fishbone as a picture, drawn in the light appearance on white.
    @MainActor static func fishboneImage(_ labs: BriefLabs) -> UIImage? {
        guard !labs.isEmpty else { return nil }
        let view = FishboneFigure(labs: labs)
            .padding(14)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }

    /// The lines diagram with its list on the right, as a picture; nil when nothing is drawn on the diagram.
    @MainActor static func linesImage(_ record: PatientRecord, lines: [String], marks: [String], arrivalOnly: Bool, figure: RegionalFigure?) -> UIImage? {
        guard let figure else { return nil }
        let m = PatientDiagramModel.items(record, phase: arrivalOnly ? .preop : .all)
        guard !m.items.isEmpty else { return nil }
        let view = BriefDiagramLayout(figure: figure, items: m.items, cart: m.cart, lines: lines, marks: marks, scale: 1, listFont: 13)
            .frame(width: 440)
            .padding(12)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }

    /// Mail, Notes and the pasteboard keep formatting; Messages and every other app get the plain text.
    static func takesRichText(_ type: UIActivity.ActivityType?) -> Bool {
        guard let type else { return false }
        return type == .mail || type == .copyToPasteboard || type.rawValue.contains("mobilenotes")
    }

    // MARK: Share sheet

    /// The handoff as one share-sheet item: rich text for the apps that keep it, plain text for the rest.
    final class TextItem: NSObject, UIActivityItemSource {
        let plain: String
        let rich: NSAttributedString
        init(_ text: String) {
            plain = text
            rich = HandoffShare.richText(text)
        }
        /// A brief's text and its rich version (richText(blocks)).
        init(plain: String, rich: NSAttributedString) {
            self.plain = plain
            self.rich = rich
        }
        func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { plain }
        func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
            HandoffShare.takesRichText(activityType) ? rich : plain
        }
    }

    /// What the share sheet is given, in this order: the text, then the lines diagram when there is one.
    static func items(text: String, image: UIImage?) -> [Any] {
        var out: [Any] = [TextItem(text)]
        if let image { out.append(image) }
        return out
    }

    // MARK: The diagram

    /// The lines diagram as a picture, drawn in the light appearance on white so it reads in any app; nil when nothing
    /// is drawn on it. It carries the devices and nothing about the patient.
    @MainActor static func diagramImage(_ record: PatientRecord, figure: RegionalFigure?) -> UIImage? {
        guard let figure else { return nil }
        let m = PatientDiagramModel.items(record, phase: .all)
        guard !m.items.isEmpty else { return nil }
        // The limb alerts are written under the picture (1.9), so the mark on the figure can be read in any app; with
        // none, the picture is the figure alone, as before.
        let canvas = PatientDiagramCanvas(figure: figure, items: m.items, cart: m.cart)
        let groups = PatientDeviceFills.limbAlertGroups(record)
        let content: AnyView = groups.isEmpty ? AnyView(canvas)
            : AnyView(VStack(alignment: .leading, spacing: 8) { canvas; LimbAlertCaption(groups: groups) })
        let view = content
            .frame(width: 360)
            .padding(12)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}
