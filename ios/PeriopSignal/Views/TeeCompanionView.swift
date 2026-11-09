import SwiftUI

// MARK: - TEE companion
//
// Reference → Cardiothoracic. Two questions (which surgery, before or after bypass) bring up what to check and report
// (Nicoara 2020) and, after bypass, what to compare against the pre-bypass exam; the 28 views (Hahn 2013) with Reeves'
// basic 11 sit behind "Views". A checklist, not the formal echo report. reference.json "tee", a draft until signed off.

struct TeeCompanionView: View {
    var onOpen: (URL) -> Void
    var onOpenTool: (RefRoute) -> Void
    @Environment(ReferenceStore.self) private var refs
    @Environment(TipCenter.self) private var tips
    @Environment(PatientStore.self) private var patient
    /// The handoff just added to My Patient (for its Undo), cleared when anything changes.
    @State private var handedOff: (before: PatientRecord, after: PatientRecord)?
    @State private var surgery = "cabg"
    @State private var post = false
    @State private var checked: Set<String> = []
    @State private var found: Set<String> = []
    @State private var viewsOpen = false
    @State private var basicOnly = false
    @State private var practiceOpen = false

    var body: some View {
        Group {
            if let d = refs.tee {
                ToolScroll {
                    VStack(alignment: .leading, spacing: 18) {
                        ToolHeader(eyebrow: "Cardiothoracic", title: "TEE Companion",
                                   summary: "Pick the surgery and the phase: what to check and report, and after bypass, what to compare with before.",
                                   tint: Topics.info("cardiacSurgery").fg)
                        DraftBanner(section: "tee")
                        questions(d)
                        checklist(d)
                        if surgery == "avRepair", let note = d.avRepairNote {
                            VStack(alignment: .leading, spacing: 6) {
                                InfoCaptionText(text: note, font: PS.sys(size: 12.5))
                                EvidenceLinks(sources: d.sources.filter { $0.id == "bierbach2010" || $0.id == "lepolain2009" }, onOpen: onOpen)
                            }
                        }
                        if post { changes(d) }
                        handoff(d)
                        Text(d.rv).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                        footer(d)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 30)
                }
                .sheet(isPresented: $viewsOpen) { TeeViewsSheet(data: d, basicOnly: $basicOnly, onOpen: onOpen) }
                .sheet(isPresented: $practiceOpen) { TeePracticeSheet(questions: d.practice ?? []) }
            } else {
                ContentUnavailableView("Not available offline yet", systemImage: "wifi.slash", description: Text("This tool arrives with the next refresh."))
            }
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("TEE Companion")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { withAnimation(.snappy) { checked = []; found = [] } }.disabled(checked.isEmpty && found.isEmpty)
            }
        }
        .task(id: refs.tee != nil) {
            // The first visit, once the content is on screen: one tip at the phase switch.
            guard refs.tee != nil else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeOut(duration: 0.25)) { _ = tips.offer(.tee) }
        }
        .onAppear {
            #if DEBUG
            if LaunchSeed.bool("ps.tee.practice") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { practiceOpen = true } }
            if !LaunchSeed.string("ps.tee.surgery").isEmpty { surgery = LaunchSeed.string("ps.tee.surgery") }
            if LaunchSeed.bool("ps.tee.post") { post = true }
            #endif
        }
    }

    private func questions(_ d: TeeData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which surgery?").font(PS.serif(size: 18)).foregroundStyle(PS.fg)
            ChoiceChips(options: d.surgeries.filter { $0.id != "all" }.map { (id: $0.id, label: $0.name) } + [(id: "all", label: "Other")],
                        selected: surgery) { id in withAnimation(.snappy) { surgery = id } }
            Picker("Phase", selection: $post.animation(.snappy)) {
                Text("Before bypass").tag(false)
                Text("After bypass").tag(true)
            }
            .pickerStyle(.segmented)
            .tipFrame(TipSet.tee.steps[0].target, in: tips)
        }
    }

    private func items(_ d: TeeData) -> [String] {
        let all = d.surgery("all").map { post ? $0.post : $0.pre } ?? []
        guard surgery != "all", let s = d.surgery(surgery) else { return all }
        return all + (post ? s.post : s.pre)
    }

    private func checklist(_ d: TeeData) -> some View {
        let list = items(d)
        let key = { (i: String) in "\(surgery):\(post):\(i)" }
        let done = list.filter { checked.contains(key($0)) }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: post ? "Check and report after bypass" : "Check and report before bypass")
                Spacer()
                Text("\(done) of \(list.count)").font(PS.mono(size: 11, weight: .semibold)).foregroundStyle(done == list.count ? PS.green : PS.fg3)
            }
            .padding(.horizontal, 2)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, item in
                    let on = checked.contains(key(item))
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { if on { checked.remove(key(item)) } else { checked.insert(key(item)) } }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(PS.sys(size: 18)).foregroundStyle(on ? PS.green : PS.fg3)
                            Text(item).font(PS.sys(size: 14.5)).foregroundStyle(on ? PS.fg2 : PS.fg).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if (d.required ?? []).contains(item) && !on { EvidenceTag(text: "Required") }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < list.count - 1 { Hairline().padding(.leading, 44) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private func changes(_ d: TeeData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "What changed from before bypass?", info: "Tap a finding to mark it: anything marked belongs in the report and with the surgeon.")
            VStack(spacing: 0) {
                ForEach(Array(d.flags.enumerated()), id: \.offset) { i, f in
                    let name = f.first ?? ""
                    let on = found.contains(name)
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { if on { found.remove(name) } else { found.insert(name) } }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: on ? "exclamationmark.circle.fill" : "circle.dashed").font(PS.sys(size: 17)).foregroundStyle(on ? PS.red : PS.fg3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(on ? PS.red : PS.fg)
                                if f.count > 1 { Text(f[1]).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true) }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < d.flags.count - 1 { Hairline().padding(.leading, 44) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            if !found.isEmpty {
                Text("Tell the surgeon: " + d.flags.compactMap(\.first).filter { found.contains($0) }.joined(separator: ", ") + ".")
                    .font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Handoff to My Patient (review doc, TEE row 11)

    /// About six lines for the case's echo notes, marked as a draft to confirm with the echocardiographer.
    static func handoffLines(_ d: TeeData, surgery: String, post: Bool, checked: [String], unchecked: [String], found: [String], at: Date) -> [String] {
        let name = surgery == "all" ? "Cardiac surgery" : (d.surgery(surgery)?.name ?? surgery)
        var lines = [(d.handoff?.title ?? "TEE draft: confirm with the echocardiographer") + " (\(ClockText.time(at)), TEE companion)"]
        lines.append("\(name), \(post ? "after" : "before") bypass: \(checked.count) of \(checked.count + unchecked.count) checked")
        if post { lines.append(found.isEmpty ? "No change from before bypass marked" : "Changed from before bypass: " + found.joined(separator: ", ")) }
        let missingRequired = unchecked.filter { (d.required ?? []).contains($0) }
        if !missingRequired.isEmpty { lines.append("Required, not recorded: " + missingRequired.joined(separator: ", ")) }
        let rest = unchecked.filter { !missingRequired.contains($0) }
        if !rest.isEmpty { lines.append("Not checked: " + rest.prefix(4).joined(separator: ", ") + (rest.count > 4 ? ", and \(rest.count - 4) more" : "")) }
        if !found.isEmpty { lines.append("Surgeon to be told: " + found.joined(separator: ", ")) }
        return Array(lines.prefix(6))
    }

    @ViewBuilder private func handoff(_ d: TeeData) -> some View {
        let list = items(d)
        let key = { (i: String) in "\(surgery):\(post):\(i)" }
        let checkedItems = list.filter { checked.contains(key($0)) }
        if !checkedItems.isEmpty || !found.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let h = handedOff, patient.isLatestStep(before: h.before, after: h.after) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(PS.green)
                        Text("Added to the case's echo notes").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                        Spacer()
                        Button("Undo") { withAnimation(.snappy) { patient.undo(); handedOff = nil } }
                            .buttonStyle(CapsuleButtonStyle(prominent: false))
                    }
                } else {
                    Button {
                        let lines = Self.handoffLines(d, surgery: surgery, post: post, checked: checkedItems,
                                                      unchecked: list.filter { !checked.contains(key($0)) },
                                                      found: d.flags.compactMap(\.first).filter { found.contains($0) }, at: Date())
                        let before = patient.record
                        withAnimation(.snappy) {
                            patient.update(discrete: true) { r in
                                let text = lines.joined(separator: "\n")
                                r.echo = r.echo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : r.echo + "\n\n" + text
                            }
                        }
                        handedOff = (before, patient.record)
                    } label: { Label("Add a draft to My Patient", systemImage: "square.and.arrow.down") }
                    .buttonStyle(GhostButtonStyle())
                    if let n = d.handoff?.note { InfoCaptionText(text: n, font: PS.sys(size: 12)) }
                }
            }
        }
    }

    private func footer(_ d: TeeData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            FlowLayout(spacing: 10) {
                Button { viewsOpen = true } label: { Label("Views", systemImage: "tablecells") }.buttonStyle(GhostButtonStyle())
                if !(d.practice ?? []).isEmpty {
                    Button { practiceOpen = true } label: { Label("Practice", systemImage: "questionmark.bubble") }.buttonStyle(GhostButtonStyle())
                }
                if let s = d.sources.first(where: { $0.id == "hahn2013" }), let url = URL(string: s.url) {
                    Button { onOpen(url) } label: { Label("Guideline ↗", systemImage: "doc.text") }.buttonStyle(GhostButtonStyle())
                }
                Button { onOpenTool(.valves) } label: { Label("Valve grading", systemImage: "waveform.path.ecg.rectangle") }.buttonStyle(GhostButtonStyle())
                Button { onOpenTool(.chamber) } label: { Label("Chambers", systemImage: "ruler") }.buttonStyle(GhostButtonStyle())
                Button { onOpenTool(.diastolic) } label: { Label("Diastolic (pre-op TTE)", systemImage: "waveform") }.buttonStyle(GhostButtonStyle())
            }
            EvidenceDisclosure {
                Text([d.report, d.diastolic, d.basicNote].joined(separator: " "))
                    .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                EvidenceLinks(sources: d.sources, onOpen: onOpen)
            }
        }
    }
}

