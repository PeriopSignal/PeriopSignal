import Foundation

// MARK: - Home medications and allergies as items (1.9, Ben's Wanted Changes)
//
// "Need large reference list of common home medications so the user does not need to type everything to the last
// letter. Should be smart enough to list multiple medications with a space or comma break … Flagged medications should
// autoselect if added to home medications." The catalog gives each common outpatient drug its generic name, brand names
// and abbreviations, and the medication flags it raises (PatientCatalog.medFlags ids: "anticoagulant", "p2y12",
// "aspirin", "insulin", "glp1", "sglt2", "betablocker", "acei", "statin", "steroid", "opioid", "maoi"). The list itself,
// its sources and the judgment behind each flag are in MedicationCatalogData.swift.
//
// A typed line ("metoprolol 25 mg bid, lisinopril 10 atorvastatin") is read as items: commas, semicolons, new lines, "+"
// and "and" separate them, and so does a space before a drug the list knows ("metoprolol lisinopril atorvastatin" is
// three). The longest name wins ("insulin glargine", "Toprol XL"). What follows a drug up to the next one is its dose,
// as typed. A brand reads as its generic name ("Eliquis 5 bid" is Apixaban, "5 bid"): the catalog id keeps the brand's
// entry, so nothing is lost and the list reads one way. A word the list does not know becomes a typed item only where a
// drug name would be (the start of an item, or a word with a drug's ending such as -pril or -olol after a dose); dose and
// timing words ("daily", "mg", "prn") never do, nor a word after "last dose" or "held" ("last dose Sunday" is a remark
// on the drug before). A drug after a denial ("no opioids", "denies anticoagulants") is kept as typed and raises no flag;
// a stop ("stopped Plavix 5 days ago", "holding Eliquis", "no longer taking Plavix") stays with its drug and its flag, and
// so does a denied stop ("not holding Eliquis", "did not stop Plavix"). Only "or" carries a denial on to the next drug,
// and never to one with a dose ("no aspirin and Eliquis 5 mg bid" takes Eliquis).

/// One drug the list knows.
struct MedEntry: Hashable, Identifiable {
    var id: String
    /// The generic name as the list shows it: "Metoprolol succinate".
    var name: String
    /// Brand names and abbreviations that find it, lowercased ("toprol xl", "toprol").
    var aliases: [String]
    /// The medication flags it raises.
    var flags: Set<String>
    /// Its class, for the list's second line: "Beta-blocker".
    var drugClass: String
}

enum MedicationCatalog {
    private static let parsedRows: [(entry: MedEntry, common: Bool)] = MedicationData.rows.compactMap(row)
    static let entries: [MedEntry] = parsedRows.map(\.entry)
    /// The most prescribed, offered first among equal matches.
    static let commonIDs: Set<String> = Set(parsedRows.filter(\.common).map(\.entry.id))

