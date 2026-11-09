import SwiftUI

// MARK: - Parts of the Assessment page, as views of their own (1.9)
//
// The Assessment editor kept these as private parts of the editor view. The reorganized Preprocedure tab (Examination &
// Workup, Current Medications, Risk Scores & Checks) shows the same controls in place, so they are views here and both
// the editor and the tab use them: one set of logic, two layouts (`compact` is the tab's). Each draws only its rows; the
// caller supplies the box (PatientGroup) around it.
//
// 1.11 (Ben's notes 3, 4 and 5; the layout review's P1-3, P1-4, P1-10): the Cardiopulmonary Evaluation box and the ASA
// box live here too (PreopCardioBox, PreopAsaBox). The Intrathoracic answer comes from the planned procedure where the
// catalog knows it; the two cardiac questions are one row with a None preset until one is answered; the stepwise
// conclusion is one row with its reasoning behind it; the workup link gains the stress test; the Suggested ASA line goes
// once that class is chosen; the Current infusions box is a quiet link until a drip exists and has no ⊕ row.

// MARK: Quiet link (grammar A: opens in place, collapses to "Name: value · Change")

/// "+ Name" while nothing is recorded; "Name: value · Change" once it is (the caller passes the filled words). The "+"
/// and Change are actions (PS.action), the words quiet (PS.fg2); `alert` draws the filled words red for a clinical
/// warning that must stay in view (an undiscussed DNR plan). The caller supplies the open controls under it.
struct QuietLinkRow: View {
    var title: String
    var filled = false
    var alert = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !filled {
                    Image(systemName: "plus").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.action).frame(width: 14)
                }
                Group {
                    if filled {
                        Text(title).foregroundStyle(alert ? PS.red : PS.fg2) + Text(" · ").foregroundStyle(PS.fg3) + Text("Change").foregroundStyle(PS.action)
                    } else {
                        Text(title).foregroundStyle(PS.fg2)
                    }
                }
                .font(PS.sys(size: 13.5, weight: .semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filled ? title : "Add " + title.replacingOccurrences(of: "Add ", with: ""))
        .accessibilityHint(filled ? "Change it" : "Opens the controls here")
    }
}

/// The small header over a quiet link's open controls: the name and a Hide button, as the urgency row has (1.10).
struct QuietOpenHeader: View {
    var label: String
    var onHide: () -> Void

    var body: some View {
        HStack {
            Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            Spacer(minLength: 6)
            Button("Hide", action: onHide)
                .font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg3).buttonStyle(.plain)
        }
    }
}

// MARK: ASA class

/// The ASA suggestion, the class chips and the E switch. Compact (the tab): the suggestion on one line with the findings
/// that set it under it, and only while it differs from the class chosen (1.11, P1-10: once ASA III is chosen the chips
/// say it); otherwise the editor's table of reasons.
struct PatientAsaContent: View {
    @Environment(PatientStore.self) private var patient
    var compact = false

