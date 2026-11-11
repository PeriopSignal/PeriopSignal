import Foundation

// MARK: - Labs that are not numbers: type and screen, and infectious results (1.8.3)
//
// Ben, Nov 3: "add lactate and type and screen to labs"; "need infectious labs (staph, mrsa, Covid, c-diff, other)".
// Both sit in Labs, after the numbers, and on the labs line in that order: "… · Lactate 1.4 · T&S A−, screen neg ·
// 2 u crossmatched · Staph screen neg · MRSA neg · COVID neg · C. diff neg". Typed shorthand is read by the note
// reader, so the quick-add bar and a pasted note read the same words ("T&S A-/-", "MRSA screen negative", "2u xm").
//
// A positive result marks the matching Infectious history item (Ben, Nov 3): MRSA → MRSA or VRE ("mdro"), COVID-19 →
// Recent COVID-19 ("covid-recent"), C. difficile → C. difficile ("c-diff"), and an Other result the history's MRSA/VRE
// rule reads (VRE) → "mdro". A Staph aureus screen links nothing: S. aureus colonization is not an MDRO unless it is
// MRSA. Negative or pending never adds anything. The items a result added are kept in PatientRecord.labProblems; when
// that result stops being positive the item goes again, but only if the result added it: an item the user (or a
// history finding from a note) entered stays.

enum LabResult: String, Codable, CaseIterable, Hashable {
    case negative = "neg", positive = "pos", pending

    var label: String {
        switch self {
        case .negative: return "Negative"
        case .positive: return "Positive"
        case .pending: return "Pending"
        }
    }

    /// "neg", "pos", "pending", as the labs line writes it.
    var short: String { rawValue }

    /// Positive or pending: what the short handoff shows.
    var needsTelling: Bool { self != .negative }
}

/// Where the type and screen stands before its result (1.11, Ben's note 1: "Type & Screen" on the labs fishbone sheet):
/// not sent, sent and awaited, or resulted (the ABO/Rh and the antibody screen are then recorded).
enum TypeScreenStatus: String, Codable, CaseIterable, Hashable {
    case notSent = "not-sent", sent, resulted

    var label: String {
        switch self {
        case .notSent: return "Not sent"
        case .sent: return "Sent"
        case .resulted: return "Resulted"
        }
    }
}

/// Type and screen: ABO/Rh, the antibody screen and the units crossmatched.
struct PatientTypeScreen: Codable, Hashable {
    /// "A+", "A-", … "O-" (ASCII); shown with a minus sign ("A−").
    var type: String?
    var screen: LabResult?
    /// The antibody a positive screen found, as typed ("anti-K").
    var antibody = ""
    var crossmatched: Int?
    /// Not sent or sent, as the user said (1.11); a result recorded (hasResult) reads as resulted whatever this holds.
    var status: TypeScreenStatus?

