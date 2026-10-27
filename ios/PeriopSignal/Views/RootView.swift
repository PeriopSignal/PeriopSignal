import SwiftUI

struct RootView: View {
    @Environment(PostStore.self) private var store
    @Environment(SavedStore.self) private var saved
    @Environment(ReadStore.self) private var read
    @Environment(SpeechPlayer.self) private var speech
    @Environment(Preferences.self) private var prefs
    @Environment(Router.self) private var router
    @State private var showOnboarding = false

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
        tabs
            .sheet(isPresented: $showOnboarding) {
                OnboardingView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .task { await launch() }
            .onChange(of: read.ids.count) { _, _ in
                Task { await ReadStore.updateBadge(unread: read.unread(in: store.posts).count) }
            }
            .onChange(of: store.posts.count) { _, _ in
                Task { await ReadStore.updateBadge(unread: read.unread(in: store.posts).count) }
            }
    }

    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
            FeedView()
                .tabItem { Label("Feed", systemImage: "waveform.path.ecg") }
                .tag(Router.Tab.feed)
            GuidelinesView()
                .tabItem { Label("Guidelines", systemImage: "list.bullet.rectangle.portrait") }
                .tag(Router.Tab.guidelines)
            SavedView()
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(Router.Tab.saved)
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
        case "saved": router.selectedTab = .saved
        case "about", "more": router.selectedTab = .more
        case "guidelines": router.selectedTab = .guidelines
        default: break
        }
        #endif
        if !prefs.onboardingDone { showOnboarding = true }
        await store.loadInitial()
        read.prune(keeping: store.posts)
        await ReadStore.updateBadge(unread: read.unread(in: store.posts).count)
        #if DEBUG
        if let id = DebugLaunch.openPost { router.open(postID: id) }
        if DebugLaunch.openQuiz { router.openQuiz = true }
        if DebugLaunch.listen, let first = store.latestBatch.first {
            // Show the mini player for the screenshot, paused, without audio on the simulator.
            speech.play([first] + Array(store.latestBatch.dropFirst().prefix(2)))
            speech.toggle()
        }
        #endif
    }
}
