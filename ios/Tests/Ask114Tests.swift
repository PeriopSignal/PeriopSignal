import XCTest
@testable import PeriopSignal

/// Ben, Nov 20 (after an outside review): an Ask answer must not look better supported by the library than it is.
/// Short words and abbreviations match whole words only, an alias table lets TXA find "tranexamic acid" and back, a
/// source needs a hit in its name or three distinct question words in its body to be listed, the list on screen is what
/// the model was given (same items, order and numbers on both routes), a quick reference is clipped to the passage that
/// holds the question's words, and a question nothing matched says so. Everything here is a pure function over posts
/// and quick references built in the test.
final class Ask114Tests: XCTestCase {
    // MARK: Builders

    private func post(_ id: String, headline: String = "Sample headline", summary: String = "Sample summary.", trial: String = "") -> Post {
        Post(id: id, date: "2026-10-14", journal: "Sample Journal", jshort: "Sample", kind: "RCT", topics: [],
             headline: headline, summary: summary, takeHome: [], deepDive: "", url: "https://example.com", impact: 1, trialName: trial)
    }

    private func ref(_ id: String, title: String = "Sample card", keywords: [String]? = nil, summary: String = "Sample summary.", sections: [RefSection] = []) -> QuickRef {
        QuickRef(id: id, title: title, society: "Sample Society", short: "SS", year: 2025, keywords: keywords, summary: summary,
                 source: RefSource(title: "Sample source", url: "https://example.com"), sections: sections)
    }

    private func ids(_ g: AskEngine.Grounding) -> [String] { g.posts.map(\.id) + g.refs.map(\.id) }

    private func listed(_ question: String, posts: [Post] = [], refs: [QuickRef] = []) -> [String] {
        ids(AskEngine.grounding(for: question, posts: posts, refs: refs))
    }

    // MARK: Whole words for short words and abbreviations

    func testShortWordMatchesWholeWordsOnly() {
        let concepts = AskEngine.concepts(for: "last dose")
        let last = concepts.flatMap { $0 }.first { $0.text == "last" }
        XCTAssertNotNil(last)
        XCTAssertEqual(last?.wholeWord, true)
        XCTAssertFalse(AskEngine.matches(last!, in: AskEngine.Haystack("the effect lasted for hours")), "last is not in lasted")
        XCTAssertTrue(AskEngine.matches(last!, in: AskEngine.Haystack("the last dose was at noon")))
        XCTAssertTrue(AskEngine.matches(last!, in: AskEngine.Haystack("last")), "the start and end of the text count as edges")
    }

    func testAbbreviationDoesNotMatchInsideAnotherWord() {
        let mh = AskEngine.concepts(for: "MH").flatMap { $0 }.first { $0.text == "mh" }
        XCTAssertNotNil(mh)
        XCTAssertFalse(AskEngine.matches(mh!, in: AskEngine.Haystack("a monitor that operates at 3 MHz")))
        XCTAssertTrue(AskEngine.matches(mh!, in: AskEngine.Haystack("an MH crisis")))
        XCTAssertTrue(AskEngine.matches(mh!, in: AskEngine.Haystack("(MH)")), "punctuation is an edge")
        // And through the whole path: a post about a frequency is not listed for the question.
        XCTAssertEqual(listed("MH", posts: [post("freq", headline: "A 3 MHz probe for nerve blocks")]), [])
    }

    func testLongWordsStillMatchInsideLongerWords() {
        let hep = AskEngine.concepts(for: "heparin").flatMap { $0 }.first { $0.text == "heparin" }
        XCTAssertEqual(hep?.wholeWord, false)
        XCTAssertTrue(AskEngine.matches(hep!, in: AskEngine.Haystack("heparinization before bypass")))
    }

    func testDoseIsNoLongerAStopWord() {
        XCTAssertFalse(AskEngine.concepts(for: "dose").isEmpty)
        XCTAssertTrue(AskEngine.concepts(for: "the use of the").isEmpty, "the rest of the stoplist stays")
    }

    // MARK: Aliases

