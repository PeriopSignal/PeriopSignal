import XCTest
@testable import PeriopSignal

/// Ben, Nov 12: an antibiotic alternative reference in the Reference tab: for each type of surgery the first-choice
/// prophylactic antibiotic and the alternative for a β-lactam allergy, from the 2013 ASHP/IDSA/SIS/SHEA guideline
/// (Bratzler et al., Table 2). The rows asserted here were read from the guideline's table; a change to them needs the
/// source again.
final class AbxReference112Tests: XCTestCase {

    private func card() throws -> QuickRef {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"), "reference.json is bundled with the tests")
        let b = try ReferenceLoader.decode(try Data(contentsOf: url))
        return try XCTUnwrap(b.quickrefs.first { $0.id == "ashp-surgical-prophylaxis" }, "the antibiotic reference is in reference.json")
    }

    private func rows(_ c: QuickRef) -> [[String]] {
        c.sections.filter { $0.kind == .table }.flatMap { $0.rows ?? [] }
    }

    private func row(_ c: QuickRef, _ procedure: String) throws -> [String] {
        try XCTUnwrap(rows(c).first { $0[0] == procedure }, procedure)
    }

    func testTheCardNamesItsSourceAndWhereTheDosesAre() throws {
        let c = try card()
        XCTAssertEqual(c.year, 2013)
        XCTAssertEqual(c.societyShort, "ASHP")
        XCTAssertEqual(c.source.url, "https://pubmed.ncbi.nlm.nih.gov/23327981/")
        XCTAssertTrue((c.source.citation ?? "").contains("Bratzler"))
        XCTAssertTrue((c.source.citation ?? "").contains("2013;70(3):195"))
        XCTAssertTrue(c.summary.contains("Case Timers"), "doses and redose intervals stay in Case Timers")
        XCTAssertFalse(c.isEmergency)
        XCTAssertEqual(QuickRefView.headers[c.id]?.title, "Surgical Prophylaxis")
        for word in ["cefazolin", "penicillin allergy", "alternative antibiotic", "vancomycin", "clindamycin"] {
            XCTAssertTrue(c.searchText.contains(word), word + " finds the card")
        }
    }

    func testEveryTableHasTheFourColumnsAndAGradeOnEachRow() throws {
        let c = try card()
        let tables = c.sections.filter { $0.kind == .table }
        XCTAssertEqual(tables.count, 13)
        for t in tables {
            XCTAssertEqual(t.columns, ["Procedure", "Recommended", "β-lactam allergy", "Evidence"], t.heading ?? "")
            XCTAssertFalse((t.rows ?? []).isEmpty, t.heading ?? "")
        }
        let all = rows(c)
        XCTAssertEqual(all.count, 41, "the guideline's Table 2 has 41 procedure rows")
        XCTAssertEqual(Set(all.map { $0[0] }).count, all.count, "every procedure row has its own name")
        for r in all {
            XCTAssertEqual(r.count, 4)
            XCTAssertTrue(["A", "B", "C"].contains(String(r[3].prefix(1))), r[0] + ": " + r[3])
            XCTAssertFalse(r[1].isEmpty)
            XCTAssertFalse(r[2].isEmpty)
        }
    }

    func testTheCardiacThoracicAndVascularRows() throws {
        let c = try card()
        XCTAssertEqual(try row(c, "Coronary artery bypass"), ["Coronary artery bypass", "Cefazolin, cefuroxime", "Clindamycin*, vancomycin*", "A"])
        XCTAssertEqual(try row(c, "Cardiac device insertion (e.g., pacemaker implantation)")[1...], ["Cefazolin, cefuroxime", "Clindamycin, vancomycin", "A"])
        XCTAssertEqual(try row(c, "Ventricular assist devices")[1...], ["Cefazolin, cefuroxime", "Clindamycin, vancomycin", "C"])
        XCTAssertEqual(try row(c, "Video-assisted thoracoscopic surgery")[1...], ["Cefazolin, ampicillin–sulbactam", "Clindamycin*, vancomycin*", "C"])
        XCTAssertEqual(try row(c, "Vascular procedures")[1...], ["Cefazolin", "Clindamycin*, vancomycin*", "A"])
        XCTAssertEqual(try row(c, "Heart")[1...], ["Cefazolin", "Clindamycin*, vancomycin*", "A (based on cardiac procedures)"])
    }

    func testRowsWhereNoProphylaxisIsRecommended() throws {
        let c = try card()
        for p in ["Laparoscopic, elective, low risk", "Clean", "Clean operations on the hand, knee or foot without implantation of foreign material"] {
            let r = try row(c, p)
            XCTAssertEqual(r[1], "None", p)
            XCTAssertEqual(r[2], "None", p)
        }
        XCTAssertEqual(try row(c, "Ophthalmic")[2], "None")
    }

    func testTheGramNegativeAlternativesAndTheGrades() throws {
        let c = try card()
        let combo = "Clindamycin or vancomycin + aminoglycoside or aztreonam or fluoroquinolone"
        XCTAssertEqual(try row(c, "Kidney")[1...], ["Cefazolin", combo, "A"])
        XCTAssertEqual(try row(c, "Liver")[1...], ["Piperacillin–tazobactam, cefotaxime + ampicillin", combo, "B"])
        XCTAssertEqual(try row(c, "Cesarean delivery")[1...], ["Cefazolin", "Clindamycin + aminoglycoside", "A"])
        XCTAssertEqual(try row(c, "Small intestine, obstructed")[1...], ["Cefazolin + metronidazole, cefoxitin, cefotetan", "Metronidazole + aminoglycoside or fluoroquinolone", "C"])
        XCTAssertEqual(try row(c, "Hernia repair (hernioplasty and herniorrhaphy)")[1...], ["Cefazolin", "Clindamycin, vancomycin", "A"])
        XCTAssertTrue(try row(c, "Colorectal")[1].hasSuffix("ertapenem"))
        XCTAssertEqual(try row(c, "Total joint replacement")[1...], ["Cefazolin", "Clindamycin*, vancomycin*", "A"])
        XCTAssertEqual(try row(c, "Implantation of internal fixation devices (e.g., nails, screws, plates, wires)")[3], "C")
    }

    func testTheNotesSayWhatTheStarAndTheDrugClassesMean() throws {
        let c = try card()
        let reading = try XCTUnwrap(c.sections.first { $0.heading == "Reading the Tables" })
        let items = (reading.items ?? []).joined(separator: "\n")
        XCTAssertTrue(items.contains("gentamicin or tobramycin"))
        XCTAssertTrue(items.contains("ciprofloxacin or levofloxacin"))
        XCTAssertTrue(items.contains("* Where pathogens other than staphylococci and streptococci are likely"))
        XCTAssertTrue(items.contains("single preoperative dose of vancomycin"), "the MRSA note")
        XCTAssertTrue(items.contains("120 minutes for vancomycin"))
        let allergy = try XCTUnwrap(c.sections.first { $0.heading == "Who Needs the Alternative" })
        XCTAssertTrue((allergy.text ?? "").contains("IgE-mediated"))
        XCTAssertTrue((allergy.note ?? "").contains("2013"), "the guideline's age is stated")
    }
}
