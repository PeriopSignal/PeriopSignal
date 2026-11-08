import SwiftUI
import SafariServices
import UIKit

// MARK: - Small pieces shared by the feed card and the deep dive

/// Three bars showing the impact score (1-3), as on the site.
struct SignalBars: View {
    var impact: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < impact ? (impact >= 3 ? PS.accent : PS.fg2) : PS.line2)
                    .frame(width: 3, height: CGFloat(5 + i * 3))
            }
        }
        .accessibilityLabel(impact >= 3 ? "Landmark" : impact == 2 ? "Important" : "Notable")
    }
}

struct Pill: View {
    enum Style { case landmark, new, neutral }
    var text: String
    var style: Style = .neutral
    var body: some View {
        Text(text)
            .font(PS.sys(size: 10, weight: .bold, design: .rounded))
            .textCase(.uppercase)
            .kerning(0.4)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }
    private var background: Color {
        switch style {
        case .landmark: return PS.accent.opacity(0.16)
        case .new: return PS.green.opacity(0.16)
        case .neutral: return PS.surface3
        }
    }
    private var foreground: Color {
        switch style {
        case .landmark: return PS.accent
        case .new: return PS.green
        case .neutral: return PS.fg2
        }
    }
}

struct TopicTag: View {
    var topicID: String
    var body: some View {
        let t = Topics.info(topicID)
        Text(t.name)
            .font(PS.sys(size: 11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(t.bg, in: Capsule())
            .foregroundStyle(t.fg)
            .lineLimit(1)
    }
}

/// Journal badge coloured by the post's first topic.
struct JournalAvatar: View {
    var post: Post
    var size: CGFloat = 40
    var body: some View {
        let t = Topics.info(post.primaryTopic)
        Text(post.jshort)
            .font(PS.sys(size: post.jshort.count > 4 ? 9 : 11, weight: .bold, design: .monospaced))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(4)
            .frame(width: size, height: size)
            .background(t.bg, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .foregroundStyle(t.fg)
            .accessibilityHidden(true)
    }
}

/// Take-home bullets with the coral diamond markers, grouped by a thin left rule (no box).
struct TakeHomeList: View {
    var items: [String]
    var size: CGFloat = 14.5
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "diamond.fill")
                        .font(PS.sys(size: 6))
                        .foregroundStyle(PS.accent)
                        .padding(.top, 1)
                    Text(item)
                        .font(PS.sys(size: size))
                        .foregroundStyle(PS.fg)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(PS.line2).frame(width: 2) }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text)
            .font(PS.sys(size: 11, weight: .semibold, design: .monospaced))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(PS.fg3)
    }
}

