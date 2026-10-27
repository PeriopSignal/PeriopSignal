import Foundation
import UIKit

/// Firebase Cloud Messaging topics the feed's workflow (notify.yml) publishes to:
///   new-posts            every morning update (readers with no topics chosen)
///   t-<topic>            updates that touch one topic (readers who chose topics)
///   …-weekdays           the same, but nothing on Saturday and Sunday (quiet weekends)
///   weekly-digest        the Sunday summary
enum PushTopics {
    static let all = "new-posts"
    static let digest = "weekly-digest"
    static func topic(_ id: String) -> String { "t-" + id }

    /// The set a reader should be subscribed to, from their settings.
    static func desired(myTopics: Set<String>, digest: Bool, quietWeekends: Bool, enabled: Bool) -> Set<String> {
        guard enabled else { return [] }
        let suffix = quietWeekends ? "-weekdays" : ""
        var s: Set<String> = myTopics.isEmpty ? [all + suffix] : Set(myTopics.map { topic($0) + suffix })
        if digest { s.insert(digest) }
        return s
    }
}

#if canImport(FirebaseCore) && canImport(FirebaseMessaging)
import FirebaseCore
import FirebaseMessaging

/// Firebase Cloud Messaging bridge. Active only when GoogleService-Info.plist ships in the bundle.
enum PushBridge {
    static var isConfigured = false
    private static let subscribedKey = "ps.fcmTopics"

    static func configure() {
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else { return }
        FirebaseApp.configure()
        isConfigured = true
    }

    /// Subscribes to the topics the reader should have and leaves the rest.
    static func sync(topics desired: Set<String>) {
        guard isConfigured else { return }
        let current = Set(UserDefaults.standard.stringArray(forKey: subscribedKey) ?? [])
        for t in current.subtracting(desired) { Messaging.messaging().unsubscribe(fromTopic: t) { _ in } }
        for t in desired.subtracting(current) { Messaging.messaging().subscribe(toTopic: t) { _ in } }
        UserDefaults.standard.set(Array(desired).sorted(), forKey: subscribedKey)
    }

    static func didRegister(deviceToken: Data) {
        guard isConfigured else { return }
        Messaging.messaging().apnsToken = deviceToken
        // Re-apply the subscriptions now that the token exists.
        let desired = Set(UserDefaults.standard.stringArray(forKey: subscribedKey) ?? [])
        for t in desired { Messaging.messaging().subscribe(toTopic: t) { _ in } }
    }
}
#else
/// Placeholder used until the Firebase package is added; every call is a no-op.
enum PushBridge {
    static var isConfigured = false
    static func configure() {}
    static func sync(topics desired: Set<String>) {}
    static func didRegister(deviceToken: Data) {}
}
#endif
