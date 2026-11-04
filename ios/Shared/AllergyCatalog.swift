import Foundation

// MARK: - Allergies as items (1.9, Ben's Wanted Changes)
//
// "No known allergies or +add medication (can add multiple) -> severity mild, severe, anaphylaxis." The + Add field
// finds an allergen in the medication list, in the drug classes people write ("PCN", "sulfa", "NSAIDs", "opioids"), in
// the drugs given around anesthesia, and in the common allergens that are not drugs (latex, chlorhexidine, iodinated
// contrast, adhesive tape, foods, insect stings). A line holds several: commas, semicolons and new lines separate them
// (not inside parentheses), and so does a space before an allergen the list knows ("PCN sulfa latex" is three). What
// follows an allergen is its reaction as typed ("PCN - rash", "sulfa (hives)"); a severity is read only when it is
// written: "mild", "severe", "anaphylaxis" (or "anaphylactic", "anaphylactoid"). "Hives" and "rash" are reactions and set
// no severity. A severity or an allergen after a word that denies it ("no anaphylaxis", "not allergic to latex",
// "tolerated cefazolin") is not recorded: the words stay in the reaction as typed. Nothing here gives advice about an
// allergen.

/// One allergen the + Add field knows.
struct AllergenEntry: Hashable, Identifiable {
    enum Kind: String, Hashable { case drugClass, drug, other }
    var id: String
    /// As the list shows it: "Penicillin", "Latex".
    var name: String
    var aliases: [String]
    var kind: Kind
    /// The line under it in the type-ahead: the medication's class, or what the allergen is.
    var detail: String
}

