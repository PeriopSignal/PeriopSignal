import XCTest
@testable import PeriopSignal

/// The 1.9 system pages (Ben's Wanted Changes): every page's items and options through HistorySections (select, clear,
/// the edits the pages make), the summary words, shared items listed once, the From Obstetric cross-references, the ASA
/// classes the new ids may and may not change, and a record saved by 1.8.3 opening on the right pages.
final class PatientPages19Tests: XCTestCase {
    private static let newPages = ["renal", "gi", "endo", "heme", "infectious", "acute", "ob", "msk", "social"]

    private func adult(_ problems: Set<String>) -> PatientRecord {
        var r = PatientRecord(); r.ageYears = 45; r.problems = problems
        return r
    }
    private func child(_ problems: Set<String>) -> PatientRecord {
        var r = PatientRecord(); r.ageYears = 8; r.problems = problems
        return r
    }
    private func section(_ system: String, _ id: String) throws -> HistorySection {
        try XCTUnwrap(HistorySections.sections(system)?.first { $0.id == id }, system + "." + id)
    }
    private func system(_ id: String) throws -> PatientSystem { try XCTUnwrap(PatientCatalog.allSystems.first { $0.id == id }, id) }
    private func items(_ system: String, _ r: PatientRecord) throws -> [String] { HistorySections.items(try self.system(system), r) }
    private func line(_ label: String, _ r: PatientRecord) -> String? { PatientSummary.historyLines(r).first { $0.label == label }?.text }
    private func asa(_ r: PatientRecord) -> Int? { PatientRules.asaSuggestion(r)?.level }

    // MARK: Every page

    func testEveryPageHasItsItemsAndTheClosingFields() throws {
        for id in ["cv", "resp", "neuro"] + Self.newPages {
            let s = try XCTUnwrap(HistorySections.sections(id), id)
            XCTAssertEqual(s.suffix(2).map(\.id), ["other-disorders", "other"], id + " ends with Other [system] disorders and Other details")
            XCTAssertEqual(s.last?.title, "Other details", id)
            XCTAssertEqual(s.dropLast().last?.title, HistorySections.otherTitle(id), id)
            XCTAssertEqual(Set(s.map(\.id)).count, s.count, id + ": item ids are unique on the page")
            let sys = try system(id)
            let onPage = Set(s.flatMap(\.members))
            for p in sys.problems { XCTAssertTrue(onPage.contains(p.id), id + ": " + p.id + " sits under an item") }
            for m in onPage { XCTAssertNotNil(PatientCatalog.system(of: m), id + ": " + m + " is in the catalog") }
        }
        XCTAssertNil(HistorySections.sections("peds"), "the Pediatric list stays as chips")
        XCTAssertEqual(HistorySections.social.first?.id, "smoking", "Smoking is the first item of Smoking & Substances")
    }

    func testSharedItems() {
        var shared: Set<String> = []
        for id in ["cv", "resp", "neuro"] + Self.newPages {
            for s in HistorySections.sections(id) ?? [] where HistorySections.isShared(s, on: id) { shared.insert(id + "." + s.id) }
        }
        XCTAssertEqual(shared, ["cv.endocarditis", "infectious.sepsis", "infectious.uri", "infectious.pneumonia", "neuro.cspine",
                                "acute.aorta-acute", "ob.thrombophilia"])
    }

    /// One id on two pages is said once, under its home system.
    func testSharedItemsAreListedOnce() throws {
        var r = adult(["sepsis", "endocarditis", "uri", "pneumonia", "dissection-a", "cspine-unstable", "thrombophilia-heme"])
        r.hx.sepsisSource = "pneumonia"
        let names = Set(PatientCatalog.allSystems.map(\.name))
        let lines = PatientSummary.historyLines(r).filter { names.contains($0.label ?? "") }
        func count(_ word: String) -> Int { lines.filter { $0.text.contains(word) }.count }
        XCTAssertEqual(count("sepsis"), 1)
        XCTAssertEqual(line("Acute illness", r), "sepsis, source pneumonia")
        XCTAssertEqual(count("endocarditis"), 1)
        XCTAssertEqual(line("Infectious", r), "infective endocarditis")
        XCTAssertEqual(count("URI"), 1)
        XCTAssertEqual(line("Respiratory", r), "respiratory infection: URI, pneumonia")
        XCTAssertEqual(count("dissection"), 1)
        XCTAssertEqual(line("Cardiovascular", r), "aortopathy: type A dissection")
        XCTAssertEqual(count("C-spine"), 1)
        XCTAssertEqual(line("Musculoskeletal", r), "unstable C-spine")
        XCTAssertNil(line("Neurologic", r))
        XCTAssertEqual(count("thrombophilia"), 1)
        XCTAssertEqual(line("Hematologic", r), "thrombophilia")
        XCTAssertNil(line("Obstetric", r))
        // Every id has words on its home page and none on the page it is only shown on.
        for id in Self.newPages + ["resp", "neuro"] {
            for p in try system(id).problems {
                XCTAssertFalse(try items(id, adult([p.id])).isEmpty, id + ": " + p.id + " has summary words")
            }
        }
        for (page, ids) in [("infectious", ["sepsis", "uri", "pneumonia"]), ("cv", ["endocarditis"]), ("acute", ["dissection-a", "dissection-b"]),
                            ("neuro", ["cspine-unstable"]), ("ob", ["thrombophilia-heme", "fvl"])] {
            for id in ids { XCTAssertEqual(try items(page, adult([id])), [], page + " does not repeat " + id) }
        }
    }

