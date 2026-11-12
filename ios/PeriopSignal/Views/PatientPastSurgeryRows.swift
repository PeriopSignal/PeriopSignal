import SwiftUI

/// The rows of the Past Surgical History page (and of Previous Intrathoracic Surgery, which lists the same entries marked
/// cardiac or thoracic), newest first (1.12 follow-up, Ben: "most recent at top").
///
/// The order is worked out when the page appears and when an entry is added or removed (the "Add another operation" button,
/// the page's bar filing one, a delete, two entries merged), not on every keystroke: a row whose date is being typed stays
/// where it is until the page is shown again. Every row is bound by its entry's id, so an edit lands on its own entry whatever
/// order the rows are drawn in (PastSurgeryOrder, PatientSurgery.chronological).
struct PastSurgeryRows: View {
    @Environment(PatientStore.self) private var patient
    /// Only the operations marked cardiac or thoracic (the Previous Intrathoracic Surgery page).
    var chestOnly: Bool
    @Binding var wobbling: Bool
    /// The ids in the order the page fixed.
    @State private var fixed: [UUID] = []

    private var entries: [PatientSurgery] {
        chestOnly ? patient.record.surgeries.filter(\.intrathoracic) : patient.record.surgeries
    }

    var body: some View {
        let ids = entries.map(\.id)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(PastSurgeryOrder.rows(entries, fixed: fixed)) { s in
                SurgeryRow(surgery: binding(s.id), intrathoracicToggle: !chestOnly) { remove(s.id) }
                    .wobbleDelete($wobbling, label: s.text.isEmpty ? "operation" : s.text, angle: 0.6) { remove(s.id) }
            }
        }
        .onAppear { fixed = PastSurgeryOrder.ids(entries) }
        .onChange(of: ids) { _, _ in withAnimation(.snappy) { fixed = PastSurgeryOrder.ids(entries) } }
    }

    /// An entry of Past surgical history, edited so that an operation already listed is not listed twice and a cardiac one is
    /// the cardiovascular page's Previous cardiac surgery (1.10).
    private func binding(_ id: UUID) -> Binding<PatientSurgery> {
        Binding(get: { patient.record.surgeries.first { $0.id == id } ?? PatientSurgery() },
                set: { v in patient.update { PatientHistoryDetails.editSurgery(v, &$0) } })
    }

    private func remove(_ id: UUID) {
        patient.update(discrete: true) { $0.surgeries.removeAll { $0.id == id } }
    }
}
