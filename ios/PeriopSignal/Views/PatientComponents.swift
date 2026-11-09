import SwiftUI
import UIKit

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
                // One line, shrunk a little on a narrow row, never broken mid-word (review 1.10).
                Text(label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                    .lineLimit(1).minimumScaleFactor(0.75)
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

/// Screenshot runs only (a debug build): `-ps.patient.width 375` lays My Patient out at that width, so a row can be checked on
/// the narrowest phone the CI simulator (402 pt) is wider than. Does nothing in a release build.
struct DebugContentWidth: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG
        if let w = Double(LaunchSeed.string("ps.patient.width")), w > 0 {
            content.frame(maxWidth: CGFloat(w)).frame(maxWidth: .infinity)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Chip sets: one line when it fits (1.10)

/// The four looks a chip can have (1.11, Ben's Q7 and Q8): one chip grammar, enforced here rather than by each row's
/// colours. A **choice** (one of a few: Class, Sex, the No/Yes pills) is ink-filled when chosen, inverted text, never a hue.
/// A **toggle** (any number on: GA, PNB, a flag) is tinted in the action colour with a ✓ when on. A **preset** (a one-tap
/// normal: Exam normal, Echo normal, NSR, None) has a green outline, and a ✓ once applied. An **add** chip ("+ ECG")
/// opens a page or reveals more: a grey outline with a "+". Red never marks a chip's state; PS.red is for clinical alerts.
enum ChipStyle: String, CaseIterable {
    case choice, toggle, preset, add

    /// The colour roles a look is built from (the tests check these; `ChipSet` maps them to the PS tokens).
    enum Tone: Equatable { case ink, inverted, action, green, neutral, secondary, line, clear }
    struct Look: Equatable {
        var fill: Tone
        var text: Tone
        var edge: Tone
        /// The symbol drawn before the words, when there is one ("checkmark", "plus").
        var mark: String?
    }

    /// The look of a chip that is on or off.
    func look(on: Bool) -> Look {
        switch self {
        case .choice:
            return on ? Look(fill: .ink, text: .inverted, edge: .clear, mark: nil) : Look(fill: .neutral, text: .secondary, edge: .line, mark: nil)
        case .toggle:
            return on ? Look(fill: .action, text: .ink, edge: .action, mark: "checkmark") : Look(fill: .neutral, text: .secondary, edge: .line, mark: nil)
        case .preset:
            return on ? Look(fill: .green, text: .ink, edge: .green, mark: "checkmark") : Look(fill: .neutral, text: .ink, edge: .green, mark: nil)
        case .add:
            return Look(fill: .neutral, text: .secondary, edge: .line, mark: "plus")
        }
    }

    /// One of a few: the chosen chip is filled solid (no ✓ forms).
    var isChoice: Bool { self == .choice }
    /// Chosen chips draw a ✓ (the one-line ✓ forms of ChipSet).
    var checks: Bool { self == .toggle || self == .preset }
    /// Every chip draws its mark, on or off (the add chip's "+").
    var alwaysMarked: Bool { self == .add }

    /// The PS colour for a tone; `tint` is the action colour of this row (PS.action unless a row says otherwise).
    static func color(_ tone: Tone, tint: Color) -> Color {
        switch tone {
        case .ink: return PS.fg
        case .inverted: return PS.bg
        case .action: return tint
        case .green: return PS.green
        case .neutral: return PS.surface2
        case .secondary: return PS.fg2
        case .line: return PS.line2
        case .clear: return .clear
        }
    }
}

/// A set of chips in the fewest lines. Ben (Nov 7): any chip set that fits one line without making the chips too small goes
/// on one line. The first of these that fits the width is used, else the chips wrap as they always did:
/// the full words with the usual padding; the full words with tighter padding; the short words (where an option has
/// them: "≥4 METs", "GA", "Upper abd"; VoiceOver always reads the full words) with the usual and then tighter padding;
/// the full and then the short words with the tightest padding. The font never gets smaller than the chip font. The
/// padding steps and the text size are in `ChipMetrics`, which the tests use to check a row at 375 and 402 pt.
///
/// A chosen toggle chip (several can be on) is never shown by colour alone (review 1.10; WCAG 2.1 SC 1.4.1, Use of
/// Color): on one line it reads "✓ Warfarin", as every chosen toggle chip did in 1.9. Only a chosen chip makes room for
/// the ✓, partly out of its own padding (never below the compact padding), so a tap widens it by little; the row may then
/// take a tighter padding, down to the compact one, to keep the ✓ on its line. Only a row that cannot fit its ✓ at any
/// padding but fit one line in 1.10 stays on one line without it, its chosen chips with a 1.5-pt outline in the full
/// tint (a heavier edge, not a hue), rather than wrapping; the wrapped form keeps the ✓ and bold text. A choice chip (one
/// of a few) is filled solid with inverted text, not a hue.
struct ChipSet: View {
    typealias Style = ChipStyle

    var options: [ChipChoice]
    var style: Style
    var tint: Color = PS.action
    var hints: [String: String] = [:]
    /// A row Ben asked for on one line with its full words (urgency, review 1.10) tries the compact padding last.
    var compact = false
    var isOn: (String) -> Bool
    var tap: (String) -> Void
    @Environment(PatientStore.self) private var store: PatientStore?
    /// InlineChoices' hidden measure of the row: only the first form without a ✓, the width 1.10 measured.
    @Environment(\.chipLineProbe) private var probe

    /// Any option has shorter words; without them the short forms are the full ones and are not tried twice.
    private var shorts: Bool { options.contains { $0.short != nil } }

    var body: some View {
        if probe {
            line(short: false, .regular)
        } else {
            forms
        }
    }

    private var forms: some View {
        // The order is ChipMetrics.forms(choice:compact:shorts:). Each form is a whole row of chips that ViewThatFits
        // keeps: a toggle row's ✓ forms (the ✓ only on chosen chips, so with none chosen they are the plain forms) down
        // to the compact padding, then only the narrowest forms without the ✓, which fit wherever a 1.10 form did.
        ViewThatFits(in: .horizontal) {
            if style.checks {
                Group {
                    line(short: false, .regular, check: true)
                    line(short: false, .tight, check: true)
                    if shorts {
                        line(short: true, .regular, check: true)
                        line(short: true, .tight, check: true)
                    }
                    line(short: false, .dense, check: true)
                    if shorts { line(short: true, .dense, check: true) }
                    compactCheck(short: false)
                    if shorts { compactCheck(short: true) }
                }
                Group {
                    line(short: false, .dense)
                    if shorts { line(short: true, .dense) }
                    if compact {
                        line(short: false, .compact)
                        if shorts { line(short: true, .compact) }
                    }
                }
            } else {
                line(short: false, .regular)
                line(short: false, .tight)
                if shorts {
                    line(short: true, .regular)
                    line(short: true, .tight)
                }
                line(short: false, .dense)
                if shorts { line(short: true, .dense) }
                if compact {
                    line(short: false, .compact)
                    if shorts { line(short: true, .compact) }
                }
            }
            WrapLayout(spacing: ChipMetrics.gap(.regular)) {
                ForEach(Array(options.enumerated()), id: \.offset) { chip($0.element, short: false, .regular, wrapped: true) }
            }
        }
    }

    /// The ✓ form at the compact padding, taken only where 1.10's narrowest form of the row (the dense one) fits too: it
    /// keeps a chosen chip's ✓ on a row 1.10 kept on one line, and never puts on one line a row 1.10 wrapped (which a
    /// tap could then wrap again). A compact row tried the compact padding in 1.10: its own form is the measure.
    @ViewBuilder private func compactCheck(short: Bool) -> some View {
        if compact {
            line(short: short, .compact, check: true)
        } else {
            CheckedLineLayout {
                line(short: short, .dense).hidden().allowsHitTesting(false).accessibilityHidden(true)
                line(short: short, .compact, check: true)
            }
        }
    }

    private func line(short: Bool, _ d: ChipMetrics.Density, check: Bool = false) -> some View {
        HStack(spacing: ChipMetrics.gap(d)) {
            ForEach(Array(options.enumerated()), id: \.offset) { chip($0.element, short: short, d, wrapped: false, check: check) }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func chip(_ o: ChipChoice, short: Bool, _ d: ChipMetrics.Density, wrapped: Bool, check: Bool = false) -> some View {
        let on = isOn(o.id)
        let choice = style.isChoice
        let look = style.look(on: on)
        // A chosen chip of a one-line ✓ form: the ✓, in room taken partly out of its padding (ChipMetrics.width); an add
        // chip's "+" is drawn in every form.
        let mark = (check && on && style.checks) || style.alwaysMarked
        // A one-line toggle row without the ✓ (no padding fits it): the chosen chip's heavier outline.
        let heavy = style.checks && on && !wrapped && !check
        let text = ChipStyle.color(look.text, tint: tint)
        let fill: Color = {
            switch look.fill {
            case .action: return tint.opacity(0.18)
            case .green: return PS.green.opacity(0.16)
            default: return ChipStyle.color(look.fill, tint: tint)
            }
        }()
        let edge: Color = {
            switch look.edge {
            case .action: return heavy ? tint : tint.opacity(0.55)
            case .green: return on ? PS.green : PS.green.opacity(0.6)
            default: return ChipStyle.color(look.edge, tint: tint)
            }
        }()
        return Button {
            Haptics.light()
            store?.markDiscrete()
            tap(o.id)
        } label: {
            HStack(spacing: wrapped ? ChipMetrics.checkGap : ChipMetrics.lineCheckGap) {
                if wrapped, style.checks, on { Image(systemName: "checkmark").font(PS.sys(size: ChipMetrics.checkFont, weight: .bold)) }
                // The symbol's own side margins overflow its frame, which is as wide as the ✓ it draws (checkWidth).
                if mark, let symbol = look.mark {
                    Image(systemName: symbol).font(PS.sys(size: ChipMetrics.checkFont, weight: .bold))
                        .frame(width: ChipMetrics.checkWidth)
                        .accessibilityHidden(true)
                }
                // Bold when chosen only where the row wraps: bold text is wider. (13.5 is scaled by PS.sys, as ChipMetrics.fontSize is.)
                Text(short ? o.shown : o.label)
                    .font(PS.sys(size: 13.5, weight: wrapped && on ? .semibold : .medium))
                    .lineLimit(wrapped ? nil : 1)
            }
            .foregroundStyle(text)
            .padding(.horizontal, ChipMetrics.hPad(d, choice: choice, checked: mark)).padding(.vertical, 7)
            .background(fill, in: Capsule())
            .overlay(Capsule().stroke(edge, lineWidth: heavy ? ChipMetrics.heavyEdge : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style == .add ? "Add " + o.label : o.label)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(hints[o.id] ?? "")
    }
}

/// ChipSet's compact ✓ form: its ideal width, which ViewThatFits compares with the room, is the wider of the hidden measure
/// (the row's dense form without the ✓) and the drawn row, so the form is taken only where both fit; given a width, it
/// is the drawn row's own, and only the drawn row shows.
struct CheckedLineLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let shown = subviews[1].sizeThatFits(.unspecified)
        guard proposal.width == nil || proposal.width == .infinity else { return shown }
        return CGSize(width: max(shown.width, subviews[0].sizeThatFits(.unspecified).width), height: shown.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        subviews[0].place(at: bounds.origin, proposal: .unspecified)
        subviews[1].place(at: bounds.origin, proposal: .unspecified)
    }
}

/// The chip font and the padding steps of a chip row, and how wide a row is: the tests check the rows against these.
enum ChipMetrics {
    enum Density { case regular, tight, dense, compact }
    /// Today's chip font (13.5 pt, scaled by the in-app text size).
    static var fontSize: CGFloat { (13.5 * PS.textScale).rounded(toPlaces: 1) }
    static func gap(_ d: Density) -> CGFloat {
        switch d { case .regular: return 7; case .tight: return 5; case .dense: return 4; case .compact: return 3 }
    }
    static func hPad(_ d: Density, choice: Bool) -> CGFloat {
        switch d { case .regular: return choice ? 12 : 11; case .tight: return 8; case .dense: return 6; case .compact: return 4 }
    }
    /// The padding of a chip, `checked` when it is a chosen toggle chip drawing its ✓ on one line: that chip gives
    /// `checkInset` of each side to the ✓, never going below the compact padding.
    static func hPad(_ d: Density, choice: Bool, checked: Bool) -> CGFloat {
        let pad = hPad(d, choice: choice)
        return checked ? max(hPad(.compact, choice: choice), pad - checkInset) : pad
    }

    /// The ✓ of a chosen toggle chip: its size (before the text-size scale, as PS.sys takes it), the width it draws
    /// (the glyph, without the symbol's side margins), and the space between it and the words, where the row wraps
    /// (1.9's) and on one line (a little less: every point counts there, and the symbol's margins are not in the slot).
    static let checkFont: CGFloat = 10.5
    static var checkWidth: CGFloat {
        let size = (checkFont * PS.textScale).rounded(toPlaces: 1)
        if let c = checkCache, c.size == size { return c.width }
        let config = UIImage.SymbolConfiguration(font: UIFont.systemFont(ofSize: size, weight: .bold))
        let image = UIImage(systemName: "checkmark", withConfiguration: config)
        let width = (image.flatMap(inkWidth) ?? image?.size.width ?? size * 1.1).rounded(.up)
        checkCache = (size, width)
        return width
    }
    /// The ✓ width at the last text size (every chosen chip of every one-line form asks for it).
    private static var checkCache: (size: CGFloat, width: CGFloat)?
    static let checkGap: CGFloat = 5
    static let lineCheckGap: CGFloat = 4
    /// What a chosen chip gives of its padding, on each side, to its ✓ on one line.
    static let checkInset: CGFloat = 2
    /// The outline of a chosen toggle chip in a one-line row with no room for the ✓.
    static let heavyEdge: CGFloat = 1.5

    /// How wide an image draws: its columns with any ink, at a quarter point (nil when nothing is drawn).
    static func inkWidth(_ image: UIImage) -> CGFloat? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 4
        format.opaque = false
        let raster = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(at: .zero) }
        guard let cg = raster.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var lo = w, hi = -1
        for y in 0..<h {
            for x in 0..<w where px[(y * w + x) * 4 + 3] > 16 {
                lo = min(lo, x)
                hi = max(hi, x)
            }
        }
        return hi >= lo ? CGFloat(hi - lo + 1) / 4 : nil
    }

    /// One one-line form of a row: the short words or the full ones, the padding, and whether its chosen toggle chips
    /// draw the ✓.
    typealias Form = (short: Bool, density: Density, check: Bool)

    /// The order the row tries its one-line forms in, without the ✓ (ChipSet.body).
    static let order: [(short: Bool, density: Density)] = [(false, .regular), (false, .tight), (true, .regular), (true, .tight), (false, .dense), (true, .dense)]
    /// The order of a row that may go compact (ChipSet.compact).
    static let compactOrder: [(short: Bool, density: Density)] = order + [(false, .compact), (true, .compact)]

    /// Every one-line form in the order ChipSet.body tries them: a toggle row tries each form with the ✓ first, down to
    /// the compact padding, then its narrowest forms without it (the dense ones, and the compact ones of a compact row),
    /// which fit wherever a form 1.10 tried fits; a choice row only the forms without it. Without short words (`shorts`
    /// false) the short forms, the same as the full ones, are left out.
    static func forms(choice: Bool, compact: Bool = false, shorts: Bool = true) -> [Form] {
        let base = (compact ? compactOrder : order).filter { shorts || !$0.short }
        let plain: [Form] = base.map { (short: $0.short, density: $0.density, check: false) }
        guard !choice else { return plain }
        let checked: [Form] = compactOrder.filter { shorts || !$0.short }.map { (short: $0.short, density: $0.density, check: true) }
        return checked + plain.filter { $0.density == .dense || $0.density == .compact }
    }

    /// The width of one line of chips, by the system font at the chip size and weight; `checked` marks the chips that
    /// draw a ✓ (the chosen toggle chips of a ✓ form), each with its ✓ and its smaller padding.
    static func width(_ labels: [String], density d: Density, choice: Bool, checked: [Bool] = []) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        var total = CGFloat(max(0, labels.count - 1)) * gap(d)
        for (i, label) in labels.enumerated() {
            let mark = i < checked.count && checked[i]
            total += (label as NSString).size(withAttributes: [.font: font]).width + 2 * hPad(d, choice: choice, checked: mark)
            if mark { total += checkWidth + lineCheckGap }
        }
        return total
    }

    /// The first one-line form that fits `width` with these chips chosen, nil when the row wraps. A toggle row's compact
    /// ✓ form needs its dense form without the ✓ to fit as well (ChipSet.compactCheck), unless the row is a compact one.
    static func lineFit(_ options: [ChipChoice], choice: Bool, in width: CGFloat, compact: Bool = false, selected: Set<String> = []) -> Form? {
        forms(choice: choice, compact: compact, shorts: options.contains { $0.short != nil }).first { o in
            let labels = options.map { o.short ? $0.shown : $0.label }
            if o.check, o.density == .compact, !compact, width < Self.width(labels, density: .dense, choice: choice) { return false }
            let checked = options.map { o.check && selected.contains($0.id) }
            return width >= Self.width(labels, density: o.density, choice: choice, checked: checked)
        }
    }
}

/// Toggle chips for a set of flags; several can be on. Each tap is an Undo step of its own. `shorts` give a narrow single
/// line shorter words by id (ChipSet).
struct PatientChips: View {
    var options: [PatientFlag]
    @Binding var selection: Set<String>
    var tint: Color = PS.action
    var shorts: [String: String] = [:]

    var body: some View {
        ChipSet(options: options.map { ChipChoice($0.id, $0.label, short: shorts[$0.id]) }, style: .toggle, tint: tint,
                hints: Dictionary(options.compactMap { o in o.detail.map { (o.id, $0) } }, uniquingKeysWith: { a, _ in a }),
                isOn: { selection.contains($0) },
                tap: { id in if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } })
    }
}

/// One choice among a few, as chips; tapping the chosen one clears it. Each tap is an Undo step of its own.
struct PatientChoice: View {
    var choices: [ChipChoice]
    @Binding var selection: String?
    /// Kept for callers; a choice chip is ink-filled, so no tint is drawn (ChipStyle.choice).
    var tint: Color = PS.action
    var compact = false

    init(options: [(id: String, label: String)], selection: Binding<String?>, tint: Color = PS.action, shorts: [String: String] = [:], compact: Bool = false) {
        choices = options.map { ChipChoice($0.id, $0.label, short: shorts[$0.id]) }
        _selection = selection
        self.tint = tint
        self.compact = compact
    }

    init(choices: [ChipChoice], selection: Binding<String?>, tint: Color = PS.action) {
        self.choices = choices
        _selection = selection
        self.tint = tint
    }

    var body: some View {
        ChipSet(options: choices, style: .choice, tint: tint, compact: compact, isOn: { selection == $0 },
                tap: { id in selection = selection == id ? nil : id })
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
                    // The suggested class as a chosen choice chip (ink, 1.11), not the brand red.
                    Text(PatientRules.roman(r.level))
                        .font(PS.mono(size: 12, weight: .bold))
                        .foregroundStyle(r.level == top ? PS.bg : PS.fg2)
                        .frame(minWidth: 36)
                        .padding(.vertical, 3)
                        .background(r.level == top ? PS.fg : PS.surface2, in: Capsule())
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
    /// 1.11 (one heading per thing): the tab hides the caption of a box that would restate its section title; the ⓘ then
    /// sits on the title line (PreopSectionTitle.info), so the note is not drawn here either.
    @Environment(\.patientCaptionHidden) private var captionHidden

    /// Whether a box draws its caption: it has one, and the section has not taken it over.
    static func showsCaption(title: String?, hidden: Bool) -> Bool { title != nil && !hidden }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, Self.showsCaption(title: title, hidden: captionHidden) { SectionHeader(title: title, info: note).padding(.leading, 2) }
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            if title == nil, let note, !note.isEmpty { EvidenceNote(note).padding(.horizontal, 2) }
        }
    }
}

private struct PatientCaptionHiddenKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// A PatientGroup under a section title that says the same thing draws no caption (1.11, P1-6).
    var patientCaptionHidden: Bool {
        get { self[PatientCaptionHiddenKey.self] }
        set { self[PatientCaptionHiddenKey.self] = newValue }
    }
}

extension View {
    /// The box's caption is the section title above it: draw the box without the caption (the ⓘ, if any, goes on the
    /// title: PreopSectionTitle.info).
    func patientCaptionHidden(_ hidden: Bool = true) -> some View { environment(\.patientCaptionHidden, hidden) }
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
