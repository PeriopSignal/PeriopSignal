import Foundation
import Observation
import UserNotifications

/// Which posts the reader has opened. Mirrored to iCloud Key-Value Storage like the bookmarks.
///
/// "Unread" is deliberately narrow: a post counts only if it arrived after the app was first opened
/// (minus a three-day starter set) and within the last two weeks, so the badge never nags about
/// the archive.
@MainActor
@Observable
final class ReadStore {
    private(set) var ids: Set<String> = []
    private static let key = "ps.read"
    private static let baselineKey = "ps.readBaseline"
    private let kv = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private var observer: NSObjectProtocol?

    static let unreadWindowDays = 14

    init() {
        if defaults.string(forKey: Self.baselineKey) == nil {
            defaults.set(PSDate.daysAgo(3), forKey: Self.baselineKey)
        }
        load()
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kv, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
        kv.synchronize()
    }

    /// Posts added on or before this date are never counted as unread.
    var baseline: String { defaults.string(forKey: Self.baselineKey) ?? "" }

    func isRead(_ id: String) -> Bool { ids.contains(id) }

    func isUnread(_ post: Post) -> Bool {
        Self.isUnread(post, read: ids, baseline: baseline)
    }

    nonisolated static func isUnread(_ post: Post, read: Set<String>, baseline: String) -> Bool {
        !read.contains(post.id) && post.addedAt > baseline && post.addedAt >= PSDate.daysAgo(unreadWindowDays)
    }

    func unread(in posts: [Post]) -> [Post] { posts.filter { isUnread($0) } }

    func markRead(_ id: String) {
        guard !ids.contains(id) else { return }
        ids.insert(id)
        persist()
    }

    func markUnread(_ id: String) {
        guard ids.contains(id) else { return }
        ids.remove(id)
        persist()
    }

    func markAllRead(_ posts: [Post]) {
        ids.formUnion(posts.map(\.id))
        persist()
    }

    /// Drop markers for posts that are no longer in the feed.
    func prune(keeping posts: [Post]) {
        let live = Set(posts.map(\.id))
        let kept = ids.intersection(live)
        if kept.count != ids.count { ids = kept; persist() }
    }

    private func load() {
        let cloud = kv.array(forKey: Self.key) as? [String]
        let local = defaults.array(forKey: Self.key) as? [String]
        ids = Set((cloud ?? []) + (local ?? []))
        if cloud == nil, let local, !local.isEmpty { kv.set(local, forKey: Self.key) }
    }

    private func persist() {
        let list = Array(ids).sorted()
        defaults.set(list, forKey: Self.key)
        kv.set(list, forKey: Self.key)
        kv.synchronize()
    }

    // MARK: Used off the main store (background refresh, badge)

    /// Unread count computed from stored state alone, for background refresh.
    nonisolated static func unreadCount(in posts: [Post]) -> Int {
        let read = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let baseline = UserDefaults.standard.string(forKey: baselineKey) ?? ""
        return posts.filter { isUnread($0, read: read, baseline: baseline) }.count
    }

    /// Sets the app icon badge to the unread count (no-op when badges are not authorized).
    nonisolated static func updateBadge(unread: Int) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.badgeSetting == .enabled else { return }
        try? await UNUserNotificationCenter.current().setBadgeCount(unread)
    }
}
