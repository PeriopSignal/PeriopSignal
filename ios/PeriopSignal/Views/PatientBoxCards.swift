import SwiftUI
import UIKit

// MARK: - 1.12 (Ben's note 17): the boxes that fold once filled in
//
// PatientBoxCard wraps a box where its tab places it (PatientView.swift). Expanded, the box is untouched, with a small
// "Done" under it once it holds a value; collapsed, it is a card with its title, a chevron and its summary (PatientBox.summary:
// the lines the summaries use), tapped anywhere to expand. The rules and the state are in Shared/PatientBoxModel.swift;
// PatientBoxes below holds them for the screen, keeps the box that was touched where it is on screen when the ones above it
// fold, and waits for the keyboard.

/// The screen's boxes: which are folded (PatientBoxCollapse), where each is on screen, and the keyboard. One per My Patient
/// screen: the state is not saved in the record.
@MainActor
@Observable
final class PatientBoxes {
    /// Off in the screenshot runs that predate it (PatientBox.collapsingEnabled), on everywhere else.
    let enabled: Bool
    private(set) var state = PatientBoxCollapse()

    /// Where each box is, in the window's coordinates, written as the tab lays out (not observed: scrolling redraws nothing).
    @ObservationIgnored var frames: [PatientBox: CGRect] = [:]
    /// The part of the window the tab scrolls in: its top (under the navigation bar) and bottom (above the tab bar or keyboard).
    @ObservationIgnored var viewport: () -> (top: CGFloat, bottom: CGFloat) = { (0, 0) }
    /// Scrolls the tab so the id sits at the unit point of the viewport (the tab's ScrollViewProxy).
    @ObservationIgnored var scroll: ((String, UnitPoint) -> Void)?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastTouched: PatientBox?
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []

    nonisolated static var collapsingEnabled: Bool {
        PatientBox.collapsingEnabled(patientSeed: LaunchSeed.string("ps.patient"), collapseFlag: LaunchSeed.bool("ps.patient.collapse"))
    }

    init(enabled: Bool = PatientBoxes.collapsingEnabled) {
        self.enabled = enabled
        let nc = NotificationCenter.default
        tokens.append(nc.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.keyboard(up: true) }
        })
        tokens.append(nc.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.keyboard(up: false) }
        })
    }

    deinit {
        for t in tokens { NotificationCenter.default.removeObserver(t) }
    }

    /// The id the tab scrolls to for a box (a zero-height marker at its top).
    nonisolated static func pinID(_ box: PatientBox) -> String { "ps.box.pin." + box.rawValue }

    // MARK: Reading

    func isCollapsed(_ box: PatientBox, _ r: PatientRecord) -> Bool { enabled && state.isCollapsed(box, r) }

    // MARK: Events

    /// A saved patient opens (the tab appears, another case is chosen, the patient is cleared or one is received): the boxes
    /// that hold values start folded.
    func start(_ r: PatientRecord) {
        guard enabled else { return }
        started = true
        state.start(r)
    }

    /// The first time only: the tab appearing again (back from a page) keeps the boxes as they are.
    func startOnce(_ r: PatientRecord) {
        guard !started else { return }
        start(r)
    }

    /// The user touched a box (a tap in it) or expanded it: the other boxes that hold values fold.
    func touch(_ box: PatientBox, _ r: PatientRecord) {
        guard enabled else { return }
        lastTouched = box
        keepInPlace(box) { state.touched(box, r) }
        resolveKeyboardOwner()
    }

    /// A jump or a deep link brings the user to a box: it opens (the others fold, as for a tap).
    func expand(_ box: PatientBox, _ r: PatientRecord) { touch(box, r) }

    /// The box's own Done.
    func done(_ box: PatientBox, _ r: PatientRecord) {
        guard enabled else { return }
        Keyboard.dismiss()
        keepInPlace(box) { state.done(box, r) }
    }

    private func keyboard(up: Bool) {
        guard enabled else { return }
        if up {
            state.keyboardChanged(up: true)
        } else {
            keepInPlace(lastTouched) { state.keyboardChanged(up: false) }
        }
    }

    /// A box that folded while a keyboard was up waited for it. A moment after a touch the field with the keyboard is known:
    /// the boxes waiting fold unless it is theirs.
    private func resolveKeyboardOwner() {
        guard state.keyboardUp, !state.pending.isEmpty else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, self.state.keyboardUp else { return }
            let owner = self.ownerOfKeyboard()
            self.keepInPlace(self.lastTouched) { self.state.keyboardOwner(owner) }
        }
    }

    /// The box the first responder (the field with the keyboard) is in; nil when it is in none of them.
    private func ownerOfKeyboard() -> PatientBox? {
        guard let view = Self.firstResponder() as? UIView else { return nil }
        let y = view.convert(view.bounds, to: nil).midY
        return frames.first { $0.value.minY <= y && y <= $0.value.maxY }?.key
    }

    // MARK: Keeping the screen still

    /// Runs a change of what is folded and, when it moved the touched box (a box above it folded, or the box itself folded
    /// with its top above the screen), scrolls the tab so that box is where it was: the content under the finger stays put.
    private func keepInPlace(_ anchor: PatientBox?, _ change: () -> Void) {
        let old = state
        change()
        guard state != old, let anchor, let before = frames[anchor]?.minY, let scroll else { return }
        let view = viewport()
        guard view.bottom > view.top else { return }
        let newlyFolded = state.collapsed.subtracting(old.collapsed)
        let above = newlyFolded.contains { ($0 != anchor) && (frames[$0]?.minY ?? .infinity) < before }
        guard above || before < view.top else { return }
        let fraction = min(max((before - view.top) / (view.bottom - view.top), 0), 1)
        // After the change has laid out (a frame or two later).
        let id = Self.pinID(anchor)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            scroll(id, UnitPoint(x: 0, y: fraction))
        }
    }

    /// The window's first responder, found by sending an action down the responder chain.
    private static func firstResponder() -> UIResponder? {
        let finder = FirstResponderFinder()
        UIApplication.shared.sendAction(#selector(UIResponder.psReportFirstResponder(_:)), to: nil, from: finder, for: nil)
        return finder.found
    }
}

