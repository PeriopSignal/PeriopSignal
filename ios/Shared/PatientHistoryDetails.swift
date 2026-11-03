import Foundation

// MARK: - History details beside the problem ids (1.8.1)
//
// The Cardiovascular, Respiratory and (1.8.2) Neurologic pages are expanding sections: a top item, and its options under it once chosen.
// The problem ids stay the record of what the patient has (PatientRecord.problems), so the ASA suggestion, the RCRI,
// STOP-BANG, ARISCAT and the AHA/ACC evaluation read them as before. What the ids cannot hold sits here: each valve's
// lesions and grades, each aneurysm by its location, the typed details. A few ids follow from these details and are
// kept in step by `sync` ("valve-severe" from a severe lesion; the aneurysm ids from the aneurysms by location), and
// a record saved before 1.8.1 is moved into them by `migrate`.

/// One valve's lesions: stenosis and regurgitation with a grade ("mild", "moderate", "severe"; nil not graded), and a
/// prosthesis with what was typed about it.
struct PatientValve: Codable, Hashable {
    var stenosis = false
    var stenosisGrade: String?
    var regurgitation = false
    var regurgitationGrade: String?
    var prosthetic = false
    var prosthesis = ""

    init(stenosis: Bool = false, stenosisGrade: String? = nil, regurgitation: Bool = false, regurgitationGrade: String? = nil,
         prosthetic: Bool = false, prosthesis: String = "") {
        self.stenosis = stenosis; self.stenosisGrade = stenosisGrade; self.regurgitation = regurgitation
        self.regurgitationGrade = regurgitationGrade; self.prosthetic = prosthetic; self.prosthesis = prosthesis
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stenosis = (try? c.decodeIfPresent(Bool.self, forKey: .stenosis)) ?? false
        stenosisGrade = try? c.decodeIfPresent(String.self, forKey: .stenosisGrade)
        regurgitation = (try? c.decodeIfPresent(Bool.self, forKey: .regurgitation)) ?? false
        regurgitationGrade = try? c.decodeIfPresent(String.self, forKey: .regurgitationGrade)
        prosthetic = (try? c.decodeIfPresent(Bool.self, forKey: .prosthetic)) ?? false
        prosthesis = (try? c.decodeIfPresent(String.self, forKey: .prosthesis)) ?? ""
    }

    var isEmpty: Bool { !stenosis && !regurgitation && !prosthetic }
    var severe: Bool { (stenosis && stenosisGrade == "severe") || (regurgitation && regurgitationGrade == "severe") }

    func has(_ lesion: String) -> Bool {
        switch lesion {
        case "stenosis": return stenosis
        case "regurgitation": return regurgitation
        case "prosthetic": return prosthetic
        default: return false
        }
    }

    mutating func set(_ lesion: String, _ on: Bool) {
        switch lesion {
        case "stenosis": stenosis = on; if !on { stenosisGrade = nil }
        case "regurgitation": regurgitation = on; if !on { regurgitationGrade = nil }
        case "prosthetic": prosthetic = on; if !on { prosthesis = "" }
        default: break
        }
    }

    func grade(_ lesion: String) -> String? { lesion == "stenosis" ? stenosisGrade : (lesion == "regurgitation" ? regurgitationGrade : nil) }

    mutating func setGrade(_ lesion: String, _ g: String?) {
        if lesion == "stenosis" { stenosis = true; stenosisGrade = g }
        if lesion == "regurgitation" { regurgitation = true; regurgitationGrade = g }
    }
}

/// An aortic aneurysm at one location: its diameter, whether it has ruptured, and notes.
struct PatientAneurysm: Codable, Hashable {
    var cm: Double?
    var ruptured = false
    var notes = ""

    init(cm: Double? = nil, ruptured: Bool = false, notes: String = "") { self.cm = cm; self.ruptured = ruptured; self.notes = notes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cm = try? c.decodeIfPresent(Double.self, forKey: .cm)
        ruptured = (try? c.decodeIfPresent(Bool.self, forKey: .ruptured)) ?? false
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
    }
}

/// One anticoagulant on the Hematologic page (1.9): heparin's intensity, the last dose as typed, and a name for Other.
/// Warfarin's last INR is the record's INR (PatientRecord.labs["inr"]), so it is entered once.
struct PatientAnticoagulant: Codable, Hashable {
    /// Heparin (and enoxaparin): "therapeutic" or "prophylaxis".
    var intensity: String?
    /// As typed: "yesterday 08:00", "11/02 21:00".
    var lastDose = ""
    /// Other: the drug, as typed ("apixaban 5 mg BID").
    var name = ""

    init(intensity: String? = nil, lastDose: String = "", name: String = "") { self.intensity = intensity; self.lastDose = lastDose; self.name = name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intensity = try? c.decodeIfPresent(String.self, forKey: .intensity)
        lastDose = (try? c.decodeIfPresent(String.self, forKey: .lastDose)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
    }
}

struct PatientHistoryDetails: Codable, Hashable {
    // Cardiovascular
    /// Heart failure marked compensated (decompensated is the "hf-decomp" problem).
    var hfCompensated = false
    /// By valve: "aortic", "mitral", "tricuspid".
    var valves: [String: PatientValve] = [:]
    /// A prosthetic valve saved before 1.8.1, whose position was never recorded ("prosthetic-valve").
    var prosthesisUnplaced = false
    /// Severe valve disease saved before 1.8.1 (or a severe pulmonic lesion), with no valve recorded: keeps its ASA IV.
    var severeUnplaced = false
    /// Other arrhythmia: its type, as typed.
    var arrhythmiaType = ""
    /// Pacemaker or ICD: dependence, make, magnet response.
    var deviceDetails = ""
    /// "mild" or "moderate"; severe is the "pulm-htn-severe" problem.
    var pulmHtnSeverity: String?
    /// By location (PatientHistoryDetails.aneurysmSites): "root", "arch", "descending", "thoracoabdominal", "abdominal";
    /// "thoracic" for a thoracic aneurysm whose location was not recorded.
    var aneurysms: [String: PatientAneurysm] = [:]
    /// Prior aortic repair: the details (a complex EVAR's type, the year).
    var repairDetails = ""
    var pvdDetails = ""
    var chdDetails = ""
    /// Previous cardiac surgery: the entry it keeps in the past surgical history (its text is that entry's name).
    var cardiacSurgeryID: UUID?

    // Respiratory
    var asthmaControlled = false
    /// Sleep apnea, not on CPAP (CPAP or BiPAP is the "cpap" problem).
    var osaNoCPAP = false
    /// CPAP or BiPAP home settings ("CPAP 10", "BiPAP 14/8").
    var cpapSettings = ""
    /// Other respiratory infection: its type.
    var respInfectionType = ""
    /// Home oxygen flow, L/min.
    var homeO2Flow: Double?

    // MARK: 1.9 (Ben's Wanted Changes): what the new pages hold beside their problem ids. Every field has a fallback
    // when a record saved before 1.9 opens; nothing here needs a migration.

    // Cardiovascular
    /// AF/flutter: "paroxysmal", "persistent", "longstanding" (long-standing persistent), "permanent" (2023 ACC/AHA/ACCP/HRS).
    var afType: String?
    /// Pacemaker or ICD: the patient is pacer dependent (a paced rhythm is filed on the ECG: PatientCrossFill).
    var pacerDependent = false
    /// The generator's side, "left" or "right", for the diagram; nil not recorded.
    var ciedSide: String?
    /// Infective endocarditis: the valve and organism, as typed.
    var endocarditisDetails = ""

