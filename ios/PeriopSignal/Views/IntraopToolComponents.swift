import SwiftUI

// MARK: - Pieces shared by the 1.9 tools (case timers, MTP, mechanical support, TEE companion)

/// The primary sources behind a tool, as small links at the foot of its "Explanation & Evidence ⓘ": discreet, one tap
/// to the paper or label, never in the way of the numbers.
struct EvidenceLinks: View {
    var sources: [EvidenceSource]
    var onOpen: (URL) -> Void

    var body: some View {
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Sources", size: 10)
                FlowLayout(spacing: 6) {
                    ForEach(sources) { s in
                        if let url = URL(string: s.url) {
                            Button { onOpen(url) } label: {
                                HStack(spacing: 3) {
                                    Text(CaseTimerEngine.shortLabel(s.label))
                                    Image(systemName: "arrow.up.right").font(PS.sys(size: 8.5, weight: .bold))
                                }
                                .font(PS.sys(size: 11.5, weight: .medium))
                                .foregroundStyle(PS.fg2)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(PS.surface2, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(s.label)
                            .accessibilityHint("Opens the source")
                        }
                    }
                }
            }
        }
    }
}

/// A tiny tag beside a number saying how firm it is — G (checked against the guideline), G? (cited, wording not yet
/// opened), P (practice only), Mfr, Per your team, Verify — and, with a link, where it comes from.
struct EvidenceTag: View {
    var text: String
    var url: URL?
    var onOpen: ((URL) -> Void)?

    private var tint: Color {
        let t = text.lowercased()
        if t.hasPrefix("g?") || t.contains("verify") { return PS.accent2 }
        if t.hasPrefix("g") || t.hasPrefix("rct") { return PS.green }
        return PS.fg3
    }

    var body: some View {
        let label = HStack(spacing: 2) {
            Text(text)
            if url != nil { Image(systemName: "arrow.up.right").font(PS.sys(size: 7.5, weight: .bold)) }
        }
        .font(PS.mono(size: 9.5, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 1))
        .fixedSize()
        if let url, let onOpen {
            Button { onOpen(url) } label: { label }.buttonStyle(.plain).accessibilityHint("Opens the source")
        } else {
            label
        }
    }
}

/// "Draft · awaiting clinical review" while a section's reviewed date is missing (debug builds only: release builds
/// hide draft tools entirely).
struct DraftBanner: View {
    var section: String

    var body: some View {
        if DraftGate.isDraft(section) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.and.list.clipboard").font(PS.sys(size: 12, weight: .semibold))
                Text("Draft · awaiting clinical review. Not shown in release builds.")
                    .font(PS.sys(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(PS.accent2)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.accent2.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// The checks on a dose before it is logged: a note, a soft flag, one to confirm, or one that stops it.
struct DoseIssueList: View {
    var issues: [DoseIssue]

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(issues.sorted { $0.level > $1.level }) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: icon(i.level)).font(PS.sys(size: 12, weight: .semibold))
                        Text(i.text).font(PS.sys(size: 13, weight: i.level >= .confirm ? .semibold : .regular))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(color(i.level))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func icon(_ l: DoseIssue.Level) -> String {
        switch l {
        case .block: return "nosign"
        case .confirm: return "exclamationmark.triangle.fill"
        case .soft: return "exclamationmark.circle"
        case .note: return "clock"
        }
    }

    private func color(_ l: DoseIssue.Level) -> Color {
        switch l {
        case .block, .confirm: return PS.red
        case .soft: return PS.accent
        case .note: return PS.fg2
        }
    }
}

/// The log button of a dose with checks: disabled when something blocks it, and a second tap ("Confirm") when
/// something needs confirming. `armed` resets whenever the dose changes.
struct CheckedLogButton: View {
    var title: String
    var issues: [DoseIssue]
    @Binding var armed: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            if issues.needsConfirm && !armed { withAnimation(.snappy) { armed = true }; return }
            armed = false
            action()
        } label: {
            Text(issues.needsConfirm && armed ? "Confirm: " + title.lowercased() : title)
        }
        .buttonStyle(CapsuleButtonStyle(prominent: true, color: issues.needsConfirm && armed ? PS.red : PS.accent))
        .disabled(issues.blocks)
        .opacity(issues.blocks ? 0.45 : 1)
    }
}

/// A one-line numeric field with its unit ("24000 U").
struct UnitField: View {
    var prompt: String
    var unit: String
    @Binding var value: Double?
    var width: CGFloat = 96

