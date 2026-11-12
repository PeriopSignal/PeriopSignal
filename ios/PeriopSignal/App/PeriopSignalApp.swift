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
    @State private var refs = ReferenceStore()
    @State private var favorites = FavoritesStore()
    @State private var patient = PatientStore()
    @State private var inbox = PatientInbox()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("ps.appearance") private var appearance: Appearance = .dark

    /// The saved appearance. A screenshot run's -ps.forceAppearance light|dark applies to that launch only and is
    /// never saved, so the next launch's appearance comes from its own arguments.
    private var launchAppearance: Appearance {
        #if DEBUG
        if let forced = Appearance(rawValue: LaunchSeed.string("ps.forceAppearance")) { return forced }
        #endif
        return appearance
    }

    init() {
        #if DEBUG
        // Screenshot runs: the CI waits for a page this launch opens (ShotReady).
        ShotReady.begin()
        #endif
        // Earlier versions kept the last patient weight and age in settings; those keys are removed. My Patient keeps
        // its one record in a protected file instead (PatientStore), until the user clears it.
        PatientHandoff.purgeStoredPatientValues()
        PatientInbox.purgeLeftovers()
        let prefs = Preferences()
        let postStore = PostStore()
        postStore.preferences = prefs
        _preferences = State(initialValue: prefs)
        _store = State(initialValue: postStore)
        let player = SpeechPlayer()
        player.rate = Float(prefs.speechRate)
        player.preferences = prefs
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
                .environment(refs)
                .environment(favorites)
                .environment(patient)
                .environment(inbox)
                .preferredColorScheme(launchAppearance.colorScheme)
                .tint(PS.accent)
                .onOpenURL { url in
                    // A patient a colleague sent (AirDrop or Messages) opens My Patient, which asks before taking it.
                    // 1.12: a patient link (AirDrop, opt-in) holds the patient, so IncomingURL takes it before the router.
                    IncomingURL.handle(url, inbox: inbox, router: router)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let id = SpotlightIndexer.postID(from: activity) { router.open(postID: id) }
                }
                .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openPostNotification)) { note in
                    if let id = note.userInfo?["postID"] as? String { router.open(postID: id) }
                    else if let tab = note.userInfo?["tab"] as? String {
                        if tab == "saved" { router.showSaved() }
                        else if let t = Router.Tab(rawValue: tab == "guidelines" ? "reference" : tab) { router.selectedTab = t }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        patient.refresh()
                        CaseTimerNotifier.shared.sync(book: patient.book, data: refs.caseTimers)
                    }
                }
                // Case timers of every open case, as notifications and the lock-screen countdown.
                .onChange(of: patient.book) { _, book in CaseTimerNotifier.shared.sync(book: book, data: refs.caseTimers) }
                .onChange(of: refs.caseTimers) { _, data in CaseTimerNotifier.shared.sync(book: patient.book, data: data) }
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
    /// Presents the welcome screen (topics and alerts) from More or a link.
    var showWelcome = false
    /// A calculator or quick reference to open on the Reference tab (links, Spotlight, debug launches).
    var pendingRefRoute: RefRoute?
    /// Set to open the saved posts, which live under More.
    var openSaved = false

    enum Tab: String, Hashable { case feed, patient, reference, more }

    init() {
        #if DEBUG
        // Screenshot runs open on their tab from the first frame. RootView's launch task sets it too, but a slow first
        // launch in the simulator can hold that task back past the screenshot, which then shows the Feed.
        switch UserDefaults.standard.string(forKey: "ps.tab") {
        case "patient": selectedTab = .patient
        case "about", "more": selectedTab = .more
        case "guidelines", "reference": selectedTab = .reference
        default: break
        }
        if let r = UserDefaults.standard.string(forKey: "ps.ref"), !r.isEmpty { selectedTab = .reference }
        #endif
    }

    func showSaved() {
        selectedTab = .more
        openSaved = true
    }

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
        case "saved": showSaved()
        case "patient", "mypatient": selectedTab = .patient
        case "guidelines", "reference": selectedTab = .reference
        case "calculator", "score", "tool":
            // periopsignal://tool/valves, periopsignal://score/rcri, periopsignal://calculator/peds
            selectedTab = .reference
            if let id = parts.first {
                pendingRefRoute = id == "pediatric" ? .peds : (RefRoute(key: id) ?? RefRoute(key: parts.joined(separator: ":")) ?? .score(id))
            }
        case "quickref", "ref":
            selectedTab = .reference
            if let id = parts.first { pendingRefRoute = .quickref(id) }
        case "more", "about", "settings": selectedTab = .more
        case "quiz", "question":
            selectedTab = .feed
            openQuiz = true
        case "welcome", "topics":
            showWelcome = true
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
