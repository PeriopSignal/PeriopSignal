import Foundation

// MARK: - Studies beyond the heart: carotid ultrasound, radial artery ultrasound and pulmonary function tests
//
// Findings and key numbers, every field optional, as the reports give them. Each type decodes with a fallback for
// every field, like PatientRecord, so a patient saved before 1.8.1 (or sent from an older version) still opens.
// PatientStudies reads the record for the cautions the summary and the handoff show.

/// One side of a carotid duplex: the ICA stenosis category, the vertebral flow, and the ICA velocities.
struct CarotidSide: Codable, Hashable {
    /// CarotidSide.stenoses' ids: "normal", "lt50", "50-69", "ge70", "near", "occluded".
    var stenosis: String?
    /// CarotidSide.vertebralFlows' ids: "antegrade", "partial", "reversed", "absent".
    var vertebral: String?
    /// ICA peak systolic and end-diastolic velocity, cm/s.
    var psv: Double?
    var edv: Double?

    init(stenosis: String? = nil, vertebral: String? = nil, psv: Double? = nil, edv: Double? = nil) {
        self.stenosis = stenosis; self.vertebral = vertebral; self.psv = psv; self.edv = edv
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stenosis = try? c.decodeIfPresent(String.self, forKey: .stenosis)
        vertebral = try? c.decodeIfPresent(String.self, forKey: .vertebral)
        psv = try? c.decodeIfPresent(Double.self, forKey: .psv)
        edv = try? c.decodeIfPresent(Double.self, forKey: .edv)
    }

    var isEmpty: Bool { self == CarotidSide() }

    // The lab's category as reported, never worked out from the velocities. Categories: SRU consensus, Grant EG, et al.
    // Radiology 2003;229:340 [G?, abstract]; near occlusion its own category, its velocities high, low or undetectable
    // [G?, SRU abstract; Johansson E, Fox AJ. AJNR 2016;37:2, G?]. Labs' criteria differ and SRU overcalls stenosis
    // (IAC, Gornik HL, et al. Vasc Med 2021;26:515) [G]. NASCET method recommended (ESC 2024 PAAD, Mazzolai L, et al.
    // Eur Heart J 2024;45:3538, class I, B) [G].
    static let stenoses: [(id: String, label: String)] = [
        ("normal", "Normal"), ("lt50", "<50%"), ("50-69", "50–69%"), ("ge70", "≥70%"), ("near", "Near occlusion"), ("occluded", "Occluded"),
    ]
    // Antegrade, partial reversal (alternating, Kliewer type 4: partial steal), reversed (complete steal), absent
    // (occlusion or hypoplasia, not steal): Kliewer MA, et al. AJR 2000;174:815 [G?, abstract]; the grouping is common
    // teaching [P]. Systolic deceleration without reversal goes in Notes.
    static let vertebralFlows: [(id: String, label: String)] = [
        ("antegrade", "Antegrade"), ("partial", "Partial reversal"), ("reversed", "Reversed"), ("absent", "Absent"),
    ]

    static func stenosisLabel(_ id: String?) -> String? { id.flatMap { i in stenoses.first { $0.id == i }?.label } }
    static func vertebralLabel(_ id: String?) -> String? { id.flatMap { i in vertebralFlows.first { $0.id == i }?.label } }

    /// ≥70%, near occlusion or occluded.
    var severe: Bool { ["ge70", "near", "occluded"].contains(stenosis ?? "") }
}

