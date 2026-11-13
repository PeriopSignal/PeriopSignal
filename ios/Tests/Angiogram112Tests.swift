import XCTest
@testable import PeriopSignal

/// Ben, Nov 12: "Add angiogram with possible intervention and diagnostic angiogram to procedures list."
final class Angiogram112Tests: XCTestCase {

    private func first(_ q: String) -> String? { ProcedureCatalog.search(q).first?.name }
    private func top(_ q: String, _ n: Int) -> [String] { ProcedureCatalog.search(q).prefix(n).map(\.name) }

    func testBothAreInTheListOnceWithThePercutaneousSettings() throws {
        let all = ProcedureCatalog.all
        for (id, name) in [("angiogram-diagnostic", "Diagnostic angiogram"), ("angiogram-intervention", "Angiogram with possible intervention")] {
            let found = all.filter { $0.id == id }
            XCTAssertEqual(found.count, 1, id)
            let p = try XCTUnwrap(found.first)
            XCTAssertEqual(p.name, name)
            XCTAssertEqual(p.anesthetic, ["mac"], id)
            XCTAssertEqual(p.incision, "Peripheral", id)
            XCTAssertEqual(p.duration, "≤ 2 h", id)
            XCTAssertFalse(p.highRisk, "percutaneous: not the RCRI's high-risk surgery")
            XCTAssertFalse(p.cardiac, id)
        }
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "no id twice")
    }

    func testEachIsFoundByItsName() {
        XCTAssertEqual(first("Diagnostic angiogram"), "Diagnostic angiogram")
        XCTAssertEqual(first("diagnostic angiogram"), "Diagnostic angiogram")
        XCTAssertEqual(first("Angiogram with possible intervention"), "Angiogram with possible intervention")
        XCTAssertEqual(first("angiogram possible intervention"), "Angiogram with possible intervention")
        XCTAssertEqual(first("angiogram with possible angioplasty"), "Angiogram with possible intervention")
        XCTAssertEqual(first("arteriogram"), "Diagnostic angiogram")
        XCTAssertEqual(PlannedProcedure.parse("Diagnostic angiogram").first?.catalogID, "angiogram-diagnostic")
        XCTAssertEqual(PlannedProcedure.parse("Angiogram with possible intervention").first?.catalogID, "angiogram-intervention")
    }

    /// Part-way through typing it, the first row is the list's entry, not "Diagnostic angiogram possible".
    func testTheInterventionEntryLeadsWhileItIsBeingTyped() {
        for q in ["angiogram with possible", "angiogram possible", "angiogram with possible interv"] {
            XCTAssertEqual(PlannedProcedure.parse(q).first?.catalogID, "angiogram-intervention", q)
            XCTAssertEqual(first(q), "Angiogram with possible intervention", q)
        }
        XCTAssertEqual(PlannedProcedure.parse("angiogram").first?.catalogID, "angiogram-diagnostic")
    }

    func testABareAngiogramOffersBoth() {
        let names = top("angiogram", 4)
        XCTAssertTrue(names.contains("Diagnostic angiogram"), "\(names)")
        XCTAssertTrue(names.contains("Angiogram with possible intervention"), "\(names)")
    }

    func testTheAngiogramsThatNameTheirBedStayWhereTheyWere() {
        XCTAssertEqual(first("coronary angiogram"), "Left heart catheterization")
        XCTAssertEqual(first("diagnostic coronary angiogram"), "Left heart catheterization")
        XCTAssertEqual(first("cerebral angiogram"), "Endovascular aneurysm coiling")
        XCTAssertEqual(first("spinal angiogram"), "Spinal angiogram")
        XCTAssertEqual(first("lower extremity angiogram"), "Peripheral angioplasty and stenting")
        XCTAssertEqual(first("runoff angiogram"), "Peripheral angioplasty and stenting")
        XCTAssertEqual(PlannedProcedure.parse("coronary angiogram").first?.catalogID, "lhc")
        XCTAssertEqual(PlannedProcedure.parse("lower extremity angiogram").first?.catalogID, "peripheral-angioplasty")
        XCTAssertEqual(PlannedProcedure.parse("cerebral angiogram").first?.catalogID, "neuro-endovascular")
        XCTAssertEqual(first("angioplasty"), "Peripheral angioplasty and stenting", "an angioplasty is not an angiogram")
        XCTAssertEqual(first("fistulagram"), "Fistulagram with angioplasty")
    }

    // MARK: Mesenteric angiogram (Ben, Nov 12)

    func testMesentericAngiogramIsInTheList() throws {
        let p = try XCTUnwrap(ProcedureCatalog.all.first { $0.id == "mesenteric-angiogram" })
        XCTAssertEqual(p.name, "Mesenteric angiogram")
        XCTAssertEqual(p.anesthetic, ["mac"])
        XCTAssertEqual(p.incision, "Peripheral")
        XCTAssertEqual(p.duration, "≤ 2 h")
        XCTAssertFalse(p.highRisk)
        for q in ["Mesenteric angiogram", "mesenteric angiogram", "mesenteric angiography", "SMA angiogram", "celiac angiogram", "visceral angiogram"] {
            XCTAssertEqual(first(q), "Mesenteric angiogram", q)
            XCTAssertEqual(PlannedProcedure.parse(q).first?.catalogID, "mesenteric-angiogram", q)
        }
    }

    func testMesentericStentingAndEmbolizationStayWhereTheyWere() {
        XCTAssertEqual(first("mesenteric stenting"), "Mesenteric or renal artery stenting")
        XCTAssertEqual(first("SMA stenting"), "Mesenteric or renal artery stenting")
        XCTAssertEqual(first("renal artery stenting"), "Mesenteric or renal artery stenting")
        XCTAssertEqual(first("GI bleed embolization"), "Arterial embolization")
        XCTAssertEqual(first("angiogram"), "Diagnostic angiogram", "a bare angiogram is still the diagnostic one")
    }
}
