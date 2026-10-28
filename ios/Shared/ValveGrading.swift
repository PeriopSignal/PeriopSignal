import Foundation

// MARK: - Valve severity grading (ASE)
//
// The grading tables of the 2017 ASE native regurgitation recommendations (Tables 8, 11, 14 and the
// Figure 18 integration for MR), the 2017 EACVI/ASE aortic stenosis update (Table 3 and the low-gradient
// pathway) and the 2023 ASE rheumatic heart disease document (mitral stenosis), as rules. Each parameter
// the user enters is graded; the lesion's integration rule turns the set into one reading.

enum ValveGrade: Int, Comparable, Hashable {
    case mild = 1, moderate = 2, severe = 3
    static func < (a: ValveGrade, b: ValveGrade) -> Bool { a.rawValue < b.rawValue }
    var label: String {
        switch self {
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        }
    }
}

enum ValveLesion: String, CaseIterable, Identifiable, Hashable {
    case as_ = "as", ar, mr, ms, tr
    var id: String { rawValue }
    var name: String {
        switch self {
        case .as_: return "Aortic stenosis"
        case .ar: return "Aortic regurgitation"
        case .mr: return "Mitral regurgitation"
        case .ms: return "Mitral stenosis"
        case .tr: return "Tricuspid regurgitation"
        }
    }
    var short: String {
        switch self {
        case .as_: return "AS"
        case .ar: return "AR"
        case .mr: return "MR"
        case .ms: return "MS"
        case .tr: return "TR"
        }
    }
    var source: String {
        switch self {
        case .as_: return "EACVI/ASE 2017 aortic stenosis focused update, Table 3 and the stepwise low-gradient pathway"
        case .ar: return "ASE 2017 native valvular regurgitation, Table 11"
        case .mr: return "ASE 2017 native valvular regurgitation, Table 8 and Figure 18"
        case .ms: return "ASE 2023 rheumatic heart disease, Table 1 (ASE's current mitral stenosis criteria)"
        case .tr: return "ASE 2017 native valvular regurgitation, Table 14"
        }
    }
}

/// A measured parameter: a number graded against two cut points, or a sign that is specific for a grade.
struct ValveParam: Identifiable, Hashable {
    enum Kind: Hashable {
        /// `mildBelow` and `severeFrom` for a value where higher is worse (e.g. vena contracta).
        case higherWorse(mildBelow: Double, severeFrom: Double)
        /// Lower is worse (e.g. valve area, pressure half-time in AR): mild at or above `mildFrom`, severe below `severeBelow`.
        case lowerWorse(mildFrom: Double, severeBelow: Double)
        /// A yes/no sign that counts as specific for a grade.
        case sign(ValveGrade)
        /// A value the tables only define a severe threshold for (TR color jet area): severe at or above it, otherwise ungraded.
        case severeFrom(Double)
        /// A supporting input used by the integration rule, not graded on its own (LVEF, SVi).
        case context
    }
    let id: String
    let label: String
    let unit: String
    let kind: Kind
    let hint: String?
    /// Specific signs carry more weight than supportive ones in the integration (bold in the ASE tables).
    let specific: Bool

    static func num(_ id: String, _ label: String, _ unit: String, higherWorse mild: Double, _ severe: Double, specific: Bool = false, hint: String? = nil) -> ValveParam {
        ValveParam(id: id, label: label, unit: unit, kind: .higherWorse(mildBelow: mild, severeFrom: severe), hint: hint, specific: specific)
    }
    static func inv(_ id: String, _ label: String, _ unit: String, lowerWorse mild: Double, _ severe: Double, specific: Bool = false, hint: String? = nil) -> ValveParam {
        ValveParam(id: id, label: label, unit: unit, kind: .lowerWorse(mildFrom: mild, severeBelow: severe), hint: hint, specific: specific)
    }
    static func sign(_ id: String, _ label: String, _ grade: ValveGrade, hint: String? = nil) -> ValveParam {
        ValveParam(id: id, label: label, unit: "", kind: .sign(grade), hint: hint, specific: true)
    }
    static func ctx(_ id: String, _ label: String, _ unit: String, hint: String? = nil) -> ValveParam {
        ValveParam(id: id, label: label, unit: unit, kind: .context, hint: hint, specific: false)
    }
    static func severeOnly(_ id: String, _ label: String, _ unit: String, from: Double, hint: String? = nil) -> ValveParam {
        ValveParam(id: id, label: label, unit: unit, kind: .severeFrom(from), hint: hint, specific: false)
    }

