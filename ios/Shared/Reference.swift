import Foundation

// MARK: - reference.json
//
// The Reference tab's content: condensed quick references (society guidelines and checklists, each
// citing its source document) and the pediatric dosing table. It lives at the repository root as
// reference.json, is served by GitHub Pages next to posts.json, is bundled with the app as a fallback,
// and is refreshed on launch, so a correction never has to wait for an app update.

struct ReferenceBundle: Codable {
    var version: Int
    var updated: String
    /// Build stamp (seconds since 1970) that orders two files written on the same day.
    var revision: Int? = nil

    /// Whether this file is at least as new as `other`: the date first, then the build stamp.
    func isAtLeastAsNew(as other: ReferenceBundle) -> Bool {
        if updated != other.updated { return updated > other.updated }
        return (revision ?? 0) >= (other.revision ?? 0)
    }
    var disclaimer: String?
    var ask: AskConfig?
    var quickrefs: [QuickRef]
    var peds: PedsData?
    var infusions: InfusionData?
    var neuraxial: NeuraxialData?
    var ponv: PONVData?
    var echo: EchoData?
    var diastolic: DiastolicData?
    var acls: AclsData?
    var abg: AbgData?
    var regional: RegionalData?
    var obEmergency: ObEmergencyData?

    /// This bundle with any section it lacks taken from `other`: a server file written before a section
    /// existed never hides the copy built into a newer app, and a newer app keeps the Ask endpoint the server has.
    func filling(from other: ReferenceBundle) -> ReferenceBundle {
        var b = self
        if b.peds == nil { b.peds = other.peds }
        if b.infusions == nil { b.infusions = other.infusions }
        if b.neuraxial == nil { b.neuraxial = other.neuraxial }
        if b.ponv == nil { b.ponv = other.ponv }
        if b.echo == nil { b.echo = other.echo }
        if b.diastolic == nil { b.diastolic = other.diastolic }
        if b.acls == nil { b.acls = other.acls }
        if b.abg == nil { b.abg = other.abg }
        if b.regional == nil { b.regional = other.regional }
        if b.obEmergency == nil { b.obEmergency = other.obEmergency }
        if b.ask?.endpoint == nil, let e = other.ask?.endpoint { b.ask = AskConfig(endpoint: e) }
        return b
    }
}

// MARK: OB emergencies: one checklist per obstetric crisis, in the quick references' section format, with weight
// doses and, for the arrest, a clock with its decision marks. The website reads the same JSON (src/reference-ob.js).

struct ObEmergencyData: Codable {
    var reviewed: String?
    var manual: ObManual?
    var events: [ObEvent]
    var sources: [EchoSource]?
    var notes: [String]?
}

/// The Stanford manual: linked, not reproduced.
struct ObManual: Codable, Hashable {
    var title: String
    var url: String?
    var note: String?
}

struct ObEvent: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var short: String?
    var summary: String?
    var timer: ObTimer?
    /// Whose weight the doses use when it is not the mother's (the newborn): its own field and its own value.
    var weightFor: ObWeightFor?
    var weightDoses: [WeightDose]?
    var sections: [RefSection]
    /// Ids into `ObEmergencyData.sources`.
    var sources: [String]?
}

/// A separate weight for an event's doses (the newborn's), kept apart from the mother's so one is never used for
/// the other; above `maxKg` the doses are withheld and `maxText` says why.
struct ObWeightFor: Codable, Hashable {
    var key: String
    var title: String?
    var eyebrow: String?
    var prompt: String?
    var maxKg: Double?
    var maxText: String?
}

struct ObTimer: Codable, Hashable {
    var label: String?
    /// The start button's text.
    var start: String?
    var marks: [ObMark]
    var note: String?
}

struct ObMark: Codable, Hashable {
    var sec: Double
    var text: String
}

// MARK: Regional anesthesia: the body figure, peripheral blocks, the finder's map and the neuraxial guide. RegionalCalc
// reads them; the website reads the same JSON (src/reference-regional.js, R.regional).

/// A text field that the JSON writes either as one string or as a list of strings.
struct TextList: Codable, Hashable {
    var items: [String]
    init(_ items: [String]) { self.items = items }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let one = try? c.decode(String.self) { items = [one] } else { items = try c.decode([String].self) }
    }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(items) }
}

