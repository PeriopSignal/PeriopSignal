import Foundation

#if DEBUG
/// Helper F's demo patients for the malignancy screenshots (-ps.patient <seed>; seeds start with "demo-112-onc"). Start
/// from an existing demo (PatientDemo.record ...) and change what the shot needs.
enum PatientDemo112Onc {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-onc": return onc
        case "demo-112-onc-remission": return remission
        default: return nil
        }
    }

    /// Lung and colorectal cancer chosen on the Malignancy list, prostate cancer recorded on the Genitourinary page (the
    /// Prostate chip shows chosen from there), Other typed, active and metastatic, chemotherapy and radiation, with a
    /// line of dates and agents under Other details; anemia beside them on the same page.
    static var onc: PatientRecord {
        var r = PatientDemo.record
        r.problems = ["htn", "anemia", "malignancy", "prostate-cancer"]
        r.hx.malignancies = ["lung", "colorectal"]
        r.hx.malignancyOther = "thymoma"
        r.hx.malignancyStatus = "active"
        r.hx.malignancyMetastatic = true
        r.hx.malignancyTreatment = ["chemo", "radiation"]
        r.systemNotes = ["heme": "Bleomycin 2024; chest radiation 2019"]
        r.medFlags.remove("insulin")
        r.asaClass = nil
        r.preopSummaryOn = true
        PatientHistoryDetails.sync(&r)
        return r
    }

    /// Breast cancer and lymphoma in remission, treated with chemotherapy: the shorter phrase, "breast cancer; lymphoma
    /// (in remission; chemotherapy)".
    static var remission: PatientRecord {
        var r = PatientDemo.record
        r.problems = ["htn", "malignancy"]
        r.hx.malignancies = ["breast", "lymphoma"]
        r.hx.malignancyStatus = "remission"
        r.hx.malignancyTreatment = ["chemo"]
        r.medFlags.remove("insulin")
        r.asaClass = nil
        r.preopSummaryOn = true
        PatientHistoryDetails.sync(&r)
        return r
    }
}
#endif
