import Foundation

// MARK: - Preprocedure results that are not a number (1.12, Ben's note 12)
//
// "+ Pregnancy test": a Negative chip and/or an hCG value as typed; "+ Infectious labs": urinalysis (a Negative chip, or
// findings), blood cultures (a Negative chip, or what grew) and the vancomycin level. The numbers (the typed hCG when it
// reads as a number, the vancomycin level, TSH and free T4) are in `PatientRecord.labs` under "hcg", "vanc", "tsh" and
// "ft4"; what is not a number is here. No reference range is shown for the hCG or the vancomycin level: the hCG's depends
// on the assay and the setting, and a vancomycin target depends on the indication (the catalog gives none, so nothing is
// invented). TSH and free T4 were already in the thyroid group (ABIM Laboratory Test Reference Ranges, January 2026), so
// they keep that source.

/// Urinalysis findings that have a chip: the four a dipstick and a microscopy report most often.
struct UrinalysisFinding: Hashable, Identifiable {
    var id: String
    var label: String
}

/// Preprocedure results that are not a number in `PatientRecord.labs`: the pregnancy test (negative, or an hCG value as
/// typed), urinalysis and blood cultures (negative, or findings). Every field has a default and is read with a fallback in
/// `init(from:)`, so a record saved by an older version still opens.
struct PatientMoreLabs: Codable, Hashable {
    /// The pregnancy test was negative (a urine or serum test; the hCG value, if any, is beside it).
    var pregnancyNegative = false
    /// The hCG value as typed when it does not read as a number ("<5", "pending"); a number goes to `labs["hcg"]`.
    var hcgText = ""
    /// Urinalysis: negative, or the findings (chips by `UrinalysisFinding.id`, and free text).
    var uaNegative = false
    var uaFindings: Set<String> = []
    var uaText = ""
    /// Blood cultures: negative, or what is known (free text).
    var bloodCxNegative = false
    var bloodCxText = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pregnancyNegative = (try? c.decodeIfPresent(Bool.self, forKey: .pregnancyNegative)) ?? false
        hcgText = (try? c.decodeIfPresent(String.self, forKey: .hcgText)) ?? ""
        uaNegative = (try? c.decodeIfPresent(Bool.self, forKey: .uaNegative)) ?? false
        uaFindings = (try? c.decodeIfPresent(Set<String>.self, forKey: .uaFindings)) ?? []
        uaText = (try? c.decodeIfPresent(String.self, forKey: .uaText)) ?? ""
        bloodCxNegative = (try? c.decodeIfPresent(Bool.self, forKey: .bloodCxNegative)) ?? false
        bloodCxText = (try? c.decodeIfPresent(String.self, forKey: .bloodCxText)) ?? ""
    }

    var isEmpty: Bool { self == PatientMoreLabs() }

    // MARK: Words

    static let urinalysisFindings: [UrinalysisFinding] = [
        UrinalysisFinding(id: "le", label: "Leukocyte esterase +"),
        UrinalysisFinding(id: "nitrite", label: "Nitrite +"),
        UrinalysisFinding(id: "bacteria", label: "Bacteria"),
        UrinalysisFinding(id: "pyuria", label: "Pyuria"),
    ]

    private static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    var hcgTyped: String { Self.trimmed(hcgText) }
    var uaTyped: String { Self.trimmed(uaText) }
    var bloodCxTyped: String { Self.trimmed(bloodCxText) }

    /// The findings chosen, in the chips' order.
    var uaFindingLabels: [String] { Self.urinalysisFindings.filter { uaFindings.contains($0.id) }.map(\.label) }

    var hasPregnancy: Bool { pregnancyNegative || !hcgTyped.isEmpty }
    var hasUrinalysis: Bool { uaNegative || !uaFindings.isEmpty || !uaTyped.isEmpty }
    var hasBloodCultures: Bool { bloodCxNegative || !bloodCxTyped.isEmpty }
    /// Something in the infectious labs group beyond the vancomycin level (a number, in `labs`).
    var hasInfectious: Bool { hasUrinalysis || hasBloodCultures }

    /// "Pregnancy test neg" and "hCG <5" as typed (an hCG that is a number is `labs["hcg"]`, on the numbers' line).
    var pregnancyParts: [String] {
        [pregnancyNegative ? "Pregnancy test neg" : nil, hcgTyped.isEmpty ? nil : "hCG " + hcgTyped].compactMap { $0 }
    }

    /// "Pregnancy test neg", "hCG <5", "Pregnancy test neg, hCG <5"; an hCG that is a number (`labs["hcg"]`) is passed as
    /// `number` ("hCG 12"). Nil with nothing recorded.
    func pregnancyText(number: String? = nil) -> String? {
        let parts = number.map { n in [pregnancyNegative ? "Pregnancy test neg" : nil, "hCG " + n].compactMap { $0 } } ?? pregnancyParts
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// "UA neg", "UA: leukocyte esterase +, nitrite +; cloudy" (findings first, then the typed words).
    var urinalysisText: String? {
        guard hasUrinalysis else { return nil }
        if uaNegative && uaFindings.isEmpty && uaTyped.isEmpty { return "UA neg" }
        let parts = uaFindingLabels.map { $0.lowercased() } + (uaTyped.isEmpty ? [] : [uaTyped])
        return "UA: " + parts.joined(separator: ", ")
    }

    /// "Blood cx neg", "Blood cx: GPC in clusters, 1 of 2 bottles".
    var bloodCulturesText: String? {
        guard hasBloodCultures else { return nil }
        if bloodCxNegative && bloodCxTyped.isEmpty { return "Blood cx neg" }
        return "Blood cx: " + bloodCxTyped
    }

    /// A urinalysis with a finding, or blood cultures with anything but "negative", is something the next team has to
    /// read (bold red, as a positive MRSA is).
    var urinalysisNeedsTelling: Bool { !uaFindings.isEmpty || !uaTyped.isEmpty }
    var bloodCulturesNeedTelling: Bool { !bloodCxTyped.isEmpty }

    /// The infectious labs' parts for the labs line, the urinalysis then the blood cultures, with those to show in red.
    var infectiousParts: (parts: [String], marks: [String]) {
        var parts: [String] = []
        var marks: [String] = []
        if let t = urinalysisText { parts.append(t); if urinalysisNeedsTelling { marks.append(t) } }
        if let t = bloodCulturesText { parts.append(t); if bloodCulturesNeedTelling { marks.append(t) } }
        return (parts, marks)
    }

    // MARK: Changes

    /// Negative and findings exclude each other: choosing Negative clears the findings and the words; a finding or words
    /// (and "negative" chosen again, to clear it) leave Negative off.
    mutating func setUrinalysisNegative(_ on: Bool) {
        uaNegative = on
        if on {
            uaFindings = []
            uaText = ""
        }
    }

    mutating func toggleUrinalysisFinding(_ id: String) {
        if uaFindings.contains(id) { uaFindings.remove(id) } else { uaFindings.insert(id) }
        if !uaFindings.isEmpty { uaNegative = false }
    }

    mutating func setUrinalysisText(_ s: String) {
        uaText = s
        if !Self.trimmed(s).isEmpty { uaNegative = false }
    }

    mutating func setBloodCulturesNegative(_ on: Bool) {
        bloodCxNegative = on
        if on { bloodCxText = "" }
    }

    mutating func setBloodCulturesText(_ s: String) {
        bloodCxText = s
        if !Self.trimmed(s).isEmpty { bloodCxNegative = false }
    }

    /// The typed hCG: a number is a lab (`labs["hcg"]`, shown and kept like any other), anything else ("<5", "pending")
    /// stays as typed here; never both.
    static func setHCG(_ text: String, in r: inout PatientRecord) {
        let t = trimmed(text)
        if let n = Double(t.replacingOccurrences(of: ",", with: ".")), n.isFinite, n >= 0 {
            r.labs["hcg"] = n
            r.moreLabs.hcgText = ""
        } else {
            r.labs["hcg"] = nil
            r.moreLabs.hcgText = text
        }
    }

    /// What the hCG field shows: the number as the catalog formats it, else the words as typed.
    static func hcgField(_ r: PatientRecord) -> String {
        if let n = r.labs["hcg"], let t = PatientLabs.test("hcg") { return t.format(n) }
        return r.moreLabs.hcgText
    }

    /// The pregnancy test belongs to the Labs page and the summaries unless the patient is male (shown for a woman and for
    /// a patient whose sex is not set).
    static func showsPregnancy(_ sex: PatientSex?) -> Bool { sex != .male }
}
