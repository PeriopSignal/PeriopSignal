import Foundation

// MARK: - TEE screen: possible difficult or contraindicated transesophageal echocardiography
//
// What could make placing a TEE probe dangerous, read from the record and from a short checklist, and classed as no
// contraindication recorded, relative or absolute, with the reasons.
//
// Sources (each item names its own):
//   - Hahn RT, Abraham T, Adams MS, et al. Guidelines for performing a comprehensive transesophageal echocardiographic
//     examination: recommendations from the American Society of Echocardiography and the Society of Cardiovascular
//     Anesthesiologists. J Am Soc Echocardiogr 2013;26:921-964 (Table 6, p 927, and the safety text beside it).
//     doi:10.1016/j.echo.2013.07.009. This is the ASE/SCA comprehensive TEE guideline (it replaced the 1999 ASE/SCA
//     comprehensive intraoperative multiplane guideline) and the only society table that classes each item as
//     absolute or relative.
//   - Practice guidelines for perioperative transesophageal echocardiography: an updated report by the ASA and the
//     SCA Task Force on Transesophageal Echocardiography. Anesthesiology 2010;112:1084-1096 (Contraindications; Oral,
//     esophageal or gastric disease). doi:10.1097/ALN.0b013e3181c51e90. It found the literature insufficient to set
//     contraindications and reports its survey of consultants and members instead.
//   - Reeves ST, Finley AC, Skubas NJ, et al. Basic perioperative transesophageal echocardiography examination: a
//     consensus statement of the ASE and the SCA. J Am Soc Echocardiogr 2013;26:443-456 (p 453).
//     doi:10.1016/j.echo.2013.02.015.
// The ASE's 2020 surgery-based intraoperative TEE guideline (Nicoara A, et al. J Am Soc Echocardiogr 2020;33:692-734)
// is about cardiac surgery and gives no contraindication list that we found; no ASE/SCA guideline on intraoperative TEE
// in noncardiac surgery was found.
//
// Rules, as applied here:
//   - Hahn's Table 6 sets every class it lists. Radiation, esophageal scleroderma and achalasia are, in Hahn's text,
//     absolute or relative by their severity; the screen counts them as relative (the lower class) and says so.
//   - Esophagectomy or esophagogastrectomy, tracheoesophageal fistula and Zenker diverticulum are not in Hahn's table
//     by name (a Zenker diverticulum is a diverticulum, which Hahn lists as absolute). The ASA/SCA 2010 survey treats
//     them as absolute in the opinion of consultants or members; the screen marks them absolute and the evidence
//     says it is opinion.
//   - What the record states in a structured field counts: problems (esophageal varices, a bleeding disorder or DIC,
//     cervical fusion or an unstable cervical spine; 1.9: a history of gastric bypass as previous upper GI surgery,
//     dysphagia, an active upper GI bleed, von Willebrand disease, hemophilia and thrombocytopenia), airway signs (neck
//     radiation changes, limited neck movement), and esophageal or upper GI operations in the past surgical history.
//     Free text, reflux, cirrhosis, abnormal platelets or INR, and (1.9) a hiatal hernia, an esophageal disorder with
//     its type and previous procedure, a GI bleed that is not active and upper, and a previous EGD's findings are
//     offered to confirm on the checklist, never counted on their own.
//   - Hahn gives no platelet or INR cutoffs, so the labs only prompt the question.

/// The clinician's answers on the TEE screen.
struct PatientTEEScreen: Codable, Hashable {
    /// Checklist items answered Yes and No (PatientTEE.items ids).
    var yes: Set<String> = []
    var no: Set<String> = []
    /// The whole list was asked about: anything not answered Yes is taken as No.
    var reviewed = false
    var notes = ""
    /// Previous EGD (1.9, Ben): nil not asked, false No, true Yes; its date and findings as typed. The findings are read
    /// for items to confirm, as the notes are.
    var previousEGD: Bool?
    var egdDate = ""
    var egdFindings = ""
    /// Previous TEE (1.9, Ben): nil not asked, false No, true Yes; its date as typed.
    var previousTEE: Bool?
    var teeDate = ""