    func testClosingFieldsFollowTheItems() {
        var r = adult(["aki"])
        r.systemOther["renal"] = "Renal artery stenosis"
        r.systemNotes["renal"] = "Nephrology follows"
        XCTAssertEqual(line("Renal", r), "AKI; Renal artery stenosis; Nephrology follows")
        var other = PatientRecord()
        other.systemOther["msk"] = "Paget disease"
        let s = HistorySections.msk.first { $0.id == "other-disorders" }!
        XCTAssertTrue(HistorySections.isSelected(s, system: "msk", other))
        HistorySections.clear(s, system: "msk", &other)
        XCTAssertNil(other.systemOther["msk"])
    }

    // MARK: Cardiovascular, Respiratory, Neurologic additions

    func testCardiovascularAdditions() throws {
        var r = adult(["af", "pacemaker"])
        r.hx.afType = "permanent"
        r.hx.pacerDependent = true
        r.hx.ciedSide = "left"
        r.hx.deviceDetails = "Medtronic"
        XCTAssertEqual(HistorySections.cvItems(r), ["permanent AF", "pacemaker, pacer dependent, left-sided generator (Medtronic)"])
        r.hx.afType = "longstanding"
        XCTAssertEqual(HistorySections.cvItems(r).first, "long-standing persistent AF")
        XCTAssertEqual(HistorySections.afTypes.map(\.id), ["paroxysmal", "persistent", "longstanding", "permanent"])
        let arrhythmia = try section("cv", "arrhythmia"), device = try section("cv", "device")
        HistorySections.clear(arrhythmia, system: "cv", &r)
        HistorySections.clear(device, system: "cv", &r)
        XCTAssertTrue(r.problems.isEmpty)
        XCTAssertNil(r.hx.afType); XCTAssertFalse(r.hx.pacerDependent); XCTAssertNil(r.hx.ciedSide)
        var dep = PatientRecord(); dep.hx.pacerDependent = true
        XCTAssertTrue(HistorySections.isSelected(device, system: "cv", dep), "pacer dependence alone keeps the item open")
        var typed = adult(["af"]); typed.hx.afType = "permanent"
        XCTAssertEqual(asa(adult(["af"])), asa(typed), "the AF type changes no class")
    }

    func testPleuralEffusion() throws {
        let s = try section("resp", "pleural")
        var r = PatientRecord()
        HistorySections.setOption("pleural-effusion", true, in: s, &r)
        r.hx.pleuralSide = "left"
        r.hx.pleuralFluid = "hemothorax"
        HistorySections.setPleuralDrained(true, &r)
        HistorySections.setChestTube(true, &r)
        r.hx.chestTubeSides = ["left"]
        XCTAssertEqual(HistorySections.respItems(r), ["left hemothorax, drained, chest tube left"])
        HistorySections.setChestTube(false, &r)
        XCTAssertTrue(r.hx.chestTubeSides.isEmpty, "no chest tube: no sides")
        HistorySections.setChestTube(true, &r); r.hx.chestTubeSides = ["right"]
        HistorySections.setPleuralDrained(false, &r)
        XCTAssertNil(r.hx.chestTube, "not drained: no chest tube")
        XCTAssertEqual(HistorySections.respItems(r), ["left hemothorax, not drained"])
        HistorySections.setOption("pneumothorax", true, in: s, &r)
        r.hx.pleuralFluid = nil; r.hx.pleuralSide = "bilateral"
        XCTAssertEqual(HistorySections.respItems(r), ["bilateral pleural effusion and pneumothorax, not drained"])
        HistorySections.clear(s, system: "resp", &r)
        XCTAssertTrue(r.problems.isEmpty)
        XCTAssertNil(r.hx.pleuralSide); XCTAssertNil(r.hx.pleuralDrained)
        XCTAssertNil(asa(adult(["pleural-effusion", "pneumothorax"])))
    }

    func testNeurologicAdditions() throws {
        var r = adult(["visual-impairment", "psych", "mdd", "anxiety"])
        r.hx.visualImpairment = "acute"
        r.hx.psychOther = "bipolar disorder"
        XCTAssertEqual(HistorySections.neuroItems(r), ["visual impairment, acute", "psychological disorder: MDD, anxiety, bipolar disorder"])
        let psych = try section("neuro", "psych")
        HistorySections.setOption("mdd", false, in: psych, &r)
        XCTAssertTrue(r.has("psych"), "the item stays chosen")
        HistorySections.clear(psych, system: "neuro", &r)
        XCTAssertEqual(r.problems, ["visual-impairment"])
        XCTAssertEqual(r.hx.psychOther, "")
        XCTAssertEqual(HistorySections.neuroItems(adult(["psych"])), ["psychological disorder"])
    }

    // MARK: Renal

