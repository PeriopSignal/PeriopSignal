import XCTest
@testable import PeriopSignal

/// 1.12 follow-up, helper R (Ben, Nov 13): "Have ability to change antibiotic dose in case timer." (1) The antibiotic's dose for the
/// case can be typed (one per antibiotic, used for the first dose and every redose, shown in the Intraoperative row, on the
/// Medications page and in the handoff, the worked-out dose kept as a hint). (2) The time of a dose already logged can be changed and
/// the redose countdown moves with it. Every test that depends on the clock passes its own `now`.
final class R112Tests: XCTestCase {

    private func at(_ hour: Int, _ minute: Int, day: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

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

    private func adult(_ kg: Double? = 82) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = kg
        return r
    }

    private func course(_ drug: String = "cefazolin", doses: [TimedEntry], dose: String? = nil, reminders: Bool = true,
                        every: Double? = nil) -> AntibioticCourse {
        AntibioticCourse(drug: drug, doses: doses, everyMinutes: every, reminders: reminders, dose: dose)
    }

    private func cefazolinReminder(_ t: CaseTimers, _ r: PatientRecord, kind: String = "antibiotic") throws -> CaseReminder? {
        CaseTimerEngine.reminders(t, record: r, data: try data()).first { $0.id == kind + ".cefazolin" }
    }

    // MARK: 1. The model: saved records, trimming, the cap

    func testABuild40CourseDecodesWithNoDoseAndWritesNoDoseKeyBack() throws {
        let json = """
        {"antibiotics":[{"drug":"cefazolin","doses":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","time":790000000,"ebl":100,"given":"1 g"}],"everyMinutes":240},
                        {"drug":"vancomycin","doses":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FE","time":790000000}],"reminders":false}]}
        """
        let t = try JSONDecoder().decode(CaseTimers.self, from: Data(json.utf8))
        XCTAssertEqual(t.antibiotics.map(\.dose), [nil, nil], "no key: the worked-out dose")
        XCTAssertEqual(t.antibiotics.map(\.reminders), [true, false], "the rest decodes as before")
        let out = try JSONEncoder().encode(t)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        for c in try XCTUnwrap(root["antibiotics"] as? [[String: Any]]) {
            XCTAssertNil(c["dose"], "a course with no dose written back has no dose key: \(c.keys.sorted())")
            XCTAssertNotNil(c["doses"])
        }
    }

    func testACourseWithADoseRoundTripsAndOnlyThenWritesTheKey() throws {
        var t = CaseTimers()
        t.antibiotics = [course(doses: [TimedEntry(time: at(8, 10), ebl: 0, given: "1 g")], dose: "3 g"),
                         course("vancomycin", doses: [TimedEntry(time: at(8, 20))], dose: "1.25 g", reminders: false)]
        let out = try JSONEncoder().encode(t)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        let written = try XCTUnwrap(root["antibiotics"] as? [[String: Any]])
        XCTAssertEqual(written.compactMap { $0["dose"] as? String }, ["3 g", "1.25 g"])
        XCTAssertEqual(written[1]["reminders"] as? Bool, false, "a recorded-only course keeps both keys")
        let back = try JSONDecoder().decode(CaseTimers.self, from: out)
        XCTAssertEqual(back, t)
        XCTAssertEqual(back.antibiotics.map(\.dose), ["3 g", "1.25 g"])
    }

    func testADoseReadFromARecordIsCleanedAndAWrongTypeIsIgnored() throws {
        let json = """
        {"antibiotics":[{"drug":"cefazolin","doses":[],"dose":"  3 g \\n"},{"drug":"vancomycin","doses":[],"dose":5},{"drug":"cefoxitin","doses":[],"dose":"   "}]}
        """
        let t = try JSONDecoder().decode(CaseTimers.self, from: Data(json.utf8))
        XCTAssertEqual(t.antibiotics.map(\.dose), ["3 g", nil, nil])
    }

