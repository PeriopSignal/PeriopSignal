import SwiftUI

/// Vasoactive infusions and hematologic agents: the recommended starting dose as labeled, and its
/// equivalent in the other unit for the patient's weight (mcg/kg/min ↔ mcg/min; mg/kg → total).
struct InfusionsView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void

    /// The patient's weight lives only while this table is open.
    @State private var weightText = LaunchSeed.string("ps.la.weight")
    @State private var expanded: String?
    @State private var query = ""
    @FocusState private var focused: Bool

    private var weight: Double? { WeightField.value(weightText) }
    private var groups: [InfusionGroup] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard let data = refs.bundle?.infusions else { return [] }
        if q.isEmpty { return data.groups }
        return data.groups.compactMap { g in
            let hits = g.drugs.filter { ($0.name + " " + $0.use + " " + ($0.role ?? "")).lowercased().contains(q) }
            return hits.isEmpty ? nil : InfusionGroup(name: g.name, drugs: hits)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if groups.count > 1 { jumpChips(proxy) }
                    if groups.isEmpty {
                        Text(refs.bundle?.infusions == nil ? "Loading the table…" : "No drug matches.").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                    }
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(g.name.titleCased).font(PS.serif(size: 18)).foregroundStyle(PS.fg)
                                Spacer()
                                Text("\(g.drugs.count)").font(PS.mono(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                            }
                            .padding(.leading, 2)
                            VStack(spacing: 0) {
                                ForEach(Array(g.drugs.enumerated()), id: \.element.id) { i, d in
                                    row(d)
                                    if i < g.drugs.count - 1 { Hairline().padding(.leading, 16) }
                                }
                            }
                            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                        }
                        .id(g.name)
                    }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .onAppear {
                // CI screenshots: -ps.inf.group "Blood Products" opens the table at that group.
                let g = LaunchSeed.string("ps.inf.group")
                if !g.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo(g, anchor: .top) } }
            }
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Infusions and Blood")
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
            WeightField(text: $weightText, focus: $focused, prompt: "Enter the weight to see every dose in the other unit (mcg/kg/min ↔ mcg/min) and weight-based doses as totals.")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg3)
                TextField("Find a drug or class", text: $query)
                    .focused($focused)
                    .font(PS.sys(size: 15))
                    .foregroundStyle(PS.fg)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PS.fg3) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Starting doses as labeled (operating-room starts where the editor set them). Tap a row for titration, range, maximum, preparation and source.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    private func jumpChips(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groups) { g in
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { proxy.scrollTo(g.name, anchor: .top) }
                    } label: {
                        Text(g.name.titleCased)
                            .font(PS.sys(size: 12.5, weight: .semibold))
                            .foregroundStyle(PS.fg2)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(PS.surface, in: Capsule())
                            .overlay(Capsule().stroke(PS.line2, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func row(_ d: InfusionDrug) -> some View {
        let lines = InfusionCalc.lines(for: d, weightKg: weight)
        let open = expanded == d.id
        return Button {
            withAnimation(.snappy) { expanded = open ? nil : d.id }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(d.name).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            if d.offLabel == true { Eyebrow(text: "Off-label", color: PS.fg3, size: 8.5) }
                        }
                        HStack(spacing: 5) {
                            if let r = d.role { RoleTag(role: r) }
                            Text(d.use).font(PS.sys(size: 11)).foregroundStyle(PS.fg3).lineLimit(open ? nil : 1)
                        }
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(d.display ?? lines.dose)
                            .font(PS.sys(size: 14.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PS.fg)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if let eq = lines.equivalent {
                            Text(eq).font(PS.sys(size: 11.5)).foregroundStyle(PS.accent).lineLimit(1).minimumScaleFactor(0.75)
                        }
                    }
                }
                if let t = d.threshold {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "drop.fill").font(PS.sys(size: 10)).foregroundStyle(PS.accent)
                        Text(t).font(PS.sys(size: 12.5, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PS.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
