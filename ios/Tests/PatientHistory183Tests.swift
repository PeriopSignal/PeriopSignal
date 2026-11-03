import XCTest
@testable import PeriopSignal

/// 1.8.3, Ben: month and year typed without "/" (#7), and Past surgical history filled from a typed history (#9).
final class PatientHistory183Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 8))! }

    private func my(_ s: String) -> PatientMonthYear? { PatientMonthYear.parse(s, now: now) }
    private func m(_ month: Int?, _ year: Int) -> PatientMonthYear { PatientMonthYear(month: month, year: year) }

    /// What the field holds after these characters are typed one at a time.
    private func typed(_ s: String, from start: String = "") -> String {
        var text = start
        for ch in s {
            let raw = text + String(ch)
            var shown = PatientMonthYear.typing(raw, was: text)
            // The field runs the formatter again on its own output until it settles.
            var guardCount = 0
            while true {
                let again = PatientMonthYear.typing(shown, was: raw)
                if again == shown || guardCount > 3 { break }
                shown = again; guardCount += 1
            }
            text = shown
        }
        return text
    }

    // MARK: #7 Month and year

    func testEveryDateFormIsRead() {
        XCTAssertEqual(my("06/2026"), m(6, 2026))
        XCTAssertEqual(my("6/2026"), m(6, 2026))
        XCTAssertEqual(my("0626"), m(6, 2026), "MMYY")
        XCTAssertEqual(my("062026"), m(6, 2026), "MMYYYY")
        XCTAssertEqual(my("626"), m(6, 2026), "M YY")
        XCTAssertEqual(my("62026"), m(6, 2026), "M YYYY")
        XCTAssertEqual(my("12026"), m(1, 2026), "M YYYY with a month of one digit")
        XCTAssertEqual(my("102019"), m(10, 2019))
        XCTAssertEqual(my("6 2026"), m(6, 2026))
        XCTAssertEqual(my("6-2026"), m(6, 2026))
        XCTAssertEqual(my("6.2026"), m(6, 2026))
        XCTAssertEqual(my("2026-06"), m(6, 2026))
        XCTAssertEqual(my("Jun 2026"), m(6, 2026))
        XCTAssertEqual(my("June 26"), m(6, 2026))
        XCTAssertEqual(my("sept 2020"), m(9, 2020))
        XCTAssertEqual(my("2019"), PatientMonthYear(year: 2019))
        XCTAssertEqual(my("1999"), PatientMonthYear(year: 1999))
        XCTAssertEqual(my("1126"), m(11, 2026), "not a year, so MMYY")
    }

    func testNotADate() {
        XCTAssertNil(my("13/2019"))
        XCTAssertNil(my("soon"))
        XCTAssertNil(my("marx 2020"), "not a month")
        XCTAssertNil(my("0026"))
        XCTAssertNil(my("6/2"), "a year of one digit")
        XCTAssertNil(my(""))
    }

    func testTwoDigitYear() {
        XCTAssertEqual(my("06/26"), m(6, 2026))
        XCTAssertEqual(my("06/27"), m(6, 2027), "next year is still 20YY")
        XCTAssertEqual(my("06/28"), m(6, 1928), "later than next year: 19YY")
        XCTAssertEqual(my("06/99"), m(6, 1999))
        XCTAssertEqual(my("06/05"), m(6, 2005))
        XCTAssertEqual(my("Jun 28"), m(6, 1928))
        XCTAssertEqual(my("0627"), m(6, 2027))
        XCTAssertEqual(PatientMonthYear.fullYear(twoDigit: 27, now: now), 2027)
        XCTAssertEqual(PatientMonthYear.fullYear(twoDigit: 28, now: now), 1928)
    }

    func testStoredFormatIsUnchanged() {
        XCTAssertEqual(my("0626")?.text, "06/2026")
        XCTAssertEqual(my("6 2026")?.text, "06/2026")
        XCTAssertEqual(my("2019")?.text, "2019")
        let json = try? JSONEncoder().encode(PatientMonthYear(month: 6, year: 2026))
        let back = json.flatMap { try? JSONDecoder().decode(PatientMonthYear.self, from: $0) }
        XCTAssertEqual(back, m(6, 2026))
    }

    func testSlashGoesInAsDigitsAreTyped() {
        XCTAssertEqual(typed("06"), "06/")
        XCTAssertEqual(typed("062"), "06/2")
        XCTAssertEqual(typed("062026"), "06/2026")
        XCTAssertEqual(typed("0626"), "06/26")
        XCTAssertEqual(typed("12"), "12/")
        XCTAssertEqual(typed("122019"), "12/2019")
        XCTAssertEqual(typed("6"), "06/", "a month that cannot start a two-digit month")
        XCTAssertEqual(typed("62026"), "06/2026")
        XCTAssertEqual(typed("9"), "09/")
        XCTAssertEqual(typed("06/"), "06/", "typing the slash oneself changes nothing")
        XCTAssertEqual(typed("06/2026"), "06/2026")
        XCTAssertEqual(typed("6/"), "06/")
        XCTAssertEqual(typed("6-"), "06/", "a dash, dot or space after the month is the slash")
        XCTAssertEqual(typed("6.2026"), "06/2026")
        XCTAssertEqual(typed("6 2026"), "06/2026")
    }

    func testAYearAloneIsLeftToBeTyped() {
        XCTAssertEqual(typed("1"), "1")
        XCTAssertEqual(typed("19"), "19")
        XCTAssertEqual(typed("199"), "199")
        XCTAssertEqual(typed("1999"), "1999")
        XCTAssertEqual(typed("2"), "2")
        XCTAssertEqual(typed("20"), "20")
        XCTAssertEqual(typed("2019"), "2019")
        XCTAssertEqual(typed("201912"), "2019", "no more than four digits")
        XCTAssertEqual(typed("21"), "02/1", "21 cannot be a year: February and a year starting 1")
        XCTAssertEqual(typed("10"), "10/")
        XCTAssertEqual(typed("00"), "00")
        XCTAssertEqual(typed("0"), "0")
    }

    func testBackspaceGoesBackThroughTheSlash() {
        // Deleting never adds anything.
        XCTAssertEqual(PatientMonthYear.typing("06", was: "06/"), "06")
        XCTAssertEqual(PatientMonthYear.typing("0", was: "06"), "0")
        XCTAssertEqual(PatientMonthYear.typing("06/202", was: "06/2026"), "06/202")
        XCTAssertEqual(PatientMonthYear.typing("06/", was: "06/2"), "06/")
        XCTAssertEqual(PatientMonthYear.typing("", was: "06/"), "")
        // A selection replaced by a digit is typing.
        XCTAssertEqual(PatientMonthYear.typing("7", was: "06/2026"), "07/")
        // And typing on after deleting back to the month works as before.
        XCTAssertEqual(typed("2", from: "06"), "06/2")
        XCTAssertEqual(typed("7", from: "06"), "06/7")
        XCTAssertEqual(typed("026", from: "06/2"), "06/2026")
    }

    func testPastedDates() {
        XCTAssertEqual(PatientMonthYear.typing("62026", was: ""), "06/2026")
        XCTAssertEqual(PatientMonthYear.typing("062026", was: ""), "06/2026")
        XCTAssertEqual(PatientMonthYear.typing("12026", was: ""), "01/2026")
        XCTAssertEqual(PatientMonthYear.typing("2019", was: ""), "2019")
        XCTAssertEqual(PatientMonthYear.typing("Jun 2026", was: ""), "Jun 2026", "words are left as typed")
        XCTAssertEqual(PatientMonthYear.typing("June", was: "Jun"), "June")
    }

    func testAHalfTypedDateChangesNothing() {
        XCTAssertNil(PatientMonthYear.parseTyped("06/", now: now))
        XCTAssertNil(PatientMonthYear.parseTyped("06/2", now: now))
        XCTAssertNil(PatientMonthYear.parseTyped("06/202", now: now))
        XCTAssertNil(PatientMonthYear.parseTyped("20", now: now))
        XCTAssertNil(PatientMonthYear.parseTyped("201", now: now))
        XCTAssertNil(PatientMonthYear.parseTyped("1", now: now))
        XCTAssertNil(PatientMonthYear.parseTyped("Jun", now: now))
        XCTAssertEqual(PatientMonthYear.parseTyped("06/2026", now: now), m(6, 2026))
        XCTAssertEqual(PatientMonthYear.parseTyped("06/26", now: now), m(6, 2026))
        XCTAssertEqual(PatientMonthYear.parseTyped("2019", now: now), PatientMonthYear(year: 2019))
        XCTAssertEqual(PatientMonthYear.parseTyped("Jun 2026", now: now), m(6, 2026))
    }

    // MARK: #9 Past surgical history

    private func read(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func psh(_ s: String) -> [PatientNoteFinding] { read(s).findings.filter { $0.id.hasPrefix("psh:") || $0.id == "cardiac-surgery" } }
    private func applied(_ text: String, to start: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = start
        PatientNote.apply(read(text).findings.map(\.change), to: &r)
        return r
    }

    func testPSHSectionFillsEachOperationWithItsDate() {
        let r = applied("PSH: CABG x3 2019, TEVAR 08/2022, appendectomy")
        XCTAssertEqual(r.surgeries.count, 3)
        XCTAssertEqual(r.surgeries[0].text, "Coronary artery bypass grafting ×3 (2019)")
        XCTAssertEqual(r.surgeries[0].procedures.first?.catalogID, "cabg", "matched to the procedure list")
        XCTAssertEqual(r.surgeries[0].date, PatientMonthYear(year: 2019))
        XCTAssertEqual(r.surgeries[1].procedures.first?.catalogID, "tevar")
        XCTAssertEqual(r.surgeries[1].date, m(8, 2022))
        XCTAssertEqual(r.surgeries[2].text, "Appendectomy", "not in the list by that name: as typed, and not made laparoscopic")
        XCTAssertNil(r.surgeries[2].procedures.first?.catalogID)
        XCTAssertTrue(r.surgeries[2].date.isEmpty)
    }

    func testSectionHeaders() {
        for header in ["PSH:", "PSHx:", "Past surgical history:", "Surgical history:", "psh -", "PSH"] {
            let r = applied("68M. " + header + " cholecystectomy 2015.")
            XCTAssertEqual(r.surgeries.count, 1, header)
            XCTAssertEqual(r.surgeries.first?.date, PatientMonthYear(year: 2015), header)
        }
        XCTAssertTrue(psh("PSH: none").isEmpty)
        XCTAssertTrue(psh("PSH: noncontributory").isEmpty)
        XCTAssertTrue(psh("PSH: denies").isEmpty)
        XCTAssertTrue(psh("No prior surgeries").isEmpty)
    }

    func testSeveralProceduresOnOneDateAreOneOperation() {
        let r = applied("PSH: Ascending aorta replacement + LM and RCA endarterectomy + AV repair 06/2025")
        XCTAssertEqual(r.surgeries.count, 1)
        let s = r.surgeries[0]
        XCTAssertEqual(s.date, m(6, 2025))
        XCTAssertEqual(s.procedures.count, 3)
        XCTAssertEqual(s.procedures[0].catalogID, "ascending-aorta")
        XCTAssertTrue(s.procedures[1].text.contains("LM and RCA endarterectomy"), s.procedures[1].text)
        XCTAssertEqual(s.procedures[2].catalogID, "av-repair")
        XCTAssertTrue(s.intrathoracic, "a cardiac operation")
        XCTAssertEqual(r.allIntrathoracic.count, 1)
    }

    func testSeparateOperationsAndADateOnItsOwn() {
        let r = applied("Past surgical history: appendectomy 2010 and cholecystectomy 2015, hernia repair, 2018")
        XCTAssertEqual(r.surgeries.count, 3)
        XCTAssertEqual(r.surgeries.map(\.date.year), [2010, 2015, 2018], "a date after a comma belongs to the operation before it")
    }

    func testSPForms() {
        let a = applied("CAD s/p CABG x3 2015, appendectomy 2010")
        XCTAssertEqual(a.surgeries.count, 2)
        XCTAssertEqual(a.surgeries.map(\.date.year), [2015, 2010])
        let b = applied("Status post cholecystectomy in 2012. Otherwise well.")
        XCTAssertEqual(b.surgeries.count, 1)
        XCTAssertEqual(b.surgeries[0].date, PatientMonthYear(year: 2012))
        let c = applied("h/o CABG 2019")
        XCTAssertEqual(c.surgeries.count, 1)
        XCTAssertEqual(c.surgeries[0].date, PatientMonthYear(year: 2019))
        XCTAssertEqual(c.surgeries[0].procedures.first?.catalogID, "cabg")
        let d = applied("s/p TKA 03/2019")
        XCTAssertEqual(d.surgeries.first?.date, m(3, 2019))
        let e = applied("hx of lap chole")
        XCTAssertEqual(e.surgeries.first?.procedures.first?.catalogID, "lap-chole")
    }

    func testOnlyOperationsAreRead() {
        XCTAssertTrue(psh("s/p fall from a ladder").isEmpty)
        XCTAssertTrue(psh("h/o HTN, DM2").isEmpty)
        XCTAssertTrue(psh("history of asthma").isEmpty)
        XCTAssertTrue(psh("No h/o surgery").isEmpty, "negated")
        XCTAssertTrue(psh("Father s/p CABG at 50").isEmpty, "family")
    }

    func testThePlannedProcedureIsNeverPastSurgery() {
        for note in ["Procedure: lap chole", "Scheduled for CABG.", "68M presents for AVR.", "Procedure: redo CABG. PSH: appendectomy 2010",
                     "PSH: appendectomy 2010, now presenting for redo CABG", "s/p CABG 2019 now presenting for AVR, MVR"] {
            let r = applied(note)
            for s in r.surgeries { XCTAssertFalse(s.text.lowercased().contains("lap chole") || s.text.contains("AVR") || s.text.contains("Mitral"), note + " → " + s.text) }
        }
        XCTAssertTrue(applied("Procedure: lap chole").surgeries.isEmpty)
        XCTAssertTrue(applied("Scheduled for CABG.").surgeries.isEmpty)
        XCTAssertTrue(applied("68M presents for AVR.").surgeries.isEmpty)
        let both = applied("Procedure: redo CABG. PSH: appendectomy 2010")
        XCTAssertEqual(both.surgeries.count, 1)
        XCTAssertEqual(both.surgeries[0].text, "Appendectomy (2010)")
        XCTAssertFalse(both.procedure.isEmpty, "the planned procedure is still the procedure")
        let cut = applied("s/p CABG 2019 now presenting for AVR, MVR")
        XCTAssertEqual(cut.surgeries.count, 1)
        XCTAssertEqual(cut.surgeries[0].procedures.first?.catalogID, "cabg")
    }

    func testNothingIsAddedTwice() {
        let once = applied("PSH: CABG x3 2019, appendectomy 2010")
        let twice = applied("PSH: CABG x3 2019, appendectomy 2010", to: once)
        XCTAssertEqual(twice.surgeries.count, 2)
        // The same operation said two ways in one note.
        let two = applied("CAD s/p CABG 2019. PSH: CABG x3, appendectomy")
        XCTAssertEqual(two.surgeries.count, 2, "CABG once")
        // An entry already there, typed by hand.
        var r = PatientRecord()
        r.surgeries = [PatientSurgery(name: "Appendectomy as child")]
        let again = applied("PSH: appendectomy 2010", to: r)
        XCTAssertEqual(again.surgeries.count, 1)
        for f in read("PSH: appendectomy 2010, cholecystectomy").findings where f.id.hasPrefix("psh:") {
            XCTAssertEqual(PatientNote.status(f, in: r) == .recorded, f.id.contains("appendectomy"), f.id)
        }
        // A different date is a different operation.
        var cabg = PatientRecord()
        cabg.surgeries = [PatientSurgery(procedures: [PlannedProcedure(name: "CABG")], date: PatientMonthYear(year: 2010))]
        XCTAssertEqual(applied("s/p CABG 2019", to: cabg).surgeries.count, 2)
        // The dates differ only by a missing month.
        XCTAssertEqual(applied("s/p CABG 06/2010", to: cabg).surgeries.count, 1)
    }

    func testIntrathoracicLinkStillUpdates() {
        let r = applied("PSH: CABG x3 2019, appendectomy 2010")
        XCTAssertEqual(r.allIntrathoracic.count, 1)
        XCTAssertEqual(r.allIntrathoracic.first?.text, "Coronary artery bypass grafting ×3 (2019)")
        XCTAssertTrue(PatientSummary.assessmentLines(r).contains { $0.label == "Previous intrathoracic surgery" && $0.text.contains("bypass") })
        let plain = applied("PSH: appendectomy 2010, tonsillectomy")
        XCTAssertTrue(plain.allIntrathoracic.isEmpty)
        XCTAssertFalse(PatientSummary.assessmentLines(plain).contains { $0.label == "Previous intrathoracic surgery" })
        // Typed chest operations that the list does not know.
        let chest = applied("PSH: right thoracotomy for a cyst 2012")
        XCTAssertTrue(chest.surgeries.first?.intrathoracic ?? false)
        // The cardiac page shows the first cardiac operation.
        XCTAssertEqual(PatientHistoryDetails.cardiacSurgeryText(r), "Coronary artery bypass grafting ×3")
    }

    func testCardiacOperationsFromTheCardiacReaderAreStructuredToo() {
        let r = applied("s/p CABG x3 2015, AVr 2020")
        XCTAssertEqual(r.surgeries.count, 2)
        XCTAssertEqual(r.surgeries[0].text, "Coronary artery bypass grafting ×3 (2015)")
        XCTAssertEqual(r.surgeries[1].procedures.first?.catalogID, "av-repair")
        XCTAssertEqual(r.surgeries[1].date, PatientMonthYear(year: 2020))
        XCTAssertTrue(r.surgeries.allSatisfy(\.intrathoracic))
        XCTAssertEqual(psh("s/p CABG x3 2015").count, 1, "one finding for the operation, not two")
        let bare = applied("AVR 2015, MVR 2017")
        XCTAssertTrue(bare.surgeries.isEmpty || bare.surgeries.allSatisfy { $0.date.year != nil }, "a bare valve in the list is read as before")
    }

    func testWhatIsLeftOfASurgicalSentenceStaysAnAnestheticNote() {
        let r = read("PSH: appendectomy 2010 under GA, uneventful. Meds: metoprolol.")
        XCTAssertEqual(r.previous, "under GA; uneventful")
        XCTAssertEqual(r.findings.filter { $0.id.hasPrefix("psh:") }.count, 1)
        XCTAssertEqual(read("PSH: tonsillectomy as child, no anesthetic complications.").previous, "no anesthetic complications")
    }

    func testSectionWithBulletedLines() {
        let note = "PSH:\n- appendectomy 2010\n- TEVAR 08/2022\nMeds: metoprolol, aspirin\nAllergies: NKDA"
        let r = applied(note)
        XCTAssertEqual(r.surgeries.count, 2)
        XCTAssertEqual(r.surgeries.map(\.date.year), [2010, 2022])
        XCTAssertFalse(r.surgeries.contains { $0.text.lowercased().contains("metoprolol") })
        // Lines with no bullets, each an operation.
        let plain = applied("PSH:\nappendectomy 2010\nCABG 2019\nMeds: metoprolol")
        XCTAssertEqual(plain.surgeries.count, 2)
        // A line after the header that is another section's is not one of its items.
        let stop = applied("PSH:\nProcedure: redo CABG\nHPI: chest pain")
        XCTAssertTrue(stop.surgeries.isEmpty)
    }

    func testQuickAddReadsItTheSameWay() {
        let line = "PSH: appendectomy 2010, TEVAR 08/2022"
        let q = QuickAdd.read(line, record: PatientRecord(), tab: .preop, now: now)
        let n = read(line).findings.filter { $0.id.hasPrefix("psh:") }
        XCTAssertEqual(q.findings.filter { $0.id.hasPrefix("psh:") }.map(\.id), n.map(\.id))
        XCTAssertEqual(n.count, 2)
        var rec = PatientRecord()
        PatientNote.apply(q.findings.map(\.change), to: &rec)
        XCTAssertEqual(rec.surgeries.map(\.text), applied(line).surgeries.map(\.text), "the bar and the note file the same entries")
        XCTAssertEqual(rec.surgeries.count, 2)
        // Not filed from what happens in the OR.
        let intra = QuickAdd.read(line, record: PatientRecord(), tab: .intraop, now: now)
        XCTAssertTrue(intra.findings.filter { $0.id.hasPrefix("psh:") }.isEmpty)
        // Shown as one chip each, new until filed.
        let chips = QuickAdd.chips(q, record: PatientRecord())
        XCTAssertEqual(chips.filter { $0.id.hasPrefix("psh:") }.count, 2)
        XCTAssertTrue(chips.filter { $0.id.hasPrefix("psh:") }.allSatisfy { $0.canAdd })
    }

    func testPatternsCompile() {
        for rx in PastSurgeryNote.allPatterns { XCTAssertNotNil(rx.re, rx.pattern) }
    }

    func testDateReading() {
        XCTAssertEqual(PastSurgeryNote.extractDate("CABG x3 2019").1, PatientMonthYear(year: 2019))
        XCTAssertEqual(PastSurgeryNote.extractDate("CABG x3 2019").0, "CABG x3")
        XCTAssertEqual(PastSurgeryNote.extractDate("TEVAR 08/2022").1, m(8, 2022))
        XCTAssertEqual(PastSurgeryNote.extractDate("TEVAR (June 2015)").1, m(6, 2015))
        XCTAssertEqual(PastSurgeryNote.extractDate("lap chole in 2012").0, "lap chole")
        XCTAssertTrue(PastSurgeryNote.extractDate("T10-11 fusion").1.isEmpty, "a spinal level is not a date")
    }

    // MARK: Review fixes (1.8.3)

    /// The dates a note may give: MM/YYYY, a year, a month and year, and an apostrophe year. Never M/D or MM/YY.
    func testNotesNeverReadADayOrTwoDigitsAsAYear() {
        for text in ["appy 6/30", "L4-5 laminectomy 3/22", "TKA 6/19", "cholecystectomy 12/95", "TKA 6.19", "hernia repair 10/28"] {
            XCTAssertTrue(PastSurgeryNote.extractDate(text).1.isEmpty, text)
        }
        XCTAssertEqual(PastSurgeryNote.extractDate("TKA 6/'19").1, m(6, 2019))
        XCTAssertEqual(PastSurgeryNote.extractDate("TKA 6/'19").0, "TKA")
        XCTAssertEqual(PastSurgeryNote.extractDate("cholecystectomy '15").1, PatientMonthYear(year: 2015))
        XCTAssertEqual(PastSurgeryNote.extractDate("cholecystectomy ’15").1, PatientMonthYear(year: 2015), "a typographic apostrophe")
        XCTAssertTrue(PastSurgeryNote.extractDate("cholecystectomy '95").1.isEmpty, "never a 19xx year from two digits (and 2095 is not a date)")
        XCTAssertEqual(PastSurgeryNote.extractDate("TKA 06/2019").1, m(6, 2019))
        XCTAssertEqual(PastSurgeryNote.extractDate("TKA 6/2019").1, m(6, 2019))
        XCTAssertEqual(PastSurgeryNote.extractDate("TKA March 2019").1, m(3, 2019))
        let r = applied("s/p appy 6/30")
        XCTAssertEqual(r.surgeries.count, 1)
        XCTAssertTrue(r.surgeries[0].date.isEmpty, "not June 1930")
        XCTAssertEqual(applied("s/p TKA 6/'19").surgeries.first?.date, m(6, 2019))
        XCTAssertEqual(applied("PSH: cholecystectomy '15, TKA 6/19").surgeries.map(\.date.year), [2015, nil])
    }

    func testADiagnosisThatIsAlsoAnAliasIsNotAnOperation() {
        for note in ["h/o AAA 4.5 cm", "h/o type A dissection", "history of hiatal hernia", "h/o ectopic pregnancy", "history of hip fracture", "prior AAA",
                     "s/p aortic dissection", "hx of ovarian cyst", "h/o hernia", "PSH: AAA 4.5 cm", "PSH: hiatal hernia", "PSH: ectopic pregnancy"] {
            let r = applied(note)
            XCTAssertTrue(r.surgeries.isEmpty, note + " → " + r.surgeries.map(\.text).joined(separator: "; "))
            XCTAssertNil(r.hx.cardiacSurgeryID, note)
            XCTAssertTrue(psh(note).isEmpty, note)
        }
    }

    func testTheOperationIsStillReadWhenItSaysSo() {
        for note in ["h/o AAA repair 2018", "s/p CABG", "prior TAVR 2020", "h/o EVAR 2017", "history of hip fracture ORIF 2019", "h/o hiatal hernia repair 2015",
                     "s/p type A dissection repair 2021", "PSH: AAA repair 2018", "PSH: lap chole for gallstones 2015"] {
            XCTAssertEqual(applied(note).surgeries.count, 1, note)
        }
        XCTAssertEqual(applied("s/p CABG").surgeries.first?.procedures.first?.catalogID, "cabg")
        XCTAssertEqual(applied("PSH: lap chole for gallstones 2015").surgeries.first?.procedures.first?.catalogID, "lap-chole")
        XCTAssertEqual(applied("s/p lap chole 2015, appendectomy 2010, ORIF R ankle").surgeries.count, 3)
    }

    /// 1.8.3 re-check: after "h/o", "Hx" or "prior", a procedure-list alias that names a diagnosis is not an operation;
    /// an operative word, an eponym or an operation abbreviation is needed. "s/p" still reads the list.
    func testAHistoryLeadNeedsAnOperativeWord() {
        for note in ["h/o scoliosis", "Hx: scoliosis", "h/o adolescent idiopathic scoliosis", "h/o coarctation", "history of neuroblastoma",
                     "h/o acoustic neuroma", "h/o varicose veins", "h/o varicocele", "h/o hydrocele", "h/o Achilles tendon rupture",
                     "h/o Lisfranc injury", "h/o rectovaginal fistula", "h/o anal fistula", "prior popliteal entrapment", "h/o midgut volvulus",
                     "h/o epiphrenic diverticulum", "Hx of esophageal leiomyoma"] {
            let r = applied(note)
            XCTAssertTrue(r.surgeries.isEmpty, note + " → " + r.surgeries.map(\.text).joined(separator: "; "))
            XCTAssertNil(r.hx.cardiacSurgeryID, note)
            XCTAssertTrue(psh(note).isEmpty, note)
        }
        for note in ["h/o Whipple 2019", "h/o lap chole", "prior VATS", "h/o TKA 2018", "Hx CABG 2015", "h/o Nissen fundoplication",
                     "s/p scoliosis fusion 2010", "s/p coarctation repair", "h/o hiatal hernia repair 2015", "history of Bentall procedure"] {
            XCTAssertEqual(applied(note).surgeries.count, 1, note)
        }
        XCTAssertTrue(PastSurgeryNote.isHistoryLead("h/o "))
        XCTAssertTrue(PastSurgeryNote.isHistoryLead("Hx: "))
        XCTAssertFalse(PastSurgeryNote.isHistoryLead("s/p "))
        XCTAssertFalse(PastSurgeryNote.isHistoryLead("Status post "))
    }

    func testAPlanningWordDropsTheItemWhole() {
        for note in ["s/p PCI 2020, CABG scheduled 11/4", "s/p LHC 10/28 showing 3VD, referred for CABG", "s/p appendectomy 2010, awaiting CABG",
                     "s/p CABG 2019, needs AVR", "s/p PCI 2020; candidate for CABG", "s/p lap chole 2015, booked for AVR",
                     "s/p PCI 2020, CABG planned", "s/p PCI 2020, CABG pending", "h/o PCI 2018, presents for CABG", "s/p PCI 2020, CABG for 3VD next week"] {
            let r = applied(note)
            for s in r.surgeries {
                XCTAssertFalse(s.text.lowercased().contains("bypass") && !note.contains("CABG 2019"), note + " → " + s.text)
                XCTAssertFalse(s.text.contains("Aortic valve") || s.text.lowercased().contains("sternotomy"), note + " → " + s.text)
            }
        }
        let a = applied("s/p PCI 2020, CABG scheduled 11/4")
        XCTAssertEqual(a.surgeries.count, 1, "PCI only: " + a.surgeries.map(\.text).joined(separator: "; "))
        XCTAssertEqual(a.surgeries.first?.date, PatientMonthYear(year: 2020))
        XCTAssertNil(a.surgeries.first { $0.text.lowercased().contains("bypass") })
        let b = applied("s/p LHC 10/28 showing 3VD, referred for CABG")
        XCTAssertFalse(b.surgeries.contains { $0.text.lowercased().contains("bypass") || $0.text.contains("CABG") })
        XCTAssertTrue(b.surgeries.allSatisfy { $0.date.year != 1928 })
        // A list stops at a planning word: what follows it is not read.
        let c = applied("s/p appendectomy 2010, needs AVR, cholecystectomy 2015")
        XCTAssertEqual(c.surgeries.count, 1)
    }

    func testASectionMayStateWhatAnOperationWasFor() {
        let r = applied("PSH: lap chole for gallstones 2015, appendectomy for appendicitis")
        XCTAssertEqual(r.surgeries.count, 2)
        XCTAssertTrue(applied("s/p repair for hernia").surgeries.isEmpty, "after s/p a bare for is a planning word")
    }

    // MARK: Ben's abbreviations: Hx, PSHx, PMH, AAA, AKI

    private func ids(_ s: String) -> Set<String> { Set(read(s).findings.map(\.id)) }

    func testTheAbbreviationsAreInTheList() {
        for (key, meaning) in [("Hx", "history"), ("hx", "history"), ("PSH", "past surgical history"), ("PSHx", "past surgical history"),
                               ("PMH", "past medical history"), ("PMHx", "past medical history"), ("AAA", "abdominal aortic aneurysm"),
                               ("AKI", "acute kidney injury"), ("FHx", "family history")] {
            let a = MedAbbreviations.lookup(key)
            XCTAssertEqual(a?.meanings.first?.text, meaning, key)
            XCTAssertEqual(a?.isAmbiguous, false, key + " has one meaning, so it is read as written and a header is still a header")
        }
    }

    func testHxIsAHistoryLead() {
        XCTAssertEqual(applied("Hx CABG 2015").surgeries.count, 1)
        XCTAssertEqual(applied("Hx CABG 2015").surgeries.first?.date, PatientMonthYear(year: 2015))
        XCTAssertEqual(applied("Hx of appendectomy 2010").surgeries.first?.date, PatientMonthYear(year: 2010))
        XCTAssertEqual(applied("Hx: cholecystectomy 2012, appendectomy 2010").surgeries.count, 2)
        XCTAssertEqual(applied("hx lap chole").surgeries.count, 1)
        XCTAssertEqual(applied("Hx CABG").surgeries.first?.procedures.first?.catalogID, "cabg")
        // The diagnosis rule applies to it as to h/o.
        for note in ["Hx of AAA", "Hx AAA 4.5 cm", "Hx: type A dissection", "Hx of hiatal hernia", "Hx of ectopic pregnancy"] {
            XCTAssertTrue(applied(note).surgeries.isEmpty, note)
        }
        XCTAssertEqual(applied("Hx of AAA repair 2018").surgeries.count, 1)
        // And the planning rule.
        XCTAssertTrue(applied("Hx of PCI, CABG scheduled").surgeries.allSatisfy { !$0.text.lowercased().contains("bypass") })
    }

    func testFHxIsNeverAHistoryLead() {
        for note in ["FHx: CABG 2015", "FHx CABG", "FHx: appendectomy 2010", "FHx of AAA repair", "Family hx: appendectomy 2010", "SHx: tobacco, appendectomy"] {
            let r = applied(note)
            XCTAssertTrue(r.surgeries.isEmpty, note + " → " + r.surgeries.map(\.text).joined(separator: "; "))
        }
    }

    func testPSHxWithAndWithoutAColon() {
        for note in ["PSHx: appendectomy 2010", "PSHx appendectomy 2010", "PSH: appendectomy 2010", "PSH appendectomy 2010", "pshx - appendectomy 2010",
                     "Past surgical history: appendectomy 2010", "Surgical history: appendectomy 2010"] {
            let r = applied(note)
            XCTAssertEqual(r.surgeries.count, 1, note)
            XCTAssertEqual(r.surgeries.first?.date, PatientMonthYear(year: 2010), note)
        }
        XCTAssertEqual(applied("PSHx CABG 2015, TEVAR 08/2022").surgeries.count, 2)
    }

    func testAPMHHeaderEndsASurgicalHistoryAndItsItemsAreDiagnoses() {
        // The same sentence.
        let a = applied("PSH: appendectomy 2010, PMH: HTN, AAA 4.8 cm, hernia, AKI 2024")
        XCTAssertEqual(a.surgeries.map(\.text), ["Appendectomy (2010)"])
        // Another sentence, and another line.
        XCTAssertEqual(applied("PSH: appendectomy 2010. PMH: HTN, hernia, hiatal hernia").surgeries.count, 1)
        XCTAssertEqual(applied("PSH:\n- appendectomy 2010\nPMH:\n- HTN\n- AAA 4.8 cm\n- hernia").surgeries.count, 1)
        XCTAssertEqual(applied("PSHx: appendectomy 2010\nPMHx: HTN, AAA").surgeries.count, 1)
        XCTAssertEqual(applied("PSH: appendectomy 2010. Past medical history: HTN, ectopic pregnancy").surgeries.count, 1)
        // After a PMH header: diagnoses are not operations.
        for note in ["PMH: HTN, AAA 4.8 cm, hernia, hip fracture, ectopic pregnancy", "PMHx: DM2, hiatal hernia", "Past medical history: HTN, AAA"] {
            XCTAssertTrue(applied(note).surgeries.isEmpty, note)
        }
        // An s/p after it is still read, in the same sentence as the surgical history or not.
        XCTAssertEqual(applied("PSH: appendectomy 2010, PMH: HTN, s/p cholecystectomy 2012").surgeries.count, 2)
    }

    func testBensExamplePMHSentence() {
        let note = "PMH: HTN, AAA 4.8 cm, AKI 2024, s/p CABG 2015"
        let found = ids(note)
        XCTAssertTrue(found.contains("problem:htn"))
        XCTAssertTrue(found.contains("problem:aaa"), "AAA is the history item")
        XCTAssertTrue(found.contains("problem:aki"), "AKI is the history item")
        let r = applied(note)
        XCTAssertEqual(r.surgeries.count, 1, "past surgery for the CABG 2015 only: " + r.surgeries.map(\.text).joined(separator: "; "))
        XCTAssertEqual(r.surgeries.first?.procedures.first?.catalogID, "cabg")
        XCTAssertEqual(r.surgeries.first?.date, PatientMonthYear(year: 2015))
        XCTAssertTrue(r.has("aaa"))
        XCTAssertTrue(r.has("aki"))
    }

    func testAAAAndAKIFileTheHistoryItemNeverASurgery() {
        for note in ["AAA 4.8 cm", "AAA", "known AAA", "h/o AAA", "Hx of AAA 5.2 cm", "PMH: AAA", "PSH: none. PMH: AAA 4.8 cm", "AKI", "AKI 2024", "h/o AKI",
                     "PMH: AKI 2024", "Hx AKI"] {
            let r = applied(note)
            XCTAssertTrue(r.surgeries.isEmpty, note + " → " + r.surgeries.map(\.text).joined(separator: "; "))
            XCTAssertNil(r.hx.cardiacSurgeryID, note)
        }
        XCTAssertTrue(ids("AAA 4.8 cm").contains("problem:aaa"))
        XCTAssertTrue(ids("h/o AAA").contains("problem:aaa") || applied("h/o AAA").has("aaa"), "the history item")
        XCTAssertTrue(ids("AKI 2024").contains("problem:aki"))
        XCTAssertTrue(applied("AAA 4.8 cm").has("aaa"))
        XCTAssertTrue(applied("AKI").has("aki"))
    }
}
