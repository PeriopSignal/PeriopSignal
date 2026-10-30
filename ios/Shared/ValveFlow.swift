import Foundation

// MARK: - Valve severity, one step at a time
//
// The grading documents' own sequences as workflows: each step asks for one measurement or sign, "Cannot
// obtain" moves on, and the flow ends as soon as the guideline's criteria settle the grade. The words, views
// and cutoffs of every step live in reference.json ("valveFlows"), so a correction reaches the app without an
// update; the order of the steps and the integration rules live here and in src/reference-logic.js
// (R.valveFlow), and both are run against the same cases (ios/Tests/Fixtures/valve-flow-cases.json).

struct ValveFlowData: Codable {
    /// The content format this app understands; a server file in a newer format falls back to the bundled copy.
    static let supportedFormat = 1
    var format: Int
    var reviewed: String?
    var sources: [EchoSource]
    /// "native", "prosthetic": the headings the lesions are listed under.
    var groups: [ValveFlowGroup]?
    var flows: [ValveFlowDef]
    var notes: [String]?

    var isSupported: Bool { format == Self.supportedFormat }
    func groupName(_ id: String) -> String { groups?.first { $0.id == id }?.name ?? id.capitalized }
    /// The flows this build has rules for, in the file's order.
    var usable: [ValveFlowDef] { flows.filter { ValveFlow.rules[$0.id] != nil } }
    func source(_ id: String) -> EchoSource? { sources.first { $0.id == id } }
}

struct ValveFlowGroup: Codable, Hashable {
    var id: String
    var name: String
}

struct ValveFlowDef: Codable, Hashable, Identifiable {
    var id: String
    /// "native" or "prosthetic".
    var group: String
    var name: String
    var short: String
    var intro: String?
    var source: String
    /// Further documents the steps cite (the TEE views).
    var also: [String]?
    var ref: String?
    var steps: [ValveFlowStep]
    var results: [String: ValveFlowResultDef]
    var notes: [String]?

    func step(_ id: String) -> ValveFlowStep? { steps.first { $0.id == id } }
}

struct ValveFlowStep: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    /// A short name for result sentences ("EROA"); the title when absent.
    var short: String?
    /// "number" or "choice".
    var kind: String
    var unit: String?
    /// What to measure and how.
    var ask: String?
    var tte: String?
    var tee: String?
    var bands: [ValveFlowBand]?
    var options: [ValveFlowOption]?
    /// How a number outside every band reads ("intermediate").
    var between: String?

    var isNumber: Bool { kind == "number" }
    /// The bands as one line: "< 0.3 specific for mild · ≥ 0.7 specific for severe".
    var bandText: String? {
        guard let b = bands, !b.isEmpty else { return nil }
        return b.map { [$0.rangeText, $0.label].compactMap { $0 }.joined(separator: " ") }.joined(separator: " · ")
    }
}

struct ValveFlowBand: Codable, Hashable {
    var lt: Double?
    var le: Double?
    var gt: Double?
    var ge: Double?
    var tag: String
    var label: String?
    /// The range as the source prints it ("0.3–0.69"); one-sided bands can leave it out.
    var range: String?

    func contains(_ v: Double) -> Bool {
        if let x = lt, !(v < x) { return false }
        if let x = le, !(v <= x) { return false }
        if let x = gt, !(v > x) { return false }
        if let x = ge, !(v >= x) { return false }
        return true
    }

    var rangeText: String {
        if let range { return range }
        let f = ValveFlow.fmt
        let parts = [gt.map { "> " + f($0) } ?? ge.map { "≥ " + f($0) }, lt.map { "< " + f($0) } ?? le.map { "≤ " + f($0) }].compactMap { $0 }
        return parts.joined(separator: " and ")
    }
}

struct ValveFlowOption: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var detail: String?
    /// What the answer counts as in the flow's rules ("severe", "mild", "low-flow").
    var tag: String?
}

struct ValveFlowResultDef: Codable, Hashable {
    /// 1 mild, 2 moderate, 3 severe; absent when the flow ends on a pathway or an indeterminate reading.
    var grade: Int?
    var headline: String
    /// May hold {placeholders} the rules fill in ("{severe} specific criteria for severe MR").
    var text: String
    var next: [String]?
}

/// One answer: a number, an option, or "Cannot obtain".
enum FlowAnswer: Hashable {
    case number(Double)
    case choice(String)
    case cannot
}

/// A step on the path the answers took, as the result card lists it.
struct FlowRecord: Hashable, Identifiable {
    var step: ValveFlowStep
    var answer: FlowAnswer
    var tag: String?
    var text: String
    var id: String { step.id }
}

struct FlowOutcome: Hashable {
    var id: String
    var grade: ValveGrade?
    var headline: String
    var text: String
    var next: [String]
    var cautions: [String]
}

struct FlowProgress: Hashable {
    var path: [FlowRecord]
    /// The step waiting for an answer; nil once the flow has ended.
    var current: ValveFlowStep?
    var outcome: FlowOutcome?
    /// A running count shown with the current step ("Specific for severe so far: 2").
    var tally: String?
    var cautions: [String]
}

