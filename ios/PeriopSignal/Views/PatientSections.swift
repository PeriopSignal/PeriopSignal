import SwiftUI

// MARK: - My Patient sections added in 1.6: procedure and demographics, the surgical history, the cardiac
// evaluation's tests, the current airway, current infusions, and the intraoperative record in parts.

/// 1.11 (P1-6, one heading per thing): a page's only box draws no caption that says the page's title again ("ECG" over
/// "ECG FINDINGS", "Left Heart Catheterization" over "LEFT HEART CATHETERIZATION"). A caption that carries the box's ⓘ
/// stays: a page has no title line for the ⓘ to move to, and the note would otherwise fall under a long list.
enum PatientPageCaption {
    static func caption(_ caption: String, page: String, note: String? = nil) -> String? {
        if note != nil { return caption }
        return restates(caption, page) ? nil : caption
    }

    /// The caption says the page title ("findings" after a study's name adds nothing).
    static func restates(_ caption: String, _ page: String) -> Bool {
        let c = words(caption).filter { $0 != "findings" }
        return !c.isEmpty && c == words(page)
    }

    private static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}

extension PatientEditorView {

    // MARK: Procedure and demographics

    @ViewBuilder var procedureEditor: some View {
        let recognized = r.procedures.contains { $0.catalogID != nil }
        PatientGroup(title: "Planned procedures") {
            ForEach(r.procedures) { p in
                PlannedProcedureRow(item: plannedBinding(p.id)) { patient.update(discrete: true) { $0.setProcedures($0.procedures.filter { $0.id != p.id }) } }
                    .wobbleDelete($wobbling, label: p.title) { patient.update(discrete: true) { $0.setProcedures($0.procedures.filter { $0.id != p.id }) } }
                // Laterality: the row's own red "Which side?" with its side chips is the one prompt (Ben, Nov 2: the
                // second "Pick the side for …" line was a duplicate and is gone).
                Hairline().padding(.leading, 14)
            }
            WobbleDoneBar(editing: $wobbling)
            ProcedureSearchField(seedKey: "ps.procsearch") { items in patient.update(discrete: true) { $0.setProcedures($0.procedures + items) } }
        }
        .onAppear(perform: readOldProcedureText)
        // The chosen urgency's definition: behind the group title's ⓘ (1.8.1), not on a row of its own in the card.
        PatientGroup(title: "Urgency & anesthetic", note: urgencyNote) {
            PatientChipRow(label: "Urgency") { UrgencyChips() }
            PatientChipRow(label: "Planned anesthetic") { AnestheticChips() }
        }
        PatientGroup(title: "Risk-score inputs", note: riskInputsNote(recognized: recognized)) {
            if !PatientRules.cardiacSurgery(r) {
                toggleRow("High-risk surgery", "Intraperitoneal, intrathoracic or suprainguinal vascular (RCRI)", bind(\.highRiskSurgery))
            }
            PatientChipRow(label: "Incision (ARISCAT)") { IncisionChips() }
            PatientChipRow(label: "Expected duration (ARISCAT)") { DurationChips() }
        }
    }

    /// The chosen urgency's definition, for the group title's ⓘ.
    var urgencyNote: String? { r.urgency.map { $0.detail + " (2024 AHA/ACC)" } }

    /// How the body-size line is worked out, for the group title's ⓘ once there is a line.
    var bodySizeNote: String? { PatientPreop.bodySizeNote(r) }

