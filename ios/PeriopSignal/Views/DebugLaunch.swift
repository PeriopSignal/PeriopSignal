import SwiftUI
import WidgetKit

#if DEBUG
/// Launch arguments used by the CI screenshot run (simulator only):
///   -ps.openPost <id>       open a deep dive once the feed has loaded
///   -ps.tab saved|more|reference   start on a tab
///   -ps.ref <RefRoute.key>  open a tool, quick reference or folder on the Reference tab (score:rcri, quickref:<id>, peds, valves, folder:<id> …)
///   -ps.score.on a,b        open a score calculator (score:<id>) with these toggles on (ids as in Scores.swift: female,nonsmoker,...)
///   -ps.ponv.factors a,b / -ps.ponv.agents a,b   the PONV tool with these Apfel factors and agents ticked; -ps.patient.width 375 lays it out at that width
///   -ps.presave <id>        bookmark a post before the first frame
///   -ps.topics a,b          follow these topics (turns on "For you")
///   -ps.favorites.debug a,b  star these Reference tools (RefRoute keys) for this launch
///   -ps.openQuiz 1          open the question of the day
///   -ps.listen 1            show the mini player (paused)
///   -ps.screen widget       show the widget preview screen instead of the app
///   -ps.screen cards        show the two posts with the most topic tags as cards (button-row layout check)
///   -ps.screen cards -ps.card.post a,b   the feed cards of these posts (ids) instead of the two with most topic tags (1.12: the glance line's third line)
///   -ps.screen sharecard    render the share image for the newest landmark post
///   -ps.screen gallery      My Patient's style gallery: every chip, link and heading variant on one page (1.11)
///   -ps.showWelcome 1       open the welcome screen (topics and alerts)
///   -ps.nx.drug <id> [-ps.nx.tier <id>] [-ps.nx.renal <n>] [-ps.nx.elderly 1]   Blocks on anticoagulants: pick the drug, the dose
///                           tier, the kidney row (counted from 0) and the elderly toggle, with -ps.ref neuraxial. With none of them the tool
///                           starts unchosen, as it does for a user. Add -ps.patient.width 375 to lay it out at that width.
///   -ps.ask.demo matched|none   the Ask sheet with a fixed question and a canned answer, no model called. "matched" lists sample
///                           sources found by the app's own matching; "none" shows the nothing-matched line. Add -ps.patient.width 375 and -ps.textScale 1.5 as usual.
///   -ps.forceAppearance light|dark   this launch only (not saved) / -ps.forceLaunchCount N
///   -ps.peds.tab 0|1|2      the pediatric calculator's section: Drugs, Airway, Fluids & Blood (with -ps.peds.weight, .years, .months)
///   -ps.mcs.table 1         open the Device numbers sheet on the mechanical support page (with -ps.mcs.device lvad)
///   -ps.patient demo-switch | demo-switch-peds   two made-up cases (OR 4, OR 9); with -ps.ref peds, -ps.ref score:rcri or
///                           -ps.patient.open prophylaxis the tool opens for the case -ps.patient.case picks (1 or 2), and
///                           -ps.case.switchAfter 12 -ps.case.switchTo 2 makes the second case current 12 s after launch, once the
///                           tool is on screen: the picture shows the tool refilled for it (CaseScope, PatientDemoCaseSwitch115)
///   -ps.patient.width 375   also lays the pediatric calculator, the mechanical support page, a post's deep dive and the
///                           Reference home out at that width; -ps.textScale 1.5 lays the Reference home out at large text
enum DebugLaunch {
    static var openPost: String? { UserDefaults.standard.string(forKey: "ps.openPost") }
    static var tab: String? { UserDefaults.standard.string(forKey: "ps.tab") }
    static var presave: String? { UserDefaults.standard.string(forKey: "ps.presave") }
    static var screen: String? { UserDefaults.standard.string(forKey: "ps.screen") }
    /// "matched" or "none": see AskDemo.
    static var askDemo: String? {
        let s = LaunchSeed.string("ps.ask.demo")
        return s.isEmpty ? nil : s
    }
    static var openQuiz: Bool { UserDefaults.standard.bool(forKey: "ps.openQuiz") }
    static var listen: Bool { UserDefaults.standard.bool(forKey: "ps.listen") }
    static var showWelcome: Bool { UserDefaults.standard.bool(forKey: "ps.showWelcome") }
    /// Any `RefRoute.key`: score:rcri, quickref:<id>, peds, local, infusions, neuraxial, fasting, airway, valves, folder:<id>.
    static var refRoute: RefRoute? {
        guard let s = UserDefaults.standard.string(forKey: "ps.ref"), !s.isEmpty else { return nil }
        return RefRoute(key: s)
    }
    static var topics: [String]? {
        guard let s = UserDefaults.standard.string(forKey: "ps.topics.debug"), !s.isEmpty else { return nil }
        return s.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

/// What the Ask sheet shows in a screenshot run instead of calling a model: the library it searches and the answer it shows.
struct AskPreset {
    var posts: [Post]
    var refs: [QuickRef]
    var answer: String
    var backend: AskEngine.Backend
}

/// Sample material for the Ask screenshots. It is made up for the picture (it says so) and carries no clinical content.
enum AskDemo {
    static func post(_ id: String, _ headline: String) -> Post {
        Post(id: id, date: "2026-10-14", journal: "Sample Journal", jshort: "Sample", kind: "RCT", topics: [],
             headline: headline, summary: "A sample post made up for a screenshot.", takeHome: [], deepDive: "", url: "https://example.com", impact: 1)
    }

    static var refs: [QuickRef] {
        [QuickRef(id: "demo-ref", title: "Sample quick reference: tranexamic acid", society: "Sample Society", short: "Sample", year: 2025,
                  keywords: ["TXA"], summary: "A sample card made up for a screenshot.",
                  source: RefSource(title: "Sample source", url: "https://example.com"),
                  sections: [RefSection(heading: "Cardiac surgery", kind: .text, text: "Sample text about cardiac surgery.")])]
    }

    /// The question, the sample library and the canned answer for a launch argument; nil for any other value.
    static func preset(_ name: String) -> (question: String, preset: AskPreset)? {
        let library = [post("demo-1", "Sample post: tranexamic acid in cardiac surgery"),
                       post("demo-2", "Sample post: a different topic that should not be listed")]
        switch name {
        case "matched":
            return ("What is TXA used for in cardiac surgery?",
                    AskPreset(posts: library, refs: refs,
                              answer: "Sample answer for a screenshot; no model was called. It cites the sample sources as [1] and [2].",
                              backend: .onDevice))
        case "none":
            return ("How do I plan the week for my team?",
                    AskPreset(posts: library, refs: refs,
                              answer: "Sample answer for a screenshot; no model was called. It is written from general knowledge.",
                              backend: .onDevice))
        default:
            return nil
        }
    }
}

/// The Ask sheet on its own for the screenshot run.
struct AskDemoScreen: View {
    var body: some View {
        if let d = AskDemo.preset(DebugLaunch.askDemo ?? "") {
            AskView(question: d.question, preset: d.preset)
        } else {
            Text("Unknown -ps.ask.demo value").foregroundStyle(PS.fg)
        }
    }
}

/// Renders the two posts with the most topic tags as feed cards, so the CI screenshot shows the
/// tags-plus-buttons row at its most crowded.
struct CardPreviewScreen: View {
    @Environment(PostStore.self) private var store
    var body: some View {
        let chosen = LaunchSeed.list("ps.card.post").compactMap { id in store.posts.first { $0.id == id } }
        let posts = chosen.isEmpty ? Array(store.posts.sorted { $0.topics.count > $1.topics.count }.prefix(2)) : chosen
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(posts.isEmpty ? [Post.sample] : posts) { post in
                    PostCard(post: post, onOpen: {}, onOpenPaper: { _ in })
                }
            }
            .padding(16)
        }
        .background(PS.bg.ignoresSafeArea())
        .task { await store.loadInitial() }
    }
}