    private static let byID: [String: Int] = Dictionary(entries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    private static let commonIndex: Set<Int> = Set(entries.indices.filter { commonIDs.contains(entries[$0].id) })

    static let phrases = CatalogPhrases(forms: CatalogPhrases.forms(entries.map { (name: $0.name, aliases: $0.aliases) }))

    /// "id|Name|aliases|flags|class", a leading "*" on the id for the most prescribed.
    private static func row(_ s: String) -> (entry: MedEntry, common: Bool)? {
        let f = s.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard f.count == 5, !f[0].isEmpty, !f[1].isEmpty else { return nil }
        var id = f[0]
        let common = id.hasPrefix("*")
        if common { id.removeFirst() }
        let aliases = f[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let flags = Set(f[3].split(separator: " ").map(String.init))
        return (MedEntry(id: id, name: f[1], aliases: aliases, flags: flags, drugClass: f[4]), common)
    }

    static func entry(id: String) -> MedEntry? { byID[id].map { entries[$0] } }

    /// The entry a whole name names exactly, generic or brand ("Toprol XL", "apixaban"); nil otherwise.
    static func entry(named s: String) -> MedEntry? { phrases.exact(s).map { entries[$0] } }

    // MARK: Search

    /// One entry the type-ahead offers, with the brand or abbreviation that found it when that is not the name.
    struct Hit: Hashable {
        var entry: MedEntry
        /// "eliquis" when "eli" found Apixaban by its brand.
        var matched: String?
    }

    /// The entries a typed prefix finds, best first.
    static func search(_ q: String, limit: Int = 8) -> [MedEntry] { hits(q, limit: limit).map(\.entry) }

    static func hits(_ q: String, limit: Int = 8) -> [Hit] {
        phrases.search(q, limit: limit) { commonIndex.contains($0) ? 1 : 0 }.map { h in
            let p = phrases.phrases[h.phrase]
            return Hit(entry: entries[h.entry], matched: p.isName ? nil : p.text)
        }
    }

    /// A suggestion for what is being typed at the end of the line, with the words it replaces.
    struct Suggestion: Hashable {
        var hit: Hit
        var replaces: Range<String.Index>
        /// The text after the pick: the words replaced by the entry's name and a space.
        func completing(_ line: String) -> String {
            line.replacingCharacters(in: replaces, with: MedicationCatalog.listName(hit.entry) + " ")
        }
    }

    /// The type-ahead for the end of the line: the last one to three words being typed (not a dose or timing word, not
    /// the start of one after a drug: "metoprolol 25 mg b" offers nothing). The longer query first ("insulin gla"), then
    /// the last word alone ("lisinopril meto").
    static func typeahead(_ line: String, limit: Int = 5) -> [Suggestion] {
        guard let last = line.last, last.isLetter || last.isNumber else { return [] }
        let ws = CatalogText.words(line)
        guard !ws.isEmpty, ws[ws.count - 1].range.upperBound == line.endIndex else { return [] }
        let br = CatalogText.breaks(line, ws)
        let segStart = ws.indices.last(where: { br[$0] || ws[$0].key == "and" }).map { ws[$0].key == "and" ? $0 + 1 : $0 } ?? 0
        guard segStart < ws.count else { return [] }
        // Does the item being typed already name a drug before the last word? Then a dose word may be on its way.
        let drugBefore = (segStart..<(ws.count - 1)).contains(where: { phrases.longest(ws, at: $0) != nil })
        var out: [Suggestion] = []
        for n in stride(from: min(3, ws.count - segStart), through: 1, by: -1) {
            let start = ws.count - n
            let w = ws[start]
            guard w.isLetters, w.key.count >= 2, !noise.contains(w.key) else { continue }
            if n == 1, drugBefore, noise.contains(where: { $0.hasPrefix(w.key) }) { continue }
            let q = String(line[w.range.lowerBound...])
            for h in hits(q, limit: limit) where !out.contains(where: { $0.hit.entry.id == h.entry.id }) {
                out.append(Suggestion(hit: h, replaces: w.range.lowerBound..<line.endIndex))
            }
            if out.count >= limit { break }
        }
        // A whole name typed and nothing more to offer.
        if out.count == 1, let s = out.first, phrases.exact(String(line[s.replaces])) == byID[s.hit.entry.id] { return [] }
        return Array(out.prefix(limit))
    }

    /// The name an item takes and a pick puts in the line: the generic name, without "(agent not named)" when the rest
    /// still names the entry ("Insulin", "Statin").
    static func listName(_ e: MedEntry) -> String {
        if let p = e.name.range(of: " (") {
            let short = String(e.name[..<p.lowerBound])
            if entry(named: short)?.id == e.id { return short }
            if let a = e.aliases.first, entry(named: a)?.id == e.id { return a }
        }
        return e.name
    }

    // MARK: Reading a line

    /// One item read from a line, with where its name sits.
    struct ReadItem: Hashable {
        var med: PatientMed
        /// Not in the list: as typed.
        var typed: Bool { med.catalogID == nil }
        var nameRange: Range<String.Index>
    }

    /// A line of several medications ("metoprolol 25 bid, lisinopril 10 daily atorvastatin"), as items.
    static func parse(_ line: String) -> [PatientMed] { read(line).map(\.med) }

    /// As `parse`, with a word still being typed at the end of the line left out when the list does not know it yet
    /// (the type-ahead speaks for it).
    static func reading(_ line: String) -> [ReadItem] {
        var items = read(line)
        if let last = line.last, last.isLetter || last.isNumber, let it = items.last, it.typed, it.nameRange.upperBound == line.endIndex {
            items.removeLast()
        }
        return items
    }

    static func read(_ line: String) -> [ReadItem] {
        struct Building {
            var entry: Int?
            var nameRange: Range<String.Index>
            var dose: [Int] = []
        }
        let ws = CatalogText.words(line)
        let br = CatalogText.breaks(line, ws)
        var out: [Building] = []
        var itemInSegment = false
        var pending: [Int] = []
        // Where this segment's items start in `out`.
        var segmentStart = 0
        // The first word since the last drug that denies or stops the next one ("no", "denies"; "stopped", "held").
        var modifier: Int?
        // The item a denial made in this segment, and the word after its drug: "or" or "and" carries the denial on.
        var deniedItem: Int?
        var deniedEnd = 0

        // A segment that names no drug but says when one was last taken, held or stopped ("last dose Sunday", "held
        // since Monday"): it belongs to the drug before.
        func closeSegment() {
            if out.count == segmentStart, !out.isEmpty, pending.contains(where: { remarks.contains(ws[$0].key) || stops.contains(ws[$0].key) }) {
                out[out.count - 1].dose += pending
            }
            pending = []
            itemInSegment = false
            modifier = nil
            deniedItem = nil
            segmentStart = out.count
        }

        var i = 0
        while i < ws.count {
            if br[i] { closeSegment() }
            let w = ws[i]
            if w.key == "and" {
                itemInSegment = false
                pending = []
                modifier = nil
                i += 1
                continue
            }
            if let m = phrases.longest(ws, at: i) {
                let range = w.range.lowerBound..<ws[i + m.count - 1].range.upperBound
                // "Denies opioids or anticoagulants": one denial, as typed. Only "or" carries it on, and not to a drug
                // with a dose after it: "no aspirin and Eliquis 5 mg bid" takes Eliquis.
                let dosed = i + m.count < ws.count && !br[i + m.count] && ws[i + m.count].isNumeric
                if let d = deniedItem, d == out.count - 1, !dosed,
                   (deniedEnd..<i).contains(where: { ["or", "nor"].contains(ws[$0].key) }),
                   (deniedEnd..<i).allSatisfy({ deniedBetween.contains(ws[$0].key) }) {
                    out[d].nameRange = out[d].nameRange.lowerBound..<range.upperBound
                    out[d].dose.removeAll { $0 < i }
                    deniedEnd = i + m.count
                    pending = []
                    modifier = nil
                    itemInSegment = true
                    i += m.count
                    continue
                }
                // "No aspirin or Eliquis 5 mg": the "or" is not a word of the denial.
                if let d = deniedItem, d == out.count - 1 {
                    out[d].dose.removeAll { $0 >= deniedEnd && deniedBetween.contains(ws[$0].key) }
                }
                // The same drug named again in its own item ("apixaban (Eliquis) 5 mg") is one item; a brand in
                // parentheses right after the generic ("metoprolol (Toprol XL) 50 mg") is the same item, read as the
                // more specific entry when it is one ("Metoprolol succinate"), or as the combination pill it names
                // ("metformin (Synjardy)" is empagliflozin/metformin, which raises the SGLT2 flag).
                if itemInSegment, let last = out.last {
                    if last.entry == m.entry {
                        i += m.count
                        continue
                    }
                    if let le = last.entry, last.dose.isEmpty, line[last.nameRange.upperBound..<w.range.lowerBound].contains("(") {
                        if refines(m.entry, le) { out[out.count - 1].entry = m.entry }
                        i += m.count
                        continue
                    }
                }
                // The words before the drug: a dose written first ("2 puffs albuterol"), or a stop ("stopped Plavix 5
                // days ago", "holding Eliquis", "no longer taking Plavix"), kept with it; a denial ("no opioids", "denies
                // anticoagulants") makes an item as typed, which raises no flag. A denial of a stop ("not holding
                // Eliquis", "did not stop Plavix") is the drug still taken.
                var before = pending
                if let n = modifier, itemInSegment, !out.isEmpty {
                    before = out[out.count - 1].dose.filter { $0 >= n }
                    out[out.count - 1].dose.removeAll { $0 >= n }
                }
                if let n = modifier, let d = (n..<i).first(where: { denials.contains(ws[$0].key) }),
                   !(d + 1..<i).contains(where: { stops.contains(ws[$0].key) }) {
                    out.append(Building(entry: nil, nameRange: ws[n].range.lowerBound..<range.upperBound))
                    deniedItem = out.count - 1
                    deniedEnd = i + m.count
                } else {
                    let keep = before.contains { ws[$0].isNumeric || stops.contains(ws[$0].key) }
                    out.append(Building(entry: m.entry, nameRange: range, dose: keep ? before : []))
                }
                pending = []
                modifier = nil
                itemInSegment = true
                i += m.count
                continue
            }
            // After "last dose", "held" or "no", a word the list does not know is not a drug's name ("last dose Sunday").
            let remarked = modifier != nil || pending.contains { remarks.contains(ws[$0].key) }
            if !remarked, startsTypedName(w, atStart: !itemInSegment) {
                var j = i + 1
                while j < ws.count, j - i < 3, !br[j], ws[j].key != "and", phrases.longest(ws, at: j) == nil, continuesName(ws[j]) { j += 1 }
                out.append(Building(entry: nil, nameRange: w.range.lowerBound..<ws[j - 1].range.upperBound,
                                    dose: pending.contains(where: { ws[$0].isNumeric }) ? pending : []))
                pending = []
                itemInSegment = true
                i = j
                continue
            }
            if denials.contains(w.key) || stops.contains(w.key) {
                if modifier == nil { modifier = i }
            } else if !noise.contains(w.key), !leadNoise.contains(w.key) {
                modifier = nil
            }
            // "Stopped taking Plavix": after a stop, "taking" stays with it.
            if leadNoise.contains(w.key) && !itemInSegment && modifier == nil {
                i += 1
                continue
            }
            if itemInSegment { out[out.count - 1].dose.append(i) } else { pending.append(i) }
            i += 1
        }
        closeSegment()
        return out.map { b in
            let dose = CatalogText.text(line, runs: CatalogText.runs(line, ws, b.dose))
            if let e = b.entry {
                // "Hydrocortisone 1% cream", "prednisolone 1% eye drops": the name as read, the local form's entry.
                let id = localForm(e, b.dose.map { ws[$0].key }).map { entries[$0].id } ?? entries[e].id
                return ReadItem(med: PatientMed(name: listName(entries[e]), dose: dose, catalogID: id), nameRange: b.nameRange)
            }
            return ReadItem(med: PatientMed(name: FreeText.cap(String(line[b.nameRange])), dose: dose), nameRange: b.nameRange)
        }
    }

    /// Entry `b` is a more specific form of entry `a` ("Metoprolol succinate" of metoprolol) or a combination pill
    /// holding it ("Empagliflozin/metformin" holds metformin).
    private static func refines(_ b: Int, _ a: Int) -> Bool {
        let short = CatalogText.fold(listName(entries[a]))
        let name = CatalogText.fold(entries[b].name)
        return name.hasPrefix(short) || name.split(separator: "/").contains { $0.trimmingCharacters(in: .whitespaces) == short }
    }

    /// Words that deny the drug after them: "no opioids", "denies anticoagulants", "never on insulin".
    static let denials: Set<String> = ["no", "not", "denies", "denied", "never", "nor", "doesnt", "didnt", "dont", "hasnt",
                                       "havent", "isnt", "wasnt"]
    /// Words that stop or hold the drug after them: "stopped Plavix 5 days ago", "holding Eliquis", "no longer taking
    /// Plavix". After a denial they still stop ("not holding Eliquis" is Eliquis taken).
    static let stops: Set<String> = ["stopped", "stop", "stopping", "held", "hold", "holding", "discontinued", "off", "quit",
                                     "paused", "longer"]
    /// Words between two denied drugs that carry the denial on: "denies opioids or insulin", "no opioid use or insulin".
    private static let deniedBetween: Set<String> = ["or", "nor", "any", "use", "other", "either"]
    /// Words that open a remark on the drug before: "last dose Sunday", "last taken this morning".
    static let remarks: Set<String> = ["last", "taken", "took", "since", "ago", "longer", "dose", "doses", "dosed"]

    /// A systemic glucocorticoid written with a route on the skin or in the eye ("hydrocortisone 1% cream", "prednisolone
    /// 1% eye drops") reads as its topical or eye-drop entry, which raises no flag: the steroid flag is for systemic use.
    /// Any other route keeps the systemic entry.
    private static let localRoutes: [(suffix: String, words: Set<String>)] = [
        (suffix: "-ophthalmic", words: ["eye", "eyes", "ophthalmic", "ou", "os", "gtt", "gtts", "drop", "drops"]),
        (suffix: "-topical", words: ["cream", "ointment", "lotion", "topical", "top", "skin", "gel"]),
    ]

    private static func localForm(_ e: Int, _ words: [String]) -> Int? {
        guard entries[e].flags.contains("steroid") else { return nil }
        for r in localRoutes where words.contains(where: { r.words.contains($0) }) {
            if let i = byID[entries[e].id + r.suffix] { return i }
        }
        return nil
    }

    /// A word the list does not know that reads as a drug's name: at the start of an item any word of three letters or
    /// more that is not a dose, timing or filler word; after that, only one with a drug's ending (lisinopril's -pril).
    private static func startsTypedName(_ w: CatalogWord, atStart: Bool) -> Bool {
        guard w.isLetters, w.key.count >= 3, !noise.contains(w.key), !leadNoise.contains(w.key) else { return false }
        if atStart { return true }
        return w.key.count >= 5 && drugEndings.contains(where: { w.key.hasSuffix($0) })
    }

    /// The next word of a typed name: letters, or a short letter-digit word ("K2", "B6"); not a dose word.
    private static func continuesName(_ w: CatalogWord) -> Bool {
        guard !noise.contains(w.key), !leadNoise.contains(w.key), w.key.first?.isLetter == true else { return false }
        if w.isLetters { return w.key.count >= 2 }
        // "q6h", "x2" are timing.
        if (w.key.hasPrefix("q") || w.key.hasPrefix("x")), w.key.dropFirst().first?.isNumber == true { return false }
        return w.key.count <= 3
    }

    /// Dose, route and timing words: never a drug's name.
    static let noise: Set<String> = [
        "mg", "mcg", "ug", "g", "gm", "gram", "grams", "kg", "ml", "l", "unit", "units", "u", "iu", "meq", "mmol",
        "tab", "tabs", "tablet", "tablets", "cap", "caps", "capsule", "capsules", "pill", "pills", "puff", "puffs", "spray",
        "sprays", "drop", "drops", "patch", "patches", "inj", "injection", "injections", "shot", "shots", "dose", "doses",
        "po", "iv", "im", "sc", "sq", "subq", "subcut", "sl", "pr", "top", "topical", "inh", "inhaled", "inhaler", "neb",
        "nebs", "nebulizer", "nasal", "oral", "orally", "daily", "bid", "tid", "qid", "qd", "qam", "qpm", "qhs", "hs",
        "prn", "qod", "qwk", "weekly", "monthly", "once", "twice", "times", "day", "days", "week", "weeks", "month",
        "months", "year", "years", "morning", "evening", "night", "nightly", "bedtime", "am", "pm", "noon", "meals",
        "meal", "with", "without", "before", "after", "at", "in", "on", "of", "the", "a", "an", "or", "for", "to", "per",
        "as", "needed", "every", "each", "other", "last", "taken", "take", "takes", "taking", "took", "held", "hold",
        "holding", "stopped", "stop", "started", "start", "since", "today", "yesterday", "tonight", "ago", "hours", "hour",
        "hrs", "hr", "h", "min", "mins", "er", "xr", "sr", "la", "cr", "xl", "ir", "dr", "ec", "od", "bd", "sliding",
        "scale", "ss", "chewable", "enteric", "coated", "extended", "release", "delayed", "immediate", "low", "high",
        "half", "full", "then", "until", "x", "via", "pump", "pen", "vial", "solution", "cream", "ointment", "gel",
        "drip", "infusion", "gtt", "mouth", "skin", "eye", "eyes", "both", "left", "right", "ou", "os", "ad", "lib",
        "and", "also", "plus", "but", "not", "no", "none", "denies", "occasional", "occasionally", "sometimes", "rarely",
        "usually", "dosing", "dosed", "unknown", "unsure", "same", "home", "meds", "med", "medication", "medications",
        "denied", "never", "nor", "stopping", "discontinued", "off", "quit", "paused", "longer", "compliance", "compliant",
        "noncompliance", "noncompliant", "adherence", "adherent", "did", "does", "do", "has", "have", "had", "was", "doesnt",
        "didnt", "dont", "hasnt", "havent", "isnt", "wasnt",
    ]

    /// Words that open a list and are dropped there ("Home meds:", "takes", "pt on").
    static let leadNoise: Set<String> = [
        "home", "meds", "med", "medication", "medications", "current", "list", "includes", "including", "takes", "taking",
        "take", "on", "also", "plus", "pt", "patient", "is", "uses", "using", "reports", "rx", "otc", "supplements",
        "herbals", "prescribed", "and",
    ]

    /// Endings of drug names, for a typed word after a dose ("metoprolol 25 xyzolol 10").
    static let drugEndings: [String] = [
        "pril", "sartan", "olol", "alol", "ilol", "statin", "dipine", "azole", "prazole", "tidine", "setron", "triptan",
        "gliptin", "gliflozin", "glutide", "glitazone", "xaban", "gatran", "parin", "grel", "mab", "tinib", "cillin",
        "mycin", "floxacin", "cycline", "navir", "gravir", "fovir", "clovir", "azepam", "zolam", "barbital", "oxetine",
        "ipramine", "triptyline", "afil", "dronate", "olone", "asone", "lukast", "terol", "tropium", "curium", "caine",
        "codone", "morphone", "semide", "thiazide", "tiazem", "pamil", "darone", "profen", "coxib", "apine", "idone",
        "azine", "etine",
    ]

    // MARK: Flags

    /// The flags a medication list raises: each item's entry by its catalog id, or by its name when that names an entry
    /// exactly.
    static func flags(for meds: [PatientMed]) -> Set<String> {
        meds.reduce(into: Set<String>()) { s, m in if let e = resolve(m) { s.formUnion(e.flags) } }
    }

    /// The flags a typed name raises ("Eliquis" → anticoagulant); none for a name the list does not know. For the note
    /// reader and quick add.
    static func flags(forName s: String) -> Set<String> { entry(named: s)?.flags ?? [] }

    /// An item's entry: by its catalog id, else by its name.
    static func resolve(_ m: PatientMed) -> MedEntry? {
        if let id = m.catalogID, let e = entry(id: id) { return e }
        return entry(named: m.name)
    }

    // MARK: Adding to the list

    /// The same drug: one entry, or the same name typed.
    static func same(_ a: PatientMed, _ b: PatientMed) -> Bool {
        if let x = resolve(a)?.id, let y = resolve(b)?.id { return x == y }
        let fa = CatalogText.fold(a.name).trimmingCharacters(in: .whitespaces), fb = CatalogText.fold(b.name).trimmingCharacters(in: .whitespaces)
        return !fa.isEmpty && fa == fb
    }

    /// How an item compares with the list: new, already there, or a new dose for one there.
    static func status(_ m: PatientMed, in list: [PatientMed]) -> PatientNoteStatus {
        guard let o = list.first(where: { same($0, m) }) else { return .new }
        let d = m.dose.trimmingCharacters(in: .whitespaces)
        let old = o.dose.trimmingCharacters(in: .whitespaces)
        if d.isEmpty || old.caseInsensitiveCompare(d) == .orderedSame { return .recorded }
        return old.isEmpty ? .new : .replaces(old)
    }

    /// Adds items to the list: a drug already there takes the new dose (one typed without a dose keeps its dose); a new
    /// drug is added.
    static func apply(_ items: [PatientMed], to list: inout [PatientMed]) {
        for m in items {
            if let i = list.firstIndex(where: { same($0, m) }) {
                let d = m.dose.trimmingCharacters(in: .whitespaces)
                if !d.isEmpty { list[i].dose = d }
                if list[i].catalogID == nil { list[i].catalogID = m.catalogID }
            } else {
                list.append(m)
            }
        }
    }

    /// Every drug in a list typed before 1.9 is on the item list already (so the typed text need not be shown too).
    static func covers(_ list: [PatientMed], legacy: String) -> Bool {
        let items = parse(legacy)
        return !items.isEmpty && items.allSatisfy { m in list.contains { same($0, m) } }
    }
}

/// One allergy (1.9): the allergen as picked or typed, its severity, and the reaction as typed.
struct PatientAllergy: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = ""
    /// "mild", "severe", "anaphylaxis"; nil not recorded.
    var severity: String?
    var reaction = ""

    init(id: UUID = UUID(), name: String = "", severity: String? = nil, reaction: String = "") {
        self.id = id; self.name = name; self.severity = severity; self.reaction = reaction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        severity = try? c.decodeIfPresent(String.self, forKey: .severity)
        reaction = (try? c.decodeIfPresent(String.self, forKey: .reaction)) ?? ""
    }

    static let severities: [(id: String, label: String)] = [("mild", "Mild"), ("severe", "Severe"), ("anaphylaxis", "Anaphylaxis")]

    /// "Penicillin (mild)", "Latex (anaphylaxis)".
    var text: String {
        let label = PatientAllergy.severities.first { $0.id == severity }?.label.lowercased()
        let extra = [label, reaction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reaction.trimmingCharacters(in: .whitespacesAndNewlines)].compactMap { $0 }
        return name + (extra.isEmpty ? "" : " (" + extra.joined(separator: ", ") + ")")
    }
}
