import Foundation

// MARK: - My Patient
//
// One patient at a time, kept on this device only (PatientStore, in the app target), until the user clears it.
// There are no name, record-number or date-of-birth fields. This file holds the record and the arithmetic and
// rules that read it (body size, ASA suggestion, score pre-fills, the handoff text), so the tests can reach them.

enum PatientSex: String, Codable, CaseIterable, Hashable {
    case male, female
    var label: String { self == .male ? "Male" : "Female" }
    var noun: String { self == .male ? "man" : "woman" }
}

/// Surgical timing as the 2024 AHA/ACC perioperative guideline defines it (Table 2).
enum PatientUrgency: String, Codable, CaseIterable, Hashable {
    case elective, timeSensitive, urgent, emergency
    var label: String {
        switch self {
        case .elective: return "Elective"
        case .timeSensitive: return "Time-sensitive"
        case .urgent: return "Urgent"
        case .emergency: return "Emergency"
        }
    }
    var detail: String {
        switch self {
        case .elective: return "Can be delayed for a complete evaluation and management."
        case .timeSensitive: return "Can wait up to 3 months for evaluation without harming the outcome."
        case .urgent: return "Threat to life or limb, with time for some evaluation; typically 2 to 24 h."
        case .emergency: return "Immediate threat to life or limb, with little or no time for evaluation; typically under 2 h."
        }
    }
}

/// One line of vascular access.
struct PatientLine: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind = "Peripheral IV"
    var site = ""
    var size = ""

    init(kind: String = "Peripheral IV", site: String = "", size: String = "") { self.kind = kind; self.site = site; self.size = size }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "Peripheral IV"
        site = (try? c.decodeIfPresent(String.self, forKey: .site)) ?? ""
        size = (try? c.decodeIfPresent(String.self, forKey: .size)) ?? ""
    }
    static let kinds = ["Peripheral IV", "Arterial line", "Central line", "PICC", "Intraosseous", "PA catheter", "Other"]
    var text: String { [kind, size, site].filter { !$0.isEmpty }.joined(separator: ", ") }
}

/// A regional or neuraxial technique performed.
struct PatientRegional: Codable, Hashable, Identifiable {
    var id = UUID()
    var technique = ""
    var side = ""
    var drug = ""
    var catheter = false

    init(technique: String = "", side: String = "", drug: String = "", catheter: Bool = false) {
        self.technique = technique; self.side = side; self.drug = drug; self.catheter = catheter
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        technique = (try? c.decodeIfPresent(String.self, forKey: .technique)) ?? ""
        side = (try? c.decodeIfPresent(String.self, forKey: .side)) ?? ""
        drug = (try? c.decodeIfPresent(String.self, forKey: .drug)) ?? ""
        catheter = (try? c.decodeIfPresent(Bool.self, forKey: .catheter)) ?? false
    }
    var text: String {
        var s = [side, technique].filter { !$0.isEmpty }.joined(separator: " ")
        if !drug.isEmpty { s += (s.isEmpty ? "" : ": ") + drug }
        if catheter { s += (s.isEmpty ? "" : ", ") + "catheter left in" }
        return s
    }
}

/// An infusion running or given.
struct PatientInfusion: Codable, Hashable, Identifiable {
    var id = UUID()
    var drug = ""
    var rate = ""

    init(drug: String = "", rate: String = "") { self.drug = drug; self.rate = rate }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        drug = (try? c.decodeIfPresent(String.self, forKey: .drug)) ?? ""
        rate = (try? c.decodeIfPresent(String.self, forKey: .rate)) ?? ""
    }
    var text: String { [drug, rate].filter { !$0.isEmpty }.joined(separator: " at ") }
}

/// A calculator result saved to the record.
struct PatientScore: Codable, Hashable {
    var points: Int?
    var max: Int?
    var label: String?
    var detail: String?
    /// The answers that scored ("Ischemic heart disease", "Age: 51–80").
    var answers: [String]?
    var on: [String]?
    var choices: [String: String]?
    var date: Date?
}

struct PatientRecord: Codable, Equatable {
    var version = 1
    var updated: Date?

    // Patient and procedure
    var ageYears: Double?
    var sex: PatientSex?
    var heightCm: Double?
    var weightKg: Double?
    var procedure = ""
    var urgency: PatientUrgency?
    /// "ga", "mac", "neuraxial", "regional".
    var anesthetic: Set<String> = []
    /// RCRI: intraperitoneal, intrathoracic or suprainguinal vascular surgery.
    var highRiskSurgery = false
    /// ARISCAT: "Peripheral", "Upper abdominal", "Intrathoracic".
    var incision: String?
    /// ARISCAT: "≤ 2 h", "> 2–3 h", "> 3 h".
    var duration: String?
    /// "sbp", "dbp", "hr", "spo2", "rr", "temp".
    var vitals: [String: Double] = [:]

