import SwiftUI
import UIKit
#if DEBUG
import PDFKit
#endif

// MARK: - 1.12 sharing a summary as an image or a PDF (Ben, Nov 10)
//
// The Share button on both summaries offers, in this order, "Image" (the first item), "PDF" and "Text only"; Copy stays plain
// text. An image is the summary as it looks on screen (the same block views: headings, red alerts, the labs, the lines
// diagram under "Lines & devices") on a white page, always in the light appearance, at phone width: PNG pages of a phone's
// height (390 x 844 pt, 1170 x 2532 px at 3x). A page breaks only BETWEEN blocks, never inside one; a block taller than a
// page gets a page of its own that runs as tall as it needs. Each page has a small footer ("Periop Signal · page 2 of 3 ·
// generated 10:42") and nothing that names the patient beyond what the summary already holds. The PDF is the same layout
// on US Letter width pages, blocks kept whole across the page breaks. ImageRenderer draws both, on the main actor.

/// What the Share button offers, in the order of its menu.
enum BriefShareFormat: CaseIterable, Equatable {
    case image, pdf, text

    var title: String {
        switch self {
        case .image: return "Image"
        case .pdf: return "PDF"
        case .text: return "Text only"
        }
    }

    var icon: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .text: return "text.alignleft"
        }
    }
}

enum BriefPages {
    /// A page's measures, in points.
    struct Geometry: Equatable {
        var width: CGFloat
        var height: CGFloat
        /// Left, right and top.
        var margin: CGFloat
        /// Under the last block: the footer and the room around it.
        var bottom: CGFloat
        /// Between blocks.
        var spacing: CGFloat

        /// What a page's blocks may fill (a little less than the measures give, so a rounding never clips a line).
        var available: CGFloat { height - margin - bottom - 2 }

        /// A phone's screen: 390 x 844 pt, 1170 x 2532 px at 3x.
        static let phone = Geometry(width: 390, height: 844, margin: 20, bottom: 36, spacing: 12)
        /// US Letter.
        static let letter = Geometry(width: 612, height: 792, margin: 36, bottom: 48, spacing: 14)

        /// The page's height: the usual one, or taller for a block that does not fit a page.
        func pageHeight(body: CGFloat, oversize: Bool) -> CGFloat {
            oversize ? max(height, margin + body + bottom + 2) : height
        }
    }

    /// The blocks (by index) on one page, and how tall they stand together.
    struct Page: Equatable {
        var blocks: [Int]
        var bodyHeight: CGFloat
        /// One block, taller than a page, on a page of its own.
        var oversize: Bool
    }

    /// Fills pages in order: a block goes on the page being filled while it fits, else starts the next; one taller than a
    /// page gets a page of its own. Pages break between blocks only.
    static func paginate(_ heights: [CGFloat], available: CGFloat, spacing: CGFloat) -> [Page] {
        var pages: [Page] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for (i, h) in heights.enumerated() {
            if h > available {
                if !current.isEmpty { pages.append(Page(blocks: current, bodyHeight: used, oversize: false)); current = []; used = 0 }
                pages.append(Page(blocks: [i], bodyHeight: h, oversize: true))
                continue
            }
            let added = current.isEmpty ? h : spacing + h
            if used + added > available {
                pages.append(Page(blocks: current, bodyHeight: used, oversize: false))
                current = [i]
                used = h
            } else {
                current.append(i)
                used += added
            }
        }
        if !current.isEmpty { pages.append(Page(blocks: current, bodyHeight: used, oversize: false)) }
        return pages
    }

    /// "Periop Signal · page 2 of 3 · generated 10:42".
    static func footer(page: Int, of total: Int, now: Date) -> String {
        "Periop Signal · page \(page) of \(total) · generated " + PatientSummary.time(now, now: now)
    }

    /// One page to draw.
    struct Sheet {
        var blocks: [SummaryBlock]
        var height: CGFloat
        var footer: String
    }

    /// What the blocks are drawn with: the record (the lines diagram), the stores the block views read, and the body figure
    /// the diagram is drawn on (the reference's, taken when Share is tapped; none draws the list alone, as on screen before
    /// the reference has loaded).
    struct Context {
        var record: PatientRecord
        var refs: ReferenceStore
        var patient: PatientStore
        var figure: RegionalFigure?
    }

