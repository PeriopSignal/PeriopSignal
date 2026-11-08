import XCTest
@testable import PeriopSignal

/// Case timers 1.10 (Ben, Nov 7): ACT goals by purpose (i-STAT), the flat heparin dose, protamine by a fixed ratio on
/// the initial dose with a cap (method (c)), start time and "recurring every" with Other, chips that clear on a second
/// tap, the running timers' order, snooze and stop, several antibiotics, and saved 1.9 logs.
final class CaseTimers110Tests: XCTestCase {
    private func data() throws -> CaseTimerData {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        return try XCTUnwrap(ReferenceLoader.decode(try Data(contentsOf: url)).caseTimers, "caseTimers decodes")
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func adult(_ kg: Double? = 80) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 60; r.sex = .male; r.heightCm = 178; r.weightKg = kg
        return r
    }

    // MARK: Goals

    func testGoalsPerPurpose() throws {
        let d = try data()
        XCTAssertEqual(d.purpose("bypass")?.goal, 480, "STS 2018 / EACTS 2024: 480 s")
        XCTAssertEqual(d.purpose("tavr")?.goal, 250, "ten Berg 2021: 250–300 s, the lower bound")
        XCTAssertEqual(d.purpose("offpump")?.goal, 300, "OCAB: practice, Ben Nov 4")
        XCTAssertEqual(d.purpose("offpump")?.name, "OCAB", "renamed; the stored id stays offpump")
        XCTAssertNil(d.purpose("vascular")?.goal, "ACTION-1: no preset goal")
        XCTAssertEqual(d.purpose("vascular")?.name, "Vascular/TEVAR")
        XCTAssertNil(d.purpose("ecmo")?.goal, "varies by centre: the user sets it")
        XCTAssertEqual(d.heparinRules.actDevice, "i-STAT")
        XCTAssertEqual(d.offeredPurposes.map(\.id), ["bypass", "vascular", "ecmo", "tavr", "offpump", "other"], "Ben's order")
        XCTAssertEqual(d.purpose("endovascular")?.hidden, true, "EVAR / TEVAR still reads for a saved case")
        XCTAssertNil(d.purpose("endovascular")?.goal)
        for p in d.heparinPurposes { XCTAssertEqual(CaseTimerEngine.presetGoal(p), p.goal) }
    }

    func testGoalEditing() throws {
        let d = try data()
        let bypass = try XCTUnwrap(d.purpose("bypass")), tavr = try XCTUnwrap(d.purpose("tavr")), vascular = try XCTUnwrap(d.purpose("vascular"))
        var h = HeparinCourse(purpose: "bypass", goal: bypass.goal, actEvery: 30)
        h = CaseTimerEngine.settingGoal(h, to: 500, purpose: bypass)
        XCTAssertEqual(h.goal, 500); XCTAssertTrue(h.userGoal)
        h = CaseTimerEngine.settingGoal(h, to: nil, purpose: bypass)
        XCTAssertEqual(h.goal, 480, "back to the preset"); XCTAssertFalse(h.userGoal)
        h = CaseTimerEngine.settingGoal(h, to: 480, purpose: bypass)
        XCTAssertFalse(h.userGoal, "the preset value is the preset")
        // A 1.9 device goal is cleared by any edit.
        var old = HeparinCourse(purpose: "bypass", goal: 400, actEvery: 30); old.deviceAlt = true
        XCTAssertFalse(CaseTimerEngine.settingGoal(old, to: nil, purpose: bypass).deviceAlt)
        XCTAssertEqual(CaseTimerEngine.settingGoal(old, to: nil, purpose: bypass).goal, 480)

        var v = HeparinCourse(purpose: "vascular", goal: nil, actEvery: 30)
        v = CaseTimerEngine.settingGoal(v, to: 250, purpose: vascular)
        XCTAssertEqual(v.goal, 250); XCTAssertTrue(v.userGoal)
        XCTAssertNil(CaseTimerEngine.settingGoal(v, to: nil, purpose: vascular).goal, "removing it leaves none")

        XCTAssertTrue(CaseTimerEngine.goalIssues(350, purpose: bypass, rules: d.heparinRules).needsConfirm, "a bypass goal under 400 s")
        XCTAssertTrue(CaseTimerEngine.goalIssues(48, purpose: bypass, rules: d.heparinRules).blocks, "seconds, not minutes")
        XCTAssertTrue(CaseTimerEngine.goalIssues(250, purpose: tavr, rules: d.heparinRules).isEmpty)

        // The goal is reached at the goal value.
        var c = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
        c.doses = [TimedEntry(time: t0, value: 24000)]
        c.acts = [TimedEntry(time: t0.addingTimeInterval(240), value: 480)]
        XCTAssertEqual(CaseTimerEngine.status(c, record: adult()).goalMet, true)
        c.acts = [TimedEntry(time: t0.addingTimeInterval(240), value: 479)]
        XCTAssertEqual(CaseTimerEngine.status(c, record: adult()).goalMet, false)
    }

