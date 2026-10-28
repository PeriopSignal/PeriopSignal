import Foundation

// MARK: - Pediatric arithmetic
//
// Pure functions behind the pediatric calculator so they can be unit-tested. Drug doses themselves
// come from reference.json (PedsData); this file holds the formulas: weight estimation, airway sizes
// and depths, maintenance fluids, blood volume and allowable blood loss, local-anesthetic maximums.

enum PedsCalc {
    /// APLS weight estimate: (0.5 × months) + 4 under 1 year, (age + 4) × 2 for 1–5 years, (3 × age) + 7 for 6–12 years.
    static func estimatedWeight(years: Int, months: Int) -> Double? {
        let totalMonths = years * 12 + months
        if totalMonths < 1 { return nil }
        if totalMonths < 12 { return 0.5 * Double(totalMonths) + 4 }
        let age = Double(totalMonths) / 12
        if age <= 5 { return (age + 4) * 2 }
        if age <= 12 { return 3 * age + 7 }
        return nil
    }

    /// Endotracheal tube internal diameter (mm): Cole's formula for uncuffed tubes from 2 years, the
    /// Khine modification for cuffed; fixed sizes below that.
    static func ettSizes(years: Int, months: Int) -> (uncuffed: String, cuffed: String) {
        let totalMonths = years * 12 + months
        switch totalMonths {
        case ..<1: return ("3.0–3.5", "3.0")
        case 1..<12: return ("3.5–4.0", "3.0–3.5")
        case 12..<24: return ("4.0–4.5", "3.5–4.0")
        default:
            let age = Double(totalMonths) / 12
            return (half(age / 4 + 4), half(age / 4 + 3.5))
        }
    }

    /// Oral insertion depth at the lip (cm): age/2 + 12 from 2 years; 3 × tube ID below that (≈ 6 + weight for neonates).
    static func ettDepthOral(years: Int, months: Int, uncuffedID: Double?) -> String {
        let totalMonths = years * 12 + months
        if totalMonths >= 24 { return tenth(Double(totalMonths) / 12 / 2 + 12) }
        if let id = uncuffedID { return tenth(id * 3) }
        return "—"
    }

    /// Nasal depth (cm): age/2 + 15 from 2 years.
    static func ettDepthNasal(years: Int, months: Int) -> String {
        let totalMonths = years * 12 + months
        return totalMonths >= 24 ? tenth(Double(totalMonths) / 12 / 2 + 15) : "—"
    }

    /// Laryngeal mask size by weight (manufacturer bands).
    static func lmaSize(weightKg: Double) -> String {
        switch weightKg {
        case ..<5: return "1"
        case 5..<10: return "1.5"
        case 10..<20: return "2"
        case 20..<30: return "2.5"
        case 30..<50: return "3"
        case 50..<70: return "4"
        case 70..<100: return "5"
        default: return "6"
        }
    }

    /// Holliday–Segar maintenance rate, mL/h (4-2-1).
    static func maintenanceMLPerHour(weightKg w: Double) -> Double {
        guard w > 0 else { return 0 }
        return 4 * min(w, 10) + 2 * min(max(w - 10, 0), 10) + 1 * max(w - 20, 0)
    }

    /// Estimated blood volume, mL, from the age-banded mL/kg table.
    static func bloodVolume(weightKg: Double, ageMonths: Double, rows: [BloodVolumeRow]) -> (row: BloodVolumeRow, low: Double, high: Double)? {
        guard let row = rows.first(where: { r in (r.fromMonths ?? -1) <= ageMonths && ageMonths < (r.toMonths ?? .infinity) }) ?? rows.last else { return nil }
        return (row, row.mlPerKgLow * weightKg, row.mlPerKgHigh * weightKg)
    }

    /// Maximum allowable blood loss (Gross 1983): EBV × (Hct₀ − Hct_min) / Hct_average.
    static func mabl(ebv: Double, hctStart: Double, hctMin: Double) -> Double? {
        guard ebv > 0, hctStart > hctMin, hctMin > 0 else { return nil }
        let average = (hctStart + hctMin) / 2
        return ebv * (hctStart - hctMin) / average
    }

    /// Maximum local-anesthetic dose in mg and the equivalent volume at a concentration in percent.
    static func localAnestheticMax(mgPerKg: Double, weightKg: Double, percent: Double) -> (mg: Double, mL: Double) {
        let mg = mgPerKg * weightKg
        return (mg, mg / (percent * 10))
    }

    // MARK: Formatting

    /// "70–75" or a single number when the ends coincide.
    static func range(_ lo: Double, _ hi: Double) -> String { abs(hi - lo) < 0.0001 ? fmt(lo) : fmt(lo) + "–" + fmt(hi) }

    /// Round to the nearest 0.5 (tube sizes).
    static func half(_ v: Double) -> String { fmt((v * 2).rounded() / 2) }
    static func tenth(_ v: Double) -> String { fmt((v * 10).rounded() / 10) }

    /// Clinical rounding: 2 decimals under 1, 1 decimal under 10, whole numbers from 10.
    static func fmt(_ v: Double) -> String {
        let r: Double
        if v < 1 { r = (v * 100).rounded() / 100 }
        else if v < 10 { r = (v * 10).rounded() / 10 }
        else { r = v.rounded() }
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.2f", r)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// "12–18 mg" style range for a per-kg dose at a weight, held within `min` and `max`.
    static func doseText(low: Double, high: Double?, unit: String, weightKg: Double, min: Double? = nil, max: Double?) -> (text: String, capped: Bool) {
        var lo = low * weightKg
        var hi = (high ?? low) * weightKg
        var capped = false
        if let m = min {
            if lo < m { lo = m; capped = true }
            if hi < m { hi = m; capped = true }
        }
        if let m = max {
            if lo > m { lo = m; capped = true }
            if hi > m { hi = m; capped = true }
        }
        if abs(hi - lo) < 0.0001 { return (fmt(lo) + " " + unit, capped) }
        return (fmt(lo) + "–" + fmt(hi) + " " + unit, capped)
    }
}
