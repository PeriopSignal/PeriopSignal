import SwiftUI

/// The editors behind My Patient's cards.
enum PatientEditor: Hashable {
    case details, procedure, demographics, history, system(String), medications, assessment, airway, intraop, plan
    /// One part of the intraoperative record: "airway", "lines", "regional", "infusions", "fluids", "labs", "meds", "events",
    /// "echo", "considerations".
    case intraopPart(String)
    /// The Studies: "ecg", "echo" (preoperative), "lhc", "rhc", "tee", "carotid", "radial", "pft"; and the surgical history.
    case workup(String)
    /// The lines and devices on the diagram: "preop" (on arrival), "support" (mechanical support), "intraop".
    case devices(String)

    var title: String {
        switch self {
        case .details: return "Patient"
        case .procedure: return "Procedure"
        case .demographics: return "Demographics"
        case .history: return "History"
        case .system(let id): return PatientCatalog.allSystems.first { $0.id == id }?.name ?? "System"
        case .medications: return "Medications & Allergies"
        case .assessment: return "Assessment"
        case .airway: return "Airway"
        case .intraop: return "Intraop"
        case .plan: return "Plan"
        case .intraopPart(let id): return PatientEditor.intraopParts.first { $0.id == id }?.title ?? "Intraop"
        case .workup(let id): return PatientEditor.workups.first { $0.id == id }?.title ?? "Workup"
        case .devices(let p): return p == "support" ? "Mechanical Support" : "Lines & Devices"
        }
    }

    var icon: String {
        switch self {
        case .details: return "person"
        case .procedure: return "scissors"
        case .demographics: return "person"
        case .history: return "list.bullet.clipboard"
        case .system(let id): return PatientCatalog.allSystems.first { $0.id == id }?.icon ?? "circle"
        case .medications: return "pills"
        case .assessment: return "gauge.with.dots.needle.33percent"
        case .airway: return "mouth"
        case .intraop: return "waveform.path.ecg.rectangle"
        case .plan: return "arrow.right.circle"
        case .intraopPart(let id): return PatientEditor.intraopParts.first { $0.id == id }?.icon ?? "waveform.path.ecg.rectangle"
        case .workup(let id): return PatientEditor.workups.first { $0.id == id }?.icon ?? "waveform.path.ecg"
        case .devices(let p): return p == "support" ? "heart.circle" : "figure.stand"
        }
    }

    /// The compact quick-add bar at the top of the page (1.8.1): the intraoperative pages read the line as the
    /// Intraoperative tab does (drips to the case's infusions, blood, fluids, the airway course); the others as the
    /// Preoperative tab.
    var quickAddPlace: QuickAddPlace {
        switch self {
        case .intraop, .intraopPart: return .editor(intraop: true)
        case .devices(let p): return .editor(intraop: p == "intraop")
        default: return .editor(intraop: false)
        }
    }

    static let intraopParts: [(id: String, title: String, icon: String)] = [
        ("airway", "Airway", "mouth"), ("lines", "Lines", "syringe"), ("regional", "Regional & Neuraxial", "figure.flexibility"),
        ("infusions", "Infusions", "ivfluid.bag"), ("fluids", "Fluids & Blood", "drop"), ("labs", "Labs", "testtube.2"),
        ("meds", "Medications & Interventions", "pills"), ("events", "Events", "exclamationmark.triangle"),
        ("echo", "Echo Findings", "waveform.path.ecg.rectangle"), ("considerations", "Major Considerations", "exclamationmark.bubble"),
    ]
    static let workups: [(id: String, title: String, icon: String)] = [
        ("surgeries", "Past Surgical History", "scissors"), ("ecg", "ECG", "waveform.path.ecg"), ("echo", "Echo Findings", "heart.text.square"),
        ("lhc", "Left Heart Catheterization", "heart"), ("rhc", "Right Heart Catheterization", "heart.circle"), ("intrathoracic", "Previous Intrathoracic Surgery", "lungs"),
        ("anesthetic", "Anesthetic Complications", "exclamationmark.shield"), ("labs", "Labs", "testtube.2"),
        ("tee", "TEE Screen", "exclamationmark.triangle"), ("carotid", "Carotid Ultrasound", "waveform.path"),
        ("radial", "Radial Artery Ultrasound", "hand.raised"), ("pft", "Pulmonary Function Tests", "lungs"),
    ]
}

struct PatientEditorView: View {
    @Environment(PatientStore.self) var patient
    @Environment(ReferenceStore.self) var refs
    var editor: PatientEditor
    var onOpenRoute: (String) -> Void
    /// Home Screen–style editing of this page's lists (procedures, operations, infusions): long-press to wobble.
    @State var wobbling = false
    /// The number field typing, by its id in `numberOrder`: Previous and Next on the keyboard move it.
    @FocusState private var numberFocus: String?
    /// The grey shield's "No patient identifiers" explanation is open.
    @State private var showIdentifiers = false

