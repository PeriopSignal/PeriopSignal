import SwiftUI

/// Medications and hematology: one tab at a time (hemodynamic infusions, single doses, anesthetic
/// infusions, blood products, hematologic drugs), each row just the drug and its starting dose.
/// Tap a row for the indication, titration, range, maximum, preparation, cautions and source.
struct InfusionsView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void

    /// The patient's weight lives only while this list is open.
    @State private var weightText = LaunchSeed.string("ps.la.weight")
    @State private var tab = LaunchSeed.string("ps.inf.tab")
    @State private var expanded: String?
    @State private var query = ""
    @FocusState private var focused: Bool

    private var weight: Double? { WeightField.value(weightText) }
    private var groups: [InfusionGroup] { refs.bundle?.infusions?.groups ?? [] }
    private var tabs: [String] {
        var out: [String] = []
        for g in groups where !out.contains(g.tab ?? g.name) { out.append(g.tab ?? g.name) }
        return out
    }
    private var currentTab: String { tabs.contains(tab) ? tab : (tabs.first ?? "") }
    private var tabGroups: [InfusionGroup] { groups.filter { ($0.tab ?? $0.name) == currentTab } }
    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
    private var searchGroups: [InfusionGroup] {
        groups.compactMap { g in
            let hits = g.drugs.filter { ($0.name + " " + $0.use + " " + ($0.role ?? "")).lowercased().contains(q) }
            return hits.isEmpty ? nil : InfusionGroup(name: g.name, drugs: hits, tab: g.tab)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CompactWeightField(text: $weightText, focus: $focused)
                searchField
                if groups.isEmpty {
                    Text("Loading the table…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                } else if q.isEmpty {
                    tabBar
                    ForEach(tabGroups) { g in
                        section(g, title: tabGroups.count > 1 ? g.name : nil)
                    }
                } else if searchGroups.isEmpty {
                    Text("No drug matches “\(query)”.").font(PS.sys(size: 14)).foregroundStyle(PS.fg3).padding(.top, 8)
                } else {
                    ForEach(searchGroups) { g in
                        section(g, title: [g.tab, g.tab == g.name ? nil : g.name].compactMap { $0 }.joined(separator: " · "))
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
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Medications and Hematology")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg3)
            TextField("Find a drug", text: $query)
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
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs, id: \.self) { t in
                        let on = t == currentTab
                        Button {
                            Haptics.light()
                            withAnimation(.snappy) { tab = t; expanded = nil }
                        } label: {
                            Text(t)
                                .font(PS.sys(size: 13.5, weight: .semibold))
                                .foregroundStyle(on ? PS.bg : PS.fg2)
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                .background(on ? PS.fg : PS.surface, in: Capsule())
                                .overlay(Capsule().stroke(on ? Color.clear : PS.line2, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .id(t)
                    }
                }
                .padding(.horizontal, 1)
            }
            // Keep the selected tab in view (it can start off-screen, e.g. Blood Products).
            .onAppear { proxy.scrollTo(currentTab, anchor: .center) }
            .onChange(of: currentTab) { _, t in withAnimation(.snappy) { proxy.scrollTo(t, anchor: .center) } }
        }
    }

    private func section(_ g: InfusionGroup, title: String?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title { Eyebrow(text: title).padding(.leading, 4).padding(.top, 4) }
            VStack(spacing: 0) {
                ForEach(Array(g.drugs.enumerated()), id: \.element.id) { i, d in
                    row(d)
                    if i < g.drugs.count - 1 { Hairline().padding(.leading, 16) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private func row(_ d: InfusionDrug) -> some View {
        let lines = InfusionCalc.lines(for: d, weightKg: weight)
        let open = expanded == d.id
        let parts = d.nameParts
        return Button {
            withAnimation(.snappy) { expanded = open ? nil : d.id }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(parts.main).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                            if d.offLabel == true { Text("†").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg3) }
                        }
                        if let alias = parts.alias {
                            Text(alias).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(d.display ?? lines.dose)
                            .font(PS.sys(size: 14.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PS.fg)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if let eq = lines.equivalent {
                            Text(eq).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).lineLimit(1).minimumScaleFactor(0.75)
                        }
                    }
                }
                if let t = d.threshold {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "drop.fill").font(PS.sys(size: 9.5)).foregroundStyle(PS.accent)
                        Text(t).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if open { details(d) }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func details(_ d: InfusionDrug) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            detail("Use", d.use + (d.role.map { " · \($0)" } ?? ""))
            if d.offLabel == true { detail("Label", "Off-label use: see the source") }
            if let t = d.titration { detail("Titration", t) }
            if let r = d.range { detail("Range", r) }
            if let m = d.max { detail("Maximum", m) }
            if let b = d.bolus { detail("Bolus", b) }
            if let p = d.preparation { detail("Preparation", p) }
            if let c = d.caution { detail("Caution", c) }
            if let s = d.source { Text(s).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).padding(.top, 2) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detail(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(PS.mono(size: 9.5, weight: .semibold)).textCase(.uppercase).kerning(0.5).foregroundStyle(PS.fg3)
            Text(text).font(PS.sys(size: 13)).foregroundStyle(PS.fg).lineSpacing(1.5)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline().padding(.top, 6)
            Text("† Off-label use. Starting points from the FDA labels and the cited guidelines\(refs.bundle?.infusions?.reviewed.map { ", reviewed \(PSDate.monthYear($0))" } ?? ""); norepinephrine, epinephrine and phenylephrine show the usual operating-room start. Titrate to the patient and check your pump's concentration before programming a rate.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }
}