    init(yes: Set<String> = [], no: Set<String> = [], reviewed: Bool = false, notes: String = "",
         previousEGD: Bool? = nil, egdDate: String = "", egdFindings: String = "", previousTEE: Bool? = nil, teeDate: String = "") {
        self.yes = yes; self.no = no; self.reviewed = reviewed; self.notes = notes
        self.previousEGD = previousEGD; self.egdDate = egdDate; self.egdFindings = egdFindings
        self.previousTEE = previousTEE; self.teeDate = teeDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        yes = (try? c.decodeIfPresent(Set<String>.self, forKey: .yes)) ?? []
        no = (try? c.decodeIfPresent(Set<String>.self, forKey: .no)) ?? []
        reviewed = (try? c.decodeIfPresent(Bool.self, forKey: .reviewed)) ?? false
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        previousEGD = try? c.decodeIfPresent(Bool.self, forKey: .previousEGD)
        egdDate = (try? c.decodeIfPresent(String.self, forKey: .egdDate)) ?? ""
        egdFindings = (try? c.decodeIfPresent(String.self, forKey: .egdFindings)) ?? ""
        previousTEE = try? c.decodeIfPresent(Bool.self, forKey: .previousTEE)
        teeDate = (try? c.decodeIfPresent(String.self, forKey: .teeDate)) ?? ""
    }

    private static func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var isEmpty: Bool {
        yes.isEmpty && no.isEmpty && !reviewed && Self.blank(notes)
            && previousEGD == nil && Self.blank(egdDate) && Self.blank(egdFindings) && previousTEE == nil && Self.blank(teeDate)
    }

    /// "Previous EGD 03/2025: LA grade B esophagitis", "No previous EGD"; nil not asked.
    var egdText: String? {
        switch previousEGD {
        case true?:
            let d = egdDate.trimmingCharacters(in: .whitespacesAndNewlines), f = egdFindings.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Previous EGD" + (d.isEmpty ? "" : " " + d) + (f.isEmpty ? "" : ": " + f)
        case false?: return "No previous EGD"
        case nil: return nil
        }
    }

    /// "Previous TEE 2023", "No previous TEE"; nil not asked.
    var teeText: String? {
        switch previousTEE {
        case true?:
            let d = teeDate.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Previous TEE" + (d.isEmpty ? "" : " " + d)
        case false?: return "No previous TEE"
        case nil: return nil
        }
    }

    /// nil not asked, true Yes, false No.
    func answer(_ id: String) -> Bool? { yes.contains(id) ? true : (no.contains(id) ? false : nil) }

    mutating func set(_ id: String, _ value: Bool?) {
        yes.remove(id); no.remove(id)
        if value == true { yes.insert(id) } else if value == false { no.insert(id) }
    }
}

enum TEEClass: Int, Comparable, Hashable {
    case none = 0, relative, absolute
    static func < (a: TEEClass, b: TEEClass) -> Bool { a.rawValue < b.rawValue }
    var label: String {
        switch self {
        case .none: return "No contraindication recorded"
        case .relative: return "Relative contraindication"
        case .absolute: return "Absolute contraindication"
        }
    }
}

enum TEESource: String, Hashable, CaseIterable {
    case hahn2013, asa2010, reeves2013

    /// "ASE/SCA 2013".
    var short: String {
        switch self {
        case .hahn2013: return "ASE/SCA 2013"
        case .asa2010: return "ASA/SCA 2010 survey"
        case .reeves2013: return "ASE/SCA 2013 basic TEE"
        }
    }

    var citation: String {
        switch self {
        case .hahn2013:
            return "Hahn RT, et al. Guidelines for performing a comprehensive transesophageal echocardiographic examination: recommendations from the ASE and the SCA. J Am Soc Echocardiogr 2013;26:921–964 (Table 6). doi:10.1016/j.echo.2013.07.009"
        case .asa2010:
            return "ASA and SCA Task Force on Transesophageal Echocardiography. Practice guidelines for perioperative transesophageal echocardiography. Anesthesiology 2010;112:1084–1096. doi:10.1097/ALN.0b013e3181c51e90"
        case .reeves2013:
            return "Reeves ST, et al. Basic perioperative transesophageal echocardiography examination: a consensus statement of the ASE and the SCA. J Am Soc Echocardiogr 2013;26:443–456. doi:10.1016/j.echo.2013.02.015"
        }
    }

    var url: String {
        switch self {
        case .hahn2013: return "https://doi.org/10.1016/j.echo.2013.07.009"
        case .asa2010: return "https://doi.org/10.1097/ALN.0b013e3181c51e90"
        case .reeves2013: return "https://doi.org/10.1016/j.echo.2013.02.015"
        }
    }
}

/// One checklist item.
struct TEEItem: Hashable, Identifiable {
    var id: String
    var label: String
    /// For joining into a line: "esophageal varices", "previous upper GI surgery".
    var short: String
    var detail: String?
    var level: TEEClass
    var source: TEESource
}