/// Carotid duplex ultrasound, right and left.
struct PatientCarotid: Codable, Hashable {
    var right = CarotidSide()
    var left = CarotidSide()
    var date = PatientMonthYear()
    var notes = ""

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        right = (try? c.decodeIfPresent(CarotidSide.self, forKey: .right)) ?? CarotidSide()
        left = (try? c.decodeIfPresent(CarotidSide.self, forKey: .left)) ?? CarotidSide()
        date = (try? c.decodeIfPresent(PatientMonthYear.self, forKey: .date)) ?? PatientMonthYear()
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
    }

    var isEmpty: Bool { self == PatientCarotid() }

    /// The sides in report order, right then left.
    var sides: [(name: String, side: CarotidSide)] { [("right", right), ("left", left)] }

    /// "right", "left": the sides with ICA stenosis ≥70%, near occlusion or occlusion.
    var severeSides: [String] { sides.filter { $0.side.severe }.map(\.name) }

    /// The sides whose vertebral flow is reversed (PatientStudies.vertebralCaution decides whether partial counts).
    var reversedSides: [String] { sides.filter { PatientStudies.stealFlows.contains($0.side.vertebral ?? "") }.map(\.name) }

    /// "R ICA 50–69% (PSV 180, EDV 60)", "L vertebral reversed".
    private static func sideText(_ letter: String, _ s: CarotidSide) -> [String] {
        var out: [String] = []
        var ica: [String] = []
        if let l = CarotidSide.stenosisLabel(s.stenosis) { ica.append(s.stenosis == "normal" ? "no stenosis" : l) }
        var v: [String] = []
        if let p = s.psv { v.append("PSV " + NumText.short(p)) }
        if let e = s.edv { v.append("EDV " + NumText.short(e)) }
        if !ica.isEmpty || !v.isEmpty {
            out.append(letter + " ICA " + ica.joined() + (v.isEmpty ? "" : (ica.isEmpty ? "" : " ") + "(" + v.joined(separator: ", ") + ")"))
        }
        if let f = CarotidSide.vertebralLabel(s.vertebral) { out.append(letter + " vertebral " + f.lowercased()) }
        return out
    }

    /// "Carotid US 05/2026: R ICA 50–69%, L ICA ≥70%; L vertebral reversed".
    var summary: String {
        var head = "Carotid US"
        if !date.isEmpty { head += " " + date.text }
        let r = Self.sideText("R", right), l = Self.sideText("L", left)
        let ica = (r + l).filter { $0.contains(" ICA ") }
        let vert = (r + l).filter { $0.contains(" vertebral ") }
        var parts: [String] = []
        if !ica.isEmpty { parts.append(ica.joined(separator: ", ")) }
        if !vert.isEmpty { parts.append(vert.joined(separator: ", ")) }
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { parts.append(n) }
        return parts.isEmpty ? head : head + ": " + parts.joined(separator: "; ")
    }
}

/// One radial artery on ultrasound: its inner diameter, calcification and the ulnar compensation.
struct RadialSide: Codable, Hashable {
    /// Inner diameter, mm.
    var diameter: Double?
    var calcified: Bool?
    /// RadialSide.ulnarOptions' ids: "adequate", "inadequate".
    var ulnar: String?

    init(diameter: Double? = nil, calcified: Bool? = nil, ulnar: String? = nil) {
        self.diameter = diameter; self.calcified = calcified; self.ulnar = ulnar
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        diameter = try? c.decodeIfPresent(Double.self, forKey: .diameter)
        calcified = try? c.decodeIfPresent(Bool.self, forKey: .calcified)
        ulnar = try? c.decodeIfPresent(String.self, forKey: .ulnar)
    }

    var isEmpty: Bool { self == RadialSide() }

    // Adequate or inadequate as the lab reads it: no society sets a threshold (Gaudino M, et al. EACTS/STS-endorsed
    // review, Eur J Cardiothorac Surg 2023;64:ezad163) [G]; a "borderline" grade has no source [P] and is left out.
    static let ulnarOptions: [(id: String, label: String)] = [("adequate", "Adequate"), ("inadequate", "Inadequate")]
    static func ulnarLabel(_ id: String?) -> String? { id.flatMap { i in ulnarOptions.first { $0.id == i }?.label } }

    /// "2.6 mm, calcified, ulnar compensation reduced".
    var text: String {
        var parts: [String] = []
        if let d = diameter { parts.append(NumText.short(d) + " mm") }
        if let c = calcified { parts.append(c ? "calcified" : "not calcified") }
        if let u = RadialSide.ulnarLabel(ulnar) { parts.append("ulnar compensation " + u.lowercased()) }
        return parts.joined(separator: ", ")
    }
}

