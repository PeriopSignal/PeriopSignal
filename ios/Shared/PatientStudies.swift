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

    // The lab's category as reported, in the Society of Radiologists in Ultrasound consensus's (Grant EG, et al.
    // Radiology 2003;229:340). It is not worked out from the velocities: criteria differ between labs (IAC, Gornik HL,
    // et al. Vasc Med 2021;26:515), and near occlusion can have low or no measurable velocity (Johansson E, Fox AJ.
    // AJNR 2016;37:2).
    static let stenoses: [(id: String, label: String)] = [
        ("normal", "Normal"), ("lt50", "<50%"), ("50-69", "50–69%"), ("ge70", "≥70%"), ("near", "Near occlusion"), ("occluded", "Occluded"),
    ]
    // Antegrade, partial reversal (alternating, partial steal), reversed (complete steal), absent (Kliewer MA, et al.
    // AJR 2000;174:815).
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
    /// RadialSide.ulnarOptions' ids: "adequate", "borderline", "inadequate".
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

    // No society sets a threshold for adequate ulnar compensation (Gaudino M, et al. Eur J Cardiothorac Surg 2023);
    // the lab's reading is recorded as it is.
    static let ulnarOptions: [(id: String, label: String)] = [("adequate", "Adequate"), ("borderline", "Borderline"), ("inadequate", "Inadequate")]
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
    // Respir J 2022;60:2101499): obstruction is FEV1/FVC below the lower limit of normal; restriction a TLC below it
    // (spirometry alone only suggests it); mixed both; nonspecific a low FEV1 or FVC with a normal ratio and TLC. It
    // grades severity in three (mild, moderate, severe); older reports use five (ATS/ERS 2005), recorded nearest.
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

    /// The lab's reading includes obstruction (obstructive or mixed).
    var obstruction: Bool { pattern == "obstruction" || pattern == "mixed" }

    /// The GOLD grade of airflow obstruction from FEV1 % predicted, when the lab reads obstruction and FEV1/FVC, if
    /// entered, is below GOLD's fixed 0.70 (a lab may call obstruction by the lower limit of normal above it).
    var gold: Int? {
        guard obstruction, let p = fev1Pct, (ratio ?? 0) < 0.70 else { return nil }
        return PatientStudies.goldGrade(fev1Pct: p)
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

    /// "PFT 04/2026: obstruction, moderate (GOLD 2); FEV1 1.62 L (58%), FVC 2.90 L (78%), FEV1/FVC 0.56; TLC 104%, DLCO 61%".
    var summary: String {
        var head = "PFT"
        if !date.isEmpty { head += " " + date.text }
        var parts: [String] = []
        if let r = readingText {
            parts.append(r.lowercased() == "normal" ? "normal" : r.prefix(1).lowercased() + r.dropFirst() + (gold.map { " (GOLD \($0) if post-bronchodilator)" } ?? ""))
        }
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

/// A caution a study raises, with the source it rests on (shown behind ⓘ).
struct StudyCaution: Hashable, Identifiable {
    /// "harvest", "harvest-arm", "carotid", "vertebral".
    var id: String
    var text: String
    var source: String
    /// The words shown in bold red on the handoff: the caution's head, before its colon.
    var mark: String { text.components(separatedBy: ":").first ?? text }
}

enum PatientStudies {
    /// The vertebral flows that raise the subclavian-steal caution. Every pattern but normal antegrade flow and absent
    /// flow means a pressure gradient across the proximal subclavian (innominate on the right): partial reversal
    /// (alternating flow) is partial steal, reversed flow complete steal; absent flow (occluded or hypoplastic) is not
    /// steal. Kliewer MA, et al. AJR 2000;174:815 (abstract; the grouping is common teaching, no guideline defines it).
    static let stealFlows: Set<String> = ["partial", "reversed"]

    /// GOLD 1 FEV1 ≥80% predicted, 2 50–79%, 3 30–49%, 4 <30% (post-bronchodilator, with FEV1/FVC below 0.70).
    // GOLD 2025 report (Global Initiative for Chronic Obstructive Lung Disease): the grades of airflow obstruction, a
    // long-standing figure read from secondary sources; the post-bronchodilator FEV1/FVC < 0.7 rule from the 2025
    // Pocket Guide's text. Pre-bronchodilator spirometry rules COPD out, post-bronchodilator confirms it (Singh D, et al.
    // Eur Respir J 2025;65:2401603, abstract).
    static func goldGrade(fev1Pct p: Double) -> Int {
        if p >= 80 { return 1 }
        if p >= 50 { return 2 }
        if p >= 30 { return 3 }
        return 4
    }

    static let goldCaveat = "GOLD grading assumes post-bronchodilator values, with FEV1/FVC below 0.70; it is for COPD, not asthma."

    /// The device kinds that are a line in the arm: arterial lines, peripheral IVs and PICCs.
    static let armLineKinds: Set<DeviceKind> = [.arterial, .piv, .picc]

    static func otherSide(_ s: String) -> String { s == "left" ? "right" : "left" }

    /// "Planned left radial harvest: arterial line, IVs and BP cuff in the right arm." When the other arm has subclavian steal
    /// it reads low too, so neither radial is right for the arterial line: a femoral line is suggested instead.
    static func harvestReminder(_ r: PatientRecord) -> String? {
        guard let h = r.radial.harvestSide else { return nil }
        let other = otherSide(h)
        if r.carotid.reversedSides.contains(other) {
            return "Planned " + h + " radial harvest: IVs in the " + other + " arm, but it may read low (" + other + " vertebral flow reversed): consider a femoral arterial line."
        }
        return "Planned " + h + " radial harvest: arterial line, IVs and BP cuff in the " + other + " arm."
    }

    /// Arterial lines, IVs and PICCs in place on the arm planned for harvest.
    static func linesOnHarvestArm(_ r: PatientRecord) -> [PatientDevice] {
        guard let h = r.radial.harvestSide else { return [] }
        return r.currentDevices().filter { d in
            guard armLineKinds.contains(d.kind), let site = DeviceSite.site(id: d.site) else { return false }
            return site.region == "arm" && site.side == h
        }
    }

    // Gaudino M, et al. Expert systematic review on the choice of conduits for CABG, endorsed by EACTS and STS. Eur J
    // Cardiothorac Surg 2023;64:ezad163 (full text): "Previous catheterization of the RA is a contraindication to RA use
    // for CABG". No guideline names lines in the harvest arm: keeping them off it is practice extrapolated from that.
    static let harvestSource = "A radial artery that has been catheterized should not be used as a graft (EACTS/STS-endorsed review, Gaudino M, et al. Eur J Cardiothorac Surg 2023). Keeping lines, IVs and the cuff off the harvest arm follows from that; no guideline states it. With steal on the other arm, neither radial reads true, so a femoral line is suggested (practice)."
    // Grant EG, et al. Radiology 2003;229:340 (SRU categories, abstract); Naylor AR, et al. Eur J Vasc Endovasc Surg
    // 2002;23:283 (peri-CABG stroke: under 2% without carotid disease, about 3% unilateral and 5% bilateral 50–99%,
    // 7–11% with occlusion; about half of strokes occur without carotid disease); Thiele RH, et al. ASER/POQI-6, Anesth
    // Analg 2020;131:1444 (cerebral oximetry against a pre-induction baseline).
    static let carotidSource = "≥70%, near occlusion or occlusion (Society of Radiologists in Ultrasound categories, Grant EG, et al. Radiology 2003). Stroke with CABG is about 3% with one-sided 50–99% stenosis, 5% with both sides and 7–11% with an occlusion, against under 2% without; half of strokes occur without carotid disease (Naylor AR, et al. Eur J Vasc Endovasc Surg 2002). Cerebral oximetry is read against a pre-induction baseline (ASER/POQI, Thiele RH, et al. Anesth Analg 2020)."
    // Kliewer MA, et al. AJR 2000;174:815 (waveforms, abstract); Clark CE, et al. Lancet 2012;379:905 (an inter-arm
    // difference ≥10 mmHg is strongly associated with subclavian stenosis, abstract); Kilic ID, et al. Herz
    // 2013;38:250 (coronary–subclavian steal, abstract). The arterial line on the other side is practice.
    static let vertebralSource = "Reversed or alternating vertebral flow means subclavian steal: a stenosis of the subclavian (or, on the right, the innominate) before the vertebral (Kliewer MA, et al. AJR 2000). The arm beyond it reads low; a difference of 10 mmHg or more between the arms suggests it (Clark CE, et al. Lancet 2012). The internal mammary arises beyond the stenosis, so a graft from it on that side can steal from the coronaries (Kilic ID, et al. Herz 2013). Measuring on the other arm is practice, not a guideline."

    /// The cautions the studies raise, in the order the handoff reads them: the harvest arm first.
    static func cautions(_ r: PatientRecord) -> [StudyCaution] {
        var out: [StudyCaution] = []
        if let h = harvestReminder(r) { out.append(StudyCaution(id: "harvest", text: h, source: harvestSource)) }
        let onArm = linesOnHarvestArm(r)
        if !onArm.isEmpty, let h = r.radial.harvestSide {
            let names = PatientDevices.labels(onArm).joined(separator: "; ")
            out.append(StudyCaution(id: "harvest-arm", text: "On the " + h + " (harvest) arm: " + names + ". Move it to the other arm if you can.", source: harvestSource))
        }
        let severe = r.carotid.severeSides
        if !severe.isEmpty {
            let what = severe.map { s in s + " ICA " + (CarotidSide.stenosisLabel((s == "right" ? r.carotid.right : r.carotid.left).stenosis) ?? "").lowercased() }
            out.append(StudyCaution(id: "carotid", text: "Severe carotid disease: " + what.joined(separator: ", ") + ". Higher stroke risk with cardiac surgery, though most strokes after CABG are not carotid; consider a cerebral oximetry baseline before induction.", source: carotidSource))
        }
        for s in r.carotid.reversedSides {
            let partial = (s == "right" ? r.carotid.right : r.carotid.left).vertebral == "partial"
            let head = partial ? "Alternating " + s + " vertebral flow" : "Reversed " + s + " vertebral flow"
            let lesion = s == "right" ? "right subclavian or innominate" : "left subclavian"
            out.append(StudyCaution(id: "vertebral-" + s, text: head + ": suggests " + lesion + " stenosis. The " + s + " arm may read low: cuff and arterial line on the " + otherSide(s) + ". A " + s + " internal mammary graft would sit beyond the stenosis.", source: vertebralSource))
        }
        return out
    }
}

extension PatientStudies {
    static let carotidEvidence = "Record the ICA stenosis as the lab reports it. The usual categories are the Society of Radiologists in Ultrasound's (Grant EG, et al. Radiology 2003): peak systolic velocity under 125 cm/s for normal and under 50%, 125–230 for 50–69%, and over 230 for 70% or more; near occlusion can have high, low or no measurable velocity, and occlusion has no flow. Labs may use other validated criteria (IAC, Gornik HL, et al. Vasc Med 2021). Percentages are NASCET-method (ESC 2024); ECST percentages run higher. Vertebral flow: partial reversal (alternating) and reversed flow mean subclavian steal; absent flow does not (Kliewer MA, et al. AJR 2000)."
    static let radialEvidence = "The ulnar collateral circulation should always be assessed before a radial artery is harvested; the clinical Allen test depends on the examiner, and ultrasound adds the artery's diameter and calcification. Harvest the side with the better ulnar compensation and artery quality, not the nondominant arm by rule. A radial artery that has been catheterized should not be used (EACTS/STS-endorsed review, Gaudino M, et al. Eur J Cardiothorac Surg 2023). No society sets a minimum diameter: trials used 1.5 mm (RAPCO) or 2.0 mm (Agrifoglio M, et al. Ann Thorac Surg 2005)."
    static let pftEvidence = "Record the lab's reading as reported. ERS/ATS 2022 (Stanojevic S, et al. Eur Respir J 2022): obstruction is FEV1/FVC below the lower limit of normal; restriction needs a low TLC, since spirometry alone only suggests it; mixed is both; nonspecific is a low FEV1 or FVC with a normal ratio and TLC. Severity has three grades (mild, moderate, severe); older reports use five (ATS/ERS 2005). GOLD grades COPD by post-bronchodilator FEV1 % predicted when FEV1/FVC is below 0.70: 1 at 80% or more, 2 at 50–79%, 3 at 30–49%, 4 under 30% (GOLD 2025). It is shown when the reading includes obstruction and the ratio, if entered, is below 0.70."
}

extension PatientRecord {
    /// Any study beyond the heart recorded.
    var hasStudies: Bool { !carotid.isEmpty || !radial.isEmpty || !pft.isEmpty }
}
