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
}
