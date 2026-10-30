import Foundation

// MARK: - The choices My Patient offers: problems by system, medication and anesthesia-history flags, airway signs.
//
// `asa` marks a problem the ASA's own adult or obstetric examples place in a class, and `peds` one its pediatric
// examples do (ASA Physical Status Classification System, last amended December 13, 2020, which added the pediatric
// and obstetric examples); the tab suggests the highest class among them and the clinician confirms.
// `rcri`, `stopBang`, `ariscat` mark the score items a problem answers, so a calculator opens pre-filled.

struct PatientProblem: Hashable, Identifiable {
    var id: String
    var label: String
    /// The ASA class this problem is an example of, when the ASA's examples name it.
    var asa: Int?
    /// The ASA example it matches, quoted in the suggestion's reasons.
    var asaExample: String?
    /// The class the ASA's pediatric examples give it, for a patient under 18.
    var peds: Int?
    var pedsExample: String?
    /// The RCRI item it answers ("ihd", "hf", "cva", "insulin").
    var rcri: String?
    /// The STOP-Bang item it answers ("snoring", "tired", "observed", "pressure").
    var stopBang: String?

    init(_ id: String, _ label: String, asa: Int? = nil, asaExample: String? = nil, peds: Int? = nil, pedsExample: String? = nil, rcri: String? = nil, stopBang: String? = nil) {
        self.id = id; self.label = label; self.asa = asa; self.asaExample = asaExample; self.peds = peds; self.pedsExample = pedsExample
        self.rcri = rcri; self.stopBang = stopBang
    }
}

struct PatientSystem: Hashable, Identifiable {
    var id: String
    var name: String
    /// SF Symbol.
    var icon: String
    var problems: [PatientProblem]
}

/// A number field with its unit (labs, vital signs, fluids).
struct PatientField: Hashable, Identifiable {
    var id: String
    var label: String
    var unit: String
    init(_ id: String, _ label: String, _ unit: String) { self.id = id; self.label = label; self.unit = unit }
}

struct PatientFlag: Hashable, Identifiable {
    var id: String
    var label: String
    var detail: String?
    init(_ id: String, _ label: String, _ detail: String? = nil) { self.id = id; self.label = label; self.detail = detail }
}