/// Walks the answers through a flow's steps in the order the rules ask for them.
final class FlowWalk {
    enum Got: Equatable {
        /// Not answered yet: the flow stops here and asks.
        case pending
        case cannot
        case number(Double, tag: String?)
        case choice(String, tag: String?)

        var tag: String? {
            switch self {
            case .number(_, let t), .choice(_, let t): return t
            default: return nil
            }
        }
        var number: Double? { if case .number(let v, _) = self { return v } else { return nil } }
        var choice: String? { if case .choice(let c, _) = self { return c } else { return nil } }
    }

    let flow: ValveFlowDef
    let answers: [String: FlowAnswer]
    /// Intraoperative TEE rather than TTE: the rules add the loading-condition cautions.
    let tee: Bool
    private(set) var path: [FlowRecord] = []
    var cautions: [String] = []
    var tally: String?
    /// Steps already taken: a rule may consult a step twice (TR's vena contracta) without listing it twice.
    private var taken: [String: Got] = [:]

    init(_ flow: ValveFlowDef, _ answers: [String: FlowAnswer], tee: Bool = false) {
        self.flow = flow
        self.answers = answers
        self.tee = tee
    }

    /// The answer to a step, recorded on the path. A step the content lacks reads as not obtainable, and an
    /// answer of the wrong kind (a stale option) as not answered.
    func take(_ id: String) -> Got {
        if let g = taken[id] { return g }
        let g = record(id)
        if g != .pending { taken[id] = g }
        return g
    }

    private func record(_ id: String) -> Got {
        guard let s = flow.step(id) else { return .cannot }
        guard let a = answers[id] else { return .pending }
        switch a {
        case .cannot:
            path.append(FlowRecord(step: s, answer: a, tag: nil, text: "Cannot obtain"))
            return .cannot
        case .number(let v):
            guard s.isNumber, v.isFinite else { return .pending }
            let band = s.bands?.first { $0.contains(v) }
            let reading: String? = band != nil ? band?.label : s.between
            let text = ValveFlow.fmt(v) + ValveFlow.unitSuffix(s.unit) + (reading.map { " · " + $0 } ?? "")
            path.append(FlowRecord(step: s, answer: a, tag: band?.tag, text: text))
            return .number(v, tag: band?.tag)
        case .choice(let c):
            guard !s.isNumber, let o = s.options?.first(where: { $0.id == c }) else { return .pending }
            path.append(FlowRecord(step: s, answer: a, tag: o.tag, text: o.label))
            return .choice(c, tag: o.tag)
        }
    }

    func caution(_ s: String) { if !cautions.contains(s) { cautions.append(s) } }
}

/// What a flow's rules decide: ask a step next, or end on a result (with values for its placeholders).
enum FlowEnd: Equatable {
    case ask(String)
    case done(String, [String: String] = [:])
}

enum ValveFlow {
    typealias Rule = (FlowWalk) -> FlowEnd

    /// The rules for each flow id; content for a flow without rules is not offered.
    static let rules: [String: Rule] = [
        "as": aorticStenosis,
        "mr": mitralRegurgitation,
        "ar": aorticRegurgitation,
        "tr": tricuspidRegurgitation,
        "pr": pulmonicRegurgitation,
        "ms": mitralStenosis,
        "ps": pulmonicStenosis,
        "pav": aorticProsthesis,
    ]

    static func progress(_ flow: ValveFlowDef, _ answers: [String: FlowAnswer], tee: Bool = false) -> FlowProgress {
        let w = FlowWalk(flow, answers, tee: tee)
        guard let rule = rules[flow.id] else {
            return FlowProgress(path: [], current: nil, outcome: nil, tally: nil, cautions: [])
        }
        switch rule(w) {
        case .ask(let id):
            return FlowProgress(path: w.path, current: flow.step(id), outcome: nil, tally: w.tally, cautions: w.cautions)
        case .done(let id, let vars):
            let def = flow.results[id] ?? ValveFlowResultDef(grade: nil, headline: "No reading", text: "This version of the content has no text for the result \(id).", next: nil)
            var text = def.text
            for (k, v) in vars { text = text.replacingOccurrences(of: "{\(k)}", with: v) }
            let outcome = FlowOutcome(id: id, grade: def.grade.flatMap(ValveGrade.init(rawValue:)), headline: def.headline, text: text, next: def.next ?? [], cautions: w.cautions)
            return FlowProgress(path: w.path, current: nil, outcome: outcome, tally: nil, cautions: w.cautions)
        }
    }

    /// Enough digits to see which side of a cutoff a value falls: 3 decimals under 1, 2 under 10, 1 under 100.
    static func fmt(_ v: Double) -> String {
        let a = Swift.abs(v)
        let places = a >= 100 ? 0 : (a >= 10 ? 1 : (a >= 1 ? 2 : 3))
        var t = String(format: "%.\(places)f", v)
        if t.contains(".") {
            while t.hasSuffix("0") { t.removeLast() }
            if t.hasSuffix(".") { t.removeLast() }
        }
        return t
    }

    /// A value as typed back into the field when an answer is changed: full precision, no trailing ".0".
    static func entryText(_ v: Double) -> String {
        var t = String(v)
        if t.hasSuffix(".0") { t.removeLast(2) }
        return t
    }

