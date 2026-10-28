import SwiftUI

/// The question of the day on the feed: a quiet row that opens the question sheet, and shows the
/// result once answered.
struct DailyQuestionCard: View {
    @Environment(PostStore.self) private var store
    @Environment(QuizStore.self) private var quiz
    @Environment(Preferences.self) private var prefs
    var onOpenSheet: (Post) -> Void

    var body: some View {
        if prefs.showDailyQuestion, let post = quiz.todaysQuestion(from: store.posts), let q = post.quiz {
            let answer = quiz.answer(for: post.id)
            Button { onOpenSheet(post) } label: {
                QuietRow(icon: answer == nil ? "questionmark" : (answer!.correct ? "checkmark" : "xmark"),
                         tint: answer == nil ? PS.accent2 : (answer!.correct ? PS.green : PS.accent),
                         eyebrow: eyebrow(answer: answer, post: post),
                         text: q.question, textSize: 14.5, lines: 4) {
                    Image(systemName: "chevron.right").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func eyebrow(answer: QuizStore.Answer?, post: Post) -> String {
        guard let answer else { return "Question of the day · " + post.jshort }
        return (answer.correct ? "Correct" : "Missed") + " · see the explanation"
    }
}

/// One question with four options; records the answer and shows the explanation.
struct QuizView: View {
    @Environment(QuizStore.self) private var quiz
    var post: Post
    var showPostLink = false
    var onOpenPost: ((Post) -> Void)? = nil
    @State private var chosen: Int?

    static let letters = ["A", "B", "C", "D"]
    private var q: Quiz { post.quiz ?? Quiz(question: "", options: [], answer: 0, explanation: "") }
    private var revealed: Bool { chosen != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(q.question)
                .font(PS.sys(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(PS.fg)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                    Button {
                        guard chosen == nil else { return }
                        chosen = i
                        let correct = i == q.answer
                        if correct { Haptics.success() } else { Haptics.light() }
                        quiz.record(postID: post.id, chosen: i, correct: correct)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Self.letters[i])
                                .font(PS.sys(size: 12, weight: .bold, design: .monospaced))
                                .frame(width: 22, height: 22)
                                .background(letterBackground(i), in: Circle())
                                .foregroundStyle(letterForeground(i))
                            Text(option)
                                .font(PS.sys(size: 14.5, weight: revealed && i == q.answer ? .semibold : .regular))
                                .foregroundStyle(PS.fg)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if revealed && i == q.answer {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(PS.green)
                            } else if revealed && i == chosen {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(PS.accent)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(rowBackground(i), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(rowStroke(i), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(revealed)
                    .accessibilityAddTraits(revealed && i == q.answer ? .isSelected : [])
                }
            }
            if revealed {
                VStack(alignment: .leading, spacing: 8) {
                    Text(chosen == q.answer ? "Correct" : "Not quite — the answer is \(Self.letters[q.answer])")
                        .font(PS.sys(size: 14, weight: .bold))
                        .foregroundStyle(chosen == q.answer ? PS.green : PS.accent)
                    Text(q.explanation)
                        .font(PS.sys(size: 14.5))
                        .foregroundStyle(PS.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    if showPostLink, let onOpenPost {
                        Button { onOpenPost(post) } label: {
                            Label("Read the post", systemImage: "text.book.closed")
                        }
                        .buttonStyle(CapsuleButtonStyle(prominent: true))
                        .padding(.top, 2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: chosen)
        .onAppear { chosen = quiz.answer(for: post.id)?.chosen }
    }

    private func rowBackground(_ i: Int) -> Color {
        guard revealed else { return PS.surface }
        if i == q.answer { return PS.green.opacity(0.14) }
        if i == chosen { return PS.accent.opacity(0.12) }
        return PS.surface
    }
    private func rowStroke(_ i: Int) -> Color {
        guard revealed else { return PS.line2 }
        if i == q.answer { return PS.green.opacity(0.7) }
        if i == chosen { return PS.accent.opacity(0.6) }
        return PS.line
    }
    private func letterBackground(_ i: Int) -> Color {
        guard revealed else { return PS.surface3 }
        if i == q.answer { return PS.green }
        if i == chosen { return PS.accent }
        return PS.surface3
    }
    private func letterForeground(_ i: Int) -> Color {
        guard revealed, i == q.answer || i == chosen else { return PS.fg2 }
        return i == q.answer ? Color.black.opacity(0.8) : PS.accentFg
    }
}

/// The question of the day as a sheet from the feed.
struct QuizSheet: View {
    @Environment(QuizStore.self) private var quiz
    @Environment(\.dismiss) private var dismiss
    var post: Post
    var onOpenPost: (Post) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        JournalAvatar(post: post, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("From " + post.journal + " · " + PSDate.display(post.date, long: true))
                                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2)
                            Text(post.headline).font(PS.sys(size: 12.5, weight: .medium)).foregroundStyle(PS.fg3).lineLimit(2)
                        }
                    }
                    QuizView(post: post, showPostLink: true, onOpenPost: { p in dismiss(); onOpenPost(p) })
                    stats
                }
                .padding(16)
            }
            .background(PS.bg.ignoresSafeArea())
            .navigationTitle("Question of the day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var stats: some View {
        HStack(spacing: 14) {
            stat("\(quiz.streak)", quiz.streak == 1 ? "day streak" : "day streak")
            stat("\(quiz.correctCount)/\(quiz.answeredCount)", "correct")
            Spacer()
        }
        .padding(.top, 4)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(PS.sys(size: 18, weight: .bold, design: .rounded)).foregroundStyle(PS.fg)
            Text(label).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
        }
    }
}
