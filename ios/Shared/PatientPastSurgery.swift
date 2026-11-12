import Foundation

// MARK: - Past surgical history from a typed note (1.8.3, Ben)
//
// "In typed history, past surgical history should also be populated if entered." A note (or the quick-add bar) that
// gives a surgical history fills Past surgical history, one entry per operation, with its date when the note gives one:
//
//   - a section: "PSH: ...", "PSHx", "Past surgical history: ...", "Surgical history: ..." (items split at commas and
//     semicolons, and at "and" after a date; a header with nothing after it takes the bulleted lines that follow);
//   - "s/p ...", "status post ...", "h/o ...", "hx of ...", "history of ...", "prior ...", "previous ..." before an
//     operation (and the operations listed after it: "s/p CABG 2019, appendectomy 2010").
//
// "A + B + C 06/2025" is one operation with three procedures. Each procedure is matched to the procedure list when it
// can be; otherwise it stays as typed. An anesthetic remark ("under GA") is left for the anesthesia-history details.
// The planned procedure ("Procedure: ...", "scheduled for ...", "presents for ...") is never past surgery.
enum PastSurgeryNote {
    struct Operation: Hashable {
        /// The operation as written, without its date and any anesthetic remark ("CABG ×3").
        var text: String
        var date: PatientMonthYear
        /// An anesthetic remark that went with it ("under GA"), kept for the anesthesia-history details.
        var aside: String
        /// Where the item was read in the sentence.
        var range: NSRange
    }

    /// Carried from one sentence to the next: a "PSH:" header with bulleted lines after it.
    struct State {
        var open = false
        /// The header had nothing after it, so the lines that follow are its items.
        var bodyEmpty = false
    }

    struct Reading {
        var operations: [Operation] = []
    }

    // MARK: Patterns

