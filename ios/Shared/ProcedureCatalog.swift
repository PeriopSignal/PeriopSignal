import Foundation

// MARK: - Procedure catalog
//
// A built-in, offline list of common surgical and procedural cases. My Patient uses it to read the planned
// procedure(s) from what the user types (abbreviations included) and to auto-fill the risk inputs the record already
// has: the planned anesthetic, RCRI high-risk surgery, and the ARISCAT incision and duration.
//
// RCRI high-risk surgery: "intraperitoneal, intrathoracic, or suprainguinal vascular procedures" (Lee TH et al.
// Circulation 1999;100:1043–1049, Table 1 and Results; the paper adds no further definition and does not mention
// laparoscopy). Rules applied here:
//   - intraperitoneal means the peritoneal cavity is entered, by laparotomy, laparoscopy or robot (laparoscopic
//     intraperitoneal surgery counts), from the abdomen or the vagina (cesarean delivery and hysterectomy by any
//     route count; a totally extraperitoneal hernia repair, a flank nephrectomy and a kidney transplant do not);
//   - intrathoracic means the chest is opened by sternotomy, thoracotomy, thoracoscopy or robot;
//   - suprainguinal vascular means open or endovascular repair of the aorta, and open reconstruction of the iliac,
//     visceral or renal arteries; carotid surgery and percutaneous angioplasty or stenting do not count;
//   - transcatheter heart procedures (TAVR through the femoral artery, TEER) are neither intrathoracic nor
//     high-risk, and cardiac cases set `cardiac`, where the app hides the RCRI.
//
// ARISCAT incision and duration: Canet J et al. Anesthesiology 2010;113:1338–1350 (Tables 5 and 6). The incision has
// three categories, peripheral (0 points), upper abdominal (15) and intrathoracic (24), and every one of the 2,464
// patients fell into one of them (2,013 peripheral, 361 upper abdominal, 90 intrathoracic), so any site that is not
// upper abdominal or intrathoracic scores as peripheral. The duration has three: ≤ 2 h (0), > 2 to 3 h (16) and
// > 3 h (23). The paper's text names no further definitions (they sit in its Supplemental Digital Content 1) and does
// not mention laparoscopy. The PERISCOPE cohort that externally validated the score (Mazo V et al. Anesthesiology
// 2014;121:219–231) was later split into open and closed (laparoscopic or thoracoscopic) operations for a separate
// respiratory-failure score (Canet J et al. Eur J Anaesthesiol 2015;32:458–470: peripheral and other 72.8%, closed
// intrathoracic or upper abdominal 12.7%, open upper abdominal 9.8%, open intrathoracic 4.7%); the closed and open
// groups together match the upper abdominal and intrathoracic share in the validation, and the open/closed split
// belongs to that later score only. So, as applied here:
//   - Intrathoracic: the chest is entered, open or thoracoscopic or robotic, including sternotomy and mediastinal
//     surgery;
//   - Upper abdominal: open, laparoscopic or robotic surgery on the upper abdominal organs (esophagus from below,
//     stomach, duodenum, liver, bile ducts, pancreas, spleen, adrenal, kidney), any colectomy, a midline laparotomy
//     (which runs above the umbilicus), ventral hernia repair, and flank or subcostal incisions;
//   - Peripheral: everything else, which includes the head and the neck (thyroid, carotid, anterior cervical spine,
//     tracheostomy), the limbs, the back and spine, the breast and chest wall without entering the chest, lower
//     abdominal and pelvic surgery through a low transverse, groin, perineal or vaginal incision and pelvic
//     laparoscopy (cesarean, hysterectomy, prostatectomy, inguinal hernia, appendectomy), and endoscopic,
//     transurethral and catheter procedures.
//
// Durations are typical operating-time estimates for the auto-fill, and the anesthetic is the usual plan; the
// clinician can change both. Several procedures together: high risk if any is; the most serious incision; the longest
// duration, raised one step when two or more procedures each take over 2 h (a bilateral case of a sided procedure
// counts twice); general anesthesia whenever any procedure needs it (with the epidural or block that procedure's own
// plan pairs with it), otherwise the union of the plans. There are no CPT codes or descriptors here.

struct Procedure: Hashable, Identifiable {
    var id: String
    /// Display name, sentence case ("Laparoscopic cholecystectomy").
    var name: String
    var specialty: String
    /// Abbreviations and common names, matched ignoring case, hyphens and plurals; the ones in `caseSensitive` are
    /// listed here too but match only with their exact case.
    var synonyms: [String]
    /// The usual plan: "ga", "mac", "neuraxial", "regional".
    var anesthetic: Set<String>
    /// RCRI: intraperitoneal, intrathoracic or suprainguinal vascular.
    var highRisk: Bool
    /// ARISCAT: "Peripheral", "Upper abdominal" or "Intrathoracic".
    var incision: String
    /// ARISCAT: "≤ 2 h", "> 2–3 h" or "> 3 h".
    var duration: String
    /// The side must be asked (limbs, eyes, ears, breast, kidney, hernia, carotid, lung resection...).
    var lateral: Bool
    /// Cardiac surgery, where the app hides the RCRI.
    var cardiac: Bool
    /// Echo findings shown up front: liver and lung transplant, cardiac surgery, major aortic surgery.
    var echoFirst: Bool
    /// Forms whose case changes the meaning ("AVr" is a repair, "AVR" a replacement).
    var caseSensitive: [String]

    /// True when the procedure has a side and none was given.
    func needsSide(_ side: String?) -> Bool { lateral && (side ?? "").isEmpty }

    /// "Left total knee arthroplasty"; the name alone without a side.
    func displayName(side: String?) -> String {
        guard let side, !side.isEmpty else { return name }
        return side.capitalized + " " + ProcedureCatalog.lowerFirst(name)
    }
}

/// One procedure read from free text, with its side and where it was found.
struct ProcedureMatch: Hashable {
    var procedure: Procedure
    /// "left", "right", "bilateral" or nil.
    var side: String?
    /// The matched words (and an attached side word) in the text that was parsed.
    var range: Range<String.Index>
    var text: String

    var needsSide: Bool { procedure.needsSide(side) }
    var displayName: String { procedure.displayName(side: side) }
}

/// The risk inputs several procedures add up to.
struct ProcedureRisk: Hashable {
    var anesthetic: Set<String> = []
    var highRisk = false
    var incision: String?
    var duration: String?
    var cardiac = false
    var echoFirst = false

    /// Writes the planned anesthetic, RCRI surgery and ARISCAT incision and duration into the record.
    func apply(to r: inout PatientRecord) {
        r.anesthetic = anesthetic
        r.highRiskSurgery = highRisk
        r.incision = incision
        r.duration = duration
    }
}

fileprivate struct ProcToken {
    /// As typed.
    var original: String
    /// Folded (lowercase, no accents or apostrophes) and singular.
    var raw: String
    /// `raw` with spelling aliases ("lap" → "laparoscopic", "caesarean" → "cesarean").
    var key: String
    var range: Range<String.Index>
}

fileprivate struct ProcPhrase {
    var key: [String]
    var raw: [String]
    /// The exact tokens of a case-sensitive form.
    var exact: [String]?
    var proc: Int
    /// A side the form itself names ("BMT" is bilateral).
    var side: String?
    var isName: Bool
}

enum ProcedureCatalog {
    static let incisions = ["Peripheral", "Upper abdominal", "Intrathoracic"]
    static let durations = ["≤ 2 h", "> 2–3 h", "> 3 h"]
    static let sides = ["left", "right", "bilateral"]

    static let all: [Procedure] = sections.flatMap { $0 }

    static func byID(_ id: String) -> Procedure? { idTable[id] }
    private static let idTable: [String: Procedure] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    // MARK: Search

    /// Ranked: an exact abbreviation or name, then a match at the start of a name or synonym, then a word inside
    /// one starting with what was typed; ties go to the earlier word, then to catalog order (the common procedures of
    /// each specialty come first). Only when nothing matches that way, a word containing what was typed.
    static func search(_ query: String, limit: Int = 12) -> [Procedure] {
        let q = tokenize(query)
        guard !q.isEmpty, limit > 0 else { return [] }
        let qKey = q.map(\.key)
        let qOrig = q.map(\.original)
        let words = q.filter { !stopWords.contains($0.raw) }
        let qRaw = words.map(\.raw)
        // Only procedures with a word starting with each typed word (as typed or by its alias) can match by prefix.
        var candidates: Set<Int>?
        for w in words {
            let hit = Set(prefixIndex[w.raw] ?? []).union(prefixIndex[w.key] ?? [])
            candidates = candidates.map { $0.intersection(hit) } ?? hit
        }
        let procs = candidates.map { $0.sorted() } ?? Array(all.indices)

        var best: [Int: (score: Int, pos: Int, name: Bool)] = [:]
        func keep(_ ph: ProcPhrase, _ score: Int, _ pos: Int) {
            if let b = best[ph.proc] {
                if score > b.score || (score == b.score && (pos < b.pos || (pos == b.pos && ph.isName && !b.name))) {
                    best[ph.proc] = (score, pos, ph.isName)
                }
            } else {
                best[ph.proc] = (score, pos, ph.isName)
            }
        }
        for i in procs {
            for pi in phrasesByProc[i] {
                let ph = phrases[pi]
                if let ex = ph.exact {
                    if ex == qOrig { keep(ph, 1000, 0) }
                } else if ph.key == qKey {
                    keep(ph, 900, 0)
                } else if !qRaw.isEmpty, startsWith(qRaw, ph.raw) {
                    // A whole word ("hip replacement") before a longer one that starts the same ("HIPEC").
                    keep(ph, ph.raw[qRaw.count - 1] == qRaw[qRaw.count - 1] ? 750 : 700, 0)
                } else if !qRaw.isEmpty, let p = wordPosition(qRaw, ph.raw, prefix: true) {
                    keep(ph, qRaw.allSatisfy { ph.raw.contains($0) } ? 550 : 500, p)
                }
            }
        }
        if best.isEmpty && !qRaw.isEmpty {
            for ph in phrases where ph.exact == nil {
                if let p = wordPosition(qRaw, ph.raw, prefix: false) { keep(ph, 200, p) }
            }
        }
        let ranked = best.sorted { a, b in
            if a.value.score != b.value.score { return a.value.score > b.value.score }
            if a.value.pos != b.value.pos { return a.value.pos < b.value.pos }
            return a.key < b.key
        }
        return ranked.prefix(limit).map { all[$0.key] }
    }

    private static let stopWords: Set<String> = ["of", "the", "with", "for", "to", "in", "on", "under"]

    /// Each typed word starts the phrase word at the same place, from the first.
    private static func startsWith(_ q: [String], _ p: [String]) -> Bool {
        guard q.count <= p.count else { return false }
        for i in 0..<q.count where !p[i].hasPrefix(q[i]) { return false }
        return true
    }

    /// Every typed word starts (or, with `prefix` false, is found inside) some word of the phrase; the position of
    /// the first typed word's match.
    private static func wordPosition(_ q: [String], _ p: [String], prefix: Bool) -> Int? {
        var first: Int?
        for (n, w) in q.enumerated() {
            if !prefix && w.count < 3 { return nil }
            guard let i = p.firstIndex(where: { prefix ? $0.hasPrefix(w) : $0.contains(w) }) else { return nil }
            if n == 0 { first = i }
        }
        return first
    }

    // MARK: Parse

    /// Reads one or several procedures from free text ("CABG x3 + AVR", "left TKA", "lap chole and ERCP"), longest
    /// phrase first, with the side written next to each one (left, right, bilateral, L, R, lt, rt, bilat, b/l, and
    /// OD, OS, OU for the eyes); a side is kept only for a procedure that has one.
    static func parse(_ text: String) -> [ProcedureMatch] {
        let toks = tokenize(text)
        guard !toks.isEmpty else { return [] }

        // Longest phrase at each position; a case-sensitive form beats a case-insensitive one of the same length.
        var hits: [(phrase: Int, start: Int, end: Int)] = []
        var i = 0
        while i < toks.count {
            var best: (phrase: Int, len: Int, exact: Bool)?
            for pi in firstToken[toks[i].key] ?? [] {
                let ph = phrases[pi]
                let n = ph.key.count
                guard i + n <= toks.count else { continue }
                var ok = true
                for k in 0..<n {
                    if let ex = ph.exact {
                        if toks[i + k].original != ex[k] { ok = false; break }
                    } else if toks[i + k].key != ph.key[k] {
                        ok = false; break
                    }
                }
                guard ok else { continue }
                let isExact = ph.exact != nil
                if let b = best {
                    if n > b.len || (n == b.len && isExact && !b.exact) { best = (pi, n, isExact) }
                } else {
                    best = (pi, n, isExact)
                }
            }
            if let b = best {
                // The same procedure written twice in a row ("ESS/FESS") is one.
                if let last = hits.last, phrases[last.phrase].proc == phrases[b.phrase].proc, last.end == i,
                   text[toks[i - 1].range.upperBound..<toks[i].range.lowerBound].allSatisfy({ $0.isWhitespace || $0 == "/" }) {
                    hits[hits.count - 1].end = i + b.len
                } else {
                    hits.append((b.phrase, i, i + b.len))
                }
                i += b.len
            } else {
                i += 1
            }
        }
        guard !hits.isEmpty else { return [] }

        var inHit = Set<Int>()
        for h in hits { for k in h.start..<h.end { inHit.insert(k) } }
        func sideAt(_ k: Int) -> String? {
            guard k >= 0, k < toks.count, !inHit.contains(k) else { return nil }
            return sideWords[toks[k].key]
        }
        func gapIsClean(_ a: Int, _ b: Int, _ allowed: Set<Character>) -> Bool {
            text[toks[a].range.upperBound..<toks[b].range.lowerBound].allSatisfy { $0.isWhitespace || allowed.contains($0) }
        }
        let before: Set<Character> = ["(", ")", "[", "]", ".", "-", ":"]
        let after: Set<Character> = ["(", ")", "[", "]", ".", "-", "–", "—", ":", ","]

        var found = [Set<String>](repeating: [], count: hits.count)
        var lo = hits.map(\.start)
        var hi = hits.map { $0.end - 1 }
        var claimed = Set<Int>()
        // A side word just before a procedure belongs to it ("left TKA", "R. THA", "left and right TKA").
        for (h, hit) in hits.enumerated() {
            let k = hit.start - 1
            guard let s = sideAt(k), gapIsClean(k, hit.start, before) else { continue }
            found[h].insert(s); claimed.insert(k); lo[h] = k
            if let s2 = sideAt(k - 2), toks[k - 1].key == "and" || toks[k - 1].key == "or" {
                found[h].insert(s2); claimed.insert(k - 2); lo[h] = k - 2
            }
        }
        // Otherwise one just after it ("TKA, left", "THA (R)").
        for (h, hit) in hits.enumerated() {
            let k = hit.end
            guard !claimed.contains(k), let s = sideAt(k), gapIsClean(hit.end - 1, k, after) else { continue }
            found[h].insert(s); claimed.insert(k); hi[h] = k
            if k + 2 < toks.count, !claimed.contains(k + 2), let s2 = sideAt(k + 2), toks[k + 1].key == "and" {
                found[h].insert(s2); claimed.insert(k + 2); hi[h] = k + 2
            }
        }

        var out: [ProcedureMatch] = []
        for (h, hit) in hits.enumerated() {
            let ph = phrases[hit.phrase]
            let proc = all[ph.proc]
            let f = found[h]
            var side: String?
            if f.contains("bilateral") || (f.contains("left") && f.contains("right")) {
                side = "bilateral"
            } else {
                side = f.first ?? ph.side
            }
            if !proc.lateral { side = nil }
            let first = proc.lateral ? lo[h] : hit.start
            let last = proc.lateral ? hi[h] : hit.end - 1
            let range = toks[first].range.lowerBound..<toks[last].range.upperBound
            out.append(ProcedureMatch(procedure: proc, side: side, range: range, text: String(text[range])))
        }
        return out
    }

    // MARK: Risk

    /// The risk inputs for one or several procedures; empty (nil incision and duration) for none.
    static func risk(_ matches: [ProcedureMatch]) -> ProcedureRisk {
        var r = ProcedureRisk()
        guard !matches.isEmpty else { return r }
        let ps = matches.map(\.procedure)
        r.highRisk = ps.contains { $0.highRisk }
        r.cardiac = ps.contains { $0.cardiac }
        r.echoFirst = ps.contains { $0.echoFirst }
        let worst = ps.map { incisions.firstIndex(of: $0.incision) ?? 0 }.max() ?? 0
        r.incision = incisions[worst]
        var longest = 0
        var overTwo = 0
        for m in matches {
            let d = durations.firstIndex(of: m.procedure.duration) ?? 0
            longest = max(longest, d)
            if d >= 1 { overTwo += (m.procedure.lateral && m.side == "bilateral") ? 2 : 1 }
        }
        if overTwo >= 2 { longest = min(longest + 1, durations.count - 1) }
        r.duration = durations[longest]
        let general = ps.filter { $0.anesthetic.contains("ga") }
        if general.isEmpty {
            r.anesthetic = ps.reduce(into: Set<String>()) { $0.formUnion($1.anesthetic) }
        } else {
            r.anesthetic = general.reduce(into: Set<String>()) { $0.formUnion($1.anesthetic) }
            r.anesthetic.remove("mac")
        }
        return r
    }

    /// Parse and add up in one step.
    static func risk(_ text: String) -> ProcedureRisk { risk(parse(text)) }

    /// The risk inputs for procedures picked from the list, each with its side.
    static func risk(picked: [(procedure: Procedure, side: String?)]) -> ProcedureRisk {
        let none = "".startIndex..<"".endIndex
        return risk(picked.map { ProcedureMatch(procedure: $0.procedure, side: $0.side, range: none, text: $0.procedure.name) })
    }

    // MARK: Text

