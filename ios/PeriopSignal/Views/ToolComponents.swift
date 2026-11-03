import SwiftUI

// MARK: - Patient weight

/// The patient's weight, loud while it is missing: a "Required" badge, an accent outline and a line
/// saying what waits on it. Held by the tool's own state, so it is gone when the tool is closed; that is said behind
/// the ⓘ at the end of the field's title (`clearNote`), not in a permanent line.
struct WeightField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    /// What the weight unlocks, shown in the accent color while it is empty. A safety line: it stays in view and is
    /// never truncated. Keep it to one line on a phone; tools whose doses show per kg until then pass perKgPrompt.
    var prompt: String = "Enter the weight to calculate the doses."
    var badge: String = "Required"
    /// The field's name ("Newborn Weight" where the doses are the baby's, not the mother's).
    var title: String = "Patient Weight"
    /// My Patient's weight, when it applies to this tool: filled in at once and shown as one line until changed.
    var patientWeight: Double? = nil
    /// When the weight is cleared, behind the ⓘ on the title; nil drops the ⓘ (when the tool's footer says it).
    var clearNote: String? = WeightField.clearNote
    @State private var changing = false
    @State private var noteOpen = LaunchSeed.bool("ps.evidence.open")

    /// The one-line prompt for tools whose doses show per kilogram until the weight is entered.
    static let perKgPrompt = "Doses show per kg until you enter the weight."
    /// ACLS child: the shock energies are per kg too, not only the doses.
    static let aclsPerKgPrompt = "Doses and energies show per kg until you enter the weight."
    /// Local anesthetic: the tool shows each agent's maximum, not a dose.
    static let maxPerKgPrompt = "Maximums show per kg until you enter the weight."
    /// How long the weight is kept (it was a permanent "Cleared when you leave" beside the field before 1.8.1).
    static let clearNote = "Cleared when you leave."

    static func value(_ text: String) -> Double? {
        let v = Double(text.replacingOccurrences(of: ",", with: "."))
        return (v ?? 0) > 0 ? v : nil
    }

    var body: some View {
        Group {
            if let w = patientWeight, !changing, text == NumText.exact(w) {
                FromPatientLine(values: [NumText.short(w) + " kg"], what: "weight") { changing = true; focus.wrappedValue = true }
            } else {
                field
            }
        }
        .onAppear {
            if let w = patientWeight, Self.value(text) == nil { text = NumText.exact(w) }
        }
    }

    private var field: some View {
        let empty = Self.value(text) == nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "scalemass.fill")
                    .font(PS.sys(size: 12.5, weight: .semibold))
                    .foregroundStyle(empty ? PS.accent : PS.fg3)
                Text(title)
                    .font(PS.sys(size: 13.5, weight: .semibold))
                    .foregroundStyle(empty ? PS.fg : PS.fg2)
                    .lineLimit(1)
                if clearNote != nil { InfoButton(open: $noteOpen, label: "About the weight") }
                Spacer(minLength: 6)
                if empty {
                    Text(badge.uppercased())
                        .font(PS.mono(size: 9.5, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(PS.accentFg)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(PS.accent, in: Capsule())
                }
            }
            if noteOpen, let clearNote { InfoCaptionText(text: clearNote) }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("Enter weight", text: $text)
                    .keyboardType(.decimalPad)
                    .focused(focus)
                    .font(PS.serif(size: 28, weight: .semibold))
                    .foregroundStyle(PS.fg)
                Text("kg")
                    .font(PS.sys(size: 15, weight: .medium))
                    .foregroundStyle(PS.fg3)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(empty ? PS.accent : PS.line2, lineWidth: empty ? 2 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { focus.wrappedValue = true }
            if empty {
                Text(prompt)
                    .font(PS.sys(size: 12.5, weight: .medium))
                    .foregroundStyle(PS.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.snappy, value: empty)
    }
}

/// A one-line weight entry for lists where the weight refines rather than unlocks the numbers.
struct CompactWeightField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var badge: String = "For totals"
    /// My Patient's weight: filled in at once and shown as one line until changed.
    var patientWeight: Double? = nil
    /// When the weight is cleared, behind the ⓘ after "Weight"; nil drops the ⓘ (when the tool's footer says it).
    var clearNote: String? = WeightField.clearNote
    @State private var changing = false
    @State private var noteOpen = LaunchSeed.bool("ps.evidence.open")

    var body: some View {
        Group {
            if let w = patientWeight, !changing, text == NumText.exact(w) {
                FromPatientLine(values: [NumText.short(w) + " kg"], what: "weight") { changing = true; focus.wrappedValue = true }
            } else {
                field
            }
        }
        .onAppear {
            if let w = patientWeight, WeightField.value(text) == nil { text = NumText.exact(w) }
        }
    }

    private var field: some View {
        let empty = WeightField.value(text) == nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "scalemass.fill")
                    .font(PS.sys(size: 13, weight: .semibold))
                    .foregroundStyle(empty ? PS.accent : PS.fg3)
                Text("Weight").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
                if clearNote != nil { InfoButton(open: $noteOpen, label: "About the weight") }
                TextField("—", text: $text)
                    .keyboardType(.decimalPad)
                    .focused(focus)
                    .multilineTextAlignment(.trailing)
                    .font(PS.serif(size: 22, weight: .semibold))
                    .foregroundStyle(PS.fg)
                    .frame(width: 70)
                Text("kg").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                Spacer(minLength: 6)
                if empty {
                    Text(badge.uppercased())
                        .font(PS.mono(size: 9.5, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(PS.accentFg)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(PS.accent, in: Capsule())
                }
            }
            if noteOpen, let clearNote { InfoCaptionText(text: clearNote) }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(empty ? PS.accent.opacity(0.8) : PS.line, lineWidth: empty ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
    }
}

// MARK: - Tool header

/// The head of a Reference tool: a one-word eyebrow ("Emergency checklist", "Regional"; the society and year belong
/// in the sources), the tool's short name on one line, and its summary. The summary sits behind an ⓘ at the end of
/// the title, except on an emergency checklist (`infoSummary` false), where it stays in view. No decorative ECG line.
/// CI screenshots: -ps.evidence.open 1 opens the summary.
struct ToolHeader: View {
    var eyebrow: String?
    /// The short name ("LAST", not "Local Anesthetic Systemic Toxicity"): one line, shrinking to 80% before it truncates.
    var title: String
    var summary: String? = nil
    /// true: the summary is behind ⓘ; false (emergency checklists): the summary stays in view under the title.
    var infoSummary: Bool = true
    /// The eyebrow's color (the accent for emergencies, the topic's color otherwise).
    var tint: Color = PS.fg3
    @State private var open = LaunchSeed.bool("ps.evidence.open")

    private var hasSummary: Bool { !(summary ?? "").isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow, !eyebrow.isEmpty { Eyebrow(text: eyebrow, color: tint) }
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(PS.serif(size: 25, weight: .semibold))
                    .foregroundStyle(PS.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                if hasSummary && infoSummary { InfoButton(open: $open, label: "About " + title, size: 15) }
            }
            if let summary, hasSummary, !infoSummary || open {
                Text(summary)
                    .font(PS.sys(size: 15))
                    .foregroundStyle(PS.fg2)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - My Patient values in a tool

/// "82 kg · From My Patient · Change": a value the tool took from My Patient, in one line instead of a question.
struct FromPatientLine: View {
    var values: [String]
    /// What the values are, for VoiceOver ("weight", "age, sex, height and weight").
    var what: String
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .font(PS.sys(size: 13, weight: .semibold))
                .foregroundStyle(PS.accent2)
            Text(values.joined(separator: " · "))
                .font(PS.sys(size: 15, weight: .semibold))
                .foregroundStyle(PS.fg)
                .lineLimit(2)
            Text("From My Patient")
                .font(PS.sys(size: 11.5))
                .foregroundStyle(PS.fg3)
            Spacer(minLength: 6)
            Button("Change", action: onChange)
                .font(PS.sys(size: 13, weight: .semibold))
                .buttonStyle(.borderless)
                .tint(PS.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PS.accent2.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(what) from My Patient: \(values.joined(separator: ", "))")
    }
}

// MARK: - Checklists

/// "4 of 9 done" with a bar and a visible reset: the head of every checklist.
struct ChecklistProgress: View {
    var done: Int
    var total: Int
    var tint: Color = PS.accent
    var title: String = "Checklist"
    var doneWord: String = "done"
    var onReset: (() -> Void)?

    var body: some View {
        let complete = total > 0 && done == total
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: complete ? "checkmark.seal.fill" : "checklist")
                    .font(PS.sys(size: 13, weight: .semibold))
                    .foregroundStyle(complete ? PS.green : tint)
                Text(title)
                    .font(PS.sys(size: 13.5, weight: .semibold))
                    .foregroundStyle(PS.fg)
                Text("\(done) of \(total) \(doneWord)")
                    .font(PS.mono(size: 11, weight: .semibold))
                    .foregroundStyle(complete ? PS.green : PS.fg3)
                    .contentTransition(.numericText())
                Spacer(minLength: 6)
                if let onReset, done > 0 {
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { onReset() }
                    } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                        .font(PS.sys(size: 12.5, weight: .semibold))
                        .foregroundStyle(PS.fg2)
                        .buttonStyle(.plain)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(PS.surface3)
                    Capsule().fill(complete ? PS.green : tint)
                        .frame(width: total == 0 ? 0 : geo.size.width * CGFloat(done) / CGFloat(total))
                }
            }
            .frame(height: 5)
        }
        .animation(.snappy, value: done)
    }
}

