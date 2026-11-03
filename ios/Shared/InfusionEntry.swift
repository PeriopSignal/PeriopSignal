import Foundation

// MARK: - Infusions typed in one line (1.8.1)
//
// "norepi 0.05, vaso 0.04": the Infusions groups (intraoperative, and Current infusions before the case) take drips
// typed the way the quick-add bar takes them. Each piece is a drug from the infusion list, written out or by its
// usual abbreviation, then the rate and the unit as typed. With no unit typed, the unit is the drug's own from the
// app's catalog: for the drips the quick-add bar reads (QuickAdd.dripUnits), the Reference table's unit by the size of
// the number (QuickDrip: "norepi 0.05" is mcg/kg/min, "norepi 4" mcg/min); for the others, the one infusion unit the
// Reference table gives. When the drug or the unit could be more than one, it asks. Nothing is filled in that was not
// typed: no rate, no dose. A comma starts another drip.

/// A drug the line knows, as the record names it.
struct InfusionEntryDrug: Hashable, Identifiable {
    /// The Reference infusion table's id (reference.json), or our own for a drug the table does not list.
    var id: String
    /// As the record names it: "Norepinephrine".
    var name: String
    /// What may be typed for it, lowercased; the name is one.
    var aliases: [String]
    /// The catalog's unit, used when no unit is typed and no size rule applies; nil when the catalog gives none for an
    /// infusion (insulin, amiodarone: their table entries are a protocol or a bolus).
    var unit: String?
    /// The units offered when it asks, the usual first.
    var units: [String]
}

enum InfusionEntry {
    /// One drip read from the line.
    struct Item: Hashable, Identifiable {
        var drugID: String
        /// As the record names it ("Norepinephrine").
        var drug: String
        /// The rate and its unit ("0.05 mcg/kg/min"), the number alone when no unit applies, "" when none was typed.
        var rate: String
        /// The piece as typed.
        var typed: String
        /// Said under the chips: the unit read from the size of the number.
        var note: String?
        var id: String { drugID + "|" + rate + "|" + typed }
        /// "Norepinephrine 0.05 mcg/kg/min".
        var label: String { rate.isEmpty ? drug : drug + " " + rate }
    }

    /// A question, asked the way the quick-add bar asks one: nothing from its piece is added until it is answered.
    struct Question: Hashable, Identifiable {
        /// The key the answer is kept under in `choices`.
        var id: String
        /// "levo", "epi 1".
        var label: String
        var options: [Option]
        struct Option: Hashable, Identifiable {
            var id: String
            var text: String
        }
        /// "norepinephrine or levosimendan".
        var text: String { options.map(\.text).joined(separator: " or ") }
    }

    struct Reading: Hashable {
        var items: [Item] = []
        var questions: [Question] = []
        /// Pieces whose drug is not in the list, as typed.
        var unknown: [String] = []
        var isEmpty: Bool { items.isEmpty && questions.isEmpty && unknown.isEmpty }
    }

    /// The answer that keeps a rate without a unit.
    static let noUnit = "no unit"

    // MARK: The drugs

