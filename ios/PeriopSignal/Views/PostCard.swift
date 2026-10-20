import SwiftUI

struct PostCard: View {
    @Environment(SavedStore.self) private var saved
    var post: Post
    var isNew: Bool = false
    var onOpen: () -> Void
    var onOpenPaper: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                JournalAvatar(post: post)
                VStack(alignment: .leading, spacing: 4) {
                    MetaLine(post: post, isNew: isNew)
                    HStack(spacing: 8) {
                        SignalBars(impact: post.impact)
                        if post.isLandmark { Pill(text: "Landmark", style: .landmark) }
                        if !post.trialName.isEmpty {
                            Text(post.trialName)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(PS.fg2)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.light()
                    saved.toggle(post.id)
                } label: {
                    Image(systemName: saved.contains(post.id) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(saved.contains(post.id) ? PS.accent : PS.fg3)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(saved.contains(post.id) ? "Remove from saved" : "Save post")
            }

            Button(action: onOpen) {
                Text(post.headline)
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(PS.fg)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(post.summary)
                .font(.system(size: 14.5))
                .foregroundStyle(PS.fg2)
                .fixedSize(horizontal: false, vertical: true)

            TakeHomeList(items: post.takeHome)

            HStack(alignment: .center) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(post.topics, id: \.self) { TopicTag(topicID: $0) }
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    if let url = post.paperURL {
                        Button { onOpenPaper(url) } label: {
                            Label("Paper", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(CardButtonStyle(prominent: false))
                    }
                    Button(action: onOpen) {
                        Label("Deep dive", systemImage: "text.book.closed")
                    }
                    .buttonStyle(CardButtonStyle(prominent: true))
                }
            }
        }
        .padding(14)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(post.isLandmark ? PS.accent.opacity(0.75) : PS.line, lineWidth: post.isLandmark ? 1.5 : 1)
        )
        .shadow(color: post.isLandmark ? PS.accent.opacity(0.18) : .black.opacity(0.25), radius: post.isLandmark ? 14 : 10, y: 6)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(PS.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [PS.accent.opacity(post.isLandmark ? 0.10 : 0), .clear], startPoint: .topLeading, endPoint: .bottom))
            )
    }
}

struct CardButtonStyle: ButtonStyle {
    var prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(prominent ? PS.accent2.opacity(0.14) : PS.surface2, in: Capsule())
            .foregroundStyle(prominent ? PS.accent2 : PS.fg2)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

#Preview {
    ScrollView {
        PostCard(post: .sample, isNew: true, onOpen: {}, onOpenPaper: { _ in })
            .padding()
    }
    .background(PS.bg)
    .environment(SavedStore())
    .preferredColorScheme(.dark)
}