    /// " cm²" after a value; "%" goes on without a space; nothing for a ratio.
    static func unitSuffix(_ u: String?) -> String {
        guard let u, !u.isEmpty else { return "" }
        return u == "%" ? u : " " + u
    }
}

// MARK: - Aortic stenosis (EACVI/ASE 2017 focused update, pp. 383–388)

extension ValveFlow {
    static func aorticStenosis(_ w: FlowWalk) -> FlowEnd {
        if w.tee {
            w.caution("Under general anesthesia velocity and gradients often read lower than on the preoperative TTE; the valve area and the velocity ratio agree with it better (2020 TEE guideline, p. 704).")
        }
        let v = w.take("vmax")
        if v == .pending { return .ask("vmax") }
        let g = w.take("mg")
        if g == .pending { return .ask("mg") }
        let vHigh = (v.number ?? 0) >= 4, gHigh = (g.number ?? 0) >= 40
        if let x = v.number, x > 5.5 { w.caution("A peak velocity above 5.5 m/s carries a worse prognosis (p. 389).") }
        if vHigh || gHigh {
            w.tally = "High-gradient track"
            if v.number != nil, g.number != nil, vHigh != gHigh {
                w.caution("Velocity and mean gradient fall on different sides of the severe cutoff: the stepwise text calls high-gradient AS when both reach it, the basic criteria when either does (pp. 383, 387). Recheck the CW envelope and the beam alignment.")
            }
            let s = w.take("svi")
            if s == .pending { return .ask("svi") }
            guard let sv = s.number else {
                return .done("severe-high", ["flow": "Flow was not checked: high flow (SVi above 58 mL/m²) can push a non-severe valve into this range."])
            }
            if s.tag == "high" {
                let c = w.take("highflow")
                if c == .pending { return .ask("highflow") }
                switch c.choice {
                case "reversible"?: return .done("high-reversible")
                case "fixed"?: return .done("severe-fixed-flow")
                default:
                    w.caution("Stroke volume index above 58 mL/m² without a cause: an overestimated LVOT diameter inflates both the flow and the area (p. 387).")
                    return .done("severe-high", ["flow": "The high stroke volume index (\(fmt(sv)) mL/m²) is unexplained; see the caution."])
                }
            }
            return .done("severe-high", ["flow": "Stroke volume index \(fmt(sv)) mL/m²: no high-flow state."])
        }
        if v == .cannot && g == .cannot {
            let p = w.take("planimetry")
            if p == .pending { return .ask("planimetry") }
            guard let a = p.number else { return .done("nodata") }
            return .done(a < 1 ? "area-severe" : "area-other", ["area": fmt(a)])
        }
        w.tally = "Low-gradient track"
        // The valve area: continuity, else the velocity ratio, else planimetry.
        var small: Bool?
        var areaTag: String?
        var areaValue: Double?
        let a = w.take("ava")
        if a == .pending { return .ask("ava") }
        if let x = a.number {
            small = x < 1; areaTag = a.tag; areaValue = x
        } else {
            let r = w.take("vratio")
            if r == .pending { return .ask("vratio") }
            if let x = r.number {
                small = x <= 0.25; areaTag = r.tag
            } else {
                let p = w.take("planimetry")
                if p == .pending { return .ask("planimetry") }
                if let x = p.number { small = x < 1; areaTag = p.tag; areaValue = x }
            }
        }
        guard let isSmall = small else { return .done("noarea") }
        if !isSmall {
            let tags = [v.tag, g.tag, areaTag]
            if tags.contains("moderate") {
                if areaTag == "moderate" && a.number != nil { w.caution("An area of 1.0 cm² or more with a low gradient indicates moderate AS; in a large LVOT, exclude an overestimated flow and area (p. 387).") }
                return .done("moderate")
            }
            if v.tag == "mild" { return .done("mild") }
            if v.tag == "normal" { return .done("sclerosis") }
            w.caution("Without the peak velocity, mild AS cannot be told from aortic sclerosis (Table 3).")
            return .done("mild")
        }
        let e = w.take("errors")
        if e == .pending { return .ask("errors") }
        if e == .cannot { w.caution("Measurement errors were not excluded: an LVOT diameter cut short by calcium, or a PW sample in the wrong place, makes a falsely small area (pp. 381, 387).") }
        let s = w.take("svi")
        if s == .pending { return .ask("svi") }
        guard let sv = s.number else { return .done("flow-unknown") }
        if sv >= 35 { return .done("normal-flow", ["flow": "a stroke volume index of \(fmt(sv)) mL/m²"]) }
        w.tally = "Low flow, low gradient"
        let ef = w.take("lvef")
        if ef == .pending { return .ask("lvef") }
        guard let efv = ef.number else { return .done("ef-unknown") }
        if efv < 50 {
            let d = w.take("dse")
            if d == .pending { return .ask("dse") }
            switch d.choice {
            case "severe"?: return .done("dse-severe")
            case "pseudo"?: return .done("dse-pseudo")
            case "noreserve"?:
                w.caution("Without flow reserve, valve calcification (best by CT) may be the primary clue; the update prints its calcium cutoffs for preserved EF (pp. 385, 388).")
                return asCalcium(w, track: "Low-flow, low-gradient AS with reduced EF and no flow reserve (calcium cutoffs from the preserved-EF table)")
            case "inconclusive"?:
                w.caution("Flow reserve without a decisive area or gradient: the projected area at a normal flow rate of 250 mL/s can help (p. 385); the calcium cutoffs are from the preserved-EF table (p. 385).")
                return asCalcium(w, track: "Low-flow, low-gradient AS with reduced EF, dobutamine inconclusive")
            default: return .done("dse-next")
            }
        }
        let c = w.take("confirm")
        if c == .pending { return .ask("confirm") }
        if c.choice == "normal" { return .done("normal-flow", ["flow": "normal flow by another method"]) }
        if c == .cannot { w.caution("Low flow not confirmed by another method: LVOT flow tends to underestimate the real flow in these ventricles (p. 388).") }
        var present: [String] = []
        if let m = g.number, m >= 30 { present.append("mean gradient 30–40 mmHg") }
        if let x = areaValue, x <= 0.8 { present.append("area 0.8 cm² or less") }
        if !present.isEmpty { w.caution("Table 5 criteria in these answers: " + present.joined(separator: " and ") + "; the gradient counts when measured while normotensive (p. 385).") }
        return asCalcium(w, track: "Paradoxical low-flow, low-gradient AS")
    }