    // History
    var noHistory = false
    var problems: Set<String> = []
    var systemNotes: [String: String] = [:]
    var otherHistory = ""
    /// "never", "former", "current".
    var smoking: String?
    var nkda = false
    var allergies = ""
    var medications = ""
    var medFlags: Set<String> = []
    var anesthesiaHistory: Set<String> = []
    var anesthesiaNotes = ""
    var lastSolids: Date?
    var lastClears: Date?
    /// "hb", "plt", "inr", "k", "na", "cr", "glucose", "a1c".
    var labs: [String: Double] = [:]
    var labNotes = ""

    // Assessment
    /// "ge4", "lt4", "unknown".
    var mets: String?
    var dasi: Set<String> = []
    var activeCardiac: Set<String> = []
    /// Frail by a validated tool (a risk modifier in the stepwise cardiac evaluation).
    var frail = false
    /// The class the clinician chose (1–6); the suggestion is never stored.
    var asaClass: Int?
    /// The clinician's E; nil follows the urgency.
    var asaE: Bool?
    var scores: [String: PatientScore] = [:]

    // Airway and examination
    var mallampati: Int?
    var airwaySigns: Set<String> = []
    var dentition = ""
    var airwayNotes = ""
    var examNotes = ""

    // Intraoperative
    /// "easy", "difficult", "none".
    var mask: String?
    var maskNote = ""
    /// Han mask-ventilation grade, 1–4.
    var maskGrade: Int?
    /// Supraglottic airway: "easy", "difficult", "none".
    var sga: String?
    var sgaNote = ""
    /// "easy", "difficult", "none".
    var intubation: String?
    var intubationNote = ""
    var airwayDevice: String?
    /// Cormack–Lehane "1", "2a", "2b", "3", "4".
    var laryngoscopyGrade: String?
    var attempts: Int?
    var tube = ""
    /// At handoff: "extubated", "intubated", "sga", "natural".
    var airwayAtEnd: String?
    /// Ventilator settings when the patient leaves intubated.
    var ventilation = ""
    /// After a difficult airway: "told", "documented", "alert" (ASA 2022 follow-up care).
    var airwayFollowUp: Set<String> = []
    var lines: [PatientLine] = []
    var regional: [PatientRegional] = []
    var infusions: [PatientInfusion] = []
    /// Units: "prbc", "wholeBlood", "plasma", "platelets", "cryo"; mL: "cellSaver", "crystalloid", "colloid", "ebl", "uop".
    var fluids: [String: Double] = [:]
    var factors = ""
    var medsGiven = ""
    var noEvents = false
    var events = ""
    var echo = ""

    // Plan
    var disposition: String?
    var painPlan = ""
    /// Monitoring and when to call.
    var callIf = ""
    var todos = ""

    init() {}

    /// Every field read with a fallback, so a record saved by an older version still opens after an update.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        version = v(.version, 1)
        updated = try? c.decodeIfPresent(Date.self, forKey: .updated)
        ageYears = try? c.decodeIfPresent(Double.self, forKey: .ageYears)
        sex = try? c.decodeIfPresent(PatientSex.self, forKey: .sex)
        heightCm = try? c.decodeIfPresent(Double.self, forKey: .heightCm)
        weightKg = try? c.decodeIfPresent(Double.self, forKey: .weightKg)
        procedure = v(.procedure, "")
        urgency = try? c.decodeIfPresent(PatientUrgency.self, forKey: .urgency)
        anesthetic = v(.anesthetic, [])
        highRiskSurgery = v(.highRiskSurgery, false)
        incision = try? c.decodeIfPresent(String.self, forKey: .incision)
        duration = try? c.decodeIfPresent(String.self, forKey: .duration)
        vitals = v(.vitals, [:])
        noHistory = v(.noHistory, false)
        problems = v(.problems, [])
        systemNotes = v(.systemNotes, [:])
        otherHistory = v(.otherHistory, "")
        smoking = try? c.decodeIfPresent(String.self, forKey: .smoking)
        nkda = v(.nkda, false)
        allergies = v(.allergies, "")
        medications = v(.medications, "")
        medFlags = v(.medFlags, [])
        anesthesiaHistory = v(.anesthesiaHistory, [])
        anesthesiaNotes = v(.anesthesiaNotes, "")
        lastSolids = try? c.decodeIfPresent(Date.self, forKey: .lastSolids)
        lastClears = try? c.decodeIfPresent(Date.self, forKey: .lastClears)
        labs = v(.labs, [:])
        labNotes = v(.labNotes, "")
        mets = try? c.decodeIfPresent(String.self, forKey: .mets)
        dasi = v(.dasi, [])
        activeCardiac = v(.activeCardiac, [])
        frail = v(.frail, false)
        asaClass = try? c.decodeIfPresent(Int.self, forKey: .asaClass)
        asaE = try? c.decodeIfPresent(Bool.self, forKey: .asaE)
        scores = v(.scores, [:])
        mallampati = try? c.decodeIfPresent(Int.self, forKey: .mallampati)
        airwaySigns = v(.airwaySigns, [])
        dentition = v(.dentition, "")
        airwayNotes = v(.airwayNotes, "")
        examNotes = v(.examNotes, "")
        mask = try? c.decodeIfPresent(String.self, forKey: .mask)
        maskNote = v(.maskNote, "")
        maskGrade = try? c.decodeIfPresent(Int.self, forKey: .maskGrade)
        sga = try? c.decodeIfPresent(String.self, forKey: .sga)
        sgaNote = v(.sgaNote, "")
        intubation = try? c.decodeIfPresent(String.self, forKey: .intubation)
        intubationNote = v(.intubationNote, "")
        airwayDevice = try? c.decodeIfPresent(String.self, forKey: .airwayDevice)
        laryngoscopyGrade = try? c.decodeIfPresent(String.self, forKey: .laryngoscopyGrade)
        attempts = try? c.decodeIfPresent(Int.self, forKey: .attempts)
        tube = v(.tube, "")
        airwayAtEnd = try? c.decodeIfPresent(String.self, forKey: .airwayAtEnd)
        ventilation = v(.ventilation, "")
        airwayFollowUp = v(.airwayFollowUp, [])
        lines = v(.lines, [])
        regional = v(.regional, [])
        infusions = v(.infusions, [])
        fluids = v(.fluids, [:])
        factors = v(.factors, "")
        medsGiven = v(.medsGiven, "")
        noEvents = v(.noEvents, false)
        events = v(.events, "")
        echo = v(.echo, "")
        disposition = try? c.decodeIfPresent(String.self, forKey: .disposition)
        painPlan = v(.painPlan, "")
        callIf = v(.callIf, "")
        todos = v(.todos, "")
    }

    /// Nothing entered (the time stamp alone does not count).
    var isEmpty: Bool {
        var blank = PatientRecord()
        blank.updated = updated
        blank.version = version
        return self == blank
    }
}