/// A contraindication the record or the checklist shows.
struct TEEFinding: Hashable {
    var item: TEEItem
    /// Where it was found: "Past surgical history: Laparoscopic Nissen fundoplication (2018)", "Checklist".
    var from: [String]
}

/// Something in the record that may be a contraindication, offered on the checklist to confirm.
struct TEESuggestion: Hashable {
    var item: TEEItem
    var why: String
}

struct TEEResult: Hashable {
    /// Absolute first, then relative; the checklist's order within each.
    var findings: [TEEFinding]
    var suggestions: [TEESuggestion]
    var reviewed: Bool

    var level: TEEClass { findings.map(\.item.level).max() ?? .none }
    var absolute: [TEEFinding] { findings.filter { $0.item.level == .absolute } }
    var relative: [TEEFinding] { findings.filter { $0.item.level == .relative } }
    /// Something found, or the whole list asked about.
    var screened: Bool { reviewed || !findings.isEmpty }
    func finding(_ id: String) -> TEEFinding? { findings.first { $0.item.id == id } }
}

enum PatientTEE {

    // MARK: Checklist

    static let items: [TEEItem] = [
        // Absolute: Hahn 2013, Table 6.
        TEEItem(id: "perforated-viscus", label: "Perforated viscus", short: "perforated viscus", level: .absolute, source: .hahn2013),
        TEEItem(id: "stricture", label: "Esophageal stricture", short: "esophageal stricture", level: .absolute, source: .hahn2013),
        TEEItem(id: "tumor", label: "Esophageal tumor", short: "esophageal tumor", level: .absolute, source: .hahn2013),
        TEEItem(id: "perforation", label: "Esophageal perforation or laceration", short: "esophageal perforation or laceration",
                detail: "An acute tear (for example Mallory-Weiss) is a laceration", level: .absolute, source: .hahn2013),
        TEEItem(id: "diverticulum", label: "Esophageal diverticulum, including Zenker", short: "esophageal diverticulum",
                detail: "Zenker: absolute in the ASA/SCA 2010 consultants' view, equivocal among members", level: .absolute, source: .hahn2013),
        TEEItem(id: "ugib-active", label: "Active upper GI bleeding", short: "active upper GI bleeding", level: .absolute, source: .hahn2013),
        // Absolute in the ASA/SCA 2010 survey (opinion), not in Hahn's table by name.
        TEEItem(id: "esophagectomy", label: "Esophagectomy or esophagogastrectomy", short: "esophagectomy",
                detail: "ASA/SCA 2010: named as the exception to \u{201C}no absolute contraindications\u{201D} (survey opinion, not trial evidence)", level: .absolute, source: .asa2010),
        TEEItem(id: "te-fistula", label: "Tracheoesophageal fistula", short: "tracheoesophageal fistula",
                detail: "Absolute in the ASA/SCA 2010 survey (opinion)", level: .absolute, source: .asa2010),
        // Relative: Hahn 2013, Table 6.
        TEEItem(id: "radiation", label: "Radiation to the neck or mediastinum", short: "neck or mediastinal radiation", level: .relative, source: .hahn2013),
        TEEItem(id: "gi-surgery", label: "Previous upper GI surgery", short: "previous upper GI surgery",
                detail: "Esophagus or stomach: fundoplication, hiatal hernia repair, myotomy, bariatric surgery, gastrectomy", level: .relative, source: .hahn2013),
        TEEItem(id: "ugib-recent", label: "Recent upper GI bleeding", short: "recent upper GI bleeding", level: .relative, source: .hahn2013),
        TEEItem(id: "barretts", label: "Barrett's esophagus", short: "Barrett's esophagus", level: .relative, source: .hahn2013),
        TEEItem(id: "dysphagia", label: "Dysphagia", short: "dysphagia", detail: "Now or in the past", level: .relative, source: .hahn2013),
        TEEItem(id: "neck", label: "Restricted neck mobility", short: "restricted neck mobility",
                detail: "Severe cervical arthritis, atlantoaxial disease", level: .relative, source: .hahn2013),
        TEEItem(id: "hiatal-hernia", label: "Symptomatic hiatal hernia", short: "symptomatic hiatal hernia", level: .relative, source: .hahn2013),
        TEEItem(id: "varices", label: "Esophageal varices", short: "esophageal varices", level: .relative, source: .hahn2013),
        TEEItem(id: "coagulopathy", label: "Coagulopathy or thrombocytopenia", short: "coagulopathy or thrombocytopenia", level: .relative, source: .hahn2013),
        TEEItem(id: "esophagitis", label: "Active esophagitis", short: "active esophagitis",
                detail: "Reflux, infectious, pill or eosinophilic", level: .relative, source: .hahn2013),
        TEEItem(id: "pud", label: "Active peptic ulcer disease", short: "active peptic ulcer disease", level: .relative, source: .hahn2013),
        TEEItem(id: "motility", label: "Esophageal scleroderma or achalasia", short: "esophageal scleroderma or achalasia",
                detail: "Absolute or relative by severity (Hahn 2013); counted as relative", level: .relative, source: .hahn2013),
    ]

