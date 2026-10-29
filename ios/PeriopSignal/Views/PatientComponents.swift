import SwiftUI

// MARK: - Pieces the My Patient screens share

/// A number bound to the record, typed freely: the text is kept while typing and parsed into the value.
struct PatientNumberField: View {
    var label: String
    var unit: String
    @Binding var value: Double?
    var hint: String? = nil
    var focus: FocusState<Bool>.Binding
    @State private var text = ""

    private static func parse(_ s: String) -> Double? {
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
                .focused(focus)
                .multilineTextAlignment(.trailing)
                .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(PS.fg)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(width: 92)
            Text(unit).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 52, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .onAppear { text = value.map { PedsCalc.fmt($0) } ?? "" }
        .onChange(of: text) { _, t in
            let v = Self.parse(t)
            if v != value { value = v }
        }
        .onChange(of: value) { _, v in
            if Self.parse(text) != v { text = v.map { PedsCalc.fmt($0) } ?? "" }
        }
    }
}

/// Free text bound to the record.
struct PatientTextField: View {
    var label: String
    var prompt: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            TextField(prompt, text: $text, axis: .vertical)
                .lineLimit(1...8)
                .focused(focus)
                .font(PS.sys(size: 15))
                .foregroundStyle(PS.fg)
                .padding(10)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

/// Toggle chips for a set of flags; several can be on.
struct PatientChips: View {
    var options: [PatientFlag]
    @Binding var selection: Set<String>
    var tint: Color = PS.accent

    var body: some View {
        WrapLayout(spacing: 7) {
            ForEach(options) { o in
                let on = selection.contains(o.id)
                Button {
                    Haptics.light()
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

/// One choice among a few, as chips; tapping the chosen one clears it.
struct PatientChoice: View {
    var options: [(id: String, label: String)]
    @Binding var selection: String?
    var tint: Color = PS.accent

    var body: some View {
        WrapLayout(spacing: 7) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let on = selection == o.id
                Button {
                    Haptics.light()
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

/// A titled group of inputs on a card.
struct PatientGroup<Content: View>: View {
    var title: String?
    var note: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Eyebrow(text: title).padding(.leading, 2) }
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            if let note {
                Text(note).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
            }
        }
    }
}

/// Padding for chips inside a group.
struct PatientChipRow<Content: View>: View {
    var label: String?
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label { Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2) }
            content()
        }
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
