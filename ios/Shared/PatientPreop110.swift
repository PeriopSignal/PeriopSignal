import Foundation

// MARK: - 1.10 Preprocedure tab (Ben's Nov 7 chat): the logic behind the "Planned Procedure & Anesthetic" box, the
// risk-score inputs link, the single-line chip rows and the second-tap clear. Views are in PatientPreopViews.swift and
// PatientComponents.swift.

/// A choice with its full words (what VoiceOver reads and what a wide row shows) and, where a short form keeps the
/// meaning, the words a narrow single-line row shows.
struct ChipChoice: Hashable, Identifiable {
    var id: String
    var label: String
    var short: String?
    /// What the chip says in a narrow row.
    var shown: String { short ?? label }
    init(_ id: String, _ label: String, short: String? = nil) { self.id = id; self.label = label; self.short = short }
}

enum PatientPreop110 {

    // MARK: Chips

    /// Functional capacity: "≥4 METs" and "<4 METs" keep their meaning short (2024 AHA/ACC: the 4-MET threshold); VoiceOver
    /// and the full-width row say "4 METs or more" and "Under 4 METs". The ids are what the record stores.
    static let mets: [ChipChoice] = [
        ChipChoice("ge4", "4 METs or more", short: "≥4 METs"),
        ChipChoice("lt4", "Under 4 METs", short: "<4 METs"),
        ChipChoice("unknown", "Unknown"),
    ]

    /// Planned anesthetic, in Ben's order and words: GA, MAC, PNB, Neuraxial. The ids are PatientCatalog.anesthetics'.
    static let anesthetics: [ChipChoice] = [
        ChipChoice("ga", "General", short: "GA"),
        ChipChoice("mac", "Sedation (MAC)", short: "MAC"),
        ChipChoice("regional", "Peripheral nerve block", short: "PNB"),
        ChipChoice("neuraxial", "Neuraxial"),
    ]

    /// ARISCAT incision: the ids ProcedureCatalog and the score use.
    static let incisions: [ChipChoice] = [
        ChipChoice("Peripheral", "Peripheral"),
        ChipChoice("Upper abdominal", "Upper abdominal", short: "Upper abd"),
        ChipChoice("Intrathoracic", "Intrathoracic"),
    ]

    /// ARISCAT expected duration: the ids ProcedureCatalog.durations holds.
    static let durations: [ChipChoice] = [
        ChipChoice("≤ 2 h", "2 h or less", short: "≤ 2 h"),
        ChipChoice("> 2–3 h", "Over 2 to 3 h", short: "> 2–3 h"),
        ChipChoice("> 3 h", "Over 3 h", short: "> 3 h"),
    ]

    static let sexes: [ChipChoice] = [ChipChoice("male", "Male"), ChipChoice("female", "Female")]

    // MARK: Yes / No pills

    /// A tap on No or Yes: the answer after it. A second tap on the answer shown clears it to unanswered.
    static func tapped(_ yes: Bool, from current: Bool?) -> Bool? { current == yes ? nil : yes }

    /// The No / Yes pills over an answer and the chips that hang from Yes (cardiac symptoms, acute cardiac conditions): Yes
    /// shows while an answer is Yes or a chip is picked, No while the answer is No with no chip. A second tap on what is
    /// shown clears the answer to unanswered, and clears the chips with it (a Yes carried only by a picked chip cannot be
    /// cleared otherwise); No clears the chips as it always did. One Undo step restores them.
    static func tapYesNo(_ yes: Bool, answer: inout Bool?, chips: inout Set<String>) {
        let shownYes = answer == true || !chips.isEmpty
        let shownNo = answer == false && chips.isEmpty
        if yes {
            if shownYes { answer = nil; chips = [] } else { answer = true }
        } else {
            if shownNo { answer = nil } else { answer = false; chips = [] }
        }
    }

    /// `tapYesNo` on a record's answer and chips (key paths), through locals: the two are parts of one record.
    static func tapYesNo(_ yes: Bool, answer: WritableKeyPath<PatientRecord, Bool?>, chips: WritableKeyPath<PatientRecord, Set<String>>, in r: inout PatientRecord) {
        var a = r[keyPath: answer], c = r[keyPath: chips]
        tapYesNo(yes, answer: &a, chips: &c)
        r[keyPath: answer] = a
        r[keyPath: chips] = c
    }

    // MARK: Planned Procedure & Anesthetic box

    /// "+ Urgency" while none is chosen (Ben's evening answer 2, Nov 7: renamed from "+ Procedure urgency"); once one is
    /// chosen the row collapses to "Urgency: Elective · Change".
    static func urgencyLinkTitle(_ r: PatientRecord) -> String { r.urgency.map { "Urgency: " + $0.label } ?? "Urgency" }

    /// The collapsed row's words once an urgency is chosen, the Change control included: "Urgency: Elective · Change".
    static func urgencyCollapsedParts(_ r: PatientRecord) -> (title: String, action: String)? {
        r.urgency == nil ? nil : (urgencyLinkTitle(r), "Change")
    }

    /// The risk-score inputs in one line for the "+ Risk-score inputs" link once any is filled: "High-risk surgery · Upper
    /// abdominal incision · Over 2 to 3 h". Nil while none is. A cardiac operation leaves the RCRI's high-risk switch out
    /// (PatientRules.cardiacSurgery), as the inputs page does.
    static func riskInputsLine(_ r: PatientRecord) -> String? {
        var parts: [String] = []
        if r.highRiskSurgery, !PatientRules.cardiacSurgery(r) { parts.append("High-risk surgery") }
        if let i = r.incision { parts.append((incisions.first { $0.id == i }?.label ?? i) + " incision") }
        if let d = r.duration { parts.append(durations.first { $0.id == d }?.label ?? d) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The names the old Procedure card's jump keys and the new box answer to: the box's scroll keys.
    static let boxAnchor = "planned"
    static let riskInputsAnchor = "riskinputs"
}
