import PDFKit
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import PeriopSignal

/// 1.12 follow-up, helper Q (Ben, Nov 12): a summary shared as a picture is ONE picture, as tall as it needs to be and never
/// cut off (the PDF's pages are measured and drawn the same way), and Send Patient presents one share sheet whichever way the
/// AirDrop link switch is set, with the switch on by default. AirDrop itself cannot be exercised in a test or the simulator;
/// these tests cover what the share sheet is given for each activity.
final class Q112Tests: XCTestCase {
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 13, minute: 47))!
    private let sent = Date(timeIntervalSince1970: 1_793_354_400)

    // MARK: Helpers

    private func figure() throws -> RegionalFigure {
        let json = """
        {"figure": {"box": [200, 420], "outline": "M10 10 L190 10 L190 410 L10 410 Z", "head": {"cx": 100, "cy": 30, "rx": 17, "ry": 22}, "landmarks": {},
          "regions": [{"id": "chest", "name": "Anterior chest and breast", "views": {}}]},
         "blocks": [], "map": {"chest": {"blocks": []}}}
        """
        return try JSONDecoder().decode(RegionalData.self, from: Data(json.utf8)).figure
    }

    /// A record like the handoff Ben shared from build 39, with the reference's body figure in the context as the Share button
    /// passes it.
    @MainActor private func bensContext() throws -> BriefPages.Context {
        BriefPages.Context(record: PatientDemo112Dates.share, refs: ReferenceStore(), patient: PatientStore(url: nil), figure: try figure())
    }

    @MainActor private func plainContext(_ r: PatientRecord) -> BriefPages.Context {
        BriefPages.Context(record: r, refs: ReferenceStore(), patient: PatientStore(url: nil))
    }

    private func block(_ blocks: [SummaryBlock], _ key: String, file: StaticString = #filePath, line: UInt = #line) throws -> SummaryBlock {
        try XCTUnwrap(blocks.first { $0.key == key }, "no \(key) block in \(blocks.map(\.key))", file: file, line: line)
    }

    /// Every pixel of an image, as a closure (x, y) -> [r, g, b].
    private func pixels(_ cg: CGImage) throws -> (Int, Int) -> [Int] {
        let width = cg.width, height = cg.height
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let base = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        let data = Array(UnsafeBufferPointer(start: base, count: width * height * 4))
        return { x, y in
            let i = (y * width + x) * 4
            return [Int(data[i]), Int(data[i + 1]), Int(data[i + 2])]
        }
    }

    /// True when the pixel is not (nearly) white.
    private func isInk(_ p: [Int]) -> Bool { p.contains { $0 < 245 } }

    /// The lowest row, in points, that has ink in the columns xs (points) among the rows ys (points); nil when none has.
    private func lowestInk(_ pixel: (Int, Int) -> [Int], per: CGFloat, xs: ClosedRange<CGFloat>, ys: ClosedRange<CGFloat>, height: Int) -> CGFloat? {
        let x0 = Int(xs.lowerBound * per), x1 = Int(xs.upperBound * per)
        var y = min(Int(ys.upperBound * per), height - 1)
        let low = max(Int(ys.lowerBound * per), 0)
        while y >= low {
            if (x0...x1).contains(where: { isInk(pixel($0, y)) }) { return CGFloat(y) / per }
            y -= 1
        }
        return nil
    }

    /// The blocks up to and including the lines block, as the picture of them stands, and where the lines block ends (points
    /// from the top of the picture).
    @MainActor private func throughLines(_ blocks: [SummaryBlock], _ ctx: BriefPages.Context, geo: BriefPages.Geometry) throws
        -> (blocks: [SummaryBlock], bottom: CGFloat) {
        let i = try XCTUnwrap(blocks.firstIndex { $0.key == "lines" }, "no lines block in \(blocks.map(\.key))")
        let upTo = Array(blocks[0...i])
        let inner = geo.width - 2 * geo.margin
        let heights = upTo.map { BriefPages.height(of: [$0], ctx, width: inner, spacing: geo.spacing) }
        return (upTo, geo.margin + heights.reduce(0, +) + geo.spacing * CGFloat(upTo.count - 1))
    }

    private func todos(_ n: Int) -> String {
        (1...n).map { "To do \($0): recheck labs at \(String(format: "%02d", 8 + $0 / 6)):\(String(format: "%02d", ($0 % 6) * 10)) and call with the result." }
            .joined(separator: " ")
    }

    // MARK: 1. The reproduction: Ben's record, the diagram, the page's measures

    @MainActor func testBensRecordHasTheLinesDiagramInItsHandoff() throws {
        let ctx = try bensContext()
        let blocks = PatientBriefs.handoff(ctx.record)
        let lines = try block(blocks, "lines")
        XCTAssertEqual(lines.figure, .diagram(arrivalOnly: false))
        for key in ["allergies", "labs", "lines"] { _ = try block(blocks, key) }
        var plain = ctx
        plain.figure = nil
        let without = BriefPages.height(of: [lines], plain, width: 350, spacing: 12)
        let with = BriefPages.height(of: [lines], ctx, width: 350, spacing: 12)
        XCTAssertGreaterThan(with, without + 60, "the body figure stands beside the list: \(without) -> \(with)")
    }

    /// The diagram's feet are in the picture, just above the gap before the footer: the lines block is drawn at the height it
    /// was measured at (a block drawn taller than measured is what runs off the foot of a page).
    @MainActor func testThePictureShowsTheDiagramsFeetAndNothingOverlapsTheFooter() throws {
        let ctx = try bensContext()
        let geo = BriefPages.Geometry.phone
        // The lines block is the last block here, so the picture ends with it and then the footer. Positions are taken from the
        // foot of the image (the footer's room: its gap, one line of 9-pt text and half the bottom margin), so they do not
        // depend on any measuring.
        let (upTo, _) = try throughLines(PatientBriefs.handoff(ctx.record), ctx, geo: geo)
        let image = try XCTUnwrap(BriefPages.picture(upTo, ctx, now: now))
        let cg = try XCTUnwrap(image.cgImage)
        let per = CGFloat(cg.width) / geo.width
        let pixel = try pixels(cg)
        let end = CGFloat(cg.height) / per
        let footerTop = end - geo.bottom / 2 - 11
        let blockEnd = footerTop - BriefPages.pictureFooterGap
        // The footer is drawn, at the very foot.
        let foot = lowestInk(pixel, per: per, xs: 0...(geo.width - 1), ys: footerTop...(end - 1), height: cg.height)
        XCTAssertNotNil(foot, "the footer is drawn at the foot")
        // The room between the last block and the footer is blank across the whole width: nothing runs down into it.
        let gap = lowestInk(pixel, per: per, xs: 0...(geo.width - 1), ys: (blockEnd + 1)...(footerTop - 2), height: cg.height)
        XCTAssertNil(gap, "nothing is drawn in the gap above the footer: \(gap ?? -1) (block ends at \(blockEnd))")
        // The diagram (192 pt wide at the left margin) reaches down to near the end of its block: the figure is centred in its
        // frame, so its feet are some points above the end, never cut at the top of the footer's gap.
        let feet = lowestInk(pixel, per: per, xs: geo.margin...(geo.margin + 192), ys: (blockEnd - 60)...blockEnd, height: cg.height)
        XCTAssertNotNil(feet, "the feet are in the picture")
        XCTAssertGreaterThanOrEqual(feet ?? 0, blockEnd - 26, "feet at \(feet ?? -1), block ends at \(blockEnd)")
    }

    /// The same check for the PDF's pages (US Letter, drawn with the same blocks and the same measuring).
    @MainActor func testThePDFPageShowsTheDiagramsFeet() throws {
        let ctx = try bensContext()
        let geo = BriefPages.Geometry.letter
        let blocks = PatientBriefs.handoff(ctx.record)
        let sheets = BriefPages.sheets(blocks, ctx, geo: geo, now: now)
        let pageIndex = try XCTUnwrap(sheets.firstIndex { $0.blocks.contains { $0.key == "lines" } })
        let sheet = sheets[pageIndex]
        let inner = geo.width - 2 * geo.margin
        let linesBlock = try block(sheet.blocks, "lines")
        let upTo = Array(sheet.blocks.prefix { $0.key != "lines" }) + [linesBlock]
        let heights = upTo.map { BriefPages.height(of: [$0], ctx, width: inner, spacing: geo.spacing) }
        let bottom = geo.margin + heights.reduce(0, +) + geo.spacing * CGFloat(upTo.count - 1)
        let data = try XCTUnwrap(BriefPages.pdf(blocks, ctx, now: now))
        let pages = PDFDocumentBridge.pages(try XCTUnwrap(PDFDocumentBridge.document(data)))
        XCTAssertEqual(pages.count, sheets.count)
        let cg = try XCTUnwrap(pages[pageIndex].cgImage)
        let per = CGFloat(cg.width) / geo.width
        let pixel = try pixels(cg)
        // The figure is centred in its frame, so its feet are some points above the block's measured end, never below it.
        let feet = lowestInk(pixel, per: per, xs: geo.margin...(geo.margin + 192), ys: (bottom - 60)...(bottom + 1), height: cg.height)
        XCTAssertNotNil(feet, "the feet are on the page")
        XCTAssertGreaterThanOrEqual(feet ?? 0, bottom - 26, "feet at \(feet ?? -1), the block was measured to end at \(bottom)")
        // Nothing of the block runs below the height it was measured at: the room before the next block (14 pt) is blank.
        let below = lowestInk(pixel, per: per, xs: 0...(geo.width - 1), ys: (bottom + 2)...(bottom + geo.spacing - 3), height: cg.height)
        XCTAssertNil(below, "nothing is drawn below the lines block's measured end (\(bottom)): \(below ?? -1)")
    }

    // MARK: 2. One picture

    func testThePictureScaleIsThreeThenTwoThenOneAndStaysUnderTwelveThousandPixels() {
        XCTAssertEqual(BriefPages.pictureScale(forHeight: 0), 3)
        XCTAssertEqual(BriefPages.pictureScale(forHeight: 900), 3)
        XCTAssertEqual(BriefPages.pictureScale(forHeight: 4_000), 3, "4,000 pt at 3x is exactly 12,000 px")
        XCTAssertEqual(BriefPages.pictureScale(forHeight: 4_000.5), 2)
        XCTAssertEqual(BriefPages.pictureScale(forHeight: 6_000), 2, "6,000 pt at 2x is exactly 12,000 px")
        XCTAssertEqual(BriefPages.pictureScale(forHeight: 6_000.5), 1)
        XCTAssertEqual(BriefPages.pictureScale(forHeight: 30_000), 1, "never smaller than 1x: the picture is not cut")
        for h in stride(from: CGFloat(500), through: 6_000, by: 250) {
            XCTAssertLessThanOrEqual(h * BriefPages.pictureScale(forHeight: h), 12_000, "\(h) pt")
        }
        XCTAssertEqual(BriefPages.maxPicturePixels, 12_000)
    }

    func testThePicturesFooterHasNoPageCount() {
        XCTAssertEqual(BriefPages.pictureFooter(now: now), "Periop Signal · generated 13:47")
        XCTAssertFalse(BriefPages.pictureFooter(now: now).contains("page"))
        // The PDF's footer keeps its page count.
        XCTAssertEqual(BriefPages.footer(page: 1, of: 2, now: now), "Periop Signal · page 1 of 2 · generated 13:47")
    }

    func testShareAsPictureIsTheFirstItemAndTheDefault() {
        XCTAssertEqual(BriefShareFormat.allCases.first, .image)
        XCTAssertEqual(BriefShareFormat.image.title, "Share as picture")
        XCTAssertEqual(BriefShareFormat.pdf.title, "PDF")
        XCTAssertEqual(BriefShareFormat.text.title, "Text only")
    }

    /// Short, typical and long: always one image, 390 pt wide, as tall as the content plus the footer.
    @MainActor func testAPictureIsOneImageWholeForShortTypicalAndLongRecords() throws {
        var short = PatientRecord()
        short.ageYears = 60; short.nkda = true
        var long = PatientDemo112Summary.long
        long.disposition = "PACU"
        let records: [(String, BriefPages.Context)] = [("short", plainContext(short)), ("typical", try bensContext()), ("long", plainContext(long))]
        var heights: [String: CGFloat] = [:]
        for (name, ctx) in records {
            let blocks = PatientBriefs.handoff(ctx.record)
            XCTAssertFalse(blocks.isEmpty, name)
            let h = BriefPages.pictureHeight(blocks, ctx, now: now)
            let image = try XCTUnwrap(BriefPages.picture(blocks, ctx, now: now), name)
            let scale = BriefPages.pictureScale(forHeight: h)
            XCTAssertEqual(image.scale, scale, name)
            XCTAssertEqual(image.size.width * image.scale, 390 * scale, name)
            // The picture is drawn at its natural height at the scale it is made at; `h` is measured at 1x, where a line's height
            // is rounded up to a whole point, so it is the same or up to a few tenths of a percent more. Never less than the
            // picture, never much more.
            XCTAssertLessThanOrEqual(image.size.height, h + 0.5, "\(name): the picture is not taller than the content and footer")
            XCTAssertGreaterThanOrEqual(image.size.height, h * 0.99 - 1, "\(name): the picture is as tall as the content and footer")
            // The content and the footer: the blocks as measured, the spacing, the margin, then the footer.
            let geo = BriefPages.Geometry.phone
            let measured = blocks.map { BriefPages.height(of: [$0], ctx, width: geo.width - 2 * geo.margin, spacing: geo.spacing) }
            let content = geo.margin + measured.reduce(0, +) + geo.spacing * CGFloat(blocks.count - 1)
            XCTAssertEqual(h - content, 43, accuracy: 8, "\(name): the footer and its room come after the last block (\(h) vs \(content))")
            heights[name] = h
        }
        let short1 = try XCTUnwrap(heights["short"]), typical = try XCTUnwrap(heights["typical"]), long1 = try XCTUnwrap(heights["long"])
        XCTAssertLessThan(short1, typical)
        XCTAssertLessThan(typical, long1)
        XCTAssertGreaterThan(long1, 844, "the long handoff does not stop at a phone's height")
    }

    @MainActor func testTheTypicalPictureIsWhiteAndInLightWhateverThePhonesAppearance() throws {
        let ctx = try bensContext()
        let image = try XCTUnwrap(BriefPages.picture(PatientBriefs.handoff(ctx.record), ctx, now: now))
        let cg = try XCTUnwrap(image.cgImage)
        let pixel = try pixels(cg)
        XCTAssertEqual(pixel(2, 2), [255, 255, 255])
        XCTAssertEqual(pixel(cg.width - 3, cg.height - 3), [255, 255, 255], "the foot of the picture is white too")
        XCTAssertTrue((0..<cg.height).contains { y in (0..<cg.width).contains { x in pixel(x, y).allSatisfy { $0 < 90 } } }, "dark ink")
    }

    @MainActor func testNothingToDrawGivesNoPicture() throws {
        XCTAssertNil(BriefPages.picture([], try bensContext(), now: now))
    }

    /// A very long record is one 390-pt-wide picture at 1x, as tall as it needs: nothing is cut and nothing is paginated.
    /// The largest picture is therefore 1170 x 12,000 px (content to 4,000 pt), then 780 x 12,000 (to 6,000 pt), then 390 px
    /// wide and as tall as the content.
    @MainActor func testAVeryLongRecordIsStillOnePictureAtOneTimes() throws {
        var found = false
        for n in [400, 1_000, 3_000] {
            var r = PatientDemo112Summary.summary
            r.disposition = "PACU"
            r.todos = todos(n)
            let ctx = plainContext(r)
            let blocks = PatientBriefs.handoff(r)
            let h = BriefPages.pictureHeight(blocks, ctx, now: now)
            if h <= 6_500 { continue }
            found = true
            let image = try XCTUnwrap(BriefPages.picture(blocks, ctx, now: now))
            XCTAssertEqual(image.scale, 1, "taller than 6,000 pt: 1x (\(h) pt)")
            XCTAssertEqual(image.size.width, 390)
            XCTAssertEqual(image.size.height, h, accuracy: 1.5, "the whole of it: \(image.size.height) vs \(h)")
            let cg = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(cg.width, 390)
            XCTAssertEqual(CGFloat(cg.height), h, accuracy: 1.5)
            // The footer is at the very end, after the last block.
            let pixel = try pixels(cg)
            let foot = lowestInk(pixel, per: 1, xs: 0...389, ys: (h - 40)...(h - 1), height: cg.height)
            XCTAssertNotNil(foot, "the footer is drawn at the end of the long picture")
            break
        }
        XCTAssertTrue(found, "a record that long makes a picture taller than 6,000 pt")
    }

    // MARK: 3. The PDF's pages

    /// Each page's blocks, as measured, fit its page; the page is the usual height, or a taller one for a block that does not
    /// fit; and the blocks are in order and whole.
    @MainActor func testThePDFPagesHoldTheirBlocksAndOversizeBlocksGetTallerPages() throws {
        var r = PatientDemo112Summary.summary
        r.disposition = "PACU"
        r.todos = todos(150)
        let ctx = plainContext(r)
        let blocks = PatientBriefs.handoff(r)
        let geo = BriefPages.Geometry.letter
        let inner = geo.width - 2 * geo.margin
        let sheets = BriefPages.sheets(blocks, ctx, geo: geo, now: now)
        XCTAssertEqual(sheets.flatMap { $0.blocks.map(\.key) }, blocks.map(\.key), "whole, in order")
        for (i, s) in sheets.enumerated() {
            let measured = s.blocks.map { BriefPages.height(of: [$0], ctx, width: inner, spacing: geo.spacing) }
            let body = measured.reduce(0, +) + geo.spacing * CGFloat(max(0, s.blocks.count - 1))
            XCTAssertLessThanOrEqual(geo.margin + body + geo.bottom, s.height, "page \(i + 1): the content and the footer fit the page")
            if s.height == geo.height {
                XCTAssertLessThanOrEqual(body, geo.available, "page \(i + 1)")
            }
            XCTAssertTrue(s.footer.hasPrefix("Periop Signal · page \(i + 1) of \(sheets.count) · generated "), s.footer)
        }
        let tall = sheets.filter { $0.height > geo.height }
        XCTAssertEqual(tall.count, 1, "heights: \(sheets.map(\.height))")
        XCTAssertEqual(tall.first?.blocks.map(\.key), ["concerns"])
        XCTAssertTrue(sheets.filter { $0.height <= geo.height }.allSatisfy { $0.height == geo.height })
        // The file has those pages, the tall one with its taller media box.
        let data = try XCTUnwrap(BriefPages.pdf(blocks, ctx, now: now))
        let doc = try XCTUnwrap(CGDataProvider(data: data as CFData).flatMap { CGPDFDocument($0) })
        XCTAssertEqual(doc.numberOfPages, sheets.count)
        for (i, s) in sheets.enumerated() {
            let box = try XCTUnwrap(doc.page(at: i + 1)).getBoxRect(.mediaBox)
            XCTAssertEqual(box.width, geo.width)
            XCTAssertEqual(box.height, s.height, accuracy: 0.5, "page \(i + 1)")
        }
    }

    // MARK: 4. The AirDrop switch: on by default

    private func freshDefaults() -> UserDefaults {
        let suite = "q112-" + UUID().uuidString
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        addTeardownBlock { d.removePersistentDomain(forName: suite) }
        return d
    }

    @MainActor func testAPhoneThatNeverTouchedTheSwitchReadsOnAndOneThatTurnedItOffStaysOff() {
        let key = "ps.send.airDropLink"
        let d = freshDefaults()
        XCTAssertNil(d.object(forKey: key))
        XCTAssertTrue(Preferences.readAirDropLink(d), "no key: on")
        d.set(false, forKey: key)
        XCTAssertFalse(Preferences.readAirDropLink(d), "turned off: stays off")
        d.set(true, forKey: key)
        XCTAssertTrue(Preferences.readAirDropLink(d), "turned on")
        d.removeObject(forKey: key)
        XCTAssertTrue(Preferences.readAirDropLink(d), "back to no key: on")
    }

    @MainActor func testALaunchArgumentArrivesAsTextAndIsRead() {
        let key = "ps.send.airDropLink"
        let d = freshDefaults()
        d.set("0", forKey: key)
        XCTAssertFalse(Preferences.readAirDropLink(d), "-ps.send.airDropLink 0")
        d.set("1", forKey: key)
        XCTAssertTrue(Preferences.readAirDropLink(d), "-ps.send.airDropLink 1")
    }

    @MainActor func testThePreferenceIsOnWithNoKeyAndKeptWhenSwitchedBothWays() {
        let key = "ps.send.airDropLink"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        let prefs = Preferences()
        XCTAssertTrue(prefs.airDropLink, "on for a phone that never touched the switch")
        XCTAssertNil(UserDefaults.standard.object(forKey: key), "reading it writes nothing")
        prefs.airDropLink = false
        XCTAssertFalse(Preferences().airDropLink, "off is kept")
        prefs.airDropLink = true
        XCTAssertTrue(Preferences().airDropLink)
    }

    @MainActor func testTheSwitchsWordsFollowTheSpec() {
        XCTAssertEqual(MoreView.airDropLinkTitle, "AirDrop opens Periop Signal directly")
        XCTAssertFalse(MoreView.airDropLinkTitle.contains("(test)"))
        XCTAssertEqual(MoreView.airDropLinkNote,
                       "Sends the patient by AirDrop as a Periop Signal link, so the receiving phone opens the app without the Files step. Both phones need version 1.12 build 39 or later. Turn this off to AirDrop the file instead. Other ways of sending (Messages) always send the file.")
    }

    // MARK: 5. Send Patient: what the one share sheet is given

    private func packet(room: String? = "OR 12") -> PatientPacket {
        PatientPacket(record: PatientDemo.record, sent: sent, room: room)
    }

    private let others: [UIActivity.ActivityType] = [.message, .mail, .copyToPasteboard, .print, .saveToCameraRoll, UIActivity.ActivityType("com.example.unknown")]

    /// The switch ON: AirDrop gets the link; Messages, Mail, copy, print, anything else and "no activity" get the file.
    func testWithTheSwitchOnAirDropGetsTheLinkAndEverythingElseTheFile() throws {
        let p = packet()
        let item = try XCTUnwrap(PatientShareItem(packet: p, airDropLink: true))
        let vc = UIActivityViewController(activityItems: [], applicationActivities: nil)
        let link = try XCTUnwrap(item.activityViewController(vc, itemForActivityType: .airDrop) as? URL)
        XCTAssertEqual(link.scheme, "periopsignal")
        XCTAssertEqual(try PatientLink.decode(link), p, "the link holds the patient and the case's name")
        XCTAssertEqual(item.activityViewController(vc, dataTypeIdentifierForActivityType: .airDrop), UTType.url.identifier)
        XCTAssertTrue(item.usesLink(.airDrop))
        for other in others {
            let file = try XCTUnwrap(item.activityViewController(vc, itemForActivityType: other) as? URL, other.rawValue)
            XCTAssertTrue(file.isFileURL, other.rawValue)
            XCTAssertEqual(file.lastPathComponent, "Patient handoff.periop", other.rawValue)
            XCTAssertEqual(try Data(contentsOf: file), try p.encoded(), other.rawValue)
            XCTAssertEqual(item.activityViewController(vc, dataTypeIdentifierForActivityType: other), "org.periopsignal.patient", other.rawValue)
            XCTAssertFalse(item.usesLink(other), other.rawValue)
        }
        let none = try XCTUnwrap(item.activityViewController(vc, itemForActivityType: nil) as? URL)
        XCTAssertTrue(none.isFileURL, "no activity named: the file")
        XCTAssertFalse(item.usesLink(nil))
        XCTAssertEqual(item.activityViewController(vc, dataTypeIdentifierForActivityType: nil), "org.periopsignal.patient")
        XCTAssertEqual(try XCTUnwrap(item.activityViewControllerPlaceholderItem(vc) as? URL), item.fileURL, "the placeholder is the file")
    }

    /// The switch OFF: every activity, AirDrop included, gets the FILE: a file URL of the exported type, named for what it is.
    func testWithTheSwitchOffEveryActivityIncludingAirDropGetsTheFile() throws {
        let p = packet()
        let item = try XCTUnwrap(PatientShareItem(packet: p, airDropLink: false))
        XCTAssertNil(item.link, "no link is offered")
        let vc = UIActivityViewController(activityItems: [], applicationActivities: nil)
        for type in [UIActivity.ActivityType.airDrop] + others {
            let file = try XCTUnwrap(item.activityViewController(vc, itemForActivityType: type) as? URL, type.rawValue)
            XCTAssertTrue(file.isFileURL, type.rawValue)
            XCTAssertEqual(file, item.fileURL, type.rawValue)
            XCTAssertEqual(file.lastPathComponent, "Patient handoff.periop", type.rawValue)
            XCTAssertEqual(file.pathExtension, PatientPacket.fileExtension)
            XCTAssertEqual(try PatientPacket.decode(try Data(contentsOf: file)), p, "\(type.rawValue): the file holds the patient and the name")
            XCTAssertEqual(item.activityViewController(vc, dataTypeIdentifierForActivityType: type), "org.periopsignal.patient", type.rawValue)
            XCTAssertFalse(item.usesLink(type), type.rawValue)
        }
        XCTAssertTrue(try XCTUnwrap(item.activityViewController(vc, itemForActivityType: nil) as? URL).isFileURL)
        XCTAssertEqual(item.activityViewController(vc, dataTypeIdentifierForActivityType: nil), "org.periopsignal.patient")
        // What AirDrop is offered: a file URL placeholder, and the exported type, which conforms to public.data.
        XCTAssertEqual(try XCTUnwrap(item.activityViewControllerPlaceholderItem(vc) as? URL), item.fileURL)
        XCTAssertEqual(UTType.periopPatient.identifier, "org.periopsignal.patient")
        XCTAssertTrue(UTType.periopPatient.conforms(to: .data))
        XCTAssertTrue(PatientInbox.handles(item.fileURL), "the receiving app reads it as a patient file")
    }

    /// The default is the switch's default: on.
    func testAnItemMadeWithNoSwitchGivenOffersTheLink() throws {
        let item = try XCTUnwrap(PatientShareItem(packet: packet()))
        XCTAssertNotNil(item.link)
    }

    func testAnOverLongLinkStillFallsBackToTheFileForAirDropWithTheSwitchOn() throws {
        var r = PatientDemo.record
        var x: UInt64 = 0x9E3779B97F4A7C15
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        r.medications = String((0..<90_000).map { _ -> Character in
            x = x &* 6364136223846793005 &+ 1442695040888963407
            return alphabet[Int((x >> 33) % UInt64(alphabet.count))]
        })
        let p = PatientPacket(record: r, sent: sent, room: "OR 12")
        XCTAssertNil(PatientLink.url(for: p))
        let item = try XCTUnwrap(PatientShareItem(packet: p, airDropLink: true))
        XCTAssertNil(item.link)
        let vc = UIActivityViewController(activityItems: [], applicationActivities: nil)
        let file = try XCTUnwrap(item.activityViewController(vc, itemForActivityType: .airDrop) as? URL)
        XCTAssertTrue(file.isFileURL)
        XCTAssertEqual(item.activityViewController(vc, dataTypeIdentifierForActivityType: .airDrop), "org.periopsignal.patient")
    }

    /// The Send Patient button hands the sheet exactly one item, the PatientShareItem, with either switch state (no ShareLink
    /// path any more), and the case's name travels in both.
    @MainActor func testSendPatientAlwaysOpensOneSheetWithAPatientShareItem() throws {
        for on in [true, false] {
            let items = try XCTUnwrap(PatientSendButton.items(record: PatientDemo.record, room: "OR 12", airDropLink: on), "switch \(on)")
            XCTAssertEqual(items.count, 1)
            let item = try XCTUnwrap(items.first as? PatientShareItem, "switch \(on)")
            XCTAssertEqual(item.link != nil, on)
            XCTAssertEqual(item.packet.room, "OR 12", "the case's name still travels")
            let vc = UIActivityViewController(activityItems: [], applicationActivities: nil)
            let forAirDrop = try XCTUnwrap(item.activityViewController(vc, itemForActivityType: .airDrop) as? URL)
            XCTAssertEqual(forAirDrop.isFileURL, !on, "AirDrop: the link when on, the file when off")
            let forMessages = try XCTUnwrap(item.activityViewController(vc, itemForActivityType: .message) as? URL)
            XCTAssertTrue(forMessages.isFileURL, "Messages always gets the file")
            XCTAssertEqual(try PatientPacket.decode(try Data(contentsOf: forMessages)).room, "OR 12")
        }
        let unnamed = try XCTUnwrap(PatientSendButton.items(record: PatientDemo.record, room: nil, airDropLink: false)?.first as? PatientShareItem)
        XCTAssertNil(unnamed.packet.room, "a case with no name sends none")
    }

    func testTheSendFilesAreStillRemovable() throws {
        let item = try XCTUnwrap(PatientShareItem(packet: packet(), airDropLink: false))
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.fileURL.path))
        PatientSendFiles.purge()
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.fileURL.path))
    }
}
