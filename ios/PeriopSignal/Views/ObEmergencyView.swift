import SwiftUI

/// OB Emergencies: one checklist per obstetric crisis (maternal cardiac arrest, hemorrhage and the rest), the doses
/// for the patient's weight, and for the arrest a clock with its 4- and 5-minute marks. Built from the primary
/// sources; the Stanford Obstetric Anesthesia Emergency Manual is linked, not reproduced. Content: reference.json
/// "obEmergency"; the website has the same tool (src/reference-ob.js). Nothing is stored: the weight, ticks and
/// clocks live only while the screen is open.
struct ObEmergencyView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void

    @State private var eventId = LaunchSeed.string("ps.ob.event")
    /// Weights by whose they are: "" is the mother's; an event's `weightFor.key` (the newborn) has its own.
    @State private var weights: [String: String] = ["": LaunchSeed.string("ps.la.weight"), "newborn": LaunchSeed.string("ps.ob.newborn")]
    /// Ticked steps: event → section → items.
    @State private var done: [String: [Int: Set<Int>]] = [:]
    @State private var clocks: [String: Date] = [:]
    @FocusState private var focused: Bool

    private var data: ObEmergencyData? { refs.bundle?.obEmergency }
    private let tint = PS.accent

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let d = data, let ev = d.events.first(where: { $0.id == eventId }) ?? d.events.first {
                        tabs(d, ev).id("top")
                        header(ev)
                        if let tm = ev.timer { clockCard(ev, tm) }
                        if let doses = ev.weightDoses, !doses.isEmpty { weightCard(ev, doses) }
                        let checklist = ev.sections.indices.filter { ev.sections[$0].kind == .steps }
                        let total = checklist.reduce(0) { $0 + (ev.sections[$1].items?.count ?? 0) }
                        if total > 0 {
                            ChecklistProgress(done: doneCount(ev), total: total, tint: tint, title: "Emergency Checklist") { done[ev.id] = [:] }
                                .padding(14)
                                .background(PS.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1))
                        }
                        ForEach(Array(ev.sections.enumerated()), id: \.offset) { i, section in
                            RefSectionView(section: section, tint: tint,
                                           done: checklist.contains(i) ? Binding(get: { done[ev.id]?[i] ?? [] }, set: { done[ev.id, default: [:]][i] = $0 }) : nil)
                        }
                        footer(d, ev)
                    } else {
                        Text("Loading…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .onChange(of: eventId) { _, _ in withAnimation(.snappy) { proxy.scrollTo("top", anchor: .top) } }
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("OB Emergencies")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private func doneCount(_ ev: ObEvent) -> Int { (done[ev.id] ?? [:]).values.reduce(0) { $0 + $1.count } }

    private func tabs(_ d: ObEmergencyData, _ ev: ObEvent) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(d.events) { e in
                    let on = e.id == ev.id
                    Button { withAnimation(.snappy) { eventId = e.id } } label: {
                        Text(e.short ?? e.title)
                            .font(PS.sys(size: 14, weight: .semibold))
                            .foregroundStyle(on ? PS.bg : PS.fg2)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(on ? PS.fg : PS.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func header(_ ev: ObEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Emergency checklist", color: PS.accent)
            Text(ev.title.titleCased)
                .font(PS.serif(size: 25, weight: .semibold))
                .foregroundStyle(PS.fg)
                .fixedSize(horizontal: false, vertical: true)
            if let s = ev.summary {
                Text(s).font(PS.sys(size: 15)).foregroundStyle(PS.fg2).lineSpacing(2.5).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    private func clockCard(_ ev: ObEvent, _ tm: ObTimer) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let start = clocks[ev.id]
            let el = start.map { ctx.date.timeIntervalSince($0) } ?? 0
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: tm.label ?? "Clock", color: tint)
                        Text(Self.clock(el))
                            .font(PS.mono(size: 40, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(PS.fg)
                    }
                    Spacer()
                    if start == nil {
                        Button { Haptics.light(); clocks[ev.id] = Date() } label: { Text(tm.start ?? "Start the clock") }
                            .buttonStyle(CapsuleButtonStyle())
                    } else {
                        Button { clocks[ev.id] = nil } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(GhostButtonStyle())
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(tm.marks.enumerated()), id: \.offset) { _, m in
                        let past = start != nil && el >= m.sec
                        let near = start != nil && !past && el >= m.sec - 60
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Self.clock(m.sec))
                                .font(PS.mono(size: 13, weight: .bold))
                                .foregroundStyle(past || near ? PS.accent : PS.fg3)
                                .frame(width: 46, alignment: .leading)
                            Text(m.text).font(PS.sys(size: 14)).foregroundStyle(past || near ? PS.fg : PS.fg2).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background((past ? PS.accent.opacity(0.16) : near ? Topics.info("trauma").fg.opacity(0.14) : PS.surface2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                if let n = tm.note { Text(n).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(start == nil ? Color.clear : tint.opacity(0.45), lineWidth: 1))
        }
    }

    private func weightCard(_ ev: ObEvent, _ doses: [WeightDose]) -> some View {
        let wf = ev.weightFor
        let key = wf?.key ?? ""
        let entered = WeightField.value(weights[key] ?? "")
        var tooHigh = false
        if let e = entered, let m = wf?.maxKg { tooHigh = e > m }
        let weight = tooHigh ? nil : entered
        return VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: wf?.eyebrow ?? "Doses for this patient", color: tint)
            WeightField(text: Binding(get: { weights[key] ?? "" }, set: { weights[key] = $0 }), focus: $focused,
                        prompt: wf?.prompt ?? "Enter the weight: the doses below are per kilogram until you do.",
                        title: wf?.title ?? "Patient Weight")
            if tooHigh {
                Label(wf?.maxText ?? "Check the weight.", systemImage: "exclamationmark.triangle.fill")
                    .font(PS.sys(size: 13, weight: .semibold))
                    .foregroundStyle(PS.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(doses.enumerated()), id: \.element.id) { i, d in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.label).font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                            if let n = d.note { Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                        }
                        Spacer(minLength: 8)
                        Text(computed(d, weight))
                            .font(PS.sys(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(weight == nil ? PS.fg3 : PS.fg)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 9)
                    if i < doses.count - 1 { Hairline() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1))
    }

    private func computed(_ d: WeightDose, _ weight: Double?) -> String {
        guard let w = weight else {
            return PedsCalc.fmt(d.perKg) + (d.perKgHigh.map { "–" + PedsCalc.fmt($0) } ?? "") + " \(d.unit)/kg"
        }
        if let above = d.aboveKg, w > above, let text = d.aboveText { return text }
        return PedsCalc.doseText(low: d.perKg, high: d.perKgHigh, unit: d.unit, weightKg: w, max: d.max).text
    }

    private func footer(_ d: ObEmergencyData, _ ev: ObEvent) -> some View {
        let srcs = (ev.sources ?? []).compactMap { id in d.sources?.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 10) {
            Hairline()
            Eyebrow(text: srcs.count > 1 ? "Sources" : "Source")
            ForEach(srcs) { s in
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.citation).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    if let u = s.url, let url = URL(string: u) {
                        Button { onOpen(url) } label: { Text("Open ↗") }.buttonStyle(TextButtonStyle(color: PS.accent, size: 13.5))
                    }
                }
            }
            if let m = d.manual {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: m.title)
                    if let n = m.note { Text(n).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                    if let u = m.url, let url = URL(string: u) {
                        Button { onOpen(url) } label: { Text("Open the manual ↗") }.buttonStyle(TextButtonStyle(color: PS.accent, size: 13.5))
                    }
                }
                .padding(.top, 4)
            }
            ForEach(d.notes ?? [], id: \.self) { n in
                Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
            Text("Condensed by Periop Signal\(d.reviewed.map { ", reviewed " + $0 } ?? ""). A checklist to prompt, not a protocol: follow your institution’s obstetric emergency plan and confirm doses against the sources.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }
}
