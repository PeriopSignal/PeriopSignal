import WidgetKit
import SwiftUI

struct FeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeedEntry {
        FeedEntry(date: Date(), post: .sample, newThisWeek: 4, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (FeedEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context)); return
        }
        completion(entry(from: FeedLoader.loadCached()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeedEntry>) -> Void) {
        Task {
            var feed = FeedLoader.loadCached()
            if let result = try? await FeedLoader.fetch() {
                feed = result.0
                FeedLoader.saveCache(result.1)
            }
            let next = Calendar.current.date(byAdding: .hour, value: 3, to: Date()) ?? Date().addingTimeInterval(3 * 3600)
            completion(Timeline(entries: [entry(from: feed)], policy: .after(next)))
        }
    }

    private func entry(from feed: Feed?) -> FeedEntry {
        let posts = (feed?.posts ?? []).sorted { ($0.date, $0.addedAt) > ($1.date, $1.addedAt) }
        let weekAgo = PSDate.formatter.string(from: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())
        let recent = posts.filter { $0.date >= weekAgo }.count
        // Newest landmark paper; fall back to the newest post of any kind.
        let pick = posts.first(where: \.isLandmark) ?? posts.first
        return FeedEntry(date: Date(), post: pick, newThisWeek: recent, isPlaceholder: false)
    }
}

struct PeriopSignalWidget: Widget {
    let kind = "PeriopSignalWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FeedProvider()) { entry in
            PeriopSignalWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Latest landmark paper")
        .description("The newest practice-changing paper from Periop Signal.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct PeriopSignalWidgetBundle: WidgetBundle {
    var body: some Widget {
        PeriopSignalWidget()
    }
}

#Preview(as: .systemMedium) {
    PeriopSignalWidget()
} timeline: {
    FeedEntry(date: .now, post: .sample, newThisWeek: 4, isPlaceholder: false)
}