    static let types = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]
    static let unitLimit = 40

    init(type: String? = nil, screen: LabResult? = nil, antibody: String = "", crossmatched: Int? = nil, status: TypeScreenStatus? = nil) {
        self.type = type; self.screen = screen; self.antibody = antibody; self.crossmatched = crossmatched; self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decodeIfPresent(String.self, forKey: .type)).flatMap { Self.types.contains($0) ? $0 : nil }
        screen = try? c.decodeIfPresent(LabResult.self, forKey: .screen)
        antibody = (try? c.decodeIfPresent(String.self, forKey: .antibody)) ?? ""
        crossmatched = try? c.decodeIfPresent(Int.self, forKey: .crossmatched)
        // Records saved before 1.11 have no status: nil, and a recorded result still reads as resulted.
        status = try? c.decodeIfPresent(TypeScreenStatus.self, forKey: .status)
    }

    var isEmpty: Bool { type == nil && screen == nil && antibodyText.isEmpty && crossmatched == nil && status == nil }

    var antibodyText: String { antibody.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A result is recorded: the ABO/Rh, the antibody screen, an antibody named, or units crossmatched. Every one
    /// of them prints on the labs line, so every one keeps the result rows open.
    var hasResult: Bool { type != nil || screen != nil || !antibodyText.isEmpty || (crossmatched ?? 0) > 0 }

    /// A result recorded means resulted, whatever was tapped; otherwise what the user said, if anything.
    var effectiveStatus: TypeScreenStatus? { hasResult ? .resulted : status }

    /// What a tap on the status chips records: Resulted opens the result rows; Not sent and Sent clear a result
    /// already recorded (the user says there is none): the type, the screen, the antibody and the units
    /// crossmatched, so the line never reads "T&S not sent · 2 u crossmatched". The same chip again (nil) clears
    /// the status, and a result recorded stays.
    mutating func setStatus(_ s: TypeScreenStatus?) {
        status = s
        if let s, s != .resulted {
            type = nil
            screen = nil
            antibody = ""
            crossmatched = nil
        }
    }

    /// "A−".
    static func display(_ t: String) -> String { t.replacingOccurrences(of: "-", with: "−") }

    /// "screen neg", "screen pos (anti-K)", "screen pending".
    var screenText: String? {
        guard let s = screen else { return antibodyText.isEmpty ? nil : "antibody " + antibodyText }
        return "screen " + s.short + (s == .positive && !antibodyText.isEmpty ? " (" + antibodyText + ")" : "")
    }

    /// "T&S A−, screen neg"; without a result, "T&S sent, result pending" or "T&S not sent" when the user said so;
    /// nil with nothing, and nil with only units crossmatched (they are a result, and print on their own).
    var head: String? {
        let parts = [type.map(Self.display), screenText].compactMap { $0 }
        if parts.isEmpty {
            switch effectiveStatus {
            case .sent?: return "T&S sent, result pending"
            case .notSent?: return "T&S not sent"
            default: return nil
            }
        }
        return "T&S " + parts.joined(separator: ", ")
    }

    /// "2 u crossmatched".
    var crossmatchText: String? { crossmatched.flatMap { $0 > 0 ? "\($0) u crossmatched" : nil } }

    /// The labs line's parts: ["T&S A−, screen neg", "2 u crossmatched"].
    var parts: [String] { [head, crossmatchText].compactMap { $0 } }

    /// What a note gave, over what the record holds: only the parts the note said.
    func merged(over o: PatientTypeScreen) -> PatientTypeScreen {
        var r = o
        if let t = type { r.type = t }
        if let s = screen { r.screen = s }
        if !antibodyText.isEmpty { r.antibody = antibodyText }
        if let x = crossmatched { r.crossmatched = x }
        if let s = status { r.status = s }
        return r
    }
}

/// An infectious result beyond the four named tests: a typed name ("VRE") and its result.
struct PatientInfectiousOther: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = ""
    var result: LabResult?

    init(name: String = "", result: LabResult? = nil) { self.name = name; self.result = result }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        result = try? c.decodeIfPresent(LabResult.self, forKey: .result)
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct PatientInfections: Codable, Hashable {
    /// By InfectiousTest id ("staph", "mrsa", "covid", "cdiff").
    var results: [String: LabResult] = [:]
    var other: [PatientInfectiousOther] = []

    init(results: [String: LabResult] = [:], other: [PatientInfectiousOther] = []) { self.results = results; self.other = other }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = (try? c.decodeIfPresent([String: LabResult].self, forKey: .results)) ?? [:]
        other = (try? c.decodeIfPresent([PatientInfectiousOther].self, forKey: .other)) ?? []
    }

    var isEmpty: Bool { results.isEmpty && !other.contains { $0.result != nil || !$0.trimmedName.isEmpty } }
}

/// One of the four named tests.
struct InfectiousTest: Hashable, Identifiable {
    var id: String
    /// "MRSA screen", on the Labs screen.
    var label: String
    /// "MRSA", on the labs line.
    var short: String
    /// The Infectious history item a positive result marks.
    var link: String?
}

enum LabResults {
    static let infectious: [InfectiousTest] = [
        InfectiousTest(id: "staph", label: "Staph aureus screen", short: "Staph screen", link: nil),
        InfectiousTest(id: "mrsa", label: "MRSA screen", short: "MRSA", link: "mdro"),
        InfectiousTest(id: "covid", label: "COVID-19 test", short: "COVID", link: "covid-recent"),
        InfectiousTest(id: "cdiff", label: "C. difficile test", short: "C. diff", link: "c-diff"),
    ]

