import SwiftUI

struct RootView: View {
    @Environment(PostStore.self) private var store
    @Environment(SavedStore.self) private var saved
    @Environment(ReadStore.self) private var read
    @Environment(SpeechPlayer.self) private var speech
    @Environment(Preferences.self) private var prefs
    @Environment(Router.self) private var router
    @Environment(ReferenceStore.self) private var refs
    /// The terms version this phone accepted; a new version asks again.
    @AppStorage("ps.terms.accepted") private var termsAccepted = ""

    var body: some View {
        #if DEBUG
        if DebugLaunch.screen == "widget" {
            WidgetPreviewScreen()
        } else if DebugLaunch.screen == "cards" {
            CardPreviewScreen()
        } else if DebugLaunch.screen == "sharecard" {
            ShareCardPreviewScreen()
        } else {
            main
        }
        #else
        main
        #endif
    }

    private var main: some View {
        @Bindable var router = router
        return tabs
            .sheet(isPresented: $router.showWelcome) {
                OnboardingView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: Binding(get: { needsTerms }, set: { _ in })) {
                TermsGateView { termsAccepted = Terms.version }
            }
            .task { await launch() }
            .onChange(of: read.ids.count) { _, _ in
                Task { await ReadStore.updateBadge(unread: read.unread(in: store.posts).count) }
            }
            .onChange(of: store.posts.count) { _, _ in
                Task { await ReadStore.updateBadge(unread: read.unread(in: store.posts).count) }
            }
    }

    /// First launch, or new terms. Screenshot runs (debug builds) skip it unless -ps.terms show.
    private var needsTerms: Bool {
        #if DEBUG
        if LaunchSeed.string("ps.terms") != "show" { return false }
        #endif
        return termsAccepted != Terms.version
    }

    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
            FeedView()
                .tabItem { Label("Feed", systemImage: "waveform.path.ecg") }
                .tag(Router.Tab.feed)
            PatientView()
                .tabItem { Label("My Patient", systemImage: "person.text.rectangle") }
                .tag(Router.Tab.patient)
            ReferenceView()
                .tabItem { Label("Reference", systemImage: "books.vertical") }
                .tag(Router.Tab.reference)
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(Router.Tab.more)
        }
        // Re-render everything when the in-app text size changes (PS.sys reads a static scale).
        .id(prefs.textScale)
    }

    private func launch() async {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "ps.launchCount") + 1, forKey: "ps.launchCount")
        #if DEBUG
        if let a = UserDefaults.standard.string(forKey: "ps.forceAppearance") { UserDefaults.standard.set(a, forKey: "ps.appearance") }
        if let n = UserDefaults.standard.string(forKey: "ps.forceLaunchCount"), let v = Int(n) { UserDefaults.standard.set(v, forKey: "ps.launchCount") }
        if let id = DebugLaunch.presave, !saved.contains(id) { saved.toggle(id) }
        if let topics = DebugLaunch.topics { prefs.setTopics(Set(topics)) }
        switch DebugLaunch.tab {
        case "saved": router.showSaved()
        case "patient": router.selectedTab = .patient
        case "about", "more": router.selectedTab = .more
        case "guidelines", "reference": router.selectedTab = .reference
        default: break
        }
        // Screenshot runs open their tool at once; the reference data is already bundled.
        if let r = DebugLaunch.refRoute { router.selectedTab = .reference; router.pendingRefRoute = r }
        #endif
        async let refsLoad: Void = refs.load()
        await store.loadInitial()
        _ = await refsLoad
        read.prune(keeping: store.posts)
        let unread = read.unread(in: store.posts).count
        Task { await ReadStore.updateBadge(unread: unread) }
        #if DEBUG
        if let id = DebugLaunch.openPost { router.open(postID: id) }
        if DebugLaunch.openQuiz { router.openQuiz = true }
        if DebugLaunch.showWelcome { router.showWelcome = true }
        if DebugLaunch.listen, let first = store.latestBatch.first {
            // Show the mini player for the screenshot, paused, without audio on the simulator.
            speech.play([first] + Array(store.latestBatch.dropFirst().prefix(2)))
            speech.toggle()
        }
        #endif
    }
}
