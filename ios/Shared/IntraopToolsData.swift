import Foundation

// MARK: - 1.9 content: case timers, MTP, mechanical support, TEE companion
//
// The numbers live in reference.json ("caseTimers", "mtp", "mcs", "tee"), each section with its primary sources, so a
// correction reaches phones without an app update. Every number was drafted in the 1.9 clinical review doc
// (https://claude.ai/artifact/2hHaheME7LbUiVxjss9n3v). A section whose "reviewed" is null is a draft: release builds
// hide the tool (DraftGate) until the reviewer signs off there and "reviewed" is set to the sign-off date.

/// One primary source, shown as a discreet link inside a tool (EvidenceLinks).
struct EvidenceSource: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var url: String
}

// MARK: Case timers

struct CaseTimerData: Codable, Hashable {
    var reviewed: String?
    var reviewDoc: String?
    var adultOnly: Bool?
    /// Weights outside this range (kg) are flagged before any U/kg number shows.
    var weightFlag: [Double]?
    var antibiotics: [AntibioticDef]
    var antibioticRules: AntibioticRules
    var heparinPurposes: [HeparinPurpose]
    var heparinRules: HeparinRules
    var protamine: ProtamineRules
    var checks: [LabCheckDef]
    var sources: [EvidenceSource]

    func antibiotic(_ id: String) -> AntibioticDef? { antibiotics.first { $0.id == id } }
    func purpose(_ id: String) -> HeparinPurpose? { heparinPurposes.first { $0.id == id } }
    func check(_ id: String) -> LabCheckDef? { checks.first { $0.id == id } }
    func sources(_ ids: [String]) -> [EvidenceSource] { ids.compactMap { id in sources.first { $0.id == id } } }
}

struct AntibioticDef: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    /// As written ("2 g; 3 g if ≥120 kg").
    var dose: String
    /// nil: no routine redose.
    var redoseHours: Double?
    var doseG: Double?
    var heavyKg: Double?
    var heavyDoseG: Double?
    var mgPerKg: Double?
    /// Gentamicin: dosed on the dosing weight above 120% of ideal body weight.
    var dosingWeight: Bool?
    var note: String?
    /// The STS cardiac-surgery rule, shown when the heparin purpose is bypass or off-pump.
    var cardiac: String?
}

struct AntibioticRules: Codable, Hashable {
    var fromStart: String
    var bloodLossML: Double
    var bloodLoss: String
    var noRedose: String
    var renal: String
    var closure: String
    var bypassNoGentamicin: String
}

struct HeparinPurpose: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var doseLow: Double?
    var doseHigh: Double?
    var doseDefault: Double?
    /// A flat dose some centres give instead (5,000 IU).
    var flatUnits: Double?
    /// The preset ACT goal (s); nil: none preset (vascular, carotid, endovascular, other).
    var goal: Double?
    /// The goal on maximally activated or microcuvette devices (bypass).
    var goalDevice: Double?
    var goalText: String?
    /// Shown beside a goal the user sets where none is preset ("~200–250 s, practice only").
    var userGoalText: String?
    /// ACT reminder intervals offered (min), the first being the default.
    var actEvery: [Double]
    /// G, G? or P.
    var strength: String?
    var sources: [String]?
    var note: String?

    var isBypass: Bool { id == "bypass" }
    var isCardiac: Bool { id == "bypass" || id == "offpump" }
}

struct HeparinRules: Codable, Hashable {
    var outOfRangePct: Double
    var hardConfirmNonBypassUPerKg: Double
    /// Purposes without the bypass-size hard confirm (bypass; ECMO, signed off in the review doc).
    var hardConfirmExempt: [String]?
    var bypassMinUPerKg: Double
    var bypassMinGoal: Double
    var firstActMinutes: Double
    var unitsCheckBelow: Double
    var resistance: String
    var clottingTest: String
    var deviceNote: String
}

struct ProtamineRules: Codable, Hashable {
    var ratioLow: Double
    var ratioHigh: Double
    var flagAbove: Double
    var blockAbove: Double
    var maxMgPer10Min: Double
    var postActMinutes: Double
    var basis: String
    var ratioNote: String
    var ceilingNote: String
    var noBypass: String
    var onBypass: String
    var suction: String
    var rate: String
    /// [item, value, strength, source id].
    var facts: [[String]]
}

struct LabCheckDef: Codable, Hashable, Identifiable {
    struct Option: Codable, Hashable { var label: String; var minutes: Double }
    var id: String
    var name: String
    var options: [Option]
    /// Intervals (min) the running check can be changed to.
    var every: [Double]?
    var high: Double?
    var low: Double?
    var unit: String?
    var note: String?
    var strength: String?
    var sources: [String]?
}

// MARK: MTP