    // Respiratory
    /// Pleural effusion or pneumothorax: "left", "right", "bilateral".
    var pleuralSide: String?
    /// The fluid of an effusion: "unspecified", "hemothorax", "chylothorax".
    var pleuralFluid: String?
    /// Drained: nil not asked, false No, true Yes.
    var pleuralDrained: Bool?
    /// A chest tube in place (asked when drained): nil not asked, false No, true Yes.
    var chestTube: Bool?
    /// Its side or sides: "left", "right".
    var chestTubeSides: Set<String> = []

    // Neurologic
    /// Visual impairment: "acute" or "chronic".
    var visualImpairment: String?
    /// Psychological disorder: anything beyond depression and anxiety, as typed.
    var psychOther = ""

    // Renal
    /// CKD stage, KDIGO's GFR categories: "1", "2", "3a", "3b", "4", "5".
    var ckdStage: String?
    /// Hemodialysis days: "mwf" (Mon/Wed/Fri), "tts" (Tue/Thu/Sat); nil with a typed schedule or none recorded.
    var dialysisSchedule: String?
    var dialysisScheduleOther = ""
    /// The dialysis access: "fistula" (an AV fistula or graft), "catheter".
    var dialysisAccess: Set<String> = []
    /// Where each is, as typed ("left forearm", "right IJ tunneled"); placed on the diagram when it can be read.
    var fistulaSite = ""
    var dialysisCatheterSite = ""

    // GI & liver
    var gastricBypassDetails = ""
    /// Esophageal disorder: its type, as typed ("achalasia", "stricture").
    var esophagealDisorderType = ""
    /// Previous esophageal procedure: nil not asked, false No, true Yes; what it was (stent, dilation, resection).
    var esophagealProcedure: Bool?
    var esophagealProcedureDetails = ""
    /// GI bleed: "active" or "resolved"; "upper" or "lower"; anything else.
    var giBleedStatus: String?
    var giBleedSite: String?
    var giBleedDetails = ""

    // Endocrine
    /// Diabetes marked not on insulin (on insulin is the "insulin" problem).
    var dmNoInsulin = false
    /// Thyroid disease: "hypo" or "hyper".
    var thyroidType: String?
    /// Adrenal insufficiency or chronic steroids: "insufficiency", "steroids" (either or both).
    var adrenalKinds: Set<String> = []
    /// The glucocorticoid, as picked or typed ("prednisolone", "hydrocortisone").
    var steroidDrug = ""
    /// Its total daily dose, mg.
    var steroidDailyMg: Double?
    /// How long: "lt1m" (under 1 month) or "ge1m" (1 month or more), the threshold of the 2020 UK perioperative
    /// guideline (Woodcock T, et al. Anaesthesia 2020;75:654–663).
    var steroidDuration: String?

    // Hematologic
    /// Bleeding disorder, Other: as typed.
    var bleedingOther = ""
    /// Thrombophilia, Other: as typed ("prothrombin G20210A", "antiphospholipid syndrome").
    var thrombophiliaOther = ""
    /// On anticoagulation, by drug: "heparin", "warfarin", "enoxaparin", "other".
    var anticoagulants: [String: PatientAnticoagulant] = [:]
    /// Declines blood products: what is and is not accepted, as typed.
    var declinesBloodDetails = ""
    /// DVT/PE: "acute" or "chronic", and the date as typed.
    var vteTiming: String?
    var vteDate = ""

    // Infectious and acute illness
    /// Sepsis: the source, as typed (shown on both pages).
    var sepsisSource = ""
    /// Sepsis: the antibiotic, as typed (also listed with the medications: PatientCrossFill).
    var sepsisAntibiotic = ""
    /// HIV viral load, as typed ("undetectable", "<20 copies/mL").
    var hivViralLoad = ""
    /// Viral hepatitis: "a", "b", "c".
    var hepatitisTypes: Set<String> = []
    /// COVID-19: "active" or "recent"; the positive test's date as typed.
    var covidStatus: String?
    var covidTestDate = ""
    /// Tuberculosis: "active" (pulmonary or laryngeal) or "latent".
    var tbStatus: String?
    /// Isolation precautions: "contact", "droplet", "airborne".
    var precautions: Set<String> = []
    /// Shock: "cardiogenic", "distributive", "obstructive", "hypovolemic"; two or more read as mixed shock.
    var shockTypes: Set<String> = []
    /// Massive trauma or burn: as typed.
    var traumaDetails = ""

    // Obstetric
    /// G, P, A, L.
    var gravida: Int?
    var para: Int?
    var abortus: Int?
    var living: Int?
    /// Weeks (and days) of gestation.
    var gestationWeeks: Int?
    var gestationDays: Int?
    /// Prior cesarean delivery, and whether it was the last birth: nil not asked, false No, true Yes.
    var priorCesarean: Bool?
    var cesareanLastBirth: Bool?
    /// Preeclampsia with severe features: "neuro" (headache or visual changes), "aki", "thrombocytopenia", "pulm-edema",
    /// "hellp" (HELLP is also the "hellp" problem). Shown on the matching system pages (OB cross-references).
    var preeclampsiaFeatures: Set<String> = []
    /// Gestational diabetes: "controlled" or "uncontrolled"; on insulin.
    var gdmControl: String?
    var gdmInsulin = false
    /// Peripartum cardiomyopathy: the LVEF, %; below 40 is the ASA's class IV example ("peripartum-cm").
    var ppcmEF: Double?
    /// Placenta: "previa", "accreta".
    var placenta: Set<String> = []
    /// Thrombophilia in pregnancy, anticoagulated: nil not asked, false No; Yes is the "thrombophilia" problem.
    var obThrombophiliaAnticoag: Bool?

    // Musculoskeletal
    var arthritisLocation = ""
    var fractureLocation = ""
    /// Marfan or Ehlers-Danlos: valve disease or aortopathy? nil not asked, false No, true Yes (recorded on the
    /// Cardiovascular page).
    var ctdCardiovascular: Bool?
    var compartmentLocation = ""

