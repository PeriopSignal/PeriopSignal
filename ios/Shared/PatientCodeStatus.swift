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

    // MARK: 1.10 chips (Ben, Nov 7): DNR and DNI are two chips that can both be on; Full code, Limited and Not discussed
    // stay exclusive. A record keeps one status, so both on is `.dnrDni`; a saved "DNR/DNI" lights both chips, and
    // its text ("DNR/DNI") reads as both orders in the summary, the handoff and the plan link.

    /// DNR is in force (alone or with DNI).
    var hasDNR: Bool { self == .dnr || self == .dnrDni }
    /// DNI is in force (alone or with DNR).
    var hasDNI: Bool { self == .dni || self == .dnrDni }

    /// The status for the two orders switched on or off: both is `.dnrDni`; neither is nil.
    static func orders(dnr: Bool, dni: Bool) -> CodeStatus? {
        switch (dnr, dni) {
        case (true, true): return .dnrDni
        case (true, false): return .dnr
        case (false, true): return .dni
        case (false, false): return nil
        }
    }

    /// One chip of the code-status row.
    struct Chip: Hashable, Identifiable {
        var id: String
        var label: String
        /// Shorter words for a narrow row (nil: the label stays). VoiceOver always reads the label.
        var short: String?
    }

    /// The chips, in order: there is no DNR/DNI chip any more (both on is DNR and DNI together).
    static let chips: [Chip] = [
        Chip(id: "full", label: "Full code", short: "Full"),
        Chip(id: "dnr", label: "DNR", short: nil),
        Chip(id: "dni", label: "DNI", short: nil),
        Chip(id: "limited", label: "Limited", short: nil),
        Chip(id: "notDiscussed", label: "Not discussed", short: nil),
    ]

    /// The chips a status lights: `.dnrDni` lights DNR and DNI together.
    var chipIDs: Set<String> {
        switch self {
        case .dnrDni: return ["dnr", "dni"]
        case .notDiscussed: return ["notDiscussed"]
        default: return [rawValue]
        }
    }

    /// The status after a tap on a chip. DNR and DNI toggle each other's partner on and off (DNR then DNI is both; a tap on
    /// one that is on takes it off, leaving the other); a tap on Full code, Limited or Not discussed chooses it, replacing
    /// any order, and a second tap on the one chosen clears it. A tap on DNR or DNI while one of those three is chosen
    /// replaces it.
    static func tapped(_ chip: String, from current: CodeStatus?) -> CodeStatus? {
        let dnr = current?.hasDNR ?? false, dni = current?.hasDNI ?? false
        switch chip {
        case "dnr": return orders(dnr: !dnr, dni: dni)
        case "dni": return orders(dnr: dnr, dni: !dni)
        default:
            guard let status = CodeStatus(rawValue: chip) else { return current }
            return current == status ? nil : status
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
        case .maintained: return "The orders stand as written during the anesthetic: the procedures the patient refuses are not used. Tell the patient which procedures are essential to the anesthetic and the operation (for example intubation for a general anesthetic in someone who is DNI); if any is refused, the plan is a modified one."
        case .modified: return "A limited attempt at resuscitation, defined by specific procedures or by the patient's goals and values (ASA options 2 and 3). Write down what is and is not acceptable."
        case .suspended: return "A full attempt at resuscitation during the anesthetic and the immediate postoperative period (ASA option 1). Write down when the original orders resume."
        }
    }

    /// The end of `detail` that stays in view under the chips when this plan is chosen: Maintained's instruction to the
    /// clinician (review 1.8.1 row 32). Nil when the whole definition sits behind the ⓘ.
    var inView: String? {
        switch self {
        case .maintained: return "Tell the patient which procedures are essential to the anesthetic and the operation (for example intubation for a general anesthetic in someone who is DNI); if any is refused, the plan is a modified one."
        case .modified, .suspended: return nil
        }
    }

    /// The rest of `detail`, behind the ⓘ on "For the procedure".
    var info: String {
        guard let v = inView, detail.hasSuffix(v) else { return detail }
        return String(detail.dropLast(v.count)).trimmingCharacters(in: .whitespaces)
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

    /// When a suspended or modified order resumes has not been written down (the ASA asks the plan to say if or when
    /// the original orders are reinstated).
    static let resumeMissing = "when the orders resume: not recorded"
    /// A POLST with no status chosen: it may order CPR or not, so the line says to check it.
    static let polstOnly = "not recorded · POLST on file (check its orders)"

    /// "DNR/DNI (POLST on file); modified for the procedure: accepts intubation", "Full code", "POLST on file".
    static func text(_ r: PatientRecord) -> String? {
        guard let s = r.codeStatus else { return r.polst ? polstOnly : nil }
        var t = s.label
        let limits = r.codeStatusLimits.trimmingCharacters(in: .whitespacesAndNewlines)
        if s == .limited && !limits.isEmpty { t += ": " + limits }
        if r.polst { t += " (POLST on file)" }
        if s.limits {
            let note = r.codeStatusPlanNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if let p = r.codeStatusPlan {
                t += "; " + p.label.lowercased() + (note.isEmpty ? "" : ": " + note)
                if note.isEmpty && p != .maintained { t += "; " + resumeMissing }
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
        var marks: [String] = []
        if limits && r.codeStatusPlan == nil { marks.append("perioperative plan not yet discussed") }
        if t.contains(resumeMissing) { marks.append(resumeMissing) }
        if r.codeStatus == nil && r.polst { marks.append(polstOnly) }
        return PatientSummary.Line("Code status", t, alert: limits || r.codeStatus == nil, marks: marks)
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
    static let modifiedRx = NoteRx(#"\b(?:modif\w*|amend\w*|ok(?:ay)? to (?:intubate|use|give)|will accept|accepts?|except|other than|acceptable|allowed|permitted)\b"#)
    /// "do not resuscitate" and "do not intubate" hold a "not" that is not a negation.
    private static let phraseNot = NoteRx(#"\bdo[- ](not)[- ](?=(?:attempt[- ])?resuscitat|intubat)"#)
    /// Before an order: the patient declines it, or had it before ("declines DNR", "was DNR last admission").
    static let voidBefore = NoteRx(#"\b(?:declin\w*|refus\w*|does not want|doesn't want|did not want|opts? out of|no longer|rescind\w*|revok\w*|cancel\w*|discontinu\w*|was|previously|formerly|prior|previous)\b[^.;,]{0,25}$"#)
    /// After an order, in the same sentence: it was declined or undone ("DNR discussed and declined", "DNR order
    /// rescinded"). With the procedure named, these words mean the plan for the procedure instead.
    static let voidAfter = NoteRx(#"^[^.;]{0,40}?\b(?:declin\w*|refus\w*|rescind\w*|revok\w*|revers\w*|cancel\w*|discontinu\w*|removed|withdrawn|no longer)\b"#)
    /// Someone else's order ("wife is DNR").
    static let otherPerson = NoteRx(#"\b(?:wife|husband|spouse|partner|son|daughter|mother|father|brother|sister|parents?|family member|roommate)\b[^.;,]{0,25}$"#)
    /// A plan word with a negation just before it ("will not be suspended", "won't be modified").
    static let planNot = NoteRx(#"\b(?:not|never|no longer|n't|wont)\b[^.;]{0,12}$|n't\s+(?:be\s+)?$"#)
    /// After a POLST mention: there is none ("POLST not completed", "POLST: none").
    static let polstNone = NoteRx(#"^[^.;]{0,15}\b(?:not|none|unavailable|missing|pending|absent)\b"#)

    static var patterns: [NoteRx] { [dnrDniRx, dnrRx, dniRx, fullRx, polstRx, labelRx, periopRx, suspendedRx, maintainedRx, modifiedRx, phraseNot] }

    /// The code status, POLST and perioperative plan one clause of a note gives; nil when it says none of them.
    static func read(_ c: String) -> CodeStatusReading? {
        // A copy with the phrases' "not" made harmless, the same length, for the negation check.
        let neutral = NSMutableString(string: c)
        for m in phraseNot.all(c).reversed() { neutral.replaceCharacters(in: m.range(at: 1), with: "nxt") }
        let plain = neutral as String
        let ns = plain as NSString
        let periop = periopRx.first(c)
        func before(_ m: NSTextCheckingResult) -> String { ns.substring(to: m.range.location) }
        func after(_ m: NSTextCheckingResult) -> String { ns.substring(from: m.range.location + m.range.length) }
        func found(_ rx: NoteRx) -> NSTextCheckingResult? { rx.all(c).first { !PatientNote.negated(plain, at: $0.range.location) } }
        /// An order that is the patient's and in force: not negated, declined, undone, past or someone else's.
        func order(_ rx: NoteRx) -> NSTextCheckingResult? {
            rx.all(c).first { m in
                if PatientNote.negated(plain, at: m.range.location) { return false }
                let b = before(m)
                if voidBefore.first(b) != nil || otherPerson.first(b) != nil { return false }
                if periop == nil, voidAfter.first(after(m)) != nil { return false }
                return true
            }
        }
        var ranges: [NSRange] = []
        var status: CodeStatus?
        if let m = order(dnrDniRx) {
            status = .dnrDni; ranges.append(m.range)
        } else {
            let dnr = order(dnrRx), dni = order(dniRx)
            if let a = dnr, let b = dni { status = .dnrDni; ranges += [a.range, b.range] }
            else if let a = dnr { status = .dnr; ranges.append(a.range) }
            else if let b = dni { status = .dni; ranges.append(b.range) }
        }
        let full = found(fullRx)
        var plan: CodeStatusPlan?
        if let f = full {
            ranges.append(f.range)
            if status == nil {
                status = .full
                // "Full code for the OR": full resuscitation for the procedure (an order elsewhere is suspended).
                if periop != nil { plan = .suspended }
            } else if periop != nil {
                // "DNR; full code for surgery": the orders are suspended for the procedure.
                plan = .suspended
            } else if let lim = ranges.first, f.range.location > lim.location {
                // "DNR discussed, wishes to remain full code": the later statement stands ("Previously full code,
                // now DNR" keeps the order).
                status = .full
            }
        }
        var polst = found(polstRx)
        if let p = polst, polstNone.first(after(p)) != nil { polst = nil }
        if let p = polst { ranges.append(p.range) }
        guard status != nil || polst != nil else { return nil }
        if plan == nil, periop != nil {
            /// A plan word, and whether a negation sits just before it.
            func planWord(_ rx: NoteRx) -> (match: NSTextCheckingResult, negated: Bool)? {
                guard let m = rx.first(c) else { return nil }
                return (m, planNot.first(before(m)) != nil)
            }
            if let w = planWord(suspendedRx) {
                // "DNR will not be suspended during surgery": the orders stand.
                plan = w.negated ? .maintained : .suspended; ranges.append(w.match.range)
            } else if let w = planWord(modifiedRx) {
                plan = w.negated ? .maintained : .modified; ranges.append(w.match.range)
            } else if let w = planWord(maintainedRx), !w.negated {
                plan = .maintained; ranges.append(w.match.range)
            }
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
        if let x = s, let y = t, x != y {
            // A limiting order and "full code for the procedure" (read with the procedure named): the order, suspended.
            if x.limits && y == .full && q2 == .suspended { status = x; plan = .suspended }
            else if y.limits && x == .full && q == .suspended { status = y; plan = .suspended }
            // "DNR/DNI." then "DNR suspended for the OR": the fuller order stands.
            else if x.resuscitationOrder && y.resuscitationOrder { status = .dnrDni }
            // Otherwise the later sentence stands ("Was DNR. Now full code."); its own plan only.
            else { return finding(y, polst: p || p2, plan: y.limits ? q2 : nil) }
        }
        if status == .full { plan = nil }
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
