import XCTest
@testable import PeriopSignal

/// My Patient: body size, the ASA suggestion, score pre-fills, the stepwise cardiac evaluation, the handoff text and
/// the store's clear and undo.
final class PatientTests: XCTestCase {
    private var demo: PatientRecord { PatientDemo.record }

    func testBodySize() {
        let r = demo
        XCTAssertEqual(r.bmi ?? 0, 30.3, accuracy: 0.01)
        XCTAssertEqual(r.bsa ?? 0, 2.140, accuracy: 0.001, "DuBois, as in the echo tools")
        XCTAssertEqual(r.ibw ?? 0, 73.18, accuracy: 0.01, "Devine, men")
        XCTAssertEqual(r.lbw ?? 0, 67.29, accuracy: 0.01, "Janmahasatian, men")
        XCTAssertNil(PatientBody.ibw(heightCm: 150, sex: .female), "Devine starts at 5 feet")
        XCTAssertEqual(r.person, "67-year-old man")
        var child = PatientRecord(); child.ageYears = 0.5; child.sex = .female
        XCTAssertEqual(child.person, "6-month-old girl")
    }

    func testAsaSuggestion() {
        let s = PatientRules.asaSuggestion(demo)
        XCTAssertEqual(s?.level, 3, "COPD and coronary disease are ASA III examples")
        XCTAssertEqual(s?.reasons.first?.level, 3, "the highest class leads")
        XCTAssertEqual(s?.topFindings, ["Coronary disease or MI, over 3 months", "Coronary stent, over 3 months", "COPD"])
        XCTAssertNil(s?.reasons.first { $0.finding == "COPD" }?.example, "an example that repeats the finding is not shown")
        XCTAssertEqual(s?.reasons.first { $0.finding.hasPrefix("BMI") }?.finding, "BMI 30.3", "BMI to one decimal")
        XCTAssertFalse(s?.emergency ?? true)
        var healthy = PatientRecord(); healthy.ageYears = 30; healthy.noHistory = true
        XCTAssertEqual(PatientRules.asaSuggestion(healthy)?.level, 1)
        var unknown = PatientRecord(); unknown.ageYears = 30
        XCTAssertNil(PatientRules.asaSuggestion(unknown), "nothing recorded, no suggestion")
        var obese = PatientRecord(); obese.heightCm = 170; obese.weightKg = 120
        XCTAssertEqual(PatientRules.asaSuggestion(obese)?.level, 3, "BMI 41.5 is the ASA III example")
        var child = PatientRecord(); child.ageYears = 6; child.problems = ["copd"]
        XCTAssertNil(PatientRules.asaSuggestion(child), "COPD is not among the pediatric examples")
        XCTAssertEqual(PatientRules.asaSuggestion(obese)?.reasons.first?.example, "morbid obesity (BMI ≥40)")
        var healthyAdult = PatientRecord(); healthyAdult.ageYears = 40; healthyAdult.noHistory = true
        XCTAssertEqual(PatientRules.asaSuggestion(healthyAdult)?.reasons.first?.example, "healthy, non-smoking, no or minimal alcohol use")
        var e = demo; e.urgency = .emergency; e.asaClass = 3
        XCTAssertEqual(PatientRules.asaText(e), "ASA IIIE")
        e.asaE = false
        XCTAssertEqual(PatientRules.asaText(e), "ASA III", "the clinician's E wins")
    }

    func testTermsText() {
        XCTAssertFalse(Terms.version.isEmpty)
        XCTAssertEqual(Terms.points.count, 4)
        XCTAssertTrue(Terms.sections.contains { $0.title == "No warranty" })
        XCTAssertTrue(Terms.sections.contains { $0.body.contains("not been reviewed or cleared") })
        XCTAssertTrue(Terms.privacy.contains { $0.title == "My Patient" && $0.body.contains("leaves the phone") })
    }

