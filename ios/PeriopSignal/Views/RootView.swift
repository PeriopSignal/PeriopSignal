import SwiftUI

struct RootView: View {
    @Environment(PostStore.self) private var store
    @Environment(SavedStore.self) private var saved
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        #if DEBUG
        if DebugLaunch.screen == "widget" {
            WidgetPreviewScreen()
        } else {
            tabs($router)
        }
        #else
        tabs($router)
        #endif
    }

    private func tabs(_ router: Bindable<Router>) -> some View {
        TabView(selection: router.selectedTab) {
            FeedView()
                .tabItem { Label("Feed", systemImage: "waveform.path.ecg") }
                .tag(Router.Tab.feed)
            SavedView()
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(Router.Tab.saved)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(Router.Tab.about)
        }
        .task {
            #if DEBUG
            if let id = DebugLaunch.presave, !saved.contains(id) { saved.toggle(id) }
            if DebugLaunch.tab == "saved" { self.router.selectedTab = .saved }
            if DebugLaunch.tab == "about" { self.router.selectedTab = .about }
            #endif
            await store.loadInitial()
            #if DEBUG
            if let id = DebugLaunch.openPost { self.router.open(postID: id) }
            #endif
        }
    }
}
