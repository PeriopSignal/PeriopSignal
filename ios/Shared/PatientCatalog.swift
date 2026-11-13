import Foundation

// MARK: - The choices My Patient offers: problems by system, medication and anesthesia-history flags, airway signs.
//
// `asa` marks a problem the ASA's own adult or obstetric examples place in a class, and `peds` one its pediatric
// examples do (ASA Physical Status Classification System, last amended December 13, 2020, which added the pediatric
// and obstetric examples); the tab suggests the highest class among them and the clinician confirms.
// `asaDef` (1.12, Ben) gives every other adult problem a class from the ASA's definitions of the classes (shown "by
// definition"), except the few listed as having no class (PatientRules.asaNoClass).
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
    /// The STOP-BANG item it answers ("snoring", "tired", "observed", "pressure").
    var stopBang: String?
    /// A line for the system page's ⓘ (its group note), when the item's class can be higher than its example gives.
    var note: String?
    /// 1.12 (Ben, Nov 12): the class an adult problem takes BY THE ASA'S DEFINITION of the classes (II mild, III severe, IV
    /// severe and a constant threat to life), for a problem the ASA's examples do not name. Never set together with `asa`;
    /// a child is not given it (`peds` is the child's class). Four items (ckd, vte, malignancy, prostate-cancer) take this
    /// class or class II by a recorded detail: it holds the higher one (PatientRules.asaDefinitionLevel).
    var asaDef: Int?

    init(_ id: String, _ label: String, asa: Int? = nil, asaExample: String? = nil, peds: Int? = nil, pedsExample: String? = nil, rcri: String? = nil, stopBang: String? = nil,
         note: String? = nil, asaDef: Int? = nil) {
        self.id = id; self.label = label; self.asa = asa; self.asaExample = asaExample; self.peds = peds; self.pedsExample = pedsExample
        self.rcri = rcri; self.stopBang = stopBang; self.note = note; self.asaDef = asaDef
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
        // Cardiovascular and Respiratory are drawn as expanding sections (HistorySections, 1.8.1); their details sit in
        // PatientRecord.hx. Every id the rules read is here, the ones the page sets from its options too.
        PatientSystem(id: "cv", name: "Cardiovascular", icon: "heart", problems: [
            // Confirmed by Ben, Nov 2: plain hypertension suggests class II ("well-controlled DM/HTN"); "poorly controlled
            // DM or HTN" is class III, set by hand. "htn-poor" (poorly controlled) loads as this item (renamedProblems).
            PatientProblem("htn", "Hypertension", asa: 2, asaExample: "well-controlled DM/HTN", stopBang: "pressure",
                           note: "ASA III if poorly controlled; change the class by hand."),
            // 2024 AHA/ACC §6.2 (p e373): "recent history of poorly controlled hypertension (SBP ≥180 mm Hg or DBP ≥110
            // mm Hg before the day of surgery)".
            PatientProblem("htn-180", "BP ≥ 180/110 before the day of surgery", asa: 3, asaExample: "poorly controlled DM or HTN", stopBang: "pressure"),
            PatientProblem("hyperlipidemia", "Hyperlipidemia", asaDef: 2),
            // CAD chosen alone is coronary disease of unrecorded timing: the ASA's ">3 months … CAD/stents" example.
            PatientProblem("cad", "Coronary artery disease", asa: 3, asaExample: "history (>3 months) of MI, CVA, TIA, or CAD/stents", rcri: "ihd"),
            PatientProblem("mi", "MI over 3 months", asa: 3, asaExample: "history (>3 months) of MI, CVA, TIA, or CAD/stents", rcri: "ihd"),
            PatientProblem("cad-recent", "MI within 3 months", asa: 4, asaExample: "recent (<3 months) MI, CVA, TIA or CAD/stents", rcri: "ihd"),
            PatientProblem("pci", "PCI over 3 months", asa: 3, asaExample: "history (>3 months) of MI, CVA, TIA, or CAD/stents", rcri: "ihd"),
            PatientProblem("pci-recent", "PCI within 3 months", asa: 4, asaExample: "recent (<3 months) MI, CVA, TIA or CAD/stents", rcri: "ihd"),
            PatientProblem("ischemia", "Ongoing (unstable) ischemia", asa: 4, asaExample: "ongoing cardiac ischemia", rcri: "ihd"),
            PatientProblem("cabg", "Prior CABG", asa: 3, asaExample: "history (>3 months) of MI, CVA, TIA, or CAD/stents", rcri: "ihd"),
            PatientProblem("hf", "Heart failure", peds: 4, pedsExample: "congestive heart failure", rcri: "hf", asaDef: 3),
            PatientProblem("hf-decomp", "Heart failure, decompensated", peds: 5, pedsExample: "decompensated congestive heart failure", rcri: "hf", asaDef: 4),
            PatientProblem("ef-moderate", "EF moderately reduced", asa: 3, asaExample: "moderate reduction of ejection fraction"),
            PatientProblem("ef-severe", "EF severely reduced", asa: 4, asaExample: "severe reduction of ejection fraction"),
            // Set by a severe lesion on any valve (PatientHistoryDetails.sync), or saved before 1.8.1 without its valve.
            PatientProblem("valve-severe", "Severe valve disease", asa: 4, asaExample: "severe valve dysfunction"),
            PatientProblem("af", "AF/flutter", asaDef: 3),
            PatientProblem("arrhythmia", "Other arrhythmia", asaDef: 2),
            PatientProblem("pacemaker", "Pacemaker", asa: 3, asaExample: "implanted pacemaker"),
            PatientProblem("icd", "ICD", peds: 4, pedsExample: "automatic implantable cardioverter-defibrillator", asaDef: 3),
            PatientProblem("pulm-htn", "Pulmonary hypertension", asaDef: 3),
            PatientProblem("pulm-htn-severe", "Pulmonary hypertension, severe", asaDef: 4),
            PatientProblem("pvd", "Peripheral vascular disease", asaDef: 3),
            PatientProblem("chd", "Congenital heart disease", asaDef: 2),
            // 2024 AHA/ACC Table 10: single ventricle or Fontan, cyanotic disease, TGA and similar lesions.
            PatientProblem("chd-elevated", "Congenital heart disease, complex lesion", asaDef: 3),
            // Aortopathy. Set from the aneurysms by location (PatientHistoryDetails.sync). "Ruptured abdominal/thoracic
            // aneurysm" is the ASA's own class V example, its only aortic one (ASA Physical Status Classification System);
            // a thoracoabdominal aneurysm is both. Unruptured aneurysms, dissections and repairs are in no ASA example.
            PatientProblem("aaa", "Abdominal aortic aneurysm", asaDef: 3),
            PatientProblem("aaa-ruptured", "Ruptured abdominal aortic aneurysm", asa: 5, asaExample: "ruptured abdominal/thoracic aneurysm"),
            PatientProblem("taa", "Thoracic aortic aneurysm", asaDef: 3),
            PatientProblem("taa-ruptured", "Ruptured thoracic aortic aneurysm", asa: 5, asaExample: "ruptured abdominal/thoracic aneurysm"),
            PatientProblem("taaa", "Thoracoabdominal aortic aneurysm", asaDef: 3),
            PatientProblem("taaa-ruptured", "Ruptured thoracoabdominal aortic aneurysm", asa: 5, asaExample: "ruptured abdominal/thoracic aneurysm"),
            PatientProblem("dissection-a", "Aortic dissection, type A", asaDef: 4),
            PatientProblem("dissection-b", "Aortic dissection, type B", asaDef: 3),
            PatientProblem("aortic-repair-open", "Prior open aortic repair", asaDef: 2),
            PatientProblem("evar", "Prior EVAR", asaDef: 2),
            PatientProblem("tevar", "Prior TEVAR", asaDef: 2),
        ]),
        // The STOP-BANG questions (snoring, tiredness, observed apnea) and "Mild lung disease" are no longer items
        // (1.8.1): the STOP-BANG tool asks its own questions. Saved ones still load and are not shown.
        PatientSystem(id: "resp", name: "Respiratory", icon: "lungs", problems: [
            PatientProblem("asthma", "Asthma", peds: 2, pedsExample: "asthma without exacerbation", asaDef: 2),
            // The coordinator's default (Ben had no preference): uncontrolled is the pediatric "asthma with exacerbation".
            PatientProblem("asthma-uncontrolled", "Asthma, uncontrolled", peds: 3, pedsExample: "asthma with exacerbation", asaDef: 3),
            PatientProblem("copd", "COPD", asa: 3, asaExample: "COPD"),
            PatientProblem("osa", "Obstructive sleep apnea", peds: 2, pedsExample: "mild/moderate OSA", asaDef: 2),
            PatientProblem("cpap", "Uses CPAP or BiPAP", asaDef: 2),
            // Each is ARISCAT's respiratory infection in the last month (PatientRules.prefill).
            PatientProblem("uri", "URI", asaDef: 2),
            PatientProblem("pneumonia", "Pneumonia", asaDef: 3),
            PatientProblem("resp-infection-other", "Other respiratory infection", asaDef: 2),
            PatientProblem("ild", "Interstitial lung disease", asaDef: 3),
            PatientProblem("home-o2", "Home oxygen", asaDef: 3),
            // 1.9: the side, the fluid, drainage and a chest tube sit in PatientRecord.hx; a chest tube in place is drawn
            // on the diagram (PatientDeviceFills).
            PatientProblem("pleural-effusion", "Pleural effusion", asaDef: 3),
            PatientProblem("pneumothorax", "Pneumothorax", asaDef: 3),
        ]),
        PatientSystem(id: "neuro", name: "Neurologic", icon: "brain.head.profile", problems: [
            PatientProblem("cva", "Stroke or TIA, over 3 months", asa: 3, asaExample: "history (>3 months) of MI, CVA, TIA, or CAD/stents", rcri: "cva"),
            PatientProblem("cva-recent", "Stroke or TIA within 3 months", asa: 4, asaExample: "recent (<3 months) MI, CVA, TIA or CAD/stents", rcri: "cva"),
            // A stroke whose timing the record does not give (1.8.1). Confirmed by Ben, Nov 2: the lowest class the ASA's
            // examples give a stroke, history (>3 months), class III; within 3 months is class IV.
            PatientProblem("cva-unspec", "Stroke or TIA, unspecified", asa: 3, asaExample: "history (>3 months) of MI, CVA, TIA, or CAD/stents", rcri: "cva",
                           note: "ASA IV if within 3 months."),
            // The bleed itself, with no class of its own (the ASA's examples give only a bleed with mass effect); the Intracranial
            // bleed page's "With mass effect" option is ich-mass (1.8.2).
            PatientProblem("ich", "Intracranial bleed", asaDef: 4),
            PatientProblem("ich-mass", "Intracranial bleed with mass effect", asa: 5, asaExample: "intracranial bleed with mass effect", peds: 5, pedsExample: "intracranial hemorrhage with mass effect"),
            PatientProblem("raised-icp", "Intracranial mass or raised ICP", asaDef: 4),
            PatientProblem("seizure", "Seizure disorder", peds: 2, pedsExample: "well-controlled epilepsy", asaDef: 2),
            PatientProblem("dementia", "Dementia or cognitive impairment", asaDef: 3),
            PatientProblem("parkinson", "Parkinson disease", asaDef: 3),
            PatientProblem("neuromuscular", "Neuromuscular disease", asaDef: 3),
            PatientProblem("sci", "Spinal cord injury", asaDef: 3),
            PatientProblem("chronic-pain", "Chronic pain or opioid tolerance", asaDef: 2),
            // 1.9 (Ben's list). An unstable cervical spine is the Musculoskeletal item "cspine-unstable", shown on this page
            // too.
            PatientProblem("visual-impairment", "Visual impairment"),
            PatientProblem("psych", "Psychological disorder", asaDef: 2),
            PatientProblem("mdd", "Major depressive disorder", asaDef: 2),
            PatientProblem("anxiety", "Anxiety disorder", asaDef: 2),
        ]),
        // 1.9: an expanding page. The CKD stage (KDIGO G1–G5), the dialysis schedule and the access sites sit in
        // PatientRecord.hx; a fistula or dialysis catheter with a location is drawn on the diagram (PatientDeviceFills).
        PatientSystem(id: "renal", name: "Renal", icon: "drop", problems: [
            PatientProblem("ckd", "Chronic kidney disease", peds: 3, pedsExample: "renal failure", asaDef: 3),
            // Chosen by hand (an option of CKD/ESRD), never inferred from stage 5: a stage-5 patient may be on peritoneal
            // dialysis. Until 1.9 this was part of "aki", whose ASA IV example it shares.
            PatientProblem("esrd-no-dialysis", "ESRD not on regularly scheduled dialysis", asa: 4, asaExample: "ARD or ESRD not undergoing regularly scheduled dialysis", peds: 3, pedsExample: "renal failure"),
            // Saved before 1.9 as "Acute kidney injury, or ESRD not on scheduled dialysis"; the id and its ASA IV are kept.
            PatientProblem("aki", "Acute kidney injury", asa: 4, asaExample: "ARD or ESRD not undergoing regularly scheduled dialysis", peds: 3, pedsExample: "renal failure"),
            PatientProblem("bph", "Benign prostatic hyperplasia"),
            PatientProblem("prostate-cancer", "Prostate cancer", asaDef: 3),
            // The Hemodialysis item (1.9).
            PatientProblem("esrd-dialysis", "ESRD on regularly scheduled dialysis", asa: 3, asaExample: "ESRD undergoing regularly scheduled dialysis", peds: 3, pedsExample: "renal failure"),
        ]),
        // 1.9: an expanding page, in Ben's order. Reflux and a hiatal hernia are two items now ("gerd" was "Reflux or hiatal
        // hernia"); the aspiration and heparin warnings and the TEE concerns are PatientWarnings and PatientTEE.
        PatientSystem(id: "gi", name: "GI & liver", icon: "cross.case", problems: [
            PatientProblem("gerd", "Reflux/GERD", asaDef: 2),
            PatientProblem("gastric-bypass", "History of gastric bypass"),
            PatientProblem("dysphagia", "Dysphagia"),
            PatientProblem("esophageal-disorder", "Esophageal disorder", asaDef: 2),
            PatientProblem("hiatal-hernia", "Hiatal hernia", asaDef: 2),
            // A relative contraindication to a TEE probe (Hahn RT, et al. J Am Soc Echocardiogr 2013, Table 6).
            PatientProblem("varices", "Esophageal varices", asaDef: 3),
            PatientProblem("cirrhosis", "Cirrhosis", asaDef: 3),
            PatientProblem("hepatitis-active", "Active hepatitis", asa: 3, asaExample: "active hepatitis"),
            PatientProblem("gastroparesis", "Gastroparesis", asaDef: 2),
            PatientProblem("gi-bleed", "GI bleed", asaDef: 3),
            PatientProblem("full-stomach", "Full stomach or bowel obstruction"),
        ]),
        PatientSystem(id: "endo", name: "Endocrine", icon: "flask", problems: [
            // One item since 1.8.1 ("dm-poor", Diabetes, poorly controlled, loads as this one: migratedProblems). Confirmed
            // by Ben, Nov 2: the lowest class the ASA's examples give a diabetic, "well-controlled DM/HTN", class II; "poorly
            // controlled DM or HTN" is class III, set by hand.
            PatientProblem("dm", "Diabetes", asa: 2, asaExample: "well-controlled DM/HTN", peds: 2, pedsExample: "non-insulin-dependent diabetes mellitus",
                           note: "ASA III if poorly controlled; change the class by hand."),
            PatientProblem("insulin", "Diabetes treated with insulin", peds: 3, pedsExample: "insulin-dependent diabetes mellitus", rcri: "insulin", asaDef: 2),
            PatientProblem("thyroid", "Thyroid disease", asaDef: 2),
            PatientProblem("adrenal", "Adrenal insufficiency or chronic steroids", asaDef: 3),
        ]),
        // 1.9: an expanding page. Anemia is also set by a low hemoglobin (WHO 2024 cut-offs, PatientCrossFill). Factor V
        // Leiden is a thrombophilia, not a bleeding disorder (Ben, Nov 3); the Obstetric page's Thrombophilia is this item.
        // 1.12 (Ben, Nov 11): "Heme & Oncology", with one Malignancy item for the common cancers (PatientMalignancy; its ASA class
        // is by definition and by status, no RCRI item). Its id and the ids of the Hematologic problems are unchanged.
        PatientSystem(id: "heme", name: "Heme & Oncology", icon: "drop.triangle", problems: [
            PatientProblem("anemia", "Anemia", asaDef: 2),
            PatientProblem("thrombocytopenia", "Thrombocytopenia", asaDef: 2),
            // 1.12 follow-up (Ben, Nov 12): heparin-induced thrombocytopenia ("HIIT" was HIT) and heparin resistance, each its own
            // item and neither the Thrombocytopenia item. Ben chose no ASA class for either (PatientRules.asaNoClass).
            PatientProblem("hit", "Heparin-induced thrombocytopenia (HIT)"),
            PatientProblem("bleeding", "Bleeding disorder or coagulopathy", asaDef: 3),
            PatientProblem("vwd", "von Willebrand disease", asaDef: 2),
            PatientProblem("hemophilia-a", "Hemophilia A", asaDef: 3),
            PatientProblem("hemophilia-b", "Hemophilia B", asaDef: 3),
            PatientProblem("dic", "DIC", asa: 4, asaExample: "DIC", peds: 4, pedsExample: "disseminated intravascular coagulation"),
            // Not the Obstetric "thrombophilia", whose ASA III example is a thrombophilic disease requiring anticoagulation
            // in pregnancy.
            PatientProblem("thrombophilia-heme", "Thrombophilia", asaDef: 2),
            PatientProblem("fvl", "Factor V Leiden", asaDef: 2),
            PatientProblem("anticoagulation", "On anticoagulation", asaDef: 2),
            PatientProblem("heparin-resistance", "Heparin resistance"),
            PatientProblem("declines-blood", "Declines blood products"),
            PatientProblem("vte", "DVT or PE", asaDef: 3),
            PatientProblem("sickle", "Sickle cell disease", asaDef: 3),
            PatientProblem("malignancy", "Malignancy", asaDef: 3),
        ]),
        // 1.8.1. None is among the ASA's examples (sepsis stays under Acute illness, with shock). 1.9: an expanding page.
        // Sepsis (Acute illness), URI and pneumonia (Respiratory) are shown here too, with the same ids; endocarditis is
        // shown on the Cardiovascular page. The precautions they suggest are PatientPrecautions.
        PatientSystem(id: "infectious", name: "Infectious", icon: "facemask", problems: [
            PatientProblem("infection-active", "Active infection", asaDef: 3),
            PatientProblem("endocarditis", "Infective endocarditis", asaDef: 4),
            PatientProblem("hiv", "HIV", asaDef: 2),
            // Saved before 1.9 as "Hepatitis B or C"; the types (A, B, C) sit in PatientRecord.hx.
            PatientProblem("hepatitis-viral", "Viral hepatitis", asaDef: 2),
            PatientProblem("mdro", "MRSA or VRE"),
            PatientProblem("c-diff", "C. difficile", asaDef: 2),
            PatientProblem("tb", "Tuberculosis", asaDef: 3),
            // Active or recent sits in PatientRecord.hx; ARISCAT reads the one id either way.
            PatientProblem("covid-recent", "COVID-19", asaDef: 2),
            PatientProblem("isolation", "Isolation precautions"),
        ]),
        PatientSystem(id: "acute", name: "Acute illness", icon: "waveform.path.ecg", problems: [
            PatientProblem("sepsis", "Sepsis", asa: 4, asaExample: "sepsis", peds: 4, pedsExample: "sepsis"),
            PatientProblem("shock", "Shock", asa: 4, asaExample: "shock", peds: 4, pedsExample: "shock"),
            PatientProblem("massive-trauma", "Massive trauma", asa: 5, asaExample: "massive trauma", peds: 5, pedsExample: "massive trauma"),
            // 1.9. A burn is in no ASA example.
            PatientProblem("burn", "Major burn", asaDef: 4),
            PatientProblem("ruptured-aneurysm", "Ruptured abdominal or thoracic aneurysm", asa: 5, asaExample: "ruptured abdominal/thoracic aneurysm"),
        ]),
        PatientSystem(id: "ob", name: "Obstetric", icon: "figure.2.and.child.holdinghands", problems: [
            PatientProblem("pregnant", "Pregnant", asa: 2, asaExample: "pregnancy"),
            PatientProblem("gest-htn", "Gestational hypertension, well controlled", asa: 2, asaExample: "well-controlled gestational HTN"),
            PatientProblem("preeclampsia", "Preeclampsia without severe features, controlled", asa: 2, asaExample: "controlled preeclampsia without severe features"),
            // 1.9: Gestational diabetes alone; controlled or uncontrolled and insulin sit in PatientRecord.hx. Only the ASA's
            // own examples (diet-controlled; complications or high insulin requirements) carry a class.
            PatientProblem("gdm", "Gestational diabetes", asaDef: 2),
            PatientProblem("gdm-diet", "Gestational diabetes, diet-controlled", asa: 2, asaExample: "diet-controlled gestational DM"),
            PatientProblem("gdm-complex", "Gestational diabetes with complications or high insulin needs", asa: 3, asaExample: "gestational DM with complications or high insulin requirements"),
            PatientProblem("thrombophilia", "Thrombophilia needing anticoagulation", asa: 3, asaExample: "a thrombophilic disease requiring anticoagulation"),
            PatientProblem("preeclampsia-severe", "Preeclampsia with severe features", asa: 3, asaExample: "preeclampsia with severe features"),
            PatientProblem("hellp", "Preeclampsia complicated by HELLP or another adverse event", asa: 4, asaExample: "preeclampsia with severe features complicated by HELLP or other adverse event"),
            // 1.9 (Ben, Nov 3): peripartum cardiomyopathy as the ESC Heart Failure Association defines it, LVEF < 45%
            // (Bauersachs J, et al. Eur J Heart Fail 2019;21:827–843). An EF below 40% is the ASA's class IV example.
            PatientProblem("ppcm", "Peripartum cardiomyopathy (LVEF < 45%)", asaDef: 3),
            PatientProblem("peripartum-cm", "Peripartum cardiomyopathy, EF below 40%", asa: 4, asaExample: "peripartum cardiomyopathy with EF <40"),
            PatientProblem("previa-accreta", "Placenta previa or accreta spectrum", asaDef: 3),
            // Active rupture is the ASA's class V example; a past rupture is in none (1.9).
            PatientProblem("uterine-rupture", "Uterine rupture, active", asa: 5, asaExample: "uterine rupture"),
            PatientProblem("uterine-rupture-past", "Uterine rupture, past"),
        ]),
        // 1.9: an expanding page. The unstable cervical spine is shown on the Neurologic page too.
        PatientSystem(id: "msk", name: "Musculoskeletal", icon: "figure.walk", problems: [
            PatientProblem("ra", "Rheumatoid arthritis", asaDef: 2),
            PatientProblem("oa", "Osteoarthritis", asaDef: 2),
            PatientProblem("spine-fusion", "Ankylosing spondylitis or cervical fusion", asaDef: 2),
            PatientProblem("cspine-unstable", "Unstable cervical spine", asaDef: 3),
            PatientProblem("scoliosis", "Scoliosis", asaDef: 2),
            PatientProblem("fracture", "Fracture"),
            // The ASA's pediatric class III example ("p-muscular-dystrophy" is the same example on the Pediatric list).
            PatientProblem("muscular-dystrophy", "Muscular dystrophy", peds: 3, pedsExample: "muscular dystrophy", asaDef: 3),
            PatientProblem("marfan", "Marfan syndrome", asaDef: 2),
            PatientProblem("eds", "Ehlers-Danlos syndrome", asaDef: 2),
            PatientProblem("compartment-syndrome", "Compartment syndrome", asaDef: 3),
        ]),
        PatientSystem(id: "social", name: "Smoking & Substances", icon: "wineglass", problems: [
            PatientProblem("alcohol-social", "Social alcohol use", asa: 2, asaExample: "social alcohol drinker"),
            PatientProblem("alcohol-abuse", "Alcohol dependence or abuse", asa: 3, asaExample: "alcohol dependence or abuse"),
            // 1.9. The ASA's example names dependence or abuse without saying current; a former one is set by hand.
            PatientProblem("alcohol-abuse-former", "Former alcohol dependence or abuse", asaDef: 2),
            // Saved before 1.9 as "Opioid or stimulant use"; the drugs are its options.
            PatientProblem("substance", "Illicit drug use", asaDef: 3),
            PatientProblem("cocaine", "Cocaine use", asaDef: 3),
            PatientProblem("opioid-use", "Illicit opioid use", asaDef: 3),
            PatientProblem("marijuana", "Marijuana use", asaDef: 2),
            PatientProblem("methamphetamine", "Methamphetamine use", asaDef: 3),
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

    /// The Cardiovascular page's Aortopathy ids, in the page's order (the aneurysm ids follow from the aneurysms by
    /// location: PatientHistoryDetails.sync).
    static let aortaIDs: [String] = ["aaa", "aaa-ruptured", "taa", "taa-ruptured", "taaa", "taaa-ruptured", "dissection-a", "dissection-b",
                                     "aortic-repair-open", "evar", "tevar"]
    static func problem(_ id: String) -> PatientProblem? { allProblems.first { $0.id == id } }

    /// Problem ids that are no longer offered, and the item a saved record's id now loads as (1.8.1: diabetes is one
    /// item; hypertension has no control qualifier). Aortic stenosis, mitral regurgitation and a prosthetic valve move
    /// into the valve details (PatientHistoryDetails.migrate); "fh-cad", "snoring", "tired", "observed-apnea" and
    /// "lung-mild" still load and are no longer shown or read.
    static let renamedProblems: [String: String] = ["dm-poor": "dm", "htn-poor": "htn"]

    /// A saved record's problems with retired ids moved to their current item.
    static func migratedProblems(_ ids: Set<String>) -> Set<String> { Set(ids.map { renamedProblems[$0] ?? $0 }) }

    /// The system page's ⓘ: each item's own line first ("Diabetes: ASA III if poorly controlled; change the class by
    /// hand."), then how the page's problems feed the scores.
    static func systemNote(_ s: PatientSystem) -> String {
        let base = "Problems the ASA's own examples place in a class (adult or pediatric, by the age recorded) feed the ASA suggestion; the RCRI, STOP-BANG and other scores open with them ticked. Where the ASA gives no example, an adult problem takes a class from the ASA's definitions of the classes, marked \u{201C}by definition\u{201D}; you assign the class."
        let items = s.problems.compactMap { p in p.note.map { p.label + ": " + $0 } }
        return (items + [base]).joined(separator: "\n\n")
    }
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
    static let devices = ["Direct laryngoscope", "Video laryngoscope", "Fiberoptic scope", "Supraglottic airway", "Face mask only"]
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

    /// The At handoff choices for this patient. One who arrived with an ETT or a tracheostomy, or whose airway course
    /// records an intubation or a supraglottic airway, cannot be "Never instrumented" (review 1.10: the choice sat
    /// under "ETT … on arrival" and under a recorded intubation), so it is offered only to the others, or while it is
    /// the saved value (an older record keeps showing its choice).
    static func airwayAtEndChoices(_ r: PatientRecord) -> [(id: String, label: String)] {
        let instrumented = r.arrivesWithAirway || PatientAirway.intubationChosen(r) || PatientAirway.lmaChosen(r)
        guard instrumented else { return airwayAtEnd }
        return airwayAtEnd.filter { $0.id != "natural" || r.airwayAtEnd == "natural" }
    }
}
