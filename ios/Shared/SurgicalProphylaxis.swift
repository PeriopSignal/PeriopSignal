import Foundation

// MARK: - Surgical antibiotic prophylaxis as a calculator (1.12 follow-up, Ben, Nov 16)
//
// Ben: "The Surgical prophylaxis reference is too text heavy and difficult to navigate. Convert this to a calculator where the
// user can click options and choices are given based on input. Place explanations behind info link." His answers: the result is
// the AGENT, DOSE AND REDOSE (the doses Case Timers uses, with a weight field); the extra inputs are known MRSA colonization and,
// only where the guideline splits a procedure, the risk level; from a case in My Patient it prefills the procedure, the allergy
// and the weight and each result can be started in Case Timers; the text and the tables sit behind ⓘ links and one "Full
// guideline table" link.
//
// The clinical content is reference.json "prophylaxis" (the 2013 ASHP/IDSA/SIS/SHEA guideline, Bratzler et al.): its table cells
// kept verbatim next to the structured choices built from them. Nothing here writes a dose, an agent or a guideline sentence: the
// doses come from `CaseTimerEngine.antibioticDose` (adult only), the sentences from the data.
//
// This file is the one place that turns the inputs into everything the screen shows (`ProphylaxisEngine.answer`), so the screen
// holds no clinical logic. It is pure and shared with the widget target, so it uses nothing from the app's views.

// MARK: Data (reference.json "prophylaxis")

/// Every field that may be absent decodes when it is; an unknown result `kind` reads as "text" (the table's cell is shown as it is),
/// so a newer file never makes the whole bundle fail to decode.
struct ProphylaxisData: Codable, Hashable {
    var reviewed: String?
    /// The quick reference's id: the "Full guideline table" link opens it.
    var quickref: String
    var source: ProphylaxisSource
    var classes: [ProphylaxisClass]
    /// Agents the guideline names that Case Timers has no dose for.
    var agents: [ProphylaxisAgent]
    var mrsaAgent: String
    var info: ProphylaxisInfo
    var groups: [ProphylaxisGroup]

    init(reviewed: String? = nil, quickref: String = "", source: ProphylaxisSource = ProphylaxisSource(), classes: [ProphylaxisClass] = [],
         agents: [ProphylaxisAgent] = [], mrsaAgent: String = "vancomycin", info: ProphylaxisInfo = ProphylaxisInfo(), groups: [ProphylaxisGroup] = []) {
        self.reviewed = reviewed; self.quickref = quickref; self.source = source; self.classes = classes; self.agents = agents
        self.mrsaAgent = mrsaAgent; self.info = info; self.groups = groups
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reviewed = try? c.decodeIfPresent(String.self, forKey: .reviewed)
        quickref = (try? c.decodeIfPresent(String.self, forKey: .quickref)) ?? ""
        source = (try? c.decodeIfPresent(ProphylaxisSource.self, forKey: .source)) ?? ProphylaxisSource()
        classes = (try? c.decodeIfPresent([ProphylaxisClass].self, forKey: .classes)) ?? []
        agents = (try? c.decodeIfPresent([ProphylaxisAgent].self, forKey: .agents)) ?? []
        mrsaAgent = (try? c.decodeIfPresent(String.self, forKey: .mrsaAgent)) ?? "vancomycin"
        info = (try? c.decodeIfPresent(ProphylaxisInfo.self, forKey: .info)) ?? ProphylaxisInfo()
        groups = (try? c.decodeIfPresent([ProphylaxisGroup].self, forKey: .groups)) ?? []
    }

    func group(_ id: String) -> ProphylaxisGroup? { groups.first { $0.id == id } }
    func agentName(_ id: String) -> String? { agents.first { $0.id == id }?.name }
    func cls(_ id: String) -> ProphylaxisClass? { classes.first { $0.id == id } }
}

struct ProphylaxisSource: Codable, Hashable {
    var id: String
    var label: String
    var url: String

    init(id: String = "", label: String = "", url: String = "") { self.id = id; self.label = label; self.url = url }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
    }
}