enum AllergyCatalog {
    /// "id|Name|aliases|kind|detail": the allergens that are not on the medication list, or read differently here (a
    /// class before a single drug: "penicillin" is the class).
    static let rows: [String] = [
        // Drug classes as written
        "penicillin|Penicillin|pcn, penicillins, penicillin class|class|Penicillins (drug class)",
        "cephalosporins|Cephalosporins|cephalosporin, cephs|class|Drug class",
        "carbapenems|Carbapenems|carbapenem|class|Drug class",
        "sulfa|Sulfa drugs|sulfa, sulfas, sulfa drug, sulfonamide, sulfonamides, sulfonamide antibiotics|class|Sulfonamide antibiotics (drug class)",
        "macrolides|Macrolides|macrolide|class|Drug class",
        "fluoroquinolones|Fluoroquinolones|fluoroquinolone, quinolones, quinolone|class|Drug class",
        "tetracyclines|Tetracyclines|tetracycline class|class|Drug class",
        "aminoglycosides|Aminoglycosides|aminoglycoside|class|Drug class",
        "nsaids|NSAIDs|nsaid, anti-inflammatories, nonsteroidal anti-inflammatory drugs|class|Drug class",
        "opioids|Opioids|opioid, opiates, opiate, narcotics, narcotic|class|Drug class",
        "ace-inhibitors|ACE inhibitors|ace inhibitor, acei, ace-i|class|Drug class",
        "statins|Statins|statin|class|Drug class",
        "local-anesthetics|Local anesthetics|local anesthetic, local anaesthetics, local anaesthetic, novocaine|class|Drug class",
        "ester-local-anesthetics|Ester local anesthetics|ester local anesthetic, ester anesthetics, paba|class|Drug class (procaine, chloroprocaine, tetracaine, benzocaine)",
        "amide-local-anesthetics|Amide local anesthetics|amide local anesthetic, amide anesthetics|class|Drug class (lidocaine, bupivacaine, ropivacaine, mepivacaine)",
        "nmb|Neuromuscular blocking agents|neuromuscular blockers, neuromuscular blocking drugs, nmba, nmbas, paralytics, paralytic|class|Drug class",
        "antiepileptics|Anticonvulsants|anticonvulsant, antiepileptics, antiepileptic, aeds|class|Drug class",
        // Drugs given around anesthesia (not home medications)
        "propofol|Propofol|diprivan|drug|Anesthetic",
        "succinylcholine|Succinylcholine|sux, anectine, quelicin, suxamethonium|drug|Depolarizing neuromuscular blocker",
        "rocuronium|Rocuronium|roc, zemuron|drug|Nondepolarizing neuromuscular blocker",
        "vecuronium|Vecuronium|vec|drug|Nondepolarizing neuromuscular blocker",
        "cisatracurium|Cisatracurium|nimbex|drug|Nondepolarizing neuromuscular blocker",
        "atracurium|Atracurium||drug|Nondepolarizing neuromuscular blocker",
        "sugammadex|Sugammadex|bridion|drug|Reversal agent",
        "neostigmine|Neostigmine|bloxiverz|drug|Cholinesterase inhibitor (reversal agent)",
        "midazolam|Midazolam|versed|drug|Benzodiazepine",
        "etomidate|Etomidate|amidate|drug|Anesthetic",
        "ketamine|Ketamine|ketalar|drug|Anesthetic",
        "dexmedetomidine|Dexmedetomidine|precedex|drug|Sedative (alpha-2 agonist)",
        "remifentanil|Remifentanil|ultiva|drug|Opioid",
        "sufentanil|Sufentanil|sufenta|drug|Opioid",
        "lidocaine|Lidocaine|xylocaine|drug|Amide local anesthetic",
        "bupivacaine|Bupivacaine|marcaine, sensorcaine, exparel|drug|Amide local anesthetic",
        "ropivacaine|Ropivacaine|naropin|drug|Amide local anesthetic",
        "mepivacaine|Mepivacaine|carbocaine, polocaine|drug|Amide local anesthetic",
        "chloroprocaine|Chloroprocaine|nesacaine, clorotekal|drug|Ester local anesthetic",
        "tetracaine|Tetracaine|pontocaine|drug|Ester local anesthetic",
        "benzocaine|Benzocaine|hurricaine, cetacaine|drug|Ester local anesthetic",
        "procaine|Procaine||drug|Ester local anesthetic",
        "protamine|Protamine||drug|Heparin reversal",
        "gentamicin|Gentamicin|garamycin|drug|Aminoglycoside antibiotic",
        "tobramycin|Tobramycin|tobrex|drug|Aminoglycoside antibiotic",
        "contrast|Iodinated contrast|contrast, iv contrast, ct contrast, contrast dye, iv dye, ct dye, iodinated contrast media, contrast media, omnipaque, visipaque, isovue, iohexol, iodixanol, iopamidol|other|Contrast medium",
        "gadolinium|Gadolinium contrast|gadolinium, mri contrast, mri dye|other|Contrast medium",
        "isosulfan-blue|Isosulfan blue dye|blue dye, isosulfan blue, lymphazurin|other|Dye",
        "povidone-iodine|Povidone-iodine|betadine, iodine, povidone iodine|other|Antiseptic",
        "chlorhexidine|Chlorhexidine|chg, hibiclens, chloraprep, peridex|other|Antiseptic",
        // Not drugs
        "latex|Latex|natural rubber latex, rubber, latex gloves|other|Natural rubber latex",
        "adhesive|Adhesive tape|tape, adhesive, adhesives, medical adhesive, medical tape, tegaderm, steri-strips, bandaids|other|Adhesive",
        "egg|Egg|eggs|other|Food",
        "soy|Soy|soybean, soybeans, soya|other|Food",
        "peanut|Peanut|peanuts|other|Food",
        "tree-nuts|Tree nuts|tree nut, nuts, almonds, walnuts, cashews, pecans|other|Food",
        "shellfish|Shellfish|shrimp, crab, lobster, seafood, shellfish allergy|other|Food",
        "fish|Fish||other|Food",
        "milk|Milk|dairy, cows milk|other|Food",
        "wheat|Wheat||other|Food",
        "sesame|Sesame||other|Food",
        "sulfites|Sulfites|sulfite, metabisulfite, sodium metabisulfite|other|Food and drug preservative",
        "gelatin|Gelatin||other|Food and drug ingredient",
        "insect-stings|Insect stings|bee stings, bee sting, bees, wasps, wasp, insect venom, hymenoptera, yellow jackets|other|Venom",
        "nickel|Nickel||other|Metal",
        "blood-products|Blood products|blood transfusion, transfusion, transfusions|other|Transfusion",
    ]

