import XCTest
@testable import PeriopSignal

final class FeedDecodingTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "posts-sample", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testDecodesSampleFeed() throws {
        let feed = try FeedLoader.decode(try fixture())
        XCTAssertEqual(feed.name, "Periop Signal")
        XCTAssertEqual(feed.posts.count, 6)
        let first = feed.posts[0]
        XCTAssertFalse(first.headline.isEmpty)
        XCTAssertFalse(first.takeHome.isEmpty)
        XCTAssertTrue(first.topics.allSatisfy { Topics.byID[$0] != nil }, "every topic id maps to a known topic")
    }

    func testOptionalFieldsDefault() throws {
        let json = """
        {"name":"x","generatedAt":"2026-10-20T00:00:00+00:00","posts":[{"id":"a","date":"2026-10-01","journal":"NEJM","jshort":"NEJM","kind":"RCT","topics":["cardiac"],"headline":"H","summary":"S","takeHome":["t"],"deepDive":"d","url":"https://doi.org/10.1/x","impact":2}]}
        """
        let feed = try FeedLoader.decode(Data(json.utf8))
        let p = feed.posts[0]
        XCTAssertEqual(p.addedAt, "2026-10-01")
        XCTAssertEqual(p.authorLimitations, [])
        XCTAssertFalse(p.takeHomeIsAuthors)
        XCTAssertTrue(p.isResearch)
        XCTAssertFalse(p.isLandmark)
    }

    func testMarkdownBlocks() {
        let blocks = MarkdownBlocks.parse("**Why it matters.** One.\n\n- a\n- b\n\n# Head\nPara line one\nline two")
        XCTAssertEqual(blocks.count, 4)
        if case .bullets(let items) = blocks[1] { XCTAssertEqual(items, ["a", "b"]) } else { XCTFail("expected bullets") }
        if case .heading(let h) = blocks[2] { XCTAssertEqual(h, "Head") } else { XCTFail("expected heading") }
        if case .paragraph(let p) = blocks[3] { XCTAssertEqual(p, "Para line one line two") } else { XCTFail("expected paragraph") }
    }

    func testDateDisplay() {
        XCTAssertEqual(PSDate.display("2025-03-07", long: true), "Mar 7, 2025")
        XCTAssertEqual(PSDate.monthTitle("2026-10"), "October 2026")
    }
}