    // Units and defaults from reference.json's infusion table (InfusionTests checks them): perMin is "<unit>/min",
    // perKgPerMin "<unit>/kg/min", perHour "<unit>/h", perKgPerHour "<unit>/kg/h"; vasopressin and inhaled nitric oxide
    // give their unit outright. Where the table's entry is a bolus or a protocol (amiodarone, ketamine, lidocaine,
    // insulin, heparin, bivalirudin, diltiazem, tranexamic and aminocaproic acid), or the drug is not in it
    // (sufentanil), there is no default and the line asks.
    static let drugs: [InfusionEntryDrug] = [
        d("norepinephrine", "Norepinephrine", ["norepinephrine", "noradrenaline", "norepi", "levophed", "ne"], "mcg/min", ["mcg/kg/min", "mcg/min"]),
        d("epinephrine", "Epinephrine", ["epinephrine", "adrenaline", "epi"], "mcg/min", ["mcg/kg/min", "mcg/min"]),
        d("vasopressin", "Vasopressin", ["vasopressin", "vaso", "vasostrict", "avp"], "units/min", ["units/min", "units/h"]),
        d("phenylephrine", "Phenylephrine", ["phenylephrine", "phenyl", "neo", "neosynephrine", "neo-synephrine", "phenylepherine"], "mcg/min", ["mcg/min", "mcg/kg/min"]),
        d("angiotensin2", "Angiotensin II", ["angiotensin ii", "angiotensin 2", "angiotensin", "giapreza", "ang ii", "ang 2", "at2"], "ng/kg/min", ["ng/kg/min"]),
        d("milrinone", "Milrinone", ["milrinone", "milri", "primacor"], "mcg/kg/min", ["mcg/kg/min"]),
        d("dobutamine", "Dobutamine", ["dobutamine", "dobut", "dobuta", "dobu"], "mcg/kg/min", ["mcg/kg/min"]),
        d("dopamine", "Dopamine", ["dopamine", "dopa"], "mcg/kg/min", ["mcg/kg/min"]),
        d("isoproterenol", "Isoproterenol", ["isoproterenol", "isuprel", "iso", "isoprenaline"], "mcg/min", ["mcg/min"]),
        d("levosimendan", "Levosimendan", ["levosimendan", "simdax"], "mcg/kg/min", ["mcg/kg/min"]),
        d("nitroglycerin", "Nitroglycerin", ["nitroglycerin", "nitroglycerine", "ntg", "tng", "nitro", "gtn"], "mcg/min", ["mcg/min", "mcg/kg/min"]),
        d("nitroprusside", "Nitroprusside", ["nitroprusside", "snp", "nipride", "nitropress"], "mcg/kg/min", ["mcg/kg/min"]),
        d("nicardipine", "Nicardipine", ["nicardipine", "nicard", "nicardi", "cardene"], "mg/h", ["mg/h"]),
        d("clevidipine", "Clevidipine", ["clevidipine", "clevi", "cleviprex"], "mg/h", ["mg/h"]),
        d("esmolol", "Esmolol", ["esmolol", "brevibloc"], "mcg/kg/min", ["mcg/kg/min"]),
        d("diltiazem", "Diltiazem", ["diltiazem", "dilt", "cardizem"], nil, ["mg/h"]),
        d("amiodarone", "Amiodarone", ["amiodarone", "amio", "nexterone"], nil, ["mg/min", "mg/h"]),
        d("lidocaine-iv", "Lidocaine", ["lidocaine", "lido"], nil, ["mg/min", "mg/kg/h"]),
        d("insulin", "Insulin", ["insulin", "regular insulin"], nil, ["units/h"]),
        d("heparin", "Heparin", ["heparin", "hep", "ufh"], nil, ["units/h", "units/kg/h"]),
        d("bivalirudin", "Bivalirudin", ["bivalirudin", "bival", "angiomax"], nil, ["mg/kg/h"]),
        d("tranexamic", "Tranexamic acid", ["tranexamic acid", "tranexamic", "txa"], nil, ["mg/kg/h"]),
        d("aminocaproic", "Aminocaproic acid", ["aminocaproic acid", "aminocaproic", "amicar", "eaca"], nil, ["g/h"]),
        d("propofol", "Propofol", ["propofol", "prop", "diprivan"], "mcg/kg/min", ["mcg/kg/min"]),
        d("dexmedetomidine", "Dexmedetomidine", ["dexmedetomidine", "dexmed", "dex", "precedex"], "mcg/kg/h", ["mcg/kg/h"]),
        d("ketamine", "Ketamine", ["ketamine", "ket", "ketalar"], nil, ["mg/kg/h", "mcg/kg/min"]),
        d("remifentanil", "Remifentanil", ["remifentanil", "remi", "ultiva"], "mcg/kg/min", ["mcg/kg/min"]),
        d("sufentanil", "Sufentanil", ["sufentanil", "sufent", "sufenta"], nil, ["mcg/kg/h", "mcg/h"]),
        d("iepo", "Epoprostenol, inhaled", ["epoprostenol", "inhaled epoprostenol", "iepo", "flolan", "veletri"], "ng/kg/min", ["ng/kg/min"]),
        d("ino", "Nitric oxide, inhaled", ["nitric oxide", "inhaled nitric oxide", "ino", "inomax"], "ppm", ["ppm"]),
    ]

    /// Words that name more than one drip: asked.
    static let ambiguous: [String: [String]] = ["levo": ["norepinephrine", "levosimendan"]]

    private static func d(_ id: String, _ name: String, _ aliases: [String], _ unit: String?, _ units: [String]) -> InfusionEntryDrug {
        InfusionEntryDrug(id: id, name: name, aliases: aliases, unit: unit, units: units)
    }

    static func drug(id: String) -> InfusionEntryDrug? { drugs.first { $0.id == id } }

    /// The drug a recorded infusion names ("Norepinephrine (Levophed)", "norepinephrine", "NE"), so a typed drip
    /// updates its row instead of adding a second.
    static func drugID(of recorded: String) -> String? {
        var t = fold(recorded)
        if let p = t.firstIndex(of: "(") { t = String(t[..<p]).trimmingCharacters(in: .whitespaces) }
        if let comma = t.firstIndex(of: ","), !t.hasPrefix("epoprostenol"), !t.hasPrefix("nitric") {
            t = String(t[..<comma]).trimmingCharacters(in: .whitespaces)
        }
        if let x = drugs.first(where: { fold($0.name) == t || $0.aliases.contains(t) }) { return x.id }
        return nil
    }

