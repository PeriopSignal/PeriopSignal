import Foundation

// MARK: - My Patient as words: the lines each card shows, and the handoff text.

enum PatientSummary {
    struct Line: Hashable {
        var label: String?
        var text: String
        /// Needs attention (allergies, a difficult airway, an event).
        var alert = false
        /// Parts of the text to show in bold red: abnormal values and scores ("K 5.9", "MELD 3.0 24").
        var marks: [String] = []
        init(_ label: String?, _ text: String, alert: Bool = false, marks: [String] = []) { self.label = label; self.text = text; self.alert = alert; self.marks = marks }
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

    /// "09:41" for today; with another day, "11/03/26 09:41" (1.10, PatientDates).
    static func time(_ d: Date, now: Date = Date()) -> String {
        if Calendar.current.isDate(d, inSameDayAs: now) {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "HH:mm"
            return fmt.string(from: d)
        }
        return PatientDates.dayTime(d)
    }

    /// The procedure card: what, how urgent, the planned anesthetic and the risk-score inputs it sets.
    static func procedureLines(_ r: PatientRecord) -> [Line] {
        let r = r.capitalized
        var out: [Line] = []
        let what = r.procedure.trimmingCharacters(in: .whitespacesAndNewlines)
        if !what.isEmpty { out.append(Line(nil, what)) }
        let noSide = r.procedures.filter(\.needsSide).map(\.title)
        if !noSide.isEmpty { out.append(Line("Side not set", noSide.joined(separator: ", "), alert: true)) }
        var how: [String] = []
        if let u = r.urgency { how.append(u.label) }
        let an = anestheticText(r)
        if !an.isEmpty { how.append(an) }
        if !how.isEmpty { out.append(Line(nil, how.joined(separator: " · "), alert: r.emergency)) }
        var risk: [String] = []
        if r.highRiskSurgery && !PatientRules.cardiacSurgery(r) { risk.append("High-risk surgery (RCRI)") }
        if let i = r.incision { risk.append(i + " incision") }
        if let d = r.duration { risk.append(d) }
        if !risk.isEmpty { out.append(Line("Risk-score inputs", risk.joined(separator: " · "))) }
        return out
    }

    /// The demographics card: the one-liner, body size and baseline vitals.
    static func demographicsLines(_ r: PatientRecord) -> [Line] {
        var out: [Line] = []
        if !r.person.isEmpty { out.append(Line(nil, r.person)) }
        let body = bodyLine(r)
        if !body.isEmpty { out.append(Line(nil, body)) }
        if let v = vitalsLine(r) { out.append(Line("Preprocedure vitals", v)) }
        return out
    }

    /// "Hb 9.8 L · Hct ~29 (est.) · … · Lactate 1.4 · T&S A−, screen neg · MRSA neg", the abnormal values and
    /// positive results marked for bold red, with the other results typed after.
    static func labsLine(_ r: PatientRecord) -> Line? {
        let sum = PatientLabs.summary(r)
        let more = LabResults.lineParts(r)
        let note = r.labNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sum.isEmpty || !more.parts.isEmpty || !note.isEmpty else { return nil }
        let text = ([sum.line].filter { !$0.isEmpty } + more.parts + (note.isEmpty ? [] : [note])).joined(separator: " · ")
        return Line("Labs", text, marks: sum.abnormal.map(\.compact) + more.marks)
    }

