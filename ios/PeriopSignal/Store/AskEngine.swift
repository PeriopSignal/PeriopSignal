import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Answers a question the references and the feed could not: on the phone with Apple's model when
/// the device has it, otherwise through the Periop Signal proxy (worker/), which asks Claude. Both
/// are handed the best-matching posts and quick references so the answer is grounded and cited.
enum AskEngine {
    enum Backend: String { case onDevice, cloud }

    struct Source: Identifiable, Hashable {
        enum Kind: Hashable { case post(String), quickref(String) }
        let id: Int
        let title: String
        let subtitle: String
        let kind: Kind
    }

    struct Grounding {
        var posts: [Post]
        var refs: [QuickRef]
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

    static func grounding(for question: String, posts: [Post], refs: [QuickRef]) -> Grounding {
        let words = Set(question.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stop.contains($0) })
        guard !words.isEmpty else { return Grounding(posts: [], refs: []) }
        func score(_ text: String, headline: String) -> Int {
            var s = 0
            for w in words {
                if headline.contains(w) { s += 3 }
                if text.contains(w) { s += 1 }
            }
            return s
        }
        let rankedPosts = posts.map { ($0, score($0.searchText, headline: $0.headline.lowercased())) }
            .filter { $0.1 >= 2 }.sorted { $0.1 > $1.1 }.prefix(4).map(\.0)
        let rankedRefs = refs.map { ($0, score($0.searchText, headline: ($0.title + " " + ($0.keywords ?? []).joined(separator: " ")).lowercased())) }
            .filter { $0.1 >= 2 }.sorted { $0.1 > $1.1 }.prefix(2).map(\.0)
        return Grounding(posts: Array(rankedPosts), refs: Array(rankedRefs))
    }

    private static let stop: Set<String> = ["the", "and", "for", "with", "what", "when", "how", "does", "are", "is", "of", "in", "to", "a", "an", "on", "or", "should", "can", "patient", "patients", "about", "versus", "after", "before", "which", "that", "this", "than", "from", "use", "used", "dose"]

    /// A plain-text excerpt of a quick reference for the model (its tables flattened).
    static func excerpt(of ref: QuickRef, limit: Int = 1400) -> String {
        var parts: [String] = [ref.summary]
        for s in ref.sections {
            if let h = s.heading { parts.append(h + ":") }
            switch s.kind {
            case .text: if let t = s.text { parts.append(t) }
            case .list, .steps: parts.append((s.items ?? []).joined(separator: " · "))
            case .facts: parts.append((s.rows ?? []).map { $0.joined(separator: ": ") }.joined(separator: "; "))
            case .table:
                let cols = s.columns ?? []
                for row in s.rows ?? [] {
                    let cells = row.enumerated().dropFirst().compactMap { i, c in c.isEmpty ? nil : "\(i < cols.count ? cols[i] : "") \(c)" }
                    parts.append((row.first ?? "") + " — " + cells.joined(separator: "; "))
                }
            }
        }
        let text = parts.joined(separator: "\n")
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
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
            let instructions = """
            You are a concise reference assistant for anesthesiologists. Answer in under 120 words, in plain prose. Use the material provided and cite it as [1], [2]; when the material does not cover the question, answer from established knowledge in one or two sentences and say that the Periop Signal material did not cover it. Give numbers only when sure.
            """
            var prompt = "Question: \(question)\n"
            let sources = grounding.sources
            if !sources.isEmpty {
                prompt += "\nMaterial:\n"
                var n = 0
                for p in grounding.posts.prefix(3) {
                    n += 1
                    prompt += "[\(n)] \(p.headline) (\(p.journal)). \(String(p.summary.prefix(420)))\n"
                }
                for r in grounding.refs.prefix(1) {
                    n += 1
                    prompt += "[\(n)] \(r.title) (\(r.societyShort)). \(excerpt(of: r, limit: 700))\n"
                }
            }
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
        let context: [[String: Any]] = grounding.posts.map { p in
            ["id": p.id, "headline": p.headline, "journal": p.journal, "date": p.date, "summary": p.summary, "takeHome": p.takeHome]
        }
        let refs: [[String: Any]] = grounding.refs.map { r in
            ["id": r.id, "title": r.title, "society": r.society, "excerpt": excerpt(of: r)]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["question": question, "context": context, "refs": refs])
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
