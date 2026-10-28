import SwiftUI

struct FeedView: View {
    @Environment(PostStore.self) private var store
    @Environment(QuizStore.self) private var quiz
    @Environment(Preferences.self) private var prefs
    @Environment(Router.self) private var router
    @State private var path = NavigationPath()
    @State private var webLink: WebLink?
    @State private var quizPost: Post?
    @State private var searching = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    FeedHeader(searching: $searching) {
                        withAnimation(.snappy) { searching.toggle() }
                        if searching { searchFocused = true } else { store.query = "" }
                    }
                    if searching {
                        searchField
                    }
                    TodayHero(onOpen: { path.append($0) })
                    Hairline()
                    DailyQuestionCard(onOpenSheet: { quizPost = $0 })
                    if prefs.showDailyQuestion, quiz.todaysQuestion(from: store.posts) != nil { Hairline() }
                    NotifyBanner()
                    PersonalizeBanner()
                    FilterBar()
                        .padding(.top, 12)
                    statusLine
                        .padding(.top, 14)
                    postList
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(FeedBackground())
            .scrollContentBackground(.hidden)
            .refreshable { await store.refresh() }
            .navigationDestination(for: Post.self) { post in
                DeepDiveView(post: post, onOpenPaper: { webLink = WebLink(url: $0) })
            }
            .toolbar(.hidden, for: .navigationBar)
            .listenBar()
        }
        .fullScreenCover(item: $webLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
        .sheet(item: $quizPost) { post in
            QuizSheet(post: post, onOpenPost: { p in path.append(p) })
        }
        .onChange(of: router.pendingPostID) { _, _ in openPending() }
        .onChange(of: store.posts.count) { _, _ in openPending(); openQuizIfAsked() }
        .onChange(of: router.openQuiz) { _, _ in openQuizIfAsked() }
    }

    private func openPending() {
        guard let id = router.pendingPostID, let post = store.post(id: id) else { return }
        router.pendingPostID = nil
        path = NavigationPath()
        path.append(post)
    }

    private func openQuizIfAsked() {
        guard router.openQuiz, let post = quiz.todaysQuestion(from: store.posts) else { return }
        router.openQuiz = false
        quizPost = post
    }

    // MARK: Sections

    private var searchField: some View {
        @Bindable var store = store
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(PS.fg3)
            TextField("Search papers, journals, trials", text: $store.query)
                .font(PS.sys(size: 15))
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !store.query.isEmpty {
                Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PS.line2, lineWidth: 1))
        .padding(.top, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var statusLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if store.isRefreshing && store.posts.isEmpty {
                ProgressView().controlSize(.small)
                Text("Loading the feed…").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
            } else if let msg = store.errorMessage {
                Image(systemName: "wifi.exclamationmark").foregroundStyle(PS.accent)
                Text(msg).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2)
            } else {
                Eyebrow(text: monthEyebrow)
            }
            Spacer()
            Text(countText).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineLimit(1)
        }
        .padding(.bottom, 10)
    }

    private var monthEyebrow: String {
        if store.hasFilters { return "Results" }
        guard let first = store.filtered.first else { return "" }
        return PSDate.monthTitle(first.monthKey)
    }

    private var countText: String {
        let n = store.filtered.count
        if store.hasFilters { return "\(n) of \(store.posts.count) posts" }
        return "\(store.posts.count) posts · \(store.landmarkCount) landmark"
    }

    @ViewBuilder
    private var postList: some View {
        let list = store.filtered
        if list.isEmpty && !store.posts.isEmpty {
            ContentUnavailableView.search(text: store.query.isEmpty ? "these filters" : store.query)
                .padding(.top, 40)
        } else {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, post in
                let prev = index > 0 ? list[index - 1] : nil
                let wasNew = prev.map { store.newIDs.contains($0.id) } ?? false
                let nowNew = store.newIDs.contains(post.id)
                if wasNew && !nowNew {
                    caughtUp
                }
                if let prev, prev.monthKey != post.monthKey || (wasNew && !nowNew) {
                    Eyebrow(text: PSDate.monthTitle(post.monthKey))
                        .padding(.top, 18)
                        .padding(.bottom, 10)
                }
                PostCard(post: post, isNew: nowNew, onOpen: { path.append(post) }, onOpenPaper: { webLink = WebLink(url: $0) })
                    .padding(.bottom, 12)
            }
            if !list.isEmpty {
                endNote
            }
        }
    }

    private var caughtUp: some View {
        HStack(spacing: 10) {
            Hairline()
            Label("You’re all caught up", systemImage: "checkmark.circle")
                .font(PS.sys(size: 12, weight: .semibold))
                .foregroundStyle(PS.green)
                .fixedSize()
            Hairline()
        }
        .padding(.vertical, 6)
    }

    private var endNote: some View {
        VStack(spacing: 6) {
            ECGLine().stroke(PS.line2, lineWidth: 1.2).frame(width: 118, height: 20)
            Text("That’s everything since October 2025").font(PS.serif(size: 15)).foregroundStyle(PS.fg)
            Text("New posts land each morning.").font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// Brand row with the date underneath and a search button; replaces the navigation bar.
struct FeedHeader: View {
    @Binding var searching: Bool
    var onSearch: () -> Void

    private var dateText: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                LogoMark(size: 30, cornerRadius: 8)
                Wordmark(size: 21)
                Spacer()
                Button(action: onSearch) {
                    Image(systemName: searching ? "xmark" : "magnifyingglass")
                        .font(PS.sys(size: 15, weight: .semibold))
                        .foregroundStyle(PS.fg2)
                        .frame(width: 36, height: 36)
                        .background(PS.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(searching ? "Close search" : "Search")
            }
            Eyebrow(text: dateText).padding(.leading, 1)
        }
        .padding(.top, 8)
    }
}

/// Dark background with the site's two soft glows.
struct FeedBackground: View {
    var body: some View {
        ZStack {
            PS.bg
            GeometryReader { geo in
                Circle().fill(PS.blueGlow.opacity(0.12))
                    .frame(width: geo.size.width * 1.2)
                    .blur(radius: 100)
                    .offset(x: -geo.size.width * 0.25, y: -geo.size.height * 0.5)
                Circle().fill(PS.coral.opacity(0.08))
                    .frame(width: geo.size.width * 0.9)
                    .blur(radius: 100)
                    .offset(x: geo.size.width * 0.5, y: -geo.size.height * 0.4)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Filter bar

struct FilterBar: View {
    @Environment(PostStore.self) private var store
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var store = store
        @Bindable var prefs = prefs
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isOn: !store.hasFilters, fg: PS.accent) { store.clearFilters() }
                if !prefs.myTopics.isEmpty {
                    FilterChip(title: "For you", isOn: prefs.forYou, fg: PS.accent) { prefs.forYou.toggle() }
                }
                FilterChip(title: "This week", isOn: store.recentOnly, fg: PS.accent) { store.recentOnly.toggle() }
                FilterChip(title: "Landmark", isOn: store.landmarkOnly, fg: PS.accent) { store.landmarkOnly.toggle() }
                ForEach(Topics.all) { t in
                    FilterChip(title: t.name, isOn: store.selectedTopics.contains(t.id), fg: PS.accent, dot: t.fg) {
                        if store.selectedTopics.contains(t.id) { store.selectedTopics.remove(t.id) } else { store.selectedTopics.insert(t.id) }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .padding(.horizontal, -20)
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }
}

struct FilterChip: View {
    var title: String
    var isOn: Bool
    var fg: Color
    var dot: Color? = nil
    var action: () -> Void
    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 7) {
                if let dot { Circle().fill(isOn ? PS.accentFg.opacity(0.8) : dot).frame(width: 7, height: 7) }
                Text(title)
            }
            .font(PS.sys(size: 12.5, weight: .semibold))
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(isOn ? fg : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(isOn ? .clear : PS.line2, lineWidth: 1))
            .foregroundStyle(isOn ? PS.accentFg : PS.fg2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - One-time invitation to turn on alerts (shown from the second launch)

struct NotifyBanner: View {
    @AppStorage("ps.notifyBannerDismissed") private var dismissed = false
    @AppStorage("ps.launchCount") private var launchCount = 0
    @ObservedObject private var notifications = NotificationManager.shared
    @State private var busy = false

    private var visible: Bool {
        !dismissed && launchCount >= 2 && !notifications.enabled && notifications.authorization != .denied
    }

    var body: some View {
        if visible {
            VStack(spacing: 0) {
                QuietRow(icon: "bell.badge", tint: PS.accent, eyebrow: "Morning alerts", text: "One notification when new papers land, at the time you choose.", textSize: 14, lines: 2) {
                    HStack(spacing: 4) {
                        Button {
                            busy = true
                            Task { _ = await notifications.requestPermission(); busy = false; dismissed = true }
                        } label: { Text(busy ? "…" : "Turn on") }
                        .buttonStyle(CapsuleButtonStyle(prominent: true))
                        Button { dismissed = true } label: {
                            Image(systemName: "xmark").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.fg3).frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss")
                    }
                }
                Hairline()
            }
            .task { await notifications.refreshAuthorization() }
        }
    }
}
