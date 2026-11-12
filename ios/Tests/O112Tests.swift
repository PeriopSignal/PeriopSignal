import XCTest
@testable import PeriopSignal

/// 1.12 follow-up, helper O (Ben, Nov 12): "Heparin timer needs to be reworked to accommodate baseline ACT times, initial heparin
/// dose, multiple subsequent ACT samples (on and off timer alarms) and repeated heparin doses." Heparin & ACT is one editable
/// timeline (a row per baseline ACT, heparin dose, ACT and protamine dose, each with a time the user sets), and the ACT
/// reminder is one switch whose countdown runs from the last ACT sample (answers 1 to 4). Times are fixed; every test that
/// depends on the clock passes its own `now`.
final class O112Tests: XCTestCase {

    private func at(_ hour: Int, _ minute: Int, day: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func data() throws -> CaseTimerData {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        return try XCTUnwrap(ReferenceLoader.decode(try Data(contentsOf: url)).caseTimers, "caseTimers decodes")
    }

    private func adult(_ kg: Double = 82) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = kg
        return r
    }

    private func course(_ purpose: String = "bypass", goal: Double? = 480, every: Double = 30) -> HeparinCourse {
        HeparinCourse(purpose: purpose, goal: goal, actEvery: every)
    }

    /// The log of the spec's example: baseline, dose, ACT at goal, ACT below goal, second dose, ACT at goal, protamine.
    private func fullLog() -> HeparinCourse {
        var h = course()
        h.logACT(seconds: 128, at: at(8, 0), kind: .act)
        h.logDose(units: 26000, at: at(8, 10), now: at(8, 10))
        h.logACT(seconds: 512, at: at(8, 20), kind: .act)
        h.logACT(seconds: 468, at: at(8, 50), kind: .act)
        h.logDose(units: 5000, at: at(8, 52), now: at(8, 52))
        h.logACT(seconds: 545, at: at(9, 15), kind: .act)
        h.logProtamine(mg: 150, at: at(9, 40))
        return h
    }

    private func rows(_ h: HeparinCourse, now: Date) -> [String] {
        h.timeline.map { HeparinTimeline.rowText($0, now: now) }
    }

    private func due(_ h: HeparinCourse) -> Date? { CaseTimerEngine.actDue(h) }

    private func reminders(_ h: HeparinCourse, snoozes: [String: ReminderSnooze] = [:]) throws -> [CaseReminder] {
        var t = CaseTimers()
        t.heparin = h
        t.snoozes = snoozes
        return CaseTimerEngine.reminders(t, record: adult(), data: try data())
    }

    // MARK: The timeline: rows and order

    func testTheTimelineListsEveryEventInTimeOrderWithTheGoalLabels() {
        XCTAssertEqual(rows(fullLog(), now: at(10, 0)), [
            "08:00 Baseline ACT 128 s",
            "08:10 Heparin 26,000 U",
            "08:20 ACT 512 s at goal",
            "08:50 ACT 468 s below goal",
            "08:52 Heparin 5,000 U",
            "09:15 ACT 545 s at goal",
            "09:40 Protamine 150 mg",
        ])
    }

    func testABackTimedEntryTakesItsPlaceByItsTime() {
        var h = fullLog()
        // Logged last, drawn at 08:35: between the two ACTs that surround it.
        h.logACT(seconds: 505, at: at(8, 35), kind: .act)
        // A dose back-timed to before the baseline.
        h.logDose(units: 1000, at: at(7, 55), now: at(9, 50))
        let r = rows(h, now: at(10, 0))
        XCTAssertEqual(r.first, "07:55 Heparin 1,000 U")
        XCTAssertEqual(r[3], "08:20 ACT 512 s at goal")
        XCTAssertEqual(r[4], "08:35 ACT 505 s at goal")
        XCTAssertEqual(r[5], "08:50 ACT 468 s below goal")
        XCTAssertEqual(r.count, 9)
    }

