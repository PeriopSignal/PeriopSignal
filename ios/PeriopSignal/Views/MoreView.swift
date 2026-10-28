import SwiftUI
import UIKit

/// Settings and about: topics, alerts, reading preferences, the daily question tally and the feed.
struct MoreView: View {
    @Environment(PostStore.self) private var store
    @Environment(Preferences.self) private var prefs
    @Environment(QuizStore.self) private var quiz
    @Environment(SpeechPlayer.self) private var speech
    @Environment(Router.self) private var router
    @AppStorage("ps.appearance") private var appearance: Appearance = .dark
    @ObservedObject private var notifications = NotificationManager.shared
    @State private var notifyOn = NotificationManager.shared.enabled
    @State private var webLink: WebLink?
    @State private var alertDate = Date()

    var body: some View {
        @Bindable var p = prefs
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        LogoMark(size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Wordmark(size: 24)
                            Text("Curated research for anesthesiologists").font(PS.sys(size: 13)).foregroundStyle(PS.fg2)
                            Text("Creator: Benjamin Mori, MD").font(PS.sys(size: 12.5, weight: .medium)).foregroundStyle(PS.fg2)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(PS.surface)
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        TopicChipGrid(selection: $p.myTopics, counts: store.topicCounts())
                        Text(prefs.myTopics.isEmpty
                             ? "Following everything. Pick areas to get a “For you” filter and alerts only for those topics."
                             : "The feed opens on “For you” and alerts cover only these topics. Clear them to follow everything.")
                            .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
                        HStack(spacing: 16) {
                            if !prefs.myTopics.isEmpty {
                                Button("Follow everything") { prefs.setTopics([]) }
                                    .buttonStyle(.borderless)
                                    .font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent2)
                            }
                            Button("Show welcome screen") { router.showWelcome = true }
                                .buttonStyle(.borderless)
                                .font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent2)
                        }
                    }
                    .padding(.vertical, 4)
                    .onChange(of: prefs.myTopics) { _, new in
                        if !new.isEmpty { prefs.forYou = true }
                        notifications.syncTopics()
                    }
                } header: {
                    Text("My topics")
                }
                .listRowBackground(PS.surface)

                Section("Morning alerts") {
                    Toggle(isOn: $notifyOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("New-paper alerts")
                            Text(notificationStatus).font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                        }
                    }
                    .tint(PS.accent)
                    .onChange(of: notifyOn) { _, on in
                        Task {
                            if on {
                                let ok = await notifications.requestPermission()
                                if !ok { notifyOn = false }
                            } else {
                                notifications.enabled = false
                            }
                        }
                    }
                    if notifications.authorization == .denied {
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    DatePicker(selection: $alertDate, displayedComponents: .hourAndMinute) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not before")
                            Text("Alerts found earlier wait until this time.").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                        }
                    }
                    .onChange(of: alertDate) { _, d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        prefs.alertHour = c.hour ?? 6; prefs.alertMinute = c.minute ?? 30
                    }
                    Toggle("Quiet on weekends", isOn: $p.quietWeekends).tint(PS.accent)
                        .onChange(of: prefs.quietWeekends) { _, _ in notifications.syncTopics() }
                    Toggle(isOn: $p.weeklyDigest) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sunday digest")
                            Text("One summary of the week’s posts.").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                        }
                    }
                    .tint(PS.accent)
                    .onChange(of: prefs.weeklyDigest) { _, _ in notifications.syncTopics() }
                }
                .listRowBackground(PS.surface)

                Section("Reading") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Text size")
                        Picker("Text size", selection: Binding(get: { TextScale.nearest(prefs.textScale) }, set: { prefs.textScale = $0.rawValue })) {
                            ForEach(TextScale.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Listening speed")
                        Picker("Listening speed", selection: Binding(get: { SpeechRate.nearest(prefs.speechRate) }, set: { prefs.speechRate = $0.rawValue; speech.setRate($0.rawValue) })) {
                            ForEach(SpeechRate.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .listRowBackground(PS.surface)

                Section("Question of the day") {
                    Toggle(isOn: $p.showDailyQuestion) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Question of the day")
                            Text("The card on the feed and the “Test yourself” section in deep dives.").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                        }
                    }
                    .tint(PS.accent)
                    LabeledContent("Streak", value: "\(quiz.streak) day\(quiz.streak == 1 ? "" : "s")")
                    LabeledContent("Answered", value: "\(quiz.answeredCount)")
                    LabeledContent("Correct", value: quiz.answeredCount == 0 ? "—" : "\(quiz.correctCount) (\(Int((Double(quiz.correctCount) / Double(quiz.answeredCount) * 100).rounded()))%)")
                    Text("One question each morning, written from that post’s own text. Answers sync through iCloud.")
                        .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
                }
                .listRowBackground(PS.surface)

                Section("The feed") {
                    LabeledContent("Posts", value: "\(store.posts.count)")
                    LabeledContent("Landmark", value: "\(store.landmarkCount)")
                    if let d = store.generatedDate {
                        LabeledContent("Feed updated", value: d.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button {
                        webLink = WebLink(url: FeedLoader.siteURL)
                    } label: {
                        Label("Open the website", systemImage: "safari")
                    }
                    ShareLink(item: FeedLoader.siteURL, message: Text("Periop Signal: the practice-changing papers in anesthesiology and critical care, every morning.")) {
                        Label("Share Periop Signal", systemImage: "square.and.arrow.up")
                    }
                }
                .listRowBackground(PS.surface)

                Section("How it works") {
                    Text("Every morning the feed sweeps about 60 journals plus the ASA, SCA, ASE, STS, ELSO, APSF and FDA pages, keeps only the papers that clear a high bar, and writes a short post for each: the authors’ own key points as the take-home, an overview, the limitations the authors state, and one question to check what stuck. Summaries are reading aids, not clinical advice. Read the source before acting on it.")
                        .font(PS.sys(size: 13.5))
                        .foregroundStyle(PS.fg2)
                }
                .listRowBackground(PS.surface)

                Section {
                    LabeledContent("Version", value: Bundle.main.versionString)
                }
                .listRowBackground(PS.surface)
            }
            .scrollContentBackground(.hidden)
            .background(FeedBackground())
            .navigationTitle("More")
            .toolbarBackground(PS.bg.opacity(0.9), for: .navigationBar)
            .task {
                await notifications.refreshAuthorization()
                var c = DateComponents(); c.hour = prefs.alertHour; c.minute = prefs.alertMinute
                alertDate = Calendar.current.date(from: c) ?? Date()
            }
            .listenBar()
        }
        .fullScreenCover(item: $webLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
    }

    private var notificationStatus: String {
        switch notifications.authorization {
        case .denied: return "Turned off in iOS Settings"
        case .authorized, .provisional, .ephemeral:
            return notifyOn ? (prefs.myTopics.isEmpty ? "One alert when new papers land" : "One alert when papers land in your topics") : "Off"
        default: return "Get an alert when new papers land"
        }
    }
}

extension Bundle {
    var versionString: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
