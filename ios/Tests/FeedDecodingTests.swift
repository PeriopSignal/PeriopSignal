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
        XCTAssertNil(p.glance)
        XCTAssertNil(p.quiz)
        XCTAssertNil(p.citation)
        XCTAssertEqual(p.doi, "10.1/x")
    }

    func testDecodesGlanceQuizCitation() throws {
        let json = """
        {"name":"x","generatedAt":"2026-10-20T00:00:00+00:00","posts":[{"id":"a","date":"2026-10-01","journal":"JAMA","jshort":"JAMA","kind":"RCT","topics":["criticalCare"],"headline":"H","summary":"S","takeHome":["t"],"deepDive":"d","url":"https://doi.org/10.1001/jama.1","impact":3,
          "glance":{"design":"RCT","n":"100 adults","outcome":"Mortality","result":"No difference"},
          "quiz":{"question":"What happened to mortality?","options":["Up","Down","Same","Unknown"],"answer":2,"explanation":"No difference was found in the trial."},
          "title":"Paper title","citation":{"title":"Paper title","authors":["Smith AB","Jones C"],"journal":"JAMA","year":2026,"volume":"1","issue":"2","pages":"3-4","doi":"10.1001/jama.1"}}]}
        """
        let p = try FeedLoader.decode(Data(json.utf8)).posts[0]
        XCTAssertEqual(p.glance?.rows.count, 4)
        XCTAssertEqual(p.quiz?.answer, 2)
        XCTAssertEqual(p.citation?.authors.count, 2)
        XCTAssertEqual(p.amaCitation, "Smith AB, Jones C. Paper title. JAMA. 2026;1(2):3-4. doi:10.1001/jama.1")
        XCTAssertTrue(p.risRecord.contains("AU  - Smith, AB"))
        XCTAssertTrue(p.risRecord.contains("SP  - 3"))
        XCTAssertTrue(p.risRecord.contains("EP  - 4"))
        XCTAssertTrue(p.bibtex.hasPrefix("@article{smith2026,"))
        XCTAssertEqual(p.authorLine, "Smith AB and Jones C")
    }

    func testBrokenQuizIsDropped() throws {
        let json = """
        {"name":"x","generatedAt":"2026-10-20T00:00:00+00:00","posts":[{"id":"a","date":"2026-10-01","journal":"JAMA","jshort":"JAMA","kind":"RCT","topics":["criticalCare"],"headline":"H","summary":"S","takeHome":["t"],"deepDive":"d","url":"https://doi.org/10.1001/jama.1","impact":3,
          "quiz":{"question":"Q","options":["Up","Down"],"answer":5,"explanation":"E"},"glance":{}}]}
        """
        let p = try FeedLoader.decode(Data(json.utf8)).posts[0]
        XCTAssertNil(p.quiz, "a quiz without four options is ignored rather than crashing the view")
        XCTAssertNil(p.glance, "an empty glance is treated as absent")
    }

    func testAMACitationTruncatesLongAuthorLists() {
        var p = Post.sample
        p.citation = Citation(title: "T", authors: ["A A", "B B", "C C", "D D", "E E", "F F", "G G"], journal: "J", year: 2026, volume: nil, issue: nil, pages: nil, doi: nil)
        XCTAssertEqual(p.amaCitation, "A A, B B, C C, et al. T. J. 2026.")
    }

    func testFallbackCitationForNonDOI() {
        var p = Post.sample
        p.citation = nil; p.url = "https://www.fda.gov/notice"; p.journal = "FDA"
        XCTAssertNil(p.doi)
        XCTAssertTrue(p.amaCitation.hasPrefix("FDA. "))
        XCTAssertTrue(p.amaCitation.hasSuffix("https://www.fda.gov/notice"))
        XCTAssertTrue(p.risRecord.hasPrefix("TY  - ELEC"))
    }

    func testSocietyDetection() {
        func post(_ headline: String, journal: String = "X", kind: String = "Guideline") -> Post {
            Post(id: "x", date: "2026-01-01", journal: journal, jshort: journal, kind: kind, topics: ["general"], headline: headline, summary: "", takeHome: [], deepDive: "", url: "https://e.x", impact: 2)
        }
        XCTAssertEqual(post("2026 AHA/ACC PE guideline: PERT is Class 1").society, "AHA / ACC")
        XCTAssertEqual(post("SCA and STS publish the first joint consensus on DOACs").society, "SCA")
        XCTAssertEqual(post("ESICM 2025 shock guideline: echo first").society, "ESICM")
        XCTAssertEqual(post("Surviving Sepsis 2026: peripheral pressors").society, "SCCM")
        XCTAssertEqual(post("PROSPECT hip arthroplasty update backs PENG blocks").society, "PROSPECT")
        XCTAssertEqual(post("FDA Class I recall of every Automated Impella Controller", journal: "FDA", kind: "Safety alert").society, "FDA")
        XCTAssertEqual(post("Something with no society name").society, "Other societies")
    }

    func testMarkdownBlocks() {
        let blocks = MarkdownBlocks.parse("**Why it matters.** One.\n\n- a\n- b\n\n# Head\nPara line one\nline two")
        XCTAssertEqual(blocks.count, 4)
        if case .bullets(let items) = blocks[1] { XCTAssertEqual(items, ["a", "b"]) } else { XCTFail("expected bullets") }
        if case .heading(let h) = blocks[2] { XCTAssertEqual(h, "Head") } else { XCTFail("expected heading") }
        if case .paragraph(let p) = blocks[3] { XCTAssertEqual(p, "Para line one line two") } else { XCTFail("expected paragraph") }
    }

    func testSpokenTextStripsMarkdownAndExpandsAbbreviations() {
        XCTAssertEqual(SpeechPlayer.spoken("**Mortality** 31.8% vs 33.0% (HR 0.98, 95% CI 0.88-1.24)"), "Mortality 31.8% versus 33.0% (hazard ratio 0.98, 95% confidence interval 0.88-1.24)")
        let segments = SpeechPlayer.segments(for: .sample)
        XCTAssertEqual(segments.first, SpeechPlayer.spoken(Post.sample.headline))
        XCTAssertTrue(segments.first?.contains("micrograms per kilogram per minute") == true)
        XCTAssertTrue(segments.contains("The authors' key points."))
        XCTAssertTrue(segments.contains("Limitations stated by the authors."))
    }

    func testDateDisplay() {
        XCTAssertEqual(PSDate.display("2025-03-07", long: true), "Mar 7, 2025")
        XCTAssertEqual(PSDate.monthTitle("2026-10"), "October 2026")
        XCTAssertEqual(PSDate.today.count, 10)
    }

    @MainActor
    func testRelatedPostsPreferSameTrialAndTopics() throws {
        var posts = try FeedLoader.decode(try fixture()).posts
        let base = posts[0]
        // A post sharing the trial name should outrank everything else.
        var twin = posts[posts.count - 1]
        twin.id = "twin"; twin.trialName = base.trialName.isEmpty ? "X" : base.trialName; twin.topics = base.topics
        if base.trialName.isEmpty { posts[0].trialName = "X" }
        posts.append(twin)
        let related = PostStoreTestHelper.related(in: posts, to: posts[0])
        XCTAssertFalse(related.contains { $0.id == posts[0].id })
        XCTAssertLessThanOrEqual(related.count, 3)
        XCTAssertEqual(related.first?.id, "twin")
    }

    @MainActor
    func testTodaysQuestionIsStableForTheDay() throws {
        let feed = try FeedLoader.decode(try fixture())
        var posts = feed.posts
        for i in posts.indices {
            posts[i].quiz = Quiz(question: "Question number \(i) about the post?", options: ["a", "b", "c", "d"], answer: i % 4, explanation: "Because the post says so, in detail.")
        }
        UserDefaults.standard.removeObject(forKey: "ps.quiz.today")
        // The test host shares the app's container on the simulator; leave no pick behind for the screenshot run.
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: "ps.quiz.today") }
        let store = QuizStore()
        let first = store.todaysQuestion(from: posts)
        let second = store.todaysQuestion(from: posts)
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.id, second?.id)
    }
}

/// Runs the related-posts scoring without needing a loaded store.
enum PostStoreTestHelper {
    @MainActor
    static func related(in posts: [Post], to post: Post) -> [Post] {
        let store = PostStore()
        store.inject(posts)
        return store.related(to: post)
    }
}

final class PushTopicsTests: XCTestCase {
    func testDesiredTopics() {
        XCTAssertEqual(PushTopics.desired(myTopics: [], digest: true, quietWeekends: false, enabled: true), ["new-posts", "weekly-digest"])
        XCTAssertEqual(PushTopics.desired(myTopics: ["cardiac", "echo"], digest: false, quietWeekends: true, enabled: true), ["t-cardiac-weekdays", "t-echo-weekdays"])
        XCTAssertEqual(PushTopics.desired(myTopics: ["cardiac"], digest: true, quietWeekends: false, enabled: false), [])
    }
}
