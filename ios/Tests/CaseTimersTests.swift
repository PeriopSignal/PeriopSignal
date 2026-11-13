import XCTest
@testable import PeriopSignal

/// Case timers (1.9): the reminders, the antibiotic and heparin doses, and the safety checks the clinical review doc
/// asks for, against the draft numbers in reference.json "caseTimers".
final class CaseTimersTests: XCTestCase {
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

    // MARK: Data

    func testSignedOffAndReleased() throws {
        let d = try data()
        XCTAssertEqual(d.reviewed, "2026-11-03", "signed off in the review doc")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        DraftGate.update(from: try ReferenceLoader.decode(try Data(contentsOf: url)))
        XCTAssertEqual(DraftGate.released, ["caseTimers", "mtp", "mcs", "tee"])
        XCTAssertFalse(DraftGate.isDraft("caseTimers"))
        XCTAssertFalse(d.sources.isEmpty)
        for s in d.sources { XCTAssertTrue(s.url.hasPrefix("https://"), s.id) }
        for p in d.heparinPurposes { for id in p.sources ?? [] { XCTAssertNotNil(d.sources.first { $0.id == id }, "\(p.id) cites \(id)") } }
    }

    func testNoPresetGoalForVascular() throws {
        let d = try data()
        XCTAssertNil(d.purpose("vascular")?.goal, "ACTION-1: no preset ACT goal for open vascular or carotid")
        XCTAssertNil(d.purpose("endovascular")?.goal)
        // 1.10 changes this (Ben, Nov 7: "Make ACT goes 480 sec based off STS"): 450 s → 480 s.
        XCTAssertEqual(d.purpose("bypass")?.goal, 480, "1.10: ≥ 480 s (STS 2018)")
        XCTAssertEqual(d.purpose("bypass")?.goalDevice, 400)
        XCTAssertNil(d.purpose("ecmo")?.goal, "ECMO: varies by center, the user sets it")
        for p in d.heparinPurposes { XCTAssertEqual(p.actEvery, [30, 20], "\(p.id): 30 or 20 min") }
        XCTAssertEqual(d.check("glucose")?.options.first?.minutes, 60, "glucose every 60 min by default")
        XCTAssertEqual(d.check("glucose")?.every, [30, 60, 90, 120])
    }

    // MARK: Antibiotics