struct ProphylaxisClass: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    /// Case Timers antibiotic ids.
    var agents: [String]
    var note: String?

    init(id: String, name: String, agents: [String] = [], note: String? = nil) { self.id = id; self.name = name; self.agents = agents; self.note = note }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        agents = (try? c.decodeIfPresent([String].self, forKey: .agents)) ?? []
        note = try? c.decodeIfPresent(String.self, forKey: .note)
    }
}

struct ProphylaxisAgent: Codable, Hashable, Identifiable {
    var id: String
    var name: String

    init(id: String, name: String) { self.id = id; self.name = name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
    }
}

/// The explanations behind the ⓘ links, as the data words them.
struct ProphylaxisInfo: Codable, Hashable {
    var about: [String]
    var allergy: String
    var allergyNote: String
    var mrsa: String
    var evidence: String
    var star: [String]
    var classes: String
    var fluoroquinolone: [String]
    var ampicillinSulbactam: [String]
    var timing: String
    var noDose: String
    var none: String

    init() {
        about = []; allergy = ""; allergyNote = ""; mrsa = ""; evidence = ""; star = []; classes = ""; fluoroquinolone = []
        ampicillinSulbactam = []; timing = ""; noDose = ""; none = ""
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        about = (try? c.decodeIfPresent([String].self, forKey: .about)) ?? []
        allergy = (try? c.decodeIfPresent(String.self, forKey: .allergy)) ?? ""
        allergyNote = (try? c.decodeIfPresent(String.self, forKey: .allergyNote)) ?? ""
        mrsa = (try? c.decodeIfPresent(String.self, forKey: .mrsa)) ?? ""
        evidence = (try? c.decodeIfPresent(String.self, forKey: .evidence)) ?? ""
        star = (try? c.decodeIfPresent([String].self, forKey: .star)) ?? []
        classes = (try? c.decodeIfPresent(String.self, forKey: .classes)) ?? ""
        fluoroquinolone = (try? c.decodeIfPresent([String].self, forKey: .fluoroquinolone)) ?? []
        ampicillinSulbactam = (try? c.decodeIfPresent([String].self, forKey: .ampicillinSulbactam)) ?? []
        timing = (try? c.decodeIfPresent(String.self, forKey: .timing)) ?? ""
        noDose = (try? c.decodeIfPresent(String.self, forKey: .noDose)) ?? ""
        none = (try? c.decodeIfPresent(String.self, forKey: .none)) ?? ""
    }
}

struct ProphylaxisGroup: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var short: String?
    /// The quick reference's table sections this group draws from.
    var sections: [String]
    /// `ProcedureCatalog` specialty names: a planned procedure of one of them selects this group.
    var specialties: [String]
    var note: String?
    var procedures: [ProphylaxisProcedure]

    /// What the group's chip says.
    var chip: String { short ?? name }

    func procedure(_ id: String) -> ProphylaxisProcedure? { procedures.first { $0.id == id } }

    init(id: String, name: String, short: String? = nil, sections: [String] = [], specialties: [String] = [], note: String? = nil,
         procedures: [ProphylaxisProcedure] = []) {
        self.id = id; self.name = name; self.short = short; self.sections = sections; self.specialties = specialties
        self.note = note; self.procedures = procedures
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        short = try? c.decodeIfPresent(String.self, forKey: .short)
        sections = (try? c.decodeIfPresent([String].self, forKey: .sections)) ?? []
        specialties = (try? c.decodeIfPresent([String].self, forKey: .specialties)) ?? []
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        procedures = (try? c.decodeIfPresent([ProphylaxisProcedure].self, forKey: .procedures)) ?? []
    }
}

