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

/// One value of the labs, as the fishbone and the lists show it.
struct BriefLabCell: Hashable {
    var key: String
    /// The short name under the value ("HCO₃").
    var label: String
    /// The value formatted as the Labs screen does ("1.10" for a creatinine).
    var text: String
    var flag: LabFlag = .normal
    /// From an intraoperative set (marked * and dated in the caption).
    var intraop = false
    /// Hemoglobin or hematocrit worked out from the other (PatientLabs.estimate): shown, never flagged.
    var estimated = false

    var abnormal: Bool { flag.isAbnormal }

    /// "K 5.9 H", "Hb 11.6*" (intraoperative), "Hct ~39 (est.)", "Hct ~22 (est.)*" (from an intraoperative Hb).
    var compact: String {
        if estimated { return label + " ~" + text + " (est.)" + (intraop ? "*" : "") }
        return label + " " + text + (flag.mark.isEmpty ? "" : " " + flag.mark) + (intraop ? "*" : "")
    }

    /// The copied text: the same, with plain digits in the subscripts ("HCO3").
    var plain: String { PatientBriefs.ascii(compact) }
}

/// The fishbone's values (BMP, CBC, coagulation) by key, with the caption that says which came from the case.
struct BriefLabs: Hashable {
    static let bmpKeys = ["na", "k", "cl", "hco3", "bun", "cr", "glucose"]
    static let cbcKeys = ["wbc", "hb", "hct", "plt"]
    static let coagKeys = ["pt", "inr", "ptt", "fibrinogen"]
    static let fishboneKeys = Set(bmpKeys + cbcKeys + coagKeys)

    var cells: [String: BriefLabCell] = [:]
    /// "* Intraop 10:40; other values preop": which values came from the intraoperative sets, and when.
    var caption: String?

    var isEmpty: Bool { cells.isEmpty }
    func has(_ keys: [String]) -> Bool { keys.contains { cells[$0] != nil } }
    var hasBMP: Bool { has(Self.bmpKeys) }
    var hasCBC: Bool { has(Self.cbcKeys) }
    var hasCoags: Bool { has(Self.coagKeys) }

