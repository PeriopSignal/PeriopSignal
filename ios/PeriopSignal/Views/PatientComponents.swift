import SwiftUI

// MARK: - Pieces the My Patient screens share

/// A number field's place in its page's Previous / Next order (PatientEditorView.numberOrder): the page's focus and
/// this field's id in it.
struct PatientFieldChain {
    var focus: FocusState<String?>.Binding
    var id: String

    func focusHere() { focus.wrappedValue = id }
}

/// Focus from the page's chain when the field has a place in it, else the field's own.
struct PatientFieldFocus: ViewModifier {
    var chain: PatientFieldChain?
    var local: FocusState<Bool>.Binding

    @ViewBuilder func body(content: Content) -> some View {
        if let chain {
            content.focused(chain.focus, equals: chain.id)
        } else {
            content.focused(local)
        }
    }
}

/// A number bound to the record, typed freely: the text is kept while typing and parsed into the value. The field
/// has its own focus, or a place in the page's Previous / Next order (`chain`), and a tap anywhere on the row starts
/// typing.
struct PatientNumberField: View {
    var label: String
    var unit: String
    @Binding var value: Double?
    var hint: String? = nil
    var chain: PatientFieldChain? = nil
    @State private var text = ""
    @FocusState private var focused: Bool

    static func parse(_ s: String) -> Double? {
        let v = Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        guard let v, v.isFinite, v >= 0 else { return nil }
        return v
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                if let hint { Text(hint).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 6)
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .modifier(PatientFieldFocus(chain: chain, local: $focused))
                .multilineTextAlignment(.trailing)
                .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(PS.fg)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(width: 92)
            Text(unit).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 52, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if let chain { chain.focusHere() } else { focused = true } }
        // NumText.exact, not a rounding format: the text parses back to the same value, so showing it never edits it.
        .onAppear { text = value.map { NumText.exact($0) } ?? "" }
        .onChange(of: text) { _, t in
            let v = Self.parse(t)
            if v != value { value = v }
        }
        .onChange(of: value) { _, v in
            if Self.parse(text) != v { text = v.map { NumText.exact($0) } ?? "" }
        }
    }
}

/// Undo in the navigation bar: steps back the last change to the current case, on any My Patient tab or editor.
/// Shown only when there is something to undo.
struct PatientUndoButton: View {
    @Environment(PatientStore.self) private var patient

    var body: some View {
        if patient.canUndo {
            Button {
                Haptics.light()
                withAnimation(.snappy) { patient.undo() }
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .accessibilityHint("Undoes the last change to this patient")
        }
    }
}

/// Free text bound to the record; a tap on the label or anywhere in the box starts typing.
struct PatientTextField: View {
    var label: String
    var prompt: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            TextField(prompt, text: $text, axis: .vertical)
                .lineLimit(1...8)
                .focused($focused)
                .onChange(of: focused) { _, now in if !now { let c = FreeText.cap(text); if c != text { text = c } } }
                .font(PS.sys(size: 15))
                .foregroundStyle(PS.fg)
                .padding(10)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

/// Toggle chips for a set of flags; several can be on. Each tap is an Undo step of its own.
struct PatientChips: View {
    var options: [PatientFlag]
    @Binding var selection: Set<String>
    var tint: Color = PS.accent
    @Environment(PatientStore.self) private var store: PatientStore?