    // MARK: Drawing

    /// The blocks as they look on screen, at `width`, in the light appearance and the standard text size.
    @MainActor private static func column(_ blocks: [SummaryBlock], _ ctx: Context, width: CGFloat, spacing: CGFloat) -> some View {
        BriefColumn(blocks: blocks, record: ctx.record, spacing: spacing)
            .frame(width: width, alignment: .topLeading)
            .environment(ctx.refs)
            .environment(ctx.patient)
            .environment(\.briefFigure, ctx.figure)
            .environment(\.briefOnPage, true)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
    }

    /// How tall the blocks stand at `width`.
    @MainActor static func height(of blocks: [SummaryBlock], _ ctx: Context, width: CGFloat, spacing: CGFloat) -> CGFloat {
        let renderer = ImageRenderer(content: column(blocks, ctx, width: width, spacing: spacing).fixedSize(horizontal: false, vertical: true))
        var h: CGFloat = 0
        renderer.render { size, _ in h = size.height }
        return h
    }

    /// The summary laid out in pages.
    @MainActor static func sheets(_ blocks: [SummaryBlock], _ ctx: Context, geo: Geometry, now: Date = Date()) -> [Sheet] {
        let inner = geo.width - 2 * geo.margin
        let heights = blocks.map { height(of: [$0], ctx, width: inner, spacing: geo.spacing) }
        let pages = paginate(heights, available: geo.available, spacing: geo.spacing)
        return pages.enumerated().map { entry in
            Sheet(blocks: entry.element.blocks.map { blocks[$0] },
                  height: geo.pageHeight(body: entry.element.bodyHeight, oversize: entry.element.oversize),
                  footer: footer(page: entry.offset + 1, of: pages.count, now: now))
        }
    }

    @MainActor private static func sheetView(_ s: Sheet, _ ctx: Context, geo: Geometry) -> some View {
        BriefSheet(blocks: s.blocks, record: ctx.record, footer: s.footer, geo: geo, height: s.height)
            .environment(ctx.refs)
            .environment(ctx.patient)
            .environment(\.briefFigure, ctx.figure)
            .environment(\.briefOnPage, true)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
    }

    /// The summary as PNG pages: 1170 x 2532 px (390 x 844 pt at 3x), taller for a block that is taller than a page.
    @MainActor static func images(_ blocks: [SummaryBlock], _ ctx: Context, now: Date = Date()) -> [UIImage] {
        let geo = Geometry.phone
        return sheets(blocks, ctx, geo: geo, now: now).compactMap { s in
            let renderer = ImageRenderer(content: sheetView(s, ctx, geo: geo))
            renderer.scale = 3
            return renderer.uiImage
        }
    }

