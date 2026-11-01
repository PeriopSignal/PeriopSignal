import Foundation

// MARK: - Intraoperative extras: the last labs, blood products, and the major considerations for the handoff
//
// Lab ranges, as in PatientLabs: the ABIM Laboratory Test Reference Ranges, January 2026, for the arterial blood gas
// (pH 7.38–7.44, PaCO₂ 38–42 mmHg, PaO₂ 75–100 mmHg, bicarbonate 23–26 mEq/L), arterial lactate (under 1.3 mmol/L),
// ionized calcium (1.16–1.31 mmol/L) and the aPTT (25–35 s); hemoglobin, potassium, sodium, glucose, INR, fibrinogen and
// platelets reuse the preoperative catalog's entries and flags. PaO₂ is flagged only when low: on supplemental oxygen
// a value above the room-air range is expected. The ABIM list gives no range for base excess or the ACT, so they are
// recorded without a flag; for the ACT during cardiopulmonary bypass, the STS/SCA/AmSECT guideline (Shore-Lesserson L,
// et al. J Extra Corpor Technol 2018;50:5–18) finds it reasonable to keep it above 480 s (class IIa, level C), or
// above about 400 s on maximal-activation or microcuvette devices.

/// One set of intraoperative labs, drawn at one time.
struct IntraopLabSet: Codable, Hashable, Identifiable {
    var id = UUID()
    var time: Date?
    /// By PatientLabs key (IntraopLabs.abg and .coag).
    var values: [String: Double] = [:]
    /// ROTEM or TEG, as written.
    var viscoelastic = ""
    var other = ""

    init(time: Date? = nil, values: [String: Double] = [:], viscoelastic: String = "", other: String = "") {
        self.time = time; self.values = values; self.viscoelastic = viscoelastic; self.other = other
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        time = try? c.decodeIfPresent(Date.self, forKey: .time)
        values = (try? c.decodeIfPresent([String: Double].self, forKey: .values)) ?? [:]
        viscoelastic = (try? c.decodeIfPresent(String.self, forKey: .viscoelastic)) ?? ""
        other = (try? c.decodeIfPresent(String.self, forKey: .other)) ?? ""
    }