    private static let byID: [String: TEEItem] = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    static func item(_ id: String) -> TEEItem? { byID[id] }

    // MARK: When to ask

    /// The procedure list's TEE entries.
    static let teeProcedureIDs: Set<String> = ["tee", "tee-dccv"]

    /// Echo-first surgery (cardiac, major aortic, liver or lung transplant), or a TEE as the procedure.
    static func planned(_ r: PatientRecord) -> Bool {
        if PatientRules.echoFirst(r) { return true }
        if r.recognizedProcedures.contains(where: { teeProcedureIDs.contains($0.id) }) { return true }
        return matches(r.typedProcedureNames, ["tee", "transesophageal", "transoesophageal"])
    }

    // MARK: The record

    /// Esophagectomy in the procedure list, an esophageal replacement with colon and a conduit takedown, which follow one
    /// (1.8.3).
    static let esophagectomyIDs: Set<String> = ["ivor-lewis", "mie", "transhiatal-esophagectomy", "mckeown", "colon-interposition", "conduit-takedown"]
    /// Esophageal and gastric operations in the procedure list (not endoscopy, gastrostomy, a gastric stimulator or a
    /// perforated or bleeding ulcer patch). A tracheoesophageal fistula repair, a tracheoesophageal puncture for a voice
    /// prosthesis and a Zenker or other esophageal diverticulectomy are esophageal surgery here; the fistula or the
    /// diverticulum itself is asked on the checklist. Endoscopic operations that change the anatomy (POEM, endoscopic
    /// bariatric procedures, transoral fundoplication) count. 1.8.3 adds the ids from "esophageal-diversion" on.
    static let upperGIIDs: Set<String> = ["sleeve", "rygb", "lap-band", "duodenal-switch", "bariatric-revision", "nissen", "heller", "linx",
                                          "total-gastrectomy", "partial-gastrectomy", "lap-gastrectomy", "gastric-wedge", "gastrojejunostomy",
                                          "hiatal-hernia", "whipple", "robotic-whipple", "zenker", "poem", "endoscopic-bariatric", "tef",
                                          "esophageal-diversion", "esophageal-diverticulum", "esophageal-perforation", "esophageal-enucleation",
                                          "tif", "oagb", "bypass-reversal", "sleeve-conversion", "gastric-band-removal-open",
                                          "lap-gastrojejunostomy-revision", "pyloroplasty", "peds-gastrostomy-fundoplication", "tep-voice",
                                          "surgical-cystgastrostomy"]
    static let esophagectomyWords = ["esophagectomy", "esophagogastrectomy", "ivor lewis", "mckeown", "colonic interposition", "colon interposition"]
    static let upperGIWords = ["fundoplication", "nissen", "toupet", "hiatal hernia repair", "hiatus hernia repair", "paraesophageal hernia",
                               "heller", "esophageal myotomy", "poem", "gastrectomy", "gastric bypass", "roux-en-y gastric", "rygb", "gastric sleeve",
                               "gastric band", "lap band", "duodenal switch", "linx", "whipple", "pancreaticoduodenectomy", "zenker",
                               "esophageal surgery", "esophagus surgery", "gastric surgery", "stomach surgery", "esophageal atresia",
                               "tracheoesophageal fistula repair", "tef repair", "antireflux surgery"]

    /// "esophagectomy", "gi-surgery" or nil for one past operation.
    static func surgeryItem(_ s: PatientSurgery) -> String? {
        var ids: Set<String> = []
        if let p = s.procedureID { ids.insert(p) } else { ids.formUnion(ProcedureCatalog.parse(s.name).map(\.procedure.id)) }
        let name = normalized(s.name)
        if !ids.isDisjoint(with: esophagectomyIDs) || matches(name, esophagectomyWords) { return "esophagectomy" }
        if !ids.isDisjoint(with: upperGIIDs) || matches(name, upperGIWords) { return "gi-surgery" }
        return nil
    }

