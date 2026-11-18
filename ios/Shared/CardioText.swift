import Foundation

// MARK: - Cardiopulmonary test findings typed into the text bars (1.12 follow-up, Ben, Nov 18)
//
// "add ability to fill cardiopulmonary testing findings into text bars (allow abbreviations)". A line such as "TTE 6/26 EF 35%,
// mod MR, RV nl" or "LHC: LAD 90%, RCA 40%" is read into the fields of that test (the echo, the left and right heart
// catheterization, the PFTs and chest X-ray, the carotid and radial artery ultrasounds), as chips to confirm before they are
// added. Nothing is stored that is not read: no field is added or renamed, the reader only fills the ones the pages hold.
//
// The one rule that keeps this safe: a finding is read ONLY inside its study's run. A run starts at the study's cue ("TTE",
// "LHC", "RHC", "PFTs", "CXR", "carotid US", "radial US"; a cue alone that means a catheter or a probe is no cue) and covers the
// rest of its comma piece, then the following pieces for as long as each holds only findings of that study and filler; it ends
// at the first piece that is something else, at a full stop or a new line, or at another study's cue. On a study's own page the
// page is the cue. Outside a run everything is read exactly as before: an "EF 35%" with no echo cue stays history, "RA" stays
// room air, "PDA" a duct. A study that was not done ("no echo", "needs TTE", "LHC ordered") reads nothing and its words are
// masked; a number outside the plausible range, a finding that is denied or hedged, and two findings that disagree for the same
// field are not read (their words stay). Words in a run that are not understood stay exactly as the bar leaves unread words.
//
// The patterns are CardioRx (CardioTextPatterns.swift), generated from the Python model this reader was written and tested in
// (SP/cardiotext/cardio.py with the tables of tables.py); T112Tests is generated from the same tables.

enum CardioStudy: String, CaseIterable, Hashable {
    case echo, lhc, rhc, pft, cxr, carotid, radial

    /// Where the chip says the finding goes.
    var destination: String {
        switch self {
        case .echo: return "Echo"
        case .lhc: return "LHC"
        case .rhc: return "RHC"
        case .pft: return "PFT"
        case .cxr: return "CXR"
        case .carotid: return "Carotid"
        case .radial: return "Radial"
        }
    }
}

/// One field of one study read from a line: the study, the field ("lvef", "stenosis.lad", "right.stenosis", "date") and its
/// value as text ("35", "ge70", "06/2026"). PatientNoteChange.cardio carries it; CardioText applies, compares and words it.
struct CardioFinding: Hashable {
    var study: CardioStudy
    var field: String
    var value: String
}

/// What a line gave: findings to confirm and the stretches of the line to mask from the readers that follow.
struct CardioReading {
    var findings: [PatientNoteFinding] = []
    var masks: [NSRange] = []
}

enum CardioText {
    // MARK: Internal records

    /// One reading, with where it was read (offsets in UTF-16 units of the line).
    private struct CF {
        var study: String
        var field: String
        var value: String
        var a: Int = 0
        var b: Int = 0
        /// Left heart cath: the vessel was named with a segment (two segments of one vessel read the higher number).
        var segment = false
        /// Echo valve: the history reader reads these words too, so they are left in the line.
        var keepWords = false
        /// Echo valve in a form the history reader does not know ("sev AS"): the history's valve (valve, lesion, grade).
        var history: [String]? = nil

        var key: String { study + "." + field }
    }

    /// One piece (or part of one) of the line and what it gave.
    private final class CParse {
        let text: String
        let base: Int
        var work: String
        var findings: [CF] = []
        var consumed: [NSRange] = []
        var poison: [String] = []
        var aux: [NSRange] = []
        var rejected = false
        /// "disease": the cath named disease the model does not store (a branch, three-vessel disease).
        var flags = Set<String>()

        init(_ text: String, _ base: Int) {
            self.text = text
            self.base = base
            self.work = text
        }

        func take(_ a: Int, _ b: Int, _ f: CF?) {
            consumed.append(NSRange(location: a, length: b - a))
            work = CardioText.blank(work, a, b)
            if var g = f {
                g.a = base + a
                g.b = base + b
                findings.append(g)
            }
        }

        /// Recognized but not read (denied, hedged, out of range): the words stay.
        func skip(_ a: Int, _ b: Int) {
            consumed.append(NSRange(location: a, length: b - a))
            work = CardioText.blank(work, a, b)
            rejected = true
        }

        /// Understood but not stored (RVSP, CI, "no MR"): the words stay and do not end the run.
        func known(_ a: Int, _ b: Int) {
            consumed.append(NSRange(location: a, length: b - a))
            work = CardioText.blank(work, a, b)
        }

        func poisoned(_ study: String, _ field: String) {
            poison.append(study + "." + field)
        }

        /// Every word and number of the piece is understood: a finding, a known term or filler. A number nothing read is not
        /// filler ("LAD 70%-80%", "PSV 130-230", "FEV1 1.8/62%" read nothing).
        var pure: Bool {
            if rejected { return false }
            let t: String = CardioText.blanked(work, CardioRx.fillerWords)
            return CardioRx.punctOnly.first(t) != nil
        }
    }

    private struct CCue {
        var study: String
        var strong: Bool
        var a: Int
        var b: Int
        var lead: String?
        var token: String
    }

    private final class CRun {
        let study: String
        let cue: CCue?
        var parses: [CParse] = []
        var extra: [CF] = []
        var masks: [NSRange] = []
        var weak: Bool
        /// The run tells of a change, an earlier study or a doubt ("EF was 55%, now 35%", "effusion resolved", "probably clear"):
        /// nothing of it is read.
        var vetoed = false
        /// Where the last piece the run read ends (-1: none).
        var end = -1
        /// Carotid: "normal" said of the study as a whole (both sides).
        var bare = false
        /// The name stood alone in its piece ("Echo", "TTE 6/26:"): the lines under it are its findings.
        var heading = false
        /// Chest X-ray: the last piece read opened with a denial ("no infiltrate").
        var denial = false

        /// The findings from the name's own words, the date apart.
        var extraReal: [CF] { extra.filter { $0.field != "date" } }

        /// The run has read a finding (the date alone is none).
        var told: Bool {
            if !extraReal.isEmpty { return true }
            for q in parses where !q.findings.isEmpty { return true }
            return false
        }

        init(_ study: String, _ cue: CCue?, weak: Bool = false) {
            self.study = study
            self.cue = cue
            self.weak = weak
        }
    }

    // MARK: Small helpers

    private static func sub(_ s: String, _ a: Int, _ b: Int) -> String {
        let n = s as NSString
        let lo = max(0, min(a, n.length))
        let hi = max(lo, min(b, n.length))
        return n.substring(with: NSRange(location: lo, length: hi - lo))
    }

    private static func head(_ s: String, _ a: Int) -> String { sub(s, 0, a) }

    private static func tail(_ s: String, _ a: Int) -> String { sub(s, a, (s as NSString).length) }

    fileprivate static func blank(_ s: String, _ a: Int, _ b: Int) -> String {
        let n = s as NSString
        guard a >= 0, b <= n.length, b > a else { return s }
        return n.replacingCharacters(in: NSRange(location: a, length: b - a), with: String(repeating: " ", count: b - a))
    }

    /// The text with every match of the pattern replaced by as many spaces.
    fileprivate static func blanked(_ s: String, _ rx: NoteRx) -> String {
        var out = s
        for m in rx.all(s).reversed() {
            out = blank(out, m.range.location, m.range.location + m.range.length)
        }
        return out
    }

    private static func end(_ r: NSRange) -> Int { r.location + r.length }

    private static func grp(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String? {
        guard i < m.numberOfRanges else { return nil }
        let r = m.range(at: i)
        guard r.location != NSNotFound else { return nil }
        return (s as NSString).substring(with: r)
    }

    private static func overlaps(_ a: Int, _ b: Int, _ list: [NSRange]) -> Bool {
        for r in list where a < end(r) && r.location < b { return true }
        return false
    }

    /// Matches in the text from an offset on, seeing what stands before it (like Python's finditer(string, pos)).
    private static func matches(_ rx: NoteRx, _ s: String, from: Int) -> [NSTextCheckingResult] {
        guard let re = rx.re else { return [] }
        let n = (s as NSString).length
        guard from <= n else { return [] }
        return re.matches(in: s, options: [.withTransparentBounds, .withoutAnchoringBounds], range: NSRange(location: from, length: n - from))
    }

    static func num(_ v: Double) -> String {
        if v == v.rounded(), Swift.abs(v) < 1_000_000 { return String(Int(v)) }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private static func negated(_ t: String, _ a: Int) -> Bool {
        let before = head(t, a)
        return CardioRx.negatedBefore.first(before) != nil || CardioRx.qOrCmpBefore.first(before) != nil
    }

    /// Denied or hedged: a negation or doubt before it, or a comparison or a question right after it.
    private static func doubted(_ t: String, _ a: Int, _ b: Int) -> Bool {
        if negated(t, a) { return true }
        return CardioRx.hedgeAfter.first(tail(t, b)) != nil
    }

    // MARK: Dates

    /// The month (nil for a year alone) and year of a date typed next to a cue, by the app's own PatientMonthYear.parse; nil when
    /// it is not one, or is in the future or before 1950 (a study that was done is not dated so).
    private static func studyDate(_ token: String, now: Date) -> PatientMonthYear? {
        guard let d = PatientMonthYear.parse(token, now: now), let y = d.year else { return nil }
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month], from: now)
        let ny = c.year ?? 2026
        let nm = c.month ?? 1
        if y < 1950 || y > ny { return nil }
        if y == ny, let m = d.month, m > nm { return nil }
        return d
    }

    // MARK: Grades

    private static func gradeOf(_ words: [String?]) -> String? {
        var best = -1
        var trivial = false
        for w in words {
            guard let word = w else { continue }
            let l = word.lowercased()
            if l.hasPrefix("triv") || l == "trace" {
                trivial = true
            } else if l.hasPrefix("mild") {
                best = max(best, 0)
            } else if l.hasPrefix("mod") {
                best = max(best, 1)
            } else if l.hasPrefix("sev") || l == "critical" {
                best = max(best, 2)
            }
        }
        if best >= 0 { return ["mild", "moderate", "severe"][best] }
        return trivial ? "trivial" : nil
    }

    private static func gradeRangeOf(_ text: String) -> String? {
        var words: [String?] = []
        for m in CardioRx.wordRx.all(text) { words.append(grp(m, 0, text)) }
        return gradeOf(words)
    }

    private static func chamberOf(_ ch: String) -> String {
        let c = ch.lowercased()
        return c.hasPrefix("lv") || c.hasPrefix("left") ? "lv" : "rv"
    }

    // MARK: Echo

