import Foundation

/// Fetches and caches posts.json. Used by the app and the widget (each in its own container).
enum FeedLoader {
    static let siteURL = URL(string: "https://periopsignal.github.io/PeriopSignal/")!
    static let feedURL = URL(string: "https://periopsignal.github.io/PeriopSignal/posts.json")!

    static let decoder: JSONDecoder = { JSONDecoder() }()

    static func decode(_ data: Data) throws -> Feed {
        try decoder.decode(Feed.self, from: data)
    }

    /// Network fetch that bypasses intermediate caches (GitHub Pages sets short max-age, but be explicit).
    static func fetch() async throws -> (Feed, Data) {
        var comps = URLComponents(url: feedURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970)))]
        var req = URLRequest(url: comps.url!)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let feed = try decode(data)
        return (feed, data)
    }

    // MARK: Cache (Application Support/posts.json)

    static var cacheURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("posts.json")
    }

    static func loadCached() -> Feed? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? decode(data)
    }

    static func saveCache(_ data: Data) {
        try? data.write(to: cacheURL, options: .atomic)
    }

    static var cacheDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate]) as? Date
    }
}