    // MARK: Reading

    /// Typeahead for the piece being typed (the last one, before its rate): drugs whose name or an alias starts with
    /// what was typed, the name first.
    static func suggestions(_ text: String, limit: Int = 4) -> [InfusionEntryDrug] {
        guard let last = pieces(text).last else { return [] }
        let parts = split(last)
        guard parts.rate == nil else { return [] }
        let w = fold(parts.drug)
        guard w.count >= 2 else { return [] }
        if drugs.contains(where: { fold($0.name) == w }) { return [] }
        var out: [InfusionEntryDrug] = []
        for x in drugs where fold(x.name).hasPrefix(w) && !out.contains(x) { out.append(x) }
        for x in drugs where x.aliases.contains(where: { $0.hasPrefix(w) }) && !out.contains(x) { out.append(x) }
        return Array(out.prefix(limit))
    }

    /// The line read: drips to add, questions, and drugs not in the list. `choices`: the answers given, by question id.
    static func read(_ text: String, choices: [String: String] = [:]) -> Reading {
        var r = Reading()
        let all = pieces(text)
        for (n, piece) in all.enumerated() {
            var parts = split(piece)
            // "angiotensin 2" is the drug's name, not a rate of 2.
            if let rate = parts.rate, parts.unit == nil, parts.high == nil, !matches(parts.drug + " " + rate, prefix: false).isEmpty {
                parts = (parts.drug + " " + rate, nil, nil, nil)
            }
            let word = fold(parts.drug)
            guard !word.isEmpty else { continue }
            // The piece still being typed, with no rate yet: the typeahead speaks for it.
            let typing = n == all.count - 1 && parts.rate == nil
            // The drug.
            var drug: InfusionEntryDrug?
            let candidates = matches(word)
            if candidates.count == 1 {
                drug = candidates[0]
            } else if candidates.count > 1 {
                let qid = "drug:" + word
                if let a = choices[qid], let x = candidates.first(where: { $0.id == a }) {
                    drug = x
                } else {
                    let q = Question(id: qid, label: parts.drug, options: candidates.prefix(4).map { Question.Option(id: $0.id, text: $0.name.lowercasedFirst) })
                    if !r.questions.contains(q) { r.questions.append(q) }
                    continue
                }
            }
            guard let drug else {
                if !typing && !r.unknown.contains(parts.drug) { r.unknown.append(parts.drug) }
                continue
            }
            // The rate and its unit: as typed; without a unit, the catalog's.
            guard let rate = parts.rate else {
                r.items.append(Item(drugID: drug.id, drug: drug.name, rate: "", typed: piece))
                continue
            }
            if let u = parts.unit {
                r.items.append(Item(drugID: drug.id, drug: drug.name, rate: rate + " " + u, typed: piece))
                continue
            }
            var offered: [String]?
            if let qd = QuickAdd.dripUnits.first(where: { $0.reference == drug.id }), let v = Double(parts.high ?? rate) {
                let low = Double(rate) ?? v
                switch (qd.fit(low), qd.fit(v)) {
                case (.unit(let a), .unit(let b)) where a == b:
                    r.items.append(Item(drugID: drug.id, drug: drug.name, rate: rate + " " + a, typed: piece, note: "No unit written: read as " + a + "."))
                    continue
                case (.asTyped, _), (_, .asTyped):
                    offered = qd.overlapUnits
                default:
                    offered = drug.units
                }
            } else if let u = drug.unit {
                r.items.append(Item(drugID: drug.id, drug: drug.name, rate: rate + " " + u, typed: piece, note: "No unit written: read as " + u + "."))
                continue
            }
            let units = offered ?? drug.units
            let qid = "unit:" + drug.id + ":" + rate
            if let a = choices[qid], a == noUnit || units.contains(a) {
                r.items.append(Item(drugID: drug.id, drug: drug.name, rate: a == noUnit ? rate : rate + " " + a, typed: piece))
            } else {
                let q = Question(id: qid, label: parts.drug + " " + rate, options: units.map { Question.Option(id: $0, text: $0) } + [Question.Option(id: noUnit, text: noUnit)])
                if !r.questions.contains(q) { r.questions.append(q) }
            }
        }
        return r
    }

    /// The drugs a typed word names: an alias outright (or a word that names several, all of them); else every drug
    /// a name or an alias of which starts with it (three letters or more).
    static func matches(_ word: String, prefix: Bool = true) -> [InfusionEntryDrug] {
        let w = fold(word)
        if let ids = ambiguous[w] { return ids.compactMap { drug(id: $0) } }
        let exact = drugs.filter { fold($0.name) == w || $0.aliases.contains(w) }
        if !exact.isEmpty { return exact }
        guard prefix, w.count >= 3 else { return [] }
        return drugs.filter { fold($0.name).hasPrefix(w) || $0.aliases.contains { $0.hasPrefix(w) } }
    }