    private static let own: [AllergenEntry] = rows.compactMap { s in
        let f = s.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard f.count == 5 else { return nil }
        let kind: AllergenEntry.Kind = f[3] == "class" ? .drugClass : (f[3] == "drug" ? .drug : .other)
        return AllergenEntry(id: f[0], name: f[1], aliases: f[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                             kind: kind, detail: f[4])
    }

    /// The allergens: the list above first, then every medication (its class as the detail). A medication with the
    /// same name as one above is left out.
    static let entries: [AllergenEntry] = {
        var out = own
        var names = Set(own.map { CatalogText.fold($0.name) })
        for m in MedicationCatalog.entries where !m.name.hasSuffix("not named)") && names.insert(CatalogText.fold(m.name)).inserted {
            out.append(AllergenEntry(id: "med:" + m.id, name: m.name, aliases: m.aliases, kind: .drug, detail: m.drugClass))
        }
        return out
    }()

    static let phrases = CatalogPhrases(forms: CatalogPhrases.forms(entries.map { (name: $0.name, aliases: $0.aliases) }))

    private static let classIndex: Set<Int> = Set(entries.indices.filter { !entries[$0].id.hasPrefix("med:") })

    static func entry(id: String) -> AllergenEntry? { entries.first { $0.id == id } }

    // MARK: Search

    struct Hit: Hashable {
        var entry: AllergenEntry
        var matched: String?
    }

    /// The allergens a typed prefix finds, best first: the classes and the allergens above before single medications.
    static func search(_ q: String, limit: Int = 8) -> [AllergenEntry] { hits(q, limit: limit).map(\.entry) }

    static func hits(_ q: String, limit: Int = 8) -> [Hit] {
        phrases.search(q, limit: limit) { classIndex.contains($0) ? 1 : 0 }.map { h in
            let p = phrases.phrases[h.phrase]
            return Hit(entry: entries[h.entry], matched: p.isName ? nil : p.text)
        }
    }

    struct Suggestion: Hashable {
        var hit: Hit
        var replaces: Range<String.Index>
        func completing(_ line: String) -> String { line.replacingCharacters(in: replaces, with: hit.entry.name + " ") }
    }

    /// The type-ahead for the allergen being typed at the end of the line (not for a reaction being typed after one).
    static func typeahead(_ line: String, limit: Int = 5) -> [Suggestion] {
        guard let last = line.last, last.isLetter || last.isNumber else { return [] }
        let ws = CatalogText.words(line)
        guard !ws.isEmpty, ws[ws.count - 1].range.upperBound == line.endIndex else { return [] }
        let br = CatalogText.breaks(line, ws)
        let segStart = ws.indices.last(where: { br[$0] }) ?? 0
        // An allergen already in this item: the next word is likely its reaction ("PCN - ra" is not ramipril).
        let allergenBefore = (segStart..<(ws.count - 1)).contains(where: { phrases.longest(ws, at: $0) != nil })
        var out: [Suggestion] = []
        for n in stride(from: min(3, ws.count - segStart), through: 1, by: -1) {
            let start = ws.count - n
            let w = ws[start]
            guard w.isLetters, w.key.count >= 2, !lead.contains(w.key), !reactionWords.contains(w.key), severity(w.key) == nil else { continue }
            if n == 1, allergenBefore, reactionWords.contains(where: { $0.hasPrefix(w.key) }) { continue }
            let q = String(line[w.range.lowerBound...])
            for h in hits(q, limit: limit) where !out.contains(where: { $0.hit.entry.id == h.entry.id }) {
                out.append(Suggestion(hit: h, replaces: w.range.lowerBound..<line.endIndex))
            }
            if out.count >= limit { break }
        }
        if out.count == 1, let s = out.first, phrases.exact(String(line[s.replaces])).map({ entries[$0].id }) == s.hit.entry.id { return [] }
        return Array(out.prefix(limit))
    }

    // MARK: Reading a line

    /// "NKDA", "NKA", "no known allergies", "none".
    static func isNone(_ line: String) -> Bool {
        let t = CatalogText.words(line).map(\.key).joined(separator: " ")
        return ["nkda", "nka", "nkfa", "none", "nil", "no allergies", "no known allergies", "no known drug allergies",
                "no known drug allergy", "no known allergy", "denies allergies", "denies"].contains(t)
    }

    /// A line of several allergies, as items.
    static func parse(_ line: String) -> [PatientAllergy] { read(line).map(\.allergy) }

    struct ReadItem: Hashable {
        var allergy: PatientAllergy
        var typed: Bool
        var nameRange: Range<String.Index>
    }

    /// As `parse`, with a word still being typed at the end left out when the list does not know it yet.
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
            var reaction: [[Int]] = [[]]
            var severity: String?
        }
        guard !isNone(line) else { return [] }
        let ws = CatalogText.words(line)
        let br = CatalogText.breaks(line, ws)
        var out: [Building] = []
        var inSegment = 0
        var pendingSeverity: String?
        var orphan: [Int] = []
        var afterAnd = false