    /// What the structured record shows, by item id, with where.
    static func fromRecord(_ r: PatientRecord) -> [String: [String]] {
        var out: [String: [String]] = [:]
        func add(_ id: String, _ why: String) { out[id, default: []].append(why) }
        func problem(_ p: String, _ id: String) {
            if r.has(p), let label = PatientCatalog.problem(p)?.label { add(id, "History: " + label) }
        }
        problem("varices", "varices")
        problem("bleeding", "coagulopathy")
        problem("dic", "coagulopathy")
        // 1.9: the GI & liver page's structured items (Ben: "triggers possible TEE concern"). A history of gastric
        // bypass is previous upper GI surgery; Dysphagia is Hahn's own item; an active upper GI bleed is Hahn's absolute
        // one. The Hematologic page's named bleeding disorders and Thrombocytopenia are Hahn's "coagulopathy or
        // thrombocytopenia", as a bleeding disorder was before.
        if r.has("gastric-bypass") {
            let d = r.hx.gastricBypassDetails.trimmingCharacters(in: .whitespacesAndNewlines)
            add("gi-surgery", "History: gastric bypass" + (d.isEmpty ? "" : " (" + d + ")"))
        }
        problem("dysphagia", "dysphagia")
        for p in ["vwd", "hemophilia-a", "hemophilia-b", "thrombocytopenia"] { problem(p, "coagulopathy") }
        if r.has("gi-bleed"), r.hx.giBleedStatus == "active", r.hx.giBleedSite == "upper" {
            add("ugib-active", "History: GI bleed, active, upper")
        }
        problem("spine-fusion", "neck")
        problem("cspine-unstable", "neck")
        for (sign, id) in [("radiation", "radiation"), ("neck", "neck")] where r.airwaySigns.contains(sign) {
            if let label = PatientAirway.signs.first(where: { $0.id == sign })?.label { add(id, "Airway: " + label) }
        }
        for s in r.surgeries {
            if let id = surgeryItem(s) { add(id, "Past surgical history: " + s.text) }
        }
        return out
    }

    // MARK: Suggestions

    /// Words in the notes that point to an item, matched on whole words after "oesophag" is read as "esophag".
    static let noteWords: [(id: String, words: [String])] = [
        ("stricture", ["stricture", "esophageal dilation", "esophageal dilatation"]),
        ("tumor", ["esophageal cancer", "esophageal carcinoma", "esophageal tumor", "esophageal mass"]),
        ("perforation", ["esophageal perforation", "boerhaave", "mallory-weiss", "mallory weiss"]),
        ("diverticulum", ["zenker", "esophageal diverticulum", "pharyngeal pouch"]),
        ("esophagectomy", esophagectomyWords),
        ("te-fistula", ["tracheoesophageal fistula", "tef"]),
        ("radiation", ["radiation", "radiotherapy", "xrt"]),
        ("ugib-active", ["active gi bleed", "active upper gi bleed", "active ugib", "actively bleeding", "ongoing hematemesis", "acute upper gi bleed", "acute gi bleed"]),
        ("ugib-recent", ["gi bleed", "ugib", "hematemesis", "melena", "variceal bleed", "variceal bleeding"]),
        ("barretts", ["barrett", "barretts"]),
        ("dysphagia", ["dysphagia"]),
        ("hiatal-hernia", ["hiatal hernia", "hiatus hernia", "paraesophageal hernia"]),
        ("varices", ["varices", "varix", "variceal"]),
        ("esophagitis", ["esophagitis", "eoe"]),
        ("pud", ["peptic ulcer", "gastric ulcer", "duodenal ulcer", "pud"]),
        ("motility", ["achalasia", "scleroderma", "systemic sclerosis"]),
    ]

    /// A previous esophageal procedure as Ben's list names them (stent, dilation, resection), with the question each
    /// asks (1.9). Offered to confirm, never counted: a resection may have been endoscopic, a stent or a dilation may
    /// have treated a stricture or a tumor.
    static let procedureWords: [(id: String, words: [String], question: String)] = [
        ("stricture", ["dilation", "dilatation", "dilated", "bougie", "bougienage", "stent", "stented"], "is there a stricture?"),
        ("tumor", ["stent", "stented"], "was it for a tumor?"),
        ("esophagectomy", ["resection", "resected"], "was it an esophagectomy?"),
        ("gi-surgery", upperGIWords + ["myotomy"], "previous upper GI surgery?"),
    ]