    /// The name with its first letter lowered for "Left total knee arthroplasty", unless it starts with an
    /// abbreviation or a proper name.
    static func lowerFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        let word = s.prefix { $0 != " " && $0 != "," && $0 != "-" }
        if word.dropFirst().contains(where: { $0.isUppercase }) || properNames.contains(String(word)) { return s }
        return first.lowercased() + s.dropFirst()
    }

    private static let properNames: Set<String> = ["Whipple", "Nissen", "Heller", "Hartmann", "Ivor", "McKeown", "Ross",
        "Bentall", "Kasai", "Nuss", "Ravitch", "Puestow", "Burch", "Glenn", "Fontan", "Norwood", "Mohs", "Altemeier",
        "Roux", "Le", "Latarjet", "Bankart", "Morrow", "David", "Chiari", "Achilles", "Dupuytren", "Ladd", "Toupet"]

    // MARK: Tokens and phrases

    private static let sideWords: [String: String] = [
        "left": "left", "lt": "left", "l": "left",
        "right": "right", "rt": "right", "r": "right",
        "bilateral": "bilateral", "bilat": "bilateral", "bil": "bilateral", "bilaterally": "bilateral", "both": "bilateral",
        // Eyes: oculus dexter, sinister, uterque.
        "od": "right", "os": "left", "ou": "bilateral",
    ]

    /// Spellings read as one word (after folding and singular).
    private static let aliases: [String: String] = [
        "lap": "laparoscopic", "robot": "robotic", "robotically": "robotic", "laparoscopically": "laparoscopic",
        "caesarean": "cesarean", "caesarian": "cesarean", "cesarian": "cesarean",
        "oesophagectomy": "esophagectomy", "oesophagus": "esophagus", "oesophageal": "esophageal",
        "oesophagogastroduodenoscopy": "esophagogastroduodenoscopy", "haemorrhoidectomy": "hemorrhoidectomy",
        "orchidopexy": "orchiopexy", "tumour": "tumor", "appendicectomy": "appendectomy", "foetal": "fetal",
        "paediatric": "pediatric", "labour": "labor", "anaesthesia": "anesthesia", "haematoma": "hematoma", "oophrectomy": "oophorectomy",
    ]

    /// Forms that name their own side.
    private static let impliedSides: [String: String] = ["BMT": "bilateral", "BMTs": "bilateral", "BSO": "bilateral", "laparoscopic BSO": "bilateral", "TAH BSO": "bilateral"]

    fileprivate static let phrases: [ProcPhrase] = {
        var out: [ProcPhrase] = []
        for (i, p) in all.enumerated() {
            for (n, form) in ([p.name] + p.synonyms).enumerated() where n == 0 || !p.caseSensitive.contains(form) {
                let t = tokenize(form)
                guard !t.isEmpty else { continue }
                var side = impliedSides[form]
                if side == nil, p.lateral, let f = t.first?.raw, sides.contains(f) { side = f }
                out.append(ProcPhrase(key: t.map(\.key), raw: t.map(\.raw), exact: nil, proc: i, side: side, isName: n == 0))
            }
            for form in p.caseSensitive {
                let t = tokenize(form)
                guard !t.isEmpty else { continue }
                out.append(ProcPhrase(key: t.map(\.key), raw: t.map(\.raw), exact: t.map(\.original), proc: i, side: nil, isName: false))
            }
        }
        return out
    }()

    fileprivate static let phrasesByProc: [[Int]] = {
        var out = [[Int]](repeating: [], count: all.count)
        for (i, p) in phrases.enumerated() { out[p.proc].append(i) }
        return out
    }()

    /// Every beginning of every word (as typed and by its alias) → the procedures with such a word, sorted.
    private static let prefixIndex: [String: [Int]] = {
        var byWord: [String: Set<Int>] = [:]
        for p in phrases {
            for w in p.raw + p.key { byWord[w, default: []].insert(p.proc) }
        }
        var byPrefix: [String: Set<Int>] = [:]
        for (w, procs) in byWord {
            var prefix = ""
            for c in w {
                prefix.append(c)
                byPrefix[prefix, default: []].formUnion(procs)
            }
        }
        return byPrefix.mapValues { $0.sorted() }
    }()

    fileprivate static let firstToken: [String: [Int]] = {
        var d: [String: [Int]] = [:]
        for (i, p) in phrases.enumerated() {
            if let f = p.key.first { d[f, default: []].append(i) }
        }
        return d
    }()

    /// Words with their place in the text: letters and digits (with inner apostrophes); "&" reads as "and"; "b/l"
    /// as "bilateral"; a count glued to an abbreviation ("CABGx3") is dropped.
    fileprivate static func tokenize(_ s: String) -> [ProcToken] {
        var out: [ProcToken] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "&" {
                let j = s.index(after: i)
                out.append(ProcToken(original: "&", raw: "and", key: "and", range: i..<j))
                i = j
                continue
            }
            guard c.isLetter || c.isNumber else { i = s.index(after: i); continue }
            var j = s.index(after: i)
            while j < s.endIndex {
                let d = s[j]
                if d.isLetter || d.isNumber { j = s.index(after: j); continue }
                if d == "'" || d == "’" {
                    let k = s.index(after: j)
                    if k < s.endIndex, s[k].isLetter { j = s.index(after: k); continue }
                }
                break
            }
            addWord(s, i..<j, &out)
            i = j
        }
        // "b/l"
        var merged: [ProcToken] = []
        var k = 0
        while k < out.count {
            if k + 1 < out.count, out[k].raw == "b", out[k + 1].raw == "l",
               s[out[k].range.upperBound..<out[k + 1].range.lowerBound].trimmingCharacters(in: .whitespaces) == "/" {
                merged.append(ProcToken(original: "b/l", raw: "bilateral", key: "bilateral", range: out[k].range.lowerBound..<out[k + 1].range.upperBound))
                k += 2
            } else {
                merged.append(out[k])
                k += 1
            }
        }
        return merged
    }

    private static func addWord(_ s: String, _ r: Range<String.Index>, _ out: inout [ProcToken]) {
        var range = r
        var word = String(s[r])
        var f = fold(word)
        if let x = f.lastIndex(of: "x"), x != f.startIndex {
            let digits = f[f.index(after: x)...]
            let head = f[..<x]
            if !digits.isEmpty, digits.allSatisfy(\.isNumber), head.count >= 2, head.allSatisfy(\.isLetter),
               let end = s.index(r.lowerBound, offsetBy: head.count, limitedBy: r.upperBound) {
                range = r.lowerBound..<end
                word = String(s[range])
                f = String(head)
            }
        }
        let raw = singular(f)
        out.append(ProcToken(original: word, raw: raw, key: aliases[raw] ?? raw, range: range))
    }

    private static func fold(_ w: String) -> String {
        var f = w.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        if f.hasSuffix("'s") || f.hasSuffix("’s") { f.removeLast(2) }
        f.removeAll { $0 == "'" || $0 == "’" }
        return f
    }

    /// A plural read as its singular ("tubes", "hernias", "biopsies", "sinuses"); short words and words ending in
    /// -ss, -us or -is are left alone.
    private static func singular(_ w: String) -> String {
        guard w.count > 3, w.hasSuffix("s"), w.allSatisfy(\.isLetter) else { return w }
        if w.hasSuffix("ss") || w.hasSuffix("us") || w.hasSuffix("is") { return w }
        if w.hasSuffix("ies"), w.count > 4 { return String(w.dropLast(3)) + "y" }
        for suffix in ["sses", "uses", "ches", "shes", "xes", "zes"] where w.hasSuffix(suffix) { return String(w.dropLast(2)) }
        return String(w.dropLast())
    }
}

// MARK: - The catalog

extension ProcedureCatalog {
    fileprivate static let per = "Peripheral", upper = "Upper abdominal", chest = "Intrathoracic"
    fileprivate static let short = "≤ 2 h", mid = "> 2–3 h", long = "> 3 h"
    fileprivate static let ga: Set<String> = ["ga"]
    fileprivate static let mac: Set<String> = ["mac"]
    fileprivate static let nx: Set<String> = ["neuraxial"]
    fileprivate static let gaNx: Set<String> = ["ga", "neuraxial"]
    fileprivate static let gaRa: Set<String> = ["ga", "regional"]
    fileprivate static let nxRa: Set<String> = ["neuraxial", "regional"]
    fileprivate static let raMac: Set<String> = ["regional", "mac"]

    fileprivate static func p(_ id: String, _ name: String, _ synonyms: [String], _ anesthetic: Set<String>, _ incision: String, _ duration: String,
                              risk: Bool = false, side: Bool = false, cardiac: Bool = false, echo: Bool = false, exact: [String] = []) -> Procedure {
        Procedure(id: id, name: name, specialty: "", synonyms: synonyms + exact, anesthetic: anesthetic, highRisk: risk, incision: incision,
                  duration: duration, lateral: side, cardiac: cardiac, echoFirst: echo, caseSensitive: exact)
    }

    /// A cardiac case: cardiac and echo first, general anesthesia, through the chest, over 3 h unless given.
    fileprivate static func heart(_ id: String, _ name: String, _ synonyms: [String], _ anesthetic: Set<String> = ga, _ incision: String = chest,
                                  _ duration: String = long, risk: Bool = true, exact: [String] = []) -> Procedure {
        p(id, name, synonyms, anesthetic, incision, duration, risk: risk, cardiac: true, echo: true, exact: exact)
    }

    fileprivate static func section(_ specialty: String, _ items: [Procedure]) -> [Procedure] {
        items.map { item in
            var x = item
            x.specialty = specialty
            return x
        }
    }

    fileprivate static let sections: [[Procedure]] = [
        section("General & colorectal", general),
        section("Hepatobiliary & pancreas", hepatobiliary),
        section("Upper GI & bariatric", upperGI),
        section("Hernia", hernia),
        section("Breast & endocrine", breastEndocrine),
        section("Vascular", vascular),
        section("Cardiac", cardiacSurgery),
        section("Thoracic", thoracic),
        section("Transplant", transplant),
        section("Urology", urology),
        section("Gynecology & obstetrics", gynecology),
        section("Orthopedics", orthopedics),
        section("Spine", spine),
        section("Neurosurgery", neurosurgery),
        section("ENT & head and neck", ent),
        section("Ophthalmology", ophthalmology),
        section("Plastics", plastics),
        section("Dental & oral", dental),
        section("GI endoscopy", endoscopy),
        section("Interventional radiology", radiology),
        section("Cardiac cath & EP", cathEP),
        section("Bronchoscopy", bronchoscopy),
        section("Pediatrics", pediatrics),
    ]

    // MARK: General and colorectal

    fileprivate static let general: [Procedure] = [
        p("ex-lap", "Exploratory laparotomy", ["ex lap", "exlap", "laparotomy", "trauma laparotomy", "damage control laparotomy", "open abdomen"], ga, upper, mid, risk: true),
        p("abdominal-washout", "Abdominal washout or second look", ["abdominal washout", "second look laparotomy", "relook laparotomy", "take back laparotomy", "abdominal closure", "fascial closure"], ga, upper, short, risk: true),
        p("dx-lap", "Diagnostic laparoscopy", ["dx lap", "diagnostic lap", "staging laparoscopy", "laparoscopy"], ga, upper, short, risk: true),
        p("lap-appy", "Laparoscopic appendectomy", ["lap appy", "appy", "appendectomy", "robotic appendectomy"], ga, per, short, risk: true),
        p("open-appy", "Open appendectomy", ["open appy"], ga, per, short, risk: true),
        p("open-colectomy", "Open colectomy", ["colectomy", "partial colectomy", "segmental colectomy", "hemicolectomy", "open hemicolectomy", "open partial colectomy"], ga, upper, long, risk: true),
        p("open-right-hemi", "Open right hemicolectomy", ["right hemicolectomy", "R hemicolectomy", "right colectomy", "open right colectomy", "ileocolic resection", "ileocecectomy", "extended right hemicolectomy"], ga, upper, long, risk: true),
        p("open-left-hemi", "Open left hemicolectomy", ["left hemicolectomy", "L hemicolectomy", "left colectomy", "open left colectomy"], ga, upper, long, risk: true),
        p("open-sigmoid", "Open sigmoid colectomy", ["sigmoid colectomy", "sigmoidectomy", "open sigmoidectomy"], ga, upper, long, risk: true),
        p("lap-colectomy", "Laparoscopic colectomy", ["robotic colectomy", "laparoscopic hemicolectomy", "robotic hemicolectomy", "laparoscopic partial colectomy"], ga, upper, long, risk: true),
        p("lap-right-hemi", "Laparoscopic right hemicolectomy", ["laparoscopic right colectomy", "robotic right colectomy", "robotic right hemicolectomy", "laparoscopic ileocecectomy", "laparoscopic ileocolic resection"], ga, upper, mid, risk: true),
        p("lap-left-hemi", "Laparoscopic left hemicolectomy", ["laparoscopic left colectomy", "robotic left colectomy", "robotic left hemicolectomy"], ga, upper, long, risk: true),
        p("lap-sigmoid", "Laparoscopic sigmoid colectomy", ["laparoscopic sigmoidectomy", "robotic sigmoid colectomy", "robotic sigmoidectomy"], ga, upper, long, risk: true),
        p("hartmann", "Hartmann procedure", ["Hartmann's", "Hartmann", "sigmoid colectomy with end colostomy"], ga, upper, mid, risk: true),
        p("hartmann-reversal", "Hartmann reversal", ["reversal of Hartmann's", "colostomy takedown", "colostomy reversal", "colostomy closure"], ga, upper, long, risk: true),
        p("open-lar", "Open low anterior resection", ["LAR", "low anterior resection", "open LAR", "anterior resection", "proctectomy"], ga, upper, long, risk: true),
        p("lap-lar", "Laparoscopic low anterior resection", ["laparoscopic LAR", "robotic LAR", "robotic low anterior resection", "laparoscopic proctectomy", "robotic proctectomy"], ga, upper, long, risk: true),
        p("apr", "Abdominoperineal resection", ["APR", "AP resection", "open APR", "Miles procedure"], ga, upper, long, risk: true),
        p("lap-apr", "Laparoscopic abdominoperineal resection", ["laparoscopic APR", "robotic APR", "robotic abdominoperineal resection"], ga, upper, long, risk: true),
        p("total-colectomy", "Total abdominal colectomy", ["total colectomy", "subtotal colectomy", "TAC", "colectomy with end ileostomy"], ga, upper, long, risk: true),
        p("proctocolectomy", "Total proctocolectomy with ileal pouch", ["proctocolectomy", "IPAA", "J pouch", "ileal pouch anal anastomosis", "TPC", "restorative proctocolectomy"], ga, upper, long, risk: true),
        p("ileostomy-closure", "Ileostomy closure", ["ileostomy takedown", "ileostomy reversal", "loop ileostomy closure", "stoma closure", "stoma reversal"], ga, per, short, risk: true),
        p("stoma-creation", "Diverting ileostomy or colostomy", ["loop ileostomy", "diverting ileostomy", "diverting colostomy", "loop colostomy", "colostomy", "ileostomy", "stoma creation", "end colostomy"], ga, per, short, risk: true),
        p("small-bowel-resection", "Small bowel resection", ["SBR", "bowel resection", "enterectomy", "ileal resection", "jejunal resection"], ga, upper, mid, risk: true),
        p("adhesiolysis", "Lysis of adhesions", ["LOA", "adhesiolysis", "laparoscopic lysis of adhesions", "lysis of adhesions for SBO"], ga, upper, mid, risk: true),
        p("feeding-jejunostomy", "Feeding jejunostomy", ["J tube", "jejunostomy", "jejunostomy tube", "feeding J tube"], ga, upper, short, risk: true),
        p("lap-splenectomy", "Laparoscopic splenectomy", ["laparoscopic splenectomy", "robotic splenectomy"], ga, upper, mid, risk: true),
        p("open-splenectomy", "Open splenectomy", ["splenectomy", "trauma splenectomy"], ga, upper, short, risk: true),
        p("hipec", "Cytoreductive surgery with HIPEC", ["HIPEC", "CRS HIPEC", "cytoreductive surgery", "cytoreduction", "peritonectomy"], gaNx, upper, long, risk: true),
        p("hemorrhoidectomy", "Hemorrhoidectomy", ["hemorrhoid surgery", "excisional hemorrhoidectomy", "hemorrhoidopexy", "PPH stapled hemorrhoidopexy"], ga, per, short),
        p("fistulotomy", "Anal fistulotomy or seton", ["fistulotomy", "seton", "seton placement", "anal fistula", "fistula in ano", "LIFT procedure", "sphincterotomy", "lateral internal sphincterotomy"], ga, per, short),
        p("perirectal-abscess", "Drainage of perirectal abscess", ["perirectal abscess", "perianal abscess", "I&D perirectal abscess", "ischiorectal abscess"], ga, per, short),
        p("pilonidal", "Pilonidal cyst excision", ["pilonidal cyst", "pilonidal cystectomy", "pilonidal sinus", "pilonidal"], ga, per, short),
        p("anorectal-eua", "Anorectal examination under anesthesia", ["EUA anus", "anorectal EUA", "EUA rectum", "exam under anesthesia anorectal", "anal EUA"], mac, per, short),
        p("transanal-excision", "Transanal excision", ["TAE", "TAMIS", "transanal minimally invasive surgery", "TEM", "transanal endoscopic microsurgery", "transanal excision of rectal tumor"], ga, per, short),
        p("perineal-proctectomy", "Perineal proctosigmoidectomy", ["Altemeier", "Altemeier procedure", "perineal rectosigmoidectomy", "Delorme", "Delorme procedure", "perineal rectal prolapse repair"], nx, per, mid),
        p("rectopexy", "Laparoscopic rectopexy", ["rectopexy", "robotic rectopexy", "ventral mesh rectopexy", "abdominal rectopexy"], ga, per, mid, risk: true),
        p("incision-drainage", "Incision and drainage of abscess", ["I&D", "incision and drainage", "abscess drainage", "I&D abscess", "abscess I&D"], mac, per, short),
        p("soft-tissue-mass", "Excision of soft tissue mass", ["lipoma excision", "lipoma", "soft tissue mass excision", "mass excision", "excision of mass", "sebaceous cyst excision"], mac, per, short),
        p("lymph-node-biopsy", "Excisional lymph node biopsy", ["lymph node biopsy", "LN biopsy", "lymph node excision", "cervical lymph node biopsy", "axillary lymph node biopsy", "inguinal lymph node biopsy"], ga, per, short),
        p("port-placement", "Port placement", ["port a cath", "port-a-cath placement", "mediport", "chemo port", "port insertion", "implanted port", "power port", "port"], mac, per, short),
        p("port-removal", "Port removal", ["port a cath removal", "mediport removal", "chemo port removal", "port explant"], mac, per, short),
        p("debridement", "Wound debridement", ["debridement", "excisional debridement", "wound washout", "wound VAC change", "VAC change", "necrotizing fasciitis debridement", "wound exploration"], ga, per, short),
    ]

    // MARK: Hepatobiliary and pancreas