enum PatientCatalog {
    static let systems: [PatientSystem] = [
        PatientSystem(id: "cv", name: "Cardiovascular", icon: "heart", problems: [
            PatientProblem("htn", "Hypertension, well controlled", asa: 2, asaExample: "well-controlled DM/HTN", stopBang: "pressure"),
            PatientProblem("htn-poor", "Hypertension, poorly controlled", asa: 3, asaExample: "poorly controlled DM or HTN", stopBang: "pressure"),
            // 2024 AHA/ACC §6.2 (p e373): "recent history of poorly controlled hypertension (SBP ≥180 mm Hg or DBP ≥110
            // mm Hg before the day of surgery)".
            PatientProblem("htn-180", "Recent BP 180/110 or more, before the day of surgery", asa: 3, asaExample: "poorly controlled DM or HTN", stopBang: "pressure"),
            PatientProblem("hyperlipidemia", "High cholesterol"),
            PatientProblem("cad", "Coronary disease or MI, over 3 months", asa: 3, asaExample: "history (>3 months) of MI, CVA, TIA, or CAD/stents", rcri: "ihd"),
            PatientProblem("pci", "Coronary stent, over 3 months", asa: 3, asaExample: "history (>3 months) of MI, CVA, TIA, or CAD/stents", rcri: "ihd"),
            PatientProblem("pci-recent", "Coronary stent within 3 months", asa: 4, asaExample: "recent (<3 months) MI, CVA, TIA or CAD/stents", rcri: "ihd"),
            PatientProblem("cad-recent", "MI or ACS within 3 months", asa: 4, asaExample: "recent (<3 months) MI, CVA, TIA or CAD/stents", rcri: "ihd"),
            PatientProblem("ischemia", "Ongoing cardiac ischemia", asa: 4, asaExample: "ongoing cardiac ischemia", rcri: "ihd"),
            PatientProblem("cabg", "Prior CABG", asa: 3, asaExample: "history (>3 months) of MI, CVA, TIA, or CAD/stents", rcri: "ihd"),
            PatientProblem("hf", "Heart failure", peds: 4, pedsExample: "congestive heart failure", rcri: "hf"),
            PatientProblem("hf-decomp", "Decompensated heart failure", peds: 5, pedsExample: "decompensated congestive heart failure", rcri: "hf"),
            PatientProblem("ef-moderate", "Ejection fraction moderately reduced", asa: 3, asaExample: "moderate reduction of ejection fraction"),
            PatientProblem("ef-severe", "Ejection fraction severely reduced", asa: 4, asaExample: "severe reduction of ejection fraction"),
            PatientProblem("valve-severe", "Severe valve disease", asa: 4, asaExample: "severe valve dysfunction"),
            PatientProblem("as", "Aortic stenosis"),
            PatientProblem("mr", "Mitral regurgitation"),
            PatientProblem("prosthetic-valve", "Prosthetic valve"),
            PatientProblem("af", "Atrial fibrillation or flutter"),
            PatientProblem("arrhythmia", "Other significant arrhythmia"),
            PatientProblem("pacemaker", "Pacemaker", asa: 3, asaExample: "implanted pacemaker"),
            PatientProblem("icd", "Implanted defibrillator (ICD)", peds: 4, pedsExample: "automatic implantable cardioverter-defibrillator"),
            PatientProblem("pulm-htn", "Pulmonary hypertension"),
            PatientProblem("pulm-htn-severe", "Severe pulmonary hypertension"),
            PatientProblem("pvd", "Peripheral vascular disease"),
            PatientProblem("chd", "Congenital heart disease"),
            // 2024 AHA/ACC Table 10: single ventricle or Fontan, cyanotic disease, TGA and similar lesions.
            PatientProblem("chd-elevated", "Congenital heart disease, elevated-risk lesion"),
            PatientProblem("fh-cad", "Family history of premature coronary disease"),
        ]),
        PatientSystem(id: "resp", name: "Respiratory", icon: "lungs", problems: [
            PatientProblem("lung-mild", "Mild lung disease", asa: 2, asaExample: "mild lung disease"),
            PatientProblem("asthma", "Asthma", peds: 2, pedsExample: "asthma without exacerbation"),
            PatientProblem("copd", "COPD", asa: 3, asaExample: "COPD"),
            PatientProblem("osa", "Obstructive sleep apnea", peds: 2, pedsExample: "mild/moderate OSA"),
            PatientProblem("cpap", "Uses CPAP or BiPAP"),
            PatientProblem("snoring", "Loud snoring", stopBang: "snoring"),
            PatientProblem("tired", "Daytime tiredness or sleepiness", stopBang: "tired"),
            PatientProblem("observed-apnea", "Observed apnea or choking in sleep", stopBang: "observed"),
            PatientProblem("uri", "Respiratory infection in the last month"),
            PatientProblem("home-o2", "Home oxygen"),
            PatientProblem("ild", "Interstitial lung disease"),
        ]),
        PatientSystem(id: "neuro", name: "Neurologic", icon: "brain.head.profile", problems: [
            PatientProblem("cva", "Stroke or TIA, over 3 months", asa: 3, asaExample: "history (>3 months) of MI, CVA, TIA, or CAD/stents", rcri: "cva"),
            PatientProblem("cva-recent", "Stroke or TIA within 3 months", asa: 4, asaExample: "recent (<3 months) MI, CVA, TIA or CAD/stents", rcri: "cva"),
            PatientProblem("ich-mass", "Intracranial bleed with mass effect", asa: 5, asaExample: "intracranial bleed with mass effect", peds: 5, pedsExample: "intracranial hemorrhage with mass effect"),
            PatientProblem("raised-icp", "Intracranial mass or raised ICP"),
            PatientProblem("seizure", "Seizure disorder", peds: 2, pedsExample: "well-controlled epilepsy"),
            PatientProblem("dementia", "Dementia or cognitive impairment"),
            PatientProblem("parkinson", "Parkinson disease"),
            PatientProblem("neuromuscular", "Neuromuscular disease"),
            PatientProblem("sci", "Spinal cord injury"),
            PatientProblem("chronic-pain", "Chronic pain or opioid tolerance"),
        ]),
        PatientSystem(id: "renal", name: "Renal", icon: "drop", problems: [
            PatientProblem("ckd", "Chronic kidney disease", peds: 3, pedsExample: "renal failure"),
            PatientProblem("esrd-dialysis", "ESRD on regularly scheduled dialysis", asa: 3, asaExample: "ESRD undergoing regularly scheduled dialysis", peds: 3, pedsExample: "renal failure"),
            PatientProblem("aki", "Acute kidney injury, or ESRD not on scheduled dialysis", asa: 4, asaExample: "ARD or ESRD not undergoing regularly scheduled dialysis", peds: 3, pedsExample: "renal failure"),
        ]),
        PatientSystem(id: "gi", name: "GI and liver", icon: "cross.case", problems: [
            PatientProblem("gerd", "Reflux or hiatal hernia"),
            PatientProblem("full-stomach", "Full stomach or bowel obstruction"),
            PatientProblem("gastroparesis", "Gastroparesis"),
            PatientProblem("hepatitis-active", "Active hepatitis", asa: 3, asaExample: "active hepatitis"),
            PatientProblem("cirrhosis", "Cirrhosis"),
        ]),
        PatientSystem(id: "endo", name: "Endocrine", icon: "flask", problems: [
            PatientProblem("dm", "Diabetes, well controlled", asa: 2, asaExample: "well-controlled DM/HTN", peds: 2, pedsExample: "non-insulin-dependent diabetes mellitus"),
            PatientProblem("dm-poor", "Diabetes, poorly controlled", asa: 3, asaExample: "poorly controlled DM or HTN"),
            PatientProblem("insulin", "Diabetes treated with insulin", peds: 3, pedsExample: "insulin-dependent diabetes mellitus", rcri: "insulin"),
            PatientProblem("thyroid", "Thyroid disease"),
            PatientProblem("adrenal", "Adrenal insufficiency or chronic steroids"),
        ]),
        PatientSystem(id: "heme", name: "Hematologic", icon: "drop.triangle", problems: [
            PatientProblem("anemia", "Anemia"),
            PatientProblem("bleeding", "Bleeding disorder or coagulopathy"),
            PatientProblem("vte", "DVT or PE"),
            PatientProblem("sickle", "Sickle cell disease"),
            PatientProblem("dic", "DIC", asa: 4, asaExample: "DIC", peds: 4, pedsExample: "disseminated intravascular coagulation"),
            PatientProblem("declines-blood", "Declines blood products"),
        ]),
        PatientSystem(id: "acute", name: "Acute illness", icon: "waveform.path.ecg", problems: [
            PatientProblem("sepsis", "Sepsis", asa: 4, asaExample: "sepsis", peds: 4, pedsExample: "sepsis"),
            PatientProblem("shock", "Shock", asa: 4, asaExample: "shock", peds: 4, pedsExample: "shock"),
            PatientProblem("massive-trauma", "Massive trauma", asa: 5, asaExample: "massive trauma", peds: 5, pedsExample: "massive trauma"),
            PatientProblem("ruptured-aneurysm", "Ruptured abdominal or thoracic aneurysm", asa: 5, asaExample: "ruptured abdominal/thoracic aneurysm"),
        ]),
        PatientSystem(id: "ob", name: "Obstetric", icon: "figure.2.and.child.holdinghands", problems: [
            PatientProblem("pregnant", "Pregnant", asa: 2, asaExample: "pregnancy"),
            PatientProblem("gest-htn", "Gestational hypertension, well controlled", asa: 2, asaExample: "well-controlled gestational HTN"),
            PatientProblem("preeclampsia", "Preeclampsia without severe features, controlled", asa: 2, asaExample: "controlled preeclampsia without severe features"),
            PatientProblem("gdm-diet", "Gestational diabetes, diet-controlled", asa: 2, asaExample: "diet-controlled gestational DM"),
            PatientProblem("gdm-complex", "Gestational diabetes with complications or high insulin needs", asa: 3, asaExample: "gestational DM with complications or high insulin requirements"),
            PatientProblem("thrombophilia", "Thrombophilia needing anticoagulation", asa: 3, asaExample: "a thrombophilic disease requiring anticoagulation"),
            PatientProblem("preeclampsia-severe", "Preeclampsia with severe features", asa: 3, asaExample: "preeclampsia with severe features"),
            PatientProblem("hellp", "Preeclampsia complicated by HELLP or another adverse event", asa: 4, asaExample: "preeclampsia with severe features complicated by HELLP or other adverse event"),
            PatientProblem("peripartum-cm", "Peripartum cardiomyopathy, EF below 40%", asa: 4, asaExample: "peripartum cardiomyopathy with EF <40"),
            PatientProblem("previa-accreta", "Placenta previa or accreta spectrum"),
            PatientProblem("uterine-rupture", "Uterine rupture", asa: 5, asaExample: "uterine rupture"),
        ]),
        PatientSystem(id: "msk", name: "Musculoskeletal", icon: "figure.walk", problems: [
            PatientProblem("ra", "Rheumatoid arthritis"),
            PatientProblem("spine-fusion", "Ankylosing spondylitis or cervical fusion"),
            PatientProblem("cspine-unstable", "Unstable cervical spine"),
            PatientProblem("scoliosis", "Scoliosis"),
        ]),
        PatientSystem(id: "social", name: "Substance use", icon: "wineglass", problems: [
            PatientProblem("alcohol-social", "Social alcohol use", asa: 2, asaExample: "social alcohol drinker"),
            PatientProblem("alcohol-abuse", "Alcohol dependence or abuse", asa: 3, asaExample: "alcohol dependence or abuse"),
            PatientProblem("substance", "Opioid or stimulant use"),
        ]),
    ]

