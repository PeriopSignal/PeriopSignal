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

/// The sample the blood gas in a lab set came from (1.12, Ben's note 13): arterial (the default, and what every set saved
/// before 1.12 is), a venous gas, or a central venous (ScvO₂, from the CVL) or mixed venous (SvO₂, from the PA catheter)
/// saturation sample. The arterial reference ranges and H/L flags are not applied to a venous sample, and the labels follow.
enum BloodGasType: String, Codable, CaseIterable, Hashable {
    case abg, vbg, scvo2, svo2

    /// The menu's words: "ABG", "VBG", "ScvO₂ (CVL)", "SvO₂ (PA)".
    var label: String {
        switch self {
        case .abg: return "ABG"
        case .vbg: return "VBG"
        case .scvo2: return "ScvO₂ (CVL)"
        case .svo2: return "SvO₂ (PA)"
        }
    }

    /// The summaries' and the menu's short words: "ABG", "VBG", "ScvO₂", "SvO₂".
    var short: String {
        switch self {
        case .abg: return "ABG"
        case .vbg: return "VBG"
        case .scvo2: return "ScvO₂"
        case .svo2: return "SvO₂"
        }
    }

    /// Everything but an arterial sample.
    var isVenous: Bool { self != .abg }
    /// The saturation is the value of interest of ScvO₂ and SvO₂ samples, so the set has a field for it.
    var hasSaturation: Bool { self == .scvo2 || self == .svo2 }
}

/// One set of intraoperative labs, drawn at one time.
struct IntraopLabSet: Codable, Hashable, Identifiable {
    var id = UUID()
    var time: Date?
    /// By PatientLabs key (IntraopLabs.abg and .coag).
    var values: [String: Double] = [:]
    /// ROTEM or TEG, as written.
    var viscoelastic = ""
    var other = ""
    /// The blood gas's sample (1.12); ABG for a set saved before it.
    var gasType: BloodGasType = .abg

    init(time: Date? = nil, values: [String: Double] = [:], viscoelastic: String = "", other: String = "", gasType: BloodGasType = .abg) {
        self.time = time; self.values = values; self.viscoelastic = viscoelastic; self.other = other; self.gasType = gasType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        time = try? c.decodeIfPresent(Date.self, forKey: .time)
        values = (try? c.decodeIfPresent([String: Double].self, forKey: .values)) ?? [:]
        viscoelastic = (try? c.decodeIfPresent(String.self, forKey: .viscoelastic)) ?? ""
        other = (try? c.decodeIfPresent(String.self, forKey: .other)) ?? ""
        gasType = (try? c.decodeIfPresent(BloodGasType.self, forKey: .gasType)) ?? .abg
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
        lactate,
        LabTest("ica", "Ionized calcium", short: "iCa", unit: "mmol/L", group: .main, range: LabRange(1.16, 1.31), decimals: 2, plausible: 0.2...4),
        ptt,
        LabTest("act", "ACT", short: "ACT", unit: "s", group: .main, decimals: 0, plausible: 30...1500,
                note: "Not flagged: read against the target. During bypass, above 480 s is reasonable (STS/SCA/AmSECT 2018, class IIa), or above about 400 s on maximal-activation or microcuvette devices."),
        // 1.12 (Ben's note 13): the saturation of a central venous (ScvO₂) or mixed venous (SvO₂) sample, the value of interest
        // of those gases. No reference range: what a saturation should be depends on the patient and the question, so none
        // is invented and it is never flagged. The words follow the sample (IntraopLabs.test(_:type:)).
        LabTest(satKey, "Venous oxygen saturation", short: "SvO₂", unit: "%", group: .main, decimals: 0, plausible: 1...100,
                note: "Not flagged: no reference range is shown; read it against the clinical target."),
    ]

    /// The saturation of an ScvO₂ or SvO₂ sample (1.12).
    static let satKey = "so2v"

    /// The aPTT: ABIM 25–35 s. The preoperative catalog (1.9) reuses this entry, so the same value is flagged the same way
    /// before and during the case; the PT beside it has no flag (PatientLabs.catalog).
    static let ptt = LabTest("ptt", "aPTT", short: "PTT", unit: "s", group: .main, range: LabRange(25, 35), decimals: 0, plausible: 10...300)

    /// The gas's lactate; the preoperative catalog's "Lactate" (1.8.3) reuses its unit, range and note.
    static let lactate = LabTest("lactate", "Lactate, arterial", short: "Lactate", unit: "mmol/L", group: .main, range: LabRange(nil, 2.0),
                                 decimals: 1, plausible: 0...40,
                                 note: "High above 2 mmol/L, the Sepsis-3 septic-shock lactate criterion (Singer M, et al. JAMA 2016;315:801); the ABIM arterial reference limit is stricter (under 1.3).")

