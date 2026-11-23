import XCTest
@testable import PeriopSignal

/// Ben, Nov 23 ("approve all"): the Surgical Prophylaxis calculator lists the operations the 2013 guideline does not name. Each shows the
/// result of the guideline row it belongs with, flagged as Periop Signal's reading; some answer only with text; carotid endarterectomy
/// asks about a patch or graft; every group ends with "Operation not listed". The caveats moved behind the info link (Ben, Nov 16:
/// "explanations behind info link"): a flagged result shows one caution line, its other notes are the first paragraphs of the info, and
/// the card says how many there are. A planned operation that no row names opens on "Operation not listed".
final class ProphylaxisReading115Tests: XCTestCase {

    // Nov 23 check: the label says "the 2013 guideline's table" (it said "the 2013 guideline"). Ten rows that carried it now carry a
    // "Periop Signal note: ..." instead, seven flagged rows were removed and one added, so 65 rows (134 results) are flagged, where 81 rows
    // (166 results) were.
    static let notNamed = "Not named in the 2013 guideline's table: Periop Signal's reading. Check your protocol."

    private var bundleFile: ReferenceBundle!
    private var d: ProphylaxisData { bundleFile.prophylaxis! }
    private var t: CaseTimerData { bundleFile.caseTimers! }

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        bundleFile = try ReferenceLoader.decode(try Data(contentsOf: url))
    }

    private func adult(_ kg: Double? = 90) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = kg
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

    private func answer(_ g: String, _ p: String, _ v: String? = nil, allergy: Bool = false, mrsa: Bool = false) -> ProphylaxisAnswer {
        ProphylaxisEngine.answer(input(g, p, v, allergy: allergy, mrsa: mrsa), record: adult(), data: d, timers: t)
    }

    private func caseWith(_ planned: [PlannedProcedure]) -> PatientRecord {
        var r = adult()
        r.setProcedures(planned)
        return r
    }

    private func planned(_ id: String) throws -> PlannedProcedure {
        PlannedProcedure(try XCTUnwrap(ProcedureCatalog.byID(id), id))
    }

    // MARK: - The flag in the data

    func testTheFlagDecodesWhenThereIsOneAndOlderDataHasNone() throws {
        let with = try JSONDecoder().decode(ProphylaxisResult.self, from: Data(#"{"text":"Cefazolin","kind":"text","notes":["a"],"flag":"F"}"#.utf8))
        XCTAssertEqual(with.flag, "F")
        let old = try JSONDecoder().decode(ProphylaxisResult.self, from: Data(#"{"text":"Cefazolin","kind":"text","notes":["a"]}"#.utf8))
        XCTAssertNil(old.flag)
        // It survives a round trip.
        let again = try JSONDecoder().decode(ProphylaxisResult.self, from: try JSONEncoder().encode(with))
        XCTAssertEqual(again, with)
        XCTAssertEqual(again.flag, "F")
    }

    func testAFileWithoutTheFlagStillDecodesAndAnswers() throws {
        // An installed app that fetches an older reference.json: no "flag" anywhere. Nothing fails; there is just no caution line.
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        func stripped(_ any: Any) -> Any {
            if let dict = any as? [String: Any] {
                var out: [String: Any] = [:]
                for (k, v) in dict where k != "flag" { out[k] = stripped(v) }
                return out
            }
            if let arr = any as? [Any] { return arr.map { stripped($0) } }
            return any
        }
        obj["prophylaxis"] = stripped(try XCTUnwrap(obj["prophylaxis"]))
        let older = try ReferenceLoader.decode(try JSONSerialization.data(withJSONObject: obj))
        let od = try XCTUnwrap(older.prophylaxis)
        for g in od.groups { for p in g.procedures { for v in p.variants {
            XCTAssertNil(v.recommended?.flag, p.id)
            XCTAssertNil(v.allergy?.flag, p.id)
        } } }
        var i = ProphylaxisInput()
        i.chooseGroup("cardiac", data: od)
        i.chooseProcedure("x-valve-replacement-surgical-avr-mvr-t", data: od)
        let a = ProphylaxisEngine.answer(i, record: adult(), data: od, timers: t)
        XCTAssertEqual(a.state, .regimens)
        XCTAssertNil(a.flag)
        XCTAssertEqual(a.notes, [Self.notNamed], "the sentence is an ordinary note when the file has no flag: behind the info link")
    }

    func testEveryResultWhoseNotesStartWithTheNotNamedSentenceHasItAsFlagAndViceVersa() {
        var flagged = 0
        var plain = 0
        for g in d.groups { for p in g.procedures { for v in p.variants {
            for res in [v.recommended, v.allergy].compactMap({ $0 }) {
                let starts = res.notes.first == Self.notNamed
                XCTAssertEqual(res.flag != nil, starts, "\(g.id)/\(p.id)/\(v.id)")
                if let flag = res.flag {
                    XCTAssertEqual(flag, Self.notNamed, "\(g.id)/\(p.id)/\(v.id)")
                    XCTAssertEqual(res.notes.filter { $0 == Self.notNamed }.count, 1, "the sentence is in the notes once: \(p.id)")
                    flagged += 1
                } else {
                    XCTAssertFalse(res.notes.contains(Self.notNamed), "\(g.id)/\(p.id)/\(v.id)")
                    plain += 1
                }
            }
        } } }
        XCTAssertGreaterThan(flagged, 100)
        XCTAssertGreaterThan(plain, 50)
    }

    func testEveryGroupEndsWithOperationNotListedAsANoRowText() throws {
        XCTAssertEqual(ProphylaxisEngine.notListedID, "not-listed")
        for g in d.groups {
            let last = try XCTUnwrap(g.procedures.last, g.id)
            XCTAssertEqual(last.id, "not-listed", g.id)
            XCTAssertEqual(last.name, "Operation not listed", g.id)
            XCTAssertEqual(g.procedures.filter { $0.id == "not-listed" }.count, 1, g.id)
            XCTAssertFalse(last.asks, "it never asks: \(g.id)")
            XCTAssertNil(last.question, g.id)
            XCTAssertTrue((last.catalog ?? []).isEmpty, "no operation of the catalog opens it by name: \(g.id)")
            let v = try XCTUnwrap(last.variants.first, g.id)
            XCTAssertEqual(last.variants.count, 1, g.id)
            let text = try XCTUnwrap(v.outside, "a no-row text: \(g.id)")
            XCTAssertFalse(text.isEmpty, g.id)
            XCTAssertNil(v.recommended, g.id)
            XCTAssertNil(v.allergy, g.id)
            XCTAssertNil(v.table, g.id)
            // It answers as a no-row text, with or without the allergy and MRSA answers, and shows no agent and no Start.
            for allergy in [false, true] {
                let a = answer(g.id, "not-listed", allergy: allergy, mrsa: true)
                XCTAssertEqual(a.state, .outside, g.id)
                XCTAssertEqual(a.body, text, g.id)
                XCTAssertEqual(a.title, ProphylaxisEngine.outsideTitle, g.id)
                XCTAssertTrue(a.allLines.isEmpty, g.id)
                XCTAssertNil(a.mrsa, g.id)
                XCTAssertNil(a.flag, g.id)
                XCTAssertNil(a.evidence, g.id)
            }
        }
    }

    // MARK: - The result: the flag, and the notes behind the info link

    func testAReadingRowShowsItsFlagAndKeepsTheAgentsOfTheRowItBelongsWith() throws {
        let valve = answer("cardiac", "x-valve-replacement-surgical-avr-mvr-t")
        XCTAssertEqual(valve.state, .regimens)
        XCTAssertEqual(valve.flag, Self.notNamed)
        XCTAssertEqual(valve.evidence, "Evidence A")
        XCTAssertEqual(valve.allLines.map(\.agent), answer("cardiac", "cabg").allLines.map(\.agent))
        XCTAssertTrue(valve.notes.isEmpty, "the flag sentence was the only note: nothing moved behind the info link")
        XCTAssertFalse(valve.info.contains(Self.notNamed), "the flag sentence is the caution line, not repeated in the info")
        let alt = answer("cardiac", "x-valve-replacement-surgical-avr-mvr-t", allergy: true)
        XCTAssertEqual(alt.flag, Self.notNamed, "the alternative is the reading too")
        XCTAssertEqual(Set(alt.allLines.map(\.agent)), ["clindamycin", "vancomycin"])
        XCTAssertFalse(alt.info.contains(Self.notNamed))
        // A row of the guideline itself has no flag.
        XCTAssertNil(answer("cardiac", "cabg").flag)
        XCTAssertNil(answer("cardiac", "valve-repair").flag)
    }

    func testAFlaggedResultWithOtherNotesListsThemFirstInTheInfoWithoutTheFlagSentence() throws {
        // Flag plus two notes, no prophylaxis recommended.
        let none = answer("orthopedic", "x-ganglion-foot-neuroma-plantar-fascia")
        XCTAssertEqual(none.state, .none)
        XCTAssertEqual(none.flag, Self.notNamed)
        let res = try XCTUnwrap(d.group("orthopedic")?.procedure("x-ganglion-foot-neuroma-plantar-fascia")?.variants.first?.recommended)
        XCTAssertEqual(res.notes.count, 3)
        XCTAssertEqual(none.notes, Array(res.notes.dropFirst()))
        XCTAssertEqual(Array(none.info.prefix(2)), none.notes)
        XCTAssertFalse(none.info.contains(Self.notNamed))
        XCTAssertFalse(none.notes.contains(Self.notNamed))
        // The same on agents.
        // Nov 23 check: the pancreas-after-kidney row was removed, so this uses the new heart retransplant row: the flag and two other
        // notes on agents.
        let reHeart = answer("transplant", "x-heart-retransplant")
        XCTAssertEqual(reHeart.state, .regimens)
        XCTAssertEqual(reHeart.flag, Self.notNamed)
        XCTAssertEqual(reHeart.notes.count, 2)
        XCTAssertEqual(Array(reHeart.info.prefix(2)), reHeart.notes)
        XCTAssertFalse(reHeart.info.contains(Self.notNamed))
        // A guideline row's own notes move too (no flag), and the one-note and many-notes words differ.
        let pancreas = answer("transplant", "pancreas")
        XCTAssertNil(pancreas.flag)
        XCTAssertEqual(pancreas.notes.count, 2)
        XCTAssertEqual(Array(pancreas.info.prefix(2)), pancreas.notes)
        XCTAssertEqual(answer("vascular", "aneurysm").notes.count, 1)
        // Without notes, the info begins as before.
        let cabg = answer("cardiac", "cabg")
        XCTAssertTrue(cabg.notes.isEmpty)
        XCTAssertEqual(cabg.info.first, d.info.evidence)
    }

    func testTextOnlyAndNoProphylaxisResultsKeepTheirTextVisible() throws {
        // The ophthalmic reading rows answer with the cell's text; the flag is the caution line and the cell is the body.
        let oil = answer("ophthalmic", "x-silicone-oil-removal")
        XCTAssertEqual(oil.state, .text)
        XCTAssertEqual(oil.flag, Self.notNamed)
        XCTAssertEqual(oil.body, d.group("ophthalmic")?.procedure("x-silicone-oil-removal")?.variants.first?.recommended?.text)
        XCTAssertTrue(oil.allLines.isEmpty)
        // Nov 23 check: the row now carries two guideline notes besides the flag (it had only the flag sentence): they are behind the
        // info link, and the flag sentence is not one of them.
        let oilRes = try XCTUnwrap(d.group("ophthalmic")?.procedure("x-silicone-oil-removal")?.variants.first?.recommended)
        XCTAssertEqual(oilRes.notes.count, 3)
        XCTAssertEqual(oil.notes, Array(oilRes.notes.dropFirst()))
        XCTAssertFalse(oil.notes.contains(Self.notNamed))
        XCTAssertEqual(Array(oil.info.prefix(2)), oil.notes)
        let oilAlt = answer("ophthalmic", "x-silicone-oil-removal", allergy: true)
        XCTAssertEqual(oilAlt.state, .text)
        XCTAssertEqual(oilAlt.body, "No alternative agent listed")
        XCTAssertEqual(oilAlt.flag, Self.notNamed)
        XCTAssertEqual(oilAlt.notes.count, 1, "the note that says what the cell means moved behind the info link")
        XCTAssertFalse(oilAlt.info.contains(Self.notNamed))
        // No prophylaxis recommended keeps its headline.
        let thyroid = answer("headneck", "x-parathyroidectomy-central-neck-disse")
        XCTAssertEqual(thyroid.state, .none)
        XCTAssertEqual(thyroid.body, "No prophylaxis recommended")
        XCTAssertEqual(thyroid.flag, Self.notNamed)
    }

    func testEveryResultShowsItsFlagAndItsNotesOnceAndInOrder() throws {
        var checked = 0
        for g in d.groups { for p in g.procedures { for v in p.variants where v.outside == nil {
            for allergy in [false, true] {
                guard let res = allergy ? v.allergy : v.recommended else { continue }
                let a = answer(g.id, p.id, v.id, allergy: allergy)
                let label = "\(g.id)/\(p.id)/\(v.id)/\(allergy ? "allergy" : "recommended")"
                XCTAssertEqual(a.flag, res.flag, label)
                let moved = res.notes.filter { $0 != res.flag }
                XCTAssertEqual(a.notes, moved, label)
                XCTAssertEqual(Array(a.info.prefix(a.notes.count)), a.notes, "\(label): the notes come first")
                XCTAssertEqual(Set(a.info).count, a.info.count, "\(label): no paragraph twice")
                if let flag = res.flag { XCTAssertFalse(a.info.contains(flag), label) }
                checked += 1
            }
        } } }
        XCTAssertGreaterThan(checked, 200)
    }

    func testTheNotesLinkAndTheSheetsHeadings() {
        XCTAssertEqual(ProphylaxisEngine.notesLinkText(1), "1 guideline note")
        XCTAssertEqual(ProphylaxisEngine.notesLinkText(2), "2 guideline notes")
        XCTAssertEqual(ProphylaxisEngine.notesLinkText(5), "5 guideline notes")
        let a = answer("transplant", "pancreas")
        let c = ProphylaxisInfoContent(id: "result", title: a.title, paragraphs: a.info, noteCount: a.notes.count)
        XCTAssertEqual(c.heading(at: 0), "Guideline notes")
        XCTAssertNil(c.heading(at: 1))
        XCTAssertEqual(c.heading(at: 2), "About this result")
        XCTAssertNil(c.heading(at: 3))
        XCTAssertGreaterThan(a.info.count, a.notes.count, "there is more behind the link than the notes")
        // No notes: no headings, as the other sheets.
        let plain = ProphylaxisInfoContent(id: "x", title: "t", paragraphs: ["a", "b"])
        XCTAssertNil(plain.heading(at: 0))
        XCTAssertNil(plain.heading(at: 1))
        // Only notes: the second heading has nothing to stand over.
        let only = ProphylaxisInfoContent(id: "x", title: "t", paragraphs: ["a", "b"], noteCount: 2)
        XCTAssertEqual(only.heading(at: 0), "Guideline notes")
        XCTAssertNil(only.heading(at: 2))
    }

    // MARK: - Carotid endarterectomy

    func testCarotidAsksAboutAPatchOrGraftAndBothAnswersBehave() throws {
        let p = try XCTUnwrap(d.group("vascular")?.procedure("carotid"))
        XCTAssertEqual(p.name, "Carotid endarterectomy")
        XCTAssertEqual(p.question, "Prosthetic patch or graft?")
        XCTAssertEqual(p.variants.map(\.id), ["patch", "none"])
        XCTAssertEqual(p.variants.map(\.label), ["Patch or graft", "No patch or graft"])
        let asking = answer("vascular", "carotid")
        XCTAssertEqual(asking.state, .question)
        XCTAssertEqual(asking.question, "Prosthetic patch or graft?")
        XCTAssertTrue(asking.allLines.isEmpty)

        // Patch or graft: the vascular agents, no evidence grade (the note says why), and no flag: the guideline's own text names it.
        let patch = answer("vascular", "carotid", "patch")
        XCTAssertEqual(patch.state, .regimens)
        XCTAssertEqual(patch.title, "Recommended")
        XCTAssertNil(patch.evidence)
        XCTAssertNil(patch.flag)
        XCTAssertEqual(patch.allLines.map(\.agent), ["cefazolin"])
        XCTAssertEqual(patch.notes.count, 1)
        // Nov 23 check: the sentence is now "Periop Signal note: no evidence grade is shown for that reason." (it began "No evidence").
        XCTAssertTrue(patch.notes[0].contains("Periop Signal note: no evidence grade is shown for that reason."), patch.notes[0])
        XCTAssertEqual(patch.info.first, patch.notes[0])
        let alt = answer("vascular", "carotid", "patch", allergy: true)
        XCTAssertEqual(alt.state, .regimens)
        XCTAssertNil(alt.evidence)
        XCTAssertEqual(Set(alt.allLines.map(\.agent)), ["clindamycin", "vancomycin"])
        for s in d.info.star { XCTAssertTrue(alt.info.contains(s), "the asterisk's explanation is behind the info link") }
        // The other answers of the vascular group keep their grade.
        XCTAssertEqual(answer("vascular", "vascular").evidence, "Evidence A")

        // No patch or graft: a no-row text, whatever the allergy.
        for allergy in [false, true] {
            let none = answer("vascular", "carotid", "none", allergy: allergy, mrsa: true)
            XCTAssertEqual(none.state, .outside)
            // Nov 23 check: "has no antibiotic row for this" (it read "has no row for this").
            XCTAssertTrue(none.body.hasPrefix("The guideline's table has no antibiotic row for this"), none.body)
            XCTAssertNil(none.evidence)
            XCTAssertTrue(none.allLines.isEmpty)
            XCTAssertNil(none.mrsa)
        }

        // A planned carotid endarterectomy opens the row and leaves the question to the user.
        let pre = ProphylaxisEngine.prefill(record: caseWith([try planned("cea")]), data: d)
        XCTAssertEqual(pre.group, "vascular")
        XCTAssertEqual(pre.procedure, "carotid")
        var i = ProphylaxisInput()
        i.apply(pre, data: d)
        XCTAssertNil(i.variant)
        XCTAssertEqual(ProphylaxisEngine.answer(i, record: adult(), data: d, timers: t).state, .question)
    }

    // MARK: - Rows that answer with text

    func testRowsThatOnlyShowTextShowItAndNoAgent() throws {
        let tavr = answer("cardiac", "x-tavr-and-other-transcatheter-valve-p", allergy: true, mrsa: true)
        XCTAssertEqual(tavr.state, .outside)
        XCTAssertTrue(tavr.body.hasPrefix("Periop Signal note: the 2013 guideline does not address transcatheter valve procedures."), tavr.body)
        XCTAssertTrue(tavr.allLines.isEmpty)
        XCTAssertNil(tavr.mrsa)
        XCTAssertNil(tavr.flag)
        let stent = answer("vascular", "x-endovascular-stenting-and-stent-graf")
        XCTAssertEqual(stent.state, .outside)
        XCTAssertFalse(stent.body.isEmpty)
        XCTAssertTrue(stent.allLines.isEmpty)
        for id in ["tavr", "tavr-chest", "tavr-alternative", "teer", "tmvr", "ttvr", "tpvr"] {
            let p = ProphylaxisEngine.prefill(record: caseWith([try planned(id)]), data: d)
            XCTAssertEqual(p.group, "cardiac", id)
            XCTAssertEqual(p.procedure, "x-tavr-and-other-transcatheter-valve-p", id)
        }
    }

    // MARK: - The ophthalmic group has several rows

    func testOphthalmicHasSeveralRowsAndNoneIsChosenForTheUser() throws {
        let g = try XCTUnwrap(d.group("ophthalmic"))
        XCTAssertGreaterThan(g.procedures.count, 1)
        var i = ProphylaxisInput()
        i.chooseGroup("ophthalmic", data: d)
        XCTAssertNil(i.procedure)
        XCTAssertNil(answer("ophthalmic", "ophthalmic").flag, "the first ophthalmic row is the guideline's own")
        XCTAssertEqual(ProphylaxisEngine.prefill(record: caseWith([try planned("cataract")]), data: d).procedure, "ophthalmic")
        XCTAssertEqual(ProphylaxisEngine.prefill(record: caseWith([try planned("silicone-oil-removal")]), data: d).procedure, "x-silicone-oil-removal")
    }

    // MARK: - The prefill from a case

    func testAPlannedOperationNoRowNamesOpensOperationNotListed() throws {
        let r = caseWith([try planned("revision-tka")])
        let p = ProphylaxisEngine.prefill(record: r, data: d)
        XCTAssertEqual(p.group, "orthopedic")
        XCTAssertEqual(p.procedure, "not-listed")
        XCTAssertEqual(p.procedureCaption, "From the case: " + r.procedures[0].title)
        XCTAssertFalse(p.isEmpty)
        var i = ProphylaxisInput()
        i.apply(p, data: d)
        XCTAssertEqual(i.group, "orthopedic")
        XCTAssertEqual(i.procedure, "not-listed")
        XCTAssertEqual(i.summary(d), (d.group("orthopedic")?.chip ?? "") + " · Operation not listed")
        let a = ProphylaxisEngine.answer(i, record: adult(), data: d, timers: t)
        XCTAssertEqual(a.state, .outside)
        XCTAssertTrue(a.allLines.isEmpty)
    }

    func testAnOperationThatOpensARealRowNeverOpensOperationNotListed() throws {
        let p = ProphylaxisEngine.prefill(record: caseWith([try planned("femoral-nail")]), data: d)
        XCTAssertEqual(p.group, "orthopedic")
        XCTAssertEqual(p.procedure, "x-femoral-intramedullary-nail")
        // The catalogued operation wins over an earlier one that only matches a specialty, in either order of the two.
        let tha = try planned("tha")
        let revision = try planned("revision-tka")
        let first = ProphylaxisEngine.prefill(record: caseWith([revision, tha]), data: d)
        XCTAssertEqual(first.procedure, "joint")
        let second = ProphylaxisEngine.prefill(record: caseWith([tha, revision]), data: d)
        XCTAssertEqual(second.procedure, "joint")
        XCTAssertEqual(first.procedureCaption, "From the case: " + tha.title)
    }

    func testWhenNoGroupMatchesNothingIsSelectedAsToday() throws {
        for id in ["colonoscopy", "hartmann", "ivor-lewis"] {
            let p = ProphylaxisEngine.prefill(record: caseWith([try planned(id)]), data: d)
            XCTAssertNil(p.group, id)
            XCTAssertNil(p.procedure, id)
            XCTAssertNil(p.procedureCaption, id)
        }
        // A group of the file without the row (an older shape): the group alone, as before.
        var dd = d
        dd.groups = [ProphylaxisGroup(id: "g", name: "G", specialties: ["Orthopedics"], procedures: [
            ProphylaxisProcedure(id: "p", name: "P", variants: [ProphylaxisVariant(id: "only", outside: "x")]),
            ProphylaxisProcedure(id: "q", name: "Q", variants: [ProphylaxisVariant(id: "only", outside: "y")]),
        ])]
        let p = ProphylaxisEngine.prefill(record: caseWith([try planned("revision-tka")]), data: dd)
        XCTAssertEqual(p.group, "g")
        XCTAssertNil(p.procedure)
        XCTAssertNotNil(p.procedureCaption)
    }

    func testTheOperationsThatOpenedNoRowBeforeNowOpenOne() throws {
        // Previously unmapped (they selected the group only or nothing), and the few that moved to a labelled row.
        let ids = ["avr", "mvr", "bentall", "ascending-aorta", "tavr", "femoral-nail", "bariatric-revision", "hartmann-reversal", "tatme",
                   "proctocolectomy", "mvd", "acoustic-neuroma", "cavernoma", "intraventricular-tumor", "epilepsy-surgery", "cystoscopy"]
        for id in ids {
            let want = d.groups.flatMap { g in g.procedures.filter { ($0.catalog ?? []).contains(id) }.map { (g.id, $0.id) } }
            XCTAssertEqual(want.count, 1, id)
            let p = ProphylaxisEngine.prefill(record: caseWith([try planned(id)]), data: d)
            XCTAssertEqual(p.group, want.first?.0, id)
            XCTAssertEqual(p.procedure, want.first?.1, id)
            XCTAssertNotEqual(p.procedure, "not-listed", id)
            XCTAssertTrue(p.procedure?.hasPrefix("x-") ?? false, "a row added on Nov 23: \(id)")
        }
    }

    func testTheRowsOfTheNov23CheckAreInTheData() throws {
        // Nov 23 check: 157 rows. Seven rows were removed because their operations belong with a row the guideline names (the catalog
        // ids they listed moved to that row), one retransplant row was added, and some planned operations that opened no row now open one.
        XCTAssertEqual(d.groups.flatMap(\.procedures).count, 157)
        let removed: [(group: String, row: String)] = [
            ("vascular", "x-hero-graft-placement-dialysis-access"), ("neurosurgery", "x-intrathecal-pump-for-pain-or-cancer"),
            ("ophthalmic", "x-cyclophotocoagulation-or-angle-surge"), ("orthopedic", "x-proximal-humerus-pinning-elbow-fract"),
            ("plastic", "x-breast-cancer-simple-mastectomy-onco"), ("plastic", "x-lumpectomy-with-sentinel-node-biopsy"),
            ("transplant", "x-pancreas-after-kidney-transplant"),
        ]
        for r in removed { XCTAssertNil(d.group(r.group)?.procedure(r.row), r.row) }
        let opens: [(id: String, group: String, row: String)] = [
            ("hero-graft", "vascular", "dialysis-graft"), ("mi-glaucoma", "ophthalmic", "ophthalmic"),
            ("simple-mastectomy", "plastic", "breast-cancer"), ("lumpectomy-slnb", "plastic", "breast-cancer"),
            ("elbow-orif-complex", "orthopedic", "fixation"), ("wrist-arthroscopy", "orthopedic", "clean"),
            ("heart-retransplant", "transplant", "x-heart-retransplant"),
            ("device-pocket", "cardiac", "x-pacemaker-or-icd-lead-pocket-revisio"),
            ("tvp-lead-repositioning", "cardiac", "x-pacemaker-or-icd-lead-pocket-revisio"),
            ("moyamoya", "neurosurgery", "x-craniotomy-cerebral-revascularizatio"),
            ("cleft-lip", "plastic", "x-cleft-lip-and-palate-repair"), ("cleft-palate", "plastic", "x-cleft-lip-and-palate-repair"),
        ]
        for o in opens {
            let p = ProphylaxisEngine.prefill(record: caseWith([try planned(o.id)]), data: d)
            XCTAssertEqual(p.group, o.group, o.id)
            XCTAssertEqual(p.procedure, o.row, o.id)
        }
        // The wrist and ankle row asks whether it is a fusion or a joint replacement.
        let wrist = try XCTUnwrap(d.group("orthopedic")?.procedure("x-wrist-fusion-and-ankle-fusion-or-rep"))
        XCTAssertEqual(wrist.question, "Fusion or joint replacement?")
        XCTAssertEqual(wrist.variants.map(\.id), ["fusion", "replacement"])
        // A row the check took the label from keeps its agents and carries the sentence as an ordinary note.
        let nail = try XCTUnwrap(d.group("orthopedic")?.procedure("x-femoral-intramedullary-nail")?.variants.first?.recommended)
        XCTAssertNil(nail.flag)
        XCTAssertTrue(nail.notes.first?.hasPrefix("Periop Signal note: ") == true, "\(nail.notes)")
        XCTAssertNil(answer("orthopedic", "x-femoral-intramedullary-nail").flag)
    }

    func testEveryOperationOfTheCatalogOpensItsRowThenItsGroupsNotListedRowThenNothing() throws {
        var rows = 0
        var notListed = 0
        var nothing = 0
        for c in ProcedureCatalog.all {
            let p = ProphylaxisEngine.prefill(record: caseWith([PlannedProcedure(c)]), data: d)
            var wantGroup: String?
            var wantRow: String?
            outer: for g in d.groups {
                for pr in g.procedures where (pr.catalog ?? []).contains(c.id) {
                    wantGroup = g.id; wantRow = pr.id
                    break outer
                }
            }
            if wantRow != nil {
                rows += 1
            } else if let g = d.groups.first(where: { $0.specialties.contains(c.specialty) }) {
                wantGroup = g.id; wantRow = "not-listed"
                notListed += 1
            } else {
                nothing += 1
            }
            XCTAssertEqual(p.group, wantGroup, c.id)
            XCTAssertEqual(p.procedure, wantRow, c.id)
        }
        XCTAssertGreaterThan(rows, 300)
        XCTAssertGreaterThan(notListed, 20)
        XCTAssertGreaterThan(nothing, 100)
    }
}
