import Foundation

#if DEBUG
/// Helper R's demo patients for the antibiotic's dose and a logged dose's time in Case Timers (-ps.patient <seed>; seeds
/// start with "demo-112-abxdose"), shots 1175-1189. Nothing here is written to disk. All are a 67-year-old man (82 kg, 178 cm)
/// for a CABG ×3 on the table unless said.
///   demo-112-abxdose-none: no antibiotic charted yet (a drug to pick, with a dose typed before "Log dose").
///   demo-112-abxdose-cefaz: cefazolin logged 40 minutes ago with the worked-out dose (nothing typed): "Change" beside "2 g".
///   demo-112-abxdose-custom: cefazolin timed, dose "3 g" for the case (the first dose 40 minutes ago), and vancomycin recorded
///     only with the dose "1.25 g" for the case while the dose itself was typed in the bar as "1 g" (a differing typed dose):
///     the row, the page and the handoff tell both.
///   demo-112-abxdose-three: cefazolin with three doses (3 h 40 min, 40 min and 5 minutes ago), no custom dose: the log has rows.
///   demo-112-abxdose-vanc: no weight on the record; vancomycin recorded 20 minutes ago with the dose "1.25 g" for the case,
///     the worked-out dose being "Weight needed".
enum PatientDemo112AbxDose {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-abxdose-none": return base()
        case "demo-112-abxdose-cefaz": return cefazolin()
        case "demo-112-abxdose-custom": return custom()
        case "demo-112-abxdose-three": return three()
        case "demo-112-abxdose-vanc": return vanc()
        default: return nil
        }
    }

    private static func base(weight: Double? = 82) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = weight
        r.setProcedures(PlannedProcedure.parse("CABG x3"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.problems = ["htn", "hld", "cad"]
        r.airwayAtEnd = "intubated"
        return r
    }

    private static func ago(_ minutes: Double) -> Date { Date().addingTimeInterval(-minutes * 60) }

    private static func cefazolin() -> PatientRecord {
        var r = base()
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: ago(40), ebl: 0)])]
        return r
    }

    private static func custom() -> PatientRecord {
        var r = base()
        r.timers.antibiotics = [
            AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: ago(40), ebl: 0)], dose: "3 g"),
            AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: ago(20), ebl: 0, given: "1 g")], reminders: false, dose: "1.25 g"),
        ]
        return r
    }

    private static func three() -> PatientRecord {
        var r = base()
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [
            TimedEntry(time: ago(220), ebl: 0), TimedEntry(time: ago(40), ebl: 150), TimedEntry(time: ago(5), ebl: 300),
        ])]
        return r
    }

    private static func vanc() -> PatientRecord {
        var r = base(weight: nil)
        r.timers.antibiotics = [AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: ago(20), ebl: 0)], dose: "1.25 g")]
        return r
    }
}
#endif
