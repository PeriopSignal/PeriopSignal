import Foundation

// MARK: - Fill from a note
//
// A typed or dictated note read into My Patient by fixed rules, on the phone: nothing is sent anywhere and the note
// itself is not kept. Each thing recognized becomes a finding the user confirms before it is added. Negated mentions
// ("denies chest pain", "no history of stroke"), family history ("father had an MI") and past events ("history of
// ACS") are not read as the patient's current problems. What nothing was read from is offered for Other conditions
// or, from a surgical or anesthetic history, for the anesthesia-history details.
//
// Abbreviations (MedAbbreviations) are read too. An ambiguous one ("RA") and one the user saved are read as their
// meaning (the user's choice, else the one the context picks); the others are read as written by the rules below and,
// where no rule read them, through their meaning ("AVr" as aortic valve repair). Ambiguous and unknown abbreviations are
// listed for the user to choose or explain.
//
// What the patient arrives with goes to the 1.6 fields: the current airway (own airway, ETT with its size and depth,
// tracheostomy), the ventilator's settings, oxygen (room air means their own airway), and lines and mechanical support,
// each phrase read by PatientDevices.parse. A device the record already has (same kind and site) is not added twice.

enum PatientNoteChange: Hashable {
    case age(Double), sex(PatientSex), height(Double), weight(Double)
    case procedure(String), urgency(PatientUrgency), anesthetic(String), asa(Int, Bool)
    case problem(String), noHistory, smoking(String)
    /// An aortic aneurysm at a location (PatientHistoryDetails.aneurysmSites; "thoracic" when the note does not say
    /// where), with its diameter in cm when written, and whether it has ruptured.
    case aneurysm(String, Double?, Bool)
    /// A valve lesion: the valve ("aortic", "mitral", "tricuspid"), "stenosis" or "regurgitation", and its grade ("mild",
    /// "moderate", "severe"; nil when not written).
    case valve(String, String, String?)
    /// A prosthetic valve: its position ("" when not written) and what the note says of it ("mechanical", "TAVR 2019").
    case prosthesis(String, String)
    /// Pulmonary hypertension graded mild or moderate (severe is the "pulm-htn-severe" problem).
    case pulmHtn(String)
    /// Previous cardiac surgery, as written ("AVR 2015", "CABG"): it goes to the past surgical history too.
    case cardiacSurgery(String)
    /// One past operation (1.8.3): the operation as written, without its date, and its month and year when the note gives
    /// them. It becomes an entry in Past surgical history (PastSurgeryNote).
    case pastSurgery(String, PatientMonthYear)
    /// The Left heart cath's result (1.8.3): PatientLHC.result, "non-obstructive" or "no-cad". Read only beside a cath word.
    case lhcResult(String)
    /// Home oxygen with its flow, L/min.
    case homeO2(Double)
    /// A problem, and the words to add to its details ("evar", "FEVAR 2021": a complex EVAR files as Prior EVAR, and its
    /// type goes to the repair details so it is not lost; "arrhythmia", "SVT"; "pacemaker", "dependent").
    case problemNote(String, String)
    /// A detail the 1.9 History pages hold beside a problem (PatientHistoryDetails): the problem, filed with it ("" for
    /// none: pack-years, a fistula before dialysis), the detail's key (PatientNote.setDetail) and its value as the field
    /// stores it ("ckdStage", "3b"; "hepatitisTypes", "b,c"; "anticoagulant:heparin", "therapeutic").
    case detail(String, String, String)
    case medFlag(String), medications(String)
    /// A running infusion: the drug and its rate as written ("0.1 mcg/kg/min", or "" when none was given).
    case infusion(String, String)
    case nkda, allergies(String)
    case anesthesiaHistory(String), anesthesiaNotes(String)
    case vital(String, Double), lab(String, Double)
    case lastSolids(Date), lastClears(Date)
    case mets(String), frail, symptom(String), acute(String)
    case mallampati(Int), airwaySign(String), dentition(String)
    /// The airway on arrival: "natural", "ett" or "trach"; then the ETT's size or the tracheostomy's type, and the ETT's
    /// depth ("23 cm at the lip"), "" when not given.
    case currentAirway(String, String, String)
    /// Ventilator settings on arrival; only the settings given are set.
    case vent(PatientVent)
    /// Oxygen on arrival, breathing on their own (PatientOxygen.devices): "ra" room air, "nc", "hfnc", "niv", ...
    case oxygen(PatientOxygen)
    /// Lines or mechanical support on arrival, from one phrase of the note (PatientDevices.parse); a device the record
    /// already has (same kind and site) is not added again.
    case devices([PatientDevice])
    case otherHistory(String)
    /// Code status, a POLST on file and the perioperative plan (PatientCodeStatus); nil where the note did not say.
    case codeStatus(CodeStatus?, polst: Bool, plan: CodeStatusPlan?)
    // From the quick-add bar's Intraoperative tab (QuickAdd):
    /// Intraoperative lab values: they join the set with the same id, or start it.
    case intraopLabs(IntraopLabSet)
    /// Blood products given, added to the case's total (BloodProducts' keys in PatientRecord.fluids; units, cell saver in mL).
    case blood(String, Double)
    /// An infusion running during the case (PatientRecord.infusions), as `infusion` is one running before it.
    case intraopInfusion(String, String)
    /// One field of the intraoperative airway course, by QuickAdd.airwayFields' name, and its value.
    case intraopAirway(String, String)
    // Labs that are not numbers (LabResults, 1.8.3):
    /// Type and screen: only the parts written are set.
    case typeScreen(PatientTypeScreen)
    /// An infectious result: the test id ("mrsa", or "other" with its name) and the result.
    case infectious(String, String, LabResult)
}

struct PatientNoteFinding: Identifiable, Hashable {
    var id: String
    /// The review group (PatientNote.sections).
    var section: String
    var label: String
    var change: PatientNoteChange
    /// A caution shown under the item ("Added as well controlled; ...").
    var note: String? = nil
}

/// How a finding compares with what the record already holds.
enum PatientNoteStatus: Hashable {
    /// Not in the record yet.
    case new
    /// The record already says this, or something more specific: nothing to add.
    case recorded
    /// Adding it changes what the record says (the old value).
    case replaces(String)
    /// It contradicts the record in a way to sort out by hand first (NKDA over a recorded allergy); cannot be added.
    case conflicts(String)

    var onByDefault: Bool { canAdd }

    var canAdd: Bool {
        switch self {
        case .new, .replaces: return true
        case .recorded, .conflicts: return false
        }
    }
}

struct PatientNoteReading: Hashable {
    var findings: [PatientNoteFinding]
    /// The parts of the note nothing was read from, offered for Other conditions.
    var other: String
    /// Leftovers from a surgical or anesthetic history, offered for the anesthesia-history details.
    var previous: String
    /// What looked like an identifier: "a record number", "a date", "a name", "a phone number".
    var identifiers: [String]
    /// Ambiguous abbreviations, with the meaning read (the user's choice, else the context's or the usual one).
    var ambiguous: [AmbiguousAbbreviation] = []
    /// Letters that look like abbreviations but are in neither the built-in list nor the user's.
    var unknown: [UnknownAbbreviation] = []

    var isEmpty: Bool { findings.isEmpty && other.isEmpty && previous.isEmpty }
}

/// A regular expression compiled once; `re` is nil only for an invalid pattern (a test checks there is none).
struct NoteRx {
    let pattern: String
    let re: NSRegularExpression?

    init(_ p: String, caseSensitive: Bool = false) {
        pattern = p
        re = try? NSRegularExpression(pattern: p, options: caseSensitive ? [] : [.caseInsensitive])
    }

    func all(_ s: String) -> [NSTextCheckingResult] {
        guard let re else { return [] }
        return re.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }

    func first(_ s: String) -> NSTextCheckingResult? {
        guard let re else { return nil }
        return re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
}

private extension NSTextCheckingResult {
    /// The text of capture group `i`, when it took part in the match.
    func text(_ i: Int, in s: String) -> String? {
        guard i < numberOfRanges else { return nil }
        let r = range(at: i)
        guard r.location != NSNotFound else { return nil }
        return (s as NSString).substring(with: r)
    }

    /// The first of these groups that took part in the match.
    func text(_ groups: [Int], in s: String) -> String? {
        for g in groups {
            if let t = text(g, in: s) { return t }
        }
        return nil
    }
}

/// One rule: a pattern for one item, with the context it needs.
private struct Rule {
    let id: String
    let rx: NoteRx
    /// Also read inside a family history (only for items that are about the family).
    var family = false
    /// Counts only when the sentence also matches this (a bare "stent" needs a cardiac word).
    var onlyIf: NoteRx? = nil
    /// Skipped when the sentence matches this (a ureteral stent).
    var notIf: NoteRx? = nil
    /// A mention followed by this is read as negative ("HIV negative", "MRSA screen neg").
    var negAfter: NoteRx? = nil
    /// Filed without the item's caution (the note gave what the caution asks for: "CVA 2019").
    var quiet = false
    /// 1.9. An item that is there now (a pneumothorax, a fracture): a mention told as past ("h/o", "s/p ORIF of", a year,
    /// "PMH:") is not read. `pastOnly` is the reverse (a past uterine rupture).
    var current = false
    var pastOnly = false
    /// 1.9. A risk, a suspicion or a screen is not the item: "at risk for compartment syndrome", "concern for GI bleed",
    /// "possible PTX", "fracture risk" (PatientNote.riskBefore, riskAfter).
    var guarded = false
    /// 1.9. Skipped when the text just before (after) the mention matches ("former" alcohol dependence, "topical"
    /// cocaine).
    var notBefore: NoteRx? = nil
    var notAfter: NoteRx? = nil

    init(_ id: String, _ p: String, family: Bool = false, onlyIf: NoteRx? = nil, notIf: NoteRx? = nil, negAfter: NoteRx? = nil, quiet: Bool = false,
         current: Bool = false, pastOnly: Bool = false, guarded: Bool = false, notBefore: NoteRx? = nil, notAfter: NoteRx? = nil) {
        self.id = id
        rx = NoteRx(p)
        self.family = family
        self.onlyIf = onlyIf
        self.notIf = notIf
        self.negAfter = negAfter
        self.quiet = quiet
        self.current = current
        self.pastOnly = pastOnly
        self.guarded = guarded
        self.notBefore = notBefore
        self.notAfter = notAfter
    }
}

/// A detail read beside a problem (1.9), before it is placed on the problem's finding or one of its own.
private struct NoteDetail {
    var problem: String
    var key: String
    var value: String
    var range: NSRange
}

/// What one sentence gave: findings, and every stretch of it that was read (findings, negations, family history),
/// so the rest can be offered as leftovers.
private struct Hits {
    var findings: [PatientNoteFinding] = []
    /// Where each finding was read, in step with `findings`.
    var at: [NSRange] = []
    var ranges: [NSRange] = []
    /// Infusions read ("heparin infusion"): their medicine names do not go into the medication list as well.
    var infusions: [NSRange] = []
    /// Lines and devices read: their numbers (an ECMO circuit's FdO₂) are not the ventilator's.
    var deviceRanges: [NSRange] = []
    /// A lab value's marks, by finding id: said to be current ("now Hb 8.2"), or earlier ("preop Hb 12.1").
    var labFlags: [String: (current: Bool, earlier: Bool)] = [:]
    /// Questions asked while reading (two values of a test, neither marked current).
    var questions: [AmbiguousAbbreviation] = []
    /// History details read (1.9), placed on their problems' findings at the end of readRules.
    var details: [NoteDetail] = []

    mutating func add(_ f: PatientNoteFinding, at r: NSRange) {
        findings.append(f)
        at.append(r)
        ranges.append(r)
    }

    mutating func seen(_ r: NSRange) { ranges.append(r) }
}

enum PatientNote {
    /// The review groups, in the order My Patient's editors ask for them.
    enum Part {
        static let patient = "Patient", procedure = "Procedure", vitals = "Vital signs", history = "History",
                   meds = "Medications & allergies", anesthesia = "Anesthesia history", intake = "Last intake",
                   labs = "Labs", assessment = "Assessment", airway = "Airway", devices = "Lines & devices",
                   support = "Mechanical support"
    }

    static let sections = [Part.patient, Part.procedure, Part.vitals, Part.history, Part.meds, Part.anesthesia, Part.intake,
                           Part.labs, Part.assessment, Part.airway, Part.devices, Part.support]

    /// A made-up note for "Try an example" and the screenshots (no identifiers). "RA" is ambiguous (room air here) and
    /// "POEC" is a local abbreviation the list does not know, so the example shows both.
    static let example = "68 yo M presenting for elective laparoscopic right hemicolectomy under general anesthesia. PMH: HTN, T2DM on insulin, OSA on CPAP, CAD s/p DES to LAD 2021, hereditary angioedema. Denies chest pain or SOB. Climbs 2 flights of stairs without stopping. Meds: metoprolol, lisinopril, glargine, aspirin, clopidogrel. Allergies: penicillin (rash). Former smoker. Ht 178 cm, Wt 96 kg. BP 148/86, HR 72, SpO2 95% on RA. Hb 12.8, Cr 1.1, K 4.3 (POEC labs). Mallampati 3, thick neck. NPO after midnight. PSH: appendectomy 2010 under GA, uneventful."

    // MARK: Rules

    private static let stentCardiac = NoteRx(#"\b(?:cad|coronary|cardiac|heart|lad|rca|lcx|circumflex|mi|cath|angina|n?stemi|des|bms|pci)\b"#)
    private static let stentOther = NoteRx(#"\b(?:ureter|ureteral|ureteric|jj|double[- ]j|biliary|cbd|bile duct|pancrea|esophag|oesophag|trache|airway|bronch|carotid|renal|iliac|femoral|sfa|popliteal|colonic|duodenal|venous|svc|ivc|tips)"#)
    private static let ichWords = #"(?<!risk of )(?<!risk for )(?<!spinal )(?<!neuraxial )\b(?:intracranial|intracerebral|subarachnoid|subdural|epidural) (?:hemorrhages?|haemorrhages?|bleeds?|bleeding|hematomas?|haematomas?)\b"#
    private static let within3Months = #"(?:\d{1,2} days? ago|(?:[1-9]|1[0-2]) weeks? ago|last (?:week|month)|this month|(?:1|2|one|two) months? ago)"#
    /// A time over 3 months ago: a year ("2019"; the current year or later is not, see strokeYearNotPast), "5 years
    /// ago", "6 months ago".
    private static let over3Months = #"(?:(?:19|20)\d\d\b|(?:[4-9]|1[0-2]) months? ago|\d{1,2} (?:years?|yrs?) ago|(?:a|one|two|three|several|many) years? ago)"#
    // One vocabulary for a result that is not positive, shared by the history rules (infectionNotPositive) and the lab
    // results reader (LabResults), so the two never disagree: what reads as a negative or pending result never files a
    // history item (1.8.3 review).
    /// The words written between a test's name and its result ("MRSA nasal swab PCR …").
    static let resultQualifiers = #"-?1\s*[/&]\s*2|ab|abs|antibody|antibodies|ag|antigen|sag|serology|serologies|screen|screening|swab|nares|nasal|test|testing|tests|pcr|naat|rapid|status|igm|igg|culture|cultures|toxin|stool|result|results|precautions|aureus|colonization"#
    /// A negative result: "neg", "negative", "non-reactive", "-ve", "(-)", "not detected", "non-detected", "undetected",
    /// a "-" or "−" written onto the name ("MRSA-") or ending the phrase ("MRSA −"); a spaced dash before more words is a
    /// separator ("MRSA - on contact precautions").
    static let resultNegative = #"neg(?:ative)?\b|non-?reactive\b|-ve\b|\(-\)|not detected\b|non-?detected\b|undetected\b|[-−](?=[,;.)/]|$)|(?<=[A-Za-z0-9)])[-−](?=\s)"#
    /// A result still to come: "pending", "sent", "in process", "in progress".
    static let resultPending = #"pending\b|sent\b|in process\b|in progress\b"#

    /// After an infection word, a result that is not positive: "HIV negative", "MRSA screen neg", "HCV Ab (-)", "HIV-",
    /// "HIV-1/2 Ab negative", "C diff pending", "MRSA PCR not detected", "Isolation: none"; other abbreviations may sit
    /// between ("HIV/HCV neg").
    static let infectionNotPositive = NoteRx(#"^(?:\s*[/,&]\s*(?:and\s+)?(?-i:[A-Z][A-Z0-9]{1,6}))*(?:-(?=[\s,;.)]|$)|\s*\(?\s*(?:(?:"# + resultQualifiers + #")\s*){0,4}\)?\s*[:=]?\s*(?:is\s+|was\s+|were\s+|came back\s+|returned\s+)?(?:"# + resultNegative + "|" + resultPending + #"|unknown\b|ordered\b|none\b|no\b|n/a\b|not required\b|decoloni[sz]ation\b))"#)
    /// After a thrombophilia or Factor V Leiden, a test that is not positive (1.9 review): "thrombophilia workup negative",
    /// "FVL negative", "factor V Leiden: not detected", "prothrombin gene mutation neg", "FVL wild type".
    static let thrombophiliaNotPositive = NoteRx(#"^\s*\(?\s*(?:(?:work-?up|work up|screen|screening|panel|testing|tests?|studies|evaluation|eval|mutation|gene|genetic|genotype|genotyping|analysis|pcr|status|results?)\s*){0,4}\)?\s*[:=]?\s*(?:is\s+|was\s+|were\s+|came back\s+|returned\s+)?(?:"# + resultNegative + "|" + resultPending + #"|unremarkable\b|normal\b|wnl\b|none\b|no\b|n/a\b|wild[- ]?type\b|absent\b)"#)
    /// Before it: "negative thrombophilia workup", "normal FVL".
    static let thrombophiliaNegativeBefore = NoteRx(#"\b(?:negative|neg|normal|unremarkable)\s+(?:(?:hypercoagulab\w*|inherited)\s+)?$"#)
    /// HIV prevention, which is not HIV.
    static let hivPrevention = NoteRx(#"(?-i:\bPrEP\b|\bPEP\b)|pre-?exposure prophylaxis|post-?exposure prophylaxis|\bhiv prevention"#)
    /// COVID-19 written any common way, but not its vaccine, an exposure, a screen, or a test that is not positive.
    private static let covidWord = #"(?:covid(?:[- ]?19)?|sars[- ]?cov[- ]?2|coronavirus)(?!-?\d)(?!\s*[- ]?(?:vaccin|booster|shot|jab|immuni|exposure|screen|test(?:ing)?\b(?!\s*(?:positive|\+|pos\b))))"#
    /// Recent or positive: "recent COVID", "COVID-19 positive", "COVID 2 weeks ago", "tested positive for SARS-CoV-2".
    private static let covidRecent: String = [
        #"\b(?:recent|recently|current|active|acute|ongoing)\s+(?:(?:mild|symptomatic|asymptomatic)\s+)?"#, covidWord,
        #"|\b"#, covidWord, #"\s*(?:\(\s*)?(?:(?:pcr|antigen|ag|test|swab|infection|diagnosis|diagnosed)\s*)?(?:positive\b|pos\b|\+|detected\b|"#, within3Months, #")"#,
        #"|(?:\bpositive|\+)\s+(?:for\s+)?"#, covidWord,
    ].joined()
    /// Years before this one: a COVID-19 dated then is not recent ("COVID+ 2021").
    private static let pastYears: String = {
        let y = Calendar(identifier: .gregorian).component(.year, from: Date())
        return "(?:19\\d\\d|" + (2000..<max(y, 2001)).map { String($0) }.joined(separator: "|") + ")"
    }()
    /// A COVID-19 mention that is old or someone else's: a past year or "over 3 months ago" next to it, or an exposure
    /// ("exposure to a COVID-positive coworker"). The history item is not filed and no positive result is read (1.8.3
    /// review).
    static let covidNotRecent = NoteRx([
        #"(?:covid|sars[- ]?cov|coronavirus)[^,;.]{0,24}?\b(?:"#, pastYears, #"\b|(?:[4-9]|1[0-2]) months? ago|\d{1,2} (?:years?|yrs?) ago|(?:a|one|two|three|several|many) years? ago)"#,
        #"|\b(?:in\s+)?"#, pastYears, #"\b[^,;.]{0,12}?(?:covid|sars[- ]?cov|coronavirus)"#,
        #"|\b(?:expos(?:ure|ed)|close contacts?|contacts? with|sick contacts?)\b[^,;.]{0,40}?(?:covid|sars[- ]?cov|coronavirus)"#,
        #"|(?:covid|sars[- ]?cov|coronavirus)[^,;.]{0,30}?\b(?:co-?workers?|colleagues?|family members?|household|spouse|wife|husband|partner|roommate|exposure|exposed)\b"#,
    ].joined())

    /// Problem-list items, by the catalog's ids. Abbreviations that are also words are matched in capitals only.
    private static let problemRules: [Rule] = [
        // Hypertension has no control qualifier (1.8.1): "poorly controlled HTN" files Hypertension, as diabetes does.
        Rule("htn", #"(?<!pulmonary )(?<!arterial )(?<!gestational )(?<!induced )(?<!portal )(?<!intracranial )\b(?:hypertension|htn)\b|high blood pressure"#),
        Rule("hyperlipidemia", #"hyperlipid(?:a)?emia|(?-i:\bHLD\b)|dyslipid(?:a)?emia|hypercholesterol(?:a)?emia|high cholesterol"#),
        // CAD (1.8.1): coronary disease with no MI or PCI timing is CAD, unspecified; an MI within 3 months, over 3 months
        // (a time given: "MI 2019", quiet), or with no time ("h/o MI", "NSTEMI": over 3 months, with its caution).
        Rule("cad-recent", #"\b(?:recent|new) (?:mi|myocardial infarction|n?stemi|acs|acute coronary syndrome|heart attack)\b|\b(?:mi|n?stemi|myocardial infarction|heart attack|acs)\s+"# + within3Months),
        Rule("mi", #"\b(?:mi|n?stemi|myocardial infarction|heart attack)\s+(?:in\s+|\(\s*)?"# + over3Months + #"|\b(?:19|20)\d\d\s+(?:(?-i:MI)|n?stemi|myocardial infarction)\b"#, quiet: true),
        Rule("mi", #"\b(?:prior|previous|old|remote|history of|hx of|h/o|s/p) (?:mi|myocardial infarction|n?stemi|heart attack|acs)\b|\bn?stemi\b|\bmyocardial infarction\b|(?<!mild )(?<!trace )(?<!trivial )(?<!moderate )(?<!severe )(?-i:\bMI\b)"#),
        Rule("cad", #"\bcad\b|coronary artery disease|coronary (?:heart )?disease|ischemic heart disease|(?-i:\bIHD\b)"#),
        Rule("pci-recent", #"\b(?:recent|new) (?:coronary )?(?:stents?|(?-i:DES|PCI))\b|\b(?:stents?|(?-i:DES|PCI))(?: placed| to (?:the )?[a-z]+)?\s+"# + within3Months, notIf: stentOther),
        Rule("pci", #"(?-i:\b(?:DES|BMS|PCI)\b)|percutaneous coronary|coronary stents?|cardiac stents?|\b(?:LAD|RCA|LCx|circumflex) stents?\b"#),
        Rule("pci", #"\bstents?(?:ed)?\b"#, onlyIf: stentCardiac, notIf: stentOther),
        Rule("cabg", #"\bcabg|coronary (?:artery )?bypass|\b(?:cardiac|heart|triple|quadruple|double) bypass"#),
        Rule("ischemia", #"(?:ongoing|active|current) (?:myocardial |cardiac )?ischemia"#),
        Rule("hf-decomp", #"decompensated (?:heart failure|hf|chf)|(?:chf|heart failure|hf) exacerbation|acute (?:on chronic )?(?:(?:systolic|diastolic) )?(?:heart failure|chf)|(?-i:\bADHF\b)"#),
        Rule("hf", #"heart failure|\bchf\b|\bhf[rpm]?ef\b|(?-i:\bHF\b)"#),
        // Valve lesions and prosthetic valves are read by readValves (1.8.1), each into its valve.
        Rule("af", #"atrial fibrillation|atrial flutter|\ba[-. ]?fib\b|(?-i:\b(?:AF|AFL|PAF)\b)"#),
        Rule("arrhythmia", #"(?-i:\b(?:SVT|WPW|VT)\b)|ventricular tachycardia|heart block|long qt|\barrhythmias?\b|bradyarrhythmia|sick sinus"#),
        Rule("pacemaker", #"pacemaker|(?-i:\bPPM\b)"#),
        Rule("icd", #"(?-i:\b(?:ICD|AICD)\b)(?!-?\d)|defibrillator"#),
        Rule("pulm-htn-severe", #"severe pulmonary (?:arterial )?(?:hypertension|htn)|severe (?-i:\b(?:PH|PAH)\b)"#),
        Rule("pulm-htn", #"pulmonary (?:arterial )?(?:hypertension|htn)|(?-i:\bPAH\b)|\bphtn\b"#),
        Rule("pvd", #"(?-i:\b(?:PVD|PAD)\b)|peripheral (?:vascular|arterial) disease|claudication"#),
        // The aorta (the Cardiovascular page's Aorta group). "AAA" in capitals only; "rAAA" and "TAAA" are words of
        // their own, read longest first. A size beside an aneurysm is read with it (aortaSize). A repair counts as
        // history only when the sentence places it in the past ("s/p EVAR", "TEVAR 2019"): otherwise it may be the planned
        // procedure. A rupture told as past ("s/p repair of a ruptured AAA") is not read as a rupture now.
        // rAAA = ruptured AAA (2022 ACC/AHA aortic guideline, Isselbacher EM, et al. Circulation 2022;146:e334) [G];
        // "leaking AAA" [P].
        Rule("aaa-ruptured", #"(?:ruptured|leaking) (?:(?-i:AAA)\b|abdominal aortic aneurysm|abdominal aneurysm|infrarenal (?:aortic )?aneurysm)|(?-i:\brAAA\b)|(?-i:\bAAA\b),? (?:has |had |with )?(?:ruptured|rupture)\b"#),
        Rule("taa-ruptured", #"ruptured (?:(?-i:TAA)\b|thoracic aortic aneurysm|thoracic aneurysm|(?:ascending|descending|arch) (?:aortic )?aneurysm)|(?-i:\brTAA\b)|(?-i:\bTAA\b),? (?:has |had |with )?(?:ruptured|rupture)\b"#),
        Rule("taaa-ruptured", #"ruptured (?:(?-i:TAAA)\b|thoraco-?abdominal (?:aortic )?aneurysm)|(?-i:\bTAAA\b),? (?:has |had |with )?(?:ruptured|rupture)\b"#),
        Rule("aaa", #"(?<!thoraco)(?<!thoraco-)\babdominal aortic aneurysm|\binfrarenal (?:aortic )?aneurysm|(?-i:\bAAA\b)(?!\s+repair)|\btriple a\b"#),
        // An ascending, root, arch or descending aneurysm is a thoracic aortic aneurysm (2022 ACC/AHA) [G]; "dilated" and
        // "ectasia" are below aneurysm size and are not read [P]. Written out, always read (an "aortic valve replacement"
        // or "orthopnea" beside it changes nothing).
        Rule("taa", #"\bthoracic aortic aneurysm|\b(?:ascending|descending|descending thoracic|aortic root|aortic arch|arch) (?:aortic )?aneurysm|\baneurysm of the (?:ascending|descending|thoracic) aorta"#),
        // A bare "TAA" is also a total ankle arthroplasty [P]: aortic words or a size and no ankle words read it; ankle
        // words alone leave it unread; both or neither ask (readTAA). It is never read through its abbreviation's meaning.
        Rule("taa", #"\bTAA\b"#, onlyIf: taaContext, notIf: ankleContext),
        // TAAA: a descending aneurysm into the abdominal aorta; extent by Crawford (2022 ACC/AHA) [G].
        Rule("taaa", #"thoraco-?abdominal (?:aortic )?aneurysm|(?-i:\bTAAA\b)|\bcrawford (?:type |extent )?(?:i|ii|iii|iv|v|1|2|3|4|5)\b"#),
        // Stanford and DeBakey classifications (2022 ACC/AHA) [G]. "Type A"/"type B" only beside "dissection" (influenza,
        // WPW, personality) and never a bare "AD" (Alzheimer disease) [P]. "TAAD" is asked: common usage (as in
        // ProcedureCatalog) is type A aortic dissection, but in genetics, and per the research in the 2022 ACC/AHA guideline,
        // thoracic aortic aneurysm and dissection [G?, unverified]; "ATAAD" is acute type A [P].
        Rule("dissection-a", #"\b(?:stanford )?type[- ]?a (?:aortic )?dissection|\b(?:aortic )?dissection,? (?:stanford )?type[- ]?a\b|(?-i:\bATAAD\b)|\bstanford a (?:aortic )?dissection|\bascending aortic dissection|\bdebakey (?:type )?(?:i|ii|1|2)\b"#),
        Rule("dissection-b", #"\b(?:stanford )?type[- ]?b (?:aortic )?dissection|\b(?:aortic )?dissection,? (?:stanford )?type[- ]?b\b|(?-i:\b[uc]?TBAD\b)|\bstanford b (?:aortic )?dissection|\bdescending (?:thoracic )?aortic dissection|\bdebakey (?:type )?(?:iii|3)[ab]?\b"#),
        // Open repair: Bentall, hemiarch, elephant trunk imply a thoracic open repair [P]. "s/p AAA repair" with no
        // modality is not read (open or EVAR) [P].
        Rule("aortic-repair-open", #"\bopen (?:(?-i:AAA|TAA|TAAA)\s+|aortic\s+|aneurysm\s+|abdominal aortic aneurysm\s+|thoracoabdominal\s+)repair|\bopen (?:(?-i:AAA|TAAA)) (?:repair|resection)|\btype a (?:aortic )?dissection repair|\b(?:bio-?)?bentall\b|\b(?:ascending|hemiarch|total arch) (?:aortic )?replacement|\belephant trunk"#),
        // A bare "open repair" only with an aortic word in the sentence ("open repair of an inguinal hernia" is not) [P].
        Rule("aortic-repair-open", #"\bopen repair\b"#, onlyIf: NoteRx(#"\b(?:aorta|aortic|aneurysm|thoracoabdominal)\b|(?-i:\b(?:AAA|TAA|TAAA)\b)"#)),
        // EVAR, FEVAR (fenestrated-branched EVAR, 2022 ACC/AHA) [G]; FEVAR and BEVAR file as Prior EVAR (coordinator's
        // decision) [P]. "TEVAR" is its own word.
        Rule("evar", #"(?-i:\b(?:F/?B?|B)?EVAR\b)|\bendovascular (?:aaa |abdominal aortic aneurysm |aortic aneurysm |aneurysm )repair|\b(?:fenestrated|branched) (?:endovascular|(?-i:EVAR))"#),
        Rule("tevar", #"(?-i:\bTEVAR\b)|\bthoracic endovascular (?:aortic )?repair"#),
        Rule("chd-elevated", #"\bfontan\b|single ventricle|cyanotic (?:congenital|heart)|transposition of the great|(?-i:\b(?:TGA|HLHS)\b)|truncus arteriosus|eisenmenger|hypoplastic left heart"#),
        Rule("chd", #"congenital heart|atrial septal defect|ventricular septal defect|(?-i:\b(?:VSD|TOF)\b)|tetralogy|coarctation|ebstein"#),
        // A family history of premature coronary disease is no longer recorded (1.8.1); it reads as family history.
        Rule("asthma-uncontrolled", #"\b(?:uncontrolled|poorly controlled|not well controlled|badly controlled|severe persistent) asthma\b|\basthma exacerbation|\bexacerbation of (?:(?:his|her|their) )?asthma|status asthmaticus"#),
        Rule("asthma", #"\basthma|reactive airway"#),
        Rule("copd", #"\bcopd\b|emphysema|chronic bronchitis"#),
        Rule("cpap", #"\bc-?pap\b|\bbi-?pap\b|\bapap\b"#),
        Rule("osa", #"(?-i:\bOSA\b)|obstructive sleep apn(?:o)?ea|sleep apn(?:o)?ea"#),
        // Snoring, tiredness and observed apnea are the STOP-BANG tool's own questions (1.8.1): not read here.
        // A recent COVID-19 files Recent COVID-19 (Infectious, 1.8.1), not this as well; ARISCAT reads it as a respiratory
        // infection (PatientRules.prefill).
        Rule("pneumonia", #"\b(?:recent|current|active|ongoing|resolving|being treated for|treated for|on (?:antibiotics|abx) for) (?:(?:aspiration|community[- ]acquired|bacterial|viral|multifocal|lobar) )?pneumonia\b|\bpneumonia (?:last|this) (?:week|month)\b|\bpneumonia\s+"# + within3Months),
        Rule("uri", #"(?-i:\bURI\b)|upper respiratory (?:tract )?infection|(?:recent|current) (?:cold|cough|chest infection|bronchitis|respiratory infection|flu)"#),
        Rule("home-o2", #"home (?:oxygen|o2)|oxygen at home|o2 at home|\d+(?:\.\d+)? ?l(?:pm)? (?:nc )?at home"#),
        Rule("ild", #"(?-i:\b(?:ILD|IPF)\b)|interstitial lung disease|pulmonary fibrosis"#),
        // 1.9. Read only when there now (not "h/o PTX", "s/p chest tube for effusion 2019"), never a risk or a
        // differential; a bare "effusion" only with a side (not pericardial, nor a knee). The side, the fluid and a chest
        // tube go to the details (readDetails19).
        Rule("pleural-effusion", #"\bpleural effusions?\b|\b(?:hemo|haemo|chylo)thora(?:x|ces)\b|\b(?:left|right|bilateral|l|r|lt|rt|b/l|bilat)(?:[- ]sided)?\s+effusions?\b|\bparapneumonic effusions?\b|\bempyema\b"#,
             current: true, guarded: true),
        Rule("pneumothorax", #"\bpneumothora(?:x|ces)\b|\bhydropneumothorax\b|(?-i:\bPTX\b)"#, current: true, guarded: true),
        // A stroke or TIA within 3 months, over 3 months (a time given: "CVA 2019", "TIA 5 years ago"), or unspecified (no
        // time: "h/o stroke", "CVA", "prior stroke", "TIA"); the timed items replace the unspecified one (1.8.1). Since 1.8.2
        // the unspecified item reads "Stroke or TIA, unspecified", so a TIA with no time files it too, as a stroke does,
        // instead of claiming over 3 months. Not "heat stroke" or "stroke volume".
        Rule("cva-recent", #"\b(?:recent|new) (?:stroke|cva|tia)\b|\b(?:stroke|cva|tia)\s+"# + within3Months),
        Rule("cva", #"\b(?:stroke|cva|(?-i:TIA)|transient ischemic attack)\s+(?:in\s+|\(\s*)?"# + over3Months + #"|\b(?:19|20)\d\d\s+(?:stroke|cva|(?-i:TIA))\b"#, quiet: true),
        Rule("cva-unspec", #"(?-i:\bTIA\b)|transient ischemic attack"#),
        Rule("cva-unspec", #"(?<!heat )(?<!sun )\b(?:stroke|cva)\b(?!\s+(?:volume|work|index|risk|prevention|prophylaxis|distance|scale))(?!-like)"#),
        // An intracranial bleed (1.8.2): plain files "ich"; with mass effect or midline shift, "ich-mass", which replaces it. Not
        // a spinal or neuraxial epidural hematoma, nor a risk ("intracranial hemorrhage risk", "risk of subdural hematoma").
        // A bare "epidural hematoma" or "epidural bleed" is left out of the plain item: in an anesthesia note it is usually
        // the neuraxial complication. With mass effect or midline shift it is intracranial and files ich-mass.
        Rule("ich-mass", ichWords + #" with (?:mass effect|midline shift)"#),
        Rule("ich", #"(?!epidural\b)"# + ichWords + #"(?!\s+(?:risk|precautions?|prophylaxis|prevention)\b)"#),
        Rule("raised-icp", #"(?:raised|elevated|increased|high) (?:icp|intracranial pressure)|brain (?:tumou?r|mass)|intracranial mass"#),
        Rule("seizure", #"\bseizures?\b|epilepsy"#),
        Rule("dementia", #"dementia|alzheimer|cognitive impairment"#),
        Rule("parkinson", #"parkinson"#),
        // A muscular dystrophy is the Musculoskeletal item since 1.9 ("muscular-dystrophy", the ASA's pediatric example), and a
        // cardiomyopathy is not a myopathy (1.9: "peripartum cardiomyopathy" filed Neuromuscular disease as well).
        Rule("neuromuscular", #"myasthenia|(?-i:\bALS\b)|amyotrophic|guillain|neuromuscular disease|(?<!cardio)(?<!cardio-)myopathy|charcot-marie|myotonic(?! (?:muscular )?dystroph)"#),
        Rule("sci", #"spinal cord injury|paraplegi|quadriplegi|tetraplegi"#),
        Rule("chronic-pain", #"chronic (?:back )?pain|opioid[- ]tolerant|chronic opioids|fibromyalgia"#),
        // 1.9. Not "double-blind", a blind loop or a blind intubation, nor colour blindness (1.9 review); acute or chronic
        // goes to the details.
        Rule("visual-impairment", #"\bvisual(?:ly)?[- ]impair(?:ment|ed)\b|\bvision (?:loss|impairment)\b|\bloss of vision\b|\bvisual loss\b|\b(?:low|poor|impaired|decreased|reduced) vision\b|\blegally blind\b|(?<!double[- ])(?<!single[- ])(?<!double )(?<!single )(?<!color[- ])(?<!colour[- ])\bblind(?:ness)?\b(?![- ](?:spot|loop|pouch|nasal|intubation|insertion|placement|technique|study|trial|end(?:ed)?)\b)(?!-)"#,
             guarded: true),
        // Depression is major depressive disorder; not respiratory, ST-segment, CNS or myocardial depression, nor a
        // depression screen. Anxiety about the operation is not an anxiety disorder. Both file Psychological disorder
        // beside them (its base, readRules), as do the others, whose name goes to its details.
        Rule("mdd", #"(?-i:\bMDD\b)|\bmajor depressi(?:ve|on)(?: disorder)?\b|\bdepressive disorder\b|(?<!respiratory )(?<!ventilatory )(?<!st )(?<!st-)(?<!segment )(?<!cns )(?<!myocardial )(?<!cardiac )(?<!marrow )(?<!pr )(?<!circulatory )(?<!neonatal )(?<!brainstem )(?<!bipolar )\bdepression\b(?!\s+(?:of\s+(?:the\s+)?(?:st|pr|j)\b|screen))"#,
             guarded: true),
        Rule("anxiety", #"\banxiety(?: disorder)?\b(?!\s+(?:about|regarding|re\b|before|prior|with|around|over|related|surrounding|due|for)\b)|(?-i:\bGAD\b)|\bgeneralized anxiety\b|\bpanic (?:disorder|attacks)\b"#,
             guarded: true, notBefore: NoteRx(#"\b(?:pre-?op(?:erative)?|preoperative|perioperative|situational|procedural|periprocedural|anticipatory|some|mild|appropriate|expected|understandable)\s+$"#)),
        Rule("psych", #"\bbipolar(?: (?:i|ii|1|2))?(?: (?:affective )?disorder)?\b(?!\s*(?:cautery|electrocautery|forceps|sealer|diathermy|energy|leads?|pacing|sensing|scissors|device|vessel))|\bschizo(?:phrenia|affective(?: disorder)?)\b|(?-i:\bPTSD\b)|\bpost-?traumatic stress(?: disorder)?\b|(?<!knee )(?<!talus )(?<!talar )(?<!elbow )(?<!capitellum )(?<!capitellar )(?<!ankle )(?<!femoral )(?<!condyle )(?<!condylar )(?<!patellar )(?<!trochlear )(?<!dome )(?<!shoulder )(?<!hip )(?<!joint )(?-i:\bOCD\b)(?!\s+(?:lesions?|defects?|fragments?|of\s+(?:the\s+)?(?:\w+\s+)?(?:knee|talus|talar|elbow|capitellum|ankle|femoral|condyle|patella|hip|shoulder|dome)))|\bobsessive[- ]compulsive(?: disorder)?\b|\bpsychosis\b|\bpsychotic disorder\b|\bborderline personality(?: disorder)?\b|\banorexia nervosa\b|\bbulimia(?: nervosa)?\b|\beating disorder\b|(?-i:\bADHD\b)|\bpsychiatric (?:disorder|illness|disease)\b|\bmental illness\b"#,
             guarded: true),
        Rule("esrd-dialysis", #"\b(?:on|receives?|getting|undergoes|undergoing) (?:hemo|peritoneal )?dialysis|\bon (?-i:(?:HD|PD|CAPD|CCPD))\b|\bdialysis (?:m/?w/?f|mwf|tts|t/?th/?s|three times)|(?-i:\bHD\b) (?:m/?w/?f|mwf|tts|t/?th/?s)|peritoneal dialysis|\bhemodialysis\b"#,
             // 1.9: dialysis declined or not started is ESRD not on dialysis ("ESRD, declines HD").
             notBefore: NoteRx(#"\b(?:declin(?:es|ed|ing)|refus(?:es|ed|ing)|without|off|never on|not a candidate for|opts? against|elect(?:s|ed) against|not yet on|pre-?)\s*(?:(?:regularly|regular|scheduled|chronic|maintenance|any)\s+)*$"#)),
        // ESRD not on regularly scheduled dialysis is its own item since 1.9 (it was part of "aki", whose ASA IV example it
        // keeps), filed with CKD stage 5 (PatientNote.read). A typed "HD" reads as hemodialysis here.
        Rule("esrd-no-dialysis", #"(?:(?-i:\b(?:ESRD|ESKD)\b)|\bend[- ]stage (?:renal|kidney) disease\b|(?-i:\bCKD\b)[ -]?(?:stage[ -]?)?(?:5|V|G5)\b),?\s+(?:not (?:yet )?(?:on|receiving|requiring|undergoing|started on)|without|declin(?:es|ed|ing)|refus(?:es|ed|ing)|no|off|never on|not a candidate for|opts? against|elect(?:s|ed) against)\s+(?:(?:regularly|regular|scheduled|chronic|maintenance|any|renal replacement|hemo|peritoneal)\s*)*(?:dialysis|(?-i:HD|RRT|PD)\b|therapy)|\bpre-?dialysis (?:(?-i:ESRD|ESKD|CKD)|end[- ]stage)"#),
        Rule("aki", #"(?-i:\bAKI\b)|acute kidney injury|acute renal failure"#),
        Rule("ckd", #"(?-i:\b(?:CKD|CRI|CRF|ESRD|ESKD)\b)|chronic kidney disease|chronic renal (?:insufficiency|failure|disease)|renal insufficiency|end[- ]stage (?:renal|kidney)"#),
        Rule("bph", #"(?-i:\bBPH\b)|\bbenign prostatic (?:hyperplasia|hypertrophy|enlargement)\b|\bprostatic (?:hyperplasia|hypertrophy|enlargement)\b|\benlarged prostate\b|\bprostatomegaly\b"#, guarded: true),
        Rule("prostate-cancer", #"\bprostate (?:cancer|carcinoma|adenocarcinoma|ca)\b|\bprostatic (?:adeno)?carcinoma\b|\bcancer of the prostate\b|\bgleason\b"#, guarded: true),
        // A hiatal hernia is its own item since 1.9 ("gerd" was "Reflux or hiatal hernia").
        Rule("gerd", #"\bgerd\b|(?-i:\bGORD\b)|(?<!vesicoureteral )(?<!vesicoureteric )\breflux\b|heartburn"#),
        // 1.9 (GI & liver, Ben's list). A repaired hiatal hernia is the repair (Past surgical history), not a hernia.
        // The repair may come first ("s/p laparoscopic repair of paraesophageal hernia") or after a comma, a bracket or
        // "s/p" ("hiatal hernia, repaired 2019", "hiatal hernia s/p Nissen") (1.9 review).
        Rule("hiatal-hernia", #"\bhiatal hernia\b|\bhiatus hernia\b|\bpara-?o?esophageal hernia\b"#, guarded: true,
             notBefore: NoteRx(#"\b(?:repair|repaired|reduction|reduced|fundoplication)\s+(?:of\s+)?(?:(?:an?|the|his|her|large|small|giant|recurrent|laparoscopic|lap|robotic|open|type\s+(?:i{1,3}|iv|[1-4]))\s+){0,3}$"#),
             notAfter: NoteRx(#"^\s*(?:[,(]\s*)?(?:(?:s/p|status post|now|was|is)\s+)?(?:(?:lap(?:aroscopic)?|robotic|open)\s+)?(?:repair(?:ed)?|surgery|reduction|reduced|fundoplication|nissen|toupet|dor)\b"#)),
        // History of: never the operation planned ("for laparoscopic RYGB").
        Rule("gastric-bypass", #"\bgastric bypass\b|(?-i:\bR(?:N|ou)?YGB\b)|\broux[- ]en[- ]y (?:gastric )?bypass\b|\broux[- ]en[- ]y gastric\b"#,
             notBefore: plannedWide),
        Rule("dysphagia", #"\bdysphagia\b|\bodynophagia\b|\b(?:difficulty|trouble|problems?) (?:with )?swallowing\b|\bswallowing (?:difficult(?:y|ies)|problems?)\b"#, guarded: true),
        // Its name goes to the type (PatientHistoryDetails.esophagealDisorderType), which the TEE screen reads. Varices
        // are their own item.
        Rule("esophageal-disorder", #"\bachalasia\b|\besophageal (?:stricture|stenosis|cancer|carcinoma|adenocarcinoma|tumou?r|mass|web|ring|diverticulum|spasm|dysmotility|motility disorder|disorder|disease|perforation|atresia)\b|\bbarrett'?s(?: esophagus)?\b|\bzenker'?s(?: diverticulum)?\b|\beosinophilic esophagitis\b|(?-i:\bEoE\b)|\besophagitis\b|\bschatzki'?s? ring\b"#,
             guarded: true),
        // Active or resolved, upper or lower, to the details (readDetails19). Not a risk or prophylaxis ("GI bleed
        // prophylaxis", "stress ulcer prophylaxis"). Hematochezia alone is not read (hemorrhoids).
        Rule("gi-bleed", #"\b(?:upper |lower )?(?:gi|gastrointestinal)\s+(?:bleed(?:ing|s)?|h(?:a)?emorrhage)\b|(?-i:\b(?:GIB|UGIB|LGIB)\b)|\b(?:ugi|lgi)\s+bleed(?:ing|s)?\b|\bvariceal (?:bleed(?:ing)?|h(?:a)?emorrhage)\b|\bbleeding (?:peptic |duodenal |gastric )?ulcer\b|\bmelena\b|\bhematemesis\b"#,
             guarded: true),
        Rule("full-stomach", #"(?:small |large )?bowel obstruction|(?-i:\b(?:SBO|LBO)\b)|full stomach|\bileus\b"#),
        Rule("gastroparesis", #"gastroparesis"#),
        Rule("hepatitis-active", #"(?:active|acute) hepatitis"#),
        Rule("cirrhosis", #"cirrhosis|(?-i:\bESLD\b)|end[- ]stage liver"#),
        // Diabetes is one item (1.8.1): every mention files it, poorly controlled or not ("uncontrolled T2DM", "poorly
        // controlled sugars"); insulin mentions also file Diabetes treated with insulin. Not gestational diabetes,
        // prediabetes or diabetes insipidus.
        // A gestational diabetes's insulin is its own detail (1.9), unless a diabetes from before the pregnancy is named too.
        Rule("insulin", #"insulin[- ](?:dependent|requiring|treated)|\bon insulin\b|(?-i:\b(?:IDDM|T1DM|DM1|T1D|DMT1)\b)|type (?:1|one|i) (?:diabetes|dm)"#,
             notIf: NoteRx(#"^(?=.*(?:gestational diabetes|(?-i:GDM)))(?!.*(?:type (?:1|one|i|2|two|ii) (?:diabetes|dm)|(?-i:T1DM|T2DM|DM1|DM2|IDDM|NIDDM|T1D|T2D|DMT1|DMT2)|pre-?gestational|pre-?existing diabetes))"#)),
        Rule("dm", #"(?<!gestational )(?<!pre-)(?<!pre )\bdiabet(?:es|ic)\b(?! insipidus)|(?-i:\b(?:DM|T2DM|T1DM|NIDDM|IDDM|DM2|DMII|DM1|T2D|T1D|DMT2|DMT1)\b)|(?:poorly|badly|not well|sub-?optimally)[- ]controlled (?:blood )?(?:sugars|glucose)"#),
        Rule("thyroid", #"hypothyroid|hyperthyroid|thyroid disease|hashimoto|graves"#),
        Rule("adrenal", #"adrenal insufficiency|addison|chronic (?:steroids|prednisone)|(?:on|takes) (?:daily |chronic )?(?:prednisone|steroids|hydrocortisone)"#),
        Rule("anemia", #"\ban(?:a)?emi(?:a|c)\b"#),
        // ITP is Thrombocytopenia since 1.9, and a von Willebrand factor level is a lab, not the disease. The named
        // disorders (vWD, hemophilia A or B) file this item beside them, its base.
        Rule("bleeding", #"bleeding disorder|von willebrand(?!\s*(?:factor|antigen|panel|activity|level|testing)\b)|(?-i:\b(?:vWD|VWD)\b)|h(?:a)?emophilia(?!\s+(?:a\s+|b\s+)?carrier)|coagulopathy|bleeding diathesis"#),
        Rule("vwd", #"\bvon willebrand(?:'?s)?(?: disease)?\b(?!\s*(?:factor|antigen|panel|activity|level|testing)\b)|(?-i:\b(?:vWD|VWD)\b)"#),
        Rule("hemophilia-a", #"\bh(?:a)?emophilia\s+a\b(?!\s+carrier)|\bfactor (?:viii|8) deficiency\b"#),
        Rule("hemophilia-b", #"\bh(?:a)?emophilia\s+b\b(?!\s+carrier)|\bfactor (?:ix|9) deficiency\b|\bchristmas disease\b"#),
        // 1.9. Not heparin-induced thrombocytopenia (HIT: a heparin caution, not a low count of its own).
        Rule("thrombocytopenia", #"(?<!heparin[- ]induced )(?<!heparin induced )\bthrombocytopeni(?:a|c)\b|(?-i:\bITP\b)|\blow platelets?\b|\bplatelets? (?:are |is |were )?low\b"#,
             guarded: true),
        // Factor V Leiden is a thrombophilia (Ben, Nov 3): "fvl" beside "thrombophilia-heme", the Hematologic item; the
        // others' names go to its details. The Obstetric example ("thrombophilia", ASA III) is filed only for a pregnant
        // patient on anticoagulation (PatientNote.read).
        Rule("thrombophilia-heme", #"\bthrombophilia\b|\bantiphospholipid(?: antibody)?(?: syndrome)?\b|(?-i:\bAPLS\b)|\bprothrombin (?:gene )?(?:mutation|g20210a)\b|\bprotein [cs] deficiency\b|\bantithrombin(?: iii)? deficiency\b|\bfactor (?:v|5) leiden\b|(?-i:\bFVL\b)"#,
             negAfter: thrombophiliaNotPositive, guarded: true, notBefore: thrombophiliaNegativeBefore),
        Rule("fvl", #"\bfactor (?:v|5) leiden\b|(?-i:\bFVL\b)|\bf5 leiden\b"#,
             negAfter: thrombophiliaNotPositive, guarded: true, notBefore: thrombophiliaNegativeBefore),
        // On anticoagulation, in general words; a named drug files it too, with the drug (readAnticoagulants).
        Rule("anticoagulation", #"\b(?:on|receiving|requires?|requiring|needs?|chronic|therapeutic|long[- ]term|lifelong|systemic|full)\s+(?:(?:chronic|therapeutic|full|long[- ]term|lifelong|systemic|oral)\s+)?anticoagula(?:tion|nts?)\b|\banticoagulated\b|\bon (?:a )?blood thinners?\b|\bon (?:a )?(?-i:DOAC|NOAC|VKA|OAC)\b"#,
             negAfter: NoteRx(#"^\s*[:\-–]?\s*(?:none|no|n/a|nil|stopped|discontinued)\b"#)),
        Rule("vte", #"(?-i:\b(?:DVT|VTE)\b)|deep vein thrombosis|pulmonary embol"#),
        Rule("sickle", #"sickle cell(?! trait)|(?-i:\bHbSS\b)"#),
        Rule("dic", #"(?-i:\bDIC\b)|disseminated intravascular"#),
        Rule("declines-blood", #"jehovah|(?:declines|refuses) (?:all )?(?:blood|transfusion)|no blood products"#),
        // Infectious (1.8.1). A result that is not positive is not read ("HIV negative", "HCV Ab neg", "MRSA screen
        // negative", "PPD negative"); nor a bare "IE" (also "i.e.": PatientNote.neverRead) or "TB" inside a word. Active
        // hepatitis stays under GI & liver ("active hepatitis C" is both); sepsis under Acute illness.
        Rule("infection-active", #"\b(?:active|current|ongoing|untreated|systemic|uncontrolled)\s+(?:(?:bacterial|fungal|viral|wound|soft tissue)\s+)?infections?\b|\bbacter(?:a)?emi(?:a|c)\b|\bfung(?:a)?emia\b|\bcandid(?:a)?emia\b|\bpositive blood cultures?\b|\bblood cultures? (?:are |were )?positive\b|\binfected (?:hardware|graft|prosthesis|wound|joint|line|device|leads?|pacemaker|stent|mesh)\b"#),
        Rule("endocarditis", #"(?:\bendocarditis\b|(?-i:\bSBE\b))(?!\s+(?:prophylaxis|ppx|prevention))"#),
        Rule("hiv", #"\bhiv\b|\bhuman immunodeficiency virus\b|\bacquired immun(?:o)?deficiency syndrome\b"#, notIf: hivPrevention, negAfter: infectionNotPositive),
        // Hepatitis A as well since 1.9 (the type, A, B or C, to the details); an IgG or antibody to hepatitis A is immunity.
        // A spaced lowercase "a" before a lowercase word is the article ("autoimmune hepatitis a few years ago"), and a
        // vaccine or immunity may follow another type ("Hep A/B vaccinated") (1.9 review).
        Rule("hepatitis-viral", #"(?:\bhep(?:atitis)?\.?[- ]?[bc]\b|(?-i:\b(?:HBV|HCV|HBsAg)\b))(?!(?:\s*/\s*(?:hep(?:atitis)?\.?\s*)?[abc]\b)*\s+(?:vaccin|immun|surface antibody|s\s*ab\b|core antibody))|(?:\bhep(?:atitis)?\.?(?:-?a|\s+(?-i:A)|\s+a(?!\s+(?-i:[a-z])))\b|(?-i:\bHAV\b))(?!\s+(?:few|year|month|week|day|while|long|couple|decade|number|lot|bit)s?\b)(?!(?:\s*/\s*(?:hep(?:atitis)?\.?\s*)?[abc]\b)*\s+(?:vaccin\w*|immun\w*|igg|ab|antibody|antibodies|total)\b)"#, negAfter: infectionNotPositive),
        Rule("mdro", #"\b(?:mrsa|vre)\b|\bmethicillin[- ]resistant (?:staph(?:ylococcus)?|s\.)\s*(?:aureus)?|\bvancomycin[- ]resistant enterococc(?:us|i|al)\b"#, negAfter: infectionNotPositive),
        Rule("c-diff", #"\bc\.?\s?diff(?:icile)?\b|\bclostridi(?:um|oides) difficile\b|(?-i:\bCDI\b)"#, negAfter: infectionNotPositive),
        Rule("tb", #"(?:\btuberculosis\b|(?-i:\b(?:TB|LTBI)\b)|\blatent tb\b)(?!\s+exposure)|(?:\bpositive|\+)\s*(?:ppd|quantiferon|qft|igra|tst|tb test)\b|\b(?:ppd|quantiferon|qft|igra|tst)\s*(?:test\s*)?(?:\+|positive\b|pos\b)"#, negAfter: infectionNotPositive),
        Rule("covid-recent", covidRecent, notIf: covidNotRecent, negAfter: infectionNotPositive),
        Rule("isolation", #"\b(?:contact|droplet|airborne|enteric|respiratory|enhanced contact|special contact|contact plus)(?:\s*(?:/|and|&|\+|,)\s*(?:contact|droplet|airborne|enteric|respiratory))*\s+(?:isolation|precautions)\b|\b(?:on|in|under|requires?|requiring|needs?)\s+(?:strict\s+)?(?:contact\s+|droplet\s+|airborne\s+|respiratory\s+|reverse\s+|protective\s+|neutropenic\s+)?isolation\b|(?<!lung )(?<!vein )(?<!veins )(?<!wall )(?<!social )(?<!electrical )\bisolation\s+(?:precautions|room|status|for (?:mrsa|vre|c\.?\s?diff|covid|tb|flu|influenza|esbl|cre|mdro))\b|(?:^|[,;:(]\s*)isolation\b(?!\s+of\b)"#, negAfter: infectionNotPositive),
        // Sepsis and shock are there now (1.9: "h/o septic shock 2019" is not today's ASA IV). The source of the sepsis and
        // the kinds of shock ("septic" is distributive) go to the details.
        Rule("sepsis", #"\bsepsis\b|\burosepsis\b|\bseptic\b(?!\s+(?:arthritis|joint|knee|hip|bursitis|emboli|technique|tank))"#, current: true),
        // An allergy's reaction is not shock today ("Allergies: penicillin (anaphylactic shock)").
        Rule("shock", shockRx + #"|\bin shock\b"#, notIf: allergyShock, current: true),
        Rule("massive-trauma", #"massive trauma|polytrauma|multi-?trauma|multiple trauma"#),
        // 1.9. A major burn: a burn in TBSA, a major, full-thickness, third-degree or inhalation burn, a burn injury or a
        // burn unit; not a small burn, "burning", heartburn, nor a burn told as past.
        Rule("burn", #"\b\d{1,2}(?:\.\d)?\s*%\s*(?:tbsa\b\s*)?(?:(?:full|partial|mixed|deep partial)[- ]thickness\s+)?burns?\b|\b(?:tbsa|total body surface area)\b[^.;]{0,24}\bburns?\b|\bburns?\b[^.;]{0,24}\b(?:tbsa|total body surface area)\b|\b(?:major|severe|extensive|massive|large|full[- ]thickness|third[- ]degree|3rd[- ]degree|inhalation(?:al)?)\s+burns?(?:\s+injur(?:y|ies))?\b|\bburn (?:injury|injuries|patient|victim|unit|icu|center)\b|\binhalation injury\b"#,
             current: true, guarded: true),
        // Where the note does not say where (a specific site reads as the Aorta group's item). "Ruptured aortic aneurysm"
        // is always read; a bare "ruptured aneurysm" not when the note has intracranial words (a subarachnoid
        // hemorrhage: PatientNote.read drops it for the whole note) [P].
        Rule("ruptured-aneurysm", #"ruptured aortic aneurysm\b"#),
        Rule("ruptured-aneurysm", #"ruptured aneurysm\b"#, notIf: intracranialAneurysm),
        // G and P alone file Pregnant only when they leave a pregnancy uncounted (1.9: "G2P1" yes; "G2P2", "G3P2012" no:
        // readObstetric); weeks of gestation, an IUP and labor do.
        Rule("pregnant", #"\bpregnant\b|\b\d{1,2}(?:\s*\+\s*\d(?:/7)?| \d/7|\s*w(?:ks?|eeks?)?\s*\d\s*d(?:ays?)?)?\s*(?:weeks|wks|w)'?\s*(?:of\s+)?(?:gestation|pregnant|(?-i:GA)|gestational age|pregnancy)\b|(?-i:\bIUP\b)|\bparturient\b|\bin (?:active )?labou?r\b|\blabou?ring\b"#),
        Rule("gest-htn", #"gestational hypertension|(?-i:\b(?:gHTN|GHTN|PIH)\b)|pregnancy[- ]induced hypertension"#),
        Rule("preeclampsia-severe", #"pre-?eclampsia with severe features|severe pre-?eclampsia"#),
        Rule("preeclampsia", #"pre-?eclampsia"#),
        Rule("hellp", #"(?-i:\bHELLP\b)"#),
        // Gestational diabetes (1.9) is "gdm", with controlled or uncontrolled and insulin in the details; only the ASA's
        // own examples carry a class: diet-controlled ("gdm-diet", II) and with complications or high insulin needs
        // ("gdm-complex", III), each filed beside "gdm". Until 1.9 any GDM on insulin was "gdm-complex". A gestational
        // diabetes of an earlier pregnancy ("h/o GDM") is not this one's.
        Rule("gdm-complex", #"(?:gestational diabetes|(?-i:\bA?[12]?GDM(?:A[12])?\b))[^.;]{0,30}?\b(?:with complications|complicated by|high insulin (?:requirements?|needs|doses?)|requiring high(?:[- ]dose)? insulin)|\bhigh insulin (?:requirements?|needs)\b[^.;]{0,24}?(?:gestational diabetes|(?-i:GDM))|\bcomplicated (?:gestational diabetes|(?-i:GDM))\b"#,
             current: true),
        Rule("gdm-diet", #"\bdiet[- ]controlled (?:gestational diabetes|(?-i:GDM))\b|(?:gestational diabetes|(?-i:\bGDM\b)),? (?:diet[- ]controlled|controlled (?:with|by|on) diet|on diet(?: alone)?)\b|(?-i:\b(?:A1GDM|GDMA1)\b)"#, current: true),
        Rule("gdm", #"gestational diabetes|(?-i:\b(?:GDM|A1GDM|GDMA1|A2GDM|GDMA2)\b)"#, current: true),
        Rule("previa-accreta", #"placenta (?:previa|praevia|accreta|increta|percreta)|accreta spectrum"#),
        // Peripartum cardiomyopathy is "ppcm" (LVEF < 45%, ESC HFA: Bauersachs J, et al. Eur J Heart Fail 2019;21:827–843);
        // with an EF below 40% written beside it, the ASA's class IV example "peripartum-cm" replaces it (readRules).
        Rule("ppcm", #"\bperi-?partum cardiomyopathy\b|\bpost-?partum cardiomyopathy\b|\bpregnancy[- ]associated cardiomyopathy\b|(?-i:\bPPCM\b)"#),
        // An active rupture is the ASA's class V example; one told as past ("h/o", "in a prior pregnancy", "PMH:") is
        // "uterine-rupture-past" (1.9). Never the risk of one (VBAC counselling).
        Rule("uterine-rupture", #"\buterine rupture\b|\bruptured uterus\b|\brupture of (?:the |her )?uterus\b"#, current: true, guarded: true),
        Rule("uterine-rupture-past", #"\buterine rupture\b|\bruptured uterus\b|\brupture of (?:the |her )?uterus\b"#, pastOnly: true, guarded: true),
        Rule("ra", #"rheumatoid"#),
        // 1.9 (Musculoskeletal, Ben's list). The joint goes to the arthritis location (readRules).
        // A bare "OA" in a labor note is the fetal position, occiput anterior ("vertex OA", "OA position") (1.9 review).
        Rule("oa", #"\bosteoarthritis\b|\bosteoarthrosis\b|(?<!vertex )(?<!vtx )(?<!cephalic )(?<!direct )(?<!fetal )(?<!fetus )(?<!baby )(?<!head )(?<!position )(?<!presentation )(?-i:\bOA\b)(?!\s*(?:position|presentation|vertex|vtx)\b)(?!\s*/\s*(?:\d|[LR]?OP\b))|\bdegenerative joint disease\b|(?-i:\bDJD\b)"#),
        // A fracture there now, with its place (the location); not a risk ("fracture risk", "evaluate for fracture"), nor
        // one told as past ("h/o hip fracture", "s/p ORIF of a hip fracture"; "s/p fall with a hip fracture" is now).
        // "fx" as function is not a fracture ("normal LV fx", "renal fx stable", "lung fx on PFTs") (1.9 review).
        Rule("fracture", #"\bfractures?\b|(?<!lv )(?<!rv )(?<!la )(?<!bv )(?<!lvs )(?<!ventricular )(?<!biventricular )(?<!systolic )(?<!diastolic )(?<!cardiac )(?<!heart )(?<!valve )(?<!valvular )(?<!renal )(?<!kidney )(?<!liver )(?<!hepatic )(?<!lung )(?<!pulmonary )(?<!pulm )(?<!thyroid )(?<!adrenal )(?<!bowel )(?<!bladder )(?<!sexual )(?<!cognitive )(?<!neuro )(?<!motor )(?<!sensory )(?<!platelet )(?<!immune )(?<!synthetic )(?<!graft )(?<!nl )(?<!normal )(?<!baseline )(?<!organ )(?<!pump )(?<!marrow )(?<!ventilatory )(?<!respiratory )(?<!diaphragm )(?<!diaphragmatic )(?<!swallow )(?<!swallowing )(?<!pft )\bfx\b(?!\s+(?:tests?|testing|studies|study|panel|wnl|nl|normal|preserved|intact|impaired|reduced|decreased|depressed|improved|worsening|declin\w*)\b)"#, current: true, guarded: true, notAfter: NoteRx(#"^\s*(?:liaison|clinic|service|team|prevention)\b"#)),
        Rule("muscular-dystrophy", #"\bmuscular dystroph(?:y|ies)\b|\bduchenne(?:'s)?\b|\bbecker(?:'s)? (?:muscular )?dystrophy\b|(?-i:\bDMD\b)|\bmyotonic (?:muscular )?dystrophy\b|\bfacioscapulohumeral\b|(?-i:\bFSHD\b)|\blimb[- ]girdle\b"#),
        Rule("marfan", #"\bmarfan(?:'?s)?(?: syndrome)?\b"#),
        // A typed "EDS" is asked: Ehlers-Danlos or excessive daytime sleepiness (MedAbbreviations).
        Rule("eds", #"\behlers[- ]danlos(?: syndrome)?\b|(?-i:\b(?:hEDS|vEDS)\b)"#),
        Rule("compartment-syndrome", #"\bcompartment syndrome\b"#, current: true, guarded: true),
        Rule("spine-fusion", #"ankylosing spondylitis|cervical (?:spine )?fusion|(?-i:\bACDF\b)|fused (?:cervical|neck)"#),
        Rule("cspine-unstable", #"unstable (?:c-?spine|cervical spine)"#),
        Rule("scoliosis", #"scoliosis"#),
        // A dependence told as former ("former alcohol abuse", "alcohol use disorder in remission", "sober 10 years") is
        // "alcohol-abuse-former" since 1.9, with no ASA class; the ASA's class III example is a current one.
        Rule("alcohol-abuse", #"alcohol (?:abuse|use disorder|dependence)|alcoholism|\betoh (?:abuse|use disorder|dependence)|heavy (?:drinker|drinking|alcohol|etoh)|drinks (?:heavily|daily)|\b\d+ (?:beers|drinks) (?:a|per) day"#,
             notBefore: formerBefore, notAfter: formerAfter),
        Rule("alcohol-abuse-former", #"\b(?:former|ex-?|past|previous|prior|remote|recovering|recovered)\s+(?:heavy\s+(?:drinker|drinking|alcohol(?: use)?|etoh(?: use)?)|alcoholic|alcoholism|(?:alcohol|etoh)\s+(?:abuse|use disorder|dependence|misuse))\b|\b(?:alcoholism|(?:alcohol|etoh)\s+(?:abuse|use disorder|dependence|misuse))\b[^.;]{0,30}?\b(?:in (?:sustained |early )?remission|sober|abstinent|quit|stopped)\b|\bsober (?:for|since|x)\b|\brecovering alcoholic\b"#),
        Rule("alcohol-social", #"(?:social|occasional|rare) (?:alcohol|drinker|etoh|drinking)|drinks (?:socially|occasionally)|etoh socially"#),
        // Illicit drug use (1.9: "substance", in any drug), with the drugs beside it; methadone or buprenorphine treatment
        // is not illicit use (its medicine flag, opioid, is set from the medicines), and neither is topical cocaine. A use
        // told as former ("quit", "in remission", "clean 5 years") is not read.
        Rule("substance", #"\bsubstance (?:use|abuse|misuse)(?: disorder)?\b|\bpolysubstance\b|\billicit (?:drugs?|drug use|substances?)\b|\brecreational drugs?(?: use)?\b|\bstimulant (?:use|abuse)\b|\bamphetamine (?:use|abuse|misuse)\b|(?-i:\b(?:IVDU|IVDA|PWID)\b)|\b(?:iv|intravenous|injection) drug (?:use|abuse|user)s?\b|\bdrug (?:abuse|addiction)\b"#,
             negAfter: drugNegAfter, notBefore: formerBefore, notAfter: formerAfter),
        Rule("cocaine", #"\bcocaine\b|\bcrack (?:cocaine|use|user|smoker|abuse)\b"#, negAfter: drugNegAfter,
             notBefore: NoteRx(#"(?:\b(?:topical|nasal|intranasal)|\d+(?:\.\d+)?\s*%|\b(?:former|ex-?|past|previous|prior|remote|quit|stopped|recovering|recovered|clean|sober))\s+(?:(?:iv|intravenous|heavy|daily|occasional|crack)\s+)?$"#),
             notAfter: NoteRx(#"^\s*(?:pledgets?|paste|solution|spray|topical|\d+\s*%|4\s*%)|"# + formerAfterText)),
        Rule("opioid-use", #"\bheroin\b|(?-i:\bOUD\b)|\bopioid use disorder\b|\bopioid (?:abuse|misuse|addiction)\b|\b(?:illicit|street|non-?prescribed) (?:opioids?|fentanyl|pills)\b|\bfentanyl (?:use|abuse|misuse|smoking)\b"#,
             negAfter: drugNegAfter, notBefore: formerBefore, notAfter: formerAfter),
        Rule("marijuana", #"\bmarijuana\b|\bmarihuana\b|\bcannabis\b(?!\s+(?:oil|cbd))|(?-i:\bTHC\b)|\b(?:smokes?|smoking|uses?|using) (?:weed|pot)\b"#,
             negAfter: drugNegAfter, notBefore: formerBefore, notAfter: formerAfter),
        Rule("methamphetamine", #"\bmethamphetamines?\b|\bcrystal meth\b|\bmeth\b(?!\s*-?(?:hb|hgb|h(?:a)?emoglobin))"#,
             negAfter: drugNegAfter, notBefore: formerBefore, notAfter: formerAfter),
    ]

    /// A general item and the more specific ones that replace it ("hypertension, well controlled" by "poorly
    /// controlled").
    static let supersededBy: [String: [String]] = [
        "htn": ["htn-180"], "cad": ["mi", "cad-recent", "pci", "pci-recent", "ischemia", "cabg"], "mi": ["cad-recent"], "pci": ["pci-recent"], "cva": ["cva-recent"], "cva-unspec": ["cva", "cva-recent"], "ich": ["ich-mass"],
        "hf": ["hf-decomp"], "ef-moderate": ["ef-severe"], "pulm-htn": ["pulm-htn-severe"], "chd": ["chd-elevated"],
        "asthma": ["asthma-uncontrolled"], "ckd": ["esrd-dialysis"], "gdm-diet": ["gdm-complex"], "alcohol-social": ["alcohol-abuse", "alcohol-abuse-former"],
        // 1.9: Alcohol is one answer (a current dependence over a former one); an EF below 40% makes the peripartum
        // cardiomyopathy the ASA's class IV example.
        "alcohol-abuse-former": ["alcohol-abuse"], "ppcm": ["peripartum-cm"],
        "aaa": ["aaa-ruptured"], "taa": ["taa-ruptured"], "taaa": ["taaa-ruptured"],
        "ruptured-aneurysm": ["aaa-ruptured", "taa-ruptured", "taaa-ruptured"],
        "preeclampsia": ["preeclampsia-severe", "hellp"], "gest-htn": ["preeclampsia", "preeclampsia-severe", "hellp"],
    ]

    /// Items whose catalog wording says more than a note usually does.
    private static let cautions: [String: String] = [
        "mi": "Added as over 3 months ago; choose within 3 months in History if recent.",
        "pci": "Added as over 3 months ago; choose within 3 months in History if recent.",
        "cva": "Added as over 3 months ago; choose within 3 months in History if recent.",
    ]

    private static let anesthesiaRules: [Rule] = [
        Rule("ponv", #"(?-i:\bPONV\b)|post-?op(?:erative)? nausea|motion sickness|nausea(?: and vomiting)? (?:after|with|following) (?:an(?:a)?esthesia|surgery|(?-i:GA))"#),
        Rule("difficult-airway", #"difficult (?:airway|intubation|mask(?: ventilation)?|laryngoscopy|bag[- ]mask)|failed intubation|difficult airway letter"#),
        Rule("mh", #"malignant hyperthermia|(?-i:\bMH\b)(?! negative)"#, family: true),
        Rule("pseudocholinesterase", #"pseudocholinesterase|butyrylcholinesterase|plasma cholinesterase deficiency|prolonged (?:paralysis|apn(?:o)?ea|block) after (?:sux|succinylcholine|suxamethonium)|sux apn(?:o)?ea"#),
        Rule("awareness", #"awareness (?:under|during) an(?:a)?esthesia|intraoperative awareness|woke up during (?:surgery|the operation)"#),
        Rule("delirium", #"emergence (?:delirium|agitation)"#),
    ]

    private static let symptomRules: [Rule] = [
        Rule("chest-pain", #"chest (?:pain|tightness|pressure|discomfort)|\bangina\b"#),
        Rule("dyspnea", #"dyspn(?:o)?ea|shortness of breath|short of breath|(?-i:\b(?:SOB|DOE)\b)|breathless"#),
        Rule("palpitations", #"palpitations"#),
        Rule("tachycardia", #"(?<!ventricular )(?<!supraventricular )(?<!atrial )\btachycardi(?:a|c)\b"#),
        Rule("syncope", #"syncop(?:e|al)|passed out|fainted|fainting"#),
        Rule("murmur", #"\bmurmurs?\b"#),
        Rule("hf-signs", #"(?:leg|ankle|pedal|peripheral|lower extremity|lower limb|(?-i:LE)) (?:edema|oedema|swelling)|orthopn(?:o)?ea|(?-i:\b(?:PND|JVD)\b)|paroxysmal nocturnal|(?:elevated|raised) (?:jvp|jugular venous pressure)|\bcrackles\b|\brales\b|(?-i:\bS3\b)"#),
    ]

    /// Figure 1's acute conditions; read only when the note does not place them in the past.
    private static let acuteRules: [Rule] = [
        Rule("acs", #"(?-i:\bACS\b)|acute coronary syndrome|unstable angina|acute (?:mi|myocardial infarction)"#),
        Rule("decomp-hf", #"decompensated (?:heart failure|hf|chf)|(?:chf|heart failure|hf) exacerbation|acute (?:on chronic )?(?:(?:systolic|diastolic) )?(?:heart failure|chf)|(?-i:\bADHF\b)"#),
        Rule("arrhythmia", #"rapid ventricular response|(?-i:\bRVR\b)|unstable (?:arrhythmia|rhythm|tachyarrhythmia)|(?-i:\b(?:VT|VF)\b) storm|symptomatic bradycardia|complete heart block|third[- ]degree (?:heart |av )?block|(?-i:\bCHB\b)"#),
    ]

    private static let signRules: [Rule] = [
        Rule("mouth", #"(?:limited|small|reduced|restricted|poor|decreased) mouth opening|mouth opening (?:is )?(?:limited|reduced|restricted|small)|(?:mouth opening|interincisor (?:gap|distance))\s*(?:<|less than|under)\s*3\s*cm"#),
        Rule("tmd", #"(?:short|small|reduced) (?:thyromental distance|(?-i:TMD))|(?:(?-i:TMD)|thyromental distance)\s*(?:<|less than|under)\s*(?:3\s*(?:fb|finger)|6\s*cm|three finger)"#),
        Rule("smd", #"(?:sternomental distance|(?-i:SMD))\s*(?:<|less than|under|≤)\s*12(?:\.5)?\s*cm"#),
        Rule("neck", #"(?:limited|reduced|restricted|decreased|poor) (?:neck|cervical) (?:movement|motion|extension|flexion|mobility|(?-i:ROM)|range of motion)|(?:neck|cervical) (?:extension|flexion|(?-i:ROM)|range of motion|mobility) (?:is )?(?:limited|reduced|restricted|decreased)|cannot extend (?:the |his |her )?neck"#),
        Rule("jaw", #"(?:cannot|can't|unable to) protrude (?:the |his |her )?(?:jaw|mandible)|(?:limited|reduced|poor) (?:jaw|mandibular) protrusion"#),
        Rule("ulbt", #"(?:(?-i:ULBT)|upper lip bite test)\s*(?:class|grade)?\s*(?:iii|3)\b"#),
        Rule("incisors", #"(?:prominent|long|protruding|buck) (?:upper )?(?:incisors|teeth)|overbite"#),
        Rule("palate", #"high[- ]arched palate|narrow palate"#),
        Rule("mandible", #"(?:stiff|indurated|non-?resilient|firm) (?:sub)?mandibular"#),
        Rule("thick-neck", #"(?:short|thick|large|wide) neck"#),
        Rule("neck40", #"neck (?:circumference|circ\.?)\s*(?:of|is|:|=)?\s*(?:4[1-9]|[5-9]\d)(?:\.\d)?\s*cm|neck (?:circumference|circ\.?)\s*(?:>|over|more than|greater than)\s*40"#),
        Rule("beard", #"\bbeard(?:ed)?\b|facial hair"#),
        Rule("edentulous", #"edentulous|no teeth|full dentures"#),
        Rule("radiation", #"(?:neck|head and neck|cervical|(?-i:H&N)) (?:radiation|irradiation|(?-i:XRT)|radiotherapy)|radiation to the neck|(?-i:XRT) to (?:the )?neck"#),
        Rule("mass", #"(?:airway|neck|laryngeal|tongue|tracheal|mediastinal|oropharyngeal|glottic) (?:mass|tumou?r|lesion)|\bstridor\b|\bgoit(?:er|re)\b|ludwig|epiglottitis|peritonsillar abscess"#),
    ]

    private static let noHistoryRx = NoteRx(#"\b(?:no significant (?:pmh|past medical history|medical history|history)|no (?:pmh|past medical history|medical history)|(?:previously|otherwise) (?:healthy|well)|nil pmh|pmh:?\s*(?:none|nil|non-?significant|non-?contributory|unremarkable|negative))\b|^\s*(?:a\s+)?healthy\b"#)
    private static let esrdRx = NoteRx(#"(?-i:\b(?:ESRD|ESKD)\b)|end[- ]stage (?:renal|kidney)"#)

    // MARK: Medicines

    /// Medicine name → the medication flag it sets ("" when the name only joins the list).
    private static let drugs: [String: String] = {
        var d: [String: String] = [:]
        func add(_ flag: String, _ names: [String]) { for n in names { d[n] = flag } }
        add("anticoagulant", ["warfarin", "coumadin", "apixaban", "eliquis", "rivaroxaban", "xarelto", "dabigatran", "pradaxa", "edoxaban", "savaysa", "enoxaparin", "lovenox", "dalteparin", "heparin", "fondaparinux", "arixtra"])
        add("p2y12", ["clopidogrel", "plavix", "ticagrelor", "brilinta", "prasugrel", "effient", "ticlopidine"])
        add("aspirin", ["aspirin", "baby aspirin"])
        add("insulin", ["insulin", "glargine", "lantus", "basaglar", "toujeo", "lispro", "humalog", "aspart", "novolog", "detemir", "levemir", "degludec", "tresiba", "humulin", "novolin"])
        add("glp1", ["semaglutide", "ozempic", "wegovy", "rybelsus", "liraglutide", "victoza", "saxenda", "dulaglutide", "trulicity", "tirzepatide", "mounjaro", "zepbound", "exenatide", "byetta", "bydureon", "lixisenatide"])
        add("sglt2", ["empagliflozin", "jardiance", "dapagliflozin", "farxiga", "canagliflozin", "invokana", "ertugliflozin", "steglatro", "sotagliflozin"])
        add("betablocker", ["metoprolol", "lopressor", "toprol", "atenolol", "carvedilol", "coreg", "bisoprolol", "propranolol", "labetalol", "nebivolol", "bystolic", "nadolol", "sotalol"])
        add("acei", ["lisinopril", "enalapril", "ramipril", "benazepril", "captopril", "quinapril", "fosinopril", "perindopril", "trandolapril", "losartan", "cozaar", "valsartan", "diovan", "irbesartan", "olmesartan", "candesartan", "telmisartan", "azilsartan", "sacubitril", "entresto"])
        add("steroid", ["prednisone", "prednisolone", "methylprednisolone", "medrol", "hydrocortisone", "fludrocortisone", "dexamethasone"])
        add("opioid", ["oxycodone", "oxycontin", "percocet", "hydrocodone", "norco", "vicodin", "morphine", "hydromorphone", "dilaudid", "methadone", "buprenorphine", "suboxone", "subutex", "tramadol", "tapentadol", "oxymorphone", "fentanyl patch"])
        add("maoi", ["phenelzine", "nardil", "tranylcypromine", "parnate", "isocarboxazid", "selegiline", "emsam", "rasagiline", "azilect", "safinamide"])
        add("statin", PatientFunctional.statinNames)
        add("", ["metformin", "glipizide", "glyburide", "glimepiride", "sitagliptin", "januvia", "pioglitazone", "ezetimibe", "amlodipine", "norvasc", "nifedipine", "diltiazem", "verapamil", "hydralazine", "furosemide", "lasix", "torsemide", "bumetanide", "hydrochlorothiazide", "hctz", "chlorthalidone", "spironolactone", "eplerenone", "digoxin", "amiodarone", "flecainide", "isosorbide", "nitroglycerin", "levothyroxine", "synthroid", "omeprazole", "pantoprazole", "esomeprazole", "famotidine", "albuterol", "tiotropium", "fluticasone", "budesonide", "montelukast", "gabapentin", "pregabalin", "sertraline", "escitalopram", "citalopram", "fluoxetine", "paroxetine", "bupropion", "venlafaxine", "duloxetine", "trazodone", "quetiapine", "olanzapine", "risperidone", "lithium", "levetiracetam", "keppra", "lamotrigine", "valproate", "carbamazepine", "phenytoin", "carbidopa", "levodopa", "donepezil", "allopurinol", "tamsulosin", "finasteride", "acetaminophen", "tylenol", "ibuprofen", "naproxen", "celecoxib", "methotrexate", "colchicine", "clonidine", "terazosin", "doxazosin", "alprazolam", "lorazepam", "clonazepam", "diazepam", "zolpidem"])
        return d
    }()

    private static let drugRx: NoteRx = {
        let names = drugs.keys.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: "\\s+") }
        return NoteRx("\\b(" + names.joined(separator: "|") + ")\\b")
    }()

    /// Drug classes, as written or as an abbreviation reads ("BB" as beta-blocker), and the flag each sets.
    private static let drugClasses: [(NoteRx, String)] = [
        (NoteRx(#"\bbeta[- ]?blockers?\b|β[- ]?blockers?"#), "betablocker"),
        (NoteRx(#"\bace[- ]?inhibitors?\b|angiotensin[- ]converting enzyme inhibitors?|angiotensin (?:ii )?receptor blockers?|angiotensin receptor-neprilysin"#), "acei"),
        (NoteRx(#"\b(?:direct|novel) oral anticoagulants?|\bvitamin k antagonists?|low[- ]molecular[- ]weight heparin|unfractionated heparin|subcutaneous heparin|(?-i:\b(?:DOAC|NOAC|VKA|OAC|LMWH|UFH)\b)|\b(?:oral )?anticoagulants?\b|\banticoagulat(?:ion|ed)\b"#), "anticoagulant"),
        (NoteRx(#"\bp2y12 (?:inhibitors?|antagonists?)|\bdual antiplatelet"#), "p2y12"),
        (NoteRx(#"\bdual antiplatelet"#), "aspirin"),
        (NoteRx(#"\bsglt-?2 inhibitors?"#), "sglt2"),
        (NoteRx(#"\bglp-?1 (?:receptor )?agonists?"#), "glp1"),
        (NoteRx(#"\bmao inhibitors?|monoamine oxidase inhibitors?"#), "maoi"),
        (NoteRx(#"\b(?:on|takes|taking) (?:chronic |daily |long[- ]term )?(?:steroids|corticosteroids)\b|\bchronic (?:steroids|corticosteroids)\b"#), "steroid"),
        (NoteRx(#"\bchronic opioids?\b|\bopioid[- ]tolerant\b|\b(?:on|takes|taking) (?:chronic |daily )?opioids\b"#), "opioid"),
    ]

    /// A medicine running as an infusion, with its rate when given: "norepinephrine infusion at 0.05 mcg/kg/min" ("levo
    /// gtt" reads as one), or a medicine with a rate per minute or hour ("propofol 30 mcg/kg/min"; not a fentanyl patch).
    static let infusionRx = NoteRx(#"\b(nitroglycerin|nitroprusside|epinephrine|norepinephrine|phenylephrine|vasopressin|dobutamine|dopamine|milrinone|isoproterenol|nicardipine|clevidipine|esmolol|diltiazem|amiodarone|lidocaine|heparin|bivalirudin|argatroban|insulin|propofol|dexmedetomidine|ketamine|fentanyl|remifentanil|sufentanil|hydromorphone|morphine|midazolam|cisatracurium|rocuronium|vecuronium|labetalol|magnesium|oxytocin|epoprostenol|treprostinil|furosemide|bumetanide|octreotide|pantoprazole|angiotensin ii|methylene blue|levosimendan|eptifibatide|tirofiban|alteplase|naloxone|sodium bicarbonate|bicarbonate)\s+(?:(?:infusion|drip|gtt)s?\b(?:\s*(?:at|@|of|running at|=|:)?\s*(\d+(?:\.\d+)?)(?:\s*((?:mcg|mg|units?|u|ng|g|ml|meq|mmol)(?:\s*/\s*kg)?(?:\s*/\s*(?:min|minute|hr|hour|h))?)\b)?)?|(?:at\s+|@\s*)?(\d+(?:\.\d+)?)\s*((?:mcg|mg|units?|u|ng|g|ml|meq|mmol)(?:\s*/\s*kg)?\s*/\s*(?:min|minute|hr|hour|h))\b(?!\s*patch))"#)
    /// An infusion that has been stopped ("weaned off the norepinephrine infusion").
    static let offCue = NoteRx(#"\b(?:off|weaned|stopped|discontinued|held|d/c'?d|dc'?d)\b[^.;,]{0,20}$"#)

    // MARK: Context

    private static let negCue = NoteRx(#"\b(?:no|not|denies|denied|deny|negative for|neg for|without|never|free of|nor|r/o|rule out|ruled out|absent|w/o)\b"#)
    private static let negEnd = NoteRx(#"\b(?:but|however|although|though|except|apart from|aside from|positive for|significant for|notable for|reports|endorses|complains of|c/o|presents|admits|has|have|can|could|uses|takes|walks|climbs|lives|works)\b|[;:]|(?:,|\band\b)\s*(?:had|is|was|with|on|also)\b"#)
    private static let famCue = NoteRx(#"\b(?:family history|fhx|(?-i:FH)|mother|father|brother|sister|siblings?|parents?|grandmother|grandfather|grandparents?|aunt|uncle)\b"#)
    private static let famEnd = NoteRx(#"\b(?:patient|pt|he|she|they|himself|herself|personally|but|however|otherwise|whereas|own)\b|;|,\s*(?:has|have|had|is|was|also)\b"#)
    private static let pastBefore = NoteRx(#"\b(?:recent|recently|prior|previous|previously|history of|hx of|h/o|s/p|status post|old|remote|resolved)\b[^.;]{0,20}$"#)
    private static let pastAfter = NoteRx(#"^[^.;]{0,15}\b(?:in (?:19|20)\d\d|\d+ (?:years?|yrs?|months?) ago|last year)\b"#)
    /// 1.9. Before a mention: a risk, a suspicion, a screen or a differential, not the diagnosis ("at risk for
    /// compartment syndrome", "concern for GI bleed", "possible PTX", "evaluate for fracture", "vs pneumothorax").
    static let riskBefore = NoteRx(#"\b(?:at (?:high |increased |low )?risk (?:of|for)|risks? (?:of|for|include|including)|high[- ]risk (?:of|for)|concern(?:ed|ing)? (?:for|about|of)|evaluat(?:e|ed|ion|ing) (?:for|of)|eval (?:for|of)|monitor(?:ed|ing)? for|watch(?:ing)? for|assess(?:ed|ing)? for|screen(?:ed|ing)? for|work-?up (?:for|of)|prevent(?:ion of|ing)?|prophylaxis (?:of|for|against)|counsel(?:l)?ed (?:on|about|regarding)|discussed|possible|possibly|probable|suspected|suspicion (?:of|for)|presumed|questionable|query|likely|unlikely|versus|vs\.?|\?)\s*(?:(?:an?|the|acute|new|recurrent|developing|impending|worsening|any|for|of|left|right|bilateral|l|r)\s+){0,3}$"#)
    /// After a mention: "fracture risk", "compartment checks", "PTX?", "GI bleed was ruled out".
    static let riskAfter = NoteRx(#"^\s*(?:risks?|precautions?|prophylaxis|ppx|prevention|protocol|checks?|screen(?:ing)?|work-?up|rule[- ]out|r/o|watch|monitoring|concerns?|education|counsel\w*|vs\.?|versus)\b|^\s*\?|^\s*(?:is|was)\s+(?:possible|suspected|likely|unlikely|ruled out|excluded)\b"#)
    /// 1.9. A mention told as past, for an item that is there now: a history cue before it ("h/o", "s/p ORIF of", not "s/p
    /// fall with": the event behind a current injury), a year before this one, "years ago" or "in a prior pregnancy"
    /// after it, or a past-history heading before it ("PMH: …, hip fracture").
    static let historyCueRx = NoteRx(#"\b(?:prior|previous|previously|history of|hx of|h/o|s/p|status post|old|remote|resolved|healed|childhood)\b([^.;,]{0,30})$"#)
    /// Between a history cue and the mention: the event behind a current injury, or words that make it now ("h/o AF, now
    /// with PTX" is cut at the comma; "h/o AF now with PTX" is read here).
    static let causeWords = NoteRx(#"\b(?:falls?|fell|mvc|mva|accident|trauma|injur\w*|assault\w*|collision|crash|gsw|gunshot|stab\w*|glf|fire|explosion|ejection|struck|motorcycle|bicycle|now|currently|presents?|presenting|presented|admitted|new|acute)\b"#)
    static let pastTailRx = NoteRx(#"^[^.;,]{0,30}?(?:\(?\b"# + pastYears + #"\b|\b\d+ (?:years?|yrs?|months?|mos?) ago\b|\blast year\b|\bas a (?:child|kid|teen\w*)\b|\bin (?:childhood|the past)\b|\b(?:resolved|healed)\b|\bin (?:a |her |the )?(?:prior|previous|last|first|1st|second|2nd) (?:pregnanc(?:y|ies)|deliver(?:y|ies)|labou?r)\b|\bwith (?:her )?(?:first|prior|previous|last) (?:pregnancy|delivery|child|baby)\b)"#)
    static let pmhBefore = NoteRx(#"\b(?:pmh|pmhx|past medical history|medical history|ob(?:stetric)? (?:history|hx)|obhx|(?:prior|previous) pregnanc(?:y|ies))\b"#)

    /// A dependence or a drug use told as over: "former", "ex-", "recovered" before it; "in remission", "quit", "sober",
    /// "clean" or "years ago" after it.
    static let formerBefore = NoteRx(#"\b(?:former|ex|past|previous|prior|remote|recovering|recovered|quit|stopped|clean|sober)(?:-|\s+)(?:(?:iv|intravenous|heavy|daily|occasional)\s+)?$"#)
    static let formerAfterText = #"^[^.;]{0,30}?\b(?:in (?:sustained |early |full )?remission|sober|abstinent|quit|stopped|clean|no longer|(?:\d+|many|several) (?:years?|yrs?) ago)\b"#
    static let formerAfter = NoteRx(formerAfterText)
    /// After a drug: a negative screen ("cocaine negative", "UDS: neg"), or a templated answer that denies it ("Illicit
    /// drugs: denies", "Marijuana use: Never", "Cocaine: n/a").
    static let drugNegAfter = NoteRx(#"^\s*(?:screen|tox|uds|use)?\s*[:=]?\s*(?:neg(?:ative)?\b|[-−](?=[\s,;.)]|$)|none\b|denied\b|denies\b|deny\b|never\b|no\b|n/a(?![\w/])|nil\b)"#)
    /// Before an operation: the one planned, not one in the past ("for laparoscopic RYGB", "scheduled for gastric bypass",
    /// "for left AVF"), or the one under a procedure heading ("Procedure: Laparoscopic Roux-en-Y gastric bypass", "Planned
    /// procedure: RYGB"; not "Prior surgery: RYGB 2015") (1.9 review).
    static let plannedWide = NoteRx(#"(?:\b(?:for|undergo(?:ing)?|to undergo|scheduled(?: for)?|planned|planning|booked(?: for)?|candidate for|evaluation for|eval for|consult(?:ed)? for|referred for|considering)\s+|(?:^|[.;,(]\s*)(?:(?:planned|proposed|scheduled|today'?s)\s+)?(?:procedure|surgery|operation|case)\s*[:\-–]\s*)(?:(?:an?|the|elective|urgent|laparoscopic|lap|robotic|robot-assisted|open|revision(?: of)?|redo|possible|conversion to|left|right|l|r|lt|rt|bilateral)\.?\s+){0,4}$"#)
    /// The kinds of shock (1.9: Ben's list, cardiogenic, distributive, obstructive, hypovolemic; septic, anaphylactic,
    /// neurogenic and vasoplegic shock are distributive, hemorrhagic shock hypovolemic).
    static let shockKinds = #"septic|cardiogenic|h(?:a)?emorrhagic|hypovol(?:a)?emic|distributive|obstructive|anaphylactic|neurogenic|vasoplegic|vasodilatory|mixed"#
    /// An allergy sentence that names an anaphylactic shock: the reaction recorded, not a shock now.
    static let allergyShock = NoteRx(#"^(?=.*(?:allerg|intoleran|reaction to|(?-i:\bNKDA\b)))(?=.*\banaphylactic\s+shock\b)"#)
    static let shockRx = #"\b(?:"# + shockKinds + #")(?:\s*(?:,|/|and|&|\+|or)?\s*(?:"# + shockKinds + #"))*\s+shock\b"#

    private static func toldAsPast(_ c: String, _ m: NSTextCheckingResult) -> Bool {
        let ns = c as NSString
        let before = ns.substring(to: m.range.location), after = ns.substring(from: m.range.location + m.range.length)
        if let h = historyCueRx.first(before), causeWords.first(h.text(1, in: before) ?? "") == nil { return true }
        return pastTailRx.first(after) != nil || pmhBefore.first(before) != nil
    }
    /// A sentence about past surgery or anesthetics: its leftovers go to the anesthesia-history details, and a
    /// technique it names is not read as the planned one.
    private static let pastCare = NoteRx(#"\b(?:psh|pshx|past surgical history|surgical history|prior surger(?:y|ies)|previous surger(?:y|ies)|previous an(?:a)?esthe|prior an(?:a)?esthe|an(?:a)?esthetic history|uneventful|tolerated (?:ga|general|an(?:a)?esthesia))"#)
    /// A plan sentence: its leftovers ("ETT, PACU") are not conditions.
    private static let planClause = NoteRx(#"^\s*(?:plan|a/p|assessment and plan|anesthetic plan|anesthesia plan|dispo|disposition)\b"#)
    private static let surgicalPiece = NoteRx(#"^(?:s/p|status post)\b|ectomy\b|otomy\b|plasty\b|oscopy\b|\brepair\b|\bsurgery\b|\boperation\b|(?-i:\b(?:ORIF|TKA|THA|TKR|THR)\b)|c-?section|cesarean"#)

    /// A negation cue before a mention, within its scope ("denies chest pain, SOB" but not "no CAD, has DM").
    static func negated(_ c: String, at loc: Int) -> Bool { inScope(negCue, end: negEnd, in: c, at: loc) }

    /// A family-history cue before a mention, within its scope ("father had an MI", "FHx: CAD, DM").
    static func familyContext(_ c: String, at loc: Int) -> Bool { inScope(famCue, end: famEnd, in: c, at: loc) }

    private static func inScope(_ cue: NoteRx, end: NoteRx, in c: String, at loc: Int) -> Bool {
        let ns = c as NSString
        let at = max(0, min(loc, ns.length))
        let prefix = ns.substring(to: at)
        guard let m = cue.all(prefix).last else { return false }
        let between = (prefix as NSString).substring(from: m.range.location + m.range.length)
        // The mention's own first word can end the scope too ("no chest pain can climb two flights").
        let word = String(ns.substring(from: at).prefix(while: { $0.isLetter }))
        return between.count <= 80 && end.first(between + word + " ") == nil
    }

    private static func past(_ c: String, _ m: NSTextCheckingResult) -> Bool {
        let ns = c as NSString
        let before = ns.substring(to: m.range.location)
        let after = ns.substring(from: m.range.location + m.range.length)
        return pastBefore.first(before) != nil || pastAfter.first(after) != nil
    }

    /// The first mention a sentence makes of a rule's item about the patient: negated and family mentions are skipped
    /// (but count as read).
    private static func accepted(_ rule: Rule, in c: String, _ h: inout Hits) -> NSTextCheckingResult? {
        allAccepted(rule, in: c, &h, first: true).first
    }

    /// Every mention accepted (1.9: each type of hepatitis, each kind of shock), or only the first.
    private static func allAccepted(_ rule: Rule, in c: String, _ h: inout Hits, first: Bool = false) -> [NSTextCheckingResult] {
        if let o = rule.onlyIf, o.first(c) == nil { return [] }
        if let n = rule.notIf, n.first(c) != nil { return [] }
        let ns = c as NSString
        var out: [NSTextCheckingResult] = []
        for m in rule.rx.all(c) {
            if negated(c, at: m.range.location) || (!rule.family && familyContext(c, at: m.range.location)) {
                h.seen(m.range)
                continue
            }
            if let na = rule.negAfter, let n = na.first(ns.substring(from: m.range.location + m.range.length)) {
                h.seen(NSRange(location: m.range.location, length: m.range.length + n.range.length))
                continue
            }
            // 1.9: a risk or a suspicion, words that make it someone's past or another thing, past or current.
            let before = ns.substring(to: m.range.location), after = ns.substring(from: m.range.location + m.range.length)
            if rule.guarded && (riskBefore.first(before) != nil || riskAfter.first(after) != nil) {
                h.seen(m.range)
                continue
            }
            // Told as past (or, for a past item, as now), former, or another thing: left for Other conditions unless
            // another rule reads it.
            if (rule.notBefore?.first(before) != nil) || (rule.notAfter?.first(after) != nil)
                || (rule.current && toldAsPast(c, m)) || (rule.pastOnly && !toldAsPast(c, m)) { continue }
            out.append(m)
            if first { break }
        }
        return out
    }

    /// The accepted mentions of a problem's rules in a clause (1.9).
    private static func acceptedMentions(_ id: String, in c: String) -> [NSTextCheckingResult] {
        var h = Hits()
        return problemRules.filter { $0.id == id }.flatMap { allAccepted($0, in: c, &h) }
    }

    /// Every pattern, for the test that each one compiles.
    static var allPatterns: [NoteRx] {
        var out: [NoteRx] = (problemRules + anesthesiaRules + symptomRules + acuteRules + signRules).map(\.rx)
        out += [rupturePastBefore, repairPastBefore, repairPastAfter, aortaSizeBefore, aortaSizeAfter, bareDissection, taaContext, ankleContext, bareTAA,
                intracranialAneurysm, rupturedAorticRx, notAorticDissection, complexEVARRx, complexEVARTail]
        out += [anticoagulationWords, gradeBeforeRx, pacerDependent, homeO2FlowRx, valveWrittenRx, valveShortRx, prosthesisTypedRx, prosthesisOpRx, prosthesisOpWrittenRx,
                prosthesisBare, prosthesisSizeAfter, yearAfter, plannedBefore, bentallRx, cardiacSurgeryRx, cardiacSurgeryYearRx, redoSternotomyRx, gradedMI]
        out += [infectionNotPositive, hivPrevention, covidNotRecent]
        out += detailPatterns
        out += problemRules.flatMap { r -> [NoteRx] in [r.notBefore, r.notAfter, r.notIf, r.onlyIf, r.negAfter].compactMap { $0 } }
        out += [stentCardiac, stentOther, noHistoryRx, esrdRx, drugRx, negCue, negEnd, famCue, famEnd, pastBefore, pastAfter, pastCare, planClause, surgicalPiece]
        out += PatientCodeStatus.patterns
        out += LabResults.patterns
        out += PastSurgeryNote.allPatterns + PatientLHC.patterns
        out += [ageRx, ageMonthsRx, ageWeeksRx, ageSexRx, maleRx, femaleRx, heightFtRx, heightCtxRx, heightMRx, heightCmRx, weightKgRx, weightLbRx, lossCue, bmiRx]
        out += [procedureHeaderRx, procedureRx, procedurePersonRx, procedureTechniqueRx, procedureLeadRx, procedureCut, emergencyRx, urgentRx, timeSensitiveRx, electiveRx, plannedRx, gaRx, neuraxialRx, macRx, regionalRx, asaRx]
        out += drugClasses.map { $0.0 } + [infusionRx, offCue]
        out += [devicePlannedBefore, devicePlannedAfter, ivRoute, supportCue]
        out += [deviceCue, tubeCue, deviceSettingCue, ecmoPart, countRx, tubeSkip, tubeGone, intubatedRx, intubatedPast, ventCue, vtRx,
                ventRateRx, peepRx, psRx, fio2Rx, roomAirRx, ncRx, hfncRx, nrbRx, venturiRx, faceMaskRx, nivRx, trachCollarRx, onLitersRx,
                flowRx, percentRx, homeRx, currentRx, breathingPast, satBefore]
        out += ventModes.map { $0.0 }
        out += [smokeNeverRx, smokeFormerRx, smokeCurrentRx, medsHeaderRx, aspirinDoseRx, allergyCue, nkdaRx, allergyRx, allergyAfterRx, allergySkipRx, allergyCut, noneRx]
        out += [bpRx, hrRx, spo2Rx, onOxygenRx, rrRx, tempRx, efRx, venousSatBefore, venousSatAfter, roomAirAfter, roomAirWords, labTrend, labTrendStop,
                labEarlier, labNow, notAge, hemolyzedRx, devicePresent, deviceListPlanned, planWord, labEnd, labEarlierAfter, labCurrentBefore,
                labPreop, labGoal, labCurrentAfter]
        out += labRules.map { $0.rx }
        out += [npoMidnightRx, lastAteRx, lastDrankRx, metsUnknownRx, metsPoorRx, metsGoodRx, metsNumberRx, frailRx, mallampatiRx, dentitionRx]
        out += [pieceBreak, headerLead, negLead]
        out += identifierRules.map { $0.1 }
        return out
    }

    // MARK: Reading

    /// The note in sentences: split at line breaks, and at a full stop or semicolon followed by a space, except at the
    /// end of an abbreviation such as "y.o." or "e.g.".
    static func clauses(_ text: String) -> [String] {
        let chars = Array(text.replacingOccurrences(of: "\r", with: "\n"))
        var out: [String] = []
        var cur = ""
        func flush() {
            let t = cur.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(t) }
            cur = ""
        }
        for (i, c) in chars.enumerated() {
            let next: Character = i + 1 < chars.count ? chars[i + 1] : "\n"
            let abbreviation = c == "." && i >= 2 && chars[i - 2] == "."
            // "C. diff" (C. difficile) is one name.
            let cDiff = c == "." && i >= 1 && (chars[i - 1] == "C" || chars[i - 1] == "c") && (i < 2 || !chars[i - 2].isLetter)
                && String(chars[(i + 1)...].prefix(5)).lowercased() == " diff"
            if c == "\n" || (c == ";" && next.isWhitespace) || (c == "." && next.isWhitespace && !abbreviation && !cDiff) {
                flush()
            } else {
                cur.append(c)
            }
        }
        flush()
        return out
    }

    /// What the note says, as findings to confirm. `now` places "midnight" and clock times; `abbreviations` holds the
    /// user's own [abbreviation: meaning] and `choices` the meanings chosen for ambiguous ones (by
    /// AmbiguousAbbreviation.id, MedAbbreviations.asWritten to leave one as written).
    /// `askRoomAir`: a saturation with no room air written is asked about (PatientNote.roomAir) and read only when room
    /// air is chosen; the quick-add bar, which asks it itself, passes false and gets it marked roomAirUnstated.
    static func read(_ text: String, now: Date = Date(), abbreviations user: [String: String] = [:], choices: [String: String] = [:],
                     askRoomAir: Bool = true) -> PatientNoteReading {
        var found: [String: PatientNoteFinding] = [:]
        var order: [String] = []
        var other: [String] = []
        var previous: [String] = []
        var names: [String] = []
        var ambiguous: [AmbiguousAbbreviation] = []
        var unknown: [UnknownAbbreviation] = []
        var labFlags: [String: (current: Bool, earlier: Bool)] = [:]
        var labConflicts: [String: [Double]] = [:]
        var surgeryState = PastSurgeryNote.State()
        func put(_ f: PatientNoteFinding, _ flag: (current: Bool, earlier: Bool)? = nil) {
            if let old = found[f.id] {
                // Two values of a test in different sentences: the one marked current, if exactly one is; otherwise
                // asked ("Preop Hb 12.1. Now Hb 8.2": 8.2; "Preop Hb 12.1. Hb 8.2": asked).
                if f.id.hasPrefix("lab:"), case .lab(_, let a) = old.change, case .lab(_, let b) = f.change, a != b {
                    let o = labFlags[f.id] ?? (current: false, earlier: false)
                    let n = flag ?? (current: false, earlier: false)
                    if n.current && !o.current {
                        found[f.id] = f
                        labFlags[f.id] = n
                        labConflicts[f.id] = nil
                    } else if !(o.current && !n.current) {
                        var values = labConflicts[f.id] ?? [a]
                        if !values.contains(b) { values.append(b) }
                        labConflicts[f.id] = values
                    }
                    return
                }
                // The airway, ventilator and oxygen can be told over several sentences: put together.
                if let merged = combined(old, f) { found[f.id] = merged }
                return
            }
            found[f.id] = f
            if let flag { labFlags[f.id] = flag }
            if !order.contains(f.id) { order.append(f.id) }
        }
        func has(_ id: String) -> Bool { found[id] != nil }

        // What looks like an identifier is blanked before reading: nothing is read from it, and it never reaches Other
        // conditions (the warning still names it).
        var blanked = text as NSString
        for r in QuickAdd.identifierRanges(text) where r.location + r.length <= blanked.length {
            blanked = blanked.replacingCharacters(in: r, with: String(repeating: " ", count: r.length)) as NSString
        }

        for written in clauses(blanked as String) {
            let abbreviations = MedAbbreviations.scan(written, user: user, choices: choices)
            for a in MedAbbreviations.ambiguous(abbreviations, in: written) where !ambiguous.contains(where: { $0.id == a.id }) { ambiguous.append(a) }
            for u in MedAbbreviations.unknown(in: written, besides: abbreviations, user: user) where !unknown.contains(where: { $0.token == u.token }) {
                unknown.append(u)
            }
            // Ambiguous abbreviations and the user's own are read as their meaning; the rest as written.
            let meant = MedAbbreviations.expand(written, abbreviations.compactMap { a -> AbbreviationReplacement? in
                guard a.isAmbiguous || a.source == .user, let meaning = a.meaning else { return nil }
                return AbbreviationReplacement(range: a.range, text: meaning.reading)
            })
            let c = meant.text
            var h = Hits()
            // The cath's result (1.8.3): in "non-obstructive CAD" the words "CAD" belong to it. They are blanked for the rules,
            // so that phrase does not file the CAD history item (and the ASA class that follows); a CAD told anywhere else in
            // the note still does, and nothing already in the record is ever taken out.
            let lhcResult = PatientLHC.readResult(c)
            var ruleText = c
            if let k = lhcResult?.cadWords { ruleText = (c as NSString).replacingCharacters(in: k, with: String(repeating: " ", count: k.length)) }
            readRules(ruleText, &h)
            // Read here, before the abbreviations are read through their meanings, so the "CAD" in it is already read.
            if let m = lhcResult {
                h.add(PatientNoteFinding(id: "lhc:result", section: Part.assessment, label: "Left heart cath: " + (m.result == "no-cad" ? "no CAD" : "non-obstructive"),
                                         change: .lhcResult(m.result)), at: m.cadWords.map { NSUnionRange(m.phrase, $0) } ?? m.phrase)
                h.seen(m.cath)
            }
            readPatient(c, &h)
            readProcedure(c, choices, &h)
            readInfusions(c, &h)
            readMeds(c, &h, names: &names)
            readAllergies(c, &h)
            readNumbers(c, &h, choices)
            for x in LabResults.read(c) {
                guard let first = x.ranges.first else { continue }
                h.add(x.finding, at: first)
                for r in x.ranges.dropFirst() { h.seen(r) }
            }
            readDissection(c, choices, &h)
            readTAA(c, choices, &h)
            readAssessment(c, now: now, &h)
            if planClause.first(c) == nil {
                readTubesAndDevices(written, abbreviations, meant, &h)
                readBreathing(c, &h)
            }
            // "mild MI", "trivial MI": mitral insufficiency, so not read through MI's meaning as an infarction (1.8.1).
            for m in gradedMI.all(c) { h.seen(m.range(at: 1)) }
            // The others, where no rule read them as written, are read through their meaning.
            var plain: [AbbreviationReplacement] = []
            var unread: [AbbreviationReplacement] = []
            for a in abbreviations where !a.isAmbiguous && a.source == .builtIn {
                guard let meaning = a.meaning else { continue }
                let r = meant.target(a.range)
                plain.append(AbbreviationReplacement(range: r, text: meaning.text))
                if a.reads && !neverRead.contains(a.key) && !h.ranges.contains(where: { NSIntersectionRange($0, r).length > 0 }) {
                    unread.append(AbbreviationReplacement(range: r, text: meaning.reading))
                }
            }
            if !unread.isEmpty { readMeanings(c, unread, &h, names: &names) }
            // A finding from an ambiguous abbreviation's usual meaning, which neither the context nor the user picked.
            for i in h.findings.indices where h.findings[i].note == nil {
                guard let a = abbreviations.first(where: { a in
                    a.isAmbiguous && !a.fromContext && a.meaning != nil && choices[a.choiceKey ?? ""] == nil
                        && NSIntersectionRange(meant.target(a.range), h.at[i]).length > 0
                }), let meaning = a.meaning else { continue }
                h.findings[i].note = "Read “" + a.token + "” as " + meaning.text + "; change it under Abbreviations if not."
            }
            // Past surgical history: a "PSH:" section, "s/p ...", "h/o ..." (1.8.3). What the cardiac reader took is its own.
            let taken = zip(h.findings, h.at).filter { $0.0.id == "cardiac-surgery" }.map { $0.1 }
            for op in PastSurgeryNote.read(c, state: &surgeryState, skip: taken).operations {
                let entry = PastSurgeryNote.surgery(op.text, op.date)
                h.add(PatientNoteFinding(id: "psh:" + op.text.lowercased() + "|" + op.date.text, section: Part.history,
                                         label: "Past surgical history: " + entry.text, change: .pastSurgery(op.text, op.date)), at: op.range)
                if !op.aside.isEmpty, !previous.contains(where: { $0.caseInsensitiveCompare(op.aside) == .orderedSame }) { previous.append(op.aside) }
            }
            for f in h.findings { put(f, h.labFlags[f.id]) }
            for q in h.questions where !ambiguous.contains(where: { $0.id == q.id }) { ambiguous.append(q) }
            // Leftovers keep what was written; their meanings sort them ("AVr 2020" is a past operation).
            let full = MedAbbreviations.expand(c, plain)
            let pastClause = pastCare.first(c) != nil || pastCare.first(full.text) != nil
            let pieces = planClause.first(c) != nil ? [] : leftovers(c, h.ranges, keepNegatives: pastClause)
            for (piece, range) in pieces {
                let expanded = (full.text as NSString).substring(with: full.target(range))
                if pastClause || surgicalPiece.first(piece) != nil || surgicalPiece.first(expanded) != nil {
                    if !previous.contains(where: { $0.caseInsensitiveCompare(piece) == .orderedSame }) { previous.append(piece) }
                } else if !other.contains(where: { $0.caseInsensitiveCompare(piece) == .orderedSame }) {
                    other.append(piece)
                }
            }
        }

        // Two values of a test, neither marked current: asked, and read only when one is chosen.
        for id in order {
            guard let values = labConflicts[id], case .lab(let key, _)? = found[id]?.change else { continue }
            let asked = labChoice(key, values, choices)
            if !ambiguous.contains(where: { $0.id == asked.question.id }) { ambiguous.append(asked.question) }
            if let v = asked.value, var f = found[id] {
                f.change = .lab(key, v)
                f.label = labLabel(key, v)
                found[id] = f
            } else {
                found[id] = nil
            }
        }
        // A saturation with no room air written: asked, and read only when room air is chosen.
        if askRoomAir, var f = found["vital:spo2"], f.note == roomAirUnstated, case .vital(_, let v) = f.change {
            let asked = roomAir(v, choices)
            if !ambiguous.contains(where: { $0.id == asked.question.id }) { ambiguous.insert(asked.question, at: 0) }
            if asked.answer == roomAirAnswer {
                f.note = nil
                found["vital:spo2"] = f
            } else {
                found["vital:spo2"] = nil
            }
        }
        // Insulin means diabetes treated with insulin; CPAP means sleep apnea.
        // Not a gestational diabetes's insulin (1.9: its own detail).
        let gestational = ["problem:gdm", "problem:gdm-diet", "problem:gdm-complex"].contains(where: has)
        if has("flag:insulin"), !has("problem:insulin"), !gestational, let l = problemLabels["insulin"] {
            put(PatientNoteFinding(id: "problem:insulin", section: Part.history, label: l, change: .problem("insulin"), note: "From the insulin in the medications."))
        }
        // CPAP or BiPAP running now (respiratory failure) is the oxygen support, not home therapy for sleep apnea.
        var acuteNIV = false
        if case .oxygen(let o)? = found["oxygen"]?.change, o.device == "niv" { acuteNIV = true }
        if acuteNIV, !has("problem:osa") {
            found["problem:cpap"] = nil
            order.removeAll { $0 == "problem:cpap" }
        }
        if has("problem:cpap"), !has("problem:osa"), !acuteNIV, let l = problemLabels["osa"] {
            put(PatientNoteFinding(id: "problem:osa", section: Part.history, label: l, change: .problem("osa"), note: "From the CPAP or BiPAP."))
        }
        // A ventilator means a tube; oxygen means the patient's own airway (a trach collar, a tracheostomy).
        if !has("airway") {
            if has("vent") {
                put(airwayFinding("ett", "", "", note: "From the ventilator settings; choose Tracheostomy in Airway if it is one."))
            } else if case .oxygen(let o)? = found["oxygen"]?.change {
                if o.device == "trachCollar" {
                    put(airwayFinding("trach", "", "", note: "From the trach collar."))
                } else {
                    put(airwayFinding("natural", "", "", note: o.device == "ra" ? "On room air." : "Breathing on their own with oxygen."))
                }
            }
        }
        // A bare "ruptured aneurysm" in a note about the head (a subarachnoid hemorrhage) is not aortic.
        if has("problem:ruptured-aneurysm"), intracranialAneurysm.first(text) != nil, rupturedAorticRx.first(text) == nil {
            found["problem:ruptured-aneurysm"] = nil
        }
        // The more specific item replaces the general one.
        for (general, specific) in supersededBy where has("problem:" + general) && specific.contains(where: { has("problem:" + $0) }) {
            found["problem:" + general] = nil
        }
        // ESRD: on dialysis (Hemodialysis replaces CKD), not on dialysis (1.9: CKD stage 5 with the ESRD-not-on-dialysis
        // item, which keeps the ASA IV that "aki" gave it until 1.9), or not said (CKD stage 5, with a caution). ESRD is
        // KDIGO's kidney failure, G5.
        if esrdRx.first(text) != nil {
            if has("problem:esrd-dialysis") {
                found["problem:ckd"] = nil
            } else if var ckd = found["problem:ckd"] {
                if case .problem = ckd.change {
                    ckd.change = .detail("ckd", "ckdStage", "5")
                    ckd.label += " (" + detailText("ckdStage", "5") + ")"
                }
                if !has("problem:esrd-no-dialysis") {
                    ckd.note = "The note says ESRD: in History, choose Hemodialysis or ESRD not on regularly scheduled dialysis as well."
                }
                found["problem:ckd"] = ckd
            }
        }
        // A dialysis access read apart from the hemodialysis (another sentence) goes with it.
        if has("problem:esrd-dialysis") {
            for id in order where id.hasPrefix("hx:fistula") || id.hasPrefix("hx:catheter") {
                guard var f = found[id], case .detail("", let k, let v) = f.change else { continue }
                f.change = .detail("esrd-dialysis", k, v)
                found[id] = f
            }
        }
        // A thrombophilia in a pregnant patient on anticoagulation is also the ASA's obstetric example (class III,
        // "a thrombophilic disease requiring anticoagulation"; Ben, Nov 3).
        if has("problem:thrombophilia-heme"), has("problem:pregnant"),
           has("problem:anticoagulation") || order.contains(where: { $0.hasPrefix("hx:anticoagulant") && has($0) }),
           !has("problem:thrombophilia"), let l = problemLabels["thrombophilia"] {
            put(PatientNoteFinding(id: "problem:thrombophilia", section: Part.history, label: l, change: .problem("thrombophilia"),
                                   note: "Pregnant, with a thrombophilia and on anticoagulation."))
        }
        if found.keys.contains(where: { $0.hasPrefix("problem:") }) { found["nohistory"] = nil }
        // NKDA beside a named allergy (often latex or a food): keep the allergy.
        if has("nkda"), let first = order.first(where: { $0.hasPrefix("allergies:") && has($0) }), var a = found[first] {
            found["nkda"] = nil
            a.note = "The note also says no known drug allergies; the allergy is kept."
            found[first] = a
        }
        if !has("meds"), !names.isEmpty {
            let list = names.joined(separator: ", ")
            put(PatientNoteFinding(id: "meds", section: Part.meds, label: "Medication list: " + list, change: .medications(list)))
        }

        var rank: [String: Int] = [:]
        for (i, s) in sections.enumerated() { rank[s] = i }
        let kept = order.compactMap { found[$0] }
        let findings = kept.indices.sorted { a, b in
            let ra = rank[kept[a].section] ?? 99
            let rb = rank[kept[b].section] ?? 99
            return ra != rb ? ra < rb : a < b
        }.map { kept[$0] }
        return PatientNoteReading(findings: findings, other: other.joined(separator: "; "), previous: previous.joined(separator: "; "),
                                  identifiers: identifiers(text), ambiguous: ambiguous, unknown: unknown)
    }

    /// Reads abbreviations no rule read as written through their meanings; what comes from a meaning is placed back on
    /// the abbreviation.
    private static func readMeanings(_ c: String, _ items: [AbbreviationReplacement], _ h: inout Hits, names: inout [String]) {
        let y = MedAbbreviations.expand(c, items)
        var h2 = Hits()
        readRules(y.text, &h2)
        readInfusions(y.text, &h2)
        readMeds(y.text, &h2, names: &names, header: false)
        readAllergies(y.text, &h2)
        for (f, r) in zip(h2.findings, h2.at) where y.touches(r) && !h.findings.contains(where: { $0.id == f.id }) {
            h.add(f, at: y.source(r))
        }
        for r in h2.ranges where y.touches(r) { h.seen(y.source(r)) }
        h.infusions += h2.infusions.map { y.source($0) }
    }

    // MARK: The aorta

    private static let rupturedIDs: Set<String> = ["aaa-ruptured", "taa-ruptured", "taaa-ruptured", "ruptured-aneurysm"]
    private static let repairIDs: Set<String> = ["aortic-repair-open", "evar", "tevar"]
    /// MI after a valve grade is mitral insufficiency.
    static let gradedMI = NoteRx(#"\b(?:mild|trace|trivial|moderate|severe)\s+((?-i:MI))\b"#)
    /// A rupture told as past: repaired, or after a history cue.
    static let rupturePastBefore = NoteRx(#"\b(?:s/p|status post|history of|hx of|h/o|prior|previous|previously|old|remote|repaired|repair of)\b[^.;]{0,24}$"#)
    /// A repair told as done: after a history cue or "had", or with a year or "ago" after it.
    static let repairPastBefore = NoteRx(#"\b(?:s/p|status post|history of|hx of|h/o|prior|previous|previously|old|remote|had|has had|underwent|treated with|repaired with|after|post)\b[^.;]{0,24}$"#)
    static let repairPastAfter = NoteRx(#"^[^.;]{0,24}?(?:\(?\b(?:19|20)\d\d\b|\bago\b|\bin (?:19|20)\d\d\b)"#)
    /// The diameter written before an aneurysm ("5.2 cm AAA", "5.2-cm infrarenal AAA") or after it ("AAA 52 mm",
    /// "TAA measuring 4.8 cm", "AAA 4.5 x 4.3 cm": the largest). A number with no unit (a year, "AAA 2019") is not a
    /// size. 2.5 to 15 cm (2022 ACC/AHA: an AAA is over 3.0 cm).
    static let aortaSizeBefore = NoteRx(#"(\d{1,2}(?:\.\d{1,2})?)\s*-?\s*(cm|mm)\s+(?:(?:infrarenal|juxtarenal|pararenal|suprarenal|fusiform|saccular|ascending|descending|thoracic|abdominal|aortic|root|arch)\s+){0,3}$"#)
    static let aortaSizeAfter = NoteRx(#"^\s*[,(:\-–]?\s*(?:(?:measuring|measures|measured|of|is|at|now|size|sized|diameter|max|maximal|maximum|approx|approximately|about|~)\s*:?\s*){0,3}(\d{1,3}(?:\.\d{1,2})?)(?:\s*[x×]\s*(\d{1,3}(?:\.\d{1,2})?))?\s*(cm|mm)\b"#)
    /// A bare "dissection" with no type, which is asked about: "aortic dissection", "AoD", or "dissection" opening a
    /// phrase of the history ("HTN, dissection, CKD"); not a surgical one ("lymph node dissection", "neck dissection").
    /// "TAAD" is asked too: usually type A aortic dissection, but also thoracic aortic aneurysm and dissection ("ATAAD"
    /// is read as type A). A bare "AD" (Alzheimer disease) is never read.
    static let bareDissection = NoteRx(#"\baortic dissection\b|\bdissection of the aorta\b|\bdissecting (?:aortic )?aneurysm\b|(?-i:\b(?:TAAD|AoD)\b)|(?:^|[,;:(+]\s*|\b(?:and|with|known|chronic|acute|prior|previous|old|remote|s/p|h/o|hx|history of|hx of)\s+)(?:acute |chronic )?dissection\b(?!\s+of\b)"#)
    static let dissectionQuestion = "quick:aorta:dissection"
    /// A sentence about another dissection: coronary (PCI, SCAD), carotid or vertebral; not asked about [P].
    static let notAorticDissection = NoteRx(#"\bcoronary\b|(?-i:\b(?:PCI|SCAD)\b)|\bcarotid\b|\bvertebral\b"#)
    static let taaQuestion = "quick:aorta:taa"
    /// Words that place an aneurysm in the head: a bare "ruptured aneurysm" in such a note is not aortic. Not a bare
    /// "clip" (left atrial appendage clip).
    static let intracranialAneurysm = NoteRx(#"(?-i:\bSAH\b)|subarachnoid|intracranial|cerebral|\bberry\b|\bcoil(?:ed|ing)\b|\bclipp(?:ed|ing)\b|hunt[- ]?hess|fisher grade|\baneurysmal\b|(?-i:\b(?:ACOM|PCOM|AComm|PComm|ACoA|PCoA|MCA)\b)|\bbasilar\b|(?-i:\bEVD\b)|ventriculostomy"#)
    static let rupturedAorticRx = NoteRx(#"ruptured aortic aneurysm"#)
    /// Aortic words or a size in the sentence: a bare "TAA" is the aneurysm.
    static let taaContext = NoteRx(#"\b(?:thoracic|aortic|aorta|ascending|aneurysm)\b|\d\s*(?:cm|mm)\b"#)
    static let ankleContext = NoteRx(#"\bankle\b|\barthroplast(?:y|ies)\b|\bortho(?:p(?:a)?edic)?s?\b|\bpodiatr"#)
    static let bareTAA = NoteRx(#"\bTAA\b"#)

    /// A bare "TAA" with both aortic and ankle words in its sentence, or neither: asked whether it is the aneurysm or an
    /// ankle arthroplasty.
    private static func readTAA(_ c: String, _ choices: [String: String], _ h: inout Hits) {
        let ankle = ankleContext.first(c) != nil, aortic = taaContext.first(c) != nil
        guard !h.findings.contains(where: { ["problem:taa", "problem:taa-ruptured", "problem:taaa"].contains($0.id) }),
              ankle == aortic,
              let m = bareTAA.all(c).first(where: { !negated(c, at: $0.range.location) && !familyContext(c, at: $0.range.location) }) else { return }
        let asked = question(taaQuestion, "TAA", value: "", options: [AbbreviationMeaning("thoracic aortic aneurysm", id: "taa"),
                                                                       AbbreviationMeaning("total ankle arthroplasty", id: "ankle")], usual: "", choices)
        h.questions.append(asked.question)
        if asked.answer == "taa", let label = problemLabels["taa"] {
            if let size = aortaSize(c, m) {
                h.add(PatientNoteFinding(id: "problem:taa", section: Part.history, label: label + ", " + NumText.short(size.cm) + " cm", change: .aneurysm("thoracic", size.cm, false)), at: size.range)
            } else {
                h.add(PatientNoteFinding(id: "problem:taa", section: Part.history, label: label, change: .aneurysm("thoracic", nil, false)), at: m.range)
            }
        } else {
            h.seen(m.range)
        }
    }

    /// FEVAR, BEVAR, F/BEVAR and fenestrated or branched repairs file as Prior EVAR (Ben's decision) [P]; the term as
    /// typed, with the words of the repair and a year after it ("FEVAR 2021", "fenestrated endovascular repair"), goes to
    /// the cardiovascular details.
    static let complexEVARRx = NoteRx(#"(?-i:\b(?:F/?B?|B)EVAR\b)|\b(?:fenestrated|branched)\b"#)
    static let complexEVARTail = NoteRx(#"^((?:\s+(?:endovascular|aortic|aneurysm|repair|(?-i:EVAR|AAA)))*)(?:,?\s*\(?(?:in\s+)?((?:19|20)\d\d)\)?)?"#)

    private static func complexEVAR(_ c: String, _ m: NSTextCheckingResult) -> String? {
        let ns = c as NSString
        let hit = ns.substring(with: m.range)
        guard complexEVARRx.first(hit) != nil else { return nil }
        let after = ns.substring(from: m.range.location + m.range.length)
        guard let t = complexEVARTail.first(after) else { return hit }
        return hit + (t.text(1, in: after) ?? "") + (t.text(2, in: after).map { " " + $0 } ?? "")
    }

    private static func rupturePast(_ c: String, _ m: NSTextCheckingResult) -> Bool {
        let ns = c as NSString
        return rupturePastBefore.first(ns.substring(to: m.range.location)) != nil || pastAfter.first(ns.substring(from: m.range.location + m.range.length)) != nil
    }

    private static func repairPast(_ c: String, _ m: NSTextCheckingResult) -> Bool {
        let ns = c as NSString
        return repairPastBefore.first(ns.substring(to: m.range.location)) != nil || repairPastAfter.first(ns.substring(from: m.range.location + m.range.length)) != nil
    }

    /// The diameter written beside an aneurysm, in cm (mm read as tenths), from 2.5 to 15 cm; with the range that covers
    /// the aneurysm and its size.
    static func aortaSize(_ c: String, _ m: NSTextCheckingResult) -> (cm: Double, range: NSRange)? {
        let ns = c as NSString
        let end = m.range.location + m.range.length
        func cm(_ v: String?, _ unit: String?) -> Double? {
            guard let v, let n = Double(v), let unit else { return nil }
            let x = unit.lowercased() == "mm" ? n / 10 : n
            return x >= 2.5 && x <= 15 ? (x * 100).rounded() / 100 : nil
        }
        let after = ns.substring(from: end)
        // "4.5 x 4.3 cm": the largest.
        let largest = { (a: NSTextCheckingResult) -> String? in
            let xs = [a.text(1, in: after), a.text(2, in: after)].compactMap { $0 }.compactMap(Double.init)
            return xs.max().map { String($0) }
        }
        if let a = aortaSizeAfter.first(after), let x = cm(largest(a), a.text(3, in: after)) {
            return (x, NSRange(location: m.range.location, length: end - m.range.location + a.range.length))
        }
        let before = ns.substring(to: m.range.location)
        if let b = aortaSizeBefore.first(before), let x = cm(b.text(1, in: before), b.text(2, in: before)) {
            return (x, NSRange(location: b.range.location, length: end - b.range.location))
        }
        return nil
    }

    /// A dissection with no type ("dissection", "aortic dissection"): asked type A or type B, and read once answered.
    private static func readDissection(_ c: String, _ choices: [String: String], _ h: inout Hits) {
        guard !h.findings.contains(where: { $0.id == "problem:dissection-a" || $0.id == "problem:dissection-b" }) else { return }
        guard notAorticDissection.first(c) == nil,
              let m = bareDissection.all(c).first(where: { !negated(c, at: $0.range.location) && !familyContext(c, at: $0.range.location) }) else { return }
        let asked = question(dissectionQuestion, "Dissection", value: "", options: [AbbreviationMeaning("type A", id: "dissection-a"), AbbreviationMeaning("type B", id: "dissection-b")],
                             usual: "", choices)
        h.questions.append(asked.question)
        if let a = asked.answer, let label = problemLabels[a] {
            h.add(PatientNoteFinding(id: "problem:" + a, section: Part.history, label: label, change: .problem(a)), at: m.range)
        } else {
            h.seen(m.range)
        }
    }

    // MARK: Aneurysm location, grades, valves, cardiac surgery (1.8.1)

    /// Where a thoracic aneurysm is, from the words that named it: root or ascending, arch, descending; "thoracic" when
    /// they do not say.
    static func aneurysmSite(_ id: String, _ words: String) -> String {
        if id.hasPrefix("aaa") { return "abdominal" }
        if id.hasPrefix("taaa") { return "thoracoabdominal" }
        let w = words.lowercased()
        if w.contains("ascending") || w.contains("root") { return "root" }
        if w.contains("arch") { return "arch" }
        if w.contains("descending") { return "descending" }
        return "thoracic"
    }

    /// A grade written just before a finding ("moderate pulmonary hypertension", "mild to moderate"): the highest named.
    static let gradeBeforeRx = NoteRx(#"\b(trace|trivial|mild|moderate|severe|critical)(?:\s*(?:-|–|to|/)\s*(mild|moderate|severe|critical))?\s*$"#)

    private static func gradeBefore(_ c: String, _ m: NSTextCheckingResult) -> String? {
        let before = (c as NSString).substring(to: m.range.location)
        guard let g = gradeBeforeRx.first(before) else { return nil }
        return grade([g.text(1, in: before), g.text(2, in: before)].compactMap { $0 })
    }

    /// The highest of the grades written, as the page grades: "critical" is severe; trace and trivial are not a grade
    /// of disease (nil, and the lesion is not read).
    static func grade(_ words: [String]) -> String? {
        let order = ["mild", "moderate", "severe"]
        let read = words.map { $0.lowercased() == "critical" ? "severe" : $0.lowercased() }.filter(order.contains)
        return read.max { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
    }

    /// Pacer dependence (1.9: PatientHistoryDetails.pacerDependent): "pacer dependent", "PPM-dependent", "dependent on
    /// his pacemaker"; not "non-pacer-dependent".
    static let pacerDependent = NoteRx(#"(?<!non-)(?<!non)(?<!non )\b(?:pacer|pacemaker|(?-i:PPM|CIED)|device)[- ]dependen(?:t|ce|cy)\b|\bdependent on (?:(?:the|a|his|her|their) )?(?:pacer|pacemaker|(?-i:PPM))\b"#)
    static let homeO2FlowRx = NoteRx(#"(\d{1,2}(?:\.\d)?)\s?(?:l|lpm|l/min|liters?)\b(?:\s*(?:nc|per minute|/min))?"#)

    /// The flow written within a few words of "home oxygen".
    private static func homeO2Flow(_ c: String, near r: NSRange) -> (value: Double, range: NSRange)? {
        let ns = c as NSString
        let lo = max(0, r.location - 16), hi = min(ns.length, r.location + r.length + 16)
        let window = NSRange(location: lo, length: hi - lo)
        guard let m = homeO2FlowRx.re?.firstMatch(in: c, range: window), let v = number(m, [1], c), v > 0, v <= 15 else { return nil }
        return (v, m.range)
    }

    /// A lesion written out ("severe aortic stenosis", "moderate to severe mitral regurgitation", "aortic valve
    /// stenosis") or abbreviated with a grade ("severe AS", "moderate MR", "mild TR"). Trace and trivial lesions are not
    /// valve disease (the echo's Trivial grade) and are not read. A severe pulmonic lesion has no valve of its own on the
    /// page: it files severe valve disease, valve not recorded (its ASA IV kept).
    static let valveWrittenRx = NoteRx(#"(?:\b(trace|trivial|mild|moderate|severe|critical)(?:\s*(?:-|–|to|/)\s*(mild|moderate|severe|critical))?\s+)?\b(aortic|mitral|tricuspid|pulmonic|pulmonary)\s+(?:valve\s+)?(stenosis|regurgitation|insufficiency)\b"#)
    static let valveShortRx = NoteRx(#"\b(trace|trivial|mild|moderate|severe|critical)(?:\s*(?:-|–|to|/)\s*(mild|moderate|severe|critical))?\s+((?-i:AS|AR|AI|MS|MR|TS|TR|TI|PS|PR|PI))\b"#)
    /// A prosthetic valve in place: a type and "valve" ("mechanical mitral valve", "bioprosthetic valve"), a type and
    /// the operation ("mechanical AVR", "tissue MVR"), or the operation told as past ("s/p TAVR", "AVR 2019"), with the
    /// size after it ("23 mm"). Not a planned one ("for TAVR", "scheduled for a bioprosthetic Bentall").
    static let prosthesisTypedRx = NoteRx(#"\b(mechanical|bioprosthetic|bio-?prosthetic|tissue|porcine|bovine|prosthetic)\s+(?:(aortic|mitral|tricuspid)\s+)?(?:heart\s+)?valve\b(?:\s+replacement)?"#)
    static let prosthesisOpRx = NoteRx(#"(?:\b(mechanical|bioprosthetic|bio-?prosthetic|tissue|porcine|bovine)\s+)?(?-i:\b(SAVR|AVR|TAVR|TAVI|MVR|TMVR|TVR|TTVR)\b)"#)
    static let prosthesisOpWrittenRx = NoteRx(#"\b(aortic|mitral|tricuspid)?\s*valve replacement\b"#)
    static let prosthesisBare = NoteRx(#"\bbio-?prosthetic\b(?!\s+(?:aortic|mitral|tricuspid|heart)?\s*valve)"#)
    static let prosthesisSizeAfter = NoteRx(#"^\s*(?:\(|,)?\s*(?:size\s+)?(\d{2})\s*-?\s*mm\b"#)
    static let yearAfter = NoteRx(#"^\s*(?:\(|,)?\s*(?:in\s+)?((?:19|20)\d\d)\b"#)
    static let plannedBefore = NoteRx(#"(?:\b(?:scheduled|planned|plan|planning|undergo|undergoing|presenting|presents|candidate|evaluation|eval|referred|consult|consulted|booked|listed|needs|will have)\b[^.;]{0,30}|\bfor\s+(?:an?\s+|the\s+|elective\s+|urgent\s+|emergent\s+|redo\s+)*)$"#)
    /// "On warfarin for a mechanical AVR": the valve is in place, not planned.
    static let anticoagulationWords = NoteRx(#"\b(?:warfarin|coumadin|anticoagulat\w*|inr|heparin|eliquis|apixaban|lovenox|enoxaparin|bridg\w*)\b"#)
    static let bentallRx = NoteRx(#"\b(?:bio-?)?bentall\b"#)

    private static func readValves(_ c: String, _ h: inout Hits) {
        let ns = c as NSString
        func free(_ r: NSRange) -> Bool { !negated(c, at: r.location) && !familyContext(c, at: r.location) }
        func add(_ valve: String, _ lesion: String, _ words: [String], _ r: NSRange) {
            let g = grade(words)
            if !words.isEmpty, g == nil { h.seen(r); return }
            if valve == "pulmonic" {
                guard g == "severe" else { h.seen(r); return }
                h.add(PatientNoteFinding(id: "problem:valve-severe", section: Part.history, label: "Severe valve disease (pulmonic), valve not recorded",
                                         change: .problem("valve-severe")), at: r)
                return
            }
            let id = valve == "aortic" && lesion == "stenosis" ? "problem:as" : (valve == "mitral" && lesion == "regurgitation" ? "problem:mr" : "valve:" + valve + ":" + lesion)
            guard !h.findings.contains(where: { $0.id == id }) else { h.seen(r); return }
            let name = valve.prefix(1).uppercased() + valve.dropFirst() + " " + lesion
            h.add(PatientNoteFinding(id: id, section: Part.history, label: name + (g.map { ", " + $0 } ?? ""), change: .valve(valve, lesion, g)), at: r)
        }
        for m in valveWrittenRx.all(c) where free(m.range) {
            let valve = (m.text(3, in: c) ?? "").lowercased().replacingOccurrences(of: "pulmonary", with: "pulmonic")
            let lesion = (m.text(4, in: c) ?? "").lowercased() == "stenosis" ? "stenosis" : "regurgitation"
            add(valve, lesion, [m.text(1, in: c), m.text(2, in: c)].compactMap { $0 }, m.range)
        }
        let valves: [Character: String] = ["A": "aortic", "M": "mitral", "T": "tricuspid", "P": "pulmonic"]
        for m in valveShortRx.all(c) where free(m.range) {
            guard let ab = m.text(3, in: c), let v = valves[ab.first ?? " "] else { continue }
            add(v, ab.hasSuffix("S") ? "stenosis" : "regurgitation", [m.text(1, in: c), m.text(2, in: c)].compactMap { $0 }, m.range)
        }
        // Prosthetic valves.
        let bentallPlanned: Bool = {
            guard let b = bentallRx.first(c) else { return false }
            let before = ns.substring(to: b.range.location)
            return plannedBefore.first(before) != nil && pastBefore.first(before) == nil && pastCare.first(c) == nil
        }()
        let anticoagulated = anticoagulationWords.first(c) != nil
        func past(_ r: NSRange) -> Bool {
            pastBefore.first(ns.substring(to: r.location)) != nil || yearAfter.first(ns.substring(from: r.location + r.length)) != nil
                || pastCare.first(c) != nil
        }
        func planned(_ r: NSRange) -> Bool { !past(r) && !anticoagulated && (plannedBefore.first(ns.substring(to: r.location)) != nil || bentallPlanned) }
        func addProsthesis(_ valve: String, _ words: [String], _ r: NSRange) {
            let after = ns.substring(from: r.location + r.length)
            var parts = words.filter { !$0.isEmpty }
            var range = r
            // The size goes with the prosthesis; a year is the operation's (Previous cardiac surgery).
            if let s = prosthesisSizeAfter.first(after), let mm = s.text(1, in: after) {
                parts.append(mm + " mm")
                range.length += s.range.length
            }
            let text = parts.joined(separator: " ")
            let id = "problem:prosthetic-valve" + (valve.isEmpty ? "" : "-" + valve)
            guard !h.findings.contains(where: { $0.id == id }) else { h.seen(range); return }
            let label = (valve.isEmpty ? "Prosthetic valve" : valve.prefix(1).uppercased() + valve.dropFirst() + " prosthetic valve") + (text.isEmpty ? "" : " (" + text + ")")
            h.add(PatientNoteFinding(id: id, section: Part.history, label: label, change: .prosthesis(valve, text)), at: range)
        }
        func typeWord(_ t: String?) -> String {
            guard let t = t?.lowercased() else { return "" }
            if t == "prosthetic" { return "" }
            return t.hasPrefix("bio") ? "bioprosthetic" : t
        }
        for m in prosthesisTypedRx.all(c) where free(m.range) && !planned(m.range) {
            addProsthesis((m.text(2, in: c) ?? "").lowercased(), [typeWord(m.text(1, in: c))], m.range)
        }
        for m in prosthesisOpRx.all(c) where free(m.range) && !planned(m.range) {
            guard let op = m.text(2, in: c) else { continue }
            let type = typeWord(m.text(1, in: c))
            guard !type.isEmpty || past(m.range) else { continue }
            let valve = op.contains("A") ? "aortic" : (op.contains("M") ? "mitral" : "tricuspid")
            let transcatheter = ["TAVR", "TAVI", "TMVR", "TTVR"].contains(op) ? op : ""
            addProsthesis(valve, [type, transcatheter], m.range)
        }
        for m in prosthesisOpWrittenRx.all(c) where free(m.range) && past(m.range) && !planned(m.range) {
            addProsthesis((m.text(1, in: c) ?? "").lowercased(), [], m.range)
        }
        for m in prosthesisBare.all(c) where free(m.range) && !planned(m.range) {
            addProsthesis("", ["bioprosthetic"], m.range)
        }
    }

    /// Previous cardiac surgery, told as past: an operation on the heart ("s/p AVR 2015", "prior CABG", "h/o Bentall"),
    /// "prior cardiac surgery", or a redo sternotomy (which means there was one). Transcatheter procedures are not.
    static let cardiacOpWords = #"(?:(?:mechanical|bioprosthetic|tissue)\s+)?(?:(?-i:SAVR|AVR|MVR|TVR|CABG|OPCAB|AVr|MVr|TVr)|aortic valve (?:replacement|repair)|mitral valve (?:replacement|repair)|tricuspid valve (?:replacement|repair)|valve (?:replacement|repair|surgery)|coronary (?:artery )?bypass(?: graft(?:ing)?)?|(?:bio-?)?bentall|ross procedure|maze procedure|myectomy|(?-i:ASD|VSD) (?:repair|closure)|heart transplant(?:ation)?|(?-i:OHT)|cardiac surgery|heart surgery|open[- ]heart surgery|sternotomy)(?:\s*(?:x|×)\s*\d)?"#
    static let cardiacSurgeryRx = NoteRx(#"\b(?:s/p|status post|prior|previous|history of|hx of|h/o|old|remote)\s+(?:an?\s+)?("# + cardiacOpWords + #")(?:\s*(?:\(|,)?\s*(?:in\s+)?((?:19|20)\d\d)\)?)?"#)
    static let cardiacSurgeryYearRx = NoteRx(#"(?-i:\b((?:SAVR|AVR|MVR|CABG|Bentall)\b(?:\s*(?:x|×)\s*\d)?))\s*(?:\(|,)?\s*(?:in\s+)?((?:19|20)\d\d)\b"#)
    static let redoSternotomyRx = NoteRx(#"\bredo\s+(?:median\s+)?sternotomy\b|\bre-?(?:do\s+)?sternotomy\b"#)

    private static func readCardiacSurgery(_ c: String, _ h: inout Hits) {
        var parts: [String] = []
        var at: NSRange?
        var read: [NSRange] = []
        func note(_ t: String, _ r: NSRange) {
            read.append(r)
            let t = t.trimmingCharacters(in: .whitespaces)
            if !parts.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { parts.append(t) }
            at = at.map { NSUnionRange($0, r) } ?? r
        }
        for m in cardiacSurgeryRx.all(c) where !negated(c, at: m.range.location) && !familyContext(c, at: m.range.location) {
            guard var op = m.text(1, in: c) else { continue }
            if ["cardiac surgery", "heart surgery", "open heart surgery", "open-heart surgery"].contains(op.lowercased()) { op = "Cardiac surgery" }
            if op.lowercased() == "sternotomy" { op = "Sternotomy" }
            note(op + (m.text(2, in: c).map { " " + $0 } ?? ""), m.range)
        }
        for m in cardiacSurgeryYearRx.all(c) where !negated(c, at: m.range.location) && !familyContext(c, at: m.range.location) {
            guard let op = m.text(1, in: c), let y = m.text(2, in: c) else { continue }
            if read.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
            note(op + " " + y, m.range)
        }
        if let m = redoSternotomyRx.first(c), !negated(c, at: m.range.location), !parts.contains(where: { $0.lowercased().contains("sternotomy") }) {
            note("Sternotomy", m.range)
        }
        guard let r = at, !parts.isEmpty else { return }
        let text = parts.joined(separator: "; ")
        h.add(PatientNoteFinding(id: "cardiac-surgery", section: Part.history, label: "Past surgical history: " + text, change: .cardiacSurgery(text)), at: r)
    }

    /// Abbreviations never read through their meaning: "IE" (infective endocarditis) is also "i.e.".
    static let neverRead: Set<String> = ["IE"]

    /// A stroke's year that is this year or later (it may be within 3 months).
    private static func strokeYearNotPast(_ c: String, _ m: NSTextCheckingResult) -> Bool {
        let t = (c as NSString).substring(with: m.range)
        guard let r = NoteRx(#"(?:19|20)\d\d"#).first(t), let y = Int((t as NSString).substring(with: r.range)) else { return false }
        return y >= Calendar(identifier: .gregorian).component(.year, from: Date())
    }

    /// A problem's own note-reader pattern (LabResults.otherLink asks whether "VRE" reads as MRSA or VRE).
    static func problemRule(_ id: String) -> NoteRx? { problemRules.first { $0.id == id }?.rx }

    /// The history rule for a problem files it from this clause, with all its conditions (negation, notIf, a result that
    /// is not positive): a positive COVID-19 result is read only where Recent COVID-19 would be filed.
    static func problemRuleAccepts(_ id: String, _ c: String) -> Bool {
        guard let rule = problemRules.first(where: { $0.id == id }) else { return false }
        var h = Hits()
        return accepted(rule, in: c, &h) != nil
    }

    private static let problemLabels: [String: String] = Dictionary(PatientCatalog.allProblems.map { ($0.id, $0.label) }, uniquingKeysWith: { a, _ in a })

    private static func readRules(_ c: String, _ h: inout Hits) {
        for rule in problemRules {
            guard let m = accepted(rule, in: c, &h), let label = problemLabels[rule.id] else { continue }
            if rupturedIDs.contains(rule.id), rupturePast(c, m) {
                h.seen(m.range)
                continue
            }
            if repairIDs.contains(rule.id), !repairPast(c, m) { continue }
            // "Stroke 2026": a year that may be within 3 months is read as unspecified ("MI 2026" as an MI with its caution).
            if rule.id == "cva" || rule.id == "mi", rule.quiet, strokeYearNotPast(c, m) { continue }
            if rule.id == "evar", let term = complexEVAR(c, m) {
                h.add(PatientNoteFinding(id: "problem:evar", section: Part.history, label: label, change: .problemNote("evar", term),
                                         note: "Adds “" + term + "” to the repair details."), at: m.range)
                continue
            }
            // An aneurysm goes to its location, with its size when written beside it.
            if PatientHistoryDetails.aneurysmProblems.contains(rule.id) {
                let ruptured = rule.id.hasSuffix("-ruptured")
                let site = aneurysmSite(rule.id, (c as NSString).substring(with: m.range))
                let size = aortaSize(c, m)
                let place = site == "thoracic" || site == "abdominal" || site == "thoracoabdominal" ? "" : " (" + PatientHistoryDetails.siteLabel(site).lowercased() + ")"
                h.add(PatientNoteFinding(id: "problem:" + rule.id, section: Part.history, label: label + place + (size.map { ", " + NumText.short($0.cm) + " cm" } ?? ""),
                                         change: .aneurysm(site, size?.cm, ruptured)), at: size?.range ?? m.range)
                continue
            }
            // Mild or moderate pulmonary hypertension keeps its grade.
            if rule.id == "pulm-htn", let g = gradeBefore(c, m), g != "severe" {
                h.add(PatientNoteFinding(id: "problem:pulm-htn", section: Part.history, label: label + ", " + g, change: .pulmHtn(g)), at: m.range)
                continue
            }
            // Another arrhythmia: its name goes to the type ("SVT", "heart block").
            if rule.id == "arrhythmia" {
                let t = (c as NSString).substring(with: m.range)
                h.add(PatientNoteFinding(id: "problem:arrhythmia", section: Part.history, label: label + " (" + t + ")", change: .problemNote("arrhythmia", t)), at: m.range)
                continue
            }
            // 1.9: words that go to the problem's own detail field (a fracture's place, the esophageal disorder's type,
            // the source of a sepsis). A pacemaker-dependent patient is read with the details (readDetails19).
            if let t = detailWords(rule.id, c, m) {
                h.add(PatientNoteFinding(id: "problem:" + rule.id, section: Part.history, label: label + " (" + t.text + ")", change: .problemNote(rule.id, t.text)),
                      at: NSUnionRange(m.range, t.range))
                continue
            }
            // Home oxygen with a flow ("2 L at home", "home O2 3 L").
            if rule.id == "home-o2", let flow = homeO2Flow(c, near: m.range) {
                h.add(PatientNoteFinding(id: "problem:home-o2", section: Part.history, label: label + " " + NumText.short(flow.value) + " L/min", change: .homeO2(flow.value)),
                      at: NSUnionRange(m.range, flow.range))
                continue
            }
            h.add(PatientNoteFinding(id: "problem:" + rule.id, section: Part.history, label: label, change: .problem(rule.id), note: rule.quiet ? nil : cautions[rule.id]), at: m.range)
        }
        readDetails19(c, &h)
        readValves(c, &h)
        readCardiacSurgery(c, &h)
        if let m = efRx.first(c), let a = number(m, [1], c) {
            h.seen(m.range)
            let ef = number(m, [2], c).map { ($0 + a) / 2 } ?? a
            let id = ef < 30 ? "ef-severe" : (ef <= 40 ? "ef-moderate" : "")
            if !id.isEmpty, let label = problemLabels[id] {
                h.add(PatientNoteFinding(id: "problem:" + id, section: Part.history, label: label + " (EF " + NumText.short(ef) + "%)", change: .problem(id)), at: m.range)
            }
        }
        if let m = noHistoryRx.first(c) {
            h.add(PatientNoteFinding(id: "nohistory", section: Part.history, label: "No significant medical history", change: .noHistory), at: m.range)
        }
        for rule in anesthesiaRules {
            guard let m = accepted(rule, in: c, &h), let f = PatientCatalog.anesthesiaHistory.first(where: { $0.id == rule.id }) else { continue }
            h.add(PatientNoteFinding(id: "anesthesia:" + rule.id, section: Part.anesthesia, label: f.label, change: .anesthesiaHistory(rule.id)), at: m.range)
        }
        for rule in symptomRules {
            guard let m = accepted(rule, in: c, &h), let f = PatientFunctional.cardiacSymptomFlags.first(where: { $0.id == rule.id }) else { continue }
            h.add(PatientNoteFinding(id: "symptom:" + rule.id, section: Part.assessment, label: "Cardiac symptom: " + f.label.lowercased(), change: .symptom(rule.id)), at: m.range)
        }
        for rule in acuteRules {
            guard let m = accepted(rule, in: c, &h), let f = PatientFunctional.activeCardiac.first(where: { $0.id == rule.id }) else { continue }
            if past(c, m) {
                h.seen(m.range)
                continue
            }
            h.add(PatientNoteFinding(id: "acute:" + rule.id, section: Part.assessment, label: "Acute cardiac condition: " + f.label.lowercased(), change: .acute(rule.id)), at: m.range)
        }
        for rule in signRules {
            guard let m = accepted(rule, in: c, &h), let f = PatientAirway.signs.first(where: { $0.id == rule.id }) else { continue }
            h.add(PatientNoteFinding(id: "sign:" + rule.id, section: Part.airway, label: f.label, change: .airwaySign(rule.id)), at: m.range)
        }
    }

    // MARK: History details (1.9)
    //
    // What the 1.9 History pages hold beside a problem (PatientHistoryDetails), read where the note says it: the CKD
    // stage, the dialysis days and access, the AF type, pacer dependence, the hepatitis types, latent or active TB,
    // COVID-19 active or recent, pack-years and the quit year, G/P and weeks of gestation, the kinds of shock, a GI bleed
    // active or resolved and upper or lower, the anticoagulants, a peripartum cardiomyopathy's LVEF, a gestational
    // diabetes's insulin and control, the side and fluid of a pleural effusion or pneumothorax and a chest tube, and a
    // previous esophageal procedure. Each is read only where its own words are not negated or a relative's; a detail
    // goes on its problem's finding (one chip) when that finding has nothing else, else it is a finding of its own.

    /// The CKD stage, KDIGO's GFR categories (G1–G5, 3a and 3b): "CKD 3b", "CKD stage IV", "CKD G4", "stage 4 CKD",
    /// "CKD5D". A bare stage 3 is not a KDIGO category (3a or 3b) and is not read; "CKD 2/2 diabetes" is not a stage.
    static let ckdStageRx = NoteRx(#"(?:(?-i:\b(?:CKD|CRI)\b)|\bchronic kidney disease\b)[\s-]*(?:stage|stg\.?)?[\s-]*(?-i:G)?(1|2|3a|3b|3|4|5|iiia|iiib|iii|ii|iv|v)(?:\s*d)?\b(?!\s*/\s*\d|\.\d|\s*(?:years?|yrs?|y\b|months?|mos?|weeks?|wks?|days?|x\b))|\bstage\s+(1|2|3a|3b|3|4|5|iiia|iiib|iii|ii|iv|v)\s+(?:(?-i:CKD)|chronic kidney disease)\b|(?:(?-i:CKD)|chronic kidney disease)[^.;]{0,12}?(?-i:\bG(1|2|3a|3b|4|5)\b)"#)
    /// Hemodialysis days: Mon/Wed/Fri or Tue/Thu/Sat, after or before the dialysis words ("HD MWF", "TTS HD").
    static let dialysisDaysRx = NoteRx(#"\b(?:hd|hemodialysis|dialysis|dialyzes|dialyses)\b[^.;]{0,24}?\b(?:(m/?w/?f|mwf|mon(?:day)?[,/ ]+wed(?:nesday)?[,/ ]+(?:and |& )?fri(?:day)?)|(t/?th/?s(?:at)?|tts|tths|tu(?:e(?:s(?:day)?)?)?[,/ ]+th(?:u(?:r(?:s(?:day)?)?)?)?[,/ ]+(?:and |& )?sat(?:urday)?))\b|\b(?:(m/?w/?f|mwf)|(t/?th/?s|tts|tths))\s+(?:hd|hemodialysis|dialysis)\b"#)
    /// An AV fistula or graft: "AVF", "AV graft", "arteriovenous fistula", "radiocephalic", "brachiobasilic"; a bare
    /// "fistula" or "graft" only after a limb ("L arm fistula") in a sentence about dialysis.
    static let fistulaRx = NoteRx(#"\b(?:(?:av|a-v|arteriovenous)\s*(?:fistula|graft)|(?-i:AV[FG])s?|(?:brachio|radio)-?cephalic(?:\s+(?:av\s*)?(?:fistula|graft|avf|avg))?|brachio-?basilic(?:\s+(?:av\s*)?(?:fistula|graft|avf|avg))?)\b"#)
    static let limb = #"(?:(?:left|right|l|r|lt|rt)\.?\s*)?(?:upper arm|forearm|arm|wrist|antecubital|upper extremity|thigh|leg|groin)|(?-i:[LR]UE|[LR]LE)"#
    static let limbFistulaRx = NoteRx(#"\b("# + limb + #")\s+(?:dialysis\s+)?(?:fistula|graft)\b"#)
    static let limbBefore = NoteRx(#"\b("# + limb + #"|(?:left|right|l|r|lt|rt)\.?)\s*$"#)
    static let limbAfter = NoteRx(#"^\s*(?:,|\(|in|on|at|of|to)?\s*(?:the\s+)?("# + limb + #")\b"#)
    static let dialysisWords = NoteRx(#"\b(?:hd|hemodialysis|dialysis|dialyzes|esrd|eskd)\b"#)
    /// A dialysis catheter: "R IJ tunneled HD catheter", "permcath", "tunneled dialysis line", "trialysis", "Quinton".
    static let dialysisCatheterRx = NoteRx(#"(?:((?:(?:left|right|l|r|lt|rt)\.?\s*)?(?:ij|internal jugular|subclavian|femoral|fem)|(?-i:[LR]IJ|[LR]SC|[LR]FV))\s+)?((?:non-?)?tunnel(?:l)?ed\s+)?(?:(?:hd|hemodialysis|dialysis)\s+(?:cath(?:eter)?|line|access catheter)|perm-?a?-?cath|quinton|trialysis|vas-?cath|mahurkar)\b"#)
    static let catheterSiteAfter = NoteRx(#"^\s*(?:,|\(|in|via|at|through)?\s*(?:the\s+)?((?:(?:left|right|l|r)\.?\s*)?(?:ij|internal jugular|subclavian|femoral)|(?-i:[LR]IJ|[LR]SC|[LR]FV))\b"#)
    /// An access no longer there, or one to come ("AVF ligated", "failed AVF", "for AVF creation").
    static let accessGone = NoteRx(#"^\s*(?:ligat\w*|removed|pulled|excised|explant\w*|thrombosed|clotted|creation|placement|planned|pending|to be placed)\b"#)
    /// An arteriovenous fistula that is not a dialysis access (1.9 review): "spinal dural AVF", "coronary AV fistula".
    static let fistulaElsewhereBefore = NoteRx(#"\b(?:dural|spinal|cord|coronary|pulmonary|lung|cerebral|intracranial|brain|carotid[- ]cavernous|cavernous|vertebral|renal|kidney|hepatic|liver|portal|splenic|mesenteric|pelvic|uterine|scalp|facial|orbital|traumatic|congenital|iatrogenic)\s+(?:(?:av|a-v|arteriovenous)\s+)?$"#)
    static let accessGoneBefore = NoteRx(#"\b(?:ligated|thrombosed|failed|clotted|non-?functioning|non-?functional|abandoned|removed|old|planned|future|for|needs?|will need)\s+(?:an?\s+|the\s+)?$"#)
    /// The AF type (2023 ACC/AHA/ACCP/HRS: paroxysmal, persistent, long-standing persistent, permanent).
    static let afTypeRx = NoteRx(#"\b(paroxysmal|persistent|long[- ]?standing(?: persistent)?|permanent)\s+(?:atrial fibrillation|atrial flutter|a[-. ]?fib|a[-. ]?flutter|(?-i:AF|AFL|AFib|Afib))\b|(?-i:\b(PAF)\b)|\b(?:atrial fibrillation|a[-. ]?fib|(?-i:AF))\s*(?:,|\(|-|–)\s*(paroxysmal|persistent|long[- ]?standing persistent|permanent)\b(?!\s*(?:pacemaker|pacer|pacing|(?-i:PPM|ICD|AICD|CRT|CRT-[DP]|CIED)|device|defibrillator|leads?)\b)"#)
    /// Pacer dependence asked, unknown, or with temporary pacing: not read as a permanent device's.
    static let pacerDependenceNo = NoteRx(#"^\s*(?:[:=\-–]\s*)?(?:no|none|negative|unknown|unclear|n)\b|^\s*\?"#)
    static let pacerDependenceUnsure = NoteRx(#"\b(?:unknown|unclear|uncertain|unsure|whether|if|\?)\s+(?:(?:the|pt|patient|he|she)\s+)?(?:is\s+)?$"#)
    static let temporaryPacing = NoteRx(#"\b(?:epicardial|temporary|transvenous|transcutaneous|external|pacing wires?|wires|pads|(?-i:TVP))\b"#)
    /// Latent tuberculosis: "LTBI", "latent TB", a positive skin or blood test ("+PPD treated").
    static let tbLatentRx = NoteRx(#"\blatent\b|(?-i:\bLTBI\b)|(?:\bpositive|\+)\s*(?:ppd|quantiferon|qft|igra|tst|tb test)\b|\b(?:ppd|quantiferon|qft|igra|tst)\s*(?:test\s*)?(?:\+|positive\b|pos\b)"#)
    /// Active tuberculosis: pulmonary or laryngeal (the airborne kinds), cavitary, smear-positive, on treatment.
    static let tbActiveRx = NoteRx(#"\b(?:active|pulmonary|laryngeal|cavitary|miliary)\s+(?:tb|tuberculosis)\b|\bsmear[- ]positive\b|\bafb (?:smear )?positive\b|\bon (?:ripe|rhze)\b|\b(?:tb|tuberculosis),?\s+(?:active|on treatment)\b"#)
    static let tbTreated = NoteRx(#"\b(?:treated|completed|s/p treatment|cured)\b"#)
    static let covidRecentWords = NoteRx(#"\b(?:recent|recently|recovered|resolved)\b|\b\d{1,2} (?:days?|weeks?) ago\b|\blast (?:week|month)\b|\b(?:1|2|one|two) months? ago\b"#)
    static let covidActiveWords = NoteRx(#"\b(?:active|current|currently|acute|ongoing|symptomatic)\b|(?:\bpositive|\+|\bpos\b|\bdetected)\b"#)
    static let covidDateRx = NoteRx(#"\bpositive\s+(?:test\s+)?(?:on\s+)?(\d{1,2}/\d{1,2}(?:/\d{2})?)(?![/\d])"#)
    static let shockKindRx = NoteRx(#"\b("# + shockKinds + #")\b"#)
    /// GI bleed: active or resolved, upper or lower.
    static let bleedActiveBefore = NoteRx(#"\b(?:active|acute|ongoing|current|actively|brisk|massive|presenting with|presents with|admitted (?:with|for)|now with|new)\b[^.;,]{0,12}$"#)
    static let bleedActiveAfter = NoteRx(#"^\s*[,(]?[^.;,]{0,20}\b(?:ongoing|active(?:ly)?|today|now|currently)\b"#)
    static let bleedResolvedAfter = NoteRx(#"^\s*[,(]?[^.;,]{0,25}\b(?:resolved|healed|no recurrence|s/p (?:clips?|egd|banding|cautery|embolization))\b"#)
    static let bleedUpper = NoteRx(#"\b(?:upper|ugi|ugib|variceal|varices|melena|hematemesis|peptic|ulcers?|duodenal|gastric|esophag\w*|egd)\b"#)
    static let bleedLower = NoteRx(#"\b(?:lower|lgi|lgib|diverticul\w*|colonic|colonoscopy|rectal|hemorrhoidal)\b"#)
    /// A gestational diabetes on insulin, and its control.
    static let gdmInsulinRx = NoteRx(#"\b(?:on|requiring|requires|treated with|managed with|needs?|started on)\s+(?:basal\s+|nightly\s+|nph\s+)?insulin\b|\binsulin[- ](?:requiring|treated|dependent)\b"#)
    static let poorControlRx = NoteRx(#"\b(?:poorly|badly|not well|sub-?optimally)[- ]controlled\b|\buncontrolled\b"#)
    static let wellControlRx = NoteRx(#"(?<!diet[- ])(?<!poorly )(?<!badly )(?<!well )\b(?:well[- ])?controlled\b"#)
    static let visualAcuteRx = NoteRx(#"\b(?:acute|sudden|new|acute-onset|new-onset)\b"#)
    static let visualChronicRx = NoteRx(#"\b(?:chronic|longstanding|long-standing|congenital|legally|since (?:birth|childhood)|baseline)\b"#)
    /// The side of a pleural effusion or a pneumothorax, before or after it.
    static let pleuralSideBefore = NoteRx(#"\b(left|right|bilateral|l|r|lt|rt|b/l|bilat)\.?(?:[- ]sided)?\s+(?:(?:large|small|moderate|massive|tension|loculated|simple|complicated|traumatic|spontaneous|pleural|apical|persistent)\s+){0,2}$"#)
    static let pleuralSideAfter = NoteRx(#"^\s*(?:,|\()?\s*(?:on the\s+)?(left|right|bilateral|l|r|b/l|bilat)\b"#)
    static let pleuralSideInside = NoteRx(#"^(left|right|bilateral|l|r|lt|rt|b/l|bilat)\b"#)
    static let chestTubeRx = NoteRx(#"\b(?:(left|right|l|r|lt|rt|bilateral|b/l)\.?\s+)?(?:chest tubes?|thoracostomy tubes?|pigtail(?: catheter)?|pleurx(?: catheter)?)\b(?:\s*(?:\(|,|on the|in the)?\s*(left|right|l|r|bilateral)\b)?"#)
    static let chestTubeGone = NoteRx(#"^\s*(?:was\s+|were\s+)?(?:removed|pulled|out|d/c'?d|discontinued|planned|to be placed)\b"#)
    static let chestTubeGoneBefore = NoteRx(#"\b(?:removed|pulled|removal of|planned|for|needs?|will need|consider(?:ing)?)\s+(?:an?\s+|the\s+)?$"#)
    /// A previous esophageal procedure (the TEE screen asks): dilation, stent, myotomy, resection.
    static let esophagealProcedureRx = NoteRx(#"\besophageal (?:dilation|dilatation|stent(?:ing)?|stent placement|resection|surgery|myotomy)\b|\b(?:pneumatic |balloon |savary )?dilation of (?:the )?esophagus\b|(?-i:\bPOEM\b)|\bper-?oral endoscopic myotomy\b|\bheller myotomy\b|\besophagectomy\b"#)
    /// Smoking: pack-years and the year quit.
    static let packYearsRx = NoteRx(#"\b(\d{1,3}(?:\.\d)?)\s*[- ]?\s*(?:pack[- ]?years?|pk[- ]?yrs?|pack[- ]?yrs?|pky|(?-i:PY|py))\b"#)
    static let quitYearRx = NoteRx(#"\bquit(?:\s+(?:smoking|tobacco|cigarettes))?\s+(?:in\s+)?((?:19|20)\d\d)\b|\bquit(?:\s+(?:smoking|tobacco|cigarettes))?\s+(\d{1,2})\s+(?:years?|yrs?)\s+ago\b"#)
    static let smokingWords = NoteRx(#"\b(?:smok\w*|tobacco|cig\w*|packs?|ppd|nicotine|vap\w*)\b|\bpack[- ]?years?\b"#)
    /// G and P: "G2P1", "G2 P1 A0", "G3P2012" (TPAL: term, preterm, abortus, living; P is term + preterm).
    static let gpalRx = NoteRx(#"(?-i:\bG(\d{1,2})\s?P(?:(\d)-?(\d)-?(\d)-?(\d)|(\d{1,2}))(?:\s?Ab?(\d{1,2}))?(?:\s?L(\d{1,2}))?\b)"#)
    /// Weeks of gestation: "32+4 weeks", "32 4/7", "32w4d", "28 weeks gestation", "IUP at 28 weeks", "GA 32+4".
    static let gestationDaysRx = NoteRx(#"\b(\d{1,2})\s*(?:\+\s*(\d)(?:\s*/\s*7)?|\s+(\d)\s*/\s*7)\s*(?:(weeks?|wks?|w)\b)?"#)
    static let gestationWDRx = NoteRx(#"\b(\d{1,2})\s*w(?:ks?|eeks?)?\s*(\d)\s*d(?:ays?)?\b"#)
    static let gestationWeeksRx = NoteRx(#"\b(\d{1,2})\s*(?:weeks?|wks?)'?\s*(?:of\s+)?(?:gestation(?:al age)?|pregnant|pregnancy|(?-i:GA)|iup)\b|(?:(?-i:\bIUP|\bGA|\bEGA)|\bgestational age)\s*(?:at|of|:|=)?\s*(\d{1,2})\s*(?:\+\s*(\d)\s*)?(?:weeks?|wks?)\b"#)
    /// A sentence about a pregnancy. Not a bare "weeks" (1.9 review: "Gleason 4+3, diagnosed 6 weeks ago" is not 4+3 weeks).
    static let pregnancyWords = NoteRx(#"\b(?:pregnan\w*|gestation\w*|parturient|gravid\w*|labou?r|edd|lmp)\b|(?-i:\b(?:IUP|GA|EGA|G\d{1,2}\s?P\d)\b)"#)
    static let hivLoadRx = NoteRx(#"\b(?:viral load|(?-i:VL))\s*(?:is|of|was|:|=)?\s*(undetectable|suppressed|non-?detectable|<\s*\d+(?:\s*copies(?:\s*/\s*ml)?)?|\d[\d,]*(?:\s*copies(?:\s*/\s*ml)?)?)"#)
    /// Anticoagulants, by name: heparin and enoxaparin with their intensity, warfarin (its INR is the lab), the others by
    /// name. Not in an allergy sentence, not one to avoid, not heparin-induced thrombocytopenia, a heparin flush or lock,
    /// nor one stopped or taken before.
    static let anticoagulantRx = NoteRx(#"\b(unfractionated heparin|heparin|(?-i:UFH)|enoxaparin|lovenox|(?-i:LMWH)|low[- ]molecular[- ]weight heparin|warfarin|coumadin|jantoven|apixaban|eliquis|rivaroxaban|xarelto|dabigatran|pradaxa|edoxaban|savaysa|dalteparin|fragmin|fondaparinux|arixtra|bivalirudin|argatroban|(?-i:DOAC|NOAC))\b(?![- ](?:induced|flush(?:es)?|lock(?:ed|s)?|free|allergy|antibod\w*|pf4)\b)"#)
    static let anticoagulantOff = NoteRx(#"\b(?:off|stopped|discontinued|d/c'?d|dc'?d|no longer|previously|formerly|was on|were on|used to (?:be on|take)|avoid\w*|contraindicat\w*|allergic to)\b[^.;,]{0,20}$"#)
    static let anticoagulantOffAfter = NoteRx(#"^[^.;,]{0,25}?\b(?:stopped|discontinued|d/c'?d|dc'?d|no longer|contraindicated)\b"#)
    static let therapeuticRx = NoteRx(#"\b(?:gtts?|drips?|infusion|therapeutic|treatment[- ]dose|full[- ]dose|weight[- ]based|nomogram|bridg\w*|ptt goal|anti-?xa goal|(?:1|1\.5)\s*mg\s*/\s*kg|\d[\d,]*\s*(?:units?|u)\s*/\s*(?:kg\s*/\s*)?(?:hr|h|hour))\b"#)
    static let prophylaxisRx = NoteRx(#"\b(?:prophyla\w*|ppx|40\s*(?:mg)?\s*(?:(?:sq|subq|sc)\s+)?(?:daily|qd|once daily|q\s?24\s?h?|nightly)|30\s*(?:mg)?\s*(?:(?:sq|subq|sc)\s+)?(?:bid|q\s?12\s?h?))\b"#)
    static let heparinSubcutaneousRx = NoteRx(#"\b(?:sq|subq|sc|subcut\w*|5,?000(?:\s*(?:units?|u))?|7,?500(?:\s*(?:units?|u))?|q\s?8\s?h?)\b"#)
    static let fvlRx = NoteRx(#"\bfactor (?:v|5) leiden\b|(?-i:\bFVL\b)|\bf5 leiden\b"#)
    /// A place in the body: an arthritis's joint, a fracture's bone, a compartment syndrome's limb.
    static let anatomy = #"(?:distal radius|femoral neck|femoral shaft|tibial plateau|lumbar spine|cervical spine|thoracic spine|upper arm|lower leg|upper extremity|lower extremity|c-?spine|tib(?:ia)?[/-]fib(?:ula)?|knees?|hips?|shoulders?|hands?|wrists?|ankles?|elbows?|fingers?|thumbs?|toes?|feet|foot|spine|neck|back|tmj|jaw|femur|femoral|intertrochanteric|subtrochanteric|tibia|tibial|fibula|patella|humerus|humeral|clavicle|scapula|radius|ulna|olecranon|ribs?|sternum|sternal|pelvis|pelvic|acetabul(?:um|ar)|sacr(?:um|al)|coccyx|vertebral|vertebrae?|compression|skull|mandible|mandibular|orbital|nasal|facial|zygomatic|maxillary|calcaneus|calcaneal|metatarsals?|legs?|thigh|calf|forearm|arm|gluteal|abdominal|(?-i:[LR][UL]E)|(?-i:[CTL]\d{1,2}(?:-[CTL]?\d{1,2})?))"#
    static let sideWord = #"(?:left|right|bilateral|both|l|r|lt|rt|b/l|bilat)\.?"#
    static let placeBefore = NoteRx(#"((?:"# + sideWord + #"\s+)?(?:"# + anatomy + #"\s+){1,2})$"#)
    static let placeAfter = NoteRx(#"^\s+(?:arthritis\s+)?(?:of|in|to|at|involving)\s+(?:the\s+|both\s+|his\s+|her\s+|their\s+)?((?:"# + sideWord + #"\s+)?"# + anatomy + #"(?:\s+"# + anatomy + #")?)\b"#)
    static let sepsisSourceAfter = NoteRx(#"^\s*(?:shock\s+)?(?:from|due to|secondary to|2/2(?: to)?|d/t|in the setting of|with (?:a )?source(?: of)?|source\s*:?)\s+(?:an?\s+|the\s+|presumed\s+|likely\s+|probable\s+|suspected\s+)?([a-z][a-z /'-]{1,40}?)(?=\s*(?:[,.;)(]|$)|\s+(?:on|with|and|now|s/p|requiring|status|currently|in|who|but|for)\b)"#)
    static let sepsisSourceBefore = NoteRx(#"\b(pulmonary|urinary|abdominal|intra-?abdominal|biliary|line|catheter|skin|soft tissue|wound|pneumonia|uti|cholangitis|line-associated|catheter-related)[- ](?:source\s+)?$"#)

    static var detailPatterns: [NoteRx] {
        [ckdStageRx, dialysisDaysRx, fistulaRx, fistulaElsewhereBefore, limbFistulaRx, limbBefore, limbAfter, dialysisWords, dialysisCatheterRx, catheterSiteAfter, accessGone,
         accessGoneBefore, afTypeRx, pacerDependenceNo, pacerDependenceUnsure, temporaryPacing, tbLatentRx, tbActiveRx, tbTreated, covidRecentWords,
         covidActiveWords, covidDateRx, shockKindRx, bleedActiveBefore, bleedActiveAfter, bleedResolvedAfter, bleedUpper, bleedLower, gdmInsulinRx,
         poorControlRx, wellControlRx, visualAcuteRx, visualChronicRx, pleuralSideBefore, pleuralSideAfter, pleuralSideInside, chestTubeRx,
         chestTubeGone, chestTubeGoneBefore, esophagealProcedureRx, packYearsRx, quitYearRx, smokingWords, gpalRx, gestationDaysRx, gestationWDRx,
         gestationWeeksRx, pregnancyWords, hivLoadRx, anticoagulantRx, anticoagulantOff, anticoagulantOffAfter, therapeuticRx, prophylaxisRx,
         heparinSubcutaneousRx, fvlRx, placeBefore, placeAfter, sepsisSourceAfter, sepsisSourceBefore, riskBefore, riskAfter, historyCueRx,
         causeWords, pastTailRx, pmhBefore, formerBefore, formerAfter, drugNegAfter, plannedWide, NoteRx(shockRx)]
    }

    /// The words of a problem's own detail field, read with it (problemNoteField): a fracture's place, an arthritis's
    /// joint, the esophageal disorder's type, the psychological disorder's name, a thrombophilia other than FVL, the burn,
    /// the source of a sepsis.
    private static func detailWords(_ id: String, _ c: String, _ m: NSTextCheckingResult) -> (text: String, range: NSRange)? {
        let ns = c as NSString
        let hit = ns.substring(with: m.range)
        let end = m.range.location + m.range.length
        let before = ns.substring(to: m.range.location), after = ns.substring(from: end)
        func place() -> (text: String, range: NSRange)? {
            if let b = placeBefore.first(before), let t = b.text(1, in: before)?.trimmingCharacters(in: .whitespaces), !t.isEmpty {
                return (t, b.range)
            }
            if let a = placeAfter.first(after), let t = a.text(1, in: after) {
                return (t, NSRange(location: end, length: a.range.length))
            }
            return nil
        }
        switch id {
        case "fracture", "compartment-syndrome", "ra", "oa":
            return place()
        case "esophageal-disorder", "psych", "burn":
            return (hit, m.range)
        case "thrombophilia-heme":
            return fvlRx.first(hit) == nil ? (hit, m.range) : nil
        case "sepsis":
            if hit.lowercased() == "urosepsis" { return ("urinary", m.range) }
            if let a = sepsisSourceAfter.first(after), let t = a.text(1, in: after) {
                return (t.trimmingCharacters(in: .whitespaces), NSRange(location: end, length: a.range.length))
            }
            if let b = sepsisSourceBefore.first(before), let t = b.text(1, in: before) { return (t, b.range) }
            return nil
        default:
            return nil
        }
    }

    private static func kdigoStage(_ raw: String) -> String? {
        let map = ["1": "1", "2": "2", "3a": "3a", "3b": "3b", "4": "4", "5": "5", "ii": "2", "iiia": "3a", "iiib": "3b", "iv": "4", "v": "5"]
        return map[raw.lowercased()]
    }

    private static func readDetails19(_ c: String, _ h: inout Hits) {
        let ns = c as NSString
        func found(_ id: String) -> Bool { h.findings.contains { $0.id == "problem:" + id } }
        func free(_ r: NSRange) -> Bool { !negated(c, at: r.location) && !familyContext(c, at: r.location) }
        func before(_ r: NSRange) -> String { ns.substring(to: r.location) }
        func after(_ r: NSRange) -> String { ns.substring(from: r.location + r.length) }
        func add(_ problem: String, _ key: String, _ value: String, _ r: NSRange) {
            h.details.append(NoteDetail(problem: problem, key: key, value: value, range: r))
        }

        // Renal: the CKD stage, the dialysis days and the access (with the hemodialysis when the sentence has it; a
        // fistula before dialysis is a detail alone, and the note-wide reading joins one told apart: PatientNote.read).
        if let m = ckdStageRx.all(c).first(where: { free($0.range) }) {
            if let raw = m.text([1, 2, 3], in: c), let stage = kdigoStage(raw) { add("ckd", "ckdStage", stage, m.range) } else { h.seen(m.range) }
        }
        if let m = dialysisDaysRx.all(c).first(where: { free($0.range) }) {
            add("esrd-dialysis", "dialysisSchedule", m.text([1, 3], in: c) != nil ? "mwf" : "tts", m.range)
        }
        let dialysis = found("esrd-dialysis") || h.details.contains(where: { $0.problem == "esrd-dialysis" }) ? "esrd-dialysis" : ""
        var accesses: [NSRange] = []
        for m in fistulaRx.all(c) + (dialysisWords.first(c) != nil ? limbFistulaRx.all(c) : []) where free(m.range) {
            guard !accesses.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) else { continue }
            if accessGone.first(after(m.range)) != nil || accessGoneBefore.first(before(m.range)) != nil || plannedWide.first(before(m.range)) != nil
                || fistulaElsewhereBefore.first(before(m.range)) != nil {
                h.seen(m.range)
                continue
            }
            accesses.append(m.range)
            let word = ns.substring(with: m.range)
            var site = m.numberOfRanges > 1 ? (m.text(1, in: c) ?? "") : ""
            var r = m.range
            if site.isEmpty, let b = limbBefore.first(before(m.range)), let t = b.text(1, in: before(m.range)) {
                site = t.trimmingCharacters(in: .whitespaces)
                r = NSUnionRange(r, b.range)
            }
            if word.lowercased().contains("cephalic") || word.lowercased().contains("basilic") {
                let vein = word.split(separator: " ").first.map(String.init) ?? word
                site = (site.isEmpty ? "" : site + " ") + vein
            } else if site.isEmpty, let a = limbAfter.first(after(m.range)), let t = a.text(1, in: after(m.range)) {
                site = t
                r.length += a.range.length
            }
            add(dialysis, "fistula", site.trimmingCharacters(in: .whitespaces), r)
        }
        for m in dialysisCatheterRx.all(c) where free(m.range) {
            if chestTubeGone.first(after(m.range)) != nil || accessGoneBefore.first(before(m.range)) != nil { h.seen(m.range); continue }
            var site = [m.text(1, in: c), m.text(2, in: c)].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
            var r = m.range
            if m.text(1, in: c) == nil, let a = catheterSiteAfter.first(after(m.range)), let t = a.text(1, in: after(m.range)) {
                site = ([t] + (site.isEmpty ? [] : [site])).joined(separator: " ")
                r.length += a.range.length
            }
            add(dialysis, "catheter", site, r)
        }

        // Cardiovascular: the AF type; pacer dependence on a permanent device ("not pacer dependent", "pacer dependent:
        // no" and dependence on temporary wires are not read).
        if found("af"), let m = afTypeRx.all(c).first(where: { free($0.range) }), let t = m.text([1, 2, 3], in: c)?.lowercased() {
            let type = t == "paf" || t.hasPrefix("parox") ? "paroxysmal" : (t.hasPrefix("long") ? "longstanding" : t)
            add("af", "afType", type, m.range)
        }
        if temporaryPacing.first(c) == nil,
           let m = pacerDependent.all(c).first(where: { free($0.range) && pacerDependenceNo.first(after($0.range)) == nil && pacerDependenceUnsure.first(before($0.range)) == nil }) {
            add(found("icd") && !found("pacemaker") ? "icd" : "pacemaker", "pacerDependent", "true", m.range)
        } else {
            for m in pacerDependent.all(c) { h.seen(m.range) }
        }

        // Infectious: the hepatitis types, TB latent or active, COVID-19 active or recent (and the date of the positive
        // test), the HIV viral load.
        for m in acceptedMentions("hepatitis-viral", in: c) {
            let t = ns.substring(with: m.range).lowercased()
            let type = t.contains("hbv") || t.contains("hbsag") ? "b" : (t.contains("hcv") ? "c" : (t.contains("hav") ? "a" : String(t.filter(\.isLetter).suffix(1))))
            if ["a", "b", "c"].contains(type) { add("hepatitis-viral", "hepatitisTypes", type, m.range) }
        }
        if found("tb") {
            if let m = tbLatentRx.all(c).first(where: { free($0.range) }) {
                add("tb", "tbStatus", "latent", m.range)
            } else if let m = tbActiveRx.all(c).first(where: { free($0.range) && !toldAsPast(c, $0) }), tbTreated.first(c) == nil {
                add("tb", "tbStatus", "active", m.range)
            }
        }
        if found("covid-recent") {
            if let m = covidRecentWords.first(c) {
                add("covid-recent", "covidStatus", "recent", m.range)
            } else if let m = covidActiveWords.first(c) {
                add("covid-recent", "covidStatus", "active", m.range)
            }
            if let m = covidDateRx.first(c), let d = m.text(1, in: c) { add("covid-recent", "note", d, m.range) }
        }
        if found("hiv"), let m = hivLoadRx.first(c), free(m.range), let v = m.text(1, in: c) { add("hiv", "note", "viral load " + v, m.range) }

        // Acute illness: the kinds of shock ("septic" is distributive).
        for m in acceptedMentions("shock", in: c) {
            var kinds: [String] = []
            for k in shockKindRx.all(ns.substring(with: m.range)) {
                let w = (ns.substring(with: m.range) as NSString).substring(with: k.range).lowercased()
                let kind: String?
                if w == "cardiogenic" || w == "obstructive" { kind = w }
                else if w.hasPrefix("h") { kind = "hypovolemic" }
                else if w == "mixed" { kind = nil }
                else { kind = "distributive" }
                if let kind, !kinds.contains(kind) { kinds.append(kind) }
            }
            if !kinds.isEmpty { add("shock", "shockTypes", kinds.joined(separator: ","), m.range) }
        }

        // GI: a GI bleed active or resolved, upper or lower; a previous esophageal procedure.
        if let m = acceptedMentions("gi-bleed", in: c).first {
            let b = before(m.range), a = after(m.range)
            let window = String(b.suffix(24)) + " " + ns.substring(with: m.range) + " " + String(a.prefix(24))
            let status = toldAsPast(c, m) || bleedResolvedAfter.first(a) != nil ? "resolved"
                : (bleedActiveBefore.first(b) != nil || bleedActiveAfter.first(a) != nil ? "active" : "")
            let site = bleedLower.first(window) != nil ? "lower" : (bleedUpper.first(window) != nil ? "upper" : "")
            if !status.isEmpty || !site.isEmpty { add("gi-bleed", "giBleed", status + "," + site, m.range) }
        }
        if let m = esophagealProcedureRx.all(c).first(where: { free($0.range) && toldAsPast(c, $0) }) {
            add("esophageal-disorder", "esophagealProcedure", ns.substring(with: m.range), m.range)
        }

        // Hematologic: the anticoagulants.
        readAnticoagulants(c, &h)

        // Obstetric: a peripartum cardiomyopathy's LVEF (below 40%: the ASA's class IV example), a gestational
        // diabetes's insulin and control, G and P, the weeks of gestation.
        if found("ppcm"), let m = efRx.first(c), let a = number(m, [1], c) {
            let ef = number(m, [2], c).map { ($0 + a) / 2 } ?? a
            add(ef < 40 ? "peripartum-cm" : "ppcm", "ppcmEF", NumText.short(ef), m.range)
        }
        if found("gdm") {
            if let m = gdmInsulinRx.all(c).first(where: { free($0.range) }) { add("gdm", "gdmInsulin", "true", m.range) }
            if let m = poorControlRx.first(c) { add("gdm", "gdmControl", "uncontrolled", m.range) }
            else if let m = wellControlRx.all(c).first(where: { free($0.range) }) { add("gdm", "gdmControl", "controlled", m.range) }
        }
        readObstetric(c, &h)

        // Neurologic and respiratory: acute or chronic visual impairment; the side and fluid of an effusion or a
        // pneumothorax, and a chest tube in place.
        if let m = acceptedMentions("visual-impairment", in: c).first {
            let window = String(before(m.range).suffix(24)) + " " + ns.substring(with: m.range) + " " + String(after(m.range).prefix(20))
            if visualAcuteRx.first(window) != nil { add("visual-impairment", "visualImpairment", "acute", m.range) }
            else if visualChronicRx.first(window) != nil { add("visual-impairment", "visualImpairment", "chronic", m.range) }
        }
        var pleuralSide = ""
        for id in ["pleural-effusion", "pneumothorax"] {
            guard let m = acceptedMentions(id, in: c).first else { continue }
            defer { if pleuralSide.isEmpty, let d = h.details.last, d.key == "pleural" { pleuralSide = String(d.value.prefix { $0 != "," }) } }
            let hit = ns.substring(with: m.range).lowercased()
            let s = pleuralSideInside.first(hit).flatMap { $0.text(1, in: hit) } ?? pleuralSideBefore.first(before(m.range)).flatMap { $0.text(1, in: before(m.range)) }
                ?? pleuralSideAfter.first(after(m.range)).flatMap { $0.text(1, in: after(m.range)) }
            let side = s.map(sideName) ?? ""
            let fluid = id == "pleural-effusion" ? (hit.contains("hemo") || hit.contains("haemo") ? "hemothorax" : (hit.contains("chylo") ? "chylothorax" : "")) : ""
            if !side.isEmpty || !fluid.isEmpty { add(id, "pleural", side + "," + fluid, m.range) }
        }
        if found("pleural-effusion") || found("pneumothorax"),
           let m = chestTubeRx.all(c).first(where: { free($0.range) && chestTubeGone.first(after($0.range)) == nil && chestTubeGoneBefore.first(before($0.range)) == nil }) {
            // A tube with no side of its own is on the side of the one effusion or pneumothorax.
            var sides = [m.text(1, in: c), m.text(2, in: c)].compactMap { $0 }.map(sideName)
            if sides.isEmpty, pleuralSide == "left" || pleuralSide == "right" { sides = [pleuralSide] }
            let list = sides.contains("bilateral") ? ["left", "right"] : sides
            add(found("pneumothorax") ? "pneumothorax" : "pleural-effusion", "chestTube", list.joined(separator: ","), m.range)
        }

        // Smoking: pack-years and the year quit (with a smoking word in the sentence).
        if let m = packYearsRx.all(c).first(where: { free($0.range) }), let v = number(m, [1], c), v > 0, v <= 300 {
            add("", "packYears", NumText.short(v), m.range)
        }
        if smokingWords.first(c) != nil, let m = quitYearRx.first(c) {
            let thisYear = Calendar(identifier: .gregorian).component(.year, from: Date())
            let year = m.text(1, in: c).flatMap { Int($0) } ?? m.text(2, in: c).flatMap { Int($0) }.map { thisYear - $0 }
            if let year, year >= 1930, year <= thisYear { add("", "smokingQuitYear", String(year), m.range) }
        }

        // Items that file their page's item beside them (the Psychological disorder for depression, Illicit drug use for
        // cocaine, Bleeding disorder for vWD, Thrombophilia for FVL).
        let bases: [(String, String)] = [("mdd", "psych"), ("anxiety", "psych"), ("vwd", "bleeding"), ("hemophilia-a", "bleeding"),
                                         ("hemophilia-b", "bleeding"), ("fvl", "thrombophilia-heme"), ("cocaine", "substance"),
                                         ("opioid-use", "substance"), ("marijuana", "substance"), ("methamphetamine", "substance")]
        for (member, base) in bases where !found(base) {
            guard let i = h.findings.firstIndex(where: { $0.id == "problem:" + member }), let l = problemLabels[base] else { continue }
            h.add(PatientNoteFinding(id: "problem:" + base, section: Part.history, label: l, change: .problem(base)), at: h.at[i])
        }
        attachDetails(&h)
    }

    private static func sideName(_ s: String) -> String {
        switch s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) {
        case "left", "l", "lt": return "left"
        case "right", "r", "rt": return "right"
        default: return "bilateral"
        }
    }

    /// G and P, and the weeks of gestation. G and P file Pregnant only when a pregnancy is not counted in them (G greater
    /// than P + A): "G2P2" or "G3P2012" in a gynecological note is not a pregnancy.
    private static func readObstetric(_ c: String, _ h: inout Hits) {
        let found = h.findings.contains { $0.id == "problem:pregnant" }
        var pregnant = found
        if let m = gpalRx.first(c), !familyContext(c, at: m.range.location), let g = number(m, [1], c) {
            var p: Double?, a = number(m, [7], c), l = number(m, [8], c)
            if let t = number(m, [2], c), let pre = number(m, [3], c) {
                p = t + pre
                a = number(m, [4], c)
                l = number(m, [5], c)
            } else {
                p = number(m, [6], c)
            }
            if let p, g > p + (a ?? 0) { pregnant = true }
            let value = [Optional(g), p, a, l].map { $0.map { String(Int($0)) } ?? "" }.joined(separator: ",")
            h.details.append(NoteDetail(problem: pregnant ? "pregnant" : "", key: "gpal", value: value, range: m.range))
        }
        // Weeks with days ("32+4", "32 4/7") only in a sentence about a pregnancy, or with "weeks" after them.
        var weeks: (Double, Double?, NSRange)?
        if let m = gestationWDRx.first(c), let w = number(m, [1], c) {
            weeks = (w, number(m, [2], c), m.range)
        } else if let m = gestationWeeksRx.first(c), let w = number(m, [1, 2], c) {
            weeks = (w, number(m, [3], c), m.range)
        } else if let m = gestationDaysRx.all(c).first(where: { $0.text(4, in: c) != nil || pregnant || pregnancyWords.first(c) != nil }),
                  let w = number(m, [1], c) {
            weeks = (w, number(m, [2, 3], c), m.range)
        }
        if let wk = weeks, case let (w, d, r) = wk, w >= 4, w <= 44, (d ?? 0) <= 6, !negated(c, at: r.location), !familyContext(c, at: r.location) {
            h.details.append(NoteDetail(problem: "pregnant", key: "gestation", value: String(Int(w)) + "," + (d.map { String(Int($0)) } ?? ""), range: r))
        }
    }

    /// The anticoagulants a sentence says the patient is on, each to Hematologic's On anticoagulation with its kind.
    private static func readAnticoagulants(_ c: String, _ h: inout Hits) {
        guard allergyCue.first(c) == nil else { return }
        let ns = c as NSString
        let generic: [String: String] = ["unfractionated heparin": "heparin", "ufh": "heparin", "lovenox": "enoxaparin", "coumadin": "warfarin", "jantoven": "warfarin",
                                         "eliquis": "apixaban", "xarelto": "rivaroxaban", "pradaxa": "dabigatran", "savaysa": "edoxaban", "fragmin": "dalteparin",
                                         "arixtra": "fondaparinux", "lmwh": "LMWH", "low molecular weight heparin": "LMWH", "low-molecular-weight heparin": "LMWH",
                                         "low-molecular weight heparin": "LMWH", "low molecular-weight heparin": "LMWH", "doac": "DOAC", "noac": "DOAC"]
        let all = anticoagulantRx.all(c)
        for (i, m) in all.enumerated() where !negated(c, at: m.range.location) && !familyContext(c, at: m.range.location) {
            let before = ns.substring(to: m.range.location)
            let end = m.range.location + m.range.length
            // Up to the next anticoagulant, the clause's end or 40 characters.
            let stop = i + 1 < all.count ? all[i + 1].range.location : ns.length
            let after = ns.substring(with: NSRange(location: end, length: max(0, min(stop, end + 40) - end)))
            if anticoagulantOff.first(before) != nil || anticoagulantOffAfter.first(after) != nil {
                h.seen(m.range)
                continue
            }
            let name = (m.text(1, in: c) ?? "").lowercased()
            let drug = generic[name] ?? name
            let near = String(before.suffix(25)) + " " + after
            switch drug {
            case "heparin", "enoxaparin":
                var kind = ""
                if therapeuticRx.first(near) != nil { kind = "therapeutic" }
                else if prophylaxisRx.first(near) != nil || (drug == "heparin" && heparinSubcutaneousRx.first(near) != nil) { kind = "prophylaxis" }
                h.details.append(NoteDetail(problem: "anticoagulation", key: "anticoagulant:" + drug, value: kind, range: m.range))
            case "warfarin":
                h.details.append(NoteDetail(problem: "anticoagulation", key: "anticoagulant:warfarin", value: "", range: m.range))
            default:
                h.details.append(NoteDetail(problem: "anticoagulation", key: "anticoagulant:other", value: drug, range: m.range))
            }
        }
    }

    /// Details that add to a set ("hepatitis B, C", "cardiogenic, distributive", chest tubes) merge.
    private static let listDetails: Set<String> = ["hepatitisTypes", "shockTypes", "chestTube"]

    /// Puts each detail read on its problem's finding when that finding has nothing else (one chip: "Viral hepatitis
    /// (hepatitis C)"), as the problem's finding when the sentence has none ("on apixaban" files On anticoagulation), or
    /// as a finding of its own.
    private static func attachDetails(_ h: inout Hits) {
        var merged: [NoteDetail] = []
        for d in h.details {
            if let i = merged.firstIndex(where: { $0.problem == d.problem && $0.key == d.key && (d.key != "anticoagulant:other" || $0.value == d.value) }) {
                if listDetails.contains(d.key) { merged[i].value = mergedList(merged[i].value, d.value) }
                merged[i].range = NSUnionRange(merged[i].range, d.range)
                continue
            }
            merged.append(d)
        }
        h.details = []
        for d in merged {
            let change: PatientNoteChange = d.key == "note" ? .problemNote(d.problem, d.value) : .detail(d.problem, d.key, d.value)
            let text = d.key == "note" ? d.value : detailText(d.key, d.value)
            if !d.problem.isEmpty, let i = h.findings.firstIndex(where: { $0.id == "problem:" + d.problem }) {
                if case .problem = h.findings[i].change {
                    h.findings[i].change = change
                    h.findings[i].label += " (" + text + ")"
                    h.at[i] = NSUnionRange(h.at[i], d.range)
                    h.seen(d.range)
                    continue
                }
            } else if !d.problem.isEmpty, let l = problemLabels[d.problem] {
                h.add(PatientNoteFinding(id: "problem:" + d.problem, section: Part.history, label: l + " (" + text + ")", change: change), at: d.range)
                continue
            }
            h.add(PatientNoteFinding(id: detailID(d.problem, d.key, d.value), section: Part.history, label: detailLabel(d.problem, d.key, d.value), change: change),
                  at: d.range)
        }
    }

    /// "hx:ckdStage@ckd", "hx:anticoagulant:other:apixaban@anticoagulation", "hx:packYears".
    static func detailID(_ problem: String, _ key: String, _ value: String) -> String {
        "hx:" + key + (key == "anticoagulant:other" ? ":" + value.lowercased() : "") + (problem.isEmpty ? "" : "@" + problem)
    }

    private static func mergedList(_ a: String, _ b: String) -> String {
        var out = a.split(separator: ",").map(String.init)
        for x in b.split(separator: ",").map(String.init) where !out.contains(x) { out.append(x) }
        return out.joined(separator: ",")
    }

    /// A detail as the review and the quick-add chip show it.
    static func detailLabel(_ problem: String, _ key: String, _ value: String) -> String {
        let text = key == "note" ? value : detailText(key, value)
        if let l = problemLabels[problem] { return l + ": " + text }
        switch key {
        case "packYears", "smokingQuitYear": return "Smoking: " + text
        case "gpal": return "Obstetric history: " + text
        case "fistula", "catheter": return "Dialysis access: " + text
        default: return text
        }
    }

    static func detailText(_ key: String, _ value: String) -> String {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        func part(_ i: Int) -> String { i < parts.count ? parts[i] : "" }
        switch key {
        case "ckdStage": return "stage " + value
        case "dialysisSchedule": return value == "mwf" ? "Mon/Wed/Fri" : (value == "tts" ? "Tue/Thu/Sat" : value)
        case "fistula": return value.isEmpty ? "AV fistula" : "AV fistula, " + value
        case "catheter": return value.isEmpty ? "dialysis catheter" : "dialysis catheter, " + value
        case "afType": return value == "longstanding" ? "long-standing persistent" : value
        case "pacerDependent": return "pacer dependent"
        case "hepatitisTypes": return "hepatitis " + parts.map { $0.uppercased() }.joined(separator: ", ")
        case "shockTypes", "giBleed", "pleural": return parts.filter { !$0.isEmpty }.joined(separator: ", ")
        case "packYears": return value + " pack-years"
        case "smokingQuitYear": return "quit " + value
        case "gpal":
            return zip(["G", "P", "A", "L"], parts).compactMap { $0.1.isEmpty ? nil : $0.0 + $0.1 }.joined(separator: " ")
        case "gestation": return part(0) + (part(1).isEmpty ? "" : "+" + part(1)) + " weeks"
        case "ppcmEF": return "LVEF " + value + "%"
        case "gdmInsulin": return "on insulin"
        case "chestTube": return "chest tube" + (value.isEmpty ? "" : " " + parts.joined(separator: ", "))
        case "esophagealProcedure": return "previous procedure: " + value
        default:
            if key.hasPrefix("anticoagulant:") {
                let drug = String(key.dropFirst("anticoagulant:".count))
                if drug == "other" { return value }
                return value.isEmpty ? drug : drug + ", " + value
            }
            return value
        }
    }

    /// Whether the record already holds a detail, or what it holds instead.
    private static func detailStatus(_ key: String, _ value: String, _ r: PatientRecord) -> PatientNoteStatus {
        let d = r.hx
        let parts = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        func scalar(_ old: String?) -> PatientNoteStatus {
            guard let old, !old.isEmpty else { return .new }
            return old == value ? .recorded : .replaces(detailText(key, old))
        }
        func number(_ old: Double?) -> PatientNoteStatus {
            guard let old else { return .new }
            return same(old, Double(value) ?? -1) ? .recorded : .replaces(detailText(key, NumText.short(old)))
        }
        func list(_ have: Set<String>) -> PatientNoteStatus { Set(parts.filter { !$0.isEmpty }).isSubset(of: have) ? .recorded : .new }
        switch key {
        case "ckdStage": return scalar(d.ckdStage)
        case "dialysisSchedule": return scalar(d.dialysisSchedule)
        case "afType": return scalar(d.afType)
        case "tbStatus": return scalar(d.tbStatus)
        case "covidStatus": return scalar(d.covidStatus)
        case "visualImpairment": return scalar(d.visualImpairment)
        case "gdmControl": return scalar(d.gdmControl)
        case "pacerDependent": return d.pacerDependent ? .recorded : .new
        case "gdmInsulin": return d.gdmInsulin ? .recorded : .new
        case "hepatitisTypes": return list(d.hepatitisTypes)
        case "shockTypes": return list(d.shockTypes)
        case "chestTube": return d.chestTube == true && Set(parts.filter { !$0.isEmpty }).isSubset(of: d.chestTubeSides) ? .recorded : .new
        case "fistula": return d.dialysisAccess.contains("fistula") && (value.isEmpty || mentions(d.fistulaSite, value)) ? .recorded : .new
        case "catheter": return d.dialysisAccess.contains("catheter") && (value.isEmpty || mentions(d.dialysisCatheterSite, value)) ? .recorded : .new
        case "packYears": return number(d.packYears)
        case "ppcmEF": return number(d.ppcmEF)
        case "smokingQuitYear": return number(d.smokingQuitYear.map { Double($0) })
        case "esophagealProcedure": return d.esophagealProcedure == true && mentions(d.esophagealProcedureDetails, value) ? .recorded : .new
        case "giBleed", "pleural":
            let old = key == "giBleed" ? [d.giBleedStatus, d.giBleedSite] : [d.pleuralSide, d.pleuralFluid]
            var differs = false, missing = false
            for (i, o) in old.enumerated() where i < parts.count && !parts[i].isEmpty {
                if o == nil || o == "" { missing = true } else if o != parts[i] { differs = true }
            }
            if differs { return .replaces(old.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")) }
            return missing ? .new : .recorded
        case "gpal", "gestation":
            let old: [Int?] = key == "gpal" ? [d.gravida, d.para, d.abortus, d.living] : [d.gestationWeeks, d.gestationDays]
            var differs = false, missing = false
            for (i, o) in old.enumerated() where i < parts.count && !parts[i].isEmpty {
                if o == nil { missing = true } else if String(o!) != parts[i] { differs = true }
            }
            if differs { return .replaces(detailText(key, old.map { $0.map { String($0) } ?? "" }.joined(separator: ","))) }
            return missing ? .new : .recorded
        default:
            guard key.hasPrefix("anticoagulant:") else { return .new }
            let drug = String(key.dropFirst("anticoagulant:".count))
            guard let a = d.anticoagulants[drug] else { return .new }
            if drug == "other" { return mentions(a.name, value) ? .recorded : .new }
            if value.isEmpty || a.intensity == value { return .recorded }
            return a.intensity.map { .replaces($0) } ?? .new
        }
    }

    /// Writes a detail into the record's History details (PatientHistoryDetails).
    static func setDetail(_ key: String, _ value: String, _ r: inout PatientRecord) {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        func part(_ i: Int) -> String? { i < parts.count && !parts[i].isEmpty ? parts[i] : nil }
        switch key {
        case "ckdStage": r.hx.ckdStage = value
        case "dialysisSchedule": r.hx.dialysisSchedule = value
        case "fistula":
            r.hx.dialysisAccess.insert("fistula")
            r.hx.fistulaSite = joined(r.hx.fistulaSite, value)
        case "catheter":
            r.hx.dialysisAccess.insert("catheter")
            r.hx.dialysisCatheterSite = joined(r.hx.dialysisCatheterSite, value)
        case "afType": r.hx.afType = value
        case "pacerDependent": r.hx.pacerDependent = true
        case "hepatitisTypes": r.hx.hepatitisTypes.formUnion(parts.filter { !$0.isEmpty })
        case "tbStatus": r.hx.tbStatus = value
        case "covidStatus": r.hx.covidStatus = value
        case "shockTypes": r.hx.shockTypes.formUnion(parts.filter { !$0.isEmpty })
        case "giBleed":
            if let s = part(0) { r.hx.giBleedStatus = s }
            if let s = part(1) { r.hx.giBleedSite = s }
        case "packYears": r.hx.packYears = Double(value)
        case "smokingQuitYear": r.hx.smokingQuitYear = Int(value)
        case "gpal":
            if let x = part(0).flatMap({ Int($0) }) { r.hx.gravida = x }
            if let x = part(1).flatMap({ Int($0) }) { r.hx.para = x }
            if let x = part(2).flatMap({ Int($0) }) { r.hx.abortus = x }
            if let x = part(3).flatMap({ Int($0) }) { r.hx.living = x }
        case "gestation":
            r.hx.gestationWeeks = part(0).flatMap { Int($0) }
            r.hx.gestationDays = part(1).flatMap { Int($0) }
        case "ppcmEF": r.hx.ppcmEF = Double(value)
        case "gdmInsulin": r.hx.gdmInsulin = true
        case "gdmControl": r.hx.gdmControl = value
        case "visualImpairment": r.hx.visualImpairment = value
        case "pleural":
            if let s = part(0) { r.hx.pleuralSide = s }
            if let s = part(1) { r.hx.pleuralFluid = s }
        case "chestTube":
            r.hx.pleuralDrained = true
            r.hx.chestTube = true
            r.hx.chestTubeSides.formUnion(parts.filter { !$0.isEmpty })
        case "esophagealProcedure":
            r.hx.esophagealProcedure = true
            r.hx.esophagealProcedureDetails = joined(r.hx.esophagealProcedureDetails, value)
        default:
            guard key.hasPrefix("anticoagulant:") else { return }
            let drug = String(key.dropFirst("anticoagulant:".count))
            var a = r.hx.anticoagulants[drug] ?? PatientAnticoagulant()
            if drug == "other" {
                a.name = joined(a.name, value)
            } else if !value.isEmpty {
                a.intensity = value
            }
            r.hx.anticoagulants[drug] = a
        }
    }

    private static func number(_ m: NSTextCheckingResult, _ groups: [Int], _ s: String) -> Double? {
        guard let t = m.text(groups, in: s) else { return nil }
        return Double(t.replacingOccurrences(of: ",", with: ""))
    }

    // MARK: Patient

    static let ageRx = NoteRx(#"\b(\d{1,3})\s*-?\s*(?:y/?o\b|yo\b|y\.o\.?|(?:years?|yrs?)[- ]old\b)|\bage[sd]?\s*:?\s*(\d{1,3})\b"#)
    static let ageMonthsRx = NoteRx(#"\b(\d{1,2})\s*-?\s*(?:months?|mos?)[- ]old\b"#)
    static let ageWeeksRx = NoteRx(#"\b(\d{1,2})\s*-?\s*(?:weeks?|wks?)[- ]old\b"#)
    /// Before "101F": a temperature, not an age and sex ("Tmax 101F", "febrile to 101F").
    static let notAge = NoteRx(#"\b(?:t|tmax|t\s?max|temp|temperature|febrile(?:\s+to)?|fever(?:\s+(?:of|to))?|max|spiked(?:\s+to)?)\s*:?\s*$"#)
    static let ageSexRx = NoteRx(#"(?:^|\s)(\d{1,3})\s?(?i:yo|y/o|y\.o\.?)?\s?(M|F)\b"#, caseSensitive: true)
    static let maleRx = NoteRx(#"\b(?:male|man|gentleman|gent|boy)\b"#)
    static let femaleRx = NoteRx(#"\b(?:female|woman|lady|girl)\b"#)
    static let heightFtRx = NoteRx(#"\b([3-7])\s*(?:'|’|ft\b|feet\b|foot\b)\s*(?:(\d{1,2})\s*(?:"|”|''|in\b|inches\b)?)?"#)
    static let heightCtxRx = NoteRx(#"\b(?:height|ht|tall)\b\s*(?:of|is|:|=)?\s*(\d{2,3}(?:\.\d+)?)\s*(cm|in\b|inches|")?"#)
    static let heightMRx = NoteRx(#"\b([12]\.\d{1,2})\s*m\b"#)
    static let heightCmRx = NoteRx(#"\b(\d{3}(?:\.\d+)?)\s*cm\b"#)
    static let weightKgRx = NoteRx(#"\b(\d{1,3}(?:\.\d+)?)\s*(?:kg|kgs|kilos?|kilograms?)\b"#)
    static let weightLbRx = NoteRx(#"\b(\d{2,3}(?:\.\d+)?)\s*(?:lb|lbs|pounds?)\b"#)
    static let lossCue = NoteRx(#"\b(?:lost|loss of|losing|gained|gain of|gaining|down|up|dropped)\s*(?:about |around |~|approximately )?$"#)
    static let bmiRx = NoteRx(#"\bbmi\s*(?:of|is|:|=)?\s*\d{2}(?:\.\d)?\b"#)

    private static func readPatient(_ c: String, _ h: inout Hits) {
        if let m = ageMonthsRx.first(c), let v = number(m, [1], c), v > 0 {
            h.add(PatientNoteFinding(id: "age", section: Part.patient, label: "Age " + NumText.short(v) + " months", change: .age(v / 12)), at: m.range)
        } else if let m = ageWeeksRx.first(c), let v = number(m, [1], c), v > 0 {
            h.add(PatientNoteFinding(id: "age", section: Part.patient, label: "Age " + NumText.short(v) + " weeks", change: .age(v / 52)), at: m.range)
        } else if let m = ageSexRx.all(c).first(where: { notAge.first((c as NSString).substring(to: $0.range.location)) == nil }),
                  let v = number(m, [1], c), v > 0, v < 120, let s = m.text(2, in: c) {
            h.add(PatientNoteFinding(id: "age", section: Part.patient, label: "Age " + PatientRecord.ageText(v),
                                     change: .age(Swift.min(v, PatientRecord.oldestAge))), at: m.range)
            let sex: PatientSex = s == "M" ? .male : .female
            h.add(PatientNoteFinding(id: "sex", section: Part.patient, label: sex.label, change: .sex(sex)), at: m.range)
        } else if let m = ageRx.first(c), let v = number(m, [1, 2], c), v > 0, v < 120 {
            h.add(PatientNoteFinding(id: "age", section: Part.patient, label: "Age " + PatientRecord.ageText(v),
                                     change: .age(Swift.min(v, PatientRecord.oldestAge))), at: m.range)
        }
        if let m = femaleRx.first(c) {
            h.add(PatientNoteFinding(id: "sex", section: Part.patient, label: "Female", change: .sex(.female)), at: m.range)
        } else if let m = maleRx.first(c) {
            h.add(PatientNoteFinding(id: "sex", section: Part.patient, label: "Male", change: .sex(.male)), at: m.range)
        }

        var height: Double?
        var heightRange = NSRange(location: 0, length: 0)
        if let m = heightFtRx.first(c), let ft = number(m, [1], c) {
            let inch = number(m, [2], c) ?? 0
            if inch < 12 { height = (ft * 12 + inch) * 2.54; heightRange = m.range }
        }
        if height == nil, let m = heightCtxRx.first(c), let v = number(m, [1], c) {
            let unit = m.text(2, in: c)?.lowercased()
            if unit == "in" || unit == "inches" || unit == "\"" { height = v * 2.54; heightRange = m.range }
            else if v >= 100 || unit == "cm" { height = v; heightRange = m.range }
        }
        if height == nil, let m = heightMRx.first(c), let v = number(m, [1], c) { height = v * 100; heightRange = m.range }
        if height == nil, let m = heightCmRx.first(c), let v = number(m, [1], c), v >= 120 { height = v; heightRange = m.range }
        if let v = height, v >= 40, v <= 230 {
            let cm = (v * 10).rounded() / 10
            h.add(PatientNoteFinding(id: "height", section: Part.patient, label: "Height " + NumText.short(cm) + " cm", change: .height(cm)), at: heightRange)
        }

        var weight: Double?
        var weightRange = NSRange(location: 0, length: 0)
        let units: [(NoteRx, Double)] = [(weightKgRx, 1.0), (weightLbRx, 2.20462)]
        for (rx, perKg) in units where weight == nil {
            for m in rx.all(c) {
                let before = (c as NSString).substring(to: m.range.location)
                if lossCue.first(before) != nil {
                    h.seen(m.range)
                    continue
                }
                if let v = number(m, [1], c) {
                    weight = v / perKg
                    weightRange = m.range
                    break
                }
            }
        }
        if let v = weight, v >= 0.5, v <= 400 {
            let kg = (v * 10).rounded() / 10
            h.add(PatientNoteFinding(id: "weight", section: Part.patient, label: "Weight " + NumText.short(kg) + " kg", change: .weight(kg)), at: weightRange)
        }
        if let m = bmiRx.first(c) { h.seen(m.range) }
    }

    // MARK: Procedure

    static let procedureHeaderRx = NoteRx(#"^\s*(?:procedure|surgery|operation|planned procedure|proposed procedure|planned surgery|case)\s*[:\-–]\s*(.+)"#)
    static let procedureRx = NoteRx(#"\b(?:scheduled|booked|planned|listed|presenting|presents|presented|consented|posted|coming in)\s+for\s+(?:an?\s+|the\s+|his\s+|her\s+)?(?:elective\s+|urgent\s+|emergent\s+|emergency\s+|semi-?urgent\s+)?(.+)"#)
    static let procedurePersonRx = NoteRx(#"(?:\b(?:male|female|man|woman|boy|girl|gentleman|lady|patient|pt|yo|y/o|gestation|weeks|wks)|(?<=\d)(?-i:[MF])|\b(?-i:[MF]))\s+(?:presenting\s+|here\s+|scheduled\s+|booked\s+|coming in\s+|now\s+)?for\s+(?:an?\s+|the\s+|his\s+|her\s+)?(?:elective\s+|urgent\s+|emergent\s+|emergency\s+|semi-?urgent\s+)?(.+)"#)
    static let procedureTechniqueRx = NoteRx(#"\bfor\s+(?:an?\s+|the\s+)?(?:elective\s+|urgent\s+|emergent\s+|emergency\s+)?([^,;]{3,80}?)\s+(?:under|with)\s+(?:general|ga\b|geta\b|mac\b|spinal|epidural|cse\b|sedation|regional|neuraxial|a block|a nerve block|block|monitored)"#)
    static let procedureLeadRx = NoteRx(#"^\s*(?:for|undergoing|to undergo)\s+(?:an?\s+|the\s+)?(?:elective\s+|urgent\s+|emergent\s+|emergency\s+)?(.+)"#)
    static let procedureCut = NoteRx(#"\s+(?:under|with (?:dr\b|spinal|epidural|general|ga\b|mac\b|sedation|regional|a block|block)|by dr\b|tomorrow|today|tonight|this (?:morning|afternoon|evening)|on (?:\d|mon|tue|wed|thu|fri|sat|sun)|at \d|in the (?:morning|afternoon)|who\b|which\b|that\b|history of|hx of|h/o|pmh|past medical|with a history|has\b|is\b|no\b|denies|allergic|allergies|meds\b|medications|nkda|npo\b).*$|\s*[,;(].*$"#)
    static let emergencyRx = NoteRx(#"\b(?:emergent|emergency|emergently|stat)\b(?!\s+(?:department|dept|room|services|medical|physician|medicine))"#)
    static let urgentRx = NoteRx(#"\b(?:urgent|urgently|semi-?urgent)\b(?!\s+care)"#)
    static let timeSensitiveRx = NoteRx(#"\btime[- ]sensitive\b"#)
    static let electiveRx = NoteRx(#"\belective\b"#)
    static let plannedRx = NoteRx(#"\b(?:plan|planned|planning|scheduled|booked|consented|under|will (?:have|receive|get|be under))\b"#)
    static let gaRx = NoteRx(#"general an(?:a)?esthe(?:sia|tic)|(?-i:\b(?:GA|GETA)\b)(?!\s*\d)|\bunder general\b"#)
    static let neuraxialRx = NoteRx(#"\b(?:spinal|epidural|neuraxial|intrathecal)\b(?!\s+(?:cord|stenosis|fusion|surgery|fracture|injury|abscess|hematoma|haematoma|steroid|injection|stimulator|tumou?r|canal|column|anatomy|muscular))|combined spinal|(?-i:\b(?:CSE|SAB)\b)"#)
    static let macRx = NoteRx(#"(?-i:\bMAC\b)|monitored an(?:a)?esthesia care|\bsedation\b"#)
    static let regionalRx = NoteRx(#"nerve block|regional (?:an(?:a)?esthesia|block)|interscalene|supraclavicular|infraclavicular|axillary block|femoral (?:nerve )?block|adductor canal|(?-i:\b(?:TAP|ESP|PENG|QL)\b) block|popliteal|sciatic (?:nerve )?block|fascia iliaca"#)
    static let asaRx = NoteRx(#"\bASA\s*(?:class|PS|physical status)?\s*:?\s*(VI|IV|V|III|II|I|[1-6])(E)?\b"#, caseSensitive: true)

    private static func readProcedure(_ c: String, _ choices: [String: String], _ h: inout Hits) {
        let pastClause = pastCare.first(c) != nil
        var gotProcedure = false
        if !pastClause {
            for rx in [procedureHeaderRx, procedureRx, procedurePersonRx, procedureLeadRx, procedureTechniqueRx] {
                guard let m = rx.first(c), var p = m.text(1, in: c) else { continue }
                if let cut = procedureCut.first(p) { p = (p as NSString).substring(to: cut.range.location) }
                p = p.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;"))
                if p.count >= 3 && p.count <= 120 {
                    // A bare Bentall asks which valve (1.8.1); the answer is read into the procedure.
                    let asked = ProcedureCatalog.asking(p, choices: choices)
                    h.questions += asked.questions
                    p = asked.text
                    h.add(PatientNoteFinding(id: "procedure", section: Part.procedure, label: "Procedure: " + p, change: .procedure(p)), at: m.range)
                    gotProcedure = true
                }
                break
            }
        }
        let timings: [(NoteRx, PatientUrgency)] = [(emergencyRx, .emergency), (urgentRx, .urgent), (timeSensitiveRx, .timeSensitive), (electiveRx, .elective)]
        for (rx, u) in timings {
            guard let m = rx.first(c), !negated(c, at: m.range.location) else { continue }
            h.add(PatientNoteFinding(id: "urgency", section: Part.procedure, label: "Timing: " + u.label.lowercased(), change: .urgency(u)), at: m.range)
            break
        }
        if !pastClause && (gotProcedure || plannedRx.first(c) != nil) {
            let techniques: [(NoteRx, String)] = [(gaRx, "ga"), (neuraxialRx, "neuraxial"), (macRx, "mac"), (regionalRx, "regional")]
            for (rx, id) in techniques {
                guard let m = rx.first(c), !negated(c, at: m.range.location),
                      let f = PatientCatalog.anesthetics.first(where: { $0.id == id }) else { continue }
                h.add(PatientNoteFinding(id: "anesthetic:" + id, section: Part.procedure, label: "Planned anesthetic: " + f.label.lowercased(), change: .anesthetic(id)), at: m.range)
            }
        }
        if let m = asaRx.first(c), let g = m.text(1, in: c) {
            let roman = ["I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6]
            let n = roman[g] ?? Int(g) ?? 0
            let e = m.text(2, in: c) != nil
            if n >= 1 && n <= 6 {
                h.add(PatientNoteFinding(id: "asa", section: Part.assessment, label: "ASA " + PatientRules.roman(n) + (e ? "E" : ""), change: .asa(n, e)), at: m.range)
            }
        }
    }

    // MARK: Smoking, medicines and allergies

    static let smokeNeverRx = NoteRx(#"\b(?:never smok|non-?smok|lifelong non-?smok|denies (?:smoking|tobacco|cigarettes)|no (?:tobacco|smoking|cigarettes)\b|never used tobacco)"#)
    static let smokeFormerRx = NoteRx(#"\b(?:former|ex-?|previous|past|remote|quit) ?smok|\bquit (?:smoking|tobacco|cigarettes)|no longer smokes|stopped smoking"#)
    static let smokeCurrentRx = NoteRx(#"\b(?:current|active|daily) (?:smoker|smoking|tobacco|cigarette)|\bsmokes\b|\bsmoker\b|\bvap(?:es|ing)\b|\b\d+(?:\.\d+)? ?(?:ppd|packs? (?:a|per) day|cigarettes (?:a|per) day)"#)
    static let medsHeaderRx = NoteRx(#"^\s*(?:home meds|home medications|current meds|current medications|medications|meds|medication list|med list)\s*(?:include|includes|are|:|-|–)?\s+(.+)|\b(?:home meds|home medications|current meds|current medications|medications|meds|medication list|med list)\s*(?:include|includes|are|:|-|–)\s*(.+)"#)
    static let aspirinDoseRx = NoteRx(#"(?-i:\bASA\b)\s*(?:81|325)\b"#)
    static let allergyCue = NoteRx(#"allerg|intoleran|reaction to|(?-i:\bNKDA\b)"#)
    static let nkdaRx = NoteRx(#"\bnkda\b|(?-i:\bNKA\b)|no known (?:drug )?allergies|no (?:drug )?allergies|denies (?:any )?(?:drug )?allergies|allergies\s*:?\s*(?:none|nil|nkda|nka|no known)\b"#)
    static let allergyRx = NoteRx(#"^\s*(?:drug )?allergies\s*(?::|-|–|include|includes|are)?\s*(.+)|\b(?:allergies|allergy)\s*(?:to|include|includes|are|:|-|–)\s*(.+)|\ballergic to\s+(.+)"#)
    static let allergyAfterRx = NoteRx(#"\b([a-z][a-z0-9/-]*(?:\s+[a-z][a-z0-9/-]*){0,3})\s+allerg(?:y|ies|ic)\b"#)
    static let allergySkipRx = NoteRx(#"\b(?:no|denies|seasonal|environmental|drug|known|food)\b"#)
    /// Where a dictated allergy runs into the next topic ("penicillin last ate at 8 pm").
    static let allergyCut = NoteRx(#"\s+(?:last|npo|bp|hr|meds|medications|plan|mallampati|airway|labs?|no|denies|takes|on|for|and (?:has|is|takes))\b.*$"#)
    static let noneRx = NoteRx(#"^(?:none|nil|no|nka|nkda|denies|unknown)\b"#)
    private static let allergyLead: Set<String> = ["has", "have", "with", "known", "a", "an", "severe", "the", "pt", "patient", "is", "reports",
                                                   "reported", "documented", "listed", "she", "he", "they", "states", "that", "mild", "possible",
                                                   "history", "of", "hx", "and", "also"]

    private static func readMeds(_ c: String, _ h: inout Hits, names: inout [String], header: Bool = true) {
        if let m = smokeNeverRx.first(c) {
            h.add(PatientNoteFinding(id: "smoking", section: Part.history, label: "Smoking: never", change: .smoking("never")), at: m.range)
        } else if let m = smokeFormerRx.first(c) {
            h.add(PatientNoteFinding(id: "smoking", section: Part.history, label: "Smoking: former", change: .smoking("former")), at: m.range)
        } else if let m = smokeCurrentRx.first(c), !negated(c, at: m.range.location) {
            h.add(PatientNoteFinding(id: "smoking", section: Part.history, label: "Smoking: current", change: .smoking("current")), at: m.range)
        }

        // Medicine names in an allergy sentence are allergies, not medicines.
        let allergySentence = allergyCue.first(c) != nil
        if header, !allergySentence, let m = medsHeaderRx.first(c), let raw = m.text([1, 2], in: c) {
            let list = raw.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;"))
            if !list.isEmpty {
                h.add(PatientNoteFinding(id: "meds", section: Part.meds, label: "Medication list: " + list, change: .medications(list)), at: m.range)
            }
        }
        for m in drugRx.all(c) {
            h.seen(m.range)
            guard !allergySentence, let raw = m.text(1, in: c) else { continue }
            let key = raw.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            // A medicine running as an infusion is listed as the infusion.
            let infused = h.infusions.contains { NSIntersectionRange($0, m.range).length > 0 }
            if !infused && !names.contains(key) { names.append(key) }
            guard let flag = drugs[key], !flag.isEmpty, !negated(c, at: m.range.location),
                  let f = PatientCatalog.medFlags.first(where: { $0.id == flag }) else { continue }
            h.add(PatientNoteFinding(id: "flag:" + flag, section: Part.meds, label: "Takes: " + f.label.lowercased(), change: .medFlag(flag)), at: m.range)
        }
        // Drug classes ("on a beta-blocker"; "DOAC" read as direct oral anticoagulant).
        for (rx, flag) in drugClasses where !allergySentence {
            guard let m = rx.first(c), !negated(c, at: m.range.location), let f = PatientCatalog.medFlags.first(where: { $0.id == flag }) else { continue }
            h.add(PatientNoteFinding(id: "flag:" + flag, section: Part.meds, label: "Takes: " + f.label.lowercased(), change: .medFlag(flag)), at: m.range)
        }
        // "ASA 81" is aspirin; "ASA III" is the physical status.
        if !allergySentence, let m = aspirinDoseRx.first(c) {
            if !names.contains("aspirin") { names.append("aspirin") }
            h.add(PatientNoteFinding(id: "flag:aspirin", section: Part.meds, label: "Takes: aspirin", change: .medFlag("aspirin")), at: m.range)
        }
    }

    /// Infusions running: added to Current infusions with their rate ("Norepinephrine", "0.05 mcg/kg/min").
    private static func readInfusions(_ c: String, _ h: inout Hits) {
        for m in infusionRx.all(c) {
            h.infusions.append(m.range)
            let before = (c as NSString).substring(to: m.range.location)
            guard let drug = m.text(1, in: c)?.lowercased(), !negated(c, at: m.range.location), offCue.first(before) == nil else {
                h.seen(m.range)
                continue
            }
            var rate = m.text([2, 4], in: c) ?? ""
            if let unit = m.text([3, 5], in: c) { rate += " " + unit.replacingOccurrences(of: " ", with: "") }
            h.add(PatientNoteFinding(id: "infusion:" + drug, section: Part.meds, label: "Infusion: " + drug + (rate.isEmpty ? "" : " at " + rate),
                                     change: .infusion(drug, rate)), at: m.range)
        }
    }

    private static func readAllergies(_ c: String, _ h: inout Hits) {
        if let m = nkdaRx.first(c) {
            h.add(PatientNoteFinding(id: "nkda", section: Part.meds, label: "No known drug allergies", change: .nkda), at: m.range)
            for m2 in allergyRx.all(c) where NSIntersectionRange(m2.range, m.range).length == 0 {
                if let raw = m2.text([1, 2, 3], in: c) { allergy(raw, m2.range, &h) }
                break
            }
            return
        }
        if let m = allergyRx.first(c), let raw = m.text([1, 2, 3], in: c) {
            allergy(raw, m.range, &h)
            return
        }
        if let m = allergyAfterRx.first(c), let raw = m.text(1, in: c) {
            var words = raw.split(separator: " ").map(String.init)
            while let w = words.first, allergyLead.contains(w.lowercased()) { words.removeFirst() }
            let a = words.joined(separator: " ")
            if a.count >= 2, allergySkipRx.first(a) == nil {
                allergy(a, m.range, &h)
            } else {
                h.seen(m.range)
            }
        }
    }

    private static func allergy(_ raw: String, _ r: NSRange, _ h: inout Hits) {
        var t = raw
        if let cut = allergyCut.first(t) { t = (t as NSString).substring(to: cut.range.location) }
        let a = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;"))
        guard a.count >= 2, noneRx.first(a) == nil else {
            h.seen(r)
            return
        }
        h.add(PatientNoteFinding(id: "allergies:" + a.lowercased(), section: Part.meds, label: "Allergies: " + a, change: .allergies(a)), at: r)
    }

    // MARK: Vital signs and labs

    static let bpRx = NoteRx(#"\b(?:bp|blood pressure|nibp)\s*(?:of|is|was|:|=)?\s*(\d{2,3})\s*/\s*(\d{2,3})"#)
    static let hrRx = NoteRx(#"\b(?:hr|heart rate|pulse)\s*(?:of|is|was|:|=)?\s*(\d{2,3})\b"#)
    static let spo2Rx = NoteRx(#"\b(?:spo2|spo₂|sats?|saturation|saturating|o2 sat|sao2|pulse ox)\s*(?:of|is|was|:|=)?\s*(\d{2,3})\s*%?"#)
    /// A mixed venous, central venous or cerebral saturation is not the SpO₂.
    static let venousSatBefore = NoteRx(#"\b(?:venous|mixed|cerebral|central|regional|tissue|fetal|svo2|scvo2|rso2|nirs)\s*(?:o2\s*)?$"#)
    static let venousSatAfter = NoteRx(#"^\s*%?\s*[(,]?\s*(?:mixed venous|venous|central venous|svo2|scvo2|cerebral|rso2|nirs|fetal)\b"#)
    static let roomAirAfter = NoteRx(#"^\s*%?\s*(?:on\s+)?(?:room air|ra)\b"#)
    static let roomAirWords = NoteRx(#"\broom air\b"#)

    // MARK: Questions

    /// The question a saturation with no room air written is asked; the answer is kept in the reader's choices.
    static let roomAirQuestion = "quick:spo2"
    static let roomAirAnswer = "spo2-room-air"
    static let oxygenAnswer = "spo2-oxygen"
    /// The note of a saturation read with no room air written, until it is asked about.
    static let roomAirUnstated = "Room air not written."

    /// The answer kept for a question, when it was given for this value: the quick-add bar keeps the value with it
    /// (under the id + "@value") and asks again when the value changes.
    static func answer(_ id: String, value: String, _ choices: [String: String]) -> String? {
        guard let a = choices[id] else { return nil }
        if let tied = choices[id + "@value"], tied != value { return nil }
        return a
    }

    /// A question shown as an ambiguous abbreviation is: nothing is read from it until it is answered. Unanswered, its
    /// chosen meaning is "as written" and `fromContext` is false; answered (left out included), `fromContext` is true.
    static func question(_ id: String, _ label: String, value: String, options: [AbbreviationMeaning], usual: String,
                         _ choices: [String: String]) -> (question: AmbiguousAbbreviation, answer: String?) {
        let a = answer(id, value: value, choices)
        var q = AmbiguousAbbreviation(id: id, abbreviation: label, options: options, defaultID: usual, fromContext: a != nil,
                                      chosenID: a ?? MedAbbreviations.asWritten, context: label)
        q.valueKey = value
        return (q, a)
    }

    /// "SpO₂ 95% · room air?": the field is SpO₂ on room air.
    static func roomAir(_ v: Double, _ choices: [String: String]) -> (question: AmbiguousAbbreviation, answer: String?) {
        let value = NumText.short(v)
        return question(roomAirQuestion, "SpO₂ " + value + "%", value: value,
                        options: [AbbreviationMeaning("room air", id: roomAirAnswer), AbbreviationMeaning("on oxygen", id: oxygenAnswer)],
                        usual: roomAirAnswer, choices)
    }
    static let onOxygenRx = NoteRx(#"^\s*%?\s*(?:on|with)\s+(?:\d+(?:\.\d+)?\s*(?:l\b|lpm|liters?)|o2|oxygen|nc\b|nasal cannula|bipap|cpap|hfnc|face ?mask|nrb)"#)
    static let rrRx = NoteRx(#"\b(?:rr|resp(?:iratory)? rate|resps)\s*(?:of|is|was|:|=)?\s*(\d{1,2})\b"#)
    static let tempRx = NoteRx(#"\b(?:temp|temperature|(?-i:T))\s*(?:of|is|was|:|=)?\s*(\d{2,3}(?:\.\d)?)\s*°?\s*([cf])?\b"#)
    static let efRx = NoteRx(#"\b(?:ef|lvef|ejection fraction)\s*(?:of|is|was|:|=|~|<|>|≤|≥)?\s*(\d{1,2})\s*(?:-|–|to)?\s*(\d{1,2})?\s*%"#)
    private static let value = #"(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)"#
    /// A trend's next value ("→ 1.6", "-> 7.8", "then 7.1", "now 1.6"), and what after it makes it a dose or blood.
    static let labTrend = NoteRx(#"^[\s,)\]]*(?:-+>|→|⟶|➝|=>|\bto\b|\bthen\b)\s*(\d+(?:\.\d+)?)(?!\d|\.\d|\s*/\s*\d)"#)
    /// After a value: only punctuation or the end, so it is the last word. Brackets never hide a mark.
    static let labEnd = NoteRx(#"^[\s)\]]*(?:[,;.]|$)"#)
    /// The words that mark a value earlier ("baseline", "on admit", "last month", "old") or current ("now"), after it,
    /// in brackets or not: "Cr 1.1 (baseline), now 1.6", "K 3.1 on admit", "Cr 1.1 last month".
    static let earlierWords = #"(?:baseline|admission|admit|prior|previous(?:ly)?|earlier|before|old|yesterday|last\s+(?:month|week|year|visit|admission|wk|mo|yr)|(?:\d+|a|an|one|two|three|few|several)\s*(?:days?|d|wks?|weeks?|mos?|months?|yrs?|years?)\s+ago|pre-?op(?:eratively)?)"#
    static let labEarlierAfter = NoteRx(#"^[\s(\[]*(?:(?:at|on|from|in)\s+)?"# + earlierWords + #"\b[\s)\]]*"#)
    static let labCurrentAfter = NoteRx(#"^[\s(\[]*(?:now|current(?:ly)?|latest|today|new|repeat)\b(?![\s:]*[-−]?\d)[\s)\]]*"#)
    /// Marked current right before the test's name ("Now Hb 8.2"), or preoperative ("Preop Hb 12.1").
    static let labCurrentBefore = NoteRx(#"\b(?:now|current(?:ly)?|latest|today|repeat|new)[\s:()\[\]]*$"#)
    static let labPreop = NoteRx(#"\b(?:pre-?op(?:erative)?|preoperative)[\s:()\[\]]*$"#)
    /// A goal or a threshold, not a value ("goal Hb 8 to 10", "transfuse for Hb 7").
    static let labGoal = NoteRx(#"\b(?:goal|target|keep|maintain|threshold|trigger|transfuse\s+(?:for|if|to|at|when))\b[^,;]*$"#)
    static let labTrendStop = NoteRx(#"^\s*(?:[x×]\s?\d|runs?\b|amps?\b|ampules?\b|vials?\b|units?\b|u\b|mg\b|mcg\b|g\b|gm\b|meq\b|ml\b|cc\b|iv\b|im\b|po\b|prbcs?\b|rbcs?\b|ffp\b|plasma\b|plts?\b|platelets?\b|cryo\w*|whole blood|packed|bags?\b|doses?\b|tabs?\b)"#)
    /// Marked as earlier right before the test's name, and the current value that follows.
    static let labEarlier = NoteRx(#"\b(?:baseline|prior|previous(?:ly)?|admission|admit|initial|outside|osh|historical|(?<!year )(?<!years )(?<!yr )(?<!-)old|yesterday(?:'s)?|last\s+(?:month|week|year|wk|mo|yr)(?:'s)?|(?:\d+|a|an|one|two|three|few|several)\s*(?:days?|d|wks?|weeks?|mos?|months?|yrs?|years?)\s+ago)[\s:()\[\]]*$"#)
    static let labNow = NoteRx(#"^[\s,;()\[\]]*(?:now|currently|current|today|repeat|latest|new)\b[\s:()\[\]]*(\d+(?:\.\d+)?)(?!\d|\.\d|\s*/\s*\d)"#)
    static let hemolyzedRx = NoteRx(#"\bh(?:a)?emoly[sz](?:ed|is)\b"#)
    private static let labRules: [(id: String, rx: NoteRx, min: Double, max: Double)] = [
        ("hb", NoteRx(#"\b(?:hb|hgb|hbg|hemoglobin|haemoglobin)\s*(?:of|is|was|:|=)?\s*(\d{1,2}(?:\.\d)?)\b"#), 3, 25),
        ("plt", NoteRx(#"\b(?:plt|plts|platelets?)\s*(?:of|is|was|:|=)?\s*"# + value + #"\s*k?\b"#), 5, 2000),
        ("inr", NoteRx(#"\binr\s*(?:of|is|was|:|=)?\s*(\d(?:\.\d{1,2})?)\b"#), 0.5, 15),
        ("k", NoteRx(#"(?-i:\bK\+?)\s*(?:of|is|was|:|=)?\s*(\d(?:\.\d)?)\b|\bpotassium\s*(?:of|is|was|:|=)?\s*(\d(?:\.\d)?)\b"#), 1.5, 9),
        ("na", NoteRx(#"(?-i:\bNa\+?)\s*(?:of|is|was|:|=)?\s*(\d{3})\b|\bsodium\s*(?:of|is|was|:|=)?\s*(\d{3})\b"#), 100, 180),
        ("cr", NoteRx(#"\b(?:cr|creat|creatinine|scr)\s*(?:of|is|was|:|=)?\s*(\d{1,2}(?:\.\d{1,2})?)\b"#), 0.1, 20),
        ("glucose", NoteRx(#"\b(?:glucose|bg|bgl|blood sugar|blood glucose|fsbg|fsbs|poc glucose|cbg)\s*(?:of|is|was|:|=)?\s*(\d{2,4})\b"#), 20, 1500),
        ("a1c", NoteRx(#"\b(?:a1c|hba1c|hgba1c|hemoglobin a1c)\s*(?:of|is|was|:|=)?\s*(\d{1,2}(?:\.\d)?)\s*%?"#), 3, 20),
        ("ntprobnp", NoteRx(#"\bnt[- ]?pro[- ]?bnp\s*(?:of|is|was|:|=)?\s*"# + value), 1, 100_000),
        ("bnp", NoteRx(#"(?<![a-z-])bnp\s*(?:of|is|was|:|=)?\s*"# + value), 1, 50_000),
    ]

    private static func readNumbers(_ c: String, _ h: inout Hits, _ choices: [String: String]) {
        if let m = bpRx.first(c), let s = number(m, [1], c), let d = number(m, [2], c) {
            vital("sbp", s, 50, 260, m.range, &h)
            vital("dbp", d, 20, 160, m.range, &h)
        }
        if let m = hrRx.first(c), let v = number(m, [1], c) { vital("hr", v, 20, 220, m.range, &h) }
        if let m = spo2Rx.first(c), let v = number(m, [1], c) {
            let after = (c as NSString).substring(from: m.range.location + m.range.length)
            // A mixed venous, central venous or cerebral saturation, named before or after the number, is not the SpO₂.
            if venousSatBefore.first((c as NSString).substring(to: m.range.location)) == nil, venousSatAfter.first(after) == nil {
                let o2 = onOxygenRx.first(after) != nil
                let air = roomAirAfter.first(after) != nil || roomAirWords.first(c) != nil
                vital("spo2", v, 50, 100, m.range, &h, note: o2 ? "The note gives it on oxygen; this field is SpO₂ on room air." : (air ? nil : roomAirUnstated))
            } else {
                h.seen(m.range)
            }
        }
        if let m = rrRx.first(c), let v = number(m, [1], c) { vital("rr", v, 4, 60, m.range, &h) }
        if let m = tempRx.first(c), var v = number(m, [1], c) {
            if m.text(2, in: c)?.lowercased() == "f" || v > 45 { v = ((v - 32) * 5 / 9 * 10).rounded() / 10 }
            vital("temp", v, 30, 43, m.range, &h)
        }
        for l in labRules {
            let ns = c as NSString
            func cut(_ s: String, _ n: Int) -> String { (s as NSString).substring(from: n) }
            // Every value written for the test in the clause, each mention with its marks before and after it
            // ("baseline", "at baseline", "now") and the values after it, current when nothing but punctuation follows
            // ("Cr 0.9 → 1.6", "Cr 0.9 to 1.6").
            var values: [(v: Double, current: Bool, earlier: Bool, strong: Bool)] = []
            var ranges: [NSRange] = []
            for m in l.rx.all(c) {
                guard let first = number(m, [1, 2], c) else { continue }
                let before = ns.substring(to: m.range.location)
                // A goal or a threshold ("goal Hb 8 to 10") is no value.
                if labGoal.first(before) != nil {
                    h.seen(m.range)
                    continue
                }
                var r = m.range
                let strong = labEarlier.first(before) != nil
                var rest = cut(c, m.range.location + m.range.length)
                values.append((first, labCurrentBefore.first(before) != nil, strong || labPreop.first(before) != nil, strong))
                while true {
                    // Marks after the last value: "(baseline)", "on admit", "last month" (earlier); "now" (current).
                    let last = values.count - 1
                    if let e = labEarlierAfter.first(rest) {
                        let word = (rest as NSString).substring(with: e.range).lowercased()
                        values[last].earlier = true
                        if !word.contains("preop") && !word.contains("pre-op") { values[last].strong = true }
                        r.length += e.range.length
                        rest = cut(rest, e.range.length)
                    }
                    if let n = labCurrentAfter.first(rest) {
                        values[last].current = true
                        r.length += n.range.length
                        rest = cut(rest, n.range.length)
                    }
                    let step: NSTextCheckingResult
                    if let t = labNow.first(rest), let v = number(t, [1], rest) {
                        values.append((v, true, false, false))
                        step = t
                    } else if let t = labTrend.first(rest), let v = number(t, [1], rest) {
                        let after = cut(rest, t.range.location + t.range.length)
                        // Never a dose or blood after it ("then 2 PRBC", "then 4 runs").
                        if labTrendStop.first(after) != nil { break }
                        values.append((v, labEnd.first(after) != nil, false, false))
                        step = t
                    } else {
                        break
                    }
                    r.length += step.range.length
                    rest = cut(rest, step.range.length)
                }
                ranges.append(r)
            }
            guard let at = ranges.first else { continue }
            func seenAll() { for r in ranges { h.seen(r) } }
            // One value: filed, unless marked earlier ("baseline Cr 1.1"; "preop Hb 12.1" is filed as earlier, for
            // another sentence's newer value to replace). Two or more: the one marked current, if exactly one is;
            // otherwise asked ("Cr: 1.1 or 1.6?").
            var distinct: [Double] = []
            for x in values where !distinct.contains(x.v) { distinct.append(x.v) }
            var current: [Double] = []
            for x in values where x.current && !x.earlier && !current.contains(x.v) { current.append(x.v) }
            var v: Double
            var flag = (current: false, earlier: false)
            if values.allSatisfy({ $0.earlier }) {
                guard let weak = values.last(where: { !$0.strong }), distinct.count == 1 || values.allSatisfy({ !$0.strong }) else {
                    seenAll()
                    continue
                }
                v = weak.v
                flag.earlier = true
            } else if distinct.count == 1 {
                v = distinct[0]
                flag.current = !current.isEmpty
            } else if current.count == 1 {
                v = current[0]
                flag.current = true
            } else {
                let asked = labChoice(l.id, distinct, choices)
                h.questions.append(asked.question)
                guard let chosen = asked.value else {
                    seenAll()
                    continue
                }
                v = chosen
                flag.current = true
            }
            if l.id == "plt" && v >= 2000 { v /= 1000 }
            guard v >= l.min, v <= l.max, PatientCatalog.labs.contains(where: { $0.id == l.id }) else {
                seenAll()
                continue
            }
            // A hemolyzed sample's potassium may be falsely high.
            let note = l.id == "k" && hemolyzedRx.first(c) != nil ? "Hemolyzed: may be falsely high." : nil
            h.add(PatientNoteFinding(id: "lab:" + l.id, section: Part.labs, label: labLabel(l.id, v), change: .lab(l.id, v), note: note), at: at)
            for r in ranges.dropFirst() { h.seen(r) }
            h.labFlags["lab:" + l.id] = flag
        }
    }

    /// "Hemoglobin 9.1 g/dL": a lab finding's label.
    static func labLabel(_ id: String, _ v: Double) -> String {
        guard let f = PatientCatalog.labs.first(where: { $0.id == id }) else { return id + " " + NumText.short(v) }
        let text = PatientLabs.test(id)?.format(v) ?? NumText.short(v)
        return f.label + " " + text + (f.unit.isEmpty ? "" : (f.unit == "%" ? "%" : " " + f.unit))
    }

    /// Two values of a test, neither marked current: "Cr: 0.9 or 1.6?", nothing read until one is chosen.
    static let labQuestionPrefix = "quick:lab:"

    static func labChoice(_ key: String, _ values: [Double], _ choices: [String: String]) -> (question: AmbiguousAbbreviation, value: Double?) {
        let texts = values.map { NumText.short($0) }
        let options = texts.map { AbbreviationMeaning($0, id: "lab-" + $0) }
        let asked = question(labQuestionPrefix + key, PatientLabs.test(key)?.short ?? key, value: texts.joined(separator: ","), options: options,
                             usual: options.last?.id ?? "", choices)
        return (asked.question, asked.answer.flatMap { a in values.first { "lab-" + NumText.short($0) == a } })
    }

    private static func vital(_ key: String, _ v: Double, _ lo: Double, _ hi: Double, _ r: NSRange, _ h: inout Hits, note: String? = nil) {
        guard v >= lo, v <= hi, let f = PatientCatalog.vitals.first(where: { $0.id == key }) else {
            h.seen(r)
            return
        }
        let unit = f.unit.hasPrefix("/") || f.unit == "%" ? f.unit : " " + f.unit
        h.add(PatientNoteFinding(id: "vital:" + key, section: Part.vitals, label: f.label + " " + NumText.short(v) + unit, change: .vital(key, v), note: note), at: r)
    }

    // MARK: Assessment, airway and fasting

    static let npoMidnightRx = NoteRx(#"\b(?:npo|nil by mouth|nothing (?:to eat|by mouth)|fasting|fasted)\s*(?:after|since|from|at|past|>)\s*(?:midnight|mn|12 ?am|0000|00:00)\b"#)
    static let lastAteRx = NoteRx(#"\blast (?:ate|meal|food|solids?|ate solids|solid food|light meal)\s*(?:at|was at|was|:|~|around|about)?\s*(\d{1,4})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?"#)
    static let lastDrankRx = NoteRx(#"\blast (?:drank|drink|clears?|clear fluids?|clear liquids?|fluids?|sip|water|po fluids?)\s*(?:at|was at|was|:|~|around|about)?\s*(\d{1,4})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?"#)
    static let metsUnknownRx = NoteRx(#"(?:exercise|functional) (?:tolerance|capacity) (?:is )?(?:unknown|unclear|not assessable|unable to be assessed|cannot be assessed)|unable to assess (?:exercise|functional)"#)
    static let metsPoorRx = NoteRx(#"\b(?:unable to|can't|cannot|can not|could not|couldn't|not able to|has difficulty|difficulty|struggles to)\s+(?:climb|climbing|walk up|walking up|do|manage)\s+(?:a\s+|one\s+|1\s+|two\s+|2\s+)?(?:flights?|stairs|flight of stairs|steps)|(?:<|less than|under)\s*4\s*mets?\b|\bmets?\s*(?:<|under|less than)\s*4|(?:poor|limited|low|reduced|decreased) (?:exercise|functional) (?:tolerance|capacity)|\b(?:wheelchair[- ]bound|wheelchair user|bed-?bound|bedridden|housebound|uses a walker|non-?ambulatory)\b"#)
    static let metsGoodRx = NoteRx(#"\b(?:can|able to|could|does|climbs?|walks? up|goes up)\s+(?:climb\s+|walk up\s+|do\s+)?(?:two|2|three|3|four|4|several|multiple|a couple of|a few)\s+(?:flights?|flight of stairs)|(?:>|more than|over|at least|≥|greater than)\s*4\s*mets?\b|\bmets?\s*(?:>|≥|over|more than|at least)\s*4|good (?:exercise|functional) (?:tolerance|capacity)|\b(?:jogs|plays (?:tennis|basketball|soccer|squash)|swims laps|runs (?:regularly|daily|for exercise|marathons|\d+ (?:miles|km)))\b"#)
    static let metsNumberRx = NoteRx(#"\b(\d{1,2}(?:\.\d)?)\s*mets?\b"#)
    static let frailRx = NoteRx(#"\bfrail\b|\bfrailty\b(?!\s+(?:scale|score|assessment|screen|index))|(?:clinical frailty scale|(?-i:CFS))\s*(?:of|is|:|=)?\s*[5-9]\b"#)
    static let mallampatiRx = NoteRx(#"\b(?:mallampati|(?-i:MP))\s*(?:class|score|grade)?\s*:?\s*(iv|iii|ii|i|[1-4])\b"#)
    static let dentitionRx = NoteRx(#"\b(?:dentures?|partial (?:plate|denture)|bridge(?:work)?|caps|crowns?|veneers|dental implants?|loose (?:tooth|teeth)|chipped (?:tooth|teeth)|poor dentition|missing (?:tooth|teeth)|broken (?:tooth|teeth))\b"#)

    private static func readAssessment(_ c: String, now: Date, _ h: inout Hits) {
        if let m = metsUnknownRx.first(c) {
            h.add(PatientNoteFinding(id: "mets", section: Part.assessment, label: "Functional capacity: unknown", change: .mets("unknown")), at: m.range)
        } else if let m = metsPoorRx.first(c) {
            h.add(PatientNoteFinding(id: "mets", section: Part.assessment, label: "Functional capacity: under 4 METs", change: .mets("lt4")), at: m.range)
        } else if let m = metsGoodRx.first(c), !negated(c, at: m.range.location) {
            h.add(PatientNoteFinding(id: "mets", section: Part.assessment, label: "Functional capacity: 4 METs or more", change: .mets("ge4")), at: m.range)
        } else if let m = metsNumberRx.first(c), let v = number(m, [1], c) {
            let good = v >= 4
            h.add(PatientNoteFinding(id: "mets", section: Part.assessment, label: "Functional capacity: " + (good ? "4 METs or more" : "under 4 METs"), change: .mets(good ? "ge4" : "lt4")), at: m.range)
        }
        if let m = frailRx.first(c) {
            if negated(c, at: m.range.location) {
                h.seen(m.range)
            } else {
                h.add(PatientNoteFinding(id: "frail", section: Part.assessment, label: "Frail", change: .frail), at: m.range)
            }
        }
        let grades = ["i": 1, "ii": 2, "iii": 3, "iv": 4, "1": 1, "2": 2, "3": 3, "4": 4]
        if let m = mallampatiRx.first(c), let g = m.text(1, in: c)?.lowercased(), let n = grades[g] {
            h.add(PatientNoteFinding(id: "mallampati", section: Part.airway, label: "Mallampati " + PatientRules.roman(n), change: .mallampati(n)), at: m.range)
        }
        if let m = dentitionRx.first(c) {
            if negated(c, at: m.range.location) {
                h.seen(m.range)
            } else {
                let t = piece(around: m.range, in: c)
                h.add(PatientNoteFinding(id: "dentition", section: Part.airway, label: "Teeth: " + t, change: .dentition(t)), at: m.range)
            }
        }
        if let cs = PatientCodeStatus.read(c), let first = cs.ranges.first {
            h.add(PatientCodeStatus.finding(cs.status, polst: cs.polst, plan: cs.plan), at: first)
            for r in cs.ranges.dropFirst() { h.seen(r) }
        }
        if let m = npoMidnightRx.first(c) {
            let midnight = PatientRecord.npoMidnight(now)
            h.add(PatientNoteFinding(id: "intake:solids", section: Part.intake, label: "Solids: midnight", change: .lastSolids(midnight)), at: m.range)
            h.add(PatientNoteFinding(id: "intake:clears", section: Part.intake, label: "Clear fluids: midnight", change: .lastClears(midnight)), at: m.range)
        }
        if let m = lastAteRx.first(c), let digits = m.text(1, in: c), let d = clock(digits, m.text(2, in: c), m.text(3, in: c), now: now) {
            h.add(PatientNoteFinding(id: "intake:solids", section: Part.intake, label: "Solids: " + PatientSummary.time(d, now: now), change: .lastSolids(d)), at: m.range)
        }
        if let m = lastDrankRx.first(c), let digits = m.text(1, in: c), let d = clock(digits, m.text(2, in: c), m.text(3, in: c), now: now) {
            h.add(PatientNoteFinding(id: "intake:clears", section: Part.intake, label: "Clear fluids: " + PatientSummary.time(d, now: now), change: .lastClears(d)), at: m.range)
        }
    }

    /// The most recent past time a clock reading names: "7 pm" read at 8 am is yesterday evening, "0530" is 05:30.
    /// An hour from 1 to 11 with no am or pm and no leading zero could be either half of the day: the more recent.
    static func clock(_ digits: String, _ minutes: String?, _ ampm: String?, now: Date) -> Date? {
        guard let n = Int(digits) else { return nil }
        var hour = n
        var minute = minutes.flatMap { Int($0) } ?? 0
        if minutes == nil && digits.count >= 3 {
            hour = n / 100
            minute = n % 100
        }
        let ap = ampm?.lowercased().replacingOccurrences(of: ".", with: "")
        if ap == "pm" && hour < 12 { hour += 12 }
        if ap == "am" && hour == 12 { hour = 0 }
        guard hour < 24, minute < 60, let best = latest(hour, minute, now: now) else { return nil }
        if ap == nil && hour >= 1 && hour < 12 && !digits.hasPrefix("0") && digits.count <= 2,
           let evening = latest(hour + 12, minute, now: now), evening > best {
            return evening
        }
        return best
    }

    /// The latest time at or before `now` with this hour and minute.
    private static func latest(_ hour: Int, _ minute: Int, now: Date) -> Date? {
        let cal = Calendar.current
        guard let d = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        return d > now ? cal.date(byAdding: .day, value: -1, to: d) : d
    }

    /// The comma-separated part of a sentence around a match ("upper partial denture" from "MP 3, upper partial denture").
    private static func piece(around r: NSRange, in c: String) -> String {
        let ns = c as NSString
        let stops = CharacterSet(charactersIn: ",;")
        var start = r.location
        var end = r.location + r.length
        while start > 0, let u = UnicodeScalar(ns.character(at: start - 1)), !stops.contains(u) { start -= 1 }
        while end < ns.length, let u = UnicodeScalar(ns.character(at: end)), !stops.contains(u) { end += 1 }
        return ns.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Leftovers

    static let pieceBreak = NoteRx(#"\s*(?:,|\+|&|\band\b|\bwith\b|\bbut\b|\bplus\b|\balso\b)\s*"#)
    static let headerLead = NoteRx(#"^\s*(?:(?:pmhx?|pshx?|hpi|hx|history|past (?:medical|surgical) history|surgical history|medical history|ros|social history|sh|fhx?|family history|physical exam|exam|pe|plan|assessment|a/p|other|significant for|notable for|known|history of|hx of|h/o)\b\s*[:\-–]?\s*)+"#)
    static let negLead = NoteRx(#"^\s*(?:no|not|denies|denied|negative(?: for)?|without|never|nil|none)\b"#)
    private static let fillers: Set<String> = [
        "pt", "patient", "presents", "presenting", "presented", "here", "today", "who", "has", "have", "had", "is", "a", "an", "the", "for",
        "of", "on", "in", "at", "to", "also", "history", "hx", "pmh", "significant", "notable", "known", "otherwise", "and", "with", "but",
        "s/p", "status", "post", "he", "she", "they", "his", "her", "their", "year", "years", "old", "yo", "y/o", "male", "female", "man",
        "woman", "now", "currently", "recently", "well", "stable", "good", "normal", "fine", "ok", "none", "nil", "plan", "afebrile", "nad",
        "wnl", "unremarkable", "benign", "clear", "rrr", "ctab", "soft", "intact", "alert", "oriented", "comfortable", "exam", "vitals",
        "labs", "meds", "medications", "allergies", "airway", "per", "was", "were", "be", "been", "that", "this", "which", "from", "by",
        "admitted", "reports", "states", "notes", "noted", "found", "seen", "since", "ago", "days", "weeks", "months", "prior", "recent",
        "mother", "father", "brother", "sister", "sibling", "siblings", "parent", "parents", "grandmother", "grandfather", "aunt", "uncle",
        "family", "fhx",
    ]

    /// The parts of a sentence nothing was read from: split at commas and joining words, headings dropped, negatives
    /// and filler left out.
    private static func leftovers(_ c: String, _ used: [NSRange], keepNegatives: Bool = false) -> [(text: String, range: NSRange)] {
        let ns = c as NSString
        var pieces: [NSRange] = []
        var start = 0
        for cut in pieceBreak.all(c) {
            if cut.range.location > start { pieces.append(NSRange(location: start, length: cut.range.location - start)) }
            start = cut.range.location + cut.range.length
        }
        if start < ns.length { pieces.append(NSRange(location: start, length: ns.length - start)) }
        var out: [(text: String, range: NSRange)] = []
        for p in pieces where !used.contains(where: { NSIntersectionRange($0, p).length > 0 }) {
            var t = ns.substring(with: p)
            if let head = headerLead.first(t) { t = (t as NSString).substring(from: head.range.location + head.range.length) }
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: " :;,.-–"))
            if !keepNegatives && negLead.first(t) != nil { continue }
            let words = t.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "/" }).map(String.init)
            guard words.contains(where: { $0.count >= 3 && !fillers.contains($0) && $0.contains(where: { $0.isLetter }) }) else { continue }
            out.append((t, p))
        }
        return out
    }

    // MARK: Identifiers

    /// Words after "Patient" or "Pt" that begin a sentence about the patient, not a name.
    static let headerStop = #"(?:is|was|has|had|a|an|the|with|presents?|presented|presenting|and|who|will|did|does|not|no|in|on|for|to|of|here|being|now|states?|stated|reports?|reported|denies|denied|underwent|tolerated|agrees|agreed|plan|he|she|they|we|this|it|seen|consented)"#
    static let identifierRules: [(String, NoteRx)] = [
        ("a record number", NoteRx(#"\b(?:mrn|medical record|record (?:no|number|#)|patient id|acct|account (?:no|number)|nhs (?:no|number)|ssn|social security)\b|\b\d{7,}\b"#)),
        ("a date", NoteRx(#"\b(?:dob|d\.o\.b|date of birth|born on)\b|\b\d{1,2}[/.-]\d{1,2}[/.-](?:19|20)\d{2}\b"#)),
        // After "born", through the year (or to the end of the clause); and any date with a day in it ("04-Mar-1950",
        // "1950-03-04", "March 4 1950").
        ("a date", NoteRx(#"\bborn\b[^\n.;]*?(?:\b(?:19|20)\d{2}\b|(?=[\n.;]|$))|\b(?:19|20)\d{2}-\d{1,2}-\d{1,2}\b|\b\d{1,2}(?:st|nd|rd|th)?(?:\s+of)?[\s/.-]+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?[\s/.,-]+(?:19|20)\d{2}\b|\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?[\s/.-]+\d{1,2}(?:st|nd|rd|th)?[\s/.,-]+(?:19|20)\d{2}\b"#)),
        // A date with the month in words ("born 4 March 1950", "March 4, 1950").
        ("a date", NoteRx(#"\b\d{1,2}(?:st|nd|rd|th)?\s+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?,?\s+(?:19|20)\d{2}\b|\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+\d{1,2}(?:st|nd|rd|th)?,?\s+(?:19|20)\d{2}\b"#)),
        ("a name", NoteRx(#"\b(?:Mr|Mrs|Ms|Miss|Mx)\.?\s+[A-Z][A-Za-z'’-]*[a-z][A-Za-z'’-]*"#, caseSensitive: true)),
        ("a name", NoteRx(#"\b(?:name is|named|patient name|pt name)\b|\bname\s*:"#)),
        // After a header ("Patient:", "Pt -", "Name —"; or "Patient", "Pt." or "Patient-" right before a capitalized
        // name, or one in capitals: "Pt. Jane Doe", "Patient-Jane Doe", "Patient JANE DOE"), the words that
        // follow, in any case or order ("Doe, Jane", "jane doe"), up to a number or the end of the line; never when the
        // next word is a stop word or a number ("Patient is a 68M", "Pt: 68M"). Past a comma only a capitalized name that
        // ends the line ("Doe, Jane"): "Name: Jane Doe, 68F for lap chole" and "pt name John Smith, K 5.4" still read the
        // rest. A hyphen needs a space beside it ("patient-controlled" is no header).
        ("a name", NoteRx(#"\b(?:patient|pt|name|patient name|pt name)(?:\s*(?::|\s[-–—]+|[–—]+|-+\s)[ \t]*(?!"# + headerStop + #"\b)[A-Za-z]|(?:[ \t]+|\.[ \t]*|-)(?!"# + headerStop + #"\b)(?-i:[A-Z][a-z]|[A-Z]{2,}(?=[ \t]+[A-Z]{2,})))[A-Za-z'’.-]*(?:[ \t]+[A-Za-z][A-Za-z'’.-]*){0,3}(?:,[ \t]*(?-i:[A-Z][a-z])[A-Za-z'’.-]*(?:[ \t]+(?-i:[A-Z][a-z])[A-Za-z'’.-]*)?(?=[ \t]*(?:$|[\n.;])))?"#)),
        ("a phone number", NoteRx(#"\b\d{3}[-. )]\s?\d{3}[-. ]\d{4}\b"#)),
    ]

    /// Kinds of identifier the text seems to hold, for a warning (nothing is removed automatically).
    static func identifiers(_ text: String) -> [String] {
        var out: [String] = []
        for (kind, rx) in identifierRules where !out.contains(kind) && rx.first(text) != nil { out.append(kind) }
        return out
    }

    // MARK: Airway, breathing, lines and devices

    /// A line or device the diagram knows (PatientDevices.parse reads the phrase): "PIV x2 18G", "R radial A-line",
    /// "RIJ TLC", "PAC/Swan", "Cordis", "HD catheter", "IABP 1:1", "Impella CP P8", "HM3 LVAD", "VA ECMO".
    static let deviceCue = NoteRx(#"\b(?:pivs?|pivc|ivs?|a-?line|art(?:erial)? (?:line|cath(?:eter)?)|cvc|cvl|tlc|central (?:venous )?(?:line|catheter)|triple lumen|quad lumen|picc|cordis|introducer|sheath|pac|swan(?:-ganz)?|pa (?:catheter|cath|line)|pulmonary artery catheter|ez-?io|intraosseous|hd (?:cath|catheter|line)|dialysis (?:cath|catheter|line)|trialysis|quinton|vas-?cath|mahurkar|iabp|balloon pump|impella|protek ?duo|protek|oxy-?rvad|lvad|hm ?3|hm ?ii|heartmate|hvad|ecmo|ecls|midline|foley|suprapubic catheter|urinary catheter)\b|(?-i:\bIO\b)"#)
    /// An ETT or a tracheostomy.
    static let tubeCue = NoteRx(#"\b(?:ett|et tube|endotracheal tube|dlt|double[- ]lumen tube|trach(?:eostomy)?|trach'?d)\b"#)
    /// Mechanical support, whose settings and cannulas may follow a comma.
    static let supportCue = NoteRx(#"\b(?:ecmo|ecls|iabp|balloon pump|impella|protek ?duo|protek|oxy-?rvad|lvad|hm ?3|hm ?ii|heartmate|hvad)\b"#)
    static let deviceSettingCue = NoteRx(#"\b(?:flow|sweep|fdo2|rpm|speed|pi|power|aug(?:mentation)?|position)\b|\b\d:\d\b|\bp-?\d\b|\d\s*(?:l/min|lpm)\b"#)
    static let ecmoPart = NoteRx(#"\b(?:drainage|return|inflow|outflow)\b|\b\d+(?:\.\d)?\s*fr?\b"#)
    /// "x2", "×2", "2 PIVs".
    static let countRx = NoteRx(#"(?<![a-z0-9])[x×]\s?([2-6])\b|\b([2-6])\s+(?:large[- ]bore\s+)?(?:pivs|ivs)\b"#)
    /// A tube or tracheostomy planned or in the past, not there on arrival ("for tracheostomy", "prior ETT").
    static let tubeSkip = NoteRx(#"\b(?:for|undergo(?:ing)?|scheduled|booked|consent(?:ed)?|planned|plan|presenting|candidate|will|prior|previous|previously|history of|h/o|was|were)\b(?:\s+[a-z/]+){0,3}\s*$"#)
    /// A line still to be placed ("will place an A-line", "A-line pre-induction").
    static let devicePlannedBefore = NoteRx(#"\b(?:will|plan(?:ned)?|to place|placing|prior to|consider|possible|may need|needs?)\b[^.;,]{0,25}$"#)
    /// A device said to be there, which ends a planned list.
    /// "planned" or "to be placed" after a device, which covers the list it ends.
    static let deviceListPlanned = NoteRx(#"^[^.;,]{0,25}\b(?:planned|to be placed|(?:pre|post)-?\s?induction|(?:before|after)\s+(?:induction|intubation)|in the or|once asleep)\b"#)
    /// A piece that starts with a plan ("plan GA"), which carries to the devices after it.
    static let planWord = NoteRx(#"^\s*(?:plan(?:ned|ning)?|will (?:place|need|get|have)|to place)\b"#)
    static let devicePresent = NoteRx(#"\b(?:has|have|had|with|existing|in place|placed|in situ|indwelling|already|current(?:ly)?|present)\b"#)
    static let devicePlannedAfter = NoteRx(#"^[^.;,]{0,25}\b(?:pre-?induction|post-?induction|after induction|before induction|to be placed|planned)\b"#)
    /// "IV fluids", "IV antibiotics": the route, not a line.
    static let ivRoute = NoteRx(#"\bivs?\s+(?:fluids?|abx|antibiotics?|push|pushes|meds?|medications?|contrast|iron|hydration|bolus|access|drip|infusion|ns|lr|steroids?|dexamethasone|tylenol|acetaminophen|morphine|dilaudid)\b"#)
    static let tubeGone = NoteRx(#"^\s*(?:was\s+|is\s+)?(?:removed|decannulated|pulled|out|discontinued)\b"#)
    /// Intubated or on the ventilator now, with no tube named.
    static let intubatedRx = NoteRx(#"\b(?:intubated|on (?:the )?vent(?:ilator)?|mechanically ventilated|vented)\b"#)
    static let intubatedPast = NoteRx(#"\b(?:was|were|previously|prior|history of|h/o|s/p|after|until|briefly)\b[^.;,]{0,20}$"#)
    static let ventCue = NoteRx(#"\b(?:on (?:the )?vent(?:ilator)?|mechanically ventilated|vent(?:ilator)? settings|prvc|simv|aprv|psv|assist[- ]control|peep)\b|\bvent\s*:|\ba/?c\s*/\s*(?:vc|pc|prvc)\b"#)
    /// Ventilator modes, the more specific first ("AC/PRVC" is PRVC).
    static let ventModes: [(NoteRx, String)] = [
        (NoteRx(#"\baprv\b"#), "APRV"), (NoteRx(#"\bprvc\b"#), "PRVC"), (NoteRx(#"\bsimv\b"#), "SIMV"),
        (NoteRx(#"\ba/?c\s*/?\s*pc\b|\bpressure control\b|(?-i:\bPC\b)"#), "AC/PC"),
        (NoteRx(#"\ba/?c\s*/?\s*vc\b|\bvolume control\b|\bassist[- ]control\b|(?-i:\b(?:VC|AC|A/C)\b)"#), "AC/VC"),
        (NoteRx(#"\bpsv\b|\bpressure support ventilation\b"#), "PSV"),
    ]
    static let vtRx = NoteRx(#"\b(?:vt|tv|tidal volume)\s*(?:of|:|=)?\s*(\d{3,4})\b|\b(\d{3,4})\s*(?:ml\s*)?[x×]\s*(\d{1,2})\b"#)
    static let ventRateRx = NoteRx(#"(?<!heart )(?<!resp )(?<!respiratory )\b(?:set rate|vent rate|rate)\s*(?:of|:|=)?\s*(\d{1,2})\b"#)
    static let peepRx = NoteRx(#"\bpeep\s*(?:of|:|=)?\s*(\d{1,2}(?:\.\d)?)\b"#)
    static let psRx = NoteRx(#"\b(?:ps|pressure support)\s*(?:of|:|=)?\s*(\d{1,2})(?:\s*/\s*(\d{1,2}))?\b"#)
    static let fio2Rx = NoteRx(#"\bfio2\s*(?:of|:|=)?\s*(0?\.\d{1,2}|1\.0|\d{2,3})\b\s*%?|\b(\d{2,3})\s*%\s*fio2\b"#)
    static let roomAirRx = NoteRx(#"\broom air\b"#)
    static let ncRx = NoteRx(#"(?<!high.flow )\b(?:nc|nasal cannula|nasal prongs)\b"#)
    static let hfncRx = NoteRx(#"\b(?:hfnc|hfno|high[- ]flow(?: nasal(?: cannula)?| oxygen| o2)?|optiflow|airvo)\b"#)
    static let nrbRx = NoteRx(#"\b(?:nrb|non-?rebreather(?: mask)?)\b"#)
    static let venturiRx = NoteRx(#"\b(?:venturi|venti)(?: mask)?\b"#)
    static let faceMaskRx = NoteRx(#"\b(?:simple|face|facial|oxygen|o2) mask\b|\bfacemask\b"#)
    static let nivRx = NoteRx(#"\b(?:bi-?pap|c-?pap|niv|nippv|non-?invasive (?:positive pressure )?ventilation)\b"#)
    static let trachCollarRx = NoteRx(#"\btrach(?:eostomy)? (?:collar|mask)\b|\bt-?piece\b"#)
    static let onLitersRx = NoteRx(#"\bon\s+(\d{1,2}(?:\.\d)?)\s*(?:l|lpm|l/min|liters?)\b(?!\s*/\s*kg)(?:\s*(?:of\s+)?(?:o2|oxygen))?"#)
    static let flowRx = NoteRx(#"\b(\d{1,2}(?:\.\d)?)\s*(?:l|lpm|l/min|liters?)\b(?!\s*/\s*kg)"#)
    static let percentRx = NoteRx(#"\b(\d{2,3})\s*%"#)
    /// CPAP or BiPAP at home for sleep apnea, not the support on arrival.
    static let homeRx = NoteRx(#"\b(?:home|at home|nightly|at night|qhs|osa|sleep|apn(?:o)?ea|uses|compliant|machine|wears)\b"#)
    /// CPAP or BiPAP running now: with a saturation, its pressures or an FiO₂.
    static let currentRx = NoteRx(#"\b(?:sats?|spo2|saturating|satting|currently|now|requiring|on arrival|placed on|started on|escalated to|weaned to)\b|\d{1,2}\s*/\s*\d{1,2}|fio2"#)
    static let breathingPast = NoteRx(#"\b(?:was|were|previously|prior|weaned off|off|discontinued|stopped|history of|h/o|s/p|home)\b[^.;,]{0,20}$"#)
    static let satBefore = NoteRx(#"\b(?:spo2|spo₂|sats?|sao2|saturating|satting|saturation|pulse ox)\s*(?:of|is|was|:|=)?\s*$"#)
    private static let devicePieceCut = NoteRx(#"\s*(?:[,;+]|\band\b|\bplus\b)\s*"#)

    /// Tubes, lines and devices in a sentence as written: the parser reads "PAC" and "ETT" as written, and their
    /// ambiguous readings say whether they are devices here ("PACs" on an ECG are beats). Each phrase is one finding.
    private static func readTubesAndDevices(_ written: String, _ abbreviations: [AbbreviationMatch], _ meant: AbbreviationExpansion, _ h: inout Hits) {
        let ns = written as NSString
        let blocked = abbreviations.filter { a in
            guard a.isAmbiguous, let m = a.meaning else { return false }
            return (a.key == "ETT" && m.id != "ett-tube") || (a.key == "PAC" && m.id != "pac-catheter")
        }.map(\.range)
        func free(_ m: NSTextCheckingResult, in piece: NSRange) -> Bool {
            let r = NSRange(location: piece.location + m.range.location, length: m.range.length)
            return !blocked.contains { NSIntersectionRange($0, r).length > 0 }
        }
        let pieces = devicePieces(written)
        // Each piece's cue: a tube's, else a device's.
        let cues: [(cue: NSTextCheckingResult, tube: Bool)?] = pieces.map { piece -> (cue: NSTextCheckingResult, tube: Bool)? in
            let text = ns.substring(with: piece)
            if let t = tubeCue.all(text).first(where: { free($0, in: piece) }) { return (cue: t, tube: true) }
            if let d = deviceCue.all(text).first(where: { free($0, in: piece) }) { return (cue: d, tube: false) }
            return nil
        }
        // "planned" after a list of devices covers the list ("A-line, PAC planned"), back to a piece that is not a device
        // or says the device is there.
        var plannedByList = Array(repeating: false, count: pieces.count)
        var carry = false
        for i in pieces.indices.reversed() {
            guard let x = cues[i], !x.tube else {
                carry = false
                continue
            }
            let text = ns.substring(with: pieces[i])
            if deviceListPlanned.first((text as NSString).substring(from: x.cue.range.location + x.cue.range.length)) != nil {
                carry = true
            } else if devicePresent.first(text) != nil {
                carry = false
            }
            plannedByList[i] = carry
        }
        // A plan carries along the devices after it ("plan A-line, PAC", "plan GA/ETT, A-line, PAC": the PAC is planned
        // too), until a piece that names no device or plan, or says the device is there.
        var planned = false
        for (i, piece) in pieces.enumerated() {
            let text = ns.substring(with: piece)
            guard let x = cues[i] else {
                planned = planWord.first(text) != nil
                continue
            }
            let cue = x.cue
            let tube: NSTextCheckingResult? = x.tube ? cue : nil
            let at = piece.location + cue.range.location
            let target = meant.target(piece)
            if negated(written, at: at) {
                h.seen(target)
                continue
            }
            let before = ns.substring(to: at)
            let after = ns.substring(from: at + cue.range.length)
            if tube != nil {
                if devicePlannedBefore.first(before) != nil { planned = true }
                guard tubeSkip.first(before) == nil, tubeGone.first(after) == nil else {
                    h.seen(target)
                    continue
                }
                guard let p = PatientDevices.parse(deviceWords(text)), p.kind == .ett || p.kind == .trach else { continue }
                if p.kind == .ett {
                    var size = p.size
                    if let v = Double(size), !(2...10).contains(v) { size = "" }
                    var depth = ""
                    if let d = p.settings["depth"], let v = Double(d), (8...35).contains(v) {
                        depth = d + " cm" + (p.settings["depthAt"].map { " at the " + $0 } ?? "")
                    }
                    h.add(airwayFinding("ett", size, depth), at: target)
                } else {
                    h.add(airwayFinding("trach", [p.size, p.detail].filter { !$0.isEmpty }.joined(separator: " "), ""), at: target)
                }
                continue
            }
            if devicePlannedBefore.first(before) != nil || devicePlannedAfter.first(after) != nil || plannedByList[i] {
                // Only a plan written before the device carries on ("A-line pre-induction, PIV 18G": the PIV is there).
                planned = devicePlannedBefore.first(before) != nil
                h.seen(target)
                continue
            }
            if planned, devicePresent.first(text) == nil {
                h.seen(target)
                continue
            }
            planned = false
            guard ivRoute.first(text) == nil else {
                h.seen(target)
                continue
            }
            var words = text
            var count = 1
            if let m = countRx.first(text), let n = m.text([1, 2], in: text).flatMap({ Int($0) }) {
                count = n
                let cut = m.range(at: 1).location != NSNotFound ? m.range : m.range(at: 2)
                words = (text as NSString).replacingCharacters(in: cut, with: " ")
            }
            guard let p = PatientDevices.parse(deviceWords(words)), p.confidence >= 0.35, p.kind != .other,
                  PatientDevice.lineKinds.contains(p.kind) || PatientDevice.supportKinds.contains(p.kind) else { continue }
            // A peripheral IV only with a gauge, a site, a count or the word PIV ("1 L IV" is a volume).
            if p.kind == .piv, !p.size.isEmpty, !["14", "16", "18", "20", "22", "24"].contains(p.size) { continue }
            if p.kind == .piv, p.size.isEmpty, (p.site ?? "").isEmpty, count < 2,
               text.range(of: #"\bpivs?\b"#, options: [.regularExpression, .caseInsensitive]) == nil { continue }
            var ds = p.devices(placedIntraop: false)
            if count > 1, p.companions.isEmpty { ds = (0..<count).map { _ in p.device(placedIntraop: false) } }
            let labels = PatientDevices.labels(ds)
            var label = labels.joined(separator: "; ")
            if count > 1, Set(labels).count == 1, let one = labels.first { label = one + " ×\(count)" }
            let support = ds.contains { PatientDevice.supportKinds.contains($0.kind) }
            h.add(PatientNoteFinding(id: "device:" + label.lowercased(), section: support ? Part.support : Part.devices, label: label,
                                     change: .devices(ds)), at: target)
            h.deviceRanges.append(target)
        }
    }

    /// A sentence in pieces at commas, semicolons and "and"; a pump's or circuit's settings and cannulas after a comma
    /// stay with it ("VV ECMO 25 Fr RFV drainage, 21 Fr RIJ return, flow 4.5 L/min").
    private static func devicePieces(_ c: String) -> [NSRange] {
        let ns = c as NSString
        var raw: [NSRange] = []
        var start = 0
        for cut in devicePieceCut.all(c) {
            if cut.range.location > start { raw.append(NSRange(location: start, length: cut.range.location - start)) }
            start = cut.range.location + cut.range.length
        }
        if start < ns.length { raw.append(NSRange(location: start, length: ns.length - start)) }
        var out: [NSRange] = []
        for r in raw {
            let t = ns.substring(with: r)
            if let last = out.last, deviceCue.first(t) == nil, tubeCue.first(t) == nil {
                let prev = ns.substring(with: last)
                let ecmo = prev.range(of: #"\b(?:ecmo|ecls)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
                if supportCue.first(prev) != nil, deviceSettingCue.first(t) != nil || (ecmo && ecmoPart.first(t) != nil) {
                    out[out.count - 1] = NSUnionRange(last, r)
                    continue
                }
            }
            out.append(r)
        }
        return out
    }

    /// The words of a phrase the device parser reads; the rest ("pt has", "placed yesterday") would only lower its
    /// confidence and end up in the device's detail.
    private static func deviceWords(_ text: String) -> String {
        var out: [String] = []
        for raw in text.split(whereSeparator: { $0.isWhitespace }) {
            let w = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]\"'"))
            if !w.isEmpty, isDeviceWord(w) { out.append(w) }
        }
        return out.joined(separator: " ")
    }

    private static func isDeviceWord(_ w: String) -> Bool {
        let low = w.lowercased()
        if deviceVocabulary.contains(low) { return true }
        if low.contains("/") {
            let parts = low.split(separator: "/").map(String.init)
            return !parts.isEmpty && parts.allSatisfy { isDeviceWord($0) }
        }
        let patterns = [#"^\d+(?:\.\d+)?(?:g|ga|f|fr|cm|mm|%|rpm|w|lpm|l/min|mmhg)?$"#, #"^\d:\d$"#, #"^p-?\d$"#,
                        #"^[rl](?:ij|ijv|sc|scv|ej|fv|fa|ac|fem|rad|dp|ax|brach)$"#]
        return patterns.contains { low.range(of: $0, options: .regularExpression) != nil }
    }

    private static let deviceVocabulary: Set<String> = [
        "piv", "pivs", "pivc", "iv", "ivs", "peripheral", "midline", "aline", "a-line", "art", "arterial", "line", "lines", "cath", "catheter",
        "catheters", "cvc", "cvl", "central", "venous", "tlc", "triple", "quad", "lumen", "mac", "introducer", "intro", "cordis", "sheath",
        "trialysis", "hd", "dialysis", "quinton", "vascath", "vas-cath", "mahurkar", "swan", "swan-ganz", "swanganz", "ganz", "pac", "pa",
        "pulmonary", "artery", "picc", "io", "ezio", "ez-io", "intraosseous", "iabp", "balloon", "pump", "impella", "cp", "rp", "ecp", "flex", "protek", "protekduo", "duo", "oxyrvad", "oxygenator",
        "lvad", "vad", "hm3", "hmiii", "hm2", "hmii", "hvad", "heartmate", "hm", "ecmo", "ecls", "cannula", "cannulas", "cannulae", "vv", "va",
        "vav", "v-v", "v-a", "drainage", "return", "inflow", "outflow", "avalon", "crescent", "flow", "sweep", "fdo2", "pi", "power", "speed",
        "rpm", "aug", "augmentation", "timing", "position", "depth", "ett", "et", "tube", "dlt", "double", "trach", "tracheostomy", "shiley",
        "portex", "bivona", "cuffed", "uncuffed", "fenestrated", "ij", "ijv", "internal", "jugular", "ej", "external", "sc", "subclavian",
        "subclav", "fv", "fem", "femoral", "rad", "radial", "brach", "brachial", "ax", "axillary", "dp", "dorsalis", "pedis", "tib", "tibial",
        "hum", "humeral", "ac", "antecubital", "fa", "forearm", "hand", "wrist", "upper", "arm", "foot", "saphenous", "r", "l", "rt", "lt",
        "right", "left", "bilat", "b/l", "bilateral", "rue", "lue", "rle", "lle", "ue", "le", "g", "ga", "gauge", "f", "fr", "french", "cm",
        "mm", "lpm", "w", "mmhg", "%", "via", "at", "@", "teeth", "lip", "lips", "gums", "nare", "oral", "nasal", "stoma", "heart", "apex",
        "aorta", "atrium", "1:1", "1:2", "1:3", "/", "foley", "foleys", "ifc", "spc", "suprapubic", "urethral", "urinary", "bladder", "coude", "coudé",
    ]

    /// Intubated or ventilated with no tube named, the ventilator's settings, and oxygen (on the reading text: "RA" is
    /// already "room air" where the context says so).
    private static func readBreathing(_ c: String, _ h: inout Hits) {
        let ns = c as NSString
        let devices = h.deviceRanges
        func free(_ r: NSRange) -> Bool { !devices.contains { NSIntersectionRange($0, r).length > 0 } }
        func current(_ m: NSTextCheckingResult) -> Bool {
            !negated(c, at: m.range.location) && breathingPast.first(ns.substring(to: m.range.location)) == nil && free(m.range)
        }
        if let m = intubatedRx.first(c), current(m), intubatedPast.first(ns.substring(to: m.range.location)) == nil, !past(c, m) {
            if h.findings.contains(where: { $0.id == "airway" }) { h.seen(m.range) } else { h.add(airwayFinding("ett", "", ""), at: m.range) }
        }
        let tubeHere = h.findings.contains { f in
            if case .currentAirway(let id, _, _) = f.change { return id == "ett" || id == "trach" }
            return false
        }
        let ventHere = ventCue.first(c) != nil || tubeHere

        // FiO₂: the ventilator's, or a high-flow, Venturi, CPAP or trach collar's.
        var fio2: Double?
        var fio2At: NSRange?
        if let m = fio2Rx.all(c).first(where: { free($0.range) }), var f = number(m, [1, 2], c) {
            if f <= 1 { f *= 100 }
            if (21...100).contains(f) { fio2 = (f * 10).rounded() / 10; fio2At = m.range }
        }

        // Oxygen, breathing on their own.
        var oxygen: PatientOxygen?
        var oxygenAt = NSRange(location: 0, length: 0)
        let devicesInOrder: [(NoteRx, String)] = [(trachCollarRx, "trachCollar"), (hfncRx, "hfnc"), (nrbRx, "nrb"), (venturiRx, "venturi"),
                                                  (faceMaskRx, "mask"), (ncRx, "nc"), (nivRx, "niv")]
        for (rx, id) in devicesInOrder {
            guard let m = rx.all(c).first(where: { current($0) }) else { continue }
            if id == "niv", ventHere || homeRx.first(c) != nil || currentRx.first(c) == nil { continue }
            oxygen = PatientOxygen(device: id)
            oxygenAt = m.range
            break
        }
        if oxygen == nil, !ventHere, let m = onLitersRx.first(c), current(m), let f = number(m, [1], c), (0.25...15).contains(f) {
            oxygen = PatientOxygen(device: "nc", flow: f)
            oxygenAt = m.range
        }
        if oxygen == nil, !ventHere, let m = roomAirRx.first(c), current(m) {
            oxygen = PatientOxygen(device: "ra")
            oxygenAt = m.range
        }
        var fio2Taken = false
        if var o = oxygen, let d = o.device {
            let piece = pieceRange(around: oxygenAt, in: c)
            let text = ns.substring(with: piece)
            let at = oxygenAt.location - piece.location
            if PatientOxygen.flowDevices.contains(d), o.flow == nil {
                let flows = flowRx.all(text).filter { m in number(m, [1], text).map { flowFits(d, $0) } ?? false }
                if let m = flows.min(by: { Swift.abs($0.range.location - at) < Swift.abs($1.range.location - at) }) {
                    o.flow = number(m, [1], text)
                    h.seen(NSRange(location: piece.location + m.range.location, length: m.range.length))
                }
            }
            if PatientOxygen.fio2Devices.contains(d) {
                if let f = fio2, let r = fio2At, !ventHere {
                    o.fio2 = f
                    fio2Taken = true
                    h.seen(r)
                } else {
                    for m in percentRx.all(text) where satBefore.first((text as NSString).substring(to: m.range.location)) == nil {
                        guard let f = number(m, [1], text), (21...100).contains(f) else { continue }
                        o.fio2 = f
                        h.seen(NSRange(location: piece.location + m.range.location, length: m.range.length))
                        break
                    }
                }
            }
            h.add(oxygenFinding(o), at: oxygenAt)
        }

        // The ventilator.
        guard ventHere else { return }
        var v = PatientVent()
        var first: NSRange?
        func note(_ r: NSRange) {
            h.seen(r)
            if first == nil || r.location < first!.location { first = r }
        }
        for (rx, mode) in ventModes {
            if let m = rx.all(c).first(where: { free($0.range) }) {
                v.mode = mode
                note(m.range)
                break
            }
        }
        if let m = vtRx.first(c), free(m.range) {
            if let a = number(m, [1, 2], c), (150...1500).contains(a) { v.vt = a; note(m.range) }
            if let r = number(m, [3], c), (4...60).contains(r) { v.rr = r }
        }
        if v.rr == nil, let m = ventRateRx.first(c), free(m.range), let r = number(m, [1], c), (4...60).contains(r) {
            v.rr = r
            note(m.range)
        }
        if let m = peepRx.first(c), let p = number(m, [1], c), p <= 30 {
            v.peep = p
            note(m.range)
        }
        if let m = psRx.first(c), free(m.range), let p = number(m, [1], c), p <= 40 {
            v.ps = p
            if v.peep == nil, let e = number(m, [2], c), e <= 30 { v.peep = e }
            note(m.range)
        }
        if let f = fio2, let r = fio2At, !fio2Taken {
            v.fio2 = f
            note(r)
        }
        if !v.isEmpty, let r = first { h.add(ventFinding(v), at: r) }
    }

    /// The comma- or semicolon-separated part of a sentence around a range.
    private static func pieceRange(around r: NSRange, in c: String) -> NSRange {
        let ns = c as NSString
        var start = r.location
        var end = r.location + r.length
        while start > 0, ns.character(at: start - 1) != 44, ns.character(at: start - 1) != 59 { start -= 1 }
        while end < ns.length, ns.character(at: end) != 44, ns.character(at: end) != 59 { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    /// A flow that fits the device (L/min).
    private static func flowFits(_ device: String, _ f: Double) -> Bool {
        switch device {
        case "nc": return (0.25...15).contains(f)
        case "mask": return (4...15).contains(f)
        case "nrb": return (8...25).contains(f)
        case "hfnc": return (5...80).contains(f)
        default: return (1...30).contains(f)
        }
    }

    private static func airwayFinding(_ id: String, _ detail: String, _ depth: String, note: String? = nil) -> PatientNoteFinding {
        PatientNoteFinding(id: "airway", section: Part.airway, label: airwayLabel(id, detail, depth), change: .currentAirway(id, detail, depth), note: note)
    }

    /// "Current airway: intubated (ETT 7.5 at 23 cm at the lip)", "Current airway: tracheostomy (8 Shiley)".
    private static func airwayLabel(_ id: String, _ detail: String, _ depth: String) -> String {
        switch id {
        case "ett":
            let tube = ["ETT" + (detail.isEmpty ? "" : " " + detail), depth.isEmpty ? nil : "at " + depth].compactMap { $0 }.joined(separator: " ")
            return "Current airway: intubated" + (detail.isEmpty && depth.isEmpty ? "" : " (" + tube + ")")
        case "trach":
            return "Current airway: tracheostomy" + (detail.isEmpty ? "" : " (" + detail + ")")
        default:
            return "Current airway: own airway"
        }
    }

    private static func ventFinding(_ v: PatientVent) -> PatientNoteFinding {
        PatientNoteFinding(id: "vent", section: Part.airway, label: "Ventilator: " + v.text, change: .vent(v))
    }

    private static func oxygenFinding(_ o: PatientOxygen) -> PatientNoteFinding {
        PatientNoteFinding(id: "oxygen", section: Part.airway, label: "Oxygen: " + o.text, change: .oxygen(o))
    }

    /// The same item from two sentences put together; nil keeps the first as it is.
    private static func combined(_ a: PatientNoteFinding, _ b: PatientNoteFinding) -> PatientNoteFinding? {
        switch (a.change, b.change) {
        case (.vent(let x), .vent(let y)):
            return ventFinding(mergedVent(y, x))
        case (.oxygen(let x), .oxygen(let y)):
            guard x.device == y.device else { return nil }
            return oxygenFinding(PatientOxygen(device: x.device, flow: x.flow ?? y.flow, fio2: x.fio2 ?? y.fio2))
        case (.currentAirway(let i, let d, let p), .currentAirway(let j, let e, let q)):
            if i == j { return airwayFinding(i, d.isEmpty ? e : d, p.isEmpty ? q : p, note: a.note) }
            // A bare "intubated" or "on the vent" gives way to a tracheostomy named.
            if i == "ett", d.isEmpty, p.isEmpty, j == "trach" { return b }
            return nil
        case (.codeStatus, .codeStatus):
            return PatientCodeStatus.merged(a.change, b.change)
        case (.typeScreen(let x), .typeScreen(let y)):
            // "T&S A neg." then "Antibody screen negative.": one item.
            return LabResults.typeScreenFinding(y.merged(over: x))
        case (.cardiacSurgery(let x), .cardiacSurgery(let y)):
            // Operations told in several places of the note: one entry.
            let t = mentions(x, y) ? x : x + "; " + y
            return PatientNoteFinding(id: a.id, section: a.section, label: "Past surgical history: " + t, change: .cardiacSurgery(t))
        case (.detail(let p, let k, let x), .detail(let q, let l, let y)) where p == q && k == l && listDetails.contains(k):
            // 1.9: "HBV. HCV.": one item, both types.
            let v = mergedList(x, y)
            let label = a.id.hasPrefix("problem:") ? (problemLabels[p] ?? p) + " (" + detailText(k, v) + ")" : detailLabel(p, k, v)
            return PatientNoteFinding(id: a.id, section: a.section, label: label, change: .detail(p, k, v), note: a.note)
        case (.problem, .detail), (.problem, .problemNote):
            // The same item told again with its detail.
            return b
        default:
            return nil
        }
    }

    /// The record's settings with the note's laid over them.
    private static func mergedVent(_ a: PatientVent, _ b: PatientVent) -> PatientVent {
        var v = a
        if !b.mode.isEmpty { v.mode = b.mode }
        if let x = b.vt { v.vt = x }
        if let x = b.rr { v.rr = x }
        if let x = b.peep { v.peep = x }
        if let x = b.fio2 { v.fio2 = x }
        if let x = b.ps { v.ps = x }
        return v
    }

    /// Another device replaces the oxygen; the same device keeps what the note does not give.
    private static func mergedOxygen(_ a: PatientOxygen, _ b: PatientOxygen) -> PatientOxygen {
        guard a.device == b.device else { return b }
        return PatientOxygen(device: b.device, flow: b.flow ?? a.flow, fio2: b.fio2 ?? a.fio2)
    }

    /// Both given and different.
    private static func differs(_ a: Double?, _ b: Double?) -> Bool {
        guard let a, let b else { return false }
        return Swift.abs(a - b) >= 0.05
    }

    /// The devices not in the record yet: one already there with the same kind and site counts once.
    private static func newDevices(_ ds: [PatientDevice], in r: PatientRecord) -> [PatientDevice] {
        var have = r.currentDevices()
        var out: [PatientDevice] = []
        for d in ds {
            if let i = have.firstIndex(where: { $0.kind == d.kind && $0.site == d.site }) { have.remove(at: i) } else { out.append(d) }
        }
        return out
    }

    // MARK: Status and adding

    static func status(_ f: PatientNoteFinding, in r: PatientRecord) -> PatientNoteStatus {
        switch f.change {
        case .age(let v):
            guard let o = r.ageYears else { return .new }
            return same(o, v) ? .recorded : .replaces("age " + PatientRecord.ageText(o))
        case .sex(let s):
            guard let o = r.sex else { return .new }
            return o == s ? .recorded : .replaces(o.label.lowercased())
        case .height(let v):
            guard let o = r.heightCm else { return .new }
            return same(o, v) ? .recorded : .replaces(NumText.short(o) + " cm")
        case .weight(let v):
            guard let o = r.weightKg else { return .new }
            return same(o, v) ? .recorded : .replaces(NumText.short(o) + " kg")
        case .procedure(let p):
            let o = r.procedure.trimmingCharacters(in: .whitespacesAndNewlines)
            if o.isEmpty { return .new }
            let read = PlannedProcedure.parse(p).map(\.text).joined(separator: " + ")
            return o.caseInsensitiveCompare(p) == .orderedSame || o.caseInsensitiveCompare(read) == .orderedSame ? .recorded : .replaces(o)
        case .urgency(let u):
            guard let o = r.urgency else { return .new }
            return o == u ? .recorded : .replaces(o.label.lowercased())
        case .anesthetic(let a):
            return r.anesthetic.contains(a) ? .recorded : .new
        case .asa(let n, let e):
            guard let o = r.asaClass else { return .new }
            if o == n && (!e || r.asaE == true) { return .recorded }
            return .replaces("ASA " + PatientRules.roman(o) + (r.asaE == true ? "E" : ""))
        case .problem(let p):
            if r.problems.contains(p) || (supersededBy[p] ?? []).contains(where: { r.problems.contains($0) }) { return .recorded }
            let general = supersededBy.keys.filter { (supersededBy[$0] ?? []).contains(p) && r.problems.contains($0) }.compactMap { problemLabels[$0] }.sorted()
            return general.isEmpty ? .new : .replaces(general.joined(separator: "; "))
        case .aneurysm(let site, let cm, let ruptured):
            guard let key = aneurysmKey(site, in: r), let a = r.hx.aneurysms[key] else { return .new }
            if ruptured && !a.ruptured { return .new }
            if !ruptured && a.ruptured { return .recorded }
            guard let cm else { return .recorded }
            guard let o = a.cm else { return .new }
            return same(o, cm) ? .recorded : .replaces(NumText.short(o) + " cm")
        case .valve(let v, let lesion, let g):
            let x = r.hx.valve(v)
            guard x.has(lesion) else { return .new }
            guard let g else { return .recorded }
            guard let o = x.grade(lesion) else { return .new }
            return o == g ? .recorded : .replaces(o)
        case .prosthesis(let v, let t):
            if v.isEmpty {
                let any = r.hx.prosthesisUnplaced || r.hx.valves.values.contains(where: \.prosthetic)
                return any && (t.isEmpty || r.hx.valves.values.contains { mentions($0.prosthesis, t) }) ? .recorded : .new
            }
            let x = r.hx.valve(v)
            guard x.prosthetic else { return .new }
            if t.isEmpty || mentions(x.prosthesis, t) { return .recorded }
            return x.prosthesis.isEmpty ? .new : .replaces(x.prosthesis)
        case .pulmHtn(let g):
            if r.has("pulm-htn-severe") { return .recorded }
            guard r.has("pulm-htn") else { return .new }
            guard let o = r.hx.pulmHtnSeverity else { return .new }
            return o == g ? .recorded : .replaces(o)
        case .cardiacSurgery(let t):
            return mentions(PatientHistoryDetails.cardiacSurgeryText(r), t) || r.surgeries.contains(where: { mentions($0.name, t) })
                || PastSurgeryNote.cardiacRecorded(t, in: r) ? .recorded : .new
        case .pastSurgery(let t, let d):
            return PastSurgeryNote.isRecorded(t, d, in: r) ? .recorded : .new
        case .lhcResult(let v):
            guard let o = r.lhc.result else { return .new }
            return o == v ? .recorded : .replaces(o == "no-cad" ? "no CAD" : "non-obstructive")
        case .homeO2(let flow):
            guard r.has("home-o2"), let o = r.hx.homeO2Flow else { return .new }
            return same(o, flow) ? .recorded : .replaces(NumText.short(o) + " L/min")
        case .problemNote(let p, let t):
            let has = r.problems.contains(p)
            return has && mentions(problemNoteField(p, r), t) ? .recorded : .new
        case .detail(let p, let key, let value):
            if !p.isEmpty, !r.problems.contains(p), !(supersededBy[p] ?? []).contains(where: { r.problems.contains($0) }) { return .new }
            return detailStatus(key, value, r)
        case .noHistory:
            if r.noHistory { return .recorded }
            return r.problems.isEmpty ? .new : .conflicts("Problems are already recorded.")
        case .smoking(let s):
            guard let o = r.smoking else { return .new }
            return o == s ? .recorded : .replaces(o == "never" ? "never smoked" : o + " smoker")
        case .medFlag(let f):
            return r.medFlags.contains(f) ? .recorded : .new
        case .medications(let m):
            return mentions(r.medications, m) ? .recorded : .new
        case .infusion(let drug, let rate):
            if let it = infusionItem(drug, rate) { return InfusionEntry.status(it, in: r.homeInfusions) }
            guard let o = r.homeInfusions.first(where: { $0.drug.caseInsensitiveCompare(drug) == .orderedSame }) else { return .new }
            if rate.isEmpty || o.rate.caseInsensitiveCompare(rate) == .orderedSame { return .recorded }
            return o.rate.isEmpty ? .new : .replaces(o.rate)
        case .nkda:
            if r.nkda { return .recorded }
            let a = recordedAllergies(r)
            return a.isEmpty ? .new : .conflicts("Allergies are recorded (" + a + "); check them in Medications and allergies.")
        case .allergies(let a):
            if r.nkda { return .replaces("NKDA") }
            return mentions(r.allergies, a) ? .recorded : .new
        case .anesthesiaHistory(let a):
            return r.anesthesiaHistory.contains(a) ? .recorded : .new
        case .anesthesiaNotes(let t):
            return mentions(r.anesthesiaNotes, t) ? .recorded : .new
        case .vital(let k, let v):
            guard let o = r.vitals[k] else { return .new }
            return same(o, v) ? .recorded : .replaces(NumText.short(o))
        case .lab(let k, let v):
            guard let o = r.labs[k] else { return .new }
            return same(o, v) ? .recorded : .replaces(PatientLabs.test(k)?.format(o) ?? NumText.short(o))
        case .lastSolids(let d):
            guard let o = r.lastSolids else { return .new }
            return o == d ? .recorded : .replaces(PatientSummary.time(o))
        case .lastClears(let d):
            guard let o = r.lastClears else { return .new }
            return o == d ? .recorded : .replaces(PatientSummary.time(o))
        case .mets(let m):
            guard let o = r.mets else { return .new }
            return o == m ? .recorded : .replaces(o == "ge4" ? "4 METs or more" : (o == "lt4" ? "under 4 METs" : "unknown"))
        case .frail:
            return r.frail ? .recorded : .new
        case .symptom(let s):
            return r.cardiacSymptoms.contains(s) ? .recorded : .new
        case .acute(let a):
            return r.activeCardiac.contains(a) ? .recorded : .new
        case .mallampati(let n):
            guard let o = r.mallampati else { return .new }
            return o == n ? .recorded : .replaces("Mallampati " + PatientRules.roman(o))
        case .airwaySign(let s):
            return r.airwaySigns.contains(s) ? .recorded : .new
        case .dentition(let t):
            return mentions(r.dentition, t) ? .recorded : .new
        case .currentAirway(let id, let detail, let depth):
            guard let o = r.currentAirway else { return .new }
            let old = o == "natural" ? "own airway" : (r.currentAirwayText ?? o)
            if o != id { return .replaces(old) }
            switch id {
            case "ett":
                let sizeSame = detail.isEmpty || r.ettSize == detail
                let depthSame = depth.isEmpty || r.ettDepth.caseInsensitiveCompare(depth) == .orderedSame
                if sizeSame && depthSame { return .recorded }
                return (sizeSame || r.ettSize.isEmpty) && (depthSame || r.ettDepth.isEmpty) ? .new : .replaces(old)
            case "trach":
                if detail.isEmpty || r.trachType.caseInsensitiveCompare(detail) == .orderedSame { return .recorded }
                return r.trachType.isEmpty ? .new : .replaces(old)
            default:
                return .recorded
            }
        case .vent(let v):
            let merged = mergedVent(r.vent, v)
            if merged == r.vent { return .recorded }
            let clash = (!v.mode.isEmpty && !r.vent.mode.isEmpty && v.mode != r.vent.mode) || differs(v.vt, r.vent.vt) || differs(v.rr, r.vent.rr)
                || differs(v.peep, r.vent.peep) || differs(v.fio2, r.vent.fio2) || differs(v.ps, r.vent.ps)
            return clash ? .replaces(r.vent.text) : .new
        case .oxygen(let o):
            if r.oxygen.isEmpty { return .new }
            if r.oxygen.device == o.device && !differs(o.flow, r.oxygen.flow) && !differs(o.fio2, r.oxygen.fio2) {
                return mergedOxygen(r.oxygen, o) == r.oxygen ? .recorded : .new
            }
            return .replaces(r.oxygen.text)
        case .devices(let ds):
            return newDevices(ds, in: r).isEmpty ? .recorded : .new
        case .otherHistory(let t):
            return mentions(r.otherHistory, t) ? .recorded : .new
        case .codeStatus(let s, let polst, let plan):
            return PatientCodeStatus.status(s, polst: polst, plan: plan, in: r)
        case .intraopLabs(let set):
            guard let o = r.intraopLabs.first(where: { $0.id == set.id }) else { return .new }
            let changed = set.values.keys.sorted().filter { k in o.values[k].map { !same($0, set.values[k] ?? $0) } ?? false }
            if !changed.isEmpty {
                return .replaces(changed.compactMap { k in o.values[k].map { (PatientLabs.test(k)?.short ?? k) + " " + NumText.short($0) } }.joined(separator: ", "))
            }
            return set.values.keys.allSatisfy { o.values[$0] != nil } ? .recorded : .new
        case .blood:
            return .new
        case .intraopInfusion(let drug, let rate):
            if let it = infusionItem(drug, rate) { return InfusionEntry.status(it, in: r.infusions) }
            guard let o = r.infusions.first(where: { $0.drug.caseInsensitiveCompare(drug) == .orderedSame }) else { return .new }
            if rate.isEmpty || o.rate.caseInsensitiveCompare(rate) == .orderedSame { return .recorded }
            return o.rate.isEmpty ? .new : .replaces(o.rate)
        case .typeScreen(let ts):
            return LabResults.status(ts, in: r)
        case .infectious(let id, let name, let v):
            return LabResults.status(id, name: name, v, in: r)
        case .intraopAirway(let key, let value):
            guard let o = r.intraopAirway(key) else { return .new }
            // A tube written with less than the record has ("7.5 ETT, 23 cm" for "… at the lip") is already there.
            let known = o.caseInsensitiveCompare(value) == .orderedSame || (key == "tube" && o.lowercased().hasPrefix(value.lowercased()))
            return known ? .recorded : .replaces(o)
        }
    }

    /// Which aneurysm a note's location means in this record: the location itself; for "thoracic" (no location written),
    /// the record's one thoracic aneurysm if it has exactly one, else "thoracic".
    static func aneurysmKey(_ site: String, in r: PatientRecord) -> String? {
        guard site == "thoracic" else { return r.hx.aneurysms[site] != nil ? site : nil }
        let thoracic = r.hx.aneurysms.keys.filter { PatientHistoryDetails.thoracicSites.contains($0) }
        if thoracic.count == 1 { return thoracic[0] }
        return r.hx.aneurysms["thoracic"] != nil ? "thoracic" : nil
    }

    /// Where a problem's words go: an aortic repair's to the repair details, an arrhythmia's to its type, a device's to
    /// the device details, PVD's and congenital disease's to their details; any other to its system's details.
    /// 1.9: the new pages' items have a text field each (PatientHistoryDetails): a fracture's place, the arthritis's
    /// joint, the esophageal disorder's type, the psychological disorder's name, the sepsis's source, the burn.
    private static func problemNoteField(_ p: String, _ r: PatientRecord) -> String {
        switch p {
        case "evar", "tevar", "aortic-repair-open": return r.hx.repairDetails
        case "arrhythmia": return r.hx.arrhythmiaType
        case "pacemaker", "icd": return r.hx.deviceDetails
        case "pvd": return r.hx.pvdDetails
        case "chd", "chd-elevated": return r.hx.chdDetails
        // 1.9
        case "endocarditis": return r.hx.endocarditisDetails
        case "psych": return r.hx.psychOther
        case "esrd-dialysis": return r.hx.dialysisScheduleOther
        case "gastric-bypass": return r.hx.gastricBypassDetails
        case "esophageal-disorder": return r.hx.esophagealDisorderType
        case "gi-bleed": return r.hx.giBleedDetails
        case "bleeding": return r.hx.bleedingOther
        case "thrombophilia-heme": return r.hx.thrombophiliaOther
        case "declines-blood": return r.hx.declinesBloodDetails
        case "vte": return r.hx.vteDate
        case "sepsis": return r.hx.sepsisSource
        case "hiv": return r.hx.hivViralLoad
        case "covid-recent": return r.hx.covidTestDate
        case "massive-trauma", "burn": return r.hx.traumaDetails
        case "ra", "oa": return r.hx.arthritisLocation
        case "fracture": return r.hx.fractureLocation
        case "compartment-syndrome": return r.hx.compartmentLocation
        case "substance", "cocaine", "opioid-use", "marijuana", "methamphetamine": return r.hx.drugsOther
        default: return r.systemNotes[PatientCatalog.system(of: p)?.id ?? "cv"] ?? ""
        }
    }

    private static func setProblemNote(_ p: String, _ t: String, _ r: inout PatientRecord) {
        switch p {
        case "evar", "tevar", "aortic-repair-open": r.hx.repairDetails = t
        case "arrhythmia": r.hx.arrhythmiaType = t
        case "pacemaker", "icd": r.hx.deviceDetails = t
        case "pvd": r.hx.pvdDetails = t
        case "chd", "chd-elevated": r.hx.chdDetails = t
        // 1.9
        case "endocarditis": r.hx.endocarditisDetails = t
        case "psych": r.hx.psychOther = t
        case "esrd-dialysis": r.hx.dialysisScheduleOther = t
        case "gastric-bypass": r.hx.gastricBypassDetails = t
        case "esophageal-disorder": r.hx.esophagealDisorderType = t
        case "gi-bleed": r.hx.giBleedDetails = t
        case "bleeding": r.hx.bleedingOther = t
        case "thrombophilia-heme": r.hx.thrombophiliaOther = t
        case "declines-blood": r.hx.declinesBloodDetails = t
        case "vte": r.hx.vteDate = t
        case "sepsis": r.hx.sepsisSource = t
        case "hiv": r.hx.hivViralLoad = t
        case "covid-recent": r.hx.covidTestDate = t
        case "massive-trauma", "burn": r.hx.traumaDetails = t
        case "ra", "oa": r.hx.arthritisLocation = t
        case "fracture": r.hx.fractureLocation = t
        case "compartment-syndrome": r.hx.compartmentLocation = t
        case "substance", "cocaine", "opioid-use", "marijuana", "methamphetamine": r.hx.drugsOther = t
        default: r.systemNotes[PatientCatalog.system(of: p)?.id ?? "cv"] = t
        }
    }

    /// Files a problem as `.problem` does: not beside a more specific one already recorded, and in place of its general
    /// form.
    private static func fileProblem(_ p: String, _ r: inout PatientRecord) {
        r.noHistory = false
        if (supersededBy[p] ?? []).contains(where: { r.problems.contains($0) }) { return }
        r.problems.insert(p)
        r.labProblems.remove(p)
        for general in supersededBy.keys where (supersededBy[general] ?? []).contains(p) { r.problems.remove(general) }
    }

    /// Puts the chosen findings into the record: values are set, lists gain items, text is added after what is there.
    /// A general problem never goes in beside its more specific form, and NKDA never hides a recorded allergy.
    static func apply(_ changes: [PatientNoteChange], to r: inout PatientRecord) {
        for c in changes {
            switch c {
            case .age(let v): r.ageYears = v
            case .sex(let s): r.sex = s
            case .height(let v): r.heightCm = v
            case .weight(let v): r.weightKg = v
            case .procedure(let p):
                // The note's own anesthetic findings decide the plan; the procedure list fills the risk-score inputs.
                r.setProcedures(PlannedProcedure.parse(p), fillAnesthetic: false)
                if r.procedures.allSatisfy({ $0.catalogID == nil }) { r.procedure = p }
            case .urgency(let u): r.urgency = u
            case .anesthetic(let a): r.anesthetic.insert(a)
            case .asa(let n, let e):
                r.asaClass = n
                if e { r.asaE = true }
            case .problem(let p):
                r.noHistory = false
                if (supersededBy[p] ?? []).contains(where: { r.problems.contains($0) }) { continue }
                r.problems.insert(p)
                // Filed from the note's history: the user's now, whatever a lab result linked (LabResults.edit).
                r.labProblems.remove(p)
                for general in supersededBy.keys where (supersededBy[general] ?? []).contains(p) { r.problems.remove(general) }
            case .aneurysm(let site, let cm, let ruptured):
                r.noHistory = false
                let key = aneurysmKey(site, in: r) ?? site
                var a = r.hx.aneurysms[key] ?? PatientAneurysm()
                if let cm { a.cm = cm }
                if ruptured { a.ruptured = true }
                r.hx.aneurysms[key] = a
                PatientHistoryDetails.sync(&r)
            case .valve(let v, let lesion, let g):
                r.noHistory = false
                r.hx.editValve(v) { x in
                    x.set(lesion, true)
                    if let g { x.setGrade(lesion, g) }
                }
                PatientHistoryDetails.sync(&r)
            case .prosthesis(let v, let t):
                r.noHistory = false
                if v.isEmpty {
                    r.hx.prosthesisUnplaced = true
                } else {
                    r.hx.editValve(v) { x in
                        x.prosthetic = true
                        if !t.isEmpty, !mentions(x.prosthesis, t) { x.prosthesis = joined(x.prosthesis, t) }
                    }
                }
            case .pulmHtn(let g):
                r.noHistory = false
                if r.has("pulm-htn-severe") { continue }
                r.problems.insert("pulm-htn")
                r.hx.pulmHtnSeverity = g
            case .cardiacSurgery(let t):
                r.noHistory = false
                // Each operation its own entry in Past surgical history, with its date (1.8.3).
                PastSurgeryNote.addCardiac(t, to: &r)
            case .pastSurgery(let t, let d):
                PastSurgeryNote.add(t, d, to: &r)
            case .lhcResult(let v):
                r.lhc.result = v
            case .homeO2(let flow):
                r.noHistory = false
                r.problems.insert("home-o2")
                r.hx.homeO2Flow = flow
            case .problemNote(let p, let t):
                r.noHistory = false
                r.problems.insert(p)
                setProblemNote(p, joined(problemNoteField(p, r), t), &r)
            case .detail(let p, let key, let value):
                if !p.isEmpty { fileProblem(p, &r) }
                setDetail(key, value, &r)
            case .noHistory:
                if r.problems.isEmpty { r.noHistory = true }
            case .smoking(let s): r.smoking = s
            case .medFlag(let f): r.medFlags.insert(f)
            case .medications(let m): r.medications = joined(r.medications, m)
            case .infusion(let drug, let rate):
                if let it = infusionItem(drug, rate) {
                    InfusionEntry.apply([it], to: &r.homeInfusions)
                } else if let i = r.homeInfusions.firstIndex(where: { $0.drug.caseInsensitiveCompare(drug) == .orderedSame }) {
                    if !rate.isEmpty { r.homeInfusions[i].rate = rate }
                } else {
                    r.homeInfusions.append(PatientInfusion(drug: drug.prefix(1).uppercased() + drug.dropFirst(), rate: rate))
                }
            case .nkda:
                // NKDA never hides a recorded allergy, typed or on the 1.9 list.
                if recordedAllergies(r).isEmpty { r.nkda = true }
            case .allergies(let a):
                r.nkda = false
                r.allergies = joined(r.allergies, a)
            case .anesthesiaHistory(let a): r.anesthesiaHistory.insert(a)
            case .anesthesiaNotes(let t): r.anesthesiaNotes = joined(r.anesthesiaNotes, t)
            case .vital(let k, let v): r.vitals[k] = v
            case .lab(let k, let v): r.labs[k] = v
            case .lastSolids(let d): r.lastSolids = d
            case .lastClears(let d): r.lastClears = d
            case .mets(let m): r.mets = m
            case .frail: r.frail = true
            case .symptom(let s): r.cardiacSymptoms.insert(s)
            case .acute(let a): r.activeCardiac.insert(a)
            case .mallampati(let n): r.mallampati = n
            case .airwaySign(let s): r.airwaySigns.insert(s)
            case .dentition(let t): r.dentition = joined(r.dentition, t)
            case .currentAirway(let id, let detail, let depth):
                r.currentAirway = id
                if id == "ett" {
                    if !detail.isEmpty { r.ettSize = detail }
                    if !depth.isEmpty { r.ettDepth = depth }
                } else if id == "trach", !detail.isEmpty {
                    r.trachType = detail
                }
            case .vent(let v): r.vent = mergedVent(r.vent, v)
            case .oxygen(let o): r.oxygen = mergedOxygen(r.oxygen, o)
            case .devices(let ds):
                let add = newDevices(ds, in: r)
                r.devices += add
            case .otherHistory(let t): r.otherHistory = joined(r.otherHistory, t)
            case .codeStatus(let s, let polst, let plan): PatientCodeStatus.apply(s, polst: polst, plan: plan, to: &r)
            case .intraopLabs(let set):
                if let i = r.intraopLabs.firstIndex(where: { $0.id == set.id }) {
                    for (k, v) in set.values { r.intraopLabs[i].values[k] = v }
                } else {
                    r.intraopLabs.append(set)
                }
            case .blood(let k, let n): r.fluids[k] = (r.fluids[k] ?? 0) + n
            case .intraopInfusion(let drug, let rate):
                if let it = infusionItem(drug, rate) {
                    InfusionEntry.apply([it], to: &r.infusions)
                } else if let i = r.infusions.firstIndex(where: { $0.drug.caseInsensitiveCompare(drug) == .orderedSame }) {
                    if !rate.isEmpty { r.infusions[i].rate = rate }
                } else {
                    r.infusions.append(PatientInfusion(drug: drug.prefix(1).uppercased() + drug.dropFirst(), rate: rate))
                }
            case .intraopAirway(let key, let value): r.setIntraopAirway(key, value)
            case .typeScreen(let ts): r.typeScreen = ts.merged(over: r.typeScreen)
            case .infectious(let id, let name, let v): LabResults.set(id, name: name, v, in: &r)
            }
        }
        // Ids a finding added that the History details hold (an aneurysm, severe valve disease) go to their place.
        PatientHistoryDetails.migrate(&r)
    }

    /// What My Patient still lacks, in the order its editors ask for it.
    static func missing(_ r: PatientRecord) -> [String] {
        var out: [String] = []
        if r.ageYears == nil { out.append("age") }
        if r.sex == nil { out.append("sex") }
        if r.heightCm == nil { out.append("height") }
        if r.weightKg == nil { out.append("weight") }
        if blank(r.procedure) { out.append("procedure") }
        if r.urgency == nil { out.append("urgency") }
        if r.anesthetic.isEmpty { out.append("planned anesthetic") }
        if r.vitals.isEmpty { out.append("vital signs") }
        if r.problems.isEmpty && !r.noHistory && blank(r.otherHistory) { out.append("medical history") }
        if blank(r.medications) && r.medFlags.isEmpty && r.homeMeds.allSatisfy({ blank($0.name) }) { out.append("medications") }
        if !r.nkda && recordedAllergies(r).isEmpty { out.append("allergies") }
        if r.smoking == nil { out.append("smoking") }
        if r.lastSolids == nil || r.lastClears == nil { out.append("last intake") }
        if r.mets == nil { out.append("functional capacity") }
        if r.mallampati == nil { out.append("Mallampati") }
        return out
    }

    private static func same(_ a: Double, _ b: Double) -> Bool { Swift.abs(a - b) < 0.05 }

    /// A drip on the infusion list, as the Infusions groups' reader holds it (1.8.1): filed and compared by the drug, so
    /// "norepinephrine" updates a row written "Norepinephrine (Levophed)" instead of adding a second. Nil for a drug not
    /// on the list, which is matched by its name as before.
    private static func infusionItem(_ drug: String, _ rate: String) -> InfusionEntry.Item? {
        guard let id = InfusionEntry.drugID(of: drug) else { return nil }
        return InfusionEntry.Item(drugID: id, drug: drug.prefix(1).uppercased() + drug.dropFirst(), rate: rate, typed: drug)
    }

    private static func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The allergies a record holds, typed before 1.9 or on the 1.9 list, as one text ("" when none).
    private static func recordedAllergies(_ r: PatientRecord) -> String {
        let typed = r.allergies.trimmingCharacters(in: .whitespacesAndNewlines)
        let listed = r.allergyList.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return ([typed].filter { !$0.isEmpty } + listed).joined(separator: ", ")
    }

    private static func mentions(_ field: String, _ t: String) -> Bool {
        let n = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return !n.isEmpty && field.localizedCaseInsensitiveContains(n)
    }

    private static func joined(_ old: String, _ new: String) -> String {
        let n = new.trimmingCharacters(in: .whitespacesAndNewlines)
        let o = old.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || o.localizedCaseInsensitiveContains(n) { return old }
        return o.isEmpty ? n : o + "; " + n
    }
}

extension PatientRecord {
    /// Where a new last-intake time starts: the midnight just past, since the usual instruction is nothing by mouth
    /// after midnight. The user changes it to what the patient reports.
    static func npoMidnight(_ now: Date = Date()) -> Date { Calendar.current.startOfDay(for: now) }
}
