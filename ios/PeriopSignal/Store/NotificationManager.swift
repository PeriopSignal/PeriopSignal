import Foundation
import UIKit
import UserNotifications
import BackgroundTasks
import WidgetKit

/// Morning notifications.
///
/// Two layers:
/// 1. Background refresh (no server needed): iOS wakes the app a few times a day; if the feed has new
///    posts since the last check, a local notification is posted, held until the reader's alert time
///    and skipped on weekends when they asked for quiet weekends. On Sundays the same refresh posts
///    the week's summary.
/// 2. Push through Firebase Cloud Messaging when the owner has added a GoogleService-Info.plist: the
///    feed's publishing workflow sends one message per topic ("t-cardiac", …) or to "new-posts", and
///    the Sunday digest to "weekly-digest". FirebaseMessaging is wired in PushBridge.swift and is a
///    no-op until that file is present.
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    static let refreshTaskID = "org.periopsignal.app.refresh"
    private let lastNotifiedKey = "ps.lastNotifiedAddedAt"
    private let lastDigestKey = "ps.lastDigestWeek"

    @Published var authorization: UNAuthorizationStatus = .notDetermined

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "ps.notifyEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "ps.notifyEnabled")
            syncTopics()
        }
    }

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
    }

    /// Ask for permission; returns whether notifications are allowed afterwards.
    @discardableResult
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        if granted {
            enabled = true
            UIApplication.shared.registerForRemoteNotifications()
            scheduleRefresh()
        }
        return granted
    }

    // MARK: Settings read without the Preferences object (background refresh runs without the UI)

    private var alertTime: DateComponents {
        let d = UserDefaults.standard
        return DateComponents(hour: d.object(forKey: "ps.alertHour") as? Int ?? 6, minute: d.object(forKey: "ps.alertMinute") as? Int ?? 30)
    }
    private var quietWeekends: Bool { UserDefaults.standard.bool(forKey: "ps.quietWeekends") }
    private var weeklyDigest: Bool { UserDefaults.standard.object(forKey: "ps.weeklyDigest") as? Bool ?? true }
    private var myTopics: Set<String> { Set(UserDefaults.standard.stringArray(forKey: "ps.myTopics") ?? []) }

    /// Keep the push subscriptions in line with the reader's topics and digest setting.
    func syncTopics() {
        PushBridge.sync(topics: PushTopics.desired(myTopics: myTopics, digest: weeklyDigest, quietWeekends: quietWeekends, enabled: enabled))
    }

    // MARK: Background refresh

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                await self.handleRefresh(task: task)
            }
        }
    }

    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleRefresh(task: BGAppRefreshTask) async {
        scheduleRefresh()
        let work = Task { () -> Bool in
            let previous = FeedLoader.loadCached()
            guard let result = try? await FeedLoader.fetch() else { return false }
            let (feed, data) = result
            FeedLoader.saveCache(data)
            WidgetCenter.shared.reloadAllTimelines()
            let known = Set(previous?.posts.map(\.id) ?? [])
            let fresh = feed.posts.filter { !known.contains($0.id) }
            if !fresh.isEmpty, !known.isEmpty { await self.notifyLocally(about: fresh) }
            await self.notifyDigestIfSunday(feed.posts)
            await ReadStore.updateBadge(unread: ReadStore.unreadCount(in: feed.posts))
            return true
        }
        task.expirationHandler = { work.cancel() }
        let ok = await work.value
        task.setTaskCompleted(success: ok)
    }

    private func canNotify() async -> Bool {
        guard enabled else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Delivery trigger honouring the alert time: immediate once the time has passed today, otherwise
    /// a calendar trigger for later today. Nil means "skip" (quiet weekend).
    private func deliveryTrigger(for date: Date = Date()) -> (UNNotificationTrigger?, skip: Bool) {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        if quietWeekends && (weekday == 1 || weekday == 7) { return (nil, true) }
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = alertTime.hour; comps.minute = alertTime.minute
        if let at = cal.date(from: comps), at > date.addingTimeInterval(60) {
            return (UNCalendarNotificationTrigger(dateMatching: comps, repeats: false), false)
        }
        return (nil, false)
    }

    /// Local notification for posts found by background refresh. Only the reader's topics count when
    /// they chose some; a push already covering the batch is deduplicated by addedAt.
    func notifyLocally(about fresh: [Post]) async {
        guard await canNotify() else { return }
        let mine = myTopics
        let relevant = mine.isEmpty ? fresh : fresh.filter { !mine.isDisjoint(with: $0.topics) }
        guard !relevant.isEmpty else { return }
        let newest = relevant.map(\.addedAt).max() ?? ""
        let lastNotified = UserDefaults.standard.string(forKey: lastNotifiedKey) ?? ""
        guard newest > lastNotified else { return }
        let (trigger, skip) = deliveryTrigger()
        if skip { return }
        UserDefaults.standard.set(newest, forKey: lastNotifiedKey)

        let content = UNMutableNotificationContent()
        let lead = relevant.sorted { ($0.impact, $0.date) > ($1.impact, $1.date) }.first!
        content.title = relevant.count == 1 ? "New in Periop Signal" : "\(relevant.count) new papers in Periop Signal"
        content.body = lead.headline
        content.sound = .default
        content.userInfo = ["postID": lead.id]
        content.threadIdentifier = "periop-signal"
        let request = UNNotificationRequest(identifier: "ps-\(newest)", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Sunday summary from background refresh (the push path sends the same through "weekly-digest").
    func notifyDigestIfSunday(_ posts: [Post]) async {
        guard weeklyDigest, await canNotify() else { return }
        let cal = Calendar.current
        guard cal.component(.weekday, from: Date()) == 1 else { return }
        let week = "\(cal.component(.yearForWeekOfYear, from: Date()))-\(cal.component(.weekOfYear, from: Date()))"
        guard UserDefaults.standard.string(forKey: lastDigestKey) != week else { return }
        let cutoff = PSDate.daysAgo(7)
        let mine = myTopics
        var recent = posts.filter { $0.addedAt >= cutoff }
        if !mine.isEmpty { recent = recent.filter { !mine.isDisjoint(with: $0.topics) } }
        guard !recent.isEmpty else { return }
        let (trigger, _) = deliveryTrigger()
        UserDefaults.standard.set(week, forKey: lastDigestKey)
        let landmark = recent.filter(\.isLandmark).count
        let content = UNMutableNotificationContent()
        content.title = "This week in Periop Signal"
        content.body = "\(recent.count) new post\(recent.count == 1 ? "" : "s")" + (landmark > 0 ? ", \(landmark) landmark" : "") + ". " + (recent.sorted { ($0.impact, $0.date) > ($1.impact, $1.date) }.first?.headline ?? "")
        content.sound = .default
        content.threadIdentifier = "periop-signal-digest"
        content.userInfo = ["tab": "feed"]
        let request = UNNotificationRequest(identifier: "ps-digest-\(week)", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