    func testTheDoseIsKeptAsTypedTrimmedOneLineAtMost24Characters() {
        XCTAssertEqual(AntibioticCourse.cleanDose("  1.5 g  "), "1.5 g")
        XCTAssertEqual(AntibioticCourse.cleanDose("3"), "3", "no unit is added")
        XCTAssertEqual(AntibioticCourse.cleanDose("3 G"), "3 G", "not corrected")
        XCTAssertEqual(AntibioticCourse.cleanDose("1,230 mg"), "1,230 mg", "not converted")
        XCTAssertNil(AntibioticCourse.cleanDose(""), "empty: back to the worked-out dose")
        XCTAssertNil(AntibioticCourse.cleanDose("  \n "), "whitespace: back to the worked-out dose")
        XCTAssertNil(AntibioticCourse.cleanDose(nil))
        XCTAssertEqual(AntibioticCourse.cleanDose("3 g\nover 30 min"), "3 g over 30 min", "one line")
        let long = String(repeating: "x", count: 40)
        XCTAssertEqual(AntibioticCourse.cleanDose(long)?.count, 24)
        XCTAssertEqual(AntibioticCourse.cleanDose(String(repeating: "x", count: 24))?.count, 24, "24 is allowed")
        XCTAssertEqual(AntibioticCourse.cleanDose(String(repeating: "x", count: 23) + " yyyy"), String(repeating: "x", count: 23),
                       "a cut that ends on a space is trimmed")
        XCTAssertEqual(AntibioticDoseText.limited("a\nb"), "a b", "while typing: a newline becomes a space")
        XCTAssertEqual(AntibioticDoseText.limited(long).count, 24)
        XCTAssertEqual(AntibioticDoseText.limited("3 "), "3 ", "a space between words can be typed")
    }

    func testSetDoseTrimsAndClears() {
        var c = course(doses: [TimedEntry(time: at(8, 0))])
        c.setDose("  1.5 g ")
        XCTAssertEqual(c.dose, "1.5 g")
        c.setDose("   ")
        XCTAssertNil(c.dose)
        var t = CaseTimers()
        t.antibiotics = [c]
        XCTAssertTrue(t.setAntibioticDose("3 g", drug: "cefazolin"))
        XCTAssertEqual(t.course("cefazolin")?.dose, "3 g")
        XCTAssertFalse(t.setAntibioticDose("3 g", drug: "vancomycin"), "no such course")
    }

    func testAPendingPicksTypedDoseGoesIntoTheCourseWhenItIsLogged() {
        let c = AntibioticCourse.started(drug: "cefazolin", time: at(8, 10), ebl: 50, every: 240, typedDose: "  3 g ")
        XCTAssertEqual(c.dose, "3 g")
        XCTAssertEqual(c.doses.count, 1)
        XCTAssertEqual(c.doses[0].time, at(8, 10)); XCTAssertEqual(c.doses[0].ebl, 50)
        XCTAssertEqual(c.everyMinutes, 240)
        XCTAssertNil(c.doses[0].given, "the dose is the course's, not the dose entry's")
        XCTAssertNil(AntibioticCourse.started(drug: "cefazolin", time: at(8, 10), ebl: 0, every: 0, typedDose: nil).dose)
        XCTAssertNil(AntibioticCourse.started(drug: "cefazolin", time: at(8, 10), ebl: 0, every: 0, typedDose: "  ").dose)
    }

    // MARK: 1. What every surface shows

    func testTheLineDoseIsTheCoursesOwnWhenSetOtherwiseWhatItWasBefore() throws {
        let d = try data()
        let worked = CaseTimerEngine.antibioticDose(try XCTUnwrap(d.antibiotic("cefazolin")), record: adult()).text
        XCTAssertEqual(worked, "2 g")
        let plain = course(doses: [TimedEntry(time: at(8, 10))])
        XCTAssertEqual(AntibioticDoseText.line(plain, workedOut: worked), "2 g", "not set: the worked-out dose, as before")
        var set = plain; set.setDose("3 g")
        XCTAssertEqual(AntibioticDoseText.line(set, workedOut: worked), "3 g", "set: the course's dose")
        // A dose typed earlier in the bar: it was shown before; the course's dose, once set, wins.
        let typed = course(doses: [TimedEntry(time: at(8, 10), given: "1 g")])
        XCTAssertEqual(AntibioticDoseText.line(typed, workedOut: worked), "1 g", "not set: the last dose's typed text, as before")
        var differing = typed; differing.setDose("1.5 g")
        XCTAssertEqual(AntibioticDoseText.line(differing, workedOut: worked), "1.5 g", "set, and a differing typed dose: the course's wins")
        // Recorded only: nothing worked out was given, so nothing is said unless one was typed or set.
        let only = course("vancomycin", doses: [TimedEntry(time: at(8, 10))], reminders: false)
        XCTAssertEqual(AntibioticDoseText.line(only, workedOut: "1,230 mg"), "", "record-only, nothing typed")
        var onlyTyped = only; onlyTyped.doses[0].given = "1 g"
        XCTAssertEqual(AntibioticDoseText.line(onlyTyped, workedOut: "1,230 mg"), "1 g")
        onlyTyped.setDose("1.25 g")
        XCTAssertEqual(AntibioticDoseText.line(onlyTyped, workedOut: "1,230 mg"), "1.25 g")
        var onlySet = only; onlySet.setDose("1.25 g")
        XCTAssertEqual(AntibioticDoseText.line(onlySet, workedOut: nil), "1.25 g")
    }

