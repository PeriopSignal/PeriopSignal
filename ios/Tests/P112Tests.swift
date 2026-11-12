import XCTest
@testable import PeriopSignal

/// 1.12 follow-up, helper P (Ben, Nov 12): "Have option to just add antibiotic and heparin to intraop meds without using timer."
/// (1) An antibiotic course can be recorded only: no reminder of any kind, still listed where antibiotics are listed, with a
/// "Redose reminder" switch. (2) The quick-add bar records only and offers the timer as an optional second chip. (3) Heparin has one
/// log, Case Timers' Heparin & ACT timeline; "+ Heparin" and a typed dose write to it and the ACT reminder stays off unless switched
/// on. (4) A link to the surgical prophylaxis reference. Every test that depends on the clock passes its own `now`.
final class P112Tests: XCTestCase {

    private func at(_ hour: Int, _ minute: Int, day: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { at(9, 30) }

    private func data() throws -> CaseTimerData {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        return try XCTUnwrap(ReferenceLoader.decode(try Data(contentsOf: url)).caseTimers, "caseTimers decodes")
    }

    override func setUpWithError() throws {
        CaseAntibiotics.override = try data()
    }

    override func tearDown() {
        CaseAntibiotics.override = nil
    }

    private func adult(_ kg: Double = 82) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = kg
        return r
    }

