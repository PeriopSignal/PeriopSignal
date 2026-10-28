import Foundation

// MARK: - Valve intervention (2020 ACC/AHA valvular heart disease guideline)
//
// The guideline's recommendation tables as rules over a few prompted questions. A rule matches when
// every one of its conditions is answered the way it needs; a rule whose conditions are not yet all
// answered, and none contradicted, is "pending" and tells the user which question to answer next.
// Classes and levels of evidence are the guideline's own. Otto CM et al, Circulation 2021;143:e72–e227.

enum VILesion: String, CaseIterable, Identifiable, Hashable {
    case as_ = "as", ar, mrPrimary, mrSecondary, ms, tr
    var id: String { rawValue }
    var name: String {
        switch self {
        case .as_: return "Aortic stenosis"
        case .ar: return "Aortic regurgitation"
        case .mrPrimary: return "Primary mitral regurgitation"
        case .mrSecondary: return "Secondary mitral regurgitation"
        case .ms: return "Mitral stenosis"
        case .tr: return "Tricuspid regurgitation"
        }
    }
    var short: String {
        switch self {
        case .as_: return "AS"
        case .ar: return "AR"
        case .mrPrimary: return "Primary MR"
        case .mrSecondary: return "Secondary MR"
        case .ms: return "MS"
        case .tr: return "TR"
        }
    }
    /// What "severe" means for this lesion in the guideline.
    var severityNote: String {
        switch self {
        case .as_: return "Severe: Vmax ≥ 4 m/s or mean gradient ≥ 40 mmHg (AVA usually ≤ 1.0 cm²); very severe: Vmax ≥ 5 m/s or mean gradient ≥ 60 mmHg. Low-flow, low-gradient: AVA ≤ 1.0 cm² with Vmax < 4 m/s, confirmed severe by dobutamine stress or calcium scoring."
        case .ar: return "Severe: vena contracta > 0.6 cm, regurgitant volume ≥ 60 mL, fraction ≥ 50%, EROA ≥ 0.3 cm², holodiastolic flow reversal."
        case .mrPrimary: return "Severe: vena contracta ≥ 0.7 cm, regurgitant volume ≥ 60 mL, fraction ≥ 50%, EROA ≥ 0.40 cm²; stages C1 (compensated) and C2 (LVEF ≤ 60% or LVESD ≥ 40 mm) are asymptomatic, D symptomatic."
        case .mrSecondary: return "Severe: EROA ≥ 0.40 cm², regurgitant volume ≥ 60 mL, fraction ≥ 50%; 2D PISA underestimates crescentic orifices and the volume runs lower in low-flow states."
        case .ms: return "Severe rheumatic MS: planimetered MVA ≤ 1.5 cm² with pressure half-time ≥ 150 ms; the mean gradient is not a severity criterion."
        case .tr: return "Severe: vena contracta ≥ 0.7 cm, EROA ≥ 0.40 cm², hepatic vein systolic flow reversal; progressive (stage B): moderate TR."
        }
    }
}

struct VIQuestion: Identifiable, Hashable {
    let id: String
    let label: String
    let options: [String]
    let hint: String?
    init(_ id: String, _ label: String, _ options: [String], hint: String? = nil) {
        self.id = id; self.label = label; self.options = options; self.hint = hint
    }
    static func yesNo(_ id: String, _ label: String, hint: String? = nil) -> VIQuestion { VIQuestion(id, label, ["Yes", "No"], hint: hint) }
}

/// A condition on one answer: the answer must be one of `any`.
struct VICond: Hashable {
    let question: String
    let any: Set<String>
    static func q(_ id: String, _ values: String...) -> VICond { VICond(question: id, any: Set(values)) }
    static func yes(_ id: String) -> VICond { VICond(question: id, any: ["Yes"]) }
    static func no(_ id: String) -> VICond { VICond(question: id, any: ["No"]) }
}

enum VIClass: String, Hashable, Comparable {
    case one = "1", twoA = "2a", twoB = "2b", three = "3"
    private var order: Int { switch self { case .one: return 0; case .twoA: return 1; case .twoB: return 2; case .three: return 3 } }
    static func < (a: VIClass, b: VIClass) -> Bool { a.order < b.order }
    var word: String {
        switch self {
        case .one: return "Recommended"
        case .twoA: return "Reasonable"
        case .twoB: return "May be considered"
        case .three: return "Not recommended"
        }
    }
}

