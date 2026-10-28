import SwiftUI

/// Vasoactive infusions and hematologic agents: the recommended starting dose as labeled, and its
/// equivalent in the other unit for the patient's weight (mcg/kg/min ↔ mcg/min; mg/kg → total).
struct InfusionsView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void

    @AppStorage("ps.la.weight") private var weightText = ""
    @State private var expanded: String?
    @State private var query = ""
    @FocusState private var focused: Bool

    private var weight: Double? {
        let v = Double(weightText.replacingOccurrences(of: ",", with: "."))
        return (v ?? 0) > 0 ? v : nil
    }
    private var groups: [InfusionGroup] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard let data = refs.bundle?.infusions else { return [] }
        if q.isEmpty { return data.groups }
        return data.groups.compactMap { g in
            let hits = g.drugs.filter { ($0.name + " " + $0.use).lowercased().contains(q) }
            return hits.isEmpty ? nil : InfusionGroup(name: g.name, drugs: hits)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if groups.isEmpty {
                    Text(refs.bundle?.infusions == nil ? "Loading the table…" : "No drug matches.").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                }
                ForEach(groups) { g in
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: g.name).padding(.leading, 2)
                        VStack(spacing: 0) {
                            ForEach(Array(g.drugs.enumerated()), id: \.element.id) { i, d in
                                row(d)
                                if i < g.drugs.count - 1 { Hairline().padding(.leading, 16) }
                            }
                        }
                        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                    }
                }
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Infusions and blood")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private var header: some View {
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
                VStack(alignment: .trailing, spacing: 4) {
                    Eyebrow(text: "Find", size: 10)
                    TextField("drug", text: $query)
                        .focused($focused)
                        .font(PS.sys(size: 15))
                        .foregroundStyle(PS.fg)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(width: 130)
                }
            }
            Text(weight == nil ? "Starting doses as labeled; enter a weight to see each one in the other unit (mcg/kg/min ↔ mcg/min) and weight-based doses as totals." : "Starting doses as labeled, with the equivalent at \(PedsCalc.fmt(weight!)) kg. Tap a row for titration, range, maximum and source.")
                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    private func row(_ d: InfusionDrug) -> some View {
        let lines = InfusionCalc.lines(for: d, weightKg: weight)
        let open = expanded == d.id
        return Button {
            withAnimation(.snappy) { expanded = open ? nil : d.id }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(d.name).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                            if d.offLabel == true { Eyebrow(text: "Off-label", color: PS.fg3, size: 9) }
                        }
                        Text(d.use).font(PS.sys(size: 12)).foregroundStyle(PS.fg2).lineLimit(open ? nil : 1)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(lines.dose)
                            .font(PS.sys(size: 14.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PS.fg)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        if let eq = lines.equivalent {
                            Text(eq).font(PS.sys(size: 11.5)).foregroundStyle(PS.accent).lineLimit(1).minimumScaleFactor(0.75)
                        }
                    }
                }
                if open {
                    VStack(alignment: .leading, spacing: 5) {
                        if let t = d.titration { detail("Titration", t) }
                        if let r = d.range { detail("Range", r) }
                        if let m = d.max { detail("Maximum", m) }
                        if let b = d.bolus { detail("Bolus", b) }
                        if let p = d.preparation { detail("Preparation", p) }
                        if let c = d.caution { detail("Caution", c) }
                        if let s = d.source { Text(s).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).lineSpacing(1.5) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detail(_ label: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(PS.mono(size: 9.5, weight: .semibold)).textCase(.uppercase).kerning(0.5).foregroundStyle(PS.fg3).frame(width: 84, alignment: .leading)
            Text(text).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineSpacing(1.5)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            if let n = refs.bundle?.infusions?.note {
                Text(n).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
            Text("Starting points from the labels and the cited guidelines\(refs.bundle?.infusions?.reviewed.map { ", reviewed \(PSDate.monthYear($0))" } ?? ""); titrate to the patient, and check your pump's concentration before programming a rate.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }
}
