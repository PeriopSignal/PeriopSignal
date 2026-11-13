import Foundation

// MARK: - 1.9 briefs: the preprocedure summary and the single handoff, as blocks
//
// One block model for both (Ben, Nov 3): a header, then labelled blocks that are left out when the record has nothing
// for them. Every block's text can be edited in place; an edit is kept by block key in PatientRecord.preopSummaryEdits /
// handoffEdits and shown instead of the generated text (with an "edited" mark) until Regenerate clears them. Figures (the
// fishbone and the lines diagram) are never edited: they follow the record.
//
// Formats are Ben's: "76 yo M (80 kg, 180 cm) for Laparoscopic cholecystectomy" (preprocedure) and "… had …" (handoff).
// The handoff keeps what the 1.8.3 full and short handoffs carried for safety (code status, warnings, positive and
// pending infectious results, isolation, TEE contraindications, limb alerts, the radial-harvest arm, difficult-airway
// follow-up, the major considerations, the disposition); the places are in PatientBriefs below.

/// One block of a brief.
struct SummaryBlock: Identifiable, Hashable {
    enum Figure: Hashable {
        /// The labs block's figure. 1.12 (Ben's note 8): no fishbone any more; the case keeps its name so the code that
        /// places the figure keeps compiling. It carries the Preop and Intraop columns (BriefLabs).
        case fishbone(BriefLabs)
        /// The lines diagram, with the block's text as the list on its right; `arrivalOnly` for the preprocedure picture.
        case diagram(arrivalOnly: Bool)
    }

    var key: String
    var label: String?
    var text: String = ""
    var figure: Figure?
    /// Needs attention: the label shows in red.
    var alert = false
    /// Parts of the text to show in bold red (abnormal values, a code status that limits resuscitation).
    var marks: [String] = []
    /// In the copied text, the lines of this block's text are joined on one line with this.
    var joiner: String?
    /// The user's words stand in for the generated ones.
    var edited = false
    /// The text for the plain-text outputs (Copy, "Share as text only") when it differs from the drawn `text` (1.12): the labs
    /// block draws an out-of-range value bold red with no letter, and its plain text keeps the H or L, since colour cannot be
    /// carried there. Nil: the plain text is `text`. An edited block's words are the user's: no plain form.
    var plain: String?
    /// The text for VoiceOver when it differs (1.12): a red value says "low" or "high".
    var spoken: String?

    var id: String { key }
    var lines: [String] { text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    /// The lines of the plain text.
    var plainLinesOfText: [String] { (plain ?? text).components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    /// The labs columns with a value in them, or the lines diagram (built only with a line or device to draw: before the case
    /// a patient with mechanical support alone has it in the workup's words and on this picture, with no list beside it).
    /// A block the user edited counts by its words alone, so one they emptied is left out, figure and all (1.12: the labs
    /// text now holds everything the columns show, so an edited labs block shows the words, not the columns).
    var figureHasContent: Bool {
        switch figure {
        case .fishbone(let l)?: return !edited && !l.isEmpty
        case .diagram?: return !edited
        case nil: return false
        }
    }
    var hasContent: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || figureHasContent }
}

enum PatientBriefs {
    enum Kind { case preop, handoff }

    // MARK: The two briefs

    /// The preprocedure summary: the slots with the user's edits applied, absent blocks left out.
    static func preop(_ r: PatientRecord, now: Date = Date()) -> [SummaryBlock] {
        resolve(slots(.preop, r, now: now), edits: r.preopSummaryEdits)
    }

    /// The handoff, in Ben's order.
    static func handoff(_ r: PatientRecord, now: Date = Date()) -> [SummaryBlock] {
        resolve(slots(.handoff, r, now: now), edits: r.handoffEdits)
    }

    static func blocks(_ kind: Kind, _ r: PatientRecord, now: Date = Date()) -> [SummaryBlock] {
        kind == .preop ? preop(r, now: now) : handoff(r, now: now)
    }

    static func edits(_ kind: Kind, _ r: PatientRecord) -> [String: String] {
        kind == .preop ? r.preopSummaryEdits : r.handoffEdits
    }

