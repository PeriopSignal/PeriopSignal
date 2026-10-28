import SwiftUI

/// The top of the feed: the brand's ECG hairline, one sentence about what arrived, and the two
/// ways through it (read or listen). No box: this is the page's headline, not a widget.
struct TodayHero: View {
    @Environment(PostStore.self) private var store
    @Environment(ReadStore.self) private var read
    @Environment(QuizStore.self) private var quiz
    @Environment(SpeechPlayer.self) private var speech
    @Environment(Preferences.self) private var prefs
    var onOpen: (Post) -> Void
    @State private var drawn: CGFloat = 0

    private var batch: [Post] { store.latestBatch }
    private var unread: [Post] { read.unread(in: store.forYouPosts) }
    private var fresh: Int { batch.filter { read.isUnread($0) }.count }
    private var isWeekend: Bool {
        let wd = Calendar.current.component(.weekday, from: Date())
        return wd == 1 || wd == 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ECGLine(progress: drawn)
                .stroke(PS.accent.opacity(0.9), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(height: 24)
                .padding(.bottom, 14)
                .onAppear { withAnimation(.easeInOut(duration: 1.4)) { drawn = 1 } }
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: eyebrow, color: PS.accent)
                Spacer()
                if quiz.streak >= 2 {
                    Label("\(quiz.streak)-day streak", systemImage: "flame.fill")
                        .font(PS.sys(size: 11, weight: .semibold))
                        .foregroundStyle(PS.fg3)
                }
            }
            Text(sentence)
                .font(PS.serif(size: 27))
                .foregroundStyle(PS.fg)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .contentTransition(.opacity)
            if let lead = unread.first {
                Text(lead.headline)
                    .font(PS.sys(size: 14))
                    .foregroundStyle(PS.fg2)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .padding(.top, 10)
            } else if !batch.isEmpty {
                Text(store.latestBatchIsToday ? "Next edition tomorrow morning." : "The next edition lands in the morning.")
                    .font(PS.sys(size: 14))
                    .foregroundStyle(PS.fg3)
                    .padding(.top, 8)
            }
            if isWeekend, store.weekSummary.posts > 0 {
                weekLine.padding(.top, 8)
            }
            if !batch.isEmpty {
                HStack(spacing: 10) {
                    if let first = unread.first {
                        Button { onOpen(first) } label: { Label("Start reading", systemImage: "play.fill") }
                            .buttonStyle(CapsuleButtonStyle(prominent: true))
                    }
                    Button {
                        Haptics.light()
                        speech.play(unread.isEmpty ? batch : unread)
                    } label: {
                        Text(unread.isEmpty ? "Listen again" : "Listen · \(listenMinutes) min")
                    }
                    .buttonStyle(GhostButtonStyle())
                    Spacer(minLength: 0)
                    if !unread.isEmpty {
                        Button {
                            Haptics.success()
                            withAnimation(.snappy) { read.markAllRead(unread) }
                        } label: { Text("Mark all read") }
                        .buttonStyle(TextButtonStyle(color: PS.fg3, size: 12.5))
                    }
                }
                .padding(.top, 16)
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 18)
        .animation(.snappy, value: unread.count)
    }

    private var eyebrow: String {
        var s = store.latestBatchIsToday ? "Today" : (batch.isEmpty ? "Periop Signal" : "Latest · " + PSDate.display(store.latestBatchDate))
        if !unread.isEmpty { s += " · \(unread.count) unread" }
        return s
    }

    private var sentence: String {
        if store.posts.isEmpty { return "Loading the feed…" }
        let n = unread.count
        if n == 0 {
            return store.latestBatchIsToday && !batch.isEmpty ? "You’re all caught up." : "Nothing new this morning."
        }
        let waiting = n - fresh
        if fresh == 0 { return "\(Self.words(n).capitalized) \(n == 1 ? "paper" : "papers") waiting from the last few days." }
        if waiting == 0 { return "\(Self.words(fresh).capitalized) new this morning." }
        return "\(Self.words(fresh).capitalized) new this morning, \(Self.words(waiting)) still waiting."
    }

    /// "one" … "ten", digits above that.
    static func words(_ n: Int) -> String {
        let w = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return n < w.count ? w[n] : String(n)
    }

    /// Rough listening time at ~165 words a minute.
    private var listenMinutes: Int {
        let words = unread.reduce(0) { $0 + SpeechPlayer.segments(for: $1).reduce(0) { $0 + $1.split(separator: " ").count } }
        return max(1, Int((Double(words) / 165).rounded()))
    }

    private var weekLine: some View {
        let s = store.weekSummary
        let topics = s.topTopics.map { "\(Topics.name($0.0)) \($0.1)" }.joined(separator: ", ")
        return Text("This week: \(s.posts) post\(s.posts == 1 ? "" : "s")" + (s.landmark > 0 ? " · \(s.landmark) landmark" : "") + (topics.isEmpty ? "" : " · " + topics))
            .font(PS.sys(size: 12.5))
            .foregroundStyle(PS.fg3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