    var body: some View {
        WrapLayout(spacing: 7) {
            ForEach(options) { o in
                let on = selection.contains(o.id)
                Button {
                    Haptics.light()
                    store?.markDiscrete()
                    if on { selection.remove(o.id) } else { selection.insert(o.id) }
                } label: {
                    HStack(spacing: 5) {
                        if on { Image(systemName: "checkmark").font(PS.sys(size: 10.5, weight: .bold)) }
                        Text(o.label).font(PS.sys(size: 13.5, weight: on ? .semibold : .medium))
                    }
                    .foregroundStyle(on ? PS.fg : PS.fg2)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(on ? tint.opacity(0.18) : PS.surface2, in: Capsule())
                    .overlay(Capsule().stroke(on ? tint.opacity(0.55) : PS.line2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityHint(o.detail ?? "")
            }
        }
    }
}

/// One choice among a few, as chips; tapping the chosen one clears it. Each tap is an Undo step of its own.
struct PatientChoice: View {
    var options: [(id: String, label: String)]
    @Binding var selection: String?
    var tint: Color = PS.accent
    @Environment(PatientStore.self) private var store: PatientStore?

    var body: some View {
        WrapLayout(spacing: 7) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let on = selection == o.id
                Button {
                    Haptics.light()
                    store?.markDiscrete()
                    selection = on ? nil : o.id
                } label: {
                    Text(o.label)
                        .font(PS.sys(size: 13.5, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? PS.bg : PS.fg2)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(on ? PS.fg : PS.surface2, in: Capsule())
                        .overlay(Capsule().stroke(on ? Color.clear : PS.line2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A one-tap preset (Exam normal, Echo normal): the button, with what it sets behind an ⓘ beside it (the fields it
/// fills are right below, and Undo steps it back). Once the record shows what it sets, the button reads as done;
/// everything stays editable below. VoiceOver reads what it sets as the button's hint.
struct PatientPresetRow: View {
    var title: String
    var caption: String
    var applied: Bool
    var action: () -> Void
    @State private var open = LaunchSeed.bool("ps.evidence.open")

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Button {
                    Haptics.light()
                    withAnimation(.snappy) { action() }
                } label: {
                    Label(title, systemImage: applied ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(CapsuleButtonStyle(prominent: !applied, color: PS.green))
                .accessibilityHint(caption)
                InfoButton(open: $open, label: "What " + title + " sets", size: 13)
                Spacer(minLength: 0)
            }
            if open {
                InfoCaptionText(text: caption, font: PS.sys(size: 12))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The ASA suggestion as a small table: what is recorded, the ASA example it matches (when that says more), and the
/// example's class; the rows that set the suggestion are filled.
struct AsaReasonTable: View {
    var reasons: [AsaReason]
    var top: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("RECORDED").frame(maxWidth: .infinity, alignment: .leading)
                Text("ASA EXAMPLE").frame(alignment: .trailing)
            }
            .font(PS.mono(size: 9.5, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(PS.fg3)
            .padding(.bottom, 4)
            Hairline()
            ForEach(Array(reasons.enumerated()), id: \.offset) { i, r in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.finding)
                            .font(PS.sys(size: 13.5, weight: r.level == top ? .semibold : .regular))
                            .foregroundStyle(PS.fg)
                        if let ex = r.example {
                            Text(ex).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(PatientRules.roman(r.level))
                        .font(PS.mono(size: 12, weight: .bold))
                        .foregroundStyle(r.level == top ? PS.accentFg : PS.fg2)
                        .frame(minWidth: 36)
                        .padding(.vertical, 3)
                        .background(r.level == top ? PS.accent : PS.surface2, in: Capsule())
                        .accessibilityLabel("ASA " + PatientRules.roman(r.level))
                }
                .padding(.vertical, 7)
                if i < reasons.count - 1 { Hairline() }
            }
        }
    }
}

/// A titled group of inputs on a card. The group's `note` (how it works, its source) sits behind an ⓘ at the end of
/// the title and opens under it (SectionHeader), so groups no longer stack "Explanation & Evidence ⓘ" rows between
/// their cards. A group without a title keeps the note on its own ⓘ line under the card. Notes are explanation only:
/// a caution that must stay in view belongs in the card's content, not here.
struct PatientGroup<Content: View>: View {
    var title: String?
    var note: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionHeader(title: title, info: note).padding(.leading, 2) }
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            if title == nil, let note, !note.isEmpty { EvidenceNote(note).padding(.horizontal, 2) }
        }
    }
}

/// Padding for chips inside a group.
struct PatientChipRow<Content: View>: View {
    var label: String?
    @ViewBuilder var content: () -> Content
    var body: some View {
        Group {
            if let label {
                // On the title's line when the choices fit there.
                InlineChoices {
                    Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
                } choices: {
                    content()
                }
            } else {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: - Mallampati

/// An original drawing of the open mouth with the tongue out: the tongue rises from class I to IV and hides, in turn,
/// the pillars, the uvula and the soft palate.
struct MallampatiDrawing: View {
    var mclass: Int

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func r(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> CGRect { CGRect(x: x * w, y: y * h, width: rw * w, height: rh * h) }
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
            let cavity = Path(ellipseIn: r(0.08, 0.10, 0.84, 0.82))
            let outline = ctx
            ctx.fill(cavity, with: .color(Color(hex: "4A1520")))
            ctx.clip(to: cavity)
            // posterior pharyngeal wall
            ctx.fill(Path(ellipseIn: r(0.30, 0.40, 0.40, 0.42)), with: .color(Color(hex: "6B2230")))
            // soft palate, then the hard palate in front of it
            ctx.fill(Path(ellipseIn: r(0.16, 0.20, 0.68, 0.26)), with: .color(Color(hex: "E39AA2")))
            ctx.fill(Path(ellipseIn: r(0.14, 0.04, 0.72, 0.24)), with: .color(Color(hex: "F0C4C4")))
            // faucial pillars: an arch on each side, the tonsillar fossa inside it
            var pillars = Path()
            let sides: [CGFloat] = [0.29, 0.71]
            for c in sides {
                var fossa = Path()
                fossa.move(to: p(c - 0.10, 0.96))
                fossa.addQuadCurve(to: p(c + 0.10, 0.96), control: p(c, 0.40))
                fossa.closeSubpath()
                ctx.fill(fossa, with: .color(Color(hex: "5E1C28")))
                pillars.move(to: p(c - 0.11, 0.96))
                pillars.addQuadCurve(to: p(c + 0.11, 0.96), control: p(c, 0.36))
                pillars.move(to: p(c - 0.05, 0.96))
                pillars.addQuadCurve(to: p(c + 0.05, 0.96), control: p(c, 0.50))
            }
            ctx.stroke(pillars, with: .color(Color(hex: "D07080")), style: StrokeStyle(lineWidth: max(2, w * 0.03), lineCap: .round))
            // uvula
            var uvula = Path()
            uvula.move(to: p(0.46, 0.40))
            uvula.addQuadCurve(to: p(0.50, 0.64), control: p(0.43, 0.58))
            uvula.addQuadCurve(to: p(0.54, 0.40), control: p(0.57, 0.58))
            uvula.closeSubpath()
            ctx.fill(uvula, with: .color(Color(hex: "D9707E")))
            // tongue: its top edge sets the class
            let top: CGFloat
            switch mclass {
            case 2: top = 0.57
            case 3: top = 0.48
            case 4: top = 0.28
            default: top = 0.84
            }
            let tongue = Path(roundedRect: r(0.10, top, 0.80, 0.70), cornerRadius: 0.30 * w)
            ctx.fill(tongue, with: .color(Color(hex: "E8828E")))
            var groove = Path()
            groove.move(to: p(0.5, top + 0.07))
            groove.addLine(to: p(0.5, min(0.95, top + 0.30)))
            ctx.stroke(groove, with: .color(Color(hex: "C9646F")), style: StrokeStyle(lineWidth: max(1, w * 0.012), lineCap: .round))
            // lips
            outline.stroke(cavity, with: .color(Color(hex: "B04A58")), lineWidth: max(2, w * 0.03))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Mallampati class \(PatientRules.roman(mclass)): \(PatientAirway.mallampati(mclass))")
    }
}

// MARK: - Wobble to delete (like editing the Home Screen)

/// Long-press an item to make the whole list wobble; each item shows a red minus badge, and a tap on it deletes the
/// item. Done (or the editor's own Done) stops the wobble. The binding is shared by the items of one list, so they
/// wobble together.
struct WobbleDelete: ViewModifier {
    @Binding var editing: Bool
    var label: String
    /// Degrees each way: small for wide rows, larger for chips and markers.
    var angle: Double = 0.9
    var onDelete: () -> Void
    @State private var phase = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if editing {
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { onDelete() }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, PS.red)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: -8, y: -8)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Delete \(label)")
                }
            }
            .rotationEffect(.degrees(editing ? (phase ? angle : -angle) : 0))
            .animation(editing ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true) : .snappy, value: phase)
            .onChange(of: editing) { _, on in phase = on }
            .onAppear { if editing { phase = true } }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                guard !editing else { return }
                Haptics.light()
                withAnimation(.snappy) { editing = true }
            })
            .accessibilityAction(named: "Delete") { onDelete() }
    }
}

extension View {
    /// Home Screen–style editing: long-press to wobble, tap the minus badge to delete.
    func wobbleDelete(_ editing: Binding<Bool>, label: String, angle: Double = 0.9, onDelete: @escaping () -> Void) -> some View {
        modifier(WobbleDelete(editing: editing, label: label, angle: angle, onDelete: onDelete))
    }
}

/// The bar shown while a list wobbles: what to do, and Done.
struct WobbleDoneBar: View {
    @Binding var editing: Bool
    var body: some View {
        if editing {
            HStack {
                Text("Tap − to delete").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
                Spacer()
                Button("Done") { Haptics.light(); withAnimation(.snappy) { editing = false } }
                    .buttonStyle(CapsuleButtonStyle())
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .transition(.opacity)
        }
    }
}
