import SwiftUI

// MARK: - The preprocedure stress test (1.11, Ben's note 4)
//
// "Should add stress test to this too (exercise and dobutamine; minimal input should be needed, just summary of
// findings)". A small page behind the "+ Stress test" chip of the Preprocedure cardiac workup: the type (Exercise,
// Dobutamine, Other), the result (Negative/normal, Positive/ischemia, Equivocal/nondiagnostic), the month and year, and
// one Findings line. Its one-liner (PatientStressTest.summary) is the workup chip's row; the briefs read
// PatientPreop.stressLine. The page records what the report said and grades nothing itself.

struct PatientStressTestEditor: View {
    @Environment(PatientStore.self) private var patient

    private var test: PatientStressTest { patient.record.stressTest }

    /// The result chips' full words (VoiceOver and a wide row) and the one word a narrow row shows.
    static let results: [ChipChoice] = [
        ChipChoice(PatientStressTest.Result.negative.rawValue, "Negative/normal", short: "Negative"),
        ChipChoice(PatientStressTest.Result.positive.rawValue, "Positive/ischemia", short: "Positive"),
        ChipChoice(PatientStressTest.Result.equivocal.rawValue, "Equivocal/nondiagnostic", short: "Equivocal"),
    ]

    static let kinds: [ChipChoice] = PatientStressTest.Kind.allCases.map { ChipChoice($0.rawValue, $0.label) }

    var body: some View {
        PatientGroup(title: "Stress test", note: PatientPreop.stressNote) {
            PatientChipRow(label: "Type") {
                PatientChoice(choices: Self.kinds,
                              selection: Binding(get: { patient.record.stressTest.kind?.rawValue },
                                                 set: { v in patient.update { $0.stressTest.kind = v.flatMap { PatientStressTest.Kind(rawValue: $0) } } }))
            }
            Hairline().padding(.leading, 14)
            PatientChipRow(label: "Result") {
                PatientChoice(choices: Self.results,
                              selection: Binding(get: { patient.record.stressTest.result?.rawValue },
                                                 set: { v in patient.update { $0.stressTest.result = v.flatMap { PatientStressTest.Result(rawValue: $0) } } }))
            }
            Hairline().padding(.leading, 14)
            MonthYearField(label: "Date", value: Binding(get: { patient.record.stressTest.date }, set: { v in patient.update { $0.stressTest.date = v } }))
            Hairline().padding(.leading, 14)
            PatientTextField(label: "Findings", prompt: "One line, e.g. no ischemia at 9 METs; inferior wall ischemia at 7 METs",
                             text: Binding(get: { patient.record.stressTest.findings }, set: { v in patient.update { $0.stressTest.findings = v } }))
            if let s = test.summary {
                Hairline().padding(.leading, 14)
                Text(s).font(PS.sys(size: 13, weight: .medium)).foregroundStyle(test.result == .positive ? PS.red : PS.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .id("stress")
    }
}