/// One checklist line: a numbered box that becomes a green tick, the text struck through once done.
struct ChecklistItemRow: View {
    var number: Int
    var text: String
    var done: Bool
    var tint: Color = PS.accent
    var size: CGFloat = 14.5
    var toggle: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            withAnimation(.snappy) { toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(done ? PS.green : tint.opacity(0.10))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(done ? PS.green : tint.opacity(0.75), lineWidth: 1.6)
                    if done {
                        Image(systemName: "checkmark").font(PS.sys(size: 13, weight: .heavy)).foregroundStyle(PS.accentFg)
                    } else {
                        Text("\(number)").font(PS.mono(size: 11.5, weight: .bold)).foregroundStyle(tint)
                    }
                }
                .frame(width: 26, height: 26)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 }
                Text(text)
                    .font(PS.sys(size: size))
                    .foregroundStyle(done ? PS.fg3 : PS.fg)
                    .strikethrough(done, color: PS.fg3)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityValue(done ? "Done" : "Not done")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Role tags

/// A drug's class as a small colored tag: pressors coral, dilators blue, inotropes green.
struct RoleTag: View {
    var role: String

    static func color(_ role: String) -> Color {
        let r = role.lowercased()
        if r.contains("pressor") && !r.contains("ino") { return PS.accent }
        if r.contains("ino") || r.contains("chrono") { return PS.green }
        if r.contains("dilator") { return PS.accent2 }
        return PS.fg3
    }

    var body: some View {
        Text(role.uppercased())
            .font(PS.mono(size: 8.5, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(Self.color(role))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Self.color(role).opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Text entry and leaving a page

/// The keyboard's Done: ends editing wherever the cursor is.
enum Keyboard {
    @MainActor static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// A text box with its own focus, so a tap goes to this field and no other (one focus shared by several fields can
/// send the cursor elsewhere), and that takes the tap anywhere in its box or row, not only on the line of text.
struct FocusBox<Content: View>: View {
    @FocusState private var focused: Bool
    private let content: (FocusState<Bool>.Binding) -> Content

    init(@ViewBuilder _ content: @escaping (FocusState<Bool>.Binding) -> Content) { self.content = content }

    var body: some View {
        content($focused)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
    }
}

/// Done at the end of a page: goes back like the back button (what was entered is kept).
struct DoneFooter: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            Haptics.light()
            dismiss()
        } label: {
            Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity)
        }
        .buttonStyle(BigButtonStyle(prominent: false))
        .accessibilityHint("Goes back to the previous screen")
    }
}

/// A tool page's scroll view: the page, then Done.
struct ToolScroll<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                content
                DoneFooter()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
    }
}
