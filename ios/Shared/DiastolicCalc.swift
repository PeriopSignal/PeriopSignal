import Foundation

// MARK: - ASE 2025 diastolic function
//
// Nagueh SF, et al. Recommendations for the Evaluation of LV Diastolic Function by Echocardiography and for
// HFpEF Diagnosis: An Update From the ASE. J Am Soc Echocardiogr 2025;38:537–569.
// Figure 3: filling pressure (LAP) and grade in sinus rhythm, irrespective of LVEF. Figure 2: whether
// diastolic dysfunction is present. Figure 4: moderate or severe mitral annular calcification. Section 15B:
// heart transplant. Where the document's figures and text differ by an equals sign, Figure 3 wins. The
// website runs the same rules (src/reference-logic.js, R.diastolic); the unit tests mirror each other.

enum DiastolicCalc {
    // Cutoffs (Figure 3 unless noted).
    static let eSeptal = 6.0, eLateral = 7.0, eAverage = 6.5          // reduced e′ when ≤
    static let eeSeptal = 15.0, eeLateral = 13.0, eeAverage = 14.0    // increased E/e′ when ≥ (Figure 2: average > 14)
    static let pasp = 35.0, tr = 2.8                                  // increased when ≥
    static let pvsd = 0.67, lars = 18.0, lavi = 34.0, ivrt = 70.0     // S/D ≤, LARS ≤, LAVi >, IVRT ≤
    static let prEdv = 2.0, padp = 16.0, lwave = 50.0, ara = 30.0, valsalva = 50.0
    /// Table 6: age-specific e′, abnormal when below (septal, lateral, average).
    static let ageE: [String: [Double]] = ["20-39": [7, 10, 9], "40-65": [6, 8, 7], ">65": [6, 7, 6.5]]

    struct Input: Hashable {
        var E: Double?, A: Double?, eSeptal: Double?, eLateral: Double?, pasp: Double?, tr: Double?
        var lungDisease = false
        var ageBand: String?
        var pvsd: Double?, lars: Double?, lavi: Double?, ivrt: Double?
        var prEdv: Double?, padp: Double?, lwave: Double?, ara: Double?, valsalva: Double?
        var esr: Double?, lvmi: Double?
        var female = false
    }

    struct Primaries: Hashable {
        var E: Double?, A: Double?, EA: Double?
        var es: Double?, el: Double?, ea: Double?
        var ees: Double?, eel: Double?, eea: Double?
        var v1: Bool?, v2: Bool?, v3: Bool?
        var v3ByTR = false
        var eFlags: [Bool?] = []
    }

    struct Step: Hashable, Identifiable {
        var id: String
        var label: String
        var state: Bool?
        var text: String
    }

    enum LAP: Hashable { case normal, increased, lvedp, unknown }

    struct Presence: Hashable {
        var state: Bool?
        var count: Int
        var supportive: Bool
        var text: String
    }

    struct Reading: Hashable {
        var lap: LAP
        /// 0 normal function, 1–3 the grades; nil when the reading sets filling pressure only.
        var grade: Int?
        var headline: String
        var explanation: String
        var steps: [Step]
        var cautions: [String]
        var primaries: Primaries
        var presence: Presence
    }

    private static func f(_ v: Double) -> String { PedsCalc.fmt(v) }

    static func primaries(_ i: Input) -> Primaries {
        var p = Primaries()
        p.E = i.E; p.A = i.A
        p.es = i.eSeptal; p.el = i.eLateral
        if let s = p.es, let l = p.el { p.ea = (s + l) / 2 }
        if let e = p.E, let a = p.A, a > 0 { p.EA = e / a }
        if let e = p.E {
            if let s = p.es, s > 0 { p.ees = e / s }
            if let l = p.el, l > 0 { p.eel = e / l }
            if let a = p.ea, a > 0 { p.eea = e / a }
        }
        let age = i.ageBand.flatMap { ageE[$0] }
        func low(_ v: Double?, _ cut: Double, _ k: Int) -> Bool? {
            guard let v else { return nil }
            if let age { return v < age[k] }
            return v <= cut
        }
        p.eFlags = [low(p.es, eSeptal, 0), low(p.el, eLateral, 1), low(p.ea, eAverage, 2)]
        p.v1 = p.eFlags.allSatisfy { $0 == nil } ? nil : p.eFlags.contains(true)
        let r: [Bool?] = [p.ees.map { $0 >= eeSeptal }, p.eel.map { $0 >= eeLateral }, p.eea.map { $0 >= eeAverage }]
        p.v2 = r.allSatisfy { $0 == nil } ? nil : r.contains(true)
        if !i.lungDisease {
            if let pa = i.pasp { p.v3 = pa >= pasp; p.v3ByTR = false }
            else if let t = i.tr { p.v3 = t >= tr; p.v3ByTR = true }
        }
        return p
    }