    func testRenal() throws {
        let ckd = try section("renal", "ckd"), hd = try section("renal", "hemodialysis")
        var r = PatientRecord()
        HistorySections.select(ckd, &r)
        r.hx.ckdStage = "3b"
        XCTAssertEqual(HistorySections.renalItems(r), ["CKD stage 3b"])
        HistorySections.select(hd, &r)
        r.hx.dialysisSchedule = "mwf"
        HistorySections.setDialysisAccess(["fistula"], &r)
        r.hx.fistulaSite = "L forearm"
        XCTAssertEqual(line("Renal", r), "CKD stage 3b; ESRD on hemodialysis M/W/F (L forearm fistula)")
        HistorySections.setDialysisAccess(["fistula", "catheter"], &r)
        r.hx.dialysisCatheterSite = "right IJ tunneled"
        r.hx.dialysisSchedule = nil; r.hx.dialysisScheduleOther = "nightly"
        XCTAssertEqual(HistorySections.renalItems(r).last, "ESRD on hemodialysis nightly (L forearm fistula, right IJ tunneled dialysis catheter)")
        HistorySections.setDialysisAccess(["catheter"], &r)
        XCTAssertEqual(r.hx.fistulaSite, "", "an access taken off takes its site")
        HistorySections.clear(hd, system: "renal", &r)
        XCTAssertFalse(r.has("esrd-dialysis"))
        XCTAssertTrue(r.hx.dialysisAccess.isEmpty); XCTAssertEqual(r.hx.dialysisScheduleOther, "")
        HistorySections.setOption("esrd-no-dialysis", true, in: ckd, &r)
        XCTAssertEqual(r.problems, ["ckd", "esrd-no-dialysis"], "chosen by hand beside CKD")
        XCTAssertEqual(HistorySections.renalItems(r), ["CKD stage 3b", "ESRD not on scheduled dialysis"])
        HistorySections.clear(ckd, system: "renal", &r)
        XCTAssertTrue(r.problems.isEmpty); XCTAssertNil(r.hx.ckdStage)
        XCTAssertEqual(HistorySections.renalItems(adult(["aki", "bph", "prostate-cancer"])), ["AKI", "BPH", "prostate cancer"])
    }

    // MARK: GI & liver

    func testGI() throws {
        var r = adult(["gi-bleed"])
        r.hx.giBleedSite = "upper"; r.hx.giBleedStatus = "resolved"
        XCTAssertEqual(HistorySections.giItems(r), ["GI bleed, upper, resolved"])
        r.hx.giBleedDetails = "duodenal ulcer"
        XCTAssertEqual(HistorySections.giItems(r), ["GI bleed, upper, resolved (duodenal ulcer)"])
        let esophageal = try section("gi", "esophageal")
        HistorySections.setOption("dysphagia", true, in: esophageal, &r)
        HistorySections.setOption("esophageal-disorder", true, in: esophageal, &r)
        r.hx.esophagealDisorderType = "achalasia"
        r.hx.esophagealProcedure = true; r.hx.esophagealProcedureDetails = "dilation"
        XCTAssertEqual(HistorySections.giItems(r).first, "dysphagia, esophageal disorder (achalasia), previous esophageal procedure (dilation)")
        HistorySections.clear(esophageal, system: "gi", &r)
        XCTAssertEqual(r.problems, ["gi-bleed"]); XCTAssertNil(r.hx.esophagealProcedure)
        var p = PatientRecord(); p.hx.esophagealProcedure = false
        XCTAssertTrue(HistorySections.isSelected(esophageal, system: "gi", p), "an answer keeps the heading open")
        XCTAssertEqual(HistorySections.giItems(adult(["gerd", "gastric-bypass", "hiatal-hernia", "varices", "cirrhosis", "hepatitis-active",
                                                     "gastroparesis", "full-stomach"])),
                       ["GERD", "prior gastric bypass", "hiatal hernia", "esophageal varices", "cirrhosis", "active hepatitis", "gastroparesis",
                        "full stomach or bowel obstruction"])
        XCTAssertEqual(PatientCatalog.problem("gerd")?.label, "Reflux/GERD")
    }

    // MARK: Endocrine

    func testEndocrine() throws {
        var r = PatientRecord()
        HistorySections.setDiabetesInsulin("insulin", &r)
        XCTAssertEqual(r.problems, ["dm", "insulin"], "insulin sits beside dm, never in its place")
        XCTAssertEqual(HistorySections.endoItems(r), ["diabetes on insulin"])
        XCTAssertEqual(HistorySections.diabetesInsulin(r), "insulin")
        HistorySections.setDiabetesInsulin("none", &r)
        XCTAssertEqual(r.problems, ["dm"]); XCTAssertTrue(r.hx.dmNoInsulin)
        XCTAssertEqual(HistorySections.endoItems(r), ["diabetes, not on insulin"])
        HistorySections.setDiabetesInsulin(nil, &r)
        XCTAssertEqual(HistorySections.endoItems(r), ["diabetes"])
        r.problems.insert("thyroid"); r.hx.thyroidType = "hypo"
        r.problems.insert("adrenal"); r.hx.adrenalKinds = ["steroids"]
        r.hx.steroidDrug = "Prednisolone"; r.hx.steroidDailyMg = 10; r.hx.steroidDuration = "ge1m"
        XCTAssertEqual(HistorySections.endoItems(r), ["diabetes", "hypothyroidism", "chronic steroids (prednisolone 10 mg/day, 1 month or more)"])
        r.hx.adrenalKinds = ["insufficiency", "steroids"]; r.hx.steroidDrug = "Fludrocortisone"; r.hx.steroidDailyMg = nil; r.hx.steroidDuration = nil
        XCTAssertEqual(HistorySections.endoItems(r).last, "adrenal insufficiency and chronic steroids (Fludrocortisone)")
        let adrenal = try section("endo", "adrenal")
        HistorySections.clear(adrenal, system: "endo", &r)
        XCTAssertTrue(r.hx.adrenalKinds.isEmpty); XCTAssertEqual(r.hx.steroidDrug, "")
        XCTAssertEqual(line("Endocrine", r), "diabetes; hypothyroidism")
    }

