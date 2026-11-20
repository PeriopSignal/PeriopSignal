import SwiftUI

/// The answer sheet: the question, a streamed answer, the sources it was given, and where it came from.
struct AskView: View {
    @Environment(PostStore.self) private var store
    @Environment(ReferenceStore.self) private var refs
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    var question: String
    /// Opens a cited post or quick reference (the presenter decides how).
    var onOpenPost: (Post) -> Void = { _ in }
    var onOpenRef: (QuickRef) -> Void = { _ in }
    #if DEBUG
    /// Screenshot runs only (-ps.ask.demo): fixed sources and a canned answer, no model called.
    var preset: AskPreset? = nil
    #endif

    @State private var answer = ""
    @State private var error: String?
    @State private var running = false
    @State private var backend: AskEngine.Backend?
    @State private var grounding = AskEngine.Grounding(posts: [], refs: [])
    /// False until the sources for this question are worked out, so "nothing matched" is not shown while they load.
    @State private var groundingReady = false
    @State private var task: Task<Void, Never>?
    @State private var followUp = ""
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Question")
                        Text(question)
                            .font(PS.serif(size: 21))
                            .foregroundStyle(PS.fg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if showsNothingMatched { nothingMatched }
                    answerBlock
                    if !grounding.isEmpty { sources }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 30)
                .modifier(DebugContentWidth())
            }
            .background(FeedBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = answer + "\n\n(Periop Signal · " + provenance + ")"
                        copied = true
                    } label: { Image(systemName: "doc.on.doc") }
                    .disabled(answer.isEmpty)
                }
            }
            .sensoryFeedback(.success, trigger: copied)
        }
        .task(id: question) { await run() }
        .onDisappear { task?.cancel() }
    }

    /// Nothing matched and an answer is on its way: say so above it (Ben, Nov 20), so a general-knowledge answer does not
    /// look like it came from the library.
    private var showsNothingMatched: Bool { groundingReady && grounding.isEmpty && backend != nil }

    private var nothingMatched: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg2)
            Text(AskEngine.nothingMatchedLine)
                .font(PS.sys(size: 14, weight: .medium))
                .foregroundStyle(PS.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var answerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Eyebrow(text: "Answer", color: PS.accent)
                if running { ProgressView().controlSize(.small) }
            }
            if let e = error {
                Text(e)
                    .font(PS.sys(size: 14.5))
                    .foregroundStyle(PS.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                if backend == .onDevice, refs.askEndpoint != nil {
                    Button { task?.cancel(); task = Task { await run(force: .cloud) } } label: { Text("Try Claude instead →") }
                        .buttonStyle(TextButtonStyle(color: PS.accent, size: 13.5))
                }
            } else if answer.isEmpty && running {
                Text(backend == .onDevice ? "Thinking on this phone…" : "Asking Claude…")
                    .font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
            } else {
                Text(rendered)
                    .font(PS.sys(size: 15.5))
                    .foregroundStyle(PS.fg)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(answer)
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Material it was given")
            VStack(spacing: 0) {
                ForEach(Array(grounding.sources.enumerated()), id: \.element.id) { i, s in
                    Button {
                        switch s.kind {
                        case .post(let id): if let p = store.posts.first(where: { $0.id == id }) { onOpenPost(p) }
                        case .quickref(let id): if let r = refs.quickref(id) { onOpenRef(r) }
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("[\(s.id)]").font(PS.mono(size: 11)).foregroundStyle(PS.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Text(s.subtitle).font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < grounding.sources.count - 1 { Hairline() }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 2)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            Text(provenance)
                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2)
            EvidenceNote(AskEngine.footerNote(matched: !grounding.isEmpty), title: "AI answer: it can be wrong")
        }
    }

    private var provenance: String { AskEngine.provenance(backend: backend, matched: !grounding.isEmpty) }

    private func run(force: AskEngine.Backend? = nil) async {
        answer = ""; error = nil
        #if DEBUG
        if let preset { applyPreset(preset); return }
        #endif
        let chosen = force ?? AskEngine.backend(endpoint: refs.askEndpoint, preferOnDevice: prefs.askOnDevice)
        backend = chosen
        // Cut to what this route can take, so the list below is exactly what the model is given (also when the route changes).
        grounding = AskEngine.grounding(for: question, posts: store.posts, refs: refs.quickrefs, backend: chosen)
        groundingReady = true
        guard let chosen else {
            error = "Answers need either Apple Intelligence (iPhone 15 Pro or newer on iOS 26) or the Periop Signal proxy, which is not set up yet."
            return
        }
        running = true
        defer { running = false }
        do {
            for try await delta in AskEngine.answer(question: question, grounding: grounding, backend: chosen, endpoint: refs.askEndpoint) {
                answer += delta
            }
            if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error = "No answer came back; try again." }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if DEBUG
extension AskView {
    /// Shows a canned answer with sources worked out from the preset's own posts and quick references, by the same
    /// grounding the app uses.
    fileprivate func applyPreset(_ p: AskPreset) {
        backend = p.backend
        grounding = AskEngine.grounding(for: question, posts: p.posts, refs: p.refs, backend: p.backend)
        groundingReady = true
        answer = p.answer
        running = false
    }
}
#endif

/// The row that offers an answer from search results.
struct AskRow: View {
    var query: String
    var available: Bool
    var action: () -> Void

    var body: some View {
        if available {
            Button(action: action) {
                QuietRow(icon: "sparkles", tint: PS.accent2, eyebrow: "Ask", text: "Answer “\(query)” with the feed and references as context", textSize: 14, lines: 2) {
                    Image(systemName: "arrow.right.circle.fill").font(PS.sys(size: 22)).foregroundStyle(PS.accent2)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
