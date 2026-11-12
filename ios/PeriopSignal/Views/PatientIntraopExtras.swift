import SwiftUI

// MARK: - Intraoperative extras: lab sets, blood products with + and −, major considerations; and code status
//
// The record's fields, ranges, lines and sources are in Shared/PatientIntraop.swift and
// Shared/PatientCodeStatus.swift.

private extension PatientStore {
    func binding<T>(_ kp: WritableKeyPath<PatientRecord, T>) -> Binding<T> {
        Binding(get: { self.record[keyPath: kp] }, set: { v in self.update { $0[keyPath: kp] = v } })
    }
}

// MARK: Labs

/// The intraoperative lab sets: the newest open, the earlier ones folded under their summary.
struct IntraopLabsEditor: View {
    @Environment(PatientStore.self) private var patient
    /// The page's Previous / Next focus: the newest set's fields take part in it.
    var focus: FocusState<String?>.Binding? = nil

    /// The newest set's fields, top to bottom: the order Previous and Next walk ("iop.glucose", then the gas, "iop.ph").
    /// 1.12: the glucose has its own section above the blood gas, and an ScvO₂ or SvO₂ sample has its saturation first.
    static func fieldOrder(_ r: PatientRecord) -> [String] {
        guard let newest = IntraopLabs.newestFirst(r.intraopLabs).first else { return [] }
        return IntraopLabs.tests(IntraopLabs.pageOrder(newest.gasType), type: newest.gasType).map { "iop." + $0.key }
    }

    private var r: PatientRecord { patient.record }

    /// Newest first; a set just added (empty) comes first too.
    private var sets: [IntraopLabSet] { IntraopLabs.newestFirst(r.intraopLabs) }

