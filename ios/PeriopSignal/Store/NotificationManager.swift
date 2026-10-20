import Foundation
import UIKit
import UserNotifications
import BackgroundTasks
import WidgetKit

/// Morning notifications.
///
/// Two layers:
/// 1. Background refresh (no server needed): iOS wakes the app a few times a day; if the feed has new
///    posts since the last check, a local notification is posted.
/// 2. Push through Firebase Cloud Messaging (topic "new-posts") when the owner has added a
///    GoogleService-Info.plist; the feed's publishing workflow sends one message per update.
///    FirebaseMessaging is wired in PushBridge.swift and is a no-op until that file is present.
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    static let refreshTaskID = "org.periopsignal.app.refresh"
    private let lastNotifiedKey = "ps.lastNotifiedAddedAt"

    @Published var authorization: UNAuthorizationStatus = .notDetermined

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "ps.notifyEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "ps.notifyEnabled") }
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
            PushBridge.subscribe()
            scheduleRefresh()
        }
        return granted
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
            return true
        }
        task.expirationHandler = { work.cancel() }
        let ok = await work.value
        task.setTaskCompleted(success: ok)
    }

    /// Local notification for posts found by background refresh (skipped when a push already covered them).
    func notifyLocally(about fresh: [Post]) async {
        guard enabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let newest = fresh.map(\.addedAt).max() ?? ""
        let lastNotified = UserDefaults.standard.string(forKey: lastNotifiedKey) ?? ""
        guard newest > lastNotified else { return }
        UserDefaults.standard.set(newest, forKey: lastNotifiedKey)

        let content = UNMutableNotificationContent()
        let lead = fresh.sorted { ($0.impact, $0.date) > ($1.impact, $1.date) }.first!
        content.title = fresh.count == 1 ? "New in Periop Signal" : "\(fresh.count) new papers in Periop Signal"
        content.body = lead.headline
        content.sound = .default
        content.userInfo = ["postID": lead.id]
        content.threadIdentifier = "periop-signal"
        let request = UNNotificationRequest(identifier: "ps-\(newest)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