    /// A block with an edit shows it (even when the record has nothing for the block any more, and even as the record
    /// changes); one the user emptied stays out; the others show when they have content.
    static func resolve(_ slots: [SummaryBlock], edits: [String: String]) -> [SummaryBlock] {
        var out: [SummaryBlock] = []
        for slot in slots {
            var b = slot
            if let e = edits[b.key] {
                b.text = e
                b.edited = true
                b.plain = nil
                b.spoken = nil
                b.marks = b.marks.filter { e.contains($0) }
            }
            guard b.hasContent else { continue }
            out.append(b)
        }
        return out
    }

    // MARK: Editing

    /// Keeps the user's text for a block; text equal to what the record generates is no edit.
    static func setEdit(_ r: inout PatientRecord, _ kind: Kind, key: String, text: String, now: Date = Date()) {
        let generated = slots(kind, r, now: now).first { $0.key == key }?.text ?? ""
        var edits = kind == .preop ? r.preopSummaryEdits : r.handoffEdits
        if text == generated { edits.removeValue(forKey: key) } else { edits[key] = text }
        if kind == .preop { r.preopSummaryEdits = edits } else { r.handoffEdits = edits }
    }

    /// Regenerate: this brief's edits cleared; the other brief's stay.
    static func regenerate(_ r: inout PatientRecord, _ kind: Kind) {
        if kind == .preop { r.preopSummaryEdits = [:] } else { r.handoffEdits = [:] }
    }

    // MARK: Text

    /// The copied text: the header, then "Label: text" lines; a block of several lines is the label, then its lines
    /// indented; the fishbone is one line ("Labs: BMP: … · CBC: … · Coags: …"), then the other labs after it.
    static func plainText(_ blocks: [SummaryBlock]) -> String {
        var out: [String] = []
        for b in blocks { out += plainLines(b) }
        return out.joined(separator: "\n")
    }

    static func plainLines(_ b: SummaryBlock) -> [String] {
        // The plain text keeps the lab letters H and L that the screen no longer draws (1.12).
        let lines = b.plainLinesOfText
        let label = b.label.map { $0 + ":" }
        if case .fishbone(let labs)? = b.figure {
            // 1.12 (Ben's note 8): the labs text is two labelled paragraphs, "Preop: …" and "Intraop: …" (plain digits for
            // other apps); the small caption with the times follows on its own line while the words are the generated ones.
            guard !lines.isEmpty else { return [] }
            var out: [String] = lines.count == 1 ? [ascii(((label.map { $0 + " " }) ?? "") + lines[0])]
                : [ascii(label ?? "")] + lines.map { "  " + ascii($0) }
            if !b.edited, let c = labs.caption { out.append("  " + ascii(c)) }
            return out
        }
        guard !lines.isEmpty else { return [] }
        if let j = b.joiner { return [((label.map { $0 + " " }) ?? "") + lines.joined(separator: j)] }
        if label == nil { return lines }
        if lines.count == 1 { return [((label.map { $0 + " " }) ?? "") + lines[0]] }
        return [label ?? ""] + lines.map { "  " + $0 }
    }

    /// The line that closes a brief when it is copied or shared, as the 1.8.3 handoffs' did: when it was prepared, and to
    /// check it against the chart.
    static func footer(_ now: Date) -> String {
        "Prepared with Periop Signal, " + PatientSummary.time(now, now: now.addingTimeInterval(86_400 * 2)) + ". Check against the chart."
    }

    /// What Copy and Share give: the brief's text, a blank line, then the footer.
    static func sharedText(_ blocks: [SummaryBlock], now: Date = Date()) -> String {
        let t = plainText(blocks)
        return t.isEmpty ? footer(now) : t + "\n\n" + footer(now)
    }

    /// "HCO₃" as "HCO3", for text that goes to other apps.
    static func ascii(_ s: String) -> String {
        s.replacingOccurrences(of: "₂", with: "2").replacingOccurrences(of: "₃", with: "3")
    }

    // MARK: Slots (every block, empty or not, in order)

