import Foundation

/// A preprocedure stress test (1.11, Ben: "Exercise and dobutamine; minimal input, just a summary of findings"):
/// its kind, the result, when, and one line of findings. Lives in the Preprocedure cardiac workup beside the ECG,
/// echo and caths; read by the preop summary and the handoff's cardiac-workup block.
struct PatientStressTest: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case exercise, dobutamine, other
        var label: String {
            switch self {
            case .exercise: return "Exercise"
            case .dobutamine: return "Dobutamine"
            case .other: return "Other"
            }
        }
    }

    enum Result: String, Codable, CaseIterable {
        case negative, positive, equivocal
        var label: String {
            switch self {
            case .negative: return "Negative"
            case .positive: return "Positive"
            case .equivocal: return "Equivocal"
            }
        }
        /// The handoff's wording.
        var text: String {
            switch self {
            case .negative: return "negative, no ischemia"
            case .positive: return "positive for ischemia"
            case .equivocal: return "equivocal"
            }
        }
    }

    var kind: Kind?
    var result: Result?
    var date = PatientMonthYear()
    /// One line, as typed ("inferior wall ischemia at 7 METs").
    var findings = ""

    init(kind: Kind? = nil, result: Result? = nil, date: PatientMonthYear = PatientMonthYear(), findings: String = "") {
        self.kind = kind; self.result = result; self.date = date; self.findings = findings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try? c.decodeIfPresent(Kind.self, forKey: .kind)
        result = try? c.decodeIfPresent(Result.self, forKey: .result)
        date = (try? c.decodeIfPresent(PatientMonthYear.self, forKey: .date)) ?? PatientMonthYear()
        findings = (try? c.decodeIfPresent(String.self, forKey: .findings)) ?? ""
    }

    var isEmpty: Bool { kind == nil && result == nil && date.isEmpty && findings.trimmingCharacters(in: .whitespaces).isEmpty }

    /// "Dobutamine stress test (03/2025): negative, no ischemia; inferior wall ischemia at 7 METs" or nil when empty.
    var summary: String? { summary(dates: .app) }

    /// The same with the date as `style` writes it (1.12).
    func summary(dates: PatientDateStyle) -> String? {
        guard !isEmpty else { return nil }
        var head = (kind.map { $0 == .other ? "Stress test" : $0.label + " stress test" } ?? "Stress test")
        if !date.isEmpty { head += " (" + date.shown(dates) + ")" }
        var parts: [String] = []
        if let result { parts.append(result.text) }
        let f = findings.trimmingCharacters(in: .whitespaces)
        if !f.isEmpty { parts.append(f) }
        return parts.isEmpty ? head : head + ": " + parts.joined(separator: "; ")
    }
}
