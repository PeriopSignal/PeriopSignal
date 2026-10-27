import SwiftUI

/// Mini player pinned above the tab bar while posts are being read aloud.
struct ListenBar: View {
    @Environment(SpeechPlayer.self) private var speech
    @Environment(Router.self) private var router
    @Environment(Preferences.self) private var prefs
    @State private var showRate = false

    var body: some View {
        if speech.isActive, let post = speech.current {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(PS.line2)
                        Rectangle().fill(PS.accent).frame(width: geo.size.width * speech.progress)
                    }
                }
                .frame(height: 2)
                .animation(.linear(duration: 0.3), value: speech.progress)
                HStack(spacing: 10) {
                    Button { router.open(postID: post.id) } label: {
                        HStack(spacing: 10) {
                            JournalAvatar(post: post, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.headline)
                                    .font(PS.sys(size: 13, weight: .semibold))
                                    .foregroundStyle(PS.fg)
                                    .lineLimit(1)
                                Text(status)
                                    .font(PS.sys(size: 11)).foregroundStyle(PS.fg3).lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Button { showRate = true } label: {
                        Text(rateLabel).font(PS.sys(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(PS.fg2)
                            .frame(width: 34, height: 30)
                            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Speech rate")
                    .confirmationDialog("Speech rate", isPresented: $showRate, titleVisibility: .visible) {
                        ForEach(SpeechRate.allCases) { r in
                            Button(r.label) { prefs.speechRate = r.rawValue; speech.setRate(r.rawValue) }
                        }
                    }
                    Button { speech.previous() } label: { Image(systemName: "backward.end.fill") }
                        .buttonStyle(BarButtonStyle())
                        .accessibilityLabel("Previous")
                    Button { speech.toggle() } label: {
                        Image(systemName: speech.finished ? "arrow.counterclockwise" : (speech.isPlaying ? "pause.fill" : "play.fill"))
                    }
                    .buttonStyle(BarButtonStyle(prominent: true))
                    .accessibilityLabel(speech.isPlaying ? "Pause" : "Play")
                    Button { speech.next() } label: { Image(systemName: "forward.end.fill") }
                        .buttonStyle(BarButtonStyle())
                        .disabled(!speech.hasNext)
                        .accessibilityLabel("Next")
                    Button { speech.stop() } label: { Image(systemName: "xmark") }
                        .buttonStyle(BarButtonStyle())
                        .accessibilityLabel("Stop listening")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)
            .background(PS.surface.opacity(0.85))
            .overlay(Rectangle().fill(PS.line).frame(height: 1), alignment: .top)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var status: String {
        if speech.finished { return "Finished · tap to replay" }
        let pos = speech.positionText
        return (speech.isPlaying ? "Playing" : "Paused") + (pos.isEmpty ? "" : " · " + pos)
    }

    private var rateLabel: String { SpeechRate.nearest(prefs.speechRate).label }
}

struct BarButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: prominent ? 15 : 13, weight: .bold))
            .frame(width: prominent ? 38 : 32, height: prominent ? 38 : 32)
            .background(prominent ? PS.accent : PS.surface2, in: Circle())
            .foregroundStyle(prominent ? PS.accentFg : PS.fg)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

enum SpeechRate: Double, CaseIterable, Identifiable {
    case slow = 0.42, normal = 0.5, brisk = 0.55, fast = 0.6
    var id: Double { rawValue }
    var label: String {
        switch self {
        case .slow: return "0.8×"
        case .normal: return "1×"
        case .brisk: return "1.2×"
        case .fast: return "1.5×"
        }
    }
    static func nearest(_ v: Double) -> SpeechRate {
        allCases.min { abs($0.rawValue - v) < abs($1.rawValue - v) } ?? .normal
    }
}

/// Adds the mini player above the tab bar of a tab's content.
struct ListenBarInset: ViewModifier {
    @Environment(SpeechPlayer.self) private var speech
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            ListenBar().animation(.easeOut(duration: 0.25), value: speech.isActive)
        }
    }
}

extension View {
    func listenBar() -> some View { modifier(ListenBarInset()) }
}
