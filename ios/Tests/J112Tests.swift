import XCTest
@testable import PeriopSignal

/// 1.12 follow-up, helper J (Ben, Nov 12): past surgical history newest first everywhere (part 1), and the typing bar adds
/// every past surgery, not only the first (part 2).
final class J112Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 8))! }

    private func d(_ m: Int, _ day: Int, _ y: Int) -> PatientMonthYear { PatientMonthYear(month: m, day: day, year: y) }
    private func my(_ m: Int, _ y: Int) -> PatientMonthYear { PatientMonthYear(month: m, year: y) }
    private func yr(_ y: Int) -> PatientMonthYear { PatientMonthYear(year: y) }

    /// What the Past Surgical History bar does with one line, as QuickAddBar.add does: read it, take the chips that can be
    /// added, file them. With `tabBar` the line goes to the Preoperative tab's bar instead.
    @discardableResult
    private func bar(_ line: String, _ r: inout PatientRecord, tabBar: Bool = false) -> [QuickAddChip] {
        let q = QuickAdd.read(line, record: r, tab: .preop, now: now, surgicalHistory: !tabBar)
        let chosen = QuickAdd.chips(q, record: r).filter(\.canAdd)
        PatientNote.apply(QuickAdd.changes(chosen), to: &r)
        return chosen
    }

    private func readOperations(_ line: String, tabBar: Bool = false) -> [(String, PatientMonthYear)] {
        QuickAdd.read(line, record: PatientRecord(), tab: .preop, now: now, surgicalHistory: !tabBar).findings.compactMap { f in
            if case .pastSurgery(let t, let date) = f.change { return (t, date) }
            return nil
        }
    }

    private func typed(_ name: String, _ date: PatientMonthYear = PatientMonthYear()) -> PatientSurgery {
        PatientSurgery(procedures: [PlannedProcedure(name: name)], date: date)
    }

    // MARK: Part 2: the typing bar adds every past surgery (reproductions)

    /// Candidate cause 1: the bar read a line strictly, so an operation that is not an operative word, an eponym or a
    /// procedure-list name was not read at all. On this bar everything typed is an operation.
    func testEveryOperationTypedOnTheBarIsRead() {
        let lines = ["bunion surgery", "jaw wiring", "knee scope", "tubes tied", "tonsils out", "ACL", "ex lap", "Whipple", "wisdom teeth out",
                     "gallbladder out", "hysterectomy", "hip pinning", "carpal tunnel release", "back surgery", "eye surgery", "C-section",
                     "vasectomy", "heart bypass", "appy", "chole", "lap band", "cataract", "deviated septum", "hammertoe"]
        var missed: [String] = []
        for line in lines {
            var r = PatientRecord()
            bar(line, &r)
            if r.surgeries.count != 1 { missed.append(line) }
        }
        XCTAssertTrue(missed.isEmpty, "not filed by the Past Surgical History bar: " + missed.joined(separator: " | "))
    }

    /// Candidate cause 1b: an item with a reason ("for sleep apnea") was dropped, and so was everything after it.
    func testAnOperationWithAReasonDoesNotStopTheOnesAfterIt() {
        var r = PatientRecord()
        bar("tonsillectomy for sleep apnea, jaw wiring 2012, appendectomy 2010", &r)
        XCTAssertEqual(r.surgeries.count, 3, r.surgeries.map(\.text).joined(separator: " | "))
        var s = PatientRecord()
        bar("stent for CAD 2019, CABG 2021", &s)
        XCTAssertEqual(s.surgeries.count, 2, s.surgeries.map(\.text).joined(separator: " | "))
    }

    /// Candidate cause 2: two different typed operations read as one (`same`), so the second was "already recorded".
    func testDifferentTypedOperationsAreNeverTheSameOperation() {
        let pairs: [(String, String)] = [("Hernia repair", "Inguinal hernia repair"), ("Knee surgery", "Knee surgery on the other side"),
                                         ("Jaw wiring", "Jaw wiring revision"), ("Hip pinning", "Hip pinning left"), ("Eye surgery", "Eye surgery laser")]
        var wrong: [String] = []
        for (a, b) in pairs where PastSurgeryNote.same(typed(a), typed(b)) { wrong.append(a + " ~ " + b) }
        XCTAssertTrue(wrong.isEmpty, "read as one operation: " + wrong.joined(separator: " | "))
        // The same words are still one.
        XCTAssertTrue(PastSurgeryNote.same(typed("Jaw wiring"), typed("jaw wiring")))
        XCTAssertTrue(PastSurgeryNote.same(typed("Jaw wiring", yr(2012)), typed("Jaw wiring", my(6, 2012))))
        XCTAssertFalse(PastSurgeryNote.same(typed("Jaw wiring", yr(2012)), typed("Jaw wiring", yr(2015))), "another year, another operation")
    }

    /// Operations added one after the other through the bar's own path: each is a new entry.
    func testOperationsFiledOneAfterTheOtherAreAllKept() {
        let sequences: [[String]] = [
            ["appendectomy", "cholecystectomy"],
            ["hernia repair", "inguinal hernia repair 2019"],
            ["knee surgery", "knee surgery 2020 on the other side"],
            ["jaw wiring 2012", "jaw wiring revision 2014"],
            ["bunion surgery", "tubes tied"],
            ["appendectomy 2010", "appendectomy 2015"],
            ["appendectomy 2010", "cholecystectomy 2015", "knee scope 2020"],
        ]
        var wrong: [String] = []
        for seq in sequences {
            var r = PatientRecord()
            for line in seq { bar(line, &r) }
            if r.surgeries.count != seq.count { wrong.append(seq.joined(separator: " then ") + " -> " + r.surgeries.map(\.text).joined(separator: " / ")) }
        }
        XCTAssertTrue(wrong.isEmpty, wrong.joined(separator: " | "))
    }

    /// The second line's chip is offered (not "already recorded") after the first was filed.
    func testTheSecondLinesChipCanBeAdded() {
        var r = PatientRecord()
        bar("appendectomy 2010", &r)
        let q = QuickAdd.read("cholecystectomy 2015", record: r, tab: .preop, now: now, surgicalHistory: true)
        let chips = QuickAdd.chips(q, record: r)
        XCTAssertEqual(chips.filter(\.canAdd).count, 1, chips.map { $0.value + " [" + ($0.statusText ?? "new") + "]" }.joined(separator: " | "))
        let q2 = QuickAdd.read("jaw wiring", record: r, tab: .preop, now: now, surgicalHistory: true)
        XCTAssertEqual(QuickAdd.chips(q2, record: r).filter(\.canAdd).count, 1)
    }

    /// One line of several operations, each with its date or none, on the page's bar and on the tab's.
    func testALineOfSeveralOperationsFilesEachWithItsDate() {
        for line in ["appy 2010, chole 2015, knee scope 2020", "appendectomy 2010, cholecystectomy 2015, knee scope 2020"] {
            var r = PatientRecord()
            bar(line, &r)
            XCTAssertEqual(r.surgeries.count, 3, line + " -> " + r.surgeries.map(\.text).joined(separator: " / "))
            XCTAssertEqual(r.surgeries.map(\.date.year), [2010, 2015, 2020], line)
        }
        var s = PatientRecord()
        bar("appendectomy, cholecystectomy, knee scope", &s)
        XCTAssertEqual(s.surgeries.count, 3, s.surgeries.map(\.text).joined(separator: " / "))
        var t = PatientRecord()
        bar("tubes tied, jaw wiring, tonsils out", &t)
        XCTAssertEqual(t.surgeries.count, 3, t.surgeries.map(\.text).joined(separator: " / "))
    }

    /// The same line typed in the Preoperative tab's bar ("PSH: ...", "s/p ..."), whose reading stays the stricter one.
    func testThePreoperativeTabsBarFilesEveryOperationOfAPSHLine() {
        var r = PatientRecord()
        bar("PSH: appendectomy 2010, cholecystectomy 2015, knee scope 2020", &r, tabBar: true)
        XCTAssertEqual(r.surgeries.count, 3, r.surgeries.map(\.text).joined(separator: " / "))
        var s = PatientRecord()
        bar("s/p appendectomy 2010, cholecystectomy 2015", &s, tabBar: true)
        XCTAssertEqual(s.surgeries.count, 2, s.surgeries.map(\.text).joined(separator: " / "))
        // And one after the other.
        var u = PatientRecord()
        bar("PSH: appendectomy 2010", &u, tabBar: true)
        bar("PSH: cholecystectomy 2015", &u, tabBar: true)
        XCTAssertEqual(u.surgeries.count, 2, u.surgeries.map(\.text).joined(separator: " / "))
    }

    /// What is not an operation is still not made one.
    func testTheLenientBarStillRefusesWhatIsNotAnOperation() {
        for line in ["none", "no surgeries", "no prior surgeries", "denies any surgeries", "2015", "06/2015", "HTN", "Hgb 12", "metoprolol 25 bid",
                     "hiatal hernia", "under GA"] {
            XCTAssertTrue(readOperations(line).isEmpty, "filed as an operation: " + line)
        }
    }

    /// The Preoperative tab's bar and the note reader keep their stricter rule: a diagnosis after "h/o" is not an operation, and
    /// words that are no operation are not made one.
    func testThePreoperativeTabsBarAndTheNoteReaderAreNotLoosened() {
        for line in ["h/o hiatal hernia", "h/o HTN", "history of AAA 4.5 cm"] {
            XCTAssertTrue(readOperations(line, tabBar: true).isEmpty, "filed from the tab's bar: " + line)
        }
        XCTAssertTrue(readOperations("jaw wiring", tabBar: true).isEmpty, "a bare unlisted operation on the tab's bar is not read as past surgery")
        var state = PastSurgeryNote.State(open: true, bodyEmpty: true)
        XCTAssertTrue(PastSurgeryNote.read("jaw wiring", state: &state, now: now).operations.isEmpty, "the note reader's strict rule")
        var lenient = PastSurgeryNote.State(open: true, bodyEmpty: true)
        XCTAssertEqual(PastSurgeryNote.read("jaw wiring", state: &lenient, now: now, lenient: true).operations.map(\.text), ["jaw wiring"])
    }

    // MARK: Part 1: past surgical history, newest first

    private func entries(_ pairs: [(String, PatientMonthYear)]) -> [PatientSurgery] { pairs.map { typed($0.0, $0.1) } }
    private func names(_ list: [PatientSurgery]) -> [String] { list.map { $0.procedures.first?.name ?? "" } }

    func testFullDatesAreListedNewestFirstWithTheDayBreakingTies() {
        let list = entries([("a", d(3, 5, 2019)), ("b", d(3, 20, 2019)), ("c", d(12, 1, 2018)), ("d", d(11, 30, 2019))])
        XCTAssertEqual(names(PatientSurgery.chronological(list)), ["d", "b", "a", "c"])
    }

    func testMonthAndYearAndYearOnlyAreListedNewestFirst() {
        let list = entries([("old", yr(1998)), ("mid", my(6, 2015)), ("new", my(3, 2019)), ("recent", yr(2022)), ("jan", my(1, 2015))])
        XCTAssertEqual(names(PatientSurgery.chronological(list)), ["recent", "new", "mid", "jan", "old"])
    }

    func testWithinAYearAMonthComesBeforeTheYearAloneAndADayBeforeNone() {
        let list = entries([("year", yr(2015)), ("june", my(6, 2015)), ("june14", d(6, 14, 2015)), ("june20", d(6, 20, 2015)), ("dec", my(12, 2015)), ("jan", my(1, 2015))])
        XCTAssertEqual(names(PatientSurgery.chronological(list)), ["dec", "june20", "june14", "june", "jan", "year"])
        // Whatever order they were entered in.
        XCTAssertEqual(names(PatientSurgery.chronological(Array(list.reversed()))), ["dec", "june20", "june14", "june", "jan", "year"])
    }

    func testNoDateComesLastInTheOrderEntered() {
        let list = entries([("none1", PatientMonthYear()), ("y", yr(2001)), ("none2", PatientMonthYear()), ("m", my(2, 2020)), ("none3", PatientMonthYear())])
        XCTAssertEqual(names(PatientSurgery.chronological(list)), ["m", "y", "none1", "none2", "none3"])
    }

    func testTiesKeepTheOrderEntered() {
        // Many entries on one date, so an unstable sort would show: the order entered is kept.
        let same = (0..<30).map { typed("t\($0)", my(6, 2015)) }
        XCTAssertEqual(names(PatientSurgery.chronological(same)), (0..<30).map { "t\($0)" })
        let mixed = entries([("a", yr(2015)), ("b", my(6, 2015)), ("c", yr(2015)), ("d", my(6, 2015)), ("e", yr(2015))])
        XCTAssertEqual(names(PatientSurgery.chronological(mixed)), ["b", "d", "a", "c", "e"])
    }

    func testAMonthWithoutAYearIsNoDateAndAMixedListIsInOrder() {
        let list = entries([("1998", yr(1998)), ("none", PatientMonthYear()), ("d1", d(6, 14, 2015)), ("2015", yr(2015)), ("2019", my(3, 2019)),
                            ("monthOnly", PatientMonthYear(month: 5)), ("m2015", my(6, 2015)), ("d2", d(6, 20, 2015))])
        XCTAssertEqual(names(PatientSurgery.chronological(list)), ["2019", "d2", "d1", "m2015", "2015", "1998", "none", "monthOnly"])
    }

    func testTheRecordKeepsWhatIsStoredInTheOrderEntered() {
        var r = PatientRecord()
        r.surgeries = entries([("old", yr(1998)), ("new", my(3, 2019))])
        let stored = r.surgeries.map(\.id)
        XCTAssertEqual(names(r.surgeriesNewestFirst), ["new", "old"])
        XCTAssertEqual(r.surgeries.map(\.id), stored, "nothing is reordered in the record")
    }

    /// Both summaries and the History row print the same order.
    func testTheSummariesAndTheHistoryRowPrintTheSameOrder() throws {
        var r = PatientRecord()
        r.ageYears = 60
        r.surgeries = entries([("Appendectomy", yr(1998)), ("Tonsillectomy", PatientMonthYear()), ("Jaw wiring", yr(2015)), ("Knee scope", my(3, 2019)),
                               ("Gallbladder out", d(6, 14, 2015)), ("Hernia repair", my(5, 2015))])
        let expected = "Knee scope (03/2019); Gallbladder out (06/2015); Hernia repair (05/2015); Jaw wiring (2015); Appendectomy (1998); Tonsillectomy"
        func psh(_ blocks: [SummaryBlock]) throws -> String { try XCTUnwrap(blocks.first { $0.key == "psh" }).text }
        XCTAssertEqual(try psh(PatientBriefs.preop(r, now: now)), expected, "the Preprocedure Summary")
        XCTAssertEqual(try psh(PatientBriefs.handoff(r, now: now)), expected, "the handoff")
        let line = try XCTUnwrap(PatientSummary.historyLines(r, now: now, dates: .summary(now: now)).first { $0.label == "Past surgical history" })
        XCTAssertEqual(line.text, expected, "the history lines")
        // The History row and the folded box (the app's own dates).
        let row = r.capitalized.surgeriesNewestFirst.map(\.text).joined(separator: "; ")
        XCTAssertEqual(row, "Knee scope (03/2019); Gallbladder out (06/14/2015); Hernia repair (05/2015); Jaw wiring (2015); Appendectomy (1998); Tonsillectomy")
        // A list from before 1.10 (the evaluation's own) joins the same list.
        r.intrathoracic = [typed("Redo sternotomy", my(1, 2020))]
        XCTAssertEqual(try psh(PatientBriefs.handoff(r, now: now)), "Redo sternotomy (01/2020); " + expected)
    }

    /// The copied handoff and the archive carry the block's text, so they have the same order.
    func testTheCopiedHandoffHasTheSameOrder() {
        var r = PatientRecord()
        r.ageYears = 60
        r.surgeries = entries([("Appendectomy", yr(1998)), ("Knee scope", my(3, 2019))])
        let blocks = PatientBriefs.handoff(r, now: now)
        let text = blocks.map { ($0.label ?? "") + ": " + $0.plainLinesOfText.joined(separator: "\n") }.joined(separator: "\n")
        let knee = text.range(of: "Knee scope")?.lowerBound
        let appy = text.range(of: "Appendectomy")?.lowerBound
        XCTAssertNotNil(knee)
        XCTAssertNotNil(appy)
        if let knee, let appy { XCTAssertLessThan(knee, appy) }
    }

    func testPreviousCardiacSurgeryStillPointsAtItsEntryAndListsNewestFirst() {
        var r = PatientRecord()
        PatientHistoryDetails.setCardiacSurgery("CABG ×3 2012", &r)
        let cardiacID = r.hx.cardiacSurgeryID
        XCTAssertNotNil(cardiacID)
        // Newer operations entered after it: it is still the same entry, in the same place in the record.
        PastSurgeryNote.add("knee scope", my(3, 2024), to: &r)
        PastSurgeryNote.add("jaw wiring", yr(2025), to: &r)
        XCTAssertEqual(r.hx.cardiacSurgeryID, cardiacID)
        XCTAssertEqual(r.surgeries.first?.id, cardiacID, "stored first, as entered")
        XCTAssertEqual(PatientHistoryDetails.cardiacSurgeryText(r), "CABG ×3 2012")
        XCTAssertEqual(r.surgeriesNewestFirst.last?.id, cardiacID, "listed last: the oldest")
        // Typing on the cardiovascular page edits the same entry.
        PatientHistoryDetails.setCardiacSurgery("CABG ×4 2012", &r)
        XCTAssertEqual(r.surgeries.first?.id, cardiacID)
        XCTAssertEqual(r.hx.cardiacSurgeryID, cardiacID)
        // Two cardiac operations: the evaluation's line lists the newer first.
        PastSurgeryNote.add("AVR", my(6, 2019), cardiac: true, to: &r)
        let cardiac = PatientPreop.previousCardiacSurgery(r)
        XCTAssertEqual(cardiac.count, 2)
        XCTAssertEqual(cardiac.map(\.date), [my(6, 2019), PatientMonthYear()], "the AVR first; the CABG typed on the cardiovascular page has its words only")
        XCTAssertEqual(r.hx.cardiacSurgeryID, cardiacID, "the link did not move")
    }

    /// A row edited after the list was shown sorted edits its own entry (the page binds by id, never by index).
    func testEditingARowAfterTheListIsSortedEditsThatEntry() {
        var r = PatientRecord()
        r.surgeries = entries([("old", yr(1998)), ("mid", yr(2010)), ("new", yr(2020))])
        let fixed = PastSurgeryOrder.ids(r.surgeries)
        let rows = PastSurgeryOrder.rows(r.surgeries, fixed: fixed)
        XCTAssertEqual(names(rows), ["new", "mid", "old"])
        // The row at the top of the page is "new", stored last: editing it must not touch the first stored entry.
        var edited = rows[0]
        edited.date = yr(2021)
        PatientHistoryDetails.editSurgery(edited, &r)
        XCTAssertEqual(r.surgeries.map(\.date), [yr(1998), yr(2010), yr(2021)])
        XCTAssertEqual(names(r.surgeries), ["old", "mid", "new"])
        // And the row at the bottom.
        var last = rows[2]
        last.setProcedures([PlannedProcedure(name: "oldest")])
        PatientHistoryDetails.editSurgery(last, &r)
        XCTAssertEqual(names(r.surgeries), ["oldest", "mid", "new"])
        XCTAssertEqual(r.surgeries.map(\.date), [yr(1998), yr(2010), yr(2021)])
    }

    /// The order is worked out when the page appears and when an entry is added or removed, not on every keystroke.
    func testRowsDoNotJumpWhileADateIsTypedButSortWhenTheListChanges() {
        var r = PatientRecord()
        r.surgeries = entries([("old", yr(1998)), ("mid", yr(2010)), ("new", yr(2020))])
        var fixed = PastSurgeryOrder.ids(r.surgeries)
        // A date typed into the bottom row that would put it on top: the rows stay where they are.
        var e = PastSurgeryOrder.rows(r.surgeries, fixed: fixed)[2]
        e.date = yr(2024)
        PatientHistoryDetails.editSurgery(e, &r)
        XCTAssertEqual(names(PastSurgeryOrder.rows(r.surgeries, fixed: fixed)), ["new", "mid", "old"], "no jump while typing")
        // The page shown again: sorted.
        XCTAssertEqual(names(PastSurgeryOrder.rows(r.surgeries, fixed: PastSurgeryOrder.ids(r.surgeries))), ["old", "new", "mid"])
        // An entry added (the page's bar filing one, or the Add button): before the page sorts again, a new row is at the end.
        PastSurgeryNote.add("jaw wiring", yr(2022), to: &r)
        XCTAssertEqual(names(PastSurgeryOrder.rows(r.surgeries, fixed: fixed)).last, "Jaw wiring")
        fixed = PastSurgeryOrder.ids(r.surgeries)
        XCTAssertEqual(names(PastSurgeryOrder.rows(r.surgeries, fixed: fixed)), ["old", "Jaw wiring", "new", "mid"])
        // An entry removed: it is gone from the rows.
        let gone = r.surgeries[0].id
        r.surgeries.removeAll { $0.id == gone }
        XCTAssertEqual(names(PastSurgeryOrder.rows(r.surgeries, fixed: fixed)), ["Jaw wiring", "new", "mid"])
        // Nothing fixed yet (the page's first frame): sorted.
        XCTAssertEqual(names(PastSurgeryOrder.rows(r.surgeries, fixed: [])), ["Jaw wiring", "new", "mid"])
    }

    /// A page opened on a 1.11 record (no day anywhere) lists it newest first too.
    func testARecordFromBeforeTheDayWasAddedOpensAndSorts() throws {
        let json = """
        {"surgeries":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Appendectomy","date":{"year":1998}},\
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FE","name":"Total knee arthroplasty","side":"right","date":{"month":3,"year":2019}}]}
        """
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.surgeries.count, 2)
        XCTAssertEqual(r.surgeriesNewestFirst.map(\.date), [my(3, 2019), yr(1998)])
    }
}
