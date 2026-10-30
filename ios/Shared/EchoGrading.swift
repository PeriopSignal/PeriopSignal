import Foundation

// MARK: - ASE chamber quantification
//
// Reference values for chamber size and function (reference.json "echo"): Lang 2015 (ASE/EACVI chamber
// quantification) for the LV and LA, the ASE 2025 right-heart guideline for the RV and RA, ASE 2017 for the
// tricuspid annulus and the ASE/EACVI 2015 aorta guideline for the aortic sinuses. A measurement is graded
// against its cutoffs: where the guideline publishes partitions it reads normal, mildly, moderately or
// severely abnormal; where it gives one cutoff it reads normal or abnormal. The website runs the same rules
// (src/reference-logic.js, R.echo) and the unit tests mirror each other.

enum EchoSex: String, CaseIterable, Identifiable, Hashable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Male" : "Female" }
}

enum EchoCalc {
    /// What a row may need beyond the sex: age and BSA for the aortic sinuses.
    struct Context: Hashable {
        var age: Double?
        var bsa: Double?
    }

    /// Body surface area, m²: DuBois & DuBois by default, or Mosteller. Height in cm, weight in kg.
    static func bsa(heightCm: Double?, weightKg: Double?, formula: String?) -> Double? {
        guard let h = heightCm, let w = weightKg, h > 0, w > 0 else { return nil }
        if formula == "mosteller" { return (h * w / 3600).squareRoot() }
        return 0.007184 * pow(h, 0.725) * pow(w, 0.425)
    }