    static func test(_ id: String) -> InfectiousTest? { infectious.first { $0.id == id } }

    /// The history item an Other result named so would mark when positive: "mdro" for a name the MRSA/VRE rule reads.
    static func otherLink(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        return PatientNote.problemRuleReads("mdro", n) ? "mdro" : nil
    }

    // MARK: Text

    /// "Staph screen neg", "MRSA pos", "VRE pending", each entered result in the screen's order.
    static func infectiousParts(_ x: PatientInfections, onlyTelling: Bool = false) -> [(text: String, result: LabResult)] {
        var out: [(String, LabResult)] = []
        for t in infectious {
            guard let v = x.results[t.id], !onlyTelling || v.needsTelling else { continue }
            out.append((t.short + " " + v.short, v))
        }
        for o in x.other {
            guard let v = o.result, !o.trimmedName.isEmpty, !onlyTelling || v.needsTelling else { continue }
            out.append((o.trimmedName + " " + v.short, v))
        }
        return out
    }

    /// The labs line after the numbers: type and screen, then the infectious results; positives are marked.
    static func lineParts(_ r: PatientRecord) -> (parts: [String], marks: [String]) {
        var parts = r.typeScreen.parts
        var marks: [String] = []
        if r.typeScreen.screen == .positive, let h = r.typeScreen.head { marks.append(h) }
        for p in infectiousParts(r.infections) {
            parts.append(p.text)
            if p.result == .positive { marks.append(p.text) }
        }
        // 1.12 (Ben's note 12): the urinalysis and blood cultures sit with the infectious results; the pregnancy test (a
        // typed hCG that is a number is on the numbers' line) after them, for a woman or a patient whose sex is not set.
        let more = r.moreLabs.infectiousParts
        parts += more.parts
        marks += more.marks
        if PatientMoreLabs.showsPregnancy(r.sex) { parts += r.moreLabs.pregnancyParts }
        return (parts, marks)
    }

    /// The short handoff's line: positive and pending results only ("MRSA pos · COVID pending").
    static func shortInfectious(_ r: PatientRecord) -> String {
        infectiousParts(r.infections, onlyTelling: true).map(\.text).joined(separator: " · ")
    }

    // MARK: Linking to the Infectious history

    /// The history items the record's positive results point to.
    static func links(_ r: PatientRecord) -> Set<String> {
        var out: Set<String> = []
        for t in infectious where r.infections.results[t.id] == .positive { if let l = t.link { out.insert(l) } }
        for o in r.infections.other where o.result == .positive { if let l = otherLink(o.name) { out.insert(l) } }
        return out
    }

    /// Changes the infectious results and keeps the history in step: an item a result now points to is added (and
    /// remembered as the labs') when it is not there; one no result points to any more is removed only if the labs
    /// added it.
    static func edit(_ r: inout PatientRecord, _ body: (inout PatientInfections) -> Void) {
        let before = links(r)
        body(&r.infections)
        let after = links(r)
        for p in after.subtracting(before) where !r.problems.contains(p) {
            r.noHistory = false
            r.problems.insert(p)
            r.labProblems.insert(p)
        }
        for p in before.subtracting(after) where r.labProblems.contains(p) {
            r.problems.remove(p)
            r.labProblems.remove(p)
        }
    }

    /// One result set (nil clears it), by test id, or by name for an Other result.
    static func set(_ id: String, name: String = "", _ v: LabResult?, in r: inout PatientRecord) {
        edit(&r) { x in
            if id == "other" {
                let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if let i = x.other.firstIndex(where: { $0.trimmedName.caseInsensitiveCompare(n) == .orderedSame }) {
                    if let v { x.other[i].result = v } else { x.other.remove(at: i) }
                } else if let v, !n.isEmpty {
                    x.other.append(PatientInfectiousOther(name: n, result: v))
                }
            } else {
                x.results[id] = v
            }
        }
    }

    static func result(_ id: String, name: String = "", in r: PatientRecord) -> LabResult? {
        if id == "other" { return r.infections.other.first { $0.trimmedName.caseInsensitiveCompare(name) == .orderedSame }?.result }
        return r.infections.results[id]
    }

    // MARK: Reading typed shorthand

