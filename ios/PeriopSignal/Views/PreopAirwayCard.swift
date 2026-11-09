import SwiftUI

// MARK: - The Airway Examination card (1.11, P1-11)
//
// Ben's layout review: Mallampati was five taps through the page, and a normal exam four. The card now opens with one
// control line, "✓ Exam normal" (the page's PatientAirway.isNormalExam preset) and the Mallampati class I–IV, so both are
// one tap on the tab; the page is unchanged and the card's title row still opens it. Under the controls, the findings
// read as findings (P1-10, Q18: "Mallampati III", "Difficult mask ventilation: 2 of 5 predictors"), with the drawing of
// the chosen class to their right; the definitions and the Langeron / Kheterpal wording stay on the page and in the
// brief. A class tapped after Exam normal leaves the preset unapplied (isNormalExam reads the record), so the record
// never contradicts itself; a second tap on the chosen class clears it, as every chip does.

struct PreopAirwayCard: View {
    @Environment(PatientStore.self) private var patient
    private var r: PatientRecord { patient.record }

    /// The class chips, I to IV, by the stored number.
    static let classChips: [ChipChoice] = (1...4).map { ChipChoice(String($0), PatientRules.roman($0)) }

    /// A class chip's tap: the class, or nil when the chosen one is tapped again. Exam normal's other fields stay as
    /// recorded (teeth, the reviewed signs): a class is a finding, not a reason to forget the rest of the exam.
    static func tapClass(_ id: String, _ r: inout PatientRecord) {
        guard let m = Int(id) else { return }
        r.mallampati = r.mallampati == m ? nil : m
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: PatientEditor.airway) { header }.buttonStyle(.plain)
            if !r.arrivesWithAirway { controls }
            NavigationLink(value: PatientEditor.airway) { findings }.buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: PatientEditor.airway.icon).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent)
            Text("Airway Examination").font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer()
            Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the airway page")
    }

    // MARK: Controls

    /// "✓ Exam normal" above the "Mallampati I II III IV" row: the two do not fit side by side at the app's text size on
    /// any phone width the shots cover (375 or 402 pt; shots 808–811 all stack), so the stacked form is the one seen;
    /// the one-line form is kept for wider layouts (an iPad, landscape).
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { preset; mallampatiRow }
            VStack(alignment: .leading, spacing: 8) { preset; mallampatiRow }
        }
    }

    private var preset: some View {
        let applied = PatientAirway.isNormalExam(r)
        return Button {
            Haptics.light()
            withAnimation(.snappy) { patient.update(discrete: true) { PatientAirway.applyNormalExam(&$0) } }
        } label: {
            Label("Exam normal", systemImage: applied ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .buttonStyle(CapsuleButtonStyle(prominent: !applied, color: PS.green))
        .accessibilityHint(PatientAirway.normalExamCaption)
        .accessibilityValue(applied ? "Applied" : "")
    }

    private var mallampatiRow: some View {
        HStack(spacing: 8) {
            Text("Mallampati").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2).fixedSize()
            ChipSet(options: Self.classChips, style: .choice,
                    hints: Dictionary(uniqueKeysWithValues: (1...4).map { (String($0), PatientAirway.mallampati($0)) }),
                    isOn: { r.mallampati.map { String($0) } == $0 },
                    tap: { id in withAnimation(.snappy) { patient.update { Self.tapClass(id, &$0) } } })
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mallampati class")
    }

    // MARK: Findings

    private var findings: some View {
        let lines = PatientSummary.airwayCardLines(r)
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if lines.isEmpty {
                    Text(PreopEmptyHints.airway).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in PatientLineText(line: l) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let m = r.mallampati, !r.arrivesWithAirway {
                VStack(spacing: 4) {
                    MallampatiDrawing(mclass: m).frame(width: 64, height: 64)
                    Text(PatientRules.roman(m)).font(PS.mono(size: 11, weight: .bold)).foregroundStyle(PS.fg2)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityHint("Opens the airway page")
    }
}