    // Smoking & substances (smoking itself is PatientRecord.smoking)
    var smokingQuitYear: Int?
    /// Estimated pack-years.
    var packYears: Double?
    /// Alcohol: none (the other answers are problem ids).
    var alcoholNone = false
    /// Illicit drug use, Other: as typed.
    var drugsOther = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        hfCompensated = v(.hfCompensated, false)
        valves = v(.valves, [:])
        prosthesisUnplaced = v(.prosthesisUnplaced, false)
        severeUnplaced = v(.severeUnplaced, false)
        arrhythmiaType = v(.arrhythmiaType, "")
        deviceDetails = v(.deviceDetails, "")
        pulmHtnSeverity = try? c.decodeIfPresent(String.self, forKey: .pulmHtnSeverity)
        aneurysms = v(.aneurysms, [:])
        repairDetails = v(.repairDetails, "")
        pvdDetails = v(.pvdDetails, "")
        chdDetails = v(.chdDetails, "")
        cardiacSurgeryID = try? c.decodeIfPresent(UUID.self, forKey: .cardiacSurgeryID)
        asthmaControlled = v(.asthmaControlled, false)
        osaNoCPAP = v(.osaNoCPAP, false)
        cpapSettings = v(.cpapSettings, "")
        respInfectionType = v(.respInfectionType, "")
        homeO2Flow = try? c.decodeIfPresent(Double.self, forKey: .homeO2Flow)
        afType = try? c.decodeIfPresent(String.self, forKey: .afType)
        pacerDependent = v(.pacerDependent, false)
        ciedSide = try? c.decodeIfPresent(String.self, forKey: .ciedSide)
        endocarditisDetails = v(.endocarditisDetails, "")
        pleuralSide = try? c.decodeIfPresent(String.self, forKey: .pleuralSide)
        pleuralFluid = try? c.decodeIfPresent(String.self, forKey: .pleuralFluid)
        pleuralDrained = try? c.decodeIfPresent(Bool.self, forKey: .pleuralDrained)
        chestTube = try? c.decodeIfPresent(Bool.self, forKey: .chestTube)
        chestTubeSides = v(.chestTubeSides, [])
        visualImpairment = try? c.decodeIfPresent(String.self, forKey: .visualImpairment)
        psychOther = v(.psychOther, "")
        ckdStage = try? c.decodeIfPresent(String.self, forKey: .ckdStage)
        dialysisSchedule = try? c.decodeIfPresent(String.self, forKey: .dialysisSchedule)
        dialysisScheduleOther = v(.dialysisScheduleOther, "")
        dialysisAccess = v(.dialysisAccess, [])
        fistulaSite = v(.fistulaSite, "")
        dialysisCatheterSite = v(.dialysisCatheterSite, "")
        gastricBypassDetails = v(.gastricBypassDetails, "")
        esophagealDisorderType = v(.esophagealDisorderType, "")
        esophagealProcedure = try? c.decodeIfPresent(Bool.self, forKey: .esophagealProcedure)
        esophagealProcedureDetails = v(.esophagealProcedureDetails, "")
        giBleedStatus = try? c.decodeIfPresent(String.self, forKey: .giBleedStatus)
        giBleedSite = try? c.decodeIfPresent(String.self, forKey: .giBleedSite)
        giBleedDetails = v(.giBleedDetails, "")
        dmNoInsulin = v(.dmNoInsulin, false)
        thyroidType = try? c.decodeIfPresent(String.self, forKey: .thyroidType)
        adrenalKinds = v(.adrenalKinds, [])
        steroidDrug = v(.steroidDrug, "")
        steroidDailyMg = try? c.decodeIfPresent(Double.self, forKey: .steroidDailyMg)
        steroidDuration = try? c.decodeIfPresent(String.self, forKey: .steroidDuration)
        bleedingOther = v(.bleedingOther, "")
        thrombophiliaOther = v(.thrombophiliaOther, "")
        anticoagulants = v(.anticoagulants, [:])
        declinesBloodDetails = v(.declinesBloodDetails, "")
        vteTiming = try? c.decodeIfPresent(String.self, forKey: .vteTiming)
        vteDate = v(.vteDate, "")
        sepsisSource = v(.sepsisSource, "")
        sepsisAntibiotic = v(.sepsisAntibiotic, "")
        hivViralLoad = v(.hivViralLoad, "")
        hepatitisTypes = v(.hepatitisTypes, [])
        covidStatus = try? c.decodeIfPresent(String.self, forKey: .covidStatus)
        covidTestDate = v(.covidTestDate, "")
        tbStatus = try? c.decodeIfPresent(String.self, forKey: .tbStatus)
        precautions = v(.precautions, [])
        shockTypes = v(.shockTypes, [])
        traumaDetails = v(.traumaDetails, "")
        gravida = try? c.decodeIfPresent(Int.self, forKey: .gravida)
        para = try? c.decodeIfPresent(Int.self, forKey: .para)
        abortus = try? c.decodeIfPresent(Int.self, forKey: .abortus)
        living = try? c.decodeIfPresent(Int.self, forKey: .living)
        gestationWeeks = try? c.decodeIfPresent(Int.self, forKey: .gestationWeeks)
        gestationDays = try? c.decodeIfPresent(Int.self, forKey: .gestationDays)
        priorCesarean = try? c.decodeIfPresent(Bool.self, forKey: .priorCesarean)
        cesareanLastBirth = try? c.decodeIfPresent(Bool.self, forKey: .cesareanLastBirth)
        preeclampsiaFeatures = v(.preeclampsiaFeatures, [])
        gdmControl = try? c.decodeIfPresent(String.self, forKey: .gdmControl)
        gdmInsulin = v(.gdmInsulin, false)
        ppcmEF = try? c.decodeIfPresent(Double.self, forKey: .ppcmEF)
        placenta = v(.placenta, [])
        obThrombophiliaAnticoag = try? c.decodeIfPresent(Bool.self, forKey: .obThrombophiliaAnticoag)
        arthritisLocation = v(.arthritisLocation, "")
        fractureLocation = v(.fractureLocation, "")
        ctdCardiovascular = try? c.decodeIfPresent(Bool.self, forKey: .ctdCardiovascular)
        compartmentLocation = v(.compartmentLocation, "")
        smokingQuitYear = try? c.decodeIfPresent(Int.self, forKey: .smokingQuitYear)
        packYears = try? c.decodeIfPresent(Double.self, forKey: .packYears)
        alcoholNone = v(.alcoholNone, false)
        drugsOther = v(.drugsOther, "")
    }

    // MARK: Fixed lists

    static let valveNames: [(id: String, label: String)] = [("aortic", "Aortic"), ("mitral", "Mitral"), ("tricuspid", "Tricuspid")]
    static let lesions: [(id: String, label: String)] = [("stenosis", "Stenosis"), ("regurgitation", "Regurgitation"), ("prosthetic", "Prosthetic")]
    static let grades: [(id: String, label: String)] = [("mild", "Mild"), ("moderate", "Moderate"), ("severe", "Severe")]

    /// Aneurysm locations, in the page's order, with the problem each files under. "thoracic" is not offered: it holds
    /// a thoracic aneurysm saved before 1.8.1, or read from a note, with no location.
    static let aneurysmSites: [(id: String, label: String, problem: String)] = [
        ("root", "Root/ascending", "taa"), ("arch", "Arch", "taa"), ("descending", "Descending thoracic", "taa"),
        ("thoracoabdominal", "Thoracoabdominal", "taaa"), ("abdominal", "Abdominal", "aaa"),
    ]
    static let unplacedThoracic = (id: "thoracic", label: "Thoracic, location not recorded", problem: "taa")
    static let thoracicSites: Set<String> = ["root", "arch", "descending", "thoracic"]
    static let aneurysmProblems: Set<String> = ["aaa", "aaa-ruptured", "taa", "taa-ruptured", "taaa", "taaa-ruptured"]

    static func siteProblem(_ site: String) -> String {
        if site == unplacedThoracic.id { return "taa" }
        return aneurysmSites.first { $0.id == site }?.problem ?? "taa"
    }
    static func siteLabel(_ site: String) -> String {
        site == unplacedThoracic.id ? unplacedThoracic.label : (aneurysmSites.first { $0.id == site }?.label ?? site)
    }
    /// The words before "aneurysm" in a summary.
    static func siteWords(_ site: String) -> String {
        switch site {
        case "root": return "ascending"
        case "arch": return "arch"
        case "descending": return "descending thoracic"
        case "thoracoabdominal": return "thoracoabdominal"
        case "abdominal": return "abdominal"
        default: return "thoracic"
        }
    }

    // MARK: Queries

    /// A valve lesion or prosthesis recorded, or one saved before 1.8.1 without its valve.
    var hasValveDisease: Bool { valves.values.contains { !$0.isEmpty } || prosthesisUnplaced || severeUnplaced }
    /// A native stenosis or regurgitation that is ungraded or moderate: the AHA/ACC "echo if moderate or severe is
    /// suspected" line. A lesion documented as mild does not need the reminder; a severe one has its own line.
    var hasUngradedOrModerateLesion: Bool {
        valves.values.contains { v in
            (v.stenosis && v.stenosisGrade != "mild" && v.stenosisGrade != "severe")
                || (v.regurgitation && v.regurgitationGrade != "mild" && v.regurgitationGrade != "severe")
        }
    }
    var anySevereLesion: Bool { valves.values.contains(where: \.severe) }