/// The 28 views with their level and angle; Basic shows Reeves' 11.
struct TeeViewsSheet: View {
    var data: TeeData
    @Binding var basicOnly: Bool
    var onOpen: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Set", selection: $basicOnly) {
                        Text("Comprehensive (28)").tag(false)
                        Text("Basic (11)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if basicOnly {
                        Text(data.basicNote).font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.accent2).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 0) {
                        let views = data.views.filter { !basicOnly || $0.basic }
                        ForEach(Array(views.enumerated()), id: \.element.id) { i, v in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(v.n)").font(PS.mono(size: 11, weight: .semibold)).foregroundStyle(PS.fg3).frame(width: 22, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.name).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                                    Text(v.level + (v.depth.map { " · " + $0 } ?? "")).font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                                }
                                Spacer(minLength: 6)
                                Text(v.angle).font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg2).multilineTextAlignment(.trailing)
                                if v.basic && !basicOnly { EvidenceTag(text: "Basic") }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            if i < views.count - 1 { Hairline().padding(.leading, 46) }
                        }
                    }
                    .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                    Text(data.viewsNote).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    EvidenceLinks(sources: data.sources.filter { $0.id == "hahn2013" || $0.id == "reeves2013" }, onOpen: onOpen)
                }
                .padding(20)
            }
            .background(FeedBackground())
            .navigationTitle("TEE Views")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

