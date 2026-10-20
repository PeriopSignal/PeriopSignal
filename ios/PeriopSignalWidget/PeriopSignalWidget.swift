import WidgetKit
import SwiftUI

struct FeedEntry: TimelineEntry {
    let date: Date
    let post: Post?
    let newThisWeek: Int
    let isPlaceholder: Bool
}

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

struct PeriopSignalWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: FeedEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemMedium: medium
            default: small
            }
        }
        .widgetURL(entry.post.map { URL(string: "periopsignal://post/\($0.id)") } ?? URL(string: "periopsignal://feed"))
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    private var post: Post? { entry.post }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LogoMark(size: 22, cornerRadius: 6)
                Text(post?.isLandmark == true ? "Landmark" : "Latest")
                    .font(.system(size: 10, weight: .bold, design: .rounded)).textCase(.uppercase).kerning(0.5)
                    .foregroundStyle(PS.coral)
                Spacer(minLength: 0)
            }
            Text(post?.headline ?? "No posts yet")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(5)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Text(post.map { "\($0.journal) · \(PSDate.display($0.date))" } ?? "")
                .font(.system(size: 10.5)).foregroundStyle(Color(hex: "A9B3C2")).lineLimit(1)
        }
        .containerBackground(for: .widget) { widgetBackground }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    LogoMark(size: 22, cornerRadius: 6)
                    Text(post?.isLandmark == true ? "Landmark paper" : "Latest paper")
                        .font(.system(size: 10, weight: .bold, design: .rounded)).textCase(.uppercase).kerning(0.5)
                        .foregroundStyle(PS.coral)
                    Spacer(minLength: 0)
                    if entry.newThisWeek > 0 {
                        Text("\(entry.newThisWeek) this week")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color(hex: "43D68E").opacity(0.18), in: Capsule())
                            .foregroundStyle(Color(hex: "43D68E"))
                    }
                }
                Text(post?.headline ?? "No posts yet")
                    .font(.system(size: 14.5, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                if let first = post?.takeHome.first {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "diamond.fill").font(.system(size: 5)).foregroundStyle(PS.coral)
                        Text(first).font(.system(size: 11.5)).foregroundStyle(Color(hex: "A9B3C2")).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Text(post.map { "\($0.journal) · \($0.kind) · \(PSDate.display($0.date))" } ?? "")
                    .font(.system(size: 10.5)).foregroundStyle(Color(hex: "717D8F")).lineLimit(1)
            }
        }
        .containerBackground(for: .widget) { widgetBackground }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                Text(post?.isLandmark == true ? "Landmark" : "Periop Signal").font(.system(size: 11, weight: .semibold))
            }
            Text(post?.headline ?? "No posts yet").font(.system(size: 12)).lineLimit(2)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var inline: some View {
        Text(post.map { "\($0.journal): \($0.headline)" } ?? "Periop Signal")
            .containerBackground(for: .widget) { Color.clear }
    }

    private var widgetBackground: some View {
        ZStack {
            Color(hex: "111722")
            LinearGradient(colors: [PS.coral.opacity(post?.isLandmark == true ? 0.16 : 0.06), .clear], startPoint: .topLeading, endPoint: .bottom)
        }
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
