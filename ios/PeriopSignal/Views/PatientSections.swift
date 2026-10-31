import SwiftUI

// MARK: - My Patient sections added in 1.6: procedure and demographics, the surgical history, the cardiac
// evaluation's tests, the current airway, current infusions, and the intraoperative record in parts.

extension PatientEditorView {

    // MARK: Procedure and demographics

    @ViewBuilder var procedureEditor: some View {
        PatientGroup(title: "Procedure") {
            PatientTextField(label: "Procedure", prompt: "e.g. laparoscopic colectomy", text: bind(\.procedure))
            PatientChipRow(label: "Urgency") {
                PatientChoice(options: PatientUrgency.allCases.map { (id: $0.rawValue, label: $0.label) }, selection: urgencyChoice, tint: PS.accent)
            }
            if let u = r.urgency {
                EvidenceNote(u.detail + " (2024 AHA/ACC)")
                    .padding(.horizontal, 14).padding(.bottom, 8)
            }
            PatientChipRow(label: "Planned anesthetic") { PatientChips(options: PatientCatalog.anesthetics, selection: bind(\.anesthetic), tint: PS.accent2) }
        }
        PatientGroup(title: "Risk-score inputs", note: PatientRules.cardiacSurgery(r) ? "Cardiac surgery: the RCRI is not shown, as it was derived for noncardiac surgery (Lee 1999)." : nil) {
            if !PatientRules.cardiacSurgery(r) {
                toggleRow("High-risk surgery", "Intraperitoneal, intrathoracic or suprainguinal vascular (RCRI)", bind(\.highRiskSurgery))
            }
            PatientChipRow(label: "Incision (ARISCAT)") {
                PatientChoice(options: [(id: "Peripheral", label: "Peripheral"), (id: "Upper abdominal", label: "Upper abdominal"), (id: "Intrathoracic", label: "Intrathoracic")], selection: bind(\.incision))
            }
            PatientChipRow(label: "Expected duration (ARISCAT)") {
                PatientChoice(options: [(id: "≤ 2 h", label: "2 h or less"), (id: "> 2–3 h", label: "Over 2 to 3 h"), (id: "> 3 h", label: "Over 3 h")], selection: bind(\.duration))
            }
        }
    }

