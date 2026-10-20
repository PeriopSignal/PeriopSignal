import SwiftUI
import UIKit

struct AboutView: View {
    @Environment(PostStore.self) private var store
    @AppStorage("ps.appearance") private var appearance: Appearance = .dark
    @ObservedObject private var notifications = NotificationManager.shared
    @State private var notifyOn = NotificationManager.shared.enabled
    @State private var webLink: WebLink?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        LogoMark(size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Wordmark(size: 24)
                            Text("Curated research for anesthesiologists").font(.system(size: 13)).foregroundStyle(PS.fg2)
                            Text("Creator: Benjamin Mori, MD").font(.system(size: 12.5, weight: .medium)).foregroundStyle(PS.fg2)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(PS.surface)
                }

                Section("Notifications") {
                    Toggle(isOn: $notifyOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("New-paper alerts")
                            Text(notificationStatus).font(.system(size: 12)).foregroundStyle(PS.fg3)
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
                }
                .listRowBackground(PS.surface)

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
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
                    Text("Every morning the feed sweeps about 50 journals plus the ASA, SCA, ASE, STS, ELSO, APSF and FDA pages, keeps only the papers that clear a high bar, and writes a short post for each: the authors’ own key points as the take-home, an overview, and the limitations the authors state. Summaries are reading aids, not clinical advice. Read the source before acting on it.")
                        .font(.system(size: 13.5))
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
            .navigationTitle("About")
            .toolbarBackground(PS.bg.opacity(0.9), for: .navigationBar)
            .task { await notifications.refreshAuthorization() }
        }
        .fullScreenCover(item: $webLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
    }

    private var notificationStatus: String {
        switch notifications.authorization {
        case .denied: return "Turned off in iOS Settings"
        case .authorized, .provisional, .ephemeral: return notifyOn ? "One alert when new papers land" : "Off"
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
