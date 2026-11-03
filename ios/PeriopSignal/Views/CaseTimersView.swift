import SwiftUI
import UserNotifications

// MARK: - Case timers: antibiotic redose, heparin and ACT, protamine, ABG and glucose checks
//
// Opened from My Patient's ⋯ menu (Case Timers) or from the strip at the top of the Intraoperative tab, which shows
// what is due next. Each card asks one question first ("Which antibiotic?", "What is the heparin for?") and then shows
// only what that answer needs. The log is the case record's `timers` (CaseTimers), so Undo, the case chips and the
// archive treat it like any other entry; CaseTimerNotifier turns the reminders of every open case into notifications
// and the lock-screen countdown. Content: reference.json "caseTimers", a draft until signed off in the review doc.

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
                // Screenshot runs: -ps.timers.seed 1 starts made-up timers on the current case; -ps.timers.open 1 opens them.
                if LaunchSeed.bool("ps.timers.seed"), patient.record.timers.isEmpty { CaseTimersDemo.seed(patient) }
                if LaunchSeed.bool("ps.timers.open") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { CaseTimersUI.shared.open = true }
                }
                #endif
            }
    }
}

#if DEBUG
enum CaseTimersDemo {
    /// A bypass case: cefazolin 3 h 40 min ago, 30,000 U of heparin with ACTs, glucose and ABG checks running.
    @MainActor static func seed(_ patient: PatientStore, now: Date = Date()) {
        patient.update(discrete: true) { r in
            if r.weightKg == nil { r.weightKg = 82 }
            if r.ageYears == nil { r.ageYears = 66 }
            var t = CaseTimers()
            t.antibiotic = AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: now.addingTimeInterval(-220 * 60), ebl: 0)])
            var h = HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30)
            h.acts = [TimedEntry(time: now.addingTimeInterval(-95 * 60), value: 128, baseline: true)]
            h.doses = [TimedEntry(time: now.addingTimeInterval(-80 * 60), value: 25000)]
            h.acts.append(TimedEntry(time: now.addingTimeInterval(-76 * 60), value: 512))
            h.acts.append(TimedEntry(time: now.addingTimeInterval(-44 * 60), value: 468))
            h.doses.append(TimedEntry(time: now.addingTimeInterval(-42 * 60), value: 5000))
            h.acts.append(TimedEntry(time: now.addingTimeInterval(-38 * 60), value: 545))
            h.bypassOn = now.addingTimeInterval(-70 * 60)
            t.heparin = h
            t.checks["glucose"] = LabCheckCourse(every: 30, started: now.addingTimeInterval(-70 * 60),
                                                 done: [TimedEntry(time: now.addingTimeInterval(-26 * 60), value: 196)])
            t.checks["abg"] = LabCheckCourse(every: 30, started: now.addingTimeInterval(-70 * 60),
                                             done: [TimedEntry(time: now.addingTimeInterval(-31 * 60))])
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

// MARK: - The timers

