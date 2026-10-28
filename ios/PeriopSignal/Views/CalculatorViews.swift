import SwiftUI

// MARK: - Score calculators (RCRI, ARISCAT, STOP-Bang, Aldrete, Apfel)

struct ScoreCalculatorView: View {
    var def: ScoreDefinition
    var onOpen: (URL) -> Void
    var onOpenRef: (String) -> Void = { _ in }
    @State private var selection = ScoreSelection()
    @State private var copied = false

    private var score: Int { def.total(selection) }
    private var band: ScoreBand? { def.band(for: score) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                result
                items
                bands
                if !def.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Notes")
                        TakeHomeList(items: def.notes, size: 13.5)
                    }
                }
                sources
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle(def.short)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { withAnimation(.snappy) { selection = ScoreSelection() } }
                    .disabled(selection.isEmpty)
            }
        }
        .sensoryFeedback(.success, trigger: copied)
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: def.name)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(score)")
                    .font(PS.serif(size: 44, weight: .semibold))
                    .foregroundStyle(PS.fg)
                    .contentTransition(.numericText())
                Text("of \(def.maxScore)")
                    .font(PS.sys(size: 14))
                    .foregroundStyle(PS.fg3)
                Spacer()
                Button {
                    UIPasteboard.general.string = summaryText
                    copied = true
                } label: { Text("Copy") }
                .buttonStyle(GhostButtonStyle())
            }
            if let b = band {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle().fill(tone(b.tone)).frame(width: 8, height: 8)
                        Text(b.label).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                    }
                    Text(b.detail)
                        .font(PS.sys(size: 14))
                        .foregroundStyle(PS.fg2)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .animation(.snappy, value: score)
            }
            if let n = def.next {
                Button { onOpenRef(n.quickref) } label: { Label(n.label, systemImage: "arrow.right.circle") }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.top, 2)
            }
            Text(def.readout)
                .font(PS.sys(size: 12.5))
                .foregroundStyle(PS.fg3)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(alignment: .top) {
            if let b = band {
                UnevenRoundedRectangle(topLeadingRadius: PS.cardRadius, topTrailingRadius: PS.cardRadius)
                    .fill(tone(b.tone).opacity(0.9))
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            }
        }
    }

    private var items: some View {
        VStack(spacing: 0) {
            ForEach(Array(def.items.enumerated()), id: \.element.id) { i, item in
                ScoreItemRow(item: item, selection: $selection)
                if i < def.items.count - 1 { Hairline().padding(.leading, 16) }
            }
        }
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    private var bands: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Interpretation")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(def.bands.enumerated()), id: \.offset) { i, b in
                    let active = b.range.contains(score)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(tone(b.tone)).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.label).font(PS.sys(size: 13.5, weight: active ? .semibold : .regular)).foregroundStyle(active ? PS.fg : PS.fg2)
                            Text(b.detail).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if active { Image(systemName: "arrow.left").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.accent) }
                    }
                    .padding(.vertical, 8)
                    if i < def.bands.count - 1 { Hairline() }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            Eyebrow(text: "Sources")
            SourceLine(source: def.source, onOpen: onOpen)
            if let r = def.rateSource { SourceLine(source: r, onOpen: onOpen) }
            Text("A calculator, not a consultation: the score informs, your assessment decides.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).padding(.top, 2)
        }
    }

    private var summaryText: String {
        var s = "\(def.name): \(score)/\(def.maxScore)"
        if let b = band { s += " — \(b.label); \(b.detail)" }
        let yes = def.items.compactMap { item -> String? in
            switch item.input {
            case .toggle: return selection.on.contains(item.id) ? item.label : nil
            case .choice(let options):
                let chosen = selection.choices[item.id] ?? options.first?.label ?? ""
                return "\(item.label): \(chosen)"
            }
        }
        if !yes.isEmpty { s += "\n" + yes.joined(separator: "; ") }
        s += "\n(\(def.source.citation ?? def.source.title))"
        return s
    }

    private func tone(_ t: ScoreBand.Tone) -> Color {
        switch t {
        case .low: return PS.green
        case .moderate: return PS.accent2
        case .high: return PS.accent
        }
    }
}

struct ScoreItemRow: View {
    var item: ScoreItem
    @Binding var selection: ScoreSelection

