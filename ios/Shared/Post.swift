import Foundation

/// The feed file published by the website (posts.json).
struct Feed: Codable {
    var name: String
    var generatedAt: String
    var posts: [Post]
}

/// The at-a-glance strip: design, population, primary outcome and result, as the post states them.
struct Glance: Codable, Hashable {
    var design: String = ""
    var n: String = ""
    var outcome: String = ""
    var result: String = ""

    enum CodingKeys: String, CodingKey { case design, n, outcome, result }
    init(design: String = "", n: String = "", outcome: String = "", result: String = "") {
        self.design = design; self.n = n; self.outcome = outcome; self.result = result
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        design = try c.decodeIfPresent(String.self, forKey: .design) ?? ""
        n = try c.decodeIfPresent(String.self, forKey: .n) ?? ""
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome) ?? ""
        result = try c.decodeIfPresent(String.self, forKey: .result) ?? ""
    }
    var isEmpty: Bool { design.isEmpty && n.isEmpty && outcome.isEmpty && result.isEmpty }
    /// Label/value pairs that have a value, in display order.
    var rows: [(label: String, value: String)] {
        [("Design", design), ("Population", n), ("Outcome", outcome), ("Result", result)].filter { !$0.1.isEmpty }
    }
}

/// One single-best-answer question written from the post.
struct Quiz: Codable, Hashable {
    var question: String
    var options: [String]
    var answer: Int
    var explanation: String

    var isValid: Bool { options.count == 4 && (0..<4).contains(answer) && !question.isEmpty }
}

/// A studio recording of the post (made by the repository's audio workflow).
struct PostAudio: Codable, Hashable {
    var url: String
    var seconds: Int
    var bytes: Int?
    var voice: String?
}

/// Bibliographic record from Crossref, used for citations and RIS export.
struct Citation: Codable, Hashable {
    var title: String
    var authors: [String]
    var journal: String?
    var year: Int?
    var volume: String?
    var issue: String?
    var pages: String?
    var doi: String?
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
    var title: String?
    var glance: Glance?
    var quiz: Quiz?
    var citation: Citation?
    var audio: PostAudio?

    enum CodingKeys: String, CodingKey {
        case id, date, dateApprox, addedAt, journal, jshort, kind, topics, headline, summary, takeHome, deepDive, url, impact, trialName, firstAuthor, authorLimitations, authorBasis, takeHomeBy, title, glance, quiz, citation, audio
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
        title = try c.decodeIfPresent(String.self, forKey: .title)
        glance = try? c.decodeIfPresent(Glance.self, forKey: .glance)
        if glance?.isEmpty == true { glance = nil }
        quiz = try? c.decodeIfPresent(Quiz.self, forKey: .quiz)
        if quiz?.isValid == false { quiz = nil }
        citation = try? c.decodeIfPresent(Citation.self, forKey: .citation)
        audio = try? c.decodeIfPresent(PostAudio.self, forKey: .audio)
        if let a = audio, a.seconds < 1 || URL(string: a.url) == nil { audio = nil }
    }

    init(id: String, date: String, dateApprox: Bool = false, addedAt: String? = nil, journal: String, jshort: String, kind: String, topics: [String], headline: String, summary: String, takeHome: [String], deepDive: String, url: String, impact: Int, trialName: String = "", firstAuthor: String = "", authorLimitations: [String] = [], authorBasis: String = "", takeHomeBy: String = "", title: String? = nil, glance: Glance? = nil, quiz: Quiz? = nil, citation: Citation? = nil, audio: PostAudio? = nil) {
        self.id = id; self.date = date; self.dateApprox = dateApprox; self.addedAt = addedAt ?? date
        self.journal = journal; self.jshort = jshort; self.kind = kind; self.topics = topics
        self.headline = headline; self.summary = summary; self.takeHome = takeHome; self.deepDive = deepDive
        self.url = url; self.impact = impact; self.trialName = trialName; self.firstAuthor = firstAuthor
        self.authorLimitations = authorLimitations; self.authorBasis = authorBasis; self.takeHomeBy = takeHomeBy
        self.title = title; self.glance = glance; self.quiz = quiz; self.citation = citation; self.audio = audio
    }