    // MARK: Hematologic

    func testHematologic() throws {
        let bleeding = try section("heme", "bleeding")
        var r = PatientRecord()
        HistorySections.select(bleeding, &r)
        XCTAssertEqual(HistorySections.hemeItems(r), ["bleeding disorder or coagulopathy"])
        HistorySections.setOption("vwd", true, in: bleeding, &r)
        r.hx.bleedingOther = "factor VII deficiency"
        XCTAssertEqual(HistorySections.hemeItems(r), ["bleeding disorder: von Willebrand disease, factor VII deficiency"])
        XCTAssertEqual(HistorySections.bleedingKinds.map(\.id), ["vwd", "hemophilia-a", "hemophilia-b", "dic"], "factor V Leiden is a thrombophilia")
        HistorySections.clear(bleeding, system: "heme", &r)
        XCTAssertTrue(r.problems.isEmpty); XCTAssertEqual(r.hx.bleedingOther, "")

        HistorySections.setAnticoagulant("heparin", true, &r)
        r.hx.anticoagulants["heparin"]?.intensity = "therapeutic"
        r.hx.anticoagulants["heparin"]?.lastDose = "08:00"
        HistorySections.setAnticoagulant("other", true, &r)
        r.hx.anticoagulants["other"]?.name = "apixaban 5 mg BID"
        XCTAssertTrue(r.has("anticoagulation"))
        XCTAssertEqual(HistorySections.hemeItems(r), ["on anticoagulation: heparin, therapeutic, last dose 08:00; apixaban 5 mg BID"])
        HistorySections.setAnticoagulant("heparin", false, &r)
        XCTAssertNil(r.hx.anticoagulants["heparin"])
        r.problems.formUnion(["vte", "thrombophilia-heme", "fvl"])
        r.hx.vteTiming = "acute"; r.hx.vteDate = "10/2026"
        XCTAssertEqual(HistorySections.hemeItems(r), ["thrombophilia (factor V Leiden)", "on anticoagulation: apixaban 5 mg BID", "DVT/PE, acute, 10/2026"])
        let thrombophilia = try section("heme", "thrombophilia")
        HistorySections.clear(thrombophilia, system: "heme", &r)
        XCTAssertFalse(r.has("fvl")); XCTAssertFalse(r.has("thrombophilia-heme"))
        XCTAssertEqual(HistorySections.hemeItems(adult(["declines-blood"])), ["declines blood products"])
    }

    // MARK: Infectious

    func testInfectious() throws {
        var r = adult(["hepatitis-viral", "covid-recent", "tb", "isolation", "hiv", "sepsis", "uri"])
        r.hx.hepatitisTypes = ["c", "b"]
        r.hx.covidStatus = "active"; r.hx.covidTestDate = "11/01"
        r.hx.tbStatus = "latent"
        r.hx.precautions = ["droplet", "contact"]
        r.hx.hivViralLoad = "undetectable"
        XCTAssertEqual(HistorySections.infectiousItems(r), ["HIV (viral load undetectable)", "hepatitis B and C", "COVID-19, active, positive 11/01",
                                                            "tuberculosis, latent", "isolation precautions: contact, droplet"],
                       "sepsis and URI are said under Acute illness and Respiratory")
        let isolation = try section("infectious", "isolation")
        HistorySections.clear(isolation, system: "infectious", &r)
        XCTAssertTrue(r.hx.precautions.isEmpty)
        XCTAssertEqual(PatientPrecautions.kinds.map(\.id), ["contact", "droplet", "airborne"])
        XCTAssertNil(asa(adult(["hepatitis-viral", "covid-recent", "tb", "isolation", "hiv"])))
    }

    // MARK: Acute illness