    fileprivate static let hepatobiliary: [Procedure] = [
        p("lap-chole", "Laparoscopic cholecystectomy", ["lap chole", "chole", "cholecystectomy", "robotic cholecystectomy", "lap cholecystectomy with cholangiogram", "lap chole with IOC"], ga, upper, short, risk: true),
        p("open-chole", "Open cholecystectomy", ["open chole", "converted cholecystectomy"], ga, upper, mid, risk: true),
        p("cbde", "Common bile duct exploration", ["CBDE", "LCBDE", "CBD exploration", "laparoscopic common bile duct exploration", "bile duct exploration"], ga, upper, mid, risk: true),
        p("whipple", "Whipple procedure", ["Whipple", "pancreaticoduodenectomy", "open Whipple", "pylorus preserving pancreaticoduodenectomy", "PPPD"], gaNx, upper, long, risk: true),
        p("robotic-whipple", "Robotic Whipple procedure", ["robotic Whipple", "robotic pancreaticoduodenectomy", "laparoscopic Whipple", "laparoscopic pancreaticoduodenectomy"], ga, upper, long, risk: true),
        p("distal-pancreatectomy", "Distal pancreatectomy", ["open distal pancreatectomy", "distal pancreatectomy and splenectomy", "distal pancreatectomy with splenectomy"], ga, upper, long, risk: true),
        p("lap-distal-pancreatectomy", "Laparoscopic distal pancreatectomy", ["robotic distal pancreatectomy"], ga, upper, mid, risk: true),
        p("total-pancreatectomy", "Total pancreatectomy", ["TPIAT", "total pancreatectomy with islet autotransplant", "total pancreatectomy and islet autotransplantation"], ga, upper, long, risk: true),
        p("puestow", "Puestow procedure", ["Puestow", "lateral pancreaticojejunostomy", "Frey procedure", "Frey", "pancreaticojejunostomy", "Beger procedure"], ga, upper, long, risk: true),
        p("necrosectomy", "Pancreatic necrosectomy", ["necrosectomy", "open necrosectomy", "VARD", "video assisted retroperitoneal debridement"], ga, upper, mid, risk: true),
        p("pancreatic-enucleation", "Pancreatic enucleation", ["enucleation of pancreatic tumor", "insulinoma enucleation"], ga, upper, mid, risk: true),
        p("major-hepatectomy", "Major hepatectomy", ["hepatectomy", "right hepatectomy", "left hepatectomy", "hemihepatectomy", "trisectionectomy", "extended hepatectomy", "liver resection", "open liver resection", "right lobectomy liver"], ga, upper, long, risk: true),
        p("partial-hepatectomy", "Partial hepatectomy", ["wedge liver resection", "liver wedge resection", "liver segmentectomy", "partial liver resection", "nonanatomic liver resection", "sectionectomy"], ga, upper, mid, risk: true),
        p("lap-hepatectomy", "Laparoscopic liver resection", ["laparoscopic hepatectomy", "robotic hepatectomy", "robotic liver resection", "minimally invasive hepatectomy"], ga, upper, long, risk: true),
        p("liver-ablation-surgical", "Operative liver ablation", ["laparoscopic liver ablation", "open liver ablation", "laparoscopic microwave ablation", "intraoperative liver ablation"], ga, upper, mid, risk: true),
        p("hepaticojejunostomy", "Hepaticojejunostomy", ["Roux-en-Y hepaticojejunostomy", "HJ", "choledochojejunostomy", "biliary bypass", "hepaticojejunostomy revision"], ga, upper, long, risk: true),
        p("bile-duct-resection", "Bile duct resection", ["Klatskin resection", "hilar cholangiocarcinoma resection", "bile duct excision", "extrahepatic bile duct resection"], ga, upper, long, risk: true),
        p("liver-cyst", "Liver cyst fenestration", ["liver cyst unroofing", "hepatic cyst fenestration", "laparoscopic liver cyst fenestration", "hydatid cyst excision"], ga, upper, mid, risk: true),
    ]

    // MARK: Upper GI and bariatric

    fileprivate static let upperGI: [Procedure] = [
        p("sleeve", "Laparoscopic sleeve gastrectomy", ["sleeve", "sleeve gastrectomy", "LSG", "VSG", "vertical sleeve gastrectomy", "gastric sleeve", "robotic sleeve gastrectomy"], ga, upper, short, risk: true),
        p("rygb", "Laparoscopic Roux-en-Y gastric bypass", ["RYGB", "LRYGB", "RNY", "gastric bypass", "Roux-en-Y gastric bypass", "robotic gastric bypass", "lap gastric bypass", "lap RYGB"], ga, upper, mid, risk: true),
        p("lap-band", "Laparoscopic adjustable gastric band", ["lap band", "gastric band", "LAGB", "lap band removal", "gastric band removal", "lap band revision"], ga, upper, short, risk: true),
        p("duodenal-switch", "Duodenal switch", ["BPD-DS", "biliopancreatic diversion with duodenal switch", "biliopancreatic diversion", "SADI-S", "SADI", "single anastomosis duodenal ileal bypass"], ga, upper, long, risk: true),
        p("bariatric-revision", "Revisional bariatric surgery", ["bariatric revision", "sleeve to bypass", "conversion to gastric bypass", "revision gastric bypass", "gastric bypass revision"], ga, upper, long, risk: true),
        p("nissen", "Laparoscopic Nissen fundoplication", ["Nissen", "Nissen fundoplication", "fundoplication", "LNF", "Toupet", "Toupet fundoplication", "Dor fundoplication", "robotic fundoplication", "partial fundoplication"], ga, upper, mid, risk: true),
        p("heller", "Laparoscopic Heller myotomy", ["Heller myotomy", "Heller", "LHM", "Heller myotomy with Dor", "myotomy for achalasia", "robotic Heller myotomy"], ga, upper, mid, risk: true),
        p("linx", "Magnetic sphincter augmentation", ["LINX", "LINX placement", "magnetic sphincter augmentation device"], ga, upper, short, risk: true),
        p("total-gastrectomy", "Total gastrectomy", ["open total gastrectomy", "total gastrectomy with Roux-en-Y", "esophagojejunostomy"], gaNx, upper, long, risk: true),
        p("partial-gastrectomy", "Partial gastrectomy", ["subtotal gastrectomy", "distal gastrectomy", "gastrectomy", "Billroth I", "Billroth II", "antrectomy", "open gastrectomy"], ga, upper, long, risk: true),
        p("lap-gastrectomy", "Laparoscopic gastrectomy", ["robotic gastrectomy", "laparoscopic subtotal gastrectomy", "laparoscopic total gastrectomy", "robotic total gastrectomy"], ga, upper, long, risk: true),
        p("gastric-wedge", "Gastric wedge resection", ["wedge gastrectomy", "GIST resection", "laparoscopic gastric wedge resection", "gastric GIST excision"], ga, upper, mid, risk: true),
        p("perforated-ulcer", "Repair of perforated ulcer", ["Graham patch", "omental patch", "perforated ulcer repair", "perforated peptic ulcer", "perforated duodenal ulcer repair", "laparoscopic Graham patch"], ga, upper, short, risk: true),
        p("surgical-gastrostomy", "Surgical gastrostomy", ["open gastrostomy", "laparoscopic gastrostomy", "G tube", "gastrostomy tube placement", "Stamm gastrostomy", "gastrostomy"], ga, upper, short, risk: true),
        p("gastrojejunostomy", "Gastrojejunostomy", ["GJ bypass", "gastric bypass for outlet obstruction", "palliative gastrojejunostomy", "laparoscopic gastrojejunostomy"], ga, upper, mid, risk: true),
    ]

    // MARK: Hernia

    fileprivate static let hernia: [Procedure] = [
        p("inguinal-hernia-open", "Open inguinal hernia repair", ["inguinal hernia repair", "inguinal hernia", "IHR", "open IHR", "Lichtenstein repair", "Lichtenstein", "groin hernia repair", "inguinal herniorrhaphy", "Shouldice repair"], ga, per, short, side: true),
        p("inguinal-hernia-lap", "Laparoscopic inguinal hernia repair", ["laparoscopic IHR", "TAPP", "TAPP repair", "transabdominal preperitoneal repair", "robotic inguinal hernia repair", "robotic IHR", "laparoscopic hernia repair", "lap hernia"], ga, per, short, risk: true, side: true),
        p("inguinal-hernia-tep", "Totally extraperitoneal inguinal hernia repair", ["TEP", "TEP repair", "TEP inguinal hernia repair", "totally extraperitoneal repair", "eTEP inguinal hernia repair"], ga, per, short, side: true),
        p("femoral-hernia", "Femoral hernia repair", ["femoral hernia", "femoral herniorrhaphy", "incarcerated femoral hernia repair"], ga, per, short, side: true),
        p("umbilical-hernia", "Umbilical hernia repair", ["umbilical hernia", "umbilical herniorrhaphy", "UHR", "periumbilical hernia repair", "epigastric hernia repair", "epigastric hernia"], ga, per, short),
        p("ventral-hernia-open", "Open ventral hernia repair", ["ventral hernia repair", "ventral hernia", "incisional hernia repair", "incisional hernia", "VHR", "open incisional hernia repair", "open VHR"], ga, upper, mid, risk: true),
        p("ventral-hernia-lap", "Laparoscopic ventral hernia repair", ["laparoscopic incisional hernia repair", "robotic ventral hernia repair", "robotic incisional hernia repair", "laparoscopic VHR", "robotic VHR", "IPOM", "eTEP ventral hernia repair"], ga, upper, mid, risk: true),
        p("hiatal-hernia", "Paraesophageal hernia repair", ["PEH repair", "PEHR", "paraesophageal hernia", "hiatal hernia repair", "hiatal hernia", "laparoscopic hiatal hernia repair", "robotic hiatal hernia repair", "redo fundoplication"], ga, upper, mid, risk: true),
        p("abdominal-wall-reconstruction", "Abdominal wall reconstruction", ["component separation", "AWR", "TAR", "transversus abdominis release", "complex abdominal wall reconstruction", "anterior component separation"], gaNx, upper, long, risk: true),
        p("parastomal-hernia", "Parastomal hernia repair", ["parastomal hernia", "Sugarbaker repair", "stoma revision"], ga, upper, mid, risk: true),
        p("spigelian-hernia", "Spigelian hernia repair", ["spigelian hernia", "flank hernia repair", "lumbar hernia repair"], ga, per, short, side: true),
        p("sports-hernia", "Sports hernia repair", ["sports hernia", "athletic pubalgia repair", "core muscle injury repair"], ga, per, short, side: true),
    ]

    // MARK: Breast and endocrine

    fileprivate static let breastEndocrine: [Procedure] = [
        p("lumpectomy", "Lumpectomy", ["partial mastectomy", "breast lumpectomy", "segmental mastectomy", "wide local excision breast", "breast conserving surgery", "re-excision lumpectomy"], ga, per, short, side: true),
        p("lumpectomy-slnb", "Lumpectomy with sentinel node biopsy", ["lumpectomy and SLNB", "lumpectomy with SLNB", "partial mastectomy with sentinel lymph node biopsy", "lumpectomy and sentinel node biopsy"], ga, per, short, side: true),
        p("breast-biopsy", "Excisional breast biopsy", ["breast biopsy", "wire localized breast biopsy", "needle localized excisional biopsy", "breast mass excision", "duct excision", "fibroadenoma excision"], mac, per, short, side: true),
        p("slnb", "Sentinel lymph node biopsy", ["SLNB", "sentinel node biopsy", "sentinel lymph node", "axillary sentinel node biopsy"], ga, per, short, side: true),
        p("simple-mastectomy", "Simple mastectomy", ["mastectomy", "total mastectomy", "skin sparing mastectomy", "nipple sparing mastectomy", "prophylactic mastectomy", "simple mastectomy with SLNB"], gaRa, per, short, side: true),
        p("modified-radical-mastectomy", "Modified radical mastectomy", ["MRM", "radical mastectomy", "mastectomy with axillary dissection"], gaRa, per, mid, side: true),
        p("mastectomy-reconstruction", "Mastectomy with immediate reconstruction", ["mastectomy with tissue expanders", "mastectomy with expander", "mastectomy and reconstruction", "mastectomy with implant reconstruction", "mastectomy with immediate reconstruction"], gaRa, per, long, side: true),
        p("alnd", "Axillary lymph node dissection", ["ALND", "axillary dissection", "axillary node dissection", "completion axillary dissection"], ga, per, short, side: true),
        p("gynecomastia", "Gynecomastia excision", ["gynecomastia", "male breast reduction", "subcutaneous mastectomy"], ga, per, short, side: true),
        p("thyroidectomy-total", "Total thyroidectomy", ["thyroidectomy", "TT", "total thyroidectomy with central neck dissection", "completion thyroidectomy", "near total thyroidectomy"], ga, per, short),
        p("hemithyroidectomy", "Thyroid lobectomy", ["hemithyroidectomy", "thyroid lobectomy and isthmusectomy", "lobectomy thyroid", "isthmusectomy"], ga, per, short, side: true),
        p("substernal-thyroid", "Substernal thyroidectomy", ["substernal goiter", "retrosternal goiter", "thyroidectomy with sternotomy", "substernal goiter excision"], ga, per, mid),
        p("parathyroidectomy", "Parathyroidectomy", ["parathyroid exploration", "minimally invasive parathyroidectomy", "MIP", "focused parathyroidectomy", "4 gland exploration", "subtotal parathyroidectomy"], ga, per, short),
        p("lap-adrenalectomy", "Laparoscopic adrenalectomy", ["adrenalectomy", "laparoscopic adrenalectomy for pheochromocytoma", "robotic adrenalectomy", "retroperitoneoscopic adrenalectomy", "posterior retroperitoneoscopic adrenalectomy"], ga, upper, mid, risk: true, side: true),
        p("open-adrenalectomy", "Open adrenalectomy", ["open adrenalectomy for pheochromocytoma", "adrenalectomy open"], ga, upper, mid, risk: true, side: true),
        p("neck-dissection-endocrine", "Central neck dissection", ["central compartment neck dissection", "level VI neck dissection", "lateral neck dissection for thyroid cancer"], ga, per, mid),
    ]

    // MARK: Vascular

    fileprivate static let vascular: [Procedure] = [
        p("cea", "Carotid endarterectomy", ["CEA", "carotid endarterectomy with patch", "redo CEA", "carotid surgery"], ga, per, mid, side: true),
        p("tcar", "Transcarotid artery revascularization", ["TCAR", "transcarotid stenting", "transcarotid artery stent"], ga, per, short, side: true),
        p("carotid-stent", "Carotid artery stenting", ["CAS", "carotid stent", "carotid stenting", "transfemoral carotid stenting", "TF-CAS"], mac, per, short, side: true),
        p("open-aaa", "Open abdominal aortic aneurysm repair", ["open AAA", "open AAA repair", "AAA repair", "AAA", "abdominal aortic aneurysm repair", "aortic aneurysm repair", "ruptured AAA", "rAAA", "aortic tube graft", "aortobiiliac graft"], gaNx, upper, long, risk: true, echo: true),
        p("evar", "Endovascular aneurysm repair", ["EVAR", "endovascular AAA repair", "endovascular aortic aneurysm repair", "percutaneous EVAR", "PEVAR", "aortic endograft", "EVAR for ruptured AAA"], ga, per, mid, risk: true, echo: true),
        p("fevar", "Fenestrated or branched EVAR", ["FEVAR", "BEVAR", "FBEVAR", "fenestrated EVAR", "branched EVAR", "complex EVAR", "chimney EVAR", "ChEVAR", "physician modified endograft"], ga, per, long, risk: true, echo: true),
        p("tevar", "Thoracic endovascular aortic repair", ["TEVAR", "thoracic EVAR", "thoracic stent graft", "TEVAR for dissection", "type B dissection TEVAR", "endovascular repair of thoracic aorta"], ga, per, mid, risk: true, echo: true),
        p("taaa", "Open thoracoabdominal aortic aneurysm repair", ["TAAA", "TAAA repair", "thoracoabdominal aneurysm repair", "thoracoabdominal aortic aneurysm repair", "thoracoabdominal aneurysm", "Crawford extent II"], gaNx, chest, long, risk: true, echo: true),
        p("open-dtaa", "Open descending thoracic aortic repair", ["DTAA repair", "descending thoracic aneurysm repair", "open descending aortic repair", "descending thoracic aortic aneurysm repair"], gaNx, chest, long, risk: true, echo: true),
        p("aortobifemoral", "Aortobifemoral bypass", ["ABF", "aortobifemoral", "aorto bifem", "aortobifem bypass", "aortofemoral bypass", "aortoiliac bypass", "aortoiliac endarterectomy", "aortic bypass"], gaNx, upper, long, risk: true),
        p("mesenteric-bypass", "Mesenteric bypass", ["mesenteric revascularization", "SMA bypass", "aortomesenteric bypass", "celiac bypass", "open mesenteric revascularization", "renal artery bypass"], gaNx, upper, long, risk: true),
        p("axillobifemoral", "Axillobifemoral bypass", ["ax bifem", "axillobifemoral", "axillofemoral bypass", "ax fem bypass", "extra anatomic bypass"], ga, per, mid),
        p("fem-fem", "Femorofemoral bypass", ["fem fem bypass", "fem-fem", "femoral femoral bypass", "femorofemoral crossover bypass", "crossover bypass"], ga, per, mid),
        p("fem-pop", "Femoropopliteal bypass", ["fem pop", "fem pop bypass", "femoral popliteal bypass", "FPB", "above knee fem pop", "below knee fem pop"], ga, per, mid, side: true),
        p("fem-distal", "Femoral-distal bypass", ["fem distal bypass", "fem tib bypass", "femoral tibial bypass", "fem peroneal bypass", "distal bypass", "pedal bypass", "tibial bypass"], ga, per, long, side: true),
        p("femoral-endarterectomy", "Common femoral endarterectomy", ["femoral endarterectomy", "CFE", "femoral endarterectomy with patch angioplasty", "femoral artery endarterectomy", "profundaplasty"], ga, per, mid, side: true),
        p("embolectomy", "Arterial embolectomy", ["embolectomy", "arterial thrombectomy", "femoral embolectomy", "brachial embolectomy", "Fogarty embolectomy", "open thrombectomy"], ga, per, short, side: true),
        p("popliteal-aneurysm", "Popliteal aneurysm repair", ["popliteal aneurysm", "popliteal artery aneurysm repair", "popliteal aneurysm exclusion and bypass"], ga, per, mid, side: true),
        p("peripheral-angioplasty", "Peripheral angioplasty and stenting", ["peripheral angioplasty", "angioplasty", "PTA", "lower extremity angiogram", "LE angiogram", "peripheral atherectomy", "iliac stent", "SFA stent", "runoff angiogram", "peripheral vascular intervention"], mac, per, short, side: true),
        p("av-fistula", "Arteriovenous fistula creation", ["AVF", "AV fistula", "AVF creation", "radiocephalic fistula", "brachiocephalic fistula", "brachiobasilic fistula", "basilic vein transposition", "BVT", "dialysis fistula", "fistula creation"], raMac, per, short, side: true),
        p("av-graft", "Arteriovenous graft", ["AVG", "AV graft", "dialysis graft", "forearm loop graft", "upper arm AV graft", "AV graft placement"], raMac, per, short, side: true),
        p("access-revision", "Dialysis access revision", ["fistula revision", "AV fistula revision", "fistula thrombectomy", "graft thrombectomy", "AVG thrombectomy", "fistula ligation", "DRIL", "access revision", "fistula superficialization"], mac, per, short, side: true),
        p("bka", "Below knee amputation", ["BKA", "below the knee amputation", "transtibial amputation", "guillotine amputation"], gaRa, per, short, side: true),
        p("aka", "Above knee amputation", ["above the knee amputation", "transfemoral amputation", "through knee amputation"], gaRa, per, short, side: true, exact: ["AKA"]),
        p("foot-amputation", "Toe or transmetatarsal amputation", ["toe amputation", "TMA", "transmetatarsal amputation", "ray amputation", "ray resection", "forefoot amputation", "partial foot amputation"], raMac, per, short, side: true),
        p("vein-ablation", "Endovenous ablation", ["EVLT", "EVLA", "endovenous laser ablation", "radiofrequency vein ablation", "venous ablation", "vein ablation", "GSV ablation", "saphenous vein ablation", "ClosureFast"], mac, per, short, side: true),
        p("vein-stripping", "Vein stripping and phlebectomy", ["vein stripping", "phlebectomy", "stab phlebectomy", "varicose vein surgery", "varicose veins", "high ligation and stripping"], ga, per, short, side: true),
        p("fasciotomy", "Fasciotomy", ["four compartment fasciotomy", "compartment release", "leg fasciotomy", "forearm fasciotomy", "fasciotomy for compartment syndrome"], ga, per, short, side: true),
        p("first-rib", "First rib resection", ["thoracic outlet decompression", "TOS decompression", "thoracic outlet syndrome surgery", "transaxillary first rib resection", "scalenectomy"], ga, per, mid, side: true),
    ]

