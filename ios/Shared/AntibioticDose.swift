import Foundation

// MARK: - The antibiotic's dose and a logged dose's time, changed in Case Timers (1.12 follow-up, Ben, Nov 13)
//
// Ben: "Have ability to change antibiotic dose in case timer." His answers: (1) the antibiotic's dose, typed beside the drug's
// name ("3 g", "1.5 g"), used for the first dose and every redose, shown in the Intraoperative row, on the Medications page and
// in the handoff, with the worked-out dose kept as a hint; one dose per antibiotic for the case, not one per logged dose.
// (2) the time of a dose already logged, changed the way the Heparin & ACT log rows are, the redose countdown moving with it.
//
// The dose is text AS TYPED, like `TimedEntry.given`: never computed, converted or corrected, no unit added, and no dose check
// runs on it (the checks of `CaseTimerEngine` are for the numbers Case Timers works out itself; the quick-add bar puts no check
// on a typed antibiotic dose either, so none is added here). `AntibioticCourse.dose` holds it; nil is the worked-out dose.
// Everything that shows a course's dose asks `AntibioticDoseText`, so the card, the Intraoperative row, the Medications page and
// the handoff cannot disagree.

extension AntibioticCourse {
    /// The longest dose text kept: one line, short.
    static let doseMaxLength = 24

    /// A dose as typed, kept as one trimmed line of at most 24 characters; empty or whitespace is nil (back to the worked-out dose).
    static func cleanDose(_ typed: String?) -> String? {
        guard let typed else { return nil }
        let oneLine = typed.split(whereSeparator: \.isNewline).joined(separator: " ")
        let cut = String(oneLine.trimmingCharacters(in: .whitespacesAndNewlines).prefix(doseMaxLength))
        let t = cut.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// A new course whose first dose is logged at `time` ("Log dose" / "Log dose & start timer", and leaving with a pick pending): the
    /// redose interval chosen (0: none) and the dose typed for the pick before it was logged (nil: the worked-out dose).
    static func started(drug: String, time: Date, ebl: Double, every: Double, typedDose: String?) -> AntibioticCourse {
        AntibioticCourse(drug: drug, doses: [TimedEntry(time: time, ebl: ebl)], everyMinutes: every, dose: cleanDose(typedDose))
    }

    /// Sets the course's dose from what was typed (nil, empty or whitespace clears it).
    mutating func setDose(_ typed: String?) { dose = Self.cleanDose(typed) }

    /// Changes the time of one logged dose; false when the id is not in the course or the time is after `now` (a dose is one already
    /// given). The dose stays in the list as it is, with its blood loss and its typed text; everything reads `last` as the latest by
    /// time, so the redose and the reminders built on it move with it (`CaseTimerEngine.reminders`).
    @discardableResult
    mutating func updateDose(_ id: UUID, time: Date, now: Date = Date()) -> Bool {
        guard time <= now, let i = doses.firstIndex(where: { $0.id == id }) else { return false }
        doses[i].time = time
        return true
    }
}

extension CaseTimers {
    /// The dose of one antibiotic's course (nil clears it); false when the course is not there.
    @discardableResult
    mutating func setAntibioticDose(_ typed: String?, drug: String) -> Bool {
        guard let i = antibiotics.firstIndex(where: { $0.drug == drug }) else { return false }
        antibiotics[i].setDose(typed)
        return true
    }

    /// Changes the time of one logged dose of a course. When that moves the course's latest dose, the snoozes and "stopped" marks
    /// on its reminders are cleared, as a new dose clears them (`markDone`): they belonged to the occurrence that ran from the old
    /// time (a due time, or for the blood-loss rule the dose it runs from), and a stale one must not hide a later reminder. A change
    /// that leaves the latest dose where it was leaves the reminders, and so their snoozes, exactly as they were.
    @discardableResult
    mutating func updateAntibioticDose(_ id: UUID, drug: String, time: Date, now: Date = Date()) -> Bool {
        guard let i = antibiotics.firstIndex(where: { $0.drug == drug }) else { return false }
        let before = antibiotics[i].last?.time
        guard antibiotics[i].updateDose(id, time: time, now: now) else { return false }
        if antibiotics[i].last?.time != before { clearAntibioticSnoozes(drug) }
        return true
    }
}

/// What a course's dose reads as, everywhere.
enum AntibioticDoseText {
    /// The same dose to the eye: "1 g" and "1g" and "1 G" are one.
    static func same(_ a: String, _ b: String) -> Bool {
        func plain(_ s: String) -> String { s.lowercased().filter { !$0.isWhitespace } }
        return plain(a) == plain(b)
    }

