import Foundation

// MARK: - Valve severity, one step at a time
//
// The grading documents' own sequences as workflows: each step asks for one measurement or sign, "Cannot
// obtain" moves on, and the flow ends as soon as the guideline's criteria settle the grade. The words, views
// and cutoffs of every step live in reference.json ("valveFlows"), so a correction reaches the app without an
// update; the order of the steps and the integration rules live here and in src/reference-logic.js
// (R.valveFlow), and both are run against the same cases (tools/valve_flow_cases.json).

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
    var ref: String?
    var steps: [ValveFlowStep]
    var results: [String: ValveFlowResultDef]
    var notes: [String]?

    func step(_ id: String) -> ValveFlowStep? { steps.first { $0.id == id } }
}

struct ValveFlowStep: Codable, Hashable, Identifiable {
    var id: String
    var title: String
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

    init(_ flow: ValveFlowDef, _ answers: [String: FlowAnswer], tee: Bool = false) {
        self.flow = flow
        self.answers = answers
        self.tee = tee
    }

    /// The answer to a step, recorded on the path. A step the content lacks reads as not obtainable, and an
    /// answer of the wrong kind (a stale option) as not answered.
    func take(_ id: String) -> Got {
        guard let s = flow.step(id) else { return .cannot }
        guard let a = answers[id] else { return .pending }
        switch a {
        case .cannot:
            path.append(FlowRecord(step: s, answer: a, tag: nil, text: "Cannot obtain"))
            return .cannot
        case .number(let v):
            guard s.isNumber, v.isFinite else { return .pending }
            let band = s.bands?.first { $0.contains(v) }
            let reading = band?.label ?? s.between
            let text = ValveFlow.fmt(v) + (s.unit.map { $0.isEmpty ? "" : " " + $0 } ?? "") + (reading.map { " · " + $0 } ?? "")
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
    static let rules: [String: Rule] = [:]

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

    static func fmt(_ v: Double) -> String { PedsCalc.fmt(v) }
}