    var isSign: Bool { if case .sign = kind { return true } else { return false } }

    /// Grade of a numeric value; nil for context parameters and for severe-only values below their threshold.
    func grade(_ value: Double) -> ValveGrade? {
        switch kind {
        case .higherWorse(let mild, let severe):
            if value >= severe { return .severe }
            if value < mild { return .mild }
            return .moderate
        case .lowerWorse(let mild, let severe):
            if value < severe { return .severe }
            if value >= mild { return .mild }
            return .moderate
        case .severeFrom(let severe):
            return value >= severe ? .severe : nil
        case .sign, .context: return nil
        }
    }
}

struct ValveInput: Hashable {
    var numbers: [String: Double] = [:]
    var signs: Set<String> = []
    var isEmpty: Bool { numbers.isEmpty && signs.isEmpty }
}

struct ValveReading: Hashable {
    struct Line: Hashable, Identifiable {
        var id: String
        var label: String
        var text: String
        var grade: ValveGrade?
    }
    var overall: ValveGrade?
    /// "Severe", "Probably moderate", "Indeterminate", or a pathway statement for low-gradient AS.
    var headline: String
    var explanation: String
    var lines: [Line]
    var cautions: [String]
}

enum ValveGrading {
    static func params(for lesion: ValveLesion) -> [ValveParam] {
        switch lesion {
        case .as_: return [
            .num("vmax", "Peak velocity", "m/s", higherWorse: 3.0, 4.0, specific: true, hint: "Mild 2.6–2.9 · moderate 3.0–4.0 · severe ≥ 4.0"),
            .num("mg", "Mean gradient", "mmHg", higherWorse: 20, 40, specific: true, hint: "Mild < 20 · moderate 20–40 · severe ≥ 40"),
            .inv("ava", "Aortic valve area", "cm²", lowerWorse: 1.5, 1.0, hint: "Mild > 1.5 · moderate 1.0–1.5 · severe < 1.0"),
            .inv("avai", "Indexed valve area", "cm²/m²", lowerWorse: 0.85, 0.6, hint: "Severe < 0.6"),
            .inv("ratio", "Velocity ratio", "", lowerWorse: 0.5, 0.25, hint: "LVOT ÷ aortic velocity; severe < 0.25"),
            .ctx("svi", "Stroke volume index", "mL/m²", hint: "Low flow < 35"),
            .ctx("lvef", "LVEF", "%", hint: "Decides the low-flow, low-gradient pathway"),
        ]
        case .ar: return [
            .num("vc", "Vena contracta width", "cm", higherWorse: 0.3, 0.61, specific: true, hint: "Mild < 0.3 · moderate 0.3–0.6 · severe > 0.6"),
            .num("jetw", "Jet width ÷ LVOT width", "%", higherWorse: 25, 65, hint: "Central jets; severe ≥ 65"),
            .num("jeta", "Jet area ÷ LVOT area", "%", higherWorse: 5, 60, hint: "Central jets; severe ≥ 60"),
            .inv("pht", "Pressure half-time", "ms", lowerWorse: 500, 200, hint: "Mild > 500 · moderate 200–500 · severe < 200"),
            .num("rvol", "Regurgitant volume", "mL", higherWorse: 30, 60, hint: "Mild < 30 · moderate 30–59 · severe ≥ 60"),
            .num("rf", "Regurgitant fraction", "%", higherWorse: 30, 50, hint: "Severe ≥ 50"),
            .num("eroa", "EROA", "cm²", higherWorse: 0.10, 0.30, hint: "Severe ≥ 0.30"),
            .sign("flail", "Flail leaflet or wide coaptation defect", .severe),
            .sign("holo", "Prominent holodiastolic flow reversal in the descending aorta", .severe),
            .sign("lvdil", "LV dilated without another cause", .severe, hint: "Supportive; not in acute AR"),
            .sign("faint", "Faint or incomplete CW jet, slow deceleration", .mild),
        ]
        case .mr: return [
            .num("vc", "Vena contracta width", "cm", higherWorse: 0.3, 0.7, specific: true, hint: "Mild < 0.3 · severe ≥ 0.7 (> 0.8 biplane)"),
            .num("eroa", "EROA by 2D PISA", "cm²", higherWorse: 0.20, 0.40, hint: "Grades I–IV: < 0.20 · 0.20–0.29 · 0.30–0.39 · ≥ 0.40"),
            .num("rvol", "Regurgitant volume", "mL", higherWorse: 30, 60, hint: "< 30 · 30–44 · 45–59 · ≥ 60"),
            .num("rf", "Regurgitant fraction", "%", higherWorse: 30, 50, hint: "< 30 · 30–39 · 40–49 · ≥ 50"),
            .num("pisa", "PISA radius at Nyquist 30–40 cm/s", "cm", higherWorse: 0.31, 1.0, specific: true, hint: "≤ 0.3 specific for mild; ≥ 1.0 specific for severe"),
            .sign("flail", "Flail leaflet", .severe),
            .sign("bigjet", "Central jet larger than 50% of the LA", .severe),
            .sign("pvrev", "Pulmonary vein systolic flow reversal", .severe),
            .sign("lvbig", "Enlarged LV with normal function", .severe),
            .sign("smalljet", "Small, narrow central jet", .mild),
            .sign("awave", "A-wave dominant mitral inflow", .mild),
            .sign("softcw", "Soft or incomplete CW jet", .mild),
            .sign("normal", "Normal LV and LA size", .mild),
            .sign("secondary", "Secondary (functional) MR", .moderate, hint: "Crescentic orifice: PISA underestimates; a grade III EROA may be severe"),
            .sign("nonholo", "Non-holosystolic (mid-to-late) MR", .moderate, hint: "Single-frame EROA and vena contracta overestimate; trust the regurgitant volume"),
        ]
        case .ms: return [
            .inv("mva", "Mitral valve area", "cm²", lowerWorse: 2.51, 1.51, specific: true, hint: "Mild > 2.5 · moderate 1.6–2.5 · severe ≤ 1.5 (planimetry preferred)"),
            .num("pht", "Pressure half-time", "ms", higherWorse: 100, 150, hint: "Mild < 100 · moderate 100–149 · severe ≥ 150"),
            .num("mg", "Mean gradient at 60–80 bpm", "mmHg", higherWorse: 5, 10, hint: "Supportive; flow and rate dependent"),
            .num("pasp", "Systolic PA pressure", "mmHg", higherWorse: 30, 50, hint: "Supportive; severe ≥ 50"),
        ]
        case .tr: return [
            .num("vc", "Vena contracta width", "cm", higherWorse: 0.3, 0.7, specific: true, hint: "Mild < 0.3 · moderate 0.3–0.69 · severe ≥ 0.7"),
            .num("eroa", "EROA", "cm²", higherWorse: 0.20, 0.40, hint: "Severe ≥ 0.40"),
            .num("rvol", "Regurgitant volume by 2D PISA", "mL", higherWorse: 30, 45, hint: "Severe ≥ 45"),
            .num("pisa", "PISA radius at Nyquist 28 cm/s", "cm", higherWorse: 0.51, 0.91, hint: "≤ 0.5 · 0.6–0.9 · > 0.9"),
            .severeOnly("jet", "Color jet area", "cm²", from: 10, hint: "> 10 cm² supports severe; the tables do not grade smaller areas"),
            .num("ivc", "IVC diameter", "cm", higherWorse: 2.05, 2.55, hint: "Normal < 2 · 2.1–2.5 · > 2.5"),
            .sign("flail", "Flail leaflet, severe retraction or large perforation", .severe),
            .sign("hvrev", "Hepatic vein systolic flow reversal", .severe),
            .sign("ewave", "Tricuspid E-wave above 1.0 m/s", .severe, hint: "Supportive, nonspecific"),
            .sign("dilated", "RV and RA dilated", .severe, hint: "Supportive; can be normal in acute TR"),
        ]
        }
    }

