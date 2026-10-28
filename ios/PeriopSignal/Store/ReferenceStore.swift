import Foundation
import Observation

/// Holds reference.json: the bundled copy first, the cached download if newer, then a refresh.
@MainActor
@Observable
final class ReferenceStore {
    private(set) var bundle: ReferenceBundle?
    private(set) var lastRefresh: Date?
    private var loaded = false

    var quickrefs: [QuickRef] {
        (bundle?.quickrefs ?? []).sorted { a, b in
            if a.isEmergency != b.isEmergency { return a.isEmergency }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }
    var peds: PedsData? { bundle?.peds }
    var askEndpoint: URL? {
        guard let s = bundle?.ask?.endpoint, let u = URL(string: s), u.scheme == "https" else { return nil }
        return u
    }

    func quickref(_ id: String) -> QuickRef? { bundle?.quickrefs.first { $0.id == id } }

    func load() async {
        guard !loaded else { return }
        loaded = true
        let bundled = ReferenceLoader.loadBundled()
        let cached = ReferenceLoader.loadCached()
        // Prefer whichever is newer by its `updated` date; the bundled copy wins ties (it matched the build).
        if let c = cached, let b = bundled {
            bundle = c.updated > b.updated ? c : b
        } else {
            bundle = cached ?? bundled
        }
        await refresh()
    }

    func refresh() async {
        guard let (fresh, data) = try? await ReferenceLoader.fetch() else { return }
        if bundle == nil || fresh.updated >= (bundle?.updated ?? "") {
            bundle = fresh
            ReferenceLoader.saveCache(data)
        }
        lastRefresh = Date()
    }

    #if DEBUG
    func inject(_ b: ReferenceBundle) { bundle = b; loaded = true }
    #endif
}