    static func suggestions(_ r: PatientRecord, found: Set<String>) -> [TEESuggestion] {
        var out: [TEESuggestion] = []
        func offer(_ id: String, _ why: String) {
            guard let it = item(id), !found.contains(id), r.teeScreen.answer(id) == nil, !out.contains(where: { $0.item.id == id }) else { return }
            out.append(TEESuggestion(item: it, why: why))
        }
        // 1.9: a recorded hiatal hernia asks Hahn's question first; reflux (which until 1.9 was "Reflux or hiatal hernia")
        // keeps its own.
        if r.has("hiatal-hernia") { offer("hiatal-hernia", "Hiatal hernia recorded: is it symptomatic?") }
        if r.has("gerd") { offer("hiatal-hernia", "Reflux or hiatal hernia recorded: is a hiatal hernia symptomatic?") }
        if r.has("cirrhosis") { offer("varices", "Cirrhosis recorded: are there esophageal varices?") }
        // A GI bleed that is not an active upper one (a finding): resolved upper, or the site or status not recorded.
        if r.has("gi-bleed"), r.hx.giBleedSite != "lower" {
            let active = r.hx.giBleedStatus == "active"
            if r.hx.giBleedSite == "upper" {
                if r.hx.giBleedStatus == "resolved" {
                    offer("ugib-recent", "Resolved upper GI bleed recorded: was it recent?")
                } else if !active {
                    // No status recorded: an active upper bleed (absolute) is asked first, then a recent one.
                    offer("ugib-active", "Upper GI bleed recorded, status not recorded: is it active?")
                    offer("ugib-recent", "Upper GI bleed recorded, status not recorded: was it recent?")
                }
            } else if active {
                offer("ugib-active", "Active GI bleed recorded: is it an upper GI bleed?")
            } else {
                offer("ugib-recent", "GI bleed recorded: was it a recent upper GI bleed?")
            }
        }
        // An esophageal disorder: its type and any previous esophageal procedure, read for the items they name; with
        // none named, the question goes to the first esophageal item. The previous procedure sits on the section both
        // dysphagia and an esophageal disorder share, and the section can hold a procedure answered Yes with neither
        // chosen (the summary then lists it), so it is read under either, or whenever it is answered Yes.
        let disorder = r.has("esophageal-disorder")
        if disorder || r.has("dysphagia") || r.hx.esophagealProcedure == true {
            let type = disorder ? r.hx.esophagealDisorderType.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let procedure = r.hx.esophagealProcedure == false ? "" : r.hx.esophagealProcedureDetails.trimmingCharacters(in: .whitespacesAndNewlines)
            var named = false
            if !type.isEmpty {
                for (id, words) in noteWords {
                    if let w = mention(type, words) { named = true; offer(id, "Esophageal disorder: \u{201C}" + w + "\u{201D}.") }
                }
            }
            if !procedure.isEmpty {
                for (id, words) in noteWords {
                    if let w = mention(procedure, words) { named = true; offer(id, "Previous esophageal procedure: \u{201C}" + w + "\u{201D}.") }
                }
                for p in procedureWords {
                    if let w = mention(procedure, p.words) { named = true; offer(p.id, "Previous esophageal procedure: \u{201C}" + w + "\u{201D}: " + p.question) }
                }
            }
            if disorder, !named {
                let what = type.isEmpty ? "Esophageal disorder recorded" : "Esophageal disorder recorded (\u{201C}" + type + "\u{201D})"
                offer("stricture", what + ": is it a stricture, tumor, diverticulum, scleroderma or achalasia? Answer those below.")
            }
        }
        var labs: [String] = []
        if let p = r.labs["plt"], PatientLabs.flag("plt", p, sex: r.sex) == .low { labs.append("platelets " + NumText.short(p) + " ×10³/µL") }
        if let i = r.labs["inr"], PatientLabs.flag("inr", i, sex: r.sex) == .high { labs.append("INR " + (PatientLabs.test("inr")?.format(i) ?? NumText.short(i))) }
        if !labs.isEmpty { offer("coagulopathy", "Outside the reference range: " + labs.joined(separator: ", ") + ".") }
        // Operations the screen already counts are not read again as notes.
        var texts: [String] = r.systemNotes.keys.sorted().compactMap { r.systemNotes[$0] }
        texts.append(contentsOf: [r.otherHistory, r.airwayNotes, r.anesthesiaNotes])
        // 1.9: Other GI & liver disease, a history of gastric bypass's details and an upper (or unplaced) GI bleed's
        // details; a previous EGD's findings are read on their own, below.
        texts.append(contentsOf: [r.systemOther["gi"] ?? "", r.hx.gastricBypassDetails])
        if r.has("gi-bleed"), r.hx.giBleedSite != "lower" { texts.append(r.hx.giBleedDetails) }
        let egd = r.teeScreen.previousEGD == false ? "" : r.teeScreen.egdFindings
        if !egd.isEmpty {
            for (id, words) in noteWords {
                if let w = mention(egd, words) { offer(id, "Previous EGD: \u{201C}" + w + "\u{201D}.") }
            }
        }
        texts.append(contentsOf: r.surgeries.filter { surgeryItem($0) == nil }.map(\.name))
        for t in texts where !t.isEmpty {
            for (id, words) in noteWords {
                if let w = mention(t, words) { offer(id, "Notes mention “" + w + "”.") }
            }
        }
        return out
    }