        // A segment with only a reaction or a severity ("PCN - rash, hives"): it belongs to the item before.
        func closeSegment() {
            if inSegment == 0, !out.isEmpty {
                if !orphan.isEmpty { out[out.count - 1].reaction.append(orphan) }
                if let s = pendingSeverity { out[out.count - 1].severity = s }
            }
            orphan = []
            pendingSeverity = nil
            inSegment = 0
            afterAnd = false
        }

        /// A word of the last item's reaction.
        func addReaction(_ i: Int) {
            let k = out.count - 1
            let g = out[k].reaction.count - 1
            out[k].reaction[g].append(i)
        }

        var i = 0
        while i < ws.count {
            if br[i] { closeSegment() }
            let w = ws[i]
            // "no anaphylaxis", "not allergic to latex", "tolerated cefazolin": neither a severity nor an allergy, but
            // words of the reaction (or of the item before, at the start of a segment).
            if negations.contains(w.key), let end = negatedEnd(ws, br, from: i) {
                for k in i..<end {
                    if inSegment > 0 { addReaction(k) } else { orphan.append(k) }
                }
                i = end
                continue
            }
            if let s = severity(w.key) {
                if inSegment > 0 { out[out.count - 1].severity = s } else { pendingSeverity = s }
                i += 1
                continue
            }
            if w.key == "and" || w.key == "or" {
                afterAnd = true
                i += 1
                continue
            }
            if let m = phrases.longest(ws, at: i) {
                if inSegment > 0, out.last?.entry == m.entry, !afterAnd {
                    i += m.count
                    continue
                }
                out.append(Building(entry: m.entry, nameRange: w.range.lowerBound..<ws[i + m.count - 1].range.upperBound, severity: pendingSeverity))
                pendingSeverity = nil
                inSegment += 1
                afterAnd = false
                i += m.count
                continue
            }
            if lead.contains(w.key) && (inSegment == 0 || out[out.count - 1].reaction.allSatisfy(\.isEmpty)) {
                i += 1
                continue
            }
            let reaction = reactionWords.contains(w.key)
            if inSegment == 0 || (afterAnd && !reaction) {
                if reaction || !w.key.first!.isLetter {
                    if inSegment == 0 { orphan.append(i) } else { addReaction(i) }
                    i += 1
                    continue
                }
                // A typed allergen: this word and the next ones up to a reaction word, a dash or a parenthesis.
                var j = i + 1
                while j < ws.count, j - i < 4, !br[j], phrases.longest(ws, at: j) == nil, !reactionWords.contains(ws[j].key),
                      severity(ws[j].key) == nil, !lead.contains(ws[j].key), !negations.contains(ws[j].key), ws[j].key != "and", ws[j].key != "or",
                      !line[ws[j - 1].range.upperBound..<ws[j].range.lowerBound].contains(where: { "-–—:(=".contains($0) }) {
                    j += 1
                }
                out.append(Building(entry: nil, nameRange: w.range.lowerBound..<ws[j - 1].range.upperBound, severity: pendingSeverity))
                pendingSeverity = nil
                inSegment += 1
                afterAnd = false
                i = j
                continue
            }
            addReaction(i)
            i += 1
        }
        closeSegment()

