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
        if b.ask?.endpoint == nil, let e = other.ask?.endpoint { b.ask = AskConfig(endpoint: e) }
        return b
    }
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
    /// Unit of the reference values (per m² for indexed rows).
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
    /// The grade's word: "dilated", "increased", "reduced"; "abnormal" when absent.
    var word: String?
    var male: EchoRef?
    var female: EchoRef?
    var all: EchoRef?
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
