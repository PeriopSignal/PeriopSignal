import SwiftUI
import AudioToolbox

/// The running code, kept while the app runs: leaving the screen and coming back resumes it. Never stored;
/// "End code" clears it.
@Observable final class AclsStore {
    static let shared = AclsStore()

    var state: AclsState?
    /// Shown after "End code" until a new one starts: when it ended and how long it ran.
    var ended: (wall: String, duration: String)?
    var weightText = ""
    var joules = ""
    var confirmEnd = false
    var now = Date()
    /// Alert prompts already sounded, and the cycle whose end already sounded.
    var fired: Set<String> = []
    var lastCycleAlert: Double = -1

    /// Milliseconds since the start of the code.
    var t: Double { state.map { (now.timeIntervalSince1970 - $0.startedAt) * 1000 } ?? 0 }

    func start() {
        var s = AclsState(startedAt: Date().timeIntervalSince1970)
        s.add(0, "start", "Code clock started")
        if let seed = LaunchSeed.string("ps.acls.mode").nilIfEmpty { s.mode = seed }
        if LaunchSeed.string("ps.acls.patient") == "child" { s.patient = "child" }
        if let w = Double(LaunchSeed.string("ps.acls.weight")) { s.weight = w; weightText = LaunchSeed.string("ps.acls.weight") }
        state = s
        ended = nil
        fired = []
        lastCycleAlert = -1
        joules = ""
        confirmEnd = false
        now = Date()
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

/// ACLS: a code clock that starts when the screen opens, the 2-minute CPR cycle with its rhythm-check alert,
/// drug and shock prompts with the patient's doses, decision trees and checklists, and a timestamped log to
/// copy into the record. The screen stays awake while it is open.
struct AclsView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void

    @State private var store = AclsStore.shared
    @State private var copied = false
    @FocusState private var focused: Bool
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private static let wallFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    private func wall(_ ms: Double) -> String { Self.wallFormatter.string(from: Date(timeIntervalSince1970: ms / 1000)) }

    var body: some View {
        Group {
            if let d = refs.bundle?.acls {
                if let ended = store.ended {
                    endedView(ended)
                } else if let s = store.state {
                    content(d, s)
                } else {
                    Color.clear
                }
            } else {
                Text("Loading the reference values…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(FeedBackground())
        .navigationTitle("ACLS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .onAppear {
            if store.state == nil && store.ended == nil { store.start() }
            store.now = Date()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(ticker) { date in
            store.now = date
            checkAlerts()
        }
        .sensoryFeedback(.success, trigger: copied)
    }

    // MARK: Alerts

    /// A prompt marked alert, or the end of a cycle, sounds and vibrates once when it appears.
    private func checkAlerts() {
        guard let d = refs.bundle?.acls, let s = store.state, store.ended == nil else { return }
        let t = store.t
        let active = Set(AclsCalc.prompts(s, d, t).filter(\.alert).map(\.id))
        var fire = !active.subtracting(store.fired).isEmpty
        store.fired = active
        if AclsCalc.mode(s, d)?.cycle == true {
            let c = AclsCalc.cycle(s, d, t)
            if c.elapsed >= d.cycleSec && store.lastCycleAlert != c.from { store.lastCycleAlert = c.from; fire = true }
        }
        if fire {
            AudioServicesPlayAlertSound(SystemSoundID(1007))
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    // MARK: Layout

    private func content(_ d: AclsData, _ s: AclsState) -> some View {
        let t = store.t
        let m = AclsCalc.mode(s, d) ?? d.modes[0]
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if store.confirmEnd { confirmCard(s) }
                if s.patient == "child" {
                    WeightField(text: Binding(get: { store.weightText }, set: { v in
                        store.weightText = v
                        store.state?.weight = WeightField.value(v)
                    }), focus: $focused, prompt: "Enter the weight for the child doses and energies; it clears when the code ends.")
                }
                modeTabs(d, m)
                if let pts = m.patients, !pts.contains(s.patient) {
                    note(m.patientNote ?? "This protocol is written for \(pts.joined(separator: " and ")) patients.", warn: true)
                }
                if let n = m.note { note(n) }
                deadlines(d, s, t)
                prompts(d, s, t, m)
                if let tr = AclsCalc.tree(s, d) { treeCard(d, s, t, tr) }
                ForEach(Array((m.groups ?? []).enumerated()), id: \.offset) { _, g in group(d, s, t, g) }
                ForEach((m.lists ?? []).filter { $0.patient == nil || $0.patient == s.patient }, id: \.id) { l in checklist(s, l) }
                logSection(s)
                footer(d, m)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { clockBar(d, s, t, m) }
    }

    private func clockBar(_ d: AclsData, _ s: AclsState, _ t: Double, _ m: AclsMode) -> some View {
        let cyc = m.cycle == true ? AclsCalc.cycle(s, d, t) : nil
        let left = cyc.map { d.cycleSec - $0.elapsed } ?? 0
        let alarm = cyc != nil && left <= 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AclsCalc.clock(t)).font(PS.sys(size: 40, weight: .semibold, design: .monospaced)).foregroundStyle(PS.fg).monospacedDigit().contentTransition(.numericText())
                    Text("Code time · started \(wall(s.startedAt * 1000))").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                }
                Spacer(minLength: 8)
                if cyc != nil {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(left > 0 ? AclsCalc.clock(left * 1000) : "Now").font(PS.sys(size: 26, weight: .semibold, design: .monospaced)).foregroundStyle(alarm ? PS.accent : PS.fg).monospacedDigit()
                        Text(left > 0 ? "Rhythm check in" : "Rhythm check").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                    }
                }
            }
            if let cyc {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(PS.surface3)
                        Capsule().fill(alarm ? PS.accent : PS.green).frame(width: geo.size.width * min(1, max(0, cyc.elapsed / d.cycleSec)))
                    }
                }
                .frame(height: 6)
            }
            HStack(spacing: 12) {
                Picker("Patient", selection: Binding(get: { s.patient }, set: { v in
                    guard store.state?.patient != v else { return }
                    store.state?.patient = v
                    store.state?.add(store.t, nil, "Patient: \(v)")
                })) {
                    Text("Adult").tag("adult")
                    Text("Child").tag("child")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                Spacer()
                Button { withAnimation(.snappy) { store.confirmEnd.toggle() } } label: { Text("End code") }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(16)
        .background(alarm ? PS.accent.opacity(0.12) : PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(alarm ? PS.accent : PS.line2, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func confirmCard(_ s: AclsState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            (Text("End this code? ").fontWeight(.semibold) + Text("The clock stops and the log is cleared; copy it first if you need it."))
                .font(PS.sys(size: 14)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { copyLog(s) } label: { Label("Copy log", systemImage: "doc.on.doc") }.buttonStyle(GhostButtonStyle())
                Button {
                    store.ended = (wall(Date().timeIntervalSince1970 * 1000), AclsCalc.clock(store.t))
                    store.state = nil
                    store.confirmEnd = false
                    store.weightText = ""
                } label: { Text("End code").foregroundStyle(PS.accent) }.buttonStyle(GhostButtonStyle())
                Button { store.confirmEnd = false } label: { Text("Keep going") }.buttonStyle(GhostButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(PS.accent.opacity(0.45), lineWidth: 1))
    }

    private func endedView(_ e: (wall: String, duration: String)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Code ended")
            Text("Ended at \(e.wall) after \(e.duration)").font(PS.serif(size: 24, weight: .semibold)).foregroundStyle(PS.fg)
            Text("The clock is stopped and the log was cleared.").font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
            Button { store.start() } label: { Text("Start a new code") }.buttonStyle(GhostButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func modeTabs(_ d: AclsData, _ m: AclsMode) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(d.modes) { x in
                    let on = x.id == m.id
                    Button {
                        guard !on else { return }
                        Haptics.light()
                        withAnimation(.snappy) {
                            store.state?.mode = x.id
                            store.state?.add(store.t, nil, "Switched to \(x.name)")
                        }
                    } label: {
                        Text(x.short ?? x.name)
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

    private func note(_ text: String, warn: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if warn { Image(systemName: "exclamationmark.triangle.fill").font(PS.sys(size: 11)).foregroundStyle(PS.accent) }
            Text(text).font(PS.sys(size: 12.5)).foregroundStyle(warn ? PS.fg : PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }

    // MARK: Deadlines and prompts

    @ViewBuilder private func deadlines(_ d: AclsData, _ s: AclsState, _ t: Double) -> some View {
        let dl = AclsCalc.deadlines(s, d, t)
        if !dl.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(dl) { x in
                    let over = x.remaining <= 0, near = x.remaining <= 60
                    HStack {
                        Text(x.label).font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(over ? PS.accent : PS.fg)
                        Spacer()
                        Text(over ? AclsCalc.clock(-x.remaining * 1000) + " over" : AclsCalc.clock(x.remaining * 1000) + " left")
                            .font(PS.sys(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(over ? PS.accent : near ? Topics.info("trauma").fg : PS.fg2).monospacedDigit()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(PS.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(over ? PS.accent : near ? Topics.info("trauma").fg : PS.line2, lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder private func prompts(_ d: AclsData, _ s: AclsState, _ t: Double, _ m: AclsMode) -> some View {
        let cyc = m.cycle == true ? AclsCalc.cycle(s, d, t) : nil
        let due = cyc.map { $0.elapsed >= d.cycleSec } ?? false
        let list = (due ? [AclsPromptNow(id: "cycle", level: "now", text: m.cycleText ?? "Rhythm check: pause compressions under 10 seconds, switch compressors, then log the rhythm.", action: nil, alert: true)] : []) + AclsCalc.prompts(s, d, t)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(list) { p in
                    HStack(spacing: 12) {
                        Text(p.text).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        if let id = p.action, let a = d.actions[id] {
                            Button { log(d, id) } label: {
                                Text(a.kind == "shock" ? "Shock given" : a.kind == "drug" ? "Given" : "Done")
                                    .font(PS.sys(size: 13.5, weight: .bold)).foregroundStyle(PS.bg)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(PS.fg, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(p.level == "now" ? PS.accent.opacity(0.12) : p.level == "soon" ? Topics.info("trauma").fg.opacity(0.10) : PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.level == "now" ? PS.accent : p.level == "soon" ? Topics.info("trauma").fg.opacity(0.7) : PS.line2, lineWidth: 1))
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: Actions

    private func log(_ d: AclsData, _ id: String) {
        guard let a = d.actions[id], var s = store.state else { return }
        let n = AclsCalc.count(s, id)
        guard n < AclsCalc.maxDoses(a, s) else { return }
        Haptics.light()
        s.add(store.t, id, AclsCalc.entryText(a, s, n, joules: Double(store.joules.replacingOccurrences(of: ",", with: "."))))
        if let g = a.goto, let target = d.modes.first(where: { $0.id == g }) {
            s.mode = g
            s.add(store.t, nil, "Switched to \(target.name)")
        }
        withAnimation(.snappy) { store.state = s }
    }

    private func group(_ d: AclsData, _ s: AclsState, _ t: Double, _ g: AclsGroup) -> some View {
        let ids = g.actions.filter { id in d.actions[id].map { $0.patients == nil || $0.patients!.contains(s.patient) } ?? false }
        let shockID = ids.first { d.actions[$0]?.kind == "shock" }
        return VStack(alignment: .leading, spacing: 8) {
            if !ids.isEmpty {
                Eyebrow(text: g.title).padding(.leading, 2)
                if let sid = shockID, let a = d.actions[sid] {
                    let e = AclsCalc.energy(a, s, AclsCalc.count(s, sid))
                    HStack {
                        Text("Energy used for the next shock").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
                        Spacer()
                        TextField(e?.joules.map { String($0) } ?? "J", text: $store.joules)
                            .keyboardType(.numberPad)
                            .focused($focused)
                            .multilineTextAlignment(.trailing)
                            .font(PS.sys(size: 16, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .frame(width: 84)
                        Text("J").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                    }
                }
                actionGrid(d, s, t, ids)
                if let n = g.note { note(n) }
            }
        }
    }

    private func actionGrid(_ d: AclsData, _ s: AclsState, _ t: Double, _ ids: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(ids, id: \.self) { id in
                if let a = d.actions[id] { actionButton(d, s, t, id, a) }
            }
        }
    }

    private func actionButton(_ d: AclsData, _ s: AclsState, _ t: Double, _ id: String, _ a: AclsAction) -> some View {
        let n = AclsCalc.count(s, id), full = n >= AclsCalc.maxDoses(a, s)
        let detail: String = {
            switch a.kind {
            case "drug": return AclsCalc.dose(a, s, n)?.text ?? ""
            case "shock": return AclsCalc.energy(a, s, n)?.text ?? ""
            default: return a.detail ?? ""
            }
        }()
        let tm = AclsCalc.timer(a, s, id, t)
        let border: Color = {
            switch a.kind {
            case "shock": return PS.accent.opacity(0.55)
            case "rhythm": return a.rhythm == "shockable" ? PS.accent.opacity(0.55) : a.rhythm == "rosc" ? PS.green.opacity(0.6) : PS.accent2.opacity(0.55)
            default: return PS.line2
            }
        }()
        return Button { log(d, id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(a.label).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg).multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if n > 0 { Text("×\(n)").font(PS.mono(size: 12, weight: .medium)).foregroundStyle(PS.fg3) }
                }
                if !detail.isEmpty {
                    Text(detail).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                if full {
                    Text("Max doses given").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                } else if let tm {
                    switch tm.state {
                    case "wait": Text("Next in \(AclsCalc.clock(tm.remaining * 1000))").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3).monospacedDigit()
                    case "due": Text("Due now").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(Topics.info("trauma").fg)
                    default: Text("Overdue \(AclsCalc.clock((tm.since - (a.repeats?.max ?? tm.since)) * 1000))").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.accent).monospacedDigit()
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(border, lineWidth: 1))
            .opacity(full ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(full)
    }

    // MARK: Decision tree

    private func treeCard(_ d: AclsData, _ s: AclsState, _ t: Double, _ tr: (tree: AclsTree, path: [String], node: AclsNode, nodeId: String)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: tr.tree.title ?? "Algorithm").padding(.leading, 2)
            VStack(alignment: .leading, spacing: 10) {
                if !tr.path.isEmpty {
                    HStack(alignment: .center, spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(tr.path.enumerated()), id: \.offset) { _, id in
                                    let nd = tr.tree.nodes[id]
                                    Text(nd?.crumb ?? nd?.q ?? nd?.title ?? "").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                                        .padding(.horizontal, 9).padding(.vertical, 3)
                                        .background(PS.surface2, in: Capsule())
                                }
                            }
                        }
                        Button {
                            guard var st = store.state else { return }
                            AclsCalc.back(&st, d)
                            withAnimation(.snappy) { store.state = st }
                        } label: { Label("Back", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(TextButtonStyle(color: PS.accent2, size: 13))
                    }
                }
                if let ti = tr.node.title { Text(ti).font(PS.serif(size: 19, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true) }
                if let tx = tr.node.text { Text(tx).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true) }
                if let items = tr.node.items, !items.isEmpty { TakeHomeList(items: items, size: 13.5) }
                if let q = tr.node.q, let opts = tr.node.options {
                    Text(q).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(opts.enumerated()), id: \.offset) { _, o in
                            Button {
                                guard var st = store.state else { return }
                                Haptics.light()
                                AclsCalc.choose(&st, d, store.t, next: o.next, label: o.label)
                                withAnimation(.snappy) { store.state = st }
                            } label: {
                                Text(o.label).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg).multilineTextAlignment(.leading)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PS.line2, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let acts = tr.node.actions?.filter({ d.actions[$0] != nil }), !acts.isEmpty { actionGrid(d, s, t, acts) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    // MARK: Checklists and log

    private func checklist(_ s: AclsState, _ l: AclsList) -> some View {
        let key: (AclsItem) -> String = { "chk:\(l.id):\($0.id)" }
        let done = l.items.filter { AclsCalc.count(s, key($0)) > 0 }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(l.title).font(PS.serif(size: 17, weight: .semibold)).foregroundStyle(PS.fg)
                Spacer()
                Text("\(done)/\(l.items.count)").font(PS.mono(size: 12, weight: .medium)).foregroundStyle(done == l.items.count ? PS.green : PS.fg3)
            }
            .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(l.items.enumerated()), id: \.element.id) { i, item in
                    let on = AclsCalc.count(s, key(item)) > 0
                    ChecklistItemRow(number: i + 1, text: item.label + (item.detail.map { " — " + $0 } ?? ""), done: on, tint: PS.accent) {
                        guard var st = store.state else { return }
                        if on { if let e = st.log.last(where: { $0.action == key(item) }) { st.remove(e) } }
                        else { st.add(store.t, key(item), "\(l.verb ?? "Done"): \(item.label)") }
                        store.state = st
                    }
                    if i < l.items.count - 1 { Hairline().padding(.leading, 38) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            if let n = l.note { note(n) }
        }
    }

    private func copyLog(_ s: AclsState) {
        UIPasteboard.general.string = AclsCalc.logText(s) { wall($0) }
        copied.toggle()
    }

    private func logSection(_ s: AclsState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: "Log · \(s.log.count) \(s.log.count == 1 ? "entry" : "entries")")
                Spacer()
                Button { copyLog(s) } label: { Label("Copy log", systemImage: "doc.on.doc") }.buttonStyle(GhostButtonStyle())
            }
            .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(s.log.reversed().enumerated()), id: \.element.id) { i, e in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(wall(s.startedAt * 1000 + e.t)).font(PS.mono(size: 11.5, weight: .medium)).foregroundStyle(PS.fg3)
                        Text("+" + AclsCalc.clock(e.t)).font(PS.mono(size: 11.5, weight: .medium)).foregroundStyle(PS.fg3)
                        Text(e.text).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if e.action != "start" {
                            Button {
                                guard var st = store.state else { return }
                                st.remove(e)
                                withAnimation(.snappy) { store.state = st }
                            } label: { Image(systemName: "xmark").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3).frame(width: 26, height: 26) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove this entry")
                        }
                    }
                    .padding(.vertical, 8)
                    if i < s.log.count - 1 { Hairline() }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            Text("Clock times are this phone's; the log stays in the app while it runs and clears when the code ends.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
        }
    }

    private func footer(_ d: AclsData, _ m: AclsMode) -> some View {
        let src = (m.sources ?? []).compactMap { id in d.sources.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 10) {
            Hairline()
            Eyebrow(text: "Sources")
            ForEach(src) { s in
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
            Text("Reviewed \(d.reviewed.map { PSDate.monthYear($0) } ?? ""). Prompts follow the guideline sequence; the team leader decides.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }
}
