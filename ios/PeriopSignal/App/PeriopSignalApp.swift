import CoreSpotlight
import SwiftUI
import UserNotifications

@main
struct PeriopSignalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var preferences: Preferences
    @State private var store: PostStore
    @State private var speech: SpeechPlayer
    @State private var saved = SavedStore()
    @State private var read = ReadStore()
    @State private var quiz = QuizStore()
    @State private var router = Router()
    @AppStorage("ps.appearance") private var appearance: Appearance = .dark

    init() {
        let prefs = Preferences()
        let postStore = PostStore()
        postStore.preferences = prefs
        _preferences = State(initialValue: prefs)
        _store = State(initialValue: postStore)
        let player = SpeechPlayer()
        player.rate = Float(prefs.speechRate)
        _speech = State(initialValue: player)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(saved)
                .environment(read)
                .environment(quiz)
                .environment(speech)
                .environment(preferences)
                .environment(router)
                .preferredColorScheme(appearance.colorScheme)
                .tint(PS.accent)
                .onOpenURL { url in router.handle(url) }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let id = SpotlightIndexer.postID(from: activity) { router.open(postID: id) }
                }
                .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openPostNotification)) { note in
                    if let id = note.userInfo?["postID"] as? String { router.open(postID: id) }
                    else if let tab = note.userInfo?["tab"] as? String, let t = Router.Tab(rawValue: tab) { router.selectedTab = t }
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

/// Navigation requests from widgets, notifications, Spotlight and links (periopsignal://post/<id>).
@MainActor
@Observable
final class Router {
    var pendingPostID: String?
    var selectedTab: Tab = .feed
    /// Set to open today's question from a link or notification.
    var openQuiz = false

    enum Tab: String, Hashable { case feed, guidelines, saved, more }

    func open(postID: String) {
        selectedTab = .feed
        pendingPostID = postID
    }

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "periopsignal" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host?.lowercased() {
        case "post":
            if let id = parts.first { open(postID: id) }
        case "saved": selectedTab = .saved
        case "guidelines": selectedTab = .guidelines
        case "more", "about", "settings": selectedTab = .more
        case "quiz", "question":
            selectedTab = .feed
            openQuiz = true
        default: selectedTab = .feed
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
        NotificationManager.shared.syncTopics()
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
        } else if let tab = info["tab"] as? String {
            NotificationCenter.default.post(name: Self.openPostNotification, object: nil, userInfo: ["tab": tab])
        }
    }
}
