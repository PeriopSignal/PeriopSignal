import Foundation

// A made-up patient for the 1.11 add-grammar and empty-state screenshots (-ps.patient demo-add111, shots 800–819, helper
// C2): the 1.9 medication demo (seven home medications as items, three allergies, the flags read from the list) with the
// airway findings the Airway Examination card shortens (Mallampati III, a thick neck and a neck over 40 cm, so the
// Kheterpal count is 3 of 5 for a man with sleep apnea), a left forearm AV fistula drawn on the figure and a typed right-arm
// limb alert, so the Intraoperative tab's Lines & Devices card shows a limb alert said once.

extension PatientDemo {
    static var add111: PatientRecord {
        var r = meds
        r.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "Prior axillary lymph node dissection")]
        r.devices += ["AVF L forearm"].compactMap { PatientDevices.parse($0)?.device(placedIntraop: false) }
        return r
    }
}
