import SwiftUI

// MARK: - Tools follow the current case
//
// Ben, Nov 23: "Calculators clear and refill from the new case when the current case changes, and Save or Start names the case it
// writes to." The rules are in CaseScope (Store); this is how a screen takes part.

/// Gives a tool's root the identity of the case it is for. When that identity changes (another case becomes current, the case
/// is ended, its patient is cleared or received) SwiftUI builds the tool again, so its own fill-on-open code runs for the
/// now-current case and nothing typed for the last patient stays. Editing the same case does not change it. The Reference tab's
/// stack is untouched: the user stays on the same tool, only its contents are new.
struct CaseScoped: ViewModifier {
    @Environment(PatientStore.self) private var patient
    var resets: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if resets {
            content.id(CaseScope.identity(of: patient.book, patientEpoch: patient.patientEpoch))
        } else {
            content
        }
    }
}

/// Runs `action` when the current case, or its patient, changes: for a tool that keeps its checklist and clock through a switch
/// and refills only what belongs to the patient.
struct CaseScopeChange: ViewModifier {
    @Environment(PatientStore.self) private var patient
    var action: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: CaseScope.identity(of: patient.book, patientEpoch: patient.patientEpoch)) { _, _ in action() }
    }
}

/// "Saves to OR 12" under a control that writes to a case: the case it will write to, named as the case switcher names it.
/// Nothing with one case.
struct CaseWriteCaption: View {
    @Environment(PatientStore.self) private var patient
    var lead: String

    var body: some View {
        if let text = CaseScope.writeCaption(lead, in: patient.book) {
            Text(text)
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    /// The tool is rebuilt for each case (and patient) it is opened on; `false` leaves it as it is.
    func caseScoped(_ resets: Bool = true) -> some View { modifier(CaseScoped(resets: resets)) }

    /// Calls `action` when another case becomes current or the current case's patient is replaced.
    func onCaseChange(_ action: @escaping () -> Void) -> some View { modifier(CaseScopeChange(action: action)) }
}
