import SwiftUI

/// Measurements in, the ASE grade out: pick the lesion, enter what you measured, tick the signs.
struct ValveGraderView: View {
    var onOpen: (URL) -> Void
    var onOpenTable: () -> Void

    @State private var lesion: ValveLesion = .as_
    @State private var texts: [String: String] = [:]
    @State private var signs: Set<String> = []
    @FocusState private var focused: Bool

    private var input: ValveInput {
        var i = ValveInput()
        for (k, v) in texts {
            if let d = Double(v.replacingOccurrences(of: ",", with: ".")), d > 0 { i.numbers[k] = d }
        }
        i.signs = signs
        return i
    }
    private var reading: ValveReading { ValveGrading.read(lesion, input) }
    private var params: [ValveParam] { ValveGrading.params(for: lesion) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                picker
                result
                numbers
                if params.contains(where: \.isSign) { signsCard }
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Valve severity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { withAnimation(.snappy) { texts = [:]; signs = [] } }.disabled(texts.isEmpty && signs.isEmpty)
            }
        }
    }

    private var picker: some View {
        Picker("Lesion", selection: $lesion) {
            ForEach(ValveLesion.allCases) { l in Text(l.short).tag(l) }
        }
        .pickerStyle(.segmented)
        .onChange(of: lesion) { _, _ in texts = [:]; signs = [] }
    }

    private var result: some View {
        let r = reading
        let tone: Color = {
            switch r.overall {
            case .severe?: return PS.accent
            case .moderate?: return PS.accent2
            case .mild?: return PS.green
            case nil: return input.isEmpty ? PS.fg3 : PS.accent2
            }
        }()
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: lesion.name, color: tone)
            Text(r.headline).font(PS.serif(size: 24, weight: .semibold)).foregroundStyle(input.isEmpty ? PS.fg3 : PS.fg).fixedSize(horizontal: false, vertical: true)
            Text(r.explanation).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            if !r.lines.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(r.lines) { line in
                        HStack(spacing: 4) {
                            if let g = line.grade { Circle().fill(color(g)).frame(width: 6, height: 6) }
                            Text("\(line.label): \(line.text)").font(PS.sys(size: 11.5, weight: .medium)).foregroundStyle(PS.fg2)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(PS.surface2, in: Capsule())
                    }
                }
            }
            ForEach(Array(r.cautions.enumerated()), id: \.offset) { _, c in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(PS.sys(size: 11)).foregroundStyle(PS.accent)
                    Text(c).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
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

    private func color(_ g: ValveGrade) -> Color {
        switch g {
        case .mild: return PS.green
        case .moderate: return PS.accent2
        case .severe: return PS.accent
        }
    }

    private var numbers: some View {
        let list = params.filter { !$0.isSign }
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Measurements").padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                    let value = texts[p.id].flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
                    let grade = value.flatMap { p.grade($0) }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                                if let h = p.hint { Text(h).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                            }
                            Spacer(minLength: 6)
                            if let g = grade { Circle().fill(color(g)).frame(width: 8, height: 8) }
                            TextField("—", text: Binding(get: { texts[p.id] ?? "" }, set: { texts[p.id] = $0 }))
                                .keyboardType(.decimalPad)
                                .focused($focused)
                                .multilineTextAlignment(.trailing)
                                .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                                .foregroundStyle(PS.fg)
                                .padding(.horizontal, 6).padding(.vertical, 5)
                                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .frame(width: 78)
                            Text(p.unit).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 46, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    if i < list.count - 1 { Hairline().padding(.leading, 14) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private var signsCard: some View {
        let list = params.filter(\.isSign)
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Signs").padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                    let on = signs.contains(p.id)
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { if on { signs.remove(p.id) } else { signs.insert(p.id) } }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(PS.sys(size: 19)).foregroundStyle(on ? PS.accent : PS.fg3)
                                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.label).font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                if let h = p.hint { Text(h).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true) }
                            }
                            Spacer(minLength: 0)
                            if case .sign(let g) = p.kind, g != .moderate { Text(g.label).font(PS.mono(size: 9.5, weight: .semibold)).foregroundStyle(color(g)) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < list.count - 1 { Hairline().padding(.leading, 14) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            HStack(spacing: 10) {
                Button(action: onOpenTable) { Label("Grading tables", systemImage: "tablecells") }.buttonStyle(GhostButtonStyle())
                if let url = URL(string: "https://www.asecho.org/guideline/native-valvular-regurgitation-by-echo") {
                    Button { onOpen(url) } label: { Label("ASE ↗", systemImage: "doc.text") }.buttonStyle(GhostButtonStyle())
                }
            }
            Text("Source: \(lesion.source). The reading integrates the signs the way the documents describe and sets aside what you leave blank; it is a second pair of eyes on the numbers, not a report. Loading conditions in the operating room usually under-read regurgitation.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }
}