enum VIGroup: String, Hashable, CaseIterable {
    case intervene = "Intervention", procedure = "Which procedure", prosthesis = "Prosthesis"
}

struct VIRule: Identifiable, Hashable {
    let id: String
    let group: VIGroup
    /// The guideline's situation, in its words.
    let situation: String
    let recommendation: String
    let cls: VIClass
    /// Level of evidence (A, B-R, B-NR, C-LD, C-EO) or "Harm" for class 3.
    let level: String
    /// Any one of these condition sets matching is enough (an OR of ANDs).
    let when: [[VICond]]
    let note: String?
    init(_ id: String, _ situation: String, _ recommendation: String, _ cls: VIClass, _ level: String, group: VIGroup = .intervene, when: [[VICond]], note: String? = nil) {
        self.id = id; self.group = group; self.situation = situation; self.recommendation = recommendation
        self.cls = cls; self.level = level; self.when = when; self.note = note
    }
}

enum VIState: Hashable { case match, pending(Set<String>), contradicted }

struct VIResult: Hashable {
    var matched: [VIRule]
    /// Question ids still unanswered that could add a recommendation, in the order the lesion asks them.
    var needed: [String]
    /// Shown when nothing matches and nothing is pending.
    var fallback: String?
}

enum ValveIntervention {
    // Shared questions
    static let age = VIQuestion("age", "Age", ["< 50", "50–64", "65–80", "> 80"])
    static let anticoag = VIQuestion.yesNo("anticoag", "Long-term anticoagulation possible and acceptable", hint: "Indications for and risks of a vitamin K antagonist, and the patient's preference")
    static let position = VIQuestion("position", "Valve position", ["Aortic", "Mitral"])