    func testAcuteIllness() throws {
        XCTAssertEqual(HistorySections.shockWords([]), "shock")
        XCTAssertEqual(HistorySections.shockWords(["cardiogenic"]), "cardiogenic shock")
        XCTAssertEqual(HistorySections.shockWords(["distributive", "cardiogenic"]), "mixed shock: cardiogenic, distributive")
        var r = PatientRecord()
        HistorySections.setSepsisShock(true, &r)
        XCTAssertEqual(r.problems, ["sepsis", "shock"], "sepsis with shock adds the Shock item")
        r.hx.shockTypes = ["cardiogenic", "distributive"]
        r.hx.sepsisSource = "pneumonia"; r.hx.sepsisAntibiotic = "cefepime"
        XCTAssertEqual(HistorySections.acuteItems(r), ["sepsis, source pneumonia, on cefepime", "mixed shock: cardiogenic, distributive"])
        HistorySections.setSepsisShock(false, &r)
        XCTAssertEqual(r.problems, ["sepsis"]); XCTAssertTrue(r.hx.shockTypes.isEmpty)
        r.problems.formUnion(["massive-trauma", "burn", "ruptured-aneurysm"])
        r.hx.traumaDetails = "MVC"
        XCTAssertEqual(HistorySections.acuteItems(r).suffix(2), ["massive trauma and major burn (MVC)", "ruptured abdominal or thoracic aneurysm"])
        // A ruptured aneurysm recorded by site on Cardiovascular is shown on Acute illness, not filed again.
        var cv = PatientRecord()
        cv.hx.aneurysms = ["abdominal": PatientAneurysm(cm: 7, ruptured: true)]
        PatientHistoryDetails.sync(&cv)
        XCTAssertEqual(HistorySections.fromCardiovascular(cv), ["ruptured abdominal aneurysm"])
        XCTAssertFalse(cv.has("ruptured-aneurysm"))
        cv.ageYears = 70
        XCTAssertEqual(asa(cv), 5, "the Cardiovascular ruptured aneurysm keeps its class V")
    }

    // MARK: Obstetric

    func testObstetricPregnancyWords() {
        var r = adult(["pregnant"])
        XCTAssertEqual(HistorySections.obItems(r), ["pregnant"])
        r.hx.gravida = 2; r.hx.para = 1; r.hx.abortus = 0; r.hx.living = 1
        r.hx.gestationWeeks = 32; r.hx.gestationDays = 4
        r.hx.priorCesarean = true; r.hx.cesareanLastBirth = true
        XCTAssertEqual(HistorySections.obItems(r), ["G2P1A0L1, 32+4 weeks, prior cesarean (last birth)"])
        r.hx.gravida = nil; r.hx.para = nil; r.hx.abortus = nil; r.hx.living = nil; r.hx.gestationDays = nil
        r.hx.priorCesarean = false
        XCTAssertEqual(HistorySections.obItems(r), ["pregnant, 32 weeks, no prior cesarean"])
    }

    func testPreeclampsia() throws {
        var r = adult([])
        HistorySections.setPreeclampsiaSeverity("without", &r)
        XCTAssertEqual(r.problems, ["preeclampsia"])
        XCTAssertEqual(asa(r), 2)
        HistorySections.setPreeclampsiaSeverity("with", &r)
        XCTAssertEqual(r.problems, ["preeclampsia-severe"])
        XCTAssertEqual(asa(r), 3)
        HistorySections.setPreeclampsiaFeatures(["aki", "hellp", "thrombocytopenia"], &r)
        XCTAssertEqual(r.problems, ["preeclampsia-severe", "hellp"])
        XCTAssertEqual(asa(r), 4, "HELLP is the ASA's class IV example")
        XCTAssertEqual(HistorySections.obItems(r), ["preeclampsia with severe features: AKI, thrombocytopenia, HELLP syndrome"])
        HistorySections.setPreeclampsiaFeatures(["aki"], &r)
        XCTAssertFalse(r.has("hellp"))
        HistorySections.setPreeclampsiaSeverity("without", &r)
        XCTAssertEqual(r.problems, ["preeclampsia"]); XCTAssertTrue(r.hx.preeclampsiaFeatures.isEmpty)
        XCTAssertEqual(HistorySections.preeclampsiaSeverity(r), "without")
        let s = try section("ob", "preeclampsia")
        HistorySections.setPreeclampsiaFeatures(["hellp"], &r)
        HistorySections.clear(s, system: "ob", &r)
        XCTAssertTrue(r.problems.isEmpty); XCTAssertTrue(r.hx.preeclampsiaFeatures.isEmpty)
        XCTAssertNil(HistorySections.preeclampsiaSeverity(r))
    }

    func testGestationalDiabetesAndPlacenta() {
        var r = adult(["gdm"])
        r.hx.gdmControl = "uncontrolled"; r.hx.gdmInsulin = true
        XCTAssertEqual(HistorySections.obItems(r), ["gestational diabetes, uncontrolled, on insulin"])
        XCTAssertNil(asa(r), "gestational diabetes alone is in no ASA example")
        r.problems.insert("gdm-complex")
        XCTAssertEqual(asa(r), 3)
        XCTAssertEqual(HistorySections.obItems(adult(["gdm-diet"])), ["gestational diabetes, diet-controlled"], "as saved before 1.9")
        var p = adult(["previa-accreta"])
        XCTAssertEqual(HistorySections.obItems(p), ["placenta previa or accreta"])
        p.hx.placenta = ["accreta", "previa"]
        XCTAssertEqual(HistorySections.obItems(p), ["placenta previa and accreta"])
    }

