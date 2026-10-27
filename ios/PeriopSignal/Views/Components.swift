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

/// Bulleted take-home list with the site's coral diamond markers.
struct TakeHomeList: View {
    var items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "diamond.fill")
                        .font(PS.sys(size: 6))
                        .foregroundStyle(PS.accent)
                        .padding(.top, 1)
                    Text(item)
                        .font(PS.sys(size: 14.5))
                        .foregroundStyle(PS.fg)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PS.line, lineWidth: 1))
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
    var body: some View {
        HStack(spacing: 5) {
            Text(post.journal).fontWeight(.semibold).foregroundStyle(PS.fg)
            Text("·").foregroundStyle(PS.fg3)
            Text(post.kind)
            Text("·").foregroundStyle(PS.fg3)
            Text((post.dateApprox ? "~" : "") + PSDate.display(post.date, long: long))
            if isNew { Pill(text: "New", style: .new) }
        }
        .font(PS.sys(size: 12.5))
        .foregroundStyle(PS.fg2)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
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
/// version; the full version is a labelled grid for the deep dive.
struct GlanceStrip: View {
    var glance: Glance
    var compact = false

    var body: some View {
        if compact {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(glance.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 4) {
                            Text(shortLabel(row.label)).font(PS.sys(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(PS.fg3)
                            Text(row.value).font(PS.sys(size: 11.5, weight: .medium)).foregroundStyle(PS.fg2).lineLimit(1)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .scrollClipDisabled()
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(glance.rows.enumerated()), id: \.offset) { i, row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.label.uppercased())
                            .font(PS.sys(size: 10, weight: .bold, design: .monospaced))
                            .kerning(0.5)
                            .foregroundStyle(PS.fg3)
                            .frame(width: 92, alignment: .leading)
                        Text(row.value)
                            .font(PS.sys(size: 13.5, weight: row.label == "Result" ? .semibold : .regular))
                            .foregroundStyle(PS.fg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                    if i < glance.rows.count - 1 { Divider().overlay(PS.line) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 2)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PS.line, lineWidth: 1))
        }
    }

    private func shortLabel(_ l: String) -> String {
        switch l {
        case "Design": return "DESIGN"
        case "Population": return "N"
        case "Primary outcome": return "OUTCOME"
        default: return "RESULT"
        }
    }
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
                .buttonStyle(.plain)
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