    func testPediatricAsaSuggestion() {
        var kid = PatientRecord(); kid.ageYears = 8
        kid.problems = ["asthma"]
        XCTAssertEqual(PatientRules.asaSuggestion(kid)?.level, 2, "asthma without exacerbation")
        XCTAssertEqual(PatientRules.asaSuggestion(kid)?.reasons.first?.example, "asthma without exacerbation")
        kid.problems = ["asthma", "p-asthma-exacerbation"]
        XCTAssertEqual(PatientRules.asaSuggestion(kid)?.level, 3)
        kid.problems = ["insulin"]
        XCTAssertEqual(PatientRules.asaSuggestion(kid)?.level, 3, "insulin-dependent diabetes")
        kid.problems = ["p-ecmo", "sepsis"]
        XCTAssertEqual(PatientRules.asaSuggestion(kid)?.level, 5)
        XCTAssertEqual(PatientRules.asaSuggestion(kid)?.topFindings, ["On ECMO"])
        kid.problems = []; kid.noHistory = true
        XCTAssertEqual(PatientRules.asaSuggestion(kid)?.level, 1)
        XCTAssertEqual(PatientRules.asaSuggestion(kid)?.reasons.first?.example, "healthy (no acute or chronic disease), normal BMI percentile for age")
        kid.smoking = "current"; kid.heightCm = 130; kid.weightKg = 80
        XCTAssertEqual(PatientRules.asaSuggestion(kid)?.level, 1, "the adult BMI and smoking examples do not apply")
        var airway = PatientRecord(); airway.ageYears = 4; airway.anesthesiaHistory = ["difficult-airway"]
        XCTAssertEqual(PatientRules.asaSuggestion(airway)?.level, 3, "difficult airway is a pediatric class III example")
        var infant = PatientRecord(); infant.ageYears = 0.08
        XCTAssertEqual(PatientRules.asaSuggestion(infant)?.level, 3, "under 6 weeks")
        infant.ageYears = 0.5
        XCTAssertNil(PatientRules.asaSuggestion(infant))
        var teen = PatientRecord(); teen.ageYears = 17; teen.sex = .female; teen.problems = ["preeclampsia-severe"]
        XCTAssertEqual(PatientRules.asaSuggestion(teen)?.level, 3, "the obstetric examples apply at any age")
        XCTAssertEqual(PatientCatalog.systems(for: kid).first?.id, "peds")
        XCTAssertFalse(PatientCatalog.systems(for: demo).contains { $0.id == "peds" }, "no pediatric list for an adult")
        for p in PatientCatalog.pediatric.problems {
            XCTAssertNotNil(p.peds, p.id); XCTAssertNotNil(p.pedsExample, p.id)
        }
        XCTAssertEqual(Set(PatientCatalog.allProblems.map(\.id)).count, PatientCatalog.allProblems.count, "problem ids are unique")
    }

    func testScorePrefills() {
        XCTAssertEqual(PatientRules.prefill("rcri", demo).on, ["surgery", "ihd", "insulin"])
        let a = PatientRules.prefill("ariscat", demo)
        XCTAssertEqual(a.choices["age"], "51–80")
        XCTAssertEqual(a.choices["spo2"], "91–95%")
        XCTAssertEqual(a.choices["incision"], "Upper abdominal")
        XCTAssertEqual(a.choices["duration"], "> 3 h")
        XCTAssertTrue(a.on.isEmpty)
        XCTAssertEqual(PatientRules.prefill("stopbang", demo).on, ["snoring", "pressure", "age", "neck", "gender"])
        XCTAssertEqual(PatientRules.prefill("apfel", demo).on, ["nonsmoker", "history"])
        // every pre-filled id and choice exists in its score
        for id in ["rcri", "ariscat", "stopbang", "apfel"] {
            let def = try? XCTUnwrap(Scores.byID(id))
            let s = PatientRules.prefill(id, demo)
            let ids = Set(def?.items.map(\.id) ?? [])
            XCTAssertTrue(s.on.isSubset(of: ids), "\(id): \(s.on.subtracting(ids))")
            for (k, v) in s.choices {
                guard let item = def?.items.first(where: { $0.id == k }), case .choice(let options) = item.input else { return XCTFail("\(id): \(k) is not a choice") }
                XCTAssertTrue(options.contains { $0.label == v }, "\(id): \(k) has no option \(v)")
            }
        }
    }

