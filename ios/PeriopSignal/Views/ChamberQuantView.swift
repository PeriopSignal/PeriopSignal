import SwiftUI

/// Echo measurements in, the ASE reading out: sex, height and weight set the reference values and the
/// body surface area; each row shows its cutoffs as a strip with the value marked. Nothing is stored.
struct ChamberQuantView: View {
    @Environment(ReferenceStore.self) private var refs
    @Environment(PatientStore.self) private var myPatient
    var onOpen: (URL) -> Void
    @State private var changingPatient = false

    @State private var sex: EchoSex = EchoSex(rawValue: LaunchSeed.string("ps.echo.sex")) ?? .male
    @State private var heightText = LaunchSeed.string("ps.echo.height")
    @State private var weightText = LaunchSeed.string("ps.echo.weight")
    @State private var group: String? = LaunchSeed.string("ps.echo.group").isEmpty ? nil : LaunchSeed.string("ps.echo.group")
    @State private var values: [String: String] = Self.seededValues()
    @State private var ageText = LaunchSeed.string("ps.echo.age")
    @State private var raw: Set<String> = []
    @State private var ivcText = LaunchSeed.string("ps.echo.ivc")
    @State private var collapses: Bool?
    @State private var ventilated = LaunchSeed.bool("ps.echo.vent")
    @State private var paspText = LaunchSeed.string("ps.echo.pasp")

    private var data: EchoData? { refs.bundle?.echo }
    private var bsa: Double? { EchoCalc.bsa(heightCm: WeightField.value(heightText), weightKg: WeightField.value(weightText), formula: data?.bsaFormula) }
    private var ctx: EchoCalc.Context { EchoCalc.Context(age: WeightField.value(ageText), bsa: bsa) }

    /// DEBUG screenshots: -ps.echo.values "rvb=4.5,ta=42,tapse=1.3" -ps.echo.group rv -ps.echo.age 55 -ps.echo.vent 1
    /// -ps.echo.pasp 45.
    private static func seededValues() -> [String: String] {
        var out: [String: String] = [:]
        for pair in LaunchSeed.list("ps.echo.values") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
    }

    static func color(_ g: Int) -> Color {
        switch g {
        case 0: return PS.green
        case 1: return Topics.info("trauma").fg
        case 2: return Topics.info("mcs").fg
        case 3, 4: return PS.accent
        default: return PS.fg3
        }
    }