    /// Blood gas, in the order analyzers print it.
    /// 1.12 (Ben's note 13): the glucose has a section of its own above the blood gas card, so it is not in `abg` any more.
    static let abg = ["ph", "paco2", "pao2", "hco3a", "be", "lactate", "hb", "k", "na", "ica"]
    static let glucoseKeys = ["glucose"]
    /// 1.11 (Ben, Nov 9): the gas's slash figure, pH / PaCO₂ / PaO₂ / HCO₃, typed into its slots on the intraoperative
    /// labs page; the rest of the gas follows as rows. Together they are `abg`, in its order, so Next walks them the same.
    static let abgSlash = ["ph", "paco2", "pao2", "hco3a"]
    static var abgRest: [String] { abg.filter { !abgSlash.contains($0) } }
    static let coag = ["inr", "ptt", "fibrinogen", "plt", "act"]
    /// Every intraoperative test, in the order the "Last labs" line prints them (the glucose keeps its old place after the
    /// ionized calcium, the saturation comes last).
    static var keys: [String] { abg + glucoseKeys + coag + [satKey] }

    /// A set holding any of these is a blood gas (the summaries show the newest one, with its lactate).
    static var gasKeys: [String] { abgSlash + [satKey] }

    /// The set's fields on its page, top to bottom, which is the order Previous and Next walk: the glucose, the saturation
    /// of an ScvO₂ or SvO₂ sample, the gas, the coagulation.
    static func pageOrder(_ type: BloodGasType) -> [String] {
        glucoseKeys + (type.hasSaturation ? [satKey] : []) + abg + coag
    }

    /// The tests by key, this list's own entry first ("Lactate, arterial"), then the preoperative catalog's.
    static func tests(_ keys: [String]) -> [LabTest] { keys.compactMap { k in added.first { $0.key == k } ?? PatientLabs.test(k) } }

    // MARK: The gas's sample (1.12)

    /// The values the arterial reference ranges are for; a venous sample is not judged by them.
    static let arterialRated: Set<String> = ["ph", "paco2", "pao2", "hco3a"]

    /// Whether the catalog's range applies to this value of a gas of this type. The lactate's (above 2 mmol/L, the Sepsis-3
    /// criterion) is not an arterial range, so it still applies to a venous sample; so do the ones of the ions, hemoglobin
    /// and glucose.
    static func isRanged(_ key: String, type: BloodGasType) -> Bool { !(type.isVenous && arterialRated.contains(key)) }

    /// The test as a gas of this type reads it: PvCO₂ and PvO₂ for a venous gas, "Lactate" and "Bicarbonate" without
    /// "arterial", no arterial range on the gas values, and the saturation named for its sample.
    static func test(_ key: String, type: BloodGasType) -> LabTest? {
        guard var t = added.first(where: { $0.key == key }) ?? PatientLabs.test(key) else { return nil }
        if key == satKey {
            switch type {
            case .scvo2: t.label = "ScvO₂ saturation"; t.short = "ScvO₂"
            case .svo2: t.label = "SvO₂ saturation"; t.short = "SvO₂"
            default: break
            }
            return t
        }
        guard type.isVenous else { return t }
        switch key {
        case "paco2": t.label = "PvCO₂"; t.short = "PvCO₂"
        case "pao2": t.label = "PvO₂"; t.short = "PvO₂"
        case "hco3a": t.label = "Bicarbonate"
        case "lactate": t.label = "Lactate"
        default: break
        }
        if !isRanged(key, type: type) {
            t.range = nil
            t.female = nil
            t.male = nil
            t.note = "Not flagged: the arterial reference range is not applied to a venous sample."
        }
        return t
    }

    static func tests(_ keys: [String], type: BloodGasType) -> [LabTest] { keys.compactMap { test($0, type: type) } }

    /// Normal, low or high; a venous sample's gas values are never flagged against the arterial ranges.
    static func flag(_ key: String, _ value: Double, sex: PatientSex?, type: BloodGasType) -> LabFlag {
        isRanged(key, type: type) ? PatientLabs.flag(key, value, sex: sex) : .normal
    }

    /// The newest set that holds a blood gas (a value of the slash figure, or the saturation): the gas the summaries show.
    static func latestGas(_ sets: [IntraopLabSet]) -> IntraopLabSet? {
        ordered(sets).first { s in gasKeys.contains { (s.values[$0] ?? .nan).isFinite } }
    }

    static let sources = "Reference ranges: ABIM Laboratory Test Reference Ranges, January 2026 (arterial pH 7.38–7.44, PaCO₂ 38–42 mmHg, PaO₂ 75–100 mmHg, bicarbonate 23–26 mEq/L, arterial lactate under 1.3 mmol/L (flagged here above 2, the Sepsis-3 criterion), ionized calcium 1.16–1.31 mmol/L, aPTT 25–35 s); hemoglobin, potassium, sodium, platelets and fibrinogen as in the preoperative labs; INR from MedlinePlus; glucose flagged above 180 mg/dL (ADA perioperative target 100–180 mg/dL) and below 70 (hypoglycemia). PaO₂ is flagged only when low. Base excess and ACT have no ABIM range and are not flagged; during bypass an ACT above 480 s is reasonable (STS/SCA/AmSECT 2018, class IIa). The pH, carbon dioxide, oxygen and bicarbonate ranges are arterial: they are not applied to a venous gas (VBG, ScvO₂, SvO₂), whose values are not flagged (the lactate and the other values keep their ranges); the saturation has no range. Your laboratory's ranges may differ."