/// Radial artery ultrasound before a radial artery graft: each side, and the side planned for harvest.
struct PatientRadial: Codable, Hashable {
    var right = RadialSide()
    var left = RadialSide()
    /// "none", "right", "left"; nil when not said.
    var harvest: String?
    var date = PatientMonthYear()
    var notes = ""

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        right = (try? c.decodeIfPresent(RadialSide.self, forKey: .right)) ?? RadialSide()
        left = (try? c.decodeIfPresent(RadialSide.self, forKey: .left)) ?? RadialSide()
        harvest = try? c.decodeIfPresent(String.self, forKey: .harvest)
        date = (try? c.decodeIfPresent(PatientMonthYear.self, forKey: .date)) ?? PatientMonthYear()
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
    }

    var isEmpty: Bool { self == PatientRadial() }

    static let harvestOptions: [(id: String, label: String)] = [("none", "None"), ("right", "Right"), ("left", "Left")]

    /// "right" or "left" when a harvest side is planned.
    var harvestSide: String? { harvest == "right" || harvest == "left" ? harvest : nil }

    /// "Radial US 04/2026: planned left harvest; R 2.4 mm, …; L 2.8 mm, …".
    var summary: String {
        var head = "Radial US"
        if !date.isEmpty { head += " " + date.text }
        var parts: [String] = []
        if let h = harvestSide { parts.append("planned " + h + " harvest") } else if harvest == "none" { parts.append("no harvest planned") }
        if !right.text.isEmpty { parts.append("R " + right.text) }
        if !left.text.isEmpty { parts.append("L " + left.text) }
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { parts.append(n) }
        return parts.isEmpty ? head : head + ": " + parts.joined(separator: "; ")
    }
}

/// Pulmonary function tests: the key numbers and the lab's reading.
struct PatientPFT: Codable, Hashable {
    /// Liters, and % predicted.
    var fev1: Double?
    var fev1Pct: Double?
    var fvc: Double?
    var fvcPct: Double?
    /// FEV1/FVC as typed: a ratio (0.55) or a percentage (55); `ratio` reads either.
    var ratioTyped: Double?
    var tlcPct: Double?
    var dlcoPct: Double?
    /// PatientPFT.patterns' ids: "normal", "obstruction", "restriction", "mixed", "nonspecific".
    var pattern: String?
    /// "mild", "moderate", "severe".
    var severity: String?
    var date = PatientMonthYear()
    var notes = ""

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fev1 = try? c.decodeIfPresent(Double.self, forKey: .fev1)
        fev1Pct = try? c.decodeIfPresent(Double.self, forKey: .fev1Pct)
        fvc = try? c.decodeIfPresent(Double.self, forKey: .fvc)
        fvcPct = try? c.decodeIfPresent(Double.self, forKey: .fvcPct)
        ratioTyped = try? c.decodeIfPresent(Double.self, forKey: .ratioTyped)
        tlcPct = try? c.decodeIfPresent(Double.self, forKey: .tlcPct)
        dlcoPct = try? c.decodeIfPresent(Double.self, forKey: .dlcoPct)
        pattern = try? c.decodeIfPresent(String.self, forKey: .pattern)
        severity = try? c.decodeIfPresent(String.self, forKey: .severity)
        date = (try? c.decodeIfPresent(PatientMonthYear.self, forKey: .date)) ?? PatientMonthYear()
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
    }

    var isEmpty: Bool { self == PatientPFT() }

    // The lab's reading as reported, in the ERS/ATS 2022 interpretive standard's words (Stanojevic S, et al. Eur
    // Respir J 2022;60:2101499) [G]: obstruction FEV1/FVC below the lower limit of normal; restriction a TLC below it,
    // which spirometry alone cannot confirm; mixed both; nonspecific a low FEV1 or FVC with a normal ratio and TLC.
    // Severity in three grades: mild, moderate, severe [G]. Older reports' five grades (ATS/ERS 2005) [G?, unverified]
    // go in Notes.
    static let patterns: [(id: String, label: String)] = [
        ("normal", "Normal"), ("obstruction", "Obstruction"), ("restriction", "Restriction"), ("mixed", "Mixed"), ("nonspecific", "Nonspecific"),
    ]
    static let severities: [(id: String, label: String)] = [("mild", "Mild"), ("moderate", "Moderate"), ("severe", "Severe")]

    /// FEV1/FVC as a ratio: 0.55 typed as 0.55 or 55. Nil when it reads as neither (over 100, or 0).
    var ratio: Double? {
        guard let v = ratioTyped, v > 0 else { return nil }
        if v <= 1 { return v }
        return v <= 100 ? v / 100 : nil
    }

    /// The GOLD grade, when the lab reads obstruction, FEV1 % predicted is entered and FEV1/FVC is below GOLD's fixed
    /// 0.70 or not entered (a lab may call obstruction by the lower limit of normal above 0.70).
    var gold: Int? {
        guard pattern == "obstruction", let p = fev1Pct, (ratio ?? 0) < 0.70 else { return nil }
        return PatientStudies.goldGrade(fev1Pct: p)
    }

    /// "GOLD 2 (moderate), FEV1 58% predicted".
    var goldText: String? {
        guard let g = gold, let p = fev1Pct else { return nil }
        return "GOLD \(g) (" + PatientStudies.goldNames[g - 1] + "), FEV1 " + NumText.short(p) + "% predicted"
    }

    /// "Obstruction, moderate".
    var readingText: String? {
        let p = pattern.flatMap { i in PatientPFT.patterns.first { $0.id == i }?.label }
        let s = severity.flatMap { i in PatientPFT.severities.first { $0.id == i }?.label.lowercased() }
        switch (p, s) {
        case let (p?, s?): return p + ", " + s
        case let (p?, nil): return p
        case let (nil, s?): return s.prefix(1).uppercased() + s.dropFirst()
        default: return nil
        }
    }

    /// "PFT 04/2026: obstruction, moderate; GOLD 2 (moderate), FEV1 58% predicted; FEV1 1.62 L (58%), FVC 2.90 L (78%), FEV1/FVC 0.56; TLC 104%, DLCO 61%".
    var summary: String {
        var head = "PFT"
        if !date.isEmpty { head += " " + date.text }
        var parts: [String] = []
        if let r = readingText {
            parts.append(r.lowercased() == "normal" ? "normal" : r.prefix(1).lowercased() + r.dropFirst())
        }
        if let g = goldText { parts.append(g) }
        var spiro: [String] = []
        func vol(_ name: String, _ l: Double?, _ pct: Double?) {
            guard l != nil || pct != nil else { return }
            var s = name
            if let l { s += " " + NumText.short(l) + " L" }
            if let pct { s += l == nil ? " " + NumText.short(pct) + "%" : " (" + NumText.short(pct) + "%)" }
            spiro.append(s)
        }
        vol("FEV1", fev1, fev1Pct)
        vol("FVC", fvc, fvcPct)
        if let r = ratio { spiro.append("FEV1/FVC " + String(format: "%.2f", r)) }
        if !spiro.isEmpty { parts.append(spiro.joined(separator: ", ")) }
        var other: [String] = []
        if let t = tlcPct { other.append("TLC " + NumText.short(t) + "%") }
        if let d = dlcoPct { other.append("DLCO " + NumText.short(d) + "%") }
        if !other.isEmpty { parts.append(other.joined(separator: ", ")) }
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { parts.append(n) }
        return parts.isEmpty ? head : head + ": " + parts.joined(separator: "; ")
    }
}