    /// The summary as one PDF, US Letter width, blocks whole across the page breaks (vector text); nil with nothing to draw.
    @MainActor static func pdf(_ blocks: [SummaryBlock], _ ctx: Context, now: Date = Date()) -> Data? {
        let geo = Geometry.letter
        let all = sheets(blocks, ctx, geo: geo, now: now)
        guard !all.isEmpty else { return nil }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var first = CGRect(x: 0, y: 0, width: geo.width, height: geo.height)
        guard let pdf = CGContext(consumer: consumer, mediaBox: &first, nil) else { return nil }
        for s in all {
            var box = CGRect(x: 0, y: 0, width: geo.width, height: s.height)
            let boxData = withUnsafeBytes(of: &box) { Data($0) }
            pdf.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
            ImageRenderer(content: sheetView(s, ctx, geo: geo)).render { _, draw in draw(pdf) }
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return data as Data
    }

    /// The PDF in a file of its own, named for what it is, for the share sheet; nil when there is nothing to draw.
    @MainActor static func pdfFile(_ blocks: [SummaryBlock], _ ctx: Context, now: Date = Date()) -> URL? {
        guard let data = pdf(blocks, ctx, now: now) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Periop Signal summary.pdf")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }
}

extension HandoffShare {
    /// "Text only": the text (rich for the apps that keep it), closed by the footer; no pictures.
    @MainActor static func textOnlyItems(_ blocks: [SummaryBlock], now: Date = Date()) -> [Any] {
        [TextItem(plain: PatientBriefs.sharedText(blocks, now: now), rich: richText(blocks, footer: PatientBriefs.footer(now)))]
    }
}

// MARK: Views

/// The body figure the lines diagram is drawn on, when the page is drawn for a picture (BriefPages.Context.figure); the
/// diagram on screen takes the reference store's (BriefDiagramList).
struct BriefFigureKey: EnvironmentKey {
    static let defaultValue: RegionalFigure? = nil
}

/// True while a block is drawn for a shared picture or PDF: the small "edited" mark is the screen's and stays off it.
struct BriefOnPageKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var briefFigure: RegionalFigure? {
        get { self[BriefFigureKey.self] }
        set { self[BriefFigureKey.self] = newValue }
    }
    var briefOnPage: Bool {
        get { self[BriefOnPageKey.self] }
        set { self[BriefOnPageKey.self] = newValue }
    }
}

/// The blocks, one under the other, as the summary shows them (read-only: a tap edits nothing in a picture).
private struct BriefColumn: View {
    var blocks: [SummaryBlock]
    var record: PatientRecord
    var spacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(blocks) { b in
                BriefBlockView(record: record, block: b) { _, _ in }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// One page: white, the blocks from the top, the footer at the foot.
private struct BriefSheet: View {
    var blocks: [SummaryBlock]
    var record: PatientRecord
    var footer: String
    var geo: BriefPages.Geometry
    var height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BriefColumn(blocks: blocks, record: record, spacing: geo.spacing)
                .padding(.horizontal, geo.margin)
                .padding(.top, geo.margin)
            Spacer(minLength: 0)
            Text(footer)
                .font(PS.sys(size: 9))
                .foregroundStyle(PS.fg3)
                .padding(.horizontal, geo.margin)
                .padding(.bottom, geo.bottom / 2)
        }
        .frame(width: geo.width, height: height, alignment: .topLeading)
        .background(Color.white)
    }
}

#if DEBUG
/// The PDF's pages as pictures, for the screenshot runs and the tests.
enum PDFDocumentBridge {
    static func document(_ data: Data) -> PDFDocument? { PDFDocument(data: data) }

    static func pages(_ doc: PDFDocument) -> [UIImage] {
        (0..<doc.pageCount).compactMap { i -> UIImage? in
            guard let page = doc.page(at: i) else { return nil }
            let box = page.bounds(for: .mediaBox)
            return page.thumbnail(of: CGSize(width: box.width * 2, height: box.height * 2), for: .mediaBox)
        }
    }
}

/// Screenshot runs: -ps.brief.pages 1 shows the image pages a summary shares, one under the other, each with the id
/// "briefpage1", "briefpage2" ... for -ps.patient.scroll; -ps.brief.pages pdf shows the pages of the PDF it shares.
struct BriefPagesPreview: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    var blocks: [SummaryBlock]
    var mode: String

    private func images(_ figure: RegionalFigure?) -> [UIImage] {
        let ctx = BriefPages.Context(record: patient.record, refs: refs, patient: patient, figure: figure)
        if mode == "pdf" {
            guard let data = BriefPages.pdf(blocks, ctx), let doc = PDFDocumentBridge.document(data) else { return [] }
            return PDFDocumentBridge.pages(doc)
        }
        return BriefPages.images(blocks, ctx)
    }

    var body: some View {
        // The figure is read here, so the pages are drawn again once the reference has loaded.
        let figure = refs.bundle?.regional?.figure
        VStack(alignment: .center, spacing: 10) {
            Eyebrow(text: mode == "pdf" ? "Pages of the PDF" : "Pages of the image").frame(maxWidth: .infinity, alignment: .leading)
            // Each page whole, at 300 pt wide, so the footer shows too.
            ForEach(Array(images(figure).enumerated()), id: \.offset) { i, img in
                Image(uiImage: img).resizable().scaledToFit().frame(width: 300)
                    .overlay(Rectangle().stroke(PS.line2, lineWidth: 1))
                    .id("briefpage\(i + 1)")
            }
            // The end of the last page, for -ps.patient.scroll briefpagesend.
            Color.clear.frame(height: 1).id("briefpagesend")
        }
    }
}
#endif
