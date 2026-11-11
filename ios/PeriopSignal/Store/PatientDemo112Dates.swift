import Foundation

#if DEBUG
/// Helper G's demo patients for the dates, Type & Screen expiration and lab-letter screenshots (-ps.patient <seed>; seeds start
/// with "demo-112-dates"). Every date is relative to the day the shot runs, so "within the last 90 days" holds whenever it is taken.
///
///   demo-112-dates          the briefs patient with past surgeries of every kind (a stent three weeks ago with its day, a
///                           cholecystectomy 06/14/2015 with its day, a knee 03/2019, an appendectomy 1998), an echo, a stress
///                           test and a cath with a day, the Preprocedure Summary on, abnormal labs (no H or L beside them)
///   demo-112-dates-ts-sent  the same, the type and screen sent and no result yet: "+ Expires" on the Labs page
///   demo-112-dates-ts-set   the type and screen resulted (A+, screen neg, 2 u) and expiring in three days at 23:59
///   demo-112-dates-ts-expired  the same, expired yesterday at 23:59 (red)
enum PatientDemo112Dates {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-dates": return base
        case "demo-112-dates-ts-sent":
            var r = base
            r.typeScreen = PatientTypeScreen(status: .sent)
            return r
        case "demo-112-dates-ts-set":
            var r = base
            r.typeScreen = PatientTypeScreen(type: "A+", screen: .negative, crossmatched: 2, expires: atEndOfDay(plusDays: 3))
            return r
        case "demo-112-dates-ts-expired":
            var r = base
            r.typeScreen = PatientTypeScreen(type: "A+", screen: .negative, crossmatched: 2, expires: atEndOfDay(plusDays: -1))
            return r
        default: return nil
        }
    }

    /// The calendar day `days` days before today, as the app's date with a day.
    static func daysAgo(_ days: Int) -> PatientMonthYear {
        let d = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return PatientMonthYear(month: c.month, day: c.day, year: c.year)
    }

    /// 23:59 on the day `plusDays` from today.
    static func atEndOfDay(plusDays: Int) -> Date? {
        guard let d = Calendar.current.date(byAdding: .day, value: plusDays, to: Date()) else { return nil }
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: d)
    }

    static var base: PatientRecord {
        var r = PatientDemo.briefs
        r.surgeries = [
            PatientSurgery(name: "PCI with stent to the proximal LAD", date: daysAgo(21)),
            PatientSurgery(procedures: PlannedProcedure.parse("lap chole"), date: PatientMonthYear(month: 6, day: 14, year: 2015)),
            PatientSurgery(name: "Total knee arthroplasty", side: "right", date: PatientMonthYear(month: 3, year: 2019)),
            PatientSurgery(name: "Appendectomy", date: PatientMonthYear(year: 1998)),
        ]
        var echo = PatientEcho()
        echo.study = "TTE"; echo.date = daysAgo(40); echo.lv = .mild; echo.lvef = 45; echo.rv = .normal
        r.echoFindings = echo
        r.stressTest = PatientStressTest(kind: .dobutamine, result: .negative, date: PatientMonthYear(month: 3, day: 14, year: 2025))
        var lhc = PatientLHC()
        lhc.dominance = "right"; lhc.stenosis = ["lad": 90, "rca": 40]; lhc.date = daysAgo(24)
        r.lhc = lhc
        // Out-of-range values to show red with no letter: Hb, K, BUN, Cr with its GFR, Plt.
        r.labs["plt"] = 112
        r.labs["gfr"] = 9
        r.preopSummaryOn = true
        return r
    }
}
#endif
