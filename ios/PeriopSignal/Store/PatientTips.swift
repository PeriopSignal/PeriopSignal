import Foundation

// MARK: - First-time tips on My Patient
//
// Four short coach marks, shown once, the first time My Patient appears after 1.8.1, and again from ⋯ → Show Tips:
// the quick-add bar, the three tabs, the ⋯ menu and the shield. Each points at its target from a small card with Next
// (Done on the last) and Skip. Finishing or skipping marks them seen (`seenKey`, kept on this phone); nothing about the
// patient is involved. PatientTipsView draws them.
//
// Since 1.8.1 wave 2b this is a thin wrapper over the app-wide tips (Tips.swift: `Tips` with `TipSet.patient`), kept
// so My Patient's views and tests use it unchanged. -ps.tips 1 without -ps.tips.set still means these.

/// What a tip points at: two targets in My Patient's scroll view (their frames come from anchor preferences) and two
/// navigation bar items (which report their own frames; placed on the bar's row from the safe area until they do).
enum PatientTipTarget: Int, CaseIterable, Hashable {
    case quickAdd, tabs, more, shield

    /// In the scroll view, measured where it is drawn; otherwise a navigation bar item.
    var inScrollView: Bool { self == .quickAdd || self == .tabs }

    /// Its target id in `TipSet.patient`.
    var tipID: String {
        switch self {
        case .quickAdd: return "patient.quickAdd"
        case .tabs: return "patient.tabs"
        case .more: return "patient.more"
        case .shield: return "patient.shield"
        }
    }

    init?(tipID: String) {
        guard let t = Self.allCases.first(where: { $0.tipID == tipID }) else { return nil }
        self = t
    }
}

struct PatientTip: Equatable {
    var target: PatientTipTarget
    var text: String
}

struct PatientTips: Equatable {
    /// Seen (finished or skipped) on this phone: they don't show on their own again.
    static let seenKey = TipSet.patient.seenKey

    static let steps: [PatientTip] = TipSet.patient.steps.compactMap { s in
        PatientTipTarget(tipID: s.target).map { PatientTip(target: $0, text: s.text) }
    }

    /// How My Patient was opened, for whether the tips start on their own: `.normal`, `.screenshot` (never on their
    /// own) or `.forced(step:)` (-ps.tips 1, at -ps.tips.step N).
    typealias Launch = Tips.Launch

    private var base: Tips

    init(seen: Bool = false) {
        base = Tips(.patient, seen: seen)
    }

    /// Finished or skipped, here or before (stored).
    var seen: Bool { base.seen }
    /// The step on screen (0-based), or nil while the tips are not showing.
    var step: Int? { base.step }

    var isShowing: Bool { base.isShowing }
    var current: PatientTip? { step.map { Self.steps[$0] } }
    var isLast: Bool { base.isLast }
    /// "1 of 4".
    var progress: String { base.progress }

    /// My Patient appeared: the tips start if they have never been finished or skipped (`storedSeen`), except in a
    /// screenshot run, which shows them only when asked (-ps.tips 1, at -ps.tips.step N).
    mutating func appear(storedSeen: Bool, launch: Launch = .normal) {
        base.appear(storedSeen: storedSeen, launch: launch)
    }

    /// ⋯ → Show Tips: from the first step, seen or not.
    mutating func showAgain() { base.showAgain() }

    /// Next, or Done on the last step (which marks them seen).
    mutating func next() { base.next() }

    /// Skip: closes them, seen.
    mutating func skip() { base.skip() }

    static func clamped(_ n: Int) -> Int { max(0, min(steps.count - 1, n)) }

    /// Debug builds launched with -ps. arguments are screenshot runs (CI); -ps.tips 1 shows the tips there, at
    /// -ps.tips.step N (1-based), unless -ps.tips.set names another set. Release builds are always `.normal`.
    static var launch: Launch { Tips.launch(for: .patient) }
}