    func testEntriesAcrossMidnightSortByTheirDayAndShowTheDateWhenNotToday() {
        var h = course()
        let now = at(0, 20, day: 13)
        h.logACT(seconds: 130, at: at(23, 40, day: 12), kind: .baseline)
        h.logDose(units: 26000, at: at(23, 50, day: 12), now: at(23, 50, day: 12))
        h.logACT(seconds: 520, at: at(0, 10, day: 13), kind: .act)
        XCTAssertEqual(rows(h, now: now), [
            "11/12/26 23:40 Baseline ACT 130 s",
            "11/12/26 23:50 Heparin 26,000 U",
            "00:10 ACT 520 s at goal",
        ])
        // Entered out of order across the day change, the order is still the clock's.
        var g = course()
        g.logDose(units: 5000, at: at(0, 10, day: 13), now: at(0, 12, day: 13))
        g.logDose(units: 26000, at: at(23, 50, day: 12), now: at(0, 12, day: 13))
        XCTAssertEqual(g.timeline.map(\.value), [26000, 5000])
        XCTAssertEqual(HeparinTimeline.timeText(at(23, 50, day: 12), now: now), "11/12/26 23:50")
        XCTAssertEqual(HeparinTimeline.timeText(at(0, 10, day: 13), now: now), "00:10", "today: the clock alone, 24-hour")
    }

    func testEventsInTheSameMinuteReadBaselineDoseACTProtamine() {
        var h = course()
        h.logDose(units: 5000, at: at(9, 0), now: at(9, 0))
        h.logProtamine(mg: 100, at: at(9, 0))
        h.logACT(seconds: 500, at: at(9, 0), kind: .act)
        h.logACT(seconds: 120, at: at(9, 0), kind: .baseline)
        XCTAssertEqual(h.timeline.map(\.kind), [.baseline, .heparin, .act, .protamine])
    }

    func testTheValuesAreWrittenAsTheAppWritesThem() {
        let h = fullLog()
        XCTAssertEqual(h.timeline.map { HeparinTimeline.valueText($0) }, ["128 s", "26,000 U", "512 s", "468 s", "5,000 U", "545 s", "150 mg"])
        XCTAssertEqual(HeparinTimeline.label(.baseline), "Baseline ACT")
        XCTAssertEqual(HeparinTimeline.goalText(true), "at goal")
        XCTAssertEqual(HeparinTimeline.goalText(false), "below goal")
        XCTAssertNil(HeparinTimeline.goalText(nil))
    }

    // MARK: Goal labels

    func testGoalLabelsAtBelowNoneWithoutAGoalAndNoneForABaseline() {
        let h = fullLog()
        let byKind = h.timeline.filter { $0.kind == .act }.map(\.goalMet)
        XCTAssertEqual(byKind, [true, false, true])
        XCTAssertNil(h.timeline.first { $0.kind == .baseline }?.goalMet, "a baseline never gets a label")
        XCTAssertNil(h.timeline.first { $0.kind == .heparin }?.goalMet)
        // At the goal itself is at goal ("≥ 480").
        var edge = course(); edge.logDose(units: 26000, at: at(8, 0), now: at(8, 0)); edge.logACT(seconds: 480, at: at(8, 20), kind: .act)
        XCTAssertEqual(edge.timeline.last?.goalMet, true)
        // No goal set (vascular has none preset): no label on any row.
        var none = course("vascular", goal: nil)
        none.logDose(units: 5000, at: at(8, 0), now: at(8, 0))
        none.logACT(seconds: 210, at: at(8, 20), kind: .act)
        XCTAssertNil(none.timeline.last?.goalMet)
        XCTAssertEqual(rows(none, now: at(9, 0)).last, "08:20 ACT 210 s")
        // The goal in force decides: the same log against a user's goal of 500 reads differently.
        var g = fullLog(); g.goal = 500
        XCTAssertEqual(g.timeline.filter { $0.kind == .act }.map(\.goalMet), [true, false, true])
        g.goal = 520
        XCTAssertEqual(g.timeline.filter { $0.kind == .act }.map(\.goalMet), [false, false, true])
    }

    func testAnACTDrawnBeforeAnyHeparinSaysNothingAboutTheGoal() {
        var h = course()
        h.logDose(units: 26000, at: at(8, 10), now: at(8, 10))
        // "+ ACT" with a dose in the log is not a baseline, but this one is back-timed to before the dose.
        h.logACT(seconds: 300, at: at(7, 50), kind: .act)
        XCTAssertNotEqual(h.acts.last?.baseline, true)
        XCTAssertNil(h.timeline.first { $0.kind == .act }?.goalMet)
    }

    func testTheRowLabelIsTheOneLastACTLineUses() {
        // "Last ACT 545 s at … · at goal" is CaseTimerEngine.status; the last row says the same thing.
        let h = fullLog()
        let s = CaseTimerEngine.status(h, record: adult())
        XCTAssertEqual(s.goalMet, true)
        XCTAssertEqual(h.timeline.last { $0.kind == .act }?.goalMet, s.goalMet)
        XCTAssertTrue(CaseTimerEngine.atGoal(480, goal: 480))
        XCTAssertFalse(CaseTimerEngine.atGoal(479, goal: 480))
        // A below-goal last ACT after the last dose: below in both.
        var b = course(); b.logDose(units: 26000, at: at(8, 0), now: at(8, 0)); b.logACT(seconds: 400, at: at(8, 20), kind: .act)
        XCTAssertEqual(CaseTimerEngine.status(b, record: adult()).goalMet, false)
        XCTAssertEqual(b.timeline.last?.goalMet, false)
    }