    func testTheCardHeaderShowsTheCustomDoseThenTheWorkedOutOne() {
        XCTAssertEqual(AntibioticDoseText.header(custom: "3 g", workedOut: "2 g"), "3 g")
        XCTAssertEqual(AntibioticDoseText.header(custom: nil, workedOut: "2 g"), "2 g")
        let typedOnly = course("daptomycin", doses: [TimedEntry(time: at(8, 0), given: "500 mg")], reminders: false)
        XCTAssertEqual(AntibioticDoseText.typedCourseHeader(typedOnly), "500 mg", "a drug Case Timers does not list: the typed dose")
        var set = typedOnly; set.setDose("600 mg")
        XCTAssertEqual(AntibioticDoseText.typedCourseHeader(set), "600 mg")
        XCTAssertEqual(AntibioticDoseText.typedCourseHeader(course("daptomycin", doses: [TimedEntry(time: at(8, 0))], reminders: false)), "")
    }

    func testTheRowThePageAndTheHandoffCarryTheCustomDose() throws {
        let d = try data()
        var r = adult()
        r.timers.antibiotics = [
            course(doses: [TimedEntry(time: at(8, 10))], dose: "3 g"),
            course("vancomycin", doses: [TimedEntry(time: at(8, 20), given: "1 g")], dose: "1.25 g", reminders: false),
        ]
        let now = at(8, 40)
        let lines = CaseAntibiotics.lines(r, data: d, now: now)
        // The Intraoperative row and the Medications page both write `tabText`.
        XCTAssertEqual(lines[0].tabText, "Cefazolin 3 g · last 08:10 · next due 12:10")
        XCTAssertEqual(lines[1].tabText, "Vancomycin 1.25 g · given 08:20", "the course's dose wins over the dose typed with the dose")
        XCTAssertEqual(lines[0].handoffText, "Cefazolin 3 g, last 08:10, next due 12:10")
        let row = IntraopNotableMedicationLink.lines(r, antibiotics: lines)
        XCTAssertEqual(row.first?.text, "Cefazolin 3 g · last 08:10 · next due 12:10")
        let blocks = PatientBriefs.handoff(r, now: now)
        let b = try XCTUnwrap(blocks.first { $0.key == "infusions" })
        XCTAssertTrue(b.lines.contains("Antibiotics: Cefazolin 3 g, last 08:10, next due 12:10; Vancomycin 1.25 g, given 08:20"), "\(b.lines)")
        // Cleared: the lines read as they did before.
        r.timers.antibiotics[0].setDose(nil)
        XCTAssertEqual(CaseAntibiotics.lines(r, data: d, now: now)[0].tabText, "Cefazolin 2 g · last 08:10 · next due 12:10")
    }