    func testDasiAndCardiacStep() {
        var r = PatientRecord()
        r.dasi = Set(PatientFunctional.dasiItems.map(\.id))
        XCTAssertEqual(PatientFunctional.dasi(r) ?? 0, 58.2, accuracy: 0.001, "the 12 weights sum to 58.2")
        r.dasi = ["self-care", "walk-indoors", "walk-blocks", "stairs", "light-housework", "moderate-housework", "yardwork", "sex"]
        XCTAssertEqual(PatientFunctional.dasi(r) ?? 0, 28.7, accuracy: 0.001)
        XCTAssertEqual(PatientFunctional.dasiText(34.45), "DASI 34.45 of 58.2 · above 34", "not rounded down to 34")
        XCTAssertEqual(PatientFunctional.dasiText(34), "DASI 34 of 58.2 · 34 or less: poor")

        XCTAssertEqual(PatientFunctional.riskModifiers(demo), ["prior coronary stent"])
        XCTAssertTrue(PatientFunctional.cardiacStep(demo).title.hasPrefix("Good functional capacity"), "RCRI 3 with 4 METs or more")
        var poor = demo; poor.mets = "lt4"
        XCTAssertTrue(PatientFunctional.cardiacStep(poor).title.hasPrefix("Poor or unknown"))
        XCTAssertTrue(PatientFunctional.cardiacStep(poor).alert)
        var dasiWins = poor; dasiWins.dasi = Set(PatientFunctional.dasiItems.map(\.id))
        XCTAssertTrue(PatientFunctional.cardiacStep(dasiWins).title.hasPrefix("Good"), "a recorded DASI above 34 decides")
        var normal = poor; normal.labs["ntprobnp"] = 180
        XCTAssertEqual(PatientFunctional.cardiacStep(normal).title, "Natriuretic peptide normal: proceed")
        var raised = poor; raised.labs["bnp"] = 92.5
        XCTAssertEqual(PatientFunctional.cardiacStep(raised).title, "Natriuretic peptide raised", "BNP over 92")
        var edge = poor; edge.labs["bnp"] = 92
        XCTAssertFalse(PatientFunctional.cardiacStep(edge).alert, "BNP 92 is not over 92")
        var nt = poor; nt.labs["ntprobnp"] = 300
        XCTAssertTrue(PatientFunctional.cardiacStep(nt).alert, "NT-proBNP 300 or more")
        var low = PatientRecord(); low.ageYears = 60; low.problems = ["htn"]
        XCTAssertTrue(PatientFunctional.cardiacStep(low).title.hasPrefix("Low estimated risk"))
        low.frail = true
        XCTAssertFalse(PatientFunctional.cardiacStep(low).title.hasPrefix("Low"), "frailty adds risk beyond the RCRI")
        var em = demo; em.urgency = .emergency
        XCTAssertTrue(PatientFunctional.cardiacStep(em).title.hasPrefix("Emergency"))
        var active = demo; active.activeCardiac = ["acs"]
        XCTAssertTrue(PatientFunctional.cardiacStep(active).title.hasPrefix("Acute cardiac condition"))
        var decompensated = demo; decompensated.problems.insert("hf-decomp")
        XCTAssertTrue(PatientFunctional.cardiacStep(decompensated).title.hasPrefix("Acute cardiac condition"), "from the problem list too")
        var urgent = demo; urgent.urgency = .urgent
        XCTAssertTrue(PatientFunctional.cardiacStep(urgent).detail.hasPrefix("Urgent surgery"))
    }