    static func questions(for lesion: VILesion) -> [VIQuestion] {
        switch lesion {
        case .as_: return [
            VIQuestion("sev", "Severity on echo", ["Moderate", "Severe", "Very severe", "Low-flow, low-gradient"], hint: "Moderate Vmax 3–3.9 m/s · severe ≥ 4 · very severe ≥ 5 · low-flow, low-gradient: AVA ≤ 1.0 cm² with Vmax < 4"),
            .yesNo("sx", "Symptoms attributable to the stenosis", hint: "Exertional dyspnea, angina, syncope or presyncope; an exercise test settles doubtful cases"),
            VIQuestion("ef", "LVEF", ["≥ 60%", "50–59%", "< 50%"]),
            .yesNo("surg", "Other cardiac surgery planned"),
            VIQuestion("risk", "Surgical risk", ["Low", "Intermediate", "High or prohibitive"], hint: "Low: STS < 3%, no frailty, no major organ compromise; high: STS > 8%, ≥ 2 frailty indices or 1–2 uncorrectable organ systems"),
            age,
            .yesNo("markers", "Abnormal exercise test, BNP > 3× normal, or Vmax rising ≥ 0.3 m/s a year", hint: "Reduced exercise tolerance or a systolic pressure fall ≥ 10 mmHg on exercise testing"),
            .yesNo("effall", "LVEF fallen below 60% on three or more serial studies"),
            .yesNo("tf", "Transfemoral anatomy suitable for TAVI"),
            .yesNo("bicuspid", "Bicuspid valve"),
            .yesNo("survival", "Expected survival after intervention over 12 months with acceptable quality of life"),
            .yesNo("critical", "Critically ill"),
            anticoag,
        ]
        case .ar: return [
            VIQuestion("sev", "Severity on echo", ["Moderate", "Severe"]),
            .yesNo("sx", "Symptoms"),
            VIQuestion("ef", "LVEF", ["> 60%", "55–60%", "≤ 55%"]),
            .yesNo("lvesd", "LVESD > 50 mm, or indexed LVESD > 25 mm/m²"),
            .yesNo("lvedd", "LVEDD > 65 mm"),
            .yesNo("surg", "Other cardiac or aortic surgery planned"),
            VIQuestion("risk", "Surgical risk", ["Low", "Not low"]),
            .yesNo("effall", "LVEF drifting into 55–60% on three or more serial studies"),
            .yesNo("bicuspid", "Bicuspid valve"),
            .yesNo("candidate", "Surgical candidate"),
            age,
            anticoag,
        ]
        case .mrPrimary: return [
            VIQuestion("sev", "Severity on echo", ["Moderate", "Severe"]),
            .yesNo("sx", "Symptoms"),
            VIQuestion("nyha", "NYHA class", ["I–II", "III–IV"]),
            VIQuestion("ef", "LVEF", ["> 60%", "≤ 60%"]),
            .yesNo("lvesd", "LVESD ≥ 40 mm"),
            .yesNo("serial", "LV enlarging or LVEF falling on three or more serial studies"),
            .yesNo("durable", "Durable repair without residual MR more than 95% likely, with mortality under 1%", hint: "At a Primary or Comprehensive Valve Center"),
            VIQuestion("risk", "Surgical risk", ["Low or intermediate", "High or prohibitive"]),
            .yesNo("anatomy", "Anatomy favorable for edge-to-edge repair, life expectancy at least a year"),
            .yesNo("posterior", "Pathology limited to less than half of the posterior leaflet"),
            .yesNo("rheumatic", "Rheumatic valve"),
            age,
            anticoag,
        ]
        case .mrSecondary: return [
            VIQuestion("sev", "Severity on echo", ["Moderate", "Severe"]),
            .yesNo("hf", "Heart failure with reduced LVEF"),
            .yesNo("gdmt", "On optimal guideline-directed medical therapy, with biventricular pacing if indicated", hint: "ACE inhibitor, ARB or sacubitril-valsartan; beta-blocker; aldosterone antagonist; led by a heart-failure cardiologist"),
            VIQuestion("nyha", "NYHA class despite that therapy", ["I", "II", "III–IV"]),
            VIQuestion("ef", "LVEF", ["≥ 50%", "20–49%", "< 20%"]),
            .yesNo("lvesd70", "LVESD ≤ 70 mm"),
            .yesNo("pasp70", "PA systolic pressure ≤ 70 mmHg"),
            .yesNo("anatomy", "Anatomy suitable for edge-to-edge repair on TEE"),
            .yesNo("cabg", "Coronary bypass surgery planned"),
            .yesNo("cad", "Coronary artery disease"),
            .yesNo("af", "Atrial fibrillation with annular dilation (atrial MR)"),
        ]
        case .ms: return [
            VIQuestion("sev", "Severity", ["Severe (MVA ≤ 1.5 cm²)", "Not severe (MVA > 1.5 cm²)"]),
            VIQuestion("nyha", "NYHA class", ["I", "II", "III–IV"]),
            .yesNo("pmbc", "Favorable morphology, less than 2+ MR and no left atrial thrombus", hint: "The requirements for percutaneous mitral balloon commissurotomy (PMBC)"),
            .yesNo("calcific", "Calcific stenosis from annular calcification (non-rheumatic)"),
            .yesNo("pasp", "PA systolic pressure > 50 mmHg"),
            .yesNo("af", "New-onset atrial fibrillation"),
            .yesNo("exercise", "Exercise wedge pressure > 25 mmHg or mean gradient > 15 mmHg"),
            .yesNo("surg", "Other cardiac surgery planned, failed PMBC, or no access to PMBC"),
            .yesNo("candidate", "Surgical candidate at acceptable risk"),
        ]
        case .tr: return [
            VIQuestion("sev", "Severity on echo", ["Progressive (moderate)", "Severe"]),
            VIQuestion("cause", "Mechanism", ["Primary (leaflet)", "Secondary (annular dilation)"]),
            .yesNo("left", "Left-sided valve surgery planned"),
            .yesNo("annulus", "Annular dilation (end-diastolic diameter > 4.0 cm) or prior right-sided heart failure"),
            .yesNo("rhf", "Right-sided heart failure"),
            .yesNo("ph", "Pulmonary hypertension or left-sided disease"),
            .yesNo("medical", "Poorly responsive to medical therapy"),
            .yesNo("rv", "Progressive RV dilation or dysfunction"),
            .yesNo("prior", "Previous left-sided valve surgery"),
            .yesNo("severeph", "Severe pulmonary hypertension or RV dysfunction"),
        ]
        }
    }

