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
                                        if i < group.posts.count - 1 { Hairline().padding(.leading, 18) }
                                    }
                                }
                                .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                            } header: {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(group.society)
                                        .font(PS.serif(size: 18))
                                        .foregroundStyle(group.society == "FDA and safety notices" ? PS.accent : PS.fg)
                                    Spacer()
                                    Text("\(group.posts.count)").font(PS.mono(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                                }
                                .padding(.top, 14)
                                .padding(.bottom, 8)
                                .background(PS.bg.opacity(0.94))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(FeedBackground())
            .scrollContentBackground(.hidden)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Society, topic, drug, procedure")
            .navigationTitle("Guidelines")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: Post.self) { post in
                DeepDiveView(post: post, onOpenPaper: { webLink = WebLink(url: $0) })
            }
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
            .font(PS.sys(size: 14))
            .foregroundStyle(PS.fg2)
            .lineSpacing(2)
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
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(post.headline)
                        .font(PS.serif(size: 15.5))
                        .foregroundStyle(PS.fg)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Circle().fill(Topics.info(post.primaryTopic).fg).frame(width: 7, height: 7)
                        Text(post.journal).fontWeight(.semibold)
                        Text("·").foregroundStyle(PS.fg3)
                        Text(post.kind)
                        Text("·").foregroundStyle(PS.fg3)
                        Text(PSDate.display(post.date, long: true))
                        if post.isLandmark { Eyebrow(text: "Landmark", color: PS.accent, size: 9.5) }
                        if isUnread { UnreadDot() }
                    }
                    .font(PS.sys(size: 12))
                    .foregroundStyle(PS.fg2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3).padding(.top, 4)
            }
            .padding(.horizontal, 18).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
