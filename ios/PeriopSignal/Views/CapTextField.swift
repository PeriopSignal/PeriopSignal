import SwiftUI

/// A one-line text field that capitalizes the first letter of what was typed once the field is left or submitted
/// (FreeText.cap, 1.8.3), so a typed name reads like the catalog's. Not while typing: "eGFR" and "iCa" are decided by
/// the whole first word.
struct CapTextField: View {
    var prompt: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $text)
            .focused($focused)
            .onChange(of: focused) { _, now in if !now { commit() } }
            .onSubmit(commit)
    }

    private func commit() {
        let c = FreeText.cap(text)
        if c != text { text = c }
    }
}
