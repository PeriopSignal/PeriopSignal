import Foundation

// MARK: - Notable medications as chips (1.12, Ben's note 18) and the antibiotics charted in Case Timers (note 3)
//
// The Intraoperative tab's "Antibiotics & Notable Medications" row and its page. The chips are the drugs Ben named,
// each with an optional dose typed beside it once chosen: Milrinone bolus, Inhaled milrinone, TXA, Amicar (aminocaproic
// acid), PCC (Kcentra), Fibrinogen concentrate, Factor VIIa (NovoSeven), Cyanokit (hydroxocobalamin), Methylene blue.
// No default dose and no dose suggestion anywhere: what is printed is what was typed. A milrinone bolus or inhaled
// milrinone is NOT an infusion and never goes to the infusion list; dobutamine is an infusion only (no chip).
//
// What the page recorded before 1.12 keeps working: `PatientRecord.medsGiven` (the free text: antibiotic and time, steroids,
// TXA, reversal) is still there and still printed as typed. A TXA entry typed in it ("TXA 1 g", "Tranexamic acid 1 g load
// then 400 mg/h") shows on the page as the TXA chip chosen with that dose (`pageState`), and moves out of the text into
// the chip when the page is first changed (`migrateLegacy`); the summaries print the saved text as it is until then.

/// The Intraoperative tab's notable medications as chips, each with an optional dose.
struct PatientNotableMeds: Codable, Hashable {
    /// One chosen chip and the dose typed beside it ("" when none).
    struct Entry: Codable, Hashable, Identifiable {
        var id: String
        var dose: String = ""