    func testPeripartumCardiomyopathyAndUterineRupture() {
        var r = adult([])
        HistorySections.setPPCMEF(nil, &r)
        XCTAssertEqual(r.problems, ["ppcm"])
        XCTAssertNil(asa(r), "peripartum cardiomyopathy alone (LVEF < 45%) suggests no class")
        HistorySections.setPPCMEF(35, &r)
        XCTAssertEqual(r.problems, ["peripartum-cm"])
        XCTAssertEqual(asa(r), 4, "LVEF 35%: the ASA's class IV example")
        XCTAssertEqual(HistorySections.obItems(r), ["peripartum cardiomyopathy, LVEF 35%"])
        HistorySections.setPPCMEF(40, &r)
        XCTAssertEqual(r.problems, ["ppcm"], "40% is not below 40")
        XCTAssertNil(asa(r))
        XCTAssertEqual(HistorySections.obItems(adult(["peripartum-cm"])), ["peripartum cardiomyopathy, EF below 40%"])

        XCTAssertNil(asa(adult(["uterine-rupture-past"])), "a past rupture is in no example")
        XCTAssertEqual(asa(adult(["uterine-rupture"])), 5)
        XCTAssertEqual(HistorySections.obItems(adult(["uterine-rupture-past"])), ["past uterine rupture"])
    }

    func testObstetricThrombophilia() throws {
        var r = adult([])
        HistorySections.setObThrombophiliaAnticoag(false, &r)
        XCTAssertEqual(r.problems, ["thrombophilia-heme"])
        XCTAssertEqual(HistorySections.obThrombophiliaAnticoag(r), false)
        XCTAssertNil(asa(r), "a thrombophilia not anticoagulated is in no example")
        HistorySections.setObThrombophiliaAnticoag(true, &r)
        XCTAssertEqual(r.problems, ["thrombophilia-heme", "thrombophilia"])
        XCTAssertEqual(asa(r), 3, "anticoagulated in pregnancy: the ASA's obstetric class III example")
        XCTAssertEqual(line("Obstetric", r), "on anticoagulation for thrombophilia")
        XCTAssertEqual(line("Hematologic", r), "thrombophilia")
        let ob = try section("ob", "thrombophilia")
        XCTAssertTrue(HistorySections.isSelected(ob, system: "ob", r))
        XCTAssertTrue(HistorySections.isSelected(try section("heme", "thrombophilia"), system: "heme", r), "one disease, either page")
        HistorySections.clear(ob, system: "ob", &r)
        XCTAssertTrue(r.problems.isEmpty)
    }

    func testFromObstetric() {
        var r = adult(["pregnant", "gest-htn", "preeclampsia-severe", "hellp", "ppcm", "gdm"])
        r.hx.preeclampsiaFeatures = ["neuro", "aki", "thrombocytopenia", "pulm-edema", "hellp"]
        r.hx.ppcmEF = 42; r.hx.gdmInsulin = true
        XCTAssertEqual(HistorySections.fromObstetric("cv", r), ["gestational hypertension", "preeclampsia with severe features", "peripartum cardiomyopathy, LVEF 42%"])
        XCTAssertEqual(HistorySections.fromObstetric("heme", r), ["thrombocytopenia (preeclampsia)", "HELLP syndrome"])
        XCTAssertEqual(HistorySections.fromObstetric("resp", r), ["pulmonary edema (preeclampsia)"])
        XCTAssertEqual(HistorySections.fromObstetric("neuro", r), ["headache or visual changes (preeclampsia)"])
        XCTAssertEqual(HistorySections.fromObstetric("renal", r), ["AKI (preeclampsia)"])
        XCTAssertEqual(HistorySections.fromObstetric("endo", r), ["gestational diabetes, on insulin"])
        XCTAssertEqual(HistorySections.fromObstetric("gi", r), [])
        // Display only: nothing is filed on those pages, so AKI's ASA IV is not suggested.
        XCTAssertFalse(r.has("aki")); XCTAssertFalse(r.has("thrombocytopenia"))
        XCTAssertNil(line("Renal", r)); XCTAssertNil(line("Cardiovascular", r))
        XCTAssertEqual(asa(r), 4, "HELLP, not AKI")
        XCTAssertEqual(PatientRules.asaSuggestion(r)?.topFindings.count, 1)
        XCTAssertEqual(HistorySections.fromObstetric("cv", adult(["preeclampsia"])), ["preeclampsia without severe features"])
    }

    // MARK: Musculoskeletal

