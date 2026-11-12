import Foundation

// MARK: - The labs in the two summaries (1.12, Ben's note 8) and "+ Add other input data into Handoff" (note 14)
//
// No fishbone figures in the summaries. The Labs block has two columns, "Preop" and "Intraop" (the Preprocedure Summary has
// the Preop column alone, full width):
//
//   Preop    CMP: Na, K, BUN, Cr (GFR), AST/ALT, glucose.  Heme: Hb, Plt, PTT, INR, fibrinogen, Type & Screen.
//            Other: lactate, TSH, free T4, T bilirubin, MRSA screen, hCG / pregnancy test (not for a man).
//   Intraop  (handoff only) the newest blood gas with its lactate, drawn as the slash figure (pH / PCO₂ / PO₂ / HCO₃) and
//            labelled with the gas type and its time; then Heme: the newest Hb, Plt, INR, fibrinogen and TEG/ROTEM, each from
//            the latest set that holds it.
//
// Only what is recorded is shown; a group with nothing is left out and so is a column. Abnormal values are bold red with no H or
// L beside them (1.12; the plain text, which cannot carry colour, keeps the letter: BriefLabCell.ownLetter). What is recorded and not in these lists is offered under "+ Add other input data into Handoff" (chips,
// `PatientRecord.handoffExtras`: "preop:<lab key>", "intraop:<lab key>"); a chosen one is added to its column under "Other".
// Not dropped, whatever the lists above say, because the handoff has carried them for safety since 1.8.3: a positive or
// pending infectious result (and a urinalysis with a finding, or a blood culture that is not negative), the liver scores,
// the lab notes typed on the Labs page, and the free text of the newest intraoperative set's "Other results".

/// One value of the labs, as the summary shows it.
struct BriefLabCell: Hashable {
    var key: String
    /// The short name ("HCO₃").
    var label: String
    /// The value formatted as the Labs screen does ("1.10" for a creatinine).
    var text: String
    var flag: LabFlag = .normal
    /// Shown in brackets beside it: the GFR beside the creatinine.
    var also: [BriefLabCell] = []

    var abnormal: Bool { flag.isAbnormal }

    /// "K 5.9": this value alone, as the app draws it. An out-of-range value is bold red and has no letter after it (1.12, Ben:
    /// "remove the H and L, simple red text is fine to highlight").
    var own: String { label + " " + text }

    /// "Cr 1.8 (GFR 42)": both are red when both are out of range.
    var compact: String { also.isEmpty ? own : own + " (" + also.map(\.compact).joined(separator: ", ") + ")" }

    /// The parts of `compact` that are abnormal, for bold red. Each is matched only where it stands alone
    /// (MarkedText), so "K 5.9" never paints the start of "K 5.95".
    var marks: [String] { (flag.isAbnormal ? [own] : []) + also.flatMap(\.marks) }

    /// "K 5.9 H": for the plain text only, which cannot carry colour (Copy, "Share as text only"); there the letter stays, or an
    /// abnormal value would not be told from a normal one in a text message.
    var ownLetter: String { label + " " + text + (flag.mark.isEmpty ? "" : " " + flag.mark) }

    /// "Cr 1.8 H (GFR 42 L)": the plain text's form.
    var compactLetter: String { also.isEmpty ? ownLetter : ownLetter + " (" + also.map(\.compactLetter).joined(separator: ", ") + ")" }

    /// "K 5.9, high": what VoiceOver says, since it cannot see that the value is red.
    var ownSpoken: String { label + " " + text + (flag.word.isEmpty ? "" : ", " + flag.word) }

    /// "Cr 1.8, high (GFR 42, low)".
    var spoken: String { also.isEmpty ? ownSpoken : ownSpoken + " (" + also.map(\.spoken).joined(separator: ", ") + ")" }

    /// The copied text: the plain text's form, with plain digits in the subscripts ("HCO3").
    var plain: String { PatientBriefs.ascii(compactLetter) }
}