    var body: some View {
        ToolScroll {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 18) {
                    patient
                    if let d = data {
                        summary(d)
                        groupTabs(d)
                        if let g = currentGroup(d) { groupCard(g) }
                        if let ivc = d.ivc, ivc.group == currentGroup(d)?.id { ivcCard(ivc) }
                        if let cp = d.coupling, cp.group == currentGroup(d)?.id { couplingCard(cp).id("coupling") }
                        footer(d)
                    } else {
                        Text("Loading the reference values…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 30)
                .onAppear {
                    #if DEBUG
                    // Screenshot runs: -ps.echo.scroll coupling scrolls to that card.
                    let a = LaunchSeed.string("ps.echo.scroll")
                    if !a.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo(a, anchor: .top) }
                    }
                    #endif
                }
            }
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: fillFromPatient)
        .navigationTitle("ASE Chamber Quantification")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { Keyboard.dismiss() }
            }
        }
    }

    // MARK: Patient

    /// My Patient's age, sex, height and weight, as this tool writes them.
    private var patientValues: (sex: EchoSex?, height: String, weight: String, age: String) {
        let r = myPatient.record
        return (r.sex.map { $0 == .female ? EchoSex.female : EchoSex.male },
                r.heightCm.map { NumText.exact($0) } ?? "", r.weightKg.map { NumText.exact($0) } ?? "",
                r.ageYears.map { String(Int($0)) } ?? "")
    }

    /// The tool still holds My Patient's values, untouched.
    private var showsPatient: Bool {
        let p = patientValues
        guard p.sex != nil || !p.height.isEmpty || !p.weight.isEmpty else { return false }
        return !changingPatient && (p.sex == nil || p.sex == sex) && heightText == p.height && weightText == p.weight && ageText == p.age
    }

    private func fillFromPatient() {
        let p = patientValues
        guard heightText.isEmpty, weightText.isEmpty, ageText.isEmpty else { return }
        if let s = p.sex { sex = s }
        heightText = p.height
        weightText = p.weight
        ageText = p.age
    }

    @ViewBuilder private var patient: some View {
        if showsPatient {
            let p = patientValues
            let values = [p.age.isEmpty ? nil : p.age + " y", p.sex?.label, p.height.isEmpty ? nil : p.height + " cm", p.weight.isEmpty ? nil : p.weight + " kg"].compactMap { $0 }
            VStack(alignment: .leading, spacing: 8) {
                FromPatientLine(values: values, what: "age, sex, height and weight") { changingPatient = true }
                if let b = bsa {
                    Text("Body surface area \(EchoCalc.fmt(b)) m² (\(data?.bsaFormula == "mosteller" ? "Mosteller" : "DuBois")).")
                        .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).padding(.horizontal, 2)
                }
            }
        } else {
            patientFields
        }
    }

    private var patientFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Sex").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg2)
                Spacer()
                Picker("Sex", selection: $sex) {
                    ForEach(EchoSex.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            HStack(spacing: 12) {
                field("Height (cm)", text: $heightText)
                field("Weight (kg)", text: $weightText)
            }
            Group {
                if let b = bsa {
                    Text("Body surface area **\(EchoCalc.fmt(b)) m²** (\(data?.bsaFormula == "mosteller" ? "Mosteller" : "DuBois")). Indexed rows accept the raw value too, and rows with indexed cutoffs grade both.")
                } else {
                    Text("Height and weight give the body surface area for indexed values (volumes, mass, the indexed RV and annulus cutoffs); they clear when you leave.")
                }
            }
            .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        FocusBox { f in
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: label, size: 9.5)
                TextField("—", text: text)
                    .keyboardType(.decimalPad)
                    .focused(f)
                    .font(PS.sys(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PS.fg)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Summary

    /// A row's value graded, and graded again per m² when the row carries indexed cutoffs and BSA is known.
    private struct Reading {
        var v: Double?
        var g: Int?
        var ix: EchoMeasure?
        var iv: Double?
        var ig: Int?
        var worst: Int { max(g ?? -1, ig ?? -1) }
    }

    private func reading(_ m: EchoMeasure) -> Reading {
        let v = EchoCalc.value(m, text: values[m.id] ?? "", raw: raw.contains(m.id), bsa: bsa)
        let ix = EchoCalc.indexed(m)
        var iv: Double?
        if ix != nil, let v, let b = bsa { iv = v / b }
        return Reading(v: v, g: EchoCalc.grade(m, sex, v, ctx), ix: ix, iv: iv, ig: ix.flatMap { EchoCalc.grade($0, sex, iv) })
    }

    private struct Entry: Identifiable { var id: String { m.id }; var m: EchoMeasure; var r: Reading }

    private func entries(_ d: EchoData) -> [Entry] {
        d.groups.flatMap(\.measures).compactMap { m in
            let r = reading(m)
            return r.g == nil ? nil : Entry(m: m, r: r)
        }
    }

    private func summaryLabel(_ x: Entry) -> String {
        var s = EchoCalc.label(x.m, x.r.g ?? 0)
        if let ig = x.r.ig, let ix = x.r.ix, ig != x.r.g { s += " · indexed " + EchoCalc.label(ix, ig).lowercased() }
        return s
    }

    @ViewBuilder private func summary(_ d: EchoData) -> some View {
        let e = entries(d)
        if !e.isEmpty {
            // outside = abnormal, or outside the range on the harmless side (an LVEF above 72%)
            let outside = e.filter { $0.r.worst != 0 }
            let worst = e.map(\.r.worst).max() ?? 0
            let tone = worst > 0 ? Self.color(worst) : (outside.isEmpty ? PS.green : Self.color(-1))
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: sex == .female ? "Female reference values" : "Male reference values", color: tone)
                Text(outside.isEmpty ? (e.count == 1 ? "Within the Normal Range" : "All Entered Values Within the Normal Range") : "\(outside.count) of \(e.count) Outside the Normal Range")
                    .font(PS.serif(size: 22, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(e) { x in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Self.color(x.r.worst)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(x.m.short ?? x.m.name).font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg)
                                Text(summaryLabel(x)).font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(Self.color(x.r.worst))
                            }
                            Spacer(minLength: 6)
                            Text(EchoCalc.fmt(x.r.v ?? 0) + (x.m.unit.isEmpty ? "" : " " + x.m.unit)).font(PS.sys(size: 12.5, design: .monospaced)).foregroundStyle(PS.fg2)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: PS.cardRadius, topTrailingRadius: PS.cardRadius)
                    .fill(tone.opacity(0.9)).frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            }
        }
    }

    // MARK: Groups

    private func currentGroup(_ d: EchoData) -> EchoGroup? { d.groups.first { $0.id == group } ?? d.groups.first }

    private func groupTabs(_ d: EchoData) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(d.groups) { g in
                    let on = g.id == currentGroup(d)?.id
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { group = g.id }
                    } label: {
                        Text(g.short ?? g.name)
                            .font(PS.sys(size: 13.5, weight: .semibold))
                            .foregroundStyle(on ? PS.bg : PS.fg2)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(on ? PS.fg : PS.surface, in: Capsule())
                            .overlay(Capsule().stroke(on ? Color.clear : PS.line2, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func groupCard(_ g: EchoGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: g.name).padding(.leading, 2)
            VStack(spacing: 0) {
                if g.measures.contains(where: { $0.byAge != nil }) {
                    ageRow
                    Hairline().padding(.leading, 16)
                }
                ForEach(Array(g.measures.enumerated()), id: \.element.id) { i, m in
                    row(m)
                    if i < g.measures.count - 1 { Hairline().padding(.leading, 16) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            if let n = g.note {
                Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
            }
        }
    }

    private var ageRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Age").font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                Text("The aortic root limits are set by age and sex, then BSA").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            numberField($ageText)
            Text("years").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 46, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private func numberField(_ text: Binding<String>) -> some View {
        FocusBox { f in
            TextField("—", text: text)
                .keyboardType(.numberPad)
                .focused(f)
                .multilineTextAlignment(.trailing)
                .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(PS.fg)
                .padding(.horizontal, 6).padding(.vertical, 5)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
            .frame(width: 74)
    }

    private func rangeLine(_ m: EchoMeasure, _ c: EchoCalc.Context?, unit: String) -> String {
        EchoCalc.ranges(m, sex, c).map(\.text).joined(separator: " · ") + (unit.isEmpty ? "" : " " + unit)
    }

    private func row(_ m: EchoMeasure) -> some View {
        let isRaw = raw.contains(m.id)
        let text = values[m.id] ?? ""
        let r = reading(m)
        let unit = m.index == "bsa" && isRaw ? (m.rawUnit ?? m.unit.replacingOccurrences(of: "/m²", with: "")) : m.unit
        let hasRef = EchoCalc.ref(m, sex, ctx) != nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                    if let me = m.method { Text(me).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 6)
                // Strain rows take a negative entry, so they get the keyboard with a minus sign.
                FocusBox { f in
                    TextField("—", text: Binding(get: { values[m.id] ?? "" }, set: { values[m.id] = $0 }))
                        .keyboardType(m.abs == true ? .numbersAndPunctuation : .decimalPad)
                        .focused(f)
                        .multilineTextAlignment(.trailing)
                        .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PS.fg)
                        .padding(.horizontal, 6).padding(.vertical, 5)
                        .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                    .frame(width: 74)
                if m.index == "bsa" {
                    Button {
                        Haptics.light()
                        if isRaw { raw.remove(m.id) } else { raw.insert(m.id) }
                    } label: {
                        Text(unit).font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.accent2)
                            .padding(.horizontal, 6).padding(.vertical, 5)
                            .background(PS.accent2.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Switch between the indexed and the raw value")
                    .frame(minWidth: 52)
                } else {
                    Text(unit).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 46, alignment: .leading)
                }
            }
            if hasRef {
                EchoStrip(bands: EchoCalc.bands(m, sex, ctx), value: r.v)
                Text(rangeLine(m, ctx, unit: m.unit) + (m.ref.map { " · " + $0 } ?? ""))
                    .font(PS.sys(size: 12)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                if let lim = EchoCalc.ageLimit(m, sex, ctx) {
                    let band = lim.row.to.map { "\(lim.row.from)–\($0)" } ?? "\(lim.row.from) and over"
                    Text("\(sex == .female ? "Women" : "Men") \(band): upper limit \(EchoCalc.fmt(lim.base)) cm at BSA \(EchoCalc.fmt(lim.refBsa)) m²" + (lim.adjusted ? ", \(EchoCalc.fmt(lim.value)) cm at this patient's \(EchoCalc.fmt(bsa ?? 0)) m²." : "; add height and weight to adjust it for BSA."))
                        .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                }
            } else if m.byAge != nil {
                Text((WeightField.value(ageText) ?? 99) < 15 ? "The adult tables start at 15 years." : "Enter the age for the upper limit.").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
            } else {
                Text("No reference value for this sex.").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
            }
            if m.index == "bsa" && isRaw && !text.isEmpty && bsa == nil {
                Text("Enter height and weight to index this value.").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent)
            } else if let g = r.g {
                Text(EchoCalc.label(m, g) + (m.index == "bsa" && isRaw ? " · \(EchoCalc.fmt(r.v ?? 0)) \(m.unit)" : ""))
                    .font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(Self.color(g))
            }
            if let ix = r.ix {
                if let ig = r.ig, let iv = r.iv {
                    Text("Indexed \(EchoCalc.fmt(iv)) \(ix.unit): \(EchoCalc.label(ix, ig).lowercased())")
                        .font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(Self.color(ig))
                }
                Text("Indexed: " + rangeLine(ix, nil, unit: ix.unit) + (bsa == nil ? " · needs height and weight" : ""))
                    .font(PS.sys(size: 12)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            }
            if let n = m.note { Text(n).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    // MARK: Right-atrial pressure

    private func ivcCard(_ ivc: EchoIVC) -> some View {
        let rap = EchoCalc.rap(ivcCm: WeightField.value(ivcText), collapses: collapses, cut: ivc.cut, ventilated: ventilated, ventCut: ivc.ventCut)
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Right-atrial pressure from the IVC").padding(.leading, 2)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Breathing").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg2)
                    Spacer()
                    Picker("Breathing", selection: $ventilated) {
                        Text("Spontaneous").tag(false)
                        Text("Ventilated").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("IVC diameter").font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                        Text(ivc.method ?? "Subcostal, just proximal to the hepatic veins").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    FocusBox { f in
                        TextField("—", text: $ivcText)
                            .keyboardType(.decimalPad)
                            .focused(f)
                            .multilineTextAlignment(.trailing)
                            .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 5)
                            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                        .frame(width: 74)
                    Text("cm").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 46, alignment: .leading)
                }
                if !ventilated {
                    HStack {
                        Text("Collapses 50% or more with a sniff").font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Picker("Collapse", selection: Binding(get: { collapses.map { $0 ? 1 : 0 } ?? -1 }, set: { collapses = $0 < 0 ? nil : $0 == 1 })) {
                            Text("Yes").tag(1)
                            Text("No").tag(0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                }
                if let rap {
                    if let v = rap.value {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(v) mmHg").font(PS.serif(size: 28, weight: .semibold)).foregroundStyle(PS.fg)
                            Text("\(rap.label), \(rap.range ?? "")").font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg2)
                        }
                    } else {
                        Text(rap.label).font(PS.serif(size: 24, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                    }
                    if let d = rap.detail { Text(d).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true) }
                } else {
                    Text(ventilated ? "Enter the diameter." : "Enter the diameter and the collapse.").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
                }
                ForEach(ivc.notes ?? [], id: \.self) { n in
                    Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    // MARK: RV–PA coupling

    private func couplingCard(_ c: EchoCoupling) -> some View {
        let tapse = WeightField.value(values["tapse"] ?? "")
        let r = EchoCalc.coupling(tapseCm: tapse, pasp: WeightField.value(paspText), c)
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "RV–PA coupling: TAPSE/PASP").padding(.leading, 2)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PA systolic pressure").font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                        Text(c.method ?? "").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    FocusBox { f in
                        TextField("—", text: $paspText)
                            .keyboardType(.decimalPad)
                            .focused(f)
                            .multilineTextAlignment(.trailing)
                            .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 5)
                            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .frame(width: 74)
                    Text("mmHg").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 46, alignment: .leading)
                }
                if let r {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(EchoCalc.fmt(r.ratio) + " mm/mmHg").font(PS.serif(size: 28, weight: .semibold)).foregroundStyle(PS.fg)
                        Text(r.label).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(r.grade.map { Self.color($0) } ?? PS.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(r.detail).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text((tapse ?? 0) > 0 ? "Enter the PA systolic pressure." : "Enter TAPSE above and the PA systolic pressure.")
                        .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
                }
                ForEach(c.notes ?? [], id: \.self) { n in
                    Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                }
                if let ref = c.ref { Text(ref).font(PS.sys(size: 11.5, weight: .semibold)).foregroundStyle(PS.fg3) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    // MARK: Footer

    private func footer(_ d: EchoData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            Eyebrow(text: "Sources")
            ForEach(d.sources) { s in
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.citation).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    if let u = s.url, let url = URL(string: u) {
                        Button { onOpen(url) } label: { Text("Open ↗") }.buttonStyle(TextButtonStyle(color: PS.accent, size: 13))
                    }
                }
            }
            ForEach(d.notes ?? [], id: \.self) { n in
                Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
            Text("Reviewed \(d.reviewed.map { PSDate.monthYear($0) } ?? ""). A reference, not a report: measure the way the guideline describes, and read borderline values with the whole study.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The cutoffs as a colored strip (normal green, then mild, moderate, severe) with the value marked.
struct EchoStrip: View {
    var bands: [EchoCalc.Band]
    var value: Double?

    var body: some View {
        let from = bands.first?.from ?? 0, to = bands.last?.to ?? 1
        let span = max(to - from, 0.0001)
        let ticks = bands.dropLast().map(\.to)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(Array(bands.enumerated()), id: \.offset) { _, b in
                        Rectangle()
                            .fill(b.grade == -1 ? PS.surface3 : ChamberQuantView.color(b.grade).opacity(0.85))
                            .frame(width: max(0, w * (b.to - b.from) / span - 2))
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
                .offset(y: 4)
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, t in
                    Text(EchoCalc.fmt(t))
                        .font(PS.mono(size: 9.5, weight: .medium))
                        .foregroundStyle(PS.fg3)
                        .fixedSize()
                        .position(x: w * (t - from) / span, y: 23)
                }
                if let v = value {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(PS.fg)
                        .frame(width: 4, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).stroke(PS.surface, lineWidth: 1.5))
                        .position(x: min(max(0, (v - from) / span), 1) * w, y: 8)
                }
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}
