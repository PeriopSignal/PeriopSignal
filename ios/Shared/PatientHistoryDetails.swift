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

    // Renal
    /// "aki" saved before 1.9, when it was "Acute kidney injury, or ESRD not on scheduled dialysis" (a note's "ESRD, not
    /// on dialysis" filed it): which of the two is not known, so it keeps that wording (akiLabel) until it is taken off.
    var akiBefore19 = false

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
        akiBefore19 = v(.akiBefore19, false)
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
        case "arrhythmia": return !d.arrhythmiaType.isEmpty || d.afType != nil
        case "device": return !d.deviceDetails.isEmpty || d.pacerDependent || d.ciedSide != nil
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

    /// Choosing the item alone: its base problem, when it has one. Smoking and Alcohol are answered, not filed: never
    /// smoked and no alcohol are the ASA I example ("healthy, non-smoking, no or minimal alcohol use"), so opening them
    /// leaves "No significant medical history" as it is (an alcohol answer that is a problem clears it: setAlcohol).
    static func select(_ s: HistorySection, _ r: inout PatientRecord) {
        if s.id != "smoking" && s.id != "alcohol" { r.noHistory = false }
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
        out += valveWords(r)
        if p.contains("af") { out.append((d.afType.flatMap { afTypeWords[$0] }.map { $0 + " " } ?? "") + "AF") }
        if p.contains("arrhythmia") { out.append("other arrhythmia" + paren(d.arrhythmiaType)) }
        let devices = [p.contains("pacemaker") ? "pacemaker" : nil, p.contains("icd") ? "ICD" : nil].compactMap { $0 }
        // 1.9: pacer dependence and the generator's side ("pacemaker, pacer dependent, left-sided generator").
        var device = devices.joined(separator: " and ")
        if device.isEmpty && (d.pacerDependent || d.ciedSide != nil || !trimmed(d.deviceDetails).isEmpty) { device = "pacemaker or ICD" }
        if !device.isEmpty {
            if d.pacerDependent { device += ", pacer dependent" }
            if let side = d.ciedSide { device += ", " + side + "-sided generator" }
            out.append(device + paren(d.deviceDetails))
        }
        if p.contains("pulm-htn-severe") { out.append("pulmonary hypertension, severe") }
        else if p.contains("pulm-htn") { out.append("pulmonary hypertension" + (d.pulmHtnSeverity.map { ", " + $0 } ?? "")) }
        if let aorta = aortaWords(r) { out.append(aorta) }
        if p.contains("pvd") { out.append("peripheral vascular disease" + paren(d.pvdDetails)) }
        if p.contains("chd") || p.contains("chd-elevated") {
            out.append("congenital heart disease" + (p.contains("chd-elevated") ? ", complex lesion" : "") + paren(d.chdDetails))
        }
        let surgery = PatientHistoryDetails.cardiacSurgeryDisplay(r)
        if !trimmed(surgery).isEmpty { out.append("previous cardiac surgery: " + trimmed(surgery)) }
        return out
    }

    /// Each valve lesion in a few words ("aortic stenosis severe", "mitral prosthetic (mechanical 27 mm)"): the
    /// Cardiovascular summary, and the Musculoskeletal connective-tissue item's cross-reference (1.9).
    static func valveWords(_ r: PatientRecord) -> [String] {
        let d = r.hx
        var out: [String] = []
        for (v, name) in PatientHistoryDetails.valveNames {
            let x = d.valve(v)
            if x.stenosis { out.append(name.lowercased() + " stenosis" + (x.stenosisGrade.map { " " + $0 } ?? "")) }
            if x.regurgitation { out.append(name.lowercased() + " regurgitation" + (x.regurgitationGrade.map { " " + $0 } ?? "")) }
            if x.prosthetic { out.append(name.lowercased() + " prosthetic" + paren(x.prosthesis)) }
        }
        if d.prosthesisUnplaced { out.append("prosthetic valve, position not recorded") }
        if d.severeUnplaced, !d.anySevereLesion { out.append("severe valve disease, valve not recorded") }
        return out
    }

    /// The Aortopathy item in a few words ("aortopathy: ascending aneurysm 4.8 cm, type B dissection"), or nil.
    static func aortaWords(_ r: PatientRecord) -> String? {
        let p = r.problems, d = r.hx
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
        return aorta.isEmpty ? nil : "aortopathy: " + aorta.joined(separator: ", ")
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
        if let pleural = pleuralWords(r) { out.append(pleural) }
        return out
    }

    /// "left hemothorax, drained, chest tube left"; nil when nothing is recorded (1.9).
    static func pleuralWords(_ r: PatientRecord) -> String? {
        let p = r.problems, d = r.hx
        var kinds: [String] = []
        if p.contains("pleural-effusion") {
            switch d.pleuralFluid {
            case "hemothorax": kinds.append("hemothorax")
            case "chylothorax": kinds.append("chylothorax")
            default: kinds.append("pleural effusion")
            }
        }
        if p.contains("pneumothorax") { kinds.append("pneumothorax") }
        guard !kinds.isEmpty || d.pleuralSide != nil || d.pleuralDrained != nil else { return nil }
        var t = (d.pleuralSide.map { $0 + " " } ?? "") + (kinds.isEmpty ? "pleural effusion or pneumothorax" : kinds.joined(separator: " and "))
        if d.pleuralDrained == true {
            t += ", drained"
            if d.chestTube == true {
                let sides = ["left", "right"].filter(d.chestTubeSides.contains)
                t += ", chest tube" + (sides.isEmpty ? " in place" : " " + sides.joined(separator: " and "))
            }
        } else if d.pleuralDrained == false {
            t += ", not drained"
        }
        return t
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
        // 1.9. The unstable cervical spine is listed under Musculoskeletal, its home.
        if p.contains("visual-impairment") { out.append("visual impairment" + (r.hx.visualImpairment.map { ", " + $0 } ?? "")) }
        let psych = [p.contains("mdd") ? "MDD" : nil, p.contains("anxiety") ? "anxiety" : nil, nonEmpty(r.hx.psychOther)].compactMap { $0 }
        if !psych.isEmpty { out.append("psychological disorder: " + psych.joined(separator: ", ")) }
        else if p.contains("psych") { out.append("psychological disorder") }
        return out
    }

    // MARK: 1.9 pages in a few words. Each id is listed once, under its home system (PatientCatalog.system(of:)): an
    // item shown on two pages (isShared) is left out of the page it is only shown on.

    /// "CKD stage 3b; ESRD on hemodialysis M/W/F (left forearm fistula)".
    static func renalItems(_ r: PatientRecord) -> [String] {
        let p = r.problems, d = r.hx
        var out: [String] = []
        if p.contains("ckd") { out.append("CKD" + (d.ckdStage.map { " stage " + $0 } ?? "")) }
        if p.contains("esrd-no-dialysis") { out.append("ESRD not on scheduled dialysis") }
        if p.contains("aki") { out.append(d.akiBefore19 ? "AKI or ESRD not on scheduled dialysis" : "AKI") }
        if p.contains("bph") { out.append("BPH") }
        if p.contains("prostate-cancer") { out.append("prostate cancer") }
        if p.contains("esrd-dialysis") {
            let days = d.dialysisSchedule.flatMap { s in dialysisSchedules.first { $0.id == s }?.label } ?? nonEmpty(d.dialysisScheduleOther)
            var access: [String] = []
            if d.dialysisAccess.contains("fistula") { access.append((nonEmpty(d.fistulaSite).map { $0 + " " } ?? "") + "fistula") }
            if d.dialysisAccess.contains("catheter") { access.append((nonEmpty(d.dialysisCatheterSite).map { $0 + " " } ?? "") + "dialysis catheter") }
            out.append("ESRD on hemodialysis" + (days.map { " " + $0 } ?? "") + paren(access.joined(separator: ", ")))
        }
        return out
    }

    /// "GERD; prior gastric bypass (Roux-en-Y 2018); GI bleed, upper, resolved".
    static func giItems(_ r: PatientRecord) -> [String] {
        let p = r.problems, d = r.hx
        var out: [String] = []
        if p.contains("gerd") { out.append("GERD") }
        if p.contains("gastric-bypass") { out.append("prior gastric bypass" + paren(d.gastricBypassDetails)) }
        var esophagus: [String] = []
        if p.contains("dysphagia") { esophagus.append("dysphagia") }
        if p.contains("esophageal-disorder") { esophagus.append("esophageal disorder" + paren(d.esophagealDisorderType)) }
        if d.esophagealProcedure == true { esophagus.append("previous esophageal procedure" + paren(d.esophagealProcedureDetails)) }
        if !esophagus.isEmpty { out.append(esophagus.joined(separator: ", ")) }
        if p.contains("hiatal-hernia") { out.append("hiatal hernia") }
        if p.contains("varices") { out.append("esophageal varices") }
        if p.contains("cirrhosis") { out.append("cirrhosis") }
        if p.contains("hepatitis-active") { out.append("active hepatitis") }
        if p.contains("gastroparesis") { out.append("gastroparesis") }
        if p.contains("gi-bleed") {
            let parts = [d.giBleedSite, d.giBleedStatus].compactMap { $0 }
            out.append((["GI bleed"] + parts).joined(separator: ", ") + paren(d.giBleedDetails))
        }
        if p.contains("full-stomach") { out.append("full stomach or bowel obstruction") }
        return out
    }

    /// "diabetes on insulin; hypothyroidism; chronic steroids (prednisolone 10 mg/day, 1 month or more)".
    static func endoItems(_ r: PatientRecord) -> [String] {
        let p = r.problems, d = r.hx
        var out: [String] = []
        if p.contains("insulin") { out.append("diabetes on insulin") }
        else if p.contains("dm") { out.append("diabetes" + (d.dmNoInsulin ? ", not on insulin" : "")) }
        if p.contains("thyroid") {
            switch d.thyroidType {
            case "hypo": out.append("hypothyroidism")
            case "hyper": out.append("hyperthyroidism")
            default: out.append("thyroid disease")
            }
        }
        if p.contains("adrenal") {
            let kinds = adrenalKinds.filter { d.adrenalKinds.contains($0.id) }.map { $0.label.lowercased() }
            let drug = nonEmpty(d.steroidDrug).map { PatientSteroids.drugs.contains($0) ? $0.lowercased() : $0 }
            let dose = [drug, d.steroidDailyMg.map { NumText.short($0) + " mg/day" }].compactMap { $0 }.joined(separator: " ")
            let duration = d.steroidDuration.flatMap { s in PatientSteroids.durations.first { $0.id == s }?.label.lowercased() }
            let detail = [dose.isEmpty ? nil : dose, duration].compactMap { $0 }.joined(separator: ", ")
            out.append((kinds.isEmpty ? "adrenal insufficiency or chronic steroids" : kinds.joined(separator: " and ")) + paren(detail))
        }
        return out
    }

    /// "anemia; thrombophilia (factor V Leiden); on anticoagulation: heparin, therapeutic, last dose 08:00".
    static func hemeItems(_ r: PatientRecord) -> [String] {
        let p = r.problems, d = r.hx
        var out: [String] = []
        if p.contains("anemia") { out.append("anemia") }
        if p.contains("thrombocytopenia") { out.append("thrombocytopenia") }
        let bleeding = bleedingKinds.filter { p.contains($0.id) }.map(\.words) + [nonEmpty(d.bleedingOther)].compactMap { $0 }
        if !bleeding.isEmpty { out.append("bleeding disorder: " + bleeding.joined(separator: ", ")) }
        else if p.contains("bleeding") { out.append("bleeding disorder or coagulopathy") }
        if p.contains("thrombophilia-heme") || p.contains("fvl") {
            let kinds = [p.contains("fvl") ? "factor V Leiden" : nil, nonEmpty(d.thrombophiliaOther)].compactMap { $0 }
            out.append("thrombophilia" + paren(kinds.joined(separator: ", ")))
        }
        if p.contains("anticoagulation") {
            let drugs = anticoagulantKinds.compactMap { k -> String? in
                guard let a = d.anticoagulants[k.id] else { return nil }
                let name = k.id == "other" ? (nonEmpty(a.name) ?? "other") : k.label.lowercased()
                return ([name, a.intensity] + [nonEmpty(a.lastDose).map { "last dose " + $0 }]).compactMap { $0 }.joined(separator: ", ")
            }
            out.append("on anticoagulation" + (drugs.isEmpty ? "" : ": " + drugs.joined(separator: "; ")))
        }
        if p.contains("declines-blood") { out.append("declines blood products" + paren(d.declinesBloodDetails)) }
        if p.contains("vte") { out.append((["DVT/PE", d.vteTiming, nonEmpty(d.vteDate)].compactMap { $0 }).joined(separator: ", ")) }
        if p.contains("sickle") { out.append("sickle cell disease") }
        return out
    }

    /// "MRSA or VRE; HIV (viral load undetectable); COVID-19, active, positive 11/01; isolation precautions: contact".
    /// Sepsis (Acute illness), URI and pneumonia (Respiratory) are listed under their own systems.
    static func infectiousItems(_ r: PatientRecord) -> [String] {
        let p = r.problems, d = r.hx
        var out: [String] = []
        if p.contains("mdro") { out.append("MRSA or VRE") }
        if p.contains("hiv") { out.append("HIV" + paren(nonEmpty(d.hivViralLoad).map { "viral load " + $0 } ?? "")) }
        if p.contains("hepatitis-viral") {
            let types = hepatitisTypes.filter { d.hepatitisTypes.contains($0.id) }.map(\.label)
            out.append(types.isEmpty ? "viral hepatitis" : "hepatitis " + types.joined(separator: " and "))
        }
        if p.contains("covid-recent") {
            out.append((["COVID-19", d.covidStatus, nonEmpty(d.covidTestDate).map { "positive " + $0 }].compactMap { $0 }).joined(separator: ", "))
        }
        if p.contains("c-diff") { out.append("C. difficile") }
        if p.contains("tb") { out.append("tuberculosis" + (d.tbStatus.map { ", " + $0 } ?? "")) }
        if p.contains("endocarditis") { out.append("infective endocarditis" + paren(d.endocarditisDetails)) }
        if p.contains("infection-active") { out.append("active infection") }
        if p.contains("isolation") {
            let kinds = PatientPrecautions.kinds.filter { d.precautions.contains($0.id) }.map { $0.label.lowercased() }
            out.append("isolation precautions" + (kinds.isEmpty ? "" : ": " + kinds.joined(separator: ", ")))
        }
        return out
    }

    /// "sepsis, source pneumonia, on cefepime; mixed shock: cardiogenic, distributive; massive trauma".
    static func acuteItems(_ r: PatientRecord) -> [String] {
        let p = r.problems, d = r.hx
        var out: [String] = []
        if p.contains("sepsis") {
            out.append((["sepsis", nonEmpty(d.sepsisSource).map { "source " + $0 }, nonEmpty(d.sepsisAntibiotic).map { "on " + $0 }].compactMap { $0 })
                .joined(separator: ", "))
        }
        if p.contains("shock") { out.append(shockWords(d.shockTypes)) }
        let trauma = [p.contains("massive-trauma") ? "massive trauma" : nil, p.contains("burn") ? "major burn" : nil].compactMap { $0 }
        if !trauma.isEmpty || !trimmed(d.traumaDetails).isEmpty {
            out.append((trauma.isEmpty ? "trauma or burn" : trauma.joined(separator: " and ")) + paren(d.traumaDetails))
        }
        if p.contains("ruptured-aneurysm") { out.append("ruptured abdominal or thoracic aneurysm") }
        return out
    }

    /// "shock", "cardiogenic shock", or two or more: "mixed shock: cardiogenic, distributive" (Ben's wording).
    static func shockWords(_ types: Set<String>) -> String {
        let t = shockTypes.filter { types.contains($0.id) }.map { $0.label.lowercased() }
        switch t.count {
        case 0: return "shock"
        case 1: return t[0] + " shock"
        default: return "mixed shock: " + t.joined(separator: ", ")
        }
    }

    /// "G2P1A0L1, 32+4 weeks, prior cesarean (last birth); preeclampsia with severe features: AKI, HELLP syndrome".
    static func obItems(_ r: PatientRecord) -> [String] {
        let p = r.problems, d = r.hx
        var out: [String] = []
        if p.contains("pregnant") {
            let gpal = [("G", d.gravida), ("P", d.para), ("A", d.abortus), ("L", d.living)].compactMap { l, n in n.map { l + String($0) } }.joined()
            var parts: [String] = [gpal.isEmpty ? "pregnant" : gpal]
            if let w = d.gestationWeeks { parts.append(String(w) + (d.gestationDays.map { "+" + String($0) } ?? "") + " weeks") }
            if d.priorCesarean == true {
                parts.append("prior cesarean" + (d.cesareanLastBirth == true ? " (last birth)" : (d.cesareanLastBirth == false ? " (not the last birth)" : "")))
            } else if d.priorCesarean == false {
                parts.append("no prior cesarean")
            }
            out.append(parts.joined(separator: ", "))
        }
        if p.contains("gest-htn") { out.append("gestational hypertension, controlled") }
        if p.contains("preeclampsia-severe") || p.contains("hellp") || !d.preeclampsiaFeatures.isEmpty {
            let f = preeclampsiaFeatures.filter { d.preeclampsiaFeatures.contains($0.id) || ($0.id == "hellp" && p.contains("hellp")) }.map(\.words)
            out.append("preeclampsia with severe features" + (f.isEmpty ? "" : ": " + f.joined(separator: ", ")))
        } else if p.contains("preeclampsia") {
            out.append("preeclampsia without severe features")
        }
        if p.contains("gdm") || p.contains("gdm-diet") || p.contains("gdm-complex") { out.append("gestational diabetes" + gdmDetail(r)) }
        if p.contains("ppcm") || p.contains("peripartum-cm") {
            var t = "peripartum cardiomyopathy"
            if let ef = d.ppcmEF { t += ", LVEF " + NumText.short(ef) + "%" } else if p.contains("peripartum-cm") { t += ", EF below 40%" }
            out.append(t)
        }
        if p.contains("previa-accreta") {
            let k = placentaKinds.filter { d.placenta.contains($0.id) }.map { $0.label.lowercased() }
            out.append("placenta " + (k.isEmpty ? "previa or accreta" : k.joined(separator: " and ")))
        }
        if p.contains("uterine-rupture") { out.append("uterine rupture, active") }
        if p.contains("uterine-rupture-past") { out.append("past uterine rupture") }
        if p.contains("thrombophilia") { out.append("on anticoagulation for thrombophilia") }
        return out
    }

    /// ", uncontrolled, on insulin" (or ", diet-controlled" as saved before 1.9).
    private static func gdmDetail(_ r: PatientRecord) -> String {
        let p = r.problems, d = r.hx
        let parts = [p.contains("gdm-diet") ? "diet-controlled" : d.gdmControl, d.gdmInsulin ? "on insulin" : nil,
                     p.contains("gdm-complex") ? "complications or high insulin needs" : nil].compactMap { $0 }
        return parts.isEmpty ? "" : ", " + parts.joined(separator: ", ")
    }

    /// "rheumatoid arthritis (hands); unstable C-spine; Marfan syndrome, valve disease or aortopathy".
    static func mskItems(_ r: PatientRecord) -> [String] {
        let p = r.problems, d = r.hx
        var out: [String] = []
        let arthritis = [p.contains("ra") ? "rheumatoid arthritis" : nil, p.contains("oa") ? "osteoarthritis" : nil].compactMap { $0 }
        let location = arthritisUnspecified(d) ? "" : d.arthritisLocation
        if !arthritis.isEmpty || !trimmed(location).isEmpty { out.append((arthritis.isEmpty ? "arthritis" : arthritis.joined(separator: " and ")) + paren(location)) }
        if p.contains("spine-fusion") { out.append("ankylosing spondylitis or cervical fusion") }
        if p.contains("cspine-unstable") { out.append("unstable C-spine") }
        if p.contains("scoliosis") { out.append("scoliosis") }
        if p.contains("fracture") { out.append("fracture" + paren(d.fractureLocation)) }
        if p.contains("muscular-dystrophy") { out.append("muscular dystrophy") }
        let ctd = [p.contains("marfan") ? "Marfan syndrome" : nil, p.contains("eds") ? "Ehlers-Danlos syndrome" : nil].compactMap { $0 }
        if !ctd.isEmpty || d.ctdCardiovascular != nil {
            let cv = d.ctdCardiovascular.map { $0 ? ", valve disease or aortopathy" : ", no valve disease or aortopathy" } ?? ""
            out.append((ctd.isEmpty ? "connective tissue disorder" : ctd.joined(separator: " and ")) + cv)
        }
        if p.contains("compartment-syndrome") { out.append("compartment syndrome" + paren(d.compartmentLocation)) }
        return out
    }

    /// The arthritis location left unspecified on purpose (the Unspecified chip).
    static func arthritisUnspecified(_ d: PatientHistoryDetails) -> Bool { trimmed(d.arthritisLocation).lowercased() == "unspecified" }

    /// "former smoker, quit 2015, 20 pack-years; social alcohol use; illicit drug use: cocaine". Smoking is said here
    /// only (PatientSummary.historyLines no longer adds it).
    static func socialItems(_ r: PatientRecord) -> [String] {
        let p = r.problems, d = r.hx
        var out: [String] = []
        if let s = smokingWords(r) { out.append(s) }
        if p.contains("alcohol-abuse") { out.append("current alcohol dependence or abuse") }
        else if p.contains("alcohol-abuse-former") { out.append("former alcohol dependence or abuse") }
        else if p.contains("alcohol-social") { out.append("social alcohol use") }
        else if d.alcoholNone { out.append("no alcohol use") }
        let drugs = HistorySections.drugs.filter { p.contains($0.id) }.map { $0.label.lowercased() } + [nonEmpty(d.drugsOther)].compactMap { $0 }
        if !drugs.isEmpty { out.append("illicit drug use: " + drugs.joined(separator: ", ")) }
        else if p.contains("substance") { out.append("illicit drug use") }
        return out
    }

    /// "never smoked", "former smoker, quit 2015, 20 pack-years", "current smoker, 30 pack-years"; nil not recorded.
    static func smokingWords(_ r: PatientRecord) -> String? {
        let d = r.hx
        let pack = d.packYears.map { NumText.short($0) + " pack-years" }
        switch r.smoking {
        case "never": return "never smoked"
        case "former": return (["former smoker", d.smokingQuitYear.map { "quit " + String($0) }, pack].compactMap { $0 }).joined(separator: ", ")
        case "current": return (["current smoker", pack].compactMap { $0 }).joined(separator: ", ")
        default: return nil
        }
    }

    /// The items a summary lists for a system: the expanding pages' own words, else the problems' labels.
    static func items(_ sys: PatientSystem, _ r: PatientRecord) -> [String] {
        switch sys.id {
        case "cv": return cvItems(r)
        case "resp": return respItems(r)
        case "neuro": return neuroItems(r)
        case "renal": return renalItems(r)
        case "gi": return giItems(r)
        case "endo": return endoItems(r)
        case "heme": return hemeItems(r)
        case "infectious": return infectiousItems(r)
        case "acute": return acuteItems(r)
        case "ob": return obItems(r)
        case "msk": return mskItems(r)
        case "social": return socialItems(r)
        default: return sys.problems.filter { r.problems.contains($0.id) }.map(\.label)
        }
    }

    private static func nonEmpty(_ s: String) -> String? { trimmed(s).isEmpty ? nil : trimmed(s) }

    // MARK: Cross-references (1.9): shown on a page, never filed there

    /// What the Obstetric page records that belongs on another system's page (display only: no problem id is added,
    /// so nothing changes the ASA): CV gestational hypertension, preeclampsia, peripartum cardiomyopathy; Hematologic
    /// thrombocytopenia and HELLP; Respiratory pulmonary edema; Neurologic headache or visual changes; Renal AKI;
    /// Endocrine gestational diabetes.
    static func fromObstetric(_ system: String, _ r: PatientRecord) -> [String] {
        let p = r.problems, f = r.hx.preeclampsiaFeatures
        var out: [String] = []
        switch system {
        case "cv":
            if p.contains("gest-htn") { out.append("gestational hypertension") }
            if p.contains("preeclampsia-severe") || p.contains("hellp") || !f.isEmpty { out.append("preeclampsia with severe features") }
            else if p.contains("preeclampsia") { out.append("preeclampsia without severe features") }
            if p.contains("ppcm") || p.contains("peripartum-cm") {
                out.append("peripartum cardiomyopathy" + (r.hx.ppcmEF.map { ", LVEF " + NumText.short($0) + "%" } ?? ""))
            }
        case "heme":
            if f.contains("thrombocytopenia") { out.append("thrombocytopenia (preeclampsia)") }
            if f.contains("hellp") || p.contains("hellp") { out.append("HELLP syndrome") }
        case "resp":
            if f.contains("pulm-edema") { out.append("pulmonary edema (preeclampsia)") }
        case "neuro":
            if f.contains("neuro") { out.append("headache or visual changes (preeclampsia)") }
        case "renal":
            if f.contains("aki") { out.append("AKI (preeclampsia)") }
        case "endo":
            if p.contains("gdm") || p.contains("gdm-diet") || p.contains("gdm-complex") { out.append("gestational diabetes" + gdmDetail(r)) }
        default: break
        }
        return out
    }

    /// The Cardiovascular page's ruptured aneurysms, shown on Acute illness instead of a second entry
    /// ("ruptured abdominal aneurysm").
    static func fromCardiovascular(_ r: PatientRecord) -> [String] {
        let order = PatientHistoryDetails.aneurysmSites.map(\.id) + [PatientHistoryDetails.unplacedThoracic.id]
        return order.filter { r.hx.aneurysms[$0]?.ruptured == true }.map { "ruptured " + PatientHistoryDetails.siteWords($0) + " aneurysm" }
    }

    /// For a connective tissue disorder with valve disease or aortopathy: the Cardiovascular page's valve and aorta
    /// words, as recorded there.
    static func cvValveAortaWords(_ r: PatientRecord) -> [String] { valveWords(r) + [aortaWords(r)].compactMap { $0 } }
}