/// One thing in a group: a value, or a result in words.
struct BriefLabItem: Hashable {
    var key: String
    var text: String
    /// The parts of `text` to show in bold red.
    var marks: [String] = []
    /// An intraoperative value: when its set was drawn (nil: the set has no time), for the caption.
    var timed = false
    var time: Date?
    /// The short name the caption uses for it.
    var name = ""
    /// The plain text's form of `text` (the lab letters H and L stay there, 1.12) and VoiceOver's (a red value says low or
    /// high); both are `text` for an item that has no flagged value.
    var plain: String
    var spoken: String

    init(key: String, text: String, marks: [String] = []) {
        self.key = key
        self.text = text
        self.marks = marks
        plain = text
        spoken = text
    }

    init(_ cell: BriefLabCell) {
        key = cell.key
        text = cell.compact
        marks = cell.marks
        name = cell.label
        plain = cell.compactLetter
        spoken = cell.spoken
    }
}

/// A named group of a column: "CMP: Na 138, K 4.1", "Heme: Hb 9 L, Plt 98 L, INR 1.6 H".
struct BriefLabGroup: Hashable {
    var name: String
    var items: [BriefLabItem]
    /// The blood gas's group: the Intraop column draws it as the slash figure instead of this text.
    var isGas = false

    var text: String { name + ": " + items.map(\.text).joined(separator: ", ") }
    /// The group for the plain text (the lab letters stay) and for VoiceOver (1.12).
    var plainText: String { name + ": " + items.map(\.plain).joined(separator: ", ") }
    var spokenText: String { name + ": " + items.map(\.spoken).joined(separator: ", ") }
    var marks: [String] { items.flatMap(\.marks) }
}

/// The newest blood gas, for the slash figure.
struct BriefGas: Hashable {
    var type: BloodGasType
    /// "10:40", or "11/03/26 10:40" for another day; nil when the set has no time.
    var time: String?
    /// pH, PCO₂, PO₂, HCO₃ in that order; nil where not recorded.
    var slash: [BriefLabCell?]
    /// The saturation of an ScvO₂ or SvO₂ sample.
    var saturation: BriefLabCell?
    var lactate: BriefLabCell?

    /// "ABG (10:40)", the group's name; "ABG" with no time.
    var title: String { type.short + (time.map { " (" + $0 + ")" } ?? "") }
    /// "ABG · 10:40", the small label over the figure.
    var figureLabel: String { type.short + (time.map { " · " + $0 } ?? "") }
    var hasSlash: Bool { slash.contains { $0 != nil } }
}

/// The two columns of the Labs block.
struct BriefLabs: Hashable {
    /// The groups the preoperative figure on the tab card still draws (PreopLabsCard).
    static let bmpKeys = ["na", "k", "cl", "hco3", "bun", "cr", "glucose"]
    static let cbcKeys = ["wbc", "hb", "hct", "plt"]
    static let coagKeys = ["pt", "inr", "ptt", "fibrinogen"]
    static let fishboneKeys = Set(bmpKeys + cbcKeys + coagKeys)

    var preop: [BriefLabGroup] = []
    var gas: BriefGas?
    /// The gas's group first (when there is a gas), then Heme, then Other.
    var intraop: [BriefLabGroup] = []
    /// "Preop labs 06:30 · Intraop 10:40 (INR, TEG/ROTEM) / 09:15 (Plt)": the small caption with the times.
    var caption: String?

    var hasPreop: Bool { !preop.isEmpty }
    var hasIntraop: Bool { !intraop.isEmpty }
    var isEmpty: Bool { preop.isEmpty && intraop.isEmpty }

    /// "Preop: CMP: Na 138; Heme: Hb 12" and "Intraop: ABG (10:40): pH 7.33 / …; Heme: …": the text of the block and the
    /// copied text (groups separated by "; ").
    var paragraphs: [String] {
        var out: [String] = []
        if !preop.isEmpty { out.append("Preop: " + preop.map(\.text).joined(separator: "; ")) }
        if !intraop.isEmpty { out.append("Intraop: " + intraop.map(\.text).joined(separator: "; ")) }
        return out
    }

