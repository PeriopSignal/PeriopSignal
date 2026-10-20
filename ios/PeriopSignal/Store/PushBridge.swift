import Foundation
import UIKit

#if canImport(FirebaseCore) && canImport(FirebaseMessaging)
import FirebaseCore
import FirebaseMessaging

/// Firebase Cloud Messaging bridge. Active only when GoogleService-Info.plist ships in the bundle.
enum PushBridge {
    static let topic = "new-posts"
    static var isConfigured = false

    static func configure() {
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else { return }
        FirebaseApp.configure()
        isConfigured = true
    }

    static func subscribe() {
        guard isConfigured else { return }
        Messaging.messaging().subscribe(toTopic: topic) { _ in }
    }

    static func didRegister(deviceToken: Data) {
        guard isConfigured else { return }
        Messaging.messaging().apnsToken = deviceToken
        subscribe()
    }
}
#else
/// Placeholder used until the Firebase package is added; every call is a no-op.
enum PushBridge {
    static let topic = "new-posts"
    static var isConfigured = false
    static func configure() {}
    static func subscribe() {}
    static func didRegister(deviceToken: Data) {}
}
#endif