// MARK: - 1.9 options and the edits the pages make (view-free, so the tests use them)

extension HistorySections {
    typealias Option = (id: String, label: String)

    static let afTypes: [Option] = [("paroxysmal", "Paroxysmal"), ("persistent", "Persistent"), ("longstanding", "Long-standing persistent"), ("permanent", "Permanent")]
    static let afTypeWords: [String: String] = ["paroxysmal": "paroxysmal", "persistent": "persistent", "longstanding": "long-standing persistent", "permanent": "permanent"]
    static let leftRight: [Option] = [("left", "Left"), ("right", "Right")]
    static let pleuralSides: [Option] = [("left", "Left"), ("right", "Right"), ("bilateral", "Bilateral")]
    static let pleuralFluids: [Option] = [("unspecified", "Unspecified"), ("hemothorax", "Hemothorax"), ("chylothorax", "Chylothorax")]
    static let acuteChronic: [Option] = [("acute", "Acute"), ("chronic", "Chronic")]
    static let ckdStages: [Option] = [("1", "1"), ("2", "2"), ("3a", "3a"), ("3b", "3b"), ("4", "4"), ("5", "5")]
    static let dialysisSchedules: [Option] = [("mwf", "M/W/F"), ("tts", "Tu/Th/Sa")]
    static let dialysisAccesses: [Option] = [("fistula", "Fistula"), ("catheter", "Dialysis catheter")]
    static let giBleedStatuses: [Option] = [("active", "Active"), ("resolved", "Resolved")]
    static let giBleedSites: [Option] = [("upper", "Upper"), ("lower", "Lower")]
    static let thyroidTypes: [Option] = [("hypo", "Hypothyroid"), ("hyper", "Hyperthyroid")]
    static let adrenalKinds: [Option] = [("insufficiency", "Adrenal insufficiency"), ("steroids", "Chronic steroids")]
    /// Bleeding disorders: the chip, and the summary's words.
    static let bleedingKinds: [(id: String, label: String, words: String)] = [
        ("vwd", "von Willebrand disease", "von Willebrand disease"), ("hemophilia-a", "Hemophilia A", "hemophilia A"),
        ("hemophilia-b", "Hemophilia B", "hemophilia B"), ("dic", "DIC", "DIC"),
    ]
    static let anticoagulantKinds: [Option] = [("heparin", "Heparin"), ("warfarin", "Warfarin"), ("enoxaparin", "Enoxaparin"), ("other", "Other")]
    static let intensities: [Option] = [("therapeutic", "Therapeutic"), ("prophylaxis", "Prophylaxis")]
    static let hepatitisTypes: [Option] = [("a", "A"), ("b", "B"), ("c", "C")]
    static let covidStatuses: [Option] = [("active", "Active"), ("recent", "Recent")]
    static let tbStatuses: [Option] = [("active", "Active"), ("latent", "Latent")]
    static let shockTypes: [Option] = [("cardiogenic", "Cardiogenic"), ("distributive", "Distributive"), ("obstructive", "Obstructive"), ("hypovolemic", "Hypovolemic")]
    /// Preeclampsia's severe features: the chip, and the summary's words.
    static let preeclampsiaFeatures: [(id: String, label: String, words: String)] = [
        ("neuro", "Headache/visual changes", "headache or visual changes"), ("aki", "AKI", "AKI"),
        ("thrombocytopenia", "Thrombocytopenia", "thrombocytopenia"), ("pulm-edema", "Pulmonary edema", "pulmonary edema"),
        ("hellp", "HELLP syndrome", "HELLP syndrome"),
    ]
    static let gdmControls: [Option] = [("controlled", "Controlled"), ("uncontrolled", "Uncontrolled")]
    static let placentaKinds: [Option] = [("previa", "Previa"), ("accreta", "Accreta")]
    static let smokingStatuses: [Option] = [("never", "Never"), ("former", "Former"), ("current", "Current")]
    static let alcoholAnswers: [Option] = [("none", "None"), ("social", "Social"), ("former", "Former dependence/abuse"), ("current", "Current dependence/abuse")]
    static let drugs: [Option] = [("cocaine", "Cocaine"), ("opioid-use", "Opioids"), ("marijuana", "Marijuana"), ("methamphetamine", "Methamphetamine")]

