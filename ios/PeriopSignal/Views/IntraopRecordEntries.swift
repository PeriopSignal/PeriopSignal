import SwiftUI

// MARK: - "+ Antibiotic" and "+ Heparin" on the Medications & Interventions page (1.12 follow-up, Ben, Nov 12)
//
// "Have option to just add antibiotic and heparin to intraop meds without using timer." Each opens in place under its group (the
// add grammar: a quiet "+ Name" link that opens the controls where it is), takes what it needs and records it. Nothing here
// starts a timer or a reminder unless the user turns the antibiotic's "Redose reminder" switch on. One Log is one Undo step.
//
// Antibiotic: the drug (a menu of Case Timers' list; Other to type a name the list does not have), the dose as typed (optional;
// never computed, converted or corrected; the dose Case Timers would suggest is only a hint beside it), the time (default now,
// 24-hour, never in the future) and the Redose reminder switch (off; disabled with the reason for a drug with no redose interval on
// file or one that is already timed). Heparin: the units (UnitField, and the checks Case Timers makes: a blocked dose is refused)
// and the time; it writes to the one Heparin & ACT log and leaves the ACT reminder as it is.

/// "Time" on the 24-hour clock: now (kept current) until the user picks one.
struct RecordTimeRow: View {
    @Binding var picked: Date?

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            DatePicker("Time", selection: Binding(get: { picked ?? ctx.date }, set: { picked = $0 }), displayedComponents: [.hourAndMinute])
                .font(PS.sys(size: 14.5, weight: .medium))
                .foregroundStyle(PS.fg)
                .tint(PS.action)
                .environment(\.locale, PatientDates.locale24)
        }
    }
}

private extension View {
    /// The quiet box an entry opens in, as Case Timers' timeline entries do.
    func recordBox() -> some View {
        padding(12)
            .background(PS.action.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PS.action.opacity(0.25), lineWidth: 1))
    }
}

// MARK: Antibiotic

