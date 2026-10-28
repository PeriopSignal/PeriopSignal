import SwiftUI

/// Where to go from the Reference tab's lists and search results.
enum RefRoute: Hashable {
    case quickref(String)
    case score(String)
    case peds
}

/// The Reference tab: calculators, condensed society quick references, and the society guidelines
/// that have come through the feed — with one search across all of it and the papers.
struct ReferenceView: View {
    @Environment(PostStore.self) private var store
    @Environment(ReadStore.self) private var read
    @Environment(ReferenceStore.self) private var refs
    @Environment(Router.self) private var router
    @State private var path = NavigationPath()
    @State private var webLink: WebLink?
    @State private var query = ""
    @State private var ask: AskPrompt?

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searching: Bool { !trimmed.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if searching {
                        ReferenceSearchResults(query: trimmed, path: $path) { ask = AskPrompt(question: trimmed) }
                    } else {
                        calculators
                        quickReferences
                        FeedGuidelinesSection(path: $path)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .background(FeedBackground())
            .scrollContentBackground(.hidden)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Drug, score, society, procedure")
            .navigationTitle("Reference")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: RefRoute.self) { route in
                switch route {
                case .quickref(let id):
                    if let ref = refs.quickref(id) {
                        QuickRefView(ref: ref, onOpen: { webLink = WebLink(url: $0) })
                    } else {
                        ContentUnavailableView("Not available offline yet", systemImage: "wifi.slash", description: Text("This reference arrives with the next refresh."))
                    }
                case .score(let id):
                    if let def = Scores.byID(id) { ScoreCalculatorView(def: def, onOpen: { webLink = WebLink(url: $0) }) }
                case .peds:
                    PedsCalculatorView(onOpen: { webLink = WebLink(url: $0) })
                }
            }
            .navigationDestination(for: Post.self) { post in
                DeepDiveView(post: post, onOpenPaper: { webLink = WebLink(url: $0) })
            }
            .listenBar()
        }
        .fullScreenCover(item: $webLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
        .sheet(item: $ask) { prompt in
            AskView(question: prompt.question,
                    onOpenPost: { post in ask = nil; path.append(post) },
                    onOpenRef: { ref in ask = nil; path.append(RefRoute.quickref(ref.id)) })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear { consumePending() }
        .onChange(of: router.pendingRefRoute) { _, _ in consumePending() }
        .onChange(of: refs.quickrefs.count) { _, _ in consumePending() }
    }

    /// Opens a route requested from a link or launch argument once its content exists.
    private func consumePending() {
        guard let route = router.pendingRefRoute else { return }
        if case .quickref(let id) = route, refs.quickref(id) == nil { return }   // wait for the bundle
        router.pendingRefRoute = nil
        path = NavigationPath()
        path.append(route)
    }

    // MARK: Calculators

    private var calculators: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Calculators").padding(.leading, 2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Scores.all) { def in
                    CalculatorTile(icon: def.icon, title: def.short, blurb: def.blurb) { path.append(RefRoute.score(def.id)) }
                }
                CalculatorTile(icon: "scalemass", title: "Pediatric", blurb: "Weight-based doses, tube sizes, fluids and blood volume") { path.append(RefRoute.peds) }
            }
        }
    }

    // MARK: Quick references

    private var quickReferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Quick references").padding(.leading, 2)
                Spacer()
                if let updated = refs.bundle?.updated { Eyebrow(text: "Reviewed \(PSDate.monthYear(updated))", size: 10) }
            }
            if refs.quickrefs.isEmpty {
                Text("Loading the references…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3).padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(refs.quickrefs.enumerated()), id: \.element.id) { i, ref in
                        QuickRefRow(ref: ref) { path.append(RefRoute.quickref(ref.id)) }
                        if i < refs.quickrefs.count - 1 { Hairline().padding(.leading, 18) }
                    }
                }
                .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                Text("Condensed from the society documents in Periop Signal's words, each with a link to the original. Confirm against the source before acting on it.")
                    .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