    /// Smoking never, former or current (nil clears it): a quit year only for a former smoker, pack-years for either.
    static func setSmoking(_ s: String?, _ r: inout PatientRecord) {
        r.smoking = s
        if s != "former" { r.hx.smokingQuitYear = nil }
        if s != "former" && s != "current" { r.hx.packYears = nil }
    }

    /// Alcohol, one answer: "none" (hx.alcoholNone), "social", "former", "current" (problem ids), nil not recorded.
    static func alcohol(_ r: PatientRecord) -> String? {
        if r.has("alcohol-abuse") { return "current" }
        if r.has("alcohol-abuse-former") { return "former" }
        if r.has("alcohol-social") { return "social" }
        return r.hx.alcoholNone ? "none" : nil
    }

    static func setAlcohol(_ a: String?, _ r: inout PatientRecord) {
        r.problems.subtract(["alcohol-social", "alcohol-abuse", "alcohol-abuse-former"])
        r.hx.alcoholNone = a == "none"
        switch a {
        case "social": r.problems.insert("alcohol-social")
        case "former": r.problems.insert("alcohol-abuse-former")
        case "current": r.problems.insert("alcohol-abuse")
        default: break
        }
        // No alcohol is part of ASA I's "healthy" (select): only an answer that files a problem clears No significant
        // medical history.
        if a != nil && a != "none" { r.noHistory = false }
    }