    private static func asCalcium(_ w: FlowWalk, track: String) -> FlowEnd {
        let c = w.take("calcium")
        if c == .pending { return .ask("calcium") }
        switch c.choice {
        case "likely"?: return .done("calcium-severe", ["track": track])
        case "unlikely"?: return .done("calcium-unlikely", ["track": track])
        default: return .done("indeterminate", ["track": track])
        }
    }
}

// MARK: - Regurgitation (ASE 2017: Figures 18, 25, 31 and 35)

extension ValveFlow {
    /// What a lesion's measurements say: a step to ask, nothing obtained, a grade with its description, or a disagreement.
    enum Measure: Equatable {
        case ask(String)
        case none
        case grade(Int, String)
        case split(String)
    }

    /// One lesion's integration figure: the specific-criteria steps, then its measurements.
    struct RegurgPlan {
        var criteria: [String]
        /// Specific criteria from one list that settle the grade, when that list also outnumbers the other: four for MR,
        /// AR and TR, three for PR.
        var need: Int
        /// 4: grades I–IV (MR, AR); 3: mild, moderate, severe (TR, PR).
        var scale: Int
        /// Acute MR or AR: the specific signs never settle mild, and a mild reading is not accepted (p. 323).
        var acute = false
        /// Criteria that must be assessed before "probably moderate" without measurements (PR).
        var minAssessed = 0
        /// The result when the measurements give nothing.
        var noQuant = "indeterminate"
        /// 1 when an answer is a specific criterion for mild, 3 for severe; nil when it does not count.
        var specific: (String, FlowWalk.Got) -> Int?
        var measure: (FlowWalk) -> Measure
        /// Grade III on the four-grade scale: severe only with three specific severe criteria (or, for MR, an elliptical orifice).
        var gradeThree: ((FlowWalk, Int, [String: String]) -> FlowEnd)?
    }

    static func tallyText(_ mild: Int, _ severe: Int) -> String {
        "Specific for mild: \(mild) · for severe: \(severe)"
    }

    static func regurgitation(_ w: FlowWalk, _ plan: RegurgPlan) -> FlowEnd {
        var mild = 0, severe = 0, assessed = 0
        for id in plan.criteria {
            let g = w.take(id)
            if g == .pending { w.tally = tallyText(mild, severe); return .ask(id) }
            if g != .cannot { assessed += 1 }
            switch plan.specific(id, g) {
            case 1?: mild += 1
            case 3?: severe += 1
            default: break
            }
            if severe >= plan.need && severe > mild { return .done("severe-specific", ["severe": "\(severe)", "mild": "\(mild)"]) }
            if !plan.acute && mild >= plan.need && mild > severe { return .done("mild-specific", ["mild": "\(mild)", "severe": "\(severe)"]) }
        }
        if mild >= plan.need && severe >= plan.need { w.caution("Specific criteria from both lists in equal measure: the measurements decide.") }
        var vars = ["mild": "\(mild)", "severe": "\(severe)"]
        switch plan.measure(w) {
        case .ask(let id):
            w.tally = tallyText(mild, severe)
            return .ask(id)
        case .none:
            vars["lean"] = severe > mild ? "The signs so far lean toward severe." : (mild > severe ? "The signs so far lean toward mild." : "")
            return .done(assessed < plan.minAssessed ? "indeterminate" : plan.noQuant, vars)
        case .split(let text):
            vars["quant"] = text
            return .done("discordant", vars)
        case .grade(let q, let text):
            vars["quant"] = text
            // A specific sign of severe against the lowest grade, or two of mild against the highest, do not agree.
            if (q == plan.scale && mild >= 2) || (q == 1 && severe >= 1) { return .done("discordant", vars) }
            if plan.acute && q == 1 { return .done("acute-mild", vars) }
            if plan.scale == 3 { return .done(["q-mild", "q-moderate", "q-severe"][max(0, min(2, q - 1))], vars) }
            switch q {
            case 1: return .done("grade1", vars)
            case 2: return .done("grade2", vars)
            case 3: return plan.gradeThree?(w, severe, vars) ?? .done("grade3", vars)
            default: return .done("grade4", vars)
            }
        }
    }

