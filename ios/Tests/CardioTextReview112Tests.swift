import XCTest
@testable import PeriopSignal

/// Cardiopulmonary findings typed into the text bars, after the independent review of how a reading is written to the record: an
/// effusion that replaces another never keeps the old one's size or side, "aorta intact" replaces an aorta described in words,
/// findings already in the chest X-ray's line are not added twice, and a ratio typed the other way (0.55 for 55) is the same value.
/// The reading rules themselves are in T112Tests, generated from the tables.
final class CardioTextReview112Tests: XCTestCase {

    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 8))! }

    private func status(_ line: String, _ id: String, _ r: PatientRecord) -> PatientNoteStatus? {
        let q = QuickAdd.read(line, record: r, tab: .preop, now: now)
        return q.findings.first { $0.id == id }.map { PatientNote.status($0, in: r) }
    }

    private func applied(_ line: String, to record: PatientRecord) -> PatientRecord {
        var r = record
        let reading = CardioText.read(line, page: nil, now: now)
        PatientNote.apply(reading.findings.map(\.change), to: &r)
        return r
    }

    // MARK: The chest X-ray's effusion

    func testAnEffusionThatReplacesAnotherKeepsNothingOfTheOldOne() {
        var r = PatientRecord()
        r.chestXray.choose(.effusion)
        r.chestXray.side = .left
        r.chestXray.size = .moderate
        // Another side, no size typed: the moderate size was the left effusion's and does not move to the right.
        XCTAssertEqual(status("CXR: R effusion", "cardio:cxr:effusion", r), .replaces("moderate left effusion"))
        let right = applied("CXR: R effusion", to: r)
        XCTAssertEqual(right.chestXray.result, .effusion)
        XCTAssertEqual(right.chestXray.side, .right)
        XCTAssertNil(right.chestXray.size)
        // Another size, no side typed: the side is not kept either.
        let large = applied("CXR: large effusion", to: r)
        XCTAssertEqual(large.chestXray.size, .large)
        XCTAssertNil(large.chestXray.side)
        // Both typed: exactly what was typed.
        let both = applied("CXR: small R effusion", to: r)
        XCTAssertEqual(both.chestXray.side, .right)
        XCTAssertEqual(both.chestXray.size, .small)
    }

    func testTheSameEffusionToldWithMoreDetailOnlyAddsTheDetail() {
        var r = PatientRecord()
        r.chestXray.choose(.effusion)
        r.chestXray.side = .left
        // The size is new; the side stays.
        XCTAssertEqual(status("CXR: small effusion", "cardio:cxr:effusion", r), .new)
        let sized = applied("CXR: small effusion", to: r)
        XCTAssertEqual(sized.chestXray.side, .left)
        XCTAssertEqual(sized.chestXray.size, .small)
        // The same side again changes nothing.
        XCTAssertEqual(status("CXR: L effusion", "cardio:cxr:effusion", r), .recorded)
        XCTAssertEqual(applied("CXR: L effusion", to: r).chestXray, r.chestXray)
    }

    func testAnEffusionOverANormalFilmIsWrittenAsTyped() {
        var r = PatientRecord()
        r.chestXray.choose(.normal)
        let eff = applied("CXR: small L effusion", to: r)
        XCTAssertEqual(eff.chestXray.result, .effusion)
        XCTAssertEqual(eff.chestXray.side, .left)
        XCTAssertEqual(eff.chestXray.size, .small)
    }

    // MARK: The chest X-ray's findings line

    func testFindingsAlreadyInTheLineAreNotAddedTwice() {
        var r = PatientRecord()
        r.chestXray.findings = "cardiomegaly"
        // Two findings in one run arrive joined: only the one the line lacks is added.
        XCTAssertEqual(status("CXR: RLL infiltrate, cardiomegaly", "cardio:cxr:findings", r), .new)
        XCTAssertEqual(applied("CXR: RLL infiltrate, cardiomegaly", to: r).chestXray.findings, "cardiomegaly; RLL infiltrate")
        // Both already there: recorded, and the line is left exactly as it was.
        r.chestXray.findings = "cardiomegaly; RLL infiltrate"
        XCTAssertEqual(status("CXR: RLL infiltrate, cardiomegaly", "cardio:cxr:findings", r), .recorded)
        XCTAssertEqual(applied("CXR: RLL infiltrate, cardiomegaly", to: r).chestXray.findings, "cardiomegaly; RLL infiltrate")
        // An empty line takes them in the order typed.
        XCTAssertEqual(applied("CXR: RLL infiltrate, cardiomegaly", to: PatientRecord()).chestXray.findings, "RLL infiltrate; cardiomegaly")
    }

    // MARK: The echo's aorta

    func testAortaIntactReplacesAnAortaDescribedInWords() {
        var r = PatientRecord()
        r.echoFindings.aorta = "ascending 4.6 cm"
        XCTAssertEqual(status("TTE EF 55%, aorta nl", "cardio:echo:aorta", r), .replaces("ascending 4.6 cm"))
        let a = applied("TTE EF 55%, aorta nl", to: r)
        XCTAssertEqual(a.echoFindings.aortaIntact, true)
        XCTAssertEqual(a.echoFindings.aorta, "", "the two never stand side by side")
        // Marked abnormal with no words: as before.
        var marked = PatientRecord()
        marked.echoFindings.aortaIntact = false
        XCTAssertEqual(status("TTE EF 55%, aorta nl", "cardio:echo:aorta", marked), .replaces("aorta abnormal"))
        // Already intact: recorded. Nothing recorded: new.
        var intact = PatientRecord()
        intact.echoFindings.aortaIntact = true
        XCTAssertEqual(status("TTE EF 55%, aorta nl", "cardio:echo:aorta", intact), .recorded)
        XCTAssertEqual(status("TTE EF 55%, aorta nl", "cardio:echo:aorta", PatientRecord()), .new)
    }

    // MARK: The PFT ratio

    func testARatioTypedTheOtherWayIsTheSameValue() {
        var r = PatientRecord()
        r.pft.ratioTyped = 55
        XCTAssertEqual(status("PFT FEV1/FVC 0.55", "cardio:pft:ratio", r), .recorded)
        XCTAssertEqual(status("PFT FEV1/FVC 55%", "cardio:pft:ratio", r), .recorded)
        XCTAssertEqual(status("PFT FEV1/FVC 0.62", "cardio:pft:ratio", r), .replaces("55"))
        r.pft.ratioTyped = 0.55
        XCTAssertEqual(status("PFT FEV1/FVC 55%", "cardio:pft:ratio", r), .recorded)
        XCTAssertEqual(status("PFT FEV1/FVC 0.55", "cardio:pft:ratio", PatientRecord()), .new)
    }
}
