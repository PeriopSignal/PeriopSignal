import Foundation

// MARK: - 1.10 dates (Ben, Nov 7: "Dates should be formatted MM/DD/YY")
//
// One place for every date the patient pages, the summary, the handoff and the tools write with a day in it: "11/07/26",
// with a clock time "11/07/26 09:41". A value with only a month and year (a past surgery, a catheterization:
// PatientMonthYear) has no day to show and stays "06/2025". Times alone ("09:41") stay as they are.

enum PatientDates {
    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    /// "11/07/26".
    static func day(_ d: Date, calendar: Calendar = .current) -> String {
        formatter("MM/dd/yy", calendar: calendar).string(from: d)
    }

    /// "11/07/26 09:41" (24-hour, as the summary writes clock times).
    static func dayTime(_ d: Date, calendar: Calendar = .current) -> String {
        formatter("MM/dd/yy HH:mm", calendar: calendar).string(from: d)
    }

    /// "Sat 11/07/26, 09:41", for the tools that show the weekday too (fasting, neuraxial timing).
    static func weekdayDayTime(_ d: Date, calendar: Calendar = .current) -> String {
        formatter("EEE MM/dd/yy, HH:mm", calendar: calendar).string(from: d)
    }

    /// "Sat 11/07/26".
    static func weekdayDay(_ d: Date, calendar: Calendar = .current) -> String {
        formatter("EEE MM/dd/yy", calendar: calendar).string(from: d)
    }
}
