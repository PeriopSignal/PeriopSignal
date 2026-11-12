import SwiftUI
import UserNotifications

// MARK: - Case timers: antibiotic redose, heparin and ACT, protamine, lab checks
//
// Opened from My Patient's ⋯ menu (Case Timers), from Reference → Preoperative & General → Case Timers, or from the
// strip on the Intraoperative tab. 1.10 layout (Ben, Nov 7): "Running timers" first, soonest due at the top, each with
// a live countdown to the second and its due time; then "Add case timers": + Antibiotic, + Lab/ABG timer and
// + Heparin & ACT, each opening its own section, and every section ending with Start timer (start time, and
// "recurring every" from four chips, the last one "Other"). The log is the case record's `timers` (CaseTimers), so
// Undo, the case chips and the archive treat it like any other entry; CaseTimerNotifier turns the reminders of every
// open case into notifications and the lock-screen countdown. Content: reference.json "caseTimers". Times show on the
// 24-hour clock (ClockText), as the rest of the intraoperative record does.
//
// 1.12 follow-up (Ben, Nov 12): Heparin & ACT is one timeline, "Heparin & ACT log": a row per baseline ACT, heparin dose,
// ACT and protamine dose in time order, each with a time the user can set (defaulting to now, never in the future) and
// change; "+ ACT", "+ Heparin dose" and "+ Baseline ACT" open an entry row in place. The ACT reminder is one switch with its
// interval chips, counting from the last ACT logged (CaseTimerEngine.actDue); the old Start timer / Update timer controls,
// the separate dose and ACT blocks and the "Log (n)" list are gone.

@MainActor
@Observable
final class CaseTimersUI {
    static let shared = CaseTimersUI()
    var open = false
    /// The card to open and scroll to when the timers appear (1.12 follow-up: the Medications & Interventions page's
    /// "+ Antibiotic" opens the antibiotic card); read once by the view.
    var target: String?

    /// Opens the timers at the antibiotic card.
    func openAntibiotic() {
        target = CaseTimersView.antibioticCardID
        open = true
    }
}

/// Presents the timers sheet on My Patient's page.
struct CaseTimersPresentation: ViewModifier {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs

    func body(content: Content) -> some View {
        @Bindable var ui = CaseTimersUI.shared
        return content
            .sheet(isPresented: $ui.open) {
                CaseTimersView()
                    .environment(patient)
                    .environment(refs)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                #if DEBUG
                // Screenshot runs: -ps.timers.seed 1 (or tavr) starts made-up timers on the current case;
                // -ps.timers.open 1 opens them.
                CaseTimersDemo.seedIfAsked(patient)
                if LaunchSeed.bool("ps.timers.open") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { CaseTimersUI.shared.open = true }
                }
                #endif
            }
    }
}

#if DEBUG
enum CaseTimersDemo {
    @MainActor static func seedIfAsked(_ patient: PatientStore) {
        let kind = LaunchSeed.string("ps.timers.seed").lowercased()
        guard !kind.isEmpty, kind != "0", patient.record.timers.isEmpty else { return }
        if kind == "tavr" { seedTAVR(patient) } else { seed(patient) }
    }

    /// A bypass case: cefazolin 3 h 40 min ago and vancomycin, 26,000 U of heparin with ACTs, glucose, ABG and
    /// coagulation checks running.
    @MainActor static func seed(_ patient: PatientStore, now: Date = Date()) {
        patient.update(discrete: true) { r in
            if r.weightKg == nil { r.weightKg = 82 }
            if r.ageYears == nil { r.ageYears = 66 }
            var t = CaseTimers()
            t.antibiotics = [
                AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: now.addingTimeInterval(-220 * 60), ebl: 0)], everyMinutes: 240),
                AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: now.addingTimeInterval(-185 * 60), ebl: 0)], everyMinutes: 0),
            ]
            var h = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
            h.acts = [TimedEntry(time: now.addingTimeInterval(-95 * 60), value: 128, baseline: true)]
            h.doses = [TimedEntry(time: now.addingTimeInterval(-80 * 60), value: 26000)]
            h.acts.append(TimedEntry(time: now.addingTimeInterval(-76 * 60), value: 512))
            h.acts.append(TimedEntry(time: now.addingTimeInterval(-44 * 60), value: 468))
            h.doses.append(TimedEntry(time: now.addingTimeInterval(-42 * 60), value: 5000))
            h.acts.append(TimedEntry(time: now.addingTimeInterval(-38 * 60 + 25), value: 545))
            h.bypassOn = now.addingTimeInterval(-70 * 60)
            t.heparin = h
            t.checks["glucose"] = LabCheckCourse(every: 30, started: now.addingTimeInterval(-70 * 60),
                                                 done: [TimedEntry(time: now.addingTimeInterval(-26 * 60 + 13), value: 196)])
            t.checks["abg"] = LabCheckCourse(every: 30, started: now.addingTimeInterval(-70 * 60),
                                             done: [TimedEntry(time: now.addingTimeInterval(-29 * 60 - 20))])
            t.checks["coag"] = LabCheckCourse(every: 60, started: now.addingTimeInterval(-48 * 60 - 40))
            r.timers = t
        }
    }

    /// A TAVR: cefazolin 40 min ago, 7,000 U of heparin with a baseline and one ACT, the ACT timer every 30 min.
    @MainActor static func seedTAVR(_ patient: PatientStore, now: Date = Date()) {
        patient.update(discrete: true) { r in
            if r.weightKg == nil { r.weightKg = 82 }
            if r.ageYears == nil { r.ageYears = 81 }
            var t = CaseTimers()
            t.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: now.addingTimeInterval(-40 * 60), ebl: 0)], everyMinutes: 240)]
            var h = HeparinCourse(purpose: "tavr", goal: 250, actEvery: 30)
            h.acts = [TimedEntry(time: now.addingTimeInterval(-31 * 60), value: 131, baseline: true)]
            h.doses = [TimedEntry(time: now.addingTimeInterval(-25 * 60), value: 7000)]
            h.acts.append(TimedEntry(time: now.addingTimeInterval(-19 * 60 - 30), value: 271))
            h.actStart = now.addingTimeInterval(-19 * 60 - 30)
            t.heparin = h
            r.timers = t
        }
    }
}
#endif

// MARK: - The strip on the Intraoperative tab

/// What is due next, in one line per timer, at the top of the Intraoperative tab; a tap opens the timers. Nothing
/// shows until a timer is running (they start from ⋯ → Case Timers).
struct CaseTimersStrip: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs

    var body: some View {
        if DraftGate.shows("caseTimers"), let d = refs.caseTimers, !patient.record.timers.isEmpty {
            TimelineView(.periodic(from: .now, by: 20)) { ctx in
                let items = CaseTimerEngine.reminders(patient.record.timers, record: patient.record, data: d)
                Button { CaseTimersUI.shared.open = true } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Eyebrow(text: "Case timers", color: PS.accent2)
                            Spacer()
                            Image(systemName: "chevron.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                        }
                        if items.isEmpty {
                            Text("Nothing due").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                        }
                        ForEach(items.prefix(3)) { rem in
                            CaseReminderLine(reminder: rem, now: ctx.date, compact: true)
                        }
                    }
                    .padding(14)
                    .background(PS.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PS.line2, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the case timers")
            }
        }
    }
}

/// "● Cefazolin redose · 11:55 · in 14 min".
struct CaseReminderLine: View {
    var reminder: CaseReminder
    var now: Date
    var compact = false