struct RegionalData: Codable {
    var reviewed: String?
    var figure: RegionalFigure
    var blockGroups: [RegionalGroup]?
    var blocks: [RegionalBlock]
    var map: [String: RegionalMapEntry]?
    var neuraxial: NeuraxialGuide?
    var sources: [EchoSource]?
    var finderNotes: [String]?
    var blockNotes: [String]?
}

struct RegionalFigure: Codable, Hashable {
    /// [width, height] of the drawing's coordinate box.
    var box: [Double]
    /// SVG path data (M, C and Z, absolute) of the body outline without the head.
    var outline: String
    var head: RegionalEllipse
    /// "front" / "back" → faint landmark dots and lines.
    var landmarks: [String: [RegionalLandmark]]
    var regions: [RegionalRegion]
}

struct RegionalEllipse: Codable, Hashable { var cx: Double; var cy: Double; var rx: Double; var ry: Double }

struct RegionalLandmark: Codable, Hashable {
    var kind: String
    var x: Double?
    var y: Double?
    var pts: [[Double]]?
}

struct RegionalRegion: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    /// "front" / "back" → polygons; a paired region lists the viewer's left polygon first.
    var views: [String: [[[Double]]]]
}

struct RegionalGroup: Codable, Hashable, Identifiable { var id: String; var name: String }

struct RegionalBlock: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var group: String
    var summary: String?
    var indications: TextList?
    var coverage: TextList?
    var position: TextList?
    var equipment: TextList?
    var target: TextList?
    var volume: TextList?
    var onset: TextList?
    var cautions: TextList?
    var tips: TextList?
    var url: String?
    var art: RegionalArt?
}

struct RegionalArt: Codable, Hashable {
    var probe: RegionalProbe?
    var sono: SonoSpec?
    var caption: String?
}

struct RegionalProbe: Codable, Hashable {
    var view: String
    var x: Double
    var y: Double
    var angle: Double?
    var len: Double?
}

/// An original ultrasound schematic in a 160 × 100 box.
struct SonoSpec: Codable, Hashable {
    /// "linear" (default) or "curved".
    var kind: String?
    var items: [SonoItem]
    var needle: SonoNeedle?
}

struct SonoItem: Codable, Hashable {
    /// band, muscle, fascia, bone, pleura, artery, vein, nerve, la, text
    var t: String
    var x: Double?
    var y: Double?
    var r: Double?
    var rx: Double?
    var ry: Double?
    var h: Double?
    var x1: Double?
    var x2: Double?
    var pts: [[Double]]?
    var label: String?
    var anchor: String?
}

struct SonoNeedle: Codable, Hashable { var from: [Double]; var to: [Double] }

struct RegionalMapEntry: Codable, Hashable {
    var neuraxial: RegionalNeuraxialOption?
    var blocks: [RegionalMapBlock]?
    var note: String?
}

struct RegionalNeuraxialOption: Codable, Hashable {
    var technique: String?
    var level: String?
    var text: String?
}

struct RegionalMapBlock: Codable, Hashable {
    var id: String
    /// "primary" (default) or "alternative".
    var role: String?
    var note: String?
}

struct NeuraxialGuide: Codable, Hashable {
    var procedures: [NeuraxialProcedure]
    var dermatomes: [NeuraxialDermatome]?
    var tables: [NeuraxialTable]?
    var sources: [EchoSource]?
    var notes: [String]?
}

struct NeuraxialProcedure: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var level: String?
    var levelText: String?
    var technique: TextList?
    var insertion: TextList?
    var spinal: TextList?
    var epidural: TextList?
    var adjuvants: TextList?
    var notes: TextList?
}

struct NeuraxialDermatome: Codable, Hashable { var level: String; var landmark: String? }

struct NeuraxialTable: Codable, Hashable {
    var title: String
    var columns: [String]
    var rows: [[String]]
    var notes: [String]?
}

// MARK: ABG: normal ranges, the Henderson–Hasselbalch constants and the compensation rules. AbgCalc reads them;
// the website reads the same JSON (src/reference-logic.js, R.abg).

