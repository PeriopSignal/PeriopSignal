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
    /// At most 90: an age of 90 or more is kept as "90 or older" (HIPAA Safe Harbor), however it was entered.
    var ageYears: Double? {
        didSet { if let a = ageYears, a > Self.oldestAge { ageYears = Self.oldestAge } }
    }
    var sex: PatientSex?
    var heightCm: Double?
    var weightKg: Double?
    /// The planned procedures joined with " + " for the summary, handoff and rules; kept in step with `procedures`.
    var procedure = ""
    /// The planned procedures as items (1.6). Empty in older saves, where only `procedure` holds the text.
    var procedures: [PlannedProcedure] = []
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
    var problems: Set<String> = [] {
        // An item taken off, by any path, is no longer the labs' (LabResults.edit) or a link's (PatientCrossFill) to take
        // off later.
        didSet {
            if !labProblems.isSubset(of: problems) { labProblems.formIntersection(problems) }
            if !fills.problems.isSubset(of: problems) { fills.problems.formIntersection(problems) }
        }
    }
    /// The diameter (cm) of each unruptured aortic aneurysm, by problem id ("aaa", "taa", "taaa"), as saved before the
    /// aneurysms were kept by location (PatientHistoryDetails.aneurysms); read once and moved there.
    var aortaSizes: [String: Double] = [:]
    /// What the expanding History pages hold beside the problem ids: valves, aneurysms by location, typed details (1.8.1).
    var hx = PatientHistoryDetails()
    /// Each system page's Other details (1.8: its "Other"), by system id.
    var systemNotes: [String: String] = [:]
    /// Each system page's Other [system] disorders (1.9), by system id.
    var systemOther: [String: String] = [:]
    var otherHistory = ""
    /// "never", "former", "current".
    var smoking: String?
    var nkda = false
    /// Allergies as typed before 1.9; shown until the list below holds them.
    var allergies = ""
    /// Allergies as items with their severity (1.9).
    var allergyList: [PatientAllergy] = []
    /// The medication list as typed before 1.9; shown until the list below holds the same drugs.
    var medications = ""
    /// Home and current medications as items (1.9).
    var homeMeds: [PatientMed] = []
    var medFlags: Set<String> = [] {
        didSet { if !fills.medFlags.isSubset(of: medFlags) { fills.medFlags.formIntersection(medFlags) } }
    }
    var anesthesiaHistory: Set<String> = []
    var anesthesiaNotes = ""
    var lastSolids: Date?
    var lastClears: Date?
    /// "hb", "plt", "inr", "k", "na", "cr", "glucose", "a1c", "bnp", "ntprobnp", "troponin", "troponin99" (the assay's
    /// 99th percentile), "lactate" (1.8.3) and the rest of PatientLabs.catalog.
    var labs: [String: Double] = [:]
    var labNotes = ""
    /// Type and screen, and the infectious results (LabResults, 1.8.3).
    var typeScreen = PatientTypeScreen()
    var infections = PatientInfections()
    /// Infectious history items a positive result added (LabResults.edit), so only those are taken off when the result
    /// changes; never one the user entered.
    var labProblems: Set<String> = []
    /// Past surgical history (PatientWorkup), in the order entered.
    var surgeries: [PatientSurgery] = []
    /// Infusions running before the case, with their rates (Medications & Allergies).
    var homeInfusions: [PatientInfusion] = []
    /// Child-Turcotte-Pugh and MELD inputs beyond the labs (PatientLabs): ascites, encephalopathy, and dialysis twice
    /// or more in the past week (or CVVHD for 24 h).
    var ascites: LiverAscites?
    var encephalopathy: LiverEncephalopathy?
    var dialysis = false
    /// The lab sections opened with their ⊕ (cardiac, liver, thyroid), kept open while the patient is.
    var labSections: Set<String> = []

    // Assessment
    /// "ge4", "lt4", "unknown".
    var mets: String?
    var dasi: Set<String> = []
    var activeCardiac: Set<String> = []
    /// Active cardiac symptoms and signs (PatientFunctional.cardiacSymptomFlags).
    var cardiacSymptoms: Set<String> = []
    /// The single-line answers that open the symptom and acute-condition chips: nil not asked, false No, true Yes.
    var cardiacSymptomsAnswer: Bool?
    var activeCardiacAnswer: Bool?
    /// Previous cardiac or thoracic operations added in the cardiac evaluation (the surgical history's own
    /// intrathoracic operations are listed with them).
    var intrathoracic: [PatientSurgery] = []
    /// ECG findings from the typeable list, and anything else.
    var ecg: [String] = [] {
        didSet { if !fills.ecg.isSubset(of: Set(ecg)) { fills.ecg.formIntersection(Set(ecg)) } }
    }
    var ecgNotes = ""
    var echoFindings = PatientEcho()
    var lhc = PatientLHC()
    var rhc = PatientRHC()
    /// Studies beyond the heart (PatientStudies, 1.8.1): carotid and radial artery ultrasound, pulmonary function tests.
    var carotid = PatientCarotid()
    var radial = PatientRadial()
    var pft = PatientPFT()
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
    /// The airway examination was done: mouth opening, thyromental distance and neck movement not flagged under the
    /// signs read as normal (set by Exam normal, PatientAirway.applyNormalExam). False in records saved before 1.8.
    var airwayExamReviewed = false
    /// The airway the patient arrives with: "natural", "ett" or "trach"; with an ETT or a tracheostomy the airway
    /// examination and the intraoperative airway course are not asked.
    var currentAirway: String?
    var ettSize = ""
    /// "23 cm at the lip".
    var ettDepth = ""
    /// "Shiley 8 cuffed".
    var trachType = ""
    /// Ventilator settings (intubated or on a tracheostomy) or oxygen (breathing on their own) on arrival.
    var vent = PatientVent()
    var oxygen = PatientOxygen()

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
    /// Lines as entered before 1.6; a saved patient's are moved into `devices` when it opens.
    var lines: [PatientLine] = []
    /// Lines and devices on the patient diagram (PatientDevices): peripheral, arterial and central lines, PA catheter,
    /// ECMO cannulas, LVAD, IABP, Impella. The airway lives in currentAirway and the intraoperative course; blocks and
    /// neuraxial techniques in `regional`.
    var devices: [PatientDevice] = []
    /// Limbs to spare (1.9): typed by the user ("prior axillary lymph node dissection"); an AV fistula's arm is
    /// added on the diagram by itself (PatientDeviceFills.limbAlerts), not stored here.
    var limbAlerts: [PatientLimbAlert] = []
    var regional: [PatientRegional] = []
    var infusions: [PatientInfusion] = []
    /// Units: "prbc", "wholeBlood", "plasma", "platelets", "cryo"; mL: "cellSaver", "crystalloid", "colloid", "ebl", "uop".
    var fluids: [String: Double] = [:]
    var factors = ""
    var medsGiven = ""
    var noEvents = false
    var events = ""
    /// Intraoperative echo: the structured findings, and anything else as text.
    var intraopEcho = PatientEcho()
    var echo = ""
    /// The TEE screen's checklist answers (PatientTEE).
    var teeScreen = PatientTEEScreen()
    /// Intraoperative lab sets (PatientIntraop); the handoff shows the most recent.
    var intraopLabs: [IntraopLabSet] = []
    /// Case timers (CaseTimers): antibiotic doses, heparin, ACTs, protamine and lab checks, each with its time.
    var timers = CaseTimers()
    /// Major intraoperative considerations (IntraopConsiderations.flags) and anything else, for the handoff.
    var considerations: Set<String> = []
    var considerationsNote = ""
    /// Code status and its perioperative plan (PatientCodeStatus, after the ASA's DNR guidelines).
    var codeStatus: CodeStatus?
    var codeStatusLimits = ""
    var codeStatusPlan: CodeStatusPlan?
    var codeStatusPlanNote = ""
    var polst = false

    // Plan
    var disposition: String?
    var painPlan = ""
    /// Monitoring and when to call.
    var callIf = ""
    var todos = ""

    /// What one part of the record filled in another (1.9), so a link takes back only what it added.
    var fills = PatientFills()

    // 1.9 Preprocedure tab and Summary & Handoff
    /// Cardiopulmonary evaluation's "Intrathoracic procedure": nil not asked, false No, true Yes.
    var intrathoracicProcedure: Bool?
    /// The preprocedure summary was generated (its + Generate button); it then follows the record.
    var preopSummaryOn = false
    /// Text the user changed in the generated preprocedure summary and handoff, by block key; a block with an edit keeps
    /// it until Regenerate.
    var preopSummaryEdits: [String: String] = [:]
    var handoffEdits: [String: String] = [:]

    init() {}

    /// Every field read with a fallback, so a record saved by an older version still opens after an update.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        version = v(.version, 1)
        updated = try? c.decodeIfPresent(Date.self, forKey: .updated)
        ageYears = (try? c.decodeIfPresent(Double.self, forKey: .ageYears)).map { Swift.min($0, PatientRecord.oldestAge) }
        sex = try? c.decodeIfPresent(PatientSex.self, forKey: .sex)
        heightCm = try? c.decodeIfPresent(Double.self, forKey: .heightCm)
        weightKg = try? c.decodeIfPresent(Double.self, forKey: .weightKg)
        procedure = v(.procedure, "")
        procedures = v(.procedures, [])
        urgency = try? c.decodeIfPresent(PatientUrgency.self, forKey: .urgency)
        anesthetic = v(.anesthetic, [])
        highRiskSurgery = v(.highRiskSurgery, false)
        incision = try? c.decodeIfPresent(String.self, forKey: .incision)
        duration = try? c.decodeIfPresent(String.self, forKey: .duration)
        vitals = v(.vitals, [:])
        noHistory = v(.noHistory, false)
        problems = PatientCatalog.migratedProblems(v(.problems, []))
        aortaSizes = v(.aortaSizes, [:])
        hx = v(.hx, PatientHistoryDetails())
        systemNotes = v(.systemNotes, [:])
        systemOther = v(.systemOther, [:])
        otherHistory = v(.otherHistory, "")
        smoking = try? c.decodeIfPresent(String.self, forKey: .smoking)
        nkda = v(.nkda, false)
        allergies = v(.allergies, "")
        allergyList = v(.allergyList, [])
        medications = v(.medications, "")
        homeMeds = v(.homeMeds, [])
        medFlags = v(.medFlags, [])
        anesthesiaHistory = v(.anesthesiaHistory, [])
        anesthesiaNotes = v(.anesthesiaNotes, "")
        lastSolids = try? c.decodeIfPresent(Date.self, forKey: .lastSolids)
        lastClears = try? c.decodeIfPresent(Date.self, forKey: .lastClears)
        labs = v(.labs, [:])
        labNotes = v(.labNotes, "")
        typeScreen = v(.typeScreen, PatientTypeScreen())
        infections = v(.infections, PatientInfections())
        labProblems = v(.labProblems, Set<String>()).intersection(problems)
        surgeries = v(.surgeries, [])
        homeInfusions = v(.homeInfusions, [])
        ascites = try? c.decodeIfPresent(LiverAscites.self, forKey: .ascites)
        encephalopathy = try? c.decodeIfPresent(LiverEncephalopathy.self, forKey: .encephalopathy)
        dialysis = v(.dialysis, false)
        labSections = v(.labSections, [])
        mets = try? c.decodeIfPresent(String.self, forKey: .mets)
        dasi = v(.dasi, [])
        activeCardiac = v(.activeCardiac, [])
        cardiacSymptoms = v(.cardiacSymptoms, [])
        cardiacSymptomsAnswer = try? c.decodeIfPresent(Bool.self, forKey: .cardiacSymptomsAnswer)
        activeCardiacAnswer = try? c.decodeIfPresent(Bool.self, forKey: .activeCardiacAnswer)
        intrathoracic = v(.intrathoracic, [])
        ecg = v(.ecg, [])
        ecgNotes = v(.ecgNotes, "")
        echoFindings = v(.echoFindings, PatientEcho())
        lhc = v(.lhc, PatientLHC())
        rhc = v(.rhc, PatientRHC())
        carotid = v(.carotid, PatientCarotid())
        radial = v(.radial, PatientRadial())
        pft = v(.pft, PatientPFT())
        frail = v(.frail, false)
        asaClass = try? c.decodeIfPresent(Int.self, forKey: .asaClass)
        asaE = try? c.decodeIfPresent(Bool.self, forKey: .asaE)
        scores = v(.scores, [:])
        mallampati = try? c.decodeIfPresent(Int.self, forKey: .mallampati)
        airwaySigns = v(.airwaySigns, [])
        dentition = v(.dentition, "")
        airwayNotes = v(.airwayNotes, "")
        examNotes = v(.examNotes, "")
        airwayExamReviewed = v(.airwayExamReviewed, false)
        currentAirway = try? c.decodeIfPresent(String.self, forKey: .currentAirway)
        ettSize = v(.ettSize, "")
        ettDepth = v(.ettDepth, "")
        trachType = v(.trachType, "")
        vent = v(.vent, PatientVent())
        oxygen = v(.oxygen, PatientOxygen())
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
        devices = v(.devices, [])
        limbAlerts = v(.limbAlerts, [])
        if !c.contains(.devices) && !lines.isEmpty {
            devices = lines.map { l in var d = PatientDevice(line: l); d.placedIntraop = true; return d }
            lines = []
        }
        regional = v(.regional, [])
        infusions = v(.infusions, [])
        fluids = v(.fluids, [:])
        factors = v(.factors, "")
        medsGiven = v(.medsGiven, "")
        noEvents = v(.noEvents, false)
        events = v(.events, "")
        intraopEcho = v(.intraopEcho, PatientEcho())
        echo = v(.echo, "")
        teeScreen = v(.teeScreen, PatientTEEScreen())
        intraopLabs = v(.intraopLabs, [])
        timers = v(.timers, CaseTimers())
        considerations = v(.considerations, [])
        considerationsNote = v(.considerationsNote, "")
        codeStatus = try? c.decodeIfPresent(CodeStatus.self, forKey: .codeStatus)
        codeStatusLimits = v(.codeStatusLimits, "")
        codeStatusPlan = try? c.decodeIfPresent(CodeStatusPlan.self, forKey: .codeStatusPlan)
        codeStatusPlanNote = v(.codeStatusPlanNote, "")
        polst = v(.polst, false)
        disposition = try? c.decodeIfPresent(String.self, forKey: .disposition)
        painPlan = v(.painPlan, "")
        callIf = v(.callIf, "")
        todos = v(.todos, "")
        fills = v(.fills, PatientFills())
        intrathoracicProcedure = try? c.decodeIfPresent(Bool.self, forKey: .intrathoracicProcedure)
        preopSummaryOn = v(.preopSummaryOn, false)
        preopSummaryEdits = v(.preopSummaryEdits, [:])
        handoffEdits = v(.handoffEdits, [:])
        fills.problems.formIntersection(problems)
        fills.medFlags.formIntersection(medFlags)
        fills.ecg.formIntersection(Set(ecg))
        // Saved before 1.9 (which saves the fills on every record), "aki" also meant ESRD not on scheduled dialysis.
        if !c.contains(.fills), problems.contains("aki") { hx.akiBefore19 = true }
        PatientHistoryDetails.migrate(&self)
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

    /// The oldest age kept: 90 stands for 90 or older.
    static let oldestAge = 90.0

    /// "62", or "90 or older" for 90 and over.
    static func ageText(_ years: Double) -> String { years >= oldestAge ? "90 or older" : NumText.short(years) }
    /// The age field's unit: "90 or older" reads as the number and this.
    static func ageFieldUnit(_ years: Double?) -> String { (years ?? 0) >= oldestAge ? "or older" : "years" }

    /// "62-year-old man", "4-year-old girl", "Woman, 90 or older", "Woman", "": the opening of the one-liner.
    var person: String {
        let noun: String? = sex.map { s in isChild ? (s == .male ? "boy" : "girl") : s.noun }
        guard let a = ageYears else { return noun.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "" }
        if a >= Self.oldestAge { return noun.map { $0.prefix(1).uppercased() + $0.dropFirst() + ", 90 or older" } ?? "90 or older" }
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

    /// Arrives with an ETT or a tracheostomy: no airway examination or intraoperative airway course to record.
    var arrivesWithAirway: Bool { currentAirway == "ett" || currentAirway == "trach" }
    /// Anything recorded in the airway examination: the Mallampati class, a sign, the teeth, or the exam marked
    /// reviewed. Without it the full handoff says the exam was not assessed.
    var airwayExamTouched: Bool {
        mallampati != nil || !airwaySigns.isEmpty || !dentition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || airwayExamReviewed
    }
    /// Cardiac or thoracic operations from the surgical history and those added in the cardiac evaluation.
    var allIntrathoracic: [PatientSurgery] { surgeries.filter(\.intrathoracic) + intrathoracic }
    var hasCardiacSymptoms: Bool { cardiacSymptomsAnswer == true || !cardiacSymptoms.isEmpty }
    var hasActiveCardiac: Bool { activeCardiacAnswer == true || !activeCardiac.isEmpty }
    /// Devices in place now (not removed); on arrival only, for the preoperative picture.
    func currentDevices(arrivalOnly: Bool = false) -> [PatientDevice] { devices.filter { !$0.removed && (!arrivalOnly || !$0.placedIntraop) } }
    /// IABP, Impella, LVAD and ECMO cannulas in place.
    var mechanicalSupport: [PatientDevice] { currentDevices().filter { PatientDevice.supportKinds.contains($0.kind) } }
    /// "7.5 ETT at 23 cm at the lip", "Tracheostomy (Shiley 8 cuffed)", "Own airway".
    var currentAirwayText: String? {
        switch currentAirway {
        case "ett": return ["ETT" + (ettSize.isEmpty ? "" : " " + ettSize), ettDepth.isEmpty ? nil : "at " + ettDepth].compactMap { $0 }.joined(separator: " ")
        case "trach": return "Tracheostomy" + (trachType.isEmpty ? "" : " (" + trachType + ")")
        case "natural": return "Own airway"
        default: return nil
        }
    }
}
