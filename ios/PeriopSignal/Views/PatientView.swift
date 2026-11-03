import SwiftUI

/// My Patient's three tabs: Preoperative, Intraoperative, and Summary & Handoff.
enum PatientTab: String, CaseIterable, Identifiable {
    case preop, intraop, summary
    var id: String { rawValue }
    var title: String {
        switch self {
        case .preop: return "Preoperative"
        case .intraop: return "Intraoperative"
        case .summary: return "Summary & Handoff"
        }
    }
    var short: String {
        switch self {
        case .preop: return "Preop"
        case .intraop: return "Intraop"
        case .summary: return "Handoff"
        }
    }
    var icon: String {
        switch self {
        case .preop: return "list.bullet.clipboard"
        case .intraop: return "waveform.path.ecg.rectangle"
        case .summary: return "arrow.left.arrow.right.square"
        }
    }
}

/// My Patient: one patient, in three tabs. Preoperative is the history and physical (procedure, demographics,
/// history, assessment, airway); Intraoperative is the anesthetic in parts; Summary & Handoff carries the plan and
/// the handoff, written as you go, to share or send. Each card opens its editor; the tools it prompts open already
/// filled in. Kept on this phone only until Clear (with Undo). The bar holds the shield (no identifiers) on the left
/// and Undo and the ⋯ menu (cases, rooms, End case, Clear, Show Tips) on the right; the first time, four tips point
/// at the quick-add bar, the tabs, the ⋯ menu and the shield (PatientTips).
struct PatientView: View {
    @Environment(PatientStore.self) private var patient
    @Environment(PatientInbox.self) private var inbox
    @State private var path = NavigationPath()
    @State private var webLink: WebLink?
    @State private var confirmClear = false
    @State private var handoff = PatientHandoff()
    @State private var showNote = false
    /// The last tab used (screenshot runs pass -ps.patient.tab, which UserDefaults reads first).
    @AppStorage("ps.patient.tab") private var tabID = PatientTab.preop.rawValue
    /// A tab opened for a screenshot, without changing the one remembered.
    @State private var tabOverride: PatientTab?
    /// What Fill from a note just added, for its banner and Undo.
    @State private var noteResult: NoteResult?
    /// A patient from a colleague was just opened (true when it replaced another, which Undo brings back).
    @State private var received: Bool?
    /// The jump bar has scrolled under the top of the tab, so its pinned copy shows.
    @State private var jumpPinned = false
    /// The grey shield's "No patient identifiers" explanation is open.
    @State private var showIdentifiers = false
    /// Where the jump bar and its pinned copy are, read as the tab scrolls (not observed, so scrolling redraws nothing).
    @State private var jumpGeometry = PatientJumpGeometry()
    /// The first-time tips: whether they show, and which step.
    @State private var tips = PatientTips()
    /// Finished or skipped on this phone (the tips then show only from ⋯ → Show Tips).
    @AppStorage(PatientTips.seenKey) private var tipsSeen = false
    /// Where the tips' targets in the scroll view are, read only while the tips show.
    @State private var tipFrames: [PatientTipTarget: CGRect] = [:]
    /// Where the ⋯ menu and the shield are in the navigation bar, as they report it.
    @State private var tipBar = PatientTipBarFrames()
    /// Asks the tab to scroll back to the top (the tips start there).
    @State private var scrollToTop = 0

    private struct NoteResult {
        /// Each banner's own, so its 6-second timer ends only that one.
        var id = UUID()
        var count: Int
        var before: PatientRecord
        /// The record right after adding: Undo is offered only until the next edit.
        var after: PatientRecord
    }

