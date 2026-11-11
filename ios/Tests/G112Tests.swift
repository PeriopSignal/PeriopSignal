import XCTest
@testable import PeriopSignal

/// 1.12, helper G (Ben, Nov 11): a day in dates (part 1), the Type & Screen expiration (part 2), and no "H" or "L" beside a
/// lab value (part 3). "Today" is a fixed 11 November 2026, 08:00.
final class G112Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 8))! }
    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    private func my(_ s: String) -> PatientMonthYear? { PatientMonthYear.parse(s, now: now) }
    private func d(_ m: Int?, _ day: Int?, _ y: Int) -> PatientMonthYear { PatientMonthYear(month: m, day: day, year: y) }

    // MARK: Part 1: the day is optional

    func testARecordSavedBeforeHasNoDay() throws {
        let old = try JSONDecoder().decode(PatientMonthYear.self, from: Data(#"{"month":6,"year":2015}"#.utf8))
        XCTAssertEqual(old, PatientMonthYear(month: 6, year: 2015))
        XCTAssertNil(old.day)
        XCTAssertEqual(old.text, "06/2015")
        // A month and year still encodes as before (no day key); a day round-trips.
        let plain = String(decoding: try JSONEncoder().encode(PatientMonthYear(month: 6, year: 2015)), as: UTF8.self)
        XCTAssertFalse(plain.contains("day"), plain)
        let full = try JSONDecoder().decode(PatientMonthYear.self, from: JSONEncoder().encode(d(6, 14, 2015)))
        XCTAssertEqual(full, d(6, 14, 2015))
        XCTAssertEqual(full.day, 14)
        // A whole 1.11 patient with a surgery dated by month and year opens unchanged.
        let json = #"{"surgeries":[{"name":"Appendectomy","date":{"month":3,"year":2019}}]}"#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.surgeries.first?.date, PatientMonthYear(month: 3, year: 2019))
        XCTAssertTrue(r.surgeries.first?.text.hasSuffix("(03/2019)") ?? false)
    }

    func testADayNeedsAMonthAndAYearAndARealDate() {
        XCTAssertNil(PatientMonthYear(month: nil, day: 14, year: 2015).day)
        XCTAssertNil(PatientMonthYear(month: 6, day: 14, year: nil).day)
        XCTAssertNil(PatientMonthYear(month: 2, day: 30, year: 2024).day)
        XCTAssertNil(PatientMonthYear(month: 2, day: 29, year: 2023).day)
        XCTAssertEqual(PatientMonthYear(month: 2, day: 29, year: 2024).day, 29)
        XCTAssertNil(PatientMonthYear(month: 13, day: 1, year: 2024).day)
    }

    func testTheOneFieldTakesAYearAMonthAndYearAndAFullDate() {
        XCTAssertEqual(my("2015"), PatientMonthYear(year: 2015))
        XCTAssertEqual(my("06/2015"), PatientMonthYear(month: 6, year: 2015))
        XCTAssertEqual(my("06/14/2015"), d(6, 14, 2015))
        XCTAssertEqual(my("6/14/2015"), d(6, 14, 2015))
        XCTAssertEqual(my("6/14/15"), d(6, 14, 2015), "the two-digit-year rule the parser already uses")
        XCTAssertEqual(my("6-14-2015"), d(6, 14, 2015))
        XCTAssertEqual(my("2015-06-14"), d(6, 14, 2015))
        XCTAssertEqual(my("Jun 14 2015"), d(6, 14, 2015))
        XCTAssertEqual(my("June 14, 2015"), d(6, 14, 2015))
        XCTAssertEqual(my("06142015"), d(6, 14, 2015))
        XCTAssertEqual(my("2/29/2024"), d(2, 29, 2024))
        // Only three numbers make a day: 06/15 stays June 2015.
        XCTAssertEqual(my("06/15"), PatientMonthYear(month: 6, year: 2015))
        XCTAssertEqual(my("06/2015")?.text, "06/2015")
        XCTAssertEqual(my("06/14/2015")?.text, "06/14/2015")
    }

    func testAnImpossibleDateIsNotRead() {
        XCTAssertNil(my("02/30/2024"))
        XCTAssertNil(my("02/29/2023"))
        XCTAssertNil(my("13/14/2015"), "month 13")
        XCTAssertNil(my("14/6/2015"), "never guessed to be day first")
        XCTAssertNil(my("06/32/2015"))
        XCTAssertNil(my("06/00/2015"))
        XCTAssertNil(my("06142015x"))
        XCTAssertNil(my("13142015"))
        // What it did for a bad month and year it still does.
        XCTAssertNil(my("13/2019"))
        XCTAssertNil(my("soon"))
    }

    func testEqualityHashingAndSortingTakeTheDayIntoAccount() {
        XCTAssertNotEqual(d(6, 14, 2015), PatientMonthYear(month: 6, year: 2015))
        XCTAssertNotEqual(d(6, 14, 2015), d(6, 15, 2015))
        XCTAssertEqual(Set([d(6, 14, 2015), d(6, 14, 2015), PatientMonthYear(month: 6, year: 2015)]).count, 2)
        let sorted = [d(6, 14, 2015), PatientMonthYear(year: 2015), d(6, 2, 2015), PatientMonthYear(month: 6, year: 2015), PatientMonthYear(year: 2014)].sorted()
        XCTAssertEqual(sorted.map(\.text), ["2014", "2015", "06/2015", "06/02/2015", "06/14/2015"])
    }

    func testADateWithADayAndTheSameWithoutOneAreOneDateAndTheFullerIsKept() {
        let full = PatientSurgery(name: "Appendectomy", date: d(6, 14, 2015))
        XCTAssertTrue(PastSurgeryNote.same(full, PatientSurgery(name: "Appendectomy", date: PatientMonthYear(month: 6, year: 2015))))
        XCTAssertTrue(PastSurgeryNote.same(full, PatientSurgery(name: "Appendectomy", date: PatientMonthYear(year: 2015))))
        XCTAssertFalse(PastSurgeryNote.same(full, PatientSurgery(name: "Appendectomy", date: d(6, 15, 2015))), "another day is another date")
        XCTAssertFalse(PastSurgeryNote.same(full, PatientSurgery(name: "Appendectomy", date: PatientMonthYear(month: 7, year: 2015))))
        XCTAssertEqual(PatientMonthYear.fuller(PatientMonthYear(year: 2015), d(6, 14, 2015)), d(6, 14, 2015))
        XCTAssertEqual(PatientMonthYear.fuller(d(6, 14, 2015), PatientMonthYear(month: 6, year: 2015)), d(6, 14, 2015))
        XCTAssertEqual(PatientMonthYear.fuller(PatientMonthYear(), d(6, 14, 2015)), d(6, 14, 2015))
        XCTAssertEqual(PatientMonthYear.fuller(d(6, 14, 2015), d(6, 15, 2015)), d(6, 14, 2015), "dates that disagree: the first stays")
        // Entered twice, once with the day: one entry, with the day, whichever came first.
        var r = PatientRecord()
        PastSurgeryNote.add("appendectomy", PatientMonthYear(month: 6, year: 2015), to: &r)
        PastSurgeryNote.add("appendectomy", d(6, 14, 2015), to: &r)
        XCTAssertEqual(r.surgeries.count, 1)
        XCTAssertEqual(r.surgeries.first?.date, d(6, 14, 2015))
        var q = PatientRecord()
        PastSurgeryNote.add("appendectomy", d(6, 14, 2015), to: &q)
        PastSurgeryNote.add("appendectomy", PatientMonthYear(month: 6, year: 2015), to: &q)
        XCTAssertEqual(q.surgeries.count, 1)
        XCTAssertEqual(q.surgeries.first?.date, d(6, 14, 2015))
    }

    /// What the field holds after these characters are typed one at a time (the field runs the formatter on its own output).
    private func typed(_ s: String, from start: String = "") -> String {
        var text = start
        for ch in s {
            let raw = text + String(ch)
            var shown = PatientMonthYear.typing(raw, was: text)
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

    func testTypingAFullDateIntoTheField() {
        XCTAssertEqual(typed("06/14/2015"), "06/14/2015")
        XCTAssertEqual(typed("6/4/2015"), "06/04/2015")
        XCTAssertEqual(typed("6 14 2015"), "06/14/2015", "a space after the month and the day is the slash")
        XCTAssertEqual(typed("06/14/"), "06/14/")
        XCTAssertEqual(typed("06/14/20"), "06/14/20")
        XCTAssertEqual(typed("06/14/201512"), "06/14/2015", "no more than four digits of year")
        // As before: month and year, and a year alone.
        XCTAssertEqual(typed("06/2015"), "06/2015")
        XCTAssertEqual(typed("062026"), "06/2026")
        XCTAssertEqual(typed("2015"), "2015")
        // A day that cannot be one is left to the old reading.
        XCTAssertEqual(typed("06/45/"), "06/45")
        // Backspace goes back through the second slash.
        XCTAssertEqual(PatientMonthYear.typing("06/14", was: "06/14/"), "06/14")
        // Pasted: digits that read as a whole date.
        XCTAssertEqual(PatientMonthYear.typing("06142015", was: ""), "06/14/2015")
    }

    func testAFullDateIsSettledOnlyOnceItsYearIsTyped() {
        XCTAssertNil(PatientMonthYear.parseTyped("06/14/", now: now))
        XCTAssertNil(PatientMonthYear.parseTyped("06/14/201", now: now))
        XCTAssertEqual(PatientMonthYear.parseTyped("06/14/2015", now: now), d(6, 14, 2015))
        XCTAssertEqual(PatientMonthYear.parseTyped("06/14/15", now: now), d(6, 14, 2015))
        XCTAssertEqual(PatientMonthYear.parseTyped("06/2015", now: now), PatientMonthYear(month: 6, year: 2015))
    }

    func testThePlaceholderAndTheLabelSayTheDayIsOptional() {
        XCTAssertEqual(PatientMonthYear.placeholder, "MM/YYYY or MM/DD/YYYY")
        XCTAssertTrue(PatientMonthYear.accessibilityLabel("Date").contains("the day is optional"))
        XCTAssertTrue(PatientMonthYear.accessibilityLabel("Date").hasPrefix("Date"))
    }

    // MARK: Part 1: typing

    private func read(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func applied(_ text: String, to start: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = start
        PatientNote.apply(read(text).findings.map(\.change), to: &r)
        return r
    }
    private func psh(_ line: String) -> QuickAddReading {
        QuickAdd.read(line, record: PatientRecord(), tab: .preop, now: now, surgicalHistory: true)
    }
    private func pastSurgeries(_ q: QuickAddReading) -> [(String, PatientMonthYear)] {
        q.findings.compactMap { f in
            if case .pastSurgery(let t, let date) = f.change { return (t, date) }
            return nil
        }
    }

    func testAFullDateIsReadWhereAMonthAndYearIsRead() {
        let a = PastSurgeryNote.extractDate("appendectomy 6/14/2015", now: now)
        XCTAssertEqual(a.0, "appendectomy")
        XCTAssertEqual(a.1, d(6, 14, 2015))
        let b = PastSurgeryNote.extractDate("CABG on 5/1/2019", now: now)
        XCTAssertEqual(b.0, "CABG")
        XCTAssertEqual(b.1, d(5, 1, 2019))
        let c = PastSurgeryNote.extractDate("TKA 6/14/15", now: now)
        XCTAssertEqual(c.0, "TKA")
        XCTAssertEqual(c.1, d(6, 14, 2015), "two digits of year as the field reads them")
        let e = PastSurgeryNote.extractDate("PCI June 14, 2015", now: now)
        XCTAssertEqual(e.0, "PCI")
        XCTAssertEqual(e.1, d(6, 14, 2015))
        // Unchanged: a month and year, a year, and never M/D or MM/YY.
        XCTAssertEqual(PastSurgeryNote.extractDate("TEVAR 08/2022", now: now).1, PatientMonthYear(month: 8, year: 2022))
        XCTAssertEqual(PastSurgeryNote.extractDate("CABG x3 in 2019", now: now).1, PatientMonthYear(year: 2019))
        XCTAssertTrue(PastSurgeryNote.extractDate("appy 6/30", now: now).1.isEmpty)
        XCTAssertTrue(PastSurgeryNote.extractDate("appy 06/15", now: now).1.isEmpty)
    }

    func testTheQuickLineAndTheNoteReaderFileAFullDate() {
        XCTAssertEqual(pastSurgeries(psh("appendectomy 6/14/2015")).first?.1, d(6, 14, 2015))
        XCTAssertEqual(pastSurgeries(psh("appendectomy 6/14/2015")).first?.0, "appendectomy")
        let two = pastSurgeries(psh("PSH: appendectomy 6/14/2015, CABG x3 5/1/2019"))
        XCTAssertEqual(two.map(\.1), [d(6, 14, 2015), d(5, 1, 2019)])
        // "s/p CABG on 5/1/2019" in a note.
        let r = applied("s/p CABG on 5/1/2019")
        XCTAssertEqual(r.surgeries.count, 1)
        XCTAssertEqual(r.surgeries.first?.date, d(5, 1, 2019))
        XCTAssertEqual(applied("s/p appendectomy 6/14/2015").surgeries.first?.date, d(6, 14, 2015))
        XCTAssertEqual(applied("PSH: appendectomy 6/14/2015").surgeries.first?.date, d(6, 14, 2015))
        // An echo with a full date: no surgery is made of it, and the date is not taken for one.
        XCTAssertTrue(pastSurgeries(psh("TTE 3/2/2026: EF 55%")).isEmpty)
        XCTAssertTrue(applied("TTE 3/2/2026: EF 55%").surgeries.isEmpty)
    }

    func testAFullDateThatIsNotASurgeryDateIsNotOne() {
        XCTAssertTrue(applied("DOB 3/14/1958").surgeries.isEmpty)
        XCTAssertTrue(read("DOB 3/14/1958").findings.filter { $0.id.hasPrefix("psh:") }.isEmpty)
        XCTAssertTrue(pastSurgeries(psh("DOB 3/14/1958")).isEmpty)
        XCTAssertTrue(pastSurgeries(psh("K 5.4 on 11/10/2026")).isEmpty, "a lab draw is not a surgery")
        XCTAssertTrue(applied("K 5.4 on 11/10/2026").surgeries.isEmpty)
        XCTAssertTrue(applied("PSH: K 5.4 on 11/10/2026").surgeries.isEmpty)
        // Today's date is not a past surgery's: it is taken out of the words and the operation is left undated.
        let today = PastSurgeryNote.extractDate("CABG 11/11/2026", now: now)
        XCTAssertEqual(today.0, "CABG")
        XCTAssertTrue(today.1.isEmpty)
        XCTAssertTrue(PastSurgeryNote.extractDate("CABG 12/25/2026", now: now).1.isEmpty, "a later date neither")
        XCTAssertEqual(PastSurgeryNote.extractDate("CABG 11/10/2026", now: now).1, d(11, 10, 2026), "yesterday is a past date")
    }

    func testAStressTestIsDatedByAFullDate() {
        func stress(_ line: String) -> PatientStressTest? {
            let q = QuickAdd.read(line, record: PatientRecord(), tab: .preop, now: now)
            if case .stressTest(let t)? = q.findings.first(where: { $0.id == "stress" })?.change { return t }
            return nil
        }
        XCTAssertEqual(stress("DSE 03/14/2025 negative")?.date, d(3, 14, 2025))
        XCTAssertEqual(stress("DSE 03/14/2025 negative")?.result, .negative)
        XCTAssertEqual(stress("DSE negative 3/14/2025")?.date, d(3, 14, 2025))
        // Unchanged: a month and year, a year.
        XCTAssertEqual(stress("DSE negative 03/2025")?.date, PatientMonthYear(month: 3, year: 2025))
        XCTAssertEqual(stress("DSE 2024 negative")?.date, PatientMonthYear(year: 2024))
        let t = PatientStressTest(kind: .dobutamine, result: .negative, date: d(3, 14, 2025))
        XCTAssertEqual(QuickAdd.stressText(t), "DSE negative (03/14/2025)")
        XCTAssertEqual(t.summary, "Dobutamine stress test (03/14/2025): negative, no ischemia")
    }

    // MARK: Part 1: display

    func testTheDayShowsInTheAppAndInASummaryOnlyWhenRecent() {
        // 90 days before 11 Nov 2026 is 13 Aug 2026.
        XCTAssertEqual(d(8, 13, 2026).summaryText(now: now), "08/13/2026", "90 days ago: the day shows")
        XCTAssertEqual(d(8, 12, 2026).summaryText(now: now), "08/2026", "91 days ago: month and year")
        XCTAssertEqual(d(11, 11, 2026).summaryText(now: now), "11/11/2026", "today")
        XCTAssertEqual(d(11, 12, 2026).summaryText(now: now), "11/2026", "not a past date: month and year")
        XCTAssertEqual(d(6, 14, 2015).summaryText(now: now), "06/2015")
        XCTAssertEqual(PatientMonthYear(month: 10, year: 2026).summaryText(now: now), "10/2026", "no day: as it is")
        XCTAssertEqual(PatientMonthYear(year: 2015).summaryText(now: now), "2015")
        XCTAssertEqual(d(6, 14, 2015).shown(.app), "06/14/2015")
        XCTAssertEqual(d(6, 14, 2015).shown(.summary(now: now)), "06/2015")
        XCTAssertEqual(d(6, 14, 2015).text, "06/14/2015", "in the app")
    }

    private var datedRecord: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 70; r.sex = .male
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        r.surgeries = [PatientSurgery(name: "PCI with stent to the LAD", date: d(10, 21, 2026)),
                       PatientSurgery(name: "Appendectomy", date: d(6, 14, 2015))]
        var echo = PatientEcho()
        echo.study = "TTE"; echo.date = d(3, 2, 2026); echo.lvef = 55
        r.echoFindings = echo
        var lhc = PatientLHC()
        lhc.dominance = "right"; lhc.date = d(10, 18, 2026)
        r.lhc = lhc
        r.stressTest = PatientStressTest(kind: .dobutamine, result: .negative, date: d(3, 14, 2025))
        r.rhc.ra = 8; r.rhc.date = d(10, 1, 2026)
        return r
    }

    func testTheAppShowsTheFullDate() {
        let r = datedRecord
        XCTAssertTrue(r.surgeries[1].text.hasSuffix("(06/14/2015)"), r.surgeries[1].text)
        XCTAssertTrue(r.surgeries[0].text.hasSuffix("(10/21/2026)"), r.surgeries[0].text)
        XCTAssertTrue(r.echoFindings.summary.hasPrefix("TTE 03/02/2026"), r.echoFindings.summary)
        XCTAssertTrue(r.lhc.summary.hasPrefix("LHC 10/18/2026"), r.lhc.summary)
        XCTAssertEqual(r.stressTest.summary, "Dobutamine stress test (03/14/2025): negative")
        // The lines the tab's boxes use keep the day too.
        let assess = PatientSummary.assessmentLines(r)
        XCTAssertTrue(assess.contains { $0.label == "Echo" && $0.text.contains("03/02/2026") })
    }

    func testBothSummariesShowTheDayOnlyForARecentDate() {
        let r = datedRecord
        for kind in [PatientBriefs.Kind.preop, .handoff] {
            let blocks = PatientBriefs.blocks(kind, r, now: now)
            let psh = blocks.first { $0.key == "psh" }?.text ?? ""
            XCTAssertTrue(psh.contains("(10/21/2026)"), "\(kind): " + psh)
            XCTAssertTrue(psh.contains("(06/2015)"), "\(kind): " + psh)
            XCTAssertFalse(psh.contains("06/14/2015"), "\(kind): " + psh)
            let workup = blocks.first { $0.key == "workup" }?.text ?? ""
            XCTAssertTrue(workup.contains("TTE 03/2026"), "\(kind): " + workup)
            XCTAssertFalse(workup.contains("03/02/2026"), "\(kind): " + workup)
            XCTAssertTrue(workup.contains("LHC 10/18/2026"), "\(kind): " + workup)
            XCTAssertTrue(workup.contains("03/2025"), "\(kind): " + workup)
            XCTAssertFalse(workup.contains("03/14/2025"), "\(kind): " + workup)
            XCTAssertTrue(workup.contains("RHC 10/01/2026"), "\(kind): " + workup)
            // What is copied or shared is the same text.
            let copied = PatientBriefs.sharedText(blocks, now: now)
            XCTAssertFalse(copied.contains("06/14/2015"))
            XCTAssertFalse(copied.contains("03/02/2026"))
            XCTAssertTrue(copied.contains("10/21/2026"))
        }
    }

    func testTheOldHandoffTextFollowsTheSameRule() {
        let text = HandoffWriter.text(datedRecord, now: now)
        XCTAssertTrue(text.contains("10/21/2026"))
        XCTAssertFalse(text.contains("06/14/2015"))
        XCTAssertFalse(text.contains("03/02/2026"))
        XCTAssertTrue(text.contains("TTE 03/2026"))
    }

    // MARK: Part 2: the Type & Screen expiration

    private func sent(_ expires: Date?) -> PatientTypeScreen { PatientTypeScreen(status: .sent, expires: expires) }
    private var resulted: PatientTypeScreen {
        PatientTypeScreen(type: "A+", screen: .negative, crossmatched: 2, expires: day(2026, 11, 14, 23, 59))
    }

    func testAnOldTypeAndScreenHasNoExpiration() throws {
        let old = try JSONDecoder().decode(PatientTypeScreen.self, from: Data(#"{"type":"A+","screen":"neg","crossmatched":2,"status":"resulted"}"#.utf8))
        XCTAssertNil(old.expires)
        XCTAssertEqual(old.parts(now: now), ["T&S A+, screen neg", "2 u crossmatched"])
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"typeScreen":{"type":"A+","screen":"neg","crossmatched":2,"status":"resulted"}}"#.utf8))
        XCTAssertNil(r.typeScreen.expires)
        XCTAssertEqual(r.typeScreen.type, "A+")
        // One with an expiration round-trips.
        let back = try JSONDecoder().decode(PatientTypeScreen.self, from: JSONEncoder().encode(resulted))
        XCTAssertEqual(back.expires, day(2026, 11, 14, 23, 59))
        XCTAssertEqual(back, resulted)
    }

    func testTheExpirationIsWrittenWithTheTypeAndScreen() {
        let ts = resulted
        XCTAssertEqual(ts.expiryText(now: now), "expires 11/14/26 23:59")
        XCTAssertEqual(ts.parts(now: now), ["T&S A+, screen neg", "2 u crossmatched", "expires 11/14/26 23:59"])
        // The time as the app writes times elsewhere (PatientSummary.time): the clock alone today, the date added otherwise.
        XCTAssertEqual(PatientTypeScreen(status: .resulted, expires: day(2026, 11, 11, 23, 59)).expiryText(now: now), "T&S expires 23:59")
        XCTAssertEqual(PatientTypeScreen(type: "O-", expires: day(2026, 11, 11, 23, 59)).expiryText(now: now), "expires 23:59")
        // Sent, not yet resulted.
        XCTAssertEqual(sent(day(2026, 11, 14, 23, 59)).parts(now: now), ["T&S sent, result pending", "expires 11/14/26 23:59"])
        XCTAssertFalse(ts.isExpired(now: now))
        XCTAssertTrue(ts.marks(now: now).isEmpty)
    }

    func testAnExpiredTypeAndScreenSaysSoInRed() {
        let ts = PatientTypeScreen(type: "A+", screen: .negative, crossmatched: 2, expires: day(2026, 11, 10, 23, 59))
        XCTAssertTrue(ts.isExpired(now: now))
        XCTAssertEqual(ts.expiryText(now: now), "T&S expired 11/10/26 23:59")
        XCTAssertEqual(ts.parts(now: now).last, "T&S expired 11/10/26 23:59")
        XCTAssertEqual(ts.marks(now: now), ["T&S expired 11/10/26 23:59"], "a mark of the line")
        // At the minute it passes.
        XCTAssertTrue(PatientTypeScreen(status: .sent, expires: now).isExpired(now: now))
        XCTAssertFalse(PatientTypeScreen(status: .sent, expires: now.addingTimeInterval(60)).isExpired(now: now))
        // A positive screen is red as before, and with an expired time both.
        let pos = PatientTypeScreen(type: "A+", screen: .positive, expires: day(2026, 11, 10, 23, 59))
        XCTAssertEqual(pos.marks(now: now), ["T&S A+, screen pos", "T&S expired 11/10/26 23:59"])
    }

    func testNotSentOffersNoExpirationAndShowsNone() {
        var ts = PatientTypeScreen(type: "A+", screen: .negative, crossmatched: 2, expires: day(2026, 11, 14, 23, 59))
        ts.setStatus(.notSent)
        XCTAssertEqual(ts.expires, day(2026, 11, 14, 23, 59), "a saved expiration stays in the record")
        XCTAssertNil(ts.shownExpiry)
        XCTAssertNil(ts.expiryText(now: now))
        XCTAssertEqual(ts.parts(now: now), ["T&S not sent"])
        XCTAssertFalse(ts.isExpired(now: now))
        // Never calculated: a draw time, or the status, set no expiration.
        var r = PatientRecord()
        r.labsDrawn = day(2026, 11, 11, 6, 30)
        r.typeScreen = PatientTypeScreen(status: .sent)
        XCTAssertNil(r.typeScreen.expires)
        XCTAssertNil(r.typeScreen.expiryText(now: now))
        var s = PatientTypeScreen(status: .sent)
        s.setStatus(.resulted)
        XCTAssertNil(s.expires)
    }

    func testTheExpirationIsOnTheLabsLineAndTheHemeGroupOfBothSummaries() {
        var r = PatientRecord()
        r.ageYears = 70; r.sex = .male
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        r.typeScreen = resulted
        // The labs line (the card on the tab) and its parts.
        let line = LabResults.lineParts(r, now: now)
        XCTAssertEqual(line.parts, ["T&S A+, screen neg", "2 u crossmatched", "expires 11/14/26 23:59"])
        XCTAssertTrue(line.marks.isEmpty)
        let labs = PatientSummary.labsLine(r, now: now)
        XCTAssertEqual(labs?.text, "T&S A+, screen neg · 2 u crossmatched · expires 11/14/26 23:59")
        // The Heme group of both summaries.
        for kind in [PatientBriefs.Kind.preop, .handoff] {
            let made = BriefLabs.make(r, withIntraop: kind == .handoff, now: now)
            let heme = made.preop.first { $0.name == "Heme" }
            XCTAssertEqual(heme?.items.first { $0.key == "ts" }?.text, "T&S A+, screen neg, 2 u crossmatched, expires 11/14/26 23:59")
            let blocks = PatientBriefs.blocks(kind, r, now: now)
            let text = blocks.first { $0.key == "labs" }?.text ?? ""
            XCTAssertTrue(text.contains("T&S A+, screen neg, 2 u crossmatched, expires 11/14/26 23:59"), text)
            // The plain text.
            XCTAssertTrue(PatientBriefs.plainText(blocks).contains("T&S A+, screen neg, 2 u crossmatched, expires 11/14/26 23:59"))
        }
    }

    func testAnExpiredTypeAndScreenIsAMarkOfEveryLineItIsOn() {
        var r = PatientRecord()
        r.ageYears = 70; r.sex = .male
        r.typeScreen = PatientTypeScreen(type: "A+", screen: .negative, crossmatched: 2, expires: day(2026, 11, 10, 23, 59))
        let expired = "T&S expired 11/10/26 23:59"
        let labs = PatientSummary.labsLine(r, now: now)
        XCTAssertTrue(labs?.text.contains(expired) ?? false)
        XCTAssertEqual(labs?.marks, [expired])
        XCTAssertNil(PatientBox.lineLimit(labs!), "a line with a mark is never truncated")
        XCTAssertEqual(PreopLabsCard.otherLine(r, now: now)?.marks, [expired])
        for kind in [PatientBriefs.Kind.preop, .handoff] {
            let block = PatientBriefs.blocks(kind, r, now: now).first { $0.key == "labs" }
            XCTAssertTrue(block?.text.contains(expired) ?? false)
            XCTAssertTrue(block?.marks.contains(expired) ?? false, "\(kind)")
            // And it is painted on the item it is in, and only where it stands alone.
            let item = BriefLabs.make(r, withIntraop: false, now: now).preop.flatMap(\.items).first { $0.key == "ts" }
            XCTAssertEqual(item.map { MarkedText.ranges(ofAny: $0.marks, in: $0.text).count }, 1)
        }
        // A record that is not expired has no mark for it.
        r.typeScreen.expires = day(2026, 11, 14, 23, 59)
        XCTAssertTrue(PatientSummary.labsLine(r, now: now)?.marks.isEmpty ?? false)
    }

    // MARK: Part 3: no "H" or "L" beside a lab value

    func testALabValueIsRedWithNoLetter() {
        let s = PatientLabs.summary(["plt": 112, "k": 5.9], sex: nil)
        XCTAssertEqual(s.abnormal.count, 2, "both are out of range")
        for v in s.items {
            XCTAssertFalse(v.compact.hasSuffix(" L") || v.compact.hasSuffix(" H"), v.compact)
        }
        XCTAssertTrue(s.line.contains("Plt 112"))
        XCTAssertTrue(s.line.contains("K 5.9"))
        XCTAssertFalse(s.line.contains("  "), "no stray space where the letter was: " + s.line)
        XCTAssertFalse(s.line.hasSuffix(" "))
        XCTAssertEqual(Set(s.abnormal.map(\.compact)), ["Plt 112", "K 5.9"], "the marks are the values alone")
        // The plain text keeps the letter; VoiceOver says low or high.
        XCTAssertTrue(s.plainLine.contains("Plt 112 L"))
        XCTAssertTrue(s.plainLine.contains("K 5.9 H"))
        XCTAssertTrue(s.spokenLine.contains("Plt 112, low"))
        XCTAssertTrue(s.spokenLine.contains("K 5.9, high"))
        // The flag itself is unchanged.
        XCTAssertEqual(PatientLabs.flag("plt", 112, sex: nil), .low)
        XCTAssertEqual(PatientLabs.flag("k", 5.9, sex: nil), .high)
        XCTAssertTrue(LabFlag.low.isAbnormal)
        XCTAssertEqual(LabFlag.low.word, "low")
        XCTAssertEqual(LabFlag.high.word, "high")
        XCTAssertEqual(LabFlag.normal.word, "")
    }

    func testBothValuesOfACreatinineAndItsGFRAreRed() {
        let gfr = BriefLabCell(key: "gfr", label: "GFR", text: "42", flag: .low)
        let cr = BriefLabCell(key: "cr", label: "Cr", text: "1.73", flag: .high, also: [gfr])
        XCTAssertEqual(cr.compact, "Cr 1.73 (GFR 42)")
        XCTAssertEqual(cr.marks, ["Cr 1.73", "GFR 42"])
        XCTAssertEqual(cr.compactLetter, "Cr 1.73 H (GFR 42 L)")
        XCTAssertEqual(cr.plain, "Cr 1.73 H (GFR 42 L)")
        XCTAssertEqual(cr.spoken, "Cr 1.73, high (GFR 42, low)")
        let item = BriefLabItem(cr)
        XCTAssertEqual(item.text, "Cr 1.73 (GFR 42)")
        XCTAssertEqual(item.plain, "Cr 1.73 H (GFR 42 L)")
        XCTAssertEqual(MarkedText.ranges(ofAny: item.marks, in: item.text).map { String(item.text[$0]) }, ["Cr 1.73", "GFR 42"])
        // Only one out of range: only it is red.
        let okGFR = BriefLabCell(key: "gfr", label: "GFR", text: "72")
        let one = BriefLabCell(key: "cr", label: "Cr", text: "1.73", flag: .high, also: [okGFR])
        XCTAssertEqual(one.marks, ["Cr 1.73"])
    }

    func testAMarkPaintsOnlyItsOwnValue() {
        func painted(_ mark: String, in text: String) -> [String] { MarkedText.ranges(of: mark, in: text).map { String(text[$0]) } }
        XCTAssertEqual(MarkedText.ranges(of: "K 5.9", in: "K 5.95 · K 5.9").count, 1, "not the start of K 5.95")
        XCTAssertEqual(MarkedText.ranges(of: "K 5.9", in: "K 5.95").count, 0)
        let both = "K 5.95 · K 5.9"
        XCTAssertEqual(both.distance(from: both.startIndex, to: MarkedText.ranges(of: "K 5.9", in: both)[0].lowerBound), 9, "the second one")
        XCTAssertEqual(MarkedText.ranges(of: "Na 13", in: "Na 135").count, 0, "not Na 135")
        XCTAssertEqual(MarkedText.ranges(of: "Na 13", in: "Na 135 · Na 13").count, 1)
        XCTAssertEqual(MarkedText.ranges(of: "K 5", in: "K 5.9").count, 0, "the number goes on")
        XCTAssertEqual(MarkedText.ranges(of: "T4 1.2", in: "fT4 1.2 · T4 1.2").count, 1, "not inside another name")
        XCTAssertEqual(MarkedText.ranges(of: "K 5.9", in: "Mg 5.9 · K 5.9").count, 1, "not the same digits of another item")
        XCTAssertEqual(MarkedText.ranges(of: "K 5.9", in: "BK 5.9").count, 0)
        XCTAssertEqual(MarkedText.ranges(of: "K 5.9", in: "K 5.9").count, 1)
        XCTAssertEqual(MarkedText.ranges(of: "K 5.9", in: "CMP: K 5.9, Na 138").count, 1)
        XCTAssertEqual(MarkedText.ranges(of: "K 5.9", in: "(K 5.9)").count, 1)
        XCTAssertEqual(MarkedText.ranges(of: "K 5.9", in: "K 5.9.").count, 1, "a full stop is not more decimals")
        XCTAssertEqual(painted("Cr 1.73", in: "Cr 1.73 (GFR 42)"), ["Cr 1.73"])
        XCTAssertEqual(MarkedText.ranges(of: "", in: "K 5.9").count, 0)
        XCTAssertEqual(MarkedText.ranges(ofAny: ["K 5.9", "K 5.9"], in: "K 5.9").count, 1, "a place once")
        // The short marked values keep their spaces together.
        let text = "Ca 8.3 · Mg 1.7"
        let spans = MarkedText.ranges(ofAny: ["Ca 8.3"], in: text)
        let together = MarkedText.keepingTogether(text, spans, upTo: 18)
        XCTAssertEqual(together, "Ca\u{00A0}8.3 · Mg 1.7")
        XCTAssertEqual(together.count, text.count)
    }

    private var abnormalRecord: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 70; r.sex = .male
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        r.labs = ["k": 5.9, "plt": 112, "cr": 1.73, "gfr": 42, "na": 139]
        return r
    }

    func testTheSummariesDrawTheValueInRedAndTheTextKeepsTheLetter() {
        for kind in [PatientBriefs.Kind.preop, .handoff] {
            let blocks = PatientBriefs.blocks(kind, abnormalRecord, now: now)
            let block = blocks.first { $0.key == "labs" }
            let text = block?.text ?? ""
            XCTAssertTrue(text.contains("K 5.9"), text)
            XCTAssertFalse(text.contains("K 5.9 H"), "\(kind): " + text)
            XCTAssertFalse(text.contains("Plt 112 L"), "\(kind): " + text)
            XCTAssertTrue(text.contains("Cr 1.73 (GFR 42)"), "\(kind): " + text)
            XCTAssertTrue(block?.marks.contains("K 5.9") ?? false)
            XCTAssertTrue(block?.marks.contains("Plt 112") ?? false)
            XCTAssertTrue(block?.marks.contains("Cr 1.73") ?? false)
            XCTAssertTrue(block?.marks.contains("GFR 42") ?? false)
            // The painted parts are exactly the values: none inside a longer number or another item.
            for g in BriefLabs.make(abnormalRecord.capitalized, withIntraop: false, now: now).preop {
                XCTAssertEqual(MarkedText.ranges(ofAny: g.marks, in: g.text).count, Set(g.marks).count, g.text)
            }
            // The plain text: the letter stays, or an abnormal value is not told from a normal one in a text message.
            let plain = PatientBriefs.plainText(blocks)
            XCTAssertTrue(plain.contains("K 5.9 H"), plain)
            XCTAssertTrue(plain.contains("Plt 112 L"), plain)
            XCTAssertTrue(plain.contains("Cr 1.73 H (GFR 42 L)"), plain)
            XCTAssertTrue(PatientBriefs.sharedText(blocks, now: now).contains("K 5.9 H"))
            // VoiceOver.
            XCTAssertTrue(block?.spoken?.contains("K 5.9, high") ?? false)
            XCTAssertTrue(block?.spoken?.contains("Plt 112, low") ?? false)
        }
    }

    func testAnEditedLabsBlockHasOnlyTheUsersWords() {
        var r = abnormalRecord
        PatientBriefs.setEdit(&r, .preop, key: "labs", text: "K high, platelets low", now: now)
        let block = PatientBriefs.preop(r, now: now).first { $0.key == "labs" }
        XCTAssertEqual(block?.text, "K high, platelets low")
        XCTAssertNil(block?.plain)
        XCTAssertEqual(block.map { PatientBriefs.plainLines($0) }, ["Labs: K high, platelets low"])
    }

    func testTheLabsLineAndTheCardKeepTheLetterOnlyInThePlainForm() {
        let line = PatientSummary.labsLine(abnormalRecord, now: now)
        XCTAssertNotNil(line)
        XCTAssertFalse(line?.text.contains("K 5.9 H") ?? true)
        XCTAssertTrue(line?.text.contains("K 5.9") ?? false)
        XCTAssertTrue(line?.marks.contains("K 5.9") ?? false)
        XCTAssertTrue(line?.plainText.contains("K 5.9 H") ?? false)
        XCTAssertTrue(line?.spokenText.contains("K 5.9, high") ?? false)
        // The card's one line of the other results.
        var r = PatientRecord()
        r.labs = ["gfr": 55, "mg": 1.4]
        XCTAssertEqual(PreopLabsCard.otherLine(r, now: now)?.text, "GFR 55 · Mg 1.4")
        XCTAssertEqual(PreopLabsCard.otherLine(r, now: now)?.marks, ["GFR 55", "Mg 1.4"])
        XCTAssertEqual(PreopLabsCard.otherLine(r, now: now)?.spoken, "GFR 55, low · Mg 1.4, low")
        // A line with no plain form is its text.
        XCTAssertEqual(PatientSummary.Line("A", "b").plainText, "b")
        XCTAssertEqual(PatientSummary.Line("A", "b").spokenText, "b")
    }

    func testTheIntraoperativeSetsDrawNoLetterAndTheTextKeepsIt() {
        let set = IntraopLabSet(time: day(2026, 11, 11, 7, 40), values: ["ph": 7.33, "paco2": 47, "pao2": 212])
        let l = IntraopLabs.line(set, sex: nil, now: now)
        XCTAssertNotNil(l)
        XCTAssertTrue(l?.text.hasPrefix("07:40 · pH 7.33 · PaCO₂ 47") ?? false, l?.text ?? "")
        XCTAssertEqual(l?.marks, ["pH 7.33", "PaCO₂ 47"])
        XCTAssertTrue(l?.plainText.contains("pH 7.33 L · PaCO₂ 47 H") ?? false, l?.plainText ?? "")
        XCTAssertTrue(l?.spokenText.contains("pH 7.33, low · PaCO₂ 47, high") ?? false, l?.spokenText ?? "")
        // The short handoff is a plain text: the letters stay.
        var r = PatientRecord()
        r.intraopLabs = [set]
        let short = HandoffWriter.shortText(r, now: now)
        XCTAssertTrue(short.contains("pH 7.33 L"), short)
        // The long one too.
        r.labs = ["k": 5.9]
        XCTAssertTrue(HandoffWriter.text(r, now: now).contains("K 5.9 H"))
    }

    func testTheQuickAddReviewChipDrawsNoLetter() {
        XCTAssertEqual(QuickAdd.labText("k", 5.4, sex: nil), "K 5.4")
        XCTAssertEqual(QuickAdd.labSpoken("k", 5.4, sex: nil), "K 5.4, high")
        XCTAssertEqual(QuickAdd.labText("cr", 1, sex: nil), "Cr 1.00")
        let q = QuickAdd.read("K 5.4 Cr 1.6", record: PatientRecord(), tab: .preop, now: now)
        let chips = QuickAdd.chips(q, record: PatientRecord())
        let k = chips.first { $0.value.hasPrefix("K ") }
        XCTAssertEqual(k?.value, "K 5.4")
        XCTAssertEqual(k?.marks, ["K 5.4"])
        XCTAssertEqual(k?.spokenText, "Labs · K 5.4, high")
        XCTAssertEqual(k?.text, "Labs · K 5.4")
        // A chip that is not a lab value has no mark.
        let other = QuickAdd.chips(QuickAdd.read("HR 72", record: PatientRecord(), tab: .preop, now: now), record: PatientRecord())
        XCTAssertTrue(other.allSatisfy { $0.marks.isEmpty })
        // An in-range value has none either.
        let normal = QuickAdd.chips(QuickAdd.read("K 4.1", record: PatientRecord(), tab: .preop, now: now), record: PatientRecord())
        XCTAssertEqual(normal.first?.marks, [])
    }

    func testTheStrayTrailingSpaceIsNeverLeftWhereTheLetterWas() {
        let r = abnormalRecord
        let line = PatientSummary.labsLine(r, now: now)
        XCTAssertFalse(line?.text.contains("  ") ?? true)
        XCTAssertFalse(line?.text.hasSuffix(" ") ?? true)
        for kind in [PatientBriefs.Kind.preop, .handoff] {
            for b in PatientBriefs.blocks(kind, r, now: now) where b.key == "labs" {
                XCTAssertFalse(b.text.contains("  "), b.text)
                XCTAssertFalse(b.text.contains(" ;"), b.text)
                XCTAssertFalse(b.text.contains(" ,"), b.text)
            }
        }
    }
}