struct AbgData: Codable {
    var reviewed: String?
    /// Normal ranges, [low, high]: pH, PaCO2 (mmHg), HCO3 (mEq/L).
    var normal: AbgRanges
    /// The midpoints a change is read from (7.40, 40, 24).
    var mid: AbgPoint
    var check: AbgCheck
    /// Values outside these draw a "check the entry" caution.
    var plausible: AbgRanges?
    /// metAcid and metAlk predict PaCO2 from HCO3; respAcidAcute, respAcidChronic, respAlkAcute and
    /// respAlkChronic predict HCO3 from PaCO2.
    var rules: [String: AbgRule]
    var notes: [String]?
    var sources: [EchoSource]
}

struct AbgRanges: Codable, Hashable {
    var ph: [Double]
    var paco2: [Double]
    var hco3: [Double]
}

struct AbgPoint: Codable, Hashable {
    var ph: Double
    var paco2: Double
    var hco3: Double
}

/// Henderson–Hasselbalch: pH = pk + log10(HCO3 / (solubility × PaCO2)); `tol` is how far, in pH units, the entered
/// pH may sit from that before the values are flagged as not agreeing.
struct AbgCheck: Codable, Hashable {
    var pk: Double
    var solubility: Double
    var tol: Double
}

/// expected = slope × x + intercept ± tol.
struct AbgRule: Codable, Hashable {
    var name: String?
    var slope: Double
    var intercept: Double
    var tol: Double?
    /// The highest x the rule was derived for (PaCO2 70 for chronic respiratory acidosis); above it the reading carries a caution.
    var xmax: Double?
    /// Shown before "expects" in the reading ("Winters' formula").
    var label: String?
    /// The rule as printed ("PaCO₂ = 1.5 × HCO₃ + 8 ± 2").
    var formula: String?
    var source: String?
}

// MARK: ACLS code tool: actions (drugs, shocks, rhythm checks, events), modes and their prompts, trees, lists.
// The rules that read this are in AclsCalc; the website reads the same JSON (src/reference-logic.js, R.acls).

struct AclsData: Codable {
    var reviewed: String?
    /// Length of a CPR cycle between rhythm checks, seconds.
    var cycleSec: Double
    var sources: [EchoSource]
    var actions: [String: AclsAction]
    var modes: [AclsMode]
    var notes: [String]?
}

struct AclsAction: Codable, Hashable {
    var label: String
    /// "drug", "shock", "rhythm" or "event".
    var kind: String
    /// For a rhythm check: "shockable", "nonshockable" or "rosc".
    var rhythm: String?
    /// Logging this starts a new CPR cycle (CPR started, a rhythm check).
    var cycleReset: Bool?
    /// Text logged for an event or rhythm check (the label when absent).
    var log: String?
    var detail: String?
    var repeats: AclsRepeat?
    var adult: AclsSpec?
    var child: AclsSpec?
    /// Mode to switch to once logged (ROSC → post-ROSC care).
    var goto: String?
    /// Only for these patients ("adult", "child"); all when absent.
    var patients: [String]?

    enum CodingKeys: String, CodingKey {
        case label, kind, rhythm, cycleReset, log, detail, adult, child, goto, patients
        case repeats = "repeat"
    }
}

/// Seconds after the last dose when the next one is due (min) and overdue (max).
struct AclsRepeat: Codable, Hashable {
    var min: Double
    var max: Double?
}

/// A dose or a shock energy for one kind of patient. Doses: a fixed `dose`, or `perKg` with `max`/`min`, or free
/// `text`; `doses` lists the 1st, 2nd… dose where they differ; `conc` adds the volume. Energies: `text` for adults,
/// `perKgSeq` (J/kg for shocks 1, 2…) then `thenPerKg` up to `maxPerKg` for children.
struct AclsSpec: Codable, Hashable {
    var dose: Double?
    var perKg: Double?
    var unit: String?
    var route: String?
    var max: Double?
    var min: Double?
    var conc: AclsConc?
    var text: String?
    var doses: [AclsSpec]?
    var maxDoses: Int?
    var note: String?
    var joules: Double?
    var perKgSeq: [Double]?
    var thenPerKg: Double?
    var thenAtLeast: Bool?
    var maxPerKg: Double?
    var capText: String?
    /// A child's shock energy is capped here (the adult dose).
    var maxJ: Double?
    /// No repeat timer for this patient (the action's `repeat` applies to the other).
    var noRepeat: Bool?