    static func presence(_ i: Input, _ p: Primaries) -> Presence {
        guard let v1 = p.v1 else { return Presence(state: nil, count: 0, supportive: false, text: "Needs e′") }
        let markers: [Bool?] = [
            p.eea.map { $0 > eeAverage },
            i.lars.map { $0 <= lars },
            p.EA.map { $0 <= 0.8 || $0 >= 2 },
            i.lavi.map { $0 > lavi },
        ]
        let n = markers.filter { $0 == true }.count
        let present = (v1 && n >= 1) || (!v1 && n >= 2)
        let supportive = i.lvmi.map { i.female ? $0 > 95 : $0 > 115 } ?? false
        let text: String
        if present { text = "Present: " + (v1 ? "reduced e′ with " : "normal e′ with ") + "\(n) marker" + (n == 1 ? "" : "s") }
        else { text = "Criteria not met (" + (v1 ? "reduced e′, no marker" : "normal e′, \(n) marker" + (n == 1 ? "" : "s")) + ")" }
        return Presence(state: present, count: n, supportive: supportive, text: text)
    }

    /// One supplemental or second-line sign: true (present), false (absent) or nil (not entered, or not decisive).
    struct Sign: Hashable { var id: String; var label: String; var v: Bool?; var text: String? }

    /// The supplemental signs (S/D, LARS, LAVi, IVRT) and the second-line ones. A pulmonary vein S/D above 0.67 is
    /// not taken as evidence of normal LAP: with a normal LVEF the ratio can exceed 0.67 despite raised filling
    /// pressure (2025, p. 554).
    static func signs(_ i: Input) -> (first: [Sign], second: [Sign]) {
        let first = [
            Sign(id: "pvsd", label: "Pulmonary vein S/D ≤ 0.67", v: i.pvsd.flatMap { $0 <= pvsd ? true : nil },
                 text: i.pvsd.map { f($0) + ($0 > pvsd ? " · not decisive with a normal LVEF" : "") }),
            Sign(id: "lars", label: "LA reservoir strain ≤ 18%", v: i.lars.map { $0 <= lars }, text: i.lars.map { f($0) + "%" }),
            Sign(id: "lavi", label: "LA volume index > 34 mL/m²", v: i.lavi.map { $0 > lavi }, text: i.lavi.map { f($0) + " mL/m²" }),
            Sign(id: "ivrt", label: "IVRT ≤ 70 ms", v: i.ivrt.map { $0 <= ivrt }, text: i.ivrt.map { f($0) + " ms" }),
        ]
        let second = [
            Sign(id: "predv", label: "PR end-diastolic velocity ≥ 2 m/s", v: i.prEdv.map { $0 >= prEdv }, text: i.prEdv.map { f($0) + " m/s" }),
            Sign(id: "padp", label: "PA diastolic pressure ≥ 16 mmHg", v: i.padp.map { $0 >= padp }, text: i.padp.map { f($0) + " mmHg" }),
            Sign(id: "lwave", label: "Mitral L-wave ≥ 50 cm/s", v: i.lwave.map { $0 >= lwave }, text: i.lwave.map { f($0) + " cm/s" }),
            Sign(id: "ara", label: "Ar − A > 30 ms", v: i.ara.map { $0 > ara }, text: i.ara.map { f($0) + " ms" }),
            Sign(id: "valsalva", label: "E/A falls ≥ 50% with Valsalva", v: i.valsalva.map { $0 >= valsalva }, text: i.valsalva.map { f($0) + "%" }),
        ]
        return (first, second)
    }

