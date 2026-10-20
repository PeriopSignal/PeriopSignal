import SwiftUI

struct FeedView: View {
    @Environment(PostStore.self) private var store
    @Environment(SavedStore.self) private var saved
    @Environment(Router.self) private var router
    @State private var path = NavigationPath()
    @State private var webLink: WebLink?
    @State private var showShare = false

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                    intro
                    FilterBar()
                    statusLine
                    postList
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(FeedBackground())
            .scrollContentBackground(.hidden)
            .refreshable { await store.refresh() }
            .searchable(text: $store.query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search papers, journals, trials")
            .navigationDestination(for: Post.self) { post in
                DeepDiveView(post: post, onOpenPaper: { webLink = WebLink(url: $0) })
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        LogoMark(size: 26, cornerRadius: 7)
                        Wordmark(size: 19)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share Periop Signal")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PS.bg.opacity(0.9), for: .navigationBar)
        }
        .fullScreenCover(item: $webLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: ["Periop Signal: the practice-changing papers in anesthesiology and critical care, every morning.", FeedLoader.siteURL])
                .presentationDetents([.medium, .large])
        }
        .onChange(of: router.pendingPostID) { _, _ in openPending() }
        .onChange(of: store.posts.count) { _, _ in openPending() }
    }

    private func openPending() {
        guard let id = router.pendingPostID, let post = store.post(id: id) else { return }
        router.pendingPostID = nil
        path = NavigationPath()
        path.append(post)
    }

    // MARK: Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The practice-changing papers in anesthesiology and critical care, from 50 journals every morning.")
                .font(.system(size: 15))
                .foregroundStyle(PS.fg2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("Creator:").font(.system(size: 11, weight: .semibold, design: .monospaced)).textCase(.uppercase).foregroundStyle(PS.fg3)
                Text("Benjamin Mori, MD").font(.system(size: 12.5, weight: .medium)).foregroundStyle(PS.fg2)
            }
        }
        .padding(.top, 6)
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            if store.isRefreshing && store.posts.isEmpty {
                ProgressView().controlSize(.small)
                Text("Loading the feed…").foregroundStyle(PS.fg3)
            } else if let msg = store.errorMessage {
                Image(systemName: "wifi.exclamationmark").foregroundStyle(PS.accent)
                Text(msg).foregroundStyle(PS.fg2)
            } else {
                Text(countText).foregroundStyle(PS.fg3)
                if store.hasFilters {
                    Button("Clear") { store.clearFilters() }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(PS.accent2)
                }
            }
            Spacer()
            if let d = store.lastRefresh {
                Text("Updated " + d.formatted(.relative(presentation: .named)))
                    .foregroundStyle(PS.fg3)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 12.5))
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
                if prev == nil || prev!.monthKey != post.monthKey || (wasNew && !nowNew) {
                    MonthDivider(title: PSDate.monthTitle(post.monthKey))
                }
                PostCard(post: post, isNew: nowNew, onOpen: { path.append(post) }, onOpenPaper: { webLink = WebLink(url: $0) })
            }
            if !list.isEmpty {
                endNote
            }
        }
    }

    private var caughtUp: some View {
        HStack(spacing: 8) {
            Rectangle().fill(PS.line2).frame(height: 1)
            Label("You’re all caught up", systemImage: "checkmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PS.green)
                .fixedSize()
            Rectangle().fill(PS.line2).frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private var endNote: some View {
        VStack(spacing: 4) {
            Text("That’s everything since October 2025").font(.system(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            Text("New posts land each morning.").font(.system(size: 13)).foregroundStyle(PS.fg3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct MonthDivider: View {
    var title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .textCase(.uppercase)
            .kerning(0.8)
            .foregroundStyle(PS.fg3)
            .padding(.top, 8)
    }
}

/// Dark background with the site's two soft glows.
struct FeedBackground: View {
    var body: some View {
        ZStack {
            PS.bg
            GeometryReader { geo in
                Circle().fill(PS.blueGlow.opacity(0.16))
                    .frame(width: geo.size.width * 1.2)
                    .blur(radius: 90)
                    .offset(x: -geo.size.width * 0.2, y: -geo.size.height * 0.45)
                Circle().fill(PS.coral.opacity(0.10))
                    .frame(width: geo.size.width * 0.9)
                    .blur(radius: 90)
                    .offset(x: geo.size.width * 0.5, y: -geo.size.height * 0.35)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Filter bar

struct FilterBar: View {
    @Environment(PostStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let counts = store.topicCounts()
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "This week", count: store.publishedThisWeek, isOn: store.recentOnly, fg: PS.green, bg: PS.green.opacity(0.16)) {
                    store.recentOnly.toggle()
                }
                FilterChip(title: "Landmark", count: store.landmarkCount, isOn: store.landmarkOnly, fg: PS.accent, bg: PS.accent.opacity(0.16)) {
                    store.landmarkOnly.toggle()
                }
                Rectangle().fill(PS.line2).frame(width: 1, height: 18)
                ForEach(Topics.all) { t in
                    FilterChip(title: t.name, count: counts[t.id] ?? 0, isOn: store.selectedTopics.contains(t.id), fg: t.fg, bg: t.bg) {
                        if store.selectedTopics.contains(t.id) { store.selectedTopics.remove(t.id) } else { store.selectedTopics.insert(t.id) }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .padding(.horizontal, -16)
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }
}

struct FilterChip: View {
    var title: String
    var count: Int
    var isOn: Bool
    var fg: Color
    var bg: Color
    var action: () -> Void
    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isOn ? fg.opacity(0.9) : PS.fg3)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(isOn ? bg : PS.surface, in: Capsule())
            .overlay(Capsule().stroke(isOn ? fg.opacity(0.6) : PS.line2, lineWidth: 1))
            .foregroundStyle(isOn ? fg : PS.fg2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