    static func slots(_ kind: Kind, _ r: PatientRecord, now: Date = Date()) -> [SummaryBlock] {
        let hist = PatientSummary.historyLines(r, now: now, dates: .summary(now: now))
        let assess = PatientSummary.assessmentLines(r, dates: .summary(now: now))
        var out: [SummaryBlock] = []
        out.append(headerBlock(r, kind: kind))
        out.append(codeStatusBlock(r))
        if kind == .handoff { out.append(caseBlock(r)) }
        out.append(allergiesBlock(hist))
        out.append(pmhBlock(r, hist: hist, assess: assess))
        out.append(pshBlock(r, now: now))
        if kind == .preop {
            out.append(airwayExamBlock(r))
            out.append(workupBlock(r, assess: assess, kind: kind, now: now))
            out.append(imagingBlock(r))
            out.append(labsBlock(r, kind: kind, now: now))
            out.append(medicationsBlock(r, hist: hist, kind: kind))
            out.append(lastIntakeBlock(hist))
            out.append(linesBlock(r, kind: kind))
            out.append(riskBlock(r))
        } else {
            out.append(airwayCourseBlock(r))
            out.append(workupBlock(r, assess: assess, kind: kind, now: now))
            out.append(imagingBlock(r))
            out.append(intraopTEEBlock(r, now: now))
            out.append(labsBlock(r, kind: kind, now: now))
            out.append(medicationsBlock(r, hist: hist, kind: kind))
            out.append(infusionsBlock(r, now: now))
            out.append(intakeOutputBlock(r))
            out.append(linesBlock(r, kind: kind))
            out.append(regionalBlock(r))
            out.append(eventsBlock(r))
            out.append(riskBlock(r))
            out.append(concernsBlock(r))
        }
        return out
    }

    private static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "label: text" for a summary line.
    private static func joined(_ l: PatientSummary.Line) -> String { (l.label.map { $0 + ": " } ?? "") + l.text }

    // MARK: Header

    /// "76 yo", "4 mo" for an infant, "90+ yo" for 90 or older (HIPAA Safe Harbor, as the record keeps it).
    static func ageText(_ years: Double) -> String {
        if years >= PatientRecord.oldestAge { return "90+ yo" }
        if years < 1 {
            let months = Int((max(years, 0) * 12).rounded())
            return months < 1 ? "<1 mo" : "\(months) mo"
        }
        return "\(Int(years.rounded(.down))) yo"
    }

    /// "76 yo M (80 kg, 180 cm) for Laparoscopic cholecystectomy"; `verb` is "for" before the case and "had" after it. Parts
    /// not recorded are left out; nil with nothing at all.
    static func header(_ r: PatientRecord, verb: String) -> String? {
        let c = r.capitalized
        var who: [String] = []
        if let a = c.ageYears { who.append(ageText(a)) }
        if let s = c.sex { who.append(s == .male ? "M" : "F") }
        var head = who.joined(separator: " ")
        var size: [String] = []
        if let w = c.weightKg { size.append(NumText.short(w) + " kg") }
        if let h = c.heightCm { size.append(NumText.short(h) + " cm") }
        if !size.isEmpty { head += (head.isEmpty ? "" : " ") + "(" + size.joined(separator: ", ") + ")" }
        let proc = trimmed(c.procedure)
        if !proc.isEmpty {
            if head.isEmpty {
                head = String(verb.prefix(1)).uppercased() + String(verb.dropFirst()) + " " + proc
            } else {
                head += " " + verb + " " + proc
            }
        }
        return head.isEmpty ? nil : head
    }

    private static func headerBlock(_ r: PatientRecord, kind: Kind) -> SummaryBlock {
        SummaryBlock(key: "header", label: nil, text: header(r, verb: kind == .preop ? "for" : "had") ?? "")
    }

    /// Code status when it is not full code (the old handoff's Code status line): the orders that limit resuscitation in
    /// red, with the perioperative plan.
    private static func codeStatusBlock(_ r: PatientRecord) -> SummaryBlock {
        var b = SummaryBlock(key: "code", label: "Code status")
        if r.codeStatus != .full, let l = PatientCodeStatus.line(r) {
            b.text = l.text
            b.alert = l.alert
            b.marks = l.marks
        }
        return b
    }

    /// The case the handoff is about: not elective, and the anesthetic given (the old handoff's procedure line).
    private static func caseBlock(_ r: PatientRecord) -> SummaryBlock {
        var parts: [String] = []
        if let u = r.urgency, u != .elective { parts.append(u.label) }
        let an = PatientSummary.anestheticText(r)
        if !an.isEmpty { parts.append(an) }
        return SummaryBlock(key: "case", label: "Case", text: parts.joined(separator: " · "), alert: r.emergency)
    }

    // MARK: History

