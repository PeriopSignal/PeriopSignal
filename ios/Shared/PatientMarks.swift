import Foundation

// MARK: - Which text a "mark" may paint (1.12, Ben: "remove the H and L, simple red text is fine to highlight")
//
// A summary line carries `marks`: substrings the screen paints bold red (an abnormal value, an alert phrase). Until 1.12 an
// abnormal lab value was marked with its letter ("K 5.9 H"), which made the mark unmistakable. Without the letter the mark is
// shorter ("K 5.9"), and a plain substring search would also find it inside "K 5.95", inside "Na 135" for the mark "Na 13", and
// inside another item that happens to end in the same label and digits ("fT4 1.2" for "T4 1.2"). So a mark paints only an
// occurrence that stands on its own: the character before it is not a letter or digit, and the character after it is not a
// letter or digit nor the start of more decimals ("K 5.9" beside "5" or ".5"). Every place that paints marks asks here.

enum MarkedText {
    private static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    /// The places in `text` where `mark` stands on its own.
    static func ranges(of mark: String, in text: String) -> [Range<String.Index>] {
        guard !mark.isEmpty, !text.isEmpty else { return [] }
        var out: [Range<String.Index>] = []
        var from = text.startIndex
        while from < text.endIndex, let r = text.range(of: mark, range: from..<text.endIndex) {
            if standsAlone(r, in: text) { out.append(r) }
            // Step one character on, so an overlapping candidate ("K 5.9" in "K K 5.9") is still found.
            from = text.index(after: r.lowerBound)
        }
        return out
    }

    /// The places of any of the marks, in text order, each place once (marks that overlap are merged).
    static func ranges(ofAny marks: [String], in text: String) -> [Range<String.Index>] {
        var all: [Range<String.Index>] = []
        for m in marks { all += ranges(of: m, in: text) }
        all.sort { $0.lowerBound < $1.lowerBound }
        var out: [Range<String.Index>] = []
        for r in all {
            if let last = out.last, r.lowerBound < last.upperBound {
                if r.upperBound > last.upperBound { out[out.count - 1] = last.lowerBound..<r.upperBound }
            } else {
                out.append(r)
            }
        }
        return out
    }

    private static func standsAlone(_ r: Range<String.Index>, in text: String) -> Bool {
        if r.lowerBound > text.startIndex {
            let before = text[text.index(before: r.lowerBound)]
            if isWordChar(before) { return false }
        }
        if r.upperBound < text.endIndex {
            let after = text[r.upperBound]
            if isWordChar(after) { return false }
            // "K 5" beside ".9": the number goes on.
            if after == "." || after == "," {
                let next = text.index(after: r.upperBound)
                if next < text.endIndex, text[next].isNumber { return false }
            }
        }
        return true
    }

    /// `text` with the spaces inside the short marked stretches made non-breaking, so a short value ("Ca 8.3") never breaks
    /// between its name and its number. The text keeps its length and its characters' places, so the ranges stay valid.
    static func keepingTogether(_ text: String, _ ranges: [Range<String.Index>], upTo limit: Int) -> String {
        var chars = Array(text)
        for r in ranges where text.distance(from: r.lowerBound, to: r.upperBound) <= limit {
            let lo = text.distance(from: text.startIndex, to: r.lowerBound)
            let hi = text.distance(from: text.startIndex, to: r.upperBound)
            for i in lo..<hi where chars[i] == " " { chars[i] = "\u{00A0}" }
        }
        return String(chars)
    }
}