    /// Problems the ASA's pediatric examples name that the adult lists do not, in the order of the ASA's table
    /// (class II to V). Shown first for a patient under 18, and not at all for an adult.
    static let pediatric = PatientSystem(id: "peds", name: "Pediatric", icon: "figure.and.child.holdinghands", problems: [
        PatientProblem("p-chd-asymptomatic", "Congenital heart disease, asymptomatic", peds: 2, pedsExample: "asymptomatic congenital cardiac disease"),
        PatientProblem("p-dysrhythmia", "Dysrhythmia, well controlled", peds: 2, pedsExample: "well-controlled dysrhythmias"),
        PatientProblem("p-bmi", "BMI percentile abnormal for age", peds: 2, pedsExample: "abnormal BMI percentile for age"),
        PatientProblem("p-onc-remission", "Cancer in remission", peds: 2, pedsExample: "oncologic state in remission"),
        PatientProblem("p-autism-mild", "Autism with mild limitations", peds: 2, pedsExample: "autism with mild limitations"),
        PatientProblem("p-infant6wk", "Full-term infant under 6 weeks", peds: 3, pedsExample: "full-term infants <6 weeks of age"),
        PatientProblem("p-premature60", "Born premature, postconceptual age under 60 weeks", peds: 3, pedsExample: "premature infant PCA <60 weeks"),
        PatientProblem("p-chd-uncorrected", "Congenital heart defect, uncorrected and stable", peds: 3, pedsExample: "uncorrected stable congenital cardiac abnormality"),
        PatientProblem("p-asthma-exacerbation", "Asthma with exacerbation", peds: 3, pedsExample: "asthma with exacerbation"),
        PatientProblem("p-epilepsy-poor", "Epilepsy, poorly controlled", peds: 3, pedsExample: "poorly controlled epilepsy"),
        PatientProblem("p-morbid-obesity", "Morbid obesity", peds: 3, pedsExample: "morbid obesity"),
        PatientProblem("p-malnutrition", "Malnutrition", peds: 3, pedsExample: "malnutrition"),
        PatientProblem("p-osa-severe", "Severe obstructive sleep apnea", peds: 3, pedsExample: "severe OSA"),
        PatientProblem("p-onc", "Cancer, current", peds: 3, pedsExample: "oncologic state"),
        PatientProblem("p-muscular-dystrophy", "Muscular dystrophy", peds: 3, pedsExample: "muscular dystrophy"),
        PatientProblem("p-cf", "Cystic fibrosis", peds: 3, pedsExample: "cystic fibrosis"),
        PatientProblem("p-transplant", "History of organ transplant", peds: 3, pedsExample: "history of organ transplantation"),
        PatientProblem("p-cns-malformation", "Brain or spinal cord malformation", peds: 3, pedsExample: "brain/spinal cord malformation"),
        PatientProblem("p-hydrocephalus", "Symptomatic hydrocephalus", peds: 3, pedsExample: "symptomatic hydrocephalus"),
        PatientProblem("p-autism-severe", "Autism with severe limitations", peds: 3, pedsExample: "autism with severe limitations"),
        PatientProblem("p-metabolic", "Metabolic disease", peds: 3, pedsExample: "metabolic disease"),
        PatientProblem("p-tpn", "Long-term parenteral nutrition", peds: 3, pedsExample: "long term parenteral nutrition"),
        PatientProblem("p-chd-symptomatic", "Congenital heart defect, symptomatic", peds: 4, pedsExample: "symptomatic congenital cardiac abnormality"),
        PatientProblem("p-prematurity-active", "Active sequelae of prematurity", peds: 4, pedsExample: "active sequelae of prematurity"),
        PatientProblem("p-hie", "Acute hypoxic-ischemic encephalopathy", peds: 4, pedsExample: "acute hypoxic-ischemic encephalopathy"),
        PatientProblem("p-ventilator", "Ventilator dependent", peds: 4, pedsExample: "ventilator dependence"),
        PatientProblem("p-endocrinopathy", "Endocrinopathy", peds: 4, pedsExample: "endocrinopathy"),
        PatientProblem("p-severe-trauma", "Severe trauma", peds: 4, pedsExample: "severe trauma"),
        PatientProblem("p-resp-distress", "Severe respiratory distress", peds: 4, pedsExample: "severe respiratory distress"),
        PatientProblem("p-onc-advanced", "Cancer, advanced", peds: 4, pedsExample: "advanced oncologic state"),
        PatientProblem("p-ecmo", "On ECMO", peds: 5, pedsExample: "patient requiring ECMO"),
        PatientProblem("p-resp-failure", "Respiratory failure or arrest", peds: 5, pedsExample: "respiratory failure or arrest"),
        PatientProblem("p-malignant-htn", "Malignant hypertension", peds: 5, pedsExample: "malignant hypertension"),
        PatientProblem("p-hepatic-enceph", "Hepatic encephalopathy", peds: 5, pedsExample: "hepatic encephalopathy"),
        PatientProblem("p-ischemic-bowel", "Ischemic bowel or multiple organ dysfunction", peds: 5, pedsExample: "ischemic bowel or multiple organ/system dysfunction"),
    ])