struct MetaLine: View {
    var post: Post
    var long = false
    var isNew = false
    var showDot = true
    /// Cards drop the year (the month label above them carries it).
    var short = false
    var body: some View {
        HStack(spacing: 6) {
            if showDot {
                Circle().fill(Topics.info(post.primaryTopic).fg).frame(width: 8, height: 8)
            }
            Text(post.journal).fontWeight(.semibold).foregroundStyle(PS.fg)
            Text("·").foregroundStyle(PS.fg3)
            Text(post.kind)
            Text("·").foregroundStyle(PS.fg3)
            Text((post.dateApprox ? "~" : "") + (short ? PSDate.short.string(from: post.dateValue) : PSDate.display(post.date, long: long)))
            if isNew { Pill(text: "New", style: .new) }
        }
        .font(PS.sys(size: 12.5))
        .foregroundStyle(PS.fg2)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}

/// Small monospaced caps label used for eyebrows, section headings and dates.
struct Eyebrow: View {
    var text: String
    var color: Color = PS.fg3
    var size: CGFloat = 11
    var body: some View {
        Text(text)
            .font(PS.mono(size: size))
            .textCase(.uppercase)
            .kerning(size * 0.12)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(PS.line).frame(height: 1) }
}

// MARK: - Explanation & Evidence

/// Explanations, sources and caveats sit behind one small "Explanation & Evidence ⓘ" line that opens in place, so a
/// screen shows its numbers and choices first. CI screenshots: -ps.evidence.open 1 opens them all.
///
/// Usage rule (1.8.1): at most one free-standing "Explanation & Evidence ⓘ" per screen, at the bottom, holding the
/// screen's sources and how it works. An explanation that belongs to one card or section goes behind the ⓘ on that
/// card's header instead (SectionHeader, or InfoTitle for a row); per-row repeats are merged into the one footer.
/// Safety cautions never go behind either: they stay in view next to the control they qualify.
struct EvidenceDisclosure<Content: View>: View {
    var title = "Explanation & Evidence"
    @ViewBuilder var content: () -> Content
    @State private var open = LaunchSeed.bool("ps.evidence.open")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Haptics.light()
                withAnimation(.snappy) { open.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text(title)
                    Image(systemName: open ? "info.circle.fill" : "info.circle")
                }
                .font(PS.sys(size: 12, weight: .semibold))
                .foregroundStyle(open ? PS.fg2 : PS.fg3)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "Shown" : "Hidden")
            .accessibilityHint(open ? "Hides the explanation" : "Shows the explanation and sources")
            if open {
                VStack(alignment: .leading, spacing: 8) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One paragraph of explanation behind "Explanation & Evidence ⓘ".
struct EvidenceNote: View {
    var text: String
    var title = "Explanation & Evidence"
    init(_ text: String, title: String = "Explanation & Evidence") { self.text = text; self.title = title }
    var body: some View {
        EvidenceDisclosure(title: title) {
            Text(text).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Captions behind ⓘ

/// A question or item title whose long grey caption sits behind a small ⓘ at the end of the title, in the look of
/// "Explanation & Evidence ⓘ": hidden until tapped, then shown under the title; tap again to hide. The parent owns
/// `open`, so each row keeps its state for the visit. VoiceOver reads the ⓘ as "Details" and the caption once shown.
/// With `collapsible` false the caption simply shows, as before (short captions stay as they are).
struct InfoTitle<Title: View>: View {
    var caption: String?
    var collapsible = true
    @Binding var open: Bool
    var captionFont: Font = PS.sys(size: 11.5)
    var spacing: CGFloat = 2
    @ViewBuilder var title: () -> Title

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                title()
                if caption != nil && collapsible { InfoButton(open: $open) }
            }
            if let c = caption, !collapsible || open {
                InfoCaptionText(text: c, font: captionFont)
            }
        }
    }
}

/// The small ⓘ that shows or hides a caption.
struct InfoButton: View {
    @Binding var open: Bool
    /// What VoiceOver calls the button ("Details", "About Mallampati").
    var label: String = "Details"
    /// The symbol's point size: 12 beside a row title or eyebrow, larger beside a page title.
    var size: CGFloat = 12

    var body: some View {
        Button {
            Haptics.light()
            withAnimation(.snappy) { open.toggle() }
        } label: {
            Image(systemName: open ? "info.circle.fill" : "info.circle")
                .font(PS.sys(size: size, weight: .semibold))
                .foregroundStyle(open ? PS.fg2 : PS.fg3)
                // A finger-sized target without making the row taller.
                .padding(10).contentShape(Rectangle()).padding(-10)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(label)
        .accessibilityValue(open ? "Shown" : "Hidden")
        .accessibilityHint(open ? "Hides the details" : "Shows the details under the title")
    }
}

/// A section's eyebrow with its explanation behind a small ⓘ at the end of the eyebrow; a tap opens the explanation
/// under the header, above the section's card, and a second tap hides it. This replaces a free-standing
/// "Explanation & Evidence ⓘ" row under a card (see EvidenceDisclosure's usage rule). Without an explanation it is
/// the plain eyebrow. CI screenshots: -ps.evidence.open 1 opens them, as it does EvidenceDisclosure.
struct SectionHeader<Info: View>: View {
    var title: String
    var color: Color = PS.fg3
    var size: CGFloat = 11
    private let info: (() -> Info)?
    @State private var open = LaunchSeed.bool("ps.evidence.open")

    init(title: String, color: Color = PS.fg3, size: CGFloat = 11, @ViewBuilder info: @escaping () -> Info) {
        self.title = title
        self.color = color
        self.size = size
        self.info = info
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Eyebrow(text: title, color: color, size: size)
                    .accessibilityAddTraits(.isHeader)
                if info != nil { InfoButton(open: $open, label: "About " + title) }
            }
            if open, let info {
                VStack(alignment: .leading, spacing: 8) { info() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SectionHeader where Info == InfoCaptionText {
    /// The eyebrow with one paragraph behind its ⓘ; no ⓘ when `info` is nil or empty.
    init(title: String, info: String?, color: Color = PS.fg3, size: CGFloat = 11) {
        self.title = title
        self.color = color
        self.size = size
        if let text = info, !text.isEmpty {
            self.info = { InfoCaptionText(text: text, font: PS.sys(size: 12.5)) }
        } else {
            self.info = nil
        }
    }
}

/// The caption text itself, in the grey of the rows it belongs to.
struct InfoCaptionText: View {
    var text: String
    var font: Font = PS.sys(size: 11.5)

    var body: some View {
        Text(text).font(font).foregroundStyle(PS.fg3).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
    }
}

enum InfoCaption {
    /// Whether a caption runs past two lines on a phone row (about 45 characters a line at 12 pt beside a switch), so
    /// it goes behind ⓘ; shorter captions stay in view.
    static func runsLong(_ text: String?) -> Bool { (text?.count ?? 0) > 90 }
}

/// Takes the width it is offered and reports no ideal width of its own, so a ViewThatFits choosing between layouts
/// decides on the other children (a caption that wraps should not push a row into its stacked form).
struct OfferedWidth: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let s = subviews.first else { return .zero }
        guard let w = proposal.width, w.isFinite else {
            let ideal = s.sizeThatFits(.unspecified)
            return CGSize(width: proposal.width == nil ? 0 : ideal.width, height: ideal.height)
        }
        return CGSize(width: w, height: s.sizeThatFits(ProposedViewSize(width: w, height: nil)).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

extension View {
    /// See OfferedWidth: this view takes the offered width and adds nothing to a ViewThatFits decision.
    func offeredWidth() -> some View { OfferedWidth().callAsFunction { self } }

    /// An empty-input headline ("Enter Measurements") stays on one line, shrinking a little if it must; result
    /// headlines wrap as usual.
    func promptHeadline(_ isPrompt: Bool) -> some View {
        lineLimit(isPrompt ? 1 : nil).minimumScaleFactor(isPrompt ? 0.75 : 1)
    }
}

/// One ECG cycle repeated across the width; the brand's hairline. `progress` draws it in.
struct ECGLine: Shape {
    var progress: CGFloat = 1
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cycle: CGFloat = 118
        let base = rect.midY
        var x = rect.minX
        p.move(to: CGPoint(x: x, y: base))
        while x + cycle <= rect.maxX {
            let w = cycle / 30
            func to(_ dx: CGFloat, _ dy: CGFloat) { x += dx; p.addLine(to: CGPoint(x: x, y: base + dy)) }
            func curve(_ dx: CGFloat, _ depth: CGFloat) {
                let c1 = CGPoint(x: x + dx * 0.3, y: base + depth), c2 = CGPoint(x: x + dx * 0.7, y: base + depth)
                x += dx; p.addCurve(to: CGPoint(x: x, y: base), control1: c1, control2: c2)
            }
            to(6 * w, 0)
            curve(3.5 * w, -3)                                   // P
            to(2.5 * w, 0)
            to(1 * w, 1.6); to(1.5 * w, -10); to(1.5 * w, 11.5); to(1 * w, -3.1)   // QRS
            to(2.5 * w, 0)
            curve(5 * w, -4.2)                                   // T
            to(5.5 * w, 0)
        }
        if x < rect.maxX { p.addLine(to: CGPoint(x: rect.maxX, y: base)) }
        return p.trimmedPath(from: 0, to: max(0, min(1, progress)))
    }
}

/// A hairline-separated row: icon tile, eyebrow + text, optional trailing control. Replaces the
/// boxed banners on the feed.
struct QuietRow<Trailing: View>: View {
    var icon: String
    var tint: Color
    var eyebrow: String
    var text: String
    var textSize: CGFloat = 14.5
    var lines: Int = 3
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(PS.sys(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: eyebrow, color: tint, size: 10.5)
                Text(text)
                    .font(PS.sys(size: textSize))
                    .foregroundStyle(PS.fg)
                    .lineSpacing(1.5)
                    .lineLimit(lines)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            trailing().frame(maxHeight: .infinity, alignment: .center)
        }
        .padding(.vertical, 14)
    }
}

/// Text-only actions ("Deep dive →", "Paper ↗") for card footers.
struct TextButtonStyle: ButtonStyle {
    var color: Color = PS.accent
    var size: CGFloat = 13
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PS.sys(size: size, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

/// Outlined capsule button (the quiet sibling of CapsuleButtonStyle's filled form).
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PS.sys(size: 13.5, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .foregroundStyle(PS.fg)
            .overlay(Capsule().stroke(PS.line2, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Small coral dot marking an unread post.
struct UnreadDot: View {
    var body: some View {
        Circle().fill(PS.accent).frame(width: 8, height: 8)
            .accessibilityLabel("Unread")
    }
}

/// The at-a-glance strip: design, population, primary outcome, result. `compact` is the one-line card
/// version; the full version is a hairline table for the deep dive.
struct GlanceStrip: View {
    var glance: Glance
    var compact = false

    var body: some View {
        if compact {
            (Text(compactLine))
                .font(PS.sys(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(PS.fg3)
                .lineLimit(2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("At a glance: " + compactPlain)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(glance.rows.enumerated()), id: \.offset) { i, row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Eyebrow(text: row.label, size: 10)
                            .frame(width: 96, alignment: .leading)
                        Text(row.value)
                            .font(PS.sys(size: 14, weight: row.label == "Result" ? .semibold : .regular))
                            .foregroundStyle(PS.fg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 9)
                    if i < glance.rows.count - 1 { Hairline() }
                }
            }
        }
    }

    private var compactLine: AttributedString {
        var out = AttributedString()
        let parts = glance.rows
        for (i, row) in parts.enumerated() {
            var piece = AttributedString(row.value)
            if row.label == "Design" || row.label == "Result" { piece.foregroundColor = PS.fg2 }
            out += piece
            if i < parts.count - 1 { out += AttributedString("  ·  ") }
        }
        return out
    }
    private var compactPlain: String { glance.rows.map(\.value).joined(separator: ", ") }
}

/// Wrapping grid of topic chips used by onboarding and the More tab.
struct TopicChipGrid: View {
    @Binding var selection: Set<String>
    var counts: [String: Int] = [:]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Topics.all) { t in
                let on = selection.contains(t.id)
                Button {
                    Haptics.light()
                    if on { selection.remove(t.id) } else { selection.insert(t.id) }
                } label: {
                    HStack(spacing: 5) {
                        if on { Image(systemName: "checkmark").font(PS.sys(size: 10, weight: .bold)) }
                        Text(t.name)
                        if let c = counts[t.id], c > 0 {
                            Text("\(c)").font(PS.sys(size: 10.5, weight: .semibold, design: .monospaced)).foregroundStyle(on ? t.fg.opacity(0.85) : PS.fg3)
                        }
                    }
                    .font(PS.sys(size: 13.5, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(on ? t.bg : PS.surface, in: Capsule())
                    .overlay(Capsule().stroke(on ? t.fg.opacity(0.7) : PS.line2, lineWidth: 1))
                    .foregroundStyle(on ? t.fg : PS.fg2)
                }
                .buttonStyle(.borderless)   // not .plain: inside a List row, .plain would make the whole row a button
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Left-to-right wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Card chrome shared by the Today card, the daily question and the banners.
struct CardChrome: ViewModifier {
    var tint: Color? = nil
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(PS.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(LinearGradient(colors: [(tint ?? .clear).opacity(tint == nil ? 0 : 0.10), .clear], startPoint: .topLeading, endPoint: .bottom))
                    )
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(tint?.opacity(0.35) ?? PS.line, lineWidth: 1))
    }
}

extension View {
    func cardChrome(tint: Color? = nil, radius: CGFloat = 16) -> some View { modifier(CardChrome(tint: tint, radius: radius)) }
}

/// Capsule button used across the new cards: filled (prominent) or quiet.
struct CapsuleButtonStyle: ButtonStyle {
    var prominent = true
    var color: Color = PS.accent
    var onColor: Color = PS.accentFg
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PS.sys(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(prominent ? color : PS.surface2, in: Capsule())
            .foregroundStyle(prominent ? onColor : PS.fg)
            .overlay(Capsule().stroke(prominent ? .clear : PS.line2, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - In-app browser and share sheet

struct WebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(PS.accent)
        vc.dismissButtonStyle = .close
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

extension Post {
    /// Link to this post on the website (opens the deep dive there).
    var siteLink: URL { FeedLoader.siteURL.appendingFragment(id) }

    /// Plain-text summary for the share sheet and clipboard, same shape as the site's "Copy summary".
    var shareText: String {
        var s = headline + "\n" + journal + " · " + kind + " · " + PSDate.display(date, long: true)
        if !trialName.isEmpty { s += " · " + trialName }
        s += "\n\n" + summary + "\n\nTake-home:\n" + takeHome.map { "• " + $0 }.joined(separator: "\n")
        s += "\n\nPaper: " + url + "\nPeriop Signal: " + siteLink.absoluteString
        return s
    }
}

private extension URL {
    func appendingFragment(_ fragment: String) -> URL {
        var comps = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        comps.fragment = fragment
        return comps.url ?? self
    }
}

/// A title and its choice buttons on one line when they fit, saving a row; the choices wrap under the title when
/// they don't (long titles, many choices, large text sizes).
///
/// Whether they fit is decided as 1.10 decided it: by the choices' first one-line form without a chosen toggle chip's
/// ✓ slot (a hidden copy of the choices, drawn with `chipLineProbe`, which makes a ChipSet draw only that form). On the
/// title's line the choices then get the room that is left and pick their own form in it, the ✓ forms first (review
/// 1.10: the ✓ slot made the 1.9 and 1.10 one-line rows such as Renal's "Access  ✓ Fistula  Dialysis catheter" stack,
/// because the row was measured at its widest form). One copy of the title and the choices is drawn either way.
struct InlineChoices<Title: View, Choices: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var title: () -> Title
    @ViewBuilder var choices: () -> Choices

    var body: some View {
        InlineChoicesLayout(spacing: spacing) {
            VStack(alignment: .leading, spacing: 0) { title() }
            VStack(alignment: .leading, spacing: 0) { choices() }
            VStack(alignment: .leading, spacing: 0) { choices() }
                .environment(\.chipLineProbe, true)
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct ChipLineProbeKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// InlineChoices' measure of a row: a ChipSet draws only its first one-line form without the ✓ slot.
    var chipLineProbe: Bool {
        get { self[ChipLineProbeKey.self] }
        set { self[ChipLineProbeKey.self] = newValue }
    }
}

/// InlineChoices' layout of its three parts (the title, the choices, the hidden measure of the choices): on one line,
/// the title at the leading edge and the choices at the trailing one, as the HStack with a spacer it replaces (10 pt,
/// the spacer's 8, 10 pt); or the title above the choices.
struct InlineChoicesLayout: Layout {
    var spacing: CGFloat = 8
    /// Between the title and the choices on one line, at the least.
    static let gap: CGFloat = 28

    /// Whether a title and choices of these widths share one line in `width` (nil: no limit).
    static func inline(title: CGFloat, choices: CGFloat, in width: CGFloat?) -> Bool {
        guard let width else { return true }
        return title + gap + choices <= width + 0.001
    }

    private struct Plan {
        var inline: Bool
        var size: CGSize
        var title: CGSize
        var choices: CGSize
        var choicesProposal: ProposedViewSize
    }

    private func plan(_ proposal: ProposedViewSize, _ subviews: Subviews) -> Plan? {
        guard subviews.count == 3 else { return nil }
        let title = subviews[0], choices = subviews[1], measure = subviews[2]
        let width: CGFloat? = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let titleIdeal = title.sizeThatFits(.unspecified)
        if Self.inline(title: titleIdeal.width, choices: measure.sizeThatFits(.unspecified).width, in: width) {
            let ideal = choices.sizeThatFits(.unspecified)
            let room = width.map { min(ideal.width, max(0, $0 - titleIdeal.width - Self.gap)) } ?? ideal.width
            let p = ProposedViewSize(width: room, height: nil)
            let c = choices.sizeThatFits(p)
            let w = width ?? (titleIdeal.width + Self.gap + c.width)
            return Plan(inline: true, size: CGSize(width: w, height: max(titleIdeal.height, c.height)), title: titleIdeal, choices: c, choicesProposal: p)
        }
        let p = ProposedViewSize(width: width, height: nil)
        let t = title.sizeThatFits(p), c = choices.sizeThatFits(p)
        return Plan(inline: false, size: CGSize(width: max(t.width, c.width), height: t.height + spacing + c.height), title: t, choices: c, choicesProposal: p)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        plan(proposal, subviews)?.size ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let plan = plan(ProposedViewSize(width: bounds.width, height: nil), subviews) else { return }
        // The measure is hidden; it is placed only because every subview must be.
        subviews[2].place(at: bounds.origin, proposal: .unspecified)
        if plan.inline {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(plan.title))
            subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: plan.choicesProposal)
        } else {
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + plan.title.height + spacing), proposal: plan.choicesProposal)
        }
    }
}
