import SwiftUI
import UIKit
#if DEBUG
import PDFKit
#endif

// MARK: - 1.12 sharing a summary as an image or a PDF (Ben, Nov 10)
//
// The Share button on both summaries offers, in this order, "Share as picture" (the first item), "PDF" and "Text only"; Copy
// stays plain text. A picture is the summary as it looks on screen (the same block views: headings, red alerts, the labs, the
// lines diagram under "Lines & devices") on a white page, always in the light appearance, at phone width (390 pt): ONE picture of
// the whole summary, as tall as it needs to be (1.12, Ben: pages were cut off in Photos and the viewer's controls covered the
// foot of a page; people zoom to read), the blocks in order and a small footer after the last one ("Periop Signal · generated
// 10:42", no page count). It is drawn at its natural height, so there is no page whose height a block could outgrow. Scale 3x
// (1170 px wide) unless that would be taller than 12,000 px, then 2x, then 1x, so it stays an image every app accepts. The PDF
// is the same layout on US Letter width pages, blocks kept whole across the page breaks (an oversize block on a taller page),
// each with the footer "Periop Signal · page 2 of 3 · generated 10:42". ImageRenderer draws both, on the main actor.
//
// Why Ben's build 39 picture looked cut off (Nov 12): it was one 390 x 844 pt page, the shape of the phone's screen, and the
// viewer (Photos, or Messages' quick look) draws its own controls over such a picture: the grey bar at the top, and at the
// foot the zoom and reply pill and the share button, which are opaque. In his screenshot the right foot's sole line is drawn
// at 775.7 pt, the pill's top edge is at 771 pt and covers the left foot, the page's footer text is at 822 pt and the page is
// 844 pt: the diagram was complete on the page (its frame ends at about 787 pt) and the controls stood over it. The measuring
// and the drawing agree (the blocks are rigid in height and both are fixed at their ideal height), which the tests in
// Q112Tests check on the diagram's page and on every page of a long PDF. The picture is now one image of the whole summary,
// so no page-shaped picture sits under a viewer's controls, and people zoom (or hide the controls) to read.

/// What the Share button offers, in the order of its menu.
enum BriefShareFormat: CaseIterable, Equatable {
    case image, pdf, text

    var title: String {
        switch self {
        case .image: return "Share as picture"
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

        /// The picture's measures: 390 pt wide (1170 px at 3x); its height is whatever the blocks need (the 844 is a phone's
        /// height and is not used by the picture).
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

    // MARK: The picture

    /// The tallest picture, in pixels, a share makes at its first scale; taller steps down to the next scale.
    static let maxPicturePixels: CGFloat = 12_000
    /// The scales a picture is drawn at, in order of preference.
    static let pictureScales: [CGFloat] = [3, 2, 1]
    /// Points between the last block and the footer.
    static let pictureFooterGap: CGFloat = 14

    /// 3x unless the picture would be taller than 12,000 px, then 2x, then 1x (used however tall, as the picture cannot be
    /// made smaller without cutting it). So a picture is at most 1170 x 12,000 px (content up to 4,000 pt), then 780 x
    /// 12,000 px (up to 6,000 pt), then 390 px wide and as tall as the content.
    static func pictureScale(forHeight height: CGFloat) -> CGFloat {
        pictureScales.first { height * $0 <= maxPicturePixels } ?? 1
    }

    /// "Periop Signal · generated 10:42": the picture's footer (no page count: it is one picture).
    static func pictureFooter(now: Date) -> String {
        "Periop Signal · generated " + PatientSummary.time(now, now: now)
    }

    @MainActor private static func pictureView(_ blocks: [SummaryBlock], _ ctx: Context, geo: Geometry, now: Date) -> some View {
        BriefPicture(blocks: blocks, record: ctx.record, footer: pictureFooter(now: now), geo: geo)
            .environment(ctx.refs)
            .environment(ctx.patient)
            .environment(\.briefFigure, ctx.figure)
            .environment(\.briefOnPage, true)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
    }

    /// How tall the picture stands, in points: the blocks, the margins and the footer, at their natural height.
    @MainActor static func pictureHeight(_ blocks: [SummaryBlock], _ ctx: Context, now: Date = Date()) -> CGFloat {
        let renderer = ImageRenderer(content: pictureView(blocks, ctx, geo: .phone, now: now))
        var h: CGFloat = 0
        renderer.render { size, _ in h = size.height }
        return h
    }

    /// The summary as ONE picture: 390 pt wide, as tall as its blocks and footer need, never paginated and never cut; nil with
    /// nothing to draw.
    @MainActor static func picture(_ blocks: [SummaryBlock], _ ctx: Context, now: Date = Date()) -> UIImage? {
        guard !blocks.isEmpty else { return nil }
        let height = pictureHeight(blocks, ctx, now: now)
        guard height > 0 else { return nil }
        let renderer = ImageRenderer(content: pictureView(blocks, ctx, geo: .phone, now: now))
        renderer.scale = pictureScale(forHeight: height)
        return renderer.uiImage
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
                // The blocks stand at the height they were measured at (BriefPages.height(of:) fixes the vertical size the
                // same way), so a page never squeezes or clips them.
                .fixedSize(horizontal: false, vertical: true)
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

/// The whole picture: white, the blocks from the top, the footer after the last one; its height is the content's.
private struct BriefPicture: View {
    var blocks: [SummaryBlock]
    var record: PatientRecord
    var footer: String
    var geo: BriefPages.Geometry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BriefColumn(blocks: blocks, record: record, spacing: geo.spacing)
                .padding(.horizontal, geo.margin)
                .padding(.top, geo.margin)
            Text(footer)
                .font(PS.sys(size: 9))
                .foregroundStyle(PS.fg3)
                .padding(.horizontal, geo.margin)
                .padding(.top, BriefPages.pictureFooterGap)
                .padding(.bottom, geo.bottom / 2)
        }
        .frame(width: geo.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
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

/// Screenshot runs: -ps.brief.menu 1 lists the Share menu's items as the menu shows them, in order.
struct BriefShareMenuPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "The Share menu").frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
            ForEach(Array(BriefShareFormat.allCases.enumerated()), id: \.offset) { i, f in
                Label(f.title, systemImage: f.icon)
                    .font(PS.sys(size: 16)).foregroundStyle(PS.fg)
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if i < BriefShareFormat.allCases.count - 1 { Divider() }
            }
        }
        .padding(14)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }
}

/// Screenshot runs: -ps.brief.pages 1 shows the ONE picture a summary shares, at the screen's width, with the id "briefpage1"
/// (its top) and "briefpagesend" (under it) for -ps.patient.scroll; -ps.brief.pages fit shows the whole of it scaled to
/// one screen's height; -ps.brief.pages tail shows its last 470 pt; -ps.brief.pages pdf shows the pages of the PDF it shares, "briefpage1", "briefpage2" ....
struct BriefPagesPreview: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    var blocks: [SummaryBlock]
    var mode: String

