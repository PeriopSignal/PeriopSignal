import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Answers a question the references and the feed could not: on the phone with Apple's model when
/// the device has it, otherwise through the Periop Signal proxy (worker/), which asks Claude. Both
/// are handed the best-matching posts and quick references so the answer is grounded and cited.
///
/// Ben, Nov 20 (after an outside review): an answer must not look better supported by the library than it is. So the
/// matching is strict (whole words for short words and abbreviations, a higher bar to be listed), the list on screen is
/// exactly what the model was given, a quick reference is clipped to the passage that holds the question's words, and a
/// question nothing matched says so above the answer.
enum AskEngine {
    enum Backend: String { case onDevice, cloud }

    struct Source: Identifiable, Hashable {
        enum Kind: Hashable { case post(String), quickref(String) }
        let id: Int
        let title: String
        let subtitle: String
        let kind: Kind
    }

    /// One word or phrase to look for. `text` is lowercase, except for a case-sensitive abbreviation (LAST, TAP) which is
    /// kept in capitals and only matches capitals, so the ordinary word "last" is not taken for the toxicity syndrome.
    struct Term: Hashable {
        let text: String
        /// Matches only where no letter or digit touches either end ("last" is not in "lasted", "MH" is not in "MHz").
        let wholeWord: Bool
        let caseSensitive: Bool
    }

    struct Grounding {
        var posts: [Post]
        var refs: [QuickRef]
        /// What the question asked for, after the alias table (see `concepts(for:)`). Kept so an excerpt of a quick
        /// reference can pick the passages that hold these words instead of the card's first characters.
        var concepts: [[Term]] = []

        var isEmpty: Bool { posts.isEmpty && refs.isEmpty }

        /// The one numbered list. The model is given exactly these, in this order, and the screen draws exactly these:
        /// posts first, then quick references, numbered from 1 (the numbers the answer cites as [1], [2]).
        var sources: [Source] {
            var out: [Source] = []
            for p in posts { out.append(Source(id: out.count + 1, title: p.headline, subtitle: "\(p.journal) · \(PSDate.display(p.date, long: true))", kind: .post(p.id))) }
            for r in refs { out.append(Source(id: out.count + 1, title: r.title, subtitle: r.societyShort + (r.year.map { " · \($0)" } ?? ""), kind: .quickref(r.id))) }
            return out
        }
    }

    // MARK: Availability

    /// Apple's on-device model is usable (iOS 26, Apple Intelligence on, model downloaded).
    static var onDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static func backend(endpoint: URL?, preferOnDevice: Bool) -> Backend? {
        if preferOnDevice && onDeviceAvailable { return .onDevice }
        if endpoint != nil { return .cloud }
        return onDeviceAvailable ? .onDevice : nil
    }

    // MARK: Grounding: the posts and references that best match the question

    /// How many sources each route can take. The on-device model has a small context, so it takes fewer; the list on
    /// screen is cut to the same number, so it never shows a source the model did not receive.
    static func limits(for backend: Backend?) -> (posts: Int, refs: Int) {
        backend == .onDevice ? (3, 1) : (4, 2)
    }