    // MARK: Result

    static func evaluate(_ r: PatientRecord) -> TEEResult {
        let rec = fromRecord(r)
        var findings: [TEEFinding] = []
        for it in items {
            var from = rec[it.id] ?? []
            if r.teeScreen.yes.contains(it.id) { from.append("Checklist") }
            if !from.isEmpty { findings.append(TEEFinding(item: it, from: from)) }
        }
        findings = findings.filter { $0.item.level == .absolute } + findings.filter { $0.item.level == .relative }
        let sug = suggestions(r, found: Set(findings.map(\.item.id)))
        return TEEResult(findings: findings, suggestions: sug, reviewed: r.teeScreen.reviewed)
    }

    /// The Intraoperative echo card's and the handoffs' line, only when something is flagged; an absolute
    /// contraindication is in capitals (the shared text) and marked for bold red (the app).
    static func line(_ r: PatientRecord) -> PatientSummary.Line? {
        let res = evaluate(r)
        guard !res.findings.isEmpty else { return nil }
        var parts: [String] = []
        var marks: [String] = []
        let abs = res.absolute.map(\.item.short), rel = res.relative.map(\.item.short)
        if !abs.isEmpty {
            let t = "ABSOLUTE contraindication" + (abs.count > 1 ? "s" : "") + " to the probe: " + abs.joined(separator: ", ")
            parts.append(t); marks.append(t)
        }
        if !rel.isEmpty {
            parts.append(abs.isEmpty ? "Relative contraindication" + (rel.count > 1 ? "s" : "") + ": " + rel.joined(separator: ", ") : "relative: " + rel.joined(separator: ", "))
        }
        return PatientSummary.Line("TEE screen", parts.joined(separator: "; "), alert: true, marks: marks)
    }