    /// The same paragraphs for the plain text (Copy, "Share as text only"): the lab letters H and L stay (1.12).
    var plainParagraphs: [String] {
        var out: [String] = []
        if !preop.isEmpty { out.append("Preop: " + preop.map(\.plainText).joined(separator: "; ")) }
        if !intraop.isEmpty { out.append("Intraop: " + intraop.map(\.plainText).joined(separator: "; ")) }
        return out
    }

    /// The same for VoiceOver: a red value says "low" or "high".
    var spokenParagraphs: [String] {
        var out: [String] = []
        if !preop.isEmpty { out.append("Preop: " + preop.map(\.spokenText).joined(separator: "; ")) }
        if !intraop.isEmpty { out.append("Intraop: " + intraop.map(\.spokenText).joined(separator: "; ")) }
        return out
    }

    /// Every part to show in bold red.
    var marks: [String] { (preop + intraop).flatMap(\.marks) }

    // MARK: Making them

    /// The value as a cell, flagged against the catalog's range for the patient's sex.
    static func labCell(_ key: String, _ v: Double, sex: PatientSex?, p99: Double?) -> BriefLabCell {
        guard let t = PatientLabs.test(key) else { return BriefLabCell(key: key, label: key, text: NumText.short(v)) }
        return BriefLabCell(key: key, label: t.short, text: t.format(v), flag: PatientLabs.flag(key, v, sex: sex, troponin99: p99))
    }

    private static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The preoperative groups and, for the handoff (`withIntraop`), the intraoperative ones. `r` is the capitalized record.
    static func make(_ r: PatientRecord, withIntraop: Bool, now: Date = Date()) -> BriefLabs {
        var out = BriefLabs()
        let extras = Set(r.handoffExtras)
        out.preop = preopGroups(r, extras: extras, now: now)
        var timed: [(time: Date?, name: String)] = []
        if withIntraop {
            let built = intraopGroups(r, extras: extras, now: now)
            out.gas = built.gas
            out.intraop = built.groups
            timed = built.timed
        }
        var parts: [String] = []
        if !out.preop.isEmpty, let drawn = r.labsDrawn { parts.append("Preop labs " + PatientSummary.time(drawn, now: now)) }
        if !timed.isEmpty { parts.append("Intraop " + when(timed, now: now)) }
        out.caption = parts.isEmpty ? nil : parts.joined(separator: " · ")
        return out
    }

    /// "10:40" for one time; with several, each time names its values ("10:40 (INR, TEG/ROTEM) / 09:15 (Plt)"), so an older
    /// value is not read as the newest.
    private static func when(_ items: [(time: Date?, name: String)], now: Date) -> String {
        var times: [Date?] = []
        for i in items where !times.contains(where: { $0 == i.time }) { times.append(i.time) }
        times.sort { ($0 ?? Date.distantPast) > ($1 ?? Date.distantPast) }
        let several = times.count > 1
        return times.map { t -> String in
            let clock = t.map { PatientSummary.time($0, now: now) } ?? "no time"
            guard several else { return clock }
            let names = items.filter { $0.time == t }.map(\.name)
            return clock + (names.isEmpty ? "" : " (" + names.joined(separator: ", ") + ")")
        }.joined(separator: " / ")
    }

    // MARK: Preop

