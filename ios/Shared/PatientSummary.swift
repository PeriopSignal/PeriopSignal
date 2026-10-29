import Foundation

// MARK: - My Patient as words: the lines each card shows, and the handoff text.

enum PatientSummary {
    struct Line: Hashable {
        var label: String?
        var text: String
        /// Needs attention (allergies, a difficult airway, an event).
        var alert = false
        init(_ label: String?, _ text: String, alert: Bool = false) { self.label = label; self.text = text; self.alert = alert }
    }

    /// Typed values as typed (to two decimals): "Hb 12.8", "Creatinine 1.15".
    private static func f(_ v: Double) -> String { NumText.short(v) }

    /// "96 kg · 178 cm · BMI 30.3 · BSA 2.17 m² · IBW 73 kg · LBW 67 kg".
    static func bodyLine(_ r: PatientRecord) -> String {
        var parts: [String] = []
        if let w = r.weightKg { parts.append(f(w) + " kg") }
        if let h = r.heightCm { parts.append(f(h) + " cm") }
        if let b = r.bmi { parts.append("BMI " + String(format: "%.1f", b)) }
        if let s = r.bsa { parts.append("BSA " + String(format: "%.2f", s) + " m²") }
        if let i = r.ibw { parts.append("IBW " + f(i.rounded()) + " kg") }
        if let l = r.lbw { parts.append("LBW " + f(l.rounded()) + " kg") }
        return parts.joined(separator: " · ")
    }

    static func metsText(_ r: PatientRecord) -> String? {
        switch r.mets {
        case "ge4": return "4 METs or more"
        case "lt4": return "Under 4 METs"
        case "unknown": return "METs unknown"
        default: return nil
        }
    }

    static func anestheticText(_ r: PatientRecord) -> String {
        PatientCatalog.anesthetics.filter { r.anesthetic.contains($0.id) }.map(\.label).joined(separator: " + ")
    }