    /// Negative and pending: the note reader's own words (PatientNote.resultNegative, resultPending), so a result read
    /// here as not positive is never filed as a history item there.
    private static let negWord = PatientNote.resultNegative
    private static let posWord = #"pos(?:itive)?\b|\+ve\b|\(\+\)|detected\b|\+(?=[\s,;.)/]|$)"#
    private static let pendingWord = PatientNote.resultPending

    static func resultOf(_ word: String) -> LabResult? {
        let w = word.lowercased()
        if NoteRx("^(?:" + pendingWord + ")").first(w) != nil { return .pending }
        if NoteRx("^(?:" + negWord + ")").first(w) != nil { return .negative }
        if NoteRx("^(?:" + posWord + ")").first(w) != nil { return .positive }
        return nil
    }

    /// The names read, each with its test id ("other" with the name to show).
    private static let names: [(id: String, show: String?, rx: String)] = [
        ("mrsa", nil, #"mrsa|methicillin[- ]resistant\s+(?:staph(?:ylococcus)?|s\.)\s*(?:aureus)?"#),
        ("staph", nil, #"mssa|staph(?:ylococcus)?(?:\s+aureus)?|s\.\s?aureus"#),
        ("covid", nil, #"covid(?:[- ]?19)?|sars[- ]?cov[- ]?2|coronavirus"#),
        ("cdiff", nil, #"c\.?\s?diff(?:icile)?|clostridi(?:um|oides)\s+difficile"#),
        ("other", "VRE", #"vre|vancomycin[- ]resistant\s+enterococc(?:us|i|al)"#),
        ("other", "ESBL", #"esbl"#),
        ("other", "CRE", #"cre"#),
        ("other", "GBS", #"gbs|group\s+b\s+strep(?:tococcus)?"#),
        ("other", "Influenza", #"influenza|flu"#),
        ("other", "RSV", #"rsv"#),
    ]

    private static let nameAlt = names.map(\.rx).joined(separator: "|")
    /// Names (one, or several joined by "/" or "and"), the words a result is written with, then the result.
    static let infectiousRx = NoteRx(#"(?<![A-Za-z0-9])((?:"# + nameAlt + #")(?:\s*(?:/|&|\band\b)\s*(?:"# + nameAlt + #"))*)(?![A-Za-z0-9])(?:\s*\(?\s*(?:"# + PatientNote.resultQualifiers + #")\)?){0,4}\s*(?:(?:is|was|were|came back|returned)\s+)?[:=]?\s*("# + negWord + "|" + posWord + "|" + pendingWord + ")")
    private static let nameSplit = NoteRx(#"\s*(?:/|&|\band\b)\s*"#)

    private static func nameID(_ s: String) -> (id: String, show: String)? {
        for n in names where NoteRx("^(?:" + n.rx + ")$").first(s.trimmingCharacters(in: .whitespaces)) != nil {
            return (n.id, n.show ?? s)
        }
        return nil
    }

    // Type and screen.
    static let tsLead = NoteRx(#"\bt\s*&\s*s\b|\bt\s+and\s+s\b|\btype\s*(?:&|and)\s*(?:screen|cross(?:match)?)\b|\bt\s*&\s*c\b|\babo(?:\s*/\s*rh)?\b|\bblood\s+(?:type|group|bank)\b"#)
    private static let rhWord = #"\+|-|−|pos(?:itive)?\b|neg(?:ative)?\b"#
    static let tsType = NoteRx(#"^\s*[:=]?\s*(?:is\s+)?(ab|a|b|o)\s*(?:rh\s*(?:\(d\)\s*)?)?("# + rhWord + #")(?:\s*/\s*("# + rhWord + #"))?"#)
    static let tsScreen = NoteRx(#"\b((?:antibody|ab|abs)\s+)?screen(?:ing)?\s*(?:is\s+|was\s+)?[:=]?\s*(neg(?:ative)?\b|pos(?:itive)?\b|pending\b|-(?=[\s,;.)]|$)|\+)"#)
    /// Screens that are not the blood bank's, said just before "screen": infectious (MRSA, COVID), HIT (PF4, heparin),
    /// viral serologies (HIV, HCV, HBs), transplant (HLA, PRA), ANA, drug, tox and urine screens.
    private static let notBloodBankBefore = NoteRx(#"\b(?:mrsa|mssa|staph\w*|aureus|covid\S*|vre|nares|nasal|diff\w*|esbl|cre|gbs|flu|influenza|rsv|swab|hit|pf4|heparin|hiv(?:[- ]?1\s*/\s*2)?|hcv|hbs\w*|hbv|hla|pra|ana|drugs?|tox\w*|urine|uds|hep(?:atitis)?\s*[abc]|hav|hev)\s*(?:[/&]\s*\w+\s*)?(?:(?:antibody|ab|abs)\s+)?$"#)
    /// An ABO/Rh type written without a lead ("O neg, antibody screen negative"): lets the clause's antibody screen be read.
    static let aboType = NoteRx(#"(?<![A-Za-z])(?<![Hh]ep\s)(?<!HEP\s)(?<![Hh]epatitis\s)(?<![Gg]roup\s)(?<!GROUP\s)(?<![Vv]itamin\s)(?:AB|A|B|O)\s*(?:Rh\s*)?(?:\+|[-−](?![A-Za-z])|pos(?:itive)?\b|neg(?:ative)?\b)"#, caseSensitive: true)
    /// Red-cell alloantibodies only ("anti-K", "anti-Fya", "anti-Jk(a)"), case as written: not anti-Xa, anti-PF4 or an
    /// anticoagulant.
    static let tsAntibody = NoteRx(#"(?<![A-Za-z])[Aa]nti-?\s?(D|C|c|E|e|K|k|Cw|Kp(?:a|b|\([ab]\))|Js(?:a|b|\([ab]\))|Fy(?:a|b|\([ab]\))|Jk(?:a|b|\([ab]\))|Le(?:a|b|\([ab]\))|Lu(?:a|b|\([ab]\))|Di(?:a|b|\([ab]\))|M|N|S|s|U|P1|Wra)(?![A-Za-z0-9(])"#, caseSensitive: true)
    static let xmBefore = NoteRx(#"\b(\d{1,2})\s*(?:u\b|units?\b|uprbc\b)?\s*(?:(?:of\s+)?(?:prbcs?|rbcs?|red cells)\s+)?(?:x-?m(?:atch(?:ed)?)?|xm'?d|cross-?match(?:ed)?)\b"#)
    static let xmAfter = NoteRx(#"\b(?:x-?m(?:atch(?:ed)?)?|xm'?d|cross-?match(?:ed)?)\s*(?:for\s+|x\s*)?(\d{1,2})\s*(?:u\b|units?\b)"#)

    static var patterns: [NoteRx] { [infectiousRx, nameSplit, tsLead, tsType, tsScreen, notBloodBankBefore, aboType, tsAntibody, xmBefore, xmAfter] }

    /// What one clause says of type and screen and infectious results, with where.
    static func read(_ c: String) -> [(finding: PatientNoteFinding, ranges: [NSRange])] {
        var out: [(finding: PatientNoteFinding, ranges: [NSRange])] = []
        let ns = c as NSString
        // Infectious results.
        var taken: [NSRange] = []
        for m in infectiousRx.all(c) {
            let list = ns.substring(with: m.range(at: 1))
            guard let v = resultOf(ns.substring(with: m.range(at: 2))) else { continue }
            let pieces = list.components(separatedBy: "/").flatMap { $0.components(separatedBy: "&") }
                .flatMap { $0.components(separatedBy: " and ") }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for p in pieces {
                guard let n = nameID(p) else { continue }
                // A positive COVID-19 only where the history would file Recent COVID-19: not old ("COVID+ 2021"), not an
                // exposure, vaccine or screen (1.8.3 review).
                if n.id == "covid", v == .positive, !PatientNote.problemRuleAccepts("covid-recent", c) { continue }
                out.append((infectiousFinding(n.id, name: n.show, v), [m.range]))
            }
            taken.append(m.range)
        }
        // Type and screen.
        var ts = PatientTypeScreen()
        var ranges: [NSRange] = []
        let lead = tsLead.first(c)
        if let l = lead {
            ranges.append(l.range)
            let after = ns.substring(from: l.range.location + l.range.length)
            if let t = tsType.first(after) {
                let abo = (after as NSString).substring(with: t.range(at: 1)).uppercased()
                let rh = (after as NSString).substring(with: t.range(at: 2))
                if let rhRes = resultOf(rh.replacingOccurrences(of: "+", with: "pos")) {
                    ts.type = abo + (rhRes == .positive ? "+" : "-")
                }
                if t.range(at: 3).location != NSNotFound, let s = resultOf((after as NSString).substring(with: t.range(at: 3)).replacingOccurrences(of: "+", with: "pos")), s != .pending {
                    ts.screen = s
                }
                ranges.append(NSRange(location: l.range.location + l.range.length + t.range.location, length: t.range.length))
            }
        }
        // The antibody screen only with a T&S, type-and-screen or blood-bank lead, or an ABO/Rh type in the same clause,
        // and never another screen's ("HIT antibody screen", "HCV Ab screen", "drug/tox screen") (1.8.3 review).
        let bloodBank = lead != nil || aboType.first(c) != nil
        for m in tsScreen.all(c) where bloodBank && !taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
            let before = ns.substring(to: m.range.location)
            guard notBloodBankBefore.first(before) == nil else { continue }
            if let s = resultOf(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: "+", with: "pos")) {
                ts.screen = s
                ranges.append(m.range)
                break
            }
        }
        // The antibody named, as written; a name alone never makes the screen positive.
        if bloodBank {
            let found = tsAntibody.all(c)
            if !found.isEmpty {
                ts.antibody = found.map { "anti-" + ns.substring(with: $0.range(at: 1)) }.joined(separator: ", ")
                ranges += found.map(\.range)
            }
        }
        if let x = xmBefore.first(c) ?? xmAfter.first(c), let n = Int(ns.substring(with: x.range(at: 1))), (1...PatientTypeScreen.unitLimit).contains(n) {
            ts.crossmatched = n
            ranges.append(x.range)
        }
        if !ts.isEmpty, !ranges.isEmpty { out.append((typeScreenFinding(ts), ranges)) }
        return out
    }

    static func infectiousFinding(_ id: String, name: String, _ v: LabResult) -> PatientNoteFinding {
        let n = id == "other" ? name : (test(id)?.label ?? name)
        return PatientNoteFinding(id: "infectious:" + (id == "other" ? "other:" + name.lowercased() : id), section: PatientNote.Part.labs,
                                  label: n + ": " + v.label.lowercased(), change: .infectious(id, id == "other" ? name : "", v))
    }

    static func typeScreenFinding(_ ts: PatientTypeScreen) -> PatientNoteFinding {
        var parts: [String] = []
        if let t = ts.type { parts.append(PatientTypeScreen.display(t)) }
        if let s = ts.screen { parts.append("antibody screen " + s.label.lowercased() + (ts.antibodyText.isEmpty ? "" : " (" + ts.antibodyText + ")")) }
        if let x = ts.crossmatched { parts.append("\(x) unit" + (x == 1 ? "" : "s") + " crossmatched") }
        return PatientNoteFinding(id: "typeScreen", section: PatientNote.Part.labs, label: "Type & screen: " + parts.joined(separator: ", "),
                                  change: .typeScreen(ts))
    }

    // MARK: The note reader's status and apply

    static func status(_ ts: PatientTypeScreen, in r: PatientRecord) -> PatientNoteStatus {
        let o = r.typeScreen
        let merged = ts.merged(over: o)
        if merged == o { return .recorded }
        let clash = (ts.type != nil && o.type != nil && ts.type != o.type) || (ts.screen != nil && o.screen != nil && ts.screen != o.screen)
            || (ts.crossmatched != nil && o.crossmatched != nil && ts.crossmatched != o.crossmatched)
        return clash ? .replaces(o.parts.joined(separator: ", ")) : .new
    }

    static func status(_ id: String, name: String, _ v: LabResult, in r: PatientRecord) -> PatientNoteStatus {
        guard let o = result(id, name: name, in: r) else { return .new }
        return o == v ? .recorded : .replaces(o.label.lowercased())
    }
}

extension PatientNote {
    /// The history's own rule for a problem reads this text (an Other result named "VRE" reads as MRSA or VRE).
    static func problemRuleReads(_ id: String, _ text: String) -> Bool { problemRule(id)?.first(text) != nil }
}