    static func rules(for lesion: VILesion) -> [VIRule] {
        let severe: VICond = .q("sev", "Severe", "Very severe")
        let operable: VICond = .q("risk", "Low", "Intermediate")   // AS: the age-based SAVR/TAVI choice is for patients fit for either
        switch lesion {
        case .as_:
            let base: [VIRule] = [
            VIRule("as-d1", "Symptomatic severe high-gradient AS (stage D1)", "Aortic valve replacement", .one, "A", when: [[.yes("sx"), severe]]),
            VIRule("as-c2", "Asymptomatic severe AS with LVEF < 50% (C2)", "Aortic valve replacement", .one, "B-NR", when: [[.no("sx"), severe, .q("ef", "< 50%")]]),
            VIRule("as-surg", "Asymptomatic severe AS having other cardiac surgery (C1)", "Aortic valve replacement", .one, "B-NR", when: [[.no("sx"), severe, .yes("surg")]]),
            VIRule("as-d2", "Symptomatic low-flow, low-gradient AS with LVEF < 50% (D2)", "Aortic valve replacement", .one, "B-NR", when: [[.yes("sx"), .q("sev", "Low-flow, low-gradient"), .q("ef", "< 50%")]], note: "D2 means true severe stenosis on low-dose dobutamine stress echo: Vmax ≥ 4 m/s or mean gradient ≥ 40 mmHg with AVA ≤ 1.0 cm² at any flow."),
            VIRule("as-d3", "Symptomatic low-flow, low-gradient AS with LVEF ≥ 50% (D3)", "Aortic valve replacement when the stenosis is the most likely cause of the symptoms", .one, "B-NR", when: [[.yes("sx"), .q("sev", "Low-flow, low-gradient"), .q("ef", "≥ 60%", "50–59%")]], note: "Paradoxical low-flow AS: confirm the small stroke volume by another technique and the severity by calcium scoring before attributing the symptoms to the valve."),
            VIRule("as-2a", "Asymptomatic severe AS, low surgical risk, with an abnormal exercise test, BNP > 3× normal or rapid progression (C1)", "Aortic valve replacement is reasonable", .twoA, "B-NR", when: [[.no("sx"), severe, .q("risk", "Low"), .yes("markers")]]),
            VIRule("as-vs", "Asymptomatic very severe AS (Vmax ≥ 5 m/s), low surgical risk", "Aortic valve replacement is reasonable", .twoA, "B-NR", when: [[.no("sx"), .q("sev", "Very severe"), .q("risk", "Low")]]),
            VIRule("as-2b", "Asymptomatic severe AS with LVEF fallen below 60% on three or more serial studies", "Aortic valve replacement may be considered", .twoB, "B-NR", when: [[.no("sx"), severe, .yes("effall")]]),
            VIRule("as-mod", "Moderate AS having other cardiac surgery (B)", "Aortic valve replacement may be considered", .twoB, "C-EO", when: [[.q("sev", "Moderate"), .yes("surg")]]),
            // Which procedure
            VIRule("as-savr-age", "Age under 65, or life expectancy over 20 years", "Surgical AVR", .one, "A", group: .procedure, when: [[.q("age", "< 50", "50–64"), operable]]),
            VIRule("as-either", "Age 65–80 with no anatomic contraindication to transfemoral TAVI", "Surgical AVR or transfemoral TAVI after shared decision-making (longevity against valve durability)", .one, "A", group: .procedure, when: [[.q("age", "65–80"), .yes("tf"), operable]]),
            VIRule("as-tavi-age", "Age over 80, or life expectancy under 10 years", "Transfemoral TAVI in preference to surgery", .one, "A", group: .procedure, when: [[.q("age", "> 80"), .yes("tf"), operable]]),
            VIRule("as-tavi-risk", "High or prohibitive surgical risk with predicted survival after TAVI over 12 months", "TAVI", .one, "A", group: .procedure, when: [[.q("risk", "High or prohibitive"), .yes("survival")]]),
            VIRule("as-pall", "Predicted survival under 12 months, or minimal expected benefit", "Palliative care after shared decision-making", .one, "C-EO", group: .procedure, when: [[.no("survival")]]),
            VIRule("as-savr-anat", "Anatomy unsuitable for transfemoral TAVI and a bioprosthesis preferred", "Surgical AVR", .one, "A", group: .procedure, when: [[.no("tf"), operable]]),
            VIRule("as-savr-2a", "Asymptomatic AS operated for a 2a indication (exercise test, very severe stenosis, rapid progression, BNP)", "Surgical AVR in preference to TAVI", .one, "B-NR", group: .procedure, when: [[.no("sx"), .yes("markers")], [.no("sx"), .q("sev", "Very severe")]]),
            VIRule("as-bav", "Bicuspid valve with symptomatic severe AS", "TAVI may be considered as an alternative to surgery at a Comprehensive Valve Center", .twoB, "B-NR", group: .procedure, when: [[.yes("bicuspid"), .yes("sx")]], note: "A bicuspid valve otherwise favors surgery, as do LVOT calcification, a very small or large annulus, aortic dilation, severe primary MR and coronary disease needing bypass."),
            VIRule("as-bav-crit", "Critically ill", "Balloon aortic valvuloplasty may be considered as a bridge to AVR", .twoB, "C-EO", group: .procedure, when: [[.yes("critical")]]),
            ]
            return base + prosthesisRules(position: "Aortic", also: [operable])
        case .ar:
            let base: [VIRule] = [
            VIRule("ar-d", "Symptomatic severe AR (D)", "Aortic valve surgery, regardless of LV function", .one, "B-NR", when: [[.q("sev", "Severe"), .yes("sx")]]),
            VIRule("ar-c2", "Asymptomatic severe AR with LVEF ≤ 55% (C2)", "Aortic valve surgery, if there is no other cause of the LV dysfunction", .one, "B-NR", when: [[.q("sev", "Severe"), .no("sx"), .q("ef", "≤ 55%")]]),
            VIRule("ar-surg", "Severe AR having other cardiac surgery", "Aortic valve surgery", .one, "C-EO", when: [[.q("sev", "Severe"), .yes("surg")]]),
            VIRule("ar-c2-dim", "Asymptomatic severe AR with LVEF > 55% and LVESD > 50 mm or indexed > 25 mm/m² (C2)", "Aortic valve surgery is reasonable", .twoA, "B-NR", when: [[.q("sev", "Severe"), .no("sx"), .q("ef", "> 60%", "55–60%"), .yes("lvesd")]]),
            VIRule("ar-mod", "Moderate AR having other cardiac or aortic surgery (B)", "Aortic valve surgery is reasonable", .twoA, "C-EO", when: [[.q("sev", "Moderate"), .yes("surg")]]),
            VIRule("ar-2b", "Asymptomatic severe AR at low risk, LVEF drifting into 55–60% on serial studies or LVEDD > 65 mm (C1)", "Aortic valve surgery may be considered", .twoB, "B-NR", when: [[.q("sev", "Severe"), .no("sx"), .q("risk", "Low"), .yes("effall")], [.q("sev", "Severe"), .no("sx"), .q("risk", "Low"), .yes("lvedd")]]),
            VIRule("ar-bav", "Bicuspid valve with severe AR", "Valve repair may be considered in selected patients at a Comprehensive Valve Center", .twoB, "C-LD", group: .procedure, when: [[.yes("bicuspid"), .q("sev", "Severe")]]),
            VIRule("ar-tavi", "Isolated severe AR in a surgical candidate", "TAVI should not be performed", .three, "Harm", group: .procedure, when: [[.q("sev", "Severe"), .yes("candidate")]]),
            ]
            return base + prosthesisRules(position: "Aortic")
        case .mrPrimary:
            let base: [VIRule] = [
            VIRule("mr-d", "Symptomatic severe primary MR (D)", "Mitral intervention, regardless of LV function", .one, "B-NR", when: [[.q("sev", "Severe"), .yes("sx")]]),
            VIRule("mr-c2", "Asymptomatic severe MR with LVEF ≤ 60% or LVESD ≥ 40 mm (C2)", "Mitral surgery", .one, "B-NR", when: [[.q("sev", "Severe"), .no("sx"), .q("ef", "≤ 60%")], [.q("sev", "Severe"), .no("sx"), .yes("lvesd")]]),
            VIRule("mr-c1", "Asymptomatic severe MR with LVEF > 60% and LVESD < 40 mm (C1), a durable repair likely", "Mitral repair is reasonable at a Primary or Comprehensive Valve Center", .twoA, "B-NR", when: [[.q("sev", "Severe"), .no("sx"), .q("ef", "> 60%"), .no("lvesd"), .yes("durable")]]),
            VIRule("mr-c1-serial", "C1 with the LV enlarging or LVEF falling on serial studies", "Mitral surgery may be considered", .twoB, "C-LD", when: [[.q("sev", "Severe"), .no("sx"), .q("ef", "> 60%"), .no("lvesd"), .yes("serial")]]),
            VIRule("mr-teer", "Symptomatic severe primary MR, NYHA III–IV, high or prohibitive surgical risk, favorable anatomy, life expectancy at least a year", "Transcatheter edge-to-edge repair is reasonable", .twoA, "B-NR", when: [[.q("sev", "Severe"), .yes("sx"), .q("nyha", "III–IV"), .q("risk", "High or prohibitive"), .yes("anatomy")]]),
            VIRule("mr-repair", "Surgery for degenerative disease", "Repair rather than replacement whenever a durable repair is possible", .one, "B-NR", group: .procedure, when: [[.q("sev", "Severe"), .no("rheumatic")]]),
            VIRule("mr-posterior", "Pathology limited to less than half of the posterior leaflet", "Replacement should not be done unless repair was attempted at a valve center and failed", .three, "Harm", group: .procedure, when: [[.yes("posterior")]]),
            VIRule("mr-rheum", "Rheumatic severe primary MR with surgery indicated", "Repair may be considered at a Comprehensive Valve Center", .twoB, "B-NR", group: .procedure, when: [[.yes("rheumatic"), .q("sev", "Severe")]]),
            ]
            return base + prosthesisRules(position: "Mitral")
        case .mrSecondary: return [
            VIRule("smr-gdmt", "Severe secondary MR with heart failure and reduced LVEF", "Guideline-directed medical therapy first, led by a heart-failure cardiologist: ACE inhibitor, ARB or sacubitril-valsartan, beta-blocker, aldosterone antagonist, biventricular pacing as indicated", .one, "A", when: [[.q("sev", "Severe"), .yes("hf")]]),
            VIRule("smr-teer", "Persistent NYHA II–IV on optimal therapy, LVEF 20–50%, LVESD ≤ 70 mm, PA systolic pressure ≤ 70 mmHg, suitable anatomy", "Transcatheter edge-to-edge repair is reasonable", .twoA, "B-R", when: [[.q("sev", "Severe"), .yes("gdmt"), .q("nyha", "II", "III–IV"), .q("ef", "20–49%"), .yes("lvesd70"), .yes("pasp70"), .yes("anatomy")]]),
            VIRule("smr-cabg", "Severe secondary MR when coronary bypass surgery is undertaken", "Concomitant mitral surgery is reasonable", .twoA, "B-NR", when: [[.q("sev", "Severe"), .yes("cabg")]]),
            VIRule("smr-surg", "LVEF < 50% with NYHA III–IV despite optimal therapy", "Mitral surgery may be considered", .twoB, "B-NR", when: [[.q("sev", "Severe"), .yes("gdmt"), .q("nyha", "III–IV"), .q("ef", "20–49%", "< 20%")]]),
            VIRule("smr-cad", "Surgery with coronary disease", "Chordal-sparing replacement may be preferred over downsized annuloplasty", .twoB, "B-R", group: .procedure, when: [[.q("sev", "Severe"), .yes("gdmt"), .q("nyha", "III–IV"), .q("ef", "20–49%", "< 20%"), .yes("cad")]]),
            VIRule("smr-atrial", "Atrial annular dilation with LVEF ≥ 50% and NYHA III–IV despite therapy for heart failure and atrial fibrillation", "Mitral surgery may be considered", .twoB, "B-NR", when: [[.q("sev", "Severe"), .yes("gdmt"), .q("nyha", "III–IV"), .q("ef", "≥ 50%"), .yes("af")]]),
        ]
        case .ms: return [
            VIRule("ms-pmbc", "Symptomatic (NYHA II–IV) severe rheumatic MS with favorable morphology, less than 2+ MR and no LA thrombus", "Percutaneous mitral balloon commissurotomy at a Comprehensive Valve Center", .one, "A", when: [[.q("sev", "Severe (MVA ≤ 1.5 cm²)"), .q("nyha", "II", "III–IV"), .yes("pmbc"), .no("calcific")]]),
            VIRule("ms-surg", "NYHA III–IV severe MS not suitable for PMBC, after a failed PMBC, needing other cardiac surgery, or without access to PMBC", "Mitral surgery (repair, commissurotomy or replacement)", .one, "B-NR", when: [[.q("sev", "Severe (MVA ≤ 1.5 cm²)"), .q("nyha", "III–IV"), .no("pmbc"), .no("calcific"), .yes("candidate")], [.q("sev", "Severe (MVA ≤ 1.5 cm²)"), .q("nyha", "III–IV"), .yes("surg"), .no("calcific"), .yes("candidate")]]),
            VIRule("ms-pasp", "Asymptomatic severe MS with PA systolic pressure > 50 mmHg, PMBC-suitable", "PMBC is reasonable", .twoA, "B-NR", when: [[.q("sev", "Severe (MVA ≤ 1.5 cm²)"), .q("nyha", "I"), .yes("pasp"), .yes("pmbc")]]),
            VIRule("ms-af", "Asymptomatic severe MS with new-onset atrial fibrillation, PMBC-suitable", "PMBC may be considered", .twoB, "C-LD", when: [[.q("sev", "Severe (MVA ≤ 1.5 cm²)"), .q("nyha", "I"), .yes("af"), .yes("pmbc")]]),
            VIRule("ms-ex", "Symptomatic with MVA > 1.5 cm² but a wedge pressure > 25 mmHg or mean gradient > 15 mmHg on exercise", "PMBC may be considered", .twoB, "C-LD", when: [[.q("sev", "Not severe (MVA > 1.5 cm²)"), .q("nyha", "II", "III–IV"), .yes("exercise")]]),
            VIRule("ms-highrisk", "NYHA III–IV with suboptimal anatomy, not a surgical candidate or at high risk", "PMBC may be considered", .twoB, "B-NR", when: [[.q("sev", "Severe (MVA ≤ 1.5 cm²)"), .q("nyha", "III–IV"), .no("pmbc"), .no("candidate"), .no("calcific")]]),
            VIRule("ms-mac", "Calcific (non-rheumatic) severe MS from annular calcification with NYHA III–IV", "Intervention only after discussion of its high procedural risk", .twoB, "C-LD", when: [[.yes("calcific"), .q("nyha", "III–IV")]]),
        ]
        case .tr: return [
            VIRule("tr-left", "Severe TR (C, D) at left-sided valve surgery", "Tricuspid surgery", .one, "B-NR", when: [[.q("sev", "Severe"), .yes("left")]]),
            VIRule("tr-prog", "Progressive TR (B) at left-sided valve surgery with annular dilation or prior right-sided heart failure", "Tricuspid surgery can be beneficial", .twoA, "B-NR", when: [[.q("sev", "Progressive (moderate)"), .yes("left"), .yes("annulus")]]),
            VIRule("tr-primary", "Right-sided heart failure with severe primary TR (D)", "Isolated tricuspid surgery can be beneficial", .twoA, "B-NR", when: [[.q("sev", "Severe"), .q("cause", "Primary (leaflet)"), .yes("rhf"), .no("left")]]),
            VIRule("tr-secondary", "Right-sided heart failure with severe isolated secondary TR from annular dilation, no pulmonary hypertension or left-sided disease, poorly responsive to medical therapy", "Isolated tricuspid surgery can be beneficial", .twoA, "B-NR", when: [[.q("sev", "Severe"), .q("cause", "Secondary (annular dilation)"), .yes("rhf"), .no("ph"), .yes("medical"), .no("left")]]),
            VIRule("tr-rv", "Asymptomatic severe primary TR with progressive RV dilation or dysfunction", "Isolated tricuspid surgery may be considered", .twoB, "C-LD", when: [[.q("sev", "Severe"), .q("cause", "Primary (leaflet)"), .no("rhf"), .yes("rv")]]),
            VIRule("tr-redo", "Severe TR after previous left-sided valve surgery with right-sided heart failure, no severe pulmonary hypertension or RV dysfunction", "Reoperation may be considered", .twoB, "B-NR", when: [[.q("sev", "Severe"), .yes("prior"), .yes("rhf"), .no("severeph")]]),
        ]
        }
    }

