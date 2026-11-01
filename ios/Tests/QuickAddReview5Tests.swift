import XCTest
@testable import PeriopSignal

/// The fifth clinical review of the quick-add bar and the full note (1.8): close variants of the fourth review's fixed
/// lines, kept to what would be unsafe. All lines are synthetic; no real patient data.
final class QuickAddReview5Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))! }

    private func read(_ s: String, _ tab: QuickAddTab = .preop) -> QuickAddReading {
        QuickAdd.read(s, record: PatientRecord(), tab: tab, now: now)
    }
    private func change(_ q: QuickAddReading, _ id: String) -> PatientNoteChange? { q.findings.first { $0.id == id }?.change }
    private func note(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func change(_ n: PatientNoteReading, _ id: String) -> PatientNoteChange? { n.findings.first { $0.id == id }?.change }

    /// The laryngoscope after the grade written "w/ DL" or "(DL)": still the view grade, not the mask grade.
    func testGradeThenLaryngoscopeVariants() {
        for line in ["easy mask gr 3 w/ DL, bougie, 7.5 ETT", "easy mask grade 3 (DL), bougie, 7.5 ETT"] {
            var r = PatientRecord()
            PatientNote.apply(read(line, .intraop).findings.map(\.change), to: &r)
            XCTAssertNotEqual(r.maskGrade, 3, line + ": the view grade filed as the mask grade")
        }
    }

    /// An earlier value marked "3 days ago" or "(last wk)" is not the current one.
    func testEarlierMarkTimeVariants() {
        XCTAssertNotEqual(change(read("Cr 1.1 3 days ago, now 1.6"), "lab:cr"), .lab("cr", 1.1))
        XCTAssertNotEqual(change(read("Cr 1.1 (last wk), now 1.6"), "lab:cr"), .lab("cr", 1.1))
        XCTAssertNotEqual(change(note("Cr 1.1 3 days ago, now 1.6"), "lab:cr"), .lab("cr", 1.1), "full-note path")
    }

    /// A header written "Pt." or followed by a name in capitals: the name is masked and not filed into Other conditions.
    func testFullNoteHeaderVariants() {
        for text in ["Pt. Jane Doe\n68F for lap chole, HTN", "Patient JANE DOE\n68F for lap chole, HTN"] {
            let n = note(text)
            let lower = n.other.lowercased()
            XCTAssertTrue(!n.identifiers.isEmpty || !(lower.contains("jane") || lower.contains("doe")), "filed into Other conditions: " + n.other)
        }
    }
}
