import Foundation

// MARK: - reference.json
//
// The Reference tab's content: condensed quick references (society guidelines and checklists, each
// citing its source document) and the pediatric dosing table. It lives at the repository root as
// reference.json, is served by GitHub Pages next to posts.json, is bundled with the app as a fallback,
// and is refreshed on launch, so a correction never has to wait for an app update.

struct ReferenceBundle: Codable {
    var version: Int
    var updated: String
    var disclaimer: String?
    var ask: AskConfig?
    var quickrefs: [QuickRef]
    var peds: PedsData?
}

/// Where the app sends questions the references and the feed cannot answer (set once the proxy exists).
struct AskConfig: Codable, Hashable {
    var endpoint: String?
}

struct RefSource: Codable, Hashable {
    var title: String
    var citation: String?
    var url: String
    var doi: String?
}

struct QuickRef: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var society: String
    /// Short society name for eyebrows ("ASRA", "ASE", "MHAUS").
    var short: String?
    var year: Int?
    /// Topic id for the colour dot (see Topics).
    var topic: String?
    var keywords: [String]?
    var summary: String
    var source: RefSource
    var reviewed: String?
    /// Emergency checklists get the coral treatment and sort first.
    var emergency: Bool?
    var sections: [RefSection]

    var isEmergency: Bool { emergency ?? false }
    var societyShort: String { short ?? society }

    /// Everything searchable, lowercased once.
    var searchText: String {
        var parts = [title, society, societyShort, summary]
        parts += keywords ?? []
        for s in sections {
            if let h = s.heading { parts.append(h) }
            parts += s.items ?? []
            if let t = s.text { parts.append(t) }
            for row in s.rows ?? [] { parts += row }
        }
        return parts.joined(separator: " ").lowercased()
    }
}

struct RefSection: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        /// `columns` + `rows`: the first cell of a row is its title.
        case table
        /// `items`: diamond bullets.
        case list
        /// `items`: numbered steps.
        case steps
        /// `text`: a paragraph.
        case text
        /// `rows` of [label, value]: a two-column fact table.
        case facts
    }
    var heading: String?
    var kind: Kind
    var columns: [String]?
    var rows: [[String]]?
    var items: [String]?
    var text: String?
    var note: String?
}

// MARK: Pediatric dosing data

struct PedsData: Codable {
    var reviewed: String?
    var note: String?
    var drugs: [PedsDrug]
    var localAnesthetics: [LocalAnesthetic]
    var bloodVolume: [BloodVolumeRow]
}

struct PedsDrug: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// What the dose is for ("Induction", "RSI", "Cardiac arrest").
    var use: String
    /// Grouping on screen ("Induction", "Neuromuscular", "Emergency", "Analgesia", "Antiemetic", "Reversal", "Other").
    var group: String
    var route: String
    /// Dose per kilogram: `low`–`high` `unit`/kg (high optional).
    var low: Double
    var high: Double?
    var unit: String
    /// Ceiling for one dose, in `unit` (e.g. 1 mg of epinephrine, 4 mg of ondansetron).
    var max: Double?
    /// Concentration note, shown as written ("0.1 mg/mL (1:10,000) → 0.1 mL/kg").
    var conc: String?
    var note: String?
    var source: String?
}

struct LocalAnesthetic: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// Maximum single-injection dose, mg/kg.
    var maxMgPerKg: Double
    /// Typical concentrations as percent, for the mL conversion (0.25 → 0.25% = 2.5 mg/mL).
    var concentrations: [Double]
    var note: String?
    var source: String?
}

struct BloodVolumeRow: Codable, Identifiable, Hashable {
    var id: String { group }
    var group: String
    /// Age window in months the row applies to (upper bound exclusive; nil = open).
    var fromMonths: Double?
    var toMonths: Double?
    var mlPerKgLow: Double
    var mlPerKgHigh: Double
}

// MARK: - Loader (network + cache + bundled fallback)

enum ReferenceLoader {
    static let url = URL(string: "https://periopsignal.github.io/PeriopSignal/reference.json")!
    static let decoder = JSONDecoder()

    static func decode(_ data: Data) throws -> ReferenceBundle { try decoder.decode(ReferenceBundle.self, from: data) }

    static func fetch() async throws -> (ReferenceBundle, Data) {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970 / 3600)))]
        var req = URLRequest(url: comps.url!)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { throw URLError(.badServerResponse) }
        return (try decode(data), data)
    }

    static var cacheURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("reference.json")
    }

    static func loadCached() -> ReferenceBundle? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? decode(data)
    }

    static func saveCache(_ data: Data) { try? data.write(to: cacheURL, options: .atomic) }

    /// The copy shipped inside the app (the repository's reference.json at build time).
    static func loadBundled(bundle: Bundle = .main) -> ReferenceBundle? {
        guard let url = bundle.url(forResource: "reference", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }
}
