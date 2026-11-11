import SwiftUI

// MARK: - 1.12 (Ben's note 10): the case and the tabs are always at hand
//
// At the top of My Patient nothing changes: the row of cases (two or more, or a room) and the Preoperative /
// Intraoperative / Summary & Handoff control. Once those have scrolled under the navigation bar, ONE slim row is pinned in
// their place: on the left the cases as compact chips (the open one filled; "Case 1" as plain words when there is one case
// and no room), on the right three small tab buttons (icon and "Preop", "Intraop", "Summary"; the tab showing in the
// brand-red selection). Under it sits the 1.11 section-chip bar, unchanged. A case chip opens that case as the full row's
// does; a tab button switches tab as the full control does (a switch goes to the top of the new tab).
// On every page opened from My Patient the open case's label is a small read-only caption under the page title.

extension PatientTab {
    /// The words on the pinned row's buttons; VoiceOver reads `title`, the full name.
    var pinnedTitle: String {
        switch self {
        case .preop: return "Preop"
        case .intraop: return "Intraop"
        case .summary: return "Summary"
        }
    }
}

/// When the pinned row and the pinned section chips show, from where things are on screen. `tabsBottom` is the bottom of the
/// case row and the tab control, `barY` the top of the section-chip bar, `pinY` the top of what the pinned bars cover.
enum PatientPinned {
    static func flags(tabsBottom: CGFloat, barY: CGFloat, pinY: CGFloat, rowHeight: CGFloat) -> (tabs: Bool, chips: Bool) {
        // The row takes over once the case row and the tab control have gone under the bar.
        let tabs = tabsBottom < pinY
        // The chips take over when their own bar reaches what is left under the row (the whole of the bar's room when the
        // row is not there), so they do not jump when they pin.
        return (tabs, barY < pinY + (tabs ? rowHeight : 0))
    }

    /// About 44 pt; a larger in-app text size makes it a little taller (its labels grow with the text).
    static var rowHeight: CGFloat { (44 * (1 + (PS.textScale - 1) * 0.5)).rounded() }

    /// The cases the pinned row draws as chips: all of them when the full row shows (two cases or more, or a room);
    /// otherwise none, and the single label is shown (`singleLabel`).
    struct CaseChip: Equatable, Identifiable {
        var id: UUID
        var label: String
        /// Spoken: the room and the first procedure ("OR 66, AVR with supracoronary graft").
        var spoken: String
        var open: Bool
    }

    static func caseChips(cases: [PatientCase], currentID: UUID, showsRow: Bool) -> [CaseChip] {
        guard showsRow else { return [] }
        return cases.map { c in
            CaseChip(id: c.id, label: c.label, spoken: c.label + (c.detail.isEmpty ? "" : ", " + c.detail), open: c.id == currentID)
        }
    }

    /// With one case and no room: its label, "Case 1", as plain words.
    static func singleLabel(current: PatientCase, showsRow: Bool) -> String? { showsRow ? nil : current.label }
}

/// The pinned row itself: cases at the left, the three tabs at the right.
struct PatientPinnedRow: View {
    @Environment(PatientStore.self) private var patient
    var tab: PatientTab
    var select: (PatientTab) -> Void

