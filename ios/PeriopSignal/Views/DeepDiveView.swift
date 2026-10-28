import SwiftUI
import UIKit

struct DeepDiveView: View {
    @Environment(PostStore.self) private var store
    @Environment(SavedStore.self) private var saved
    @Environment(ReadStore.self) private var read
    @Environment(SpeechPlayer.self) private var speech
    @Environment(Preferences.self) private var prefs
    var post: Post
    var onOpenPaper: (URL) -> Void
    @State private var shareItems: ShareItems?
    @State private var copied: String?

    struct ShareItems: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                VStack(alignment: .leading, spacing: 6) {
                    Text(post.headline)
                        .font(PS.sys(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(PS.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    if let title = post.title, !title.isEmpty, title.lowercased() != post.headline.lowercased() {
                        Text(title)
                            .font(PS.sys(size: 13).italic())
                            .foregroundStyle(PS.fg3)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                actions
                if let g = post.glance {
                    section(label: "At a glance") { GlanceStrip(glance: g) }
                }
                section(label: post.takeHomeIsAuthors ? "Take-home · the authors’ key points" : "Take-home") {
                    TakeHomeList(items: post.takeHome)
                }
                section(label: "Overview") {
                    MarkdownBlocks(text: post.deepDive)
                }
                limitations
                if post.quiz != nil && prefs.showDailyQuestion {
                    section(label: "Test yourself") {
                        QuizView(post: post)
                            .padding(12)
                            .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PS.line, lineWidth: 1))
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(post.topics, id: \.self) { TopicTag(topicID: $0) } }
                }
                related
                Text("Overview written by Claude from the paper, abstract and society pages, then checked against the source link. Confirm details against the paper before changing practice. Added to the feed \(PSDate.display(post.addedAt, long: true)).")
                    .font(PS.sys(size: 12))
                    .foregroundStyle(PS.fg3)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(PS.bg.ignoresSafeArea())
        .navigationTitle("Deep dive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                citeMenu
                shareMenu
            }
        }
        .sheet(item: $shareItems) { s in
            ShareSheet(items: s.items)
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .bottom) {
            if let copied {
                Text(copied)
                    .font(PS.sys(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(PS.surface3, in: Capsule())
                    .foregroundStyle(PS.fg)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear { read.markRead(post.id) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            JournalAvatar(post: post, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                MetaLine(post: post, long: true)
                HStack(spacing: 8) {
                    SignalBars(impact: post.impact)
                    if post.isLandmark { Pill(text: "Landmark", style: .landmark) }
                    if !post.trialName.isEmpty {
                        Text(post.trialName).font(PS.sys(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(PS.fg2)
                    }
                    if !post.authorLine.isEmpty {
                        Text(post.authorLine).font(PS.sys(size: 12)).foregroundStyle(PS.fg2).lineLimit(1)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var actions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let url = post.paperURL {
                    Button { onOpenPaper(url) } label: {
                        Label("Open paper", systemImage: "arrow.up.right.square")
                            .font(PS.sys(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(PS.accent, in: Capsule())
                            .foregroundStyle(PS.accentFg)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    Haptics.light(); saved.toggle(post.id)
                } label: {
                    Label(saved.contains(post.id) ? "Saved" : "Save", systemImage: saved.contains(post.id) ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(CardButtonStyle(prominent: false))
                Button {
                    Haptics.light()
                    if speech.current?.id == post.id, speech.isActive { speech.toggle() } else { speech.play(post) }
                } label: {
                    Label(speech.current?.id == post.id && speech.isPlaying ? "Pause" : "Listen", systemImage: speech.current?.id == post.id && speech.isPlaying ? "pause.fill" : "headphones")
                }
                .buttonStyle(CardButtonStyle(prominent: false))
                Button {
                    UIPasteboard.general.string = post.shareText
                    flash("Summary copied")
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(CardButtonStyle(prominent: false))
            }
        }
        .scrollClipDisabled()
    }

    private var shareMenu: some View {
        Menu {
            Button {
                if let image = ShareCardRenderer.render(post) {
                    shareItems = ShareItems(items: [image, post.siteLink])
                }
            } label: { Label("Share as image", systemImage: "photo") }
            Button { shareItems = ShareItems(items: [post.shareText]) } label: { Label("Share summary text", systemImage: "text.alignleft") }
            Button { shareItems = ShareItems(items: [post.siteLink]) } label: { Label("Share link", systemImage: "link") }
            if let url = post.paperURL {
                Button { shareItems = ShareItems(items: [url]) } label: { Label("Share paper link", systemImage: "doc.text") }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share this post")
    }

    private var citeMenu: some View {
        Menu {
            Button {
                UIPasteboard.general.string = post.amaCitation
                flash("Citation copied")
            } label: { Label(post.hasBibliographicRecord ? "Copy citation (AMA)" : "Copy web citation", systemImage: "quote.opening") }
            if let doi = post.doi {
                Button {
                    UIPasteboard.general.string = doi
                    flash("DOI copied")
                } label: { Label("Copy DOI", systemImage: "number") }
            }
            Button {
                UIPasteboard.general.string = post.bibtex
                flash("BibTeX copied")
            } label: { Label("Copy BibTeX", systemImage: "chevron.left.forwardslash.chevron.right") }
            Button {
                if let file = post.risFileURL() { shareItems = ShareItems(items: [file]) }
            } label: { Label("Export to reference manager (RIS)", systemImage: "books.vertical") }
        } label: {
            Image(systemName: "text.quote")
        }
        .accessibilityLabel("Cite this paper")
    }

    @ViewBuilder
    private var related: some View {
        let others = store.related(to: post)
        if !others.isEmpty {
            section(label: "Related in Periop Signal") {
                VStack(spacing: 0) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { i, other in
                        NavigationLink(value: other) {
                            HStack(alignment: .top, spacing: 10) {
                                JournalAvatar(post: other, size: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(other.headline)
                                        .font(PS.sys(size: 14, weight: .semibold, design: .serif))
                                        .foregroundStyle(PS.fg)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack(spacing: 5) {
                                        Text(other.journal).fontWeight(.semibold)
                                        Text("·").foregroundStyle(PS.fg3)
                                        Text(other.kind)
                                        Text("·").foregroundStyle(PS.fg3)
                                        Text(PSDate.display(other.date))
                                        if other.isLandmark { Pill(text: "Landmark", style: .landmark) }
                                    }
                                    .font(PS.sys(size: 11.5)).foregroundStyle(PS.fg2).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3).padding(.top, 4)
                            }
                            .padding(12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < others.count - 1 { Divider().overlay(PS.line).padding(.leading, 12) }
                    }
                }
                .background(PS.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PS.line, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private var limitations: some View {
        if !post.authorLimitations.isEmpty {
            section(label: "Limitations · stated by the authors") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(post.authorLimitations.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "minus").font(PS.sys(size: 9, weight: .bold)).foregroundStyle(PS.fg3)
                            Text(item).font(PS.sys(size: 14.5)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !post.authorBasis.isEmpty {
                        Text("Taken from the \(post.authorBasis).")
                            .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).padding(.top, 2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PS.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PS.line, lineWidth: 1))
            }
        } else if post.isResearch {
            section(label: "Limitations · stated by the authors") {
                let why = post.authorBasis == "abstract"
                    ? "the full text was not accessible; the abstract does not state them"
                    : "the source text was not accessible when this post was written"
                Text("Not captured: \(why). The paper’s discussion section lists them.")
                    .font(PS.sys(size: 13.5))
                    .foregroundStyle(PS.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func section<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: label)
            content()
        }
    }

    private func flash(_ message: String) {
        Haptics.success()
        withAnimation { copied = message }
        Task { try? await Task.sleep(for: .seconds(1.8)); withAnimation { copied = nil } }
    }
}

/// Renders the deep dive's markdown subset: **bold** inline, "- " bullet lines, "#" headings, blank-line paragraphs.
struct MarkdownBlocks: View {
    var text: String

    enum Block: Identifiable {
        case paragraph(String), bullets([String]), heading(String)
        var id: String {
            switch self {
            case .paragraph(let s): return "p:" + s
            case .bullets(let l): return "l:" + l.joined(separator: "|")
            case .heading(let s): return "h:" + s
            }
        }
    }

    static func parse(_ src: String) -> [Block] {
        var out: [Block] = [], para: [String] = [], list: [String] = []
        func flushP() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] } }
        func flushL() { if !list.isEmpty { out.append(.bullets(list)); list = [] } }
        for raw in src.components(separatedBy: "\n") {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { flushP(); flushL(); continue }
            if let r = l.range(of: #"^[-*•]\s+"#, options: .regularExpression) {
                flushP(); list.append(String(l[r.upperBound...])); continue
            }
            if let r = l.range(of: #"^#{1,4}\s+"#, options: .regularExpression) {
                flushP(); flushL(); out.append(.heading(String(l[r.upperBound...]))); continue
            }
            flushL(); para.append(l)
        }
        flushP(); flushL()
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let s):
                    inline(s).font(PS.sys(size: 15.5)).foregroundStyle(PS.fg).lineSpacing(3)
                case .heading(let s):
                    inline(s).font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(PS.fg3)
                                inline(item).font(PS.sys(size: 15)).foregroundStyle(PS.fg).lineSpacing(2)
                            }
                        }
                    }
                }
            }
        }
    }

    private func inline(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(a)
        }
        return Text(s)
    }
}

#Preview {
    NavigationStack {
        DeepDiveView(post: .sample, onOpenPaper: { _ in })
    }
    .environment(PostStore())
    .environment(SavedStore())
    .environment(ReadStore())
    .environment(QuizStore())
    .environment(SpeechPlayer())
    .environment(Preferences())
    .preferredColorScheme(.dark)
}