    private var r: PatientRecord { patient.record }
    private var tab: PatientTab { tabOverride ?? PatientTab(rawValue: tabID) ?? .preop }
    /// The top of the tab, which the tips scroll back to.
    private static let topID = "ps.patient.top"

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // The row of cases only when it earns its place (two or more, or a room or phone); its sheets
                        // and the End case dialog are on the page (PatientCasePresentations).
                        if PatientRoomsBar.shows(patient) { PatientRoomsBar() }
                        tabBar.patientTipTarget(.tabs)
                        if let n = noteResult { noteBanner(n) }
                        if let replaced = received { receivedBanner(replaced) }
                        switch tab {
                        case .preop: preop(proxy)
                        case .intraop: intraop(proxy)
                        case .summary: summary
                        }
                        EvidenceNote("Kept on this phone, with no name or record number, until you clear it. Not backed up; it leaves the phone only if you send it.", title: "Kept on this phone")
                            .padding(.horizontal, 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                    .id(Self.topID)
                }
                .overlay(alignment: .top) { pinnedJumpBar(proxy) }
                .readPatientTipFrames(tips.isShowing, into: $tipFrames)
                .noIdentifiersAlert(isPresented: $showIdentifiers)
                .modifier(PatientCasePresentations())
                .modifier(CaseTimersPresentation())
                .onChange(of: scrollToTop) { _, _ in
                    withAnimation(.snappy) { proxy.scrollTo(Self.topID, anchor: .top) }
                }
                .onAppear {
                    #if DEBUG
                    // Screenshot runs: -ps.patient.jump handoff | assessment | history | airway | intraop:<part> scrolls
                    // the tab to it. -ps.patient.scroll, when no editor is opened, does the same and then again once
                    // the title has collapsed, as a tap on the pinned jump bar would.
                    let jump = LaunchSeed.string("ps.patient.jump")
                    let scroll = LaunchSeed.string("ps.patient.open").isEmpty ? LaunchSeed.string("ps.patient.scroll") : ""
                    let a = jump.isEmpty ? scroll : jump
                    if !a.isEmpty {
                        let go = {
                            if a.hasPrefix("intraop:") { proxy.scrollTo(PatientJumpID(PatientEditor.intraopPart(String(a.dropFirst(8)))), anchor: .top) }
                            else if let e = Self.jumpKeys[a] { proxy.scrollTo(PatientJumpID(e), anchor: .top) }
                            else { proxy.scrollTo(a, anchor: .top) }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: go)
                        if jump.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: go) }
                    }
                    #endif
                    // The first time (not in screenshot runs unless -ps.tips 1), once the tab has settled.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.easeOut(duration: 0.25)) { tips.appear(storedSeen: tipsSeen, launch: PatientTips.launch) }
                    }
                }
            }
            .background(FeedBackground())
            .scrollContentBackground(.hidden)
            .sheet(isPresented: $showNote) {
                PatientNoteSheet { n, before in
                    withAnimation(.snappy) {
                        received = nil
                        noteResult = NoteResult(count: n, before: before, after: patient.record)
                    }
                }
                .environment(patient)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: Binding(get: { inbox.pending != nil }, set: { if !$0 { inbox.pending = nil } })) {
                if let packet = inbox.pending {
                    PatientReceiveSheet(packet: packet) { replaced in
                        withAnimation(.snappy) {
                            noteResult = nil
                            received = replaced
                        }
                    }
                    .environment(patient)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            .alert("Couldn't open the patient", isPresented: Binding(get: { inbox.problem != nil }, set: { if !$0 { inbox.problem = nil } })) {
                Button("OK", role: .cancel) { inbox.problem = nil }
            } message: {
                Text(inbox.problem ?? "")
            }
            .navigationTitle("My Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NoIdentifiersShield(isPresented: $showIdentifiers)
                        .patientTipBarItem(.shield, into: tipBar)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    PatientUndoButton()
                    PatientCaseMenu(onClear: { confirmClear = true }, onShowTips: showTips)
                        .patientTipBarItem(.more, into: tipBar)
                }
            }
            .confirmationDialog("Clear this patient?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Patient", role: .destructive) { withAnimation(.snappy) { patient.clear() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Everything on this tab is removed from the phone. You can undo it right after.")
            }
            .navigationDestination(for: PatientEditor.self) { e in
                PatientEditorView(editor: e, onOpenRoute: { open($0) })
            }
            .navigationDestination(for: RefRoute.self) { route in
                RefDestination(route: route, push: { path.append($0) }, openURL: { webLink = WebLink(url: $0) }, path: nil, handoff: handoff)
            }
        }
        .overlay {
            if tips.isShowing {
                PatientTipsOverlay(tips: $tips, frames: tipFrames, bar: tipBar)
                    .transition(.opacity)
            }
        }
        .onChange(of: tips.step) { old, new in
            if old == nil && new != nil { prepareForTips() }
        }
        .onChange(of: tips.seen) { _, seen in
            if seen { tipsSeen = true }
        }
        .environment(handoff)
        .task { await openForScreenshot() }
        .fullScreenCover(item: $webLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
    }

    /// ⋯ → Show Tips: once the menu has closed.
    private func showTips() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.25)) { tips.showAgain() }
        }
    }

    /// The tips start at the top of a tab with the quick-add bar, with the keyboard down.
    private func prepareForTips() {
        Keyboard.dismiss()
        if tab == .summary { tabOverride = .preop }
        scrollToTop += 1
    }

    private func open(_ key: String) {
        if key.hasPrefix("workup:") { path.append(PatientEditor.workup(String(key.dropFirst(7)))); return }
        if let route = RefRoute(key: key) { path.append(route) }
    }

    /// Screenshot runs: -ps.patient.tab preop | intraop | summary; -ps.patient.open details | procedure | demographics |
    /// history | medications | assessment | airway | intraop | plan | handoff | note | receive | workup:<id> |
    /// intraop:<part> | system:<id> | a reference route such as score:rcri; -ps.patient.edit exam | echo | intraop-echo makes that
    /// change first (one-tap normals; harvest-both plans both radials), so Undo shows.
    private func openForScreenshot() async {
        #if DEBUG
        let edit = LaunchSeed.string("ps.patient.edit")
        if !edit.isEmpty {
            try? await Task.sleep(nanoseconds: 300_000_000)
            patient.update(discrete: true) { r in
                switch edit {
                case "echo": r.echoFindings.applyNormal()
                case "intraop-echo": r.intraopEcho.applyNormal()
                case "harvest-both": r.radial.harvest = "both"
                default: PatientAirway.applyNormalExam(&r)
                }
            }
        }
        let o = LaunchSeed.string("ps.patient.open")
        // A push asked for before the navigation stack is on screen is sometimes dropped (screenshot runs): wait a moment.
        if !o.isEmpty { try? await Task.sleep(nanoseconds: 400_000_000) }
        switch o {
        case "details": path.append(PatientEditor.details)
        case "procedure": path.append(PatientEditor.procedure)
        case "demographics": path.append(PatientEditor.demographics)
        case "history": path.append(PatientEditor.history)
        case "medications": path.append(PatientEditor.medications)
        case "assessment": path.append(PatientEditor.assessment)
        case "airway": path.append(PatientEditor.airway)
        case "intraop": path.append(PatientEditor.intraop)
        case "plan": path.append(PatientEditor.plan)
        case "handoff": tabOverride = .summary
        case "note":
            // A sheet asked for before the tab is on screen can be dropped, so wait a moment.
            try? await Task.sleep(nanoseconds: 800_000_000)
            showNote = true
        case "receive":
            try? await Task.sleep(nanoseconds: 800_000_000)
            inbox.pending = PatientPacket(record: PatientDemo.record)
        default:
            if o.hasPrefix("workup:") { path.append(PatientEditor.workup(String(o.dropFirst(7)))) }
            else if o.hasPrefix("intraop:") { path.append(PatientEditor.intraopPart(String(o.dropFirst(8)))) }
            else if o.hasPrefix("devices:") { path.append(PatientEditor.devices(String(o.dropFirst(8)))) }
            else if o.hasPrefix("system:") { path.append(PatientEditor.system(String(o.dropFirst(7)))) }
            else if let route = RefRoute(key: o) { path.append(route) }
        }
        #endif
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(PatientTab.allCases) { t in
                let on = t == tab
                Button {
                    Haptics.light()
                    withAnimation(.snappy) { tabOverride = nil; tabID = t.rawValue }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon).font(PS.sys(size: 15, weight: .semibold))
                        Text(t.title).font(PS.sys(size: 12.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(on ? PS.accentFg : PS.fg2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(on ? PS.accent : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private func preop(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            noteButton
            // The empty patient's one hint, in place of an explainer card.
            if patient.isEmpty {
                Text("Type the patient in one line, or open a section below.")
                    .font(PS.sys(size: 12.5))
                    .foregroundStyle(PS.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        jumpBar(proxy, Self.preopJumps).background(jumpBarReader)
        PatientSectionCard(editor: .procedure, lines: PatientSummary.procedureLines(r), empty: "Procedure, urgency, planned anesthetic and the risk-score inputs.")
            .jumpTarget(PatientEditor.procedure)
        PatientSectionCard(editor: .demographics, lines: PatientSummary.demographicsLines(r), empty: "Age, sex, height, weight and preprocedure vital signs.")
            .jumpTarget(PatientEditor.demographics)
        PatientSectionCard(editor: .history, lines: PatientSummary.historyLines(r), empty: "Problems by system, surgical history, medications, allergies, anesthetic complications, NPO and labs.")
            .jumpTarget(PatientEditor.history)
        PatientSectionCard(editor: .assessment, lines: PatientSummary.assessmentLines(r), empty: "ASA class, functional capacity, the cardiac evaluation and the risk scores.")
            .jumpTarget(PatientEditor.assessment)
        airwayCard.jumpTarget(PatientEditor.airway)
        devicesCard.jumpTarget(PatientEditor.devices("preop"))
        PatientSectionCard(editor: .devices("support"), lines: PatientSummary.supportLines(r), empty: "IABP, Impella, LVAD or ECMO, with their settings.")
            .jumpTarget(PatientEditor.devices("support"))
    }

    private static let preopJumps: [PatientEditor] = [.procedure, .demographics, .history, .assessment, .airway, .devices("preop"), .devices("support")]

    /// Screenshot runs: the names -ps.patient.jump and -ps.patient.scroll take for the preoperative cards.
    private static let jumpKeys: [String: PatientEditor] = [
        "procedure": .procedure, "demographics": .demographics, "history": .history, "assessment": .assessment,
        "airway": .airway, "devices": .devices("preop"), "support": .devices("support"),
    ]

    /// The intraoperative echo card shows when an echo is usual for the surgery, a TEE is planned, or one is recorded.
    private var echoUp: Bool { PatientRules.echoFirst(r) || PatientTEE.planned(r) || !r.intraopEcho.isEmpty || !r.echo.isEmpty }

    /// The intraoperative parts with a card of their own, in order; major considerations close the tab, after the
    /// echo button.
    private var intraopCardParts: [(id: String, title: String, icon: String)] {
        PatientEditor.intraopParts.filter { ($0.id != "echo" || echoUp) && $0.id != "considerations" }
    }

    /// The jump bar's sections for the tab (none on Summary & Handoff).
    private var jumpEditors: [PatientEditor]? {
        switch tab {
        case .preop: return Self.preopJumps
        case .intraop: return intraopCardParts.map { PatientEditor.intraopPart($0.id) } + [PatientEditor.intraopPart("considerations")]
        case .summary: return nil
        }
    }

    /// Lines and devices on arrival, drawn on the patient.
    private var devicesCard: some View {
        NavigationLink(value: PatientEditor.devices("preop")) {
            VStack(alignment: .leading, spacing: 9) {
                sectionHeader(.devices("preop"))
                let lines = PatientSummary.arrivalDeviceLines(r)
                if lines.isEmpty && !r.arrivesWithAirway && r.mechanicalSupport.isEmpty {
                    Text("Tap to draw the lines, airway and devices the patient arrives with.").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                } else {
                    PatientDiagramCard(record: r, phase: .preop, height: 260)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in summaryLine(l) }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func intraop(_ proxy: ScrollViewProxy) -> some View {
        noteButton
        CaseTimersStrip()
        let parts = intraopCardParts
        jumpBar(proxy, jumpEditors ?? []).background(jumpBarReader)
        ForEach(parts, id: \.id) { part in
            PatientSectionCard(editor: .intraopPart(part.id), lines: PatientSummary.intraopPartLines(r, part.id), empty: Self.intraopEmpty[part.id] ?? "")
                .jumpTarget(PatientEditor.intraopPart(part.id))
        }
        if !echoUp {
            NavigationLink(value: PatientEditor.intraopPart("echo")) {
                Label("Add echo findings", systemImage: "plus.circle")
            }
            .buttonStyle(GhostButtonStyle())
        }
        PatientSectionCard(editor: .intraopPart("considerations"), lines: PatientSummary.intraopPartLines(r, "considerations"), empty: Self.intraopEmpty["considerations"] ?? "")
            .jumpTarget(PatientEditor.intraopPart("considerations"))
    }

    private static let intraopEmpty: [String: String] = [
        "airway": "Mask, supraglottic airway, intubation, the view and the tube.",
        "lines": "Peripheral, arterial and central lines.",
        "regional": "Blocks and neuraxial techniques, drugs and catheters.",
        "infusions": "Drips running and their rates.",
        "fluids": "Blood products, cell saver, crystalloid and albumin with + and −; blood loss and urine.",
        "labs": "Blood gas and coagulation sets with their times; the latest goes to the handoff.",
        "considerations": "Difficult airway, massive transfusion, pressors, TEE findings and more, for the top of the handoff.",
        "meds": "Antibiotic and time, steroids, TXA, reversal, positioning.",
        "events": "What happened, and whether the patient leaves intubated or extubated.",
        "echo": "LV and RV function, valves, aorta, other findings.",
    ]

    @ViewBuilder private var summary: some View {
        PatientSectionCard(editor: .plan, lines: PatientSummary.planLines(r), empty: "Disposition, pain plan and what the next team should do.")
            .id(PatientEditor.plan)
        if patient.isEmpty {
            Text("The handoff writes itself here as you fill in the other tabs.")
                .font(PS.sys(size: 14)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        } else {
            HandoffPanel(record: r).id("handoff")
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Lines & devices now")
                PatientDiagramCard(record: r, phase: .all, height: 380)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    // MARK: Top

    /// The quick-add bar (1.8), in place of the Fill from a note card; its pencil opens the full note. The first tip
    /// points at it.
    private var noteButton: some View {
        QuickAddBar(tab: tab == .intraop ? .intraop : .preop)
            .patientTipTarget(.quickAdd)
    }

    private func noteBanner(_ n: NoteResult) -> some View {
        let missing = PatientNote.missing(r)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.green)
                Text("Added \(n.count) item\(n.count == 1 ? "" : "s") from your note").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                Spacer(minLength: 6)
                // The note's add is one step in the store's Undo history: offered while it is still the latest.
                if patient.isLatestStep(before: n.before, after: n.after) {
                    Button("Undo") {
                        withAnimation(.snappy) {
                            patient.undo()
                            noteResult = nil
                        }
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
                }
                closeButton { noteResult = nil }
            }
            if !missing.isEmpty {
                Text("Still to fill: " + missing.joined(separator: ", ") + ".")
                    .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PS.line2, lineWidth: 1))
        // Goes after 6 seconds, like the quick-add snackbar; its Undo is there until then. (The ↩ in the bar steps
        // back the same change afterwards.)
        .task(id: n.id) {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, noteResult?.id == n.id else { return }
            withAnimation(.snappy) { noteResult = nil }
        }
    }

    private func receivedBanner(_ replaced: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.fill.checkmark").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.green)
            Text("Patient from a colleague: check it against the chart").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if replaced && patient.canUndoReceive {
                Button("Undo") {
                    withAnimation(.snappy) {
                        patient.undoReceive()
                        received = nil
                    }
                }
                .buttonStyle(CapsuleButtonStyle(prominent: false))
            }
            closeButton { received = nil }
        }
        .padding(12)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PS.line2, lineWidth: 1))
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Image(systemName: "xmark").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.fg3).frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }

    // MARK: Pinned jump bar

    /// Reads where the tab's jump bar is as it scrolls; the pinned copy shows once it has gone under the top.
    private var jumpBarReader: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { jumpGeometry.barY = g.frame(in: .global).minY; updateJumpPin() }
                .onChange(of: g.frame(in: .global).minY) { _, y in jumpGeometry.barY = y; updateJumpPin() }
        }
    }

    private func updateJumpPin() {
        let pinned = jumpGeometry.barY < jumpGeometry.pinY
        if pinned != jumpPinned { jumpPinned = pinned }
    }

    /// The jump bar again, pinned at the top of the tab on the app's background material, once the tab's own has
    /// scrolled under it: any section is one tap away from anywhere on the tab. At rest only a point at the top is
    /// there, to measure where the chips pin; the bar and its material exist only while pinned.
    @ViewBuilder private func pinnedJumpBar(_ proxy: ScrollViewProxy) -> some View {
        if let editors = jumpEditors {
            ZStack(alignment: .top) {
                Color.clear
                    .frame(height: 1)
                    .padding(.top, 8)
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { jumpGeometry.pinY = g.frame(in: .global).minY + 8; updateJumpPin() }
                            .onChange(of: g.frame(in: .global).minY) { _, y in jumpGeometry.pinY = y + 8; updateJumpPin() }
                    })
                    .allowsHitTesting(false)
                if jumpPinned {
                    jumpBar(proxy, editors)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            Rectangle().fill(.ultraThinMaterial)
                                .overlay(PS.bg.opacity(0.55))
                                .overlay(alignment: .bottom) { Hairline() }
                                .ignoresSafeArea(edges: [.horizontal, .top])
                        }
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: jumpPinned)
        }
    }

    private func jumpBar(_ proxy: ScrollViewProxy, _ editors: [PatientEditor]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(editors, id: \.self) { e in
                    Button { withAnimation(.snappy) { proxy.scrollTo(PatientJumpID(e), anchor: .top) } } label: {
                        Text(e.title)
                            .font(PS.sys(size: 13.5, weight: .semibold))
                            .foregroundStyle(PS.fg2)
                            .padding(.horizontal, 13).padding(.vertical, 7)
                            .background(PS.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    // MARK: Section cards

    private var airwayCard: some View {
        NavigationLink(value: PatientEditor.airway) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(.airway)
                    let lines = PatientSummary.airwayLines(r)
                    if lines.isEmpty {
                        Text("Current airway and oxygen, Mallampati, difficult-airway signs and teeth.").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in summaryLine(l) }
                    }
                }
                if let m = r.mallampati, !r.arrivesWithAirway {
                    VStack(spacing: 4) {
                        MallampatiDrawing(mclass: m).frame(width: 64, height: 64)
                        Text(PatientRules.roman(m)).font(PS.mono(size: 11, weight: .bold)).foregroundStyle(PS.fg2)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ e: PatientEditor) -> some View {
        HStack(spacing: 8) {
            Image(systemName: e.icon).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent)
            Text(e.title).font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer()
            Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
        }
    }

    private func summaryLine(_ l: PatientSummary.Line) -> some View { PatientLineText(line: l) }
}

/// A section of the note: its header, then its lines (or what it holds, while empty). Opens the section's editor.
struct PatientSectionCard: View {
    var editor: PatientEditor
    var lines: [PatientSummary.Line]
    var empty: String

    var body: some View {
        NavigationLink(value: editor) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: editor.icon).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent)
                    Text(editor.title).font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
                    Spacer()
                    Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                }
                if lines.isEmpty {
                    Text(empty).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in PatientLineText(line: l) }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The handoff as it stands, short or full, written from the record as you go: read it, copy it, share it, or send
/// the patient itself to a colleague's Periop Signal so they carry on with the case.
struct HandoffPanel: View {
    @Environment(ReferenceStore.self) private var refs
    var record: PatientRecord
    @State private var sharing: [Any]?
    /// "full" or "short"; the last one used is kept.
    @AppStorage("ps.handoff.format") private var format = "full"
    @State private var copied = false

    private var text: String { format == "short" ? HandoffWriter.shortText(record) : HandoffWriter.text(record) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Handoff, as it stands")
                Spacer()
                Picker("Handoff", selection: $format) {
                    Text("Short").tag("short")
                    Text("Full").tag("full")
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            Text(handoffStyled(text, marks: HandoffWriter.marks(record)))
                .font(PS.sys(size: 14.5))
                .foregroundStyle(PS.fg)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            HStack(spacing: 10) {
                Button { sharing = [text] + (diagramImage().map { [$0] } ?? []) } label: { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(prominent: true))
                Button { UIPasteboard.general.string = text; copied.toggle() } label: { Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(prominent: false))
            }
            EvidenceNote("Share only through channels your institution approves for patient information.", title: "Approved channels only")
            sendCard
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Handing over")
                ForEach(Array(HandoffWriter.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)").font(PS.mono(size: 12, weight: .bold)).foregroundStyle(PS.accent).frame(width: 16, alignment: .leading)
                        Text(step).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                EvidenceNote("From the HATRICC handoff protocol (Lane-Fall MB, et al. Implement Sci 2021). In a PACU, anesthesia often reports alone.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
        .sensoryFeedback(.success, trigger: copied)
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            ShareSheet(items: sharing ?? []).presentationDetents([.medium, .large])
        }
    }

    /// The diagram as a picture for the end of the shared handoff, when anything is drawn on it.
    @MainActor private func diagramImage() -> UIImage? {
        guard let fig = refs.bundle?.regional?.figure else { return nil }
        let m = PatientDiagramModel.items(record, phase: .all)
        guard !m.items.isEmpty else { return nil }
        let view = PatientDiagramCanvas(figure: fig, items: m.items, cart: m.cart)
            .frame(width: 360, height: 560)
            .padding(12)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }

    private var sendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(PS.sys(size: 16, weight: .semibold))
                    .foregroundStyle(PS.accent2)
                    .frame(width: 36, height: 36)
                    .background(PS.accent2.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Send this patient").font(PS.sys(size: 15.5, weight: .semibold)).foregroundStyle(PS.fg)
                    Text("To a colleague's Periop Signal by AirDrop or iMessage; it opens in their My Patient so they can carry on with the case.")
                        .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
            }
            ShareLink(item: PatientTransfer(record: record),
                      preview: SharePreview("Patient for handoff", image: Image(systemName: "person.text.rectangle"))) {
                Label("Send Patient", systemImage: "iphone.and.arrow.forward").frame(maxWidth: .infinity)
            }
            .buttonStyle(BigButtonStyle(prominent: false))
            EvidenceNote("In Messages, they tap the file, then Share, then Periop Signal. Send only to the colleague taking over, through channels your institution approves; Messages keeps a copy in the conversation.", title: "How it works")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }
}

/// One summary line: its label, then the text, alerts in red and abnormal values and scores in bold red.
struct PatientLineText: View {
    var line: PatientSummary.Line

    private var styled: AttributedString {
        var a = AttributedString(line.text)
        for m in line.marks where !m.isEmpty {
            var from = a.startIndex
            while let r = a[from...].range(of: m) {
                a[r].foregroundColor = PS.red
                a[r].font = PS.sys(size: 14, weight: .bold)
                from = r.upperBound
            }
        }
        return a
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let k = line.label { Text(k).font(PS.sys(size: 11.5, weight: .semibold)).foregroundStyle(line.alert ? PS.accent : PS.fg3) }
            Text(styled).font(PS.sys(size: 14, weight: line.alert ? .semibold : .regular)).foregroundStyle(line.alert ? PS.accent : PS.fg)
                .lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Where the tab's jump bar and its pinned copy sit on screen, updated as the tab scrolls. A plain class, so the
/// updates redraw nothing; PatientView redraws only when the pinned copy shows or hides.
final class PatientJumpGeometry {
    /// The top of the tab's own jump bar.
    var barY: CGFloat = .infinity
    /// The top of the pinned copy's chips.
    var pinY: CGFloat = -.infinity
}

/// A card's scroll target, kept apart from the jump bar's own chips (identified by the same editors), so a jump
/// scrolls the tab and never the row of chips.
struct PatientJumpID: Hashable {
    var editor: PatientEditor
    init(_ editor: PatientEditor) { self.editor = editor }
}

extension View {
    /// A card the jump bar scrolls to. Its scroll target is a clear anchor stacked above the card, pulled up by
    /// negative padding so the layout is unchanged: scrolling aligns the anchor with the top of the safe area, under
    /// the navigation bar, so 110 pt clears the inline title and the pinned jump bar and the card lands just under
    /// them. (An id in a background is not used by ScrollViewReader; a stacked child is.)
    func jumpTarget(_ editor: PatientEditor) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 110)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .id(PatientJumpID(editor))
            self
        }
        .padding(.top, -110)
    }
}
