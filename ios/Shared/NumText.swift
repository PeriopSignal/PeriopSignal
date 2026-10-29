import Foundation

/// Numbers someone typed, shown back without changing them.
///
/// PedsCalc.fmt rounds for dose display (anything from 10 up becomes a whole number), which is right for a computed
/// dose but wrong for a typed value: a field that shows "13" for a stored 12.8 and parses it back would overwrite it.
enum NumText {
    /// The stored value exactly, the way it would be typed: "12.8", "96.5", "162", "1.25".
    static func exact(_ v: Double) -> String {
        guard v.isFinite else { return "" }
        if v == v.rounded(), Swift.abs(v) < 1e15 { return String(Int(v)) }
        let s = "\(v)"
        return s.contains("e") ? trimmed(String(format: "%.6f", v)) : s
    }

    /// For reading: at most `places` decimals, trailing zeros dropped ("12.8", "1.25", "34.45", "162").
    static func short(_ v: Double, places: Int = 2) -> String {
        guard v.isFinite else { return "" }
        let p = pow(10.0, Double(max(0, places)))
        let r = (v * p).rounded() / p
        if r == r.rounded(), Swift.abs(r) < 1e15 { return String(Int(r)) }
        return trimmed(String(format: "%.\(max(0, places))f", r))
    }

    private static func trimmed(_ s: String) -> String {
        var s = s
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