    func valve(_ id: String) -> PatientValve { valves[id] ?? PatientValve() }

    mutating func editValve(_ id: String, _ f: (inout PatientValve) -> Void) {
        var v = valve(id)
        f(&v)
        valves[id] = v.isEmpty ? nil : v
    }

    // MARK: Keeping the ids in step

    /// The ids that follow from the details: "valve-severe" from a severe lesion (or one saved without its valve), the
    /// aneurysm ids from the aneurysms by location; a severe pulmonary hypertension drops the mild/moderate grade.
    static func sync(_ r: inout PatientRecord) {
        if r.hx.anySevereLesion || r.hx.severeUnplaced { r.problems.insert("valve-severe") } else { r.problems.remove("valve-severe") }
        r.problems.subtract(aneurysmProblems)
        for (site, a) in r.hx.aneurysms { r.problems.insert(siteProblem(site) + (a.ruptured ? "-ruptured" : "")) }
        if r.problems.contains("pulm-htn-severe") { r.hx.pulmHtnSeverity = nil }
        if let id = r.hx.cardiacSurgeryID, !r.surgeries.contains(where: { $0.id == id }) { r.hx.cardiacSurgeryID = nil }
    }

    /// A record saved before 1.8.1 (or ids a note added): aortic stenosis, mitral regurgitation and a prosthetic valve
    /// become valve details; severe valve disease with no severe lesion keeps its ASA IV as "valve not recorded"; each
    /// aneurysm id without a location becomes one (a thoracic one "location not recorded"), with its saved diameter.
    static func migrate(_ r: inout PatientRecord) {
        if r.problems.remove("as") != nil { r.hx.editValve("aortic") { $0.stenosis = true } }
        if r.problems.remove("mr") != nil { r.hx.editValve("mitral") { $0.regurgitation = true } }
        if r.problems.remove("prosthetic-valve") != nil { r.hx.prosthesisUnplaced = true }
        if r.problems.contains("valve-severe"), !r.hx.anySevereLesion { r.hx.severeUnplaced = true }
        let sizes = r.aortaSizes
        func site(for problem: String) -> String { problem == "aaa" ? "abdominal" : (problem == "taaa" ? "thoracoabdominal" : "thoracic") }
        func sites(of problem: String) -> [String] {
            problem == "taa" ? r.hx.aneurysms.keys.filter { thoracicSites.contains($0) }.sorted() : r.hx.aneurysms.keys.filter { $0 == site(for: problem) }
        }
        for base in ["aaa", "taa", "taaa"] {
            if r.problems.contains(base), !sites(of: base).contains(where: { r.hx.aneurysms[$0]?.ruptured == false }) {
                let s = site(for: base)
                if r.hx.aneurysms[s] == nil { r.hx.aneurysms[s] = PatientAneurysm(cm: sizes[base]) }
            }
            if r.problems.contains(base + "-ruptured"), !sites(of: base).contains(where: { r.hx.aneurysms[$0]?.ruptured == true }) {
                let existing = sites(of: base)
                let s = existing.count == 1 ? existing[0] : site(for: base)
                var a = r.hx.aneurysms[s] ?? PatientAneurysm(cm: sizes[base])
                a.ruptured = true
                r.hx.aneurysms[s] = a
            }
        }
        r.aortaSizes = [:]
        sync(&r)
    }

    // MARK: Previous cardiac surgery

    /// The text of the past surgical history entry that Previous cardiac surgery keeps.
    static func cardiacSurgeryText(_ r: PatientRecord) -> String {
        guard let id = r.hx.cardiacSurgeryID, let s = r.surgeries.first(where: { $0.id == id }) else { return "" }
        return s.name
    }

    /// The same operation for a summary: with its date when the entry has one ("Aortic valve replacement (06/2025)").
    static func cardiacSurgeryDisplay(_ r: PatientRecord) -> String {
        guard let id = r.hx.cardiacSurgeryID, let s = r.surgeries.first(where: { $0.id == id }) else { return "" }
        return s.text
    }

    /// Sets Previous cardiac surgery: its entry in the past surgical history is added (or an entry with the same words
    /// is used, so nothing is listed twice), renamed as it is edited, and removed when it is cleared. The entry is marked
    /// cardiac or thoracic, so it shows under Previous intrathoracic surgery too.
    static func setCardiacSurgery(_ text: String, _ r: inout PatientRecord) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = r.hx.cardiacSurgeryID, let i = r.surgeries.firstIndex(where: { $0.id == id }) {
            if t.isEmpty {
                r.surgeries.remove(at: i)
                r.hx.cardiacSurgeryID = nil
            } else {
                r.surgeries[i].setProcedures([PlannedProcedure(name: text)])
                r.surgeries[i].intrathoracic = true
            }
            return
        }
        guard !t.isEmpty else { r.hx.cardiacSurgeryID = nil; return }
        if let i = r.surgeries.firstIndex(where: { $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(t) == .orderedSame }) {
            r.surgeries[i].intrathoracic = true
            r.hx.cardiacSurgeryID = r.surgeries[i].id
            return
        }
        var s = PatientSurgery(procedures: [PlannedProcedure(name: text)])
        s.intrathoracic = true
        r.surgeries.append(s)
        r.hx.cardiacSurgeryID = s.id
    }
}

// MARK: - The expanding sections

/// One top item of an expanding page: its id, the title shown, the problem it adds when chosen alone (nil for a heading
/// whose options say what the patient has), the problem ids that belong to it, and those that replace the base when
/// chosen (a superseding option, as the note reader files them).
struct HistorySection: Hashable, Identifiable {
    var id: String
    var title: String
    var base: String?
    var members: [String]
    var replacesBase: Set<String> = []
}

enum HistorySections {
    static let cv: [HistorySection] = [
        HistorySection(id: "htn", title: "Hypertension", base: "htn", members: ["htn", "htn-180"], replacesBase: ["htn-180"]),
        HistorySection(id: "hyperlipidemia", title: "Hyperlipidemia", base: "hyperlipidemia", members: ["hyperlipidemia"]),
        HistorySection(id: "cad", title: "CAD", base: "cad", members: ["cad", "mi", "cad-recent", "pci", "pci-recent", "ischemia", "cabg"],
                       replacesBase: ["mi", "cad-recent", "pci", "pci-recent", "ischemia", "cabg"]),
        HistorySection(id: "hf", title: "Heart failure", base: "hf", members: ["hf", "hf-decomp", "ef-moderate", "ef-severe"], replacesBase: ["hf-decomp"]),
        HistorySection(id: "valves", title: "Valve disease", base: nil, members: ["valve-severe"]),
        // The Infectious item, shown here too (1.9): one id, either page.
        HistorySection(id: "endocarditis", title: "Infective endocarditis", base: "endocarditis", members: ["endocarditis"]),
        HistorySection(id: "arrhythmia", title: "Arrhythmia", base: nil, members: ["af", "arrhythmia"]),
        HistorySection(id: "device", title: "Pacemaker / ICD", base: nil, members: ["pacemaker", "icd"]),
        HistorySection(id: "pulm-htn", title: "Pulmonary hypertension", base: "pulm-htn", members: ["pulm-htn", "pulm-htn-severe"], replacesBase: ["pulm-htn-severe"]),
        HistorySection(id: "aorta", title: "Aortopathy", base: nil, members: Array(PatientHistoryDetails.aneurysmProblems).sorted()
                       + ["dissection-a", "dissection-b", "aortic-repair-open", "evar", "tevar"]),
        HistorySection(id: "pvd", title: "Peripheral vascular disease", base: "pvd", members: ["pvd"]),
        HistorySection(id: "chd", title: "Congenital heart disease", base: "chd", members: ["chd", "chd-elevated"], replacesBase: ["chd-elevated"]),
        HistorySection(id: "cardiac-surgery", title: "Previous cardiac surgery", base: nil, members: []),
    ] + closing("cv")