struct ProphylaxisProcedure: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var variants: [ProphylaxisVariant]
    /// `ProcedureCatalog` ids a planned procedure of the case may have.
    var catalog: [String]?
    /// Asked only when there are several variants.
    var question: String?
    var questionInfo: String?

    init(id: String, name: String, variants: [ProphylaxisVariant] = [], catalog: [String]? = nil, question: String? = nil, questionInfo: String? = nil) {
        self.id = id; self.name = name; self.variants = variants; self.catalog = catalog; self.question = question; self.questionInfo = questionInfo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        variants = (try? c.decodeIfPresent([ProphylaxisVariant].self, forKey: .variants)) ?? []
        catalog = try? c.decodeIfPresent([String].self, forKey: .catalog)
        question = try? c.decodeIfPresent(String.self, forKey: .question)
        questionInfo = try? c.decodeIfPresent(String.self, forKey: .questionInfo)
    }

    /// The procedure asks (several answers).
    var asks: Bool { variants.count > 1 }
}

struct ProphylaxisTableRef: Codable, Hashable {
    var section: String
    var row: String

    init(section: String = "", row: String = "") { self.section = section; self.row = row }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        section = (try? c.decodeIfPresent(String.self, forKey: .section)) ?? ""
        row = (try? c.decodeIfPresent(String.self, forKey: .row)) ?? ""
    }
}

/// One answer of a procedure's question (or its only answer): either a table row (recommended and allergy results with the
/// evidence grade) or "outside": the guideline's table has no row for it.
struct ProphylaxisVariant: Codable, Hashable, Identifiable {
    var id: String
    var label: String?
    var table: ProphylaxisTableRef?
    var evidence: String?
    var recommended: ProphylaxisResult?
    var allergy: ProphylaxisResult?
    var outside: String?

    init(id: String, label: String? = nil, table: ProphylaxisTableRef? = nil, evidence: String? = nil, recommended: ProphylaxisResult? = nil,
         allergy: ProphylaxisResult? = nil, outside: String? = nil) {
        self.id = id; self.label = label; self.table = table; self.evidence = evidence; self.recommended = recommended
        self.allergy = allergy; self.outside = outside
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        label = try? c.decodeIfPresent(String.self, forKey: .label)
        table = try? c.decodeIfPresent(ProphylaxisTableRef.self, forKey: .table)
        evidence = try? c.decodeIfPresent(String.self, forKey: .evidence)
        recommended = try? c.decodeIfPresent(ProphylaxisResult.self, forKey: .recommended)
        allergy = try? c.decodeIfPresent(ProphylaxisResult.self, forKey: .allergy)
        outside = try? c.decodeIfPresent(String.self, forKey: .outside)
    }
}

/// A table cell and what it means. Regimens are alternatives ("or"); the slots of one regimen are given together ("plus"); the
/// tokens of one slot are alternatives ("or"); an optional slot is "with or without".
struct ProphylaxisResult: Codable, Hashable {
    enum Kind: String, Codable, Hashable { case regimens, none, text }

    /// The table's cell, verbatim.
    var text: String
    var kind: Kind
    var regimens: [ProphylaxisRegimen]
    /// The cell carries the guideline's asterisk.
    var star: Bool
    var notes: [String]

    init(text: String = "", kind: Kind = .text, regimens: [ProphylaxisRegimen] = [], star: Bool = false, notes: [String] = []) {
        self.text = text; self.kind = kind; self.regimens = regimens; self.star = star; self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        let raw = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "text"
        kind = Kind(rawValue: raw) ?? .text
        regimens = (try? c.decodeIfPresent([ProphylaxisRegimen].self, forKey: .regimens)) ?? []
        star = (try? c.decodeIfPresent(Bool.self, forKey: .star)) ?? false
        notes = (try? c.decodeIfPresent([String].self, forKey: .notes)) ?? []
    }
}

struct ProphylaxisRegimen: Codable, Hashable {
    var slots: [ProphylaxisSlot]

    init(slots: [ProphylaxisSlot] = []) { self.slots = slots }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slots = (try? c.decodeIfPresent([ProphylaxisSlot].self, forKey: .slots)) ?? []
    }
}

struct ProphylaxisSlot: Codable, Hashable {
    /// Alternatives: a Case Timers antibiotic id, an `agents` id, or "class:<class id>".
    var any: [String]
    var optional: Bool
    var why: String?

