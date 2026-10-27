import SwiftUI

/// The first thing on the feed: what arrived, what is unread, and the two ways to get through it
/// (read or listen). Shows the week's tally on Sunday and Monday.
struct TodayCard: View {
    @Environment(PostStore.self) private var store
    @Environment(ReadStore.self) private var read
    @Environment(QuizStore.self) private var quiz
    @Environment(SpeechPlayer.self) private var speech
    var onOpen: (Post) -> Void

    private var batch: [Post] { store.latestBatch }
    private var unread: [Post] { read.unread(in: store.forYouPosts) }
    private var isWeekend: Bool {
        let wd = Calendar.current.component(.weekday, from: Date())
        return wd == 1 || wd == 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(PS.sys(size: 11, weight: .bold, design: .monospaced))
                    .textCase(.uppercase).kerning(0.8)
                    .foregroundStyle(PS.accent)
                Spacer()
                if quiz.streak >= 2 {
                    Label("\(quiz.streak)-day streak", systemImage: "flame.fill")
                        .font(PS.sys(size: 11, weight: .semibold))
                        .foregroundStyle(PS.accent)
                }
            }
            if batch.isEmpty {
                Text(store.posts.isEmpty ? "Loading the feed…" : "No posts yet")
                    .font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
            } else if unread.isEmpty {
                caughtUp
            } else {
                Text(headline)
                    .font(PS.sys(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(PS.fg)
                    .fixedSize(horizontal: false, vertical: true)
                if let lead = unread.first {
                    Text(lead.headline)
                        .font(PS.sys(size: 13.5))
                        .foregroundStyle(PS.fg2)
                        .lineLimit(2)
                }
            }
            if isWeekend, store.weekSummary.posts > 0 {
                weekLine
            }
            if !batch.isEmpty {
                HStack(spacing: 8) {
                    if let first = unread.first {
                        Button { onOpen(first) } label: { Label("Start reading", systemImage: "book") }
                            .buttonStyle(CapsuleButtonStyle(prominent: true))
                    }
                    Button {
                        Haptics.light()
                        speech.play(unread.isEmpty ? batch : unread)
                    } label: { Label(unread.isEmpty ? "Listen again" : "Listen", systemImage: "headphones") }
                    .buttonStyle(CapsuleButtonStyle(prominent: unread.isEmpty))
                    Spacer(minLength: 0)
                    if !unread.isEmpty {
                        Button {
                            Haptics.success()
                            withAnimation { read.markAllRead(unread) }
                        } label: {
                            Text("Mark all read").font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .cardChrome(tint: PS.accent)
    }

    private var title: String {
        if store.latestBatchIsToday { return "Today" }
        if batch.isEmpty { return "Periop Signal" }
        return "Latest · " + PSDate.display(store.latestBatchDate)
    }

    private var headline: String {
        let n = unread.count
        let fresh = batch.filter { read.isUnread($0) }.count
        if fresh == n { return "\(n) new post\(n == 1 ? "" : "s") to read" }
        return "\(n) unread · \(fresh) new this morning"
    }

    private var caughtUp: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(PS.sys(size: 22)).foregroundStyle(PS.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("You’re all caught up").font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
                Text(store.latestBatchIsToday ? "Next update tomorrow morning." : "The next batch lands in the morning.")
                    .font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
            }
        }
    }

    private var weekLine: some View {
        let s = store.weekSummary
        let topics = s.topTopics.map { "\(Topics.name($0.0)) \($0.1)" }.joined(separator: ", ")
        return Text("This week: \(s.posts) post\(s.posts == 1 ? "" : "s")" + (s.landmark > 0 ? " · \(s.landmark) landmark" : "") + (topics.isEmpty ? "" : " · " + topics))
            .font(PS.sys(size: 12.5))
            .foregroundStyle(PS.fg2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
