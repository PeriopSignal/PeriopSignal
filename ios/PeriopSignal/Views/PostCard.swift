import SwiftUI
import UIKit

struct PostCard: View {
    @Environment(SavedStore.self) private var saved
    @Environment(ReadStore.self) private var read
    @Environment(SpeechPlayer.self) private var speech
    var post: Post
    var isNew: Bool = false
    var onOpen: () -> Void
    var onOpenPaper: (URL) -> Void
    @State private var shareItems: DeepDiveView.ShareItems?

    private var isUnread: Bool { read.isUnread(post) }

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
                                .font(PS.sys(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(PS.fg2)
                        }
                        if isUnread && !isNew { UnreadDot() }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.light()
                    saved.toggle(post.id)
                } label: {
                    Image(systemName: saved.contains(post.id) ? "bookmark.fill" : "bookmark")
                        .font(PS.sys(size: 16, weight: .medium))
                        .foregroundStyle(saved.contains(post.id) ? PS.accent : PS.fg3)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(saved.contains(post.id) ? "Remove from saved" : "Save post")
            }

            Button(action: onOpen) {
                Text(post.headline)
                    .font(PS.sys(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(PS.fg)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(post.summary)
                .font(PS.sys(size: 14.5))
                .foregroundStyle(PS.fg2)
                .fixedSize(horizontal: false, vertical: true)

            if let g = post.glance {
                GlanceStrip(glance: g, compact: true)
            }

            TakeHomeList(items: post.takeHome)

            // The buttons keep their natural width so their labels never wrap; the topic tags scroll
            // in whatever width is left.
            HStack(alignment: .center, spacing: 8) {
                topicsRow
                Spacer(minLength: 0)
                actionButtons
            }
        }
        .padding(14)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(post.isLandmark ? PS.accent.opacity(0.75) : PS.line, lineWidth: post.isLandmark ? 1.5 : 1)
        )
        .shadow(color: post.isLandmark ? PS.accent.opacity(0.18) : .black.opacity(0.25), radius: post.isLandmark ? 14 : 10, y: 6)
        .contextMenu { contextMenu }
        .sheet(item: $shareItems) { s in
            ShareSheet(items: s.items).presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(action: onOpen) { Label("Deep dive", systemImage: "text.book.closed") }
        if let url = post.paperURL {
            Button { onOpenPaper(url) } label: { Label("Open paper", systemImage: "arrow.up.right.square") }
        }
        Button { speech.play(post) } label: { Label("Listen", systemImage: "headphones") }
        Divider()
        Button {
            if let image = ShareCardRenderer.render(post) { shareItems = .init(items: [image, post.siteLink]) }
        } label: { Label("Share as image", systemImage: "photo") }
        Button { shareItems = .init(items: [post.shareText]) } label: { Label("Share summary text", systemImage: "text.alignleft") }
        Button {
            UIPasteboard.general.string = post.amaCitation
            Haptics.success()
        } label: { Label("Copy citation", systemImage: "quote.opening") }
        Divider()
        Button { saved.toggle(post.id) } label: {
            Label(saved.contains(post.id) ? "Remove from saved" : "Save", systemImage: saved.contains(post.id) ? "bookmark.slash" : "bookmark")
        }
        if read.isRead(post.id) {
            Button { read.markUnread(post.id) } label: { Label("Mark as unread", systemImage: "circle") }
        } else {
            Button { read.markRead(post.id) } label: { Label("Mark as read", systemImage: "checkmark.circle") }
        }
    }

    private var topicsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(post.topics, id: \.self) { TopicTag(topicID: $0) }
            }
        }
        .layoutPriority(0)
    }

    private var actionButtons: some View {
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
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
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
            .font(PS.sys(size: 12.5, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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
    .environment(ReadStore())
    .environment(SpeechPlayer())
    .preferredColorScheme(.dark)
}