    var body: some View {
        let state = reminder.state(at: now)
        let tone: Color = state == .waiting ? PS.fg3 : (state == .due ? PS.accent : PS.red)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(tone).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title).font(PS.sys(size: compact ? 14 : 15, weight: .semibold)).foregroundStyle(PS.fg)
                if !compact {
                    Text(reminder.detail).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                if let due = reminder.due {
                    Text(ClockText.time(due)).font(PS.mono(size: 12, weight: .semibold)).foregroundStyle(PS.fg2)
                }
                Text(state == .waiting ? ClockText.relative(reminder.due, now: now) : (state == .due ? "Due" : "Overdue " + ClockText.relative(reminder.due, now: now).replacingOccurrences(of: " ago", with: "")))
                    .font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(tone)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Small parts

/// One chip row; the caller decides what a tap does (ChipToggle: a second tap clears).
private struct TimerChipRow: View {
    struct Chip: Identifiable { var id: String; var label: String; var on: Bool; var a11y: String? = nil }
    var chips: [Chip]
    var onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(chips) { c in
                Button {
                    Haptics.light()
                    withAnimation(.snappy) { onTap(c.id) }
                } label: {
                    Text(c.label)
                        .font(PS.sys(size: 13.5, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 7)  // 10 pt (as the Labs and infusion chips): four chips with a chosen Other value fit one line at 375 pt
                        // 1.11 (P1-8): the chosen chip in the action tint with the heavier edge (ChipStyle.toggle's one-line
                        // form), not the brand red; the chip keeps its width, so the rows sized for 375 pt still fit.
                        .background(c.on ? PS.action.opacity(0.18) : PS.surface2, in: Capsule())
                        .overlay(Capsule().stroke(c.on ? PS.action : PS.line2, lineWidth: c.on ? ChipMetrics.heavyEdge : 1))
                        .foregroundStyle(PS.fg)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(c.a11y ?? c.label)
                .accessibilityAddTraits(c.on ? .isSelected : [])
                .accessibilityHint(c.on ? "Tap again to clear" : "")
            }
        }
    }
}

/// The Start / Update timer button at the bottom of each section. With nothing to start it is drawn in the neutral chip
/// fill with secondary text at full opacity (review 1.10: the accent capsule faded to 0.45 left "Start timer" at about
/// 1.2:1 in dark and 1.9:1 in light); it still reads as inactive because it loses the accent fill.
struct TimerStartButtonStyle: ButtonStyle {
    var active: Bool

    struct Look { var fill: Color; var text: Color; var stroke: Color; var opacity: Double }
    static func look(active: Bool) -> Look {
        active ? Look(fill: PS.action, text: PS.accentFg, stroke: .clear, opacity: 1)
               : Look(fill: PS.surface2, text: PS.fg2, stroke: PS.line, opacity: 1)
    }

    func makeBody(configuration: Configuration) -> some View {
        let l = Self.look(active: active)
        return configuration.label
            .font(PS.sys(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(l.fill, in: Capsule())
            .foregroundStyle(l.text)
            .overlay(Capsule().stroke(l.stroke, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : l.opacity)
    }
}

/// "Recurring every": three interval chips and Other, which opens a wheel in 5-minute steps at its best guess.
private struct RecurrenceRow: View {
    var label: String
    var chips: [Double]
    @Binding var pick: RecurrencePick
    var preferred: Double
    var maxMinutes: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(PS.sys(size: 12.5, weight: .medium)).foregroundStyle(PS.fg3)
            TimerChipRow(chips: chips.map { m in
                TimerChipRow.Chip(id: "m\(m)", label: CaseTimerEngine.interval(m), on: pick.chipOn(m))
            } + [TimerChipRow.Chip(id: "other", label: CaseTimerRecurrence.otherChipLabel(pick),
                                   on: pick.other, a11y: CaseTimerRecurrence.otherChipA11y(pick))]) { id in
                if id == "other" {
                    pick.tapOther(preselect: CaseTimerRecurrence.otherPreselect(current: pick.minutes, preferred: preferred, maxMinutes: maxMinutes))
                } else if let m = chips.first(where: { "m\($0)" == id }) {
                    pick.tapChip(m)
                }
            }
            if pick.other {
                Picker("Interval", selection: Binding(get: { pick.minutes ?? preferred }, set: { pick.setOther($0) })) {
                    ForEach(CaseTimerRecurrence.otherValues(maxMinutes: maxMinutes), id: \.self) { v in
                        Text(CaseTimerEngine.interval(v)).tag(v)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                .clipped()
                .accessibilityLabel(label + ", other interval")
            }
        }
    }
}

/// "Start time" on the 24-hour clock: the current time, kept current, until the user picks one (StartTimePick).
private struct StartTimeRow: View {
    @Binding var start: StartTimePick

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            DatePicker("Start time", selection: Binding(get: { start.shown(now: ctx.date) }, set: { start.picked = $0 }),
                       displayedComponents: [.hourAndMinute])
                .font(PS.sys(size: 14.5, weight: .medium))
                .foregroundStyle(PS.fg)
                .tint(PS.action)
                .environment(\.locale, PatientDates.locale24)
        }
    }
}

/// The add rows under "Add case timers": "+ Antibiotic", turning to "−" while its section is open.
private struct AddRow: View {
    var title: String
    var detail: String?
    var open: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: open ? "minus.circle.fill" : "plus.circle.fill")
                    .font(PS.sys(size: 18, weight: .semibold)).foregroundStyle(PS.action)
                Text(title).font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
                Spacer(minLength: 6)
                if let detail { Text(detail).font(PS.sys(size: 12.5, weight: .medium)).foregroundStyle(PS.fg3).lineLimit(1) }
                Image(systemName: open ? "chevron.up" : "chevron.down").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(open ? PS.action.opacity(0.45) : PS.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(open ? "Open" : "Closed")
    }
}

/// An entry being added under the timeline: its kind, its value, the time picked (nil: now, kept current).
private struct HeparinDraft {
    var kind: HeparinEvent.Kind
    var value: Double?
    var picked: Date?
    var armed = false
}

/// A timeline row opened in place: the value being typed, the time picked (nil: unchanged) and the second-tap states.
private struct HeparinRowEdit {
    var id: UUID
    var kind: HeparinEvent.Kind
    var value: Double?
    /// The row's logged time: what the time control shows until another is picked.
    var shown: Date
    var picked: Date?
    var armed = false
    var deleteArmed = false
}

/// "Time" on the 24-hour clock for a timeline entry: now (kept current) for a new one, the row's own time for an edit, until
/// the user picks one.
private struct EntryTimeRow: View {
    var base: Date?
    @Binding var picked: Date?

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            DatePicker("Time", selection: Binding(get: { picked ?? base ?? ctx.date }, set: { picked = $0 }),
                       displayedComponents: [.hourAndMinute])
                .font(PS.sys(size: 14.5, weight: .medium))
                .foregroundStyle(PS.fg)
                .tint(PS.action)
                .environment(\.locale, PatientDates.locale24)
        }
    }
}

// MARK: - The timers

struct CaseTimersView: View {
    /// A sheet from My Patient (its own navigation bar and Done); false: pushed from Reference → Preoperative & General.
    var inSheet = true
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    @Environment(\.dismiss) private var dismiss

    enum Section: String, CaseIterable { case antibiotic, labs, heparin }

    @State private var webLink: WebLink?
    @State private var openSections: Set<Section> = []
    @State private var didSetUp = false
    @State private var didSeed = false
    @State private var scrollTarget: String?
    /// The leave-with-an-antibiotic-pending question (1.12 follow-up).
    @State private var showLeave = false

    /// The antibiotic card's scroll id.
    static let antibioticCardID = "antibiotic.card"

    // Antibiotic
    @State private var abxPending: [String] = []
    @State private var abxPicks: [String: RecurrencePick] = [:]
    @State private var abxStart = StartTimePick()
    // Labs
    @State private var labPicks: [String: RecurrencePick] = [:]
    @State private var labStart = StartTimePick()
    @State private var glucoseValue: Double?
    // Heparin
    /// The entry being added under the timeline, and the row opened in place (1.12 follow-up); at most one of the two.
    @State private var draft: HeparinDraft?
    @State private var rowEdit: HeparinRowEdit?
    @State private var protamineMg: Double?
    @State private var protamineArmed = false
    @State private var weightEntry: Double?
    @State private var weightArmed = false
    @State private var goalEditing = false
    @State private var goalEntry: Double?
    @State private var goalArmed = false
    @State private var actPick: RecurrencePick?
    @State private var goalInfoOpen = LaunchSeed.bool("ps.evidence.open")
    @State private var protamineInfoOpen = LaunchSeed.bool("ps.evidence.open")

    private var r: PatientRecord { patient.record }
    private var t: CaseTimers { patient.record.timers }

    var body: some View {
        Group {
            if inSheet { NavigationStack { page } } else { page }
        }
        .fullScreenCover(item: $webLink) { link in SafariView(url: link.url).ignoresSafeArea() }
        // An antibiotic picked and not logged is not lost by a swipe: the sheet stays until Done asks (1.12 follow-up).
        .interactiveDismissDisabled(inSheet && !pendingDrugs.isEmpty)
        .onAppear(perform: setUp)
        #if DEBUG
        // The reference data loads asynchronously (RootView: the route is set before refs.load()), so a screenshot's
        // picks wait for it instead of being dropped when the page appears first (review 1.10: 502–507, 516, 517).
        .onChange(of: refs.caseTimers != nil) { _, ready in
            if ready, didSetUp, let d = refs.caseTimers { applyLaunchSeeds(d) }
        }
        #endif
    }