    var isEmpty: Bool {
        values.isEmpty && viscoelastic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && other.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum IntraopLabs {
    /// The tests the preoperative catalog lacks; PatientLabs.test finds them too.
    static let added: [LabTest] = [
        LabTest("ph", "pH", short: "pH", unit: "", group: .main, range: LabRange(7.38, 7.44), decimals: 2, plausible: 6.5...8.0),
        LabTest("paco2", "PaCO₂", short: "PaCO₂", unit: "mmHg", group: .main, range: LabRange(38, 42), decimals: 0, plausible: 5...200),
        LabTest("pao2", "PaO₂", short: "PaO₂", unit: "mmHg", group: .main, range: LabRange(75, nil), decimals: 0, plausible: 10...800,
                note: "Flagged only when low: on supplemental oxygen a value above the room-air range (75–100) is expected."),
        LabTest("hco3a", "Bicarbonate, arterial", short: "HCO₃", unit: "mmol/L", group: .main, range: LabRange(23, 26), decimals: 0, plausible: 1...60),
        LabTest("be", "Base excess", short: "BE", unit: "mmol/L", group: .main, decimals: 1, plausible: -40...40,
                note: "Not flagged: the ABIM ranges give none; read it against your analyzer's range."),
        LabTest("lactate", "Lactate, arterial", short: "Lactate", unit: "mmol/L", group: .main, range: LabRange(nil, 1.3, highInclusive: true),
                decimals: 1, plausible: 0...40),
        LabTest("ica", "Ionized calcium", short: "iCa", unit: "mmol/L", group: .main, range: LabRange(1.16, 1.31), decimals: 2, plausible: 0.2...4),
        LabTest("ptt", "aPTT", short: "PTT", unit: "s", group: .main, range: LabRange(25, 35), decimals: 0, plausible: 10...300),
        LabTest("act", "ACT", short: "ACT", unit: "s", group: .main, decimals: 0, plausible: 30...1500,
                note: "Not flagged: read against the target. During bypass, above 480 s is reasonable (STS/SCA/AmSECT 2018, class IIa), or above about 400 s on maximal-activation or microcuvette devices."),
    ]

    /// Blood gas, in the order analyzers print it.
    static let abg = ["ph", "paco2", "pao2", "hco3a", "be", "lactate", "hb", "k", "na", "ica", "glucose"]
    static let coag = ["inr", "ptt", "fibrinogen", "plt", "act"]
    static var keys: [String] { abg + coag }

    static func tests(_ keys: [String]) -> [LabTest] { keys.compactMap { PatientLabs.test($0) } }

    static let sources = "Reference ranges: ABIM Laboratory Test Reference Ranges, January 2026 (arterial pH 7.38–7.44, PaCO₂ 38–42 mmHg, PaO₂ 75–100 mmHg, bicarbonate 23–26 mEq/L, arterial lactate under 1.3 mmol/L, ionized calcium 1.16–1.31 mmol/L, aPTT 25–35 s); hemoglobin, potassium, sodium, platelets and fibrinogen as in the preoperative labs; INR from MedlinePlus; glucose 70–180 mg/dL, the ADA's perioperative range. PaO₂ is flagged only when low. Base excess and ACT have no ABIM range and are not flagged; during bypass an ACT above 480 s is reasonable (STS/SCA/AmSECT 2018, class IIa). Your laboratory's ranges may differ."

    /// The values entered in a set, in the screen's order, flagged.
    static func values(_ s: IntraopLabSet, sex: PatientSex?) -> [LabValue] {
        keys.compactMap { k in
            guard let t = PatientLabs.test(k), let v = s.values[k], v.isFinite else { return nil }
            return LabValue(key: k, label: t.short, value: v, text: t.format(v), unit: t.unit, flag: PatientLabs.flag(k, v, sex: sex),
                            rated: t.isRated, group: t.group, note: nil)
        }
    }

    /// The sets with anything in them, newest first: by time, and by order among sets without one (or the same time).
    static func ordered(_ sets: [IntraopLabSet]) -> [IntraopLabSet] { newestFirst(sets).filter { !$0.isEmpty } }

    /// Every set, newest first (a set just added, still empty, included).
    static func newestFirst(_ sets: [IntraopLabSet]) -> [IntraopLabSet] {
        let indexed = Array(sets.enumerated())
        let sorted = indexed.sorted { a, b in
            let ta: Date = a.element.time ?? Date.distantPast
            let tb: Date = b.element.time ?? Date.distantPast
            if ta != tb { return ta > tb }
            return a.offset > b.offset
        }
        return sorted.map { $0.element }
    }

    static func latest(_ r: PatientRecord) -> IntraopLabSet? { ordered(r.intraopLabs).first }

    /// "10:40 · pH 7.33 L · PaCO₂ 47 H · … · ROTEM/TEG: …", the abnormal values marked for bold red. `abnormalOnly`
    /// (the short handoff) keeps the flagged values and counts the rest.
    static func line(_ s: IntraopLabSet, sex: PatientSex?, now: Date = Date(), abnormalOnly: Bool = false) -> PatientSummary.Line? {
        let vals = values(s, sex: sex)
        let flagged = vals.filter { $0.flag.isAbnormal }
        var parts = (abnormalOnly ? flagged : vals).map(\.compact)
        if abnormalOnly && vals.count > flagged.count {
            let n = vals.count - flagged.count
            parts.append(flagged.isEmpty ? "\(n) value\(n == 1 ? "" : "s"), none flagged" : "\(n) more not flagged")
        }
        let ve = s.viscoelastic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ve.isEmpty { parts.append("ROTEM/TEG: " + ve) }
        let other = s.other.trimmingCharacters(in: .whitespacesAndNewlines)
        if !other.isEmpty { parts.append(other) }
        guard !parts.isEmpty else { return nil }
        let head = s.time.map { PatientSummary.time($0, now: now) + " · " } ?? ""
        return PatientSummary.Line("Last labs", head + parts.joined(separator: " · "), marks: flagged.map(\.compact))
    }

    static func lastLine(_ r: PatientRecord, now: Date = Date(), abnormalOnly: Bool = false) -> PatientSummary.Line? {
        latest(r).flatMap { line($0, sex: r.sex, now: now, abnormalOnly: abnormalOnly) }
    }
}

// MARK: - Blood products

enum BloodProducts {
    /// Counted in units with + and −; the keys are PatientRecord.fluids' own.
    static let units: [(id: String, label: String, short: String)] = [
        ("prbc", "Red cells (PRBC)", "PRBC"), ("plasma", "Plasma (FFP)", "FFP"), ("platelets", "Platelets", "Platelets"),
        ("cryo", "Cryoprecipitate", "Cryo"), ("wholeBlood", "Whole blood", "Whole blood"),
    ]
    static let cellSaver = "cellSaver"
    static let cellSaverStep = 50.0
    static var ids: [String] { units.map(\.id) + [cellSaver] }

    /// "PRBC 2 units · FFP 2 units · Cryo 10 units · Cell saver 450 mL", the case's totals.
    static func text(_ r: PatientRecord) -> String {
        var parts: [String] = units.compactMap { u in
            guard let v = r.fluids[u.id], v > 0 else { return nil }
            return u.short + " " + NumText.short(v) + (v == 1 ? " unit" : " units")
        }
        if let v = r.fluids[cellSaver], v > 0 { parts.append("Cell saver " + NumText.short(v) + " mL") }
        return parts.joined(separator: " · ")
    }

    static func line(_ r: PatientRecord) -> PatientSummary.Line? {
        let t = text(r)
        return t.isEmpty ? nil : PatientSummary.Line("Blood products", t)
    }
}

// MARK: - Major intraoperative considerations

enum IntraopConsiderations {
    static let flags: [PatientFlag] = [
        PatientFlag("difficult-airway", "Difficult airway"),
        PatientFlag("massive-transfusion", "Massive transfusion"),
        PatientFlag("pressors", "Hemodynamic instability on pressors"),
        PatientFlag("tee", "Significant TEE findings"),
        PatientFlag("surgical", "Surgical concerns"),
        PatientFlag("positioning", "Positioning or pressure points"),
        PatientFlag("awareness", "Awareness risk"),
        PatientFlag("other", "Other"),
    ]

    /// "Difficult airway; Positioning or pressure points; steep Trendelenburg 3 h". "Other" alone, with nothing
    /// typed, still shows.
    static func text(_ r: PatientRecord) -> String? {
        let typed = r.considerationsNote.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = flags.filter { r.considerations.contains($0.id) && $0.id != "other" }.map(\.label)
        if !typed.isEmpty { items.append(typed) } else if r.considerations.contains("other") { items.append("Other") }
        return items.isEmpty ? nil : items.joined(separator: "; ")
    }

    static func line(_ r: PatientRecord) -> PatientSummary.Line? {
        text(r).map { PatientSummary.Line("Key considerations", $0, alert: true) }
    }

    /// Chips the record suggests and that are not on yet: a difficult airway recorded in the airway course.
    static func suggested(_ r: PatientRecord) -> [PatientFlag] {
        var ids: [String] = []
        if PatientSummary.difficultAirway(r) || r.anesthesiaHistory.contains("difficult-airway") { ids.append("difficult-airway") }
        return flags.filter { ids.contains($0.id) && !r.considerations.contains($0.id) }
    }
}

extension HandoffWriter {
    /// The parts of the handoff to show in bold red on the screen: abnormal labs, before and during the case, and the
    /// liver scores.
    static func marks(_ r: PatientRecord) -> [String] {
        var out = PatientSummary.labsLine(r)?.marks ?? []
        out += PatientSummary.liverLine(r)?.marks ?? []
        out += IntraopLabs.lastLine(r)?.marks ?? []
        out += PatientCodeStatus.line(r)?.marks ?? []
        return out
    }
}