    // MARK: Cardiac

    fileprivate static let cardiacSurgery: [Procedure] = [
        heart("cabg", "Coronary artery bypass grafting", ["CABG", "coronary bypass", "coronary artery bypass", "bypass surgery", "on pump CABG", "LIMA to LAD"]),
        heart("opcab", "Off-pump coronary artery bypass", ["OPCAB", "OPCABG", "off pump CABG", "off pump coronary bypass", "beating heart CABG"]),
        heart("midcab", "Minimally invasive coronary artery bypass", ["MIDCAB", "TECAB", "robotic CABG", "minimally invasive CABG", "robotic assisted CABG", "hybrid coronary revascularization"]),
        heart("avr", "Aortic valve replacement", ["AVR", "SAVR", "surgical aortic valve replacement", "mechanical AVR", "bioprosthetic AVR", "tissue AVR"]),
        heart("av-repair", "Aortic valve repair", ["AV repair", "aortic valvuloplasty", "aortic valve resuspension"], exact: ["AVr"]),
        heart("mini-avr", "Minimally invasive aortic valve replacement", ["mini AVR", "ministernotomy AVR", "mini sternotomy AVR", "right anterior thoracotomy AVR", "minimally invasive AVR", "MIAVR", "sutureless AVR"]),
        heart("mvr", "Mitral valve replacement", ["MVR", "mechanical MVR", "bioprosthetic MVR", "mitral replacement", "chordal sparing MVR"]),
        heart("mv-repair", "Mitral valve repair", ["MV repair", "mitral repair", "mitral valvuloplasty", "mitral annuloplasty", "mitral ring", "mitral valve repair with ring"], exact: ["MVr"]),
        heart("mini-mitral", "Minimally invasive mitral valve surgery", ["mini mitral", "robotic mitral valve repair", "robotic mitral repair", "right minithoracotomy mitral repair", "minimally invasive mitral valve repair", "MIMVS"]),
        heart("tvr", "Tricuspid valve replacement", ["TVR", "tricuspid replacement", "bioprosthetic TVR"]),
        heart("tv-repair", "Tricuspid valve repair", ["TV repair", "tricuspid repair", "tricuspid annuloplasty", "tricuspid ring", "De Vega annuloplasty"], exact: ["TVr"]),
        heart("pv-replacement", "Pulmonary valve replacement", ["pulmonic valve replacement", "surgical pulmonary valve replacement", "SPVR"]),
        heart("pv-repair", "Pulmonary valve repair", ["pulmonic valve repair", "pulmonary valvotomy"], exact: ["PVr"]),
        heart("dvr", "Double valve replacement", ["DVR", "aortic and mitral valve replacement", "double valve surgery", "triple valve surgery"]),
        heart("bentall", "Aortic root replacement", ["Bentall", "Bentall procedure", "modified Bentall", "composite valve graft", "root replacement", "aortic root replacement with composite graft"]),
        heart("valve-sparing-root", "Valve-sparing aortic root replacement", ["VSRR", "David procedure", "valve sparing root replacement", "valve sparing aortic root", "Yacoub procedure"]),
        heart("ascending-aorta", "Ascending aorta replacement", ["ascending aortic aneurysm repair", "ascending aortic replacement", "supracoronary graft", "hemiarch replacement", "hemiarch"]),
        heart("arch", "Aortic arch replacement", ["total arch replacement", "arch replacement", "aortic arch repair", "elephant trunk", "frozen elephant trunk", "FET"]),
        heart("type-a-dissection", "Type A aortic dissection repair", ["type A dissection", "type A dissection repair", "acute type A dissection", "aortic dissection repair", "TAAD repair", "ATAAD"]),
        heart("root-enlargement", "Aortic root enlargement", ["root enlargement", "aortic annular enlargement", "Nicks procedure", "Manouguian", "Konno", "Y incision root enlargement"]),
        heart("ross", "Ross procedure", ["Ross", "pulmonary autograft"]),
        heart("myectomy", "Septal myectomy", ["myectomy", "Morrow myectomy", "HCM myectomy", "HOCM myectomy", "transaortic septal myectomy"]),
        heart("asd-repair", "Atrial septal defect repair", ["ASD repair", "surgical ASD closure", "ASD patch closure", "sinus venosus defect repair", "surgical PFO closure"], ga, chest, mid),
        heart("vsd-repair", "Ventricular septal defect repair", ["VSD repair", "surgical VSD closure", "VSD patch closure", "post infarct VSD repair", "VSR repair"]),
        heart("pericardiectomy", "Pericardiectomy", ["pericardial stripping", "radical pericardiectomy", "pericardiectomy for constriction"]),
        heart("pericardial-window", "Pericardial window", ["subxiphoid pericardial window", "subxiphoid window", "pericardiostomy", "VATS pericardial window", "pericardial window for tamponade"], ga, chest, short),
        heart("redo-sternotomy", "Redo sternotomy", ["sternal re-entry", "sternal reentry", "reoperative sternotomy", "redo cardiac surgery", "re-do sternotomy"]),
        heart("mediastinal-reexploration", "Re-exploration for bleeding", ["take back for bleeding", "reexploration for bleeding", "mediastinal exploration", "mediastinal washout", "chest washout", "tamponade evacuation"], ga, chest, mid),
        heart("sternal-debridement", "Sternal debridement and closure", ["sternal wound debridement", "sternal rewiring", "sternal plating", "sternal dehiscence repair", "mediastinitis debridement", "delayed sternal closure", "chest closure"], ga, chest, mid),
        heart("lvad", "Left ventricular assist device implantation", ["LVAD", "LVAD implant", "LVAD implantation", "HeartMate 3", "HM3", "VAD implantation", "durable LVAD", "LVAD exchange"]),
        heart("rvad", "Right ventricular assist device", ["RVAD", "temporary RVAD", "CentriMag", "BiVAD", "RVAD insertion"]),
        heart("heart-transplant", "Heart transplant", ["OHT", "orthotopic heart transplant", "heart transplantation", "cardiac transplant", "HTx"]),
        heart("heart-lung-transplant", "Heart-lung transplant", ["heart lung transplant", "HLT", "heart and lung transplant"]),
        heart("ecmo", "ECMO cannulation", ["ECMO", "VA ECMO", "VV ECMO", "peripheral ECMO", "VA ECMO cannulation", "VV ECMO cannulation", "ECLS", "ECPR", "femoral ECMO cannulation"], ga, per, short, risk: false),
        heart("central-ecmo", "Central ECMO cannulation", ["central ECMO", "central cannulation", "ECMO via sternotomy"], ga, chest, mid),
        heart("ecmo-decannulation", "ECMO decannulation", ["decannulation", "VA ECMO decannulation", "VV ECMO decannulation"], ga, per, short, risk: false),
        heart("tavr", "Transcatheter aortic valve replacement", ["TAVR", "TAVI", "transfemoral TAVR", "TF TAVR", "transcatheter aortic valve implantation", "valve in valve TAVR", "ViV TAVR"], mac, per, short, risk: false),
        heart("tavr-chest", "TAVR, transapical or transaortic", ["transapical TAVR", "TA TAVR", "transapical TAVI", "transaortic TAVR", "direct aortic TAVR"], ga, chest, mid),
        heart("tavr-alternative", "TAVR, subclavian or transcaval", ["subclavian TAVR", "axillary TAVR", "transcaval TAVR", "transcarotid TAVR", "alternative access TAVR"], ga, per, mid, risk: false),
        heart("teer", "Transcatheter edge-to-edge repair", ["TEER", "MitraClip", "mitral TEER", "M-TEER", "PASCAL", "TriClip", "tricuspid TEER", "T-TEER", "edge to edge repair", "percutaneous mitral repair"], ga, per, mid, risk: false),
        heart("tmvr", "Transcatheter mitral valve replacement", ["TMVR", "transcatheter mitral valve", "mitral valve in valve", "mitral valve in ring", "transseptal mitral valve in valve"], ga, per, mid, risk: false),
        heart("ttvr", "Transcatheter tricuspid valve replacement", ["TTVR", "EVOQUE", "transcatheter tricuspid valve"], ga, per, mid, risk: false),
        heart("tpvr", "Transcatheter pulmonary valve replacement", ["TPVR", "Melody valve", "Harmony valve", "transcatheter pulmonary valve"], ga, per, mid, risk: false),
        heart("maze", "Surgical ablation (maze)", ["maze", "Cox maze", "Cox maze IV", "surgical AF ablation", "LAA clip", "AtriClip", "left atrial appendage ligation", "left atrial appendage clip"]),
        heart("cardiac-tumor", "Cardiac tumor resection", ["atrial myxoma excision", "myxoma resection", "myxoma", "cardiac mass excision", "papillary fibroelastoma resection"]),
        heart("pulmonary-endarterectomy", "Pulmonary endarterectomy", ["pulmonary thromboendarterectomy", "CTEPH surgery", "PTE surgery"]),
        heart("pulmonary-embolectomy", "Surgical pulmonary embolectomy", ["pulmonary embolectomy", "surgical embolectomy for PE", "open pulmonary embolectomy"]),
        heart("epicardial-leads", "Epicardial lead placement", ["epicardial leads", "epicardial pacing leads", "epicardial pacemaker", "epicardial LV lead"], ga, chest, short),
        heart("anomalous-coronary", "Anomalous coronary artery repair", ["anomalous coronary unroofing", "coronary unroofing", "AAOCA repair", "anomalous coronary repair"]),
    ]

    // MARK: Thoracic

    fileprivate static let thoracic: [Procedure] = [
        p("vats-lobectomy", "VATS lobectomy", ["VATS lobe", "thoracoscopic lobectomy", "video assisted thoracoscopic lobectomy", "lobectomy", "lung lobectomy", "pulmonary lobectomy"], gaRa, chest, mid, risk: true, side: true),
        p("robotic-lobectomy", "Robotic lobectomy", ["RATS lobectomy", "robotic assisted lobectomy", "robotic lung lobectomy", "RATS"], gaRa, chest, mid, risk: true, side: true),
        p("open-lobectomy", "Lobectomy by thoracotomy", ["open lobectomy", "thoracotomy lobectomy", "thoracotomy and lobectomy", "thoracotomy with lobectomy"], gaNx, chest, mid, risk: true, side: true),
        p("segmentectomy", "Anatomic segmentectomy", ["segmentectomy", "VATS segmentectomy", "robotic segmentectomy", "lung segmentectomy", "pulmonary segmentectomy"], gaRa, chest, mid, risk: true, side: true),
        p("wedge", "VATS wedge resection", ["VATS wedge", "wedge resection", "lung wedge resection", "VATS lung biopsy", "lung biopsy", "thoracoscopic wedge resection", "robotic wedge resection", "VATS"], gaRa, chest, short, risk: true, side: true),
        p("pneumonectomy", "Pneumonectomy", ["completion pneumonectomy", "extrapleural pneumonectomy", "EPP", "sleeve pneumonectomy", "intrapericardial pneumonectomy"], gaNx, chest, long, risk: true, side: true),
        p("sleeve-lobectomy", "Sleeve lobectomy", ["sleeve resection", "bronchial sleeve resection", "bronchoplastic lobectomy"], gaNx, chest, long, risk: true, side: true),
        p("lvrs", "Lung volume reduction surgery", ["LVRS", "lung volume reduction", "bullectomy", "VATS bullectomy"], gaRa, chest, mid, risk: true, side: true),
        p("decortication", "Decortication", ["VATS decortication", "empyema decortication", "pleural decortication", "open decortication", "VATS for empyema"], gaRa, chest, mid, risk: true, side: true),
        p("pleurodesis", "VATS pleurodesis or blebectomy", ["pleurodesis", "talc pleurodesis", "VATS talc pleurodesis", "pleurectomy", "VATS pleurectomy", "blebectomy", "VATS blebectomy", "VATS for pneumothorax"], gaRa, chest, short, risk: true, side: true),
        p("pleural-catheter", "Tunneled pleural catheter", ["PleurX", "PleurX catheter", "indwelling pleural catheter", "IPC placement", "tunneled pleural catheter placement"], mac, per, short, side: true),
        p("chest-tube", "Chest tube insertion", ["chest tube", "tube thoracostomy", "thoracostomy", "pigtail chest tube", "chest drain"], mac, per, short, side: true),
        p("mediastinoscopy", "Mediastinoscopy", ["cervical mediastinoscopy", "mediastinal lymph node biopsy", "Chamberlain procedure", "anterior mediastinotomy"], ga, chest, short, risk: true),
        p("thymectomy", "Thymectomy", ["VATS thymectomy", "robotic thymectomy", "transsternal thymectomy", "thymoma resection", "anterior mediastinal mass resection", "mediastinal mass excision"], ga, chest, mid, risk: true),
        p("ivor-lewis", "Ivor Lewis esophagectomy", ["Ivor Lewis", "esophagectomy", "esophagogastrectomy", "open esophagectomy", "transthoracic esophagectomy"], gaNx, chest, long, risk: true),
        p("mie", "Minimally invasive esophagectomy", ["MIE", "robotic esophagectomy", "RAMIE", "thoracoscopic esophagectomy", "minimally invasive Ivor Lewis"], gaRa, chest, long, risk: true),
        p("transhiatal-esophagectomy", "Transhiatal esophagectomy", ["transhiatal", "Orringer esophagectomy", "blunt esophagectomy"], gaNx, chest, long, risk: true),
        p("mckeown", "McKeown esophagectomy", ["McKeown", "three field esophagectomy", "tri-incisional esophagectomy", "three incision esophagectomy"], gaNx, chest, long, risk: true),
        p("rib-fixation", "Rib fracture fixation", ["rib plating", "SSRF", "surgical stabilization of rib fractures", "rib ORIF", "rib fixation"], gaRa, per, mid, side: true),
        p("chest-wall-resection", "Chest wall resection", ["chest wall tumor resection", "chest wall reconstruction", "sternal resection", "sternectomy"], ga, chest, long, risk: true, side: true),
        p("diaphragm-plication", "Diaphragm plication", ["diaphragmatic plication", "VATS diaphragm plication", "robotic diaphragm plication", "diaphragm pacing"], ga, chest, mid, risk: true, side: true),
        p("tracheal-resection", "Tracheal resection", ["tracheal resection and reconstruction", "tracheal reconstruction", "laryngotracheal resection", "cricotracheal resection", "slide tracheoplasty"], ga, per, long),
        p("sympathectomy", "Thoracoscopic sympathectomy", ["sympathectomy", "VATS sympathectomy", "ETS", "endoscopic thoracic sympathectomy", "sympathectomy for hyperhidrosis"], ga, chest, short, risk: true, side: true),
        p("thoracotomy", "Exploratory thoracotomy", ["thoracotomy", "trauma thoracotomy", "clamshell thoracotomy", "resuscitative thoracotomy", "open thoracotomy"], ga, chest, mid, risk: true, side: true),
    ]

    // MARK: Transplant

    fileprivate static let transplant: [Procedure] = [
        p("liver-transplant", "Liver transplant", ["OLT", "orthotopic liver transplant", "liver transplantation", "deceased donor liver transplant", "living donor liver transplant", "LDLT", "OLTx", "liver retransplant"], ga, upper, long, risk: true, echo: true),
        p("donor-hepatectomy", "Living donor hepatectomy", ["donor hepatectomy", "living liver donation", "donor right hepatectomy", "living donor right hepatectomy"], ga, upper, long, risk: true),
        p("kidney-transplant", "Kidney transplant", ["renal transplant", "kidney transplantation", "renal transplantation", "deceased donor kidney transplant", "living donor kidney transplant", "LDKT", "DDKT", "KTx"], ga, per, mid),
        p("donor-nephrectomy", "Living donor nephrectomy", ["donor nephrectomy", "laparoscopic donor nephrectomy", "hand assisted donor nephrectomy", "robotic donor nephrectomy"], ga, upper, mid, risk: true, side: true),
        p("pancreas-transplant", "Pancreas transplant", ["pancreas transplantation", "SPK", "simultaneous pancreas kidney transplant", "simultaneous pancreas and kidney transplant", "PAK", "pancreas after kidney transplant"], ga, upper, long, risk: true),
        p("bilateral-lung-transplant", "Bilateral lung transplant", ["BLT", "BSLT", "double lung transplant", "bilateral sequential lung transplant", "lung transplant", "lung transplantation"], ga, chest, long, risk: true, echo: true),
        p("single-lung-transplant", "Single lung transplant", ["SLT", "single lung transplantation", "unilateral lung transplant"], ga, chest, long, risk: true, side: true, echo: true),
        p("intestinal-transplant", "Intestinal transplant", ["small bowel transplant", "intestine transplant", "multivisceral transplant", "multivisceral transplantation"], ga, upper, long, risk: true),
        p("transplant-nephrectomy", "Transplant nephrectomy", ["allograft nephrectomy", "transplant kidney removal", "graft nephrectomy"], ga, per, mid),
    ]

    // MARK: Urology