    private var page: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let d = refs.caseTimers {
                    VStack(alignment: .leading, spacing: 18) {
                        DraftBanner(section: "caseTimers")
                        if !inSheet {
                            // From Reference: the timers belong to My Patient's open case.
                            Label("For \(patient.currentCase.label), the open case in My Patient", systemImage: "person.text.rectangle")
                                .font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg2)
                        }
                        runningCard(d).id("running")
                        addSection(d)
                        footer(d)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                } else {
                    ContentUnavailableView("Not available offline yet", systemImage: "wifi.slash", description: Text("The timers arrive with the next refresh."))
                }
            }
            .onChange(of: scrollTarget) { _, id in
                guard let id else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.snappy) { proxy.scrollTo(id, anchor: .top) }
                    scrollTarget = nil
                }
            }
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Case Timers")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!inSheet && !pendingDrugs.isEmpty)
        .confirmationDialog(leaveTitle, isPresented: $showLeave, titleVisibility: .visible) {
            Button("Log dose") { logPendingAndLeave() }
            Button("Discard", role: .destructive) { discardPendingAndLeave() }
            Button("Keep editing", role: .cancel) {}
        }
        .toolbar {
            if inSheet {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { requestLeave() }.fontWeight(.semibold).tint(PS.action) }
            }
            if !inSheet && !pendingDrugs.isEmpty {
                // The back arrow of a page pushed from Reference asks first, too (the system one is hidden meanwhile).
                ToolbarItem(placement: .topBarLeading) {
                    Button { requestLeave() } label: { Label("Back", systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                        .tint(PS.action)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { Keyboard.dismiss() }
            }
        }
    }

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        #if DEBUG
        // Screenshot runs from Reference (-ps.ref case-timers): the made-up timers start here.
        if !inSheet { CaseTimersDemo.seedIfAsked(patient) }
        #endif
        var open: Set<Section> = []
        if !t.antibiotics.isEmpty { open.insert(.antibiotic) }
        if !t.checks.isEmpty { open.insert(.labs) }
        if t.heparin != nil { open.insert(.heparin) }
        #if DEBUG
        // -ps.timers.sections "antibiotic,labs,heparin"; -ps.timers.pick "vancomycin" (antibiotics added, not started);
        // -ps.timers.labs "abg:30,coag" (lab chips picked); -ps.timers.other antibiotic|labs:<id>|act (Other open);
        // -ps.timers.purpose tavr (a purpose picked); -ps.timers.scroll <section id>.
        let asked = LaunchSeed.list("ps.timers.sections")
        if !asked.isEmpty { open = Set(asked.compactMap(Section.init(rawValue:))) }
        if let d = refs.caseTimers { applyLaunchSeeds(d) }
        #endif
        // Opened from the Medications & Interventions page's "+ Antibiotic": the antibiotic card, scrolled to.
        if let target = CaseTimersUI.shared.target {
            CaseTimersUI.shared.target = nil
            if target == Self.antibioticCardID { open.insert(.antibiotic) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { scrollTarget = target }
        }
        openSections = open
    }

    // MARK: Leaving with an antibiotic picked and not logged

    /// The antibiotics picked in this visit that no dose has been logged for.
    private var pendingDrugs: [String] { abxPending.filter { t.course($0) == nil } }

    private var leaveTitle: String {
        IntraopAntibiotic.leaveTitle(names: pendingDrugs.map { IntraopAntibiotic.name($0, in: refs.caseTimers) },
                                     at: ClockText.time(abxStart.resolved(now: Date())))
    }

    private func requestLeave() {
        if pendingDrugs.isEmpty { dismiss() } else { Haptics.light(); showLeave = true }
    }

    private func logPendingAndLeave() {
        if let d = refs.caseTimers { startAntibiotics(pendingDrugs, changes: abxChanges(d)) }
        dismiss()
    }

    private func discardPendingAndLeave() {
        for drug in pendingDrugs { abxPicks[drug] = nil }
        abxPending = []
        dismiss()
    }

    #if DEBUG
    /// The launch-argument picks that need the reference data, applied once: from setUp when the data is already
    /// loaded, else when it arrives. The purpose is picked before -ps.timers.other act, because picking a purpose
    /// clears the ACT pick. The scroll waits for the picks so it lands on the laid-out row.
    private func applyLaunchSeeds(_ d: CaseTimerData) {
        guard !didSeed else { return }
        didSeed = true
        abxPending = LaunchSeed.list("ps.timers.pick").filter { d.antibiotic($0) != nil && t.course($0) == nil }
        for id in abxPending { if let def = d.antibiotic(id) { abxPicks[id] = RecurrencePick(minutes: CaseTimerRecurrence.antibioticDefault(def)) } }
        // -ps.timers.leave 1: the question asked on leaving with a pick pending.
        if LaunchSeed.bool("ps.timers.leave"), !abxPending.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showLeave = true } }
        for item in LaunchSeed.list("ps.timers.labs") {
            let parts = item.split(separator: ":").map(String.init)
            guard let def = d.check(parts[0]) else { continue }
            labPicks[def.id] = RecurrencePick(minutes: parts.count > 1 ? Double(parts[1]) : CaseTimerRecurrence.labChips(def).first)
        }
        let purpose = LaunchSeed.string("ps.timers.purpose")
        if !purpose.isEmpty, t.heparin == nil, d.purpose(purpose) != nil { pickPurpose(purpose, d) }
        let other = LaunchSeed.string("ps.timers.other")
        if other == "antibiotic", let id = abxPending.first, let def = d.antibiotic(id) {
            abxPicks[id] = RecurrencePick(minutes: CaseTimerRecurrence.antibioticPreferred(def, rules: d.antibioticRules) + 30, other: true)
        } else if other.hasPrefix("labs:"), let def = d.check(String(other.dropFirst(5))) {
            labPicks[def.id] = RecurrencePick(minutes: 45, other: true)
        } else if other == "act" {
            actPick = RecurrencePick(minutes: 45, other: true)
        }
        // -ps.timers.hep.add act|dose|baseline [-ps.timers.hep.value 512]: the entry row open under the timeline;
        // -ps.timers.hep.edit <row, from 0>: that row opened in place.
        let add = LaunchSeed.string("ps.timers.hep.add")
        if let h = t.heparin, let p = d.purpose(h.purpose), let kind = ["act": HeparinEvent.Kind.act, "dose": .heparin, "baseline": .baseline][add] {
            var dr = HeparinDraft(kind: kind)
            dr.value = Double(LaunchSeed.string("ps.timers.hep.value")) ?? (kind == .heparin && h.doses.isEmpty ? CaseTimerEngine.suggestedBolus(p, weightKg: r.weightKg) : nil)
            draft = dr
        }
        if let h = t.heparin, let i = Int(LaunchSeed.string("ps.timers.hep.edit")), h.timeline.indices.contains(i) {
            let e = h.timeline[i]
            rowEdit = HeparinRowEdit(id: e.id, kind: e.kind, value: e.value, shown: e.time)
        }
        let scroll = LaunchSeed.string("ps.timers.scroll")
        if !scroll.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { scrollTarget = scroll } }
    }
    #endif

    private func edit(_ change: (inout CaseTimers) -> Void) {
        withAnimation(.snappy) { patient.update(discrete: true) { change(&$0.timers) } }
        CaseTimerNotifier.shared.requestPermissionIfNeeded()
    }

    private func openLink(_ url: URL) { webLink = WebLink(url: url) }

    private func toggle(_ s: Section) {
        withAnimation(.snappy) {
            if openSections.contains(s) { openSections.remove(s) } else {
                openSections.insert(s)
                switch s {
                case .antibiotic: abxStart = StartTimePick()
                case .labs: labStart = StartTimePick()
                case .heparin: draft = nil; rowEdit = nil
                }
                scrollTarget = s.rawValue
            }
        }
    }

    private func show(_ s: Section, at anchor: String? = nil) {
        withAnimation(.snappy) { _ = openSections.insert(s) }
        scrollTarget = anchor ?? s.rawValue
    }

    // MARK: Running timers

    @ViewBuilder private func runningCard(_ d: CaseTimerData) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let items = CaseTimerEngine.reminders(t, record: r, data: d)
            let tint: Color? = items.isEmpty ? nil : (items.contains { $0.state(at: ctx.date) != .waiting } ? PS.accent : PS.accent2)
            ToolCard(tint: tint) {
                Eyebrow(text: "Running timers")
                if items.isEmpty {
                    Text("None running. Add one below.").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { i, rem in
                    if i > 0 { Hairline() }
                    runningRow(rem, d, now: ctx.date)
                }
            }
        }
    }

    @ViewBuilder private func runningRow(_ rem: CaseReminder, _ d: CaseTimerData, now: Date) -> some View {
        let state = rem.state(at: now)
        let tone: Color = state == .waiting ? PS.fg : (state == .due ? PS.accent : PS.red)
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(state == .waiting ? PS.fg3 : tone).frame(width: 7, height: 7)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                Text(rem.title).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Text(rem.due == nil ? "Due now" : CaseTimerEngine.countdown(to: rem.due, now: now))
                    .font(PS.mono(size: 16, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .fixedSize()
            }
            // What the timer is for, under its title, as 1.9's Next list had it (1.10 review): the ACT goal and interval,
            // the antibiotic dose and interval, the check interval. A row with no due time shows it once, as its due line.
            let text = Self.runningText(rem, state: state)
            if let detail = text.detail {
                Text(detail)
                    .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text(text.due)
                    .font(PS.sys(size: 12.5, weight: state == .overdue ? .semibold : .regular))
                    .foregroundStyle(state == .overdue ? PS.red : PS.fg2)
                    .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(doneTitle(rem)) { done(rem, d) }
                    .buttonStyle(CapsuleButtonStyle.patientAction(prominent: state != .waiting))
                if state != .waiting {
                    Button("Snooze 5") { edit { $0.snooze(rem, now: Date()) } }
                        .buttonStyle(CapsuleButtonStyle(prominent: false))
                        .accessibilityLabel("Snooze 5 minutes")
                }
                Menu {
                    Button(role: .destructive) { edit { $0.stop(rem) } } label: { Label(stopTitle(rem), systemImage: "stop.circle") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(PS.sys(size: 18)).foregroundStyle(PS.fg3)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .accessibilityLabel(rem.title + " options")
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The two lines under a running timer's title: its detail ("Goal ≥ 480 s · every 30 min", "2 g · every 4 h from the
    /// last dose", "Every 30 min") and its due line ("Due at 07:19", "Overdue · due at 07:11"). A reminder with no due time
    /// (blood loss) has its detail as its due line and no separate detail, so nothing shows twice.
    static func runningText(_ rem: CaseReminder, state: CaseReminder.State) -> (detail: String?, due: String) {
        guard let due = rem.due else { return (nil, rem.detail) }
        let at = (rem.snoozed ? "Snoozed to " : "Due at ") + ClockText.time(due)
        let detail = rem.detail.trimmingCharacters(in: .whitespaces)
        return (detail.isEmpty ? nil : detail, state == .overdue ? "Overdue · " + at.lowercasedFirst : at)
    }

    private func doneTitle(_ rem: CaseReminder) -> String {
        switch rem.kind {
        case .antibiotic, .longCase, .bloodLoss: return "Given"
        case .abg, .lab: return "Sent"
        case .glucose, .act, .protamineACT: return "Log"
        }
    }

    private func stopTitle(_ rem: CaseReminder) -> String {
        switch rem.kind {
        case .antibiotic: return "Stop the redose timer"
        case .abg, .glucose, .lab: return "Stop this check"
        case .act: return "Stop the ACT timer"
        case .longCase, .bloodLoss, .protamineACT: return "Dismiss"
        }
    }

    private func done(_ rem: CaseReminder, _ d: CaseTimerData) {
        Haptics.light()
        switch rem.kind {
        case .glucose: show(.labs, at: "lab.glucose")
        case .act, .protamineACT:
            // A due ACT needs a value: the timeline's "+ ACT" entry opens, at now.
            show(.heparin, at: "heparin.act")
            if t.heparin != nil { rowEdit = nil; draft = HeparinDraft(kind: .act) }
        default:
            let ebl = r.fluids["ebl"]
            edit { _ = $0.markDone(rem, now: Date(), ebl: ebl) }
        }
    }

    // MARK: Add case timers

    @ViewBuilder private func addSection(_ d: CaseTimerData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Add case timers")
            if CaseTimerEngine.isChild(r) {
                ToolCard(tint: PS.red) {
                    Text("Adult defaults only").font(PS.serif(size: 20)).foregroundStyle(PS.fg)
                    Text("The antibiotic and heparin doses here are for adults; they are locked for a child. The lab checks still work.")
                        .font(PS.sys(size: 14)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                AddRow(title: "Antibiotic", detail: t.antibiotics.isEmpty ? nil : "\(t.antibiotics.count) running",
                       open: openSections.contains(.antibiotic)) { toggle(.antibiotic) }
                    .id("antibiotic")
                if openSections.contains(.antibiotic) { antibioticSection(d) }
            }
            AddRow(title: "Lab/ABG timer", detail: t.checks.isEmpty ? nil : "\(t.checks.count) running",
                   open: openSections.contains(.labs)) { toggle(.labs) }
                .id("labs")
            if openSections.contains(.labs) { labsSection(d) }
            if !CaseTimerEngine.isChild(r) {
                AddRow(title: "Heparin & ACT", detail: t.heparin.flatMap { d.purpose($0.purpose)?.name },
                       open: openSections.contains(.heparin)) { toggle(.heparin) }
                    .id("heparin")
                if openSections.contains(.heparin) { heparinSection(d) }
            }
        }
    }

    // MARK: Antibiotic

    private func abxPick(_ drug: String, _ d: CaseTimerData) -> Binding<RecurrencePick> {
        Binding(get: {
            if let p = abxPicks[drug] { return p }
            guard let def = d.antibiotic(drug) else { return RecurrencePick() }
            if let c = t.course(drug) {
                return RecurrencePick(running: CaseTimerRecurrence.redoseMinutes(c, def: def), chips: CaseTimerRecurrence.antibioticChips(def))
            }
            return RecurrencePick(minutes: CaseTimerRecurrence.antibioticDefault(def))
        }, set: { abxPicks[drug] = $0 })
    }

    /// Interval changes on running antibiotics, by drug.
    private func abxChanges(_ d: CaseTimerData) -> [String: Double] {
        var out: [String: Double] = [:]
        for (drug, pick) in abxPicks {
            guard let c = t.course(drug), let def = d.antibiotic(drug) else { continue }
            let now = CaseTimerRecurrence.redoseMinutes(c, def: def) ?? 0
            let new = CaseTimerRecurrence.storedInterval(pick)
            if new != now { out[drug] = new }
        }
        return out
    }

    @ViewBuilder private func antibioticSection(_ d: CaseTimerData) -> some View {
        let drugs = t.antibiotics.map(\.drug) + abxPending.filter { t.course($0) == nil }
        let changes = abxChanges(d)
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Antibiotic", info: d.antibioticRules.fromStart + " " + d.antibioticRules.closure)
            ToolCard {
                ForEach(Array(drugs.enumerated()), id: \.element) { i, drug in
                    if i > 0 { Hairline() }
                    if let def = d.antibiotic(drug) { antibioticRow(def, d) }
                }
                Menu {
                    ForEach(d.antibiotics.filter { !drugs.contains($0.id) }) { a in
                        Button(a.name + (a.redoseHours.map { " · every \(CaseTimerEngine.fmt($0)) h" } ?? " · no redose")) {
                            abxPending.append(a.id)
                            abxPicks[a.id] = RecurrencePick(minutes: CaseTimerRecurrence.antibioticDefault(a))
                        }
                    }
                } label: {
                    Label(drugs.isEmpty ? "Choose the antibiotic" : "Add another antibiotic", systemImage: "plus")
                        .font(PS.sys(size: 14.5, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(PS.surface2, in: Capsule())
                        .foregroundStyle(PS.fg)
                }
                let pending = abxPending.filter { t.course($0) == nil }
                let update = pending.isEmpty && !changes.isEmpty
                // 1.12 follow-up: the button says what it does for what is pending (a drug with no routine redose has no
                // interval chosen, and "Start timer" read as if there were nothing to start).
                let anyInterval = hasInterval(pending, d)
                let title = IntraopAntibiotic.buttonTitle(pending: !pending.isEmpty, anyInterval: anyInterval, onlyChanges: update)
                Hairline()
                if !update { StartTimeRow(start: $abxStart) }
                Button {
                    startAntibiotics(pending, changes: changes)
                } label: {
                    Text(title).frame(maxWidth: .infinity)
                }
                .buttonStyle(TimerStartButtonStyle(active: !(pending.isEmpty && changes.isEmpty)))
                .disabled(pending.isEmpty && changes.isEmpty)
                .accessibilityHint(IntraopAntibiotic.buttonHint(pending: !pending.isEmpty, anyInterval: anyInterval, onlyChanges: update))
                if !pending.isEmpty {
                    Text(IntraopAntibiotic.pendingNote(buttonTitle: title))
                        .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .id(Self.antibioticCardID)
    }

    @ViewBuilder private func antibioticRow(_ def: AntibioticDef, _ d: CaseTimerData) -> some View {
        let course = t.course(def.id)
        let dose = CaseTimerEngine.antibioticDose(def, record: r)
        let chips = CaseTimerRecurrence.antibioticChips(def)
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(def.name).font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
                Text(dose.text).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).lineLimit(2)
                Spacer(minLength: 4)
                EvidenceTag(text: "G", url: d.sources(["bratzler"]).first.flatMap { URL(string: $0.url) }, onOpen: openLink)
                if course != nil {
                    Menu {
                        Button(role: .destructive) {
                            edit { $0.antibiotics.removeAll { $0.drug == def.id } }
                            abxPicks[def.id] = nil
                        } label: { Label("Remove \(def.name) from this case", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle").font(PS.sys(size: 17)).foregroundStyle(PS.fg3) }
                    .accessibilityLabel(def.name + " options")
                } else {
                    Button {
                        abxPending.removeAll { $0 == def.id }; abxPicks[def.id] = nil
                    } label: { Image(systemName: "xmark.circle.fill").font(PS.sys(size: 17)).foregroundStyle(PS.fg3) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove " + def.name)
                }
            }
            if let needs = dose.needs { Text(needs).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent) }
            RecurrenceRow(label: def.redoseHours == nil ? "Redose every (no routine redose)" : "Redose every",
                          chips: chips, pick: abxPick(def.id, d),
                          preferred: CaseTimerRecurrence.antibioticPreferred(def, rules: d.antibioticRules),
                          maxMinutes: CaseTimerRecurrence.antibioticMax)
            if let n = def.note { Text(n).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true) }
            if let c = def.cardiac, t.heparin.flatMap({ d.purpose($0.purpose) })?.isCardiac == true || r.procedure.lowercased().contains("bypass") {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(c).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                    EvidenceTag(text: "G?", url: d.sources(["sts2007"]).first.flatMap { URL(string: $0.url) }, onOpen: openLink)
                }
            }
            if CaseTimerEngine.renalCaution(r) {
                Label(d.antibioticRules.renal, systemImage: "exclamationmark.triangle")
                    .font(PS.sys(size: 12.5, weight: .medium)).foregroundStyle(PS.accent).fixedSize(horizontal: false, vertical: true)
            }
            if let course, let last = course.last {
                let every = CaseTimerRecurrence.redoseMinutes(course, def: def)
                // A dose typed in the quick-add bar is shown as typed beside the last dose when it says more than the computed one.
                HStack(spacing: 10) {
                    Text(Self.lastDoseText(last: last, every: every, computed: dose.text))
                        .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2)
                    Spacer(minLength: 4)
                    Button("Redose given") {
                        let ebl = r.fluids["ebl"] ?? 0
                        edit { t in
                            if let i = t.antibiotics.firstIndex(where: { $0.drug == def.id }) { t.antibiotics[i].doses.append(TimedEntry(time: Date(), ebl: ebl)) }
                        }
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
                }
                if course.doses.count > 1 {
                    DoseHistory(entries: course.doses, text: { Self.doseText($0, name: def.name) }) { id in
                        edit { t in
                            if let i = t.antibiotics.firstIndex(where: { $0.drug == def.id }) { t.antibiotics[i].doses.removeAll { $0.id == id } }
                        }
                    }
                }
            }
        }
    }

    /// Whether any of the pending antibiotics has a redose interval chosen.
    private func hasInterval(_ drugs: [String], _ d: CaseTimerData) -> Bool {
        for drug in drugs where (abxPick(drug, d).wrappedValue.minutes ?? 0) > 0 { return true }
        return false
    }

    /// "Last dose 08:10 · next 12:10", and "· given: 1 g" when the last dose was typed in the quick-add bar and says more than the
    /// dose computed above it.
    static func lastDoseText(last: TimedEntry, every: Double?, computed: String) -> String {
        var s = "Last dose " + ClockText.time(last.time)
        if let every { s += " · next " + ClockText.time(last.time.addingTimeInterval(every * 60)) }
        if let given = IntraopAntibiotic.givenNote(last: last, computed: computed) { s += " · " + given }
        return s
    }

    /// A dose in the log: "08:10  Vancomycin 1 g" (the dose when it was typed).
    static func doseText(_ e: TimedEntry, name: String) -> String {
        var s = ClockText.time(e.time) + "  " + name
        if let g = e.given?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty { s += " " + g }
        return s
    }

    private func startAntibiotics(_ pending: [String], changes: [String: Double]) {
        Haptics.light()
        let start = abxStart.resolved(now: Date())
        let ebl = r.fluids["ebl"] ?? 0
        let picks = abxPicks
        edit { t in
            for drug in pending where t.course(drug) == nil {
                let pick = picks[drug] ?? RecurrencePick()
                t.antibiotics.append(AntibioticCourse(drug: drug, doses: [TimedEntry(time: start, ebl: ebl)],
                                                      everyMinutes: CaseTimerRecurrence.storedInterval(pick)))
            }
            for (drug, m) in changes {
                if let i = t.antibiotics.firstIndex(where: { $0.drug == drug }) { t.antibiotics[i].everyMinutes = m }
            }
        }
        abxPending = []
        abxPicks = [:]
        abxStart = StartTimePick()
    }

    // MARK: Lab checks

    private func labPick(_ def: LabCheckDef) -> Binding<RecurrencePick> {
        Binding(get: {
            if let p = labPicks[def.id] { return p }
            if let c = t.checks[def.id] { return RecurrencePick(running: c.every, chips: CaseTimerRecurrence.labChips(def)) }
            return RecurrencePick()
        }, set: { labPicks[def.id] = $0 })
    }

    @ViewBuilder private func labsSection(_ d: CaseTimerData) -> some View {
        let starts = d.checks.filter { t.checks[$0.id] == nil && labPicks[$0.id]?.minutes != nil }
        let changes = d.checks.filter { def in
            guard let c = t.checks[def.id], let p = labPicks[def.id] else { return false }
            return (p.minutes ?? 0) != c.every
        }
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Lab checks", info: d.checks.compactMap(\.note).joined(separator: " "))
            ToolCard {
                ForEach(Array(d.checks.enumerated()), id: \.element.id) { i, def in
                    if i > 0 { Hairline() }
                    labRow(def, d).id("lab." + def.id)
                }
                let update = starts.isEmpty && !changes.isEmpty
                Hairline()
                if !update { StartTimeRow(start: $labStart) }
                Button {
                    startLabs(starts, changes: changes)
                } label: {
                    Text(update ? "Update timer" : "Start timer").frame(maxWidth: .infinity)
                }
                .buttonStyle(TimerStartButtonStyle(active: !(starts.isEmpty && changes.isEmpty)))
                .disabled(starts.isEmpty && changes.isEmpty)
            }
        }
        .id("labs.card")
    }

    @ViewBuilder private func labRow(_ def: LabCheckDef, _ d: CaseTimerData) -> some View {
        let c = t.checks[def.id]
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(def.name).font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
                if let s = def.strength, !s.isEmpty {
                    EvidenceTag(text: s, url: d.sources(def.sources ?? []).first.flatMap { URL(string: $0.url) }, onOpen: openLink)
                }
                Spacer(minLength: 4)
                if let c {
                    if let last = c.last {
                        let alert = last.value.flatMap { CaseTimerEngine.glucoseAlert($0, def: def) }
                        Text("Last \(ClockText.time(last.time))" + (last.value.map { " · \(CaseTimerEngine.fmt($0)) \(def.unit ?? "")" } ?? ""))
                            .font(PS.sys(size: 13, weight: alert == nil ? .regular : .semibold)).foregroundStyle(alert == nil ? PS.fg2 : PS.red)
                    } else {
                        Text("Started \(ClockText.time(c.started))").font(PS.sys(size: 13)).foregroundStyle(PS.fg2)
                    }
                }
            }
            RecurrenceRow(label: "Check every", chips: CaseTimerRecurrence.labChips(def), pick: labPick(def),
                          preferred: def.options.first?.minutes ?? 60, maxMinutes: CaseTimerRecurrence.labMax)
            if let c {
                if let last = c.last, let v = last.value, let alert = CaseTimerEngine.glucoseAlert(v, def: def) {
                    Text(alert).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.red)
                }
                if def.id == "glucose" {
                    HStack(spacing: 12) {
                        UnitField(prompt: "Value", unit: def.unit ?? "", value: $glucoseValue)
                        Button("Log") {
                            guard let v = glucoseValue else { return }
                            edit { $0.checks[def.id]?.done.append(TimedEntry(time: Date(), value: v)) }
                            glucoseValue = nil
                        }
                        .buttonStyle(CapsuleButtonStyle.patientAction()).disabled(glucoseValue == nil)
                    }
                } else {
                    Button("Sent now") { edit { $0.checks[def.id]?.done.append(TimedEntry(time: Date())) } }
                        .buttonStyle(CapsuleButtonStyle(prominent: false))
                }
            }
        }
    }

    private func startLabs(_ starts: [LabCheckDef], changes: [LabCheckDef]) {
        Haptics.light()
        let start = labStart.resolved(now: Date())
        let picks = labPicks
        edit { t in
            for def in starts { if let m = picks[def.id]?.minutes { t.checks[def.id] = LabCheckCourse(every: m, started: start) } }
            for def in changes {
                if let m = picks[def.id]?.minutes { t.checks[def.id]?.every = m } else { t.checks[def.id] = nil }
            }
        }
        labPicks = [:]
        labStart = StartTimePick()
    }

    // MARK: Heparin & ACT

    @ViewBuilder private func heparinSection(_ d: CaseTimerData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Heparin & ACT", info: d.heparinRules.clottingTest + " " + d.heparinRules.deviceNote)
            ToolCard {
                purposeChips(d)
                if let h = t.heparin, let p = d.purpose(h.purpose) {
                    weightLine(d)
                    heparinHead(h, p, d)
                }
            }
            if let h = t.heparin, let p = d.purpose(h.purpose) {
                ToolCard { logCard(h, p, d) }.id("heparin.log")
                if !h.doses.isEmpty {
                    ToolCard { protamineBlock(h, p, d) }.id("heparin.protamine")
                }
            }
        }
        .id("heparin.card")
    }

    @ViewBuilder private func purposeChips(_ d: CaseTimerData) -> some View {
        let h = t.heparin
        let locked = h.map { !$0.isBlank } ?? false
        let list = purposeList(d)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Heparin purpose").font(PS.sys(size: 12.5, weight: .medium)).foregroundStyle(PS.fg3)
                Spacer()
                if let h {
                    Menu {
                        Button(role: .destructive) { edit { $0.heparin = nil }; resetHeparinEntry() } label: {
                            Label(h.isBlank ? "Clear the purpose" : "Clear heparin, ACTs and protamine", systemImage: "xmark")
                        }
                    } label: { Image(systemName: "ellipsis.circle").font(PS.sys(size: 17)).foregroundStyle(PS.fg3) }
                    .accessibilityLabel("Heparin options")
                }
            }
            TimerChipRow(chips: list.map { TimerChipRow.Chip(id: $0.id, label: $0.name, on: $0.id == h?.purpose) }) { id in
                if locked {
                    // Doses are logged against this purpose: clear the log (⋯) to change it.
                    return
                }
                if ChipToggle.tap(h?.purpose, id) == nil {
                    edit { $0.heparin = nil }
                    resetHeparinEntry()
                } else {
                    pickPurpose(id, d)
                }
            }
            .opacity(locked ? 0.75 : 1)
            if locked {
                Text("Purpose fixed once a dose or ACT is logged; ⋯ clears the log.").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
            }
        }
    }

    /// The offered purposes, and a saved case's retired one (EVAR / TEVAR) so it still shows selected.
    private func purposeList(_ d: CaseTimerData) -> [HeparinPurpose] {
        var list = d.offeredPurposes
        if let h = t.heparin, !list.contains(where: { $0.id == h.purpose }), let p = d.purpose(h.purpose) { list.append(p) }
        return list
    }

    private func pickPurpose(_ id: String, _ d: CaseTimerData) {
        guard let p = d.purpose(id) else { return }
        edit { $0.heparin = HeparinCourse(purpose: id, goal: CaseTimerEngine.presetGoal(p), actEvery: p.actEvery.first ?? 30) }
        draft = nil; rowEdit = nil
        goalEditing = false
        actPick = nil
    }

    private func resetHeparinEntry() {
        draft = nil; rowEdit = nil; protamineMg = nil; goalEditing = false; goalEntry = nil; actPick = nil
    }

    /// The weight, from My Patient or typed here (and kept in My Patient): no dose shows without it.
    @ViewBuilder private func weightLine(_ d: CaseTimerData) -> some View {
        if let w = r.weightKg, w > 0 {
            let issues = CaseTimerEngine.weightIssues(r, data: d)
            if !issues.isEmpty { DoseIssueList(issues: issues) }
            else {
                Text("\(CaseTimerEngine.fmt(w.rounded())) kg, from My Patient").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
            }
        } else {
            let issues = (weightEntry.map { w in d.weightFlag.map { lim in w < lim[0] || w > lim[1] } ?? false } ?? false)
                ? [DoseIssue(level: .confirm, text: "Outside \(CaseTimerEngine.fmt(d.weightFlag?[0] ?? 35))–\(CaseTimerEngine.fmt(d.weightFlag?[1] ?? 200)) kg: check it.")] : []
            Text("Weight first, for the dose").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            HStack(spacing: 12) {
                UnitField(prompt: "Weight", unit: "kg", value: $weightEntry)
                CheckedLogButton(title: "Use", issues: weightEntry == nil ? [DoseIssue(level: .block, text: "")] : issues, armed: $weightArmed) {
                    if let w = weightEntry {
                        withAnimation(.snappy) { patient.update(discrete: true) { $0.weightKg = w } }
                    }
                }
            }
            DoseIssueList(issues: issues)
        }
    }

    /// The lines above the log, unchanged: the ACT goal (editable) and the dose range.
    @ViewBuilder private func heparinHead(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        let src = d.sources(p.sources ?? []).first.flatMap { URL(string: $0.url) }
        Hairline()
        goalRow(h, p, d, src: src)
        doseRow(p, src: src)
    }

    /// "ACT goal ≥ 480 s", editable; the device and where the number comes from under it.
    @ViewBuilder private func goalRow(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData, src: URL?) -> some View {
        let device = d.heparinRules.actDevice ?? "i-STAT"
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("ACT goal").font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
                InfoButton(open: $goalInfoOpen, label: "About ACT goals")
            }
            .frame(width: 88, alignment: .leading)
            Text(h.goal.map { "≥ \(Int($0)) s" } ?? "No preset goal")
                .font(h.goal == nil ? PS.sys(size: 15, weight: .semibold) : PS.serif(size: 22)).foregroundStyle(PS.fg)
            if h.goal != nil, !h.userGoal, let s = p.strength, !s.isEmpty { EvidenceTag(text: s, url: src, onOpen: openLink) }
            if h.userGoal { EvidenceTag(text: "You") }
            Spacer(minLength: 4)
            Button(goalEditing ? "Close" : (h.goal == nil ? "Set" : "Change")) {
                withAnimation(.snappy) { goalEditing.toggle(); goalEntry = goalEditing ? h.goal : nil; goalArmed = false }
            }
            .font(PS.sys(size: 13.5, weight: .semibold))
            .tint(PS.action)
        }
        if goalInfoOpen { InfoCaptionText(text: CaseTimerEngine.actGoalInfo(device: device), font: PS.sys(size: 12)) }
        Text(CaseTimerEngine.goalCaption(h, p, device: device)).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
        if goalEditing {
            let issues = CaseTimerEngine.goalIssues(goalEntry, purpose: p, rules: d.heparinRules)
            HStack(spacing: 10) {
                UnitField(prompt: "Goal", unit: "s", value: Binding(get: { goalEntry }, set: { goalEntry = $0; goalArmed = false }), width: 84)
                CheckedLogButton(title: "Set goal", issues: goalEntry == nil ? [DoseIssue(level: .block, text: "")] : issues, armed: $goalArmed) {
                    let g = goalEntry
                    edit { if let c = $0.heparin { $0.heparin = CaseTimerEngine.settingGoal(c, to: g, purpose: p) } }
                    goalEditing = false
                }
                if h.userGoal {
                    Button(p.goal.map { "Back to \(Int($0)) s" } ?? "Remove") {
                        edit { if let c = $0.heparin { $0.heparin = CaseTimerEngine.settingGoal(c, to: nil, purpose: p) } }
                        goalEditing = false
                    }
                    .font(PS.sys(size: 13, weight: .semibold))
                }
            }
            DoseIssueList(issues: issues.filter { !$0.text.isEmpty })
        }
    }

    /// "300–400 U/kg ≈ 24,000–32,000 U".
    @ViewBuilder private func doseRow(_ p: HeparinPurpose, src: URL?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Heparin").font(PS.sys(size: 13)).foregroundStyle(PS.fg3).frame(width: 88, alignment: .leading)
            if let text = CaseTimerEngine.flatDose(p, weightKg: r.weightKg) {
                Text(text).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(p.doseLow == nil ? "Enter the dose you give" : "Weight needed for the dose")
                    .font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg2)
            }
            Spacer(minLength: 4)
        }
        if let n = p.note { Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
    }

    // MARK: The log

    @ViewBuilder private func logCard(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        Text("Heparin & ACT log").font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
        timelineRows(h, p, d)
        addButtons(h, p)
        if let dr = draft { entryRow(dr, h, p, d) }
        logSummary(h, p)
        Hairline()
        reminderRow(h, p, d).id("heparin.timer")
        if p.isBypass && !h.reversed && !h.doses.isEmpty { bypassRow(h) }
    }

    /// One row per event, oldest first; a tap opens the row in place. The order is read from the log, so an edit re-sorts
    /// it when it is saved, not while typing.
    @ViewBuilder private func timelineRows(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        let events = h.timeline
        if events.isEmpty {
            Text("Nothing logged yet. Add a baseline ACT, a heparin dose or an ACT.")
                .font(PS.sys(size: 13)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { Hairline() }
                    if let ed = rowEdit, ed.id == e.id { editRow(ed, h, p, d) } else { timelineRow(e) }
                }
            }
            Text("Tap a row to change its time or value.").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
        }
    }

    /// "09:41  ACT   545 s  at goal" (a below-goal ACT is red: a clinical alert; no label without a goal or for a baseline).
    private func timelineRow(_ e: HeparinEvent) -> some View {
        let now = Date()
        let below = e.goalMet == false
        let goal: String? = e.kind == .baseline ? nil : HeparinTimeline.goalText(e.goalMet)
        return Button { openEdit(e) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(HeparinTimeline.timeText(e.time, now: now))
                    .font(PS.mono(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg2).lineLimit(1).fixedSize()
                Text(HeparinTimeline.label(e.kind)).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg).lineLimit(1)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(HeparinTimeline.valueText(e)).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(below ? PS.red : PS.fg)
                    if let goal {
                        Text(goal).font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(below ? PS.red : PS.green)
                    }
                }
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(HeparinTimeline.rowText(e, now: now))
        .accessibilityHint("Change its time or value, or delete it")
    }

    private func openEdit(_ e: HeparinEvent) {
        Haptics.light()
        withAnimation(.snappy) {
            draft = nil
            rowEdit = HeparinRowEdit(id: e.id, kind: e.kind, value: e.value, shown: e.time)
        }
    }

    // MARK: Adding an entry

    private func addButtons(_ h: HeparinCourse, _ p: HeparinPurpose) -> some View {
        FlowLayout(spacing: 16) {
            addButton("+ ACT", .act, h, p)
            addButton("+ Heparin dose", .heparin, h, p)
            addButton("+ Baseline ACT", .baseline, h, p)
        }
    }

    private func addButton(_ title: String, _ kind: HeparinEvent.Kind, _ h: HeparinCourse, _ p: HeparinPurpose) -> some View {
        let open = draft?.kind == kind
        return Button {
            Haptics.light()
            withAnimation(.snappy) { openDraft(kind, h, p) }
        } label: {
            Text(title)
                .font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.action)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(open ? PS.action.opacity(0.14) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add " + String(title.dropFirst(2)))
        .accessibilityValue(open ? "Open" : "")
    }

    private func openDraft(_ kind: HeparinEvent.Kind, _ h: HeparinCourse, _ p: HeparinPurpose) {
        if draft?.kind == kind { draft = nil; return }
        rowEdit = nil
        var dr = HeparinDraft(kind: kind)
        // The first bolus opens with the suggested dose, as the field always did.
        if kind == .heparin, h.doses.isEmpty { dr.value = CaseTimerEngine.suggestedBolus(p, weightKg: r.weightKg) }
        draft = dr
    }

    private func entryTitle(_ kind: HeparinEvent.Kind, _ h: HeparinCourse) -> String {
        switch kind {
        case .heparin: return "Heparin dose"
        case .baseline: return "Baseline ACT"
        case .act: return h.offersBaseline ? "Baseline ACT" : "ACT"
        case .protamine: return "Protamine"
        }
    }

    private func unitPrompt(_ kind: HeparinEvent.Kind) -> (prompt: String, unit: String) {
        switch kind {
        case .heparin: return ("Units", "U")
        case .protamine: return ("mg", "mg")
        case .baseline, .act: return ("Seconds", "s")
        }
    }

    private func entryRow(_ dr: HeparinDraft, _ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        let time = HeparinTimeline.resolved(picked: dr.picked, now: Date())
        let issues = CaseTimerEngine.entryIssues(kind: dr.kind, value: dr.value, course: h, purpose: p, record: r, data: d)
            + (HeparinTimeline.timeIssue(time).map { [$0] } ?? [])
        let unit = unitPrompt(dr.kind)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(entryTitle(dr.kind, h)).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                Spacer(minLength: 4)
                UnitField(prompt: unit.prompt, unit: unit.unit,
                          value: Binding(get: { draft?.value }, set: { draft?.value = $0; draft?.armed = false }), width: 100)
            }
            EntryTimeRow(base: nil, picked: Binding(get: { draft?.picked }, set: { draft?.picked = $0; draft?.armed = false }))
            DoseIssueList(issues: issues.filter { !$0.text.isEmpty })
            HStack(spacing: 10) {
                Spacer(minLength: 4)
                Button("Cancel") { withAnimation(.snappy) { draft = nil } }.buttonStyle(CapsuleButtonStyle(prominent: false))
                CheckedLogButton(title: "Log", issues: issues, armed: Binding(get: { draft?.armed ?? false }, set: { draft?.armed = $0 })) {
                    logDraft()
                }
            }
        }
        .padding(12)
        .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// One Undo step: the entry and, for the first dose of the case, the reminder's switch.
    private func logDraft() {
        guard let dr = draft, let v = dr.value else { return }
        let now = Date()
        guard let time = HeparinTimeline.resolved(picked: dr.picked, now: now) else { return }
        edit { t in
            switch dr.kind {
            case .heparin: t.heparin?.logDose(units: v, at: time, now: now)
            case .act, .baseline: t.heparin?.logACT(seconds: v, at: time, kind: dr.kind)
            case .protamine: t.heparin?.logProtamine(mg: v, at: time)
            }
        }
        draft = nil
    }

    // MARK: Changing a row

    private func editRow(_ ed: HeparinRowEdit, _ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        let time = HeparinTimeline.resolvedEdit(picked: ed.picked, original: ed.shown, now: Date())
        let issues = CaseTimerEngine.entryIssues(kind: ed.kind, value: ed.value, course: h.removing(ed.id), purpose: p, record: r, data: d)
            + (HeparinTimeline.timeIssue(time).map { [$0] } ?? [])
        let unit = unitPrompt(ed.kind)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(HeparinTimeline.label(ed.kind)).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                Spacer(minLength: 4)
                UnitField(prompt: unit.prompt, unit: unit.unit,
                          value: Binding(get: { rowEdit?.value }, set: { rowEdit?.value = $0; rowEdit?.armed = false }), width: 100)
            }
            EntryTimeRow(base: ed.shown, picked: Binding(get: { rowEdit?.picked }, set: { rowEdit?.picked = $0; rowEdit?.armed = false }))
            DoseIssueList(issues: issues.filter { !$0.text.isEmpty })
            HStack(spacing: 10) {
                Button { deleteTapped(ed) } label: {
                    Label(ed.deleteArmed ? "Confirm delete" : "Delete", systemImage: "trash")
                }
                .buttonStyle(CapsuleButtonStyle(prominent: ed.deleteArmed, color: PS.red))
                Spacer(minLength: 4)
                Button("Cancel") { withAnimation(.snappy) { rowEdit = nil } }.buttonStyle(CapsuleButtonStyle(prominent: false))
                CheckedLogButton(title: "Save", issues: issues, armed: Binding(get: { rowEdit?.armed ?? false }, set: { rowEdit?.armed = $0 })) {
                    saveEdit(ed, time: time)
                }
            }
        }
        .padding(12)
        .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// One Undo step: the changed time and value; the list re-sorts now.
    private func saveEdit(_ ed: HeparinRowEdit, time: Date?) {
        guard let time, let cur = rowEdit else { return }
        edit { $0.heparin?.updateEntry(ed.id, time: time, value: cur.value) }
        rowEdit = nil
    }

    /// Delete asks a second tap ("Confirm delete"), then is one Undo step.
    private func deleteTapped(_ ed: HeparinRowEdit) {
        Haptics.light()
        guard ed.deleteArmed else { withAnimation(.snappy) { rowEdit?.deleteArmed = true }; return }
        edit { $0.heparin?.removeEntry(ed.id) }
        rowEdit = nil
    }

    /// The facts under the log that the old blocks carried: the heparin-resistance note beside a below-goal ACT, and the initial
    /// and total heparin (the protamine suggestion rests on the initial dose).
    @ViewBuilder private func logSummary(_ h: HeparinCourse, _ p: HeparinPurpose) -> some View {
        let status = CaseTimerEngine.status(h, record: r)
        if status.goalMet == false, let pk = status.initialPerKg, let lo = p.doseLow, pk >= lo,
           let text = refs.caseTimers?.heparinRules.resistance {
            Text(text).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
        }
        if let initial = status.initialUnits, h.doses.count > 1 {
            Text("Initial \(CaseTimerEngine.grouped(initial)) U · total \(CaseTimerEngine.grouped(status.totalUnits)) U in \(h.doses.count) doses")
                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2)
        }
    }

    // MARK: The ACT reminder

    /// "ACT reminder": one switch for the series, its interval chips, and the next due time. Turning it off keeps the log and
    /// stops the running list, the notification and the lock-screen activity; turning it on counts from now or the last ACT.
    @ViewBuilder private func reminderRow(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        let chips = CaseTimerRecurrence.actChips(p)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACT reminder").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                    if h.actRunning { nextDueLine(d) }
                }
                Spacer(minLength: 6)
                Toggle("ACT reminder", isOn: reminderSwitch).labelsHidden().tint(PS.action)
            }
            RecurrenceRow(label: "Recurring every", chips: chips, pick: intervalPick(h, chips), preferred: p.actEvery.first ?? 30,
                          maxMinutes: CaseTimerRecurrence.actMax)
            Text("Each ACT you log restarts the countdown; a heparin dose does not.")
                .font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reminderSwitch: Binding<Bool> {
        Binding(get: { t.heparin?.actRunning ?? false }, set: { on in
            Haptics.light()
            edit { $0.heparin?.setReminder(on, now: Date()) }
            actPick = nil
        })
    }

    /// The interval is always one of the chips or Other (a second tap on the chosen one keeps it: the reminder needs an interval).
    private func intervalPick(_ h: HeparinCourse, _ chips: [Double]) -> Binding<RecurrencePick> {
        Binding(get: { actPick ?? RecurrencePick(running: h.actEvery, chips: chips) }, set: { new in
            guard let m = new.minutes else { return }
            actPick = new
            if m != h.actEvery { edit { $0.heparin?.actEvery = m } }
        })
    }

    /// "Next ACT due 09:20", red once overdue (as the running list); "Snoozed to 09:25" after a snooze. The time is the one the
    /// running list shows: both read `CaseTimerEngine.reminders`.
    private func nextDueLine(_ d: CaseTimerData) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let rem = CaseTimerEngine.reminders(t, record: r, data: d).first { $0.kind == .act }
            let overdue = CaseReminder.state(due: rem?.due, at: ctx.date) == .overdue
            Text(Self.nextDueText(rem))
                .font(PS.sys(size: 13, weight: overdue ? .semibold : .medium))
                .foregroundStyle(overdue ? PS.red : PS.fg2)
        }
    }

    static func nextDueText(_ rem: CaseReminder?) -> String {
        guard let due = rem?.due else { return "Next ACT due" }
        return (rem?.snoozed == true ? "Snoozed to " : "Next ACT due ") + ClockText.time(due)
    }


    @ViewBuilder private func bypassRow(_ h: HeparinCourse) -> some View {
        HStack(spacing: 10) {
            if h.onBypass {
                Text("On bypass since \(ClockText.time(h.bypassOn!))").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.accent2)
                Spacer()
                Button("Bypass off") { edit { $0.heparin?.bypassOff = Date() } }.buttonStyle(CapsuleButtonStyle(prominent: false))
            } else {
                if let off = h.bypassOff { Text("Off bypass \(ClockText.time(off))").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2) }
                Spacer()
                Button("Bypass on") { edit { $0.heparin?.bypassOn = Date(); $0.heparin?.bypassOff = nil } }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
            }
        }
    }

    /// Method (c): the suggestion from the initial dose with its cap, and the current ACT beside it.
    @ViewBuilder private func protamineBlock(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        let pr = d.protamine
        let issues = protamineMg.map { CaseTimerEngine.protamineIssues(mg: $0, course: h, purpose: p, rules: pr) } ?? []
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Protamine").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            InfoButton(open: $protamineInfoOpen, label: "About the protamine suggestion")
            Spacer()
            EvidenceTag(text: "G", url: d.sources(p.isBypass ? ["eacts2024"] : ["protamine"]).first.flatMap { URL(string: $0.url) }, onOpen: openLink)
        }
        if protamineInfoOpen { InfoCaptionText(text: CaseTimerEngine.protamineInfo(bypass: p.isBypass, rules: pr), font: PS.sys(size: 12)) }
        if let s = CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: pr) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let lo = s.lowMg, let hi = s.highMg {
                    Text(lo == hi ? "\(CaseTimerEngine.fmt(hi)) mg" : "\(CaseTimerEngine.fmt(lo))–\(CaseTimerEngine.fmt(hi)) mg")
                        .font(PS.serif(size: 22)).foregroundStyle(PS.fg)
                } else {
                    Text("Up to \(CaseTimerEngine.fmt(s.capMg)) mg").font(PS.serif(size: 22)).foregroundStyle(PS.fg)
                }
                Spacer(minLength: 4)
                if let act = s.lastACT, let at = s.lastACTTime {
                    Text("ACT \(Int(act)) s · \(ClockText.time(at))").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
                }
            }
            Text(protamineBasis(s, pr: pr, bypass: p.isBypass))
                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            if s.givenMg > 0 {
                Text("Given \(CaseTimerEngine.fmt(s.givenMg)) mg · \(CaseTimerEngine.fmt(s.remainingMg)) mg left under the cap")
                    .font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(s.remainingMg > 0 ? PS.fg : PS.accent)
            }
            Text(p.isBypass ? pr.ratioNote + " " + pr.suction : pr.noBypass)
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 12) {
            Text("Dose").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer(minLength: 4)
            UnitField(prompt: "mg", unit: "mg", value: Binding(get: { protamineMg }, set: { protamineMg = $0; protamineArmed = false }), width: 84)
            CheckedLogButton(title: "Started", issues: protamineMg == nil ? [DoseIssue(level: .block, text: "")] : issues, armed: $protamineArmed) {
                if let mg = protamineMg { edit { $0.heparin?.logProtamine(mg: mg, at: Date()) } }
                protamineMg = nil
            }
        }
        DoseIssueList(issues: issues)
        Text(pr.ceilingNote + " " + pr.rate).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
    }

    private func protamineBasis(_ s: CaseTimerEngine.ProtamineSuggestion, pr: ProtamineRules, bypass: Bool) -> String {
        let initial = CaseTimerEngine.grouped(s.basisUnits)
        let total = s.totalUnits > s.basisUnits ? " (not the \(CaseTimerEngine.grouped(s.totalUnits)) U total)" : ""
        if bypass {
            return "\(CaseTimerEngine.fmt(pr.ratioLow))–\(CaseTimerEngine.fmt(pr.ratioHigh)) mg per 100 U of the initial \(initial) U\(total) · cap \(CaseTimerEngine.fmt(s.capMg)) mg"
        }
        return "1 mg per 100 U of the initial \(initial) U\(total) is the cap"
    }

    // MARK: Footer

    private func footer(_ d: CaseTimerData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            EvidenceDisclosure {
                Text("Reminders and suggestions, not orders: each is a check against the cited source. Times run from what you log here; delete a mistaken entry and everything after it is recalculated. Reminders reach the lock screen while the app is closed, for every open case.")
                    .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                ForEach(d.protamine.facts, id: \.self) { f in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text((f.first ?? "") + ": " + (f.count > 1 ? f[1] : "")).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                        if f.count > 2, !f[2].isEmpty {
                            EvidenceTag(text: f[2], url: f.count > 3 ? d.sources([f[3]]).first.flatMap { URL(string: $0.url) } : nil, onOpen: openLink)
                        }
                    }
                }
                EvidenceLinks(sources: d.sources, onOpen: openLink)
            }
        }
    }
}

/// Logged entries, newest first, each removable (a mistaken tap).
struct DoseHistory: View {
    var entries: [TimedEntry]
    var text: (TimedEntry) -> String
    var onDelete: (UUID) -> Void
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entries.sorted { $0.time > $1.time }) { e in
                    HStack {
                        Text(text(e)).font(PS.mono(size: 12, weight: .medium)).foregroundStyle(PS.fg2)
                        Spacer()
                        Button(role: .destructive) { onDelete(e.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).tint(PS.fg3)
                            .accessibilityLabel("Remove " + text(e))
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Log (\(entries.count))").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
        }
        .tint(PS.fg3)
    }
}
