import Foundation

#if DEBUG
/// Helper H's demo patients for the typed-antibiotic and Case Timers "Log dose" screenshots (-ps.patient <seed>; seeds start
/// with "demo-112-abx"), shots 980–999. Nothing here is written to disk.
///   demo-112-abx-none: a 67-year-old man for a CABG ×3 on the table, no antibiotic charted: the page says "None charted", the
///     bar has a line to type, Case Timers has a drug to pick.
///   demo-112-abx-typed: the same after "vanc 1 g" was filed from the bar 20 minutes ago (dose typed, no routine redose), and
///     cefazolin logged in Case Timers 40 minutes ago: the row, the page and the handoff tell both.
enum PatientDemo112Abx {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-abx-none": return base()
        case "demo-112-abx-typed": return typed()
        default: return nil
        }
    }

    private static func base() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = 82
        r.setProcedures(PlannedProcedure.parse("CABG x3"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.problems = ["htn", "hld", "cad"]
        r.infusions = [PatientInfusion(drug: "Norepinephrine", rate: "0.05 mcg/kg/min")]
        r.airwayAtEnd = "intubated"
        return r
    }

    private static func typed() -> PatientRecord {
        var r = base()
        let now = Date()
        r.timers.antibiotics = [
            AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: now.addingTimeInterval(-40 * 60), ebl: 0)]),
            AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: now.addingTimeInterval(-20 * 60), ebl: 0, given: "1 g")]),
        ]
        return r
    }
}
#endif
