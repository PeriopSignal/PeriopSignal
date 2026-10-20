import SwiftUI
import WidgetKit

#if DEBUG
/// Launch arguments used by the CI screenshot run (simulator only):
///   -ps.openPost <id>     open a deep dive once the feed has loaded
///   -ps.tab saved|about   start on a tab
///   -ps.presave <id>      bookmark a post before the first frame
///   -ps.screen widget     show the widget preview screen instead of the app
///   -ps.appearance light  (read by @AppStorage directly)
enum DebugLaunch {
    static var openPost: String? { UserDefaults.standard.string(forKey: "ps.openPost") }
    static var tab: String? { UserDefaults.standard.string(forKey: "ps.tab") }
    static var presave: String? { UserDefaults.standard.string(forKey: "ps.presave") }
    static var screen: String? { UserDefaults.standard.string(forKey: "ps.screen") }
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