    func testMusculoskeletal() throws {
        var r = adult(["ra", "oa", "fracture", "marfan", "compartment-syndrome"])
        r.hx.arthritisLocation = "hands"
        r.hx.fractureLocation = "left femur"
        r.hx.ctdCardiovascular = true
        r.hx.compartmentLocation = "right forearm"
        XCTAssertEqual(HistorySections.mskItems(r), ["rheumatoid arthritis and osteoarthritis (hands)", "fracture (left femur)",
                                                     "Marfan syndrome, valve disease or aortopathy", "compartment syndrome (right forearm)"])
        r.hx.arthritisLocation = "Unspecified"
        XCTAssertTrue(HistorySections.arthritisUnspecified(r.hx))
        XCTAssertEqual(HistorySections.mskItems(r).first, "rheumatoid arthritis and osteoarthritis")
        r.hx.ctdCardiovascular = false
        XCTAssertEqual(HistorySections.mskItems(r)[2], "Marfan syndrome, no valve disease or aortopathy")
        // Yes shows the Cardiovascular page's valve and aorta words.
        var cv = adult(["marfan"])
        cv.hx.aneurysms = ["root": PatientAneurysm(cm: 4.6)]
        cv.hx.editValve("aortic") { $0.regurgitation = true; $0.regurgitationGrade = "moderate" }
        PatientHistoryDetails.sync(&cv)
        XCTAssertEqual(HistorySections.cvValveAortaWords(cv), ["aortic regurgitation moderate", "aortopathy: ascending aneurysm 4.6 cm"])
        let ctd = try section("msk", "ctd")
        HistorySections.clear(ctd, system: "msk", &r)
        XCTAssertNil(r.hx.ctdCardiovascular); XCTAssertFalse(r.has("marfan"))
        XCTAssertNil(asa(adult(["ra", "oa", "fracture", "marfan", "eds", "compartment-syndrome", "scoliosis"])))
        XCTAssertNil(asa(adult(["muscular-dystrophy"])), "the ASA's muscular dystrophy example is pediatric")
        XCTAssertEqual(asa(child(["muscular-dystrophy"])), 3)
    }

    // MARK: Smoking & substances

    func testSmokingAlcoholAndDrugs() throws {
        var r = PatientRecord()
        HistorySections.setSmoking("former", &r)
        r.hx.smokingQuitYear = 2015; r.hx.packYears = 20
        XCTAssertEqual(HistorySections.socialItems(r), ["former smoker, quit 2015, 20 pack-years"])
        HistorySections.setSmoking("current", &r)
        XCTAssertNil(r.hx.smokingQuitYear, "a current smoker has no quit year")
        XCTAssertEqual(HistorySections.socialItems(r), ["current smoker, 20 pack-years"])
        HistorySections.setSmoking("never", &r)
        XCTAssertNil(r.hx.packYears)
        XCTAssertEqual(HistorySections.socialItems(r), ["never smoked"])

        for (answer, id, words) in [("social", "alcohol-social", "social alcohol use"), ("former", "alcohol-abuse-former", "former alcohol dependence or abuse"),
                                    ("current", "alcohol-abuse", "current alcohol dependence or abuse")] {
            HistorySections.setAlcohol(answer, &r)
            XCTAssertEqual(r.problems, [id], answer)
            XCTAssertEqual(HistorySections.alcohol(r), answer)
            XCTAssertEqual(HistorySections.socialItems(r).last, words)
        }
        HistorySections.setAlcohol("none", &r)
        XCTAssertTrue(r.problems.isEmpty); XCTAssertTrue(r.hx.alcoholNone)
        XCTAssertEqual(HistorySections.socialItems(r), ["never smoked", "no alcohol use"])
        HistorySections.setAlcohol(nil, &r)
        XCTAssertFalse(r.hx.alcoholNone)

        let drugs = try section("social", "drugs")
        HistorySections.select(drugs, &r)
        HistorySections.setOption("cocaine", true, in: drugs, &r)
        HistorySections.setOption("marijuana", true, in: drugs, &r)
        r.hx.drugsOther = "benzodiazepines"
        XCTAssertEqual(HistorySections.socialItems(r).last, "illicit drug use: cocaine, marijuana, benzodiazepines")
        HistorySections.clear(drugs, system: "social", &r)
        XCTAssertTrue(r.problems.isEmpty); XCTAssertEqual(r.hx.drugsOther, "")
        let smoking = try section("social", "smoking")
        HistorySections.clear(smoking, system: "social", &r)
        XCTAssertNil(r.smoking)
        XCTAssertNil(line("Smoking & Substances", r))

        var s = adult(["alcohol-social"]); s.smoking = "current"
        XCTAssertEqual(line("Smoking & Substances", s), "current smoker; social alcohol use", "smoking said once, first")
        XCTAssertEqual(asa(adult(["alcohol-social"])), 2)
        XCTAssertEqual(asa(adult(["alcohol-abuse"])), 3)
        XCTAssertNil(asa(adult(["alcohol-abuse-former"])), "a former dependence is set by hand")
    }

    // MARK: ASA

