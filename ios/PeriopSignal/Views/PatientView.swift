import SwiftUI
import os

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
    /// The quick-add bar at the top of the tab (every tab has one, 1.8.1).
    var quickAddPlace: QuickAddPlace {
        switch self {
        case .preop: return .preopTab
        case .intraop: return .intraopTab
        case .summary: return .summaryTab
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
    /// Screenshot runs: asks the tab to scroll to -ps.patient.jump once the tab it names is showing.
    @State private var shotJump = 0

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
                .scrollDismissesKeyboard(.interactively)
                .overlay(alignment: .top) { pinnedJumpBar(proxy) }
                .readPatientTipFrames(tips.isShowing, into: $tipFrames)
                .noIdentifiersAlert(isPresented: $showIdentifiers)
                .modifier(PatientCasePresentations())
                .modifier(CaseTimersPresentation())
                .onChange(of: scrollToTop) { _, _ in
                    withAnimation(.snappy) { proxy.scrollTo(Self.topID, anchor: .top) }
                }
                #if DEBUG
                .onChange(of: shotJump) { _, _ in Self.screenshotScroll(Self.shotScrollName, proxy) }
                #endif
                .onDisappear {
                    #if DEBUG
                    ShotTrace.note("root disappear")
                    ShotReady.rootHidden()
                    ShotReady.rootOnScreen = false
                    #endif
                }
                .onAppear {
                    #if DEBUG
                    // Screenshot runs: -ps.patient.jump handoff | assessment | history | airway | intraop:<part> scrolls
                    // the tab to it. -ps.patient.scroll, when no editor is opened, does the same from the task, again
                    // and again until the shot is taken (scrollForScreenshot).
                    ShotReady.rootOnScreen = true
                    let jump = LaunchSeed.string("ps.patient.jump")
                    if !jump.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { Self.screenshotScroll(jump, proxy) }
                    }
                    #endif
                    #if DEBUG
                    ShotTrace.note("root appear tab=\(tab.rawValue)")
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
                    #if DEBUG
                    .onAppear { ShotTrace.note("page appear \(e)"); ShotReady.pageShown() }
                    .onDisappear { ShotTrace.note("page disappear \(e)") }
                    #endif
            }
            .navigationDestination(for: RefRoute.self) { route in
                RefDestination(route: route, push: { path.append($0) }, openURL: { webLink = WebLink(url: $0) }, path: nil, handoff: handoff)
                    #if DEBUG
                    .onAppear { ShotTrace.note("route appear"); ShotReady.pageShown() }
                    #endif
            }
        }
        // Screenshot runs: -ps.patient.width 375 lays My Patient out as on that width (the CI simulator is wider).
        .modifier(DebugContentWidth())
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
        #if DEBUG
        .onChange(of: path) { o, n in ShotTrace.note("path \(o.count) -> \(n.count)") }
        .onAppear { ShotTrace.note("PatientView appear") }
        .onDisappear { ShotTrace.note("PatientView disappear") }
        #endif
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

    /// A box's link: a reference route first ("airway" is the airway reference page here), else an editor or one of
    /// its pages by its deep-link name (workup:tee, medications).
    private func open(_ key: String) {
        if let route = RefRoute(key: key) { path.append(route); return }
        if let e = PatientDeepLink.parse(key)?.editor { path.append(e) }
    }

    /// Screenshot runs: -ps.patient.tab preop | intraop | summary; -ps.patient.open details | procedure | demographics |
    /// history | medications | assessment | airway | intraop | plan | handoff | note | receive | workup:<id> |
    /// intraop:<part> | system:<id> | a reference route such as score:rcri; -ps.patient.edit exam | echo | intraop-echo | echo-trivial makes that
    /// change first (one-tap normals; harvest-both plans both radials; echo-trivial grades TR and AR trivial; ecg-af, ecg-none for the ECG link), so Undo shows.
    private func openForScreenshot() async {
        #if DEBUG
        let edit = LaunchSeed.string("ps.patient.edit")
        if !edit.isEmpty {
            try? await Task.sleep(nanoseconds: 300_000_000)
            patient.update(discrete: true) { r in
                switch edit {
                case "echo": r.echoFindings.applyNormal()
                case "intraop-echo": r.intraopEcho.applyNormal()
                // Trivial regurgitation (1.8.1) on the preoperative echo, for its screenshots.
                case "echo-trivial":
                    r.echoFindings.tricuspid.regurgitation = .trivial
                    r.echoFindings.aortic.regurgitation = .trivial
                case "harvest-both": r.radial.harvest = "both"
                // 1.9 (the Preprocedure tab): Intrathoracic procedure answered Yes, as a tap would.
                case "intrathoracic": PatientPreop.setIntrathoracic(true, &r)
                // 1.8.3 (the ECG and the history linked): an AF found on the ECG, which the history then holds too; the ECG
                // cleared, so the history's AF and pacemaker are offered as suggestions.
                case "ecg-af": PatientECGLink.add("Atrial fibrillation", to: &r)
                case "ecg-none": r.ecg = []
                // 1.8.3: a non-obstructive cath, right dominant, with a date.
                case "lhc-nonobstructive":
                    r.lhc.dominance = "right"; r.lhc.result = "non-obstructive"; r.lhc.date = PatientMonthYear(month: 6, year: 2026)
                default: PatientAirway.applyNormalExam(&r)
                }
            }
        }
        guard let link = PatientDeepLink.parse(LaunchSeed.string("ps.patient.open")) else {
            if !LaunchSeed.string("ps.patient.jump").isEmpty { await jumpForScreenshot() }
            else if !Self.shotScrollName.isEmpty { await scrollForScreenshot() }
            return
        }
        ShotTrace.note("open begin \(link)")
        switch link {
        case .summary:
            tabOverride = .summary
            await jumpForScreenshot()
        case .note:
            // A sheet asked for before the tab is on screen can be dropped, so wait a moment.
            try? await Task.sleep(nanoseconds: 800_000_000)
            showNote = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            ShotReady.ready()
        case .receive:
            try? await Task.sleep(nanoseconds: 800_000_000)
            inbox.pending = PatientPacket(record: PatientDemo.record)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            ShotReady.ready()
        case .editor, .route:
            // A push asked for before the navigation stack has settled is sometimes dropped (the stack writes its empty
            // first state back over the path), and the 1.9 tab's longer first layout on the CI simulator made one wait
            // of 0.4 s lose now and then (run 375: 340, 393 and 394 showed the tab). Push after a moment, then look
            // again a few times and push once more while the path is still empty. A push that took can still be written
            // over later on the slower Intel runner (run 416: 569 and 570 showed the Preoperative tab), so every look
            // pushes again while the path is empty, not only the looks before the first push took.
            // Review 1.10 (531, 575 and 576 still showed the tab): the looks ended 8 s in, and a path written over after
            // that stayed empty for the picture 16 to 20 s in. So after them the path is watched for the rest of the
            // longest shot's wait, and pushed again, without the animation, whenever it is found empty. A push that
            // stays is never repeated (only an empty path is pushed onto), and nothing in a screenshot run pops it.
            var pushed = false
            for delay in Self.openLookDelays {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { ShotTrace.note("open task cancelled"); return }
                guard path.isEmpty else { continue }
                ShotTrace.note("push (pushed before: \(pushed))")
                var t = Transaction()
                t.disablesAnimations = pushed
                withTransaction(t) {
                    switch link {
                    case .editor(let e): path.append(e)
                    case .route(let r): path.append(r)
                    default: break
                    }
                }
                pushed = true
            }
        }
        #endif
    }

    /// Screenshot runs: -ps.patient.jump, once the task has set the tab it is on (-ps.patient.open handoff). The tab's
    /// own first scroll, a second after it appears, can come before that on a slow simulator (the macos-15-intel runner's
    /// iOS 26 simulator starts the task seconds after the tab appears), and then lands on the Preoperative tab, which
    /// has no handoff. So the task asks for the scroll twice more, then reports the shot ready (ShotReady).
    private func jumpForScreenshot() async {
        #if DEBUG
        guard !LaunchSeed.string("ps.patient.jump").isEmpty else {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            ShotReady.ready()
            return
        }
        for delay: UInt64 in [800_000_000, 1_200_000_000] {
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { return }
            shotJump += 1
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        ShotReady.ready()
        #endif
    }

    /// Screenshot runs: -ps.patient.scroll on the tab (no -ps.patient.open). Three timed scrolls after the tab appeared
    /// left 451, 452, 455, 457 and 458 at the top of the Preoperative tab in the final 1.10 run: on the Intel runner the
    /// tab can appear 10 s or more after launch and take seconds more to lay its sections out. So the task asks for the
    /// scroll every half second while the tab is on screen, reports the shot ready (ShotReady) once the target has been
    /// laid out (jumpTarget reports it; a plain id counts once the tab is showing) and scrolled to for 3 s, and goes on
    /// asking until past the longest wait for ready, so the picture is taken at the target whenever it comes.
    private func scrollForScreenshot() async {
        #if DEBUG
        let name = Self.shotScrollName
        let key = Self.shotTargetKey(name)
        ShotTrace.note("scroll begin \(name) key=\(key ?? "-")")
        let start = Date()
        var looks = 0
        var reported = false
        while Date().timeIntervalSince(start) < Self.scrollWatchSeconds {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { ShotTrace.note("scroll task cancelled"); return }
            guard ShotReady.rootOnScreen else { continue }
            shotJump += 1
            if key.map({ ShotReady.targetsShown.contains($0) }) ?? true { looks += 1 }
            if !reported && looks >= 6 {
                reported = true
                ShotTrace.note("scroll settled after \(Int(Date().timeIntervalSince(start))) s")
                ShotReady.ready()
            }
        }
        if !reported { ShotTrace.note("scroll target never shown"); ShotReady.ready() }
        #endif
    }

    /// How long the task goes on scrolling: past the longest shot's wait and the 30 s more it can wait for ready.
    static let scrollWatchSeconds: Double = 56

    /// Screenshot runs: the name the tab scrolls to, -ps.patient.jump, or -ps.patient.scroll when no page is opened.
    static var shotScrollName: String {
        let jump = LaunchSeed.string("ps.patient.jump")
        if !jump.isEmpty { return jump }
        return LaunchSeed.string("ps.patient.open").isEmpty ? LaunchSeed.string("ps.patient.scroll") : ""
    }

    /// The jumpTarget key a name scrolls to, or nil for a plain id.
    static func shotTargetKey(_ a: String) -> String? {
        if a.hasPrefix("intraop:") { return PatientJumpID(intraop: IntraopSection(part: String(a.dropFirst(8)))).key }
        return jumpKeys[a]?.key
    }

    /// Screenshot runs: scrolls the tab to a -ps.patient.jump or -ps.patient.scroll name.
    static func screenshotScroll(_ a: String, _ proxy: ScrollViewProxy) {
        guard !a.isEmpty else { return }
        if a.hasPrefix("intraop:") { proxy.scrollTo(PatientJumpID(intraop: IntraopSection(part: String(a.dropFirst(8)))), anchor: .top) }
        else if let e = jumpKeys[a] { proxy.scrollTo(e, anchor: .top) }
        else { proxy.scrollTo(a, anchor: .top) }
    }

    /// When the screenshot runs' -ps.patient.open pushes its page, and looks again: after the stack's first frame,
    /// then with room for a slow launch (the last well inside the shortest open-key shot's 12 s wait).
    static let openRetryDelays: [Double] = [0.4, 1.2, 2.4, 4.0]

    /// After those, how often the path is looked at again, and for how long in all: past the longest open-key shot's
    /// wait (30 s: the system pages and the Past Surgical History page, which the Intel runner draws 20 to 30 s after a
    /// launch; review 1.10), so a push written over late is put back before the picture.
    static let openWatchInterval: Double = 0.5
    static let openWatchSeconds: Double = 32

    /// Every wait between looks, in order: the retries, then the watch.
    static var openLookDelays: [Double] {
        let early = openRetryDelays.reduce(0, +)
        let watch = max(0, Int(((openWatchSeconds - early) / openWatchInterval).rounded(.down)))
        return openRetryDelays + Array(repeating: openWatchInterval, count: watch)
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
                Text("Type the patient in one line, or fill in a box below.")
                    .font(PS.sys(size: 12.5))
                    .foregroundStyle(PS.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        jumpBar(proxy, Self.preopJumps).background(jumpBarReader)
        // 1. Procedure: the open Planned Procedure & Anesthetic box and the "+ Risk-score inputs" link under it (1.10); the
        // Procedure editor is still behind PatientEditor.procedure for deep links.
        PreopPlannedBox().jumpTarget(section: .procedure)
        PreopRiskInputsLink().jumpTarget(anchor: PatientPreop110.riskInputsAnchor)
        demographicsSection
        workupSection
        medicationsSection
        riskSection
        summarySection
    }

    // The 1.9 tab (Ben's Wanted Changes): six sections, each a jump-bar target, with the boxes' controls in place
    // (PatientPreopViews.swift). The editors behind the old cards are still there for the boxes' links and deep links.

    /// 2. Demographics & History: Demographics, Allergies, Problems by system, and the surgical history, complications
    /// and last intake chips. (Labs moved to Examination & Workup.)
    @ViewBuilder private var demographicsSection: some View {
        PreopSectionTitle(text: PreopSection.demographics.title).jumpTarget(section: .demographics)
        PreopDemographicsBox().jumpTarget(anchor: "demographics")
        PatientGroup(title: "Allergies") { AllergiesBox() }.jumpTarget(anchor: "allergies")
        PreopProblemsBox().jumpTarget(anchor: "problems")
        PreopHistoryChipsBox().jumpTarget(anchor: "chips")
    }

    /// 3. Examination & Workup: ASA and functional capacity, Cardiopulmonary Evaluation (with the cardiac workup),
    /// the airway examination, laboratory studies, lines and devices.
    @ViewBuilder private var workupSection: some View {
        PreopSectionTitle(text: PreopSection.workup.title).jumpTarget(section: .workup)
        PreopAsaBox().jumpTarget(anchor: "asa")
        PreopCardioBox().jumpTarget(anchor: "cardio")
        airwayCard.jumpTarget(anchor: "airway")
        PreopLabsCard().jumpTarget(anchor: "labs")
        devicesCard.jumpTarget(anchor: "devices")
    }

    /// 4. Current Medications: home medications, current infusions, flagged medications.
    @ViewBuilder private var medicationsSection: some View {
        PreopSectionTitle(text: PreopSection.medications.title).jumpTarget(section: .medications)
        PatientGroup(title: "Home medications") { HomeMedicationsBox() }.jumpTarget(anchor: "homemeds")
        PatientGroup(title: "Current infusions", note: "Drips running before the case, with their rates: they carry into the intraoperative infusions when you add them there.") {
            CurrentInfusionsBox()
        }
        .jumpTarget(anchor: "infusions")
        PreopFlaggedBox(onOpenRoute: { open($0) }).jumpTarget(anchor: "flagged")
    }

    /// 5. Risk Scores & Checks: the warnings, then the prompts (no RCRI for cardiac surgery).
    @ViewBuilder private var riskSection: some View {
        PreopSectionTitle(text: PreopSection.risk.title).jumpTarget(section: .risk)
        PreopRiskBox(onOpenRoute: { open($0) })
    }

    /// 6. Preprocedure Summary.
    @ViewBuilder private var summarySection: some View {
        PreopSectionTitle(text: PreopSection.summary.title).jumpTarget(section: .summary)
        PreprocedureSummaryView()
    }

    private static let preopJumps: [PatientJumpItem] = PreopSection.allCases.map { PatientJumpItem(section: $0) }

    /// Screenshot runs: the names -ps.patient.jump and -ps.patient.scroll take for the preoperative tab: its six sections
    /// (procedure, demographics, workup, medications, risk) and the boxes in them; "preopsummary" is the summary view's own id. The cards of earlier
    /// versions keep their names, pointing at the nearest new box: history -> problems, assessment -> asa, support -> cardio.
    private static let jumpKeys: [String: PatientJumpID] = [
        "procedure": PatientJumpID(section: .procedure), "planned": PatientJumpID(section: .procedure),
        "riskinputs": PatientJumpID(anchor: PatientPreop110.riskInputsAnchor), "demographics": PatientJumpID(anchor: "demographics"),
        "workup": PatientJumpID(section: .workup), "medications": PatientJumpID(section: .medications),
        "risk": PatientJumpID(section: .risk),
        "allergies": PatientJumpID(anchor: "allergies"), "problems": PatientJumpID(anchor: "problems"), "chips": PatientJumpID(anchor: "chips"),
        "asa": PatientJumpID(anchor: "asa"), "cardio": PatientJumpID(anchor: "cardio"), "airway": PatientJumpID(anchor: "airway"),
        "labs": PatientJumpID(anchor: "labs"), "devices": PatientJumpID(anchor: "devices"),
        "homemeds": PatientJumpID(anchor: "homemeds"), "infusions": PatientJumpID(anchor: "infusions"), "flagged": PatientJumpID(anchor: "flagged"),
        "preopworkup": PatientJumpID(anchor: "preopworkup"),
        "history": PatientJumpID(anchor: "problems"), "assessment": PatientJumpID(anchor: "asa"), "support": PatientJumpID(anchor: "cardio"),
    ]

    /// The jump bar's sections for the tab (none on Summary & Handoff).
    private var jumpItems: [PatientJumpItem]? {
        switch tab {
        case .preop: return Self.preopJumps
        case .intraop: return IntraopSection.allCases.map { PatientJumpItem(intraop: $0) }
        case .summary: return nil
        }
    }

    /// Lines and devices on arrival, drawn on the patient.
    private var devicesCard: some View {
        NavigationLink(value: PatientEditor.devices("preop")) {
            VStack(alignment: .leading, spacing: 9) {
                sectionHeader(.devices("preop"))
                let lines = PatientSummary.arrivalDeviceLines(r)
                if lines.isEmpty && !r.arrivesWithAirway && r.mechanicalSupport.isEmpty && PatientDeviceFills.limbAlerts(r).isEmpty {
                    Text("Tap to draw the lines, airway and devices the patient arrives with.").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                } else {
                    // The limb alerts open the card, above the figure, as on the Intraoperative tab (1.10 review).
                    PatientDiagramCard.preopCard(r)
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

    /// The 1.10 tab (Ben, Nov 7): five headings in his order (PatientIntraopTab): Airway Course, Lines & Devices,
    /// Medications & Infusions, Fluids & Blood, and Other Intraoperative Details (links). Major considerations, which closed
    /// the tab as a card, is the last of those links, shown in full once filled. The old part keys (-ps.patient.jump
    /// intraop:labs and the like) scroll to the section that now holds the part.
    @ViewBuilder private func intraop(_ proxy: ScrollViewProxy) -> some View {
        noteButton
        CaseTimersStrip()
        jumpBar(proxy, jumpItems ?? []).background(jumpBarReader)
        IntraopSectionTitle(text: IntraopSection.airway.title).jumpTarget(id: PatientJumpID(intraop: .airway))
        IntraopAirwayCourse()
        IntraopSectionTitle(text: IntraopSection.lines.title).jumpTarget(id: PatientJumpID(intraop: .lines))
        IntraopDevicesCard()
        IntraopSectionTitle(text: IntraopSection.meds.title).jumpTarget(id: PatientJumpID(intraop: .meds))
        IntraopInfusionsSection()
        IntraopNotableMedicationLink()
        IntraopSectionTitle(text: IntraopSection.fluids.title).jumpTarget(id: PatientJumpID(intraop: .fluids))
        IntraopFluidsSection()
        IntraopSectionTitle(text: IntraopSection.other.title).jumpTarget(id: PatientJumpID(intraop: .other))
        IntraopOtherDetails()
    }

    @ViewBuilder private var summary: some View {
        QuickAddBar(place: .summaryTab)
        // Status & Plan (1.9): short chips for the airway and the disposition, and To do & Concerns; no folder to open.
        StatusPlanCard()
            .id(PatientEditor.plan)
        if patient.isEmpty {
            Text("The handoff writes itself here as you fill in the other tabs.")
                .font(PS.sys(size: 14)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        } else {
            // The lines and devices figure is the handoff's Lines & devices block (PatientBriefs, 1.9).
            HandoffPanel(record: r).id("handoff")
        }
    }

    // MARK: Top

    /// The quick-add bar (1.8), in place of the Fill from a note card; its pencil opens the full note. The first tip
    /// points at it.
    private var noteButton: some View {
        QuickAddBar(place: tab.quickAddPlace)
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
        if let items = jumpItems {
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
                    jumpBar(proxy, items)
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

    private func jumpBar(_ proxy: ScrollViewProxy, _ items: [PatientJumpItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button { withAnimation(.snappy) { proxy.scrollTo(item.id, anchor: .top) } } label: {
                        Text(item.title)
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
                    sectionHeader(.airway, title: "Airway Examination")
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

    private func sectionHeader(_ e: PatientEditor, title: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: e.icon).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent)
            Text(title ?? e.title).font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
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
    /// The card's title when it is not the editor's own ("Laboratory Studies" for the Labs page).
    var title: String? = nil

    var body: some View {
        NavigationLink(value: editor) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: editor.icon).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent)
                    Text(title ?? editor.title).font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
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

/// The handoff as it stands (1.9: one handoff in Ben's format, no Short or Full), written from the record as you go and
/// editable block by block (BriefPanel): read it, edit it, copy it, share it with the fishbone and the lines diagram as
/// pictures, or send the patient itself to a colleague's Periop Signal so they carry on with the case.
struct HandoffPanel: View {
    @Environment(ReferenceStore.self) private var refs
    var record: PatientRecord

    /// Screenshot runs: -ps.handoff.from Airway starts the handoff at the block whose label begins with it, so a block far
    /// down fits the frame.
    private var startAt: String {
        #if DEBUG
        return LaunchSeed.string("ps.handoff.from")
        #else
        return ""
        #endif
    }

    /// Screenshot runs: -ps.handoff.image 1 shows the pictures that go after the text when the handoff is shared.
    @ViewBuilder private var sharedImageShot: some View {
        #if DEBUG
        if LaunchSeed.string("ps.handoff.image") == "1" {
            let images = HandoffShare.briefImages(PatientBriefs.handoff(record), record: record, figure: refs.bundle?.regional?.figure)
            if !images.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Pictures shared after the text")
                    ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity)
                    }
                }
                .padding(12)
                .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                .id("sharedimage")
            }
        }
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if DEBUG
            // Screenshot runs: -ps.brief preop shows the Preprocedure tab's summary here too (its own tab is helper 5's).
            if LaunchSeed.string("ps.brief") == "preop" { PreprocedureSummaryView() }
            #endif
            BriefPanel(kind: .handoff, startAt: startAt)
            sharedImageShot
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
    var key: String
    init(_ editor: PatientEditor) { key = "editor:\(editor)" }
    /// A section of the Preprocedure tab, or a box in one.
    init(section: PreopSection) { key = "preop:" + section.rawValue }
    /// A box has a key of its own, so a box named like its section ("demographics") is not a second view with the
    /// section title's id.
    init(anchor: String) { key = "preop-box:" + anchor }
    /// A section of the 1.10 Intraoperative tab.
    init(intraop section: IntraopSection) { key = "intraop-section:" + section.rawValue }
}

/// One chip of the jump bar: where it scrolls and its words.
struct PatientJumpItem: Hashable {
    var id: PatientJumpID
    var title: String
    init(_ editor: PatientEditor) { id = PatientJumpID(editor); title = editor.title }
    init(section: PreopSection) { id = PatientJumpID(section: section); title = section.title }
    init(intraop section: IntraopSection) { id = PatientJumpID(intraop: section); title = section.jumpTitle }
}

extension PatientJumpID {
    /// How far above its card a jump anchor sits. Scrolling aligns the anchor with the top of the scroll view's
    /// content, which is already under the inline title, so the anchor clears only the pinned jump bar (about 54 pt,
    /// growing with the in-app text size) and a small margin. (110 pt, meant to clear the title too, landed the card
    /// 70 pt under the bar, after the tail of the box before it: run 375's shots 442–446.)
    static var clearance: CGFloat { 56 * PS.textScale }
}

extension View {
    /// A card the jump bar scrolls to. Its scroll target is a clear anchor stacked above the card, pulled up by
    /// negative padding so the layout is unchanged: scrolling aligns the anchor with the top of the scroll view's
    /// content, under the navigation bar, and PatientJumpID.clearance puts the card just under the pinned jump bar.
    /// (An id in a background is not used by ScrollViewReader; a stacked child is.)
    func jumpTarget(_ editor: PatientEditor) -> some View { jumpTarget(id: PatientJumpID(editor)) }
    /// A section of the Preprocedure tab.
    func jumpTarget(section: PreopSection) -> some View { jumpTarget(id: PatientJumpID(section: section)) }
    /// A box in the Preprocedure tab.
    func jumpTarget(anchor: String) -> some View { jumpTarget(id: PatientJumpID(anchor: anchor)) }

    func jumpTarget(id: PatientJumpID) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: PatientJumpID.clearance)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .id(id)
                #if DEBUG
                .onAppear { ShotReady.targetsShown.insert(id.key) }
                #endif
            self
        }
        .padding(.top, -PatientJumpID.clearance)
    }
}

#if DEBUG
/// Screenshot runs (debug builds): a trace of the -ps.patient.open push and what follows it, in the device log under
/// the "shots" category, which the CI keeps beside each shot of a filtered run.
enum ShotTrace {
    private static let log = Logger(subsystem: "org.periopsignal.app", category: "shots")
    static var on: Bool {
        !LaunchSeed.string("ps.patient.open").isEmpty || !LaunchSeed.string("ps.patient.jump").isEmpty
            || !LaunchSeed.string("ps.patient.scroll").isEmpty
    }
    static func note(_ s: String) {
        guard on else { return }
        log.notice("\(s, privacy: .public)")
    }
}

/// Screenshot runs (debug builds): a launch that opens a page, a tab or a sheet, or jumps the tab, says when that has
/// happened, so the CI waits for it instead of a fixed time alone. At launch it leaves a "pending" file in the app's
/// temporary folder; once the page has been pushed and its transition has ended (the tab under it has gone) and its
/// own launch seeds have had their time (-ps.patient.scroll, -ps.patient.focus), a "ready" file. The CI's shot
/// function waits past its usual time, up to 30 s more, while pending is there and ready is not. The CI's Intel
/// simulator (macos-15-intel, iOS 26) can take 10 s or more to show My Patient and a few more to push the page, which
/// the 1.9.0 build there does too; the shots' fixed waits were set on the faster macos-14 runner.
@MainActor
enum ShotReady {
    private static var page = false
    private static var rootGone = false
    private static var done = false
    private static let folder = URL(fileURLWithPath: NSTemporaryDirectory())
    static let pendingName = "ps-shot-pending"
    static let readyName = "ps-shot-ready"
    /// The tab (the scroll view of My Patient) is on screen, and the jumpTarget anchors laid out so far by key: what a
    /// -ps.patient.scroll on the tab waits for (PatientView.scrollForScreenshot).
    static var rootOnScreen = false
    static var targetsShown: Set<String> = []

    /// The launch asks for something ShotReady reports: a page, the handoff tab, the note or a received patient, a jump,
    /// or a scroll of the tab.
    static var expected: Bool {
        if !LaunchSeed.string("ps.patient.jump").isEmpty { return true }
        let open = LaunchSeed.string("ps.patient.open")
        if open.isEmpty && !LaunchSeed.string("ps.patient.scroll").isEmpty { return true }
        if ["room", "room-tap", "archive", "archive-entry", "end-case"].contains(open) { return false }
        return PatientDeepLink.parse(open) != nil
    }

    /// At launch (the app's init).
    static func begin() {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(readyName))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(pendingName))
        guard expected else { return }
        try? Data().write(to: folder.appendingPathComponent(pendingName))
    }

    static func pageShown() {
        page = true
        settleIfShown()
        // The tab under the page may never report going on some systems: ready a little later anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { rootGone = true; settleIfShown() }
    }

    static func rootHidden() {
        rootGone = true
        settleIfShown()
    }

    /// The page's own launch seeds: scroll at 0.4 s, focus at 1.2 s and again at 2.8 and 4.4 s (PatientEditorView).
    private static func settleIfShown() {
        guard page, rootGone, !done else { return }
        done = true
        var settle = 1.0
        if !LaunchSeed.string("ps.patient.scroll").isEmpty { settle += 1.0 }
        if !LaunchSeed.string("ps.patient.focus").isEmpty { settle = 6.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { ready() }
    }

    static func ready() {
        guard expected else { return }
        ShotTrace.note("ready")
        try? Data().write(to: folder.appendingPathComponent(readyName))
    }
}
#endif