    static let head: [Int: String] = [0: "Normal Diastolic Function", 1: "Grade 1 Diastolic Dysfunction",
                                      2: "Grade 2 Diastolic Dysfunction", 3: "Grade 3 Diastolic Dysfunction"]

    /// Figure 3 for one set of main variables (all three known); `why` leaves out the E/A sentence.
    private struct Core { var lap: LAP; var grade: Int?; var why: String; var ea = false }

    private static func core(_ v1: Bool, _ v2: Bool, _ v3: Bool, _ p: Primaries, _ s: (first: [Sign], second: [Sign]), _ v3name: String) -> Core {
        let abn = [v1, v2, v3].filter { $0 }.count
        func byEA(_ why: String) -> Core { Core(lap: .increased, grade: p.EA.map { $0 >= 2 ? 3 : 2 }, why: why, ea: true) }
        func supp(_ why: String, eOnly: Bool) -> Core {
            let pos = s.first.filter { $0.v == true }, neg = s.first.filter { $0.v == false }
            if !pos.isEmpty { return byEA(why + " " + pos.map(\.label).joined(separator: ", ") + ": increased LAP.") }
            if !neg.isEmpty {
                return Core(lap: .normal, grade: nil, why: why + " None of the supplemental signs is present, so LAP is likely normal." + (eOnly ? " The guideline assigns no grade on this path (Grade 1 needs E/A ≤ 0.8)." : ""))
            }
            let mp = s.second.filter { $0.v == true }, mn = s.second.filter { $0.v == false }
            if !mp.isEmpty && mp.allSatisfy({ $0.id == "ara" }) {
                return Core(lap: .lvedp, grade: nil, why: why + " Ar − A above 30 ms reflects LV end-diastolic pressure rather than mean LAP; report it as an isolated LVEDP increase.")
            }
            if !mp.isEmpty { return byEA(why + " " + mp.map(\.label).joined(separator: ", ") + ": increased LAP.") }
            if !mn.isEmpty { return Core(lap: .normal, grade: nil, why: why + " None of the further signs is present, so LAP is likely normal.") }
            return Core(lap: .unknown, grade: nil, why: why + " Enter the supplemental parameters: pulmonary vein S/D, LA reservoir strain, LA volume index or IVRT.")
        }
        if abn == 0 { return Core(lap: .normal, grade: 0, why: "e′, E/e′ and \(v3name) are all normal: normal LAP and normal diastolic function.") }
        if abn == 3 { return byEA("All three main variables are abnormal.") }
        if v1 && !v2 && !v3 {
            if let ea = p.EA, ea <= 0.8 { return Core(lap: .normal, grade: 1, why: "Only e′ is reduced and E/A is \(f(ea)) (0.8 or less): impaired relaxation with normal LAP.") }
            return supp(p.EA == nil ? "Only e′ is reduced; E/A is not entered." : "Only e′ is reduced, with E/A \(f(p.EA!)) above 0.8.", eOnly: true)
        }
        let which = [v1 ? "e′" : nil, v2 ? "E/e′" : nil, v3 ? v3name : nil].compactMap { $0 }
        return supp(which.count == 1 ? "Only \(which[0]) is abnormal." : which.joined(separator: " and ") + " are abnormal.", eOnly: false)
    }

