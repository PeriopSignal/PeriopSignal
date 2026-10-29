import Foundation

extension String {
    /// Headline-style Title Case for headers, tool names and checklist titles: every word starts with a
    /// capital except short connecting words in the middle; acronyms, units and anything already
    /// capitalized stay as written ("Blocks on anticoagulants" → "Blocks on Anticoagulants",
    /// "Doses in mg/kg" stays, "pH" stays, "Low-gradient" → "Low-Gradient", "Non-cardiac" stays).
    var titleCased: String {
        let words = self.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var startOfClause = true
        for (i, word) in words.enumerated() {
            let isLast = i == words.count - 1
            out.append(TitleCase.capitalize(word, force: startOfClause || isLast))
            let trimmed = word.trimmingCharacters(in: .whitespaces)
            startOfClause = trimmed.hasSuffix(":") || trimmed.hasSuffix("—") || trimmed == "—" || trimmed == "–"
        }
        return out.joined(separator: " ")
    }
}

enum TitleCase {
    /// Connecting words kept lower case unless they open or close the title or follow a colon.
    static let small: Set<String> = ["a", "an", "and", "as", "at", "but", "by", "for", "from", "if", "in", "into", "nor", "of",
                                     "off", "on", "or", "per", "than", "the", "to", "up", "vs", "vs.", "via", "with"]
    /// Words whose case is meaningful as written.
    static let keep: Set<String> = ["mg", "mcg", "kg", "g", "ng", "ml", "mL", "dL", "dl", "h", "min", "ppm", "mmHg", "cm", "mm",
                                    "pH", "iNO", "iEPO", "eGFR", "e.g.", "i.e.", "et", "al", "x"]

    /// Prefixes whose hyphenated partner stays lower case ("Non-cardiac", "Anti-inflammatory").
    static let prefixes: Set<String> = ["non", "anti", "pre", "post", "re", "co", "sub", "semi", "multi", "inter", "intra", "peri", "self"]

    static func capitalize(_ word: String, force: Bool) -> String {
        let parts = word.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return capitalizePart(word, force: force) }
        var out: [String] = []
        for (i, part) in parts.enumerated() {
            if i == 0 {
                out.append(capitalizePart(part, force: force))
            } else {
                let previous = parts[i - 1].lowercased().filter(\.isLetter)
                out.append(prefixes.contains(previous) ? part : capitalizePart(part, force: false))
            }
        }
        return out.joined(separator: "-")
    }

    static func capitalizePart(_ word: String, force: Bool) -> String {
        guard let firstLetter = word.firstIndex(where: { $0.isLetter }) else { return word }
        let lead = word[..<firstLetter]
        let core = String(word[firstLetter...])
        let bare = core.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]”\"’'"))
        // Units, numbers and abbreviations with inner dots are left alone.
        if keep.contains(bare) || bare.contains(where: { $0.isNumber }) { return word }
        if let slash = bare.firstIndex(of: "/"), keep.contains(String(bare[..<slash])) { return word }
        if bare.dropLast().contains(".") { return word }
        if !force && small.contains(bare.lowercased()) && bare == bare.lowercased() { return word }
        guard let c = core.first, c.isLowercase else { return word }
        return String(lead) + c.uppercased() + core.dropFirst()
    }
}
