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

    /// Maximum allowable blood loss: EBV × (Hct₀ − Hct_min) / Hct₀ (the starting-hematocrit form, more
    /// conservative than Gross's mean-hematocrit denominator).
    static func mabl(ebv: Double, hctStart: Double, hctMin: Double) -> Double? {
        guard ebv > 0, hctStart > hctMin, hctMin > 0 else { return nil }
        return ebv * (hctStart - hctMin) / hctStart
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

// MARK: - Infusion arithmetic

enum InfusionCalc {
    /// The starting dose as written ("0.05–0.1 mcg/kg/min") and, for a weight, its equivalent in the other
    /// form ("3.5–7 mcg/min at 70 kg"); weight-based boluses become totals.
    static func lines(for d: InfusionDrug, weightKg: Double?) -> (dose: String, equivalent: String?) {
        guard let start = d.start else { return (d.range ?? "see notes", nil) }
        let unit = d.unit ?? "mcg"
        func span(_ lo: Double, _ hi: Double?, _ u: String) -> String {
            if let hi, abs(hi - lo) > 0.0001 { return "\(PedsCalc.fmt(lo))–\(PedsCalc.fmt(hi)) \(u)" }
            return "\(PedsCalc.fmt(lo)) \(u)"
        }
        switch d.form {
        case .perKgPerMin:
            let dose = span(start, d.startHigh, unit + "/kg/min")
            guard let w = weightKg, w > 0 else { return (dose, nil) }
            let s = scaled(start * w, d.startHigh.map { $0 * w }, unit)
            return (dose, span(s.lo, s.hi, s.unit + "/min") + " at \(PedsCalc.fmt(w)) kg")
        case .perMin:
            let dose = span(start, d.startHigh, unit + "/min")
            guard let w = weightKg, w > 0 else { return (dose, nil) }
            return (dose, span(start / w, d.startHigh.map { $0 / w }, unit + "/kg/min") + " at \(PedsCalc.fmt(w)) kg")
        case .perKg:
            let dose = span(start, d.startHigh, unit + "/kg")
            guard let w = weightKg, w > 0 else { return (dose, nil) }
            return (dose, total(start * w, d.startHigh.map { $0 * w }, unit) + " at \(PedsCalc.fmt(w)) kg")
        case .perKgPerHour:
            let dose = span(start, d.startHigh, unit + "/kg/h")
            guard let w = weightKg, w > 0 else { return (dose, nil) }
            let s = scaled(start * w, d.startHigh.map { $0 * w }, unit)
            return (dose, span(s.lo, s.hi, s.unit + "/h") + " at \(PedsCalc.fmt(w)) kg")
        case .perHour:
            return (span(start, d.startHigh, unit + "/h"), nil)
        case .fixed:
            return (span(start, d.startHigh, unit), nil)
        case .text:
            return (d.range ?? "see notes", nil)
        }
    }

    /// ng above 1,000 read better as mcg, mcg above 1,000 as mg, mg above 1,000 as g (both ends of a range move together).
    static func scaled(_ lo: Double, _ hi: Double?, _ unit: String) -> (lo: Double, hi: Double?, unit: String) {
        var l = lo, h = hi, u = unit
        if u == "ng", l >= 1000, (h ?? l) >= 1000 { l /= 1000; h = h.map { $0 / 1000 }; u = "mcg" }
        if u == "mcg", l >= 1000, (h ?? l) >= 1000 { l /= 1000; h = h.map { $0 / 1000 }; u = "mg" }
        if u == "mg", l >= 1000, (h ?? l) >= 1000 { l /= 1000; h = h.map { $0 / 1000 }; u = "g" }
        return (l, h, u)
    }

    static func total(_ lo: Double, _ hi: Double?, _ unit: String) -> String {
        let s = scaled(lo, hi, unit)
        if let h = s.hi, abs(h - s.lo) > 0.0001 { return "\(PedsCalc.fmt(s.lo))–\(PedsCalc.fmt(h)) \(s.unit)" }
        return "\(PedsCalc.fmt(s.lo)) \(s.unit)"
    }
}

// MARK: - Neuraxial timing arithmetic

enum NeuraxialCalc {
    struct Answer: Hashable {
        /// Earliest time for the block; nil when it is to be avoided or no interval applies.
        var earliest: Date?
        var hours: Double?
        /// What the interval is, in words ("72 h after the last dose", "Avoid …").
        var rule: String
        var avoid: Bool
    }

    static func answer(tier: NeuraxialTier, renalIndex: Int?, elderly: Bool, lastDose: Date) -> Answer {
        var hours = tier.holdHours
        var rule = tier.holdText ?? ""
        var avoid = false
        if let renal = tier.renal, !renal.isEmpty {
            let r = renal[min(max(renalIndex ?? 0, 0), renal.count - 1)]
            if let h = r.hours {
                hours = (elderly ? r.elderlyHours : nil) ?? h
                rule = "\(fmtHours(hours!)) after the last dose (\(r.label.lowercased())\(elderly && r.elderlyHours != nil ? ", elderly" : ""))"
            } else {
                hours = nil; avoid = true
                rule = r.text ?? "Avoid the block"
            }
        } else if let h = hours {
            if rule.isEmpty { rule = "\(fmtHours(h)) after the last dose" }
            if h == 0 { rule = tier.holdText ?? "No hold required" }
        } else {
            avoid = tier.holdText?.lowercased().contains("against") ?? false
            if rule.isEmpty { rule = "No interval specified" }
        }
        let earliest = hours.map { lastDose.addingTimeInterval($0 * 3600) }
        return Answer(earliest: earliest, hours: hours, rule: rule, avoid: avoid)
    }

    static func fmtHours(_ h: Double) -> String {
        if h >= 48, h.truncatingRemainder(dividingBy: 24) == 0 { return "\(Int(h / 24)) days" }
        return h == h.rounded() ? "\(Int(h)) h" : String(format: "%.1f h", h)
    }

    /// "in 41 h", "in 3 days 5 h", or "now" when the time has passed.
    static func countdown(to date: Date, from now: Date = Date()) -> String {
        let secs = date.timeIntervalSince(now)
        if secs <= 0 { return "now" }
        let totalMinutes = Int(secs / 60)
        let days = totalMinutes / 1440, hours = (totalMinutes % 1440) / 60, minutes = totalMinutes % 60
        if days > 0 { return "in \(days) d \(hours) h" }
        if hours > 0 { return "in \(hours) h \(minutes) min" }
        return "in \(minutes) min"
    }
}
