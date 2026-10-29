import Foundation

// MARK: - ASE chamber quantification
//
// Sex-specific reference values for chamber size and function (reference.json "echo", transcribed from
// the ASE/EACVI 2015 chamber quantification update and the ASE right-heart guidance). A measurement is
// graded against its cutoffs: where the guideline publishes partitions it reads normal, mildly,
// moderately or severely abnormal; where it gives one cutoff it reads normal or abnormal. The website
// runs the same rules (src/reference-logic.js, R.echo).

enum EchoSex: String, CaseIterable, Identifiable, Hashable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Male" : "Female" }
}

enum EchoCalc {
    /// Body surface area, m²: DuBois & DuBois by default, or Mosteller. Height in cm, weight in kg.
    static func bsa(heightCm: Double?, weightKg: Double?, formula: String?) -> Double? {
        guard let h = heightCm, let w = weightKg, h > 0, w > 0 else { return nil }
        if formula == "mosteller" { return (h * w / 3600).squareRoot() }
        return 0.007184 * pow(h, 0.725) * pow(w, 0.425)
    }

    /// The reference values for this sex: the sex-specific set first, then the shared one.
    static func ref(_ m: EchoMeasure, _ sex: EchoSex) -> EchoRef? {
        (sex == .female ? m.female : m.male) ?? m.all
    }

    /// -1 outside the normal range on the harmless side (a small LV, an LVEF above the range), 0 normal,
    /// 1–3 mildly/moderately/severely abnormal, 4 abnormal where the guideline gives one cutoff.
    static func grade(_ m: EchoMeasure, _ sex: EchoSex, _ v: Double?) -> Int? {
        guard let v, v.isFinite, let r = ref(m, sex) else { return nil }
        let inclusive = m.edge == "inclusive"
        let n: Int
        if m.isLowWorse {
            n = r.cuts.filter { inclusive ? v <= $0 : v < $0 }.count
        } else {
            n = r.cuts.filter { inclusive ? v >= $0 : v > $0 }.count
        }
        if n == 0 {
            if let nr = r.normal, nr.count == 2 {
                if !m.isLowWorse && v < nr[0] { return -1 }
                if m.isLowWorse && v > nr[1] { return -1 }
            }
            return 0
        }
        return r.cuts.count >= 3 ? min(n, 3) : 4
    }

    static func label(_ m: EchoMeasure, _ g: Int) -> String {
        let word = m.word ?? "abnormal"
        switch g {
        case -1: return m.isLowWorse ? "Above the normal range" : "Below the normal range"
        case 0: return "Normal"
        case 1: return "Mildly " + word
        case 2: return "Moderately " + word
        case 3: return "Severely " + word
        default: return word.prefix(1).uppercased() + word.dropFirst()
        }
    }

    /// The value to grade: an indexed row takes the indexed value as typed, or a raw value divided by BSA.
    static func value(_ m: EchoMeasure, text: String, raw: Bool, bsa: Double?) -> Double? {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
        if m.index == "bsa" && raw { return bsa.map { v / $0 } }
        return v
    }

    struct Band: Hashable { var from: Double; var to: Double; var grade: Int }

    /// Bands for the strip under each row, across a padded span around the reference values.
    static func bands(_ m: EchoMeasure, _ sex: EchoSex) -> [Band] {
        guard let r = ref(m, sex) else { return [] }
        let cuts = r.cuts.sorted()
        let lo = r.normal?.first, hi = (r.normal?.count ?? 0) > 1 ? r.normal?[1] : nil
        let all = cuts + [lo, hi].compactMap { $0 }
        guard let mn = all.min(), let mx = all.max() else { return [] }
        let spread = mx - mn
        let pad = (spread > 0 ? spread : max(abs(mx), 1)) * 0.25
        let start = max(0, mn - pad), end = mx + pad
        var out: [Band] = []
        if m.isLowWorse {
            let g = cuts.count >= 3 ? [3, 2, 1] : Array(repeating: 4, count: cuts.count)
            var x = start
            for (i, c) in cuts.enumerated() { out.append(Band(from: x, to: c, grade: g[i])); x = c }
            let top = (hi ?? end) > x ? (hi ?? end) : end
            out.append(Band(from: x, to: top, grade: 0))
            if top < end { out.append(Band(from: top, to: end, grade: -1)) }
        } else {
            var x = start
            if let lo, lo > start { out.append(Band(from: start, to: lo, grade: -1)); x = lo }
            let g = cuts.count >= 3 ? [0, 1, 2, 3] : [0] + Array(repeating: 4, count: cuts.count)
            for (i, c) in cuts.enumerated() { out.append(Band(from: x, to: c, grade: g[i])); x = c }
            out.append(Band(from: x, to: end, grade: g.count > cuts.count ? g[cuts.count] : 4))
        }
        return out.filter { $0.to > $0.from }
    }

    /// Right-atrial pressure from the IVC diameter (cm) and whether it collapses by more than half with a sniff.
    static func rap(ivcCm: Double?, collapses: Bool?, cut: Double?) -> (value: Int, range: String, label: String)? {
        guard let d = ivcCm, d > 0, let collapses else { return nil }
        let c = cut ?? 2.1
        if d <= c && collapses { return (3, "0–5", "Normal") }
        if d > c && !collapses { return (15, "10–20", "High") }
        return (8, "5–10", "Intermediate")
    }
}

extension EchoMeasure {
    /// Lower is worse (LVEF, TAPSE, FAC); otherwise higher is worse (dimensions, volumes, mass).
    var isLowWorse: Bool { dir == "low" }
}