    /// "MELD 3.0 18 · MELD-Na 17 · Child-Pugh B (8)", when the liver section has what it needs.
    static func liverLine(_ r: PatientRecord) -> Line? {
        guard r.labSections.contains("liver") || r.ascites != nil || r.encephalopathy != nil else { return nil }
        let res = PatientLabs.liver(LiverInput(record: r, dialysis: r.dialysis, ascites: r.ascites, encephalopathy: r.encephalopathy))
        var parts: [String] = []
        var marks: [String] = []
        // Bold red from 15: in Teh 2007 (Gastroenterology 2007;132:1261), 30-day mortality after major surgery in
        // cirrhosis rose steadily with MELD, from 5.7% under 8 to over 50% above 20; 15 marks the middle of that rise.
        if let m = res.meld3 { let t = "MELD 3.0 \(m)"; parts.append(t); if m >= 15 { marks.append(t) } }
        if let m = res.meldNa { let t = "MELD-Na \(m)"; parts.append(t); if m >= 15 { marks.append(t) } }
        if let c = res.childPughClass, let p = res.childPugh { let t = "Child-Pugh \(c.rawValue) (\(p))"; parts.append(t); if c != .a { marks.append(t) } }
        return parts.isEmpty ? nil : Line("Liver", parts.joined(separator: " · "), alert: !marks.isEmpty, marks: marks)
    }

    static func smokingText(_ s: String) -> String { s == "current" ? "Current smoker" : (s == "former" ? "Former smoker" : "Never smoked") }

    /// "Known difficult airway; PONV or motion sickness; …", flagged when it matters for this anesthetic.
    static func anestheticComplications(_ r: PatientRecord) -> Line? {
        let r = r.capitalized
        let ah = PatientCatalog.anesthesiaHistory.filter { r.anesthesiaHistory.contains($0.id) }.map(\.label)
        let note = r.anesthesiaNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ah.isEmpty || !note.isEmpty else { return nil }
        let serious: Set<String> = ["mh", "difficult-airway", "pseudocholinesterase"]
        return Line("Anesthetic complications", (ah + (note.isEmpty ? [] : [note])).joined(separator: "; "), alert: !r.anesthesiaHistory.isDisjoint(with: serious))
    }

    static func ecgText(_ r: PatientRecord) -> String? {
        let r = r.capitalized
        let note = r.ecgNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = r.ecg + (note.isEmpty ? [] : [note])
        return all.isEmpty ? nil : all.joined(separator: "; ")
    }

    /// "RA 12, PA 52/24 (mean 33), PCWP 22, CO 3.8": the measured values; the derived ones are on the RHC page.
    static func rhcText(_ r: PatientRecord) -> String? {
        let h = r.rhc
        guard !h.isEmpty else { return nil }
        var parts: [String] = []
        if let v = h.ra { parts.append("RA " + f(v)) }
        if let s = h.pasp, let d = h.padp { parts.append("PA " + f(s) + "/" + f(d) + (h.pam.map { " (mean " + f($0) + ")" } ?? "")) }
        else if let m = h.pam { parts.append("PA mean " + f(m)) }
        if let v = h.pcwp { parts.append("PCWP " + f(v)) }
        if let v = h.co { parts.append("CO " + f(v)) }
        let head = h.date.isEmpty ? "" : "RHC " + h.date.text + ": "
        return parts.isEmpty ? nil : head + parts.joined(separator: ", ")
    }