    /// One line for the link row and the prompt.
    static func status(_ r: PatientRecord) -> String {
        let res = evaluate(r)
        if !res.findings.isEmpty {
            let names = res.findings.map(\.item.short)
            return res.level.label + ": " + names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " and \(names.count - 3) more" : "")
        }
        if res.reviewed { return "Screened: no contraindication recorded" }
        if !res.suggestions.isEmpty { return "\(res.suggestions.count) item\(res.suggestions.count == 1 ? "" : "s") in the record to confirm" }
        return "Not screened"
    }

    /// The prompt when a TEE is likely; it opens the screen (route "workup:tee").
    static func prompts(_ r: PatientRecord) -> [PatientPrompt] {
        guard planned(r) else { return [] }
        let res = evaluate(r)
        let why = PatientRules.echoFirst(r) ? "TEE is usual for this surgery: check for contraindications to the probe" : "TEE planned: check for contraindications to the probe"
        return [PatientPrompt(id: "tee", title: "TEE screen", why: why, route: "workup:tee", done: res.screened ? "TEE screen: " + (res.findings.isEmpty ? "no contraindication recorded" : res.level.label.lowercased()) : nil)]
    }

    // MARK: Evidence

    /// With any contraindication: Hahn 2013's and the ASA/SCA 2010 precautions.
    static let precautions = [
        "Weigh the benefit against the risk case by case (ASE/SCA 2013; ASA/SCA 2010).",
        "When GI symptoms or disease raise the question, get a gastroenterologist's clearance (ASE/SCA 2013: strongly recommended).",
        "Consider other imaging, such as epicardial echocardiography (ASA/SCA 2010).",
        "Use a smaller probe, limit the examination, and avoid unnecessary manipulation; not advancing past the midesophagus is one example (ASA/SCA 2010; ASE/SCA 2013).",
        "Have the most experienced operator place and drive the probe (ASA/SCA 2010).",
    ]

    static let evidence = [
        "Classes from the ASE/SCA guideline for performing a comprehensive TEE examination (Hahn RT, et al. J Am Soc Echocardiogr 2013;26:921–964, Table 6). Absolute: perforated viscus; esophageal stricture, tumor, perforation or laceration, or diverticulum; active upper GI bleeding. Relative: radiation to the neck and mediastinum, GI surgery, recent upper GI bleeding, Barrett's esophagus, dysphagia, restricted neck mobility (severe cervical arthritis, atlantoaxial joint disease), symptomatic hiatal hernia, esophageal varices, coagulopathy or thrombocytopenia, active esophagitis and active peptic ulcer disease. Patients with a relative contraindication are judged case by case, with precautions such as not advancing the probe past the midesophagus and limiting its manipulation.",
        "The same guideline: radiation, esophageal scleroderma and achalasia can weaken the esophagus, and their severity decides whether they are absolute or relative. The screen counts them as relative and leaves the judgment to you. It gives no platelet or INR cutoffs, so abnormal labs only prompt the question.",
        "Esophagectomy or esophagogastrectomy and a tracheoesophageal fistula are not in that table. The ASA/SCA practice guidelines (Anesthesiology 2010;112:1084–1096) found the literature insufficient to set contraindications. In their survey, consultants and members were equivocal whether anything besides a previous esophagectomy or esophagogastrectomy is absolute; those who disagreed named esophageal stricture, tracheoesophageal fistula, esophageal surgery and esophageal trauma; consultants agreed, and members were equivocal, that a Zenker diverticulum is absolute; both disagreed that Barrett's esophagus or a hiatal hernia is. The screen marks esophagectomy and a fistula absolute on that opinion.",
        "ASA/SCA 2010: TEE may be used with oral, esophageal or gastric disease if the expected benefit outweighs the risk, with precautions: other imaging (such as epicardial echocardiography), a gastroenterology consultation, a smaller probe, a limited examination, no unnecessary probe manipulation, and the most experienced operator.",
        "An unstable cervical spine counts with restricted neck mobility: the ASE/SCA basic perioperative TEE statement advises caution with probe placement and manipulation when an esophageal or cervical spine injury may coexist (Reeves ST, et al. J Am Soc Echocardiogr 2013;26:443–456).",
        "What counts on its own: esophageal varices, a history of gastric bypass (as upper GI surgery), dysphagia, an active upper GI bleed, a bleeding disorder, thrombocytopenia or DIC, cervical fusion or an unstable cervical spine (History); neck radiation changes and limited neck movement (Airway); esophageal and upper GI operations in the past surgical history. Reflux, a hiatal hernia, an esophageal disorder (its type and any previous esophageal procedure), a GI bleed that is not active and upper, cirrhosis, abnormal platelets or INR, a previous EGD's findings and words in the notes are offered to confirm, never counted until you answer Yes.",
    ]

    // MARK: Text matching

    /// Lowercased, with "oesophag" read as "esophag" and "œ" spelled out.
    static func normalized(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "oesophag", with: "esophag")
    }

    private static func matches(_ text: String, _ words: [String]) -> Bool {
        let p = " " + normalized(text) + " "
        return words.contains { w in p.range(of: "\\b" + NSRegularExpression.escapedPattern(for: w) + "\\b", options: .regularExpression) != nil }
    }

    /// The first of `words` the text mentions, unless a negation ("no", "denies", "without", "negative for") comes
    /// shortly before it in the same sentence.
    static func mention(_ text: String, _ words: [String]) -> String? {
        let t = normalized(text)
        for w in words {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: w) + "\\b"
            var from = t.startIndex
            while let r = t.range(of: pattern, options: .regularExpression, range: from..<t.endIndex) {
                defer { from = r.upperBound }
                // The sentence the word is in, and the note reader's own negation scope ("no reflux but has
                // dysphagia" keeps the dysphagia).
                let sentenceStart = t[..<r.lowerBound].lastIndex(where: { ".;\n".contains($0) }).map { t.index(after: $0) } ?? t.startIndex
                let prefix = String(t[sentenceStart..<r.lowerBound])
                if prefix.hasSuffix("lower ") { continue }   // a lower GI bleed is not an upper one
                if !PatientNote.negated(String(t[sentenceStart...]), at: (prefix as NSString).length) { return w }
            }
        }
        return nil
    }
}
