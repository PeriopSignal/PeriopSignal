import Foundation
import Observation

/// Daily question: which questions the reader has answered, the running streak, and today's pick.
/// Answers mirror to iCloud so the streak follows the reader across devices.
@MainActor
@Observable
final class QuizStore {
    struct Answer: Codable, Hashable {
        var chosen: Int
        var correct: Bool
        var date: String   // YYYY-MM-DD in the feed's time zone
    }

    private(set) var answers: [String: Answer] = [:]
    private static let key = "ps.quiz.answers"
    private static let todayKey = "ps.quiz.today"
    private let kv = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private var observer: NSObjectProtocol?

    init() {
        load()
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kv, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
    }

    func answer(for postID: String) -> Answer? { answers[postID] }

    func record(postID: String, chosen: Int, correct: Bool) {
        answers[postID] = Answer(chosen: chosen, correct: correct, date: PSDate.today)
        persist()
    }

    // MARK: Stats

    var answeredCount: Int { answers.count }
    var correctCount: Int { answers.values.filter(\.correct).count }

    /// Consecutive days with at least one answer, counting back from today (or yesterday, so the
    /// streak survives until tonight).
    var streak: Int {
        let days = Set(answers.values.map(\.date))
        guard !days.isEmpty else { return 0 }
        var cursor = PSDate.parse(PSDate.today) ?? Date()
        if !days.contains(PSDate.formatter.string(from: cursor)) {
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
            if !days.contains(PSDate.formatter.string(from: cursor)) { return 0 }
        }
        var n = 0
        while days.contains(PSDate.formatter.string(from: cursor)) {
            n += 1
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return n
    }

    var answeredToday: Bool { answers.values.contains { $0.date == PSDate.today } }

    // MARK: Today's pick

    /// The question for today: fixed for the whole day, chosen among unanswered questions with a
    /// preference for recent and high-impact posts. Falls back to any question once all are answered.
    func todaysQuestion(from posts: [Post]) -> Post? {
        let today = PSDate.today
        if let saved = defaults.dictionary(forKey: Self.todayKey) as? [String: String],
           saved["date"] == today, let id = saved["id"], let post = posts.first(where: { $0.id == id && $0.quiz != nil }) {
            return post
        }
        let withQuiz = posts.filter { $0.quiz != nil }
        guard !withQuiz.isEmpty else { return nil }
        var pool = withQuiz.filter { answers[$0.id] == nil }
        if pool.isEmpty { pool = withQuiz }
        // Newest 40 posts, weighted by impact so landmark papers come up more often.
        let recent = Array(pool.sorted { ($0.addedAt, $0.id) > ($1.addedAt, $1.id) }.prefix(40))
        var weighted: [Post] = []
        for p in recent { for _ in 0..<max(1, p.impact) { weighted.append(p) } }
        let seed = today.unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) }
        let pick = weighted[Int(seed.magnitude % UInt(weighted.count))]
        defaults.set(["date": today, "id": pick.id], forKey: Self.todayKey)
        return pick
    }

    // MARK: Persistence

    private func load() {
        let cloudData = kv.data(forKey: Self.key)
        let localData = defaults.data(forKey: Self.key)
        let dec = JSONDecoder()
        let cloud = cloudData.flatMap { try? dec.decode([String: Answer].self, from: $0) } ?? [:]
        let local = localData.flatMap { try? dec.decode([String: Answer].self, from: $0) } ?? [:]
        answers = local.merging(cloud) { mine, theirs in mine.date >= theirs.date ? mine : theirs }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(answers) else { return }
        defaults.set(data, forKey: Self.key)
        kv.set(data, forKey: Self.key)
        kv.synchronize()
    }
}