    private let tabIcon: CGFloat = 12.5

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Icon and word on each tab button, while the cases keep at least 84 pt (the chips scroll sideways): a 375-pt phone
            // has 335 pt between the gutters, and the three buttons take about 225 of them.
            HStack(spacing: 8) { cases; tabs(words: true).fixedSize() }
            // A large text size: the icons alone (VoiceOver still says the full names).
            HStack(spacing: 8) { cases; tabs(words: false).fixedSize() }
        }
        .frame(height: PatientPinned.rowHeight)
    }

    // MARK: Cases

    @ViewBuilder private var cases: some View {
        let chips = PatientPinned.caseChips(cases: patient.cases, currentID: patient.currentCase.id, showsRow: patient.showsCaseRow)
        Group {
            if let single = PatientPinned.singleLabel(current: patient.currentCase, showsRow: patient.showsCaseRow) {
                Text(single)
                    .font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Open case: " + single)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(chips) { c in chip(c).id(c.id) }
                        }
                        .padding(.vertical, 2).padding(.horizontal, 1)
                    }
                    .onAppear {
                        let id = patient.currentCase.id
                        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: patient.currentCase.id) { _, id in
                        withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
                    }
                    // A chip that runs on under the tab buttons fades out, so it reads as more to scroll to, not as cut off.
                    .mask(HStack(spacing: 0) {
                        Rectangle().fill(Color.black)
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 14)
                    })
                }
            }
        }
        // The ideal width is what the row must keep for the cases; they take whatever more there is.
        .frame(minWidth: 0, idealWidth: 84, maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ c: PatientPinned.CaseChip) -> some View {
        Button {
            guard let target = patient.cases.first(where: { $0.id == c.id }) else { return }
            PatientRoomsBar.open(target, in: patient)
        } label: {
            Text(c.label)
                .font(PS.sys(size: 13.5, weight: .semibold))
                .foregroundStyle(c.open ? PS.fg : PS.fg2)
                .lineLimit(1)
                .padding(.horizontal, 11).frame(height: 32)
                .background(c.open ? PS.accent2.opacity(0.16) : PS.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(c.open ? PS.accent2 : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.spoken)
        .accessibilityAddTraits(c.open ? .isSelected : [])
        .accessibilityHint(c.open ? "The open case" : "Opens this case")
    }

    // MARK: Tabs

    private func tabs(words: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(PatientTab.allCases) { t in
                let on = t == tab
                Button {
                    Haptics.light()
                    select(t)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: t.icon).font(PS.sys(size: tabIcon, weight: .semibold))
                        if words { Text(t.pinnedTitle).font(PS.sys(size: 12, weight: .semibold)).lineLimit(1) }
                    }
                    .foregroundStyle(on ? PS.accentFg : PS.fg2)
                    .padding(.horizontal, words ? 6 : 11)
                    .frame(minHeight: 32)
                    .background(on ? PS.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityHint("Goes to the top of " + t.title)
            }
        }
    }
}

// MARK: - The case under the page title

/// The open case's label as a small caption under a page's title (1.12, note 10): read-only, "OR 66", or "Case 1" with one
/// case and no room. The page's own title stays its navigation title (the back button and VoiceOver); this draws it with
/// the caption in the bar's middle.
struct PatientPageTitle: ViewModifier {
    @Environment(PatientStore.self) private var patient
    var title: String

    /// Fixed sizes, as the system's own bar title is: a bar does not grow with the text size, so nothing here can clip.
    static let titleSize: CGFloat = 16
    static let captionSize: CGFloat = 11

    /// The caption: the open case's room, or "Case 1" while it has none.
    static func caption(_ c: PatientCase) -> String { c.label }

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: Self.titleSize, weight: .semibold)).foregroundStyle(PS.fg)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(Self.caption(patient.currentCase))
                        .font(.system(size: Self.captionSize, weight: .medium)).foregroundStyle(PS.fg3)
                        .lineLimit(1)
                }
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title + ", " + Self.caption(patient.currentCase))
                .accessibilityAddTraits(.isHeader)
            }
        }
    }
}

extension View {
    /// The open case's label under this page's title.
    func patientCaseCaption(_ title: String) -> some View { modifier(PatientPageTitle(title: title)) }
}

/// Case Timers pushed from My Patient (a Reference route in the tab's stack) carries the case caption; the other tools do not
/// belong to a case.
struct PatientRouteCaption: ViewModifier {
    var route: RefRoute

    @ViewBuilder func body(content: Content) -> some View {
        if route == .caseTimers { content.patientCaseCaption("Case Timers") } else { content }
    }
}
