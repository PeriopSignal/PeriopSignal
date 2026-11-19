import XCTest
@testable import PeriopSignal

/// The PONV tool and the Apfel score after the Nov 19 review (Ben: "Use your best judgement and make the decisions"): the headline
/// says interventions as the Fifth Consensus does, the Apfel band texts are the reference.json counts wording, the oral ondansetron
/// dose is shown with its source, and "Prophylaxis plan" opens the tool.
final class PONV113Tests: XCTestCase {
    private func bundled() throws -> ReferenceBundle {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"), "reference.json is bundled with the tests")
        return try ReferenceLoader.decode(try Data(contentsOf: url))
    }

    private func ponv() throws -> PONVData { try XCTUnwrap(try bundled().ponv) }

    // MARK: Headline and progress

    func testHeadlineSaysInterventionsAndMatchesTheStoredCounts() throws {
        let p = try ponv()
        for f in 0...2 {
            XCTAssertEqual(PONVPlan.headline(PONVPlan.target(factors: f, counts: p.counts)), "2 interventions from different classes", "\(f) factors")
        }
        for f in 3...4 {
            XCTAssertEqual(PONVPlan.headline(PONVPlan.target(factors: f, counts: p.counts)), "3 to 4 interventions from different classes", "\(f) factors")
        }
        XCTAssertEqual(PONVPlan.headline(nil), "2 interventions from different classes", "no row: the base count")
        XCTAssertFalse(PONVPlan.headline(PONVPlan.target(factors: 3, counts: p.counts)).contains("antiemetic"))
    }

    func testProgressWordNamesTheUpperEndOnlyForARange() throws {
        let p = try ponv()
        XCTAssertEqual(PONVPlan.progressWord(PONVPlan.target(factors: 1, counts: p.counts)), "chosen")
        XCTAssertEqual(PONVPlan.progressWord(PONVPlan.target(factors: 4, counts: p.counts)), "chosen, up to 4")
        // The bar is full at the fewest the row asks for (3 here) and the word says the range goes to 4.
        XCTAssertEqual(PONVPlan.target(factors: 4, counts: p.counts)?.agents, 3)
        XCTAssertEqual(PONVPlan.target(factors: 4, counts: p.counts)?.agentsHigh, 4)
    }

    // MARK: Note on the 3 to 4 row

    func testHighRiskRowCarriesTheFifthConsensusNote() throws {
        let p = try ponv()
        let high = try XCTUnwrap(PONVPlan.target(factors: 3, counts: p.counts))
        XCTAssertEqual(high.note, "The Fifth Consensus recommends two interventions for every adult at risk and says more research is required on adding a third or fourth antiemetic in high-risk patients.")
        XCTAssertNil(PONVPlan.target(factors: 2, counts: p.counts)?.note, "only the 3 to 4 row has a note")
    }

    func testCountRowDecodesWithoutANote() throws {
        // An older bundle has no "note"; it must still decode.
        let json = #"{"minFactors": 0, "maxFactors": 2, "agents": 2, "text": "Two prophylactic interventions for every adult at risk"}"#
        let row = try JSONDecoder().decode(PONVCount.self, from: Data(json.utf8))
        XCTAssertNil(row.note)
        XCTAssertEqual(PONVPlan.headline(row), "2 interventions from different classes")
    }

    // MARK: Ondansetron

    func testOndansetronShowsTheOralDoseWithItsSources() throws {
        let p = try ponv()
        let o = try XCTUnwrap(p.agents.first { $0.id == "ondansetron" })
        XCTAssertEqual(o.dose, "4 mg IV, or by mouth 16 mg (US label) or 8 mg ODT (consensus table)")
        XCTAssertEqual(o.timing, "IV at the end of surgery; by mouth 1 h before induction")
        XCTAssertEqual(o.rescueDose, "4 mg IV", "the oral doses are for prevention; the rescue list keeps the IV dose")
        XCTAssertTrue(p.source.contains("oral ondansetron dose from the US prescribing information"))
    }

    func testCardAndToolStillShareOneListOfAgents() throws {
        // testPONVPlan checks the same; repeated here because the ondansetron edit touched the tool's list.
        let b = try bundled()
        let card = try XCTUnwrap(b.quickrefs.first { $0.id == "ponv-consensus" })
        let table = try XCTUnwrap(card.sections.first { $0.kind == .table })
        let agents = try ponv().agents.filter { $0.prophylaxis != false }.map(\.name)
        XCTAssertEqual(table.rows?.map { $0.first ?? "" }, agents)
    }

    // MARK: Apfel

    func testApfelBandTextsContainTheReferenceCountsWording() throws {
        let p = try ponv()
        for band in Scores.apfel.bands {
            let row = try XCTUnwrap(PONVPlan.target(factors: band.range.lowerBound, counts: p.counts), "a count row for \(band.label)")
            XCTAssertTrue(band.detail.contains(row.text), "\(band.label): \"\(band.detail)\" should contain \"\(row.text)\"")
            XCTAssertEqual(PONVPlan.target(factors: band.range.upperBound, counts: p.counts), row, "\(band.label) sits inside one count row")
        }
        XCTAssertFalse(Scores.apfel.bands.contains { $0.detail.contains("e.g.") }, "no unsourced example agents in the band texts")
        // Every count row is used by some band, so none can drift unseen.
        for row in p.counts {
            XCTAssertTrue(Scores.apfel.bands.contains { $0.detail.contains(row.text) }, "no Apfel band shows: \(row.text)")
        }
    }

    func testApfelNextStepOpensThePONVTool() throws {
        let next = try XCTUnwrap(Scores.apfel.next)
        XCTAssertEqual(next.label, "Prophylaxis plan")
        XCTAssertEqual(RefRoute(key: next.route), .ponv, "the Prophylaxis plan button opens the interactive tool, not the static card")
        XCTAssertEqual(RefRoute(key: "quickref:ponv-consensus"), .quickref("ponv-consensus"), "the card stays reachable (the tool's Full card button)")
    }
}