    var body: some View {
        let r = patient.record
        VStack(alignment: .leading, spacing: 0) {
            if let s = PatientRules.asaSuggestion(r), !compact || PatientPreop.showsAsaSuggestion(r) {
                if compact {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Suggested: " + s.label).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(s.topFindings.joined(separator: "; ")).font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        if r.asaClass != s.level { useButton(s) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggested: " + s.label).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                        AsaReasonTable(reasons: s.reasons, top: s.level)
                        if r.asaClass != s.level { useButton(s).padding(.top, 4) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                Hairline().padding(.leading, 14)
            }
            PatientChipRow(label: "Class") {
                PatientChoice(options: (1...6).map { (id: String($0), label: (compact ? "" : "ASA ") + PatientRules.roman($0)) },
                              selection: Binding(get: { patient.record.asaClass.map { String($0) } }, set: { v in patient.update { $0.asaClass = v.flatMap { Int($0) } } }))
            }
            PatientInfoToggle(title: "Emergency (E)", info: "Delay would significantly increase the threat to life or body part",
                              isOn: Binding(get: { patient.record.asaE ?? patient.record.emergency }, set: { v in patient.update { $0.asaE = v } }))
                .padding(.bottom, 4)
        }
    }

    private func useButton(_ s: AsaSuggestion) -> some View {
        Button("Use ASA " + PatientRules.roman(s.level)) { patient.update(discrete: true) { $0.asaClass = s.level } }
            .buttonStyle(CapsuleButtonStyle(color: PS.action))
    }
}

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

// MARK: Functional capacity

/// METs, the Duke Activity Status Index and the Frail switch. With `inlineInfo` the METs row carries the ⓘ of its guidance
/// itself (the tab's box has no title of its own for it).
struct PatientFunctionalContent: View {
    @Environment(PatientStore.self) private var patient
    var inlineInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let mets = PatientChoice(choices: PatientPreop110.mets,
                                     selection: Binding(get: { patient.record.mets }, set: { v in patient.update { $0.mets = v } }))
            if inlineInfo {
                InfoChipRow(label: "Functional capacity", info: PatientFunctional.metsNote) { mets }
            } else {
                PatientChipRow(label: nil) { mets }
            }
            PatientDasiDisclosure()
            Hairline().padding(.leading, 14)
            PatientInfoToggle(title: "Frail", detail: "By a validated tool",
                              info: "Use a validated tool, such as the Clinical Frailty Scale. Assessing frailty is reasonable at 65 or older, or younger with perceived frailty, before elevated-risk surgery (2024 AHA/ACC, class 2a).",
                              isOn: Binding(get: { patient.record.frail }, set: { v in patient.update { $0.frail = v } }))
                .padding(.bottom, 4)
        }
    }
}

/// The Duke Activity Status Index: its items behind a disclosure, the score under them.
struct PatientDasiDisclosure: View {
    @Environment(PatientStore.self) private var patient

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(PatientFunctional.dasiItems) { it in
                    Toggle(isOn: Binding(get: { patient.record.dasi.contains(it.id) }, set: { on in patient.update(discrete: true) { if on { $0.dasi.insert(it.id) } else { $0.dasi.remove(it.id) } } })) {
                        Text(it.label).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                    }
                    .tint(PS.action)
                    .padding(.vertical, 6)
                }
                if let d = PatientFunctional.dasi(patient.record) {
                    PatientInfoLine(text: PatientFunctional.dasiText(d), info: PatientFunctional.dasiNote,
                                    font: PS.sys(size: 14, weight: .semibold), color: d > PatientFunctional.dasiCutoff ? PS.fg : PS.red)
                        .padding(.top, 6)
                }
            }
        } label: {
            Text("Duke Activity Status Index").font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
        }
        .tint(PS.fg2)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: Cardiac evaluation

/// One line with No and Yes; Yes opens the chips. No clears them.
struct PatientYesNoChipsRow: View {
    @Environment(PatientStore.self) private var patient
    var title: String
    var answer: WritableKeyPath<PatientRecord, Bool?>
    var chips: WritableKeyPath<PatientRecord, Set<String>>
    var options: [PatientFlag]