// MARK: - Body size

enum PatientBody {
    static func bmi(heightCm: Double?, weightKg: Double?) -> Double? {
        guard let h = heightCm, let w = weightKg, h > 0, w > 0 else { return nil }
        let m = h / 100
        return w / (m * m)
    }

    /// DuBois & DuBois, the formula the echo tools use.
    static func bsa(heightCm: Double?, weightKg: Double?) -> Double? {
        guard let h = heightCm, let w = weightKg, h > 0, w > 0 else { return nil }
        return 0.007184 * pow(h, 0.725) * pow(w, 0.425)
    }

    /// Devine (1974): 50 kg (men) or 45.5 kg (women) plus 2.3 kg per inch over 5 feet; only from 5 feet up.
    static func ibw(heightCm: Double?, sex: PatientSex?) -> Double? {
        guard let h = heightCm, let s = sex, h >= 152.4 else { return nil }
        let inchesOver = (h - 152.4) / 2.54
        return (s == .male ? 50 : 45.5) + 2.3 * inchesOver
    }

    /// Janmahasatian (2005) lean body weight.
    static func lbw(heightCm: Double?, weightKg: Double?, sex: PatientSex?) -> Double? {
        guard let w = weightKg, let s = sex, let b = bmi(heightCm: heightCm, weightKg: weightKg) else { return nil }
        return s == .male ? 9270 * w / (6680 + 216 * b) : 9270 * w / (8780 + 244 * b)
    }
}

extension PatientRecord {
    var bmi: Double? { PatientBody.bmi(heightCm: heightCm, weightKg: weightKg) }
    var bsa: Double? { PatientBody.bsa(heightCm: heightCm, weightKg: weightKg) }
    var ibw: Double? { PatientBody.ibw(heightCm: heightCm, sex: sex) }
    var lbw: Double? { PatientBody.lbw(heightCm: heightCm, weightKg: weightKg, sex: sex) }
    var isAdult: Bool { (ageYears ?? 18) >= 18 }
    var isChild: Bool { (ageYears ?? 99) < 18 }
    var emergency: Bool { urgency == .emergency }

    /// "62-year-old man", "4-year-old girl", "Woman", "": the opening of the one-liner.
    var person: String {
        let noun: String? = sex.map { s in isChild ? (s == .male ? "boy" : "girl") : s.noun }
        guard let a = ageYears else { return noun.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "" }
        let age = a < 1 ? "\(Int((a * 12).rounded()))-month-old" : "\(PedsCalc.fmt(a.rounded(.down)))-year-old"
        return age + (noun.map { " " + $0 } ?? "")
    }

    /// "62-year-old man · 82 kg · 178 cm": the line at the top of the tab and of the handoff.
    var oneLiner: String {
        var parts: [String] = []
        if !person.isEmpty { parts.append(person) }
        if let w = weightKg { parts.append(NumText.short(w) + " kg") }
        if let h = heightCm { parts.append(NumText.short(h) + " cm") }
        return parts.joined(separator: " · ")
    }

    func has(_ problem: String) -> Bool { problems.contains(problem) }
}
