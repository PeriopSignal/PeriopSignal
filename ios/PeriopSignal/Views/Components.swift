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
            .font(.system(size: 10, weight: .bold, design: .rounded))
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
            .font(.system(size: 11, weight: .semibold))
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
            .font(.system(size: post.jshort.count > 4 ? 9 : 11, weight: .bold, design: .monospaced))
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
                        .font(.system(size: 6))
                        .foregroundStyle(PS.accent)
                        .padding(.top, 1)
                    Text(item)
                        .font(.system(size: 14.5))
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
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
        .font(.system(size: 12.5))
        .foregroundStyle(PS.fg2)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
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