struct MtpData: Codable, Hashable {
    struct Product: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var unit: String
        var step: Double?
        var citrated: Bool
        /// The intraoperative fluids key in My Patient ("prbc", "plasma", "platelets", "cryo", "wholeBlood").
        var caseKey: String?
        /// Counted in the ratio as these lines too (whole blood: ["prbc", "plasma"]).
        var ratioAs: [String]?
        var note: String?
    }
    struct Setting: Codable, Hashable {
        var `default`: Double
        var min: Double
        var max: Double
        var mgPerUnit: Double?
        var note: String?
    }
    struct Ratio: Codable, Hashable { var target: String; var note: String }
    struct Calcium: Codable, Hashable {
        var everyUnits: Int
        var dose: String
        var chloride: String
        var rule: String
        var icaGive: Double
        var icaUrgent: Double
        var icaNote: String
        /// [product, elemental, equivalent, notes].
        var salts: [[String]]
        var fastNote: String
    }
    struct TxaContext: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var text: String
        var maxHoursFromInjury: Double?
        var late: String?
    }
    struct Txa: Codable, Hashable { var contexts: [TxaContext] }
    struct Fibrinogen: Codable, Hashable {
        var clauss: Double
        var fibtem: Double
        var tegFF: Double
        var text: String
        var note: String
    }
    /// INR 2 to <4, 4–6 (to inclusive), >6.
    struct PccBand: Codable, Hashable { var from: Double; var to: Double?; var toInclusive: Bool?; var iuPerKg: Double }
    struct Pcc: Codable, Hashable { var bands: [PccBand]; var capKg: Double; var text: String; var boxed: String }
    struct Labs: Codable, Hashable {
        var everyRbc: Int
        var everyMinutes: Double
        var kHigh: Double
        var text: String
        var strength: String?
    }

    var reviewed: String?
    var reviewDoc: String?
    var adultOnly: Bool?
    var products: [Product]
    var plateletUnits: Setting
    var cryoPool: Setting
    var ratio: Ratio
    var calcium: Calcium
    var txa: Txa
    var fibrinogen: Fibrinogen
    var pcc: Pcc
    var labs: Labs
    /// [lab, target, source].
    var targets: [[String]]
    var cautions: [String]
    var sources: [EvidenceSource]

    func product(_ id: String) -> Product? { products.first { $0.id == id } }
}

// MARK: Mechanical support

struct McsData: Codable, Hashable {
    struct Question: Codable, Hashable { var q: String; var look: String }
    struct Device: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var detail: String?
        /// My Patient device kinds (DeviceKind raw values) that preselect this device.
        var deviceKinds: [String]?
        var questions: [Question]
        /// [item, number, flag].
        var rows: [[String]]
        var call: String?
        var sources: [String]?
    }
    var reviewed: String?
    var reviewDoc: String?
    var legend: String
    var devices: [Device]
    var cautions: [String]
    var sources: [EvidenceSource]

    func sources(_ ids: [String]) -> [EvidenceSource] { ids.compactMap { id in sources.first { $0.id == id } } }
}

// MARK: TEE companion

struct TeeData: Codable, Hashable {
    struct ViewDef: Codable, Hashable, Identifiable {
        var n: Int
        var name: String
        var angle: String
        var level: String
        var basic: Bool
        var depth: String?
        var id: Int { n }
    }
    struct Surgery: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var pre: [String]
        var post: [String]
    }
    var reviewed: String?
    var reviewDoc: String?
    var views: [ViewDef]
    var viewsNote: String
    var basicNote: String
    var surgeries: [Surgery]
    /// [flag, trigger].
    var flags: [[String]]
    var rv: String
    var diastolic: String
    var report: String
    /// Checklist items that must be filled in (the exam's conditions, Nicoara 2020).
    var required: [String]?
    struct Handoff: Codable, Hashable { var title: String; var note: String }
    var handoff: Handoff?
    var sources: [EvidenceSource]

    func surgery(_ id: String) -> Surgery? { surgeries.first { $0.id == id } }
}

// MARK: - Draft gate

/// Which 1.9 sections have been signed off. Release builds show a section's tool only once reference.json carries its
/// "reviewed" date; debug builds (CI screenshots, development) show drafts with a banner. ReferenceStore updates the
/// set whenever reference.json loads or refreshes.
enum DraftGate {
    nonisolated(unsafe) static var released: Set<String> = []

    /// "caseTimers", "mtp", "mcs", "tee".
    static func shows(_ section: String) -> Bool {
        #if DEBUG
        return true
        #else
        return released.contains(section)
        #endif
    }

    static func isDraft(_ section: String) -> Bool { !released.contains(section) }

    static func update(from b: ReferenceBundle?) {
        var s = Set<String>()
        if b?.caseTimers?.reviewed?.isEmpty == false { s.insert("caseTimers") }
        if b?.mtp?.reviewed?.isEmpty == false { s.insert("mtp") }
        if b?.mcs?.reviewed?.isEmpty == false { s.insert("mcs") }
        if b?.tee?.reviewed?.isEmpty == false { s.insert("tee") }
        released = s
    }
}
