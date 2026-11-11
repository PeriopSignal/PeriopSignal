import XCTest
@testable import PeriopSignal

/// 1.10 Intraoperative tab and handoff text (Ben, Nov 7): the airway course as his example reads it (no Han grade, no
/// difficult-airway follow-up, "Fiberoptic scope"), Intubation or LMA, MM/DD/YY dates, SLIC on central lines, the labs'
/// times, the drips' units, and where the older tab's parts went.
final class Intraop110Tests: XCTestCase {
    /// 7 November 2026, 09:41 on the device's clock.
    private func date(_ day: Int = 7, _ hour: Int = 9, _ minute: Int = 41, month: Int = 11, year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func block(_ blocks: [SummaryBlock], _ key: String) throws -> SummaryBlock {
        try XCTUnwrap(blocks.first { $0.key == key }, "no \(key) block in \(blocks.map(\.key))")
    }

    /// Ben's example (notes-img2).
    private var example: PatientRecord {
        var r = PatientRecord()
        r.oxygen = PatientOxygen(device: "ra")
        r.mask = "difficult"
        r.maskNote = "Beard"
        r.intubation = "easy"
        r.airwayDevice = "Video laryngoscope"
        r.laryngoscopyGrade = "1"
        r.tube = "8.0 cuffed ETT (23 cm)"
        r.airwayAtEnd = "intubated"
        return r
    }

    // MARK: Airway course

    func testTheAirwayCourseReadsAsBensExample() throws {
        // 1.12 (Ben, Nov 10): the same course in the short form (B112Tests has the rules).
        let want = "Oxygen on arrival: Room air. Difficult Mask (beard), Easy VL Intubation, ETT 8.0 at 23 cm. Remains intubated"
        XCTAssertEqual(PatientBriefs.airwayCourse(example)?.text, want)
        XCTAssertEqual(try block(PatientBriefs.handoff(example), "airway").text, want)
        XCTAssertEqual(PatientBriefs.airwayCourse(example)?.alert, true)
    }

    func testNoStraySpaceBeforeAPeriod() {
        var r = example
        r.maskNote = "Beard "
        r.tube = "8.0 cuffed ETT (23 cm). "
        let text = PatientBriefs.airwayCourse(r)?.text ?? ""
        XCTAssertFalse(text.contains(" ."), text)
        XCTAssertFalse(text.contains(".."), text)
        XCTAssertTrue(text.contains("Difficult Mask (beard), Easy VL"), text)
        XCTAssertTrue(text.contains("at 23 cm. Remains intubated"), text)
        r.maskNote = "Beard.  "
        XCTAssertTrue(PatientBriefs.airwayCourse(r)?.text.contains("Difficult Mask (beard), Easy VL") ?? false)
    }

    func testASavedHanGradeIsIgnored() throws {
        var r = example
        r.mask = "easy"; r.maskNote = ""
        r.maskGrade = 4
        let text = PatientBriefs.airwayCourse(r)?.text ?? ""
        XCTAssertTrue(text.contains("Easy Mask"), text)
        XCTAssertFalse(text.lowercased().contains("grade 4"), text)
        XCTAssertFalse(text.contains("(grade"), text)
        XCTAssertFalse(PatientSummary.difficultAirway(r), "a Han grade of 3 or 4 no longer makes the airway difficult")
        // A grade alone, with no mask ease, adds no sentence either.
        var alone = PatientRecord()
        alone.maskGrade = 2
        XCTAssertNil(PatientBriefs.airwayCourse(alone))
        XCTAssertTrue(PatientSummary.airwayCourseSentences(alone).isEmpty)
        // 1.10 review: read from a save, a grade of 3 or 4 is the difficult mask it meant (migrate on read,
        // PatientAirway.migratedMask; Review110HistoryIntraopTests), so it is not lost; the grade itself is then dropped,
        // so a later edit of the mask is not undone on the next load.
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertNil(back.maskGrade)
        XCTAssertEqual(back.mask, "difficult")
    }

    func testTheDifficultAirwayFollowUpIsGoneFromTheAirwayAndTheHandoff() throws {
        var r = example
        r.intubation = "difficult"
        r.airwayFollowUp = ["told", "documented"]
        let course = PatientBriefs.airwayCourse(r)?.text ?? ""
        XCTAssertFalse(course.localizedCaseInsensitiveContains("follow-up"), course)
        XCTAssertFalse(course.contains("Still to do"), course)
        for text in [HandoffWriter.text(r), HandoffWriter.shortText(r), PatientBriefs.plainText(PatientBriefs.handoff(r))] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("follow-up"), text)
            XCTAssertFalse(text.contains("Patient told"), text)
        }
        XCTAssertTrue(PatientSummary.intraopPartLines(r, "airway").allSatisfy { $0.label != "Difficult-airway follow-up" })
        XCTAssertTrue(PatientSummary.intraopLines(r).allSatisfy { $0.label != "Difficult-airway follow-up" })
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.airwayFollowUp, ["told", "documented"], "a saved follow-up stays in the record, ignored")
    }

    func testFiberopticScopeAndASavedFlexibleScope() throws {
        XCTAssertTrue(PatientCatalog.devices.contains("Fiberoptic scope"))
        XCTAssertFalse(PatientCatalog.devices.contains("Flexible scope"))
        XCTAssertEqual(PatientAirway.deviceName("Flexible scope"), "Fiberoptic scope")
        XCTAssertEqual(PatientAirway.deviceName("flexible scope"), "Fiberoptic scope")
        XCTAssertEqual(PatientAirway.deviceName("Video laryngoscope"), "Video laryngoscope")
        XCTAssertNil(PatientAirway.deviceName(nil))
        // A patient saved before 1.10 loads with the new name, so the chip shows it chosen.
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"airwayDevice":"Flexible scope","intubation":"easy"}"#.utf8))
        XCTAssertEqual(old.airwayDevice, "Fiberoptic scope")
        XCTAssertTrue(PatientAirway.intubationDevices.contains(old.airwayDevice ?? ""))
        // And a record set in memory with the old name still reads the new way.
        var r = PatientRecord()
        r.intubation = "easy"; r.airwayDevice = "Flexible scope"
        XCTAssertEqual(PatientSummary.airwayCourseSentences(r), ["Intubation easy: fiberoptic scope"])
    }

    // MARK: Intubation or LMA

    func testChoosingIntubationOrLMA() {
        var r = PatientRecord()
        XCTAssertFalse(PatientAirway.intubationChosen(r))
        XCTAssertFalse(PatientAirway.lmaChosen(r))
        PatientAirway.setIntubation(true, &r)
        XCTAssertTrue(PatientAirway.intubationChosen(r))
        XCTAssertEqual(PatientAirway.ease(r.intubation), nil, "chosen, with no ease recorded yet")
        XCTAssertEqual(PatientSummary.airwayCourseSentences(r), ["Intubation"], "chosen, nothing more said yet")
        r.airwayDevice = "Video laryngoscope"; r.laryngoscopyGrade = "2a"; r.tube = "7.5 ETT"
        XCTAssertEqual(PatientSummary.airwayCourseSentences(r), ["Intubation: video laryngoscope, grade 2a; 7.5 ETT"])
        r.intubation = "difficult"; r.intubationNote = "Bougie"
        XCTAssertEqual(PatientSummary.airwayCourseSentences(r), ["Intubation DIFFICULT: video laryngoscope, grade 2a; 7.5 ETT. Bougie"])
        XCTAssertTrue(PatientSummary.difficultAirway(r))
        // Clearing Intubation clears what it opened.
        PatientAirway.setIntubation(false, &r)
        XCTAssertFalse(PatientAirway.intubationChosen(r))
        XCTAssertNil(r.intubation); XCTAssertNil(r.airwayDevice); XCTAssertNil(r.laryngoscopyGrade); XCTAssertEqual(r.tube, ""); XCTAssertEqual(r.intubationNote, "")
        // The LMA.
        PatientAirway.setLMA(true, &r)
        XCTAssertTrue(PatientAirway.lmaChosen(r))
        XCTAssertFalse(PatientAirway.intubationChosen(r))
        XCTAssertEqual(PatientSummary.airwayCourseSentences(r), ["Supraglottic airway"])
        r.sga = "easy"
        XCTAssertEqual(PatientSummary.airwayCourseSentences(r), ["Supraglottic airway easy"])
        PatientAirway.setLMA(false, &r)
        XCTAssertFalse(PatientAirway.lmaChosen(r))
        XCTAssertNil(r.sga)
    }

    func testOlderRecordsKeepTheirChoice() {
        // An older save with an intubation and its details, and one with an LMA the quick-add bar filed as a device.
        var a = PatientRecord()
        a.intubation = "easy"; a.airwayDevice = "Direct laryngoscope"; a.attempts = 2
        XCTAssertTrue(PatientAirway.intubationChosen(a))
        XCTAssertFalse(PatientAirway.lmaChosen(a))
        var b = PatientRecord()
        b.airwayDevice = "Supraglottic airway"; b.tube = "LMA 4"
        XCTAssertTrue(PatientAirway.lmaChosen(b))
        XCTAssertFalse(PatientAirway.intubationChosen(b), "an LMA's size is not a tube")
        var none = PatientRecord()
        none.intubation = "none"; none.sga = "none"
        XCTAssertFalse(PatientAirway.intubationChosen(none))
        XCTAssertFalse(PatientAirway.lmaChosen(none))
        XCTAssertEqual(PatientSummary.airwayCourseSentences(none), ["Not intubated"], "an older 'Not intubated' still reads")
    }

    // MARK: Dates

    func testDatesWithADayAreMMDDYY() {
        let d = date()
        XCTAssertEqual(PatientDates.day(d), "11/07/26")
        XCTAssertEqual(PatientDates.dayTime(d), "11/07/26 09:41")
        XCTAssertEqual(PatientDates.weekdayDayTime(d), "Sat 11/07/26, 09:41")
        XCTAssertEqual(PatientDates.weekdayDay(d), "Sat 11/07/26")
        XCTAssertEqual(PatientDates.day(date(3, month: 1)), "01/03/26", "two digits, with the zero")
        // The summary's times: the clock alone for today, the date and clock for another day.
        XCTAssertEqual(PatientSummary.time(d, now: d), "09:41")
        XCTAssertEqual(PatientSummary.time(date(3, 15, 5, month: 11), now: d), "11/03/26 15:05")
        // The line that closes a copied handoff.
        XCTAssertTrue(PatientBriefs.footer(d).hasPrefix("Prepared with Periop Signal, 11/07/26 09:41."), PatientBriefs.footer(d))
        // The case archive.
        XCTAssertEqual(PatientArchiveWriter.label("2026-10-29", now: d), "10/29/26")
        XCTAssertEqual(PatientArchiveWriter.label("2026-11-07", now: d), "Today")
        // A month and year has no day to show: MM/YYYY.
        XCTAssertEqual(PatientMonthYear(month: 6, year: 2025).text, "06/2025")
        XCTAssertEqual(PatientMonthYear(year: 2025).text, "2025")
    }

    // MARK: SLIC

    func testSLICIsACentralLineOption() throws {
        XCTAssertTrue(DeviceKind.cvc.fields.first { $0.id == "detail" }?.choices.contains("SLIC") ?? false, "a Type choice for the central line")
        let p = try XCTUnwrap(PatientDevices.parse("RIJ SLIC"))
        XCTAssertEqual(p.kind, .cvc)
        XCTAssertEqual(p.detail, "SLIC")
        XCTAssertEqual(p.site, "ij-right")
        XCTAssertEqual(p.device().label, "CVL R IJ (SLIC)")
        let sized = try XCTUnwrap(PatientDevices.parse("LIJ SLIC 9 Fr"))
        XCTAssertEqual(sized.kind, .cvc)
        XCTAssertEqual(sized.size, "9")
        XCTAssertEqual(sized.device().label, "CVL 9 Fr L IJ (SLIC)")
        // The words, and an "introducer" beside it, name the same thing once.
        XCTAssertEqual(try XCTUnwrap(PatientDevices.parse("R IJ short length introducer")).detail, "SLIC")
        XCTAssertEqual(try XCTUnwrap(PatientDevices.parse("RIJ SLIC introducer")).detail, "SLIC")
        // The others still read as they did.
        XCTAssertEqual(try XCTUnwrap(PatientDevices.parse("RIJ introducer/mac")).detail, "MAC introducer")
        XCTAssertEqual(try XCTUnwrap(PatientDevices.parse("RIJ TLC")).detail, "triple lumen")
    }

    // MARK: Labs: times, very small
    //
    // 1.12 (Ben's note 8) took the asterisk and its footnote ("* Intraop 10:40; other values preop") out: the Preop and
    // Intraop columns say which is which. The times stay as the small caption, so the 1.10 tests of the caption were
    // rewritten for the new wording (they are also covered in A112Tests).

    func testAnOlderTimeInTheLabsCaptionUsesTheNewDate() {
        var r = PatientRecord()
        r.labs = ["k": 5.0, "na": 138]
        r.intraopLabs = [IntraopLabSet(time: date(3, 10, 40), values: ["inr": 1.4])]
        let caption = BriefLabs.make(r, withIntraop: true, now: date()).caption
        XCTAssertEqual(caption, "Intraop 11/03/26 10:40")
        // The gas names its own time, with the date when it is another day.
        r.intraopLabs = [IntraopLabSet(time: date(3, 10, 40), values: ["ph": 7.4])]
        XCTAssertEqual(BriefLabs.make(r, withIntraop: true, now: date()).gas?.title, "ABG (11/03/26 10:40)")
    }

    func testPreoperativeLabsNoteWhenTheyWereDrawn() throws {
        var r = PatientRecord()
        r.labs = ["k": 4.1, "na": 138]
        XCTAssertNil(BriefLabs.make(r, withIntraop: false, now: date()).caption, "no time entered, none shown")
        r.labsDrawn = date(7, 6, 30)
        XCTAssertEqual(BriefLabs.make(r, withIntraop: false, now: date()).caption, "Preop labs 06:30")
        guard case .fishbone(let pre)? = try block(PatientBriefs.preop(r, now: date()), "labs").figure else { return XCTFail("no labs figure") }
        XCTAssertEqual(pre.caption, "Preop labs 06:30")
        XCTAssertEqual(PatientBriefs.plainText(PatientBriefs.preop(r, now: date())), "Labs: Preop: CMP: Na 138, K 4.1\n  Preop labs 06:30")
        // Drawn another day: the date too.
        r.labsDrawn = date(5, 6, 30)
        XCTAssertEqual(BriefLabs.make(r, withIntraop: false, now: date()).caption, "Preop labs 11/05/26 06:30")
    }

    func testTheHandoffNotesTheTimeOfEachSetAndOfThePreoperativeValues() throws {
        var r = PatientRecord()
        r.labs = ["k": 5.6, "na": 138]
        r.labsDrawn = date(7, 6, 30)
        r.intraopLabs = [IntraopLabSet(time: date(7, 10, 40), values: ["inr": 1.4])]
        let caption = BriefLabs.make(r, withIntraop: true, now: date()).caption
        XCTAssertEqual(caption, "Preop labs 06:30 · Intraop 10:40")
        XCTAssertEqual(PatientBriefs.plainText(PatientBriefs.handoff(r, now: date())),
                       "Labs:\n  Preop: CMP: Na 138, K 5.6 H\n  Intraop: Heme: INR 1.4 H\n  Preop labs 06:30 · Intraop 10:40")
        // Preoperative labs with a time and no case sets: the time alone.
        var pre = PatientRecord()
        pre.labs = ["na": 138]
        pre.labsDrawn = date(7, 6, 30)
        XCTAssertEqual(BriefLabs.make(pre, withIntraop: true, now: date()).caption, "Preop labs 06:30")
    }

    func testALabSetWithOnlyAGasStillShowsItsTime() throws {
        // pH and lactate alone: the Intraop column is the gas, labelled with its time.
        var r = PatientRecord()
        r.intraopLabs = [IntraopLabSet(time: date(7, 10, 40), values: ["ph": 7.33, "lactate": 1.4])]
        let labs = try block(PatientBriefs.handoff(r, now: date()), "labs")
        guard case .fishbone(let f)? = labs.figure else { return XCTFail("the labs block keeps its figure") }
        XCTAssertFalse(f.isEmpty)
        XCTAssertEqual(f.gas?.figureLabel, "ABG · 10:40")
        XCTAssertNil(f.caption, "the gas carries its time; no coags, so nothing else to date")
        XCTAssertTrue(labs.figureHasContent)
        XCTAssertEqual(labs.text, "Intraop: ABG (10:40): pH 7.33 L, Lactate 1.4")
    }

    func testTheDrawnTimeSavesAndOlderRecordsHaveNone() throws {
        var r = PatientRecord()
        r.labsDrawn = date()
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.labsDrawn, r.labsDrawn)
        XCTAssertNil(try JSONDecoder().decode(PatientRecord.self, from: Data("{}".utf8)).labsDrawn)
        XCTAssertFalse(r.isEmpty)
    }

    // MARK: Infusions: the unit fills in

    private func drips(_ s: String) -> [String] { InfusionEntry.read(s).items.map(\.label) }

    func testTheUnitFillsInForTheCommonDrips() {
        XCTAssertEqual(drips("norepi 0.05"), ["Norepinephrine 0.05 mcg/kg/min"])
        XCTAssertEqual(drips("vaso 0.04"), ["Vasopressin 0.04 units/min"])
        XCTAssertEqual(drips("milri 0.25"), ["Milrinone 0.25 mcg/kg/min"])
        XCTAssertEqual(drips("dobut 5"), ["Dobutamine 5 mcg/kg/min"])
        XCTAssertEqual(drips("dopa 5"), ["Dopamine 5 mcg/kg/min"])
        XCTAssertEqual(drips("nicard 5"), ["Nicardipine 5 mg/h"])
        XCTAssertEqual(drips("prop 75"), ["Propofol 75 mcg/kg/min"])
        XCTAssertEqual(drips("dexmed 0.7"), ["Dexmedetomidine 0.7 mcg/kg/h"])
        // A drug whose list gives one unit fills it in too (1.10); one that could be more than one still asks.
        XCTAssertEqual(drips("insulin 4"), ["Insulin 4 units/h"])
        XCTAssertEqual(drips("vec 1"), ["Vecuronium 1 mcg/kg/min"])
        XCTAssertEqual(drips("amicar 1"), ["Aminocaproic acid 1 g/h"])
        XCTAssertTrue(drips("ketamine 0.5").isEmpty)
        XCTAssertFalse(InfusionEntry.read("ketamine 0.5").questions.isEmpty)
        XCTAssertTrue(drips("heparin 1000").isEmpty)
    }

    func testTheTypeaheadSaysTheUnit() {
        XCTAssertEqual(InfusionEntry.suggestions("norepi 0.05, va").first?.id, "vasopressin")
        XCTAssertEqual(InfusionEntry.unitHint("norepi"), "Units: mcg/kg/min or mcg/min")
        XCTAssertEqual(InfusionEntry.unitHint("insulin"), "Unit fills in: units/h")
        XCTAssertEqual(InfusionEntry.unitHint("vasopressin"), "Units: units/min or units/h")
        XCTAssertNil(InfusionEntry.unitHint("norepi 0.05"), "a rate typed: the unit is filled in on the chip")
        XCTAssertNil(InfusionEntry.unitHint(""))
        XCTAssertNil(InfusionEntry.unitHint("xyz"))
        XCTAssertNil(InfusionEntry.unitHint("levo"), "a word that names two drugs is asked, not hinted")
    }

    // MARK: The tab

    func testTheOlderPartKeysScrollToTheirNewSection() {
        XCTAssertEqual(IntraopSection(part: "airway"), .airway)
        XCTAssertEqual(IntraopSection(part: "lines"), .lines)
        XCTAssertEqual(IntraopSection(part: "infusions"), .meds)
        XCTAssertEqual(IntraopSection(part: "meds"), .meds)
        XCTAssertEqual(IntraopSection(part: "fluids"), .fluids)
        for part in ["regional", "labs", "events", "echo", "considerations", "something-else"] {
            XCTAssertEqual(IntraopSection(part: part), .other, part)
        }
        // Every part of the older tab is in a section, and every part's editor is still there for a deep link.
        for part in PatientEditor.intraopParts { _ = IntraopSection(part: part.id) }
        XCTAssertEqual(PatientDeepLink.parse("intraop:labs"), .editor(.intraopPart("labs")))
        XCTAssertEqual(PatientDeepLink.parse("intraop:considerations"), .editor(.intraopPart("considerations")))
    }

    func testTheFiveHeadingsInBensOrder() {
        XCTAssertEqual(IntraopSection.allCases.map(\.title),
                       ["Airway Course", "Lines & Devices", "Medications & Infusions", "Fluids & Blood", "Other Intraoperative Details"])
        XCTAssertEqual(Set(IntraopSection.allCases.map { PatientJumpID(intraop: $0) }).count, 5, "each heading is its own scroll target")
    }

    // MARK: Quick add

    private func applied(_ s: String, _ base: PatientRecord = PatientRecord()) -> PatientRecord {
        let q = QuickAdd.read(s, record: base, tab: .intraop, now: date(), choices: [:])
        var r = base
        PatientNote.apply(q.findings.map(\.change), to: &r)
        return r
    }

    func testQuickAddFilesTheFiberopticScopeAndDropsTheHanGrade() {
        XCTAssertEqual(applied("fiberoptic intubation, 7.0 ETT").airwayDevice, "Fiberoptic scope")
        let r = applied("easy mask grade 2, VL grade 1, 7.5 ETT")
        XCTAssertNil(r.maskGrade, "the Han grade is not recorded")
        XCTAssertEqual(r.mask, "easy")
        XCTAssertEqual(r.laryngoscopyGrade, "1")
    }
}