        return out.map { b in
            let reaction = b.reaction.filter { !$0.isEmpty }.map { CatalogText.text(line, runs: CatalogText.runs(line, ws, $0), separator: ", ") }
                .filter { !$0.isEmpty }.joined(separator: ", ")
            let name = b.entry.map { entries[$0].name } ?? FreeText.cap(String(line[b.nameRange]))
            return ReadItem(allergy: PatientAllergy(name: name, severity: b.severity, reaction: reaction), typed: b.entry == nil, nameRange: b.nameRange)
        }
    }

    /// Words that deny the severity or the allergen after them: "no anaphylaxis", "not allergic to latex", "tolerated
    /// cefazolin", "non-anaphylactic".
    static let negations: Set<String> = ["no", "not", "never", "non", "nor", "without", "denies", "denied", "negative",
                                         "tolerated", "tolerates", "tolerate", "tolerating", "tolerant"]

    /// After a denying word at `i`: the end of the severity or the allergen it denies, with the words between ("not
    /// allergic to", "never had") and an "allergy" after; nil when no severity or allergen follows in the same item.
    private static func negatedEnd(_ ws: [CatalogWord], _ br: [Bool], from i: Int) -> Int? {
        let between: Set<String> = lead.union(["had", "any", "true", "real", "an", "a"])
        var k = i + 1
        while k < ws.count, !br[k], between.contains(ws[k].key) { k += 1 }
        guard k < ws.count, !br[k] else { return nil }
        var end: Int
        if severity(ws[k].key) != nil {
            end = k + 1
        } else if let m = phrases.longest(ws, at: k), !(k + 1..<k + m.count).contains(where: { br[$0] }) {
            end = k + m.count
        } else {
            return nil
        }
        let after: Set<String> = ["allergy", "allergies", "allergic", "reaction", "reactions", "sensitivity"]
        while end < ws.count, !br[end], after.contains(ws[end].key) { end += 1 }
        return end
    }

    /// "mild", "severe", "anaphylaxis" as written.
    static func severity(_ w: String) -> String? {
        switch w {
        case "mild": return "mild"
        case "severe": return "severe"
        case "anaphylaxis", "anaphylactic", "anaphylactoid", "anaphylaxsis", "anaphalaxis": return "anaphylaxis"
        default: return nil
        }
    }

    /// Words around an allergen that are neither it nor its reaction.
    static let lead: Set<String> = ["allergy", "allergies", "allergic", "allergen", "to", "reaction", "reactions", "rxn",
                                    "causes", "caused", "gives", "gave", "with", "of", "hx", "history", "pt", "patient",
                                    "is", "has", "reports", "states", "known", "a", "an", "the", "sensitivity"]

    /// Reaction words: they end a typed allergen's name and never start one.
    static let reactionWords: Set<String> = [
        "rash", "rashes", "hives", "urticaria", "itch", "itching", "itchy", "pruritus", "swelling", "swollen", "angioedema",
        "edema", "nausea", "vomiting", "emesis", "diarrhea", "gi", "upset", "stomach", "sob", "dyspnea", "wheeze",
        "wheezing", "bronchospasm", "hypotension", "hypotensive", "shock", "throat", "tongue", "lip", "lips", "face",
        "facial", "closing", "blisters", "blistering", "sjs", "stevens", "johnson", "dress", "flushing", "redness", "red",
        "palpitations", "tachycardia", "bradycardia", "headache", "dizziness", "dizzy", "confusion", "hallucinations",
        "delirium", "seizure", "seizures", "cough", "myalgia", "myalgias", "intolerance", "intolerant", "unknown",
        "jittery", "anxiety", "drowsy", "sedation", "respiratory", "depression", "arrest", "eczema", "dermatitis",
        "contact", "burning", "tingling", "numbness", "thrombocytopenia", "hit", "fever", "chills", "agitation",
        "weakness", "jaundice", "hepatitis", "aki", "nephritis", "neutropenia", "anemia", "bleeding", "pancreatitis",
        "serum", "sickness", "difficulty", "breathing", "trouble", "chest", "pain", "tightness", "moderate", "life",
        "threatening", "rigidity", "hyperthermia", "mh", "syndrome", "man", "flush", "sick", "nauseous", "vomit",
        "vomited", "swelled", "hive", "welts", "anxious", "insomnia", "cramps", "cramping", "rhinitis", "sneezing",
        "watery", "conjunctivitis", "hoarseness",
    ]

    // MARK: Adding to the list

    static func same(_ a: PatientAllergy, _ b: PatientAllergy) -> Bool {
        let fa = CatalogText.fold(a.name).trimmingCharacters(in: .whitespaces), fb = CatalogText.fold(b.name).trimmingCharacters(in: .whitespaces)
        if !fa.isEmpty, fa == fb { return true }
        guard let x = phrases.exact(a.name), let y = phrases.exact(b.name) else { return false }
        return x == y
    }

    /// New, already listed, or adding a severity or reaction to one listed.
    static func status(_ a: PatientAllergy, in list: [PatientAllergy]) -> PatientNoteStatus {
        guard let o = list.first(where: { same($0, a) }) else { return .new }
        let r = a.reaction.trimmingCharacters(in: .whitespaces)
        let sameSeverity = a.severity == nil || a.severity == o.severity
        let sameReaction = r.isEmpty || o.reaction.caseInsensitiveCompare(r) == .orderedSame
        if sameSeverity && sameReaction { return .recorded }
        return o.severity == nil && o.reaction.isEmpty ? .new : .replaces(o.text)
    }

    /// Adds items to the list: one already there takes a severity or reaction that was typed; a new one is added.
    static func apply(_ items: [PatientAllergy], to list: inout [PatientAllergy]) {
        for a in items {
            if let i = list.firstIndex(where: { same($0, a) }) {
                if let s = a.severity { list[i].severity = s }
                let r = a.reaction.trimmingCharacters(in: .whitespaces)
                if !r.isEmpty { list[i].reaction = r }
            } else {
                list.append(a)
            }
        }
    }

    /// Every allergy typed before 1.9 is on the list already, with its severity and reaction: a typed "PCN -
    /// anaphylaxis" is not covered by a listed "Penicillin (mild)", so it still shows.
    static func covers(_ list: [PatientAllergy], legacy: String) -> Bool {
        let items = parse(legacy)
        return !items.isEmpty && items.allSatisfy { a in
            if case .recorded = status(a, in: list) { return true }
            return false
        }
    }
}