    static func read(_ lesion: ValveLesion, _ input: ValveInput) -> ValveReading {
        switch lesion {
        case .as_: return readAS(input)
        case .mr: return readMR(input)
        case .ms: return readMS(input)
        case .ar, .tr: return readRegurg(lesion, input)
        }
    }

    // MARK: Aortic stenosis

    private static func readAS(_ i: ValveInput) -> ValveReading {
        var lines: [ValveReading.Line] = []
        var cautions: [String] = []
        let p = params(for: .as_)
        for param in p {
            guard let v = i.numbers[param.id] else { continue }
            if case .context = param.kind {
                lines.append(.init(id: param.id, label: param.label, text: "\(fmt(v)) \(param.unit)", grade: nil))
            } else if let g = param.grade(v) {
                lines.append(.init(id: param.id, label: param.label, text: "\(fmt(v)) \(param.unit) · \(g.label.lowercased())", grade: g))
            }
        }
        let vmax = i.numbers["vmax"], mg = i.numbers["mg"], ava = i.numbers["ava"], avai = i.numbers["avai"], svi = i.numbers["svi"], lvef = i.numbers["lvef"]
        guard vmax != nil || mg != nil || ava != nil || avai != nil else {
            return ValveReading(overall: nil, headline: "Enter the measurements", explanation: "Peak velocity and mean gradient first; the valve area, flow and LVEF decide the low-gradient cases.", lines: lines, cautions: [])
        }
        let highGradient = (vmax ?? 0) >= 4.0 || (mg ?? 0) >= 40
        let smallArea = (ava.map { $0 < 1.0 } ?? false) || (avai.map { $0 < 0.6 } ?? false)
        if let s = svi, s > 58 { cautions.append("High flow (SVi > 58 mL/m²) inflates gradients: reassess the area.") }
        if highGradient {
            if let a = ava, a >= 1.0 { cautions.append("High gradient with an area of 1.0 cm² or more: check for high flow, measurement error or pressure recovery (ascending aorta under 30 mm).") }
            if let v = vmax, v > 5.5 { cautions.append("Peak velocity above 5.5 m/s is a prognostic marker in asymptomatic patients.") }
            return ValveReading(overall: .severe, headline: "Severe, high-gradient AS", explanation: "Peak velocity ≥ 4 m/s or mean gradient ≥ 40 mmHg defines high-gradient AS (Step 1).", lines: lines, cautions: cautions)
        }
        if smallArea {
            if let s = svi {
                if s >= 35 {
                    return ValveReading(overall: .moderate, headline: "Normal-flow, low-gradient: severe AS unlikely", explanation: "With a normal stroke volume index (≥ 35 mL/m²) a calculated area under 1.0 cm² does not make severe AS; look for an LVOT under-measurement before calling it more than moderate.", lines: lines, cautions: cautions)
                }
                if let ef = lvef {
                    if ef < 50 {
                        return ValveReading(overall: nil, headline: "Low-flow, low-gradient AS with reduced EF", explanation: "Low-dose dobutamine stress echo: severe if the velocity reaches 4 m/s or the mean gradient 30–40 mmHg while the area stays ≤ 1.0 cm² at any flow; an area rising above 1.0 cm² means not severe (pseudosevere). A stroke volume rise over 20% shows contractile reserve.", lines: lines, cautions: cautions)
                    }
                    return ValveReading(overall: nil, headline: "Paradoxical low-flow, low-gradient AS", explanation: "Confirm the low flow by another technique (3D TEE or CT for the LVOT, CMR) and weigh the likelihood criteria: symptoms without another cause, age over 70, LVH, reduced longitudinal function, mean gradient 30–40 mmHg when normotensive, AVA ≤ 0.8 cm², and the CT calcium score (severe likely at ≥ 2,000 AU in men, ≥ 1,200 in women).", lines: lines, cautions: cautions)
                }
                return ValveReading(overall: nil, headline: "Low-flow, low-gradient AS", explanation: "Enter the LVEF: below 50% the next step is dobutamine stress echo; 50% or more is the paradoxical pattern that needs flow confirmation and the likelihood criteria.", lines: lines, cautions: cautions)
            }
            return ValveReading(overall: nil, headline: "Low-gradient with a small area", explanation: "An area under 1.0 cm² suggests but does not confirm severe AS. Enter the stroke volume index: normal flow (≥ 35 mL/m²) makes severe AS unlikely; low flow sends you down the dobutamine or paradoxical pathway depending on LVEF.", lines: lines, cautions: cautions)
        }
        // Not high gradient, area not small: grade by the velocity/gradient/area bands.
        var grades: [ValveGrade] = []
        if let v = vmax { grades.append(v < 2.6 ? .mild : (v < 3.0 ? .mild : .moderate)) }
        if let m = mg { grades.append(m < 20 ? .mild : .moderate) }
        if let a = ava { grades.append(a > 1.5 ? .mild : .moderate) }
        let overall = grades.max() ?? .mild
        if let v = vmax, v <= 2.5 {
            return ValveReading(overall: nil, headline: "Aortic sclerosis", explanation: "Peak velocity ≤ 2.5 m/s: thickening without stenosis.", lines: lines, cautions: cautions)
        }
        return ValveReading(overall: overall, headline: "\(overall.label) AS", explanation: overall == .moderate ? "Velocity 3.0–4.0 m/s, mean gradient 20–40 mmHg or area 1.0–1.5 cm² (Table 3)." : "Velocity 2.6–2.9 m/s, mean gradient under 20 mmHg, area over 1.5 cm² (Table 3).", lines: lines, cautions: cautions)
    }