    private static func allergiesBlock(_ hist: [PatientSummary.Line]) -> SummaryBlock {
        var b = SummaryBlock(key: "allergies", label: "Allergies")
        if let l = hist.first(where: { $0.label == "Allergies" }) {
            b.text = l.text
            b.alert = l.alert
            b.marks = l.marks
        }
        return b
    }

    /// History lines that have a block of their own.
    private static let notPMH: Set<String> = ["Allergies", "Past surgical history", "Medications", "Medication alerts", "Current infusions",
                                              "Last intake", "Labs", "Liver"]
    /// Assessment lines that read as history: function and the cardiac flags.
    private static let assessmentHistory: Set<String> = ["Functional capacity", "Frailty", "Cardiac symptoms", "Acute cardiac conditions"]

    /// The lines of the history that are a list of problems, with no heading of their own in the PMH (1.12, Ben): a system's
    /// (its name is the page's heading, not a problem) and "Other conditions". The warnings (Aspiration risk: ...), the
    /// anesthetic complications and the function lines keep their labels, which are part of what they say.
    private static let unlabelledInPMH: Set<String> = Set(PatientCatalog.allSystems.map(\.name) + ["Other conditions"])

    /// PMH (ASA class): the system pages' words in one paragraph, the history's warnings (aspiration risk, heparin
    /// caution), anesthetic complications, positive infectious items and isolation (they are on the Infectious page's
    /// words), and function, frailty and the active cardiac flags. 1.12 (Ben, Nov 10): the problems in the systems' order,
    /// with no system heading, joined by "; " ("PMH (ASA IV): hypertension; CAD; COPD; ESRD on hemodialysis"); the tab and
    /// the pages keep their headings.
    private static func pmhBlock(_ r: PatientRecord, hist: [PatientSummary.Line], assess: [PatientSummary.Line]) -> SummaryBlock {
        var parts: [String] = []
        var marks: [String] = []
        for l in hist where !notPMH.contains(l.label ?? "") {
            let t = unlabelledInPMH.contains(l.label ?? "") ? l.text : joined(l)
            parts.append(t)
            if l.alert { marks.append(t) }
            marks += l.marks
        }
        for l in assess where assessmentHistory.contains(l.label ?? "") {
            let t = joined(l)
            parts.append(t)
            if l.alert { marks.append(t) }
        }
        let asa = PatientRules.asaText(r)
        // A class chosen with nothing else to say: the class is the block's words, so it is not lost with an empty paragraph.
        if parts.isEmpty, let asa { return SummaryBlock(key: "pmh", label: "PMH", text: asa) }
        // The alerts inside it are in bold red; the label stays plain.
        return SummaryBlock(key: "pmh", label: asa.map { "PMH (" + $0 + ")" } ?? "PMH", text: parts.joined(separator: "; "), marks: marks)
    }

    /// PSH: the past surgical history, with the cardiac or thoracic operations added in the cardiac evaluation.
    private static func pshBlock(_ r: PatientRecord, now: Date) -> SummaryBlock {
        let c = r.capitalized
        let dates = PatientDateStyle.summary(now: now)
        // Newest first (1.12 follow-up, Ben): the entries of the record and the evaluation's own list (a record from before 1.10)
        // are one list.
        var seen = Set(c.surgeries.map { $0.shownText(dates) })
        var all = c.surgeries
        for s in c.intrathoracic {
            let t = s.shownText(dates)
            if !t.isEmpty, !seen.contains(t) { seen.insert(t); all.append(s) }
        }
        let items = PatientSurgery.chronological(all).map { $0.shownText(dates) }.filter { !$0.isEmpty }
        return SummaryBlock(key: "psh", label: "PSH", text: items.joined(separator: "; "))
    }

    private static func lastIntakeBlock(_ hist: [PatientSummary.Line]) -> SummaryBlock {
        SummaryBlock(key: "intake", label: "Last intake", text: hist.first(where: { $0.label == "Last intake" })?.text ?? "")
    }

    // MARK: Medications