    private static func typed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// The dose of a course for display in a line (the Intraoperative row, the Medications page, the handoff; the record-only line):
    /// the course's own dose when it is set; otherwise exactly what those lines showed before 1.12: the dose typed with the last dose,
    /// else the dose Case Timers works out (`workedOut`), which a course recorded only does not have ("" then).
    static func line(_ course: AntibioticCourse, workedOut: String?) -> String {
        if let d = course.dose { return d }
        if let t = typed(course.last?.given) { return t }
        return course.reminders ? (workedOut ?? "") : ""
    }

    /// The dose beside the drug's name on Case Timers' card: the custom dose (a course's, or one set with a pending pick), else the
    /// worked-out dose as before.
    static func header(custom: String?, workedOut: String) -> String { custom ?? workedOut }

    /// The dose beside the name of a course whose drug Case Timers' list does not have: the custom dose, else the one typed with the
    /// last dose; "" when neither.
    static func typedCourseHeader(_ course: AntibioticCourse) -> String { course.dose ?? typed(course.last?.given) ?? "" }

    /// "Worked out: 2 g (cefazolin, 82 kg)": the hint under the field, in the existing dose wording. A dose that cannot be worked
    /// out says so in the existing words ("Weight needed") with the written dose; a per-kg dose carries its own working.
    static func hint(_ def: AntibioticDef, record r: PatientRecord) -> String {
        let w = CaseTimerEngine.antibioticDose(def, record: r)
        if let needs = w.needs { return "Worked out: " + needs + " (" + w.text + ")" }
        if w.text.contains("(") { return "Worked out: " + w.text }
        var who = def.name.lowercased()
        if def.doseG != nil, let kg = r.weightKg, kg > 0 { who += ", " + CaseTimerEngine.fmt(kg.rounded()) + " kg" }
        return "Worked out: " + w.text + " (" + who + ")"
    }

    /// "worked out: 2 g", the quiet text beside a custom dose in the header.
    static func workedOutNote(_ def: AntibioticDef, record r: PatientRecord) -> String {
        let w = CaseTimerEngine.antibioticDose(def, record: r)
        return "worked out: " + (w.needs?.lowercasedFirst ?? w.text)
    }

    /// "Use the worked-out dose (2 g)": clears the custom dose; no number in it where the dose cannot be worked out.
    static func useWorkedOutTitle(_ def: AntibioticDef, record r: PatientRecord) -> String {
        let w = CaseTimerEngine.antibioticDose(def, record: r)
        // A per-kg dose keeps its working in the hint, not in the link: "(1,230 mg)", not "(1,230 mg (15 mg/kg × 82 kg))".
        let head = w.text.components(separatedBy: " (").first ?? w.text
        return w.needs == nil ? "Use the worked-out dose (\(head))" : "Use the worked-out dose"
    }

    /// What the field opens with: the custom dose, else the dose shown (a long worked-out text such as "1,230 mg (15 mg/kg × 82 kg)"
    /// opens as the dose without its working, so the 24-character limit never cuts it in the middle).
    static func prefill(custom: String?, shown: String) -> String {
        if let custom { return custom }
        if shown.count <= AntibioticCourse.doseMaxLength { return shown }
        let head = shown.components(separatedBy: " (").first ?? shown
        return limited(head)
    }

    /// While typing: one line, at most 24 characters (no trimming, so a space between words can be typed).
    static func limited(_ s: String) -> String {
        String(s.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).joined(separator: " ").prefix(AntibioticCourse.doseMaxLength))
    }
}