    init(any: [String] = [], optional: Bool = false, why: String? = nil) { self.any = any; self.optional = optional; self.why = why }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        any = (try? c.decodeIfPresent([String].self, forKey: .any)) ?? []
        optional = (try? c.decodeIfPresent(Bool.self, forKey: .optional)) ?? false
        why = try? c.decodeIfPresent(String.self, forKey: .why)
    }
}

// MARK: - The inputs

/// What the user has chosen. The view holds one of these; every change goes through its functions, so the rules (a group with one
/// procedure selects it at once, a new procedure forgets the old answer) are tested, not drawn.
struct ProphylaxisInput: Hashable {
    var group: String?
    var procedure: String?
    var variant: String?
    var betaLactamAllergy = false
    var mrsa = false

    init(group: String? = nil, procedure: String? = nil, variant: String? = nil, betaLactamAllergy: Bool = false, mrsa: Bool = false) {
        self.group = group; self.procedure = procedure; self.variant = variant
        self.betaLactamAllergy = betaLactamAllergy; self.mrsa = mrsa
    }

    /// A group chosen: its only procedure at once, else none yet. The same group again changes nothing.
    mutating func chooseGroup(_ id: String, data: ProphylaxisData) {
        guard let g = data.group(id), group != id else { return }
        group = id
        variant = nil
        procedure = g.procedures.count == 1 ? g.procedures[0].id : nil
    }

    /// A procedure of the chosen group. A different one forgets the answer to the old one's question.
    mutating func chooseProcedure(_ id: String, data: ProphylaxisData) {
        guard let g = group.flatMap({ data.group($0) }), g.procedure(id) != nil else { return }
        if procedure != id { variant = nil }
        procedure = id
    }

    mutating func chooseVariant(_ id: String, data: ProphylaxisData) {
        guard let p = selectedProcedure(data), p.variants.contains(where: { $0.id == id }) else { return }
        variant = id
    }

    func selectedGroup(_ data: ProphylaxisData) -> ProphylaxisGroup? { group.flatMap { data.group($0) } }

    func selectedProcedure(_ data: ProphylaxisData) -> ProphylaxisProcedure? {
        guard let g = selectedGroup(data), let p = procedure else { return nil }
        return g.procedure(p)
    }

    /// "Cardiac · Coronary artery bypass": the collapsed Surgery row (the group as its chip says it: "Bowel & Hernia · Colorectal");
    /// nil until a procedure is chosen. A procedure that is its group's name ("Ophthalmic") is said once.
    func summary(_ data: ProphylaxisData) -> String? {
        guard let g = selectedGroup(data), let p = selectedProcedure(data) else { return nil }
        return g.chip == p.name ? p.name : g.chip + " · " + p.name
    }

    /// The prefill laid over the inputs: the procedure (or only the group), the allergy and the MRSA answer. Nothing it does
    /// writes back to the case.
    mutating func apply(_ p: ProphylaxisPrefill, data: ProphylaxisData) {
        if let g = p.group, data.group(g) != nil {
            group = nil
            chooseGroup(g, data: data)
            if let proc = p.procedure { chooseProcedure(proc, data: data) }
        }
        if p.betaLactamAllergy { betaLactamAllergy = true }
        if p.mrsa { mrsa = true }
    }
}

// MARK: - What the screen shows

/// One agent on one line: its name, its dose and redose from Case Timers' own numbers, and whether it can be started there.
struct ProphylaxisLine: Hashable, Identifiable {
    var id: String
    /// The Case Timers antibiotic id, or the `agents` id.
    var agent: String
    var name: String
    /// The class it came from ("Aminoglycoside"), when it was named as a class.
    var caption: String?
    /// Exactly `CaseTimerEngine.antibioticDose(def, record:).text`; nil for an agent with no dose here and for a child.
    var dose: String?
    /// "Weight needed" and the like, with the written dose.
    var needs: String?
    /// "Redose every 4 h" or "No routine redose"; nil for an agent with no dose here and for a child.
    var redose: String?
    /// The agent's own note in Case Timers ("Start within 120 min of incision.").
    var note: String?
    /// It is a Case Timers antibiotic (it has a dose and an interval there); the case's own rules decide the rest.
    var startable: Bool
    /// "Dose not in this app", for an agent Case Timers has no dose for.
    var noDose: String?
}

