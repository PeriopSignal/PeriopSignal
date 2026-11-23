import SwiftUI

// The bypass and cross-clamp rows of Case Timers' Heparin & ACT log (Ben, Nov 23: "Have ability to change bypass start time. And add
// total bypass time to handoff (have ability to add new bypass run too)"). Each list of runs (BypassRuns.swift) has its own section:
// the state row with its button, the runs one to a line, and the editor a tap on a run opens in place. The editor is the log's own
// (the same time rows, box, delete step and Save/Cancel buttons as a changed heparin or ACT entry); the page holds the one open
// editor and does the writing, so these views hold no course of their own.

/// A run opened for change: the times its row shows, and the times picked so far (nil: unchanged).
struct BypassRunEdit: Equatable {
    var kind: BypassRunKind
    var id: UUID
    var shownStart: Date
    var shownEnd: Date?
    var pickedStart: Date?
    var pickedEnd: Date?
    var deleteArmed = false
}

/// What the page does for a section's buttons; each one is one Undo step.
struct BypassRunActions {
    var start: () -> Void
    var end: () -> Void
    var save: (UUID, Date, Date?) -> Void
    var delete: (UUID) -> Void
}

/// One list of runs: the state row, then the runs.
struct BypassRunSection: View {
    var kind: BypassRunKind
    var course: HeparinCourse
    @Binding var editing: BypassRunEdit?
    var actions: BypassRunActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BypassRunStateRow(kind: kind, course: course, actions: actions)
            BypassRunList(kind: kind, course: course, editing: $editing, actions: actions)
        }
    }
}

/// No run yet: "Bypass on". A run open: "On bypass since 08:40" and "Bypass off". Every run ended: the total, and "Bypass on", which
/// starts a new run and keeps the earlier ones.
private struct BypassRunStateRow: View {
    var kind: BypassRunKind
    var course: HeparinCourse
    var actions: BypassRunActions

    var body: some View {
        HStack(spacing: 10) {
            if let open = course.runs(kind).last, open.isOpen {
                Text(kind.openText(since: HeparinTimeline.timeText(open.start, now: Date())))
                    .font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.accent2)
                Spacer()
                Button(kind.offTitle) { actions.end() }.buttonStyle(CapsuleButtonStyle(prominent: false))
            } else {
                if !course.runs(kind).isEmpty {
                    Text(kind.totalText(BypassRunText.duration(course.totalSeconds(kind, at: Date()))))
                        .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2)
                }
                Spacer()
                Button(kind.onTitle) { actions.start() }.buttonStyle(CapsuleButtonStyle(prominent: false))
            }
        }
    }
}

/// The runs, one line each; a tap opens that run's editor in its place.
private struct BypassRunList: View {
    var kind: BypassRunKind
    var course: HeparinCourse
    @Binding var editing: BypassRunEdit?
    var actions: BypassRunActions

    var body: some View {
        let list = course.runs(kind)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, run in
                    if i > 0 { Hairline() }
                    if let ed = editing, ed.kind == kind, ed.id == run.id {
                        BypassRunEditor(ed: ed, number: i + 1, course: course, editing: $editing, actions: actions)
                    } else {
                        BypassRunLine(number: i + 1, run: run) { open(run) }
                    }
                }
            }
            Text("Tap a run to change its times.").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
        }
    }

    private func open(_ run: BypassRun) {
        Haptics.light()
        withAnimation(.snappy) { editing = BypassRunEdit(kind: kind, id: run.id, shownStart: run.start, shownEnd: run.end) }
    }
}

/// "Run 1 · 08:40–10:12 · 1 h 32 min"; a run still going counts with the clock, as the page's other running times do.
private struct BypassRunLine: View {
    var number: Int
    var run: BypassRun
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if run.isOpen {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in text(ctx.date) }
                } else {
                    text(Date())
                }
            }
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Change its times, or delete it")
    }

    private func text(_ now: Date) -> some View {
        Text(BypassRunText.runLine(number, run, now: now) { HeparinTimeline.timeText($0, now: now) })
            .font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A run's start and, once it has ended, its end, in the log's own time rows, with a delete step and Save and Cancel. A refused
/// change shows its reason in the page's warning style and Save is off, so nothing is written.
private struct BypassRunEditor: View {
    var ed: BypassRunEdit
    var number: Int
    var course: HeparinCourse
    @Binding var editing: BypassRunEdit?
    var actions: BypassRunActions

    /// The start and end as picked; nil when one is in the future (the page's own check of a picked time).
    private func values(_ now: Date) -> (start: Date, end: Date?)? {
        guard let s = HeparinTimeline.resolvedEdit(picked: ed.pickedStart, original: ed.shownStart, now: now) else { return nil }
        guard let shownEnd = ed.shownEnd else { return (s, nil) }
        guard let e = HeparinTimeline.resolvedEdit(picked: ed.pickedEnd, original: shownEnd, now: now) else { return nil }
        return (s, e)
    }

    private func reason(_ now: Date) -> String? {
        guard let v = values(now) else { return HeparinTimeline.futureText }
        return course.runIssue(ed.kind, id: ed.id, start: v.start, end: v.end, now: now)
    }

    private var title: String { (ed.kind == .bypass ? "Bypass run " : "Cross-clamp run ") + "\(number)" }

    var body: some View {
        let now = Date()
        let issues = reason(now).map { [DoseIssue(level: .block, text: $0)] } ?? []
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            EntryTimeRow(title: "Start", base: ed.shownStart,
                         picked: Binding(get: { editing?.pickedStart }, set: { editing?.pickedStart = $0; editing?.deleteArmed = false }))
            endRow
            DoseIssueList(issues: issues)
            HStack(spacing: 10) {
                Button { deleteTapped() } label: {
                    Label(ed.deleteArmed ? "Confirm delete" : "Delete", systemImage: "trash")
                }
                .buttonStyle(CapsuleButtonStyle(prominent: ed.deleteArmed, color: PS.red))
                Spacer(minLength: 4)
                Button("Cancel") { withAnimation(.snappy) { editing = nil } }.buttonStyle(CapsuleButtonStyle(prominent: false))
                CheckedLogButton(title: "Save", issues: issues, armed: .constant(false)) { save() }
            }
        }
        .entryBox()
    }

    @ViewBuilder private var endRow: some View {
        if let shownEnd = ed.shownEnd {
            EntryTimeRow(title: "End", base: shownEnd,
                         picked: Binding(get: { editing?.pickedEnd }, set: { editing?.pickedEnd = $0; editing?.deleteArmed = false }))
        } else {
            Text("Still running. \(ed.kind.offTitle) ends it.").font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
        }
    }

    private func save() {
        guard let v = values(Date()) else { return }
        actions.save(ed.id, v.start, v.end)
        editing = nil
    }

    /// Delete asks a second tap, then is one Undo step (as a log row does).
    private func deleteTapped() {
        Haptics.light()
        guard ed.deleteArmed else { withAnimation(.snappy) { editing?.deleteArmed = true }; return }
        actions.delete(ed.id)
        editing = nil
    }
}
