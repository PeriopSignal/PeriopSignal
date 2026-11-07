import SwiftUI

// MARK: - The intraoperative echo in two exams (1.10)
//
// Ben (Nov 7, notes-img3): "Intraoperative echo: should be able to add pre-bypass exam and post-bypass exam (2 sections).
// Should be able to add free text to any echo valve and chamber section (both pre-bypass and post-bypass section)."
// The pre-bypass exam is the record's `intraopEcho` (a 1.9 save's intraoperative echo opens as it, and it is the only exam
// of a case without bypass); the post-bypass exam is `intraopEchoPost`, offered behind "Add a post-bypass exam" until it
// holds something. Reached by the existing PatientEditor case (.intraopPart("echo")), whatever links to it.

/// The two exams, each the full findings editor with a notes field on every chamber and valve.
struct IntraopEchoExams: View {
    @Environment(PatientStore.self) private var patient
    @State private var postOpen = LaunchSeed.bool("ps.echo.post")

    private func bind(_ kp: WritableKeyPath<PatientRecord, PatientEcho>) -> Binding<PatientEcho> {
        Binding(get: { patient.record[keyPath: kp] }, set: { v in patient.update { $0[keyPath: kp] = v } })
    }

    var body: some View {
        let r = patient.record
        let postShown = !r.intraopEchoPost.isEmpty || postOpen
        IntraopExamHeader(title: "Pre-bypass exam", detail: "Before bypass, or the case's only exam").id("echo-pre")
        EchoFindingsEditor(echo: bind(\.intraopEcho), sectionNotes: true, showsEvidence: !postShown)
        IntraopExamHeader(title: "Post-bypass exam", detail: "After separation from bypass").id("echo-post")
        if !postShown {
            PatientGroup(title: nil) {
                Button {
                    Haptics.light()
                    withAnimation(.snappy) { postOpen = true }
                } label: {
                    Label("Add a post-bypass exam", systemImage: "plus.circle")
                        .font(PS.sys(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(PS.accent)
                if !r.intraopEcho.isEmpty {
                    Hairline().padding(.leading, 14)
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) {
                            postOpen = true
                            patient.update(discrete: true) { $0.intraopEchoPost = $0.intraopEcho.copiedForPostBypass() }
                        }
                    } label: {
                        Label("Start from the pre-bypass findings", systemImage: "doc.on.doc")
                            .font(PS.sys(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PS.accent)
                    .accessibilityHint("Copies the pre-bypass findings into the post-bypass exam, to change what is different")
                }
            }
        } else {
            EchoFindingsEditor(echo: bind(\.intraopEchoPost), sectionNotes: true, anchorPrefix: "post-")
        }
    }
}

/// An exam's heading on the intraoperative echo page.
struct IntraopExamHeader: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(PS.sys(size: 18, weight: .bold)).foregroundStyle(PS.fg)
                .accessibilityAddTraits(.isHeader)
            Text(detail).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2).padding(.top, 8)
    }
}
