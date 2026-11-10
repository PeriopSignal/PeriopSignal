import SwiftUI

// MARK: - The expanding History pages (Cardiovascular, Respiratory; 1.8.1; Neurologic, 1.8.2; every system, 1.9)
//
// A list of top items: tapping one chooses it and opens its options under it; tapping it again clears it and its
// details (Undo steps it back). The options are chips and short typed fields, with no explanation on the page: how an
// item feeds the ASA suggestion and the scores is behind the group's ⓘ. Every page ends with two always-open fields,
// Other [system] disorders and Other details (1.9).
//
// 1.9: warnings beside an item (PatientWarnings), suggestions under it (isolation precautions, a thyroid disease from
// the TSH), stress-dose steroid advice under Adrenal, values shared with Labs shown in place (Hb, platelets, INR, TFTs,
// MELD and CTP), and display-only rows for what another page records ("From Obstetric", "From Cardiovascular").

struct PatientHistorySectionsView: View {
    var system: PatientSystem
    @Environment(PatientStore.self) private var patient
    /// Headings opened that hold nothing yet (Valve disease, Arrhythmia), and "Other" chips opened before anything is
    /// typed: open while the page is.
    @State private var opened: Set<String> = []
    /// Captions behind an ⓘ toggled on this visit (flipped from all open on a -ps.evidence.open run).
    @State private var infoToggled: Set<String> = []
    private let infoAllOpen = LaunchSeed.bool("ps.evidence.open")

    private var r: PatientRecord { patient.record }
    private var sections: [HistorySection] { HistorySections.sections(system.id) ?? [] }
    private static let noYes: [(id: String, label: String)] = [("no", "No"), ("yes", "Yes")]

