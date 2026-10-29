import SwiftUI

/// The editors behind My Patient's cards.
enum PatientEditor: Hashable {
    case details, history, system(String), medications, assessment, airway, intraop, plan

    var title: String {
        switch self {
        case .details: return "Patient"
        case .history: return "History"
        case .system(let id): return PatientCatalog.allSystems.first { $0.id == id }?.name ?? "System"
        case .medications: return "Medications and Allergies"
        case .assessment: return "Assessment"
        case .airway: return "Airway and Exam"
        case .intraop: return "Intraop"
        case .plan: return "Plan"
        }
    }

    var icon: String {
        switch self {
        case .details: return "person"
        case .history: return "list.bullet.clipboard"
        case .system(let id): return PatientCatalog.allSystems.first { $0.id == id }?.icon ?? "circle"
        case .medications: return "pills"
        case .assessment: return "gauge.with.dots.needle.33percent"
        case .airway: return "mouth"
        case .intraop: return "waveform.path.ecg.rectangle"
        case .plan: return "arrow.right.circle"
        }
    }
}

struct PatientEditorView: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    var editor: PatientEditor
    var onOpenRoute: (String) -> Void
    @FocusState private var focused: Bool

    private var r: PatientRecord { patient.record }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch editor {
                    case .details: details
                    case .history: history
                    case .system(let id): system(id)
                    case .medications: medications
                    case .assessment: assessment
                    case .airway: airway
                    case .intraop: intraop
                    case .plan: plan
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .onAppear {
                #if DEBUG
                // Screenshot runs: -ps.patient.scroll cardiac | mask scrolls to that group.
                let a = LaunchSeed.string("ps.patient.scroll")
                if !a.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo(a, anchor: .top) }
                }
                #endif
            }
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(editor.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    // MARK: Bindings

    private func bind<T>(_ kp: WritableKeyPath<PatientRecord, T>) -> Binding<T> {
        Binding(get: { patient.record[keyPath: kp] }, set: { v in patient.update { $0[keyPath: kp] = v } })
    }

    private func entry(_ kp: WritableKeyPath<PatientRecord, [String: Double]>, _ key: String) -> Binding<Double?> {
        Binding(get: { patient.record[keyPath: kp][key] }, set: { v in patient.update { $0[keyPath: kp][key] = v } })
    }

    private func note(_ key: String) -> Binding<String> {
        Binding(get: { patient.record.systemNotes[key] ?? "" }, set: { v in patient.update { $0.systemNotes[key] = v.isEmpty ? nil : v } })
    }

    private var sexChoice: Binding<String?> {
        Binding(get: { patient.record.sex?.rawValue }, set: { v in patient.update { $0.sex = v.flatMap { PatientSex(rawValue: $0) } } })
    }

    private var urgencyChoice: Binding<String?> {
        Binding(get: { patient.record.urgency?.rawValue }, set: { v in patient.update { $0.urgency = v.flatMap { PatientUrgency(rawValue: $0) } } })
    }

    private func line(_ text: String) -> some View {
        Text(text).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
    }

    private func toggleRow(_ title: String, _ detail: String?, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                if let detail { Text(detail).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .tint(PS.accent)
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func linkRow(_ title: String, _ detail: String, icon: String, value: PatientEditor) -> some View {
        NavigationLink(value: value) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                    Text(detail).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineLimit(2)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toolButton(_ title: String, route: String) -> some View {
        Button { onOpenRoute(route) } label: { Label(title, systemImage: "arrow.right.circle") }
            .buttonStyle(GhostButtonStyle())
    }

    // MARK: Patient

    @ViewBuilder private var details: some View {
        PatientGroup(title: "Patient", note: "No name, record number or date of birth: the age is enough for the calculators.") {
            PatientNumberField(label: "Age", unit: "years", value: bind(\.ageYears), focus: $focused)
            Hairline().padding(.leading, 14)
            PatientChipRow(label: "Sex") { PatientChoice(options: [(id: "male", label: "Male"), (id: "female", label: "Female")], selection: sexChoice) }
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "Height", unit: "cm", value: bind(\.heightCm), focus: $focused)
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "Weight", unit: "kg", value: bind(\.weightKg), focus: $focused)
            let size = PatientSummary.bodyLine(r)
            if r.bmi != nil {
                Text(size).font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg2)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PS.surface2.opacity(0.5))
            }
        }
        if r.bmi != nil {
            line("BSA by DuBois and DuBois, as in the echo tools; ideal body weight by Devine (from 152 cm); lean body weight by Janmahasatian.")
        }
        PatientGroup(title: "Procedure") {
            PatientTextField(label: "Procedure", prompt: "e.g. laparoscopic colectomy", text: bind(\.procedure), focus: $focused)
            PatientChipRow(label: "Urgency") {
                PatientChoice(options: PatientUrgency.allCases.map { (id: $0.rawValue, label: $0.label) }, selection: urgencyChoice, tint: PS.accent)
            }
            if let u = r.urgency {
                line(u.detail + " (2024 AHA/ACC)")
                    .padding(.horizontal, 14).padding(.bottom, 8)
            }
            PatientChipRow(label: "Planned anesthetic") { PatientChips(options: PatientCatalog.anesthetics, selection: bind(\.anesthetic), tint: PS.accent2) }
            Hairline().padding(.leading, 14)
            toggleRow("High-risk surgery", "Intraperitoneal, intrathoracic or suprainguinal vascular (RCRI)", bind(\.highRiskSurgery))
            PatientChipRow(label: "Incision (ARISCAT)") {
                PatientChoice(options: [(id: "Peripheral", label: "Peripheral"), (id: "Upper abdominal", label: "Upper abdominal"), (id: "Intrathoracic", label: "Intrathoracic")], selection: bind(\.incision))
            }
            PatientChipRow(label: "Expected duration (ARISCAT)") {
                PatientChoice(options: [(id: "≤ 2 h", label: "2 h or less"), (id: "> 2–3 h", label: "Over 2 to 3 h"), (id: "> 3 h", label: "Over 3 h")], selection: bind(\.duration))
            }
        }
        PatientGroup(title: "Vital signs") {
            ForEach(Array(PatientCatalog.vitals.enumerated()), id: \.element.id) { i, v in
                PatientNumberField(label: v.label, unit: v.unit, value: entry(\.vitals, v.id), focus: $focused)
                if i < PatientCatalog.vitals.count - 1 { Hairline().padding(.leading, 14) }
            }
        }
    }

    // MARK: History

    @ViewBuilder private var history: some View {
        PatientGroup(title: nil) {
            toggleRow("No significant medical history", "Lets the tab suggest ASA I when nothing else is recorded", bind(\.noHistory))
        }
        PatientGroup(title: "Problems by system", note: "Tap a system to add its common problems; anything rare goes under Other conditions.") {
            let systems = PatientCatalog.systems(for: r)
            ForEach(Array(systems.enumerated()), id: \.element.id) { i, s in
                let picked = s.problems.filter { r.problems.contains($0.id) }.map(\.label)
                linkRow(s.name, picked.isEmpty ? "None recorded" : picked.joined(separator: "; "), icon: s.icon, value: .system(s.id))
                if i < systems.count - 1 { Hairline().padding(.leading, 50) }
            }
        }
        PatientGroup(title: "Other conditions") {
            PatientTextField(label: "Rare or uncommon conditions and findings", prompt: "e.g. hereditary angioedema; Ehlers–Danlos", text: bind(\.otherHistory), focus: $focused)
        }
        PatientGroup(title: nil) {
            linkRow("Medications and allergies", medsSummary, icon: "pills", value: .medications)
        }
        PatientGroup(title: "Smoking") {
            PatientChipRow(label: nil) {
                PatientChoice(options: [(id: "never", label: "Never"), (id: "former", label: "Former"), (id: "current", label: "Current")], selection: bind(\.smoking))
            }
        }
        PatientGroup(title: "Anesthesia history") {
            PatientChipRow(label: nil) { PatientChips(options: PatientCatalog.anesthesiaHistory, selection: bind(\.anesthesiaHistory)) }
            PatientTextField(label: "Details", prompt: "Previous anesthetics and what happened", text: bind(\.anesthesiaNotes), focus: $focused)
        }
        PatientGroup(title: "Last intake", note: "For the fasting check: the ASA fasting guidance is under Reference.") {
            intakeRow("Solids", bind(\.lastSolids))
            Hairline().padding(.leading, 14)
            intakeRow("Clear fluids", bind(\.lastClears))
        }
        PatientGroup(title: "Labs") {
            ForEach(Array(PatientCatalog.labs.enumerated()), id: \.element.id) { i, l in
                PatientNumberField(label: l.label, unit: l.unit, value: entry(\.labs, l.id), focus: $focused)
                if i < PatientCatalog.labs.count - 1 { Hairline().padding(.leading, 14) }
            }
            PatientTextField(label: "Other results", prompt: "ECG, echo, imaging, other labs", text: bind(\.labNotes), focus: $focused)
        }
    }

    private var medsSummary: String {
        if r.nkda && r.medications.isEmpty { return "No known drug allergies" }
        let parts = [r.nkda ? "NKDA" : (r.allergies.isEmpty ? "" : "Allergies: " + r.allergies), r.medications].filter { !$0.isEmpty }
        return parts.isEmpty ? "None recorded" : parts.joined(separator: " · ")
    }

    private func intakeRow(_ title: String, _ date: Binding<Date?>) -> some View {
        HStack {
            Text(title).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
            Spacer()
            if let d = date.wrappedValue {
                DatePicker(title, selection: Binding(get: { d }, set: { date.wrappedValue = $0 }), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                Button { date.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the time")
            } else {
                Button("Set time") { date.wrappedValue = Date() }
                    .font(PS.sys(size: 13.5, weight: .semibold))
                    .buttonStyle(.borderless)
                    .tint(PS.accent)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    @ViewBuilder private func system(_ id: String) -> some View {
        if let s = PatientCatalog.allSystems.first(where: { $0.id == id }) {
            PatientGroup(title: s.name, note: "Problems the ASA's own examples place in a class (adult or pediatric, by the age recorded) feed the ASA suggestion; the RCRI, STOP-Bang and other scores open with them ticked.") {
                PatientChipRow(label: nil) {
                    PatientChips(options: s.problems.map { p in PatientFlag(p.id, p.label, PatientRules.asaLevel(p, r).map { "ASA " + PatientRules.roman($0) + " example" }) }, selection: bind(\.problems))
                }
                PatientTextField(label: "Details", prompt: "Severity, dates, devices, the last echo or stress test", text: note(s.id), focus: $focused)
            }
        }
    }

    @ViewBuilder private var medications: some View {
        PatientGroup(title: "Allergies") {
            toggleRow("No known drug allergies", nil, bind(\.nkda))
            if !r.nkda {
                PatientTextField(label: "Allergies and reactions", prompt: "e.g. penicillin (rash); latex", text: bind(\.allergies), focus: $focused)
            }
        }
        PatientGroup(title: "Medications") {
            PatientTextField(label: "Home medications", prompt: "Drug, dose, last taken", text: bind(\.medications), focus: $focused)
            PatientChipRow(label: "Flags") { PatientChips(options: PatientCatalog.medFlags, selection: bind(\.medFlags)) }
        }
        let notes = PatientCatalog.medFlags.filter { r.medFlags.contains($0.id) }.compactMap { f in PatientFunctional.medNotes[f.id].map { (f.label, $0) } }
        if !notes.isEmpty {
            PatientGroup(title: "Before surgery", note: "2024 AHA/ACC perioperative guideline, with the class of each recommendation.") {
                ForEach(Array(notes.enumerated()), id: \.offset) { i, n in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(n.0).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                        Text(n.1).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if i < notes.count - 1 { Hairline().padding(.leading, 14) }
                }
            }
        }
        if r.medFlags.contains("anticoagulant") || r.medFlags.contains("p2y12") {
            toolButton("Anticoagulant timing for blocks (ASRA)", route: "neuraxial")
        }
        if r.medFlags.contains("glp1") {
            toolButton("Fasting check", route: "fasting")
        }
    }

    // MARK: Assessment

    @ViewBuilder private var assessment: some View {
        PatientGroup(title: "ASA physical status", note: "The suggestion is the highest class among the ASA's published examples (adult, pediatric under 18, and obstetric) that match what is recorded; the class is a clinical judgment, so it counts only once you choose it.") {
            if let s = PatientRules.asaSuggestion(r) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggested: " + s.label).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                    AsaReasonTable(reasons: s.reasons, top: s.level)
                    if r.asaClass != s.level {
                        Button("Use ASA " + PatientRules.roman(s.level)) { patient.update { $0.asaClass = s.level } }
                            .buttonStyle(CapsuleButtonStyle())
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                Hairline().padding(.leading, 14)
            } else if r.isChild {
                line("Tick problems under History, including the Pediatric list, or mark no significant history, for a suggestion from the ASA's pediatric examples.")
                    .padding(.horizontal, 14).padding(.vertical, 10)
            }
            PatientChipRow(label: "Class") {
                PatientChoice(options: (1...6).map { (id: String($0), label: "ASA " + PatientRules.roman($0)) },
                              selection: Binding(get: { patient.record.asaClass.map { String($0) } }, set: { v in patient.update { $0.asaClass = v.flatMap { Int($0) } } }))
            }
            toggleRow("Emergency (E)", "Delay would significantly increase the threat to life or body part", Binding(get: { patient.record.asaE ?? patient.record.emergency }, set: { v in patient.update { $0.asaE = v } }))
            if let c = r.asaClass {
                line(PatientFunctional.asaDefinition(c) + (PatientFunctional.asaExampleLead(c).map { " " + $0 } ?? ""))
                    .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
        PatientGroup(title: "Functional capacity", note: PatientFunctional.metsNote) {
            PatientChipRow(label: nil) {
                PatientChoice(options: [(id: "ge4", label: "4 METs or more"), (id: "lt4", label: "Under 4 METs"), (id: "unknown", label: "Unknown")], selection: bind(\.mets))
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(PatientFunctional.dasiItems) { it in
                        Toggle(isOn: Binding(get: { patient.record.dasi.contains(it.id) }, set: { on in patient.update { if on { $0.dasi.insert(it.id) } else { $0.dasi.remove(it.id) } } })) {
                            Text(it.label).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                        }
                        .tint(PS.accent)
                        .padding(.vertical, 6)
                    }
                    if let d = PatientFunctional.dasi(r) {
                        Text(PatientFunctional.dasiText(d)).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(d > PatientFunctional.dasiCutoff ? PS.fg : PS.accent).padding(.top, 6)
                        line(PatientFunctional.dasiNote)
                    }
                }
            } label: {
                Text("Duke Activity Status Index").font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
            }
            .tint(PS.fg2)
            .padding(.horizontal, 14).padding(.vertical, 10)
            Hairline().padding(.leading, 14)
            toggleRow("Frail", "By a validated tool, such as the Clinical Frailty Scale; assessing frailty is reasonable at 65 or older, or younger with perceived frailty, before elevated-risk surgery (2024 AHA/ACC, class 2a)", bind(\.frail))
        }
        PatientGroup(title: "Cardiac evaluation", note: PatientFunctional.cardiacNote) {
            PatientChipRow(label: "Acute cardiac conditions") { PatientChips(options: PatientFunctional.activeCardiac, selection: bind(\.activeCardiac)) }
            let mods = PatientFunctional.riskModifiers(r)
            if !mods.isEmpty {
                line("Adds risk beyond the RCRI: " + mods.joined(separator: ", ") + ".")
                    .padding(.horizontal, 14).padding(.bottom, 4)
            }
            let step = PatientFunctional.cardiacStep(r)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(step.alert ? PS.accent : PS.fg)
                Text(step.detail).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            let advice = PatientFunctional.conditionAdvice(r)
            if !advice.isEmpty {
                Hairline().padding(.leading, 14)
                VStack(alignment: .leading, spacing: 8) {
                    Text("By condition").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
                    ForEach(Array(advice.enumerated()), id: \.offset) { _, a in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "arrow.turn.down.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.accent)
                            Text(a).font(PS.sys(size: 13)).foregroundStyle(PS.fg).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
        .id("cardiac")
        PatientGroup(title: "Risk scores and checks") {
            let prompts = PatientRules.prompts(r)
            ForEach(Array(prompts.enumerated()), id: \.element.id) { i, p in
                Button { onOpenRoute(p.route) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: p.done == nil ? "circle.dashed" : "checkmark.circle.fill")
                            .font(PS.sys(size: 16, weight: .semibold))
                            .foregroundStyle(p.done == nil ? PS.accent : PS.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.done ?? p.title).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                            Text(p.why).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < prompts.count - 1 { Hairline().padding(.leading, 42) }
            }
            if prompts.isEmpty {
                line("Add the age to see the adult scores.").padding(14)
            }
        }
    }

    // MARK: Airway and exam

    @ViewBuilder private var airway: some View {
        PatientGroup(title: "Mallampati", note: PatientFunctional.mallampatiHow) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(1...4, id: \.self) { m in
                    let on = r.mallampati == m
                    Button {
                        Haptics.light()
                        patient.update { $0.mallampati = on ? nil : m }
                    } label: {
                        VStack(spacing: 6) {
                            MallampatiDrawing(mclass: m).frame(maxWidth: 120)
                            Text("Class " + PatientRules.roman(m)).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                            Text(PatientAirway.mallampati(m)).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(on ? PS.accent.opacity(0.14) : PS.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? PS.accent : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(12)
        }
        PatientGroup(title: "Difficult-airway signs") {
            PatientChipRow(label: nil) { PatientChips(options: PatientAirway.signs, selection: bind(\.airwaySigns)) }
            PatientTextField(label: "Teeth", prompt: "Loose, capped, dentures", text: bind(\.dentition), focus: $focused)
            PatientTextField(label: "Airway notes", prompt: "Previous intubation notes, plan", text: bind(\.airwayNotes), focus: $focused)
        }
        let predictors = PatientRules.airwayPredictors(r)
        let mask = PatientAirway.maskRisk(r)
        if !mask.isEmpty {
            PatientGroup(title: "Mask ventilation", note: "Langeron O, et al. Anesthesiology 2000 (difficult); Kheterpal S, et al. Anesthesiology 2009 (impossible).") {
                ForEach(Array(mask.enumerated()), id: \.offset) { i, m in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: m.alert ? "exclamationmark.triangle.fill" : "circle")
                            .font(PS.sys(size: 12, weight: .semibold))
                            .foregroundStyle(m.alert ? PS.accent : PS.fg3)
                        Text(m.text).font(PS.sys(size: 13.5)).foregroundStyle(m.alert ? PS.fg : PS.fg2).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    if i < mask.count - 1 { Hairline().padding(.leading, 14) }
                }
            }
            .id("mask")
        }
        if !predictors.isEmpty {
            line("Recorded predictors: " + predictors.joined(separator: "; ") + ". The ASA's 2022 guideline finds no single sign consistently more predictive than another.")
            toolButton("Open the airway guide", route: "airway")
        }
        PatientGroup(title: "Examination") {
            PatientTextField(label: "Heart, lungs and other findings", prompt: "e.g. regular rhythm, no murmur; clear lungs", text: bind(\.examNotes), focus: $focused)
        }
    }

    // MARK: Intraop

    @ViewBuilder private var intraop: some View {
        PatientGroup(title: "Airway") {
            PatientChipRow(label: "Mask ventilation") {
                PatientChoice(options: [(id: "easy", label: "Easy"), (id: "difficult", label: "Difficult"), (id: "none", label: "Not used")], selection: bind(\.mask))
            }
            if r.mask != nil && r.mask != "none" {
                PatientChipRow(label: "Grade (Han)") {
                    PatientChoice(options: PatientAirway.maskGrades.map { (id: $0.id, label: $0.label) },
                                  selection: Binding(get: { patient.record.maskGrade.map { String($0) } }, set: { v in patient.update { $0.maskGrade = v.flatMap { Int($0) } } }))
                }
                if let g = r.maskGrade, let d = PatientAirway.maskGrades.first(where: { $0.id == String(g) }) {
                    line("Grade " + d.label + ": " + d.detail.lowercased() + ".")
                        .padding(.horizontal, 14).padding(.bottom, 6)
                }
            }
            if r.mask == "difficult" {
                PatientTextField(label: "What made it difficult", prompt: "Two hands, oral airway, what worked", text: bind(\.maskNote), focus: $focused)
            }
            PatientChipRow(label: "Supraglottic airway") {
                PatientChoice(options: [(id: "easy", label: "Easy"), (id: "difficult", label: "Difficult"), (id: "none", label: "Not used")], selection: bind(\.sga))
            }
            if r.sga == "difficult" {
                PatientTextField(label: "What made it difficult", prompt: "Device and size, leak, attempts, what worked", text: bind(\.sgaNote), focus: $focused)
            }
            PatientChipRow(label: "Intubation") {
                PatientChoice(options: [(id: "easy", label: "Easy"), (id: "difficult", label: "Difficult"), (id: "none", label: "Not intubated")], selection: bind(\.intubation))
            }
            if r.intubation == "difficult" {
                PatientTextField(label: "What made it difficult", prompt: "View, adjuncts, what worked", text: bind(\.intubationNote), focus: $focused)
            }
            PatientChipRow(label: "Device") {
                PatientChoice(options: PatientCatalog.devices.map { (id: $0, label: $0) }, selection: bind(\.airwayDevice))
            }
            PatientChipRow(label: "Laryngeal view (Cormack–Lehane)") {
                PatientChoice(options: PatientCatalog.grades.map { (id: $0, label: $0) }, selection: bind(\.laryngoscopyGrade))
            }
            if let g = r.laryngoscopyGrade, let d = PatientCatalog.gradeDetail(g) {
                line("Grade " + g + ": " + d.lowercased() + (g == "3" || g == "4" ? " (difficult laryngoscopy)." : "."))
                    .padding(.horizontal, 14).padding(.bottom, 6)
            }
            Stepper(value: Binding(get: { patient.record.attempts ?? 0 }, set: { v in patient.update { $0.attempts = v > 0 ? v : nil } }), in: 0...9) {
                Text("Attempts: " + (r.attempts.map { String($0) } ?? "not recorded")).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            PatientTextField(label: "Tube", prompt: "e.g. 7.5 ETT, 23 cm at the lip", text: bind(\.tube), focus: $focused)
            PatientChipRow(label: "At handoff") {
                PatientChoice(options: PatientCatalog.airwayAtEnd, selection: bind(\.airwayAtEnd))
            }
            if r.airwayAtEnd == "intubated" {
                PatientTextField(label: "Ventilation", prompt: "e.g. VC 450 × 14, PEEP 8, FiO₂ 0.5", text: bind(\.ventilation), focus: $focused)
            }
        }
        if PatientSummary.difficultAirway(r) {
            PatientGroup(title: "Difficult-airway follow-up", note: "ASA 2022: tell the patient or a responsible person, document the nature of the difficulty and what worked, and advise registering with an alert service.") {
                ForEach(Array(PatientSummary.followUp.enumerated()), id: \.element.id) { i, f in
                    toggleRow(f.label, nil, Binding(get: { patient.record.airwayFollowUp.contains(f.id) }, set: { on in patient.update { if on { $0.airwayFollowUp.insert(f.id) } else { $0.airwayFollowUp.remove(f.id) } } }))
                    if i < PatientSummary.followUp.count - 1 { Hairline().padding(.leading, 14) }
                }
            }
        }
        PatientGroup(title: "Lines") {
            ForEach(r.lines) { l in
                lineEditor(l)
                Hairline().padding(.leading, 14)
            }
            Button { patient.update { $0.lines.append(PatientLine()) } } label: { Label("Add line", systemImage: "plus.circle") }
                .font(PS.sys(size: 14, weight: .semibold)).buttonStyle(.borderless).tint(PS.accent)
                .padding(14)
        }
        PatientGroup(title: "Regional and neuraxial") {
            ForEach(r.regional) { b in
                blockEditor(b)
                Hairline().padding(.leading, 14)
            }
            Button { patient.update { $0.regional.append(PatientRegional()) } } label: { Label("Add block", systemImage: "plus.circle") }
                .font(PS.sys(size: 14, weight: .semibold)).buttonStyle(.borderless).tint(PS.accent)
                .padding(14)
        }
        PatientGroup(title: "Infusions") {
            ForEach(r.infusions) { inf in
                infusionEditor(inf)
                Hairline().padding(.leading, 14)
            }
            Button { patient.update { $0.infusions.append(PatientInfusion()) } } label: { Label("Add infusion", systemImage: "plus.circle") }
                .font(PS.sys(size: 14, weight: .semibold)).buttonStyle(.borderless).tint(PS.accent)
                .padding(14)
        }
        PatientGroup(title: "Fluids and blood") {
            ForEach(Array(PatientCatalog.fluids.enumerated()), id: \.element.id) { i, fl in
                PatientNumberField(label: fl.label, unit: fl.unit, value: entry(\.fluids, fl.id), focus: $focused)
                if i < PatientCatalog.fluids.count - 1 { Hairline().padding(.leading, 14) }
            }
            PatientTextField(label: "Factor concentrates and other products", prompt: "e.g. fibrinogen concentrate 2 g; PCC", text: bind(\.factors), focus: $focused)
        }
        PatientGroup(title: "Medications and interventions") {
            PatientTextField(label: "Notable medications and interventions", prompt: "Antibiotic and time, steroids, TXA, reversal, positioning", text: bind(\.medsGiven), focus: $focused)
        }
        PatientGroup(title: "Events") {
            toggleRow("No notable events", nil, bind(\.noEvents))
            if !r.noEvents {
                PatientTextField(label: "What happened", prompt: "Hypotension, arrhythmia, bronchospasm, bleeding…", text: bind(\.events), focus: $focused)
            }
        }
        PatientGroup(title: "Echo findings") {
            PatientChipRow(label: "Add a finding") {
                WrapLayout(spacing: 7) {
                    ForEach(PatientFunctional.echoPhrases, id: \.self) { phrase in
                        Button {
                            patient.update { $0.echo = $0.echo.isEmpty ? phrase : $0.echo + "; " + phrase }
                        } label: {
                            Text(phrase).font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg2)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(PS.surface2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            PatientTextField(label: "Summary", prompt: "LV and RV function, valves, effusion, new wall-motion changes", text: bind(\.echo), focus: $focused)
        }
    }

    private func lineEditor(_ l: PatientLine) -> some View {
        let idx = r.lines.firstIndex { $0.id == l.id }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    ForEach(PatientLine.kinds, id: \.self) { k in
                        Button(k) { if let i = idx { patient.update { $0.lines[i].kind = k } } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(l.kind).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                    }
                }
                Spacer()
                Button(role: .destructive) { if let i = idx { patient.update { $0.lines.remove(at: i) } } } label: { Image(systemName: "trash").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this line")
            }
            HStack(spacing: 8) {
                TextField("Size", text: Binding(get: { idx.map { patient.record.lines[$0].size } ?? "" }, set: { v in if let i = idx { patient.update { $0.lines[i].size = v } } }))
                    .focused($focused)
                    .padding(8).background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(width: 90)
                TextField("Site", text: Binding(get: { idx.map { patient.record.lines[$0].site } ?? "" }, set: { v in if let i = idx { patient.update { $0.lines[i].site = v } } }))
                    .focused($focused)
                    .padding(8).background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .font(PS.sys(size: 14))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func blockEditor(_ b: PatientRegional) -> some View {
        let idx = r.regional.firstIndex { $0.id == b.id }
        let names = (refs.bundle?.regional?.blocks ?? []).map(\.name) + ["Spinal", "Epidural", "Combined spinal-epidural"]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    ForEach(names, id: \.self) { n in
                        Button(n) { if let i = idx { patient.update { $0.regional[i].technique = n } } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(b.technique.isEmpty ? "Choose the technique" : b.technique).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(b.technique.isEmpty ? PS.accent : PS.fg).multilineTextAlignment(.leading)
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                    }
                }
                Spacer()
                Button(role: .destructive) { if let i = idx { patient.update { $0.regional.remove(at: i) } } } label: { Image(systemName: "trash").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this block")
            }
            PatientChoice(options: [(id: "Left", label: "Left"), (id: "Right", label: "Right"), (id: "Bilateral", label: "Bilateral"), (id: "Midline", label: "Midline")],
                          selection: Binding(get: { idx.flatMap { i in patient.record.regional[i].side.isEmpty ? nil : patient.record.regional[i].side } }, set: { v in if let i = idx { patient.update { $0.regional[i].side = v ?? "" } } }))
            TextField("Drug, concentration and volume", text: Binding(get: { idx.map { patient.record.regional[$0].drug } ?? "" }, set: { v in if let i = idx { patient.update { $0.regional[i].drug = v } } }), axis: .vertical)
                .focused($focused)
                .font(PS.sys(size: 14))
                .padding(8).background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Toggle("Catheter left in", isOn: Binding(get: { idx.map { patient.record.regional[$0].catheter } ?? false }, set: { v in if let i = idx { patient.update { $0.regional[i].catheter = v } } }))
                .font(PS.sys(size: 14)).tint(PS.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func infusionEditor(_ inf: PatientInfusion) -> some View {
        let idx = r.infusions.firstIndex { $0.id == inf.id }
        let names = (refs.bundle?.infusions?.groups ?? []).flatMap { $0.drugs.map(\.name) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    ForEach(names, id: \.self) { n in
                        Button(n) { if let i = idx { patient.update { $0.infusions[i].drug = n } } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(inf.drug.isEmpty ? "Choose the drug" : inf.drug).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(inf.drug.isEmpty ? PS.accent : PS.fg).multilineTextAlignment(.leading)
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                    }
                }
                Spacer()
                Button(role: .destructive) { if let i = idx { patient.update { $0.infusions.remove(at: i) } } } label: { Image(systemName: "trash").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this infusion")
            }
            TextField("Rate", text: Binding(get: { idx.map { patient.record.infusions[$0].rate } ?? "" }, set: { v in if let i = idx { patient.update { $0.infusions[i].rate = v } } }))
                .focused($focused)
                .font(PS.sys(size: 14))
                .padding(8).background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: Plan

    @ViewBuilder private var plan: some View {
        PatientGroup(title: "Disposition") {
            PatientChipRow(label: nil) {
                PatientChoice(options: PatientCatalog.dispositions.map { (id: $0, label: $0) }, selection: bind(\.disposition))
            }
        }
        PatientGroup(title: "Pain plan") {
            PatientTextField(label: "Analgesia", prompt: "Blocks, catheters, multimodal, PCA", text: bind(\.painPlan), focus: $focused)
        }
        PatientGroup(title: "Monitoring") {
            PatientTextField(label: "When to call", prompt: "e.g. SBP under 90, SpO₂ under 92%, urine under 0.5 mL/kg/h", text: bind(\.callIf), focus: $focused)
        }
        PatientGroup(title: "To do and concerns") {
            PatientTextField(label: "For the next team", prompt: "Labs to check, antibiotic redosing, CPAP, glucose, drains", text: bind(\.todos), focus: $focused)
        }
    }
}
