import Foundation

/// The preprocedure chest X-ray (1.12, Ben's note 11): normal, or an effusion (its side and size), and one line of
/// findings as typed. It sits in the Preprocedure cardiac workup beside the ECG, echo and stress test; its line is read by
/// the workup row and by the cardiac-workup block of the preprocedure summary and the handoff. The page records what the
/// report said and grades nothing itself.
///
/// Every field has a default and is read with a fallback in `init(from:)`, so a record saved by an older version (which
/// has no chest X-ray at all) still opens.
struct PatientChestXray: Codable, Hashable {
    /// Normal and Effusion exclude each other: one value, so both can never be on.
    enum Result: String, Codable, CaseIterable {
        case normal, effusion
        var label: String { self == .normal ? "Normal" : "Effusion" }
    }

    /// The side of an effusion (only meaningful with `.effusion`).
    enum Side: String, Codable, CaseIterable {
        case left, right, bilateral
        var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    /// The size of an effusion (only meaningful with `.effusion`).
    enum Size: String, Codable, CaseIterable {
        case small, moderate, large
        var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    var result: Result?
    /// Kept only while the result is an effusion.
    var side: Side?
    var size: Size?
    /// One line, as typed ("blunting of the left costophrenic angle").
    var findings = ""

    init(result: Result? = nil, side: Side? = nil, size: Size? = nil, findings: String = "") {
        self.result = result; self.side = side; self.size = size; self.findings = findings
        tidy()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        result = try? c.decodeIfPresent(Result.self, forKey: .result)
        side = try? c.decodeIfPresent(Side.self, forKey: .side)
        size = try? c.decodeIfPresent(Size.self, forKey: .size)
        findings = (try? c.decodeIfPresent(String.self, forKey: .findings)) ?? ""
        tidy()
    }

    /// A side or size means nothing without an effusion: drop them so a stale one can never read as a finding.
    private mutating func tidy() {
        if result != .effusion { side = nil; size = nil }
    }

    var isEmpty: Bool { result == nil && findings.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// A tap on a result chip: the same chip again clears it; Normal drops the effusion's side and size, and an effusion
    /// replaces Normal (the two never stand together).
    mutating func choose(_ r: Result?) {
        result = r
        tidy()
    }

    /// "moderate left effusion", "bilateral effusion", "effusion"; nil unless the result is an effusion. The words in
    /// the order a report reads them: size, side, effusion.
    var effusionText: String? {
        guard result == .effusion else { return nil }
        var words: [String] = []
        if let size { words.append(size.rawValue) }
        if let side { words.append(side.rawValue) }
        words.append("effusion")
        return words.joined(separator: " ")
    }

    /// The finding without its label: "Normal", "moderate left effusion; blunted angle", or the findings alone when no
    /// result is chosen. nil when empty.
    var text: String? {
        guard !isEmpty else { return nil }
        var parts: [String] = []
        switch result {
        case .normal?: parts.append("Normal")
        case .effusion?: parts.append(effusionText ?? "effusion")
        case nil: break
        }
        let f = findings.trimmingCharacters(in: .whitespacesAndNewlines)
        if !f.isEmpty { parts.append(f) }
        return parts.joined(separator: "; ")
    }

    /// "Chest X-ray: Normal" or "Chest X-ray: moderate left effusion; blunted angle"; nil when empty.
    var summary: String? { text.map { "Chest X-ray: " + $0 } }

    /// The line of the briefs' Preprocedure cardiac workup block, labelled "Chest X-ray". An effusion is marked for
    /// attention: its words are bold red in the summary. The findings are capitalized as the other typed text is.
    static func line(_ r: PatientRecord) -> PatientSummary.Line? {
        let x = r.chestXray
        guard !x.isEmpty else { return nil }
        var parts: [String] = []
        switch x.result {
        case .normal?: parts.append("Normal")
        case .effusion?: parts.append(x.effusionText ?? "effusion")
        case nil: break
        }
        let f = FreeText.cap(x.findings.trimmingCharacters(in: .whitespacesAndNewlines))
        if !f.isEmpty { parts.append(f) }
        let effusion = x.result == .effusion
        return PatientSummary.Line("Chest X-ray", parts.joined(separator: "; "), alert: effusion, marks: effusion ? [x.effusionText ?? "effusion"] : [])
    }
}