    static let resp: [HistorySection] = [
        HistorySection(id: "asthma", title: "Asthma", base: "asthma", members: ["asthma", "asthma-uncontrolled"], replacesBase: ["asthma-uncontrolled"]),
        HistorySection(id: "copd", title: "COPD", base: "copd", members: ["copd"]),
        HistorySection(id: "osa", title: "OSA", base: "osa", members: ["osa", "cpap"]),
        HistorySection(id: "resp-infection", title: "Respiratory infection", base: nil, members: ["uri", "pneumonia", "resp-infection-other"]),
        HistorySection(id: "ild", title: "Interstitial lung disease", base: "ild", members: ["ild"]),
        HistorySection(id: "home-o2", title: "Home oxygen", base: "home-o2", members: ["home-o2"]),
        HistorySection(id: "pleural", title: "Pleural effusion or pneumothorax", base: nil, members: ["pleural-effusion", "pneumothorax"]),
    ] + closing("resp")

    /// Neurologic (1.8.2). Stroke or TIA keeps "Stroke or TIA, unspecified" (cva-unspec) as the item chosen alone, whose timing
    /// is not recorded; Within 3 months (cva-recent) or Over 3 months (cva) replaces it. An intracranial bleed alone is "ich";
    /// With mass effect (ich-mass) replaces it.
    static let neuro: [HistorySection] = [
        HistorySection(id: "stroke", title: "Stroke or TIA", base: "cva-unspec", members: ["cva-unspec", "cva", "cva-recent"], replacesBase: ["cva", "cva-recent"]),
        HistorySection(id: "ich", title: "Intracranial bleed", base: "ich", members: ["ich", "ich-mass"], replacesBase: ["ich-mass"]),
        HistorySection(id: "raised-icp", title: "Intracranial mass or raised ICP", base: "raised-icp", members: ["raised-icp"]),
        HistorySection(id: "seizure", title: "Seizure disorder", base: "seizure", members: ["seizure"]),
        HistorySection(id: "dementia", title: "Dementia or cognitive impairment", base: "dementia", members: ["dementia"]),
        HistorySection(id: "parkinson", title: "Parkinson disease", base: "parkinson", members: ["parkinson"]),
        HistorySection(id: "neuromuscular", title: "Neuromuscular disease", base: "neuromuscular", members: ["neuromuscular"]),
        HistorySection(id: "sci", title: "Spinal cord injury", base: "sci", members: ["sci"]),
        HistorySection(id: "chronic-pain", title: "Chronic pain or opioid tolerance", base: "chronic-pain", members: ["chronic-pain"]),
        HistorySection(id: "visual", title: "Visual impairment", base: "visual-impairment", members: ["visual-impairment"]),
        HistorySection(id: "psych", title: "Psychological disorder", base: "psych", members: ["psych", "mdd", "anxiety"]),
        // The Musculoskeletal item, shown here too (1.9).
        HistorySection(id: "cspine", title: "Unstable C-spine", base: "cspine-unstable", members: ["cspine-unstable"]),
    ] + closing("neuro")

    // MARK: 1.9 pages (Ben's Wanted Changes), in his order. Every page ends with Other [system] disorders and Other
    // details (closing(_:)), both always open.

    static let renal: [HistorySection] = [
        HistorySection(id: "ckd", title: "CKD/ESRD", base: "ckd", members: ["ckd", "esrd-no-dialysis"]),
        HistorySection(id: "aki", title: "Acute kidney injury", base: "aki", members: ["aki"]),
        HistorySection(id: "prostate", title: "Prostate disease", base: nil, members: ["bph", "prostate-cancer"]),
        HistorySection(id: "hemodialysis", title: "Hemodialysis", base: "esrd-dialysis", members: ["esrd-dialysis"]),
    ] + closing("renal")

    static let gi: [HistorySection] = [
        HistorySection(id: "gerd", title: "Reflux/GERD", base: "gerd", members: ["gerd"]),
        HistorySection(id: "gastric-bypass", title: "History of gastric bypass", base: "gastric-bypass", members: ["gastric-bypass"]),
        HistorySection(id: "esophageal", title: "Dysphagia or esophageal disorder", base: nil, members: ["dysphagia", "esophageal-disorder"]),
        HistorySection(id: "hiatal-hernia", title: "Hiatal hernia", base: "hiatal-hernia", members: ["hiatal-hernia"]),
        HistorySection(id: "varices", title: "Esophageal varices", base: "varices", members: ["varices"]),
        HistorySection(id: "cirrhosis", title: "Cirrhosis", base: "cirrhosis", members: ["cirrhosis"]),
        // Not in Ben's list; kept, as the ASA's class III example ("active hepatitis").
        HistorySection(id: "hepatitis-active", title: "Active hepatitis", base: "hepatitis-active", members: ["hepatitis-active"]),
        HistorySection(id: "gastroparesis", title: "Gastroparesis", base: "gastroparesis", members: ["gastroparesis"]),
        HistorySection(id: "gi-bleed", title: "GI bleed", base: "gi-bleed", members: ["gi-bleed"]),
        HistorySection(id: "full-stomach", title: "Full stomach or bowel obstruction", base: "full-stomach", members: ["full-stomach"]),
    ] + closing("gi")

    /// Diabetes keeps "dm" with "insulin" beside it (not in its place): the ASA's class II example is read from "dm".
    static let endo: [HistorySection] = [
        HistorySection(id: "dm", title: "Diabetes", base: "dm", members: ["dm", "insulin"]),
        HistorySection(id: "thyroid", title: "Thyroid disease", base: "thyroid", members: ["thyroid"]),
        HistorySection(id: "adrenal", title: "Adrenal insufficiency or chronic steroids", base: "adrenal", members: ["adrenal"]),
    ] + closing("endo")

    static let heme: [HistorySection] = [
        HistorySection(id: "anemia", title: "Anemia", base: "anemia", members: ["anemia"]),
        HistorySection(id: "thrombocytopenia", title: "Thrombocytopenia", base: "thrombocytopenia", members: ["thrombocytopenia"]),
        HistorySection(id: "bleeding", title: "Bleeding disorder or coagulopathy", base: "bleeding",
                       members: ["bleeding", "vwd", "hemophilia-a", "hemophilia-b", "dic"]),
        HistorySection(id: "thrombophilia", title: "Thrombophilia", base: "thrombophilia-heme", members: ["thrombophilia-heme", "fvl"]),
        HistorySection(id: "anticoagulation", title: "On anticoagulation", base: "anticoagulation", members: ["anticoagulation"]),
        HistorySection(id: "declines-blood", title: "Declines blood products", base: "declines-blood", members: ["declines-blood"]),
        HistorySection(id: "vte", title: "DVT/PE", base: "vte", members: ["vte"]),
        // Not in Ben's list; kept from 1.8.
        HistorySection(id: "sickle", title: "Sickle cell disease", base: "sickle", members: ["sickle"]),
    ] + closing("heme")