    @ViewBuilder var demographicsEditor: some View {
        NoIdentifiersBanner()
        PatientGroup(title: "Demographics") {
            PatientNumberField(label: "Age", unit: "years", value: bind(\.ageYears))
            Hairline().padding(.leading, 14)
            PatientChipRow(label: "Sex") { PatientChoice(options: [(id: "male", label: "Male"), (id: "female", label: "Female")], selection: sexChoice) }
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "Height", unit: "cm", value: bind(\.heightCm))
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "Weight", unit: "kg", value: bind(\.weightKg))
            if r.bmi != nil {
                Text(PatientSummary.bodyLine(r)).font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg2)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PS.surface2.opacity(0.5))
            }
        }
        if r.bmi != nil {
            EvidenceNote("BSA by DuBois and DuBois, as in the echo tools; ideal body weight by Devine (from 152 cm); lean body weight by Janmahasatian.")
        }
        PatientGroup(title: "Preprocedure vital signs") {
            ForEach(Array(PatientCatalog.vitals.enumerated()), id: \.element.id) { i, v in
                PatientNumberField(label: v.label, unit: v.unit, value: entry(\.vitals, v.id))
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
        default: EmptyView()
        }
    }

    @ViewBuilder private var surgeriesEditor: some View {
        PatientGroup(title: "Past surgical history", note: "Cardiac and thoracic operations also appear under Previous intrathoracic surgery in the cardiac evaluation.") {
            ForEach(r.surgeries) { s in
                SurgeryRow(surgery: surgeryBinding(\.surgeries, s.id)) { patient.update { $0.surgeries.removeAll { $0.id == s.id } } }
                Hairline().padding(.leading, 14)
            }
            addButton("Add an operation") { patient.update { $0.surgeries.append(PatientSurgery()) } }
        }
    }

    @ViewBuilder private var intrathoracicEditor: some View {
        let fromHistory = r.surgeries.filter(\.intrathoracic)
        if !fromHistory.isEmpty {
            PatientGroup(title: "From the surgical history") {
                ForEach(fromHistory) { s in
                    Text(s.text).font(PS.sys(size: 14.5)).foregroundStyle(PS.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
        }
        PatientGroup(title: "Previous intrathoracic surgery", note: "A previous sternotomy or thoracotomy matters for re-entry, adhesions, bleeding and lung isolation.") {
            ForEach(r.intrathoracic) { s in
                SurgeryRow(surgery: surgeryBinding(\.intrathoracic, s.id), intrathoracicToggle: false) { patient.update { $0.intrathoracic.removeAll { $0.id == s.id } } }
                Hairline().padding(.leading, 14)
            }
            addButton("Add an operation") { patient.update { $0.intrathoracic.append(PatientSurgery(intrathoracic: true)) } }
        }
    }

    @ViewBuilder private var ecgEditor: some View {
        PatientGroup(title: "ECG findings") {
            if !r.ecg.isEmpty {
                WrapLayout(spacing: 7) {
                    ForEach(r.ecg, id: \.self) { f in
                        RemovableChip(text: f) { patient.update { $0.ecg.removeAll { $0 == f } } }
                    }
                }
                .padding(.horizontal, 14).padding(.top, 10)
            }
            PatientTypeahead(label: "Add a finding", prompt: "Type: afib, LBBB, paced, Q waves…", options: PatientECG.findings.filter { !r.ecg.contains($0) }) { pick in
                patient.update { if !$0.ecg.contains(pick) { $0.ecg.append(pick) } }
            }
            PatientTextField(label: "Other", prompt: "Rate, axis, intervals, comparison", text: bind(\.ecgNotes))
        }
    }

    @ViewBuilder private var lhcEditor: some View {
        PatientGroup(title: "Left heart catheterization") {
            PatientChipRow(label: "Dominance") {
                PatientChoice(options: [(id: "right", label: "Right"), (id: "left", label: "Left"), (id: "codominant", label: "Codominant")], selection: bind(\.lhc.dominance))
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
        PatientGroup(title: "Right heart catheterization") {
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
    }

    @ViewBuilder private var anestheticEditor: some View {
        PatientGroup(title: "Anesthetic complications") {
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
                    Button { patient.update { $0.oxygen.device = "trachCollar"; $0.vent = PatientVent() } } label: { Label("Off the ventilator: trach collar", systemImage: "arrow.uturn.right") }
                        .font(PS.sys(size: 14, weight: .semibold)).buttonStyle(.borderless).tint(PS.accent).padding(14)
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
        PatientGroup(title: "Current infusions", note: "Drips running before the case, with their rates: they carry into the intraoperative infusions when you add them there.") {
            ForEach(r.homeInfusions) { inf in
                InfusionRow(infusion: infusionBinding(\.homeInfusions, inf.id)) { patient.update { $0.homeInfusions.removeAll { $0.id == inf.id } } }
                Hairline().padding(.leading, 14)
            }
            addButton("Add an infusion") { patient.update { $0.homeInfusions.append(PatientInfusion()) } }
        }
    }

    // MARK: Helpers

    /// One line with No and Yes; Yes opens the chips. No clears them.
    func yesNoRow(_ title: String, answer: WritableKeyPath<PatientRecord, Bool?>, chips: WritableKeyPath<PatientRecord, Set<String>>, options: [PatientFlag]) -> some View {
        let picked = !r[keyPath: chips].isEmpty
        let yes = r[keyPath: answer] == true || picked
        let no = r[keyPath: answer] == false && !picked
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(title).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                Spacer(minLength: 6)
                YesNoPills(no: no, yes: yes,
                           onNo: { withAnimation(.snappy) { patient.update { $0[keyPath: answer] = false; $0[keyPath: chips] = [] } } },
                           onYes: { withAnimation(.snappy) { patient.update { $0[keyPath: answer] = true } } })
            }
            if yes { PatientChips(options: options, selection: bind(chips)) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    func addButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: { Label(title, systemImage: "plus.circle") }
            .font(PS.sys(size: 14, weight: .semibold)).buttonStyle(.borderless).tint(PS.accent)
            .padding(14)
    }

    func summaryBox(_ text: String) -> some View {
        Text(text).font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(PS.fg2).lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        Button { commit(text) } label: { Image(systemName: "plus.circle.fill").font(PS.sys(size: 18)).foregroundStyle(PS.accent) }
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
                        Image(systemName: "plus").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.accent)
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
        onPick(v)
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
        .background(PS.accent.opacity(0.12), in: Capsule())
    }
}

/// Month and year typed as "03/2019" (or "2019").
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
                .onChange(of: text) { _, t in
                    if let v = PatientMonthYear.parse(t) { value = v } else if t.isEmpty { value = PatientMonthYear() }
                }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .onAppear { text = value.text }
    }
}

/// One past operation: name, side, month and year, and whether it entered the chest.
struct SurgeryRow: View {
    @Binding var surgery: PatientSurgery
    var intrathoracicToggle = true
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Operation, e.g. CABG ×3, R TKA", text: $surgery.name)
                    .font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete this operation")
            }
            .padding(.horizontal, 14).padding(.top, 10)
            PatientChipRow(label: nil) {
                PatientChoice(options: [(id: "left", label: "Left"), (id: "right", label: "Right"), (id: "bilateral", label: "Bilateral")], selection: $surgery.side)
            }
            MonthYearField(label: "Date", value: $surgery.date)
            if intrathoracicToggle {
                Toggle(isOn: $surgery.intrathoracic) {
                    Text("Cardiac or thoracic (sternotomy, thoracotomy)").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2)
                }
                .tint(PS.accent)
                .padding(.horizontal, 14).padding(.bottom, 8)
            }
        }
    }
}

