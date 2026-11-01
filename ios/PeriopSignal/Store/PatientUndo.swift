import Foundation

// MARK: - Undo for My Patient
//
// Every change to the current case's record (PatientStore.update, clear, receive) keeps the record as it was, so Undo
// can step back through them on any tab or editor. The steps are kept per case, in memory only (never written to
// disk, gone when the app quits), at most `limit` of them. Typing makes many small changes: those less than `burst`
// seconds apart join one step. A discrete action (an add, a delete, a chip, toggle or stepper tap) is always a step of
// its own, and the next change after it starts a new one. Each case keeps its own steps, so switching rooms and back
// still lets you step back in each, and an Undo only ever changes the case on screen. Ending a case (End case or Next
// Patient) drops its steps.

struct PatientUndoHistory {
    /// Steps kept per case; the oldest go first.
    static let limit = 50
    /// Changes less than this many seconds apart (a burst of typing) make one step.
    static let burst: TimeInterval = 1

    /// The records before each step, by case, newest last.
    private var steps: [UUID: [PatientRecord]] = [:]
    /// The last change while a burst can still join its step: its case and time.
    private var open: (caseID: UUID, at: Date)?

    init() {}

    func canUndo(_ id: UUID) -> Bool { !(steps[id] ?? []).isEmpty }

    /// How many steps case `id` can undo.
    func depth(_ id: UUID) -> Int { steps[id]?.count ?? 0 }

    /// The record the next Undo of case `id` brings back.
    func top(_ id: UUID) -> PatientRecord? { steps[id]?.last }

    /// Called before case `id` changes from `before`: keeps it as a new step, unless the change continues the burst of
    /// the change before it (same case, not discrete, less than `burst` seconds later).
    mutating func willChange(_ before: PatientRecord, case id: UUID, discrete: Bool, now: Date = Date()) {
        var joins = false
        if !discrete, let o = open, o.caseID == id {
            let gap = now.timeIntervalSince(o.at)
            joins = gap >= 0 && gap < Self.burst
        }
        if !joins || !canUndo(id) {
            var list = steps[id] ?? []
            list.append(before)
            if list.count > Self.limit { list.removeFirst(list.count - Self.limit) }
            steps[id] = list
        }
        // A discrete action closes its step: the next change starts another.
        open = discrete ? nil : (id, now)
    }

    /// The record before the last step of case `id`, which Undo restores; the next change starts a new step.
    mutating func pop(_ id: UUID) -> PatientRecord? {
        open = nil
        guard var list = steps[id], let last = list.popLast() else { return nil }
        steps[id] = list.isEmpty ? nil : list
        return last
    }

    /// Drops case `id`'s steps.
    mutating func clear(_ id: UUID) {
        steps[id] = nil
        if open?.caseID == id { open = nil }
    }

    /// Drops the steps of every case not in `ids` (cases that were ended or removed).
    mutating func keep(only ids: Set<UUID>) {
        steps = steps.filter { ids.contains($0.key) }
        if let o = open, !ids.contains(o.caseID) { open = nil }
    }
}
