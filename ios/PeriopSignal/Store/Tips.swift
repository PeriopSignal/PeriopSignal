import Foundation
import Observation

// MARK: - First-time tips, app-wide (1.8.1)
//
// A tip set is a few short coach marks, each pointing at one thing on screen with an arrow, shown once and then
// remembered on this phone under the set's own seen-key. A tap anywhere moves to the next tip (Done on the last); Skip
// closes the set. Sets:
//   tour       the first open after the welcome (and the terms): the Feed, My Patient and Reference tabs
//   reference  Reference home, first visit: the search field, then (only with no favorites) the first folder
//   patient    My Patient (PatientTips, drawn by My Patient itself: PatientView and PatientTipsOverlay)
// Tool-level tips (first non-emergency tool, Regional finder, Lines & Devices) come later; any view can be a target
// (`.tipTarget(id)`, read with `.readTipFrames(_:)`), and `TipSet.allowed(on:)` keeps them off emergency tools.
//
// Never on an emergency tool (ACLS, OB, LAST, MH, Difficult Airway): a first open may be a real emergency. Those
// screens block the tips while they are on screen (TipCenter.block), and a tip set showing when one opens is put away
// unseen, to come back later.
//
// Screenshot runs (debug builds launched with -ps. arguments) never start a set on their own, so no other shot is
// covered. Hooks:
//   -ps.tips 1 [-ps.tips.set tour|reference|patient] [-ps.tips.step N]   shows that set at step N (1-based), seen or
//   not; without -ps.tips.set it is My Patient's, as before 1.8.1 wave 2b.

/// One coach mark: what it points at (a target id) and what it says.
struct TipStep: Equatable {
    var target: String
    var text: String
}

/// What the tips point at. Targets in a view report their frames (`.tipTarget(id)`); the tab bar's items and the
/// Reference search field are system views, found where UIKit draws them (TipLocator).
enum TipTarget {
    static let feedTab = "tab.feed"
    static let patientTab = "tab.patient"
    static let referenceTab = "tab.reference"
    static let referenceSearch = "reference.search"
    static let referenceFirstFolder = "reference.firstFolder"
    /// The top of the Reference home's content, from which the search field is placed when UIKit doesn't say.
    static let referenceTop = "reference.top"

    /// The tab bar's items, in order, with their titles (as the tab bar reads them to VoiceOver).
    static let tabs: [(id: String, title: String)] = [
        (feedTab, "Feed"), (patientTab, "My Patient"), (referenceTab, "Reference"), ("tab.more", "More"),
    ]
}

/// A set of tips, shown once per phone.
struct TipSet: Equatable, Identifiable {
    /// Its name in launch arguments (-ps.tips.set).
    var id: String
    /// Finished or skipped on this phone.
    var seenKey: String
    var steps: [TipStep]

    /// The first open after the welcome: the three tabs, in order.
    static let tour = TipSet(id: "tour", seenKey: "ps.tips.tour.v1", steps: [
        TipStep(target: TipTarget.feedTab, text: "New practice-changing papers land here every morning."),
        TipStep(target: TipTarget.patientTab, text: "Enter your patient once; the calculators and handoff fill in from it."),
        TipStep(target: TipTarget.referenceTab, text: "Calculators, emergency checklists and echo grading live here."),
    ])

    static let referenceSeenKey = "ps.tips.reference.v1"

    /// Reference home, first visit: the search field, then the first folder only while there are no favorites.
    static func referenceHome(hasFavorites: Bool) -> TipSet {
        var steps = [TipStep(target: TipTarget.referenceSearch, text: "Search any drug, score or society, or ask a question if nothing matches.")]
        if !hasFavorites {
            steps.append(TipStep(target: TipTarget.referenceFirstFolder, text: "Tap ☆ inside any tool to pin it to the top of this page."))
        }
        return TipSet(id: "reference", seenKey: referenceSeenKey, steps: steps)
    }