    var body: some View {
        Button {
            withAnimation(.snappy) { patient.update(discrete: true) { $0.intraopLabs.append(IntraopLabSet(time: Date())) } }
        } label: {
            Label(r.intraopLabs.isEmpty ? "Add a lab set" : "Add a new set", systemImage: "plus.circle")
        }
        .buttonStyle(GhostButtonStyle())
        if r.intraopLabs.isEmpty {
            Text("Blood gas and coagulation as they come back, each set with its time; the intraoperative card and the handoff show the most recent, abnormal values in bold red.")
                .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
        }
        ForEach(Array(sets.enumerated()), id: \.element.id) { i, s in
            if i == 0 {
                setEditor(s, chained: true)
            } else {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 16) { setEditor(s) }.padding(.top, 8)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Earlier set" + (s.time.map { ", " + PatientSummary.time($0) } ?? "")).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                        if let l = IntraopLabs.line(s, sex: r.sex) { PatientLineText(line: PatientSummary.Line(nil, l.text, marks: l.marks, spoken: l.spoken)) }
                    }
                }
                .tint(PS.fg2)
                .padding(14)
                .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            }
        }
        EvidenceNote(IntraopLabs.sources)
    }

    private func index(_ id: UUID) -> Int? { patient.record.intraopLabs.firstIndex { $0.id == id } }

    private func value(_ id: UUID, _ key: String) -> Binding<Double?> {
        Binding(get: { index(id).flatMap { patient.record.intraopLabs[$0].values[key] } },
                set: { v in if let i = index(id) { patient.update { $0.intraopLabs[i].values[key] = v } } })
    }

    private func text(_ id: UUID, _ kp: WritableKeyPath<IntraopLabSet, String>) -> Binding<String> {
        Binding(get: { index(id).map { patient.record.intraopLabs[$0][keyPath: kp] } ?? "" },
                set: { v in if let i = index(id) { patient.update { $0.intraopLabs[i][keyPath: kp] = v } } })
    }

    /// The set's blood gas type (1.12, Ben's note 13), chosen from a menu at the top right of the set, level with the
    /// "Drawn at" heading: ABG (the default), VBG, ScvO₂ (CVL) or SvO₂ (PA). The labels and ranges below follow it.
    private func gasTypeMenu(_ s: IntraopLabSet) -> some View {
        Menu {
            ForEach(BloodGasType.allCases, id: \.self) { t in
                Button {
                    Haptics.light()
                    withAnimation(.snappy) { if let i = index(s.id) { patient.update(discrete: true) { $0.intraopLabs[i].gasType = t } } }
                } label: {
                    if t == s.gasType { Label(t.label, systemImage: "checkmark") } else { Text(t.label) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(s.gasType.short)
                Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 10, weight: .bold))
            }
            .font(PS.sys(size: 13.5, weight: .semibold))
            .foregroundStyle(PS.action)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(PS.action.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .accessibilityLabel("Blood gas type, " + s.gasType.label)
        .accessibilityHint("Chooses ABG, VBG, ScvO₂ or SvO₂")
    }

    @ViewBuilder private func setEditor(_ s: IntraopLabSet, chained: Bool = false) -> some View {
        let type = s.gasType
        // The "Drawn at" heading with the gas type menu on its line (PatientGroup draws no accessory, so the box is drawn
        // here the same way).
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                SectionHeader(title: "Drawn at", info: nil).padding(.leading, 2)
                Spacer(minLength: 8)
                gasTypeMenu(s)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    DatePicker("Time drawn", selection: Binding(get: { index(s.id).flatMap { patient.record.intraopLabs[$0].time } ?? Date() },
                                                                set: { v in if let i = index(s.id) { patient.update { $0.intraopLabs[i].time = v } } }),
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .environment(\.locale, PatientDates.locale24)
                    Spacer()
                    Button(role: .destructive) {
                        withAnimation(.snappy) { if let i = index(s.id) { patient.update(discrete: true) { _ = $0.intraopLabs.remove(at: i) } } }
                    } label: { Image(systemName: "trash").foregroundStyle(PS.fg3) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove this lab set")
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
        // 1.12 (Ben's note 13): the glucose is a section of its own, above the blood gas.
        PatientGroup(title: "Glucose") { rows(s.id, IntraopLabs.glucoseKeys, chained: chained, type: type) }
        // 1.11 (Ben, Nov 9): the gas as its slash figure, pH / PaCO₂ / PaO₂ / HCO₃, typed into the slots; the rest of
        // the gas follows as rows. Previous and Next walk them in the same order as before (IntraopLabs.abg). 1.12: the
        // labels and the ranges follow the gas type (PvCO₂ and PvO₂ and no arterial flags on a venous gas), and an ScvO₂
        // or SvO₂ sample has its saturation first.
        PatientGroup(title: "Blood gas") {
            if type.hasSaturation {
                rows(s.id, [IntraopLabs.satKey], chained: chained, type: type)
                Hairline().padding(.leading, 14)
            }
            FishboneABG(g: .page) { key in
                if let t = IntraopLabs.test(key, type: type) {
                    LabSlot(test: t, sex: r.sex, value: value(s.id, t.key), chain: chain(t.key, chained),
                            ranged: IntraopLabs.isRanged(t.key, type: type))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            Hairline().padding(.leading, 14)
            rows(s.id, IntraopLabs.abgRest, chained: chained, type: type)
        }
        PatientGroup(title: "Coagulation") { rows(s.id, IntraopLabs.coag, chained: chained, type: type) }
        PatientGroup(title: "Viscoelastic & other") {
            PatientTextField(label: "ROTEM or TEG", prompt: "e.g. EXTEM CT 85 s, A10 38 mm; FIBTEM A10 7 mm", text: text(s.id, \.viscoelastic))
            PatientTextField(label: "Other results", prompt: "e.g. Mg 1.6, SvO₂ 64%, anti-Xa", text: text(s.id, \.other))
        }
    }

    private func chain(_ key: String, _ chained: Bool) -> PatientFieldChain? {
        guard chained, let focus else { return nil }
        return PatientFieldChain(focus: focus, id: "iop." + key)
    }

    @ViewBuilder private func rows(_ id: UUID, _ keys: [String], chained: Bool, type: BloodGasType) -> some View {
        let tests = IntraopLabs.tests(keys, type: type)
        ForEach(Array(tests.enumerated()), id: \.element.id) { i, t in
            if t.key == "be" {
                // The number pad has no minus sign: ± turns an excess into a deficit.
                HStack(spacing: 0) {
                    LabFieldRow(test: t, sex: r.sex, troponin99: nil, value: value(id, t.key), chain: chain(t.key, chained),
                                ranged: IntraopLabs.isRanged(t.key, type: type))
                    Button {
                        let b = value(id, t.key)
                        patient.markDiscrete()
                        if let v = b.wrappedValue { b.wrappedValue = -v }
                    } label: {
                        Text("±").font(PS.sys(size: 16, weight: .bold)).foregroundStyle(PS.action).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    .accessibilityLabel("Change the sign of the base excess")
                }
            } else {
                LabFieldRow(test: t, sex: r.sex, troponin99: nil, value: value(id, t.key), chain: chain(t.key, chained),
                            ranged: IntraopLabs.isRanged(t.key, type: type))
            }
            if i < tests.count - 1 { Hairline().padding(.leading, 14) }
        }
    }
}

// MARK: Blood products

/// PRBC, FFP, platelets, cryoprecipitate and whole blood in units, and cell saver in mL, each with − and +.
struct BloodProductsGroup: View {
    @Environment(PatientStore.self) private var patient

    private func amount(_ id: String) -> Binding<Double?> {
        Binding(get: { patient.record.fluids[id] }, set: { v in patient.update { $0.fluids[id] = (v ?? 0) > 0 ? v : nil } })
    }

    var body: some View {
        PatientGroup(title: "Blood products", note: "Running totals for the case: tap + as each unit goes up, or type the number. Cell saver is the volume returned to the patient. The totals go to the intraoperative card and both handoffs.") {
            ForEach(Array(BloodProducts.units.enumerated()), id: \.element.id) { _, u in
                BloodStepperRow(label: u.label, unit: "units", step: 1, limit: 199, quick: u.id == "cryo" ? 5 : nil, value: amount(u.id))
                Hairline().padding(.leading, 14)
            }
            BloodStepperRow(label: "Cell saver returned", unit: "mL", step: BloodProducts.cellSaverStep, limit: 20000, value: amount(BloodProducts.cellSaver))
        }
    }
}

/// One product: − and + around the number, which can also be typed.
struct BloodStepperRow: View {
    var label: String
    var unit: String
    var step: Double
    var limit: Double
    /// A second + for a usual pool ("+5" cryoprecipitate).
    var quick: Double? = nil
    @Binding var value: Double?
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(PatientStore.self) private var store: PatientStore?

    private var v: Double { value ?? 0 }

    /// − and +: each tap is an Undo step of its own.
    private func set(_ n: Double) {
        Haptics.light()
        store?.markDiscrete()
        value = n > 0 ? min(n, limit) : nil
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg).lineLimit(2).minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            if let q = quick {
                Button { set(v + q) } label: {
                    Text("+" + NumText.short(q)).font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.action)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(PS.action.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(NumText.short(q)) \(unit) of \(label)")
            }
            Button { set(v - step) } label: {
                Image(systemName: "minus").font(PS.sys(size: 14, weight: .bold)).frame(width: 34, height: 34)
                    .foregroundStyle(v > 0 ? PS.fg : PS.fg3)
                    .background(PS.surface2, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(v <= 0)
            .accessibilityLabel("Remove \(NumText.short(step)) \(unit) of \(label)")
            TextField("0", text: $text)
                .focused($focused)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(v > 0 ? PS.fg : PS.fg3)
                .frame(width: unit == "mL" ? 64 : 40)
                .accessibilityLabel(label + ", " + unit)
            Button { set(v + step) } label: {
                Image(systemName: "plus").font(PS.sys(size: 14, weight: .bold)).frame(width: 34, height: 34)
                    .foregroundStyle(PS.accentFg)
                    .background(PS.action, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(NumText.short(step)) \(unit) of \(label)")
            Text(unit).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 30, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .onAppear { text = value.map { NumText.short($0) } ?? "" }
        .onChange(of: text) { _, t in
            let n = Double(t.trimmingCharacters(in: .whitespaces))
            let next: Double? = (n ?? 0) > 0 ? min(n ?? 0, limit) : nil
            if next != value { value = next }
        }
        .onChange(of: value) { _, n in
            let shown: Double? = Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
            if shown != n { text = n.map { NumText.short($0) } ?? "" }
        }
    }
}

// MARK: Major considerations

struct IntraopConsiderationsEditor: View {
    @Environment(PatientStore.self) private var patient

    var body: some View {
        let r = patient.record
        PatientGroup(title: "Major intraoperative considerations", note: "What the next team most needs to know. These go near the top of both handoffs, under Key considerations.") {
            PatientChipRow(label: nil) { PatientChips(options: IntraopConsiderations.flags, selection: patient.binding(\.considerations), tint: PS.action) }
            let suggested = IntraopConsiderations.suggested(r)
            if !suggested.isEmpty {
                Button {
                    patient.update(discrete: true) { rec in for f in suggested { rec.considerations.insert(f.id) } }
                } label: {
                    Label("Add " + suggested.map { $0.label.lowercased() }.joined(separator: ", ") + " (recorded in the airway)", systemImage: "plus.circle")
                        .font(PS.sys(size: 13.5, weight: .semibold)).multilineTextAlignment(.leading)
                }
                .buttonStyle(.borderless).tint(PS.action)
                .padding(.horizontal, 14).padding(.bottom, 6)
            }
            PatientTextField(label: "Details", prompt: "e.g. grade 4 view, awake fiberoptic; ongoing coagulopathy; new RWMA on TEE; prone 5 h", text: patient.binding(\.considerationsNote))
        }
    }
}

// MARK: Code status

/// Code status with the perioperative plan for it, after the ASA's required reconsideration of DNR orders.
struct PatientCodeStatusGroup: View {
    @Environment(PatientStore.self) private var patient

    var body: some View {
        let r = patient.record
        PatientGroup(title: "Code status", note: PatientCodeStatus.note) {
            PatientChipRow(label: nil) {
                CodeStatusChips()
            }
            if r.codeStatus == .limited {
                PatientTextField(label: "Limits", prompt: "e.g. no chest compressions or defibrillation; vasopressors acceptable", text: patient.binding(\.codeStatusLimits))
            }
            Toggle(isOn: Binding(get: { patient.record.polst }, set: { v in patient.update(discrete: true) { $0.polst = v } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("POLST on file").font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                    Text("Portable medical orders (POLST, MOLST)").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                }
            }
            .tint(PS.action)
            .padding(.horizontal, 14).padding(.vertical, 9)
            if r.codeStatus?.limits == true {
                Hairline().padding(.leading, 14)
                // The chosen plan's definition (the ASA option it is) sits behind the ⓘ on "For the procedure" (1.8.1);
                // Maintained's instruction to tell the patient stays in view under the chips, and "Not yet discussed"
                // stays in view in red.
                InfoChipRow(label: "For the procedure", info: r.codeStatusPlan?.info) {
                    PatientChoice(options: CodeStatusPlan.allCases.map { (id: $0.rawValue, label: $0.label) },
                                  selection: Binding(get: { patient.record.codeStatusPlan?.rawValue }, set: { v in patient.update { $0.codeStatusPlan = v.flatMap { CodeStatusPlan(rawValue: $0) } } }),
                                  tint: PS.accent2,
                                  // One word each when the row has room for no more ("For the procedure" is the title).
                                  shorts: ["maintained": "Maintained", "modified": "Modified", "suspended": "Suspended"])
                }
                if let shown = r.codeStatusPlan?.inView {
                    Text(shown)
                        .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.top, -4).padding(.bottom, 4)
                }
                if r.codeStatusPlan == nil {
                    Text("Not yet discussed: review the orders with the patient or surrogate before the anesthetic.")
                        .font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.red).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.bottom, 4)
                }
                PatientTextField(label: r.codeStatusPlan == .suspended ? "When the original orders resume" : "What is and is not acceptable, and when the orders resume",
                                 prompt: "e.g. accepts intubation and vasopressors; no compressions; resumes on leaving the PACU", text: patient.binding(\.codeStatusPlanNote))
            }
        }
        .id("codestatus")
    }
}

// MARK: Handoff

/// The handoff text with its headers bold and underlined, its labels bold (HandoffStyle, 1.8.3) and its abnormal values
/// in bold red (HandoffWriter.marks).
func handoffStyled(_ text: String, marks: [String]) -> AttributedString {
    var a = AttributedString(MarkedText.kept(text, marks: marks))
    for s in HandoffStyle.spans(text) {
        let lo = a.index(a.startIndex, offsetByCharacters: text.distance(from: text.startIndex, to: s.range.lowerBound))
        let hi = a.index(lo, offsetByCharacters: text.distance(from: s.range.lowerBound, to: s.range.upperBound))
        a[lo..<hi].font = PS.sys(size: 14.5, weight: .bold)
        if s.kind == .header { a[lo..<hi].underlineStyle = .single }
    }
    a.paintMarks(marks, in: text, font: PS.sys(size: 14.5, weight: .bold))
    return a
}
