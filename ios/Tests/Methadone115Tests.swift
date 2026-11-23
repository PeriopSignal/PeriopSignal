import XCTest
@testable import PeriopSignal

/// Ben, Nov 23: "add methadone to notable intraop meds". The Methadone chip of the Intraoperative tab's notable medications:
/// last in the list, a dose typed beside it once chosen (none suggested), told in the row, the summaries and the handoff as the
/// other chips are. Methadone on the home medication list is a different thing and is left as it was.
final class Methadone115Tests: XCTestCase {

    private func block(_ blocks: [SummaryBlock], _ key: String) throws -> SummaryBlock {
        try XCTUnwrap(blocks.first { $0.key == key }, "block \(key) in \(blocks.map(\.key))")
    }

    func testMethadoneIsTheLastChipWithAnIdAndALabel() throws {
        let last = try XCTUnwrap(PatientNotableMeds.options.last)
        XCTAssertEqual(last.id, "methadone")
        XCTAssertEqual(last.label, "Methadone")
        XCTAssertEqual(last.full, "Methadone", "no longer name: the label is the whole name")
        XCTAssertEqual(PatientNotableMeds.option("methadone")?.label, "Methadone")
        XCTAssertEqual(Set(PatientNotableMeds.options.map(\.id)).count, PatientNotableMeds.options.count, "unique ids")
        // The nine before it are where they were.
        XCTAssertEqual(PatientNotableMeds.options.dropLast().map(\.id),
                       ["milrinoneBolus", "milrinoneInhaled", "txa", "amicar", "pcc", "fibrinogen", "factorVIIa", "cyanokit", "methyleneBlue"])
    }

    func testAChosenMethadoneHasNoDoseUntilOneIsTypedAndASecondTapClearsIt() {
        var m = PatientNotableMeds()
        m.toggle("methadone")
        XCTAssertTrue(m.has("methadone"))
        XCTAssertEqual(m.dose("methadone"), "", "no default dose")
        XCTAssertEqual(m.items, ["Methadone"])
        m.setDose("methadone", "10 mg")
        XCTAssertEqual(m.dose("methadone"), "10 mg")
        XCTAssertEqual(m.items, ["Methadone 10 mg"])
        m.toggle("methadone")
        XCTAssertTrue(m.isEmpty)
        m.toggle("methadone")
        XCTAssertEqual(m.dose("methadone"), "", "chosen again: the old dose is gone")
        // A dose is only typed beside a chosen chip.
        var none = PatientNotableMeds()
        none.setDose("methadone", "10 mg")
        XCTAssertFalse(none.has("methadone"))
    }

    func testMethadoneComesLastInTheListWhateverOrderItWasChosenIn() {
        var m = PatientNotableMeds()
        for id in ["methadone", "methyleneBlue", "txa", "milrinoneBolus"] { m.toggle(id) }
        m.setDose("methadone", "10 mg")
        XCTAssertEqual(m.items, ["Milrinone bolus", "TXA", "Methylene blue", "Methadone 10 mg"])
    }

    @MainActor func testNoDoseIsSuggestedForMethadoneAnywhereOnThePage() throws {
        // The chip, its words and the page's notes carry no number: a dose is printed only if it was typed.
        let o = try XCTUnwrap(PatientNotableMeds.options.last)
        for w in [o.label, o.full, IntraopMedicationsPage.notableNote, IntraopNotableMedicationLink.hint] {
            XCTAssertNil(w.range(of: #"\d\s*(?:mg|mcg|g|units)\b"#, options: .regularExpression), "no dose in: \(w)")
        }
        var m = PatientNotableMeds()
        m.toggle("methadone")
        XCTAssertTrue(m.entries.allSatisfy { $0.dose.isEmpty })
    }

    func testTheRecordRoundTripsWithMethadoneAndItsDose() throws {
        var r = PatientRecord()
        r.notableMeds.toggle("methadone"); r.notableMeds.setDose("methadone", "10 mg")
        r.notableMeds.toggle("txa")
        let data = try JSONEncoder().encode(r)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"methadone\""), "the id is what the record stores")
        let back = try JSONDecoder().decode(PatientRecord.self, from: data)
        XCTAssertEqual(back.notableMeds, r.notableMeds)
        XCTAssertEqual(back.notableMeds.dose("methadone"), "10 mg")
        XCTAssertEqual(back.notableMeds.items, ["TXA", "Methadone 10 mg"])
    }

