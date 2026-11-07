import Foundation

// MARK: - 1.8.3: free text starts with a capital (Ben: "all inputs not recognized by chips (free texted) should be
// formatted with Capital first letter for cohesiveness").

/// Capitalizes the first letter of a free-text entry and leaves the rest as typed. The entry is left alone when it starts
/// with something that is not a letter (a digit, a quote, a symbol), when its first word has a capital after the first
/// letter (eGFR, iCa, pH, NTproBNP, mL/kg), or when its first word is a unit or a dosing token (mg, mcg, kg, mL, dL,
/// mmHg, q6h).
enum FreeText {
    /// Units and tokens whose lower case is meaningful; compared as typed (the capitals in mL, dL and mmHg already keep
    /// those, the rest are here).
    static let tokens: Set<String> = ["mg", "mcg", "kg", "g", "ml", "mL", "dL", "dl", "l", "cm", "mm", "mmol", "meq", "mEq", "mmHg", "iu", "bpm", "min", "h", "hr", "x"]

    /// Leading characters skipped before deciding: spaces and opening or list punctuation.
    private static let skipped: Set<Character> = [" ", "\t", "\n", "(", "[", "{", "-", "–", "—", "•", "*", "·", ".", ",", ";", ":"]

    /// "metoprolol" → "Metoprolol"; "  adhesive tape" → "  Adhesive tape"; "eGFR 45", "3 vessel disease" unchanged.
    static func cap(_ s: String) -> String {
        // ASCII letters only: a leading "µg" or "μg" must not become "Μg", which reads as mg or Mg.
        guard let i = s.firstIndex(where: { !skipped.contains($0) }), s[i].isASCII, s[i].isLetter, s[i].isLowercase else { return s }
        // The first word, up to the next space; its first run of letters decides.
        let wordEnd = s[i...].firstIndex(where: { $0.isWhitespace }) ?? s.endIndex
        let word = s[i..<wordEnd]
        let run = word.prefix(while: { $0.isLetter })
        if run.dropFirst().contains(where: \.isUppercase) { return s }
        if tokens.contains(String(run)) || isDosingToken(word) { return s }
        // Leading spaces go with the capital; punctuation before the word stays.
        let start = s.firstIndex(where: { !$0.isWhitespace }) ?? s.startIndex
        var out = String(s[start...])
        let j = out.index(out.startIndex, offsetBy: s.distance(from: start, to: i))
        out.replaceSubrange(j...j, with: s[i].uppercased())
        return out
    }

    /// q6h, q4-6h, qAM style tokens, and "x3" multipliers.
    private static func isDosingToken(_ word: Substring) -> Bool {
        guard word.first == "q" || word.first == "x", let second = word.dropFirst().first else { return false }
        return second.isNumber
    }

    /// What a typeahead adds: a pick from its list as the list words it, anything typed with its first letter capitalized.
    static func picked(_ value: String, from options: [String]) -> String { options.contains(value) ? value : cap(value) }

    /// A list typed on one line ("amlodipine, metoprolol (25 mg, bid); aspirin"): each item is capitalized, the commas
    /// and semicolons inside parentheses are not item breaks.
    static func capItems(_ s: String, separators: Set<Character> = [",", ";", "\n"]) -> String {
        var out = ""
        var item = ""
        var depth = 0
        for ch in s {
            if ch == "(" || ch == "[" { depth += 1 } else if (ch == ")" || ch == "]") && depth > 0 { depth -= 1 }
            if depth == 0 && separators.contains(ch) {
                out += capItem(item) + String(ch)
                item = ""
            } else {
                item.append(ch)
            }
        }
        return out + capItem(item)
    }

    /// One item of a list, keeping the space after the separator.
    private static func capItem(_ item: String) -> String {
        let lead = item.prefix(while: { $0 == " " || $0 == "\t" })
        return String(lead) + cap(String(item.dropFirst(lead.count)))
    }

    /// Procedures joined with " + ".
    static func capJoined(_ s: String) -> String {
        s.components(separatedBy: " + ").map(cap).joined(separator: " + ")
    }
}

// MARK: - The record as it reads on a summary

