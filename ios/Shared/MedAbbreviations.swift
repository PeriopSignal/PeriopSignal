import Foundation

// MARK: - Medical abbreviations
//
// The shorthand Fill from a note reads, by fixed rules on the phone: a built-in list of common perioperative and
// medical abbreviations, and the ones the user saves (kept on the phone by the app and passed in here). A built-in has
// one meaning, or several when it is ambiguous ("RA": rheumatoid arthritis, right atrium or room air), with the context
// that picks one ("SpO2 98% on RA"). Case matters where it changes the meaning: AVR is a replacement, AVr a repair.
// Nothing here keeps, logs or sends the text it reads.

/// One meaning of an abbreviation.
struct AbbreviationMeaning: Hashable, Identifiable {
    /// Stable, for a choice ("room-air").
    var id: String
    /// The expansion as shown ("room air").
    var text: String
    /// What the note reader reads in its place, when that differs ("ASA" for the ASA class, so "ASA 3" stays a class).
    var reading: String

    init(_ text: String, id: String? = nil, reading: String? = nil) {
        self.text = text
        self.id = id ?? MedAbbreviations.slug(text)
        self.reading = reading ?? text
    }
}

/// Where an abbreviation sits in its sentence: patterns for the text just before it, just after it, anywhere near it,
/// or the token itself ("PACs"). Every pattern given must match.
struct AbbreviationContext {
    var before: NoteRx? = nil
    var after: NoteRx? = nil
    var near: NoteRx? = nil
    var token: NoteRx? = nil

    func matches(token t: String, before b: String, after a: String) -> Bool {
        if let token, token.first(t) == nil { return false }
        if let before, before.first(b) == nil { return false }
        if let after, after.first(a) == nil { return false }
        if let near, near.first(b + " … " + a) == nil { return false }
        return !patterns.isEmpty
    }

    var patterns: [NoteRx] { [before, after, near, token].compactMap { $0 } }
}

/// A built-in abbreviation.
struct MedAbbreviation {
    /// As written in the list ("AVr", "HTN", "s/p").
    var key: String
    /// Matched only in this exact case (AVR and AVr; MS but not "ms").
    var caseSensitive: Bool
    /// One meaning, or several when it is ambiguous, the usual one first.
    var meanings: [AbbreviationMeaning]
    /// For an ambiguous one: the context that picks a meaning (by id); the first that matches wins.
    var hints: [(meaning: String, context: AbbreviationContext)]
    /// Context in which the letters are something else ("IV" after "ASA" is a class, "ICD" before "-10" a code).
    var skip: [AbbreviationContext]
    /// False for connecting shorthand ("s/p", "w/", "x3") that the note reader understands as written.
    var reads: Bool

    init(_ key: String, caseSensitive: Bool, meanings: [AbbreviationMeaning], hints: [(meaning: String, context: AbbreviationContext)] = [],
         skip: [AbbreviationContext] = [], reads: Bool = true) {
        self.key = key
        self.caseSensitive = caseSensitive
        self.meanings = meanings
        self.hints = hints
        self.skip = skip
        self.reads = reads
    }

    var isAmbiguous: Bool { meanings.count > 1 }
}

/// An abbreviation found in a text.
struct AbbreviationMatch: Hashable {
    enum Source: Hashable { case builtIn, user }
    /// As written ("AVr", "PACs").
    var token: String
    /// Where it is in the text read (UTF-16 offsets).
    var range: NSRange
    /// The list's key ("AVr", "HTN"), or the user's abbreviation.
    var key: String
    var source: Source
    /// The meaning read in its place; nil for an ambiguous one left as written.
    var meaning: AbbreviationMeaning?
    /// For an ambiguous one: its meanings, the one the context picked (or the usual one), whether the context picked
    /// it, and the key its choice is kept under ("RA@room-air": the same letters that the context reads differently
    /// are chosen apart).
    var options: [AbbreviationMeaning] = []
    var defaultMeaning: AbbreviationMeaning? = nil
    var fromContext = false
    var choiceKey: String? = nil
    /// False for connecting shorthand the note reader understands as written.
    var reads = true

    var isAmbiguous: Bool { !options.isEmpty }
}

/// An ambiguous abbreviation in a note, for the user to confirm or change.
struct AmbiguousAbbreviation: Hashable, Identifiable {
    /// The key the choice is kept under ("RA@room-air").
    var id: String
    /// "RA".
    var abbreviation: String
    var options: [AbbreviationMeaning]
    /// The meaning the context picked, or the usual one.
    var defaultID: String
    var fromContext: Bool
    /// What is read: the user's choice, else the default; MedAbbreviations.asWritten when left as written.
    var chosenID: String
    /// A few words around its first use.
    var context: String
    /// The value the choice is for ("0.1" after "levo", "95" for a saturation): the quick-add bar keeps it with the
    /// choice and asks again when the value changes. Empty when the choice holds whatever the value.
    var valueKey = ""

    var chosen: AbbreviationMeaning? { options.first { $0.id == chosenID } }
}

/// Letters that look like an abbreviation but are in neither list.
struct UnknownAbbreviation: Hashable, Identifiable {
    var token: String
    /// A few words around its first use.
    var context: String
    var id: String { token }
}

/// A note read for abbreviations.
struct AbbreviationReading {
    /// The text with every abbreviation read replaced by its meaning (ambiguous ones by the choice or the default).
    var expanded: String
    /// Every abbreviation found, in order, with its range in the text.
    var matches: [AbbreviationMatch]
    var ambiguous: [AmbiguousAbbreviation]
    var unknown: [UnknownAbbreviation]
}

/// A range of a text and what replaces it.
struct AbbreviationReplacement {
    var range: NSRange
    var text: String
}

/// A text with some ranges replaced, and where each replacement sits in both texts, so a range found in one can be
/// placed in the other.
struct AbbreviationExpansion {
    struct Span: Hashable {
        var source: NSRange
        var target: NSRange
    }

    var text: String
    var spans: [Span]

    /// A range of the expanded text, in the original; a range that reaches into a replacement covers all of it.
    func source(_ r: NSRange) -> NSRange { map(r, from: \.target, to: \.source) }

    /// A range of the original, in the expanded text.
    func target(_ r: NSRange) -> NSRange { map(r, from: \.source, to: \.target) }

    /// Whether a range of the expanded text overlaps a replacement.
    func touches(_ r: NSRange) -> Bool { spans.contains { NSIntersectionRange($0.target, r).length > 0 } }

    private func map(_ r: NSRange, from: KeyPath<Span, NSRange>, to: KeyPath<Span, NSRange>) -> NSRange {
        let a = position(r.location, end: false, from, to)
        let b = position(r.location + r.length, end: true, from, to)
        return NSRange(location: a, length: max(0, b - a))
    }

    private func position(_ p: Int, end: Bool, _ from: KeyPath<Span, NSRange>, _ to: KeyPath<Span, NSRange>) -> Int {
        var delta = 0
        for s in spans {
            let f = s[keyPath: from], t = s[keyPath: to]
            if p <= f.location { break }
            if p >= f.location + f.length {
                delta = (t.location + t.length) - (f.location + f.length)
                continue
            }
            return end ? t.location + t.length : t.location
        }
        return p + delta
    }
}

enum MedAbbreviations {
    /// The choice for an ambiguous abbreviation the user leaves as written.
    static let asWritten = ""

