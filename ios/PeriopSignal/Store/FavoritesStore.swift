import Foundation
import Observation

/// Starred calculators and references (Reference tab), kept in order of starring and mirrored to
/// iCloud Key-Value Storage like saved posts.
@MainActor
@Observable
final class FavoritesStore {
    private(set) var keys: [String] = []
    private let key = "ps.favorites"
    private let kv = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private var observer: NSObjectProtocol?

    init() {
        load()
        #if DEBUG
        // CI screenshots: -ps.favorites.debug "valves,score:rcri" seeds the list for this launch only.
        if let seed = UserDefaults.standard.string(forKey: "ps.favorites.debug"), !seed.isEmpty {
            keys = seed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        #endif
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kv, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.adoptCloud() }
        }
        kv.synchronize()
    }

    func contains(_ k: String) -> Bool { keys.contains(k) }

    func toggle(_ k: String) {
        if let i = keys.firstIndex(of: k) { keys.remove(at: i) } else { keys.append(k) }
        persist()
    }

    /// Tools that were merged into another keep their place in the list under the new key.
    static let renamed: [String: String] = ["score:apfel": "ponv", "quickref:ponv-consensus": "ponv"]

    static func migrate(_ list: [String]) -> [String] {
        var out: [String] = []
        for k in list.map({ renamed[$0] ?? $0 }) where !out.contains(k) { out.append(k) }
        return out
    }

    /// First launch: union of what iCloud and this device know (so nothing starred is lost).
    private func load() {
        let cloud = kv.array(forKey: key) as? [String]
        let local = defaults.array(forKey: key) as? [String]
        let merged = Self.migrate((cloud ?? []) + (local ?? []))
        keys = merged
        if merged != (cloud ?? []) && !merged.isEmpty { persist() }
    }

    /// Another device changed the list: take it as it is, removals included.
    private func adoptCloud() {
        guard let cloud = kv.array(forKey: key) as? [String] else { return }
        keys = Self.migrate(cloud)
        defaults.set(keys, forKey: key)
    }

    private func persist() {
        defaults.set(keys, forKey: key)
        kv.set(keys, forKey: key)
        kv.synchronize()
    }
}
