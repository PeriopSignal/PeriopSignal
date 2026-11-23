import Foundation

// MARK: - Bypass and aortic cross-clamp runs
//
// Ben, Nov 23: "Have ability to change bypass start time. And add total bypass time to handoff (have ability to add new bypass run
// too)". Asked how the handoff should show it he chose "Total only" (one line, the sum of all runs), and for the aortic cross-clamp
// he chose "Bypass and cross-clamp": on/off buttons in Case Timers, editable times, the total in the handoff.
//
// A run is a start time and, once it has ended, an end time. HeparinCourse keeps a list of bypass runs and a list of cross-clamp
// runs, each in start-time order. What these do is record times: nothing here advises anything, and the ACT, heparin and protamine
// logic reads only `onBypass`, which keeps its meaning (the latest bypass run has no end).

/// One run of bypass, or one aortic cross-clamp: when it started and, if it has ended, when.
struct BypassRun: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: Date
    /// nil: still running.
    var end: Date?

    init(id: UUID = UUID(), start: Date, end: Date? = nil) {
        self.id = id; self.start = start; self.end = end
    }

    var isOpen: Bool { end == nil }

    /// Seconds from the start to the end, or to `now` while it runs; never negative.
    func seconds(at now: Date) -> TimeInterval { max(0, (end ?? now).timeIntervalSince(start)) }
}

/// The two lists a course keeps, and the words each is told in.
enum BypassRunKind: String, CaseIterable {
    case bypass, clamp

    /// The button that starts a run ("Bypass on", "Cross-clamp on").
    var onTitle: String { self == .bypass ? "Bypass on" : "Cross-clamp on" }
    /// The button that ends the open run.
    var offTitle: String { self == .bypass ? "Bypass off" : "Cross-clamp off" }
    /// "On bypass since 08:40", "Cross-clamp on since 08:55".
    func openText(since time: String) -> String {
        self == .bypass ? "On bypass since \(time)" : "Cross-clamp on since \(time)"
    }
    /// "Bypass 1 h 32 min", "Cross-clamp 1 h 08 min": the total, once every run has ended.
    func totalText(_ duration: String) -> String { (self == .bypass ? "Bypass " : "Cross-clamp ") + duration }
    /// The handoff's label.
    var handoffLabel: String { self == .bypass ? "Bypass time" : "Cross-clamp time" }
    /// The handoff's words for a run still going, after the time so far.
    func handoffOpenText(since time: String) -> String {
        self == .bypass ? "on bypass since \(time)" : "still on since \(time)"
    }
}

enum BypassRunText {
    static let endBeforeStart = "The end is before the start."
    static let overlap = "That overlaps another run."

    /// Whole minutes, rounded to the nearest: "52 min", "1 h 08 min", "2 h 00 min".
    static func duration(_ seconds: TimeInterval) -> String {
        let m = max(0, Int((seconds / 60).rounded()))
        return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60)) min" : "\(m) min"
    }

    /// "Run 1 · 08:40–10:12 · 1 h 32 min"; a run still going: "Run 2 · 10:35– · 12 min". `time` writes a clock time.
    static func runLine(_ number: Int, _ run: BypassRun, now: Date, time: (Date) -> String) -> String {
        let span = time(run.start) + "–" + (run.end.map(time) ?? "")
        return "Run \(number) · \(span) · \(duration(run.seconds(at: now)))"
    }
}

extension HeparinCourse {
    /// A time this far ahead of the clock is still accepted (the phone's clock and the picker's minute).
    static let runClockSlack: TimeInterval = 60

    /// The runs of one list, in start-time order.
    func runs(_ kind: BypassRunKind) -> [BypassRun] { kind == .bypass ? bypassRuns : clampRuns }

    mutating func setRuns(_ kind: BypassRunKind, _ runs: [BypassRun]) {
        let sorted = runs.sorted { $0.start < $1.start }
        if kind == .bypass { bypassRuns = sorted } else { clampRuns = sorted }
    }