    func testTheLastDoseLineDoesNotRepeatATypedDoseThatSaysTheSameButTellsOneThatDiffers() {
        let typed = TimedEntry(time: at(8, 10), given: "1 g")
        // Timed. Not set: as before ("given" where it says more than the worked-out dose).
        XCTAssertEqual(CaseTimersView.lastDoseText(last: typed, every: 240, computed: "2 g"), "Last dose 08:10 · next 12:10 · given: 1 g")
        // Set to the same words: not written again (case and spaces do not matter).
        XCTAssertEqual(CaseTimersView.lastDoseText(last: typed, every: 240, computed: "2 g", custom: "1g"), "Last dose 08:10 · next 12:10")
        XCTAssertEqual(CaseTimersView.lastDoseText(last: typed, every: 240, computed: "2 g", custom: "1 G"), "Last dose 08:10 · next 12:10")
        // Set to another dose: this dose's own typed text still tells how it was logged.
        XCTAssertEqual(CaseTimersView.lastDoseText(last: typed, every: 240, computed: "2 g", custom: "1.5 g"), "Last dose 08:10 · next 12:10 · given: 1 g")
        // The worked-out dose typed in the bar is not "more" than the worked-out dose; once set to something else it is.
        let same = TimedEntry(time: at(8, 10), given: "2 g")
        XCTAssertEqual(CaseTimersView.lastDoseText(last: same, every: 240, computed: "2 g"), "Last dose 08:10 · next 12:10")
        XCTAssertEqual(CaseTimersView.lastDoseText(last: same, every: 240, computed: "2 g", custom: "3 g"), "Last dose 08:10 · next 12:10 · given: 2 g")
        // Recorded only.
        XCTAssertEqual(CaseTimersView.lastDoseText(last: typed, every: nil, computed: "", recordOnly: true), "Last dose 08:10 · given: 1 g")
        XCTAssertEqual(CaseTimersView.lastDoseText(last: typed, every: nil, computed: "", recordOnly: true, custom: "1 g"), "Last dose 08:10")
        XCTAssertEqual(CaseTimersView.lastDoseText(last: typed, every: nil, computed: "", recordOnly: true, custom: "1.25 g"), "Last dose 08:10 · given: 1 g")
        // The log row of that dose keeps its own typed text whatever the course is set to.
        XCTAssertEqual(CaseTimersView.doseText(typed, name: "Cefazolin"), "08:10  Cefazolin 1 g")
    }

    func testTheHintTheNoteAndTheLinkSayTheWorkedOutDoseInTheExistingWords() throws {
        let d = try data()
        let cefazolin = try XCTUnwrap(d.antibiotic("cefazolin"))
        XCTAssertEqual(AntibioticDoseText.hint(cefazolin, record: adult()), "Worked out: 2 g (cefazolin, 82 kg)")
        XCTAssertEqual(AntibioticDoseText.workedOutNote(cefazolin, record: adult()), "worked out: 2 g")
        XCTAssertEqual(AntibioticDoseText.useWorkedOutTitle(cefazolin, record: adult()), "Use the worked-out dose (2 g)")
        XCTAssertEqual(AntibioticDoseText.hint(cefazolin, record: adult(130)), "Worked out: 3 g (cefazolin, 130 kg)", "3 g from 120 kg, as Case Timers says")
        // No weight: the written dose, never a number worked out.
        XCTAssertEqual(AntibioticDoseText.hint(cefazolin, record: adult(nil)), "Worked out: 2 g; 3 g if ≥120 kg (cefazolin)")
        // A dose that does not depend on the weight names no weight.
        XCTAssertEqual(AntibioticDoseText.hint(try XCTUnwrap(d.antibiotic("cefuroxime")), record: adult()), "Worked out: 1.5 g (cefuroxime)")
        // Per kg: its own working.
        let vanc = try XCTUnwrap(d.antibiotic("vancomycin"))
        XCTAssertEqual(AntibioticDoseText.hint(vanc, record: adult()), "Worked out: 1,230 mg (15 mg/kg × 82 kg)")
        XCTAssertEqual(AntibioticDoseText.workedOutNote(vanc, record: adult()), "worked out: 1,230 mg (15 mg/kg × 82 kg)")
        XCTAssertEqual(AntibioticDoseText.useWorkedOutTitle(vanc, record: adult()), "Use the worked-out dose (1,230 mg)")
        // Vancomycin with no weight: the existing "Weight needed" wording.
        XCTAssertEqual(AntibioticDoseText.hint(vanc, record: adult(nil)), "Worked out: Weight needed (15 mg/kg)")
        XCTAssertEqual(AntibioticDoseText.workedOutNote(vanc, record: adult(nil)), "worked out: weight needed")
        XCTAssertEqual(AntibioticDoseText.useWorkedOutTitle(vanc, record: adult(nil)), "Use the worked-out dose")
    }

