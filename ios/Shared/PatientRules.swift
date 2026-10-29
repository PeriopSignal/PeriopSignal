import Foundation

// MARK: - Rules that read My Patient: the ASA suggestion, score pre-fills, prompts and the handoff text.

struct AsaSuggestion: Hashable {
    var level: Int
    /// The findings that set it, highest class first ("COPD: ASA III example").
    var reasons: [String]
    var emergency: Bool
    var label: String { "ASA " + PatientRules.roman(level) + (emergency ? "E" : "") }
}

/// A test or tool the record suggests opening next.
struct PatientPrompt: Hashable, Identifiable {
    var id: String
    var title: String
    var why: String
    /// RefRoute key ("score:rcri", "airway", "neuraxial", "quickref:mhaus-mh").
    var route: String
    /// Done: the saved result's one-line summary.
    var done: String?
}

enum PatientRules {
    static func roman(_ n: Int) -> String {
        let r = ["", "I", "II", "III", "IV", "V", "VI"]
        return n >= 0 && n < r.count ? r[n] : "\(n)"
    }

    private static func f(_ v: Double) -> String { PedsCalc.fmt(v) }

    // MARK: ASA

    /// The highest class among the ASA's adult examples that the record matches, with E for an emergency. None for
    /// a child (the pediatric examples differ) or when nothing is recorded and "no significant history" is not set.
    static func asaSuggestion(_ r: PatientRecord) -> AsaSuggestion? {
        guard !r.isChild else { return nil }
        var found: [(Int, String)] = []
        for p in PatientCatalog.allProblems where r.problems.contains(p.id) {
            if let a = p.asa { found.append((a, p.label + ": ASA " + roman(a) + " example (" + (p.asaExample ?? p.label) + ")")) }
        }
        if let b = r.bmi {
            if b >= 40 { found.append((3, "BMI " + f(b) + ": ASA III example (morbid obesity, BMI ≥40)")) }
            else if b > 30 { found.append((2, "BMI " + f(b) + ": ASA II example (obesity, 30 < BMI < 40)")) }
        }
        if r.smoking == "current" { found.append((2, "Current smoker: ASA II example")) }
        guard let top = found.map(\.0).max() else {
            return r.noHistory ? AsaSuggestion(level: 1, reasons: ["No systemic disease recorded: ASA I is a normal healthy patient"], emergency: r.emergency) : nil
        }
        let reasons = found.sorted { $0.0 > $1.0 }.map(\.1)
        return AsaSuggestion(level: top, reasons: reasons, emergency: r.emergency)
    }

    /// The class to show: the clinician's choice, with E from their choice or from the urgency.
    static func asaText(_ r: PatientRecord) -> String? {
        guard let c = r.asaClass else { return nil }
        return "ASA " + roman(c) + ((r.asaE ?? r.emergency) ? "E" : "")
    }

    // MARK: Score pre-fills

    /// The answers the record already gives for a score, so the calculator opens with them ticked.
    static func prefill(_ scoreId: String, _ r: PatientRecord) -> ScoreSelection {
        var s = ScoreSelection()
        let fromProblems = { (key: KeyPath<PatientProblem, String?>) -> Set<String> in
            Set(PatientCatalog.allProblems.filter { r.problems.contains($0.id) }.compactMap { $0[keyPath: key] })
        }
        switch scoreId {
        case "rcri":
            var on = fromProblems(\.rcri)
            if r.highRiskSurgery { on.insert("surgery") }
            if r.medFlags.contains("insulin") && (r.has("dm") || r.has("dm-poor") || r.has("insulin")) { on.insert("insulin") }
            if let cr = r.labs["cr"], cr > 2.0 { on.insert("creatinine") }
            s.on = on
        case "ariscat":
            if let a = r.ageYears { s.choices["age"] = a <= 50 ? "≤ 50" : (a <= 80 ? "51–80" : "> 80") }
            if let o = r.vitals["spo2"] { s.choices["spo2"] = o >= 96 ? "≥ 96%" : (o > 90 ? "91–95%" : "≤ 90%") }
            if r.has("uri") { s.on.insert("infection") }
            if let hb = r.labs["hb"], hb <= 10 { s.on.insert("anemia") }
            if let i = r.incision { s.choices["incision"] = i }
            if let d = r.duration { s.choices["duration"] = d }
            if r.emergency { s.on.insert("emergency") }
        case "stopbang":
            s.on = fromProblems(\.stopBang)
            if let b = r.bmi, b > 35 { s.on.insert("bmi") }
            if let a = r.ageYears, a > 50 { s.on.insert("age") }
            if r.airwaySigns.contains("neck40") { s.on.insert("neck") }
            if r.sex == .male { s.on.insert("gender") }
        case "apfel":
            if r.sex == .female { s.on.insert("female") }
            if let sm = r.smoking, sm != "current" { s.on.insert("nonsmoker") }
            if r.anesthesiaHistory.contains("ponv") { s.on.insert("history") }
        default: break
        }
        return s
    }

