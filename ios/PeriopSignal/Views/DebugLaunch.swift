import SwiftUI
import WidgetKit

#if DEBUG
/// Launch arguments used by the CI screenshot run (simulator only):
///   -ps.openPost <id>       open a deep dive once the feed has loaded
///   -ps.tab saved|more|reference   start on a tab
///   -ps.ref score:rcri | quickref:<id> | peds   open a calculator or quick reference on the Reference tab
///   -ps.presave <id>        bookmark a post before the first frame
///   -ps.topics a,b          follow these topics (turns on "For you")
///   -ps.openQuiz 1          open the question of the day
///   -ps.listen 1            show the mini player (paused)
///   -ps.screen widget       show the widget preview screen instead of the app
///   -ps.screen cards        show the two posts with the most topic tags as cards (button-row layout check)
///   -ps.screen sharecard    render the share image for the newest landmark post
///   -ps.showWelcome 1       open the welcome screen (topics and alerts)
///   -ps.forceAppearance light / -ps.forceLaunchCount N
enum DebugLaunch {
    static var openPost: String? { UserDefaults.standard.string(forKey: "ps.openPost") }
    static var tab: String? { UserDefaults.standard.string(forKey: "ps.tab") }
    static var presave: String? { UserDefaults.standard.string(forKey: "ps.presave") }
    static var screen: String? { UserDefaults.standard.string(forKey: "ps.screen") }
    static var openQuiz: Bool { UserDefaults.standard.bool(forKey: "ps.openQuiz") }
    static var listen: Bool { UserDefaults.standard.bool(forKey: "ps.listen") }
    static var showWelcome: Bool { UserDefaults.standard.bool(forKey: "ps.showWelcome") }
    static var refRoute: RefRoute? {
        guard let s = UserDefaults.standard.string(forKey: "ps.ref"), !s.isEmpty else { return nil }
        if s == "peds" { return .peds }
        let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "score": return .score(parts[1])
        case "quickref": return .quickref(parts[1])
        default: return nil
        }
    }
    static var topics: [String]? {
        guard let s = UserDefaults.standard.string(forKey: "ps.topics.debug"), !s.isEmpty else { return nil }
        return s.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

/// Renders the two posts with the most topic tags as feed cards, so the CI screenshot shows the
/// tags-plus-buttons row at its most crowded.
struct CardPreviewScreen: View {
    @Environment(PostStore.self) private var store
    var body: some View {
        let posts = Array(store.posts.sorted { $0.topics.count > $1.topics.count }.prefix(2))
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(posts.isEmpty ? [Post.sample] : posts) { post in
                    PostCard(post: post, onOpen: {}, onOpenPaper: { _ in })
                }
            }
            .padding(16)
        }
        .background(PS.bg.ignoresSafeArea())
        .task { await store.loadInitial() }
    }
}

/// Shows the share image exactly as it is rendered (the newest landmark post).
struct ShareCardPreviewScreen: View {
    @Environment(PostStore.self) private var store
    @State private var image: UIImage?
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Share image").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(PS.fg)
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 16)
                    Text("\(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale)) px")
                        .font(.caption).foregroundStyle(PS.fg3)
                } else {
                    ProgressView()
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(PS.bg.ignoresSafeArea())
        .task {
            await store.loadInitial()
            let post = store.newestLandmark ?? store.newestPost ?? .sample
            image = ShareCardRenderer.render(post)
        }
    }
}

/// Renders the widget families at their real sizes so the CI run can screenshot them.
struct WidgetPreviewScreen: View {
    @Environment(PostStore.self) private var store
    var body: some View {
        let post = store.newestLandmark ?? store.newestPost ?? .sample
        let entry = FeedEntry(date: Date(), post: post, newThisWeek: store.publishedThisWeek, isPlaceholder: false)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Widget preview").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(PS.fg)
                Text("Small").font(.caption).foregroundStyle(PS.fg3)
                PeriopSignalWidgetEntryView(entry: entry, family: .systemSmall)
                    .padding(16)
                    .frame(width: 170, height: 170)
                    .background(Color(hex: "111722"), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                Text("Medium").font(.caption).foregroundStyle(PS.fg3)
                PeriopSignalWidgetEntryView(entry: entry, family: .systemMedium)
                    .padding(16)
                    .frame(width: 364, height: 170)
                    .background(Color(hex: "111722"), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                Text("Lock screen").font(.caption).foregroundStyle(PS.fg3)
                PeriopSignalWidgetEntryView(entry: entry, family: .accessoryRectangular)
                    .padding(8)
                    .frame(width: 172, height: 76)
                    .foregroundStyle(.white)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PS.bg.ignoresSafeArea())
        .task { await store.loadInitial() }
    }
}
#endif
