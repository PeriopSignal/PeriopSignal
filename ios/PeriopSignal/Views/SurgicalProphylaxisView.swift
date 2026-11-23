import SwiftUI

// MARK: - Surgical antibiotic prophylaxis calculator (1.12 follow-up, Ben, Nov 16)
//
// "The Surgical prophylaxis reference is too text heavy and difficult to navigate. Convert this to a calculator where the user can
// click options and choices are given based on input. Place explanations behind info link."
//
// Surgery (a group, then a procedure), the procedure's question where the guideline splits it, β-lactam allergy, known MRSA
// colonization and the weight go in; the agents, each with its dose and redose from Case Timers' own numbers, come out. Every
// explanation sits behind an ⓘ (one small sheet for all of them) and the guideline's tables behind "Full guideline table". All
// of the logic is in SurgicalProphylaxis.swift (`ProphylaxisEngine`); this file only draws it.
//
// Opened from My Patient (a case): the procedure, the allergy and the MRSA screen are prefilled from the case, each with a caption,
// the weight is the case's, and each agent that Case Timers has a dose for can be started there ("Start"). Opened from the
// Reference tab: blank, no captions, no Start. Nothing here writes to the record except "Start".

/// What an ⓘ opens: a title and its paragraphs (as a list for "About"), one component for all of them.
struct ProphylaxisInfoContent: Identifiable, Hashable {
    var id: String
    var title: String
    var paragraphs: [String]
    /// A quieter note under the paragraphs.
    var footnote: String? = nil
    var asList = false
    /// Ben, Nov 23: a result's ⓘ lists the guideline notes first. This many of the first paragraphs are notes: they sit under
    /// "Guideline notes", and the rest under "About this result". 0 for every other sheet (no headings).
    var noteCount = 0

    /// A long text opens full height.
    var isLong: Bool { paragraphs.joined().count > 420 }

    static let notesHeading = "Guideline notes"
    static let aboutHeading = "About this result"

    /// The short heading that stands above paragraph `index`, if one does.
    func heading(at index: Int) -> String? {
        guard noteCount > 0 else { return nil }
        if index == 0 { return Self.notesHeading }
        if index == noteCount, index < paragraphs.count { return Self.aboutHeading }
        return nil
    }
}