struct CalculatorTile: View {
    var icon: String
    var title: String
    var blurb: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(PS.sys(size: 17, weight: .semibold))
                    .foregroundStyle(PS.accent)
                    .frame(height: 22)
                Text(title)
                    .font(PS.serif(size: 16.5))
                    .foregroundStyle(PS.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(blurb)
                    .font(PS.sys(size: 12))
                    .foregroundStyle(PS.fg2)
                    .lineSpacing(1)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct QuickRefRow: View {
    var ref: QuickRef
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(ref.title)
                        .font(PS.serif(size: 15.5))
                        .foregroundStyle(PS.fg)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if ref.isEmergency {
                            Eyebrow(text: "Emergency", color: PS.accent, size: 9.5)
                        } else {
                            Circle().fill(Topics.info(ref.topic ?? "general").fg).frame(width: 7, height: 7)
                        }
                        Text(ref.societyShort).fontWeight(.semibold)
                        if let y = ref.year {
                            Text("·").foregroundStyle(PS.fg3)
                            Text(String(y))
                        }
                    }
                    .font(PS.sys(size: 12))
                    .foregroundStyle(PS.fg2)
                    .lineLimit(1)
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

// MARK: - Society guidelines from the feed (the previous Guidelines tab, as a section)

struct FeedGuidelinesSection: View {
    @Environment(PostStore.self) private var store
    @Environment(ReadStore.self) private var read
    @Binding var path: NavigationPath
    var groups: [(society: String, posts: [Post])]? = nil

    private var shown: [(society: String, posts: [Post])] { groups ?? store.guidelineGroups }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Society guidelines from the feed").padding(.leading, 2)
                Spacer()
                let n = shown.reduce(0) { $0 + $1.posts.count }
                if n > 0 { Text("\(n)").font(PS.mono(size: 11, weight: .semibold)).foregroundStyle(PS.fg3) }
            }
            if store.posts.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                ForEach(shown, id: \.society) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.society)
                                .font(PS.serif(size: 17))
                                .foregroundStyle(group.society == "FDA and safety notices" ? PS.accent : PS.fg)
                            Spacer()
                            Text("\(group.posts.count)").font(PS.mono(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                        }
                        .padding(.top, 6)
                        VStack(spacing: 0) {
                            ForEach(Array(group.posts.enumerated()), id: \.element.id) { i, post in
                                GuidelineRow(post: post, isUnread: read.isUnread(post)) { path.append(post) }
                                if i < group.posts.count - 1 { Hairline().padding(.leading, 18) }
                            }
                        }
                        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                    }
                }
            }
        }
    }
}

// MARK: - Search across everything

/// A question handed to the Ask sheet.
struct AskPrompt: Identifiable {
    var question: String
    var id: String { question }
}

struct ReferenceSearchResults: View {
    @Environment(PostStore.self) private var store
    @Environment(ReadStore.self) private var read
    @Environment(ReferenceStore.self) private var refs
    var query: String
    @Binding var path: NavigationPath
    var onAsk: () -> Void = {}

    private var askAvailable: Bool { AskEngine.onDeviceAvailable || refs.askEndpoint != nil }

    private var q: String { query.lowercased() }
    private var scores: [ScoreDefinition] { Scores.all.filter { $0.searchText.contains(q) } }
    private var pedsMatches: Bool {
        guard let p = refs.peds else { return false }
        let words = ["pediatric", "peds", "child", "weight", "dose", "dosing", "ett", "tube", "lma", "fluid", "blood volume", "mabl"]
        return words.contains { $0.contains(q) || q.contains($0) } || p.drugs.contains { $0.name.lowercased().contains(q) } || p.localAnesthetics.contains { $0.name.lowercased().contains(q) }
    }
    private var quickrefs: [QuickRef] { refs.quickrefs.filter { $0.searchText.contains(q) } }
    private var guidelineGroups: [(society: String, posts: [Post])] {
        store.guidelineGroups.compactMap { g in
            let hits = g.posts.filter { $0.searchText.contains(q) || g.society.lowercased().contains(q) }
            return hits.isEmpty ? nil : (society: g.society, posts: hits)
        }
    }
    private var papers: [Post] {
        store.posts.filter { !$0.isGuidance && !$0.isRegulatory && $0.searchText.contains(q) }
    }

    var body: some View {
        let nothing = scores.isEmpty && !pedsMatches && quickrefs.isEmpty && guidelineGroups.isEmpty && papers.isEmpty
        if nothing {
            VStack(spacing: 10) {
                ContentUnavailableView.search(text: query)
                AskRow(query: query, available: askAvailable, action: onAsk)
            }
            .padding(.top, 30)
        } else {
            if !scores.isEmpty || pedsMatches {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Calculators").padding(.leading, 2)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(scores) { def in
                            CalculatorTile(icon: def.icon, title: def.short, blurb: def.blurb) { path.append(RefRoute.score(def.id)) }
                        }
                        if pedsMatches {
                            CalculatorTile(icon: "scalemass", title: "Pediatric", blurb: "Weight-based doses, tube sizes, fluids and blood volume") { path.append(RefRoute.peds) }
                        }
                    }
                }
            }
            if !quickrefs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Quick references").padding(.leading, 2)
                    VStack(spacing: 0) {
                        ForEach(Array(quickrefs.enumerated()), id: \.element.id) { i, ref in
                            QuickRefRow(ref: ref) { path.append(RefRoute.quickref(ref.id)) }
                            if i < quickrefs.count - 1 { Hairline().padding(.leading, 18) }
                        }
                    }
                    .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                }
            }
            if !guidelineGroups.isEmpty {
                FeedGuidelinesSection(path: $path, groups: guidelineGroups)
            }
            if !papers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Eyebrow(text: "Papers in the feed").padding(.leading, 2)
                        Spacer()
                        Text("\(papers.count)").font(PS.mono(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(papers.prefix(25).enumerated()), id: \.element.id) { i, post in
                            GuidelineRow(post: post, isUnread: read.isUnread(post)) { path.append(post) }
                            if i < min(papers.count, 25) - 1 { Hairline().padding(.leading, 18) }
                        }
                    }
                    .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                }
            }
            AskRow(query: query, available: askAvailable, action: onAsk)
        }
    }
}

/// A guideline or paper row: headline, then journal · kind · date with the topic dot.
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