        init(_ id: String, dose: String = "") { self.id = id; self.dose = dose }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
            dose = (try? c.decodeIfPresent(String.self, forKey: .dose)) ?? ""
        }
    }

    /// A chip: what it says, and the words VoiceOver and the dose field use.
    struct Option: Hashable, Identifiable {
        var id: String
        var label: String
        var full: String
        init(_ id: String, _ label: String, full: String? = nil) { self.id = id; self.label = label; self.full = full ?? label }
    }

    /// Ben's list, in his order. The ids are what the record stores.
    static let options: [Option] = [
        Option("milrinoneBolus", "Milrinone bolus"),
        Option("milrinoneInhaled", "Inhaled milrinone"),
        Option("txa", "TXA", full: "TXA (tranexamic acid)"),
        Option("amicar", "Amicar", full: "Amicar (aminocaproic acid)"),
        Option("pcc", "PCC", full: "PCC (Kcentra)"),
        Option("fibrinogen", "Fibrinogen concentrate"),
        Option("factorVIIa", "Factor VIIa", full: "Factor VIIa (NovoSeven)"),
        Option("cyanokit", "Cyanokit", full: "Cyanokit (hydroxocobalamin)"),
        Option("methyleneBlue", "Methylene blue"),
    ]

    static func option(_ id: String) -> Option? { options.first { $0.id == id } }

    /// The chosen chips, in the order they were chosen.
    var entries: [Entry] = []

    private enum CodingKeys: String, CodingKey { case entries }

    init() {}

    /// Every field has a default and is read with a fallback, so a record saved by an older version still opens.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var seen = Set<String>()
        entries = ((try? c.decodeIfPresent([Entry].self, forKey: .entries)) ?? []).filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }

    var isEmpty: Bool { entries.isEmpty }

    func has(_ id: String) -> Bool { entries.contains { $0.id == id } }

    func dose(_ id: String) -> String { entries.first { $0.id == id }?.dose ?? "" }

    /// A tap on a chip: chosen, or (a second tap) cleared with its dose.
    mutating func toggle(_ id: String) {
        if let i = entries.firstIndex(where: { $0.id == id }) { entries.remove(at: i) } else { entries.append(Entry(id)) }
    }

    mutating func setDose(_ id: String, _ dose: String) {
        if let i = entries.firstIndex(where: { $0.id == id }) { entries[i].dose = dose }
    }

    /// The chosen chips as the summaries list them: Ben's order, then any id this version does not know.
    var ordered: [Entry] {
        let known = Self.options.compactMap { o in entries.first { $0.id == o.id } }
        return known + entries.filter { Self.option($0.id) == nil }
    }

    /// "TXA 1 g", "Milrinone bolus".
    static func text(of e: Entry) -> String {
        [option(e.id)?.label ?? e.id, e.dose.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The chosen chips with their doses, one string each.
    var items: [String] { ordered.map(Self.text(of:)) }

    // MARK: A TXA typed before 1.12

    private static let txaRx = try! NSRegularExpression(pattern: #"^(?:txa|tranexamic acid|tranexamic)\b[\s:\-–]*"#, options: [.caseInsensitive])

    /// The first entry of the free text that starts with TXA or tranexamic acid, as a dose, and the text without it.
    /// Entries are separated by ";" or a new line, as FreeText.capItems reads them; nil when there is none.
    static func legacyTXA(in text: String) -> (dose: String, rest: String)? {
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ";\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let i = parts.firstIndex(where: { txaRx.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }),
              let m = txaRx.firstMatch(in: parts[i], range: NSRange(parts[i].startIndex..., in: parts[i])) else { return nil }
        let dose = (parts[i] as NSString).substring(from: m.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
        var others = parts
        others.remove(at: i)
        return (dose, others.filter { !$0.isEmpty }.joined(separator: "; "))
    }

    /// What the page shows: the chips chosen (a TXA typed in the free text before 1.12 as the TXA chip, first) and the free
    /// text without that entry. A record with a TXA chip already keeps its text as it is.
    static func pageState(_ r: PatientRecord) -> (entries: [Entry], text: String) {
        if !r.notableMeds.has("txa"), let legacy = legacyTXA(in: r.medsGiven) {
            return ([Entry("txa", dose: legacy.dose)] + r.notableMeds.entries, legacy.rest)
        }
        return (r.notableMeds.entries, r.medsGiven)
    }

    /// Moves a TXA typed in the free text into the TXA chip; the page's first change calls it, so what the user did not touch
    /// is never rewritten.
    static func migrateLegacy(_ r: inout PatientRecord) {
        guard !r.notableMeds.has("txa"), let legacy = legacyTXA(in: r.medsGiven) else { return }
        r.notableMeds.entries.insert(Entry("txa", dose: legacy.dose), at: 0)
        r.medsGiven = legacy.rest
    }

    /// "Medications & interventions" as the Intraoperative tab and the handoff say it: the chips with their doses, then the free
    /// text as typed.
    static func lines(_ r: PatientRecord) -> [String] {
        var out = r.notableMeds.items
        let free = r.medsGiven.trimmingCharacters(in: .whitespacesAndNewlines)
        if !free.isEmpty { out.append(free.hasSuffix(".") || free.hasSuffix(";") ? String(free.dropLast()) : free) }
        return out
    }
}

// MARK: - Antibiotics charted in Case Timers (1.12, Ben's note 3)

/// The antibiotics of the open case's Case Timers, read-only: the drug and dose as Case Timers holds them, the last dose
/// given and the next redose due ("Cefazolin 2 g · last 08:12 · next due 12:12"), or "no routine redose" where the timer
/// has none. An overdue redose (five minutes past its time, as Case Timers counts it) is red. Nothing here changes a
/// course: it reads `PatientRecord.timers` and the numbers in reference.json "caseTimers".
enum CaseAntibiotics {
    struct Line: Hashable, Identifiable {
        var id: String
        var name: String
        var dose: String
        var last: Date
        /// When the next redose falls due; nil: no routine redose (or the course is recorded only).
        var next: Date?
        var overdue: Bool
        var lastText: String
        var nextText: String?
        /// 1.12 (Ben, Nov 12): the course is recorded only: its doses and times are told, never a next dose or "no routine redose".
        var recordOnly = false
        /// Every dose's time, oldest first, as the summaries write a time ("08:12", "11/11/26 23:50").
        var givenTexts: [String] = []

        var drug: String { [name, dose].filter { !$0.isEmpty }.joined(separator: " ") }

        /// Where a recorded-only course was given: "08:12"; several doses, every time ("08:12, 12:30"). The line for a timed course tells
        /// the LAST dose only, because its next dose is the news; a recorded course has no next dose, so each time is told.
        var givenText: String { givenTexts.isEmpty ? lastText : givenTexts.joined(separator: ", ") }

        /// "Cefazolin 2 g · last 08:12 · next due 12:12" (the tab and the page); recorded only: "Cefazolin 2 g · given 08:12".
        var tabText: String {
            if recordOnly { return drug + " · given " + givenText }
            return drug + " · last " + lastText + " · " + (nextText.map { "next due " + $0 } ?? "no routine redose")
        }

        /// "Cefazolin 2 g, last 08:12, next due 12:12" (the handoff); recorded only: "Cefazolin 2 g, given 08:12".
        var handoffText: String {
            if recordOnly { return drug + ", given " + givenText }
            return drug + ", last " + lastText + ", " + (nextText.map { "next due " + $0 } ?? "no routine redose")
        }
    }

    /// reference.json as it shipped with the app: the summaries have no store to ask, so they read this; a view that has the
    /// refreshed copy passes it. Tests set `override`.
    nonisolated(unsafe) static var override: CaseTimerData?
    static let bundled: CaseTimerData? = ReferenceLoader.loadBundled()?.caseTimers
    static var current: CaseTimerData? { override ?? bundled }

    /// Five minutes past its time, as CaseReminder.state counts it.
    static let overdueAfter: TimeInterval = 300

    /// One line per antibiotic with a dose logged, in the order the courses were started.
    static func lines(_ r: PatientRecord, data: CaseTimerData? = CaseAntibiotics.current, now: Date = Date()) -> [Line] {
        var out: [Line] = []
        for course in r.timers.antibiotics {
            guard let last = course.last else { continue }
            let def = data?.antibiotic(course.drug)
            let name = def?.name ?? course.drug.capitalized
            // The dose typed in the bar with the last dose (1.12 follow-up), as typed; else the dose Case Timers computes.
            // A course recorded only (1.12) states the dose only when one was typed: the dose Case Timers would compute was not given.
            var dose = course.reminders ? (def.map { CaseTimerEngine.antibioticDose($0, record: r).text } ?? "") : ""
            if let typed = last.given?.trimmingCharacters(in: .whitespacesAndNewlines), !typed.isEmpty { dose = typed }
            var next: Date?
            if !course.reminders {
                // Recorded only: no next dose, never overdue.
            } else if let def {
                next = CaseTimerRecurrence.redoseMinutes(course, def: def).map { last.time.addingTimeInterval($0 * 60) }
            } else if let m = course.everyMinutes, m > 0 {
                next = last.time.addingTimeInterval(m * 60)
            }
            let overdue = next.map { now.timeIntervalSince($0) > overdueAfter } ?? false
            out.append(Line(id: course.drug, name: name, dose: dose, last: last.time, next: next, overdue: overdue,
                            lastText: PatientSummary.time(last.time, now: now), nextText: next.map { PatientSummary.time($0, now: now) },
                            recordOnly: !course.reminders,
                            givenTexts: course.doses.sorted { $0.time < $1.time }.map { PatientSummary.time($0.time, now: now) }))
        }
        return out
    }
}