    static func roman(_ n: Int) -> String { ["I", "II", "III", "IV"][max(0, min(3, n - 1))] }

    /// A measurement's grade from its band tag: g1–g4 (MR, AR) or mild, moderate, severe (TR, PR).
    static func quantLevel(_ tag: String?) -> Int? {
        if let t = tag, t.hasPrefix("g"), let n = Int(t.dropFirst()) { return n }
        return level(tag)
    }

    static func describe(_ w: FlowWalk, _ id: String, _ v: Double, _ n: Int, scale: Int) -> String {
        let s = w.flow.step(id)
        let word = scale == 4 ? "grade \(roman(n))" : ["mild", "moderate", "severe"][max(0, min(2, n - 1))]
        return "\(s?.short ?? s?.title ?? id) \(fmt(v))\(unitSuffix(s?.unit)), \(word)"
    }

    /// EROA (the lesion) against the volumes (regurgitant volume and fraction as one measure, the higher of the two).
    /// Equal or one grade apart: the higher; two or more apart: a disagreement, unless one of them leads.
    static func lesionAndVolume(_ w: FlowWalk, order: [String], lesion: String, volumes: [String], scale: Int, lead: String?, why: String) -> Measure {
        var got: [String: (v: Double, n: Int)] = [:]
        for id in order {
            let g = w.take(id)
            if g == .pending { return .ask(id) }
            if let v = g.number, let n = quantLevel(g.tag) { got[id] = (v, n) }
        }
        let text = order.compactMap { id in got[id].map { describe(w, id, $0.v, $0.n, scale: scale) } }.joined(separator: "; ")
        let vols = volumes.compactMap { got[$0]?.n }
        if let lo = vols.min(), let hi = vols.max(), hi - lo >= 2 {
            w.caution("The regurgitant volume and fraction differ by two grades or more: the fraction depends on the total stroke volume, so low or high flow splits them (Table 8).")
        }
        let l = got[lesion]?.n, vol = vols.max()
        switch (l, vol) {
        case (nil, nil): return .none
        case let (x?, nil): return .grade(x, text)
        case let (nil, y?): return .grade(y, text)
        case let (x?, y?):
            if x == y { return .grade(x, text) }
            if lead == "lesion" { w.caution(why); return .grade(x, text) }
            if lead == "volume" { w.caution(why); return .grade(y, text) }
            if Swift.abs(x - y) >= 2 { return .split(text) }
            w.caution("EROA and the volumes differ by one grade: the higher is taken. Low or high flow can split them (Table 8).")
            return .grade(max(x, y), text)
        }
    }

    static func mitralRegurgitation(_ w: FlowWalk) -> FlowEnd {
        if w.tee {
            w.caution("Grading is best done on the awake TTE: under anesthesia lower loading conditions make MR, secondary MR especially, look less severe (2020 TEE guideline, pp. 695, 698; ASE 2017, p. 323). Prefer the preoperative grade, record blood pressure, heart rate and rhythm, and try fluids, inotropes or an afterload challenge before deciding on the intraoperative findings (ASE 2017, p. 324; 2020, p. 698).")
        }
        let t = w.take("type")
        if t == .pending { return .ask("type") }
        let acute = t.choice == "acute", secondary = t.choice == "secondary"
        if acute { w.caution("Acute MR: Figure 18 and Table 8 are for chronic MR. Acute severe MR can have a small, brief, eccentric low-velocity jet with normal chamber sizes; pulmonary vein systolic reversal is usually present; keep a low threshold for TEE (pp. 323, 334).") }
        if secondary { w.caution("Secondary MR: 2D PISA underestimates an elliptical orifice, an EROA of 0.30 cm² or more may still be severe, and the volumes run lower when the stroke volume is low (p. 334).") }
        if w.answers["jet"] == .choice("eccentric") { w.caution("Eccentric, wall-impinging jet: its color area underestimates the MR; quantitation is advised (Figure 18).") }
        let partial = w.answers["cw"] == .choice("partial")
        if partial { w.caution("MR that is not holosystolic: single-frame EROA and vena contracta overestimate it; the regurgitant volume is the better measure (Figure 18; p. 323).") }
        let plan = RegurgPlan(
            criteria: ["flail", "jet", "cw", "vc", "pisa", "pv", "inflow", "size"],
            need: 4,
            scale: 4,
            acute: acute,
            specific: { id, g in
                if acute && id == "size" { return nil }
                return g.tag == "mild" ? 1 : (g.tag == "severe" ? 3 : nil)
            },
            measure: { w in
                lesionAndVolume(w, order: ["eroa", "rvol", "rf"], lesion: "eroa", volumes: ["rvol", "rf"], scale: 4,
                                lead: partial ? "volume" : (secondary ? "lesion" : nil),
                                why: partial ? "Not holosystolic: the regurgitant volume leads, since single-frame EROA overestimates (Figure 18; p. 323)." : "Secondary MR: EROA leads, since the volumes run lower when the stroke volume is low (p. 334).")
            },
            gradeThree: { w, severe, vars in
                var v = vars
                if severe >= 3 { v["why"] = "\(severe) specific criteria for severe MR"; return .done("grade3-severe", v) }
                let e = w.take("ellipse")
                if e == .pending { return .ask("ellipse") }
                if e.choice == "yes" { v["why"] = "an elliptical regurgitant orifice"; return .done("grade3-severe", v) }
                return .done("grade3", v)
            }
        )
        return regurgitation(w, plan)
    }