    /// Preprocedure: the infusions running, then the home medications and the flags that need action. Handoff: the home
    /// medications with those flags (the infusions are with the intraoperative ones). 1.12 (Ben's note 16): the medication
    /// line follows the order of the Current Medications & Infusions box: infusions, then antibiotics, cardiovascular
    /// medications and the rest, each group in the order entered.
    private static func medicationsBlock(_ r: PatientRecord, hist: [PatientSummary.Line], kind: Kind) -> SummaryBlock {
        var pieces: [(label: String, text: String, alert: Bool)] = []
        if kind == .preop, let i = hist.first(where: { $0.label == "Current infusions" }) { pieces.append(("Infusions", i.text, true)) }
        if let m = hist.first(where: { $0.label == "Medications" }) { pieces.append(("Home", orderedMedications(r, line: m.text), m.alert)) }
        if let a = hist.first(where: { $0.label == "Medication alerts" }) { pieces.append(("Alerts", a.text, true)) }
        var b = SummaryBlock(key: "meds", label: kind == .preop ? "Medications" : "Home medications")
        if pieces.count == 1, pieces[0].label == "Home" {
            b.text = pieces[0].text
        } else {
            b.text = pieces.map { $0.label + ": " + $0.text }.joined(separator: "\n")
        }
        b.alert = pieces.contains { $0.alert && $0.label != "Home" }
        b.marks = pieces.filter { $0.label == "Alerts" }.map { "Alerts: " + $0.text }
        // With no list typed, the flags are the list and an action flag among them is the alert, with or without the
        // infusions beside it.
        if let home = pieces.first(where: { $0.label == "Home" }), home.alert { b.marks.append(home.text); b.alert = true }
        return b
    }

    /// The medication line (PatientSummary.historyLines: the list's items, then any text typed before 1.9) with the list's items
    /// in the shown order: antibiotics, cardiovascular, then the rest. A line that is the flags' words (no list) is as it was.
    static func orderedMedications(_ r: PatientRecord, line: String) -> String {
        let items = r.capitalized.homeMeds
        let stored = items.map(\.text).filter { !$0.isEmpty }.joined(separator: "; ")
        guard !stored.isEmpty, line.hasPrefix(stored) else { return line }
        let ordered = MedicationCatalog.ordered(items).map(\.text).filter { !$0.isEmpty }.joined(separator: "; ")
        return ordered + line.dropFirst(stored.count)
    }

    // MARK: Airway

    /// Airway exam, on one line: how it is secured now if it is, the Mallampati class, the exam, the difficult-airway signs,
    /// the mask-ventilation predictors, the teeth and the notes.
    private static func airwayExamBlock(_ r: PatientRecord) -> SummaryBlock {
        let lines = PatientSummary.airwayLines(r)
        var b = SummaryBlock(key: "airway", label: "Airway exam", text: lines.map { joined($0) }.joined(separator: "; "))
        b.alert = lines.contains { $0.alert }
        b.marks = lines.filter(\.alert).map { joined($0) }
        return b
    }

    /// Airway course, on one line: how it arrived, mask and intubation in the room, and how the patient leaves (extubated,
    /// remains intubated). 1.10: no difficult-airway follow-up sentence. 1.12 (Ben, Nov 10): the short form
    /// (PatientAirwayLine): "Easy Mask, Easy VL Intubation, ETT 8.0 at 23 cm. Remains intubated, AC/VC 450 × 18, PEEP 8";
    /// a difficult airway keeps its details on the line, in red (`marks`).
    static func airwayCourse(_ r: PatientRecord) -> (text: String, alert: Bool, marks: [String])? {
        PatientAirwayLine.course(r).map { ($0.text, $0.alert, $0.marks) }
    }

    private static func airwayCourseBlock(_ r: PatientRecord) -> SummaryBlock {
        var b = SummaryBlock(key: "airway", label: "Airway course")
        if let c = airwayCourse(r) {
            b.text = c.text
            b.alert = c.alert
            b.marks = c.marks
        }
        return b
    }

    // MARK: Cardiac workup, TEE

    private static let workupLabels: Set<String> = ["ECG", "Echo", "Stress test", "Coronaries", "Right heart cath", "Carotid ultrasound", "Radial artery ultrasound",
                                                    "Pulmonary function tests", "Caution"]