    private func riskInputsNote(recognized: Bool) -> String? {
        var parts: [String] = []
        if recognized {
            parts.append("Filled in from the planned procedures; change any that do not fit this case. Several procedures: high risk if any is, the most serious incision, and the longest duration (one step longer when two or more each take over 2 h).")
        }
        if PatientRules.cardiacSurgery(r) {
            parts.append(PatientRules.rcriHiddenNote)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// A record saved before 1.6 has the procedure as text only: read it into items once, leaving the text and the
    /// risk-score inputs as they were until the list is changed.
    private func readOldProcedureText() {
        guard r.procedures.isEmpty, !r.procedure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        patient.update(discrete: true) { $0.procedures = PlannedProcedure.parse($0.procedure) }
    }

    func plannedBinding(_ id: UUID) -> Binding<PlannedProcedure> {
        Binding(get: { patient.record.procedures.first { $0.id == id } ?? PlannedProcedure() },
                set: { v in patient.update { r in
                    var list = r.procedures
                    if let i = list.firstIndex(where: { $0.id == id }) { list[i] = v; r.setProcedures(list) }
                } })
    }

    @ViewBuilder var demographicsEditor: some View {
        PatientGroup(title: "Demographics", note: bodySizeNote) {
            PatientNumberField(label: "Age", unit: PatientRecord.ageFieldUnit(r.ageYears), value: bind(\.ageYears), chain: chain("age"))
            Hairline().padding(.leading, 14)
            PatientChipRow(label: "Sex") { PatientChoice(options: [(id: "male", label: "Male"), (id: "female", label: "Female")], selection: sexChoice) }
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "Height", unit: "cm", value: bind(\.heightCm), chain: chain("height"))
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "Weight", unit: "kg", value: bind(\.weightKg), chain: chain("weight"))
            if r.bmi != nil {
                Text(PatientSummary.bodyLine(r)).font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg2)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PS.surface2.opacity(0.5))
            }
        }
        PatientGroup(title: "Preprocedure vital signs") {
            ForEach(Array(PatientCatalog.vitals.enumerated()), id: \.element.id) { i, v in
                PatientNumberField(label: v.label, unit: v.unit, value: entry(\.vitals, v.id), chain: chain("vital." + v.id))
                if i < PatientCatalog.vitals.count - 1 { Hairline().padding(.leading, 14) }
            }
        }
    }

    // MARK: Workup pages

    @ViewBuilder func workup(_ id: String) -> some View {
        switch id {
        case "surgeries": surgeriesEditor
        case "intrathoracic": intrathoracicEditor
        case "ecg": ecgEditor
        case "echo": EchoFindingsEditor(echo: bind(\.echoFindings), showsStudy: true)
        case "lhc": lhcEditor
        case "rhc": rhcEditor
        case "anesthetic": anestheticEditor
        case "labs": labsEditor
        case "tee": teeScreenEditor
        case "carotid": carotidEditor
        case "radial": radialEditor
        case "pft": pftEditor
        case "codestatus": PatientCodeStatusGroup()
        case "stress": PatientStressTestEditor()
        default: EmptyView()
        }
    }

    @ViewBuilder private var surgeriesEditor: some View {
        PatientGroup(title: "Past surgical history", note: "Cardiac and thoracic operations also appear under Previous intrathoracic surgery in the cardiac evaluation.") {
            ForEach(r.surgeries) { s in
                SurgeryRow(surgery: pastSurgeryBinding(s.id)) { patient.update(discrete: true) { $0.surgeries.removeAll { $0.id == s.id } } }
                    .wobbleDelete($wobbling, label: s.text.isEmpty ? "operation" : s.text, angle: 0.6) { patient.update(discrete: true) { $0.surgeries.removeAll { $0.id == s.id } } }
            }
            WobbleDoneBar(editing: $wobbling)
            addButton(r.surgeries.isEmpty ? "Add an operation" : "Add another operation") { patient.update(discrete: true) { $0.surgeries.append(PatientSurgery()) } }
        }
    }

    /// 1.10 (Ben): the operations here are Past surgical history's own entries marked cardiac or thoracic, edited in place,
    /// so an operation entered here, on Past surgical history or as the cardiovascular page's Previous cardiac surgery is
    /// one entry (PatientHistoryDetails.editSurgery). A list saved before 1.10 was folded in when the record was read.
    @ViewBuilder private var intrathoracicEditor: some View {
        let chest = r.surgeries.filter(\.intrathoracic)
        PatientGroup(title: "Previous intrathoracic surgery", note: "A previous sternotomy or thoracotomy matters for re-entry, adhesions, bleeding and lung isolation. These operations are in Past surgical history too.") {
            ForEach(chest) { s in
                SurgeryRow(surgery: pastSurgeryBinding(s.id), intrathoracicToggle: false) { patient.update(discrete: true) { $0.surgeries.removeAll { $0.id == s.id } } }
                    .wobbleDelete($wobbling, label: s.text.isEmpty ? "operation" : s.text, angle: 0.6) { patient.update(discrete: true) { $0.surgeries.removeAll { $0.id == s.id } } }
            }
            ForEach(r.intrathoracic) { s in
                SurgeryRow(surgery: surgeryBinding(\.intrathoracic, s.id), intrathoracicToggle: false) { patient.update(discrete: true) { $0.intrathoracic.removeAll { $0.id == s.id } } }
            }
            WobbleDoneBar(editing: $wobbling)
            addButton(chest.isEmpty && r.intrathoracic.isEmpty ? "Add an operation" : "Add another operation") {
                patient.update(discrete: true) { PatientHistoryDetails.addIntrathoracic(&$0) }
            }
        }
    }

    @ViewBuilder private var ecgEditor: some View {
        PatientGroup(title: PatientPageCaption.caption("ECG findings", page: PatientEditor.workup("ecg").title)) {
            if !r.ecg.isEmpty {
                WrapLayout(spacing: 7) {
                    ForEach(r.ecg, id: \.self) { f in
                        RemovableChip(text: FreeText.cap(f)) { patient.update(discrete: true) { $0.ecg.removeAll { $0 == f } } }
                    }
                }
                .padding(.horizontal, 14).padding(.top, 10)
            }
            ECGQuickRow(ecg: bind(\.ecg))
            // The history could say more than the ECG does: offered, never filed (PatientECGLink.suggestions).
            ForEach(PatientECGLink.suggestions(r)) { s in
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.prompt).font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg2)
                    WrapLayout(spacing: 7) {
                        ForEach(s.findings, id: \.self) { f in
                            Button {
                                Haptics.light()
                                patient.update(discrete: true) { PatientECGLink.add(f, to: &$0) }
                            } label: {
                                Label(f, systemImage: "plus").font(PS.sys(size: 14, weight: .semibold))
                            }
                            .buttonStyle(CapsuleButtonStyle(prominent: false))
                            .accessibilityLabel("Add " + f + " to the ECG, from the history")
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.top, 10)
            }
            // A paced rhythm that did not add a pacemaker by itself (temporary wires, an ICD or CRT): offered for the history.
            if PatientECGLink.pacemakerSuggested(r) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("From ECG: paced rhythm — add pacemaker to the history?").font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg2)
                    Button {
                        Haptics.light()
                        patient.update(discrete: true) { PatientECGLink.addPacemaker(to: &$0) }
                    } label: {
                        Label("Pacemaker", systemImage: "plus").font(PS.sys(size: 14, weight: .semibold))
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
                    .accessibilityLabel("Add a pacemaker to the history, from the ECG")
                }
                .padding(.horizontal, 14).padding(.top, 10)
            }
            PatientTypeahead(label: "Add a finding", prompt: "Type: afib, LBBB, paced, Q waves…", options: PatientECG.findings.filter { !r.ecg.contains($0) }) { pick in
                patient.update(discrete: true) { PatientECGLink.add(pick, to: &$0) }
            }
            PatientTextField(label: "Other", prompt: "Rate, axis, intervals, comparison", text: bind(\.ecgNotes))
        }
    }

    @ViewBuilder private var lhcEditor: some View {
        PatientGroup(title: PatientPageCaption.caption("Left heart catheterization", page: PatientEditor.workup("lhc").title)) {
            PatientChipRow(label: "Dominance") {
                PatientChoice(options: [(id: "right", label: "Right"), (id: "left", label: "Left"), (id: "codominant", label: "Codominant")], selection: bind(\.lhc.dominance))
            }
            Hairline().padding(.leading, 14)
            // The cath's result: Non-obstructive or No CAD, a row of its own with chips like the dominance's (one at a time,
            // one tap on, one off). It sets no history and no score, and the vessels below stay.
            PatientChipRow(label: nil) {
                PatientChoice(options: PatientLHC.resultOptions, selection: bind(\.lhc.result))
            }
            Hairline().padding(.leading, 14)
            ForEach(Array(PatientLHC.vessels.enumerated()), id: \.element.id) { i, v in
                PatientNumberField(label: v.label, unit: "% stenosis", value: Binding(get: { patient.record.lhc.stenosis[v.id] }, set: { x in patient.update { $0.lhc.stenosis[v.id] = x } }))
                if i < PatientLHC.vessels.count - 1 { Hairline().padding(.leading, 14) }
            }
            MonthYearField(label: "Date", value: bind(\.lhc.date))
            PatientTextField(label: "Notes", prompt: "Grafts, stents, collaterals, CTO", text: bind(\.lhc.notes))
        }
        if !r.lhc.isEmpty { summaryBox(r.lhc.summary) }
    }

    @ViewBuilder private var rhcEditor: some View {
        PatientGroup(title: PatientPageCaption.caption("Right heart catheterization", page: PatientEditor.workup("rhc").title)) {
            PatientNumberField(label: "Right atrium", unit: "mmHg", value: bind(\.rhc.ra))
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "PA systolic", unit: "mmHg", value: bind(\.rhc.pasp))
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "PA diastolic", unit: "mmHg", value: bind(\.rhc.padp))
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "PA mean, if measured", unit: "mmHg", value: bind(\.rhc.pam))
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "Wedge (PCWP)", unit: "mmHg", value: bind(\.rhc.pcwp))
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "Cardiac output", unit: "L/min", value: bind(\.rhc.co))
            MonthYearField(label: "Date", value: bind(\.rhc.date))
        }
        rhcResults
    }

    @ViewBuilder private var anestheticEditor: some View {
        PatientGroup(title: PatientPageCaption.caption("Anesthetic complications", page: PatientEditor.workup("anesthetic").title)) {
            PatientChipRow(label: nil) { PatientChips(options: PatientCatalog.anesthesiaHistory, selection: bind(\.anesthesiaHistory)) }
            PatientTextField(label: "Details", prompt: "What happened, when, and what was done", text: bind(\.anesthesiaNotes))
        }
        if let s = PatientSummary.anestheticComplications(r) { summaryBox(s.text) }
    }

    // MARK: Current airway and oxygen

    @ViewBuilder var currentAirwayGroup: some View {
        PatientGroup(title: "Current airway") {
            PatientChipRow(label: nil) {
                PatientChoice(options: [(id: "natural", label: "Own airway"), (id: "ett", label: "Intubated (ETT)"), (id: "trach", label: "Tracheostomy")], selection: bind(\.currentAirway))
            }
            switch r.currentAirway {
            case "ett"?:
                PatientTextField(label: "ETT size", prompt: "e.g. 7.5", text: bind(\.ettSize))
                PatientTextField(label: "Distance", prompt: "e.g. 23 cm at the lip", text: bind(\.ettDepth))
            case "trach"?:
                PatientTextField(label: "Tracheostomy type", prompt: "e.g. Shiley 8 cuffed; fresh or mature", text: bind(\.trachType))
            default:
                EmptyView()
            }
        }
        if r.currentAirway == "ett" || (r.currentAirway == "trach" && r.oxygen.device != "trachCollar") {
            PatientGroup(title: "Ventilator") {
                PatientChipRow(label: "Mode") {
                    PatientChoice(options: PatientVent.modes.map { (id: $0, label: $0) }, selection: Binding(get: { patient.record.vent.mode.isEmpty ? nil : patient.record.vent.mode }, set: { v in patient.update { $0.vent.mode = v ?? "" } }))
                }
                PatientNumberField(label: "Tidal volume", unit: "mL", value: bind(\.vent.vt))
                Hairline().padding(.leading, 14)
                PatientNumberField(label: "Rate", unit: "/min", value: bind(\.vent.rr))
                Hairline().padding(.leading, 14)
                PatientNumberField(label: "PEEP", unit: "cmH₂O", value: bind(\.vent.peep))
                Hairline().padding(.leading, 14)
                PatientNumberField(label: "Pressure support", unit: "cmH₂O", value: bind(\.vent.ps))
                Hairline().padding(.leading, 14)
                PatientNumberField(label: "FiO₂", unit: "%", value: bind(\.vent.fio2))
                if r.currentAirway == "trach" {
                    Button { patient.update(discrete: true) { $0.oxygen.device = "trachCollar"; $0.vent = PatientVent() } } label: { Label("Off the ventilator: trach collar", systemImage: "arrow.uturn.right") }
                        .font(PS.sys(size: 14, weight: .semibold)).buttonStyle(.borderless).tint(PS.action).padding(14)
                }
            }
        }
        if r.currentAirway == "natural" || r.currentAirway == nil || r.oxygen.device == "trachCollar" {
            PatientGroup(title: "Oxygen") {
                PatientChipRow(label: nil) {
                    PatientChoice(options: PatientOxygen.devices.filter { r.currentAirway == "trach" ? $0.id == "trachCollar" || $0.id == "ra" : $0.id != "trachCollar" }.map { (id: $0.id, label: $0.label) },
                                  selection: bind(\.oxygen.device))
                }
                if let d = r.oxygen.device, PatientOxygen.flowDevices.contains(d) {
                    PatientNumberField(label: "Flow", unit: "L/min", value: bind(\.oxygen.flow))
                }
                if let d = r.oxygen.device, PatientOxygen.fio2Devices.contains(d) {
                    Hairline().padding(.leading, 14)
                    PatientNumberField(label: "FiO₂", unit: "%", value: bind(\.oxygen.fio2))
                }
            }
        }
    }

    // MARK: Current infusions (Medications & Allergies)

    @ViewBuilder var currentInfusionsGroup: some View {
        PatientGroup(title: "Current infusions", note: "Drips running before the case, with their rates: they appear in the intraoperative infusions list tagged \"from preop\".") {
            CurrentInfusionsBox()
        }
    }

    // MARK: Helpers

    /// One line with No and Yes; Yes opens the chips. No clears them.
    func yesNoRow(_ title: String, answer: WritableKeyPath<PatientRecord, Bool?>, chips: WritableKeyPath<PatientRecord, Set<String>>, options: [PatientFlag]) -> some View {
        PatientYesNoChipsRow(title: title, answer: answer, chips: chips, options: options)
    }

    func addButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: { Label(title, systemImage: "plus.circle") }
            .font(PS.sys(size: 14, weight: .semibold)).buttonStyle(.borderless).tint(PS.action)
            .padding(14)
    }

    func summaryBox(_ text: String) -> some View {
        Text(text).font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(PS.fg2).lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// An entry of Past surgical history, edited so that an operation already listed is not listed twice and a cardiac
    /// one is the cardiovascular page's Previous cardiac surgery (1.10).
    func pastSurgeryBinding(_ id: UUID) -> Binding<PatientSurgery> {
        Binding(get: { patient.record.surgeries.first { $0.id == id } ?? PatientSurgery() },
                set: { v in patient.update { PatientHistoryDetails.editSurgery(v, &$0) } })
    }

    func surgeryBinding(_ kp: WritableKeyPath<PatientRecord, [PatientSurgery]>, _ id: UUID) -> Binding<PatientSurgery> {
        Binding(get: { patient.record[keyPath: kp].first { $0.id == id } ?? PatientSurgery() },
                set: { v in patient.update { r in if let i = r[keyPath: kp].firstIndex(where: { $0.id == id }) { r[keyPath: kp][i] = v } } })
    }

    func infusionBinding(_ kp: WritableKeyPath<PatientRecord, [PatientInfusion]>, _ id: UUID) -> Binding<PatientInfusion> {
        Binding(get: { patient.record[keyPath: kp].first { $0.id == id } ?? PatientInfusion() },
                set: { v in patient.update { r in if let i = r[keyPath: kp].firstIndex(where: { $0.id == id }) { r[keyPath: kp][i] = v } } })
    }
}