    /// Every system, the pediatric one last, for summaries and look-ups.
    static let allSystems: [PatientSystem] = systems + [pediatric]

    /// The systems to offer: the pediatric list first for a child, left out for an adult.
    static func systems(for r: PatientRecord) -> [PatientSystem] { r.isChild ? [pediatric] + systems : systems }

    static let allProblems: [PatientProblem] = allSystems.flatMap(\.problems)
    static func problem(_ id: String) -> PatientProblem? { allProblems.first { $0.id == id } }
    static func system(of problemId: String) -> PatientSystem? { allSystems.first { s in s.problems.contains { $0.id == problemId } } }

    static let medFlags: [PatientFlag] = [
        PatientFlag("anticoagulant", "Anticoagulant", "Warfarin, a DOAC or heparin"),
        PatientFlag("p2y12", "P2Y12 inhibitor", "Clopidogrel, prasugrel or ticagrelor"),
        PatientFlag("aspirin", "Aspirin"),
        PatientFlag("insulin", "Insulin"),
        PatientFlag("glp1", "GLP-1 receptor agonist"),
        PatientFlag("sglt2", "SGLT2 inhibitor"),
        PatientFlag("betablocker", "Beta-blocker"),
        PatientFlag("acei", "ACE inhibitor or ARB"),
        PatientFlag("statin", "Statin"),
        PatientFlag("steroid", "Chronic steroids"),
        PatientFlag("opioid", "Chronic opioids or buprenorphine"),
        PatientFlag("maoi", "MAO inhibitor"),
    ]