    /// This spec with the fields of `o` laid over it (the nth entry of `doses`).
    func merged(_ o: AclsSpec) -> AclsSpec {
        var s = self
        s.doses = nil
        if o.dose != nil { s.dose = o.dose; s.perKg = nil; s.text = nil }
        if o.perKg != nil { s.perKg = o.perKg; s.dose = nil; s.text = nil }
        if o.text != nil { s.text = o.text; if o.dose == nil { s.dose = nil }; if o.perKg == nil { s.perKg = nil } }
        if let v = o.unit { s.unit = v }
        if let v = o.route { s.route = v }
        if let v = o.max { s.max = v }
        if let v = o.min { s.min = v }
        if let v = o.conc { s.conc = v }
        if let v = o.note { s.note = v }
        return s
    }
}

struct AclsConc: Codable, Hashable {
    var value: Double
    var unit: String
}

struct AclsMode: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var short: String?
    var patients: [String]?
    var patientNote: String?
    /// Shows the 2-minute CPR cycle and its rhythm-check alert.
    var cycle: Bool?
    var cycleText: String?
    var note: String?
    var groups: [AclsGroup]?
    var prompts: [AclsPrompt]?
    var deadlines: [AclsDeadline]?
    /// Decision tree by patient: "adult", "child", or "all".
    var tree: [String: AclsTree]?
    var lists: [AclsList]?
    var sources: [String]?
}

struct AclsGroup: Codable, Hashable {
    var title: String
    var actions: [String]
    var note: String?
}

struct AclsPrompt: Codable, Hashable {
    var id: String
    /// "now" (alerts when `alert`), "soon" or "info".
    var level: String?
    /// May hold {dose:id}, {energy:id}, {count:id} and {next:id}.
    var text: String
    var action: String?
    var alert: Bool?
    var patient: String?
    var when: [AclsCond]?
}

/// One condition of a prompt; every condition of a prompt must hold.
struct AclsCond: Codable, Hashable {
    var patient: String?
    var rhythm: String?
    var done: String?
    var not: String?
    var notAny: [String]?
    var count: AclsCountCond?
    var countAny: AclsCountAnyCond?
    var countSince: AclsCountSinceCond?
    var since: AclsCountCond?
    var elapsed: AclsTimeCond?
    var cycle: AclsTimeCond?
    var weight: Bool?
}

/// [[ids], op, n]: the entries of all these actions together.
struct AclsCountAnyCond: Codable, Hashable {
    var ids: [String]
    var op: String
    var n: Double
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        ids = try c.decode([String].self); op = try c.decode(String.self); n = try c.decode(Double.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(ids); try c.encode(op); try c.encode(n)
    }
}

/// [id, op, n]: the number of entries (count) or the seconds since the last one (since).
struct AclsCountCond: Codable, Hashable {
    var id: String
    var op: String
    var n: Double
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        id = try c.decode(String.self); op = try c.decode(String.self); n = try c.decode(Double.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(id); try c.encode(op); try c.encode(n)
    }
    init(id: String, op: String, n: Double) { self.id = id; self.op = op; self.n = n }
}

/// [id, sinceId, op, n]: entries of id logged after the last sinceId.
struct AclsCountSinceCond: Codable, Hashable {
    var id: String
    var sinceId: String
    var op: String
    var n: Double
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        id = try c.decode(String.self); sinceId = try c.decode(String.self); op = try c.decode(String.self); n = try c.decode(Double.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(id); try c.encode(sinceId); try c.encode(op); try c.encode(n)
    }
    init(id: String, sinceId: String, op: String, n: Double) { self.id = id; self.sinceId = sinceId; self.op = op; self.n = n }
}

/// [op, seconds]: time since the start (elapsed) or since the cycle began (cycle).
struct AclsTimeCond: Codable, Hashable {
    var op: String
    var sec: Double
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        op = try c.decode(String.self); sec = try c.decode(Double.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(op); try c.encode(sec)
    }
    init(op: String, sec: Double) { self.op = op; self.sec = sec }
}

