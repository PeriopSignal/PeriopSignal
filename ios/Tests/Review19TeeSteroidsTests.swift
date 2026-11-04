import XCTest
@testable import PeriopSignal

/// 1.9 review: the TEE screen's GI bleed of unrecorded status and a previous esophageal procedure under dysphagia, and
/// fludrocortisone in the steroid conversion.
final class Review19TeeSteroidsTests: XCTestCase {

    private func record(_ problems: Set<String>) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 55; r.sex = .female
        r.problems = problems
        return r
    }

    private func suggestions(_ r: PatientRecord) -> [TEESuggestion] { PatientTEE.evaluate(r).suggestions }

    // MARK: Upper GI bleed, status not recorded

    func testUpperGIBleedWithoutStatusAsksWhetherItIsActive() {
        var r = record(["gi-bleed"])
        r.hx.giBleedSite = "upper"; r.hx.giBleedStatus = nil
        let s = suggestions(r)
        XCTAssertEqual(s.map(\.item.id), ["ugib-active", "ugib-recent"], "the absolute question is asked first")
        XCTAssertFalse(s.contains { $0.why.contains("Resolved") }, "a status that was never recorded is not called resolved")
        XCTAssertTrue(PatientTEE.evaluate(r).findings.isEmpty, "suggested, never counted")
        // A resolved upper bleed keeps its own question; an active one is a finding.
        r.hx.giBleedStatus = "resolved"
        XCTAssertEqual(suggestions(r).map(\.why), ["Resolved upper GI bleed recorded: was it recent?"])
        r.hx.giBleedStatus = "active"
        XCTAssertEqual(PatientTEE.evaluate(r).findings.map(\.item.id), ["ugib-active"])
        XCTAssertFalse(suggestions(r).contains { $0.item.id == "ugib-active" })
    }

    // MARK: Previous esophageal procedure under dysphagia

    func testPreviousEsophagealProcedureIsReadUnderDysphagiaAlone() {
        var r = record(["dysphagia"])
        XCTAssertTrue(suggestions(r).isEmpty, "dysphagia alone: a finding, no question")
        r.hx.esophagealProcedure = true; r.hx.esophagealProcedureDetails = "esophageal dilation and stent"
        let ids = Set(suggestions(r).map(\.item.id))
        XCTAssertTrue(ids.isSuperset(of: ["stricture", "tumor"]), "\(ids)")
        XCTAssertEqual(PatientTEE.evaluate(r).findings.map(\.item.id), ["dysphagia"], "the procedure is offered, never counted")
        r.hx.esophagealProcedure = false
        XCTAssertTrue(suggestions(r).isEmpty, "No previous procedure: its text is not read")
        // Without dysphagia or an esophageal disorder the section's text is not read.
        var none = record(["htn"])
        none.hx.esophagealProcedure = true; none.hx.esophagealProcedureDetails = "esophageal dilation and stent"
        XCTAssertTrue(suggestions(none).isEmpty)
    }

    // MARK: Fludrocortisone

    func testFludrocortisoneIsNotConvertedAsCortisone() throws {
        XCTAssertNil(PatientSteroids.prednisoloneEquivalent(drug: "Fludrocortisone", mg: 0.1))
        XCTAssertNil(PatientSteroids.prednisoloneEquivalent(drug: "Florinef", mg: 0.1))
        XCTAssertEqual(try XCTUnwrap(PatientSteroids.prednisoloneEquivalent(drug: "Cortisone", mg: 25)), 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(PatientSteroids.prednisoloneEquivalent(drug: "Hydrocortisone", mg: 20)), 5, accuracy: 1e-9)
        var r = record(["adrenal"])
        r.hx.adrenalKinds = ["steroids"]
        r.hx.steroidDrug = "Fludrocortisone"; r.hx.steroidDailyMg = 0.1; r.hx.steroidDuration = "ge1m"
        let a = try XCTUnwrap(PatientSteroids.advice(r))
        XCTAssertTrue(a.headline.contains("is not converted here"), a.headline)
        XCTAssertFalse(a.lines.contains { $0.contains("prednisolone a day") }, "no equivalence the cited table does not give")
    }
}