    /// Figure 3 for sinus rhythm. With a main variable missing (or PASP/TR set aside for lung disease) the tool reads
    /// every way the missing one could fall and reports only a reading they all share; the guideline does not cover
    /// this case.
    static func read(_ i: Input) -> Reading {
        let p = primaries(i), s = signs(i)
        var steps: [Step] = []
        var cautions: [String] = []
        func show(_ b: Bool?) -> String { b == nil ? "not entered" : (b! ? "abnormal" : "normal") }
        let v3name = p.v3ByTR ? "TR velocity" : "PASP"
        let eText = [p.es.map { "septal " + f($0) }, p.el.map { "lateral " + f($0) }, p.ea.map { "average " + f($0) }].compactMap { $0 }.joined(separator: ", ")
        let rText = [p.ees.map { "septal " + f($0) }, p.eel.map { "lateral " + f($0) }, p.eea.map { "average " + f($0) }].compactMap { $0 }.joined(separator: ", ")
        steps.append(Step(id: "v1", label: "e′ reduced", state: p.v1, text: p.v1 == nil ? "Enter septal and lateral e′" : eText + " cm/s · " + show(p.v1)))
        steps.append(Step(id: "v2", label: "E/e′ increased", state: p.v2, text: p.v2 == nil ? "Needs E and e′" : rText + " · " + show(p.v2)))
        let v3Text: String
        if i.lungDisease { v3Text = "Not used: lung or pulmonary vascular disease" }
        else if p.v3 == nil { v3Text = "Enter PASP, or TR velocity when RAP cannot be estimated" }
        else if p.v3ByTR { v3Text = "TR " + f(i.tr ?? 0) + " m/s · " + show(p.v3) }
        else { v3Text = "PASP " + f(i.pasp ?? 0) + " mmHg · " + show(p.v3) }
        steps.append(Step(id: "v3", label: p.v3ByTR ? "TR velocity increased" : "PASP increased", state: p.v3, text: v3Text))
        for x in s.first + s.second {
            guard let t = x.text else { continue }
            steps.append(Step(id: x.id, label: x.label, state: x.v, text: t + (x.v == nil ? "" : " · " + (x.v! ? "present" : "absent"))))
        }
        let pres = presence(i, p)

        func finish(_ r: Core) -> Reading {
            var explanation = r.why
            if r.ea, let ea = p.EA {
                steps.append(Step(id: "ea", label: "E/A", state: nil, text: f(ea) + (ea >= 2 ? " · 2 or more" : " · below 2")))
                explanation += ea >= 2 ? " E/A \(f(ea)) is 2 or more: marked increase in LAP." : " E/A \(f(ea)) is below 2: mild to moderate increase in LAP."
            } else if r.ea { explanation += " Enter E and A: E/A below 2 is Grade 2, 2 or more is Grade 3." }
            let headline: String
            switch r.lap {
            case .unknown: headline = "LAP Not Yet Determined"
            case .lvedp: headline = "Isolated LVEDP Elevation"
            default: headline = r.grade.flatMap { head[$0] } ?? (r.lap == .increased ? "Increased LAP" : "Normal LAP")
            }
            return Reading(lap: r.lap, grade: r.grade, headline: headline, explanation: explanation, steps: steps, cautions: cautions, primaries: p, presence: pres)
        }

        let prim = [p.v1, p.v2, p.v3]
        if prim.allSatisfy({ $0 == nil }) {
            return Reading(lap: .unknown, grade: nil, headline: "Enter the Measurements", explanation: "Start with septal and lateral e′, mitral E and A, and PASP or TR velocity.",
                           steps: steps, cautions: cautions, primaries: p, presence: pres)
        }
        if let v1 = p.v1, let v2 = p.v2, let v3 = p.v3 { return finish(core(v1, v2, v3, p, s, v3name)) }

        // A main variable missing: read every way it could fall.
        let names = ["e′", "E/e′", "PASP or TR velocity"]
        let missing = prim.indices.filter { prim[$0] == nil }
        var results: [Core] = []
        for mask in 0..<(1 << missing.count) {
            var v = prim.map { $0 ?? false }
            for (j, k) in missing.enumerated() { v[k] = mask & (1 << j) != 0 }
            results.append(core(v[0], v[1], v[2], p, s, "PASP or TR velocity"))
        }
        let miss = missing.map { names[$0] }.joined(separator: " and ")
        if i.lungDisease && missing.contains(2) {
            cautions.append("With lung or pulmonary vascular disease, TR velocity and PASP do not stand in for LAP, so the reading has to hold without them.")
        } else {
            cautions.append(miss + (missing.count > 1 ? " are" : " is") + " not entered. The guideline does not cover this case, so the tool reports a reading only when every possible value of the missing one would give it.")
        }
        let known = [p.v1.map { "e′ " + ($0 ? "reduced" : "normal") }, p.v2.map { "E/e′ " + ($0 ? "increased" : "normal") },
                     p.v3.map { v3name + " " + ($0 ? "increased" : "normal") }].compactMap { $0 }.joined(separator: ", ")
        let lap = results[0].lap
        if lap != .unknown && results.allSatisfy({ $0.lap == lap }) {
            let grade = results.allSatisfy({ $0.grade == results[0].grade }) ? results[0].grade : nil
            let pos = s.first.filter { $0.v == true }.map(\.label), neg = s.first.contains { $0.v == false }
            let tail = !pos.isEmpty ? ": " + pos.joined(separator: ", ") + " point" + (pos.count == 1 ? "s" : "") + " to increased LAP."
                : (neg ? ": none of the supplemental signs entered is present." : ".")
            return finish(Core(lap: lap, grade: grade, why: "With \(known), the reading is the same whichever way \(miss) would fall" + tail, ea: lap == .increased))
        }
        var outcomes: [String] = []
        for r in results {
            let o: String
            switch r.lap {
            case .unknown: o = "not determined"
            case .lvedp: o = "isolated LVEDP elevation"
            default: o = r.grade.flatMap { head[$0]?.lowercased() } ?? (r.lap == .increased ? "increased LAP" : "normal LAP")
            }
            if !outcomes.contains(o) { outcomes.append(o) }
        }
        let advice = i.lungDisease && missing.contains(2)
            ? "Add the supplemental signs: LA reservoir strain, pulmonary vein S/D, LA volume index or IVRT."
            : "Measure \(miss), or add the supplemental signs."
        return finish(Core(lap: .unknown, grade: nil, why: "With \(known), the reading depends on \(miss) (\(outcomes.joined(separator: " or "))). " + advice))
    }

