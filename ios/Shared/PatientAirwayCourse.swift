import Foundation

// MARK: - 1.10 airway course (Ben, Nov 7): Mask ventilation; Intubation or LMA
//
// The Intraoperative tab's Airway Course asks for the mask ventilation, then "Intubation or LMA": choosing Intubation
// opens the device chips, the laryngeal view chips and the tube details; choosing LMA opens its ease. The record keeps
// its fields (mask, intubation, sga, airwayDevice, laryngoscopyGrade, attempts, tube); these helpers say which of the
// two is chosen and set it, so a saved patient reads the same way it always did.

extension PatientAirway {
    /// The devices that go with an intubation: the laryngoscopes and the fiberoptic scope. ("Supraglottic airway" and
    /// "Face mask only" stay in the catalog for the quick-add bar and older records; the LMA has its own chip.)
    static var intubationDevices: [String] { [PatientCatalog.devices[0], PatientCatalog.devices[1], fiberoptic] }

    /// "easy" or "difficult" as saved; anything else (none, placed, nil) is no ease recorded.
    static func ease(_ saved: String?) -> String? { saved == "easy" || saved == "difficult" ? saved : nil }

    /// Intubation is chosen: an intubation recorded (easy, difficult, or placed with no ease), or any of its details.
    static func intubationChosen(_ r: PatientRecord) -> Bool {
        if r.intubation == "easy" || r.intubation == "difficult" || r.intubation == placed { return true }
        if let d = deviceName(r.airwayDevice), intubationDevices.contains(d) { return true }
        if r.laryngoscopyGrade != nil || r.attempts != nil { return true }
        return !r.tube.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !supraglotticDevice(r)
    }

    /// An LMA (supraglottic airway) is chosen.
    static func lmaChosen(_ r: PatientRecord) -> Bool {
        r.sga == "easy" || r.sga == "difficult" || r.sga == placed || supraglotticDevice(r)
    }

    private static func supraglotticDevice(_ r: PatientRecord) -> Bool { r.airwayDevice == "Supraglottic airway" }

    /// Chooses or clears Intubation. Clearing it clears its details too (device, view, attempts, tube and the note on
    /// a difficult one); Undo brings them back.
    static func setIntubation(_ on: Bool, _ r: inout PatientRecord) {
        if on {
            if r.intubation == nil || r.intubation == "none" { r.intubation = placed }
        } else {
            r.intubation = nil
            r.intubationNote = ""
            if let d = deviceName(r.airwayDevice), intubationDevices.contains(d) { r.airwayDevice = nil }
            r.laryngoscopyGrade = nil
            r.attempts = nil
            if !supraglotticDevice(r) { r.tube = "" }
        }
    }

    /// Chooses or clears the LMA.
    static func setLMA(_ on: Bool, _ r: inout PatientRecord) {
        if on {
            if r.sga == nil || r.sga == "none" { r.sga = placed }
        } else {
            r.sga = nil
            r.sgaNote = ""
            if supraglotticDevice(r) { r.airwayDevice = nil }
        }
    }
}