    /// Prosthesis choice for a replaced aortic or mitral valve (the guideline's age bands).
    /// `also`: extra conditions every prosthesis rule needs (for AS, that the patient is a surgical candidate at all).
    private static func prosthesisRules(position: String, also: [VICond] = []) -> [VIRule] {
        var r: [VIRule] = [
            VIRule("pr-bio-any", "Anticoagulation impossible or unwanted", "Bioprosthesis at any age", .one, "C-EO", group: .prosthesis, when: [[.no("anticoag")] + also]),
        ]
        if position == "Aortic" {
            r += [
                VIRule("pr-ao-young", "Aortic valve, age under 50, anticoagulation acceptable", "Mechanical prosthesis is reasonable; the Ross procedure may be considered at a Comprehensive Valve Center (2b)", .twoA, "B-NR", group: .prosthesis, when: [[.q("age", "< 50"), .yes("anticoag")] + also]),
                VIRule("pr-ao-mid", "Aortic valve, age 50–65", "Either prosthesis, individualized", .twoA, "B-NR", group: .prosthesis, when: [[.q("age", "50–64"), .yes("anticoag")] + also]),
                VIRule("pr-ao-old", "Aortic valve, age over 65", "Bioprosthesis is reasonable", .twoA, "B-NR", group: .prosthesis, when: [[.q("age", "65–80", "> 80")] + also]),
            ]
        } else {
            r += [
                VIRule("pr-mi-young", "Mitral valve, age under 65, anticoagulation acceptable", "Mechanical prosthesis is reasonable", .twoA, "B-NR", group: .prosthesis, when: [[.q("age", "< 50", "50–64"), .yes("anticoag")]]),
                VIRule("pr-mi-old", "Mitral valve, age 65 or over", "Bioprosthesis is reasonable", .twoA, "B-NR", group: .prosthesis, when: [[.q("age", "65–80", "> 80")]]),
            ]
        }
        return r
    }

