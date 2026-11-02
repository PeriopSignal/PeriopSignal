import SwiftUI

// MARK: - My Patient's first-time tips (PatientTips), drawn
//
// A dimmed layer over the whole tab with a rounded spotlight cut out around the target, a short arrow from a card to
// it, the card's text, and Next (Done on the last) and Skip. The quick-add bar and the tab bar are found where they
// are drawn (anchor preferences, read inside the navigation stack, which preferences don't cross). The ⋯ menu and the
// shield are navigation bar items, which anchors don't reach: each reports its own frame (onGeometryChange) into
// PatientTipBarFrames, which the overlay reads; until a frame comes in, or if one lies off the bar's row, the spotlight
// is placed on the row from the safe area's top, the inline bar's height and its margins.

/// Where the navigation bar's ⋯ menu and shield are, in global coordinates, as their toolbar items report them. Only
/// the tips' overlay reads it, so the reports redraw nothing else.
@Observable
final class PatientTipBarFrames {
    var frames: [PatientTipTarget: CGRect] = [:]
}

/// Where the tips' targets in the scroll view are: the quick-add bar and the tab bar.
struct PatientTipAnchorKey: PreferenceKey {
    static let defaultValue: [PatientTipTarget: Anchor<CGRect>] = [:]

    static func reduce(value: inout [PatientTipTarget: Anchor<CGRect>], nextValue: () -> [PatientTipTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }

    /// The anchors as rectangles in global coordinates.
    @MainActor static func globalRects(_ anchors: [PatientTipTarget: Anchor<CGRect>], in g: GeometryProxy) -> [PatientTipTarget: CGRect] {
        let origin = g.frame(in: .global).origin
        var rects: [PatientTipTarget: CGRect] = [:]
        for (target, anchor) in anchors {
            rects[target] = g[anchor].offsetBy(dx: origin.x, dy: origin.y)
        }
        return rects
    }
}

extension View {
    /// A navigation bar item the tips point at (the ⋯ menu or the shield): reports where it is drawn.
    func patientTipBarItem(_ target: PatientTipTarget, into bar: PatientTipBarFrames) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
            if bar.frames[target] != f { bar.frames[target] = f }
        }
    }

    /// A target of My Patient's tips, found where it is drawn.
    func patientTipTarget(_ target: PatientTipTarget) -> some View {
        anchorPreference(key: PatientTipAnchorKey.self, value: .bounds) { [target: $0] }
    }

    /// While the tips show (`active`), keeps `frames` up to date with where this view's tip targets are, in global
    /// coordinates; otherwise reads nothing, so scrolling redraws nothing.
    func readPatientTipFrames(_ active: Bool, into frames: Binding<[PatientTipTarget: CGRect]>) -> some View {
        overlayPreferenceValue(PatientTipAnchorKey.self) { anchors in
            GeometryReader { g in
                PatientTipFrameSink(rects: active ? PatientTipAnchorKey.globalRects(anchors, in: g) : [:], frames: frames)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Copies the targets' frames out to My Patient's state when they change.
struct PatientTipFrameSink: View {
    var rects: [PatientTipTarget: CGRect]
    @Binding var frames: [PatientTipTarget: CGRect]

    var body: some View {
        Color.clear
            .onAppear { if frames != rects { frames = rects } }
            .onChange(of: rects) { _, r in if frames != r { frames = r } }
    }
}

/// A spotlight: the hole cut out of the dimmed layer, in the overlay's coordinates.
struct PatientTipSpot: Equatable {
    var rect: CGRect
    var radius: CGFloat
}

/// The tips over My Patient: on the navigation stack, full screen, blocking touches underneath until Done or Skip.
struct PatientTipsOverlay: View {
    @Binding var tips: PatientTips
    /// The scroll view's targets, in global coordinates.
    var frames: [PatientTipTarget: CGRect]
    /// The navigation bar items' frames, as they report them.
    var bar: PatientTipBarFrames
    @Environment(\.colorScheme) private var scheme
    @AccessibilityFocusState private var textFocused: Bool

    /// The inline navigation bar, right under the safe area's top, and its round buttons (iOS 26, iPhone 16 Pro): 44 pt
    /// across, their centres 38.5 pt in from the screen's leading edge and 39.5 pt from its trailing edge, on the bar's
    /// middle. The ⋯ is the last item on the trailing side, with or without Undo beside it.
    static let barHeight: CGFloat = 44
    static let barItemLeading: CGFloat = 38.5
    static let barItemTrailing: CGFloat = 39.5
    /// Around a bar button: 5 pt clear of its 44 pt glass circle.
    static let barItemRadius: CGFloat = 27
    /// Around a target in the scroll view.
    static let padding: CGFloat = 6
    /// The arrow, and the gap between it and the spotlight.
    static let arrowLength: CGFloat = 34
    static let gap: CGFloat = 6

    var body: some View {
        GeometryReader { outer in
            // The reader keeps to the safe area, so its frame is the safe area (in run 207 its insets were added to it
            // a second time, which put the bar's spotlights 62 pt low); the window's own inset is preferred.
            let safeTop = Self.windowSafeTop() ?? outer.frame(in: .global).minY
            GeometryReader { g in
                let f = g.frame(in: .global)
                layer(size: g.size, origin: f.origin, safeTop: safeTop, screen: f)
            }
            .ignoresSafeArea()
        }
    }

    /// The top of the key window's safe area (the status bar's height), in global coordinates.
    @MainActor private static func windowSafeTop() -> CGFloat? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        guard let w = windows.first(where: \.isKeyWindow) ?? windows.first else { return nil }
        let top = w.safeAreaInsets.top
        return top > 0 ? top : nil
    }

    /// A bar item's spotlight, in global coordinates: around the item where it reported itself, when that is on the
    /// bar's row (`safeTop` to 44 pt below) on its own side of the screen; otherwise on the row's middle, the bar's
    /// margins in from the screen's edges.
    static func barSpot(_ target: PatientTipTarget, reported: CGRect?, safeTop: CGFloat, screen: CGRect) -> PatientTipSpot {
        var center = CGPoint(x: target == .more ? screen.maxX - barItemTrailing : screen.minX + barItemLeading,
                             y: safeTop + barHeight / 2)
        var r = barItemRadius
        if let f = reported, plausibleBarItem(f, target: target, safeTop: safeTop, screen: screen) {
            center = CGPoint(x: f.midX, y: f.midY)
            r = max(r, min(34, max(f.width, f.height) / 2 + 5))
        }
        return PatientTipSpot(rect: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r), radius: r)
    }

    /// A reported frame is a bar button's: button-sized, its middle on the bar's row and on the item's side.
    static func plausibleBarItem(_ f: CGRect, target: PatientTipTarget, safeTop: CGFloat, screen: CGRect) -> Bool {
        guard f.width >= 8, f.height >= 8, f.width <= 60, f.height <= 60 else { return false }
        guard f.midY >= safeTop, f.midY <= safeTop + barHeight else { return false }
        return target == .more ? (f.midX > screen.midX && f.midX < screen.maxX) : (f.midX < screen.midX && f.midX > screen.minX)
    }

    /// Where the current tip's spotlight goes, in the overlay's coordinates (`origin` is the overlay's global origin).
    private func spotlight(for target: PatientTipTarget, origin: CGPoint, safeTop: CGFloat, screen: CGRect) -> PatientTipSpot? {
        switch target {
        case .quickAdd, .tabs:
            guard let f = frames[target], f.width > 1, f.height > 1 else { return nil }
            let rect = f.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -Self.padding, dy: -Self.padding)
            return PatientTipSpot(rect: rect, radius: (target == .quickAdd ? PS.cardRadius : 16) + Self.padding)
        case .more, .shield:
            var s = Self.barSpot(target, reported: bar.frames[target], safeTop: safeTop, screen: screen)
            s.rect = s.rect.offsetBy(dx: -origin.x, dy: -origin.y)
            return s
        }
    }

    @ViewBuilder private func layer(size: CGSize, origin: CGPoint, safeTop: CGFloat, screen: CGRect) -> some View {
        if let tip = tips.current {
            let hole = self.spotlight(for: tip.target, origin: origin, safeTop: safeTop, screen: screen)
            let cardWidth = min(size.width - 32, 380)
            ZStack(alignment: .topLeading) {
                dim(size: size, spot: hole)
                if let hole {
                    ring(hole)
                    arrow(spot: hole, size: size, cardWidth: cardWidth)
                }
                placed(card(tip), spot: hole, size: size, cardWidth: cardWidth)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture {}   // nothing underneath takes a touch while the tips show
            .animation(.snappy, value: hole)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    // MARK: Parts

    /// The dimmed layer, with the spotlight cut out.
    private func dim(size: CGSize, spot: PatientTipSpot?) -> some View {
        Path { p in
            p.addRect(CGRect(origin: .zero, size: size))
            if let s = spot {
                p.addRoundedRect(in: s.rect, cornerSize: CGSize(width: s.radius, height: s.radius), style: .continuous)
            }
        }
        .fill(Color.black.opacity(scheme == .dark ? 0.62 : 0.48), style: FillStyle(eoFill: true))
        .accessibilityHidden(true)
    }

    private func ring(_ s: PatientTipSpot) -> some View {
        RoundedRectangle(cornerRadius: s.radius, style: .continuous)
            .stroke(Color.white.opacity(0.92), lineWidth: 2)
            .frame(width: s.rect.width, height: s.rect.height)
            .offset(x: s.rect.minX, y: s.rect.minY)
            .accessibilityHidden(true)
    }

    /// The card goes below a target in the top part of the screen and above one lower down.
    private static func below(_ s: PatientTipSpot, size: CGSize) -> Bool { s.rect.midY < size.height * 0.55 }

    /// From the card's edge to the spotlight's, kept over the card at its ends.
    private func arrow(spot s: PatientTipSpot, size: CGSize, cardWidth: CGFloat) -> some View {
        let cardX = (size.width - cardWidth) / 2
        let fromX = min(max(s.rect.midX, cardX + 30), cardX + cardWidth - 30)
        let down = Self.below(s, size: size)
        let tipY = down ? s.rect.maxY + Self.gap : s.rect.minY - Self.gap
        let fromY = down ? tipY + Self.arrowLength : tipY - Self.arrowLength
        return Self.arrowPath(from: CGPoint(x: fromX, y: fromY), to: CGPoint(x: s.rect.midX, y: tipY))
            .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .accessibilityHidden(true)
    }

    /// A line with an open head at `b`.
    static func arrowPath(from a: CGPoint, to b: CGPoint, head: CGFloat = 9) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        let angle: Double = atan2(Double(b.y - a.y), Double(b.x - a.x))
        let spread: Double = Double.pi * 0.78
        let h = Double(head)
        let left = CGPoint(x: b.x + CGFloat(h * cos(angle + spread)), y: b.y + CGFloat(h * sin(angle + spread)))
        let right = CGPoint(x: b.x + CGFloat(h * cos(angle - spread)), y: b.y + CGFloat(h * sin(angle - spread)))
        p.move(to: left)
        p.addLine(to: b)
        p.addLine(to: right)
        return p
    }

    /// The card under (or over) its spotlight, with room for the arrow; in the middle when there is no spotlight.
    @ViewBuilder private func placed<Card: View>(_ card: Card, spot: PatientTipSpot?, size: CGSize, cardWidth: CGFloat) -> some View {
        if let s = spot, Self.below(s, size: size) {
            VStack(spacing: 0) {
                Color.clear.frame(height: max(0, s.rect.maxY + Self.gap + Self.arrowLength))
                card.frame(width: cardWidth)
                Spacer(minLength: 0)
            }
            .frame(width: size.width, height: size.height)
        } else if let s = spot {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                card.frame(width: cardWidth)
                Color.clear.frame(height: max(0, size.height - (s.rect.minY - Self.gap - Self.arrowLength)))
            }
            .frame(width: size.width, height: size.height)
        } else {
            card.frame(width: cardWidth)
                .frame(width: size.width, height: size.height)
        }
    }

    private func card(_ tip: PatientTip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Tip " + tips.progress, color: PS.accent)
            Text(tip.text)
                .font(PS.sys(size: 15.5))
                .foregroundStyle(PS.fg)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($textFocused)
            HStack(spacing: 10) {
                if !tips.isLast {
                    Button { skip() } label: {
                        Text("Skip")
                            .font(PS.sys(size: 14, weight: .semibold))
                            .foregroundStyle(PS.fg2)
                            .padding(.vertical, 8)
                            .padding(.trailing, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Closes the tips")
                }
                Spacer(minLength: 0)
                Button { next() } label: { Text(tips.isLast ? "Done" : "Next") }
                    .buttonStyle(CapsuleButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(PS.line2, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 8)
        .onAppear { focusText() }
        .onChange(of: tips.step) { _, _ in focusText() }
    }

    // MARK: Actions

    private func next() {
        Haptics.light()
        withAnimation(.snappy) { tips.next() }
    }

    private func skip() {
        withAnimation(.snappy) { tips.skip() }
    }

    /// VoiceOver reads each step's text as it shows.
    private func focusText() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { textFocused = true }
    }
}