    private func child() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 8; r.weightKg = 26
        return r
    }

    private func read(_ line: String, record: PatientRecord? = nil, tab: QuickAddTab = .intraop, at when: Date? = nil) -> QuickAddReading {
        QuickAdd.read(line, record: record ?? adult(), tab: tab, now: when ?? now)
    }

    private func abxDoses(_ q: QuickAddReading) -> [IntraopAntibioticDose] {
        q.findings.compactMap { f -> IntraopAntibioticDose? in if case .antibioticDose(let d) = f.change { return d }; return nil }
    }

    private func hepDoses(_ q: QuickAddReading) -> [IntraopHeparinDose] {
        q.findings.compactMap { f -> IntraopHeparinDose? in if case .heparinDose(let d) = f.change { return d }; return nil }
    }

    /// Files the chips the way the bar's Add does: the optional second choices start left out.
    private func filed(_ line: String, into record: PatientRecord, at when: Date? = nil) -> PatientRecord {
        var r = record
        let chips = QuickAdd.chips(read(line, record: record, at: when), record: record)
        PatientNote.apply(QuickAdd.changes(chips, dropped: QuickAdd.offByDefault(chips)), to: &r)
        return r
    }

    private func recordOnly(_ drug: String, doses: [TimedEntry], reminders: Bool = false) -> AntibioticCourse {
        AntibioticCourse(drug: drug, doses: doses, everyMinutes: nil, reminders: reminders)
    }

    // MARK: 1. A recorded-only course: the model

    func testACourseSavedByBuild39KeepsTheRemindersItHad() throws {
        let json = """
        {"antibiotics":[{"drug":"cefazolin","doses":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","time":790000000,"ebl":100}],"everyMinutes":240},
                        {"drug":"vancomycin","doses":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FE","time":790000000,"given":"1 g"}],"everyMinutes":0}]}
        """
        let t = try JSONDecoder().decode(CaseTimers.self, from: Data(json.utf8))
        XCTAssertEqual(t.antibiotics.map(\.reminders), [true, true], "no key: the reminders it had")
        XCTAssertEqual(t.antibiotics.map(\.recordOnly), [false, false])
        let rem = CaseTimerEngine.reminders(t, record: adult(), data: try data())
        XCTAssertNotNil(rem.first { $0.id == "antibiotic.cefazolin" }, "cefazolin's redose is still made")
        // The 1.9 single "antibiotic" key too.
        let old = """
        {"antibiotic":{"drug":"cefazolin","doses":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","time":790000000}]}}
        """
        XCTAssertEqual(try JSONDecoder().decode(CaseTimers.self, from: Data(old.utf8)).antibiotics.first?.reminders, true)
    }

    func testTheRemindersFlagIsWrittenOnlyWhenFalseAndRoundTrips() throws {
        let timed = AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: at(8, 0))])
        let only = recordOnly("cefazolin", doses: [TimedEntry(time: at(8, 0), given: "2 g")])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(timed), as: UTF8.self).contains("reminders"), "a timed course reads back as it always did")
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(only), as: UTF8.self).contains("\"reminders\":false"))
        XCTAssertEqual(try JSONDecoder().decode(AntibioticCourse.self, from: try JSONEncoder().encode(only)), only)
        XCTAssertEqual(try JSONDecoder().decode(AntibioticCourse.self, from: try JSONEncoder().encode(timed)), timed)
        var r = adult()
        r.timers.antibiotics = [only, timed]
        let again = try JSONDecoder().decode(PatientRecord.self, from: try JSONEncoder().encode(r))
        XCTAssertEqual(again.timers.antibiotics.map(\.reminders), [false, true])
    }

    func testARecordedOnlyCourseMakesNoReminderOfAnyKindAtAnyHour() throws {
        let d = try data()
        // Cefazolin has a redose interval, vancomycin none (the long-case rule); a record with 2,000 mL of blood loss would also raise
        // the blood-loss rule on a timed course. None of the three is made for a course recorded only, whatever the hour.
        for hours in [0.0, 5, 9, 13] {
            let given = at(9, 0).addingTimeInterval(-hours * 3600)
            for ebl in [0.0, 2000] {
                var r = adult()
                r.fluids["ebl"] = ebl
                r.timers.antibiotics = [recordOnly("cefazolin", doses: [TimedEntry(time: given, ebl: 0)]),
                                        recordOnly("vancomycin", doses: [TimedEntry(time: given, ebl: 0, given: "1 g")])]
                XCTAssertTrue(CaseTimerEngine.reminders(r.timers, record: r, data: d).isEmpty, "\(hours) h, EBL \(ebl)")
                // The notifications and the lock-screen activity read the schedule; the running list and the strip read the engine.
                XCTAssertTrue(CaseTimerSchedule.items([(id: UUID(), label: "OR 12", record: r)], data: d).isEmpty, "\(hours) h, EBL \(ebl)")
                // The same doses on timed courses DO make them (what the test would miss without the change).
                r.timers.antibiotics = r.timers.antibiotics.map { c in var t = c; t.reminders = true; return t }
                let timed = CaseTimerEngine.reminders(r.timers, record: r, data: d)
                XCTAssertNotNil(timed.first { $0.id == "antibiotic.cefazolin" }, "\(hours) h")
                XCTAssertNotNil(timed.first { $0.id == "longCase.vancomycin" }, "\(hours) h")
                if ebl >= 1500 { XCTAssertNotNil(timed.first { $0.id == "bloodLoss.cefazolin" }, "\(hours) h") }
            }
        }
    }

    func testARecordedOnlyCourseKeepsItsDosesAndTypedDoses() throws {
        var r = adult()
        r.timers.antibiotics = [recordOnly("cefazolin", doses: [TimedEntry(time: at(8, 12), ebl: 0, given: "2 g"), TimedEntry(time: at(12, 30), ebl: 0)])]
        XCTAssertEqual(r.timers.course("cefazolin")?.doses.map(\.given), ["2 g", nil])
        XCTAssertEqual(r.timers.course("cefazolin")?.last?.time, at(12, 30))
        XCTAssertFalse(r.timers.isEmpty)
        XCTAssertTrue(CaseTimerEngine.reminders(r.timers, record: r, data: try data()).isEmpty)
    }

    func testTheSwitchMakesItAnOrdinaryTimedCourseAtTheDefaultIntervalFromTheLastDose() throws {
        let d = try data()
        var t = CaseTimers()
        var c = recordOnly("cefazolin", doses: [TimedEntry(time: at(8, 0), ebl: 0), TimedEntry(time: at(8, 30), ebl: 0)])
        c.everyMinutes = 180
        t.antibiotics = [c]
        t.snoozes["antibiotic.cefazolin"] = ReminderSnooze(due: at(12, 30), until: at(13, 0))
        t.setAntibioticReminders(true, drug: "cefazolin", hasInterval: true)
        XCTAssertEqual(t.antibiotics[0].reminders, true)
        XCTAssertNil(t.antibiotics[0].everyMinutes, "the drug's default interval")
        XCTAssertNil(t.snoozes["antibiotic.cefazolin"])
        let rem = try XCTUnwrap(CaseTimerEngine.reminders(t, record: adult(), data: d).first { $0.id == "antibiotic.cefazolin" })
        XCTAssertEqual(rem.due, at(12, 30), "four hours from the LAST dose")
        // Already past: it shows overdue at once, as any course would.
        XCTAssertEqual(rem.state(at: at(13, 0)), .overdue)
        // Off again: recorded only, the doses stay.
        t.setAntibioticReminders(false, drug: "cefazolin", hasInterval: true)
        XCTAssertEqual(t.antibiotics[0].reminders, false)
        XCTAssertEqual(t.antibiotics[0].doses.count, 2)
        XCTAssertTrue(CaseTimerEngine.reminders(t, record: adult(), data: d).isEmpty)
    }

    func testTheSwitchCannotBeTurnedOnForADrugWithNoIntervalOnFile() throws {
        var t = CaseTimers()
        t.antibiotics = [recordOnly("vancomycin", doses: [TimedEntry(time: at(8, 0), given: "1 g")])]
        t.setAntibioticReminders(true, drug: "vancomycin", hasInterval: false)
        XCTAssertEqual(t.antibiotics[0].reminders, false)
        XCTAssertFalse(IntraopAntibiotic.hasInterval("vancomycin", in: try data()))
        XCTAssertFalse(IntraopAntibiotic.hasInterval("daptomycin", in: try data()), "a typed drug has none")
        XCTAssertTrue(IntraopAntibiotic.hasInterval("cefazolin", in: try data()))
        XCTAssertEqual(IntraopAntibiotic.noIntervalNote, "No redose interval on file")
        // And one that is on can still be turned off.
        t.antibiotics[0].reminders = true
        t.setAntibioticReminders(false, drug: "vancomycin", hasInterval: false)
        XCTAssertEqual(t.antibiotics[0].reminders, false)
    }

    @MainActor func testACourseStartedInCaseTimersIsStillTimed() throws {
        // Case Timers' own Start makes AntibioticCourse(drug:doses:everyMinutes:): the reminders it always had.
        let c = AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: at(8, 0))], everyMinutes: 240)
        XCTAssertTrue(c.reminders)
        var t = CaseTimers()
        t.antibiotics = [c]
        XCTAssertNotNil(CaseTimerEngine.reminders(t, record: adult(), data: try data()).first { $0.id == "antibiotic.cefazolin" })
        XCTAssertEqual(CaseTimersView.antibioticDetail([c, recordOnly("vancomycin", doses: [TimedEntry(time: at(8, 0))])]), "1 running · 1 recorded")
        XCTAssertEqual(CaseTimersView.antibioticDetail([c]), "1 running")
        XCTAssertEqual(CaseTimersView.antibioticDetail([recordOnly("vancomycin", doses: [])]), "1 recorded")
        XCTAssertNil(CaseTimersView.antibioticDetail([]))
    }

    func testTheStripOnTheTabShowsOnlyForSomethingThatCanRunATimer() {
        var t = CaseTimers()
        XCTAssertFalse(t.hasTimers)
        t.antibiotics = [recordOnly("cefazolin", doses: [TimedEntry(time: at(8, 0))])]
        XCTAssertFalse(t.hasTimers, "an antibiotic recorded only puts no card on the tab")
        var h = course()
        h.logDose(units: 26000, at: at(8, 10), now: at(8, 10))
        t.heparin = h
        XCTAssertFalse(t.hasTimers, "heparin doses alone neither")
        XCTAssertTrue(h.isRecordOnly)
        // Anything more is the case timers' user: a timed antibiotic, an ACT, protamine, the switch, a lab check, a saved (build 39) bolus.
        var timed = t; timed.antibiotics[0].reminders = true
        XCTAssertTrue(timed.hasTimers)
        var act = t; act.heparin?.logACT(seconds: 520, at: at(8, 20), kind: .act)
        XCTAssertTrue(act.hasTimers)
        var on = t; on.heparin?.setReminder(true, now: at(8, 30))
        XCTAssertTrue(on.hasTimers)
        var check = t; check.checks["glucose"] = LabCheckCourse(every: 30, started: at(8, 0))
        XCTAssertTrue(check.hasTimers)
        var legacy = t; legacy.heparin?.actOff = false
        XCTAssertTrue(legacy.hasTimers, "a case saved before 1.12 had its timer started by the bolus")
    }

    // MARK: The lines: tab row, page, handoff

    func testARecordedOnlyLineSaysGivenAndNeverNextDueOrNoRoutineRedose() throws {
        let d = try data()
        var r = adult()
        r.timers.antibiotics = [recordOnly("cefazolin", doses: [TimedEntry(time: at(8, 12), ebl: 0, given: "2 g")])]
        let l = try XCTUnwrap(CaseAntibiotics.lines(r, data: d, now: at(9, 0)).first)
        XCTAssertEqual(l.tabText, "Cefazolin 2 g · given 08:12")
        XCTAssertEqual(l.handoffText, "Cefazolin 2 g, given 08:12")
        XCTAssertTrue(l.recordOnly)
        XCTAssertNil(l.next); XCTAssertFalse(l.overdue)
        // Not overdue however late it is, and never "next due" / "no routine redose".
        let late = try XCTUnwrap(CaseAntibiotics.lines(r, data: d, now: at(22, 0)).first)
        XCTAssertFalse(late.overdue)
        XCTAssertFalse(late.tabText.contains("next due")); XCTAssertFalse(late.tabText.contains("no routine redose"))
        // A drug with no interval (vancomycin): the same, not the timed drug's "no routine redose".
        r.timers.antibiotics = [recordOnly("vancomycin", doses: [TimedEntry(time: at(8, 10), given: "1 g")])]
        XCTAssertEqual(CaseAntibiotics.lines(r, data: d, now: at(9, 0))[0].tabText, "Vancomycin 1 g · given 08:10")
        // The same course timed is the line it always was.
        r.timers.antibiotics = [AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: at(8, 10), given: "1 g")])]
        XCTAssertEqual(CaseAntibiotics.lines(r, data: d, now: at(9, 0))[0].tabText, "Vancomycin 1 g · last 08:10 · no routine redose")
    }

    func testSeveralRecordedDosesTellEveryTimeAndNoDoseIsInventedWhenNoneWasTyped() throws {
        let d = try data()
        var r = adult()
        r.timers.antibiotics = [recordOnly("cefazolin", doses: [TimedEntry(time: at(12, 30), given: "2 g"), TimedEntry(time: at(8, 12), given: "2 g")])]
        let l = try XCTUnwrap(CaseAntibiotics.lines(r, data: d, now: at(13, 0)).first)
        XCTAssertEqual(l.tabText, "Cefazolin 2 g · given 08:12, 12:30", "oldest first, each time")
        XCTAssertEqual(l.handoffText, "Cefazolin 2 g, given 08:12, 12:30")
        // No dose typed: the dose Case Timers would compute (2 g) was not given, so none is stated; a timed course keeps stating it.
        r.timers.antibiotics = [recordOnly("cefazolin", doses: [TimedEntry(time: at(8, 12))])]
        XCTAssertEqual(CaseAntibiotics.lines(r, data: d, now: at(9, 0))[0].tabText, "Cefazolin · given 08:12")
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: at(8, 12))])]
        XCTAssertEqual(CaseAntibiotics.lines(r, data: d, now: at(9, 0))[0].tabText, "Cefazolin 2 g · last 08:12 · next due 12:12")
        // A dose on another day carries its date, as every time in the summaries does.
        r.timers.antibiotics = [recordOnly("cefazolin", doses: [TimedEntry(time: at(23, 50, day: 11), given: "2 g")])]
        XCTAssertEqual(CaseAntibiotics.lines(r, data: d, now: at(9, 0))[0].tabText, "Cefazolin 2 g · given 11/11/26 23:50")
    }

    @MainActor func testTheTabRowAndTheHandoffListARecordedCourseAndTheTimedOneBesideIt() throws {
        let d = try data()
        var r = adult()
        r.setProcedures(PlannedProcedure.parse("CABG x3"))
        r.timers.antibiotics = [recordOnly("cefazolin", doses: [TimedEntry(time: at(8, 12), given: "2 g")]),
                                AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: at(8, 20), given: "1 g")])]
        let lines = IntraopNotableMedicationLink.lines(r, antibiotics: CaseAntibiotics.lines(r, data: d, now: at(9, 0)), now: at(9, 0))
        XCTAssertEqual(lines.map(\.text), ["Cefazolin 2 g · given 08:12", "Vancomycin 1 g · last 08:20 · no routine redose"])
        let b = try XCTUnwrap(PatientBriefs.handoff(r, now: at(9, 0)).first { $0.key == "infusions" })
        XCTAssertTrue(b.lines.contains("Antibiotics: Cefazolin 2 g, given 08:12; Vancomycin 1 g, last 08:20, no routine redose"), "\(b.lines)")
    }

    @MainActor func testLastDoseTextInCaseTimersTellsATypedDoseOfARecordedCourseAlways() {
        let last = TimedEntry(time: at(8, 10), given: "2 g")
        XCTAssertEqual(CaseTimersView.lastDoseText(last: last, every: nil, computed: "2 g", recordOnly: true), "Last dose 08:10 · given: 2 g")
        XCTAssertEqual(CaseTimersView.lastDoseText(last: last, every: 240, computed: "2 g"), "Last dose 08:10 · next 12:10", "timed: only where it says more")
        XCTAssertEqual(CaseTimersView.lastDoseText(last: TimedEntry(time: at(8, 10)), every: nil, computed: "2 g", recordOnly: true), "Last dose 08:10")
    }

    // MARK: The page's own entry

    func testPlusAntibioticRecordsWithNoTimerByDefault() throws {
        let d = try data()
        var r = adult()
        r.fluids["ebl"] = 300
        IntraopAntibiotic.record(.init(drug: "cefazolin", given: "2 g", time: at(8, 10), reminder: false), in: &r, data: d)
        let c = try XCTUnwrap(r.timers.course("cefazolin"))
        XCTAssertTrue(c.recordOnly)
        XCTAssertNil(c.everyMinutes)
        XCTAssertEqual(c.doses.count, 1)
        XCTAssertEqual(c.doses[0].time, at(8, 10)); XCTAssertEqual(c.doses[0].given, "2 g"); XCTAssertEqual(c.doses[0].ebl, 300)
        XCTAssertTrue(CaseTimerEngine.reminders(r.timers, record: r, data: d).isEmpty)
    }

    func testTheDoseIsOptionalAndKeptAsTypedNeverComputedOrConverted() throws {
        let d = try data()
        var r = adult()
        IntraopAntibiotic.record(.init(drug: "cefazolin", given: "", time: at(8, 10), reminder: false), in: &r, data: d)
        XCTAssertNil(r.timers.course("cefazolin")?.doses[0].given, "left empty: nothing is filled in from Case Timers' 2 g")
        IntraopAntibiotic.record(.init(drug: "vancomycin", given: "  1,230 mg  ", time: at(8, 10), reminder: false), in: &r, data: d)
        XCTAssertEqual(r.timers.course("vancomycin")?.doses[0].given, "1,230 mg", "trimmed, nothing more")
        IntraopAntibiotic.record(.init(drug: "vancomycin", given: "15 mg/kg", time: at(14, 10), reminder: false), in: &r, data: d)
        XCTAssertEqual(r.timers.course("vancomycin")?.doses.map(\.given), ["1,230 mg", "15 mg/kg"])
    }

    func testTheReminderSwitchOnStartsATimedCourseOnlyForADrugWithAnInterval() throws {
        let d = try data()
        var r = adult()
        IntraopAntibiotic.record(.init(drug: "cefazolin", given: "2 g", time: at(8, 10), reminder: true), in: &r, data: d)
        XCTAssertEqual(r.timers.course("cefazolin")?.reminders, true)
        XCTAssertEqual(CaseTimerEngine.reminders(r.timers, record: r, data: d).first { $0.id == "antibiotic.cefazolin" }?.due, at(12, 10))
        // Vancomycin has no interval: the switch is disabled in the view, and the model records only even if it were on.
        IntraopAntibiotic.record(.init(drug: "vancomycin", given: "1 g", time: at(8, 10), reminder: true), in: &r, data: d)
        XCTAssertEqual(r.timers.course("vancomycin")?.reminders, false)
        XCTAssertNil(CaseTimerEngine.reminders(r.timers, record: r, data: d).first { $0.ref == "vancomycin" })
    }

    func testAnOtherNameIsATypedDrugRecordedOnlyAndAListedBrandIsThatDrug() throws {
        let d = try data()
        var r = adult()
        IntraopAntibiotic.record(.init(drug: "Daptomycin", given: "6 mg/kg", time: at(8, 10), reminder: true), in: &r, data: d)
        let c = try XCTUnwrap(r.timers.course("daptomycin"))
        XCTAssertTrue(c.recordOnly, "a typed drug has no interval, whatever the switch says")
        let l = try XCTUnwrap(CaseAntibiotics.lines(r, data: d, now: at(9, 0)).first)
        XCTAssertEqual(l.tabText, "Daptomycin 6 mg/kg · given 08:10")
        XCTAssertTrue(CaseTimerEngine.reminders(r.timers, record: r, data: d).isEmpty)
        IntraopAntibiotic.record(.init(drug: "  Ancef ", given: "2 g", time: at(8, 12), reminder: false), in: &r, data: d)
        XCTAssertNotNil(r.timers.course("cefazolin"), "a name Case Timers' list knows is that drug")
        XCTAssertEqual(IntraopAntibiotic.courseID("cefazolin", in: d), "cefazolin")
        XCTAssertEqual(IntraopAntibiotic.courseID("Some  New   Drug", in: d), "some new drug")
        IntraopAntibiotic.record(.init(drug: "   ", given: "1 g", time: at(8, 12), reminder: false), in: &r, data: d)
        XCTAssertEqual(r.timers.antibiotics.count, 2, "no name: nothing recorded")
    }

    func testASecondDoseOfADrugAlreadyRecordedIsAddedToItsCourse() throws {
        let d = try data()
        var r = adult()
        IntraopAntibiotic.record(.init(drug: "cefazolin", given: "2 g", time: at(8, 10), reminder: false), in: &r, data: d)
        IntraopAntibiotic.record(.init(drug: "cefazolin", given: "2 g", time: at(12, 15), reminder: false), in: &r, data: d)
        XCTAssertEqual(r.timers.antibiotics.count, 1)
        XCTAssertEqual(r.timers.course("cefazolin")?.doses.map(\.time), [at(8, 10), at(12, 15)])
        XCTAssertEqual(r.timers.course("cefazolin")?.reminders, false)
        // A timed course stays timed when a recorded dose is added with the switch off, and its redose moves.
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: at(8, 10))])]
        IntraopAntibiotic.record(.init(drug: "cefazolin", given: "2 g", time: at(12, 15), reminder: false), in: &r, data: d)
        XCTAssertEqual(r.timers.course("cefazolin")?.reminders, true)
        XCTAssertEqual(CaseTimerEngine.reminders(r.timers, record: r, data: d).first { $0.id == "antibiotic.cefazolin" }?.due, at(16, 15))
        // A recorded course turned on by the switch on a later dose.
        r.timers.antibiotics = [recordOnly("cefazolin", doses: [TimedEntry(time: at(8, 10))])]
        IntraopAntibiotic.record(.init(drug: "cefazolin", given: nil, time: at(12, 15), reminder: true), in: &r, data: d)
        XCTAssertEqual(r.timers.course("cefazolin")?.reminders, true)
    }

    @MainActor func testThePageLinkAndItsGroupFollowCaseTimersGate() {
        XCTAssertEqual(IntraopMedicationsPage.antibioticsTitle, "Antibiotics")
        XCTAssertTrue(IntraopMedicationsPage.antibioticsNote.contains("No timer runs unless you turn the redose reminder on"))
        XCTAssertEqual(IntraopAntibiotic.pageLink(hasAntibiotics: false, caseTimersShown: true), "+ Antibiotic")
        XCTAssertEqual(IntraopAntibiotic.pageLink(hasAntibiotics: true, caseTimersShown: true), "+ Antibiotic or redose")
        XCTAssertNil(IntraopAntibiotic.pageLink(hasAntibiotics: true, caseTimersShown: false))
        XCTAssertEqual(IntraopAntibiotic.openCaseTimersLink, "Open Case Timers")
        XCTAssertEqual(IntraopAntibiotic.reminderTitle, "Redose reminder")
    }

    @MainActor func testOneUndoStepPerAddAndPerSwitch() throws {
        let d = try data()
        let store = PatientStore(url: nil)
        store.update(discrete: true, now: Date(timeIntervalSince1970: 1000)) { $0.weightKg = 82; $0.ageYears = 67 }
        var states = [store.record]
        func step(_ change: (inout PatientRecord) -> Void) {
            store.update(discrete: true, now: Date(timeIntervalSince1970: 1000 + Double(states.count))) { change(&$0) }
            states.append(store.record)
        }
        step { IntraopAntibiotic.record(.init(drug: "cefazolin", given: "2 g", time: self.at(8, 10), reminder: false), in: &$0, data: d) }
        step { IntraopAntibiotic.setReminders(true, drug: "cefazolin", in: &$0, data: d) }
        step { IntraopAntibiotic.setReminders(false, drug: "cefazolin", in: &$0, data: d) }
        step { IntraopHeparin.record(units: 26000, at: self.at(8, 15), in: &$0) }
        XCTAssertEqual(states.count, 5)
        XCTAssertEqual(store.record.timers.course("cefazolin")?.reminders, false)
        for expected in states.dropLast().reversed() {
            store.undo()
            XCTAssertEqual(store.record, expected)
        }
        XCTAssertTrue(store.record.timers.isEmpty)
    }

    // MARK: 2. The bar records only, and offers the timer

    func testTheBarFilesATypedDoseAsRecordedOnlyWithTheLabelSayingSo() throws {
        let d = try data()
        let dose = try XCTUnwrap(abxDoses(read("vanc 1 g at 0810")).first)
        XCTAssertEqual(IntraopAntibiotic.label(dose, record: adult(), data: d, now: now), "Vancomycin 1 g: recorded at 08:10")
        let cef = try XCTUnwrap(abxDoses(read("cefazolin 2 g at 0810")).first)
        XCTAssertEqual(IntraopAntibiotic.label(cef, record: adult(), data: d, now: now), "Cefazolin 2 g: recorded at 08:10")
        for l in ["Vancomycin 1 g: recorded at 08:10", "Cefazolin 2 g: recorded at 08:10"] { XCTAssertFalse(l.contains("Case Timers") || l.contains("next due")) }
        // Filed: no timer.
        let r = filed("vanc 1 g at 0810", into: adult())
        XCTAssertEqual(r.timers.course("vancomycin")?.reminders, false)
        XCTAssertTrue(CaseTimerEngine.reminders(r.timers, record: r, data: d).isEmpty)
    }

    func testTheReviewOffersTheTimerAsASecondChipThatIsOffUntilChosen() throws {
        let q = read("cefazolin 2 g at 0810")
        let chips = QuickAdd.chips(q, record: adult())
        XCTAssertEqual(chips.count, 2)
        XCTAssertEqual(chips[0].text, "Intraop · Cefazolin 2 g: recorded at 08:10")
        XCTAssertFalse(chips[0].offByDefault)
        XCTAssertEqual(chips[1].text, "Intraop · Also start the redose reminder (every 4 h, next due 12:10)")
        XCTAssertTrue(chips[1].offByDefault)
        XCTAssertTrue(chips[1].canAdd)
        XCTAssertEqual(QuickAdd.offByDefault(chips), [chips[1].id])
        // Off by default: only the dose is filed.
        let off = QuickAdd.changes(chips, dropped: QuickAdd.offByDefault(chips))
        XCTAssertEqual(off.count, 1)
        var r = adult()
        PatientNote.apply(off, to: &r)
        XCTAssertEqual(r.timers.course("cefazolin")?.reminders, false)
        XCTAssertTrue(CaseTimerEngine.reminders(r.timers, record: r, data: try data()).isEmpty)
        // Chosen (not left out): the dose, then that course's reminders on, from the dose.
        let on = QuickAdd.changes(chips, dropped: [])
        XCTAssertEqual(on.count, 2)
        var t = adult()
        PatientNote.apply(on, to: &t)
        XCTAssertEqual(t.timers.course("cefazolin")?.reminders, true)
        XCTAssertNil(t.timers.course("cefazolin")?.everyMinutes)
        XCTAssertEqual(CaseTimerEngine.reminders(t.timers, record: t, data: try data()).first { $0.id == "antibiotic.cefazolin" }?.due, at(12, 10))
    }

    func testEveryOtherChipIsOnByDefault() {
        // The general mechanism changes nothing for a line without an optional choice.
        for line in ["vanc 1 g at 0810", "norepi 0.05, PRBC 2, EBL 500", "heparin 26000 at 0810", "extubated, to PACU"] {
            let chips = QuickAdd.chips(read(line), record: adult())
            XCTAssertFalse(chips.isEmpty, line)
            XCTAssertTrue(QuickAdd.offByDefault(chips).isEmpty, line)
        }
    }

    func testTheOfferIsNotMadeForADrugWithNoIntervalAChildOrACourseAlreadyTimed() throws {
        let d = try data()
        XCTAssertEqual(QuickAdd.chips(read("vanc 1 g at 0810"), record: adult()).count, 1, "no interval to offer")
        XCTAssertEqual(QuickAdd.chips(read("cefazolin 2 g at 0810", record: child()), record: child()).count, 1, "a child has no antibiotic card to run it")
        // Already timed: the dose is appended, the timer moves as today, and the label says "next due".
        var timed = adult()
        timed.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: at(8, 0))])]
        let q = read("redose cefazolin at 1205", record: timed, at: at(12, 6))
        let chips = QuickAdd.chips(q, record: timed)
        XCTAssertEqual(chips.count, 1)
        XCTAssertEqual(chips[0].text, "Intraop · Cefazolin: redose logged in Case Timers at 12:05, next due 16:05")
        var r = timed
        PatientNote.apply(QuickAdd.changes(chips), to: &r)
        XCTAssertEqual(r.timers.course("cefazolin")?.reminders, true)
        XCTAssertEqual(CaseTimerEngine.reminders(r.timers, record: r, data: d).first { $0.id == "antibiotic.cefazolin" }?.due, at(16, 5))
        // A recorded-only course typed again: still recorded only, the offer is made.
        var rec = adult()
        rec.timers.antibiotics = [recordOnly("cefazolin", doses: [TimedEntry(time: at(8, 0))])]
        let again = QuickAdd.chips(read("redose cefazolin at 1205", record: rec, at: at(12, 6)), record: rec)
        XCTAssertEqual(again.map(\.text), ["Intraop · Cefazolin: redose recorded at 12:05",
                                          "Intraop · Also start the redose reminder (every 4 h, next due 16:05)"])
    }

    func testTheOptionalChipNeedsItsDoseAndOneOfferIsMadePerDrug() throws {
        let q = read("cefazolin 2 g at 0810")
        let chips = QuickAdd.chips(q, record: adult())
        // Dose chip left out, no course to turn on: the offer has nothing to start.
        let withoutDose = QuickAdd.chips(q, record: adult(), dropped: [chips[0].id])
        XCTAssertEqual(withoutDose[1].status, .conflicts("needs the dose"))
        XCTAssertFalse(withoutDose[1].canAdd)
        XCTAssertTrue(QuickAdd.changes(withoutDose, dropped: [chips[0].id]).isEmpty)
        // A course that exists (recorded only): the offer stands without the dose chip.
        var rec = adult()
        rec.timers.antibiotics = [recordOnly("cefazolin", doses: [TimedEntry(time: at(7, 0))])]
        let qr = read("cefazolin 2 g at 0810", record: rec)
        let cr = QuickAdd.chips(qr, record: rec)
        let alone = QuickAdd.chips(qr, record: rec, dropped: [cr[0].id])
        XCTAssertTrue(alone[1].canAdd)
        // Two doses of one drug in one line: one offer, from the later dose.
        let two = QuickAdd.chips(read("cefazolin 2 g at 0600, cefazolin 2 g at 0810"), record: adult())
        XCTAssertEqual(two.filter(\.offByDefault).count, 1)
        XCTAssertTrue(try XCTUnwrap(two.last).text.hasSuffix("next due 12:10)"), two.last?.text ?? "")
    }

    func testTheOptionalChipIdIsTheSameFromOneMinuteToTheNext() {
        let a = QuickAdd.chips(read("cefazolin 2 g", at: at(9, 30)), record: adult())
        let b = QuickAdd.chips(read("cefazolin 2 g", at: at(9, 31)), record: adult())
        XCTAssertEqual(a.map(\.id), b.map(\.id), "Add re-reads the line later and must find the chips it showed")
        XCTAssertNotEqual(a[1].text, b[1].text, "the next-due time follows the dose")
    }

    func testNotificationsAreAskedForOnlyWhenAReminderIsTurnedOn() throws {
        let before = adult()
        let recorded = QuickAdd.changes(QuickAdd.chips(read("cefazolin 2 g at 0810"), record: before), dropped: QuickAdd.offByDefault(QuickAdd.chips(read("cefazolin 2 g at 0810"), record: before)))
        XCTAssertFalse(IntraopAntibiotic.startsReminder(recorded, before: before), "recorded only: no reminder, no permission request")
        let chosen = QuickAdd.changes(QuickAdd.chips(read("cefazolin 2 g at 0810"), record: before))
        XCTAssertTrue(IntraopAntibiotic.startsReminder(chosen, before: before), "the optional chip")
        var timed = adult()
        timed.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: at(8, 0))])]
        let redose = QuickAdd.changes(QuickAdd.chips(read("redose cefazolin at 1205", record: timed, at: at(12, 6)), record: timed))
        XCTAssertTrue(IntraopAntibiotic.startsReminder(redose, before: timed), "a redose moves a running reminder")
        XCTAssertFalse(IntraopAntibiotic.startsReminder(QuickAdd.changes(QuickAdd.chips(read("heparin 26000"), record: before)), before: before), "heparin starts none")
    }

    // MARK: 3. Heparin: one log, the ACT reminder off unless switched on

    private func course(purpose: String = "bypass", goal: Double? = 480) -> HeparinCourse {
        HeparinCourse(purpose: purpose, goal: goal, actEvery: 30)
    }

    func testNoDoseTurnsTheACTReminderOnTheFirstIncluded() {
        var h = course()
        h.logDose(units: 26000, at: at(8, 10), now: at(8, 10))
        XCTAssertFalse(h.actRunning)
        XCTAssertNil(CaseTimerEngine.actDue(h))
        h.logDose(units: 5000, at: at(8, 46), now: at(8, 46))
        XCTAssertFalse(h.actRunning, "a later dose neither")
        XCTAssertNil(CaseTimerEngine.actDue(h))
        // Only the switch turns it on, counting from the last ACT sample as before.
        h.logACT(seconds: 520, at: at(8, 50), kind: .act)
        h.setReminder(true, now: at(8, 55))
        XCTAssertTrue(h.actRunning)
        XCTAssertEqual(CaseTimerEngine.actDue(h), at(9, 25))
        h.setReminder(false, now: at(9, 0))
        h.logDose(units: 3000, at: at(9, 5), now: at(9, 5))
        XCTAssertFalse(h.actRunning)
    }

    func testAnACTBeforeAnyDoseStillDoesNotStartItAndTheSwitchBeforeTheFirstDoseIsKept() {
        var h = course()
        h.logACT(seconds: 128, at: at(8, 0), kind: .act)
        h.logDose(units: 26000, at: at(8, 10), now: at(8, 10))
        XCTAssertFalse(h.actRunning)
        var on = course()
        on.setReminder(true, now: at(7, 0))
        on.logDose(units: 26000, at: at(8, 5), now: at(8, 5))
        XCTAssertTrue(on.actRunning, "switched on before the first dose: it stays on")
        XCTAssertEqual(on.actStart, at(7, 0))
    }

    func testACourseSavedByBuild39KeepsTheStateItHadAndSoDoesOneSavedByTheSwitchBuild() throws {
        let ref = at(8, 0).timeIntervalSinceReferenceDate
        func entry(_ minutes: Double, _ value: Double) -> [String: Any] { ["id": UUID().uuidString, "time": ref + minutes * 60, "value": value] }
        // Build 39: a bolus started the timer; nothing was stamped.
        let old: [String: Any] = ["purpose": "bypass", "goal": 480, "actEvery": 30, "doses": [entry(10, 26000)], "acts": [entry(20, 512)]]
        var h = try JSONDecoder().decode(HeparinCourse.self, from: try JSONSerialization.data(withJSONObject: old))
        XCTAssertTrue(h.actRunning, "it ran from the bolus, and still does")
        h.logDose(units: 5000, at: at(8, 46), now: at(8, 46))
        XCTAssertTrue(h.actRunning, "a later dose does not change it")
        // The build in between: a first dose stamped the switch.
        var stamped = old
        stamped["actStart"] = ref + 11 * 60
        let s = try JSONDecoder().decode(HeparinCourse.self, from: try JSONSerialization.data(withJSONObject: stamped))
        XCTAssertTrue(s.actRunning)
        XCTAssertEqual(s.actStart, at(8, 11))
        // A switched-off course reads off.
        var offJSON = old
        offJSON["actOff"] = true
        XCTAssertFalse(try JSONDecoder().decode(HeparinCourse.self, from: try JSONSerialization.data(withJSONObject: offJSON)).actRunning)
        // A course the new rule saved: off, with a dose in it, reads back off.
        var fresh = course()
        fresh.logDose(units: 26000, at: at(8, 10), now: at(8, 10))
        let again = try JSONDecoder().decode(HeparinCourse.self, from: try JSONEncoder().encode(fresh))
        XCTAssertFalse(again.actRunning)
        XCTAssertEqual(again, fresh)
    }

    func testPlusHeparinCreatesTheCourseWithThePurposeNotChosenNoGoalAndTheReminderOff() throws {
        let d = try data()
        var r = adult()
        XCTAssertNil(r.timers.heparin)
        IntraopHeparin.record(units: 26000, at: at(8, 10), in: &r)
        let h = try XCTUnwrap(r.timers.heparin)
        XCTAssertEqual(h.purpose, "other", "the existing Other: Case Timers makes no course without a purpose")
        XCTAssertNotNil(d.purpose(h.purpose))
        XCTAssertNil(h.goal)
        XCTAssertFalse(h.actRunning)
        XCTAssertEqual(h.doses.map(\.value), [26000])
        XCTAssertEqual(h.doses.map(\.time), [at(8, 10)])
        XCTAssertNil(CaseTimerEngine.reminders(r.timers, record: r, data: d).first { $0.kind == .act })
        // It appends to a course that exists, whatever its purpose, and leaves its goal, purpose and switch alone.
        var withCourse = adult()
        withCourse.timers.heparin = course()
        withCourse.timers.heparin?.setReminder(true, now: at(7, 50))
        IntraopHeparin.record(units: 5000, at: at(8, 46), in: &withCourse)
        XCTAssertEqual(withCourse.timers.heparin?.purpose, "bypass")
        XCTAssertEqual(withCourse.timers.heparin?.goal, 480)
        XCTAssertEqual(withCourse.timers.heparin?.doses.map(\.value), [5000])
        XCTAssertEqual(withCourse.timers.heparin?.actRunning, true, "a switch the user turned on stays on")
    }

    func testThePagesDoseIsCheckedAsCaseTimersChecksItAndABlockedDoseIsRefused() throws {
        let d = try data()
        // Plausible: nothing.
        XCTAssertTrue(IntraopHeparin.pageIssues(units: 26000, time: at(8, 10), record: adult(), data: d).isEmpty)
        // No weight: blocked, as in Case Timers.
        var noWeight = adult(); noWeight.weightKg = nil
        XCTAssertTrue(IntraopHeparin.pageIssues(units: 26000, time: at(8, 10), record: noWeight, data: d).blocks)
        // A child: blocked.
        XCTAssertTrue(IntraopHeparin.pageIssues(units: 3000, time: at(8, 10), record: child(), data: d).blocks)
        // No value: blocked. A time in the future (nil): blocked with the app's sentence.
        XCTAssertTrue(IntraopHeparin.pageIssues(units: nil, time: at(8, 10), record: adult(), data: d).blocks)
        let future = IntraopHeparin.pageIssues(units: 26000, time: nil, record: adult(), data: d)
        XCTAssertTrue(future.blocks)
        XCTAssertTrue(future.contains { $0.text == "That time is in the future." })
        // A tiny number is asked about (a second tap), as Case Timers asks.
        XCTAssertTrue(IntraopHeparin.pageIssues(units: 26, time: at(8, 10), record: adult(), data: d).needsConfirm)
        // The course's own purpose decides the range check when there is one (3,000 U is under the bypass dose; 26,000 U is a
        // bypass-size dose for a vascular case). With no course there is no purpose to name: 26,000 U is not questioned.
        var bypass = adult()
        bypass.timers.heparin = course()
        XCTAssertTrue(IntraopHeparin.pageIssues(units: 3000, time: at(8, 10), record: bypass, data: d).needsConfirm)
        var vascular = adult()
        vascular.timers.heparin = course(purpose: "vascular", goal: nil)
        XCTAssertTrue(IntraopHeparin.pageIssues(units: 26000, time: at(8, 10), record: vascular, data: d).needsConfirm)
        // The time: default now, a picked clock time resolved, the future refused (the control the antibiotic entry shares).
        XCTAssertEqual(HeparinTimeline.resolved(picked: nil, now: now), now)
        XCTAssertNil(HeparinTimeline.resolved(picked: at(11, 0), now: now))
    }

    func testTheHeparinLineListsTheDosesTheirTimesAndTheTotal() {
        var r = adult()
        XCTAssertNil(CaseHeparin.text(r, now: at(10, 0)))
        r.timers.heparin = course()
        XCTAssertNil(CaseHeparin.text(r, now: at(10, 0)), "a course with no dose says nothing")
        r.timers.heparin?.logDose(units: 26000, at: at(8, 10), now: at(8, 10))
        XCTAssertEqual(CaseHeparin.text(r, now: at(10, 0)), "Heparin 26,000 U 08:10", "one dose: no total")
        r.timers.heparin?.logDose(units: 5000, at: at(8, 46), now: at(8, 46))
        XCTAssertEqual(CaseHeparin.text(r, now: at(10, 0)), "Heparin 26,000 U 08:10; 5,000 U 08:46 (31,000 U total)")
        // Time order, whatever the order logged; an ACT or protamine entry is not a dose.
        r.timers.heparin?.logDose(units: 1000, at: at(7, 55), now: at(9, 0))
        r.timers.heparin?.logACT(seconds: 520, at: at(8, 20), kind: .act)
        r.timers.heparin?.logProtamine(mg: 150, at: at(9, 40))
        XCTAssertEqual(CaseHeparin.text(r, now: at(10, 0)), "Heparin 1,000 U 07:55; 26,000 U 08:10; 5,000 U 08:46 (32,000 U total)")
        // Another day carries its date.
        r.timers.heparin?.doses = [TimedEntry(time: at(23, 50, day: 11), value: 26000)]
        XCTAssertEqual(CaseHeparin.text(r, now: at(10, 0)), "Heparin 26,000 U 11/11/26 23:50")
        // ACTs and protamine alone: nothing.
        r.timers.heparin?.doses = []
        XCTAssertNil(CaseHeparin.text(r, now: at(10, 0)))
    }

    @MainActor func testTheTabRowThePageAndTheHandoffListHeparinFromTheOneLogAndNoACTOrProtamine() throws {
        let d = try data()
        var r = adult()
        r.setProcedures(PlannedProcedure.parse("CABG x3"))
        r.timers.heparin = course()
        r.timers.heparin?.logDose(units: 26000, at: at(8, 10), now: at(8, 10))
        r.timers.heparin?.logDose(units: 5000, at: at(8, 46), now: at(8, 46))
        r.timers.heparin?.logACT(seconds: 520, at: at(8, 20), kind: .act)
        r.timers.heparin?.logProtamine(mg: 150, at: at(9, 40))
        let text = "Heparin 26,000 U 08:10; 5,000 U 08:46 (31,000 U total)"
        let row = IntraopNotableMedicationLink.lines(r, antibiotics: CaseAntibiotics.lines(r, data: d, now: at(10, 0)), now: at(10, 0))
        XCTAssertEqual(row.map(\.text), [text])
        let b = try XCTUnwrap(PatientBriefs.handoff(r, now: at(10, 0)).first { $0.key == "infusions" })
        XCTAssertTrue(b.lines.contains(text), "\(b.lines)")
        XCTAssertFalse(b.lines.joined(separator: "\n").contains("ACT"))
        XCTAssertFalse(b.lines.joined(separator: "\n").contains("rotamine"), "the handoff has never printed protamine")
        // Antibiotics first, then heparin, in the same block.
        r.timers.antibiotics = [recordOnly("cefazolin", doses: [TimedEntry(time: at(8, 5), given: "2 g")])]
        let both = try XCTUnwrap(PatientBriefs.handoff(r, now: at(10, 0)).first { $0.key == "infusions" })
        let lines = both.lines
        let a = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("Antibiotics: ") })
        let h = try XCTUnwrap(lines.firstIndex(of: text))
        XCTAssertLessThan(a, h)
    }

    // MARK: Typed heparin

    func testTypedHeparinFilesADoseInTheOneLogRecordedOnly() throws {
        let d = try data()
        XCTAssertEqual(hepDoses(read("heparin 26000")), [IntraopHeparinDose(units: 26000, time: now)])
        XCTAssertEqual(hepDoses(read("heparin 26,000 units at 0810")), [IntraopHeparinDose(units: 26000, time: at(8, 10))])
        XCTAssertEqual(hepDoses(read("5000 u heparin")), [IntraopHeparinDose(units: 5000, time: now)])
        XCTAssertEqual(hepDoses(read("heparin 5000 units")), [IntraopHeparinDose(units: 5000, time: now)])
        XCTAssertEqual(hepDoses(read("gave heparin 3000 u at 0846")), [IntraopHeparinDose(units: 3000, time: at(8, 46))])
        XCTAssertEqual(hepDoses(read("heparin bolus 26000, norepi 0.05")).first?.units, 26000)
        let f = try XCTUnwrap(read("heparin 26,000 units at 0810").findings.first)
        XCTAssertEqual(f.label, "Heparin 26,000 U: recorded at 08:10")
        XCTAssertEqual(QuickAdd.chips(read("heparin 26,000 units at 0810"), record: adult()).first?.text, "Intraop · Heparin 26,000 U: recorded at 08:10")
        // Filed in Case Timers' one log, the ACT reminder not touched (a new course: off).
        let r = filed("heparin 26,000 units at 0810", into: adult())
        let h = try XCTUnwrap(r.timers.heparin)
        XCTAssertEqual(h.doses.map(\.value), [26000])
        XCTAssertEqual(h.doses.map(\.time), [at(8, 10)])
        XCTAssertEqual(h.purpose, "other")
        XCTAssertFalse(h.actRunning)
        XCTAssertNil(CaseTimerEngine.reminders(r.timers, record: r, data: d).first { $0.kind == .act })
        // A course whose switch is on keeps it on and a second dose joins the log.
        var on = adult()
        on.timers.heparin = course()
        on.timers.heparin?.setReminder(true, now: at(7, 0))
        let two = filed("heparin 5000 at 0846", into: on)
        XCTAssertEqual(two.timers.heparin?.doses.map(\.value), [5000])
        XCTAssertEqual(two.timers.heparin?.actRunning, true)
        XCTAssertEqual(two.timers.heparin?.purpose, "bypass")
    }

    func testTheSameTypedDoseTwiceIsOneDoseAndTheBarOnlyReadsHeparinOnTheIntraoperativeSide() throws {
        let first = filed("heparin 26000 at 0810", into: adult())
        XCTAssertEqual(first.timers.heparin?.doses.count, 1)
        let chips = QuickAdd.chips(read("heparin 26000 at 0810", record: first), record: first)
        XCTAssertEqual(chips.first?.status, .recorded)
        XCTAssertTrue(QuickAdd.changes(chips).isEmpty)
        var r = first
        PatientNote.apply([.heparinDose(IntraopHeparinDose(units: 26000, time: at(8, 11)))], to: &r)
        XCTAssertEqual(r.timers.heparin?.doses.count, 1, "within two minutes, the same units")
        // Another amount at the same minute is another dose.
        XCTAssertEqual(QuickAdd.chips(read("heparin 5000 at 0810", record: first), record: first).first?.status, .new)
        // The Preoperative tab reads no such dose.
        XCTAssertTrue(hepDoses(read("heparin 26000 at 0810", tab: .preop)).isEmpty)
    }

    func testAnInfusionOrARateStaysWhatItWasAndIsNotADose() {
        for line in ["heparin gtt", "heparin gtt 1200 units/h", "heparin at 500 units/h", "heparin infusion", "heparin infusion at 1000 units/h",
                     "heparin 1200 units/h", "heparin 12 units/kg/h", "heparin 5000 u/hr", "heparin drip running", "heparin 300 U/kg"] {
            XCTAssertTrue(hepDoses(read(line)).isEmpty, line)
            XCTAssertFalse(read(line).findings.contains { if case .heparinDose = $0.change { return true }; return false }, line)
        }
        // And the drip keeps being read by the drip readers.
        XCTAssertFalse(read("heparin 1200 units/h").findings.isEmpty, "still read as the drip it is")
    }

    func testSubcutaneousAndProphylacticHeparinFilesNothingInTheLog() {
        for line in ["SQ heparin 5000", "heparin 5000 subq", "heparin 5000 SQ", "heparin 5000 sc", "heparin prophylaxis", "heparin ppx 5000",
                     "subcutaneous heparin 5000 units", "heparin 5000 units q8h", "heparin 5000 bid", "DVT prophylaxis heparin 5000", "enoxaparin 40"] {
            XCTAssertTrue(hepDoses(read(line)).isEmpty, line)
            let before = adult()
            var r = before
            PatientNote.apply(QuickAdd.changes(QuickAdd.chips(read(line), record: before)), to: &r)
            XCTAssertNil(r.timers.heparin, line)
        }
    }

    func testResistanceHITHeldNegatedPlannedAndFlushLinesFileNothing() {
        for line in ["heparin resistance", "HIT", "heparin-induced thrombocytopenia", "history of HIT, heparin 5000", "HIT: no heparin 5000", "no heparin", "heparin held",
                     "hold heparin", "heparin on hold", "will give heparin 5000", "plan heparin 26000", "going to give heparin 5000", "heparinized saline",
                     "heparin flush", "heparin lock", "heparin 100 units flush", "allergic to heparin", "heparin allergy", "allergies: heparin 5000",
                     "heparin level 0.3", "on heparin 5000", "post heparin ACT", "no heparin given", "didn't give heparin", "heparin not given",
                     "need heparin 26000", "heparin 26000?", "protamine 150", "ACT 480", "ACT 480 after heparin"] {
            XCTAssertTrue(hepDoses(read(line)).isEmpty, line)
        }
    }

    func testTheNumbersThatAreNotADoseAreNotRead() {
        // A time is not units, a handful is not a bolus, a number without units must be a plausible dose.
        for line in ["heparin 0810", "heparin at 0810", "heparin 5", "heparin 500", "heparin 5 mg", "heparin 1 ml", "heparin 300000"] {
            XCTAssertTrue(hepDoses(read(line)).isEmpty, line)
        }
        XCTAssertEqual(hepDoses(read("heparin 500 units")).first?.units, 500, "a labelled number may be small")
        // A time that is not a time of day, or a plan later today, files nothing.
        XCTAssertTrue(hepDoses(read("heparin 5000 at 2575")).isEmpty)
        XCTAssertTrue(hepDoses(read("heparin 5000 at 1500", at: at(9, 30))).isEmpty)
    }

    func testATypedHeparinDoseForAChildIsKeptAsTypedWithTheSameNoteTheAntibioticHas() throws {
        let f = try XCTUnwrap(read("heparin 3000 units", record: child()).findings.first)
        XCTAssertEqual(f.note, "Adult defaults only: not for children. The dose is recorded as typed.")
        XCTAssertNil(try XCTUnwrap(read("heparin 26000").findings.first).note)
    }

    @MainActor func testOneUndoStepRemovesATypedHeparinAndAnAntibioticTogether() throws {
        let store = PatientStore(url: nil)
        store.update(discrete: true, now: Date(timeIntervalSince1970: 1000)) { $0.weightKg = 82; $0.ageYears = 67 }
        let before = store.record
        let chips = QuickAdd.chips(read("heparin 26000 at 0810, cefazolin 2 g at 0805", record: before), record: before)
        XCTAssertEqual(chips.count, 3)
        let chosen = QuickAdd.changes(chips, dropped: QuickAdd.offByDefault(chips))
        store.update(discrete: true, now: Date(timeIntervalSince1970: 1000.3)) { PatientNote.apply(chosen, to: &$0) }
        XCTAssertEqual(store.record.timers.heparin?.doses.count, 1)
        XCTAssertEqual(store.record.timers.antibiotics.count, 1)
        XCTAssertTrue(store.isLatestStep(before: before, after: store.record))
        store.undo()
        XCTAssertEqual(store.record, before)
    }

    // MARK: 4. The link to the antibiotic reference card

    func testTheReferenceCardExistsAndTheLinkOpensItByTheExistingRoute() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        let b = try ReferenceLoader.decode(try Data(contentsOf: url))
        XCTAssertNotNil(b.quickrefs.first { $0.id == IntraopAntibiotic.referenceID })
        XCTAssertEqual(IntraopAntibiotic.referenceID, "ashp-surgical-prophylaxis")
        XCTAssertEqual(IntraopAntibiotic.referenceLink, "Which antibiotic?")
        // The page opens it through its host's onOpenRoute (a RefRoute key); the timers push the same route.
        XCTAssertEqual(RefRoute(key: "quickref:" + IntraopAntibiotic.referenceID), RefRoute.quickref("ashp-surgical-prophylaxis"))
        XCTAssertEqual(RefRoute.quickref(IntraopAntibiotic.referenceID).key, "quickref:ashp-surgical-prophylaxis")
    }

    @MainActor func testCaseTimersOpensAtTheHeparinSectionAsItDoesAtTheAntibioticCard() {
        let ui = CaseTimersUI.shared
        ui.open = false; ui.target = nil
        ui.openHeparin()
        XCTAssertTrue(ui.open)
        XCTAssertEqual(ui.target, "heparin.card")
        XCTAssertEqual(CaseTimersView.heparinCardID, "heparin.card")
        ui.open = false; ui.target = nil
        ui.openAntibiotic()
        XCTAssertEqual(ui.target, "antibiotic.card")
        ui.open = false; ui.target = nil
    }
}