    func testTheFieldOpensWithTheDoseShownWithoutTheWorkingWhenItIsLong() {
        XCTAssertEqual(AntibioticDoseText.prefill(custom: "3 g", shown: "2 g"), "3 g")
        XCTAssertEqual(AntibioticDoseText.prefill(custom: nil, shown: "2 g"), "2 g")
        XCTAssertEqual(AntibioticDoseText.prefill(custom: nil, shown: "1,230 mg (15 mg/kg × 82 kg)"), "1,230 mg")
        XCTAssertEqual(AntibioticDoseText.prefill(custom: nil, shown: "15 mg/kg"), "15 mg/kg", "the written dose when the weight is missing")
    }

    func testSameDoseIgnoresCaseAndSpaces() {
        XCTAssertTrue(AntibioticDoseText.same("1 g", "1G"))
        XCTAssertFalse(AntibioticDoseText.same("1 g", "1.5 g"))
    }

    // MARK: 2. A logged dose's time

    func testChangingTheTimeMovesNextDueTheReminderAndTheLine() throws {
        let d = try data()
        let dose = TimedEntry(time: at(8, 0), ebl: 100, given: "1 g")
        var r = adult()
        r.timers.antibiotics = [course(doses: [dose])]
        XCTAssertEqual(try cefazolinReminder(r.timers, r)?.due, at(12, 0))
        let now = at(9, 0)
        XCTAssertTrue(r.timers.updateAntibioticDose(dose.id, drug: "cefazolin", time: at(7, 40), now: now))
        let c = try XCTUnwrap(r.timers.course("cefazolin"))
        XCTAssertEqual(c.last?.time, at(7, 40))
        XCTAssertEqual(c.doses.count, 1, "the dose stays in the list")
        XCTAssertEqual(c.doses[0].id, dose.id)
        XCTAssertEqual(c.doses[0].ebl, 100, "the blood loss stays with the dose")
        XCTAssertEqual(c.doses[0].given, "1 g", "so does the text typed with it")
        XCTAssertEqual(try cefazolinReminder(r.timers, r)?.due, at(11, 40), "the redose countdown moved with it")
        XCTAssertEqual(CaseAntibiotics.lines(r, data: d, now: now)[0].next, at(11, 40))
        XCTAssertEqual(CaseAntibiotics.lines(r, data: d, now: now)[0].lastText, "07:40")
        let items = CaseTimerSchedule.items([(id: UUID(), label: "OR 1", record: r)], data: d)
        XCTAssertEqual(items.first { $0.reminder.id == "antibiotic.cefazolin" }?.reminder.due, at(11, 40), "the notification and the lock screen read this")
    }

    func testTheLongCaseAndBloodLossRemindersRunFromTheMovedDose() throws {
        let d = try data()
        let dose = TimedEntry(time: at(8, 0), ebl: 0)
        var r = adult()
        r.fluids["ebl"] = 1600
        r.timers.antibiotics = [course("ceftriaxone", doses: [dose])]
        // Ceftriaxone has no routine redose: the long-case reminder runs from the dose.
        let long = CaseTimerEngine.reminders(r.timers, record: r, data: d).first { $0.id == "longCase.ceftriaxone" }
        XCTAssertEqual(long?.due, at(8, 0).addingTimeInterval(try XCTUnwrap(d.antibioticRules.longCaseHours) * 3600))
        XCTAssertTrue(r.timers.updateAntibioticDose(dose.id, drug: "ceftriaxone", time: at(8, 30), now: at(9, 0)))
        let moved = CaseTimerEngine.reminders(r.timers, record: r, data: d)
        XCTAssertEqual(moved.first { $0.id == "longCase.ceftriaxone" }?.due, at(8, 30).addingTimeInterval(try XCTUnwrap(d.antibioticRules.longCaseHours) * 3600))
        XCTAssertEqual(moved.first { $0.id == "bloodLoss.ceftriaxone" }?.since, at(8, 30), "the blood-loss rule runs from the moved dose")
    }