extension PatientRecord {
    /// A copy whose free-text entries start with a capital, for the summary, the handoff and the History list; the saved
    /// record keeps what was typed, so an older save reads the same way. Catalog items are not touched (they are
    /// already styled), and text that sits inside a sentence or a parenthesis (the tracheostomy type, the ventilator settings) is left as typed.
    var capitalized: PatientRecord {
        var r = self
        r.procedure = FreeText.capJoined(r.procedure)
        r.procedures = r.procedures.map(Self.capTyped)
        r.otherHistory = FreeText.cap(r.otherHistory)
        r.allergies = FreeText.capItems(r.allergies)
        r.medications = FreeText.capItems(r.medications)
        r.systemNotes = r.systemNotes.mapValues(FreeText.cap)
        r.systemOther = r.systemOther.mapValues(FreeText.cap)
        r.homeMeds = r.homeMeds.map { var m = $0; m.name = FreeText.cap(m.name); return m }
        r.allergyList = r.allergyList.map { var a = $0; a.name = FreeText.cap(a.name); return a }
        r.limbAlerts = r.limbAlerts.map { var a = $0; a.reason = FreeText.cap(a.reason); return a }
        r.hx.respInfectionType = FreeText.cap(r.hx.respInfectionType)
        r.anesthesiaNotes = FreeText.cap(r.anesthesiaNotes)
        r.labNotes = FreeText.cap(r.labNotes)
        r.infections.other = r.infections.other.map { var o = $0; o.name = FreeText.cap(o.name); return o }
        r.surgeries = r.surgeries.map(Self.capSurgery)
        r.intrathoracic = r.intrathoracic.map(Self.capSurgery)
        r.homeInfusions = r.homeInfusions.map(Self.capInfusion)
        r.ecg = r.ecg.map(FreeText.cap)
        r.ecgNotes = FreeText.cap(r.ecgNotes)
        r.echoFindings = Self.capEcho(r.echoFindings)
        r.intraopEcho = Self.capEcho(r.intraopEcho)
        r.intraopEchoPost = Self.capEcho(r.intraopEchoPost)
        r.lhc.notes = FreeText.cap(r.lhc.notes)
        r.carotid.notes = FreeText.cap(r.carotid.notes)
        r.radial.notes = FreeText.cap(r.radial.notes)
        r.pft.notes = FreeText.cap(r.pft.notes)
        r.teeScreen.notes = FreeText.cap(r.teeScreen.notes)
        r.teeScreen.egdFindings = FreeText.cap(r.teeScreen.egdFindings)
        r.dentition = FreeText.cap(r.dentition)
        r.airwayNotes = FreeText.cap(r.airwayNotes)
        r.examNotes = FreeText.cap(r.examNotes)
        r.maskNote = FreeText.cap(r.maskNote)
        r.sgaNote = FreeText.cap(r.sgaNote)
        r.intubationNote = FreeText.cap(r.intubationNote)
        r.tube = FreeText.cap(r.tube)
        r.infusions = r.infusions.map(Self.capInfusion)
        r.factors = FreeText.capItems(r.factors, separators: [";", "\n"])
        r.medsGiven = FreeText.capItems(r.medsGiven, separators: [";", "\n"])
        r.events = FreeText.cap(r.events)
        r.echo = FreeText.cap(r.echo)
        r.intraopLabs = r.intraopLabs.map { var s = $0; s.viscoelastic = FreeText.cap(s.viscoelastic); s.other = FreeText.cap(s.other); return s }
        r.considerationsNote = FreeText.cap(r.considerationsNote)
        r.codeStatusLimits = FreeText.cap(r.codeStatusLimits)
        r.codeStatusPlanNote = FreeText.cap(r.codeStatusPlanNote)
        r.painPlan = FreeText.cap(r.painPlan)
        r.callIf = FreeText.cap(r.callIf)
        r.todos = FreeText.cap(r.todos)
        return r
    }

    private static func capTyped(_ p: PlannedProcedure) -> PlannedProcedure {
        guard p.catalogID == nil else { return p }
        var q = p
        q.name = FreeText.cap(p.name)
        return q
    }

    private static func capSurgery(_ s: PatientSurgery) -> PatientSurgery {
        var t = s
        t.name = FreeText.capJoined(s.name)
        t.procedures = s.procedures.map(capTyped)
        return t
    }

    private static func capInfusion(_ i: PatientInfusion) -> PatientInfusion {
        var j = i
        j.drug = FreeText.cap(i.drug)
        return j
    }

    private static func capEcho(_ e: PatientEcho) -> PatientEcho {
        var f = e
        f.aorta = FreeText.cap(e.aorta)
        f.other = FreeText.cap(e.other)
        // 1.10: the chambers' and valves' free text and the prosthesis details.
        f.lvNotes = FreeText.cap(e.lvNotes)
        f.rvNotes = FreeText.cap(e.rvNotes)
        for kp in [\PatientEcho.mitral, \PatientEcho.tricuspid, \PatientEcho.aortic] {
            f[keyPath: kp].notes = FreeText.cap(e[keyPath: kp].notes)
            f[keyPath: kp].prosthesisDetail = FreeText.cap(e[keyPath: kp].prosthesisDetail)
        }
        return f
    }
}
