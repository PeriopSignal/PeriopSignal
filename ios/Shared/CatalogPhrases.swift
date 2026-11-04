import Foundation

// MARK: - Lists typed in one line, read against a catalog (1.9)
//
// What the medication and allergy lists share: the words of a typed line with their place in it, where one item ends
// and the next begins (a comma, a semicolon, a new line, "+", a sentence's full stop; commas inside parentheses do not
// count), and a phrase table that finds the longest catalog name at a word ("insulin glargine" before "insulin") and
// ranks a typed prefix for the type-ahead. Matching ignores case, accents and apostrophes ("St. John's wort").

/// A word of a typed line: letters and digits ("0.5" and "#3" are one word each), folded for matching, with where it
/// sits in the line.
struct CatalogWord: Hashable {
    var key: String
    var range: Range<String.Index>

    /// A dose word: a number ("25", "0.5", "25mg", "#3").
    var isNumeric: Bool { key.first.map { $0.isNumber || $0 == "#" } ?? false }
    var isLetters: Bool { !key.isEmpty && key.allSatisfy(\.isLetter) }
}

enum CatalogText {
    /// Lowercased, without accents or apostrophes.
    static func fold(_ s: String) -> String {
        var f = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        f.removeAll { $0 == "'" || $0 == "’" }
        return f
    }

    static func words(_ s: String) -> [CatalogWord] {
        var out: [CatalogWord] = []
        let end = s.endIndex
        var i = s.startIndex
        while i < end {
            let c = s[i]
            let next = s.index(after: i)
            let hash = c == "#" && next < end && s[next].isNumber
            guard c.isLetter || c.isNumber || hash else { i = next; continue }
            var j = next
            while j < end {
                let d = s[j]
                if d.isLetter || d.isNumber { j = s.index(after: j); continue }
                let k = s.index(after: j)
                // An apostrophe inside a word ("John's"), a decimal point inside a number ("0.5").
                if d == "'" || d == "’", k < end, s[k].isLetter { j = k; continue }
                if d == ".", s[s.index(before: j)].isNumber, k < end, s[k].isNumber { j = k; continue }
                break
            }
            out.append(CatalogWord(key: fold(String(s[i..<j])), range: i..<j))
            i = j
        }
        return out
    }

    /// For each word, whether a new item starts at it: a comma (not "1,000"), semicolon, new line, bullet or "+" before
    /// it outside parentheses, or a full stop and a space after a word ("held. Lisinopril"; not "St. John's").
    static func breaks(_ s: String, _ words: [CatalogWord]) -> [Bool] {
        var out = Array(repeating: false, count: words.count)
        var depth = 0
        var from = s.startIndex
        for (n, w) in words.enumerated() {
            let gap = s[from..<w.range.lowerBound]
            var brk = false
            var prev: Character?
            for ch in gap {
                switch ch {
                case "(", "[": depth += 1
                case ")", "]": depth = max(0, depth - 1)
                case ";", "\n", "•", "+":
                    if depth == 0 { brk = true }
                case ",":
                    // "1,000": a thousands comma.
                    let thousands = n > 0 && words[n - 1].isNumeric && w.isNumeric && gap.count == 1
                    if depth == 0 && !thousands { brk = true }
                default: break
                }
                if ch.isWhitespace, prev == ".", depth == 0, n > 0, words[n - 1].key.count >= 3, !words[n - 1].isNumeric { brk = true }
                prev = ch
            }
            if n > 0 { out[n] = brk }
            from = w.range.upperBound
        }
        return out
    }

    /// Ranges of the text as one string, joined by `separator`, with parentheses balanced: the leftover words of a dose
    /// or a reaction ("25 mg bid", "rash, hives").
    static func text(_ s: String, runs: [Range<String.Index>], separator: String = " ") -> String {
        var t = runs.map { String(s[$0]) }.joined(separator: separator)
        // A closing parenthesis with no opening one goes; an opening one gets its close.
        var depth = 0
        var kept = ""
        for ch in t {
            if ch == "(" { depth += 1 } else if ch == ")" { if depth == 0 { continue }; depth -= 1 }
            kept.append(ch)
        }
        t = kept + String(repeating: ")", count: depth)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—=@").union(.whitespacesAndNewlines))
        // "(hives)": the parentheses around the whole of it go.
        if t.hasPrefix("("), t.hasSuffix(")"), !t.dropFirst().dropLast().contains("("), !t.dropFirst().dropLast().contains(")") {
            t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    /// Consecutive word indices as ranges of the text.
    static func runs(_ s: String, _ words: [CatalogWord], _ indices: [Int]) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: Int?
        var last = -2
        for i in indices {
            if i == last + 1, start != nil {
                last = i
                continue
            }
            if let a = start { out.append(words[a].range.lowerBound..<words[last].range.upperBound) }
            start = i
            last = i
        }
        if let a = start { out.append(words[a].range.lowerBound..<words[last].range.upperBound) }
        // A closing parenthesis right after a run belongs to it ("(held today)").
        return out.map { r in
            var u = r.upperBound
            while u < s.endIndex, s[u] == ")" || s[u] == "%" { u = s.index(after: u) }
            return r.lowerBound..<u
        }
    }
}

/// A catalog's names and aliases as word sequences: the longest one at a word, an exact name, and a ranked prefix search.
struct CatalogPhrases {
    struct Phrase {
        var words: [String]
        var entry: Int
        var isName: Bool
        /// As the catalog writes it.
        var text: String
    }

