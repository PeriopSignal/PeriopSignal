import SwiftUI

/// The thin strip under the masthead: the brand's ECG hairline and one line saying how many new
/// publications there are (they sit at the top of the feed already), with Listen on the right.
struct TodayHero: View {
    @Environment(PostStore.self) private var store
    @Environment(ReadStore.self) private var read
    @Environment(SpeechPlayer.self) private var speech
    var onOpen: (Post) -> Void
    @State private var drawn: CGFloat = 0

    private var unread: [Post] { read.unread(in: store.forYouPosts) }
    /// Posts that arrived since the previous visit (the site's "New" marker).
    private var newSinceLastVisit: [Post] { store.forYouPosts.filter { store.newIDs.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ECGLine(progress: drawn)
                .stroke(PS.accent.opacity(0.85), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                .frame(height: 20)
                .padding(.vertical, 10)
                .onAppear { withAnimation(.easeInOut(duration: 1.4)) { drawn = 1 } }
            HStack(alignment: .center, spacing: 8) {
                if !listenable.isEmpty { Circle().fill(PS.accent).frame(width: 7, height: 7) }
                Text(line)
                    .font(PS.sys(size: 14, weight: listenable.isEmpty ? .regular : .semibold))
                    .foregroundStyle(listenable.isEmpty ? PS.fg3 : PS.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                if !listenable.isEmpty {
                    Button {
                        Haptics.light()
                        speech.play(listenable)
                    } label: { Text("Listen · \(listenMinutes) min") }
                    .buttonStyle(TextButtonStyle(color: PS.accent, size: 13))
                }
            }
            .padding(.bottom, 10)
            .contextMenu {
                if !unread.isEmpty {
                    Button { withAnimation(.snappy) { read.markAllRead(unread) } } label: { Label("Mark all as read", systemImage: "checkmark.circle") }
                }
                if let first = listenable.first {
                    Button { onOpen(first) } label: { Label("Open the first one", systemImage: "text.book.closed") }
                }
            }
        }
        .animation(.snappy, value: unread.count)
    }

    /// What Listen plays: new since the last visit, else the unread backlog.
    private var listenable: [Post] {
        if !newSinceLastVisit.isEmpty { return newSinceLastVisit }
        return unread
    }

    private var line: String {
        if store.posts.isEmpty { return "Loading the feed…" }
        let n = newSinceLastVisit.count
        if n > 0 { return "\(n) new publication\(n == 1 ? "" : "s") since your last visit" }
        let u = unread.count
        if u > 0 { return "\(u) unread publication\(u == 1 ? "" : "s") at the top" }
        return "Nothing new since your last visit · next edition " + (store.latestBatchIsToday ? "tomorrow morning" : "in the morning")
    }

    /// Listening time: the recordings' real length where they exist, ~165 words a minute otherwise.
    private var listenMinutes: Int {
        let seconds = listenable.reduce(0.0) { total, post in
            if let a = post.audio { return total + Double(a.seconds) }
            let words = SpeechPlayer.segments(for: post).reduce(0) { $0 + $1.split(separator: " ").count }
            return total + Double(words) / 165 * 60
        }
        return max(1, Int((seconds / 60).rounded()))
    }
}
