import SwiftUI

/// PONV in one place: the Apfel factors set how many antiemetics to give (Fifth consensus), the agents
/// are ticked as they are chosen, and the rescue section offers only classes not already given.
struct PONVView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void
    var onOpenCard: () -> Void

    @State private var selection = ScoreSelection(on: Set(LaunchSeed.list("ps.ponv.factors")))
    @State private var chosen: Set<String> = Set(LaunchSeed.list("ps.ponv.agents"))

    private let def = Scores.apfel
    private var data: PONVData? { refs.bundle?.ponv }
    private var factors: Int { def.total(selection) }
    private var band: ScoreBand? { def.band(for: factors) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                riskCard
                if let data {
                    planCard(data)
                    agentsSection(data)
                    rescueSection(data)
                } else {
                    Text("Loading the agents…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                }
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("PONV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { withAnimation(.snappy) { selection = ScoreSelection(); chosen = [] } }
                    .disabled(selection.isEmpty && chosen.isEmpty)
            }
        }
    }

    // MARK: Risk

    private var riskCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Risk Factors (Apfel)").font(PS.serif(size: 18)).foregroundStyle(PS.fg).padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(def.items.enumerated()), id: \.element.id) { i, item in
                    ScoreItemRow(item: item, selection: $selection)
                    if i < def.items.count - 1 { Hairline().padding(.leading, 16) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private func tone(_ t: ScoreBand.Tone) -> Color {
        switch t {
        case .low: return PS.green
        case .moderate: return PS.accent2
        case .high: return PS.accent
        }
    }

    // MARK: How many

    private func planCard(_ data: PONVData) -> some View {
        let target = PONVPlan.target(factors: factors, counts: data.counts)
        let classes = PONVPlan.classes(of: chosen, in: data.agents)
        let need = target?.agents ?? 2
        let toneColor = band.map { tone($0.tone) } ?? PS.fg3
        let wanted: String = {
            guard let t = target else { return "2" }
            if let hi = t.agentsHigh, hi > t.agents { return "\(t.agents)–\(hi)" }
            return "\(t.agents)"
        }()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(factors)").font(PS.serif(size: 40, weight: .semibold)).foregroundStyle(PS.fg).contentTransition(.numericText())
                VStack(alignment: .leading, spacing: 2) {
                    Text(factors == 1 ? "risk factor" : "risk factors").font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
                    if let b = band { Text(b.label).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(toneColor) }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "pills.fill").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(toneColor)
                Text("Give \(wanted) antiemetics from different classes")
                    .font(PS.serif(size: 20, weight: .semibold)).foregroundStyle(PS.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let t = target { Text(t.text + " (Fifth consensus).").font(PS.sys(size: 13)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true) }
            ChecklistProgress(done: min(classes.count, need), total: need, tint: toneColor, title: "Classes Chosen") { chosen = [] }
            if factors >= 3 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reduce the Baseline Risk").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg)
                    FlowLayout(spacing: 6) {
                        ForEach(data.riskReduction, id: \.self) { r in
                            Text(r).font(PS.sys(size: 12, weight: .medium)).foregroundStyle(PS.fg2)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(PS.surface2, in: Capsule())
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: PS.cardRadius, topTrailingRadius: PS.cardRadius)
                .fill(toneColor.opacity(0.9)).frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
        .animation(.snappy, value: factors)
    }

    // MARK: Agents

    private func agentsSection(_ data: PONVData) -> some View {
        let agents = data.agents.filter { $0.prophylaxis != false }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Antiemetic Agents").font(PS.serif(size: 18)).foregroundStyle(PS.fg).padding(.leading, 2)
            Text("Tick what you give; two agents of one class count once.").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(agents.enumerated()), id: \.element.id) { i, a in
                    agentRow(a, all: data.agents)
                    if i < agents.count - 1 { Hairline().padding(.leading, 54) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 2)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private func agentRow(_ a: PONVAgent, all: [PONVAgent]) -> some View {
        let on = chosen.contains(a.id)
        let sameClass = on ? all.filter { $0.id != a.id && chosen.contains($0.id) && $0.cls == a.cls }.map(\.name) : []
        return Button {
            Haptics.light()
            withAnimation(.snappy) { if on { chosen.remove(a.id) } else { chosen.insert(a.id) } }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? PS.green : PS.surface2)
                    RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(on ? PS.green : PS.line2, lineWidth: 1.6)
                    if on { Image(systemName: "checkmark").font(PS.sys(size: 13, weight: .heavy)).foregroundStyle(PS.accentFg) }
                }
                .frame(width: 26, height: 26)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(a.name).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                        RoleTag(role: a.cls)
                        if a.longActing == true { Eyebrow(text: "Long-acting", color: PS.fg3, size: 8.5) }
                    }
                    Text(a.dose + (a.timing.map { " · " + $0.lowercasedFirst } ?? ""))
                        .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !sameClass.isEmpty {
                        Text("Same class as \(sameClass.joined(separator: ", ")): counts once").font(PS.sys(size: 11.5, weight: .medium)).foregroundStyle(PS.accent)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Rescue

    private func rescueSection(_ data: PONVData) -> some View {
        let given = PONVPlan.classes(of: chosen, in: data.agents)
        let options = PONVPlan.rescueOptions(chosen: chosen, agents: data.agents)
        let longActing = PONVPlan.longActingGiven(chosen: chosen, agents: data.agents)
        return VStack(alignment: .leading, spacing: 8) {
            Text("PONV Rescue").font(PS.serif(size: 18)).foregroundStyle(PS.fg).padding(.leading, 2)
            VStack(alignment: .leading, spacing: 12) {
                if !given.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "nosign").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.accent)
                        Text("Not again within 6 h: " + given.joined(separator: ", ")).font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !longActing.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "clock.badge.xmark").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.accent)
                        Text("Do not redose \(longActing.map(\.name).joined(separator: " or ")) in recovery.").font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(given.isEmpty ? "Rescue options (tick the prophylaxis above to narrow them to classes not yet given)" : "From a class not yet given")
                    .font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg3)
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { i, a in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.name).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                                RoleTag(role: a.cls)
                            }
                            Spacer(minLength: 8)
                            Text(a.rescueDose ?? a.dose).font(PS.sys(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(PS.fg)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 9)
                        if i < options.count - 1 { Hairline() }
                    }
                }
                if options.isEmpty {
                    Text("Every rescue class has been used: after 6 hours a second 5-HT₃ antagonist or butyrophenone dose may be considered.").font(PS.sys(size: 13)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                }
                Hairline()
                ForEach(Array(data.rescueRules.enumerated()), id: \.offset) { _, rule in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(PS.fg3).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
                        Text(rule).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            HStack(spacing: 10) {
                Button(action: onOpenCard) { Label("Full card, with children", systemImage: "tablecells") }.buttonStyle(GhostButtonStyle())
                if let s = data?.sourceURL, let url = URL(string: s) {
                    Button { onOpen(url) } label: { Label("Guideline ↗", systemImage: "doc.text") }.buttonStyle(GhostButtonStyle())
                }
            }
            Text(def.readout).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            if let s = data?.source {
                Text(s).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension String {
    var lowercasedFirst: String {
        guard let f = first else { return self }
        // Keep acronyms ("PACU") and units as written.
        if dropFirst().first?.isUppercase == true { return self }
        return f.lowercased() + dropFirst()
    }
}
