import SwiftUI

// MARK: - Studies: carotid ultrasound, radial artery ultrasound, pulmonary function tests
//
// The workup pages behind Assessment → Studies. Findings and key numbers, every field optional; a one-line summary
// under them, with the cautions the record raises (PatientStudies, Shared), each with its source behind ⓘ.

extension PatientEditorView {

    // MARK: Carotid ultrasound

    @ViewBuilder var carotidEditor: some View {
        carotidSide("Right", \.carotid.right)
        carotidSide("Left", \.carotid.left)
        PatientGroup(title: "ICA velocities") {
            SideBySideHeader()
            Hairline().padding(.leading, 14)
            SideBySideNumbers(label: "PSV", unit: "cm/s", right: bind(\.carotid.right.psv), left: bind(\.carotid.left.psv))
            Hairline().padding(.leading, 14)
            SideBySideNumbers(label: "EDV", unit: "cm/s", right: bind(\.carotid.right.edv), left: bind(\.carotid.left.edv))
        }
        studyDateNotes(date: bind(\.carotid.date), notes: bind(\.carotid.notes), prompt: "Plaque, CCA, ECA, comparison with the last study")
        if !r.carotid.isEmpty {
            summaryBox(r.carotid.summary)
            studyCautions(PatientStudies.cautions(r).filter { $0.id == "carotid" || $0.id.hasPrefix("vertebral") })
        }
        EvidenceNote(PatientStudies.carotidEvidence)
    }

    private func carotidSide(_ title: String, _ kp: WritableKeyPath<PatientRecord, CarotidSide>) -> some View {
        PatientGroup(title: title) {
            InfoChipRow(label: "ICA stenosis", info: PatientStudies.stenosisInfo) {
                PatientChoice(options: CarotidSide.stenoses, selection: bind(kp.appending(path: \.stenosis)))
            }
            Hairline().padding(.leading, 14)
            PatientChipRow(label: "Vertebral flow") {
                PatientChoice(options: CarotidSide.vertebralFlows, selection: bind(kp.appending(path: \.vertebral)))
            }
        }
    }

    // MARK: Radial artery ultrasound

    @ViewBuilder var radialEditor: some View {
        PatientGroup(title: "Planned harvest") {
            PatientChipRow(label: nil) {
                PatientChoice(options: PatientRadial.harvestOptions, selection: bind(\.radial.harvest), tint: PS.accent)
            }
        }
        PatientGroup(title: "Radial arteries") {
            SideBySideHeader()
            Hairline().padding(.leading, 14)
            SideBySideNumbers(label: "Inner diameter", unit: "mm", right: bind(\.radial.right.diameter), left: bind(\.radial.left.diameter))
            Hairline().padding(.leading, 14)
            SideBySideChoices(label: "Calcified", options: [(id: "no", label: "No"), (id: "yes", label: "Yes")],
                              right: calcified(\.radial.right.calcified), left: calcified(\.radial.left.calcified))
            Hairline().padding(.leading, 14)
            SideBySideChoices(label: "Ulnar compensation", options: RadialSide.ulnarOptions,
                              right: bind(\.radial.right.ulnar), left: bind(\.radial.left.ulnar), info: PatientStudies.ulnarInfo)
        }
        studyDateNotes(date: bind(\.radial.date), notes: bind(\.radial.notes), prompt: "Allen test, palmar arch, ulnar artery")
        if !r.radial.isEmpty {
            summaryBox(r.radial.summary)
            studyCautions(PatientStudies.cautions(r).filter { $0.id.hasPrefix("harvest") })
        }
        EvidenceNote(PatientStudies.radialEvidence)
    }

    private func calcified(_ kp: WritableKeyPath<PatientRecord, Bool?>) -> Binding<String?> {
        Binding(get: { patient.record[keyPath: kp].map { $0 ? "yes" : "no" } }, set: { v in patient.update { $0[keyPath: kp] = v.map { $0 == "yes" } } })
    }

    // MARK: Pulmonary function tests

    @ViewBuilder var pftEditor: some View {
        // The lab's reading comes first, above the spirometry table (Ben, 1.8.3).
        PatientGroup(title: "Lab's reading") {
            InfoChipRow(label: "Pattern", info: PatientStudies.patternInfo) {
                PatientChoice(options: PatientPFT.patterns, selection: bind(\.pft.pattern))
            }
            Hairline().padding(.leading, 14)
            InfoChipRow(label: "Severity", info: PatientStudies.severityInfo) {
                PatientChoice(options: PatientPFT.severities, selection: bind(\.pft.severity))
            }
        }
        PatientGroup(title: "Spirometry") {
            SideBySideHeader(columns: ["Liters", "% pred."])
            Hairline().padding(.leading, 14)
            SideBySideNumbers(label: "FEV1", unit: nil, right: bind(\.pft.fev1), left: bind(\.pft.fev1Pct), columns: ["liters", "% predicted"])
            Hairline().padding(.leading, 14)
            SideBySideNumbers(label: "FVC", unit: nil, right: bind(\.pft.fvc), left: bind(\.pft.fvcPct), columns: ["liters", "% predicted"])
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "FEV1/FVC", unit: "", value: bind(\.pft.ratioTyped), hint: "0.55 or 55")
        }
        PatientGroup(title: "Lung volumes & diffusion") {
            PatientNumberField(label: "TLC", unit: "% pred.", value: bind(\.pft.tlcPct))
            Hairline().padding(.leading, 14)
            PatientNumberField(label: "DLCO", unit: "% pred.", value: bind(\.pft.dlcoPct))
        }
        studyDateNotes(date: bind(\.pft.date), notes: bind(\.pft.notes), prompt: "Bronchodilator response, ABG, the trend")
        if !r.pft.isEmpty {
            summaryBox(r.pft.summary(copd: r.has("copd"), gold: false))
            if let g = r.pft.goldText(copd: r.has("copd")) {
                GoldRow(text: g)
            }
        }
        EvidenceNote(PatientStudies.pftEvidence)
    }

    // MARK: Shared pieces

    func studyDateNotes(date: Binding<PatientMonthYear>, notes: Binding<String>, prompt: String) -> some View {
        PatientGroup(title: nil) {
            MonthYearField(label: "Date", value: date)
            Hairline().padding(.leading, 14)
            PatientTextField(label: "Notes", prompt: prompt, text: notes)
        }
    }

    /// The cautions a study raises, each with its source behind ⓘ.
    @ViewBuilder func studyCautions(_ cautions: [StudyCaution]) -> some View {
        if !cautions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(cautions.enumerated()), id: \.element.id) { i, c in
                    StudyCautionRow(caution: c)
                    if i < cautions.count - 1 { Hairline().padding(.leading, 38) }
                }
            }
            .padding(.vertical, 2)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }
}

