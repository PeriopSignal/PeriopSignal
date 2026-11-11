import Foundation

#if DEBUG
/// Helper D's demo patients for the 1.12 screenshots (-ps.patient <seed>), shots 890–909. Nothing here is written to disk.
///   demo-112-meds-preop: the Current Medications & Infusions box: a home list typed out of order (an SSRI first), an
///     antibiotic, cardiovascular drugs and two drips running before the case, so the box lists the drips first, then the
///     antibiotic, the cardiovascular medications and the rest.
///   demo-112-meds-abx: the Intraoperative row and page: Case Timers' antibiotics (cefazolin on time, vancomycin with no
///     routine redose), notable medication chips with doses typed beside them, and free text.
///   demo-112-meds-overdue: the same with the cefazolin redose overdue (red).
///   demo-112-meds-deleted: a preop drip taken off the case's list in the room: gone from the handoff's infusions, still
///     in the Preprocedure Summary and the preop box.
enum PatientDemo112Meds {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-meds-preop": return preop
        case "demo-112-meds-abx": return intraop(cefazolinGivenMinutesAgo: 40)
        case "demo-112-meds-overdue": return intraop(cefazolinGivenMinutesAgo: 300)
        case "demo-112-meds-deleted": return deleted
        default: return nil
        }
    }

    /// A 67-year-old man for a CABG ×3 with his medications typed in no order and two drips running.
    private static func base() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = 82
        r.setProcedures(PlannedProcedure.parse("CABG x3"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.problems = ["htn", "hld", "cad"]
        r.homeMeds = MedicationCatalog.parse("sertraline 50 daily, metoprolol succinate 50 daily, cephalexin 500 qid, lisinopril 10 daily, levothyroxine 75 mcg daily, apixaban 5 bid, atorvastatin 40 nightly")
        r.medFlags = MedicationCatalog.flags(for: r.homeMeds)
        r.homeInfusions = [PatientInfusion(drug: "Heparin", rate: "1200 units/h"), PatientInfusion(drug: "Nitroglycerin", rate: "0.5 mcg/kg/min")]
        return r
    }

    static var preop: PatientRecord { base() }

    /// On the table: Case Timers' antibiotics, chips with doses and free text.
    private static func intraop(cefazolinGivenMinutesAgo minutes: Double) -> PatientRecord {
        var r = base()
        let now = Date()
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: now.addingTimeInterval(-minutes * 60))]),
                                AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: now.addingTimeInterval(-20 * 60))])]
        r.infusions = [PatientInfusion(drug: "Norepinephrine", rate: "0.05 mcg/kg/min")]
        r.notableMeds.toggle("txa"); r.notableMeds.setDose("txa", "1 g")
        r.notableMeds.toggle("milrinoneBolus")
        r.notableMeds.toggle("pcc"); r.notableMeds.setDose("pcc", "1500 units")
        r.notableMeds.toggle("methyleneBlue")
        r.medsGiven = "Methylprednisolone 500 mg"
        r.airwayAtEnd = "intubated"
        return r
    }

    /// The heparin drip taken off the case's list in the room; the nitroglycerin left running.
    private static var deleted: PatientRecord {
        var r = base()
        IntraopInfusionList.remove(r.homeInfusions[0].id, in: &r)
        r.preopSummaryOn = true
        return r
    }
}
#endif