/// Shows the share image exactly as it is rendered (the newest landmark post).
struct ShareCardPreviewScreen: View {
    @Environment(PostStore.self) private var store
    @State private var image: UIImage?
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Share image").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(PS.fg)
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 16)
                    Text("\(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale)) px")
                        .font(.caption).foregroundStyle(PS.fg3)
                } else {
                    ProgressView()
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(PS.bg.ignoresSafeArea())
        .task {
            await store.loadInitial()
            let post = store.newestLandmark ?? store.newestPost ?? .sample
            image = ShareCardRenderer.render(post)
        }
    }
}

/// Renders the widget families at their real sizes so the CI run can screenshot them.
struct WidgetPreviewScreen: View {
    @Environment(PostStore.self) private var store
    var body: some View {
        let post = store.newestLandmark ?? store.newestPost ?? .sample
        let entry = FeedEntry(date: Date(), post: post, newThisWeek: store.publishedThisWeek, isPlaceholder: false)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Widget preview").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(PS.fg)
                Text("Small").font(.caption).foregroundStyle(PS.fg3)
                PeriopSignalWidgetEntryView(entry: entry, family: .systemSmall)
                    .padding(16)
                    .frame(width: 170, height: 170)
                    .background(Color(hex: "111722"), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                Text("Medium").font(.caption).foregroundStyle(PS.fg3)
                PeriopSignalWidgetEntryView(entry: entry, family: .systemMedium)
                    .padding(16)
                    .frame(width: 364, height: 170)
                    .background(Color(hex: "111722"), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                Text("Lock screen").font(.caption).foregroundStyle(PS.fg3)
                PeriopSignalWidgetEntryView(entry: entry, family: .accessoryRectangular)
                    .padding(8)
                    .frame(width: 172, height: 76)
                    .foregroundStyle(.white)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PS.bg.ignoresSafeArea())
        .task { await store.loadInitial() }
    }
}
#endif