    /// The posts and quick references that best match the question, already cut to what `backend` can take.
    /// Matching stays lexical and on the phone.
    ///
    /// Which source is listed (Ben, Nov 20): the ranking idea is unchanged, a hit in a source's name counts 3 and a hit
    /// anywhere in it counts 1 for each distinct question word, best first. What changed is the bar: a source is listed
    /// only when (a) a question word is in its name (a post's headline, title or trial name; a quick reference's title
    /// or keywords), or (b) at least three distinct question words (after the stoplist, an alias group counting once)
    /// are in its body. Two stray words in the body list nothing. Words of four letters or fewer and capital
    /// abbreviations match as whole words only.
    static func grounding(for question: String, posts: [Post], refs: [QuickRef], backend: Backend? = nil) -> Grounding {
        let wanted = concepts(for: question)
        guard !wanted.isEmpty else { return Grounding(posts: [], refs: []) }
        let limit = limits(for: backend)

        var scoredPosts: [(index: Int, score: Int)] = []
        for (i, p) in posts.enumerated() {
            let name = Haystack([p.headline, p.title ?? "", p.trialName].joined(separator: " "))
            let body = Haystack(bodyText(of: p))
            let m = match(wanted, name: name, body: body)
            if m.listed { scoredPosts.append((i, m.score)) }
        }
        var scoredRefs: [(index: Int, score: Int)] = []
        for (i, r) in refs.enumerated() {
            let name = Haystack(([r.title] + (r.keywords ?? [])).joined(separator: " "))
            let body = Haystack(bodyText(of: r))
            let m = match(wanted, name: name, body: body)
            if m.listed { scoredRefs.append((i, m.score)) }
        }
        // Best score first; equal scores keep the order they came in.
        func best(_ list: [(index: Int, score: Int)], _ n: Int) -> [Int] {
            list.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }.prefix(n).map { $0.index }
        }
        return Grounding(posts: best(scoredPosts, limit.posts).map { posts[$0] },
                         refs: best(scoredRefs, limit.refs).map { refs[$0] },
                         concepts: wanted)
    }

    /// The score of one source and whether it clears the bar. `body` holds `name`, so a name hit counts in both.
    private static func match(_ concepts: [[Term]], name: Haystack, body: Haystack) -> (score: Int, listed: Bool) {
        var nameHits = 0
        var bodyHits = 0
        for c in concepts {
            let inName = c.contains { matches($0, in: name) }
            if inName { nameHits += 1 }
            if inName || c.contains(where: { matches($0, in: body) }) { bodyHits += 1 }
        }
        return (nameHits * 3 + bodyHits, nameHits >= 1 || bodyHits >= 3)
    }

    /// Everything searchable in a post, as Post.searchText has it but with its capitals kept (a case-sensitive
    /// abbreviation needs them).
    private static func bodyText(of p: Post) -> String {
        [p.headline, p.summary, p.journal, p.kind, p.trialName, p.firstAuthor, p.title ?? "", p.takeHome.joined(separator: " ")].joined(separator: " ")
    }

    /// Everything searchable in a quick reference, as QuickRef.searchText has it but with its capitals kept.
    private static func bodyText(of r: QuickRef) -> String {
        var parts = [r.title, r.society, r.societyShort, r.summary]
        parts += r.keywords ?? []
        for s in r.sections {
            if let h = s.heading { parts.append(h) }
            parts += s.items ?? []
            if let t = s.text { parts.append(t) }
            for row in s.rows ?? [] { parts += row }
        }
        return parts.joined(separator: " ")
    }

    // MARK: The question's words and the alias table

    /// Interchangeable terms, so a question that says TXA finds a post that says tranexamic acid and the other way
    /// round. Synonyms only; there is no clinical content in this table. `abbreviations` match as whole words.
    private struct Alias {
        let abbreviations: [String]
        let terms: [String]
    }

    private static let aliases: [Alias] = [
        Alias(abbreviations: ["TXA"], terms: ["tranexamic acid"]),
        Alias(abbreviations: ["MH"], terms: ["malignant hyperthermia"]),
        Alias(abbreviations: ["LAST"], terms: ["local anesthetic systemic toxicity", "local anesthetic toxicity"]),
        Alias(abbreviations: ["PONV"], terms: ["postoperative nausea and vomiting"]),
        Alias(abbreviations: ["DOAC"], terms: ["direct oral anticoagulant"]),
        Alias(abbreviations: ["LMWH"], terms: ["low molecular weight heparin", "enoxaparin"]),
        Alias(abbreviations: ["UFH"], terms: ["unfractionated heparin"]),
        Alias(abbreviations: ["MTP"], terms: ["massive transfusion"]),
        Alias(abbreviations: ["TEE"], terms: ["transesophageal"]),
        Alias(abbreviations: ["TAVR", "TAVI"], terms: ["transcatheter aortic valve"]),
        Alias(abbreviations: ["CABG"], terms: ["coronary artery bypass"]),
        Alias(abbreviations: ["ECMO"], terms: ["extracorporeal membrane oxygenation"]),
        Alias(abbreviations: ["LVAD"], terms: ["left ventricular assist device"]),
        Alias(abbreviations: ["GLP-1"], terms: ["semaglutide", "tirzepatide"]),
        Alias(abbreviations: ["SGLT2"], terms: ["empagliflozin", "dapagliflozin"]),
        Alias(abbreviations: ["OSA"], terms: ["obstructive sleep apnea"]),
        Alias(abbreviations: ["AF"], terms: ["atrial fibrillation"]),
        Alias(abbreviations: ["PE"], terms: ["pulmonary embolism"]),
        Alias(abbreviations: ["AKI"], terms: ["acute kidney injury"]),
        Alias(abbreviations: ["RSI"], terms: ["rapid sequence"]),
        Alias(abbreviations: ["ESP"], terms: ["erector spinae"]),
        Alias(abbreviations: ["TAP"], terms: ["transversus abdominis plane"]),
    ]

    /// Abbreviations that are also ordinary words: they count only when typed, and found, in capitals.
    private static let capitalsOnly: Set<String> = ["LAST", "TAP", "ESP", "PE", "AF"]

    private static func terms(of alias: Alias) -> [Term] {
        let abbreviations = alias.abbreviations.map { a in
            capitalsOnly.contains(a) ? Term(text: a, wholeWord: true, caseSensitive: true) : Term(text: a.lowercased(), wholeWord: true, caseSensitive: false)
        }
        let full = alias.terms.map { Term(text: $0.lowercased(), wholeWord: false, caseSensitive: false) }
        return abbreviations + full
    }

    private static let stop: Set<String> = ["the", "and", "for", "with", "what", "when", "how", "does", "are", "is", "of", "in", "to", "a", "an", "on", "or", "should", "can", "patient", "patients", "about", "versus", "after", "before", "which", "that", "this", "than", "from", "use", "used"]

    /// An all-capital abbreviation as typed: two to six characters, a letter among them (MH, TXA, GLP1).
    private static func isAbbreviation(_ raw: String) -> Bool {
        raw.count >= 2 && raw.count <= 6 && raw == raw.uppercased() && raw.contains { $0.isLetter }
    }

    /// The question as a list of things to look for. Each entry is one idea with its interchangeable terms: an alias
    /// group (every term in it) or a single word. A word the alias already covers is not counted a second time.
    static func concepts(for question: String) -> [[Term]] {
        let q = Haystack(question)
        let nonWord = CharacterSet.alphanumerics.inverted
        var out: [[Term]] = []
        var covered = Set<String>()
        for alias in aliases {
            let group = terms(of: alias)
            let found = group.filter { matches($0, in: q) }
            guard !found.isEmpty else { continue }
            out.append(group)
            for t in found {
                for w in t.text.lowercased().components(separatedBy: nonWord) where !w.isEmpty { covered.insert(w) }
            }
        }
        var seen = Set<String>()
        for raw in question.components(separatedBy: nonWord) where !raw.isEmpty {
            let w = raw.lowercased()
            let abbreviation = isAbbreviation(raw)
            guard (w.count > 2 || abbreviation), !stop.contains(w), !covered.contains(w), !seen.contains(w) else { continue }
            seen.insert(w)
            out.append([Term(text: w, wholeWord: abbreviation || w.count <= 4, caseSensitive: false)])
        }
        return out
    }

    /// A text with its capitals kept and without them, so each term is compared the way it asks to be.
    struct Haystack {
        let raw: String
        let lower: String
        init(_ s: String) { raw = s; lower = s.lowercased() }
    }

    static func matches(_ term: Term, in hay: Haystack) -> Bool {
        let text = term.caseSensitive ? hay.raw : hay.lower
        guard !term.text.isEmpty else { return false }
        var from = text.startIndex
        while from < text.endIndex, let r = text.range(of: term.text, range: from..<text.endIndex) {
            if !term.wholeWord { return true }
            let startsClean = r.lowerBound == text.startIndex || !isWordCharacter(text[text.index(before: r.lowerBound)])
            let endsClean = r.upperBound == text.endIndex || !isWordCharacter(text[r.upperBound])
            if startsClean && endsClean { return true }
            from = text.index(after: r.lowerBound)
        }
        return false
    }

    private static func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    // MARK: Excerpts of a quick reference

    /// A piece of a quick reference that can be kept or left out: `section` is -1 for the summary.
    private struct Piece {
        var section: Int
        var text: String
    }

    /// A plain-text excerpt of a quick reference for the model (its tables flattened). It always starts with the card's
    /// title. When the card is longer than `limit`, the excerpt keeps the sentences, list items and table rows that hold
    /// the question's words (`concepts`, after aliases), best first, with their section headings, then the summary and
    /// the rest in order while there is room, instead of cutting at the first characters (Ben, Nov 20: the cited card
    /// often did not contain the passage). The result stays within `limit` characters, plus a closing "…" when
    /// something was left out. With no concepts it is the title and the card from the top, as before.
    static func excerpt(of ref: QuickRef, limit: Int = 1400, concepts: [[Term]] = []) -> String {
        var units: [Piece] = [Piece(section: -1, text: ref.summary)]
        var headings: [Int: String] = [:]
        var joiners: [Int: String] = [:]
        for (i, s) in ref.sections.enumerated() {
            if let h = s.heading { headings[i] = h + ":" }
            switch s.kind {
            case .text:
                joiners[i] = " "
                for piece in pieces(of: s.text ?? "") { units.append(Piece(section: i, text: piece)) }
            case .list, .steps:
                joiners[i] = " · "
                for item in s.items ?? [] { units.append(Piece(section: i, text: item)) }
            case .facts:
                joiners[i] = "; "
                for row in s.rows ?? [] { units.append(Piece(section: i, text: row.joined(separator: ": "))) }
            case .table:
                joiners[i] = "\n"
                let cols = s.columns ?? []
                for row in s.rows ?? [] {
                    let cells = row.enumerated().dropFirst().compactMap { idx, c in c.isEmpty ? nil : "\(idx < cols.count ? cols[idx] : "") \(c)" }
                    units.append(Piece(section: i, text: (row.first ?? "") + " — " + cells.joined(separator: "; ")))
                }
            }
        }
        units = units.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }

        func assemble(_ chosen: Set<Int>) -> String {
            var lines = [ref.title]
            if let first = units.firstIndex(where: { $0.section == -1 }), chosen.contains(first) { lines.append(units[first].text) }
            for i in ref.sections.indices {
                let mine = units.indices.filter { units[$0].section == i && chosen.contains($0) }
                guard !mine.isEmpty else { continue }
                if let h = headings[i] { lines.append(h) }
                lines.append(mine.map { units[$0].text }.joined(separator: joiners[i] ?? "\n"))
            }
            return lines.joined(separator: "\n")
        }

        let whole = assemble(Set(units.indices))
        if whole.count <= limit { return whole }

        func score(_ text: String) -> Int {
            let hay = Haystack(text)
            var n = 0
            for concept in concepts where concept.contains(where: { term in matches(term, in: hay) }) { n += 1 }
            return n
        }
        let scores = units.map { score($0.text) }
        let summaryIndex = units.firstIndex { $0.section == -1 }
        var order = units.indices.filter { $0 != summaryIndex && scores[$0] > 0 }
        order.sort { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
        if let s = summaryIndex { order.append(s) }
        let rest = units.indices.filter { !order.contains($0) }
        order += rest

        let budget = limit - 1   // room for the closing "…"
        var chosen = Set<Int>()
        for i in order {
            var trial = chosen
            trial.insert(i)
            let length = assemble(trial).count
            if length <= budget { chosen = trial; continue }
            // A passage that holds the question's words, or the summary, is worth clipping to fit.
            let overflow = length - budget
            let isMatched = i == summaryIndex || scores[i] > 0
            if isMatched, units[i].text.count - overflow >= 80 {
                units[i].text = String(units[i].text.prefix(units[i].text.count - overflow - 1)) + "…"
                chosen.insert(i)
            }
            // Past the passages that hold the question's words and the summary, the card is taken from the top and
            // stops at the first piece that does not fit, so a later short piece never fills a gap out of order.
            if !isMatched { break }
        }
        return assemble(chosen) + "…"
    }

    /// A text section's paragraphs, with a long paragraph cut into sentences so a passage can be picked on its own.
    private static func pieces(of text: String) -> [String] {
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.count <= 400 { out.append(t); continue }
            let parts = t.components(separatedBy: ". ")
            for (k, part) in parts.enumerated() { out.append(k < parts.count - 1 ? part + "." : part) }
        }
        return out
    }

    // MARK: What the model is given

    /// Shown above the answer when no post or quick reference matched, and nothing was sent as material.
    static let nothingMatchedLine = "Nothing in Periop Signal matched this question. This answer is from general knowledge."

    /// Where the answer came from, under it. With no sources it does not mention "the material above".
    static func provenance(backend: Backend?, matched: Bool) -> String {
        switch backend {
        case .onDevice:
            return matched
                ? "Answered on this phone by Apple Intelligence; nothing left the device. AI answers can be wrong: check the sources."
                : "Answered on this phone by Apple Intelligence; nothing left the device. No Periop Signal material was used. AI answers can be wrong: check the original documents."
        case .cloud:
            return matched
                ? "Answered by Claude through Periop Signal's proxy; the question and the material above were sent, nothing else. AI answers can be wrong: check the sources."
                : "Answered by Claude through Periop Signal's proxy; only the question was sent, nothing else. No Periop Signal material was used. AI answers can be wrong: check the original documents."
        case nil:
            return "Answers are not available on this phone yet."
        }
    }

    /// The note under the footer.
    static func footerNote(matched: Bool) -> String {
        matched
            ? "An AI answer for orientation, written from the material above and general knowledge. It can be wrong: check doses, thresholds and recommendations against the source documents before acting on them."
            : "An AI answer for orientation, written from general knowledge. It can be wrong: check doses, thresholds and recommendations against the source documents before acting on them."
    }

    /// The numbered material for the on-device prompt, one line per source, in the order and with the numbers of
    /// `grounding.sources` (the list on screen).
    static func materialLines(_ grounding: Grounding, refExcerptLimit: Int = 700) -> [String] {
        var out: [String] = []
        for (i, p) in grounding.posts.enumerated() {
            out.append("[\(i + 1)] \(p.headline) (\(p.journal)). \(String(p.summary.prefix(420)))")
        }
        for (j, r) in grounding.refs.enumerated() {
            out.append("[\(grounding.posts.count + j + 1)] Quick reference (\(r.societyShort)). \(excerpt(of: r, limit: refExcerptLimit, concepts: grounding.concepts))")
        }
        return out
    }

    static func onDeviceInstructions(hasSources: Bool) -> String {
        if hasSources {
            return """
            You are a concise reference assistant for anesthesiologists. Answer in under 120 words, in plain prose. Use the material provided and cite it as [1], [2]; when the material does not cover the question, answer from established knowledge in one or two sentences and say that the Periop Signal material did not cover it. Give numbers only when sure.
            """
        }
        return """
        You are a concise reference assistant for anesthesiologists. Answer in under 120 words, in plain prose. No Periop Signal material matched this question, so answer from established knowledge and do not cite any source. Give numbers only when sure.
        """
    }

    static func onDevicePrompt(question: String, grounding: Grounding) -> String {
        var prompt = "Question: \(question)\n"
        let lines = materialLines(grounding)
        if !lines.isEmpty { prompt += "\nMaterial:\n" + lines.joined(separator: "\n") + "\n" }
        return prompt
    }

    /// The body sent to the proxy: the posts, then the quick references, which the proxy numbers [1], [2], … in that order
    /// (the order of `grounding.sources`). Nothing matched: both lists are empty.
    static func cloudBody(question: String, grounding: Grounding) -> [String: Any] {
        let context: [[String: Any]] = grounding.posts.map { p in
            ["id": p.id, "headline": p.headline, "journal": p.journal, "date": p.date, "summary": p.summary, "takeHome": p.takeHome]
        }
        let refs: [[String: Any]] = grounding.refs.map { r in
            ["id": r.id, "title": r.title, "society": r.society, "excerpt": excerpt(of: r, concepts: grounding.concepts)]
        }
        return ["question": question, "context": context, "refs": refs]
    }

    // MARK: Answering

    /// Streams the answer as text deltas. The cloud path streams; the on-device path answers in one go.
    static func answer(question: String, grounding: Grounding, backend: Backend, endpoint: URL?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch backend {
                    case .onDevice:
                        let text = try await answerOnDevice(question: question, grounding: grounding)
                        continuation.yield(text)
                    case .cloud:
                        guard let endpoint else { throw AskError.noEndpoint }
                        try await streamCloud(question: question, grounding: grounding, endpoint: endpoint) { continuation.yield($0) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    enum AskError: LocalizedError {
        case noEndpoint, onDeviceUnavailable, server(String), guardrail
        var errorDescription: String? {
            switch self {
            case .noEndpoint: return "Answers are not set up yet: the Ask proxy has no address."
            case .onDeviceUnavailable: return "Apple Intelligence is not available on this phone."
            case .server(let s): return s
            case .guardrail: return "The on-device model declined this question; try the Claude route from More › Answers."
            }
        }
    }

    private static func answerOnDevice(question: String, grounding: Grounding) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard case .available = SystemLanguageModel.default.availability else { throw AskError.onDeviceUnavailable }
            let instructions = onDeviceInstructions(hasSources: !grounding.isEmpty)
            let prompt = onDevicePrompt(question: question, grounding: grounding)
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                if String(describing: error).lowercased().contains("guardrail") { throw AskError.guardrail }
                throw error
            }
        }
        #endif
        throw AskError.onDeviceUnavailable
    }

    private static func streamCloud(question: String, grounding: Grounding, endpoint: URL, onDelta: (String) -> Void) async throws {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ios", forHTTPHeaderField: "X-Periop-Signal")
        req.httpBody = try JSONSerialization.data(withJSONObject: cloudBody(question: question, grounding: grounding))
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines { body += line; if body.count > 600 { break } }
            let message = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])?["error"] as? String
            throw AskError.server(message ?? "The Ask service returned an error (\(http.statusCode)).")
        }
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let t = obj["t"] as? String { onDelta(t) }
            if let e = obj["error"] as? String { throw AskError.server(e) }
            if obj["done"] != nil { break }
        }
    }
}