    private func context(_ figure: RegionalFigure?) -> BriefPages.Context {
        BriefPages.Context(record: patient.record, refs: refs, patient: patient, figure: figure)
    }

    private func pdfPages(_ figure: RegionalFigure?) -> [UIImage] {
        guard let data = BriefPages.pdf(blocks, context(figure)), let doc = PDFDocumentBridge.document(data) else { return [] }
        return PDFDocumentBridge.pages(doc)
    }

    @ViewBuilder private func pdfView(_ figure: RegionalFigure?) -> some View {
        // Each page whole, at 300 pt wide, so the footer shows too.
        ForEach(Array(pdfPages(figure).enumerated()), id: \.offset) { i, img in
            Image(uiImage: img).resizable().scaledToFit().frame(width: 300)
                .overlay(Rectangle().stroke(PS.line2, lineWidth: 1))
                .id("briefpage\(i + 1)")
        }
    }

    @ViewBuilder private func pictureView(_ figure: RegionalFigure?) -> some View {
        if let img = BriefPages.picture(blocks, context(figure)) {
            if mode == "fit" {
                Image(uiImage: img).resizable().scaledToFit().frame(height: 600)
                    .overlay(Rectangle().stroke(PS.line2, lineWidth: 1))
                    .id("briefpage1")
            } else if mode == "tail" {
                // Only the foot of the picture (the last 470 pt of it, at 358 pt wide): the lines diagram's feet and the footer.
                Image(uiImage: img).resizable().scaledToFit().frame(width: 358)
                    .frame(height: 470, alignment: .bottom).clipped()
                    .overlay(Rectangle().stroke(PS.line2, lineWidth: 1))
                    .id("briefpage1")
            } else {
                // Close to the picture's own width (390 pt), as Photos shows it before any zoom.
                Image(uiImage: img).resizable().scaledToFit().frame(width: 358)
                    .overlay(Rectangle().stroke(PS.line2, lineWidth: 1))
                    .id("briefpage1")
            }
        }
    }

    var body: some View {
        // The figure is read here, so the picture is drawn again once the reference has loaded.
        let figure = refs.bundle?.regional?.figure
        VStack(alignment: .center, spacing: 10) {
            Eyebrow(text: mode == "pdf" ? "Pages of the PDF" : "The picture").frame(maxWidth: .infinity, alignment: .leading)
            if mode == "pdf" { pdfView(figure) } else { pictureView(figure) }
            // The end of the last page, for -ps.patient.scroll briefpagesend.
            Color.clear.frame(height: 1).id("briefpagesend")
        }
    }
}
#endif
