import XCTest
@testable import PeriopSignal

/// 1.10 review fixes in Case Timers: a dismissed blood-loss reminder comes back after the next dose; a baseline ACT alone
/// starts no ACT check; the protamine cap never rounds above 1 mg per 100 U; off bypass the STS ceiling reads on the
/// heparin given, on bypass it stays on the initial bolus (1.9);
/// Start time defaults to the current time; a saved 1.9 bypass preset reads as 480 s; the goal caption says i-STAT once;
/// the two ⓘ captions (Ben's answer 4); the blood-loss subtitle is short.
final class Review110TimersTests: XCTestCase {
    private func data() throws -> CaseTimerData {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        return try XCTUnwrap(ReferenceLoader.decode(try Data(contentsOf: url)).caseTimers, "caseTimers decodes")
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func adult(_ kg: Double = 80) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 60; r.sex = .male; r.heightCm = 178; r.weightKg = kg
        return r
    }

    // MARK: Blood-loss redose

    func testDismissedBloodLossReminderComesBackAfterTheNextDose() throws {
        let d = try data()
        var r = adult()
        var t = CaseTimers()
        t.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0, ebl: 0)], everyMinutes: 240)]
        r.fluids["ebl"] = 1600
        let bl = try XCTUnwrap(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .bloodLoss })
        t.stop(bl)
        XCTAssertNil(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .bloodLoss }, "dismissed")

        // The 4-h redose given from the section ("Redose given" appends a dose, nothing else).
        t.antibiotics[0].doses.append(TimedEntry(time: t0.addingTimeInterval(4 * 3600), ebl: 1600))
        XCTAssertNil(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .bloodLoss }, "0 mL since the new dose")
        r.fluids["ebl"] = 3200
        let back = CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .bloodLoss }
        XCTAssertNotNil(back, "1,600 mL since the new dose: the dismissal was for the earlier dose only")
        XCTAssertEqual(back?.since, t0.addingTimeInterval(4 * 3600))

        // Dismissed again, then the antibiotic row's Given (markDone on the redose reminder) brings it back too.
        let backRem = try XCTUnwrap(back)
        t.stop(backRem)
        XCTAssertNil(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .bloodLoss })
        let redose = try XCTUnwrap(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .antibiotic })
        let given = t.markDone(redose, now: t0.addingTimeInterval(8 * 3600), ebl: 3200)
        XCTAssertTrue(given)
        XCTAssertNil(t.snoozes["bloodLoss.cefazolin"], "a new dose clears the drug's put-away rules")
        r.fluids["ebl"] = 4800
        XCTAssertNotNil(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .bloodLoss })

        // A snooze applies to this occurrence: it shows snoozed, and after the next dose it is due now again.
        let now = try XCTUnwrap(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .bloodLoss })
        t.snooze(now, now: t0.addingTimeInterval(9 * 3600))
        let snoozed = try XCTUnwrap(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .bloodLoss })
        XCTAssertTrue(snoozed.snoozed)
        XCTAssertEqual(snoozed.due, t0.addingTimeInterval(9 * 3600 + 300))
        t.antibiotics[0].doses.append(TimedEntry(time: t0.addingTimeInterval(10 * 3600), ebl: 3000))
        let fresh = try XCTUnwrap(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .bloodLoss })
        XCTAssertFalse(fresh.snoozed); XCTAssertNil(fresh.due)
    }

    func testBloodLossSubtitleIsShort() throws {
        let d = try data()
        var r = adult(); r.fluids["ebl"] = 1600
        var t = CaseTimers()
        t.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0, ebl: 0)], everyMinutes: 240)]
        let bl = try XCTUnwrap(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .bloodLoss })
        XCTAssertEqual(bl.detail, "EBL ≥ 1,500 mL since the last dose")
        XCTAssertLessThanOrEqual(bl.detail.count, 36, "fits the running row")
    }

    // MARK: ACT timer

    func testBaselineACTAloneStartsNoACTCheck() throws {
        let d = try data()
        var h = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
        h.acts = [TimedEntry(time: t0, value: 128, baseline: true)]
        XCTAssertFalse(h.actRunning)
        XCTAssertNil(CaseTimerEngine.actDue(h, rules: d.heparinRules), "no heparin, no Start timer: nothing due")
        var t = CaseTimers(); t.heparin = h
        XCTAssertNil(CaseTimerEngine.reminders(t, record: adult(), data: d).first { $0.kind == .act }, "no ACT check before heparin")

        // Start timer: the running list and the timer row agree.
        t.heparin?.actStart = t0.addingTimeInterval(60)
        XCTAssertEqual(t.heparin?.actRunning, true)
        XCTAssertEqual(CaseTimerEngine.reminders(t, record: adult(), data: d).first { $0.kind == .act }?.due,
                       t0.addingTimeInterval(60 + 1800))
        // Or a bolus without Start timer.
        t.heparin?.actStart = nil
        t.heparin?.doses = [TimedEntry(time: t0.addingTimeInterval(600), value: 24000)]
        XCTAssertEqual(t.heparin?.actRunning, true)
        XCTAssertEqual(CaseTimerEngine.reminders(t, record: adult(), data: d).first { $0.kind == .act }?.due,
                       t0.addingTimeInterval(600 + 180))
        t.heparin?.actOff = true
        XCTAssertEqual(t.heparin?.actRunning, false)
        XCTAssertNil(CaseTimerEngine.reminders(t, record: adult(), data: d).first { $0.kind == .act })
    }

    // MARK: Protamine

    func testProtamineCapNeverAboveOneMgPer100U() throws {
        let d = try data()
        let tavr = try XCTUnwrap(d.purpose("tavr")), bypass = try XCTUnwrap(d.purpose("bypass"))
        for (initial, cap) in [(7_500.0, 75.0), (3_500, 35), (5_500, 55), (6_500, 65), (7_000, 70), (5_000, 50)] {
            var h = HeparinCourse(purpose: "tavr", goal: 250, actEvery: 30)
            h.doses = [TimedEntry(time: t0, value: initial)]
            let s = try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: tavr, rules: d.protamine))
            XCTAssertEqual(s.capMg, cap, "\(initial) U")
            XCTAssertTrue(CaseTimerEngine.protamineIssues(mg: s.capMg, course: h, purpose: tavr, rules: d.protamine)
                .filter { $0.level >= .soft }.isEmpty, "logging the shown cap is not 'above the cap' (\(initial) U)")
        }
        for purpose in [tavr, bypass] {
            for initial in stride(from: 500.0, through: 45_000, by: 500) {
                var h = HeparinCourse(purpose: purpose.id, goal: purpose.goal, actEvery: 30)
                h.doses = [TimedEntry(time: t0, value: initial)]
                let s = try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: purpose, rules: d.protamine))
                XCTAssertLessThanOrEqual(s.capMg, initial / 100 * d.protamine.ratioHigh + 1e-9, "\(purpose.id) \(initial) U")
                if let lo = s.lowMg { XCTAssertLessThanOrEqual(lo, s.capMg) }
            }
        }
        // An odd bypass dose: 24,600 U → cap 245 mg (not 250).
        var h = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
        h.doses = [TimedEntry(time: t0, value: 24_600)]
        XCTAssertEqual(try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: bypass, rules: d.protamine)).capMg, 245)
    }

    func testSTSCeilingReadsOnTheHeparinGivenOffBypass() throws {
        let d = try data()
        let p = try XCTUnwrap(d.purpose("vascular"))
        // Long open vascular case: 5,000 U, then three 2,000 U top-ups.
        var h = HeparinCourse(purpose: "vascular", goal: nil, actEvery: 30)
        h.doses = [TimedEntry(time: t0, value: 5_000)] + (1...3).map { TimedEntry(time: t0.addingTimeInterval(Double($0) * 3600), value: 2_000) }
        h.protamine = [TimedEntry(time: t0.addingTimeInterval(4 * 3600), value: 50)]
        let issues = CaseTimerEngine.protamineIssues(mg: 90, course: h, purpose: p, rules: d.protamine)
        XCTAssertFalse(issues.blocks, "140 mg is 1.27 mg per 100 U of the 11,000 U given: it can be logged")
        XCTAssertTrue(issues.needsConfirm, "2.8 mg per 100 U of the initial dose still needs a second tap")
        XCTAssertTrue(issues.contains { $0.text.contains("11,000 U given") }, issues.map(\.text).joined(separator: " | "))
        // The total reads with two decimals, so 1.27 never shows as "1.3" next to "over 1.3".
        let confirm = try XCTUnwrap(issues.first { $0.level == .confirm }).text
        XCTAssertTrue(confirm.contains("1.27 per 100 U of all 11,000 U given"), confirm)
        XCTAssertFalse(confirm.contains("(1.3"), confirm)
        XCTAssertTrue(confirm.hasPrefix("2.8 mg per 100 U of the initial dose, over 1.3"), confirm)
        // Over 2.6 of everything given is still blocked (STS 2018).
        XCTAssertTrue(CaseTimerEngine.protamineIssues(mg: 250, course: h, purpose: p, rules: d.protamine).blocks, "300 mg / 11,000 U = 2.7")
        // A single dose: initial and total are the same.
        var one = HeparinCourse(purpose: "vascular", goal: nil, actEvery: 30)
        one.doses = [TimedEntry(time: t0, value: 5_000)]
        XCTAssertTrue(CaseTimerEngine.protamineIssues(mg: 140, course: one, purpose: p, rules: d.protamine).blocks)
        XCTAssertTrue(CaseTimerEngine.protamineIssues(mg: 70, course: one, purpose: p, rules: d.protamine).needsConfirm, "1.4")
    }

    func testSTSCeilingStaysOnTheInitialBolusOnBypass() throws {
        let d = try data()
        let p = try XCTUnwrap(d.purpose("bypass"))
        // 30,000 U initial, then a 5,000 U top-up: 800 mg is 2.67 per 100 U of the initial bolus (2.29 of the total).
        var h = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
        h.doses = [TimedEntry(time: t0, value: 30_000), TimedEntry(time: t0.addingTimeInterval(3600), value: 5_000)]
        let issues = CaseTimerEngine.protamineIssues(mg: 800, course: h, purpose: p, rules: d.protamine)
        XCTAssertTrue(issues.blocks, "the top-up never relaxes the STS block on bypass (1.9)")
        XCTAssertTrue(issues.contains { $0.level == .block && $0.text.contains("of the initial dose") }, issues.map(\.text).joined(separator: " | "))
        // Just under the ceiling on the initial bolus: a second tap, not a block.
        let under = CaseTimerEngine.protamineIssues(mg: 770, course: h, purpose: p, rules: d.protamine)
        XCTAssertFalse(under.blocks, "2.57 of the initial")
        XCTAssertTrue(under.needsConfirm)
    }

    // MARK: Start time

    func testStartTimeDefaultsToTheCurrentTime() {
        let opened = t0, tapped = t0.addingTimeInterval(40 * 60)
        let pick = StartTimePick()
        XCTAssertEqual(pick.shown(now: opened), opened)
        XCTAssertEqual(pick.shown(now: tapped), tapped, "the picker follows the clock until a time is picked")
        XCTAssertEqual(pick.resolved(now: tapped), tapped, "Start logs the time it is tapped, not when the section opened")
        let picked = StartTimePick(picked: t0.addingTimeInterval(-15 * 60))
        XCTAssertEqual(picked.shown(now: tapped), t0.addingTimeInterval(-15 * 60))
        XCTAssertEqual(picked.resolved(now: tapped), t0.addingTimeInterval(-15 * 60))
        // A picked clock time more than 12 h ahead was yesterday's.
        XCTAssertEqual(StartTimePick(picked: tapped.addingTimeInterval(13 * 3600)).resolved(now: tapped), tapped.addingTimeInterval(-11 * 3600))
    }

    // MARK: Saved 1.9 bypass goal

    private func course(_ fields: [String: Any]) throws -> HeparinCourse {
        let none: [Any] = []
        var obj: [String: Any] = ["actEvery": 30, "doses": none, "acts": none, "protamine": none]
        for (k, v) in fields { obj[k] = v }
        return try JSONDecoder().decode(HeparinCourse.self, from: try JSONSerialization.data(withJSONObject: obj))
    }

    func testA19BypassPresetReadsAs480() throws {
        let d = try data()
        let p = try XCTUnwrap(d.purpose("bypass"))
        let preset = try course(["purpose": "bypass", "goal": 450, "userGoal": false, "deviceAlt": false])
        XCTAssertEqual(preset.goal, 480, "the retired 1.9 preset reads as the 1.10 preset")
        XCTAssertFalse(preset.userGoal)
        XCTAssertEqual(CaseTimerEngine.goalCaption(preset, p, device: "i-STAT"), "i-STAT · STS 2018 and EACTS 2024: above 480 s")
        var h = preset
        h.doses = [TimedEntry(time: t0, value: 24_000)]
        h.acts = [TimedEntry(time: t0.addingTimeInterval(300), value: 460)]
        XCTAssertEqual(CaseTimerEngine.status(h, record: adult()).goalMet, false, "460 s is under 480 s")
        var t = CaseTimers(); t.heparin = h
        XCTAssertEqual(CaseTimerEngine.reminders(t, record: adult(), data: d).first { $0.kind == .act }?.detail.hasPrefix("Goal ≥ 480 s"), true)

        // Written without the flags (an early 1.9 record): still a preset.
        XCTAssertEqual(try course(["purpose": "bypass", "goal": 450]).goal, 480)
        // A goal the user set, the 1.9 device goal, and other purposes stay as saved.
        XCTAssertEqual(try course(["purpose": "bypass", "goal": 450, "userGoal": true]).goal, 450)
        XCTAssertEqual(try course(["purpose": "bypass", "goal": 400, "deviceAlt": true]).goal, 400)
        XCTAssertEqual(try course(["purpose": "offpump", "goal": 300]).goal, 300)
        XCTAssertEqual(try course(["purpose": "tavr", "goal": 450]).goal, 450)
        XCTAssertEqual(try course(["purpose": "bypass", "goal": 500]).goal, 500)
        // Saved again, it reads back the same.
        XCTAssertEqual(try JSONDecoder().decode(HeparinCourse.self, from: try JSONEncoder().encode(preset)), preset)
    }

    // MARK: Captions

    func testGoalCaptionSaysTheDeviceOnce() throws {
        let d = try data()
        var p = try XCTUnwrap(d.purpose("bypass"))
        let h = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
        let caption = CaseTimerEngine.goalCaption(h, p, device: "i-STAT")
        XCTAssertEqual(caption, "i-STAT · STS 2018 and EACTS 2024: above 480 s")
        XCTAssertEqual(caption.components(separatedBy: "i-STAT").count - 1, 1)
        // A reference.json cached from 1.10.0 still wrote the device into the text.
        p.goalText = "i-STAT; STS 2018 and EACTS 2024: above 480 s"
        XCTAssertEqual(CaseTimerEngine.goalCaption(h, p, device: "i-STAT"), "i-STAT · STS 2018 and EACTS 2024: above 480 s")
        let tavr = try XCTUnwrap(d.purpose("tavr"))
        XCTAssertEqual(CaseTimerEngine.goalCaption(HeparinCourse(purpose: "tavr", goal: 250, actEvery: 30), tavr, device: "i-STAT"), "i-STAT · 250–300 s")
    }

    func testInfoCaptions() throws {
        let d = try data()
        XCTAssertEqual(CaseTimerEngine.actGoalInfo(device: d.heparinRules.actDevice ?? "i-STAT"), "ACT goals assume i-STAT values.")
        let bypass = CaseTimerEngine.protamineInfo(bypass: true, rules: d.protamine)
        XCTAssertEqual(bypass, "Suggested from the initial heparin dose (0.8–1 mg per 100 U, capped at 1 mg per 100 U), not the total given; later doses do not change it (EACTS 2024).")
        let other = CaseTimerEngine.protamineInfo(bypass: false, rules: d.protamine)
        XCTAssertTrue(other.contains("initial heparin dose") && other.contains("not the total given"), other)
        XCTAssertFalse(other.contains("0.8"), "no lower bound without bypass")
    }
}
