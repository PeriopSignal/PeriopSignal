import XCTest
@testable import PeriopSignal

/// 1.12 follow-up, helper M (Ben, Nov 12): heparin-induced thrombocytopenia (HIT) and heparin resistance on the Heme & Oncology
/// page with no ASA class; a heading typed "pmh" read as "PMH"; premature ventricular contractions typed in free text, in any
/// letter case, filed as Other arrhythmia with "PVCs" as its detail.
final class M112Tests: XCTestCase {
    /// 12 November 2026, 08:00 on the device's clock.
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 8))! }

    private func note(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func quick(_ s: String, tab: QuickAddTab = .preop) -> QuickAddReading { QuickAdd.read(s, record: PatientRecord(), tab: tab, now: now) }
    private func noteIDs(_ s: String) -> [String] { note(s).findings.map(\.id) }
    private func quickIDs(_ s: String) -> [String] { quick(s).findings.map(\.id) }

    /// The record after the note reader's findings are filed.
    private func applied(_ s: String) -> PatientRecord {
        var r = PatientRecord()
        PatientNote.apply(note(s).findings.map(\.change), to: &r)
        return r
    }

    private func adult(_ problems: Set<String>) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 62
        r.problems = problems
        return r
    }

    private func heme() throws -> PatientSystem { try XCTUnwrap(PatientCatalog.systems.first { $0.id == "heme" }) }

    /// Both readers file the item for each line.
    private func assertFiles(_ id: String, _ lines: [String], file: StaticString = #filePath, line: UInt = #line) {
        for s in lines {
            XCTAssertTrue(noteIDs(s).contains("problem:" + id), "note reader: " + s + " → " + noteIDs(s).joined(separator: ", "), file: file, line: line)
            XCTAssertTrue(quickIDs(s).contains("problem:" + id), "bar: " + s + " → " + quickIDs(s).joined(separator: ", "), file: file, line: line)
        }
    }

    /// Neither reader files the item for any line.
    private func assertFilesNot(_ id: String, _ lines: [String], file: StaticString = #filePath, line: UInt = #line) {
        for s in lines {
            XCTAssertFalse(noteIDs(s).contains("problem:" + id), "note reader: " + s + " → " + noteIDs(s).joined(separator: ", "), file: file, line: line)
            XCTAssertFalse(quickIDs(s).contains("problem:" + id), "bar: " + s + " → " + quickIDs(s).joined(separator: ", "), file: file, line: line)
        }
    }

    // MARK: 1. The two problems

    func testBothAreHemeItemsBesideThrombocytopeniaAndAnticoagulation() throws {
        let ids = try heme().problems.map(\.id)
        XCTAssertEqual(ids.firstIndex(of: "hit"), (ids.firstIndex(of: "thrombocytopenia") ?? -9) + 1, "beside Thrombocytopenia")
        XCTAssertEqual(ids.firstIndex(of: "heparin-resistance"), (ids.firstIndex(of: "anticoagulation") ?? -9) + 1, "beside On anticoagulation")
        XCTAssertEqual(PatientCatalog.problem("hit")?.label, "Heparin-induced thrombocytopenia (HIT)")
        XCTAssertEqual(PatientCatalog.problem("heparin-resistance")?.label, "Heparin resistance")
        XCTAssertEqual(ids.last, "malignancy", "Malignancy is still the last item")
        XCTAssertEqual(PatientCatalog.system(of: "hit")?.id, "heme")
        XCTAssertEqual(PatientCatalog.system(of: "heparin-resistance")?.id, "heme")
    }

    func testNeitherHasAClassACautionOrARiskItem() {
        for id in ["hit", "heparin-resistance"] {
            let p = PatientCatalog.problem(id)
            XCTAssertNil(p?.asa, id)
            XCTAssertNil(p?.asaDef, id)
            XCTAssertNil(p?.peds, id)
            XCTAssertNil(p?.rcri, id)
            XCTAssertNil(p?.stopBang, id)
            XCTAssertNil(p?.note, id)
            XCTAssertTrue(PatientRules.asaNoClass.contains(id), id + " is in the no-class list")
            XCTAssertNil(PatientRules.asaSuggestion(adult([id]))?.level, id + " suggests no class")
            var child = adult([id])
            child.ageYears = 8
            XCTAssertNil(PatientRules.asaSuggestion(child)?.level, id + ": none for a child either")
            XCTAssertTrue(PatientWarnings.tags(id, adult([id])).isEmpty, id + " raises no warning")
            XCTAssertTrue(PatientWarnings.lines(adult([id])).isEmpty, id + " adds no warning line to the summaries")
        }
        XCTAssertEqual(PatientRules.asaSuggestion(adult(["htn", "hit", "heparin-resistance"]))?.level, 2, "only hypertension counts")
        XCTAssertEqual(PatientRules.asaSuggestion(adult(["htn", "hit", "heparin-resistance"]))?.reasons.map(\.finding), ["Hypertension"])
    }

    func testTheNoClassListIsTheTenOfNov12AndTheTwo() {
        XCTAssertEqual(PatientRules.asaNoClass, ["visual-impairment", "bph", "gastric-bypass", "dysphagia", "full-stomach", "declines-blood",
                                                 "mdro", "isolation", "uterine-rupture-past", "fracture", "hit", "heparin-resistance"])
    }

    func testEachIsAnItemOnThePageThatSetsOnlyItself() throws {
        let page = try XCTUnwrap(HistorySections.sections("heme"))
        let order = page.map(\.id)
        XCTAssertEqual(order.firstIndex(of: "hit"), (order.firstIndex(of: "thrombocytopenia") ?? -9) + 1)
        XCTAssertEqual(order.firstIndex(of: "heparin-resistance"), (order.firstIndex(of: "anticoagulation") ?? -9) + 1)
        for (id, title) in [("hit", "Heparin-induced thrombocytopenia (HIT)"), ("heparin-resistance", "Heparin resistance")] {
            let item = try XCTUnwrap(page.first { $0.id == id })
            XCTAssertEqual(item.title, title)
            XCTAssertEqual(item.base, id)
            XCTAssertEqual(item.members, [id])
            var r = PatientRecord()
            XCTAssertFalse(HistorySections.isSelected(item, system: "heme", r))
            HistorySections.select(item, &r)
            XCTAssertEqual(r.problems, [id], "choosing it files that one item only")
            XCTAssertTrue(HistorySections.isSelected(item, system: "heme", r))
            XCTAssertFalse(r.problems.contains("thrombocytopenia"), "not the Thrombocytopenia item")
            HistorySections.clear(item, system: "heme", &r)
            XCTAssertTrue(r.problems.isEmpty)
            XCTAssertFalse(HistorySections.isSelected(item, system: "heme", r))
        }
        // Thrombocytopenia chosen leaves the HIT item alone, and the reverse.
        var r = adult(["thrombocytopenia"])
        XCTAssertFalse(HistorySections.isSelected(try XCTUnwrap(page.first { $0.id == "hit" }), system: "heme", r))
        r.problems = ["hit"]
        XCTAssertFalse(HistorySections.isSelected(try XCTUnwrap(page.first { $0.id == "thrombocytopenia" }), system: "heme", r))
    }

    func testTheSummariesSayHITAndHeparinResistance() throws {
        let both = adult(["hit", "heparin-resistance"])
        XCTAssertEqual(HistorySections.hemeItems(both), ["HIT", "heparin resistance"])
        XCTAssertEqual(HistorySections.items(try heme(), both), ["HIT", "heparin resistance"])
        XCTAssertEqual(HistorySections.hemeItems(adult(["hit"])), ["HIT"])
        XCTAssertEqual(HistorySections.hemeItems(adult(["heparin-resistance"])), ["heparin resistance"])
        XCTAssertEqual(HistorySections.hemeItems(adult(["thrombocytopenia", "hit", "anticoagulation", "heparin-resistance"])),
                       ["thrombocytopenia", "HIT", "on anticoagulation", "heparin resistance"], "in the page's order")
        XCTAssertEqual(HistorySections.hemeItems(adult(["thrombocytopenia"])), ["thrombocytopenia"], "no HIT words without the item")
        // The Preprocedure Summary and the handoff: the PMH line, no system heading.
        var r = both
        r.asaClass = 3
        for blocks in [PatientBriefs.preop(r), PatientBriefs.handoff(r)] {
            let pmh = try XCTUnwrap(blocks.first { $0.key == "pmh" })
            XCTAssertTrue(pmh.text.contains("HIT; heparin resistance"), pmh.text)
        }
        let line = PatientSummary.historyLines(both).first { $0.label == "Heme & Oncology" }
        XCTAssertEqual(line?.text, "HIT; heparin resistance")
    }

    // MARK: Typing: the item filed

    func testHITIsReadInCapitalsAndSpelledOut() {
        assertFiles("hit", ["HIT", "HITT", "h/o HIT", "HIT type II", "HIT type 2", "heparin-induced thrombocytopenia", "heparin induced thrombocytopenia (and thrombosis)",
                            "Heparin-Induced Thrombocytopenia", "HIT positive", "HIT antibody positive", "PMH: HTN, HIT", "history of HIT, avoid heparin",
                            "heparin-induced thrombocytopenia (HIT)", "HIT (heparin-induced thrombocytopenia)", "heparin-induced thrombocytopenia and thrombosis (HITT)"])
    }

    func testHITFilesOnlyItselfAndTheRestOfTheLineIsStillRead() {
        for s in ["HIT", "heparin-induced thrombocytopenia", "h/o HIT, avoid heparin"] {
            XCTAssertFalse(noteIDs(s).contains("problem:thrombocytopenia"), s)
            XCTAssertFalse(quickIDs(s).contains("problem:thrombocytopenia"), s)
            XCTAssertFalse(noteIDs(s).contains("flag:anticoagulant"), s + ": not a heparin the patient takes")
            XCTAssertFalse(noteIDs(s).contains("problem:anticoagulation"), s)
        }
        let r = applied("HIT")
        XCTAssertEqual(r.problems, ["hit"])
        XCTAssertEqual(applied("HIT, HTN, ITP").problems, ["hit", "htn", "thrombocytopenia"], "ITP is still thrombocytopenia")
        // The spelled-out form and its short form are one mention, with nothing left over.
        for s in ["heparin-induced thrombocytopenia (HIT)", "HIT (heparin-induced thrombocytopenia)", "heparin induced thrombocytopenia (and thrombosis)"] {
            XCTAssertEqual(note(s).findings.map(\.id), ["problem:hit"], s)
            XCTAssertEqual(note(s).other, "", s)
            XCTAssertEqual(quick(s).unread, "", s)
        }
    }

    func testHITInLowerCaseIsTheEnglishWord() {
        assertFilesNot("hit", ["hit by a car", "took a hit", "hit", "hitt", "Hit by a car", "hit the ground", "fell and hit her head", "hit and run"])
        XCTAssertTrue(noteIDs("hit by a car").filter { $0.hasPrefix("problem:") }.isEmpty)
    }

    func testHITGuards() {
        assertFilesNot("hit", ["HIT negative", "HIT neg", "HIT: negative", "HIT panel sent", "HIT panel pending", "HIT antibody negative", "HIT antibody pending",
                               "HIT PF4 negative", "r/o HIT", "rule out HIT", "no HIT", "no history of HIT", "denies HIT", "HIT ruled out", "HIT excluded",
                               "negative HIT", "possible HIT", "suspected HIT", "concern for HIT", "mother had HIT", "FHx: HIT", "family history of HIT",
                               "not heparin-induced thrombocytopenia", "heparin-induced thrombocytopenia ruled out", "negative for heparin-induced thrombocytopenia",
                               "was HIT by a car", "got HIT", "a HIT", "HIT BY A CAR", "HIT ON THE HEAD", "HIT protocol", "HIT precautions"])
    }

    func testHeparinResistanceIsReadAnyCase() {
        assertFiles("heparin-resistance", ["heparin resistance", "heparin resistant", "heparin-resistant", "Heparin resistance", "h/o heparin resistance",
                                           "HEPARIN RESISTANCE", "PMH: HTN, heparin resistance", "heparin resistance, needs antithrombin"])
        XCTAssertEqual(applied("heparin-resistant").problems, ["heparin-resistance"])
    }

    func testHeparinResistanceGuards() {
        assertFilesNot("heparin-resistance", ["not heparin resistant", "no heparin resistance", "denies heparin resistance", "heparin resistance negative",
                                              "possible heparin resistance", "concern for heparin resistance", "mother had heparin resistance",
                                              "on heparin gtt", "heparin infusion at 1200 units/h", "heparin 5000 units SQ", "heparin flush", "resistant to antibiotics"])
    }

    func testHeparinResistanceIsNotAHeparinTheyTake() {
        for s in ["heparin resistance", "heparin-resistant", "h/o heparin resistance"] {
            XCTAssertFalse(noteIDs(s).contains("flag:anticoagulant"), s)
            XCTAssertFalse(noteIDs(s).contains("problem:anticoagulation"), s)
            XCTAssertFalse(quickIDs(s).contains("flag:anticoagulant"), s)
            let r = applied(s)
            XCTAssertTrue(r.hx.anticoagulants.isEmpty, s)
            XCTAssertFalse(r.medFlags.contains("anticoagulant"), s)
            XCTAssertEqual(r.medications, "", s + ": no medication named")
        }
    }

    func testTheAnticoagulationReadersReadAsBefore() {
        // A heparin infusion or dose is still the anticoagulant, and heparin resistance beside it adds only itself.
        let gtt = applied("on heparin gtt")
        XCTAssertTrue(gtt.has("anticoagulation"))
        XCTAssertEqual(gtt.hx.anticoagulants["heparin"]?.intensity, "therapeutic")
        XCTAssertFalse(gtt.has("heparin-resistance"))
        XCTAssertFalse(gtt.has("hit"))
        let both = applied("on heparin gtt, heparin resistance")
        XCTAssertTrue(both.has("anticoagulation") && both.has("heparin-resistance"))
        XCTAssertEqual(both.hx.anticoagulants["heparin"]?.intensity, "therapeutic")
        XCTAssertTrue(applied("heparin 5000 units SQ q8h").medFlags.contains("anticoagulant"))
        XCTAssertTrue(applied("on warfarin").has("anticoagulation"))
        for s in ["HIT, avoid heparin", "allergic to heparin", "heparin flush"] { XCTAssertFalse(applied(s).has("anticoagulation"), s) }
    }

    func testHITAndHITTAreAbbreviationsInCapitalsOnly() {
        XCTAssertNotNil(MedAbbreviations.lookup("HIT"))
        XCTAssertNotNil(MedAbbreviations.lookup("HITT"))
        XCTAssertNil(MedAbbreviations.lookup("hit"))
        XCTAssertNil(MedAbbreviations.lookup("hitt"))
        XCTAssertNil(MedAbbreviations.lookup("Hit"))
        XCTAssertEqual(MedAbbreviations.lookup("HITT")?.meanings.first?.text, "heparin-induced thrombocytopenia and thrombosis")
        XCTAssertTrue(note("HITT").unknown.isEmpty, "HITT is no longer an unknown abbreviation")
        XCTAssertTrue(quick("HITT").unknown.isEmpty)
        XCTAssertTrue(MedAbbreviations.scan("hit by a car").allSatisfy { $0.key != "HIT" })
    }

    func testTheOldTestOfNov12IsTheBehaviourThatChanged() {
        // Until now "heparin-induced thrombocytopenia" filed nothing (PatientNote19Tests); it files the HIT item.
        XCTAssertEqual(noteIDs("heparin-induced thrombocytopenia").filter { $0.hasPrefix("problem:") }, ["problem:hit"])
    }

    // MARK: 2. "pmh" is the heading

    private func samePair(_ lower: String, _ capital: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(note(lower), note(capital), "note reader: " + lower + " vs " + capital, file: file, line: line)
        let a = quick(lower), b = quick(capital)
        XCTAssertEqual(a, b, "bar: " + lower + " vs " + capital, file: file, line: line)
        XCTAssertEqual(QuickAdd.chips(a, record: PatientRecord()).map(\.value), QuickAdd.chips(b, record: PatientRecord()).map(\.value),
                       "chips: " + lower, file: file, line: line)
    }

    func testPMHInAnyCaseGivesWhatTheCapitalFormGives() {
        samePair("pmh htn, dm2", "PMH htn, dm2")
        samePair("pmh: htn, dm2", "PMH: htn, dm2")
        samePair("Pmh htn", "PMH htn")
        samePair("pmhx: cad", "PMHx: cad")
        samePair("Pmhx: cad", "PMHx: cad")
        samePair("68M for lap chole, pmh htn dm2 osa", "68M for lap chole, PMH htn dm2 osa")
        samePair("68M for lap chole, Pmh htn dm2 osa", "68M for lap chole, PMH htn dm2 osa")
        samePair("pmh: htn, dm2, asymptomatic carotid stenosis", "PMH: htn, dm2, asymptomatic carotid stenosis")
    }

    func testTheItemsAfterTheHeadingAreFiledAsHistory() {
        for s in ["pmh htn, dm2", "pmh: htn, dm2", "Pmh htn, dm2", "pmhx: htn, dm2"] {
            let n = noteIDs(s), q = quickIDs(s)
            XCTAssertTrue(n.contains("problem:htn") && n.contains("problem:dm"), "note: " + s + " → " + n.joined(separator: ", "))
            XCTAssertTrue(q.contains("problem:htn") && q.contains("problem:dm"), "bar: " + s + " → " + q.joined(separator: ", "))
            XCTAssertTrue(note(s).unknown.isEmpty && quick(s).unknown.isEmpty, s + ": nothing to explain")
            XCTAssertTrue(quick(s).ambiguous.isEmpty, s)
            XCTAssertFalse(quick(s).unread.lowercased().contains("pmh"), s + ": " + quick(s).unread)
            XCTAssertFalse(note(s).other.lowercased().contains("pmh"), s + ": " + note(s).other)
        }
        // After a planned procedure in the same sentence, the note reader takes the rest of the sentence as the procedure's own words
        // (both spellings alike: "PMH htn dm2 osa" reads the hypertension and no more); the bar reads the history behind it.
        for s in ["68M for lap chole, pmh htn dm2 osa", "68M for lap chole, PMH htn dm2 osa"] {
            XCTAssertTrue(noteIDs(s).contains("problem:htn"), "note: " + s + " → " + noteIDs(s).joined(separator: ", "))
            XCTAssertTrue(quickIDs(s).contains("problem:htn"), "bar: " + s + " → " + quickIDs(s).joined(separator: ", "))
            XCTAssertTrue(quickIDs(s).contains("procedure") || quick(s).findings.contains { if case .procedure = $0.change { return true }; return false }, s)
        }
        // "68M for lap chole" is still the procedure, and the heading does not end up in it.
        let q = quick("68M for lap chole, pmh htn dm2 osa")
        for f in q.findings {
            if case .procedure = f.change { XCTAssertFalse(f.label.lowercased().contains("pmh"), f.label) }
        }
    }

    func testTheHistoryHeadingsAreKnownInAnyCase() {
        for k in ["PMH", "pmh", "Pmh", "pMH", "PMHx", "pmhx", "Pmhx", "PSH", "psh", "Psh", "PSHx", "pshx", "Pshx", "FHx", "fhx", "SHx", "shx", "HPI", "hpi", "ROS", "ros"] {
            XCTAssertNotNil(MedAbbreviations.lookup(k), k + " is a heading")
        }
        XCTAssertEqual(MedAbbreviations.lookup("pmh")?.meanings.first?.text, "past medical history")
        XCTAssertEqual(MedAbbreviations.lookup("Psh")?.meanings.first?.text, "past surgical history")
        XCTAssertFalse(MedAbbreviations.lookup("Pmh")?.reads ?? true, "a heading is understood as written, not read as a problem")
    }

    func testAWordThatMerelyContainsTheLettersIsNotAHeading() {
        for w in ["pmhotel", "campmhx", "Pshaw", "psha", "hypmh", "pmhh", "ppmh", "spsh"] {
            XCTAssertNil(MedAbbreviations.lookup(w), w)
            XCTAssertTrue(MedAbbreviations.scan(w + " htn").allSatisfy { $0.key != "PMH" && $0.key != "PSH" && $0.key != "PMHx" && $0.key != "PSHx" }, w)
        }
        // Names stay names: only the two headings were opened to any case.
        XCTAssertNil(MedAbbreviations.lookup("Tia"))
        XCTAssertNil(MedAbbreviations.lookup("Ross"))
        XCTAssertNil(MedAbbreviations.lookup("Ros"))
        XCTAssertNil(MedAbbreviations.lookup("Hpi"))
    }

    func testThePastSurgicalAndTheOtherHeadingsInAnyCase() {
        samePair("psh: appendectomy 2010", "PSH: appendectomy 2010")
        samePair("pshx: appendectomy 2010", "PSHx: appendectomy 2010")
        samePair("Psh appendectomy 2010", "PSH appendectomy 2010")
        samePair("fhx: htn", "FHx: htn")
        samePair("shx: former smoker", "SHx: former smoker")
        samePair("hpi: chest pain", "HPI: chest pain")
        samePair("ros: negative", "ROS: negative")
        XCTAssertEqual(applied("psh: appendectomy 2010").surgeries.count, 1)
        XCTAssertEqual(applied("pmh: htn. psh: appendectomy 2010").surgeries.count, 1, "a lower-case PMH ends the PSH section as PMH does")
        XCTAssertTrue(applied("pmh: htn. psh: appendectomy 2010").has("htn"))
    }

    // MARK: 3. PVCs typed in free text

    private func pvcChange(_ s: String) -> PatientNoteChange? { note(s).findings.first { $0.id == PatientNote.pvcFindingID }?.change }

    func testPVCsAreFiledAsOtherArrhythmiaWithPVCsAsTheDetail() {
        for s in ["PVC", "PVCs", "pvc", "pvcs", "Pvcs", "frequent PVCs", "occasional pvcs", "premature ventricular contractions", "premature ventricular complexes",
                  "premature ventricular beats", "Premature Ventricular Contractions", "h/o PVCs", "PMH: HTN, PVCs", "HTN, frequent PVCs on Holter"] {
            XCTAssertEqual(pvcChange(s), .problemNote("arrhythmia", "PVCs"), "note: " + s)
            XCTAssertEqual(quick(s).findings.first { $0.id == PatientNote.pvcFindingID }?.change, .problemNote("arrhythmia", "PVCs"), "bar: " + s)
            XCTAssertEqual(note(s).findings.first { $0.id == PatientNote.pvcFindingID }?.label, "Other arrhythmia (PVCs)", s)
            let r = applied(s)
            XCTAssertTrue(r.has("arrhythmia"), s)
            XCTAssertEqual(r.hx.arrhythmiaType, "PVCs", s)
            XCTAssertFalse(r.has("pvd"), s + ": not peripheral vascular disease")
        }
    }

    func testTheBarOffersItAsAChipAndFilesItOnTheArrhythmiaPage() throws {
        let q = quick("frequent pvcs")
        let chips = QuickAdd.chips(q, record: PatientRecord())
        let chip = try XCTUnwrap(chips.first { $0.findings.contains { $0.id == PatientNote.pvcFindingID } })
        XCTAssertEqual(chip.destination, "History")
        XCTAssertTrue(chip.value.contains("PVCs"), chip.value)
        XCTAssertEqual(chip.status, .new)
        var r = PatientRecord()
        PatientNote.apply(QuickAdd.changes(chips.filter(\.canAdd)), to: &r)
        XCTAssertTrue(r.has("arrhythmia"))
        XCTAssertEqual(r.hx.arrhythmiaType, "PVCs")
        XCTAssertEqual(HistorySections.cvItems(r, pshAlongside: false).first { $0.contains("arrhythmia") }, "other arrhythmia (PVCs)")
        // Recorded already: nothing to add.
        let again = QuickAdd.chips(quick("frequent pvcs"), record: r)
        XCTAssertEqual(again.first { $0.findings.contains { $0.id == PatientNote.pvcFindingID } }?.status, .recorded)
    }

    func testTypedTwiceTheDetailIsNotDoubled() {
        let r = applied("PVCs, frequent PVCs, premature ventricular contractions")
        XCTAssertEqual(r.hx.arrhythmiaType, "PVCs")
        var again = r
        PatientNote.apply(note("pvcs").findings.map(\.change), to: &again)
        PatientNote.apply(note("PVCs").findings.map(\.change), to: &again)
        XCTAssertEqual(again.hx.arrhythmiaType, "PVCs")
    }

    func testAnotherArrhythmiaOnTheSameLineIsKeptBesideIt() {
        let r = applied("SVT, frequent PVCs")
        XCTAssertTrue(r.has("arrhythmia"))
        XCTAssertTrue(r.hx.arrhythmiaType.contains("SVT") && r.hx.arrhythmiaType.contains("PVCs"), r.hx.arrhythmiaType)
        XCTAssertEqual(note("SVT, frequent PVCs").findings.filter { $0.id.hasPrefix("problem:arrhythmia") }.count, 2)
        // SVT alone is as before.
        XCTAssertEqual(note("SVT").findings.first { $0.id == "problem:arrhythmia" }?.change, .problemNote("arrhythmia", "SVT"))
        XCTAssertNil(pvcChange("SVT"))
    }

    func testPVCGuards() {
        for s in ["no PVCs", "no pvc", "denies palpitations or PVCs", "denies PVCs", "PVC pipe", "pvc pipe", "PVC tubing", "PVC-free tubing", "PVC conduit",
                  "mother has PVCs", "FHx: PVCs", "family history of PVCs", "possible PVCs", "concern for PVCs", "r/o PVCs", "metoprolol 25 mg bid, lisinopril 10 mg daily",
                  "Meds: metoprolol, lisinopril, amlodipine", "PvCO2 51", "PvCO₂ 51, PvO2 38"] {
            XCTAssertNil(pvcChange(s), "note: " + s)
            XCTAssertFalse(quickIDs(s).contains(PatientNote.pvcFindingID), "bar: " + s)
            XCTAssertFalse(applied(s).has("arrhythmia"), s)
        }
    }

    func testPVDIsStillPeripheralVascularDisease() {
        for s in ["PVD", "pvd", "peripheral vascular disease", "PMH: HTN, PVD", "hx pvd"] {
            XCTAssertTrue(noteIDs(s).contains("problem:pvd"), "note: " + s + " → " + noteIDs(s).joined(separator: ", "))
            XCTAssertTrue(quickIDs(s).contains("problem:pvd"), "bar: " + s)
            XCTAssertNil(pvcChange(s), s)
            XCTAssertFalse(quickIDs(s).contains(PatientNote.pvcFindingID), s)
            XCTAssertFalse(applied(s).has("arrhythmia"), s)
        }
        XCTAssertFalse(MedAbbreviations.lookup("PVD")?.meanings.first?.text.contains("ventricular") ?? true)
    }

    func testUnderAnECGCueTheECGFindingIsFiledAsToday() {
        for s in ["ECG: NSR, PVCs", "EKG shows PVCs", "ECG: NSR, pvcs", "ekg: frequent pvcs", "NSR with PVCs"] {
            let q = quickIDs(s)
            XCTAssertTrue(q.contains("ecg:PVCs"), "bar: " + s + " → " + q.joined(separator: ", "))
            XCTAssertFalse(q.contains(PatientNote.pvcFindingID), "the ECG's finding only, as today: " + s)
        }
        // The Intraoperative tab files no history.
        XCTAssertFalse(quick("frequent PVCs", tab: .intraop).findings.contains { $0.id == PatientNote.pvcFindingID })
    }

    func testEveryPatternCompilesAndNothingElseMoved() {
        for rx in PatientNote.allPatterns { XCTAssertNotNil(rx.re, rx.pattern) }
        for rx in QuickAdd.allPatterns { XCTAssertNotNil(rx.re, rx.pattern) }
        for rx in MedAbbreviations.allPatterns { XCTAssertNotNil(rx.re, rx.pattern) }
        // A 1.11 record with none of the new ids opens as it did.
        var old = PatientRecord()
        old.problems = ["thrombocytopenia", "anticoagulation", "arrhythmia"]
        old.hx.arrhythmiaType = "SVT"
        XCTAssertEqual(HistorySections.hemeItems(old), ["thrombocytopenia", "on anticoagulation"])
        let data = try? JSONEncoder().encode(old)
        let back = data.flatMap { try? JSONDecoder().decode(PatientRecord.self, from: $0) }
        XCTAssertEqual(back?.problems, old.problems)
    }
}
