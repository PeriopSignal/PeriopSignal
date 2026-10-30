import Foundation

// MARK: - Fill from a note
//
// A typed or dictated note read into My Patient by fixed rules, on the phone: nothing is sent anywhere and the note
// itself is not kept. Each thing recognized becomes a finding the user confirms before it is added. Negated mentions
// ("denies chest pain", "no history of stroke"), family history ("father had an MI") and past events ("history of
// ACS") are not read as the patient's current problems. What nothing was read from is offered for Other conditions
// or, from a surgical or anesthetic history, for the anesthesia-history details.

enum PatientNoteChange: Hashable {
    case age(Double), sex(PatientSex), height(Double), weight(Double)
    case procedure(String), urgency(PatientUrgency), anesthetic(String), asa(Int, Bool)
    case problem(String), noHistory, smoking(String)
    case medFlag(String), medications(String)
    case nkda, allergies(String)
    case anesthesiaHistory(String), anesthesiaNotes(String)
    case vital(String, Double), lab(String, Double)
    case lastSolids(Date), lastClears(Date)
    case mets(String), frail, symptom(String), acute(String)
    case mallampati(Int), airwaySign(String), dentition(String)
    case otherHistory(String)
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

    init(_ id: String, _ p: String, family: Bool = false, onlyIf: NoteRx? = nil, notIf: NoteRx? = nil) {
        self.id = id
        rx = NoteRx(p)
        self.family = family
        self.onlyIf = onlyIf
        self.notIf = notIf
    }
}

/// What one sentence gave: findings, and every stretch of it that was read (findings, negations, family history),
/// so the rest can be offered as leftovers.
private struct Hits {
    var findings: [PatientNoteFinding] = []
    var ranges: [NSRange] = []

    mutating func add(_ f: PatientNoteFinding, at r: NSRange) {
        findings.append(f)
        ranges.append(r)
    }

    mutating func seen(_ r: NSRange) { ranges.append(r) }
}

enum PatientNote {
    /// The review groups, in the order My Patient's editors ask for them.
    enum Part {
        static let patient = "Patient", procedure = "Procedure", vitals = "Vital signs", history = "History",
                   meds = "Medications and allergies", anesthesia = "Anesthesia history", intake = "Last intake",
                   labs = "Labs", assessment = "Assessment", airway = "Airway"
    }

    static let sections = [Part.patient, Part.procedure, Part.vitals, Part.history, Part.meds, Part.anesthesia, Part.intake,
                           Part.labs, Part.assessment, Part.airway]

    /// A made-up note for "Try an example" and the screenshots (no identifiers).
    static let example = "68 yo M presenting for elective laparoscopic right hemicolectomy under general anesthesia. PMH: HTN, T2DM on insulin, OSA on CPAP, CAD s/p DES to LAD 2021, hereditary angioedema. Denies chest pain or SOB. Climbs 2 flights of stairs without stopping. Meds: metoprolol, lisinopril, glargine, aspirin, clopidogrel. Allergies: penicillin (rash). Former smoker. Ht 178 cm, Wt 96 kg. BP 148/86, HR 72, SpO2 95%. Hb 12.8, Cr 1.1, K 4.3. Mallampati 3, thick neck. NPO after midnight. PSH: appendectomy 2010 under GA, uneventful."

    // MARK: Rules

