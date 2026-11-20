import XCTest
@testable import PeriopSignal

/// 1.12, Ben, Nov 20 (after an outside review): a feed post says once, right under the headline's meta line, what it was
/// written from; the footnote under the limitations and the "from the paper" footer are gone; the card's glance line shows
/// up to three lines. These tests cover the rules; where the line sits on the page needs a screen (shots 1380 to 1389).
final class FeedBasis114Tests: XCTestCase {
    private func post(basis: String, limitations: [String] = []) -> Post {
        Post(id: "t", date: "2026-10-01", journal: "JAMA", jshort: "JAMA", kind: "RCT", topics: ["cardiac"], headline: "H", summary: "S",
             takeHome: ["t"], deepDive: "d", url: "https://doi.org/10.1/x", impact: 2, authorLimitations: limitations, authorBasis: basis)
    }

    // MARK: The line under the headline

    func testLineForEachBasis() {
        XCTAssertEqual(PostBasis.line(for: "abstract"), "Written from the abstract")
        XCTAssertEqual(PostBasis.line(for: "full text"), "Written from the full text")
        XCTAssertEqual(PostBasis.line(for: "summary page"), "Written from the publisher’s summary page")
    }

    func testEmptyAndUnknownBasisShowNothing() {
        XCTAssertNil(PostBasis.line(for: ""))
        XCTAssertNil(PostBasis.line(for: "poster"))
        // Only the three values the feed writes count: no guessing at spelling or case.
        XCTAssertNil(PostBasis.line(for: "Abstract"))
        XCTAssertNil(PostBasis.line(for: "full-text"))
        XCTAssertNil(PostBasis.line(for: " abstract"))
    }

    func testPostBasisLineFollowsItsBasisWithOrWithoutLimitations() {
        XCTAssertEqual(post(basis: "abstract").basisLine, "Written from the abstract")
        // A guideline with no author limitations still says what it was written from.
        XCTAssertEqual(post(basis: "summary page", limitations: []).basisLine, "Written from the publisher’s summary page")
        XCTAssertEqual(post(basis: "full text", limitations: ["Open label."]).basisLine, "Written from the full text")
        XCTAssertNil(post(basis: "").basisLine)
    }

    func testSampleAndFixtureFeed() throws {
        XCTAssertEqual(Post.sample.basisLine, "Written from the abstract")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "posts-sample", withExtension: "json"))
        let feed = try FeedLoader.decode(try Data(contentsOf: url))
        for p in feed.posts {
            XCTAssertEqual(p.basisLine == nil, p.authorBasis.isEmpty, "\(p.id): a line exactly when there is a basis")
        }
    }

    // MARK: The footer

    func testFooterNoLongerSaysThePaperWasRead() {
        for basis in ["abstract", "full text", "summary page", ""] {
            let text = PostBasis.footer(basis: basis, added: "Nov 20, 2026")
            XCTAssertFalse(text.contains("from the paper"), basis)
            XCTAssertFalse(text.contains("society pages"), basis)
            XCTAssertTrue(text.contains("source named above"), basis)
            XCTAssertTrue(text.contains("then checked against the source link"), basis)
            XCTAssertTrue(text.contains("Confirm details against the paper before changing practice."), basis)
            XCTAssertTrue(text.hasSuffix("Added to the feed Nov 20, 2026."), basis)
        }
    }

    func testFooterPointsToTheLineOnlyWhenThereIsOne() {
        XCTAssertTrue(PostBasis.footer(basis: "abstract", added: "x").contains("the line under the headline says what was read"))
        XCTAssertFalse(PostBasis.footer(basis: "", added: "x").contains("line under the headline"))
        XCTAssertFalse(PostBasis.footer(basis: "poster", added: "x").contains("line under the headline"))
    }

    // MARK: The card

    func testCompactGlanceShowsThreeLines() {
        XCTAssertEqual(GlanceStrip.compactLineLimit, 3)
    }

    func testGlanceFieldOrderIsUnchanged() {
        // The result stays last; the card gets more room, not a new order.
        let g = Glance(design: "RCT", n: "100 adults", outcome: "Mortality", result: "No difference")
        XCTAssertEqual(g.rows.map { $0.label }, ["Design", "Population", "Outcome", "Result"])
    }
}
