import SwiftUI
import UIKit

/// ABG interpretation: pH, PaCO2 and HCO3 in (any two), primary disorder, expected compensation and any second
/// disorder out, with the measured value drawn against the band the rule expects. Rules: AbgCalc; numbers:
/// reference.json "abg". The website has the same tool (src/reference-abg.js).
struct AbgView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void

    @State private var values: [String: String] = Self.seededValues()
    @State private var copied = false
    @FocusState private var focused: Bool

    private var data: AbgData? { refs.bundle?.abg }

    /// DEBUG screenshots: -ps.abg.values "ph=7.28,paco2=30,hco3=14".
    private static func seededValues() -> [String: String] {
        var out: [String: String] = [:]
        for pair in LaunchSeed.list("ps.abg.values") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
    }

    private func num(_ k: String) -> Double? { WeightField.value(values[k] ?? "") }

    private struct Field { var id: String; var label: String; var unit: String }
    private static let fields = [Field(id: "ph", label: "pH", unit: ""), Field(id: "paco2", label: "PaCO₂", unit: "mmHg"), Field(id: "hco3", label: "HCO₃", unit: "mEq/L")]
    private static let order: [(String, String)] = [
        ("metAcid", "Metabolic acidosis"), ("metAlk", "Metabolic alkalosis"),
        ("respAcidAcute", "Acute respiratory acidosis"), ("respAcidChronic", "Chronic respiratory acidosis"),
        ("respAlkAcute", "Acute respiratory alkalosis"), ("respAlkChronic", "Chronic respiratory alkalosis"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let d = data {
                    let r = AbgCalc.read(ph: num("ph"), paco2: num("paco2"), hco3: num("hco3"), data: d)
                    gasCard(d, r)
                    readingCard(r)
                    rulesCard(d)
                    footer(d)
                } else {
                    Text("Loading the rules…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("ABG Interpretation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .sensoryFeedback(.success, trigger: copied)
    }

    // MARK: The gas

    private func range(_ k: String, _ r: [Double]) -> String {
        k == "ph" ? r.map { String(format: "%.2f", $0) }.joined(separator: "–") : r.map { AbgCalc.f1($0) }.joined(separator: "–")
    }

    private func normal(_ d: AbgData, _ k: String) -> [Double] {
        switch k {
        case "ph": return d.normal.ph
        case "paco2": return d.normal.paco2
        default: return d.normal.hco3
        }
    }

    private func derivedValue(_ r: AbgCalc.Reading, _ k: String) -> Double? {
        guard let dv = r.derived else { return nil }
        switch (dv, k) {
        case (.ph, "ph"): return r.values.ph
        case (.paco2, "paco2"): return r.values.paco2
        case (.hco3, "hco3"): return r.values.hco3
        default: return nil
        }
    }

    private func gasCard(_ d: AbgData, _ r: AbgCalc.Reading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Arterial blood gas").padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(Self.fields.enumerated()), id: \.element.id) { i, fld in
                    let n = normal(d, fld.id)
                    let calc = derivedValue(r, fld.id)
                    let shown = num(fld.id) ?? calc
                    let flag: Bool? = shown.map { !($0 >= n[0] && $0 <= n[1]) }
                    let hint = "Normal \(range(fld.id, n))" + (calc != nil ? " · calculated" : (fld.id == "hco3" ? " · leave blank to calculate" : ""))
                    let placeholder = calc.map { "≈ " + (fld.id == "ph" ? AbgCalc.fph($0) : AbgCalc.f1($0)) } ?? "—"
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fld.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                            Text(hint).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        Circle().fill(flag == true ? PS.accent : (flag == false ? PS.green : Color.clear)).frame(width: 8, height: 8)
                        TextField(placeholder, text: Binding(get: { values[fld.id] ?? "" }, set: { values[fld.id] = $0 }))
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .multilineTextAlignment(.trailing)
                            .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PS.fg)
                            .padding(.horizontal, 6).padding(.vertical, 5)
                            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .frame(width: 84)
                            .accessibilityLabel(fld.label + (fld.unit.isEmpty ? "" : " in " + fld.unit))
                        Text(fld.unit).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 46, alignment: .leading)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    if i < Self.fields.count - 1 { Hairline().padding(.leading, 14) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    // MARK: The reading

    private func tone(_ r: AbgCalc.Reading) -> Color {
        if r.empty { return PS.fg3 }
        if r.headline == "Check the Values" { return Topics.info("trauma").fg }
        return r.disorders.isEmpty ? PS.green : PS.accent
    }

    private func stepColor(_ t: AbgCalc.Tone) -> Color {
        switch t {
        case .ok: return PS.green
        case .bad: return PS.accent
        case .info: return PS.accent2
        }
    }

    private func readingCard(_ r: AbgCalc.Reading) -> some View {
        let t = tone(r)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Acid–base", color: t)
                Spacer()
                if !r.empty {
                    Button {
                        UIPasteboard.general.string = AbgCalc.summary(r)
                        copied.toggle()
                    } label: { Text("Copy") }
                    .buttonStyle(GhostButtonStyle())
                }
            }
            Text(r.headline).font(PS.serif(size: 23, weight: .semibold)).foregroundStyle(r.empty ? PS.fg3 : PS.fg).fixedSize(horizontal: false, vertical: true)
            Text(r.explanation).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            if let v = r.visual { AbgStrip(visual: v).padding(.top, 4) }
            if !r.steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(r.steps) { s in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(stepColor(s.tone)).frame(width: 7, height: 7)
                            (Text(s.label).fontWeight(.semibold).foregroundColor(PS.fg) + Text("  " + s.text).foregroundColor(PS.fg2))
                                .font(PS.sys(size: 13)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            ForEach(Array(r.cautions.enumerated()), id: \.offset) { _, c in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(PS.sys(size: 11)).foregroundStyle(PS.accent)
                    Text(c).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: PS.cardRadius, topTrailingRadius: PS.cardRadius)
                .fill(t.opacity(0.9)).frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    // MARK: Rules and sources

    @ViewBuilder private func rulesCard(_ d: AbgData) -> some View {
        let rows: [[String]] = Self.order.compactMap { k, name in d.rules[k].map { [$0.name ?? name, $0.formula ?? ""] } }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Expected compensation").padding(.leading, 2)
                FactTable(rows: rows)
            }
        }
    }

    private func footer(_ d: AbgData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            Eyebrow(text: d.sources.count > 1 ? "Sources" : "Source")
            ForEach(d.sources) { s in
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.citation).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    if let u = s.url, let url = URL(string: u) {
                        Button { onOpen(url) } label: { Text("Open ↗") }.buttonStyle(TextButtonStyle(color: PS.accent, size: 13.5))
                    }
                }
            }
            ForEach((d.notes ?? []) + ["Reviewed \(d.reviewed ?? ""). Interpret the gas with the history, the anion gap and the electrolytes; the rules give a range, not a diagnosis."], id: \.self) { n in
                Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The measured value against the band(s) the rule expects: a track with the bands shaded and a mark at the value.
struct AbgStrip: View {
    var visual: AbgCalc.Visual

    private var bounds: (lo: Double, hi: Double) {
        let vals = visual.bands.flatMap { [$0.lo, $0.hi] } + [visual.measured]
        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
        let pad = max((hi - lo) * 0.2, 2)
        return (max(0, (lo - pad).rounded(.down)), (hi + pad).rounded(.up))
    }

    private func color(_ id: String) -> Color {
        switch id {
        case "acute": return Topics.info("trauma").fg
        case "chronic": return PS.accent2
        default: return PS.green
        }
    }

    var body: some View {
        let b = bounds
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let x: (Double) -> CGFloat = { CGFloat(($0 - b.lo) / (b.hi - b.lo)) * w }
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(PS.surface2).frame(height: 28).offset(y: 18)
                    ForEach(visual.bands) { band in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(color(band.id).opacity(0.32))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(color(band.id).opacity(0.75), lineWidth: 1))
                            .frame(width: max(2, x(band.hi) - x(band.lo)), height: 22)
                            .offset(x: x(band.lo), y: 21)
                    }
                    Text(AbgCalc.f1(visual.measured))
                        .font(PS.sys(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(PS.fg)
                        .fixedSize()
                        .frame(width: 60)
                        .offset(x: min(max(x(visual.measured) - 30, -14), w - 46), y: 0)
                    RoundedRectangle(cornerRadius: 2).fill(PS.fg).frame(width: 3, height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(PS.surface, lineWidth: 2))
                        .offset(x: x(visual.measured) - 1.5, y: 14)
                }
            }
            .frame(height: 50)
            HStack {
                Text(AbgCalc.f1(b.lo))
                Spacer()
                Text("\(visual.variable), \(visual.unit)")
                Spacer()
                Text(AbgCalc.f1(b.hi))
            }
            .font(PS.sys(size: 10.5, design: .monospaced)).foregroundStyle(PS.fg3)
            HStack(spacing: 14) {
                ForEach(visual.bands) { band in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(color(band.id).opacity(0.5)).frame(width: 10, height: 10)
                        Text("\(band.label) \(AbgCalc.f1(band.lo))–\(AbgCalc.f1(band.hi))")
                    }
                }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(PS.fg).frame(width: 3, height: 12)
                    Text("Measured \(AbgCalc.f1(visual.measured))")
                }
            }
            .font(PS.sys(size: 12)).foregroundStyle(PS.fg2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(visual.variable) \(AbgCalc.f1(visual.measured)) \(visual.unit) against " + visual.bands.map { "\($0.label.lowercased()) \(AbgCalc.f1($0.lo)) to \(AbgCalc.f1($0.hi))" }.joined(separator: " and "))
    }
}
