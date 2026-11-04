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
