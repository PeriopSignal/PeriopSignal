import Foundation

/// The feed file published by the website (posts.json).
struct Feed: Codable {
    var name: String
    var generatedAt: String
    var posts: [Post]
}

struct Post: Codable, Identifiable, Hashable {
    var id: String
    var date: String
    var dateApprox: Bool
    var addedAt: String
    var journal: String
    var jshort: String
    var kind: String
    var topics: [String]
    var headline: String
    var summary: String
    var takeHome: [String]
    var deepDive: String
    var url: String
    var impact: Int
    var trialName: String
    var firstAuthor: String
    var authorLimitations: [String]
    var authorBasis: String
    var takeHomeBy: String

    enum CodingKeys: String, CodingKey {
        case id, date, dateApprox, addedAt, journal, jshort, kind, topics, headline, summary, takeHome, deepDive, url, impact, trialName, firstAuthor, authorLimitations, authorBasis, takeHomeBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        dateApprox = try c.decodeIfPresent(Bool.self, forKey: .dateApprox) ?? false
        addedAt = try c.decodeIfPresent(String.self, forKey: .addedAt) ?? date
        journal = try c.decodeIfPresent(String.self, forKey: .journal) ?? ""
        jshort = try c.decodeIfPresent(String.self, forKey: .jshort) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        topics = try c.decodeIfPresent([String].self, forKey: .topics) ?? []
        headline = try c.decodeIfPresent(String.self, forKey: .headline) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        takeHome = try c.decodeIfPresent([String].self, forKey: .takeHome) ?? []
        deepDive = try c.decodeIfPresent(String.self, forKey: .deepDive) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        impact = try c.decodeIfPresent(Int.self, forKey: .impact) ?? 1
        trialName = try c.decodeIfPresent(String.self, forKey: .trialName) ?? ""
        firstAuthor = try c.decodeIfPresent(String.self, forKey: .firstAuthor) ?? ""
        authorLimitations = try c.decodeIfPresent([String].self, forKey: .authorLimitations) ?? []
        authorBasis = try c.decodeIfPresent(String.self, forKey: .authorBasis) ?? ""
        takeHomeBy = try c.decodeIfPresent(String.self, forKey: .takeHomeBy) ?? ""
    }

    init(id: String, date: String, dateApprox: Bool = false, addedAt: String? = nil, journal: String, jshort: String, kind: String, topics: [String], headline: String, summary: String, takeHome: [String], deepDive: String, url: String, impact: Int, trialName: String = "", firstAuthor: String = "", authorLimitations: [String] = [], authorBasis: String = "", takeHomeBy: String = "") {
        self.id = id; self.date = date; self.dateApprox = dateApprox; self.addedAt = addedAt ?? date
        self.journal = journal; self.jshort = jshort; self.kind = kind; self.topics = topics
        self.headline = headline; self.summary = summary; self.takeHome = takeHome; self.deepDive = deepDive
        self.url = url; self.impact = impact; self.trialName = trialName; self.firstAuthor = firstAuthor
        self.authorLimitations = authorLimitations; self.authorBasis = authorBasis; self.takeHomeBy = takeHomeBy
    }

    static func == (lhs: Post, rhs: Post) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: Derived

    var isLandmark: Bool { impact >= 3 }
    var primaryTopic: String { topics.first ?? "general" }
    var paperURL: URL? { URL(string: url) }
    var takeHomeIsAuthors: Bool { takeHomeBy == "authors" }

    static let researchKinds: Set<String> = ["RCT", "Observational", "Registry", "Meta-analysis", "Trial update"]
    var isResearch: Bool { Post.researchKinds.contains(kind) }

    var dateValue: Date { PSDate.parse(date) ?? .distantPast }
    var addedAtValue: Date { PSDate.parse(addedAt) ?? dateValue }

    /// Year-month key used for the month dividers in the feed.
    var monthKey: String { String(date.prefix(7)) }

    /// Text that the site's search box matches against.
    var searchText: String {
        [headline, summary, journal, kind, trialName, firstAuthor, takeHome.joined(separator: " ")].joined(separator: " ").lowercased()
    }

    static let sample = Post(
        id: "sample-landmark", date: "2026-10-14", journal: "JAMA", jshort: "JAMA", kind: "RCT", topics: ["criticalCare", "cardiac"],
        headline: "Adding vasopressin at 0.1 vs 0.4 mcg/kg/min norepinephrine did not change 28-day mortality in septic shock",
        summary: "A 13-hospital cluster-crossover trial in Utah and Idaho (3,959 patients) compared hospital policies of adding fixed-dose vasopressin at two norepinephrine thresholds.",
        takeHome: ["28-day mortality 31.8% vs 33.0%; adjusted OR 0.98.", "No gain in kidney replacement-free, vasopressor-free or ICU-free days.", "Exploratory signal of more cardiogenic shock with early vasopressin."],
        deepDive: "**Why it matters.** Observational data suggested that adding vasopressin earlier might save lives.\n\n**What they found.**\n- Mortality at 28 days was 31.8% vs 33.0%.\n- Secondary outcomes were unchanged.\n\n**Caveats.** Open label, policy-level randomization.",
        url: "https://doi.org/10.1001/jama.2026.21333", impact: 3, trialName: "VASSPR", firstAuthor: "Peltan",
        authorLimitations: ["Open-label, cluster-level randomization with incomplete adherence."], authorBasis: "abstract", takeHomeBy: "authors")
}

enum PSDate {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func parse(_ s: String) -> Date? { formatter.date(from: String(s.prefix(10))) }

    static let short: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM d"; return f
    }()
    static let long: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM d, yyyy"; return f
    }()
    static let month: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMMM yyyy"; return f
    }()

    /// "Oct 14" for the current year, "Oct 14, 2025" otherwise.
    static func display(_ s: String, long wantLong: Bool = false) -> String {
        guard let d = parse(s) else { return s }
        let thisYear = Calendar.current.component(.year, from: Date()) == Calendar.current.component(.year, from: d)
        return (wantLong || !thisYear) ? long.string(from: d) : short.string(from: d)
    }
    static func monthTitle(_ key: String) -> String {
        guard let d = parse(key + "-01") else { return key }
        return month.string(from: d)
    }
}
