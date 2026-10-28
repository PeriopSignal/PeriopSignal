import SwiftUI

/// Welcome screen, opened from More (or a periopsignal://welcome link): what the app is, a choice of
/// topics, and the alerts prompt. New installs open straight to the feed.
struct OnboardingView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notifications = NotificationManager.shared
    @State private var step = 0
    @State private var topics: Set<String> = []
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if step == 0 { welcome } else { alerts }
                }
                .padding(.horizontal, 22)
                .padding(.top, 28)
                .padding(.bottom, 16)
            }
            footer
        }
        .background(PS.bg.ignoresSafeArea())
        .interactiveDismissDisabled(false)
        .onAppear { topics = prefs.myTopics }
        .onDisappear { finish() }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                LogoMark(size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Wordmark(size: 26)
                    Text("Curated research for anesthesiologists").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                point("waveform.path.ecg", "The practice-changing papers", "From about 60 journals and the society and FDA pages, every morning. Only what clears a high bar.")
                point("diamond.fill", "The authors’ own key points", "Take-home bullets as the authors state them, an overview, and the limitations they acknowledge.")
                point("brain.head.profile", "One question a day", "A board-style question from a recent post, so what you read sticks.")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick your areas").font(PS.sys(size: 17, weight: .bold)).foregroundStyle(PS.fg)
                Text("Optional. The feed opens on these and alerts cover only these; everything stays one tap away. You can change them any time under More.")
                    .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                TopicChipGrid(selection: $topics).padding(.top, 2)
            }
        }
    }

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "bell.badge")
                .font(PS.sys(size: 34, weight: .semibold))
                .foregroundStyle(PS.accent)
                .frame(width: 64, height: 64)
                .background(PS.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("One alert in the morning").font(PS.sys(size: 24, weight: .bold, design: .serif)).foregroundStyle(PS.fg)
            Text(topics.isEmpty
                 ? "When new papers land, you get a single notification with the lead headline. Nothing else, ever."
                 : "When papers land in \(topicNames), you get a single notification with the lead headline. Nothing else, ever.")
                .font(PS.sys(size: 15)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            Text("You can set the earliest delivery time and quiet weekends under More.")
                .font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
        }
    }

    private var topicNames: String {
        let names = Topics.all.filter { topics.contains($0.id) }.map(\.name)
        if names.count <= 2 { return names.joined(separator: " and ") }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    private func point(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(PS.sys(size: 15, weight: .semibold))
                .foregroundStyle(PS.accent)
                .frame(width: 32, height: 32)
                .background(PS.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                Text(body).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            if step == 0 {
                Button {
                    prefs.setTopics(topics)
                    if notifications.enabled { finish(); dismiss() } else { withAnimation { step = 1 } }
                } label: {
                    Text(topics.isEmpty ? "Continue" : "Follow \(topics.count) topic\(topics.count == 1 ? "" : "s")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(prominent: true))
                Button("Not now") { finish(); dismiss() }
                    .font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg3)
            } else {
                Button {
                    busy = true
                    Task {
                        _ = await notifications.requestPermission()
                        busy = false
                        finish(); dismiss()
                    }
                } label: {
                    Text(busy ? "…" : "Turn on alerts").frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(prominent: true))
                .disabled(busy)
                Button("Not now") { finish(); dismiss() }
                    .font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg3)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(PS.bg)
        .overlay(Rectangle().fill(PS.line).frame(height: 1), alignment: .top)
    }

    private func finish() {
        guard !prefs.onboardingDone else { return }
        prefs.onboardingDone = true
        NotificationManager.shared.syncTopics()
    }
}

struct BigButtonStyle: ButtonStyle {
    var prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PS.sys(size: 16, weight: .semibold))
            .padding(.vertical, 14)
            .background(prominent ? PS.accent : PS.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(prominent ? PS.accentFg : PS.fg)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Reminder shown a few days in when the reader has not picked topics.
struct PersonalizeBanner: View {
    @Environment(Preferences.self) private var prefs
    @Environment(Router.self) private var router

    var body: some View {
        if prefs.shouldPromptToPersonalize {
            VStack(spacing: 0) {
                QuietRow(icon: "slider.horizontal.3", tint: PS.accent2, eyebrow: "Make it yours", text: "Pick your areas for a For you feed and alerts that matter.", textSize: 14, lines: 2) {
                    HStack(spacing: 4) {
                        Button {
                            prefs.personalizePromptDismissed = true
                            router.selectedTab = .more
                        } label: { Text("Pick topics") }
                        .buttonStyle(CapsuleButtonStyle(prominent: true, color: PS.accent2, onColor: .white))
                        Button { prefs.personalizePromptDismissed = true } label: {
                            Image(systemName: "xmark").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.fg3).frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss")
                    }
                }
                Hairline()
            }
        }
    }
}
