import Foundation

// MARK: - Local anesthetic mixture arithmetic
//
// A block often uses more than one agent. The convention (ASRA/ESRA pediatric recommendations and
// most reviews) treats toxicity as additive: each agent is expressed as a fraction of its own
// maximum, and the fractions are summed; the mixture is within limits while the sum is ≤ 1.
// Exparel (liposomal bupivacaine) adds label rules of its own, checked here as warnings.

struct LAEntry: Hashable, Identifiable {
    var id = UUID()
    var agentID: String
    /// Concentration in percent (0.25 = 0.25% = 2.5 mg/mL).
    var percent: Double
    var mL: Double

    var mg: Double { percent * 10 * mL }
}

struct LAAgentResult: Identifiable, Hashable {
    var id: UUID
    var agent: LocalAnesthetic
    var percent: Double
    var mL: Double
    var mg: Double
    /// This agent's maximum for the patient (mg), or nil when the data has no applicable limit.
    var maxMg: Double?
    var fraction: Double { (maxMg ?? 0) > 0 ? mg / maxMg! : 0 }
    /// Volume of this agent alone at this concentration that would reach its maximum.
    var maxMLAlone: Double? { maxMg.map { $0 / (percent * 10) } }
    /// Volume of this agent that could still be added at this concentration given the whole mixture.
    var remainingML: Double?
}

struct LAMixResult: Hashable {
    var agents: [LAAgentResult]
    /// Sum of fractions; ≤ 1 is within limits.
    var combined: Double
    var warnings: [String]
    var percentUsed: Int { Int((combined * 100).rounded()) }
}

enum LAMixCalc {
    /// Maximum for one agent, in mg. Adults: the label (per-kg figure capped at the absolute maximum,
    /// with or without epinephrine). Children: the pediatric mg/kg, capped at the adult maximum.
    static func maxMg(for agent: LocalAnesthetic, weightKg: Double, pediatric: Bool, epinephrine: Bool, ageYears: Int?) -> Double? {
        guard weightKg > 0 else { return nil }
        if pediatric {
            if let minYears = agent.pedsMinYears, let age = ageYears, age < minYears { return nil }
            var m = agent.maxMgPerKg * weightKg
            if let cap = agent.pedsMaxMg ?? agent.adultPlainMaxMg { m = min(m, cap) }
            return m
        }
        let perKg = epinephrine ? (agent.adultEpiMgPerKg ?? agent.adultPlainMgPerKg) : agent.adultPlainMgPerKg
        let cap = epinephrine ? (agent.adultEpiMaxMg ?? agent.adultPlainMaxMg) : agent.adultPlainMaxMg
        switch (perKg, cap) {
        case let (p?, c?): return min(p * weightKg, c)
        case let (p?, nil): return p * weightKg
        case let (nil, c?): return c
        case (nil, nil): return nil
        }
    }

    static func evaluate(entries: [LAEntry], agents: [LocalAnesthetic], weightKg: Double, pediatric: Bool, epinephrine: Bool, ageYears: Int?) -> LAMixResult {
        let byID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        var results: [LAAgentResult] = []
        for e in entries {
            guard let agent = byID[e.agentID] else { continue }
            let maxMg = maxMg(for: agent, weightKg: weightKg, pediatric: pediatric, epinephrine: epinephrine, ageYears: ageYears)
            results.append(LAAgentResult(id: e.id, agent: agent, percent: e.percent, mL: e.mL, mg: e.mg, maxMg: maxMg, remainingML: nil))
        }
        let combined = results.reduce(0) { $0 + $1.fraction }
        let remainingFraction = max(0, 1 - combined)
        for i in results.indices {
            if let m = results[i].maxMg, results[i].percent > 0 {
                results[i].remainingML = remainingFraction * m / (results[i].percent * 10)
            }
        }

        var warnings: [String] = []
        if combined > 1 {
            warnings.append("The mixture exceeds the combined maximum (\(Int((combined * 100).rounded()))% of the additive limit).")
        }
        for r in results where r.maxMg == nil && r.mg > 0 {
            if pediatric, let minYears = r.agent.pedsMinYears {
                warnings.append("\(r.agent.name) is not labeled under \(minYears) years; no pediatric maximum is applied.")
            } else {
                warnings.append("No maximum is on file for \(r.agent.name) in this setting.")
            }
        }
        let liposomal = results.filter { $0.agent.isLiposomal && $0.mg > 0 }
        if let lipo = liposomal.first {
            let hcl = results.filter { !$0.agent.isLiposomal && $0.agent.id.hasPrefix("bupivacaine") && $0.mg > 0 }.reduce(0) { $0 + $1.mg }
            if hcl > 0.5 * lipo.mg + 0.0001 {
                warnings.append("Bupivacaine HCl (\(fmt(hcl)) mg) exceeds half the Exparel dose (\(fmt(lipo.mg)) mg): the label limits the ratio to 1:2.")
            }
            let others = results.filter { !$0.agent.isLiposomal && !$0.agent.id.hasPrefix("bupivacaine") && $0.mg > 0 }
            if others.contains(where: { $0.agent.id.hasPrefix("lidocaine") }) {
                warnings.append("Give Exparel at least 20 minutes after lidocaine, which otherwise releases bupivacaine from the liposomes.")
            }
            let nonLido = others.filter { !$0.agent.id.hasPrefix("lidocaine") }
            if !nonLido.isEmpty {
                warnings.append("Exparel is not to be mixed with local anesthetics other than bupivacaine HCl, and no other local anesthetic should follow it for 96 hours.")
            } else if hcl == 0 && others.isEmpty {
                warnings.append("After Exparel, no other local anesthetic for 96 hours.")
            }
        }
        if epinephrine && results.contains(where: { $0.agent.isLiposomal && $0.mg > 0 }) {
            warnings.append("Exparel's maximum does not change with epinephrine.")
        }
        return LAMixResult(agents: results, combined: combined, warnings: warnings)
    }

    static func fmt(_ v: Double) -> String { PedsCalc.fmt(v) }
}