    func testTxaFindsTranexamicAcidAndTheOtherWayRound() {
        let full = post("full", headline: "Tranexamic acid and blood loss after surgery")
        let abbr = post("abbr", headline: "TXA and blood loss after surgery")
        XCTAssertTrue(listed("TXA", posts: [full]).contains("full"))
        XCTAssertTrue(listed("tranexamic acid", posts: [abbr]).contains("abbr"))
        XCTAssertTrue(listed("txa", posts: [full]).contains("full"), "typed in lower case")
    }

    func testMalignantHyperthermiaAndMhAreInterchangeable() {
        let full = post("full", headline: "Malignant hyperthermia: what to stock")
        let abbr = post("abbr", headline: "MH cart contents")
        XCTAssertTrue(listed("MH", posts: [full]).contains("full"))
        XCTAssertTrue(listed("malignant hyperthermia", posts: [abbr]).contains("abbr"))
    }

    func testLmwhEnoxaparinAndTheLongName() {
        let enox = post("enox", headline: "Enoxaparin timing before a block")
        let long = post("long", headline: "Low molecular weight heparin and spinal anesthesia")
        let abbr = post("abbr", headline: "LMWH and neuraxial blocks")
        XCTAssertEqual(Set(listed("LMWH", posts: [enox, long])), ["enox", "long"])
        XCTAssertTrue(listed("enoxaparin", posts: [abbr]).contains("abbr"))
        XCTAssertTrue(listed("low molecular weight heparin", posts: [abbr]).contains("abbr"))
    }

    func testGlp1AndSemaglutide() {
        let sema = post("sema", headline: "Semaglutide and aspiration risk")
        let glp = post("glp", headline: "GLP-1 agonists before anesthesia")
        XCTAssertTrue(listed("GLP-1", posts: [sema]).contains("sema"))
        XCTAssertTrue(listed("semaglutide", posts: [glp]).contains("glp"))
    }

    func testAnAliasCountsAsOneQuestionWord() {
        // "TXA" and "tranexamic acid" typed together are one idea, not two question words.
        XCTAssertEqual(AskEngine.concepts(for: "TXA tranexamic acid").count, 1)
    }

    func testAbbreviationsThatAreWordsNeedCapitals() {
        // "last" in a question is the word; "LAST" is the syndrome.
        XCTAssertEqual(AskEngine.concepts(for: "last dose").count, 2)
        let syndrome = AskEngine.concepts(for: "LAST dose")
        XCTAssertEqual(syndrome.count, 2)
        let names = syndrome.flatMap { group in group.map { term in term.text } }
        XCTAssertTrue(names.contains("local anesthetic systemic toxicity"))
        // The ordinary word "last" in a post is not a hit for the syndrome.
        XCTAssertEqual(listed("local anesthetic toxicity", posts: [post("word", headline: "The last trial of the year")]), [])
        XCTAssertTrue(listed("local anesthetic toxicity", posts: [post("abbr", headline: "Treating LAST early")]).contains("abbr"))
    }

    // MARK: The bar for listing a source

    func testTwoStrayBodyWordsDoNotListAPost() {
        let q = "esmolol infusion bradycardia"
        let two = post("two", summary: "Mentions an esmolol infusion in passing.")
        XCTAssertEqual(listed(q, posts: [two]), [])
    }

    func testThreeDistinctBodyWordsListAPost() {
        let q = "esmolol infusion bradycardia"
        let three = post("three", summary: "An esmolol infusion and the bradycardia that followed.")
        XCTAssertEqual(listed(q, posts: [three]), ["three"])
    }

    func testAHeadlineHitListsAPostAlone() {
        XCTAssertEqual(listed("esmolol infusion bradycardia", posts: [post("h", headline: "Esmolol in the operating room")]), ["h"])
    }

    func testATrialNameOrKeywordAlsoCounts() {
        XCTAssertEqual(listed("esmolol infusion bradycardia", posts: [post("t", trial: "ESMOLOL-2")]), ["t"])
        let card = ref("k", keywords: ["esmolol"])
        XCTAssertEqual(listed("esmolol infusion bradycardia", refs: [card]), ["k"])
        let strays = ref("s", summary: "An esmolol infusion.")
        XCTAssertEqual(listed("esmolol infusion bradycardia", refs: [strays]), [])
    }