    static func == (lhs: Post, rhs: Post) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: Derived

    var isLandmark: Bool { impact >= 3 }
    var primaryTopic: String { topics.first ?? "general" }
    var paperURL: URL? { URL(string: url) }
    var takeHomeIsAuthors: Bool { takeHomeBy == "authors" }

    static let researchKinds: Set<String> = ["RCT", "Observational", "Registry", "Meta-analysis", "Trial update"]
    static let guidanceKinds: Set<String> = ["Guideline", "Consensus"]
    static let regulatoryKinds: Set<String> = ["FDA/Regulatory", "Safety alert", "Device"]
    var isResearch: Bool { Post.researchKinds.contains(kind) }
    var isGuidance: Bool { Post.guidanceKinds.contains(kind) }
    var isRegulatory: Bool { Post.regulatoryKinds.contains(kind) }

    var dateValue: Date { PSDate.parse(date) ?? .distantPast }
    var addedAtValue: Date { PSDate.parse(addedAt) ?? dateValue }

    /// Year-month key used for the month dividers in the feed (the month the post was added, which is
    /// also the feed's order).
    var monthKey: String { String(addedAt.prefix(7)) }

    /// Text that the site's search box matches against.
    var searchText: String {
        [headline, summary, journal, kind, trialName, firstAuthor, title ?? "", takeHome.joined(separator: " ")].joined(separator: " ").lowercased()
    }

    /// The society or body behind a guideline, consensus or regulatory post, read from the headline and journal.
    var society: String {
        let text = " " + headline + " " + journal + " "
        for (needle, name) in Post.societyMarkers {
            if text.range(of: "\\b" + NSRegularExpression.escapedPattern(for: needle) + "\\b", options: [.regularExpression, .caseInsensitive]) != nil {
                return name
            }
        }
        if isRegulatory { return "FDA and safety notices" }
        return "Other societies"
    }

    /// Ordered so that the more specific marker wins (ESC before ACC, SCA before ASA).
    static let societyMarkers: [(String, String)] = [
        ("FDA", "FDA"), ("APSF", "APSF"), ("SCA", "SCA"), ("SCA/EACTA", "SCA"), ("EACTAIC", "EACTAIC"), ("EACTA", "EACTAIC"),
        ("ASA", "ASA"), ("ASE", "ASE"), ("STS", "STS"), ("AATS", "AATS"), ("EACTS", "EACTS"), ("ESC", "ESC"),
        ("AHA/ACC", "AHA / ACC"), ("ACC/AHA", "AHA / ACC"), ("AHA", "AHA / ACC"), ("ACC", "AHA / ACC"),
        ("ISHLT", "ISHLT"), ("ELSO", "ELSO"), ("ASRA", "ASRA"), ("SOAP", "SOAP"), ("ESAIC", "ESAIC"), ("ESRA", "ESRA"),
        ("SCCM", "SCCM"), ("ESICM", "ESICM"), ("Surviving Sepsis", "SCCM"), ("DAS", "DAS"), ("ILTS", "ILTS"), ("AASLD", "AASLD"),
        ("SPA", "SPA"), ("CCAS", "SPA"), ("ERAS", "ERAS Society"), ("PROSPECT", "PROSPECT"), ("AABB", "AABB"), ("WHO", "WHO"),
        ("NICE", "NICE"), ("HFA", "ESC"), ("ACNAP", "ESC"), ("EAPC", "ESC"), ("ESVS", "ESVS"), ("SVS", "SVS"), ("ASH", "ASH"),
        ("ATS", "ATS"), ("ERS", "ERS"), ("ANZCA", "ANZCA"), ("AAGBI", "Association of Anaesthetists"), ("Association of Anaesthetists", "Association of Anaesthetists"),
        ("CAS", "CAS"), ("ESPEN", "ESPEN"), ("ASPEN", "ASPEN"), ("BTS", "BTS"), ("NATA", "NATA"), ("SIAARTI", "SIAARTI"), ("SFAR", "SFAR"),
    ]

