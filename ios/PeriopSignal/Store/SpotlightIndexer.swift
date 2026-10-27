import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Puts every post into iOS Spotlight so a colleague can type a trial name on the home screen and
/// land in the deep dive. Re-indexed only when the feed changes.
enum SpotlightIndexer {
    static let domain = "posts"
    private static let stampKey = "ps.spotlightStamp"

    static func indexIfNeeded(_ posts: [Post]) async {
        #if targetEnvironment(simulator)
        return   // the simulator's index daemon can stall; devices only
        #else
        guard CSSearchableIndex.isIndexingAvailable(), !posts.isEmpty else { return }
        let stamp = "\(posts.count)|\(posts.map(\.addedAt).max() ?? "")|\(posts.map(\.id).joined().hashValue)"
        guard UserDefaults.standard.string(forKey: stampKey) != stamp else { return }
        let items = posts.map { p -> CSSearchableItem in
            let a = CSSearchableItemAttributeSet(contentType: .text)
            a.title = p.headline
            a.contentDescription = p.summary
            a.keywords = p.topics.map(Topics.name) + [p.journal, p.jshort, p.kind, p.trialName, p.firstAuthor].filter { !$0.isEmpty }
            a.identifier = p.id
            a.contentCreationDate = p.dateValue
            a.displayName = p.headline
            let item = CSSearchableItem(uniqueIdentifier: p.id, domainIdentifier: domain, attributeSet: a)
            item.expirationDate = .distantFuture
            return item
        }
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
            try await CSSearchableIndex.default().indexSearchableItems(items)
            UserDefaults.standard.set(stamp, forKey: stampKey)
        } catch {
            // Indexing is a convenience; try again on the next refresh.
        }
        #endif
    }

    /// The post id inside a Spotlight continuation activity, if it is one of ours.
    static func postID(from activity: NSUserActivity) -> String? {
        guard activity.activityType == CSSearchableItemActionType else { return nil }
        return activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    }
}