    var body: some View {
        let r = patient.record
        let picked = !r[keyPath: chips].isEmpty
        let yes = r[keyPath: answer] == true || picked
        let no = r[keyPath: answer] == false && !picked
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(title).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                YesNoPills(no: no, yes: yes,
                           onNo: { withAnimation(.snappy) { patient.update(discrete: true) { PatientPreop110.tapYesNo(false, answer: answer, chips: chips, in: &$0) } } },
                           onYes: { withAnimation(.snappy) { patient.update(discrete: true) { PatientPreop110.tapYesNo(true, answer: answer, chips: chips, in: &$0) } } },
                           // A second tap on the answer shown clears it to unanswered (and the chips under a Yes).
                           onClear: { withAnimation(.snappy) { patient.update(discrete: true) {
                               PatientPreop110.tapYesNo(yes, answer: answer, chips: chips, in: &$0) } } })
            }
            if yes {
                PatientChips(options: options, selection: Binding(get: { patient.record[keyPath: chips] }, set: { v in patient.update { $0[keyPath: chips] = v } }))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// A titled list of recommendations, each on its own line.
struct PatientAdviceList: View {
    var title: String
    var items: [String]
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            ForEach(Array(items.enumerated()), id: \.offset) { _, a in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "arrow.turn.down.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(tint)
                    Text(a).font(PS.sys(size: 13)).foregroundStyle(PS.fg).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// The 2024 AHA/ACC stepwise evaluation: cardiac symptoms and acute conditions as No / Yes, then the step it reaches and
/// its advice (adults only; under 18 the symptoms and acute conditions are still recorded). The "Previous intrathoracic
/// surgery" row is gone (Ben, 1.9): the Preprocedure tab's Intrathoracic procedure answer leads to it.
///
/// 1.11 (P1-3 b, c; Q4): while both questions are unanswered, or both are No, they are one row with a "None" preset
/// (both No in one Undo step; a second tap clears both) and an "Add…" that opens the two rows; once one is answered
/// otherwise the two rows show as before. The conclusion is one row with a chevron; the reasoning (what adds risk, the
/// detail, "For this risk", "By condition") opens under it, and opens by itself for a red acute-condition row, which is
/// never folded away. For a planned cardiac operation nothing stepwise is shown (the box's ⓘ says why); its condition
/// notes sit behind a "Condition notes" row.
struct PatientCardiacEvaluationContent: View {
    @Environment(PatientStore.self) private var patient
    /// "Add…" was tapped: the two rows show even while both are unanswered.
    @State private var rowsOpen = LaunchSeed.bool("ps.preop.symptoms")
    /// The conclusion's reasoning is open; nil follows the row (open for an alert).
    @State private var resultOpen: Bool? = LaunchSeed.bool("ps.preop.result") ? true : nil
    @State private var conditionsOpen = LaunchSeed.bool("ps.preop.result")

    var body: some View {
        let r = patient.record
        VStack(alignment: .leading, spacing: 0) {
            if let none = PatientPreop.cardiacNone(r), !rowsOpen {
                noneRow(applied: none)
            } else {
                PatientYesNoChipsRow(title: "Cardiac symptoms or signs", answer: \.cardiacSymptomsAnswer, chips: \.cardiacSymptoms, options: PatientFunctional.cardiacSymptomFlags)
                Hairline().padding(.leading, 14)
                PatientYesNoChipsRow(title: "Acute cardiac conditions", answer: \.activeCardiacAnswer, chips: \.activeCardiac, options: PatientFunctional.activeCardiac)
            }
            if r.isAdult && !PatientFunctional.stepwiseApplies(r) {
                // Cardiac surgery: no stepwise verdict (the box's ⓘ says so); the condition notes, less the valve ones, behind a row.
                let advice = PatientFunctional.conditionAdvice(r)
                if !advice.isEmpty {
                    Hairline().padding(.leading, 14)
                    disclosureRow(icon: "list.bullet", title: "Condition notes", count: advice.count, open: conditionsOpen) {
                        conditionsOpen.toggle()
                    }
                    if conditionsOpen {
                        PatientAdviceList(title: "By condition", items: advice, tint: PS.fg3)
                    }
                }
            }
            if PatientFunctional.stepwiseApplies(r) {
                Hairline().padding(.leading, 14)
                let step = PatientFunctional.cardiacStep(r)
                let open = resultOpen ?? step.alert
                resultRow(step, open: open) { resultOpen = !open }
                if open {
                    let mods = PatientFunctional.riskModifiers(r)
                    VStack(alignment: .leading, spacing: 6) {
                        if !mods.isEmpty {
                            Text("Adds risk beyond the RCRI: " + mods.joined(separator: ", ") + ".")
                                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                        }
                        Text(step.detail).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.bottom, 10)
                    let branch = PatientFunctional.branchAdvice(r)
                    if !branch.isEmpty {
                        Hairline().padding(.leading, 14)
                        PatientAdviceList(title: "For this risk", items: branch, tint: PS.fg3)
                    }
                    let advice = PatientFunctional.conditionAdvice(r)
                    if !advice.isEmpty {
                        Hairline().padding(.leading, 14)
                        PatientAdviceList(title: "By condition", items: advice, tint: PS.fg3)
                    }
                }
            }
        }
    }

    // MARK: One row for the two questions

    private func noneRow(applied: Bool) -> some View {
        let title = Text(PatientPreop.cardiacNoneTitle).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
            .fixedSize(horizontal: false, vertical: true)
        let buttons = HStack(spacing: 8) {
            Button {
                Haptics.light()
                withAnimation(.snappy) { patient.update(discrete: true) { PatientPreop.setCardiacNone(!applied, &$0) } }
            } label: {
                Text("None")
            }
            .buttonStyle(PresetButtonStyle(applied: applied))
            .accessibilityLabel(applied ? "None, applied" : "None")
            .accessibilityHint(PatientPreop.cardiacNoneCaption)
            Button {
                Haptics.light()
                withAnimation(.snappy) { rowsOpen = true }
            } label: {
                Label("Add…", systemImage: "plus")
            }
            .buttonStyle(CapsuleButtonStyle(prominent: false))
            .accessibilityLabel("Add cardiac symptoms or acute conditions")
            .accessibilityHint("Shows the two questions with their findings")
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                title
                Spacer(minLength: 6)
                buttons
            }
            VStack(alignment: .leading, spacing: 8) {
                title
                buttons
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: The one result row

    private func resultRow(_ step: CardiacStep, open: Bool, toggle: @escaping () -> Void) -> some View {
        let proceeds = step.title.hasSuffix("proceed")
        return Button {
            withAnimation(.snappy) { toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: step.alert ? "exclamationmark.triangle.fill" : (proceeds ? "checkmark.circle.fill" : "questionmark.circle"))
                    .font(PS.sys(size: 14, weight: .semibold))
                    .foregroundStyle(step.alert ? PS.red : (proceeds ? PS.green : PS.fg3))
                    .frame(width: 18)
                Text(step.title).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(step.alert ? PS.red : PS.fg)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Image(systemName: open ? "chevron.down" : "chevron.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(open ? "Hides the reasoning" : "Shows the reasoning and the recommendations")
    }

    private func disclosureRow(icon: String, title: String, count: Int, open: Bool, toggle: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg3).frame(width: 18)
                Text(title).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                Text(String(count)).font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg3)
                Spacer(minLength: 6)
                Image(systemName: open ? "chevron.down" : "chevron.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Cardiopulmonary Evaluation box

/// Cardiopulmonary Evaluation: Intrathoracic procedure (the planned procedure's answer where the catalog knows it,
/// else Yes / No), the cardiac evaluation, and the cardiac workup link with its chips.
struct PreopCardioBox: View {
    @Environment(PatientStore.self) private var patient
    @State private var workupOpen = LaunchSeed.bool("ps.preop.workup")
    /// "Change" on the derived Intrathoracic line: the pills show until an answer is picked, or the shown one is tapped
    /// again (which keeps the procedure's answer).
    @State private var intrathoracicOpen = LaunchSeed.bool("ps.preop.intrathoracic")

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
        let derived = PatientPreop.intrathoracicDerived(r) != nil
        return VStack(alignment: .leading, spacing: 10) {
            if let line = PatientPreop.intrathoracicDerivedLine(r), !intrathoracicOpen {
                // 1.11 (Ben's note 3): the procedure answered it; a quiet line says so, with Change beside it.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line).font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button("Change") { withAnimation(.snappy) { intrathoracicOpen = true } }
                        .font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.action).buttonStyle(.plain)
                        .accessibilityHint("Shows No and Yes to answer it yourself")
                }
            } else {
                HStack(spacing: 10) {
                    Text("Intrathoracic procedure").font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    // A second tap on the chosen answer clears it, as every chip does; on the procedure's own answer it
                    // keeps that answer and folds the pills back into the line.
                    YesNoPills(no: no, yes: yes,
                               onNo: { withAnimation(.snappy) { intrathoracicOpen = false; patient.update(discrete: true) { PatientPreop.setIntrathoracic(false, &$0) } } },
                               onYes: { withAnimation(.snappy) { intrathoracicOpen = false; patient.update(discrete: true) { PatientPreop.setIntrathoracic(true, &$0) } } },
                               onClear: { withAnimation(.snappy) {
                                   if derived { intrathoracicOpen = false } else { patient.update(discrete: true) { PatientPreop.setIntrathoracic(nil, &$0) } } } })
                }
            }
            if yes {
                VStack(alignment: .leading, spacing: 8) {
                    // The RCRI's own rule (cardiac surgery, under 18 only: an adult's box says it in its ⓘ) in words. The
                    // "Incision: Intrathoracic" line is gone (1.11, P1-10): it reads under "+ Risk-score inputs".
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
            // 1.11 (Ben's note 4): named for what it holds; a quiet link, since it opens the chips in place.
            QuietLinkRow(title: PatientPreop.workupLinkTitle) { withAnimation(.snappy) { workupOpen = true } }
        }
    }
}

// MARK: Risk scores and checks

/// The prompts (risk scores and checks the record suggests), each opening its tool.
struct PatientPromptRows: View {
    var prompts: [PatientPrompt]
    var onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(prompts.enumerated()), id: \.element.id) { i, p in
                Button { onOpen(p.route) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: p.done == nil ? "circle.dashed" : "checkmark.circle.fill")
                            .font(PS.sys(size: 16, weight: .semibold))
                            .foregroundStyle(p.done == nil ? PS.action : PS.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.done ?? p.title).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Text(p.why).font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < prompts.count - 1 { Hairline().padding(.leading, 42) }
            }
        }
    }
}

// MARK: Medications

/// The current infusions (drips running before the case): a "+ Current infusions" link until a drip exists (1.11, P1-9),
/// then the type line and the list with its rates; long-press wobbles the list to delete. The "⊕ Add an infusion" row is
/// gone (Ben's note 5): the type line adds drips. The caller supplies the captioned box.
struct CurrentInfusionsBox: View {
    @Environment(PatientStore.self) private var patient
    @State private var wobbling = false
    @State private var open = LaunchSeed.bool("ps.preop.infusions")

    private func binding(_ id: UUID) -> Binding<PatientInfusion> {
        Binding(get: { patient.record.homeInfusions.first { $0.id == id } ?? PatientInfusion() },
                set: { v in patient.update { r in if let i = r.homeInfusions.firstIndex(where: { $0.id == id }) { r.homeInfusions[i] = v } } })
    }

    var body: some View {
        let r = patient.record
        VStack(alignment: .leading, spacing: 0) {
            if r.homeInfusions.isEmpty && !open {
                QuietLinkRow(title: "Current infusions") { withAnimation(.snappy) { open = true } }
                    .padding(14)
            } else {
                InfusionTypeField(list: \.homeInfusions)
                Hairline().padding(.leading, 14)
                ForEach(r.homeInfusions) { inf in
                    InfusionRow(infusion: binding(inf.id)) { patient.update(discrete: true) { $0.homeInfusions.removeAll { $0.id == inf.id } } }
                        .wobbleDelete($wobbling, label: inf.drug.isEmpty ? "infusion" : inf.drug) { patient.update(discrete: true) { $0.homeInfusions.removeAll { $0.id == inf.id } } }
                    Hairline().padding(.leading, 14)
                }
                WobbleDoneBar(editing: $wobbling)
            }
        }
    }
}

/// The AHA/ACC "Before surgery" note of each flagged medication that has one.
struct PatientBeforeSurgeryRows: View {
    var notes: [(label: String, note: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(notes.enumerated()), id: \.offset) { i, n in
                VStack(alignment: .leading, spacing: 3) {
                    Text(n.label).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                    Text(n.note).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 10)
                if i < notes.count - 1 { Hairline().padding(.leading, 14) }
            }
        }
    }
}

// MARK: Last intake

/// One last-intake time (solids, clear fluids): Set time starts at midnight, the usual nothing-by-mouth instruction.
struct PatientIntakeRow: View {
    var title: String
    @Binding var date: Date?

    var body: some View {
        HStack {
            Text(title).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
            Spacer()
            if let d = date {
                DatePicker(title, selection: Binding(get: { d }, set: { date = $0 }), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                Button { date = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the time")
            } else {
                Button("Set time") { date = PatientRecord.npoMidnight() }
                    .font(PS.sys(size: 13.5, weight: .semibold))
                    .buttonStyle(.borderless)
                    .tint(PS.action)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}
