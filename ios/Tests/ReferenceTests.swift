import XCTest
import SwiftUI
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
        let esmolol = InfusionDrug(id: "esmolol", name: "Esmolol", use: "Tachycardia", form: .perKgPerMin, start: 50, startHigh: 150, unit: "mcg", titration: nil, range: nil, max: nil, bolus: nil, preparation: nil, caution: nil, offLabel: nil, source: "label")
        XCTAssertEqual(InfusionCalc.lines(for: esmolol, weightKg: 70).equivalent, "3.5–11 mg/min at 70 kg", "mcg/min above 1,000 reads as mg/min")
        let giapreza = InfusionDrug(id: "at2", name: "Angiotensin II", use: "Shock", form: .perKgPerMin, start: 20, startHigh: nil, unit: "ng", titration: nil, range: nil, max: nil, bolus: nil, preparation: nil, caution: nil, offLabel: nil, source: "label")
        XCTAssertEqual(InfusionCalc.lines(for: giapreza, weightKg: 70).equivalent, "1.4 mcg/min at 70 kg")
        let vaso = InfusionDrug(id: "vaso", name: "Vasopressin", use: "Shock", form: .fixed, start: 0.03, startHigh: nil, unit: "units/min", titration: nil, range: nil, max: nil, bolus: nil, preparation: nil, caution: nil, offLabel: nil, source: "label")
        XCTAssertEqual(InfusionCalc.lines(for: vaso, weightKg: 70).dose, "0.03 units/min")
        XCTAssertNil(InfusionCalc.lines(for: vaso, weightKg: 70).equivalent)
    }

    func testInfusionTabsAsReviewed() throws {
        let inf = try XCTUnwrap(try bundled().infusions)
        var tabs: [String] = []
        for g in inf.groups where !tabs.contains(g.tab ?? g.name) { tabs.append(g.tab ?? g.name) }
        XCTAssertEqual(tabs, ["Hemodynamic", "Single-Dose", "Anesthetic", "Blood Products", "Hematologic"])
        XCTAssertEqual(inf.groups.filter { $0.tab == "Hemodynamic" }.map(\.name), ["Vasopressors", "Inotropes", "Vasodilators and Antihypertensives", "Pulmonary Vasodilators"])
        XCTAssertEqual(inf.groups.filter { $0.tab == "Hematologic" }.map(\.name), ["Factor Concentrates", "Antifibrinolytics and Hemostatics", "Anticoagulants", "Reversal Agents"])
        let all = inf.groups.flatMap(\.drugs)
        XCTAssertEqual(all.filter { $0.name.hasPrefix("Epinephrine") }.count, 1, "one epinephrine row")
        let blood = try XCTUnwrap(inf.groups.first { $0.name == "Blood Products" })
        XCTAssertEqual(Set(blood.drugs.map(\.id)), ["red-cells", "plasma", "platelets", "cryoprecipitate"])
        for d in blood.drugs { XCTAssertNotNil(d.threshold, "\(d.id) shows its transfusion threshold") }
        // Rows whose dosing is a formula or protocol show a short dose, not the paragraph.
        for d in all where d.form == .text { XCTAssertNotNil(d.display, "\(d.id) has a short dose for the row") }
        let norepi = try XCTUnwrap(all.first { $0.id == "norepinephrine" })
        XCTAssertEqual(InfusionCalc.lines(for: norepi, weightKg: 80).dose, "4–8 mcg/min")
        XCTAssertEqual(InfusionCalc.lines(for: norepi, weightKg: 80).equivalent, "0.05–0.1 mcg/kg/min at 80 kg")
        let cryo = try XCTUnwrap(blood.drugs.first { $0.id == "cryoprecipitate" })
        XCTAssertEqual(InfusionCalc.lines(for: cryo, weightKg: 70).equivalent, "7–10 units at 70 kg")
        XCTAssertEqual(norepi.nameParts.main, "Norepinephrine")
        XCTAssertEqual(norepi.nameParts.alias, "Levophed")
        XCTAssertNil(try XCTUnwrap(all.first { $0.id == "dobutamine" }).nameParts.alias)
    }

    func testTitleCase() {
        XCTAssertEqual("Blocks on anticoagulants".titleCased, "Blocks on Anticoagulants")
        XCTAssertEqual("Recognize it".titleCased, "Recognize It")
        XCTAssertEqual("Aortic stenosis: low-gradient states".titleCased, "Aortic Stenosis: Low-Gradient States")
        XCTAssertEqual("Cardiac risk for non-cardiac surgery".titleCased, "Cardiac Risk for Non-cardiac Surgery")
        XCTAssertEqual("Doses in mg/kg".titleCased, "Doses in mg/kg")
        XCTAssertEqual("5-HT₃ antagonist".titleCased, "5-HT₃ Antagonist")
        XCTAssertEqual("STOP-Bang and the ASA".titleCased, "STOP-Bang and the ASA")
        XCTAssertEqual("a plan for the airway".titleCased, "A Plan for the Airway")
        XCTAssertEqual("Severe, high-gradient AS".titleCased, "Severe, High-Gradient AS")
        XCTAssertEqual("Local Anesthetic Systemic Toxicity (LAST)".titleCased, "Local Anesthetic Systemic Toxicity (LAST)", "already Title Case stays")
    }

    func testPONVPlan() throws {
        let ponv = try XCTUnwrap(try bundled().ponv)
        XCTAssertEqual(PONVPlan.target(factors: 0, counts: ponv.counts)?.agents, 2)
        XCTAssertEqual(PONVPlan.target(factors: 2, counts: ponv.counts)?.agents, 2)
        XCTAssertEqual(PONVPlan.target(factors: 3, counts: ponv.counts)?.agents, 3)
        XCTAssertEqual(PONVPlan.target(factors: 4, counts: ponv.counts)?.agentsHigh, 4)
        XCTAssertEqual(PONVPlan.classes(of: ["ondansetron", "granisetron", "dexamethasone"], in: ponv.agents), ["5-HT₃ antagonist", "Corticosteroid"], "two 5-HT₃ antagonists count once")
        let rescue = PONVPlan.rescueOptions(chosen: ["ondansetron", "dexamethasone"], agents: ponv.agents).map(\.id)
        XCTAssertFalse(rescue.contains("ondansetron"))
        XCTAssertFalse(rescue.contains("granisetron"), "no 5-HT₃ antagonist again within 6 h")
        XCTAssertTrue(rescue.contains("amisulpride"))
        XCTAssertTrue(rescue.contains("propofol"))
        XCTAssertEqual(ponv.agents.first { $0.id == "amisulpride" }?.rescueDose, "10 mg IV")
        XCTAssertEqual(PONVPlan.longActingGiven(chosen: ["palonosetron", "dexamethasone"], agents: ponv.agents).map(\.id), ["palonosetron"])
        XCTAssertFalse(ponv.agents.filter { $0.prophylaxis != false }.contains { $0.id == "propofol" }, "propofol is rescue only")
        // The card's table and the tool share one list.
        let card = try XCTUnwrap(try bundled().quickrefs.first { $0.id == "ponv-consensus" })
        let table = try XCTUnwrap(card.sections.first { $0.kind == .table })
        XCTAssertEqual(table.rows?.map { $0.first ?? "" }, ponv.agents.filter { $0.prophylaxis != false }.map(\.name))
    }

    @MainActor func testFavoritesMigrateMergedTools() {
        XCTAssertEqual(FavoritesStore.migrate(["score:rcri", "score:apfel", "quickref:ponv-consensus", "valves"]), ["score:rcri", "ponv", "valves"])
        XCTAssertEqual(RefRoute(key: "ponv"), .ponv)
        XCTAssertNotNil(RefItem.item(forKey: "ponv"))
        XCTAssertEqual(RefItem.folder(of: .neuraxial), .regional)
        XCTAssertEqual(RefItem.folder(of: .local), .regional)
        XCTAssertEqual(RefItem.folder(of: .valves), .cardiothoracic)
        XCTAssertEqual(RefItem.folder(of: .intervention), .cardiothoracic)
        XCTAssertEqual(RefItem.item(for: .valves)?.title, "ASE Valve Severity Grading")
        XCTAssertEqual(RefItem.item(for: .intervention)?.title, "AHA/ACC Valve Intervention")
        XCTAssertFalse(RefFolder.preoperative.items.contains { $0.route == .valves || $0.route == .intervention })
        XCTAssertEqual(RefFolder.medications.route, .infusions, "a one-tool folder opens the tool")
        XCTAssertEqual(RefFolder.pediatrics.route, .peds)
        XCTAssertEqual(RefFolder.cardiothoracic.route, .folder(.cardiothoracic))
    }

    func testNewerFileWinsBySameDayStamp() throws {
        var a = try bundled()
        var b = a
        a.revision = 100; b.revision = 200
        XCTAssertTrue(b.isAtLeastAsNew(as: a))
        XCTAssertFalse(a.isAtLeastAsNew(as: b), "same date: the later build stamp wins")
        b.updated = "2000-01-01"
        XCTAssertTrue(a.isAtLeastAsNew(as: b), "a later date wins whatever the stamps")
        a.revision = nil; b = a
        XCTAssertTrue(a.isAtLeastAsNew(as: b), "identical files tie, and a tie keeps the download")
    }

    func testOlderServerFileDoesNotHideNewSections() throws {
        let b = try bundled()
        var server = b
        server.infusions = nil
        server.neuraxial = nil
        server.ask = AskConfig(endpoint: "https://ask.example.workers.dev/ask")
        let merged = server.filling(from: b)
        XCTAssertNotNil(merged.infusions, "the app's own infusion table survives a server file written before it existed")
        XCTAssertNotNil(merged.neuraxial)
        XCTAssertEqual(merged.ask?.endpoint, "https://ask.example.workers.dev/ask", "the server's endpoint is kept")
        XCTAssertEqual(b.filling(from: server).ask?.endpoint, "https://ask.example.workers.dev/ask", "…and reaches a newer bundled copy too")
    }

    func testInfusionBundleIsComplete() throws {
        let b = try bundled()
        let inf = try XCTUnwrap(b.infusions)
        XCTAssertGreaterThanOrEqual(inf.groups.count, 5)
        let all = inf.groups.flatMap(\.drugs)
        XCTAssertGreaterThanOrEqual(all.count, 40)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "infusion ids are unique")
        for d in all {
            XCTAssertFalse(d.source?.isEmpty ?? true, "\(d.id) cites a source")
            if d.form != .text {
                XCTAssertNotNil(d.start, "\(d.id) has a starting dose")
                XCTAssertNotNil(d.unit, "\(d.id) has a unit")
            } else {
                XCTAssertNotNil(d.range, "\(d.id): a text row carries its dosing in range")
            }
            // Every row renders a dose line, with and without a weight.
            XCTAssertFalse(InfusionCalc.lines(for: d, weightKg: nil).dose.isEmpty, d.id)
            XCTAssertFalse(InfusionCalc.lines(for: d, weightKg: 70).dose.isEmpty, d.id)
        }
        for g in inf.groups {
            let names = g.drugs.map { $0.name.lowercased() }
            XCTAssertEqual(names, names.sorted(), "\(g.name) is alphabetical")
        }
        let wanted = ["phenylephrine", "norepinephrine", "epinephrine", "vasopressin", "nitroglycerin", "nitroprusside", "esmolol", "clevidipine", "nicardipine", "milrinone", "dobutamine", "tranexamic", "aminocaproic", "iepo", "ino", "factor-viia", "pcc", "antithrombin",
                      "bivalirudin", "insulin", "amiodarone", "propofol", "dexmedetomidine", "lidocaine-iv", "ketamine", "remifentanil", "red-cells", "phenylephrine-bolus"]
        for id in wanted { XCTAssertTrue(all.contains { $0.id == id }, "\(id) is in the table") }
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
        XCTAssertEqual(NeuraxialCalc.answer(tier: dabi, renalIndex: 1, elderly: false, lastDose: last).rule, "5 days after the last dose (CrCl 30–49)", "acronyms in the kidney label keep their case")
        XCTAssertEqual(NeuraxialCalc.softLowercased("Normal renal function"), "normal renal function")
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

    // MARK: Valve intervention (ACC/AHA 2020)

    private func vi(_ lesion: VILesion, _ answers: [String: String]) -> VIResult { ValveIntervention.evaluate(lesion, answers: answers) }
    private func ids(_ r: VIResult) -> [String] { r.matched.map(\.id) }

    func testInterventionRulesReferToRealQuestions() {
        for lesion in VILesion.allCases {
            let qs = ValveIntervention.questions(for: lesion)
            let qids = Set(qs.map(\.id))
            XCTAssertEqual(qids.count, qs.count, "\(lesion) question ids are unique")
            let rules = ValveIntervention.rules(for: lesion)
            XCTAssertEqual(Set(rules.map(\.id)).count, rules.count, "\(lesion) rule ids are unique")
            for r in rules {
                for conj in r.when {
                    for c in conj {
                        let q = qs.first { $0.id == c.question }
                        XCTAssertNotNil(q, "\(lesion) rule \(r.id) asks for unknown question \(c.question)")
                        if let q { XCTAssertTrue(c.any.isSubset(of: Set(q.options)), "\(lesion) rule \(r.id): \(c.any) are not options of \(q.id)") }
                    }
                }
            }
        }
    }

    func testAorticStenosisIntervention() {
        XCTAssertNil(vi(.as_, [:]).fallback)
        XCTAssertFalse(vi(.as_, [:]).needed.isEmpty, "with nothing answered the tool asks")
        let d1 = vi(.as_, ["sev": "Severe", "sx": "Yes"])
        XCTAssertEqual(d1.matched.first?.id, "as-d1")
        XCTAssertTrue(d1.needed.contains("age"), "once AVR is indicated the procedure questions are asked")
        XCTAssertEqual(vi(.as_, ["sev": "Severe", "sx": "Yes", "age": "< 50", "risk": "Low", "anticoag": "Yes"]).matched.map(\.id), ["as-d1", "as-savr-age", "pr-ao-young"])
        XCTAssertTrue(ids(vi(.as_, ["sev": "Severe", "sx": "Yes", "age": "> 80", "risk": "Low", "tf": "Yes"])).contains("as-tavi-age"))
        XCTAssertTrue(ids(vi(.as_, ["sev": "Severe", "sx": "Yes", "age": "50–64", "risk": "High or prohibitive", "survival": "Yes"])).contains("as-tavi-risk"))
        XCTAssertFalse(ids(vi(.as_, ["sev": "Severe", "sx": "Yes", "age": "50–64", "risk": "High or prohibitive", "survival": "Yes"])).contains("as-savr-age"), "the age rule is for operable patients")
        XCTAssertTrue(ids(vi(.as_, ["sev": "Severe", "sx": "Yes", "survival": "No"])).contains("as-pall"))
        XCTAssertEqual(vi(.as_, ["sev": "Severe", "sx": "No", "ef": "< 50%"]).matched.first?.id, "as-c2")
        XCTAssertEqual(vi(.as_, ["sev": "Low-flow, low-gradient", "sx": "Yes", "ef": "< 50%"]).matched.first?.id, "as-d2")
        XCTAssertEqual(vi(.as_, ["sev": "Low-flow, low-gradient", "sx": "Yes", "ef": "≥ 60%"]).matched.first?.id, "as-d3")
        XCTAssertEqual(vi(.as_, ["sev": "Very severe", "sx": "No", "risk": "Low"]).matched.first?.cls, .twoA)
        XCTAssertEqual(vi(.as_, ["sev": "Moderate", "surg": "Yes"]).matched.first?.cls, .twoB)
        let watch = vi(.as_, ["sev": "Moderate", "sx": "No", "surg": "No", "ef": "≥ 60%", "risk": "Low", "markers": "No", "effall": "No"])
        XCTAssertTrue(watch.matched.isEmpty)
        XCTAssertNotNil(watch.fallback, "nothing met and nothing pending → surveillance")
        XCTAssertTrue(watch.fallback?.contains("1–2 years") ?? false)
    }

    func testRegurgitationAndStenosisIntervention() {
        XCTAssertEqual(vi(.ar, ["sev": "Severe", "sx": "Yes"]).matched.first?.id, "ar-d")
        XCTAssertEqual(vi(.ar, ["sev": "Severe", "sx": "No", "ef": "≤ 55%"]).matched.first?.id, "ar-c2")
        XCTAssertEqual(vi(.ar, ["sev": "Severe", "sx": "No", "ef": "> 60%", "lvesd": "Yes"]).matched.first?.id, "ar-c2-dim")
        XCTAssertEqual(vi(.ar, ["sev": "Severe", "sx": "No", "ef": "> 60%", "lvesd": "No", "risk": "Low", "lvedd": "Yes"]).matched.first?.id, "ar-2b")
        XCTAssertTrue(ids(vi(.ar, ["sev": "Severe", "sx": "Yes", "candidate": "Yes"])).contains("ar-tavi"), "the harm line shows once surgery is indicated")
        XCTAssertFalse(ids(vi(.ar, ["sev": "Moderate", "sx": "No", "surg": "No", "candidate": "Yes"])).contains("ar-tavi"))

        XCTAssertEqual(vi(.mrPrimary, ["sev": "Severe", "sx": "Yes"]).matched.first?.id, "mr-d")
        XCTAssertEqual(vi(.mrPrimary, ["sev": "Severe", "sx": "No", "lvesd": "Yes"]).matched.first?.id, "mr-c2")
        XCTAssertEqual(vi(.mrPrimary, ["sev": "Severe", "sx": "No", "ef": "> 60%", "lvesd": "No", "durable": "Yes"]).matched.first?.id, "mr-c1")
        let teer = vi(.mrPrimary, ["sev": "Severe", "sx": "Yes", "nyha": "III–IV", "risk": "High or prohibitive", "anatomy": "Yes", "rheumatic": "No"])
        XCTAssertEqual(ids(teer).prefix(2), ["mr-d", "mr-teer"])
        XCTAssertTrue(ids(teer).contains("mr-repair"))
        XCTAssertTrue(ids(vi(.mrPrimary, ["sev": "Severe", "sx": "Yes", "posterior": "Yes"])).contains("mr-posterior"))

        XCTAssertEqual(vi(.mrSecondary, ["sev": "Severe", "hf": "Yes"]).matched.first?.id, "smr-gdmt")
        let smrTeer = vi(.mrSecondary, ["sev": "Severe", "hf": "Yes", "gdmt": "Yes", "nyha": "III–IV", "ef": "20–49%", "lvesd70": "Yes", "pasp70": "Yes", "anatomy": "Yes"])
        XCTAssertTrue(ids(smrTeer).contains("smr-teer"))
        XCTAssertTrue(ids(smrTeer).contains("smr-surg"))
        XCTAssertEqual(ids(smrTeer).first, "smr-gdmt", "medical therapy stays first")
        XCTAssertEqual(vi(.mrSecondary, ["sev": "Severe", "hf": "No", "gdmt": "Yes", "nyha": "III–IV", "ef": "≥ 50%", "af": "Yes"]).matched.first?.id, "smr-atrial")

        XCTAssertEqual(vi(.ms, ["sev": "Severe (MVA ≤ 1.5 cm²)", "nyha": "II", "pmbc": "Yes", "calcific": "No"]).matched.first?.id, "ms-pmbc")
        XCTAssertEqual(vi(.ms, ["sev": "Severe (MVA ≤ 1.5 cm²)", "nyha": "III–IV", "pmbc": "No", "calcific": "No", "candidate": "Yes"]).matched.first?.id, "ms-surg")
        XCTAssertEqual(vi(.ms, ["sev": "Severe (MVA ≤ 1.5 cm²)", "nyha": "III–IV", "pmbc": "No", "calcific": "No", "candidate": "No"]).matched.first?.id, "ms-highrisk")
        XCTAssertEqual(vi(.ms, ["sev": "Severe (MVA ≤ 1.5 cm²)", "nyha": "I", "pasp": "Yes", "pmbc": "Yes"]).matched.first?.id, "ms-pasp")
        XCTAssertEqual(vi(.ms, ["sev": "Not severe (MVA > 1.5 cm²)", "nyha": "II", "exercise": "Yes"]).matched.first?.id, "ms-ex")
        XCTAssertEqual(vi(.ms, ["calcific": "Yes", "nyha": "III–IV", "sev": "Severe (MVA ≤ 1.5 cm²)", "pmbc": "Yes"]).matched.first?.id, "ms-mac", "calcific stenosis is not a PMBC case")

        XCTAssertEqual(vi(.tr, ["sev": "Severe", "left": "Yes"]).matched.first?.id, "tr-left")
        XCTAssertEqual(vi(.tr, ["sev": "Progressive (moderate)", "left": "Yes", "annulus": "Yes"]).matched.first?.id, "tr-prog")
        XCTAssertEqual(vi(.tr, ["sev": "Severe", "cause": "Primary (leaflet)", "rhf": "Yes", "left": "No"]).matched.first?.id, "tr-primary")
        XCTAssertEqual(vi(.tr, ["sev": "Severe", "cause": "Secondary (annular dilation)", "rhf": "Yes", "left": "No", "ph": "No", "medical": "Yes"]).matched.first?.id, "tr-secondary")
        XCTAssertEqual(vi(.tr, ["sev": "Severe", "prior": "Yes", "rhf": "Yes", "severeph": "No"]).matched.first?.id, "tr-redo")
        let trWatch = vi(.tr, ["sev": "Progressive (moderate)", "left": "No", "cause": "Secondary (annular dilation)", "rhf": "No", "prior": "No"])
        XCTAssertTrue(trWatch.matched.isEmpty)
        XCTAssertNotNil(trWatch.fallback)
    }

    // MARK: Echo chamber quantification

    private func measure(_ id: String, dir: String? = nil, edge: String? = nil, word: String, male: EchoRef? = nil, all: EchoRef? = nil, index: String? = nil) -> EchoMeasure {
        EchoMeasure(id: id, name: id, short: nil, unit: "mm", rawUnit: nil, method: nil, dir: dir, index: index, edge: edge, word: word, male: male, female: nil, all: all, source: "test", ref: nil, note: nil)
    }

    func testEchoGrading() {
        let lv = measure("lvedd", word: "dilated", male: EchoRef(normal: [42, 58.4], cuts: [58.4, 63, 68]))
        XCTAssertEqual([40, 50, 58.4, 58.5, 63, 63.1, 68, 70].map { EchoCalc.grade(lv, .male, $0) }, [-1, 0, 0, 1, 1, 2, 2, 3])
        XCTAssertEqual(EchoCalc.label(lv, 2), "Moderately dilated")
        XCTAssertNil(EchoCalc.grade(lv, .female, 60), "no female values in this example")
        let ef = measure("lvef", dir: "low", word: "reduced", male: EchoRef(normal: [52, 72], cuts: [52, 41, 30]))
        XCTAssertEqual([75, 60, 52, 51.5, 41, 40, 30, 29].map { EchoCalc.grade(ef, .male, $0) }, [-1, 0, 0, 1, 1, 2, 2, 3])
        XCTAssertEqual(EchoCalc.label(ef, -1), "Above the normal range")
        let ta = measure("ta", edge: "inclusive", word: "dilated", all: EchoRef(normal: nil, cuts: [40]))
        XCTAssertEqual([39.9, 40, 41].map { EchoCalc.grade(ta, .female, $0) }, [0, 4, 4], "≥ 40 mm: the cutoff itself is dilated")
        XCTAssertEqual(EchoCalc.label(ta, 4), "Dilated")
        let lavi = measure("lavi", word: "dilated", all: EchoRef(normal: nil, cuts: [34, 41, 48]), index: "bsa")
        XCTAssertEqual(EchoCalc.value(lavi, text: "50", raw: true, bsa: 2), 25)
        XCTAssertNil(EchoCalc.value(lavi, text: "50", raw: true, bsa: nil), "a raw volume needs the body surface area")
        XCTAssertEqual(EchoCalc.bands(ef, .male).map(\.grade), [3, 2, 1, 0, -1])
        XCTAssertEqual(EchoCalc.bands(lv, .male).map(\.grade), [-1, 0, 1, 2, 3])
        XCTAssertEqual(EchoCalc.bsa(heightCm: 175, weightKg: 70, formula: nil) ?? 0, 1.848, accuracy: 0.001)
        XCTAssertEqual(EchoCalc.bsa(heightCm: 175, weightKg: 70, formula: "mosteller") ?? 0, 1.845, accuracy: 0.001)
        XCTAssertEqual(EchoCalc.rap(ivcCm: 1.8, collapses: true, cut: nil)?.label, "Normal")
        XCTAssertEqual(EchoCalc.rap(ivcCm: 2.4, collapses: false, cut: nil)?.label, "Elevated")
        XCTAssertEqual(EchoCalc.rap(ivcCm: 1.8, collapses: false, cut: nil)?.label, "Indeterminate")
        XCTAssertEqual(EchoCalc.rap(ivcCm: 1.8, collapses: true, cut: nil).flatMap(\.value), 3)
    }

    func testEchoEdgesRangesIndexedAndAgeTables() {
        // ASE 2025 RV basal diameter: normal < 4.1, mild ≥ 4.1 to ≤ 4.4, moderate > 4.4 to ≤ 4.9, severe > 4.9
        var rvb = measure("rvb", word: "dilated", all: EchoRef(normal: nil, cuts: [4.1, 4.4, 4.9]))
        rvb.edges = ["inclusive", "exclusive", "exclusive"]
        rvb.indexed = EchoIndexed(unit: "cm/m²", edge: nil, edges: ["inclusive", "exclusive", "exclusive"], male: nil, female: nil, all: EchoRef(normal: nil, cuts: [2.4, 2.6, 2.9]))
        XCTAssertEqual([4.0, 4.1, 4.4, 4.41, 4.9, 4.91].map { EchoCalc.grade(rvb, .male, $0) }, [0, 1, 1, 2, 2, 3])
        XCTAssertEqual(EchoCalc.ranges(rvb, .male).map(\.text).joined(separator: " · "), "Normal < 4.1 · mild ≤ 4.4 · moderate ≤ 4.9 · severe > 4.9")
        let ix = try? XCTUnwrap(EchoCalc.indexed(rvb))
        XCTAssertEqual(ix?.unit, "cm/m²")
        XCTAssertEqual(ix.flatMap { EchoCalc.grade($0, .female, 2.4) }, 1)
        XCTAssertEqual(ix.flatMap { EchoCalc.grade($0, .female, 2.39) }, 0)
        // TAPSE: normal > 1.7, mild ≤ 1.7 to > 1.3, moderate ≤ 1.3 to > 1.0, severe ≤ 1.0
        var tapse = measure("tapse", dir: "low", word: "reduced", all: EchoRef(normal: nil, cuts: [1.7, 1.3, 1.0]))
        tapse.edges = ["inclusive", "inclusive", "inclusive"]
        XCTAssertEqual([1.8, 1.7, 1.31, 1.3, 1.01, 1.0].map { EchoCalc.grade(tapse, .male, $0) }, [0, 1, 1, 2, 2, 3])
        XCTAssertEqual(EchoCalc.ranges(tapse, .male).map(\.text).joined(separator: " · "), "Normal > 1.7 · mild > 1.3 · moderate > 1 · severe ≤ 1")
        let tb = EchoCalc.bands(tapse, .male)
        XCTAssertEqual(tb.last?.to ?? 0, 2.4, accuracy: 1e-9)
        XCTAssertEqual(tb.map(\.grade), [3, 2, 1, 0])
        // 3D RVEF: moderate ≤ 39 to ≥ 32, severe < 32
        var rvef = measure("rvef", dir: "low", word: "reduced", all: EchoRef(normal: nil, cuts: [45, 39, 32]))
        rvef.edges = ["inclusive", "inclusive", "exclusive"]
        XCTAssertEqual([46.0, 45, 39, 32, 31.9].map { EchoCalc.grade(rvef, .male, $0) }, [0, 1, 2, 2, 3])
        XCTAssertEqual(EchoCalc.ranges(rvef, .male).map(\.text).joined(separator: " · "), "Normal > 45 · mild > 39 · moderate ≥ 32 · severe < 32")
        let ef = measure("lvef", dir: "low", word: "reduced", male: EchoRef(normal: [52, 72], cuts: [52, 41, 30]))
        XCTAssertEqual(EchoCalc.ranges(ef, .male).map(\.text).joined(separator: " · "), "Normal 52–72 · mild ≥ 41 · moderate ≥ 30 · severe < 30")
        let lvidd = measure("lvidd", word: "dilated", male: EchoRef(normal: [42, 58.4], cuts: [58.4]))
        XCTAssertEqual(EchoCalc.ranges(lvidd, .male).map(\.text).joined(separator: " · "), "Normal 42–58.4 · dilated > 58.4")
        var ta = measure("ta", edge: "inclusive", word: "dilated", all: EchoRef(normal: nil, cuts: [40]))
        ta.indexed = EchoIndexed(unit: "mm/m²", edge: nil, edges: nil, male: nil, female: nil, all: EchoRef(normal: nil, cuts: [21]))
        XCTAssertEqual(EchoCalc.ranges(ta, .male).map(\.text).joined(separator: " · "), "Normal < 40 · dilated ≥ 40")
        XCTAssertEqual(EchoCalc.indexed(ta).map { EchoCalc.ranges($0, .male).map(\.text).joined(separator: " · ") }, "Normal ≤ 21 · dilated > 21", "the indexed cut keeps its own edge")
        XCTAssertEqual(EchoCalc.bands(ta, .male).map { [$0.from, $0.to, Double($0.grade)] }, [[30, 40, 0], [40, 50, 4]])
        // strain is tabulated as magnitude
        var strain = measure("rvfws", dir: "low", word: "reduced", all: EchoRef(normal: nil, cuts: [20, 15, 11]))
        strain.abs = true
        XCTAssertEqual(EchoCalc.value(strain, text: "-22", raw: false, bsa: nil), 22)
        XCTAssertNil(EchoCalc.value(tapse, text: "-22", raw: false, bsa: nil))
        // Goldstein 2015 aortic sinuses: men 50–59 4.0 cm at BSA 2.0, ± 0.5 mm per 0.1 m²; z ≥ 2 is dilated
        var sov = measure("sov", edge: "inclusive", word: "dilated")
        sov.byAge = EchoByAge(perM2: 0.5,
                              male: EchoAgeTable(refBsa: 2.0, rows: [EchoAgeRow(from: 15, to: 29, uln: 3.7), EchoAgeRow(from: 50, to: 59, uln: 4.0), EchoAgeRow(from: 70, to: nil, uln: 4.2)]),
                              female: EchoAgeTable(refBsa: 1.7, rows: [EchoAgeRow(from: 50, to: 59, uln: 3.6)]))
        XCTAssertEqual(EchoCalc.ageLimit(sov, .male, EchoCalc.Context(age: 55, bsa: 2.2))?.value, 4.1)
        XCTAssertEqual(EchoCalc.ageLimit(sov, .male, EchoCalc.Context(age: 55, bsa: nil))?.value, 4.0, "no BSA: the reference-BSA limit")
        XCTAssertEqual(EchoCalc.ageLimit(sov, .female, EchoCalc.Context(age: 59.9, bsa: 1.5))?.value, 3.5)
        XCTAssertEqual(EchoCalc.ageLimit(sov, .male, EchoCalc.Context(age: 88, bsa: 2.0))?.value, 4.2, "open-ended top band")
        XCTAssertNil(EchoCalc.ageLimit(sov, .male, EchoCalc.Context(age: 12, bsa: 2.0)), "the adult tables start at 15")
        XCTAssertEqual([4.05, 4.1].map { EchoCalc.grade(sov, .male, $0, EchoCalc.Context(age: 55, bsa: 2.2)) }, [0, 4])
        XCTAssertNil(EchoCalc.grade(sov, .male, 4.1), "no age, no grade")
        // RA pressure on positive-pressure ventilation
        XCTAssertEqual(EchoCalc.rap(ivcCm: 2.4, collapses: nil, cut: 2.1, ventilated: true)?.label, "Not estimable")
        XCTAssertEqual(EchoCalc.rap(ivcCm: 1.9, collapses: nil, cut: 2.1, ventilated: true, ventCut: 1.2)?.label, "Not estimable", "ventilated: 1.2 cm (ASE 2010), not 2.1")
        XCTAssertEqual(EchoCalc.rap(ivcCm: 1.2, collapses: nil, cut: 2.1, ventilated: true, ventCut: 1.2)?.label, "Likely below 10 mmHg")
        XCTAssertEqual(EchoCalc.rap(ivcCm: 1.1, collapses: nil, cut: 2.1, ventilated: true)?.label, "Likely below 10 mmHg", "defaults to 1.2 cm")
        XCTAssertNil(EchoCalc.rap(ivcCm: 1.9, collapses: nil, cut: 2.1, ventilated: false), "spontaneous breathing needs the sniff")
        XCTAssertEqual([EchoCalc.fmt(58.4), EchoCalc.fmt(3.85000001), EchoCalc.fmt(145.26)], ["58.4", "3.85", "145.3"])
    }

    func testEchoBundleDrawsEveryRow() throws {
        guard let echo = try bundled().echo else { return }
        var ids = Set<String>()
        let ctx = EchoCalc.Context(age: 50, bsa: 1.9)
        for m in echo.groups.flatMap(\.measures) {
            XCTAssertTrue(ids.insert(m.id).inserted, "\(m.id) is unique")
            for row in [m, EchoCalc.indexed(m)].compactMap({ $0 }) {
                for sex in EchoSex.allCases {
                    XCTAssertNotNil(EchoCalc.ref(row, sex, ctx), "\(m.id) has \(sex) values")
                    let b = EchoCalc.bands(row, sex, ctx)
                    XCTAssertGreaterThanOrEqual(b.count, 2, "\(m.id) draws a strip")
                    for i in b.indices.dropFirst() { XCTAssertEqual(b[i].from, b[i - 1].to, accuracy: 1e-9, "\(m.id) bands are contiguous") }
                    XCTAssertGreaterThanOrEqual(EchoCalc.ranges(row, sex, ctx).count, 2, "\(m.id) states its ranges")
                }
            }
        }
        // spot checks against the printed tables (mirrors tools/test_reference_logic.js)
        let all = echo.groups.flatMap(\.measures)
        func m(_ id: String) throws -> EchoMeasure { try XCTUnwrap(all.first { $0.id == id }, id) }
        XCTAssertEqual(try [4.0, 4.1, 4.4, 4.45, 4.9, 4.95].map { EchoCalc.grade(try m("rvb"), .male, $0) }, [0, 1, 1, 2, 2, 3], "ASE 2025 RV basal diameter")
        XCTAssertEqual(try [1.75, 1.7, 1.3, 1.0].map { EchoCalc.grade(try m("tapse"), .female, $0) }, [0, 1, 2, 3], "ASE 2025 TAPSE")
        XCTAssertEqual(try [34.0, 34.5, 41, 48, 48.5].map { EchoCalc.grade(try m("lavi"), .male, $0) }, [0, 1, 1, 2, 3], "Lang 2015 LA volume index")
        XCTAssertEqual(try [54.0, 53, 41, 40, 29].map { EchoCalc.grade(try m("lvef"), .female, $0) }, [0, 1, 1, 2, 3], "Lang 2015 LVEF, women")
        XCTAssertEqual(try [39.0, 40].map { EchoCalc.grade(try m("ta"), .male, $0) }, [0, 4], "tricuspid annulus ≥ 40 mm")
        let taIndexed = try XCTUnwrap(EchoCalc.indexed(try m("ta")))
        XCTAssertEqual([21.0, 21.5].map { EchoCalc.grade(taIndexed, .male, $0) }, [0, 4], "tricuspid annulus > 21 mm/m²")
        XCTAssertEqual(EchoCalc.ageLimit(try m("sov"), .female, EchoCalc.Context(age: 45, bsa: 1.7))?.value, 3.6, "Goldstein 2015 women 40–49")
        // Lang 2015 Supplemental Table 3: mild, moderate and severe for LV size, wall thickness and mass
        XCTAssertEqual(try [58.4, 58.5, 63, 64, 68, 69].map { EchoCalc.grade(try m("lvidd"), .male, $0) }, [0, 1, 1, 2, 2, 3], "LV end-diastolic diameter, men (mm)")
        XCTAssertEqual(try [52.2, 53, 56, 57, 61, 62].map { EchoCalc.grade(try m("lvidd"), .female, $0) }, [0, 1, 1, 2, 2, 3], "LV end-diastolic diameter, women (mm)")
        XCTAssertEqual(try [1.0, 1.05, 1.3, 1.4, 1.6, 1.7].map { EchoCalc.grade(try m("ivsd"), .male, $0) }, [0, 1, 1, 2, 2, 3], "septum, men")
        XCTAssertEqual(try [0.9, 1.0, 1.2, 1.3, 1.5, 1.6].map { EchoCalc.grade(try m("pwd"), .female, $0) }, [0, 1, 1, 2, 2, 3], "posterior wall, women")
        XCTAssertEqual(try [115.0, 116, 131, 132, 148, 149].map { EchoCalc.grade(try m("lvmi"), .male, $0) }, [0, 1, 1, 2, 2, 3], "LV mass index (linear), men")
        // RV free-wall strain: normal limit by sex (2025 strain consensus); the limit itself is normal
        XCTAssertEqual(try [20.0, 19.9, 15, 14.9, 11, 10.9].map { EchoCalc.grade(try m("rvfws"), .male, $0) }, [0, 1, 1, 2, 2, 3], "free-wall strain, men")
        XCTAssertEqual(try [21.0, 20.5, 15, 11, 10.9].map { EchoCalc.grade(try m("rvfws"), .female, $0) }, [0, 1, 1, 2, 3], "free-wall strain, women")
        // main PA diameter (ASE 2025 Table 1, May 2025 file)
        XCTAssertEqual(try [2.5, 2.6, 3.0, 3.1, 3.5, 3.6].map { EchoCalc.grade(try m("pa"), .male, $0) }, [0, 1, 1, 2, 2, 3], "PA diameter")
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

    // MARK: ASE 2025 diastolic function (mirrors tools/test_reference_logic.js)

    private func ddInput(_ v: [String: Double], lung: Bool = false, age: String? = nil) -> DiastolicCalc.Input {
        var i = DiastolicCalc.Input()
        i.E = v["E"]; i.A = v["A"]; i.eSeptal = v["eSeptal"]; i.eLateral = v["eLateral"]; i.pasp = v["pasp"]; i.tr = v["tr"]
        i.pvsd = v["pvsd"]; i.lars = v["lars"]; i.lavi = v["lavi"]; i.ivrt = v["ivrt"]
        i.prEdv = v["prEdv"]; i.padp = v["padp"]; i.lwave = v["lwave"]; i.ara = v["ara"]; i.valsalva = v["valsalva"]
        i.esr = v["esr"]; i.lvmi = v["lvmi"]; i.lvef = v["lvef"]
        i.lungDisease = lung; i.ageBand = age
        return i
    }

    func testDiastolicFigure3() {
        func dd(_ v: [String: Double], lung: Bool = false) -> DiastolicCalc.Reading { DiastolicCalc.read(ddInput(v, lung: lung)) }
        var r = dd(["E": 80, "A": 60, "eSeptal": 9, "eLateral": 12, "tr": 2.3])
        XCTAssertEqual(r.lap, .normal); XCTAssertEqual(r.grade, 0)
        r = dd(["E": 100, "A": 80, "eSeptal": 5, "eLateral": 6, "tr": 3.0])
        XCTAssertEqual(r.lap, .increased); XCTAssertEqual(r.grade, 2, "E/A 1.25 is Grade 2")
        r = dd(["E": 120, "A": 50, "eSeptal": 5, "eLateral": 6, "tr": 3.0])
        XCTAssertEqual(r.lap, .increased); XCTAssertEqual(r.grade, 3, "E/A 2.4 is Grade 3")
        r = dd(["E": 50, "A": 80, "eSeptal": 5, "eLateral": 6.5, "tr": 2.2])
        XCTAssertEqual(r.lap, .normal); XCTAssertEqual(r.grade, 1, "e′ alone with E/A 0.8 or less")
        r = dd(["E": 70, "A": 70, "eSeptal": 5, "eLateral": 6.5, "tr": 2.2, "lars": 30, "lavi": 28])
        XCTAssertEqual(r.lap, .normal); XCTAssertNil(r.grade); XCTAssertTrue(r.explanation.contains("no grade"))
        r = dd(["E": 70, "A": 70, "eSeptal": 5, "eLateral": 6.5, "tr": 2.2, "lars": 16])
        XCTAssertEqual(r.lap, .increased); XCTAssertEqual(r.grade, 2)
        r = dd(["E": 80, "A": 60, "eSeptal": 9, "eLateral": 12, "tr": 3.0, "lavi": 40])
        XCTAssertEqual(r.lap, .increased); XCTAssertEqual(r.grade, 2)
        r = dd(["E": 90, "A": 70, "eSeptal": 5, "eLateral": 6, "tr": 2.2, "pvsd": 1.2, "lars": 25])
        XCTAssertEqual(r.lap, .normal, "e′ and E/e′ abnormal, S/D and LARS normal")
        r = dd(["E": 80, "A": 60, "eSeptal": 9, "eLateral": 12, "tr": 3.0, "pasp": 30])
        XCTAssertEqual(r.lap, .normal); XCTAssertEqual(r.grade, 0, "PASP 30 overrides TR 3.0")
        r = dd(["E": 80, "A": 60, "eSeptal": 9, "eLateral": 12, "tr": 3.0], lung: true)
        XCTAssertEqual(r.lap, .unknown); XCTAssertFalse(r.cautions.isEmpty)
        // a missing main variable: read every way it could fall, report only a shared reading
        r = dd(["E": 80, "A": 60, "eSeptal": 9, "eLateral": 12, "lavi": 40])
        XCTAssertEqual(r.lap, .unknown, "TR missing with e′ and E/e′ normal and LAVi 40 depends on TR"); XCTAssertNil(r.grade)
        r = dd(["E": 100, "A": 80, "eSeptal": 5, "eLateral": 6, "lars": 15])
        XCTAssertEqual(r.lap, .increased); XCTAssertEqual(r.grade, 2); XCTAssertTrue(r.explanation.contains("whichever way"))
        r = dd(["E": 80, "A": 60, "eSeptal": 9, "eLateral": 12, "lars": 30])
        XCTAssertEqual(r.lap, .normal); XCTAssertNil(r.grade); XCTAssertEqual(r.headline, "Normal LAP")
        // a pulmonary vein S/D above 0.67 does not settle it (normal LVEF)
        r = dd(["E": 90, "A": 70, "eSeptal": 5, "eLateral": 6, "tr": 2.2, "pvsd": 1.0])
        XCTAssertEqual(r.lap, .unknown, "S/D above 0.67 alone is not evidence of normal LAP")
        r = dd(["E": 90, "A": 70, "eSeptal": 5, "eLateral": 6, "tr": 2.2, "pvsd": 0.5])
        XCTAssertEqual(r.lap, .increased, "S/D 0.67 or less still counts")
        // with a reduced LVEF an S/D above 0.67 is an absent sign; with 50% or more it still settles nothing
        r = dd(["E": 90, "A": 70, "eSeptal": 5, "eLateral": 6, "tr": 2.2, "pvsd": 1.0, "lvef": 35])
        XCTAssertEqual(r.lap, .normal, "S/D 1.0 with LVEF 35%"); XCTAssertNil(r.grade)
        XCTAssertTrue(r.steps.first { $0.id == "pvsd" }?.text.contains("counts as normal") ?? false)
        XCTAssertEqual(dd(["E": 90, "A": 70, "eSeptal": 5, "eLateral": 6, "tr": 2.2, "pvsd": 1.0, "lvef": 50]).lap, .unknown, "LVEF 50% is not reduced")
        XCTAssertEqual(dd(["E": 90, "A": 70, "eSeptal": 5, "eLateral": 6, "tr": 2.2, "pvsd": 0.6, "lvef": 35]).lap, .increased)
        r = dd(["E": 80, "A": 60, "eSeptal": 9, "eLateral": 12, "tr": 3.0, "ara": 40])
        XCTAssertEqual(r.lap, .lvedp, "Ar − A alone is an LVEDP marker")
        r = dd(["E": 80, "A": 60, "eSeptal": 9, "eLateral": 12, "tr": 3.0, "padp": 18])
        XCTAssertEqual(r.lap, .increased); XCTAssertEqual(r.grade, 2)
        r = dd(["E": 80, "A": 60, "eSeptal": 9, "eLateral": 12, "tr": 3.0, "ara": -20])
        XCTAssertEqual(r.lap, .normal, "Ar − A of −20 ms is an absent sign"); XCTAssertNil(r.grade)
        r = dd(["E": 80, "A": 60, "eSeptal": 9, "eLateral": 12, "tr": 3.0, "valsalva": 0])
        XCTAssertEqual(r.lap, .normal, "no fall with Valsalva is an absent sign")
        XCTAssertEqual(DiastolicCalc.primaries(ddInput(["eSeptal": 6])).v1, true, "septal 6 alone is reduced")
        XCTAssertEqual(DiastolicCalc.primaries(ddInput(["eLateral": 7])).v1, true, "lateral 7 alone is reduced")
        XCTAssertEqual(DiastolicCalc.primaries(ddInput(["eSeptal": 6.1, "eLateral": 7.1])).v1, false)
        // both sites measured: the average decides (septal 6 with lateral 8 averages 7)
        XCTAssertEqual(DiastolicCalc.primaries(ddInput(["eSeptal": 6, "eLateral": 8])).v1, false, "average 7 is not reduced")
        XCTAssertEqual(DiastolicCalc.primaries(ddInput(["eSeptal": 5, "eLateral": 8])).v1, true, "average 6.5 is reduced")
        XCTAssertEqual(DiastolicCalc.primaries(ddInput(["E": 100, "eSeptal": 6.5, "eLateral": 9])).v2, false, "septal E/e′ 15.4 but average 12.9")
        XCTAssertEqual(DiastolicCalc.primaries(ddInput(["E": 100, "eSeptal": 6.5])).v2, true, "septal E/e′ 15.4 alone counts")
        XCTAssertTrue(dd(["E": 100, "A": 80, "eSeptal": 6, "eLateral": 8, "tr": 2.2]).steps[0].text.hasSuffix("by the average"))
        XCTAssertEqual(DiastolicCalc.primaries(ddInput(["E": 98, "eSeptal": 7, "eLateral": 7])).v2, true, "average E/e′ 14 counts (Figure 3: 14 or more)")
        XCTAssertEqual(DiastolicCalc.primaries(ddInput(["tr": 2.8])).v3, true, "TR 2.8 counts")
        XCTAssertEqual(DiastolicCalc.primaries(ddInput(["eSeptal": 6.5, "eLateral": 9.5], age: "20-39")).v1, true, "average 8 is under 9 at 20–39 y")
        XCTAssertEqual(DiastolicCalc.primaries(ddInput(["eSeptal": 6.5], age: "20-39")).v1, true, "septal 6.5 is under 7 at 20–39 y")
        XCTAssertEqual(DiastolicCalc.primaries(ddInput(["eSeptal": 6, "eLateral": 7], age: ">65")).v1, false, "strictly under at > 65 y")
    }

    func testDiastolicPresenceMACAndTransplant() {
        func present(_ v: [String: Double]) -> Bool? {
            let i = ddInput(v)
            return DiastolicCalc.presence(i, DiastolicCalc.primaries(i)).state
        }
        XCTAssertEqual(present(["E": 50, "A": 80, "eSeptal": 5, "eLateral": 6]), true, "reduced e′ with E/A 0.8 or less")
        XCTAssertEqual(present(["E": 80, "A": 60, "eSeptal": 9, "eLateral": 12, "lavi": 40]), false, "normal e′ needs two markers")
        XCTAssertEqual(present(["E": 80, "A": 60, "eSeptal": 9, "eLateral": 12, "lavi": 40, "lars": 15]), true)
        XCTAssertEqual(DiastolicCalc.mac(ddInput(["E": 50, "A": 80])).lap, .normal)
        XCTAssertEqual(DiastolicCalc.mac(ddInput(["E": 120, "A": 60])).lap, .increased)
        XCTAssertEqual(DiastolicCalc.mac(ddInput(["E": 80, "A": 80, "ivrt": 90])).lap, .normal)
        XCTAssertEqual(DiastolicCalc.mac(ddInput(["E": 80, "A": 80, "ivrt": 70])).lap, .increased)
        XCTAssertEqual(DiastolicCalc.mac(ddInput(["E": 80, "A": 80])).lap, .unknown)
        XCTAssertEqual(DiastolicCalc.transplant(ddInput(["E": 60, "eSeptal": 10, "eLateral": 12])).lap, .normal, "E/e′ 5.5")
        XCTAssertEqual(DiastolicCalc.transplant(ddInput(["E": 120, "eSeptal": 7, "eLateral": 8])).lap, .increased, "E/e′ 16")
        XCTAssertEqual(DiastolicCalc.transplant(ddInput(["E": 100, "eSeptal": 9, "eLateral": 11, "esr": 250])).lap, .increased, "E/e′ 10, E/SRIVR 250")
        XCTAssertEqual(DiastolicCalc.transplant(ddInput(["E": 100, "eSeptal": 9, "eLateral": 11, "tr": 2.5])).lap, .normal, "E/e′ 10, no SRIVR, TR 2.5")
    }

    func testDiastolicBundle() throws {
        guard let dd = try bundled().diastolic else { return }
        XCTAssertEqual(dd.populations.first?.id, "standard", "the main algorithm comes first")
        XCTAssertEqual(Set(dd.populations.map(\.id)).count, dd.populations.count, "population ids are unique")
        XCTAssertTrue(Set(dd.populations.map(\.mode)).isSubset(of: ["main", "mac", "transplant", "list"]))
        XCTAssertTrue(dd.populations.contains { $0.mode == "mac" })
        XCTAssertTrue(dd.populations.contains { $0.mode == "transplant" })
        XCTAssertFalse(dd.scope.isEmpty)
        XCTAssertTrue(dd.readingWarning?.contains("intraoperative") ?? false, "every reading carries the intraoperative warning")
    }

    // MARK: ACLS code timer (mirrors tools/test_reference_logic.js)

    private static let aclsFixture = """
    {"cycleSec": 120, "sources": [],
     "actions": {
      "vf": {"label": "VF / pVT", "kind": "rhythm", "rhythm": "shockable", "cycleReset": true, "log": "Rhythm: VF/pVT"},
      "nonsh": {"label": "Asystole / PEA", "kind": "rhythm", "rhythm": "nonshockable", "cycleReset": true, "log": "Rhythm: asystole/PEA"},
      "rosc": {"label": "ROSC", "kind": "rhythm", "rhythm": "rosc", "log": "ROSC", "goto": "rosc"},
      "shock": {"label": "Shock", "kind": "shock", "adult": {"text": "device dose"}, "child": {"perKgSeq": [2, 4], "thenPerKg": 4, "thenAtLeast": true, "maxPerKg": 10}},
      "epi": {"label": "Epinephrine", "kind": "drug", "adult": {"dose": 1, "unit": "mg", "route": "IV/IO"}, "child": {"perKg": 0.01, "unit": "mg", "max": 1, "route": "IV/IO", "conc": {"value": 0.1, "unit": "mg/mL"}}, "repeat": {"min": 180, "max": 300}},
      "amio": {"label": "Amiodarone", "kind": "drug", "adult": {"unit": "mg", "route": "IV/IO", "doses": [{"dose": 300}, {"dose": 150}], "maxDoses": 2}, "child": {"perKg": 5, "unit": "mg", "max": 300, "route": "IV/IO", "maxDoses": 3}},
      "cpr": {"label": "CPR started", "kind": "event", "cycleReset": true, "log": "CPR started"},
      "reopen": {"label": "Resternotomy", "kind": "event"}
     },
     "modes": [
      {"id": "arrest", "name": "Cardiac arrest", "short": "Arrest", "cycle": true, "prompts": [
        {"id": "shock-now", "level": "now", "alert": true, "action": "shock", "text": "Shock now: {energy:shock}", "when": [{"rhythm": "shockable"}, {"countSince": ["shock", "vf", "==", 0]}]},
        {"id": "epi-ns", "level": "now", "alert": true, "action": "epi", "text": "Epi {dose:epi}", "when": [{"rhythm": "nonshockable"}, {"count": ["epi", "==", 0]}]},
        {"id": "epi-s", "level": "now", "alert": true, "action": "epi", "text": "Epi after shock 2: {dose:epi}", "when": [{"rhythm": "shockable"}, {"count": ["shock", ">=", 2]}, {"count": ["epi", "==", 0]}]},
        {"id": "epi-due", "level": "now", "alert": true, "action": "epi", "text": "Epi due", "when": [{"count": ["epi", ">=", 1]}, {"since": ["epi", ">=", 180]}]},
        {"id": "anti", "level": "now", "action": "amio", "text": "Amio {dose:amio}", "when": [{"rhythm": "shockable"}, {"count": ["shock", ">=", 3]}, {"notAny": ["amio"]}]},
        {"id": "child-only", "patient": "child", "level": "info", "text": "Child note", "when": []}
      ]},
      {"id": "cals", "name": "After cardiac surgery", "short": "CALS", "deadlines": [{"id": "reopen", "label": "Resternotomy", "sec": 300, "until": "reopen"}]},
      {"id": "brady", "name": "Bradycardia", "short": "Brady", "tree": {"adult": {"start": "q", "nodes": {"q": {"q": "Poor perfusion?", "options": [{"label": "Yes", "next": "y"}, {"label": "No", "next": "n"}]}, "y": {"text": "Atropine", "actions": ["epi"]}, "n": {"text": "Observe"}}}}}
     ]}
    """

    private func aclsData() throws -> AclsData { try JSONDecoder().decode(AclsData.self, from: Data(Self.aclsFixture.utf8)) }

    func testAclsClockDosesAndEnergies() throws {
        let d = try aclsData()
        XCTAssertEqual([0, 75000, 3725000, -5000].map { AclsCalc.clock($0) }, ["0:00", "1:15", "1:02:05", "-0:05"])
        var s = AclsState(startedAt: 1, mode: "arrest", patient: "adult")
        s.add(30000, "epi", "Epinephrine 1 mg")
        s.add(10000, "cpr", "CPR started")
        XCTAssertEqual(s.log.map(\.action), ["cpr", "epi"], "kept in time order")
        XCTAssertEqual(AclsCalc.count(s, "epi"), 1)
        XCTAssertEqual(AclsCalc.last(s, "epi"), 30000)
        XCTAssertNil(AclsCalc.last(s, "amio"))
        let epi = try XCTUnwrap(d.actions["epi"]), amio = try XCTUnwrap(d.actions["amio"]), shock = try XCTUnwrap(d.actions["shock"])
        XCTAssertEqual(AclsCalc.dose(epi, s, 0)?.text, "1 mg IV/IO")
        XCTAssertEqual(AclsCalc.dose(amio, s, 0)?.text, "300 mg IV/IO")
        XCTAssertEqual(AclsCalc.dose(amio, s, 1)?.text, "150 mg IV/IO", "second amiodarone dose")
        XCTAssertEqual(AclsCalc.maxDoses(amio, s), 2)
        var c = AclsState(startedAt: 0, mode: "arrest", patient: "child")
        XCTAssertEqual(AclsCalc.dose(epi, c, 0)?.text, "0.01 mg/kg IV/IO (max 1 mg)", "no weight yet")
        c.weight = 18
        XCTAssertEqual(AclsCalc.dose(epi, c, 0)?.text, "0.18 mg IV/IO · 1.8 mL of 0.1 mg/mL (0.01 mg/kg)")
        c.weight = 120
        XCTAssertEqual(AclsCalc.dose(epi, c, 0)?.text, "1 mg IV/IO · 10 mL of 0.1 mg/mL (the maximum)", "capped at 1 mg")
        c.weight = 18
        XCTAssertEqual(AclsCalc.dose(amio, c, 0)?.text, "90 mg IV/IO (5 mg/kg)")
        XCTAssertEqual([0, 1, 2].map { AclsCalc.energy(shock, c, $0)?.text }, ["36 J (2 J/kg)", "72 J (4 J/kg)", "≥ 72 J (4 J/kg), up to 180 J"])
        XCTAssertEqual(AclsCalc.entryText(shock, c, 1), "Shock 2: 72 J")
        XCTAssertEqual(AclsCalc.entryText(shock, s, 0, joules: 200), "Shock 1: 200 J", "the typed energy is logged")
        XCTAssertEqual(AclsCalc.entryText(epi, c, 1), "Epinephrine 0.18 mg IV/IO (dose 2)")
        XCTAssertEqual([AclsCalc.round(0.1834), AclsCalc.round(4.56), AclsCalc.round(72.4)], [0.18, 4.6, 72])
        XCTAssertEqual([AclsCalc.num(0.18), AclsCalc.num(1.8), AclsCalc.num(90), AclsCalc.num(0.01)], ["0.18", "1.8", "90", "0.01"])
    }

    func testAclsPromptsFollowTheLog() throws {
        let d = try aclsData()
        var s = AclsState(startedAt: 0, mode: "arrest", patient: "adult")
        func ids(_ t: Double) -> [String] { AclsCalc.prompts(s, d, t).map(\.id) }
        XCTAssertEqual(AclsCalc.cycle(s, d, 90000).elapsed, 90, "the first cycle runs from the start")
        s.add(20000, "cpr", "CPR started")
        XCTAssertEqual(AclsCalc.cycle(s, d, 90000).elapsed, 70, "CPR started resets it")
        s.add(140000, "vf", "Rhythm: VF/pVT")
        XCTAssertEqual(ids(141000), ["shock-now"])
        s.add(150000, "shock", "Shock 1")
        XCTAssertEqual(ids(151000), [], "shock given: nothing due")
        s.add(260000, "vf", "Rhythm: VF/pVT")
        s.add(265000, "shock", "Shock 2")
        XCTAssertEqual(ids(266000), ["epi-s"], "epinephrine after the second shock")
        s.add(280000, "epi", "Epinephrine 1 mg")
        let epi = try XCTUnwrap(d.actions["epi"])
        XCTAssertEqual(AclsCalc.timer(epi, s, "epi", 400000)?.state, "wait")
        XCTAssertEqual(AclsCalc.timer(epi, s, "epi", 400000)?.remaining ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(ids(460000), ["epi-due"], "due 3 minutes after the last dose")
        XCTAssertEqual(AclsCalc.timer(epi, s, "epi", 580000)?.state, "overdue")
        s.add(380000, "vf", "Rhythm: VF/pVT")
        s.add(385000, "shock", "Shock 3")
        XCTAssertEqual(ids(390000), ["anti"])
        XCTAssertEqual(AclsCalc.prompts(s, d, 390000).first?.text, "Amio 300 mg IV/IO")
        s.add(395000, "amio", "Amiodarone 300 mg")
        XCTAssertTrue(AclsCalc.prompts(s, d, 396000).isEmpty)
        if let e = s.log.first(where: { $0.action == "amio" }) { s.remove(e) }
        XCTAssertEqual(ids(396000), ["anti"], "removing the mistaken amiodarone brings the prompt back")
        var n = AclsState(startedAt: 0, mode: "arrest", patient: "adult")
        n.add(5000, "nonsh", "Rhythm: asystole/PEA")
        XCTAssertEqual(AclsCalc.prompts(n, d, 6000).map { [$0.id, $0.text] }, [["epi-ns", "Epi 1 mg IV/IO"]])
        XCTAssertEqual(AclsCalc.rhythm(n, d), "nonshockable")
        let c = AclsState(startedAt: 0, mode: "arrest", patient: "child")
        XCTAssertEqual(AclsCalc.prompts(c, d, 1000).map(\.id), ["child-only"], "a child prompt shows only for a child")
    }

    func testAclsDeadlinesTreesAndLog() throws {
        let d = try aclsData()
        var s = AclsState(startedAt: 0, mode: "cals", patient: "adult")
        XCTAssertEqual(AclsCalc.deadlines(s, d, 60000).map { [$0.id, String($0.remaining)] }, [["reopen", "240.0"]])
        XCTAssertEqual(AclsCalc.deadlines(s, d, 330000).first?.remaining, -30, "negative once passed")
        s.add(200000, "reopen", "Resternotomy")
        XCTAssertTrue(AclsCalc.deadlines(s, d, 330000).isEmpty, "done before the deadline: gone")
        var b = AclsState(startedAt: 0, mode: "brady", patient: "adult")
        XCTAssertEqual(AclsCalc.tree(b, d)?.nodeId, "q")
        XCTAssertEqual(AclsCalc.tree(b, d)?.node.q, "Poor perfusion?")
        AclsCalc.choose(&b, d, 5000, next: "y", label: "Yes")
        XCTAssertEqual(AclsCalc.tree(b, d)?.nodeId, "y")
        XCTAssertEqual(AclsCalc.tree(b, d)?.path, ["y"])
        XCTAssertEqual(b.log.last?.text, "Brady: Poor perfusion? Yes")
        AclsCalc.back(&b, d)
        XCTAssertEqual(AclsCalc.tree(b, d)?.nodeId, "q")
        XCTAssertNil(AclsCalc.tree(AclsState(startedAt: 0, mode: "brady", patient: "child"), d), "no child tree in this example")
        var l = AclsState(startedAt: 1_793_275_200, mode: "arrest", patient: "child")   // 2026-10-29 12:00:00 UTC
        l.weight = 18
        l.add(0, "start", "Code clock started")
        l.add(75000, "epi", "Epinephrine 0.18 mg IV/IO")
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX")
        let text = AclsCalc.logText(l) { f.string(from: Date(timeIntervalSince1970: $0 / 1000)) }
        XCTAssertEqual(text, "Code log (child, 18 kg), started 12:00:00\n12:00:00  +0:00  Code clock started\n12:01:15  +1:15  Epinephrine 0.18 mg IV/IO")
    }

    func testAclsBundle() throws {
        guard let a = try bundled().acls else { return }
        XCTAssertGreaterThan(a.cycleSec, 0)
        let ids = Set(a.modes.map(\.id))
        XCTAssertEqual(ids.count, a.modes.count, "mode ids are unique")
        for m in a.modes {
            for g in m.groups ?? [] { for id in g.actions { XCTAssertNotNil(a.actions[id], "\(m.id) group names \(id)") } }
            for p in m.prompts ?? [] { if let id = p.action { XCTAssertNotNil(a.actions[id], "\(m.id) prompt \(p.id) names \(id)") } }
            for (_, tr) in m.tree ?? [:] {
                XCTAssertNotNil(tr.nodes[tr.start], "\(m.id) tree starts at a node")
                for (_, n) in tr.nodes {
                    for o in n.options ?? [] { XCTAssertNotNil(tr.nodes[o.next], "\(m.id) option leads to \(o.next)") }
                    for id in n.actions ?? [] { XCTAssertNotNil(a.actions[id], "\(m.id) node names \(id)") }
                }
            }
        }
        for (id, act) in a.actions { if let g = act.goto { XCTAssertTrue(ids.contains(g), "\(id) goes to \(g)") } }
    }

    /// The shipped content, walked the way tools/test_reference_logic.js walks it.
    func testAclsContentWalk() throws {
        guard let d = try bundled().acls else { return }
        XCTAssertEqual(d.modes.count, 6)
        var s = AclsState(startedAt: 0, mode: "arrest", patient: "adult")
        func ids(_ t: Double) -> [String] { AclsCalc.prompts(s, d, t).map(\.id) }
        XCTAssertEqual(ids(0), ["first-adult"])
        s.add(10000, "vf", "Rhythm: VF/pVT")
        var ps = AclsCalc.prompts(s, d, 11000)
        XCTAssertEqual(ps.map(\.id), ["shock-now"])
        XCTAssertTrue(ps[0].text.hasPrefix("Shock now: the device’s recommended biphasic dose (e.g. 120–200 J)"), ps[0].text)
        s.add(12000, "shock", AclsCalc.entryText(d.actions["shock"]!, s, 0, joules: 200))
        XCTAssertEqual(s.log.last?.text, "Shock 1: 200 J")
        s.add(130000, "vf", "Rhythm: VF/pVT"); s.add(131000, "shock", "Shock 2: 200 J")
        ps = AclsCalc.prompts(s, d, 132000)
        XCTAssertEqual(ps.map(\.id), ["epi-s", "airway"])
        XCTAssertEqual(ps[0].text, "Two shocks have not worked: epinephrine 1 mg IV/IO.")
        s.add(140000, "epi", AclsCalc.entryText(d.actions["epi"]!, s, 0))
        XCTAssertEqual(s.log.last?.text, "Epinephrine 1 mg IV/IO")
        s.add(250000, "vf", "Rhythm: VF/pVT"); s.add(251000, "shock", "Shock 3: 200 J")
        ps = AclsCalc.prompts(s, d, 252000)
        XCTAssertEqual(ps.map(\.id), ["anti", "airway", "causes"])
        XCTAssertEqual(ps[0].text, "Three shocks have not worked: amiodarone 300 mg IV/IO, or lidocaine 1–1.5 mg/kg.")
        s.add(260000, "amio", AclsCalc.entryText(d.actions["amio"]!, s, 0))
        XCTAssertEqual(ids(330000), ["epi-due", "airway", "causes"], "epinephrine due 3 min after the first dose")
        s.add(331000, "epi", AclsCalc.entryText(d.actions["epi"]!, s, 1))
        XCTAssertEqual(s.log.last?.text, "Epinephrine 1 mg IV/IO (dose 2)")
        s.add(370000, "vf", "Rhythm: VF/pVT"); s.add(371000, "shock", "Shock 4: 200 J")
        ps = AclsCalc.prompts(s, d, 372000)
        XCTAssertEqual(ps.map(\.id), ["anti-2a", "airway", "causes"])
        XCTAssertEqual(ps[0].text, "If VF/pVT persists, a second amiodarone dose: 150 mg IV/IO. The algorithm prints no interval for it.")
        s.add(380000, "airway", "Advanced airway placed")
        XCTAssertEqual(ids(381000), ["anti-2a", "vent-adult", "causes"])
        // lidocaine first: the second lidocaine dose is offered, not a switch to amiodarone
        var l = AclsState(startedAt: 0, mode: "arrest", patient: "adult")
        for (t0, id) in [(1000.0, "vf"), (2000, "shock"), (125000, "vf"), (126000, "shock"), (130000, "epi"), (250000, "vf"), (251000, "shock"), (255000, "lido"), (370000, "vf"), (371000, "shock")] { l.add(t0, id, id) }
        let lp = AclsCalc.prompts(l, d, 372000)
        XCTAssertEqual(lp.map(\.id).filter { $0.hasPrefix("anti") }, ["anti-2b"])
        XCTAssertEqual(lp.first { $0.id == "anti-2b" }?.text, "If VF/pVT persists, a second lidocaine dose: 0.5–0.75 mg/kg. The algorithm prints no interval for it.")
        XCTAssertEqual(AclsCalc.cycle(s, d, 400000).from, 370000)
        XCTAssertEqual(d.actions["rosc"]?.goto, "rosc")

        // a child, asystole first, with weight-based doses
        var c = AclsState(startedAt: 0, mode: "arrest", patient: "child"); c.weight = 18
        XCTAssertEqual(AclsCalc.prompts(c, d, 0).map(\.id), ["first-child"])
        c.add(5000, "nonsh", "Rhythm: asystole/PEA")
        let cp = AclsCalc.prompts(c, d, 6000)
        XCTAssertEqual(cp.map(\.id), ["epi-ns"])
        XCTAssertEqual(cp[0].text, "Epinephrine as soon as possible: 0.18 mg IV/IO · 1.8 mL of 0.1 mg/mL = 100 mcg/mL (0.01 mg/kg).")
        XCTAssertEqual(AclsCalc.energy(d.actions["shock"]!, c, 0)?.text, "36 J (2 J/kg)")
        XCTAssertEqual(AclsCalc.energy(d.actions["shock"]!, c, 1)?.text, "72 J (4 J/kg)")
        XCTAssertEqual(AclsCalc.energy(d.actions["shock"]!, c, 2)?.text, "≥ 72 J (4 J/kg), up to 180 J")
        XCTAssertEqual(AclsCalc.dose(d.actions["amio"]!, c, 0)?.text, "90 mg IV/IO (5 mg/kg)")
        XCTAssertEqual(AclsCalc.maxDoses(d.actions["amio"]!, c), 3)
        var big = AclsState(startedAt: 0, mode: "arrest", patient: "child"); big.weight = 70
        XCTAssertEqual(AclsCalc.dose(d.actions["amio"]!, big, 0)?.text, "300 mg IV/IO (the maximum)")
        XCTAssertEqual(AclsCalc.dose(d.actions["amio"]!, big, 1)?.text, "150 mg IV/IO (the maximum)", "later doses are capped at 150 mg")
        XCTAssertEqual(AclsCalc.dose(d.actions["epi"]!, big, 0)?.text, "0.7 mg IV/IO · 7 mL of 0.1 mg/mL = 100 mcg/mL (0.01 mg/kg)")
        // a large child's shocks stop at the adult dose (10 J/kg or the adult dose, whichever is lower)
        XCTAssertEqual([0, 1, 2].map { AclsCalc.energy(d.actions["shock"]!, big, $0)?.text ?? "" },
                       ["140 J (2 J/kg)", "200 J, the adult dose (4 J/kg would be 280 J)", "200 J, the adult dose (4 J/kg would be 280 J)"])
        var forty = AclsState(startedAt: 0, mode: "arrest", patient: "child"); forty.weight = 40
        XCTAssertEqual(AclsCalc.energy(d.actions["shock"]!, forty, 2)?.text, "≥ 160 J (4 J/kg), up to 200 J (the adult dose)")
        XCTAssertEqual(AclsCalc.energy(d.actions["shock"]!, forty, 2)?.joules, 160)
        XCTAssertEqual(AclsCalc.energy(d.actions["shock"]!, AclsState(startedAt: 0, mode: "arrest", patient: "child"), 2)?.text,
                       "≥ 4 J/kg (up to 10 J/kg or the adult dose, whichever is lower)")
        XCTAssertEqual(AclsCalc.dose(d.actions["lido"]!, c, 0)?.text, "18 mg IV/IO (1 mg/kg)")
        var b = AclsState(startedAt: 0, mode: "brady", patient: "child"); b.weight = 3
        XCTAssertEqual(AclsCalc.dose(d.actions["atropine"]!, b, 0)?.text, "0.1 mg IV/IO (the minimum)")
        b.weight = 40
        XCTAssertEqual(AclsCalc.dose(d.actions["atropine"]!, b, 0)?.text, "0.5 mg IV/IO (the maximum)")
        // a child's atropine "may repeat once" with no printed interval: no countdown; an adult's runs every 3–5 min
        b.add(1000, "atropine", "Atropine")
        XCTAssertNil(AclsCalc.timer(d.actions["atropine"], b, "atropine", 400000))
        var ba = AclsState(startedAt: 0, mode: "brady", patient: "adult"); ba.add(1000, "atropine", "Atropine")
        XCTAssertEqual(AclsCalc.timer(d.actions["atropine"], ba, "atropine", 200000)?.state, "due")
        var t = AclsState(startedAt: 0, mode: "tachy", patient: "child"); t.weight = 18
        XCTAssertEqual(AclsCalc.dose(d.actions["adenosine-child"]!, t, 0)?.text, "1.8 mg IV/IO rapid push, then flush (0.1 mg/kg)")
        XCTAssertEqual(AclsCalc.dose(d.actions["adenosine-child"]!, t, 1)?.text, "3.6 mg IV/IO rapid push, then flush (0.2 mg/kg)")
        var an = AclsState(startedAt: 0, mode: "anaphylaxis", patient: "child"); an.weight = 18
        XCTAssertEqual(AclsCalc.dose(d.actions["ana-epi-2"]!, an, 0)?.text, "20 mcg IV · 1 mL of 20 mcg/mL (the maximum)", "capped at the adult grade II dose")
        XCTAssertEqual(AclsCalc.dose(d.actions["ana-epi-2"]!, an, 1)?.text, "36 mcg IV · 1.8 mL of 20 mcg/mL (2 mcg/kg)")
        XCTAssertEqual(AclsCalc.dose(d.actions["ana-epi-3"]!, an, 0)?.text, "50 mcg IV · 2.5 mL of 20 mcg/mL (the maximum)")
        XCTAssertEqual(AclsCalc.dose(d.actions["ana-epi-3"]!, an, 1)?.text, "180 mcg IV · 9 mL of 20 mcg/mL (10 mcg/kg)", "escalates: ANZAAG 4–10 mcg/kg")
        var teen = AclsState(startedAt: 0, mode: "anaphylaxis", patient: "child"); teen.weight = 70
        XCTAssertEqual([AclsCalc.dose(d.actions["ana-epi-2"]!, teen, 0)?.amount, AclsCalc.dose(d.actions["ana-epi-3"]!, teen, 1)?.amount, AclsCalc.dose(d.actions["ana-fluid"]!, teen, 0)?.amount],
                       [20, 200, 1000], "never above the adult doses")
        XCTAssertEqual(AclsCalc.dose(d.actions["ana-epi-im"]!, an, 0)?.text, "180 mcg IM, lateral thigh (10 mcg/kg)")
        XCTAssertEqual(AclsCalc.dose(d.actions["ana-glucagon"]!, an, 0)?.text, "0.72 mg IV (0.04 mg/kg)")

        // CALS: the one-minute and five-minute rules
        var k = AclsState(startedAt: 0, mode: "cals", patient: "adult")
        XCTAssertEqual(AclsCalc.deadlines(k, d, 0).map { [$0.id, "\(Int($0.remaining))"] }, [["ecm", "60"], ["reopen", "300"]])
        k.add(5000, "vf", "Rhythm: VF/pVT")
        XCTAssertEqual(AclsCalc.prompts(k, d, 6000).map(\.id), ["vf-shock", "airway"])
        for t0 in [10000.0, 20000, 30000] { k.add(t0, "cshock", "Shock") }
        XCTAssertEqual(AclsCalc.prompts(k, d, 61000).map(\.id), ["vf-fail", "ecm-rule", "airway", "infusions"])
        k.add(62000, "ecm", "External compressions started")
        XCTAssertEqual(AclsCalc.prompts(k, d, 301000).map(\.id), ["vf-fail", "under-60", "reopen-rule", "airway", "infusions"])
        k.add(302000, "reopen", "Emergency resternotomy")
        XCTAssertEqual(AclsCalc.deadlines(k, d, 303000).count, 0)
        XCTAssertNil(AclsCalc.tree(k, d))
        // trees start where the JS test says; every node reachable
        for (mode, who, start) in [("brady", "adult", "q1"), ("brady", "child", "q1"), ("tachy", "adult", "q1"), ("tachy", "child", "q1"), ("anaphylaxis", "adult", "grade"), ("anaphylaxis", "child", "grade")] {
            XCTAssertEqual(AclsCalc.tree(AclsState(startedAt: 0, mode: mode, patient: who), d)?.nodeId, start, "\(mode) \(who)")
        }
        for m in d.modes {
            for (who, tr) in m.tree ?? [:] {
                var seen: Set<String> = [tr.start]; var todo = [tr.start]
                while let cur = todo.popLast() {
                    for o in tr.nodes[cur]?.options ?? [] where !seen.contains(o.next) { seen.insert(o.next); todo.append(o.next) }
                }
                XCTAssertEqual(seen, Set(tr.nodes.keys), "\(m.id)/\(who): every node reachable")
            }
        }
        // anaphylaxis prompts
        var a2 = AclsState(startedAt: 0, mode: "anaphylaxis", patient: "adult")
        XCTAssertEqual(AclsCalc.prompts(a2, d, 0).map(\.id), ["start"])
        a2.add(1000, "ana-help", "Help called")
        a2.add(2000, "ana-epi-3", AclsCalc.entryText(d.actions["ana-epi-3"]!, a2, 0))
        XCTAssertEqual(a2.log.last?.text, "Epinephrine IV · grade III 50 mcg IV")
        let ap = AclsCalc.prompts(a2, d, 123000)
        XCTAssertEqual(ap.map(\.id), ["epi3-due"])
        XCTAssertEqual(ap[0].text, "Two minutes: if the response is inadequate, repeat epinephrine 200 mcg IV · 2 mL of 100 mcg/mL.")
        for t0 in [130000.0, 260000, 390000] { a2.add(t0, "ana-epi-3", "Epinephrine") }
        XCTAssertEqual(AclsCalc.prompts(a2, d, 391000).map(\.id), ["infusion"])
        XCTAssertEqual(AclsCalc.prompts(a2, d, 3400000).map(\.id), ["epi3-due", "infusion", "refractory", "tryptase"])
        // boluses of both grades count together towards the infusion
        var mix = AclsState(startedAt: 0, mode: "anaphylaxis", patient: "adult")
        for (t0, id) in [(1000.0, "ana-help"), (2000, "ana-epi-2"), (60000, "ana-epi-2"), (120000, "ana-epi-3"), (180000, "ana-epi-3")] { mix.add(t0, id, id) }
        XCTAssertEqual(AclsCalc.prompts(mix, d, 181000).map(\.id), ["infusion"])
        var ch = AclsState(startedAt: 0, mode: "anaphylaxis", patient: "child"); ch.weight = 18
        ch.add(1000, "ana-help", "Help called"); ch.add(2000, "ana-epi-3", "Epinephrine")
        let chp = AclsCalc.prompts(ch, d, 123000)
        XCTAssertEqual(chp.map(\.id), ["child-doses", "epi3-due-child"], "the age limit for the child doses stays on screen")
        XCTAssertEqual(chp.last?.text, "Two minutes: if the response is inadequate, increase the dose: 180 mcg IV · 9 mL of 20 mcg/mL (10 mcg/kg) (ANZAAG: 4–10 mcg/kg).")
    }
    // MARK: ABG (mirrors tools/test_reference_logic.js)

    private static let abgFixture = """
    {"normal":{"ph":[7.35,7.45],"paco2":[35,45],"hco3":[22,26]},"mid":{"ph":7.4,"paco2":40,"hco3":24},
     "check":{"pk":6.1,"solubility":0.0307,"tol":0.03},"plausible":{"ph":[6.8,7.8],"paco2":[10,150],"hco3":[3,60]},
     "rules":{"metAcid":{"slope":1.5,"intercept":8,"tol":2,"label":"Winters’ formula"},"metAlk":{"slope":0.7,"intercept":23.2,"tol":2},
      "respAcidAcute":{"slope":0.1,"intercept":20,"tol":2},"respAcidChronic":{"slope":0.35,"intercept":10,"tol":2},
      "respAlkAcute":{"slope":0.2,"intercept":16,"tol":2},"respAlkChronic":{"slope":0.5,"intercept":4,"tol":2}},
     "sources":[]}
    """

    func testAbgReadings() throws {
        let d = try JSONDecoder().decode(AbgData.self, from: Data(Self.abgFixture.utf8))
        func abg(_ ph: Double?, _ pc: Double?, _ hc: Double?) -> AbgCalc.Reading { AbgCalc.read(ph: ph, paco2: pc, hco3: hc, data: d) }
        var r = abg(7.28, 30, 14)
        XCTAssertEqual(r.headline, "Metabolic Acidosis"); XCTAssertEqual(r.primary, .metAcid); XCTAssertNil(r.second); XCTAssertEqual(r.check?.ok, true)
        XCTAssertEqual(r.visual?.bands.map { [AbgCalc.f1($0.lo), AbgCalc.f1($0.hi)] }, [["27", "31"]], "Winters’ formula: 1.5 × 14 + 8 ± 2")
        XCTAssertEqual(r.explanation, "pH 7.28: acidemia. HCO₃ 14 mEq/L (below 22) makes it metabolic. Winters’ formula expects PaCO₂ 27–31 mmHg; 30 sits in it: the respiratory compensation is appropriate.")
        r = abg(7.19, 40, 15)
        XCTAssertEqual(r.headline, "Metabolic and Respiratory Acidosis"); XCTAssertEqual(r.second, .respAcid)
        r = abg(7.38, 30, 17.5)
        XCTAssertEqual(r.status, "normal"); XCTAssertEqual(r.headline, "Metabolic Acidosis and Respiratory Alkalosis")
        r = abg(7.25, 60, 26)
        XCTAssertEqual(r.headline, "Acute Respiratory Acidosis"); XCTAssertEqual(r.phase, .acute)
        XCTAssertEqual(abg(7.33, 60, 31.5).headline, "Chronic Respiratory Acidosis")
        r = abg(7.29, 60, 28.5)
        XCTAssertEqual(r.headline, "Respiratory Acidosis, Partly Compensated"); XCTAssertEqual(r.phase, .between)
        XCTAssertEqual(abg(7.39, 60, 36).headline, "Respiratory Acidosis and Metabolic Alkalosis", "HCO₃ above the chronic band")
        XCTAssertEqual(abg(7.4, 60, 36).headline, "Respiratory Acidosis and Metabolic Alkalosis", "pH at 7.40 with both abnormal")
        r = abg(7.49, 48, 36)
        XCTAssertEqual(r.headline, "Metabolic Alkalosis"); XCTAssertNil(r.second)
        XCTAssertEqual(abg(7.55, 25, 21.5).headline, "Acute Respiratory Alkalosis")
        r = abg(7.1, 55, 17)
        XCTAssertEqual(r.headline, "Respiratory and Metabolic Acidosis"); XCTAssertEqual(r.disorders, [.respAcid, .metAcid])
        XCTAssertEqual(abg(7.4, 40, 24).headline, "Normal Acid–Base Status")
        // two values: the third from Henderson–Hasselbalch
        r = abg(7.28, 30, nil)
        XCTAssertEqual(r.derived, .hco3); XCTAssertEqual(AbgCalc.f1(r.values.hco3 ?? 0), "13.9"); XCTAssertEqual(r.headline, "Metabolic Acidosis")
        r = abg(nil, 30, 14)
        XCTAssertEqual(r.derived, .ph); XCTAssertEqual(AbgCalc.fph(r.values.ph ?? 0), "7.28")
        XCTAssertEqual(abg(7.28, nil, 14).derived, .paco2)
        XCTAssertTrue(abg(7.28, nil, nil).empty)
        // values that do not agree
        r = abg(7.4, 30, 14)
        XCTAssertEqual(r.check?.ok, false); XCTAssertTrue(r.cautions.contains { $0.contains("do not agree") })
        XCTAssertTrue(AbgCalc.summary(abg(7.28, 30, 14)).hasPrefix("ABG: pH 7.28, PaCO₂ 30 mmHg, HCO₃ 14 mEq/L. Metabolic Acidosis."))
    }

    /// The coefficients that ship in reference.json (mirrors 'abg: the shipped rules').
    func testAbgShippedRules() throws {
        guard let d = try bundled().abg else { return }
        func r(_ ph: Double, _ pc: Double, _ hc: Double) -> AbgCalc.Reading { AbgCalc.read(ph: ph, paco2: pc, hco3: hc, data: d) }
        var x = r(7.28, 30, 14)
        XCTAssertEqual(x.headline, "Metabolic Acidosis")
        XCTAssertEqual(x.visual.map { AbgCalc.band(AbgCalc.Expect(v: 0, lo: $0.bands[0].lo, hi: $0.bands[0].hi)) }, "27–31")
        x = r(7.5, 47, 34)
        XCTAssertEqual(x.headline, "Metabolic Alkalosis")
        XCTAssertEqual(x.visual.map { AbgCalc.band(AbgCalc.Expect(v: 0, lo: $0.bands[0].lo, hi: $0.bands[0].hi)) }, "42–52")
        x = r(7.37, 60, 34)
        XCTAssertEqual(x.headline, "Chronic Respiratory Acidosis")
        XCTAssertEqual(x.visual?.bands.map { AbgCalc.band(AbgCalc.Expect(v: 0, lo: $0.lo, hi: $0.hi)) }, ["23–29", "32–36"])
        XCTAssertEqual(x.status, "normal", "a normal pH in compensated chronic hypercapnia is not called mixed")
        XCTAssertEqual(r(7.27, 60, 27).headline, "Acute Respiratory Acidosis")
        XCTAssertEqual(r(7.31, 60, 30.5).headline, "Respiratory Acidosis, Partly Compensated")
        XCTAssertTrue(r(7.2, 80, 32).cautions.contains { $0.contains("derived up to PaCO₂ 70") })
        x = r(7.47, 30, 21.5)
        XCTAssertEqual(x.phase, .either); XCTAssertEqual(x.headline, "Respiratory Alkalosis")
        XCTAssertEqual(r(7.55, 25, 21.5).headline, "Acute Respiratory Alkalosis")
        x = r(7.44, 30, 20)
        XCTAssertEqual(x.headline, "Respiratory Alkalosis"); XCTAssertNil(x.second)
        XCTAssertEqual(r(7.3, 30, 14).check?.ok, true)
        XCTAssertEqual(r(7.36, 30, 14).check?.ok, false)
    }

    // MARK: Regional technique finder (mirrors tools/test_reference_logic.js)

    private func regionalFixture() throws -> RegionalData {
        let json = """
        {"figure": {"box": [200, 420], "outline": "M10 10 L190 10 L190 410 L10 410 Z", "head": {"cx": 100, "cy": 30, "rx": 17, "ry": 22}, "landmarks": {},
          "regions": [{"id": "chest", "name": "Anterior chest and breast", "views": {}}, {"id": "lower-abdomen", "name": "Lower abdomen", "views": {}},
                      {"id": "hip", "name": "Hip", "views": {}}, {"id": "knee", "name": "Knee", "views": {}}]},
         "blocks": [{"id": "acb", "name": "Adductor canal", "group": "lower"}, {"id": "ipack", "name": "IPACK", "group": "lower"},
                    {"id": "peng", "name": "PENG", "group": "lower"}, {"id": "tap", "name": "TAP", "group": "trunk"}],
         "map": {"knee": {"neuraxial": {"level": "T10", "technique": "spinal"}, "blocks": [{"id": "acb"}, {"id": "ipack"}, {"id": "missing"}]},
                 "hip": {"neuraxial": {"level": "T10", "technique": "spinal"}, "blocks": [{"id": "peng"}]},
                 "lower-abdomen": {"neuraxial": {"level": "T6", "technique": "spinal or epidural"}, "blocks": [{"id": "tap", "role": "alternative"}]},
                 "chest": {"blocks": []}}}
        """
        return try JSONDecoder().decode(RegionalData.self, from: Data(json.utf8))
    }

    func testRegionalRules() throws {
        let d = try regionalFixture()
        XCTAssertEqual([RegionalCalc.side(view: "front", index: 0, count: 2), RegionalCalc.side(view: "front", index: 1, count: 2),
                        RegionalCalc.side(view: "back", index: 0, count: 2), RegionalCalc.side(view: "back", index: 1, count: 2),
                        RegionalCalc.side(view: "front", index: 0, count: 1)], ["R", "L", "L", "R", "M"])
        XCTAssertEqual([RegionalCalc.rank("T4"), RegionalCalc.rank("T10"), RegionalCalc.rank("S2–S5"), RegionalCalc.rank("x")], [10, 16, 25, -1])
        XCTAssertEqual([RegionalCalc.label("Knee", sides: ["R"]), RegionalCalc.label("Hip", sides: ["L", "R"]), RegionalCalc.label("Perineum and anus", sides: ["M"])],
                       ["Right knee", "Both sides: hip", "Perineum and anus"])
        let r = RegionalCalc.recommend(["knee:R", "hip:L", "lower-abdomen:M", "knee:R", "nowhere:M"], d)
        XCTAssertEqual(r.items.map(\.id), ["lower-abdomen", "hip", "knee"], "head to foot, duplicates merged")
        XCTAssertEqual(r.items.map(\.label), ["Lower abdomen", "Left hip", "Right knee"])
        XCTAssertEqual(r.items[2].blocks.map(\.id), ["acb", "ipack"], "unknown blocks dropped")
        XCTAssertEqual(r.items[0].blocks.first?.role, "alternative")
        XCTAssertEqual(r.top, RegionalCalc.Top(level: "T6", region: "Lower abdomen"))
        XCTAssertNil(RegionalCalc.recommend(["chest:M"], d).top)
        XCTAssertEqual(RegionalCalc.recommend(["hip:L", "hip:R"], d).items.first?.sides, ["R", "L"])
        // the outline parser closes the shape, and a point inside it is inside
        let p = RegionalCalc.path(svg: "M10 10 C20 10 30 10 40 10 L40 40 L10 40 Z")
        XCTAssertTrue(p.contains(CGPoint(x: 25, y: 25)))
        XCTAssertFalse(p.contains(CGPoint(x: 45, y: 25)))
        XCTAssertEqual(RegionalCalc.y(forLevel: "T10"), 150)
        XCTAssertNil(RegionalCalc.y(forLevel: "none"))
    }

    func testRegionalShippedContent() throws {
        guard let d = try bundled().regional else { return }
        let blockIds = Set(d.blocks.map(\.id)), regionIds = Set(d.figure.regions.map(\.id)), groups = Set((d.blockGroups ?? []).map(\.id))
        XCTAssertEqual(blockIds.count, d.blocks.count, "block ids are unique")
        XCTAssertFalse(RegionalCalc.path(svg: d.figure.outline).isEmpty)
        for b in d.blocks {
            XCTAssertTrue(groups.contains(b.group), "\(b.id) is in a listed group")
            XCTAssertFalse((b.volume?.items ?? []).isEmpty, "\(b.id) has a volume")
            XCTAssertTrue(["https://www.nysora.com/", "https://nysora.com/"].contains { (b.url ?? "").hasPrefix($0) }, "\(b.id) links to NYSORA")
            if let pr = b.art?.probe { XCTAssertTrue(["front", "back"].contains(pr.view), "\(b.id) probe view") }
        }
        for (rid, m) in d.map ?? [:] {
            XCTAssertTrue(regionIds.contains(rid), "map region \(rid) is on the figure")
            for b in m.blocks ?? [] { XCTAssertTrue(blockIds.contains(b.id), "\(rid) → \(b.id) is a listed block") }
            if let lv = m.neuraxial?.level { XCTAssertGreaterThanOrEqual(RegionalCalc.rank(lv), 0, "\(rid) level \(lv)") }
        }
        for r in d.figure.regions { XCTAssertNotNil(d.map?[r.id], "\(r.id) has options") }
        let knee = RegionalCalc.recommend(["knee:R"], d)
        XCTAssertFalse(knee.items[0].blocks.isEmpty)
        if let n = d.neuraxial {
            XCTAssertFalse(n.procedures.isEmpty)
            for p in n.procedures { XCTAssertGreaterThanOrEqual(RegionalCalc.rank(p.level), 0, "\(p.id) has a sensory level") }
        }
    }

    // MARK: OB emergencies

    func testObEmergencyShippedContent() throws {
        guard let d = try bundled().obEmergency else { return }
        let src = Set((d.sources ?? []).map(\.id))
        XCTAssertEqual(d.events.first?.id, "arrest", "the arrest opens first")
        XCTAssertEqual(d.events.first?.timer?.marks.map(\.sec), [240, 300], "hysterotomy by 4, delivery by 5 minutes")
        for e in d.events {
            XCTAssertTrue(e.sections.contains { $0.kind == .steps && !($0.items ?? []).isEmpty }, "\(e.id) has a checklist")
            for id in e.sources ?? [] { XCTAssertTrue(src.contains(id), "\(e.id) → \(id)") }
            if e.id != "newborn" { XCTAssertNil(e.weightFor, "\(e.id) uses the mother's weight") }
        }
        let nb = try XCTUnwrap(d.events.first { $0.id == "newborn" })
        XCTAssertEqual(nb.weightFor?.key, "newborn", "the newborn has its own weight")
        XCTAssertLessThanOrEqual(nb.weightFor?.maxKg ?? 99, 10, "an adult weight is refused")
        let epi = try XCTUnwrap(nb.weightDoses?.first { $0.label.hasPrefix("Epinephrine IV") })
        XCTAssertEqual(PedsCalc.doseText(low: epi.perKg, high: epi.perKgHigh, unit: epi.unit, weightKg: 3, max: epi.max).text, "0.03–0.09 mg")
        let last = try XCTUnwrap(d.events.first { $0.id == "last" })
        let bolus = try XCTUnwrap(last.weightDoses?.first { $0.label.hasPrefix("Lipid 20% bolus") })
        XCTAssertEqual(bolus.aboveKg, 70)
        XCTAssertEqual(bolus.aboveText, "100 mL (over 70 kg)")
        XCTAssertNotNil(d.manual?.url, "the Stanford manual is linked")
    }
}