    static func aorticRegurgitation(_ w: FlowWalk) -> FlowEnd {
        if w.tee {
            w.caution("Loading conditions and LV and aortic compliance change the AR signs under anesthesia (2020 TEE guideline, p. 703); record blood pressure and heart rate with the numbers (ASE 2017, p. 318).")
        }
        let t = w.take("type")
        if t == .pending { return .ask("type") }
        let acute = t.choice == "acute"
        if acute { w.caution("Acute AR: the jet may be brief and of low velocity, the LV is not yet dilated, the mitral valve may close early and the aortic reversal may not be holodiastolic; keep a low threshold for TEE (pp. 336, 345).") }
        let plan = RegurgPlan(
            criteria: ["flail", "vc", "jet", "pisa", "cw", "pht", "aorta", "lv"],
            need: 4,
            scale: 4,
            acute: acute,
            specific: { id, g in
                if acute && id == "lv" { return nil }
                return g.tag == "mild" ? 1 : (g.tag == "severe" ? 3 : nil)
            },
            measure: { w in
                lesionAndVolume(w, order: ["rvol", "rf", "eroa"], lesion: "eroa", volumes: ["rvol", "rf"], scale: 4, lead: nil, why: "")
            },
            gradeThree: { _, severe, vars in
                if severe >= 3 { return .done("grade3-severe", vars) }
                return .done("grade3", vars)
            }
        )
        return regurgitation(w, plan)
    }
}

// MARK: - Mitral stenosis (ASE 2023 rheumatic heart disease, Table 1; EAE/ASE 2009)

extension ValveFlow {
    /// 1 mild, 2 moderate, 3 severe for a band or option tag.
    static func level(_ tag: String?) -> Int? {
        switch tag {
        case "mild"?: return 1
        case "moderate"?: return 2
        case "severe"?: return 3
        default: return nil
        }
    }

    static func mitralStenosis(_ w: FlowWalk) -> FlowEnd {
        if w.tee {
            w.caution("Flow and heart rate change under general anesthesia, and the gradient and half-time with them (2020 TEE guideline, p. 696); planimetry does not depend on flow (2009, p. 12). Record the heart rate and rhythm with the numbers.")
        }
        let e = w.take("etiology")
        if e == .pending { return .ask("etiology") }
        if e.choice == "calcific" {
            let g = w.take("mg")
            if g == .pending { return .ask("mg") }
            let p = w.take("pasp")
            if p == .pending { return .ask("pasp") }
            guard let m = g.number, let n = level(g.tag) else { return .done("calcific-nograd") }
            return .done("calcific-\(n)", ["mg": fmt(m), "pasp": p.number.map { ", PA systolic pressure \(fmt($0)) mmHg" } ?? ""])
        }
        let p = w.take("planimetry")
        if p == .pending { return .ask("planimetry") }
        let h = w.take("pht")
        if h == .pending { return .ask("pht") }
        let g = w.take("mg")
        if g == .pending { return .ask("mg") }
        let pa = w.take("pasp")
        if pa == .pending { return .ask("pasp") }
        var area: Int?
        var basis = ""
        if let x = p.number, let n = level(p.tag) {
            area = n
            basis = "planimetered area (\(fmt(x)) cm²)"
            if let y = h.number, let hn = level(h.tag), hn != n {
                w.caution("Planimetry and the half-time disagree (half-time area about \(fmt(220 / y)) cm²): planimetry is the reference, except with poor acoustic windows (2009, p. 15).")
            }
        } else if let y = h.number, let n = level(h.tag) {
            area = n
            basis = "pressure half-time (\(fmt(y)) ms, area about \(fmt(220 / y)) cm²)"
        } else {
            let a = w.take("alt")
            if a == .pending { return .ask("alt") }
            if let x = a.number, let n = level(a.tag) {
                area = n
                basis = "continuity or PISA area (\(fmt(x)) cm²)"
                w.caution("Graded on a second-line area: the continuity equation and PISA are for inconclusive data and carry more error (2023, p. 9).")
            }
        }
        guard let ag = area else {
            var supp: [String] = []
            if let m = g.number { supp.append("Mean gradient \(fmt(m)) mmHg.") }
            if let s = pa.number { supp.append("PA systolic pressure \(fmt(s)) mmHg.") }
            return supp.isEmpty ? .done("nodata") : .done("supportive-only", ["supp": supp.joined(separator: " ")])
        }
        if [g.tag, pa.tag].compactMap(level).contains(3) && ag < 3 {
            w.caution("Gradient or PA pressure in the severe range with a non-severe area: high flow, tachycardia, significant MR or another cause of pulmonary hypertension (2023, p. 8).")
        }
        if ag == 3 && level(g.tag) == 1 {
            w.caution("Severe by area with a low gradient: low flow, where planimetry is essential (2020 TEE guideline, p. 696).")
        }
        return .done(["mild", "moderate", "severe"][ag - 1], ["basis": basis])
    }
}

