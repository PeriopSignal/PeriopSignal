import SwiftUI

// MARK: - The reorganized Preprocedure tab (1.9, Ben's Wanted Changes)
//
// Ben: "minimize the amount of folders that have to be navigated". The tab's sections are Procedure; Demographics &
// History; Examination & Workup; Current Medications; Risk Scores & Checks; Preprocedure Summary. What used to be a card
// that opened an editor is now a box with its controls in place; a tap leaves the tab only for a long list (a system's
// problems, the labs, the airway examination, the lines diagram, one study). Every PatientEditor stays reachable for
// deep links, quick add and the screenshots. The logic is in Shared/PatientPreop.swift; the parts shared with the
// Assessment editor are in PatientAssessmentParts.swift.

/// The tab's sections, in order: each is a jump-bar target.
enum PreopSection: String, CaseIterable, Identifiable {
    case procedure, demographics, workup, medications, risk, summary
    var id: String { rawValue }
    var title: String {
        switch self {
        case .procedure: return "Procedure"
        case .demographics: return "Demographics & History"
        case .workup: return "Examination & Workup"
        case .medications: return "Current Medications"
        case .risk: return "Risk Scores & Checks"
        case .summary: return "Preprocedure Summary"
        }
    }
}

extension PatientEditor {
    /// The editor a PatientPreop key opens: "workup:ecg", "devices:support".
    init?(preopKey key: String) {
        if key.hasPrefix("workup:") { self = .workup(String(key.dropFirst(7))) }
        else if key.hasPrefix("devices:") { self = .devices(String(key.dropFirst(8))) }
        else { return nil }
    }
}

private extension PatientStore {
    func preopBinding<T>(_ kp: WritableKeyPath<PatientRecord, T>, discrete: Bool = false) -> Binding<T> {
        Binding(get: { self.record[keyPath: kp] }, set: { v in self.update(discrete: discrete) { $0[keyPath: kp] = v } })
    }
}

/// A section's title above its boxes. 1.11 (one heading per thing): a section whose first box would restate the title
/// draws that box without its caption, and the caption's ⓘ moves here (`info`), opening under the title.
struct PreopSectionTitle: View {
    var text: String
    var info: String? = nil
    @State private var open = LaunchSeed.bool("ps.evidence.open")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(text)
                    .font(PS.sys(size: 19, weight: .bold))
                    .foregroundStyle(PS.fg)
                    .accessibilityAddTraits(.isHeader)
                if let info, !info.isEmpty { InfoButton(open: $open, label: "About " + text, size: 13) }
            }
            if open, let info, !info.isEmpty { InfoCaptionText(text: info, font: PS.sys(size: 12.5)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }
}

// MARK: - Small pieces