    func testWithSeveralDosesTheLatestByTimeDecidesTheCountdown() throws {
        let first = TimedEntry(time: at(6, 0)), second = TimedEntry(time: at(8, 0))
        var t = CaseTimers()
        t.antibiotics = [course(doses: [first, second])]
        let r = adult()
        let now = at(9, 0)
        // An earlier dose moved earlier: the latest is the same, so the countdown is too.
        XCTAssertTrue(t.updateAntibioticDose(first.id, drug: "cefazolin", time: at(5, 30), now: now))
        XCTAssertEqual(try cefazolinReminder(t, r)?.due, at(12, 0))
        // An earlier dose moved after the latest becomes the latest.
        XCTAssertTrue(t.updateAntibioticDose(first.id, drug: "cefazolin", time: at(8, 45), now: now))
        XCTAssertEqual(try cefazolinReminder(t, r)?.due, at(12, 45))
        // The latest moved before the other: the other is the latest now.
        XCTAssertTrue(t.updateAntibioticDose(first.id, drug: "cefazolin", time: at(7, 0), now: now))
        XCTAssertEqual(try cefazolinReminder(t, r)?.due, at(12, 0))
    }

    func testAnUnknownDoseOrCourseChangesNothingAndTheFutureIsRefused() throws {
        let dose = TimedEntry(time: at(8, 0))
        var t = CaseTimers()
        t.antibiotics = [course(doses: [dose])]
        let before = t
        let now = at(9, 0)
        XCTAssertFalse(t.updateAntibioticDose(UUID(), drug: "cefazolin", time: at(8, 30), now: now), "no such dose")
        XCTAssertFalse(t.updateAntibioticDose(dose.id, drug: "vancomycin", time: at(8, 30), now: now), "no such course")
        var c = try XCTUnwrap(t.course("cefazolin"))
        XCTAssertFalse(c.updateDose(UUID(), time: at(8, 30), now: now))
        XCTAssertEqual(t, before)
        // Never in the future.
        XCTAssertFalse(t.updateAntibioticDose(dose.id, drug: "cefazolin", time: now.addingTimeInterval(60), now: now))
        XCTAssertFalse(c.updateDose(dose.id, time: now.addingTimeInterval(60), now: now))
        XCTAssertEqual(c.last?.time, at(8, 0))
        XCTAssertEqual(t, before)
        XCTAssertTrue(c.updateDose(dose.id, time: now, now: now), "now itself is allowed")
        // The control's rule (the Heparin & ACT row editor's, reused): a picked time after now does not resolve.
        XCTAssertNil(HeparinTimeline.resolvedEdit(picked: now.addingTimeInterval(3600), original: at(8, 0), now: now))
        XCTAssertEqual(HeparinTimeline.resolvedEdit(picked: nil, original: at(8, 0), now: now), at(8, 0), "unchanged until a time is picked")
        XCTAssertEqual(HeparinTimeline.resolvedEdit(picked: at(7, 30), original: at(8, 0), now: now), at(7, 30))
    }

    // MARK: 2. Snoozes and stops belong to the occurrence

    func testASnoozeOfTheOldDueTimeDoesNotHideTheNewOneOrStayBehind() throws {
        let dose = TimedEntry(time: at(8, 0))
        var r = adult()
        r.timers.antibiotics = [course(doses: [dose])]
        let now = at(12, 10)
        let overdue = try XCTUnwrap(try cefazolinReminder(r.timers, r))
        r.timers.snooze(overdue, now: now)
        XCTAssertEqual(try cefazolinReminder(r.timers, r)?.snoozed, true, "snoozed")
        XCTAssertNotNil(r.timers.snoozes["antibiotic.cefazolin"])
        XCTAssertTrue(r.timers.updateAntibioticDose(dose.id, drug: "cefazolin", time: at(8, 30), now: now))
        XCTAssertNil(r.timers.snoozes["antibiotic.cefazolin"], "no stale entry")
        let moved = try XCTUnwrap(try cefazolinReminder(r.timers, r))
        XCTAssertEqual(moved.due, at(12, 30)); XCTAssertFalse(moved.snoozed)
        // Back to the first time: a stale snooze for that due time would hide it again; there is none.
        XCTAssertTrue(r.timers.updateAntibioticDose(dose.id, drug: "cefazolin", time: at(8, 0), now: now))
        let back = try XCTUnwrap(try cefazolinReminder(r.timers, r))
        XCTAssertEqual(back.due, at(12, 0)); XCTAssertFalse(back.snoozed)
    }