    /// Sepsis is the Acute illness item and URI and pneumonia the Respiratory ones, shown here with the same ids.
    static let infectious: [HistorySection] = [
        HistorySection(id: "sepsis", title: "Sepsis", base: "sepsis", members: ["sepsis"]),
        HistorySection(id: "mdro", title: "MRSA or VRE", base: "mdro", members: ["mdro"]),
        HistorySection(id: "uri", title: "Upper respiratory tract infection", base: "uri", members: ["uri"]),
        HistorySection(id: "hiv", title: "HIV", base: "hiv", members: ["hiv"]),
        HistorySection(id: "hepatitis", title: "Viral hepatitis", base: "hepatitis-viral", members: ["hepatitis-viral"]),
        HistorySection(id: "covid", title: "COVID-19", base: "covid-recent", members: ["covid-recent"]),
        HistorySection(id: "pneumonia", title: "Pneumonia", base: "pneumonia", members: ["pneumonia"]),
        HistorySection(id: "c-diff", title: "C. difficile", base: "c-diff", members: ["c-diff"]),
        HistorySection(id: "tb", title: "Tuberculosis", base: "tb", members: ["tb"]),
        HistorySection(id: "endocarditis", title: "Infective endocarditis", base: "endocarditis", members: ["endocarditis"]),
        // Not in Ben's list; kept from 1.8.1.
        HistorySection(id: "infection-active", title: "Active infection", base: "infection-active", members: ["infection-active"]),
        HistorySection(id: "isolation", title: "Isolation precautions", base: "isolation", members: ["isolation"]),
    ] + closing("infectious")

    /// Shock is its own item and an option of Sepsis (one id); the dissections are the Cardiovascular page's.
    static let acute: [HistorySection] = [
        HistorySection(id: "sepsis", title: "Sepsis", base: "sepsis", members: ["sepsis"]),
        HistorySection(id: "shock", title: "Shock", base: "shock", members: ["shock"]),
        HistorySection(id: "trauma", title: "Massive trauma or burn", base: nil, members: ["massive-trauma", "burn"]),
        HistorySection(id: "aorta-acute", title: "Aortic dissection or rupture", base: nil, members: ["dissection-a", "dissection-b", "ruptured-aneurysm"]),
    ] + closing("acute")

    /// Thrombophilia is the Hematologic item ("thrombophilia-heme"); anticoagulated in pregnancy adds the ASA's
    /// obstetric example ("thrombophilia") beside it. Peripartum cardiomyopathy alone is "ppcm" (LVEF < 45%); an EF
    /// below 40% replaces it with the ASA's class IV example ("peripartum-cm").
    static let ob: [HistorySection] = [
        HistorySection(id: "pregnant", title: "Pregnant", base: "pregnant", members: ["pregnant"]),
        HistorySection(id: "gest-htn", title: "Gestational hypertension (controlled)", base: "gest-htn", members: ["gest-htn"]),
        HistorySection(id: "preeclampsia", title: "Preeclampsia", base: nil, members: ["preeclampsia", "preeclampsia-severe", "hellp"]),
        HistorySection(id: "gdm", title: "Gestational diabetes", base: "gdm", members: ["gdm", "gdm-diet", "gdm-complex"]),
        HistorySection(id: "ppcm", title: "Peripartum cardiomyopathy (LVEF < 45%)", base: "ppcm", members: ["ppcm", "peripartum-cm"], replacesBase: ["peripartum-cm"]),
        HistorySection(id: "placenta", title: "Placenta previa or accreta", base: "previa-accreta", members: ["previa-accreta"]),
        HistorySection(id: "uterine-rupture", title: "Uterine rupture", base: nil, members: ["uterine-rupture", "uterine-rupture-past"]),
        HistorySection(id: "thrombophilia", title: "Thrombophilia", base: "thrombophilia-heme", members: ["thrombophilia-heme", "thrombophilia"]),
    ] + closing("ob")

    static let msk: [HistorySection] = [
        HistorySection(id: "arthritis", title: "Arthritis", base: nil, members: ["ra", "oa"]),
        HistorySection(id: "spine", title: "Spine disorders", base: nil, members: ["spine-fusion", "cspine-unstable", "scoliosis"]),
        HistorySection(id: "fracture", title: "Fracture", base: "fracture", members: ["fracture"]),
        HistorySection(id: "muscular-dystrophy", title: "Muscular dystrophy", base: "muscular-dystrophy", members: ["muscular-dystrophy"]),
        HistorySection(id: "ctd", title: "Connective tissue disorder", base: nil, members: ["marfan", "eds"]),
        HistorySection(id: "compartment", title: "Compartment syndrome", base: "compartment-syndrome", members: ["compartment-syndrome"]),
    ] + closing("msk")

    /// Smoking is PatientRecord.smoking; alcohol is one answer among none and three problem ids.
    static let social: [HistorySection] = [
        HistorySection(id: "smoking", title: "Smoking", base: nil, members: []),
        HistorySection(id: "alcohol", title: "Alcohol", base: nil, members: ["alcohol-social", "alcohol-abuse", "alcohol-abuse-former"]),
        HistorySection(id: "drugs", title: "Illicit drug use", base: "substance", members: ["substance", "cocaine", "opioid-use", "marijuana", "methamphetamine"]),
    ] + closing("social")

    /// The two items every page ends with (1.9): Other [system] disorders (PatientRecord.systemOther) and Other details
    /// (PatientRecord.systemNotes, the 1.8 "Other"), both free text, capitalized when left.
    static func closing(_ system: String) -> [HistorySection] {
        [HistorySection(id: "other-disorders", title: otherTitle(system), base: nil, members: []),
         HistorySection(id: "other", title: "Other details", base: nil, members: [])]
    }

    /// The first closing item's title, in Ben's words where his list gives them.
    static func otherTitle(_ system: String) -> String {
        switch system {
        case "cv": return "Other cardiovascular disorders"
        case "resp": return "Other respiratory disorders"
        case "neuro": return "Other neurological disorders"
        case "renal": return "Other renal disease"
        case "gi": return "Other GI & liver disease"
        case "endo": return "Other endocrine disorders"
        case "heme": return "Other hematologic disorders"
        case "infectious": return "Other infectious disorders"
        case "acute": return "Other acute illnesses"
        case "ob": return "Other obstetric disorders or concerns"
        case "msk": return "Other musculoskeletal disorders"
        case "social": return "Other substance use"
        default: return "Other disorders"
        }
    }

    /// Items shown on a page whose ids are another system's (one record, two pages): Sepsis, URI and pneumonia on
    /// Infectious, endocarditis on Cardiovascular, the dissections on Acute illness, the unstable cervical spine on
    /// Neurologic, Thrombophilia on Obstetric. The summary lists each under its own system only.
    static func isShared(_ s: HistorySection, on system: String) -> Bool {
        guard let first = (s.base ?? s.members.first), let home = PatientCatalog.system(of: first)?.id else { return false }
        return home != system
    }

    /// The systems drawn as expanding sections.
    static func sections(_ system: String) -> [HistorySection]? {
        switch system {
        case "cv": return cv
        case "resp": return resp
        case "neuro": return neuro
        case "renal": return renal
        case "gi": return gi
        case "endo": return endo
        case "heme": return heme
        case "infectious": return infectious
        case "acute": return acute
        case "ob": return ob
        case "msk": return msk
        case "social": return social
        default: return nil
        }
    }

