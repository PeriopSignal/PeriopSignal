import SwiftUI
import UIKit

struct PostCard: View {
    @Environment(SavedStore.self) private var saved
    @Environment(ReadStore.self) private var read
    @Environment(SpeechPlayer.self) private var speech
    @Environment(\.colorScheme) private var scheme
    var post: Post
    var isNew: Bool = false
    var onOpen: () -> Void
    var onOpenPaper: (URL) -> Void
    @State private var shareItems: DeepDiveView.ShareItems?

    private var isUnread: Bool { read.isUnread(post) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                MetaLine(post: post, isNew: isNew)
                if isUnread && !isNew { UnreadDot() }
                Spacer(minLength: 6)
                if post.isLandmark {
                    Eyebrow(text: "Landmark", color: PS.accent, size: 10)
                }
                Button {
                    Haptics.light()
                    saved.toggle(post.id)
                } label: {
                    Image(systemName: saved.contains(post.id) ? "bookmark.fill" : "bookmark")
                        .font(PS.sys(size: 14, weight: .medium))
                        .foregroundStyle(saved.contains(post.id) ? PS.accent : PS.fg3)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(saved.contains(post.id) ? "Remove from saved" : "Save post")
                .padding(.trailing, -8)
            }

            Button(action: onOpen) {
                Text(post.headline)
                    .font(PS.serif(size: 20.5))
                    .foregroundStyle(PS.fg)
                    .lineSpacing(1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(post.summary)
                .font(PS.sys(size: 14.5))
                .foregroundStyle(PS.fg2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            TakeHomeList(items: post.takeHome, size: 14)
                .padding(.top, 2)

            if let g = post.glance {
                GlanceStrip(glance: g, compact: true)
                    .padding(.top, 2)
            }

            // Topics and actions share one row when both fit; otherwise the actions take their own line.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    topicLabels.fixedSize()
                    Spacer(minLength: 10)
                    actions
                }
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView(.horizontal, showsIndicators: false) { topicLabels }
                    HStack { Spacer(minLength: 0); actions }
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).fill(PS.surface))
        .overlay(alignment: .top) {
            if post.isLandmark {
                LinearGradient(colors: [PS.accent, PS.accent.opacity(0.15)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 3)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: PS.cardRadius, topTrailingRadius: PS.cardRadius))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.05), radius: scheme == .dark ? 10 : 6, y: 4)
        .contextMenu { contextMenu }
        .sheet(item: $shareItems) { s in
            ShareSheet(items: s.items).presentationDetents([.medium, .large])
        }
    }

    private var topicLabels: some View {
        HStack(spacing: 12) {
            ForEach(post.topics, id: \.self) { id in
                let t = Topics.info(id)
                HStack(spacing: 5) {
                    Circle().fill(t.fg).frame(width: 7, height: 7)
                    Eyebrow(text: t.name, color: PS.fg3, size: 10)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 16) {
            if let url = post.paperURL {
                Button { onOpenPaper(url) } label: { Text("Paper ↗") }
                    .buttonStyle(TextButtonStyle(color: PS.fg2))
            }
            Button(action: onOpen) { Text("Deep dive →") }
                .buttonStyle(TextButtonStyle(color: PS.accent))
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
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
}

/// Capsule buttons used in the deep dive's action row.
struct CardButtonStyle: ButtonStyle {
    var prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PS.sys(size: 13, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(prominent ? PS.accent : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(prominent ? .clear : PS.line2, lineWidth: 1))
            .foregroundStyle(prominent ? PS.accentFg : PS.fg)
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
