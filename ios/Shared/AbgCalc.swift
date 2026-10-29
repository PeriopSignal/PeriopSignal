import Foundation

// MARK: - ABG: acid–base and compensation
//
// pH, PaCO2 (mmHg) and HCO3 (mEq/L) in: the primary disorder, whether the compensation is what the rule expects,
// and the second disorder when it is not. Each rule is a straight line read from reference.json ("abg"),
// expected = slope × x + intercept ± tol, so a review can change a coefficient without touching code. Any two of
// the three values are enough: the third comes from Henderson–Hasselbalch. The website runs the same rules
// (src/reference-logic.js, R.abg); the unit tests mirror each other.

enum AbgCalc {
    enum Disorder: String, Hashable {
        case metAcid, metAlk, respAcid, respAlk
        var name: String {
            switch self {
            case .metAcid: return "metabolic acidosis"
            case .metAlk: return "metabolic alkalosis"
            case .respAcid: return "respiratory acidosis"
            case .respAlk: return "respiratory alkalosis"
            }
        }
        var isRespiratory: Bool { self == .respAcid || self == .respAlk }
    }

    enum Phase: Hashable { case acute, chronic, either, between }
    enum Tone: Hashable { case ok, bad, info }
    enum Derived: Hashable { case ph, paco2, hco3 }

    struct Step: Hashable, Identifiable {
        var id: String
        var label: String
        var tone: Tone
        var text: String
    }

    struct Band: Hashable, Identifiable {
        var id: String
        var label: String
        var lo: Double
        var hi: Double
    }

    /// The measured value against the band(s) the rule expects: PaCO2 for a metabolic disorder, HCO3 (acute and
    /// chronic) for a respiratory one.
    struct Visual: Hashable {
        var variable: String
        var unit: String
        var measured: Double
        var bands: [Band]
    }

    struct Check: Hashable {
        var calc: Double
        var diff: Double
        var ok: Bool
    }

    struct Values: Hashable {
        var ph: Double?
        var paco2: Double?
        var hco3: Double?
    }

    struct Reading: Hashable {
        var empty: Bool
        var headline: String
        var explanation: String
        /// "acidemia", "alkalemia" or "normal"; nil before two values are in.
        var status: String?
        var primary: Disorder?
        var second: Disorder?
        var phase: Phase?
        var disorders: [Disorder]
        var steps: [Step]
        var cautions: [String]
        var visual: Visual?
        var values: Values
        var derived: Derived?
        var check: Check?
    }

    struct Expect: Hashable {
        var v: Double
        var lo: Double
        var hi: Double
    }

    // MARK: Henderson–Hasselbalch

    static func ph(_ d: AbgData, paco2: Double, hco3: Double) -> Double { d.check.pk + log10(hco3 / (d.check.solubility * paco2)) }
    static func hco3(_ d: AbgData, ph: Double, paco2: Double) -> Double { d.check.solubility * paco2 * pow(10, ph - d.check.pk) }
    static func paco2(_ d: AbgData, ph: Double, hco3: Double) -> Double { hco3 / (d.check.solubility * pow(10, ph - d.check.pk)) }

    /// The band a rule expects at x.
    static func expect(_ rule: AbgRule, _ x: Double) -> Expect {
        let v = rule.slope * x + rule.intercept, t = rule.tol ?? 0
        return Expect(v: v, lo: v - t, hi: v + t)
    }

    // MARK: Text

    /// 24.84 → "24.8"; 31 → "31".
    static func f1(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded(.towardZero) ? String(Int(r)) : String(format: "%.1f", r)
    }

    /// pH to two places.
    static func fph(_ v: Double) -> String { String(format: "%.2f", (v * 100).rounded() / 100) }

    static func band(_ e: Expect) -> String { f1(e.lo) + "–" + f1(e.hi) }

    private static func cap(_ s: String) -> String {
        s.split(separator: " ").map { w in w == "and" ? String(w) : w.prefix(1).uppercased() + w.dropFirst() }.joined(separator: " ")
    }