/// Practice questions from the companion's own sourced content: tap one to see the answer and its source.
struct TeePracticeSheet: View {
    var questions: [TeeData.Practice]
    @Environment(\.dismiss) private var dismiss
    /// Screenshots: -ps.tee.answer 8 opens question 8's answer and scrolls to it (DEBUG; LaunchSeed is empty in release).
    @State private var shown: Set<Int> = Set(LaunchSeed.list("ps.tee.answer").compactMap { Int($0) }.map { $0 - 1 })

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tap a question to see the answer.").font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
                    ForEach(Array(questions.enumerated()), id: \.offset) { i, item in
                        let open = shown.contains(i)
                        Button {
                            Haptics.light()
                            withAnimation(.snappy) { if open { shown.remove(i) } else { shown.insert(i) } }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("\(i + 1)").font(PS.mono(size: 12, weight: .bold)).foregroundStyle(PS.accent)
                                    Text(item.q).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                if open {
                                    Text(item.a).font(PS.sys(size: 14.5)).foregroundStyle(PS.green).fixedSize(horizontal: false, vertical: true)
                                        .padding(.leading, 22)
                                    Text(item.source).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).padding(.leading, 22)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PS.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(open ? "Hides the answer" : "Shows the answer")
                        .id(i)
                    }
                }
                .padding(20)
            }
            .onAppear {
                guard let first = shown.min() else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo(first, anchor: .center) }
            }
            }
            .background(FeedBackground())
            .navigationTitle("TEE Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}