/// A countdown from the start of the code until an action is logged (resternotomy within 5 minutes).
struct AclsDeadline: Codable, Hashable {
    var id: String
    var label: String
    var sec: Double
    var until: String?
}

struct AclsTree: Codable, Hashable {
    var title: String?
    var start: String
    var nodes: [String: AclsNode]
}

struct AclsNode: Codable, Hashable {
    var q: String?
    var crumb: String?
    var title: String?
    var text: String?
    var items: [String]?
    var options: [AclsOption]?
    var actions: [String]?
}

struct AclsOption: Codable, Hashable {
    var label: String
    var next: String
}

struct AclsList: Codable, Hashable {
    var id: String
    var title: String
    /// Word logged before an item ("Considered: hypoxia").
    var verb: String?
    var patient: String?
    var note: String?
    var items: [AclsItem]
}

struct AclsItem: Codable, Hashable {
    var id: String
    var label: String
    var detail: String?
}

// MARK: Echo reference values (ASE chamber quantification) and the diastolic algorithm

struct EchoData: Codable {
    var reviewed: String?
    /// "dubois" (default) or "mosteller".
    var bsaFormula: String?
    var sources: [EchoSource]
    var groups: [EchoGroup]
    /// Right-atrial pressure from the IVC, shown under the group named here.
    var ivc: EchoIVC?
    var notes: [String]?
}

struct EchoSource: Codable, Hashable, Identifiable {
    var id: String
    var citation: String
    var url: String?
}

struct EchoGroup: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    /// Tab label ("LV", "RA").
    var short: String?
    var note: String?
    var measures: [EchoMeasure]
}

struct EchoMeasure: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var short: String?
    /// Unit of the reference values (per m² for indexed rows; empty for a ratio).
    var unit: String
    /// Unit of the un-indexed value, for an indexed row typed raw ("mL").
    var rawUnit: String?
    var method: String?
    /// "high" (default): larger is abnormal; "low": smaller is abnormal.
    var dir: String?
    /// "bsa": the reference values are indexed to body surface area.
    var index: String?
    /// "inclusive": the cutoff value itself is abnormal (≥ 40 mm); otherwise it is the last normal value.
    var edge: String?
    /// The same per cut, in the order of `cuts` ("inclusive" or "exclusive"); overrides `edge`. ASE 2025
    /// prints "< 4.1 · ≥ 4.1 to ≤ 4.4 · > 4.4 to ≤ 4.9 · > 4.9": inclusive, then exclusive, exclusive.
    var edges: [String]?
    /// The grade's word: "dilated", "increased", "reduced"; "abnormal" when absent.
    var word: String?
    var male: EchoRef?
    var female: EchoRef?
    var all: EchoRef?
    /// BSA-indexed cutoffs for a row typed as an absolute value (RV basal diameter: cm, and cm/m²).
    var indexed: EchoIndexed?
    /// Upper limits by age band, moved with BSA (the aortic sinuses).
    var byAge: EchoByAge?
    /// The guideline tabulates magnitudes (strain): a negative entry is read as its magnitude.
    var abs: Bool?
    var source: String?
    /// Table or page in the source ("Lang 2015, Table 2").
    var ref: String?
    var note: String?
}

struct EchoRef: Codable, Hashable {
    /// The normal range, low and high (mean ± 2 SD in the ASE tables).
    var normal: [Double]?
    /// Cutoffs between grades: three for normal / mild / moderate / severe, one for normal / abnormal.
    var cuts: [Double]
}

struct EchoIndexed: Codable, Hashable {
    var unit: String
    var edge: String?
    var edges: [String]?
    var male: EchoRef?
    var female: EchoRef?
    var all: EchoRef?
}

/// Goldstein 2015 Tables 1–2: the upper limit of the aortic sinuses by age band at a reference BSA.
struct EchoByAge: Codable, Hashable {
    /// cm added per m² of BSA above the reference, taken off below it (0.5 mm per 0.1 m²).
    var perM2: Double
    var male: EchoAgeTable
    var female: EchoAgeTable
}

struct EchoAgeTable: Codable, Hashable {
    var refBsa: Double
    var rows: [EchoAgeRow]
}