struct CaseTimersView: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    @Environment(\.dismiss) private var dismiss

    @State private var webLink: WebLink?
    @State private var antibioticPick: String?
    @State private var antibioticStart = Date()
    @State private var purposePick: String?
    @State private var heparinUnits: Double?
    @State private var heparinArmed = false
    @State private var actValue: Double?
    @State private var actBaseline = false
    @State private var protamineMg: Double?
    @State private var protamineArmed = false
    @State private var glucoseValue: Double?
    @State private var weightEntry: Double?
    @State private var weightArmed = false
    @State private var goalEntry: Double?
    @State private var goalArmed = false

    private var r: PatientRecord { patient.record }
    private var t: CaseTimers { patient.record.timers }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let d = refs.caseTimers {
                    TimelineView(.periodic(from: .now, by: 15)) { ctx in
                        VStack(alignment: .leading, spacing: 18) {
                            DraftBanner(section: "caseTimers")
                            nextCard(d, now: ctx.date)
                            if CaseTimerEngine.isChild(r) {
                                ToolCard(tint: PS.red) {
                                    Text("Adult defaults only").font(PS.serif(size: 20)).foregroundStyle(PS.fg)
                                    Text("The antibiotic and heparin doses here are for adults; they are locked for a child. The ABG and glucose checks still work.")
                                        .font(PS.sys(size: 14)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                                antibioticCard(d, now: ctx.date)
                                heparinCard(d, now: ctx.date)
                            }
                            checksCard(d, now: ctx.date)
                            footer(d)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 30)
                    }
                } else {
                    ContentUnavailableView("Not available offline yet", systemImage: "wifi.slash", description: Text("The timers arrive with the next refresh."))
                }
            }
            .background(FeedBackground())
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Case Timers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { Keyboard.dismiss() }
                }
            }
        }
        .fullScreenCover(item: $webLink) { link in SafariView(url: link.url).ignoresSafeArea() }
    }

    private func edit(_ change: (inout CaseTimers) -> Void) {
        withAnimation(.snappy) { patient.update(discrete: true) { change(&$0.timers) } }
        CaseTimerNotifier.shared.requestPermissionIfNeeded()
    }

    private func openLink(_ url: URL) { webLink = WebLink(url: url) }

    // MARK: Next

    @ViewBuilder private func nextCard(_ d: CaseTimerData, now: Date) -> some View {
        let items = CaseTimerEngine.reminders(t, record: r, data: d)
        if !items.isEmpty {
            ToolCard(tint: items.contains { $0.state(at: now) != .waiting } ? PS.accent : PS.accent2) {
                Eyebrow(text: "Next")
                ForEach(items) { rem in
                    HStack(alignment: .center, spacing: 10) {
                        CaseReminderLine(reminder: rem, now: now)
                        if let action = quickAction(rem) {
                            Button(action.title) { action.run() }
                                .buttonStyle(CapsuleButtonStyle(prominent: rem.state(at: now) != .waiting))
                        }
                    }
                }
            }
            .onceTip("ps.tips.timers.next", "The next redose, ACT and lab check land here and on the lock screen. Tap Given or Sent when it's done.")
        }
    }

    private struct QuickAction { var title: String; var run: () -> Void }

    private func quickAction(_ rem: CaseReminder) -> QuickAction? {
        switch rem.kind {
        case .antibiotic, .bloodLoss:
            return QuickAction(title: "Given") { logAntibioticDose(Date()) }
        case .abg:
            return QuickAction(title: "Sent") { edit { $0.checks["abg"]?.done.append(TimedEntry(time: Date())) } }
        case .act, .protamineACT, .glucose:
            return nil
        }
    }

    // MARK: Antibiotic

    @ViewBuilder private func antibioticCard(_ d: CaseTimerData, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Antibiotic", info: d.antibioticRules.fromStart + " " + d.antibioticRules.closure)
            ToolCard {
                if let course = t.antibiotic, let def = d.antibiotic(course.drug) {
                    antibioticRunning(course, def, d, now: now)
                } else {
                    antibioticPicker(d)
                }
            }
        }
    }

    @ViewBuilder private func antibioticPicker(_ d: CaseTimerData) -> some View {
        Text("Which antibiotic was given?").font(PS.serif(size: 18)).foregroundStyle(PS.fg)
        Menu {
            ForEach(d.antibiotics) { a in
                Button(a.name + (a.redoseHours.map { " · every \(CaseTimerEngine.fmt($0)) h" } ?? " · no redose")) { antibioticPick = a.id }
            }
        } label: {
            HStack {
                Text(antibioticPick.flatMap { d.antibiotic($0)?.name } ?? "Choose").font(PS.sys(size: 15, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(PS.surface2, in: Capsule())
            .foregroundStyle(PS.fg)
        }
        if let id = antibioticPick, let def = d.antibiotic(id) {
            antibioticFacts(def, d)
            DatePicker("Dose started", selection: $antibioticStart, in: ...Date().addingTimeInterval(60), displayedComponents: [.hourAndMinute])
                .font(PS.sys(size: 14.5)).tint(PS.accent)
            Button {
                let start = antibioticStart
                edit { $0.antibiotic = AntibioticCourse(drug: id, doses: [TimedEntry(time: start, ebl: r.fluids["ebl"] ?? 0)]) }
                antibioticPick = nil
            } label: { Text(def.redoseHours == nil ? "Log the dose" : "Start the redose timer") }
            .buttonStyle(CapsuleButtonStyle(prominent: true))
        }
    }

    @ViewBuilder private func antibioticFacts(_ def: AntibioticDef, _ d: CaseTimerData) -> some View {
        let dose = CaseTimerEngine.antibioticDose(def, record: r)
        HStack(alignment: .firstTextBaseline) {
            Text(dose.text).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer(minLength: 6)
            Text(def.redoseHours.map { "Redose every \(CaseTimerEngine.fmt($0)) h" } ?? "No routine redose")
                .font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg2)
            EvidenceTag(text: "G", url: d.sources(["bratzler"]).first.flatMap { URL(string: $0.url) }, onOpen: openLink)
        }
        if let needs = dose.needs { Text(needs).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent) }
        if let n = def.note { Text(n).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true) }
        if def.redoseHours == nil { Text(d.antibioticRules.noRedose).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
        if let c = def.cardiac, t.heparin.flatMap({ d.purpose($0.purpose) })?.isCardiac == true || r.procedure.lowercased().contains("bypass") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(c).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                EvidenceTag(text: "G?", url: d.sources(["sts2007"]).first.flatMap { URL(string: $0.url) }, onOpen: openLink)
            }
        }
        if CaseTimerEngine.renalCaution(r) {
            Label(d.antibioticRules.renal, systemImage: "exclamationmark.triangle")
                .font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.accent).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func antibioticRunning(_ course: AntibioticCourse, _ def: AntibioticDef, _ d: CaseTimerData, now: Date) -> some View {
        HStack {
            Text(def.name).font(PS.serif(size: 20)).foregroundStyle(PS.fg)
            Spacer()
            Menu {
                Button(role: .destructive) { edit { $0.antibiotic = nil } } label: { Label("Stop the antibiotic timer", systemImage: "xmark") }
            } label: { Image(systemName: "ellipsis.circle").font(PS.sys(size: 18)).foregroundStyle(PS.fg3) }
            .accessibilityLabel("Antibiotic options")
        }
        antibioticFacts(def, d)
        if let last = course.last {
            Text("Last dose \(ClockText.time(last.time))" + (def.redoseHours.map { " · next \(ClockText.time(last.time.addingTimeInterval($0 * 3600)))" } ?? ""))
                .font(PS.sys(size: 14)).foregroundStyle(PS.fg2)
        }
        HStack(spacing: 10) {
            Button("Redose given now") { logAntibioticDose(Date()) }.buttonStyle(CapsuleButtonStyle(prominent: false))
        }
        if course.doses.count > 1 {
            DoseHistory(entries: course.doses, text: { "\(ClockText.time($0.time))" }) { id in
                edit { $0.antibiotic?.doses.removeAll { $0.id == id } }
            }
        }
    }

    private func logAntibioticDose(_ time: Date) {
        let ebl = r.fluids["ebl"] ?? 0
        edit { $0.antibiotic?.doses.append(TimedEntry(time: time, ebl: ebl)) }
    }

    // MARK: Heparin

    @ViewBuilder private func heparinCard(_ d: CaseTimerData, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Heparin & ACT", info: d.heparinRules.clottingTest + " " + d.heparinRules.deviceNote)
            ToolCard {
                weightLine(d)
                if let h = t.heparin, let p = d.purpose(h.purpose) {
                    heparinRunning(h, p, d, now: now)
                } else {
                    heparinStart(d)
                }
            }
        }
    }

    /// The weight, from My Patient or typed here (and kept in My Patient): no U/kg number shows without it.
    @ViewBuilder private func weightLine(_ d: CaseTimerData) -> some View {
        if let w = r.weightKg, w > 0 {
            let issues = CaseTimerEngine.weightIssues(r, data: d)
            HStack {
                Text("\(CaseTimerEngine.fmt(w.rounded())) kg").font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                Text("From My Patient").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
                Spacer()
            }
            DoseIssueList(issues: issues)
        } else {
            Text("Weight first").font(PS.serif(size: 18)).foregroundStyle(PS.fg)
            let issues = (weightEntry.map { w in d.weightFlag.map { lim in w < lim[0] || w > lim[1] } ?? false } ?? false)
                ? [DoseIssue(level: .confirm, text: "Outside \(CaseTimerEngine.fmt(d.weightFlag?[0] ?? 35))–\(CaseTimerEngine.fmt(d.weightFlag?[1] ?? 200)) kg: check it.")] : []
            HStack(spacing: 12) {
                UnitField(prompt: "Weight", unit: "kg", value: $weightEntry)
                CheckedLogButton(title: "Use", issues: weightEntry == nil ? [DoseIssue(level: .block, text: "")] : issues, armed: $weightArmed) {
                    if let w = weightEntry { withAnimation(.snappy) { patient.update(discrete: true) { $0.weightKg = w } } }
                }
            }
            DoseIssueList(issues: issues)
        }
    }

    @ViewBuilder private func heparinStart(_ d: CaseTimerData) -> some View {
        Text("What is the heparin for?").font(PS.serif(size: 18)).foregroundStyle(PS.fg)
        ChoiceChips(options: d.heparinPurposes.map { (id: $0.id, label: $0.name) }, selected: purposePick) { id in
            purposePick = id
            if let p = d.purpose(id) { heparinUnits = CaseTimerEngine.suggestedBolus(p, weightKg: r.weightKg) }
        }
        .onceTip("ps.tips.timers.purpose", "The purpose sets the usual dose, the ACT goal and how often the ACT reminder comes.")
        if let id = purposePick, let p = d.purpose(id) {
            purposeFacts(p, d)
            Button {
                let goal = p.goal
                edit { $0.heparin = HeparinCourse(purpose: id, goal: goal, actEvery: p.actEvery.first ?? 30) }
            } label: { Text("Use " + p.name.lowercased()) }
            .buttonStyle(CapsuleButtonStyle(prominent: true))
        }
    }

    @ViewBuilder private func purposeFacts(_ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        let src = d.sources(p.sources ?? []).first.flatMap { URL(string: $0.url) }
        if let range = CaseTimerEngine.usualRange(p, weightKg: r.weightKg) {
            HStack(alignment: .firstTextBaseline) {
                Text("Usual dose").font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
                Spacer(minLength: 6)
                Text(range).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg).multilineTextAlignment(.trailing)
            }
        }
        HStack(alignment: .firstTextBaseline) {
            Text("ACT goal").font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
            Spacer(minLength: 6)
            Text(p.goal == nil ? "None preset" : (p.goalText ?? ">\(Int(p.goal!)) s"))
                .font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg).multilineTextAlignment(.trailing)
            if let s = p.strength, !s.isEmpty { EvidenceTag(text: s, url: src, onOpen: openLink) }
        }
        if let n = p.note { Text(n).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true) }
    }

    @ViewBuilder private func heparinRunning(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData, now: Date) -> some View {
        let status = CaseTimerEngine.status(h, record: r)
        HStack {
            Text(p.name).font(PS.serif(size: 20)).foregroundStyle(PS.fg)
            Spacer()
            Menu {
                if h.doses.isEmpty {
                    Button { edit { $0.heparin = nil } } label: { Label("Change the purpose", systemImage: "arrow.uturn.backward") }
                }
                Button(role: .destructive) { edit { $0.heparin = nil } } label: { Label("Clear heparin and ACTs", systemImage: "xmark") }
            } label: { Image(systemName: "ellipsis.circle").font(PS.sys(size: 18)).foregroundStyle(PS.fg3) }
            .accessibilityLabel("Heparin options")
        }
        if h.doses.isEmpty { purposeFacts(p, d) }
        goalRow(h, p, d)

        // Status
        if let initial = status.initialUnits {
            VStack(alignment: .leading, spacing: 4) {
                Text("Initial bolus \(CaseTimerEngine.grouped(initial)) U" + (status.initialPerKg.map { " (\(CaseTimerEngine.fmt($0.rounded())) U/kg)" } ?? ""))
                    .font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                if h.doses.count > 1 {
                    Text("Total \(CaseTimerEngine.grouped(status.totalUnits)) U in \(h.doses.count) doses").font(PS.sys(size: 13)).foregroundStyle(PS.fg2)
                }
                if let act = status.lastACT, let at = status.lastACTTime {
                    let tone: Color = status.goalMet == false ? PS.red : (status.goalMet == true ? PS.green : PS.fg)
                    Text("Last ACT \(Int(act)) s at \(ClockText.time(at))" + (status.goalMet == false ? " · below goal" : (status.goalMet == true ? " · at goal" : "")))
                        .font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(tone)
                    if status.goalMet == false, let pk = status.initialPerKg, let lo = p.doseLow, pk >= lo {
                        Text(d.heparinRules.resistance).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        if p.isBypass && !h.reversed {
            HStack(spacing: 10) {
                if h.onBypass {
                    Text("On bypass since \(ClockText.time(h.bypassOn!))").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.accent2)
                    Spacer()
                    Button("Bypass off") { edit { $0.heparin?.bypassOff = Date() } }.buttonStyle(CapsuleButtonStyle(prominent: false))
                } else {
                    if let off = h.bypassOff { Text("Off bypass \(ClockText.time(off))").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2) }
                    Spacer()
                    Button("Bypass on") { edit { $0.heparin?.bypassOn = Date(); $0.heparin?.bypassOff = nil } }
                        .buttonStyle(CapsuleButtonStyle(prominent: false)).disabled(h.doses.isEmpty)
                }
            }
        }

        if !h.reversed {
            Hairline()
            heparinDoseEntry(h, p, d)
        }
        Hairline()
        actEntry(h)
        if !h.doses.isEmpty {
            Hairline()
            protamineEntry(h, p, d)
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
    }

    @ViewBuilder private func goalRow(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        if p.isBypass, let alt = p.goalDevice, let main = p.goal {
            Toggle(isOn: Binding(get: { h.deviceAlt }, set: { on in edit { $0.heparin?.deviceAlt = on; $0.heparin?.goal = on ? alt : main } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Maximally activated or microcuvette ACT").font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg)
                    Text("Goal >\(Int(h.goal ?? main)) s").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2)
                }
            }
            .tint(PS.accent)
        } else if p.goal == nil {
            // No preset goal: the user may set one, labelled practice only (ACTION-1 for open vascular surgery).
            if let g = h.goal, h.userGoal {
                HStack {
                    Text("Your ACT goal >\(Int(g)) s").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                    if let label = p.userGoalText {
                        EvidenceTag(text: "P")
                        Text(label).font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                    }
                    Spacer()
                    Button("Remove") { edit { $0.heparin?.goal = nil; $0.heparin?.userGoal = false } }.font(PS.sys(size: 13, weight: .semibold))
                }
            } else {
                let issues = CaseTimerEngine.goalIssues(goalEntry, purpose: p, rules: d.heparinRules)
                HStack(spacing: 10) {
                    UnitField(prompt: "Optional", unit: "s goal", value: $goalEntry, width: 84)
                    CheckedLogButton(title: "Set goal", issues: goalEntry == nil ? [DoseIssue(level: .block, text: "")] : issues, armed: $goalArmed) {
                        let g = goalEntry
                        edit { $0.heparin?.goal = g; $0.heparin?.userGoal = true }
                        goalEntry = nil
                    }
                }
                if let label = p.userGoalText { Text("If you set one: " + label + ".").font(PS.sys(size: 12)).foregroundStyle(PS.fg3) }
            }
        }
        if p.actEvery.count > 1 {
            HStack {
                Text("ACT every").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2)
                ChoiceChips(options: p.actEvery.map { (id: $0, label: "\(CaseTimerEngine.fmt($0)) min") }, selected: h.actEvery) { v in edit { $0.heparin?.actEvery = v } }
            }
        }
    }

    @ViewBuilder private func heparinDoseEntry(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        let first = h.doses.isEmpty
        let issues = heparinUnits.map { CaseTimerEngine.heparinIssues(units: $0, course: h, purpose: p, record: r, data: d) }
            ?? CaseTimerEngine.weightIssues(r, data: d).filter { $0.level == .block }
        Text(first ? "Heparin bolus" : "Another dose").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
        HStack(spacing: 12) {
            UnitField(prompt: "Units", unit: "U", value: Binding(get: { heparinUnits }, set: { heparinUnits = $0; heparinArmed = false }), width: 110)
            CheckedLogButton(title: "Given", issues: heparinUnits == nil ? issues + [DoseIssue(level: .block, text: "")] : issues, armed: $heparinArmed) {
                if let u = heparinUnits { edit { $0.heparin?.doses.append(TimedEntry(time: Date(), value: u)) } }
                heparinUnits = nil
            }
        }
        DoseIssueList(issues: issues.filter { !$0.text.isEmpty })
    }

    @ViewBuilder private func actEntry(_ h: HeparinCourse) -> some View {
        let canBaseline = h.doses.isEmpty
        Text(canBaseline ? "Baseline ACT (optional)" : "ACT").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
        HStack(spacing: 12) {
            UnitField(prompt: "Seconds", unit: "s", value: $actValue)
            Button("Log") {
                guard let v = actValue else { return }
                edit { $0.heparin?.acts.append(TimedEntry(time: Date(), value: v, baseline: canBaseline ? true : nil)) }
                actValue = nil
            }
            .buttonStyle(CapsuleButtonStyle(prominent: true))
            .disabled(actValue == nil || (actValue ?? 0) < 30)
        }
    }

    @ViewBuilder private func protamineEntry(_ h: HeparinCourse, _ p: HeparinPurpose, _ d: CaseTimerData) -> some View {
        let pr = d.protamine
        let issues = protamineMg.map { CaseTimerEngine.protamineIssues(mg: $0, course: h, purpose: p, rules: pr) } ?? []
        HStack {
            Text("Protamine").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer()
            EvidenceTag(text: "G", url: d.sources(["sts2018"]).first.flatMap { URL(string: $0.url) }, onOpen: openLink)
        }
        if let s = CaseTimerEngine.protamineSuggestion(h, purpose: p, rules: pr) {
            if let lo = s.lowMg, let hi = s.highMg {
                Text("\(CaseTimerEngine.fmt(lo))–\(CaseTimerEngine.fmt(hi)) mg")
                    .font(PS.serif(size: 22)).foregroundStyle(PS.fg)
                Text("\(CaseTimerEngine.fmt(pr.ratioLow))–\(CaseTimerEngine.fmt(pr.ratioHigh)) mg per 100 U of the \(CaseTimerEngine.grouped(s.basisUnits)) U initial bolus · total heparin \(CaseTimerEngine.grouped(s.totalUnits)) U")
                    .font(PS.sys(size: 13)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                Text(pr.ratioNote + " " + pr.suction).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(pr.noBypass).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                if let max = s.labelMaxMg {
                    Text("At most \(CaseTimerEngine.fmt(max)) mg: 1 mg per 100 U of the \(CaseTimerEngine.grouped(s.totalUnits)) U given")
                        .font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                }
            }
            if s.givenMg > 0 { Text("Given so far \(CaseTimerEngine.fmt(s.givenMg)) mg").font(PS.sys(size: 13)).foregroundStyle(PS.fg2) }
        }
        HStack(spacing: 12) {
            UnitField(prompt: "mg", unit: "mg", value: Binding(get: { protamineMg }, set: { protamineMg = $0; protamineArmed = false }))
            CheckedLogButton(title: "Started", issues: protamineMg == nil ? [DoseIssue(level: .block, text: "")] : issues, armed: $protamineArmed) {
                if let mg = protamineMg { edit { $0.heparin?.protamine.append(TimedEntry(time: Date(), value: mg)) } }
                protamineMg = nil
            }
        }
        DoseIssueList(issues: issues)
        Text(pr.ceilingNote + " " + pr.rate).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Checks

    @ViewBuilder private func checksCard(_ d: CaseTimerData, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Lab checks", info: d.checks.compactMap(\.note).joined(separator: " "))
            ToolCard {
                ForEach(Array(d.checks.enumerated()), id: \.element.id) { i, def in
                    if i > 0 { Hairline() }
                    checkRow(def, d, now: now)
                }
            }
        }
    }

    @ViewBuilder private func checkRow(_ def: LabCheckDef, _ d: CaseTimerData, now: Date) -> some View {
        if let c = t.checks[def.id] {
            HStack {
                Text(def.name).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                Text("every \(CaseTimerEngine.fmt(c.every)) min").font(PS.sys(size: 13)).foregroundStyle(PS.fg2)
                if let s = def.strength, !s.isEmpty {
                    EvidenceTag(text: s, url: d.sources(def.sources ?? []).first.flatMap { URL(string: $0.url) }, onOpen: openLink)
                }
                Spacer()
                Button("Stop") { edit { $0.checks[def.id] = nil } }.font(PS.sys(size: 13, weight: .semibold)).tint(PS.fg3)
            }
            if let last = c.last {
                let alert = last.value.flatMap { CaseTimerEngine.glucoseAlert($0, def: def) }
                Text("Last \(ClockText.time(last.time))" + (last.value.map { " · \(CaseTimerEngine.fmt($0)) \(def.unit ?? "")" } ?? ""))
                    .font(PS.sys(size: 13.5, weight: alert == nil ? .regular : .semibold)).foregroundStyle(alert == nil ? PS.fg2 : PS.red)
                if let alert { Text(alert).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.red) }
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
        } else {
            Text(def.name).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
            ChoiceChips(options: def.options.map { (id: $0.minutes, label: "\($0.label) · \(CaseTimerEngine.fmt($0.minutes)) min") }, selected: nil) { minutes in
                edit { $0.checks[def.id] = LabCheckCourse(every: minutes, started: Date()) }
            }
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
