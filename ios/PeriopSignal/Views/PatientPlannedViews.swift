import SwiftUI

// MARK: - The Preprocedure tab's top (1.10, Ben's Nov 7 chat 6 and 7)
//
// The openable "Procedure" card is an always-open "Planned Procedure & Anesthetic" box, like Demographics & History: the
// procedure search bar (the Procedure editor's own, with its list and side words), the planned procedures, a "+ Procedure
// urgency" link (the urgency chips open in place; once one is chosen the box shows it with a Change control) and the
// planned anesthetic chips on one line (GA, MAC, PNB, Neuraxial). Under the box a "+ Risk-score inputs" link opens the
// high-risk switch, the ARISCAT incision and the expected duration in place; once any is filled the link shows them in one
// line. The Procedure editor is still there for deep links and the old keys (PatientEditor.procedure).

// MARK: - Chip rows shared by the box and the editors

/// Urgency (2024 AHA/ACC): Elective, Time-sensitive, Urgent, Emergency, on one line where they fit; a second tap clears it.
struct UrgencyChips: View {
    @Environment(PatientStore.self) private var patient

    var body: some View {
        PatientChoice(options: PatientUrgency.allCases.map { (id: $0.rawValue, label: $0.label) },
                      selection: Binding(get: { patient.record.urgency?.rawValue }, set: { v in patient.update { $0.urgency = v.flatMap { PatientUrgency(rawValue: $0) } } }),
                      tint: PS.accent)
    }
}

/// Planned anesthetic: GA, MAC, PNB, Neuraxial (VoiceOver reads the full names); several can be chosen.
struct AnestheticChips: View {
    @Environment(PatientStore.self) private var patient

    var body: some View {
        ChipSet(options: PatientPreop110.anesthetics, style: .toggle, tint: PS.accent2,
                isOn: { patient.record.anesthetic.contains($0) },
                tap: { id in patient.update { if $0.anesthetic.contains(id) { $0.anesthetic.remove(id) } else { $0.anesthetic.insert(id) } } })
    }
}

/// ARISCAT incision.
struct IncisionChips: View {
    @Environment(PatientStore.self) private var patient
    var body: some View {
        PatientChoice(choices: PatientPreop110.incisions,
                      selection: Binding(get: { patient.record.incision }, set: { v in patient.update { $0.incision = v } }))
    }
}

/// ARISCAT expected duration.
struct DurationChips: View {
    @Environment(PatientStore.self) private var patient
    var body: some View {
        PatientChoice(choices: PatientPreop110.durations,
                      selection: Binding(get: { patient.record.duration }, set: { v in patient.update { $0.duration = v } }))
    }
}

