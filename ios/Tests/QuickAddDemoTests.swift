import XCTest
@testable import PeriopSignal

/// Screenshot 161: the quick-add line read against the demo patient, the way the bar reads it (once on appear, again a
/// moment later), so a preview that comes and goes can be told from the reader.
final class QuickAddDemoTests: XCTestCase {
    private let line = "68M for lap chole, HTN DM2 on insulin, K 5.4 Cr 1.6, A-line L radial 20G"

    func testTheShotLineReadsTheSameAgainstTheDemoPatient() {
        let demo = PatientDemo.record
        let start = Date()
        let first = QuickAdd.read(line, record: demo, tab: .preop, now: Date())
        let firstTime = Date().timeIntervalSince(start)
        let chips = QuickAdd.chips(first, record: demo)
        let shown = chips.map { $0.destination + " " + $0.value + ($0.statusText.map { " (" + $0 + ")" } ?? "") }
        XCTAssertFalse(first.isEmpty, shown.joined(separator: ", "))

        // What screenshot 161 showed until 1.8's fifth review: five to add, against what the demo already holds.
        let addable = chips.filter(\.canAdd)
        XCTAssertEqual(addable.count, 5, shown.joined(separator: ", "))
        XCTAssertTrue(addable.contains { $0.destination == "Patient" && $0.value.hasPrefix("Age 68") }, shown.joined(separator: ", "))
        XCTAssertTrue(addable.contains { $0.destination == "Labs" && $0.value.hasPrefix("K 5.4") }, shown.joined(separator: ", "))
        XCTAssertTrue(addable.contains { $0.destination == "Labs" && $0.value.hasPrefix("Cr 1.6") }, shown.joined(separator: ", "))
        XCTAssertTrue(chips.contains { $0.destination == "Patient" && $0.value == "Male" && !$0.canAdd }, shown.joined(separator: ", "))

        // Read again a second later, as the bar's own reading task does: the same chips.
        let again = Date()
        let second = QuickAdd.read(line, record: demo, tab: .preop, now: Date().addingTimeInterval(1))
        let secondTime = Date().timeIntervalSince(again)
        XCTAssertEqual(QuickAdd.chips(second, record: demo).map(\.id), chips.map(\.id))
        XCTAssertEqual(second.findings.map(\.id), first.findings.map(\.id))

        // Reading this line is quick: a pattern that backtracks badly would show here first.
        XCTAssertLessThan(secondTime, 2.0, String(format: "first read %.3f s, second %.3f s", firstTime, secondTime))
    }

    func testTheShotLineReadsTheSameOnAnEmptyPatient() {
        let q = QuickAdd.read(line, record: PatientRecord(), tab: .preop, now: Date())
        XCTAssertEqual(QuickAdd.chips(q, record: PatientRecord()).filter(\.canAdd).count, 12)
    }
}
