import SwiftUI

/// "+ Add other input data into Handoff" (1.12, Ben's note 14): a quiet link that opens in place and shows three groups of
/// chips, Preop labs, Intraop labs and Imaging, each listing every RECORDED item the summaries do not show by default (the
/// lists are in HandoffExtras, PatientBriefLabs.swift). A chosen chip (action-tinted, with its ✓) adds its item to both
/// summaries (the intraop labs to the handoff only): "preop:<lab key>", "intraop:<lab key>", "imaging:ct|mri|other" in
/// `PatientRecord.handoffExtras`. Collapsed with something chosen it reads "Other input data in Handoff: 3 added · Change".
/// With nothing recorded beyond what the summaries already show there is nothing to add, so nothing is drawn. Helper B
/// places it under the handoff card and under the Preprocedure Summary card.
struct HandoffExtrasLink: View {
    @Environment(PatientStore.self) private var patient
    /// Screenshot runs: -ps.handoff.extras 1 opens it.
    @State private var open = LaunchSeed.bool("ps.handoff.extras")

    /// The collapsed link's words.
    static func title(chosen: Int) -> String {
        chosen > 0 ? "Other input data in Handoff: \(chosen) added" : "Add other input data into Handoff"
    }

    private func selection(_ offered: [HandoffExtras.Candidate]) -> Binding<Set<String>> {
        let keys = Set(offered.map(\.key))
        return Binding(get: { Set(patient.record.handoffExtras) },
                       set: { v in
                           patient.update { r in
                               let old = Set(r.handoffExtras)
                               r.handoffExtras += v.subtracting(old).sorted()
                               r.handoffExtras.removeAll { keys.contains($0) && !v.contains($0) }
                           }
                       })
    }

    @ViewBuilder private func group(_ title: String, _ offered: [HandoffExtras.Candidate]) -> some View {
        if !offered.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
                PatientChips(options: offered.map { PatientFlag($0.key, $0.label) }, selection: selection(offered))
            }
        }
    }

    var body: some View {
        let r = patient.record
        let offered = HandoffExtras.offered(r)
        let any = !(offered.preop.isEmpty && offered.intraop.isEmpty && offered.imaging.isEmpty)
        if any {
            let chosen = HandoffExtras.chosenCount(r)
            VStack(alignment: .leading, spacing: 10) {
                QuietLinkRow(title: Self.title(chosen: chosen), filled: chosen > 0) { withAnimation(.snappy) { open.toggle() } }
                    .padding(.horizontal, 4).padding(.vertical, 4)
                if open {
                    VStack(alignment: .leading, spacing: 14) {
                        QuietOpenHeader(label: "Add to the summaries") { withAnimation(.snappy) { open = false } }
                        group("Preop labs", offered.preop)
                        group("Intraop labs", offered.intraop)
                        group("Imaging", offered.imaging)
                        Text("A chosen item is added to the summaries. Intraop labs show in the handoff only.")
                            .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                }
            }
            .id("handoffextras")
        }
    }
}