    fileprivate static let urology: [Procedure] = [
        p("cystoscopy", "Cystoscopy", ["cysto", "cystourethroscopy", "rigid cystoscopy", "flexible cystoscopy", "cystoscopy with biopsy", "bladder biopsy", "cystoscopy with bladder biopsy", "cystoscopy and hydrodistension"], ga, per, short),
        p("ureteral-stent", "Cystoscopy with ureteral stent", ["ureteral stent", "ureteral stent placement", "cysto stent", "cysto with stent", "cystoscopy and stent", "ureteral stent exchange", "stent exchange", "double J stent", "JJ stent", "retrograde pyelogram", "RPG", "ureteral stent removal"], ga, per, short, side: true),
        p("ureteroscopy", "Ureteroscopy with laser lithotripsy", ["URS", "ureteroscopy", "URS laser", "laser lithotripsy", "holmium laser lithotripsy", "ureteroscopy with stent", "flexible ureteroscopy", "RIRS", "ureteroscopic stone extraction", "basket extraction"], ga, per, short, side: true),
        p("pcnl", "Percutaneous nephrolithotomy", ["PCNL", "PNL", "mini PCNL", "percutaneous nephrolithotripsy", "perc nephrolithotomy", "ECIRS"], ga, per, mid, side: true),
        p("eswl", "Shock wave lithotripsy", ["ESWL", "SWL", "lithotripsy", "extracorporeal shock wave lithotripsy"], mac, per, short, side: true),
        p("turbt", "Transurethral resection of bladder tumor", ["TURBT", "TUR bladder tumor", "bladder tumor resection", "TURBT with blue light", "re-TURBT", "transurethral resection of bladder"], ga, per, short),
        p("turp", "Transurethral resection of prostate", ["TURP", "bipolar TURP", "TUR prostate", "transurethral prostatectomy", "TUIP", "transurethral resection of the prostate"], nx, per, short),
        p("holep", "Laser enucleation of prostate", ["HoLEP", "holmium laser enucleation of the prostate", "ThuLEP", "laser enucleation of the prostate", "GreenLight PVP", "photoselective vaporization of the prostate", "laser prostatectomy", "Aquablation"], ga, per, mid),
        p("urolift", "Prostatic urethral lift", ["UroLift", "Rezum", "prostatic urethral lift", "water vapor therapy prostate"], mac, per, short),
        p("ralp", "Robotic radical prostatectomy", ["RALP", "RARP", "robotic prostatectomy", "robot assisted laparoscopic prostatectomy", "robotic assisted radical prostatectomy", "radical prostatectomy", "prostatectomy", "laparoscopic radical prostatectomy", "RALP with lymph node dissection"], ga, per, mid, risk: true),
        p("open-prostatectomy", "Open radical retropubic prostatectomy", ["RRP", "open prostatectomy", "radical retropubic prostatectomy", "open radical prostatectomy", "simple prostatectomy", "open simple prostatectomy"], gaNx, per, mid),
        p("radical-cystectomy", "Radical cystectomy", ["cystectomy", "open radical cystectomy", "radical cystectomy with ileal conduit", "cystectomy with ileal conduit", "cystoprostatectomy", "anterior exenteration", "ileal conduit", "neobladder", "Indiana pouch"], gaNx, upper, long, risk: true),
        p("robotic-cystectomy", "Robotic radical cystectomy", ["RARC", "robotic cystectomy", "robot assisted radical cystectomy", "robotic cystectomy with intracorporeal diversion"], ga, upper, long, risk: true),
        p("lap-nephrectomy", "Laparoscopic nephrectomy", ["nephrectomy", "radical nephrectomy", "laparoscopic radical nephrectomy", "robotic nephrectomy", "robotic radical nephrectomy", "hand assisted nephrectomy", "laparoscopic simple nephrectomy", "nephroureterectomy", "laparoscopic nephroureterectomy", "robotic nephroureterectomy"], ga, upper, mid, risk: true, side: true),
        p("partial-nephrectomy", "Robotic partial nephrectomy", ["RAPN", "partial nephrectomy", "robot assisted partial nephrectomy", "laparoscopic partial nephrectomy", "LPN", "robotic partial nephrectomy"], ga, upper, mid, risk: true, side: true),
        p("open-nephrectomy", "Open nephrectomy", ["open radical nephrectomy", "open partial nephrectomy", "flank nephrectomy", "open simple nephrectomy", "open nephroureterectomy"], gaNx, upper, mid, side: true),
        p("ivc-thrombectomy", "Nephrectomy with IVC thrombectomy", ["IVC thrombectomy", "radical nephrectomy with IVC thrombectomy", "caval thrombectomy", "IVC tumor thrombectomy", "nephrectomy with caval thrombectomy"], gaNx, upper, long, risk: true, side: true),
        p("pyeloplasty", "Pyeloplasty", ["robotic pyeloplasty", "laparoscopic pyeloplasty", "UPJ obstruction repair", "dismembered pyeloplasty", "UPJO repair"], ga, upper, mid, risk: true, side: true),
        p("ureteral-reimplant", "Ureteral reimplantation", ["ureteral reimplant", "ureteroneocystostomy", "robotic ureteral reimplantation", "psoas hitch", "Boari flap", "ureteroureterostomy"], ga, per, mid, side: true),
        p("orchiectomy", "Orchiectomy", ["radical orchiectomy", "inguinal orchiectomy", "simple orchiectomy", "bilateral orchiectomy", "testicular prosthesis"], ga, per, short, side: true),
        p("scrotal-exploration", "Scrotal exploration for torsion", ["testicular torsion", "scrotal exploration", "detorsion", "orchiopexy for torsion", "detorsion and orchiopexy"], ga, per, short, side: true),
        p("hydrocelectomy", "Hydrocelectomy", ["hydrocele repair", "hydrocele", "adult hydrocele", "spermatocelectomy", "spermatocele excision"], ga, per, short, side: true),
        p("varicocelectomy", "Varicocelectomy", ["varicocele repair", "varicocele ligation", "microsurgical varicocelectomy", "varicocele"], ga, per, short, side: true),
        p("vasectomy", "Vasectomy", ["no scalpel vasectomy", "bilateral vasectomy"], mac, per, short),
        p("vasectomy-reversal", "Vasectomy reversal", ["vasovasostomy", "vasoepididymostomy", "microsurgical vasectomy reversal"], ga, per, mid),
        p("circumcision", "Circumcision", ["adult circumcision", "dorsal slit", "pediatric circumcision", "redo circumcision", "circumcision revision"], ga, per, short),
        p("penile-prosthesis", "Penile prosthesis insertion", ["IPP", "inflatable penile prosthesis", "penile implant", "penile prosthesis", "penile prosthesis revision"], ga, per, short),
        p("aus", "Artificial urinary sphincter", ["AUS", "AUS placement", "artificial urinary sphincter placement", "male sling", "male urethral sling"], ga, per, short),
        p("urethroplasty", "Urethroplasty", ["urethral stricture repair", "buccal graft urethroplasty", "buccal mucosa graft urethroplasty", "DVIU", "urethrotomy", "direct vision internal urethrotomy", "urethral dilation"], ga, per, mid),
        p("suprapubic-catheter", "Suprapubic catheter placement", ["SPT", "suprapubic tube", "SP tube", "suprapubic cystostomy", "SPC placement", "suprapubic catheter"], ga, per, short),
        p("sacral-neuromodulation", "Sacral neuromodulation", ["InterStim", "sacral nerve stimulator", "SNS", "InterStim stage 1", "InterStim stage 2", "sacral neuromodulator"], mac, per, short),
        p("bladder-botox", "Intravesical Botox injection", ["bladder Botox", "cystoscopy with Botox", "Botox bladder injection", "intradetrusor Botox", "bulking agent injection"], mac, per, short),
        p("prostate-biopsy", "Prostate biopsy or brachytherapy", ["prostate biopsy", "transperineal prostate biopsy", "TRUS biopsy", "fusion biopsy", "prostate brachytherapy", "brachytherapy seeds", "fiducial placement", "SpaceOAR", "hydrogel spacer"], mac, per, short),
        p("cystolitholapaxy", "Cystolitholapaxy", ["bladder stone removal", "cystolithotripsy", "bladder stones", "cystolithalopaxy"], ga, per, short),
    ]

    // MARK: Gynecology and obstetrics

    fileprivate static let gynecology: [Procedure] = [
        p("cesarean", "Cesarean delivery", ["C-section", "CS", "LTCS", "cesarean section", "cesarean", "c section", "repeat cesarean", "repeat C-section", "primary cesarean", "low transverse cesarean section", "RCS", "PLTCS"], nx, per, short, risk: true),
        p("cesarean-hysterectomy", "Cesarean hysterectomy", ["cesarean hysterectomy for accreta", "placenta accreta", "accreta", "placenta accreta spectrum", "PAS", "percreta"], ga, upper, long, risk: true),
        p("labor-epidural", "Labor epidural", ["labor analgesia", "epidural for labor", "labour epidural", "labor CSE", "CSE for labor", "DPE for labor", "epidural analgesia for labor"], nx, per, short),
        p("cerclage", "Cervical cerclage", ["cerclage", "McDonald cerclage", "Shirodkar cerclage", "transvaginal cerclage", "cerclage removal"], nx, per, short),
        p("abdominal-cerclage", "Transabdominal cerclage", ["abdominal cerclage", "laparoscopic cerclage", "TAC cerclage"], ga, per, short, risk: true),
        p("ecv", "External cephalic version", ["ECV", "version for breech", "external version"], nx, per, short),
        p("postpartum-tubal", "Postpartum tubal ligation", ["PPTL", "postpartum BTL", "postpartum tubal", "postpartum salpingectomy", "tubal ligation after delivery"], nx, per, short, risk: true),
        p("retained-placenta", "Retained placenta or postpartum D&C", ["retained placenta", "manual extraction of placenta", "manual removal of placenta", "retained products of conception", "postpartum D&C", "postpartum hemorrhage exam"], nx, per, short),
        p("laceration-repair", "Repair of obstetric laceration", ["perineal laceration repair", "fourth degree laceration repair", "third degree laceration repair", "OASIS repair", "cervical laceration repair"], nx, per, short),
        p("dc", "Dilation and curettage", ["D&C", "D and C", "suction D&C", "suction curettage", "uterine evacuation", "D&C for missed abortion", "manual vacuum aspiration", "endometrial biopsy"], mac, per, short),
        p("de", "Dilation and evacuation", ["D&E", "D and E", "second trimester D&E", "dilation and extraction"], mac, per, short),
        p("hysteroscopy", "Hysteroscopy", ["operative hysteroscopy", "hysteroscopic myomectomy", "hysteroscopic polypectomy", "hysteroscopy with D&C", "hysteroscopy D&C", "endometrial ablation", "NovaSure", "MyoSure", "hysteroscopic septum resection"], ga, per, short),
        p("tah", "Total abdominal hysterectomy", ["TAH", "TAH BSO", "TAH-BSO", "abdominal hysterectomy", "hysterectomy", "hyst", "open hysterectomy", "supracervical hysterectomy"], ga, per, mid, risk: true),
        p("tlh", "Laparoscopic hysterectomy", ["TLH", "TLH BSO", "total laparoscopic hysterectomy", "LAVH", "laparoscopic assisted vaginal hysterectomy", "laparoscopic supracervical hysterectomy", "LSH", "laparoscopic hyst"], ga, per, mid, risk: true),
        p("ralh", "Robotic hysterectomy", ["RALH", "robotic assisted laparoscopic hysterectomy", "robotic TLH", "robotic hysterectomy BSO", "robotic total hysterectomy"], ga, per, mid, risk: true),
        p("tvh", "Vaginal hysterectomy", ["TVH", "total vaginal hysterectomy", "vaginal hysterectomy with repair"], ga, per, short, risk: true),
        p("radical-hysterectomy", "Radical hysterectomy", ["Wertheim", "Wertheim hysterectomy", "radical hysterectomy with pelvic lymphadenectomy", "robotic radical hysterectomy", "radical trachelectomy"], ga, per, long, risk: true),
        p("debulking", "Ovarian cancer debulking", ["debulking", "tumor debulking", "interval debulking", "cytoreduction ovarian cancer", "staging laparotomy", "omentectomy", "gynecologic oncology staging"], gaNx, upper, long, risk: true),
        p("myomectomy", "Myomectomy", ["abdominal myomectomy", "open myomectomy", "robotic myomectomy", "laparoscopic myomectomy", "fibroid removal"], ga, per, mid, risk: true),
        p("salpingo-oophorectomy", "Laparoscopic salpingo-oophorectomy", ["BSO", "laparoscopic BSO", "salpingo oophorectomy", "salpingo-oophorectomy", "oophorectomy", "USO", "unilateral salpingo oophorectomy", "RRSO", "risk reducing salpingo oophorectomy", "adnexectomy"], ga, per, short, risk: true, side: true),
        p("ovarian-cystectomy", "Laparoscopic ovarian cystectomy", ["ovarian cystectomy", "ovarian cyst removal", "ovarian cyst", "ovarian detorsion", "ovarian torsion", "laparoscopic detorsion"], ga, per, short, risk: true, side: true),
        p("salpingectomy", "Laparoscopic salpingectomy", ["salpingectomy", "ectopic pregnancy", "ruptured ectopic", "salpingostomy", "laparoscopy for ectopic", "opportunistic salpingectomy"], ga, per, short, risk: true, side: true),
        p("btl", "Laparoscopic tubal ligation", ["BTL", "tubal ligation", "bilateral tubal ligation", "laparoscopic BTL", "Filshie clips", "tubal sterilization", "bilateral salpingectomy for sterilization"], ga, per, short, risk: true),
        p("gyn-laparoscopy", "Operative gynecologic laparoscopy", ["pelvic laparoscopy", "laparoscopic excision of endometriosis", "endometriosis excision", "excision of endometriosis", "laparoscopic fulguration of endometriosis", "chromopertubation", "gynecologic laparoscopy"], ga, per, short, risk: true),
        p("sacrocolpopexy", "Sacrocolpopexy", ["LSC", "laparoscopic sacrocolpopexy", "robotic sacrocolpopexy", "RSC", "abdominal sacrocolpopexy", "sacrohysteropexy"], ga, per, mid, risk: true),
        p("prolapse-repair", "Vaginal prolapse repair", ["anterior repair", "posterior repair", "A&P repair", "anterior and posterior colporrhaphy", "colporrhaphy", "sacrospinous ligament fixation", "SSLF", "uterosacral ligament suspension", "colpocleisis", "LeFort colpocleisis"], ga, per, mid),
        p("sling", "Midurethral sling", ["TVT", "TOT", "sling", "urethral sling", "transobturator tape", "retropubic sling", "mini sling", "midurethral sling with cystoscopy"], ga, per, short),
        p("burch", "Burch colposuspension", ["Burch", "Burch procedure", "retropubic urethropexy"], ga, per, short),
        p("leep", "LEEP or cone biopsy", ["LEEP", "cone biopsy", "cold knife cone", "CKC", "LLETZ", "cervical conization", "conization"], mac, per, short),
        p("vulvectomy", "Vulvectomy", ["radical vulvectomy", "partial vulvectomy", "wide local excision vulva", "vulvar excision", "vulvar lesion excision"], ga, per, mid),
        p("bartholin", "Bartholin cyst drainage", ["Bartholin cyst", "Bartholin abscess", "marsupialization", "Word catheter", "Bartholin gland excision"], mac, per, short),
        p("pelvic-exenteration", "Pelvic exenteration", ["total pelvic exenteration", "posterior exenteration", "exenteration"], gaNx, upper, long, risk: true),
        p("oocyte-retrieval", "Oocyte retrieval", ["egg retrieval", "transvaginal oocyte retrieval", "IVF retrieval", "TVOR"], mac, per, short),
        p("exit-procedure", "EXIT procedure", ["ex utero intrapartum treatment"], ga, per, short, risk: true, exact: ["EXIT"]),
        p("fetal-surgery", "Fetal surgery", ["open fetal surgery", "fetal myelomeningocele repair", "in utero MMC repair", "fetoscopic surgery", "fetoscopic laser ablation", "fetoscopic laser for TTTS", "FETO"], ga, per, mid, risk: true),
    ]

    // MARK: Orthopedics