/// How the box's inputs are worded for the risk-score inputs group's ⓘ: where they come from.
enum PlannedBoxNotes {
    static func riskInputs(_ r: PatientRecord) -> String? {
        var parts: [String] = []
        if r.procedures.contains(where: { $0.catalogID != nil }) {
            parts.append("Filled in from the planned procedures; change any that do not fit this case. Several procedures: high risk if any is, the most serious incision, and the longest duration (one step longer when two or more each take over 2 h).")
        }
        if PatientRules.cardiacSurgery(r) { parts.append(PatientRules.rcriHiddenNote) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

// MARK: - Planned Procedure & Anesthetic

struct PreopPlannedBox: View {
    @Environment(PatientStore.self) private var patient
    @State private var urgencyOpen = LaunchSeed.bool("ps.preop.urgency")

    /// The chosen urgency's definition, for the title's ⓘ (as the Procedure editor does).
    private var urgencyNote: String? { patient.record.urgency.map { $0.detail + " (2024 AHA/ACC)" } }

    var body: some View {
        let r = patient.record
        PatientGroup(title: "Planned Procedure & Anesthetic", note: urgencyNote) {
            VStack(alignment: .leading, spacing: 0) {
                ProcedureSearchField(seedKey: "ps.procsearch") { items in patient.update(discrete: true) { $0.setProcedures($0.procedures + items) } }
                ForEach(r.procedures) { p in
                    Hairline().padding(.leading, 14)
                    PlannedProcedureRow(item: plannedBinding(p.id)) { remove(p.id) }
                }
                Hairline().padding(.leading, 14)
                urgency(r)
                Hairline().padding(.leading, 14)
                PatientChipRow(label: "Planned anesthetic") { AnestheticChips() }
            }
        }
        .onAppear(perform: readOldProcedureText)
        // Choosing an urgency closes the chips onto the "Urgency: Urgent" line; clearing it leaves them open.
        .onChange(of: patient.record.urgency) { _, u in if u != nil, urgencyOpen { withAnimation(.snappy) { urgencyOpen = false } } }
    }

    // MARK: Urgency

    /// "+ Procedure urgency" while none is chosen; the chips in place when it is tapped; once chosen, the urgency with Change.
    @ViewBuilder private func urgency(_ r: PatientRecord) -> some View {
        if urgencyOpen {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Urgency").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
                    Spacer(minLength: 6)
                    Button("Hide") { withAnimation(.snappy) { urgencyOpen = false } }
                        .font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg3).buttonStyle(.plain)
                }
                UrgencyChips()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
        } else if let u = r.urgency {
            Button { withAnimation(.snappy) { urgencyOpen = true } } label: {
                HStack(spacing: 8) {
                    Text("Urgency").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
                    Text(u.label).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                    Spacer(minLength: 6)
                    Text("Change").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.accent)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 14).padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Urgency: " + u.label)
            .accessibilityHint("Opens the urgency choices to change it")
            .accessibilityAddTraits(.isButton)
        } else {
            Button { withAnimation(.snappy) { urgencyOpen = true } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(PS.sys(size: 11, weight: .bold)).frame(width: 14)
                    Text("Procedure urgency").font(PS.sys(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(PS.accent)
                .contentShape(Rectangle())
                .padding(.horizontal, 14).padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add procedure urgency")
            .accessibilityHint("Opens the urgency choices")
        }
    }

    // MARK: Procedures

    private func remove(_ id: UUID) {
        withAnimation(.snappy) { patient.update(discrete: true) { $0.setProcedures($0.procedures.filter { $0.id != id }) } }
    }

    private func plannedBinding(_ id: UUID) -> Binding<PlannedProcedure> {
        Binding(get: { patient.record.procedures.first { $0.id == id } ?? PlannedProcedure() },
                set: { v in patient.update { r in
                    var list = r.procedures
                    if let i = list.firstIndex(where: { $0.id == id }) { list[i] = v; r.setProcedures(list) }
                } })
    }

    /// A record saved before 1.6 has the procedure as text only: read it into items once (as the Procedure editor does).
    private func readOldProcedureText() {
        let r = patient.record
        guard r.procedures.isEmpty, !r.procedure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        patient.update(discrete: true) { $0.procedures = PlannedProcedure.parse($0.procedure) }
    }
}

// MARK: - Risk-score inputs link

/// "+ Risk-score inputs" under the box: opens the high-risk switch, the ARISCAT incision and the expected duration in place.
/// Once any is filled the link shows them in one line ("High-risk surgery · Upper abdominal incision · Over 2 to 3 h").
struct PreopRiskInputsLink: View {
    @Environment(PatientStore.self) private var patient
    @State private var open = LaunchSeed.bool("ps.preop.risk")

    var body: some View {
        let r = patient.record
        let line = PatientPreop110.riskInputsLine(r)
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "plus").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.accent).frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Risk-score inputs").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(line == nil ? PS.accent : PS.fg2)
                        if let line, !open {
                            Text(line).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).multilineTextAlignment(.leading)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Risk-score inputs" + (line.map { ": " + $0 } ?? ""))
            .accessibilityHint(open ? "Closes the inputs" : "Opens the high-risk surgery switch, the incision and the expected duration")
            .accessibilityAddTraits(.isButton)
            if open {
                PatientGroup(title: nil, note: PlannedBoxNotes.riskInputs(r)) {
                    if !PatientRules.cardiacSurgery(r) {
                        Toggle(isOn: Binding(get: { patient.record.highRiskSurgery }, set: { v in patient.update(discrete: true) { $0.highRiskSurgery = v } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("High-risk surgery").font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                                Text("Intraperitoneal, intrathoracic or suprainguinal vascular (RCRI)").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(PS.accent)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                    }
                    PatientChipRow(label: "Incision (ARISCAT)") { IncisionChips() }
                    PatientChipRow(label: "Expected duration (ARISCAT)") { DurationChips() }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