    /// The 2024 AHA/ACC Figure 1, box by box.
    func testFigureOne() {
        // First question: cardiovascular risk factors, disease or symptoms.
        var healthy = PatientRecord()
        healthy.ageYears = 40; healthy.sex = .female; healthy.heightCm = 165; healthy.weightKg = 60; healthy.smoking = "never"
        XCTAssertTrue(PatientFunctional.noCardiacRisk(healthy))
        XCTAssertEqual(PatientFunctional.cardiacStep(healthy).title, "No cardiovascular risk factors, disease or symptoms: proceed")
        var noWeight = healthy; noWeight.weightKg = nil
        XCTAssertFalse(PatientFunctional.noCardiacRisk(noWeight), "obesity can't be ruled out")
        var noSmoking = healthy; noSmoking.smoking = nil
        XCTAssertFalse(PatientFunctional.noCardiacRisk(noSmoking), "smoking not recorded")
        var woman = healthy; woman.ageYears = 64
        XCTAssertTrue(PatientFunctional.riskFactors(woman).isEmpty, "women count from over 65")
        var man = healthy; man.sex = .male; man.ageYears = 56
        XCTAssertEqual(PatientFunctional.riskFactors(man), ["man over 55"])
        var obese = healthy; obese.weightKg = 90
        XCTAssertEqual(PatientFunctional.riskFactors(obese), ["obesity"], "BMI 33")
        var family = healthy; family.problems = ["fh-cad"]
        XCTAssertEqual(PatientFunctional.riskFactors(family), ["family history of premature CAD"])
        var symptomatic = healthy; symptomatic.cardiacSymptoms = ["syncope"]
        XCTAssertFalse(PatientFunctional.noCardiacRisk(symptomatic))
        var raisedBP = healthy; raisedBP.vitals["sbp"] = 150
        XCTAssertFalse(PatientFunctional.noCardiacRisk(raisedBP), "a raised reading doesn't end the evaluation")
        var fast = healthy; fast.vitals["hr"] = 118
        XCTAssertFalse(PatientFunctional.noCardiacRisk(fast))

        // Acute conditions, in the figure's words.
        XCTAssertEqual(PatientFunctional.activeCardiac.map(\.label), ["Acute coronary syndrome", "Decompensated heart failure", "Unstable arrhythmia"])
        var acute = demo; acute.activeCardiac = ["arrhythmia"]
        XCTAssertTrue(PatientFunctional.cardiacStep(acute).detail.contains("deferring surgery, noninvasive treatment or palliation"))

        // The seven risk modifiers.
        var r = PatientRecord(); r.problems = ["chd"]
        XCTAssertTrue(PatientFunctional.riskModifiers(r).isEmpty, "only elevated-risk congenital disease")
        r.problems = ["valve-severe", "pulm-htn-severe", "chd-elevated", "pci-recent", "cva-recent", "pacemaker"]; r.frail = true
        XCTAssertEqual(PatientFunctional.riskModifiers(r), ["severe valve disease", "severe pulmonary hypertension", "elevated-risk congenital heart disease", "coronary stent within 3 months", "stroke or TIA within 3 months", "pacemaker", "frailty"])
        var mi = PatientRecord(); mi.problems = ["cad-recent"]
        XCTAssertTrue(PatientFunctional.riskModifiers(mi).isEmpty, "a recent MI is not one of the figure's modifiers")

        // Branches after the risk estimate.
        let branch = PatientFunctional.branchAdvice(demo)
        XCTAssertEqual(branch.count, 4, "\(branch)")
        XCTAssertTrue(branch[0].hasPrefix("Consider team-based consultation"), "a modifier is present")
        XCTAssertTrue(branch[1].contains("ECG") && branch[1].hasSuffix("(class 2a)."), "known coronary disease")
        XCTAssertTrue(branch[2].hasPrefix("An echo is recommended"))
        XCTAssertTrue(branch[3].hasPrefix("Consider starting guideline-directed medical therapy"))
        var elevatedOnly = PatientRecord(); elevatedOnly.ageYears = 70; elevatedOnly.problems = ["insulin"]; elevatedOnly.highRiskSurgery = true
        let b2 = PatientFunctional.branchAdvice(elevatedOnly)
        XCTAssertEqual(b2.count, 2, "RCRI 2 without modifiers: \(b2)")
        XCTAssertTrue(b2[0].hasSuffix("(class 2b)."), "no known disease or symptoms")
        var low = PatientRecord(); low.ageYears = 60; low.problems = ["htn"]
        XCTAssertTrue(PatientFunctional.branchAdvice(low).isEmpty, "low risk and no modifiers: proceed")
        low.frail = true
        XCTAssertEqual(PatientFunctional.branchAdvice(low).count, 3, "a modifier at low calculated risk: consult, echo, therapy")

        // Functional capacity, testing and biomarkers.
        var poor = demo; poor.mets = "lt4"
        XCTAssertTrue(PatientFunctional.cardiacStep(poor).detail.contains("If more testing would not change management, proceed"))
        var raised = poor; raised.labs["bnp"] = 150
        let d = PatientFunctional.cardiacStep(raised).detail
        XCTAssertTrue(d.contains("stress testing or CT coronary angiography (class 2b)"))
        XCTAssertTrue(d.hasSuffix("postoperative troponin surveillance may be considered (class 2b)."))

        // The H&P carries the symptoms and the figure's ECG, echo and consultation boxes.
        var noted = demo; noted.cardiacSymptoms = ["chest-pain", "murmur"]
        let lines = PatientSummary.assessmentLines(noted)
        XCTAssertEqual(lines.first { $0.label == "Cardiac symptoms" }?.text, "Chest pain; Murmur")
        XCTAssertEqual(lines.filter { $0.label == "Cardiac advice" }.count, 4, "3 boxes and the stent advice")
    }

