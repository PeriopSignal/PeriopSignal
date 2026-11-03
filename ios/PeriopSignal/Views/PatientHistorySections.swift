import SwiftUI

// MARK: - The expanding History pages (Cardiovascular, Respiratory; 1.8.1)
//
// A list of top items: tapping one chooses it and opens its options under it; tapping it again clears it and its
// details (Undo steps it back). The options are chips and short typed fields, with no explanation on the page: how an
// item feeds the ASA suggestion and the scores is behind the group's ⓘ.

struct PatientHistorySectionsView: View {
    var system: PatientSystem
    @Environment(PatientStore.self) private var patient
    /// Headings opened that hold nothing yet (Valve disease, Arrhythmia): open while the page is.
    @State private var opened: Set<String> = []

    private var r: PatientRecord { patient.record }
    private var sections: [HistorySection] { HistorySections.sections(system.id) ?? [] }

    var body: some View {
        PatientGroup(title: system.name, note: PatientCatalog.systemNote(system)) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { i, s in
                if system.id == "resp" && s.id == "other" {
                    pftRow
                    Hairline().padding(.leading, 48)
                }
                section(s)
                if i < sections.count - 1 { Hairline().padding(.leading, 48) }
            }
        }
    }

    // MARK: Editing

    private func edit(_ change: (inout PatientRecord) -> Void) {
        patient.update { r in
            change(&r)
            PatientHistoryDetails.sync(&r)
        }
    }

    private func isOpen(_ s: HistorySection) -> Bool { opened.contains(s.id) || HistorySections.isSelected(s, system: system.id, r) }

    private func tap(_ s: HistorySection) {
        Haptics.light()
        patient.markDiscrete()
        withAnimation(.snappy) {
            if isOpen(s) {
                opened.remove(s.id)
                edit { HistorySections.clear(s, system: system.id, &$0) }
            } else {
                opened.insert(s.id)
                edit { HistorySections.select(s, &$0) }
            }
        }
    }

    /// Several options at once, among problem ids.
    private func options(_ ids: [String], _ s: HistorySection) -> Binding<Set<String>> {
        Binding(get: { patient.record.problems.intersection(ids) }, set: { new in
            edit { r in
                let old = r.problems.intersection(ids)
                for id in ids where new.contains(id) && !old.contains(id) { HistorySections.setOption(id, true, in: s, &r) }
                for id in ids where old.contains(id) && !new.contains(id) { HistorySections.setOption(id, false, in: s, &r) }
            }
        })
    }

    /// One option among problem ids (the first recorded is shown when a saved record has two).
    private func choice(_ ids: [String], _ s: HistorySection) -> Binding<String?> {
        Binding(get: { ids.first { patient.record.problems.contains($0) } }, set: { v in edit { HistorySections.choose(v, among: ids, in: s, &$0) } })
    }

    private func text(_ kp: WritableKeyPath<PatientHistoryDetails, String>) -> Binding<String> {
        Binding(get: { patient.record.hx[keyPath: kp] }, set: { v in edit { $0.hx[keyPath: kp] = v } })
    }

    private func flags(_ list: [(String, String)]) -> [PatientFlag] { list.map { PatientFlag($0.0, $0.1) } }

    // MARK: Rows

    @ViewBuilder private func section(_ s: HistorySection) -> some View {
        let open = isOpen(s)
        Button { tap(s) } label: {
            HStack(spacing: 12) {
                Image(systemName: open ? "checkmark.circle.fill" : "circle")
                    .font(PS.sys(size: 18, weight: .regular))
                    .foregroundStyle(open ? PS.accent : PS.fg3)
                    .frame(width: 22)
                Text(s.title).font(PS.sys(size: 15, weight: open ? .semibold : .medium)).foregroundStyle(PS.fg)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(open ? .isSelected : [])
        .accessibilityHint(open ? "Clears it and its details" : "Adds it and shows its options")
        .id("hx-" + s.id)
        if open {
            VStack(alignment: .leading, spacing: 8) { content(s) }
                .padding(.leading, 48).padding(.trailing, 14).padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        }
    }

    private func row<C: View>(_ label: String?, @ViewBuilder _ c: () -> C) -> some View {
        let choices = c()
        return Group {
            if let label {
                InlineChoices { Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2) } choices: { choices }
            } else {
                choices
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func content(_ s: HistorySection) -> some View {
        switch s.id {
        case "htn":
            PatientChips(options: [PatientFlag("htn-180", "BP ≥ 180/110 before the day of surgery")], selection: options(["htn-180"], s))
        case "cad":
            row("MI") { PatientChoice(options: [(id: "cad-recent", label: "Within 3 months"), (id: "mi", label: "Over 3 months")], selection: choice(["cad-recent", "mi"], s)) }
            row("PCI") { PatientChoice(options: [(id: "pci-recent", label: "Within 3 months"), (id: "pci", label: "Over 3 months")], selection: choice(["pci-recent", "pci"], s)) }
            PatientChips(options: [PatientFlag("ischemia", "Ongoing (unstable) ischemia"), PatientFlag("cabg", "Prior CABG")], selection: options(["ischemia", "cabg"], s))
        case "hf":
            row("Status") { PatientChoice(options: [(id: "compensated", label: "Compensated"), (id: "decompensated", label: "Decompensated")], selection: hfStatus(s)) }
            row("EF") { PatientChoice(options: [(id: "ef-moderate", label: "Moderately reduced"), (id: "ef-severe", label: "Severely reduced")], selection: choice(["ef-severe", "ef-moderate"], s)) }
        case "valves":
            valves
        case "arrhythmia":
            PatientChips(options: [PatientFlag("af", "AF/flutter"), PatientFlag("arrhythmia", "Other")], selection: options(["af", "arrhythmia"], s))
            if r.has("arrhythmia") { HistoryInlineField(prompt: "Type, e.g. SVT, heart block", text: text(\.arrhythmiaType)) }
        case "device":
            PatientChips(options: [PatientFlag("pacemaker", "Pacemaker"), PatientFlag("icd", "ICD")], selection: options(["pacemaker", "icd"], s))
            HistoryInlineField(prompt: "Details, e.g. dependent, make, magnet response", text: text(\.deviceDetails))
        case "pulm-htn":
            PatientChoice(options: PatientHistoryDetails.grades, selection: pulmHtnGrade)
        case "aorta":
            aorta(s)
        case "pvd":
            HistoryInlineField(prompt: "Details", text: text(\.pvdDetails))
        case "chd":
            PatientChips(options: [PatientFlag("chd-elevated", "Complex lesion (Fontan/single ventricle, cyanotic, TGA)")], selection: options(["chd-elevated"], s))
            HistoryInlineField(prompt: "Details", text: text(\.chdDetails))
        case "cardiac-surgery":
            HistoryInlineField(prompt: "e.g. AVR 2015; CABG ×3 2010", text: Binding(get: { PatientHistoryDetails.cardiacSurgeryText(patient.record) },
                                                                                    set: { v in edit { PatientHistoryDetails.setCardiacSurgery(v, &$0) } }))
        case "other":
            HistoryInlineField(prompt: "Anything else", text: Binding(get: { patient.record.systemNotes[system.id] ?? "" },
                                                                     set: { v in edit { $0.systemNotes[system.id] = v.isEmpty ? nil : v } }))
        case "asthma":
            PatientChoice(options: [(id: "controlled", label: "Controlled"), (id: "uncontrolled", label: "Uncontrolled")], selection: asthmaControl(s))
        case "osa":
            PatientChoice(options: [(id: "none", label: "Not on CPAP"), (id: "cpap", label: "CPAP/BiPAP")], selection: osaTherapy)
            if r.has("cpap") { HistoryInlineField(prompt: "Home settings, e.g. CPAP 10, BiPAP 14/8", text: text(\.cpapSettings)) }
        case "resp-infection":
            PatientChips(options: [PatientFlag("uri", "URI"), PatientFlag("pneumonia", "Pneumonia"), PatientFlag("resp-infection-other", "Other")],
                         selection: options(["uri", "pneumonia", "resp-infection-other"], s))
            if r.has("resp-infection-other") { HistoryInlineField(prompt: "Type", text: text(\.respInfectionType)) }
        case "home-o2":
            PatientNumberField(label: "Flow", unit: "L/min", value: Binding(get: { patient.record.hx.homeO2Flow }, set: { v in edit { $0.hx.homeO2Flow = v } }))
                .padding(.horizontal, -14)
        default:
            EmptyView()
        }
    }

    // MARK: Heart failure, pulmonary hypertension, asthma, sleep apnea

    private func hfStatus(_ s: HistorySection) -> Binding<String?> {
        Binding(get: { patient.record.has("hf-decomp") ? "decompensated" : (patient.record.hx.hfCompensated ? "compensated" : nil) }, set: { v in
            edit { r in
                HistorySections.setOption("hf-decomp", v == "decompensated", in: s, &r)
                r.hx.hfCompensated = v == "compensated"
            }
        })
    }

    private var pulmHtnGrade: Binding<String?> {
        Binding(get: { patient.record.has("pulm-htn-severe") ? "severe" : patient.record.hx.pulmHtnSeverity }, set: { v in
            edit { r in
                if v == "severe" {
                    r.problems.remove("pulm-htn")
                    r.problems.insert("pulm-htn-severe")
                    r.hx.pulmHtnSeverity = nil
                } else {
                    r.problems.remove("pulm-htn-severe")
                    r.problems.insert("pulm-htn")
                    r.hx.pulmHtnSeverity = v
                }
            }
        })
    }

    private func asthmaControl(_ s: HistorySection) -> Binding<String?> {
        Binding(get: { patient.record.has("asthma-uncontrolled") ? "uncontrolled" : (patient.record.hx.asthmaControlled ? "controlled" : nil) }, set: { v in
            edit { r in
                HistorySections.setOption("asthma-uncontrolled", v == "uncontrolled", in: s, &r)
                r.hx.asthmaControlled = v == "controlled"
            }
        })
    }

    private var osaTherapy: Binding<String?> {
        Binding(get: { patient.record.has("cpap") ? "cpap" : (patient.record.hx.osaNoCPAP ? "none" : nil) }, set: { v in
            edit { r in
                r.problems.insert("osa")
                if v == "cpap" { r.problems.insert("cpap") } else { r.problems.remove("cpap"); r.hx.cpapSettings = "" }
                r.hx.osaNoCPAP = v == "none"
            }
        })
    }

    // MARK: Valves

    @ViewBuilder private var valves: some View {
        ForEach(PatientHistoryDetails.valveNames, id: \.id) { v in
            let x = r.hx.valve(v.id)
            VStack(alignment: .leading, spacing: 7) {
                row(v.label) {
                    PatientChips(options: flags(PatientHistoryDetails.lesions.map { ($0.id, $0.label) }), selection: Binding(
                        get: { Set(PatientHistoryDetails.lesions.map(\.id).filter { patient.record.hx.valve(v.id).has($0) }) },
                        set: { new in edit { r in r.hx.editValve(v.id) { val in for l in PatientHistoryDetails.lesions.map(\.id) { val.set(l, new.contains(l)) } } } }))
                }
                ForEach(["stenosis", "regurgitation"], id: \.self) { l in
                    if x.has(l) {
                        row(l == "stenosis" ? "Stenosis" : "Regurgitation") {
                            PatientChoice(options: PatientHistoryDetails.grades, selection: Binding(
                                get: { patient.record.hx.valve(v.id).grade(l) },
                                set: { g in edit { r in r.hx.editValve(v.id) { $0.setGrade(l, g) } } }))
                        }
                        .padding(.leading, 12)
                    }
                }
                if x.prosthetic {
                    HistoryInlineField(prompt: "Type, e.g. mechanical 23 mm", text: Binding(
                        get: { patient.record.hx.valve(v.id).prosthesis },
                        set: { t in edit { r in r.hx.editValve(v.id) { $0.prosthesis = t } } }))
                        .padding(.leading, 12)
                }
            }
            .padding(.vertical, 2)
        }
        // Saved before 1.8.1 without a valve: shown as such until taken off or replaced.
        let legacy = [r.hx.prosthesisUnplaced ? PatientFlag("prosthesis", "Prosthetic valve, position not recorded") : nil,
                      r.hx.severeUnplaced && !r.hx.anySevereLesion ? PatientFlag("severe", "Severe valve disease, valve not recorded") : nil].compactMap { $0 }
        if !legacy.isEmpty {
            PatientChips(options: legacy, selection: Binding(get: { Set(legacy.map(\.id)) }, set: { new in
                edit { r in
                    if !new.contains("prosthesis") { r.hx.prosthesisUnplaced = false }
                    if !new.contains("severe") { r.hx.severeUnplaced = false }
                }
            }))
        }
    }

    // MARK: Aortopathy

    @ViewBuilder private func aorta(_ s: HistorySection) -> some View {
        let unplaced = PatientHistoryDetails.unplacedThoracic
        let sites: [(id: String, label: String)] = PatientHistoryDetails.aneurysmSites.map { (id: $0.id, label: $0.label) }
            + (r.hx.aneurysms[unplaced.id] != nil ? [(id: unplaced.id, label: unplaced.label)] : [])
        row("Aneurysm") {
            PatientChips(options: flags(sites.map { ($0.id, $0.label) }), selection: Binding(get: { Set(patient.record.hx.aneurysms.keys) }, set: { new in
                edit { r in
                    for site in sites.map(\.id) {
                        if new.contains(site), r.hx.aneurysms[site] == nil { r.hx.aneurysms[site] = PatientAneurysm() }
                        if !new.contains(site) { r.hx.aneurysms[site] = nil }
                    }
                }
            }))
        }
        ForEach(sites.filter { r.hx.aneurysms[$0.id] != nil }, id: \.id) { site in
            aneurysm(site.id, site.label)
        }
        row("Dissection") { PatientChoice(options: [(id: "dissection-a", label: "Type A"), (id: "dissection-b", label: "Type B")], selection: choice(["dissection-a", "dissection-b"], s)) }
        row("Prior repair") {
            PatientChips(options: [PatientFlag("aortic-repair-open", "Open"), PatientFlag("evar", "EVAR"), PatientFlag("tevar", "TEVAR")],
                         selection: options(["aortic-repair-open", "evar", "tevar"], s))
        }
        if !r.problems.isDisjoint(with: ["aortic-repair-open", "evar", "tevar"]) || !r.hx.repairDetails.isEmpty {
            HistoryInlineField(prompt: "Repair details", text: text(\.repairDetails))
        }
    }

    private func aneurysm(_ site: String, _ label: String) -> some View {
        func field<T>(_ kp: WritableKeyPath<PatientAneurysm, T>, _ fallback: T) -> Binding<T> {
            Binding(get: { patient.record.hx.aneurysms[site]?[keyPath: kp] ?? fallback }, set: { v in
                edit { r in
                    var a = r.hx.aneurysms[site] ?? PatientAneurysm()
                    a[keyPath: kp] = v
                    r.hx.aneurysms[site] = a
                }
            })
        }
        let ruptured = field(\.ruptured, false)
        return VStack(alignment: .leading, spacing: 6) {
            Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            PatientNumberField(label: "Size", unit: "cm", value: field(\.cm, nil)).padding(.horizontal, -14)
            Toggle(isOn: Binding(get: { ruptured.wrappedValue }, set: { v in patient.markDiscrete(); ruptured.wrappedValue = v })) {
                Text("Ruptured").font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg)
            }
            .tint(PS.red)
            HistoryInlineField(prompt: "Notes", text: field(\.notes, ""))
        }
        .padding(10)
        .background(PS.surface2.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Pulmonary function tests

    private var pftRow: some View {
        NavigationLink(value: PatientEditor.workup("pft")) {
            HStack(spacing: 12) {
                Image(systemName: r.pft.isEmpty ? "plus.circle" : "lungs").font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.accent).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pulmonary function tests").font(PS.sys(size: 15, weight: .medium)).foregroundStyle(PS.fg)
                    Text(r.pft.isEmpty ? "Add results" : r.pft.summary(copd: r.has("copd"))).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineLimit(2)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id("hx-pft")
    }
}

/// A short typed field inside an expanded item: the box only, its prompt as the placeholder and the VoiceOver label.
struct HistoryInlineField: View {
    var prompt: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $text, axis: .vertical)
            .lineLimit(1...4)
            .focused($focused)
            .font(PS.sys(size: 14.5))
            .foregroundStyle(PS.fg)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .accessibilityLabel(prompt)
    }
}
