import Foundation

// MARK: - Code status and the perioperative plan for it
//
// The ASA Committee on Ethics, "Statement on Ethical Guidelines for the Anesthesia Care of Patients with
// Do-Not-Resuscitate Orders" (original approval October 17, 2001; reaffirmed October 18, 2023):
// https://www.asahq.org/standards-and-practice-parameters/statement-on-ethical-guidelines-for-the-anesthesia-care-of-patients-with-do-not-resuscitate-orders
// Policies that automatically suspend DNR orders before anesthesia may not respect self-determination; existing
// directives should be reviewed with the patient or surrogate before the anesthetic and clarified or modified, with
// three options: a full attempt at resuscitation (the directive suspended during the anesthetic and the immediate
// postoperative period), a limited attempt defined by specific procedures, or a limited attempt defined by the
// patient's goals and values. Changes are documented, with when the original directive resumes. The American College
// of Surgeons, "Statement on Advance Directives by Patients: 'Do Not Resuscitate' in the Operating Room" (January 3,
// 2014), names this "required reconsideration":
// https://www.facs.org/about-acs/statements/advance-directives-by-patients-do-not-resuscitate-in-the-operating-room/

enum CodeStatus: String, Codable, CaseIterable, Hashable {
    case full, dnr, dni, dnrDni, limited, notDiscussed

    var label: String {
        switch self {
        case .full: return "Full code"
        case .dnr: return "DNR"
        case .dni: return "DNI"
        case .dnrDni: return "DNR/DNI"
        case .limited: return "Limited"
        case .notDiscussed: return "Not discussed"
        }
    }

    /// Limits resuscitation, so the perioperative plan is asked.
    var limits: Bool { resuscitationOrder || self == .limited }

    /// DNR, DNI or both.
    var resuscitationOrder: Bool {
        switch self {
        case .dnr, .dni, .dnrDni: return true
        default: return false
        }
    }
}

/// What happens to the orders during the anesthetic, after the required reconsideration.
enum CodeStatusPlan: String, Codable, CaseIterable, Hashable {
    case maintained, modified, suspended

    var label: String {
        switch self {
        case .maintained: return "Maintained as is"
        case .modified: return "Modified for the procedure"
        case .suspended: return "Suspended for the procedure"
        }
    }

    /// The ASA option each one is.
    var detail: String {
        switch self {
        case .maintained: return "The orders stand as written during the anesthetic: the procedures the patient refuses are not used."
        case .modified: return "A limited attempt at resuscitation, defined by specific procedures or by the patient's goals and values (ASA options 2 and 3). Write down what is and is not acceptable."
        case .suspended: return "A full attempt at resuscitation during the anesthetic and the immediate postoperative period (ASA option 1). Write down when the original orders resume."
        }
    }
}

/// What a note says about code status (PatientNote).
struct CodeStatusReading: Hashable {
    var status: CodeStatus?
    var polst: Bool
    var plan: CodeStatusPlan?
    /// Every stretch read, the first being the main mention.
    var ranges: [NSRange]
}

enum PatientCodeStatus {
    static let url = "https://www.asahq.org/standards-and-practice-parameters/statement-on-ethical-guidelines-for-the-anesthesia-care-of-patients-with-do-not-resuscitate-orders"

    static let note = "Automatically suspending DNR orders before anesthesia may not respect the patient's right to self-determination. Before the anesthetic, review the orders with the patient or surrogate, agree on one of three approaches (full attempt at resuscitation, or a limited attempt defined by specific procedures or by the patient's goals and values), document it, and note when the original orders resume. ASA Committee on Ethics, Statement on Ethical Guidelines for the Anesthesia Care of Patients with Do-Not-Resuscitate Orders (reaffirmed October 18, 2023); the American College of Surgeons calls this “required reconsideration” (2014)."

