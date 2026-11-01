import XCTest
@testable import PeriopSignal

/// The third, verification-only clinical review of the quick-add bar and the full note (1.8): close variants of the
/// second review's fixed lines, kept to what would be unsafe (a plausible wrong value, a not-given item filed as given,
/// an identifier filed, the wrong field). All lines are synthetic; no real patient data.
final class QuickAddReview3Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))! }

    private func read(_ s: String, _ tab: QuickAddTab = .preop, record: PatientRecord = PatientRecord()) -> QuickAddReading {
        QuickAdd.read(s, record: record, tab: tab, now: now)
    }
    private func change(_ q: QuickAddReading, _ id: String) -> PatientNoteChange? { q.findings.first { $0.id == id }?.change }
    private func applied(_ fs: [PatientNoteFinding]) -> PatientRecord {
        var r = PatientRecord()
        PatientNote.apply(fs.map(\.change), to: &r)
        return r
    }
    private func note(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func change(_ n: PatientNoteReading, _ id: String) -> PatientNoteChange? { n.findings.first { $0.id == id }?.change }
    private func plannedLines(_ fs: [PatientNoteFinding]) -> [String] {
        fs.compactMap { f -> String? in
            guard case .devices(let ds) = f.change, ds.contains(where: { $0.kind == .arterial || $0.kind == .pac }) else { return nil }
            return f.label
        }
    }

    // MARK: Airway

    /// "Easy mask. Grade 3 view": the mask phrase ends at the full stop; grade 3 is the view, not the mask grade.
    func testMaskPhraseEndsAtTheSentence() {
        for line in ["Easy mask. Grade 3 view, bougie, 7.5 ETT", "easy BMV/grade 3 view, 7.0 ETT"] {
            let r = applied(read(line, .intraop).findings)
            XCTAssertNotEqual(r.maskGrade, 3, line + ": the view grade filed as the mask grade")
        }
    }

    // MARK: Labs: trends and earlier values in other words

    /// A trend written with "to", or with a word after the next number, ends on the current value or is left unread.
    func testTrendVariants() {
        XCTAssertNotEqual(change(read("Cr 0.9 to 1.6"), "lab:cr"), .lab("cr", 0.9), "the baseline filed as the current creatinine")
        XCTAssertNotEqual(change(note("Cr 0.9 to 1.6"), "lab:cr"), .lab("cr", 0.9), "full-note path")
        XCTAssertNotEqual(change(read("K 3.1 then 4 runs KCl"), "lab:k"), .lab("k", 4), "the number of runs filed as a normal potassium")
    }

    /// An earlier value marked after it ("at baseline", "on admission") is not the current one.
    func testEarlierMarkedAfterTheValue() {
        XCTAssertNotEqual(change(read("Cr 1.1 at baseline, now 1.6"), "lab:cr"), .lab("cr", 1.1))
        XCTAssertNotEqual(change(read("K 3.1 on admission, now 4.2"), "lab:k"), .lab("k", 3.1))
        XCTAssertNotEqual(change(note("Cr 1.1 at baseline, now 1.6"), "lab:cr"), .lab("cr", 1.1), "full-note path")
    }

    // MARK: Blood

    /// Ordered, available, planned, conditional or sent back, with a few words between: not given.
    func testNotGivenWithWordsBetween() {
        for line in ["plan for 2 PRBC", "4 PRBC are in the room", "type and cross for 4 PRBC", "if Hb < 7 give 2 PRBC",
                     "2 FFP returned to BB", "2 FFP sent back to blood bank"] {
            let r = applied(read(line, .intraop).findings)
            XCTAssertTrue(r.fluids.isEmpty, line + " → \(r.fluids)")
        }
    }

    /// "PRBC 3 of 4" is the third unit of four, not three more.
    func testUnitOfAPlannedNumberIsNotACount() {
        XCTAssertNotEqual(applied(read("PRBC 3 of 4 hanging", .intraop).findings).fluids["prbc"], 3)
    }

    // MARK: The venous gas, slashed

    /// "venous 7.28/55/40": a venous gas; its PO₂ is not a PaO₂.
    func testVenousSlashedGas() {
        for line in ["venous 7.28/55/40", "central venous 7.30/50/38"] {
            let v = applied(read(line, .intraop).findings).intraopLabs.first?.values ?? [:]
            XCTAssertNil(v["pao2"], line + " → \(v)")
        }
    }

    // MARK: Planned lines

    /// "A-line, PAC post-induction": both still to come.
    func testPlannedListEndingWithInductionTiming() {
        let line = "A-line, PAC post-induction"
        XCTAssertTrue(plannedLines(read(line).findings).isEmpty, "\(plannedLines(read(line).findings))")
        XCTAssertTrue(plannedLines(note(line).findings).isEmpty, "full-note path: \(plannedLines(note(line).findings))")
    }

    // MARK: The full note on the Intraoperative tab

    /// An OR note pasted on the Intraoperative tab: the preoperative hemoglobin is not the intraoperative one.
    func testFullNoteOnTheIntraopTabKeepsAPreopValueOut() {
        let routed = QuickAdd.forTab(note("Preop Hb 12.1. Now Hb 8.2 after EBL 1500."), tab: .intraop, record: PatientRecord(), now: now)
        let v = applied(routed.findings).intraopLabs.first?.values ?? [:]
        XCTAssertNotEqual(v["hb"], 12.1, "the preop value filed in a set stamped now: \(v)")
    }

    // MARK: Identifiers on the full-note path

    /// The full-note sheet adds Other conditions by default when no identifier is flagged: these would be filed there.
    func testFullNoteIdentifierVariants() {
        let cases: [(String, [String])] = [("Patient: Doe, Jane\n68F for lap chole, HTN", ["Doe", "Jane"]),
                                           ("Patient: jane doe\n68F for lap chole, HTN", ["jane", "doe"]),
                                           ("born 04-Mar-1950, 72M HTN", ["1950", "Mar"])]
        for (text, words) in cases {
            let n = note(text)
            XCTAssertTrue(!n.identifiers.isEmpty || !words.contains { n.other.contains($0) }, "filed into Other conditions by default: " + n.other)
        }
    }
}