// MARK: - Pulmonic stenosis (EAE/ASE 2009, Table 11)

extension ValveFlow {
    static func pulmonicStenosis(_ w: FlowWalk) -> FlowEnd {
        if w.tee { w.caution("Loading conditions and Doppler misalignment change the gradient (2020 TEE guideline, p. 706).") }
        let l = w.take("level")
        if l == .pending { return .ask("level") }
        switch l.choice {
        case "sub"?: w.caution("Infundibular obstruction is often dynamic, with a late-peaking, dagger-shaped jet; the grading table is for valvular stenosis (2009, p. 20).")
        case "supra"?: w.caution("Supra- or subvalvular obstruction: the valve cutoffs assume there is none (2023, p. 20).")
        case "serial"?: w.caution("Stenoses in series: their contributions cannot be separated, and pressure recovery can make the Doppler gradient higher than the net pressure drop (2009, p. 20).")
        default: break
        }
        let v = w.take("vmax")
        if v == .pending { return .ask("vmax") }
        guard let x = v.number, let tag = v.tag else { return .done("nodata") }
        let gradient = 4 * x * x
        let where_ = l.choice == "sub" ? "below the valve (infundibular)" : (l.choice == "supra" ? "above the valve or in the branches" : nil)
        let r = w.take("rvsp")
        if r == .pending { return .ask("rvsp") }
        var pa = ""
        if let rv = r.number {
            let est = rv - gradient
            pa = est > 0
                ? " RV systolic pressure \(fmt(rv)) mmHg minus the valve gradient leaves a PA systolic pressure of about \(fmt(est)) mmHg (2009, p. 20)."
                : " The valve gradient is higher than the RV systolic pressure entered: recheck both (2009, p. 20)."
        }
        if let place = where_ { return .done("nonvalvular", ["v": fmt(x), "gradient": fmt(gradient), "where": place, "pa": pa]) }
        return .done(tag, ["gradient": fmt(gradient), "pa": pa])
    }
}

// MARK: - Aortic prosthesis with a high velocity or gradient (ASE 2024, Tables 5 and 7)

extension ValveFlow {
    static func aorticProsthesis(_ w: FlowWalk) -> FlowEnd {
        if w.tee { w.caution("On TEE the anterior root can be shadowed, and transgastric Doppler angulation may not be optimal: the gradient can read low (ASE 2024, p. 17).") }
        let k = w.take("kind")
        if k == .pending { return .ask("kind") }
        let tavr = k.choice == "tavr"
        let depIds = tavr ? ["vmax", "mgchange"] : ["vmax", "mg"]
        let indepIds = tavr ? ["dvichange", "eoachange"] : ["dvi", "eoa"]
        let order = ["vmax", "contour", "at", "atet"] + (tavr ? ["mgchange", "dvichange", "eoachange"] : ["mg", "dvi", "eoa"])
        var got: [String: FlowWalk.Got] = [:]
        for id in order {
            let g = w.take(id)
            if g == .pending { return .ask(id) }
            got[id] = g
        }
        func names(_ ids: [String], _ tag: String) -> [String] {
            ids.filter { got[$0]?.tag == tag }.map { w.flow.step($0)?.short ?? w.flow.step($0)?.title ?? $0 }
        }
        let depSig = names(depIds, "severe"), depMid = names(depIds, "moderate")
        let indepSig = names(indepIds, "severe"), indepMid = names(indepIds, "moderate")
        let depKnown = depIds.contains { got[$0]?.tag != nil }, indepKnown = indepIds.contains { got[$0]?.tag != nil }
        let tags = order.compactMap { got[$0]?.tag }
        let counts = "\(tags.filter { $0 == "normal" }.count) normal, \(tags.filter { $0 == "moderate" }.count) possible, \(tags.filter { $0 == "severe" }.count) significant"
        guard depKnown || indepKnown else { return .done("nodata") }
        if !depSig.isEmpty && !indepSig.isEmpty {
            return .done("significant", ["dep": depSig.joined(separator: ", "), "indep": indepSig.joined(separator: ", ")])
        }
        if !indepSig.isEmpty && depSig.isEmpty && depMid.isEmpty {
            return .done("lowflow", ["indep": indepSig.joined(separator: ", "), "deptext": depKnown ? "the velocity and gradient are not high" : "no velocity or gradient was obtained"])
        }
        let depHigh = depSig + depMid
        if !depHigh.isEmpty && indepKnown && indepSig.isEmpty && indepMid.isEmpty {
            if ["contour", "at", "atet"].contains(where: { got[$0]?.tag == "severe" }) {
                w.caution("A rounded jet or a long acceleration time points to obstruction despite the normal EOA and DVI: recheck the LVOT sample and diameter (Table 5; Figure 13).")
            }
            let dep = ["dep": depHigh.joined(separator: ", ")]
            let lf = w.take("leaflets")
            if lf == .pending { return .ask("leaflets") }
            if lf.choice == "abnormal" { return .done("leaflet", dep) }
            // Mismatch needs a normally functioning valve and an EOA within 1 SD of the reference (Table 7).
            let eoaOK = tavr ? got["eoachange"]?.choice == "ok" : got["eoa"]?.choice == "ok"
            guard lf.choice == "normal", eoaOK else { return .done("highflow", dep) }
            let b = w.take("bmi")
            if b == .pending { return .ask("bmi") }
            let i = w.take("ieoa")
            if i == .pending { return .ask("ieoa") }
            guard let x = i.number, b.choice != nil else { return .done("highflow", dep) }
            let obese = b.choice == "ge30"
            let severeCut = obese ? 0.55 : 0.65, moderateCut = obese ? 0.70 : 0.85
            if x <= severeCut { return .done("ppm-severe", ["ieoa": fmt(x)]) }
            if x <= moderateCut { return .done("ppm-moderate", ["ieoa": fmt(x)]) }
            return .done("ppm-none", ["ieoa": fmt(x)])
        }
        if !depSig.isEmpty && !indepKnown {
            w.caution("No flow-independent measure (EOA or DVI): Table 5 needs one to call the stenosis significant.")
        }
        if tags.contains("severe") || tags.contains("moderate") { return .done("possible", ["counts": counts]) }
        // Normal needs one normal measure of each kind: a single parameter is not enough (ASE 2024, p. 17).
        let depNormal = depIds.contains { got[$0]?.tag == "normal" }, indepNormal = indepIds.contains { got[$0]?.tag == "normal" }
        return .done(depNormal && indepNormal ? "normal" : "insufficient", ["counts": counts])
    }
}