struct ProphylaxisSlotAnswer: Hashable {
    var lines: [ProphylaxisLine]
    var optional: Bool
    var why: String?
}

struct ProphylaxisRegimenAnswer: Hashable, Identifiable {
    var id: Int
    var slots: [ProphylaxisSlotAnswer]

    /// One agent alone: a plain row among the alternatives.
    var isSingle: Bool { slots.count == 1 && slots[0].lines.count == 1 && !slots[0].optional }
}

struct ProphylaxisAnswer: Hashable {
    enum State: Hashable {
        /// No procedure yet: the screen shows the picker.
        case noProcedure
        /// The procedure asks and no answer is chosen.
        case question
        /// The guideline's table has no row for this answer.
        case outside
        /// "No prophylaxis recommended".
        case none
        /// The table's cell as it is.
        case text
        case regimens
    }

    var state: State = .noProcedure
    var title = ""
    /// "Evidence A".
    var evidence: String?
    var question: String?
    /// The text of an outside, text or none result.
    var body = ""
    var regimens: [ProphylaxisRegimenAnswer] = []
    var notes: [String] = []
    var mrsaTitle: String?
    var mrsa: ProphylaxisLine?
    var timing: String?
    /// "Adult doses only: no dose is shown for a patient under 18."
    var childLine: String?
    /// What the result's ⓘ opens: paragraphs, none twice.
    var info: [String] = []
    var alternative = false

    /// Every agent line the result shows, the MRSA block's included.
    var allLines: [ProphylaxisLine] {
        regimens.flatMap { $0.slots.flatMap(\.lines) } + (mrsa.map { [$0] } ?? [])
    }
}

// MARK: - The prefill from a case

struct ProphylaxisPrefill: Hashable {
    var group: String?
    var procedure: String?
    /// "From the case: Coronary artery bypass grafting".
    var procedureCaption: String?
    var betaLactamAllergy = false
    /// "From the case: Penicillin (rash)".
    var allergyCaption: String?
    var mrsa = false
    var mrsaCaption: String?

    var isEmpty: Bool { group == nil && !betaLactamAllergy && !mrsa }
}

// MARK: - The engine

enum ProphylaxisEngine {
    static let recommendedTitle = "Recommended"
    static let allergyTitle = "Alternative for β-lactam allergy"
    static let outsideTitle = "Not in the guideline's table"
    static let mrsaTitle = "Known MRSA colonization"
    static let mrsaDoseNote = "Single preoperative dose"
    static let tableLead = "As the guideline's table writes it:"
    static let childLine = "Adult doses only: no dose is shown for a patient under 18."
    static let captionLead = "From the case: "
    static let noRedose = "No routine redose"
    static let fluoroquinoloneClass = "fluoroquinolone"
    static let ampicillinSulbactam = "ampicillin-sulbactam"

    // MARK: Output

