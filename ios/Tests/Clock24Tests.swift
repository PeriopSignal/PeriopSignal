import XCTest
@testable import PeriopSignal

/// Ben, Nov 11: "Make all time 24-hr military time standard". Every time the app writes is on the 24-hour clock whatever
/// the phone is set to, and every time picker is given a locale with the 24-hour clock.
final class Clock24Tests: XCTestCase {

    private func at(_ hour: Int, _ minute: Int, daysAgo: Int = 0, from now: Date) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: now))!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    func testAClockTimeIsWrittenOnThe24HourClock() {
        let now = Date()
        XCTAssertEqual(PatientDates.clock(at(14, 30, from: now)), "14:30")
        XCTAssertEqual(PatientDates.clock(at(0, 5, from: now)), "00:05", "midnight is 00, never 12")
        XCTAssertEqual(PatientDates.clock(at(12, 0, from: now)), "12:00")
        XCTAssertEqual(PatientDates.clock(at(23, 59, from: now)), "23:59")
        for h in 0..<24 {
            let s = PatientDates.clock(at(h, 7, from: now))
            XCTAssertEqual(s, String(format: "%02d:07", h))
            XCTAssertFalse(s.uppercased().contains("M"), "no AM or PM: " + s)
        }
    }

    func testThePickersLocaleHasThe24HourClock() {
        XCTAssertEqual(PatientDates.locale24.hourCycle, .zeroToTwentyThree)
        XCTAssertEqual(PatientDates.locale24.language.languageCode, Locale.current.language.languageCode, "the reader's own language, only the clock changes")
        XCTAssertEqual(PatientDates.locale24.region, Locale.current.region, "and region, so the order of day and month is theirs")
        let f = DateFormatter()
        f.locale = PatientDates.locale24
        f.dateStyle = .none
        f.timeStyle = .short
        let s = f.string(from: at(14, 30, from: Date()))
        XCTAssertTrue(s.contains("14"), "a short time in this locale is on the 24-hour clock: " + s)
        XCTAssertFalse(s.uppercased().contains("PM"), s)
    }

    func testTheLastIntakeLineIsOnThe24HourClock() {
        let now = at(15, 0, from: Date())
        var r = PatientRecord()
        r.lastSolids = at(0, 0, from: now)
        r.lastClears = at(13, 45, from: now)
        XCTAssertEqual(PatientPreop.intakeText(r, now: now), "Solids 00:00 · clears 13:45")
        XCTAssertEqual(PatientPreop.intakeRow(r, now: now), "Last intake: Solids 00:00 · clears 13:45")
        // Not today: the day too, as the app writes a day with a time.
        let yesterday = at(22, 15, daysAgo: 1, from: now)
        r.lastSolids = yesterday
        r.lastClears = nil
        XCTAssertEqual(PatientPreop.intakeText(r, now: now), "Solids " + PatientDates.dayTime(yesterday))
        XCTAssertTrue(PatientPreop.intakeText(r, now: now)?.hasSuffix(" 22:15") ?? false)
    }

    func testTheSummarysTimeIsOnThe24HourClock() {
        let now = at(15, 0, from: Date())
        XCTAssertEqual(PatientSummary.time(at(13, 5, from: now), now: now), "13:05")
        XCTAssertTrue(PatientSummary.time(at(21, 40, daysAgo: 1, from: now), now: now).hasSuffix(" 21:40"))
    }
}