    var body: some View {
        HStack(spacing: 6) {
            TextField(prompt, value: $value, format: .number)
                .keyboardType(.decimalPad)
                .font(PS.sys(size: 16, weight: .semibold))
                .multilineTextAlignment(.trailing)
                .frame(width: width)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(unit).font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg2)
        }
    }
}

/// A row of chips for one choice ("What is the heparin for?").
struct ChoiceChips<ID: Hashable>: View {
    var options: [(id: ID, label: String)]
    var selected: ID?
    var onPick: (ID) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let on = o.id == selected
                Button {
                    Haptics.light()
                    onPick(o.id)
                } label: {
                    Text(o.label)
                        .font(PS.sys(size: 13.5, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(on ? PS.accent.opacity(0.15) : PS.surface, in: Capsule())
                        .overlay(Capsule().stroke(on ? PS.accent.opacity(0.7) : PS.line2, lineWidth: 1))
                        .foregroundStyle(on ? PS.accent : PS.fg)
                }
                .buttonStyle(.borderless)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A card in the look of the Reference tools.
struct ToolCard<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .overlay(alignment: .top) {
                if let tint {
                    UnevenRoundedRectangle(topLeadingRadius: PS.cardRadius, topTrailingRadius: PS.cardRadius)
                        .fill(tint.opacity(0.9)).frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                }
            }
    }
}

/// A rows-of-three reference table (item · number · flag) for a sheet behind an "Open table" button.
struct FlagTable: View {
    var rows: [[String]]
    var onOpen: ((URL) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(r.first ?? "").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg)
                        Spacer(minLength: 6)
                        if r.count > 2, !r[2].isEmpty { EvidenceTag(text: r[2]) }
                    }
                    if r.count > 1 {
                        Text(r[1]).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                if i < rows.count - 1 { Hairline().padding(.leading, 16) }
            }
        }
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }
}

// MARK: - First-time tips with an arrow

/// A one-time tip that points at a control with a popover arrow, instead of a permanent explainer box. Shown once on
/// this phone (`key`), never on its own in a screenshot run (CI asks for it with -ps.tips 1).
struct OnceTip: ViewModifier {
    var key: String
    var text: String
    var arrowEdge: Edge = .top
    @State private var show = false

    private var shouldShow: Bool {
        switch PatientTips.launch {
        case .normal: return !UserDefaults.standard.bool(forKey: key)
        case .screenshot: return false
        case .forced: return true
        }
    }

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $show, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text)
                        .font(PS.sys(size: 14))
                        .foregroundStyle(PS.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Got it") { show = false }
                        .buttonStyle(CapsuleButtonStyle(prominent: true))
                }
                .padding(16)
                .frame(width: 270, alignment: .leading)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(PS.surface)
            }
            .task {
                guard shouldShow else { return }
                try? await Task.sleep(nanoseconds: 700_000_000)
                show = true
            }
            .onChange(of: show) { _, now in
                if !now { UserDefaults.standard.set(true, forKey: key) }
            }
    }
}

extension View {
    /// A tip shown once, pointing at this view.
    func onceTip(_ key: String, _ text: String, arrowEdge: Edge = .top) -> some View {
        modifier(OnceTip(key: key, text: text, arrowEdge: arrowEdge))
    }
}

// MARK: - Clock text

enum ClockText {
    static let hm: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "HH:mm"; return f
    }()

    static func time(_ d: Date) -> String { hm.string(from: d) }

    /// "in 12 min", "now", "8 min ago", "1 h 05 min".
    static func relative(_ d: Date?, now: Date) -> String {
        guard let d else { return "now" }
        let s = d.timeIntervalSince(now)
        let m = Int((abs(s) / 60).rounded(.down))
        let span = m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60)) min" : "\(m) min"
        if abs(s) < 60 { return "now" }
        return s > 0 ? "in " + span : span + " ago"
    }
}
