import Foundation

// A made-up patient for the 1.11 add-grammar and empty-state screenshots (-ps.patient demo-add111, shots 800–819, helper
// C2): the 1.9 medication demo (seven home medications as items, three allergies, the flags read from the list) with the
// airway findings the Airway Examination card shortens (Mallampati III, a thick neck and a neck over 40 cm, so the
// Kheterpal count is 3 of 5 for a man with sleep apnea), a left forearm AV fistula drawn on the figure and a typed right-arm
// limb alert, so the Intraoperative tab's Lines & Devices card shows a limb alert said once. The lines the base demo puts
// in those arms (a left forearm cannula, a right radial arterial line) go: nothing is left in a fistula arm or an alerted
// one.

extension PatientDemo {
    static var add111: PatientRecord {
        var r = meds
        r.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "Prior axillary lymph node dissection")]
        r.devices += ["AVF L forearm"].compactMap { PatientDevices.parse($0)?.device(placedIntraop: false) }
        let alerted = Set(PatientDeviceFills.limbAlerts(r).map(\.limb))
        r.devices.removeAll { d in d.kind != .avFistula && limb(of: d).map { alerted.contains($0) } == true }
        return r
    }

    /// "arm-left", "leg-right"… for a device on a limb site; nil elsewhere.
    static func limb(of d: PatientDevice) -> String? {
        guard let site = d.siteInfo, let side = site.side, ["arm", "leg", "groin"].contains(site.region) else { return nil }
        return (site.region == "arm" ? "arm-" : "leg-") + side
    }
}
