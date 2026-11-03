import Foundation

// MARK: - 1.8.3 handoff: which parts are headers and labels (Ben: bold and underlined headers, bold subheaders), and
// which airway lines the handoff carries.

/// Where the headers and labels are in the handoff text, found from the text itself so the builders stay as they are.
/// The plain text is never changed; the screen, the share sheet and the pasteboard style the same ranges.
enum HandoffStyle {
    enum Kind: Equatable { case header, label }
    struct Span: Equatable {
        var kind: Kind
        var range: Range<String.Index>
    }

    /// The longest label before ": ".
    static let maxLabel = 40

    /// A header is a line in all capitals (letters, digits, spaces, &, / and parentheses) that opens the text or
    /// follows a blank line, as every section title does. A label is the text up to and including the first ": " of
    /// any other line, when it starts with a letter and is at most 40 characters; a clock time ("08:20") is never one.
    static func spans(_ text: String) -> [Span] {
        var out: [Span] = []
        var previousBlank = true
        var start = text.startIndex
        while start <= text.endIndex {
            let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[start..<end]
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if !blank {
                if previousBlank, isHeader(line) {
                    out.append(Span(kind: .header, range: start..<end))
                } else if let r = labelRange(line) {
                    out.append(Span(kind: .label, range: r))
                }
            }
            previousBlank = blank
            if end == text.endIndex { break }
            start = text.index(after: end)
        }
        return out
    }

    static func isHeader(_ line: Substring) -> Bool {
        var letters = 0
        for ch in line {
            if ch.isASCII, ch.isLetter {
                guard ch.isUppercase else { return false }
                letters += 1
            } else if !(ch.isASCII && ch.isNumber) && !" &/()".contains(ch) {
                return false
            }
        }
        return letters > 0
    }

    /// The label with its colon ("Cardiovascular:"), or nil.
    static func labelRange(_ line: Substring) -> Range<String.Index>? {
        guard let first = line.first, first.isLetter, let colon = line.range(of: ": ") else { return nil }
        let label = line[line.startIndex..<colon.lowerBound]
        guard !label.isEmpty, label.count <= maxLabel, !hasTime(label), !label.contains("·") else { return nil }
        return line.startIndex..<line.index(after: colon.lowerBound)
    }

    /// "08:20", "0:05": a clock time anywhere in the candidate label.
    private static func hasTime(_ s: Substring) -> Bool {
        let c = Array(s)
        guard c.count >= 4 else { return false }
        for i in 1..<(c.count - 2) where c[i] == ":" && c[i - 1].isNumber && c[i + 1].isNumber && c[i + 2].isNumber { return true }
        return false
    }
}

extension PatientSummary {
    /// The airway the handoff carries: how it is secured now with the support behind it, and the notes. The
    /// preoperative examination (Mallampati, mouth opening, thyromental distance, neck, teeth, the difficult-airway
    /// signs and mask-ventilation predictors) stays on the Preop airway page; the intraoperative course is added by the
    /// handoff itself (1.8.3, Ben).
    static func handoffAirwayLines(_ r: PatientRecord) -> [Line] {
        let keep: Set<String> = ["Current airway", "Ventilator", "Oxygen", "Airway notes", "Examination"]
        return airwayLines(r).filter { keep.contains($0.label ?? "") }
    }
}
