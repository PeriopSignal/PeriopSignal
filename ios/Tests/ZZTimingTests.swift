import XCTest
@testable import PeriopSignal

final class ZZTimingTests: XCTestCase {
    func testTiming() {
        let note = "PSH: Ascending aorta replacement + LM and RCA endarterectomy + AV repair 06/2025"
        var log: [String] = []
        func t(_ name: String, _ f: () -> Void) {
            let s = CFAbsoluteTimeGetCurrent(); f(); log.append(name + "=" + String(format: "%.2f", CFAbsoluteTimeGetCurrent() - s))
        }
        t("planned.parse") { _ = PlannedProcedure.parse("Ascending aorta replacement") }
        t("planned.parse2") { _ = PlannedProcedure.parse("LM and RCA endarterectomy") }
        t("planned.parse3") { _ = PlannedProcedure.parse("AV repair") }
        t("surgery") { _ = PastSurgeryNote.surgery("Ascending aorta replacement + LM and RCA endarterectomy + AV repair", PatientMonthYear(month: 6, year: 2025)) }
        var st = PastSurgeryNote.State()
        t("psh.read") { _ = PastSurgeryNote.read(note, state: &st) }
        t("note.read") { _ = PatientNote.read(note) }
        t("note.read.noPSH") { _ = PatientNote.read("Ascending aorta replacement + LM and RCA endarterectomy + AV repair 06/2025") }
        t("note.read.short") { _ = PatientNote.read("PSH: AV repair 06/2025") }
        t("abbr") { _ = MedAbbreviations.scan(note, user: [:], choices: [:]) }
        t("identifiers") { _ = PatientNote.identifiers(note) }
        XCTFail("timings: " + log.joined(separator: ", "))
    }
}