    /// The two disorders in the order found: "Metabolic and Respiratory Acidosis", "Respiratory Acidosis and
    /// Metabolic Alkalosis".
    static func title(_ a: Disorder, _ b: Disorder?) -> String {
        guard let b else { return cap(a.name) }
        let pa = a.name.split(separator: " "), pb = b.name.split(separator: " ")
        return pa[1] == pb[1] ? cap("\(pa[0]) and \(pb[0]) \(pa[1])") : cap("\(a.name) and \(b.name)")
    }

    // MARK: Reading

    static func read(ph phIn: Double?, paco2 pcIn: Double?, hco3 hcIn: Double?, data d: AbgData) -> Reading {
        var steps: [Step] = []
        var cautions: [String] = []
        let given = [phIn, pcIn, hcIn].compactMap { $0 }.count
        guard given >= 2 else {
            return Reading(empty: true, headline: "Enter the Gas", explanation: "Enter pH, PaCO₂ and HCO₃. Any two are enough: the third is worked out from them.",
                           status: nil, primary: nil, second: nil, phase: nil, disorders: [], steps: [], cautions: [], visual: nil,
                           values: Values(ph: phIn, paco2: pcIn, hco3: hcIn), derived: nil, check: nil)
        }
        var derived: Derived?
        let p: Double, c: Double, h: Double
        if let pc = pcIn, let hc = hcIn, phIn == nil { p = ph(d, paco2: pc, hco3: hc); c = pc; h = hc; derived = .ph }
        else if let ph0 = phIn, let pc = pcIn, hcIn == nil { p = ph0; c = pc; h = hco3(d, ph: ph0, paco2: pc); derived = .hco3 }
        else if let ph0 = phIn, let hc = hcIn, pcIn == nil { p = ph0; c = paco2(d, ph: ph0, hco3: hc); h = hc; derived = .paco2 }
        else { p = phIn!; c = pcIn!; h = hcIn! }

        let N = d.normal, M = d.mid
        if let P = d.plausible, p < P.ph[0] || p > P.ph[1] || c < P.paco2[0] || c > P.paco2[1] || h < P.hco3[0] || h > P.hco3[1] {
            cautions.append("A value lies outside what a blood gas usually shows. Check the entry and the units (mmHg, not kPa).")
        }
        let status = p < N.ph[0] ? "acidemia" : (p > N.ph[1] ? "alkalemia" : "normal")
        let pcHi = c > N.paco2[1], pcLo = c < N.paco2[0], hcLo = h < N.hco3[0], hcHi = h > N.hco3[1]
        steps.append(Step(id: "ph", label: "pH", tone: status == "normal" ? .ok : .bad, text: fph(p) + (derived == .ph ? " (calculated)" : "") + " · " + status))
        var check: Check?
        if given == 3 {
            let calc = ph(d, paco2: c, hco3: h), diff = calc - p
            check = Check(calc: calc, diff: diff, ok: abs(diff) <= d.check.tol)
            if check?.ok == false {
                cautions.append("The three values do not agree: PaCO₂ \(f1(c)) and HCO₃ \(f1(h)) give pH \(fph(calc)), not \(fph(p)). Look for a typing error, or an HCO₃ from a separate chemistry sample; the reading below uses the values as entered.")
            }
        }
        let values = Values(ph: p, paco2: c, hco3: h)
        func out(_ headline: String, _ explanation: String, primary: Disorder? = nil, second: Disorder? = nil, phase: Phase? = nil, disorders: [Disorder] = [], visual: Visual? = nil) -> Reading {
            if let check {
                steps.append(Step(id: "check", label: "Values agree", tone: check.ok ? .ok : .bad,
                                  text: "PaCO₂ and HCO₃ give pH \(fph(check.calc)) · " + (check.ok ? "consistent" : "differs by " + String(format: "%.2f", abs(check.diff)))))
            }
            if let derived {
                let t: String
                switch derived {
                case .hco3: t = "HCO₃ \(f1(h)) mEq/L from pH and PaCO₂"
                case .paco2: t = "PaCO₂ \(f1(c)) mmHg from pH and HCO₃"
                case .ph: t = "pH \(fph(p)) from PaCO₂ and HCO₃"
                }
                steps.append(Step(id: "derived", label: "Calculated", tone: .info, text: t))
            }
            return Reading(empty: false, headline: headline, explanation: explanation, status: status, primary: primary, second: second, phase: phase,
                           disorders: disorders, steps: steps, cautions: cautions, visual: visual, values: values, derived: derived, check: check)
        }

        if status == "normal" && !pcHi && !pcLo && !hcLo && !hcHi {
            steps.append(Step(id: "primary", label: "PaCO₂ and HCO₃", tone: .ok, text: "\(f1(c)) mmHg and \(f1(h)) mEq/L · both normal"))
            return out("Normal Acid–Base Status", "pH, PaCO₂ and HCO₃ are all in the normal range. A metabolic acidosis and alkalosis that cancel out can still hide behind a normal gas.")
        }
        // Which process moves pH the way it went (toward the side of 7.40 it sits on)
        let side: String? = p < M.ph ? "acid" : (p > M.ph ? "alk" : nil)
        let resp: Bool, met: Bool
        switch side {
        case "acid": resp = c > M.paco2; met = h < M.hco3
        case "alk": resp = c < M.paco2; met = h > M.hco3
        default: resp = pcHi || pcLo; met = hcHi || hcLo
        }
        let respOut = side == "acid" ? pcHi : (side == "alk" ? pcLo : resp)
        let metOut = side == "acid" ? hcLo : (side == "alk" ? hcHi : met)
        let respKind: Disorder = c > M.paco2 ? .respAcid : .respAlk
        let metKind: Disorder = h < M.hco3 ? .metAcid : .metAlk
        let pcText = "PaCO₂ \(f1(c)) mmHg" + (pcHi ? " (above \(f1(N.paco2[1])))" : (pcLo ? " (below \(f1(N.paco2[0])))" : ""))
        let hcText = "HCO₃ \(f1(h)) mEq/L" + (hcLo ? " (below \(f1(N.hco3[0])))" : (hcHi ? " (above \(f1(N.hco3[1])))" : ""))
        let phText = status == "normal" ? "pH \(fph(p)) is normal." : "pH \(fph(p)): \(status)."
        if !resp && !met {
            cautions.append("Neither PaCO₂ nor HCO₃ moves pH the way it went, which a blood gas cannot do. Check the values.")
            return out("Check the Values", "pH \(fph(p)) does not follow from \(pcText) and \(hcText).")
        }
        var primary: Disorder
        if resp && met && respOut == metOut {
            if side == nil || respOut {
                // Both move pH the same way and both are outside their range (or pH sits at 7.40 with both abnormal)
                steps.append(Step(id: "primary", label: "Primary", tone: .bad, text: "\(pcText); \(hcText) · both"))
                let explanation = side == nil
                    ? "pH \(fph(p)) sits at the middle of the range while \(pcText) and \(hcText) are both abnormal: two opposing disorders."
                    : "\(phText) \(pcText) and \(hcText) both push pH the same way, so both are primary and there is no compensation to check."
                return out(title(respKind, metKind), explanation, primary: respKind, second: metKind, disorders: [respKind, metKind])
            }
            // Neither outside its range: the larger shift, scaled by the width of its normal half-range, leads
            let dr = abs(c - M.paco2) / max(N.paco2[1] - M.paco2, M.paco2 - N.paco2[0])
            let dm = abs(h - M.hco3) / max(N.hco3[1] - M.hco3, M.hco3 - N.hco3[0])
            primary = dr >= dm ? respKind : metKind
        } else if resp && met {
            primary = respOut ? respKind : metKind
        } else {
            primary = resp ? respKind : metKind
        }
        let isResp = primary.isRespiratory
        steps.append(Step(id: "primary", label: "Primary", tone: .bad, text: (isResp ? pcText : hcText) + " · " + primary.name))
        var second: Disorder?
        var phase: Phase?
        let visual: Visual
        let compText: String
        if !isResp {
            let rule = d.rules[primary.rawValue] ?? AbgRule(slope: 0, intercept: 0)
            let e = expect(rule, h)
            second = c > e.hi ? .respAcid : (c < e.lo ? .respAlk : nil)
            visual = Visual(variable: "PaCO₂", unit: "mmHg", measured: c, bands: [Band(id: "expected", label: "Expected", lo: e.lo, hi: e.hi)])
            let rel = second == nil ? "sits in it" : (second == .respAcid ? "is above it" : "is below it")
            compText = (rule.label.map { $0 + " expects" } ?? "Expected") + " PaCO₂ \(band(e)) mmHg; \(f1(c)) \(rel)"
            steps.append(Step(id: "comp", label: "Respiratory compensation", tone: second == nil ? .ok : .bad,
                              text: "expected \(band(e)) · measured \(f1(c))" + (second == nil ? "" : (second == .respAcid ? ", above" : ", below"))))
        } else {
            let acid = primary == .respAcid
            let ra = d.rules[acid ? "respAcidAcute" : "respAlkAcute"] ?? AbgRule(slope: 0, intercept: 0)
            let rc = d.rules[acid ? "respAcidChronic" : "respAlkChronic"] ?? AbgRule(slope: 0, intercept: 0)
            let a = expect(ra, c), ch = expect(rc, c)
            if let xmax = rc.xmax, c > xmax { cautions.append("The chronic rule was derived up to PaCO₂ \(f1(xmax)) mmHg; read its band with caution above that.") }
            let inA = h >= a.lo && h <= a.hi, inC = h >= ch.lo && h <= ch.hi
            if h < min(a.lo, ch.lo) { second = .metAcid }
            else if h > max(a.hi, ch.hi) { second = .metAlk }
            else { phase = inA && inC ? .either : (inA ? .acute : (inC ? .chronic : .between)) }
            visual = Visual(variable: "HCO₃", unit: "mEq/L", measured: h, bands: [Band(id: "acute", label: "Acute", lo: a.lo, hi: a.hi), Band(id: "chronic", label: "Chronic", lo: ch.lo, hi: ch.hi)])
            let wherePart: String
            if let second { wherePart = second == .metAcid ? "is below both" : "is above both" }
            else {
                switch phase {
                case .acute: wherePart = "fits an acute change"
                case .chronic: wherePart = "fits a chronic change"
                case .either: wherePart = "fits either; the change is too small to tell them apart"
                default: wherePart = "falls between them: subacute, or acute on chronic"
                }
            }
            compText = "An acute change expects HCO₃ \(band(a)) mEq/L and a chronic one \(band(ch)); \(f1(h)) \(wherePart)"
            steps.append(Step(id: "comp", label: "Metabolic compensation", tone: second == nil ? .ok : .bad,
                              text: "acute \(band(a)) · chronic \(band(ch)) · measured \(f1(h))" + (second == nil ? "" : (second == .metAcid ? ", below" : ", above"))))
        }
        let disorders = [primary] + (second.map { [$0] } ?? [])
        var headline = title(primary, second)
        if second == nil && isResp {
            switch phase {
            case .acute: headline = "Acute " + headline
            case .chronic: headline = "Chronic " + headline
            case .between: headline += ", Partly Compensated"
            default: break
            }
        }
        let kind = isResp ? "respiratory" : "metabolic"
        let lead = status == "normal" ? "pH \(fph(p)) is normal, but \(isResp ? pcText : hcText) points to a \(kind) process." : "\(phText) \(isResp ? pcText : hcText) makes it \(kind)."
        let tail: String
        if let second { tail = ". " + second.name.prefix(1).uppercased() + second.name.dropFirst() + " as well." }
        else { tail = isResp ? "." : ": the respiratory compensation is appropriate." }
        return out(headline, "\(lead) \(compText)\(tail)", primary: primary, second: second, phase: phase, disorders: disorders, visual: visual)
    }

    /// One line for the record.
    static func summary(_ r: Reading) -> String {
        guard !r.empty, let p = r.values.ph, let c = r.values.paco2, let h = r.values.hco3 else { return "" }
        var calc = ""
        if let dv = r.derived {
            switch dv {
            case .hco3: calc = " (HCO₃ calculated)"
            case .paco2: calc = " (PaCO₂ calculated)"
            case .ph: calc = " (pH calculated)"
            }
        }
        return "ABG: pH \(fph(p)), PaCO₂ \(f1(c)) mmHg, HCO₃ \(f1(h)) mEq/L\(calc). \(r.headline). \(r.explanation)"
    }
}