    /// Anything recorded under the item.
    static func isSelected(_ s: HistorySection, system: String, _ r: PatientRecord) -> Bool {
        if s.members.contains(where: r.problems.contains) { return true }
        let d = r.hx
        switch s.id {
        case "valves": return d.hasValveDisease
        case "arrhythmia": return !d.arrhythmiaType.isEmpty
        case "device": return !d.deviceDetails.isEmpty
        case "aorta": return !d.aneurysms.isEmpty || !d.repairDetails.isEmpty
        case "cardiac-surgery": return !PatientHistoryDetails.cardiacSurgeryText(r).isEmpty
        case "other": return !(r.systemNotes[system] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "other-disorders": return !(r.systemOther[system] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "esophageal": return !trimmed(d.esophagealDisorderType).isEmpty || d.esophagealProcedure != nil
        case "preeclampsia": return !d.preeclampsiaFeatures.isEmpty
        case "trauma": return !trimmed(d.traumaDetails).isEmpty
        case "smoking": return r.smoking != nil || d.smokingQuitYear != nil || d.packYears != nil
        case "alcohol": return d.alcoholNone
        case "pleural": return d.pleuralSide != nil || d.pleuralDrained != nil
        case "arthritis": return !trimmed(d.arthritisLocation).isEmpty
        case "ctd": return d.ctdCardiovascular != nil
        default: return false
        }
    }

    /// Choosing the item alone: its base problem, when it has one.
    static func select(_ s: HistorySection, _ r: inout PatientRecord) {
        r.noHistory = false
        if let b = s.base { r.problems.insert(b) }
    }

    /// Clearing the item: its problems and details (Previous cardiac surgery takes its past-surgery entry with it).
    static func clear(_ s: HistorySection, system: String, _ r: inout PatientRecord) {
        r.problems.subtract(s.members)
        switch s.id {
        case "hf": r.hx.hfCompensated = false
        case "valves": r.hx.valves = [:]; r.hx.prosthesisUnplaced = false; r.hx.severeUnplaced = false
        case "arrhythmia": r.hx.arrhythmiaType = ""; r.hx.afType = nil
        case "device": r.hx.deviceDetails = ""; r.hx.pacerDependent = false; r.hx.ciedSide = nil
        case "pulm-htn": r.hx.pulmHtnSeverity = nil
        case "aorta": r.hx.aneurysms = [:]; r.hx.repairDetails = ""
        case "pvd": r.hx.pvdDetails = ""
        case "chd": r.hx.chdDetails = ""
        case "cardiac-surgery": PatientHistoryDetails.setCardiacSurgery("", &r)
        case "other": r.systemNotes[system] = nil
        case "asthma": r.hx.asthmaControlled = false
        case "osa": r.hx.osaNoCPAP = false; r.hx.cpapSettings = ""
        case "resp-infection": r.hx.respInfectionType = ""
        case "home-o2": r.hx.homeO2Flow = nil
        case "other-disorders": r.systemOther[system] = nil
        // 1.9
        case "endocarditis": r.hx.endocarditisDetails = ""
        case "pleural": r.hx.pleuralSide = nil; r.hx.pleuralFluid = nil; r.hx.pleuralDrained = nil; r.hx.chestTube = nil; r.hx.chestTubeSides = []
        case "visual": r.hx.visualImpairment = nil
        case "psych": r.hx.psychOther = ""
        case "ckd": r.hx.ckdStage = nil
        case "hemodialysis":
            r.hx.dialysisSchedule = nil; r.hx.dialysisScheduleOther = ""; r.hx.dialysisAccess = []
            r.hx.fistulaSite = ""; r.hx.dialysisCatheterSite = ""
        case "gastric-bypass": r.hx.gastricBypassDetails = ""
        case "esophageal": r.hx.esophagealDisorderType = ""; r.hx.esophagealProcedure = nil; r.hx.esophagealProcedureDetails = ""
        case "gi-bleed": r.hx.giBleedStatus = nil; r.hx.giBleedSite = nil; r.hx.giBleedDetails = ""
        case "dm": r.hx.dmNoInsulin = false
        case "thyroid": r.hx.thyroidType = nil
        case "adrenal": r.hx.adrenalKinds = []; r.hx.steroidDrug = ""; r.hx.steroidDailyMg = nil; r.hx.steroidDuration = nil
        case "bleeding": r.hx.bleedingOther = ""
        case "thrombophilia":
            // One disease on two pages: cleared on either, it goes with its Factor V Leiden and its anticoagulation in
            // pregnancy.
            r.problems.subtract(["thrombophilia-heme", "fvl", "thrombophilia"])
            r.hx.thrombophiliaOther = ""; r.hx.obThrombophiliaAnticoag = nil
        case "anticoagulation": r.hx.anticoagulants = [:]
        case "declines-blood": r.hx.declinesBloodDetails = ""
        case "vte": r.hx.vteTiming = nil; r.hx.vteDate = ""
        case "sepsis": r.hx.sepsisSource = ""; r.hx.sepsisAntibiotic = ""
        case "hiv": r.hx.hivViralLoad = ""
        case "hepatitis": r.hx.hepatitisTypes = []
        case "covid": r.hx.covidStatus = nil; r.hx.covidTestDate = ""
        case "tb": r.hx.tbStatus = nil
        case "isolation": r.hx.precautions = []
        case "shock": r.hx.shockTypes = []
        case "trauma": r.hx.traumaDetails = ""
        case "pregnant":
            r.hx.gravida = nil; r.hx.para = nil; r.hx.abortus = nil; r.hx.living = nil; r.hx.gestationWeeks = nil; r.hx.gestationDays = nil
            r.hx.priorCesarean = nil; r.hx.cesareanLastBirth = nil
        case "preeclampsia": r.hx.preeclampsiaFeatures = []
        case "gdm": r.hx.gdmControl = nil; r.hx.gdmInsulin = false
        case "ppcm": r.hx.ppcmEF = nil
        case "placenta": r.hx.placenta = []
        case "arthritis": r.hx.arthritisLocation = ""
        case "fracture": r.hx.fractureLocation = ""
        case "ctd": r.hx.ctdCardiovascular = nil
        case "compartment": r.hx.compartmentLocation = ""
        case "smoking": r.smoking = nil; r.hx.smokingQuitYear = nil; r.hx.packYears = nil
        case "alcohol": r.hx.alcoholNone = false
        case "drugs": r.hx.drugsOther = ""
        default: break
        }
        PatientHistoryDetails.sync(&r)
    }

    /// Turns one option on or off. An option that replaces the base takes its place; when the last one goes, the base
    /// comes back, so the item stays chosen.
    static func setOption(_ id: String, _ on: Bool, in s: HistorySection, _ r: inout PatientRecord) {
        r.noHistory = false
        if on {
            r.problems.insert(id)
            if s.replacesBase.contains(id), let b = s.base { r.problems.remove(b) }
        } else {
            r.problems.remove(id)
            if let b = s.base, !s.members.contains(where: r.problems.contains) { r.problems.insert(b) }
        }
    }

    /// One choice among options (MI within or over 3 months): the others are taken off.
    static func choose(_ id: String?, among ids: [String], in s: HistorySection, _ r: inout PatientRecord) {
        for o in ids where o != id { r.problems.remove(o) }
        if let id { setOption(id, true, in: s, &r) } else { setOption(ids[0], false, in: s, &r) }
    }

    // MARK: Summary

    private static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func paren(_ s: String) -> String { trimmed(s).isEmpty ? "" : " (" + trimmed(s) + ")" }

    /// The Cardiovascular page in a few words, one item per section, for the History list, the summary and the
    /// handoff: "CAD: MI within 3 months, prior CABG; HF, decompensated, EF severely reduced; aortic stenosis severe".
    /// Other (the system's details) is added by the caller.
    static func cvItems(_ r: PatientRecord) -> [String] {
        let p = r.problems, d = r.hx
        var out: [String] = []
        if p.contains("htn") || p.contains("htn-180") {
            out.append("hypertension" + (p.contains("htn-180") ? ", BP ≥ 180/110 before the day of surgery" : ""))
        }
        if p.contains("hyperlipidemia") { out.append("hyperlipidemia") }
        var cad: [String] = []
        if p.contains("cad-recent") { cad.append("MI within 3 months") }
        if p.contains("mi") { cad.append("MI over 3 months") }
        if p.contains("pci-recent") { cad.append("PCI within 3 months") }
        if p.contains("pci") { cad.append("PCI over 3 months") }
        if p.contains("ischemia") { cad.append("ongoing ischemia") }
        if p.contains("cabg") { cad.append("prior CABG") }
        if !cad.isEmpty { out.append("CAD: " + cad.joined(separator: ", ")) } else if p.contains("cad") { out.append("CAD") }
        var hf: [String] = []
        if p.contains("hf") || p.contains("hf-decomp") { hf.append("HF") }
        if p.contains("hf-decomp") { hf.append("decompensated") } else if d.hfCompensated, !hf.isEmpty { hf.append("compensated") }
        if p.contains("ef-severe") { hf.append("EF severely reduced") } else if p.contains("ef-moderate") { hf.append("EF moderately reduced") }
        if !hf.isEmpty { out.append(hf.joined(separator: ", ")) }
        for (v, name) in PatientHistoryDetails.valveNames {
            let x = d.valve(v)
            if x.stenosis { out.append(name.lowercased() + " stenosis" + (x.stenosisGrade.map { " " + $0 } ?? "")) }
            if x.regurgitation { out.append(name.lowercased() + " regurgitation" + (x.regurgitationGrade.map { " " + $0 } ?? "")) }
            if x.prosthetic { out.append(name.lowercased() + " prosthetic" + paren(x.prosthesis)) }
        }
        if d.prosthesisUnplaced { out.append("prosthetic valve, position not recorded") }
        if d.severeUnplaced, !d.anySevereLesion { out.append("severe valve disease, valve not recorded") }
        if p.contains("af") { out.append("AF") }
        if p.contains("arrhythmia") { out.append("other arrhythmia" + paren(d.arrhythmiaType)) }
        let devices = [p.contains("pacemaker") ? "pacemaker" : nil, p.contains("icd") ? "ICD" : nil].compactMap { $0 }
        if !devices.isEmpty { out.append(devices.joined(separator: " and ") + paren(d.deviceDetails)) }
        if p.contains("pulm-htn-severe") { out.append("pulmonary hypertension, severe") }
        else if p.contains("pulm-htn") { out.append("pulmonary hypertension" + (d.pulmHtnSeverity.map { ", " + $0 } ?? "")) }
        var aorta: [String] = []
        let order = PatientHistoryDetails.aneurysmSites.map(\.id) + [PatientHistoryDetails.unplacedThoracic.id]
        for site in order {
            guard let a = d.aneurysms[site] else { continue }
            var t = PatientHistoryDetails.siteWords(site) + " aneurysm" + (a.cm.map { " " + NumText.short($0) + " cm" } ?? "")
            if a.ruptured { t += ", ruptured" }
            aorta.append(t + paren(a.notes))
        }
        if p.contains("dissection-a") { aorta.append("type A dissection") }
        if p.contains("dissection-b") { aorta.append("type B dissection") }
        let repairs = [p.contains("aortic-repair-open") ? "open repair" : nil, p.contains("evar") ? "EVAR" : nil, p.contains("tevar") ? "TEVAR" : nil].compactMap { $0 }
        if !repairs.isEmpty { aorta.append("prior " + repairs.joined(separator: " and ") + paren(d.repairDetails)) }
        else if !trimmed(d.repairDetails).isEmpty { aorta.append("prior repair" + paren(d.repairDetails)) }
        if !aorta.isEmpty { out.append("aortopathy: " + aorta.joined(separator: ", ")) }
        if p.contains("pvd") { out.append("peripheral vascular disease" + paren(d.pvdDetails)) }
        if p.contains("chd") || p.contains("chd-elevated") {
            out.append("congenital heart disease" + (p.contains("chd-elevated") ? ", complex lesion" : "") + paren(d.chdDetails))
        }
        let surgery = PatientHistoryDetails.cardiacSurgeryDisplay(r)
        if !trimmed(surgery).isEmpty { out.append("previous cardiac surgery: " + trimmed(surgery)) }
        return out
    }

    /// The Respiratory page in a few words: "asthma, uncontrolled; COPD; OSA on CPAP/BiPAP (BiPAP 14/8)".
    static func respItems(_ r: PatientRecord) -> [String] {
        let p = r.problems, d = r.hx
        var out: [String] = []
        if p.contains("asthma-uncontrolled") { out.append("asthma, uncontrolled") }
        else if p.contains("asthma") { out.append("asthma" + (d.asthmaControlled ? ", controlled" : "")) }
        if p.contains("copd") { out.append("COPD") }
        if p.contains("cpap") { out.append("OSA on CPAP/BiPAP" + paren(d.cpapSettings)) }
        else if p.contains("osa") { out.append("OSA" + (d.osaNoCPAP ? ", not on CPAP" : "")) }
        var inf: [String] = []
        if p.contains("uri") { inf.append("URI") }
        if p.contains("pneumonia") { inf.append("pneumonia") }
        if p.contains("resp-infection-other") { inf.append(trimmed(d.respInfectionType).isEmpty ? "other" : trimmed(d.respInfectionType)) }
        if !inf.isEmpty { out.append("respiratory infection: " + inf.joined(separator: ", ")) }
        if p.contains("ild") { out.append("interstitial lung disease") }
        if p.contains("home-o2") { out.append("home oxygen" + (d.homeO2Flow.map { " " + NumText.short($0) + " L/min" } ?? "")) }
        return out
    }

    /// The Neurologic page in a few words: "stroke or TIA within 3 months; intracranial bleed with mass effect; seizure disorder".
    static func neuroItems(_ r: PatientRecord) -> [String] {
        let p = r.problems
        var out: [String] = []
        if p.contains("cva-recent") { out.append("stroke or TIA within 3 months") }
        else if p.contains("cva") { out.append("stroke or TIA over 3 months") }
        else if p.contains("cva-unspec") { out.append("stroke or TIA") }
        if p.contains("ich-mass") { out.append("intracranial bleed with mass effect") }
        else if p.contains("ich") { out.append("intracranial bleed") }
        if p.contains("raised-icp") { out.append("intracranial mass or raised ICP") }
        if p.contains("seizure") { out.append("seizure disorder") }
        if p.contains("dementia") { out.append("dementia or cognitive impairment") }
        if p.contains("parkinson") { out.append("Parkinson disease") }
        if p.contains("neuromuscular") { out.append("neuromuscular disease") }
        if p.contains("sci") { out.append("spinal cord injury") }
        if p.contains("chronic-pain") { out.append("chronic pain or opioid tolerance") }
        return out
    }

    /// The items a summary lists for a system: the expanding pages' own words, else the problems' labels.
    static func items(_ sys: PatientSystem, _ r: PatientRecord) -> [String] {
        switch sys.id {
        case "cv": return cvItems(r)
        case "resp": return respItems(r)
        case "neuro": return neuroItems(r)
        default: return sys.problems.filter { r.problems.contains($0.id) }.map(\.label)
        }
    }
}