    static let sample = Post(
        id: "sample-landmark", date: "2026-10-14", journal: "JAMA", jshort: "JAMA", kind: "RCT", topics: ["criticalCare", "cardiac"],
        headline: "Adding vasopressin at 0.1 vs 0.4 mcg/kg/min norepinephrine did not change 28-day mortality in septic shock",
        summary: "A 13-hospital cluster-crossover trial in Utah and Idaho (3,959 patients) compared hospital policies of adding fixed-dose vasopressin at two norepinephrine thresholds.",
        takeHome: ["28-day mortality 31.8% vs 33.0%; adjusted OR 0.98.", "No gain in kidney replacement-free, vasopressor-free or ICU-free days.", "Exploratory signal of more cardiogenic shock with early vasopressin."],
        deepDive: "**Why it matters.** Observational data suggested that adding vasopressin earlier might save lives.\n\n**What they found.**\n- Mortality at 28 days was 31.8% vs 33.0%.\n- Secondary outcomes were unchanged.\n\n**Caveats.** Open label, policy-level randomization.",
        url: "https://doi.org/10.1001/jama.2026.21333", impact: 3, trialName: "VASSPR", firstAuthor: "Peltan",
        authorLimitations: ["Open-label, cluster-level randomization with incomplete adherence."], authorBasis: "abstract", takeHomeBy: "authors",
        title: "Early vs Late Vasopressin Initiation in Septic Shock: The VASSPR Cluster-Crossover Trial",
        glance: Glance(design: "Cluster-crossover RCT, 13 US hospitals", n: "3,959 adults with septic shock", outcome: "28-day mortality", result: "31.8% vs 33.0%, adjusted OR 0.98; no difference"),
        quiz: Quiz(question: "In VASSPR, what happened to 28-day mortality when vasopressin was added at a norepinephrine dose of 0.1 rather than 0.4 mcg/kg/min?",
                   options: ["It fell by about 4 percentage points", "It did not change (31.8% vs 33.0%)", "It rose because of cardiogenic shock", "It fell only in patients on kidney replacement"],
                   answer: 1, explanation: "Mortality was 31.8% vs 33.0% (adjusted OR 0.98), with no gain in organ-support-free days. The cardiogenic shock signal was exploratory and did not change mortality. Note the open-label, cluster-level design."),
        citation: Citation(title: "Early vs Late Vasopressin Initiation in Septic Shock: The VASSPR Cluster-Crossover Trial", authors: ["Peltan ID", "Brown SM", "Knox DB"], journal: "JAMA", year: 2026, volume: "336", issue: "15", pages: "1234-1245", doi: "10.1001/jama.2026.21333"))
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

    private static func display(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = TimeZone(identifier: "America/New_York")   // same zone as `parse`, so the day never shifts
        f.dateFormat = format
        return f
    }
    static let short = display("MMM d")
    static let long = display("MMM d, yyyy")
    static let month = display("MMMM yyyy")

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
    /// "Oct 2026" for a YYYY-MM-DD string (review dates).
    static func monthYear(_ s: String) -> String {
        guard let d = parse(s) else { return s }
        return shortMonthYear.string(from: d)
    }
    static let shortMonthYear = display("MMM yyyy")

    /// Today's date in the feed's time zone, as YYYY-MM-DD.
    static var today: String { formatter.string(from: Date()) }

    /// A date N days ago, as YYYY-MM-DD.
    static func daysAgo(_ n: Int) -> String {
        formatter.string(from: Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date())
    }
}