    /// Preprocedure cardiac workup: the ECG, echo, catheterizations, carotid and radial ultrasound and PFTs entered, each
    /// on its own line, the carotid and vertebral cautions, the TEE screen's contraindications and (preprocedure) the
    /// mechanical support on arrival. Absent with none. In the handoff the support is in the lines and devices; before the
    /// case it is here only, not listed again under Lines & devices.
    private static func workupBlock(_ r: PatientRecord, assess: [PatientSummary.Line], kind: Kind, now: Date) -> SummaryBlock {
        var lines = assess.filter { workupLabels.contains($0.label ?? "") }
        // 1.11 (Ben's note 4): the stress test, after the echo and before the catheterizations.
        if let s = PatientPreop.stressLine(r, dates: .summary(now: now)) {
            let at = lines.firstIndex { ["Coronaries", "Right heart cath", "Carotid ultrasound", "Radial artery ultrasound", "Pulmonary function tests", "Caution"].contains($0.label ?? "") } ?? lines.count
            lines.insert(s, at: at)
        }
        // 1.12 (Ben's note 11): the chest X-ray, after the stress test (before the catheterizations and ultrasounds).
        if let x = PatientChestXray.line(r) {
            let at = lines.firstIndex { ["Coronaries", "Right heart cath", "Carotid ultrasound", "Radial artery ultrasound", "Pulmonary function tests", "Caution"].contains($0.label ?? "") } ?? lines.count
            lines.insert(x, at: at)
        }
        if let t = PatientTEE.line(r) { lines.append(t) }
        // Before the case: the support the patient arrives with (one placed in the room is not preprocedure workup).
        if kind == .preop {
            let support = r.currentDevices(arrivalOnly: true).filter { PatientDevice.supportKinds.contains($0.kind) }
            lines += PatientDevices.labels(support).map { PatientSummary.Line("Mechanical support", $0, alert: true) }
        }
        var b = SummaryBlock(key: "workup", label: "Preprocedure cardiac workup", text: lines.map { joined($0) }.joined(separator: "\n"))
        b.alert = lines.contains { $0.alert }
        for l in lines { b.marks += l.marks }
        return b
    }

    /// Imaging (1.12, Ben): the preprocedure CT, MRI and other imaging the user chose under "+ Add other input data into
    /// Handoff" (`handoffExtras` "imaging:ct", "imaging:mri", "imaging:other"), after the cardiac workup. Typed imaging that
    /// was not chosen stays out of the summaries; a chosen item with nothing typed says nothing.
    private static func imagingBlock(_ r: PatientRecord) -> SummaryBlock {
        SummaryBlock(key: "imaging", label: "Imaging", text: r.imaging.chosenLines(r.handoffExtras).joined(separator: "\n"))
    }

    /// Intraoperative TEE: the findings entered in the Intraoperative tab, and the echo notes typed there. 1.10 (Ben's
    /// notes-img3): with a post-bypass exam, a "Pre: …" line and a "Post: …" line (PatientEcho.intraopParts); only what is
    /// entered.
    private static func intraopTEEBlock(_ r: PatientRecord, now: Date) -> SummaryBlock {
        let c = r.capitalized
        var parts: [String] = PatientEcho.intraopParts(pre: c.intraopEcho, post: c.intraopEchoPost, dates: .summary(now: now)).map { p in
            p.label.map { $0 + ": " + p.text } ?? p.text
        }
        if !trimmed(c.echo).isEmpty { parts.append(trimmed(c.echo)) }
        return SummaryBlock(key: "tee", label: "Intraoperative TEE", text: parts.joined(separator: "\n"))
    }

    // MARK: Labs

    /// Labs (1.12, Ben's note 8): no fishbone figures; two columns, "Preop" and "Intraop" (the Preprocedure Summary has the
    /// Preop column alone). The values and their order are BriefLabs.make (PatientBriefLabs.swift); the text is two
    /// labelled paragraphs, "Preop: …" and "Intraop: …", groups separated by "; ", which is also what Copy and Text only give.
    private static func labsBlock(_ r: PatientRecord, kind: Kind, now: Date) -> SummaryBlock {
        let made = BriefLabs.make(r.capitalized, withIntraop: kind == .handoff, now: now)
        var b = SummaryBlock(key: "labs", label: "Labs", text: made.paragraphs.joined(separator: "\n"),
                             figure: made.isEmpty ? nil : .fishbone(made), marks: made.marks)
        // The screen draws an out-of-range value bold red with no letter; the plain text keeps its H or L (1.12).
        b.plain = made.plainParagraphs.joined(separator: "\n")
        b.spoken = made.spokenParagraphs.joined(separator: "\n")
        return b
    }

