import XCTest
@testable import PeriopSignal

/// 1.9 (Ben's Wanted Changes): what the history suggests or warns of, never filed by itself: isolation precautions,
/// stress-dose steroids (Woodcock 2020), a thyroid disease from the TSH, the aspiration and heparin warnings, and the TEE
/// screen's GI concerns and previous EGD and TEE.
final class PatientLinks19Tests: XCTestCase {

    private func record(_ problems: Set<String>) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 55; r.sex = .female
        r.problems = problems
        return r
    }

    // MARK: Isolation precautions

    func testPrecautionsAreGroupedSuggestions() {
        var r = record(["c-diff", "uri", "pneumonia", "tb", "covid-recent"])
        let s = PatientPrecautions.suggestions(r)
        XCTAssertEqual(s.map(\.precaution), ["contact", "droplet", "airborne"])
        XCTAssertEqual(s[0].from, ["C. difficile"])
        XCTAssertEqual(s[1].from, ["URI", "Pneumonia"], "one droplet suggestion for both")
        XCTAssertEqual(s[2].from, ["Tuberculosis", "COVID-19"])
        XCTAssertTrue(s[1].source.contains("standard precautions only"), "the droplet caption says most adult pneumonia needs standard only")
        XCTAssertTrue(s[2].source.contains("latent TB: standard"))
        XCTAssertTrue(s[2].source.contains("N95"))
        XCTAssertEqual(s[0].prompt, "Contact precautions: C. difficile — add?")
        // Nothing is filed by itself.
        XCTAssertFalse(r.has("isolation"))
        XCTAssertTrue(r.hx.precautions.isEmpty)
        // Latent TB and a recent (not active) COVID-19 suggest nothing.
        r.hx.tbStatus = "latent"; r.hx.covidStatus = "recent"
        XCTAssertFalse(PatientPrecautions.suggestions(r).contains { $0.precaution == "airborne" })
        r.hx.tbStatus = "active"
        XCTAssertEqual(PatientPrecautions.suggestions(r).first { $0.precaution == "airborne" }?.from, ["Tuberculosis"])
        r.hx.covidStatus = "active"
        XCTAssertEqual(PatientPrecautions.suggestions(r).first { $0.precaution == "airborne" }?.from, ["Tuberculosis", "COVID-19"])
        // Accepting one files the item and the precaution; recorded ones are not offered again.
        let droplet = PatientPrecautions.suggestions(r)[1]
        PatientPrecautions.accept(droplet, &r)
        XCTAssertTrue(r.has("isolation"))
        XCTAssertEqual(r.hx.precautions, ["droplet"])
        XCTAssertEqual(PatientPrecautions.suggestions(r).map(\.precaution), ["contact", "airborne"])
        XCTAssertTrue(PatientPrecautions.suggestions(record(["htn"])).isEmpty)
    }

    // MARK: Stress-dose steroids

    private func onSteroid(_ drug: String, _ mg: Double?, _ duration: String?) -> PatientRecord {
        var r = record(["adrenal"])
        r.hx.adrenalKinds = ["steroids"]
        r.hx.steroidDrug = drug; r.hx.steroidDailyMg = mg; r.hx.steroidDuration = duration
        return r
    }

    func testAtRiskBoundaries() throws {
        XCTAssertFalse(try XCTUnwrap(PatientSteroids.advice(onSteroid("Prednisolone", 4.9, "ge1m"))).atRisk, "4.9 mg is below 5")
        XCTAssertTrue(try XCTUnwrap(PatientSteroids.advice(onSteroid("Prednisolone", 5, "ge1m"))).atRisk, "5 mg or more")
        XCTAssertFalse(try XCTUnwrap(PatientSteroids.advice(onSteroid("Prednisolone", 20, "lt1m"))).atRisk, "under 1 month")
        XCTAssertTrue(try XCTUnwrap(PatientSteroids.advice(onSteroid("prednisone", 10, "ge1m"))).atRisk)
        // Hydrocortisone 20 mg ≈ prednisolone 5 mg (Liu 2013, Table 3).
        XCTAssertTrue(try XCTUnwrap(PatientSteroids.advice(onSteroid("Hydrocortisone", 20, "ge1m"))).atRisk)
        XCTAssertFalse(try XCTUnwrap(PatientSteroids.advice(onSteroid("Hydrocortisone", 19, "ge1m"))).atRisk)
        XCTAssertTrue(try XCTUnwrap(PatientSteroids.advice(onSteroid("Methylprednisolone", 4, "ge1m"))).atRisk)
        XCTAssertTrue(try XCTUnwrap(PatientSteroids.advice(onSteroid("Dexamethasone", 0.75, "ge1m"))).atRisk)
        XCTAssertFalse(try XCTUnwrap(PatientSteroids.advice(onSteroid("Dexamethasone", 0.5, "ge1m"))).atRisk)
    }

    func testEquivalence() {
        XCTAssertEqual(PatientSteroids.prednisoloneEquivalent(drug: "Prednisolone", mg: 7.5), 7.5)
        XCTAssertEqual(PatientSteroids.prednisoloneEquivalent(drug: "Hydrocortisone", mg: 20), 5)
        XCTAssertEqual(PatientSteroids.prednisoloneEquivalent(drug: "Methylprednisolone", mg: 8), 10, "not read as prednisolone")
        XCTAssertEqual(PatientSteroids.prednisoloneEquivalent(drug: "Cortisone", mg: 25), 5)
        XCTAssertEqual(PatientSteroids.prednisoloneEquivalent(drug: "Hydrocortisone", mg: 25), 6.25, "not read as cortisone")
        XCTAssertEqual(PatientSteroids.prednisoloneEquivalent(drug: "Decadron", mg: 1.5) ?? 0, 10, accuracy: 0.001)
        XCTAssertNil(PatientSteroids.prednisoloneEquivalent(drug: "Fluticasone inhaler", mg: 0.5), "inhaled doses are not converted")
    }

    func testAdviceLinesFollowTheGuideline() throws {
        let a = try XCTUnwrap(PatientSteroids.advice(onSteroid("Prednisolone", 10, "ge1m")))
        XCTAssertFalse(a.lines.contains { $0.contains("≈") }, "prednisolone is the reference drug: no line comparing it with itself")
        let hc = try XCTUnwrap(PatientSteroids.advice(onSteroid("Hydrocortisone", 20, "ge1m")))
        XCTAssertEqual(hc.lines.first, "20 mg hydrocortisone a day ≈ 5 mg prednisolone a day.")
        XCTAssertTrue(a.lines.contains { $0.contains("hydrocortisone 100 mg IV at induction, then 200 mg/24 h") })
        XCTAssertTrue(a.lines.contains { $0.contains("dexamethasone 6–8 mg IV") })
        XCTAssertTrue(a.source.contains("doi:10.1111/anae.14963"))
        // Adrenal insufficiency on replacement: always at risk, whatever the dose.
        var ai = record(["adrenal"]); ai.hx.adrenalKinds = ["insufficiency"]
        let b = try XCTUnwrap(PatientSteroids.advice(ai))
        XCTAssertTrue(b.atRisk)
        XCTAssertTrue(b.lines.contains { $0.contains("not adequate cover in primary adrenal insufficiency") })
        XCTAssertFalse(b.lines.contains { $0.hasPrefix("Labor") })
        ai.problems.insert("pregnant")
        XCTAssertTrue(try XCTUnwrap(PatientSteroids.advice(ai)).lines.contains { $0.hasPrefix("Labor") })
        // Not enough recorded, an unknown drug, or no item: no dosing.
        let missing = try XCTUnwrap(PatientSteroids.advice(onSteroid("Prednisolone", nil, "ge1m")))
        XCTAssertFalse(missing.atRisk)
        XCTAssertTrue(missing.headline.hasPrefix("Record"))
        let unknown = try XCTUnwrap(PatientSteroids.advice(onSteroid("Budesonide", 9, "ge1m")))
        XCTAssertFalse(unknown.atRisk)
        XCTAssertTrue(unknown.headline.contains("not converted"))
        XCTAssertNil(PatientSteroids.advice(record(["htn"])))
        var empty = record(["adrenal"]); empty.hx.adrenalKinds = []
        XCTAssertNil(PatientSteroids.advice(empty))
    }

    func testChildrenUseTheirThreshold() throws {
        var c = onSteroid("Prednisolone", 2, "ge1m")
        c.ageYears = 8; c.heightCm = 128; c.weightKg = 26
        // 2 mg prednisolone ≈ 8 mg hydrocortisone, over a BSA of about 0.96 m²: about 8.3 mg/m², under 10.
        XCTAssertFalse(try XCTUnwrap(PatientSteroids.advice(c)).atRisk)
        c.hx.steroidDailyMg = 3
        let a = try XCTUnwrap(PatientSteroids.advice(c))
        XCTAssertTrue(a.atRisk, "about 12.5 mg/m² of hydrocortisone a day")
        XCTAssertTrue(a.lines.contains { $0.contains("2 mg/kg IV at induction (52 mg at 26 kg)") })
        c.heightCm = nil
        XCTAssertTrue(try XCTUnwrap(PatientSteroids.advice(c)).headline.contains("height and weight"))
    }

    // MARK: Thyroid suggestion

    func testThyroidSuggestionFromTheTSH() {
        var r = record(["htn"])
        XCTAssertNil(PatientCrossFill.thyroidSuggestion(r))
        r.labs["tsh"] = 2.1
        XCTAssertNil(PatientCrossFill.thyroidSuggestion(r), "normal")
        r.labs["tsh"] = 8.2
        XCTAssertEqual(PatientCrossFill.thyroidSuggestion(r), "TSH 8.2 mIU/L, high: add thyroid disease (hypothyroid)?")
        r.labs["ft4"] = 0.6
        XCTAssertEqual(PatientCrossFill.thyroidSuggestion(r), "TSH 8.2 mIU/L, high; Free T4 0.6 ng/dL, low: add thyroid disease (hypothyroid)?")
        r.labs["ft4"] = 2.4
        XCTAssertNotNil(PatientCrossFill.thyroidReading(r))
        XCTAssertNil(PatientCrossFill.thyroidReading(r)?.type ?? nil, "a free T4 that disagrees leaves the type")
        r.labs = ["tsh": 0.1]
        XCTAssertEqual(PatientCrossFill.thyroidReading(r)?.type ?? nil, "hyper")
        r.labs = ["ft4": 0.5]
        XCTAssertNotNil(PatientCrossFill.thyroidSuggestion(r))
        XCTAssertNil(PatientCrossFill.thyroidReading(r)?.type ?? nil, "free T4 alone gives no type")
        // Accepting it files Thyroid disease, and the store's fill opens the Thyroid labs.
        r.labs = ["tsh": 9]
        let before = r
        PatientCrossFill.acceptThyroidSuggestion(&r)
        PatientCrossFill.apply(before: before, after: &r)
        XCTAssertTrue(r.has("thyroid"))
        XCTAssertEqual(r.hx.thyroidType, "hypo")
        XCTAssertTrue(r.labSections.contains("thyroid"))
        XCTAssertNil(PatientCrossFill.thyroidSuggestion(r), "recorded: nothing to offer")
    }

    // MARK: Warnings

    func testWarnings() {
        for id in ["gastric-bypass", "dysphagia", "esophageal-disorder", "hiatal-hernia", "gastroparesis", "full-stomach"] {
            XCTAssertEqual(PatientWarnings.tags(id, record([id])), ["Aspiration risk"], id)
        }
        XCTAssertTrue(PatientWarnings.tags("gerd", record(["gerd"])).isEmpty, "not on Ben's list")
        var r = record(["gi-bleed", "hiatal-hernia", "gastroparesis"])
        XCTAssertEqual(PatientWarnings.tags("gi-bleed", r), ["Heparin caution"])
        r.hx.giBleedStatus = "active"; r.hx.giBleedSite = "upper"
        XCTAssertEqual(PatientWarnings.tags("gi-bleed", r), ["Heparin caution (active bleed)"])
        let lines = PatientWarnings.lines(r)
        XCTAssertEqual(lines.map(\.label), ["Aspiration risk", "Heparin caution"])
        XCTAssertEqual(lines.map(\.text), ["hiatal hernia, gastroparesis", "active upper GI bleed"])
        XCTAssertTrue(lines.allSatisfy(\.alert))
        // On the summary, after the systems.
        let h = PatientSummary.historyLines(r)
        let gi = h.firstIndex { $0.label == "GI & liver" }, asp = h.firstIndex { $0.label == "Aspiration risk" }
        XCTAssertNotNil(gi); XCTAssertNotNil(asp)
        if let gi, let asp { XCTAssertGreaterThan(asp, gi) }
        XCTAssertTrue(PatientWarnings.lines(record(["htn"])).isEmpty)
    }

    // MARK: TEE screen

    private func ids(_ s: [TEESuggestion]) -> Set<String> { Set(s.map(\.item.id)) }

    func testGIHistoryFindingsAndSuggestions() {
        let bypass = PatientTEE.evaluate(record(["gastric-bypass"]))
        XCTAssertEqual(bypass.findings.map(\.item.id), ["gi-surgery"])
        XCTAssertEqual(bypass.findings.first?.from, ["History: gastric bypass"])
        XCTAssertEqual(PatientTEE.evaluate(record(["dysphagia"])).findings.map(\.item.id), ["dysphagia"])
        let hernia = PatientTEE.evaluate(record(["hiatal-hernia"]))
        XCTAssertTrue(hernia.findings.isEmpty, "a suggestion only")
        XCTAssertEqual(hernia.suggestions.first { $0.item.id == "hiatal-hernia" }?.why, "Hiatal hernia recorded: is it symptomatic?")
        // Reflux keeps its own question.
        XCTAssertEqual(PatientTEE.evaluate(record(["gerd"])).suggestions.first?.why, "Reflux or hiatal hernia recorded: is a hiatal hernia symptomatic?")
        // An esophageal disorder: its type and previous procedure are read.
        var e = record(["esophageal-disorder"])
        XCTAssertEqual(ids(PatientTEE.evaluate(e).suggestions), ["stricture"], "nothing named: the first esophageal item asks")
        e.hx.esophagealDisorderType = "Achalasia"
        XCTAssertEqual(ids(PatientTEE.evaluate(e).suggestions), ["motility"])
        e.hx.esophagealProcedure = true; e.hx.esophagealProcedureDetails = "Pneumatic dilation 2021"
        XCTAssertEqual(ids(PatientTEE.evaluate(e).suggestions), ["motility", "stricture"])
        e.hx.esophagealProcedureDetails = "Heller myotomy"
        XCTAssertTrue(ids(PatientTEE.evaluate(e).suggestions).contains("gi-surgery"))
        e.hx.esophagealProcedureDetails = "Esophageal stent"
        XCTAssertTrue(ids(PatientTEE.evaluate(e).suggestions).isSuperset(of: ["stricture", "tumor"]))
        e.hx.esophagealProcedure = false
        XCTAssertEqual(ids(PatientTEE.evaluate(e).suggestions), ["motility"], "No previous procedure: its text is not read")
        XCTAssertTrue(PatientTEE.evaluate(e).findings.isEmpty, "never counted on its own")
    }

    func testGIBleed() {
        var r = record(["gi-bleed"])
        r.hx.giBleedStatus = "active"; r.hx.giBleedSite = "upper"
        let active = PatientTEE.evaluate(r)
        XCTAssertEqual(active.level, .absolute)
        XCTAssertEqual(active.findings.map(\.item.id), ["ugib-active"])
        r.hx.giBleedStatus = "resolved"
        let resolved = PatientTEE.evaluate(r)
        XCTAssertTrue(resolved.findings.isEmpty)
        XCTAssertEqual(ids(resolved.suggestions), ["ugib-recent"])
        r.hx.giBleedSite = "lower"; r.hx.giBleedDetails = "Diverticular bleed"
        XCTAssertTrue(PatientTEE.evaluate(r).suggestions.isEmpty, "a lower GI bleed asks nothing")
        r.hx.giBleedSite = nil; r.hx.giBleedStatus = "active"
        XCTAssertEqual(ids(PatientTEE.evaluate(r).suggestions), ["ugib-active"], "active, site not recorded: asked")
    }

    func testBleedingDisordersAndThrombocytopeniaCount() {
        for p in ["vwd", "hemophilia-a", "hemophilia-b", "thrombocytopenia"] {
            XCTAssertNotNil(PatientTEE.evaluate(record([p])).finding("coagulopathy"), p)
        }
    }

    func testPreviousEGDAndTEE() throws {
        var r = record(["htn"])
        r.teeScreen.previousEGD = true; r.teeScreen.egdDate = "03/2025"; r.teeScreen.egdFindings = "LA grade B esophagitis"
        r.teeScreen.previousTEE = true; r.teeScreen.teeDate = "2023"
        XCTAssertEqual(r.teeScreen.egdText, "Previous EGD 03/2025: LA grade B esophagitis")
        XCTAssertEqual(r.teeScreen.teeText, "Previous TEE 2023")
        XCTAssertEqual(PatientTEE.evaluate(r).suggestions.map(\.why), ["Previous EGD: “esophagitis”."], "the EGD's findings are read to confirm")
        XCTAssertFalse(r.teeScreen.isEmpty)
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again.teeScreen, r.teeScreen)
        r.teeScreen.previousEGD = false
        XCTAssertEqual(r.teeScreen.egdText, "No previous EGD")
        XCTAssertTrue(PatientTEE.evaluate(r).suggestions.isEmpty, "No: what was typed is not read")
        // A screen saved before 1.9, and a malformed one.
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"teeScreen":{"yes":["dysphagia"],"reviewed":true}}"#.utf8))
        XCTAssertNil(old.teeScreen.previousEGD)
        XCTAssertEqual(old.teeScreen.egdFindings, "")
        XCTAssertNil(old.teeScreen.teeText)
        let odd = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"teeScreen":{"previousEGD":"yes","teeDate":2023}}"#.utf8))
        XCTAssertNil(odd.teeScreen.previousEGD)
        XCTAssertEqual(odd.teeScreen.teeDate, "")
        XCTAssertTrue(PatientTEEScreen().isEmpty)
    }

    func testTheLinksDemo() {
        let r = PatientDemo.links
        let res = PatientTEE.evaluate(r)
        XCTAssertEqual(res.findings.map(\.item.id), ["gi-surgery"])
        XCTAssertEqual(ids(res.suggestions), ["hiatal-hernia", "ugib-recent", "motility", "stricture", "esophagitis"])
        XCTAssertTrue(try XCTUnwrap(PatientSteroids.advice(r)).atRisk)
        XCTAssertEqual(PatientPrecautions.suggestions(r).map(\.precaution), ["contact", "droplet", "airborne"])
        XCTAssertNotNil(PatientCrossFill.thyroidSuggestion(r))
        XCTAssertEqual(PatientWarnings.lines(r).map(\.label), ["Aspiration risk", "Heparin caution"])
    }
}
