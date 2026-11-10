import SwiftUI

/// "+ Preprocedure Imaging" (1.12, Ben): a quiet link at the end of the Problems by System box. It opens in place with
/// three free-text lines (CT, MRI, Other imaging) and collapses to "Imaging: CT · MRI · Change", naming which hold text.
/// What is typed is kept in `PatientRecord.imaging`; a summary shows an item only when it is chosen under "+ Add other
/// input data into Handoff" (PatientBriefs.imagingBlock).
struct PreopImagingLink: View {
    @Environment(PatientStore.self) private var patient
    /// Open while the three lines are shown: tapped open, or (a screenshot run) -ps.preop.imaging 1.
    @State private var open = LaunchSeed.bool("ps.preop.imaging")

    /// The line under each item's name while it is empty.
    static func prompt(_ item: PatientImaging.Item) -> String {
        switch item {
        case .ct: return "CT findings"
        case .mri: return "MRI findings"
        case .other: return "Other imaging, e.g. ultrasound"
        }
    }

    private func binding(_ item: PatientImaging.Item) -> Binding<String> {
        Binding(get: { patient.record.imaging.typed(item) }, set: { v in patient.update { $0.imaging.set(item, v) } })
    }

    var body: some View {
        let imaging = patient.record.imaging
        VStack(alignment: .leading, spacing: 10) {
            if open {
                QuietOpenHeader(label: "Preprocedure imaging") { withAnimation(.snappy) { open = false } }
                VStack(spacing: 0) {
                    ForEach(PatientImaging.Item.allCases, id: \.self) { item in
                        PatientTextField(label: item.label, prompt: Self.prompt(item), text: binding(item))
                    }
                }
                .padding(.horizontal, -14)
            } else if let title = imaging.linkTitle {
                QuietLinkRow(title: title, filled: true) { withAnimation(.snappy) { open = true } }
            } else {
                QuietLinkRow(title: "Preprocedure Imaging") { withAnimation(.snappy) { open = true } }
            }
        }
    }
}