/// One caution: the warning, and its source behind ⓘ.
struct StudyCautionRow: View {
    var caution: StudyCaution
    @State private var open = LaunchSeed.bool("ps.evidence.open")

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(PS.sys(size: 13, weight: .semibold))
                .foregroundStyle(PS.accent)
            InfoTitle(caption: caution.source, open: $open, captionFont: PS.sys(size: 12), spacing: 4) {
                Text(caution.text).font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// A chip row whose title has a caption behind ⓘ (no ⓘ while `info` is nil); the chips go under the title.
struct InfoChipRow<Content: View>: View {
    var label: String
    var info: String?
    @ViewBuilder var content: () -> Content
    @State private var open = LaunchSeed.bool("ps.evidence.open")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoTitle(caption: info, open: $open, captionFont: PS.sys(size: 12), spacing: 4) {
                Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// The GOLD grade under the PFT summary, its caveat behind ⓘ.
struct GoldRow: View {
    var text: String
    @State private var open = LaunchSeed.bool("ps.evidence.open")

    var body: some View {
        InfoTitle(caption: PatientStudies.goldCaveat, open: $open, captionFont: PS.sys(size: 12), spacing: 4) {
            Text(text).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }
}

/// "Right" and "Left" (or other) column heads over SideBySide rows.
struct SideBySideHeader: View {
    var columns = ["Right", "Left"]

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            ForEach(columns, id: \.self) { c in
                Eyebrow(text: c).frame(width: SideBySide.cell, alignment: .center)
            }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
        .accessibilityHidden(true)
    }
}

enum SideBySide {
    /// The width of one column: two fit beside a label on the narrowest phone.
    static let cell: CGFloat = 84
}

/// A label and two numbers side by side (right and left, or liters and % predicted), each typed in its own small field.
struct SideBySideNumbers: View {
    var label: String
    var unit: String?
    @Binding var right: Double?
    @Binding var left: Double?
    var columns = ["Right", "Left"]

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                if let unit { Text(unit).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CompactNumberField(value: $right, accessibility: label + ", " + columns[0])
            CompactNumberField(value: $left, accessibility: label + ", " + columns[1])
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
    }
}

/// A label, then a choice for each side, one column each.
struct SideBySideChoices: View {
    var label: String
    var options: [(id: String, label: String)]
    @Binding var right: String?
    @Binding var left: String?
    var info: String? = nil
    @State private var open = LaunchSeed.bool("ps.evidence.open")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoTitle(caption: info, open: $open, captionFont: PS.sys(size: 12), spacing: 4) {
                Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            }
            HStack(alignment: .top, spacing: 12) {
                column("R", $right)
                column("L", $left)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func column(_ side: String, _ b: Binding<String?>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(side).font(PS.mono(size: 11, weight: .bold)).foregroundStyle(PS.fg3).frame(width: 12)
            PatientChoice(options: options, selection: b)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label + (side == "R" ? ", right" : ", left"))
    }
}

/// A small number field: typed freely, parsed into the value, as PatientNumberField's.
struct CompactNumberField: View {
    @Binding var value: Double?
    var accessibility: String
    @State private var text = ""
    @FocusState private var focused: Bool

    private static func parse(_ s: String) -> Double? {
        let v = Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        guard let v, v.isFinite, v >= 0 else { return nil }
        return v
    }

    var body: some View {
        TextField("—", text: $text)
            .keyboardType(.decimalPad)
            .focused($focused)
            .multilineTextAlignment(.center)
            .font(PS.sys(size: 16, weight: .semibold, design: .monospaced))
            .foregroundStyle(PS.fg)
            .padding(.horizontal, 6).padding(.vertical, 6)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(width: SideBySide.cell)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .accessibilityLabel(accessibility)
            .onAppear { text = value.map { NumText.exact($0) } ?? "" }
            .onChange(of: text) { _, t in
                let v = Self.parse(t)
                if v != value { value = v }
            }
            .onChange(of: value) { _, v in
                if Self.parse(text) != v { text = v.map { NumText.exact($0) } ?? "" }
            }
    }
}
