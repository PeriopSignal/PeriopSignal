import XCTest
@testable import PeriopSignal

/// The Reference tab's data and arithmetic: reference.json decodes, the scores add up to the
/// published bands, and the pediatric formulas give the textbook answers.
final class ReferenceTests: XCTestCase {
    private func bundled() throws -> ReferenceBundle {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"), "reference.json is bundled with the tests")
        return try ReferenceLoader.decode(try Data(contentsOf: url))
    }

    // MARK: reference.json

    func testReferenceBundleDecodes() throws {
        let b = try bundled()
        XCTAssertGreaterThanOrEqual(b.version, 1)
        XCTAssertEqual(b.updated.count, 10, "updated is YYYY-MM-DD")
        XCTAssertFalse(b.quickrefs.isEmpty)
        let ids = b.quickrefs.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "quick reference ids are unique")
        for ref in b.quickrefs {
            XCTAssertFalse(ref.sections.isEmpty, "\(ref.id) has sections")
            XCTAssertTrue(ref.source.url.hasPrefix("https://"), "\(ref.id) source is a link")
            for s in ref.sections {
                switch s.kind {
                case .table:
                    let cols = try XCTUnwrap(s.columns, "\(ref.id): table has columns")
                    for row in s.rows ?? [] { XCTAssertEqual(row.count, cols.count, "\(ref.id): row width matches columns") }
                case .facts:
                    for row in s.rows ?? [] { XCTAssertEqual(row.count, 2, "\(ref.id): fact rows are label/value") }
                case .list, .steps:
                    XCTAssertFalse((s.items ?? []).isEmpty, "\(ref.id): list has items")
                case .text:
                    XCTAssertFalse((s.text ?? "").isEmpty, "\(ref.id): text section has text")
                }
            }
            XCTAssertFalse(ref.searchText.isEmpty)
        }
        let peds = try XCTUnwrap(b.peds)
        XCTAssertFalse(peds.drugs.isEmpty)
        XCTAssertEqual(Set(peds.drugs.map(\.id)).count, peds.drugs.count, "drug ids are unique")
        for d in peds.drugs {
            XCTAssertGreaterThan(d.low, 0, d.id)
            if let h = d.high { XCTAssertGreaterThanOrEqual(h, d.low, d.id) }
            if let m = d.max { XCTAssertGreaterThan(m, 0, d.id) }
        }
        XCTAssertFalse(peds.bloodVolume.isEmpty)
        XCTAssertFalse(peds.localAnesthetics.isEmpty)
    }

    @MainActor
    func testEmergencyReferencesSortFirst() throws {
        let b = try bundled()
        let store = ReferenceStore()
        store.inject(b)
        let sorted = store.quickrefs
        if let firstNonEmergency = sorted.firstIndex(where: { !$0.isEmergency }) {
            XCTAssertTrue(sorted[..<firstNonEmergency].allSatisfy(\.isEmergency))
            XCTAssertTrue(sorted[firstNonEmergency...].allSatisfy { !$0.isEmergency })
        }
    }

    // MARK: Scores

    func testRCRI() {
        let def = Scores.rcri
        XCTAssertEqual(def.maxScore, 6)
        XCTAssertEqual(def.total(ScoreSelection()), 0)
        XCTAssertEqual(def.band(for: 0)?.label.hasPrefix("Class I "), true)
        let two = ScoreSelection(on: ["surgery", "insulin"])
        XCTAssertEqual(def.total(two), 2)
        XCTAssertEqual(def.band(for: 2)?.label.hasPrefix("Class III"), true)
        XCTAssertEqual(def.band(for: 5)?.label.hasPrefix("Class IV"), true)
    }

    func testARISCAT() {
        let def = Scores.ariscat
        XCTAssertEqual(def.maxScore, 16 + 24 + 17 + 11 + 24 + 23 + 8)
        var s = ScoreSelection()
        s.choices["age"] = "> 80"            // 16
        s.choices["spo2"] = "≤ 90%"          // 24
        s.choices["incision"] = "Intrathoracic" // 24
        XCTAssertEqual(def.total(s), 64)
        XCTAssertEqual(def.band(for: 64)?.tone, .high)
        var mid = ScoreSelection()
        mid.choices["age"] = "51–80"         // 3
        mid.choices["incision"] = "Upper abdominal" // 15
        mid.on = ["emergency"]               // 8
        XCTAssertEqual(def.total(mid), 26)
        XCTAssertEqual(def.band(for: 26)?.tone, .moderate)
        XCTAssertEqual(def.band(for: 25)?.tone, .low)
    }

    func testSTOPBangAndApfelCount() {
        XCTAssertEqual(Scores.stopBang.maxScore, 8)
        XCTAssertEqual(Scores.stopBang.total(ScoreSelection(on: ["snoring", "tired", "pressure", "age", "gender"])), 5)
        XCTAssertEqual(Scores.stopBang.band(for: 5)?.tone, .high)
        XCTAssertEqual(Scores.stopBang.band(for: 3)?.tone, .moderate)
        XCTAssertEqual(Scores.apfel.total(ScoreSelection(on: ["female", "nonsmoker", "history", "opioids"])), 4)
        XCTAssertEqual(Scores.apfel.band(for: 4)?.label.contains("79%"), true)
    }

    func testAldreteDefaultsToTenAndDischargeThreshold() {
        let def = Scores.aldrete
        XCTAssertEqual(def.total(ScoreSelection()), 10, "the first option of each row is the healthy one")
        XCTAssertEqual(def.band(for: 10)?.tone, .low)
        var s = ScoreSelection()
        s.choices["respiration"] = "Apneic"
        XCTAssertEqual(def.total(s), 8)
        XCTAssertEqual(def.band(for: 8)?.tone, .high)
    }

    func testEveryBandRangeIsCovered() {
        for def in Scores.all {
            for score in 0...def.maxScore {
                XCTAssertNotNil(def.band(for: score), "\(def.id) has a band for \(score)")
            }
        }
    }

    // MARK: Pediatric arithmetic

    func testWeightEstimates() {
        XCTAssertEqual(PedsCalc.estimatedWeight(years: 5, months: 0), 18)
        XCTAssertEqual(PedsCalc.estimatedWeight(years: 0, months: 6), 7)
        XCTAssertEqual(PedsCalc.estimatedWeight(years: 10, months: 0), 37)
        XCTAssertNil(PedsCalc.estimatedWeight(years: 0, months: 0))
        XCTAssertNil(PedsCalc.estimatedWeight(years: 14, months: 0))
    }

    func testAirwaySizes() {
        let four = PedsCalc.ettSizes(years: 4, months: 0)
        XCTAssertEqual(four.uncuffed, "5")
        XCTAssertEqual(four.cuffed, "4.5")
        XCTAssertEqual(PedsCalc.ettDepthOral(years: 4, months: 0, uncuffedID: 5), "14")
        XCTAssertEqual(PedsCalc.ettDepthNasal(years: 4, months: 0), "17")
        XCTAssertEqual(PedsCalc.ettSizes(years: 0, months: 0).cuffed, "3.0")
        XCTAssertEqual(PedsCalc.lmaSize(weightKg: 18), "2")
        XCTAssertEqual(PedsCalc.lmaSize(weightKg: 4), "1")
        XCTAssertEqual(PedsCalc.lmaSize(weightKg: 75), "5")
    }

    func testFluidsAndBlood() {
        XCTAssertEqual(PedsCalc.maintenanceMLPerHour(weightKg: 25), 65)
        XCTAssertEqual(PedsCalc.maintenanceMLPerHour(weightKg: 8), 32)
        let mabl = try! XCTUnwrap(PedsCalc.mabl(ebv: 1000, hctStart: 40, hctMin: 30))
        XCTAssertEqual(mabl, 250, accuracy: 0.01, "EBV × (40 − 30) / 40")
        XCTAssertNil(PedsCalc.mabl(ebv: 1000, hctStart: 30, hctMin: 30))
        let rows = [BloodVolumeRow(group: "Infant", fromMonths: 1, toMonths: 12, mlPerKgLow: 75, mlPerKgHigh: 80),
                    BloodVolumeRow(group: "Child", fromMonths: 12, toMonths: nil, mlPerKgLow: 70, mlPerKgHigh: 75)]
        let child = PedsCalc.bloodVolume(weightKg: 20, ageMonths: 60, rows: rows)
        XCTAssertEqual(child?.row.group, "Child")
        XCTAssertEqual(child?.low, 1400)
    }

    func testDosesAndRounding() {
        let la = PedsCalc.localAnestheticMax(mgPerKg: 2.5, weightKg: 20, percent: 0.25)
        XCTAssertEqual(la.mg, 50)
        XCTAssertEqual(la.mL, 20)
        XCTAssertEqual(PedsCalc.fmt(0.123), "0.12")
        XCTAssertEqual(PedsCalc.fmt(2.25), "2.3")
        XCTAssertEqual(PedsCalc.fmt(12.6), "13")
        XCTAssertEqual(PedsCalc.fmt(18), "18")
        let capped = PedsCalc.doseText(low: 0.01, high: nil, unit: "mg", weightKg: 120, max: 1)
        XCTAssertEqual(capped.text, "1 mg")
        XCTAssertTrue(capped.capped)
        let range = PedsCalc.doseText(low: 2, high: 3, unit: "mg", weightKg: 18, max: nil)
        XCTAssertEqual(range.text, "36–54 mg")
        XCTAssertFalse(range.capped)
        let floored = PedsCalc.doseText(low: 20, high: nil, unit: "mcg", weightKg: 3, min: 100, max: 500)
        XCTAssertEqual(floored.text, "100 mcg", "atropine's minimum applies below 5 kg")
        XCTAssertTrue(floored.capped)
        XCTAssertEqual(PedsCalc.range(70, 70), "70")
        XCTAssertEqual(PedsCalc.range(70, 75), "70–75")
    }

    // MARK: Local anesthetic mixtures

    private var lidocaine: LocalAnesthetic {
        LocalAnesthetic(id: "lidocaine", name: "Lidocaine", maxMgPerKg: 4.5, concentrations: [1, 2], note: nil, source: nil, kind: "amide",
                        adultPlainMgPerKg: 4.5, adultPlainMaxMg: 300, adultEpiMgPerKg: 7, adultEpiMaxMg: 500, per24hMaxMg: nil, pedsEpiMgPerKg: 7, pedsMinYears: nil, pedsMaxMg: nil, short: nil)
    }
    private var bupivacaine: LocalAnesthetic {
        LocalAnesthetic(id: "bupivacaine", name: "Bupivacaine", maxMgPerKg: 2.5, concentrations: [0.25, 0.5], note: nil, source: nil, kind: "amide",
                        adultPlainMgPerKg: 2.5, adultPlainMaxMg: 175, adultEpiMgPerKg: nil, adultEpiMaxMg: 225, per24hMaxMg: 400, pedsEpiMgPerKg: nil, pedsMinYears: nil, pedsMaxMg: nil, short: nil)
    }
    private var exparel: LocalAnesthetic {
        LocalAnesthetic(id: "exparel", name: "Exparel", maxMgPerKg: 4, concentrations: [1.33], note: nil, source: nil, kind: "liposomal",
                        adultPlainMgPerKg: nil, adultPlainMaxMg: 266, adultEpiMgPerKg: nil, adultEpiMaxMg: nil, per24hMaxMg: nil, pedsEpiMgPerKg: nil, pedsMinYears: 6, pedsMaxMg: 266, short: nil)
    }

    func testLocalAnestheticMaxima() {
        XCTAssertEqual(LAMixCalc.maxMg(for: lidocaine, weightKg: 70, pediatric: false, epinephrine: false, ageYears: nil), 300, "4.5 mg/kg × 70 = 315, capped at the label's 300 mg")
        XCTAssertEqual(LAMixCalc.maxMg(for: lidocaine, weightKg: 70, pediatric: false, epinephrine: true, ageYears: nil), 490, "7 mg/kg × 70, under the 500 mg cap")
        XCTAssertEqual(LAMixCalc.maxMg(for: bupivacaine, weightKg: 70, pediatric: false, epinephrine: true, ageYears: nil), 175, "no epinephrine mg/kg on file: the plain per-kg figure applies under the epinephrine cap")
        XCTAssertEqual(LAMixCalc.maxMg(for: bupivacaine, weightKg: 20, pediatric: true, epinephrine: false, ageYears: 5), 50)
        XCTAssertEqual(LAMixCalc.maxMg(for: lidocaine, weightKg: 20, pediatric: true, epinephrine: true, ageYears: 5), 140, "a child gets the 7 mg/kg epinephrine figure too")
        XCTAssertEqual(LAMixCalc.maxMg(for: lidocaine, weightKg: 20, pediatric: true, epinephrine: false, ageYears: 5), 90)
        XCTAssertNil(LAMixCalc.maxMg(for: exparel, weightKg: 20, pediatric: true, epinephrine: false, ageYears: 5), "Exparel is not labeled under 6 years")
        XCTAssertEqual(LAMixCalc.maxMg(for: exparel, weightKg: 20, pediatric: true, epinephrine: false, ageYears: 8), 80)
        XCTAssertEqual(LAMixCalc.maxMg(for: exparel, weightKg: 90, pediatric: false, epinephrine: false, ageYears: nil), 266)
    }

    func testMixtureAddsFractions() {
        let agents = [lidocaine, bupivacaine, exparel]
        let entries = [LAEntry(agentID: "bupivacaine", percent: 0.5, mL: 20), LAEntry(agentID: "lidocaine", percent: 1, mL: 15)]
        let r = LAMixCalc.evaluate(entries: entries, agents: agents, weightKg: 70, pediatric: false, epinephrine: false, ageYears: nil)
        XCTAssertEqual(r.agents[0].mg, 100)
        XCTAssertEqual(r.agents[1].mg, 150)
        XCTAssertEqual(r.combined, 100.0 / 175 + 150.0 / 300, accuracy: 0.0001)
        XCTAssertEqual(r.percentUsed, 107)
        XCTAssertTrue(r.warnings.contains { $0.contains("exceeds the combined maximum") })
        XCTAssertEqual(r.agents[0].maxMLAlone ?? 0, 35, accuracy: 0.001, "175 mg of 0.5% is 35 mL")
        XCTAssertEqual(r.agents[0].remainingML ?? -1, 0, accuracy: 0.001, "nothing left once over the limit")
        let half = LAMixCalc.evaluate(entries: [LAEntry(agentID: "lidocaine", percent: 1, mL: 15)], agents: agents, weightKg: 70, pediatric: false, epinephrine: false, ageYears: nil)
        XCTAssertEqual(half.agents[0].remainingML ?? -1, 15, accuracy: 0.001, "half the lidocaine budget used: 15 mL of 1% remain")
    }

    func testExparelRules() {
        let agents = [lidocaine, bupivacaine, exparel]
        let ratio = LAMixCalc.evaluate(entries: [LAEntry(agentID: "exparel", percent: 1.33, mL: 20), LAEntry(agentID: "bupivacaine", percent: 0.5, mL: 30)],
                                       agents: agents, weightKg: 80, pediatric: false, epinephrine: false, ageYears: nil)
        XCTAssertTrue(ratio.warnings.contains { $0.contains("1:2") }, "150 mg HCl against 266 mg Exparel breaks the 1:2 ratio")
        let fine = LAMixCalc.evaluate(entries: [LAEntry(agentID: "exparel", percent: 1.33, mL: 20), LAEntry(agentID: "bupivacaine", percent: 0.5, mL: 20)],
                                      agents: agents, weightKg: 80, pediatric: false, epinephrine: false, ageYears: nil)
        XCTAssertFalse(fine.warnings.contains { $0.contains("1:2") }, "100 mg HCl is within half of 266 mg")
        let lido = LAMixCalc.evaluate(entries: [LAEntry(agentID: "exparel", percent: 1.33, mL: 10), LAEntry(agentID: "lidocaine", percent: 1, mL: 10)],
                                      agents: agents, weightKg: 80, pediatric: false, epinephrine: false, ageYears: nil)
        XCTAssertTrue(lido.warnings.contains { $0.contains("20 minutes") })
    }

    // MARK: Infusion conversions

    func testInfusionLines() {
        let norepi = InfusionDrug(id: "norepi", name: "Norepinephrine", use: "Hypotension", form: .perKgPerMin, start: 0.05, startHigh: 0.1, unit: "mcg", titration: nil, range: nil, max: nil, bolus: nil, preparation: nil, caution: nil, offLabel: nil, source: "label")
        let a = InfusionCalc.lines(for: norepi, weightKg: 70)
        XCTAssertEqual(a.dose, "0.05–0.1 mcg/kg/min")
        XCTAssertEqual(a.equivalent, "3.5–7 mcg/min at 70 kg")
        XCTAssertNil(InfusionCalc.lines(for: norepi, weightKg: nil).equivalent)
        let ntg = InfusionDrug(id: "ntg", name: "Nitroglycerin", use: "Hypertension", form: .perMin, start: 5, startHigh: nil, unit: "mcg", titration: nil, range: nil, max: nil, bolus: nil, preparation: nil, caution: nil, offLabel: nil, source: "label")
        let b = InfusionCalc.lines(for: ntg, weightKg: 100)
        XCTAssertEqual(b.dose, "5 mcg/min")
        XCTAssertEqual(b.equivalent, "0.05 mcg/kg/min at 100 kg")
        let txa = InfusionDrug(id: "txa", name: "Tranexamic acid", use: "Cardiac surgery load", form: .perKg, start: 30, startHigh: nil, unit: "mg", titration: nil, range: nil, max: nil, bolus: nil, preparation: nil, caution: nil, offLabel: true, source: "BART")
        let c = InfusionCalc.lines(for: txa, weightKg: 70)
        XCTAssertEqual(c.dose, "30 mg/kg")
        XCTAssertEqual(c.equivalent, "2.1 g at 70 kg", "2,100 mg reads as grams")
        XCTAssertEqual(InfusionCalc.total(1500, nil, "mcg"), "1.5 mg")
        XCTAssertEqual(InfusionCalc.total(250, 500, "mg"), "250–500 mg")
    }

    // MARK: Neuraxial timing

    func testNeuraxialTiming() {
        let last = Date(timeIntervalSince1970: 1_700_000_000)
        let apix = NeuraxialTier(id: "high", label: "High", holdHours: 72, restartHours: 24, holdText: nil, restartText: nil, catheter: nil, level: nil, renal: nil, renalNote: nil, removalHours: nil, afterRemovalHours: nil, inrRule: nil)
        let a = NeuraxialCalc.answer(tier: apix, renalIndex: nil, elderly: false, lastDose: last)
        XCTAssertEqual(a.earliest, last.addingTimeInterval(72 * 3600))
        XCTAssertEqual(a.rule, "3 days after the last dose")
        XCTAssertFalse(a.avoid)
        let dabi = NeuraxialTier(id: "high", label: "High", holdHours: 72, restartHours: 24, holdText: nil, restartText: nil, catheter: nil, level: nil,
                                 renal: [RenalRule(label: "CrCl 50 or more", hours: 72, elderlyHours: nil, text: nil), RenalRule(label: "CrCl 30–49", hours: 120, elderlyHours: nil, text: nil), RenalRule(label: "CrCl below 30", hours: nil, elderlyHours: nil, text: "Avoid")],
                                 renalNote: nil, removalHours: nil, afterRemovalHours: nil, inrRule: nil)
        XCTAssertEqual(NeuraxialCalc.answer(tier: dabi, renalIndex: 1, elderly: false, lastDose: last).hours, 120)
        let avoid = NeuraxialCalc.answer(tier: dabi, renalIndex: 2, elderly: false, lastDose: last)
        XCTAssertTrue(avoid.avoid)
        XCTAssertNil(avoid.earliest)
        let fonda = NeuraxialTier(id: "low", label: "Low", holdHours: 36, restartHours: 6, holdText: nil, restartText: nil, catheter: nil, level: nil,
                                  renal: [RenalRule(label: "Normal", hours: 36, elderlyHours: 42, text: nil)], renalNote: nil, removalHours: nil, afterRemovalHours: nil, inrRule: nil)
        XCTAssertEqual(NeuraxialCalc.answer(tier: fonda, renalIndex: 0, elderly: true, lastDose: last).hours, 42)
        XCTAssertEqual(NeuraxialCalc.answer(tier: fonda, renalIndex: 0, elderly: false, lastDose: last).hours, 36)
        XCTAssertEqual(NeuraxialCalc.fmtHours(168), "7 days")
        XCTAssertEqual(NeuraxialCalc.fmtHours(36), "36 h")
        XCTAssertEqual(NeuraxialCalc.countdown(to: last.addingTimeInterval(3600 * 26 + 60 * 5), from: last), "in 1 d 2 h")
        XCTAssertEqual(NeuraxialCalc.countdown(to: last, from: last.addingTimeInterval(10)), "now")
    }

    func testNeuraxialBundleRulesAreComplete() throws {
        let b = try bundled()
        let nx = try XCTUnwrap(b.neuraxial)
        XCTAssertFalse(nx.groups.isEmpty)
        for d in nx.allDrugs {
            XCTAssertFalse(d.tiers.isEmpty, d.id)
            for t in d.tiers where t.holdHours == nil && (t.renal ?? []).isEmpty {
                XCTAssertNotNil(t.holdText, "\(d.id)/\(t.id) has neither hours nor an explanation")
            }
        }
    }

    // MARK: Valve severity (ASE)

    private func valve(_ lesion: ValveLesion, _ numbers: [String: Double] = [:], signs: Set<String> = []) -> ValveReading {
        ValveGrading.read(lesion, ValveInput(numbers: numbers, signs: signs))
    }

    func testValveParamBands() {
        let vc = ValveGrading.params(for: .mr).first { $0.id == "vc" }!
        XCTAssertEqual(vc.grade(0.2), .mild)
        XCTAssertEqual(vc.grade(0.5), .moderate)
        XCTAssertEqual(vc.grade(0.7), .severe)
        let ava = ValveGrading.params(for: .as_).first { $0.id == "ava" }!
        XCTAssertEqual(ava.grade(1.6), .mild)
        XCTAssertEqual(ava.grade(1.2), .moderate)
        XCTAssertEqual(ava.grade(0.8), .severe)
        let jet = ValveGrading.params(for: .tr).first { $0.id == "jet" }!
        XCTAssertNil(jet.grade(6), "TR jet area below 10 cm² is not graded by the tables")
        XCTAssertEqual(jet.grade(12), .severe)
        for lesion in ValveLesion.allCases {
            let ids = ValveGrading.params(for: lesion).map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(lesion) parameter ids are unique")
        }
    }

    func testAorticStenosisPathways() {
        XCTAssertNil(valve(.as_).overall)
        XCTAssertEqual(valve(.as_, ["vmax": 4.2, "mg": 45, "ava": 0.8]).overall, .severe)
        XCTAssertEqual(valve(.as_, ["vmax": 4.1, "ava": 1.3]).overall, .severe, "a high gradient is severe whatever the area")
        XCTAssertFalse(valve(.as_, ["vmax": 4.1, "ava": 1.3]).cautions.isEmpty, "…but the discordance is flagged")
        XCTAssertEqual(valve(.as_, ["vmax": 3.4, "mg": 28, "ava": 1.2]).overall, .moderate)
        XCTAssertEqual(valve(.as_, ["vmax": 2.8, "mg": 15, "ava": 1.7]).overall, .mild)
        XCTAssertEqual(valve(.as_, ["vmax": 2.3]).headline, "Aortic sclerosis")
        // Low gradient, small area: the flow and the ejection fraction decide the pathway.
        let lowGradient = valve(.as_, ["vmax": 3.2, "mg": 25, "ava": 0.9])
        XCTAssertNil(lowGradient.overall)
        XCTAssertTrue(lowGradient.explanation.contains("stroke volume index"))
        XCTAssertEqual(valve(.as_, ["mg": 25, "ava": 0.9, "svi": 40]).overall, .moderate, "normal flow makes severe AS unlikely")
        XCTAssertTrue(valve(.as_, ["mg": 25, "ava": 0.9, "svi": 30, "lvef": 35]).headline.contains("reduced EF"))
        XCTAssertTrue(valve(.as_, ["mg": 25, "ava": 0.9, "svi": 30, "lvef": 60]).headline.contains("Paradoxical"))
    }

    func testMitralRegurgitationIntegration() {
        XCTAssertNil(valve(.mr).overall)
        XCTAssertEqual(valve(.mr, ["vc": 0.8, "pisa": 1.1], signs: ["flail", "pvrev"]).headline, "Definitely severe MR")
        XCTAssertEqual(valve(.mr, ["vc": 0.2, "pisa": 0.2], signs: ["smalljet", "awave"]).headline, "Definitely mild MR")
        XCTAssertEqual(valve(.mr, ["eroa": 0.45]).overall, .severe)
        XCTAssertEqual(valve(.mr, ["eroa": 0.25, "rvol": 40]).overall, .moderate)
        XCTAssertEqual(valve(.mr, ["eroa": 0.15]).overall, .mild)
        XCTAssertEqual(valve(.mr, ["eroa": 0.35]).overall, .moderate, "grade III alone is upper moderate")
        XCTAssertEqual(valve(.mr, ["eroa": 0.35], signs: ["secondary"]).overall, .severe, "grade III reads as severe in secondary MR")
        XCTAssertEqual(valve(.mr, ["eroa": 0.35, "vc": 0.8], signs: ["flail", "pvrev"]).overall, .severe, "grade III with three severe signs")
        XCTAssertNil(valve(.mr, ["eroa": 0.45, "vc": 0.2], signs: ["smalljet"]).overall, "numbers and signs that disagree are indeterminate")
        XCTAssertEqual(valve(.mr, signs: ["flail", "bigjet"]).overall, .severe)
        XCTAssertTrue(valve(.mr, signs: ["flail", "bigjet"]).headline.contains("quantify"))
        XCTAssertFalse(valve(.mr, ["eroa": 0.3], signs: ["nonholo"]).cautions.isEmpty)
    }

    func testMitralStenosis() {
        XCTAssertEqual(valve(.ms, ["mva": 1.2]).overall, .severe)
        XCTAssertEqual(valve(.ms, ["pht": 160]).overall, .severe)
        XCTAssertEqual(valve(.ms, ["mva": 2.0, "pht": 120]).overall, .moderate)
        XCTAssertEqual(valve(.ms, ["mva": 2.8, "pht": 80]).overall, .mild)
        XCTAssertNil(valve(.ms, ["mg": 12]).overall, "a gradient alone does not grade mitral stenosis")
        XCTAssertTrue(valve(.ms, ["mva": 2.0, "mg": 12]).cautions.first?.contains("severe range") ?? false, "a severe-range gradient with a moderate area is flagged")
    }

    func testAorticAndTricuspidRegurgitation() {
        XCTAssertEqual(valve(.ar, ["vc": 0.7], signs: ["holo"]).overall, .severe)
        XCTAssertEqual(valve(.ar, ["rvol": 65, "rf": 55, "eroa": 0.35]).overall, .severe)
        XCTAssertEqual(valve(.ar, ["rvol": 40, "pht": 350]).overall, .moderate)
        XCTAssertEqual(valve(.ar, signs: ["faint"]).overall, .mild)
        XCTAssertEqual(valve(.ar, ["pht": 600]).overall, .mild)
        XCTAssertNil(valve(.ar, ["rvol": 65, "vc": 0.2]).overall, "severe volume with a mild specific sign is indeterminate")
        XCTAssertEqual(valve(.tr, ["vc": 0.8], signs: ["hvrev"]).overall, .severe)
        XCTAssertEqual(valve(.tr, ["eroa": 0.45]).overall, .severe)
        XCTAssertEqual(valve(.tr, ["vc": 0.5, "jet": 6]).overall, .moderate)
        XCTAssertTrue(valve(.tr, ["jet": 6]).lines.contains { $0.id == "jet" && $0.grade == nil })
        XCTAssertEqual(valve(.tr, signs: ["dilated"]).overall, .moderate, "a supportive sign alone only suggests")
    }
}