    // MARK: Adding

    /// Adds the drips to a list of infusions: a drug already there takes the new rate (a drip typed without a rate
    /// leaves its rate as it is); a new drug is added.
    static func apply(_ items: [Item], to list: inout [PatientInfusion]) {
        for it in items {
            if let i = list.firstIndex(where: { drugID(of: $0.drug) == it.drugID }) {
                if !it.rate.isEmpty { list[i].rate = it.rate }
            } else {
                list.append(PatientInfusion(drug: it.drug, rate: it.rate))
            }
        }
    }

    /// How an item compares with the list: new, already there, or replacing a rate.
    static func status(_ it: Item, in list: [PatientInfusion]) -> PatientNoteStatus {
        guard let o = list.first(where: { drugID(of: $0.drug) == it.drugID }) else { return .new }
        if it.rate.isEmpty || o.rate.caseInsensitiveCompare(it.rate) == .orderedSame { return .recorded }
        return o.rate.isEmpty ? .new : .replaces(o.rate)
    }

    // MARK: Pieces

    /// The line's drips: split at commas (not inside a number: "1,000"), semicolons, "+" and "and".
    static func pieces(_ text: String) -> [String] {
        let marked = splitRx.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\u{1F}")
        return marked.split(separator: "\u{1F}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static let thousandsRx = try! NSRegularExpression(pattern: #"(\d),(\d{3})(?!\d)"#)
    private static let splitRx = try! NSRegularExpression(pattern: #"\s*(?:[;+\n]|,(?!\d{3}\b)|\band\b)\s*"#, options: [.caseInsensitive])

    /// One piece: the drug words, the rate (and the top of a range), and the unit.
    static func split(_ raw: String) -> (drug: String, rate: String?, high: String?, unit: String?) {
        // "1,000 units/h": the thousands comma goes.
        let piece = thousandsRx.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "$1$2")
        let ns = piece as NSString
        guard let m = rateRx.firstMatch(in: piece, range: NSRange(location: 0, length: ns.length)) else {
            return (cleanDrug(piece), nil, nil, nil)
        }
        let drug = cleanDrug(ns.substring(to: m.range.location))
        func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        let low = number(g(1) ?? "")
        let high = g(2).map(number)
        let unit = g(3).flatMap(normalizedUnit)
        let rate = high.map { low + "–" + $0 } ?? low
        return (drug, rate, high, unit)
    }

    /// The first number in the piece that is not part of the drug's own name ("angiotensin 2 20" reads 20), with a
    /// range ("0.05-0.1") and the unit after it.
    private static let rateRx = try! NSRegularExpression(pattern:
        #"(?<![A-Za-z0-9.])(\d*\.?\d+)(?:\s*(?:-|–|to)\s*(\d*\.?\d+))?\s*((?:mcg|ug|µg|μg|mg|ng|g|units?|u|iu|ml|ppm|mic)(?:\s*/\s*kg)?(?:\s*/\s*(?:min(?:ute)?s?|hr?s?|hours?|m))?)?\s*(?:gtts?|drips?|infusion)?\s*$"#,
        options: [.caseInsensitive])

    private static func cleanDrug(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        let trailing = ["gtt", "gtts", "drip", "drips", "infusion", "at", "@", "=", ":", "running at", "running"]
        var changed = true
        while changed {
            changed = false
            for w in trailing {
                let low = t.lowercased()
                if low.hasSuffix(" " + w) || low == w || (w.count == 1 && low.hasSuffix(w)) {
                    t = String(t.dropLast(w.count)).trimmingCharacters(in: .whitespaces)
                    changed = true
                }
            }
        }
        return t
    }

    /// ".05" → "0.05".
    private static func number(_ s: String) -> String { s.hasPrefix(".") ? "0" + s : s }

    /// "mcg/kg/min", "units/h", "ppm": typed forms read the one way ("ug/kg/min", "U/hr", "mcg/kg/m").
    static func normalizedUnit(_ s: String) -> String? {
        let parts = s.lowercased().replacingOccurrences(of: " ", with: "").split(separator: "/").map(String.init)
        guard let first = parts.first else { return nil }
        let mass: [String: String] = ["mcg": "mcg", "ug": "mcg", "µg": "mcg", "μg": "mcg", "mic": "mcg", "mg": "mg", "ng": "ng", "g": "g",
                                      "unit": "units", "units": "units", "u": "units", "iu": "units", "ml": "mL", "ppm": "ppm"]
        guard let m = mass[first] else { return nil }
        var out = m
        for p in parts.dropFirst() {
            if p == "kg" { out += "/kg" }
            else if p.hasPrefix("min") || p == "m" { out += "/min" }
            else if p.hasPrefix("h") { out += "/h" }
            else { return nil }
        }
        return out
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
