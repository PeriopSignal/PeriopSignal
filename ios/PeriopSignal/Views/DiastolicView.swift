import SwiftUI

/// ASE 2025 diastolic function: e′, E/e′ and PASP or TR first, the supplemental signs when they disagree,
/// E/A for the grade. Special populations take their own pathway or show the document's signs.
struct DiastolicView: View {
    @Environment(ReferenceStore.self) private var refs
    @Environment(PatientStore.self) private var myPatient
    var onOpen: (URL) -> Void

    @State private var population = LaunchSeed.string("ps.dd.pop").isEmpty ? "standard" : LaunchSeed.string("ps.dd.pop")
    @State private var ageBand = LaunchSeed.string("ps.dd.age")
    @State private var lungDisease = LaunchSeed.bool("ps.dd.lung")
    @State private var female = LaunchSeed.bool("ps.dd.female")
    @State private var values: [String: String] = Self.seededValues()
    @State private var showMore = LaunchSeed.bool("ps.dd.more")
    @State private var copied = false
    @FocusState private var focused: Bool

    private var data: DiastolicData? { refs.bundle?.diastolic }

    /// DEBUG screenshots: -ps.dd.pop standard -ps.dd.age 40-65 -ps.dd.values "E=100,A=80,eSeptal=5,eLateral=6,tr=3".
    private static func seededValues() -> [String: String] {
        var out: [String: String] = [:]
        for pair in LaunchSeed.list("ps.dd.values") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
    }