    /// Diabetes on insulin ("insulin", the "insulin" problem beside "dm") or not ("none", hx.dmNoInsulin); nil neither.
    static func diabetesInsulin(_ r: PatientRecord) -> String? { r.has("insulin") ? "insulin" : (r.hx.dmNoInsulin ? "none" : nil) }

    static func setDiabetesInsulin(_ v: String?, _ r: inout PatientRecord) {
        r.problems.insert("dm")
        if v == "insulin" { r.problems.insert("insulin") } else { r.problems.remove("insulin") }
        r.hx.dmNoInsulin = v == "none"
        r.noHistory = false
    }

    /// Peripartum cardiomyopathy's LVEF: below 40% is the ASA's class IV example ("peripartum-cm"); otherwise, or with
    /// no EF typed, the item is "ppcm" (LVEF < 45%, ESC HFA 2019), which carries no class.
    static func setPPCMEF(_ ef: Double?, _ r: inout PatientRecord) {
        r.hx.ppcmEF = ef
        if let ef, ef < 40 { r.problems.remove("ppcm"); r.problems.insert("peripartum-cm") }
        else { r.problems.remove("peripartum-cm"); r.problems.insert("ppcm") }
        r.noHistory = false
    }

    /// Preeclampsia without ("without": "preeclampsia", ASA II) or with severe features ("with": "preeclampsia-severe",
    /// ASA III); nil clears the item. Without severe features drops the features (and HELLP).
    static func preeclampsiaSeverity(_ r: PatientRecord) -> String? {
        if r.has("preeclampsia-severe") || r.has("hellp") || !r.hx.preeclampsiaFeatures.isEmpty { return "with" }
        return r.has("preeclampsia") ? "without" : nil
    }

