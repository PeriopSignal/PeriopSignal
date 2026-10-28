import SwiftUI

/// Maximum local-anesthetic doses for one agent or a mixture, with Exparel's rules.
struct LocalAnestheticView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void

    @AppStorage("ps.la.weight") private var weightText = ""
    @AppStorage("ps.la.pediatric") private var pediatric = false
    @AppStorage("ps.la.years") private var years = 8
    @AppStorage("ps.la.epi") private var epinephrine = false
    @State private var entries: [LAEntry] = []
    @State private var volumes: [UUID: String] = [:]
    @State private var copied = false
    @FocusState private var focused: Bool

    private var agents: [LocalAnesthetic] { refs.peds?.localAnesthetics ?? [] }
    private var weight: Double? {
        let v = Double(weightText.replacingOccurrences(of: ",", with: "."))
        return (v ?? 0) > 0 ? v : nil
    }
    private var liveEntries: [LAEntry] {
        entries.map { e in
            var copy = e
            copy.mL = Double((volumes[e.id] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
            return copy
        }
    }
    private var result: LAMixResult {
        LAMixCalc.evaluate(entries: liveEntries, agents: agents, weightKg: weight ?? 0, pediatric: pediatric, epinephrine: epinephrine, ageYears: pediatric ? years : nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                patient
                summary
                mixture
                if !result.warnings.isEmpty { warnings }
                maxima
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Local anesthetic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .onAppear { if entries.isEmpty, let first = agents.first { add(first) } }
        .onChange(of: agents.count) { _, _ in if entries.isEmpty, let first = agents.first { add(first) } }
        .sensoryFeedback(.success, trigger: copied)
    }

    // MARK: Patient

    private var patient: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Weight", size: 10)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .font(PS.serif(size: 30, weight: .semibold))
                            .foregroundStyle(PS.fg)
                            .frame(width: 96)
                        Text("kg").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Picker("Patient", selection: $pediatric) {
                        Text("Adult").tag(false)
                        Text("Child").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    if pediatric {
                        Picker("Age", selection: $years) {
                            ForEach(0...17, id: \.self) { Text("\($0) y").tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu).tint(PS.fg)
                    }
                }
            }
            Toggle(isOn: $epinephrine) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("With epinephrine").font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                    Text("Raises the label maximum for lidocaine, bupivacaine, mepivacaine and chloroprocaine; not for Exparel.").font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(PS.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    // MARK: Summary

    private var summary: some View {
        let r = result
        let tone: Color = r.combined > 1 ? PS.accent : (r.combined > 0.8 ? PS.accent2 : PS.green)
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Of the combined maximum")
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(weight == nil ? "—" : "\(r.percentUsed)%")
                    .font(PS.serif(size: 44, weight: .semibold))
                    .foregroundStyle(weight == nil ? PS.fg3 : PS.fg)
                    .contentTransition(.numericText())
                Text(weight == nil ? "enter a weight" : (r.combined > 1 ? "over the limit" : "within limits"))
                    .font(PS.sys(size: 14))
                    .foregroundStyle(weight == nil ? PS.fg3 : tone)
                Spacer()
                Button {
                    UIPasteboard.general.string = summaryText
                    copied = true
                } label: { Text("Copy") }
                .buttonStyle(GhostButtonStyle())
                .disabled(weight == nil)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(PS.line2).frame(height: 6)
                    Capsule().fill(tone).frame(width: geo.size.width * CGFloat(min(1, r.combined)), height: 6)
                }
            }
            .frame(height: 6)
            Text("Each agent counts as a fraction of its own maximum; the fractions add up, and the mixture stays within limits while the total is at or below 100%.")
                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .animation(.snappy, value: r.percentUsed)
    }

    private var summaryText: String {
        var s = "Local anesthetic mixture for \(weightText) kg \(pediatric ? "child" : "adult")\(epinephrine ? " with epinephrine" : ""): \(result.percentUsed)% of the combined maximum."
        for a in result.agents where a.mL > 0 {
            s += "\n• \(a.agent.name) \(PedsCalc.fmt(a.percent))% × \(PedsCalc.fmt(a.mL)) mL = \(PedsCalc.fmt(a.mg)) mg" + (a.maxMg.map { " of \(PedsCalc.fmt($0)) mg maximum" } ?? "")
        }
        for w in result.warnings { s += "\n! " + w }
        return s
    }

    // MARK: Mixture rows

    private var mixture: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Agents").padding(.leading, 2)
                Spacer()
                Menu {
                    ForEach(agents) { a in Button(a.name) { add(a) } }
                } label: { Label("Add", systemImage: "plus").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent) }
            }
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                    row(entry, result: result.agents.first { $0.id == entry.id })
                    if i < entries.count - 1 { Hairline().padding(.leading, 16) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private func row(_ entry: LAEntry, result r: LAAgentResult?) -> some View {
        let agent = agents.first { $0.id == entry.agentID }
        let binding = Binding<LAEntry>(
            get: { entries.first { $0.id == entry.id } ?? entry },
            set: { new in if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i] = new } })
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(agents) { a in
                        Button(a.name) {
                            binding.wrappedValue.agentID = a.id
                            binding.wrappedValue.percent = a.concentrations.first ?? 0.5
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(agent?.name ?? entry.agentID).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 10, weight: .bold)).foregroundStyle(PS.fg3)
                    }
                }
                Menu {
                    ForEach(agent?.concentrations ?? [], id: \.self) { c in
                        Button("\(PedsCalc.fmt(c))%") { binding.wrappedValue.percent = c }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(PedsCalc.fmt(entry.percent))%").font(PS.sys(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(PS.fg)
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 10, weight: .bold)).foregroundStyle(PS.fg3)
                    }
                }
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    TextField("0", text: Binding(get: { volumes[entry.id] ?? "" }, set: { volumes[entry.id] = $0 }))
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .multilineTextAlignment(.trailing)
                        .font(PS.sys(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PS.fg)
                        .frame(width: 58)
                    Text("mL").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                }
                if entries.count > 1 {
                    Button { withAnimation(.snappy) { remove(entry) } } label: {
                        Image(systemName: "xmark.circle.fill").font(PS.sys(size: 16)).foregroundStyle(PS.fg3)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let r, let w = weight, w > 0 {
                HStack(spacing: 8) {
                    Text("\(PedsCalc.fmt(r.mg)) mg")
                        .font(PS.sys(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(r.fraction > 1 ? PS.accent : PS.fg)
                    if let m = r.maxMg {
                        Text("of \(PedsCalc.fmt(m)) mg max · \(Int((r.fraction * 100).rounded()))%").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2)
                    } else {
                        Text("no maximum on file for this patient").font(PS.sys(size: 12.5)).foregroundStyle(PS.accent)
                    }
                }
                if let alone = r.maxMLAlone {
                    Text("Alone: up to \(PedsCalc.fmt(alone)) mL at \(PedsCalc.fmt(r.percent))%" + (r.remainingML.map { "; in this mixture you could still add \(PedsCalc.fmt($0)) mL" } ?? ""))
                        .font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func add(_ agent: LocalAnesthetic) {
        let e = LAEntry(agentID: agent.id, percent: agent.concentrations.first ?? 0.5, mL: 0)
        entries.append(e)
        volumes[e.id] = ""
    }

    private func remove(_ entry: LAEntry) {
        entries.removeAll { $0.id == entry.id }
        volumes[entry.id] = nil
    }

    // MARK: Warnings

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, w in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill").font(PS.sys(size: 12)).foregroundStyle(PS.accent)
                    Text(w).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PS.accent.opacity(0.35), lineWidth: 1))
    }

    // MARK: Maxima table

    private var maxima: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: weight == nil ? "Maximum doses" : "Maximum doses at \(weightText) kg").padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(agents.enumerated()), id: \.element.id) { i, a in
                    let m = weight.flatMap { LAMixCalc.maxMg(for: a, weightKg: $0, pediatric: pediatric, epinephrine: epinephrine, ageYears: pediatric ? years : nil) }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(a.name).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                            Spacer()
                            Text(m.map { PedsCalc.fmt($0) + " mg" } ?? "—")
                                .font(PS.sys(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(m == nil ? PS.fg3 : PS.fg)
                        }
                        Text(basisText(a))
                            .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5)
                            .fixedSize(horizontal: false, vertical: true)
                        if let m, !a.concentrations.isEmpty {
                            Text(a.concentrations.map { "\(PedsCalc.fmt(m / ($0 * 10))) mL of \(PedsCalc.fmt($0))%" }.joined(separator: " · "))
                                .font(PS.sys(size: 12)).foregroundStyle(PS.fg2).lineLimit(2).minimumScaleFactor(0.85)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    if i < agents.count - 1 { Hairline().padding(.leading, 16) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private func basisText(_ a: LocalAnesthetic) -> String {
        if pediatric {
            var s = "\(PedsCalc.fmt(a.maxMgPerKg)) mg/kg single injection"
            if let cap = a.pedsMaxMg ?? a.adultPlainMaxMg { s += ", at most \(PedsCalc.fmt(cap)) mg" }
            if let y = a.pedsMinYears { s += "; labeled from \(y) years" }
            return s
        }
        let perKg = epinephrine ? (a.adultEpiMgPerKg ?? a.adultPlainMgPerKg) : a.adultPlainMgPerKg
        let cap = epinephrine ? (a.adultEpiMaxMg ?? a.adultPlainMaxMg) : a.adultPlainMaxMg
        var parts: [String] = []
        if let p = perKg { parts.append("\(PedsCalc.fmt(p)) mg/kg") }
        if let c = cap { parts.append("at most \(PedsCalc.fmt(c)) mg") }
        var s = parts.isEmpty ? "no adult maximum on file" : parts.joined(separator: ", ")
        if epinephrine && a.adultEpiMaxMg == nil && a.adultEpiMgPerKg == nil { s += " (epinephrine does not change it)" }
        if let d = a.per24hMaxMg { s += "; \(PedsCalc.fmt(d)) mg in 24 h" }
        return s
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            Text("Adult maxima are the FDA labels' figures; pediatric per-kilogram maxima follow the ASRA/ESRA recommendations. Label maxima are conservative conventions, not pharmacological thresholds: site, vascularity, age, hepatic and cardiac function change the risk. Exparel's rules come from its label. The LAST checklist is under Quick references.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(Set(agents.compactMap(\.source))).sorted(), id: \.self) { s in
                Text(s).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