struct EchoAgeRow: Codable, Hashable {
    var from: Int
    /// Last year of the band; nil for the open-ended top band.
    var to: Int?
    var uln: Double
    var mean: Double?
}

/// The 2025 ASE diastolic document's scope, special populations and notes; the cutoffs and the algorithm
/// are in DiastolicCalc.
struct DiastolicData: Codable {
    var reviewed: String?
    var source: EchoSource
    var validation: String?
    var scope: String
    var supersedes: String?
    var populations: [DiastolicPopulation]
    /// Diastolic exercise echo: [reading, criteria].
    var exercise: [[String]]?
    var notes: [String]?
}

struct DiastolicPopulation: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    /// "main" (Figure 3, with any indicators alongside), "mac" (Figure 4), "transplant" (Section 15B),
    /// or "list" (the document's signs only; no grade).
    var mode: String
    var indicators: [String]?
    var notes: [String]?
}

struct EchoIVC: Codable, Hashable {
    var group: String
    /// Diameter, cm, at or below which the IVC counts as normal size.
    var cut: Double?
    /// On positive-pressure ventilation: diameter, cm, at or below which RA pressure is likely below 10 mmHg.
    var ventCut: Double?
    var method: String?
    var notes: [String]?
}

// MARK: PONV (Fifth consensus): how many agents by Apfel risk, the agents, rescue by class

struct PONVData: Codable {
    var reviewed: String?
    var source: String
    var sourceURL: String?
    var counts: [PONVCount]
    var riskReduction: [String]
    var agents: [PONVAgent]
    var rescueRules: [String]
}

struct PONVCount: Codable, Hashable {
    var minFactors: Int
    var maxFactors: Int
    var agents: Int
    var agentsHigh: Int?
    var text: String
}

struct PONVAgent: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var cls: String
    var dose: String
    var timing: String?
    /// Fast-acting agents offered for treatment after failed prophylaxis.
    var rescue: Bool?
    var rescueDose: String?
    /// Not redosed in recovery (aprepitant, palonosetron).
    var longActing: Bool?
    /// False for rescue-only agents (propofol).
    var prophylaxis: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, cls = "class", dose, timing, rescue, rescueDose, longActing, prophylaxis
    }
}

enum PONVPlan {
    /// The consensus count for this many Apfel factors: (fewest, most) interventions and the wording.
    static func target(factors: Int, counts: [PONVCount]) -> PONVCount? {
        counts.first { factors >= $0.minFactors && factors <= $0.maxFactors }
    }

    /// Classes covered by the chosen agents; two agents of one class count once.
    static func classes(of chosen: Set<String>, in agents: [PONVAgent]) -> [String] {
        var seen: [String] = []
        for a in agents where chosen.contains(a.id) && !seen.contains(a.cls) { seen.append(a.cls) }
        return seen
    }

    /// Rescue options: fast-acting agents from classes not given for prophylaxis, in table order.
    static func rescueOptions(chosen: Set<String>, agents: [PONVAgent]) -> [PONVAgent] {
        let used = Set(classes(of: chosen, in: agents))
        return agents.filter { $0.rescue == true && !used.contains($0.cls) }
    }

    /// Long-acting agents among those given (not to be redosed in recovery).
    static func longActingGiven(chosen: Set<String>, agents: [PONVAgent]) -> [PONVAgent] {
        agents.filter { chosen.contains($0.id) && $0.longActing == true }
    }
}

// MARK: Neuraxial and deep-block timing on antithrombotic drugs (ASRA)

struct NeuraxialData: Codable {
    var reviewed: String?
    var source: String
    var sourceURL: String?
    var general: [String]
    var groups: [NeuraxialGroup]
    var allDrugs: [NeuraxialDrug] { groups.flatMap(\.drugs) }
}

struct NeuraxialGroup: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var drugs: [NeuraxialDrug]
}

struct NeuraxialDrug: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var tiers: [NeuraxialTier]
    var notes: [String]?
}

struct RenalRule: Codable, Identifiable, Hashable {
    var id: String { label }
    var label: String
    /// Hours to hold; nil = the block is to be avoided (see `text`).
    var hours: Double?
    var elderlyHours: Double?
    var text: String?
}

