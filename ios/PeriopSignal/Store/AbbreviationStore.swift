import Foundation
import Observation

/// An abbreviation the user explained, for Fill from a note.
struct SavedAbbreviation: Identifiable, Hashable {
    var abbreviation: String
    var meaning: String
    var id: String { abbreviation }
}

/// The user's own abbreviations ([abbreviation: meaning]) for Fill from a note, kept in UserDefaults on this phone only:
/// never mirrored to iCloud, never sent anywhere, never logged. Only what the user saves is kept, never the note.
@MainActor
@Observable
final class AbbreviationStore {
    static let key = "ps.abbrev.user"
    static let maxKey = 16
    static let maxMeaning = 120

    private(set) var items: [String: String] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded: [String: String] = [:]
        for (k, v) in defaults.dictionary(forKey: Self.key) ?? [:] {
            guard let meaning = v as? String else { continue }
            let a = Self.cleanKey(k), m = Self.cleanMeaning(meaning)
            if !a.isEmpty && !m.isEmpty { loaded[a] = m }
        }
        items = loaded
    }

    var isEmpty: Bool { items.isEmpty }

    /// In alphabetical order, for the list.
    var sorted: [SavedAbbreviation] {
        items.map { SavedAbbreviation(abbreviation: $0.key, meaning: $0.value) }
            .sorted { $0.abbreviation.localizedCaseInsensitiveCompare($1.abbreviation) == .orderedAscending }
    }

    func save(_ abbreviation: String, meaning: String) {
        let a = Self.cleanKey(abbreviation), m = Self.cleanMeaning(meaning)
        guard !a.isEmpty, !m.isEmpty else { return }
        items[a] = m
        persist()
    }

    func remove(_ abbreviation: String) {
        items[abbreviation] = nil
        persist()
    }

    private func persist() {
        if items.isEmpty { defaults.removeObject(forKey: Self.key) } else { defaults.set(items, forKey: Self.key) }
    }

    static func cleanKey(_ s: String) -> String {
        String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxKey))
    }

    static func cleanMeaning(_ s: String) -> String {
        let one = s.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return String(one.prefix(maxMeaning))
    }
}
