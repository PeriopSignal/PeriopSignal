import XCTest
@testable import PeriopSignal

/// The note reader and the quick-add bar for the 1.9 History pages (Ben's Wanted Changes): a rule for every new item and
/// the details the pages hold beside them, read only where the note says them of the patient now: not negated, not a
/// relative's, not a risk or a suspicion, and past or current as each item is. All lines are synthetic.
final class PatientNote19Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 8))! }

    private func read(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func ids(_ s: String) -> Set<String> { Set(read(s).findings.map(\.id)) }
    private func problems(_ s: String) -> Set<String> { Set(read(s).findings.map(\.id).filter { $0.hasPrefix("problem:") }) }
    private func change(_ s: String, _ id: String) -> PatientNoteChange? { read(s).findings.first { $0.id == id }?.change }
    private func applied(_ s: String, to start: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = start
        PatientNote.apply(read(s).findings.map(\.change), to: &r)
        return r
    }
    private func quick(_ s: String) -> QuickAddReading { QuickAdd.read(s, record: PatientRecord(), tab: .preop, now: now) }
    private func quickApplied(_ s: String) -> PatientRecord {
        var r = PatientRecord()
        PatientNote.apply(quick(s).findings.map(\.change), to: &r)
        return r
    }

    /// Every new id of the contract is filed by some line, from the note and from the quick-add bar.
    func testEveryNewItemHasARule() {
        let lines: [(String, String)] = [
            ("left pleural effusion", "pleural-effusion"), ("R pneumothorax", "pneumothorax"), ("visual impairment", "visual-impairment"),
            ("bipolar disorder", "psych"), ("MDD", "mdd"), ("generalized anxiety disorder", "anxiety"),
            ("ESRD not on dialysis", "esrd-no-dialysis"), ("BPH", "bph"), ("prostate cancer", "prostate-cancer"),
            ("h/o gastric bypass", "gastric-bypass"), ("dysphagia", "dysphagia"), ("achalasia", "esophageal-disorder"),
            ("hiatal hernia", "hiatal-hernia"), ("GI bleed", "gi-bleed"), ("thrombocytopenia", "thrombocytopenia"),
            ("von Willebrand disease", "vwd"), ("hemophilia A", "hemophilia-a"), ("hemophilia B", "hemophilia-b"),
            ("antiphospholipid syndrome", "thrombophilia-heme"), ("factor V Leiden", "fvl"), ("on anticoagulation", "anticoagulation"),
            ("30% TBSA burns", "burn"), ("gestational diabetes", "gdm"), ("peripartum cardiomyopathy", "ppcm"),
            ("history of uterine rupture", "uterine-rupture-past"), ("osteoarthritis", "oa"), ("R hip fracture", "fracture"),
            ("Duchenne muscular dystrophy", "muscular-dystrophy"), ("Marfan syndrome", "marfan"), ("Ehlers-Danlos syndrome", "eds"),
            ("compartment syndrome", "compartment-syndrome"), ("former alcohol abuse", "alcohol-abuse-former"), ("cocaine use", "cocaine"),
            ("heroin use", "opioid-use"), ("marijuana use", "marijuana"), ("methamphetamine use", "methamphetamine"),
        ]
        for (line, id) in lines {
            XCTAssertNotNil(PatientCatalog.problem(id), id)
            XCTAssertTrue(problems(line).contains("problem:" + id), line + " → " + id + " (got " + problems(line).sorted().joined(separator: ", ") + ")")
            XCTAssertTrue(quickApplied("54F, HTN, " + line).has(id), "quick add: " + line)
        }
    }

    func testPatternsCompile() {
        for p in PatientNote.allPatterns { XCTAssertNotNil(p.re, p.pattern) }
        for p in MedAbbreviations.allPatterns { XCTAssertNotNil(p.re, p.pattern) }
        XCTAssertNotNil(ProcedureCatalog.diagnosisOnly.re)
    }

    /// Items shown on two pages are one id each (spec): one finding, never a second id for the same thing.
    func testSharedItemsAreOneIdEach() {
        let r = read("septic, URI, recent pneumonia, endocarditis, unstable C-spine, type B dissection, factor V Leiden")
        XCTAssertEqual(Set(r.findings.map(\.id).filter { $0.hasPrefix("problem:") }),
                       ["problem:sepsis", "problem:uri", "problem:pneumonia", "problem:endocarditis", "problem:cspine-unstable",
                        "problem:dissection-b", "problem:thrombophilia-heme", "problem:fvl"])
        XCTAssertEqual(r.findings.count, Set(r.findings.map(\.id)).count)
    }

    // MARK: Negation, family history, risk, past and current

    func testNegationFamilyAndRisk() {
        for line in ["no GI bleed", "denies cocaine", "denies illicit drug use", "no history of pneumothorax", "no fracture", "denies melena",
                     "not on anticoagulation", "no hiatal hernia", "denies depression or anxiety", "no BPH", "negative for FVL",
                     "mother with FVL", "father with hemophilia A", "brother had a pneumothorax", "FHx: prostate cancer, marfan",
                     "at risk for compartment syndrome", "concern for GI bleed", "possible PTX", "evaluate for fracture", "fracture risk",
                     "risk of uterine rupture discussed (TOLAC)", "compartment checks q1h", "r/o pneumothorax", "rule out compartment syndrome",
                     "cocaine negative", "UDS negative for cocaine", "4% topical cocaine pledgets", "not pacer dependent", "pacer dependent: no"] {
            let found = problems(line).subtracting(["problem:pacemaker"])
            XCTAssertTrue(found.isEmpty, line + " → " + found.sorted().joined(separator: ", "))
            XCTAssertFalse(applied(line).hx.pacerDependent, line)
        }
        XCTAssertFalse(ids("not pacer dependent").contains("problem:pacemaker"))
    }

    func testPastAndCurrent() {
        // Items there now: a past one is not read as current.
        for line in ["h/o pneumothorax 2015", "history of hip fracture", "s/p ORIF of R hip fracture", "PMH: HTN, hip fracture",
                     "h/o compartment syndrome", "h/o burns as a child", "h/o GDM in prior pregnancy", "h/o septic shock 2019"] {
            let found = problems(line)
            for id in ["pneumothorax", "fracture", "compartment-syndrome", "burn", "gdm", "shock", "sepsis"] {
                XCTAssertFalse(found.contains("problem:" + id), line + " → " + id)
            }
        }
        // The event behind a current injury is not its past.
        XCTAssertEqual(change("s/p fall with R hip fracture", "problem:fracture"), .problemNote("fracture", "R hip"))
        XCTAssertTrue(problems("s/p MVC with L pneumothorax").contains("problem:pneumothorax"))
        // Uterine rupture: active (ASA V) or past.
        XCTAssertEqual(problems("uterine rupture"), ["problem:uterine-rupture"])
        for line in ["history of uterine rupture", "prior uterine rupture", "uterine rupture in a prior pregnancy", "h/o uterine rupture 2019"] {
            XCTAssertEqual(problems(line), ["problem:uterine-rupture-past"], line)
        }
        XCTAssertNotEqual(PatientRules.asaSuggestion(applied("G3P2, h/o uterine rupture"))?.level, 5, "a past rupture is not the ASA V example")
        // GI bleed: resolved when past, active when said so.
        XCTAssertEqual(change("h/o upper GI bleed", "problem:gi-bleed"), .detail("gi-bleed", "giBleed", "resolved,upper"))
        XCTAssertEqual(change("active upper GI bleed", "problem:gi-bleed"), .detail("gi-bleed", "giBleed", "active,upper"))
        XCTAssertEqual(change("lower GI bleed, resolved", "problem:gi-bleed"), .detail("gi-bleed", "giBleed", "resolved,lower"))
        XCTAssertEqual(change("melena", "problem:gi-bleed"), .detail("gi-bleed", "giBleed", ",upper"))
        // Former dependence or drug use.
        XCTAssertEqual(problems("former alcohol abuse"), ["problem:alcohol-abuse-former"])
        XCTAssertEqual(problems("alcohol use disorder in remission"), ["problem:alcohol-abuse-former"])
        XCTAssertEqual(problems("alcohol abuse"), ["problem:alcohol-abuse"], "current, the ASA III example")
        XCTAssertTrue(problems("former IV cocaine use, clean 10 years").isEmpty)
        XCTAssertTrue(problems("cocaine use 2 days ago").contains("problem:cocaine"), "recent use is use")
    }

    // MARK: Meanings that changed (spec)

    func testChangedMeanings() {
        // GERD and a hiatal hernia are two items.
        XCTAssertEqual(problems("hiatal hernia"), ["problem:hiatal-hernia"])
        XCTAssertEqual(problems("GERD, hiatal hernia"), ["problem:gerd", "problem:hiatal-hernia"])
        XCTAssertTrue(problems("s/p hiatal hernia repair 2015").isEmpty, "the repair, not a hernia")
        // ESRD not on dialysis: CKD stage 5 and its own item, with the ASA IV.
        let esrd = applied("ESRD, not on dialysis")
        XCTAssertTrue(esrd.has("esrd-no-dialysis") && esrd.has("ckd"))
        XCTAssertFalse(esrd.has("aki"))
        XCTAssertEqual(esrd.hx.ckdStage, "5")
        XCTAssertEqual(PatientRules.asaSuggestion(esrd)?.level, 4)
        XCTAssertEqual(problems("AKI"), ["problem:aki"])
        XCTAssertEqual(problems("ESRD declines HD"), ["problem:esrd-no-dialysis", "problem:ckd"])
        XCTAssertEqual(problems("ESRD on HD MWF"), ["problem:esrd-dialysis"], "Hemodialysis replaces CKD")
        // Illicit drug use with the drugs beside it; methadone treatment is not illicit use.
        XCTAssertEqual(problems("cocaine use"), ["problem:cocaine", "problem:substance"])
        XCTAssertEqual(problems("IVDU (heroin)"), ["problem:opioid-use", "problem:substance"])
        XCTAssertTrue(problems("on methadone maintenance").isEmpty)
        XCTAssertTrue(ids("on methadone maintenance").contains("flag:opioid"), "the medicine flag still")
        // COVID-19 carries active or recent.
        XCTAssertEqual(change("recent COVID", "problem:covid-recent"), .detail("covid-recent", "covidStatus", "recent"))
        XCTAssertEqual(change("COVID-19 positive", "problem:covid-recent"), .detail("covid-recent", "covidStatus", "active"))
        XCTAssertEqual(applied("COVID-19 positive 10/28").hx.covidTestDate, "10/28")
        // Peripartum cardiomyopathy: EF below 40% is the ASA's class IV example, else "ppcm".
        XCTAssertEqual(problems("PPCM, EF 35%").intersection(["problem:ppcm", "problem:peripartum-cm"]), ["problem:peripartum-cm"])
        XCTAssertEqual(problems("PPCM, EF 42%").intersection(["problem:ppcm", "problem:peripartum-cm"]), ["problem:ppcm"])
        XCTAssertEqual(problems("peripartum cardiomyopathy"), ["problem:ppcm"])
        XCTAssertEqual(applied("PPCM, EF 35%").hx.ppcmEF, 35)
        XCTAssertEqual(PatientRules.asaSuggestion(applied("PPCM, EF 35%"))?.level, 4)
        // Gestational diabetes: "gdm" with its details; the ASA examples only as the ASA words them.
        let gdm = applied("GDM on insulin, poorly controlled")
        XCTAssertTrue(gdm.has("gdm"))
        XCTAssertFalse(gdm.has("gdm-complex") || gdm.has("insulin") || gdm.has("dm"), "not diabetes on insulin, nor the class III example")
        XCTAssertTrue(gdm.hx.gdmInsulin)
        XCTAssertEqual(gdm.hx.gdmControl, "uncontrolled")
        XCTAssertTrue(problems("diet-controlled GDM").isSuperset(of: ["problem:gdm", "problem:gdm-diet"]))
        XCTAssertTrue(problems("GDM with high insulin requirements").contains("problem:gdm-complex"))
        // Thrombophilia: Hematologic; the Obstetric ASA example only for a pregnant patient on anticoagulation.
        XCTAssertEqual(problems("FVL"), ["problem:fvl", "problem:thrombophilia-heme"])
        XCTAssertFalse(problems("factor V Leiden").contains("problem:thrombophilia"))
        XCTAssertTrue(problems("28 weeks pregnant with factor V Leiden on lovenox").contains("problem:thrombophilia"))
        XCTAssertEqual(change("protein S deficiency", "problem:thrombophilia-heme"), .problemNote("thrombophilia-heme", "protein S deficiency"))
        // ITP is thrombocytopenia; a muscular dystrophy is the Musculoskeletal item.
        XCTAssertEqual(problems("ITP"), ["problem:thrombocytopenia"])
        // 1.12 follow-up (Ben, Nov 12): HIT is its own Heme & Oncology item (before, it filed nothing); still never Thrombocytopenia.
        XCTAssertEqual(problems("heparin-induced thrombocytopenia"), ["problem:hit"], "HIT is its own item, not a low count")
        XCTAssertEqual(problems("Duchenne muscular dystrophy"), ["problem:muscular-dystrophy"])
        XCTAssertEqual(problems("myasthenia gravis"), ["problem:neuromuscular"])
    }

    // MARK: Details into their fields

    func testRenalDetails() {
        XCTAssertEqual(change("CKD 3b", "problem:ckd"), .detail("ckd", "ckdStage", "3b"))
        XCTAssertEqual(change("CKD stage IV", "problem:ckd"), .detail("ckd", "ckdStage", "4"))
        XCTAssertEqual(change("CKD G4", "problem:ckd"), .detail("ckd", "ckdStage", "4"))
        XCTAssertEqual(change("stage 2 CKD", "problem:ckd"), .detail("ckd", "ckdStage", "2"))
        XCTAssertEqual(change("CKD 3", "problem:ckd"), .problem("ckd"), "3 alone is not a KDIGO category")
        XCTAssertEqual(change("CKD 2/2 diabetes", "problem:ckd"), .problem("ckd"), "secondary to, not a stage")
        XCTAssertEqual(change("HD MWF", "problem:esrd-dialysis"), .detail("esrd-dialysis", "dialysisSchedule", "mwf"))
        XCTAssertEqual(applied("ESRD on HD TTS").hx.dialysisSchedule, "tts")
        let r = applied("ESRD on HD MWF via L arm AVF")
        XCTAssertTrue(r.has("esrd-dialysis"))
        XCTAssertEqual(r.hx.dialysisSchedule, "mwf")
        XCTAssertEqual(r.hx.dialysisAccess, ["fistula"])
        XCTAssertEqual(r.hx.fistulaSite, "L arm")
        let c = applied("ESRD on HD via R IJ tunneled HD catheter")
        XCTAssertEqual(c.hx.dialysisAccess, ["catheter"])
        XCTAssertEqual(c.hx.dialysisCatheterSite, "R IJ tunneled")
        XCTAssertEqual(applied("Left brachiocephalic AVF, on HD").hx.fistulaSite, "Left brachiocephalic")
        XCTAssertEqual(applied("AVF in the LUE, ESRD on HD").hx.fistulaSite, "LUE")
        // A fistula before dialysis is kept, without filing hemodialysis; one to come is not read.
        let pre = applied("CKD 4 with a maturing L forearm AVF")
        XCTAssertFalse(pre.has("esrd-dialysis"))
        XCTAssertEqual(pre.hx.fistulaSite, "L forearm")
        XCTAssertEqual(pre.hx.ckdStage, "4")
        XCTAssertTrue(applied("CKD 4, for AVF creation").hx.dialysisAccess.isEmpty)
        XCTAssertTrue(applied("anal fistula").hx.dialysisAccess.isEmpty)
        XCTAssertTrue(problems("BPH, prostate cancer").isSuperset(of: ["problem:bph", "problem:prostate-cancer"]))
    }

    func testCardiovascularDetails() {
        XCTAssertEqual(change("paroxysmal AF", "problem:af"), .detail("af", "afType", "paroxysmal"))
        XCTAssertEqual(change("PAF", "problem:af"), .detail("af", "afType", "paroxysmal"))
        XCTAssertEqual(change("permanent atrial fibrillation", "problem:af"), .detail("af", "afType", "permanent"))
        XCTAssertEqual(applied("long-standing persistent AF").hx.afType, "longstanding")
        for line in ["PPM, pacer dependent", "PPM-dependent", "pacemaker dependent", "dependent on his pacemaker"] {
            let r = applied(line)
            XCTAssertTrue(r.has("pacemaker"), line)
            XCTAssertTrue(r.hx.pacerDependent, line)
        }
        XCTAssertFalse(applied("PPM, not pacer dependent").hx.pacerDependent)
        XCTAssertTrue(applied("PPM, not pacer dependent").has("pacemaker"))
        XCTAssertFalse(applied("non-pacer-dependent PPM").hx.pacerDependent)
        XCTAssertFalse(applied("pacer dependent on epicardial wires").hx.pacerDependent, "temporary pacing is not the device's")
        let icd = applied("AICD, device dependent")
        XCTAssertTrue(icd.has("icd") && icd.hx.pacerDependent)
    }

    func testInfectiousAndAcuteDetails() {
        XCTAssertEqual(change("hep C", "problem:hepatitis-viral"), .detail("hepatitis-viral", "hepatitisTypes", "c"))
        XCTAssertEqual(applied("HBV and HCV").hx.hepatitisTypes, ["b", "c"])
        XCTAssertEqual(applied("hepatitis A").hx.hepatitisTypes, ["a"])
        XCTAssertTrue(problems("HAV IgG positive").isEmpty, "immunity")
        XCTAssertEqual(applied("LTBI").hx.tbStatus, "latent")
        XCTAssertEqual(applied("+PPD treated").hx.tbStatus, "latent")
        XCTAssertEqual(applied("active pulmonary TB").hx.tbStatus, "active")
        XCTAssertTrue(applied("ltbi").has("tb"), "lower case, through its meaning")
        XCTAssertEqual(applied("HIV, viral load undetectable").hx.hivViralLoad, "viral load undetectable")
        // Shock: the kinds; septic shock is distributive, with sepsis.
        XCTAssertEqual(change("septic shock", "problem:shock"), .detail("shock", "shockTypes", "distributive"))
        XCTAssertEqual(problems("septic shock"), ["problem:sepsis", "problem:shock"])
        XCTAssertEqual(change("cardiogenic shock", "problem:shock"), .detail("shock", "shockTypes", "cardiogenic"))
        XCTAssertEqual(applied("mixed septic and cardiogenic shock").hx.shockTypes, ["distributive", "cardiogenic"])
        XCTAssertEqual(applied("hemorrhagic shock").hx.shockTypes, ["hypovolemic"])
        XCTAssertEqual(applied("sepsis from pneumonia").hx.sepsisSource, "pneumonia")
        XCTAssertEqual(applied("urosepsis").hx.sepsisSource, "urinary")
        XCTAssertEqual(applied("40% TBSA burns").hx.traumaDetails, "40% TBSA burns")
        XCTAssertTrue(problems("small burn to the finger").isEmpty, "not a major burn")
        XCTAssertTrue(problems("heartburn").subtracting(["problem:gerd"]).isEmpty)
    }

    func testHematologicDetails() {
        let a = applied("on apixaban")
        XCTAssertTrue(a.has("anticoagulation"))
        XCTAssertEqual(a.hx.anticoagulants["other"]?.name, "apixaban")
        XCTAssertTrue(a.medFlags.contains("anticoagulant"))
        let w = applied("on warfarin, INR 2.3")
        XCTAssertNotNil(w.hx.anticoagulants["warfarin"])
        XCTAssertEqual(w.labs["inr"], 2.3)
        XCTAssertEqual(applied("heparin gtt").hx.anticoagulants["heparin"]?.intensity, "therapeutic")
        XCTAssertEqual(applied("heparin 5000 units SQ q8h").hx.anticoagulants["heparin"]?.intensity, "prophylaxis")
        XCTAssertEqual(applied("enoxaparin 40 daily").hx.anticoagulants["enoxaparin"]?.intensity, "prophylaxis")
        XCTAssertEqual(applied("enoxaparin 1 mg/kg BID").hx.anticoagulants["enoxaparin"]?.intensity, "therapeutic")
        XCTAssertEqual(applied("Eliquis 5 mg BID").hx.anticoagulants["other"]?.name, "apixaban")
        let doac = applied("on DOAC")
        XCTAssertTrue(doac.has("anticoagulation") && doac.medFlags.contains("anticoagulant"), "the flag as well as the item")
        XCTAssertTrue(applied("LMWH bridge").medFlags.contains("anticoagulant"))
        XCTAssertFalse(problems("dilated cardiomyopathy").contains("problem:neuromuscular"), "a cardiomyopathy is not a myopathy")
        for line in ["allergic to heparin", "HIT, avoid heparin", "stopped warfarin last year", "heparin flush", "mother on warfarin", "no anticoagulants"] {
            let r = applied(line)
            XCTAssertFalse(r.has("anticoagulation"), line)
            XCTAssertTrue(r.hx.anticoagulants.isEmpty, line)
        }
        XCTAssertEqual(problems("vWD"), ["problem:vwd", "problem:bleeding"])
        XCTAssertEqual(problems("hemophilia B"), ["problem:hemophilia-b", "problem:bleeding"])
        XCTAssertTrue(problems("von Willebrand factor 40%").subtracting(["problem:bleeding"]).isEmpty, "a level is not the disease")
    }

    func testOtherDetails() {
        // Smoking.
        let s = applied("former smoker, quit 2015, 40 pack-years")
        XCTAssertEqual(s.smoking, "former")
        XCTAssertEqual(s.hx.packYears, 40)
        XCTAssertEqual(s.hx.smokingQuitYear, 2015)
        XCTAssertNil(applied("quit 2015").hx.smokingQuitYear, "no smoking word: quit what?")
        // G/P and gestation (TPAL: P is term + preterm).
        let g = applied("G3P2012")
        XCTAssertEqual([g.hx.gravida, g.hx.para, g.hx.abortus, g.hx.living], [3, 2, 1, 2])
        XCTAssertFalse(g.has("pregnant"), "every pregnancy counted: not pregnant now")
        let p = applied("G2P1 at 32+4 weeks")
        XCTAssertTrue(p.has("pregnant"))
        XCTAssertEqual([p.hx.gravida, p.hx.para], [2, 1])
        XCTAssertEqual(p.hx.gestationWeeks, 32)
        XCTAssertEqual(p.hx.gestationDays, 4)
        XCTAssertEqual(applied("32w4d").hx.gestationDays, 4)
        XCTAssertEqual(applied("IUP at 28 weeks").hx.gestationWeeks, 28)
        XCTAssertEqual(applied("39 weeks gestation").hx.gestationWeeks, 39)
        XCTAssertFalse(applied("prostate cancer, Gleason 3+4").has("pregnant"), "a Gleason score is not a gestation")
        XCTAssertFalse(applied("45F G2P2 for hysterectomy").has("pregnant"))
        // Locations and types.
        XCTAssertEqual(applied("left distal radius fracture").hx.fractureLocation, "left distal radius")
        XCTAssertEqual(applied("fracture of the right femur").hx.fractureLocation, "right femur")
        XCTAssertEqual(applied("R knee OA").hx.arthritisLocation, "R knee")
        XCTAssertEqual(applied("LLE compartment syndrome").hx.compartmentLocation, "LLE")
        XCTAssertEqual(applied("achalasia s/p POEM").hx.esophagealDisorderType, "achalasia")
        XCTAssertEqual(applied("achalasia s/p POEM").hx.esophagealProcedure, true)
        XCTAssertNil(applied("achalasia, for POEM").hx.esophagealProcedure, "planned, not previous")
        XCTAssertEqual(applied("PTSD").hx.psychOther, "PTSD")
        XCTAssertTrue(applied("PTSD").has("psych"))
        XCTAssertEqual(problems("MDD, anxiety"), ["problem:mdd", "problem:anxiety", "problem:psych"])
        XCTAssertTrue(problems("respiratory depression after opioids").isEmpty)
        XCTAssertTrue(problems("ST depression in V4-V6").isEmpty)
        XCTAssertTrue(problems("preoperative anxiety").isEmpty)
        XCTAssertTrue(problems("bipolar cautery").isEmpty)
        XCTAssertEqual(applied("legally blind").hx.visualImpairment, "chronic")
        XCTAssertEqual(applied("acute vision loss").hx.visualImpairment, "acute")
        XCTAssertTrue(problems("double-blind trial").isEmpty)
        let pl = applied("left hemothorax, chest tube in place")
        XCTAssertEqual(pl.hx.pleuralSide, "left")
        XCTAssertEqual(pl.hx.pleuralFluid, "hemothorax")
        XCTAssertEqual(pl.hx.chestTube, true)
        XCTAssertEqual(pl.hx.chestTubeSides, ["left"])
        XCTAssertEqual(applied("R PTX").hx.pleuralSide, "right")
        XCTAssertFalse(applied("for laparoscopic gastric bypass").has("gastric-bypass"), "planned, not history")
    }

    /// The same note twice: the second reading finds everything recorded.
    func testDetailsAreRecordedOnceFiled() {
        let note = "62M, ESRD on HD MWF via L arm AVF, paroxysmal AF, PPM dependent, hep C, on apixaban, 40 pack-years. CKD 3b. G2P1 at 32+4 weeks"
        let r = applied(note)
        for f in read(note).findings where f.section == PatientNote.Part.history {
            XCTAssertEqual(PatientNote.status(f, in: r), .recorded, f.id + " · " + f.label)
        }
    }

    // MARK: The quick-add bar

    func testQuickAddVocabulary() {
        let lines: [(String, String)] = [("PPCM", "ppcm"), ("BPH", "bph"), ("LTBI", "tb"), ("vWD", "vwd"), ("FVL", "fvl"), ("EDS", "eds"),
                                         ("ESRD on HD MWF", "esrd-dialysis"), ("OA", "oa"), ("hiatal hernia, GERD", "hiatal-hernia")]
        for (line, id) in lines {
            XCTAssertTrue(quickApplied("60F, " + line).has(id), line)
        }
        let hd = quick("60F, ESRD on HD MWF, L arm AVF")
        XCTAssertFalse(hd.ambiguous.contains { $0.abbreviation == "HD" }, "dialysis words pick hemodialysis")
        XCTAssertEqual(quickApplied("60F, ESRD on HD MWF, L arm AVF").hx.fistulaSite, "L arm")
        // EDS beside sleep words is excessive daytime sleepiness, not Ehlers-Danlos.
        XCTAssertFalse(quickApplied("60F, OSA on CPAP, EDS").has("eds"))
        XCTAssertFalse(quickApplied("60F, on warfarin, INR 2.3").hx.anticoagulants.isEmpty)
        XCTAssertEqual(quickApplied("60F, on warfarin, INR 2.3").labs["inr"], 2.3)
        XCTAssertTrue(quickApplied("60F, G2P1 32w4d").has("pregnant"))
    }

    /// History details are preoperative: never filed from the Intraoperative tab.
    func testQuickAddIntraopFilesNoHistory() {
        let q = QuickAdd.read("septic shock, on heparin gtt", record: PatientRecord(), tab: .intraop, now: now)
        XCTAssertFalse(q.findings.contains { if case .detail = $0.change { return true } else { return false } })
    }

    // MARK: Known issue A: abbreviations in capitals are read in capitals (or all in lower case)

    func testCapitalsOnlyAbbreviations() {
        XCTAssertNil(MedAbbreviations.lookup("Tia"), "a name")
        XCTAssertNotNil(MedAbbreviations.lookup("TIA"))
        XCTAssertNotNil(MedAbbreviations.lookup("tia"), "typed quickly in lower case")
        XCTAssertNotNil(MedAbbreviations.lookup("htn"))
        XCTAssertNil(MedAbbreviations.lookup("Htn"))
        XCTAssertNil(MedAbbreviations.lookup("Dm2"))
        XCTAssertNotNil(MedAbbreviations.lookup("DM2"))
        XCTAssertNil(MedAbbreviations.lookup("Ross"), "not ROS")
        // Keys the list writes with a lower-case letter keep any case.
        for t in ["HFrEF", "hfref", "afib", "AFib", "EtOH", "etoh", "ETOH", "C-spine", "c-spine", "vWD", "VWD", "Hgb", "HGB"] {
            XCTAssertNotNil(MedAbbreviations.lookup(t), t)
        }
        XCTAssertFalse(MedAbbreviations.scan("Tia is a 34 yo F for lap chole").contains { $0.key == "TIA" })
        XCTAssertFalse(problems("Tia is a 34 yo F for lap chole").contains("problem:cva-unspec"), "Tia the name is not a TIA")
        XCTAssertFalse(quickApplied("Tia 34F for lap chole").has("cva-unspec"))
        XCTAssertEqual(problems("TIA 2019"), ["problem:cva"], "a TIA in capitals still files")
        XCTAssertEqual(problems("TIA"), ["problem:cva-unspec"])
        XCTAssertEqual(problems("h/o tia"), ["problem:cva-unspec"], "lower case, through its meaning")
        XCTAssertEqual(problems("htn, copd"), ["problem:htn", "problem:copd"])
        XCTAssertEqual(MedAbbreviations.read("HTN, s/p AVr").expanded, "hypertension, status post aortic valve repair")
    }

    // MARK: Known issue B: Return on a diagnosis adds no repair

    func testReturnOnADiagnosisAddsNoRepair() {
        for t in ["AAA", "aaa", "TAAA", "rAAA", "ruptured AAA", "thoracoabdominal aneurysm", "abdominal aortic aneurysm", "AAA 5.5 cm", "TAA", " AAA "] {
            XCTAssertTrue(ProcedureCatalog.isDiagnosisOnly(t), t)
            XCTAssertTrue(ProcedureCatalog.onReturn(t).isEmpty, t + " → " + ProcedureCatalog.onReturn(t).map(\.text).joined(separator: ", "))
        }
        XCTAssertFalse(ProcedureCatalog.search("AAA").isEmpty, "the list under the field still offers the repairs")
        XCTAssertEqual(ProcedureCatalog.onReturn("AAA repair").map(\.catalogID), ["open-aaa"])
        XCTAssertEqual(ProcedureCatalog.onReturn("EVAR").map(\.catalogID), ["evar"])
        XCTAssertEqual(ProcedureCatalog.onReturn("TAAA repair").map(\.catalogID), ["taaa"])
        XCTAssertEqual(ProcedureCatalog.onReturn("lap chole").map(\.catalogID), ["lap-chole"])
        XCTAssertEqual(ProcedureCatalog.onReturn("L TKA").first?.side, "left")
        XCTAssertNotNil(ProcedureCatalog.onReturn("Bentall").first?.ask, "a bare Bentall goes in as typed, to be asked")
        XCTAssertEqual(ProcedureCatalog.onReturn("xyzzq widget").map(\.name), ["Xyzzq widget"], "unknown text is added as typed")
        XCTAssertTrue(ProcedureCatalog.onReturn("  ").isEmpty)
        for t in ["AAA repair", "EVAR", "lap chole", "aneurysm repair"] { XCTAssertFalse(ProcedureCatalog.isDiagnosisOnly(t), t) }
    }
}