    func testAStopOfTheBloodLossRuleBelongedToTheOldDoseAndIsClearedWithIt() throws {
        let dose = TimedEntry(time: at(8, 0), ebl: 0)
        var r = adult()
        r.fluids["ebl"] = 1600
        r.timers.antibiotics = [course(doses: [dose])]
        let rule = try XCTUnwrap(try cefazolinReminder(r.timers, r, kind: "bloodLoss"))
        r.timers.stop(rule)
        XCTAssertNil(try cefazolinReminder(r.timers, r, kind: "bloodLoss"), "stopped")
        XCTAssertTrue(r.timers.updateAntibioticDose(dose.id, drug: "cefazolin", time: at(8, 30), now: at(9, 0)))
        XCTAssertTrue(r.timers.snoozes.isEmpty, "the stop is gone with the old occurrence")
        XCTAssertNotNil(try cefazolinReminder(r.timers, r, kind: "bloodLoss"), "the rule counts from the moved dose")
        // Moving it back must not bring the old stop back to life.
        XCTAssertTrue(r.timers.updateAntibioticDose(dose.id, drug: "cefazolin", time: at(8, 0), now: at(9, 0)))
        XCTAssertNotNil(try cefazolinReminder(r.timers, r, kind: "bloodLoss"))
    }

    func testAChangeThatLeavesTheLatestDoseWhereItWasLeavesTheSnoozeAlone() throws {
        let early = TimedEntry(time: at(6, 0)), latest = TimedEntry(time: at(8, 0))
        var r = adult()
        r.timers.antibiotics = [course(doses: [early, latest])]
        let now = at(12, 10)
        r.timers.snooze(try XCTUnwrap(try cefazolinReminder(r.timers, r)), now: now)
        XCTAssertTrue(r.timers.updateAntibioticDose(early.id, drug: "cefazolin", time: at(5, 0), now: now))
        XCTAssertNotNil(r.timers.snoozes["antibiotic.cefazolin"], "the reminder it belongs to did not change")
        XCTAssertEqual(try cefazolinReminder(r.timers, r)?.snoozed, true)
    }

    // MARK: The reminders: the same ones at the same times, the redose line saying the dose set

    func testSettingTheDoseChangesNoReminderButTheRedoseLineSaysIt() throws {
        let d = try data()
        var r = adult()
        r.fluids["ebl"] = 1600
        r.timers.antibiotics = [
            course(doses: [TimedEntry(time: at(8, 0), ebl: 0)]),
            course("ceftriaxone", doses: [TimedEntry(time: at(8, 5), ebl: 0)], every: 0),
            course("vancomycin", doses: [TimedEntry(time: at(8, 10))], reminders: false),
        ]
        let before = CaseTimerEngine.reminders(r.timers, record: r, data: d)
        XCTAssertFalse(before.isEmpty)
        XCTAssertTrue(r.timers.setAntibioticDose("3 g", drug: "cefazolin"))
        XCTAssertTrue(r.timers.setAntibioticDose("1.5 g", drug: "ceftriaxone"))
        XCTAssertTrue(r.timers.setAntibioticDose("1.25 g", drug: "vancomycin"))
        // Which reminders there are and when they fall due do not depend on the dose text; the redose reminder's own line says the
        // dose set for the case (the running list, the notification and the lock screen read it), and nothing else changes.
        func shape(_ rs: [CaseReminder]) -> [String] { rs.map { $0.id + "|" + $0.title + "|" + ($0.due.map { String($0.timeIntervalSinceReferenceDate) } ?? "now") } }
        let after = CaseTimerEngine.reminders(r.timers, record: r, data: d)
        XCTAssertEqual(shape(after), shape(before), "the same reminders at the same times")
        let redose = try XCTUnwrap(after.first { $0.id == "antibiotic.cefazolin" })
        XCTAssertTrue(redose.detail.hasPrefix("3 g · every"), redose.detail)
        XCTAssertEqual(after.filter { $0.id != "antibiotic.cefazolin" }, before.filter { $0.id != "antibiotic.cefazolin" }, "every other reminder is word for word the same")
        r.timers.setAntibioticDose(nil, drug: "cefazolin")
        XCTAssertEqual(CaseTimerEngine.reminders(r.timers, record: r, data: d), before, "the worked-out dose again once the custom one is cleared")
        XCTAssertEqual(r.timers.hasTimers, true)
    }
}