    static let anesthesiaHistory: [PatientFlag] = [
        PatientFlag("ponv", "PONV or motion sickness"),
        PatientFlag("difficult-airway", "Known difficult airway"),
        PatientFlag("mh", "Malignant hyperthermia, personal or family"),
        PatientFlag("pseudocholinesterase", "Pseudocholinesterase deficiency"),
        PatientFlag("awareness", "Awareness under anesthesia"),
        PatientFlag("delirium", "Emergence delirium"),
        PatientFlag("anesthesia-other", "Other anesthetic complication"),
    ]

    static let anesthetics: [PatientFlag] = [
        PatientFlag("ga", "General"),
        PatientFlag("mac", "Sedation (MAC)"),
        PatientFlag("neuraxial", "Neuraxial"),
        PatientFlag("regional", "Peripheral nerve block"),
    ]

    static let labs: [PatientField] = [
        PatientField("hb", "Hemoglobin", "g/dL"), PatientField("plt", "Platelets", "×10³/µL"), PatientField("inr", "INR", ""),
        PatientField("k", "Potassium", "mmol/L"), PatientField("na", "Sodium", "mmol/L"), PatientField("cr", "Creatinine", "mg/dL"),
        PatientField("glucose", "Glucose", "mg/dL"), PatientField("a1c", "HbA1c", "%"),
        PatientField("bnp", "BNP", "pg/mL"), PatientField("ntprobnp", "NT-proBNP", "pg/mL"),
        // Abnormal above the assay's 99th percentile (2024 AHA/ACC Figure 1, footnote §, p e371), so both are recorded.
        PatientField("troponin", "Troponin", "ng/L"), PatientField("troponin99", "Troponin, assay's 99th percentile", "ng/L"),
    ]

