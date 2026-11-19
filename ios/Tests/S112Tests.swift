import XCTest
@testable import PeriopSignal

/// 1.12 follow-up, helper S (Ben, Nov 16): "The Surgical prophylaxis reference is too text heavy and difficult to navigate. Convert this
/// to a calculator where the user can click options and choices are given based on input. Place explanations behind info link."
/// The data (reference.json "prophylaxis") against the guideline's table in the quick reference, the engine that turns the inputs into
/// the agents with their doses and redose, the prefill from a case, Start in Case Timers, and the wiring into the Reference tab.
final class S112Tests: XCTestCase {

    private var bundleFile: ReferenceBundle!
    private var d: ProphylaxisData { bundleFile.prophylaxis! }
    private var t: CaseTimerData { bundleFile.caseTimers! }

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        bundleFile = try ReferenceLoader.decode(try Data(contentsOf: url))
        XCTAssertNotNil(bundleFile.prophylaxis, "reference.json carries the prophylaxis section")
        XCTAssertNotNil(bundleFile.caseTimers)
    }

    override func tearDown() {
        ProphylaxisGate.available = true
    }

    private func adult(_ kg: Double? = 90) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = kg
        return r
    }

    private func child() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 8; r.sex = .female; r.heightCm = 128; r.weightKg = 28
        return r
    }

    private func input(_ g: String, _ p: String, _ v: String? = nil, allergy: Bool = false, mrsa: Bool = false) -> ProphylaxisInput {
        var i = ProphylaxisInput()
        i.chooseGroup(g, data: d)
        i.chooseProcedure(p, data: d)
        if let v { i.chooseVariant(v, data: d) }
        i.betaLactamAllergy = allergy
        i.mrsa = mrsa
        return i
    }

    private func answer(_ g: String, _ p: String, _ v: String? = nil, allergy: Bool = false, mrsa: Bool = false,
                        record: PatientRecord? = nil) -> ProphylaxisAnswer {
        ProphylaxisEngine.answer(input(g, p, v, allergy: allergy, mrsa: mrsa), record: record ?? adult(), data: d, timers: t)
    }

    private func line(_ a: ProphylaxisAnswer, _ agent: String) throws -> ProphylaxisLine {
        try XCTUnwrap(a.allLines.first { $0.agent == agent }, "\(agent) is in the result")
    }

    // MARK: - The data

    func testTheBundledFileDecodesWithTheSection() throws {
        let p = try XCTUnwrap(bundleFile.prophylaxis)
        XCTAssertEqual(p.groups.count, 14)
        XCTAssertEqual(p.groups.flatMap(\.procedures).count, 55)
        XCTAssertEqual(p.mrsaAgent, "vancomycin")
        XCTAssertFalse(p.info.about.isEmpty)
        XCTAssertEqual(p.info.noDose, "Dose not in this app")
        XCTAssertEqual(p.info.none, "No prophylaxis recommended")
        XCTAssertEqual(p.source.id, "bratzler")
    }

    func testABundleWithoutTheSectionStillDecodesAndIsFilledFromTheBuiltInCopy() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        obj.removeValue(forKey: "prophylaxis")
        let older = try ReferenceLoader.decode(try JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(older.prophylaxis, "an older reference.json has no section")
        XCTAssertNotNil(older.filling(from: bundleFile).prophylaxis, "the copy built into the app fills it in")
        XCTAssertNotNil(bundleFile.filling(from: older).prophylaxis, "a newer file keeps its own")
    }

    func testAnUnknownKindReadsAsTextAndAResultWithNoOptionalFieldDecodes() throws {
        let json = #"""
        {"quickref":"q","source":{"id":"a","label":"b","url":"u"},"classes":[],"agents":[],"mrsaAgent":"vancomycin","info":{},
         "groups":[{"id":"g","name":"G","specialties":[],"procedures":[{"id":"p","name":"P","variants":[
           {"id":"only","recommended":{"text":"A new table cell","kind":"somethingNewer"},"allergy":{"text":"None","kind":"none"}},
           {"id":"bare"}]}]}]}
        """#
        let p = try JSONDecoder().decode(ProphylaxisData.self, from: Data(json.utf8))
        let v = try XCTUnwrap(p.groups.first?.procedures.first?.variants.first)
        XCTAssertEqual(v.recommended?.kind, .text, "an unknown kind shows the table's text")
        XCTAssertEqual(v.recommended?.text, "A new table cell")
        XCTAssertEqual(v.allergy?.kind, ProphylaxisResult.Kind.none)
        XCTAssertEqual(v.recommended?.notes, [])
        XCTAssertFalse(v.recommended?.star ?? true)
        XCTAssertNil(v.evidence); XCTAssertNil(v.table); XCTAssertNil(v.outside); XCTAssertNil(p.reviewed)
        XCTAssertNil(p.groups[0].short); XCTAssertNil(p.groups[0].note); XCTAssertNil(p.groups[0].procedures[0].question)
        let bare = try XCTUnwrap(p.groups.first?.procedures.first?.variants.last)
        XCTAssertNil(bare.recommended)
        // The whole bundle decodes with such a section in it.
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        obj["prophylaxis"] = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let b = try ReferenceLoader.decode(try JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(b.prophylaxis?.groups.first?.id, "g")
    }

    func testEveryVariantEqualsTheCellsOfItsRowInTheTable() throws {
        let card = try XCTUnwrap(bundleFile.quickrefs.first { $0.id == d.quickref })
        XCTAssertEqual(d.quickref, "ashp-surgical-prophylaxis")
        var reached = Set<String>()
        for g in d.groups { for p in g.procedures { for v in p.variants {
            guard let ref = v.table else { continue }
            let section = try XCTUnwrap(card.sections.first { $0.heading == ref.section && $0.kind == .table }, "\(ref.section) is a table of the card")
            let row = try XCTUnwrap(section.rows?.first { $0.first == ref.row }, "\(ref.row) is a row of \(ref.section)")
            XCTAssertEqual(v.recommended?.text, row[1], "\(p.id)/\(v.id) recommended")
            XCTAssertEqual(v.allergy?.text, row[2], "\(p.id)/\(v.id) allergy")
            XCTAssertEqual(v.evidence, row[3], "\(p.id)/\(v.id) evidence")
            reached.insert(ref.section + "|" + ref.row)
        } } }
        for section in card.sections where section.kind == .table {
            for row in section.rows ?? [] {
                XCTAssertTrue(reached.contains((section.heading ?? "") + "|" + row[0]), "no variant reaches \(section.heading ?? ""): \(row[0])")
            }
        }
    }

    func testEveryTokenResolves() throws {
        let ids = Set(t.antibiotics.map(\.id))
        let named = Set(d.agents.map(\.id))
        for c in d.classes {
            XCTAssertFalse(c.agents.isEmpty, c.id)
            for a in c.agents { XCTAssertTrue(ids.contains(a), "class \(c.id): \(a) is a Case Timers antibiotic") }
        }
        XCTAssertTrue(ids.contains(d.mrsaAgent))
        for a in d.agents { XCTAssertFalse(ids.contains(a.id), "\(a.id) has no dose in Case Timers") }
        var seen = 0
        for g in d.groups { for p in g.procedures { for v in p.variants {
            for r in [v.recommended, v.allergy].compactMap({ $0 }) {
                if r.kind == .regimens { XCTAssertFalse(r.regimens.isEmpty, "\(p.id)/\(v.id)") }
                for reg in r.regimens { for slot in reg.slots {
                    XCTAssertFalse(slot.any.isEmpty)
                    for token in slot.any {
                        seen += 1
                        if token.hasPrefix("class:") {
                            XCTAssertNotNil(d.cls(String(token.dropFirst(6))), token)
                        } else {
                            XCTAssertTrue(ids.contains(token) || named.contains(token), "\(token) in \(p.id)/\(v.id)")
                        }
                    }
                } }
            }
        } } }
        XCTAssertGreaterThan(seen, 50)
    }

    func testCatalogIdsAndSpecialtiesAreTheCatalogs() throws {
        var all: [String] = []
        for g in d.groups { for p in g.procedures { all += p.catalog ?? [] } }
        for id in all { XCTAssertNotNil(ProcedureCatalog.byID(id), "\(id) is a ProcedureCatalog id") }
        XCTAssertEqual(Set(all).count, all.count, "no catalog id appears twice")
        let specialties = Set(ProcedureCatalog.all.map(\.specialty))
        for g in d.groups { for s in g.specialties { XCTAssertTrue(specialties.contains(s), "\(s) is a specialty of the catalog") } }
    }

    func testAProcedureWithSeveralVariantsAsksAQuestionWithLabels() throws {
        var asking = 0
        for g in d.groups { for p in g.procedures {
            if p.variants.count > 1 {
                asking += 1
                XCTAssertFalse((p.question ?? "").isEmpty, "\(p.id) has a question")
                for v in p.variants { XCTAssertFalse((v.label ?? "").isEmpty, "\(p.id)/\(v.id) has a label") }
            } else {
                XCTAssertNil(p.question, "\(p.id) asks nothing")
            }
        } }
        XCTAssertGreaterThanOrEqual(asking, 4)
    }

    // MARK: - The inputs

    func testAGroupWithOneProcedureSelectsItAtOnceAndANewProcedureForgetsTheAnswer() {
        var i = ProphylaxisInput()
        i.chooseGroup("ophthalmic", data: d)
        XCTAssertEqual(i.procedure, "ophthalmic", "one procedure: selected at once")
        i.chooseGroup("cardiac", data: d)
        XCTAssertNil(i.procedure, "several: the user picks")
        i.chooseProcedure("cabg", data: d)
        XCTAssertEqual(i.summary(d), "Cardiac · Coronary artery bypass (CABG)")
        var short = ProphylaxisInput()
        short.chooseGroup("lowergi", data: d)
        short.chooseProcedure("colorectal", data: d)
        XCTAssertEqual(short.summary(d), "Bowel & Hernia · Colon or rectal surgery (colectomy, rectal resection)", "the group as its chip says it")
        var same = ProphylaxisInput()
        same.chooseGroup("ophthalmic", data: d)
        XCTAssertEqual(same.summary(d), "Ophthalmic", "a name is not said twice")
        i.chooseGroup("biliary", data: d)
        i.chooseProcedure("lap", data: d)
        i.chooseVariant("high", data: d)
        XCTAssertEqual(i.variant, "high")
        i.chooseProcedure("open", data: d)
        XCTAssertNil(i.variant, "a different procedure forgets the old answer")
        i.chooseProcedure("nope", data: d)
        XCTAssertEqual(i.procedure, "open", "an id the group does not have changes nothing")
        i.chooseGroup("biliary", data: d)
        XCTAssertEqual(i.procedure, "open", "the same group again keeps the choice")
    }

    func testNothingChosenShowsNothingAndTheQuestionIsAskedBeforeAnAnswer() {
        let none = ProphylaxisEngine.answer(ProphylaxisInput(), record: adult(), data: d, timers: t)
        XCTAssertEqual(none.state, .noProcedure)
        XCTAssertTrue(none.allLines.isEmpty)
        let asking = answer("biliary", "lap")
        XCTAssertEqual(asking.state, .question)
        XCTAssertEqual(asking.question, d.group("biliary")?.procedure("lap")?.question)
        XCTAssertTrue(asking.allLines.isEmpty)
    }

    // MARK: - The output

    func testCABGAt90KgGivesCefazolinAndCefuroximeWithTheirDosesAndRedose() throws {
        let a = answer("cardiac", "cabg")
        XCTAssertEqual(a.state, .regimens)
        XCTAssertEqual(a.title, "Recommended")
        XCTAssertEqual(a.evidence, "Evidence A")
        XCTAssertFalse(a.alternative)
        XCTAssertEqual(a.regimens.count, 2, "two alternatives")
        XCTAssertTrue(a.regimens.allSatisfy { $0.isSingle })
        let cefazolin = try line(a, "cefazolin")
        XCTAssertEqual(cefazolin.dose, "2 g")
        XCTAssertEqual(cefazolin.redose, "Redose every 4 h")
        XCTAssertTrue(cefazolin.startable)
        XCTAssertEqual(try line(a, "cefuroxime").dose, "1.5 g")
        XCTAssertEqual(try line(a, "cefuroxime").redose, "Redose every 4 h")
        XCTAssertEqual(a.timing, d.info.timing)
        XCTAssertNil(a.mrsa, "no MRSA block unless it is asked for")
        XCTAssertNil(a.childLine)
    }

    func testAt125KgCefazolinIs3GAndTheWholeHoursReadWithoutADecimal() throws {
        XCTAssertEqual(try line(answer("cardiac", "cabg", record: adult(125)), "cefazolin").dose, "3 g")
        XCTAssertEqual(try line(answer("cardiac", "cabg", record: adult(119)), "cefazolin").dose, "2 g")
        XCTAssertEqual(ProphylaxisEngine.redoseText(4), "Redose every 4 h")
        XCTAssertEqual(ProphylaxisEngine.redoseText(2), "Redose every 2 h")
        XCTAssertEqual(ProphylaxisEngine.redoseText(6), "Redose every 6 h")
        XCTAssertEqual(ProphylaxisEngine.redoseText(1.5), "Redose every 1.5 h")
        XCTAssertEqual(ProphylaxisEngine.redoseText(nil), "No routine redose")
    }

    func testTheAllergyResultIsTheAlternativeWithItsStarInfo() throws {
        let a = answer("cardiac", "cabg", allergy: true)
        XCTAssertEqual(a.title, "Alternative for β-lactam allergy")
        XCTAssertTrue(a.alternative)
        let clinda = try line(a, "clindamycin")
        XCTAssertEqual(clinda.dose, "900 mg")
        XCTAssertEqual(clinda.redose, "Redose every 6 h")
        let vanc = try line(a, "vancomycin")
        let def = try XCTUnwrap(t.antibiotic("vancomycin"))
        XCTAssertEqual(vanc.dose, CaseTimerEngine.antibioticDose(def, record: adult()).text, "the weight dose, as Case Timers works it out")
        XCTAssertEqual(vanc.redose, "No routine redose")
        XCTAssertEqual(vanc.note, "Start within 120 min of incision.")
        for s in d.info.star { XCTAssertTrue(a.info.contains(s), "the asterisk's explanation is in the ⓘ") }
        XCTAssertFalse(answer("cardiac", "cabg").info.contains(d.info.star[0]), "a result without the asterisk does not carry it")
    }

    func testKnownMRSAAddsASingleDoseOfVancomycinEvenWhenItIsAlreadyAChoice() throws {
        let a = answer("cardiac", "cabg", mrsa: true)
        let m = try XCTUnwrap(a.mrsa)
        XCTAssertEqual(a.mrsaTitle, "Known MRSA colonization")
        XCTAssertEqual(m.agent, "vancomycin")
        XCTAssertEqual(m.redose, "Single preoperative dose")
        XCTAssertNotNil(m.dose)
        XCTAssertTrue(m.startable)
        XCTAssertNil(a.mrsaNote)
        // Vancomycin already among the choices (the β-lactam alternatives): named once, with the guideline's sentence in place of a
        // second line and a second Start.
        let both = answer("cardiac", "cabg", allergy: true, mrsa: true)
        XCTAssertNil(both.mrsa)
        XCTAssertEqual(both.mrsaTitle, "Known MRSA colonization")
        XCTAssertEqual(both.mrsaNote, "Vancomycin is among the choices above. " + d.info.mrsa)
        XCTAssertEqual(both.allLines.filter { $0.agent == "vancomycin" }.count, 1)
        XCTAssertNotNil(try line(both, "vancomycin"))
    }

    func testColorectalAllergyIsTwoCombinationsWithClassesExpanded() throws {
        let a = answer("lowergi", "colorectal", allergy: true)
        let want = try XCTUnwrap(d.group("lowergi")?.procedure("colorectal")?.variants.first?.allergy)
        XCTAssertEqual(a.regimens.count, 2)
        XCTAssertEqual(a.regimens.map { $0.slots.count }, want.regimens.map { $0.slots.count }, "the slot structure of the data")
        XCTAssertFalse(a.regimens.contains { $0.isSingle })
        let first = a.regimens[0]
        XCTAssertEqual(first.slots[0].lines.map(\.agent), ["clindamycin"])
        XCTAssertEqual(first.slots[1].lines.map(\.agent), ["gentamicin", "aztreonam", "ciprofloxacin", "levofloxacin"], "the class expanded in place, the others as they are")
        XCTAssertEqual(first.slots[1].lines.map(\.caption), ["Aminoglycoside", nil, "Fluoroquinolone", "Fluoroquinolone"])
        let second = a.regimens[1]
        XCTAssertEqual(second.slots[0].lines.map(\.agent), ["metronidazole"])
        XCTAssertEqual(second.slots[1].lines.map(\.agent), ["gentamicin", "ciprofloxacin", "levofloxacin"])
        XCTAssertEqual(try line(a, "gentamicin").redose, "No routine redose")
        XCTAssertEqual(a.notes, want.notes, "the notes are shown in full")
    }

    func testAnOptionalSlotKeepsItsFlag() throws {
        let a = answer("urologic", "prosthesis")
        XCTAssertEqual(a.regimens.count, 2)
        let combo = a.regimens[0]
        XCTAssertEqual(combo.slots.count, 2)
        XCTAssertFalse(combo.slots[0].optional)
        XCTAssertTrue(combo.slots[1].optional, "± an aminoglycoside or aztreonam")
        XCTAssertEqual(combo.slots[1].lines.map(\.agent), ["gentamicin", "aztreonam"])
        XCTAssertTrue(a.regimens[1].isSingle)
    }

    func testLaparoscopicBiliaryLowRiskIsNoProphylaxisWithItsNoteAndNoMRSABlock() throws {
        let a = answer("biliary", "lap", "low", mrsa: true)
        XCTAssertEqual(a.state, .none)
        XCTAssertEqual(a.body, "No prophylaxis recommended")
        XCTAssertFalse(a.notes.isEmpty)
        XCTAssertNil(a.mrsa, "MRSA changes nothing for no prophylaxis")
        XCTAssertTrue(a.allLines.isEmpty)
        XCTAssertNil(a.timing)
        let high = answer("biliary", "lap", "high", mrsa: true)
        XCTAssertEqual(high.state, .regimens)
        XCTAssertNotNil(high.mrsa)
        XCTAssertEqual(high.regimens.count, 5, "cefazolin, cefoxitin, cefotetan, ceftriaxone, ampicillin–sulbactam")
    }

    func testGastroduodenalNotHighRiskIsNotInTheTable() {
        let a = answer("gastroduodenal", "no-entry", "not-high", mrsa: true)
        XCTAssertEqual(a.state, .outside)
        XCTAssertEqual(a.title, "Not in the guideline's table")
        XCTAssertEqual(a.body, d.group("gastroduodenal")?.procedure("no-entry")?.variants.last?.outside)
        XCTAssertTrue(a.allLines.isEmpty)
        XCTAssertNil(a.mrsa)
        XCTAssertNil(a.evidence)
        let high = answer("gastroduodenal", "no-entry", "high")
        XCTAssertEqual(high.state, .regimens)
    }

    func testOphthalmicIsTheTablesTextAsItIs() throws {
        let a = answer("ophthalmic", "ophthalmic")
        XCTAssertEqual(a.state, .text)
        XCTAssertEqual(a.body, d.group("ophthalmic")?.procedure("ophthalmic")?.variants.first?.recommended?.text)
        XCTAssertTrue(a.allLines.isEmpty)
        // The allergy cell reads "None": no alternative agent is listed, which is not "no prophylaxis" (the recommended agents are
        // topical). It is shown as the cell's text with the note that says so, never as "No prophylaxis recommended".
        let alt = answer("ophthalmic", "ophthalmic", allergy: true)
        XCTAssertEqual(alt.state, .text)
        XCTAssertEqual(alt.body, "No alternative agent listed")
        XCTAssertNotEqual(alt.body, d.info.none)
        XCTAssertEqual(alt.notes.count, 1)
        XCTAssertTrue(alt.notes[0].hasPrefix("The guideline's table lists no alternative agent for ophthalmic procedures."), alt.notes[0])
        // The note carries the recommended (topical) agents word for word, so nothing has to be toggled to read them.
        let recommended = try XCTUnwrap(d.group("ophthalmic")?.procedure("ophthalmic")?.variants.first?.recommended?.text)
        XCTAssertTrue(alt.notes[0].contains(recommended), alt.notes[0])
        XCTAssertTrue(alt.info.contains { $0.hasSuffix("None") }, "the table's own cell stays behind the info link: \(alt.info)")
        XCTAssertTrue(alt.allLines.isEmpty)
        XCTAssertNil(answer("ophthalmic", "ophthalmic", allergy: true, mrsa: true).mrsa, "nothing is added to a result with no agents")
    }

    func testAppendectomyAsksWhetherTheAppendicitisIsUncomplicated() throws {
        // The table's row is for uncomplicated appendicitis only: a planned appendectomy selects the procedure and the user answers.
        let p = ProphylaxisEngine.prefill(record: caseWith([try planned("lap-appy")]), data: d)
        XCTAssertEqual(p.group, "lowergi")
        XCTAssertEqual(p.procedure, "appendectomy")
        XCTAssertEqual(answer("lowergi", "appendectomy").state, .question)
        let yes = answer("lowergi", "appendectomy", "uncomplicated")
        XCTAssertEqual(yes.state, .regimens)
        XCTAssertEqual(yes.regimens.count, 3)
        let no = answer("lowergi", "appendectomy", "complicated")
        XCTAssertEqual(no.state, .outside)
        XCTAssertTrue(no.body.contains("uncomplicated appendicitis"), no.body)
        XCTAssertTrue(no.allLines.isEmpty)
    }

    func testThePrefillLeavesOutOperationsThatAreOftenEmergenciesOrAnotherRow() throws {
        // Removed after an independent check of the mapping (Nov 16): each of these selects no table row.
        for id in ["hartmann", "colonic-volvulus", "obturator-hernia", "aneurysm-clipping", "revision-tka", "revision-tha", "femoral-nail", "hemothorax",
                   "turp", "holep", "turbt", "cystolitholapaxy"] {
            XCTAssertNotNil(ProcedureCatalog.byID(id), id)
            XCTAssertNil(ProphylaxisEngine.prefill(record: caseWith([try planned(id)]), data: d).procedure, id)
        }
        // A specialty whose operations the group's rows do not all describe opens no group: an esophagectomy is not a lung resection.
        for id in ["ivor-lewis", "angiogram-diagnostic", "donor-nephrectomy", "blepharoplasty"] {
            XCTAssertNil(ProphylaxisEngine.prefill(record: caseWith([try planned(id)]), data: d).group, id)
        }
    }

    func testLiverTransplantNamesCefotaximeWithNoDoseAndNeverStartsIt() throws {
        let a = answer("transplant", "liver")
        let cefotaxime = try line(a, "cefotaxime")
        XCTAssertEqual(cefotaxime.name, "Cefotaxime")
        XCTAssertEqual(cefotaxime.noDose, "Dose not in this app")
        XCTAssertNil(cefotaxime.dose)
        XCTAssertNil(cefotaxime.redose)
        XCTAssertFalse(cefotaxime.startable)
        XCTAssertNotNil(try line(a, "piperacillin-tazobactam").dose)
        XCTAssertEqual(ProphylaxisEngine.startState("cefotaxime", record: adult(), timers: t), .unavailable)
        var r = adult()
        XCTAssertFalse(ProphylaxisEngine.start("cefotaxime", in: &r, timers: t, now: Date()))
        XCTAssertTrue(r.timers.antibiotics.isEmpty)
    }

    func testWithoutAWeightTheDosesReadAsTheWrittenRule() throws {
        let a = answer("cardiac", "cabg", allergy: true, record: adult(nil))
        XCTAssertEqual(try line(a, "vancomycin").dose, "15 mg/kg")
        XCTAssertEqual(try line(a, "vancomycin").needs, "Weight needed")
        let b = answer("cardiac", "cabg", record: adult(nil))
        XCTAssertEqual(try line(b, "cefazolin").dose, "2 g; 3 g if ≥120 kg")
    }

    func testEveryAgentLineHasExactlyCaseTimersDoseForTheSameRecord() throws {
        var checked = 0
        for g in d.groups { for p in g.procedures { for v in p.variants {
            for allergy in [false, true] {
                let weights: [Double?] = [62, 90, 125, nil]
                for kg in weights {
                    var i = ProphylaxisInput()
                    i.chooseGroup(g.id, data: d); i.chooseProcedure(p.id, data: d); i.chooseVariant(v.id, data: d)
                    i.betaLactamAllergy = allergy; i.mrsa = true
                    let r = adult(kg)
                    let a = ProphylaxisEngine.answer(i, record: r, data: d, timers: t)
                    for l in a.allLines {
                        if let def = t.antibiotic(l.agent) {
                            let want = CaseTimerEngine.antibioticDose(def, record: r)
                            XCTAssertEqual(l.dose, want.text, "\(p.id)/\(v.id) \(l.agent)")
                            XCTAssertEqual(l.needs, want.needs)
                            XCTAssertEqual(l.note, def.note)
                            checked += 1
                        } else {
                            XCTAssertNil(l.dose, "\(l.agent) has no dose here")
                            XCTAssertFalse(l.startable)
                        }
                    }
                }
            }
        } } }
        XCTAssertGreaterThan(checked, 500)
    }

    func testAChildGetsNoDoseNoRedoseAndTheAdultOnlyLine() throws {
        let a = answer("cardiac", "cabg", allergy: true, mrsa: true, record: child())
        XCTAssertEqual(a.childLine, "Adult doses only: no dose is shown for a patient under 18.")
        for l in a.allLines {
            XCTAssertNil(l.dose, l.agent)
            XCTAssertNil(l.redose, l.agent)
        }
        XCTAssertEqual(try line(a, "clindamycin").name, "Clindamycin", "the agent is still named")
        XCTAssertEqual(ProphylaxisEngine.startState("cefazolin", record: child(), timers: t), .unavailable,
                       "Case Timers' antibiotic card is locked for a child: adult defaults only")
        XCTAssertNil(answer("cardiac", "cabg").childLine)
    }

    func testTheInfoOfAResultHoldsItsExplanationsAndNothingTwice() throws {
        // A starred result.
        let star = answer("cardiac", "cabg", allergy: true)
        XCTAssertEqual(star.info.first, d.info.evidence)
        XCTAssertTrue(star.info.contains("As the guideline's table writes it: Clindamycin*, vancomycin*"))
        XCTAssertTrue(star.info.contains(d.info.star[1]))
        // A result with classes and a fluoroquinolone.
        let fq = answer("lowergi", "colorectal", allergy: true)
        XCTAssertTrue(fq.info.contains(d.info.classes))
        XCTAssertTrue(fq.info.contains(try XCTUnwrap(d.cls("aminoglycoside")?.note)), "the class's own note")
        XCTAssertTrue(fq.info.contains(d.info.fluoroquinolone[0]))
        XCTAssertTrue(fq.info.contains(d.info.fluoroquinolone[1]))
        XCTAssertFalse(fq.info.contains(d.info.star[0]), "no star here")
        // Ampicillin–sulbactam.
        let amp = answer("thoracic", "open")
        XCTAssertTrue(amp.info.contains(d.info.ampicillinSulbactam[0]))
        XCTAssertFalse(amp.info.contains(d.info.classes))
        // A group with a note.
        let vascular = answer("vascular", "vascular")
        XCTAssertTrue(vascular.info.contains(try XCTUnwrap(d.group("vascular")?.note)))
        XCTAssertFalse(answer("cardiac", "cabg").info.contains { $0.hasPrefix("Prophylaxis is not routinely") })
        for a in [star, fq, amp, vascular] { XCTAssertEqual(Set(a.info).count, a.info.count, "no paragraph twice") }
    }

    func testTheEColiLineThatBothListsHoldIsShownOnce() throws {
        var dd = d
        let both = ProphylaxisResult(text: "Ampicillin–sulbactam, fluoroquinolone", kind: .regimens, regimens: [
            ProphylaxisRegimen(slots: [ProphylaxisSlot(any: ["ampicillin-sulbactam"])]),
            ProphylaxisRegimen(slots: [ProphylaxisSlot(any: ["class:fluoroquinolone"])]),
        ])
        dd.groups = [ProphylaxisGroup(id: "g", name: "G", procedures: [
            ProphylaxisProcedure(id: "p", name: "P", variants: [ProphylaxisVariant(id: "only", recommended: both, allergy: both)]),
        ])]
        var i = ProphylaxisInput()
        i.chooseGroup("g", data: dd)
        let a = ProphylaxisEngine.answer(i, record: adult(), data: dd, timers: t)
        XCTAssertEqual(d.info.fluoroquinolone[0], d.info.ampicillinSulbactam[0], "the data holds the line in both lists")
        XCTAssertEqual(a.info.filter { $0 == d.info.fluoroquinolone[0] }.count, 1)
    }

    // MARK: - The prefill from a case

    private func caseWith(_ planned: [PlannedProcedure]) -> PatientRecord {
        var r = adult()
        r.setProcedures(planned)
        return r
    }

    private func planned(_ id: String) throws -> PlannedProcedure {
        PlannedProcedure(try XCTUnwrap(ProcedureCatalog.byID(id), id))
    }

    func testPrefillSelectsTheProcedureNeverTheAnswer() throws {
        let r = caseWith(PlannedProcedure.parse("CABG x3"))
        let p = ProphylaxisEngine.prefill(record: r, data: d)
        XCTAssertEqual(p.group, "cardiac")
        XCTAssertEqual(p.procedure, "cabg")
        XCTAssertEqual(p.procedureCaption, "From the case: " + r.procedures[0].title)
        var i = ProphylaxisInput()
        i.apply(p, data: d)
        XCTAssertEqual(i.summary(d), "Cardiac · Coronary artery bypass (CABG)")
        XCTAssertNil(i.variant)
        // A procedure that asks: the group and procedure are chosen, the question is the user's.
        let nissen = ProphylaxisEngine.prefill(record: caseWith([try planned("nissen")]), data: d)
        XCTAssertEqual(nissen.group, "gastroduodenal")
        XCTAssertEqual(nissen.procedure, "no-entry")
        var j = ProphylaxisInput()
        j.apply(nissen, data: d)
        XCTAssertNil(j.variant)
        XCTAssertEqual(ProphylaxisEngine.answer(j, record: adult(), data: d, timers: t).state, .question)
    }

    func testAnAorticValveReplacementSelectsTheCardiacGroupOnly() throws {
        let r = caseWith(PlannedProcedure.parse("AVR"))
        XCTAssertEqual(r.procedures.first?.catalogID, "avr")
        let p = ProphylaxisEngine.prefill(record: r, data: d)
        XCTAssertEqual(p.group, "cardiac")
        XCTAssertNil(p.procedure, "no table row names a valve replacement")
        XCTAssertEqual(p.procedureCaption, "From the case: " + r.procedures[0].title)
        var i = ProphylaxisInput()
        i.apply(p, data: d)
        XCTAssertEqual(i.group, "cardiac")
        XCTAssertNil(i.procedure)
    }

    func testAHerniaRepairAndTheFirstMatchingProcedureWin() throws {
        let hernia = ProphylaxisEngine.prefill(record: caseWith([try planned("inguinal-hernia-open")]), data: d)
        XCTAssertEqual(hernia.group, "lowergi")
        XCTAssertEqual(hernia.procedure, "hernia")
        // The catalog match beats an earlier procedure that only matches a specialty.
        let two = ProphylaxisEngine.prefill(record: caseWith([try planned("avr"), try planned("cabg")]), data: d)
        XCTAssertEqual(two.procedure, "cabg")
        XCTAssertEqual(two.group, "cardiac")
    }

    func testNoProcedureOrOneOutsideEveryGroupPrefillsNothing() throws {
        XCTAssertTrue(ProphylaxisEngine.prefill(record: adult(), data: d).isEmpty)
        let colonoscopy = ProphylaxisEngine.prefill(record: caseWith([try planned("colonoscopy")]), data: d)
        XCTAssertNil(colonoscopy.group, "an endoscopy is in no group")
        XCTAssertNil(colonoscopy.procedureCaption)
        var typed = adult()
        typed.procedures = [PlannedProcedure(name: "Something typed")]
        XCTAssertNil(ProphylaxisEngine.prefill(record: typed, data: d).group)
    }

    private func allergic(_ typed: String) -> PatientRecord {
        var r = adult()
        r.allergyList = AllergyCatalog.parse(typed)
        return r
    }

    func testPrefillReadsAPenicillinCephalosporinOrCarbapenemAllergy() throws {
        let pcn = ProphylaxisEngine.prefill(record: allergic("PCN - rash"), data: d)
        XCTAssertTrue(pcn.betaLactamAllergy)
        XCTAssertEqual(pcn.allergyCaption, "From the case: Penicillin (rash)")
        for typed in ["cefazolin", "cephalosporins", "carbapenems", "meropenem", "ceftriaxone anaphylaxis", "amoxicillin", "augmentin", "Zosyn", "ertapenem"] {
            XCTAssertTrue(ProphylaxisEngine.prefill(record: allergic(typed), data: d).betaLactamAllergy, typed)
        }
        // A β-lactam the catalog does not carry, named in the extra list.
        var cefoxitin = adult()
        cefoxitin.allergyList = [PatientAllergy(name: "Cefoxitin")]
        XCTAssertTrue(ProphylaxisEngine.prefill(record: cefoxitin, data: d).betaLactamAllergy)
    }

    func testAztreonamSulfaVancomycinAndClindamycinAreNotBetaLactamAllergies() throws {
        var aztreonam = adult()
        aztreonam.allergyList = [PatientAllergy(name: "Aztreonam")]
        XCTAssertFalse(ProphylaxisEngine.prefill(record: aztreonam, data: d).betaLactamAllergy, "the guideline uses aztreonam as an alternative")
        for typed in ["sulfa", "vancomycin", "clindamycin", "latex", "gentamicin", "ciprofloxacin", "NSAIDs"] {
            XCTAssertFalse(ProphylaxisEngine.prefill(record: allergic(typed), data: d).betaLactamAllergy, typed)
        }
        // "tolerated cefazolin" is not an allergy: the reader records nothing for it.
        XCTAssertTrue(AllergyCatalog.parse("tolerated cefazolin").isEmpty)
        XCTAssertFalse(ProphylaxisEngine.prefill(record: allergic("tolerated cefazolin"), data: d).betaLactamAllergy)
        // A penicillin listed with a cefazolin tolerance is still the penicillin allergy, captioned with its reaction as typed.
        let mixed = ProphylaxisEngine.prefill(record: allergic("PCN (hives; tolerated cefazolin)"), data: d)
        XCTAssertTrue(mixed.betaLactamAllergy)
        XCTAssertEqual(mixed.allergyCaption, "From the case: Penicillin (hives; tolerated cefazolin)")
    }

    func testSeveralAllergensAreAllListedInTheCaption() {
        let p = ProphylaxisEngine.prefill(record: allergic("PCN rash, cefazolin anaphylaxis, sulfa"), data: d)
        XCTAssertTrue(p.betaLactamAllergy)
        let caption = p.allergyCaption ?? ""
        XCTAssertTrue(caption.hasPrefix("From the case: "))
        XCTAssertTrue(caption.contains("Penicillin"), caption)
        XCTAssertTrue(caption.contains("Cefazolin (anaphylaxis)"), caption)
        XCTAssertFalse(caption.lowercased().contains("sulfa"), "only the β-lactams are the answer")
    }

    func testAllergiesTypedBeforeTheListAreReadAsTheRowReadsThem() {
        var r = adult()
        r.allergies = "PCN rash"
        XCTAssertTrue(ProphylaxisEngine.prefill(record: r, data: d).betaLactamAllergy)
        r.allergies = "latex"
        XCTAssertFalse(ProphylaxisEngine.prefill(record: r, data: d).betaLactamAllergy)
        var none = adult()
        none.nkda = true
        XCTAssertFalse(ProphylaxisEngine.prefill(record: none, data: d).betaLactamAllergy)
    }

    func testOnlyAPositiveMRSAScreenPrefillsMRSA() {
        var r = adult()
        XCTAssertFalse(ProphylaxisEngine.prefill(record: r, data: d).mrsa, "not done")
        r.infections.results["mrsa"] = .negative
        XCTAssertFalse(ProphylaxisEngine.prefill(record: r, data: d).mrsa)
        r.infections.results["mrsa"] = .pending
        XCTAssertFalse(ProphylaxisEngine.prefill(record: r, data: d).mrsa)
        r.infections.results["mrsa"] = .positive
        let p = ProphylaxisEngine.prefill(record: r, data: d)
        XCTAssertTrue(p.mrsa)
        XCTAssertEqual(p.mrsaCaption, "From the case: MRSA screen positive")
        var problem = adult()
        problem.problems = ["mdro"]
        XCTAssertFalse(ProphylaxisEngine.prefill(record: problem, data: d).mrsa, "\"MRSA or VRE\" may be VRE")
    }

    func testThePrefillIsOnlyAStartingPointAndWritesNothingToTheCase() throws {
        var r = allergic("PCN - rash")
        r.infections.results["mrsa"] = .positive
        let before = r
        var i = ProphylaxisInput()
        i.apply(ProphylaxisEngine.prefill(record: r, data: d), data: d)
        XCTAssertTrue(i.betaLactamAllergy)
        XCTAssertTrue(i.mrsa)
        i.betaLactamAllergy = false
        i.mrsa = false
        XCTAssertEqual(r, before, "changing the answer here does not edit the patient's allergies")
    }

    // MARK: - Start

    private func ago(_ minutes: Double) -> Date { Date().addingTimeInterval(-minutes * 60) }

    func testStartLogsExactlyWhatCaseTimersLogsForAFirstDoseNow() throws {
        let now = Date()
        var r = adult(92)
        r.fluids["ebl"] = 150
        var expected = r
        let def = try XCTUnwrap(t.antibiotic("cefazolin"))
        // Case Timers' own path (CaseTimersView.startAntibiotics): the pick a drug starts with is its default interval.
        let pick = RecurrencePick(minutes: CaseTimerRecurrence.antibioticDefault(def))
        expected.timers.antibiotics.append(AntibioticCourse.started(drug: "cefazolin", time: now, ebl: expected.fluids["ebl"] ?? 0,
                                                                    every: CaseTimerRecurrence.storedInterval(pick), typedDose: nil))
        XCTAssertEqual(ProphylaxisEngine.startState("cefazolin", record: r, timers: t), .available)
        XCTAssertTrue(ProphylaxisEngine.start("cefazolin", in: &r, timers: t, now: now))
        // Each logged dose carries its own random id: the same dose, whatever its id.
        XCTAssertEqual(r.timers.antibiotics.count, 1)
        expected.timers.antibiotics[0].doses[0].id = r.timers.antibiotics[0].doses[0].id
        XCTAssertEqual(r, expected)
        XCTAssertEqual(r.timers.course("cefazolin")?.everyMinutes, 240)
        XCTAssertEqual(r.timers.course("cefazolin")?.doses.first?.ebl, 150)
        XCTAssertNil(r.timers.course("cefazolin")?.dose, "no typed dose: Case Timers works it out")
        XCTAssertTrue(CaseTimerEngine.reminders(r.timers, record: r, data: t).contains { $0.kind == .antibiotic },
                      "the redose reminder runs, as it does for a dose logged in Case Timers")
    }

    func testADrugWithNoRoutineRedoseStartsWithNoInterval() throws {
        var r = adult()
        XCTAssertTrue(ProphylaxisEngine.start("vancomycin", in: &r, timers: t, now: Date()))
        XCTAssertEqual(r.timers.course("vancomycin")?.everyMinutes, 0, "no redose timer")
    }

    func testAnExistingCourseIsReportedAsRunningAndNotStartedAgain() throws {
        var r = adult()
        let first = ago(40)
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: first, ebl: 0)])]
        XCTAssertEqual(ProphylaxisEngine.startState("cefazolin", record: r, timers: t), .running(last: first, recordOnly: false))
        let before = r
        XCTAssertFalse(ProphylaxisEngine.start("cefazolin", in: &r, timers: t, now: Date()), "a second dose is never logged from here")
        XCTAssertEqual(r, before)
        r.timers.antibiotics = [AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: first, ebl: 0)], reminders: false)]
        XCTAssertEqual(ProphylaxisEngine.startState("vancomycin", record: r, timers: t), .running(last: first, recordOnly: true))
        XCTAssertEqual(ProphylaxisEngine.startState("clindamycin", record: r, timers: t), .available, "another drug is not affected")
    }

    func testTheStartQuestionIsWordedAsSpecified() {
        XCTAssertEqual(ProphylaxisEngine.startTitle("Cefazolin"), "Start cefazolin now?")
        // No clock time in the question: the dose is logged when Start is tapped, which may be after the question appeared.
        XCTAssertEqual(ProphylaxisEngine.startMessage(hasRedose: true), "Logs a dose now and starts its redose timer.")
        XCTAssertEqual(ProphylaxisEngine.startMessage(hasRedose: false), "Logs a dose now.")
    }

    @MainActor func testStartIsOneUndoStepOnTheStore() throws {
        let store = PatientStore(url: nil)
        store.update { $0.ageYears = 60; $0.weightKg = 80 }
        let before = store.record
        let timers = t
        store.update(discrete: true) { r in _ = ProphylaxisEngine.start("cefazolin", in: &r, timers: timers, now: Date()) }
        XCTAssertEqual(store.record.timers.antibiotics.count, 1)
        store.undo()
        XCTAssertEqual(store.record, before, "one Undo takes the dose back")
    }

    // MARK: - Wiring

    func testTheRouteKeyAndItsRoundTrip() {
        XCTAssertEqual(RefRoute.prophylaxis.key, "prophylaxis")
        XCTAssertEqual(RefRoute(key: "prophylaxis"), .prophylaxis)
        XCTAssertEqual(RefRoute(key: RefRoute.prophylaxis.key), .prophylaxis)
        XCTAssertEqual(RefRoute(key: "quickref:ashp-surgical-prophylaxis"), .quickref("ashp-surgical-prophylaxis"), "the table itself still opens")
    }

    func testThePreoperativeFolderListsTheCalculatorInTheQuickReferencesPlace() throws {
        ProphylaxisGate.available = true
        let routes = RefFolder.preoperative.items.map(\.route)
        XCTAssertEqual(routes, [.score("rcri"), .score("ariscat"), .score("stopbang"), .score("apfel"), .fasting, .prophylaxis, .ponv, .abg, .score("aldrete"), .caseTimers])
        let item = try XCTUnwrap(RefFolder.preoperative.items.first { $0.route == .prophylaxis })
        XCTAssertEqual(item.title, "Surgical Antibiotic Prophylaxis")
        XCTAssertEqual(item.icon, "shield.lefthalf.filled")
        XCTAssertEqual(item.blurb, "Surgery and allergy in, agent, dose and redose out")
        XCTAssertFalse(routes.contains(.quickref("ashp-surgical-prophylaxis")), "the table is no longer listed on its own")
    }

    func testWithoutTheSectionTheFolderListsTheQuickReferenceAsBefore() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        obj.removeValue(forKey: "prophylaxis")
        let older = try ReferenceLoader.decode(try JSONSerialization.data(withJSONObject: obj))
        ProphylaxisGate.update(from: older)
        XCTAssertFalse(ProphylaxisGate.available)
        XCTAssertTrue(RefFolder.preoperative.items.contains { $0.route == .quickref("ashp-surgical-prophylaxis") })
        XCTAssertFalse(RefFolder.preoperative.items.contains { $0.route == .prophylaxis })
        XCTAssertEqual(ProphylaxisGate.linkRoute(hasCalculator: false), "quickref:ashp-surgical-prophylaxis", "\"Which antibiotic?\" opens the card")
        XCTAssertEqual(RefRoute.prophylaxis.listed, .quickref("ashp-surgical-prophylaxis"))
        ProphylaxisGate.update(from: bundleFile)
        XCTAssertTrue(ProphylaxisGate.available)
        XCTAssertEqual(ProphylaxisGate.linkRoute(hasCalculator: true), "prophylaxis")
        XCTAssertEqual(RefRoute(key: ProphylaxisGate.linkRoute(hasCalculator: true)), .prophylaxis)
    }

    @MainActor func testAnOldFavoriteOpensAndShowsAsTheCalculator() {
        ProphylaxisGate.available = true
        XCTAssertEqual(FavoritesStore.migrate(["valves", "quickref:ashp-surgical-prophylaxis"]), ["valves", "prophylaxis"])
        XCTAssertEqual(FavoritesStore.migrate(["quickref:ashp-surgical-prophylaxis", "prophylaxis"]), ["prophylaxis"], "no twice")
        XCTAssertEqual(RefItem.item(forKey: "quickref:ashp-surgical-prophylaxis")?.route, .prophylaxis)
        XCTAssertEqual(RefItem.item(forKey: "prophylaxis")?.route, .prophylaxis)
        XCTAssertEqual(RefItem.item(for: .quickref("ashp-surgical-prophylaxis"))?.title, "Surgical Antibiotic Prophylaxis")
        XCTAssertEqual(RefRoute.quickref("ashp-surgical-prophylaxis").listed, .prophylaxis)
        XCTAssertEqual(RefRoute.quickref("asra-last").listed, .quickref("asra-last"), "no other card changes")
    }

    @MainActor func testTheLinkTextIsKeptAndTheCalculatorIsFoundByTheCardsWords() throws {
        XCTAssertEqual(IntraopAntibiotic.referenceLink, "Which antibiotic?")
        let words = ReferenceSearchResults.keywords(for: .prophylaxis)
        XCTAssertTrue(words.contains("prophylaxis"))
        XCTAssertTrue(words.contains("antibiotic"))
        let card = try XCTUnwrap(bundleFile.quickrefs.first { $0.id == d.quickref })
        XCTAssertFalse(card.searchText.isEmpty, "the card's own text is searched for the calculator too")
    }
}
