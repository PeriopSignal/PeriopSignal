import SwiftUI

// MARK: - Labs: the table, the ⊕ sections (cardiac, liver with MELD & Child-Turcotte-Pugh, thyroid) and the summary
//
// Values outside the reference range are bold red, in the fields and in the summary. Ranges and the scores' arithmetic
// and sources are in PatientLabs.

extension PatientEditorView {

    @ViewBuilder var labsEditor: some View {
        let sum = PatientLabs.summary(r)
        if !sum.isEmpty { LabFishboneView(summary: sum) }
        PatientGroup(title: "Labs") {
            labRows(PatientLabs.tests(.main))
            PatientTextField(label: "Other results", prompt: "Endocrine, rheumatological, lipids, etc.", text: bind(\.labNotes))
        }
        labSection("cardiac", "Add cardiac labs", PatientLabs.tests(.cardiac))
        if r.labSections.contains("liver") {
            liverGroup
        } else {
            labAdd("liver", "Add liver function testing (MELD & CTP)")
        }
        labSection("thyroid", "Add thyroid function tests", PatientLabs.tests(.thyroid))
        EvidenceNote("Reference ranges are typical adult ranges (ABIM Laboratory Test Reference Ranges, 2026; INR from MedlinePlus; GFR under 60 as KDIGO's decreased GFR); your laboratory's own ranges may differ. Natriuretic peptides and troponin are read as the 2024 AHA/ACC perioperative guideline reads them.")
    }

    @ViewBuilder private func labSection(_ id: String, _ add: String, _ tests: [LabTest]) -> some View {
        if r.labSections.contains(id) || tests.contains(where: { r.labs[$0.key] != nil }) {
            PatientGroup(title: tests.first?.group.title) { labRows(tests) }
        } else {
            labAdd(id, add)
        }
    }

    private func labAdd(_ id: String, _ title: String) -> some View {
        Button { withAnimation(.snappy) { patient.update(discrete: true) { _ = $0.labSections.insert(id) } } } label: { Label(title, systemImage: "plus.circle") }
            .font(PS.sys(size: 14.5, weight: .semibold))
            .buttonStyle(.borderless)
            .tint(PS.accent)
            .padding(.horizontal, 4)
    }

    @ViewBuilder private func labRows(_ tests: [LabTest]) -> some View {
        ForEach(Array(tests.enumerated()), id: \.element.id) { i, t in
            LabFieldRow(test: t, sex: r.sex, troponin99: r.labs["troponin99"], value: entry(\.labs, t.key))
            if i < tests.count - 1 { Hairline().padding(.leading, 14) }
        }
    }

    // MARK: Liver

