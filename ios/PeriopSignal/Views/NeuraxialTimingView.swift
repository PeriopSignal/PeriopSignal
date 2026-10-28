import SwiftUI

/// "When can I block?" — the drug, its dose tier, kidney function and the last dose time in, the
/// earliest neuraxial or deep block, the catheter policy and the next-dose rule out (ASRA fifth edition).
struct NeuraxialTimingView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void
    var onOpenTable: () -> Void

    @State private var drugID: String?
    @State private var tierID: String?
    @State private var renalIndex = 0
    @State private var elderly = false
    @State private var lastDose = Date()
    @State private var now = Date()
    @State private var showGeneral = false

    private var data: NeuraxialData? { refs.bundle?.neuraxial }
    private var drug: NeuraxialDrug? { data?.allDrugs.first { $0.id == drugID } }
    private var tier: NeuraxialTier? {
        guard let d = drug else { return nil }
        return d.tiers.first { $0.id == tierID } ?? d.tiers.first
    }
    private var answer: NeuraxialCalc.Answer? {
        tier.map { NeuraxialCalc.answer(tier: $0, renalIndex: renalIndex, elderly: elderly, lastDose: lastDose) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                drugStep
                if let d = drug {
                    if d.tiers.count > 1 { tierStep(d) }
                    if let r = tier?.renal, !r.isEmpty { renalStep(r) }
                    lastDoseStep
                    if let a = answer { result(a) }
                    if let t = tier { catheterAndRestart(t, d) }
                }
                general
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Anticoagulation and blocks")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    // MARK: Steps

    private var drugStep: some View {
        step(number: 1, title: "Which drug?") {
            if let data {
                Menu {
                    ForEach(data.groups) { g in
                        Section(g.name) {
                            ForEach(g.drugs) { d in
                                Button(d.name) { select(d) }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(drug?.name ?? "Choose the antithrombotic")
                            .font(PS.sys(size: 15.5, weight: .semibold))
                            .foregroundStyle(drug == nil ? PS.accent : PS.fg)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.fg3)
                    }
                    .padding(12)
                    .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            } else {
                Text("Loading the rules…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
            }
        }
    }

    private func tierStep(_ d: NeuraxialDrug) -> some View {
        step(number: 2, title: "Which dose?") {
            VStack(spacing: 0) {
                ForEach(d.tiers) { t in
                    let on = tier?.id == t.id
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { tierID = t.id; renalIndex = 0 }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: on ? "largecircle.fill.circle" : "circle").font(PS.sys(size: 16)).foregroundStyle(on ? PS.accent : PS.fg3)
                            Text(t.label).font(PS.sys(size: 14, weight: on ? .semibold : .regular)).foregroundStyle(PS.fg).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func renalStep(_ rules: [RenalRule]) -> some View {
        step(number: drug.map { $0.tiers.count > 1 ? 3 : 2 } ?? 2, title: "Kidney function?") {
            VStack(spacing: 0) {
                ForEach(Array(rules.enumerated()), id: \.offset) { i, r in
                    let on = renalIndex == i
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { renalIndex = i }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: on ? "largecircle.fill.circle" : "circle").font(PS.sys(size: 16)).foregroundStyle(on ? PS.accent : PS.fg3)
                            Text(r.label).font(PS.sys(size: 14, weight: on ? .semibold : .regular)).foregroundStyle(PS.fg)
                            Spacer(minLength: 0)
                            if let h = r.hours { Text(NeuraxialCalc.fmtHours(h)).font(PS.mono(size: 11, weight: .semibold)).foregroundStyle(PS.fg3) }
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if rules.contains(where: { $0.elderlyHours != nil }) {
                    Toggle(isOn: $elderly) {
                        Text("Elderly patient").font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg)
                    }
                    .tint(PS.accent)
                    .padding(.top, 6)
                }
            }
        }
    }

    private var lastDoseStep: some View {
        let n = 2 + (drug.map { $0.tiers.count > 1 ? 1 : 0 } ?? 0) + ((tier?.renal?.isEmpty == false) ? 1 : 0)
        return step(number: n, title: "Last dose was at") {
            DatePicker("Last dose", selection: $lastDose, in: ...Date().addingTimeInterval(3600), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(PS.accent)
            if let t = tier, t.inrRule == true {
                Text("Warfarin counts in days: the block needs a normal INR on the day, whatever the calendar says.").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Result

    private func result(_ a: NeuraxialCalc.Answer) -> some View {
        let passed = a.earliest.map { $0 <= now } ?? false
        let tone: Color = a.avoid ? PS.accent : (passed ? PS.green : PS.accent2)
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Earliest neuraxial or deep block", color: tone)
            if a.avoid {
                Text("Avoid").font(PS.serif(size: 34, weight: .semibold)).foregroundStyle(PS.accent)
            } else if let e = a.earliest, let h = a.hours, h > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Self.when.string(from: e)).font(PS.serif(size: 30, weight: .semibold)).foregroundStyle(PS.fg)
                    Text(passed ? "now" : NeuraxialCalc.countdown(to: e, from: now)).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(tone)
                }
            } else if a.hours == 0 {
                Text("Now").font(PS.serif(size: 34, weight: .semibold)).foregroundStyle(PS.green)
            } else {
                Text("No interval").font(PS.serif(size: 26, weight: .semibold)).foregroundStyle(PS.fg)
            }
            Text(a.rule).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            if let l = tier?.level {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "testtube.2").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                    Text(l).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let r = tier?.renalNote {
                Text(r).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
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
        .animation(.snappy, value: a)
    }

    private func catheterAndRestart(_ t: NeuraxialTier, _ d: NeuraxialDrug) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let c = t.catheter {
                fact("Catheter in place", c)
                Hairline()
            }
            fact("Next dose", t.restartText ?? (t.restartHours.map { $0 == 0 ? "No interval after the block or catheter removal" : "\(NeuraxialCalc.fmtHours($0)) after needle placement or catheter removal" } ?? "Not specified"))
            if let notes = d.notes, !notes.isEmpty {
                Hairline()
                fact("Also", notes.joined(separator: " "))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    private func fact(_ label: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2).frame(width: 104, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Text(text).font(PS.sys(size: 14)).foregroundStyle(PS.fg).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    // MARK: Ground rules and footer

    private var general: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { showGeneral.toggle() } } label: {
                HStack {
                    Eyebrow(text: "Ground rules that apply to every drug")
                    Spacer()
                    Image(systemName: showGeneral ? "chevron.up" : "chevron.down").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.fg3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showGeneral, let g = data?.general { TakeHomeList(items: g, size: 13.5) }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            HStack(spacing: 10) {
                Button(action: onOpenTable) { Label("Full ASRA table", systemImage: "tablecells") }.buttonStyle(GhostButtonStyle())
                if let s = data?.sourceURL, let url = URL(string: s) {
                    Button { onOpen(url) } label: { Label("Guideline ↗", systemImage: "doc.text") }.buttonStyle(GhostButtonStyle())
                }
            }
            Text("ASRA Pain Medicine, fifth edition (2025)\(data?.reviewed.map { "; reviewed \(PSDate.monthYear($0))" } ?? ""). The interval is the guideline's minimum for a patient on this drug alone; combinations, kidney function and age push it out, and a bloody tap or a catheter changes the plan — the guideline and your judgement decide.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Helpers

    private func select(_ d: NeuraxialDrug) {
        Haptics.light()
        withAnimation(.snappy) {
            drugID = d.id
            tierID = d.tiers.first?.id
            renalIndex = 0
        }
    }

    private func step<Content: View>(number: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(number)").font(PS.mono(size: 11)).foregroundStyle(PS.accent).frame(width: 22, height: 22).background(PS.accent.opacity(0.12), in: Circle())
                Text(title).font(PS.serif(size: 17)).foregroundStyle(PS.fg)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    private static let when: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE d MMM, HH:mm"
        return f
    }()
}
