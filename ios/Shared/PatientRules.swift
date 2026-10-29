import Foundation

// MARK: - Rules that read My Patient: the ASA suggestion, score pre-fills, prompts and the handoff text.

struct AsaSuggestion: Hashable {
    var level: Int
    /// The findings that set it, highest class first.
    var reasons: [AsaReason]
    var emergency: Bool
    var label: String { "ASA " + PatientRules.roman(level) + (emergency ? "E" : "") }
    /// The findings at the suggested class ("Coronary disease or MI, over 3 months; COPD").
    var topFindings: [String] { reasons.filter { $0.level == level }.map(\.finding) }
}

/// One recorded finding and the ASA example class it matches.
struct AsaReason: Hashable {
    /// What is recorded: "COPD", "BMI 41.2".
    var finding: String
    var level: Int
    /// The ASA's example, when it says more than the finding: "history (>3 months) of MI, CVA, TIA, or CAD/stents".
    var example: String?
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

    private static func f(_ v: Double) -> String { NumText.short(v) }

    // MARK: ASA

    /// The highest class among the ASA's adult examples that the record matches, with E for an emergency. None for
    /// a child (the pediatric examples differ) or when nothing is recorded and "no significant history" is not set.
    static func asaSuggestion(_ r: PatientRecord) -> AsaSuggestion? {
        guard !r.isChild else { return nil }
        var found: [AsaReason] = []
        /// The example is shown only when it adds to the finding's own words ("COPD" is not repeated).
        func example(_ finding: String, _ ex: String?) -> String? {
            guard let ex, ex.lowercased() != finding.lowercased() else { return nil }
            return ex
        }
        for p in PatientCatalog.allProblems where r.problems.contains(p.id) {
            if let a = p.asa { found.append(AsaReason(finding: p.label, level: a, example: example(p.label, p.asaExample))) }
        }
        if let b = r.bmi {
            let bmi = "BMI " + String(format: "%.1f", b)
            if b >= 40 { found.append(AsaReason(finding: bmi, level: 3, example: "morbid obesity (BMI ≥40)")) }
            else if b > 30 { found.append(AsaReason(finding: bmi, level: 2, example: "obesity (30 < BMI < 40)")) }
        }
        if r.smoking == "current" { found.append(AsaReason(finding: "Current smoker", level: 2, example: nil)) }
        guard let top = found.map(\.level).max() else {
            return r.noHistory ? AsaSuggestion(level: 1, reasons: [AsaReason(finding: "No systemic disease recorded", level: 1, example: "a normal healthy patient")], emergency: r.emergency) : nil
        }
        // Highest class first; the order recorded within a class.
        let reasons = found.enumerated().sorted { $0.element.level != $1.element.level ? $0.element.level > $1.element.level : $0.offset < $1.offset }.map(\.element)
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

    /// The airway signs recorded, with Mallampati III–IV and the history items the ASA's 2022 guideline names
    /// (previous difficult airway, sleep apnea, obesity) counted in.
    static func airwayPredictors(_ r: PatientRecord) -> [String] {
        var out = PatientAirway.signs.filter { r.airwaySigns.contains($0.id) }.map(\.label)
        if let m = r.mallampati, m >= 3 { out.insert("Mallampati " + roman(m), at: 0) }
        if r.anesthesiaHistory.contains("difficult-airway") { out.insert("Known difficult airway", at: 0) }
        if r.has("osa") { out.append("Obstructive sleep apnea") }
        if let b = r.bmi, b >= 30 { out.append("BMI " + String(format: "%.1f", b)) }
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

/// The airway examination's findings, grouped as the exam is done. Nonreassuring findings from the ASA's
/// examination table (2003 and 2013 difficult-airway guidelines) and the features its 2022 guideline lists; the
/// 2022 guideline gives no cutoffs and finds no single sign consistently more predictive than another.
enum PatientAirway {
    static let signs: [PatientFlag] = [
        PatientFlag("mouth", "Mouth opening under 3 cm", "Interincisor distance"),
        PatientFlag("tmd", "Thyromental distance under 3 fingerbreadths"),
        PatientFlag("smd", "Sternomental distance 12.5 cm or less", "Head fully extended, mouth closed (Savva 1994)"),
        PatientFlag("neck", "Limited neck movement", "Cannot touch chin to chest, or cannot extend the neck"),
        PatientFlag("jaw", "Cannot protrude the jaw", "Lower incisors cannot come in front of the upper incisors"),
        PatientFlag("incisors", "Long or prominent upper incisors"),
        PatientFlag("palate", "High-arched or very narrow palate"),
        PatientFlag("mandible", "Stiff mandibular space", "Indurated, nonresilient or occupied by a mass"),
        PatientFlag("thick-neck", "Short or thick neck"),
        PatientFlag("neck40", "Neck circumference over 40 cm", "The STOP-Bang item"),
        PatientFlag("beard", "Beard"),
        PatientFlag("edentulous", "No teeth"),
        PatientFlag("radiation", "Neck radiation changes"),
        PatientFlag("mass", "Airway mass or obstruction", "Tumor, abscess, swelling or stridor"),
    ]

    /// Modified Mallampati (Samsoon and Young): what is visible with the mouth open and the tongue out.
    static func mallampati(_ n: Int) -> String {
        switch n {
        case 1: return "Soft palate, fauces, uvula and pillars"
        case 2: return "Soft palate, fauces and uvula"
        case 3: return "Soft palate and the base of the uvula"
        default: return "Soft palate not visible"
        }
    }

    /// "Mallampati III: soft palate and the base of the uvula visible".
    static func mallampatiLine(_ n: Int) -> String {
        "Mallampati " + PatientRules.roman(n) + ": " + mallampati(n).lowercased() + (n >= 4 ? "" : " visible")
    }

    /// Langeron 2000's independent predictors of difficult mask ventilation that the record shows: age over 55,
    /// BMI over 26, beard, lack of teeth, snoring. Two or more predicted it (sensitivity 0.72, specificity 0.73).
    static func langeron(_ r: PatientRecord) -> [String] {
        var out: [String] = []
        if let a = r.ageYears, a > 55 { out.append("age over 55") }
        if let b = r.bmi, b > 26 { out.append("BMI over 26") }
        if r.airwaySigns.contains("beard") { out.append("beard") }
        if r.airwaySigns.contains("edentulous") { out.append("no teeth") }
        if r.has("snoring") { out.append("snoring") }
        return out
    }

    /// Kheterpal 2009's independent predictors of impossible mask ventilation that the record shows: neck
    /// radiation changes, male sex, sleep apnea, Mallampati III or IV, beard. Three or more: markedly increased risk.
    static func kheterpal(_ r: PatientRecord) -> [String] {
        var out: [String] = []
        if r.airwaySigns.contains("radiation") { out.append("neck radiation changes") }
        if r.sex == .male { out.append("male") }
        if r.has("osa") { out.append("sleep apnea") }
        if let m = r.mallampati, m >= 3 { out.append("Mallampati " + PatientRules.roman(m)) }
        if r.airwaySigns.contains("beard") { out.append("beard") }
        return out
    }

    /// The mask-ventilation predictions, for adults: "Langeron 3 of 5: age over 55, BMI over 26, snoring".
    static func maskRisk(_ r: PatientRecord) -> [(text: String, alert: Bool)] {
        guard r.isAdult else { return [] }
        var out: [(text: String, alert: Bool)] = []
        let l = langeron(r), k = kheterpal(r)
        if !l.isEmpty {
            out.append(("Difficult mask ventilation: \(l.count) of 5 Langeron predictors (" + l.joined(separator: ", ") + "); 2 or more predicted it.", l.count >= 2))
        }
        if !k.isEmpty {
            out.append(("Impossible mask ventilation: \(k.count) of 5 Kheterpal predictors (" + k.joined(separator: ", ") + "); 3 or more mark a markedly increased risk.", k.count >= 3))
        }
        return out
    }

    /// Han mask-ventilation grades (Han R, et al. Anesthesiology 2004;101:267, as Kheterpal 2006 tabulates them), in
    /// our words; each applies with or without a muscle relaxant.
    static let maskGrades: [(id: String, label: String, detail: String)] = [
        ("1", "1", "Ventilated by mask"),
        ("2", "2", "Ventilated with an oral airway or other adjunct"),
        ("3", "3", "Difficult (inadequate, unstable, or needing two providers)"),
        ("4", "4", "Unable to ventilate by mask"),
    ]
}