struct NeuraxialTier: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    /// Earliest block, hours after the last dose; nil with `holdText` explaining (e.g. avoid).
    var holdHours: Double?
    /// Next dose, hours after needle placement or catheter removal.
    var restartHours: Double?
    var holdText: String?
    var restartText: String?
    var catheter: String?
    var level: String?
    var renal: [RenalRule]?
    var renalNote: String?
    var removalHours: Double?
    var afterRemovalHours: Double?
    var inrRule: Bool?
}

// MARK: Vasoactive infusions and hematologic agents

struct InfusionData: Codable {
    var reviewed: String?
    var note: String?
    var groups: [InfusionGroup]
}

struct InfusionGroup: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var drugs: [InfusionDrug]
    /// The tab this group is shown under ("Hemodynamic"); groups without one are their own tab.
    var tab: String? = nil
}

struct InfusionDrug: Codable, Identifiable, Hashable {
    /// How `start` is expressed: perKgPerMin (mcg/kg/min), perMin (mcg/min), perKg (a weight-based bolus or load),
    /// perKgPerHour (mg/kg/h), perHour (mg/h), fixed (a fixed dose), text (no number to compute).
    enum Form: String, Codable, Hashable { case perKgPerMin, perMin, perKg, perKgPerHour, perHour, fixed, text }
    var id: String
    var name: String
    var use: String
    var form: Form
    var start: Double?
    var startHigh: Double?
    /// Unit of `start`: mcg, mg, g, units, ng, ppm, mL.
    var unit: String?
    var titration: String?
    var range: String?
    var max: String?
    var bolus: String?
    var preparation: String?
    var caution: String?
    var offLabel: Bool?
    var source: String?
    /// The drug's class as a short tag ("Vasopressor", "Inodilator").
    var role: String? = nil
    /// Always-visible line for blood products: when to transfuse.
    var threshold: String? = nil
    /// Overrides the generated dose text in the row ("1 unit per 7–10 kg").
    var display: String? = nil

    /// "Dexmedetomidine (Precedex)" → ("Dexmedetomidine", "Precedex").
    var nameParts: (main: String, alias: String?) {
        guard name.hasSuffix(")"), let open = name.range(of: " (", options: .backwards) else { return (name, nil) }
        return (String(name[..<open.lowerBound]), String(name[open.upperBound..<name.index(before: name.endIndex)]))
    }
}

/// Where the app sends questions the references and the feed cannot answer (set once the proxy exists).
struct AskConfig: Codable, Hashable {
    var endpoint: String?
}

struct RefSource: Codable, Hashable {
    var title: String
    var citation: String?
    var url: String
    var doi: String?
}

struct QuickRef: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var society: String
    /// Short society name for eyebrows ("ASRA", "ASE", "MHAUS").
    var short: String?
    var year: Int?
    /// Topic id for the colour dot (see Topics).
    var topic: String?
    var keywords: [String]?
    var summary: String
    var source: RefSource
    var reviewed: String?
    /// Emergency checklists get the coral treatment and sort first.
    var emergency: Bool?
    var sections: [RefSection]
    /// Weight-based doses the card computes for the patient (emergency checklists).
    var weightDoses: [WeightDose]?

    var isEmergency: Bool { emergency ?? false }
    var societyShort: String { short ?? society }

    /// Everything searchable, lowercased once.
    var searchText: String {
        var parts = [title, society, societyShort, summary]
        parts += keywords ?? []
        for s in sections {
            if let h = s.heading { parts.append(h) }
            parts += s.items ?? []
            if let t = s.text { parts.append(t) }
            for row in s.rows ?? [] { parts += row }
        }
        return parts.joined(separator: " ").lowercased()
    }
}

/// A dose the emergency card computes from the patient's weight.
struct WeightDose: Codable, Hashable, Identifiable {
    var id: String { label }
    var label: String
    var perKg: Double
    var perKgHigh: Double?
    var unit: String
    var max: Double?
    /// Fixed regimen above a weight threshold (ASRA lipid: 100 mL bolus over 70 kg).
    var aboveKg: Double?
    var aboveText: String?
    var note: String?
    /// Vial size in `unit` for a vial count (Ryanodex 250 mg, Dantrium 20 mg).
    var vialSize: Double?
    var vialName: String?
}