    static let vitals: [PatientField] = [
        PatientField("sbp", "Systolic BP", "mmHg"), PatientField("dbp", "Diastolic BP", "mmHg"), PatientField("hr", "Heart rate", "/min"),
        PatientField("spo2", "SpO₂ on room air", "%"), PatientField("rr", "Respiratory rate", "/min"), PatientField("temp", "Temperature", "°C"),
    ]

    static let fluids: [PatientField] = [
        PatientField("crystalloid", "Crystalloid", "mL"), PatientField("colloid", "Colloid or albumin", "mL"),
        PatientField("prbc", "Red cells", "units"), PatientField("wholeBlood", "Whole blood", "units"),
        PatientField("plasma", "Plasma", "units"), PatientField("platelets", "Platelets", "units"),
        PatientField("cryo", "Cryoprecipitate", "units"), PatientField("cellSaver", "Cell salvage returned", "mL"),
        PatientField("ebl", "Estimated blood loss", "mL"), PatientField("uop", "Urine output", "mL"),
    ]

    static let dispositions = ["PACU", "ICU", "Ward", "Same-day discharge", "Other"]
    static let devices = ["Direct laryngoscope", "Video laryngoscope", "Flexible scope", "Supraglottic airway", "Face mask only"]
    static let grades = ["1", "2a", "2b", "3", "4"]

    /// Cormack and Lehane's grades with Yentis and Lee's 2a and 2b (Anaesthesia 1984; 1998). Grades 3 and 4 are
    /// difficult laryngoscopy.
    static func gradeDetail(_ g: String) -> String? {
        switch g {
        case "1": return "Full view of the glottis"
        case "2a": return "Part of the vocal cords visible"
        case "2b": return "Only the arytenoids or the very posterior origin of the cords visible"
        case "3": return "Epiglottis only; the cords are not seen"
        case "4": return "Neither the glottis nor the epiglottis seen"
        default: return nil
        }
    }

    /// The airway when care is handed over.
    static let airwayAtEnd: [(id: String, label: String)] = [
        ("extubated", "Extubated"), ("intubated", "Intubated"), ("sga", "Supraglottic airway in"), ("natural", "Never instrumented"),
    ]
}
