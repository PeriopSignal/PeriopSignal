import SwiftUI

/// "Does this valve need an operation, and which?" — the 2020 ACC/AHA recommendation tables as
/// prompted questions: answer what is known and the matching recommendations appear with their class;
/// the tool says which answer would change the picture.
struct ValveInterventionView: View {
    var onOpen: (URL) -> Void
    var onOpenCard: () -> Void

    @State private var lesion: VILesion = .as_
    @State private var answers: [String: String] = [:]

    private var result: VIResult { ValveIntervention.evaluate(lesion, answers: answers) }
    private var questions: [VIQuestion] { ValveIntervention.questions(for: lesion) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                picker
                resultCard
                questionList
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Valve intervention")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { withAnimation(.snappy) { answers = [:] } }.disabled(answers.isEmpty)
            }
        }
    }

    private var picker: some View {
        Menu {
            ForEach(VILesion.allCases) { l in
                Button { withAnimation(.snappy) { lesion = l; answers = [:] } } label: {
                    if l == lesion { Label(l.name, systemImage: "checkmark") } else { Text(l.name) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Lesion")
                    Text(lesion.name.titleCased).font(PS.serif(size: 19)).foregroundStyle(PS.fg)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg3)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
    }

    private var resultCard: some View {
        let r = result
        let top = r.matched.first { $0.group == .intervene }
        let tone: Color = {
            guard let top else { return answers.isEmpty ? PS.fg3 : (r.fallback == nil ? PS.accent2 : PS.green) }
            return color(top.cls)
        }()
        return VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: top.map { "\($0.cls.word) · class \($0.cls.rawValue)" } ?? (r.fallback == nil ? "Answer the questions" : "Surveillance"), color: tone)
            if let top {
                Text(top.recommendation).font(PS.serif(size: 22, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                Text(top.situation).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                if let n = top.note { noteRow(n) }
            } else if let f = r.fallback {
                Text(f).font(PS.sys(size: 14.5)).foregroundStyle(PS.fg).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(answers.isEmpty ? "Severity and Symptoms First" : "Nothing Settled Yet").font(PS.serif(size: 22, weight: .semibold)).foregroundStyle(PS.fg3)
                Text(answers.isEmpty ? "The recommendations appear as the answers come in; the dots mark the questions that would decide." : "Keep going: the marked questions decide.").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            }
            let rest = r.matched.filter { $0.id != top?.id }
            if !rest.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rest.enumerated()), id: \.element.id) { i, rule in
                        if i == 0 || rest[i - 1].group != rule.group {
                            Text(rule.group.rawValue.uppercased()).font(PS.mono(size: 9.5, weight: .semibold)).foregroundStyle(PS.fg3).kerning(0.6)
                                .padding(.top, i == 0 ? 4 : 10).padding(.bottom, 6)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(rule.cls.rawValue).font(PS.mono(size: 10.5, weight: .bold)).foregroundStyle(color(rule.cls))
                                .frame(width: 26, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.recommendation).font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                                Text(rule.situation + " · " + rule.level).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                                if let n = rule.note { Text(n).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true).padding(.top, 1) }
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            if !r.needed.isEmpty {
                let labels = r.needed.compactMap { id in questions.first { $0.id == id }?.label }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "arrow.turn.down.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.accent2)
                    Text((r.matched.isEmpty ? "Decides: " : "Could add: ") + labels.prefix(3).joined(separator: " · ") + (labels.count > 3 ? " · …" : ""))
                        .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: PS.cardRadius, topTrailingRadius: PS.cardRadius)
                .fill(tone.opacity(0.9)).frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
        .animation(.snappy, value: r)
    }

    private func noteRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle").font(PS.sys(size: 11)).foregroundStyle(PS.accent2)
            Text(text).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func color(_ c: VIClass) -> Color {
        switch c {
        case .one: return PS.green
        case .twoA: return PS.accent2
        case .twoB: return PS.fg2
        case .three: return PS.accent
        }
    }

    private var questionList: some View {
        let needed = Set(result.needed)
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "What is known").padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(questions.enumerated()), id: \.element.id) { i, q in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(needed.contains(q.id) ? PS.accent2 : Color.clear).frame(width: 6, height: 6)
                                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 3 }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q.label).font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                                if let h = q.hint { Text(h).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                        OptionRow(options: q.options, selected: answers[q.id]) { choice in
                            Haptics.light()
                            withAnimation(.snappy) { answers[q.id] = answers[q.id] == choice ? nil : choice }
                        }
                        .padding(.leading, 14)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if i < questions.count - 1 { Hairline().padding(.leading, 14) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            Text(lesion.severityNote).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            HStack(spacing: 10) {
                Button(action: onOpenCard) { Label("Full tables", systemImage: "tablecells") }.buttonStyle(GhostButtonStyle())
                if let url = URL(string: "https://doi.org/10.1161/CIR.0000000000000923") {
                    Button { onOpen(url) } label: { Label("Guideline ↗", systemImage: "doc.text") }.buttonStyle(GhostButtonStyle())
                }
            }
            Text("2020 ACC/AHA guideline for valvular heart disease (Otto et al, Circulation 2021;143:e72–e227), the current edition; the next is scheduled for 2027. Classes: 1 recommended, 2a reasonable, 2b may be considered, 3 no benefit or harm. Severe valve disease is evaluated by a multidisciplinary Heart Valve Team when intervention is considered (class 1); the full tables carry prosthesis anticoagulation, bridging and endocarditis prophylaxis.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One question's answers as a row of pills (wrapping when they do not fit); tap again to clear.
struct OptionRow: View {
    var options: [String]
    var selected: String?
    var choose: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.self) { o in
                let on = selected == o
                Button { choose(o) } label: {
                    Text(o)
                        .font(PS.sys(size: 12.5, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(on ? PS.accent.opacity(0.15) : PS.surface2, in: Capsule())
                        .overlay(Capsule().stroke(on ? PS.accent.opacity(0.7) : Color.clear, lineWidth: 1))
                        .foregroundStyle(on ? PS.accent : PS.fg2)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