    func testCefazolinRedoseFourHoursFromTheDose() throws {
        let d = try data()
        var t = CaseTimers()
        t.antibiotic = AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0, ebl: 0)])
        let rem = CaseTimerEngine.reminders(t, record: adult(), data: d)
        let a = try XCTUnwrap(rem.first { $0.kind == .antibiotic })
        XCTAssertEqual(a.due, t0.addingTimeInterval(4 * 3600))
        XCTAssertEqual(a.state(at: t0.addingTimeInterval(3600)), .waiting)
        XCTAssertEqual(a.state(at: t0.addingTimeInterval(4 * 3600 + 60)), .due)
        XCTAssertEqual(a.state(at: t0.addingTimeInterval(4 * 3600 + 600)), .overdue)
    }

    func testNoRedoseDrugHasALongCaseReminderInstead() throws {
        var t = CaseTimers()
        t.antibiotic = AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: t0)])
        let rem = CaseTimerEngine.reminders(t, record: adult(), data: try data())
        XCTAssertTrue(rem.filter { $0.kind == .antibiotic }.isEmpty, "no routine redose")
        XCTAssertEqual(rem.first { $0.kind == .longCase }?.due, t0.addingTimeInterval(8 * 3600), "long-case reminder at 8 h")
        var c = CaseTimers()
        c.antibiotic = AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0)])
        XCTAssertNil(CaseTimerEngine.reminders(c, record: adult(), data: try data()).first { $0.kind == .longCase }, "only drugs without a redose interval")
    }

    func testBloodLossOver1500SinceTheDose() throws {
        let d = try data()
        var t = CaseTimers()
        t.antibiotic = AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0, ebl: 200)])
        var r = adult()
        r.fluids["ebl"] = 1600
        XCTAssertNil(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .bloodLoss }, "1,400 mL since the dose")
        r.fluids["ebl"] = 1700
        XCTAssertNotNil(CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .bloodLoss })
    }

    func testCefazolinThreeGramsFrom120kg() throws {
        let def = try XCTUnwrap(try data().antibiotic("cefazolin"))
        XCTAssertEqual(CaseTimerEngine.antibioticDose(def, record: adult(119)).text, "2 g")
        XCTAssertEqual(CaseTimerEngine.antibioticDose(def, record: adult(120)).text, "3 g")
    }

    func testGentamicinDosingWeight() throws {
        // 178 cm man: IBW 50 + 2.3 × 10.1 in ≈ 73.2 kg. 120 kg > 120% IBW → 73.2 + 0.4 × 46.8 ≈ 91.9 kg → 460 mg.
        let def = try XCTUnwrap(try data().antibiotic("gentamicin"))
        let dw = try XCTUnwrap(CaseTimerEngine.dosingWeight(actual: 120, ibw: adult().ibw))
        XCTAssertTrue(dw.adjusted)
        XCTAssertEqual(dw.kg, 91.9, accuracy: 0.2)
        XCTAssertTrue(CaseTimerEngine.antibioticDose(def, record: adult(120)).text.hasPrefix("460 mg"))
        // Within 120% of IBW: the actual weight.
        XCTAssertEqual(CaseTimerEngine.dosingWeight(actual: 80, ibw: 73.2)?.adjusted, false)
        var noHeight = adult(120); noHeight.heightCm = nil
        XCTAssertNotNil(CaseTimerEngine.antibioticDose(def, record: noHeight).needs)
    }

    func testNoGentamicinPromptOnBypass() throws {
        let d = try data()
        var t = CaseTimers()
        t.antibiotic = AntibioticCourse(drug: "gentamicin", doses: [TimedEntry(time: t0, ebl: 0)])
        t.heparin = HeparinCourse(purpose: "bypass", goal: 450, actEvery: 30)
        var r = adult(); r.fluids["ebl"] = 2000
        XCTAssertTrue(CaseTimerEngine.reminders(t, record: r, data: d).filter { $0.kind == .bloodLoss || $0.kind == .antibiotic }.isEmpty)
    }

    // MARK: Heparin

    // 1.12 follow-up (Ben, Nov 12, answer 4): a heparin dose starts no countdown of its own, so the "3 minutes after the bolus" first
    // check this test asserted is gone. A case saved before 1.12 (a bolus, no stamp) counts from its first dose, then from each ACT.
    func testFirstACTThirtyMinutesAfterTheSwitchThenFromEachACT() throws {
        let d = try data()
        var h = HeparinCourse(purpose: "bypass", goal: 450, actEvery: 30)
        h.doses = [TimedEntry(time: t0, value: 24000)]
        var t = CaseTimers(); t.heparin = h
        XCTAssertEqual(CaseTimerEngine.reminders(t, record: adult(), data: d).first { $0.kind == .act }?.due, t0.addingTimeInterval(1800))
        t.heparin?.acts = [TimedEntry(time: t0.addingTimeInterval(240), value: 520)]
        XCTAssertEqual(CaseTimerEngine.reminders(t, record: adult(), data: d).first { $0.kind == .act }?.due, t0.addingTimeInterval(240 + 1800))
        let s = CaseTimerEngine.status(t.heparin!, record: adult())
        XCTAssertEqual(s.goalMet, true)
        XCTAssertEqual(s.initialPerKg, 300)
    }

    func testSuggestedBolus() throws {
        let p = try XCTUnwrap(try data().purpose("bypass"))
        XCTAssertEqual(CaseTimerEngine.suggestedBolus(p, weightKg: 80), 24000)
        XCTAssertNil(CaseTimerEngine.suggestedBolus(p, weightKg: nil))
        XCTAssertEqual(CaseTimerEngine.suggestedBolus(try XCTUnwrap(try data().purpose("offpump")), weightKg: 80), 16000, "off-pump 200 U/kg")
    }

    func testSafetyChecks() throws {
        let d = try data()
        let bypass = try XCTUnwrap(d.purpose("bypass")), vascular = try XCTUnwrap(d.purpose("vascular"))
        var child = adult(30); child.ageYears = 10
        XCTAssertTrue(CaseTimerEngine.heparinIssues(units: 9000, course: nil, purpose: bypass, record: child, data: d).blocks, "children locked out")
        var noWeight = adult(); noWeight.weightKg = nil
        XCTAssertTrue(CaseTimerEngine.heparinIssues(units: 24000, course: nil, purpose: bypass, record: noWeight, data: d).blocks, "weight required")
        XCTAssertTrue(CaseTimerEngine.heparinIssues(units: 30, course: nil, purpose: bypass, record: adult(), data: d).needsConfirm, "30 for 30,000 U")
        XCTAssertTrue(CaseTimerEngine.heparinIssues(units: 24000, course: nil, purpose: vascular, record: adult(), data: d).needsConfirm, "bypass-size dose outside bypass")
        let ecmo = try XCTUnwrap(d.purpose("ecmo"))
        let ecmoIssues = CaseTimerEngine.heparinIssues(units: 24000, course: nil, purpose: ecmo, record: adult(), data: d)
        XCTAssertFalse(ecmoIssues.needsConfirm, "ECMO is exempt from the hard confirm")
        XCTAssertEqual(ecmoIssues.worst, .soft, "but 300 U/kg is still flagged against 50–100")
        XCTAssertTrue(CaseTimerEngine.heparinIssues(units: 16000, course: nil, purpose: bypass, record: adult(), data: d).needsConfirm, "200 U/kg on bypass")
        XCTAssertFalse(CaseTimerEngine.heparinIssues(units: 24000, course: nil, purpose: bypass, record: adult(), data: d).needsConfirm)
        XCTAssertEqual(CaseTimerEngine.heparinIssues(units: 2000, course: nil, purpose: vascular, record: adult(), data: d).worst, .soft, "25 U/kg is below 50 − 20%")
        XCTAssertTrue(CaseTimerEngine.weightIssues(adult(210), data: d).needsConfirm)
        XCTAssertTrue(CaseTimerEngine.goalIssues(350, purpose: bypass, rules: d.heparinRules).needsConfirm)
    }

    // MARK: Protamine

    func testProtamineOnBypassFromTheInitialBolus() throws {
        let d = try data()
        let p = try XCTUnwrap(d.purpose("bypass"))
        var h = HeparinCourse(purpose: "bypass", goal: 450, actEvery: 30)
        h.doses = [TimedEntry(time: t0, value: 30000), TimedEntry(time: t0.addingTimeInterval(3600), value: 5000)]
        let s = try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: d.protamine))
        XCTAssertEqual(s.lowMg, 240)
        XCTAssertEqual(s.highMg, 300)
        XCTAssertEqual(s.totalUnits, 35000)
        XCTAssertTrue(s.basisIsInitial)
        XCTAssertNil(CaseTimerEngine.protamineIssues(mg: 300, course: h, purpose: p, rules: d.protamine).worst.flatMap { $0 >= .confirm ? $0 : nil })
        XCTAssertTrue(CaseTimerEngine.protamineIssues(mg: 400, course: h, purpose: p, rules: d.protamine).needsConfirm, "1.33 mg per 100 U")
        XCTAssertTrue(CaseTimerEngine.protamineIssues(mg: 800, course: h, purpose: p, rules: d.protamine).blocks, "2.67 mg per 100 U")
        h.bypassOn = t0
        XCTAssertTrue(CaseTimerEngine.protamineIssues(mg: 200, course: h, purpose: p, rules: d.protamine).needsConfirm, "bypass still running")
    }

    func testProtamineWithoutBypassHasNoComputedDose() throws {
        let d = try data()
        let p = try XCTUnwrap(d.purpose("vascular"))
        var h = HeparinCourse(purpose: "vascular", goal: nil, actEvery: 30)
        h.doses = [TimedEntry(time: t0, value: 5000)]
        let s = try XCTUnwrap(CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: d.protamine))
        XCTAssertNil(s.lowMg, "no half-life estimate: follow the label and titrate to the ACT")
        XCTAssertEqual(s.labelMaxMg, 50)
        XCTAssertTrue(CaseTimerEngine.protamineIssues(mg: 140, course: h, purpose: p, rules: d.protamine).blocks, "2.8 mg per 100 U given")
    }

    func testACTAfterProtamineWhenTheDoseEnds() throws {
        let d = try data()
        var h = HeparinCourse(purpose: "bypass", goal: 450, actEvery: 30)
        h.doses = [TimedEntry(time: t0, value: 30000)]
        h.protamine = [TimedEntry(time: t0.addingTimeInterval(7200), value: 250)]
        var t = CaseTimers(); t.heparin = h
        let rem = CaseTimerEngine.reminders(t, record: adult(), data: d)
        // A timer the bolus implied (a case saved by build 39) stops its recurring check once protamine is logged, as it did
        // there. The 1.12 switch, turned on, stays on after protamine until it is turned off (Ben: "for example after protamine").
        XCTAssertNil(rem.first { $0.kind == .act }, "saved by build 39: it stopped with protamine")
        t.heparin?.setReminder(true, now: t0.addingTimeInterval(7300))
        XCTAssertNotNil(CaseTimerEngine.reminders(t, record: adult(), data: d).first { $0.kind == .act }, "the switch is on")
        t.heparin?.actOff = true
        XCTAssertNil(CaseTimerEngine.reminders(t, record: adult(), data: d).first { $0.kind == .act }, "turned off")
        let rem2 = CaseTimerEngine.reminders(t, record: adult(), data: d)
        // 250 mg at 50 mg per 10 min = 50 min, then 3 min.
        XCTAssertEqual(rem2.first { $0.kind == .protamineACT }?.due, t0.addingTimeInterval(7200 + 53 * 60))
    }

    // MARK: Checks

    func testGlucoseAlertsAndInterval() throws {
        let d = try data()
        let g = try XCTUnwrap(d.check("glucose"))
        XCTAssertNotNil(CaseTimerEngine.glucoseAlert(190, def: g))
        XCTAssertNotNil(CaseTimerEngine.glucoseAlert(65, def: g))
        XCTAssertNil(CaseTimerEngine.glucoseAlert(140, def: g))
        var t = CaseTimers()
        t.checks["glucose"] = LabCheckCourse(every: 30, started: t0)
        XCTAssertEqual(CaseTimerEngine.reminders(t, record: adult(), data: d).first { $0.kind == .glucose }?.due, t0.addingTimeInterval(1800))
    }

    func testRecordKeepsTimersThroughEncoding() throws {
        var r = adult()
        r.timers.antibiotic = AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0, ebl: 0)])
        let back = try JSONDecoder().decode(PatientRecord.self, from: try JSONEncoder().encode(r))
        XCTAssertEqual(back.timers, r.timers)
        XCTAssertTrue(PatientRecord().timers.isEmpty)
    }

    func testEveryCaseIsScheduled() throws {
        let d = try data()
        var a = adult(); a.timers.checks["abg"] = LabCheckCourse(every: 30, started: t0)
        var b = adult(); b.timers.checks["abg"] = LabCheckCourse(every: 60, started: t0)
        let items = CaseTimerSchedule.items([(UUID(), "OR 3", b), (UUID(), "OR 5", a)], data: d)
        XCTAssertEqual(items.map(\.caseLabel), ["OR 5", "OR 3"], "soonest first, across rooms")
    }
}