    var body: some View {
        switch item.input {
        case .toggle(let points):
            Toggle(isOn: Binding(
                get: { selection.on.contains(item.id) },
                set: { on in
                    Haptics.light()
                    withAnimation(.snappy) { if on { selection.on.insert(item.id) } else { selection.on.remove(item.id) } }
                })) {
                label(points: points)
            }
            .tint(PS.accent)
            .padding(.horizontal, 16).padding(.vertical, 11)
        case .choice(let options):
            VStack(alignment: .leading, spacing: 8) {
                label(points: nil)
                VStack(spacing: 0) {
                    ForEach(options) { opt in
                        let chosen = (selection.choices[item.id] ?? options.first?.label) == opt.label
                        Button {
                            Haptics.light()
                            withAnimation(.snappy) { selection.choices[item.id] = opt.label }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                                    .font(PS.sys(size: 16))
                                    .foregroundStyle(chosen ? PS.accent : PS.fg3)
                                Text(opt.label)
                                    .font(PS.sys(size: 14, weight: chosen ? .semibold : .regular))
                                    .foregroundStyle(PS.fg)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Text(opt.points == 0 ? "0" : "+\(opt.points)")
                                    .font(PS.mono(size: 11, weight: .semibold))
                                    .foregroundStyle(chosen ? PS.fg2 : PS.fg3)
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
        }
    }

    private func label(points: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(item.label).font(PS.sys(size: 15, weight: .medium)).foregroundStyle(PS.fg)
                if let p = points, p != 1 {
                    Text("+\(p)").font(PS.mono(size: 10.5, weight: .semibold)).foregroundStyle(PS.fg3)
                }
            }
            if let d = item.detail {
                Text(d).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SourceLine: View {
    var source: RefSource
    var onOpen: (URL) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(source.citation ?? source.title)
                .font(PS.sys(size: 13)).foregroundStyle(PS.fg2).lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: source.url) {
                Button { onOpen(url) } label: { Text("Open ↗") }.buttonStyle(TextButtonStyle(color: PS.accent, size: 13))
            }
        }
    }
}

// MARK: - Pediatric calculator

struct PedsCalculatorView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void

    @AppStorage("ps.peds.weight") private var weightText = ""
    @AppStorage("ps.peds.years") private var years = 0
    @AppStorage("ps.peds.months") private var months = 0
    @State private var tab = 0
    @State private var hctStart = ""
    @State private var hctMin = ""
    @State private var expanded: String?
    @FocusState private var weightFocused: Bool

    private var weight: Double? {
        let v = Double(weightText.replacingOccurrences(of: ",", with: "."))
        return (v ?? 0) > 0 ? v : nil
    }
    private var estimate: Double? { PedsCalc.estimatedWeight(years: years, months: months) }
    private var ageMonths: Double { Double(years * 12 + months) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                inputs
                Picker("Section", selection: $tab) {
                    Text("Drugs").tag(0)
                    Text("Airway").tag(1)
                    Text("Fluids & blood").tag(2)
                }
                .pickerStyle(.segmented)
                if let peds = refs.peds {
                    switch tab {
                    case 0: drugs(peds)
                    case 1: airway
                    default: fluids(peds)
                    }
                    NavigationLink(value: RefRoute.local) {
                        QuietRow(icon: "syringe", tint: PS.accent, eyebrow: "Local anesthetic", text: "Maximum doses for a child of this weight, single agent or mixture", textSize: 14, lines: 2) {
                            Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                        }
                    }
                    .buttonStyle(.plain)
                    footer(peds)
                } else {
                    Text("Loading the dosing table…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Pediatric")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
    }

    // MARK: Inputs

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Weight", size: 10)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .focused($weightFocused)
                            .font(PS.serif(size: 30, weight: .semibold))
                            .foregroundStyle(PS.fg)
                            .frame(width: 96)
                        Text("kg").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Age", size: 10)
                    HStack(spacing: 2) {
                        Picker("Years", selection: $years) {
                            ForEach(0...17, id: \.self) { Text("\($0) y").tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu).tint(PS.fg)
                        Picker("Months", selection: $months) {
                            ForEach(0...11, id: \.self) { Text("\($0) mo").tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu).tint(PS.fg)
                    }
                }
            }
            if weight == nil, let e = estimate {
                Button {
                    Haptics.light()
                    weightText = PedsCalc.fmt(e)
                } label: { Text("Use the APLS estimate for this age: \(PedsCalc.fmt(e)) kg") }
                    .buttonStyle(TextButtonStyle(color: PS.accent, size: 13))
            } else if weight == nil {
                Text("Enter the weight; doses and sizes fill in as you type.").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    // MARK: Drugs

    private func drugs(_ peds: PedsData) -> some View {
        let groups = peds.drugs.reduce(into: [(group: String, drugs: [PedsDrug])]()) { acc, d in
            if let i = acc.firstIndex(where: { $0.group == d.group }) { acc[i].drugs.append(d) } else { acc.append((group: d.group, drugs: [d])) }
        }
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(groups, id: \.group) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: entry.group).padding(.leading, 2)
                    VStack(spacing: 0) {
                        ForEach(Array(entry.drugs.enumerated()), id: \.element.id) { i, d in
                            drugRow(d)
                            if i < entry.drugs.count - 1 { Hairline().padding(.leading, 16) }
                        }
                    }
                    .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                }
            }
        }
    }