    /// Everything the screen shows for these inputs. The dose is `CaseTimerEngine.antibioticDose` for the record, so Case
    /// Timers and this screen cannot disagree; a child gets none.
    static func answer(_ input: ProphylaxisInput, record r: PatientRecord, data: ProphylaxisData, timers: CaseTimerData) -> ProphylaxisAnswer {
        guard let g = input.selectedGroup(data), let p = input.selectedProcedure(data) else { return ProphylaxisAnswer() }
        let v: ProphylaxisVariant
        if p.variants.count == 1 {
            v = p.variants[0]
        } else if let id = input.variant, let found = p.variants.first(where: { $0.id == id }) {
            v = found
        } else {
            var a = ProphylaxisAnswer()
            a.state = .question
            a.question = p.question
            return a
        }
        if let outside = v.outside {
            var a = ProphylaxisAnswer()
            a.state = .outside
            a.title = outsideTitle
            a.body = outside
            if let n = g.note, !n.isEmpty { a.info = [n] }
            return a
        }
        guard let res = input.betaLactamAllergy ? v.allergy : v.recommended else { return ProphylaxisAnswer() }

        var a = ProphylaxisAnswer()
        a.alternative = input.betaLactamAllergy
        a.title = input.betaLactamAllergy ? allergyTitle : recommendedTitle
        a.evidence = v.evidence.flatMap { $0.isEmpty ? nil : "Evidence " + $0 }
        a.notes = res.notes
        let child = CaseTimerEngine.isChild(r)

        var info = InfoBuilder()
        info.add(data.info.evidence)
        info.add(tableLead + " " + res.text)

        switch res.kind {
        case .none:
            a.state = .none
            a.body = data.info.none
        case .text:
            a.state = .text
            a.body = res.text
        case .regimens:
            a.state = .regimens
            var usedClasses: [ProphylaxisClass] = []
            for (ri, reg) in res.regimens.enumerated() {
                var slots: [ProphylaxisSlotAnswer] = []
                for (si, slot) in reg.slots.enumerated() {
                    var lines: [ProphylaxisLine] = []
                    for token in slot.any {
                        if token.hasPrefix("class:") {
                            let cid = String(token.dropFirst("class:".count))
                            guard let c = data.cls(cid) else { continue }
                            if !usedClasses.contains(where: { $0.id == c.id }) { usedClasses.append(c) }
                            for agent in c.agents {
                                lines.append(line(agent, caption: c.name, id: "r\(ri).s\(si).", record: r, data: data, timers: timers, child: child))
                            }
                        } else {
                            lines.append(line(token, caption: nil, id: "r\(ri).s\(si).", record: r, data: data, timers: timers, child: child))
                        }
                    }
                    slots.append(ProphylaxisSlotAnswer(lines: lines, optional: slot.optional, why: slot.why))
                }
                a.regimens.append(ProphylaxisRegimenAnswer(id: ri, slots: slots))
            }
            if res.star { for s in data.info.star { info.add(s) } }
            if !usedClasses.isEmpty {
                info.add(data.info.classes)
                for c in usedClasses { if let n = c.note { info.add(n) } }
            }
            let agentIDs = Set(a.regimens.flatMap { $0.slots.flatMap { $0.lines.map(\.agent) } })
            let fq = Set(data.cls(fluoroquinoloneClass)?.agents ?? [])
            if !fq.isDisjoint(with: agentIDs) { for s in data.info.fluoroquinolone { info.add(s) } }
            if agentIDs.contains(ampicillinSulbactam) { for s in data.info.ampicillinSulbactam { info.add(s) } }
            if input.mrsa {
                a.mrsaTitle = mrsaTitle
                var m = line(data.mrsaAgent, caption: nil, id: "mrsa.", record: r, data: data, timers: timers, child: child)
                if m.dose != nil || m.noDose == nil { m.redose = child ? nil : mrsaDoseNote }
                a.mrsa = m
            }
            a.timing = data.info.timing.isEmpty ? nil : data.info.timing
            if child { a.childLine = childLine }
        }
        if let n = g.note { info.add(n) }
        a.info = info.paragraphs
        return a
    }