// MARK: - Components

/// A text field whose suggestions appear under it as you type; tap one to pick it. Abbreviations match too (the
/// options carry them), so every list in My Patient can be typed into.
struct PatientTypeahead: View {
    var label: String
    var prompt: String
    var options: [String]
    var onPick: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var matches: [String] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let words = q.split(separator: " ").map(String.init)
        return options.filter { o in
            let l = o.lowercased()
            return words.allSatisfy { w in l.contains(w) }
        }
        .sorted { a, b in (a.lowercased().hasPrefix(q) ? 0 : 1, a.count) < (b.lowercased().hasPrefix(q) ? 0 : 1, b.count) }
        .prefix(6).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg3)
                HStack {
                    TextField(prompt, text: $text)
                        .focused($focused)
                        .font(PS.sys(size: 15))
                        .foregroundStyle(PS.fg)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit { commit(matches.first ?? text) }
                    if !text.isEmpty {
                        Button { commit(text) } label: { Image(systemName: "plus.circle.fill").font(PS.sys(size: 18)).foregroundStyle(PS.action) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add “\(text)”")
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            ForEach(matches, id: \.self) { m in
                Hairline().padding(.leading, 14)
                Button { commit(m) } label: {
                    HStack {
                        Text(m).font(PS.sys(size: 14.5)).foregroundStyle(PS.fg)
                        Spacer()
                        Image(systemName: "plus").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.action)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func commit(_ value: String) {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        Haptics.light()
        // A pick from the list stays as the list words it; anything typed starts with a capital.
        onPick(FreeText.picked(v, from: options))
        text = ""
    }
}

/// A chip with an × to take it off a list.
struct RemovableChip: View {
    var text: String
    var onRemove: () -> Void
    var body: some View {
        HStack(spacing: 5) {
            Text(text).font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg)
            Button(action: onRemove) { Image(systemName: "xmark").font(PS.sys(size: 9.5, weight: .bold)).foregroundStyle(PS.fg3) }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(text)")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(PS.action.opacity(0.12), in: Capsule())
    }
}

/// Month and year typed as "03/2019" (or "2019"). The "/" goes in by itself ("06" becomes "06/"), and the date can be
/// typed as "0626", "6 2026" or "Jun 2026" too (PatientMonthYear.typing, .parse). What is stored is unchanged.
struct MonthYearField: View {
    var label: String
    @Binding var value: PatientMonthYear
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
            Spacer()
            TextField("MM/YYYY", text: $text)
                .focused($focused)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(PS.sys(size: 15, design: .monospaced))
                .frame(maxWidth: 110)
                .onChange(of: text) { old, t in
                    let shown = PatientMonthYear.typing(t, was: old)
                    // The formatted text comes back through here once more.
                    if shown != t { text = shown; return }
                    if t.trimmingCharacters(in: .whitespaces).isEmpty {
                        if !value.isEmpty { value = PatientMonthYear() }
                    } else if let v = PatientMonthYear.parseTyped(t), v != value {
                        value = v
                    }
                }
                .onChange(of: focused) { _, on in
                    // Leaving the field: the text a half-typed date left is shown as the date it holds.
                    if !on, text != value.text { text = value.text }
                }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .onAppear {
            text = value.text
            #if DEBUG
            // Screenshot runs: -ps.monthyear 062 types those digits into an empty month and year field.
            let seed = LaunchSeed.string("ps.monthyear")
            if !seed.isEmpty, value.isEmpty {
                var typed = ""
                for ch in seed { typed = PatientMonthYear.typing(typed + String(ch), was: typed) }
                text = typed
            }
            #endif
        }
        // A change from elsewhere (Undo): show it, unless the text typed already reads as it.
        .onChange(of: value) { _, v in
            if let shown = PatientMonthYear.parseTyped(text) {
                if shown != v { text = v.text }
            } else if !focused {
                text = v.text
            }
        }
    }
}

/// One past operation: name, side, month and year, and whether it entered the chest.
/// One past operation: its date, then the procedures done that day (several when they were done together, such as
/// AVR and CABG), each from the procedure list or typed, with the side asked only when the procedure has one.
struct SurgeryRow: View {
    @Binding var surgery: PatientSurgery
    var intrathoracicToggle = true
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                MonthYearField(label: "Date", value: $surgery.date)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
                    .padding(.trailing, 14)
                    .accessibilityLabel("Delete this operation")
            }
            ForEach(surgery.procedures) { p in
                Hairline().padding(.leading, 14)
                PlannedProcedureRow(item: itemBinding(p.id), typedCaption: "Typed") {
                    withAnimation(.snappy) { surgery.setProcedures(surgery.procedures.filter { $0.id != p.id }) }
                }
            }
            Hairline().padding(.leading, 14)
            ProcedureSearchField(prompt: surgery.procedures.isEmpty ? "Operation, e.g. CABG x3, R TKA" : "Add another procedure on this date",
                                 typedCaption: "Not in the list: added as typed") { items in
                surgery.setProcedures(surgery.procedures + items)
            }
            if intrathoracicToggle {
                Toggle(isOn: $surgery.intrathoracic) {
                    Text("Cardiac or thoracic (sternotomy, thoracotomy)").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2)
                }
                .tint(PS.action)
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .padding(.vertical, 4)
        .background(PS.surface2.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private func itemBinding(_ id: UUID) -> Binding<PlannedProcedure> {
        Binding(get: { surgery.procedures.first { $0.id == id } ?? PlannedProcedure() },
                set: { v in
                    var list = surgery.procedures
                    if let i = list.firstIndex(where: { $0.id == id }) { list[i] = v; surgery.setProcedures(list) }
                })
    }
}

/// A drip and its rate.
struct InfusionRow: View {
    @Binding var infusion: PatientInfusion
    var onDelete: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            CapTextField(prompt: "Drug, e.g. norepinephrine", text: $infusion.drug)
                .font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
            TextField("Rate, e.g. 0.05 mcg/kg/min", text: $infusion.rate)
                .font(PS.sys(size: 14)).foregroundStyle(PS.fg2)
                .multilineTextAlignment(.trailing)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash").foregroundStyle(PS.fg3) }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete this infusion")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

/// Echo findings in report order: LV, RV, mitral, tricuspid, aortic valve, aorta, other.
struct EchoFindingsEditor: View {
    @Binding var echo: PatientEcho
    var showsStudy = false
    /// 1.10 (Ben): a free-text field on every chamber and valve (the intraoperative exams); elsewhere a field shows only
    /// once it holds text.
    var sectionNotes = false
    /// Scroll anchors ("echonormal", "echo-m") get this in front, so two exams on one page keep their own ("post-").
    var anchorPrefix = ""
    /// The page's one Explanation & Evidence note (the intraoperative page shows it under its last exam).
    var showsEvidence = true
    @Environment(PatientStore.self) private var store: PatientStore?
    @Environment(ReferenceStore.self) private var refs: ReferenceStore?

    /// An EF below normal by the echo tools' ASE grading: Echo normal then leaves the LV as it is.
    private var keepsLV: Bool {
        let lvef = refs?.bundle?.echo?.groups.flatMap(\.measures).first { $0.id == "lvef" }
        return PatientEcho.efBelowNormal(echo.lvef, measure: lvef, sex: store?.record.sex)
    }

    /// Chamber function and stenosis use `EchoGrade.severities`; regurgitation adds Trivial (`EchoGrade.regurgitation`).
    private func grade(_ b: Binding<EchoGrade?>, normalLabel: String = "Normal", grades: [EchoGrade] = EchoGrade.severities) -> some View {
        PatientChoice(options: grades.map { (id: $0.rawValue, label: $0 == .normal ? normalLabel : $0.label) },
                      selection: Binding(get: { b.wrappedValue?.rawValue }, set: { b.wrappedValue = $0.flatMap { EchoGrade(rawValue: $0) } }))
    }

    /// Normal or Dilated (1.10, Ben).
    private func size(_ b: Binding<EchoSize?>) -> some View {
        PatientChoice(options: EchoSize.allCases.map { (id: $0.rawValue, label: $0.label) },
                      selection: Binding(get: { b.wrappedValue?.rawValue }, set: { b.wrappedValue = $0.flatMap { EchoSize(rawValue: $0) } }))
    }

    @ViewBuilder private func notes(_ section: String, _ text: Binding<String>) -> some View {
        if sectionNotes || !text.wrappedValue.isEmpty {
            PatientTextField(label: "Notes", prompt: section, text: text)
        }
    }

    @ViewBuilder private func valve(_ title: String, _ letter: String, _ v: Binding<EchoValve>) -> some View {
        PatientGroup(title: title) {
            PatientChipRow(label: letter + "R") { grade(v.regurgitation, normalLabel: "None", grades: EchoGrade.regurgitation) }
            PatientChipRow(label: letter + "S") { grade(v.stenosis, normalLabel: "None") }
            PatientChipRow(label: "Prosthesis or repair") {
                PatientChoice(options: EchoValve.prostheses.map { (id: $0, label: $0) },
                              selection: Binding(get: { v.wrappedValue.prosthesis.isEmpty ? nil : v.wrappedValue.prosthesis }, set: { v.wrappedValue.prosthesis = $0 ?? "" }))
            }
            // 1.10 (Ben): once a prosthesis or repair is chosen, its details in the user's words, if they want.
            if EchoValve.takesDetail(v.wrappedValue.prosthesis) || !v.wrappedValue.prosthesisDetail.isEmpty {
                PatientTextField(label: "Prosthesis details (optional)", prompt: "e.g. 29 mm Magna Ease, 2019; 28 mm ring", text: v.prosthesisDetail)
            }
            notes("e.g. jet direction, PISA, gradient, leaflet motion", v.notes)
        }
        .id(anchorPrefix + "echo-" + letter.lowercased())
    }

    var body: some View {
        if showsStudy {
            PatientGroup(title: "Study") {
                PatientChipRow(label: nil) {
                    PatientChoice(options: [(id: "TTE", label: "TTE"), (id: "TEE", label: "TEE")], selection: $echo.study)
                }
                MonthYearField(label: "Date", value: $echo.date)
            }
        }
        PatientGroup(title: nil) {
            let keep = keepsLV
            PatientPresetRow(title: "Echo normal", caption: echo.normalCaption(keepingLV: keep), applied: echo.isNormalPreset(keepingLV: keep)) {
                var e = echo
                e.applyNormal(keepingLV: keep)
                store?.markDiscrete()
                echo = e
            }
        }
        .id(anchorPrefix + "echonormal")
        PatientGroup(title: "Left ventricle") {
            PatientChipRow(label: "Function") { grade($echo.lv) }
            PatientChipRow(label: "Size") { size($echo.lvSize) }
            PatientNumberField(label: "Ejection fraction", unit: "%", value: $echo.lvef)
            notes("e.g. wall motion, LVOT gradient, SAM", $echo.lvNotes)
        }
        .id(anchorPrefix + "echo-lv")
        PatientGroup(title: "Right ventricle") {
            PatientChipRow(label: "Function") { grade($echo.rv) }
            PatientChipRow(label: "Size") { size($echo.rvSize) }
            notes("e.g. TAPSE, RVSP, septal motion", $echo.rvNotes)
        }
        valve("Mitral valve", "M", $echo.mitral)
        valve("Tricuspid valve", "T", $echo.tricuspid)
        valve("Aortic valve", "A", $echo.aortic)
        PatientGroup(title: "Aorta") {
            PatientChipRow(label: nil) {
                PatientChoice(options: [(id: "intact", label: "Intact"), (id: "abnormal", label: "Abnormal")],
                              selection: Binding(get: { echo.aortaIntact.map { $0 ? "intact" : "abnormal" } }, set: { echo.aortaIntact = $0.map { $0 == "intact" } }))
            }
            if echo.aortaIntact == false || !echo.aorta.isEmpty {
                PatientTextField(label: "Findings", prompt: "e.g. ascending 4.6 cm; dissection flap; atheroma grade", text: $echo.aorta)
            }
        }
        PatientGroup(title: "Other") {
            PatientTextField(label: "Other findings", prompt: "Effusion, PFO, LA size, wall motion", text: $echo.other)
        }
        if !echo.isEmpty {
            Text(echo.summary).font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(PS.fg2).lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PS.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        if showsEvidence {
            EvidenceNote("Grades as the ASE documents name them: chamber function normal or mildly, moderately or severely reduced; regurgitation none, trivial, mild, moderate or severe; stenosis none, mild, moderate or severe. The ASE grading and chamber tools under Reference work the numbers out.")
        }
    }
}

/// A switch whose explanation sits behind an ⓘ after its title; a short `detail` can stay in view under the title.
/// Each change is an Undo step of its own, as with the editor's toggle rows.
struct PatientInfoToggle: View {
    var title: String
    var detail: String? = nil
    var info: String
    @Binding var isOn: Bool
    @Environment(PatientStore.self) private var store: PatientStore?
    @State private var open = LaunchSeed.bool("ps.evidence.open")

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(title).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                    InfoButton(open: $open, label: "About " + title)
                }
                if let detail { Text(detail).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                if open { InfoCaptionText(text: info, font: PS.sys(size: 12)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: Binding(get: { isOn }, set: { v in store?.markDiscrete(); isOn = v }))
                .labelsHidden()
                .tint(PS.action)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}

/// A line of text with its explanation behind an ⓘ at its end.
struct PatientInfoLine: View {
    var text: String
    var info: String
    var font: Font = PS.sys(size: 12.5)
    var color: Color = PS.fg3
    @State private var open = LaunchSeed.bool("ps.evidence.open")

    var body: some View {
        InfoTitle(caption: info, open: $open, captionFont: PS.sys(size: 12.5), spacing: 6) {
            Text(text).font(font).foregroundStyle(color).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The No and Yes pills of a single-line question. A second tap on the pill that is on clears the answer to
/// unanswered (`onClear`), as every chip does (Ben, Nov 7); VoiceOver says so in the selected pill's hint.
struct YesNoPills: View {
    var no: Bool
    var yes: Bool
    var onNo: () -> Void
    var onYes: () -> Void
    /// Called instead of `onNo` / `onYes` when the pill tapped is already on.
    var onClear: () -> Void

    /// 1.11 (Ben's Q7): an answer is not a verdict. The chosen pill is ink-filled like every single choice (ChipStyle.choice),
    /// no green No or red Yes; the consequence, if any, is a red line under the row.
    static let style: ChipStyle = .choice
    static func look(on: Bool) -> ChipStyle.Look { style.look(on: on) }

    var body: some View {
        HStack(spacing: 6) {
            pill("No", on: no, action: onNo)
            pill("Yes", on: yes, action: onYes)
        }
    }
    private func pill(_ t: String, on: Bool, action: @escaping () -> Void) -> some View {
        let look = Self.look(on: on)
        return Button { Haptics.light(); if on { onClear() } else { action() } } label: {
            Text(t).font(PS.sys(size: 13.5, weight: .semibold))
                .foregroundStyle(ChipStyle.color(look.text, tint: PS.action))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(ChipStyle.color(look.fill, tint: PS.action), in: Capsule())
                .overlay(Capsule().stroke(ChipStyle.color(look.edge, tint: PS.action), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(on ? "Tap again to clear the answer" : "")
    }
}

/// "Save to My Patient": writes an ASE tool's grade into the patient's preoperative or intraoperative echo findings.
struct PatientEchoSaveBar: View {
    @Environment(PatientStore.self) private var myPatient
    var label: String
    var isSaved: (PatientEcho) -> Bool
    var save: (inout PatientEcho) -> Void

    var body: some View {
        let pre = isSaved(myPatient.record.echoFindings)
        let intra = isSaved(myPatient.record.intraopEcho) || isSaved(myPatient.record.intraopEchoPost)
        HStack(spacing: 10) {
            Image(systemName: pre || intra ? "checkmark.circle.fill" : "person.text.rectangle")
                .font(PS.sys(size: 15, weight: .semibold))
                .foregroundStyle(pre || intra ? PS.green : PS.accent2)
            VStack(alignment: .leading, spacing: 1) {
                Text(pre || intra ? "In My Patient's " + (pre ? "preoperative" : "intraoperative") + " echo" : "Save to My Patient")
                    .font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                Text(label).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineLimit(2)
            }
            Spacer(minLength: 6)
            Menu {
                Button("Preoperative echo") { Haptics.light(); myPatient.update(discrete: true) { save(&$0.echoFindings) } }
                Button("Intraoperative echo") { Haptics.light(); myPatient.update(discrete: true) { save(&$0.intraopEcho) } }
                // 1.10: the post-bypass exam.
                Button("Intraoperative echo, post-bypass") { Haptics.light(); myPatient.update(discrete: true) { save(&$0.intraopEchoPost) } }
            } label: {
                Text(pre || intra ? "Update" : "Save").font(PS.sys(size: 13.5, weight: .semibold))
            }
            .buttonStyle(CapsuleButtonStyle.patientAction(prominent: !(pre || intra)))
        }
        .padding(12)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Quick picks under the ECG findings. NSR is a rhythm, so it replaces another recorded rhythm (and a second tap
/// removes it).
struct ECGQuickRow: View {
    @Binding var ecg: [String]

    /// 1.11 (P1-8): NSR is a preset like Exam normal and Echo normal (ChipStyle.preset): a green outline, a ✓ once
    /// applied, never the brand red. The chip is drawn by ChipSet, so the grammar is the code's, not this row's.
    static let style: ChipStyle = .preset
    static let chips = [ChipChoice("nsr", "NSR")]

    var body: some View {
        HStack(spacing: 8) {
            ChipSet(options: Self.chips, style: Self.style, hints: ["nsr": "Normal sinus rhythm; a second tap removes it"],
                    isOn: { _ in ecg.contains(PatientECG.nsr) }) { _ in
                withAnimation(.snappy) {
                    if ecg.contains(PatientECG.nsr) { ecg.removeAll { $0 == PatientECG.nsr } }
                    else { ecg = PatientECG.adding(PatientECG.nsr, to: ecg) }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 10)
    }
}
