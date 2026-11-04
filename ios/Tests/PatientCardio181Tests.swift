import XCTest
@testable import PeriopSignal

/// The Cardiovascular and Respiratory History pages as expanding sections (1.8.1): each option's ASA, RCRI and
/// STOP-BANG mapping, the migration of records saved before them, the details beside the problem ids, the summary and
/// handoff text, and what the note and quick-add readers file.
final class PatientCardio181Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8))! }

    private func read(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func ids(_ s: String) -> Set<String> { Set(read(s).findings.map(\.id)) }
    private func change(_ s: String, _ id: String) -> PatientNoteChange? { read(s).findings.first { $0.id == id }?.change }
    private func quick(_ line: String) -> QuickAddReading { QuickAdd.read(line, record: PatientRecord(), tab: .preop, now: now) }
    private func adult(_ problems: Set<String>) -> PatientRecord {
        var r = PatientRecord(); r.ageYears = 60; r.problems = problems
        return r
    }
    private func child(_ problems: Set<String>) -> PatientRecord {
        var r = PatientRecord(); r.ageYears = 8; r.problems = problems
        return r
    }
    private func decode(_ json: String) throws -> PatientRecord { try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8)) }
    private func applied(_ text: String, to start: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = start
        PatientNote.apply(read(text).findings.map(\.change), to: &r)
        return r
    }
    private func cvLine(_ r: PatientRecord) -> String? { PatientSummary.historyLines(r).first { $0.label == "Cardiovascular" }?.text }
    private func respLine(_ r: PatientRecord) -> String? { PatientSummary.historyLines(r).first { $0.label == "Respiratory" }?.text }

    // MARK: Mappings

    func testEachOptionKeepsItsMapping() throws {
        // id: (adult ASA, pediatric ASA, RCRI, STOP-BANG)
        let expected: [String: (Int?, Int?, String?, String?)] = [
            "htn": (2, nil, nil, "pressure"), "htn-180": (3, nil, nil, "pressure"), "hyperlipidemia": (nil, nil, nil, nil),
            "cad": (3, nil, "ihd", nil), "mi": (3, nil, "ihd", nil), "cad-recent": (4, nil, "ihd", nil), "pci": (3, nil, "ihd", nil),
            "pci-recent": (4, nil, "ihd", nil), "ischemia": (4, nil, "ihd", nil), "cabg": (3, nil, "ihd", nil),
            "hf": (nil, 4, "hf", nil), "hf-decomp": (nil, 5, "hf", nil), "ef-moderate": (3, nil, nil, nil), "ef-severe": (4, nil, nil, nil),
            "valve-severe": (4, nil, nil, nil), "af": (nil, nil, nil, nil), "arrhythmia": (nil, nil, nil, nil),
            "pacemaker": (3, nil, nil, nil), "icd": (nil, 4, nil, nil), "pulm-htn": (nil, nil, nil, nil), "pulm-htn-severe": (nil, nil, nil, nil),
            "pvd": (nil, nil, nil, nil), "chd": (nil, nil, nil, nil), "chd-elevated": (nil, nil, nil, nil),
            "aaa": (nil, nil, nil, nil), "aaa-ruptured": (5, nil, nil, nil), "taa": (nil, nil, nil, nil), "taa-ruptured": (5, nil, nil, nil),
            "taaa": (nil, nil, nil, nil), "taaa-ruptured": (5, nil, nil, nil), "dissection-a": (nil, nil, nil, nil), "dissection-b": (nil, nil, nil, nil),
            "aortic-repair-open": (nil, nil, nil, nil), "evar": (nil, nil, nil, nil), "tevar": (nil, nil, nil, nil),
            "asthma": (nil, 2, nil, nil), "asthma-uncontrolled": (nil, 3, nil, nil), "copd": (3, nil, nil, nil), "osa": (nil, 2, nil, nil),
            "cpap": (nil, nil, nil, nil), "uri": (nil, nil, nil, nil), "pneumonia": (nil, nil, nil, nil), "resp-infection-other": (nil, nil, nil, nil),
            "ild": (nil, nil, nil, nil), "home-o2": (nil, nil, nil, nil),
        ]
        for (id, e) in expected {
            let p = try XCTUnwrap(PatientCatalog.problem(id), id)
            XCTAssertEqual(p.asa, e.0, id)
            XCTAssertEqual(p.peds, e.1, id)
            XCTAssertEqual(p.rcri, e.2, id)
            XCTAssertEqual(p.stopBang, e.3, id)
        }
        XCTAssertEqual(PatientCatalog.problem("cad")?.asaExample, "history (>3 months) of MI, CVA, TIA, or CAD/stents", "CAD alone: the >3 months example")
        XCTAssertEqual(PatientCatalog.problem("asthma-uncontrolled")?.pedsExample, "asthma with exacerbation")
        XCTAssertEqual(PatientCatalog.problem("htn")?.asaExample, "well-controlled DM/HTN")
        XCTAssertEqual(PatientCatalog.problem("hyperlipidemia")?.label, "Hyperlipidemia")
        XCTAssertEqual(HistorySections.cv.first { $0.id == "hyperlipidemia" }?.title, "Hyperlipidemia")
        var lipids = adult(["hyperlipidemia"]); lipids.sex = .female
        XCTAssertEqual(PatientFunctional.riskFactors(lipids), ["hyperlipidemia"])
        let cv = try XCTUnwrap(PatientCatalog.systems.first { $0.id == "cv" })
        XCTAssertTrue(PatientCatalog.systemNote(cv).hasPrefix("Hypertension: ASA III if poorly controlled; change the class by hand."))
        for gone in ["htn-poor", "as", "mr", "prosthetic-valve", "fh-cad", "snoring", "tired", "observed-apnea", "lung-mild"] {
            XCTAssertNil(PatientCatalog.problem(gone), gone + " is no longer an item")
        }
        // Every id a section names is in the catalog.
        for s in HistorySections.cv + HistorySections.resp { for id in s.members { XCTAssertNotNil(PatientCatalog.problem(id), id) } }
    }

    func testRulesGiveTheSameResultsAsBefore() {
        // ASA from the problem ids, as before the redesign.
        for (ids, level) in [(["htn"], 2), (["htn-180"], 3), (["cad"], 3), (["cad-recent"], 4), (["pci"], 3), (["pci-recent"], 4), (["ischemia"], 4),
                             (["cabg"], 3), (["ef-moderate"], 3), (["ef-severe"], 4), (["valve-severe"], 4), (["pacemaker"], 3),
                             (["aaa-ruptured"], 5), (["taa-ruptured"], 5), (["taaa-ruptured"], 5), (["copd"], 3)] as [([String], Int)] {
            XCTAssertEqual(PatientRules.asaSuggestion(adult(Set(ids)))?.level, level, ids.joined())
        }
        XCTAssertEqual(PatientRules.asaSuggestion(child(["hf"]))?.level, 4)
        XCTAssertEqual(PatientRules.asaSuggestion(child(["hf-decomp"]))?.level, 5)
        XCTAssertEqual(PatientRules.asaSuggestion(child(["icd"]))?.level, 4)
        XCTAssertEqual(PatientRules.asaSuggestion(child(["asthma"]))?.level, 2)
        XCTAssertEqual(PatientRules.asaSuggestion(child(["asthma-uncontrolled"]))?.level, 3)
        // RCRI and STOP-BANG.
        XCTAssertEqual(PatientRules.prefill("rcri", adult(["mi"])).on, ["ihd"])
        XCTAssertEqual(PatientRules.prefill("rcri", adult(["hf-decomp", "cabg"])).on, ["ihd", "hf"])
        XCTAssertEqual(PatientRules.prefill("stopbang", adult(["htn-180"])).on.intersection(["pressure"]), ["pressure"])
        // ARISCAT: every respiratory infection counts.
        for id in ["uri", "pneumonia", "resp-infection-other", "covid-recent"] {
            XCTAssertTrue(PatientRules.prefill("ariscat", adult([id])).on.contains("infection"), id)
        }
        // AHA/ACC: valve disease from the valve details, as from "as" and "mr" before.
        var valve = adult([]); valve.hx.valves["aortic"] = PatientValve(stenosis: true)
        XCTAssertTrue(PatientFunctional.knownCVD(valve))
        XCTAssertTrue(PatientFunctional.conditionAdvice(valve).contains { $0.hasPrefix("Valve disease: echo before surgery") })
        XCTAssertTrue(PatientRules.prompts(valve).contains { $0.id == "valves" })
        // The echo reminder: ungraded or moderate lesions, not one documented as mild.
        let echoLine = { (r: PatientRecord) -> Bool in PatientFunctional.conditionAdvice(r).contains { $0.hasPrefix("Valve disease: echo before surgery") } }
        var mild = adult([]); mild.hx.valves = ["aortic": PatientValve(stenosis: true, stenosisGrade: "mild"), "mitral": PatientValve(regurgitation: true, regurgitationGrade: "mild")]
        XCTAssertFalse(echoLine(mild), "every lesion mild: no reminder")
        XCTAssertTrue(PatientFunctional.knownCVD(mild), "still known valve disease")
        var moderate = mild; moderate.hx.valves["mitral"]?.regurgitationGrade = "moderate"
        XCTAssertTrue(echoLine(moderate), "a moderate lesion")
        var ungraded = mild; ungraded.hx.valves["tricuspid"] = PatientValve(regurgitation: true)
        XCTAssertTrue(echoLine(ungraded), "an ungraded lesion")
        var prosthesisOnly = adult([]); prosthesisOnly.hx.valves = ["aortic": PatientValve(prosthetic: true)]
        XCTAssertFalse(echoLine(prosthesisOnly), "a prosthesis alone, as before")
        var severe = valve; severe.hx.valves["aortic"]?.stenosisGrade = "severe"; PatientHistoryDetails.sync(&severe)
        XCTAssertTrue(severe.has("valve-severe"))
        XCTAssertTrue(PatientFunctional.conditionAdvice(severe).contains { $0.hasPrefix("Severe valve disease:") })
        XCTAssertFalse(PatientFunctional.conditionAdvice(severe).contains { $0.hasPrefix("Valve disease: echo") })
        XCTAssertEqual(PatientFunctional.riskModifiers(severe).first, "severe valve disease")
        XCTAssertTrue(PatientFunctional.ascvdProblems.contains("mi"))
        XCTAssertTrue(PatientFunctional.knownCVD(adult(["mi"])))
    }

    // MARK: Migration

    func testLegacyRecordsMigrateWithoutLosingTheirASA() throws {
        let old = try decode(#"{"ageYears": 70, "problems": ["htn-poor", "as", "mr", "prosthetic-valve", "valve-severe", "fh-cad", "snoring", "tired", "observed-apnea", "lung-mild"]}"#)
        XCTAssertEqual(old.problems, ["htn", "valve-severe", "fh-cad", "snoring", "tired", "observed-apnea", "lung-mild"], "old values still load")
        XCTAssertEqual(old.hx.valve("aortic"), PatientValve(stenosis: true), "aortic stenosis, no severity")
        XCTAssertEqual(old.hx.valve("mitral"), PatientValve(regurgitation: true), "mitral regurgitation, no severity")
        XCTAssertTrue(old.hx.prosthesisUnplaced, "a prosthesis with no position")
        XCTAssertTrue(old.hx.severeUnplaced, "severe valve disease, valve not recorded")
        let asa = PatientRules.asaSuggestion(old)
        XCTAssertEqual(asa?.level, 4, "severe valve disease keeps its ASA IV")
        XCTAssertEqual(asa?.topFindings, ["Severe valve disease, valve not recorded"])
        let line = try XCTUnwrap(cvLine(old))
        XCTAssertEqual(line, "hypertension; aortic stenosis; mitral regurgitation; prosthetic valve, position not recorded; severe valve disease, valve not recorded")
        XCTAssertNil(respLine(old), "the removed respiratory items are not shown")
        XCTAssertFalse(line.contains("family"), "fh-cad is not shown")
        // Once a severe lesion is recorded, it names the ASA IV.
        var edited = old
        edited.hx.editValve("aortic") { $0.setGrade("stenosis", "severe") }
        edited.hx.severeUnplaced = false
        PatientHistoryDetails.sync(&edited)
        XCTAssertEqual(PatientRules.asaSuggestion(edited)?.topFindings, ["Aortic stenosis, severe"])
        // Taking the severe grade off takes the ASA IV with it.
        edited.hx.editValve("aortic") { $0.setGrade("stenosis", "moderate") }
        PatientHistoryDetails.sync(&edited)
        XCTAssertFalse(edited.has("valve-severe"))
    }

    func testLegacyAneurysmsMoveToTheirLocations() throws {
        let old = try decode(#"{"problems": ["aaa", "taa", "taaa-ruptured"], "aortaSizes": {"aaa": 5.2, "taa": 4.6}}"#)
        XCTAssertEqual(old.hx.aneurysms["abdominal"], PatientAneurysm(cm: 5.2))
        XCTAssertEqual(old.hx.aneurysms["thoracic"], PatientAneurysm(cm: 4.6), "a thoracic aneurysm: location not recorded")
        XCTAssertEqual(old.hx.aneurysms["thoracoabdominal"], PatientAneurysm(ruptured: true))
        XCTAssertEqual(old.problems, ["aaa", "taa", "taaa-ruptured"], "the ids, and so the ASA V, are kept")
        XCTAssertEqual(PatientRules.asaSuggestion(old)?.level, 5)
        XCTAssertTrue(old.aortaSizes.isEmpty)
        XCTAssertEqual(cvLine(old), "aortopathy: thoracoabdominal aneurysm, ruptured, abdominal aneurysm 5.2 cm, thoracic aneurysm 4.6 cm")
        // Saved again and read back: unchanged.
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(back, old)
    }

    func testDemoRoundTrips() throws {
        for r in [PatientDemo.cardio, PatientDemo.record, PatientDemo.cardiac] {
            XCTAssertEqual(try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r)), r)
        }
    }

    // MARK: The sections

    func testSectionsSelectReplaceAndClear() throws {
        let cad = try XCTUnwrap(HistorySections.cv.first { $0.id == "cad" })
        var r = PatientRecord()
        HistorySections.select(cad, &r)
        XCTAssertEqual(r.problems, ["cad"], "CAD alone: unspecified")
        XCTAssertEqual(PatientRules.asaSuggestion(r)?.level, 3)
        HistorySections.choose("cad-recent", among: ["cad-recent", "mi"], in: cad, &r)
        XCTAssertEqual(r.problems, ["cad-recent"])
        HistorySections.choose("mi", among: ["cad-recent", "mi"], in: cad, &r)
        XCTAssertEqual(r.problems, ["mi"])
        HistorySections.setOption("cabg", true, in: cad, &r)
        XCTAssertEqual(r.problems, ["mi", "cabg"])
        HistorySections.choose(nil, among: ["cad-recent", "mi"], in: cad, &r)
        HistorySections.setOption("cabg", false, in: cad, &r)
        XCTAssertEqual(r.problems, ["cad"], "the last option off: CAD stays chosen")
        XCTAssertTrue(HistorySections.isSelected(cad, system: "cv", r))
        HistorySections.clear(cad, system: "cv", &r)
        XCTAssertTrue(r.problems.isEmpty)

        let hf = try XCTUnwrap(HistorySections.cv.first { $0.id == "hf" })
        HistorySections.select(hf, &r)
        HistorySections.setOption("hf-decomp", true, in: hf, &r)
        HistorySections.choose("ef-severe", among: ["ef-severe", "ef-moderate"], in: hf, &r)
        XCTAssertEqual(r.problems, ["hf-decomp", "ef-severe"])
        XCTAssertEqual(PatientRules.prefill("rcri", r).on, ["hf"])

        let htn = try XCTUnwrap(HistorySections.cv.first { $0.id == "htn" })
        HistorySections.select(htn, &r)
        HistorySections.setOption("htn-180", true, in: htn, &r)
        XCTAssertFalse(r.has("htn"))
        XCTAssertTrue(r.has("htn-180"))
        HistorySections.setOption("htn-180", false, in: htn, &r)
        XCTAssertTrue(r.has("htn"))

        // Valve disease: a heading; clearing it takes the valves and the ASA IV.
        let valves = try XCTUnwrap(HistorySections.cv.first { $0.id == "valves" })
        XCTAssertFalse(HistorySections.isSelected(valves, system: "cv", r))
        r.hx.editValve("mitral") { $0.setGrade("regurgitation", "severe") }
        PatientHistoryDetails.sync(&r)
        XCTAssertTrue(HistorySections.isSelected(valves, system: "cv", r))
        XCTAssertTrue(r.has("valve-severe"))
        HistorySections.clear(valves, system: "cv", &r)
        XCTAssertFalse(r.has("valve-severe"))
        XCTAssertTrue(r.hx.valves.isEmpty)

        // Aortopathy: each location files its id; ruptured is ASA V.
        r.hx.aneurysms = ["root": PatientAneurysm(cm: 4.8), "abdominal": PatientAneurysm(cm: 6.1, ruptured: true)]
        PatientHistoryDetails.sync(&r)
        XCTAssertTrue(r.problems.isSuperset(of: ["taa", "aaa-ruptured"]))
        XCTAssertEqual(PatientRules.asaSuggestion(adult(r.problems))?.level, 5)
        r.hx.aneurysms["arch"] = PatientAneurysm(ruptured: true)
        PatientHistoryDetails.sync(&r)
        XCTAssertTrue(r.problems.isSuperset(of: ["taa", "taa-ruptured"]), "arch maps to the thoracic id")
        let aorta = try XCTUnwrap(HistorySections.cv.first { $0.id == "aorta" })
        HistorySections.clear(aorta, system: "cv", &r)
        XCTAssertTrue(r.problems.isDisjoint(with: PatientHistoryDetails.aneurysmProblems))

        // Asthma and sleep apnea.
        let asthma = try XCTUnwrap(HistorySections.resp.first { $0.id == "asthma" })
        HistorySections.select(asthma, &r)
        HistorySections.setOption("asthma-uncontrolled", true, in: asthma, &r)
        XCTAssertEqual(r.problems.intersection(["asthma", "asthma-uncontrolled"]), ["asthma-uncontrolled"])
    }

    func testPreviousCardiacSurgeryKeepsThePastSurgicalHistory() {
        var r = PatientRecord()
        PatientHistoryDetails.setCardiacSurgery("AVR 2015", &r)
        XCTAssertEqual(r.surgeries.map(\.name), ["AVR 2015"])
        XCTAssertTrue(r.surgeries[0].intrathoracic, "it shows under Previous intrathoracic surgery")
        XCTAssertEqual(r.allIntrathoracic.count, 1)
        PatientHistoryDetails.setCardiacSurgery("AVR 2015; CABG ×3 2010", &r)
        XCTAssertEqual(r.surgeries.map(\.name), ["AVR 2015; CABG ×3 2010"], "edited in place, not added again")
        // Edited in the past surgical history: shown here.
        r.surgeries[0].setProcedures([PlannedProcedure(name: "Redo AVR 2015")])
        XCTAssertEqual(PatientHistoryDetails.cardiacSurgeryText(r), "Redo AVR 2015")
        PatientHistoryDetails.setCardiacSurgery("", &r)
        XCTAssertTrue(r.surgeries.isEmpty)
        // An entry with the same words already there: used, not doubled.
        var s = PatientRecord()
        s.surgeries = [PatientSurgery(name: "CABG ×3")]
        PatientHistoryDetails.setCardiacSurgery("CABG ×3", &s)
        XCTAssertEqual(s.surgeries.count, 1)
        XCTAssertEqual(s.hx.cardiacSurgeryID, s.surgeries[0].id)
        XCTAssertTrue(s.surgeries[0].intrathoracic)
    }

    // MARK: Summary and handoff

    func testSummaryAndHandoffText() {
        let r = PatientDemo.cardio
        XCTAssertEqual(cvLine(r), "hypertension; hyperlipidemia; CAD: MI within 3 months, prior CABG; HF, decompensated, EF severely reduced; "
                       + "aortic stenosis severe; mitral prosthetic (mechanical 27 mm); AF; pacemaker (dependent); pulmonary hypertension, moderate; "
                       + "aortopathy: ascending aneurysm 4.8 cm, type B dissection, prior TEVAR (2021); previous cardiac surgery: CABG ×3 2019; Followed by cardiology")
        XCTAssertEqual(respLine(r), "COPD; OSA on CPAP/BiPAP (BiPAP 14/8); respiratory infection: pneumonia; home oxygen 2 L/min")
        let handoff = HandoffWriter.text(r)
        XCTAssertTrue(handoff.contains("CAD: MI within 3 months, prior CABG"))
        XCTAssertTrue(handoff.contains("CABG ×3 2019"), "the past surgical history has it too")
        XCTAssertEqual(PatientRules.asaSuggestion(r)?.level, 4)
        XCTAssertTrue(PatientRules.asaSuggestion(r)?.topFindings.contains("Aortic stenosis, severe") ?? false)

        var p = PatientRecord()
        p.problems = ["pulm-htn-severe", "chd-elevated", "icd", "pacemaker", "arrhythmia", "asthma", "osa"]
        p.hx.arrhythmiaType = "SVT"; p.hx.chdDetails = "Fontan"; p.hx.osaNoCPAP = true; p.hx.asthmaControlled = true
        XCTAssertEqual(cvLine(p), "other arrhythmia (SVT); pacemaker and ICD; pulmonary hypertension, severe; congenital heart disease, complex lesion (Fontan)")
        XCTAssertEqual(respLine(p), "asthma, controlled; OSA, not on CPAP")
    }

    // MARK: Note and quick-add readers

    func testParserFillsTheStructure() {
        XCTAssertEqual(ids("NSTEMI 2 weeks ago").filter { $0.hasPrefix("problem:") }, ["problem:cad-recent"])
        let mi = read("MI 2019").findings.first { $0.id == "problem:mi" }
        XCTAssertNotNil(mi)
        XCTAssertNil(mi?.note, "a time given: no caution")
        XCTAssertNotNil(read("h/o MI").findings.first { $0.id == "problem:mi" }?.note, "no time: over 3 months, with its caution")
        XCTAssertTrue(ids("DES to LAD last month").contains("problem:pci-recent"))
        let cabg = ids("s/p CABG")
        XCTAssertTrue(cabg.contains("problem:cabg"))
        XCTAssertEqual(change("s/p CABG", "cardiac-surgery"), .cardiacSurgery("CABG"))
        XCTAssertEqual(change("severe AS", "problem:as"), .valve("aortic", "stenosis", "severe"))
        XCTAssertEqual(change("moderate MR", "problem:mr"), .valve("mitral", "regurgitation", "moderate"))
        XCTAssertEqual(change("moderate to severe TR", "valve:tricuspid:regurgitation"), .valve("tricuspid", "regurgitation", "severe"))
        XCTAssertEqual(change("mechanical AVR", "problem:prosthetic-valve-aortic"), .prosthesis("aortic", "mechanical"))
        XCTAssertEqual(change("s/p mechanical MVR 27 mm", "problem:prosthetic-valve-mitral"), .prosthesis("mitral", "mechanical 27 mm"))
        let hf = ids("HFrEF, EF 25%")
        XCTAssertTrue(hf.isSuperset(of: ["problem:hf", "problem:ef-severe"]))
        XCTAssertTrue(ids("PPM").contains("problem:pacemaker"))
        // 1.9 (contract): pacer dependence is its own field (PatientHistoryDetails.pacerDependent), no longer the word
        // "dependent" in the device details.
        XCTAssertEqual(change("PPM dependent", "problem:pacemaker"), .detail("pacemaker", "pacerDependent", "true"))
        XCTAssertTrue(ids("AICD").contains("problem:icd"))
        XCTAssertEqual(change("moderate pulmonary hypertension", "problem:pulm-htn"), .pulmHtn("moderate"))
        XCTAssertTrue(ids("severe pulmonary hypertension").contains("problem:pulm-htn-severe"))
        XCTAssertEqual(change("4.8 cm ascending aneurysm", "problem:taa"), .aneurysm("root", 4.8, false))
        XCTAssertEqual(change("arch aneurysm", "problem:taa"), .aneurysm("arch", nil, false))
        XCTAssertEqual(change("SVT", "problem:arrhythmia"), .problemNote("arrhythmia", "SVT"))
        XCTAssertTrue(ids("poorly controlled HTN").contains("problem:htn"), "no control qualifier")
        XCTAssertEqual(change("redo sternotomy for AVR", "cardiac-surgery"), .cardiacSurgery("Sternotomy"))
        XCTAssertEqual(change("prior cardiac surgery", "cardiac-surgery"), .cardiacSurgery("Cardiac surgery"))
        XCTAssertEqual(change("s/p AVR 2015", "cardiac-surgery"), .cardiacSurgery("AVR 2015"))
        XCTAssertNil(change("s/p TAVR 2019", "cardiac-surgery"), "a transcatheter valve is not cardiac surgery")
        XCTAssertEqual(change("s/p TAVR 2019", "problem:prosthetic-valve-aortic"), .prosthesis("aortic", "TAVR"))
        XCTAssertEqual(change("s/p mechanical AVR 2015", "cardiac-surgery"), .cardiacSurgery("mechanical AVR 2015"), "once, with its year")
        XCTAssertEqual(change("s/p mechanical AVR 2015", "problem:prosthetic-valve-aortic"), .prosthesis("aortic", "mechanical"), "the year is the operation's")
        // Respiratory.
        XCTAssertEqual(ids("poorly controlled asthma").filter { $0.hasPrefix("problem:") }, ["problem:asthma-uncontrolled"])
        XCTAssertTrue(ids("recent pneumonia").contains("problem:pneumonia"))
        XCTAssertEqual(change("home O2 2 L NC", "problem:home-o2"), .homeO2(2))
        XCTAssertTrue(ids("loud snoring, daytime sleepiness").filter { $0.hasPrefix("problem:") }.isEmpty, "the STOP-BANG tool asks these")
    }

    func testParserKeepsNegativesAndQuestions() {
        XCTAssertTrue(ids("trace MR, trivial TR").filter { $0.hasPrefix("problem:") || $0.hasPrefix("valve:") }.isEmpty, "trace and trivial are not disease")
        XCTAssertFalse(ids("No aortic stenosis").contains("problem:as"))
        XCTAssertFalse(ids("Denies MI").contains("problem:mi"))
        XCTAssertFalse(ids("Father had an MI at 50").contains("problem:mi"), "the father's MI")
        XCTAssertNil(change("72F with severe AS for TAVR under MAC.", "problem:prosthetic-valve-aortic"), "a planned TAVR")
        XCTAssertNil(change("Scheduled for mechanical AVR.", "problem:prosthetic-valve-aortic"), "a planned valve")
        XCTAssertNotNil(change("On warfarin for mechanical AVR.", "problem:prosthetic-valve-aortic"), "a valve in place")
        XCTAssertTrue(read("HTN, dissection").ambiguous.contains { $0.id == PatientNote.dissectionQuestion }, "the dissection is still asked")
        XCTAssertTrue(read("TAA, CKD").ambiguous.contains { $0.id == PatientNote.taaQuestion }, "a bare TAA is still asked")
        XCTAssertEqual(PatientNote.read("TAA 4.8 cm, s/p R ankle arthroplasty", now: now, choices: [PatientNote.taaQuestion: "taa"]).findings
            .first { $0.id == "problem:taa" }?.change, .aneurysm("thoracic", 4.8, false))
    }

    func testAppliedReadingsFillTheRecord() {
        let r = applied("NSTEMI 2 weeks ago, s/p CABG 2019, severe AS, s/p mechanical MVR 27 mm, AF, PPM dependent, moderate pulmonary hypertension, 4.8 cm ascending aneurysm")
        XCTAssertTrue(r.problems.isSuperset(of: ["cad-recent", "cabg", "valve-severe", "af", "pacemaker", "pulm-htn", "taa"]))
        XCTAssertEqual(r.hx.valve("aortic"), PatientValve(stenosis: true, stenosisGrade: "severe"))
        XCTAssertEqual(r.hx.valve("mitral"), PatientValve(prosthetic: true, prosthesis: "mechanical 27 mm"))
        // 1.9 (contract): the pacer dependence field, not the word in the device details.
        XCTAssertTrue(r.hx.pacerDependent)
        XCTAssertEqual(r.hx.deviceDetails, "")
        XCTAssertEqual(r.hx.pulmHtnSeverity, "moderate")
        XCTAssertEqual(r.hx.aneurysms["root"], PatientAneurysm(cm: 4.8))
        // 1.8.3 (Ben): each operation its own entry in Past surgical history, with its date (it was one entry, "CABG 2019; mechanical MVR").
        XCTAssertEqual(r.surgeries.count, 2, "each operation its own entry")
        XCTAssertEqual(r.surgeries[0].date, PatientMonthYear(year: 2019))
        XCTAssertTrue(r.surgeries.allSatisfy(\.intrathoracic))
        XCTAssertEqual(PatientHistoryDetails.cardiacSurgeryText(r), "Coronary artery bypass grafting", "the cardiac page shows the first")
        XCTAssertEqual(PatientRules.asaSuggestion(r)?.level, 4)
        // The same note again: nothing doubles.
        let again = applied("s/p CABG 2019, severe AS", to: r)
        XCTAssertEqual(again.surgeries.count, 2)
        XCTAssertEqual(again.hx.valves, r.hx.valves)
        // Statuses against the record.
        for f in read("severe AS, 4.8 cm ascending aneurysm, moderate pulmonary hypertension, s/p CABG 2019").findings where f.section == PatientNote.Part.history {
            XCTAssertEqual(PatientNote.status(f, in: r), .recorded, f.id)
        }
        let bigger = read("5.2 cm ascending aneurysm").findings.first { $0.id == "problem:taa" }!
        XCTAssertEqual(PatientNote.status(bigger, in: r), .replaces("4.8 cm"))
        let worse = read("severe pulmonary hypertension").findings.first { $0.id == "problem:pulm-htn-severe" }!
        XCTAssertEqual(PatientNote.status(worse, in: r), .replaces("Pulmonary hypertension"))
    }

    func testQuickAddLine() {
        let q = quick("68M, NSTEMI 2 weeks ago, s/p CABG, severe AS, s/p mechanical AVR 2015, AICD, moderate pulmonary hypertension, 4.8 cm ascending aneurysm")
        let found = Set(q.findings.map(\.id))
        for id in ["problem:cad-recent", "problem:cabg", "problem:as", "problem:prosthetic-valve-aortic", "problem:icd", "problem:pulm-htn", "problem:taa", "cardiac-surgery"] {
            XCTAssertTrue(found.contains(id), id + " in " + q.findings.map(\.label).joined(separator: " | "))
        }
        let chips = QuickAdd.chips(q, record: PatientRecord()).map(\.value)
        XCTAssertTrue(chips.contains("Aortic stenosis, severe"), chips.joined(separator: " | "))
        XCTAssertTrue(chips.contains("Thoracic aortic aneurysm (root/ascending), 4.8 cm"), chips.joined(separator: " | "))
        // On the Intraoperative tab, history is not filed.
        let intraop = QuickAdd.read("severe AS, s/p CABG", record: PatientRecord(), tab: .intraop, now: now)
        XCTAssertFalse(intraop.findings.contains { $0.id == "problem:as" || $0.id == "cardiac-surgery" })
    }

    func testNewPatternsCompile() {
        for rx in PatientNote.allPatterns { XCTAssertNotNil(rx.re, rx.pattern) }
    }
}