    /// Paragraphs for an ⓘ, never the same one twice.
    private struct InfoBuilder {
        var paragraphs: [String] = []
        mutating func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !paragraphs.contains(t) { paragraphs.append(t) }
        }
    }

    /// One agent's line: Case Timers' dose and redose for a Case Timers antibiotic, the name and "Dose not in this app" for an
    /// agent the guideline names that Case Timers has no dose for.
    static func line(_ agent: String, caption: String?, id prefix: String, record r: PatientRecord, data: ProphylaxisData,
                     timers: CaseTimerData, child: Bool) -> ProphylaxisLine {
        if let def = timers.antibiotic(agent) {
            var dose: String?
            var needs: String?
            var redose: String?
            if !child {
                let d = CaseTimerEngine.antibioticDose(def, record: r)
                dose = d.text
                needs = d.needs
                redose = redoseText(def.redoseHours)
            }
            return ProphylaxisLine(id: prefix + agent, agent: agent, name: def.name, caption: caption, dose: dose, needs: needs, redose: redose,
                                   note: def.note, startable: true, noDose: nil)
        }
        let name = data.agentName(agent) ?? agent.capitalized
        return ProphylaxisLine(id: prefix + agent, agent: agent, name: name, caption: caption, dose: nil, needs: nil, redose: nil, note: nil,
                               startable: false, noDose: data.info.noDose)
    }

    /// "Redose every 4 h" (whole hours without a decimal); "No routine redose" when the drug has none.
    static func redoseText(_ hours: Double?) -> String {
        guard let h = hours, h > 0 else { return noRedose }
        let n = h == h.rounded() ? String(Int(h)) : String(h)
        return "Redose every " + n + " h"
    }

    // MARK: Starting an antibiotic in Case Timers

    enum StartState: Hashable {
        /// It can be started now.
        case available
        /// The case already has a course of this drug: a second dose is never logged from here.
        case running(last: Date?, recordOnly: Bool)
        /// Not a Case Timers antibiotic, or a child (Case Timers' antibiotic card is locked for a child: adult defaults only).
        case unavailable
    }

    static func startState(_ agent: String, record r: PatientRecord, timers: CaseTimerData) -> StartState {
        guard timers.antibiotic(agent) != nil, !CaseTimerEngine.isChild(r) else { return .unavailable }
        if let c = r.timers.course(agent) { return .running(last: c.last?.time, recordOnly: c.recordOnly) }
        return .available
    }

    /// Logs the first dose of the drug at `now` exactly as Case Timers does when its card's "Log dose" is tapped on a drug picked
    /// there with its default interval (`startAntibiotics`): the same course (`AntibioticCourse.started`), the redose interval
    /// the pick starts with (the drug's own, none for a drug without one), the blood loss on the record, no typed dose. False and
    /// nothing changed when the drug is not available.
    @discardableResult
    static func start(_ agent: String, in r: inout PatientRecord, timers: CaseTimerData, now: Date) -> Bool {
        guard case .available = startState(agent, record: r, timers: timers), let def = timers.antibiotic(agent) else { return false }
        let pick = RecurrencePick(minutes: CaseTimerRecurrence.antibioticDefault(def))
        r.timers.antibiotics.append(AntibioticCourse.started(drug: agent, time: now, ebl: r.fluids["ebl"] ?? 0,
                                                             every: CaseTimerRecurrence.storedInterval(pick), typedDose: nil))
        return true
    }

    /// "Start cefazolin now?"
    static func startTitle(_ name: String) -> String { "Start " + name.lowercasedFirst + " now?" }

    /// "Logs a dose at 14:32 and starts its redose timer." (a drug with no redose interval: "Logs a dose at 14:32.")
    static func startMessage(at time: String, hasRedose: Bool) -> String {
        hasRedose ? "Logs a dose at " + time + " and starts its redose timer." : "Logs a dose at " + time + "."
    }

    // MARK: Prefill

    /// The case's planned procedures, the typed text read when an older save holds only that.
    private static func planned(_ r: PatientRecord) -> [PlannedProcedure] {
        r.procedures.isEmpty ? PlannedProcedure.parse(r.procedure) : r.procedures
    }

    /// The prefill for a case: the first planned procedure whose id a table procedure lists selects that procedure (never an answer:
    /// the question is always the user's); failing that, the first whose specialty a group lists selects the group only. The allergy
    /// and the MRSA screen are read as the Allergies row and the Labs screen hold them.
    static func prefill(record r: PatientRecord, data: ProphylaxisData) -> ProphylaxisPrefill {
        var out = ProphylaxisPrefill()
        let items = planned(r)
        var found = false
        for item in items {
            guard let cid = item.catalogID else { continue }
            for g in data.groups {
                if let p = g.procedures.first(where: { ($0.catalog ?? []).contains(cid) }) {
                    out.group = g.id; out.procedure = p.id
                    out.procedureCaption = captionLead + item.title
                    found = true
                    break
                }
            }
            if found { break }
        }
        if !found {
            outer: for item in items {
                guard let specialty = item.catalog?.specialty else { continue }
                for g in data.groups where g.specialties.contains(specialty) {
                    out.group = g.id
                    out.procedureCaption = captionLead + item.title
                    break outer
                }
            }
        }
        let lactam = ProphylaxisAllergy.betaLactams(r)
        if !lactam.isEmpty {
            out.betaLactamAllergy = true
            out.allergyCaption = captionLead + lactam.map(\.text).joined(separator: "; ")
        }
        if r.infections.results["mrsa"] == .positive {
            out.mrsa = true
            out.mrsaCaption = captionLead + "MRSA screen positive"
        }
        return out
    }
}

