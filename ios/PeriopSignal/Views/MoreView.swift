import SwiftUI
import UIKit

/// Settings and about: the question of the day lives here, then topics, alerts, reading
/// preferences and the feed. Built as cards on the feed's background rather than a system list.
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
    @State private var path = NavigationPath()

    var body: some View {
        @Bindable var p = prefs
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    brand
                    questionCard
                    topicsCard(p: $p)
                    alertsCard(p: $p)
                    readingCard
                    feedCard
                    about
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(FeedBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: Post.self) { post in
                DeepDiveView(post: post, onOpenPaper: { webLink = WebLink(url: $0) })
            }
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

    // MARK: Cards

    private var brand: some View {
        HStack(spacing: 14) {
            LogoMark(size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Wordmark(size: 24)
                Text("Curated research for anesthesiologists").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2)
                Text("Creator: Benjamin Mori, MD").font(PS.sys(size: 12.5, weight: .medium)).foregroundStyle(PS.fg3)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var questionCard: some View {
        @Bindable var p = prefs
        SettingsCard(title: "Question of the day") {
            if let post = quiz.todaysQuestion(from: store.posts), post.quiz != nil {
                HStack(spacing: 6) {
                    Circle().fill(Topics.info(post.primaryTopic).fg).frame(width: 7, height: 7)
                    Text(post.journal).fontWeight(.semibold).foregroundStyle(PS.fg)
                    Text("·").foregroundStyle(PS.fg3)
                    Text(post.kind)
                    Text("·").foregroundStyle(PS.fg3)
                    Text(PSDate.display(post.date, long: true))
                }
                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineLimit(1)
                QuizView(post: post, showPostLink: true, onOpenPost: { path.append($0) })
                    .padding(.top, 2)
            } else {
                Text("Today’s question appears here once the feed has loaded.")
                    .font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
            }
            Hairline().padding(.top, 4)
            HStack(spacing: 18) {
                stat("\(quiz.streak)", "day streak")
                stat("\(quiz.answeredCount)", "answered")
                stat(quiz.answeredCount == 0 ? "—" : "\(Int((Double(quiz.correctCount) / Double(max(1, quiz.answeredCount)) * 100).rounded()))%", "correct")
                Spacer()
            }
            Hairline()
            Toggle(isOn: $p.showDailyQuestion) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show at the top of the feed").font(PS.sys(size: 15))
                    Text("Off: the question lives here only.").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                }
            }
            .tint(PS.accent)
            Text("One question each morning, written from that post’s own text. Answers and the streak sync through iCloud.")
                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
        }
    }

    private func topicsCard(p: Bindable<Preferences>) -> some View {
        SettingsCard(title: "My topics") {
            TopicChipGrid(selection: p.myTopics, counts: store.topicCounts())
            Text(prefs.myTopics.isEmpty
                 ? "Following everything. Pick areas to get a “For you” filter and alerts only for those topics."
                 : "The feed opens on “For you” and alerts cover only these topics. Clear them to follow everything.")
                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
            HStack(spacing: 10) {
                if !prefs.myTopics.isEmpty {
                    Button("Follow everything") { prefs.setTopics([]) }
                        .buttonStyle(GhostButtonStyle())
                }
                Button("Show welcome screen") { router.showWelcome = true }
                    .buttonStyle(GhostButtonStyle())
            }
            .onChange(of: prefs.myTopics) { _, new in
                if !new.isEmpty { prefs.forYou = true }
                notifications.syncTopics()
            }
        }
    }

    private func alertsCard(p: Bindable<Preferences>) -> some View {
        SettingsCard(title: "Morning alerts") {
            Toggle(isOn: $notifyOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New-paper alerts").font(PS.sys(size: 15))
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
                .buttonStyle(GhostButtonStyle())
            }
            Hairline()
            DatePicker(selection: $alertDate, displayedComponents: .hourAndMinute) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not before").font(PS.sys(size: 15))
                    Text("Alerts found earlier wait until this time.").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                }
            }
            .onChange(of: alertDate) { _, d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                prefs.alertHour = c.hour ?? 6; prefs.alertMinute = c.minute ?? 30
            }
            Hairline()
            Toggle(isOn: p.quietWeekends) { Text("Quiet on weekends").font(PS.sys(size: 15)) }
                .tint(PS.accent)
                .onChange(of: prefs.quietWeekends) { _, _ in notifications.syncTopics() }
            Hairline()
            Toggle(isOn: p.weeklyDigest) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sunday digest").font(PS.sys(size: 15))
                    Text("One summary of the week’s posts.").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                }
            }
            .tint(PS.accent)
            .onChange(of: prefs.weeklyDigest) { _, _ in notifications.syncTopics() }
        }
    }

    private var readingCard: some View {
        SettingsCard(title: "Reading") {
            labelled("Theme") {
                Picker("Theme", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            labelled("Text size") {
                Picker("Text size", selection: Binding(get: { TextScale.nearest(prefs.textScale) }, set: { prefs.textScale = $0.rawValue })) {
                    ForEach(TextScale.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            labelled("Listening speed") {
                Picker("Listening speed", selection: Binding(get: { SpeechRate.nearest(prefs.speechRate) }, set: { prefs.speechRate = $0.rawValue; speech.setRate($0.rawValue) })) {
                    ForEach(SpeechRate.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var feedCard: some View {
        SettingsCard(title: "The feed") {
            HStack(spacing: 18) {
                stat("\(store.posts.count)", "posts")
                stat("\(store.landmarkCount)", "landmark")
                if let d = store.generatedDate {
                    stat(d.formatted(.relative(presentation: .named)), "updated")
                }
                Spacer()
            }
            Hairline()
            HStack(spacing: 10) {
                Button { webLink = WebLink(url: FeedLoader.siteURL) } label: { Label("Website", systemImage: "safari") }
                    .buttonStyle(GhostButtonStyle())
                ShareLink(item: FeedLoader.siteURL, message: Text("Periop Signal: the practice-changing papers in anesthesiology and critical care, every morning.")) {
                    Label("Share Periop Signal", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "How it works")
            Text("Every morning the feed sweeps about 60 journals plus the ASA, SCA, ASE, STS, ELSO, APSF and FDA pages, keeps only the papers that clear a high bar, and writes a short post for each: the authors’ own key points as the take-home, an overview, the limitations the authors state, and one question to check what stuck. Summaries are reading aids, not clinical advice. Read the source before acting on it.")
                .font(PS.sys(size: 13.5))
                .foregroundStyle(PS.fg2)
                .lineSpacing(2)
            Text("Version " + Bundle.main.versionString)
                .font(PS.mono(size: 11, weight: .semibold))
                .foregroundStyle(PS.fg3)
                .padding(.top, 6)
        }
        .padding(.horizontal, 2)
        .padding(.top, 6)
    }

    // MARK: Pieces

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(PS.sys(size: 18, weight: .bold, design: .rounded)).foregroundStyle(PS.fg).lineLimit(1)
            Text(label).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
        }
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(PS.sys(size: 15))
            content()
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

/// A settings group: eyebrow title above a surface card with its rows stacked inside.
struct SettingsCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title).padding(.leading, 2)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).fill(PS.surface))
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