    // MARK: Mitral regurgitation (Figure 18)

    private static func readMR(_ i: ValveInput) -> ValveReading {
        let p = params(for: .mr)
        var lines: [ValveReading.Line] = []
        var cautions: [String] = []
        for param in p {
            if let v = i.numbers[param.id], let g = param.grade(v) {
                lines.append(.init(id: param.id, label: param.label, text: "\(fmt(v)) \(param.unit) · \(g.label.lowercased())", grade: g))
            } else if i.signs.contains(param.id), case .sign(let g) = param.kind {
                lines.append(.init(id: param.id, label: param.label, text: g == .moderate ? "noted" : "specific for \(g.label.lowercased())", grade: g == .moderate ? nil : g))
            }
        }
        if i.isEmpty { return ValveReading(overall: nil, headline: "Enter the signs and measurements", explanation: "Four specific signs settle mild or severe; otherwise the quantitative values decide (EROA, regurgitant volume and fraction).", lines: [], cautions: []) }
        // Specific criteria
        var severeSigns = 0, mildSigns = 0
        if let vc = i.numbers["vc"] { if vc >= 0.7 { severeSigns += 1 } else if vc <= 0.3 { mildSigns += 1 } }
        if let r = i.numbers["pisa"] { if r >= 1.0 { severeSigns += 1 } else if r <= 0.3 { mildSigns += 1 } }
        for s in ["flail", "bigjet", "pvrev", "lvbig"] where i.signs.contains(s) { severeSigns += 1 }
        for s in ["smalljet", "awave", "softcw", "normal"] where i.signs.contains(s) { mildSigns += 1 }
        let secondary = i.signs.contains("secondary")
        if i.signs.contains("nonholo") { cautions.append("Non-holosystolic MR: single-frame EROA and vena contracta overestimate; the regurgitant volume is the better guide.") }
        if secondary { cautions.append("Secondary MR: 2D PISA underestimates a crescentic orifice; 3D vena contracta area can rescue the grade; E velocity and pulmonary-vein blunting are nonspecific.") }
        // Quantitative grade I–IV
        func qGrade(_ v: Double?, _ bands: [Double]) -> Int? { v.map { x in bands.filter { x >= $0 }.count + 1 } }
        let q = [qGrade(i.numbers["eroa"], [0.20, 0.30, 0.40]), qGrade(i.numbers["rvol"], [30, 45, 60]), qGrade(i.numbers["rf"], [30, 40, 50])].compactMap { $0 }
        if let hi = q.max(), let lo = q.min(), hi - lo >= 2 { cautions.append("The quantitative measures disagree with each other: check the PISA radius, the LVOT and mitral annulus measurements, or quantify by another method.") }
        if severeSigns >= 4 && mildSigns == 0 {
            return ValveReading(overall: .severe, headline: "Definitely severe MR", explanation: "Four or more specific criteria for severe MR (Figure 18).", lines: lines, cautions: cautions)
        }
        if mildSigns >= 4 && severeSigns == 0 {
            return ValveReading(overall: .mild, headline: "Definitely mild MR", explanation: "Four or more specific criteria for mild MR (Figure 18).", lines: lines, cautions: cautions)
        }
        if let qg = q.max() {
            let conflict = (qg >= 3 && mildSigns >= 2) || (qg <= 2 && severeSigns >= 2)
            if conflict {
                return ValveReading(overall: nil, headline: "Indeterminate: quantify further", explanation: "The quantitative grade and the specific signs point different ways; consider TEE or CMR for quantitation before committing to a grade.", lines: lines, cautions: cautions)
            }
            switch qg {
            case 4: return ValveReading(overall: .severe, headline: "Severe MR (grade IV)", explanation: "EROA ≥ 0.40 cm², regurgitant volume ≥ 60 mL or fraction ≥ 50%.", lines: lines, cautions: cautions)
            case 3:
                if severeSigns >= 3 || secondary {
                    return ValveReading(overall: .severe, headline: "Severe MR (grade III with severe signs)", explanation: secondary ? "Grade III values (EROA 0.30–0.39, volume 45–59 mL, fraction 40–49%) read as severe in secondary MR with an elliptical orifice (Figure 18)." : "Grade III values with three specific criteria for severe MR read as severe (Figure 18).", lines: lines, cautions: cautions)
                }
                return ValveReading(overall: .moderate, headline: "Moderate MR (grade III)", explanation: "EROA 0.30–0.39 cm², volume 45–59 mL or fraction 40–49%: the upper moderate band; severe only with three specific severe signs or an elliptical orifice.", lines: lines, cautions: cautions)
            case 2: return ValveReading(overall: .moderate, headline: "Moderate MR (grade II)", explanation: "EROA 0.20–0.29 cm², volume 30–44 mL or fraction 30–39%.", lines: lines, cautions: cautions)
            default: return ValveReading(overall: .mild, headline: "Mild MR (grade I)", explanation: "EROA under 0.20 cm², volume under 30 mL, fraction under 30%.", lines: lines, cautions: cautions)
            }
        }
        if severeSigns >= 2 && mildSigns == 0 { return ValveReading(overall: .severe, headline: "Probably severe: quantify", explanation: "\(severeSigns) specific signs of severe MR and none of mild; quantitative methods confirm it (Figure 18 asks for them whenever possible).", lines: lines, cautions: cautions) }
        if mildSigns >= 2 && severeSigns == 0 { return ValveReading(overall: .mild, headline: "Probably mild", explanation: "\(mildSigns) specific signs of mild MR and none of severe.", lines: lines, cautions: cautions) }
        return ValveReading(overall: .moderate, headline: "Probably moderate: quantify", explanation: "Intermediate or mixed signs; EROA, regurgitant volume and fraction decide (Figure 18).", lines: lines, cautions: cautions)
    }