    fileprivate static let orthopedics: [Procedure] = [
        p("tka", "Total knee arthroplasty", ["TKA", "TKR", "total knee replacement", "knee replacement", "knee arthroplasty", "primary TKA", "robotic TKA", "MAKO TKA", "total knee"], nxRa, per, short, side: true),
        p("uka", "Unicompartmental knee arthroplasty", ["UKA", "UKR", "partial knee replacement", "partial knee", "unicondylar knee", "uni knee", "unicompartmental knee replacement", "patellofemoral arthroplasty"], nxRa, per, short, side: true),
        p("revision-tka", "Revision total knee arthroplasty", ["revision TKA", "revision TKR", "revision knee replacement", "knee revision", "TKA explant", "two stage revision TKA", "knee spacer", "antibiotic spacer knee"], gaRa, per, mid, side: true),
        p("tha", "Total hip arthroplasty", ["THA", "THR", "total hip replacement", "hip replacement", "hip arthroplasty", "primary THA", "anterior hip replacement", "direct anterior THA", "anterior THA", "posterior THA", "robotic THA", "total hip"], nx, per, short, side: true),
        p("revision-tha", "Revision total hip arthroplasty", ["revision THA", "revision THR", "revision hip replacement", "hip revision", "THA explant", "hip spacer", "acetabular revision", "femoral revision"], ga, per, long, side: true),
        p("hip-hemi", "Hip hemiarthroplasty", ["hemiarthroplasty", "hip hemi", "bipolar hemiarthroplasty", "hemiarthroplasty for femoral neck fracture", "femoral neck fracture"], nx, per, short, side: true),
        p("hip-fracture-fixation", "Hip fracture fixation", ["hip fracture", "hip ORIF", "ORIF hip", "IM nail hip", "cephalomedullary nail", "CMN", "gamma nail", "TFN", "TFNA", "PFNA", "intertrochanteric fracture", "intertrochanteric fracture fixation", "DHS", "dynamic hip screw", "sliding hip screw", "hip pinning", "percutaneous hip pinning", "cannulated screws hip"], nx, per, short, side: true),
        p("femoral-nail", "Femoral intramedullary nail", ["femur IMN", "IMN femur", "femoral nail", "femur nail", "IM nail femur", "femoral shaft fracture", "femur fracture", "retrograde femoral nail", "antegrade femoral nail"], ga, per, mid, side: true),
        p("distal-femur-orif", "Distal femur ORIF", ["ORIF distal femur", "distal femur fracture", "supracondylar femur fracture", "periprosthetic femur fracture"], ga, per, mid, side: true),
        p("patella-orif", "Patella ORIF", ["ORIF patella", "patella fracture", "patellar fracture fixation", "patellar tendon repair", "quadriceps tendon repair", "quad tendon repair"], gaRa, per, short, side: true),
        p("tibial-plateau-orif", "Tibial plateau ORIF", ["ORIF tibial plateau", "tibial plateau fracture", "tibial plateau fracture fixation"], gaRa, per, mid, side: true),
        p("tibial-nail", "Tibial intramedullary nail", ["tibia IMN", "IMN tibia", "tibial nail", "tibia nail", "IM nail tibia", "tibial shaft fracture", "tibia fracture"], ga, per, short, side: true),
        p("pilon-orif", "Tibial pilon ORIF", ["pilon fracture", "pilon ORIF", "ORIF pilon", "plafond fracture"], gaRa, per, mid, side: true),
        p("ankle-orif", "Ankle ORIF", ["ORIF ankle", "ankle fracture", "ankle fracture fixation", "bimalleolar fracture", "trimalleolar fracture", "bimalleolar ankle fracture", "trimalleolar ankle fracture", "lateral malleolus ORIF", "syndesmosis fixation"], gaRa, per, short, side: true),
        p("calcaneus-orif", "Calcaneus ORIF", ["ORIF calcaneus", "calcaneal fracture", "calcaneus fracture"], gaRa, per, mid, side: true),
        p("lisfranc-orif", "Lisfranc or midfoot ORIF", ["Lisfranc", "Lisfranc ORIF", "Lisfranc injury", "midfoot ORIF", "metatarsal ORIF", "metatarsal fracture"], gaRa, per, short, side: true),
        p("ex-fix", "External fixation", ["ex fix", "external fixator", "spanning external fixator", "ex fix removal", "external fixator removal", "frame removal", "pelvic ex fix"], ga, per, short, side: true),
        p("pelvic-orif", "Pelvic ring fixation", ["pelvic ORIF", "ORIF pelvis", "pelvic fracture fixation", "pelvic ring ORIF", "SI screws", "sacroiliac screw fixation", "pubic symphysis ORIF"], ga, per, mid),
        p("acetabular-orif", "Acetabular ORIF", ["ORIF acetabulum", "acetabular fracture", "acetabulum fracture", "acetabular fracture fixation"], ga, per, long, side: true),
        p("clavicle-orif", "Clavicle ORIF", ["ORIF clavicle", "clavicle fracture", "clavicle fracture fixation", "AC joint reconstruction", "acromioclavicular joint reconstruction"], gaRa, per, short, side: true),
        p("proximal-humerus-orif", "Proximal humerus ORIF", ["ORIF proximal humerus", "proximal humerus fracture", "proximal humeral fracture"], gaRa, per, mid, side: true),
        p("humeral-shaft-orif", "Humeral shaft ORIF", ["ORIF humerus", "humeral shaft fracture", "humerus fracture", "humeral nail", "humerus IMN"], gaRa, per, mid, side: true),
        p("distal-humerus-orif", "Distal humerus ORIF", ["ORIF distal humerus", "distal humerus fracture", "elbow ORIF", "intercondylar humerus fracture"], gaRa, per, mid, side: true),
        p("olecranon-orif", "Olecranon or radial head ORIF", ["ORIF olecranon", "olecranon fracture", "olecranon ORIF", "radial head ORIF", "radial head fracture", "radial head arthroplasty", "radial head replacement", "elbow fracture"], gaRa, per, short, side: true),
        p("forearm-orif", "Forearm ORIF", ["both bone forearm fracture", "both bone forearm ORIF", "radius and ulna ORIF", "ORIF radius and ulna", "ulnar shaft ORIF", "forearm fracture", "radial shaft fracture"], gaRa, per, short, side: true),
        p("distal-radius-orif", "Distal radius ORIF", ["ORIF distal radius", "distal radius fracture", "DRF", "wrist fracture", "wrist ORIF", "ORIF wrist", "volar plating", "distal radius CRPP"], raMac, per, short, side: true),
        p("scaphoid", "Scaphoid fixation", ["scaphoid ORIF", "scaphoid fracture", "scaphoid nonunion", "scaphoid screw"], raMac, per, short, side: true),
        p("hand-fracture", "Hand fracture fixation", ["metacarpal fracture", "metacarpal ORIF", "phalanx fracture", "phalangeal fracture", "finger fracture", "boxer fracture", "CRPP hand", "CRPP finger", "finger pinning"], raMac, per, short, side: true),
        p("carpal-tunnel", "Carpal tunnel release", ["CTR", "carpal tunnel", "open carpal tunnel release", "endoscopic carpal tunnel release", "ECTR"], mac, per, short, side: true),
        p("trigger-finger", "Trigger finger release", ["trigger finger", "trigger thumb", "trigger thumb release", "A1 pulley release", "de Quervain release", "de Quervain's release"], mac, per, short, side: true),
        p("cubital-tunnel", "Cubital tunnel release", ["cubital tunnel", "ulnar nerve transposition", "ulnar nerve decompression", "ulnar nerve release"], raMac, per, short, side: true),
        p("dupuytren", "Dupuytren fasciectomy", ["Dupuytren", "Dupuytren's contracture", "Dupuytren's release", "palmar fasciectomy", "needle aponeurotomy"], raMac, per, short, side: true),
        p("hand-tendon", "Hand tendon repair", ["flexor tendon repair", "extensor tendon repair", "tendon repair hand", "finger tendon repair", "tendon transfer hand"], raMac, per, short, side: true),
        p("wrist-arthroscopy", "Wrist arthroscopy or ganglion excision", ["wrist arthroscopy", "wrist scope", "TFCC repair", "TFCC debridement", "ganglion cyst excision", "ganglion excision", "dorsal ganglion", "volar ganglion"], raMac, per, short, side: true),
        p("cmc-arthroplasty", "Thumb CMC arthroplasty", ["CMC arthroplasty", "LRTI", "trapeziectomy", "basal joint arthroplasty", "thumb arthritis surgery", "CMC suspensionplasty"], raMac, per, short, side: true),
        p("replant", "Digit replantation", ["replantation", "finger replant", "finger replantation", "hand replant", "thumb replant", "digit revascularization"], gaRa, per, long, side: true),
        p("finger-amputation", "Finger amputation", ["digit amputation", "fingertip amputation", "revision amputation finger", "finger revision amputation"], raMac, per, short, side: true),
        p("shoulder-arthroscopy", "Shoulder arthroscopy", ["shoulder scope", "arthroscopic subacromial decompression", "subacromial decompression", "acromioplasty", "distal clavicle excision", "biceps tenodesis", "labral repair", "SLAP repair", "capsular release", "shoulder arthroscopic debridement"], gaRa, per, short, side: true),
        p("rotator-cuff", "Rotator cuff repair", ["RCR", "ARCR", "rotator cuff", "rotator cuff tear repair", "arthroscopic rotator cuff repair", "mini open rotator cuff repair", "superior capsular reconstruction"], gaRa, per, mid, side: true),
        p("shoulder-stabilization", "Shoulder stabilization", ["Bankart", "Bankart repair", "Latarjet", "Latarjet procedure", "arthroscopic stabilization", "shoulder instability surgery", "remplissage"], gaRa, per, mid, side: true),
        p("tsa", "Total shoulder arthroplasty", ["TSA", "anatomic TSA", "total shoulder replacement", "shoulder replacement", "shoulder arthroplasty", "shoulder hemiarthroplasty", "total shoulder"], gaRa, per, mid, side: true),
        p("rtsa", "Reverse total shoulder arthroplasty", ["rTSA", "RSA", "reverse shoulder", "reverse total shoulder", "reverse shoulder replacement", "reverse shoulder arthroplasty", "revision shoulder arthroplasty"], gaRa, per, mid, side: true),
        p("elbow", "Elbow arthroscopy or tendon repair", ["elbow arthroscopy", "elbow scope", "tennis elbow release", "lateral epicondylitis debridement", "distal biceps repair", "distal biceps tendon repair", "UCL reconstruction", "Tommy John surgery", "total elbow arthroplasty", "elbow contracture release"], gaRa, per, short, side: true),
        p("knee-arthroscopy", "Knee arthroscopy", ["knee scope", "arthroscopic meniscectomy", "meniscectomy", "partial meniscectomy", "meniscus repair", "meniscal repair", "chondroplasty", "knee arthroscopic debridement", "arthroscopic knee surgery", "loose body removal knee"], ga, per, short, side: true),
        p("acl", "ACL reconstruction", ["ACL", "ACLR", "anterior cruciate ligament reconstruction", "ACL repair", "PCL reconstruction", "multiligament knee reconstruction", "MPFL reconstruction"], gaRa, per, mid, side: true),
        p("osteotomy-knee", "Knee osteotomy", ["HTO", "high tibial osteotomy", "tibial osteotomy", "distal femoral osteotomy", "DFO", "tibial tubercle osteotomy", "TTO"], gaRa, per, mid, side: true),
        p("hip-arthroscopy", "Hip arthroscopy", ["hip scope", "FAI surgery", "femoroacetabular impingement", "hip labral repair", "hip labral reconstruction"], ga, per, mid, side: true),
        p("pao", "Periacetabular osteotomy", ["PAO", "Ganz osteotomy", "Bernese osteotomy"], gaNx, per, long, side: true),
        p("achilles", "Achilles tendon repair", ["Achilles repair", "Achilles rupture repair", "Achilles tendon rupture", "Achilles tendon reconstruction", "gastrocnemius recession", "Strayer procedure"], gaRa, per, short, side: true),
        p("bunionectomy", "Bunionectomy", ["bunion surgery", "bunion", "hallux valgus correction", "Lapidus", "Lapidus bunionectomy", "chevron osteotomy", "Akin osteotomy", "first MTP fusion", "hammertoe correction", "hammer toe"], raMac, per, short, side: true),
        p("ankle-arthroscopy", "Ankle arthroscopy or ligament repair", ["ankle arthroscopy", "ankle scope", "ankle arthroscopic debridement", "Brostrom", "Brostrom repair", "lateral ankle ligament reconstruction", "peroneal tendon repair"], gaRa, per, short, side: true),
        p("ankle-fusion", "Ankle fusion or replacement", ["ankle fusion", "ankle arthrodesis", "total ankle arthroplasty", "total ankle replacement", "subtalar fusion", "triple arthrodesis", "hindfoot fusion", "flatfoot reconstruction"], gaRa, per, mid, side: true),
        p("hardware-removal", "Hardware removal", ["removal of hardware", "ROH", "implant removal", "screw removal", "plate removal", "removal of orthopedic hardware"], ga, per, short, side: true),
        p("joint-washout", "Joint irrigation and debridement", ["septic joint", "septic arthritis washout", "joint washout", "knee washout", "I&D knee", "arthroscopic washout", "irrigation and debridement", "DAIR", "polyethylene exchange", "I&D septic joint"], ga, per, short, side: true),
        p("mua", "Manipulation under anesthesia", ["MUA", "knee manipulation", "closed reduction", "closed reduction hip dislocation", "hip dislocation reduction", "shoulder dislocation reduction", "closed reduction of dislocation"], ga, per, short, side: true),
        p("bone-tumor", "Bone or soft tissue sarcoma resection", ["sarcoma resection", "limb salvage", "endoprosthesis", "tumor prosthesis", "radical resection of sarcoma", "bone tumor resection"], ga, per, long, side: true),
    ]

    // MARK: Spine

    fileprivate static let spine: [Procedure] = [
        p("acdf", "Anterior cervical discectomy and fusion", ["ACDF", "single level ACDF", "one level ACDF", "anterior cervical fusion", "anterior cervical discectomy"], ga, per, short),
        p("multilevel-acdf", "Multilevel anterior cervical fusion", ["multilevel ACDF", "two level ACDF", "three level ACDF", "2 level ACDF", "3 level ACDF"], ga, per, mid),
        p("cervical-disc-arthroplasty", "Cervical disc arthroplasty", ["cervical disc replacement", "CDA", "artificial cervical disc", "cervical total disc replacement"], ga, per, short),
        p("cervical-corpectomy", "Anterior cervical corpectomy", ["ACCF", "cervical corpectomy", "anterior cervical corpectomy and fusion"], ga, per, mid),
        p("posterior-cervical-fusion", "Posterior cervical laminectomy and fusion", ["PCLF", "posterior cervical fusion", "PCDF", "cervical laminectomy and fusion", "cervical laminectomy", "posterior cervical decompression and fusion", "occipitocervical fusion", "C1-C2 fusion"], ga, per, long),
        p("laminoplasty", "Cervical laminoplasty", ["laminoplasty", "open door laminoplasty"], ga, per, mid),
        p("cervical-foraminotomy", "Posterior cervical foraminotomy", ["cervical foraminotomy", "keyhole foraminotomy", "posterior cervical discectomy"], ga, per, short, side: true),
        p("odontoid", "Odontoid screw fixation", ["odontoid screw", "dens fracture fixation", "C2 fracture fixation", "odontoid fracture"], ga, per, mid),
        p("thoracic-laminectomy", "Thoracic laminectomy", ["thoracic decompression", "thoracic laminectomy and fusion", "thoracic spine fusion", "costotransversectomy", "posterior thoracic fusion"], ga, per, long),
        p("anterior-thoracic-spine", "Anterior thoracic spine surgery", ["transthoracic discectomy", "thoracic corpectomy", "anterior thoracic fusion", "thoracoscopic discectomy", "thoracolumbar corpectomy"], ga, chest, long, risk: true),
        p("microdiscectomy", "Lumbar microdiscectomy", ["microdiscectomy", "lumbar discectomy", "discectomy", "MLD", "hemilaminotomy", "lumbar disc herniation surgery", "endoscopic discectomy"], ga, per, short, side: true),
        p("lumbar-laminectomy", "Lumbar laminectomy", ["laminectomy", "lumbar decompression", "decompressive laminectomy", "laminotomy", "lumbar foraminotomy", "foraminotomy"], ga, per, short),
        p("posterior-lumbar-fusion", "Posterior lumbar fusion", ["PLF", "posterolateral fusion", "lumbar fusion", "posterior spinal fusion lumbar", "lumbar laminectomy and fusion", "pedicle screw fusion", "instrumented lumbar fusion", "PSF"], ga, per, long),
        p("tlif", "Transforaminal lumbar interbody fusion", ["TLIF", "MIS TLIF", "minimally invasive TLIF", "open TLIF"], ga, per, mid),
        p("plif", "Posterior lumbar interbody fusion", ["PLIF"], ga, per, mid),
        p("xlif", "Lateral lumbar interbody fusion", ["XLIF", "LLIF", "DLIF", "lateral interbody fusion", "extreme lateral interbody fusion", "OLIF", "oblique lumbar interbody fusion"], ga, per, mid),
        p("alif", "Anterior lumbar interbody fusion", ["ALIF", "anterior lumbar fusion", "anterior lumbar interbody fusion L5-S1"], ga, per, mid),
        p("circumferential-fusion", "Anterior and posterior lumbar fusion", ["360 fusion", "anterior posterior fusion", "anterior posterior spinal fusion", "circumferential fusion", "ALIF with PSF", "ALIF and PSF"], ga, per, long),
        p("deformity", "Adult spinal deformity correction", ["adult scoliosis surgery", "adult spinal deformity", "pedicle subtraction osteotomy", "PSO", "vertebral column resection", "VCR", "long segment spinal fusion", "kyphosis correction", "T10 to pelvis fusion"], ga, per, long),
        p("kyphoplasty", "Kyphoplasty", ["vertebroplasty", "balloon kyphoplasty", "vertebral augmentation"], mac, per, short),
        p("spinal-cord-stimulator", "Spinal cord stimulator implantation", ["SCS", "spinal cord stimulator", "SCS trial", "SCS implant", "paddle lead placement", "dorsal column stimulator", "DRG stimulator", "intrathecal pump", "intrathecal pump implant", "pain pump implantation"], mac, per, short),
        p("si-fusion", "Sacroiliac joint fusion", ["SI joint fusion", "SI fusion", "sacroiliac fusion", "iFuse"], ga, per, short, side: true),
        p("spine-washout", "Spine wound washout", ["spine I&D", "spinal wound debridement", "irrigation and debridement spine", "spine washout"], ga, per, short),
    ]

    // MARK: Neurosurgery

    fileprivate static let neurosurgery: [Procedure] = [
        p("craniotomy-tumor", "Craniotomy for tumor", ["crani", "craniotomy", "crani for tumor", "craniotomy for tumor resection", "craniotomy for mass", "brain tumor resection", "meningioma resection", "glioma resection", "stereotactic craniotomy"], ga, per, long, side: true),
        p("awake-craniotomy", "Awake craniotomy", ["awake crani", "awake craniotomy for tumor", "asleep awake asleep craniotomy", "craniotomy with language mapping"], mac, per, long, side: true),
        p("craniotomy-hematoma", "Craniotomy for hematoma", ["craniotomy for subdural hematoma", "craniotomy for SDH", "craniotomy for epidural hematoma", "EDH evacuation", "ICH evacuation", "decompressive craniectomy", "hemicraniectomy", "craniectomy"], ga, per, mid, side: true),
        p("burr-holes", "Burr hole evacuation of subdural hematoma", ["burr holes", "burr hole", "burr hole evacuation", "chronic subdural hematoma evacuation", "cSDH evacuation", "SDH evacuation", "subdural drain"], ga, per, short, side: true),
        p("aneurysm-clipping", "Craniotomy for aneurysm clipping", ["aneurysm clipping", "clipping of aneurysm", "cerebral aneurysm clipping", "crani for aneurysm", "AVM resection", "craniotomy for AVM", "EC-IC bypass"], ga, per, long, side: true),
        p("cranioplasty", "Cranioplasty", ["bone flap replacement", "cranial reconstruction", "cranioplasty with implant"], ga, per, short, side: true),
        p("suboccipital", "Suboccipital craniotomy", ["posterior fossa craniotomy", "suboccipital craniectomy", "posterior fossa tumor resection", "posterior fossa decompression", "Chiari decompression", "Chiari malformation decompression"], ga, per, long),
        p("mvd", "Microvascular decompression", ["MVD", "MVD for trigeminal neuralgia", "retrosigmoid craniotomy", "microvascular decompression for hemifacial spasm"], ga, per, long, side: true),
        p("acoustic-neuroma", "Acoustic neuroma resection", ["acoustic neuroma", "vestibular schwannoma resection", "vestibular schwannoma", "translabyrinthine approach", "cerebellopontine angle tumor"], ga, per, long, side: true),
        p("transsphenoidal", "Transsphenoidal pituitary surgery", ["transsphenoidal", "transsphenoidal hypophysectomy", "TSS", "pituitary tumor resection", "pituitary adenoma resection", "endoscopic endonasal approach", "EEA", "endoscopic endonasal pituitary resection"], ga, per, mid),
        p("vp-shunt", "Ventriculoperitoneal shunt", ["VP shunt", "VPS", "VP shunt placement", "shunt revision", "VP shunt revision", "VA shunt", "LP shunt", "lumboperitoneal shunt", "shunt externalization"], ga, per, short),
        p("evd", "External ventricular drain", ["EVD", "EVD placement", "ventriculostomy", "ICP monitor", "ICP monitor placement", "ICP bolt"], mac, per, short, side: true),
        p("etv", "Endoscopic third ventriculostomy", ["ETV", "third ventriculostomy", "ETV CPC", "ETV with choroid plexus cauterization", "neuroendoscopy"], ga, per, short),
        p("dbs", "Deep brain stimulation", ["DBS", "DBS lead placement", "deep brain stimulator", "DBS for Parkinson's", "DBS generator placement", "IPG placement"], mac, per, long),
        p("epilepsy-surgery", "Epilepsy surgery", ["temporal lobectomy", "anterior temporal lobectomy", "amygdalohippocampectomy", "SEEG", "stereo EEG", "subdural grid placement", "grid placement", "LITT", "laser interstitial thermal therapy", "responsive neurostimulation", "RNS"], ga, per, long, side: true),
        p("vns", "Vagus nerve stimulator implantation", ["VNS", "vagus nerve stimulator", "VNS battery change", "VNS generator change"], ga, per, short),
        p("brain-biopsy", "Stereotactic brain biopsy", ["brain biopsy", "stereotactic biopsy", "frameless stereotactic biopsy", "needle biopsy brain"], ga, per, short, side: true),
        p("spinal-cord-tumor", "Intradural spinal tumor resection", ["intradural tumor", "intradural spinal tumor", "spinal cord tumor resection", "intramedullary tumor", "spinal schwannoma", "spinal meningioma resection", "intradural extramedullary tumor"], ga, per, long),
        p("peripheral-nerve", "Peripheral nerve repair or decompression", ["nerve repair", "nerve graft", "nerve transfer", "brachial plexus exploration", "peroneal nerve decompression", "tarsal tunnel release"], ga, per, mid, side: true),
        p("trigeminal-rhizotomy", "Percutaneous trigeminal rhizotomy", ["glycerol rhizotomy", "balloon compression of trigeminal ganglion", "radiofrequency rhizotomy", "percutaneous rhizotomy", "trigeminal rhizotomy"], ga, per, short, side: true),
    ]

