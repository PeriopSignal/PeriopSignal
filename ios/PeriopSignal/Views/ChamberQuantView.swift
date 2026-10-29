import SwiftUI

/// Echo measurements in, the ASE reading out: sex, height and weight set the reference values and the
/// body surface area; each row shows its cutoffs as a strip with the value marked. Nothing is stored.
struct ChamberQuantView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void

    @State private var sex: EchoSex = EchoSex(rawValue: LaunchSeed.string("ps.echo.sex")) ?? .male
    @State private var heightText = LaunchSeed.string("ps.echo.height")
    @State private var weightText = LaunchSeed.string("ps.echo.weight")
    @State private var group: String? = LaunchSeed.string("ps.echo.group").isEmpty ? nil : LaunchSeed.string("ps.echo.group")
    @State private var values: [String: String] = Self.seededValues()
    @State private var raw: Set<String> = []
    @State private var ivcText = ""
    @State private var collapses: Bool?
    @FocusState private var focused: Bool

    private var data: EchoData? { refs.bundle?.echo }
    private var bsa: Double? { EchoCalc.bsa(heightCm: WeightField.value(heightText), weightKg: WeightField.value(weightText), formula: data?.bsaFormula) }

    /// DEBUG screenshots: -ps.echo.values "lvedd=64,tapse=14".
    private static func seededValues() -> [String: String] {
        var out: [String: String] = [:]
        for pair in LaunchSeed.list("ps.echo.values") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
    }

    static func color(_ g: Int) -> Color {
        switch g {
        case 0: return PS.green
        case 1: return Topics.info("trauma").fg
        case 2: return Topics.info("mcs").fg
        case 3, 4: return PS.accent
        default: return PS.fg3
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                patient
                if let d = data {
                    summary(d)
                    groupTabs(d)
                    if let g = currentGroup(d) { groupCard(g) }
                    if let ivc = d.ivc, ivc.group == currentGroup(d)?.id { ivcCard(ivc) }
                    footer(d)
                } else {
                    Text("Loading the reference values…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("ASE Chamber Quantification")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    // MARK: Patient

    private var patient: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Sex").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg2)
                Spacer()
                Picker("Sex", selection: $sex) {
                    ForEach(EchoSex.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            HStack(spacing: 12) {
                field("Height (cm)", text: $heightText)
                field("Weight (kg)", text: $weightText)
            }
            Group {
                if let b = bsa {
                    Text("Body surface area **\(PedsCalc.fmt(b)) m²** (\(data?.bsaFormula == "mosteller" ? "Mosteller" : "DuBois")). Indexed rows accept the raw value too.")
                } else {
                    Text("Height and weight give the body surface area for the indexed rows (volumes, mass, the indexed annulus); they clear when you leave.")
                }
            }
            .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: label, size: 9.5)
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .focused($focused)
                .font(PS.sys(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(PS.fg)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Summary

    private struct Entry: Identifiable { var id: String { m.id }; var m: EchoMeasure; var v: Double; var g: Int }

    private func entries(_ d: EchoData) -> [Entry] {
        d.groups.flatMap(\.measures).compactMap { m in
            guard let v = EchoCalc.value(m, text: values[m.id] ?? "", raw: raw.contains(m.id), bsa: bsa), let g = EchoCalc.grade(m, sex, v) else { return nil }
            return Entry(m: m, v: v, g: g)
        }
    }

    @ViewBuilder private func summary(_ d: EchoData) -> some View {
        let e = entries(d)
        if !e.isEmpty {
            let abnormal = e.filter { $0.g > 0 }
            let worst = abnormal.map(\.g).max()
            let tone = worst.map { Self.color($0) } ?? PS.green
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: sex == .female ? "Female reference values" : "Male reference values", color: tone)
                Text(abnormal.isEmpty ? (e.count == 1 ? "Within the Normal Range" : "All Entered Values Within the Normal Range") : "\(abnormal.count) of \(e.count) Outside the Normal Range")
                    .font(PS.serif(size: 22, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(e) { x in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Self.color(x.g)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(x.m.short ?? x.m.name).font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg)
                                Text(EchoCalc.label(x.m, x.g)).font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(Self.color(x.g))
                            }
                            Spacer(minLength: 6)
                            Text("\(PedsCalc.fmt(x.v)) \(x.m.unit)").font(PS.sys(size: 12.5, design: .monospaced)).foregroundStyle(PS.fg2)
                        }
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
        }
    }

    // MARK: Groups

    private func currentGroup(_ d: EchoData) -> EchoGroup? { d.groups.first { $0.id == group } ?? d.groups.first }

    private func groupTabs(_ d: EchoData) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(d.groups) { g in
                    let on = g.id == currentGroup(d)?.id
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { group = g.id }
                    } label: {
                        Text(g.short ?? g.name)
                            .font(PS.sys(size: 13.5, weight: .semibold))
                            .foregroundStyle(on ? PS.bg : PS.fg2)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(on ? PS.fg : PS.surface, in: Capsule())
                            .overlay(Capsule().stroke(on ? Color.clear : PS.line2, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func groupCard(_ g: EchoGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: g.name).padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(g.measures.enumerated()), id: \.element.id) { i, m in
                    row(m)
                    if i < g.measures.count - 1 { Hairline().padding(.leading, 16) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            if let n = g.note {
                Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
            }
        }
    }

    private func row(_ m: EchoMeasure) -> some View {
        let isRaw = raw.contains(m.id)
        let text = values[m.id] ?? ""
        let v = EchoCalc.value(m, text: text, raw: isRaw, bsa: bsa)
        let g = EchoCalc.grade(m, sex, v)
        let unit = m.index == "bsa" && isRaw ? (m.rawUnit ?? m.unit.replacingOccurrences(of: "/m²", with: "")) : m.unit
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                    if let me = m.method { Text(me).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 6)
                TextField("—", text: Binding(get: { values[m.id] ?? "" }, set: { values[m.id] = $0 }))
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .multilineTextAlignment(.trailing)
                    .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PS.fg)
                    .padding(.horizontal, 6).padding(.vertical, 5)
                    .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(width: 74)
                if m.index == "bsa" {
                    Button {
                        Haptics.light()
                        if isRaw { raw.remove(m.id) } else { raw.insert(m.id) }
                    } label: {
                        Text(unit).font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.accent2)
                            .padding(.horizontal, 6).padding(.vertical, 5)
                            .background(PS.accent2.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Switch between the indexed and the raw value")
                    .frame(minWidth: 52)
                } else {
                    Text(unit).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 46, alignment: .leading)
                }
            }
            if EchoCalc.ref(m, sex) != nil {
                EchoStrip(bands: EchoCalc.bands(m, sex), value: v)
                Text(Self.rangeText(m, sex) + " " + m.unit + (m.ref.map { " · " + $0 } ?? ""))
                    .font(PS.sys(size: 12)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No reference value for this sex.").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
            }
            if m.index == "bsa" && isRaw && !text.isEmpty && bsa == nil {
                Text("Enter height and weight to index this value.").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent)
            } else if let g {
                Text(EchoCalc.label(m, g) + (m.index == "bsa" && isRaw ? " · \(PedsCalc.fmt(v ?? 0)) \(m.unit)" : ""))
                    .font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(Self.color(g))
            }
            if let n = m.note { Text(n).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    /// "Normal 42–58.4 · mild 58.4–63 · moderate 63–68 · severe > 68".
    static func rangeText(_ m: EchoMeasure, _ sex: EchoSex) -> String {
        guard let r = EchoCalc.ref(m, sex) else { return "" }
        let c = r.cuts.sorted(), f = PedsCalc.fmt
        let inclusive = m.edge == "inclusive"
        let normal: (String) -> String = { fallback in
            if let n = r.normal, n.count == 2 { return "Normal \(f(n[0]))–\(f(n[1]))" }
            return "Normal " + fallback
        }
        if m.isLowWorse {
            if c.count >= 3 { return normal("≥ \(f(c[2]))") + " · mild \(f(c[1]))–\(f(c[2])) · moderate \(f(c[0]))–\(f(c[1])) · severe < \(f(c[0]))" }
            guard let c0 = c.first else { return normal("") }
            return normal((inclusive ? "> " : "≥ ") + f(c0)) + " · \(m.word ?? "abnormal") \(inclusive ? "≤" : "<") \(f(c0))"
        }
        if c.count >= 3 { return normal("≤ \(f(c[0]))") + " · mild \(f(c[0]))–\(f(c[1])) · moderate \(f(c[1]))–\(f(c[2])) · severe > \(f(c[2]))" }
        guard let c0 = c.first else { return normal("") }
        return normal((inclusive ? "< " : "≤ ") + f(c0)) + " · \(m.word ?? "abnormal") \(inclusive ? "≥" : ">") \(f(c0))"
    }

    // MARK: Right-atrial pressure

    private func ivcCard(_ ivc: EchoIVC) -> some View {
        let rap = EchoCalc.rap(ivcCm: WeightField.value(ivcText), collapses: collapses, cut: ivc.cut)
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Right-atrial pressure from the IVC").padding(.leading, 2)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("IVC diameter").font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                        Text(ivc.method ?? "Subcostal, just proximal to the hepatic veins").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    TextField("—", text: $ivcText)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .multilineTextAlignment(.trailing)
                        .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 5)
                        .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .frame(width: 74)
                    Text("cm").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 46, alignment: .leading)
                }
                HStack {
                    Text("Collapses more than 50% with a sniff").font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Picker("Collapse", selection: Binding(get: { collapses.map { $0 ? 1 : 0 } ?? -1 }, set: { collapses = $0 < 0 ? nil : $0 == 1 })) {
                        Text("Yes").tag(1)
                        Text("No").tag(0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
                if let rap {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(rap.value) mmHg").font(PS.serif(size: 28, weight: .semibold)).foregroundStyle(PS.fg)
                        Text("\(rap.label), \(rap.range)").font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg2)
                    }
                } else {
                    Text("Enter the diameter and the collapse.").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
                }
                ForEach(ivc.notes ?? [], id: \.self) { n in
                    Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    // MARK: Footer

    private func footer(_ d: EchoData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            Eyebrow(text: "Sources")
            ForEach(d.sources) { s in
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.citation).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    if let u = s.url, let url = URL(string: u) {
                        Button { onOpen(url) } label: { Text("Open ↗") }.buttonStyle(TextButtonStyle(color: PS.accent, size: 13))
                    }
                }
            }
            ForEach(d.notes ?? [], id: \.self) { n in
                Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
            Text("Reviewed \(d.reviewed.map { PSDate.monthYear($0) } ?? ""). A reference, not a report: measure the way the guideline describes, and read borderline values with the whole study.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The cutoffs as a colored strip (normal green, then mild, moderate, severe) with the value marked.
struct EchoStrip: View {
    var bands: [EchoCalc.Band]
    var value: Double?

    var body: some View {
        let from = bands.first?.from ?? 0, to = bands.last?.to ?? 1
        let span = max(to - from, 0.0001)
        let ticks = bands.dropLast().map(\.to)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(Array(bands.enumerated()), id: \.offset) { _, b in
                        Rectangle()
                            .fill(b.grade == -1 ? PS.surface3 : ChamberQuantView.color(b.grade).opacity(0.85))
                            .frame(width: max(0, w * (b.to - b.from) / span - 2))
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
                .offset(y: 4)
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, t in
                    Text(PedsCalc.fmt(t))
                        .font(PS.mono(size: 9.5, weight: .medium))
                        .foregroundStyle(PS.fg3)
                        .fixedSize()
                        .position(x: w * (t - from) / span, y: 23)
                }
                if let v = value {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(PS.fg)
                        .frame(width: 4, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).stroke(PS.surface, lineWidth: 1.5))
                        .position(x: min(max(0, (v - from) / span), 1) * w, y: 8)
                }
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}
