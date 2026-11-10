import Foundation

/// Preprocedure imaging findings, as typed (1.12, Ben: "+ Preprocedure Imaging" under Problems by System: free text for
/// a CT scan, an MRI and other imaging). Shown in a summary only when chosen under "+ Add other input data into
/// Handoff" (`PatientRecord.handoffExtras`: "imaging:ct", "imaging:mri", "imaging:other"). Helper B owns this file.
struct PatientImaging: Codable, Hashable {
    var ct = ""
    var mri = ""
    var other = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ct = (try? c.decodeIfPresent(String.self, forKey: .ct)) ?? ""
        mri = (try? c.decodeIfPresent(String.self, forKey: .mri)) ?? ""
        other = (try? c.decodeIfPresent(String.self, forKey: .other)) ?? ""
    }

    var isEmpty: Bool { [ct, mri, other].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    // MARK: The three items

    /// One of the three lines, in the order the page and the summaries give them.
    enum Item: String, CaseIterable {
        case ct, mri, other

        /// The key kept in `PatientRecord.handoffExtras`: "imaging:ct", "imaging:mri", "imaging:other".
        var extraKey: String { "imaging:" + rawValue }
        /// The name on the page, the chip and the summary line.
        var label: String {
            switch self {
            case .ct: return "CT"
            case .mri: return "MRI"
            case .other: return "Other imaging"
            }
        }
    }

    /// What is in the item's box, exactly as typed (the box shows this).
    func typed(_ item: Item) -> String {
        switch item {
        case .ct: return ct
        case .mri: return mri
        case .other: return other
        }
    }

    /// What was typed for an item, as a summary line reads it: trimmed, and a line break typed in the box reads as a space.
    func text(_ item: Item) -> String {
        typed(item).components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Sets what was typed for an item (as typed: it is trimmed when it is read).
    mutating func set(_ item: Item, _ value: String) {
        switch item {
        case .ct: ct = value
        case .mri: mri = value
        case .other: other = value
        }
    }

    /// The items that hold text, in order.
    var held: [Item] { Item.allCases.filter { !text($0).isEmpty } }

    /// The collapsed link's words: "Imaging: CT · MRI" naming which hold text (the link adds "Change"); nil with none.
    var linkTitle: String? {
        let names = held.map { $0 == .other ? "Other" : $0.label }
        return names.isEmpty ? nil : "Imaging: " + names.joined(separator: " · ")
    }

    /// The summaries' lines ("CT: 4.8 cm ascending aorta") for the items chosen under "+ Add other input data into
    /// Handoff" that hold text, in the page's order whatever order they were chosen in. A key that is not an imaging key,
    /// or whose item holds nothing, adds nothing.
    func chosenLines(_ extras: [String]) -> [String] {
        Item.allCases.compactMap { item -> String? in
            guard extras.contains(item.extraKey) else { return nil }
            let t = text(item)
            return t.isEmpty ? nil : item.label + ": " + t
        }
    }
}
