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

    /// A saved Han mask-ventilation grade (retired in 1.10), read into the mask ease it stands for, so what a 1.9 save
    /// said stays in the course, the handoff and the difficult-airway alert (migrate on read). Han R, Tremper KK,
    /// Kheterpal S, O'Reilly M. Grading scale for mask ventilation. Anesthesiology 2004;101:267: grade 3 is difficult
    /// mask ventilation, grade 4 unable to mask ventilate; grades 1-2 are ventilated by mask (with an adjunct for 2).
    /// Conservative choice: 1.9 counted a grade of 3 or 4 as a difficult airway whatever the mask ease, so a grade of 3 or
    /// 4 makes an empty or "easy" mask difficult, with the grade in its note; 1-2 fill only an empty mask, as easy.
    static func migratedMask(_ mask: String?, note: String, grade: Int?) -> (mask: String?, note: String) {
        guard let g = grade, (1...4).contains(g) else { return (mask, note) }
        if g >= 3 {
            guard mask == nil || mask == "easy" else { return (mask, note) }
            let said = "Han grade \(g)" + (g == 4 ? ", unable to mask ventilate" : "")
            let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
            return ("difficult", n.localizedCaseInsensitiveContains("Han grade") ? note : (n.isEmpty ? said : said + "; " + n))
        }
        return (mask ?? "easy", note)
    }

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

    /// `tube` holds the LMA's size, not a tube: the device is the supraglottic airway and no intubation is recorded (the
    /// quick-add bar files "LMA 4" this way). The LMA section shows it then, as the Tube field is under Intubation only.
    static func tubeIsLMA(_ r: PatientRecord) -> Bool {
        supraglotticDevice(r) && !(r.intubation == "easy" || r.intubation == "difficult" || r.intubation == placed)
    }

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

    /// Chooses or clears the LMA. Clearing it clears the LMA's size kept in `tube` too, which would otherwise read as an
    /// intubation's tube (the Intubation chip on, an ETT on the diagram); Undo brings it back.
    static func setLMA(_ on: Bool, _ r: inout PatientRecord) {
        if on {
            if r.sga == nil || r.sga == "none" { r.sga = placed }
        } else {
            r.sga = nil
            r.sgaNote = ""
            if tubeIsLMA(r) { r.tube = "" }
            if supraglotticDevice(r) { r.airwayDevice = nil }
        }
    }
}