    private static let stentCardiac = NoteRx(#"\b(?:cad|coronary|cardiac|heart|lad|rca|lcx|circumflex|mi|cath|angina|n?stemi|des|bms|pci)\b"#)
    private static let stentOther = NoteRx(#"\b(?:ureter|ureteral|ureteric|jj|double[- ]j|biliary|cbd|bile duct|pancrea|esophag|oesophag|trache|airway|bronch|carotid|renal|iliac|femoral|sfa|popliteal|colonic|duodenal|venous|svc|ivc|tips)"#)
    private static let within3Months = #"(?:\d{1,2} days? ago|(?:[1-9]|1[0-2]) weeks? ago|last (?:week|month)|this month|(?:1|2|one|two) months? ago)"#

    /// Problem-list items, by the catalog's ids. Abbreviations that are also words are matched in capitals only.
    private static let problemRules: [Rule] = [
        Rule("htn-poor", #"\b(?:poorly|badly|not well|sub-?optimally)[- ]controlled (?:hypertension|htn|blood pressure|bp)\b|\buncontrolled (?:hypertension|htn)\b|\b(?:hypertension|htn),? (?:poorly|badly|not well|sub-?optimally) controlled"#),
        Rule("htn", #"(?<!pulmonary )(?<!arterial )(?<!gestational )(?<!induced )(?<!portal )(?<!intracranial )\b(?:hypertension|htn)\b|high blood pressure"#),
        Rule("hyperlipidemia", #"hyperlipid(?:a)?emia|(?-i:\bHLD\b)|dyslipid(?:a)?emia|hypercholesterol(?:a)?emia|high cholesterol"#),
        Rule("cad-recent", #"\b(?:recent|new) (?:mi|myocardial infarction|n?stemi|acs|acute coronary syndrome|heart attack)\b|\b(?:mi|n?stemi|myocardial infarction|heart attack|acs)\s+"# + within3Months),
        Rule("cad", #"\bcad\b|coronary artery disease|coronary (?:heart )?disease|ischemic heart disease|(?-i:\bIHD\b)|\b(?:prior|previous|old|remote|history of|hx of|h/o|s/p) (?:mi|myocardial infarction|n?stemi|heart attack|acs)\b|\bn?stemi\b|\bmyocardial infarction\b|(?<!mild )(?<!trace )(?<!moderate )(?<!severe )(?-i:\bMI\b)"#),
        Rule("pci-recent", #"\b(?:recent|new) (?:coronary )?(?:stents?|(?-i:DES|PCI))\b|\b(?:stents?|(?-i:DES|PCI))(?: placed| to the [a-z]+)?\s+"# + within3Months, notIf: stentOther),
        Rule("pci", #"(?-i:\b(?:DES|BMS|PCI)\b)|percutaneous coronary|coronary stents?|cardiac stents?|\b(?:LAD|RCA|LCx|circumflex) stents?\b"#),
        Rule("pci", #"\bstents?(?:ed)?\b"#, onlyIf: stentCardiac, notIf: stentOther),
        Rule("cabg", #"\bcabg|coronary (?:artery )?bypass|\b(?:cardiac|heart|triple|quadruple|double) bypass"#),
        Rule("ischemia", #"(?:ongoing|active|current) (?:myocardial |cardiac )?ischemia"#),
        Rule("hf-decomp", #"decompensated (?:heart failure|hf|chf)|(?:chf|heart failure|hf) exacerbation|acute (?:on chronic )?(?:(?:systolic|diastolic) )?(?:heart failure|chf)|(?-i:\bADHF\b)"#),
        Rule("hf", #"heart failure|\bchf\b|\bhf[rpm]?ef\b|(?-i:\bHF\b)"#),
        Rule("valve-severe", #"\b(?:severe|critical) (?:aortic|mitral|tricuspid|pulmonic) (?:valve )?(?:stenosis|regurgitation|insufficiency)\b|\b(?:severe|critical) (?-i:(?:AS|MR|MS|AR|TR|AI))\b"#),
        Rule("as", #"aortic (?:valve )?stenosis|\b(?:mild|moderate|severe|critical)\s+(?-i:AS)\b"#),
        Rule("mr", #"mitral (?:valve )?(?:regurgitation|insufficiency)|\b(?:mild|moderate|severe|trace)\s+(?-i:MR)\b"#),
        Rule("prosthetic-valve", #"mechanical (?:aortic |mitral )?valve|prosthetic (?:heart )?valve|bioprosthetic|\b(?:s/p|status post|prior|previous|history of|hx of|h/o|old)\s+(?:(?-i:AVR|MVR|SAVR|TAVR|TAVI|TMVR)|valve replacement)\b|(?-i:\b(?:AVR|MVR|SAVR|TAVR|TAVI|TMVR))\s+(?:in\s+)?(?:19|20)\d\d\b"#),
        Rule("af", #"atrial fibrillation|atrial flutter|\ba[-. ]?fib\b|(?-i:\b(?:AF|AFL|PAF)\b)"#),
        Rule("arrhythmia", #"(?-i:\b(?:SVT|WPW|VT)\b)|ventricular tachycardia|heart block|long qt|\barrhythmias?\b|bradyarrhythmia|sick sinus"#),
        Rule("pacemaker", #"pacemaker|(?-i:\bPPM\b)"#),
        Rule("icd", #"(?-i:\b(?:ICD|AICD)\b)(?!-?\d)|defibrillator"#),
        Rule("pulm-htn-severe", #"severe pulmonary (?:arterial )?(?:hypertension|htn)|severe (?-i:\b(?:PH|PAH)\b)"#),
        Rule("pulm-htn", #"pulmonary (?:arterial )?(?:hypertension|htn)|(?-i:\bPAH\b)|\bphtn\b"#),
        Rule("pvd", #"(?-i:\b(?:PVD|PAD)\b)|peripheral (?:vascular|arterial) disease|claudication|aortic aneurysm|(?-i:\bAAA\b)"#),
        Rule("chd-elevated", #"\bfontan\b|single ventricle|cyanotic (?:congenital|heart)|transposition of the great|(?-i:\b(?:TGA|HLHS)\b)|truncus arteriosus|eisenmenger|hypoplastic left heart"#),
        Rule("chd", #"congenital heart|atrial septal defect|ventricular septal defect|(?-i:\b(?:VSD|TOF)\b)|tetralogy|coarctation|ebstein"#),
        Rule("fh-cad", #"(?:family history|fhx|(?-i:\bFH\b))(?: of|:)? (?:premature )?(?:cad|coronary|mi\b|heart attack|heart disease)|\b(?:father|mother|brother|sister|parent)s? (?:had|has|with|died of|died from) (?:an? )?(?:mi\b|heart attack|cad\b|coronary)"#, family: true),
        Rule("asthma", #"\basthma|reactive airway"#),
        Rule("copd", #"\bcopd\b|emphysema|chronic bronchitis"#),
        Rule("cpap", #"\bc-?pap\b|\bbi-?pap\b|\bapap\b"#),
        Rule("osa", #"(?-i:\bOSA\b)|obstructive sleep apn(?:o)?ea|sleep apn(?:o)?ea"#),
        Rule("snoring", #"\bsnor(?:e|es|ed|er|ing)\b"#),
        Rule("tired", #"daytime (?:sleepiness|somnolence|fatigue|tiredness)"#),
        Rule("observed-apnea", #"(?:observed|witnessed) (?:apn(?:o)?eas?|choking)|stops breathing (?:at night|in (?:his|her|their) sleep)"#),
        Rule("uri", #"(?-i:\bURI\b)|upper respiratory (?:tract )?infection|(?:recent|current) (?:cold|cough|chest infection|bronchitis|pneumonia|respiratory infection|covid|flu)"#),
        Rule("home-o2", #"home (?:oxygen|o2)|oxygen at home|o2 at home|\d+(?:\.\d+)? ?l(?:pm)? (?:nc )?at home"#),
        Rule("ild", #"(?-i:\b(?:ILD|IPF)\b)|interstitial lung disease|pulmonary fibrosis"#),
        Rule("cva-recent", #"\b(?:recent|new) (?:stroke|cva|tia)\b|\b(?:stroke|cva|tia)\s+"# + within3Months),
        Rule("cva", #"\bstroke\b|\bcva\b|(?-i:\bTIA\b)|transient ischemic attack"#),
        Rule("ich-mass", #"(?:intracranial|intracerebral|subdural|epidural) (?:hemorrhage|haemorrhage|bleed|hematoma) with (?:mass effect|midline shift)"#),
        Rule("raised-icp", #"(?:raised|elevated|increased|high) (?:icp|intracranial pressure)|brain (?:tumou?r|mass)|intracranial mass"#),
        Rule("seizure", #"\bseizures?\b|epilepsy"#),
        Rule("dementia", #"dementia|alzheimer|cognitive impairment"#),
        Rule("parkinson", #"parkinson"#),
        Rule("neuromuscular", #"myasthenia|muscular dystrophy|(?-i:\bALS\b)|amyotrophic|guillain|neuromuscular disease|myopathy|charcot-marie|myotonic"#),
        Rule("sci", #"spinal cord injury|paraplegi|quadriplegi|tetraplegi"#),
        Rule("chronic-pain", #"chronic (?:back )?pain|opioid[- ]tolerant|chronic opioids|fibromyalgia"#),
        Rule("esrd-dialysis", #"\b(?:on|receives?|getting|undergoes|undergoing) (?:hemo|peritoneal )?dialysis|\bon (?-i:(?:HD|PD|CAPD|CCPD))\b|\bdialysis (?:m/?w/?f|mwf|tts|t/?th/?s|three times)|(?-i:\bHD\b) (?:m/?w/?f|mwf|tts|t/?th/?s)|peritoneal dialysis|\bhemodialysis\b"#),
        Rule("aki", #"(?-i:\bAKI\b)|acute kidney injury|acute renal failure|(?-i:\b(?:ESRD|ESKD)\b),? (?:not on|without|declines|refuses|no) (?:scheduled )?dialysis"#),
        Rule("ckd", #"(?-i:\b(?:CKD|CRI|CRF|ESRD|ESKD)\b)|chronic kidney disease|chronic renal (?:insufficiency|failure|disease)|renal insufficiency|end[- ]stage (?:renal|kidney)"#),
        Rule("gerd", #"\bgerd\b|(?<!vesicoureteral )(?<!vesicoureteric )\breflux\b|hiatal hernia|heartburn"#),
        Rule("full-stomach", #"(?:small |large )?bowel obstruction|(?-i:\b(?:SBO|LBO)\b)|full stomach|\bileus\b"#),
        Rule("gastroparesis", #"gastroparesis"#),
        Rule("hepatitis-active", #"(?:active|acute) hepatitis"#),
        Rule("cirrhosis", #"cirrhosis|(?-i:\bESLD\b)|end[- ]stage liver"#),
        Rule("dm-poor", #"(?:poorly|badly|not well|sub-?optimally)[- ]controlled (?:diabetes|dm|t2dm|t1dm|sugars|blood sugars|glucose)|uncontrolled (?:diabetes|dm|t2dm|t1dm)|(?:diabetes|dm|t2dm),? (?:poorly|badly|not well|sub-?optimally) controlled"#),
        Rule("insulin", #"insulin[- ](?:dependent|requiring|treated)|\bon insulin\b|(?-i:\b(?:IDDM|T1DM|DM1)\b)|type (?:1|one|i) (?:diabetes|dm)"#),
        Rule("dm", #"(?<!gestational )\bdiabet(?:es|ic)\b(?! insipidus)|(?-i:\b(?:DM|T2DM|T1DM|NIDDM|IDDM|DM2|DMII|DM1)\b)"#),
        Rule("thyroid", #"hypothyroid|hyperthyroid|thyroid disease|hashimoto|graves"#),
        Rule("adrenal", #"adrenal insufficiency|addison|chronic (?:steroids|prednisone)|(?:on|takes) (?:daily |chronic )?(?:prednisone|steroids|hydrocortisone)"#),
        Rule("anemia", #"\ban(?:a)?emi(?:a|c)\b"#),
        Rule("bleeding", #"bleeding disorder|von willebrand|(?-i:\b(?:vWD|VWD|ITP)\b)|h(?:a)?emophilia|coagulopathy|bleeding diathesis"#),
        Rule("vte", #"(?-i:\b(?:DVT|VTE)\b)|deep vein thrombosis|pulmonary embol"#),
        Rule("sickle", #"sickle cell(?! trait)|(?-i:\bHbSS\b)"#),
        Rule("dic", #"(?-i:\bDIC\b)|disseminated intravascular"#),
        Rule("declines-blood", #"jehovah|(?:declines|refuses) (?:all )?(?:blood|transfusion)|no blood products"#),
        Rule("thrombophilia", #"thrombophilia|factor v leiden|antiphospholipid|prothrombin gene mutation|protein [cs] deficiency|antithrombin deficiency"#),
        Rule("sepsis", #"\bsepsis\b|\bseptic\b(?!\s+(?:arthritis|joint|knee|hip|bursitis|emboli))"#),
        Rule("shock", #"(?:septic|cardiogenic|hemorrhagic|haemorrhagic|hypovolemic|distributive) shock|\bin shock\b"#),
        Rule("massive-trauma", #"massive trauma|polytrauma|multi-?trauma|multiple trauma"#),
        Rule("ruptured-aneurysm", #"ruptured (?:(?-i:AAA)|aneurysm|aortic aneurysm|abdominal aortic|thoracic aortic)|(?-i:\brAAA\b)"#),
        Rule("pregnant", #"\bpregnant\b|(?-i:\bG\d{1,2} ?P\d)|\b\d{1,2}(?:\+\d/7| \d/7)? (?:weeks|wks)'? (?:gestation|pregnant|(?-i:GA)|gestational age)\b|(?-i:\bIUP\b)|\bparturient\b|\bin (?:active )?labou?r\b|\blabou?ring\b"#),
        Rule("gest-htn", #"gestational hypertension|(?-i:\b(?:gHTN|GHTN|PIH)\b)|pregnancy[- ]induced hypertension"#),
        Rule("preeclampsia-severe", #"pre-?eclampsia with severe features|severe pre-?eclampsia"#),
        Rule("preeclampsia", #"pre-?eclampsia"#),
        Rule("hellp", #"(?-i:\bHELLP\b)"#),
        Rule("gdm-complex", #"(?:gestational diabetes|(?-i:GDM)) (?:on|requiring|treated with|managed with) insulin|(?-i:\b(?:A2GDM|GDMA2)\b)"#),
        Rule("gdm-diet", #"gestational diabetes|(?-i:\b(?:GDM|A1GDM|GDMA1)\b)"#),
        Rule("previa-accreta", #"placenta (?:previa|praevia|accreta|increta|percreta)|accreta spectrum"#),
        Rule("peripartum-cm", #"peripartum cardiomyopathy|(?-i:\bPPCM\b)"#),
        Rule("uterine-rupture", #"uterine rupture|ruptured uterus"#),
        Rule("ra", #"rheumatoid"#),
        Rule("spine-fusion", #"ankylosing spondylitis|cervical (?:spine )?fusion|(?-i:\bACDF\b)|fused (?:cervical|neck)"#),
        Rule("cspine-unstable", #"unstable (?:c-?spine|cervical spine)"#),
        Rule("scoliosis", #"scoliosis"#),
        Rule("alcohol-abuse", #"alcohol (?:abuse|use disorder|dependence)|alcoholism|\betoh (?:abuse|use disorder|dependence)|heavy (?:drinker|drinking|alcohol|etoh)|drinks (?:heavily|daily)|\b\d+ (?:beers|drinks) (?:a|per) day"#),
        Rule("alcohol-social", #"(?:social|occasional|rare) (?:alcohol|drinker|etoh|drinking)|drinks (?:socially|occasionally)|etoh socially"#),
        Rule("substance", #"cocaine|methamphetamine|\bmeth\b|heroin|(?-i:\b(?:IVDU|IVDA|OUD)\b)|opioid use disorder|substance (?:use|abuse)|stimulant use|on methadone|on buprenorphine|suboxone"#),
    ]

    /// A general item and the more specific ones that replace it ("hypertension, well controlled" by "poorly
    /// controlled").
    static let supersededBy: [String: [String]] = [
        "htn": ["htn-poor"], "dm": ["dm-poor"], "cad": ["cad-recent"], "pci": ["pci-recent"], "cva": ["cva-recent"],
        "hf": ["hf-decomp"], "ef-moderate": ["ef-severe"], "pulm-htn": ["pulm-htn-severe"], "chd": ["chd-elevated"],
        "ckd": ["esrd-dialysis"], "gdm-diet": ["gdm-complex"], "alcohol-social": ["alcohol-abuse"],
        "preeclampsia": ["preeclampsia-severe", "hellp"], "gest-htn": ["preeclampsia", "preeclampsia-severe", "hellp"],
    ]

    /// Items whose catalog wording says more than a note usually does.
    private static let cautions: [String: String] = [
        "htn": "Added as well controlled; choose poorly controlled in History if not.",
        "dm": "Added as well controlled; choose poorly controlled in History if not.",
        "cad": "Added as over 3 months ago; choose within 3 months in History if recent.",
        "pci": "Added as over 3 months ago; choose within 3 months in History if recent.",
        "cva": "Added as over 3 months ago; choose within 3 months in History if recent.",
        "fh-cad": "Counts if premature: a male relative under 55 or a female relative under 65.",
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
        add("", ["metformin", "glipizide", "glyburide", "glimepiride", "sitagliptin", "januvia", "pioglitazone", "atorvastatin", "lipitor", "rosuvastatin", "crestor", "simvastatin", "pravastatin", "ezetimibe", "amlodipine", "norvasc", "nifedipine", "diltiazem", "verapamil", "hydralazine", "furosemide", "lasix", "torsemide", "bumetanide", "hydrochlorothiazide", "hctz", "chlorthalidone", "spironolactone", "eplerenone", "digoxin", "amiodarone", "flecainide", "isosorbide", "nitroglycerin", "levothyroxine", "synthroid", "omeprazole", "pantoprazole", "esomeprazole", "famotidine", "albuterol", "tiotropium", "fluticasone", "budesonide", "montelukast", "gabapentin", "pregabalin", "sertraline", "escitalopram", "citalopram", "fluoxetine", "paroxetine", "bupropion", "venlafaxine", "duloxetine", "trazodone", "quetiapine", "olanzapine", "risperidone", "lithium", "levetiracetam", "keppra", "lamotrigine", "valproate", "carbamazepine", "phenytoin", "carbidopa", "levodopa", "donepezil", "allopurinol", "tamsulosin", "finasteride", "acetaminophen", "tylenol", "ibuprofen", "naproxen", "celecoxib", "methotrexate", "colchicine", "clonidine", "terazosin", "doxazosin", "alprazolam", "lorazepam", "clonazepam", "diazepam", "zolpidem"])
        return d
    }()

    private static let drugRx: NoteRx = {
        let names = drugs.keys.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: "\\s+") }
        return NoteRx("\\b(" + names.joined(separator: "|") + ")\\b")
    }()

    // MARK: Context

    private static let negCue = NoteRx(#"\b(?:no|not|denies|denied|deny|negative for|neg for|without|never|free of|nor|r/o|rule out|ruled out|absent)\b"#)
    private static let negEnd = NoteRx(#"\b(?:but|however|although|though|except|apart from|aside from|positive for|significant for|notable for|reports|endorses|complains of|c/o|presents|admits|has|have|can|could|uses|takes|walks|climbs|lives|works)\b|[;:]|(?:,|\band\b)\s*(?:had|is|was|with|on|also)\b"#)
    private static let famCue = NoteRx(#"\b(?:family history|fhx|(?-i:FH)|mother|father|brother|sister|siblings?|parents?|grandmother|grandfather|grandparents?|aunt|uncle)\b"#)
    private static let famEnd = NoteRx(#"\b(?:patient|pt|he|she|they|himself|herself|personally|but|however|otherwise|whereas|own)\b|;|,\s*(?:has|have|had|is|was|also)\b"#)
    private static let pastBefore = NoteRx(#"\b(?:recent|recently|prior|previous|previously|history of|hx of|h/o|s/p|old|remote|resolved)\b[^.;]{0,20}$"#)
    private static let pastAfter = NoteRx(#"^[^.;]{0,15}\b(?:in (?:19|20)\d\d|\d+ (?:years?|yrs?|months?) ago|last year)\b"#)
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
        if let o = rule.onlyIf, o.first(c) == nil { return nil }
        if let n = rule.notIf, n.first(c) != nil { return nil }
        for m in rule.rx.all(c) {
            if negated(c, at: m.range.location) || (!rule.family && familyContext(c, at: m.range.location)) {
                h.seen(m.range)
                continue
            }
            return m
        }
        return nil
    }

    /// Every pattern, for the test that each one compiles.
    static var allPatterns: [NoteRx] {
        var out: [NoteRx] = (problemRules + anesthesiaRules + symptomRules + acuteRules + signRules).map(\.rx)
        out += [stentCardiac, stentOther, noHistoryRx, esrdRx, drugRx, negCue, negEnd, famCue, famEnd, pastBefore, pastAfter, pastCare, planClause, surgicalPiece]
        out += [ageRx, ageMonthsRx, ageWeeksRx, ageSexRx, maleRx, femaleRx, heightFtRx, heightCtxRx, heightMRx, heightCmRx, weightKgRx, weightLbRx, lossCue, bmiRx]
        out += [procedureHeaderRx, procedureRx, procedurePersonRx, procedureTechniqueRx, procedureLeadRx, procedureCut, emergencyRx, urgentRx, timeSensitiveRx, electiveRx, plannedRx, gaRx, neuraxialRx, macRx, regionalRx, asaRx]
        out += [smokeNeverRx, smokeFormerRx, smokeCurrentRx, medsHeaderRx, aspirinDoseRx, allergyCue, nkdaRx, allergyRx, allergyAfterRx, allergySkipRx, allergyCut, noneRx]
        out += [bpRx, hrRx, spo2Rx, onOxygenRx, rrRx, tempRx, efRx]
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
            if c == "\n" || (c == ";" && next.isWhitespace) || (c == "." && next.isWhitespace && !abbreviation) {
                flush()
            } else {
                cur.append(c)
            }
        }
        flush()
        return out
    }

    /// What the note says, as findings to confirm. `now` places "midnight" and clock times.
    static func read(_ text: String, now: Date = Date()) -> PatientNoteReading {
        var found: [String: PatientNoteFinding] = [:]
        var order: [String] = []
        var other: [String] = []
        var previous: [String] = []
        var names: [String] = []
        func put(_ f: PatientNoteFinding) {
            guard found[f.id] == nil else { return }
            found[f.id] = f
            if !order.contains(f.id) { order.append(f.id) }
        }
        func has(_ id: String) -> Bool { found[id] != nil }

        for c in clauses(text) {
            var h = Hits()
            readRules(c, &h)
            readPatient(c, &h)
            readProcedure(c, &h)
            readMeds(c, &h, names: &names)
            readAllergies(c, &h)
            readNumbers(c, &h)
            readAssessment(c, now: now, &h)
            for f in h.findings { put(f) }
            let pastClause = pastCare.first(c) != nil
            let pieces = planClause.first(c) != nil ? [] : leftovers(c, h.ranges, keepNegatives: pastClause)
            for piece in pieces {
                if pastClause || surgicalPiece.first(piece) != nil {
                    if !previous.contains(where: { $0.caseInsensitiveCompare(piece) == .orderedSame }) { previous.append(piece) }
                } else if !other.contains(where: { $0.caseInsensitiveCompare(piece) == .orderedSame }) {
                    other.append(piece)
                }
            }
        }

        // Insulin means diabetes treated with insulin; CPAP means sleep apnea.
        if has("flag:insulin"), !has("problem:insulin"), !has("problem:gdm-complex"), let l = problemLabels["insulin"] {
            put(PatientNoteFinding(id: "problem:insulin", section: Part.history, label: l, change: .problem("insulin"), note: "From the insulin in the medications."))
        }
        if has("problem:cpap"), !has("problem:osa"), let l = problemLabels["osa"] {
            put(PatientNoteFinding(id: "problem:osa", section: Part.history, label: l, change: .problem("osa"), note: "From the CPAP or BiPAP."))
        }
        // The more specific item replaces the general one.
        for (general, specific) in supersededBy where has("problem:" + general) && specific.contains(where: { has("problem:" + $0) }) {
            found["problem:" + general] = nil
        }
        // ESRD: on dialysis, not on dialysis, or not said.
        if esrdRx.first(text) != nil {
            if has("problem:aki") || has("problem:esrd-dialysis") {
                found["problem:ckd"] = nil
            } else if var ckd = found["problem:ckd"] {
                ckd.note = "The note says ESRD: in History, choose on scheduled dialysis or not on scheduled dialysis instead."
                found["problem:ckd"] = ckd
            }
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
                                  identifiers: identifiers(text))
    }

    private static let problemLabels: [String: String] = Dictionary(PatientCatalog.allProblems.map { ($0.id, $0.label) }, uniquingKeysWith: { a, _ in a })

    private static func readRules(_ c: String, _ h: inout Hits) {
        for rule in problemRules {
            guard let m = accepted(rule, in: c, &h), let label = problemLabels[rule.id] else { continue }
            h.add(PatientNoteFinding(id: "problem:" + rule.id, section: Part.history, label: label, change: .problem(rule.id), note: cautions[rule.id]), at: m.range)
        }
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

    private static func number(_ m: NSTextCheckingResult, _ groups: [Int], _ s: String) -> Double? {
        guard let t = m.text(groups, in: s) else { return nil }
        return Double(t.replacingOccurrences(of: ",", with: ""))
    }

    // MARK: Patient

    static let ageRx = NoteRx(#"\b(\d{1,3})\s*-?\s*(?:y/?o\b|yo\b|y\.o\.?|(?:years?|yrs?)[- ]old\b)|\bage[sd]?\s*:?\s*(\d{1,3})\b"#)
    static let ageMonthsRx = NoteRx(#"\b(\d{1,2})\s*-?\s*(?:months?|mos?)[- ]old\b"#)
    static let ageWeeksRx = NoteRx(#"\b(\d{1,2})\s*-?\s*(?:weeks?|wks?)[- ]old\b"#)
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
        } else if let m = ageSexRx.first(c), let v = number(m, [1], c), v > 0, v < 120, let s = m.text(2, in: c) {
            h.add(PatientNoteFinding(id: "age", section: Part.patient, label: "Age " + NumText.short(v), change: .age(v)), at: m.range)
            let sex: PatientSex = s == "M" ? .male : .female
            h.add(PatientNoteFinding(id: "sex", section: Part.patient, label: sex.label, change: .sex(sex)), at: m.range)
        } else if let m = ageRx.first(c), let v = number(m, [1, 2], c), v > 0, v < 120 {
            h.add(PatientNoteFinding(id: "age", section: Part.patient, label: "Age " + NumText.short(v), change: .age(v)), at: m.range)
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

    private static func readProcedure(_ c: String, _ h: inout Hits) {
        let pastClause = pastCare.first(c) != nil
        var gotProcedure = false
        if !pastClause {
            for rx in [procedureHeaderRx, procedureRx, procedurePersonRx, procedureLeadRx, procedureTechniqueRx] {
                guard let m = rx.first(c), var p = m.text(1, in: c) else { continue }
                if let cut = procedureCut.first(p) { p = (p as NSString).substring(to: cut.range.location) }
                p = p.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;"))
                if p.count >= 3 && p.count <= 120 {
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

    private static func readMeds(_ c: String, _ h: inout Hits, names: inout [String]) {
        if let m = smokeNeverRx.first(c) {
            h.add(PatientNoteFinding(id: "smoking", section: Part.history, label: "Smoking: never", change: .smoking("never")), at: m.range)
        } else if let m = smokeFormerRx.first(c) {
            h.add(PatientNoteFinding(id: "smoking", section: Part.history, label: "Smoking: former", change: .smoking("former")), at: m.range)
        } else if let m = smokeCurrentRx.first(c), !negated(c, at: m.range.location) {
            h.add(PatientNoteFinding(id: "smoking", section: Part.history, label: "Smoking: current", change: .smoking("current")), at: m.range)
        }

        // Medicine names in an allergy sentence are allergies, not medicines.
        let allergySentence = allergyCue.first(c) != nil
        if !allergySentence, let m = medsHeaderRx.first(c), let raw = m.text([1, 2], in: c) {
            let list = raw.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;"))
            if !list.isEmpty {
                h.add(PatientNoteFinding(id: "meds", section: Part.meds, label: "Medication list: " + list, change: .medications(list)), at: m.range)
            }
        }
        for m in drugRx.all(c) {
            h.seen(m.range)
            guard !allergySentence, let raw = m.text(1, in: c) else { continue }
            let key = raw.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            if !names.contains(key) { names.append(key) }
            guard let flag = drugs[key], !flag.isEmpty, !negated(c, at: m.range.location),
                  let f = PatientCatalog.medFlags.first(where: { $0.id == flag }) else { continue }
            h.add(PatientNoteFinding(id: "flag:" + flag, section: Part.meds, label: "Takes: " + f.label.lowercased(), change: .medFlag(flag)), at: m.range)
        }
        // "ASA 81" is aspirin; "ASA III" is the physical status.
        if !allergySentence, let m = aspirinDoseRx.first(c) {
            if !names.contains("aspirin") { names.append("aspirin") }
            h.add(PatientNoteFinding(id: "flag:aspirin", section: Part.meds, label: "Takes: aspirin", change: .medFlag("aspirin")), at: m.range)
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
    static let onOxygenRx = NoteRx(#"^\s*%?\s*(?:on|with)\s+(?:\d+(?:\.\d+)?\s*(?:l\b|lpm|liters?)|o2|oxygen|nc\b|nasal cannula|bipap|cpap|hfnc|face ?mask|nrb)"#)
    static let rrRx = NoteRx(#"\b(?:rr|resp(?:iratory)? rate|resps)\s*(?:of|is|was|:|=)?\s*(\d{1,2})\b"#)
    static let tempRx = NoteRx(#"\b(?:temp|temperature|(?-i:T))\s*(?:of|is|was|:|=)?\s*(\d{2,3}(?:\.\d)?)\s*°?\s*([cf])?\b"#)
    static let efRx = NoteRx(#"\b(?:ef|lvef|ejection fraction)\s*(?:of|is|was|:|=|~|<|>|≤|≥)?\s*(\d{1,2})\s*(?:-|–|to)?\s*(\d{1,2})?\s*%"#)
    private static let value = #"(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)"#
    private static let labRules: [(id: String, rx: NoteRx, min: Double, max: Double)] = [
        ("hb", NoteRx(#"\b(?:hb|hgb|hemoglobin|haemoglobin)\s*(?:of|is|was|:|=)?\s*(\d{1,2}(?:\.\d)?)\b"#), 3, 25),
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

    private static func readNumbers(_ c: String, _ h: inout Hits) {
        if let m = bpRx.first(c), let s = number(m, [1], c), let d = number(m, [2], c) {
            vital("sbp", s, 50, 260, m.range, &h)
            vital("dbp", d, 20, 160, m.range, &h)
        }
        if let m = hrRx.first(c), let v = number(m, [1], c) { vital("hr", v, 20, 220, m.range, &h) }
        if let m = spo2Rx.first(c), let v = number(m, [1], c) {
            let after = (c as NSString).substring(from: m.range.location + m.range.length)
            let o2 = onOxygenRx.first(after) != nil
            vital("spo2", v, 50, 100, m.range, &h, note: o2 ? "The note gives it on oxygen; this field is SpO₂ on room air." : nil)
        }
        if let m = rrRx.first(c), let v = number(m, [1], c) { vital("rr", v, 4, 60, m.range, &h) }
        if let m = tempRx.first(c), var v = number(m, [1], c) {
            if m.text(2, in: c)?.lowercased() == "f" || v > 45 { v = ((v - 32) * 5 / 9 * 10).rounded() / 10 }
            vital("temp", v, 30, 43, m.range, &h)
        }
        for l in labRules {
            guard let m = l.rx.first(c), var v = number(m, [1, 2], c) else { continue }
            if l.id == "plt" && v >= 2000 { v /= 1000 }
            guard v >= l.min, v <= l.max, let f = PatientCatalog.labs.first(where: { $0.id == l.id }) else {
                h.seen(m.range)
                continue
            }
            let unit = f.unit.isEmpty ? "" : (f.unit == "%" ? "%" : " " + f.unit)
            h.add(PatientNoteFinding(id: "lab:" + l.id, section: Part.labs, label: f.label + " " + NumText.short(v) + unit, change: .lab(l.id, v)), at: m.range)
        }
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
    static let headerLead = NoteRx(#"^\s*(?:(?:pmhx?|pshx?|hpi|hx|history|past (?:medical|surgical) history|surgical history|medical history|ros|social history|sh|fhx?|family history|exam|pe|plan|assessment|a/p|other|significant for|notable for|known|history of|hx of|h/o)\b\s*[:\-–]?\s*)+"#)
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
    private static func leftovers(_ c: String, _ used: [NSRange], keepNegatives: Bool = false) -> [String] {
        let ns = c as NSString
        var pieces: [NSRange] = []
        var start = 0
        for cut in pieceBreak.all(c) {
            if cut.range.location > start { pieces.append(NSRange(location: start, length: cut.range.location - start)) }
            start = cut.range.location + cut.range.length
        }
        if start < ns.length { pieces.append(NSRange(location: start, length: ns.length - start)) }
        var out: [String] = []
        for p in pieces where !used.contains(where: { NSIntersectionRange($0, p).length > 0 }) {
            var t = ns.substring(with: p)
            if let head = headerLead.first(t) { t = (t as NSString).substring(from: head.range.location + head.range.length) }
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: " :;,.-–"))
            if !keepNegatives && negLead.first(t) != nil { continue }
            let words = t.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "/" }).map(String.init)
            guard words.contains(where: { $0.count >= 3 && !fillers.contains($0) && $0.contains(where: { $0.isLetter }) }) else { continue }
            out.append(t)
        }
        return out
    }

    // MARK: Identifiers

    private static let identifierRules: [(String, NoteRx)] = [
        ("a record number", NoteRx(#"\b(?:mrn|medical record|record (?:no|number|#)|patient id|acct|account (?:no|number)|nhs (?:no|number)|ssn|social security)\b|\b\d{7,}\b"#)),
        ("a date", NoteRx(#"\b(?:dob|d\.o\.b|date of birth|born on)\b|\b\d{1,2}[/.-]\d{1,2}[/.-](?:19|20)\d{2}\b"#)),
        ("a name", NoteRx(#"\b(?:Mr|Mrs|Ms|Miss|Mx)\.?\s+[A-Z][a-z]+"#, caseSensitive: true)),
        ("a name", NoteRx(#"\b(?:name is|named|patient name|pt name)\b"#)),
        ("a phone number", NoteRx(#"\b\d{3}[-. )]\s?\d{3}[-. ]\d{4}\b"#)),
    ]

    /// Kinds of identifier the text seems to hold, for a warning (nothing is removed automatically).
    static func identifiers(_ text: String) -> [String] {
        var out: [String] = []
        for (kind, rx) in identifierRules where !out.contains(kind) && rx.first(text) != nil { out.append(kind) }
        return out
    }

    // MARK: Status and adding

    static func status(_ f: PatientNoteFinding, in r: PatientRecord) -> PatientNoteStatus {
        switch f.change {
        case .age(let v):
            guard let o = r.ageYears else { return .new }
            return same(o, v) ? .recorded : .replaces("age " + NumText.short(o))
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
            return o.caseInsensitiveCompare(p) == .orderedSame ? .recorded : .replaces(o)
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
        case .nkda:
            if r.nkda { return .recorded }
            let a = r.allergies.trimmingCharacters(in: .whitespacesAndNewlines)
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
            return same(o, v) ? .recorded : .replaces(NumText.short(o))
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
        case .otherHistory(let t):
            return mentions(r.otherHistory, t) ? .recorded : .new
        }
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
            case .procedure(let p): r.procedure = p
            case .urgency(let u): r.urgency = u
            case .anesthetic(let a): r.anesthetic.insert(a)
            case .asa(let n, let e):
                r.asaClass = n
                if e { r.asaE = true }
            case .problem(let p):
                r.noHistory = false
                if (supersededBy[p] ?? []).contains(where: { r.problems.contains($0) }) { continue }
                r.problems.insert(p)
                for general in supersededBy.keys where (supersededBy[general] ?? []).contains(p) { r.problems.remove(general) }
            case .noHistory:
                if r.problems.isEmpty { r.noHistory = true }
            case .smoking(let s): r.smoking = s
            case .medFlag(let f): r.medFlags.insert(f)
            case .medications(let m): r.medications = joined(r.medications, m)
            case .nkda:
                if r.allergies.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { r.nkda = true }
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
            case .otherHistory(let t): r.otherHistory = joined(r.otherHistory, t)
            }
        }
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
        if blank(r.medications) && r.medFlags.isEmpty { out.append("medications") }
        if !r.nkda && blank(r.allergies) { out.append("allergies") }
        if r.smoking == nil { out.append("smoking") }
        if r.lastSolids == nil || r.lastClears == nil { out.append("last intake") }
        if r.mets == nil { out.append("functional capacity") }
        if r.mallampati == nil { out.append("Mallampati") }
        return out
    }

    private static func same(_ a: Double, _ b: Double) -> Bool { Swift.abs(a - b) < 0.05 }

    private static func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