    /// Figure 4: moderate or severe mitral annular calcification (E/A, then IVRT).
    static func mac(_ i: Input) -> (lap: LAP, headline: String, explanation: String) {
        guard let e = i.E, let a = i.A, a > 0 else { return (.unknown, "Enter E and A", "With annular calcification the reading rests on E/A and IVRT; e′ and E/e′ are not used.") }
        let ea = e / a
        if ea < 0.8 { return (.normal, "Normal LAP", "E/A \(f(ea)) is below 0.8.") }
        if ea > 1.8 { return (.increased, "Increased LAP", "E/A \(f(ea)) is above 1.8.") }
        guard let iv = i.ivrt else { return (.unknown, "Enter IVRT", "E/A \(f(ea)) sits between 0.8 and 1.8: IVRT decides (80 ms or more normal, under 80 ms increased).") }
        return iv >= 80 ? (.normal, "Normal LAP", "E/A \(f(ea)) with IVRT \(f(iv)) ms (80 ms or more).")
            : (.increased, "Increased LAP", "E/A \(f(ea)) with IVRT \(f(iv)) ms (under 80 ms).")
    }

    /// Section 15B: heart transplant recipients (average E/e′, then E/SRIVR, then TR velocity).
    static func transplant(_ i: Input) -> (lap: LAP, headline: String, explanation: String) {
        let p = primaries(i)
        guard let ee = p.eea else { return (.unknown, "Enter E and Both e′", "The transplant pathway starts from average E/e′.") }
        if ee < 7 { return (.normal, "Normal Filling Pressure", "Average E/e′ \(f(ee)) is below 7.") }
        if ee > 14 { return (.increased, "Increased Filling Pressure", "Average E/e′ \(f(ee)) is above 14.") }
        if let s = i.esr {
            return s <= 200 ? (.normal, "Normal Filling Pressure", "Average E/e′ \(f(ee)) (7–14), E/SRIVR \(f(s)) cm (200 or less).")
                : (.increased, "Increased Filling Pressure", "Average E/e′ \(f(ee)) (7–14), E/SRIVR \(f(s)) cm (above 200).")
        }
        if let t = i.tr {
            return t <= 2.8 ? (.normal, "Normal Filling Pressure", "Average E/e′ \(f(ee)) (7–14), no E/SRIVR, TR \(f(t)) m/s (2.8 or less).")
                : (.increased, "Increased Filling Pressure", "Average E/e′ \(f(ee)) (7–14), no E/SRIVR, TR \(f(t)) m/s (above 2.8).")
        }
        return (.unknown, "Enter E/SRIVR or TR", "Average E/e′ \(f(ee)) sits between 7 and 14: E/SRIVR decides (200 cm or less normal), or TR velocity when SRIVR cannot be measured.")
    }
}