    func testConditionAdvice() {
        let advice = PatientFunctional.conditionAdvice(demo)
        XCTAssertEqual(advice.count, 1, "\(advice)")
        XCTAssertTrue(advice[0].hasPrefix("Prior stent"))
        XCTAssertTrue(PatientFunctional.cardiacStep(demo).detail.hasSuffix("The condition-specific steps below still apply."))
        var recentStent = demo; recentStent.problems.remove("pci"); recentStent.problems.insert("pci-recent")
        XCTAssertTrue(PatientFunctional.conditionAdvice(recentStent).contains { $0.hasPrefix("Stent within 3 months") })
        XCTAssertFalse(PatientFunctional.conditionAdvice(recentStent).contains { $0.hasPrefix("Prior stent") })
        var dyspnea = PatientRecord(); dyspnea.ageYears = 70; dyspnea.cardiacSymptoms = ["dyspnea"]
        XCTAssertTrue(PatientFunctional.conditionAdvice(dyspnea).contains { $0.hasPrefix("New dyspnea or signs of heart failure") && $0.hasSuffix("(class 1).") })
        var stroke = demo; stroke.problems.insert("cva-recent")
        XCTAssertTrue(PatientFunctional.conditionAdvice(stroke).contains { $0.hasPrefix("Stroke or TIA within 3 months") })
        var bp = demo; bp.vitals["sbp"] = 185
        XCTAssertTrue(PatientFunctional.conditionAdvice(bp).contains { $0.hasPrefix("Blood pressure 180/110") })
        var stented = demo; stented.medFlags.insert("p2y12")
        XCTAssertFalse(PatientFunctional.conditionAdvice(stented).contains { $0.hasPrefix("Prior stent") }, "the P2Y12 note carries the timing")
        var healthy = PatientRecord(); healthy.ageYears = 40
        XCTAssertTrue(PatientFunctional.conditionAdvice(healthy).isEmpty)
        let p2y12 = PatientFunctional.medNotes["p2y12"] ?? ""
        XCTAssertTrue(p2y12.contains("(class 2a)") && p2y12.contains("(class 2b)"), "6 months is 2a, 3 months 2b")
        XCTAssertTrue((PatientFunctional.medNotes["acei"] ?? "").hasPrefix("In selected patients with controlled blood pressure"))
    }

    func testMaskVentilationPredictors() {
        XCTAssertEqual(PatientAirway.langeron(demo), ["age over 55", "BMI over 26", "snoring"])
        XCTAssertEqual(PatientAirway.kheterpal(demo), ["male", "sleep apnea", "Mallampati III"])
        XCTAssertEqual(PatientAirway.maskRisk(demo).filter { $0.alert }.count, 2)
        var young = PatientRecord(); young.ageYears = 30; young.sex = .female; young.heightCm = 165; young.weightKg = 60
        XCTAssertTrue(PatientAirway.maskRisk(young).isEmpty)
        var child = demo; child.ageYears = 10
        XCTAssertTrue(PatientAirway.maskRisk(child).isEmpty, "adult predictors only")
        XCTAssertEqual(PatientAirway.mallampatiLine(4), "Mallampati IV: soft palate not visible")
        XCTAssertEqual(PatientAirway.mallampatiLine(3), "Mallampati III: soft palate and the base of the uvula visible")
    }

