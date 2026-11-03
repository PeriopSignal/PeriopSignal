import XCTest
@testable import PeriopSignal

/// Reading speed with the procedure list (1.8.3 about doubled it): the procedure field's type-ahead, a typed note, and
/// the quick-add bar. The class name starts with Z so it runs last and its timings land in the tail of the CI test
/// summary; each prints one "PROCEDURE SPEED TEST" line. The budgets are loose (a Debug build in a CI simulator).
final class ZProcedureSpeedTests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))! }

    private func seconds(_ body: () -> Void) -> Double {
        let t = CFAbsoluteTimeGetCurrent()
        body()
        return CFAbsoluteTimeGetCurrent() - t
    }

    private func ms(_ s: Double) -> String { String(format: "%.3f", s * 1000) }

    /// What a user types into the procedure field, one keystroke at a time.
    private let typed = ["lap chole", "CABG x3 + AVR", "open AAA repair", "left TKA", "VATS lobectomy", "carotid endarterectomy",
                         "fem pop bypass", "TAVR", "open left iliac aneurysm repair", "Bentall", "ex lap", "TURBT", "hip fracture",
                         "craniotomy for tumor", "whipple", "lung transplant", "esophagectomy", "EVAR", "ACDF C5-6", "cesarean"]

    func testTypeaheadStaysFast() {
        _ = ProcedureCatalog.search("warm up")
        var calls = 0
        let t = seconds {
            for _ in 0..<5 {
                for q in typed {
                    var s = ""
                    for ch in q {
                        s.append(ch)
                        guard s.count >= 2 else { continue }
                        _ = ProcedureCatalog.search(s, limit: 6)
                        _ = ProcedureCatalog.parse(s)
                        calls += 1
                    }
                }
            }
        }
        print("PROCEDURE SPEED TEST type-ahead: \(calls) keystrokes (search + parse) in \(ms(t)) ms, \(ms(t / Double(calls))) ms each, \(ProcedureCatalog.all.count) procedures")
        XCTAssertLessThan(t / Double(calls), 0.02, "a keystroke in the procedure field")
    }

    private let note = """
        72 yo M scheduled for open left iliac aneurysm repair (infrarenal clamp) tomorrow under GA with epidural.
        PMH: HTN, HLD, CAD s/p CABG 2015, COPD, CKD 3a, AF on apixaban, s/p left TKA 2019.
        Meds: metoprolol 25 mg BID, atorvastatin 40 mg, apixaban 5 mg BID (held 3 days).
        Vitals: BP 148/86 HR 72 SpO2 95% RA RR 16.
        Labs: Hgb 12.1, Cr 1.4, K 4.2, plt 210.
        TTE: EF 55%, mild MR, no AS.
        Airway: MP 2, TMD > 3 FB, full dentition, prior easy DL.
        """

    func testTypedNoteStaysFast() {
        _ = PatientNote.read(note, now: now)
        let n = 10
        let t = seconds { for _ in 0..<n { _ = PatientNote.read(note, now: now) } }
        print("PROCEDURE SPEED TEST typed note: \(n) reads in \(ms(t)) ms, \(ms(t / Double(n))) ms each")
        XCTAssertLessThan(t / Double(n), 2, "reading a typed note")
    }

    private let lines = ["for lap chole HTN DM2", "planned L TKA", "CABG x3 + AVR", "74M for EVAR, HTN, CKD", "148/86 72 95% RA 16",
                         "for open left iliac aneurysm repair", "planned VATS RUL lobectomy", "for TCAR, CAD, DM", "Plan: R BKA",
                         "for redo sternotomy MVR TV repair", "LVAD implant", "for fem pop bypass"]

    func testQuickAddStaysFast() {
        _ = QuickAdd.read(lines[0], record: PatientRecord(), tab: .preop, now: now)
        let n = 5
        let t = seconds {
            for _ in 0..<n { for l in lines { _ = QuickAdd.read(l, record: PatientRecord(), tab: .preop, now: now) } }
        }
        let count = n * lines.count
        print("PROCEDURE SPEED TEST quick-add bar: \(count) lines in \(ms(t)) ms, \(ms(t / Double(count))) ms each")
        XCTAssertLessThan(t / Double(count), 1, "a line in the quick-add bar")
    }
}