struct AbxEntryRow: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    var onDone: () -> Void

    /// A Case Timers drug id, or `IntraopAntibiotic.otherName`.
    @State private var drug = LaunchSeed.string("ps.meds.abx.drug")
    @State private var typedName = ""
    @State private var dose = LaunchSeed.string("ps.meds.abx.dose")
    @State private var picked: Date?
    @State private var reminder = false

    private var other: Bool { drug == IntraopAntibiotic.otherName }
    private var record: PatientRecord { patient.record }

    /// The course the entry goes to: the listed drug, or the typed name (a listed brand is that drug).
    private var courseID: String {
        other ? IntraopAntibiotic.courseID(typedName, in: refs.caseTimers) : drug
    }

    private var existing: AntibioticCourse? { courseID.isEmpty ? nil : record.timers.course(courseID) }
    private var child: Bool { CaseTimerEngine.isChild(record) }

    /// What the switch can do: it needs the drug's sourced interval, and a course that is not already timed.
    private var canRemind: Bool {
        !courseID.isEmpty && IntraopAntibiotic.hasInterval(courseID, in: refs.caseTimers) && !child && existing?.reminders != true
    }

    private var timed: Bool { canRemind && reminder }

    private var time: Date? { HeparinTimeline.resolved(picked: picked, now: Date()) }
    private var canLog: Bool { !courseID.isEmpty && time != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            drugRow
            if other {
                TextField("Antibiotic name", text: $typedName)
                    .font(PS.sys(size: 14.5)).foregroundStyle(PS.fg)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(PS.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Antibiotic name")
            }
            doseRow
            RecordTimeRow(picked: $picked)
            reminderRow
            if time == nil { DoseIssueList(issues: [DoseIssue(level: .block, text: HeparinTimeline.futureText)]) }
            HStack(spacing: 10) {
                Spacer(minLength: 4)
                Button("Cancel") { withAnimation(.snappy) { onDone() } }.buttonStyle(CapsuleButtonStyle(prominent: false))
                Button("Log") { log() }
                    .buttonStyle(CapsuleButtonStyle(prominent: true, color: PS.action))
                    .disabled(!canLog).opacity(canLog ? 1 : 0.45)
            }
        }
        .recordBox()
    }

    private var drugName: String {
        if other { return IntraopAntibiotic.otherName }
        return refs.caseTimers?.antibiotic(drug)?.name ?? "Choose the antibiotic"
    }

    private var drugRow: some View {
        HStack(spacing: 10) {
            Text("Antibiotic").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer(minLength: 6)
            Menu {
                ForEach(refs.caseTimers?.antibiotics ?? []) { a in
                    Button(a.name + (a.redoseHours.map { " · every \(CaseTimerEngine.fmt($0)) h" } ?? " · no redose")) { choose(a.id) }
                }
                Divider()
                Button(IntraopAntibiotic.otherName + "…") { choose(IntraopAntibiotic.otherName) }
            } label: {
                HStack(spacing: 6) {
                    Text(drugName).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(drug.isEmpty ? PS.fg3 : PS.fg).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 10, weight: .bold)).foregroundStyle(PS.fg3)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(PS.surface2, in: Capsule())
            }
            .accessibilityLabel("Antibiotic, " + drugName)
        }
    }

    private func choose(_ id: String) {
        Haptics.light()
        drug = id
        if !canRemind { reminder = false }
    }

    private var doseRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Dose").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                Spacer(minLength: 6)
                TextField("Optional", text: $dose)
                    .font(PS.sys(size: 14.5)).foregroundStyle(PS.fg)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(PS.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(width: 170)
                    .accessibilityLabel("Dose, optional")
            }
            if let hint = doseHint {
                Text(hint).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The dose Case Timers would suggest for this patient, in its own wording; a hint beside the field, never put into it. None for a
    /// child (adult defaults only), a drug the list does not have, or while the weight a per-kg dose needs is missing.
    private var doseHint: String? {
        guard !child, let def = refs.caseTimers?.antibiotic(courseID) else { return nil }
        let s = CaseTimerEngine.antibioticDose(def, record: record)
        return s.needs == nil ? "Case Timers: " + s.text : nil
    }

    private var reminderRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Text(IntraopAntibiotic.reminderTitle).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                Spacer(minLength: 6)
                Toggle(IntraopAntibiotic.reminderTitle, isOn: Binding(get: { timed || existing?.reminders == true }, set: { reminder = $0 }))
                    .labelsHidden().tint(PS.action).disabled(!canRemind)
            }
            if let note = reminderNote {
                Text(note).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var reminderNote: String? {
        if existing?.reminders == true { return "Already timed in Case Timers" }
        if child { return IntraopAntibiotic.childNote }
        if courseID.isEmpty || !IntraopAntibiotic.hasInterval(courseID, in: refs.caseTimers) { return IntraopAntibiotic.noIntervalNote }
        if let h = refs.caseTimers?.antibiotic(courseID)?.redoseHours { return "Off: recorded only. On, every " + CaseTimerEngine.interval(h * 60) + " from this dose." }
        return nil
    }

    private func log() {
        guard canLog, let t = time else { return }
        let entry = IntraopAntibiotic.PageEntry(drug: courseID, given: dose, time: t, reminder: timed)
        let data = refs.caseTimers
        withAnimation(.snappy) { patient.update(discrete: true) { IntraopAntibiotic.record(entry, in: &$0, data: data) } }
        if timed { CaseTimerNotifier.shared.requestPermissionIfNeeded() }
        Haptics.success()
        onDone()
    }
}

// MARK: Heparin

struct HeparinEntryRow: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    var onDone: () -> Void

    @State private var units: Double? = Double(LaunchSeed.string("ps.meds.hep.units"))
    @State private var picked: Date?
    @State private var armed = false

    private var time: Date? { HeparinTimeline.resolved(picked: picked, now: Date()) }

    private var issues: [DoseIssue] {
        guard let d = refs.caseTimers else { return [DoseIssue(level: .block, text: "")] }
        return IntraopHeparin.pageIssues(units: units, time: time, record: patient.record, data: d)
    }

    var body: some View {
        let list = issues
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Heparin dose").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    UnitField(prompt: "Units", unit: "", value: Binding(get: { units }, set: { units = $0; armed = false }), width: 100)
                    Text("U").font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg2).fixedSize()
                }
            }
            RecordTimeRow(picked: Binding(get: { picked }, set: { picked = $0; armed = false }))
            DoseIssueList(issues: list.filter { !$0.text.isEmpty })
            HStack(spacing: 10) {
                Spacer(minLength: 4)
                Button("Cancel") { withAnimation(.snappy) { onDone() } }.buttonStyle(CapsuleButtonStyle(prominent: false))
                CheckedLogButton(title: "Log", issues: list, armed: $armed) { log() }
            }
        }
        .recordBox()
    }

    private func log() {
        guard let u = units, let t = time else { return }
        withAnimation(.snappy) { patient.update(discrete: true) { IntraopHeparin.record(units: u, at: t, in: &$0) } }
        Haptics.success()
        onDone()
    }
}