    /// "RCRI 1 · Class II · 1 predictor": a saved result in one line.
    static func scoreLine(_ id: String, _ sc: PatientScore) -> String {
        let name = Scores.byID(id)?.short ?? id.uppercased()
        var s = name + (sc.points.map { " \($0)" } ?? "")
        if let l = sc.label { s += " · " + l }
        return s
    }

    // MARK: Prompts

    static func prompts(_ r: PatientRecord) -> [PatientPrompt] {
        var out: [PatientPrompt] = []
        func score(_ id: String, _ why: String) {
            out.append(PatientPrompt(id: id, title: Scores.byID(id)?.name ?? id, why: why, route: "score:" + id, done: r.scores[id].map { scoreLine(id, $0) }))
        }
        if r.isAdult {
            score("rcri", "Cardiac risk before noncardiac surgery")
            score("ariscat", "Postoperative pulmonary complications")
            score("stopbang", "Obstructive sleep apnea screen")
            if r.anesthetic.isEmpty || r.anesthetic.contains("ga") { score("apfel", "Nausea and vomiting risk, with the prophylaxis plan") }
        }
        let blocks = r.anesthetic.contains("neuraxial") || r.anesthetic.contains("regional")
        if blocks && (r.medFlags.contains("anticoagulant") || r.medFlags.contains("p2y12")) {
            out.append(PatientPrompt(id: "neuraxial", title: "Anticoagulant timing", why: "A block is planned with an anticoagulant or P2Y12 inhibitor listed (ASRA)", route: "neuraxial", done: nil))
        }
        if r.lastSolids != nil || r.lastClears != nil || r.medFlags.contains("glp1") {
            out.append(PatientPrompt(id: "fasting", title: "Fasting check", why: r.medFlags.contains("glp1") ? "GLP-1 receptor agonist listed" : "Last intake recorded", route: "fasting", done: nil))
        }
        if airwayPredictors(r).count >= 2 || r.anesthesiaHistory.contains("difficult-airway") {
            out.append(PatientPrompt(id: "airway", title: "Airway guide", why: "Difficult-airway predictors recorded", route: "airway", done: nil))
        }
        if r.anesthesiaHistory.contains("mh") {
            out.append(PatientPrompt(id: "mh", title: "Malignant hyperthermia", why: "Personal or family history: plan a trigger-free anesthetic", route: "quickref:mhaus-mh", done: nil))
        }
        if r.has("as") || r.has("mr") || r.has("valve-severe") || r.has("prosthetic-valve") {
            out.append(PatientPrompt(id: "valves", title: "Valve grading", why: "Valve disease recorded", route: "valves", done: nil))
        }
        return out
    }

    // MARK: Airway

    /// The airway signs recorded, with Mallampati III–IV and the history items counted in.
    static func airwayPredictors(_ r: PatientRecord) -> [String] {
        var out = PatientAirway.signs.filter { r.airwaySigns.contains($0.id) }.map(\.label)
        if let m = r.mallampati, m >= 3 { out.insert("Mallampati " + roman(m), at: 0) }
        if r.anesthesiaHistory.contains("difficult-airway") { out.insert("Known difficult airway", at: 0) }
        if r.has("osa") { out.append("Obstructive sleep apnea") }
        if let b = r.bmi, b >= 30 { out.append("BMI " + f(b)) }
        return out
    }

    // MARK: Fluids

    static func fluidLine(_ r: PatientRecord, ids: [String]) -> String? {
        let parts = PatientCatalog.fluids.filter { ids.contains($0.id) }.compactMap { fl -> String? in
            guard let v = r.fluids[fl.id], v > 0 else { return nil }
            let unit = fl.unit == "units" ? (v == 1 ? "unit" : "units") : fl.unit
            return fl.label + " " + f(v) + " " + unit
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }
}

/// The airway examination's findings, grouped as the exam is done.
enum PatientAirway {
    static let signs: [PatientFlag] = [
        PatientFlag("mouth", "Mouth opening under 3 cm", "Interincisor distance"),
        PatientFlag("tmd", "Thyromental distance under 6 cm"),
        PatientFlag("neck", "Limited neck extension"),
        PatientFlag("jaw", "Cannot protrude the lower jaw", "Upper lip bite test class III"),
        PatientFlag("incisors", "Prominent upper incisors"),
        PatientFlag("palate", "High-arched or narrow palate"),
        PatientFlag("thick-neck", "Short, thick neck"),
        PatientFlag("neck40", "Neck circumference over 40 cm"),
        PatientFlag("beard", "Beard"),
        PatientFlag("edentulous", "No teeth"),
        PatientFlag("radiation", "Neck radiation changes"),
        PatientFlag("mass", "Airway mass, tumor, abscess or swelling"),
        PatientFlag("stridor", "Stridor or voice change"),
    ]

    /// Modified Mallampati (Samsoon and Young): what is visible with the mouth open and the tongue out.
    static func mallampati(_ n: Int) -> String {
        switch n {
        case 1: return "Soft palate, fauces, uvula and pillars"
        case 2: return "Soft palate, fauces and uvula"
        case 3: return "Soft palate and the base of the uvula"
        default: return "Hard palate only"
        }
    }
}
