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
                table
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

    // MARK: The table

    private var table: some View {
        let r = result
        let over = r.combined > 1
        let tone: Color = weight == nil ? PS.fg3 : (over ? PS.accent : PS.green)
        let totalMg = r.agents.reduce(0) { $0 + $1.mg }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Doses").padding(.leading, 2)
                Spacer()
                Menu {
                    ForEach(agents) { a in Button(a.name) { add(a) } }
                } label: { Label("Add agent", systemImage: "plus").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent) }
            }
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Eyebrow(text: "Agent", size: 9.5).frame(maxWidth: .infinity, alignment: .leading)
                    Eyebrow(text: "Conc", size: 9.5).frame(width: 58, alignment: .leading)
                    Eyebrow(text: "mL", size: 9.5).frame(width: 62, alignment: .trailing)
                    Eyebrow(text: "mg", size: 9.5).frame(width: 64, alignment: .trailing)
                    Color.clear.frame(width: entries.count > 1 ? 22 : 0)
                }
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
                Hairline()
                ForEach(Array(entries.enumerated()), id: \.element.id) { _, entry in
                    row(entry, result: r.agents.first { $0.id == entry.id })
                    Hairline()
                }
                // Total
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total").font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                        Text(statusLine(r)).font(PS.sys(size: 12)).foregroundStyle(tone).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text(weight == nil ? "—" : "\(PedsCalc.fmt(totalMg)) mg")
                        .font(PS.serif(size: 26, weight: .semibold))
                        .foregroundStyle(tone)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(tone.opacity(weight == nil ? 0 : 0.10))
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(weight == nil ? PS.line : tone.opacity(0.6), lineWidth: 1))
            HStack {
                Text("Green: under the maximum for this weight. Red: above it. With more than one agent, each counts as a fraction of its own maximum and the fractions add up.")
                    .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    UIPasteboard.general.string = summaryText
                    copied = true
                } label: { Text("Copy") }
                .buttonStyle(GhostButtonStyle())
                .disabled(weight == nil)
            }
        }
        .animation(.snappy, value: r.percentUsed)
    }

    private func statusLine(_ r: LAMixResult) -> String {
        guard weight != nil else { return "Enter the weight" }
        let dosed = r.agents.filter { $0.mg > 0 }
        if dosed.isEmpty { return "Type the volumes" }
        if dosed.count == 1, let only = dosed.first, let m = only.maxMg {
            return r.combined > 1 ? "Above the maximum of \(PedsCalc.fmt(m)) mg" : "Under the maximum of \(PedsCalc.fmt(m)) mg (\(r.percentUsed)%)"
        }
        return r.combined > 1 ? "Above the combined maximum (\(r.percentUsed)%)" : "Under the combined maximum (\(r.percentUsed)% used)"
    }

    private var summaryText: String {
        var s = "Local anesthetic for \(weightText) kg \(pediatric ? "child" : "adult")\(epinephrine ? " with epinephrine" : ""): \(statusLine(result))."
        for a in result.agents where a.mL > 0 {
            s += "\n• \(a.agent.name) \(PedsCalc.fmt(a.percent))% × \(PedsCalc.fmt(a.mL)) mL = \(PedsCalc.fmt(a.mg)) mg" + (a.maxMg.map { " (max \(PedsCalc.fmt($0)) mg)" } ?? "")
        }
        for w in result.warnings { s += "\n! " + w }
        return s
    }

    private func row(_ entry: LAEntry, result r: LAAgentResult?) -> some View {
        let agent = agents.first { $0.id == entry.agentID }
        let binding = Binding<LAEntry>(
            get: { entries.first { $0.id == entry.id } ?? entry },
            set: { new in if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i] = new } })
        let overRow = (r?.fraction ?? 0) > 1
        return VStack(alignment: .leading, spacing: 4) {
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
                        Text(agent?.name ?? entry.agentID).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg).lineLimit(1).minimumScaleFactor(0.8)
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 9, weight: .bold)).foregroundStyle(PS.fg3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    ForEach(agent?.concentrations ?? [], id: \.self) { c in
                        Button("\(PedsCalc.fmt(c))%") { binding.wrappedValue.percent = c }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(PedsCalc.fmt(entry.percent))%").font(PS.sys(size: 13.5, weight: .medium, design: .monospaced)).foregroundStyle(PS.fg)
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 9, weight: .bold)).foregroundStyle(PS.fg3)
                    }
                }
                .frame(width: 58, alignment: .leading)
                TextField("0", text: Binding(get: { volumes[entry.id] ?? "" }, set: { volumes[entry.id] = $0 }))
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .multilineTextAlignment(.trailing)
                    .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PS.fg)
                    .padding(.horizontal, 6).padding(.vertical, 5)
                    .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(width: 62)
                Text(r.map { PedsCalc.fmt($0.mg) } ?? "0")
                    .font(PS.sys(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(overRow ? PS.accent : PS.fg)
                    .frame(width: 64, alignment: .trailing)
                    .contentTransition(.numericText())
                if entries.count > 1 {
                    Button { withAnimation(.snappy) { remove(entry) } } label: {
                        Image(systemName: "xmark.circle.fill").font(PS.sys(size: 15)).foregroundStyle(PS.fg3)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 22)
                }
            }
            if let r, weight != nil {
                Text(rowDetail(r))
                    .font(PS.sys(size: 11.5)).foregroundStyle(overRow ? PS.accent : PS.fg3)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func rowDetail(_ r: LAAgentResult) -> String {
        guard let m = r.maxMg else {
            if pediatric, let y = r.agent.pedsMinYears { return "Not labeled under \(y) years" }
            return "No maximum on file for this patient"
        }
        var s = "Max \(PedsCalc.fmt(m)) mg = \(PedsCalc.fmt(m / (r.percent * 10))) mL of \(PedsCalc.fmt(r.percent))% alone"
        if r.mg > 0, let left = r.remainingML { s += " · \(left < 0.05 ? "nothing" : PedsCalc.fmt(left) + " mL") more fits in this mix" }
        return s
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
                        if let n = a.note {
                            Text(n).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
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
            Text("Adult maxima are the FDA labels' figures (with a conventional per-kilogram ceiling where the label gives only milligrams); pediatric per-kilogram maxima follow the ASRA/ESRA 2018 recommendations. The additive rule for mixtures (each agent as a fraction of its own maximum, summed) is the convention described in ASRA's 2026 Pro-Con on mixing local anesthetics; no label or guideline codifies it. Label maxima are conservative conventions, not pharmacological thresholds: site, vascularity, age, hepatic and cardiac function change the risk. Exparel's rules come from its label. The LAST checklist is under Quick references.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(Set(agents.compactMap(\.source))).sorted(), id: \.self) { s in
                Text(s).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