    /// "DNR/DNI (POLST on file); modified for the procedure: accepts intubation", "Full code", "POLST on file".
    static func text(_ r: PatientRecord) -> String? {
        guard let s = r.codeStatus else { return r.polst ? "POLST on file" : nil }
        var t = s.label
        let limits = r.codeStatusLimits.trimmingCharacters(in: .whitespacesAndNewlines)
        if s == .limited && !limits.isEmpty { t += ": " + limits }
        if r.polst { t += " (POLST on file)" }
        if s.limits {
            let note = r.codeStatusPlanNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if let p = r.codeStatusPlan {
                t += "; " + p.label.lowercased() + (note.isEmpty ? "" : ": " + note)
            } else {
                t += "; perioperative plan not yet discussed"
            }
        }
        return t
    }

    /// The Assessment card's line; red when the orders limit resuscitation.
    static func line(_ r: PatientRecord) -> PatientSummary.Line? {
        guard let t = text(r) else { return nil }
        let limits = r.codeStatus?.limits ?? false
        return PatientSummary.Line("Code status", t, alert: limits, marks: limits && r.codeStatusPlan == nil ? ["perioperative plan not yet discussed"] : [])
    }

    // MARK: Fill from a note

    static let dnrDniRx = NoteRx(#"\b(?:dnr|dnar)\s*(?:/|\\|-|\+|&|and|,)\s*dni\b|\bdni\s*(?:/|\\|-|\+|&|and|,)\s*(?:dnr|dnar)\b|\bdo[- ]not[- ](?:attempt[- ])?resuscitate\s*(?:/|,|and|or|&)?\s*(?:or\s+)?(?:do[- ]not[- ])?intubate\b"#)
    static let dnrRx = NoteRx(#"\b(?:dnr|dnar)\b|\bdo[- ]not[- ](?:attempt[- ])?resuscitat\w*"#)
    static let dniRx = NoteRx(#"\bdni\b|\bdo[- ]not[- ]intubat\w*"#)
    static let fullRx = NoteRx(#"\bfull[- ]code\b|\bcode status\s*(?:is|:|-|=)?\s*full\b"#)
    static let polstRx = NoteRx(#"\b(?:polst|molst)\b(?:\s+(?:form\s+)?(?:on file|in (?:the )?chart|present|completed|reviewed|signed))?|\b(?:physician|medical) orders for life[- ]sustaining treatment\b"#)
    static let labelRx = NoteRx(#"\bcode status\s*(?:is|:|-|=)?"#)
    static let periopRx = NoteRx(#"\b(?:for|during|in|through)\s+(?:the\s+)?(?:procedure|surgery|operation|case|or|operating room|an(?:a)?esthe\w*|perioperative period)\b|\bperi-?op(?:erative(?:ly)?)?\b|\bintra-?op(?:erative(?:ly)?)?\b"#)
    static let suspendedRx = NoteRx(#"\b(?:suspend\w*|rescind\w*|revok\w*|revers\w*|lifted|on hold|waived)\b"#)
    static let maintainedRx = NoteRx(#"\b(?:maintain\w*|honou?r\w*|remains?|continu\w*|upheld|kept|stays?|in (?:place|effect))\b"#)
    static let modifiedRx = NoteRx(#"\b(?:modif\w*|amend\w*|ok(?:ay)? to (?:intubate|use|give)|will accept|accepts?)\b"#)
    /// "do not resuscitate" and "do not intubate" hold a "not" that is not a negation.
    private static let phraseNot = NoteRx(#"\bdo[- ](not)[- ](?=(?:attempt[- ])?resuscitat|intubat)"#)

    static var patterns: [NoteRx] { [dnrDniRx, dnrRx, dniRx, fullRx, polstRx, labelRx, periopRx, suspendedRx, maintainedRx, modifiedRx, phraseNot] }

    /// The code status, POLST and perioperative plan one clause of a note gives; nil when it says none of them.
    static func read(_ c: String) -> CodeStatusReading? {
        // A copy with the phrases' "not" made harmless, the same length, for the negation check.
        let neutral = NSMutableString(string: c)
        for m in phraseNot.all(c).reversed() { neutral.replaceCharacters(in: m.range(at: 1), with: "nxt") }
        let plain = neutral as String
        func found(_ rx: NoteRx) -> NSTextCheckingResult? { rx.all(c).first { !PatientNote.negated(plain, at: $0.range.location) } }
        var ranges: [NSRange] = []
        var status: CodeStatus?
        if let m = found(dnrDniRx) {
            status = .dnrDni; ranges.append(m.range)
        } else {
            let dnr = found(dnrRx), dni = found(dniRx)
            if let a = dnr, let b = dni { status = .dnrDni; ranges += [a.range, b.range] }
            else if let a = dnr { status = .dnr; ranges.append(a.range) }
            else if let b = dni { status = .dni; ranges.append(b.range) }
        }
        let full = found(fullRx)
        let periop = periopRx.first(c)
        var plan: CodeStatusPlan?
        if let f = full {
            ranges.append(f.range)
            // "DNR; full code for surgery": the orders are suspended for the procedure.
            if status != nil || periop != nil { plan = .suspended } else { status = .full }
            if status == nil { status = .full }
        }
        let polst = polstRx.first(c)
        if let p = polst { ranges.append(p.range) }
        guard status != nil || polst != nil else { return nil }
        if plan == nil, periop != nil {
            if let m = suspendedRx.first(c) { plan = .suspended; ranges.append(m.range) }
            else if let m = modifiedRx.first(c) { plan = .modified; ranges.append(m.range) }
            else if let m = maintainedRx.first(c) { plan = .maintained; ranges.append(m.range) }
        }
        if plan != nil, let p = periop { ranges.append(p.range) }
        if let l = labelRx.first(c) { ranges.append(l.range) }
        return CodeStatusReading(status: status, polst: polst != nil, plan: plan, ranges: ranges)
    }

    /// The review item for what was read.
    static func finding(_ status: CodeStatus?, polst: Bool, plan: CodeStatusPlan?) -> PatientNoteFinding {
        var parts: [String] = []
        if let s = status { parts.append(s.label) }
        if polst { parts.append("POLST on file") }
        if let p = plan, status?.limits ?? true { parts.append(p.label.lowercased()) }
        return PatientNoteFinding(id: "codeStatus", section: PatientNote.Part.assessment, label: "Code status: " + parts.joined(separator: " · "),
                                  change: .codeStatus(status, polst: polst, plan: plan))
    }

    /// Two mentions in different sentences, put together ("DNR/DNI." then "POLST on file; DNR suspended for the OR.").
    static func merged(_ a: PatientNoteChange, _ b: PatientNoteChange) -> PatientNoteFinding? {
        guard case .codeStatus(let s, let p, let q) = a, case .codeStatus(let t, let p2, let q2) = b else { return nil }
        var status = s ?? t
        var plan = q ?? q2
        // A limiting order and "full code for the procedure": the order, suspended.
        if let x = s, let y = t, x != y {
            if x.limits && y == .full { status = x; plan = plan ?? .suspended }
            else if y.limits && x == .full { status = y; plan = plan ?? .suspended }
            // "DNR/DNI." then "DNR suspended for the OR": the fuller order stands.
            else if x.resuscitationOrder && y.resuscitationOrder { status = .dnrDni }
            else { return nil }
        }
        return finding(status, polst: p || p2, plan: plan)
    }

    /// How the finding compares with the record.
    static func status(_ s: CodeStatus?, polst: Bool, plan: CodeStatusPlan?, in r: PatientRecord) -> PatientNoteStatus {
        guard let s else { return r.polst ? .recorded : .new }
        let p = s.limits ? plan : nil
        if let o = r.codeStatus, o != s { return .replaces(o == .notDiscussed ? "not discussed" : o.label) }
        if r.codeStatus == s, let p, let op = r.codeStatusPlan, op != p { return .replaces(op.label.lowercased()) }
        guard r.codeStatus == s else { return .new }
        if polst && !r.polst { return .new }
        if let p, r.codeStatusPlan != p { return .new }
        return .recorded
    }

    static func apply(_ s: CodeStatus?, polst: Bool, plan: CodeStatusPlan?, to r: inout PatientRecord) {
        if let s { r.codeStatus = s }
        if polst { r.polst = true }
        if let p = plan, r.codeStatus?.limits ?? false { r.codeStatusPlan = p }
    }
}