/// A number cell for two columns: its label above, the value and unit in a field below. A tap anywhere in the cell starts
/// typing; the keyboard has a Done.
struct PreopNumberCell: View {
    var label: String
    var unit: String
    @Binding var value: Double?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                TextField("—", text: $text)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PS.fg)
                Text(unit).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { text = value.map { NumText.exact($0) } ?? "" }
        .onChange(of: text) { _, t in
            let v = PatientNumberField.parse(t)
            if v != value { value = v }
        }
        .onChange(of: value) { _, v in
            if PatientNumberField.parse(text) != v { text = v.map { NumText.exact($0) } ?? "" }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focused {
                    Spacer()
                    Button("Done") { focused = false; Keyboard.dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

/// "+ ECG": an item with nothing recorded, as a quiet chip. The caller makes it a button or a link.
struct PreopAddChip: View {
    var title: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "plus").font(PS.sys(size: 10.5, weight: .bold))
            Text(title).font(PS.sys(size: 13.5, weight: .medium)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(PS.fg2)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(PS.surface2, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(PS.line2, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Add " + title)
    }
}

/// An item with something recorded: its name small, what it holds under it. The caller makes it a button or a link.
struct PreopFilledRow: View {
    var title: String
    var summary: String
    var icon: String
    var alert = false
    var chevron = true
    /// A warning in red under the summary (the carotid and vertebral cautions).
    var caution: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(alert ? PS.red : PS.fg3).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(PS.sys(size: 11.5, weight: .semibold)).foregroundStyle(alert ? PS.red : PS.fg3)
                Text(summary).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg).lineLimit(3).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let caution {
                    Text(caution).font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.red).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if chevron { Image(systemName: "chevron.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3).padding(.top, 4) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// One item that opens an editor: filled, it is a row with its summary; empty, a "+" chip.
struct PreopLink: Identifiable {
    var id: String
    var title: String
    var icon: String
    var editor: PatientEditor
    var summary: String?
    var alert = false
    var caution: String? = nil
}

/// Items that open an editor, in their order: a filled one is a row with its summary, a run of empty ones is chips that
/// wrap.
struct PreopLinkList: View {
    var links: [PreopLink]

    /// The links in order, split where an item changes between filled and empty.
    private var runs: [(filled: Bool, links: [PreopLink])] {
        var out: [(filled: Bool, links: [PreopLink])] = []
        for l in links {
            let filled = l.summary != nil
            if let last = out.last, last.filled == filled { out[out.count - 1].links.append(l) } else { out.append((filled: filled, links: [l])) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                if run.filled {
                    ForEach(run.links) { l in
                        NavigationLink(value: l.editor) {
                            PreopFilledRow(title: l.title, summary: l.summary ?? "", icon: l.icon, alert: l.alert, caution: l.caution)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    WrapLayout(spacing: 8) {
                        ForEach(run.links) { l in
                            NavigationLink(value: l.editor) { PreopAddChip(title: l.title) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Demographics & History

/// The code-status chips (1.10): Full code, DNR, DNI, Limited, Not discussed, on one line where they fit. DNR and DNI can both be
/// on (a record keeps both as DNR/DNI, so a saved DNR/DNI shows both chips on); Full code, Limited and Not discussed are
/// exclusive, and a second tap on the one chosen clears it (CodeStatus.tapped).
struct CodeStatusChips: View {
    @Environment(PatientStore.self) private var patient

    var body: some View {
        let status = patient.record.codeStatus
        ChipSet(options: CodeStatus.chips.map { ChipChoice($0.id, $0.label, short: $0.short) }, style: .choice, tint: PS.accent,
                isOn: { status?.chipIDs.contains($0) ?? false },
                tap: { id in patient.update { $0.codeStatus = CodeStatus.tapped(id, from: $0.codeStatus) } })
    }
}

/// Age and sex, height and weight in two columns; the code status chips; a link to the preoperative vitals.
struct PreopDemographicsBox: View {
    @Environment(PatientStore.self) private var patient
    @State private var vitalsOpen = LaunchSeed.bool("ps.preop.vitals")

    var body: some View {
        let r = patient.record
        PatientGroup(title: "Demographics", note: PatientPreop.bodySizeNote(r)) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        PreopNumberCell(label: "Age", unit: PatientRecord.ageFieldUnit(r.ageYears), value: patient.preopBinding(\.ageYears))
                        sexCell
                    }
                    HStack(alignment: .top, spacing: 12) {
                        PreopNumberCell(label: "Height", unit: "cm", value: patient.preopBinding(\.heightCm))
                        PreopNumberCell(label: "Weight", unit: "kg", value: patient.preopBinding(\.weightKg))
                    }
                    if r.bmi != nil {
                        Text(PatientSummary.bodyLine(r)).font(PS.sys(size: 12.5, weight: .medium)).foregroundStyle(PS.fg3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                Hairline().padding(.leading, 14)
                codeStatus.padding(14)
                Hairline().padding(.leading, 14)
                vitals
            }
        }
    }

    // MARK: Sex

    private var sexCell: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sex").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
            HStack(spacing: 6) {
                sexPill("Male", .male)
                sexPill("Female", .female)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sexPill(_ label: String, _ value: PatientSex) -> some View {
        let on = patient.record.sex == value
        return Button {
            Haptics.light()
            patient.update(discrete: true) { $0.sex = on ? nil : value }
        } label: {
            Text(label)
                .font(PS.sys(size: 13.5, weight: on ? .semibold : .medium))
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(on ? PS.bg : PS.fg2)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(on ? PS.fg : PS.surface2, in: Capsule())
                .overlay(Capsule().stroke(on ? Color.clear : PS.line2, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Code status

    /// The code status chips, inline; the plan for the procedure and the POLST stay on their own page behind a small link.
    private var codeStatus: some View {
        let r = patient.record
        return VStack(alignment: .leading, spacing: 8) {
            Text("Code status").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
            CodeStatusChips()
            // For every status, so the POLST can be recorded or cleared from the tab too.
            let link = PatientPreop.codeStatusLink(r)
            NavigationLink(value: PatientEditor.workup("codestatus")) {
                HStack(spacing: 6) {
                    Text(link.text).foregroundStyle(link.alert ? PS.red : PS.fg2)
                    Image(systemName: "chevron.right").font(PS.sys(size: 10.5, weight: .semibold)).foregroundStyle(PS.fg3)
                }
                .font(PS.sys(size: 13, weight: .semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Vitals

    private var vitals: some View {
        let r = patient.record
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { vitalsOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: vitalsOpen ? "chevron.down" : "plus").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.accent).frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.vitals.isEmpty ? "Add preoperative vitals" : "Preoperative vitals")
                            .font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(r.vitals.isEmpty ? PS.accent : PS.fg2)
                        if !vitalsOpen, let line = PatientSummary.vitalsLine(r) {
                            Text(line).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            if vitalsOpen {
                let fields = PatientCatalog.vitals
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(fields) { v in
                        PreopNumberCell(label: v.label, unit: v.unit,
                                        value: Binding(get: { patient.record.vitals[v.id] }, set: { x in patient.update { $0.vitals[v.id] = x } }))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

/// Problems by system: a "no significant history" switch, a tile for each system (two columns), and a small button for
/// anything else.
struct PreopProblemsBox: View {
    @Environment(PatientStore.self) private var patient
    @State private var otherOpen = LaunchSeed.bool("ps.preop.other")

    private let columns = [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), spacing: 10, alignment: .top)]

    /// The Other conditions field shows once opened or while it holds text.
    static func showsOther(open: Bool, text: String) -> Bool { open || !text.isEmpty }

    /// Typing in the field keeps it open: deleting the last letter to retype does not take it away mid-edit.
    private var otherBinding: Binding<String> {
        Binding(get: { patient.record.otherHistory },
                set: { v in
                    otherOpen = Self.showsOther(open: otherOpen, text: patient.record.otherHistory) || !v.isEmpty
                    patient.update { $0.otherHistory = v }
                })
    }

    var body: some View {
        let r = patient.record
        PatientGroup(title: "Problems by system") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { patient.record.noHistory }, set: { v in patient.update(discrete: true) { $0.noHistory = v } })) {
                    Text("No significant medical history").font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(PS.accent)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(PatientPreop.tileSystems(r)) { s in tile(s, r) }
                }
                if Self.showsOther(open: otherOpen, text: r.otherHistory) {
                    PatientTextField(label: "Other conditions", prompt: "Anything not in the lists above, e.g. hereditary angioedema", text: otherBinding)
                        .padding(.horizontal, -14).padding(.vertical, -8)
                } else {
                    Button { withAnimation(.snappy) { otherOpen = true } } label: {
                        Label("Add other conditions", systemImage: "plus")
                            .font(PS.sys(size: 13.5, weight: .semibold))
                    }
                    .buttonStyle(.borderless).tint(PS.accent)
                }
            }
            .padding(14)
        }
    }

    private func tile(_ s: PatientSystem, _ r: PatientRecord) -> some View {
        let words = PatientPreop.tileWords(s, r)
        return NavigationLink(value: PatientEditor.system(s.id)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: s.icon).font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(words.isEmpty ? PS.fg3 : PS.accent)
                    Text(s.name).font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg)
                        .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.leading)
                }
                Text(words.isEmpty ? "—" : words)
                    .font(PS.sys(size: 12)).foregroundStyle(words.isEmpty ? PS.fg3 : PS.fg2)
                    .lineLimit(3).multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.name + ": " + (words.isEmpty ? "nothing recorded" : words))
        .accessibilityHint("Opens the page")
    }
}

/// Past surgical history, anesthetic complications and last intake, as chips that show what they hold once filled.
struct PreopHistoryChipsBox: View {
    @Environment(PatientStore.self) private var patient
    @State private var intakeOpen = LaunchSeed.bool("ps.preop.intake")

    /// "Solids 00:00 · clears 05:00" (the day too when it is not today).
    private func intakeText(_ r: PatientRecord) -> String? {
        func when(_ d: Date) -> String {
            Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened) : PatientDates.day(d) + " " + d.formatted(date: .omitted, time: .shortened)
        }
        var parts: [String] = []
        if let d = r.lastSolids { parts.append("Solids " + when(d)) }
        if let d = r.lastClears { parts.append((parts.isEmpty ? "Clears " : "clears ") + when(d)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        let r = patient.record
        let psh = r.surgeries.isEmpty ? nil : "PSH: " + r.capitalized.surgeries.map(\.text).joined(separator: "; ")
        let anesthetic = PatientSummary.anestheticComplications(r)
        let intake = intakeText(r)
        PatientGroup(title: nil) {
            VStack(alignment: .leading, spacing: 10) {
                PreopLinkList(links: [
                    PreopLink(id: "psh", title: "Past surgical history", icon: "scissors", editor: .workup("surgeries"), summary: psh),
                    PreopLink(id: "anesthetic", title: "Anesthetic complications", icon: "exclamationmark.shield", editor: .workup("anesthetic"),
                              summary: anesthetic?.text, alert: anesthetic?.alert ?? false),
                ])
                if let intake {
                    Button { withAnimation(.snappy) { intakeOpen.toggle() } } label: {
                        PreopFilledRow(title: "Last intake", summary: intake, icon: "clock", chevron: false)
                    }
                    .buttonStyle(.plain)
                } else if !intakeOpen {
                    Button { withAnimation(.snappy) { intakeOpen = true } } label: { PreopAddChip(title: "Last intake") }
                        .buttonStyle(.plain)
                }
                if intakeOpen {
                    VStack(alignment: .leading, spacing: 0) {
                        PatientIntakeRow(title: "Solids", date: patient.preopBinding(\.lastSolids, discrete: true))
                        Hairline().padding(.leading, 14)
                        PatientIntakeRow(title: "Clear fluids", date: patient.preopBinding(\.lastClears, discrete: true))
                    }
                    .background(PS.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Examination & Workup

/// ASA class and functional capacity: the suggestion, the class, E, METs, Frail and the Duke Activity Status Index.
struct PreopAsaBox: View {
    @Environment(PatientStore.self) private var patient

    var body: some View {
        PatientGroup(title: "ASA & Functional Capacity", note: PatientPreop.asaNote(patient.record)) {
            VStack(alignment: .leading, spacing: 0) {
                PatientAsaContent(compact: true)
                Hairline().padding(.leading, 14)
                PatientFunctionalContent(inlineInfo: true)
            }
        }
    }
}

/// Cardiopulmonary Evaluation: Intrathoracic procedure Yes / No, the cardiac evaluation, and the cardiac workup chips.
struct PreopCardioBox: View {
    @Environment(PatientStore.self) private var patient
    @State private var workupOpen = LaunchSeed.bool("ps.preop.workup")

    var body: some View {
        let r = patient.record
        PatientGroup(title: "Cardiopulmonary Evaluation", note: PatientFunctional.evaluationNote(r)) {
            VStack(alignment: .leading, spacing: 0) {
                intrathoracic(r)
                Hairline().padding(.leading, 14)
                PatientCardiacEvaluationContent()
                Hairline().padding(.leading, 14)
                workup(r).padding(14).jumpTarget(anchor: "preopworkup")
            }
        }
    }

    // MARK: Intrathoracic procedure

    private func intrathoracic(_ r: PatientRecord) -> some View {
        let yes = r.intrathoracicProcedure == true, no = r.intrathoracicProcedure == false
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Intrathoracic procedure").font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                // A second tap on the chosen answer clears it, as every chip does.
                YesNoPills(no: no, yes: yes,
                           onNo: { withAnimation(.snappy) { patient.update(discrete: true) { PatientPreop.setIntrathoracic(false, &$0) } } },
                           onYes: { withAnimation(.snappy) { patient.update(discrete: true) { PatientPreop.setIntrathoracic(true, &$0) } } },
                           onClear: { withAnimation(.snappy) { patient.update(discrete: true) { PatientPreop.setIntrathoracic(nil, &$0) } } })
            }
            if yes {
                VStack(alignment: .leading, spacing: 8) {
                    // What Yes set, offered as already set; the RCRI's own rule (cardiac surgery, under 18 only: an adult's
                    // card already has its one cardiac-surgery line below) in words.
                    if let set = PatientPreop.intrathoracicSetLine(r) {
                        Text(set).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                    if let note = PatientPreop.intrathoracicRcriNote(r) {
                        Text(note).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                    let thoracic = PatientPreop.previousCardiacSurgery(r)
                    let tee = PatientPreop.workup(r).first { $0.id == "tee" }
                    PreopLinkList(links: [
                        PreopLink(id: "cardiac-surgery", title: "Previous cardiac surgery", icon: "lungs", editor: .workup("intrathoracic"),
                                  summary: thoracic.isEmpty ? nil : thoracic.map(\.text).joined(separator: "; "), alert: !thoracic.isEmpty),
                        PreopLink(id: "tee-screening", title: "TEE screening", icon: tee?.icon ?? "checkmark.shield", editor: .workup("tee"),
                                  summary: tee?.summary, alert: tee?.alert ?? false),
                    ])
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: Cardiac workup

    @ViewBuilder private func workup(_ r: PatientRecord) -> some View {
        let items = PatientPreop.workup(r)
        let anyFilled = items.contains { $0.filled }
        if workupOpen || anyFilled {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Preprocedure cardiac workup").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                    Spacer(minLength: 6)
                    if !anyFilled {
                        Button("Hide") { withAnimation(.snappy) { workupOpen = false } }
                            .font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg3).buttonStyle(.plain)
                    }
                }
                PreopLinkList(links: items.map { i in
                    PreopLink(id: i.id, title: i.title, icon: i.icon, editor: PatientEditor(preopKey: i.key) ?? .workup(i.id), summary: i.summary, alert: i.alert,
                              caution: i.caution)
                })
            }
        } else {
            Button { withAnimation(.snappy) { workupOpen = true } } label: { PreopAddChip(title: "Add Preprocedure Cardiac Workup") }
                .buttonStyle(.plain)
        }
    }
}

// MARK: - Current Medications

/// Flagged medications: the chips, the AHA/ACC "Before surgery" notes behind a disclosure, and the ASRA and fasting tools.
struct PreopFlaggedBox: View {
    @Environment(PatientStore.self) private var patient
    var onOpenRoute: (String) -> Void

    var body: some View {
        let r = patient.record
        let notes = PatientPreop.beforeSurgery(r)
        let asra = r.medFlags.contains("anticoagulant") || r.medFlags.contains("p2y12")
        let fasting = r.medFlags.contains("glp1")
        PatientGroup(title: "Flagged medications") {
            VStack(alignment: .leading, spacing: 0) {
                FlaggedMedicationsChips()
                if !notes.isEmpty {
                    Hairline().padding(.leading, 14)
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("2024 AHA/ACC perioperative guideline, with the class of each recommendation.")
                                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 6)
                            PatientBeforeSurgeryRows(notes: notes).padding(.horizontal, -14)
                        }
                    } label: {
                        Text("Before surgery").font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                    }
                    .tint(PS.fg2)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                if asra || fasting {
                    Hairline().padding(.leading, 14)
                    VStack(alignment: .leading, spacing: 8) {
                        if asra { tool("Anticoagulant timing for blocks (ASRA)", route: "neuraxial") }
                        if fasting { tool("Fasting check", route: "fasting") }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func tool(_ title: String, route: String) -> some View {
        Button { onOpenRoute(route) } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle").font(PS.sys(size: 14, weight: .semibold))
                Text(title).font(PS.sys(size: 13.5, weight: .semibold)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(PS.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Risk Scores & Checks

/// The warnings at the top, then the scores and checks the record suggests.
struct PreopRiskBox: View {
    @Environment(PatientStore.self) private var patient
    var onOpenRoute: (String) -> Void

    var body: some View {
        let r = patient.record
        // RCRI is left out of the prompts for cardiac surgery (PatientRules.prompts).
        let prompts = PatientRules.prompts(r) + PatientTEE.prompts(r)
        let warnings = PatientWarnings.lines(r)
        PatientGroup(title: nil) {
            VStack(alignment: .leading, spacing: 0) {
                if !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, l in PatientLineText(line: l) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    if !prompts.isEmpty { Hairline().padding(.leading, 14) }
                }
                PatientPromptRows(prompts: prompts, onOpen: onOpenRoute)
                if prompts.isEmpty && warnings.isEmpty {
                    Text(r.ageYears == nil ? "Add the age to see the adult scores." : "No scores or checks to suggest yet.")
                        .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                }
            }
        }
    }
}