    var body: some View {
        PatientGroup(title: system.name, note: PatientCatalog.systemNote(system)) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { i, s in
                if s.id == "other-disorders" { pageRows }
                if Self.closing.contains(s.id) { closingField(s) } else { section(s) }
                if i < sections.count - 1 { Hairline().padding(.leading, Self.closing.contains(s.id) ? 14 : 48) }
            }
        }
    }

    private static let closing: Set<String> = ["other-disorders", "other"]
    /// Items with nothing under them once chosen: no empty space is left below their row (1.9).
    private static let bare: Set<String> = ["hyperlipidemia", "copd", "ild", "raised-icp", "seizure", "dementia", "parkinson", "neuromuscular", "sci",
                                            "chronic-pain", "cspine", "aki", "gerd", "hiatal-hernia", "varices", "hepatitis-active", "gastroparesis",
                                            "full-stomach", "sickle", "mdro", "uri", "pneumonia", "c-diff", "infection-active", "gest-htn",
                                            "muscular-dystrophy"]

    /// A short typed field with its name beside it, for values that read ambiguously once filled ("10/20").
    private func labeled(_ label: String, _ prompt: String, _ t: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2).fixedSize()
            HistoryInlineField(prompt: prompt, label: label, text: t)
        }
    }

    /// Rows before the closing fields: the PFTs on Respiratory, and what the Obstetric page records for this system.
    @ViewBuilder private var pageRows: some View {
        if system.id == "resp" {
            pftRow
            Hairline().padding(.leading, 48)
        }
        let ob = HistorySections.fromObstetric(system.id, r)
        if !ob.isEmpty {
            crossRow("From Obstetric", ob, to: .system("ob"), icon: "figure.2.and.child.holdinghands").id("hx-from-ob")
            Hairline().padding(.leading, 48)
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

    /// One answer kept in the details ("left", "acute").
    private func hx(_ kp: WritableKeyPath<PatientHistoryDetails, String?>) -> Binding<String?> {
        Binding(get: { patient.record.hx[keyPath: kp] }, set: { v in edit { $0.hx[keyPath: kp] = v } })
    }

    private func hxSet(_ kp: WritableKeyPath<PatientHistoryDetails, Set<String>>) -> Binding<Set<String>> {
        Binding(get: { patient.record.hx[keyPath: kp] }, set: { v in edit { $0.hx[keyPath: kp] = v } })
    }

    private func number(_ kp: WritableKeyPath<PatientHistoryDetails, Double?>) -> Binding<Double?> {
        Binding(get: { patient.record.hx[keyPath: kp] }, set: { v in edit { $0.hx[keyPath: kp] = v } })
    }

    private func count(_ kp: WritableKeyPath<PatientHistoryDetails, Int?>) -> Binding<Int?> {
        Binding(get: { patient.record.hx[keyPath: kp] }, set: { v in edit { $0.hx[keyPath: kp] = v } })
    }

    /// A whole number typed in a decimal field (a year).
    private func whole(_ kp: WritableKeyPath<PatientHistoryDetails, Int?>) -> Binding<Double?> {
        Binding(get: { patient.record.hx[keyPath: kp].map { Double($0) } }, set: { v in edit { $0.hx[keyPath: kp] = v.map { Int($0.rounded()) } } })
    }

    /// No / Yes as chips over a Bool? (nil not asked); `set` may clear what hangs from the answer.
    private func yesNo(_ get: @escaping (PatientRecord) -> Bool?, _ set: @escaping (Bool?, inout PatientRecord) -> Void) -> Binding<String?> {
        Binding(get: { get(patient.record).map { $0 ? "yes" : "no" } }, set: { v in edit { r in set(v.map { $0 == "yes" }, &r) } })
    }

    private func yesNo(_ kp: WritableKeyPath<PatientHistoryDetails, Bool?>) -> Binding<String?> {
        yesNo({ $0.hx[keyPath: kp] }, { v, r in r.hx[keyPath: kp] = v })
    }

    /// Chips with an "Other" chip that opens a typed field: Other is on while the field holds text (or was just
    /// tapped); taking it off clears the text.
    private func withOther(_ get: @escaping (PatientRecord) -> Set<String>, key: String, text kp: WritableKeyPath<PatientHistoryDetails, String>,
                           _ set: @escaping (Set<String>, inout PatientRecord) -> Void) -> Binding<Set<String>> {
        Binding(get: {
            var v = get(patient.record)
            if opened.contains(key) || !patient.record.hx[keyPath: kp].isEmpty { v.insert("other") }
            return v
        }, set: { new in
            if new.contains("other") { opened.insert(key) } else { opened.remove(key) }
            edit { r in
                set(new.subtracting(["other"]), &r)
                if !new.contains("other") { r.hx[keyPath: kp] = "" }
            }
        })
    }

    /// Problem-id options with an Other text.
    private func optionsWithOther(_ ids: [String], _ s: HistorySection, key: String, text kp: WritableKeyPath<PatientHistoryDetails, String>) -> Binding<Set<String>> {
        withOther({ $0.problems.intersection(ids) }, key: key, text: kp) { new, r in
            for id in ids where new.contains(id) != r.problems.contains(id) { HistorySections.setOption(id, new.contains(id), in: s, &r) }
        }
    }

    private func otherOpen(_ key: String, _ kp: WritableKeyPath<PatientHistoryDetails, String>) -> Bool { opened.contains(key) || !r.hx[keyPath: kp].isEmpty }

    /// A lab value, the same storage as Labs.
    private func lab(_ key: String) -> Binding<Double?> {
        Binding(get: { patient.record.labs[key] }, set: { v in patient.update { $0.labs[key] = v } })
    }

    private func flags(_ list: [(id: String, label: String)]) -> [PatientFlag] { list.map { PatientFlag($0.id, $0.label) } }

    private func info(_ key: String) -> Binding<Bool> {
        Binding(get: { infoAllOpen != infoToggled.contains(key) }, set: { v in
            if v == infoAllOpen { infoToggled.remove(key) } else { infoToggled.insert(key) }
        })
    }

    // MARK: Rows

    @ViewBuilder private func section(_ s: HistorySection) -> some View {
        let open = isOpen(s)
        Button { tap(s) } label: {
            HStack(spacing: 12) {
                Image(systemName: open ? "checkmark.circle.fill" : "circle")
                    .font(PS.sys(size: 18, weight: .regular))
                    .foregroundStyle(open ? PS.action : PS.fg3)
                    .frame(width: 22)
                title(s, open: open)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(open ? .isSelected : [])
        .accessibilityHint(open ? "Clears it and its details" : "Adds it and shows its options")
        .id("hx-" + s.id)
        if open && !Self.bare.contains(s.id) {
            VStack(alignment: .leading, spacing: 8) { content(s) }
                .padding(.leading, 48).padding(.trailing, 14).padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        }
        offers(s)
    }

    /// The item's title, with its warnings beside it (on the next line when they don't fit).
    @ViewBuilder private func title(_ s: HistorySection, open: Bool) -> some View {
        let name = Text(s.title).font(PS.sys(size: 15, weight: open ? .semibold : .medium)).foregroundStyle(PS.fg)
        let tags = warnings(s)
        if tags.isEmpty {
            name
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { name.fixedSize(); WarningTags(tags: tags) }
                VStack(alignment: .leading, spacing: 4) { name; WarningTags(tags: tags) }
            }
        }
    }

    /// Warnings for the item's recorded ids, each once.
    private func warnings(_ s: HistorySection) -> [String] {
        var seen: Set<String> = []
        return s.members.filter(r.problems.contains).flatMap { PatientWarnings.tags($0, r) }.filter { seen.insert($0).inserted }
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

    /// Other [system] disorders and Other details: always open (1.9), capitalized when left.
    private func closingField(_ s: HistorySection) -> some View {
        let notes = s.id == "other"
        let binding = Binding<String>(
            get: { (notes ? patient.record.systemNotes[system.id] : patient.record.systemOther[system.id]) ?? "" },
            set: { v in edit { r in if notes { r.systemNotes[system.id] = v.isEmpty ? nil : v } else { r.systemOther[system.id] = v.isEmpty ? nil : v } } })
        return VStack(alignment: .leading, spacing: 6) {
            Text(s.title).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            HistoryInlineField(prompt: notes ? "Severity, dates, treatment" : "Type to add", capitalizes: true, label: s.title, text: binding)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("hx-" + s.id)
    }

    @ViewBuilder private func content(_ s: HistorySection) -> some View {
        switch system.id {
        case "cv", "resp", "neuro": baseContent(s)
        case "renal", "gi", "endo": renalGIEndo(s)
        case "heme", "infectious": hemeInfectious(s)
        case "acute", "ob": acuteOB(s)
        default: mskSocial(s)
        }
    }

    // MARK: Cardiovascular, Respiratory, Neurologic

    @ViewBuilder private func baseContent(_ s: HistorySection) -> some View {
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
        case "endocarditis":
            endocarditisField
        case "arrhythmia":
            PatientChips(options: [PatientFlag("af", "AF/flutter"), PatientFlag("arrhythmia", "Other")], selection: arrhythmiaKinds(s))
            if r.has("af") { row("AF type") { PatientChoice(options: HistorySections.afTypes, selection: hx(\.afType)) } }
            if r.has("arrhythmia") { HistoryInlineField(prompt: "Type, e.g. SVT, heart block", text: text(\.arrhythmiaType)) }
        case "device":
            PatientChips(options: [PatientFlag("pacemaker", "Pacemaker"), PatientFlag("icd", "ICD"), PatientFlag("dependent", "Pacer dependent")], selection: deviceChips(s))
            row("Generator") { PatientChoice(options: HistorySections.leftRight, selection: hx(\.ciedSide)) }
            HistoryInlineField(prompt: "Details, e.g. make, magnet response", text: text(\.deviceDetails))
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
        case "stroke":
            PatientChoice(options: [(id: "cva-recent", label: "Within 3 months"), (id: "cva", label: "Over 3 months")], selection: choice(["cva-recent", "cva"], s))
        case "ich":
            PatientChips(options: [PatientFlag("ich-mass", "With mass effect")], selection: options(["ich-mass"], s))
        case "asthma":
            PatientChoice(options: [(id: "controlled", label: "Controlled"), (id: "uncontrolled", label: "Uncontrolled")], selection: asthmaControl(s))
        case "osa":
            PatientChoice(options: [(id: "none", label: "Not on CPAP"), (id: "cpap", label: "CPAP/BiPAP")], selection: osaTherapy)
            if r.has("cpap") { HistoryInlineField(prompt: "Home settings, e.g. CPAP 10, BiPAP 14/8", text: text(\.cpapSettings)) }
        case "resp-infection":
            PatientChips(options: [PatientFlag("uri", "URI"), PatientFlag("pneumonia", "Pneumonia"), PatientFlag("resp-infection-other", "Other")],
                         selection: options(["uri", "pneumonia", "resp-infection-other"], s))
            if r.has("resp-infection-other") { HistoryInlineField(prompt: "Type", capitalizes: true, text: text(\.respInfectionType)) }
        case "home-o2":
            PatientNumberField(label: "Flow", unit: "L/min", value: Binding(get: { patient.record.hx.homeO2Flow }, set: { v in edit { $0.hx.homeO2Flow = v } }))
                .padding(.horizontal, -14)
        case "pleural":
            pleural(s)
        case "visual":
            PatientChoice(options: HistorySections.acuteChronic, selection: hx(\.visualImpairment))
        case "psych":
            PatientChips(options: [PatientFlag("mdd", "MDD"), PatientFlag("anxiety", "Anxiety"), PatientFlag("other", "Other")],
                         selection: optionsWithOther(["mdd", "anxiety"], s, key: "psych-other", text: \.psychOther))
            if otherOpen("psych-other", \.psychOther) { HistoryInlineField(prompt: "Other, e.g. bipolar disorder", text: text(\.psychOther)) }
        default:
            EmptyView()
        }
    }

    private var endocarditisField: some View {
        HistoryInlineField(prompt: "Valve, organism, treatment", text: text(\.endocarditisDetails))
    }

    /// AF/flutter and Other: the AF type and the typed type go with their chip.
    private func arrhythmiaKinds(_ s: HistorySection) -> Binding<Set<String>> {
        Binding(get: { patient.record.problems.intersection(["af", "arrhythmia"]) }, set: { new in
            edit { r in
                for id in ["af", "arrhythmia"] where new.contains(id) != r.problems.contains(id) { HistorySections.setOption(id, new.contains(id), in: s, &r) }
                if !new.contains("af") { r.hx.afType = nil }
                if !new.contains("arrhythmia") { r.hx.arrhythmiaType = "" }
            }
        })
    }

    /// Pacemaker, ICD and Pacer dependent (hx.pacerDependent) on one line.
    private func deviceChips(_ s: HistorySection) -> Binding<Set<String>> {
        Binding(get: {
            var v = patient.record.problems.intersection(["pacemaker", "icd"])
            if patient.record.hx.pacerDependent { v.insert("dependent") }
            return v
        }, set: { new in
            edit { r in
                for id in ["pacemaker", "icd"] where new.contains(id) != r.problems.contains(id) { HistorySections.setOption(id, new.contains(id), in: s, &r) }
                r.hx.pacerDependent = new.contains("dependent")
            }
        })
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

    // MARK: Pleural effusion or pneumothorax (1.9)

    @ViewBuilder private func pleural(_ s: HistorySection) -> some View {
        PatientChips(options: [PatientFlag("pleural-effusion", "Pleural effusion"), PatientFlag("pneumothorax", "Pneumothorax")], selection: Binding(
            get: { patient.record.problems.intersection(["pleural-effusion", "pneumothorax"]) },
            set: { new in
                edit { r in
                    for id in ["pleural-effusion", "pneumothorax"] where new.contains(id) != r.problems.contains(id) { HistorySections.setOption(id, new.contains(id), in: s, &r) }
                    if !new.contains("pleural-effusion") { r.hx.pleuralFluid = nil }
                }
            }))
        row("Side") { PatientChoice(options: HistorySections.pleuralSides, selection: hx(\.pleuralSide)) }
        if r.has("pleural-effusion") { row("Fluid") { PatientChoice(options: HistorySections.pleuralFluids, selection: hx(\.pleuralFluid)) } }
        row("Drained") { PatientChoice(options: Self.noYes, selection: yesNo({ $0.hx.pleuralDrained }, HistorySections.setPleuralDrained)) }
        if r.hx.pleuralDrained == true {
            row("Chest tube in place") { PatientChoice(options: Self.noYes, selection: yesNo({ $0.hx.chestTube }, HistorySections.setChestTube)) }
            if r.hx.chestTube == true {
                row("Chest tube side") { PatientChips(options: flags(HistorySections.leftRight), selection: hxSet(\.chestTubeSides)) }
            }
        }
    }

    // MARK: Renal, GI & liver, Endocrine (1.9)

    @ViewBuilder private func renalGIEndo(_ s: HistorySection) -> some View {
        switch s.id {
        case "ckd":
            row("Stage") { PatientChoice(options: HistorySections.ckdStages, selection: hx(\.ckdStage)) }
            PatientChips(options: [PatientFlag("esrd-no-dialysis", "ESRD, not on scheduled dialysis")], selection: options(["esrd-no-dialysis"], s))
        case "prostate":
            PatientChips(options: [PatientFlag("bph", "BPH"), PatientFlag("prostate-cancer", "Prostate cancer")], selection: options(["bph", "prostate-cancer"], s))
        case "hemodialysis":
            row("Schedule") { PatientChoice(options: HistorySections.dialysisSchedules + [(id: "other", label: "Other")], selection: dialysisSchedule) }
            if r.hx.dialysisSchedule == nil && otherOpen("hd-other", \.dialysisScheduleOther) {
                HistoryInlineField(prompt: "Schedule, e.g. nightly at home", text: text(\.dialysisScheduleOther))
            }
            row("Access") {
                PatientChips(options: flags(HistorySections.dialysisAccesses), selection: Binding(
                    get: { patient.record.hx.dialysisAccess }, set: { v in edit { HistorySections.setDialysisAccess(v, &$0) } }))
            }
            if r.hx.dialysisAccess.contains("fistula") { labeled("Fistula", "Location, e.g. left forearm", text(\.fistulaSite)) }
            if r.hx.dialysisAccess.contains("catheter") { labeled("Catheter", "Location, e.g. right IJ tunneled", text(\.dialysisCatheterSite)) }
        case "gastric-bypass":
            HistoryInlineField(prompt: "Details, e.g. Roux-en-Y 2018", text: text(\.gastricBypassDetails))
        case "esophageal":
            PatientChips(options: [PatientFlag("dysphagia", "Dysphagia"), PatientFlag("esophageal-disorder", "Esophageal disorder")], selection: Binding(
                get: { patient.record.problems.intersection(["dysphagia", "esophageal-disorder"]) },
                set: { new in
                    edit { r in
                        for id in ["dysphagia", "esophageal-disorder"] where new.contains(id) != r.problems.contains(id) { HistorySections.setOption(id, new.contains(id), in: s, &r) }
                        if !new.contains("esophageal-disorder") { r.hx.esophagealDisorderType = "" }
                    }
                }))
            if r.has("esophageal-disorder") { HistoryInlineField(prompt: "Type, e.g. achalasia, stricture", text: text(\.esophagealDisorderType)) }
            row("Previous esophageal procedure") {
                PatientChoice(options: Self.noYes, selection: yesNo({ $0.hx.esophagealProcedure }, { v, r in
                    r.hx.esophagealProcedure = v
                    if v != true { r.hx.esophagealProcedureDetails = "" }
                }))
            }
            if r.hx.esophagealProcedure == true { HistoryInlineField(prompt: "e.g. stent, dilation, resection", text: text(\.esophagealProcedureDetails)) }
        case "cirrhosis":
            let liver = PatientSummary.liverLine(r)
            if let liver { LinkedValues(text: liver.text, alert: liver.alert) }
            labsLink(liver == nil ? "Add liver function testing (MELD + CTP)" : "Liver function testing", group: "liver", add: liver == nil)
        case "gi-bleed":
            row("Status") { PatientChoice(options: HistorySections.giBleedStatuses, selection: hx(\.giBleedStatus)) }
            row("Site") { PatientChoice(options: HistorySections.giBleedSites, selection: hx(\.giBleedSite)) }
            HistoryInlineField(prompt: "Details", text: text(\.giBleedDetails))
        case "dm":
            PatientChoice(options: [(id: "insulin", label: "On insulin"), (id: "none", label: "Not on insulin")], selection: Binding(
                get: { HistorySections.diabetesInsulin(patient.record) }, set: { v in edit { HistorySections.setDiabetesInsulin(v, &$0) } }))
        case "thyroid":
            PatientChoice(options: HistorySections.thyroidTypes, selection: hx(\.thyroidType))
            let tft = thyroidValues
            if !tft.isEmpty { LinkedValues(parts: tft) }
            labsLink(tft.isEmpty ? "Add thyroid function tests" : "Thyroid function tests", group: "thyroid", add: tft.isEmpty)
        case "adrenal":
            adrenal
        default:
            EmptyView()
        }
    }

    /// M/W/F, Tu/Th/Sa, or Other with the schedule typed.
    private var dialysisSchedule: Binding<String?> {
        Binding(get: {
            patient.record.hx.dialysisSchedule ?? (otherOpen("hd-other", \.dialysisScheduleOther) ? "other" : nil)
        }, set: { v in
            if v == "other" { opened.insert("hd-other") } else { opened.remove("hd-other") }
            edit { r in
                r.hx.dialysisSchedule = v == "other" ? nil : v
                if v != "other" { r.hx.dialysisScheduleOther = "" }
            }
        })
    }

    /// TSH and free T4 as Labs holds them, out-of-range ones marked.
    private var thyroidValues: [(text: String, abnormal: Bool)] {
        ["tsh", "ft4"].compactMap { key in
            guard let v = r.labs[key], let t = PatientLabs.test(key) else { return nil }
            let flag = PatientLabs.flag(key, v, sex: r.sex)
            return (t.short + " " + t.format(v) + (t.unit.isEmpty ? "" : " " + t.unit) + (flag.isAbnormal ? " " + flag.mark : ""), flag.isAbnormal)
        }
    }

    @ViewBuilder private var adrenal: some View {
        PatientChips(options: flags(HistorySections.adrenalKinds), selection: hxSet(\.adrenalKinds))
        // A menu, not six chips on three lines (1.9, de-cluttered).
        row("Drug") {
            let pick = steroidDrug
            Menu {
                ForEach(PatientSteroids.drugs, id: \.self) { d in Button(d) { patient.markDiscrete(); pick.wrappedValue = d } }
                Button("Other") { patient.markDiscrete(); pick.wrappedValue = "other" }
                if pick.wrappedValue != nil { Button("Clear", role: .destructive) { patient.markDiscrete(); pick.wrappedValue = nil } }
            } label: {
                HStack(spacing: 5) {
                    Text(pick.wrappedValue.map { $0 == "other" ? "Other" : $0 } ?? "Choose")
                    Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 10, weight: .semibold))
                }
                .font(PS.sys(size: 13.5, weight: .semibold))
                .foregroundStyle(pick.wrappedValue == nil ? PS.fg2 : PS.fg)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(PS.surface2, in: Capsule())
                .overlay(Capsule().stroke(PS.line2, lineWidth: 1))
            }
            .accessibilityLabel("Glucocorticoid")
        }
        if !PatientSteroids.drugs.contains(r.hx.steroidDrug) && otherOpen("steroid-other", \.steroidDrug) {
            HistoryInlineField(prompt: "Glucocorticoid", text: text(\.steroidDrug))
        }
        PatientNumberField(label: "Daily dose", unit: "mg/day", value: number(\.steroidDailyMg)).padding(.horizontal, -14)
        row("Duration") { PatientChoice(options: PatientSteroids.durations, selection: hx(\.steroidDuration)) }
        if let a = PatientSteroids.advice(r) { SteroidAdviceBox(advice: a, sourceOpen: info("steroid-source")) }
    }

    /// A drug from the quick picks, or Other with the drug typed.
    private var steroidDrug: Binding<String?> {
        Binding(get: {
            let d = patient.record.hx.steroidDrug
            return PatientSteroids.drugs.contains(d) ? d : (otherOpen("steroid-other", \.steroidDrug) ? "other" : nil)
        }, set: { v in
            if v == "other" { opened.insert("steroid-other") } else { opened.remove("steroid-other") }
            edit { r in r.hx.steroidDrug = (v == "other" || v == nil) ? "" : (v ?? "") }
        })
    }

    // MARK: Hematologic, Infectious (1.9)

    @ViewBuilder private func hemeInfectious(_ s: HistorySection) -> some View {
        switch s.id {
        case "anemia":
            labRow("hb")
            labRow("hct")
        case "thrombocytopenia":
            labRow("plt")
            labsLink("Add CBC and coagulation studies", group: nil)
        case "bleeding":
            PatientChips(options: HistorySections.bleedingKinds.map { PatientFlag($0.id, $0.label) } + [PatientFlag("other", "Other")],
                         selection: optionsWithOther(HistorySections.bleedingKinds.map(\.id), s, key: "bleeding-other", text: \.bleedingOther))
            if otherOpen("bleeding-other", \.bleedingOther) { HistoryInlineField(prompt: "Other, e.g. factor VII deficiency", text: text(\.bleedingOther)) }
            labsLink("Add CBC and coagulation studies", group: nil)
        case "thrombophilia":
            PatientChips(options: [PatientFlag("fvl", "Factor V Leiden"), PatientFlag("other", "Other")],
                         selection: optionsWithOther(["fvl"], s, key: "thrombophilia-other", text: \.thrombophiliaOther))
            if otherOpen("thrombophilia-other", \.thrombophiliaOther) { HistoryInlineField(prompt: "Other, e.g. prothrombin G20210A", text: text(\.thrombophiliaOther)) }
        case "anticoagulation":
            PatientChips(options: flags(HistorySections.anticoagulantKinds), selection: Binding(
                get: { Set(patient.record.hx.anticoagulants.keys) },
                set: { new in edit { r in for k in HistorySections.anticoagulantKinds.map(\.id) { HistorySections.setAnticoagulant(k, new.contains(k), &r) } } }))
            ForEach(HistorySections.anticoagulantKinds.filter { r.hx.anticoagulants[$0.id] != nil }, id: \.id) { k in anticoagulant(k.id, k.label) }
        case "declines-blood":
            HistoryInlineField(prompt: "What is accepted, e.g. albumin, cell saver", text: text(\.declinesBloodDetails))
        case "vte":
            row("Timing") { PatientChoice(options: HistorySections.acuteChronic, selection: hx(\.vteTiming)) }
            labeled("Date", "e.g. 09/2026", text(\.vteDate))
            PatientChips(options: [PatientFlag("anticoagulation", "On anticoagulation")], selection: onAnticoagulation)
        // Infectious
        case "sepsis":
            labeled("Source", "e.g. pneumonia, urinary", text(\.sepsisSource))
        case "hiv":
            labeled("Viral load", "e.g. undetectable", text(\.hivViralLoad))
        case "hepatitis":
            row("Type") { PatientChips(options: flags(HistorySections.hepatitisTypes), selection: hxSet(\.hepatitisTypes)) }
        case "covid":
            row("Status") { PatientChoice(options: HistorySections.covidStatuses, selection: hx(\.covidStatus)) }
            labeled("Positive test", "Date, e.g. 10/28", text(\.covidTestDate))
        case "tb":
            PatientChoice(options: HistorySections.tbStatuses, selection: hx(\.tbStatus))
        case "endocarditis":
            endocarditisField
        case "isolation":
            PatientChips(options: flags(PatientPrecautions.kinds), selection: hxSet(\.precautions))
        default:
            EmptyView()
        }
    }

    /// The On anticoagulation item, chosen or cleared from DVT/PE.
    private var onAnticoagulation: Binding<Set<String>> {
        Binding(get: { patient.record.has("anticoagulation") ? ["anticoagulation"] : [] }, set: { new in
            guard let item = HistorySections.heme.first(where: { $0.id == "anticoagulation" }) else { return }
            edit { r in if new.isEmpty { HistorySections.clear(item, system: "heme", &r) } else { HistorySections.select(item, &r) } }
        })
    }

    private func anticoagulant(_ kind: String, _ label: String) -> some View {
        func field(_ kp: WritableKeyPath<PatientAnticoagulant, String>) -> Binding<String> {
            Binding(get: { patient.record.hx.anticoagulants[kind]?[keyPath: kp] ?? "" }, set: { v in
                edit { r in var a = r.hx.anticoagulants[kind] ?? PatientAnticoagulant(); a[keyPath: kp] = v; r.hx.anticoagulants[kind] = a }
            })
        }
        let intensity = Binding<String?>(get: { patient.record.hx.anticoagulants[kind]?.intensity }, set: { v in
            edit { r in var a = r.hx.anticoagulants[kind] ?? PatientAnticoagulant(); a.intensity = v; r.hx.anticoagulants[kind] = a }
        })
        return VStack(alignment: .leading, spacing: 6) {
            // Heparin and enoxaparin: therapeutic or prophylactic dosing changes the neuraxial and bleeding plan.
            if kind == "heparin" || kind == "enoxaparin" {
                row(label) { PatientChoice(options: HistorySections.intensities, selection: intensity) }
            } else {
                Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            }
            if kind == "other" { labeled("Drug", "e.g. apixaban 5 mg BID", field(\.name)) }
            labeled("Last dose", "e.g. 11/03 21:00", field(\.lastDose))
            if kind == "warfarin" { labRow("inr") }
        }
        .padding(10)
        .background(PS.surface2.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Acute illness, Obstetric (1.9)

    @ViewBuilder private func acuteOB(_ s: HistorySection) -> some View {
        switch s.id {
        case "sepsis":
            labeled("Source", "e.g. pneumonia, urinary", text(\.sepsisSource))
            row("Shock") { PatientChoice(options: Self.noYes, selection: sepsisShock) }
            labeled("Antibiotic", "e.g. piperacillin-tazobactam", text(\.sepsisAntibiotic))
        case "shock":
            PatientChips(options: flags(HistorySections.shockTypes), selection: hxSet(\.shockTypes))
            currentSupport
        case "trauma":
            PatientChips(options: [PatientFlag("massive-trauma", "Massive trauma"), PatientFlag("burn", "Major burn")], selection: options(["massive-trauma", "burn"], s))
            HistoryInlineField(prompt: "Details", text: text(\.traumaDetails))
        case "aorta-acute":
            row("Dissection") { PatientChoice(options: [(id: "dissection-a", label: "Type A"), (id: "dissection-b", label: "Type B")], selection: choice(["dissection-a", "dissection-b"], s)) }
            // A ruptured aneurysm recorded by site on Cardiovascular is shown under the item instead (offers).
            if HistorySections.fromCardiovascular(r).isEmpty || r.has("ruptured-aneurysm") {
                PatientChips(options: [PatientFlag("ruptured-aneurysm", "Aortic rupture")], selection: options(["ruptured-aneurysm"], s))
            }
        case "pregnant":
            pregnancy
        case "preeclampsia":
            PatientChoice(options: [(id: "without", label: "Without severe features"), (id: "with", label: "With severe features")], selection: Binding(
                get: { HistorySections.preeclampsiaSeverity(patient.record) }, set: { v in edit { HistorySections.setPreeclampsiaSeverity(v, &$0) } }))
            if HistorySections.preeclampsiaSeverity(r) == "with" {
                PatientChips(options: HistorySections.preeclampsiaFeatures.map { PatientFlag($0.id, $0.label) }, selection: Binding(
                    get: { patient.record.hx.preeclampsiaFeatures.union(patient.record.has("hellp") ? ["hellp"] : []) },
                    set: { v in edit { HistorySections.setPreeclampsiaFeatures(v, &$0) } }))
                if !r.hx.preeclampsiaFeatures.isDisjoint(with: ["thrombocytopenia", "hellp"]) || r.has("hellp") {
                    labsLink("Add CBC", group: nil)
                }
            }
        case "gdm":
            row("Control") { PatientChoice(options: HistorySections.gdmControls, selection: hx(\.gdmControl)) }
            PatientChips(options: gdmOptions, selection: gdmChips(s))
        case "ppcm":
            PatientNumberField(label: "LVEF", unit: "%", value: Binding(get: { patient.record.hx.ppcmEF }, set: { v in edit { HistorySections.setPPCMEF(v, &$0) } }))
                .padding(.horizontal, -14)
        case "placenta":
            PatientChips(options: flags(HistorySections.placentaKinds), selection: hxSet(\.placenta))
        case "uterine-rupture":
            PatientChoice(options: [(id: "uterine-rupture", label: "Active"), (id: "uterine-rupture-past", label: "Past")], selection: choice(["uterine-rupture", "uterine-rupture-past"], s))
        case "thrombophilia":
            row("On anticoagulation?") {
                PatientChoice(options: Self.noYes, selection: yesNo({ HistorySections.obThrombophiliaAnticoag($0) }, HistorySections.setObThrombophiliaAnticoag))
            }
            if HistorySections.obThrombophiliaAnticoag(r) == true {
                NavigationLink(value: PatientEditor.system("heme")) { LinkLabel(title: "Add medication (Hematologic)", add: true) }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        if !patient.record.has("anticoagulation") { patient.update(discrete: true) { r in r.noHistory = false; r.problems.insert("anticoagulation") } }
                    })
            }
        default:
            EmptyView()
        }
    }

    /// Sepsis with shock: Yes adds the Shock item below; No takes it off. No is kept for the visit only (nothing to
    /// store: no shock is the default).
    private var sepsisShock: Binding<String?> {
        Binding(get: {
            patient.record.has("shock") ? "yes" : (opened.contains("sepsis-no-shock") ? "no" : nil)
        }, set: { v in
            if v == "no" { opened.insert("sepsis-no-shock") } else { opened.remove("sepsis-no-shock") }
            edit { HistorySections.setSepsisShock(v == "yes", &$0) }
        })
    }

    /// The infusions running now (Medications › Current infusions), with a link to add one.
    @ViewBuilder private var currentSupport: some View {
        let drips = r.homeInfusions.filter { !$0.drug.trimmingCharacters(in: .whitespaces).isEmpty }
        VStack(alignment: .leading, spacing: 4) {
            Text("Current support").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            ForEach(drips) { d in
                Text(d.drug + (d.rate.isEmpty ? "" : " " + d.rate)).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg)
            }
            NavigationLink(value: PatientEditor.medications) { LinkLabel(title: "Add infusion", add: true) }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var pregnancy: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                HistoryCountStepper(label: "G", value: count(\.gravida))
                HistoryCountStepper(label: "P", value: count(\.para))
            }
            GridRow {
                HistoryCountStepper(label: "A", value: count(\.abortus))
                HistoryCountStepper(label: "L", value: count(\.living))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gravida, para, abortus, living")
        HStack(spacing: 8) {
            Text("Gestation").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            Spacer(minLength: 6)
            HistoryIntField(label: "Weeks", value: count(\.gestationWeeks), limit: 45)
            Text("wk").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
            HistoryIntField(label: "Days", value: count(\.gestationDays), limit: 6)
            Text("d").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
        }
        row("Prior cesarean") {
            PatientChoice(options: Self.noYes, selection: yesNo({ $0.hx.priorCesarean }, { v, r in
                r.hx.priorCesarean = v
                if v != true { r.hx.cesareanLastBirth = nil }
            }))
        }
        if r.hx.priorCesarean == true {
            row("Was it the last birth?") { PatientChoice(options: Self.noYes, selection: yesNo(\.cesareanLastBirth)) }
        }
    }

    /// On insulin, Complications or high insulin needs (the ASA's class III example) and, as saved before 1.9,
    /// Diet-controlled.
    private var gdmOptions: [PatientFlag] {
        [PatientFlag("insulin", "On insulin"), PatientFlag("gdm-complex", "Complications or high insulin needs")]
            + (r.has("gdm-diet") ? [PatientFlag("gdm-diet", "Diet-controlled")] : [])
    }

    private func gdmChips(_ s: HistorySection) -> Binding<Set<String>> {
        Binding(get: {
            var v = patient.record.problems.intersection(["gdm-complex", "gdm-diet"])
            if patient.record.hx.gdmInsulin { v.insert("insulin") }
            return v
        }, set: { new in
            edit { r in
                r.hx.gdmInsulin = new.contains("insulin")
                for id in ["gdm-complex", "gdm-diet"] where new.contains(id) != r.problems.contains(id) { HistorySections.setOption(id, new.contains(id), in: s, &r) }
            }
        })
    }

    // MARK: Musculoskeletal, Smoking & substances (1.9)

    @ViewBuilder private func mskSocial(_ s: HistorySection) -> some View {
        switch s.id {
        case "arthritis":
            PatientChips(options: [PatientFlag("ra", "Rheumatoid"), PatientFlag("oa", "Osteoarthritis")], selection: options(["ra", "oa"], s))
            row("Location") {
                PatientChoice(options: [(id: "unspecified", label: "Unspecified")], selection: Binding(
                    get: { HistorySections.arthritisUnspecified(patient.record.hx) ? "unspecified" : nil },
                    set: { v in edit { $0.hx.arthritisLocation = v == nil ? "" : "Unspecified" } }))
            }
            if !HistorySections.arthritisUnspecified(r.hx) { HistoryInlineField(prompt: "Location, e.g. hands, knees", text: text(\.arthritisLocation)) }
        case "spine":
            PatientChips(options: [PatientFlag("spine-fusion", PatientCatalog.problem("spine-fusion")?.label ?? "Ankylosing spondylitis or cervical fusion"),
                                   PatientFlag("cspine-unstable", "Unstable C-spine"), PatientFlag("scoliosis", "Scoliosis")],
                         selection: options(["spine-fusion", "cspine-unstable", "scoliosis"], s))
        case "fracture":
            labeled("Location", "e.g. left femur", text(\.fractureLocation))
        case "ctd":
            PatientChips(options: [PatientFlag("marfan", "Marfan syndrome"), PatientFlag("eds", "Ehlers-Danlos syndrome")], selection: options(["marfan", "eds"], s))
            row("Valve disease or aortopathy?") { PatientChoice(options: Self.noYes, selection: yesNo(\.ctdCardiovascular)) }
            if r.hx.ctdCardiovascular == true {
                let words = HistorySections.cvValveAortaWords(r)
                if !words.isEmpty { LinkedValues(text: FreeText.cap(words.joined(separator: "; ")), alert: false) }
                NavigationLink(value: PatientEditor.system("cv")) {
                    LinkLabel(title: words.isEmpty ? "Add valve disease or aortopathy (Cardiovascular)" : "Cardiovascular", add: words.isEmpty)
                }
                .buttonStyle(.plain)
            }
        case "compartment":
            labeled("Location", "e.g. right forearm", text(\.compartmentLocation))
        case "smoking":
            PatientChoice(options: HistorySections.smokingStatuses, selection: Binding(
                get: { patient.record.smoking }, set: { v in edit { HistorySections.setSmoking(v, &$0) } }))
            if r.smoking == "former" {
                PatientNumberField(label: "Quit year", unit: "", value: whole(\.smokingQuitYear)).padding(.horizontal, -14)
            }
            if r.smoking == "former" || r.smoking == "current" {
                PatientNumberField(label: "Pack-years (estimated)", unit: "", value: number(\.packYears)).padding(.horizontal, -14)
            }
        case "alcohol":
            PatientChoice(options: HistorySections.alcoholAnswers, selection: Binding(
                get: { HistorySections.alcohol(patient.record) }, set: { v in edit { HistorySections.setAlcohol(v, &$0) } }))
        case "drugs":
            PatientChips(options: flags(HistorySections.drugs) + [PatientFlag("other", "Other")],
                         selection: optionsWithOther(HistorySections.drugs.map(\.id), s, key: "drugs-other", text: \.drugsOther))
            if otherOpen("drugs-other", \.drugsOther) { HistoryInlineField(prompt: "Other, e.g. benzodiazepines", text: text(\.drugsOther)) }
        default:
            EmptyView()
        }
    }

    // MARK: Under an item, chosen or not: suggestions and cross-references (1.9)

    @ViewBuilder private func offers(_ s: HistorySection) -> some View {
        switch s.id {
        case "isolation":
            ForEach(PatientPrecautions.suggestions(r)) { sg in
                let kind = PatientPrecautions.kinds.first { $0.id == sg.precaution }?.label ?? sg.precaution
                SuggestionRow(text: "Suggested: " + kind + " — " + sg.from.joined(separator: ", ") + " · tap to add", source: sg.source,
                              sourceOpen: info("precaution-" + sg.precaution)) {
                    patient.markDiscrete()
                    withAnimation(.snappy) { edit { PatientPrecautions.accept(sg, &$0) } }
                }
            }
        case "thyroid":
            if let t = PatientCrossFill.thyroidSuggestion(r) {
                SuggestionRow(text: t + " · tap to add", source: nil, sourceOpen: info("thyroid-suggestion")) {
                    patient.markDiscrete()
                    withAnimation(.snappy) { edit { PatientCrossFill.acceptThyroidSuggestion(&$0) } }
                }
            }
        case "aorta-acute":
            let cv = HistorySections.fromCardiovascular(r)
            if !cv.isEmpty { crossRow("From Cardiovascular", cv, to: .system("cv"), icon: nil) }
        default:
            EmptyView()
        }
    }

    /// What another page records for this one, display only; a tap opens that page.
    private func crossRow(_ title: String, _ items: [String], to: PatientEditor, icon: String?) -> some View {
        NavigationLink(value: to) {
            HStack(spacing: 12) {
                if let icon { Image(systemName: icon).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg3).frame(width: 22) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                    Text(FreeText.cap(items.joined(separator: "; "))).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
            }
            .padding(.leading, icon == nil ? 48 : 14).padding(.trailing, 14).padding(.vertical, icon == nil ? 6 : 10)
            .padding(.bottom, icon == nil ? 6 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the page it comes from")
    }

    /// A link to Labs; `group` opens that group there ("liver", "thyroid").
    private func labsLink(_ title: String, group: String?, add: Bool = true) -> some View {
        NavigationLink(value: PatientEditor.workup("labs")) { LinkLabel(title: title, add: add) }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                if let group, !patient.record.labSections.contains(group) { patient.update(discrete: true) { _ = $0.labSections.insert(group) } }
            })
    }

    /// One lab, typed here or in Labs (the same value), marked when out of range.
    @ViewBuilder private func labRow(_ key: String) -> some View {
        if let t = PatientLabs.test(key) {
            LabFieldRow(test: t, sex: r.sex, troponin99: r.labs["troponin99"], value: lab(key)).padding(.horizontal, -14)
        }
    }

    // MARK: Valves

    @ViewBuilder private var valves: some View {
        ForEach(PatientHistoryDetails.valveNames, id: \.id) { v in
            let x = r.hx.valve(v.id)
            VStack(alignment: .leading, spacing: 7) {
                row(v.label) {
                    PatientChips(options: flags(PatientHistoryDetails.lesions), selection: Binding(
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
            PatientChips(options: flags(sites), selection: Binding(get: { Set(patient.record.hx.aneurysms.keys) }, set: { new in
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
                Image(systemName: r.pft.isEmpty ? "plus.circle" : "lungs").font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.action).frame(width: 22)
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
    /// A free-standing note or item (not words inside a parenthesis): its first letter is capitalized when the field is left.
    var capitalizes = false
    /// What VoiceOver reads when the prompt is not the field's name (the closing fields, 1.9).
    var label: String? = nil
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $text, axis: .vertical)
            .lineLimit(1...4)
            .focused($focused)
            .onChange(of: focused) { _, now in if !now && capitalizes { let c = FreeText.cap(text); if c != text { text = c } } }
            .font(PS.sys(size: 14.5))
            .foregroundStyle(PS.fg)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .accessibilityLabel(label ?? prompt)
    }
}

// MARK: - Pieces of the 1.9 pages

/// Short red-tinted warnings beside an item ("Aspiration risk").
struct WarningTags: View {
    var tags: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { t in
                Text(t)
                    .font(PS.sys(size: 11, weight: .semibold))
                    .foregroundStyle(PS.red)
                    .lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(PS.red.opacity(0.12), in: Capsule())
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: " + tags.joined(separator: ", "))
    }
}

/// A link inside an item: "+ Add thyroid function tests", or an arrow when it opens what is already there.
struct LinkLabel: View {
    var title: String
    var add: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: add ? "plus.circle" : "arrow.right.circle").font(PS.sys(size: 13, weight: .semibold))
            Text(title).font(PS.sys(size: 13.5, weight: .semibold)).multilineTextAlignment(.leading)
        }
        .foregroundStyle(PS.action)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// Values another part of the record holds, shown in place ("MELD 3.0 18 · Child-Pugh B (8)").
struct LinkedValues: View {
    var parts: [(text: String, abnormal: Bool)]

    init(parts: [(text: String, abnormal: Bool)]) { self.parts = parts }
    init(text: String, alert: Bool) { parts = [(text, alert)] }

    private var line: Text {
        var t = Text("")
        for (i, p) in parts.enumerated() {
            if i > 0 { t = t + Text(" · ").foregroundColor(PS.fg3) }
            let part: Text = Text(p.text).foregroundColor(p.abnormal ? PS.red : PS.fg).fontWeight(p.abnormal ? .bold : .regular)
            t = t + part
        }
        return t
    }

    var body: some View {
        line
            .font(PS.sys(size: 13.5))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A one-tap suggestion under an item, with its source behind an ⓘ.
struct SuggestionRow: View {
    var text: String
    var source: String?
    @Binding var sourceOpen: Bool
    var accept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button { Haptics.light(); accept() } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "plus.circle").font(PS.sys(size: 12.5, weight: .semibold))
                        Text(text).font(PS.sys(size: 13.5, weight: .medium)).multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(PS.action)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if source != nil { InfoButton(open: $sourceOpen, label: "Source") }
                Spacer(minLength: 0)
            }
            if let source, sourceOpen { InfoCaptionText(text: source, font: PS.sys(size: 12)) }
        }
        .padding(.leading, 48).padding(.trailing, 14).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stress-dose steroid advice under Adrenal insufficiency or chronic steroids (PatientSteroids.advice), its source
/// behind an ⓘ.
struct SteroidAdviceBox: View {
    var advice: SteroidAdvice
    @Binding var sourceOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(advice.headline).font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(advice.atRisk ? PS.red : PS.fg)
                    .fixedSize(horizontal: false, vertical: true)
                InfoButton(open: $sourceOpen, label: "Source")
                Spacer(minLength: 0)
            }
            ForEach(advice.lines, id: \.self) { l in
                Text(l).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            }
            if sourceOpen { InfoCaptionText(text: advice.source, font: PS.sys(size: 11.5)) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface2.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A small count with − and + (G, P, A, L): − from empty gives 0, − from 0 clears it.
struct HistoryCountStepper: View {
    var label: String
    @Binding var value: Int?
    var limit = 20
    @Environment(PatientStore.self) private var store: PatientStore?

    private func set(_ v: Int?) {
        Haptics.light()
        store?.markDiscrete()
        value = v
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg2).frame(width: 14, alignment: .leading)
            Button { set(value.map { $0 > 0 ? $0 - 1 : nil } ?? 0) } label: {
                Image(systemName: "minus").font(PS.sys(size: 12, weight: .bold)).frame(width: 30, height: 30)
                    .foregroundStyle(PS.fg).background(PS.surface2, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Less")
            Text(value.map(String.init) ?? "—")
                .font(PS.sys(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(value == nil ? PS.fg3 : PS.fg)
                .frame(minWidth: 24)
            Button { set(min(limit, (value ?? 0) + 1)) } label: {
                Image(systemName: "plus").font(PS.sys(size: 12, weight: .bold)).frame(width: 30, height: 30)
                    .foregroundStyle(PS.fg).background(PS.surface2, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityValue(value.map(String.init) ?? "Not recorded")
    }
}

/// A small whole-number field (weeks, days of gestation).
struct HistoryIntField: View {
    var label: String
    @Binding var value: Int?
    var limit: Int
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("—", text: $text)
            .keyboardType(.numberPad)
            .focused($focused)
            .multilineTextAlignment(.center)
            .font(PS.sys(size: 16, weight: .semibold, design: .monospaced))
            .foregroundStyle(PS.fg)
            .frame(width: 44)
            .padding(.vertical, 6)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(label)
            .onAppear { text = value.map(String.init) ?? "" }
            .onChange(of: text) { _, t in
                let v = Int(t.trimmingCharacters(in: .whitespaces)).map { min($0, limit) }
                if v != value { value = v }
            }
            .onChange(of: value) { _, v in if Int(text.trimmingCharacters(in: .whitespaces)) != v { text = v.map(String.init) ?? "" } }
    }
}