    // MARK: Flat dose

    func testFlatDoseText() throws {
        let d = try data()
        let bypass = try XCTUnwrap(d.purpose("bypass")), tavr = try XCTUnwrap(d.purpose("tavr"))
        let vascular = try XCTUnwrap(d.purpose("vascular")), ocab = try XCTUnwrap(d.purpose("offpump"))
        let ecmo = try XCTUnwrap(d.purpose("ecmo")), other = try XCTUnwrap(d.purpose("other"))
        XCTAssertEqual(CaseTimerEngine.flatDose(bypass, weightKg: 80), "300–400 U/kg ≈ 24,000–32,000 U")
        XCTAssertEqual(CaseTimerEngine.flatDose(bypass, weightKg: 82), "300–400 U/kg ≈ 25,000–33,000 U", "24,600 and 32,800 to 1,000 U")
        XCTAssertEqual(CaseTimerEngine.flatDose(tavr, weightKg: 70), "70–100 U/kg ≈ 5,000–7,000 U", "4,900 to 500 U")
        XCTAssertEqual(CaseTimerEngine.flatDose(vascular, weightKg: 80), "50–100 U/kg ≈ 4,000–8,000 U, or 5,000 U flat")
        XCTAssertEqual(CaseTimerEngine.flatDose(ocab, weightKg: 99), "100–200 U/kg ≈ 10,000–20,000 U", "9,900 → 10,000; 19,800 → 20,000")
        XCTAssertEqual(CaseTimerEngine.flatDose(ecmo, weightKg: 53), "50–100 U/kg ≈ 2,500–5,500 U", "2,650 → 2,500; 5,300 → 5,500")
        XCTAssertEqual(CaseTimerEngine.flatDose(tavr, weightKg: 5), "70–100 U/kg ≈ 500 U", "one number when both ends round alike")
        XCTAssertNil(CaseTimerEngine.flatDose(bypass, weightKg: nil), "no weight: the view asks for it, no per-kg-only text")
        XCTAssertNil(CaseTimerEngine.flatDose(bypass, weightKg: 0))
        XCTAssertNil(CaseTimerEngine.flatDose(other, weightKg: 80), "Other has no range")
        for w in [50.0, 63, 80, 118, 150] {
            let s = try XCTUnwrap(CaseTimerEngine.flatDose(bypass, weightKg: w))
            XCTAssertTrue(s.contains("≈"), s)
            XCTAssertFalse(s.contains("="), s)
        }
        XCTAssertEqual(CaseTimerEngine.roundUnits(9_749), 9_500)
        XCTAssertEqual(CaseTimerEngine.roundUnits(9_751), 10_000)
        XCTAssertEqual(CaseTimerEngine.roundUnits(24_499), 24_000)
        XCTAssertEqual(CaseTimerEngine.suggestedBolus(bypass, weightKg: 82), 25_000)
    }

    // MARK: Protamine, method (c)

