import Foundation

#if DEBUG
/// Helper S's demo patients for the Surgical Prophylaxis calculator opened from a case (-ps.patient <seed>; seeds start with
/// "demo-112-proph"), shots 1200-1239. Nothing here is written to disk.
///   demo-112-proph-cabg: 67-year-old man, 92 kg, 178 cm, CABG ×3 planned, a penicillin allergy with a rash, MRSA screen positive:
///     the calculator opens prefilled with all three, each with its caption, and Start buttons.
///     Since Ben's Nov 19 decision (after an outside review) the penicillin rash is ASKED: the allergy row opens with neither No nor Yes
///     chosen (shots 1300-1314).
///   demo-112-proph-ceph: the same man at 92 kg, CABG x3, a ceftriaxone rash (a cephalosporin: the allergy is still prefilled Yes).
///   demo-112-proph-plain: the same man at 82 kg with no allergy and no MRSA screen (the Start confirmation, "Started").
///   demo-112-proph-running: as plain, with a cefazolin course already running (40 minutes ago).
///   demo-112-proph-avr: an aortic valve replacement planned, 80 kg. Since Ben's Nov 23 approval it opens the "Valve replacement,
///     surgical" row (Periop Signal's reading, with the caution line); before it selected the Cardiac group only (shot 1227).
///   demo-112-proph-notlisted: a revision total knee planned, 80 kg: no row names it, so the Orthopedic group opens on its
///     "Operation not listed" row, with the "From the case" caption (shots 1410-1429).
///   demo-112-proph-child: an 8-year-old girl, 28 kg, a laparoscopic appendectomy: adult doses only, no dose and no Start.
///   demo-112-proph-noweight: as plain, with no weight recorded.
enum PatientDemo112Prophylaxis {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-proph-cabg": return cabg()
        case "demo-112-proph-ceph": return ceph()
        case "demo-112-proph-plain": return base(weight: 82)
        case "demo-112-proph-running": return running()
        case "demo-112-proph-avr": return avr()
        case "demo-112-proph-notlisted": return notListed()
        case "demo-112-proph-child": return child()
        case "demo-112-proph-noweight": return base(weight: nil)
        default: return nil
        }
    }

    private static func base(weight: Double?) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = weight
        r.setProcedures(PlannedProcedure.parse("CABG x3"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.problems = ["htn", "hld", "cad"]
        return r
    }

    private static func cabg() -> PatientRecord {
        var r = base(weight: 92)
        r.allergyList = AllergyCatalog.parse("PCN - rash")
        r.infections.results["mrsa"] = .positive
        return r
    }

    private static func ceph() -> PatientRecord {
        var r = base(weight: 92)
        r.allergyList = AllergyCatalog.parse("ceftriaxone - rash")
        return r
    }

    private static func running() -> PatientRecord {
        var r = base(weight: 82)
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: Date().addingTimeInterval(-40 * 60), ebl: 0)])]
        return r
    }

    private static func avr() -> PatientRecord {
        var r = base(weight: 80)
        r.setProcedures(PlannedProcedure.parse("AVR"))
        return r
    }

    private static func notListed() -> PatientRecord {
        var r = base(weight: 80)
        r.setProcedures(ProcedureCatalog.byID("revision-tka").map { [PlannedProcedure($0)] } ?? [])
        return r
    }

    private static func child() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 8; r.sex = .female; r.heightCm = 128; r.weightKg = 28
        r.setProcedures(ProcedureCatalog.byID("lap-appy").map { [PlannedProcedure($0)] } ?? [])
        r.urgency = .urgent
        r.anesthetic = ["ga"]
        return r
    }
}
#endif