    /// Exact-case keys, and the others by their lower case.
    private static let exact: [String: MedAbbreviation] = Dictionary(all.filter(\.caseSensitive).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    private static let anyCase: [String: MedAbbreviation] = Dictionary(all.filter { !$0.caseSensitive }.map { ($0.key.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })

    /// How many abbreviations the list holds (each spelling counted once).
    static var count: Int { exact.count + anyCase.count }

    /// The built-in abbreviation these letters are, in this case ("AVr" and "AVR" differ; "htn" is "HTN").
    static func lookup(_ token: String) -> MedAbbreviation? {
        let t = token.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if let e = exact[t] ?? anyCase[t.lowercased()] { return e }
        if t.count > 2, t.hasSuffix("s") {
            let s = String(t.dropLast())
            return exact[s] ?? anyCase[s.lowercased()]
        }
        return nil
    }

    // MARK: Reading

    /// The reading pipeline: what a note's abbreviations mean, which are ambiguous (with the default and the choice),
    /// and which letters look like abbreviations but are in neither list. `user` is the user's own [abbreviation:
    /// meaning]; `choices` holds the user's choices by AmbiguousAbbreviation.id.
    static func read(_ text: String, user: [String: String] = [:], choices: [String: String] = [:]) -> AbbreviationReading {
        let matches = scan(text, user: user, choices: choices)
        let x = expand(text, matches.compactMap { m -> AbbreviationReplacement? in
            guard let meaning = m.meaning else { return nil }
            return AbbreviationReplacement(range: m.range, text: meaning.text)
        })
        return AbbreviationReading(expanded: x.text, matches: matches, ambiguous: ambiguous(matches, in: text),
                                   unknown: unknown(in: text, besides: matches, user: user))
    }

    /// Every abbreviation in a text, in order: the user's own first (they may mean something the list does not), then
    /// the list's, with the meaning read (an ambiguous one's from the user's choice, else from the context).
    static func scan(_ text: String, user: [String: String] = [:], choices: [String: String] = [:]) -> [AbbreviationMatch] {
        let ns = text as NSString
        var out: [AbbreviationMatch] = []
        for m in userRx(user)?.all(text) ?? [] {
            let token = ns.substring(with: m.range)
            guard let mine = userMeaning(token, user) else { continue }
            out.append(AbbreviationMatch(token: token, range: m.range, key: mine.key, source: .user, meaning: AbbreviationMeaning(mine.meaning, id: "user")))
        }
        let taken = out.map(\.range)
        for m in matcher.all(text) where !taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
            let token = ns.substring(with: m.range)
            guard let e = lookup(token) else { continue }
            let (before, after) = sentence(around: m.range, in: ns)
            if e.skip.contains(where: { $0.matches(token: token, before: before, after: after) }) { continue }
            // In a note written in capitals, "AS" and "OR" are words.
            if e.caseSensitive, englishWords.contains(token.lowercased()), isShouting(before + token + after) { continue }
            guard e.isAmbiguous else {
                out.append(AbbreviationMatch(token: token, range: m.range, key: e.key, source: .builtIn, meaning: e.meanings[0], reads: e.reads))
                continue
            }
            let picked = e.hints.first { $0.context.matches(token: token, before: before, after: after) }
            let def = e.meanings.first { $0.id == picked?.meaning } ?? e.meanings[0]
            let key = e.key + "@" + def.id
            let choice = choices[key] ?? def.id
            let meaning = choice == asWritten ? nil : (e.meanings.first { $0.id == choice } ?? def)
            out.append(AbbreviationMatch(token: token, range: m.range, key: e.key, source: .builtIn, meaning: meaning, options: e.meanings,
                                         defaultMeaning: def, fromContext: picked != nil, choiceKey: key, reads: e.reads))
        }
        return out.sorted { $0.range.location < $1.range.location }
    }

    /// The ambiguous abbreviations among matches, one per choice key, in order of first use.
    static func ambiguous(_ matches: [AbbreviationMatch], in text: String) -> [AmbiguousAbbreviation] {
        var out: [AmbiguousAbbreviation] = []
        for m in matches where m.isAmbiguous {
            guard let id = m.choiceKey, let def = m.defaultMeaning, !out.contains(where: { $0.id == id }) else { continue }
            out.append(AmbiguousAbbreviation(id: id, abbreviation: m.key, options: m.options, defaultID: def.id, fromContext: m.fromContext,
                                             chosenID: m.meaning?.id ?? asWritten, context: snippet(text, around: m.range)))
        }
        return out
    }

    /// Letters that look like an abbreviation (2 to 6 letters, in capitals or mixed case: "XYZQ", "AVr") but are not in
    /// either list, nor a unit, a Roman numeral, a common English word, or initials after "Dr".
    static func unknown(in text: String, besides matches: [AbbreviationMatch], user: [String: String] = [:]) -> [UnknownAbbreviation] {
        let ns = text as NSString
        let shouting = isShouting(text)
        var out: [UnknownAbbreviation] = []
        for m in tokenRx.all(text) where !matches.contains(where: { NSIntersectionRange($0.range, m.range).length > 0 }) {
            guard let core = candidate(ns.substring(with: m.range), shouting: shouting), user[core] == nil else { continue }
            if titleBefore.first(ns.substring(to: m.range.location)) != nil { continue }
            if !out.contains(where: { $0.token == core }) { out.append(UnknownAbbreviation(token: core, context: snippet(text, around: m.range))) }
        }
        return out
    }

    /// The letters of a token that could be an unknown abbreviation, or nil for a word, a unit or a known one.
    static func candidate(_ token: String, shouting: Bool = false) -> String? {
        var t = token
        if t.hasSuffix("'s") || t.hasSuffix("’s") { t = String(t.dropLast(2)) }
        if t.count >= 3, t.hasSuffix("s"), t.dropLast().allSatisfy(\.isUppercase) { t = String(t.dropLast()) }
        guard t.allSatisfy({ $0.isASCII && $0.isLetter }), t.count >= 2, t.count <= (shouting ? 4 : 6) else { return nil }
        let upper = t.filter(\.isUppercase).count
        // All lower case, or a capitalized word: not an abbreviation candidate.
        guard upper >= 2 || (upper == 1 && t.first?.isUppercase == false) else { return nil }
        let lower = t.lowercased()
        if englishWords.contains(lower) || units.contains(lower) || romanNumerals.contains(t) || lookup(t) != nil { return nil }
        return t
    }

    /// A text with ranges replaced (ranges that overlap an earlier one are skipped).
    static func expand(_ text: String, _ items: [AbbreviationReplacement]) -> AbbreviationExpansion {
        let ns = text as NSString
        var out = ""
        var length = 0
        var at = 0
        var spans: [AbbreviationExpansion.Span] = []
        for item in items.sorted(by: { $0.range.location < $1.range.location }) where item.range.location >= at && item.range.location + item.range.length <= ns.length {
            let gap = ns.substring(with: NSRange(location: at, length: item.range.location - at))
            out += gap
            length += (gap as NSString).length
            let w = (item.text as NSString).length
            spans.append(AbbreviationExpansion.Span(source: item.range, target: NSRange(location: length, length: w)))
            out += item.text
            length += w
            at = item.range.location + item.range.length
        }
        out += ns.substring(from: min(at, ns.length))
        return AbbreviationExpansion(text: out, spans: spans)
    }

    /// A few whole words either side of a range, on one line ("…98% on RA").
    static func snippet(_ text: String, around r: NSRange, radius: Int = 22) -> String {
        let ns = text as NSString
        func word(_ i: Int) -> Bool { i >= 0 && i < ns.length && (UnicodeScalar(ns.character(at: i)).map { CharacterSet.alphanumerics.contains($0) } ?? true) }
        var s = max(0, r.location - radius)
        var e = min(ns.length, r.location + r.length + radius)
        while s > 0, s < r.location, word(s - 1), word(s) { s += 1 }
        while e < ns.length, e > r.location + r.length, word(e - 1), word(e) { e -= 1 }
        let safe = ns.rangeOfComposedCharacterSequences(for: NSRange(location: s, length: e - s))
        var t = ns.substring(with: safe).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let cut = CharacterSet(charactersIn: " ,;:")
        if safe.location > 0 {
            while let c = t.unicodeScalars.first, cut.contains(c) { t.removeFirst() }
            t = "…" + t
        }
        if safe.location + safe.length < ns.length {
            while let c = t.unicodeScalars.last, cut.contains(c) { t.removeLast() }
            t += "…"
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    // MARK: Matching

    /// One pattern for every key, longest first so "GLP-1 RA" wins over "RA"; capitals take a plural "s" ("PACs").
    private static let matcher: NoteRx = {
        let keys = all.map { ($0.key, $0.caseSensitive) }.sorted { $0.0.count > $1.0.count }
        return NoteRx(keys.map { alternative($0.0, caseSensitive: $0.1) }.joined(separator: "|"), caseSensitive: true)
    }()

    private static func alternative(_ k: String, caseSensitive: Bool) -> String {
        guard let first = k.first, let last = k.last else { return "(?!)" }
        var p = k.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\s+"#)
        if !caseSensitive { p = "(?i:" + p + ")" }
        let letters = k.filter(\.isLetter)
        if !letters.isEmpty, letters.allSatisfy(\.isUppercase), last.isLetter || last.isNumber { p += "(?:s)?" }
        let left = first.isLetter || first.isNumber ? "(?<![A-Za-z0-9])" : ""
        let right = last.isLetter || last.isNumber ? "(?![A-Za-z0-9])" : ""
        return left + p + right
    }

    private static func userRx(_ user: [String: String]) -> NoteRx? {
        let keys = user.keys.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.sorted { $0.count > $1.count }
        guard !keys.isEmpty else { return nil }
        return NoteRx(keys.map { alternative($0, caseSensitive: true) }.joined(separator: "|"), caseSensitive: true)
    }

    private static func userMeaning(_ token: String, _ user: [String: String]) -> (key: String, meaning: String)? {
        if let m = user[token] { return (token, m) }
        if token.count > 2, token.hasSuffix("s"), let m = user[String(token.dropLast())] { return (String(token.dropLast()), m) }
        return nil
    }

    /// The text before and after a range, within its sentence and at most 60 characters each way.
    private static func sentence(around r: NSRange, in ns: NSString) -> (String, String) {
        func ends(_ i: Int) -> Bool {
            let c = ns.character(at: i)
            if c == 10 || c == 13 || c == 59 { return true }
            if c == 46, i + 1 < ns.length, let u = UnicodeScalar(ns.character(at: i + 1)), CharacterSet.whitespaces.contains(u) { return true }
            return false
        }
        var s = r.location
        while s > 0, r.location - s < 60, !ends(s - 1) { s -= 1 }
        var e = r.location + r.length
        while e < ns.length, e - (r.location + r.length) < 60, !ends(e) { e += 1 }
        func text(_ range: NSRange) -> String {
            guard range.length > 0, range.location >= 0, range.location + range.length <= ns.length else { return "" }
            return ns.substring(with: ns.rangeOfComposedCharacterSequences(for: range))
        }
        return (text(NSRange(location: s, length: r.location - s)), text(NSRange(location: r.location + r.length, length: e - r.location - r.length)))
    }

    /// Mostly capitals: an all-caps note, where only short tokens are taken for abbreviations.
    private static func isShouting(_ text: String) -> Bool {
        let letters = text.filter { $0.isASCII && $0.isLetter }
        guard letters.count >= 12 else { return false }
        return Double(letters.filter(\.isUppercase).count) / Double(letters.count) > 0.7
    }

    private static let tokenRx = NoteRx(#"(?<![A-Za-z0-9])[A-Za-z][A-Za-z0-9]*(?:['’]s)?(?![A-Za-z0-9])"#, caseSensitive: true)
    private static let titleBefore = NoteRx(#"\b(?:dr|mr|mrs|ms|miss|mx|prof)\.?\s*$"#)

    static let units: Set<String> = [
        "mg", "mcg", "ug", "kg", "gm", "ml", "dl", "cc", "cm", "mm", "mmhg", "cmh", "bpm", "iu", "meq", "mmol", "umol", "nmol", "pmol",
        "mol", "hz", "mhz", "khz", "kpa", "kcal", "cal", "hr", "hrs", "min", "mins", "sec", "secs", "wk", "wks", "mo", "mos", "yr", "yrs",
        "lb", "lbs", "oz", "ft", "fr", "mosm", "ng", "pg", "miu", "uiu", "mu", "ppm", "wu", "mv", "ms", "lpm", "am", "pm", "mcl", "ul",
        "dyn", "dynes", "gy", "cgy", "mgy", "msv", "mph", "kph", "mmh", "rpm",
    ]

    static let romanNumerals: Set<String> = ["II", "III", "IV", "VI", "VII", "VIII", "IX", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX"]

    /// Every pattern, for the test that each one compiles.
    static var allPatterns: [NoteRx] {
        var out = [matcher, tokenRx, titleBefore]
        for e in all {
            out += e.hints.flatMap { $0.context.patterns }
            out += e.skip.flatMap { $0.patterns }
        }
        return out
    }
}

// MARK: - The list

extension MedAbbreviations {
    /// Every built-in abbreviation: the ambiguous ones first (they win a clash), then those with one meaning.
    static let all: [MedAbbreviation] = ambiguousList + rows(anyCaseRows, caseSensitive: false) + rows(exactCaseRows, caseSensitive: true)
        + rows(connectorRows, caseSensitive: false, reads: false) + rows(exactConnectorRows, caseSensitive: true, reads: false)
        + generatedRows + contextual

    /// "KEY|VARIANT" → meaning: each spelling becomes an entry with that one meaning.
    private static func rows(_ list: [(String, String)], caseSensitive: Bool, reads: Bool = true) -> [MedAbbreviation] {
        list.flatMap { keys, text in
            keys.split(separator: "|").map { MedAbbreviation(String($0), caseSensitive: caseSensitive, meanings: [AbbreviationMeaning(text)], reads: reads) }
        }
    }

    private static func m(_ text: String, _ id: String, reading: String? = nil) -> AbbreviationMeaning { AbbreviationMeaning(text, id: id, reading: reading) }

    private static func entry(_ key: String, _ meanings: [AbbreviationMeaning], cs: Bool = true, hints: [(meaning: String, context: AbbreviationContext)],
                              skip: [AbbreviationContext] = []) -> MedAbbreviation {
        MedAbbreviation(key, caseSensitive: cs, meanings: meanings, hints: hints, skip: skip)
    }

    private static func near(_ id: String, _ p: String) -> (meaning: String, context: AbbreviationContext) { (id, AbbreviationContext(near: NoteRx(p))) }
    private static func before(_ id: String, _ p: String) -> (meaning: String, context: AbbreviationContext) { (id, AbbreviationContext(before: NoteRx(p))) }
    private static func after(_ id: String, _ p: String) -> (meaning: String, context: AbbreviationContext) { (id, AbbreviationContext(after: NoteRx(p))) }
    /// The plural ("PACs").
    private static func plural(_ id: String) -> (meaning: String, context: AbbreviationContext) {
        (id, AbbreviationContext(token: NoteRx(#"s$"#, caseSensitive: true)))
    }

    private static let severity = #"\b(?:mild|moderate|mod|severe|critical|trace|trivial|significant|mild[- ]to[- ]moderate|moderate[- ]to[- ]severe|mild-moderate|moderate-severe)\s*$"#
    private static let valve = #"\b(?:valves?|valvular|mitral|aortic|mva|ava|gradients?|mmhg|pht|half[- ]time|cm2|cm²|rheumatic|balloon|commissurotomy|tavr|tavi|savr|mvr|tte|tee|echo\w*|stenosis|regurgitation|insufficiency|murmur|(?-i:AS|AR|MR|TR|AI|LVOT))\b"#
    private static let anticoagulants = #"anticoag\w*|heparin|apixaban|eliquis|rivaroxaban|xarelto|warfarin|coumadin|lovenox|enoxaparin|doac|dabigatran|edoxaban"#
    private static let infusion = #"gtts?|infusions?|drips?|pressors?|vasopressors?|mcg/kg/min|mcg/min|titrat\w*"#

    /// Letters with more than one common meaning, the usual one first, and the context that picks one.
    private static let ambiguousList: [MedAbbreviation] = [
        entry("RA", [m("rheumatoid arthritis", "ra-arthritis"), m("right atrium", "ra-atrium"), m("room air", "ra-air")], hints: [
            before("ra-air", #"(?:\bon|%|\bsats?|\bspo2|\bsao2|\bsatting|\bsaturating)\s*$"#),
            after("ra-air", #"^\s*(?:sats?|spo2|saturation)\b"#),
            near("ra-arthritis", #"\b(?:arthritis|rheum\w*|methotrexate|mtx|plaquenil|hydroxychloroquine|humira|adalimumab|etanercept|enbrel|infliximab|remicade|rituximab|leflunomide|sulfasalazine|tofacitinib|xeljanz|abatacept|tocilizumab|joints?|deformit\w*|flares?|dmards?|biologics?)\b"#),
            near("ra-atrium", #"\b(?:atri(?:um|al)|dilated|dilation|enlarged|enlargement|pressures?|rap|rvsp|tricuspid|ivc|thrombus|mass|leads?|chamber|size|volume|appendage|cvp|svc|(?-i:RV|LA|LV|TR|TV|TTE|TEE))\b"#),
            near("ra-air", #"\b(?:spo2|spo₂|sats?|saturating|saturation|sao2|pulse ox)\b"#),
        ]),
        entry("MS", [m("multiple sclerosis", "ms-sclerosis"), m("mitral stenosis", "ms-mitral"), m("morphine sulfate", "ms-morphine")], hints: [
            before("ms-mitral", severity),
            after("ms-morphine", #"^\s*(?:contin\b|ir\b|er\b|\d+(?:\.\d+)?\s*mg\b)"#),
            near("ms-sclerosis", #"\b(?:relapsing|remitting|progressive|demyelinat\w*|ocrelizumab|ocrevus|interferon|copaxone|glatiramer|tecfidera|natalizumab|tysabri|fingolimod|gilenya|optic neuritis|neurolog\w*|baclofen|spastic\w*|wheelchair|lesions?|mri)\b"#),
            near("ms-mitral", valve),
        ]),
        entry("PE", [m("pulmonary embolism", "pe-embolism"), m("physical exam", "pe-exam", reading: "exam"), m("pleural effusion", "pe-effusion")], hints: [
            after("pe-exam", #"^\s*(?:[:\-–]|(?:is|was)?\s*(?:unremarkable|benign|normal|notable|significant|wnl|within normal)\b)"#),
            near("pe-embolism", #"\b(?:cta|ctpa|ct angio\w*|v/q|vq|"# + anticoagulants + #"|dvt|vte|ivc filter|saddle|segmental|subsegmental|thromboly\w*|tpa|embol\w*|clots?|massive|submassive)\b"#),
            before("pe-exam", #"\b(?:on|per|by|during)\s*$"#),
            near("pe-effusion", #"\b(?:effusions?|thoracentesis|chest tube|pleur\w*|cxr|chest x-?ray|blunting|loculated|tap)\b"#),
        ]),
        entry("PD", [m("Parkinson disease", "pd-parkinson"), m("peritoneal dialysis", "pd-dialysis")], hints: [
            near("pd-parkinson", #"\b(?:parkinson\w*|sinemet|carbidopa|levodopa|tremors?|rigidity|dbs|deep brain|neurolog\w*|pramipexole|ropinirole|rasagiline|selegiline|entacapone|amantadine|bradykinesia|gait|shuffl\w*)\b"#),
            before("pd-dialysis", #"\b(?:on|via|nightly|home|does|receives|getting|started|for)\s*$"#),
            near("pd-dialysis", #"\b(?:dialysis|esrd|eskd|ckd|catheter|cycler|capd|ccpd|exchanges?|dwells?|peritonitis|renal|kidney|tenckhoff|(?-i:HD))\b"#),
        ]),
        entry("ASA", [m("aspirin", "asa-aspirin"), m("ASA physical status", "asa-class", reading: "ASA")], hints: [
            after("asa-class", #"^\s*(?:class|ps|physical status|score|status)?\s*[:=]?\s*(?:VI|IV|V|III|II|I|[1-6])(?:\s*E)?\b(?!\s*mg)"#),
            after("asa-class", #"^\s*(?:class|ps|physical status)\b"#),
        ]),
        entry("MAC", [m("monitored anesthesia care", "mac-care"), m("Macintosh blade", "mac-blade"), m("minimum alveolar concentration", "mac-alveolar"),
                      m("mitral annular calcification", "mac-annular"), m("multi-access catheter", "mac-catheter")], hints: [
            after("mac-blade", #"^\s*#?\s*[1-5]\b(?!\s*(?:%|mg|cm|mm))"#),
            before("mac-care", #"\b(?:under|with|via|plan(?:ned)?|for|anesthesia|anesthetic|anaesthesia)\s*:?\s*(?:a\s+)?$"#),
            after("mac-care", #"^\s*(?:with|w/|and|vs\.?|/|or|sedation|anesthesia|case|\+)"#),
            before("mac-alveolar", #"(?:\b\d+(?:\.\d+)?|\bhalf|\bone)\s*$"#),
            before("mac-annular", severity),
            near("mac-blade", #"\b(?:blades?|laryngoscop\w*|grade|view|miller|intubat\w*|glide\w*|bougie|(?-i:DL|VL|ETT))\b"#),
            near("mac-catheter", #"\b(?:introducer|cordis|swan|sheath|internal jugular|subclavian|femoral|lumens?|french|(?-i:PAC|CVC|IJ|RIJ|LIJ))\b"#),
            near("mac-annular", #"\b(?:mitral|annul\w*|calcif\w*|echo\w*|tte|tee|valves?|gradients?|(?-i:MR|MS))\b"#),
            near("mac-alveolar", #"\b(?:sevo\w*|desflurane|isoflurane|volatile|agents?|end[- ]tidal|inhal\w*|(?-i:ET|EtCO2))\b"#),
        ]),
        entry("PAC", [m("pulmonary artery catheter", "pac-catheter"), m("premature atrial contraction", "pac-beat")], hints: [
            plural("pac-beat"),
            near("pac-beat", #"\b(?:ecg|ekg|holter|telemetry|tele|ectopy|ectopic|pvcs?|palpitations|occasional|frequent|rare|sinus|nsr|rhythm|beats?|bigeminy|trigeminy)\b"#),
        ]),
        entry("CVA", [m("stroke", "cva-stroke"), m("costovertebral angle", "cva-angle")], cs: false, hints: [
            after("cva-angle", #"^\s*(?:tenderness|ttp|pain)\b"#),
            near("cva-angle", #"\b(?:tenderness|flank|pyelo\w*|nephrolith\w*|kidney stones?|dysuria)\b"#),
        ]),
        entry("HD", [m("hemodialysis", "hd-dialysis"), m("hospital day", "hd-day"), m("hemodynamically", "hd-hemo"), m("Huntington disease", "hd-huntington")], hints: [
            after("hd-day", #"^\s*#?\s*\d{1,2}\b(?!\s*(?:x|times|days?\s*(?:a|per)|/\s*w))"#),
            after("hd-hemo", #"^\s*(?:stable|unstable|instability|significant)\b"#),
            near("hd-huntington", #"\b(?:huntington\w*|chorea|choreiform|tetrabenazine|deutetrabenazine)\b"#),
        ]),
        entry("CP", [m("chest pain", "cp-pain"), m("cerebral palsy", "cp-palsy")], hints: [
            near("cp-palsy", #"\b(?:spastic\w*|quadripleg\w*|dipleg\w*|hemipleg\w*|g-?tube|baclofen|contractures?|nonverbal|non-verbal|developmental|seizures?|scoliosis|wheelchair|prematur\w*)\b"#),
        ], skip: [AbbreviationContext(before: NoteRx(#"\bimpella\s*$"#))]),
        entry("AS", [m("aortic stenosis", "as-aortic"), m("ankylosing spondylitis", "as-spondylitis")], hints: [
            before("as-aortic", severity),
            near("as-spondylitis", #"\b(?:spondyl\w*|spine|spinal|cervical|neck|fusion|fused|kyphosis|bamboo|sacroiliitis|hla-?b27|humira|adalimumab|etanercept|enbrel|infliximab|remicade|secukinumab|cosentyx|rheum\w*)\b"#),
        ]),
        entry("LA", [m("left atrium", "la-atrium"), m("local anesthetic", "la-local")], hints: [
            near("la-local", #"\b(?:lido\w*|bupi\w*|ropi\w*|chloroprocaine|mepivacaine|infiltrat\w*|toxicity|blocks?|injection|local|wound|ml)\b"#),
        ]),
        entry("PS", [m("pulmonic stenosis", "ps-pulmonic"), m("pressure support", "ps-support")], hints: [
            after("ps-support", #"^\s*(?:of\s*|:\s*)?\d"#),
            near("ps-support", #"\b(?:peep|vent\w*|cpap|fio2|sbt|extubat\w*|intubat\w*|psv|trach\w*)\b"#),
        ], skip: [AbbreviationContext(before: NoteRx(#"\basa\s*(?:class\s*)?$"#))]),
        entry("PR", [m("pulmonic regurgitation", "pr-pulmonic"), m("PR interval", "pr-interval"), m("per rectum", "pr-rectal")], hints: [
            // "trivial PR", "trace PR", "mild PR": a grade before it is the valve (1.8.1).
            before("pr-pulmonic", severity),
            near("pr-interval", #"\b(?:interval|msec|ms|prolonged|ecg|ekg|qrs|qtc|av block|first[- ]degree|1st degree)\b"#),
            near("pr-rectal", #"\b(?:suppositor\w*|tylenol|acetaminophen|rectal\w*|mg)\b"#),
        ]),
        entry("PDA", [m("patent ductus arteriosus", "pda-ductus"), m("posterior descending artery", "pda-artery")], hints: [
            near("pda-artery", #"\b(?:svg|lima|rima|grafts?|grafted|cabg|stents?|stented|pci|des|bms|lesions?|occlu\w*|stenosis|dominan\w*|(?-i:LAD|RCA|LCx|OM|D1))\b|%"#),
        ]),
        entry("PVR", [m("pulmonary vascular resistance", "pvr-resistance"), m("post-void residual", "pvr-residual"), m("pulmonary valve replacement", "pvr-valve")], hints: [
            before("pvr-valve", #"\b(?:s/p|status post|prior|previous|h/o|hx of|history of)\s*$"#),
            near("pvr-valve", #"\b(?:tetralogy|tof|homograft|melody|conduit|ross|pulmonary valve)\b"#),
            near("pvr-residual", #"\b(?:bladder|void\w*|urin\w*|retention|bph|foley|straight cath\w*|ml)\b"#),
        ]),
        entry("BS", [m("blood sugar", "bs-sugar"), m("bowel sounds", "bs-bowel"), m("breath sounds", "bs-breath")], hints: [
            after("bs-sugar", #"^\s*(?:of\s*|is\s*|:\s*)?\d{2,3}\b"#),
            near("bs-bowel", #"\b(?:abd\w*|bowel|soft|nontender|non-tender|distended|hypoactive|hyperactive|(?-i:NT|ND))\b"#),
            near("bs-breath", #"\b(?:lungs?|breath|diminished|decreased|wheez\w*|crackles|rales|rhonchi|bilateral\w*|b/l|auscult\w*)\b"#),
        ]),
        entry("CTA", [m("CT angiography", "cta-angio"), m("clear to auscultation", "cta-clear")], hints: [
            before("cta-clear", #"\blungs?\s*(?:are\s*|were\s*)?:?\s*$"#),
            after("cta-clear", #"^\s*(?:b/?l|bilat\w*|throughout)\b"#),
        ]),
        entry("ETT", [m("endotracheal tube", "ett-tube"), m("exercise treadmill test", "ett-treadmill")], cs: false, hints: [
            near("ett-treadmill", #"\b(?:stress|treadmill|ischemi\w*|mets|bruce|exercise|nuclear|thallium|sestamibi|myoview|perfusion)\b"#),
        ]),
        entry("APAP", [m("acetaminophen", "apap-drug"), m("auto-titrating positive airway pressure", "apap-pap", reading: "auto-titrating CPAP")], cs: false, hints: [
            near("apap-pap", #"\b(?:osa|sleep|apn(?:o)?ea|c-?pap|bi-?pap|mask|nightly|at night|machine|compliant|settings|cmh2o)\b"#),
        ]),
        entry("PAP", [m("pulmonary artery pressure", "pap-artery"), m("positive airway pressure", "pap-airway")], hints: [
            near("pap-airway", #"\b(?:osa|sleep|apn(?:o)?ea|mask|nightly|at night|machine|compliant|c-?pap|bi-?pap)\b"#),
        ]),
        entry("SCD", [m("sequential compression devices", "scd-device"), m("sickle cell disease", "scd-sickle")], hints: [
            near("scd-sickle", #"\b(?:sickle|crisis|crises|hbss|hydroxyurea|vaso-?occlusive|acute chest|exchange transfusion|transfusions?)\b"#),
        ]),
        entry("UA", [m("urinalysis", "ua-urine"), m("unstable angina", "ua-angina")], hints: [
            near("ua-angina", #"\b(?:chest pain|angina|troponin|trop|acs|n?stemi|cath\w*|heparin|ischemi\w*|(?-i:CP|CAD))\b"#),
        ]),
        entry("TAH", [m("total abdominal hysterectomy", "tah-hysterectomy"), m("total artificial heart", "tah-heart")], hints: [
            near("tah-heart", #"\b(?:syncardia|heart|transplant\w*|bridge|vad|biventricular|cardiac)\b"#),
        ]),
        entry("Ca", [m("calcium", "ca-calcium"), m("cancer", "ca-cancer")], hints: [
            near("ca-cancer", #"\b(?:breast|lung|colon|rectal|prostate|pancrea\w*|ovarian|cervical|bladder|renal cell|gastric|esophag\w*|thyroid|skin|metasta\w*|chemo\w*|radiation|xrt|onc\w*|tumou?r|stage|resect\w*|mastectomy|lumpectomy|remission|recurren\w*)\b"#),
        ]),
        entry("levo", [m("norepinephrine", "levo-norepinephrine"), m("levothyroxine", "levo-thyroxine"), m("levofloxacin", "levo-floxacin")], cs: false, hints: [
            near("levo-norepinephrine", #"\b(?:"# + infusion + #"|map|shock)\b"#),
            near("levo-thyroxine", #"\b(?:thyroid|hypothyroid\w*|tsh|synthroid)\b"#),
            near("levo-floxacin", #"\b(?:pneumonia|pna|uti|infection|antibiotics?|abx)\b"#),
        ]),
        entry("dex", [m("dexamethasone", "dex-dexamethasone"), m("dexmedetomidine", "dex-dexmedetomidine")], cs: false, hints: [
            near("dex-dexmedetomidine", #"\b(?:gtts?|infusions?|drips?|mcg/kg/h\w*|mcg/kg|sedation|precedex|rass|load(?:ing)?)\b"#),
        ]),
        entry("epi", [m("epinephrine", "epi-epinephrine"), m("epidural", "epi-epidural")], cs: false, hints: [
            near("epi-epinephrine", #"\b(?:"# + infusion + #"|mcg|code|acls|anaphyla\w*|push(?:es)?|pen|mg)\b|1:\d"#),
            near("epi-epidural", #"\b(?:labou?r|catheter|cath|lumbar|thoracic|level|dermatomes?|cse|spinal|pcea|test dose|loss of resistance|lor|bolus|[lt]\d{1,2})\b"#),
        ]),
        entry("MVA", [m("motor vehicle accident", "mva-accident"), m("mitral valve area", "mva-area")], hints: [
            after("mva-area", #"^\s*(?:of\s*|is\s*|:\s*|=\s*|~\s*)?\d"#),
            near("mva-area", #"\b(?:mitral|stenosis|cm2|cm²|planimetry|pht|gradients?|echo\w*|tte|tee|(?-i:MS))\b"#),
        ]),
        entry("ASD", [m("atrial septal defect", "asd-defect"), m("autism spectrum disorder", "asd-autism")], hints: [
            near("asd-autism", #"\b(?:autis\w*|developmental|nonverbal|non-verbal|behavio\w*|aba|sensory|asperger\w*)\b"#),
        ]),
        entry("GBS", [m("Guillain-Barré syndrome", "gbs-guillain"), m("group B streptococcus", "gbs-strep")], hints: [
            after("gbs-strep", #"^\s*(?:\+|-|pos\w*|neg\w*|unknown|status|culture|screen)"#),
            near("gbs-strep", #"\b(?:pregnan\w*|labou?r|penicillin|ampicillin|weeks|gestation\w*|ob|delivery|g\d)\b"#),
        ]),
        entry("neo", [m("phenylephrine", "neo-phenylephrine"), m("neonate", "neo-neonate")], cs: false, hints: [
            near("neo-neonate", #"\b(?:infant|nicu|born|newborn|weeks|gestation\w*|birth|apgars?|preterm|premature)\b"#),
        ]),
    ]

    /// Entries with one meaning but a context in which the letters are something else.
    private static let contextual: [MedAbbreviation] = [
        MedAbbreviation("IV", caseSensitive: false, meanings: [AbbreviationMeaning("intravenous")],
                        skip: [AbbreviationContext(before: NoteRx(#"\b(?:asa|class|grade|stage|type|nyha|mallampati|mp|ckd|cn|cranial nerve|phase|level|tier|ccs|gold|ulbt|factor)\s*:?\s*$"#))], reads: false),
        MedAbbreviation("ICD", caseSensitive: true, meanings: [AbbreviationMeaning("implantable cardioverter-defibrillator")],
                        skip: [AbbreviationContext(after: NoteRx(#"^\s*-?\s*(?:9|10|11)\b"#))]),
        MedAbbreviation("K", caseSensitive: true, meanings: [AbbreviationMeaning("potassium")],
                        skip: [AbbreviationContext(before: NoteRx(#"\bvitamin\s*$"#))], reads: false),
        // Also a total ankle arthroplasty, and TAAD also thoracic aortic aneurysm and dissection: the note reader asks
        // about each (PatientNote.readTAA, readDissection), so neither is read through its meaning.
        MedAbbreviation("TAA", caseSensitive: false, meanings: [AbbreviationMeaning("thoracic aortic aneurysm")], reads: false),
        MedAbbreviation("TAAD", caseSensitive: false, meanings: [AbbreviationMeaning("type A aortic dissection; also thoracic aortic aneurysm and dissection")], reads: false),
    ]

    /// Read in any case ("htn" is "HTN").
    private static let anyCaseRows: [(String, String)] = [
        // Cardiovascular history
        ("HTN", "hypertension"), ("HLD", "hyperlipidemia"), ("CAD", "coronary artery disease"), ("CABG", "coronary artery bypass grafting"),
        ("PCI", "percutaneous coronary intervention"), ("PTCA", "percutaneous transluminal coronary angioplasty"),
        ("STEMI", "ST-elevation myocardial infarction"), ("NSTEMI", "non-ST-elevation myocardial infarction"), ("ACS", "acute coronary syndrome"),
        ("IHD", "ischemic heart disease"), ("CHF", "congestive heart failure"), ("HFrEF", "heart failure with reduced ejection fraction"),
        ("HFpEF", "heart failure with preserved ejection fraction"), ("HFmrEF", "heart failure with mildly reduced ejection fraction"),
        ("ADHF", "acute decompensated heart failure"), ("NICM", "non-ischemic cardiomyopathy"), ("ICM", "ischemic cardiomyopathy"),
        ("HCM", "hypertrophic cardiomyopathy"), ("HOCM", "hypertrophic obstructive cardiomyopathy"), ("DCM", "dilated cardiomyopathy"),
        ("afib|a-fib|a fib", "atrial fibrillation"), ("PAF", "paroxysmal atrial fibrillation"), ("AFL|aflutter|a-flutter", "atrial flutter"),
        ("SSS", "sick sinus syndrome"), ("SND", "sinus node dysfunction"), ("SVT", "supraventricular tachycardia"), ("vtach|v-tach", "ventricular tachycardia"),
        ("vfib|v-fib", "ventricular fibrillation"), ("PVC", "premature ventricular contraction"), ("NSR", "normal sinus rhythm"),
        ("RVR", "rapid ventricular response"), ("RBBB", "right bundle branch block"), ("LBBB", "left bundle branch block"), ("BBB", "bundle branch block"),
        ("LAFB", "left anterior fascicular block"), ("CHB", "complete heart block"), ("WPW", "Wolff-Parkinson-White syndrome"), ("LQTS", "long QT syndrome"),
        ("QTc", "corrected QT interval"), ("LVH", "left ventricular hypertrophy"), ("RVH", "right ventricular hypertrophy"), ("LAE", "left atrial enlargement"),
        ("PPM", "permanent pacemaker"), ("AICD", "automatic implantable cardioverter-defibrillator"), ("CRT-D|CRTD", "cardiac resynchronization therapy defibrillator"),
        ("CRT-P|CRTP", "cardiac resynchronization therapy pacemaker"), ("CRT", "cardiac resynchronization therapy"),
        ("S-ICD|SICD", "subcutaneous implantable cardioverter-defibrillator"), ("ILR", "implantable loop recorder"), ("CIED", "cardiac implantable electronic device"),
        ("BiV", "biventricular"), ("MVP", "mitral valve prolapse"), ("BAV", "bicuspid aortic valve"),         ("LVOT", "left ventricular outflow tract"), ("LVOTO", "left ventricular outflow tract obstruction"), ("RVOT", "right ventricular outflow tract"),
        ("PFO", "patent foramen ovale"), ("VSD", "ventricular septal defect"), ("AVSD", "atrioventricular septal defect"),
        ("TOF", "tetralogy of Fallot"), ("TGA", "transposition of the great arteries"), ("HLHS", "hypoplastic left heart syndrome"),
        ("SBE", "subacute bacterial endocarditis"), ("PVD", "peripheral vascular disease"), ("AAA", "abdominal aortic aneurysm"),
        ("TAAA", "thoracoabdominal aortic aneurysm"), ("rAAA", "ruptured abdominal aortic aneurysm"), ("ATAAD", "acute type A aortic dissection"), ("TBAD", "type B aortic dissection"), ("TIA", "transient ischemic attack"), ("DVT", "deep vein thrombosis"), ("VTE", "venous thromboembolism"),
        ("SAH", "subarachnoid hemorrhage"), ("SDH", "subdural hematoma"), ("ICH", "intracerebral hemorrhage"), ("IVH", "intraventricular hemorrhage"),
        ("TBI", "traumatic brain injury"), ("ICP", "intracranial pressure"), ("EVD", "external ventricular drain"), ("VPS|VP shunt", "ventriculoperitoneal shunt"),
        // Respiratory
        ("OSA", "obstructive sleep apnea"), ("OHS", "obesity hypoventilation syndrome"), ("COPD", "chronic obstructive pulmonary disease"),
        ("ILD", "interstitial lung disease"), ("IPF", "idiopathic pulmonary fibrosis"), ("PAH", "pulmonary arterial hypertension"), ("PHTN", "pulmonary hypertension"),
        ("CTEPH", "chronic thromboembolic pulmonary hypertension"), ("ARDS", "acute respiratory distress syndrome"), ("PNA", "pneumonia"),
        ("HAP", "hospital-acquired pneumonia"), ("VAP", "ventilator-associated pneumonia"), ("URI", "upper respiratory infection"),         ("PTX", "pneumothorax"), ("PND", "paroxysmal nocturnal dyspnea"),
        ("CTAB", "clear to auscultation bilaterally"), ("AHI", "apnea-hypopnea index"), ("PFT|PFTs", "pulmonary function tests"), ("FEV1", "forced expiratory volume in 1 second"),
        ("DLCO", "diffusing capacity for carbon monoxide"),
        // Neurologic, musculoskeletal and psychiatric
        ("ALS", "amyotrophic lateral sclerosis"), ("CIDP", "chronic inflammatory demyelinating polyneuropathy"),
        ("SCI", "spinal cord injury"), ("sz", "seizure"), ("LOC", "loss of consciousness"), ("AMS", "altered mental status"), ("CRPS", "complex regional pain syndrome"),
        ("DDD", "degenerative disc disease"), ("DJD", "degenerative joint disease"), ("SLE", "systemic lupus erythematosus"), ("PMR", "polymyalgia rheumatica"),
        ("MDD", "major depressive disorder"), ("GAD", "generalized anxiety disorder"), ("PTSD", "post-traumatic stress disorder"),
        ("ADHD", "attention-deficit/hyperactivity disorder"), ("OCD", "obsessive-compulsive disorder"), ("SUD", "substance use disorder"),
        ("OUD", "opioid use disorder"), ("AUD", "alcohol use disorder"), ("IVDU", "intravenous drug use"), ("IVDA", "intravenous drug abuse"),
        ("MOUD", "medication for opioid use disorder"), ("EtOH", "alcohol"), ("TMJ", "temporomandibular joint"), ("C-spine|c spine", "cervical spine"),
        ("ROM", "range of motion"),
        // GI, liver and renal
        ("GERD", "gastroesophageal reflux disease"), ("PUD", "peptic ulcer disease"), ("GIB|GI bleed", "gastrointestinal bleeding"),
        ("UGIB", "upper gastrointestinal bleeding"), ("LGIB", "lower gastrointestinal bleeding"), ("SBO", "small bowel obstruction"),
        ("LBO", "large bowel obstruction"), ("IBD", "inflammatory bowel disease"), ("IBS", "irritable bowel syndrome"),
        ("NASH", "nonalcoholic steatohepatitis"), ("NAFLD", "nonalcoholic fatty liver disease"),
        ("MASLD", "metabolic dysfunction-associated steatotic liver disease"), ("ESLD", "end-stage liver disease"), ("HBV", "hepatitis B"), ("HCV", "hepatitis C"),
        ("HAV", "hepatitis A"), ("N/V", "nausea and vomiting"), ("LFT|LFTs", "liver function tests"),
        ("CKD", "chronic kidney disease"), ("ESRD", "end-stage renal disease"), ("ESKD", "end-stage kidney disease"), ("AKI", "acute kidney injury"),
        ("ARF", "acute renal failure"), ("CRI", "chronic renal insufficiency"), ("CRRT", "continuous renal replacement therapy"),
        ("CVVH", "continuous venovenous hemofiltration"), ("CVVHD", "continuous venovenous hemodialysis"), ("CVVHDF", "continuous venovenous hemodiafiltration"),
        ("CAPD", "continuous ambulatory peritoneal dialysis"), ("CCPD", "continuous cycling peritoneal dialysis"), ("AVF", "arteriovenous fistula"),
        ("UTI", "urinary tract infection"), ("BPH", "benign prostatic hyperplasia"), ("GFR", "glomerular filtration rate"),
        ("eGFR", "estimated glomerular filtration rate"), ("Cr|creat", "creatinine"), ("SCr", "serum creatinine"),
        ("UOP", "urine output"),
        // Endocrine and hematologic
        ("DM", "diabetes mellitus"), ("DM2|DMII|DM 2|T2DM|T2D", "type 2 diabetes mellitus"), ("DM1|T1DM|T1D", "type 1 diabetes mellitus"),
        ("IDDM", "insulin-dependent diabetes mellitus"), ("NIDDM", "non-insulin-dependent diabetes mellitus"), ("GDM", "gestational diabetes mellitus"),
        ("DKA", "diabetic ketoacidosis"), ("HHS", "hyperosmolar hyperglycemic state"), ("A1c|HbA1c|HgbA1c", "hemoglobin A1c"), ("TSH", "thyroid-stimulating hormone"),
        ("BMI", "body mass index"), ("SIADH", "syndrome of inappropriate antidiuretic hormone"), ("PCOS", "polycystic ovary syndrome"),
        ("Hgb|Hb", "hemoglobin"), ("Hct", "hematocrit"), ("plt|plts", "platelets"), ("WBC", "white blood cell count"), ("INR", "international normalized ratio"),
        ("PTT|aPTT", "partial thromboplastin time"), ("PT/INR", "prothrombin time and INR"), ("ITP", "immune thrombocytopenia"),
        ("TTP", "thrombotic thrombocytopenic purpura"), ("vWD", "von Willebrand disease"), ("vWF", "von Willebrand factor"), ("DIC", "disseminated intravascular coagulation"),
        ("HbSS", "sickle cell disease"), ("G6PD", "glucose-6-phosphate dehydrogenase deficiency"), ("APLS", "antiphospholipid syndrome"), ("FVL", "factor V Leiden"),
        ("PRBC|PRBCs", "packed red blood cells"), ("FFP", "fresh frozen plasma"), ("cryo", "cryoprecipitate"), ("TXA", "tranexamic acid"),
        ("PCC", "prothrombin complex concentrate"), ("MTP", "massive transfusion protocol"), ("EBL", "estimated blood loss"), ("T&S", "type and screen"),
        ("T&C", "type and crossmatch"),
        // Infection
        ("HIV", "human immunodeficiency virus"), ("MRSA", "methicillin-resistant Staphylococcus aureus"),
        ("MSSA", "methicillin-susceptible Staphylococcus aureus"), ("VRE", "vancomycin-resistant enterococcus"), ("C diff|C. diff|C.diff|CDI", "Clostridioides difficile infection"),
        ("HSV", "herpes simplex virus"), ("CMV", "cytomegalovirus"), ("EBV", "Epstein-Barr virus"), ("SSI", "surgical site infection"), ("abx", "antibiotics"),
        // Medicines and drug classes
        ("ACEi|ACE-I|ACE inhibitor", "ACE inhibitor"), ("ARB", "angiotensin receptor blocker"), ("ARNI", "angiotensin receptor-neprilysin inhibitor"),
        ("CCB", "calcium channel blocker"), ("DOAC", "direct oral anticoagulant"), ("NOAC", "novel oral anticoagulant"), ("VKA", "vitamin K antagonist"),
        ("OAC", "oral anticoagulant"), ("LMWH", "low-molecular-weight heparin"), ("UFH", "unfractionated heparin"), ("SQH|SQ heparin|SC heparin", "subcutaneous heparin"),
        ("SGLT2i|SGLT-2i|SGLT2-i|SGLT2", "SGLT2 inhibitor"), ("GLP-1 RA|GLP1 RA|GLP-1RA|GLP1RA|GLP-1|GLP1", "GLP-1 receptor agonist"),
        ("DPP-4i|DPP4i|DPP-4", "DPP-4 inhibitor"), ("MAOI", "MAO inhibitor"), ("SSRI", "selective serotonin reuptake inhibitor"),
        ("SNRI", "serotonin-norepinephrine reuptake inhibitor"), ("TCA", "tricyclic antidepressant"), ("PPI", "proton pump inhibitor"), ("H2RA|H2 blocker", "H2 blocker"),
        ("NSAID", "nonsteroidal anti-inflammatory drug"), ("DAPT", "dual antiplatelet therapy"), ("OCP", "oral contraceptive pill"), ("HRT", "hormone replacement therapy"),
        ("ICS", "inhaled corticosteroid"), ("LABA", "long-acting beta agonist"), ("SABA", "short-acting beta agonist"), ("LAMA", "long-acting muscarinic antagonist"),
        ("MDI", "metered-dose inhaler"), ("PCN", "penicillin"), ("TMP-SMX|TMP/SMX", "trimethoprim-sulfamethoxazole"), ("MTX", "methotrexate"),
        ("HCQ", "hydroxychloroquine"), ("IVIG", "intravenous immunoglobulin"), ("EPO", "erythropoietin"), ("NTG|nitro", "nitroglycerin"), ("norepi", "norepinephrine"),
        ("vaso", "vasopressin"), ("dobut|dobuta", "dobutamine"), ("milri", "milrinone"), ("nicard", "nicardipine"), ("clevi", "clevidipine"), ("amio", "amiodarone"),
        ("dilt", "diltiazem"), ("bicarb", "sodium bicarbonate"), ("mag", "magnesium"), ("KCl", "potassium chloride"), ("NaCl", "sodium chloride"),
        ("D5W", "5% dextrose in water"), ("D50", "50% dextrose"), ("lido", "lidocaine"), ("bupi|bupiv", "bupivacaine"), ("ropi", "ropivacaine"),
        ("sux|succ", "succinylcholine"), ("roc", "rocuronium"), ("vec", "vecuronium"), ("dexmed", "dexmedetomidine"), ("fent", "fentanyl"),
        ("MSO4", "morphine sulfate"), ("MS Contin", "morphine sulfate extended-release"), ("glyco", "glycopyrrolate"), ("neostig", "neostigmine"),
        ("Precedex", "dexmedetomidine"), ("Levophed", "norepinephrine"), ("Versed", "midazolam"), ("Ancef", "cefazolin"), ("Zofran", "ondansetron"),
        ("Decadron", "dexamethasone"), ("Toradol", "ketorolac"), ("Protonix", "pantoprazole"), ("Prilosec", "omeprazole"), ("Nexium", "esomeprazole"),
        ("Pepcid", "famotidine"), ("Zoloft", "sertraline"), ("Lexapro", "escitalopram"), ("Celexa", "citalopram"), ("Prozac", "fluoxetine"), ("Paxil", "paroxetine"),
        ("Wellbutrin", "bupropion"), ("Effexor", "venlafaxine"), ("Cymbalta", "duloxetine"), ("Neurontin", "gabapentin"), ("Lyrica", "pregabalin"),
        ("Flomax", "tamsulosin"), ("Proscar", "finasteride"), ("Glucophage", "metformin"), ("Imdur", "isosorbide mononitrate"), ("Aldactone", "spironolactone"),
        ("Cardizem", "diltiazem"), ("Cordarone|Pacerone", "amiodarone"), ("Lanoxin", "digoxin"), ("Tenormin", "atenolol"), ("Zestril|Prinivil", "lisinopril"),
        ("Vasotec", "enalapril"), ("Altace", "ramipril"), ("Lotensin", "benazepril"), ("Benicar", "olmesartan"), ("Avapro", "irbesartan"), ("Micardis", "telmisartan"),
        ("Atacand", "candesartan"), ("Fragmin", "dalteparin"), ("Xanax", "alprazolam"), ("Ativan", "lorazepam"), ("Klonopin", "clonazepam"), ("Valium", "diazepam"),
        ("Ambien", "zolpidem"), ("Seroquel", "quetiapine"), ("Zyprexa", "olanzapine"), ("Risperdal", "risperidone"), ("Lamictal", "lamotrigine"),
        ("Depakote", "valproate"), ("Tegretol", "carbamazepine"), ("Dilantin", "phenytoin"), ("Sinemet", "carbidopa-levodopa"), ("Aricept", "donepezil"),
        ("Plaquenil", "hydroxychloroquine"), ("Humira", "adalimumab"), ("Enbrel", "etanercept"), ("Remicade", "infliximab"), ("Ultram", "tramadol"),
        ("Nucynta", "tapentadol"), ("Sublocade", "buprenorphine"), ("Vivitrol", "naltrexone"), ("Adderall", "amphetamine"), ("Deltasone", "prednisone"),
        ("Motrin|Advil", "ibuprofen"), ("Aleve", "naproxen"), ("Celebrex", "celecoxib"), ("Bumex", "bumetanide"), ("Demadex", "torsemide"),
        ("Procardia", "nifedipine"), ("Catapres", "clonidine"), ("Ranexa", "ranolazine"), ("Multaq", "dronedarone"), ("Tikosyn", "dofetilide"),
        ("Rythmol", "propafenone"), ("Betapace", "sotalol"), ("Zetia", "ezetimibe"), ("Repatha", "evolocumab"), ("Glucotrol", "glipizide"), ("Amaryl", "glimepiride"),
        ("Actos", "pioglitazone"),
        // Airway, ventilation, lines and mechanical support
        ("HFNC", "high-flow nasal cannula"), ("NRB", "non-rebreather mask"), ("BiPAP", "bilevel positive airway pressure"),
        ("CPAP", "continuous positive airway pressure"), ("NIPPV", "noninvasive positive pressure ventilation"), ("FiO2", "fraction of inspired oxygen"),
        ("PEEP", "positive end-expiratory pressure"), ("ABG", "arterial blood gas"), ("VBG", "venous blood gas"), ("EtCO2", "end-tidal carbon dioxide"),
        ("PaO2", "arterial oxygen tension"), ("PaCO2", "arterial carbon dioxide tension"), ("LMA", "laryngeal mask airway"), ("NETT", "nasal endotracheal tube"),
        ("trach", "tracheostomy"), ("RSI", "rapid sequence induction"), ("MILS", "manual in-line stabilization"), ("FOI", "fiberoptic intubation"),
        ("AFOI", "awake fiberoptic intubation"), ("BVM", "bag-valve-mask"), ("OPA", "oropharyngeal airway"),
        ("NPA", "nasopharyngeal airway"), ("TIVA", "total intravenous anesthesia"), ("PNB", "peripheral nerve block"), ("ISB", "interscalene block"),
        ("PCA", "patient-controlled analgesia"), ("PCEA", "patient-controlled epidural analgesia"), ("PIV", "peripheral IV"),
        ("A-line|aline|art line", "arterial line"), ("CVC", "central venous catheter"), ("CVL", "central venous line"),         ("PICC", "peripherally inserted central catheter"), ("RIJ", "right internal jugular"), ("LIJ", "left internal jugular"),
        ("Swan|Swan-Ganz|SGC", "pulmonary artery catheter"), ("CVP", "central venous pressure"), ("PCWP", "pulmonary capillary wedge pressure"),
        ("SVR", "systemic vascular resistance"), ("SvO2", "mixed venous oxygen saturation"), ("ScvO2", "central venous oxygen saturation"),
        ("IABP", "intra-aortic balloon pump"), ("Impella", "Impella percutaneous ventricular assist device"), ("ProtekDuo", "ProtekDuo right atrium to pulmonary artery RVAD cannula"), ("LVAD", "left ventricular assist device"),
        ("RVAD", "right ventricular assist device"), ("BiVAD", "biventricular assist device"), ("VAD", "ventricular assist device"), ("HM3|HMIII", "HeartMate 3 LVAD"),
        ("HVAD", "HeartWare ventricular assist device"), ("ECMO", "extracorporeal membrane oxygenation"), ("VV ECMO|VV-ECMO|V-V ECMO", "venovenous ECMO"),
        ("VA ECMO|VA-ECMO|V-A ECMO", "venoarterial ECMO"), ("ECLS", "extracorporeal life support"), ("MCS", "mechanical circulatory support"),
        ("CPB", "cardiopulmonary bypass"), ("DHCA", "deep hypothermic circulatory arrest"),
        // Echo, tests and labs
        ("TTE", "transthoracic echocardiography"), ("RVSP", "right ventricular systolic pressure"), ("PASP", "pulmonary artery systolic pressure"),
        ("TAPSE", "tricuspid annular plane systolic excursion"), ("LAA", "left atrial appendage"), ("RWMA", "regional wall motion abnormality"),
        ("GLS", "global longitudinal strain"), ("IVC", "inferior vena cava"), ("SVC", "superior vena cava"), ("CBC", "complete blood count"),
        ("BMP", "basic metabolic panel"), ("CMP", "comprehensive metabolic panel"), ("lytes", "electrolytes"), ("trop", "troponin"),
        ("hsTnT|hs-TnT|hsTnI|hs-TnI|hs-cTnT|hs-cTnI", "high-sensitivity troponin"), ("Tbili|T bili|bili", "bilirubin"), ("BCx", "blood cultures"),
        ("UCx", "urine culture"), ("CXR", "chest x-ray"), ("MRI", "magnetic resonance imaging"), ("ECG|EKG", "electrocardiogram"),
        ("DSE", "dobutamine stress echocardiography"), ("MPI", "myocardial perfusion imaging"), ("LHC", "left heart catheterization"),
        ("RHC", "right heart catheterization"), ("cath", "catheterization"), ("CCTA", "coronary CT angiography"), ("FFR", "fractional flow reserve"),
        ("DASI", "Duke Activity Status Index"), ("RCRI", "Revised Cardiac Risk Index"), ("NYHA", "New York Heart Association"), ("STOP-BANG|STOPBANG", "STOP-BANG score"),
        // Procedures
        ("SAVR", "surgical aortic valve replacement"), ("TAVR|TAVI", "transcatheter aortic valve replacement"), ("TMVR", "transcatheter mitral valve replacement"),
        ("TEER", "transcatheter edge-to-edge repair"), ("OPCAB", "off-pump coronary artery bypass"), ("MIDCAB", "minimally invasive direct coronary artery bypass"),
        ("SVG", "saphenous vein graft"),         ("LCx", "left circumflex artery"), ("RCA", "right coronary artery"), ("LMCA", "left main coronary artery"), ("LAAO", "left atrial appendage occlusion"),
        ("PVI", "pulmonary vein isolation"), ("DCCV", "direct current cardioversion"), ("EVAR", "endovascular aneurysm repair"),
        ("TEVAR", "thoracic endovascular aortic repair"), ("FEVAR", "fenestrated endovascular aneurysm repair"), ("CEA", "carotid endarterectomy"),
        ("fem-pop", "femoral-popliteal bypass"), ("BKA", "below-knee amputation"), ("TMA", "transmetatarsal amputation"),
        ("I&D", "incision and drainage"), ("ORIF", "open reduction and internal fixation"), ("TKA|TKR", "total knee arthroplasty"),
        ("THA|THR", "total hip arthroplasty"), ("TSA", "total shoulder arthroplasty"), ("ACDF", "anterior cervical discectomy and fusion"),
        ("PSF", "posterior spinal fusion"), ("TLIF", "transforaminal lumbar interbody fusion"), ("lami", "laminectomy"), ("lap chole", "laparoscopic cholecystectomy"),
        ("chole", "cholecystectomy"), ("lap appy", "laparoscopic appendectomy"), ("appy", "appendectomy"), ("lap", "laparoscopic"),
        ("ex lap|ex-lap|XLAP", "exploratory laparotomy"), ("LAR", "low anterior resection"),         ("BSO", "bilateral salpingo-oophorectomy"), ("TLH", "total laparoscopic hysterectomy"), ("D&C", "dilation and curettage"), ("C/S", "cesarean section"),
        ("LTCS", "low transverse cesarean section"), ("VBAC", "vaginal birth after cesarean"), ("TOLAC", "trial of labor after cesarean"),
        ("NSVD|SVD", "normal spontaneous vaginal delivery"), ("TURP", "transurethral resection of the prostate"), ("TURBT", "transurethral resection of bladder tumor"),
        ("PCNL", "percutaneous nephrolithotomy"), ("URS", "ureteroscopy"), ("cysto", "cystoscopy"), ("EGD", "esophagogastroduodenoscopy"),
        ("ERCP", "endoscopic retrograde cholangiopancreatography"), ("EUS", "endoscopic ultrasound"),         ("EBUS", "endobronchial ultrasound"), ("FESS", "functional endoscopic sinus surgery"),
        ("T&A", "tonsillectomy and adenoidectomy"), ("NGT|NG tube", "nasogastric tube"), ("OGT", "orogastric tube"), ("G-tube", "gastrostomy tube"),
        ("J-tube", "jejunostomy tube"), ("TPN", "total parenteral nutrition"),
        // Places, orders and status
        ("PACU", "post-anesthesia care unit"), ("ICU", "intensive care unit"), ("CVICU", "cardiovascular intensive care unit"), ("SICU", "surgical intensive care unit"),
        ("MICU", "medical intensive care unit"), ("CCU", "cardiac care unit"), ("NICU", "neonatal intensive care unit"), ("OSH", "outside hospital"),
        ("SNF", "skilled nursing facility"), ("LTACH", "long-term acute care hospital"), ("DNR", "do not resuscitate"), ("DNI", "do not intubate"),
        ("POLST", "physician orders for life-sustaining treatment"), ("ADL|ADLs", "activities of daily living"),
        ("WNL", "within normal limits"), ("NAD", "no acute distress"), ("RRR", "regular rate and rhythm"), ("A&O|AOx3|A&Ox3", "alert and oriented"),
        ("BLE", "bilateral lower extremities"), ("RLE", "right lower extremity"), ("LLE", "left lower extremity"), ("RUE", "right upper extremity"),
        ("LUE", "left upper extremity"), ("JVD", "jugular venous distension"), ("NKA", "no known allergies"),
        ("NKDA", "no known drug allergies"), ("NKFA", "no known food allergies"), ("NKMA", "no known drug allergies"), ("DOB", "date of birth"),
        ("MRN", "medical record number"), ("PCP", "primary care physician"), ("SBP", "systolic blood pressure"), ("DBP", "diastolic blood pressure"),
        // Obstetric
        ("HELLP", "HELLP syndrome"), ("gHTN", "gestational hypertension"), ("PIH", "pregnancy-induced hypertension"), ("PPCM", "peripartum cardiomyopathy"),
        ("IUGR", "intrauterine growth restriction"), ("PROM", "premature rupture of membranes"), ("PPROM", "preterm premature rupture of membranes"),
        ("PTL", "preterm labor"), ("PPH", "postpartum hemorrhage"),
    ]

    /// Read only in this case: "AVR" is a replacement and "AVr" a repair; "MG" is myasthenia gravis and "mg" a milligram.
    private static let exactCaseRows: [(String, String)] = [
        ("AF", "atrial fibrillation"), ("VT", "ventricular tachycardia"), ("VF", "ventricular fibrillation"), ("HF", "heart failure"),
        ("MI", "myocardial infarction"), ("DES", "drug-eluting stent"), ("BMS", "bare-metal stent"), ("AR", "aortic regurgitation"),
        ("AI", "aortic insufficiency"), ("MR", "mitral regurgitation"), ("TR", "tricuspid regurgitation"), ("TS", "tricuspid stenosis"),
        ("PH", "pulmonary hypertension"), ("PAD", "peripheral arterial disease"), ("MG", "myasthenia gravis"), ("OA", "osteoarthritis"),
        ("UC", "ulcerative colitis"), ("CF", "cystic fibrosis"), ("TB", "tuberculosis"), ("CSA", "central sleep apnea"), ("CAP", "community-acquired pneumonia"),
        ("IE", "infective endocarditis"), ("CoA", "coarctation of the aorta"), ("SAM", "systolic anterior motion"), ("HIT", "heparin-induced thrombocytopenia"),
        ("DI", "diabetes insipidus"), ("HA", "headache"), ("HRS", "hepatorenal syndrome"), ("BB", "beta-blocker"),
        ("AVR", "aortic valve replacement"), ("AVr", "aortic valve repair"), ("MVR", "mitral valve replacement"), ("MVr", "mitral valve repair"),
        ("TVR", "tricuspid valve replacement"), ("TVr", "tricuspid valve repair"), ("OM", "obtuse marginal artery"), ("LM", "left main coronary artery"),
        ("SB", "sinus bradycardia"), ("SR", "sinus rhythm"), ("NC", "nasal cannula"), ("TEE", "transesophageal echocardiography"),
        ("DL", "direct laryngoscopy"), ("VL", "video laryngoscopy"), ("SGA", "supraglottic airway"), ("IJ", "internal jugular"), ("IO", "intraosseous"),
        ("CO", "cardiac output"), ("CI", "cardiac index"), ("MAP", "mean arterial pressure"), ("LV", "left ventricle"), ("RV", "right ventricle"),
        ("PA", "pulmonary artery"), ("TV", "tidal volume"), ("Na", "sodium"), ("Mg", "magnesium"), ("AST", "aspartate aminotransferase"),
        ("ALT", "alanine aminotransferase"), ("CK", "creatine kinase"), ("CT", "computed tomography"), ("MELD", "Model for End-Stage Liver Disease score"),
        ("IR", "interventional radiology"), ("OR", "operating room"), ("ED", "emergency department"), ("ER", "emergency room"), ("LE", "lower extremity"),
        ("UE", "upper extremity"), ("LR", "lactated Ringer's"), ("NS", "normal saline"), ("NE", "norepinephrine"), ("GTT", "glucose tolerance test"),
        ("gtt|gtts|Gtt", "infusion"), ("Fx", "fracture"),
        // Also English words in lower case ("aids", "tips", "lad", "bun").
        ("AIDS", "acquired immunodeficiency syndrome"), ("TIPS", "transjugular intrahepatic portosystemic shunt"),
        ("PEG", "percutaneous endoscopic gastrostomy"), ("DOE", "dyspnea on exertion"), ("RAD", "reactive airway disease"),
        ("APR", "abdominoperineal resection"), ("AKA", "above-knee amputation"), ("TLC", "triple-lumen catheter"),
        ("FOB", "fiberoptic bronchoscope"), ("SEM", "systolic ejection murmur"), ("POD", "postoperative day"),
        ("VATS", "video-assisted thoracoscopic surgery"), ("LAD", "left anterior descending artery"), ("LIMA", "left internal mammary artery"),
        ("RIMA", "right internal mammary artery"), ("AVA", "aortic valve area"), ("MASH", "metabolic dysfunction-associated steatohepatitis"),
        ("AVG", "arteriovenous graft"), ("BUN", "blood urea nitrogen"), ("SOB", "shortness of breath"),
    ]

    /// Connecting shorthand the note reader understands as written: recognized (so never asked about), not replaced.
    private static let connectorRows: [(String, String)] = [
        ("s/p", "status post"), ("h/o", "history of"), ("hx", "history"), ("c/o", "complains of"), ("w/", "with"), ("w/o", "without"),
        ("b/l|bilat", "bilateral"), ("pt|pts", "patient"), ("y/o|yo|y.o.", "years old"), ("Dx", "diagnosis"), ("Tx", "treatment"), ("Rx", "prescription"),
        ("Sx", "symptoms"), ("PMH|PMHx", "past medical history"), ("PSH|PSHx", "past surgical history"), ("FHx", "family history"), ("SHx", "social history"),
        ("HPI", "history of present illness"), ("ROS", "review of systems"), ("A/P", "assessment and plan"), ("Ht", "height"), ("Wt", "weight"),
        ("BP", "blood pressure"), ("SpO2|SaO2", "oxygen saturation"), ("O2", "oxygen"), ("EF", "ejection fraction"), ("LVEF", "left ventricular ejection fraction"),
        ("BNP", "B-type natriuretic peptide"), ("NT-proBNP|NTproBNP", "N-terminal pro-B-type natriuretic peptide"), ("MET|METs", "metabolic equivalents"),
        ("NPO", "nothing by mouth"), ("PONV", "postoperative nausea and vomiting"), ("GETA", "general endotracheal anesthesia"),
        ("CSE", "combined spinal-epidural"), ("SQ|subq|subcut|sub-q", "subcutaneous"), ("po", "by mouth"), ("prn", "as needed"), ("qd", "once daily"),
        ("qam", "every morning"), ("qpm", "every evening"), ("qhs", "at bedtime"), ("bid", "twice daily"), ("tid", "three times daily"),
        ("qid", "four times daily"), ("qod", "every other day"), ("qwk|qweek", "weekly"), ("MWF|M/W/F", "Monday, Wednesday and Friday"),
        ("TTS|TThS|T/Th/S", "Tuesday, Thursday and Saturday"), ("AC/VC", "assist-control volume control"), ("AC/PC", "assist-control pressure control"),
        ("PRVC", "pressure-regulated volume control"), ("SIMV", "synchronized intermittent mandatory ventilation"), ("PSV", "pressure support ventilation"),
        ("APRV", "airway pressure release ventilation"), ("DLT", "double-lumen tube"), ("NT/ND", "nontender, nondistended"), ("VSS", "vital signs stable"),
        ("HEENT", "head, eyes, ears, nose and throat"), ("EOMI", "extraocular movements intact"), ("PERRL|PERRLA", "pupils equal and reactive"),
        ("NCAT", "normocephalic, atraumatic"), ("MAE", "moves all extremities"), ("AAOx3|AOx4", "alert and oriented"), ("WWP", "warm and well perfused"),
        ("RUQ", "right upper quadrant"), ("LUQ", "left upper quadrant"), ("RLQ", "right lower quadrant"), ("LLQ", "left lower quadrant"),
        ("d/c", "discontinue"), ("r/o", "rule out"), ("f/u", "follow-up"), ("I/O", "intake and output"), ("OOB", "out of bed"),
        ("WBAT", "weight bearing as tolerated"), ("NWB", "non-weight-bearing"), ("GCS", "Glasgow Coma Scale"), ("NIHSS", "NIH Stroke Scale"),
        ("RASS", "Richmond Agitation-Sedation Scale"), ("SBT", "spontaneous breathing trial"), ("CAM-ICU", "Confusion Assessment Method for the ICU"),
        ("LMP", "last menstrual period"), ("EDD|EDC", "estimated due date"), ("IUP", "intrauterine pregnancy"), ("SROM", "spontaneous rupture of membranes"),
        ("AROM", "artificial rupture of membranes"), ("FHR", "fetal heart rate"), ("EFW", "estimated fetal weight"), ("IOL", "induction of labor"),
    ]

    private static let exactConnectorRows: [(String, String)] = [
        ("HR", "heart rate"), ("RR", "respiratory rate"), ("VS", "vital signs"), ("FH", "family history"), ("MP", "Mallampati"),
        ("TMD", "thyromental distance"), ("MO", "mouth opening"), ("GA", "general anesthesia"), ("SAB", "subarachnoid block"),
        ("TAP", "transversus abdominis plane"), ("ESP", "erector spinae plane"), ("PENG", "pericapsular nerve group"), ("QL", "quadratus lumborum"),
        ("MH", "malignant hyperthermia"), ("SL", "sublingual"), ("IM", "intramuscular"), ("SC", "subcutaneous"), ("Mac", "Macintosh blade"),
        ("NT", "nontender"), ("ND", "nondistended"), ("MN", "midnight"), ("BM", "bowel movement"), ("OT", "occupational therapy"),
        ("SLP", "speech-language pathology"), ("CN", "cranial nerves"),
        // Line sites and device settings, read by the device parser as written.
        ("AC", "antecubital fossa or assist-control"), ("FA", "forearm or femoral artery"), ("EJ", "external jugular"), ("FV", "femoral vein"),
        ("DP", "dorsalis pedis"), ("RFV", "right femoral vein"), ("LFV", "left femoral vein"), ("RFA", "right femoral artery or forearm"),
        ("LFA", "left femoral artery or forearm"), ("RSC", "right subclavian"), ("LSC", "left subclavian"), ("RAC", "right antecubital fossa"),
        ("LAC", "left antecubital fossa"), ("REJ", "right external jugular"), ("LEJ", "left external jugular"), ("HM", "HeartMate"),
        ("PI", "pulsatility index"), ("RP", "right-sided (Impella RP)"), ("VV", "venovenous"), ("VA", "venoarterial"), ("VAV", "veno-arteriovenous"),
        ("VC", "volume control"), ("PC", "pressure control"), ("TC", "trach collar"),
    ]

    /// CKD with its stage ("CKD 3b", "CKD stage IV"), "x3" (three times) and "q6h" (every 6 hours).
    private static let generatedRows: [MedAbbreviation] = {
        var out: [MedAbbreviation] = []
        func add(_ key: String, _ text: String, reads: Bool = true) {
            out.append(MedAbbreviation(key, caseSensitive: false, meanings: [AbbreviationMeaning(text)], reads: reads))
        }
        let stages: [(String, [String])] = [("1", ["1", "I"]), ("2", ["2", "II"]), ("3", ["3", "III"]), ("3a", ["3a", "IIIa"]), ("3b", ["3b", "IIIb"]),
                                            ("4", ["4", "IV"]), ("5", ["5", "V"])]
        for (stage, spellings) in stages {
            let text = "chronic kidney disease stage " + stage
            for s in spellings {
                add("CKD " + s, text)
                add("CKD-" + s, text)
                add("CKD stage " + s, text)
                if s.first?.isNumber == true { add("CKD" + s, text) }
            }
        }
        for n in 1...6 { add("x\(n)", "times \(n)", reads: false) }
        for h in [1, 2, 3, 4, 6, 8, 12, 24] { add("q\(h)h", "every \(h) hours", reads: false) }
        return out
    }()
}

// MARK: - Common English words

extension MedAbbreviations {
    /// Common English words of 2 to 6 letters (by frequency, with some clinical vocabulary), so that a word written in
    /// capitals ("DENIES", "PLAN") is not taken for an unknown abbreviation.
    static let englishWords: Set<String> = Set(words.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))

    private static let words = """
        able about above abroad abuse accept access acid across act acted acting action active actor actors acts actual acute
        adam adams add added adding adds admit ads adult adults advice affair affect afford afraid africa after again age
        aged agency agenda agent agents ages ago agree agreed ahead aid aids aim aimed air airway alan alarm album alert alex
        alice alien alive all allen allies allow allows almost alone along alpha also always am amazon among amount an and
        andrew andy angel angels anger angio angle angry animal anime ankle anna anne annual answer anti any anyone anyway
        aortic apart apnea app appeal appear apple apply approx apps april arab are area areas arena argue argued arm armed
        arms army around arrest arrive art arthur artist arts as asia asian aside ask asked asking asks asleep aspect ass
        assets assist assume at ate attack attend audio august austin author auto autumn avenue avoid awake award awards
        aware away awful babies baby back backed bad badly bag bags ball balls ban band bands bang bank banks banned bar
        barely barry bars base based basic basis bass bat bath battle bay be beach bear bears beast beat beauty became become
        bed beef been beer beers before began begin begins begun behalf behind being belief bell belong below belt bench
        benign berlin best bet better beyond bible bid big bigger bike bill bills billy bird birds birth bishop bit bitch
        bite black blame blast blind block blocks blog blood bloody blow blue blues bmi board boards boat boats bodies body
        bold bomb bond bonds bone bones bonus book books boom boost boots border boring born boss boston both bother bottle
        bottom bought bound bow bowl box boxes boy boys brace brain branch brand brands brave brazil bread break breaks
        breast breath brian brick bridge brief bright bring brings broad broke broken brown bruce buddy budget build built
        bull bunch bureau buried burn burned burns bus bush busy but butt butter button buy buying by bye cable cake call
        called calls calm came camera camp campus can canada cancer candy cane cannot cant cap cape car carbon card cards
        care career cares carry cars carter case cases cash cast castle cat catch cath cats caught cause caused causes cell
        cells cent center centre cents cervix chain chair chance change chaos charge chart chase chat cheap check checks
        cheese chest chief child chills china chip choice choose chose chosen chris christ church circle cited cities city
        civil claim claims clark class clay clean clear click client climb climbs clinic clip clock close closed closer cloud
        club clubs coach coal coast coat code coffee coins cold colon color colors colour column combat come comedy comes
        comic coming commit common con cook cool cooper cop copies copper cops copy core corner corp corps cost costs cotton
        cough could count counts county couple course court courts cousin cover covers crack craft crap crash crazy cream
        create credit creek crew crime crimes crisis cross crowd crown crutch cry crying cup cure custom cut cute cuts cycle
        dad daddy daily dallas damage damn dance danger daniel danny dare dark data date dated dates dating dave david davis
        dawn day days dead deal deals dean dear death deaths debate debt debut decade decent decide deck deep deeper deeply
        defeat defend define degree delay delhi demand denied denies deny depth deputy desert design desire desk detail
        device devil dick did die died diego dies diet dinner direct dirty disney do doc doctor does dog dogs doing dollar
        domain don donald done dont door doors dose doses double doubt down dozen dr draft drag dragon drain drains drama
        draw drawn dream dreams dress drew drink drinks drive driven driver drives drop drops drove drug drugs drunk dry dual
        dude due duke dumb during dust dutch duties duty dying each ear early earn earned ears earth ease easier easily east
        easy eat eating echo ecmo edema edge edit edited editor edward effect effort egg eggs egypt eight either elbow elite
        else email empire empty en enable end ended ending ends enemy energy engage engine enjoy enough ensure enter entire
        entry epic equal equity era eric error errors escape estate etc ethnic europe even event events ever every evil exact
        exam except excuse exist exists exit expand expect expert extend extent extra extub eye eyes face faced faces facing
        fact factor facts fail failed fails fair fairly faith fake fall fallen falls false fame family famous fan fancy fans
        far farm fast faster fat fate father fault favor favour fear fed fee feed feel feels fees feet fell fellow felt
        female femur fever few fewer fi field fields fifth fifty fight figure file filed files fill filled film films filter
        final finals find finds fine finger finish fire fired firing firm firms first fiscal fish fit fits five fix fixed
        flag flash flat fleet flight flood floor flow flower fly flying focus folate foley folks follow food foods fool foot
        for force forced forces ford forest forget forgot form formal format formed former forms fort forth forum foster
        fought found four fourth fox frail frame france frank fraud free french fresh friday friend from front frozen fruit
        fuck fucked fuckin fuel full fully fun fund funded funds funny future gain gained gains galaxy gallop game games
        gaming gang gap garage garden gary gas gate gates gave gay gear gen gender gene genius george german get gets ghost
        giant giants gift gifts girl girls give given gives giving glad glass global globe glory go goal goals god gods goes
        going gold golden golf gone gonna good goods google gordon got gotta gotten grab grace grade grades graft grafts
        graham grand grant grass grave gray great greece greek green grew grey gross ground group groups grow grown growth
        guard guards guess guest guests guide guilty guitar gulf gun guns guy guys gym had haha hair half hall hand handed
        handle hands hang happen happy hard harder hardly harm harris harry has hat hate have having he head headed heads
        health hear heard heart hearts heat heaven heavy height held hell hello help helped helps hence henry her here hero
        heroes hidden hide hiding high higher highly hill hills him hip hire hired his hit hits hives hockey hold holds hole
        holes holy home homes honest honey hong honor honour hook hop hope hoped hopes hoping horror horse horses host hosted
        hot hotel hour hours house houses how howard huge human humans hungry hunt hunter hurt hurts ice id idea ideal ideas
        idiot if ignore ill image images impact in inch inches income indeed index india indian info injury inner input
        insane inside intact intent into intub invest invite iowa iran iraq irish iron irreg is isis islam island israel
        issue issued issues it italy itch item items its itself jack jacket jail james jane japan jason jaw jazz jean jeff
        jerry jersey jesus jet jewish jews jimmy job jobs john johnny join joined joint joke jokes jones jordan joseph josh
        joy judge judges juice july jump jumped june junior jury just justin kansas kate keep keeps kelly kept kevin key keys
        kg khan kick kicked kid kidney kids kill killed killer kills kind kinda kinds king kings kiss kit knee knew knife
        knight knock know known knows kong korea korean lab label labor labour labs lack ladies lady laid lake land lands
        lane large larger larry las last late lately later latest latin latter laugh launch law laws lawyer lay layer le lead
        leader leads league learn least leave leaves led left leg legacy legal legend legs length less lesson let lets letter
        level levels lewis lie lies life lift light lights like liked likely likes limit limits line lines link linked links
        lion lips liquid lisa list listed listen lists little live lived liver lives living lmao load loaded loan loans local
        lock locked log logic logo london lonely long longer look looked looks loop loose lord lose losing loss losses lost
        lot lots loud louis love loved lovely lover loves loving low lower lowest luck lucky luke lumbar lunch lung lungs
        luxury lying lyrics mad made madrid magic mail main mainly major make makes makeup making male mall man manage manner
        manual many map maps march margin maria marine mark marked market marks marry mars martin mary mask mass master match
        mate math matt matter mature max may maybe mayor me meal mean means meant meat med medal media medium meds meet meets
        member memory men mental menu mercy merely mess met metal method mexico mg miami mid middle might mike mild mile
        miles milk mill miller min mind minds mine mini mining minor minute mirror miss missed mitral mix mixed mobile mode
        model models modern moist mom moment monday money month months mood moon moore moral more morgan moscow most mostly
        mother motion motor mount mouse mouth move moved moves movie movies moving mr mrs ms much multi mum murder murmur
        murray muscle museum music muslim must mutual my myself naked name named names narrow nasal nation native nature
        nausea navy nazi near nearby nearly neck need needed needs nerve net never new newly news next nice nick night nights
        nil nine no nobody noise non none nope nor normal north nose not note noted notes notice novel now number nurse nuts
        obama obese object obtain occur occurs ocean odd odds of off offer offers office often ohio oil ok okay old older on
        once one ones online only onto open opened opens opera opioid option or oral orange order orders oregon origin oscar
        other others ought our out outer output ovary over own owned owner owners oxford oxygen pace pacer pack packed page
        pages paid pain paint pair palace palate pale pan panel panic pants paper papers parent paris park parks part partly
        parts party pass passed passes past path paul pay paying pays peace peak pen people per period person pet peter phase
        phil philip phone phones photo photos phrase piano picc pick picked piece pieces pilot pin pink pipe pissed pit pitch
        pizza place placed places plain plan plane planet plans plant plants plate play played player plays please plenty
        plot plus pocket poem poetry point points police policy polish poll pool poor pop pope porn port post posted posts
        pot pound pounds powder power powers praise pray prayer pre prefer press pretty price prices pride priest prime
        prince print prior prison prize pro profit proof proper proud prove proved proven public pull pulled pump punch pure
        purple pursue push pushed put puts queen quest quick quiet quit quite quote quotes race races racial racing racism
        racist radio rail rain raise raised rally ran random range rank ranked rape rapid rare rarely rash rate rated rates
        rather rating ratio raw re reach read reader reads ready real really rear reason recall recent record rectal red
        reduce refer refers reform refuse regard regime region regret relax relief rely remain remind remote remove renal
        rent rep repair repeat reply report rescue resort rest result resume retail return reveal review reward rhythm rice
        rich rick rid ride riding right rights ring rings rip rise rising risk risks river rivers road roads robert robin
        rock rocket rocks roger role roles roll roman rome roof room rooms root roots rose ross rough round rounds route row
        royal rub rude rugby ruin ruined rule ruled rules ruling run runs rural rush russia ryan sacral sad safe safety said
        saint sake salary sale sales salt same sample sand santa sarah sat sats sauce saudi save saved saving saw say saying
        says scale scan scared scary scene scenes scheme school scope score scored scores scott screen screw script sea seal
        sean search season seat seats sec second secret sector secure sedate see seed seeds seeing seek seem seemed seems
        seen sees select self sell semi senate send senior sense sent sept series serve served server serves set sets settle
        seven severe sex sexual sexy shadow shake shall shame shape shaped share shared shares sharp she sheet shell shield
        shift ship ships shirt shit shock shoes shoot shop shops shore short shot shots should show showed shower shown shows
        shunt shut sick side sides sight sign signal signed signs silent silly silver simon simple simply sin since sing
        singer single sinus sir sister sit site sites six sixth size sized skill skills skin sky slave sleep slide slip slow
        slowly small smart smell smile smith smoke smoker smokes smooth snore snores snow so soccer social sodium soft soil
        solar sold sole solid solo solve some son song songs sons soon sooner sorry sort sought soul sound sounds source
        south soviet space spaces spain spare speak speaks speech speed spell spend spent spider spin spinal spine spirit
        splint split spoke spoken sport sports spot spots sprain spread spring sputum squad square stable staff stage stages
        stairs stand stands star stars start starts state stated states statin stats status stay stayed stays steady steal
        steam steel stem stent stents step steps steve stick still stock stocks stolen stone stones stood stool stop stops
        store stores storm story stream street stress strike string strip stroke strong struck stuck studio study stuff
        stupid style styles sub submit such suck sucks sudden suffer sugar suit suits sum summer summit sun sunday super
        supply sure surely survey swab swear sweden sweet swing switch sword sydney symbol syria system table tables tablet
        tabs tag tail take taken takes taking tale talent talk talked talks tall tank tanks tap tape taper target task taste
        taught tax taxes taylor tea teach team teams tear tears tech teen teeth tell tells temple ten tend tender tennis term
        terms terror test tested tests texas text texts than thank thanks that thats the their them theme then theory there
        these they thick thin thing things think thinks third thirty this tho thomas those though thread threat three threw
        throat throw thrown thus tibia ticket tie tied ties tiger tight till time times timing tiny tip tips tired tissue
        title titles to today toilet tokyo told ton tone tongue tons tony too took tool tools tooth top topic topics total
        touch tough tour toward tower town towns toy toys trace track tracks trade trail train trains trans trap trash trauma
        travel treat treaty tree trees trend trends trial trials trick tried tries trip triple troops truck true truly trump
        trust truth try trying tube tubes tune turkey turn turned turns twelve twenty twice twin two type types ugly ulcer un
        unable uncle under union unique unit united units unless unlike until up update upon upper upset urban urine us use
        used useful user users uses using usual uterus uvula valid valley value values valve valves van vary vast vegas vent
        versus very vessel via vice victim video videos view viewed views virgin virus vision visit visits visual vital
        vitals voice voices volume vomit vote voted voters votes voting vs wage wait waited wake wales walk walked walker
        walks wall walls walter wanna want wanted wants war ward warm warren wars was wash waste watch water waters wave
        waves way wayne ways we weak wealth wean weaned weapon wear web weed week weekly weeks weight weird well went were
        west wet what wheel when where which while whilst white who whole whom whose why wide widely wife wild will wilson
        win wind window wine wing wings winner wins winter wire wires wisdom wise wish wishes with within wolf woman women
        won wonder wood wooden woods word words wore work worked worker works world worn worry worse worst worth worthy would
        wound wrist write writer writes wrong wrote xray yard yards yeah year years yellow yes yet york you young your yours
        youth zero zone
        """
}