    func testNumbersShowAsTyped() {
        XCTAssertEqual(NumText.exact(12.8), "12.8")
        XCTAssertEqual(NumText.exact(96.5), "96.5")
        XCTAssertEqual(NumText.exact(162), "162")
        XCTAssertEqual(NumText.exact(1.25), "1.25")
        XCTAssertEqual(Double(NumText.exact(0.1 + 0.2)), 0.1 + 0.2, "exact parses back to the same value")
        XCTAssertEqual(NumText.short(34.449), "34.45")
        XCTAssertEqual(NumText.short(30.299, places: 1), "30.3")
        XCTAssertEqual(NumText.short(1800), "1800")
        var r = demo; r.weightKg = 96.5
        XCTAssertTrue(r.oneLiner.contains("96.5 kg"), "a typed weight is not rounded")
    }

    func testHandoffText() {
        let t = HandoffWriter.text(demo)
        for s in ["ANESTHESIA HANDOFF", "67-year-old man", "Laparoscopic sigmoid colectomy", "ASA III", "Penicillin", "Mallampati III",
                  "Intubation easy", "PACU", "RCRI 3", "No notable events", "Crystalloid 1800 mL", "Hb 12.8", "Creatinine 1.1",
                  "Medications: Metoprolol", "Langeron", "Call if: ", "At handoff: extubated."] {
            XCTAssertTrue(t.contains(s), "handoff has \(s)")
        }
        XCTAssertFalse(t.contains("(Beta-blocker"), "the flags do not repeat the typed list")
        XCTAssertFalse(t.contains("Cardiac evaluation"), "the cardiac step stays out of the handoff")
        XCTAssertFalse(t.contains("Cardiac advice"), "and so does the preoperative advice")
        var hard = demo; hard.intubation = "difficult"; hard.airwayFollowUp = ["told"]
        let h = HandoffWriter.text(hard)
        XCTAssertTrue(h.contains("Difficult-airway follow-up: Patient told. Still to do: document"), h)
        var vent = demo; vent.airwayAtEnd = "intubated"; vent.ventilation = "VC 450 × 14, PEEP 8"; vent.fluids["wholeBlood"] = 2
        let v = HandoffWriter.text(vent)
        XCTAssertTrue(v.contains("At handoff: intubated, VC 450 × 14, PEEP 8."), v)
        XCTAssertTrue(v.contains("Whole blood 2 units"), v)
        XCTAssertEqual(PatientCatalog.gradeDetail("2b"), "Only the arytenoids or the very posterior origin of the cords visible", "Yentis and Lee's wording")
        XCTAssertEqual(PatientCatalog.grades.compactMap { PatientCatalog.gradeDetail($0) }.count, PatientCatalog.grades.count, "every grade has its meaning")
        var alert = demo; alert.medFlags.insert("sglt2")
        XCTAssertTrue(HandoffWriter.text(alert).contains("Medication alerts: SGLT2 inhibitor"))
        XCTAssertFalse(t.contains("Optional("))
        XCTAssertFalse(t.contains("nil"))
        XCTAssertEqual(HandoffWriter.text(PatientRecord()).components(separatedBy: "\n").first, "ANESTHESIA HANDOFF")
    }