struct ProphylaxisInfoSheet: View {
    var content: ProphylaxisInfoContent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(content.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        VStack(alignment: .leading, spacing: 8) {
                            if let heading = content.heading(at: index) {
                                Eyebrow(text: heading)
                                    .padding(.top, index == 0 ? 0 : 6)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            if content.asList {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•").font(PS.sys(size: 15)).foregroundStyle(PS.fg3)
                                    paragraphText(paragraph)
                                }
                            } else {
                                paragraphText(paragraph)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let footnote = content.footnote, !footnote.isEmpty {
                        Text(footnote)
                            .font(PS.sys(size: 13)).foregroundStyle(PS.fg3).lineSpacing(1.5)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
            .background(PS.bg.ignoresSafeArea())
            .navigationTitle(content.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(PS.action)
        .presentationDetents(content.isLong ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func paragraphText(_ s: String) -> some View {
        Text(s)
            .font(PS.sys(size: 15)).foregroundStyle(PS.fg).lineSpacing(2)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The small ⓘ that opens a sheet.
private struct ProphylaxisInfoButton: View {
    var label: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: "info.circle")
                .font(PS.sys(size: 14, weight: .semibold))
                .foregroundStyle(PS.fg3)
                .padding(10).contentShape(Rectangle()).padding(-10)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(label)
        .accessibilityHint("Opens the explanation")
    }
}

/// No / Yes in the app's choice chip look (ink fill when chosen). Not answered (Ben, Nov 19: a penicillin-only allergy is asked):
/// neither is chosen.
private struct ProphylaxisYesNo: View {
    var label: String
    var on: Bool
    var answered: Bool = true
    var onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            chip("No", selected: answered && !on)
            chip("Yes", selected: answered && on)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityValue(answered ? "" : "Not answered")
    }

    private func chip(_ title: String, selected: Bool) -> some View {
        let look = ChipStyle.choice.look(on: selected)
        return Button {
            Haptics.light()
            onChange(title == "Yes")
        } label: {
            Text(title)
                .font(PS.sys(size: 13.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(ChipStyle.color(look.text, tint: PS.action))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(ChipStyle.color(look.fill, tint: PS.action), in: Capsule())
                .overlay(Capsule().stroke(ChipStyle.color(look.edge, tint: PS.action), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Under Case Timers' own page title when the calculator is a page of Case Timers' stack: the open case's label.
private struct ProphylaxisCaseCaption: ViewModifier {
    var on: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if on { content.patientCaseCaption("Antibiotic Prophylaxis") } else { content }
    }
}

/// Screenshot runs only (-ps.proph.scroll bottom): scrolls the page to its end, to see the end of a long list and the footer. In a
/// release build the page is left as it is.
private struct ProphylaxisLaunchScroll: ViewModifier {
    var proxy: ScrollViewProxy
    var bottomID: String

    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG
        content.onAppear {
            guard LaunchSeed.string("ps.proph.scroll") == "bottom" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { proxy.scrollTo(bottomID, anchor: .bottom) }
        }
        #else
        content
        #endif
    }
}

struct SurgicalProphylaxisView: View {
    static let bottomID = "prophylaxis.bottom"

    @Environment(ReferenceStore.self) private var refs
    @Environment(PatientStore.self) private var myPatient
    @Environment(\.dismiss) private var dismiss

    /// Opened from a case in My Patient: the case's procedure, allergy, MRSA screen and weight, and Start.
    var caseBound = false
    /// A page of Case Timers' own stack (its "Which antibiotic?" link): "Open Case Timers" goes back to it.
    var inCaseTimers = false
    var onOpen: (URL) -> Void

    @State private var input = ProphylaxisInput()
    @State private var prefill = ProphylaxisPrefill()
    @State private var didSetUp = false
    /// The Surgery picker reopened with "Change".
    @State private var changing = false
    @State private var weightText = LaunchSeed.string("ps.proph.weight")
    @FocusState private var weightFocused: Bool
    @State private var sheet: ProphylaxisInfoContent?
    @State private var pending: PendingStart?
    /// When each agent was started from here, for "Started 14:32".
    @State private var startedAt: [String: Date] = [:]
    /// "Full guideline table" opened (the existing quick reference).
    @State private var showTable = false

    struct PendingStart: Hashable {
        var drug: String
        var name: String
        var hasRedose: Bool
        var time: String
    }

    private var data: ProphylaxisData? { refs.prophylaxis }
    private var timers: CaseTimerData? { refs.caseTimers ?? CaseAntibiotics.current }

    /// The record the doses are worked out for: the case, or a scratch record that holds only the typed weight.
    private var record: PatientRecord {
        if caseBound { return myPatient.record }
        var r = PatientRecord()
        r.weightKg = WeightField.value(weightText)
        return r
    }

    /// Start is shown only where Case Timers is shown, for a case.
    private var canStartHere: Bool { caseBound && DraftGate.shows("caseTimers") }

    private var showPicker: Bool { input.procedure == nil || changing }

    var body: some View {
        ToolScroll {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 14) {
                    if let data, let timers {
                        content(data, timers)
                    } else {
                        ContentUnavailableView("Not available offline yet", systemImage: "wifi.slash", description: Text("This tool arrives with the next refresh."))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 30)
                .modifier(ProphylaxisLaunchScroll(proxy: proxy, bottomID: Self.bottomID))
            }
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Antibiotic Prophylaxis")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ProphylaxisCaseCaption(on: inCaseTimers))
        .modifier(DebugContentWidth())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { Keyboard.dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.light()
                    if let data { sheet = aboutContent(data) }
                } label: { Image(systemName: "info.circle") }
                .accessibilityLabel("About this calculator")
            }
        }
        .sheet(item: $sheet) { ProphylaxisInfoSheet(content: $0) }
        // An alert, not an action sheet: on an iPhone the sheet's popover hid the answers and its button read as inactive.
        .alert(pending.map { ProphylaxisEngine.startTitle($0.name) } ?? "Start", isPresented: pendingBinding) {
            Button("Start") { confirmStart() }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text(pending.map { ProphylaxisEngine.startMessage(hasRedose: $0.hasRedose) } ?? "")
        }
        .onAppear(perform: setUp)
        .onChange(of: refs.prophylaxis != nil) { _, _ in setUp() }
    }

    private var pendingBinding: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    // MARK: Setting up

    private func setUp() {
        guard !didSetUp, let data = refs.prophylaxis else { return }
        didSetUp = true
        if caseBound {
            let p = ProphylaxisEngine.prefill(record: myPatient.record, data: data)
            prefill = p
            input.apply(p, data: data)
        }
        #if DEBUG
        applyLaunchSeeds(data)
        #endif
    }

    #if DEBUG
    /// Screenshot runs: -ps.proph.group <id>, -ps.proph.procedure <id>, -ps.proph.variant <id>, -ps.proph.allergy 1 (Yes) or 0 (No), -ps.proph.mrsa 1,
    /// -ps.proph.weight 90 (the typed weight of the standalone tool), -ps.proph.change 1 (the Surgery picker reopened),
    /// -ps.proph.info about|allergy|mrsa|result|question|group, -ps.proph.table 1 ("Full guideline table" opened),
    /// -ps.proph.confirm <drug> (the Start question),
    /// -ps.proph.start <drug> (Start tapped), -ps.proph.scroll bottom (the page scrolled to its end: the end of a long list).
    private func applyLaunchSeeds(_ data: ProphylaxisData) {
        let g = LaunchSeed.string("ps.proph.group")
        if !g.isEmpty { input.chooseGroup(g, data: data) }
        let p = LaunchSeed.string("ps.proph.procedure")
        if !p.isEmpty { input.chooseProcedure(p, data: data) }
        let v = LaunchSeed.string("ps.proph.variant")
        if !v.isEmpty { input.chooseVariant(v, data: data) }
        // 1 answers Yes, 0 answers No (also for a case that left the allergy unanswered).
        if LaunchSeed.string("ps.proph.allergy") == "1" { input.setAllergy(true) }
        if LaunchSeed.string("ps.proph.allergy") == "0" { input.setAllergy(false) }
        if LaunchSeed.string("ps.proph.mrsa") == "1" { input.mrsa = true }
        if LaunchSeed.bool("ps.proph.change") { changing = true }
        if LaunchSeed.bool("ps.proph.table") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { showTable = true }
        }
        let kind = LaunchSeed.string("ps.proph.info")
        if !kind.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { sheet = launchInfo(kind, data) }
        }
        let confirm = LaunchSeed.string("ps.proph.confirm")
        if !confirm.isEmpty, let t = timers {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { askToStart(confirm, t) }
        }
        let startDrug = LaunchSeed.string("ps.proph.start")
        if !startDrug.isEmpty, let t = timers {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { startNow(startDrug, t) }
        }
    }

    private func launchInfo(_ kind: String, _ data: ProphylaxisData) -> ProphylaxisInfoContent? {
        switch kind {
        case "about": return aboutContent(data)
        case "allergy": return allergyContent(data)
        case "mrsa": return mrsaContent(data)
        case "question": return input.selectedProcedure(data).flatMap { questionContent($0) }
        case "group": return input.selectedGroup(data).flatMap { groupContent($0) }
        case "result":
            guard let t = timers else { return nil }
            return resultContent(ProphylaxisEngine.answer(input, record: record, data: data, timers: t))
        default: return nil
        }
    }
    #endif

    // MARK: Info contents

    private func aboutContent(_ data: ProphylaxisData) -> ProphylaxisInfoContent {
        ProphylaxisInfoContent(id: "about", title: "About this calculator", paragraphs: data.info.about, asList: true)
    }

    private func allergyContent(_ data: ProphylaxisData) -> ProphylaxisInfoContent {
        ProphylaxisInfoContent(id: "allergy", title: "β-lactam allergy", paragraphs: [data.info.allergy], footnote: data.info.allergyNote)
    }

    private func mrsaContent(_ data: ProphylaxisData) -> ProphylaxisInfoContent {
        ProphylaxisInfoContent(id: "mrsa", title: "Known MRSA colonization", paragraphs: [data.info.mrsa])
    }

    private func questionContent(_ p: ProphylaxisProcedure) -> ProphylaxisInfoContent? {
        guard let text = p.questionInfo, !text.isEmpty else { return nil }
        return ProphylaxisInfoContent(id: "question", title: p.question ?? p.name, paragraphs: [text])
    }

    private func groupContent(_ g: ProphylaxisGroup) -> ProphylaxisInfoContent? {
        guard let text = g.note, !text.isEmpty else { return nil }
        return ProphylaxisInfoContent(id: "group", title: g.name, paragraphs: [text])
    }

    private func resultContent(_ a: ProphylaxisAnswer) -> ProphylaxisInfoContent? {
        guard !a.info.isEmpty else { return nil }
        return ProphylaxisInfoContent(id: "result", title: a.title.isEmpty ? "About this result" : a.title, paragraphs: a.info,
                                      noteCount: a.notes.count)
    }

    // MARK: Content

    @ViewBuilder private func content(_ data: ProphylaxisData, _ timers: CaseTimerData) -> some View {
        let r = record
        let answer = ProphylaxisEngine.answer(input, record: r, data: data, timers: timers)
        inputsCard(data)
        weightRow(r)
        resultCard(answer, r, timers)
        // Wherever an agent of this result has a course in the case (started here or in Case Timers), never from memory alone.
        if canStartHere, answer.allLines.contains(where: { r.timers.course($0.agent) != nil }) { openCaseTimersLink }
        footer(data).id(Self.bottomID)
    }

    private var card: RoundedRectangle { RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous) }

    // MARK: Inputs

    private func inputsCard(_ data: ProphylaxisData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            surgeryBlock(data).padding(14)
            if let p = input.selectedProcedure(data), p.asks, !showPicker {
                Hairline()
                questionBlock(p).padding(14)
            }
            Hairline()
            toggleRow("β-lactam allergy", on: input.betaLactamAllergy, caption: allergyCaption, needsAnswer: input.allergyUnanswered,
                      info: { sheet = allergyContent(data) }) { v in
                withAnimation(.snappy) { input.setAllergy(v) }
            }
            Hairline()
            toggleRow("Known MRSA colonization", on: input.mrsa, caption: mrsaCaption, info: { sheet = mrsaContent(data) }) { v in
                withAnimation(.snappy) { input.mrsa = v }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: card)
    }

    private var procedureCaption: String? {
        guard caseBound, let c = prefill.procedureCaption, input.group == prefill.group else { return nil }
        // True only while it describes the choice: the case's own row, or (a case that selects the group only) no row chosen yet.
        if let p = prefill.procedure { return input.procedure == p ? c : nil }
        return input.procedure == nil ? c : nil
    }

    /// "From the case: Penicillin (rash)" under Yes the case set; while the allergy is asked, the entries and "Not selected for you:
    /// choose." (gone once the user taps No or Yes).
    private var allergyCaption: String? {
        guard caseBound else { return nil }
        if input.allergyUnanswered { return prefill.allergyAsk ? prefill.allergyCaption : nil }
        return prefill.betaLactamAllergy && input.betaLactamAllergy ? prefill.allergyCaption : nil
    }

    private var mrsaCaption: String? {
        caseBound && prefill.mrsa && input.mrsa ? prefill.mrsaCaption : nil
    }

    private func captionText(_ s: String) -> some View {
        Text(s).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func surgeryBlock(_ data: ProphylaxisData) -> some View {
        if showPicker {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Surgery")
                    Spacer(minLength: 8)
                    if changing && input.procedure != nil {
                        Button("Done") { withAnimation(.snappy) { changing = false } }
                            .font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.action)
                    }
                }
                ChipSet(options: data.groups.map { ChipChoice($0.id, $0.chip) }, style: .choice,
                        isOn: { input.group == $0 }, tap: { id in
                    withAnimation(.snappy) {
                        input.chooseGroup(id, data: data)
                        if input.procedure != nil { changing = false }
                    }
                })
                if let g = input.selectedGroup(data) {
                    // A case that selects the group only: say so above the rows, never under the last one as if it were that row's.
                    if prefill.procedure == nil, let c = procedureCaption { captionText(c + ". Choose the row that fits.") }
                    procedureList(g, data)
                }
                if prefill.procedure != nil, let c = procedureCaption { captionText(c) }
            }
        } else if let summary = input.summary(data) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Surgery")
                QuietLinkRow(title: summary, filled: true) { withAnimation(.snappy) { changing = true } }
                if let c = procedureCaption { captionText(c) }
            }
        }
    }

    private func procedureList(_ g: ProphylaxisGroup, _ data: ProphylaxisData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(g.name).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
                if let note = g.note, !note.isEmpty {
                    ProphylaxisInfoButton(label: "About " + g.name) { sheet = groupContent(g) }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            ForEach(Array(g.procedures.enumerated()), id: \.element.id) { i, p in
                Hairline()
                Button {
                    Haptics.light()
                    withAnimation(.snappy) {
                        input.chooseProcedure(p.id, data: data)
                        changing = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(p.name)
                            .font(PS.sys(size: 14.5, weight: input.procedure == p.id ? .semibold : .regular))
                            .foregroundStyle(PS.fg)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if input.procedure == p.id {
                            Image(systemName: "checkmark").font(PS.sys(size: 12, weight: .bold)).foregroundStyle(PS.action)
                        }
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(input.procedure == p.id ? .isSelected : [])
            }
        }
    }

    private func questionBlock(_ p: ProphylaxisProcedure) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(p.question ?? "").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg)
                    .fixedSize(horizontal: false, vertical: true)
                if let c = questionContent(p) {
                    ProphylaxisInfoButton(label: "About: " + c.title) { sheet = c }
                }
                Spacer(minLength: 0)
            }
            if let data {
                ChipSet(options: p.variants.map { ChipChoice($0.id, $0.label ?? $0.id) }, style: .choice,
                        isOn: { input.variant == $0 }, tap: { id in
                    withAnimation(.snappy) { input.chooseVariant(id, data: data) }
                })
            }
        }
    }

    /// `needsAnswer`: neither No nor Yes is chosen and the row has the attention outline the weight field has when a weight is needed.
    private func toggleRow(_ title: String, on: Bool, caption: String?, needsAnswer: Bool = false, info: @escaping () -> Void,
                           change: @escaping (Bool) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    toggleTitle(title, info: info)
                    Spacer(minLength: 8)
                    ProphylaxisYesNo(label: title, on: on, answered: !needsAnswer, onChange: change)
                }
                VStack(alignment: .leading, spacing: 8) {
                    toggleTitle(title, info: info)
                    ProphylaxisYesNo(label: title, on: on, answered: !needsAnswer, onChange: change)
                }
            }
            if let caption { captionText(caption) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay {
            if needsAnswer {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(PS.accent.opacity(0.8), lineWidth: 1.5)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func toggleTitle(_ title: String, info: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg).lineLimit(1).fixedSize()
            ProphylaxisInfoButton(label: "About " + title, action: info)
        }
    }

    // MARK: Weight

    @ViewBuilder private func weightRow(_ r: PatientRecord) -> some View {
        if caseBound {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "scalemass.fill").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg3)
                    Text("Weight").font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                    Spacer(minLength: 8)
                    if let w = r.weightKg, w > 0 {
                        Text(NumText.short(w) + " kg").font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                        Text("From the case").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
                    } else {
                        Text("Not recorded in the case").font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(PS.fg2)
                    }
                }
                if r.weightKg == nil || (r.weightKg ?? 0) <= 0 {
                    captionText("Doses show as the drug's written rule until the case has a weight.")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
        } else {
            // Adult doses only: a child's weight in My Patient is never offered here (the scratch record has no age to lock on).
            CompactWeightField(text: $weightText, focus: $weightFocused, badge: "For doses",
                               patientWeight: CaseTimerEngine.isChild(myPatient.record) ? nil : myPatient.weightKg)
        }
    }

    // MARK: Result

    @ViewBuilder private func resultCard(_ a: ProphylaxisAnswer, _ r: PatientRecord, _ timers: CaseTimerData) -> some View {
        switch a.state {
        case .noProcedure:
            plainCard { Text("Choose the surgery to see the agents.").font(PS.sys(size: 15)).foregroundStyle(PS.fg3) }
        case .question:
            plainCard { Text("Answer the question above to see the agents.").font(PS.sys(size: 15)).foregroundStyle(PS.fg3) }
        default:
            VStack(alignment: .leading, spacing: 12) {
                // Ben, Nov 23: an operation the guideline does not name says so first, in the app's caution style.
                if let flag = a.flag { CautionLine(text: flag, strong: true) }
                resultHeader(a)
                resultBody(a, r, timers)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: card)
            .accessibilityElement(children: .contain)
        }
    }

    private func plainCard<Content: View>(@ViewBuilder _ body: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { body() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: card)
    }

    /// The title, then the evidence grade and the one ⓘ: beside it when they fit on one line, under it when they do not (a long
    /// title or a large text size), so the title never breaks inside "β-lactam".
    private func resultHeader(_ a: ProphylaxisAnswer) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleText(a).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                evidenceAndInfo(a)
            }
            VStack(alignment: .leading, spacing: 6) {
                titleText(a).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) { evidenceAndInfo(a); Spacer(minLength: 0) }
            }
        }
    }

    /// The title with the hyphen of "β-lactam" that does not break the line.
    private func titleText(_ a: ProphylaxisAnswer) -> some View {
        // "No prophylaxis recommended" is the card's title: never the word "Recommended" above it.
        let title: String = a.state == .none ? a.body : a.title
        return Text(title.replacingOccurrences(of: "-", with: "\u{2011}"))
            .font(PS.serif(size: 21, weight: .semibold)).foregroundStyle(PS.fg)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func evidenceAndInfo(_ a: ProphylaxisAnswer) -> some View {
        if let e = a.evidence {
            Text(e).font(PS.mono(size: 10.5, weight: .semibold)).foregroundStyle(PS.fg3).fixedSize()
        }
        if let c = resultContent(a) {
            ProphylaxisInfoButton(label: "About this result") { sheet = c }
        }
    }

    @ViewBuilder private func resultBody(_ a: ProphylaxisAnswer, _ r: PatientRecord, _ timers: CaseTimerData) -> some View {
        switch a.state {
        case .outside, .text, .allergyQuestion:
            Text(a.body).font(PS.sys(size: 15)).foregroundStyle(PS.fg).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            notesLink(a)
        case .none:
            // The headline is the card's title (titleText).
            notesLink(a)
        case .regimens:
            // What changes how every dose below is read comes first.
            if let weightLine = a.weightLine { leadLine(weightLine) }
            if let childLine = a.childLine { leadLine(childLine) }
            if let hint = a.allergyHint { allergyHintLine(hint) }
            regimens(a, r, timers)
            notesLink(a)
            if a.mrsa != nil || a.mrsaNote != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Hairline()
                    Eyebrow(text: a.mrsaTitle ?? ProphylaxisEngine.mrsaTitle)
                    if let m = a.mrsa { agentRow(m, r, timers) }
                    if let n = a.mrsaNote {
                        Text(n).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let timing = a.timing {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "clock").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
                    Text(timing).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                }
            }
        default:
            EmptyView()
        }
    }

    /// A line that changes how the doses below are read (the weight is outside the range; adult doses only), marked and in ink.
    private func leadLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "exclamationmark.triangle").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg2).accessibilityHidden(true)
            Text(text).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Above the agents of the alternative for a β-lactam allergy (Ben, Nov 19): the guideline's own exception, with the allergy ⓘ
    /// (the sheet the allergy row opens) after it.
    @ViewBuilder private func allergyHintLine(_ text: String) -> some View {
        if let data {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(text).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                ProphylaxisInfoButton(label: "About β-lactam allergy") { sheet = allergyContent(data) }
                Spacer(minLength: 0)
            }
        }
    }

    /// Ben, Nov 16: "explanations behind info link". The result's guideline notes are not printed on the card: one quiet line says
    /// how many there are and opens the same sheet as the result's ⓘ, where they come first.
    @ViewBuilder private func notesLink(_ a: ProphylaxisAnswer) -> some View {
        if !a.notes.isEmpty, let c = resultContent(a) {
            Button {
                Haptics.light()
                sheet = c
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "info.circle").font(PS.sys(size: 12, weight: .semibold)).accessibilityHidden(true)
                    Text(ProphylaxisEngine.notesLinkText(a.notes.count)).font(PS.sys(size: 13, weight: .medium))
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(PS.fg3)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ProphylaxisEngine.notesLinkText(a.notes.count))
            .accessibilityHint("Opens the explanation")
        }
    }

    // MARK: Regimens

    @ViewBuilder private func regimens(_ a: ProphylaxisAnswer, _ r: PatientRecord, _ timers: CaseTimerData) -> some View {
        let allSingle = a.regimens.allSatisfy { $0.isSingle }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(a.regimens.enumerated()), id: \.offset) { i, reg in
                if i > 0 { joiner("or") }
                if allSingle {
                    agentRow(reg.slots[0].lines[0], r, timers)
                } else {
                    optionBlock(reg, index: i, count: a.regimens.count, r, timers)
                }
            }
        }
    }

    private func optionBlock(_ reg: ProphylaxisRegimenAnswer, index: Int, count: Int, _ r: PatientRecord, _ timers: CaseTimerData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if count > 1 { Eyebrow(text: "Option \(index + 1)", size: 10) }
            ForEach(Array(reg.slots.enumerated()), id: \.offset) { si, slot in
                joinerBefore(slot, first: si == 0)
                slotView(slot, r, timers)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PS.line2, lineWidth: 1))
    }

    /// The words that lead a slot: "plus", "with or without", and "one of" when the slot offers several agents, so "or" is only
    /// ever said between whole options. The first slot is led only when it is optional or a choice.
    static func joinerWord(optional: Bool, choices: Int, first: Bool) -> String? {
        let many: Bool = choices > 1
        if optional { return many ? "with or without one of" : "with or without" }
        if first { return many ? "one of" : nil }
        return many ? "plus one of" : "plus"
    }

    @ViewBuilder private func joinerBefore(_ slot: ProphylaxisSlotAnswer, first: Bool) -> some View {
        if let word = Self.joinerWord(optional: slot.optional, choices: slot.lines.count, first: first) {
            joiner(word, why: slot.optional ? slot.why : nil)
        }
    }

    /// One slot: a single agent, or its choices set off by a rule down the left so they read as one group.
    @ViewBuilder private func slotView(_ slot: ProphylaxisSlotAnswer, _ r: PatientRecord, _ timers: CaseTimerData) -> some View {
        if slot.lines.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(slot.lines.enumerated()), id: \.offset) { _, line in
                    agentRow(line, r, timers)
                }
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(PS.line2).frame(width: 2) }
        } else if let only = slot.lines.first {
            agentRow(only, r, timers)
        }
    }

    /// "or", "plus", "with or without": the reading order between two rows, in words.
    private func joiner(_ word: String, why: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Rectangle().fill(PS.line).frame(height: 1)
                Text(word.uppercased()).font(PS.mono(size: 10, weight: .semibold)).kerning(1).foregroundStyle(PS.fg3).fixedSize()
                Rectangle().fill(PS.line).frame(height: 1)
            }
            if let why, !why.isEmpty {
                Text(why).font(PS.sys(size: 12)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: One agent

    private func agentRow(_ line: ProphylaxisLine, _ r: PatientRecord, _ timers: CaseTimerData) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                agentText(line)
                Spacer(minLength: 8)
                doseColumn(line, r, timers, trailing: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                agentText(line)
                doseColumn(line, r, timers, trailing: false)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// "Cefazolin, 2 g, Redose every 4 h": the dose is read with its drug, not as a separate stop after it.
    static func spoken(_ line: ProphylaxisLine) -> String {
        let parts: [String?] = [line.name, line.caption, line.dose, line.needs, line.redose, line.noDose, line.note]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func agentText(_ line: ProphylaxisLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.name).font(PS.sys(size: 15.5, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
            if let c = line.caption { Text(c).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3) }
            if let redose = line.redose { Text(redose).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true) }
            if let n = line.noDose { Text(n).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true) }
            if let n = line.note { Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(line))
    }

    private func doseColumn(_ line: ProphylaxisLine, _ r: PatientRecord, _ timers: CaseTimerData, trailing: Bool) -> some View {
        let parts = Self.doseParts(line.dose)
        return VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
            if let head = parts.head {
                Text(head).font(PS.serif(size: 20, weight: .semibold)).foregroundStyle(PS.fg)
                    .multilineTextAlignment(trailing ? .trailing : .leading).fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            if let working = parts.working {
                Text(working).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).multilineTextAlignment(trailing ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
            }
            if let needs = line.needs {
                Text(needs).font(PS.sys(size: 12, weight: .medium)).foregroundStyle(PS.fg2).multilineTextAlignment(trailing ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
            }
            startControl(line, r, timers)
        }
    }

    /// "1,350 mg (15 mg/kg × 90 kg)" → "1,350 mg" and "(15 mg/kg × 90 kg)".
    static func doseParts(_ dose: String?) -> (head: String?, working: String?) {
        guard let dose, !dose.isEmpty else { return (nil, nil) }
        let pieces = dose.components(separatedBy: " (")
        let working = pieces.count > 1 ? "(" + pieces.dropFirst().joined(separator: " (") : nil
        return (pieces[0], working)
    }

    // MARK: Start

    @ViewBuilder private func startControl(_ line: ProphylaxisLine, _ r: PatientRecord, _ timers: CaseTimerData) -> some View {
        if canStartHere && line.startable {
            switch ProphylaxisEngine.startState(line.agent, record: r, timers: timers) {
            case .available:
                    Button {
                        askToStart(line.agent, timers)
                    } label: {
                        Text("Start")
                            .font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accentFg)
                            .padding(.horizontal, 16).padding(.vertical, 6)
                            .background(PS.action, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start " + line.name)
                    .accessibilityHint("Asks to log a dose now and start its redose timer in Case Timers")
            case .running(let last, _):
                // "Started" only while the dose logged from here is still the course's last dose: after an Undo or a removal in
                // Case Timers the record decides, and Start is offered again.
                if let t = startedAt[line.agent], let last, abs(last.timeIntervalSince(t)) < 1 {
                    startedText("Started " + ClockText.time(t))
                } else {
                    startedText("In Case Timers" + (last.map { " · last dose " + ClockText.time($0) } ?? ""))
                }
            case .unavailable:
                EmptyView()
            }
        }
    }

    private func startedText(_ s: String) -> some View {
        Text(s).font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
    }

    private func askToStart(_ drug: String, _ timers: CaseTimerData) {
        guard let def = timers.antibiotic(drug) else { return }
        Haptics.light()
        pending = PendingStart(drug: drug, name: def.name, hasRedose: (def.redoseHours ?? 0) > 0, time: ClockText.time(Date()))
    }

    private func confirmStart() {
        guard let p = pending, let timers else { pending = nil; return }
        pending = nil
        startNow(p.drug, timers)
    }

    /// The same course Case Timers logs for a first dose now, one Undo step, the notification permission asked for as Case Timers
    /// does.
    private func startNow(_ drug: String, _ timers: CaseTimerData) {
        let now = Date()
        var started = false
        withAnimation(.snappy) {
            myPatient.update(discrete: true) { r in
                started = ProphylaxisEngine.start(drug, in: &r, timers: timers, now: now)
            }
        }
        guard started else { return }
        startedAt[drug] = now
        CaseTimerNotifier.shared.requestPermissionIfNeeded()
        Haptics.light()
    }

    @ViewBuilder private var openCaseTimersLink: some View {
        if inCaseTimers {
            Button {
                Haptics.light()
                dismiss()
            } label: { ReferenceLinkLabel(title: IntraopAntibiotic.openCaseTimersLink) }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: RefRoute.caseTimers) {
                ReferenceLinkLabel(title: IntraopAntibiotic.openCaseTimersLink)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { CaseTimersUI.shared.target = CaseTimersView.antibioticCardID })
        }
    }

    // MARK: Footer

    /// The existing quick reference, unchanged: the guideline's complete tables.
    @ViewBuilder private var tableView: some View {
        if let id = data?.quickref, let ref = refs.quickref(id) {
            QuickRefView(ref: ref, onOpen: onOpen)
        } else {
            ContentUnavailableView("Not available offline yet", systemImage: "wifi.slash", description: Text("This reference arrives with the next refresh."))
        }
    }

    private func footer(_ data: ProphylaxisData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(isActive: $showTable) {
                tableView
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tablecells").font(PS.sys(size: 14, weight: .semibold))
                    Text("Full guideline table").font(PS.sys(size: 13.5, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(PS.sys(size: 11, weight: .semibold))
                }
                .foregroundStyle(PS.action)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the guideline's tables")
            Hairline()
            if !data.source.url.isEmpty {
                EvidenceLinks(sources: [EvidenceSource(id: data.source.id, label: data.source.label, url: data.source.url)], onOpen: onOpen)
            }
            if let reviewed = data.reviewed, !reviewed.isEmpty {
                Text("Content reviewed \(PSDate.monthYear(reviewed)).").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
            }
        }
        .padding(.top, 4)
    }
}
