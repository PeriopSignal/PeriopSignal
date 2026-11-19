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

    // MARK: The typed weight

    /// Ben, Nov 19 (after the GPT-6 review): a typed weight that cannot be a child's gets no dose, size or volume worked out
    /// from it, only "Check the weight". The limits are 0.4 kg and 150 kg, and, when an age is entered, 3 times and one third
    /// of the app's own age-based estimate (`estimatedWeight`).
    static let weightMinKg = 0.4
    static let weightMaxKg = 150.0
    static let weightAgeRatio = 3.0
    /// The line when the age is the reason (the weight is far from the estimate for the age, or over the maximum with an age entered).
    static let checkWeightAgeText = "Check the weight against the age"

    /// What the pediatric screen makes of the weight field: the weight to use (nil when none was typed or it is implausible)
    /// and, for an implausible one, the line to show.
    struct WeightVerdict: Equatable {
        var weightKg: Double?
        var message: String?
    }

    /// The text of the weight field as a number: nil for an empty or unreadable field. Unlike WeightField.value it keeps
    /// 0, a negative number and "inf", so the check can name them.
    static func typedWeight(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return t.isEmpty ? nil : Double(t)
    }

    /// Pure rule behind "Check the weight". Implausible: not finite, 0 or less, under 0.4 kg; over 150 kg; and, when the age
    /// has an estimate (1 month to 12 years), more than 3 times or less than one third of it. Over 150 kg and the age ratio
    /// read "Check the weight against the age" when an age is entered; the rest read "Check the weight".
    static func verdict(weightKg: Double?, years: Int, months: Int) -> WeightVerdict {
        guard let w = weightKg else { return WeightVerdict(weightKg: nil, message: nil) }
        let ageEntered = years * 12 + months >= 1
        guard w.isFinite, w >= weightMinKg else { return WeightVerdict(weightKg: nil, message: checkWeightText) }
        if w > weightMaxKg {
            return WeightVerdict(weightKg: nil, message: ageEntered ? checkWeightAgeText : checkWeightText)
        }
        if let e = estimatedWeight(years: years, months: months), w > weightAgeRatio * e || w < e / weightAgeRatio {
            return WeightVerdict(weightKg: nil, message: checkWeightAgeText)
        }
        return WeightVerdict(weightKg: w, message: nil)
    }

    /// The same from the field's text.
    static func verdict(text: String, years: Int, months: Int) -> WeightVerdict {
        verdict(weightKg: typedWeight(text), years: years, months: months)
    }

    /// Under 3 kg the tube size and depth shown are worked out from age only (Ben, Nov 19): one caution line beside them.
    static let newbornAirwayCaution = "Under 3 kg: choose tube size and depth by weight from your neonatal chart; the values shown are by age."
    static func newbornAirwayNote(weightKg: Double?) -> String? {
        guard let w = weightKg, w.isFinite, w < 3 else { return nil }
        return newbornAirwayCaution
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

    /// The largest number any line shows. Past it (or for a value that is not a number) no whole number can be
    /// written safely: String(Int(r)) traps on an infinite, NaN or enormous Double, which a pasted 20-digit weight reaches.
    static let shownLimit = 1e9
    /// What fmt writes for a number it cannot show.
    static let unreadable = "—"
    /// The words beside a dose or an amount that could not be worked out from the weight.
    static let checkWeightText = "Check the weight"

    /// True when a number can be shown (finite and under `shownLimit`). Same idea as AclsCalc.whole.
    static func shows(_ v: Double) -> Bool { v.isFinite && Swift.abs(v) < shownLimit }

    /// Clinical rounding: 2 decimals under 1, 1 decimal under 10, whole numbers from 10. A number that cannot be
    /// shown reads "—" (Ben, Nov 19, after the GPT-6 review: an absurd weight must never crash the app).
    static func fmt(_ v: Double) -> String {
        guard shows(v) else { return unreadable }
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
        // An absurd weight must not reach a dose, not even one held at its maximum.
        guard shows(weightKg) else { return (checkWeightText, false) }
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
        guard shows(lo), shows(hi) else { return (checkWeightText, false) }
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
        // The weight-based line, only when the weight and every number worked out from it can be shown. Otherwise
        // "Check the weight" (Ben, Nov 19, after the GPT-6 review: an absurd weight must never crash the app).
        func at(_ w: Double, _ numbers: [Double?], _ text: () -> String) -> String {
            guard PedsCalc.shows(w), numbers.allSatisfy({ n in n.map { PedsCalc.shows($0) } ?? true }) else { return PedsCalc.checkWeightText }
            return text() + " at \(PedsCalc.fmt(w)) kg"
        }
        switch d.form {
        case .perKgPerMin:
            let dose = span(start, d.startHigh, unit + "/kg/min")
            guard let w = weightKg, w > 0 else { return (dose, nil) }
            return (dose, at(w, [start * w, d.startHigh.map { $0 * w }]) {
                let s = scaled(start * w, d.startHigh.map { $0 * w }, unit)
                return span(s.lo, s.hi, s.unit + "/min")
            })
        case .perMin:
            let dose = span(start, d.startHigh, unit + "/min")
            guard let w = weightKg, w > 0 else { return (dose, nil) }
            return (dose, at(w, [start / w, d.startHigh.map { $0 / w }]) {
                span(start / w, d.startHigh.map { $0 / w }, unit + "/kg/min")
            })
        case .perKg:
            let dose = span(start, d.startHigh, unit + "/kg")
            guard let w = weightKg, w > 0 else { return (dose, nil) }
            return (dose, at(w, [start * w, d.startHigh.map { $0 * w }]) {
                total(start * w, d.startHigh.map { $0 * w }, unit)
            })
        case .perKgPerHour:
            let dose = span(start, d.startHigh, unit + "/kg/h")
            guard let w = weightKg, w > 0 else { return (dose, nil) }
            return (dose, at(w, [start * w, d.startHigh.map { $0 * w }]) {
                let s = scaled(start * w, d.startHigh.map { $0 * w }, unit)
                return span(s.lo, s.hi, s.unit + "/h")
            })
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

/// What has been picked so far on "Blocks on anticoagulants", and what is still missing.
///
/// Ben, Nov 19 (after the GPT-6 review): the tool must not show a time the user did not choose. The first dose tier is the
/// shortest interval for the heparins and the longest for the DOACs, and the first kidney row is the best kidney function,
/// so a user who skipped a step could be shown the shortest interval. A drug with more than one dose tier starts with no tier
/// chosen, a tier with kidney rows starts with no kidney row chosen, and until each needed choice is made there is no answer.
/// A drug with a single tier and no kidney rows needs no choice and answers at once, as before.
struct NeuraxialSelection: Equatable {
    var drugID: String?
    var tierID: String?
    var renalIndex: Int?
    var elderly = false

    /// The next thing the user has to choose; `ready` when the answer can be shown.
    enum Stage: Equatable { case chooseDrug, chooseDose, chooseKidney, ready }

    /// Changing the drug clears the tier, the kidney row and the "Elderly patient" toggle. A drug with one tier has that tier
    /// chosen for it (there is nothing to choose).
    mutating func selectDrug(_ drug: NeuraxialDrug) {
        drugID = drug.id
        tierID = drug.tiers.count == 1 ? drug.tiers.first?.id : nil
        renalIndex = nil
        elderly = false
    }

    /// A different dose tier has its own kidney rows, so the kidney row is cleared.
    mutating func selectTier(_ tier: NeuraxialTier) {
        tierID = tier.id
        renalIndex = nil
    }

    mutating func selectRenal(_ index: Int) { renalIndex = index }

    /// The chosen tier; nil until one is chosen (a single-tier drug counts as chosen).
    func tier(in drug: NeuraxialDrug?) -> NeuraxialTier? {
        guard let drug else { return nil }
        if let id = tierID { return drug.tiers.first { $0.id == id } }
        return drug.tiers.count == 1 ? drug.tiers.first : nil
    }

    func stage(drug: NeuraxialDrug?) -> Stage {
        guard let drug else { return .chooseDrug }
        guard let t = tier(in: drug) else { return .chooseDose }
        if let rules = t.renal, !rules.isEmpty {
            guard let i = renalIndex, rules.indices.contains(i) else { return .chooseKidney }
        }
        return .ready
    }

    /// The answer, or nil while a choice is still missing.
    func answer(drug: NeuraxialDrug?, lastDose: Date) -> NeuraxialCalc.Answer? {
        guard stage(drug: drug) == .ready, let t = tier(in: drug) else { return nil }
        return NeuraxialCalc.answer(tier: t, renalIndex: renalIndex, elderly: elderly, lastDose: lastDose)
    }

    /// What the result card says in place of a time while a choice is missing; nil when nothing is missing or no drug is chosen.
    static func prompt(for stage: Stage) -> String? {
        switch stage {
        case .chooseDose: return "Choose the dose"
        case .chooseKidney: return "Choose kidney function"
        case .chooseDrug, .ready: return nil
        }
    }
}

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
                rule = "\(fmtHours(hours!)) after the last dose (\(softLowercased(r.label))\(elderly && r.elderlyHours != nil ? ", elderly" : ""))"
            } else {
                hours = nil; avoid = true
                rule = r.text ?? "Avoid the block"
            }
        } else if let h = hours {
            if rule.isEmpty { rule = "\(fmtHours(h)) after the last dose" }
            if h == 0 { rule = tier.holdText ?? "No hold required" }
        } else {
            // Ben, Nov 19 (after the GPT-6 review): the "avoid" answer must not hang on one word in the sentence.
            // The tier's own `avoid` flag wins when the data carries it; older data (no flag) falls back to the
            // word "against" in the hold text ("ASRA suggests against ...").
            avoid = tier.avoid ?? (tier.holdText?.lowercased().contains("against") ?? false)
            if rule.isEmpty { rule = "No interval specified" }
        }
        let earliest = hours.map { lastDose.addingTimeInterval($0 * 3600) }
        return Answer(earliest: earliest, hours: hours, rule: rule, avoid: avoid)
    }

    /// "Normal renal function" → "normal renal function"; "CrCl 30–49 mL/min" stays as written.
    static func softLowercased(_ s: String) -> String {
        let first = s.split(separator: " ").first.map(String.init) ?? s
        if first.dropFirst().contains(where: { $0.isUppercase }) { return s }
        return s.prefix(1).lowercased() + s.dropFirst()
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