    /// "BMP: Na 138, K 4.1, Cl 102, HCO3 24, BUN 18, Cr 1.10, Glu 110 · CBC: WBC 7.2, Hb 13.1, Hct 39, Plt 210 · Coags: PT 12.1,
    /// INR 1.0, PTT 30": the fishbone as one line, for the copied text; only the values entered.
    func plainFishbone() -> String {
        func group(_ name: String, _ keys: [String]) -> String? {
            let parts = keys.compactMap { cells[$0]?.plain }
            return parts.isEmpty ? nil : name + ": " + parts.joined(separator: ", ")
        }
        return [group("BMP", Self.bmpKeys), group("CBC", Self.cbcKeys), group("Coags", Self.coagKeys)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The fishbone's values and the other labs entered. `withIntraop` (the handoff): for each test the newest
    /// intraoperative value replaces the preoperative one, and the caption says so with the time. The arterial
    /// bicarbonate stands in the HCO₃ cell.
    static func make(_ r: PatientRecord, withIntraop: Bool, now: Date = Date()) -> (labs: BriefLabs, side: [BriefLabCell]) {
        struct Source {
            var value: Double
            var key: String
            var intraop: Bool
            var time: Date?
        }
        var byKey: [String: Source] = [:]
        for (k, v) in r.labs where v.isFinite { byKey[k] = Source(value: v, key: k, intraop: false, time: nil) }
        if withIntraop {
            var taken: Set<String> = []
            for set in IntraopLabs.ordered(r.intraopLabs) {
                for (k, v) in set.values where v.isFinite {
                    let target = k == "hco3a" ? "hco3" : k
                    guard !taken.contains(target) else { continue }
                    taken.insert(target)
                    byKey[target] = Source(value: v, key: k, intraop: true, time: set.time)
                }
            }
        }
        let p99: Double? = r.labs["troponin99"].flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        // Catalog order, then the intraoperative tests it lacks.
        var order: [String] = PatientLabs.catalog.map(\.key).filter { $0 != "troponin99" }
        for k in IntraopLabs.keys where k != "hco3a" && !order.contains(k) { order.append(k) }

        var labs = BriefLabs()
        var side: [BriefLabCell] = []
        for k in order {
            guard let s = byKey[k], let source = PatientLabs.test(s.key), let named = PatientLabs.test(k) else { continue }
            let c = BriefLabCell(key: k, label: named.short, text: source.format(s.value),
                                 flag: PatientLabs.flag(s.key, s.value, sex: r.sex, troponin99: p99), intraop: s.intraop)
            if fishboneKeys.contains(k) { labs.cells[k] = c } else { side.append(c) }
        }
        var merged: [String: Double] = [:]
        for (k, s) in byKey { merged[k] = s.value }
        // The estimate is worked out from the other of Hb and Hct: it is from the case (starred, with that set's time)
        // when that value is.
        var estimatedFrom: (label: String, source: Source)?
        if let e = PatientLabs.estimate(merged), labs.cells[e.key] == nil {
            let source = byKey[e.key == "hct" ? "hb" : "hct"]
            labs.cells[e.key] = BriefLabCell(key: e.key, label: e.label, text: e.text, flag: .normal, intraop: source?.intraop ?? false, estimated: true)
            if let source, source.intraop { estimatedFrom = (e.label, source) }
        }
        // 1.10 (Ben, Nov 7: labs note their times, very small): when the preoperative labs were drawn, if it was entered.
        let drawn = r.labsDrawn.map { PatientSummary.time($0, now: now) }
        let preopValues = byKey.values.contains { !$0.intraop }
        if !withIntraop, let drawn, preopValues { labs.caption = "Preop labs " + drawn }
        if withIntraop {
            var times: [Date?] = []
            for s in byKey.values where s.intraop && !times.contains(where: { $0 == s.time }) { times.append(s.time) }
            times.sort { ($0 ?? Date.distantPast) > ($1 ?? Date.distantPast) }
            if !times.isEmpty {
                // With more than one set, each time names its values, so an older value is not read as the newest.
                let several = times.count > 1
                let when = times.map { t -> String in
                    let clock = t.map { PatientSummary.time($0, now: now) } ?? "no time"
                    guard several else { return clock }
                    var names = order.compactMap { k -> String? in
                        guard let s = byKey[k], s.intraop, s.time == t else { return nil }
                        return PatientLabs.test(k)?.short
                    }
                    if let e = estimatedFrom, e.source.time == t { names.append(e.label + " est.") }
                    return clock + (names.isEmpty ? "" : " (" + names.joined(separator: ", ") + ")")
                }.joined(separator: " / ")
                labs.caption = "* Intraop " + when + (preopValues ? "; other values preop" + (drawn.map { " " + $0 } ?? "") : "")
            } else if let drawn, preopValues {
                labs.caption = "Preop labs " + drawn
            }
        }
        return (labs, side)
    }
}

/// One block of a brief.
struct SummaryBlock: Identifiable, Hashable {
    enum Figure: Hashable {
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

    var id: String { key }
    var lines: [String] { text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    /// The fishbone with a value in it, or the lines diagram (built only with a line or device to draw: before the case
    /// a patient with mechanical support alone has it in the workup's words and on this picture, with no list beside it).
    /// A diagram block the user edited counts by its words alone, so one they emptied is left out, picture and all.
    var figureHasContent: Bool {
        switch figure {
        case .fishbone(let l)?: return !l.isEmpty || l.caption != nil
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
        let lines = b.lines
        let label = b.label.map { $0 + ":" }
        if case .fishbone(let labs)? = b.figure {
            var parts: [String] = []
            let fish = labs.plainFishbone()
            if !fish.isEmpty { parts.append(fish) }
            parts += lines
            var out = [ascii(((label.map { $0 + " " }) ?? "") + parts.joined(separator: " · "))]
            if let c = labs.caption { out.append("  " + ascii(c)) }
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
        let hist = PatientSummary.historyLines(r, now: now)
        let assess = PatientSummary.assessmentLines(r)
        var out: [SummaryBlock] = []
        out.append(headerBlock(r, kind: kind))
        out.append(codeStatusBlock(r))
        if kind == .handoff { out.append(caseBlock(r)) }
        out.append(allergiesBlock(hist))
        out.append(pmhBlock(r, hist: hist, assess: assess))
        out.append(pshBlock(r))
        if kind == .preop {
            out.append(airwayExamBlock(r))
            out.append(workupBlock(r, assess: assess, kind: kind))
            out.append(labsBlock(r, kind: kind, now: now))
            out.append(medicationsBlock(r, hist: hist, kind: kind))
            out.append(lastIntakeBlock(hist))
            out.append(linesBlock(r, kind: kind))
            out.append(riskBlock(r))
        } else {
            out.append(airwayCourseBlock(r))
            out.append(workupBlock(r, assess: assess, kind: kind))
            out.append(intraopTEEBlock(r))
            out.append(labsBlock(r, kind: kind, now: now))
            out.append(medicationsBlock(r, hist: hist, kind: kind))
            out.append(infusionsBlock(r))
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

    /// PMH (ASA class): the system pages' words in one paragraph, the history's warnings (aspiration risk, heparin
    /// caution), anesthetic complications, positive infectious items and isolation (they are on the Infectious page's
    /// words), and function, frailty and the active cardiac flags.
    private static func pmhBlock(_ r: PatientRecord, hist: [PatientSummary.Line], assess: [PatientSummary.Line]) -> SummaryBlock {
        var parts: [String] = []
        var marks: [String] = []
        for l in hist where !notPMH.contains(l.label ?? "") {
            let t = joined(l)
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
        return SummaryBlock(key: "pmh", label: asa.map { "PMH (" + $0 + ")" } ?? "PMH", text: parts.joined(separator: " · "), marks: marks)
    }

    /// PSH: the past surgical history, with the cardiac or thoracic operations added in the cardiac evaluation.
    private static func pshBlock(_ r: PatientRecord) -> SummaryBlock {
        let c = r.capitalized
        var items = c.surgeries.map(\.text).filter { !$0.isEmpty }
        for s in c.intrathoracic.map(\.text) where !s.isEmpty && !items.contains(s) { items.append(s) }
        return SummaryBlock(key: "psh", label: "PSH", text: items.joined(separator: "; "))
    }

    private static func lastIntakeBlock(_ hist: [PatientSummary.Line]) -> SummaryBlock {
        SummaryBlock(key: "intake", label: "Last intake", text: hist.first(where: { $0.label == "Last intake" })?.text ?? "")
    }

    // MARK: Medications

    /// Preprocedure: the home medications, the infusions running and the flags that need action. Handoff: the home
    /// medications with those flags (the infusions are with the intraoperative ones).
    private static func medicationsBlock(_ r: PatientRecord, hist: [PatientSummary.Line], kind: Kind) -> SummaryBlock {
        var pieces: [(label: String, text: String, alert: Bool)] = []
        if let m = hist.first(where: { $0.label == "Medications" }) { pieces.append(("Home", m.text, m.alert)) }
        if kind == .preop, let i = hist.first(where: { $0.label == "Current infusions" }) { pieces.append(("Infusions", i.text, true)) }
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

    /// Airway course, on one line: how it arrived, mask and intubation in the room (a difficult one in capitals), and
    /// how the patient leaves (extubated, remains intubated). 1.10: no difficult-airway follow-up sentence.
    static func airwayCourse(_ r: PatientRecord) -> (text: String, alert: Bool)? {
        let c = r.capitalized
        var sentences: [String] = []
        if c.arrivesWithAirway, let a = c.currentAirwayText {
            sentences.append(a + " on arrival" + (!c.vent.isEmpty && c.oxygen.device != "trachCollar" ? ", " + c.vent.text : ""))
        }
        if !c.oxygen.isEmpty && (!c.arrivesWithAirway || c.oxygen.device == "trachCollar") { sentences.append("Oxygen on arrival: " + c.oxygen.text) }
        sentences += PatientSummary.airwayCourseSentences(c)
        if !trimmed(c.airwayNotes).isEmpty { sentences.append("Airway notes: " + trimmed(c.airwayNotes)) }
        if !trimmed(c.examNotes).isEmpty { sentences.append("Examination: " + trimmed(c.examNotes)) }
        if let end = c.airwayAtEnd {
            let vent = trimmed(c.ventilation)
            switch end {
            case "extubated": sentences.append("Extubated")
            case "intubated": sentences.append("Remains intubated" + (vent.isEmpty ? "" : " (" + vent + ")"))
            default:
                if let label = PatientCatalog.airwayAtEnd.first(where: { $0.id == end })?.label { sentences.append("At handoff: " + label.lowercased()) }
            }
        }
        guard !sentences.isEmpty else { return nil }
        // A sentence that already ends in a period (a typed note) is not given a second one, and none has a space before
        // its period (1.10: "Beard ." in Ben's example).
        let text = sentences.map { s -> String in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t.hasSuffix(".") ? String(t.dropLast()) : t).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }.joined(separator: ". ") + "."
        return (text, PatientSummary.difficultAirway(c))
    }

    private static func airwayCourseBlock(_ r: PatientRecord) -> SummaryBlock {
        var b = SummaryBlock(key: "airway", label: "Airway course")
        if let c = airwayCourse(r) {
            b.text = c.text
            b.alert = c.alert
            if c.alert { b.marks = ["DIFFICULT"] }
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
    private static func workupBlock(_ r: PatientRecord, assess: [PatientSummary.Line], kind: Kind) -> SummaryBlock {
        var lines = assess.filter { workupLabels.contains($0.label ?? "") }
        // 1.11 (Ben's note 4): the stress test, after the echo and before the catheterizations.
        if let s = PatientPreop.stressLine(r) {
            let at = lines.firstIndex { ["Coronaries", "Right heart cath", "Carotid ultrasound", "Radial artery ultrasound", "Pulmonary function tests", "Caution"].contains($0.label ?? "") } ?? lines.count
            lines.insert(s, at: at)
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

    /// Intraoperative TEE: the findings entered in the Intraoperative tab, and the echo notes typed there. 1.10 (Ben's
    /// notes-img3): with a post-bypass exam, a "Pre: …" line and a "Post: …" line (PatientEcho.intraopParts); only what is
    /// entered.
    private static func intraopTEEBlock(_ r: PatientRecord) -> SummaryBlock {
        let c = r.capitalized
        var parts: [String] = PatientEcho.intraopParts(pre: c.intraopEcho, post: c.intraopEchoPost).map { p in
            p.label.map { $0 + ": " + p.text } ?? p.text
        }
        if !trimmed(c.echo).isEmpty { parts.append(trimmed(c.echo)) }
        return SummaryBlock(key: "tee", label: "Intraoperative TEE", text: parts.joined(separator: "\n"))
    }

    // MARK: Labs

    /// Labs: the fishbone, then the other values, type and screen, infectious results (all of them before the case; positive
    /// and pending ones in the handoff), the liver scores and the lab notes. In the handoff the newest intraoperative value of
    /// each test replaces the preoperative one, dated in the caption.
    private static func labsBlock(_ r: PatientRecord, kind: Kind, now: Date) -> SummaryBlock {
        let c = r.capitalized
        let made = BriefLabs.make(c, withIntraop: kind == .handoff, now: now)
        var lines = made.side.map(\.compact)
        var marks = made.side.filter(\.abnormal).map(\.compact)
        if kind == .preop {
            let more = LabResults.lineParts(c)
            lines += more.parts
            marks += more.marks
        } else {
            lines += c.typeScreen.parts
            if c.typeScreen.screen == .positive, let h = c.typeScreen.head { marks.append(h) }
            for p in LabResults.infectiousParts(c.infections, onlyTelling: true) {
                lines.append(p.text)
                if p.result == .positive { marks.append(p.text) }
            }
            if let set = IntraopLabs.ordered(c.intraopLabs).first {
                let ve = trimmed(set.viscoelastic)
                if !ve.isEmpty { lines.append("ROTEM/TEG: " + ve) }
                let other = trimmed(set.other)
                if !other.isEmpty { lines.append(other) }
            }
        }
        if let m = PatientSummary.liverLine(c) {
            lines.append(joined(m))
            marks += m.marks
        }
        if !trimmed(c.labNotes).isEmpty { lines.append(trimmed(c.labNotes)) }
        return SummaryBlock(key: "labs", label: "Labs", text: lines.joined(separator: "\n"),
                            figure: made.labs.isEmpty && made.labs.caption == nil ? nil : .fishbone(made.labs), marks: marks, joiner: " · ")
    }

    // MARK: Infusions, medications, intake and output

    /// Infusions (the drips running in the case; those running before it when they are not the same), the intraoperative
    /// medications, and the factor concentrates and other products.
    private static func infusionsBlock(_ r: PatientRecord) -> SummaryBlock {
        let c = r.capitalized
        var lines: [String] = []
        let drips = c.infusions.map(\.text).filter { !$0.isEmpty }
        if !drips.isEmpty { lines.append("Infusions: " + drips.joined(separator: "; ")) }
        // A drip running before the case is listed again only when it is not one of the case's (another drug or rate).
        func same(_ s: String) -> String { s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let running = Set(drips.map(same))
        let before = c.homeInfusions.map(\.text).filter { !$0.isEmpty && !running.contains(same($0)) }
        if !before.isEmpty {
            let name = drips.isEmpty ? "Infusions (running before the case)" : "Running before the case"
            lines.append(name + ": " + before.joined(separator: "; "))
        }
        var meds: [String] = []
        let given = trimmed(c.medsGiven)
        if !given.isEmpty { meds.append(given.hasSuffix(".") || given.hasSuffix(";") ? String(given.dropLast()) : given) }
        let factors = trimmed(c.factors)
        if !factors.isEmpty { meds.append(factors) }
        if !meds.isEmpty { lines.append("Intraop medications: " + meds.joined(separator: "; ")) }
        return SummaryBlock(key: "infusions", label: "Current infusions & intraop medications", text: lines.joined(separator: "\n"))
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