    /// My Patient's four (PatientTips), unchanged from 1.8.1's My Patient cleanup.
    static let patient = TipSet(id: "patient", seenKey: "ps.tips.patient.v1", steps: [
        TipStep(target: "patient.quickAdd", text: "Type the patient in one line: age, sex, procedure, history, labs, lines. Chips show what will be filed; tap one to leave it out, then Add."),
        TipStep(target: "patient.tabs", text: "Preoperative, Intraoperative, then Summary & Handoff, which writes the handoff as you go."),
        TipStep(target: "patient.more", text: "More cases and rooms, End case, and Clear patient."),
        TipStep(target: "patient.shield", text: "No names, record numbers or dates of birth. Everything stays on this phone unless you send it."),
    ])

    /// The Reference tools no tip ever shows on: the Emergency folder (ACLS, OB, LAST, MH, Difficult Airway).
    static let emergencyRouteKeys: Set<String> = ["acls", "ob", "quickref:asra-last", "quickref:mhaus-mh", "airway"]

    /// Whether a tip may show on this Reference tool or folder (never on an emergency tool).
    static func allowed(onRouteKey key: String) -> Bool { !emergencyRouteKeys.contains(key) }
}

/// One tip set's state: whether it shows, and which step. My Patient's PatientTips wraps one of these.
struct Tips: Equatable {
    /// How the screen was opened, for whether the set starts on its own.
    enum Launch: Equatable {
        /// A person opening the app: the set starts the first time.
        case normal
        /// A screenshot run (debug builds, launched with -ps. arguments): never on its own, or every shot is covered.
        case screenshot
        /// A screenshot run asking for this set: shown at this step (0-based), seen or not.
        case forced(step: Int)
    }

    let tipSet: TipSet
    /// Finished or skipped, here or before (stored).
    private(set) var seen: Bool
    /// The step on screen (0-based), or nil while the set is not showing.
    private(set) var step: Int?
    /// A forced screenshot run has shown it (once per launch).
    private var forcedShown = false

    init(_ set: TipSet, seen: Bool = false) {
        self.tipSet = set
        self.seen = seen
    }

    var steps: [TipStep] { tipSet.steps }
    var isShowing: Bool { step != nil }
    var current: TipStep? { step.flatMap { steps.indices.contains($0) ? steps[$0] : nil } }
    var isLast: Bool { step == steps.count - 1 }
    /// "1 of 4"; empty for a set of one.
    var progress: String {
        guard let s = step, steps.count > 1 else { return "" }
        return "\(s + 1) of \(steps.count)"
    }

    /// The screen appeared: the set starts if it has never been finished or skipped (`storedSeen`), except in a
    /// screenshot run, which shows it only when asked.
    mutating func appear(storedSeen: Bool, launch: Launch = .normal) {
        if storedSeen { seen = true }
        guard step == nil, !steps.isEmpty else { return }
        switch launch {
        case .normal:
            if !seen { step = 0 }
        case .screenshot:
            break
        case .forced(let n):
            guard !forcedShown else { return }
            forcedShown = true
            step = clamped(n)
        }
    }

    /// Show Tips again: from the first step, seen or not.
    mutating func showAgain() {
        guard !steps.isEmpty else { return }
        step = 0
    }

    /// Next, or Done on the last step (which marks the set seen).
    mutating func next() {
        guard let s = step else { return }
        if s + 1 < steps.count { step = s + 1 } else { finish() }
    }

    /// Skip: closes the set, seen.
    mutating func skip() {
        finish()
    }

    /// Put away unseen (an emergency screen opened): it starts again from the top next time.
    mutating func putAway() {
        step = nil
    }

    private mutating func finish() {
        step = nil
        seen = true
    }

    func clamped(_ n: Int) -> Int { max(0, min(steps.count - 1, n)) }

