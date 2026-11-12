import Foundation

#if DEBUG
/// Helper O's demo patients for the reworked Heparin & ACT timeline (-ps.patient <seed>; seeds start with "demo-112-hep"),
/// shots 1110-1129. Times are offsets from the moment the app starts, so the log reads "now" on the clock the shot is taken.
/// Nothing here is written to disk.
///   demo-112-hep-bypass: a CABG on bypass, 82 kg: a baseline ACT, 26,000 U, an ACT at goal, an ACT below goal, a second dose
///     (5,000 U) and an ACT at goal, the reminder on (30 min, counting from the last ACT).
///   demo-112-hep-bypass-off: the same log with the reminder switched off.
///   demo-112-hep-tavr: a TAVR: one dose (7,000 U) and one ACT at goal, the reminder on.
///   demo-112-hep-empty: the purpose chosen (bypass), nothing logged: the three add buttons.
///   demo-112-hep-protamine: the bypass log with a protamine dose 4 minutes ago (a row of the timeline, and the protamine block).
///   demo-112-hep-midnight: the bypass log with entries on the day before (the date shows on those rows).
enum PatientDemo112Heparin {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-hep-bypass": return bypass()
        case "demo-112-hep-bypass-off": return bypass(reminderOn: false)
        case "demo-112-hep-tavr": return tavr()
        case "demo-112-hep-empty": return empty()
        case "demo-112-hep-protamine": return protamine()
        case "demo-112-hep-midnight": return bypass(shiftMinutes: 24 * 60)
        default: return nil
        }
    }

    private static func base(_ procedure: String) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = 82
        r.setProcedures(PlannedProcedure.parse(procedure))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.problems = ["htn", "hld", "cad"]
        return r
    }

    private static func bypass(reminderOn: Bool = true, shiftMinutes: Double = 0) -> PatientRecord {
        var r = base("CABG x3")
        let now = Date()
        func ago(_ m: Double) -> Date { now.addingTimeInterval(-(m + shiftMinutes) * 60) }
        var h = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
        h.acts = [TimedEntry(time: ago(70), value: 128, baseline: true)]
        h.doses = [TimedEntry(time: ago(62), value: 26000)]
        h.acts.append(TimedEntry(time: ago(56), value: 512))
        h.acts.append(TimedEntry(time: ago(34), value: 468))
        h.doses.append(TimedEntry(time: ago(32), value: 5000))
        h.acts.append(TimedEntry(time: ago(9), value: 545))
        h.bypassOn = ago(50)
        if reminderOn { h.actStart = ago(62) } else { h.actOff = true }
        r.timers.heparin = h
        return r
    }

    private static func tavr() -> PatientRecord {
        var r = base("TAVR")
        let now = Date()
        var h = HeparinCourse(purpose: "tavr", goal: 250, actEvery: 30)
        h.acts = [TimedEntry(time: now.addingTimeInterval(-31 * 60), value: 131, baseline: true)]
        h.doses = [TimedEntry(time: now.addingTimeInterval(-25 * 60), value: 7000)]
        h.acts.append(TimedEntry(time: now.addingTimeInterval(-12 * 60), value: 271))
        h.actStart = now.addingTimeInterval(-25 * 60)
        r.timers.heparin = h
        return r
    }

    private static func empty() -> PatientRecord {
        var r = base("CABG x3")
        r.timers.heparin = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
        return r
    }

    private static func protamine() -> PatientRecord {
        var r = bypass()
        r.timers.heparin?.bypassOff = Date().addingTimeInterval(-8 * 60)
        r.timers.heparin?.protamine = [TimedEntry(time: Date().addingTimeInterval(-4 * 60), value: 150)]
        return r
    }
}
#endif
