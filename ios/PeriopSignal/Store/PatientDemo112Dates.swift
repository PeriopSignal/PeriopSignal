import Foundation

#if DEBUG
/// Helper G's demo patients for the dates, Type & Screen expiration and lab-letter screenshots (-ps.patient <seed>; seeds start
/// with "demo-112-dates"). Every date is relative to the day the shot runs, so "within the last 90 days" holds whenever it is taken.
///
///   demo-112-dates          the briefs patient with past surgeries of every kind (a stent three weeks ago with its day, a
///                           cholecystectomy 06/14/2015 with its day, a knee 03/2019, an appendectomy 1998), an echo, a stress
///                           test and a cath with a day, the Preprocedure Summary on, abnormal labs (no H or L beside them)
///   demo-112-dates-summary a short history, so the Preprocedure Summary shows its past surgery, workup and labs in one screen
///   demo-112-dates-ts-sent  the same, the type and screen sent and no result yet: "+ Expires" on the Labs page
///   demo-112-dates-ts-set   the type and screen resulted (A+, screen neg, 2 u) and expiring in three days at 23:59
///   demo-112-dates-ts-expired  the same, expired yesterday at 23:59 (red)
///   demo-112-psh            (helper J) the briefs patient with five past operations in every date form, entered out of order:
///                           the page, the summaries and the History row list them newest first
///   demo-112-psh-filed      (helper J) a patient whose past surgery came through the Past Surgical History bar, two lines one
///                           after the other ("appendectomy 2010", then "jaw wiring 2012, knee scope 2020"): the same reader and
///                           chips the bar uses, run in code
enum PatientDemo112Dates {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-dates": return base
        case "demo-112-dates-summary": return short
        case "demo-112-psh": return psh
        case "demo-112-share": return share
        case "demo-112-psh-filed": return filed(["appendectomy 2010", "jaw wiring 2012, knee scope 2020"])
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

    /// Helper Q (demo-112-share): a record like the handoff Ben shared as a picture from build 39: allergies, PMH, PSH, the ECG,
    /// labs, home medications with an alert, and one arterial line so the lines diagram is drawn. The handoff and the preop summary
    /// both carry it.
    static var share: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 52; r.sex = .female; r.heightCm = 165; r.weightKg = 70
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.allergyList = AllergyCatalog.parse("clindamycin severe hives, latex mild rash")
        r.problems = ["pvd", "asthma"]
        r.asaClass = 2
        r.mets = "ge4"
        r.surgeries = [
            PatientSurgery(name: "Laparoscopic cholecystectomy", date: PatientMonthYear(month: 9, day: 18, year: 2026)),
            PatientSurgery(name: "Spinal cord stimulator implantation", date: PatientMonthYear(month: 5, year: 2025)),
        ]
        r.ecg = ["Normal sinus rhythm"]
        r.labs = ["na": 139, "k": 5, "bun": 7, "cr": 0.85, "gfr": 95, "glucose": 90, "hb": 13.6, "plt": 293, "ptt": 28, "inr": 1.0]
        r.homeMeds = MedicationCatalog.parse("hydrocodone/acetaminophen, famotidine, ondansetron")
        r.medFlags = MedicationCatalog.flags(for: r.homeMeds)
        r.devices = ["20g R radial art line"].compactMap { PatientDevices.parse($0)?.device(placedIntraop: true) }
        PatientDeviceFills.apply(before: PatientRecord(), after: &r)
        r.preopSummaryOn = true
        return r
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

    /// Helper J: five past operations entered out of order, in every date form: a year alone (1998), a full date (06/14/2015), a
    /// typed operation with the year alone (2015, which lists after the full date of the same year), a month and year (03/2019),
    /// and one with no date, which lists last.
    static var psh: PatientRecord {
        var r = PatientDemo.briefs
        r.surgeries = [
            PatientSurgery(name: "Appendectomy", date: PatientMonthYear(year: 1998)),
            PatientSurgery(procedures: [PlannedProcedure(name: "Tonsillectomy")]),
            PatientSurgery(procedures: [PlannedProcedure(name: "Jaw wiring")], date: PatientMonthYear(year: 2015)),
            PatientSurgery(name: "Total knee arthroplasty", side: "right", date: PatientMonthYear(month: 3, year: 2019)),
            PatientSurgery(procedures: PlannedProcedure.parse("lap chole"), date: PatientMonthYear(month: 6, day: 14, year: 2015)),
        ]
        r.preopSummaryOn = true
        return r
    }

    /// Helper J: a patient whose past surgery was filed by the Past Surgical History bar, one line after the other, through the
    /// bar's own path (QuickAdd.read, the chips that can be added, PatientNote.apply: QuickAddBar.add).
    static func filed(_ lines: [String]) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 58; r.sex = .female; r.heightCm = 165; r.weightKg = 72
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        for line in lines {
            let q = QuickAdd.read(line, record: r, tab: .preop, now: Date(), surgicalHistory: true)
            let chosen = QuickAdd.chips(q, record: r).filter(\.canAdd)
            PatientNote.apply(QuickAdd.changes(chosen), to: &r)
        }
        return r
    }

    /// A short history for the Preprocedure Summary: past surgery, a workup with days, and abnormal labs, in one screen.
    static var short: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 70; r.sex = .male; r.heightCm = 178; r.weightKg = 84
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.nkda = true
        r.surgeries = [
            PatientSurgery(name: "PCI with stent to the proximal LAD", date: daysAgo(21)),
            PatientSurgery(procedures: PlannedProcedure.parse("lap chole"), date: PatientMonthYear(month: 6, day: 14, year: 2015)),
            PatientSurgery(name: "Appendectomy", date: PatientMonthYear(year: 1998)),
        ]
        var echo = PatientEcho()
        echo.study = "TTE"; echo.date = daysAgo(40); echo.lvef = 45
        r.echoFindings = echo
        var lhc = PatientLHC()
        lhc.dominance = "right"; lhc.stenosis = ["lad": 90]; lhc.date = daysAgo(24)
        r.lhc = lhc
        r.labs = ["na": 138, "k": 5.6, "bun": 48, "cr": 1.73, "gfr": 42, "hb": 10.8, "plt": 112, "glucose": 162]
        r.labsDrawn = PatientDemo.today(6, 30)
        r.typeScreen = PatientTypeScreen(type: "A+", screen: .negative, crossmatched: 2, expires: atEndOfDay(plusDays: 3))
        r.preopSummaryOn = true
        return r
    }

    static var base: PatientRecord {
        var r = PatientDemo.briefs
        // A year alone, a full date, a month and year, and a recent date with its day: the first three are on the page's first screen.
        r.surgeries = [
            PatientSurgery(name: "Appendectomy", date: PatientMonthYear(year: 1998)),
            PatientSurgery(procedures: PlannedProcedure.parse("lap chole"), date: PatientMonthYear(month: 6, day: 14, year: 2015)),
            PatientSurgery(name: "Total knee arthroplasty", side: "right", date: PatientMonthYear(month: 3, year: 2019)),
            PatientSurgery(name: "PCI with stent to the proximal LAD", date: daysAgo(21)),
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