    private static func preopGroups(_ r: PatientRecord, extras: Set<String>, now: Date) -> [BriefLabGroup] {
        let p99: Double? = r.labs["troponin99"].flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        func num(_ k: String) -> BriefLabCell? {
            guard let v = r.labs[k], v.isFinite else { return nil }
            return labCell(k, v, sex: r.sex, p99: p99)
        }
        func items(_ keys: [String]) -> [BriefLabItem] { keys.compactMap { num($0) }.map { BriefLabItem($0) } }

        // CMP: Na, K, BUN, Cr (GFR), AST/ALT, glucose.
        var cmp = items(["na", "k", "bun"])
        if var cr = num("cr") {
            if let g = num("gfr") { cr.also = [g] }
            cmp.append(BriefLabItem(cr))
        } else if let g = num("gfr") {
            cmp.append(BriefLabItem(g))
        }
        // "AST/ALT 32/28" while both are normal; an abnormal one (or only one) is written on its own, so its flag is exact.
        let ast = num("ast"), alt = num("alt")
        if let a = ast, let l = alt, !a.abnormal, !l.abnormal {
            cmp.append(BriefLabItem(key: "astalt", text: "AST/ALT " + a.text + "/" + l.text))
        } else {
            cmp += [ast, alt].compactMap { $0 }.map { BriefLabItem($0) }
        }
        cmp += items(["glucose"])

        // Heme: Hb, Plt, PTT, INR, fibrinogen, Type & Screen.
        var heme = items(["hb", "plt", "ptt", "inr", "fibrinogen"])
        let ts = r.typeScreen
        let tsParts = ts.parts(now: now)
        if !tsParts.isEmpty {
            // "T&S A+, screen neg, 2 u crossmatched, expires 11/14/26 23:59"; once expired the last part is "T&S expired ...",
            // painted red with a positive screen (1.12).
            heme.append(BriefLabItem(key: "ts", text: tsParts.joined(separator: ", "), marks: ts.marks(now: now)))
        }

        // Other: lactate, TSH, free T4, T bilirubin, MRSA screen, hCG / pregnancy test.
        var other = items(["lactate", "tsh", "ft4", "tbili"])
        if let v = r.infections.results["mrsa"], let t = LabResults.test("mrsa") {
            let text = t.short + " " + v.short
            other.append(BriefLabItem(key: "mrsa", text: text, marks: v == .positive ? [text] : []))
        }
        if PatientMoreLabs.showsPregnancy(r.sex), let t = r.moreLabs.pregnancyText(number: num("hcg")?.text) {
            other.append(BriefLabItem(key: "hcg", text: t))
        }
        // Kept for safety whatever the lists say: a positive or pending result, a urinalysis with a finding, a blood
        // culture that is not negative, the liver scores and the lab notes.
        for t in LabResults.infectious where t.id != "mrsa" {
            guard let v = r.infections.results[t.id], v.needsTelling else { continue }
            let text = t.short + " " + v.short
            other.append(BriefLabItem(key: t.id, text: text, marks: v == .positive ? [text] : []))
        }
        for o in r.infections.other {
            guard let v = o.result, !o.trimmedName.isEmpty, v.needsTelling else { continue }
            let text = o.trimmedName + " " + v.short
            other.append(BriefLabItem(key: "infx:" + o.trimmedName.lowercased(), text: text, marks: v == .positive ? [text] : []))
        }
        if r.moreLabs.urinalysisNeedsTelling, let t = r.moreLabs.urinalysisText { other.append(BriefLabItem(key: "ua", text: t, marks: [t])) }
        if r.moreLabs.bloodCulturesNeedTelling, let t = r.moreLabs.bloodCulturesText { other.append(BriefLabItem(key: "bcx", text: t, marks: [t])) }
        if let m = PatientSummary.liverLine(r) { other.append(BriefLabItem(key: "liver", text: m.text, marks: m.marks)) }
        let notes = trimmed(r.labNotes)
        if !notes.isEmpty { other.append(BriefLabItem(key: "labnotes", text: notes)) }
        // Appended under Other: what was chosen under "+ Add other input data into Handoff", and any abnormal value
        // outside the lists (Ben, Nov 11: an abnormal lab is in the summaries whether or not it was picked).
        for c in HandoffExtras.preopCandidates(r) where extras.contains(c.key) || HandoffExtras.alwaysShown(c) { other.append(c.item) }

        var groups: [BriefLabGroup] = []
        if !cmp.isEmpty { groups.append(BriefLabGroup(name: "CMP", items: cmp)) }
        if !heme.isEmpty { groups.append(BriefLabGroup(name: "Heme", items: heme)) }
        if !other.isEmpty { groups.append(BriefLabGroup(name: "Other", items: other)) }
        return groups
    }

    // MARK: Intraop