    // MARK: Baselines and "+ ACT"

    func testPlusACTBeforeAnyDoseIsABaselineAsToday() {
        var h = course()
        XCTAssertTrue(h.offersBaseline)
        h.logACT(seconds: 128, at: at(8, 0), kind: .act)
        XCTAssertEqual(h.acts.last?.baseline, true, "today's rule: no dose in the log, so the ACT is the baseline")
        XCTAssertEqual(h.timeline.last?.kind, .baseline)
        h.logDose(units: 26000, at: at(8, 10), now: at(8, 10))
        XCTAssertFalse(h.offersBaseline)
        h.logACT(seconds: 500, at: at(8, 20), kind: .act)
        XCTAssertNotEqual(h.acts.last?.baseline, true)
    }

    func testSeveralBaselinesAreAllowedAndNoneIsLabelled() {
        var h = course()
        h.logACT(seconds: 130, at: at(7, 40), kind: .baseline)
        h.logACT(seconds: 126, at: at(7, 55), kind: .baseline)
        h.logDose(units: 26000, at: at(8, 10), now: at(8, 10))
        // "+ Baseline ACT" marks a baseline even with a dose in the log.
        h.logACT(seconds: 125, at: at(8, 5), kind: .baseline)
        XCTAssertEqual(h.timeline.filter { $0.kind == .baseline }.count, 3)
        XCTAssertTrue(h.timeline.filter { $0.kind == .baseline }.allSatisfy { $0.goalMet == nil })
        XCTAssertEqual(h.baselineACT?.value, 125, "the latest baseline is the one the protamine line compares with")
        XCTAssertEqual(rows(h, now: at(9, 0)), ["07:40 Baseline ACT 130 s", "07:55 Baseline ACT 126 s", "08:05 Baseline ACT 125 s", "08:10 Heparin 26,000 U"])
    }

    // MARK: Edit, delete and Undo

    func testEditingATimeReSortsAndEditingAValueChangesTheLabel() throws {
        var h = fullLog()
        let last = try XCTUnwrap(h.timeline.first { $0.kind == .act && $0.value == 545 })
        // Value: 545 → 470 is below goal now.
        XCTAssertTrue(h.updateEntry(last.id, time: last.time, value: 470))
        XCTAssertEqual(h.timeline.first { $0.id == last.id }?.goalMet, false)
        // Time: moved to 08:30, it sorts between the 08:20 and the 08:50 ACT.
        XCTAssertTrue(h.updateEntry(last.id, time: at(8, 30), value: nil))
        XCTAssertEqual(rows(h, now: at(10, 0))[3], "08:30 ACT 470 s below goal")
        XCTAssertEqual(h.timeline.first { $0.id == last.id }?.value, 470, "a nil value leaves it")
        // The baseline flag survives an edit; a protamine dose is editable too.
        let base = try XCTUnwrap(h.timeline.first { $0.kind == .baseline })
        h.updateEntry(base.id, time: at(7, 58), value: 131)
        XCTAssertEqual(h.timeline.first?.kind, .baseline)
        XCTAssertEqual(h.timeline.first?.value, 131)
        let prot = try XCTUnwrap(h.timeline.first { $0.kind == .protamine })
        h.updateEntry(prot.id, time: at(9, 45), value: 175)
        XCTAssertEqual(rows(h, now: at(10, 0)).last, "09:45 Protamine 175 mg")
        XCTAssertFalse(h.updateEntry(UUID(), time: at(9, 0), value: 1), "an id that is not in the log changes nothing")
    }

    func testDeletingARowRemovesItFromWhicheverListHoldsIt() throws {
        var h = fullLog()
        let n = h.timeline.count
        for kind in [HeparinEvent.Kind.protamine, .heparin, .act, .baseline] {
            let e = try XCTUnwrap(h.timeline.first { $0.kind == kind })
            h.removeEntry(e.id)
            XCTAssertNil(h.timeline.first { $0.id == e.id })
        }
        XCTAssertEqual(h.timeline.count, n - 4)
        let firstLeft = try XCTUnwrap(h.timeline.first)
        XCTAssertEqual(h.removing(firstLeft.id).timeline.count, n - 5, "removing leaves the original alone")
        XCTAssertEqual(h.timeline.count, n - 4)
    }

