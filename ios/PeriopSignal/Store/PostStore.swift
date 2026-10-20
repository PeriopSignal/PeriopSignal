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

    var hasFilters: Bool { !selectedTopics.isEmpty || landmarkOnly || recentOnly || !query.isEmpty }

    func clearFilters() {
        selectedTopics = []; landmarkOnly = false; recentOnly = false; query = ""
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
        } catch {
            errorMessage = posts.isEmpty
                ? "Couldn’t load the feed. Check your connection and pull to retry."
                : "Showing the last copy saved on this phone."
        }
    }

    private func apply(_ feed: Feed) {
        posts = feed.posts.sorted { ($0.date, $0.addedAt, $0.id) > ($1.date, $1.addedAt, $1.id) }
        generatedAt = feed.generatedAt
        let lastSeen = UserDefaults.standard.string(forKey: lastSeenKey) ?? ""
        if lastSeen.isEmpty {
            newIDs = []
        } else {
            newIDs = Set(posts.filter { $0.addedAt > lastSeen }.map(\.id))
        }
    }

    /// Remember the newest addedAt so the next launch can mark what arrived in between.
    private func markSeen() {
        guard let newest = posts.map(\.addedAt).max() else { return }
        UserDefaults.standard.set(newest, forKey: lastSeenKey)
    }

    // MARK: Derived

    var weekAgo: String {
        let d = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return PSDate.formatter.string(from: d)
    }

    var publishedThisWeek: Int {
        let cutoff = weekAgo
        return posts.filter { $0.date >= cutoff }.count
    }

    var landmarkCount: Int { posts.filter(\.isLandmark).count }

    func topicCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for p in posts { for t in p.topics { counts[t, default: 0] += 1 } }
        return counts
    }

    var filtered: [Post] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cutoff = weekAgo
        return posts.filter { p in
            if landmarkOnly && !p.isLandmark { return false }
            if recentOnly && p.date < cutoff { return false }
            if !selectedTopics.isEmpty && selectedTopics.isDisjoint(with: p.topics) { return false }
            if !q.isEmpty && !p.searchText.contains(q) { return false }
            return true
        }
    }

    func post(id: String) -> Post? { posts.first { $0.id == id } }

    var newestPost: Post? { posts.first }
    var newestLandmark: Post? { posts.first(where: \.isLandmark) }

    var generatedDate: Date? { ISO8601DateFormatter().date(from: generatedAt) }
}
