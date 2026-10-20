import SwiftUI

struct RootView: View {
    @Environment(PostStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
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
        .task { await store.loadInitial() }
    }
}