// MARK: - Cautions

/// A caution a study raises: one short line, and the details and sources behind its ⓘ.
struct StudyCaution: Hashable, Identifiable {
    /// "harvest", "harvest-arm", "harvest-femoral", "carotid", "vertebral-left", "vertebral-right".
    var id: String
    var text: String
    var source: String
    /// The words shown in bold red on the handoff.
    var mark: String

    init(id: String, text: String, source: String, mark: String? = nil) {
        self.id = id; self.text = text; self.source = source
        self.mark = mark ?? (text.components(separatedBy: ":").first ?? text)
    }
}

enum PatientStudies {
    /// The vertebral flows that raise the subclavian-steal caution: partial reversal and reversed flow both mean a
    /// gradient across the proximal subclavian (innominate on the right) (Kliewer MA, et al. AJR 2000;174:815) [G?,
    /// abstract]; that partial reversal already matters for the arm pressure and the mammary inflow [P].
    static let stealFlows: Set<String> = ["partial", "reversed"]

    /// GOLD 1 FEV1 ≥80% predicted, 2 50–79%, 3 30–49%, 4 <30%: GOLD 2025 report's grades [G?, figure read from
    /// secondary sources]; post-bronchodilator FEV1/FVC < 0.70 (GOLD 2025 Pocket Guide text) [G].
    static func goldGrade(fev1Pct p: Double) -> Int {
        if p >= 80 { return 1 }
        if p >= 50 { return 2 }
        if p >= 30 { return 3 }
        return 4
    }
    static let goldNames = ["mild", "moderate", "severe", "very severe"]
    // GOLD 2025 Pocket Guide [G]; pre-bronchodilator rules COPD out, post confirms it (Singh D, et al. Eur Respir J
    // 2025;65:2401603) [G?, abstract].
    static let goldCaveat = "GOLD grades assume post-bronchodilator FEV1/FVC <0.70 (GOLD 2025)."

    /// The device kinds that are a line in the arm: arterial lines, peripheral IVs and PICCs.
    static let armLineKinds: Set<DeviceKind> = [.arterial, .piv, .picc]

