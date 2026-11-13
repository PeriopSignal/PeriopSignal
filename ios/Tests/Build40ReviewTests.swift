import XCTest
@testable import PeriopSignal

/// Build 40's last read-through before release (Nov 12): what a second reader found where the Nov 12 pieces meet, each fixed
/// and held here.
final class Build40ReviewTests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 8))! }
    private func at(_ hour: Int, _ minute: Int, day: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    private func read(_ s: String, _ tab: QuickAddTab = .preop, record: PatientRecord = PatientRecord(), handoff: Bool = false) -> QuickAddReading {
        QuickAdd.read(s, record: record, tab: tab, now: now, handoff: handoff)
    }
    private func procedure(_ q: QuickAddReading) -> PatientNoteChange? { q.findings.first { $0.id == "procedure" }?.change }

    // MARK: "for" in the middle of a line

    /// The Summary & Handoff bar tells the end of the case: "back to OR for ..." there is not the planned procedure, and must
    /// not offer to replace it. The Preoperative bar still reads a mid-line "for".
    func testAMidLineForIsNotReadOnTheSummaryAndHandoffBar() {
        var r = PatientRecord()
        PatientNote.apply([.procedure("CABG")], to: &r)
        for line in ["chest left open, back to OR for mediastinal exploration", "HTN, DM2, for TAVR", "73M with HF for ECMO cannulation"] {
            XCTAssertNil(procedure(read(line, record: r, handoff: true)), line)
        }
        XCTAssertNotNil(procedure(read("HTN, DM2, for TAVR")), "the Preoperative bar")
        XCTAssertNotNil(procedure(read("73M with HF for ECMO cannulation")), "the Preoperative bar")
    }

    /// "3D" and "2D" name a study; "3 days" and "8 h" say how long.
    func testThreeDIsNotThreeDays() {
        XCTAssertNotNil(procedure(read("68M for 3D TEE")), "3D TEE")
        XCTAssertNotNil(procedure(read("scheduled for 3D TEE")))
        XCTAssertNil(procedure(read("68M for 3 days")))
        XCTAssertNil(procedure(read("68M for 8 h")))
        XCTAssertNil(procedure(read("68M for 8h")))
        XCTAssertNil(procedure(read("HTN, on heparin for 3 d, DM2")))
    }

    /// Words that begin several listed procedures are not turned into one of them.
    func testWordsThatBeginSeveralListedProceduresStayAsTyped() {
        func text(_ line: String) -> String? {
            if case .procedure(let t)? = procedure(read(line)) { return t.lowercased() }
            return nil
        }
        XCTAssertEqual(text("68M for mitral valve"), "mitral valve")
        XCTAssertEqual(text("68M for aortic valve"), "aortic valve")
        // One listed procedure begins with the words: it is the one meant.
        XCTAssertEqual(text("for axillary imp"), "axillary impella insertion")
    }

    // MARK: Angiograms

    /// An angiogram of a vascular bed the list does not know stays one procedure as typed: not the bed as one procedure and a
    /// diagnostic angiogram (MAC) as another.
    func testAnUnlistedBedStaysWithItsAngiogram() {
        for q in ["carotid angiogram", "renal angiography", "hepatic arteriogram", "renal angiogram with possible intervention"] {
            let items = PlannedProcedure.parse(q)
            XCTAssertEqual(items.count, 1, q)
            XCTAssertNil(items.first?.catalogID, q)
            XCTAssertEqual(items.first?.name, q, q)
        }
        XCTAssertEqual(PlannedProcedure.parse("cerebral angiography").map(\.catalogID), ["neuro-endovascular"])
        XCTAssertEqual(PlannedProcedure.parse("SMA angiography").map(\.catalogID), ["mesenteric-angiogram"])
        // An angiogram that names no bed is the list's, also after another procedure or a word that is not a bed.
        XCTAssertEqual(PlannedProcedure.parse("angiogram").map(\.catalogID), ["angiogram-diagnostic"])
        XCTAssertEqual(PlannedProcedure.parse("diagnostic angiogram").map(\.catalogID), ["angiogram-diagnostic"])
        XCTAssertEqual(PlannedProcedure.parse("possible angiogram").last?.catalogID, "angiogram-diagnostic")
        XCTAssertEqual(PlannedProcedure.parse("angiogram with possible intervention").map(\.catalogID), ["angiogram-intervention"])
        XCTAssertEqual(PlannedProcedure.parse("CABG, angiogram").map(\.catalogID), ["cabg", "angiogram-diagnostic"])
    }

    // MARK: Heparin & ACT

    /// A log begun by recording a dose ("+ Heparin", a typed dose) has no purpose chosen: choosing one keeps the log, so a
    /// cardiac case gets its ACT goal and protamine range without the recorded dose being cleared.
    func testALogBegunByRecordingADoseCanStillBeGivenItsPurpose() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        let d = try XCTUnwrap(ReferenceLoader.decode(try Data(contentsOf: url)).caseTimers)
        var r = PatientRecord()
        var h = IntraopHeparin.course(r)
        XCTAssertEqual(h.purpose, IntraopHeparin.purposeNotChosen)
        XCTAssertTrue(h.purposeOpen, "nothing logged")
        h.logDose(units: 30000, at: at(8, 10), now: at(8, 10))
        XCTAssertTrue(h.purposeOpen, "recorded, purpose not chosen")
        XCTAssertFalse(h.actRunning)
        let bypass = try XCTUnwrap(d.purpose("bypass"))
        let chosen = h.choosing(bypass)
        XCTAssertEqual(chosen.purpose, "bypass")
        XCTAssertEqual(chosen.goal, bypass.goal)
        XCTAssertEqual(chosen.doses, h.doses, "the recorded dose is kept")
        XCTAssertFalse(chosen.actRunning, "choosing the purpose does not turn the reminder on")
        XCTAssertFalse(chosen.purposeOpen, "a chosen purpose with a dose in the log is fixed, as before")
        r.timers.heparin = chosen
        XCTAssertEqual(r.timers.heparin?.initialUnits, 30000)
        // A goal the user set, and a running reminder's interval, are kept.
        var own = h
        own.goal = 300; own.userGoal = true
        own.setReminder(true, now: at(8, 20))
        own.actEvery = 20
        let kept = own.choosing(bypass)
        XCTAssertEqual(kept.goal, 300); XCTAssertEqual(kept.actEvery, 20); XCTAssertTrue(kept.actRunning)
        // Any other purpose is fixed once something is logged.
        var fixed = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
        XCTAssertTrue(fixed.purposeOpen)
        fixed.logACT(seconds: 130, at: at(8, 0), kind: .baseline)
        XCTAssertFalse(fixed.purposeOpen)
    }

    // MARK: A typed dose time across midnight

    func testADoseTypedForJustAfterMidnightIsNotYesterdayMorning() {
        XCTAssertEqual(IntraopAntibiotic.moment(hour: 0, minute: 0, now: at(23, 58)), at(0, 0, day: 13), "two minutes from now")
        XCTAssertEqual(IntraopAntibiotic.moment(hour: 0, minute: 1, now: at(23, 58)), at(0, 1, day: 13))
        // Outside the five minutes it is as before: earlier today.
        XCTAssertEqual(IntraopAntibiotic.moment(hour: 0, minute: 5, now: at(23, 57)), at(0, 5))
        XCTAssertEqual(IntraopAntibiotic.moment(hour: 8, minute: 10, now: at(23, 57)), at(8, 10))
        XCTAssertEqual(IntraopAntibiotic.moment(hour: 9, minute: 5, now: at(9, 0)), at(9, 5))
        XCTAssertNil(IntraopAntibiotic.moment(hour: 9, minute: 30, now: at(9, 0)))
        XCTAssertEqual(IntraopAntibiotic.moment(hour: 23, minute: 30, now: at(1, 0)), at(23, 30, day: 11))
    }
}
