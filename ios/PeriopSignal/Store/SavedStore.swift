import Foundation
import Observation

/// Saved posts, mirrored to iCloud Key-Value Storage so the same list appears on every device
/// signed into the owner's iCloud account. Falls back to local storage when iCloud is unavailable.
@MainActor
@Observable
final class SavedStore {
    private(set) var ids: Set<String> = []
    private let key = "ps.saved"
    private let kv = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        load()
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kv, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
        kv.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        persist()
    }

    private func load() {
        let cloud = kv.array(forKey: key) as? [String]
        let local = defaults.array(forKey: key) as? [String]
        // Union keeps a bookmark made offline on this device until iCloud catches up.
        ids = Set((cloud ?? []) + (local ?? []))
        if cloud == nil, let local, !local.isEmpty { kv.set(local, forKey: key) }
    }

    private func persist() {
        let list = Array(ids).sorted()
        defaults.set(list, forKey: key)
        kv.set(list, forKey: key)
        kv.synchronize()
    }
}
