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

@MainActor
@Observable
final class CaseTimersUI {
    static let shared = CaseTimersUI()
    var open = false
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
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(c.on ? PS.accent.opacity(0.15) : PS.surface2, in: Capsule())
                        .overlay(Capsule().stroke(c.on ? PS.accent.opacity(0.7) : PS.line2, lineWidth: 1))
                        .foregroundStyle(c.on ? PS.accent : PS.fg)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(c.a11y ?? c.label)
                .accessibilityAddTraits(c.on ? .isSelected : [])
                .accessibilityHint(c.on ? "Tap again to clear" : "")
            }
        }
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
            } + [TimerChipRow.Chip(id: "other", label: pick.other ? "Other · " + CaseTimerEngine.interval(pick.minutes ?? preferred) : "Other",
                                   on: pick.other, a11y: "Other interval")]) { id in
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

/// "Start time" on the 24-hour clock.
private struct StartTimeRow: View {
    @Binding var start: Date

    var body: some View {
        DatePicker("Start time", selection: $start, displayedComponents: [.hourAndMinute])
            .font(PS.sys(size: 14.5, weight: .medium))
            .foregroundStyle(PS.fg)
            .tint(PS.accent)
            .environment(\.locale, Locale(identifier: "en_GB"))
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
                    .font(PS.sys(size: 18, weight: .semibold)).foregroundStyle(PS.accent)
                Text(title).font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
                Spacer(minLength: 6)
                if let detail { Text(detail).font(PS.sys(size: 12.5, weight: .medium)).foregroundStyle(PS.fg3).lineLimit(1) }
                Image(systemName: open ? "chevron.up" : "chevron.down").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(open ? PS.accent.opacity(0.45) : PS.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(open ? "Open" : "Closed")
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
    @State private var scrollTarget: String?

    // Antibiotic
    @State private var abxPending: [String] = []
    @State private var abxPicks: [String: RecurrencePick] = [:]
    @State private var abxStart = Date()
    // Labs
    @State private var labPicks: [String: RecurrencePick] = [:]
    @State private var labStart = Date()
    @State private var glucoseValue: Double?
    // Heparin
    @State private var heparinUnits: Double?
    @State private var heparinArmed = false
    @State private var actValue: Double?
    @State private var protamineMg: Double?
    @State private var protamineArmed = false
    @State private var weightEntry: Double?
    @State private var weightArmed = false
    @State private var goalEditing = false
    @State private var goalEntry: Double?
    @State private var goalArmed = false
    @State private var actPick: RecurrencePick?
    @State private var actStart = Date()

    private var r: PatientRecord { patient.record }
    private var t: CaseTimers { patient.record.timers }

    var body: some View {
        Group {
            if inSheet { NavigationStack { page } } else { page }
        }
        .fullScreenCover(item: $webLink) { link in SafariView(url: link.url).ignoresSafeArea() }
        .onAppear(perform: setUp)
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
        .toolbar {
            if inSheet {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
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
        if let d = refs.caseTimers {
            abxPending = LaunchSeed.list("ps.timers.pick").filter { d.antibiotic($0) != nil && t.course($0) == nil }
            for id in abxPending { if let def = d.antibiotic(id) { abxPicks[id] = RecurrencePick(minutes: CaseTimerRecurrence.antibioticDefault(def)) } }
            for item in LaunchSeed.list("ps.timers.labs") {
                let parts = item.split(separator: ":").map(String.init)
                guard let def = d.check(parts[0]) else { continue }
                labPicks[def.id] = RecurrencePick(minutes: parts.count > 1 ? Double(parts[1]) : CaseTimerRecurrence.labChips(def).first)
            }
            let other = LaunchSeed.string("ps.timers.other")
            if other == "antibiotic", let id = abxPending.first, let def = d.antibiotic(id) {
                abxPicks[id] = RecurrencePick(minutes: CaseTimerRecurrence.antibioticPreferred(def, rules: d.antibioticRules) + 30, other: true)
            } else if other.hasPrefix("labs:"), let def = d.check(String(other.dropFirst(5))) {
                labPicks[def.id] = RecurrencePick(minutes: 45, other: true)
            } else if other == "act" {
                actPick = RecurrencePick(minutes: 45, other: true)
            }
            let purpose = LaunchSeed.string("ps.timers.purpose")
            if !purpose.isEmpty, t.heparin == nil, d.purpose(purpose) != nil { pickPurpose(purpose, d) }
        }
        let scroll = LaunchSeed.string("ps.timers.scroll")
        if !scroll.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { scrollTarget = scroll } }
        #endif
        openSections = open
    }

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
                case .antibiotic: abxStart = Date()
                case .labs: labStart = Date()
                case .heparin: actStart = Date()
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
            HStack(spacing: 8) {
                Text(dueLine(rem, state: state))
                    .font(PS.sys(size: 12.5, weight: state == .overdue ? .semibold : .regular))
                    .foregroundStyle(state == .overdue ? PS.red : PS.fg2)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Button(doneTitle(rem)) { done(rem, d) }
                    .buttonStyle(CapsuleButtonStyle(prominent: state != .waiting))
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

    private func dueLine(_ rem: CaseReminder, state: CaseReminder.State) -> String {
        guard let due = rem.due else { return rem.detail }
        let at = (rem.snoozed ? "Snoozed to " : "Due at ") + ClockText.time(due)
        return state == .overdue ? "Overdue · " + at.lowercasedFirst : at
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
        case .act, .protamineACT: show(.heparin, at: "heparin.act")
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
                if !pending.isEmpty || !changes.isEmpty {
                    Hairline()
                    if !pending.isEmpty { StartTimeRow(start: $abxStart) }
                    Button {
                        startAntibiotics(pending, changes: changes)
                    } label: {
                        Text(pending.isEmpty ? "Update timer" : "Start timer").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                    .accessibilityHint(pending.isEmpty ? "Saves the new redose intervals" : "Logs the dose at the start time and starts the redose timer")
                }
            }
        }
        .id("antibiotic.card")
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
                HStack(spacing: 10) {
                    Text("Last dose \(ClockText.time(last.time))" + (every.map { " · next \(ClockText.time(last.time.addingTimeInterval($0 * 60)))" } ?? ""))
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
                    DoseHistory(entries: course.doses, text: { "\(ClockText.time($0.time))  \(def.name)" }) { id in
                        edit { t in
                            if let i = t.antibiotics.firstIndex(where: { $0.drug == def.id }) { t.antibiotics[i].doses.removeAll { $0.id == id } }
                        }
                    }
                }
            }
        }
    }

    private func startAntibiotics(_ pending: [String], changes: [String: Double]) {
        Haptics.light()
        let start = CaseTimerRecurrence.resolveStart(abxStart, now: Date())
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
        abxStart = Date()
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
                if !starts.isEmpty || !changes.isEmpty {
                    Hairline()
                    if !starts.isEmpty { StartTimeRow(start: $labStart) }
                    Button {
                        startLabs(starts, changes: changes)
                    } label: {
                        Text(starts.isEmpty ? "Update timer" : "Start timer").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                }
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
                        .buttonStyle(CapsuleButtonStyle(prominent: true)).disabled(glucoseValue == nil)
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
        let start = CaseTimerRecurrence.resolveStart(labStart, now: Date())
        let picks = labPicks
        edit { t in
            for def in starts { if let m = picks[def.id]?.minutes { t.checks[def.id] = LabCheckCourse(every: m, started: start) } }
            for def in changes {
                if let m = picks[def.id]?.minutes { t.checks[def.id]?.every = m } else { t.checks[def.id] = nil }
            }
        }
        labPicks = [:]
        labStart = Date()
    }

    // MARK: Heparin & ACT

    @ViewBuilder private func heparinSection(_ d: CaseTimerData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Heparin & ACT", info: d.heparinRules.clottingTest + " " + d.heparinRules.deviceNote)
            ToolCard {
                purposeChips(d)
                if let h = t.heparin, let p = d.purpose(h.purpose) {
                    weightLine(d)
                    heparinBody(h, p, d)
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
        heparinUnits = CaseTimerEngine.suggestedBolus(p, weightKg: r.weightKg)
        heparinArmed = false
        goalEditing = false
        actPick = nil
    }

    private func resetHeparinEntry() {
        heparinUnits = nil; actValue = nil; protamineMg = nil; goalEditing = false; goalEntry = nil; actPick = nil
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
                        if let h = t.heparin, h.doses.isEmpty, let p = refs.caseTimers?.purpose(h.purpose) {
                            heparinUnits = CaseTimerEngine.suggestedBolus(p, weightKg: w)
                        }
                    }
                }
            }
            DoseIssueList(issues: issues)
        }
    }

    @ViewBuilder private func heparinBody(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        let src = d.sources(p.sources ?? []).first.flatMap { URL(string: $0.url) }
        Hairline()
        goalRow(h, p, d, src: src)
        doseRow(p, src: src)
        if !h.reversed {
            Hairline()
            heparinDoseEntry(h, p, d)
        }
        Hairline()
        actEntry(h).id("heparin.act")
        if p.isBypass && !h.reversed && !h.doses.isEmpty { bypassRow(h) }
        if !h.doses.isEmpty {
            Hairline()
            protamineBlock(h, p, d).id("heparin.protamine")
        }
        if h.doses.count + h.acts.count + h.protamine.count > 0 {
            DoseHistory(entries: (h.doses + h.acts + h.protamine).sorted { $0.time > $1.time }, text: { e in
                if h.doses.contains(where: { $0.id == e.id }) { return "\(ClockText.time(e.time))  Heparin \(CaseTimerEngine.grouped(e.value ?? 0)) U" }
                if h.protamine.contains(where: { $0.id == e.id }) { return "\(ClockText.time(e.time))  Protamine \(CaseTimerEngine.fmt(e.value ?? 0)) mg" }
                return "\(ClockText.time(e.time))  ACT \(Int(e.value ?? 0)) s" + (e.baseline == true ? " (baseline)" : "")
            }) { id in
                edit {
                    $0.heparin?.doses.removeAll { $0.id == id }
                    $0.heparin?.acts.removeAll { $0.id == id }
                    $0.heparin?.protamine.removeAll { $0.id == id }
                }
            }
        }
        if !h.reversed {
            Hairline()
            actTimer(h, p, d).id("heparin.timer")
        }
    }

    /// "ACT goal ≥ 480 s", editable; the device and where the number comes from under it.
    @ViewBuilder private func goalRow(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData, src: URL?) -> some View {
        let device = d.heparinRules.actDevice ?? "i-STAT"
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("ACT goal").font(PS.sys(size: 13)).foregroundStyle(PS.fg3).frame(width: 74, alignment: .leading)
            Text(h.goal.map { "≥ \(Int($0)) s" } ?? "No preset goal")
                .font(h.goal == nil ? PS.sys(size: 15, weight: .semibold) : PS.serif(size: 22)).foregroundStyle(PS.fg)
            if h.goal != nil, !h.userGoal, let s = p.strength, !s.isEmpty { EvidenceTag(text: s, url: src, onOpen: openLink) }
            if h.userGoal { EvidenceTag(text: "You") }
            Spacer(minLength: 4)
            Button(goalEditing ? "Close" : (h.goal == nil ? "Set" : "Change")) {
                withAnimation(.snappy) { goalEditing.toggle(); goalEntry = goalEditing ? h.goal : nil; goalArmed = false }
            }
            .font(PS.sys(size: 13.5, weight: .semibold))
        }
        Text(goalCaption(h, p, device: device)).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
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

    private func goalCaption(_ h: HeparinCourse, _ p: HeparinPurpose, device: String) -> String {
        if h.userGoal { return "Your goal, \(device). " + (p.goal.map { "Preset ≥ \(Int($0)) s." } ?? (p.userGoalText.map { "Usual: \($0)." } ?? "")) }
        if h.deviceAlt { return "Set in 1.9 for a maximally activated or microcuvette ACT." }
        if h.goal == nil { return device + (p.userGoalText.map { ". If you set one: \($0)." } ?? ". Set one if you use one.") }
        return device + (p.goalText.map { " · \($0)" } ?? "")
    }

    /// "300–400 U/kg ≈ 24,000–32,000 U".
    @ViewBuilder private func doseRow(_ p: HeparinPurpose, src: URL?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Heparin").font(PS.sys(size: 13)).foregroundStyle(PS.fg3).frame(width: 74, alignment: .leading)
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

    @ViewBuilder private func heparinDoseEntry(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        let first = h.doses.isEmpty
        let issues = heparinUnits.map { CaseTimerEngine.heparinIssues(units: $0, course: h, purpose: p, record: r, data: d) }
            ?? CaseTimerEngine.weightIssues(r, data: d).filter { $0.level == .block }
        HStack(spacing: 12) {
            Text(first ? "Heparin bolus" : "Another dose").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer(minLength: 4)
            UnitField(prompt: "Units", unit: "U", value: Binding(get: { heparinUnits }, set: { heparinUnits = $0; heparinArmed = false }), width: 100)
            CheckedLogButton(title: "Given", issues: heparinUnits == nil ? issues + [DoseIssue(level: .block, text: "")] : issues, armed: $heparinArmed) {
                if let u = heparinUnits { edit { $0.heparin?.doses.append(TimedEntry(time: Date(), value: u)); $0.heparin?.actOff = false } }
                heparinUnits = nil
            }
        }
        DoseIssueList(issues: issues.filter { !$0.text.isEmpty })
    }

    @ViewBuilder private func actEntry(_ h: HeparinCourse) -> some View {
        let canBaseline = h.doses.isEmpty
        let status = CaseTimerEngine.status(h, record: r)
        HStack(spacing: 12) {
            Text(canBaseline ? "Baseline ACT" : "ACT").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer(minLength: 4)
            UnitField(prompt: "Seconds", unit: "s", value: $actValue, width: 100)
            Button("Log") {
                guard let v = actValue else { return }
                edit { $0.heparin?.acts.append(TimedEntry(time: Date(), value: v, baseline: canBaseline ? true : nil)) }
                actValue = nil
            }
            .buttonStyle(CapsuleButtonStyle(prominent: true))
            .disabled(actValue == nil || (actValue ?? 0) < 30)
        }
        if let act = status.lastACT, let at = status.lastACTTime {
            let tone: Color = status.goalMet == false ? PS.red : (status.goalMet == true ? PS.green : PS.fg)
            Text("Last ACT \(Int(act)) s at \(ClockText.time(at))" + (status.goalMet == false ? " · below goal" : (status.goalMet == true ? " · at goal" : "")))
                .font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(tone)
            if status.goalMet == false, let pk = status.initialPerKg, let p = refs.caseTimers?.purpose(h.purpose), let lo = p.doseLow, pk >= lo,
               let text = refs.caseTimers?.heparinRules.resistance {
                Text(text).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            }
        } else if let base = h.baselineACT, let v = base.value {
            Text("Baseline \(Int(v)) s at \(ClockText.time(base.time))").font(PS.sys(size: 13)).foregroundStyle(PS.fg2)
        }
        if let initial = status.initialUnits, h.doses.count > 1 {
            Text("Initial \(CaseTimerEngine.grouped(initial)) U · total \(CaseTimerEngine.grouped(status.totalUnits)) U in \(h.doses.count) doses")
                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2)
        }
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
        HStack(alignment: .firstTextBaseline) {
            Text("Protamine").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer()
            EvidenceTag(text: "G", url: d.sources(p.isBypass ? ["eacts2024"] : ["protamine"]).first.flatMap { URL(string: $0.url) }, onOpen: openLink)
        }
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
                if let mg = protamineMg { edit { $0.heparin?.protamine.append(TimedEntry(time: Date(), value: mg)) } }
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

    /// The ACT recheck timer: start time and "recurring every", then Start timer.
    @ViewBuilder private func actTimer(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        let chips = CaseTimerRecurrence.actChips(p)
        let running = !h.actOff && (h.actStart != nil || !h.doses.isEmpty)
        let pick = Binding<RecurrencePick>(get: {
            actPick ?? (running ? RecurrencePick(running: h.actEvery, chips: chips) : RecurrencePick(minutes: p.actEvery.first ?? 30))
        }, set: { actPick = $0 })
        let changed = running && actPick.map { ($0.minutes ?? 0) != h.actEvery } == true
        HStack(alignment: .firstTextBaseline) {
            Text("ACT timer").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer()
            if running, let due = CaseTimerEngine.actDue(h, rules: d.heparinRules) {
                Text("Next ACT \(ClockText.time(due))").font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg2)
            }
        }
        RecurrenceRow(label: "Recurring every", chips: chips, pick: pick, preferred: p.actEvery.first ?? 30,
                      maxMinutes: CaseTimerRecurrence.actMax)
        if !running { StartTimeRow(start: $actStart) }
        if !running || changed {
            Button {
                Haptics.light()
                let m = pick.wrappedValue.minutes
                let start = CaseTimerRecurrence.resolveStart(actStart, now: Date())
                edit { t in
                    guard t.heparin != nil else { return }
                    if running {
                        if let m { t.heparin?.actEvery = m } else { t.heparin?.actOff = true }
                    } else if let m {
                        t.heparin?.actEvery = m
                        t.heparin?.actStart = start
                        t.heparin?.actOff = false
                    }
                }
                actPick = nil
                actStart = Date()
            } label: {
                Text(running ? "Update timer" : "Start timer").frame(maxWidth: .infinity)
            }
            .buttonStyle(CapsuleButtonStyle(prominent: true))
            .disabled(!running && pick.wrappedValue.minutes == nil)
            .opacity(!running && pick.wrappedValue.minutes == nil ? 0.45 : 1)
        }
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