    func testRankingKeepsTheBetterMatchFirst() {
        let body = post("body", summary: "An esmolol infusion and the bradycardia that followed.")
        let head = post("head", headline: "Esmolol infusion and bradycardia", summary: "Sample.")
        XCTAssertEqual(listed("esmolol infusion bradycardia", posts: [body, head]), ["head", "body"])
    }

    // MARK: Nothing matched

    func testNothingMatchedSendsNoSources() {
        let g = AskEngine.grounding(for: "zzyzx qqqq", posts: [post("a")], refs: [ref("r")])
        XCTAssertTrue(g.isEmpty)
        XCTAssertTrue(g.sources.isEmpty)
        let prompt = AskEngine.onDevicePrompt(question: "zzyzx qqqq", grounding: g)
        XCTAssertFalse(prompt.contains("Material"))
        let body = AskEngine.cloudBody(question: "zzyzx qqqq", grounding: g)
        XCTAssertEqual((body["context"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((body["refs"] as? [[String: Any]])?.count, 0)
        XCTAssertFalse(AskEngine.onDeviceInstructions(hasSources: false).contains("cite it as [1]"))
    }

    func testAQuestionOfStopWordsMatchesNothing() {
        XCTAssertTrue(AskEngine.grounding(for: "what is the", posts: [post("a")], refs: [ref("r")]).isEmpty)
    }

    func testNothingMatchedWordingDoesNotMentionTheMaterialAbove() {
        XCTAssertEqual(AskEngine.nothingMatchedLine, "Nothing in Periop Signal matched this question. This answer is from general knowledge.")
        for b in [AskEngine.Backend.onDevice, .cloud] {
            XCTAssertFalse(AskEngine.provenance(backend: b, matched: false).contains("material above"), "\(b)")
            XCTAssertTrue(AskEngine.provenance(backend: b, matched: true).contains(b == .cloud ? "the material above were sent" : "nothing left the device"))
        }
        XCTAssertFalse(AskEngine.footerNote(matched: false).contains("material above"))
        XCTAssertTrue(AskEngine.footerNote(matched: true).contains("written from the material above and general knowledge"))
        // The wording with sources is today's, word for word.
        XCTAssertEqual(AskEngine.provenance(backend: .cloud, matched: true), "Answered by Claude through Periop Signal's proxy; the question and the material above were sent, nothing else. AI answers can be wrong: check the sources.")
        XCTAssertEqual(AskEngine.provenance(backend: .onDevice, matched: true), "Answered on this phone by Apple Intelligence; nothing left the device. AI answers can be wrong: check the sources.")
    }

    // MARK: One list, one numbering

    private func library() -> (posts: [Post], refs: [QuickRef]) {
        let posts = (1...6).map { post("p\($0)", headline: "Esmolol study \($0)") }
        let refs = (1...3).map { ref("r\($0)", title: "Esmolol card \($0)") }
        return (posts, refs)
    }

    func testOnDeviceListIsExactlyWhatThePromptHolds() {
        let lib = library()
        let g = AskEngine.grounding(for: "esmolol", posts: lib.posts, refs: lib.refs, backend: .onDevice)
        XCTAssertEqual(g.posts.count, 3)
        XCTAssertEqual(g.refs.count, 1)
        let lines = AskEngine.materialLines(g)
        XCTAssertEqual(lines.count, g.sources.count)
        for (k, source) in g.sources.enumerated() {
            XCTAssertEqual(source.id, k + 1)
            XCTAssertTrue(lines[k].hasPrefix("[\(k + 1)] "), lines[k])
            if case .post = source.kind { XCTAssertTrue(lines[k].contains(source.title), lines[k]) }
        }
        let prompt = AskEngine.onDevicePrompt(question: "esmolol", grounding: g)
        XCTAssertFalse(prompt.contains("[5]"), "nothing past the list is in the prompt")
    }

    func testCloudListIsExactlyWhatTheBodyHolds() {
        let lib = library()
        let g = AskEngine.grounding(for: "esmolol", posts: lib.posts, refs: lib.refs, backend: .cloud)
        XCTAssertEqual(g.posts.count, 4)
        XCTAssertEqual(g.refs.count, 2)
        let body = AskEngine.cloudBody(question: "esmolol", grounding: g)
        let sentPosts = (body["context"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
        let sentRefs = (body["refs"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
        XCTAssertEqual(sentPosts, g.posts.map(\.id))
        XCTAssertEqual(sentRefs, g.refs.map(\.id))
        // The proxy numbers posts, then references; the screen numbers the same way.
        XCTAssertEqual(g.sources.map(\.id), Array(1...6))
        XCTAssertEqual(g.sources.map { $0.title }, g.posts.map(\.headline) + g.refs.map(\.title))
    }

    func testBothRoutesRankTheSameWay() {
        let lib = library()
        let device = AskEngine.grounding(for: "esmolol", posts: lib.posts, refs: lib.refs, backend: .onDevice)
        let cloud = AskEngine.grounding(for: "esmolol", posts: lib.posts, refs: lib.refs, backend: .cloud)
        XCTAssertEqual(Array(cloud.posts.prefix(3)).map(\.id), device.posts.map(\.id))
        XCTAssertEqual(Array(cloud.refs.prefix(1)).map(\.id), device.refs.map(\.id))
    }

    // MARK: Passage-aware excerpts

    private func longCard() -> QuickRef {
        let filler = (1...120).map { "Filler sentence number \($0) says nothing special." }.joined(separator: " ")
        var rows: [[String]] = (1...40).map { ["Common drug \($0)", "Ordinary note about drug \($0) with some padding words."] }
        rows.append(["Zinnium", "The special zinnium note"])
        // A keyword, so the card clears the bar for being listed (one body word alone does not).
        return ref("long", title: "Long sample card", keywords: ["zinnium"], summary: "A short summary.", sections: [
            RefSection(heading: "Background", kind: .text, text: filler),
            RefSection(heading: "Drugs", kind: .table, columns: ["Drug", "Note"], rows: rows),
        ])
    }

    func testExcerptPicksTheRowThatHoldsTheWordPastTheOldCutoff() {
        let card = longCard()
        let old = AskEngine.excerpt(of: card, limit: 700)
        XCTAssertFalse(old.contains("Zinnium"), "with no question words the card is cut from the top")
        let concepts = AskEngine.concepts(for: "zinnium")
        let text = AskEngine.excerpt(of: card, limit: 700, concepts: concepts)
        XCTAssertTrue(text.contains("Zinnium"), text)
        XCTAssertTrue(text.contains("special zinnium note"), text)
        XCTAssertTrue(text.contains("Drugs:"), "the section heading comes with the row")
        XCTAssertTrue(text.hasPrefix("Long sample card"), "the title is always first")
        XCTAssertLessThanOrEqual(text.count, 700, "within the same budget")
    }

    func testExcerptKeepsTheTitleAndTheBudgetWhenNothingMatches() {
        let card = longCard()
        let text = AskEngine.excerpt(of: card, limit: 700, concepts: AskEngine.concepts(for: "quokka"))
        XCTAssertTrue(text.hasPrefix("Long sample card"))
        XCTAssertLessThanOrEqual(text.count, 700)
        XCTAssertTrue(text.contains("A short summary."), "the summary is next when no passage matches")
    }

    func testAShortCardIsGivenWholeWithItsTitle() {
        let card = ref("short", title: "Short card", summary: "Summary.", sections: [RefSection(heading: "Steps", kind: .list, items: ["First", "Second"])])
        let text = AskEngine.excerpt(of: card)
        XCTAssertEqual(text, "Short card\nSummary.\nSteps:\nFirst · Second")
    }

    func testTheCloudBodyUsesThePassageAwareExcerpt() {
        let g = AskEngine.grounding(for: "zinnium", posts: [], refs: [longCard()], backend: .cloud)
        XCTAssertEqual(g.refs.map(\.id), ["long"])
        let sent = (AskEngine.cloudBody(question: "zinnium", grounding: g)["refs"] as? [[String: Any]])?.first?["excerpt"] as? String
        XCTAssertTrue(sent?.contains("special zinnium note") == true)
    }
}