    /// The newest value of a test and its set: "the latest set that holds it".
    static func latest(_ key: String, in sets: [IntraopLabSet]) -> (value: Double, set: IntraopLabSet)? {
        for s in sets {
            if let v = s.values[key], v.isFinite { return (v, s) }
        }
        return nil
    }

    private static let slashLabels = ["ph": "pH", "paco2": "PCO₂", "pao2": "PO₂", "hco3a": "HCO₃"]

    private static func intraopGroups(_ r: PatientRecord, extras: Set<String>, now: Date)
        -> (gas: BriefGas?, groups: [BriefLabGroup], timed: [(time: Date?, name: String)]) {
        let sets = IntraopLabs.ordered(r.intraopLabs)
        var groups: [BriefLabGroup] = []
        var timed: [(time: Date?, name: String)] = []
        var gasOut: BriefGas?

        // The newest blood gas with its lactate (and, for an ScvO₂ or SvO₂ sample, its saturation).
        if let g = IntraopLabs.latestGas(r.intraopLabs) {
            let type = g.gasType
            var slash: [BriefLabCell?] = []
            for k in IntraopLabs.abgSlash {
                if let v = g.values[k], v.isFinite, let t = IntraopLabs.test(k, type: type) {
                    slash.append(BriefLabCell(key: k, label: slashLabels[k] ?? t.short, text: t.format(v),
                                              flag: IntraopLabs.flag(k, v, sex: r.sex, type: type)))
                } else {
                    slash.append(nil)
                }
            }
            var lactate: BriefLabCell?
            if let v = g.values["lactate"], v.isFinite, let t = IntraopLabs.test("lactate", type: type) {
                lactate = BriefLabCell(key: "lactate", label: "Lactate", text: t.format(v), flag: IntraopLabs.flag("lactate", v, sex: r.sex, type: type))
            }
            var sat: BriefLabCell?
            if type.hasSaturation, let v = g.values[IntraopLabs.satKey], v.isFinite, let t = IntraopLabs.test(IntraopLabs.satKey, type: type) {
                sat = BriefLabCell(key: IntraopLabs.satKey, label: type.short, text: t.format(v) + "%")
            }
            let gas = BriefGas(type: type, time: g.time.map { PatientSummary.time($0, now: now) }, slash: slash, saturation: sat, lactate: lactate)
            gasOut = gas
            var gi: [BriefLabItem] = []
            if let s = sat { gi.append(BriefLabItem(s)) }
            let present = slash.compactMap { $0 }
            if !present.isEmpty {
                var gasItem = BriefLabItem(key: "gas", text: present.map(\.own).joined(separator: " / "), marks: present.flatMap(\.marks))
                gasItem.plain = present.map(\.ownLetter).joined(separator: " / ")
                gasItem.spoken = present.map(\.ownSpoken).joined(separator: " / ")
                gi.append(gasItem)
            }
            if let l = lactate { gi.append(BriefLabItem(l)) }
            groups.append(BriefLabGroup(name: gas.title, items: gi, isGas: true))
        }

        // Heme (Ben, Nov 11): the newest hemoglobin, always, whatever its value and whether or not a gas was sent; then
        // the newest Plt, INR and fibrinogen, each from the latest set that holds it, and the TEG/ROTEM.
        var coags: [BriefLabItem] = []
        for k in ["hb", "plt", "inr", "fibrinogen"] {
            guard let hit = latest(k, in: sets), let t = PatientLabs.test(k) else { continue }
            let cell = BriefLabCell(key: k, label: t.short, text: t.format(hit.value), flag: PatientLabs.flag(k, hit.value, sex: r.sex))
            var item = BriefLabItem(cell)
            item.timed = true
            item.time = hit.set.time
            coags.append(item)
            timed.append((hit.set.time, t.short))
        }
        if let s = sets.first(where: { !trimmed($0.viscoelastic).isEmpty }) {
            var item = BriefLabItem(key: "teg", text: "TEG/ROTEM: " + trimmed(s.viscoelastic))
            item.timed = true
            item.time = s.time
            item.name = "TEG/ROTEM"
            coags.append(item)
            timed.append((s.time, "TEG/ROTEM"))
        }
        if !coags.isEmpty { groups.append(BriefLabGroup(name: "Heme", items: coags)) }

        // Other: any abnormal value outside the gas and the coags (Ben, Nov 11); the values chosen under "+ Add other
        // input data into Handoff"; and what was typed under Other results.
        var other: [BriefLabItem] = []
        for c in HandoffExtras.intraopCandidates(r) where extras.contains(c.key) || HandoffExtras.alwaysShown(c) {
            other.append(c.item)
            timed.append((c.item.time, c.label))
        }
        if let s = sets.first(where: { !trimmed($0.other).isEmpty }) { other.append(BriefLabItem(key: "intraop-other", text: trimmed(s.other))) }
        if !other.isEmpty { groups.append(BriefLabGroup(name: "Other", items: other)) }
        return (gasOut, groups, timed)
    }
}

