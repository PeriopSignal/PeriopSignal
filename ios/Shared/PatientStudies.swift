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

    // TODO(research): labels as the SRU consensus categories (Grant 2003) name them.
    static let stenoses: [(id: String, label: String)] = [
        ("normal", "Normal"), ("lt50", "<50%"), ("50-69", "50–69%"), ("ge70", "≥70%"), ("near", "Near occlusion"), ("occluded", "Occluded"),
    ]
    // TODO(research): vertebral flow labels.
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
    /// RadialSide.ulnarOptions' ids: "normal", "reduced", "absent".
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

    // TODO(research): ulnar compensation labels.
    static let ulnarOptions: [(id: String, label: String)] = [("normal", "Normal"), ("reduced", "Reduced"), ("absent", "Absent")]
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

    // TODO(research): pattern and severity labels (ATS/ERS 2022 interpretation).
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

    /// The GOLD grade of airflow obstruction from FEV1 % predicted, when the lab reads obstruction.
    var gold: Int? {
        guard obstruction, let p = fev1Pct else { return nil }
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
            parts.append(r.lowercased() == "normal" ? "normal" : r.prefix(1).lowercased() + r.dropFirst() + (gold.map { " (GOLD \($0))" } ?? ""))
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
    /// The vertebral flows that raise the subclavian-steal caution.
    // TODO(research): whether partial reversal counts.
    static let stealFlows: Set<String> = ["reversed"]

    /// GOLD 1 FEV1 ≥80% predicted, 2 50–79%, 3 30–49%, 4 <30%.
    // TODO(research): GOLD report citation.
    static func goldGrade(fev1Pct p: Double) -> Int {
        if p >= 80 { return 1 }
        if p >= 50 { return 2 }
        if p >= 30 { return 3 }
        return 4
    }

    // TODO(research): the GOLD caveat wording and source.
    static let goldCaveat = "GOLD grades use the post-bronchodilator FEV1, in a patient with FEV1/FVC below 0.70."
    static let goldSource = "GOLD 2025 report, chapter 2: severity of airflow obstruction. TODO(research)"

    /// The device kinds that are a line in the arm: arterial lines, peripheral IVs and PICCs.
    static let armLineKinds: Set<DeviceKind> = [.arterial, .piv, .picc]

    /// "Planned left radial harvest: arterial line and IVs in the right arm."
    static func harvestReminder(_ r: PatientRecord) -> String? {
        guard let h = r.radial.harvestSide else { return nil }
        let other = h == "left" ? "right" : "left"
        return "Planned " + h + " radial harvest: arterial line and IVs in the " + other + " arm."
    }

    /// Arterial lines, IVs and PICCs in place on the arm planned for harvest.
    static func linesOnHarvestArm(_ r: PatientRecord) -> [PatientDevice] {
        guard let h = r.radial.harvestSide else { return [] }
        return r.currentDevices().filter { d in
            guard armLineKinds.contains(d.kind), let site = DeviceSite.site(id: d.site) else { return false }
            return site.region == "arm" && site.side == h
        }
    }

    // TODO(research): citations for each caution.
    static let harvestSource = "Radial artery harvest: keep the arterial line and IVs off the harvest arm. TODO(research)"
    static let carotidSource = "Severe carotid stenosis: ≥70% (SRU consensus, Grant 2003). TODO(research)"
    static let vertebralSource = "Reversed vertebral flow: subclavian steal. TODO(research)"

    /// The cautions the studies raise, in the order the handoff reads them: the harvest arm first.
    static func cautions(_ r: PatientRecord) -> [StudyCaution] {
        var out: [StudyCaution] = []
        // TODO(research): wording.
        if let h = harvestReminder(r) { out.append(StudyCaution(id: "harvest", text: h, source: harvestSource)) }
        let onArm = linesOnHarvestArm(r)
        if !onArm.isEmpty, let h = r.radial.harvestSide {
            let names = PatientDevices.labels(onArm).joined(separator: "; ")
            out.append(StudyCaution(id: "harvest-arm", text: "On the " + h + " (harvest) arm: " + names + ". Move it to the other arm if you can.", source: harvestSource))
        }
        let severe = r.carotid.severeSides
        if !severe.isEmpty {
            let what = severe.map { s in (s == "right" ? "right " : "left ") + "ICA " + (CarotidSide.stenosisLabel((s == "right" ? r.carotid.right : r.carotid.left).stenosis) ?? "").lowercased() }
            out.append(StudyCaution(id: "carotid", text: "Severe carotid disease: " + what.joined(separator: ", ") + ".", source: carotidSource))
        }
        for s in r.carotid.reversedSides {
            out.append(StudyCaution(id: "vertebral-" + s, text: "Reversed " + s + " vertebral flow: blood pressure in the " + s + " arm may read low, and it matters for a " + s + " internal mammary graft.", source: vertebralSource))
        }
        return out
    }
}

extension PatientStudies {
    // TODO(research): each page's Explanation & Evidence.
    static let carotidEvidence = "ICA stenosis in the categories of the Society of Radiologists in Ultrasound consensus (Grant EG, et al. Radiology 2003). TODO(research)"
    static let radialEvidence = "TODO(research)"
    static let pftEvidence = "TODO(research)"
}

extension PatientRecord {
    /// Any study beyond the heart recorded.
    var hasStudies: Bool { !carotid.isEmpty || !radial.isEmpty || !pft.isEmpty }
}
