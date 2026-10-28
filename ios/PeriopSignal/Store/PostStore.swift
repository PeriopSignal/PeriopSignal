import Foundation
import Observation
import WidgetKit

/// Loads the feed (cache first, then network), keeps the filter state and derives the visible list.
@MainActor
@Observable
final class PostStore {
    private(set) var posts: [Post] = []
    private(set) var generatedAt: String = ""
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var loadedFromCache = false

    /// Injected at launch; drives the "For you" filter.
    var preferences: Preferences?

    // Filters
    var selectedTopics: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "ps.topics") ?? []) {
        didSet { UserDefaults.standard.set(Array(selectedTopics), forKey: "ps.topics") }
    }
    var landmarkOnly = false
    var recentOnly = false
    var query = ""

    /// Posts added since the previous launch ("New" pill), like the site's last-visit marker.
    private(set) var newIDs: Set<String> = []
    private let lastSeenKey = "ps.lastSeenAddedAt"

    var forYouActive: Bool { (preferences?.forYou ?? false) && !(preferences?.myTopics.isEmpty ?? true) }
    var hasFilters: Bool { !selectedTopics.isEmpty || landmarkOnly || recentOnly || !query.isEmpty || forYouActive }

    func clearFilters() {
        selectedTopics = []; landmarkOnly = false; recentOnly = false; query = ""
        preferences?.forYou = false
    }

    // MARK: Loading

    func loadInitial() async {
        if posts.isEmpty, let cached = FeedLoader.loadCached() {
            apply(cached)
            loadedFromCache = true
            lastRefresh = FeedLoader.cacheDate
        }
        await refresh()
        markSeen()
    }

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let (feed, data) = try await FeedLoader.fetch()
            apply(feed)
            FeedLoader.saveCache(data)
            lastRefresh = Date()
            loadedFromCache = false
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
            // Off the refresh path: Spotlight can be slow to answer and must never hold up the feed.
            let snapshot = posts
            Task.detached(priority: .utility) { await SpotlightIndexer.indexIfNeeded(snapshot) }
        } catch {
            errorMessage = posts.isEmpty
                ? "Couldn’t load the feed. Check your connection and pull to retry."
                : "Showing the last copy saved on this phone."
        }
    }

    private func apply(_ feed: Feed) {
        // Same order as the website: newest arrival first, then publication date, then impact.
        posts = feed.posts.sorted { ($0.addedAt, $0.date, $0.impact) > ($1.addedAt, $1.date, $1.impact) }
        generatedAt = feed.generatedAt
        let lastSeen = UserDefaults.standard.string(forKey: lastSeenKey) ?? ""
        if lastSeen.isEmpty {
            newIDs = []
        } else {
            newIDs = Set(posts.filter { $0.addedAt > lastSeen }.map(\.id))
        }
    }

    #if DEBUG
    /// Test hook: load posts directly.
    func inject(_ list: [Post]) { apply(Feed(name: "test", generatedAt: "", posts: list)) }
    #endif

    /// Remember the newest addedAt so the next launch can mark what arrived in between.
    private func markSeen() {
        guard let newest = posts.map(\.addedAt).max() else { return }
        UserDefaults.standard.set(newest, forKey: lastSeenKey)
    }

    // MARK: Derived

    var weekAgo: String { PSDate.daysAgo(7) }

    var publishedThisWeek: Int {
        let cutoff = weekAgo
        return posts.filter { $0.date >= cutoff }.count
    }

    var addedThisWeek: [Post] {
        let cutoff = weekAgo
        return posts.filter { $0.addedAt >= cutoff }
    }

    var landmarkCount: Int { posts.filter(\.isLandmark).count }

    func topicCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for p in posts { for t in p.topics { counts[t, default: 0] += 1 } }
        return counts
    }

    /// Posts in the reader's topics (everything when no topics are chosen).
    var forYouPosts: [Post] {
        guard let mine = preferences?.myTopics, !mine.isEmpty else { return posts }
        return posts.filter { !mine.isDisjoint(with: $0.topics) }
    }

    var forYouCount: Int { forYouPosts.count }

    var filtered: [Post] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cutoff = weekAgo
        let mine = forYouActive ? (preferences?.myTopics ?? []) : []
        return posts.filter { p in
            if landmarkOnly && !p.isLandmark { return false }
            if recentOnly && p.date < cutoff { return false }
            if !mine.isEmpty && mine.isDisjoint(with: p.topics) { return false }
            if !selectedTopics.isEmpty && selectedTopics.isDisjoint(with: p.topics) { return false }
            if !q.isEmpty && !p.searchText.contains(q) { return false }
            return true
        }
    }

    func post(id: String) -> Post? { posts.first { $0.id == id } }

    var newestPost: Post? { posts.first }
    var newestLandmark: Post? { posts.first(where: \.isLandmark) }

    var generatedDate: Date? { ISO8601DateFormatter().date(from: generatedAt) }

    // MARK: Today

    /// The most recent batch the morning run added (all posts sharing the newest addedAt).
    var latestBatchDate: String { posts.map(\.addedAt).max() ?? "" }

    var latestBatch: [Post] {
        let d = latestBatchDate
        guard !d.isEmpty else { return [] }
        return posts.filter { $0.addedAt == d }.sorted { ($0.impact, $0.date) > ($1.impact, $1.date) }
    }

    var latestBatchIsToday: Bool { latestBatchDate == PSDate.today }

    /// Counts for the Sunday / Monday "this week" line.
    var weekSummary: (posts: Int, landmark: Int, topTopics: [(String, Int)]) {
        let week = addedThisWeek
        var counts: [String: Int] = [:]
        for p in week { for t in p.topics { counts[t, default: 0] += 1 } }
        let top = counts.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.prefix(3).map { ($0.key, $0.value) }
        return (week.count, week.filter(\.isLandmark).count, Array(top))
    }

    // MARK: Guidelines

    /// Guidelines and consensus statements grouped by society, then regulatory and safety notices.
    var guidelineGroups: [(society: String, posts: [Post])] {
        var groups: [String: [Post]] = [:]
        for p in posts where p.isGuidance {
            groups[p.society, default: []].append(p)
        }
        var out = groups.map { (society: $0.key, posts: $0.value) }
            .sorted { a, b in
                if a.society == "Other societies" { return false }
                if b.society == "Other societies" { return true }
                return (a.posts.count, b.society) > (b.posts.count, a.society)
            }
        let regulatory = posts.filter(\.isRegulatory)
        if !regulatory.isEmpty { out.append((society: "FDA and safety notices", posts: regulatory)) }
        return out
    }

    // MARK: Related

    /// Up to three posts that belong with this one: same trial, shared topics, same journal or kind.
    func related(to post: Post, limit: Int = 3) -> [Post] {
        let topics = Set(post.topics)
        let trial = post.trialName.trimmingCharacters(in: .whitespaces).lowercased()
        let scored: [(Post, Double)] = posts.compactMap { other in
            guard other.id != post.id else { return nil }
            var score = 0.0
            if !trial.isEmpty, other.trialName.lowercased() == trial { score += 10 }
            score += Double(topics.intersection(other.topics).count) * 2
            if other.journal == post.journal { score += 1 }
            if other.kind == post.kind { score += 0.5 }
            if other.isLandmark { score += 0.5 }
            // Shared distinctive words in the headline (drug names, procedures).
            let a = Set(Self.keywords(post.headline)), b = Set(Self.keywords(other.headline))
            score += Double(a.intersection(b).count) * 1.5
            // Mild recency preference.
            if other.date >= PSDate.daysAgo(180) { score += 0.5 }
            return score >= 2 ? (other, score) : nil
        }
        return scored.sorted { ($0.1, $0.0.date) > ($1.1, $1.0.date) }.prefix(limit).map(\.0)
    }

    private static let stopWords: Set<String> = ["the", "and", "for", "with", "after", "before", "during", "versus", "from", "that", "this", "than", "into", "over", "under", "does", "not", "did", "are", "was", "were", "has", "have", "patients", "surgery", "trial", "study", "years", "year", "adults", "new", "first", "more", "less", "risk", "rate", "use", "per", "cardiac", "anesthesia", "anaesthesia", "care", "high", "low"]

    static func keywords(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopWords.contains($0) && Int($0) == nil }
    }
}