    // MARK: ENT and head and neck

    fileprivate static let ent: [Procedure] = [
        p("tonsillectomy-adenoidectomy", "Tonsillectomy and adenoidectomy", ["T&A", "T and A", "adenotonsillectomy", "tonsillectomy with adenoidectomy", "tonsillectomy & adenoidectomy", "T&A with tubes"], ga, per, short),
        p("tonsillectomy", "Tonsillectomy", ["tonsils", "adult tonsillectomy", "partial tonsillectomy", "tonsillotomy", "intracapsular tonsillectomy"], ga, per, short),
        p("adenoidectomy", "Adenoidectomy", ["adenoids", "adenoid removal", "revision adenoidectomy"], ga, per, short),
        p("tonsil-bleed", "Control of post-tonsillectomy bleed", ["post tonsillectomy bleed", "post tonsillectomy hemorrhage", "posttonsillectomy bleed", "tonsil bleed", "tonsillar hemorrhage"], ga, per, short),
        p("peritonsillar-abscess", "Peritonsillar abscess drainage", ["peritonsillar abscess", "PTA drainage", "quinsy", "quinsy tonsillectomy"], ga, per, short),
        p("myringotomy-tubes", "Myringotomy and tubes", ["BMT", "BMTs", "bilateral myringotomy and tubes", "PE tubes", "PE tube", "ear tubes", "tympanostomy tubes", "tympanostomy tube placement", "myringotomy", "myringotomy with tubes", "M&T", "grommets", "ear tube removal"], ga, per, short, side: true),
        p("tympanoplasty", "Tympanoplasty", ["tympanomastoidectomy", "myringoplasty", "eardrum repair", "tympanic membrane repair", "TM repair", "ossiculoplasty"], ga, per, mid, side: true),
        p("mastoidectomy", "Mastoidectomy", ["canal wall down mastoidectomy", "canal wall up mastoidectomy", "cholesteatoma excision", "cholesteatoma"], ga, per, mid, side: true),
        p("cochlear-implant", "Cochlear implant", ["cochlear implantation", "cochlear implant placement", "BAHA", "bone anchored hearing aid", "osseointegrated implant", "stapedectomy", "stapedotomy"], ga, per, mid, side: true),
        p("fess", "Functional endoscopic sinus surgery", ["FESS", "ESS", "endoscopic sinus surgery", "sinus surgery", "image guided sinus surgery", "maxillary antrostomy", "ethmoidectomy", "frontal sinusotomy", "balloon sinuplasty"], ga, per, short),
        p("septoplasty", "Septoplasty", ["SMR", "submucous resection", "septoplasty and turbinate reduction", "septoplasty with turbinates", "turbinate reduction", "inferior turbinate reduction", "turbinoplasty", "nasal septal reconstruction"], ga, per, short),
        p("nasal-fracture", "Nasal fracture reduction", ["nasal fracture", "closed reduction nasal fracture", "CRNF", "closed reduction of nasal fracture"], ga, per, short),
        p("epistaxis", "Control of epistaxis", ["epistaxis", "sphenopalatine artery ligation", "SPA ligation", "nosebleed control", "posterior nasal packing"], ga, per, short),
        p("dlb", "Direct laryngoscopy and bronchoscopy", ["DLB", "DL&B", "DL and B", "direct laryngoscopy", "microlaryngoscopy", "MLB", "microlaryngoscopy and bronchoscopy", "suspension laryngoscopy", "laryngoscopy with biopsy", "vocal cord biopsy", "panendoscopy", "triple endoscopy", "vocal fold injection"], ga, per, short),
        p("laryngeal-laser", "Laser airway surgery", ["CO2 laser larynx", "laryngeal laser surgery", "laser excision of vocal cord lesion", "laryngeal papilloma laser", "papilloma debridement", "subglottic stenosis laser", "subglottic stenosis dilation", "airway dilation", "jet ventilation laryngoscopy"], ga, per, short),
        p("tracheostomy", "Tracheostomy", ["trach", "open tracheostomy", "surgical tracheostomy", "percutaneous tracheostomy", "perc trach", "PDT", "awake tracheostomy", "cricothyrotomy", "trach revision", "tracheostomy revision"], ga, per, short),
        p("parotidectomy", "Parotidectomy", ["superficial parotidectomy", "total parotidectomy", "parotid tumor excision", "parotid gland excision", "parotid mass"], ga, per, mid, side: true),
        p("submandibular-gland", "Submandibular gland excision", ["submandibular gland", "submandibular gland resection", "sialadenectomy", "sialendoscopy"], ga, per, short, side: true),
        p("neck-dissection", "Neck dissection", ["radical neck dissection", "modified radical neck dissection", "MRND", "selective neck dissection", "SND", "lateral neck dissection"], ga, per, mid, side: true),
        p("laryngectomy", "Total laryngectomy", ["laryngectomy", "total laryngectomy with neck dissection", "pharyngolaryngectomy", "partial laryngectomy", "supraglottic laryngectomy"], ga, per, long),
        p("tors", "Transoral robotic surgery", ["TORS", "TORS base of tongue resection", "transoral robotic resection", "transoral laser microsurgery", "TLM", "base of tongue resection", "lingual tonsillectomy"], ga, per, mid),
        p("glossectomy", "Glossectomy", ["partial glossectomy", "hemiglossectomy", "tongue cancer resection", "tongue lesion excision", "composite resection", "commando procedure"], ga, per, mid),
        p("free-flap-head-neck", "Head and neck resection with free flap", ["composite resection with free flap", "head and neck free flap", "free flap reconstruction head and neck", "fibula free flap", "radial forearm free flap", "ALT free flap", "mandibulectomy", "segmental mandibulectomy", "maxillectomy"], ga, per, long),
        p("uppp", "Uvulopalatopharyngoplasty", ["UPPP", "palatoplasty for sleep apnea", "sleep apnea surgery", "expansion sphincter pharyngoplasty", "uvulectomy"], ga, per, short),
        p("hypoglossal-stimulator", "Hypoglossal nerve stimulator", ["Inspire", "Inspire implant", "hypoglossal nerve stimulation", "upper airway stimulation", "HGNS"], ga, per, mid),
        p("dise", "Drug-induced sleep endoscopy", ["DISE", "sleep endoscopy", "drug induced sleep endoscopy"], mac, per, short),
        p("zenker", "Zenker diverticulectomy", ["Zenker", "Zenker's diverticulum", "endoscopic Zenker diverticulotomy", "cricopharyngeal myotomy"], ga, per, short),
        p("rigid-esophagoscopy", "Rigid esophagoscopy", ["esophagoscopy", "esophageal foreign body removal", "esophageal foreign body", "rigid esophagoscopy with dilation"], ga, per, short),
        p("neck-mass", "Neck cyst or mass excision", ["branchial cleft cyst", "branchial cleft cyst excision", "thyroglossal duct cyst", "thyroglossal duct cyst excision", "Sistrunk", "Sistrunk procedure", "neck mass excision"], ga, per, short),
        p("neck-abscess", "Neck abscess drainage", ["deep neck abscess", "neck abscess", "retropharyngeal abscess", "retropharyngeal abscess drainage", "parapharyngeal abscess", "Ludwig's angina", "I&D neck abscess"], ga, per, short),
        p("medialization", "Vocal cord medialization", ["medialization laryngoplasty", "thyroplasty", "type I thyroplasty", "vocal fold medialization"], mac, per, short, side: true),
    ]

    // MARK: Ophthalmology

    fileprivate static let ophthalmology: [Procedure] = [
        p("cataract", "Cataract extraction with lens implant", ["cataract", "cataract surgery", "cataract extraction", "phaco", "phacoemulsification", "phaco IOL", "CE IOL", "CEIOL", "IOL", "PCIOL", "cataract extraction with intraocular lens"], mac, per, short, side: true),
        p("vitrectomy", "Pars plana vitrectomy", ["PPV", "vitrectomy", "membrane peel", "epiretinal membrane peel", "ERM peel", "macular hole repair", "vitrectomy for retinal detachment", "PPV with membrane peel"], raMac, per, short, side: true),
        p("scleral-buckle", "Scleral buckle", ["scleral buckling", "retinal detachment repair", "RD repair", "scleral buckle with vitrectomy"], ga, per, mid, side: true),
        p("glaucoma-surgery", "Glaucoma surgery", ["trabeculectomy", "trab", "tube shunt", "Ahmed valve", "Baerveldt implant", "glaucoma drainage device", "Xen gel stent", "MIGS", "iStent"], mac, per, short, side: true),
        p("keratoplasty", "Corneal transplant", ["keratoplasty", "penetrating keratoplasty", "PKP", "DSAEK", "DMEK", "corneal graft", "endothelial keratoplasty"], raMac, per, short, side: true),
        p("strabismus", "Strabismus surgery", ["strabismus repair", "eye muscle surgery", "squint surgery", "recession resection", "bilateral lateral rectus recession", "BLR recession"], ga, per, short, side: true),
        p("open-globe", "Open globe repair", ["ruptured globe repair", "ruptured globe", "globe repair", "open globe", "corneal laceration repair"], ga, per, short, side: true),
        p("enucleation", "Enucleation or evisceration", ["enucleation", "evisceration", "eye removal", "orbital exenteration"], ga, per, short, side: true),
        p("blepharoplasty", "Blepharoplasty or eyelid surgery", ["blepharoplasty", "upper blepharoplasty", "lower blepharoplasty", "eyelid surgery", "ptosis repair", "eyelid ptosis repair", "brow lift", "entropion repair", "ectropion repair", "eyelid lesion excision"], mac, per, short, side: true),
        p("dcr", "Dacryocystorhinostomy", ["DCR", "endoscopic DCR", "lacrimal surgery", "tear duct surgery", "nasolacrimal duct probing", "NLD probing", "tear duct probing"], ga, per, short, side: true),
        p("orbital-fracture", "Orbital fracture repair", ["orbital floor fracture", "orbital floor fracture repair", "blowout fracture repair", "orbital decompression"], ga, per, mid, side: true),
        p("eye-eua", "Eye examination under anesthesia", ["eye EUA", "EUA eyes", "ophthalmic EUA", "ROP laser", "retinopathy of prematurity laser", "laser for ROP"], ga, per, short),
        p("pterygium", "Pterygium excision", ["pterygium", "pterygium excision with graft", "conjunctival autograft"], mac, per, short, side: true),
    ]

    // MARK: Plastics

    fileprivate static let plastics: [Procedure] = [
        p("expander-implant", "Breast reconstruction with expander or implant", ["tissue expander placement", "tissue expander exchange", "expander to implant exchange", "implant exchange", "breast reconstruction", "implant based breast reconstruction", "fat grafting breast", "nipple reconstruction"], ga, per, short, side: true),
        p("diep", "DIEP flap breast reconstruction", ["DIEP", "DIEP flap", "bilateral DIEP", "free flap breast reconstruction", "TRAM flap", "free TRAM", "SIEA flap", "PAP flap", "autologous breast reconstruction"], ga, per, long, side: true),
        p("latissimus-flap", "Latissimus dorsi flap", ["latissimus flap", "lat flap", "latissimus dorsi flap reconstruction"], ga, per, mid, side: true),
        p("breast-reduction", "Breast reduction", ["reduction mammaplasty", "reduction mammoplasty", "bilateral breast reduction", "mastopexy", "breast lift"], ga, per, mid),
        p("breast-augmentation", "Breast augmentation", ["breast implants", "augmentation mammaplasty", "augmentation mammoplasty", "breast implant removal", "explant of breast implants", "capsulectomy"], ga, per, short),
        p("abdominoplasty", "Abdominoplasty", ["tummy tuck", "panniculectomy", "body contouring", "lower body lift", "belt lipectomy"], ga, per, mid),
        p("liposuction", "Liposuction", ["lipo", "suction assisted lipectomy", "liposculpture", "BBL", "Brazilian butt lift", "fat transfer"], ga, per, mid),
        p("facelift", "Facelift", ["rhytidectomy", "face lift", "neck lift", "deep plane facelift"], ga, per, long),
        p("rhinoplasty", "Rhinoplasty", ["septorhinoplasty", "functional rhinoplasty", "open rhinoplasty", "revision rhinoplasty"], ga, per, mid),
        p("skin-graft", "Skin graft", ["STSG", "split thickness skin graft", "FTSG", "full thickness skin graft", "skin grafting", "burn excision and grafting", "burn excision", "tangential excision", "escharotomy"], ga, per, mid),
        p("skin-lesion", "Excision of skin lesion", ["skin lesion excision", "skin cancer excision", "melanoma excision", "wide local excision", "WLE", "Mohs reconstruction", "basal cell carcinoma excision", "local flap", "scar revision"], mac, per, short),
        p("free-flap", "Free flap reconstruction", ["free flap", "free tissue transfer", "microvascular free flap", "lower extremity free flap", "ALT flap", "gracilis flap"], ga, per, long, side: true),
        p("pressure-ulcer", "Pressure ulcer flap", ["pressure ulcer", "sacral ulcer flap", "pressure sore reconstruction", "ischial ulcer flap", "decubitus ulcer debridement", "pressure injury flap"], ga, per, mid),
        p("gender-affirming", "Gender-affirming surgery", ["gender affirming surgery", "vaginoplasty", "phalloplasty", "metoidioplasty", "top surgery", "chest masculinization", "facial feminization surgery"], ga, per, long),
        p("hidradenitis", "Hidradenitis excision", ["hidradenitis", "hidradenitis suppurativa excision", "axillary hidradenitis excision"], ga, per, mid, side: true),
    ]

    // MARK: Dental and oral

    fileprivate static let dental: [Procedure] = [
        p("dental-rehab", "Dental rehabilitation", ["full mouth dental rehabilitation", "FMDR", "dental restorations", "dental rehab", "dental work under general anesthesia", "dental extractions and restorations", "pediatric dental rehabilitation"], ga, per, mid),
        p("third-molars", "Third molar extraction", ["wisdom teeth", "wisdom teeth extraction", "wisdom tooth extraction", "third molars", "third molar removal", "impacted third molars"], ga, per, short),
        p("dental-extraction", "Dental extractions", ["tooth extraction", "dental extraction", "full mouth extraction", "multiple extractions", "extraction of teeth"], mac, per, short),
        p("orthognathic", "Orthognathic surgery", ["jaw surgery", "double jaw surgery", "Le Fort I osteotomy", "LeFort I", "BSSO", "bilateral sagittal split osteotomy", "bimaxillary osteotomy", "genioplasty"], ga, per, long),
        p("facial-fracture", "Facial fracture repair", ["mandible fracture", "ORIF mandible", "mandibular fracture", "jaw fracture", "maxillomandibular fixation", "MMF", "zygomatic fracture repair", "ZMC fracture", "Le Fort fracture", "panfacial fracture"], ga, per, mid),
        p("tmj", "Temporomandibular joint surgery", ["TMJ surgery", "TMJ arthroscopy", "TMJ arthroplasty", "TMJ replacement", "TMJ arthrocentesis"], ga, per, mid, side: true),
        p("dental-implants", "Dental implants or jaw bone graft", ["dental implants", "dental implant placement", "bone graft jaw", "sinus lift", "alveolar bone graft", "All-on-4", "zygomatic implants"], mac, per, short),
        p("odontogenic-abscess", "Odontogenic abscess drainage", ["dental abscess", "odontogenic infection", "odontogenic abscess", "submandibular abscess", "buccal space abscess"], ga, per, short),
    ]

    // MARK: GI endoscopy

    fileprivate static let endoscopy: [Procedure] = [
        p("egd", "Upper endoscopy", ["EGD", "esophagogastroduodenoscopy", "OGD", "upper GI endoscopy", "EGD with biopsy", "EGD with dilation", "esophageal dilation", "variceal banding", "EGD with banding", "upper endoscopy with biopsy"], mac, per, short),
        p("colonoscopy", "Colonoscopy", ["colonoscopy with polypectomy", "screening colonoscopy", "flexible sigmoidoscopy", "flex sig", "sigmoidoscopy", "lower endoscopy", "colonoscopy with biopsy"], mac, per, short),
        p("egd-colonoscopy", "Upper endoscopy and colonoscopy", ["EGD and colonoscopy", "EGD colonoscopy", "EGD/colonoscopy", "EGD with colonoscopy", "bidirectional endoscopy", "upper and lower endoscopy"], mac, per, short),
        p("ercp", "Endoscopic retrograde cholangiopancreatography", ["ERCP", "ERCP with sphincterotomy", "ERCP with stent", "ERCP with stone extraction", "biliary stent exchange", "cholangioscopy", "SpyGlass cholangioscopy"], mac, per, short),
        p("eus", "Endoscopic ultrasound", ["EUS", "EUS FNA", "EUS FNB", "EUS guided biopsy", "EUS guided drainage", "cystgastrostomy", "EUS guided gastroenterostomy", "EUS-GE"], mac, per, short),
        p("peg", "Percutaneous endoscopic gastrostomy", ["PEG", "PEG tube", "PEG placement", "PEG tube placement", "PEG-J", "PEG J", "PEG replacement"], mac, per, short),
        p("emr-esd", "Endoscopic mucosal resection or submucosal dissection", ["EMR", "ESD", "endoscopic mucosal resection", "endoscopic submucosal dissection", "endoscopic resection"], ga, per, mid),
        p("poem", "Peroral endoscopic myotomy", ["POEM", "G-POEM", "gastric POEM", "Z-POEM", "per oral endoscopic myotomy"], ga, per, short),
        p("enteroscopy", "Enteroscopy", ["push enteroscopy", "double balloon enteroscopy", "DBE", "single balloon enteroscopy", "deep enteroscopy", "capsule endoscopy placement"], mac, per, short),
        p("endoscopic-bariatric", "Endoscopic sleeve gastroplasty", ["ESG", "endoscopic sleeve", "intragastric balloon", "intragastric balloon placement", "TORe", "transoral outlet reduction"], ga, per, short),
        p("endoscopic-foreign-body", "Endoscopic foreign body removal", ["food impaction", "food bolus impaction", "food bolus removal", "foreign body EGD", "swallowed foreign body", "coin removal", "button battery removal"], ga, per, short),
    ]

    // MARK: Interventional radiology

