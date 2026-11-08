import SwiftUI

// MARK: - Parts of the Assessment page, as views of their own (1.9)
//
// The Assessment editor kept these as private parts of the editor view. The reorganized Preprocedure tab (Examination &
// Workup, Current Medications, Risk Scores & Checks) shows the same controls in place, so they are views here and both
// the editor and the tab use them: one set of logic, two layouts (`compact` is the tab's). Each draws only its rows; the
// caller supplies the box (PatientGroup) around it.

// MARK: ASA class

/// The ASA suggestion, the class chips and the E switch. Compact (the tab): the suggestion on one line with the findings
/// that set it under it; otherwise the editor's table of reasons.
struct PatientAsaContent: View {
    @Environment(PatientStore.self) private var patient
    var compact = false

    var body: some View {
        let r = patient.record
        VStack(alignment: .leading, spacing: 0) {
            if let s = PatientRules.asaSuggestion(r) {
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
            .buttonStyle(CapsuleButtonStyle())
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
                    .tint(PS.accent)
                    .padding(.vertical, 6)
                }
                if let d = PatientFunctional.dasi(patient.record) {
                    PatientInfoLine(text: PatientFunctional.dasiText(d), info: PatientFunctional.dasiNote,
                                    font: PS.sys(size: 14, weight: .semibold), color: d > PatientFunctional.dasiCutoff ? PS.fg : PS.accent)
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
struct PatientCardiacEvaluationContent: View {
    @Environment(PatientStore.self) private var patient

    var body: some View {
        let r = patient.record
        VStack(alignment: .leading, spacing: 0) {
            PatientYesNoChipsRow(title: "Cardiac symptoms or signs", answer: \.cardiacSymptomsAnswer, chips: \.cardiacSymptoms, options: PatientFunctional.cardiacSymptomFlags)
            Hairline().padding(.leading, 14)
            PatientYesNoChipsRow(title: "Acute cardiac conditions", answer: \.activeCardiacAnswer, chips: \.activeCardiac, options: PatientFunctional.activeCardiac)
            if r.isAdult && !PatientFunctional.stepwiseApplies(r) {
                // Cardiac surgery: one quiet line instead of the noncardiac verdict; the condition notes stay.
                Hairline().padding(.leading, 14)
                Text(PatientFunctional.cardiacSurgeryNote)
                    .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                let advice = PatientFunctional.conditionAdvice(r)
                if !advice.isEmpty {
                    Hairline().padding(.leading, 14)
                    PatientAdviceList(title: "By condition", items: advice, tint: PS.accent)
                }
            }
            if PatientFunctional.stepwiseApplies(r) {
                Hairline().padding(.leading, 14)
                let mods = PatientFunctional.riskModifiers(r)
                if !mods.isEmpty {
                    Text("Adds risk beyond the RCRI: " + mods.joined(separator: ", ") + ".")
                        .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
                }
                let step = PatientFunctional.cardiacStep(r)
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(step.alert ? PS.accent : PS.fg)
                    Text(step.detail).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 10)
                let branch = PatientFunctional.branchAdvice(r)
                if !branch.isEmpty {
                    Hairline().padding(.leading, 14)
                    PatientAdviceList(title: "For this risk", items: branch, tint: PS.fg3)
                }
                let advice = PatientFunctional.conditionAdvice(r)
                if !advice.isEmpty {
                    Hairline().padding(.leading, 14)
                    PatientAdviceList(title: "By condition", items: advice, tint: PS.accent)
                }
            }
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
                            .foregroundStyle(p.done == nil ? PS.accent : PS.green)
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

/// The current infusions: typed in one line, the list with its rates, an Add button; long-press wobbles the list to delete.
struct CurrentInfusionsBox: View {
    @Environment(PatientStore.self) private var patient
    @State private var wobbling = false

    private func binding(_ id: UUID) -> Binding<PatientInfusion> {
        Binding(get: { patient.record.homeInfusions.first { $0.id == id } ?? PatientInfusion() },
                set: { v in patient.update { r in if let i = r.homeInfusions.firstIndex(where: { $0.id == id }) { r.homeInfusions[i] = v } } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InfusionTypeField(list: \.homeInfusions)
            Hairline().padding(.leading, 14)
            ForEach(patient.record.homeInfusions) { inf in
                InfusionRow(infusion: binding(inf.id)) { patient.update(discrete: true) { $0.homeInfusions.removeAll { $0.id == inf.id } } }
                    .wobbleDelete($wobbling, label: inf.drug.isEmpty ? "infusion" : inf.drug) { patient.update(discrete: true) { $0.homeInfusions.removeAll { $0.id == inf.id } } }
                Hairline().padding(.leading, 14)
            }
            WobbleDoneBar(editing: $wobbling)
            Button { withAnimation(.snappy) { patient.update(discrete: true) { $0.homeInfusions.append(PatientInfusion()) } } } label: { Label("Add an infusion", systemImage: "plus.circle") }
                .font(PS.sys(size: 14, weight: .semibold)).buttonStyle(.borderless).tint(PS.accent)
                .padding(14)
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
                    .tint(PS.accent)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}
