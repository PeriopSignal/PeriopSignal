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
            return ("difficult", note.localizedCaseInsensitiveContains("Han grade") ? note : noteWithHan(g, note))
        }
        return (mask ?? "easy", note)
    }

    /// What a Han grade of 3 or 4 says, as the mask note puts it.
    static func hanNote(_ g: Int) -> String { "Han grade \(g)" + (g == 4 ? ", unable to mask ventilate" : "") }

    /// The mask note with a Han grade in front ("Han grade 4, unable to mask ventilate; Beard"); a Han grade already at
    /// its front is replaced, so the grade is never written twice.
    static func noteWithHan(_ g: Int, _ note: String) -> String {
        var n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = n.range(of: #"^Han grade [1-4](?:, unable to mask ventilate)?\s*;?\s*"#, options: [.regularExpression, .caseInsensitive]) {
            n.removeSubrange(r)
        }
        return n.isEmpty ? hanNote(g) : hanNote(g) + "; " + n
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

// MARK: - 1.12 the handoff's airway course, as one short line (Ben, Nov 10)
//
// "Easy Mask, Easy VL Intubation, ETT 8.0 at 23 cm. Remains intubated, AC/VC 450 × 18, PEEP 8, FiO₂ 60%". An easy airway
// says what a receiving team needs (the ease of each step, the device, the tube and where it sits, how the patient leaves);
// a grade 1-2 view and a single attempt are left unsaid. A difficult one keeps its details on the line, in red: the grade,
// the attempts, the adjunct the note holds, whatever the note says about the mask. Nothing recorded as difficult, no
// adjunct, no attempt count above one and no grade 3-4 view is ever dropped. The Summary cards and the older handoff
// writer keep their longer sentences (PatientSummary.airwayCourseSentences).

enum PatientAirwayLine {
    /// The line, whether it needs attention, and the parts of it to show in bold red.
    struct Course: Equatable {
        var text: String
        var alert: Bool
        var marks: [String]
    }

    /// The first letter lower-cased in the middle of a line ("Bougie" -> "bougie"), unless the word is an acronym or a
    /// name written in capitals ("VL", "LMA rescue"), or the name Han (a saved Han grade, noteWithHan).
    static func lowerFirst(_ s: String) -> String {
        guard let first = s.first, first.isUppercase else { return s }
        if let second = s.dropFirst().first, second.isUppercase { return s }
        if s.hasPrefix("Han ") { return s }
        return first.lowercased() + s.dropFirst()
    }

    /// The device as the line says it: DL, VL, Fiberoptic; nil for any other (the Supraglottic airway and Face mask only
    /// devices of older saves), which the details then name in words.
    static func deviceWord(_ saved: String?) -> String? {
        guard let name = PatientAirway.deviceName(saved) else { return nil }
        switch name {
        case "Direct laryngoscope": return "DL"
        case "Video laryngoscope": return "VL"
        case "Fiberoptic scope": return "Fiberoptic"
        default: return nil
        }
    }

    private static let tubeFiller: Set<String> = ["ett", "et", "tube", "endotracheal", "cuffed", "at", "the", "lip", "teeth", "oral", "id", "size", "mm", "taped", "x"]

    /// The tube as typed ("8.0 cuffed ETT (23 cm)", "7.5 ETT, 23 cm at the lip") as the short line says it: "ETT 8.0 at
    /// 23 cm". Only when the words are the size and the depth and nothing else; any other word (uncuffed, armored, nasal, a
    /// double-lumen tube) means the typed text stands as it was written, with "ETT" in front unless it already names the
    /// tube, so nothing typed is lost. A depth said at the lip or the teeth keeps it: "ETT 7.5 at 22 cm (teeth)".
    static func tubeText(_ raw: String) -> String {
        let typed = PatientSummary.courseNote(raw)
        guard !typed.isEmpty else { return "" }
        func asWritten() -> String {
            let lower = typed.lowercased()
            let names = ["ett", "tube", "dlt", "double", "lumen", "trach", "blocker", "lma", "gel"]
            return names.contains { lower.contains($0) } ? typed : "ETT " + typed
        }
        var rest = typed
        var depth: String?
        if let rx = try? NSRegularExpression(pattern: #"(\d{1,2}(?:\.\d)?)\s*cm"#, options: [.caseInsensitive]) {
            let ns = rest as NSString
            if let m = rx.firstMatch(in: rest, range: NSRange(location: 0, length: ns.length)) {
                depth = ns.substring(with: m.range(at: 1))
                rest = ns.replacingCharacters(in: m.range, with: " ")
            }
        }
        let separators = CharacterSet(charactersIn: " ,;()/#:")
        let tokens = rest.lowercased().components(separatedBy: separators).filter { !$0.isEmpty }
        let left = tokens.filter { !tubeFiller.contains($0) }
        var size: String?
        if left.count == 1 {
            guard left[0].range(of: #"^\d{1,2}(\.\d)?$"#, options: .regularExpression) != nil, let v = Double(left[0]), v >= 2, v <= 10 else { return asWritten() }
            size = left[0]
        } else if !left.isEmpty {
            return asWritten()
        }
        guard size != nil || depth != nil else { return asWritten() }
        let reference = tokens.contains("teeth") ? " (teeth)" : (tokens.contains("lip") ? " (lip)" : "")
        var out = "ETT"
        if let size { out += " " + size }
        if let depth { out += " at " + depth + " cm" + reference }
        return out
    }

    /// The LMA as the line says it: "LMA 4" (a size typed alone, or the words typed), "LMA" with no size.
    static func lmaText(_ r: PatientRecord) -> String {
        guard PatientAirway.tubeIsLMA(r) else { return "LMA" }
        let t = PatientSummary.courseNote(r.tube)
        if t.isEmpty { return "LMA" }
        return t.rangeOfCharacter(from: .letters) == nil ? "LMA " + t : t
    }

    /// The course in the room, as clauses: mask, LMA, intubation with its details, the tube. `red` holds the parts that
    /// need attention.
    static func clauses(_ r: PatientRecord) -> (clauses: [String], red: [String]) {
        var out: [String] = []
        var red: [String] = []
        switch r.mask {
        case "easy": out.append("Easy Mask")
        case "difficult":
            let note = PatientSummary.courseNote(r.maskNote)
            let c = "Difficult Mask" + (note.isEmpty ? "" : " (" + lowerFirst(note) + ")")
            out.append(c); red.append(c)
        default: break  // "Mask not used" is left out
        }
        if PatientAirway.lmaChosen(r) {
            let name = lmaText(r)
            if r.sga == "difficult" {
                let note = PatientSummary.courseNote(r.sgaNote)
                let c = "Difficult " + name + (note.isEmpty ? "" : ", " + lowerFirst(note))
                out.append(c); red.append(c)
            } else {
                out.append(name)
            }
        }
        if PatientAirway.intubationChosen(r) {
            let difficult = r.intubation == "difficult"
            let ease: String? = difficult ? "Difficult" : (r.intubation == "easy" ? "Easy" : nil)
            let word = [ease, deviceWord(r.airwayDevice), "Intubation"].compactMap { $0 }.joined(separator: " ")
            var details: [String] = []
            var notable = false
            if let g = r.laryngoscopyGrade {
                let severe = g.first == "3" || g.first == "4"
                if difficult || severe { details.append("grade " + g) }
                if severe { notable = true }
            }
            if let a = r.attempts {
                if difficult || a > 1 { details.append("\(a) attempt" + (a == 1 ? "" : "s")) }
                if a > 1 { notable = true }
            }
            let note = PatientSummary.courseNote(r.intubationNote)
            if difficult, !note.isEmpty { details.append(lowerFirst(note)) }
            // A device outside DL, VL and Fiberoptic (an older save's) is named in words, not dropped.
            if let d = PatientAirway.deviceName(r.airwayDevice), deviceWord(d) == nil, !PatientAirway.tubeIsLMA(r) { details.append(d.lowercased()) }
            let clause = word + (details.isEmpty ? "" : ", " + details.joined(separator: ", "))
            out.append(clause)
            if difficult { red.append(clause) } else if notable { red.append(details.joined(separator: ", ")) }
            // The tube field holds the LMA's size when the device is the supraglottic airway and no intubation is recorded.
            let tube = PatientAirway.tubeIsLMA(r) ? "" : tubeText(r.tube)
            if !tube.isEmpty { out.append(tube) }
        } else if r.intubation == "none" {
            out.append("Not intubated")
        }
        return (out, red)
    }

    /// The airway course of the handoff: how the airway arrived (secured, or oxygen), the course in the room, the typed
    /// airway notes, and how the patient leaves; nil with none of them.
    static func course(_ r: PatientRecord) -> Course? {
        let c = r.capitalized
        var sentences: [String] = []
        if c.arrivesWithAirway, let a = c.currentAirwayText {
            sentences.append(a + " on arrival" + (!c.vent.isEmpty && c.oxygen.device != "trachCollar" ? ", " + c.vent.text : ""))
        }
        if !c.oxygen.isEmpty && (!c.arrivesWithAirway || c.oxygen.device == "trachCollar") { sentences.append("Oxygen on arrival: " + c.oxygen.text) }
        let room = clauses(c)
        if !room.clauses.isEmpty { sentences.append(room.clauses.joined(separator: ", ")) }
        let notes = PatientSummary.courseNote(c.airwayNotes), exam = PatientSummary.courseNote(c.examNotes)
        if !notes.isEmpty { sentences.append("Airway notes: " + notes) }
        if !exam.isEmpty { sentences.append("Examination: " + exam) }
        if let end = c.airwayAtEnd {
            let vent = PatientSummary.courseNote(c.ventilation)
            switch end {
            case "extubated": sentences.append("Extubated")
            case "intubated": sentences.append("Remains intubated" + (vent.isEmpty ? "" : ", " + vent))
            default:
                if let label = PatientCatalog.airwayAtEnd.first(where: { $0.id == end })?.label { sentences.append("At handoff: " + label.lowercased()) }
            }
        }
        guard !sentences.isEmpty else { return nil }
        let text = sentences.joined(separator: ". ")
        var marks: [String] = []
        for m in room.red where !m.isEmpty && !marks.contains(m) && text.contains(m) { marks.append(m) }
        return Course(text: text, alert: PatientSummary.difficultAirway(c) || !room.red.isEmpty, marks: marks)
    }
}