/// The allergies as the summary, the handoff and the Allergies box show them (1.9): the list, or the allergies typed
/// before 1.9 split at their commas and semicolons while the list does not hold them. The typed text is never changed
/// here; "Convert to list" in the Allergies box does that, by the user's choice.
enum PatientAllergyText {
    struct Item: Hashable {
        var text: String
        /// Anaphylaxis recorded (or written, in the typed text): shown in red.
        var anaphylaxis: Bool
        /// From the allergies typed before 1.9.
        var legacy: Bool
    }

    static func items(_ r: PatientRecord) -> [Item] {
        let c = r.capitalized
        var out = c.allergyList.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { Item(text: $0.text, anaphylaxis: $0.severity == "anaphylaxis", legacy: false) }
        let typed = c.allergies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty, out.isEmpty || !AllergyCatalog.covers(r.allergyList, legacy: r.allergies) {
            out += pieces(typed).map { Item(text: $0, anaphylaxis: $0.range(of: "anaphyla", options: .caseInsensitive) != nil, legacy: true) }
        }
        return out
    }

    /// "Penicillin (rash, hives); latex" → "Penicillin (rash, hives)", "Latex".
    static func pieces(_ s: String) -> [String] {
        var out: [String] = []
        var item = ""
        var depth = 0
        for ch in s {
            if ch == "(" || ch == "[" { depth += 1 } else if (ch == ")" || ch == "]") && depth > 0 { depth -= 1 }
            if depth == 0 && (ch == "," || ch == ";" || ch == "\n") {
                out.append(item)
                item = ""
            } else {
                item.append(ch)
            }
        }
        out.append(item)
        return out.map { FreeText.cap($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.filter { !$0.isEmpty }
    }

    /// The summary's line: "Penicillin (mild); Latex (anaphylaxis)", anaphylaxis in red; no known allergies; or nil.
    /// Without a list it reads as before 1.9: No known drug allergies when ticked, else the allergies as typed.
    static func line(_ r: PatientRecord) -> PatientSummary.Line? {
        let typed = r.capitalized.allergies.trimmingCharacters(in: .whitespacesAndNewlines)
        let listed = items(r).filter { !$0.legacy }
        if listed.isEmpty {
            if r.nkda { return PatientSummary.Line("Allergies", "No known drug allergies") }
            guard !typed.isEmpty else { return nil }
            return PatientSummary.Line("Allergies", typed, alert: true, marks: pieces(typed).filter { $0.range(of: "anaphyla", options: .caseInsensitive) != nil })
        }
        var text = listed.map(\.text).joined(separator: "; ")
        if !typed.isEmpty, !AllergyCatalog.covers(r.allergyList, legacy: r.allergies) { text += "; " + typed }
        return PatientSummary.Line("Allergies", text, alert: true, marks: listed.filter(\.anaphylaxis).map(\.text))
    }
}
