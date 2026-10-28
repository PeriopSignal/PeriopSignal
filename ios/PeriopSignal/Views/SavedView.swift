import SwiftUI

struct SavedView: View {
    @Environment(PostStore.self) private var store
    @Environment(SavedStore.self) private var saved
    @Environment(SpeechPlayer.self) private var speech
    @State private var path = NavigationPath()
    @State private var webLink: WebLink?

    private var posts: [Post] { store.posts.filter { saved.contains($0.id) } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if posts.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing saved yet", systemImage: "bookmark")
                        } description: {
                            Text("Tap the bookmark on any post. Saved posts sync through iCloud to your other devices.")
                        }
                        .padding(.top, 60)
                    } else {
                        HStack {
                            Eyebrow(text: "\(posts.count) saved · synced with iCloud")
                            Spacer()
                            Button { speech.play(posts) } label: { Label("Listen to all", systemImage: "headphones") }
                                .buttonStyle(GhostButtonStyle())
                        }
                        .padding(.bottom, 4)
                        ForEach(posts) { post in
                            PostCard(post: post, onOpen: { path.append(post) }, onOpenPaper: { webLink = WebLink(url: $0) })
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(FeedBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Post.self) { post in
                DeepDiveView(post: post, onOpenPaper: { webLink = WebLink(url: $0) })
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .listenBar()
        }
        .fullScreenCover(item: $webLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
    }
}
