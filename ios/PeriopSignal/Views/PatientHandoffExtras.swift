import SwiftUI

/// "+ Add other input data into Handoff" (1.12, Ben): a quiet link that opens chips for the preop labs, intraop labs
/// and imaging that the summaries do not show by default; a chosen chip's item is added (`PatientRecord.handoffExtras`).
/// 1.12 groundwork: an empty stub so the summary view can place it. Helper A owns this file and builds it; helper B
/// places `HandoffExtrasLink()` on Summary & Handoff.
struct HandoffExtrasLink: View {
    var body: some View { EmptyView() }
}
