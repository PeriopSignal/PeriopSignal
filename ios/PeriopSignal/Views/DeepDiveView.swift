import SwiftUI
import UIKit

struct DeepDiveView: View {
    @Environment(SavedStore.self) private var saved
    var post: Post
    var onOpenPaper: (URL) -> Void
    @State private var showShare = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Text(post.headline)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(PS.fg)
                    .fixedSize(horizontal: false, vertical: true)
                actions
                section(label: post.takeHomeIsAuthors ? "Take-home · the authors’ key points" : "Take-home") {
                    TakeHomeList(items: post.takeHome)
                }
                section(label: "Overview") {
                    MarkdownBlocks(text: post.deepDive)
                }
                limitations
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(post.topics, id: \.self) { TopicTag(topicID: $0) } }
                }
                Text("Overview written by Claude from the paper, abstract and society pages, then checked against the source link. Confirm details against the paper before changing practice. Added to the feed \(PSDate.display(post.addedAt, long: true)).")
                    .font(.system(size: 12))
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
            ToolbarItem(placement: .topBarTrailing) {
                Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share this post")
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [post.shareText])
                .presentationDetents([.medium, .large])
        }
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
                        Text(post.trialName).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(PS.fg2)
                    }
                    if !post.firstAuthor.isEmpty {
                        Text("\(post.firstAuthor) et al.").font(.system(size: 12)).foregroundStyle(PS.fg2)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let url = post.paperURL {
                Button { onOpenPaper(url) } label: {
                    Label("Open paper", systemImage: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .semibold))
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
                UIPasteboard.general.string = post.shareText
                Haptics.success()
                withAnimation { copied = true }
                Task { try? await Task.sleep(for: .seconds(2)); withAnimation { copied = false } }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(CardButtonStyle(prominent: false))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var limitations: some View {
        if !post.authorLimitations.isEmpty {
            section(label: "Limitations · stated by the authors") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(post.authorLimitations.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "minus").font(.system(size: 9, weight: .bold)).foregroundStyle(PS.fg3)
                            Text(item).font(.system(size: 14.5)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !post.authorBasis.isEmpty {
                        Text("Taken from the \(post.authorBasis).")
                            .font(.system(size: 12)).foregroundStyle(PS.fg3).padding(.top, 2)
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
                    .font(.system(size: 13.5))
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
                    inline(s).font(.system(size: 15.5)).foregroundStyle(PS.fg).lineSpacing(3)
                case .heading(let s):
                    inline(s).font(.system(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(PS.fg3)
                                inline(item).font(.system(size: 15)).foregroundStyle(PS.fg).lineSpacing(2)
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
    .environment(SavedStore())
    .preferredColorScheme(.dark)
}