    static func setPreeclampsiaSeverity(_ v: String?, _ r: inout PatientRecord) {
        r.problems.subtract(["preeclampsia", "preeclampsia-severe"])
        if v == "with" { r.problems.insert("preeclampsia-severe") }
        else {
            r.problems.remove("hellp")
            r.hx.preeclampsiaFeatures = []
            if v == "without" { r.problems.insert("preeclampsia") }
        }
        r.noHistory = false
    }

    /// The severe features; HELLP among them is also the "hellp" problem (the ASA's class IV example).
    static func setPreeclampsiaFeatures(_ f: Set<String>, _ r: inout PatientRecord) {
        r.hx.preeclampsiaFeatures = f
        r.problems.remove("preeclampsia")
        r.problems.insert("preeclampsia-severe")
        if f.contains("hellp") { r.problems.insert("hellp") } else { r.problems.remove("hellp") }
        r.noHistory = false
    }

    /// Thrombophilia in pregnancy on anticoagulation: Yes adds the ASA's obstetric example ("thrombophilia", class III)
    /// beside the disease; No takes it off.
    static func setObThrombophiliaAnticoag(_ v: Bool?, _ r: inout PatientRecord) {
        r.hx.obThrombophiliaAnticoag = v == true ? nil : v
        r.problems.insert("thrombophilia-heme")
        if v == true { r.problems.insert("thrombophilia") } else { r.problems.remove("thrombophilia") }
        r.noHistory = false
    }