    struct Hit {
        var entry: Int
        var phrase: Int
        var score: Int
    }

    let phrases: [Phrase]
    /// The phrases by their first word, longest first.
    private let byFirst: [String: [Int]]
    /// Every beginning of every word → the phrases with such a word, sorted.
    private let byPrefix: [String: [Int]]
    /// The words joined by a space → the entry.
    private let exactTable: [String: Int]

    /// Each entry's name, then its aliases, numbered in catalog order.
    static func forms(_ entries: [(name: String, aliases: [String])]) -> [(entry: Int, text: String, isName: Bool)] {
        var out: [(entry: Int, text: String, isName: Bool)] = []
        for (i, e) in entries.enumerated() {
            out.append((entry: i, text: e.name, isName: true))
            for a in e.aliases { out.append((entry: i, text: a, isName: false)) }
        }
        return out
    }

    /// `forms`: each entry's name and aliases, in catalog order; a form already taken by an earlier entry is skipped.
    init(forms: [(entry: Int, text: String, isName: Bool)]) {
        var list: [Phrase] = []
        var seen = Set<[String]>()
        for f in forms {
            let w = CatalogText.words(f.text).map(\.key)
            guard !w.isEmpty, seen.insert(w).inserted else { continue }
            list.append(Phrase(words: w, entry: f.entry, isName: f.isName, text: f.text))
        }
        phrases = list
        var first: [String: [Int]] = [:]
        var exact: [String: Int] = [:]
        var byWord: [String: Set<Int>] = [:]
        for (pi, p) in list.enumerated() {
            first[p.words[0], default: []].append(pi)
            exact[p.words.joined(separator: " ")] = p.entry
            for w in p.words { byWord[w, default: []].insert(pi) }
        }
        byFirst = first.mapValues { ids in
            ids.sorted { a, b in list[a].words.count != list[b].words.count ? list[a].words.count > list[b].words.count : a < b }
        }
        var prefix: [String: Set<Int>] = [:]
        for (w, set) in byWord {
            var p = ""
            for c in w {
                p.append(c)
                prefix[p, default: []].formUnion(set)
            }
        }
        byPrefix = prefix.mapValues { $0.sorted() }
        exactTable = exact
    }

    /// The longest phrase starting at word `i`: its entry and how many words it takes.
    func longest(_ words: [CatalogWord], at i: Int) -> (entry: Int, count: Int)? {
        guard i < words.count, let list = byFirst[words[i].key] else { return nil }
        for pi in list {
            let p = phrases[pi]
            guard i + p.words.count <= words.count else { continue }
            var ok = true
            for k in 1..<p.words.count where words[i + k].key != p.words[k] {
                ok = false
                break
            }
            if ok { return (p.entry, p.words.count) }
        }
        return nil
    }

    /// The entry a whole text names exactly ("Toprol XL", "insulin glargine").
    func exact(_ s: String) -> Int? {
        exactTable[CatalogText.words(s).map(\.key).joined(separator: " ")]
    }

    /// Ranked: the whole name or alias typed, then names and aliases that start with what was typed, word by word
    /// ("ins gla" finds insulin glargine), then those with every typed word starting one of their words. Ties go to a
    /// boosted entry (the most prescribed), a name over an alias, the shorter phrase, then catalog order. One hit per
    /// entry, the best.
    func search(_ q: String, limit: Int, boost: (Int) -> Int) -> [Hit] {
        let qw = CatalogText.words(q).map(\.key)
        guard let first = qw.first, limit > 0, let candidates = byPrefix[first] else { return [] }
        var best: [Int: Hit] = [:]
        for pi in candidates {
            let p = phrases[pi]
            var score: Int
            if p.words == qw {
                score = 1000
            } else if qw.count <= p.words.count, zip(qw, p.words).allSatisfy({ $1.hasPrefix($0) }) {
                score = p.words[qw.count - 1] == qw[qw.count - 1] ? 820 : 800
            } else {
                var pos = 0
                var ok = true
                for (n, w) in qw.enumerated() {
                    guard let k = p.words.firstIndex(where: { $0.hasPrefix(w) }) else { ok = false; break }
                    if n == 0 { pos = k }
                }
                guard ok else { continue }
                score = 500 - min(pos, 9)
            }
            let hit = Hit(entry: p.entry, phrase: pi, score: score)
            if let b = best[p.entry], !better(hit, b) { continue }
            best[p.entry] = hit
        }
        let ranked = best.values.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            let ba = boost(a.entry), bb = boost(b.entry)
            if ba != bb { return ba > bb }
            let pa = phrases[a.phrase], pb = phrases[b.phrase]
            if pa.isName != pb.isName { return pa.isName }
            if pa.text.count != pb.text.count { return pa.text.count < pb.text.count }
            return a.entry < b.entry
        }
        return Array(ranked.prefix(limit))
    }

    private func better(_ a: Hit, _ b: Hit) -> Bool {
        if a.score != b.score { return a.score > b.score }
        let pa = phrases[a.phrase], pb = phrases[b.phrase]
        if pa.isName != pb.isName { return pa.isName }
        return pa.text.count < pb.text.count
    }
}