    func testARecordSavedWithoutMethadoneStillOpens() throws {
        // A record saved by 1.12 before this chip, with other chips and a dose.
        let saved = #"{"notableMeds":{"entries":[{"id":"txa","dose":"1 g"},{"id":"methyleneBlue"}]},"medsGiven":"Dexamethasone 4 mg"}"#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(saved.utf8))
        XCTAssertEqual(r.notableMeds.items, ["TXA 1 g", "Methylene blue"])
        XCTAssertFalse(r.notableMeds.has("methadone"))
        // A record saved before the chips existed.
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"procedure":"CABG"}"#.utf8))
        XCTAssertTrue(old.notableMeds.isEmpty)
        // A build that meets a chip it does not know keeps it, told by its id after the known ones.
        var m = PatientNotableMeds()
        m.entries = [PatientNotableMeds.Entry("somethingNew", dose: "2 mg"), PatientNotableMeds.Entry("methadone")]
        XCTAssertEqual(m.items, ["Methadone", "somethingNew 2 mg"])
    }

    @MainActor func testTheIntraopRowTellsMethadoneWithItsDose() {
        var r = PatientRecord()
        r.notableMeds.toggle("methadone"); r.notableMeds.setDose("methadone", "10 mg")
        r.notableMeds.toggle("txa"); r.notableMeds.setDose("txa", "1 g")
        r.medsGiven = "dexamethasone 4 mg"
        let lines = IntraopNotableMedicationLink.lines(r, antibiotics: [])
        XCTAssertEqual(lines.map(\.text), ["TXA 1 g; Methadone 10 mg", "Dexamethasone 4 mg"])
    }

    func testTheHandoffPrintsMethadoneWithItsDoseBeforeTheFreeText() throws {
        var r = PatientRecord()
        r.notableMeds.toggle("methadone"); r.notableMeds.setDose("methadone", "10 mg")
        r.notableMeds.toggle("amicar")
        r.medsGiven = "Dexamethasone 4 mg"
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "infusions").text, "Intraop medications: Amicar; Methadone 10 mg; Dexamethasone 4 mg")
        // Chosen with no dose: the name alone.
        var bare = PatientRecord()
        bare.notableMeds.toggle("methadone")
        XCTAssertEqual(try block(PatientBriefs.handoff(bare), "infusions").text, "Intraop medications: Methadone")
        XCTAssertEqual(PatientNotableMeds.lines(bare), ["Methadone"])
    }

    func testMethadoneIsNotAnInfusion() {
        var r = PatientRecord()
        r.notableMeds.toggle("methadone")
        XCTAssertTrue(r.infusions.isEmpty)
        XCTAssertTrue(r.homeInfusions.isEmpty)
        XCTAssertTrue(IntraopInfusionList.rows(r).isEmpty)
    }

    func testNothingTypedIsReadAsTheMethadoneChip() {
        // The only typed text read into a chip is the TXA a 1.11 record held in the free text; the other chips have no reader and
        // neither has this one. A methadone typed in the free text stays there as typed.
        var r = PatientRecord()
        r.medsGiven = "Methadone 10 mg; dexamethasone 4 mg"
        XCTAssertTrue(PatientNotableMeds.pageState(r).entries.isEmpty)
        XCTAssertEqual(PatientNotableMeds.pageState(r).text, r.medsGiven)
        PatientNotableMeds.migrateLegacy(&r)
        XCTAssertTrue(r.notableMeds.isEmpty)
        XCTAssertEqual(r.medsGiven, "Methadone 10 mg; dexamethasone 4 mg")
        XCTAssertNil(PatientNotableMeds.legacyTXA(in: r.medsGiven))
    }

    func testMethadoneOnTheHomeMedicationListIsAsItWas() throws {
        let entry = try XCTUnwrap(MedicationCatalog.entry(named: "methadone"))
        XCTAssertEqual(entry.name, "Methadone")
        let parsed = MedicationCatalog.parse("methadone 10 mg bid")
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.catalogID, entry.id)
        XCTAssertTrue(MedicationCatalog.flags(for: parsed).contains("opioid"), "still flagged as an opioid")
    }
}