    private static func parseEcho(_ p: CParse) {
        let t = p.text
        // EF first: its "LV " belongs to it.
        for m in CardioRx.efRx.all(p.work) {
            let a = m.range.location
            let b = end(m.range)
            if overlaps(a, b, p.consumed) { continue }
            let lo = Double(grp(m, 1, p.work) ?? "") ?? 0
            let hiText = grp(m, 2, p.work)
            let hi: Double? = hiText.flatMap { Double($0) }
            let pre = head(p.work, a)
            if CardioRx.cmpBefore.first(pre) != nil || doubted(t, a, b) {
                p.skip(a, b)
                continue
            }
            var inRange = lo >= 5 && lo <= 85
            if let h = hi { inRange = inRange && h >= 5 && h <= 85 && lo < h }
            if !inRange {
                p.skip(a, b)
                p.poisoned("echo", "lvef")
                continue
            }
            let value: Double = hi == nil ? lo : (lo + (hi ?? lo)) / 2.0
            // The history reader reads "EF 35%" itself (PatientNote.efRx wants the %): its words are left to it.
            let keep = CardioRx.efHistory.first(sub(p.work, a, b)) != nil
            var f = CF(study: "echo", field: "lvef", value: num(value))
            f.keepWords = keep
            p.take(a, b, f)
        }
        // Valves.
        func ownForm(_ s: String) -> Bool { CardioRx.ownForm.first(s) != nil }
        func valveFinding(_ valve: String, _ lesion: String, _ grade: String, _ own: Bool) -> CF {
            var f = CF(study: "echo", field: "valve." + valve + "." + lesion, value: grade)
            if own {
                if grade == "mild" || grade == "moderate" || grade == "severe" { f.history = [valve, lesion, grade] }
            } else {
                f.keepWords = true
            }
            return f
        }
        func addValve(_ a: Int, _ b: Int, _ valve: String, _ lesion: String, _ words: [String?], lower: Bool = false) {
            if doubted(t, a, b) {
                p.skip(a, b)
                return
            }
            let g = gradeOf(words)
            if g == "trivial" {
                if lesion == "regurgitation" {
                    p.take(a, b, valveFinding(valve, lesion, "trivial", lower || ownForm(sub(t, a, b))))
                } else {
                    p.known(a, b)
                }
                return
            }
            guard let grade = g else {
                p.skip(a, b)
                return
            }
            p.take(a, b, valveFinding(valve, lesion, grade, lower || ownForm(sub(t, a, b))))
        }
        func valveOf(_ letter: Character) -> String {
            if letter == "A" { return "aortic" }
            return letter == "M" ? "mitral" : "tricuspid"
        }
        for m in CardioRx.vWritten.all(p.work) {
            let a = m.range.location
            let b = end(m.range)
            if overlaps(a, b, p.consumed) { continue }
            let valve = (grp(m, 3, p.work) ?? "").lowercased()
            let lesion = (grp(m, 4, p.work) ?? "").lowercased() == "stenosis" ? "stenosis" : "regurgitation"
            addValve(a, b, valve, lesion, [grp(m, 1, p.work), grp(m, 2, p.work), grp(m, 5, p.work), grp(m, 6, p.work)])
        }
        for m in CardioRx.vBefore.all(p.work) {
            let a = m.range.location
            let b = end(m.range)
            if overlaps(a, b, p.consumed) { continue }
            // "mild tr", typed on a phone: behind a grade the letters are the valve's in either case. The history reader reads only
            // capitals, so the lowercase form is the echo's own.
            let typed: String = grp(m, 3, p.work) ?? ""
            let letters: String = typed.uppercased()
            let second = grp(m, 4, p.work)
            if let s = second, !((letters == "AR" || letters == "AI") && (s == "AR" || s == "AI")) {
                p.skip(a, b)
                continue
            }
            guard let first = letters.first else { continue }
            addValve(a, b, valveOf(first), letters.hasSuffix("S") ? "stenosis" : "regurgitation", [grp(m, 1, p.work), grp(m, 2, p.work)], lower: typed != letters)
        }
        for m in CardioRx.vAfter.all(p.work) {
            let a = m.range.location
            let b = end(m.range)
            if overlaps(a, b, p.consumed) { continue }
            let letters = grp(m, 1, p.work) ?? ""
            guard let first = letters.first else { continue }
            addValve(a, b, valveOf(first), letters.hasSuffix("S") ? "stenosis" : "regurgitation", [grp(m, 2, p.work), grp(m, 3, p.work)])
        }
        // Negated lesions ("no MR") and pulmonic ones are understood, never stored.
        for m in CardioRx.vNegated.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            p.known(m.range.location, end(m.range))
            // "no MR, mod MR": the lesion denied here is not read from elsewhere in the study. (The words are read from the
            // piece's own text: the working copy has just been blanked.)
            var valve: String? = nil
            var lesions: [String] = ["stenosis", "regurgitation"]
            if let letters = grp(m, 1, t), let first = letters.first {
                if first == "A" { valve = "aortic" } else if first == "M" { valve = "mitral" } else if first == "T" { valve = "tricuspid" }
                lesions = letters.hasSuffix("S") ? ["stenosis"] : ["regurgitation"]
            } else if let written = grp(m, 2, t)?.lowercased(), written != "pulmonic" {
                valve = written
                if let word = grp(m, 3, t)?.lowercased() { lesions = word == "stenosis" ? ["stenosis"] : ["regurgitation"] }
            }
            if let v = valve {
                for les in lesions { p.poisoned("echo", "valve." + v + "." + les) }
            }
        }
        // "valves nl", "no significant valve disease", "normal biventricular function": understood and not stored, and remembered:
        // beside a moderate or severe lesion, a low EF or a reduced ventricle the echo says two things.
        for m in CardioRx.valvesNormal.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            p.known(m.range.location, end(m.range))
            p.flags.insert("valves-normal")
        }
        for m in CardioRx.bivNormal.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            p.known(m.range.location, end(m.range))
            p.flags.insert("biv-normal")
        }
        for m in CardioRx.vPulm.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            p.known(m.range.location, end(m.range))
        }
        // Aorta.
        for m in CardioRx.aorta.all(p.work) {
            let a = m.range.location
            let b = end(m.range)
            if overlaps(a, b, p.consumed) { continue }
            if doubted(t, a, b) {
                p.skip(a, b)
                continue
            }
            p.take(a, b, CF(study: "echo", field: "aorta", value: "intact"))
        }
        // Chambers: every shape that fits; overlapping candidates are ambiguous and read neither.
        var cands: [(kind: String, a: Int, b: Int, m: NSTextCheckingResult)] = []
        for shape in CardioRx.echoShapes {
            for m in shape.1.all(p.work) {
                let a = m.range.location
                let b = end(m.range)
                if overlaps(a, b, p.consumed) { continue }
                cands.append((kind: shape.0, a: a, b: b, m: m))
            }
        }
        var bad = Set<Int>()
        for i in 0..<cands.count {
            for j in (i + 1)..<cands.count where cands[i].a < cands[j].b && cands[j].a < cands[i].b {
                bad.insert(i)
                bad.insert(j)
            }
        }
        for (i, c) in cands.enumerated() {
            if bad.contains(i) { continue }
            if overlaps(c.a, c.b, p.consumed) { continue }
            var ch: String? = nil
            var gradeText: String? = nil
            var gi = 1
            while gi < c.m.numberOfRanges {
                if let g = grp(c.m, gi, p.work) {
                    if CardioRx.chamberFull.first(g) != nil { ch = chamberOf(g) }
                    if CardioRx.gradeStart.first(g) != nil { gradeText = g }
                }
                gi += 1
            }
            guard let chamber = ch else { continue }
            let blocked = doubted(t, c.a, c.b) || CardioRx.pairBefore.first(head(t, c.a)) != nil || CardioRx.pairAfter.first(tail(t, c.b)) != nil
            let gradeBefore = (c.kind == "nsize" || c.kind == "dilated" || c.kind == "fnormal") && CardioRx.gradeBefore.first(head(t, c.a)) != nil
            if blocked || gradeBefore {
                p.skip(c.a, c.b)
                continue
            }
            if c.kind == "nsize" {
                p.take(c.a, c.b, CF(study: "echo", field: chamber + "Size", value: "normal"))
            } else if c.kind == "dilated" {
                p.take(c.a, c.b, CF(study: "echo", field: chamber + "Size", value: "dilated"))
            } else if c.kind == "fnormal" {
                p.take(c.a, c.b, CF(study: "echo", field: chamber, value: "normal"))
            } else {
                let g: String? = gradeText.flatMap { gradeRangeOf($0) }
                if let grade = g, grade == "mild" || grade == "moderate" || grade == "severe" {
                    p.take(c.a, c.b, CF(study: "echo", field: chamber, value: grade))
                } else {
                    p.skip(c.a, c.b)
                }
            }
        }
        for rx in CardioRx.echoKnown {
            for m in rx.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
                p.known(m.range.location, end(m.range))
            }
        }
        // An aortic dimension is understood and not stored; "aorta intact" beside it says two things and is not read.
        for m in CardioRx.aortaDim.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            p.known(m.range.location, end(m.range))
            p.poisoned("echo", "aorta")
        }
    }

    // MARK: Left heart cath

    private static func vesselID(_ v: String) -> String {
        let l = v.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        if l.hasPrefix("left main") { return "lm" }
        if l.hasPrefix("left anterior") { return "lad" }
        if l.hasPrefix("right coronary") { return "rca" }
        switch l {
        case "lmca", "lm": return "lm"
        case "lad": return "lad"
        case "lcx", "cx", "circ", "circumflex": return "lcx"
        case "rca": return "rca"
        default: return "pda"
        }
    }

    private static func parseLHC(_ p: CParse) {
        let t = p.text
        func add(_ vessel: String, _ value: Int, _ seg: Bool, _ a: Int, _ b: Int) {
            if doubted(t, a, b) {
                p.skip(a, b)
                return
            }
            if value < 0 || value > 100 {
                p.skip(a, b)
                p.poisoned("lhc", "stenosis." + vessel)
                return
            }
            var f = CF(study: "lhc", field: "stenosis." + vessel, value: String(value))
            f.segment = seg
            p.take(a, b, f)
        }
        for m in CardioRx.lhcOccA.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            add(vesselID(grp(m, 3, p.work) ?? ""), 100, grp(m, 1, p.work) != nil || grp(m, 2, p.work) != nil, m.range.location, end(m.range))
        }
        for m in CardioRx.lhcOccB.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            add(vesselID(grp(m, 3, p.work) ?? ""), 100, grp(m, 1, p.work) != nil || grp(m, 2, p.work) != nil, m.range.location, end(m.range))
        }
        for m in CardioRx.lhcPctAfter.all(p.work) {
            let a = m.range.location
            let b = end(m.range)
            if overlaps(a, b, p.consumed) { continue }
            let v = Int(grp(m, 4, p.work) ?? "") ?? -1
            if grp(m, 5, p.work) == nil && !(v >= 10 && v <= 100) { continue }
            add(vesselID(grp(m, 3, p.work) ?? ""), v, grp(m, 1, p.work) != nil || grp(m, 2, p.work) != nil, a, b)
        }
        for m in CardioRx.lhcPctBefore.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            let v = Int(grp(m, 1, p.work) ?? "") ?? -1
            add(vesselID(grp(m, 4, p.work) ?? ""), v, grp(m, 2, p.work) != nil || grp(m, 3, p.work) != nil, m.range.location, end(m.range))
        }
        for m in CardioRx.lhcDom.all(p.work) {
            let a = m.range.location
            let b = end(m.range)
            if overlaps(a, b, p.consumed) { continue }
            if doubted(t, a, b) {
                p.skip(a, b)
                continue
            }
            var d = "codominant"
            if grp(m, 1, p.work) != nil { d = "right" } else if grp(m, 2, p.work) != nil { d = "left" }
            p.take(a, b, CF(study: "lhc", field: "dominance", value: d))
        }
        // The result in a word is the app's own reading of a cath's result, with a cath word put before the piece.
        if let r = PatientLHC.readResult("lhc " + p.work) {
            let a = r.phrase.location - 4
            var b = end(r.phrase) - 4
            if let cad = r.cadWords { b = end(cad) - 4 }
            if a >= 0, !overlaps(a, b, p.consumed) {
                if doubted(t, a, b) {
                    p.skip(a, b)
                } else {
                    p.take(a, b, CF(study: "lhc", field: "result", value: r.result))
                }
            }
        }
        for (ki, rx) in CardioRx.lhcKnown.enumerated() {
            for m in rx.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
                p.known(m.range.location, end(m.range))
                // The first two known forms are disease (a branch's stenosis, three-vessel disease): "no CAD" beside them is not read.
                if ki < 2 { p.flags.insert("disease") }
            }
        }
    }

    // MARK: Right heart cath

    private static func parseRHC(_ p: CParse) {
        let t = p.text
        func put(_ field: String, _ v: Double, _ lo: Double, _ hi: Double, _ a: Int, _ b: Int) {
            if doubted(t, a, b) {
                p.skip(a, b)
                return
            }
            if v < lo || v > hi {
                p.skip(a, b)
                p.poisoned("rhc", field)
                return
            }
            p.take(a, b, CF(study: "rhc", field: field, value: num(v)))
        }
        for m in CardioRx.rhcPa.all(p.work) {
            let a = m.range.location
            let b = end(m.range)
            if overlaps(a, b, p.consumed) { continue }
            let s = Int(grp(m, 1, p.work) ?? "") ?? 0
            let d = Int(grp(m, 2, p.work) ?? "") ?? 0
            let mean: Int? = grp(m, 3, p.work).flatMap { Int($0) }
            var ok = s >= 10 && s <= 150 && d >= 0 && d <= 80 && d < s
            if let mn = mean { ok = ok && mn >= 5 && mn <= 100 && d <= mn && mn <= s }
            if doubted(t, a, b) || !ok {
                p.skip(a, b)
                if !ok {
                    for fn in ["pasp", "padp", "pam"] { p.poisoned("rhc", fn) }
                }
                continue
            }
            p.take(a, b, CF(study: "rhc", field: "pasp", value: String(s)))
            var fd = CF(study: "rhc", field: "padp", value: String(d))
            fd.a = p.base + a
            fd.b = p.base + b
            p.findings.append(fd)
            if let mn = mean {
                var fm = CF(study: "rhc", field: "pam", value: String(mn))
                fm.a = p.base + a
                fm.b = p.base + b
                p.findings.append(fm)
            }
        }
        for m in CardioRx.rhcPam.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            put("pam", Double(grp(m, 1, p.work) ?? "") ?? -1, 5, 100, m.range.location, end(m.range))
        }
        for m in CardioRx.rhcPasp.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            let v = Double(grp(m, 2, p.work) ?? "") ?? -1
            if (grp(m, 1, p.work) ?? "").lowercased() == "pasp" {
                put("pasp", v, 10, 150, m.range.location, end(m.range))
            } else {
                put("padp", v, 0, 80, m.range.location, end(m.range))
            }
        }
        for m in CardioRx.rhcPcwp.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            put("pcwp", Double(grp(m, 1, p.work) ?? "") ?? -1, 0, 50, m.range.location, end(m.range))
        }
        for m in CardioRx.rhcCo.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            put("co", Double(grp(m, 1, p.work) ?? "") ?? -1, 1, 15, m.range.location, end(m.range))
        }
        for m in CardioRx.rhcRa.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            put("ra", Double(grp(m, 1, p.work) ?? "") ?? -1, 0, 40, m.range.location, end(m.range))
        }
        for rx in CardioRx.rhcKnown {
            for m in rx.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
                p.known(m.range.location, end(m.range))
            }
        }
    }

    // MARK: PFTs

    private static func severityOf(_ w: String) -> String {
        let l = w.lowercased()
        if l.hasPrefix("mild") { return "mild" }
        return l.hasPrefix("mod") ? "moderate" : "severe"
    }

    private static func patternID(_ w: String) -> String {
        switch w.lowercased() {
        case "obstructive", "obstruction", "obs", "obstr": return "obstruction"
        case "restrictive", "restriction", "restr": return "restriction"
        case "mixed": return "mixed"
        default: return "nonspecific"
        }
    }

    private static func parsePFT(_ p: CParse) {
        let t = p.text
        func put(_ field: String, _ v: Double, _ lo: Double, _ hi: Double, _ a: Int, _ b: Int) {
            if doubted(t, a, b) {
                p.skip(a, b)
                return
            }
            if v < lo || v > hi {
                p.skip(a, b)
                p.poisoned("pft", field)
                return
            }
            p.take(a, b, CF(study: "pft", field: field, value: num(v)))
        }
        for m in CardioRx.pftRatio.all(p.work) {
            let a = m.range.location
            let b = end(m.range)
            if overlaps(a, b, p.consumed) { continue }
            let raw = grp(m, 1, p.work) ?? grp(m, 3, p.work) ?? ""
            let v = Double(raw) ?? 0
            let ok = (v >= 0.2 && v <= 1) || (v >= 20 && v <= 100)
            if doubted(t, a, b) {
                p.skip(a, b)
            } else if !ok {
                p.skip(a, b)
                p.poisoned("pft", "ratio")
            } else {
                p.take(a, b, CF(study: "pft", field: "ratio", value: num(v)))
            }
        }
        for m in CardioRx.pftVol.all(p.work) {
            let a = m.range.location
            let b = end(m.range)
            if overlaps(a, b, p.consumed) { continue }
            let nameRaw = (grp(m, 1, p.work) ?? "").lowercased().replacingOccurrences(of: " ", with: "")
            let name = nameRaw == "fev1" ? "fev1" : "fvc"
            let n1 = Double(grp(m, 2, p.work) ?? "") ?? 0
            let u1 = (grp(m, 3, p.work) ?? "").lowercased()
            let n2: Double? = grp(m, 4, p.work).flatMap { Double($0) }
            let u2 = (grp(m, 5, p.work) ?? "").lowercased()
            var liters: Double? = nil
            var pct: Double? = nil
            if u1.hasPrefix("l") {
                liters = n1
            } else if u1 == "%" {
                pct = n1
            } else if n1 <= 7 {
                // "FEV1 2.9 predicted": the predicted volume, not the measured one.
                let whole: String = (p.work as NSString).substring(with: m.range).lowercased()
                if whole.contains("pred") && n2 == nil {
                    p.skip(a, b)
                    continue
                }
                liters = n1
            } else if n1 >= 20 {
                pct = n1
            } else {
                // A bare number between 7 and 20 is neither liters nor percent predicted.
                p.skip(a, b)
                continue
            }
            if let second = n2 {
                if u2 == "%" {
                    if pct != nil {
                        p.skip(a, b)
                        continue
                    }
                    pct = second
                } else {
                    if liters != nil {
                        p.skip(a, b)
                        continue
                    }
                    liters = second
                }
            }
            if doubted(t, a, b) {
                p.skip(a, b)
                continue
            }
            let badLiters = liters != nil && !((liters ?? 0) >= 0.3 && (liters ?? 0) <= 7)
            let badPct = pct != nil && !((pct ?? 0) >= 5 && (pct ?? 0) <= 160)
            if badLiters || badPct {
                p.skip(a, b)
                if badLiters { p.poisoned("pft", name) }
                if badPct { p.poisoned("pft", name + "Pct") }
                continue
            }
            var first = true
            if let l = liters {
                p.take(a, b, CF(study: "pft", field: name, value: num(l)))
                first = false
            }
            if let c = pct {
                var f = CF(study: "pft", field: name + "Pct", value: num(c))
                if first {
                    p.take(a, b, f)
                } else {
                    f.a = p.base + a
                    f.b = p.base + b
                    p.findings.append(f)
                }
            }
        }
        for m in CardioRx.pftTlc.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            put("tlcPct", Double(grp(m, 1, p.work) ?? "") ?? -1, 5, 160, m.range.location, end(m.range))
        }
        for m in CardioRx.pftDlco.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
            put("dlcoPct", Double(grp(m, 1, p.work) ?? "") ?? -1, 5, 160, m.range.location, end(m.range))
        }
        for m in CardioRx.pftPattern.all(p.work) {
            let a = m.range.location
            let b = end(m.range)
            if overlaps(a, b, p.consumed) { continue }
            if doubted(t, a, b) {
                p.skip(a, b)
                continue
            }
            let before = grp(m, 1, p.work)
            let after = grp(m, 3, p.work)
            // A grade after the pattern may be the next finding's ("obstruction sev DLCO 30%"): not read.
            if after != nil {
                p.skip(a, b)
                continue
            }
            p.take(a, b, CF(study: "pft", field: "pattern", value: patternID(grp(m, 2, p.work) ?? "")))
            if let sev = before {
                var f = CF(study: "pft", field: "severity", value: severityOf(sev))
                f.a = p.base + a
                f.b = p.base + b
                p.findings.append(f)
            }
        }
        for rx in CardioRx.pftKnown {
            for m in rx.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
                p.known(m.range.location, end(m.range))
            }
        }
    }

    // MARK: Chest X-ray

    private static func sideID(_ w: String) -> String {
        switch w.lowercased() {
        case "left", "l": return "left"
        case "right", "r": return "right"
        case "": return "-"
        default: return "bilateral"
        }
    }

    private static func sizeID(_ w: String) -> String {
        switch w.lowercased() {
        case "small", "sm": return "small"
        case "moderate", "mod": return "moderate"
        case "large", "lg": return "large"
        default: return "-"
        }
    }

    private struct EffCandidate {
        let first: Bool
        let m: NSTextCheckingResult
    }

    private static func parseCXR(_ p: CParse) {
        let t = p.text
        var cands: [EffCandidate] = []
        for m in CardioRx.cxrEff1.all(p.work) { cands.append(EffCandidate(first: true, m: m)) }
        for m in CardioRx.cxrEff2.all(p.work) { cands.append(EffCandidate(first: false, m: m)) }
        cands.sort { (x: EffCandidate, y: EffCandidate) -> Bool in
            if x.m.range.location != y.m.range.location { return x.m.range.location < y.m.range.location }
            return x.m.range.length > y.m.range.length
        }
        var taken: [NSRange] = []
        for c in cands {
            let a = c.m.range.location
            let b = end(c.m.range)
            if overlaps(a, b, taken) || overlaps(a, b, p.consumed) { continue }
            taken.append(c.m.range)
            let g1 = grp(c.m, 1, p.work) ?? ""
            let g2 = grp(c.m, 2, p.work) ?? ""
            let size = c.first ? g1 : g2
            let side = c.first ? g2 : g1
            if CardioRx.effBadBefore.first(head(t, a)) != nil || doubted(t, a, b) {
                p.skip(a, b)
                continue
            }
            p.take(a, b, CF(study: "cxr", field: "effusion", value: sideID(side) + "," + sizeID(size)))
        }
        // What is left, when it names a radiographic finding and says nothing normal or denied, goes to the findings line as typed.
        var marked = p.work
        for m in CardioRx.fillerWords.all(p.work).reversed() {
            marked = replaceWithBars(marked, m.range.location, end(m.range))
        }
        let trimSet = CharacterSet(charactersIn: " -–.?/")
        let markedNS = marked as NSString
        for m in CardioRx.cxrSegment.all(marked) {
            var a = m.range.location
            var b = end(m.range)
            while a < b, let u = UnicodeScalar(markedNS.character(at: a)), trimSet.contains(u) { a += 1 }
            while b > a, let u = UnicodeScalar(markedNS.character(at: b - 1)), trimSet.contains(u) { b -= 1 }
            if b <= a { continue }
            let words = markedNS.substring(with: NSRange(location: a, length: b - a)).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let s = words.joined(separator: " ")
            if CardioRx.letterRx.first(s) == nil { continue }
            if CardioRx.cxrVocab.first(s) == nil || s.count > 60 || CardioRx.cxrNormal.first(s) != nil || CardioRx.cxrNegStart.first(s) != nil { continue }
            // Every word of a description must be a radiographic word: a lab, a drug, a date or another test's name and it is not stored.
            if CardioRx.cxrPure.first(s) == nil { continue }
            if doubted(t, a, b) {
                p.skip(a, b)
                continue
            }
            p.take(a, b, CF(study: "cxr", field: "findings", value: s))
        }
        for m in CardioRx.cxrNormal.all(p.work) {
            let a = m.range.location
            let b = end(m.range)
            if overlaps(a, b, p.consumed) { continue }
            if doubted(t, a, b) {
                p.skip(a, b)
                continue
            }
            p.take(a, b, CF(study: "cxr", field: "result", value: "normal"))
        }
        cxrAsTyped(p)
    }

    /// A piece that is not wholly understood (a qualifier, a second side, a size with its unit, "clear except ...") is not a
    /// structured result: the whole piece goes to the findings line exactly as typed, when it speaks of the film at all.
    private static func cxrAsTyped(_ p: CParse) {
        var structured = 0
        var freeCount = 0
        for f in p.findings {
            if f.field == "findings" {
                freeCount += 1
            } else {
                structured += 1
            }
        }
        let strip = CharacterSet(charactersIn: " -–.?/:+&")
        // The date's empty brackets are no part of the description ("CXR (6/26): RLL infiltrate").
        var unbracketed: String = p.text
        for m in CardioRx.emptyParens.all(p.text).reversed() { unbracketed = blank(unbracketed, m.range.location, end(m.range)) }
        let words: [String] = unbracketed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var s: String = words.joined(separator: " ").trimmingCharacters(in: strip)
        // Words before the finding that are not part of it ("shows", "with", "(portable)") are not stored with it.
        if let lm = CardioRx.cxrLeadin.first(s) {
            s = sub(s, end(lm.range), (s as NSString).length).trimmingCharacters(in: strip)
        }
        if p.pure && CardioRx.runVeto.first(p.text) == nil {
            // One description told with filler between its parts ("blunting of the right CP angle", "RLL opacity c/w pneumonia")
            // is one finding, kept as typed.
            if freeCount > 1 && structured == 0 && s.count <= 60 && CardioRx.cxrPure.first(s) != nil {
                var a0 = Int.max
                var b0 = 0
                for f in p.findings {
                    a0 = min(a0, f.a)
                    b0 = max(b0, f.b)
                }
                var f = CF(study: "cxr", field: "findings", value: s)
                f.a = a0
                f.b = b0
                p.findings = [f]
            }
            return
        }
        // A plain denial ("no effusion", "without pneumothorax") is understood and stores nothing; the run goes on.
        if structured == 0 && freeCount == 0 && CardioRx.cxrDenial.first(s) != nil && CardioRx.cxrDenialBut.first(s) == nil {
            p.findings = []
            p.consumed = [NSRange(location: 0, length: (p.text as NSString).length)]
            p.work = String(repeating: " ", count: (p.text as NSString).length)
            p.rejected = false
            return
        }
        let ns = p.text as NSString
        let edge = CharacterSet(charactersIn: " \t-–.?/:+&")
        var lead = 0
        var tail = ns.length
        while lead < tail, let u = UnicodeScalar(ns.character(at: lead)), edge.contains(u) { lead += 1 }
        while tail > lead, let u = UnicodeScalar(ns.character(at: tail - 1)), edge.contains(u) { tail -= 1 }
        p.findings = []
        p.consumed = []
        p.work = p.text
        p.rejected = false
        var ok: Bool = CardioRx.letterRx.first(s) != nil && s.count <= 60
        if ok && (CardioRx.cxrNegStart.first(s) != nil || CardioRx.cxrExam.first(s) != nil || CardioRx.cxrWo.first(s) != nil) { ok = false }
        // Another test's result in the piece ("EKG nl", "labs nl"): not the film's. Neither is a purpose, a denial, an exam or
        // a condition ("to rule out pneumonia", "heart failure", "clear on exam").
        if ok && (CardioRx.cxrOther.first(s) != nil || CardioRx.cxrSkip.first(s) != nil) { ok = false }
        // Only a piece that names a radiographic finding, in radiographic words alone, is kept.
        if ok && (CardioRx.cxrVocab.first(s) == nil || CardioRx.cxrPure.first(s) == nil) { ok = false }
        // A size word left over from the effusion ("small + cardiomegaly") is not a finding.
        if ok && CardioRx.cxrOrphan.first(s) != nil { ok = false }
        if ok && tail > lead {
            p.take(lead, tail, CF(study: "cxr", field: "findings", value: s))
        } else {
            p.rejected = true
        }
    }

    private static func replaceWithBars(_ s: String, _ a: Int, _ b: Int) -> String {
        let n = s as NSString
        guard a >= 0, b <= n.length, b > a else { return s }
        return n.replacingCharacters(in: NSRange(location: a, length: b - a), with: String(repeating: "|", count: b - a))
    }

    // MARK: Carotid and radial: per side, in the order written

    private static func sidesOf(_ m: NSTextCheckingResult, _ s: String) -> [String] {
        if grp(m, 1, s) != nil { return ["right", "left"] }
        if grp(m, 2, s) != nil { return ["right"] }
        if grp(m, 3, s) != nil { return ["left"] }
        return []
    }

    /// The category id of a stenosis match (groups 1...6 of carSten); nil when it is not one the field holds.
    private static func stenID(_ m: NSTextCheckingResult, _ s: String) -> String? {
        if let word = grp(m, 6, s) {
            let w = word.lowercased()
            if w.hasPrefix("near") || w.hasPrefix("string") { return "near" }
            if w.hasPrefix("occlu") { return "occluded" }
            return "normal"
        }
        func cat(_ n: Int) -> String? {
            if n > 100 { return nil }
            if n < 50 { return "lt50" }
            if n < 70 { return "50-69" }
            if n < 100 { return "ge70" }
            return "occluded"
        }
        if let cmp = grp(m, 1, s) {
            let n = Int(grp(m, 2, s) ?? "") ?? -1
            if cmp == "<" && n >= 0 && n <= 50 { return "lt50" }
            if (cmp == ">" || cmp == "≥") && n >= 70 && n <= 99 { return "ge70" }
            return nil
        }
        if let lo = grp(m, 3, s), let hi = grp(m, 4, s) {
            let a = Int(lo) ?? 0
            let b = Int(hi) ?? 0
            if a >= b { return nil }
            let ca = cat(a)
            let cb = cat(b)
            return ca == cb ? ca : nil
        }
        if let pct = grp(m, 5, s) { return cat(Int(pct) ?? 0) }
        return nil
    }

    private struct SideEvent {
        let pos: Int
        let neg: Int
        let kind: String
        let m: NSTextCheckingResult
    }

    private static func walkSides(_ p: CParse, _ study: String, _ specs: [(String, NoteRx)], inherit: String? = nil, _ handle: (String, NSTextCheckingResult, String) -> (String, String)?) {
        let t = p.text
        let snapshot = p.work
        var ev: [SideEvent] = []
        for spec in specs {
            for m in spec.1.all(p.work) where !overlaps(m.range.location, end(m.range), p.consumed) {
                ev.append(SideEvent(pos: m.range.location, neg: -m.range.length, kind: spec.0, m: m))
            }
        }
        ev.sort { (x: SideEvent, y: SideEvent) -> Bool in
            if x.pos != y.pos { return x.pos < y.pos }
            return x.neg < y.neg
        }
        // One side to a piece: with two side words in one piece ("r ica 40% l ica 60% vertebral reversed") what belongs to which
        // cannot be told, and the piece is not read.
        var sideWords = 0
        for e in ev where e.kind == "side" { sideWords += 1 }
        if sideWords > 1 {
            p.rejected = true
            return
        }
        var cur: (sides: [String], span: NSRange?)? = nil
        var usedSides: [NSRange] = []
        var lastEnd = -1
        var ctxEnd = -1
        var pending: [(a: Int, b: Int, field: String, value: String)] = []
        // "R radial 2.6 mm, calcified": a piece that names no side goes on with the one side the study has named so far.
        if let inh = inherit, sideWords == 0 {
            cur = (sides: [inh], span: nil)
            ctxEnd = 0
        }
        for e in ev {
            let a = e.m.range.location
            let b = end(e.m.range)
            if a < lastEnd { continue }
            if e.kind == "side" {
                var sidesNow = sidesOf(e.m, snapshot)
                // "R and L 60%": the sides told together.
                if let c = cur, let sp = c.span, ctxEnd == end(sp), CardioRx.sideCombine.first(sub(t, end(sp), a)) != nil {
                    sidesNow = ["right", "left"].filter { sidesNow.contains($0) || c.sides.contains($0) }
                    usedSides.append(sp)
                }
                cur = (sides: sidesNow, span: e.m.range)
                ctxEnd = b
                lastEnd = b
                continue
            }
            guard let res = handle(e.kind, e.m, snapshot) else {
                p.skip(a, b)
                lastEnd = b
                continue
            }
            guard let c = cur else {
                pending.append((a: a, b: b, field: res.0, value: res.1))
                lastEnd = b
                continue
            }
            // "normal" said without a side is not the one side's.
            if c.span == nil && res.0 == "stenosis" && res.1 == "normal" {
                p.skip(a, b)
                lastEnd = b
                continue
            }
            if CardioRx.sideGap.first(sub(t, ctxEnd, a)) == nil {
                p.skip(a, b)
                lastEnd = b
                continue
            }
            ctxEnd = b
            // A vertebral flow needs its own side: after another finding of that side ("R ICA 70% vertebral reversed") it may be
            // the other side's, and is not read.
            var sideUsed = true
            if let sp = c.span { sideUsed = usedSides.contains(where: { NSEqualRanges($0, sp) }) }
            if res.0 == "vertebral" && sideUsed {
                p.skip(a, b)
                lastEnd = b
                continue
            }
            if let sp = c.span { usedSides.append(sp) }
            // With both sides named together only the stenosis is read.
            let single = res.0 != "stenosis"
            if single && c.sides.count > 1 {
                p.skip(a, b)
                lastEnd = b
                continue
            }
            var first = true
            for s in c.sides {
                var f = CF(study: study, field: s + "." + res.0, value: res.1)
                if first {
                    p.take(a, b, f)
                    first = false
                } else {
                    f.a = p.base + a
                    f.b = p.base + b
                    p.findings.append(f)
                }
            }
            lastEnd = b
        }
        // A finding told before its side ("70% L ICA"): only when a side follows with nothing between but a word or two.
        for item in pending {
            let nxt = matches(CardioRx.sideToken, p.work, from: item.b).filter { !overlaps($0.range.location, end($0.range), p.consumed) }
            guard let sm = nxt.first else {
                p.skip(item.a, item.b)
                continue
            }
            let gap = sub(t, item.b, sm.range.location)
            let single = item.field == "psv" || item.field == "edv" || item.field == "diameter"
            if CardioRx.pendingGap.first(gap) == nil || single {
                p.skip(item.a, item.b)
                continue
            }
            let pendingSides: [String] = sidesOf(sm, snapshot)
            // With both sides named together only the stenosis is read ("vertebral reversed bilat" reads nothing).
            if item.field != "stenosis" && pendingSides.count > 1 {
                p.skip(item.a, item.b)
                continue
            }
            usedSides.append(sm.range)
            var first = true
            for s in pendingSides {
                var f = CF(study: study, field: s + "." + item.field, value: item.value)
                if first {
                    p.take(item.a, item.b, f)
                    first = false
                } else {
                    f.a = p.base + item.a
                    f.b = p.base + item.b
                    p.findings.append(f)
                }
            }
        }
        for r in usedSides where !overlaps(r.location, end(r), p.consumed) {
            p.consumed.append(r)
            p.aux.append(r)
            p.work = blank(p.work, r.location, end(r))
        }
    }

    private static func parseCarotid(_ p: CParse, adjacentNormal: Bool, inherit: String? = nil) {
        let t = p.text
        // "carotid US normal": both sides, only when the piece names no side of its own ("normal bilaterally" is read by its side).
        if adjacentNormal, CardioRx.sideToken.first(p.work) == nil, let m = CardioRx.carBareNormal.first(p.work) {
            let word = (p.work as NSString).substring(with: m.range)
            var lead = 0
            for ch in word {
                if ch == " " || ch == ":" || ch == "-" || ch == "–" { lead += 1 } else { break }
            }
            let a = m.range.location + lead
            let b = end(m.range)
            if !doubted(t, a, b) {
                var i = 0
                for s in ["right", "left"] {
                    var f = CF(study: "carotid", field: s + ".stenosis", value: "normal")
                    if i == 0 {
                        p.take(a, b, f)
                    } else {
                        f.a = p.base + a
                        f.b = p.base + b
                        p.findings.append(f)
                    }
                    i += 1
                }
            }
        }
        let specs: [(String, NoteRx)] = [("side", CardioRx.sideToken), ("sten", CardioRx.carSten), ("vert", CardioRx.carVert), ("vel", CardioRx.carVel)]
        walkSides(p, "carotid", specs, inherit: inherit) { (kind: String, m: NSTextCheckingResult, w: String) -> (String, String)? in
            let a = m.range.location
            let b = end(m.range)
            if kind == "sten" {
                guard let sid = stenID(m, w) else { return nil }
                let isNo = (grp(m, 6, w) ?? "").lowercased().hasPrefix("no")
                if doubted(t, a, b) && !isNo { return nil }
                return ("stenosis", sid)
            }
            if kind == "vert" {
                let word = (grp(m, 1, w) ?? grp(m, 2, w) ?? "").lowercased()
                if doubted(t, a, b) { return nil }
                var value = "partial"
                if word == "antegrade" { value = "antegrade" } else if word == "retrograde" || word == "reversed" { value = "reversed" } else if word == "absent" { value = "absent" }
                return ("vertebral", value)
            }
            let name = (grp(m, 1, w) ?? "").lowercased()
            let v = Int(grp(m, 2, w) ?? "") ?? -1
            let lo = name == "psv" ? 20 : 0
            let hi = name == "psv" ? 700 : 300
            if v < lo || v > hi {
                p.poisoned("carotid", "right." + name)
                p.poisoned("carotid", "left." + name)
                return nil
            }
            return (name, String(v))
        }
        for w in CardioRx.arteryWords.all(p.work) where !p.findings.isEmpty {
            p.consumed.append(w.range)
            p.aux.append(w.range)
            p.work = blank(p.work, w.range.location, end(w.range))
        }
    }

    private static func parseRadial(_ p: CParse, inherit: String? = nil) {
        let t = p.text
        for m in CardioRx.radHarvest.all(p.work) {
            let a = m.range.location
            let b = end(m.range)
            if overlaps(a, b, p.consumed) { continue }
            if let side = grp(m, 1, p.work) {
                p.take(a, b, CF(study: "radial", field: "harvest", value: side.lowercased()))
            } else {
                p.take(a, b, CF(study: "radial", field: "harvest", value: "none"))
            }
        }
        let specs: [(String, NoteRx)] = [("side", CardioRx.sideToken), ("diam", CardioRx.radDiam), ("calc", CardioRx.radCalc), ("ulnar", CardioRx.radUlnar)]
        walkSides(p, "radial", specs, inherit: inherit) { (kind: String, m: NSTextCheckingResult, w: String) -> (String, String)? in
            let a = m.range.location
            let b = end(m.range)
            if kind == "diam" {
                let v = Double(grp(m, 1, w) ?? "") ?? -1
                if v < 1 || v > 6 {
                    p.poisoned("radial", "right.diameter")
                    p.poisoned("radial", "left.diameter")
                    return nil
                }
                if doubted(t, a, b) { return nil }
                return ("diameter", num(v))
            }
            if kind == "calc" {
                let word = (grp(m, 1, w) ?? "").lowercased()
                let value = word.hasPrefix("no") ? "false" : "true"
                if value == "true" && doubted(t, a, b) { return nil }
                return ("calcified", value)
            }
            if doubted(t, a, b) { return nil }
            return ("ulnar", (grp(m, 1, w) ?? grp(m, 2, w) ?? "").lowercased())
        }
        for w in CardioRx.arteryWords.all(p.work) where !p.findings.isEmpty {
            p.consumed.append(w.range)
            p.aux.append(w.range)
            p.work = blank(p.work, w.range.location, end(w.range))
        }
    }

    // MARK: Runs

    /// The one side a carotid or radial run has named so far, if it named exactly one.
    private static func oneSide(_ run: CRun) -> String? {
        if run.study != "carotid" && run.study != "radial" { return nil }
        var sides = Set<String>()
        for q in run.parses {
            for f in q.findings {
                let head: String = f.field.components(separatedBy: ".").first ?? ""
                if head == "right" || head == "left" { sides.insert(head) }
            }
        }
        return sides.count == 1 ? sides.first : nil
    }

    private static func runParse(_ study: String, _ s: String, _ base: Int, adjacent: Bool = false, inherit: String? = nil) -> CParse {
        let p = CParse(s, base)
        // "PFTs 6/26 - WNL": the statement right after the bare name is said of the study.
        if study == "pft" && adjacent, let am = CardioRx.pftNormalAfter.first(s) {
            let g = am.range(at: 1)
            p.take(g.location, end(g), CF(study: "pft", field: "pattern", value: "normal"))
        }
        switch study {
        case "echo": parseEcho(p)
        case "lhc": parseLHC(p)
        case "rhc": parseRHC(p)
        case "pft": parsePFT(p)
        case "cxr": parseCXR(p)
        case "carotid": parseCarotid(p, adjacentNormal: adjacent, inherit: inherit)
        default: parseRadial(p, inherit: inherit)
        }
        // A number given as a bound ("EF 55+", "PCWP 18+", "EF 35-") is not a value.
        if CardioRx.boundMark.first(s) != nil { p.rejected = true }
        return p
    }

    private static let hasDate: Set<String> = ["echo", "lhc", "rhc", "pft", "carotid", "radial"]

    private static func resolveCues(_ text: String) -> [CCue] {
        let list: [(String, Bool, NoteRx)] = [
            ("echo", true, CardioRx.cueEcho), ("lhc", true, CardioRx.cueLhc), ("lhc", false, CardioRx.cueCath), ("rhc", true, CardioRx.cueRhc),
            // The bare word "carotids" is the neck exam ("carotids nl, no bruit"), never the ultrasound.
            ("pft", true, CardioRx.cuePft), ("cxr", true, CardioRx.cueCxr), ("carotid", true, CardioRx.cueCarotid),
            ("radial", true, CardioRx.cueRadial),
        ]
        var found: [CCue] = []
        for item in list {
            for m in item.2.all(text) {
                var lead: String? = nil
                if item.0 == "pft" || item.0 == "cxr" { lead = grp(m, 1, text) }
                found.append(CCue(study: item.0, strong: item.1, a: m.range.location, b: end(m.range), lead: lead, token: (text as NSString).substring(with: m.range)))
            }
        }
        found.sort { (x: CCue, y: CCue) -> Bool in
            if x.a != y.a { return x.a < y.a }
            return (x.b - x.a) > (y.b - y.a)
        }
        var out: [CCue] = []
        for c in found {
            var clash = false
            for o in out where c.a < o.b && o.a < c.b { clash = true }
            if !clash { out.append(c) }
        }
        return out
    }

    private static func sentences(_ text: String) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        var a = 0
        for m in CardioRx.sentBreak.all(text) {
            out.append((a, m.range.location))
            a = end(m.range)
        }
        out.append((a, (text as NSString).length))
        return out
    }

    /// (start, end, soft): soft when the piece follows a comma (it continues what came before); a semicolon or the sentence's
    /// start is a new statement.
    private static func pieces(_ text: String, _ a: Int, _ b: Int) -> [(Int, Int, Bool)] {
        var out: [(Int, Int, Bool)] = []
        let ns = text as NSString
        var s = a
        var soft = false
        var i = a
        while i < b {
            let c = ns.character(at: i)
            if c == 44 || c == 59 {
                // "1,5 L": a decimal comma stays inside its number (and the number is then not read: see CParse.pure).
                var decimal = false
                if c == 44 && i > 0 && i < b - 1 {
                    let x = ns.character(at: i - 1)
                    let y = ns.character(at: i + 1)
                    decimal = x >= 48 && x <= 57 && y >= 48 && y <= 57
                }
                if !decimal {
                    out.append((s, i, soft))
                    s = i + 1
                    soft = c == 44
                }
            } else if (c == 45 || c == 0x2013 || c == 124 || c == 47) && i > a && i < b - 1 && ns.character(at: i - 1) == 32 && ns.character(at: i + 1) == 32 {
                // "TTE EF 55% - CXR clear - PFTs nl": a dash, a slash or a bar with a space on each side separates statements, as a
                // semicolon does. A value after it belongs to the name before it ("LAD - 70%", "30 - 35%"); "FEV1 / FVC" is one name.
                var k = i + 1
                while k < b - 1 && ns.character(at: k) == 32 { k += 1 }
                let nx = ns.character(at: k)
                let value: Bool = (nx >= 48 && nx <= 57) || nx == 60 || nx == 62 || nx == 0x2264 || nx == 0x2265
                let ratio: Bool = c == 47 && CardioRx.noSplitBefore.first(sub(text, s, i)) != nil
                // "Dec 2026 - TTE EF 35%", "Testing - TTE ...": a date or a heading before the dash stays with the name after it.
                let lead: String = sub(text, s, i)
                let heading: Bool = !lead.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && CardioRx.beforeOk.first(lead) != nil
                if !value && !ratio && !heading {
                    out.append((s, i, soft))
                    s = i + 1
                    soft = false
                }
            }
            i += 1
        }
        out.append((s, b, soft))
        return out
    }

    private static let gatingFields: [String: [String]] = ["lhc": ["stenosis.", "dominance", "result"], "carotid": [".stenosis", ".vertebral", ".psv", ".edv"]]

    private static func gating(_ run: CRun, _ fs: [CF]) -> Bool {
        guard let keys = gatingFields[run.study] else { return true }
        for f in fs where f.field != "date" {
            for k in keys where f.field.contains(k) { return true }
        }
        return false
    }

    /// The findings read from the text and the stretches to mask. `page`: the study of the page the line is typed on (no cue needed).
    private static func readRuns(_ text: String, page: CardioStudy?, now: Date) -> (findings: [CF], masks: [NSRange]) {
        let cues = resolveCues(text)
        var runs: [CRun] = []
        var ndMasks: [NSRange] = []
        let textNS = text as NSString
        var active: CRun? = nil
        // The last line or sentence before this one that was not empty.
        var above = ""
        for sentence in sentences(text) {
            // A study told in short sentences ("Echo 6/26: EF 55%. Mild MR.") goes on over the full stop while each statement is
            // wholly understood; a name alone on its line ("Echo", "TTE 6/26:") heads the lines under it. Anything else ends at
            // the sentence.
            var carry: CRun? = nil
            if let act = active, sentence.0 > 0 {
                let fullStop: Bool = textNS.character(at: sentence.0 - 1) == 46
                if act.heading || (fullStop && act.told) { carry = act }
            }
            active = carry
            // A chest X-ray carried over a full stop takes only "normal" and denials from the next sentence: a finding there
            // ("Trace edema.", "Mass.") may be the exam's or another test's, and the film is then not read.
            var strictFilm: CRun? = nil
            if let c = carry, c.study == "cxr", !c.heading { strictFilm = c }
            if let pg = page {
                let r = CRun(pg.rawValue, nil)
                runs.append(r)
                active = r
            }
            // A line under a label that is not a neutral one ("Pending:", "Mother:", "Prior:"), or under a line that names another
            // person, is not read, and a name alone there heads nothing.
            let beforeThis: String = above
            let thisLine: String = sub(text, sentence.0, sentence.1)
            if !thisLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { above = thisLine }
            let labelled: Bool = (CardioRx.labelLine.first(beforeThis) != nil && CardioRx.beforeOk.first(beforeThis) == nil) || CardioRx.otherPerson.first(beforeThis) != nil
            var prev: (Int, Int)? = nil
            for piece in pieces(text, sentence.0, sentence.1) {
                let pa = piece.0
                let pb = piece.1
                let soft = piece.2
                let last: (Int, Int)? = prev
                prev = (pa, pb)
                let pc = cues.filter { $0.a >= pa && $0.a < pb }
                if pc.isEmpty {
                    if let act = active {
                        let pieceText: String = sub(text, pa, pb)
                        // "PFTs 6/26 - WNL", "Carotid US - normal": the statement right after a bare name is said of the study.
                        let fresh: Bool = act.heading && !act.told
                        let p = runParse(act.study, pieceText, pa, adjacent: fresh, inherit: oneSide(act))
                        let makeBare: Bool = fresh && act.study == "carotid" && CardioRx.carBareNormal.first(pieceText) != nil && CardioRx.sideToken.first(pieceText) == nil
                        let veto: NSTextCheckingResult? = CardioRx.runVeto.first(pieceText)
                        // Another day in a statement after the name's own ("TTE 2019 EF 35%, mod MR today") tells two studies as one.
                        let shift: Bool = CardioRx.timeShift.first(pieceText) != nil
                        if p.pure && veto == nil && !shift {
                            act.parses.append(p)
                            act.end = pb
                            // "no stenosis, L 70%": a study called normal as a whole and then given a finding says two things.
                            if act.bare && !p.findings.isEmpty { act.vetoed = true }
                            if makeBare { act.bare = true }
                            // "no infiltrate, effusion, or pneumothorax": after a denial the next item of the list may be denied
                            // too, and a finding there cannot be told from one: the film is not read.
                            if act.study == "cxr" {
                                var abnormal = false
                                for f in p.findings where f.field == "effusion" || f.field == "findings" { abnormal = true }
                                if let sf = strictFilm, sf === act, abnormal { act.vetoed = true }
                                if act.denial && abnormal { act.vetoed = true }
                                act.denial = CardioRx.cxrDenialOpen.first(pieceText) != nil
                            }
                        } else {
                            // The piece that ends the run takes the whole run with it when it qualifies what was read: it opens
                            // with a word of change or doubt ("resolved on repeat", "now 35%"), speaks of one beside a number or a
                            // grade, or gives a second value for a field the run already read ("2026 EF 30%", "LAD 50% post PCI").
                            // After a comma the piece continues the study: any word of change or doubt, a number, a grade or a size
                            // in it means the study is not read, unless the piece opens with another topic's name ("labs nl",
                            // "EKG NSR", "K 4.1", "HTN"). (After a semicolon or a full stop only its opening counts: below.)
                            let other: Bool = CardioRx.otherTopic.first(pieceText) != nil
                            let bears: Bool = CardioRx.vetoBears.first(pieceText) != nil
                            // So does a piece that says where the finding before it was seen ("seen on CT", "per report").
                            let attributed: Bool = CardioRx.attributed.first(pieceText) != nil
                            if soft && (veto != nil || shift || attributed || (bears && !other)) { act.vetoed = true }
                            var have = Set<String>()
                            for q in act.parses { for f in q.findings { have.insert(f.key) } }
                            for f in act.extra { have.insert(f.key) }
                            for f in p.findings where have.contains(f.key) { act.vetoed = true }
                            active = nil
                        }
                    }
                    continue
                }
                // Two study names in one piece ("echo and CXR nl", "LHC and RHC: RA 8", "RHC: PASP 45 by echo", "CXR nl PFT ..."):
                // what belongs to which cannot be told, and the piece is not read.
                if pc.count > 1 {
                    if let act = active, soft { act.vetoed = true }
                    active = nil
                    continue
                }
                for (i, cue) in pc.enumerated() {
                    let prevEnd = i == 0 ? pa : pc[i - 1].b
                    let before = sub(text, prevEnd, cue.a)
                    let afterEnd = i + 1 < pc.count ? pc[i + 1].a : pb
                    let after = sub(text, cue.b, afterEnd)
                    var leadParse: (parse: CParse, span: NSRange)? = nil
                    if i == 0 && !before.trimmingCharacters(in: .whitespaces).isEmpty {
                        if let lm = CardioRx.leadIn.first(before) {
                            let lp = runParse(cue.study, sub(before, 0, lm.range.location), prevEnd)
                            if lp.pure && !lp.findings.isEmpty {
                                leadParse = (parse: lp, span: NSRange(location: prevEnd + lm.range.location, length: lm.range.length))
                                // "LAD 90%, RCA 40% on LHC": the list began before this piece, and reading its last item alone
                                // would tell half of it: nothing is read.
                                if soft, let l = last, !runParse(cue.study, sub(text, l.0, l.1), l.0).findings.isEmpty { leadParse = nil }
                            }
                        } else if let act = active {
                            let p = runParse(act.study, before, prevEnd)
                            if p.pure { act.parses.append(p) }
                        }
                    }
                    // What stands before the name must be nothing, a heading or a neutral word, the study's date, or a finding told
                    // first ("EF 35% on echo"). Anything else ("prior echo", "donor echo", "mother's echo", "Plan: cath",
                    // "post-bypass TEE", "cabg 2018 tte") and the name is no cue: the piece is not read, and it ends any run.
                    if leadParse == nil && CardioRx.beforeOk.first(before) == nil {
                        // "CXR: cardiomegaly, seen on echo": the finding before is said to be another study's.
                        if let act = active, soft, CardioRx.attribBefore.first(before) != nil { act.vetoed = true }
                        active = nil
                        continue
                    }
                    if labelled {
                        active = nil
                        continue
                    }
                    // Another person named earlier in the sentence ("FHx: mother HF, TTE EF 25%"): the study may be theirs.
                    if CardioRx.otherPerson.first(sub(text, sentence.0, cue.a)) != nil {
                        active = nil
                        continue
                    }
                    // "for TEE", "undergoing LHC": the planned procedure, which the procedure reader reads: no cue.
                    if CardioRx.plannedBefore.first(before) != nil { continue }
                    let nb = CardioRx.notDoneBefore.first(before)
                    let na = CardioRx.notDoneAfter.first(after)
                    if nb != nil || na != nil {
                        // LHC, RHC and TEE are also procedures' names: those words are left to the procedure reader.
                        if !(cue.study == "lhc" || cue.study == "rhc" || cue.token == "TEE") {
                            let from = nb.map { prevEnd + $0.range.location } ?? cue.a
                            let to = cue.b + (na.map { end($0.range) } ?? 0)
                            ndMasks.append(NSRange(location: from, length: to - from))
                        }
                        active = nil
                        continue
                    }
                    let run = CRun(cue.study, cue, weak: !cue.strong)
                    runs.append(run)
                    if let lp = leadParse {
                        run.parses.append(lp.parse)
                        run.masks.append(lp.span)
                    }
                    // The study's own date: right after the cue, else right before it.
                    var body = after
                    // A date right after the cue is the study's, whether or not it is kept (a date in the future, or a study that
                    // holds no date): its digits are never a finding's.
                    let dm0: NSTextCheckingResult? = CardioRx.dateAfter.first(after)
                    if let dmx = dm0 {
                        let g0 = dmx.range(at: 1)
                        body = blank(after, g0.location, end(g0))
                    }
                    do {
                        var date: PatientMonthYear? = nil
                        var da = 0
                        var db = 0
                        var dbase = 0
                        if let dm = dm0 {
                            let g = dm.range(at: 1)
                            date = studyDateRaw((after as NSString).substring(with: g), now)
                            da = g.location
                            db = end(g)
                            dbase = cue.b
                        }
                        if date == nil, let dm2 = CardioRx.dateBefore.first(before) {
                            let g = dm2.range(at: 1)
                            if let d2 = studyDateRaw((before as NSString).substring(with: g), now) {
                                date = d2
                                da = g.location
                                db = end(g)
                                dbase = prevEnd
                            }
                        }
                        if let d = date, let ok = studyDate(d.text, now: now) {
                            // (The chest X-ray holds no date: its date is judged and not stored.)
                            if hasDate.contains(cue.study) {
                                var f = CF(study: cue.study, field: "date", value: ok.text)
                                f.a = dbase + da
                                f.b = dbase + db
                                run.extra.append(f)
                            }
                            if dbase == cue.b { body = blank(after, da, db) }
                        } else if dm0 != nil || date != nil {
                            // A date beside the name that is in the future or cannot be a month and year: the study is not read.
                            run.vetoed = true
                        }
                    }
                    let adjacent = cue.study == "carotid" && CardioRx.carBareNormal.first(body) != nil
                    let p = runParse(cue.study, body, cue.b, adjacent: adjacent)
                    // "normal PFTs", "PFTs nl", "normal CXR".
                    if let lead = cue.lead, cue.study == "pft" || cue.study == "cxr" {
                        let n = (lead as NSString).length
                        var f = CF(study: cue.study, field: cue.study == "pft" ? "pattern" : "result", value: "normal")
                        f.a = cue.a
                        f.b = cue.a + n
                        run.extra.append(f)
                    } else if cue.study == "pft", let am = CardioRx.pftNormalAfter.first(body) {
                        let g = am.range(at: 1)
                        if !overlaps(g.location, end(g), p.consumed) {
                            p.take(g.location, end(g), CF(study: "pft", field: "pattern", value: "normal"))
                        }
                    }
                    // Strict: a piece is read only when every word of it is understood. An impure cue piece reads nothing, and
                    // neither does the rest of its run.
                    if CardioRx.runVeto.first(after) != nil {
                        run.vetoed = true
                        active = nil
                    } else if p.pure {
                        run.parses.append(p)
                        run.end = afterEnd
                        run.bare = cue.study == "carotid" && CardioRx.carBareNormal.first(body) != nil && CardioRx.sideToken.first(body) == nil
                        // A name alone in its piece heads what follows, unless the sentence said before it that it was not done
                        // ("Pending: TTE, LHC").
                        run.heading = leadParse == nil && p.findings.isEmpty && run.extraReal.isEmpty && CardioRx.punctOnly.first(body) != nil
                            && CardioRx.notDoneSent.first(sub(text, sentence.0, cue.a)) == nil && !labelled
                        run.denial = cue.study == "cxr" && CardioRx.cxrDenialOpen.first(body) != nil
                        active = run
                    } else {
                        // ("EF 35% on echo 3 years ago": the finding told first goes with the rest of its piece.)
                        run.vetoed = true
                        active = nil
                    }
                }
            }
        }
        // Two names of one study in the line ("TTE 6/26 ... TTE 2024 ...", "echo and TEE"): which is meant cannot be told.
        var cueCount: [String: Int] = [:]
        for c in cues { cueCount[c.study, default: 0] += 1 }
        for r in runs where (cueCount[r.study] ?? 0) > 1 { r.vetoed = true }
        // The study's own words left after its run (in the piece that ended it or later in the line, before another study's
        // name): the run did not say everything, and nothing of it is read. What any run read is not "left over".
        var restText: String = text
        for r in runs where !r.vetoed {
            for q in r.parses { restText = blank(restText, q.base, q.base + (q.text as NSString).length) }
        }
        let total: Int = (text as NSString).length
        for r in runs where !r.vetoed && r.end >= 0 {
            var stop: Int = total
            for c in cues where c.a >= r.end && c.a < stop { stop = c.a }
            if stop <= r.end { continue }
            let seg: String = sub(restText, r.end, stop)
            if let vocab = CardioRx.restVocab[r.study], vocab.first(seg) != nil { r.vetoed = true }
            // The next statement (after a comma, a semicolon or a full stop) opening with a word of change or doubt, or with a
            // number: "TTE EF 35%. Now 45%.", "LHC: LAD 90%. Stented."
            var opening = ""
            if let om = CardioRx.nextOpening.first(seg) { opening = grp(om, 1, seg) ?? "" }
            if CardioRx.startsWithValue.first(opening) != nil { r.vetoed = true }
            // (A statement that opens with another topic or with the plan is not about the study.)
            let other: Bool = CardioRx.otherTopic.first(opening) != nil || CardioRx.planOpening.first(opening) != nil
            var vetoAt: Int? = CardioRx.runVeto.first(opening)?.range.location
            if let tm = CardioRx.timeShift.first(opening), vetoAt == nil || tm.range.location < (vetoAt ?? 0) { vetoAt = tm.range.location }
            if !other, let at = vetoAt {
                let wordsBefore: Int = CardioRx.wordRx.all(sub(opening, 0, at)).count
                if wordsBefore < 3 { r.vetoed = true }
            }
            // The next statement gives the result again for another date ("Normal in 2024."), or says where the finding was seen.
            if CardioRx.resultDated.first(opening) != nil || CardioRx.attributed.first(opening) != nil { r.vetoed = true }
        }
        return assemble(text, runs, ndMasks)
    }

    /// The date as PatientMonthYear.parse reads it, whether or not it is plausible yet (studyDate judges that).
    private static func studyDateRaw(_ token: String, _ now: Date) -> PatientMonthYear? {
        var trimmed: String = token.trimmingCharacters(in: CharacterSet(charactersIn: " )"))
        // A full date: the study holds its month and year ("3/5/26" and "2026-03-05" are March 2026).
        if let m = CardioRx.dateMdy.first(trimmed), let mo = grp(m, 1, trimmed), let y = grp(m, 2, trimmed) {
            trimmed = mo + "/" + y
        } else if let m = CardioRx.dateIso.first(trimmed), let y = grp(m, 1, trimmed), let mo = grp(m, 2, trimmed) {
            trimmed = mo + "/" + y
        }
        guard let d = PatientMonthYear.parse(trimmed, now: now), d.year != nil else { return nil }
        return d
    }

    private static func assemble(_ text: String, _ runs: [CRun], _ ndMasks: [NSRange]) -> (findings: [CF], masks: [NSRange]) {
        var poison = Set<String>()
        for r in runs where !r.vetoed {
            for p in r.parses { for z in p.poison { poison.insert(z) } }
        }
        var keptRuns: [(run: CRun, fs: [CF])] = []
        for r in runs {
            if r.vetoed { continue }
            var fs: [CF] = []
            for p in r.parses { fs += p.findings }
            fs += r.extra
            if r.weak && !gating(r, fs) { continue }
            if fs.isEmpty { continue }
            keptRuns.append((run: r, fs: fs))
        }
        // The chest X-ray's free findings of the runs are one line, in the order written.
        var joinedFree: [String] = []
        for k in keptRuns { for f in k.fs where f.study == "cxr" && f.field == "findings" { joinedFree.append(f.value) } }
        if joinedFree.count > 1 {
            let joined = joinedFree.joined(separator: "; ")
            for ki in 0..<keptRuns.count {
                for fi in 0..<keptRuns[ki].fs.count where keptRuns[ki].fs[fi].study == "cxr" && keptRuns[ki].fs[fi].field == "findings" {
                    keptRuns[ki].fs[fi].value = joined
                }
            }
        }
        // The echo's study word.
        for ki in 0..<keptRuns.count {
            let r = keptRuns[ki].run
            if r.study == "echo", let cue = r.cue, cue.token.uppercased() == "TTE" || cue.token.uppercased() == "TEE" {
                var f = CF(study: "echo", field: "study", value: cue.token.uppercased())
                f.a = cue.a
                f.b = cue.b
                keptRuns[ki].fs.append(f)
            }
        }
        // Conflicts: two values for one field are read as neither.
        var byKey: [String: [CF]] = [:]
        for k in keptRuns { for f in k.fs { byKey[f.key, default: []].append(f) } }
        var drop = Set<String>()
        var conflicted = Set<String>()
        for (key, list) in byKey {
            if poison.contains(key) {
                drop.insert(key)
                continue
            }
            var values: [String] = []
            for f in list where !values.contains(f.value) { values.append(f.value) }
            if values.count > 1 {
                let allSegments = !list.contains { !$0.segment }
                if key.hasPrefix("lhc.stenosis.") && allSegments { continue }
                drop.insert(key)
                // Two values for one field: nothing of that study is read.
                if let f0 = list.first { conflicted.insert(f0.study) }
            }
        }
        // Chest X-ray: an abnormal finding beats "normal"; the normal words stay.
        var abnormal = false
        for k in keptRuns { for f in k.fs where f.study == "cxr" && (f.field == "effusion" || f.field == "findings") { abnormal = true } }
        if abnormal { drop.insert("cxr.result") }
        // Echo: "valves nl" beside a moderate or severe lesion, "normal biventricular function" beside a low EF or a reduced
        // ventricle: the echo says two things, and nothing of it is read.
        var echoFlags = Set<String>()
        for k in keptRuns where k.run.study == "echo" {
            for q in k.run.parses { echoFlags.formUnion(q.flags) }
        }
        var echoAll: [CF] = []
        var pftAll: [CF] = []
        for (key, list) in byKey {
            if key.hasPrefix("echo.") { echoAll += list }
            if key.hasPrefix("pft.") { pftAll += list }
        }
        if echoFlags.contains("valves-normal") && echoAll.contains(where: { $0.field.hasPrefix("valve.") && ($0.value == "moderate" || $0.value == "severe") }) {
            conflicted.insert("echo")
        }
        if echoFlags.contains("biv-normal") && echoAll.contains(where: { ($0.field == "lvef" && (Double($0.value) ?? 100) < 50) || (($0.field == "lv" || $0.field == "rv") && $0.value != "normal") }) {
            conflicted.insert("echo")
        }
        // PFT: "normal" beside a clearly abnormal number is not read as normal.
        if pftAll.contains(where: { $0.field == "pattern" && $0.value == "normal" }) {
            var low = false
            for f in pftAll {
                let v: Double = Double(f.value) ?? 100
                if ["fev1Pct", "fvcPct", "tlcPct", "dlcoPct"].contains(f.field) && v < 80 { low = true }
                if f.field == "ratio" && ((v <= 1 && v < 0.7) || (v > 1 && v < 70)) { low = true }
            }
            if low { conflicted.insert("pft") }
        }
        // Carotid: a normal or <50% artery with a high velocity, or an occluded one with a velocity, says two things.
        for side in ["right", "left"] {
            guard let st = byKey["carotid." + side + ".stenosis"]?.first?.value else { continue }
            var peak: Double = -1
            var anyVelocity = false
            for f in byKey["carotid." + side + ".psv"] ?? [] {
                peak = max(peak, Double(f.value) ?? -1)
                anyVelocity = true
            }
            if !(byKey["carotid." + side + ".edv"] ?? []).isEmpty { anyVelocity = true }
            if ((st == "normal" || st == "lt50") && peak > 230) || (st == "occluded" && anyVelocity) { conflicted.insert("carotid") }
        }
        for (key, list) in byKey {
            if let f0 = list.first, conflicted.contains(f0.study) { drop.insert(key) }
        }
        // The cath's result beside disease the model does not store (a branch at 90%, three-vessel disease): not read.
        var lhcDisease = false
        for k in keptRuns where k.run.study == "lhc" {
            for q in k.run.parses where q.flags.contains("disease") { lhcDisease = true }
        }
        if lhcDisease { drop.insert("lhc.result") }
        // Left heart cath: "no CAD" beside a stenosis, or a result beside a stenosis of 50% or more, says two things: neither.
        var lhcResults: [String] = []
        var lhcMax: Double = -1
        for (key, list) in byKey {
            if key == "lhc.result" { for f in list { lhcResults.append(f.value) } }
            if key.hasPrefix("lhc.stenosis.") { for f in list { lhcMax = max(lhcMax, Double(f.value) ?? 0) } }
        }
        if !lhcResults.isEmpty && lhcMax >= 0 && ((lhcResults.contains("no-cad") && lhcMax > 0) || lhcMax >= 50) {
            for key in byKey.keys where key == "lhc.result" || key.hasPrefix("lhc.stenosis.") { drop.insert(key) }
        }
        // A severity is the pattern's: without its pattern it is not read ("obstructive w/ mild restriction").
        if drop.contains("pft.pattern") || byKey["pft.pattern"] == nil { drop.insert("pft.severity") }
        var out: [CF] = []
        var seen = Set<String>()
        for k in keptRuns {
            for f in k.fs {
                if drop.contains(f.key) || seen.contains(f.key) { continue }
                var g = f
                if f.study == "lhc" && f.field.hasPrefix("stenosis.") {
                    var best = -1.0
                    for x in byKey[f.key] ?? [] { best = max(best, Double(x.value) ?? -1) }
                    g.value = num(best)
                }
                seen.insert(f.key)
                out.append(g)
            }
        }
        // A study of which only the date (or the echo's TTE / TEE) was read is not read.
        var studies = Set<String>()
        for f in out { studies.insert(f.study) }
        for st in studies {
            let real: Bool = out.contains { $0.study == st && $0.field != "study" && $0.field != "date" }
            if !real { out = out.filter { $0.study != st } }
        }
        var masks: [NSRange] = []
        let keys = Set(out.map { $0.key })
        for k in keptRuns {
            let mine = k.fs.filter { keys.contains($0.key) }
            if mine.isEmpty { continue }
            var spans: [NSRange] = []
            if let cue = k.run.cue { spans.append(NSRange(location: cue.a, length: cue.b - cue.a)) }
            spans += k.run.masks
            for f in mine where !f.keepWords { spans.append(NSRange(location: f.a, length: f.b - f.a)) }
            var fillers: [NSRange] = []
            for p in k.run.parses {
                if p.findings.contains(where: { keys.contains($0.key) }) {
                    for x in p.aux { spans.append(NSRange(location: p.base + x.location, length: x.length)) }
                }
                for m in CardioRx.fillerWords.all(p.text) {
                    fillers.append(NSRange(location: p.base + m.range.location, length: m.range.length))
                }
            }
            // Filler next to what is masked goes with it.
            var changed = true
            while changed {
                changed = false
                for fr in fillers where !spans.contains(fr) {
                    for s in spans {
                        var gap: String? = nil
                        if end(s) <= fr.location {
                            gap = sub(text, end(s), fr.location)
                        } else if end(fr) <= s.location {
                            gap = sub(text, end(fr), s.location)
                        }
                        if let g = gap, CardioRx.maskGap.first(g) != nil {
                            spans.append(fr)
                            changed = true
                            break
                        }
                    }
                }
            }
            masks += spans
        }
        // The history's valve for an echo valve told in a form the history reader does not know.
        var extra: [CF] = []
        for f in out where f.study == "echo" && f.field.hasPrefix("valve.") {
            if let h = f.history, h.count == 3 {
                var x = CF(study: "history", field: "valve." + h[0] + "." + h[1], value: h[2])
                x.a = f.a
                x.b = f.b
                extra.append(x)
            }
        }
        return (findings: out + extra, masks: masks + ndMasks)
    }

    // MARK: The public reading

    /// Reads a line (or a note: new lines end a run) for the cardiopulmonary tests. `page`: the page the line is typed on, whose
    /// study needs no cue there.
    static func read(_ text: String, page: CardioStudy? = nil, now: Date = Date()) -> CardioReading {
        let r = readRuns(text, page: page, now: now)
        var out = CardioReading()
        out.masks = r.masks
        for f in r.findings { out.findings.append(finding(f)) }
        return out
    }

    private static func finding(_ f: CF) -> PatientNoteFinding {
        let part = f.field.components(separatedBy: ".")
        if f.study == "echo", part.count == 3, part[0] == "valve", let g = EchoGrade(rawValue: f.value) {
            let first = part[1].prefix(1).uppercased()
            let rest = String(part[1].dropFirst())
            let name = first + rest + " " + part[2]
            return PatientNoteFinding(id: "echo:" + part[1] + ":" + part[2], section: PatientNote.Part.assessment, label: "Echo: " + name + ", " + g.rawValue,
                                      change: .echoValve(part[1], part[2], g))
        }
        if f.study == "history", part.count == 3, part[0] == "valve" {
            let valve = part[1]
            let lesion = part[2]
            let id = valve == "aortic" && lesion == "stenosis" ? "problem:as" : (valve == "mitral" && lesion == "regurgitation" ? "problem:mr" : "valve:" + valve + ":" + lesion)
            let first = valve.prefix(1).uppercased()
            let rest = String(valve.dropFirst())
            let name = first + rest + " " + lesion
            return PatientNoteFinding(id: id, section: PatientNote.Part.history, label: name + ", " + f.value, change: .valve(valve, lesion, f.value))
        }
        if f.study == "lhc", f.field == "result" {
            return PatientNoteFinding(id: "lhc:result", section: PatientNote.Part.assessment,
                                      label: "Left heart cath: " + (f.value == "no-cad" ? "no CAD" : "non-obstructive"), change: .lhcResult(f.value))
        }
        let study = CardioStudy(rawValue: f.study) ?? .echo
        let c = CardioFinding(study: study, field: f.field, value: f.value)
        return PatientNoteFinding(id: "cardio:" + f.study + ":" + f.field, section: PatientNote.Part.assessment,
                                  label: study.destination + ": " + valueText(c), change: .cardio(c))
    }

    /// The finding as the codes of the tables name it: "echo.lvef=35", "lhc.stenosis.lad=90", "history.valve.aortic.stenosis=severe".
    static func code(_ f: PatientNoteFinding) -> String? {
        switch f.change {
        case .cardio(let c): return c.study.rawValue + "." + c.field + "=" + c.value
        case .echoValve(let v, let l, let g): return "echo.valve." + v + "." + l + "=" + g.rawValue
        case .lhcResult(let v): return "lhc.result=" + v
        case .valve(let v, let l, let g): return "history.valve." + v + "." + l + "=" + (g ?? "")
        default: return nil
        }
    }

    /// Every pattern, for the test that each one compiles.
    static var allPatterns: [NoteRx] {
        var out: [NoteRx] = [
            CardioRx.aorta, CardioRx.arteryWords, CardioRx.carBareNormal, CardioRx.carSten, CardioRx.carVel, CardioRx.carVert, CardioRx.chamberFull,
            CardioRx.cmpBefore, CardioRx.cueCarotid, CardioRx.cueCath, CardioRx.cueCxr, CardioRx.cueEcho, CardioRx.cueLhc,
            CardioRx.cuePft, CardioRx.cueRadial, CardioRx.cueRhc, CardioRx.cxrEff1, CardioRx.cxrEff2, CardioRx.cxrNegStart, CardioRx.cxrNormal,
            CardioRx.cxrSegment, CardioRx.cxrVocab, CardioRx.dateAfter, CardioRx.dateBefore, CardioRx.effBadBefore, CardioRx.efHistory, CardioRx.efRx,
            CardioRx.fillerWords, CardioRx.gradeBefore, CardioRx.gradeStart, CardioRx.hedgeAfter, CardioRx.leadIn, CardioRx.letterRx, CardioRx.lhcDom,
            CardioRx.lhcOccA, CardioRx.lhcOccB, CardioRx.lhcPctAfter, CardioRx.lhcPctBefore, CardioRx.maskGap, CardioRx.negatedBefore,
            CardioRx.notDoneAfter, CardioRx.notDoneBefore, CardioRx.numbers, CardioRx.ownForm, CardioRx.pairAfter, CardioRx.pairBefore,
            CardioRx.pendingGap, CardioRx.plannedBefore, CardioRx.pftDlco, CardioRx.pftNormalAfter, CardioRx.pftPattern, CardioRx.pftRatio, CardioRx.pftTlc, CardioRx.pftVol,
            CardioRx.punctOnly, CardioRx.qOrCmpBefore, CardioRx.radCalc, CardioRx.radDiam, CardioRx.radHarvest, CardioRx.radUlnar, CardioRx.rhcCo,
            CardioRx.rhcPa, CardioRx.rhcPam, CardioRx.rhcPasp, CardioRx.rhcPcwp, CardioRx.rhcRa, CardioRx.sentBreak, CardioRx.sideCombine,
            CardioRx.sideGap, CardioRx.sideToken, CardioRx.vAfter, CardioRx.vBefore, CardioRx.vNegated, CardioRx.vPulm, CardioRx.vWritten, CardioRx.wordRx,
            CardioRx.cxrExam, CardioRx.cxrWo, CardioRx.cxrWords, CardioRx.runVeto, CardioRx.vetoBears,
            CardioRx.beforeOk, CardioRx.boundMark, CardioRx.startsWithValue, CardioRx.cxrOther,
            CardioRx.otherPerson, CardioRx.nextOpening, CardioRx.otherTopic, CardioRx.cxrSkip, CardioRx.cxrDenial, CardioRx.cxrDenialBut,
            CardioRx.aortaDim, CardioRx.cxrPure, CardioRx.cxrLeadin, CardioRx.cxrDenialOpen, CardioRx.emptyParens, CardioRx.noSplitBefore,
            CardioRx.dateMdy, CardioRx.dateIso, CardioRx.notDoneSent, CardioRx.planOpening,
            CardioRx.timeShift, CardioRx.resultDated, CardioRx.attributed, CardioRx.attribBefore, CardioRx.labelLine, CardioRx.valvesNormal,
            CardioRx.bivNormal, CardioRx.cxrOrphan,
        ]
        out += Array(CardioRx.restVocab.values)
        out += CardioRx.echoKnown + CardioRx.lhcKnown + CardioRx.rhcKnown + CardioRx.pftKnown
        for s in CardioRx.echoShapes { out.append(s.1) }
        return out
    }
}
