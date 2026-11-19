import XCTest
@testable import PeriopSignal

/// Ben, Nov 19: "How come no valve or aortic surgery options ... What if pt is coming for simple aortic valve repair? Please update
/// this calculator to avoid confusion for all procedures." Each surgery group lists its operations by name, each following the
/// guideline's table row its text puts it under; operations the guideline says need no routine prophylaxis are named too. Only what
/// the guideline's own text names is here: an operation it does not name (a valve replacement, aortic surgery) still selects the group
/// only, until Ben has approved the reading.
final class ProphylaxisNamed112Tests: XCTestCase {

    private var bundleFile: ReferenceBundle!
    private var d: ProphylaxisData { bundleFile.prophylaxis! }
    private var t: CaseTimerData { bundleFile.caseTimers! }

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        bundleFile = try ReferenceLoader.decode(try Data(contentsOf: url))
    }

    private func adult() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = 90
        return r
    }

    private func answer(_ g: String, _ p: String, _ v: String? = nil, allergy: Bool = false) -> ProphylaxisAnswer {
        var i = ProphylaxisInput()
        i.chooseGroup(g, data: d)
        i.chooseProcedure(p, data: d)
        if let v { i.chooseVariant(v, data: d) }
        i.betaLactamAllergy = allergy
        return ProphylaxisEngine.answer(i, record: adult(), data: d, timers: t)
    }

    private func prefill(_ catalogID: String) throws -> ProphylaxisPrefill {
        var r = adult()
        r.procedures = [PlannedProcedure(try XCTUnwrap(ProcedureCatalog.byID(catalogID), catalogID))]
        return ProphylaxisEngine.prefill(record: r, data: d)
    }

    func testAValveRepairHasItsOwnRowWithTheCardiacRecommendation() throws {
        let names: [String] = d.group("cardiac")?.procedures.map(\.name) ?? []
        XCTAssertTrue(names.contains("Valve repair, surgical (aortic, mitral, tricuspid, pulmonary)"), "\(names)")
        let a = answer("cardiac", "valve-repair")
        XCTAssertEqual(a.state, .regimens)
        XCTAssertEqual(a.evidence, "Evidence A")
        XCTAssertEqual(Set(a.allLines.map(\.agent)), ["cefazolin", "cefuroxime"])
        XCTAssertEqual(Set(answer("cardiac", "valve-repair", allergy: true).allLines.map(\.agent)), ["clindamycin", "vancomycin"])
        // The same agents as the row it follows.
        XCTAssertEqual(a.allLines.map(\.agent), answer("cardiac", "cabg").allLines.map(\.agent))
        // A planned aortic valve repair opens on it.
        for id in ["av-repair", "mv-repair", "tv-repair", "pv-repair"] {
            let p = try prefill(id)
            XCTAssertEqual(p.group, "cardiac", id)
            XCTAssertEqual(p.procedure, "valve-repair", id)
        }
    }

    func testAnOperationTheGuidelineDoesNotNameStillSelectsTheGroupOnly() throws {
        // A valve replacement and aortic surgery are not named by the guideline's text: no row until the reading is approved.
        for id in ["avr", "mvr", "bentall", "ascending-aorta", "tavr"] where ProcedureCatalog.byID(id) != nil {
            let p = try prefill(id)
            XCTAssertNil(p.procedure, id)
        }
    }

    func testOperationsTheGuidelineSaysNeedNoRoutineProphylaxisSayItsWords() throws {
        let cath = answer("cardiac", "cath-tee")
        XCTAssertEqual(cath.state, .outside)
        XCTAssertTrue(cath.body.contains("not routinely recommended for cardiac catheterization or transesophageal echocardiogram"), cath.body)
        XCTAssertTrue(cath.allLines.isEmpty)
        XCTAssertEqual(try prefill("tee").procedure, "cath-tee")
        let tube = answer("thoracic", "chest-tube")
        XCTAssertEqual(tube.state, .outside)
        XCTAssertTrue(tube.body.contains("not routinely recommended for chest tube insertion"), tube.body)
        let tonsil = answer("headneck", "tonsil-fess")
        XCTAssertEqual(tonsil.state, .outside)
        XCTAssertTrue(tonsil.body.contains("has not been shown to benefit"), tonsil.body)
        // One answer, no question: such a row never asks.
        for g in d.groups {
            for p in g.procedures where p.variants.count == 1 { XCTAssertNil(p.question, p.id) }
        }
    }

    func testEveryNamedOperationShowsTheAgentsOfTheRowItFollows() throws {
        // Named operations share their row's result: the same table cell, the same evidence, the same agents.
        var byRow: [String: Set<String>] = [:]
        for g in d.groups {
            for p in g.procedures {
                for v in p.variants {
                    guard let table = v.table, let rec = v.recommended else { continue }
                    let key = table.section + " / " + table.row
                    byRow[key, default: []].insert(rec.text + " | " + (v.allergy?.text ?? "") + " | " + (v.evidence ?? ""))
                }
            }
        }
        for (row, results) in byRow { XCTAssertEqual(results.count, 1, row) }
        XCTAssertGreaterThan(byRow.count, 30)
    }

    func testTheOtherGroupsNameTheirOperations() throws {
        XCTAssertEqual(try prefill("vp-shunt").procedure, "shunt")
        XCTAssertEqual(try prefill("craniotomy-tumor").procedure, "craniotomy")
        XCTAssertEqual(try prefill("open-aaa").procedure, "aneurysm")
        XCTAssertEqual(try prefill("fem-pop").procedure, "bypass")
        XCTAssertEqual(try prefill("whipple").procedure, "whipple")
        XCTAssertEqual(try prefill("rygb").procedure, "bariatric")
        XCTAssertEqual(try prefill("thyroidectomy-total").procedure, "thyroid")
        XCTAssertEqual(answer("headneck", "thyroid").state, .none)
        XCTAssertEqual(try prefill("alnd").procedure, "breast-cancer")
        XCTAssertEqual(answer("plastic", "breast-cancer").state, .regimens)
        let bariatric = answer("gastroduodenal", "bariatric")
        XCTAssertTrue(bariatric.notes.contains { $0.contains("morbidly obese patients undergoing bariatric procedures") }, "\(bariatric.notes)")
        XCTAssertFalse(bariatric.notes.contains { $0.contains("Pancreaticoduodenectomy") }, "the Whipple note stays with the Whipple")
    }
}
