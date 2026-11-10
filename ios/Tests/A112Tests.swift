import XCTest
@testable import PeriopSignal

/// 1.12 helper A, labs: the new preprocedure labs (note 12), the blood gas type and the glucose section (note 13), the Labs
/// block of the two summaries as Preop and Intraop columns (note 8), and "+ Add other input data into Handoff" (note 14).
final class A112Tests: XCTestCase {
    private func block(_ blocks: [SummaryBlock], _ key: String) throws -> SummaryBlock {
        try XCTUnwrap(blocks.first { $0.key == key }, "no \(key) block")
    }

    private func labs(_ blocks: [SummaryBlock]) throws -> BriefLabs {
        guard case .fishbone(let l)? = try block(blocks, "labs").figure else {
            XCTFail("the labs block has no figure")
            return BriefLabs()
        }
        return l
    }

    private func labsText(_ r: PatientRecord, handoff: Bool = true) throws -> String {
        try block(handoff ? PatientBriefs.handoff(r) : PatientBriefs.preop(r), "labs").text
    }

    private var preop: PatientRecord { PatientDemo112Labs.preop }

    // MARK: Note 12: the new preprocedure labs

    func testMoreLabsIsEmptyAndOpensAnOlderRecord() throws {
        XCTAssertTrue(PatientMoreLabs().isEmpty)
        // A 1.11 record has no moreLabs at all; an older struct with only some fields opens too.
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"labs":{"k":4.1},"intraopLabs":[{"values":{"ph":7.3}}]}"#.utf8))
        XCTAssertTrue(old.moreLabs.isEmpty)
        XCTAssertEqual(old.intraopLabs.first?.gasType, .abg, "a set saved before 1.12 is an ABG")
        let part = try JSONDecoder().decode(PatientMoreLabs.self, from: Data(#"{"uaNegative":true}"#.utf8))
        XCTAssertTrue(part.uaNegative)
        XCTAssertEqual(part.uaFindings, [])
        XCTAssertEqual(part.bloodCxText, "")
        // A value the version does not know is not fatal.
        let odd = try JSONDecoder().decode(PatientMoreLabs.self, from: Data(#"{"uaFindings":"nonsense","hcgText":"<5"}"#.utf8))
        XCTAssertEqual(odd.hcgText, "<5")
        XCTAssertEqual(odd.uaFindings, [])
    }

    func testMoreLabsRoundTripsAndKeepsTheRecordNonEmpty() throws {
        var r = PatientRecord()
        r.moreLabs.pregnancyNegative = true
        r.moreLabs.toggleUrinalysisFinding("nitrite")
        r.moreLabs.setBloodCulturesText("GPC in clusters, 1 of 2 bottles")
        r.labs["vanc"] = 18.4
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again.moreLabs, r.moreLabs)
        XCTAssertEqual(again.labs["vanc"], 18.4)
        XCTAssertFalse(r.isEmpty)
        var only = PatientRecord()
        only.moreLabs.uaNegative = true
        XCTAssertFalse(only.isEmpty, "a result recorded is something entered")
    }

    func testTheCatalogHasNoInventedRangesForTheNewNumbers() {
        let vanc = PatientLabs.test("vanc")
        XCTAssertEqual(vanc?.unit, "mcg/mL")
        XCTAssertNil(vanc?.range, "the target depends on the indication")
        XCTAssertFalse(vanc?.isRated ?? true)
        XCTAssertEqual(PatientLabs.flag("vanc", 80, sex: nil), .normal)
        let hcg = PatientLabs.test("hcg")
        XCTAssertFalse(hcg?.isRated ?? true)
        XCTAssertEqual(PatientLabs.flag("hcg", 5000, sex: .female), .normal)
        // Neither joins the main labs table or the fishbone slots.
        XCTAssertFalse(PatientLabs.tests(.main).map(\.key).contains("vanc"))
        XCTAssertFalse(PatientLabs.tests(.main).map(\.key).contains("hcg"))
        XCTAssertEqual(PatientLabs.tests(.infectious).map(\.key), ["vanc"])
        XCTAssertEqual(PatientLabs.tests(.pregnancy).map(\.key), ["hcg"])
        XCTAssertFalse(PatientLabs.slotOrder.contains("vanc"))
        // TSH and free T4 were already numbers in the thyroid group, with the ABIM ranges they have always had.
        XCTAssertEqual(PatientLabs.tests(.thyroid).map(\.key).prefix(2), ["tsh", "ft4"])
        XCTAssertEqual(PatientLabs.test("tsh")?.rangeText(for: nil), "0.5–4")
        XCTAssertEqual(PatientLabs.flag("tsh", 5.2, sex: nil), .high)
    }

    func testTheTypedHCGIsANumberOrWordsNeverBoth() {
        var r = PatientRecord()
        PatientMoreLabs.setHCG("12", in: &r)
        XCTAssertEqual(r.labs["hcg"], 12)
        XCTAssertEqual(r.moreLabs.hcgText, "")
        XCTAssertEqual(PatientMoreLabs.hcgField(r), "12")
        PatientMoreLabs.setHCG("<5", in: &r)
        XCTAssertNil(r.labs["hcg"], "words are not a number")
        XCTAssertEqual(r.moreLabs.hcgText, "<5")
        XCTAssertEqual(PatientMoreLabs.hcgField(r), "<5")
        PatientMoreLabs.setHCG("5.", in: &r)
        XCTAssertEqual(r.labs["hcg"], 5, "a trailing dot while typing is still the number")
        PatientMoreLabs.setHCG("", in: &r)
        XCTAssertNil(r.labs["hcg"])
        XCTAssertEqual(r.moreLabs.hcgText, "")
    }

    func testThePregnancyTestIsForAWomanOrAnUnsetSex() {
        XCTAssertTrue(PatientMoreLabs.showsPregnancy(.female))
        XCTAssertTrue(PatientMoreLabs.showsPregnancy(nil))
        XCTAssertFalse(PatientMoreLabs.showsPregnancy(.male))
        var r = PatientRecord()
        r.moreLabs.pregnancyNegative = true
        r.sex = .female
        XCTAssertTrue(LabResults.lineParts(r).parts.contains("Pregnancy test neg"))
        r.sex = nil
        XCTAssertTrue(LabResults.lineParts(r).parts.contains("Pregnancy test neg"))
        r.sex = .male
        XCTAssertFalse(LabResults.lineParts(r).parts.contains("Pregnancy test neg"))
        XCTAssertEqual(r.moreLabs.pregnancyText(number: "12"), "Pregnancy test neg, hCG 12")
        r.moreLabs.pregnancyNegative = false
        XCTAssertEqual(r.moreLabs.pregnancyText(number: "12"), "hCG 12")
        XCTAssertNil(r.moreLabs.pregnancyText())
    }

    func testUrinalysisAndBloodCulturesAreNegativeOrFindings() {
        var m = PatientMoreLabs()
        XCTAssertNil(m.urinalysisText)
        m.setUrinalysisNegative(true)
        XCTAssertEqual(m.urinalysisText, "UA neg")
        XCTAssertFalse(m.urinalysisNeedsTelling)
        // A finding takes Negative off; Negative again clears the findings and the words.
        m.toggleUrinalysisFinding("le")
        m.toggleUrinalysisFinding("nitrite")
        XCTAssertFalse(m.uaNegative)
        XCTAssertEqual(m.urinalysisText, "UA: leukocyte esterase +, nitrite +")
        m.setUrinalysisText("cloudy")
        XCTAssertEqual(m.urinalysisText, "UA: leukocyte esterase +, nitrite +, cloudy")
        XCTAssertTrue(m.urinalysisNeedsTelling)
        m.setUrinalysisNegative(true)
        XCTAssertTrue(m.uaFindings.isEmpty)
        XCTAssertEqual(m.uaText, "")
        XCTAssertEqual(m.urinalysisText, "UA neg")
        m.setBloodCulturesNegative(true)
        XCTAssertEqual(m.bloodCulturesText, "Blood cx neg")
        m.setBloodCulturesText("GPC in clusters")
        XCTAssertFalse(m.bloodCxNegative)
        XCTAssertEqual(m.bloodCulturesText, "Blood cx: GPC in clusters")
        XCTAssertTrue(m.bloodCulturesNeedTelling)
        XCTAssertEqual(PatientMoreLabs.urinalysisFindings.map(\.label), ["Leukocyte esterase +", "Nitrite +", "Bacteria", "Pyuria"])
    }

    func testTheLabsLineCarriesTheInfectiousLabsAndMarksFindingsRed() {
        var r = PatientRecord()
        r.moreLabs.setUrinalysisNegative(true)
        r.moreLabs.setBloodCulturesNegative(true)
        var more = LabResults.lineParts(r)
        XCTAssertEqual(more.parts, ["UA neg", "Blood cx neg"])
        XCTAssertTrue(more.marks.isEmpty)
        r.moreLabs.toggleUrinalysisFinding("bacteria")
        r.moreLabs.setBloodCulturesText("yeast")
        more = LabResults.lineParts(r)
        XCTAssertEqual(more.parts, ["UA: bacteria", "Blood cx: yeast"])
        XCTAssertEqual(more.marks, ["UA: bacteria", "Blood cx: yeast"], "a finding or a growth is for the next team to read")
        XCTAssertNotNil(PatientSummary.labsLine(r), "so the Labs card and link know there is something")
    }

    // MARK: Note 13: the blood gas type and the glucose section

    func testABloodGasHasATypeThatSavesAndDefaultsToABG() throws {
        XCTAssertEqual(IntraopLabSet().gasType, .abg)
        XCTAssertEqual(BloodGasType.allCases, [.abg, .vbg, .scvo2, .svo2])
        XCTAssertEqual(BloodGasType.allCases.map(\.label), ["ABG", "VBG", "ScvO₂ (CVL)", "SvO₂ (PA)"])
        XCTAssertEqual(BloodGasType.allCases.map(\.short), ["ABG", "VBG", "ScvO₂", "SvO₂"])
        XCTAssertEqual(BloodGasType.allCases.map(\.isVenous), [false, true, true, true])
        XCTAssertEqual(BloodGasType.allCases.map(\.hasSaturation), [false, false, true, true])
        var s = IntraopLabSet(values: ["ph": 7.3])
        s.gasType = .svo2
        let again = try JSONDecoder().decode(IntraopLabSet.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(again.gasType, .svo2)
        XCTAssertEqual(again, s)
        let unknown = try JSONDecoder().decode(IntraopLabSet.self, from: Data(#"{"gasType":"cord","values":{"ph":7.3}}"#.utf8))
        XCTAssertEqual(unknown.gasType, .abg, "a type this version does not know reads as the default")
        XCTAssertTrue(IntraopLabSet(gasType: .vbg).isEmpty, "a type alone is no result")
    }

    func testTheGlucoseLeavesTheGasAndKeepsItsPlaceInTheLine() {
        XCTAssertFalse(IntraopLabs.abg.contains("glucose"))
        XCTAssertEqual(IntraopLabs.glucoseKeys, ["glucose"])
        XCTAssertTrue(IntraopLabs.keys.contains("glucose"))
        XCTAssertEqual(IntraopLabs.abgSlash + IntraopLabs.abgRest, IntraopLabs.abg)
        // The "Last labs" line prints it after the ionized calcium, as before.
        let set = IntraopLabSet(values: ["ica": 1.2, "glucose": 164, "inr": 1.1])
        let line = IntraopLabs.values(set, sex: nil).map(\.key)
        XCTAssertEqual(line, ["ica", "glucose", "inr"])
        XCTAssertEqual(IntraopLabs.pageOrder(.abg).first, "glucose", "the glucose section is above the gas")
        XCTAssertEqual(Array(IntraopLabs.pageOrder(.abg).prefix(5)), ["glucose", "ph", "paco2", "pao2", "hco3a"])
        XCTAssertFalse(IntraopLabs.pageOrder(.vbg).contains(IntraopLabs.satKey))
        XCTAssertEqual(Array(IntraopLabs.pageOrder(.scvo2).prefix(3)), ["glucose", IntraopLabs.satKey, "ph"], "the saturation first for ScvO₂")
        XCTAssertEqual(IntraopLabs.pageOrder(.svo2).last, "act")
    }

    @MainActor func testTheEditorWalksTheGlucoseThenTheGasOfTheNewestSet() {
        var r = PatientRecord()
        r.intraopLabs = [IntraopLabSet(time: Date())]
        let abg = IntraopLabsEditor.fieldOrder(r)
        XCTAssertEqual(Array(abg.prefix(3)), ["iop.glucose", "iop.ph", "iop.paco2"])
        XCTAssertEqual(abg.last, "iop.act")
        XCTAssertFalse(abg.contains("iop." + IntraopLabs.satKey))
        r.intraopLabs[0].gasType = .svo2
        let sv = IntraopLabsEditor.fieldOrder(r)
        XCTAssertEqual(Array(sv.prefix(3)), ["iop.glucose", "iop." + IntraopLabs.satKey, "iop.ph"], "a saturation field for an SvO₂ sample")
        XCTAssertEqual(Set(sv).count, sv.count, "every field once")
        // The newest set decides.
        r.intraopLabs = [IntraopLabSet(time: Date().addingTimeInterval(-3600), gasType: .svo2), IntraopLabSet(time: Date(), gasType: .abg)]
        XCTAssertFalse(IntraopLabsEditor.fieldOrder(r).contains("iop." + IntraopLabs.satKey))
    }

    func testAVenousGasReadsPvCO2PvO2AndLactateWithoutArterial() throws {
        let a = try XCTUnwrap(IntraopLabs.test("paco2", type: .abg))
        XCTAssertEqual(a.short, "PaCO₂")
        XCTAssertEqual(IntraopLabs.test("pao2", type: .abg)?.short, "PaO₂")
        XCTAssertEqual(IntraopLabs.test("lactate", type: .abg)?.label, "Lactate, arterial")
        XCTAssertEqual(IntraopLabs.test("hco3a", type: .abg)?.label, "Bicarbonate, arterial")
        for type in [BloodGasType.vbg, .scvo2, .svo2] {
            XCTAssertEqual(IntraopLabs.test("paco2", type: type)?.short, "PvCO₂", "\(type)")
            XCTAssertEqual(IntraopLabs.test("paco2", type: type)?.label, "PvCO₂", "\(type)")
            XCTAssertEqual(IntraopLabs.test("pao2", type: type)?.short, "PvO₂", "\(type)")
            XCTAssertEqual(IntraopLabs.test("lactate", type: type)?.label, "Lactate", "\(type): not \"arterial\"")
            XCTAssertEqual(IntraopLabs.test("hco3a", type: type)?.label, "Bicarbonate", "\(type)")
            for k in ["ph", "paco2", "pao2", "hco3a"] {
                XCTAssertNil(IntraopLabs.test(k, type: type)?.range, "\(type) \(k): no arterial range")
                XCTAssertNil(IntraopLabs.test(k, type: type)?.rangeText(for: nil))
                XCTAssertFalse(IntraopLabs.isRanged(k, type: type))
            }
            XCTAssertNotNil(IntraopLabs.test("lactate", type: type)?.range, "the lactate's criterion is not an arterial range")
            XCTAssertNotNil(IntraopLabs.test("k", type: type)?.range)
        }
        // The arterial entries themselves are not changed by reading them as venous.
        XCTAssertNotNil(IntraopLabs.test("paco2", type: .abg)?.range)
        XCTAssertEqual(IntraopLabs.test("paco2", type: .abg)?.rangeText(for: nil), "38–42")
    }

    func testArterialFlagsAreNotAppliedToAVenousGas() {
        // PaCO₂ 51 and pH 7.31 are flagged on an arterial sample, not on a venous one.
        XCTAssertEqual(IntraopLabs.flag("paco2", 51, sex: nil, type: .abg), .high)
        XCTAssertEqual(IntraopLabs.flag("ph", 7.31, sex: nil, type: .abg), .low)
        XCTAssertEqual(IntraopLabs.flag("pao2", 40, sex: nil, type: .abg), .low)
        XCTAssertEqual(IntraopLabs.flag("hco3a", 28, sex: nil, type: .abg), .high)
        for type in [BloodGasType.vbg, .scvo2, .svo2] {
            XCTAssertEqual(IntraopLabs.flag("paco2", 51, sex: nil, type: type), .normal)
            XCTAssertEqual(IntraopLabs.flag("ph", 7.31, sex: nil, type: type), .normal)
            XCTAssertEqual(IntraopLabs.flag("pao2", 40, sex: nil, type: type), .normal)
            XCTAssertEqual(IntraopLabs.flag("hco3a", 28, sex: nil, type: type), .normal)
            // What is not arterial keeps its flag: lactate (Sepsis-3), potassium, hemoglobin, ionized calcium.
            XCTAssertEqual(IntraopLabs.flag("lactate", 2.4, sex: nil, type: type), .high)
            XCTAssertEqual(IntraopLabs.flag("k", 5.8, sex: nil, type: type), .high)
            XCTAssertEqual(IntraopLabs.flag("ica", 1.0, sex: nil, type: type), .low)
        }
        XCTAssertEqual(IntraopLabs.flag(IntraopLabs.satKey, 40, sex: nil, type: .svo2), .normal, "the saturation has no range")
        XCTAssertNil(IntraopLabs.test(IntraopLabs.satKey, type: .svo2)?.range)
    }

    func testTheSaturationIsNamedForItsSample() {
        XCTAssertEqual(IntraopLabs.test(IntraopLabs.satKey, type: .scvo2)?.short, "ScvO₂")
        XCTAssertEqual(IntraopLabs.test(IntraopLabs.satKey, type: .svo2)?.short, "SvO₂")
        XCTAssertEqual(IntraopLabs.test(IntraopLabs.satKey, type: .svo2)?.unit, "%")
        XCTAssertTrue(IntraopLabs.keys.contains(IntraopLabs.satKey))
        XCTAssertNotNil(PatientLabs.test(IntraopLabs.satKey), "the catalog finds it too, so a record's value is read")
    }

    func testTheLastLabsLineFollowsTheSample() throws {
        var s = IntraopLabSet(time: PatientDemo.today(10, 40), values: ["ph": 7.31, "paco2": 51, "lactate": 2.4])
        let arterial = try XCTUnwrap(IntraopLabs.line(s, sex: nil))
        XCTAssertEqual(arterial.text, "10:40 · pH 7.31 L · PaCO₂ 51 H · Lactate 2.4 H")
        s.gasType = .vbg
        let venous = try XCTUnwrap(IntraopLabs.line(s, sex: nil))
        XCTAssertEqual(venous.text, "VBG 10:40 · pH 7.31 · PvCO₂ 51 · Lactate 2.4 H", "a venous sample says so, with no arterial flags")
        XCTAssertEqual(venous.marks, ["Lactate 2.4 H"])
    }

    // MARK: Note 8: the Labs block as Preop and Intraop columns

    func testThePreopColumnHasCMPHemeAndOtherInOrder() throws {
        let l = try labs(PatientBriefs.preop(preop))
        XCTAssertEqual(l.preop.map(\.name), ["CMP", "Heme", "Other"])
        XCTAssertFalse(l.hasIntraop, "the Preprocedure Summary has the Preop column alone")
        let text = try labsText(preop, handoff: false)
        XCTAssertEqual(text, "Preop: CMP: Na 138, K 4.1, BUN 24 H, Cr 1.30 H (GFR 52 L), AST 55 H, ALT 30, Glu 142; Heme: Hb 10.9 L, Plt 210, PTT 31, INR 1.0, Fib 310, T&S A−, screen neg, 2 u crossmatched; Other: Lactate 1.4, TSH 5.2 H, Free T4 1.1, T bili 0.8, MRSA neg, Pregnancy test neg, hCG <5, WBC 11.8 H, Alb 3.1 L")
    }

    func testOnlyRecordedValuesAreShownAndAnEmptyGroupAndColumnAreOmitted() throws {
        var r = PatientRecord()
        r.labs = ["na": 138]
        XCTAssertEqual(try labsText(r), "Preop: CMP: Na 138", "no Heme or Other, no Intraop")
        r.labs = ["plt": 98]
        XCTAssertEqual(try labsText(r), "Preop: Heme: Plt 98 L")
        r.labs = [:]
        XCTAssertNil(PatientBriefs.handoff(r).first { $0.key == "labs" }, "nothing recorded, no block")
        r.intraopLabs = [IntraopLabSet(time: PatientDemo.today(10, 40), values: ["inr": 1.4])]
        XCTAssertEqual(try labsText(r), "Intraop: Coags: INR 1.4 H", "an Intraop column alone")
    }

    func testTheCrAndGFRGoTogetherAndASlashPairsAstAndAltWhileNormal() throws {
        var r = PatientRecord()
        r.sex = .male
        r.labs = ["cr": 0.9, "gfr": 95, "ast": 30, "alt": 25]
        XCTAssertEqual(try labsText(r), "Preop: CMP: Cr 0.90 (GFR 95), AST/ALT 30/25")
        r.labs = ["cr": 2.4, "gfr": 28, "ast": 90, "alt": 25]
        XCTAssertEqual(try labsText(r), "Preop: CMP: Cr 2.40 H (GFR 28 L), AST 90 H, ALT 25", "an abnormal one is written on its own so its flag is exact")
        let b = try block(PatientBriefs.handoff(r), "labs")
        XCTAssertTrue(b.marks.contains("Cr 2.40 H"))
        XCTAssertTrue(b.marks.contains("GFR 28 L"))
        XCTAssertTrue(b.marks.contains("AST 90 H"))
        XCTAssertFalse(b.marks.contains("ALT 25"))
        r.labs = ["gfr": 80, "ast": 20]
        XCTAssertEqual(try labsText(r), "Preop: CMP: GFR 80, AST 20")
    }

    func testValuesOutsideTheListsAreNotShownByDefault() throws {
        let text = try labsText(PatientDemo112Labs.preop.withExtras([]), handoff: false)
        for out in ["Cl ", "HCO₃ ", "WBC", "Hct", "PT ", "Alb ", "Ca ", "Vanc", "UA", "Blood cx", "Staph", "COVID"] {
            XCTAssertFalse(text.contains(out), "\(out) is not in the default lists: \(text)")
        }
        XCTAssertFalse(text.contains("*"), "the asterisk-and-footnote scheme is gone")
    }

    func testTheHCGAndPregnancyTestShowForAWomanAndNotForAMan() throws {
        var r = PatientRecord()
        r.sex = .female
        r.moreLabs.pregnancyNegative = true
        XCTAssertEqual(try labsText(r), "Preop: Other: Pregnancy test neg")
        PatientMoreLabs.setHCG("12", in: &r)
        XCTAssertEqual(try labsText(r), "Preop: Other: Pregnancy test neg, hCG 12", "a typed number is the lab hcg")
        r.sex = nil
        XCTAssertTrue(try labsText(r).contains("hCG 12"), "an unset sex is offered the test, so it shows")
        r.sex = .male
        XCTAssertNil(PatientBriefs.handoff(r).first { $0.key == "labs" })
    }

    func testAbnormalValuesStayBoldRedWithTheirFlagAndTheMarksAreInTheText() throws {
        let b = try block(PatientBriefs.handoff(PatientDemo112Labs.abgRecord), "labs")
        for m in ["BUN 24 H", "Cr 1.30 H", "GFR 52 L", "AST 55 H", "Hb 10.9 L", "TSH 5.2 H", "PCO₂ 43 H", "HCO₃ 28 H", "Plt 98 L", "INR 1.6 H", "Fib 180 L"] {
            XCTAssertTrue(b.marks.contains(m), "\(m) is red: \(b.marks)")
            XCTAssertTrue(b.text.contains(m), "\(m) is in the text")
        }
        XCTAssertFalse(b.marks.contains("Na 138"))
        XCTAssertTrue(b.marks.allSatisfy { b.text.contains($0) }, "every mark is a part of the text, so it can be drawn")
    }

    func testTheHandoffHasTheNewestGasWithItsLactateAndTheNewestCoags() throws {
        let l = try labs(PatientBriefs.handoff(PatientDemo112Labs.abgRecord))
        let gas = try XCTUnwrap(l.gas)
        XCTAssertEqual(gas.type, .abg)
        XCTAssertEqual(gas.title, "ABG (08:03)")
        XCTAssertEqual(gas.figureLabel, "ABG · 08:03")
        XCTAssertEqual(gas.slash.map { $0?.label }, ["pH", "PCO₂", "PO₂", "HCO₃"], "the slash figure's labels")
        XCTAssertEqual(gas.slash.map { $0?.text }, ["7.43", "43", "146", "28"])
        XCTAssertEqual(gas.lactate?.text, "1")
        XCTAssertEqual(l.intraop.map(\.name), ["ABG (08:03)", "Coags"], "Plt, INR, fibrinogen and the viscoelastic, no PTT or ACT")
        let text = try labsText(PatientDemo112Labs.abgRecord)
        XCTAssertTrue(text.contains("\nIntraop: ABG (08:03): pH 7.43 / PCO₂ 43 H / PO₂ 146 / HCO₃ 28 H, Lactate 1; Coags: Plt 98 L, INR 1.6 H, Fib 180 L, TEG/ROTEM: EXTEM CT 92 s, A10 38 mm"), text)
        XCTAssertFalse(text.contains("ACT"), "the ACT is an extra, not a default")
        XCTAssertFalse(text.contains("Na 132"), "the gas's sodium is not in the figure")
    }

    func testTheNewestGasWinsAndAVenousOneIsNotFlaggedAsArterial() throws {
        let r = PatientDemo112Labs.vbgRecord
        let l = try labs(PatientBriefs.handoff(r))
        let gas = try XCTUnwrap(l.gas)
        XCTAssertEqual(gas.type, .vbg)
        XCTAssertEqual(gas.title, "VBG (10:40)")
        XCTAssertEqual(gas.slash.compactMap { $0 }.filter(\.abnormal).count, 0, "PCO₂ 51 and pH 7.31 are not flagged on a venous gas")
        XCTAssertEqual(gas.lactate?.flag, .high, "the lactate criterion still applies")
        let b = try block(PatientBriefs.handoff(r), "labs")
        XCTAssertTrue(b.text.contains("VBG (10:40): pH 7.31 / PCO₂ 51 / PO₂ 38 / HCO₃ 25, Lactate 2.4 H"), b.text)
        XCTAssertFalse(b.marks.contains("PCO₂ 51 H"))
        XCTAssertTrue(b.marks.contains("Lactate 2.4 H"))
        XCTAssertFalse(b.text.contains("ABG (08:03)"), "only the most recent gas")
    }

    func testAnSvO2SampleShowsItsSaturationFirst() throws {
        let r = PatientDemo112Labs.svo2Record
        let gas = try XCTUnwrap(try labs(PatientBriefs.handoff(r)).gas)
        XCTAssertEqual(gas.type, .svo2)
        XCTAssertEqual(gas.saturation?.text, "64%")
        XCTAssertEqual(gas.saturation?.label, "SvO₂")
        let b = try block(PatientBriefs.handoff(r), "labs")
        XCTAssertTrue(b.text.contains("SvO₂ (10:40): SvO₂ 64%, pH 7.33 / PCO₂ 46 / PO₂ 36 / HCO₃ 24, Lactate 1.9"), b.text)
        // A saturation recorded on an ABG is not shown by default (it is an extra to choose).
        var abg = PatientRecord()
        abg.intraopLabs = [IntraopLabSet(time: PatientDemo.today(9, 0), values: ["ph": 7.4, IntraopLabs.satKey: 70])]
        XCTAssertNil(try labs(PatientBriefs.handoff(abg)).gas?.saturation)
        XCTAssertTrue(HandoffExtras.intraopCandidates(abg).map(\.key).contains("intraop:" + IntraopLabs.satKey))
    }

    func testEachCoagValueIsTheLatestSetThatHoldsIt() throws {
        var r = PatientRecord()
        r.intraopLabs = [IntraopLabSet(time: PatientDemo.today(9, 15), values: ["inr": 1.9, "plt": 90], viscoelastic: "EXTEM CT 110 s"),
                         IntraopLabSet(time: PatientDemo.today(10, 40), values: ["inr": 1.4, "fibrinogen": 230])]
        let b = try block(PatientBriefs.handoff(r), "labs")
        XCTAssertEqual(b.text, "Intraop: Coags: Plt 90 L, INR 1.4 H, Fib 230, TEG/ROTEM: EXTEM CT 110 s")
        let l = try labs([b])
        XCTAssertEqual(l.caption, "Intraop 10:40 (INR, Fib) / 09:15 (Plt, TEG/ROTEM)", "each time names its values")
        XCTAssertFalse(b.text.contains("INR 1.9"))
    }

    func testTheCaptionKeepsTheTimesAsASmallLineAndTheAsteriskSchemeIsGone() throws {
        let r = PatientDemo112Labs.abgRecord
        let l = try labs(PatientBriefs.handoff(r))
        XCTAssertEqual(l.caption, "Preop labs 06:30 · Intraop 09:15")
        XCTAssertFalse((l.caption ?? "").contains("*"))
        XCTAssertNil(try labs(PatientBriefs.preop(PatientDemo112Labs.preop.withLabsDrawn(nil))).caption, "no time entered, none shown")
        XCTAssertEqual(try labs(PatientBriefs.preop(r)).caption, "Preop labs 06:30", "the Preprocedure Summary names the preop draw time")
    }

    func testThePlainTextIsTwoLabelledParagraphs() throws {
        let plain = PatientBriefs.plainText(PatientBriefs.handoff(PatientDemo112Labs.abgRecord))
        let lines = plain.components(separatedBy: "\n")
        let at = try XCTUnwrap(lines.firstIndex(of: "Labs:"))
        XCTAssertTrue(lines[at + 1].hasPrefix("  Preop: CMP: Na 138, K 4.1, BUN 24 H"), lines[at + 1])
        XCTAssertTrue(lines[at + 2].hasPrefix("  Intraop: ABG (08:03): pH 7.43 / PCO2 43 H / PO2 146 / HCO3 28 H, Lactate 1; Coags: Plt 98 L"), "plain digits: " + lines[at + 2])
        XCTAssertEqual(lines[at + 3], "  Preop labs 06:30 · Intraop 09:15")
        // Before the case: Preop alone, on the label's line.
        let pre = PatientBriefs.plainText(PatientBriefs.preop(PatientDemo112Labs.preop))
        XCTAssertTrue(pre.contains("Labs: Preop: CMP: Na 138"), pre)
        XCTAssertFalse(pre.contains("Intraop:"))
    }

    func testAnEditedLabsBlockShowsTheUsersWordsAndAnEmptiedOneGoes() throws {
        var r = PatientDemo112Labs.abgRecord
        PatientBriefs.setEdit(&r, .handoff, key: "labs", text: "Preop: all normal")
        let b = try block(PatientBriefs.handoff(r), "labs")
        XCTAssertTrue(b.edited)
        XCTAssertEqual(b.text, "Preop: all normal")
        XCTAssertFalse(b.figureHasContent, "the words stand in for the columns")
        XCTAssertEqual(PatientBriefs.plainText([b]), "Labs: Preop: all normal")
        PatientBriefs.setEdit(&r, .handoff, key: "labs", text: "")
        XCTAssertNil(PatientBriefs.handoff(r).first { $0.key == "labs" })
        PatientBriefs.regenerate(&r, .handoff)
        XCTAssertNotNil(PatientBriefs.handoff(r).first { $0.key == "labs" })
    }

    func testWhatTheHandoffCarriedForSafetyIsNotDropped() throws {
        var r = PatientRecord()
        r.sex = .male
        r.labs = ["na": 138]
        r.infections = PatientInfections(results: ["mrsa": .positive, "covid": .pending, "cdiff": .negative])
        r.moreLabs.toggleUrinalysisFinding("nitrite")
        r.moreLabs.setBloodCulturesText("GPC in clusters")
        r.labSections = ["liver"]
        r.ascites = .slight
        r.labs["tbili"] = 3.4; r.labs["albumin"] = 2.6; r.labs["inr"] = 1.7; r.labs["cr"] = 1.0
        r.labNotes = "ANA negative"
        r.intraopLabs = [IntraopLabSet(time: PatientDemo.today(9, 0), values: ["inr": 1.2], other: "Mg 1.6")]
        let b = try block(PatientBriefs.handoff(r), "labs")
        XCTAssertTrue(b.text.contains("MRSA pos"), b.text)
        XCTAssertTrue(b.marks.contains("MRSA pos"))
        XCTAssertTrue(b.text.contains("COVID pending"), "a pending result is for the next team")
        XCTAssertFalse(b.text.contains("C. diff neg"), "a negative one is a chip")
        XCTAssertTrue(b.text.contains("UA: nitrite +"))
        XCTAssertTrue(b.marks.contains("UA: nitrite +"))
        XCTAssertTrue(b.text.contains("Blood cx: GPC in clusters"))
        XCTAssertTrue(b.text.contains("MELD"), "the liver scores")
        XCTAssertTrue(b.text.contains("ANA negative"), "the lab notes typed on the Labs page")
        XCTAssertTrue(b.text.contains("Mg 1.6"), "the newest set's other results")
    }

    func testPositiveTypeAndScreenIsMarked() throws {
        var r = PatientRecord()
        r.typeScreen = PatientTypeScreen(type: "O+", screen: .positive, antibody: "anti-K", crossmatched: 4)
        let b = try block(PatientBriefs.handoff(r), "labs")
        XCTAssertTrue(b.text.contains("Heme: T&S O+, screen pos (anti-K), 4 u crossmatched"), b.text)
        XCTAssertTrue(b.marks.contains("T&S O+, screen pos (anti-K)"))
        XCTAssertTrue(b.marks.allSatisfy { b.text.contains($0) })
    }

    // MARK: Note 14: + Add other input data into Handoff

    func testThePreopChipsAreTheRecordedItemsTheSummaryDoesNotShow() {
        let r = PatientDemo112Labs.preop.withExtras([])
        let keys = HandoffExtras.preopCandidates(r).map(\.key)
        for k in ["wbc", "hct", "pt", "cl", "hco3", "albumin", "ca", "vanc", "ua", "bcx", "staph", "covid"] {
            XCTAssertTrue(keys.contains("preop:" + k), "preop:\(k) is recorded and not shown by default: \(keys)")
        }
        for k in ["na", "k", "bun", "cr", "gfr", "ast", "alt", "glucose", "hb", "plt", "ptt", "inr", "fibrinogen", "lactate", "tsh", "ft4", "tbili", "hcg", "mrsa"] {
            XCTAssertFalse(keys.contains("preop:" + k), "preop:\(k) is shown by default")
        }
        XCTAssertFalse(keys.contains("preop:mg"), "not recorded, not offered")
        XCTAssertEqual(HandoffExtras.preopCandidates(PatientRecord()).count, 0)
        // A positive or pending infectious result and a urinalysis with a finding are shown by default, so no chip.
        var pos = PatientRecord()
        pos.infections = PatientInfections(results: ["covid": .positive, "cdiff": .pending, "staph": .negative])
        pos.moreLabs.toggleUrinalysisFinding("bacteria")
        let posKeys = HandoffExtras.preopCandidates(pos).map(\.key)
        XCTAssertEqual(posKeys, ["preop:staph"])
    }

    func testTheIntraopChipsAreTheValuesOutsideTheGasAndTheCoags() {
        let keys = HandoffExtras.intraopCandidates(PatientDemo112Labs.abgRecord).map(\.key)
        XCTAssertEqual(keys, ["intraop:be", "intraop:hb", "intraop:k", "intraop:na", "intraop:ica", "intraop:glucose", "intraop:act"])
        for k in ["ph", "paco2", "pao2", "hco3a", "lactate", "plt", "inr", "fibrinogen", "ptt"] {
            XCTAssertFalse(keys.contains("intraop:" + k), "\(k) is shown by default or not recorded")
        }
        var r = PatientRecord()
        r.intraopLabs = [IntraopLabSet(time: PatientDemo.today(9, 0), values: ["ptt": 45, "lactate": 3.1])]
        XCTAssertEqual(HandoffExtras.intraopCandidates(r).map(\.key), ["intraop:lactate", "intraop:ptt"], "a lactate on no gas, and the PTT, are extras")
        XCTAssertTrue(HandoffExtras.intraopCandidates(PatientRecord()).isEmpty)
    }

    func testImagingChipsAppearWhenTheRecordHoldsText() {
        var r = PatientRecord()
        XCTAssertTrue(HandoffExtras.imagingCandidates(r).isEmpty)
        r.imaging.ct = "CT chest 10/2026: 4.8 cm ascending aorta"
        r.imaging.other = "  "
        XCTAssertEqual(HandoffExtras.imagingCandidates(r).map(\.key), ["imaging:ct"])
        r.imaging.mri = "MRI brain: no acute findings"
        r.imaging.other = "Carotid duplex"
        XCTAssertEqual(HandoffExtras.imagingCandidates(r).map(\.label), ["CT", "MRI", "Other imaging"])
        XCTAssertEqual(HandoffExtras.imagingCandidates(r).map(\.key), ["imaging:ct", "imaging:mri", "imaging:other"])
    }

    func testAChosenPreopLabIsAppendedUnderOtherInBothSummaries() throws {
        var r = PatientDemo112Labs.preop.withExtras([])
        XCTAssertFalse(try labsText(r).contains("Alb"))
        XCTAssertEqual(HandoffExtras.chosenCount(r), 0)
        patientToggle(&r, "preop:albumin")
        XCTAssertEqual(r.handoffExtras, ["preop:albumin"])
        XCTAssertTrue(try labsText(r, handoff: false).hasSuffix("Pregnancy test neg, hCG <5, Alb 3.1 L"), "appended under Other")
        XCTAssertTrue(try labsText(r, handoff: true).contains("Alb 3.1 L"))
        XCTAssertTrue(try block(PatientBriefs.handoff(r), "labs").marks.contains("Alb 3.1 L"), "an abnormal extra stays red")
        patientToggle(&r, "preop:ua")
        XCTAssertTrue(try labsText(r, handoff: false).hasSuffix("Alb 3.1 L, UA neg"))
        XCTAssertEqual(HandoffExtras.chosenCount(r), 2)
        patientToggle(&r, "preop:albumin")
        XCTAssertFalse(try labsText(r).contains("Alb"), "a second tap takes it off")
        XCTAssertEqual(r.handoffExtras, ["preop:ua"])
    }

    func testAChosenIntraopLabIsInTheHandoffOnly() throws {
        var r = PatientDemo112Labs.abgRecord.withExtras([])
        patientToggle(&r, "intraop:k")
        patientToggle(&r, "intraop:glucose")
        let hand = try labsText(r)
        XCTAssertTrue(hand.contains("; Other: K 4.3, Glu 164"), "under Other in the Intraop column, the newest of each: " + hand)
        let l = try labs(PatientBriefs.handoff(r))
        XCTAssertEqual(l.intraop.map(\.name), ["ABG (08:03)", "Coags", "Other"])
        XCTAssertEqual(l.caption, "Preop labs 06:30 · Intraop 09:15 (Plt, INR, Fib, TEG/ROTEM) / 08:03 (K, Glu)", "the newest time first, each naming its values")
        let pre = try labsText(r, handoff: false)
        XCTAssertFalse(pre.contains("K 4.3"), "the Preprocedure Summary has no Intraop column")
        XCTAssertFalse(pre.contains("Intraop"))
        // From the newest set that holds it.
        r.intraopLabs.append(IntraopLabSet(time: PatientDemo.today(11, 0), values: ["k": 5.2]))
        XCTAssertTrue(try labsText(r).contains("K 5.2 H"), "the newest potassium")
    }

    func testAKeyWhoseItemIsNoLongerRecordedIsIgnored() throws {
        var r = PatientDemo112Labs.preop.withExtras(["preop:albumin", "preop:mg", "intraop:k", "imaging:ct"])
        XCTAssertTrue(try labsText(r, handoff: false).contains("Alb 3.1 L"))
        XCTAssertFalse(try labsText(r, handoff: false).contains("Mg"), "not recorded: nothing shown, nothing broken")
        r.labs["albumin"] = nil
        XCTAssertFalse(try labsText(r, handoff: false).contains("Alb"))
        XCTAssertEqual(HandoffExtras.chosenCount(r), 0)
        XCTAssertEqual(r.handoffExtras.count, 4, "the keys stay in the record, so recording the item again brings it back")
        r.labs["albumin"] = 3.1
        XCTAssertTrue(try labsText(r, handoff: false).contains("Alb 3.1 L"))
    }

    @MainActor func testTheExtrasLinkSaysWhatIsChosen() {
        XCTAssertEqual(HandoffExtrasLink.title(chosen: 0), "Add other input data into Handoff")
        XCTAssertEqual(HandoffExtrasLink.title(chosen: 3), "Other input data in Handoff: 3 added")
    }

    func testAnExtraThatIsNotChosenChangesNothing() throws {
        let plain = PatientDemo112Labs.preop.withExtras([])
        var more = plain
        more.handoffExtras = ["preop:albumin"]
        XCTAssertNotEqual(try labsText(plain), try labsText(more))
        XCTAssertEqual(try labsText(plain), try labsText(plain.withExtras(["imaging:ct"])), "an imaging key is the Imaging block's, not the labs'")
    }

    // MARK: Helper

    private func patientToggle(_ r: inout PatientRecord, _ key: String) { HandoffExtras.toggle(key, in: &r) }
}

private extension PatientRecord {
    func withExtras(_ keys: [String]) -> PatientRecord {
        var r = self
        r.handoffExtras = keys
        return r
    }

    func withLabsDrawn(_ d: Date?) -> PatientRecord {
        var r = self
        r.labsDrawn = d
        return r
    }
}

#if DEBUG
private extension PatientDemo112Labs {
    static var abgRecord: PatientRecord { record("demo-112-labs-abg") ?? PatientRecord() }
    static var vbgRecord: PatientRecord { record("demo-112-labs-vbg") ?? PatientRecord() }
    static var svo2Record: PatientRecord { record("demo-112-labs-svo2") ?? PatientRecord() }
}
#endif