// MARK: - Tricuspid and pulmonic regurgitation (ASE 2017, Figures 31 and 35)

extension ValveFlow {
    static func tricuspidRegurgitation(_ w: FlowWalk) -> FlowEnd {
        if w.tee {
            w.caution("TEE is in general more limited than TTE for the tricuspid valve, from off-angle planes and the distance from the probe (ASE 2017, p. 345); loading conditions and inotropes change the TR (2020 TEE guideline, pp. 700, 705).")
        }
        if w.answers["jet"] == .choice("eccentric") { w.caution("Eccentric, wall-impinging jet: its area underestimates the TR (p. 350).") }
        let plan = RegurgPlan(
            criteria: ["valve", "jet", "cw", "vc", "pisa", "hv", "inflow", "size"],
            need: 4,
            scale: 3,
            specific: { _, g in g.tag == "mild" ? 1 : (g.tag == "severe" ? 3 : nil) },
            measure: { w in
                // The vena contracta leads (Figure 31); EROA and volume by PISA come from one radius and count once.
                let vc = w.take("vc")
                var parts: [String] = []
                var vcGrade: Int?
                if let v = vc.number {
                    let n = vc.tag == "mild" ? 1 : (vc.tag == "severe" ? 3 : 2)
                    vcGrade = n
                    parts.append(describe(w, "vc", v, n, scale: 3))
                }
                var pisa: [Int] = []
                for id in ["eroa", "rvol"] {
                    let g = w.take(id)
                    if g == .pending { return .ask(id) }
                    if let v = g.number, let n = level(g.tag) { pisa.append(n); parts.append(describe(w, id, v, n, scale: 3)) }
                }
                let text = parts.joined(separator: "; ")
                switch (vcGrade, pisa.max()) {
                case (nil, nil): return .none
                case let (x?, nil): return .grade(x, text)
                case let (nil, y?): return .grade(y, text)
                case let (x?, y?):
                    if y > x {
                        w.caution("PISA reads higher than the vena contracta: the higher grade is taken (Figure 31).")
                        return .grade(y, text)
                    }
                    if y < x { w.caution("PISA reads lower than the vena contracta, which leads: 2D PISA flattens and underestimates TR flow (pp. 350, 352).") }
                    return .grade(x, text)
                }
            }
        )
        return regurgitation(w, plan)
    }

    static func pulmonicRegurgitation(_ w: FlowWalk) -> FlowEnd {
        if w.tee {
            w.caution("The pulmonic valve is anterior and hard to image by TEE, and TEE is not a preferred modality when PR needs more than the TTE (ASE 2017, pp. 353, 359); loading conditions change the signs (2020 TEE guideline, p. 706).")
        }
        let softJet = w.answers["cw"] == .choice("soft")
        let plan = RegurgPlan(
            criteria: ["jet", "rv", "ratio", "cw", "pht", "decel", "branches"],
            need: 3,
            scale: 3,
            minAssessed: 3,
            noQuant: "probable-moderate",
            specific: { id, g in
                // Figure 35's criterion is a dense jet with a half-time under 100 ms.
                if id == "pht" && softJet { return nil }
                return g.tag == "mild" ? 1 : (g.tag == "severe" ? 3 : nil)
            },
            measure: { w in
                let g = w.take("rf")
                if g == .pending { return .ask("rf") }
                guard let v = g.number, let n = level(g.tag) else { return .none }
                return .grade(n, describe(w, "rf", v, n, scale: 3))
            }
        )
        return regurgitation(w, plan)
    }
}
