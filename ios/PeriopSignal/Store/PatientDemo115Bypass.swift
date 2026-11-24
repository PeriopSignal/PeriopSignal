import Foundation

#if DEBUG
/// The 1.15 demo patients for the bypass and cross-clamp screenshots (-ps.patient <seed>), made up for the pictures (Ben, Nov 23:
/// "Have ability to change bypass start time. And add total bypass time to handoff (have ability to add new bypass run too)"). Times
/// are offsets from the moment the app starts, so the runs read on the clock the shot is taken. Nothing here is written to disk, and
/// no patient identifiers are kept. Both are a 67-year-old man (82 kg) for a CABG x3 with a heparin log.
///   demo-115-bypass-on   on bypass since 50 minutes ago with the aortic cross-clamp on since 35 minutes ago (both runs open).
///   demo-115-bypass-two  two ended bypass runs (32 and 55 minutes, 1 h 27 min in all) and one ended cross-clamp run (50 minutes).
enum PatientDemo115Bypass {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-115-bypass-on": return on
        case "demo-115-bypass-two": return two
        default: return nil
        }
    }

    /// The case and a heparin log with doses (the bypass rows show once a dose is logged), the reminder off.
    private static func base(_ now: Date) -> PatientRecord {
        func ago(_ m: Double) -> Date { now.addingTimeInterval(-m * 60) }
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = 82
        r.setProcedures(PlannedProcedure.parse("CABG x3"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.problems = ["htn", "hld", "cad"]
        var h = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
        h.acts = [TimedEntry(time: ago(175), value: 128, baseline: true), TimedEntry(time: ago(165), value: 512)]
        h.doses = [TimedEntry(time: ago(170), value: 26000)]
        h.actOff = true
        r.timers.heparin = h
        return r
    }

    private static var on: PatientRecord {
        let now = Date()
        var r = base(now)
        r.timers.heparin?.bypassRuns = [BypassRun(start: now.addingTimeInterval(-50 * 60))]
        r.timers.heparin?.clampRuns = [BypassRun(start: now.addingTimeInterval(-35 * 60))]
        return r
    }

    private static var two: PatientRecord {
        let now = Date()
        func ago(_ m: Double) -> Date { now.addingTimeInterval(-m * 60) }
        var r = base(now)
        r.timers.heparin?.bypassRuns = [BypassRun(start: ago(140), end: ago(108)), BypassRun(start: ago(95), end: ago(40))]
        r.timers.heparin?.clampRuns = [BypassRun(start: ago(125), end: ago(75))]
        return r
    }
}
#endif
