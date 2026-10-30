import SwiftUI

/// The valve workflows: pick the lesion, answer one step at a time ("Cannot obtain" moves on), and the grade
/// appears as soon as the guideline's criteria settle it. Every answer stays on the path and can be changed.
struct ValveFlowPanel: View {
    var onOpen: (URL) -> Void

    @Environment(ReferenceStore.self) private var refs
    @AppStorage("valveFlow.tee") private var tee = LaunchSeed.bool("ps.valve.tee")
    @State private var flowId = LaunchSeed.string("ps.valve.flow")
    @State private var answers: [String: FlowAnswer] = Self.seededAnswers()
    @State private var entry = ""
    @FocusState private var entryFocused: Bool

    private var data: ValveFlowData? { refs.bundle?.valveFlows }
    private var flows: [ValveFlowDef] { data?.usable ?? [] }
    private var flow: ValveFlowDef? { flows.first { $0.id == flowId } ?? flows.first }

    /// DEBUG screenshots: -ps.valve.flow mr -ps.valve.answers "vc=0.8,jet=eccentric,pisa=x" (x: cannot obtain).
    private static func seededAnswers() -> [String: FlowAnswer] {
        var out: [String: FlowAnswer] = [:]
        for pair in LaunchSeed.list("ps.valve.answers") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            if kv[1] == "x" { out[kv[0]] = .cannot } else if let v = Double(kv[1]) { out[kv[0]] = .number(v) } else { out[kv[0]] = .choice(kv[1]) }
        }
        return out
    }

    var body: some View {
        if let data, let flow {
            let p = ValveFlow.progress(flow, answers, tee: tee)
            VStack(alignment: .leading, spacing: 18) {
                picker(data)
                if let o = p.outcome { outcomeCard(flow, o) }
                if let s = p.current { stepCard(flow, s, p) }
                if !p.path.isEmpty { pathCard(p) }
                footer(data, flow)
            }
            .animation(.snappy, value: p)
        } else {
            Text("The workflows come with the reference content; they appear once it has loaded.")
                .font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    // MARK: Lesion and modality

    private func picker(_ data: ValveFlowData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups(data), id: \.id) { g in
                VStack(alignment: .leading, spacing: 7) {
                    Eyebrow(text: g.name).padding(.leading, 2)
                    FlowLayout(spacing: 8) {
                        ForEach(g.flows) { f in chip(f) }
                    }
                }
            }
            Picker("Study", selection: $tee) {
                Text("TTE").tag(false)
                Text("Intraoperative TEE").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    private struct Group { var id: String; var name: String; var flows: [ValveFlowDef] }

    private func groups(_ data: ValveFlowData) -> [Group] {
        var out: [Group] = []
        for f in flows {
            if let i = out.firstIndex(where: { $0.id == f.group }) { out[i].flows.append(f) }
            else { out.append(Group(id: f.group, name: data.groupName(f.group), flows: [f])) }
        }
        return out
    }

    private func chip(_ f: ValveFlowDef) -> some View {
        let on = f.id == flow?.id
        return Button {
            Haptics.light()
            withAnimation(.snappy) { flowId = f.id; answers = [:]; entry = "" }
        } label: {
            Text(f.short)
                .font(PS.sys(size: 13.5, weight: .semibold))
                .foregroundStyle(on ? PS.bg : PS.fg2)
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(on ? PS.fg : PS.surface, in: Capsule())
                .overlay(Capsule().stroke(on ? Color.clear : PS.line2, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(f.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: The step

    private func stepCard(_ flow: ValveFlowDef, _ s: ValveFlowStep, _ p: FlowProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "\(flow.short) · step \(p.path.count + 1)", color: PS.accent2)
                Spacer(minLength: 8)
                if let t = p.tally { Text(t).font(PS.sys(size: 11.5, weight: .medium)).foregroundStyle(PS.fg3).multilineTextAlignment(.trailing) }
            }
            Text(s.title).font(PS.serif(size: 22, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
            if let a = s.ask { Text(a).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true) }
            if let v = tee ? s.tee : s.tte {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(tee ? "TEE" : "TTE").font(PS.mono(size: 10, weight: .bold)).foregroundStyle(PS.accent2)
                    Text(v).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let b = s.bandText { Text(b).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
            if s.isNumber { numberEntry(s) } else { options(s) }
            Button {
                Haptics.light()
                withAnimation(.snappy) { answers[s.id] = .cannot; entry = "" }
            } label: { Label("Cannot obtain", systemImage: "forward") }
                .buttonStyle(GhostButtonStyle())
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    private func numberEntry(_ s: ValveFlowStep) -> some View {
        let value = Double(entry.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        let ok = (value ?? 0) > 0
        return HStack(spacing: 10) {
            TextField("Value", text: $entry)
                .keyboardType(.decimalPad)
                .focused($entryFocused)
                .font(PS.sys(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(PS.fg)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(s.title)
            if let u = s.unit, !u.isEmpty { Text(u).font(PS.sys(size: 13)).foregroundStyle(PS.fg3) }
            Button {
                guard let v = value, v > 0 else { return }
                Haptics.light()
                entryFocused = false
                withAnimation(.snappy) { answers[s.id] = .number(v); entry = "" }
            } label: { Text("Next").frame(minWidth: 52) }
                .buttonStyle(CapsuleButtonStyle(prominent: ok))
                .disabled(!ok)
        }
    }

    private func options(_ s: ValveFlowStep) -> some View {
        VStack(spacing: 8) {
            ForEach(s.options ?? []) { o in
                Button {
                    Haptics.light()
                    withAnimation(.snappy) { answers[s.id] = .choice(o.id) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Self.tint(o.tag)).frame(width: 8, height: 8)
                            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            if let d = o.detail { Text(d).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: The result

    private func outcomeCard(_ flow: ValveFlowDef, _ o: FlowOutcome) -> some View {
        let tone = o.grade.map { Self.tint(for: $0) } ?? PS.accent2
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: flow.name, color: tone)
            Text(o.headline.titleCased).font(PS.serif(size: 24, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
            Text(o.text).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(o.next.enumerated()), id: \.offset) { _, n in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "arrow.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(tone)
                    Text(n).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(Array(o.cautions.enumerated()), id: \.offset) { _, c in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(PS.sys(size: 11)).foregroundStyle(PS.accent)
                    Text(c).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                Haptics.light()
                withAnimation(.snappy) { answers = [:]; entry = "" }
            } label: { Label("Start over", systemImage: "arrow.counterclockwise") }
                .buttonStyle(GhostButtonStyle())
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: PS.cardRadius, topTrailingRadius: PS.cardRadius)
                .fill(tone.opacity(0.9)).frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    // MARK: The path so far

    private func pathCard(_ p: FlowProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: "Your answers").padding(.leading, 2)
                Spacer()
                if p.outcome == nil {
                    Button("Start over") {
                        Haptics.light()
                        withAnimation(.snappy) { answers = [:]; entry = "" }
                    }
                    .buttonStyle(TextButtonStyle(color: PS.fg2, size: 12.5))
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(p.path.enumerated()), id: \.element.id) { i, r in
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) {
                            answers.removeValue(forKey: r.step.id)
                            if case .number(let v) = r.answer { entry = ValveFlow.fmt(v) } else { entry = "" }
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(r.answer == .cannot ? PS.line2 : Self.tint(r.tag)).frame(width: 7, height: 7)
                                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.step.title).font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(PS.fg).multilineTextAlignment(.leading)
                                Text(r.text).font(PS.sys(size: 12.5)).foregroundStyle(r.answer == .cannot ? PS.fg3 : PS.fg2).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "pencil").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Changes this answer")
                    if i < p.path.count - 1 { Hairline().padding(.leading, 14) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private func footer(_ data: ValveFlowData, _ flow: ValveFlowDef) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let intro = flow.intro {
                Text(intro).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array((flow.notes ?? []).enumerated()), id: \.offset) { _, n in
                Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
            if let src = data.source(flow.source) {
                Button {
                    if let u = src.url.flatMap(URL.init(string:)) { onOpen(u) }
                } label: {
                    Text("Source: " + (flow.ref.map { $0 + ". " } ?? "") + src.citation + (src.url == nil ? "" : " ↗"))
                        .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .disabled(src.url == nil)
            }
        }
    }

    static func tint(for g: ValveGrade) -> Color {
        switch g {
        case .mild: return PS.green
        case .moderate: return PS.accent2
        case .severe: return PS.accent
        }
    }

    /// The dot beside an option or an answer: severe coral, moderate blue, mild green, anything else grey.
    static func tint(_ tag: String?) -> Color {
        switch tag {
        case "severe"?, "g4"?: return PS.accent
        case "moderate"?, "intermediate"?, "g2"?, "g3"?: return PS.accent2
        case "mild"?, "normal"?, "g1"?: return PS.green
        default: return PS.fg3
        }
    }
}