    static func vitalsLine(_ r: PatientRecord) -> String? {
        var parts: [String] = []
        if let s = r.vitals["sbp"], let d = r.vitals["dbp"] { parts.append("BP " + f(s) + "/" + f(d)) }
        else if let s = r.vitals["sbp"] { parts.append("SBP " + f(s)) }
        if let v = r.vitals["hr"] { parts.append("HR " + f(v)) }
        if let v = r.vitals["spo2"] { parts.append("SpO₂ " + f(v) + "%") }
        if let v = r.vitals["rr"] { parts.append("RR " + f(v)) }
        if let v = r.vitals["temp"] { parts.append(f(v) + " °C") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func time(_ d: Date, now: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = Calendar.current.isDate(d, inSameDayAs: now) ? "HH:mm" : "d MMM HH:mm"
        return fmt.string(from: d)
    }

    static func historyLines(_ r: PatientRecord, now: Date = Date()) -> [Line] {
        var out: [Line] = []
        if r.noHistory && r.problems.isEmpty { out.append(Line(nil, "No significant medical history")) }
        for sys in PatientCatalog.systems {
            var items = sys.problems.filter { r.problems.contains($0.id) }.map(\.label)
            if let n = r.systemNotes[sys.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { items.append(n) }
            if !items.isEmpty { out.append(Line(sys.name, items.joined(separator: "; "))) }
        }
        let other = r.otherHistory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !other.isEmpty { out.append(Line("Other conditions", other)) }
        if let s = r.smoking { out.append(Line("Smoking", s == "current" ? "Current smoker" : (s == "former" ? "Former smoker" : "Never smoked"))) }
        if r.nkda { out.append(Line("Allergies", "No known drug allergies")) }
        else if !r.allergies.isEmpty { out.append(Line("Allergies", r.allergies, alert: true)) }
        // The list as typed; the flags only add what needs action (an anticoagulant, a GLP-1 agonist), so the
        // same drugs are not listed twice. With no list typed, the flags are the list.
        let flags = PatientCatalog.medFlags.filter { r.medFlags.contains($0.id) }
        let watched = flags.filter { watchFlags.contains($0.id) }.map(\.label)
        let typed = r.medications.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            out.append(Line("Medications", typed))
            if !watched.isEmpty { out.append(Line("Medication alerts", watched.joined(separator: ", "), alert: true)) }
        } else if !flags.isEmpty {
            out.append(Line("Medications", flags.map(\.label).joined(separator: ", "), alert: !watched.isEmpty))
        }
        let ah = PatientCatalog.anesthesiaHistory.filter { r.anesthesiaHistory.contains($0.id) }.map(\.label)
        let ahNote = r.anesthesiaNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ah.isEmpty || !ahNote.isEmpty {
            let serious: Set<String> = ["mh", "difficult-airway", "pseudocholinesterase"]
            out.append(Line("Anesthesia history", (ah + (ahNote.isEmpty ? [] : [ahNote])).joined(separator: "; "), alert: !r.anesthesiaHistory.isDisjoint(with: serious)))
        }
        var npo: [String] = []
        if let d = r.lastSolids { npo.append("solids " + time(d, now: now)) }
        if let d = r.lastClears { npo.append("clear fluids " + time(d, now: now)) }
        if !npo.isEmpty { out.append(Line("Last intake", npo.joined(separator: " · "))) }
        let labs = PatientCatalog.labs.compactMap { l -> String? in r.labs[l.id].map { (l.id == "hb" ? "Hb" : (l.id == "plt" ? "Plt" : (l.id == "a1c" ? "HbA1c" : l.label))) + " " + f($0) } }
        let labNote = r.labNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !labs.isEmpty || !labNote.isEmpty { out.append(Line("Labs", (labs + (labNote.isEmpty ? [] : [labNote])).joined(separator: " · "))) }
        return out
    }

    /// Medication flags that need an action before or after surgery.
    static let watchFlags: Set<String> = ["anticoagulant", "p2y12", "glp1", "sglt2", "maoi", "steroid", "opioid"]

    static func assessmentLines(_ r: PatientRecord) -> [Line] {
        var out: [Line] = []
        if let a = PatientRules.asaText(r) {
            out.append(Line("ASA physical status", a))
        } else if let s = PatientRules.asaSuggestion(r) {
            out.append(Line("ASA physical status", "Suggested " + s.label + ", not yet chosen: " + s.topFindings.joined(separator: "; ")))
        }
        let d = PatientFunctional.dasi(r)
        let fc = [metsText(r), d.map { PatientFunctional.dasiText($0) }].compactMap { $0 }
        if !fc.isEmpty {
            out.append(Line("Functional capacity", fc.joined(separator: " · "), alert: r.mets == "lt4" || (d.map { $0 <= PatientFunctional.dasiCutoff } ?? false)))
        }
        if r.frail { out.append(Line("Frailty", "Frail by a validated tool")) }
        let active = PatientFunctional.activeCardiac.filter { r.activeCardiac.contains($0.id) }.map(\.label)
        if !active.isEmpty { out.append(Line("Acute cardiac conditions", active.joined(separator: "; "), alert: true)) }
        if r.isAdult, !r.emergency, r.ageYears != nil {
            let step = PatientFunctional.cardiacStep(r)
            out.append(Line("Cardiac evaluation", step.title, alert: step.alert))
        }
        return out
    }

    static func airwayLines(_ r: PatientRecord) -> [Line] {
        var out: [Line] = []
        if let m = r.mallampati { out.append(Line(nil, PatientAirway.mallampatiLine(m), alert: m >= 3)) }
        let signs = PatientAirway.signs.filter { r.airwaySigns.contains($0.id) }.map(\.label)
        if !signs.isEmpty { out.append(Line("Difficult-airway signs", signs.joined(separator: "; "), alert: signs.count >= 2 || (r.mallampati ?? 0) >= 3)) }
        for m in PatientAirway.maskRisk(r) where m.alert { out.append(Line(nil, m.text, alert: true)) }
        if !r.dentition.isEmpty { out.append(Line("Teeth", r.dentition)) }
        if !r.airwayNotes.isEmpty { out.append(Line("Airway notes", r.airwayNotes)) }
        if !r.examNotes.isEmpty { out.append(Line("Examination", r.examNotes)) }
        return out
    }

    /// "Mask ventilation easy. Intubation easy: video laryngoscope, grade 1, 1 attempt; 7.5 ETT, 23 cm at the lip."
    static func airwayCourse(_ r: PatientRecord) -> Line? {
        var parts: [String] = []
        let grade = r.maskGrade.map { " (grade \($0))" } ?? ""
        switch r.mask {
        case "easy": parts.append("Mask ventilation easy" + grade)
        case "difficult": parts.append("Mask ventilation DIFFICULT" + grade + (r.maskNote.isEmpty ? "" : ": " + r.maskNote))
        case "none": parts.append("No mask ventilation")
        default: if !grade.isEmpty { parts.append("Mask ventilation" + grade) }
        }
        switch r.sga {
        case "easy": parts.append("Supraglottic airway easy")
        case "difficult": parts.append("Supraglottic airway DIFFICULT" + (r.sgaNote.isEmpty ? "" : ": " + r.sgaNote))
        default: break
        }
        var tube: [String] = []
        if let d = r.airwayDevice { tube.append(d.lowercased()) }
        if let g = r.laryngoscopyGrade { tube.append("grade " + g) }
        if let a = r.attempts { tube.append("\(a) attempt" + (a == 1 ? "" : "s")) }
        let detail = tube.joined(separator: ", ") + (r.tube.isEmpty ? "" : (tube.isEmpty ? "" : "; ") + r.tube)
        switch r.intubation {
        case "easy": parts.append("Intubation easy" + (detail.isEmpty ? "" : ": " + detail))
        case "difficult": parts.append("Intubation DIFFICULT" + (detail.isEmpty ? "" : ": " + detail) + (r.intubationNote.isEmpty ? "" : ". " + r.intubationNote))
        case "none": parts.append("Not intubated" + (detail.isEmpty ? "" : ": " + detail))
        default: if !detail.isEmpty { parts.append(detail.prefix(1).uppercased() + detail.dropFirst()) }
        }
        guard !parts.isEmpty else { return nil }
        return Line("Airway", parts.joined(separator: ". ") + ".", alert: difficultAirway(r))
    }

    /// Mask, supraglottic airway or intubation recorded as difficult.
    static func difficultAirway(_ r: PatientRecord) -> Bool {
        r.mask == "difficult" || r.sga == "difficult" || r.intubation == "difficult" || (r.maskGrade ?? 0) >= 3
    }

    /// ASA 2022 follow-up care after a difficult airway: tell the patient, document it, advise an alert or registry.
    static let followUp: [(id: String, label: String, todo: String)] = [
        ("told", "Patient told", "tell the patient (or a responsible person)"),
        ("documented", "Documented in the chart", "document the difficulty and what worked"),
        ("alert", "Alert or registry advised", "advise an alert bracelet or registry"),
    ]

    /// "Patient told. Still to do: document the difficulty and what worked; advise an alert bracelet or registry".
    static func followUpLine(_ r: PatientRecord) -> Line? {
        guard difficultAirway(r) else { return nil }
        let done = followUp.filter { r.airwayFollowUp.contains($0.id) }.map(\.label)
        let todo = followUp.filter { !r.airwayFollowUp.contains($0.id) }.map(\.todo)
        var parts: [String] = []
        if !done.isEmpty { parts.append(done.joined(separator: "; ")) }
        if !todo.isEmpty { parts.append("Still to do: " + todo.joined(separator: "; ")) }
        return Line("Difficult-airway follow-up", parts.joined(separator: ". "), alert: !todo.isEmpty)
    }

    static func intraopLines(_ r: PatientRecord) -> [Line] {
        var out: [Line] = []
        if let a = airwayCourse(r) { out.append(a) }
        if let fu = followUpLine(r) { out.append(fu) }
        let lines = r.lines.map(\.text).filter { !$0.isEmpty }
        if !lines.isEmpty { out.append(Line("Lines", lines.joined(separator: "; "))) }
        let blocks = r.regional.map(\.text).filter { !$0.isEmpty }
        if !blocks.isEmpty { out.append(Line("Regional", blocks.joined(separator: "; "))) }
        let inf = r.infusions.map(\.text).filter { !$0.isEmpty }
        if !inf.isEmpty { out.append(Line("Infusions", inf.joined(separator: "; "))) }
        if let i = PatientRules.fluidLine(r, ids: ["crystalloid", "colloid", "prbc", "plasma", "platelets", "cryo", "cellSaver"]) { out.append(Line("In", i)) }
        if !r.factors.isEmpty { out.append(Line("Factor concentrates and other products", r.factors)) }
        if let o = PatientRules.fluidLine(r, ids: ["ebl", "uop"]) { out.append(Line("Out", o)) }
        if !r.medsGiven.isEmpty { out.append(Line("Medications and interventions", r.medsGiven)) }
        if r.noEvents { out.append(Line("Events", "No notable events")) }
        else if !r.events.isEmpty { out.append(Line("Events", r.events, alert: true)) }
        if !r.echo.isEmpty { out.append(Line("Echo", r.echo)) }
        return out
    }

    static func planLines(_ r: PatientRecord) -> [Line] {
        var out: [Line] = []
        if let d = r.disposition { out.append(Line("Disposition", d)) }
        if !r.painPlan.isEmpty { out.append(Line("Pain plan", r.painPlan)) }
        if !r.callIf.isEmpty { out.append(Line("Call if", r.callIf)) }
        if !r.todos.isEmpty { out.append(Line("To do and concerns", r.todos)) }
        return out
    }
}

// MARK: - Handoff

enum HandoffWriter {
    /// The anesthesia handoff, section by section, leaving out what is not recorded.
    static func text(_ r: PatientRecord, now: Date = Date()) -> String {
        var out: [String] = ["ANESTHESIA HANDOFF"]
        var head: [String] = []
        if !r.oneLiner.isEmpty { head.append(r.oneLiner + (r.bmi.map { " · BMI " + String(format: "%.1f", $0) } ?? "")) }
        var proc: [String] = []
        if !r.procedure.isEmpty { proc.append(r.procedure) }
        if let u = r.urgency { proc.append(u.label) }
        let an = PatientSummary.anestheticText(r)
        if !an.isEmpty { proc.append(an) }
        if let a = PatientRules.asaText(r) { proc.append(a) }
        if !proc.isEmpty { head.append(proc.joined(separator: " · ")) }
        if let v = PatientSummary.vitalsLine(r) { head.append("Baseline: " + v) }
        out.append(contentsOf: head)

        func section(_ title: String, _ lines: [PatientSummary.Line]) {
            guard !lines.isEmpty else { return }
            out.append("")
            out.append(title.uppercased())
            for l in lines { out.append((l.label.map { $0 + ": " } ?? "") + l.text) }
        }
        section("History", PatientSummary.historyLines(r, now: now))
        var assess = PatientSummary.assessmentLines(r).filter { $0.label != "Cardiac evaluation" }
        for (id, sc) in r.scores.sorted(by: { $0.key < $1.key }) {
            assess.append(PatientSummary.Line(Scores.byID(id)?.name ?? id, PatientRules.scoreLine(id, sc) + (sc.detail.map { " (" + $0 + ")" } ?? "")))
        }
        section("Assessment", assess)
        var airway = PatientSummary.airwayLines(r)
        if let c = PatientSummary.airwayCourse(r) { airway.append(PatientSummary.Line("Course", c.text, alert: c.alert)) }
        if let fu = PatientSummary.followUpLine(r) { airway.append(fu) }
        section("Airway", airway)
        let intraop = PatientSummary.intraopLines(r).filter { $0.label != "Airway" && $0.label != "Difficult-airway follow-up" }
        section("Intraoperative", intraop)
        section("Plan", PatientSummary.planLines(r))
        out.append("")
        out.append("Prepared with Periop Signal, " + PatientSummary.time(now, now: now.addingTimeInterval(86_400 * 2)) + ". Check against the chart.")
        return out.joined(separator: "\n")
    }
}
