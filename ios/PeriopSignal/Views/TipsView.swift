import SwiftUI
import UIKit

// MARK: - First-time tips, drawn (Tips.swift)
//
// TipLayer is the one look for every tip set, My Patient's included: a dimmed layer with a rounded spotlight cut out
// around the target, a short arrow from a card to it, the card's text, and Next (Done on the last) and Skip. The app's
// sets (TipCenter) are drawn by TipsOverlay over the whole tab view, tab bar included; their targets are views that
// report their frames (`.tipTarget(id)`, read with `.readTipFrames(_:into:)` inside each navigation stack, which
// preferences don't cross) or system views found where UIKit draws them (TipLocator: the tab bar's items and the
// Reference search field), with a measured fallback for each.

/// A spotlight: the hole cut out of the dimmed layer, in the overlay's coordinates.
struct TipSpot: Equatable {
    var rect: CGRect
    var radius: CGFloat
}

/// Where the app's tip targets are, as views report them.
struct TipAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// A target of the app's tips (`TipTarget`), found where it is drawn. Any view can be one.
    func tipTarget(_ id: String) -> some View {
        anchorPreference(key: TipAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// While a tip set shows, keeps `center.frames` up to date with where this view's tip targets are, in global
    /// coordinates; otherwise reads nothing, so scrolling redraws nothing. Put it inside the navigation stack.
    /// `active` is the caller's `center.isShowing`, passed as a value so the reader redraws when it changes (run 229,
    /// shot 245: read inside the closure, the first folder's frame never arrived).
    @MainActor func readTipFrames(_ active: Bool, into center: TipCenter) -> some View {
        overlayPreferenceValue(TipAnchorKey.self) { anchors in
            GeometryReader { g in
                let origin = g.frame(in: .global).origin
                let rects: [String: CGRect] = active
                    ? anchors.mapValues { g[$0].offsetBy(dx: origin.x, dy: origin.y) }
                    : [:]
                TipFrameSink(rects: rects, center: center)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// A target that reports its own frame into `center` as it is laid out (onGeometryChange), for views whose anchor
    /// preferences don't reach a reader (run 242, shot 245: a folder row in the Reference home's lazy stack).
    @MainActor func tipFrame(_ id: String, in center: TipCenter) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
            if center.frames[id] != f { center.frames[id] = f }
        }
    }

    /// An emergency screen: while it is up, no tip starts and one showing is put away (TipCenter.block).
    @MainActor func blocksTips(_ blocks: Bool, id: String, in center: TipCenter) -> some View {
        onAppear { if blocks { center.block(id) } }
            .onDisappear { if blocks { center.unblock(id) } }
    }
}

/// Copies a view's target frames into the center when they change (merged: other stacks report their own).
@MainActor
struct TipFrameSink: View {
    var rects: [String: CGRect]
    var center: TipCenter

    var body: some View {
        Color.clear
            .onAppear { merge(rects) }
            .onChange(of: rects) { _, r in merge(r) }
    }

    private func merge(_ r: [String: CGRect]) {
        for (k, v) in r where center.frames[k] != v { center.frames[k] = v }
    }
}

/// System views the tips point at, found in the key window (global coordinates), with measured fallbacks.
@MainActor
enum TipLocator {
    static func keyWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    private static func visible(_ v: UIView) -> Bool {
        guard v.window != nil, !v.isHidden, v.alpha > 0.01 else { return false }
        var p = v.superview
        while let s = p { if s.isHidden || s.alpha < 0.01 { return false }; p = s.superview }
        return true
    }

    private static func descendants(of v: UIView) -> [UIView] {
        v.subviews + v.subviews.flatMap { descendants(of: $0) }
    }

    /// The tab bar's item `index` of `count`, titled `title`: the visible view VoiceOver reads by that title, else an
    /// equal share of the tab bar, else of iOS 26's floating bar measured on an iPhone 16 Pro (21 pt in from each
    /// side, 60 pt tall, its foot 23 pt above the screen's).
    static func tabItem(index: Int, count: Int, title: String) -> CGRect? {
        guard let w = keyWindow(), count > 0 else { return nil }
        let bars = descendants(of: w).compactMap { $0 as? UITabBar }.filter(visible)
        if let bar = bars.first {
            let matches = descendants(of: bar).filter { v in
                guard visible(v), let label = v.accessibilityLabel, label == title || label.hasPrefix(title + ",") else { return false }
                let f = v.convert(v.bounds, to: nil)
                return f.width >= 24 && f.width <= 220 && f.height >= 24 && f.height <= 110
            }
            if let best = matches.min(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) {
                return best.convert(best.bounds, to: nil)
            }
            var f = bar.convert(bar.bounds, to: nil)
            if f.width >= w.bounds.width - 1 { f = f.insetBy(dx: 21, dy: 0) }
            let itemW = f.width / CGFloat(count)
            return CGRect(x: f.minX + itemW * CGFloat(index), y: f.minY, width: itemW, height: min(f.height, 60))
        }
        let b = w.bounds
        let floating = CGRect(x: b.minX + 21, y: b.maxY - 23 - 60, width: b.width - 42, height: 60)
        let itemW = floating.width / CGFloat(count)
        return CGRect(x: floating.minX + itemW * CGFloat(index), y: floating.minY, width: itemW, height: floating.height)
    }

    /// The visible search field in the top half of the screen (the Reference tab's), if UIKit has one.
    static func searchField() -> CGRect? {
        guard let w = keyWindow() else { return nil }
        let fields = descendants(of: w).compactMap { $0 as? UISearchTextField }.filter(visible)
        return fields.map { $0.convert($0.bounds, to: nil) }
            .first { $0.width > 100 && $0.height > 20 && $0.midY < w.bounds.height / 2 }
    }
}

/// The app's tips (TipCenter) over the whole tab view, the tab bar included.
@MainActor
struct TipsOverlay: View {
    var center: TipCenter

    var body: some View {
        GeometryReader { g in
            let f = g.frame(in: .global)
            if let t = center.showing, let tip = t.current {
                TipLayer(size: g.size,
                         spot: spot(for: tip.target, screen: f).map { s in
                             TipSpot(rect: s.rect.offsetBy(dx: -f.minX, dy: -f.minY), radius: s.radius)
                         },
                         text: tip.text,
                         progress: t.progress,
                         isLast: t.isLast,
                         step: t.step ?? 0,
                         tapAdvances: true,
                         onNext: { Haptics.light(); withAnimation(.snappy) { center.next() } },
                         onSkip: { withAnimation(.snappy) { center.skip() } })
            }
        }
        .ignoresSafeArea()
    }

    /// Where `target`'s spotlight goes, in global coordinates.
    @MainActor private func spot(for target: String, screen: CGRect) -> TipSpot? {
        if let i = TipTarget.tabs.firstIndex(where: { $0.id == target }),
           let f = TipLocator.tabItem(index: i, count: TipTarget.tabs.count, title: TipTarget.tabs[i].title) {
            let r = f.insetBy(dx: -2, dy: -2)
            return TipSpot(rect: r, radius: min(r.height, r.width) / 2)
        }
        if target == TipTarget.referenceSearch {
            if let f = TipLocator.searchField() {
                return TipSpot(rect: f.insetBy(dx: -5, dy: -5), radius: f.height / 2 + 5)
            }
            // Measured on an iPhone 16 Pro: the drawer's field is 42 pt tall, 16 pt in from each side, its foot 21 pt
            // above the content.
            if let top = center.frames[TipTarget.referenceTop], top.height > 1 {
                let f = CGRect(x: screen.minX + 16, y: top.minY - 21 - 42, width: screen.width - 32, height: 42)
                return TipSpot(rect: f.insetBy(dx: -5, dy: -5), radius: 26)
            }
            return nil
        }
        guard let f = center.frames[target], f.width > 1, f.height > 1 else { return nil }
        return TipSpot(rect: f.insetBy(dx: -6, dy: -6), radius: PS.cardRadius + 6)
    }
}

/// One tip, drawn: the dimmed layer with its spotlight, the arrow and the card. Blocks touches underneath; with
/// `tapAdvances` a tap anywhere moves on (Done on the last).
struct TipLayer: View {
    var size: CGSize
    var spot: TipSpot?
    var text: String
    /// "1 of 4", or empty for a set of one.
    var progress: String
    var isLast: Bool
    var step: Int
    var tapAdvances = false
    var onNext: () -> Void
    var onSkip: () -> Void
    @Environment(\.colorScheme) private var scheme
    @AccessibilityFocusState private var textFocused: Bool

    /// Around a target in a scroll view.
    static let padding: CGFloat = 6
    /// The arrow, and the gap between it and the spotlight.
    static let arrowLength: CGFloat = 34
    static let gap: CGFloat = 6

    var body: some View {
        let cardWidth = min(size.width - 32, 380)
        ZStack(alignment: .topLeading) {
            dim
            if let spot {
                ring(spot)
                arrow(spot: spot, cardWidth: cardWidth)
            }
            placed(card, cardWidth: cardWidth)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { if tapAdvances { onNext() } }   // otherwise nothing underneath takes a touch
        .animation(.snappy, value: spot)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Parts

    /// The dimmed layer, with the spotlight cut out.
    private var dim: some View {
        Path { p in
            p.addRect(CGRect(origin: .zero, size: size))
            if let s = spot {
                p.addRoundedRect(in: s.rect, cornerSize: CGSize(width: s.radius, height: s.radius), style: .continuous)
            }
        }
        .fill(Color.black.opacity(scheme == .dark ? 0.62 : 0.48), style: FillStyle(eoFill: true))
        .accessibilityHidden(true)
    }

    private func ring(_ s: TipSpot) -> some View {
        RoundedRectangle(cornerRadius: s.radius, style: .continuous)
            .stroke(Color.white.opacity(0.92), lineWidth: 2)
            .frame(width: s.rect.width, height: s.rect.height)
            .offset(x: s.rect.minX, y: s.rect.minY)
            .accessibilityHidden(true)
    }

    /// The card goes below a target in the top part of the screen and above one lower down.
    static func below(_ s: TipSpot, size: CGSize) -> Bool { s.rect.midY < size.height * 0.55 }

    /// From the card's edge to the spotlight's, kept over the card at its ends.
    private func arrow(spot s: TipSpot, cardWidth: CGFloat) -> some View {
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
    @ViewBuilder private func placed<Card: View>(_ card: Card, cardWidth: CGFloat) -> some View {
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

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: progress.isEmpty ? "Tip" : "Tip " + progress, color: PS.accent)
            Text(text)
                .font(PS.sys(size: 15.5))
                .foregroundStyle(PS.fg)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($textFocused)
            HStack(spacing: 10) {
                if !isLast {
                    Button { onSkip() } label: {
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
                Button { onNext() } label: { Text(isLast ? "Done" : "Next") }
                    .buttonStyle(CapsuleButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(PS.line2, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 8)
        .onAppear { focusText() }
        .onChange(of: step) { _, _ in focusText() }
    }

    /// VoiceOver reads each step's text as it shows.
    private func focusText() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { textFocused = true }
    }
}