private final class FirstResponderFinder: NSObject {
    weak var found: UIResponder?
}

private extension UIResponder {
    @objc func psReportFirstResponder(_ sender: Any?) {
        (sender as? FirstResponderFinder)?.found = self
    }
}

// MARK: - The card

/// A box of the tab, folding once it is filled in. Off (screenshot runs, or no screen state), it is the box and nothing else.
struct PatientBoxCard<Content: View>: View {
    var box: PatientBox
    @ViewBuilder var content: () -> Content
    @Environment(PatientStore.self) private var patient
    @Environment(PatientBoxes.self) private var boxes: PatientBoxes?

    var body: some View {
        if let boxes, boxes.enabled {
            card(boxes)
        } else {
            content()
        }
    }

    @ViewBuilder private func card(_ boxes: PatientBoxes) -> some View {
        let r = patient.record
        let summary = box.summary(r)
        VStack(alignment: .leading, spacing: 0) {
            // Where the tab scrolls to keep this box where it is when the ones above it fold.
            Color.clear.frame(height: 0).id(PatientBoxes.pinID(box))
            if boxes.isCollapsed(box, r) {
                PatientBoxSummaryCard(title: box.title, lines: summary.lines) { boxes.touch(box, patient.record) }
            } else {
                // A tap anywhere in the box, on top of what the tap does there, counts as working in this box.
                content()
                    .simultaneousGesture(TapGesture().onEnded { boxes.touch(box, patient.record) })
                if summary.holdsValue {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Button { boxes.done(box, patient.record) } label: {
                            Text("Done")
                                .font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.action)
                                .padding(.horizontal, 8).padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Done with " + box.title)
                        .accessibilityHint("Folds the box to its summary")
                    }
                    .padding(.top, 2)
                }
            }
        }
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { boxes.frames[box] = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in boxes.frames[box] = f }
            }
        }
    }
}

/// A folded box: its title and a chevron, then what it holds in the summaries' words (two lines at most for an ordinary
/// line; an alert line and a line with an abnormal value in full, in red). A tap anywhere expands it.
struct PatientBoxSummaryCard: View {
    var title: String
    var lines: [PatientSummary.Line]
    var expand: () -> Void

    var body: some View {
        Button(action: expand) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                }
                ForEach(Array(shown.enumerated()), id: \.offset) { _, l in
                    PatientLineText(line: l).lineLimit(PatientBox.lineLimit(l))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(title: title, lines: lines))
        .accessibilityHint("Opens the box to edit it")
    }

    /// The lines as drawn under the title: a line labelled with the title itself ("Allergies" under "Allergies") loses its label.
    private var shown: [PatientSummary.Line] { Self.drawn(title: title, lines: lines) }

    static func drawn(title: String, lines: [PatientSummary.Line]) -> [PatientSummary.Line] {
        lines.map { l in
            guard let label = l.label, label.caseInsensitiveCompare(title) == .orderedSame else { return l }
            return PatientSummary.Line(nil, l.text, alert: l.alert, marks: l.marks)
        }
    }

    /// "Allergies, collapsed. Allergies: Penicillin (rash)."
    static func spokenLabel(title: String, lines: [PatientSummary.Line]) -> String {
        let said = lines.map { ($0.label.map { $0 + ": " } ?? "") + $0.text }
        return ([title + ", collapsed"] + said).joined(separator: ". ")
    }
}