    static func state(of rule: VIRule, answers: [String: String]) -> VIState {
        var pending: Set<String> = []
        for conj in rule.when {
            var contradicted = false
            var missing: Set<String> = []
            for c in conj {
                if let a = answers[c.question] {
                    if !c.any.contains(a) { contradicted = true; break }
                } else {
                    missing.insert(c.question)
                }
            }
            if contradicted { continue }
            if missing.isEmpty { return .match }
            pending.formUnion(missing)
        }
        return pending.isEmpty ? .contradicted : .pending(pending)
    }

    static func evaluate(_ lesion: VILesion, answers: [String: String]) -> VIResult {
        let all = rules(for: lesion)
        let order = questions(for: lesion).map(\.id)
        var matched: [VIRule] = []
        var needed: Set<String> = []
        // Intervention rules first; the procedure and prosthesis rules only matter once something is indicated.
        let intervene = all.filter { $0.group == .intervene }
        for r in intervene {
            switch state(of: r, answers: answers) {
            case .match: matched.append(r)
            case .pending(let q): needed.formUnion(q)
            case .contradicted: break
            }
        }
        let indicated = matched.contains { $0.cls != .three }
        if indicated {
            for r in all where r.group != .intervene {
                switch state(of: r, answers: answers) {
                case .match: matched.append(r)
                case .pending(let q): needed.formUnion(q)
                case .contradicted: break
                }
            }
        }
        matched.sort { a, b in
            if a.group != b.group { return VIGroup.allCases.firstIndex(of: a.group)! < VIGroup.allCases.firstIndex(of: b.group)! }
            return a.cls < b.cls
        }
        let neededOrdered = order.filter { needed.contains($0) }
        var fallback: String?
        if matched.isEmpty && neededOrdered.isEmpty { fallback = surveillance(lesion, answers) }
        return VIResult(matched: matched, needed: neededOrdered, fallback: fallback)
    }