    private func drugRow(_ d: PedsDrug) -> some View {
        let perKg = PedsCalc.fmt(d.low) + (d.high.map { "–" + PedsCalc.fmt($0) } ?? "") + " \(d.unit)/kg"
        let computed = weight.map { PedsCalc.doseText(low: d.low, high: d.high, unit: d.unit, weightKg: $0, min: d.min, max: d.max) }
        let open = expanded == d.id
        return Button {
            withAnimation(.snappy) { expanded = open ? nil : d.id }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                        Text("\(d.use) · \(d.route)").font(PS.sys(size: 12)).foregroundStyle(PS.fg2).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(computed?.text ?? "—")
                            .font(PS.sys(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(computed == nil ? PS.fg3 : PS.fg)
                            .contentTransition(.numericText())
                        HStack(spacing: 4) {
                            if computed?.capped == true { Text("limit").font(PS.mono(size: 9.5)).foregroundStyle(PS.accent) }
                            Text(perKg).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
                        }
                    }
                }
                if open {
                    VStack(alignment: .leading, spacing: 4) {
                        if d.min != nil || d.max != nil {
                            Text([d.min.map { "minimum \(PedsCalc.fmt($0)) \(d.unit)" }, d.max.map { "maximum \(PedsCalc.fmt($0)) \(d.unit)" }].compactMap { $0 }.joined(separator: " · ").capitalizedFirst)
                                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2)
                        }
                        if let c = d.conc { Text(c).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2) }
                        if let n = d.note { Text(n).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineSpacing(1.5) }
                        if let s = d.source { Text(s).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).lineSpacing(1.5) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Airway

    private var airway: some View {
        let sizes = PedsCalc.ettSizes(years: years, months: months)
        let uncuffedValue = Double(sizes.uncuffed.split(separator: "–").first ?? "")
        let rows: [[String]] = [
            ["ETT uncuffed", sizes.uncuffed + " mm ID"],
            ["ETT cuffed", sizes.cuffed + " mm ID"],
            ["Depth, oral", PedsCalc.ettDepthOral(years: years, months: months, uncuffedID: uncuffedValue) + " cm at the lip"],
            ["Depth, nasal", PedsCalc.ettDepthNasal(years: years, months: months) + (PedsCalc.ettDepthNasal(years: years, months: months) == "—" ? "" : " cm at the naris")],
            ["Laryngeal mask", weight.map { "Size " + PedsCalc.lmaSize(weightKg: $0) } ?? "— (needs weight)"],
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: ageMonths < 1 ? "Set the age for tube sizes" : "For \(years) y \(months) mo").padding(.leading, 2)
            FactTable(rows: rows)
            Text("Uncuffed: age/4 + 4 (Cole); cuffed: age/4 + 3.5 (Khine), from 2 years; fixed sizes below that. Oral depth: age/2 + 12 cm from 2 years, 3 × tube ID before; nasal: age/2 + 15 cm. Laryngeal mask sizes follow the manufacturers' weight bands. Have the half-size above and below ready; confirm with a leak test and the chest radiograph when indicated.")
                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Fluids and blood

    private func fluids(_ peds: PedsData) -> some View {
        let w = weight ?? 0
        let maint = PedsCalc.maintenanceMLPerHour(weightKg: w)
        let ebv = weight.flatMap { PedsCalc.bloodVolume(weightKg: $0, ageMonths: ageMonths, rows: peds.bloodVolume) }
        let hs = Double(hctStart), hm = Double(hctMin)
        let mabl: (Double, Double)? = {
            guard let e = ebv, let a = hs, let b = hm, let lo = PedsCalc.mabl(ebv: e.low, hctStart: a, hctMin: b), let hi = PedsCalc.mabl(ebv: e.high, hctStart: a, hctMin: b) else { return nil }
            return (lo, hi)
        }()
        var rows: [[String]] = [
            ["Maintenance", weight == nil ? "—" : PedsCalc.fmt(maint) + " mL/h (4-2-1)"],
            ["Blood volume", ebv.map { "\(PedsCalc.range($0.low, $0.high)) mL · \($0.row.group), \(PedsCalc.range($0.row.mlPerKgLow, $0.row.mlPerKgHigh)) mL/kg" } ?? "—"],
        ]
        rows.append(["Allowable loss", mabl.map { "\(PedsCalc.range($0.0, $0.1)) mL" } ?? "— (enter hematocrits)"])
        return VStack(alignment: .leading, spacing: 12) {
            FactTable(rows: rows)
            HStack(spacing: 12) {
                hctField("Starting Hct %", text: $hctStart)
                hctField("Lowest acceptable Hct %", text: $hctMin)
            }
            Text("Maintenance by Holliday–Segar (4 mL/kg/h for the first 10 kg, 2 for the next 10, 1 beyond). Blood volume uses the age band in the table. Allowable blood loss = EBV × (Hct₀ − Hct_min) ÷ Hct₀; a guide for planning, not a transfusion trigger.")
                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Blood volume by age").padding(.leading, 2)
                FactTable(rows: peds.bloodVolume.map { [$0.group, "\(PedsCalc.range($0.mlPerKgLow, $0.mlPerKgHigh)) mL/kg"] })
            }
        }
    }

    private func hctField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: label, size: 9.5)
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .focused($weightFocused)
                .font(PS.sys(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(PS.fg)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func footer(_ peds: PedsData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            if let n = peds.note {
                Text(n).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
            Text("Doses are starting points from the sources shown on each line\(peds.reviewed.map { ", reviewed \(PSDate.monthYear($0))" } ?? ""). Check the concentration in your hand and your institution's references before giving a drug.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }
}


private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