struct RefSection: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        /// `columns` + `rows`: the first cell of a row is its title.
        case table
        /// `items`: diamond bullets.
        case list
        /// `items`: numbered steps.
        case steps
        /// `text`: a paragraph.
        case text
        /// `rows` of [label, value]: a two-column fact table.
        case facts
    }
    var heading: String?
    var kind: Kind
    var columns: [String]?
    var rows: [[String]]?
    var items: [String]?
    var text: String?
    var note: String?
}

// MARK: Pediatric dosing data

struct PedsData: Codable {
    var reviewed: String?
    var note: String?
    var drugs: [PedsDrug]
    var localAnesthetics: [LocalAnesthetic]
    var bloodVolume: [BloodVolumeRow]
}

struct PedsDrug: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// What the dose is for ("Induction", "RSI", "Cardiac arrest").
    var use: String
    /// Grouping on screen ("Induction", "Neuromuscular", "Emergency", "Analgesia", "Antiemetic", "Reversal", "Other").
    var group: String
    var route: String
    /// Dose per kilogram: `low`–`high` `unit`/kg (high optional).
    var low: Double
    var high: Double?
    var unit: String
    /// Floor for one dose, in `unit` (atropine's 0.1 mg minimum).
    var min: Double?
    /// Ceiling for one dose, in `unit` (e.g. 1 mg of epinephrine, 4 mg of ondansetron).
    var max: Double?
    /// Concentration note, shown as written ("0.1 mg/mL (1:10,000) → 0.1 mL/kg").
    var conc: String?
    var note: String?
    var source: String?
}

struct LocalAnesthetic: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// Pediatric maximum single-injection dose, mg/kg (ASRA/ESRA).
    var maxMgPerKg: Double
    /// Concentrations as percent, for the mL conversion (0.25 → 0.25% = 2.5 mg/mL).
    var concentrations: [Double]
    var note: String?
    var source: String?
    // Adult label maxima (added for the mixture calculator; optional so older data still decodes).
    /// "amide", "ester" or "liposomal".
    var kind: String?
    var adultPlainMgPerKg: Double?
    var adultPlainMaxMg: Double?
    var adultEpiMgPerKg: Double?
    var adultEpiMaxMg: Double?
    var per24hMaxMg: Double?
    /// Pediatric per-kg maximum with epinephrine, when a label gives one (lidocaine 7, chloroprocaine 14).
    var pedsEpiMgPerKg: Double?
    /// Pediatric floor age in years when the label limits use (Exparel: 6).
    var pedsMinYears: Int?
    var pedsMaxMg: Double?
    /// Short label for pickers ("Bupivacaine 0.5%" is built from name + concentration).
    var short: String?

    var isLiposomal: Bool { kind == "liposomal" }
}

struct BloodVolumeRow: Codable, Identifiable, Hashable {
    var id: String { group }
    var group: String
    /// Age window in months the row applies to (upper bound exclusive; nil = open).
    var fromMonths: Double?
    var toMonths: Double?
    var mlPerKgLow: Double
    var mlPerKgHigh: Double
}

// MARK: - Loader (network + cache + bundled fallback)

enum ReferenceLoader {
    static let url = URL(string: "https://periopsignal.github.io/PeriopSignal/reference.json")!
    static let decoder = JSONDecoder()

    static func decode(_ data: Data) throws -> ReferenceBundle { try decoder.decode(ReferenceBundle.self, from: data) }

    static func fetch() async throws -> (ReferenceBundle, Data) {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970 / 3600)))]
        var req = URLRequest(url: comps.url!)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { throw URLError(.badServerResponse) }
        return (try decode(data), data)
    }

    static var cacheURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("reference.json")
    }

    static func loadCached() -> ReferenceBundle? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? decode(data)
    }

    static func saveCache(_ data: Data) { try? data.write(to: cacheURL, options: .atomic) }

    /// The copy shipped inside the app (the repository's reference.json at build time).
    static func loadBundled(bundle: Bundle = .main) -> ReferenceBundle? {
        guard let url = bundle.url(forResource: "reference", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }
}