    @ViewBuilder private var liverGroup: some View {
        let res = PatientLabs.liver(LiverInput(record: r, dialysis: r.dialysis, ascites: r.ascites, encephalopathy: r.encephalopathy))
        PatientGroup(title: "Liver function testing (MELD & CTP)") {
            labRows(["tbili", "albumin", "inr", "cr", "na"].compactMap { PatientLabs.test($0) })
            Hairline().padding(.leading, 14)
            PatientChipRow(label: "Ascites") {
                PatientChoice(options: LiverAscites.allCases.map { (id: $0.rawValue, label: $0.label) },
                              selection: Binding(get: { patient.record.ascites?.rawValue }, set: { v in patient.update { $0.ascites = v.flatMap { LiverAscites(rawValue: $0) } } }))
            }
            PatientChipRow(label: "Encephalopathy") {
                PatientChoice(options: LiverEncephalopathy.allCases.map { (id: $0.rawValue, label: $0.label) },
                              selection: Binding(get: { patient.record.encephalopathy?.rawValue }, set: { v in patient.update { $0.encephalopathy = v.flatMap { LiverEncephalopathy(rawValue: $0) } } }))
            }
            toggleRow("Dialysis", "Twice or more in the past week, or CVVHD for 24 h: creatinine counts as the cap", bind(\.dialysis))
        }
        HStack(spacing: 10) {
            scoreTile("MELD 3.0", res.meld3.map(String.init), alert: (res.meld3 ?? 0) >= 15)
            scoreTile("MELD-Na", res.meldNa.map(String.init), alert: (res.meldNa ?? 0) >= 15)
            scoreTile("Child-Pugh", res.childPughClass.map { "\($0.rawValue) · \(res.childPugh ?? 0)" }, alert: res.childPughClass.map { $0 != .a } ?? false)
        }
        if !res.missing.isEmpty {
            Text("Still needed: " + res.missing.joined(separator: ", ") + ".").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).padding(.horizontal, 4)
        }
        if !res.interpretation.isEmpty || !res.adjustments.isEmpty {
            EvidenceDisclosure {
                ForEach(res.adjustments + res.interpretation, id: \.self) { t in
                    Text(t).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
                Text("MELD 3.0: Kim WR et al., Gastroenterology 2021 (the OPTN allocation score since July 2023). MELD-Na: the OPTN 2016 formula. Child-Turcotte-Pugh: Pugh RN et al., Br J Surg 1973, with the FDA and AASLD-IDSA cut-offs.")
                    .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func scoreTile(_ title: String, _ value: String?, alert: Bool) -> some View {
        VStack(spacing: 4) {
            Text(title).font(PS.mono(size: 9.5, weight: .semibold)).textCase(.uppercase).foregroundStyle(PS.fg3).lineLimit(1).minimumScaleFactor(0.8)
            Text(value ?? "—").font(PS.sys(size: 22, weight: .bold, design: .rounded)).foregroundStyle(value == nil ? PS.fg3 : (alert ? PS.red : PS.fg))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Right heart catheterization results

    @ViewBuilder var rhcResults: some View {
        let h = r.rhc
        let res = PatientLabs.rightHeart(RightHeartInput(ra: h.ra, pasp: h.pasp, padp: h.padp, mpap: h.pam, pcwp: h.pcwp, co: h.co, bsa: r.bsa))
        let rows: [(String, String?, Bool)] = [
            ("Mean PA" + (res.mpapEstimated ? " (estimated)" : ""), res.mpap.map { NumText.short($0, places: 0) + " mmHg" }, (res.mpap ?? 0) > 20),
            ("Transpulmonary gradient", res.tpg.map { NumText.short($0, places: 0) + " mmHg" }, false),
            ("Diastolic pressure gradient", res.dpg.map { NumText.short($0, places: 0) + " mmHg" }, false),
            ("PVR", res.pvr.map { NumText.short($0, places: 1) + " WU" }, (res.pvr ?? 0) > 2),
            ("PAPI", res.papi.map { NumText.short($0, places: 2) }, !res.papiBelow.isEmpty),
            ("Cardiac index", res.ci.map { NumText.short($0, places: 2) + " L/min/m²" }, (res.ci ?? 9) < 2.2),
        ]
        if rows.contains(where: { $0.1 != nil }) {
            PatientGroup(title: "Calculated") {
                ForEach(Array(rows.filter { $0.1 != nil }.enumerated()), id: \.offset) { i, row in
                    HStack {
                        Text(row.0).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                        Spacer()
                        Text(row.1 ?? "").font(PS.sys(size: 15, weight: row.2 ? .bold : .semibold, design: .monospaced)).foregroundStyle(row.2 ? PS.red : PS.fg)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                if let t = res.phText {
                    Text(t).font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(res.ph?.isPH == true ? PS.red : PS.fg2)
                        .fixedSize(horizontal: false, vertical: true).padding(14)
                }
            }
            if !res.notes.isEmpty || !res.papiBelow.isEmpty {
                EvidenceDisclosure {
                    ForEach(res.papiBelow.map(\.text) + res.notes, id: \.self) { t in
                        Text(t).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Definitions: 2022 ESC/ERS pulmonary hypertension guideline (Humbert M et al., Eur Heart J 2022). Mean PA estimated as (PASP + 2 × PADP)/3 when not measured.")
                        .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if !res.missing.isEmpty && rows.contains(where: { $0.1 != nil }) {
            Text("For the rest: " + res.missing.joined(separator: ", ") + ".").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).padding(.horizontal, 4)
        }
    }
}

/// One lab: label, the value typed, the unit and the range; out of range shows bold red with L or H.
struct LabFieldRow: View {
    var test: LabTest
    var sex: PatientSex?
    var troponin99: Double?
    @Binding var value: Double?
    @State private var text = ""
    @FocusState private var focused: Bool

    private var flag: LabFlag { value.map { PatientLabs.flag(test.key, $0, sex: sex, troponin99: troponin99) } ?? .normal }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(test.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                if let range = test.rangeText(for: sex) {
                    Text(range + (test.unit.isEmpty ? "" : " " + test.unit)).font(PS.sys(size: 11)).foregroundStyle(PS.fg3)
                }
            }
            Spacer(minLength: 6)
            if flag.isAbnormal {
                Text(flag.mark).font(PS.sys(size: 12, weight: .heavy)).foregroundStyle(PS.red)
            }
            TextField("—", text: $text)
                .focused($focused)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(PS.sys(size: 16, weight: flag.isAbnormal ? .bold : .medium, design: .monospaced))
                .foregroundStyle(flag.isAbnormal ? PS.red : PS.fg)
                .frame(width: 84)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onChange(of: text) { _, t in
                    let v = Double(t.replacingOccurrences(of: ",", with: "."))
                    if v != value { value = v }
                }
            Text(test.unit).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 54, alignment: .leading).lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .onAppear { text = value.map { test.format($0) } ?? "" }
        // A change from elsewhere (Undo, a preset): show it, unless the text being typed already reads as it ("1."
        // while typing 1.5 stays as typed).
        .onChange(of: value) { _, v in
            if Double(text.replacingOccurrences(of: ",", with: ".")) != v { text = v.map { test.format($0) } ?? "" }
        }
    }
}

/// The lab fishbones (CBC and BMP) and the coagulation values; abnormal values bold red.
struct LabFishboneView: View {
    var summary: LabSummary

    private func cell(_ v: LabValue?, _ name: String) -> some View {
        VStack(spacing: 0) {
            Text(v?.text ?? "—")
                .font(PS.sys(size: 15, weight: v?.flag.isAbnormal == true ? .heavy : .semibold, design: .monospaced))
                .foregroundStyle(v == nil ? PS.fg3 : (v?.flag.isAbnormal == true ? PS.red : PS.fg))
            Text(name).font(PS.sys(size: 9)).foregroundStyle(PS.fg3)
        }
        .frame(minWidth: 40)
    }

    var body: some View {
        let f = summary.fishbone
        VStack(alignment: .leading, spacing: 14) {
            if f.hasCBC {
                HStack(spacing: 6) {
                    cell(f.wbc, "WBC")
                    Rectangle().fill(PS.line2).frame(width: 1.2, height: 34).rotationEffect(.degrees(25))
                    VStack(spacing: 2) {
                        cell(f.hb, "Hb")
                        Rectangle().fill(PS.line2).frame(width: 46, height: 1.2)
                        cell(f.hct, "Hct")
                    }
                    Rectangle().fill(PS.line2).frame(width: 1.2, height: 34).rotationEffect(.degrees(-25))
                    cell(f.plt, "Plt")
                }
            }
            if f.hasBMP {
                HStack(spacing: 4) {
                    VStack(spacing: 2) {
                        HStack(spacing: 0) {
                            cell(f.na, "Na"); Rectangle().fill(PS.line2).frame(width: 1.2, height: 28); cell(f.cl, "Cl"); Rectangle().fill(PS.line2).frame(width: 1.2, height: 28); cell(f.bun, "BUN")
                        }
                        Rectangle().fill(PS.line2).frame(height: 1.2)
                        HStack(spacing: 0) {
                            cell(f.k, "K"); Rectangle().fill(PS.line2).frame(width: 1.2, height: 28); cell(f.hco3, "HCO₃"); Rectangle().fill(PS.line2).frame(width: 1.2, height: 28); cell(f.cr, "Cr")
                        }
                    }
                    .fixedSize()
                    Image(systemName: "chevron.left").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(PS.line2).scaleEffect(x: -1)
                    cell(f.glucose, "Glu")
                }
            }
            if f.hasCoags {
                HStack(spacing: 16) {
                    if let i = f.inr { Text("INR ").font(PS.sys(size: 13)).foregroundStyle(PS.fg3) + Text(i.text).font(PS.sys(size: 14, weight: i.flag.isAbnormal ? .heavy : .semibold, design: .monospaced)).foregroundColor(i.flag.isAbnormal ? PS.red : PS.fg) }
                    if let fb = f.fibrinogen { Text("Fibrinogen ").font(PS.sys(size: 13)).foregroundStyle(PS.fg3) + Text(fb.text).font(PS.sys(size: 14, weight: fb.flag.isAbnormal ? .heavy : .semibold, design: .monospaced)).foregroundColor(fb.flag.isAbnormal ? PS.red : PS.fg) }
                }
            }
            let rest = summary.items.filter { !["wbc", "hb", "hct", "plt", "na", "k", "cl", "hco3", "bun", "cr", "glucose", "inr", "fibrinogen"].contains($0.key) }
            if !rest.isEmpty {
                PatientLineText(line: PatientSummary.Line(nil, rest.map(\.compact).joined(separator: " · "), marks: rest.filter { $0.flag.isAbnormal }.map(\.compact)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Labs: " + summary.line)
    }
}