// MARK: - + Add other input data into Handoff (1.12, Ben's note 14)

/// What the summaries do not show by default and the record holds, as chips; a chosen chip adds its item
/// (`PatientRecord.handoffExtras`: "preop:<lab key>", "intraop:<lab key>", "imaging:ct|mri|other"). A key whose item is no
/// longer recorded is ignored (it is not offered, and shows nothing).
enum HandoffExtras {
    struct Candidate: Hashable, Identifiable {
        var key: String
        /// The chip's words.
        var label: String
        var item: BriefLabItem
        var id: String { key }
    }

    static let preopPrefix = "preop:"
    static let intraopPrefix = "intraop:"
    static let imagingPrefix = "imaging:"

    /// The preop labs the Preop column shows by default (note 8); every other recorded one is a chip. The hCG is the
    /// pregnancy test's, shown by default for a woman and never offered otherwise; the troponin's 99th percentile goes with
    /// the troponin.
    static let preopDefaults: Set<String> = ["na", "k", "bun", "cr", "gfr", "ast", "alt", "glucose", "hb", "plt", "ptt", "inr", "fibrinogen",
                                             "lactate", "tsh", "ft4", "tbili", "hcg", "troponin99"]
    /// The intraop values the Intraop column shows by default besides the gas: the hemoglobin and the coags (Heme).
    static let intraopDefaults: Set<String> = ["hb", "plt", "inr", "fibrinogen"]

    /// The recorded preoperative labs and results outside the default list, in the catalog's order, then the urinalysis and
    /// blood cultures when negative, then the infectious results that are negative (a positive or pending one is shown by
    /// default).
    static func preopCandidates(_ r: PatientRecord) -> [Candidate] {
        let p99: Double? = r.labs["troponin99"].flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        var out: [Candidate] = []
        for t in PatientLabs.catalog where !preopDefaults.contains(t.key) {
            guard let v = r.labs[t.key], v.isFinite else { continue }
            out.append(Candidate(key: preopPrefix + t.key, label: t.short, item: BriefLabItem(BriefLabs.labCell(t.key, v, sex: r.sex, p99: p99))))
        }
        let m = r.moreLabs
        if m.hasUrinalysis, !m.urinalysisNeedsTelling, let t = m.urinalysisText {
            out.append(Candidate(key: preopPrefix + "ua", label: "Urinalysis", item: BriefLabItem(key: "ua", text: t)))
        }
        if m.hasBloodCultures, !m.bloodCulturesNeedTelling, let t = m.bloodCulturesText {
            out.append(Candidate(key: preopPrefix + "bcx", label: "Blood cultures", item: BriefLabItem(key: "bcx", text: t)))
        }
        for t in LabResults.infectious where t.id != "mrsa" {
            guard let v = r.infections.results[t.id], !v.needsTelling else { continue }
            out.append(Candidate(key: preopPrefix + t.id, label: t.short, item: BriefLabItem(key: t.id, text: t.short + " " + v.short)))
        }
        for o in r.infections.other {
            guard let v = o.result, !o.trimmedName.isEmpty, !v.needsTelling else { continue }
            out.append(Candidate(key: preopPrefix + "infx:" + o.trimmedName.lowercased(), label: o.trimmedName,
                                 item: BriefLabItem(key: "infx", text: o.trimmedName + " " + v.short)))
        }
        return out
    }