    static func otherSide(_ s: String) -> String { s == "left" ? "right" : "left" }

    /// "Planned left radial harvest: arterial line, IVs and BP cuff in the right arm."
    static func harvestReminder(_ r: PatientRecord) -> String? {
        guard let h = r.radial.harvestSide else { return nil }
        return "Planned " + h + " radial harvest: arterial line, IVs and BP cuff in the " + otherSide(h) + " arm."
    }

    /// Arterial lines, IVs and PICCs in place on the arm planned for harvest.
    static func linesOnHarvestArm(_ r: PatientRecord) -> [PatientDevice] {
        guard let h = r.radial.harvestSide else { return [] }
        return r.currentDevices().filter { d in
            guard armLineKinds.contains(d.kind), let site = DeviceSite.site(id: d.site) else { return false }
            return site.region == "arm" && site.side == h
        }
    }

    // "Previous catheterization of the RA is a contraindication to RA use for CABG" (Gaudino M, et al. EACTS/STS-
    // endorsed review, Eur J Cardiothorac Surg 2023;64:ezad163) [G]. No guideline names lines or a cuff on the harvest
    // arm; keeping them off it is extrapolated from that [P].
    static let harvestSource = "A radial artery that has been catheterized should not be used as a graft (EACTS/STS-endorsed review, Gaudino M, et al. Eur J Cardiothorac Surg 2023). Keeping lines, IVs and the cuff off the harvest arm follows from that; no guideline states it."
    // Neither radial reads true with steal on the arm not harvested: femoral access [P].
    static let femoralSource = "The arm not harvested has subclavian steal, so its pressure may read low too. A femoral arterial line is practice; no guideline states it."
    // Naylor AR, et al. Eur J Vasc Endovasc Surg 2002;23:283 [G?, abstract]: peri-CABG stroke under 2% without carotid
    // disease, about 3% unilateral and 5% bilateral 50–99%, 7–11% with occlusion; about half of strokes occur without
    // carotid disease. Cerebral oximetry against a pre-induction baseline (ASER/POQI-6, Thiele RH, et al. Anesth Analg
    // 2020;131:1444) [G?, abstract]; using it for carotid disease [P].
    static let carotidSource = "Stroke with CABG runs under 2% without carotid disease, about 3% with one-sided 50–99% stenosis, 5% with both sides and 7–11% with an occlusion; about half of strokes after CABG occur without carotid disease (Naylor AR, et al. Eur J Vasc Endovasc Surg 2002). A cerebral oximetry baseline before induction is reasonable (ASER/POQI, Thiele RH, et al. Anesth Analg 2020); its use for carotid disease is practice."
    // Kliewer MA, et al. AJR 2000;174:815 [G?]; an inter-arm difference ≥10 mmHg strongly associated with subclavian
    // stenosis (Clark CE, et al. Lancet 2012;379:905) [G?]; bilateral arm BP in arterial disease (ESC 2024, I, B) [G];
    // coronary–subclavian steal (Kilic ID, et al. Herz 2013;38:250) [G?]; the arterial line on the other side [P].
    static let vertebralSource = "Partial or reversed vertebral flow means subclavian steal, from a stenosis of the subclavian (on the right, possibly the innominate) before the vertebral (Kliewer MA, et al. AJR 2000). A difference of 10 mmHg or more between the arms suggests it (Clark CE, et al. Lancet 2012); measure both arms (ESC 2024). The internal mammary arises beyond the stenosis, so a graft from it can steal from the heart (Kilic ID, et al. Herz 2013). The arterial line on the other side is practice."