    // MARK: Mitral stenosis

    private static func readMS(_ i: ValveInput) -> ValveReading {
        let p = params(for: .ms)
        var lines: [ValveReading.Line] = []
        for param in p {
            if let v = i.numbers[param.id], let g = param.grade(v) { lines.append(.init(id: param.id, label: param.label, text: "\(fmt(v)) \(param.unit) · \(g.label.lowercased())", grade: g)) }
        }
        if i.isEmpty { return ValveReading(overall: nil, headline: "Enter the measurements", explanation: "Valve area (planimetry preferred) and pressure half-time define the grade; gradient and PA pressure support it.", lines: [], cautions: []) }
        var cautions = ["Gradients depend on flow and heart rate: report the rhythm and rate, and never grade on the gradient alone.", "Pressure half-time misleads with severe AR, right after balloon commissurotomy and with altered LA or LV compliance."]
        let mva = i.numbers["mva"], pht = i.numbers["pht"]
        let anatomicSevere = (mva.map { $0 <= 1.5 } ?? false) || (pht.map { $0 >= 150 } ?? false)
        if anatomicSevere {
            if let m = mva, m > 1.5 { cautions.insert("Half-time says severe but the planimetered area does not: planimetry is the anatomic method; recheck both.", at: 0) }
            return ValveReading(overall: .severe, headline: "Severe mitral stenosis", explanation: "Valve area ≤ 1.5 cm² or pressure half-time ≥ 150 ms (ASE 2023). A mean gradient ≥ 10 mmHg at 60–80 bpm and PA systolic pressure ≥ 50 mmHg support it.", lines: lines, cautions: cautions)
        }
        let primary = [mva.map { $0 > 2.5 ? ValveGrade.mild : .moderate }, pht.map { $0 < 100 ? ValveGrade.mild : .moderate }].compactMap { $0 }
        let supportive = [i.numbers["mg"].map { $0 < 5 ? ValveGrade.mild : ($0 < 10 ? .moderate : .severe) }, i.numbers["pasp"].map { $0 < 30 ? ValveGrade.mild : ($0 < 50 ? .moderate : .severe) }].compactMap { $0 }
        if let g = primary.max() {
            if supportive.contains(.severe) { cautions.insert("Gradient or PA pressure in the severe range with a non-severe area: look for high flow, tachycardia or another cause of pulmonary hypertension.", at: 0) }
            return ValveReading(overall: g, headline: "\(g.label) (progressive) mitral stenosis", explanation: g == .mild ? "Area over 2.5 cm², half-time under 100 ms." : "Area 1.6–2.5 cm² or half-time 100–149 ms.", lines: lines, cautions: cautions)
        }
        let g = supportive.max() ?? .mild
        return ValveReading(overall: nil, headline: "Supportive signs only (\(g.label.lowercased()) range)", explanation: "Mean gradient and PA pressure are supportive signs; the grade needs the valve area or the pressure half-time.", lines: lines, cautions: cautions)
    }