    /// How this launch treats `set`, from its -ps. arguments (`args`: the launch arguments whose names start with
    /// "ps.", as strings). -ps.tips 1 asks for -ps.tips.set (My Patient's when absent) at -ps.tips.step N (1-based).
    static func launch(for setID: String, args: [String: String]) -> Launch {
        let truthy: (String?) -> Bool = { ["1", "true", "yes"].contains(($0 ?? "").lowercased()) }
        if truthy(args["ps.tips"]) {
            let wanted = (args["ps.tips.set"] ?? "").isEmpty ? TipSet.patient.id : args["ps.tips.set"]!
            if wanted == setID { return .forced(step: (Int(args["ps.tips.step"] ?? "") ?? 1) - 1) }
            return .screenshot
        }
        return args.keys.contains(where: { $0.hasPrefix("ps.") }) ? .screenshot : .normal
    }

    /// This launch, for `set`: always `.normal` in release builds.
    static func launch(for set: TipSet) -> Launch {
        #if DEBUG
        let raw = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var args: [String: String] = [:]
        for (k, v) in raw where k.hasPrefix("ps.") {
            if let s = v as? String { args[k] = s } else if let n = v as? NSNumber { args[k] = n.stringValue } else { args[k] = "" }
        }
        return launch(for: set.id, args: args)
        #else
        return .normal
        #endif
    }
}

/// The app's tips, one set at a time, over the tab bar (RootView draws them with TipsOverlay). My Patient's own set
/// stays on My Patient (PatientView); the Feed's alerts banner waits for both this and the first-open tour.
@MainActor
@Observable
final class TipCenter {
    /// The set showing, or nil.
    private(set) var showing: Tips?
    /// Where the targets that report themselves are, in global coordinates (only while a set shows).
    var frames: [String: CGRect] = [:]
    /// The first-open tour has been finished or skipped on this phone.
    private(set) var tourSeen: Bool
    /// Emergency screens on screen now: no tip starts, and one showing is put away.
    private var blockers: Set<String> = []
    /// Sets a screenshot run has already forced in this launch.
    @ObservationIgnored private var forced: Set<String> = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let launchFor: (TipSet) -> Tips.Launch

    init(defaults: UserDefaults = .standard, launch: @escaping (TipSet) -> Tips.Launch = { Tips.launch(for: $0) }) {
        self.defaults = defaults
        self.launchFor = launch
        self.tourSeen = defaults.bool(forKey: TipSet.tour.seenKey)
    }

    var isShowing: Bool { showing?.isShowing ?? false }
    var isBlocked: Bool { !blockers.isEmpty }

    /// The tour will start once the Feed is free (not seen, and not a screenshot run): the alerts banner waits for it.
    var tourPending: Bool { !tourSeen && launchFor(.tour) == .normal }

    /// The Feed's morning-alerts banner stays out of the way while any tip shows or the tour is still to come.
    var holdsBanner: Bool { isShowing || tourPending }

    func seen(_ set: TipSet) -> Bool { defaults.bool(forKey: set.seenKey) }

    /// Starts `set` if it has not been seen (or a screenshot run asks for it), nothing else shows and no emergency
    /// screen is open. Returns whether it is now showing.
    @discardableResult
    func offer(_ set: TipSet) -> Bool {
        guard !isShowing, blockers.isEmpty else { return false }
        var launch = launchFor(set)
        if case .forced = launch {
            if forced.contains(set.id) { launch = .screenshot } else { forced.insert(set.id) }
        }
        var t = Tips(set)
        t.appear(storedSeen: seen(set), launch: launch)
        guard t.isShowing else { return false }
        showing = t
        return true
    }

    /// A tap anywhere, Next or Done.
    func next() {
        guard var t = showing else { return }
        t.next()
        settle(t)
    }

    func skip() {
        guard var t = showing else { return }
        t.skip()
        settle(t)
    }

    private func settle(_ t: Tips) {
        if t.isShowing { showing = t; return }
        if t.seen {
            defaults.set(true, forKey: t.tipSet.seenKey)
            if t.tipSet.id == TipSet.tour.id { tourSeen = true }
        }
        showing = nil
        frames = [:]
    }

    /// An emergency screen appeared (`id`): no tips while it is up; one showing is put away unseen.
    func block(_ id: String) {
        blockers.insert(id)
        if showing != nil {
            showing = nil
            frames = [:]
        }
    }

    func unblock(_ id: String) {
        blockers.remove(id)
    }
}