    static func historyLines(_ r: PatientRecord, now: Date = Date()) -> [Line] {
        let original = r
        let r = r.capitalized
        var out: [Line] = []
        if r.noHistory && r.problems.isEmpty { out.append(Line(nil, "No significant medical history")) }
        for sys in PatientCatalog.allSystems {
            // Smoking leads the Smoking & Substances items (HistorySections.socialItems, 1.9).
            var items = HistorySections.items(sys, r)
            // Other [system] disorders, then Other details (1.9).
            if let o = r.systemOther[sys.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !o.isEmpty { items.append(o) }
            if let n = r.systemNotes[sys.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { items.append(n) }
            if !items.isEmpty { out.append(Line(sys.name, items.joined(separator: "; "))) }
        }
        // The history's warnings, after the systems (1.9): "Aspiration risk: hiatal hernia", "Heparin caution: GI bleed".
        out += PatientWarnings.lines(r)
        let other = r.otherHistory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !other.isEmpty { out.append(Line("Other conditions", other)) }
        if !r.surgeries.isEmpty { out.append(Line("Past surgical history", r.surgeries.map(\.text).joined(separator: "; "))) }
        // 1.9: the allergy list with each severity (anaphylaxis in red), and the allergies typed before 1.9 while the list
        // does not hold them (PatientAllergyText).
        if let a = PatientAllergyText.line(original) { out.append(a) }
        // The medication list (1.9: the items, then the list typed before 1.9 while the items do not hold its drugs);
        // the flags only add what needs action (an anticoagulant, a GLP-1 agonist), so the same drugs are not listed
        // twice. With no list, the flags are the list.
        let flags = PatientCatalog.medFlags.filter { r.medFlags.contains($0.id) }
        let watched = flags.filter { watchFlags.contains($0.id) }.map(\.label)
        var listed = r.homeMeds.map(\.text).filter { !$0.isEmpty }
        let typedText = r.medications.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typedText.isEmpty, listed.isEmpty || !MedicationCatalog.covers(original.homeMeds, legacy: original.medications) { listed.append(typedText) }
        let typed = listed.joined(separator: "; ")
        if !typed.isEmpty {
            out.append(Line("Medications", typed))
            if !watched.isEmpty { out.append(Line("Medication alerts", watched.joined(separator: ", "), alert: true)) }
        } else if !flags.isEmpty {
            out.append(Line("Medications", flags.map(\.label).joined(separator: ", "), alert: !watched.isEmpty))
        }
        let drips = r.homeInfusions.map(\.text).filter { !$0.isEmpty }
        if !drips.isEmpty { out.append(Line("Current infusions", drips.joined(separator: "; "), alert: true)) }
        if let a = anestheticComplications(r) { out.append(a) }
        var npo: [String] = []
        if let d = r.lastSolids { npo.append("solids " + time(d, now: now)) }
        if let d = r.lastClears { npo.append("clear fluids " + time(d, now: now)) }
        if !npo.isEmpty { out.append(Line("Last intake", npo.joined(separator: " · "))) }
        if let l = labsLine(r) { out.append(l) }
        if let m = liverLine(r) { out.append(m) }
        return out
    }

    /// Medication flags that need an action before or after surgery.
    static let watchFlags: Set<String> = ["anticoagulant", "p2y12", "glp1", "sglt2", "maoi", "steroid", "opioid"]

    static func assessmentLines(_ r: PatientRecord) -> [Line] {
        let r = r.capitalized
        var out: [Line] = []
        if let a = PatientRules.asaText(r) {
            out.append(Line("ASA physical status", a))
        } else if let s = PatientRules.asaSuggestion(r) {
            out.append(Line("ASA physical status", "Suggested " + s.label + ", not yet chosen: " + s.topFindings.joined(separator: "; ")))
        }
        if let c = PatientCodeStatus.line(r) { out.append(c) }
        let d = PatientFunctional.dasi(r)
        let fc = [metsText(r), d.map { PatientFunctional.dasiText($0) }].compactMap { $0 }
        if !fc.isEmpty {
            out.append(Line("Functional capacity", fc.joined(separator: " · "), alert: r.mets == "lt4" || (d.map { $0 <= PatientFunctional.dasiCutoff } ?? false)))
        }
        if r.frail { out.append(Line("Frailty", "Frail by a validated tool")) }
        let symptoms = PatientFunctional.cardiacSymptomFlags.filter { r.cardiacSymptoms.contains($0.id) }.map(\.label)
        if !symptoms.isEmpty { out.append(Line("Cardiac symptoms", symptoms.joined(separator: "; "), alert: true)) }
        let active = PatientFunctional.acuteConditions(r)
        if !active.isEmpty { out.append(Line("Acute cardiac conditions", active.joined(separator: "; "), alert: true)) }
        let thoracic = r.allIntrathoracic
        if !thoracic.isEmpty { out.append(Line("Previous intrathoracic surgery", thoracic.map(\.text).joined(separator: "; "), alert: true)) }
        if let e = ecgText(r) { out.append(Line("ECG", e)) }
        if !r.echoFindings.isEmpty { out.append(Line("Echo", r.echoFindings.summary)) }
        if !r.lhc.isEmpty { out.append(Line("Coronaries", r.lhc.summary)) }
        if let h = rhcText(r) { out.append(Line("Right heart cath", h)) }
        let cautions = PatientStudies.cautions(r)
        if !r.carotid.isEmpty {
            out.append(Line("Carotid ultrasound", r.carotid.summary, alert: cautions.contains { $0.id == "carotid" || $0.id.hasPrefix("vertebral") }))
        }
        if !r.radial.isEmpty { out.append(Line("Radial artery ultrasound", r.radial.summary)) }
        if !r.pft.isEmpty { out.append(Line("Pulmonary function tests", r.pft.summary(copd: r.has("copd")))) }
        // The carotid and vertebral cautions; the harvest arm is told with the lines (intraopLines, the handoff).
        for c in cautions where !c.id.hasPrefix("harvest") { out.append(Line("Caution", c.text, alert: true, marks: [c.mark])) }
        if r.isAdult, !r.emergency, r.ageYears != nil {
            let step = PatientFunctional.cardiacStep(r)
            out.append(Line("Cardiac evaluation", step.title, alert: step.alert))
            // The figure's ECG, echo and consultation boxes; the general therapy reminder stays on the screen.
            for a in PatientFunctional.branchAdvice(r) where !a.hasPrefix("Consider starting guideline-directed") {
                out.append(Line("Cardiac advice", a))
            }
            for a in PatientFunctional.conditionAdvice(r) { out.append(Line("Cardiac advice", a, alert: true)) }
        }
        return out
    }

    static func airwayLines(_ r: PatientRecord) -> [Line] {
        let r = r.capitalized
        var out: [Line] = []
        if let a = r.currentAirwayText {
            out.append(Line("Current airway", a, alert: r.arrivesWithAirway))
            if r.arrivesWithAirway && !r.vent.isEmpty && r.oxygen.device != "trachCollar" { out.append(Line("Ventilator", r.vent.text)) }
        }
        if !r.oxygen.isEmpty && (!r.arrivesWithAirway || r.oxygen.device == "trachCollar") { out.append(Line("Oxygen", r.oxygen.text)) }
        if let m = r.mallampati { out.append(Line(nil, PatientAirway.mallampatiLine(m), alert: m >= 3)) }
        if let n = PatientAirway.reviewedNormals(r) { out.append(Line("Exam", n)) }
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
        let r = r.capitalized
        var parts = airwayCourseSentences(r)
        if let end = r.airwayAtEnd, let label = PatientCatalog.airwayAtEnd.first(where: { $0.id == end })?.label {
            let vent = r.ventilation.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append("At handoff: " + label.lowercased() + (end == "intubated" && !vent.isEmpty ? ", " + vent : ""))
        }
        guard !parts.isEmpty else { return nil }
        return Line("Airway", parts.joined(separator: ". ") + ".", alert: difficultAirway(r))
    }

    /// A typed note as one clean fragment: trimmed, with no closing period or comma (the sentence adds its own), so the
    /// course never reads "Beard ." (1.10, Ben's airway example).
    static func courseNote(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, ".;,".contains(last) { t = String(t.dropLast()).trimmingCharacters(in: .whitespaces) }
        return t
    }

    /// The course in the room, one sentence each, without the closing period: mask ventilation, the supraglottic airway,
    /// the intubation (1.9: the new handoff adds how the airway is left itself). 1.10 (Ben, Nov 7): no Han mask-ventilation
    /// grade (a saved one is ignored); the scope reads "Fiberoptic scope", a saved "Flexible scope" too.
    static func airwayCourseSentences(_ r: PatientRecord) -> [String] {
        let r = r.capitalized
        var parts: [String] = []
        let maskNote = courseNote(r.maskNote), sgaNote = courseNote(r.sgaNote)
        let intubationNote = courseNote(r.intubationNote), tubeText = courseNote(r.tube)
        switch r.mask {
        case "easy": parts.append("Mask ventilation easy")
        case "difficult": parts.append("Mask ventilation DIFFICULT" + (maskNote.isEmpty ? "" : ": " + maskNote))
        case "none": parts.append("No mask ventilation")
        default: break
        }
        switch r.sga {
        case "easy": parts.append("Supraglottic airway easy")
        case "difficult": parts.append("Supraglottic airway DIFFICULT" + (sgaNote.isEmpty ? "" : ": " + sgaNote))
        case PatientAirway.placed: parts.append("Supraglottic airway")
        default: break
        }
        var tube: [String] = []
        if let d = PatientAirway.deviceName(r.airwayDevice) { tube.append(d.lowercased()) }
        if let g = r.laryngoscopyGrade { tube.append("grade " + g) }
        if let a = r.attempts { tube.append("\(a) attempt" + (a == 1 ? "" : "s")) }
        let detail = tube.joined(separator: ", ") + (tubeText.isEmpty ? "" : (tube.isEmpty ? "" : "; ") + tubeText)
        switch r.intubation {
        case "easy": parts.append("Intubation easy" + (detail.isEmpty ? "" : ": " + detail))
        case "difficult": parts.append("Intubation DIFFICULT" + (detail.isEmpty ? "" : ": " + detail) + (intubationNote.isEmpty ? "" : ". " + intubationNote))
        case PatientAirway.placed: parts.append("Intubation" + (detail.isEmpty ? "" : ": " + detail))
        case "none": parts.append("Not intubated" + (detail.isEmpty ? "" : ": " + detail))
        default: if !detail.isEmpty { parts.append(detail.prefix(1).uppercased() + detail.dropFirst()) }
        }
        return parts
    }

    /// What the full handoff says for an airway examination or an echo never touched, so a blank is never read as
    /// normal.
    static let notAssessed = "not assessed"

    /// The intraoperative echo is expected: surgery that shows the echo first (cardiac, aortic, transplant) or a TEE
    /// planned.
    static func intraopEchoExpected(_ r: PatientRecord) -> Bool {
        PatientRules.echoFirst(r) || PatientTEE.planned(r)
    }

    /// Mask, supraglottic airway or intubation recorded as difficult (1.10: a saved Han mask grade no longer counts).
    static func difficultAirway(_ r: PatientRecord) -> Bool {
        r.mask == "difficult" || r.sga == "difficult" || r.intubation == "difficult"
    }

    static func intraopLines(_ r: PatientRecord) -> [Line] {
        let r = r.capitalized
        var out: [Line] = []
        if let a = airwayCourse(r) { out.append(a) }
        let placed = PatientDevices.labels(r.devices.filter { $0.placedIntraop && PatientDevice.lineKinds.contains($0.kind) })
        let lines = placed + r.lines.map(\.text).filter { !$0.isEmpty }
        if !lines.isEmpty { out.append(Line("Lines", lines.joined(separator: "; "))) }
        out += limbAlertLines(r)
        out += harvestLines(r)
        let blocks = r.regional.map(\.text).filter { !$0.isEmpty }
        if !blocks.isEmpty { out.append(Line("Regional", blocks.joined(separator: "; "))) }
        let inf = r.infusions.map(\.text).filter { !$0.isEmpty }
        if !inf.isEmpty { out.append(Line("Infusions", inf.joined(separator: "; "))) }
        if let i = PatientRules.fluidLine(r, ids: ["crystalloid", "colloid"]) { out.append(Line("In", i)) }
        if let b = BloodProducts.line(r) { out.append(b) }
        if !r.factors.isEmpty { out.append(Line("Factor concentrates & other products", r.factors)) }
        if let o = PatientRules.fluidLine(r, ids: ["ebl", "uop"]) { out.append(Line("Out", o)) }
        if let l = IntraopLabs.lastLine(r) { out.append(l) }
        if !r.medsGiven.isEmpty { out.append(Line("Medications & interventions", r.medsGiven)) }
        if r.noEvents { out.append(Line("Events", "No notable events")) }
        else if !r.events.isEmpty { out.append(Line("Events", r.events, alert: true)) }
        if let t = PatientTEE.line(r) { out.append(t) }
        // 1.10: the pre- and post-bypass exams ("Echo, pre-bypass" and "Echo, post-bypass" once there is a post-bypass one).
        let exams = PatientEcho.intraopParts(pre: r.intraopEcho, post: r.intraopEchoPost)
        for p in exams { out.append(Line(p.label.map { "Echo, " + ($0 == "Pre" ? "pre-bypass" : "post-bypass") } ?? "Echo", p.text)) }
        if !r.echo.isEmpty { out.append(Line(exams.isEmpty ? "Echo" : "Echo notes", r.echo)) }
        return out
    }

    /// The planned radial artery harvest: where the arterial line and IVs go, and any already on the harvest arm.
    static func harvestLines(_ r: PatientRecord) -> [Line] {
        PatientStudies.cautions(r).filter { $0.id.hasPrefix("harvest") }.map { c in
            Line("Arms", c.text, alert: true, marks: [c.mark])
        }
    }

    /// Limbs to spare (1.9): "Limb alert: L arm — AV fistula; R arm — Prior axillary lymph node dissection". A fistula or
    /// graft on the diagram and the alerts the user added, by limb; a planned radial harvest stays in the Arms line, and an
    /// alert that only says so is not repeated here (PatientDeviceFills.limbAlerts).
    static func limbAlertLines(_ r: PatientRecord) -> [Line] {
        guard let text = PatientDeviceFills.limbAlertText(r) else { return [] }
        return [Line("Limb alert", text, alert: true, marks: PatientDeviceFills.limbAlertGroups(r).map(\.name))]
    }

    /// The lines for one part of the intraoperative record (PatientEditor.intraopParts).
    static func intraopPartLines(_ r: PatientRecord, _ part: String) -> [Line] {
        let r = r.capitalized
        if part == "considerations" { return IntraopConsiderations.text(r).map { [Line(nil, $0, alert: true)] } ?? [] }
        if part == "airway" && r.arrivesWithAirway {
            var out = [Line(nil, (r.currentAirwayText ?? "Secured") + " on arrival")]
            if let end = r.airwayAtEnd { out.append(Line("At handoff", end == "extubated" ? "Extubated" : (end == "intubated" ? "Remains intubated" : end))) }
            return out
        }
        let labels: [String: Set<String>] = [
            "airway": ["Airway"], "lines": ["Lines", "Arms", "Limb alert"], "regional": ["Regional"], "infusions": ["Infusions"],
            "fluids": ["In", "Blood products", "Out", "Factor concentrates & other products"], "labs": ["Last labs"], "meds": ["Medications & interventions"],
            "events": ["Events"], "echo": ["TEE screen", "Echo", "Echo notes"],
        ]
        // The card's own title names the part, so a line labelled the same way drops its label.
        let titles: Set<String> = ["Airway", "Lines", "Regional", "Infusions", "Medications & interventions", "Events", "Echo"]
        var out = intraopLines(r).filter { l in l.label.map { labels[part]?.contains($0) ?? false } ?? false }
            .map { l in titles.contains(l.label ?? "") ? Line(nil, l.text, alert: l.alert, marks: l.marks) : l }
        if part == "events", let end = r.airwayAtEnd, r.arrivesWithAirway || r.intubation != nil {
            out.append(Line("At handoff", end == "extubated" ? "Extubated" : (end == "intubated" ? "Remains intubated" : (PatientCatalog.airwayAtEnd.first { $0.id == end }?.label ?? end))))
        }
        return out
    }

    /// Lines and devices present on arrival (the preoperative picture).
    static func arrivalDeviceLines(_ r: PatientRecord) -> [Line] {
        let lines = PatientDevices.labels(r.currentDevices(arrivalOnly: true).filter { PatientDevice.lineKinds.contains($0.kind) })
        return lines.isEmpty ? [] : [Line(nil, lines.joined(separator: "; "))]
    }

    /// IABP, Impella, LVAD and ECMO with their settings, each on its own line.
    static func supportLines(_ r: PatientRecord) -> [Line] {
        PatientDevices.labels(r.mechanicalSupport).map { Line(nil, $0, alert: true) }
    }

    static func planLines(_ r: PatientRecord) -> [Line] {
        let r = r.capitalized
        var out: [Line] = []
        if let d = r.disposition { out.append(Line("Disposition", d)) }
        if !r.painPlan.isEmpty { out.append(Line("Pain plan", r.painPlan)) }
        if !r.callIf.isEmpty { out.append(Line("Call if", r.callIf)) }
        if !r.todos.isEmpty { out.append(Line("To do & concerns", r.todos)) }
        return out
    }
}

// MARK: - Handoff

enum HandoffWriter {
    /// How to hand over, from the HATRICC operating-room-to-ICU protocol (Lane-Fall MB, et al. Implement Sci 2021) and
    /// the open handoff studies; in a PACU, anesthesia often reports alone.
    static let steps = [
        "Connect the monitors and make sure the patient is stable before the report.",
        "Face to face, with this template, and with as few interruptions as possible.",
        "Surgeon's report, then anesthesia's.",
        "The receiving clinician sums up; questions answered.",
        "Exchange contact details.",
    ]

    /// The anesthesia handoff, section by section, leaving out what is not recorded.
    static func text(_ r: PatientRecord, now: Date = Date()) -> String {
        let r = r.capitalized
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
        if let c = PatientCodeStatus.text(r) { head.append("Code status: " + c) }
        out.append(contentsOf: head)

        func section(_ title: String, _ lines: [PatientSummary.Line]) {
            guard !lines.isEmpty else { return }
            out.append("")
            out.append(title.uppercased())
            for l in lines { out.append((l.label.map { $0 + ": " } ?? "") + l.text) }
        }
        section("Key considerations", IntraopConsiderations.text(r).map { [PatientSummary.Line(nil, $0)] } ?? [])
        section("History", PatientSummary.historyLines(r, now: now))
        var assess = PatientSummary.assessmentLines(r).filter { $0.label != "Cardiac evaluation" && $0.label != "Cardiac advice" && $0.label != "Code status" }
        // An echo never entered says so, where the echo would be (before the catheterizations).
        if r.echoFindings.isEmpty {
            let at = assess.firstIndex { ["Coronaries", "Right heart cath"].contains($0.label ?? "") } ?? assess.count
            assess.insert(PatientSummary.Line("Echo", PatientSummary.notAssessed), at: at)
        }
        for (id, sc) in r.scores.sorted(by: { $0.key < $1.key }) {
            assess.append(PatientSummary.Line(Scores.byID(id)?.name ?? id, PatientRules.scoreLine(id, sc) + (sc.detail.map { " (" + $0 + ")" } ?? "")))
        }
        section("Assessment", assess)
        // No preoperative airway examination in the handoff (1.8.3): the airway now, then the intraoperative course.
        var airway = PatientSummary.handoffAirwayLines(r)
        if let c = PatientSummary.airwayCourse(r) { airway.append(PatientSummary.Line("Course", c.text, alert: c.alert)) }
        section("Airway", airway)
        // Every line and device in place now, on arrival or placed in the room, with the mechanical support.
        let lines = PatientDevices.labels(r.currentDevices().filter { PatientDevice.lineKinds.contains($0.kind) }).map { PatientSummary.Line("Line", $0) }
        let support = PatientSummary.supportLines(r).map { PatientSummary.Line("Support", $0.text, alert: true) }
        section("Lines & devices", PatientSummary.limbAlertLines(r) + PatientSummary.harvestLines(r) + lines + support)
        let told: Set<String> = ["Airway", "Lines", "Arms", "Limb alert"]
        var intraop = PatientSummary.intraopLines(r).filter { !told.contains($0.label ?? "") }
        // An intraoperative echo expected (cardiac, aortic or transplant surgery, or a TEE planned) and not entered.
        if PatientSummary.intraopEchoExpected(r) && r.intraopEcho.isEmpty && r.intraopEchoPost.isEmpty && r.echo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            intraop.append(PatientSummary.Line("Echo", PatientSummary.notAssessed))
        }
        section("Intraoperative", intraop)
        section("Plan", PatientSummary.planLines(r))
        out.append(footer(now))
        return out.joined(separator: "\n")
    }

    /// The short version, one screen: who and what, allergies, the airway, lines and drips, events, and where the
    /// patient goes with when to call.
    static func shortText(_ original: PatientRecord, now: Date = Date()) -> String {
        let r = original.capitalized
        var out: [String] = ["ANESTHESIA HANDOFF (SHORT)"]
        if !r.oneLiner.isEmpty { out.append(r.oneLiner) }
        var proc: [String] = []
        if !r.procedure.isEmpty { proc.append(r.procedure) }
        if let u = r.urgency, u != .elective { proc.append(u.label) }
        let an = PatientSummary.anestheticText(r)
        if !an.isEmpty { proc.append(an) }
        if let a = PatientRules.asaText(r) { proc.append(a) }
        if !proc.isEmpty { out.append(proc.joined(separator: " · ")) }

        func line(_ label: String, _ text: String) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(label + ": " + t) }
        }
        line("Code status", PatientCodeStatus.text(r) ?? "")
        line("Key considerations", IntraopConsiderations.text(r) ?? "")
        // The allergies as the summary and the full handoff give them (1.9: the list, then the text typed before 1.9).
        line("Allergies", PatientAllergyText.line(original)?.text ?? "")
        // Positive and pending infectious results only (Ben, Nov 3); the full handoff lists every one entered.
        line("Infectious results", LabResults.shortInfectious(r))
        if r.arrivesWithAirway, let a = r.currentAirwayText {
            var t = a + " on arrival"
            if !r.vent.isEmpty && r.oxygen.device != "trachCollar" { t += "; " + r.vent.text }
            if let end = r.airwayAtEnd { t += "; at handoff: " + (end == "intubated" ? "remains intubated" : (PatientCatalog.airwayAtEnd.first { $0.id == end }?.label.lowercased() ?? end)) }
            line("Airway", t)
        } else if let c = PatientSummary.airwayCourse(r) { line("Airway", c.text) }
        line("Lines", PatientDevices.labels(r.currentDevices().filter { PatientDevice.lineKinds.contains($0.kind) }).joined(separator: "; "))
        line("Limb alert", PatientDeviceFills.limbAlertText(r) ?? "")
        line("Arms", PatientSummary.harvestLines(r).map(\.text).joined(separator: " "))
        line("Cautions", PatientStudies.cautions(r).filter { !$0.id.hasPrefix("harvest") }.map(\.text).joined(separator: " "))
        line("Support", PatientDevices.labels(r.mechanicalSupport).joined(separator: "; "))
        line("Drips", (r.infusions.isEmpty ? r.homeInfusions : r.infusions).map(\.text).filter { !$0.isEmpty }.joined(separator: "; "))
        line("Blood products", BloodProducts.text(r))
        line("Last labs", IntraopLabs.lastLine(r, now: now, abnormalOnly: true)?.text ?? "")
        line("Events", r.noEvents ? "No notable events" : r.events)
        if let t = PatientTEE.line(r) { line("TEE screen", t.text) }
        var plan: [String] = []
        if let d = r.disposition { plan.append(d + ".") }
        let call = r.callIf.trimmingCharacters(in: .whitespacesAndNewlines)
        if !call.isEmpty { plan.append("Call if " + call.lowercasedFirst + (call.hasSuffix(".") ? "" : ".")) }
        line("Plan", plan.joined(separator: " "))
        out.append(footer(now))
        return out.joined(separator: "\n")
    }

    private static func footer(_ now: Date) -> String {
        "\nPrepared with Periop Signal, " + PatientSummary.time(now, now: now.addingTimeInterval(86_400 * 2)) + ". Check against the chart."
    }
}