    // MARK: Infusions, medications, intake and output

    /// Infusions (the drips running in the case; those running before it when they are not the same and were not taken off the
    /// case's list), the antibiotics charted in Case Timers, the intraoperative medications (the notable medications chosen
    /// as chips with their doses, then the text typed), and the factor concentrates and other products.
    ///
    /// 1.12 (Ben's note 16): a preoperative drip that was deleted on the Intraoperative tab is no longer running, so the handoff
    /// does not list it any more; the Preprocedure Summary and the preop record keep it (they describe the patient on arrival).
    /// 1.12 (note 3): "Antibiotics: Cefazolin 2 g, last 08:12, next due 12:12" for each antibiotic charted in Case Timers; one
    /// whose redose is overdue is red.
    private static func infusionsBlock(_ r: PatientRecord, now: Date = Date()) -> SummaryBlock {
        let c = r.capitalized
        var lines: [String] = []
        var marks: [String] = []
        let drips = c.infusions.map(\.text).filter { !$0.isEmpty }
        if !drips.isEmpty { lines.append("Infusions: " + drips.joined(separator: "; ")) }
        // A drip running before the case is listed again only when it is not one of the case's (another drug or rate), and
        // not when the case's list took it off.
        func same(_ s: String) -> String { s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let running = Set(drips.map(same))
        let takenOff = IntraopInfusionList.takenOff(r)
        let before = c.homeInfusions.filter { !takenOff.contains($0.id) }.map(\.text).filter { !$0.isEmpty && !running.contains(same($0)) }
        if !before.isEmpty {
            let name = drips.isEmpty ? "Infusions (running before the case)" : "Running before the case"
            lines.append(name + ": " + before.joined(separator: "; "))
        }
        let antibiotics = CaseAntibiotics.lines(r, now: now)
        if !antibiotics.isEmpty {
            lines.append("Antibiotics: " + antibiotics.map(\.handoffText).joined(separator: "; "))
            marks += antibiotics.filter(\.overdue).map(\.handoffText)
        }
        // 1.12 follow-up (Ben, Nov 12): the heparin doses of Case Timers' one Heparin & ACT log, with their total. The ACT and protamine
        // entries of that log are not printed here (the handoff has never printed them).
        if let heparin = CaseHeparin.text(r, now: now) { lines.append(heparin) }
        var meds = PatientNotableMeds.lines(c)
        let factors = trimmed(c.factors)
        if !factors.isEmpty { meds.append(factors) }
        if !meds.isEmpty { lines.append("Intraop medications: " + meds.joined(separator: "; ")) }
        return SummaryBlock(key: "infusions", label: "Current infusions & intraop medications", text: lines.joined(separator: "\n"), marks: marks)
    }

    /// Intake & output, in Ben's order: crystalloid, colloid, blood products, EBL, urine output, cell saver.
    private static func intakeOutputBlock(_ r: PatientRecord) -> SummaryBlock {
        func ml(_ id: String, _ name: String) -> String? {
            guard let v = r.fluids[id], v > 0 else { return nil }
            return name + " " + NumText.short(v) + " mL"
        }
        var parts: [String] = []
        parts += [ml("crystalloid", "Crystalloid"), ml("colloid", "Colloid")].compactMap { $0 }
        parts += BloodProducts.units.compactMap { u -> String? in
            guard let v = r.fluids[u.id], v > 0 else { return nil }
            return u.short + " " + NumText.short(v) + (u.id == "platelets" ? " dose" : " unit") + (v == 1 ? "" : "s")
        }
        parts += [ml("ebl", "EBL"), ml("uop", "Urine output"), ml(BloodProducts.cellSaver, "Cell saver")].compactMap { $0 }
        return SummaryBlock(key: "io", label: "Intake & output", text: parts.joined(separator: " · "))
    }

    // MARK: Lines & devices

    /// The lines and devices in place (those on arrival before the case; all, each "(Pre)" or "(Intra)", in the
    /// handoff) with the limb alerts and the radial-harvest arm, as the list beside the diagram.
    private static func linesBlock(_ r: PatientRecord, kind: Kind) -> SummaryBlock {
        let c = r.capitalized
        let arrival = kind == .preop
        let devices = c.currentDevices(arrivalOnly: arrival).filter { PatientDevice.lineKinds.contains($0.kind) || PatientDevice.supportKinds.contains($0.kind) }
        // Before the case the mechanical support is listed in the cardiac workup (it is still drawn on the diagram).
        var lines = arrival ? PatientDevices.labels(devices.filter { !PatientDevice.supportKinds.contains($0.kind) }) : PatientDevices.labelsWithPhase(devices)
        var marks: [String] = []
        let groups = PatientDeviceFills.limbAlertGroups(c, arrivalOnly: arrival)
        if !groups.isEmpty {
            lines.append("Limb alert: " + groups.map(\.text).joined(separator: "; "))
            marks += groups.map(\.name)
        }
        for a in PatientSummary.harvestLines(c) {
            lines.append("Arms: " + a.text)
            marks += a.marks
        }
        return SummaryBlock(key: "lines", label: "Lines & devices", text: lines.joined(separator: "\n"),
                            figure: devices.isEmpty ? nil : .diagram(arrivalOnly: arrival), alert: !groups.isEmpty, marks: marks, joiner: "; ")
    }

    // MARK: Intraoperative

    private static func regionalBlock(_ r: PatientRecord) -> SummaryBlock {
        let blocks = r.capitalized.regional.map(\.text).filter { !$0.isEmpty }
        return SummaryBlock(key: "regional", label: "Regional performed", text: blocks.joined(separator: "; "))
    }

    private static func eventsBlock(_ r: PatientRecord) -> SummaryBlock {
        let c = r.capitalized
        let typed = trimmed(c.events)
        if !typed.isEmpty { return SummaryBlock(key: "events", label: "Intraoperative events", text: typed, alert: true) }
        return SummaryBlock(key: "events", label: "Intraoperative events", text: c.noEvents ? "No notable events" : "")
    }

    // MARK: Risk scores

    private static let scoreOrder = ["rcri", "stopbang", "ariscat"]

    /// "RCRI 2 (Class III) · STOP-BANG 5 · ARISCAT 34 (Intermediate)": the scores saved; the RCRI not for cardiac surgery.
    static func riskText(_ r: PatientRecord) -> String {
        let ids = r.scores.keys.sorted { a, b in
            let ia = scoreOrder.firstIndex(of: a) ?? scoreOrder.count, ib = scoreOrder.firstIndex(of: b) ?? scoreOrder.count
            return ia != ib ? ia < ib : a < b
        }
        var parts: [String] = []
        for id in ids {
            guard let sc = r.scores[id] else { continue }
            if id == "rcri" && PatientRules.cardiacSurgery(r) { continue }
            guard sc.points != nil || sc.label != nil else { continue }
            let name = Scores.byID(id)?.short ?? id.uppercased()
            parts.append(name + (sc.points.map { " \($0)" } ?? "") + (sc.label.map { " (" + $0 + ")" } ?? ""))
        }
        return parts.joined(separator: " · ")
    }

    private static func riskBlock(_ r: PatientRecord) -> SummaryBlock {
        SummaryBlock(key: "risk", label: "Risk scores", text: riskText(r))
    }

    // MARK: Concerns / considerations

    /// Concerns/Considerations: where the patient goes, the major intraoperative considerations, To do & Concerns, and the
    /// pain plan and call-if typed before 1.9.
    private static func concernsBlock(_ r: PatientRecord) -> SummaryBlock {
        let c = r.capitalized
        var lines: [String] = []
        var marks: [String] = []
        if let d = c.disposition, !trimmed(d).isEmpty { lines.append("Disposition: " + trimmed(d)) }
        if let k = IntraopConsiderations.text(c) {
            lines.append("Considerations: " + k)
            marks.append("Considerations: " + k)
        }
        if !trimmed(c.todos).isEmpty { lines.append("To do & concerns: " + trimmed(c.todos)) }
        if !trimmed(c.painPlan).isEmpty { lines.append("Pain plan: " + trimmed(c.painPlan)) }
        if !trimmed(c.callIf).isEmpty { lines.append("Call if: " + trimmed(c.callIf)) }
        return SummaryBlock(key: "concerns", label: "Concerns/Considerations", text: lines.joined(separator: "\n"), alert: !marks.isEmpty, marks: marks.isEmpty ? [] : ["Considerations:"])
    }
}
