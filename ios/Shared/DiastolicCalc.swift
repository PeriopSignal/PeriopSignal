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

    static func read(_ i: Input) -> Reading {
        let p = primaries(i)
        var steps: [Step] = []
        var cautions: [String] = []
        func show(_ b: Bool?) -> String { b == nil ? "not entered" : (b! ? "abnormal" : "normal") }
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
        let pres = presence(i, p)

        func out(_ lap: LAP, _ grade: Int?, _ headline: String, _ explanation: String) -> Reading {
            Reading(lap: lap, grade: grade, headline: headline, explanation: explanation, steps: steps, cautions: cautions, primaries: p, presence: pres)
        }
        func grading(_ why: String) -> Reading {
            guard let ea = p.EA else { return out(.increased, nil, "Increased LAP", why + " Enter E and A: E/A below 2 is Grade 2, 2 or more is Grade 3.") }
            steps.append(Step(id: "ea", label: "E/A", state: nil, text: f(ea) + (ea >= 2 ? " · 2 or more" : " · below 2")))
            return ea >= 2
                ? out(.increased, 3, "Grade 3 Diastolic Dysfunction", why + " E/A \(f(ea)) is 2 or more: marked increase in LAP.")
                : out(.increased, 2, "Grade 2 Diastolic Dysfunction", why + " E/A \(f(ea)) is below 2: mild to moderate increase in LAP.")
        }
        struct Sign { var id: String; var label: String; var v: Bool?; var text: String? }
        func supplemental(_ why: String, eOnly: Bool) -> Reading {
            let s = [
                Sign(id: "pvsd", label: "Pulmonary vein S/D ≤ 0.67", v: i.pvsd.map { $0 <= pvsd }, text: i.pvsd.map { f($0) }),
                Sign(id: "lars", label: "LA reservoir strain ≤ 18%", v: i.lars.map { $0 <= lars }, text: i.lars.map { f($0) + "%" }),
                Sign(id: "lavi", label: "LA volume index > 34 mL/m²", v: i.lavi.map { $0 > lavi }, text: i.lavi.map { f($0) + " mL/m²" }),
                Sign(id: "ivrt", label: "IVRT ≤ 70 ms", v: i.ivrt.map { $0 <= ivrt }, text: i.ivrt.map { f($0) + " ms" }),
            ]
            let entered = s.filter { $0.v != nil }, pos = entered.filter { $0.v == true }
            for x in entered { steps.append(Step(id: x.id, label: x.label, state: x.v, text: (x.text ?? "") + " · " + (x.v == true ? "present" : "absent"))) }
            if !pos.isEmpty { return grading(why + " " + pos.map(\.label).joined(separator: ", ") + ": increased LAP.") }
            if !entered.isEmpty {
                return out(.normal, nil, "Normal LAP", why + " None of the supplemental signs is present, so LAP is likely normal." + (eOnly ? " The guideline assigns no grade on this path (Grade 1 needs E/A ≤ 0.8)." : ""))
            }
            let m = [
                Sign(id: "predv", label: "PR end-diastolic velocity ≥ 2 m/s", v: i.prEdv.map { $0 >= prEdv }, text: i.prEdv.map { f($0) + " m/s" }),
                Sign(id: "padp", label: "PA diastolic pressure ≥ 16 mmHg", v: i.padp.map { $0 >= padp }, text: i.padp.map { f($0) + " mmHg" }),
                Sign(id: "lwave", label: "Mitral L-wave ≥ 50 cm/s", v: i.lwave.map { $0 >= lwave }, text: i.lwave.map { f($0) + " cm/s" }),
                Sign(id: "ara", label: "Ar − A > 30 ms", v: i.ara.map { $0 > ara }, text: i.ara.map { f($0) + " ms" }),
                Sign(id: "valsalva", label: "E/A falls ≥ 50% with Valsalva", v: i.valsalva.map { $0 >= valsalva }, text: i.valsalva.map { f($0) + "%" }),
            ]
            let me = m.filter { $0.v != nil }, mp = me.filter { $0.v == true }
            for x in me { steps.append(Step(id: x.id, label: x.label, state: x.v, text: (x.text ?? "") + " · " + (x.v == true ? "present" : "absent"))) }
            if !mp.isEmpty && mp.allSatisfy({ $0.id == "ara" }) {
                return out(.lvedp, nil, "Isolated LVEDP Elevation", why + " Ar − A above 30 ms reflects LV end-diastolic pressure rather than mean LAP; report it as an isolated LVEDP increase.")
            }
            if !mp.isEmpty { return grading(why + " " + mp.map(\.label).joined(separator: ", ") + ": increased LAP.") }
            if !me.isEmpty { return out(.normal, nil, "Normal LAP", why + " None of the further signs is present, so LAP is likely normal.") }
            return out(.unknown, nil, "LAP Not Yet Determined", why + " Enter the supplemental parameters: pulmonary vein S/D, LA reservoir strain, LA volume index or IVRT.")
        }

        let prim = [p.v1, p.v2, p.v3]
        let avail = prim.compactMap { $0 }
        let abn = avail.filter { $0 }.count
        if avail.isEmpty { return out(.unknown, nil, "Enter the Measurements", "Start with septal and lateral e′, mitral E and A, and PASP or TR velocity.") }
        if avail.count < 3 {
            cautions.append("One of the three main variables is missing. The guideline does not say how to read the other two alone, so the tool goes on to the supplemental parameters.")
            let why = abn > 0 ? "\(abn) of the \(avail.count) main variables entered \(abn == 1 ? "is" : "are") abnormal." : "The \(avail.count) main variables entered are normal."
            return supplemental(why, eOnly: false)
        }
        if abn == 0 { return out(.normal, 0, "Normal Diastolic Function", "e′, E/e′ and \(p.v3ByTR ? "TR velocity" : "PASP") are all normal: normal LAP and normal diastolic function.") }
        if abn == 3 { return grading("All three main variables are abnormal.") }
        if p.v1 == true && p.v2 == false && p.v3 == false {
            if let ea = p.EA, ea <= 0.8 { return out(.normal, 1, "Grade 1 Diastolic Dysfunction", "Only e′ is reduced and E/A is \(f(ea)) (0.8 or less): impaired relaxation with normal LAP.") }
            return supplemental(p.EA == nil ? "Only e′ is reduced; E/A is not entered." : "Only e′ is reduced, with E/A \(f(p.EA!)) above 0.8.", eOnly: true)
        }
        let which = [p.v1 == true ? "e′" : nil, p.v2 == true ? "E/e′" : nil, p.v3 == true ? (p.v3ByTR ? "TR velocity" : "PASP") : nil].compactMap { $0 }
        return supplemental(which.count == 1 ? "Only \(which[0]) is abnormal." : which.joined(separator: " and ") + " are abnormal.", eOnly: false)
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