    /// A reference value as printed (58.4, 0.42), or a computed one to two decimals below 100 and one above.
    static func fmt(_ v: Double) -> String {
        let p: Double = Swift.abs(v) < 100 ? 100 : 10
        let r = (v * p).rounded() / p
        var s = String(format: p == 100 ? "%.2f" : "%.1f", r)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// The reference values for this sex and patient: the sex-specific set first, then the shared one. An
    /// age-table row builds its single cutoff from age, sex and BSA.
    static func ref(_ m: EchoMeasure, _ sex: EchoSex, _ ctx: Context? = nil) -> EchoRef? {
        if m.byAge != nil {
            guard let lim = ageLimit(m, sex, ctx) else { return nil }
            return EchoRef(normal: nil, cuts: [lim.value])
        }
        return (sex == .female ? m.female : m.male) ?? m.all
    }

    struct AgeLimit: Hashable {
        var value: Double
        /// The table's limit at the reference BSA.
        var base: Double
        var row: EchoAgeRow
        var refBsa: Double
        var adjusted: Bool
    }

    /// Goldstein 2015 Tables 1–2: the age band's upper limit at the reference BSA, moved 0.5 mm per 0.1 m².
    static func ageLimit(_ m: EchoMeasure, _ sex: EchoSex, _ ctx: Context?) -> AgeLimit? {
        guard let by = m.byAge, let age = ctx?.age, age > 0 else { return nil }
        let t = sex == .female ? by.female : by.male
        let a = Int(age.rounded(.down))
        guard let row = t.rows.first(where: { a >= $0.from && ($0.to.map { a <= $0 } ?? true) }) else { return nil }
        let bsa = (ctx?.bsa ?? 0) > 0 ? ctx?.bsa : nil
        let value = bsa.map { row.uln + ($0 - t.refBsa) * by.perM2 } ?? row.uln
        return AgeLimit(value: (value * 1000).rounded() / 1000, base: row.uln, row: row, refBsa: t.refBsa, adjusted: bsa != nil)
    }

    /// Whether the cut value itself belongs to the worse grade (per-cut edges, else the row's edge).
    static func inclusive(_ m: EchoMeasure, _ i: Int) -> Bool {
        if let e = m.edges { return i < e.count && e[i] == "inclusive" }
        return m.edge == "inclusive"
    }

    /// -1 outside the normal range on the harmless side (a small LV, an LVEF above the range), 0 normal,
    /// 1–3 mildly/moderately/severely abnormal, 4 abnormal where the guideline gives one cutoff.
    static func grade(_ m: EchoMeasure, _ sex: EchoSex, _ v: Double?, _ ctx: Context? = nil) -> Int? {
        guard let v, v.isFinite, let r = ref(m, sex, ctx) else { return nil }
        var n = 0
        for (i, c) in r.cuts.enumerated() {
            let inc = inclusive(m, i)
            if m.isLowWorse ? (inc ? v <= c : v < c) : (inc ? v >= c : v > c) { n += 1 }
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

    struct Range: Hashable {
        var grade: Int
        var text: String
    }

    /// The cutoffs in words, each grade by the limit on its better side: "Normal < 4.1", "mild ≤ 4.4",
    /// "moderate ≤ 4.9", "severe > 4.9"; a single cutoff reads "Normal 42–58.4", "dilated > 58.4".
    static func ranges(_ m: EchoMeasure, _ sex: EchoSex, _ ctx: Context? = nil) -> [Range] {
        guard let r = ref(m, sex, ctx) else { return [] }
        let c = r.cuts, low = m.isLowWorse
        func better(_ i: Int) -> String { (low ? (inclusive(m, i) ? "> " : "≥ ") : (inclusive(m, i) ? "< " : "≤ ")) + fmt(c[i]) }
        func worse(_ i: Int) -> String { (low ? (inclusive(m, i) ? "≤ " : "< ") : (inclusive(m, i) ? "≥ " : "> ")) + fmt(c[i]) }
        let normal: String
        if let n = r.normal, n.count == 2 { normal = fmt(n[0]) + "–" + fmt(n[1]) }
        else if !c.isEmpty { normal = better(0) }
        else { return [] }
        var out = [Range(grade: 0, text: "Normal " + normal)]
        if c.count >= 3 {
            out += [Range(grade: 1, text: "mild " + better(1)), Range(grade: 2, text: "moderate " + better(2)), Range(grade: 3, text: "severe " + worse(2))]
        } else if !c.isEmpty {
            out.append(Range(grade: 4, text: (m.word ?? "abnormal") + " " + worse(0)))
        }
        return out
    }

    /// The row's BSA-indexed cutoffs as a row of their own (direction and words from the parent).
    static func indexed(_ m: EchoMeasure) -> EchoMeasure? {
        guard let x = m.indexed else { return nil }
        var o = m
        o.id = m.id + "-indexed"
        o.unit = x.unit
        o.edge = x.edge
        o.edges = x.edges
        o.male = x.male
        o.female = x.female
        o.all = x.all
        o.index = nil
        o.rawUnit = nil
        o.indexed = nil
        o.byAge = nil
        return o
    }

    /// The value to grade: an indexed row takes the indexed value as typed, or a raw value divided by BSA.
    /// Rows marked abs (strain) read a negative entry as its magnitude.
    static func value(_ m: EchoMeasure, text: String, raw: Bool, bsa: Double?) -> Double? {
        guard var v = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) else { return nil }
        if v < 0, m.abs == true { v = -v }
        guard v > 0, v.isFinite else { return nil }
        if m.index == "bsa" && raw { return bsa.map { v / $0 } }
        return v
    }

    struct Band: Hashable { var from: Double; var to: Double; var grade: Int }

    /// Bands for the strip under each row, across a padded span around the reference values. Without a
    /// published normal range the normal band is drawn as wide as the abnormal ones together.
    static func bands(_ m: EchoMeasure, _ sex: EchoSex, _ ctx: Context? = nil) -> [Band] {
        guard let r = ref(m, sex, ctx) else { return [] }
        let cuts = r.cuts.sorted()
        let lo = r.normal?.first, hi = (r.normal?.count ?? 0) > 1 ? r.normal?[1] : nil
        let all = cuts + [lo, hi].compactMap { $0 }
        guard let mn = all.min(), let mx = all.max() else { return [] }
        let spread = mx - mn
        let pad = (spread > 0 ? spread : (mx != 0 ? Swift.abs(mx) : 1)) * 0.25
        let ext = r.normal != nil ? pad : max(pad, spread)
        let start = max(0, mn - (m.isLowWorse ? pad : ext)), end = mx + (m.isLowWorse ? ext : pad)
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

    struct RAP: Hashable {
        /// mmHg; nil when the reading is a statement rather than a number (ventilated patients).
        var value: Int?
        var range: String?
        var label: String
        var detail: String?
    }

    /// Right-atrial pressure from the IVC diameter (cm): with spontaneous breathing, whether it collapses by
    /// 50% or more with a sniff (ASE 2025); on positive-pressure ventilation only a small IVC says anything. The
    /// ventilated cutoff is 1.2 cm (ASE 2010): the 2025 text prints 2.1 cm for the same statement.
    static func rap(ivcCm: Double?, collapses: Bool?, cut: Double?, ventilated: Bool = false, ventCut: Double? = nil) -> RAP? {
        guard let d = ivcCm, d > 0 else { return nil }
        let c = cut ?? 2.1, vc = ventCut ?? 1.2
        if ventilated {
            return d <= vc
                ? RAP(value: nil, range: "below 10", label: "Likely below 10 mmHg", detail: "An IVC of \(fmt(vc)) cm or less in an intubated patient identifies RA pressure below 10 mmHg.")
                : RAP(value: nil, range: nil, label: "Not estimable", detail: "On positive-pressure ventilation a larger IVC, and its collapse, do not estimate RA pressure.")
        }
        guard let collapses else { return nil }
        if d <= c && collapses { return RAP(value: 3, range: "0–5", label: "Normal", detail: nil) }
        if d > c && !collapses { return RAP(value: 15, range: "10–20", label: "Elevated", detail: nil) }
        return RAP(value: 8, range: "5–10", label: "Indeterminate", detail: "A normal-size IVC that does not collapse, or a dilated one that does: lower to 3 mmHg without secondary signs of raised RA pressure, raise to 15 with them.")
    }
}

extension EchoCalc {
    struct Coupling: Hashable {
        /// mm/mmHg, at two decimals as shown.
        var ratio: Double
        /// 0 not uncoupled, 4 in or below the uncoupling range, nil between the two ranges.
        var grade: Int?
        var label: String
        var detail: String
    }

    /// TAPSE/PASP, mm/mmHg: the noninvasive index of RV–PA coupling (ASE 2025). Healthy adults generally run
    /// 0.5–0.7; 0.3–0.4 is associated with uncoupling and increased mortality. TAPSE in cm, PASP in mmHg; the
    /// ratio is read at two decimals, as shown. The website runs the same rule (R.echo.coupling).
    static func coupling(tapseCm: Double?, pasp: Double?, _ c: EchoCoupling?) -> Coupling? {
        guard let t = tapseCm, t > 0, let p = pasp, p > 0 else { return nil }
        let h = c?.healthy ?? [0.5, 0.7], u = c?.uncoupled ?? [0.3, 0.4]
        let hLo = h.first ?? 0.5, hHi = h.last ?? 0.7, uLo = u.first ?? 0.3, uHi = u.last ?? 0.4
        let ratio = (t * 10 / p * 100).rounded() / 100
        let healthy = fmt(hLo) + "–" + fmt(hHi), unc = fmt(uLo) + "–" + fmt(uHi)
        if ratio > hHi {
            return Coupling(ratio: ratio, grade: 0, label: "Above the usual healthy range", detail: "Healthy adults generally run \(healthy) mm/mmHg; a higher ratio does not suggest uncoupling.")
        }
        if ratio >= hLo {
            return Coupling(ratio: ratio, grade: 0, label: "In the healthy range", detail: "Healthy adults generally run \(healthy) mm/mmHg.")
        }
        if ratio > uHi {
            return Coupling(ratio: ratio, grade: nil, label: "Below the healthy range", detail: "Between the healthy range (\(healthy)) and the range associated with uncoupling (\(unc) mm/mmHg).")
        }
        if ratio >= uLo {
            return Coupling(ratio: ratio, grade: 4, label: "In the uncoupling range", detail: "\(unc) mm/mmHg is associated with RV–PA uncoupling and increased mortality.")
        }
        return Coupling(ratio: ratio, grade: 4, label: "Below the uncoupling range", detail: "Lower than \(unc) mm/mmHg, the range associated with RV–PA uncoupling and increased mortality.")
    }
}

extension EchoMeasure {
    /// Lower is worse (LVEF, TAPSE, FAC); otherwise higher is worse (dimensions, volumes, mass).
    var isLowWorse: Bool { dir == "low" }
}
