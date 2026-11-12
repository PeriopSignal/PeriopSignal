import XCTest
@testable import PeriopSignal

/// 1.12: a second bare date after an operation is that operation again ("C-section 2012, 2015"). Before, the operation
/// with its first date was dropped and nothing was filed.
final class PastSurgeryDates112Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9))! }

    private func operations(_ line: String, bar: Bool) -> [(String, Int?)] {
        QuickAdd.read(line, record: PatientRecord(), tab: .preop, now: now, surgicalHistory: bar).findings.compactMap { f in
            if case .pastSurgery(let t, let date) = f.change { return (t, date.year) }
            return nil
        }
    }

    func testASecondBareDateIsTheSameOperationAgain() {
        let ops = operations("C-section 2012, 2015", bar: true)
        XCTAssertEqual(ops.count, 2, "\(ops)")
        XCTAssertEqual(ops.map(\.1), [2012, 2015])
        XCTAssertEqual(Set(ops.map { $0.0.lowercased() }).count, 1, "the same operation both times: \(ops)")

        var r = PatientRecord()
        let q = QuickAdd.read("C-section 2012, 2015, appendectomy 2010", record: r, tab: .preop, now: now, surgicalHistory: true)
        PatientNote.apply(QuickAdd.changes(QuickAdd.chips(q, record: r).filter(\.canAdd)), to: &r)
        XCTAssertEqual(r.surgeries.count, 3, r.surgeries.map(\.text).joined(separator: " / "))
        XCTAssertEqual(Set(r.surgeries.compactMap(\.date.year)), [2010, 2012, 2015])
    }

    func testOneBareDateStillBelongsToTheOperationBeforeIt() {
        let ops = operations("CABG x3, 2019", bar: true)
        XCTAssertEqual(ops.count, 1, "\(ops)")
        XCTAssertEqual(ops.first?.1, 2019)
        let two = operations("appendectomy, 2010, cholecystectomy, 2015", bar: true)
        XCTAssertEqual(two.map(\.1), [2010, 2015], "\(two)")
    }

    func testTheSameAfterAHeaderOnThePreoperativeBar() {
        let ops = operations("PSH: C-section 2012, 2015", bar: false)
        XCTAssertEqual(ops.map(\.1), [2012, 2015], "\(ops)")
        let lead = operations("s/p C-section 2012, 2015", bar: false)
        XCTAssertEqual(lead.map(\.1), [2012, 2015], "\(lead)")
    }
}