    func testShortHandoff() {
        let s = HandoffWriter.shortText(demo)
        let rows = s.components(separatedBy: "\n")
        XCTAssertEqual(rows.first, "ANESTHESIA HANDOFF (SHORT)")
        for x in ["67-year-old man", "Laparoscopic sigmoid colectomy", "ASA III", "Allergies: Penicillin (rash)", "Airway: Mask ventilation easy.",
                  "At handoff: extubated.", "Lines: ", "Drips: Phenylephrine", "Events: No notable events",
                  "Plan: PACU. Call if SBP under 90 or over 170; SpO₂ under 92%."] {
            XCTAssertTrue(s.contains(x), "short handoff has \(x)\n\(s)")
        }
        for x in ["Elective", "HISTORY", "Hb 12.8", "Crystalloid", "RCRI", "Mallampati", "Medications"] {
            XCTAssertFalse(s.contains(x), "short handoff leaves out \(x)")
        }
        XCTAssertLessThanOrEqual(rows.count, 14, "one screen")
        var hard = demo; hard.intubation = "difficult"; hard.urgency = .emergency; hard.nkda = true; hard.allergies = ""
        let h = HandoffWriter.shortText(hard)
        XCTAssertTrue(h.contains("Intubation DIFFICULT"))
        XCTAssertTrue(h.contains("Difficult-airway follow-up: Still to do:"), h)
        XCTAssertTrue(h.contains(" · Emergency · "), "the timing shows when it isn't elective")
        XCTAssertTrue(h.contains("Allergies: No known drug allergies"))
        let blank = HandoffWriter.shortText(PatientRecord())
        XCTAssertEqual(blank.components(separatedBy: "\n").first, "ANESTHESIA HANDOFF (SHORT)")
        XCTAssertFalse(blank.contains(": \n"))
        XCTAssertTrue(HandoffWriter.text(demo).hasSuffix(". Check against the chart."), "the full one keeps its footer")
    }

    func testRecordCoding() throws {
        let data = try JSONEncoder().encode(demo)
        let back = try JSONDecoder().decode(PatientRecord.self, from: data)
        var a = demo, b = back
        a.updated = nil; b.updated = nil
        XCTAssertEqual(a.lines.map(\.text), b.lines.map(\.text))
        XCTAssertEqual(a.problems, b.problems)
        XCTAssertEqual(a.scores["rcri"]?.points, b.scores["rcri"]?.points)
        var c = demo
        c.urgency = .timeSensitive; c.maskGrade = 2; c.sga = "easy"; c.airwayFollowUp = ["told"]; c.callIf = "SBP under 90"; c.frail = true
        c.cardiacSymptoms = ["syncope"]
        let c2 = try JSONDecoder().decode(PatientRecord.self, from: try JSONEncoder().encode(c))
        XCTAssertEqual(c2.urgency, .timeSensitive)
        XCTAssertEqual(c2.maskGrade, 2)
        XCTAssertEqual(c2.sga, "easy")
        XCTAssertEqual(c2.airwayFollowUp, ["told"])
        XCTAssertEqual(c2.callIf, "SBP under 90")
        XCTAssertTrue(c2.frail)
        XCTAssertEqual(c2.cardiacSymptoms, ["syncope"])
        let empty = try JSONDecoder().decode(PatientRecord.self, from: Data("{\"weightKg\": 70, \"future\": 1}".utf8))
        XCTAssertEqual(empty.weightKg, 70, "an older or newer file still opens")
        XCTAssertTrue(PatientRecord().isEmpty)
        XCTAssertFalse(demo.isEmpty)
    }

    @MainActor func testStoreClearAndUndo() {
        let store = PatientStore(url: nil)
        XCTAssertTrue(store.isEmpty)
        store.update { $0.weightKg = 80; $0.ageYears = 50 }
        XCTAssertEqual(store.weightKg, 80)
        XCTAssertNotNil(store.record.updated)
        store.clear()
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(store.canUndo)
        store.undoClear()
        XCTAssertEqual(store.weightKg, 80)
        XCTAssertFalse(store.canUndo)
        store.clear()
        store.update { $0.ageYears = 20 }
        XCTAssertFalse(store.canUndo, "an edit after clearing ends the undo")
    }

    func testPrompts() {
        let ids = PatientRules.prompts(demo).map(\.id)
        XCTAssertEqual(Array(ids.prefix(4)), ["rcri", "ariscat", "stopbang", "apfel"])
        XCTAssertEqual(PatientRules.prompts(demo).first?.done, "RCRI 3 · Class IV · 3 or more")
        var blocked = demo; blocked.medFlags.insert("anticoagulant")
        XCTAssertTrue(PatientRules.prompts(blocked).contains { $0.route == "neuraxial" }, "a block is planned with an anticoagulant")
        for p in PatientRules.prompts(blocked) { XCTAssertNotNil(RefRoute(key: p.route), "\(p.route) opens a tool") }
    }
}
