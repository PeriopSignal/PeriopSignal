import XCTest
@testable import PeriopSignal

/// 1.12 helper K (Ben, Nov 12): the suggested ASA class covers every recorded adult problem, by the ASA's definitions of the
/// classes where its examples name none ("heart failure" with hypertension no longer suggests class II).
final class K112Tests: XCTestCase {
    private func adult(_ problems: Set<String> = [], age: Double = 62) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = age
        r.problems = problems
        return r
    }

    private func child(_ problems: Set<String> = []) -> PatientRecord { adult(problems, age: 8) }

    private func level(_ r: PatientRecord) -> Int? { PatientRules.asaSuggestion(r)?.level }

    /// Ben's table (Nov 12), id by id.
    private let classII = ["hyperlipidemia", "arrhythmia", "chd", "aortic-repair-open", "evar", "tevar", "asthma", "osa", "cpap", "uri",
                           "resp-infection-other", "seizure", "chronic-pain", "psych", "mdd", "anxiety", "gerd", "hiatal-hernia", "gastroparesis",
                           "esophageal-disorder", "insulin", "thyroid", "anemia", "thrombocytopenia", "vwd", "thrombophilia-heme", "fvl",
                           "anticoagulation", "hiv", "hepatitis-viral", "covid-recent", "c-diff", "gdm", "ra", "oa", "spine-fusion", "scoliosis",
                           "eds", "marfan", "alcohol-abuse-former", "marijuana"]
    private let classIII = ["af", "hf", "icd", "pulm-htn", "pvd", "chd-elevated", "aaa", "taa", "taaa", "dissection-b", "asthma-uncontrolled", "ild",
                            "home-o2", "pneumonia", "pleural-effusion", "pneumothorax", "dementia", "parkinson", "neuromuscular", "sci", "cirrhosis",
                            "varices", "gi-bleed", "adrenal", "bleeding", "hemophilia-a", "hemophilia-b", "sickle", "infection-active", "tb", "ppcm",
                            "previa-accreta", "cspine-unstable", "muscular-dystrophy", "compartment-syndrome", "substance", "cocaine", "opioid-use",
                            "methamphetamine"]
    private let classIV = ["hf-decomp", "pulm-htn-severe", "dissection-a", "ich", "raised-icp", "endocarditis", "burn"]
    // Ben's list of Nov 12, and (a later note the same day) heparin-induced thrombocytopenia and heparin resistance, no class for either.
    private let noClass = ["visual-impairment", "bph", "gastric-bypass", "dysphagia", "full-stomach", "declines-blood", "mdro", "isolation",
                           "uterine-rupture-past", "fracture", "hit", "heparin-resistance"]

    // MARK: The reported case

    func testHeartFailureAloneIsClassIII() {
        XCTAssertEqual(level(adult(["hf"])), 3)
        XCTAssertEqual(PatientRules.asaSuggestion(adult(["hf"]))?.topFindings, ["Heart failure"])
    }

    func testHeartFailureWithHypertensionIsClassIIIAndNotII() throws {
        let s = try XCTUnwrap(PatientRules.asaSuggestion(adult(["htn", "hf"])))
        XCTAssertEqual(s.level, 3, "Ben's report: heart failure with hypertension suggested class II")
        XCTAssertEqual(s.label, "ASA III")
        XCTAssertEqual(s.reasons.map(\.finding), ["Heart failure", "Hypertension"], "highest class first")
        XCTAssertEqual(s.reasons.map(\.level), [3, 2])
        XCTAssertTrue(s.reasons[0].byDefinition)
        XCTAssertFalse(s.reasons[1].byDefinition, "hypertension is the ASA's own example")
        XCTAssertEqual(s.reasons[1].example, "well-controlled DM/HTN")
    }

    func testDecompensatedHeartFailureIsClassIV() {
        XCTAssertEqual(level(adult(["hf-decomp"])), 4)
        XCTAssertEqual(level(adult(["htn", "hf-decomp"])), 4)
        XCTAssertEqual(level(adult(["hf", "hf-decomp"])), 4, "the highest class among everything recorded")
    }

    // MARK: Every id in the three lists

    func testEveryIdOfTheTableGivesItsClassForAnAdult() {
        for (ids, c) in [(classII, 2), (classIII, 3), (classIV, 4)] {
            for id in ids {
                XCTAssertNotNil(PatientCatalog.problem(id), id + " is in the catalog")
                let s = PatientRules.asaSuggestion(adult([id]))
                XCTAssertEqual(s?.level, c, id)
                XCTAssertEqual(s?.reasons.first?.byDefinition, true, id + " is shown by definition")
                XCTAssertNil(s?.reasons.first?.example, id + " has no ASA example")
            }
        }
        XCTAssertEqual(classII.count + classIII.count + classIV.count, 87, "Ben's three lists, 41 + 39 + 7")
    }

    func testTheCatalogHoldsTheTableAsAFieldOnTheProblem() {
        for (ids, c) in [(classII, 2), (classIII, 3), (classIV, 4)] {
            for id in ids {
                let p = PatientCatalog.problem(id)
                XCTAssertEqual(p?.asaDef, c, id)
                XCTAssertNil(p?.asa, id + ": an example class and a class by definition are never both set")
                XCTAssertNil(p?.asaExample, id + ": the definition text is not put in asaExample")
            }
        }
    }

    func testNothingForAChildUnlessTheProblemHasAPediatricClass() {
        for id in classII + classIII + classIV {
            let p = PatientCatalog.problem(id)
            XCTAssertEqual(level(child([id])), p?.peds, id + ": a child keeps only the pediatric class")
        }
        // A few, spelled out.
        XCTAssertEqual(level(child(["hf"])), 4)
        XCTAssertEqual(level(child(["hf-decomp"])), 5)
        XCTAssertEqual(level(child(["icd"])), 4)
        XCTAssertEqual(level(child(["asthma"])), 2)
        XCTAssertEqual(level(child(["asthma-uncontrolled"])), 3)
        XCTAssertEqual(level(child(["seizure"])), 2)
        XCTAssertEqual(level(child(["muscular-dystrophy"])), 3)
        XCTAssertNil(level(child(["af"])))
        XCTAssertNil(level(child(["pneumonia"])))
        XCTAssertNil(level(child(["gdm"])))
        for r in [child(["hf"]), child(["ckd"]), child(["asthma"])] {
            XCTAssertTrue(PatientRules.asaSuggestion(r)?.reasons.allSatisfy { !$0.byDefinition } ?? false, "a child's reasons are pediatric examples")
        }
    }

    func testTheNoClassListContributesNothing() {
        XCTAssertEqual(PatientRules.asaNoClass, Set(noClass), "Ben's no-class list, exactly")
        for id in noClass {
            XCTAssertNotNil(PatientCatalog.problem(id), id)
            XCTAssertNil(level(adult([id])), id + " suggests no class")
        }
        var r = adult(Set(noClass))
        XCTAssertNil(level(r))
        r.problems.insert("htn")
        XCTAssertEqual(level(r), 2, "only hypertension counts")
        XCTAssertEqual(PatientRules.asaSuggestion(r)?.reasons.map(\.finding), ["Hypertension"])
    }

    /// Every adult problem is classed (by an ASA example, or by Ben's table), or is in the no-class list: nothing is left out
    /// without anyone having said so.
    func testEveryAdultProblemIsClassedOrDeliberatelyNot() {
        let adultProblems = PatientCatalog.systems.flatMap(\.problems)
        XCTAssertGreaterThan(adultProblems.count, 100)
        for p in adultProblems {
            let classed = p.asa != nil || p.asaDef != nil
            XCTAssertTrue(classed || PatientRules.asaNoClass.contains(p.id), p.id + " (" + p.label + ") has no class and is not in the no-class list")
            XCTAssertFalse(classed && PatientRules.asaNoClass.contains(p.id), p.id + " is both classed and in the no-class list")
            XCTAssertFalse(p.asa != nil && p.asaDef != nil, p.id + " has both an example class and a class by definition")
            if classed { XCTAssertNotNil(PatientRules.asaSuggestion(adult([p.id])), p.id + " suggests a class") }
        }
        for id in PatientRules.asaNoClass { XCTAssertTrue(adultProblems.contains { $0.id == id }, id + " is in the catalog") }
    }

    // MARK: Chronic kidney disease, by the stage recorded

    func testChronicKidneyDiseaseByStage() {
        var r = adult(["ckd"])
        XCTAssertEqual(level(r), 3, "no stage recorded: class III (Ben: CKD without stage III)")
        for (stage, expected) in [("1", 2), ("2", 2), ("3a", 3), ("3b", 3), ("4", 3), ("5", 3)] {
            r.hx.ckdStage = stage
            XCTAssertEqual(level(r), expected, "stage " + stage)
            XCTAssertEqual(PatientRules.asaSuggestion(r)?.reasons.first?.byDefinition, true)
        }
        r.hx.ckdStage = nil
        XCTAssertEqual(level(r), 3)
        // A child keeps the pediatric class whatever the stage.
        var kid = child(["ckd"]); kid.hx.ckdStage = "1"
        XCTAssertEqual(level(kid), 3)
        // ESRD not on dialysis stays the ASA's class IV example.
        XCTAssertEqual(level(adult(["ckd", "esrd-no-dialysis"])), 4)
    }

    // MARK: DVT or PE, by timing

    func testVTEByTiming() {
        var r = adult(["vte"])
        XCTAssertEqual(level(r), 2, "timing not recorded: class II")
        r.hx.vteTiming = "chronic"
        XCTAssertEqual(level(r), 2)
        r.hx.vteTiming = "acute"
        XCTAssertEqual(level(r), 3)
        r.hx.vteTiming = nil
        XCTAssertEqual(level(r), 2)
    }

    // MARK: Malignancy, by status and Metastatic

    func testMalignancyByStatusAndMetastatic() {
        var r = adult(["malignancy"])
        XCTAssertEqual(level(r), 3, "no status recorded: class III (Ben: malignancy III)")
        r.hx.malignancyStatus = "active"
        XCTAssertEqual(level(r), 3)
        r.hx.malignancyMetastatic = true
        XCTAssertEqual(level(r), 3, "active and metastatic")
        r.hx.malignancyStatus = "remission"
        XCTAssertEqual(level(r), 3, "in remission but metastatic: class III")
        r.hx.malignancyMetastatic = false
        XCTAssertEqual(level(r), 2, "in remission, not metastatic: class II")
        r.hx.malignancyStatus = nil
        r.hx.malignancyMetastatic = true
        XCTAssertEqual(level(r), 3, "metastatic with no status")
        PatientMalignancy.setStatus("remission", &r)
        PatientMalignancy.setMetastatic(false, &r)
        XCTAssertEqual(level(r), 2, "as the page writes it")
        PatientMalignancy.setStatus("active", &r)
        XCTAssertEqual(level(r), 3)
    }

    func testProstateCancerAloneFollowsTheSameRuleFromTheSameStatus() {
        var r = adult(["prostate-cancer"])
        XCTAssertEqual(level(r), 3, "no status recorded")
        XCTAssertEqual(PatientRules.asaSuggestion(r)?.reasons.map(\.finding), ["Prostate cancer"])
        r.hx.malignancyStatus = "remission"
        XCTAssertEqual(level(r), 2, "in remission, not metastatic")
        r.hx.malignancyMetastatic = true
        XCTAssertEqual(level(r), 3)
        r.hx.malignancyMetastatic = false
        r.hx.malignancyStatus = "active"
        XCTAssertEqual(level(r), 3)
    }

    func testProstateAndMalignancyAreOneReasonLine() throws {
        var r = adult(["malignancy", "prostate-cancer"])
        r.hx.malignancyStatus = "remission"
        let s = try XCTUnwrap(PatientRules.asaSuggestion(r))
        XCTAssertEqual(s.reasons.count, 1, "one fact, one line")
        XCTAssertEqual(s.reasons.first?.finding, "Malignancy")
        XCTAssertEqual(s.level, 2)
        // As the Malignancy list's Prostate chip writes it.
        var chip = adult()
        PatientMalignancy.setSite("prostate", true, &chip)
        XCTAssertTrue(chip.problems.isSuperset(of: ["malignancy", "prostate-cancer"]))
        XCTAssertEqual(PatientRules.asaSuggestion(chip)?.reasons.count, 1)
        XCTAssertEqual(PatientRules.asaSuggestion(chip)?.topFindings, ["Malignancy"])
        PatientMalignancy.setSite("lung", true, &chip)
        XCTAssertEqual(PatientRules.asaSuggestion(chip)?.reasons.count, 1)
    }

    // MARK: How a class by definition is shown

    func testAClassByDefinitionShowsItsDefinitionAndAnExampleKeepsItsQuote() throws {
        let s = try XCTUnwrap(PatientRules.asaSuggestion(adult(["hf", "ef-moderate", "hyperlipidemia", "hf-decomp"])))
        let byFinding = Dictionary(uniqueKeysWithValues: s.reasons.map { ($0.finding, $0) })
        let hf = try XCTUnwrap(byFinding["Heart failure"])
        XCTAssertTrue(hf.byDefinition)
        XCTAssertNil(hf.example, "the definition is not put in the example")
        XCTAssertEqual(hf.definitionLine, "By definition: severe systemic disease")
        XCTAssertEqual(byFinding["Heart failure, decompensated"]?.definitionLine, "By definition: severe systemic disease that is a constant threat to life")
        XCTAssertEqual(byFinding["Hyperlipidemia"]?.definitionLine, "By definition: mild systemic disease")
        let ef = try XCTUnwrap(byFinding["EF moderately reduced"])
        XCTAssertFalse(ef.byDefinition)
        XCTAssertEqual(ef.example, "moderate reduction of ejection fraction", "an ASA example keeps its quoted example")
        XCTAssertNil(ef.definitionLine)
    }

    func testTheDefinitionIsTheOneCopyTheAppAlreadyHas() {
        XCTAssertEqual(PatientFunctional.asaDefinition(2), "ASA II: a patient with mild systemic disease.")
        XCTAssertEqual(PatientFunctional.asaDefinition(3), "ASA III: a patient with severe systemic disease.")
        XCTAssertEqual(PatientFunctional.asaDefinition(4), "ASA IV: a patient with severe systemic disease that is a constant threat to life.")
        XCTAssertEqual(PatientFunctional.asaDefinition(1), "ASA I: a normal healthy patient.")
        XCTAssertEqual(PatientFunctional.asaDefinition(5), "ASA V: a moribund patient who is not expected to survive without the operation.")
        for c in 2...4 {
            XCTAssertTrue(PatientFunctional.asaDefinition(c).contains(PatientFunctional.asaDefinitionWords(c) ?? "?"), "class \(c)")
        }
        XCTAssertNil(PatientFunctional.asaDefinitionWords(1))
        XCTAssertNil(PatientFunctional.asaDefinitionWords(5))
    }

    func testTheExplanationSaysWhatByDefinitionMeans() {
        let note = PatientPreop.asaNote(adult(["hf"]))
        XCTAssertTrue(note.contains("by definition"))
        XCTAssertTrue(note.contains("assigned by this app from the ASA's class definitions where the ASA gives no example"))
        XCTAssertTrue(note.contains("the clinician assigns the class"))
        XCTAssertFalse(PatientPreop.asaNote(child(["hf"])).contains("by definition"), "nothing changes for a patient under 18")
        XCTAssertTrue(PatientCatalog.systemNote(PatientCatalog.systems[0]).contains("by definition"))
        XCTAssertTrue(PatientCatalog.systemNote(PatientCatalog.systems[1]).hasPrefix("Problems the ASA's own examples"), "the page note keeps its opening")
    }

    func testTheSummaryNamesTheFindingsAtTheSuggestedClass() {
        var r = adult(["htn", "hf"])
        r.asaClass = nil
        let line = PatientSummary.assessmentLines(r).first { $0.label == "ASA physical status" }
        XCTAssertEqual(line?.text, "Suggested ASA III, not yet chosen: Heart failure")
    }

    // MARK: Highest class wins, with E; nothing is set by itself

    func testTheHighestClassWinsAndTheReasonsAreOrderedHighestFirst() throws {
        var r = adult(["hyperlipidemia", "htn", "af", "ef-moderate", "hf-decomp", "osa"])
        let s = try XCTUnwrap(PatientRules.asaSuggestion(r))
        XCTAssertEqual(s.level, 4)
        XCTAssertEqual(s.reasons.map(\.level), s.reasons.map(\.level).sorted(by: >), "highest class first")
        XCTAssertEqual(s.reasons.map(\.level), [4, 3, 3, 2, 2, 2])
        XCTAssertEqual(s.reasons.first?.finding, "Heart failure, decompensated")
        XCTAssertEqual(s.topFindings, ["Heart failure, decompensated"])
        r.urgency = .emergency
        XCTAssertEqual(PatientRules.asaSuggestion(r)?.label, "ASA IVE", "E from the urgency")
        XCTAssertNil(r.asaClass, "the suggestion sets nothing by itself")
    }

    func testBMIAndSmokingStillCountBesideTheNewClasses() {
        var r = adult(["hyperlipidemia"])
        r.heightCm = 170; r.weightKg = 120
        XCTAssertEqual(level(r), 3, "BMI 41.5 is the ASA III example")
        r.heightCm = nil; r.weightKg = nil; r.smoking = "current"
        XCTAssertEqual(level(r), 2)
        let healthy = { () -> PatientRecord in var h = PatientRecord(); h.ageYears = 40; h.noHistory = true; return h }()
        XCTAssertEqual(level(healthy), 1)
    }

    // MARK: A record saved before opens and suggests by the new table

    func testARecordSavedBeforeOpensAndSuggestsByTheNewTable() throws {
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"ageYears":71,"sex":"male","problems":["htn","hf","ckd"],"hx":{"ckdStage":"4"}}"#.utf8))
        XCTAssertEqual(old.problems, ["htn", "hf", "ckd"])
        XCTAssertEqual(PatientRules.asaSuggestion(old)?.level, 3)
        XCTAssertEqual(Set(PatientRules.asaSuggestion(old)?.topFindings ?? []), ["Heart failure", "Chronic kidney disease"])
        let early = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"ageYears":71,"problems":["ckd","vte"],"hx":{"ckdStage":"2","vteTiming":"chronic"}}"#.utf8))
        XCTAssertEqual(level(early), 2, "stage 2 and a chronic clot: class II")
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(again, old)
        XCTAssertEqual(level(again), 3)
        // A class the clinician already chose is untouched.
        let chosen = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"ageYears":71,"problems":["hf"],"asaClass":2}"#.utf8))
        XCTAssertEqual(chosen.asaClass, 2)
        XCTAssertEqual(level(chosen), 3)
    }

    // MARK: Examples keep their class and their quote

    func testTheASAExamplesAreUnchanged() throws {
        for (id, c) in [("htn", 2), ("htn-180", 3), ("cad", 3), ("mi", 3), ("pci", 3), ("cabg", 3), ("cad-recent", 4), ("pci-recent", 4), ("ischemia", 4),
                        ("ef-moderate", 3), ("ef-severe", 4), ("valve-severe", 4), ("pacemaker", 3), ("aaa-ruptured", 5), ("copd", 3), ("cva", 3),
                        ("cva-recent", 4), ("cva-unspec", 3), ("ich-mass", 5), ("esrd-no-dialysis", 4), ("aki", 4), ("esrd-dialysis", 3),
                        ("hepatitis-active", 3), ("dm", 2), ("dic", 4), ("sepsis", 4), ("shock", 4), ("massive-trauma", 5), ("ruptured-aneurysm", 5),
                        ("pregnant", 2), ("alcohol-social", 2), ("alcohol-abuse", 3)] {
            let p = try XCTUnwrap(PatientCatalog.problem(id), id)
            XCTAssertEqual(p.asa, c, id)
            XCTAssertNil(p.asaDef, id)
            let reason = PatientRules.asaSuggestion(adult([id]))?.reasons.first
            XCTAssertEqual(reason?.level, c, id)
            XCTAssertEqual(reason?.byDefinition, false, id + " is an ASA example")
        }
        XCTAssertEqual(PatientRules.asaSuggestion(adult(["cad"]))?.reasons.first?.example, "history (>3 months) of MI, CVA, TIA, or CAD/stents")
        XCTAssertEqual(PatientRules.asaSuggestion(adult(["pulm-htn"]))?.reasons.first?.definitionLine, "By definition: severe systemic disease")
    }

    // MARK: Demo patients for the screenshots

    #if DEBUG
    func testTheDemoPatientsSuggestWhatTheShotsShow() throws {
        let hf = try XCTUnwrap(PatientDemo112Onc.record("demo-112-asa-hf"))
        XCTAssertEqual(PatientRules.asaSuggestion(hf)?.level, 3)
        XCTAssertEqual(PatientRules.asaSuggestion(hf)?.reasons.map(\.byDefinition), [true, false])
        XCTAssertEqual(PatientRules.asaSuggestion(try XCTUnwrap(PatientDemo112Onc.record("demo-112-asa-hf-decomp")))?.level, 4)
        let none = try XCTUnwrap(PatientDemo112Onc.record("demo-112-asa-noclass"))
        XCTAssertEqual(PatientRules.asaSuggestion(none)?.level, 2)
        XCTAssertEqual(PatientRules.asaSuggestion(none)?.reasons.map(\.finding), ["Hypertension"])
    }
    #endif
}