    /// The recorded intraoperative values outside the gas and the coags (base excess, potassium, sodium,
    /// ionized calcium, glucose, PTT, ACT, a saturation, and a lactate or gas value the summary's gas does not carry), each
    /// the newest of that test.
    static func intraopCandidates(_ r: PatientRecord) -> [Candidate] {
        let sets = IntraopLabs.ordered(r.intraopLabs)
        guard !sets.isEmpty else { return [] }
        let gas = IntraopLabs.latestGas(r.intraopLabs)
        func finite(_ s: IntraopLabSet?, _ k: String) -> Bool { s.flatMap { $0.values[k] }.map { $0.isFinite } ?? false }
        var out: [Candidate] = []
        for k in IntraopLabs.keys {
            if intraopDefaults.contains(k) { continue }
            // The gas's own values are the figure (the newest gas) or an older gas, which the summary does not carry.
            if IntraopLabs.abgSlash.contains(k) { continue }
            if k == "lactate", finite(gas, k) { continue }
            if k == IntraopLabs.satKey, let g = gas, g.gasType.hasSaturation, finite(g, k) { continue }
            guard let hit = BriefLabs.latest(k, in: sets), let t = IntraopLabs.test(k, type: hit.set.gasType) else { continue }
            var cell = BriefLabCell(key: k, label: t.short, text: t.format(hit.value), flag: IntraopLabs.flag(k, hit.value, sex: r.sex, type: hit.set.gasType))
            if k == IntraopLabs.satKey { cell.text += "%" }
            var item = BriefLabItem(cell)
            item.timed = true
            item.time = hit.set.time
            out.append(Candidate(key: intraopPrefix + k, label: t.short, item: item))
        }
        return out
    }

    /// CT, MRI and Other imaging, when the record holds text for them (`PatientRecord.imaging`). The item's text is what
    /// was typed; the Imaging block of the summaries is built elsewhere (PatientImaging).
    static func imagingCandidates(_ r: PatientRecord) -> [Candidate] {
        func typed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var out: [Candidate] = []
        if !typed(r.imaging.ct).isEmpty { out.append(Candidate(key: imagingPrefix + "ct", label: "CT", item: BriefLabItem(key: "ct", text: typed(r.imaging.ct)))) }
        if !typed(r.imaging.mri).isEmpty { out.append(Candidate(key: imagingPrefix + "mri", label: "MRI", item: BriefLabItem(key: "mri", text: typed(r.imaging.mri)))) }
        if !typed(r.imaging.other).isEmpty {
            out.append(Candidate(key: imagingPrefix + "other", label: "Other imaging", item: BriefLabItem(key: "other", text: typed(r.imaging.other))))
        }
        return out
    }

    /// In the summaries without being chosen: an abnormal value (its item carries a mark). Such an item is not offered
    /// as a chip, since choosing it would change nothing.
    static func alwaysShown(_ c: Candidate) -> Bool { !c.item.marks.isEmpty }

    /// The three groups of chips, in the order they are drawn: what is recorded, not shown by default and not shown anyway.
    static func offered(_ r: PatientRecord) -> (preop: [Candidate], intraop: [Candidate], imaging: [Candidate]) {
        (preopCandidates(r).filter { !alwaysShown($0) }, intraopCandidates(r).filter { !alwaysShown($0) }, imagingCandidates(r))
    }

    /// Chosen and still recorded: how many extras the summaries are showing.
    static func chosenCount(_ r: PatientRecord) -> Int {
        let o = offered(r)
        let keys = Set(r.handoffExtras)
        return (o.preop + o.intraop + o.imaging).filter { keys.contains($0.key) }.count
    }

    /// A chip's tap: chosen, or not.
    static func toggle(_ key: String, in r: inout PatientRecord) {
        if let i = r.handoffExtras.firstIndex(of: key) { r.handoffExtras.remove(at: i) } else { r.handoffExtras.append(key) }
    }
}