    /// Ar − A and the change in E/A with Valsalva can be zero or negative; the rest must be positive.
    private static let signed: Set<String> = ["ara", "valsalva"]
    private func num(_ k: String) -> Double? {
        let text = values[k] ?? ""
        guard Self.signed.contains(k) else { return WeightField.value(text) }
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "\u{2212}", with: "-")
        guard let v = Double(t), v.isFinite else { return nil }
        return v
    }

    private var input: DiastolicCalc.Input {
        var i = DiastolicCalc.Input()
        i.E = num("E"); i.A = num("A"); i.eSeptal = num("eSeptal"); i.eLateral = num("eLateral"); i.pasp = num("pasp"); i.tr = num("tr")
        i.lungDisease = lungDisease; i.ageBand = ageBand.isEmpty ? nil : ageBand
        i.pvsd = num("pvsd"); i.lars = num("lars"); i.lavi = num("lavi"); i.ivrt = num("ivrt")
        i.prEdv = num("prEdv"); i.padp = num("padp"); i.lwave = num("lwave"); i.ara = num("ara"); i.valsalva = num("valsalva")
        i.esr = num("esr"); i.lvmi = num("lvmi"); i.lvef = num("lvef"); i.female = female
        return i
    }

    private struct Field { var id: String; var label: String; var unit: String; var hint: String? }
    private static let main: [Field] = [
        Field(id: "E", label: "Mitral E velocity", unit: "cm/s", hint: "Pulsed Doppler at the leaflet tips"),
        Field(id: "A", label: "Mitral A velocity", unit: "cm/s"),
        Field(id: "eSeptal", label: "Septal e′", unit: "cm/s", hint: "Tissue Doppler"),
        Field(id: "eLateral", label: "Lateral e′", unit: "cm/s", hint: "Tissue Doppler"),
        Field(id: "pasp", label: "PA systolic pressure", unit: "mmHg", hint: "From TR velocity plus RAP; preferred when RAP can be estimated"),
        Field(id: "tr", label: "Peak TR velocity", unit: "m/s", hint: "Used when RAP cannot be estimated"),
    ]
    private static let supp: [Field] = [
        Field(id: "lvef", label: "LVEF", unit: "%", hint: "Below 50%: a pulmonary vein S/D above 0.67 counts as normal"),
        Field(id: "pvsd", label: "Pulmonary vein S/D", unit: "", hint: "Abnormal ≤ 0.67; above 0.67 settles nothing unless LVEF is reduced"),
        Field(id: "lars", label: "LA reservoir strain", unit: "%", hint: "Abnormal ≤ 18%; not with AF, significant MR, transplant, normal EF with GLS > 18%, or LA stunning"),
        Field(id: "lavi", label: "LA volume index", unit: "mL/m²", hint: "Abnormal > 34; not from athletes, anemia, AF or mitral disease"),
        Field(id: "ivrt", label: "IVRT", unit: "ms", hint: "Abnormal ≤ 70 ms; rate dependent"),
    ]
    private static let more: [Field] = [
        Field(id: "prEdv", label: "PR end-diastolic velocity", unit: "m/s", hint: "Abnormal ≥ 2 m/s"),
        Field(id: "padp", label: "PA diastolic pressure", unit: "mmHg", hint: "Abnormal ≥ 16 mmHg"),
        Field(id: "lwave", label: "Mitral L-wave", unit: "cm/s", hint: "Abnormal ≥ 50 cm/s"),
        Field(id: "ara", label: "Ar − A duration", unit: "ms", hint: "Abnormal > 30 ms with pulmonary vein Ar above 35 cm/s; reflects LVEDP"),
        Field(id: "valsalva", label: "Fall in E/A with Valsalva", unit: "%", hint: "Abnormal ≥ 50%; 0 or negative if E/A does not fall"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let d = data {
                    scopeCard(d)
                    patientCard(d)
                    let pop = d.populations.first { $0.id == population } ?? d.populations[0]
                    switch pop.mode {
                    case "main": mainPathway(d, pop)
                    case "mac", "transplant": shortPathway(d, pop)
                    default: listPathway(d, pop)
                    }
                    footer(d)
                } else {
                    Text("Loading the algorithm…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if myPatient.sex == .female && !LaunchSeed.bool("ps.dd.female") { female = true } }
        .navigationTitle("ASE Diastolic Function")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .sensoryFeedback(.success, trigger: copied)
    }

    // MARK: Scope and patient

    private func scopeCard(_ d: DiastolicData) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill").font(PS.sys(size: 12)).foregroundStyle(PS.accent)
            Text(d.scope).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PS.accent.opacity(0.35), lineWidth: 1))
    }

    private func patientCard(_ d: DiastolicData) -> some View {
        let pop = d.populations.first { $0.id == population } ?? d.populations[0]
        return VStack(alignment: .leading, spacing: 12) {
            Menu {
                ForEach(d.populations) { p in
                    Button { withAnimation(.snappy) { population = p.id } } label: {
                        if p.id == population { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "Patient")
                        Text(pop.name).font(PS.serif(size: 18)).foregroundStyle(PS.fg).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg3)
                }
                .contentShape(Rectangle())
            }
            if pop.mode == "main" {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("e′ cutoffs").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg2)
                        Text(ageBand.isEmpty ? "Any age" : "Table 6, by age").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
                    }
                    Spacer()
                    Picker("e′ cutoffs", selection: $ageBand) {
                        Text("Figure 3").tag("")
                        Text("Age 20–39").tag("20-39")
                        Text("Age 40–65").tag("40-65")
                        Text("Over 65").tag(">65")
                    }
                    .labelsHidden().pickerStyle(.menu).tint(PS.fg)
                }
                Toggle(isOn: $lungDisease) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lung or pulmonary vascular disease").font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                        Text("TR velocity and PASP then stop standing in for LAP").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                    }
                }
                .tint(PS.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    // MARK: Main algorithm (Figure 3)

    private func tone(_ r: DiastolicCalc.Reading) -> Color {
        switch r.lap {
        case .increased: return PS.accent
        case .lvedp: return Topics.info("mcs").fg
        case .normal: return r.grade == 1 ? Topics.info("trauma").fg : PS.green
        case .unknown: return PS.fg3
        }
    }

    @ViewBuilder private func mainPathway(_ d: DiastolicData, _ pop: DiastolicPopulation) -> some View {
        let r = DiastolicCalc.read(input)
        let t = tone(r)
        resultCard(tone: t) {
            HStack {
                Eyebrow(text: "ASE 2025 · Figure 3", color: t)
                Spacer()
                Button {
                    UIPasteboard.general.string = summary(r, d)
                    copied.toggle()
                } label: { Text("Copy") }
                .buttonStyle(GhostButtonStyle())
            }
            Text(r.headline).font(PS.serif(size: 23, weight: .semibold)).foregroundStyle(r.lap == .unknown ? PS.fg3 : PS.fg).fixedSize(horizontal: false, vertical: true)
            Text(r.explanation).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(r.steps) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(s.state == true ? PS.accent : (s.state == false ? PS.green : PS.fg3)).frame(width: 7, height: 7)
                        (Text(s.label).fontWeight(.semibold).foregroundColor(PS.fg) + Text("  " + s.text).foregroundColor(PS.fg2))
                            .font(PS.sys(size: 13)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if r.presence.state != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "info.circle").font(PS.sys(size: 11)).foregroundStyle(PS.accent2)
                    Text("Diastolic dysfunction (Figure 2): \(r.presence.text)\(r.presence.supportive ? "; LV mass index supports it" : "").")
                        .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(Array(r.cautions.enumerated()), id: \.offset) { _, c in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(PS.sys(size: 11)).foregroundStyle(PS.accent)
                    Text(c).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                }
            }
            readingWarning(d)
        }
        // §13A: test symptomatic patients with grade 1, normal LAP without a grade, or an undetermined reading; not grade 0
        let anyMain = [r.primaries.v1, r.primaries.v2, r.primaries.v3].contains { $0 != nil }
        if anyMain, r.grade == 1 || (r.lap == .normal && r.grade == nil) || r.lap == .unknown, let ex = d.exercise, !ex.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "If symptomatic: diastolic exercise echo").padding(.leading, 2)
                FactTable(rows: ex)
            }
        }
        if let ind = pop.indicators, !ind.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: pop.name + ": also look for").padding(.leading, 2)
                TakeHomeList(items: ind, size: 13.5)
                ForEach(pop.notes ?? [], id: \.self) { n in note(n) }
            }
        }
        let p = r.primaries
        fieldsCard("Main variables", Self.main, flags: ["eSeptal": p.eFlags.first ?? nil, "eLateral": p.eFlags.count > 1 ? p.eFlags[1] : nil, "pasp": p.v3ByTR ? nil : p.v3, "tr": p.v3ByTR ? p.v3 : nil])
        let derived = [p.EA.map { "E/A " + PedsCalc.fmt($0) }, p.ea.map { "average e′ " + PedsCalc.fmt($0) + " cm/s" }, p.ees.map { "septal E/e′ " + PedsCalc.fmt($0) }, p.eel.map { "lateral E/e′ " + PedsCalc.fmt($0) }, p.eea.map { "average E/e′ " + PedsCalc.fmt($0) }].compactMap { $0 }
        if !derived.isEmpty { note(derived.joined(separator: " · ")) }
        let reducedEF = DiastolicCalc.reducedEF(input) == true
        fieldsCard("Supplemental, when the main three disagree", Self.supp, flags: ["pvsd": num("pvsd").flatMap { $0 <= 0.67 ? true : (reducedEF ? false : nil) }, "lars": num("lars").map { $0 <= 18 }, "lavi": num("lavi").map { $0 > 34 }, "ivrt": num("ivrt").map { $0 <= 70 }])
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { showMore.toggle() } } label: {
                HStack {
                    Eyebrow(text: "If those are not available or reliable")
                    Spacer()
                    Image(systemName: showMore ? "chevron.up" : "chevron.down").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.fg3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showMore {
                fieldsCard(nil, Self.more, flags: ["prEdv": num("prEdv").map { $0 >= 2 }, "padp": num("padp").map { $0 >= 16 }, "lwave": num("lwave").map { $0 >= 50 }, "ara": num("ara").map { $0 > 30 }, "valsalva": num("valsalva").map { $0 >= 50 }])
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: "Supportive")
                Spacer()
                Picker("Sex", selection: $female) { Text("Male").tag(false); Text("Female").tag(true) }
                    .pickerStyle(.segmented).frame(width: 150)
            }
            fieldsCard(nil, [Field(id: "lvmi", label: "LV mass index", unit: "g/m²", hint: "Supports diastolic dysfunction above 95 (women) or 115 (men), not in athletes")], flags: ["lvmi": num("lvmi").map { female ? $0 > 95 : $0 > 115 }])
        }
    }

    // MARK: Annular calcification and transplant

    @ViewBuilder private func shortPathway(_ d: DiastolicData, _ pop: DiastolicPopulation) -> some View {
        let r = pop.mode == "mac" ? DiastolicCalc.mac(input) : DiastolicCalc.transplant(input)
        let t: Color = r.lap == .increased ? PS.accent : (r.lap == .normal ? PS.green : PS.fg3)
        resultCard(tone: t) {
            Eyebrow(text: pop.mode == "mac" ? "ASE 2025 · Figure 4" : "ASE 2025 · Section 15B", color: t)
            Text(r.headline).font(PS.serif(size: 23, weight: .semibold)).foregroundStyle(r.lap == .unknown ? PS.fg3 : PS.fg).fixedSize(horizontal: false, vertical: true)
            Text(r.explanation).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            readingWarning(d)
        }
        let fields: [Field] = pop.mode == "mac"
            ? [Field(id: "E", label: "Mitral E velocity", unit: "cm/s"), Field(id: "A", label: "Mitral A velocity", unit: "cm/s"), Field(id: "ivrt", label: "IVRT", unit: "ms", hint: "Decides when E/A is 0.8–1.8")]
            : [Field(id: "E", label: "Mitral E velocity", unit: "cm/s"), Field(id: "eSeptal", label: "Septal e′", unit: "cm/s"), Field(id: "eLateral", label: "Lateral e′", unit: "cm/s"), Field(id: "esr", label: "E/SRIVR", unit: "cm", hint: "Decides when average E/e′ is 7–14"), Field(id: "tr", label: "Peak TR velocity", unit: "m/s", hint: "When SRIVR cannot be measured")]
        fieldsCard("Measurements", fields, flags: [:])
        ForEach(pop.notes ?? [], id: \.self) { n in note(n) }
    }

    // MARK: Populations outside the algorithm

    @ViewBuilder private func listPathway(_ d: DiastolicData, _ pop: DiastolicPopulation) -> some View {
        resultCard(tone: PS.accent2) {
            Eyebrow(text: "Main algorithm does not apply", color: PS.accent2)
            Text(pop.name).font(PS.serif(size: 23, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
            Text("The 2025 document reads filling pressure in this group from its own signs, listed below; enter them in the report rather than a grade.")
                .font(PS.sys(size: 14)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            readingWarning(d)
        }
        if let ind = pop.indicators, !ind.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Signs of increased filling pressure").padding(.leading, 2)
                TakeHomeList(items: ind, size: 13.5)
            }
        }
        ForEach(pop.notes ?? [], id: \.self) { n in note(n) }
    }

    // MARK: Pieces

    private func resultCard<Content: View>(tone: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: PS.cardRadius, topTrailingRadius: PS.cardRadius)
                    .fill(tone.opacity(0.9)).frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            }
    }

    /// The guideline's scope on every reading: not for intraoperative use.
    @ViewBuilder private func readingWarning(_ d: DiastolicData) -> some View {
        if let w = d.readingWarning {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").font(PS.sys(size: 11)).foregroundStyle(PS.accent)
                Text(w).font(PS.sys(size: 12.5, weight: .medium)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
    }

    private func fieldsCard(_ title: String?, _ fields: [Field], flags: [String: Bool?]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Eyebrow(text: title).padding(.leading, 2) }
            VStack(spacing: 0) {
                ForEach(Array(fields.enumerated()), id: \.element.id) { i, fld in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fld.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                            if let h = fld.hint { Text(h).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                        }
                        Spacer(minLength: 6)
                        let flag = flags[fld.id] ?? nil
                        Circle().fill(flag == true ? PS.accent : (flag == false ? PS.green : Color.clear)).frame(width: 8, height: 8)
                        TextField("—", text: Binding(get: { values[fld.id] ?? "" }, set: { values[fld.id] = $0 }))
                            .keyboardType(Self.signed.contains(fld.id) ? .numbersAndPunctuation : .decimalPad)
                            .focused($focused)
                            .multilineTextAlignment(.trailing)
                            .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PS.fg)
                            .padding(.horizontal, 6).padding(.vertical, 5)
                            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .frame(width: 78)
                        Text(fld.unit).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 46, alignment: .leading)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    if i < fields.count - 1 { Hairline().padding(.leading, 14) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private func footer(_ d: DiastolicData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            Eyebrow(text: "Source")
            Text(d.source.citation).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            if let u = d.source.url, let url = URL(string: u) {
                Button { onOpen(url) } label: { Text("Open the guideline ↗") }.buttonStyle(TextButtonStyle(color: PS.accent, size: 13.5))
            }
            ForEach([d.supersedes, d.validation].compactMap { $0 } + (d.notes ?? []), id: \.self) { n in
                Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func summary(_ r: DiastolicCalc.Reading, _ d: DiastolicData) -> String {
        let p = r.primaries
        var parts: [String] = []
        if let v = p.E { parts.append("E \(PedsCalc.fmt(v)) cm/s") }
        if let v = p.A { parts.append("A \(PedsCalc.fmt(v)) cm/s") }
        if let v = p.EA { parts.append("E/A \(PedsCalc.fmt(v))") }
        if let v = p.es { parts.append("septal e′ \(PedsCalc.fmt(v))") }
        if let v = p.el { parts.append("lateral e′ \(PedsCalc.fmt(v))") }
        if let v = p.eea { parts.append("average E/e′ \(PedsCalc.fmt(v))") }
        if let v = num("pasp") { parts.append("PASP \(PedsCalc.fmt(v)) mmHg") }
        if let v = num("tr") { parts.append("TR \(PedsCalc.fmt(v)) m/s") }
        for fld in Self.supp + Self.more { if let v = num(fld.id) { parts.append("\(fld.label) \(PedsCalc.fmt(v))\(fld.unit.isEmpty ? "" : " " + fld.unit)") } }
        return "LV diastolic function (ASE 2025): \(r.headline). \(r.explanation)\n" + parts.joined(separator: "; ") + (d.readingWarning.map { "\n" + $0 } ?? "")
    }
}