    /// The new ids change no ASA suggestion, except where the ASA's own example names them.
    func testNewIdsKeepTheAsa() {
        let none = ["pleural-effusion", "pneumothorax", "visual-impairment", "psych", "mdd", "anxiety", "bph", "prostate-cancer", "gastric-bypass",
                    "dysphagia", "esophageal-disorder", "hiatal-hernia", "gi-bleed", "thrombocytopenia", "vwd", "hemophilia-a", "hemophilia-b",
                    "thrombophilia-heme", "fvl", "anticoagulation", "burn", "gdm", "ppcm", "uterine-rupture-past", "oa", "fracture", "marfan", "eds",
                    "compartment-syndrome", "alcohol-abuse-former", "cocaine", "opioid-use", "marijuana", "methamphetamine", "muscular-dystrophy"]
        for id in none {
            XCTAssertNotNil(PatientCatalog.problem(id), id)
            XCTAssertNil(asa(adult([id])), id + " suggests no class")
            XCTAssertTrue(PatientRules.prefill("rcri", adult([id])).on.isEmpty, id + " ticks no RCRI item")
        }
        XCTAssertEqual(asa(adult(["dm", "insulin"])), 2, "diabetes on insulin keeps the class II example")
        XCTAssertEqual(asa(adult(["esrd-no-dialysis"])), 4)
        XCTAssertEqual(asa(adult(["esrd-dialysis"])), 3)
        XCTAssertEqual(asa(adult(["ckd"])), nil)
        XCTAssertEqual(asa(adult(["aki"])), 4, "kept from 1.8")
        // The details beside the ids change nothing either.
        var r = adult(["dm", "insulin"])
        r.hx.ckdStage = "5"; r.hx.afType = "permanent"; r.hx.pacerDependent = true; r.hx.thyroidType = "hyper"; r.hx.adrenalKinds = ["insufficiency"]
        r.hx.shockTypes = ["cardiogenic"]; r.hx.gravida = 3; r.hx.precautions = ["airborne"]; r.hx.ppcmEF = 20; r.hx.alcoholNone = true
        XCTAssertEqual(asa(r), 2)
    }

    // MARK: Saved records

    /// A record saved by 1.8.3, with the ids as they were then, opens with each item on its page.
    func testA183RecordOpensOnTheRightPages() throws {
        let json = #"""
        {"ageYears": 52, "problems": ["gerd", "aki", "esrd-dialysis", "hepatitis-viral", "covid-recent", "endocarditis", "substance",
         "alcohol-social", "uterine-rupture", "thrombophilia", "gdm-diet", "peripartum-cm", "spine-fusion", "bleeding", "dic"],
         "smoking": "former", "systemNotes": {"renal": "Nephrology follows", "social": "Quit 2015"},
         "hx": {"deviceDetails": "dependent", "respInfectionType": "influenza"}}
        """#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.problems.count, 15, "every saved id is kept")
        XCTAssertTrue(r.systemOther.isEmpty)
        XCTAssertNil(r.hx.ckdStage); XCTAssertNil(r.hx.afType); XCTAssertFalse(r.hx.pacerDependent)
        // The item on the id's home page.
        func page(_ id: String) -> String? {
            guard let home = PatientCatalog.system(of: id)?.id, let s = HistorySections.sections(home)?.first(where: { $0.members.contains(id) }) else { return nil }
            return home + "." + s.id
        }
        XCTAssertEqual(page("gerd"), "gi.gerd")
        XCTAssertEqual(page("aki"), "renal.aki")
        XCTAssertEqual(page("esrd-dialysis"), "renal.hemodialysis")
        XCTAssertEqual(page("hepatitis-viral"), "infectious.hepatitis")
        XCTAssertEqual(page("covid-recent"), "infectious.covid")
        XCTAssertEqual(page("endocarditis"), "infectious.endocarditis")
        XCTAssertEqual(page("substance"), "social.drugs")
        XCTAssertEqual(page("alcohol-social"), "social.alcohol")
        XCTAssertEqual(page("uterine-rupture"), "ob.uterine-rupture")
        XCTAssertEqual(page("thrombophilia"), "ob.thrombophilia")
        XCTAssertEqual(page("gdm-diet"), "ob.gdm")
        XCTAssertEqual(page("peripartum-cm"), "ob.ppcm")
        XCTAssertEqual(page("spine-fusion"), "msk.spine")
        XCTAssertEqual(page("dic"), "heme.bleeding")
        for (sys, id) in [("gi", "gerd"), ("renal", "aki"), ("renal", "hemodialysis"), ("infectious", "covid"), ("social", "smoking"), ("social", "alcohol"),
                          ("social", "drugs"), ("ob", "uterine-rupture"), ("ob", "thrombophilia"), ("ob", "gdm"), ("ob", "ppcm"), ("msk", "spine"),
                          ("heme", "bleeding"), ("cv", "endocarditis"), ("cv", "device")] {
            XCTAssertTrue(HistorySections.isSelected(try section(sys, id), system: sys, r), sys + "." + id + " opens chosen")
        }
        XCTAssertEqual(HistorySections.obThrombophiliaAnticoag(r), true, "the 1.8 item was the anticoagulated one")
        XCTAssertEqual(line("Renal", r), "AKI; ESRD on hemodialysis; Nephrology follows")
        XCTAssertEqual(line("Smoking & Substances", r), "former smoker; social alcohol use; illicit drug use; Quit 2015")
        XCTAssertEqual(line("Obstetric", r), "gestational diabetes, diet-controlled; peripartum cardiomyopathy, EF below 40%; uterine rupture, active; on anticoagulation for thrombophilia")
        XCTAssertEqual(line("Hematologic", r), "bleeding disorder: DIC")
        XCTAssertEqual(line("Infectious", r), "viral hepatitis; COVID-19; infective endocarditis")
        XCTAssertEqual(line("GI & liver", r), "GERD")
        XCTAssertEqual(line("Cardiovascular", r), "pacemaker or ICD (dependent)", "the typed device details are kept")
        XCTAssertEqual(asa(r), 5, "uterine rupture, as before")
    }
}