    fileprivate static let radiology: [Procedure] = [
        p("ir", "Interventional radiology procedure", ["IR", "IR procedure", "IR case", "interventional radiology"], mac, per, short),
        p("tips", "Transjugular intrahepatic portosystemic shunt", ["TIPS", "TIPSS", "TIPS revision", "TIPS creation", "DIPS"], ga, per, mid),
        p("embolization", "Arterial embolization", ["embolization", "angioembolization", "GI bleed embolization", "splenic artery embolization", "bronchial artery embolization", "pelvic embolization", "trauma embolization", "prostate artery embolization", "PAE", "genicular artery embolization"], mac, per, short),
        p("ufe", "Uterine fibroid embolization", ["UFE", "uterine artery embolization", "UAE"], mac, per, short),
        p("liver-directed", "Chemoembolization or radioembolization", ["TACE", "chemoembolization", "Y90", "Y-90", "radioembolization", "SIRT", "Y90 mapping", "transarterial chemoembolization"], mac, per, short),
        p("tumor-ablation", "Percutaneous tumor ablation", ["RFA", "MWA", "microwave ablation", "radiofrequency ablation", "cryoablation", "percutaneous ablation", "liver ablation", "renal cryoablation", "kidney ablation", "lung ablation"], ga, per, short),
        p("ivc-filter", "IVC filter", ["IVC filter placement", "IVC filter removal", "IVC filter retrieval", "inferior vena cava filter"], mac, per, short),
        p("venous-thrombectomy", "Catheter-directed thrombolysis or thrombectomy", ["catheter directed thrombolysis", "CDT", "PE thrombectomy", "pulmonary artery thrombectomy", "FlowTriever", "EKOS", "AngioVac", "venous thrombectomy", "DVT thrombectomy", "pharmacomechanical thrombectomy"], mac, per, short),
        p("stroke-thrombectomy", "Mechanical thrombectomy for stroke", ["stroke thrombectomy", "mechanical thrombectomy", "thrombectomy for stroke", "endovascular thrombectomy", "EVT", "large vessel occlusion thrombectomy"], mac, per, short),
        p("neuro-endovascular", "Endovascular aneurysm coiling", ["coiling", "aneurysm coiling", "endovascular coiling", "flow diverter", "pipeline embolization device", "WEB device", "AVM embolization", "MMA embolization", "middle meningeal artery embolization", "cerebral angiogram", "diagnostic cerebral angiogram"], ga, per, mid),
        p("tunneled-catheter", "Tunneled catheter or line placement", ["tunneled dialysis catheter", "TDC", "permcath", "Hickman", "Hickman line", "tunneled line", "tunneled central line", "PICC", "PICC placement", "central line placement", "dialysis catheter placement"], mac, per, short),
        p("image-guided-drainage", "Image-guided drainage", ["percutaneous drainage", "percutaneous abscess drainage", "abscess drain", "IR drain", "CT guided drain", "pigtail drain", "drain exchange"], mac, per, short),
        p("biliary-drainage", "Percutaneous biliary drainage", ["PTBD", "PTC", "percutaneous transhepatic cholangiography", "biliary drain", "cholecystostomy", "percutaneous cholecystostomy", "cholecystostomy tube", "perc chole"], mac, per, short),
        p("nephrostomy", "Percutaneous nephrostomy", ["PCN", "nephrostomy", "nephrostomy tube", "nephroureteral stent", "PCN exchange", "nephrostomy tube exchange"], mac, per, short, side: true),
        p("ir-gastrostomy", "Radiologic gastrostomy", ["IR G tube", "IR gastrostomy", "radiologic gastrostomy", "PRG", "RIG", "GJ tube", "G tube exchange", "GJ tube exchange"], mac, per, short),
        p("image-guided-biopsy", "Image-guided biopsy", ["CT guided biopsy", "ultrasound guided biopsy", "percutaneous biopsy", "liver biopsy", "transjugular liver biopsy", "kidney biopsy", "renal biopsy", "bone biopsy", "lung nodule biopsy", "bone marrow biopsy"], mac, per, short),
    ]

    // MARK: Cardiac cath and EP

    fileprivate static let cathEP: [Procedure] = [
        p("lhc", "Left heart catheterization", ["LHC", "cath", "cardiac cath", "heart cath", "left heart cath", "cardiac catheterization", "coronary angiogram", "coronary angiography", "diagnostic cath", "diagnostic coronary angiogram"], mac, per, short),
        p("rhc", "Right heart catheterization", ["RHC", "right heart cath", "Swan Ganz catheterization", "hemodynamic study", "vasoreactivity testing", "right and left heart catheterization"], mac, per, short),
        p("pci", "Percutaneous coronary intervention", ["PCI", "PTCA", "coronary stent", "coronary angioplasty", "cardiac stent", "primary PCI", "STEMI PCI", "high risk PCI", "protected PCI", "CTO PCI", "rotational atherectomy", "coronary atherectomy", "intravascular lithotripsy"], mac, per, short),
        p("mcs-insertion", "Impella or balloon pump insertion", ["Impella", "Impella insertion", "Impella CP", "Impella 5.5", "IABP", "IABP insertion", "intra-aortic balloon pump", "balloon pump", "TandemHeart"], mac, per, short),
        p("ppm", "Pacemaker implantation", ["PPM", "pacemaker", "permanent pacemaker", "dual chamber pacemaker", "leadless pacemaker", "Micra", "pacemaker generator change", "generator change", "pacemaker lead revision", "temporary transvenous pacemaker"], mac, per, short),
        p("icd", "ICD implantation", ["ICD", "AICD", "ICD implant", "defibrillator implant", "subcutaneous ICD", "S-ICD", "ICD generator change", "DFT testing", "defibrillation threshold testing"], mac, per, short),
        p("crt", "Biventricular device implantation", ["CRT", "CRT-D", "CRT-P", "BiV ICD", "BiV pacemaker", "biventricular pacemaker", "cardiac resynchronization therapy", "LV lead placement", "conduction system pacing", "His bundle pacing"], mac, per, mid),
        p("lead-extraction", "Lead extraction", ["laser lead extraction", "transvenous lead extraction", "TLE", "device extraction", "ICD extraction", "pacemaker extraction", "system extraction"], ga, per, mid),
        p("af-ablation", "Atrial fibrillation ablation", ["PVI", "pulmonary vein isolation", "AF ablation", "AFib ablation", "A fib ablation", "atrial fibrillation ablation with PVI", "pulsed field ablation", "PFA", "cryoballoon ablation", "redo PVI"], ga, per, mid),
        p("flutter-ablation", "Atrial flutter ablation", ["flutter ablation", "CTI ablation", "cavotricuspid isthmus ablation", "AFL ablation"], mac, per, short),
        p("svt-ablation", "SVT ablation or EP study", ["SVT ablation", "AVNRT ablation", "WPW ablation", "accessory pathway ablation", "EP study", "EPS", "electrophysiology study", "AV node ablation", "AVN ablation"], mac, per, short),
        p("vt-ablation", "VT ablation", ["ventricular tachycardia ablation", "PVC ablation", "epicardial VT ablation", "endocardial VT ablation", "VT storm ablation"], ga, per, long),
        p("laao", "Left atrial appendage occlusion", ["LAAO", "LAAC", "Watchman", "WATCHMAN FLX", "Amulet", "LAA occlusion", "left atrial appendage closure"], ga, per, short),
        p("tee", "Transesophageal echocardiography", ["TEE", "transesophageal echo", "transesophageal echocardiogram"], mac, per, short),
        p("tee-dccv", "TEE and cardioversion", ["TEE/DCCV", "TEE DCCV", "TEE cardioversion", "TEE guided cardioversion", "TEE with DCCV", "TEE and DCCV", "TEE/cardioversion"], mac, per, short),
        p("dccv", "Electrical cardioversion", ["DCCV", "cardioversion", "DC cardioversion", "external cardioversion", "synchronized cardioversion", "elective cardioversion"], mac, per, short),
        p("structural-closure", "Percutaneous PFO or ASD closure", ["PFO closure", "percutaneous PFO closure", "ASD closure", "percutaneous ASD closure", "ASD device closure", "Amplatzer", "VSD device closure", "paravalvular leak closure", "PVL closure"], ga, per, short),
        p("pericardiocentesis", "Pericardiocentesis", ["pericardial drain", "pericardial drainage", "percutaneous pericardiocentesis"], mac, per, short),
        p("balloon-valvuloplasty", "Balloon valvuloplasty", ["BAV", "balloon aortic valvuloplasty", "BMV", "balloon mitral valvuloplasty", "PBMV", "percutaneous mitral commissurotomy", "pulmonary balloon valvuloplasty"], mac, per, short),
        p("alcohol-septal-ablation", "Alcohol septal ablation", ["septal ablation", "ethanol septal ablation", "alcohol septal ablation for HOCM"], mac, per, short),
        p("loop-recorder", "Implantable loop recorder", ["ILR", "loop recorder", "LINQ", "Reveal LINQ", "loop recorder implant"], mac, per, short),
        p("endomyocardial-biopsy", "Endomyocardial biopsy", ["EMB", "heart biopsy", "RV biopsy", "heart transplant biopsy"], mac, per, short),
    ]

    // MARK: Bronchoscopy

    fileprivate static let bronchoscopy: [Procedure] = [
        p("flexible-bronchoscopy", "Flexible bronchoscopy", ["bronchoscopy", "bronch", "flex bronch", "BAL", "bronchoalveolar lavage", "bronchoscopy with BAL", "transbronchial biopsy", "TBBx", "therapeutic bronchoscopy"], mac, per, short),
        p("ebus", "Endobronchial ultrasound", ["EBUS", "EBUS TBNA", "EBUS-TBNA", "linear EBUS", "radial EBUS", "endobronchial ultrasound with TBNA", "EBUS staging"], ga, per, short),
        p("navigational-bronchoscopy", "Navigational or robotic bronchoscopy", ["navigational bronchoscopy", "ENB", "electromagnetic navigation bronchoscopy", "robotic bronchoscopy", "Ion bronchoscopy", "Monarch bronchoscopy", "superDimension"], ga, per, short),
        p("rigid-bronchoscopy", "Rigid bronchoscopy", ["rigid bronch", "rigid bronchoscopy with stent", "airway stent", "airway stent placement", "tracheal stent", "airway debulking", "endobronchial debulking", "airway tumor debulking"], ga, per, short),
        p("whole-lung-lavage", "Whole lung lavage", ["WLL", "whole lung lavage for alveolar proteinosis", "bronchopulmonary lavage"], ga, per, mid, side: true),
        p("endobronchial-valves", "Endobronchial valve placement", ["endobronchial valves", "Zephyr valves", "EBV", "bronchoscopic lung volume reduction", "bronchial thermoplasty"], ga, per, short),
    ]

    // MARK: Pediatrics

    fileprivate static let pediatrics: [Procedure] = [
        p("pyloromyotomy", "Pyloromyotomy", ["pyloric stenosis", "laparoscopic pyloromyotomy", "Ramstedt", "Ramstedt pyloromyotomy"], ga, upper, short, risk: true),
        p("peds-inguinal-hernia", "Pediatric inguinal hernia repair", ["pediatric hernia", "pediatric inguinal hernia", "inguinal herniotomy", "herniotomy", "high ligation of hernia sac", "laparoscopic pediatric hernia repair", "PIRS"], gaNx, per, short, side: true),
        p("orchiopexy", "Orchiopexy", ["undescended testis", "undescended testicle", "inguinal orchiopexy", "laparoscopic orchiopexy", "Fowler Stephens orchiopexy", "cryptorchidism repair"], gaNx, per, short, side: true),
        p("hypospadias", "Hypospadias repair", ["hypospadias", "TIP repair", "chordee repair", "MAGPI", "hypospadias revision"], gaNx, per, mid),
        p("intussusception", "Reduction of intussusception", ["intussusception", "intussusception reduction", "laparoscopic reduction of intussusception"], ga, upper, short, risk: true),
        p("ladd", "Ladd procedure", ["Ladd", "Ladd's procedure", "malrotation repair", "malrotation", "volvulus repair", "midgut volvulus"], ga, upper, mid, risk: true),
        p("nec-laparotomy", "Laparotomy for necrotizing enterocolitis", ["NEC laparotomy", "NEC", "necrotizing enterocolitis", "peritoneal drain for NEC", "neonatal laparotomy"], ga, upper, mid, risk: true),
        p("abdominal-wall-defect", "Gastroschisis or omphalocele repair", ["gastroschisis", "gastroschisis repair", "omphalocele", "omphalocele repair", "silo placement", "abdominal wall defect repair"], ga, upper, mid, risk: true),
        p("cdh", "Congenital diaphragmatic hernia repair", ["CDH", "CDH repair", "diaphragmatic hernia repair", "Bochdalek hernia repair"], ga, upper, mid, risk: true),
        p("tef", "Tracheoesophageal fistula repair", ["TEF", "TEF repair", "esophageal atresia repair", "EA TEF repair", "EA/TEF"], ga, chest, long, risk: true),
        p("kasai", "Kasai portoenterostomy", ["Kasai", "Kasai procedure", "portoenterostomy", "biliary atresia"], ga, upper, long, risk: true),
        p("choledochal-cyst", "Choledochal cyst excision", ["choledochal cyst", "choledochal cyst resection"], ga, upper, long, risk: true),
        p("hirschsprung", "Pull-through for Hirschsprung disease", ["Hirschsprung", "Hirschsprung's", "pull through", "Soave pull through", "transanal pull through", "Swenson", "Duhamel", "endorectal pull through"], ga, per, mid, risk: true),
        p("psarp", "Anorectal malformation repair", ["PSARP", "posterior sagittal anorectoplasty", "imperforate anus", "imperforate anus repair", "anoplasty"], ga, per, mid),
        p("nuss", "Nuss procedure", ["Nuss", "pectus excavatum repair", "pectus excavatum", "Ravitch", "Ravitch procedure", "pectus carinatum repair", "Nuss bar removal", "pectus bar removal"], gaRa, chest, mid, risk: true),
        p("cleft-lip", "Cleft lip repair", ["cleft lip", "cheiloplasty", "lip adhesion", "cleft lip and nose repair"], ga, per, short),
        p("cleft-palate", "Cleft palate repair", ["cleft palate", "palatoplasty", "Furlow palatoplasty", "pharyngeal flap", "alveolar cleft bone graft"], ga, per, mid),
        p("craniosynostosis", "Craniosynostosis repair", ["craniosynostosis", "cranial vault remodeling", "cranial vault reconstruction", "CVR", "strip craniectomy", "endoscopic strip craniectomy", "fronto orbital advancement", "FOA"], ga, per, long),
        p("myelomeningocele", "Myelomeningocele closure", ["MMC repair", "MMC closure", "myelomeningocele repair", "spina bifida closure", "tethered cord release", "tethered cord"], ga, per, mid),
        p("peds-scoliosis", "Posterior spinal fusion for scoliosis", ["PSF for scoliosis", "scoliosis surgery", "scoliosis", "spinal fusion for scoliosis", "adolescent idiopathic scoliosis", "AIS fusion", "neuromuscular scoliosis fusion", "growing rods", "MAGEC rods", "VEPTR"], ga, per, long),
        p("clubfoot", "Clubfoot correction", ["clubfoot", "Ponseti tenotomy", "Achilles tenotomy", "posteromedial release"], gaNx, per, short, side: true),
        p("scfe", "Pinning of slipped capital femoral epiphysis", ["SCFE", "SCFE pinning", "in situ pinning", "slipped capital femoral epiphysis"], ga, per, short, side: true),
        p("supracondylar", "Supracondylar humerus fracture pinning", ["supracondylar fracture", "supracondylar humerus fracture", "CRPP supracondylar", "CRPP elbow", "pediatric elbow fracture", "lateral condyle fracture"], ga, per, short, side: true),
        p("closed-reduction-casting", "Closed reduction and casting", ["closed reduction and casting", "closed reduction forearm", "forearm closed reduction", "cast change under anesthesia", "spica cast", "hip spica"], ga, per, short, side: true),
        p("ddh", "Hip reconstruction for dysplasia", ["DDH", "open reduction hip", "pelvic osteotomy", "Salter osteotomy", "Pemberton osteotomy", "varus derotation osteotomy", "VDRO"], ga, per, mid, side: true),
        p("airway-foreign-body", "Airway foreign body removal", ["airway foreign body", "foreign body aspiration", "aspirated foreign body", "bronchoscopy for foreign body", "rigid bronchoscopy for foreign body"], ga, per, short),
        p("supraglottoplasty", "Supraglottoplasty", ["laryngomalacia", "aryepiglottoplasty", "supraglottoplasty for laryngomalacia"], ga, per, short),
        p("frenotomy", "Frenotomy", ["frenectomy", "frenuloplasty", "tongue tie release", "tongue tie", "ankyloglossia"], ga, per, short),
        p("otoplasty", "Otoplasty", ["ear pinning", "prominent ear correction", "microtia repair", "ear reconstruction"], ga, per, mid, side: true),
        p("peds-tumor", "Pediatric abdominal tumor resection", ["Wilms tumor", "Wilms tumor resection", "nephrectomy for Wilms", "neuroblastoma", "neuroblastoma resection", "hepatoblastoma resection"], ga, upper, long, risk: true),
        p("imaging-sedation", "Anesthesia for imaging", ["MRI under anesthesia", "MRI sedation", "anesthesia for MRI", "CT under anesthesia", "imaging under anesthesia", "radiation therapy sedation", "proton therapy anesthesia"], mac, per, short),
        p("lp-bma", "Lumbar puncture or bone marrow aspirate", ["lumbar puncture", "LP", "intrathecal chemotherapy", "IT chemo", "bone marrow aspirate", "BMA", "LP and BMA", "LP/BMA"], mac, per, short),
        heart("pda-ligation", "PDA ligation", ["patent ductus arteriosus ligation", "PDA clip", "ductus ligation", "PDA closure surgical"], ga, chest, short),
        heart("bt-shunt", "Blalock-Taussig shunt", ["BT shunt", "modified BT shunt", "MBTS", "systemic to pulmonary shunt", "central shunt"], ga, chest, mid),
        heart("coarctation", "Coarctation repair", ["coarctation", "coarctectomy", "CoA repair", "aortic coarctation repair", "extended end to end anastomosis"], ga, chest, mid),
        heart("tof-repair", "Tetralogy of Fallot repair", ["TOF repair", "tetralogy repair", "tetralogy of Fallot complete repair", "transannular patch"]),
        heart("avsd-repair", "Atrioventricular canal repair", ["AVSD repair", "AV canal repair", "CAVC repair", "complete AV canal", "endocardial cushion defect repair"]),
        heart("arterial-switch", "Arterial switch operation", ["arterial switch", "ASO", "Jatene", "Jatene procedure", "TGA repair"]),
        heart("norwood", "Norwood procedure", ["Norwood", "stage 1 palliation", "Sano shunt", "Norwood Sano", "hybrid stage 1"]),
        heart("glenn", "Glenn procedure", ["Glenn", "bidirectional Glenn", "BDG", "Glenn shunt", "hemi Fontan", "superior cavopulmonary anastomosis"]),
        heart("fontan", "Fontan procedure", ["Fontan", "Fontan completion", "extracardiac Fontan", "TCPC", "total cavopulmonary connection"]),
    ]
}