    func testProtamineFixedRatioOnTheInitialDoseWithACap() throws {
        let d = try data()
        let p = try XCTUnwrap(d.purpose("bypass"))
        for (initial, lo, hi) in [(30_000.0, 240.0, 300.0), (24_000, 190, 240), (25_000, 200, 250), (40_000, 320, 400)] {
            var h = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
            h.doses = [TimedEntry(time: t0, value: initial)]
            let s = try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: d.protamine))
            XCTAssertEqual(s.lowMg, lo, "\(initial)")
            XCTAssertEqual(s.highMg, hi, "\(initial)")
            XCTAssertEqual(s.capMg, hi, "the cap is 1 mg per 100 U of the initial dose")
            XCTAssertTrue(s.basisIsInitial)
            // Top-up doses never change the suggestion.
            h.doses.append(TimedEntry(time: t0.addingTimeInterval(3600), value: 10_000))
            h.doses.append(TimedEntry(time: t0.addingTimeInterval(5400), value: 5_000))
            let after = try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: d.protamine))
            XCTAssertEqual(after.lowMg, lo); XCTAssertEqual(after.highMg, hi); XCTAssertEqual(after.capMg, hi)
            XCTAssertEqual(after.basisUnits, initial)
            XCTAssertEqual(after.totalUnits, initial + 15_000)
        }
    }

    func testProtamineCapCurrentACTAndChecks() throws {
        let d = try data()
        let p = try XCTUnwrap(d.purpose("bypass"))
        var h = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
        // Logged out of order: the earliest dose is the initial one.
        h.doses = [TimedEntry(time: t0.addingTimeInterval(3600), value: 10_000), TimedEntry(time: t0, value: 30_000)]
        h.acts = [TimedEntry(time: t0.addingTimeInterval(-600), value: 130, baseline: true),
                  TimedEntry(time: t0.addingTimeInterval(4000), value: 532)]
        var s = try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: d.protamine))
        XCTAssertEqual(s.basisUnits, 30_000)
        XCTAssertEqual(s.lastACT, 532, "the current ACT beside the suggestion")
        XCTAssertEqual(s.baselineACT, 130)
        XCTAssertEqual(s.remainingMg, 300)
        h.protamine = [TimedEntry(time: t0.addingTimeInterval(7200), value: 200)]
        s = try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: d.protamine))
        XCTAssertEqual(s.remainingMg, 100)
        XCTAssertEqual(s.lowMg, 240, "given protamine does not change the suggestion")
        XCTAssertTrue(CaseTimerEngine.protamineIssues(mg: 100, course: h, purpose: p, rules: d.protamine).filter { $0.level >= .soft }.isEmpty, "300 mg = 1.0")
        let over = CaseTimerEngine.protamineIssues(mg: 150, course: h, purpose: p, rules: d.protamine)
        XCTAssertTrue(over.contains { $0.level == .soft }, "1.17: above the cap")
        XCTAssertFalse(over.needsConfirm)
        XCTAssertTrue(CaseTimerEngine.protamineIssues(mg: 200, course: h, purpose: p, rules: d.protamine).needsConfirm, "1.33")
        // 1.10 review: the STS 2.6 ceiling reads on the heparin given (STS does not state its basis); 2.67 on the initial
        // dose needs a second tap, it no longer blocks.
        XCTAssertFalse(CaseTimerEngine.protamineIssues(mg: 600, course: h, purpose: p, rules: d.protamine).blocks, "2.0 of the total given")
        XCTAssertTrue(CaseTimerEngine.protamineIssues(mg: 600, course: h, purpose: p, rules: d.protamine).needsConfirm, "2.67 of the initial")
        h.protamine.append(TimedEntry(time: t0.addingTimeInterval(7800), value: 150))
        XCTAssertEqual(try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: d.protamine)).remainingMg, 0, "never negative")
    }

    func testProtamineWithoutBypassIsCappedOnTheInitialDose() throws {
        let d = try data()
        let p = try XCTUnwrap(d.purpose("tavr"))
        var h = HeparinCourse(purpose: "tavr", goal: 250, actEvery: 30)
        h.doses = [TimedEntry(time: t0, value: 7_000)]
        var s = try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: d.protamine))
        XCTAssertNil(s.lowMg, "no lower bound without bypass: titrate to the ACT")
        XCTAssertEqual(s.capMg, 70)
        XCTAssertEqual(s.labelMaxMg, 70)
        h.doses.append(TimedEntry(time: t0.addingTimeInterval(2400), value: 3_000))
        s = try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: d.protamine))
        XCTAssertEqual(s.capMg, 70, "the initial dose, not the 10,000 U total")
        // 1.10 review: 1.9 mg per 100 U of the 10,000 U given is under the STS ceiling; 2.7 of the initial dose needs a
        // second tap.
        XCTAssertTrue(CaseTimerEngine.protamineIssues(mg: 190, course: h, purpose: p, rules: d.protamine).needsConfirm, "2.7 mg per 100 U of the initial dose")
        XCTAssertFalse(CaseTimerEngine.protamineIssues(mg: 190, course: h, purpose: p, rules: d.protamine).blocks)
        XCTAssertTrue(CaseTimerEngine.protamineIssues(mg: 270, course: h, purpose: p, rules: d.protamine).blocks, "2.7 of all 10,000 U given")
        XCTAssertNil(CaseTimerEngine.protamineSuggestion(HeparinCourse(purpose: "tavr", goal: 250, actEvery: 30), purpose: p, rules: d.protamine))
    }

    // MARK: Recurrence

    func testRecurrenceChoices() throws {
        let d = try data()
        XCTAssertEqual(CaseTimerRecurrence.antibioticChips(try XCTUnwrap(d.antibiotic("cefazolin"))), [180, 240, 300])
        XCTAssertEqual(CaseTimerRecurrence.antibioticChips(try XCTUnwrap(d.antibiotic("cefoxitin"))), [60, 120, 180])
        XCTAssertEqual(CaseTimerRecurrence.antibioticChips(try XCTUnwrap(d.antibiotic("clindamycin"))), [300, 360, 420])
        XCTAssertEqual(CaseTimerRecurrence.antibioticChips(try XCTUnwrap(d.antibiotic("vancomycin"))), [240, 360, 480])
        XCTAssertEqual(CaseTimerRecurrence.antibioticDefault(try XCTUnwrap(d.antibiotic("cefazolin"))), 240, "the Bratzler interval is preselected")
        XCTAssertNil(CaseTimerRecurrence.antibioticDefault(try XCTUnwrap(d.antibiotic("vancomycin"))), "no routine redose: none preselected")
        for id in ["abg", "glucose", "coag"] {
            XCTAssertEqual(CaseTimerRecurrence.labChips(try XCTUnwrap(d.check(id))), [30, 60, 90], id)
        }
        XCTAssertEqual(d.check("coag")?.name, "Coagulation studies")
        XCTAssertEqual(CaseTimerRecurrence.actChips(d.purpose("bypass")), [20, 30, 60])
        let values = CaseTimerRecurrence.otherValues(maxMinutes: CaseTimerRecurrence.labMax)
        XCTAssertEqual(values.first, 5); XCTAssertEqual(values.last, 240); XCTAssertEqual(values.count, 48)
        XCTAssertTrue(values.allSatisfy { $0.truncatingRemainder(dividingBy: 5) == 0 })
        XCTAssertEqual(CaseTimerRecurrence.otherPreselect(current: nil, preferred: 240, maxMinutes: 720), 240)
        XCTAssertEqual(CaseTimerRecurrence.otherPreselect(current: 47, preferred: 240, maxMinutes: 720), 45)
        XCTAssertEqual(CaseTimerRecurrence.otherPreselect(current: nil, preferred: 800, maxMinutes: 720), 720)
        XCTAssertEqual(CaseTimerRecurrence.antibioticPreferred(try XCTUnwrap(d.antibiotic("vancomycin")), rules: d.antibioticRules), 480, "the long-case hours")
        XCTAssertEqual(CaseTimerEngine.interval(205), "3 h 25 min")
        XCTAssertEqual(CaseTimerEngine.interval(45), "45 min")
        XCTAssertEqual(CaseTimerEngine.interval(240), "4 h")
    }

    func testRecurrenceScheduling() throws {
        let d = try data()
        let r = adult()
        var t = CaseTimers()
        t.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0, ebl: 0)], everyMinutes: 205),
                         AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: t0, ebl: 0)], everyMinutes: 360),
                         AntibioticCourse(drug: "cefoxitin", doses: [TimedEntry(time: t0, ebl: 0)])]
        var rem = CaseTimerEngine.reminders(t, record: r, data: d)
        XCTAssertEqual(rem.first { $0.id == "antibiotic.cefazolin" }?.due, t0.addingTimeInterval(205 * 60), "Other: 3 h 25 min")
        XCTAssertEqual(rem.first { $0.id == "antibiotic.vancomycin" }?.due, t0.addingTimeInterval(6 * 3600), "an institutional interval")
        XCTAssertNil(rem.first { $0.id == "longCase.vancomycin" }, "a chosen interval replaces the long-case reminder")
        XCTAssertEqual(rem.first { $0.id == "antibiotic.cefoxitin" }?.due, t0.addingTimeInterval(2 * 3600), "no choice saved: the sourced interval")
        t.antibiotics[0].everyMinutes = 0
        t.antibiotics[1].everyMinutes = 0
        rem = CaseTimerEngine.reminders(t, record: r, data: d)
        XCTAssertNil(rem.first { $0.id == "antibiotic.cefazolin" }, "none chosen: no redose timer")
        XCTAssertNil(rem.first { $0.id == "longCase.cefazolin" }, "and no long-case text for a drug that has an interval")
        XCTAssertEqual(rem.first { $0.id == "longCase.vancomycin" }?.due, t0.addingTimeInterval(8 * 3600))
        XCTAssertEqual(CaseTimerRecurrence.storedInterval(RecurrencePick()), 0)
        XCTAssertEqual(CaseTimerRecurrence.storedInterval(RecurrencePick(minutes: 300)), 300)

        // Labs: from the start time, then from the last check.
        var labs = CaseTimers()
        labs.checks["coag"] = LabCheckCourse(every: 45, started: t0)
        labs.checks["abg"] = LabCheckCourse(every: 90, started: t0)
        rem = CaseTimerEngine.reminders(labs, record: r, data: d)
        let coag = try XCTUnwrap(rem.first { $0.kind == .lab })
        XCTAssertEqual(coag.id, "lab.coag")
        XCTAssertEqual(coag.due, t0.addingTimeInterval(45 * 60))
        let sent = labs.markDone(coag, now: t0.addingTimeInterval(50 * 60), ebl: nil)
        XCTAssertTrue(sent)
        XCTAssertEqual(CaseTimerEngine.reminders(labs, record: r, data: d).first { $0.kind == .lab }?.due, t0.addingTimeInterval(95 * 60))
        XCTAssertEqual(rem.first { $0.kind == .abg }?.due, t0.addingTimeInterval(90 * 60))

        // ACT: Start timer, then a bolus, then an ACT.
        var h = HeparinCourse(purpose: "tavr", goal: 250, actEvery: 45)
        h.actStart = t0
        XCTAssertEqual(CaseTimerEngine.actDue(h, rules: d.heparinRules), t0.addingTimeInterval(45 * 60))
        h.doses = [TimedEntry(time: t0.addingTimeInterval(600), value: 7000)]
        XCTAssertEqual(CaseTimerEngine.actDue(h, rules: d.heparinRules), t0.addingTimeInterval(600 + 180), "3 min after a bolus")
        h.acts = [TimedEntry(time: t0.addingTimeInterval(840), value: 260)]
        XCTAssertEqual(CaseTimerEngine.actDue(h, rules: d.heparinRules), t0.addingTimeInterval(840 + 45 * 60))
        var ht = CaseTimers(); ht.heparin = h
        XCTAssertNotNil(CaseTimerEngine.reminders(ht, record: r, data: d).first { $0.kind == .act })
        ht.heparin?.actOff = true
        XCTAssertNil(CaseTimerEngine.reminders(ht, record: r, data: d).first { $0.kind == .act }, "stopped")
        XCTAssertNil(CaseTimerEngine.actDue(HeparinCourse(purpose: "tavr", goal: 250, actEvery: 30), rules: d.heparinRules), "nothing started")

        // A clock time is the nearest such moment.
        XCTAssertEqual(CaseTimerRecurrence.resolveStart(t0.addingTimeInterval(13 * 3600), now: t0), t0.addingTimeInterval(-11 * 3600))
        XCTAssertEqual(CaseTimerRecurrence.resolveStart(t0.addingTimeInterval(-13 * 3600), now: t0), t0.addingTimeInterval(11 * 3600))
        XCTAssertEqual(CaseTimerRecurrence.resolveStart(t0.addingTimeInterval(-7200), now: t0), t0.addingTimeInterval(-7200))
    }

    // MARK: Running timers

    func testRunningTimersSoonestFirstWithSnoozeAndStop() throws {
        let d = try data()
        var r = adult()
        var t = CaseTimers()
        t.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0, ebl: 0)], everyMinutes: 240),
                         AntibioticCourse(drug: "ampicillin", doses: [TimedEntry(time: t0, ebl: 0)], everyMinutes: 120)]
        t.checks["glucose"] = LabCheckCourse(every: 60, started: t0)
        t.checks["abg"] = LabCheckCourse(every: 30, started: t0)
        var rem = CaseTimerEngine.reminders(t, record: r, data: d)
        XCTAssertEqual(rem.map(\.id), ["abg", "glucose", "antibiotic.ampicillin", "antibiotic.cefazolin"], "soonest first")
        r.fluids["ebl"] = 1600
        rem = CaseTimerEngine.reminders(t, record: r, data: d)
        XCTAssertEqual(rem.first?.kind, .bloodLoss, "due now comes first")
        XCTAssertEqual(rem.filter { $0.kind == .bloodLoss }.count, 2, "one per antibiotic")

        // Snooze the ABG at its due time: 5 min later, and the list re-sorts.
        r.fluids["ebl"] = 0
        let abg = try XCTUnwrap(CaseTimerEngine.reminders(t, record: r, data: d).first)
        t.snooze(abg, now: t0.addingTimeInterval(31 * 60))
        rem = CaseTimerEngine.reminders(t, record: r, data: d)
        let snoozed = try XCTUnwrap(rem.first { $0.id == "abg" })
        XCTAssertTrue(snoozed.snoozed)
        XCTAssertEqual(snoozed.due, t0.addingTimeInterval(36 * 60))
        // Snoozing again pushes it from now.
        t.snooze(snoozed, now: t0.addingTimeInterval(37 * 60))
        XCTAssertEqual(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.id == "abg" }?.due, t0.addingTimeInterval(42 * 60))
        // Sent: the snooze goes and the next check runs from now.
        let abgSent = t.markDone(snoozed, now: t0.addingTimeInterval(40 * 60), ebl: nil)
        XCTAssertTrue(abgSent)
        XCTAssertNil(t.snoozes["abg"])
        XCTAssertEqual(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.id == "abg" }?.due, t0.addingTimeInterval(70 * 60))

        // Stop: the timer ends; a rule's reminder is put away until its due time changes.
        let glucose = try XCTUnwrap(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.id == "glucose" })
        t.stop(glucose)
        XCTAssertNil(t.checks["glucose"])
        var v = CaseTimers()
        v.antibiotics = [AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: t0, ebl: 0)])]
        let long = try XCTUnwrap(CaseTimerEngine.reminders(v, record: r, data: d).first { $0.kind == .longCase })
        v.stop(long)
        XCTAssertNil(CaseTimerEngine.reminders(v, record: r, data: d).first { $0.kind == .longCase })
        v.antibiotics[0].doses.append(TimedEntry(time: t0.addingTimeInterval(7200), ebl: 0))
        XCTAssertEqual(CaseTimerEngine.reminders(v, record: r, data: d).first { $0.kind == .longCase }?.due, t0.addingTimeInterval(7200 + 8 * 3600), "a new dose brings it back")
        // Stop an antibiotic's redose timer: the course and its doses stay.
        let cef = try XCTUnwrap(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.id == "antibiotic.cefazolin" })
        t.stop(cef)
        XCTAssertEqual(t.course("cefazolin")?.everyMinutes, 0)
        XCTAssertEqual(t.course("cefazolin")?.doses.count, 1)
        XCTAssertNil(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.id == "antibiotic.cefazolin" })
        // A due ACT needs a value: Done opens the section instead.
        var h = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30); h.doses = [TimedEntry(time: t0, value: 24000)]
        var ht = CaseTimers(); ht.heparin = h
        let act = try XCTUnwrap(CaseTimerEngine.reminders(ht, record: r, data: d).first { $0.kind == .act })
        let actDone = ht.markDone(act, now: t0, ebl: nil)
        XCTAssertFalse(actDone)
        ht.stop(act)
        XCTAssertEqual(ht.heparin?.actOff, true)
    }

    func testCountdownText() {
        XCTAssertEqual(CaseTimerEngine.countdown(to: t0.addingTimeInterval(3725), now: t0), "01h:02m:05s")
        XCTAssertEqual(CaseTimerEngine.countdown(to: t0, now: t0.addingTimeInterval(65)), "00h:01m:05s", "time overdue")
        XCTAssertEqual(CaseTimerEngine.countdown(to: t0.addingTimeInterval(4 * 3600 + 0.9), now: t0), "04h:00m:00s")
        XCTAssertEqual(ClockText.time(Date(timeIntervalSince1970: 0)).count, 5, "HH:mm, 24-hour")
    }

    // MARK: Chips

    func testChipsClearOnASecondTap() {
        XCTAssertEqual(ChipToggle.tap(nil as String?, "bypass"), "bypass")
        XCTAssertNil(ChipToggle.tap("bypass", "bypass"))
        XCTAssertEqual(ChipToggle.tap("bypass", "tavr"), "tavr")

        var p = RecurrencePick()
        p.tapChip(30)
        XCTAssertEqual(p.minutes, 30); XCTAssertTrue(p.chipOn(30))
        p.tapChip(30)
        XCTAssertNil(p.minutes, "second tap clears")
        p.tapChip(60)
        p.tapOther(preselect: 45)
        XCTAssertTrue(p.other); XCTAssertEqual(p.minutes, 45); XCTAssertFalse(p.chipOn(60))
        p.setOther(50)
        XCTAssertEqual(p.minutes, 50)
        p.tapOther(preselect: 45)
        XCTAssertFalse(p.other); XCTAssertNil(p.minutes, "a second tap on Other clears it too")
        p.tapOther(preselect: 45); p.tapChip(90)
        XCTAssertFalse(p.other); XCTAssertEqual(p.minutes, 90)
        XCTAssertTrue(RecurrencePick(running: 45, chips: [30, 60, 90]).other, "a running Other interval shows on Other")
        XCTAssertTrue(RecurrencePick(running: 60, chips: [30, 60, 90]).chipOn(60))
        XCTAssertNil(RecurrencePick(running: 0, chips: [30, 60, 90]).minutes)
    }

    // MARK: Saved 1.9 cases

    /// A 1.9 log as 1.9 wrote it (JSONEncoder's default dates: seconds since 2001).
    private func log19() -> [String: Any] {
        let ref = t0.timeIntervalSinceReferenceDate
        let none: [Any] = []
        let dose: [String: Any] = ["id": UUID().uuidString, "time": ref, "ebl": 0]
        let antibiotic: [String: Any] = ["drug": "cefazolin", "doses": [dose]]
        let bolus: [String: Any] = ["id": UUID().uuidString, "time": ref + 600, "value": 16000]
        let act: [String: Any] = ["id": UUID().uuidString, "time": ref + 840, "value": 310]
        let heparin: [String: Any] = ["purpose": "offpump", "goal": 300, "userGoal": false, "deviceAlt": false, "actEvery": 30,
                                      "doses": [bolus], "acts": [act], "protamine": none]
        let abg: [String: Any] = ["every": 30, "started": ref, "done": none]
        let checks: [String: Any] = ["abg": abg]
        return ["antibiotic": antibiotic, "heparin": heparin, "checks": checks]
    }

    func testDecodingA19Log() throws {
        let d = try data()
        let json = try JSONSerialization.data(withJSONObject: log19())
        let t = try JSONDecoder().decode(CaseTimers.self, from: json)
        XCTAssertEqual(t.antibiotics.map(\.drug), ["cefazolin"], "the single 1.9 course")
        XCTAssertNil(t.antibiotics.first?.everyMinutes, "the sourced interval")
        XCTAssertEqual(t.heparin?.purpose, "offpump")
        XCTAssertEqual(d.purpose(t.heparin!.purpose)?.name, "OCAB")
        XCTAssertNil(t.heparin?.actStart); XCTAssertEqual(t.heparin?.actOff, false)
        XCTAssertTrue(t.snoozes.isEmpty)
        let rem = CaseTimerEngine.reminders(t, record: adult(), data: d)
        XCTAssertEqual(rem.first { $0.id == "antibiotic.cefazolin" }?.due, t0.addingTimeInterval(4 * 3600))
        XCTAssertEqual(rem.first { $0.kind == .act }?.due, t0.addingTimeInterval(840 + 1800))
        XCTAssertEqual(rem.first { $0.kind == .abg }?.due, t0.addingTimeInterval(1800))

        // Saved again in the 1.10 shape, and read back the same.
        let again = try JSONEncoder().encode(t)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: again) as? [String: Any])
        XCTAssertNil(obj["antibiotic"]); XCTAssertNotNil(obj["antibiotics"])
        XCTAssertEqual(try JSONDecoder().decode(CaseTimers.self, from: again), t)

        // Inside a saved patient record.
        var rec = try XCTUnwrap(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(adult())) as? [String: Any])
        rec["timers"] = log19()
        let back = try JSONDecoder().decode(PatientRecord.self, from: try JSONSerialization.data(withJSONObject: rec))
        XCTAssertEqual(back.timers.antibiotics.count, 1)
        XCTAssertEqual(back.timers.heparin?.doses.first?.value, 16000)

        // A saved EVAR / TEVAR case still reads, under its own name, and a 1.9 device goal stays as saved.
        var tevar = log19()
        let empty: [Any] = []
        let tevarHeparin: [String: Any] = ["purpose": "endovascular", "goal": NSNull(), "doses": empty, "acts": empty, "protamine": empty]
        tevar["heparin"] = tevarHeparin
        let tv = try JSONDecoder().decode(CaseTimers.self, from: try JSONSerialization.data(withJSONObject: tevar))
        XCTAssertEqual(d.purpose(tv.heparin!.purpose)?.name, "EVAR / TEVAR")
        var dev = log19()
        let devHeparin: [String: Any] = ["purpose": "bypass", "goal": 400, "deviceAlt": true, "doses": empty, "acts": empty, "protamine": empty]
        dev["heparin"] = devHeparin
        let dv = try JSONDecoder().decode(CaseTimers.self, from: try JSONSerialization.data(withJSONObject: dev))
        XCTAssertEqual(dv.heparin?.goal, 400); XCTAssertEqual(dv.heparin?.deviceAlt, true)
    }

    func testSeveralAntibioticsKeepTheirOwnIDs() throws {
        let d = try data()
        var t = CaseTimers()
        t.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0, ebl: 0)]),
                         AntibioticCourse(drug: "metronidazole", doses: [TimedEntry(time: t0, ebl: 0)])]
        let ids = CaseTimerEngine.reminders(t, record: adult(), data: d).map(\.id)
        XCTAssertEqual(Set(ids), ["antibiotic.cefazolin", "longCase.metronidazole"])
        XCTAssertEqual(t.course("metronidazole")?.id, "metronidazole")
        // The 1.9 accessor still reads the first and replaces the list.
        XCTAssertEqual(t.antibiotic?.drug, "cefazolin")
        let back = try JSONDecoder().decode(CaseTimers.self, from: try JSONEncoder().encode(t))
        XCTAssertEqual(back, t)
        let items = CaseTimerSchedule.items([(UUID(), "OR 4", { var r = adult(); r.timers = t; return r }())], data: d)
        XCTAssertEqual(Set(items.map { $0.id.split(separator: ".").dropFirst().joined(separator: ".") }), Set(ids), "one notification each")
    }
}
