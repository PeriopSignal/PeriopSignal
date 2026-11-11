import SwiftUI

// MARK: - Painting marks (1.12)
//
// A summary line's `marks` are the stretches shown in bold red (an abnormal lab value, an alert phrase). Since 1.12 an abnormal
// lab value has no H or L after it, so a mark is short ("K 5.9") and is painted only where it stands alone (MarkedText): never
// inside "K 5.95", "Na 135" for the mark "Na 13", or another item's name that ends the same way. Every painter of marks in the
// app goes through here.

extension AttributedString {
    /// Paints each place of the marks in `text` (the string this value was made from) in PS.red with `font`.
    mutating func paintMarks(_ marks: [String], in text: String, font: Font) {
        for r in MarkedText.ranges(ofAny: marks, in: text) {
            let lo = index(startIndex, offsetByCharacters: text.distance(from: text.startIndex, to: r.lowerBound))
            let hi = index(lo, offsetByCharacters: text.distance(from: r.lowerBound, to: r.upperBound))
            self[lo..<hi].foregroundColor = PS.red
            self[lo..<hi].font = font
        }
    }
}

/// `text` with its marks in bold red, at `size`.
func markedString(_ text: String, marks: [String], size: CGFloat) -> AttributedString {
    var a = AttributedString(text)
    a.paintMarks(marks, in: text, font: PS.sys(size: size, weight: .bold))
    return a
}
