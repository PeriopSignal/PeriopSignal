import XCTest
@testable import PeriopSignal

/// The fourth, narrow clinical review of the quick-add bar and the full note (1.8): close variants of the third
/// review's fixed lines, kept to what would be unsafe. All lines are synthetic; no real patient data.
final class QuickAddReview4Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))! }

    private func read(_ s: String, _ tab: QuickAddTab = .preop) -> QuickAddReading {
        QuickAdd.read(s, record: PatientRecord(), tab: tab, now: now)
    }
    private func change(_ q: QuickAddReading, _ id: String) -> PatientNoteChange? { q.findings.first { $0.id == id }?.change }
    private func applied(_ fs: [PatientNoteFinding]) -> PatientRecord {
        var r = PatientRecord()
        PatientNote.apply(fs.map(\.change), to: &r)
        return r
    }
    private func note(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func change(_ n: PatientNoteReading, _ id: String) -> PatientNoteChange? { n.findings.first { $0.id == id }?.change }

    /// Not yet given, in words outside the cue list: not filed as given (asked, or left out).
    func testNotYetGivenVariants() {
        for line in ["2 PRBC to be given", "2 PRBC to be transfused", "4 FFP thawing", "4 PRBC typed and crossed", "2 FFP returned"] {
            let r = applied(read(line, .intraop).findings)
            XCTAssertTrue(r.fluids.isEmpty, line + " → \(r.fluids)")
        }
    }

    /// "PRBC 3/4": unit 3 of 4, not three more.
    func testSlashedUnitOfTotalIsNotACount() {
        XCTAssertNotEqual(applied(read("PRBC 3/4 hanging", .intraop).findings).fluids["prbc"], 3)
    }

    /// An earlier value marked after it in parentheses or as "admit" is not the current one.
    func testEarlierMarkVariants() {
        XCTAssertNotEqual(change(read("Cr 1.1 (baseline), now 1.6"), "lab:cr"), .lab("cr", 1.1))
        XCTAssertNotEqual(change(note("Cr 1.1 (baseline), now 1.6"), "lab:cr"), .lab("cr", 1.1), "full-note path")
        XCTAssertNotEqual(change(read("K 3.1 on admit, now 4.2"), "lab:k"), .lab("k", 3.1))
    }

    /// "easy mask gr 3 DL": an easy mask, and grade 3 on direct laryngoscopy; not a mask grade of 3.
    func testGradeBeforeALaryngoscopeIsTheView() {
        let r = applied(read("easy mask gr 3 DL, bougie, 7.5 ETT", .intraop).findings)
        XCTAssertNotEqual(r.maskGrade, 3, "the view grade filed as the mask grade")
    }

    /// A header written with a dash: the name is masked and not filed into Other conditions.
    func testFullNoteHeaderWithADash() {
        let n = note("Patient - Jane Doe\n68F for lap chole, HTN")
        XCTAssertTrue(!n.identifiers.isEmpty || !(n.other.contains("Jane") || n.other.contains("Doe")), "filed into Other conditions: " + n.other)
    }
}