    static func obThrombophiliaAnticoag(_ r: PatientRecord) -> Bool? { r.has("thrombophilia") ? true : r.hx.obThrombophiliaAnticoag }

    /// One anticoagulant on or off (On anticoagulation stays chosen).
    static func setAnticoagulant(_ kind: String, _ on: Bool, _ r: inout PatientRecord) {
        r.problems.insert("anticoagulation")
        if on { if r.hx.anticoagulants[kind] == nil { r.hx.anticoagulants[kind] = PatientAnticoagulant() } }
        else { r.hx.anticoagulants[kind] = nil }
        r.noHistory = false
    }

    /// Sepsis with shock (Yes adds the Shock item; No takes it off, with its types).
    static func setSepsisShock(_ v: Bool, _ r: inout PatientRecord) {
        r.problems.insert("sepsis")
        if v { r.problems.insert("shock") } else { r.problems.remove("shock"); r.hx.shockTypes = [] }
        r.noHistory = false
    }

    /// The pleural item's answers, each clearing what hangs from it: the fluid goes with the effusion, the chest tube
    /// with drainage, its sides with it.
    static func setPleuralDrained(_ v: Bool?, _ r: inout PatientRecord) {
        r.hx.pleuralDrained = v
        if v != true { r.hx.chestTube = nil; r.hx.chestTubeSides = [] }
    }

    static func setChestTube(_ v: Bool?, _ r: inout PatientRecord) {
        r.hx.chestTube = v
        if v != true { r.hx.chestTubeSides = [] }
    }

    /// The dialysis access: a site typed for an access taken off goes with it.
    static func setDialysisAccess(_ a: Set<String>, _ r: inout PatientRecord) {
        r.hx.dialysisAccess = a
        if !a.contains("fistula") { r.hx.fistulaSite = "" }
        if !a.contains("catheter") { r.hx.dialysisCatheterSite = "" }
        r.problems.insert("esrd-dialysis")
        r.noHistory = false
    }
}
