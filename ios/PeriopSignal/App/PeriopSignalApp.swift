import SwiftUI
import UserNotifications

@main
struct PeriopSignalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = PostStore()
    @State private var saved = SavedStore()
    @State private var router = Router()
    @AppStorage("ps.appearance") private var appearance: Appearance = .dark

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(saved)
                .environment(router)
                .preferredColorScheme(appearance.colorScheme)
                .tint(PS.accent)
                .onOpenURL { url in router.handle(url) }
                .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openPostNotification)) { note in
                    if let id = note.userInfo?["postID"] as? String { router.open(postID: id) }
                }
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .dark: return "Night shift"
        case .light: return "Day"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

/// Navigation requests from widgets, notifications and links (periopsignal://post/<id>).
@MainActor
@Observable
final class Router {
    var pendingPostID: String?
    var selectedTab: Tab = .feed

    enum Tab: Hashable { case feed, saved, about }

    func open(postID: String) {
        selectedTab = .feed
        pendingPostID = postID
    }

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "periopsignal" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.host == "post", let id = parts.first {
            open(postID: id)
        } else if url.host == "saved" {
            selectedTab = .saved
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let openPostNotification = Notification.Name("ps.openPost")

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PushBridge.configure()
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.shared.registerBackgroundTask()
        NotificationManager.shared.scheduleRefresh()
        if NotificationManager.shared.enabled {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushBridge.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected on the simulator and when the push entitlement is missing; background refresh still works.
    }

    // Show notifications while the app is in the foreground too.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let id = info["postID"] as? String {
            NotificationCenter.default.post(name: Self.openPostNotification, object: nil, userInfo: ["postID": id])
        }
    }
}