    /// The cautions the studies raise, in the order the handoff reads them: the harvest arm first.
    static func cautions(_ r: PatientRecord) -> [StudyCaution] {
        var out: [StudyCaution] = []
        if let h = harvestReminder(r) { out.append(StudyCaution(id: "harvest", text: h, source: harvestSource)) }
        let onArm = linesOnHarvestArm(r)
        if !onArm.isEmpty, let h = r.radial.harvestSide {
            let names = PatientDevices.labels(onArm).joined(separator: "; ")
            out.append(StudyCaution(id: "harvest-arm", text: "On the " + h + " (harvest) arm: " + names + ". Move it to the other arm if you can.", source: harvestSource))
        }
        if let h = r.radial.harvestSide, r.carotid.reversedSides.contains(otherSide(h)) {
            out.append(StudyCaution(id: "harvest-femoral", text: "Both arms are limited for arterial monitoring; consider femoral arterial access.",
                                    source: femoralSource, mark: "Both arms are limited for arterial monitoring"))
        }
        let severe = r.carotid.severeSides
        if !severe.isEmpty {
            let what = severe.map { s in s + " (" + (CarotidSide.stenosisLabel((s == "right" ? r.carotid.right : r.carotid.left).stenosis) ?? "").lowercased() + ")" }
            out.append(StudyCaution(id: "carotid", text: "Severe carotid disease, " + what.joined(separator: " and ") + ": higher stroke risk with cardiac surgery.", source: carotidSource))
        }
        for s in r.carotid.reversedSides {
            let o = otherSide(s)
            let lesion = s == "right" ? "right subclavian or innominate" : "left subclavian"
            let partial = (s == "right" ? r.carotid.right : r.carotid.left).vertebral == "partial"
            let tail: String = "-arm BP may read low; use the " + o + " arm for the arterial line and cuff. Matters for a " + s + " internal mammary graft."
            let capital: String = s.capitalized + tail
            let text: String
            if partial {
                text = "Partial (alternating) " + s + " vertebral flow: suggests significant " + lesion + " stenosis. Compare arm BPs; " + s + tail
            } else {
                text = "Reversed " + s + " vertebral flow: suggests " + lesion + " stenosis. " + capital
            }
            out.append(StudyCaution(id: "vertebral-" + s, text: text, source: vertebralSource))
        }
        return out
    }
}

extension PatientStudies {
    // Each page's Explanation & Evidence; the tags and sources are in the comments beside each fact above.
    static let carotidEvidence = "Record the ICA category the lab reports. The usual categories are the Society of Radiologists in Ultrasound's (Grant EG, et al. Radiology 2003): peak systolic velocity under 125 cm/s for normal and under 50%, 125–230 for 50–69%, over 230 for 70% or more; near occlusion can have high, low or no measurable velocity, and an occlusion has no flow. Vertebral flow: partial reversal and reversed flow mean subclavian steal; absent flow does not (Kliewer MA, et al. AJR 2000). Put systolic deceleration without reversal in Notes."
    static let radialEvidence = "Assess the ulnar collateral circulation before a radial artery is harvested; ultrasound adds the artery's diameter and calcification. Harvest the side with the better ulnar compensation and artery quality (EACTS/STS-endorsed review, Gaudino M, et al. Eur J Cardiothorac Surg 2023). No society sets a minimum diameter: trials used 1.5 mm (RAPCO) or 2.0 mm (Agrifoglio M, et al. Ann Thorac Surg 2005), so it is recorded without a cut-off."
    static let pftEvidence = "Record the lab's reading (ERS/ATS 2022, Stanojevic S, et al. Eur Respir J 2022): obstruction is FEV1/FVC below the lower limit of normal; restriction needs a low TLC; mixed is both; nonspecific is a low FEV1 or FVC with a normal ratio and TLC. GOLD grades COPD by FEV1 % predicted: 1 at 80% or more, 2 at 50–79%, 3 at 30–49%, 4 under 30% (GOLD 2025). It shows when the reading is obstruction and FEV1/FVC, if entered, is below 0.70."

    // Row captions behind ⓘ.
    // IAC 2021 [G]; NASCET method, ESC 2024 I/B [G].
    static let stenosisInfo = "Use the lab's category; labs' criteria differ (IAC 2021). Graded by the NASCET method (ESC 2024)."
    // Gaudino 2023 [G]: "the clinical Allen test is highly operator dependent"; previous RA catheterization is a
    // contraindication. Agrifoglio 2005 [G]: 5.3% with a normal Allen test had duplex findings against harvest.
    static let ulnarInfo = "The Allen test alone is not enough; a radial artery used for catheterization should not be used as a graft (Gaudino M, et al. Eur J Cardiothorac Surg 2023)."
    // ERS/ATS 2022 [G].
    static let patternInfo = "Restriction needs TLC; spirometry alone can't confirm it (ATS/ERS 2022)."
    // ERS/ATS 2022 three grades [G]; ATS/ERS 2005 five grades [G?, unverified].
    static let severityInfo = "Older reports may use five grades; record those in Notes."
}

extension PatientRecord {
    /// Any study beyond the heart recorded.
    var hasStudies: Bool { !carotid.isEmpty || !radial.isEmpty || !pft.isEmpty }
}