// MARK: - β-lactam allergy, read from the case

/// Whether a recorded allergen is a penicillin, a cephalosporin or a carbapenem, by what the Allergies list knows about it: the
/// classes the list offers ("Penicillin", "Cephalosporins", "Carbapenems") and every medication of the catalog whose class says
/// so ("Penicillin antibiotic", "Penicillin + beta-lactamase inhibitor", "Cephalosporin (first generation)", "Carbapenem
/// antibiotic"), plus the few β-lactam generics the catalog does not carry, named below. An allergen the list does not know (typed
/// as it is) is not guessed at. Aztreonam is not one (the guideline gives it as an alternative), nor are sulfa, vancomycin or
/// clindamycin.
enum ProphylaxisAllergy {
    /// Allergen entry ids of the Allergies list that are β-lactam classes.
    static let classIDs: Set<String> = ["penicillin", "cephalosporins", "carbapenems"]

    /// The class words a medication's class line starts with.
    static let classWords: [String] = ["penicillin", "cephalosporin", "carbapenem"]

    /// β-lactam generics the medication catalog does not carry, by name (folded): penicillins, cephalosporins and carbapenems with
    /// no other reading.
    static let extraGenerics: Set<String> = [
        "cefoxitin", "cefotetan", "cefotaxime", "ceftazidime", "cefaclor", "cefixime", "cefprozil", "ceftaroline", "cefiderocol",
        "ampicillin sulbactam", "ampicillin-sulbactam", "unasyn", "nafcillin", "oxacillin", "imipenem", "doripenem",
        "imipenem cilastatin", "penicillin g", "ticarcillin", "mezlocillin", "piperacillin",
    ]

    static func isBetaLactam(_ a: PatientAllergy) -> Bool {
        let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if let idx = AllergyCatalog.phrases.exact(name) {
            let e = AllergyCatalog.entries[idx]
            if classIDs.contains(e.id) { return true }
            if e.id.hasPrefix("med:"), let m = MedicationCatalog.entry(id: String(e.id.dropFirst(4))) {
                let c = m.drugClass.lowercased()
                if classWords.contains(where: { c.hasPrefix($0) }) { return true }
            }
            return false
        }
        return extraGenerics.contains(CatalogText.fold(name))
    }

    /// The allergens the Allergies row shows (the list, and the allergies typed before 1.9 while the list does not hold them), read
    /// the way the row reads them.
    static func items(_ r: PatientRecord) -> [PatientAllergy] {
        var out = r.allergyList.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let typed = r.allergies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty, out.isEmpty || !AllergyCatalog.covers(r.allergyList, legacy: r.allergies) {
            out += AllergyCatalog.parse(typed)
        }
        return out
    }

    static func betaLactams(_ r: PatientRecord) -> [PatientAllergy] { items(r).filter(isBetaLactam) }
}

// MARK: - Where the calculator replaces the quick reference

/// Whether the Reference tab shows the calculator in place of the quick reference. True unless a loaded bundle has no "prophylaxis"
/// section (an older reference.json), when the folder lists the quick reference and "Which antibiotic?" opens it, as before.
enum ProphylaxisGate {
    nonisolated(unsafe) static var available = true

    static func update(from b: ReferenceBundle?) {
        if let b { available = b.prophylaxis != nil }
    }

    /// The route key "Which antibiotic?" opens: the calculator, or the quick reference while the bundle lacks the section.
    static func linkRoute(hasCalculator: Bool) -> String {
        hasCalculator ? "prophylaxis" : "quickref:" + IntraopAntibiotic.referenceID
    }
}
