import SwiftUI

// MARK: - My Patient's first-time tips (PatientTips), drawn
//
// A dimmed layer over the whole tab with a rounded spotlight cut out around the target, a short arrow from a card to
// it, the card's text, and Next (Done on the last) and Skip: TipLayer (TipsView.swift), shared with the app's tips. The quick-add bar and the tab bar are found where they
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

/// A spotlight: the hole cut out of the dimmed layer (TipsView.swift's TipSpot, shared with the app's tips).
typealias PatientTipSpot = TipSpot

/// The tips over My Patient: on the navigation stack, full screen, blocking touches underneath until Done or Skip.
struct PatientTipsOverlay: View {
    @Binding var tips: PatientTips
    /// The scroll view's targets, in global coordinates.
    var frames: [PatientTipTarget: CGRect]
    /// The navigation bar items' frames, as they report them.
    var bar: PatientTipBarFrames

    /// The inline navigation bar, right under the safe area's top, and its round buttons (iOS 26, iPhone 16 Pro): 44 pt
    /// across, their centres 38.5 pt in from the screen's leading edge and 39.5 pt from its trailing edge, on the bar's
    /// middle. The ⋯ is the last item on the trailing side, with or without Undo beside it.
    static let barHeight: CGFloat = 44
    static let barItemLeading: CGFloat = 38.5
    static let barItemTrailing: CGFloat = 39.5
    /// Around a bar button: 5 pt clear of its 44 pt glass circle.
    static let barItemRadius: CGFloat = 27
    /// Around a target in the scroll view.
    static let padding: CGFloat = TipLayer.padding

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
            TipLayer(size: size,
                     spot: self.spotlight(for: tip.target, origin: origin, safeTop: safeTop, screen: screen),
                     text: tip.text,
                     progress: tips.progress,
                     isLast: tips.isLast,
                     step: tips.step ?? 0,
                     onNext: next,
                     onSkip: skip)
        }
    }

    /// A line with an open head at `b` (TipLayer draws it).
    static func arrowPath(from a: CGPoint, to b: CGPoint, head: CGFloat = 9) -> Path {
        TipLayer.arrowPath(from: a, to: b, head: head)
    }

    // MARK: Actions

    private func next() {
        Haptics.light()
        withAnimation(.snappy) { tips.next() }
    }

    private func skip() {
        withAnimation(.snappy) { tips.skip() }
    }
}