    /// What the guideline says when no intervention criterion is met (its surveillance intervals, Table 4).
    static func surveillance(_ lesion: VILesion, _ answers: [String: String]) -> String {
        let sev = answers["sev"] ?? ""
        switch lesion {
        case .as_:
            if sev == "Moderate" { return "No intervention criterion met: stage B. Echo every 1–2 years for moderate AS (Vmax 3–3.9 m/s); treat hypertension; reassess with any symptom." }
            return "No intervention criterion met: stage C1. Echo every 6–12 months for severe AS; an exercise test is reasonable to confirm the absence of symptoms; any symptom changes the answer."
        case .ar:
            if sev == "Moderate" { return "No intervention criterion met: stage B. Echo every 1–2 years for moderate AR; treat hypertension." }
            return "No intervention criterion met: stage C1. Echo every 6–12 months for severe AR with serial LV dimensions and ejection fraction; a fall into 55–60% or LVESD growth moves the decision."
        case .mrPrimary:
            if sev == "Moderate" { return "No intervention criterion met: stage B. Echo every 1–2 years for moderate MR." }
            return "No intervention criterion met: stage C1. Echo every 6–12 months for severe MR with LV dimensions, ejection fraction, PA pressure and rhythm; symptoms, LVEF ≤ 60% or LVESD ≥ 40 mm change the answer."
        case .mrSecondary:
            return "No intervention criterion met: optimize heart-failure therapy (and revascularization or resynchronization where indicated) and reassess the regurgitation once the ventricle has responded."
        case .ms:
            return "No intervention criterion met. Echo every 3–5 years for progressive MS (MVA > 1.5 cm²), every 1–2 years for severe (MVA 1.0–1.5 cm²) and yearly for very severe (MVA < 1.0 cm²); rate control and anticoagulation for AF, and an exercise study when symptoms and the resting findings disagree."
        case .tr:
            return "No intervention criterion met. Treat the cause (left-sided disease, pulmonary hypertension, volume overload) with diuretics for right-sided congestion, and operate before severe RV dysfunction or end-organ damage sets in."
        }
    }
}