    /// A run of this kind has started and not ended.
    func isRunning(_ kind: BypassRunKind) -> Bool { runs(kind).last?.isOpen ?? false }

    /// The sum of every run, an open one counted up to `now`.
    func totalSeconds(_ kind: BypassRunKind, at now: Date) -> TimeInterval {
        runs(kind).reduce(0) { $0 + $1.seconds(at: now) }
    }

    /// Starts a run at `now` and keeps the earlier ones (a "Bypass on" after a "Bypass off" is a new run, not a restart). Nothing
    /// happens while a run is open. A run cannot start before the last one ended, so a last end a moment ahead of the clock moves
    /// the start to it. False: nothing started.
    @discardableResult
    mutating func startRun(_ kind: BypassRunKind, at now: Date) -> Bool {
        guard !isRunning(kind) else { return false }
        var list = runs(kind)
        let start = max(now, list.last?.end ?? now)
        list.append(BypassRun(start: start))
        setRuns(kind, list)
        return true
    }

    /// Ends the open run at `now` (never before its start). False: no run was open.
    @discardableResult
    mutating func endRun(_ kind: BypassRunKind, at now: Date) -> Bool {
        var list = runs(kind)
        guard let i = list.indices.last, list[i].isOpen else { return false }
        list[i].end = max(now, list[i].start)
        setRuns(kind, list)
        return true
    }

    /// Why a run cannot take this start and end, or nil when it can: an end before its start, a run that overlaps another run of the
    /// same list, a time in the future (a minute of clock slack). Nothing else is checked (a cross-clamp need not sit inside a
    /// bypass run).
    func runIssue(_ kind: BypassRunKind, id: UUID, start: Date, end: Date?, now: Date) -> String? {
        if let end, end < start { return BypassRunText.endBeforeStart }
        let limit = now.addingTimeInterval(Self.runClockSlack)
        if start > limit || (end.map { $0 > limit } ?? false) { return HeparinTimeline.futureText }
        for other in runs(kind) where other.id != id {
            if start < (other.end ?? .distantFuture) && other.start < (end ?? .distantFuture) { return BypassRunText.overlap }
        }
        return nil
    }

    /// Changes a run's start and end. Returns the reason when it is refused, and then nothing has changed; nil when it was done (or
    /// the run is not in the list, which changes nothing either).
    @discardableResult
    mutating func changeRun(_ kind: BypassRunKind, id: UUID, start: Date, end: Date?, now: Date) -> String? {
        if let reason = runIssue(kind, id: id, start: start, end: end, now: now) { return reason }
        var list = runs(kind)
        guard let i = list.firstIndex(where: { $0.id == id }) else { return nil }
        list[i].start = start
        list[i].end = end
        setRuns(kind, list)
        return nil
    }

    mutating func deleteRun(_ kind: BypassRunKind, id: UUID) {
        setRuns(kind, runs(kind).filter { $0.id != id })
    }

    /// An older saved case has only the two times: one run, its end kept only when it is not before its start. An "off" earlier
    /// than the "on" meant a new "on" had been pressed since (the old button cleared nothing but the display), so that run is open.
    static func legacyRuns(on: Date?, off: Date?) -> [BypassRun] {
        guard let on else { return [] }
        let end = off.flatMap { $0 >= on ? $0 : nil }
        return [BypassRun(start: on, end: end)]
    }

    /// The handoff's line for one list, nil when there is no run: the total (an open run counted to `now`) and the count when more
    /// than one; a run still going says so with its start ("52 min so far, on bypass since 08:40"). `time` is the handoff's own
    /// time style (PatientSummary.time).
    func handoffLine(_ kind: BypassRunKind, now: Date, time: (Date) -> String) -> String? {
        let list = runs(kind)
        guard !list.isEmpty else { return nil }
        let total = BypassRunText.duration(totalSeconds(kind, at: now))
        let count = list.count > 1 ? " (\(list.count) runs)" : ""
        if let open = list.last, open.isOpen {
            return total + " so far" + count + ", " + kind.handoffOpenText(since: time(open.start))
        }
        return total + count
    }
}
