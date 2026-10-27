import SwiftUI

/// Guidelines and consensus statements grouped by society, then FDA and safety notices: the
/// reference shelf next to the daily feed.
struct GuidelinesView: View {
    @Environment(PostStore.self) private var store
    @Environment(ReadStore.self) private var read
    @State private var path = NavigationPath()
    @State private var webLink: WebLink?
    @State private var query = ""

    private var groups: [(society: String, posts: [Post])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.guidelineGroups }
        return store.guidelineGroups.compactMap { g in
            let hits = g.posts.filter { $0.searchText.contains(q) || g.society.lowercased().contains(q) }
            return hits.isEmpty ? nil : (society: g.society, posts: hits)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                    if store.posts.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if groups.isEmpty {
                        ContentUnavailableView.search(text: query).padding(.top, 40)
                    } else {
                        summary
                        ForEach(groups, id: \.society) { group in
                            Section {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.posts.enumerated()), id: \.element.id) { i, post in
                                        GuidelineRow(post: post, isUnread: read.isUnread(post)) { path.append(post) }
                                        if i < group.posts.count - 1 { Divider().overlay(PS.line).padding(.leading, 14) }
                                    }
                                }
                                .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PS.line, lineWidth: 1))
                            } header: {
                                HStack {
                                    Text(group.society)
                                        .font(PS.sys(size: 12, weight: .bold, design: .monospaced))
                                        .textCase(.uppercase).kerning(0.6)
                                        .foregroundStyle(group.society == "FDA and safety notices" ? PS.accent : PS.fg2)
                                    Spacer()
                                    Text("\(group.posts.count)").font(PS.sys(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(PS.fg3)
                                }
                                .padding(.vertical, 6)
                                .padding(.top, 6)
                                .background(PS.bg.opacity(0.92))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(FeedBackground())
            .scrollContentBackground(.hidden)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Society, topic, drug, procedure")
            .navigationTitle("Guidelines")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Post.self) { post in
                DeepDiveView(post: post, onOpenPaper: { webLink = WebLink(url: $0) })
            }
            .toolbarBackground(PS.bg.opacity(0.9), for: .navigationBar)
            .listenBar()
        }
        .fullScreenCover(item: $webLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
    }

    private var summary: some View {
        let guidance = store.posts.filter(\.isGuidance).count
        let regulatory = store.posts.filter(\.isRegulatory).count
        return Text("\(guidance) guidelines and consensus statements from \(max(0, store.guidelineGroups.count - (regulatory > 0 ? 1 : 0))) societies, plus \(regulatory) FDA and safety notices. Newest first within each society.")
            .font(PS.sys(size: 13.5))
            .foregroundStyle(PS.fg2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }
}

struct GuidelineRow: View {
    var post: Post
    var isUnread: Bool
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                JournalAvatar(post: post, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.headline)
                        .font(PS.sys(size: 14.5, weight: .semibold, design: .serif))
                        .foregroundStyle(PS.fg)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        Text(post.kind)
                        Text("·").foregroundStyle(PS.fg3)
                        Text(PSDate.display(post.date, long: true))
                        if post.isLandmark { Pill(text: "Landmark", style: .landmark) }
                        if isUnread { UnreadDot() }
                    }
                    .font(PS.sys(size: 12))
                    .foregroundStyle(PS.fg2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3).padding(.top, 4)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