    /// The values entered in a set, in the screen's order, flagged.
    static func values(_ s: IntraopLabSet, sex: PatientSex?) -> [LabValue] {
        keys.compactMap { k in
            guard let t = test(k, type: s.gasType), let v = s.values[k], v.isFinite else { return nil }
            return LabValue(key: k, label: t.short, value: v, text: t.format(v), unit: t.unit, flag: flag(k, v, sex: sex, type: s.gasType),
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

    /// "10:40 · pH 7.33 · PaCO₂ 47 · … · ROTEM/TEG: …", the abnormal values marked for bold red (with no H or L after them,
    /// 1.12; `plain` is the same line with the letters, for the plain text). `abnormalOnly` (the short handoff) keeps the
    /// flagged values and counts the rest.
    static func line(_ s: IntraopLabSet, sex: PatientSex?, now: Date = Date(), abnormalOnly: Bool = false) -> PatientSummary.Line? {
        let vals = values(s, sex: sex)
        // Values with no range to judge them by (base excess, ACT) are listed rather than counted as unflagged.
        let flagged = vals.filter { $0.flag.isAbnormal }
        let listed = vals.filter { $0.flag.isAbnormal || !$0.rated }
        let shown = abnormalOnly ? listed : vals
        var parts = shown.map(\.compact)
        var plainParts = shown.map(\.plainCompact)
        var spokenParts = shown.map(\.spokenCompact)
        func add(_ t: String) { parts.append(t); plainParts.append(t); spokenParts.append(t) }
        if abnormalOnly && vals.count > listed.count {
            let n = vals.count - listed.count
            add(listed.isEmpty ? "\(n) value\(n == 1 ? "" : "s"), none flagged" : "\(n) more not flagged")
        }
        let ve = s.viscoelastic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ve.isEmpty { add("ROTEM/TEG: " + ve) }
        let other = s.other.trimmingCharacters(in: .whitespacesAndNewlines)
        if !other.isEmpty { add(other) }
        guard !parts.isEmpty else { return nil }
        // A venous sample says so (1.12): its pH and PvCO₂ must not be read as arterial.
        let kind: String? = s.gasType.isVenous && s.values.keys.contains(where: { gasKeys.contains($0) }) ? s.gasType.short : nil
        let head = [kind, s.time.map { PatientSummary.time($0, now: now) }].compactMap { $0 }.joined(separator: " ")
        let lead = head.isEmpty ? "" : head + " · "
        return PatientSummary.Line("Last labs", lead + parts.joined(separator: " · "), marks: flagged.map(\.compact),
                                   plain: lead + plainParts.joined(separator: " · "), spoken: lead + spokenParts.joined(separator: " · "))
    }

    static func lastLine(_ r: PatientRecord, now: Date = Date(), abnormalOnly: Bool = false) -> PatientSummary.Line? {
        latest(r).flatMap { line($0, sex: r.sex, now: now, abnormalOnly: abnormalOnly) }
    }
}

// MARK: - Blood products

enum BloodProducts {
    /// Counted in units with + and −; the keys are PatientRecord.fluids' own.
    static let units: [(id: String, label: String, short: String)] = [
        ("prbc", "Red cells (PRBC)", "PRBC"), ("plasma", "Plasma (FFP)", "FFP"), ("platelets", "Platelets (apheresis or pooled doses)", "Platelets"),
        ("cryo", "Cryoprecipitate", "Cryo"), ("wholeBlood", "Whole blood", "Whole blood"),
    ]
    static let cellSaver = "cellSaver"
    static let cellSaverStep = 50.0
    static var ids: [String] { units.map(\.id) + [cellSaver] }

    /// Crystalloid and colloid also get − and +, one tap a bag or bottle: 1000 mL of crystalloid, 250 mL of albumin
    /// (Ben, Nov 2). The total can still be typed; blood loss and urine stay typed.
    static let fluidSteps: [String: Double] = ["crystalloid": 1000, "colloid": 250]
    static let fluidLimit = 30000.0

    /// "PRBC 2 units · FFP 2 units · Cryo 10 units · Cell saver 450 mL", the case's totals.
    static func text(_ r: PatientRecord) -> String {
        var parts: [String] = units.compactMap { u in
            guard let v = r.fluids[u.id], v > 0 else { return nil }
            // Platelets come as doses (one apheresis unit or one pool); the rest as units.
            let word = u.id == "platelets" ? "dose" : "unit"
            return u.short + " " + NumText.short(v) + " " + word + (v == 1 ? "" : "s")
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
        let r = r.capitalized
        var out = PatientSummary.labsLine(r)?.marks ?? []
        out += PatientSummary.liverLine(r)?.marks ?? []
        out += IntraopLabs.lastLine(r)?.marks ?? []
        out += PatientCodeStatus.line(r)?.marks ?? []
        out += PatientTEE.line(r)?.marks ?? []
        out += PatientStudies.cautions(r).map(\.mark)
        return out
    }
}