    @MainActor func testEachAddEditAndDeleteIsOneUndoStep() throws {
        let store = PatientStore(url: nil)
        store.update(discrete: true) { $0.weightKg = 82; $0.timers.heparin = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30) }
        var states = [store.record]
        func step(_ change: (inout CaseTimers) -> Void) {
            store.update(discrete: true) { change(&$0.timers) }
            states.append(store.record)
        }
        step { $0.heparin?.logACT(seconds: 128, at: self.at(8, 0), kind: .act) }
        step { $0.heparin?.logDose(units: 26000, at: self.at(8, 10), now: self.at(8, 10)) }
        step { $0.heparin?.logACT(seconds: 512, at: self.at(8, 20), kind: .act) }
        let id = try XCTUnwrap(store.record.timers.heparin?.timeline.last?.id)
        step { $0.heparin?.updateEntry(id, time: self.at(8, 25), value: 530) }
        step { $0.heparin?.removeEntry(id) }
        XCTAssertEqual(store.record.timers.heparin?.timeline.count, 2)
        XCTAssertEqual(states.count, 6, "five changes, each its own step")
        for expected in states.dropLast().reversed() {
            store.undo()
            XCTAssertEqual(store.record, expected)
        }
        XCTAssertNil(store.record.timers.heparin?.timeline.first)
    }

    // MARK: A case saved by build 39

    /// A heparin course as build 39 wrote it: a baseline, a bolus, two ACTs and protamine, the timer started by the bolus.
    private func build39Course() -> [String: Any] {
        let ref = at(8, 0).timeIntervalSinceReferenceDate
        func entry(_ minutes: Double, _ value: Double, baseline: Bool = false) -> [String: Any] {
            var e: [String: Any] = ["id": UUID().uuidString, "time": ref + minutes * 60, "value": value]
            if baseline { e["baseline"] = true }
            return e
        }
        return ["purpose": "bypass", "goal": 480, "userGoal": false, "deviceAlt": false, "actEvery": 30,
                "doses": [entry(10, 26000), entry(52, 5000)],
                "acts": [entry(0, 128, baseline: true), entry(20, 512), entry(50, 468)],
                "protamine": [entry(100, 150)]]
    }

    func testABuild39CourseDecodesAndListsEveryEntryAtItsLoggedTime() throws {
        let json = try JSONSerialization.data(withJSONObject: ["heparin": build39Course()])
        let t = try JSONDecoder().decode(CaseTimers.self, from: json)
        let h = try XCTUnwrap(t.heparin)
        XCTAssertEqual(rows(h, now: at(10, 0)), [
            "08:00 Baseline ACT 128 s",
            "08:10 Heparin 26,000 U",
            "08:20 ACT 512 s at goal",
            "08:50 ACT 468 s below goal",
            "08:52 Heparin 5,000 U",
            "09:40 Protamine 150 mg",
        ])
        XCTAssertNil(h.actStart); XCTAssertFalse(h.actOff)
        // Its timer ran from the bolus, as it did: the switch reads on, counting from the last ACT.
        XCTAssertTrue(h.actRunning)
        XCTAssertEqual(due(h), at(9, 20), "08:50 + 30 min")
        // Saved again, it reads back the same: nothing is rewritten.
        let again = try JSONDecoder().decode(CaseTimers.self, from: try JSONEncoder().encode(t))
        XCTAssertEqual(again, t)
        XCTAssertEqual(again.heparin?.timeline.map(\.id), h.timeline.map(\.id))
    }

    // MARK: The ACT reminder's due time

    private func switchedOn(at when: Date, every: Double = 30) -> HeparinCourse {
        var h = course(every: every)
        h.setReminder(true, now: when)
        return h
    }

    func testNoSampleTheDueTimeIsTheIntervalAfterTheSwitchWasTurnedOn() {
        let h = switchedOn(at: at(8, 0))
        XCTAssertEqual(due(h), at(8, 30))
        XCTAssertNil(due(course()), "the switch was never turned on: nothing due")
    }

    func testASampleBeforeTheSwitchWasTurnedOnDoesNotCountSampleAfterItDoes() {
        var h = switchedOn(at: at(8, 30))
        h.logACT(seconds: 130, at: at(8, 10), kind: .baseline)
        XCTAssertEqual(due(h), at(9, 0), "the switch is later than the sample: it counts from the switch")
        h.logACT(seconds: 520, at: at(8, 45), kind: .act)
        XCTAssertEqual(due(h), at(9, 15), "a sample after the switch moves it")
    }

    func testTheExampleFromBenAnACTAt0850WithAThirtyMinuteInterval() {
        var h = switchedOn(at: at(8, 0))
        h.logACT(seconds: 520, at: at(8, 50), kind: .act)
        XCTAssertEqual(due(h), at(9, 20))
    }

    func testALaterSampleRestartsTheCountdownAndABackTimedOneDoesNot() {
        var h = switchedOn(at: at(8, 0))
        h.logACT(seconds: 520, at: at(8, 40), kind: .act)
        h.logACT(seconds: 515, at: at(9, 10), kind: .act)
        XCTAssertEqual(due(h), at(9, 40))
        h.logACT(seconds: 505, at: at(8, 55), kind: .act)
        XCTAssertEqual(due(h), at(9, 40), "back-timed earlier than the latest one: not moved")
    }

    func testEditingOrDeletingTheLatestSampleMovesTheDueTime() throws {
        var h = switchedOn(at: at(8, 0))
        h.logACT(seconds: 520, at: at(8, 40), kind: .act)
        h.logACT(seconds: 515, at: at(9, 10), kind: .act)
        let latest = try XCTUnwrap(h.timeline.last)
        h.updateEntry(latest.id, time: at(9, 20), value: nil)
        XCTAssertEqual(due(h), at(9, 50))
        h.updateEntry(latest.id, time: at(8, 20), value: nil)
        XCTAssertEqual(due(h), at(9, 10), "edited to before the other sample: that one is the latest now")
        h.removeEntry(latest.id)
        XCTAssertEqual(due(h), at(9, 10))
        h.removeEntry(try XCTUnwrap(h.timeline.last).id)
        XCTAssertEqual(due(h), at(8, 30), "no sample left: from the switch again")
    }

    func testAHeparinOrProtamineDoseDoesNotMoveItBecauseADoseStartsNoCountdown() throws {
        var h = switchedOn(at: at(8, 0))
        h.logACT(seconds: 520, at: at(8, 40), kind: .act)
        let before = due(h)
        h.logDose(units: 5000, at: at(8, 55), now: at(8, 55))
        XCTAssertEqual(due(h), before, "a later dose")
        h.logProtamine(mg: 150, at: at(9, 0))
        XCTAssertEqual(due(h), before, "protamine")
        XCTAssertEqual(due(h), at(9, 10))
        // The 1.10 "3 minutes after a bolus" check is gone.
        var fresh = switchedOn(at: at(8, 0))
        fresh.logDose(units: 26000, at: at(8, 5), now: at(8, 5))
        XCTAssertEqual(due(fresh), at(8, 30))
        XCTAssertNotEqual(due(fresh), at(8, 8))
        // And the reminder is still listed after protamine, next to the one-time ACT after protamine.
        let kinds = try reminders(h).map(\.kind)
        XCTAssertTrue(kinds.contains(.act)); XCTAssertTrue(kinds.contains(.protamineACT))
    }

    func testTheIntervalChipsMoveTheDueTime() {
        var h = switchedOn(at: at(8, 0))
        h.logACT(seconds: 520, at: at(8, 40), kind: .act)
        h.actEvery = 20
        XCTAssertEqual(due(h), at(9, 0))
        h.actEvery = 45
        XCTAssertEqual(due(h), at(9, 25))
    }

    func testSwitchOffStopsTheReminderAndKeepsTheLogOnAgainCountsFromNowOrTheLastACT() throws {
        var h = switchedOn(at: at(8, 0))
        h.logACT(seconds: 520, at: at(8, 40), kind: .act)
        let rowsBefore = h.timeline.map(\.id)
        h.setReminder(false, now: at(9, 0))
        XCTAssertNil(due(h)); XCTAssertFalse(h.actRunning)
        XCTAssertNil(try reminders(h).first { $0.kind == .act }, "off: no reminder in the running list")
        XCTAssertEqual(h.timeline.map(\.id), rowsBefore, "logging continues, the log stays")
        h.logACT(seconds: 505, at: at(9, 5), kind: .act)
        XCTAssertNil(due(h), "logging an ACT while it is off does not turn it on")
        // On again at 09:30: the last ACT is 09:05, the switch later: 10:00.
        h.setReminder(true, now: at(9, 30))
        XCTAssertEqual(due(h), at(10, 0))
        // Turning it on while it is on changes nothing.
        h.setReminder(true, now: at(9, 45))
        XCTAssertEqual(due(h), at(10, 0))
        // On again right after an ACT: from the ACT when that is later (it was logged after the switch).
        h.logACT(seconds: 500, at: at(9, 50), kind: .act)
        XCTAssertEqual(due(h), at(10, 20))
    }

    func testSnoozeWorksAsTodayAndANewACTBringsTheReminderBack() throws {
        var h = switchedOn(at: at(8, 0))
        h.logACT(seconds: 520, at: at(8, 40), kind: .act)
        var t = CaseTimers(); t.heparin = h
        let rem = try XCTUnwrap(CaseTimerEngine.reminders(t, record: adult(), data: try data()).first { $0.kind == .act })
        XCTAssertEqual(rem.due, at(9, 10))
        t.snooze(rem, minutes: 5, now: at(9, 12))
        let snoozed = try XCTUnwrap(CaseTimerEngine.reminders(t, record: adult(), data: try data()).first { $0.kind == .act })
        XCTAssertTrue(snoozed.snoozed)
        XCTAssertEqual(snoozed.due, at(9, 17))
        XCTAssertEqual(CaseTimersView.nextDueText(snoozed), "Snoozed to 09:17")
        // An ACT logged at 09:14 gives a new due time (09:44): the snooze no longer applies.
        t.heparin?.logACT(seconds: 510, at: at(9, 14), kind: .act)
        let back = try XCTUnwrap(CaseTimerEngine.reminders(t, record: adult(), data: try data()).first { $0.kind == .act })
        XCTAssertFalse(back.snoozed)
        XCTAssertEqual(back.due, at(9, 44))
    }

    func testStoppingFromTheRunningListTurnsTheSwitchOff() throws {
        var h = switchedOn(at: at(8, 0))
        h.logACT(seconds: 520, at: at(8, 40), kind: .act)
        var t = CaseTimers(); t.heparin = h
        let rem = try XCTUnwrap(CaseTimerEngine.reminders(t, record: adult(), data: try data()).first { $0.kind == .act })
        XCTAssertFalse(t.markDone(rem, now: at(9, 0), ebl: nil), "an ACT needs a value: Log opens the entry")
        t.stop(rem)
        XCTAssertEqual(t.heparin?.actOff, true)
        XCTAssertFalse(t.heparin?.actRunning ?? true)
        XCTAssertEqual(t.heparin?.timeline.count, 1, "the log stays")
    }

    func testTheRunningListNotificationAndActivityGetTheSameDueTime() throws {
        let d = try data()
        var h = switchedOn(at: at(8, 0))
        h.logACT(seconds: 520, at: at(8, 50), kind: .act)
        var r = adult(); r.timers.heparin = h
        let expected = at(9, 20)
        XCTAssertEqual(due(h), expected)
        // The running list and the strip on My Patient: CaseTimerEngine.reminders.
        let list = CaseTimerEngine.reminders(r.timers, record: r, data: d)
        XCTAssertEqual(list.first { $0.kind == .act }?.due, expected)
        // The notifications and the lock-screen activity: CaseTimerSchedule.items (CaseTimerNotifier.sync schedules each timed item
        // and the activity counts down to the first).
        let items = CaseTimerSchedule.items([(id: UUID(), label: "OR 12", record: r)], data: d)
        let act = try XCTUnwrap(items.first { $0.reminder.kind == .act })
        XCTAssertEqual(act.reminder.due, expected)
        XCTAssertEqual(items.first?.reminder.due, expected, "the activity's next timer")
        // The switch row's "Next ACT due".
        XCTAssertEqual(CaseTimersView.nextDueText(list.first { $0.kind == .act }), "Next ACT due 09:20")
        XCTAssertEqual(CaseTimersView.nextDueText(nil), "Next ACT due")
        // Overdue colouring is the reminders' rule (five minutes past).
        XCTAssertEqual(CaseReminder.state(due: expected, at: at(9, 24)), .due)
        XCTAssertEqual(CaseReminder.state(due: expected, at: at(9, 26)), .overdue)
        XCTAssertEqual(CaseReminder.state(due: expected, at: at(9, 0)), .waiting)
        // Turned off, none of them has it.
        r.timers.heparin?.setReminder(false, now: at(9, 0))
        XCTAssertNil(CaseTimerSchedule.items([(id: UUID(), label: "OR 12", record: r)], data: d).first { $0.reminder.kind == .act })
    }

    // MARK: The first dose turns the reminder on; a later one never changes the switch

    func testTheFirstDoseOfACaseTurnsTheReminderOnAtThePurposesDefaultInterval() throws {
        let d = try data()
        let p = try XCTUnwrap(d.purpose("bypass"))
        XCTAssertEqual(p.actEvery.first, 30, "the default the course is created with (pickPurpose)")
        var h = course(every: p.actEvery.first ?? 30)
        XCTAssertFalse(h.actRunning)
        h.logDose(units: 26000, at: at(8, 5), now: at(8, 6))
        XCTAssertTrue(h.actRunning)
        XCTAssertEqual(h.actStart, at(8, 6), "counted from the moment the switch was turned on")
        XCTAssertEqual(h.actEvery, 30)
        XCTAssertEqual(due(h), at(8, 36))
    }

    func testALaterDoseNeverChangesTheSwitch() {
        // Turned off after the first dose: a second dose leaves it off (answer 4).
        var h = course()
        h.logDose(units: 26000, at: at(8, 5), now: at(8, 5))
        h.setReminder(false, now: at(8, 30))
        h.logDose(units: 5000, at: at(8, 40), now: at(8, 40))
        XCTAssertFalse(h.actRunning)
        XCTAssertNil(due(h))
        // Turned on and re-anchored by the user: a later dose does not touch the anchor.
        h.setReminder(true, now: at(8, 50))
        h.logDose(units: 3000, at: at(8, 55), now: at(8, 55))
        XCTAssertEqual(h.actStart, at(8, 50))
        XCTAssertEqual(due(h), at(9, 20))
    }

    func testTheFirstDoseTurnsItOnEvenIfItWasSwitchedOffBeforeAndKeepsAChosenInterval() {
        var h = course(every: 20)
        h.setReminder(true, now: at(7, 0))
        h.setReminder(false, now: at(7, 10))
        h.logDose(units: 26000, at: at(8, 5), now: at(8, 5))
        XCTAssertTrue(h.actRunning)
        XCTAssertEqual(h.actStart, at(8, 5))
        XCTAssertEqual(h.actEvery, 20, "the interval in force stays")
        // Already on before the first dose: the anchor is not moved by it.
        var on = course()
        on.setReminder(true, now: at(7, 0))
        on.logDose(units: 26000, at: at(8, 5), now: at(8, 5))
        XCTAssertEqual(on.actStart, at(7, 0))
    }

    // MARK: Times: the default, the 24-hour control and the future

    func testANewEntryIsTimedNowUntilATimeIsPickedAndAPickedClockTimeResolvesAsTheStartTimeDoes() {
        let now = at(9, 30)
        XCTAssertEqual(HeparinTimeline.resolved(picked: nil, now: now), now)
        XCTAssertEqual(HeparinTimeline.resolved(picked: at(9, 12), now: now), at(9, 12))
        // 23:50 picked just after midnight is yesterday's.
        let after = at(0, 10, day: 13)
        XCTAssertEqual(HeparinTimeline.resolved(picked: at(23, 50, day: 13), now: after), at(23, 50, day: 12))
        // Seconds of a picked time are dropped: a time is to the minute.
        let withSeconds = at(9, 12).addingTimeInterval(41)
        XCTAssertEqual(HeparinTimeline.resolved(picked: withSeconds, now: now), at(9, 12))
    }

    func testATimeInTheFutureIsRefused() throws {
        let now = at(9, 30).addingTimeInterval(40)
        XCTAssertNil(HeparinTimeline.resolved(picked: at(9, 31), now: now), "the next minute")
        XCTAssertNil(HeparinTimeline.resolved(picked: at(11, 0), now: now))
        XCTAssertNotNil(HeparinTimeline.resolved(picked: at(9, 30), now: now), "this minute is now")
        XCTAssertNil(HeparinTimeline.resolvedEdit(picked: at(9, 45), original: at(9, 0), now: now))
        XCTAssertEqual(HeparinTimeline.resolvedEdit(picked: at(9, 15), original: at(9, 0), now: now), at(9, 15))
        XCTAssertEqual(HeparinTimeline.resolvedEdit(picked: nil, original: at(9, 0), now: now), at(9, 0), "unchanged")
        // The refusal blocks the Log and Save buttons: a block issue that says so.
        let issue = try XCTUnwrap(HeparinTimeline.timeIssue(nil))
        XCTAssertEqual(issue.level, .block)
        XCTAssertEqual(issue.text, "That time is in the future.")
        XCTAssertNil(HeparinTimeline.timeIssue(at(9, 0)))
        XCTAssertTrue([issue].blocks)
    }

    // MARK: The checks are the ones the old fields had

    func testTheEntryChecksAreTheDoseACTAndProtamineChecksUnchanged() throws {
        let d = try data()
        let p = try XCTUnwrap(d.purpose("bypass"))
        let r = adult()
        var h = course()
        let direct = CaseTimerEngine.heparinIssues(units: 3000, course: h, purpose: p, record: r, data: d)
        XCTAssertEqual(CaseTimerEngine.entryIssues(kind: .heparin, value: 3000, course: h, purpose: p, record: r, data: d), direct)
        XCTAssertTrue(direct.needsConfirm, "3,000 U is under the bypass dose: the second tap, as before")
        XCTAssertTrue(CaseTimerEngine.entryIssues(kind: .heparin, value: 30, course: h, purpose: p, record: r, data: d).needsConfirm, "30 for 30,000 U")
        XCTAssertTrue(CaseTimerEngine.entryIssues(kind: .heparin, value: nil, course: h, purpose: p, record: r, data: d).blocks, "no value: no Log")
        var child = r; child.ageYears = 9
        XCTAssertTrue(CaseTimerEngine.entryIssues(kind: .heparin, value: 24000, course: h, purpose: p, record: child, data: d).blocks, "children locked out")
        // ACT: nothing under 30 s, as the old Log button.
        XCTAssertTrue(CaseTimerEngine.entryIssues(kind: .act, value: 20, course: h, purpose: p, record: r, data: d).blocks)
        XCTAssertTrue(CaseTimerEngine.entryIssues(kind: .baseline, value: nil, course: h, purpose: p, record: r, data: d).blocks)
        XCTAssertTrue(CaseTimerEngine.entryIssues(kind: .act, value: 512, course: h, purpose: p, record: r, data: d).isEmpty)
        // Protamine over the ceiling still blocks.
        h.logDose(units: 26000, at: at(8, 0), now: at(8, 0))
        XCTAssertTrue(CaseTimerEngine.entryIssues(kind: .protamine, value: 800, course: h, purpose: p, record: r, data: d).blocks)
        // The dose-range check is for a first dose: an edit of the only dose is checked as a first dose again.
        var vascular = course("vascular", goal: nil)
        vascular.logDose(units: 5000, at: at(8, 0), now: at(8, 0))
        let vp = try XCTUnwrap(d.purpose("vascular"))
        let vOnly = try XCTUnwrap(vascular.timeline.first)
        XCTAssertEqual(CaseTimerEngine.entryIssues(kind: .heparin, value: 2000, course: vascular.removing(vOnly.id), purpose: vp, record: r, data: d).worst, .soft)
    }

    // MARK: Unchanged: the protamine suggestion, the handoff

    func testTheProtamineSuggestionStillRestsOnTheInitialDoseWhateverLaterDosesAreLogged() throws {
        let d = try data()
        let p = try XCTUnwrap(d.purpose("bypass"))
        var h = course()
        h.logDose(units: 26000, at: at(8, 10), now: at(8, 10))
        let one = try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: d.protamine))
        h.logDose(units: 5000, at: at(8, 52), now: at(8, 52))
        h.logDose(units: 3000, at: at(9, 5), now: at(9, 5))
        let several = try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: d.protamine))
        XCTAssertEqual(several.basisUnits, 26000, "the first (initial) dose, not the last or the total")
        XCTAssertEqual(several.totalUnits, 34000)
        XCTAssertEqual(several.lowMg, one.lowMg); XCTAssertEqual(several.highMg, one.highMg); XCTAssertEqual(several.capMg, one.capMg)
        XCTAssertEqual(several.lowMg, 210); XCTAssertEqual(several.highMg, 260)
        // "First" is by logged time: a dose entered later but timed earlier is the initial one.
        h.logDose(units: 20000, at: at(8, 0), now: at(9, 10))
        XCTAssertEqual(CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: d.protamine)?.basisUnits, 20000)
    }

    func testTheHandoffPrintsNothingAboutHeparinOrACTBeforeOrAfter() {
        // The handoff and the summaries read the antibiotic courses only; a log of doses and ACTs, however long, changes no line.
        var with = adult()
        with.setProcedures(PlannedProcedure.parse("CABG x3"))
        let without = with
        with.timers.heparin = fullLog()
        XCTAssertEqual(PatientBriefs.plainText(PatientBriefs.handoff(with)), PatientBriefs.plainText(PatientBriefs.handoff(without)))
        XCTAssertEqual(PatientBriefs.plainText(PatientBriefs.preop(with)), PatientBriefs.plainText(PatientBriefs.preop(without)))
    }
}