    static let headerRx = NoteRx(#"\b(?:(?:psh|pshx)\b\s*[:\-–]?|(?:past surgical (?:history|hx)|surgical (?:history|hx)|prior surgeries|previous surgeries|past surgeries)\s*[:\-–])\s*"#)
    static let leadRx = NoteRx(#"\b(?:s/p|status post|h/o|hx(?: of)?:?|history of|prior|previous)\s+(?!to\b|admissions?\b|hospitali[sz]ations?\b|visits?\b|episodes?\b)(?:an?\s+|the\s+)?"#)
    static let familyHxRx = NoteRx(#"\b(?:family|fam|maternal|paternal)\s*$"#)
    static let bulletRx = NoteRx(#"^\s*(?:[-•*–·]|\d+[.)])\s*"#)
    /// Another section's header inside a section's text ends it: "PSH: appendectomy 2010, PMH: HTN, AAA". What follows a
    /// PMH header is diagnoses, which are never past surgery (only an "s/p", an operative word or an operation abbreviation
    /// such as CABG makes one an operation, and that is read on its own). "FHx" is never a lead.
    static let sectionEndRx = NoteRx(#"\b(?:pmh|pmhx|past medical (?:history|hx)|medical history|fhx|shx|family history|social history|hpi|meds|medications|allergies|ros|exam|plan|a/p|assessment|labs|vitals)\b\s*[:\-–]"#)
    /// Another section's header at the start of a line closes the surgical history.
    static let otherHeaderRx = NoteRx(#"^\s*[A-Za-z][A-Za-z/&\s]{1,28}:"#)
    static let andAfterDateRx = NoteRx(#"((?:19|20)\d\d|\d{1,2}/(?:19|20)\d\d|\d{1,2}[/.\-]\d{1,2}[/.\-]\d\d|['’]\d\d)\)?\s+(?:and|&)\s+"#)
    /// What ends an item that runs on into the rest of the sentence ("s/p CABG 2019, now doing well").
    static let cutRx = NoteRx(#"\s+(?:now|here|who|but|which|that|due to|secondary to|c/b|complicated)\b"#)
    /// The planned procedure (1.8.3 review): an item next to one of these words is dropped, not trimmed to its head, and
    /// nothing after it is read. A bare "for" counts after "s/p", "h/o" and the like ("s/p repair for hernia" is not filed
    /// either); a "PSH:" section may say what an operation was for.
    static let planningRx = NoteRx(#"\b(?:scheduled|planned|booked|pending|awaiting|needs?|candidate|referred|(?:presents?|presenting|presented|here|admitted|now|plans?|planning) (?:for|to)|presents?|presenting|presented|undergoing|will (?:undergo|have)|to have)\b"#)
    static let forRx = NoteRx(#"\bfor\b"#)
    static let asideRx = NoteRx(#"\s+(?:under|with|w/|using|via|had|received)\s+(?:general|ga\b|spinal|epidural|mac\b|local|regional|sedation|an(?:a)?esthesia|nerve block)[^,;]*$"#)
    static let commentaryRx = NoteRx(#"^(?:no|none|nil|denies|denied|negative|neg|n/a|na|noncontributory|non-contributory|unremarkable|noted|see|per|otherwise|unknown|unsure|not|ga|mac)\b|\b(?:complications?|an(?:a)?esthe\w*|difficult (?:airway|intubation)|ponv|malignant hyperthermia|uneventful|tolerated|problems?|issues?|reactions?)\b"#)
    /// An operative word: the text says an operation was done ("repair", "-ectomy", "bypass", "replacement", "ORIF", "surgery"),
    /// or is an abbreviation that only names one (CABG, AVR, TAVR, EVAR).
    static let surgicalRx = NoteRx(#"(?:ectomy|otomy|ostomy|plasty|oscopy|pexy|orrhaphy|desis)\b|\b(?:repair|surgery|operation|resection|replacement|bypass|fusion|transplant\w*|fixation|orif|graft(?:ing)?|implant\w*|excision|c-?section|cesarean|ligation|amputation|biopsy|decompression|reconstruction|ablation|closure|tka|tha|tkr|thr)\b|(?-i:\b(?:CABG|OPCAB|SAVR|AVR|MVR|TVR|AVr|MVr|TVr|TAVR|TAVI|TEER|TMVR|TTVR|TPVR|LAAO|LAAC|VSRR|EVAR|TEVAR|FEVAR|BEVAR|PCI|TURP)\b)"#)
    /// A diagnosis, which a procedure-list alias can also be ("AAA" is the open repair's, "dissection" a cardiac repair's):
    /// with no operative word it is not an operation, after "h/o" or in a "PSH:" section.
    static let diagnosisRx = NoteRx(#"\b(?:aaa|taaa?|taad|aod|aneurysms?|dissections?|hernias?|ectopic|fractures?|appendicitis|cholecystitis|cholelithiasis|gallstones?|obstruction|sbo|cancer|carcinoma|tumou?rs?|mass|stones?|stenosis|regurgitation|insufficiency|pregnancy|pneumothorax|empyema|abscess|torsion|bleed(?:ing)?|perforation|ulcers?|polyps?|cysts?)\b"#)
    /// Operations named by an eponym, a shorthand or an abbreviation, with no operative word ("Whipple", "Nissen", "lap
    /// chole", "appy", "ACDF"). After a history lead ("h/o", "Hx", "prior"), a procedure-list match counts only with an
    /// operative word or one of these: the list's aliases include diagnoses ("scoliosis", "coarctation", "varicose veins")
    /// that a history lead usually introduces (1.8.3 re-check).
    static let shorthandRx = NoteRx(#"\b(?:procedure|whipple|nissen|toupet|heller|bentall|fontan|glenn|norwood|kasai|ladd|hartmann'?s?|ivor lewis|mckeown|sistrunk|puestow|latarjet|bankart|brostrom|ravitch|nuss|maze|cox-maze|watchman|mitraclip|roux-en-y|billroth|mohs|lichtenstein|lap chole|appy|lap appy|lap band|gastric band|gastric sleeve|t&a|d&c|leep|triclip|amulet|lariat|david procedure)\b|(?-i:\b(?:TSA|ACDF|PLIF|TLIF|ALIF|XLIF|VATS|RATS|LAR|APR|IPAA|TAH|TLH|LAVH|BSO|TURBT|PCNL|FESS|UPPP|LVAD|OHT|OLT|CEA|TCAR|LAAO|TEP|TAPP)\b)"#)
    static let chestRx = NoteRx(#"\b(?:thoracotomy|sternotomy|vats|thoracoscopic|lobectomy|pneumonectomy|segmentectomy|esophagectomy|open[- ]heart|cardiac surgery|heart surgery)\b"#)
    static let monthYearRx = NoteRx(#"(?:\bin\s+|\(\s*|\b(?:on|dated|at)\s+)?\b((?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?,?\s+(?:\d{1,2},?\s+)?(?:19|20)\d\d)\b\s*\)?"#)
    /// A full date (1.12): month/day/year, "6/14/2015" or "6/14/15" (a day is certain only with three numbers). A month name
    /// takes its day in monthYearRx ("June 14, 2015"). The year is four digits, or two as the field reads them.
    static let fullDateRx = NoteRx(#"(?:\bin\s+|\(\s*|\b(?:on|dated|at)\s+)?(?<![\w/.\-])((?:0?[1-9]|1[0-2])\s*[/.\-]\s*(?:0?[1-9]|[12]\d|3[01])\s*[/.\-]\s*(?:(?:19|20)\d\d|\d\d))(?![\d/])\s*\)?"#)
    /// Dates in a note: MM/YYYY, a year, a month name and year, and "'19" (with or without a month before it), and (1.12) a
    /// full date (fullDateRx). Never M/D ("appy 6/30"), nor MM/YY with no apostrophe, nor a 19xx year from two digits.
    static let numericRx = NoteRx(#"(?:\bin\s+|\(\s*)?(?<![\w/.\-])((?:0?[1-9]|1[0-2])\s*[/.\-]\s*(?:19|20)\d\d)(?![\d/])\s*\)?"#)
    static let apostropheRx = NoteRx(#"(?:\bin\s+|\(\s*)?(?<![\w/.\-])(?:(0?[1-9]|1[0-2])\s*/\s*)?['’](\d\d)(?!\d)\s*\)?"#)
    static let yearRx = NoteRx(#"(?:\bin\s+|\(\s*)?(?<![\w/.\-])((?:19|20)\d\d)(?![\w/])\s*\)?"#)

    /// What a full date next to these is the date of (1.12): a date of birth, a lab draw or its value, a vital sign, a visit.
    /// An item with a full date and one of these is not an operation ("DOB 3/14/1958", "K 5.4 on 11/10/2026"). The existing
    /// guards stay; this only adds to them for a date with a day.
    static let notSurgeryDateRx = NoteRx(#"\b(?:dob|d\.o\.b\.?|born|birth(?:day|date)?|drawn|draw|collected|vitals?|labs?|today|as of)\b|\b(?:k|na|cr|creat\w*|hgb|hb|hct|plt|inr|ptt|bun|glucose|lactate|wbc|trop\w*|bnp|bp|hr|rr|spo2|sat|temp)\b\s*[:=]?\s*\d"#)

    /// An anesthetic remark that stands alone ("under GA", "with spinal"): the anesthesia history's, never an operation.
    static let asideStartRx = NoteRx(#"^(?:under|with|w/|using|via|had|received)\s+(?:general|ga\b|spinal|epidural|mac\b|local|regional|sedation|an(?:a)?esthesia|nerve block)"#)
    /// A planned procedure told as "for ..." at the start of an item.
    static let forStartRx = NoteRx(#"^\s*for\b"#)

    static let cardiacWordsRx = NoteRx(PatientNote.cardiacOpWords)

    /// Words that name no operation.
    private static let generic: Set<String> = ["surgery", "surgeries", "operation", "operations", "procedure", "procedures", "surgical", "history"]

    static var allPatterns: [NoteRx] {
        [cardiacWordsRx, asideStartRx, forStartRx, headerRx, sectionEndRx, familyHxRx, leadRx, bulletRx, otherHeaderRx, andAfterDateRx, cutRx, planningRx, forRx, asideRx, commentaryRx, surgicalRx, diagnosisRx, shorthandRx, chestRx, monthYearRx, fullDateRx, numericRx, apostropheRx, yearRx, notSurgeryDateRx]
    }

    // MARK: Reading a sentence

    /// The operations a sentence gives. `state` carries a header across lines; `skip` holds the stretches already read as
    /// something else (Previous cardiac surgery), which are not read again.
    ///
    /// `lenient` (1.12 follow-up, Ben: the Past Surgical History bar "adds the first procedure but not the ones after it"): on that
    /// bar everything typed is an operation, so a line is read as a list of operations by what it is NOT: any item of at least three
    /// letters that is not a date alone, a negation ("none", "no surgeries"), an anesthetic remark, a diagnosis, a planned
    /// procedure or plainly something else the note reader reads (a lab, a drug, a history item) becomes an entry, from the
    /// procedure list when it matches and as typed when it does not. The Preoperative tab's bar and the note reader keep the
    /// stricter rule: a diagnosis after "h/o" is not an operation.
    static func read(_ c: String, state: inout State, skip: [NSRange] = [], now: Date = Date(), lenient: Bool = false) -> Reading {
        let ns = c as NSString
        var out = Reading()
        func clear(_ r: NSRange) -> Bool { !skip.contains { NSIntersectionRange($0, r).length > 0 } }

        // Lines after a header.
        if state.open {
            if let b = bulletRx.first(c) {
                let start = b.range.location + b.range.length
                let ops = items(ns, NSRange(location: start, length: ns.length - start), strict: false, lenient: lenient, now: now)
                out.operations = ops.filter { clear($0.range) }
                state.open = true
                return out
            }
            let numberOnly = c.trimmingCharacters(in: .whitespaces).allSatisfy { $0.isNumber || $0 == "." || $0 == ")" }
            if numberOnly { return out }
            // The bar's line has no other sections: "Appendectomy: 2010" is an operation, not another section's header (a known
            // section's header, "PMH:" or "Meds:", still is).
            let otherHeader = otherHeaderRx.first(c) != nil && !(lenient && sectionEndRx.first(c) == nil)
            if state.bodyEmpty, !otherHeader, headerRx.first(c) == nil {
                let ops = items(ns, NSRange(location: 0, length: ns.length), strict: !lenient, lenient: lenient, now: now)
                if !ops.isEmpty {
                    out.operations = ops.filter { clear($0.range) }
                    return out
                }
            }
            state.open = false
        }

        var sectionStart = ns.length
        var sectionEnd = ns.length
        if let h = headerRx.first(c) {
            sectionStart = h.range.location
            let start = h.range.location + h.range.length
            var body = NSRange(location: start, length: ns.length - start)
            if let end = sectionEndRx.first(ns.substring(with: body)) { body.length = end.range.location }
            let text = ns.substring(with: body).trimmingCharacters(in: .whitespacesAndNewlines)
            state.open = true
            state.bodyEmpty = text.isEmpty
            sectionEnd = body.location + body.length
            out.operations += items(ns, body, strict: false, now: now).filter { clear($0.range) }
        }

        // "s/p ...", "h/o ...": the operation after it, and the operations listed after that.
        var covered = NSRange(location: 0, length: 0)
        for m in leadRx.all(c) where (m.range.location < sectionStart || m.range.location >= sectionEnd) && m.range.location >= covered.location + covered.length {
            if PatientNote.negated(c, at: m.range.location) || PatientNote.familyContext(c, at: m.range.location) { continue }
            // "Family hx: ..." (not "FHx", which \b already refuses) is the family's.
            if familyHxRx.first(ns.substring(to: m.range.location)) != nil { continue }
            let start = m.range.location + m.range.length
            let end = m.range.location < sectionStart ? sectionStart : ns.length
            guard start < end else { continue }
            let found = leadItems(ns, NSRange(location: start, length: end - start), historyLead: isHistoryLead(ns.substring(with: m.range)), now: now)
            if found.isEmpty { continue }
            out.operations += found.filter { clear($0.range) }
            if let last = found.last { covered = NSRange(location: m.range.location, length: last.range.location + last.range.length - m.range.location) }
        }
        return out
    }

    /// The operation right after a lead, then the items after it while each one is an operation too.
    /// "h/o", "Hx", "history of", "prior", "previous": what follows is often a diagnosis. "s/p" and "status post" name an
    /// operation.
    static func isHistoryLead(_ lead: String) -> Bool {
        let l = lead.lowercased().trimmingCharacters(in: .whitespaces)
        return !(l.hasPrefix("s/p") || l.hasPrefix("status post"))
    }

    private static func leadItems(_ ns: NSString, _ range: NSRange, historyLead: Bool = false, now: Date) -> [Operation] {
        var out: [Operation] = []
        for (i, p) in split(ns, range).enumerated() {
            var stopped = false
            let op = operation(ns, p, strict: true, historyLead: historyLead, now: now, stopped: &stopped)
            if let op {
                if !op.text.isEmpty {
                    out.append(op)
                } else if var last = out.popLast(), last.date.isEmpty {
                    // A bare date after a comma belongs to the operation before it.
                    last.date = op.date
                    last.range = NSUnionRange(last.range, op.range)
                    out.append(last)
                } else {
                    break
                }
            } else if i == 0 || out.isEmpty {
                return []
            } else {
                break
            }
            if stopped { break }
        }
        return out
    }

    /// The items of a section body.
    private static func items(_ ns: NSString, _ range: NSRange, strict: Bool, lenient: Bool = false, now: Date) -> [Operation] {
        var out: [Operation] = []
        for p in split(ns, range) {
            var stopped = false
            if let op = operation(ns, p, strict: strict, lenient: lenient, now: now, stopped: &stopped) {
                if !op.text.isEmpty {
                    out.append(op)
                } else if var last = out.popLast(), last.date.isEmpty {
                    // A date on its own ("CABG x3, 2019").
                    last.date = op.date
                    last.range = NSUnionRange(last.range, op.range)
                    out.append(last)
                }
            }
            if stopped { break }
        }
        return out
    }

    /// Splits at commas, semicolons and line breaks outside brackets, and at "and" after a date.
    private static func split(_ ns: NSString, _ range: NSRange) -> [NSRange] {
        var parts: [NSRange] = []
        var depth = 0
        var i = range.location
        let end = range.location + range.length
        var start = i
        while i < end {
            let ch = ns.character(at: i)
            if ch == 40 || ch == 91 { depth += 1 }
            if (ch == 41 || ch == 93) && depth > 0 { depth -= 1 }
            if depth == 0 && (ch == 44 || ch == 59 || ch == 10) {
                if i > start { parts.append(NSRange(location: start, length: i - start)) }
                start = i + 1
            }
            i += 1
        }
        if end > start { parts.append(NSRange(location: start, length: end - start)) }
        var out: [NSRange] = []
        for r in parts {
            var s = r.location
            let piece = ns.substring(with: r)
            for m in andAfterDateRx.all(piece) {
                let g = m.range(at: 1)
                let dateEnd = r.location + g.location + g.length
                let next = r.location + m.range.location + m.range.length
                if dateEnd > s { out.append(NSRange(location: s, length: dateEnd - s)) }
                s = next
            }
            if r.location + r.length > s { out.append(NSRange(location: s, length: r.location + r.length - s)) }
        }
        return out
    }

    /// One item as an operation; nil when it is not one. An item that is only a date has empty text. `stopped` is set when
    /// the item runs on into the rest of the sentence ("... now presenting for ..."): nothing after it is read.
    private static func operation(_ ns: NSString, _ range: NSRange, strict: Bool, lenient: Bool = false, historyLead: Bool = false, now: Date, stopped: inout Bool) -> Operation? {
        var t = ns.substring(with: range)
        if let b = bulletRx.first(t) { t = (t as NSString).substring(from: b.range.length) }
        var historyLead = historyLead
        if let l = leadRx.first(t), l.range.location == 0 {
            historyLead = isHistoryLead((t as NSString).substring(with: l.range))
            t = (t as NSString).substring(from: l.range.length)
        }
        // The planned procedure: the item is dropped, whole, and nothing after it is read.
        // (On the bar, "for" in the middle of an item is its reason, not a plan: "tonsillectomy for sleep apnea, jaw wiring" is two
        // operations. An item that starts with "for" is a plan.)
        if planningRx.first(t) != nil || (strict && forRx.first(t) != nil) || (lenient && forStartRx.first(t) != nil) {
            stopped = true
            return nil
        }
        if let cut = cutRx.first(t), cut.range.location > 0 {
            t = (t as NSString).substring(to: cut.range.location)
            stopped = true
        }
        t = tidy(t)
        guard !t.isEmpty else { return nil }
        var aside = ""
        if let a = asideRx.first(t) {
            aside = tidy((t as NSString).substring(from: a.range.location))
            t = tidy((t as NSString).substring(to: a.range.location))
        }
        let (rest, date) = extractDate(t, now: now)
        // A full date beside a birth date, a lab or a vital sign is that thing's (1.12).
        if date.day != nil, notSurgeryDateRx.first(t) != nil { return nil }
        t = rest
        if t.isEmpty { return date.isEmpty ? nil : Operation(text: "", date: date, aside: aside, range: range) }
        if commentaryRx.first(t) != nil || generic.contains(t.lowercased()) { return nil }
        if strict {
            guard isOperation(t, historyLead: historyLead) else { return nil }
        } else {
            guard t.filter(\.isLetter).count >= 3, !diagnosisLike(t) else { return nil }
            // On the bar: a recognized operation is one; so is any other item unless the note reader reads it as something else.
            if lenient, !isOperation(t), plainlySomethingElse(t, now: now) { return nil }
        }
        return Operation(text: t, date: date, aside: aside, range: range)
    }

    /// An item that is not an operation although it was typed on the Past Surgical History bar (1.12 follow-up): an anesthetic
    /// remark ("under GA"), or words the note reader files as anything but a procedure (a lab value, a drug, a history item,
    /// the allergies): "Hgb 12", "metoprolol 25 bid", "HTN", "NKDA".
    static func plainlySomethingElse(_ t: String, now: Date) -> Bool {
        if asideStartRx.first(t) != nil { return true }
        return PatientNote.read(t, now: now, abbreviations: [:], choices: [:], askRoomAir: false).findings.contains { f in
            switch f.change {
            case .procedure, .pastSurgery, .cardiacSurgery: return false
            default: return true
            }
        }
    }

    private static func tidy(_ s: String) -> String {
        var t = s.trimmingCharacters(in: CharacterSet(charactersIn: " \t:;,.-–•*").union(.whitespacesAndNewlines))
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        for tail in [" in", " on", " from", " at", " (", " of"] where t.lowercased().hasSuffix(tail) { t = String(t.dropLast(tail.count)) }
        if t.hasSuffix("(") { t = String(t.dropLast()) }
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " \t:;,.-–").union(.whitespacesAndNewlines))
    }

    /// The text without its (first) date, and the date: "TEVAR 08/2022", "CABG x3 in 2019", "(June 2015)"; since 1.12 a full
    /// date too: "appendectomy 6/14/2015", "CABG on 5/1/2019", "PCI June 14, 2015". A full date that is today's or later is
    /// not a past operation's: it is taken out of the words and the operation is left undated.
    static func extractDate(_ text: String, now: Date = Date()) -> (String, PatientMonthYear) {
        if let m = apostropheRx.first(text) {
            let ns = text as NSString
            let yy = m.range(at: 2).location != NSNotFound ? Int(ns.substring(with: m.range(at: 2))) : nil
            let month = m.range(at: 1).location != NSNotFound ? Int(ns.substring(with: m.range(at: 1))) : nil
            // 20YY only, and never later than next year: no 19xx from two digits.
            let thisYear = Calendar.current.component(.year, from: Date())
            if let yy, 2000 + yy <= thisYear + 1 {
                return (tidy(ns.replacingCharacters(in: m.range, with: " ")), PatientMonthYear(month: month, year: 2000 + yy))
            }
        }
        for rx in [monthYearRx, fullDateRx, numericRx, yearRx] {
            guard let m = rx.first(text), m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { continue }
            let ns = text as NSString
            guard var d = PatientMonthYear.parse(ns.substring(with: m.range(at: 1)), now: now) else { continue }
            if let day = d.calendarDate(), day >= Calendar.current.startOfDay(for: now) { d = PatientMonthYear() }
            let rest = ns.replacingCharacters(in: m.range, with: " ")
            return (tidy(rest), d)
        }
        return (text, PatientMonthYear())
    }

    /// A recognized operation: in the procedure list, or named like one.
    static func isOperation(_ t: String, historyLead: Bool = false) -> Bool {
        if surgicalRx.first(t) != nil || chestRx.first(t) != nil { return true }
        if diagnosisLike(t) { return false }
        // After a history lead, a procedure-list match alone is not enough: the list's aliases include diagnoses.
        if historyLead && shorthandRx.first(t) == nil { return false }
        return PlannedProcedure.parse(t).contains { $0.catalogID != nil }
    }

    /// A diagnosis with no operative word: the words are one ("AAA 4.5 cm", "type A dissection", "hiatal hernia",
    /// "ectopic pregnancy"), or what the procedure list matched in them is one (its alias "AAA" is the open repair's). A
    /// diagnosis beside a recognized operation ("lap chole for gallstones") is that operation's reason, not a diagnosis.
    static func diagnosisLike(_ t: String) -> Bool {
        guard diagnosisRx.first(t) != nil, surgicalRx.first(t) == nil, chestRx.first(t) == nil else { return false }
        let matches = ProcedureCatalog.parse(t)
        return matches.isEmpty || matches.contains { diagnosisRx.first($0.text) != nil && surgicalRx.first($0.text) == nil }
    }

    // MARK: Entries

    private static let modifiers: Set<String> = ["mechanical", "bioprosthetic", "tissue", "redo", "repeat", "mini", "hybrid", "emergent", "urgent", "elective",
                                                 "staged", "on-pump", "off-pump", "minimally", "invasive", "total", "partial"]
    /// Words that an approach in a procedure's name must be backed by in the note ("appendectomy" is not "laparoscopic").
    private static let approaches = ["laparoscopic", "robotic", "minimally", "thoracoscopic", "arthroscopic", "endoscopic"]
    private static let approachStems = ["lap", "robot", "scop", "vats", "minimal", "mini", "thoracosc", "tecab", "midcab"]

    /// The procedures of one piece of an operation, from the procedure list when it knows them, else as typed. A procedure
    /// whose list name adds an approach the note did not write stays as typed.
    private static func procedures(for piece: String) -> [PlannedProcedure] {
        let p = piece.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return [] }
        var parsed = PlannedProcedure.parse(p)
        // Nothing in the list: the words as typed (the list's reading drops joining words such as "and").
        if !parsed.contains(where: { $0.catalogID != nil }) { return [typed(p)] }
        let lower = p.lowercased()
        for item in parsed {
            guard let c = item.catalog else { continue }
            let n = c.name.lowercased()
            if approaches.contains(where: { n.contains($0) }), !approachStems.contains(where: { lower.contains($0) }) {
                return [typed(p)]
            }
        }
        // "mechanical MVR": the modifier is a detail of the procedure after it, not a procedure.
        if parsed.count >= 2, parsed[0].catalogID == nil {
            let words = parsed[0].name.lowercased().split(separator: " ").map(String.init)
            if !words.isEmpty, words.allSatisfy({ modifiers.contains($0) }) {
                let lead = parsed[0].name
                parsed.removeFirst()
                parsed[0].detail = ([lead] + (parsed[0].detail.isEmpty ? [] : [parsed[0].detail])).joined(separator: " ")
            }
        }
        return parsed.map { $0.catalogID == nil ? typed($0.name, detail: $0.detail, side: $0.side) : $0 }
    }

    private static func typed(_ name: String, detail: String = "", side: String? = nil) -> PlannedProcedure {
        var n = name
        if let f = n.first, f.isLowercase, n.dropFirst().first.map({ !$0.isUppercase }) ?? true { n = f.uppercased() + n.dropFirst() }
        return PlannedProcedure(name: n, side: side, detail: detail)
    }

    /// The entry for an operation: its procedures ("A + B" are two), the date, and the chest flag.
    static func surgery(_ text: String, _ date: PatientMonthYear) -> PatientSurgery {
        let pieces = text.replacingOccurrences(of: " plus ", with: " + ").components(separatedBy: "+")
        var list: [PlannedProcedure] = []
        for piece in pieces { list += procedures(for: piece) }
        if list.isEmpty { list = [typed(text)] }
        var s = PatientSurgery(procedures: list, date: date)
        if chestRx.first(text) != nil { s.intrathoracic = true }
        return s
    }

    /// Whether a cardiac operation (for the cardiac page's Previous cardiac surgery): a cardiac procedure of the list that
    /// opened the chest, or the words of a typed one. 1.10: a transcatheter heart procedure (TAVR, TEER, LAAO) is a
    /// cardiac procedure of the list but not cardiac surgery, and its name ("...aortic valve replacement") is not read
    /// as one.
    static func isCardiac(_ s: PatientSurgery) -> Bool {
        if s.procedures.contains(where: { $0.catalog.map { $0.cardiac && $0.incision == "Intrathoracic" } ?? false }) { return true }
        guard !s.procedures.isEmpty else { return cardiacWordsRx.first(s.name) != nil }
        let typed = s.procedures.filter { $0.catalog == nil }.map(\.text).joined(separator: " + ")
        return !typed.isEmpty && cardiacWordsRx.first(typed) != nil
    }

    // MARK: Matching what the record has

    /// The procedure list's ids of an entry. An entry typed as words has none: 1.12 follow-up (Ben: the bar added the first
    /// operation but not the ones after it) it is no longer given the list's nearest match by reading its words again, which
    /// gave two different typed operations the same id and made the second "already recorded". Only an entry with no procedures
    /// at all (a name with nothing behind it) is read from its name.
    private static func ids(_ s: PatientSurgery) -> Set<String> {
        var out = Set(s.procedures.compactMap(\.catalogID))
        if out.isEmpty, s.procedures.isEmpty { out = Set(ProcedureCatalog.parse(s.name).map(\.procedure.id)) }
        return out
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The dates are compatible: one is empty, or the years agree and the months agree or one is missing, and (1.12) the days
    /// agree or one is missing: a date with a day and the same date without one are one date (the fuller one is kept).
    private static func compatible(_ a: PatientMonthYear, _ b: PatientMonthYear) -> Bool {
        PatientMonthYear.compatible(a, b)
    }

    /// The same operation: the same procedures from the list (with no different side), or the same words, on dates that
    /// do not differ. 1.12 follow-up (Ben): the same WORDS, not words that contain the other's ("Hernia repair" is not "Inguinal
    /// hernia repair", nor "Knee surgery" "Knee surgery on the other side"): a different operation can always be added.
    static func same(_ a: PatientSurgery, _ b: PatientSurgery) -> Bool {
        guard compatible(a.date, b.date) else { return false }
        let x = ids(a), y = ids(b)
        if !x.isEmpty, !y.isEmpty {
            guard x == y else { return false }
            let sa = a.procedures.compactMap(\.side), sb = b.procedures.compactMap(\.side)
            return sa.isEmpty || sb.isEmpty || Set(sa) == Set(sb)
        }
        let na = normalized(a.name), nb = normalized(b.name)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        return na == nb
    }

    /// The same operation entered twice in the editors (1.10): `same`, and either the procedure list knows both or the
    /// words are the same ("Hernia repair" typed is not merged into "Inguinal hernia repair" typed).
    static func duplicate(_ a: PatientSurgery, _ b: PatientSurgery) -> Bool {
        guard same(a, b) else { return false }
        if !ids(a).isEmpty && !ids(b).isEmpty { return true }
        return normalized(a.name) == normalized(b.name)
    }

    static func index(of s: PatientSurgery, in r: PatientRecord) -> Int? {
        r.surgeries.firstIndex { same($0, s) }
    }

    static func isRecorded(_ text: String, _ date: PatientMonthYear, in r: PatientRecord) -> Bool {
        index(of: surgery(text, date), in: r) != nil
    }

    /// Adds the operation to Past surgical history unless it is there. A cardiac operation also becomes the cardiac page's
    /// Previous cardiac surgery when that is empty. Returns the entry's index.
    @discardableResult
    static func add(_ text: String, _ date: PatientMonthYear, cardiac: Bool = false, to r: inout PatientRecord) -> Int {
        var s = surgery(text, date)
        if cardiac { s.intrathoracic = true }
        let i: Int
        if let found = index(of: s, in: r) {
            i = found
            // The same operation on a date that does not differ: the fuller date stays (a day beats a month and year).
            r.surgeries[i].date = PatientMonthYear.fuller(r.surgeries[i].date, s.date)
            if cardiac { r.surgeries[i].intrathoracic = true }
        } else {
            r.surgeries.append(s)
            i = r.surgeries.count - 1
        }
        if (cardiac || isCardiac(r.surgeries[i])), r.hx.cardiacSurgeryID == nil { r.hx.cardiacSurgeryID = r.surgeries[i].id }
        return i
    }

    /// Previous cardiac surgery as the note reader gives it ("CABG x3 2015; mechanical MVR"): each operation its own entry.
    static func addCardiac(_ text: String, to r: inout PatientRecord) {
        for part in text.components(separatedBy: "; ") {
            let (rest, date) = extractDate(tidy(part))
            let t = rest.isEmpty ? tidy(part) : rest
            guard !t.isEmpty else { continue }
            add(t, date, cardiac: true, to: &r)
        }
    }

    static func cardiacRecorded(_ text: String, in r: PatientRecord) -> Bool {
        let parts = text.components(separatedBy: "; ")
        for part in parts {
            let (rest, date) = extractDate(tidy(part))
            let t = rest.isEmpty ? tidy(part) : rest
            if t.isEmpty { continue }
            if !isRecorded(t, date, in: r) { return false }
        }
        return !parts.isEmpty
    }
}

// MARK: - Newest first (1.12 follow-up, Ben: "organize psh by chronological order", then "most recent at top")

extension PatientSurgery {
    /// Where one date goes beside another in a list of past operations, newest first: -1 when `a` is listed before `b`, 1 after,
    /// 0 when they tie. Year, then month, then day, each descending. Within the same year an entry with a month comes before one
    /// with only the year, and with a day before one without (the more exactly dated first). No date at all (or a month with no
    /// year) comes last. The ONE rule: every list of past operations uses `chronological`.
    static func listOrder(_ a: PatientMonthYear, _ b: PatientMonthYear) -> Int {
        func part(_ x: Int?, _ y: Int?) -> Int {
            switch (x, y) {
            case (nil, nil): return 0
            case (nil, _?): return 1
            case (_?, nil): return -1
            case (let p?, let q?): return p == q ? 0 : (p > q ? -1 : 1)
            }
        }
        func month(_ d: PatientMonthYear) -> Int? { d.year != nil && d.month.map({ (1...12).contains($0) }) == true ? d.month : nil }
        func day(_ d: PatientMonthYear) -> Int? { month(d) != nil ? d.day : nil }
        let year = part(a.year, b.year)
        if year != 0 { return year }
        let m = part(month(a), month(b))
        if m != 0 { return m }
        return part(day(a), day(b))
    }

    /// The operations by date, the most recent first (see `listOrder`). Entries with no date come last in the order they were
    /// entered, and ties keep the order entered (a stable sort: `sorted` alone does not promise one). Nothing is stored in this
    /// order: references by id (the cardiac page's Previous cardiac surgery) keep pointing at the same entry.
    static func chronological(_ list: [PatientSurgery]) -> [PatientSurgery] {
        list.enumerated().sorted { a, b in
            let c = listOrder(a.element.date, b.element.date)
            return c != 0 ? c < 0 : a.offset < b.offset
        }.map(\.element)
    }
}

extension PatientRecord {
    /// Past surgical history for every place it is listed or printed: newest first (PatientSurgery.chronological).
    var surgeriesNewestFirst: [PatientSurgery] { PatientSurgery.chronological(surgeries) }
}

/// The rows of a page that lists past operations while they are being edited: their order is fixed when the page appears and
/// when an entry is added or removed (and so when the page's bar files one), not on every keystroke, so a row does not jump
/// under the finger while its date is typed. Rows are found by id, so a row edited after the list was sorted edits its own entry.
enum PastSurgeryOrder {
    /// The ids, newest first.
    static func ids(_ list: [PatientSurgery]) -> [UUID] { PatientSurgery.chronological(list).map(\.id) }

    /// The entries in the fixed order; an entry that is not in it yet comes after them in the order entered, one that is gone is
    /// dropped. With nothing fixed yet the list is sorted (the page's first frame).
    static func rows(_ list: [PatientSurgery], fixed: [UUID]) -> [PatientSurgery] {
        guard !fixed.isEmpty else { return PatientSurgery.chronological(list) }
        var byID: [UUID: PatientSurgery] = [:]
        for s in list where byID[s.id] == nil { byID[s.id] = s }
        let placed = Set(fixed)
        return fixed.compactMap { byID[$0] } + list.filter { !placed.contains($0.id) }
    }
}