    var r: PatientRecord { patient.record }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Type-to-fill on every page (1.8.1): the same bar as the tabs', compact, filling the whole record.
                    QuickAddBar(place: editor.quickAddPlace)
                    switch editor {
                    case .details: details
                    case .procedure: procedureEditor
                    case .demographics: demographicsEditor
                    case .history: history
                    case .system(let id): system(id)
                    case .medications: medications
                    case .assessment: assessment
                    case .airway: airway
                    case .intraop: intraop
                    case .plan: plan
                    case .intraopPart(let id): intraopPart(id)
                    case .workup(let id): workup(id)
                    case .devices(let p): PatientDevicesEditor(phase: p == "intraop" ? .intraop : .preop, supportOnly: p == "support")
                    }
                    DoneFooter().padding(.top, 4).id("done")
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .onAppear {
                #if DEBUG
                // Screenshot runs: -ps.patient.scroll cardiac | mask scrolls to that group; -ps.patient.focus main.k
                // starts typing in that number field (the keyboard's Previous / Next / Done).
                let a = LaunchSeed.string("ps.patient.scroll")
                if !a.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo(a, anchor: .top) }
                }
                // -ps.patient.addproc "TKA" adds that procedure on the Procedure page (a sided one without its side).
                let add = LaunchSeed.string("ps.patient.addproc")
                if editor == .procedure, !add.isEmpty, !patient.record.procedures.contains(where: \.needsSide) {
                    patient.update(discrete: true) { $0.setProcedures($0.procedures + PlannedProcedure.parse(add)) }
                }
                let f = LaunchSeed.string("ps.patient.focus")
                if !f.isEmpty {
                    // Again, from scratch, in case a slow launch's push dropped it while the focus still reads as set
                    // (runs 209 and 210: 177, then 171, without the keyboard).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { numberFocus = f }
                    for delay in [2.8, 4.4] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            numberFocus = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { numberFocus = f }
                        }
                    }
                }
                #endif
            }
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(editor.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("No patient identifiers", isPresented: $showIdentifiers) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(NoIdentifiersBanner.warning)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                // In a run of number fields (labs, vitals): Previous and Next, in screen order, keep the number pad up.
                if let i = numberFocus.flatMap({ numberOrder.firstIndex(of: $0) }) {
                    Button { moveFocus(i - 1) } label: {
                        HStack(spacing: 3) { Image(systemName: "chevron.up"); Text("Previous") }
                    }
                    .disabled(i == 0)
                    .accessibilityLabel("Previous field")
                    Button { moveFocus(i + 1) } label: {
                        HStack(spacing: 3) { Image(systemName: "chevron.down"); Text("Next") }
                    }
                    .disabled(i + 1 >= numberOrder.count)
                    .accessibilityLabel("Next field")
                }
                Spacer()
                Button("Done") { numberFocus = nil; Keyboard.dismiss() }
                    .fontWeight(.semibold)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                PatientUndoButton()
                // Where the age and the like are typed: the grey "No patient identifiers" shield.
                if editor == .details || editor == .demographics { NoIdentifiersShield(isPresented: $showIdentifiers) }
                if wobbling {
                    Button("Done") { Haptics.light(); withAnimation(.snappy) { wobbling = false } }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Number fields in order

    /// The number fields that Previous and Next walk on this page, in screen order.
    var numberOrder: [String] {
        switch editor {
        case .details, .demographics: return ["age", "height", "weight"] + PatientCatalog.vitals.map { "vital." + $0.id }
        case .workup("labs"): return labFieldOrder
        case .intraop, .intraopPart("labs"): return IntraopLabsEditor.fieldOrder(r)
        default: return []
        }
    }

    func chain(_ id: String) -> PatientFieldChain { PatientFieldChain(focus: $numberFocus, id: id) }

    private func moveFocus(_ i: Int) {
        let order = numberOrder
        guard order.indices.contains(i) else { return }
        numberFocus = order[i]
    }

    // MARK: Bindings

    func bind<T>(_ kp: WritableKeyPath<PatientRecord, T>) -> Binding<T> {
        Binding(get: { patient.record[keyPath: kp] }, set: { v in patient.update { $0[keyPath: kp] = v } })
    }

    func entry(_ kp: WritableKeyPath<PatientRecord, [String: Double]>, _ key: String) -> Binding<Double?> {
        Binding(get: { patient.record[keyPath: kp][key] }, set: { v in patient.update { $0[keyPath: kp][key] = v } })
    }

    func note(_ key: String) -> Binding<String> {
        Binding(get: { patient.record.systemNotes[key] ?? "" }, set: { v in patient.update { $0.systemNotes[key] = v.isEmpty ? nil : v } })
    }

    var sexChoice: Binding<String?> {
        Binding(get: { patient.record.sex?.rawValue }, set: { v in patient.update { $0.sex = v.flatMap { PatientSex(rawValue: $0) } } })
    }

    var urgencyChoice: Binding<String?> {
        Binding(get: { patient.record.urgency?.rawValue }, set: { v in patient.update { $0.urgency = v.flatMap { PatientUrgency(rawValue: $0) } } })
    }

    func line(_ text: String) -> some View {
        Text(text).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
    }

    /// A titled list of recommendations, each on its own line.
    func adviceList(_ title: String, _ items: [String], tint: Color) -> some View {
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

    func toggleRow(_ title: String, _ detail: String?, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: Binding(get: { isOn.wrappedValue }, set: { v in patient.markDiscrete(); isOn.wrappedValue = v })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                if let detail { Text(detail).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .tint(PS.accent)
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    func linkRow(_ title: String, _ detail: String, icon: String, value: PatientEditor) -> some View {
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

    func toolButton(_ title: String, route: String) -> some View {
        Button { onOpenRoute(route) } label: { Label(title, systemImage: "arrow.right.circle") }
            .buttonStyle(GhostButtonStyle())
    }

    // MARK: Patient

    @ViewBuilder private var details: some View {
        PatientGroup(title: "Patient", note: bodySizeNote) {
            PatientNumberField(label: "Age", unit: PatientRecord.ageFieldUnit(r.ageYears), value: bind(\.ageYears), chain: chain("age"))
            Hairline().padding(.leading, 14)
            PatientChipRow(label: "Sex") { PatientChoice(options: [(id: "male", label: "Male"), (id: "female", label: "Female")], selection: sexChoice) }
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "Height", unit: "cm", value: bind(\.heightCm), chain: chain("height"))
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "Weight", unit: "kg", value: bind(\.weightKg), chain: chain("weight"))
            let size = PatientSummary.bodyLine(r)
            if r.bmi != nil {
                Text(size).font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg2)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PS.surface2.opacity(0.5))
            }
        }
        PatientGroup(title: "Procedure", note: urgencyNote) {
            PatientTextField(label: "Procedure", prompt: "e.g. laparoscopic colectomy", text: bind(\.procedure))
            PatientChipRow(label: "Urgency") {
                PatientChoice(options: PatientUrgency.allCases.map { (id: $0.rawValue, label: $0.label) }, selection: urgencyChoice, tint: PS.accent)
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
                PatientNumberField(label: v.label, unit: v.unit, value: entry(\.vitals, v.id), chain: chain("vital." + v.id))
                if i < PatientCatalog.vitals.count - 1 { Hairline().padding(.leading, 14) }
            }
        }
    }

    // MARK: History

    @ViewBuilder private var history: some View {
        PatientGroup(title: nil) {
            toggleRow("No significant medical history", "Lets the tab suggest ASA I when nothing else is recorded", bind(\.noHistory))
        }
        PatientGroup(title: "Problems by system", note: "Tap a system to add its common problems; anything else goes under Other conditions.") {
            let systems = PatientCatalog.systems(for: r)
            ForEach(Array(systems.enumerated()), id: \.element.id) { i, s in
                // The expanding pages' words are lowercase for the summary; the row reads as a sentence.
                let picked = HistorySections.items(s, r).enumerated().map { $0.offset == 0 ? $0.element.prefix(1).uppercased() + $0.element.dropFirst() : $0.element }
                linkRow(s.name, picked.isEmpty ? "None recorded" : picked.joined(separator: "; "), icon: s.icon, value: .system(s.id))
                if i < systems.count - 1 { Hairline().padding(.leading, 50) }
            }
        }
        PatientGroup(title: nil) {
            PatientTextField(label: "Other conditions", prompt: "Anything not in the lists above, e.g. hereditary angioedema", text: bind(\.otherHistory))
        }
        PatientGroup(title: nil) {
            linkRow("Past surgical history", r.surgeries.isEmpty ? "Add operations, with the month and year" : r.capitalized.surgeries.map(\.text).joined(separator: "; "), icon: r.surgeries.isEmpty ? "plus.circle" : "scissors", value: .workup("surgeries"))
            Hairline().padding(.leading, 50)
            linkRow("Medications & allergies", medsSummary, icon: "pills", value: .medications)
            Hairline().padding(.leading, 50)
            linkRow("Anesthetic complications", PatientSummary.anestheticComplications(r)?.text ?? "None recorded; tap to add", icon: r.anesthesiaHistory.isEmpty && r.anesthesiaNotes.isEmpty ? "plus.circle" : "exclamationmark.shield", value: .workup("anesthetic"))
        }
        PatientGroup(title: "Last intake", note: "Set time starts at midnight, the usual nothing-by-mouth instruction; change it to what the patient reports. The ASA fasting guidance is under Reference.") {
            intakeRow("Solids", bind(\.lastSolids))
            Hairline().padding(.leading, 14)
            intakeRow("Clear fluids", bind(\.lastClears))
        }
        PatientGroup(title: nil) {
            let labs = PatientSummary.labsLine(r.capitalized)
            linkRow("Labs", labs?.text ?? "Add labs: CBC, chemistry, coagulation; cardiac, liver (MELD & CTP), thyroid", icon: labs == nil ? "plus.circle" : "testtube.2", value: .workup("labs"))
            if let liver = PatientSummary.liverLine(r) {
                Hairline().padding(.leading, 50)
                linkRow("Liver (MELD & CTP)", liver.text, icon: "cross.case", value: .workup("labs"))
            }
        }
    }

    var medsSummary: String {
        if r.nkda && r.medications.isEmpty { return "No known drug allergies" }
        let c = r.capitalized
        let parts = [r.nkda ? "NKDA" : (c.allergies.isEmpty ? "" : "Allergies: " + c.allergies), c.medications].filter { !$0.isEmpty }
        return parts.isEmpty ? "None recorded" : parts.joined(separator: " · ")
    }

    func intakeRow(_ title: String, _ date: Binding<Date?>) -> some View {
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
                Button("Set time") { date.wrappedValue = PatientRecord.npoMidnight() }
                    .font(PS.sys(size: 13.5, weight: .semibold))
                    .buttonStyle(.borderless)
                    .tint(PS.accent)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    @ViewBuilder private func system(_ id: String) -> some View {
        if let s = PatientCatalog.allSystems.first(where: { $0.id == id }) {
            if id == "social" {
                PatientGroup(title: "Smoking") {
                    PatientChipRow(label: nil) {
                        PatientChoice(options: [(id: "never", label: "Never"), (id: "former", label: "Former"), (id: "current", label: "Current")], selection: bind(\.smoking))
                    }
                }
            }
            if HistorySections.sections(s.id) != nil {
                // Cardiovascular and Respiratory (1.8.1): expanding sections; Cardiovascular ends with its studies, the
                // same editors and data as Assessment.
                PatientHistorySectionsView(system: s)
                if s.id == "cv" { cvStudies }
            } else {
                PatientGroup(title: s.name, note: PatientCatalog.systemNote(s)) {
                    PatientChipRow(label: nil) {
                        PatientChips(options: s.problems.map(problemFlag), selection: bind(\.problems))
                    }
                    PatientTextField(label: "Details", prompt: "Severity, dates, devices, the last echo or stress test", text: note(s.id))
                }
            }
        }
    }

    /// The cardiac studies, as Assessment's Studies list them (ECG, echo, left and right heart cath).
    @ViewBuilder private var cvStudies: some View {
        PatientGroup(title: "Studies") {
            linkRow("ECG", PatientSummary.ecgText(r) ?? "Add findings", icon: r.ecg.isEmpty && r.ecgNotes.isEmpty ? "plus.circle" : "waveform.path.ecg", value: .workup("ecg"))
            Hairline().padding(.leading, 50)
            linkRow("Echo", r.echoFindings.isEmpty ? "Add findings" : r.capitalized.echoFindings.summary, icon: r.echoFindings.isEmpty ? "plus.circle" : "heart.text.square", value: .workup("echo"))
            Hairline().padding(.leading, 50)
            linkRow("Left heart cath", r.lhc.isEmpty ? "Add dominance and stenoses" : r.capitalized.lhc.summary, icon: r.lhc.isEmpty ? "plus.circle" : "heart", value: .workup("lhc"))
            Hairline().padding(.leading, 50)
            linkRow("Right heart cath", PatientSummary.rhcText(r) ?? "Add pressures and cardiac output", icon: r.rhc.isEmpty ? "plus.circle" : "heart.circle", value: .workup("rhc"))
        }
        .id("cvstudies")
    }

    func problemFlag(_ p: PatientProblem) -> PatientFlag {
        PatientFlag(p.id, p.label, PatientRules.asaLevel(p, r).map { "ASA " + PatientRules.roman($0) + " example" })
    }

    @ViewBuilder private var medications: some View {
        PatientGroup(title: "Allergies") {
            toggleRow("No known drug allergies", nil, bind(\.nkda))
            if !r.nkda {
                PatientTextField(label: "Allergies & reactions", prompt: "e.g. penicillin (rash); latex", text: bind(\.allergies))
            }
        }
        PatientGroup(title: "Medications") {
            PatientTextField(label: "Home medications", prompt: "Drug, dose, last taken", text: bind(\.medications))
            PatientChipRow(label: "Flags") { PatientChips(options: PatientCatalog.medFlags, selection: bind(\.medFlags)) }
        }
        currentInfusionsGroup
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
        // One ⓘ on the group title holds what used to be the card's own "Explanation & Evidence" rows too (1.8.1).
        PatientGroup(title: "ASA physical status", note: asaNote) {
            if let s = PatientRules.asaSuggestion(r) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggested: " + s.label).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                    AsaReasonTable(reasons: s.reasons, top: s.level)
                    if r.asaClass != s.level {
                        Button("Use ASA " + PatientRules.roman(s.level)) { patient.update(discrete: true) { $0.asaClass = s.level } }
                            .buttonStyle(CapsuleButtonStyle())
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                Hairline().padding(.leading, 14)
            }
            PatientChipRow(label: "Class") {
                PatientChoice(options: (1...6).map { (id: String($0), label: "ASA " + PatientRules.roman($0)) },
                              selection: Binding(get: { patient.record.asaClass.map { String($0) } }, set: { v in patient.update { $0.asaClass = v.flatMap { Int($0) } } }))
            }
            PatientInfoToggle(title: "Emergency (E)", info: "Delay would significantly increase the threat to life or body part",
                              isOn: Binding(get: { patient.record.asaE ?? patient.record.emergency }, set: { v in patient.update { $0.asaE = v } }))
                .padding(.bottom, 4)
        }
        PatientCodeStatusGroup()
        PatientGroup(title: "Functional capacity", note: PatientFunctional.metsNote) {
            PatientChipRow(label: nil) {
                PatientChoice(options: [(id: "ge4", label: "4 METs or more"), (id: "lt4", label: "Under 4 METs"), (id: "unknown", label: "Unknown")], selection: bind(\.mets))
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(PatientFunctional.dasiItems) { it in
                        Toggle(isOn: Binding(get: { patient.record.dasi.contains(it.id) }, set: { on in patient.update(discrete: true) { if on { $0.dasi.insert(it.id) } else { $0.dasi.remove(it.id) } } })) {
                            Text(it.label).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                        }
                        .tint(PS.accent)
                        .padding(.vertical, 6)
                    }
                    if let d = PatientFunctional.dasi(r) {
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
            Hairline().padding(.leading, 14)
            PatientInfoToggle(title: "Frail", detail: "By a validated tool",
                              info: "Use a validated tool, such as the Clinical Frailty Scale. Assessing frailty is reasonable at 65 or older, or younger with perceived frailty, before elevated-risk surgery (2024 AHA/ACC, class 2a).",
                              isOn: bind(\.frail))
                .padding(.bottom, 4)
        }
        // The guideline is for adults (2024 AHA/ACC §1.4, p e355): under 18 the symptoms and acute conditions are still
        // recorded, without the stepwise evaluation or its advice, as in the H&P (PatientSummary).
        PatientGroup(title: "Cardiac evaluation", note: r.isAdult ? PatientFunctional.cardiacNote : PatientFunctional.cardiacAdultOnly) {
            yesNoRow("Cardiac symptoms or signs", answer: \.cardiacSymptomsAnswer, chips: \.cardiacSymptoms, options: PatientFunctional.cardiacSymptomFlags)
            Hairline().padding(.leading, 14)
            yesNoRow("Acute cardiac conditions", answer: \.activeCardiacAnswer, chips: \.activeCardiac, options: PatientFunctional.activeCardiac)
            Hairline().padding(.leading, 14)
            let thoracic = r.allIntrathoracic
            linkRow("Previous intrathoracic surgery", thoracic.isEmpty ? "None recorded" : thoracic.map(\.text).joined(separator: "; "), icon: thoracic.isEmpty ? "plus.circle" : "lungs", value: .workup("intrathoracic"))
            if r.isAdult {
                Hairline().padding(.leading, 14)
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
                let branch = PatientFunctional.branchAdvice(r)
                if !branch.isEmpty {
                    Hairline().padding(.leading, 14)
                    adviceList("For this risk", branch, tint: PS.fg3)
                }
                let advice = PatientFunctional.conditionAdvice(r)
                if !advice.isEmpty {
                    Hairline().padding(.leading, 14)
                    adviceList("By condition", advice, tint: PS.accent)
                }
            }
        }
        .id("cardiac")
        studiesGroup
        PatientGroup(title: "Risk scores & checks") {
            let prompts = PatientRules.prompts(r) + PatientTEE.prompts(r)
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

    /// The ASA card's explanations, for its title's ⓘ: how the suggestion works, then (a child with nothing to suggest
    /// from) where to tick problems, then the chosen class's definition; each was a row of its own before 1.8.1.
    var asaNote: String {
        var parts = ["The suggestion is the highest class among the ASA's published examples (adult, pediatric under 18, and obstetric) that match what is recorded; the class is a clinical judgment, so it counts only once you choose it."]
        if PatientRules.asaSuggestion(r) == nil && r.isChild {
            parts.append("Tick problems under History, including the Pediatric list, or mark no significant history, for a suggestion from the ASA's pediatric examples.")
        }
        if let c = r.asaClass {
            parts.append(PatientFunctional.asaDefinition(c) + (PatientFunctional.asaExampleLead(c).map { " " + $0 } ?? ""))
        }
        return parts.joined(separator: "\n\n")
    }

    /// The tests on file: the cardiac studies (unchanged from the cardiac evaluation, in its order), then the carotid
    /// and radial artery ultrasound and the pulmonary function tests.
    @ViewBuilder private var studiesGroup: some View {
        PatientGroup(title: "Studies") {
            linkRow("ECG", PatientSummary.ecgText(r) ?? "Add findings", icon: r.ecg.isEmpty && r.ecgNotes.isEmpty ? "plus.circle" : "waveform.path.ecg", value: .workup("ecg"))
            Hairline().padding(.leading, 50)
            linkRow("Echo", r.echoFindings.isEmpty ? "Add findings" : r.capitalized.echoFindings.summary, icon: r.echoFindings.isEmpty ? "plus.circle" : "heart.text.square", value: .workup("echo"))
            Hairline().padding(.leading, 50)
            teeLinkRow
            Hairline().padding(.leading, 50)
            linkRow("Left heart cath", r.lhc.isEmpty ? "Add dominance and stenoses" : r.capitalized.lhc.summary, icon: r.lhc.isEmpty ? "plus.circle" : "heart", value: .workup("lhc"))
            Hairline().padding(.leading, 50)
            linkRow("Right heart cath", PatientSummary.rhcText(r) ?? "Add pressures and cardiac output", icon: r.rhc.isEmpty ? "plus.circle" : "heart.circle", value: .workup("rhc"))
            Hairline().padding(.leading, 50)
            linkRow("Carotid ultrasound", r.carotid.isEmpty ? "Add findings" : r.capitalized.carotid.summary, icon: r.carotid.isEmpty ? "plus.circle" : "waveform.path", value: .workup("carotid"))
            Hairline().padding(.leading, 50)
            linkRow("Radial artery ultrasound", r.radial.isEmpty ? "Add findings" : r.capitalized.radial.summary, icon: r.radial.isEmpty ? "plus.circle" : "hand.raised", value: .workup("radial"))
            Hairline().padding(.leading, 50)
            linkRow("Pulmonary function tests", r.pft.isEmpty ? "Add results" : r.capitalized.pft.summary(copd: r.has("copd")), icon: r.pft.isEmpty ? "plus.circle" : "lungs", value: .workup("pft"))
        }
        .id("studies")
    }

    // MARK: Airway and exam

    @ViewBuilder private var airway: some View {
        currentAirwayGroup
        if r.arrivesWithAirway {
            // Why there is no exam here: behind the group title's ⓘ (1.8.1), not on a row between the cards.
            PatientGroup(title: "Airway notes", note: "With an ETT or a tracheostomy in place, the airway examination and the intraoperative airway course are not asked; record the previous intubation grade under Airway notes if you know it.") {
                PatientTextField(label: "Airway notes", prompt: "Previous intubation grade, how the ETT was placed, plan for extubation", text: bind(\.airwayNotes))
            }
        } else {
            airwayExam
        }
        if !r.examNotes.isEmpty {
            PatientGroup(title: "Examination") {
                PatientTextField(label: "Heart, lungs & other findings", prompt: "e.g. regular rhythm, no murmur; clear lungs", text: bind(\.examNotes))
            }
        }
    }

    @ViewBuilder private var airwayExam: some View {
        PatientGroup(title: nil) {
            PatientPresetRow(title: "Exam normal", caption: PatientAirway.normalExamCaption, applied: PatientAirway.isNormalExam(r)) {
                patient.update(discrete: true) { PatientAirway.applyNormalExam(&$0) }
            }
            if r.airwayExamReviewed {
                Hairline().padding(.leading, 14)
                toggleRow("Exam reviewed", "Mouth opening, thyromental distance and neck movement read as normal unless a sign below says otherwise", bind(\.airwayExamReviewed))
            }
        }
        .id("examnormal")
        PatientGroup(title: "Mallampati", note: PatientFunctional.mallampatiHow) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(1...4, id: \.self) { m in
                    let on = r.mallampati == m
                    Button {
                        Haptics.light()
                        patient.update(discrete: true) { $0.mallampati = on ? nil : m }
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
            PatientTextField(label: "Teeth", prompt: "Loose, capped, dentures", text: bind(\.dentition))
            PatientTextField(label: "Airway notes", prompt: "Previous intubation notes, plan", text: bind(\.airwayNotes))
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
            PatientInfoLine(text: "Recorded predictors: " + predictors.joined(separator: "; ") + ".",
                            info: "The ASA's 2022 guideline finds no single sign consistently more predictive than another.")
            toolButton("Open the airway guide", route: "airway")
        }
    }

    // MARK: Intraop

    @ViewBuilder private var intraop: some View {
        ForEach(PatientEditor.intraopParts, id: \.id) { part in intraopPart(part.id) }
    }

    @ViewBuilder func intraopPart(_ id: String) -> some View {
        switch id {
        case "airway": intraopAirway
        case "lines": intraopLines
        case "regional": intraopRegional
        case "infusions": intraopInfusions
        case "fluids": intraopFluids
        case "meds": intraopMeds
        case "events": intraopEvents
        case "echo": intraopEcho
        case "labs": IntraopLabsEditor(focus: $numberFocus)
        case "considerations": IntraopConsiderationsEditor()
        default: EmptyView()
        }
    }

    @ViewBuilder private var intraopAirway: some View {
        if r.arrivesWithAirway {
            PatientGroup(title: "Airway") {
                Text((r.currentAirwayText ?? "Airway secured") + " on arrival: no airway course to record.")
                    .font(PS.sys(size: 14)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            }
        } else {
            intraopAirwayCourse
        }
    }

    @ViewBuilder private var intraopAirwayCourse: some View {
        PatientGroup(title: "Airway") {
            PatientChipRow(label: "Mask ventilation") {
                PatientChoice(options: [(id: "easy", label: "Easy"), (id: "difficult", label: "Difficult"), (id: "none", label: "Not used")], selection: bind(\.mask))
            }
            // Each grade's definition: behind an ⓘ on its row's label (1.8.1), not on a row of its own.
            if r.mask != nil && r.mask != "none" {
                InfoChipRow(label: "Grade (Han)", info: maskGradeNote) {
                    PatientChoice(options: PatientAirway.maskGrades.map { (id: $0.id, label: $0.label) },
                                  selection: Binding(get: { patient.record.maskGrade.map { String($0) } }, set: { v in patient.update { $0.maskGrade = v.flatMap { Int($0) } } }))
                }
            }
            if r.mask == "difficult" {
                PatientTextField(label: "What made it difficult", prompt: "Two hands, oral airway, what worked", text: bind(\.maskNote))
            }
            PatientChipRow(label: "Supraglottic airway") {
                PatientChoice(options: [(id: "easy", label: "Easy"), (id: "difficult", label: "Difficult"), (id: "none", label: "Not used")], selection: bind(\.sga))
            }
            if r.sga == "difficult" {
                PatientTextField(label: "What made it difficult", prompt: "Device and size, leak, attempts, what worked", text: bind(\.sgaNote))
            }
            PatientChipRow(label: "Intubation") {
                PatientChoice(options: [(id: "easy", label: "Easy"), (id: "difficult", label: "Difficult"), (id: "none", label: "Not intubated")], selection: bind(\.intubation))
            }
            if r.intubation == "difficult" {
                PatientTextField(label: "What made it difficult", prompt: "View, adjuncts, what worked", text: bind(\.intubationNote))
            }
            PatientChipRow(label: "Device") {
                PatientChoice(options: PatientCatalog.devices.map { (id: $0, label: $0) }, selection: bind(\.airwayDevice))
            }
            InfoChipRow(label: "Laryngeal view (Cormack–Lehane)", info: laryngealGradeNote) {
                PatientChoice(options: PatientCatalog.grades.map { (id: $0, label: $0) }, selection: bind(\.laryngoscopyGrade))
            }
            Stepper(value: Binding(get: { patient.record.attempts ?? 0 }, set: { v in patient.update(discrete: true) { $0.attempts = v > 0 ? v : nil } }), in: 0...9) {
                Text("Attempts: " + (r.attempts.map { String($0) } ?? "not recorded")).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            PatientTextField(label: "Tube", prompt: "e.g. 7.5 ETT, 23 cm at the lip", text: bind(\.tube))
            PatientChipRow(label: "At handoff") {
                PatientChoice(options: PatientCatalog.airwayAtEnd, selection: bind(\.airwayAtEnd))
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
    }

    /// The chosen mask grade's definition, for the ⓘ on "Grade (Han)".
    var maskGradeNote: String? {
        guard let g = r.maskGrade, let d = PatientAirway.maskGrades.first(where: { $0.id == String(g) }) else { return nil }
        return "Grade " + d.label + ": " + d.detail.lowercased() + "."
    }

    /// The chosen laryngeal view's definition, for the ⓘ on "Laryngeal view (Cormack–Lehane)".
    var laryngealGradeNote: String? {
        guard let g = r.laryngoscopyGrade, let d = PatientCatalog.gradeDetail(g) else { return nil }
        return "Grade " + g + ": " + d.lowercased() + (g == "3" || g == "4" ? " (difficult laryngoscopy)." : ".")
    }

    @ViewBuilder private var intraopLines: some View {
        // A planned radial artery harvest and subclavian steal: where the lines and the cuff go, and any already on the
        // harvest arm (PatientStudies).
        studyCautions(PatientStudies.cautions(r).filter { $0.id.hasPrefix("harvest") || $0.id.hasPrefix("vertebral") })
        PatientDevicesEditor(phase: .intraop)
        if !r.lines.isEmpty { legacyLines }
    }

    /// Lines entered before the diagram (normally moved into devices when the patient opens).
    @ViewBuilder private var legacyLines: some View {
        PatientGroup(title: "Lines") {
            ForEach(r.lines) { l in
                lineEditor(l)
                Hairline().padding(.leading, 14)
            }
            Button { patient.update(discrete: true) { $0.lines.append(PatientLine()) } } label: { Label("Add line", systemImage: "plus.circle") }
                .font(PS.sys(size: 14, weight: .semibold)).buttonStyle(.borderless).tint(PS.accent)
                .padding(14)
        }
    }

    @ViewBuilder private var intraopRegional: some View {
        PatientGroup(title: "Regional & neuraxial") {
            ForEach(r.regional) { b in
                blockEditor(b)
                Hairline().padding(.leading, 14)
            }
            Button { patient.update(discrete: true) { $0.regional.append(PatientRegional()) } } label: { Label("Add block", systemImage: "plus.circle") }
                .font(PS.sys(size: 14, weight: .semibold)).buttonStyle(.borderless).tint(PS.accent)
                .padding(14)
        }
    }

    @ViewBuilder private var intraopInfusions: some View {
        if !r.homeInfusions.isEmpty && r.infusions.isEmpty {
            Button { patient.update(discrete: true) { $0.infusions = $0.homeInfusions.map { PatientInfusion(drug: $0.drug, rate: $0.rate) } } } label: {
                Label("Carry over the current infusions (" + r.homeInfusions.map(\.drug).filter { !$0.isEmpty }.joined(separator: ", ") + ")", systemImage: "arrow.down.circle")
                    // Wraps, unlike GhostButtonStyle's one line: two drug names ran the page wider than the screen (1.8.1).
                    .font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 15).padding(.vertical, 9)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PS.line2, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        PatientGroup(title: "Infusions") {
            // Typed in one line, as the quick-add bar takes them (1.8.1).
            InfusionTypeField(list: \.infusions)
            Hairline().padding(.leading, 14)
            ForEach(r.infusions) { inf in
                infusionEditor(inf)
                    .wobbleDelete($wobbling, label: inf.drug.isEmpty ? "infusion" : inf.drug) { patient.update(discrete: true) { $0.infusions.removeAll { $0.id == inf.id } } }
                Hairline().padding(.leading, 14)
            }
            WobbleDoneBar(editing: $wobbling)
            Button { patient.update(discrete: true) { $0.infusions.append(PatientInfusion()) } } label: { Label("Add infusion", systemImage: "plus.circle") }
                .font(PS.sys(size: 14, weight: .semibold)).buttonStyle(.borderless).tint(PS.accent)
                .padding(14)
        }
    }

    @ViewBuilder private var intraopFluids: some View {
        // Blood products have their own + and − (PatientIntraopExtras); so do crystalloid (a 1000 mL bag a tap) and
        // colloid (a 250 mL bottle), BloodProducts.fluidSteps. Blood loss and urine are typed.
        BloodProductsGroup()
        let typed = PatientCatalog.fluids.filter { !BloodProducts.ids.contains($0.id) }
        PatientGroup(title: "Fluids & output") {
            ForEach(Array(typed.enumerated()), id: \.element.id) { i, fl in
                if let step = BloodProducts.fluidSteps[fl.id] {
                    BloodStepperRow(label: fl.label, unit: fl.unit, step: step, limit: BloodProducts.fluidLimit, value: entry(\.fluids, fl.id))
                } else {
                    PatientNumberField(label: fl.label, unit: fl.unit, value: entry(\.fluids, fl.id))
                }
                if i < typed.count - 1 { Hairline().padding(.leading, 14) }
            }
            PatientTextField(label: "Factor concentrates & other products", prompt: "e.g. fibrinogen concentrate 2 g; PCC", text: bind(\.factors))
        }
        .id("fluidsOutput")
    }

    @ViewBuilder private var intraopMeds: some View {
        PatientGroup(title: "Medications & interventions") {
            PatientTextField(label: "Notable medications & interventions", prompt: "Antibiotic and time, steroids, TXA, reversal, positioning", text: bind(\.medsGiven))
        }
    }

    @ViewBuilder private var intraopEvents: some View {
        PatientGroup(title: "Events") {
            toggleRow("No notable events", nil, bind(\.noEvents))
            if !r.noEvents {
                PatientTextField(label: "What happened", prompt: "Hypotension, arrhythmia, bronchospasm, bleeding…", text: bind(\.events))
            }
        }
        // At the end of the case: extubated takes the ETT off the patient diagram.
        if r.arrivesWithAirway || r.intubation == "easy" || r.intubation == "difficult" || !r.tube.isEmpty {
            HStack(spacing: 10) {
                Button { withAnimation(.snappy) { patient.update(discrete: true) { $0.airwayAtEnd = "intubated" } } } label: {
                    Label("Remains intubated", systemImage: r.airwayAtEnd == "intubated" ? "checkmark.circle.fill" : "lungs")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(prominent: r.airwayAtEnd == "intubated"))
                Button { withAnimation(.snappy) { patient.update(discrete: true) { $0.airwayAtEnd = "extubated" } } } label: {
                    Label("Extubated", systemImage: r.airwayAtEnd == "extubated" ? "checkmark.circle.fill" : "wind")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(prominent: r.airwayAtEnd == "extubated"))
            }
            if r.airwayAtEnd == "intubated" {
                PatientGroup(title: nil) {
                    PatientTextField(label: "Ventilation", prompt: "e.g. VC 450 × 14, PEEP 8, FiO₂ 0.5", text: bind(\.ventilation))
                }
            }
        }
    }

    @ViewBuilder private var intraopEcho: some View {
        // The probe's safety first: one tap to the TEE screen from where the TEE is recorded.
        PatientGroup(title: nil) { teeLinkRow }
        EchoFindingsEditor(echo: bind(\.intraopEcho))
        PatientGroup(title: "Echo summary") {
            PatientChipRow(label: "Add a finding") {
                WrapLayout(spacing: 7) {
                    ForEach(PatientFunctional.echoPhrases, id: \.self) { phrase in
                        Button {
                            patient.update(discrete: true) { $0.echo = $0.echo.isEmpty ? phrase : $0.echo + "; " + phrase }
                        } label: {
                            Text(phrase).font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg2)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(PS.surface2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            PatientTextField(label: "Summary", prompt: "LV and RV function, valves, effusion, new wall-motion changes", text: bind(\.echo))
        }
    }

    private func lineEditor(_ l: PatientLine) -> some View {
        let idx = r.lines.firstIndex { $0.id == l.id }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    ForEach(PatientLine.kinds, id: \.self) { k in
                        Button(k) { if let i = idx { patient.update(discrete: true) { $0.lines[i].kind = k } } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(l.kind).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                    }
                }
                Spacer()
                Button(role: .destructive) { if let i = idx { patient.update(discrete: true) { $0.lines.remove(at: i) } } } label: { Image(systemName: "trash").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this line")
            }
            HStack(spacing: 8) {
                FocusBox { f in
                    TextField("Size", text: Binding(get: { idx.map { patient.record.lines[$0].size } ?? "" }, set: { v in if let i = idx { patient.update { $0.lines[i].size = v } } }))
                        .focused(f)
                        .padding(8).background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .frame(width: 90)
                FocusBox { f in
                    TextField("Site", text: Binding(get: { idx.map { patient.record.lines[$0].site } ?? "" }, set: { v in if let i = idx { patient.update { $0.lines[i].site = v } } }))
                        .focused(f)
                        .padding(8).background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
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
                        Button(n) { if let i = idx { patient.update(discrete: true) { $0.regional[i].technique = n } } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(b.technique.isEmpty ? "Choose the technique" : b.technique).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(b.technique.isEmpty ? PS.accent : PS.fg).multilineTextAlignment(.leading)
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                    }
                }
                Spacer()
                Button(role: .destructive) { if let i = idx { patient.update(discrete: true) { $0.regional.remove(at: i) } } } label: { Image(systemName: "trash").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this block")
            }
            PatientChoice(options: [(id: "Left", label: "Left"), (id: "Right", label: "Right"), (id: "Bilateral", label: "Bilateral"), (id: "Midline", label: "Midline")],
                          selection: Binding(get: { idx.flatMap { i in patient.record.regional[i].side.isEmpty ? nil : patient.record.regional[i].side } }, set: { v in if let i = idx { patient.update { $0.regional[i].side = v ?? "" } } }))
            FocusBox { f in
                TextField("Drug, concentration and volume", text: Binding(get: { idx.map { patient.record.regional[$0].drug } ?? "" }, set: { v in if let i = idx { patient.update { $0.regional[i].drug = v } } }), axis: .vertical)
                    .focused(f)
                    .font(PS.sys(size: 14))
                    .padding(8).background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Toggle("Catheter left in", isOn: Binding(get: { idx.map { patient.record.regional[$0].catheter } ?? false }, set: { v in if let i = idx { patient.update(discrete: true) { $0.regional[i].catheter = v } } }))
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
                        Button(n) { if let i = idx { patient.update(discrete: true) { $0.infusions[i].drug = n } } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(inf.drug.isEmpty ? "Choose the drug" : inf.drug).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(inf.drug.isEmpty ? PS.accent : PS.fg).multilineTextAlignment(.leading)
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                    }
                }
                Spacer()
                Button(role: .destructive) { if let i = idx { patient.update(discrete: true) { $0.infusions.remove(at: i) } } } label: { Image(systemName: "trash").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this infusion")
            }
            FocusBox { f in
                TextField("Rate", text: Binding(get: { idx.map { patient.record.infusions[$0].rate } ?? "" }, set: { v in if let i = idx { patient.update { $0.infusions[i].rate = v } } }))
                    .focused(f)
                    .font(PS.sys(size: 14))
                    .padding(8).background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
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
            PatientTextField(label: "Analgesia", prompt: "Blocks, catheters, multimodal, PCA", text: bind(\.painPlan))
        }
        PatientGroup(title: "Monitoring") {
            PatientTextField(label: "When to call", prompt: "e.g. SBP under 90, SpO₂ under 92%, urine under 0.5 mL/kg/h", text: bind(\.callIf))
        }
        PatientGroup(title: "To do & concerns") {
            PatientTextField(label: "For the next team", prompt: "Labs to check, antibiotic redosing, CPAP, glucose, drains", text: bind(\.todos))
        }
    }
}