    // MARK: Aortic and tricuspid regurgitation

    private static func readRegurg(_ lesion: ValveLesion, _ i: ValveInput) -> ValveReading {
        let p = params(for: lesion)
        var lines: [ValveReading.Line] = []
        var specificSevere = 0, specificMild = 0, supportiveSevere = 0
        var quantitative: [ValveGrade] = []
        var semi: [ValveGrade] = []
        for param in p {
            if let v = i.numbers[param.id] {
                guard let g = param.grade(v) else {
                    lines.append(.init(id: param.id, label: param.label, text: "\(fmt(v)) \(param.unit) · not graded", grade: nil))
                    continue
                }
                lines.append(.init(id: param.id, label: param.label, text: "\(fmt(v)) \(param.unit) · \(g.label.lowercased())", grade: g))
                if ["rvol", "rf", "eroa"].contains(param.id) { quantitative.append(g) } else { semi.append(g) }
                if param.specific { if g == .severe { specificSevere += 1 } else if g == .mild { specificMild += 1 } }
            } else if i.signs.contains(param.id), case .sign(let g) = param.kind {
                lines.append(.init(id: param.id, label: param.label, text: param.hint?.hasPrefix("Supportive") == true ? "supportive" : "specific for \(g.label.lowercased())", grade: g))
                if param.hint?.hasPrefix("Supportive") == true { supportiveSevere += 1 }
                else if g == .severe { specificSevere += 1 } else if g == .mild { specificMild += 1 }
            }
        }
        if i.isEmpty { return ValveReading(overall: nil, headline: "Enter the signs and measurements", explanation: "Specific signs settle the grade; the quantitative values decide the middle.", lines: [], cautions: []) }
        var cautions: [String] = []
        if lesion == .ar { cautions.append("Pressure half-time shortens with high LV diastolic pressure and lengthens in chronic adaptation; quantitative volumes anchor eccentric jets.") }
        if lesion == .tr { cautions.append("Hepatic-vein and inflow signs are nonspecific (RV diastolic function, AF, RA pressure); color jet area underestimates eccentric jets.") }
        if let hi = quantitative.max(), let lo = quantitative.min(), hi > lo, hi.rawValue - lo.rawValue >= 2 { cautions.append("The quantitative measures disagree: check the stroke volume measurements.") }
        let q = quantitative.max()
        if specificSevere >= 2 && specificMild == 0 && (q == nil || q == .severe) {
            return ValveReading(overall: .severe, headline: "Severe \(lesion.short)", explanation: "\(specificSevere) specific signs of severe regurgitation\(q == .severe ? " and severe quantitative values" : "").", lines: lines, cautions: cautions)
        }
        if let q {
            if (q == .severe && specificMild >= 1) || (q == .mild && specificSevere >= 1) {
                return ValveReading(overall: nil, headline: "Indeterminate: signs and numbers disagree", explanation: "Re-measure, or quantify by another method (volumetric Doppler, 3D, CMR) before grading.", lines: lines, cautions: cautions)
            }
            return ValveReading(overall: q, headline: "\(q.label) \(lesion.short)", explanation: q == .moderate ? "Quantitative values in the moderate band; the sub-bands separate upper from lower moderate." : "Quantitative values in the \(q.label.lowercased()) band" + (specificSevere + specificMild > 0 ? ", with concordant specific signs." : "."), lines: lines, cautions: cautions)
        }
        if specificSevere >= 1 && specificMild == 0 { return ValveReading(overall: .severe, headline: "Probably severe \(lesion.short): quantify", explanation: "A specific sign of severe regurgitation; quantitative methods confirm it.", lines: lines, cautions: cautions) }
        if specificMild >= 1 && specificSevere == 0 && supportiveSevere == 0 { return ValveReading(overall: .mild, headline: "Mild \(lesion.short)", explanation: "Specific signs of mild regurgitation without any of severe.", lines: lines, cautions: cautions) }
        let s = semi.max() ?? (supportiveSevere > 0 ? .moderate : .mild)
        return ValveReading(overall: s, headline: "\(s.label) \(lesion.short), probably: quantify", explanation: "Semiquantitative or supportive signs only; EROA, regurgitant volume and fraction decide.", lines: lines, cautions: cautions)
    }

    static func fmt(_ v: Double) -> String { PedsCalc.fmt(v) }
}