/// A drip and its rate.
struct InfusionRow: View {
    @Binding var infusion: PatientInfusion
    var onDelete: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            TextField("Drug, e.g. norepinephrine", text: $infusion.drug)
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

    private func grade(_ b: Binding<EchoGrade?>, normalLabel: String = "Normal") -> some View {
        PatientChoice(options: EchoGrade.allCases.map { (id: $0.rawValue, label: $0 == .normal ? normalLabel : $0.label) },
                      selection: Binding(get: { b.wrappedValue?.rawValue }, set: { b.wrappedValue = $0.flatMap { EchoGrade(rawValue: $0) } }))
    }

    @ViewBuilder private func valve(_ title: String, _ letter: String, _ v: Binding<EchoValve>) -> some View {
        PatientGroup(title: title) {
            PatientChipRow(label: letter + "R") { grade(v.regurgitation, normalLabel: "None") }
            PatientChipRow(label: letter + "S") { grade(v.stenosis, normalLabel: "None") }
            PatientChipRow(label: "Prosthesis or repair") {
                PatientChoice(options: EchoValve.prostheses.map { (id: $0, label: $0) },
                              selection: Binding(get: { v.wrappedValue.prosthesis.isEmpty ? nil : v.wrappedValue.prosthesis }, set: { v.wrappedValue.prosthesis = $0 ?? "" }))
            }
        }
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
        PatientGroup(title: "Left ventricle") {
            PatientChipRow(label: "Function") { grade($echo.lv) }
            PatientNumberField(label: "Ejection fraction", unit: "%", value: $echo.lvef)
        }
        PatientGroup(title: "Right ventricle") {
            PatientChipRow(label: "Function") { grade($echo.rv) }
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
        EvidenceNote("Grades as the ASE documents name them: chamber function normal or mildly, moderately or severely reduced; regurgitation and stenosis none, mild, moderate or severe. The ASE grading and chamber tools under Reference work the numbers out.")
    }
}

/// The No and Yes pills of a single-line question.
struct YesNoPills: View {
    var no: Bool
    var yes: Bool
    var onNo: () -> Void
    var onYes: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            pill("No", on: no, tint: PS.green, action: onNo)
            pill("Yes", on: yes, tint: PS.accent, action: onYes)
        }
    }
    private func pill(_ t: String, on: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button { Haptics.light(); action() } label: {
            Text(t).font(PS.sys(size: 13.5, weight: .semibold))
                .foregroundStyle(on ? PS.accentFg : PS.fg2)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(on ? tint : PS.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
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
        let intra = isSaved(myPatient.record.intraopEcho)
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
                Button("Preoperative echo") { Haptics.light(); myPatient.update { save(&$0.echoFindings) } }
                Button("Intraoperative echo") { Haptics.light(); myPatient.update { save(&$0.intraopEcho) } }
            } label: {
                Text(pre || intra ? "Update" : "Save").font(PS.sys(size: 13.5, weight: .semibold))
            }
            .buttonStyle(CapsuleButtonStyle(prominent: !(pre || intra)))
        }
        .padding(12)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
