import Foundation

// MARK: - First-time tips on My Patient
//
// Four short coach marks, shown once, the first time My Patient appears after 1.8.1, and again from ⋯ → Show Tips:
// the quick-add bar, the three tabs, the ⋯ menu and the shield. Each points at its target from a small card with Next
// (Done on the last) and Skip. Finishing or skipping marks them seen (`seenKey`, kept on this phone); nothing about the
// patient is involved. PatientTipsView draws them.

/// What a tip points at: two targets in My Patient's scroll view (their frames come from anchor preferences) and two
/// navigation bar items (placed from the safe area and the bar's margins).
enum PatientTipTarget: Int, CaseIterable, Hashable {
    case quickAdd, tabs, more, shield

    /// In the scroll view, measured where it is drawn; otherwise a navigation bar item.
    var inScrollView: Bool { self == .quickAdd || self == .tabs }
}

struct PatientTip: Equatable {
    var target: PatientTipTarget
    var text: String
}

struct PatientTips: Equatable {
    /// Seen (finished or skipped) on this phone: they don't show on their own again.
    static let seenKey = "ps.tips.patient.v1"

    static let steps: [PatientTip] = [
        PatientTip(target: .quickAdd, text: "Type the patient in one line: age, sex, procedure, history, labs, lines. Chips show what will be filed; tap one to leave it out, then Add."),
        PatientTip(target: .tabs, text: "Preoperative, Intraoperative, then Summary & Handoff, which writes the handoff as you go."),
        PatientTip(target: .more, text: "More cases and rooms, End case, and Clear patient."),
        PatientTip(target: .shield, text: "No names, record numbers or dates of birth. Everything stays on this phone unless you send it."),
    ]

    /// How My Patient was opened, for whether the tips start on their own.
    enum Launch: Equatable {
        /// A person opening the app: the tips start the first time.
        case normal
        /// A screenshot run (debug builds, launched with -ps. arguments): never on their own, or every shot is covered.
        case screenshot
        /// A screenshot run with -ps.tips 1: shown at this step (0-based), seen or not.
        case forced(step: Int)
    }

    /// Finished or skipped, here or before (stored).
    private(set) var seen: Bool
    /// The step on screen (0-based), or nil while the tips are not showing.
    private(set) var step: Int?
    /// A forced screenshot run has shown them (once per launch).
    private var forcedShown = false

    init(seen: Bool = false) {
        self.seen = seen
    }

    var isShowing: Bool { step != nil }
    var current: PatientTip? { step.map { Self.steps[$0] } }
    var isLast: Bool { step == Self.steps.count - 1 }
    /// "1 of 4".
    var progress: String { step.map { "\($0 + 1) of \(Self.steps.count)" } ?? "" }

    /// My Patient appeared: the tips start if they have never been finished or skipped (`storedSeen`), except in a
    /// screenshot run, which shows them only when asked (-ps.tips 1, at -ps.tips.step N).
    mutating func appear(storedSeen: Bool, launch: Launch = .normal) {
        if storedSeen { seen = true }
        guard step == nil else { return }
        switch launch {
        case .normal:
            if !seen { step = 0 }
        case .screenshot:
            break
        case .forced(let n):
            guard !forcedShown else { return }
            forcedShown = true
            step = Self.clamped(n)
        }
    }

    /// ⋯ → Show Tips: from the first step, seen or not.
    mutating func showAgain() {
        step = 0
    }

    /// Next, or Done on the last step (which marks them seen).
    mutating func next() {
        guard let s = step else { return }
        if s + 1 < Self.steps.count { step = s + 1 } else { finish() }
    }

    /// Skip: closes them, seen.
    mutating func skip() {
        finish()
    }

    private mutating func finish() {
        step = nil
        seen = true
    }

    static func clamped(_ n: Int) -> Int { max(0, min(steps.count - 1, n)) }

    /// Debug builds launched with -ps. arguments are screenshot runs (CI); -ps.tips 1 shows the tips there, at
    /// -ps.tips.step N (1-based). Release builds are always `.normal`.
    static var launch: Launch {
        #if DEBUG
        if LaunchSeed.bool("ps.tips") { return .forced(step: LaunchSeed.int("ps.tips.step", default: 1) - 1) }
        let args = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        if args.keys.contains(where: { $0.hasPrefix("ps.") }) { return .screenshot }
        #endif
        return .normal
    }
}
