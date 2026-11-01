import XCTest
@testable import PeriopSignal

/// The TEE screen: the ASE/SCA 2013 classes, what the record counts on its own, what it only offers to confirm, the
/// prompt, the card and handoff lines, and decoding.
final class PatientTEETests: XCTestCase {

    func testCatalogMatchesTheGuidelineTable() {
        let ids = PatientTEE.items.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "item ids are unique")
        // Hahn 2013, Table 6.
        let hahnAbsolute: Set<String> = ["perforated-viscus", "stricture", "tumor", "perforation", "diverticulum", "ugib-active"]
        let hahnRelative: Set<String> = ["radiation", "gi-surgery", "ugib-recent", "barretts", "dysphagia", "neck", "hiatal-hernia",
                                         "varices", "coagulopathy", "esophagitis", "pud"]
        for id in hahnAbsolute {
            XCTAssertEqual(PatientTEE.item(id)?.level, .absolute, id)
            XCTAssertEqual(PatientTEE.item(id)?.source, .hahn2013, id)
        }
        for id in hahnRelative {
            XCTAssertEqual(PatientTEE.item(id)?.level, .relative, id)
            XCTAssertEqual(PatientTEE.item(id)?.source, .hahn2013, id)
        }
        // Beyond the table: the ASA/SCA 2010 survey's absolute ones, and scleroderma or achalasia counted as relative.
        XCTAssertEqual(PatientTEE.item("esophagectomy")?.level, .absolute)
        XCTAssertEqual(PatientTEE.item("esophagectomy")?.source, .asa2010)
        XCTAssertEqual(PatientTEE.item("te-fistula")?.source, .asa2010)
        XCTAssertEqual(PatientTEE.item("motility")?.level, .relative)
        for s in TEESource.allCases { XCTAssertTrue(s.url.hasPrefix("https://doi.org/10."), s.rawValue) }
    }

    func testNothingRecorded() {
        let r = PatientRecord()
        let res = PatientTEE.evaluate(r)
        XCTAssertEqual(res.level, TEEClass.none)
        XCTAssertFalse(res.screened)
        XCTAssertNil(PatientTEE.line(r), "no line when nothing is flagged")
        XCTAssertEqual(PatientTEE.status(r), "Not screened")
        var reviewed = r; reviewed.teeScreen.reviewed = true
        XCTAssertTrue(PatientTEE.evaluate(reviewed).screened)
        XCTAssertEqual(PatientTEE.status(reviewed), "Screened: no contraindication recorded")
        XCTAssertNil(PatientTEE.line(reviewed))
    }

    func testRecordCountsOnItsOwn() {
        var r = PatientRecord()
        r.problems = ["varices", "bleeding", "spine-fusion"]
        r.airwaySigns = ["radiation"]
        r.surgeries = [PatientSurgery(name: "Laparoscopic Nissen fundoplication", procedureID: "nissen", date: PatientMonthYear(year: 2018)),
                       PatientSurgery(name: "Laparoscopic cholecystectomy")]
        let res = PatientTEE.evaluate(r)
        XCTAssertEqual(res.level, .relative)
        XCTAssertEqual(Set(res.findings.map(\.item.id)), ["varices", "coagulopathy", "neck", "radiation", "gi-surgery"])
        XCTAssertEqual(res.finding("gi-surgery")?.from, ["Past surgical history: Laparoscopic Nissen fundoplication (2018)"], "a cholecystectomy is not upper GI surgery")
        XCTAssertEqual(res.finding("radiation")?.from, ["Airway: Neck radiation changes"])
        let line = PatientTEE.line(r)
        XCTAssertEqual(line?.label, "TEE screen")
        XCTAssertTrue(line?.text.hasPrefix("Relative contraindications: ") ?? false, line?.text ?? "")
        XCTAssertTrue(line?.alert ?? false)
        XCTAssertEqual(line?.marks, [], "bold red only for an absolute contraindication")
    }

    func testTypedOperations() {
        XCTAssertEqual(PatientTEE.surgeryItem(PatientSurgery(name: "Ivor Lewis esophagectomy")), "esophagectomy")
        XCTAssertEqual(PatientTEE.surgeryItem(PatientSurgery(name: "Oesophagectomy for cancer")), "esophagectomy", "British spelling")
        XCTAssertEqual(PatientTEE.surgeryItem(PatientSurgery(name: "Roux-en-Y gastric bypass")), "gi-surgery")
        XCTAssertEqual(PatientTEE.surgeryItem(PatientSurgery(name: "Toupet fundoplication")), "gi-surgery")
        XCTAssertEqual(PatientTEE.surgeryItem(PatientSurgery(name: "Heller myotomy")), "gi-surgery")
        XCTAssertNil(PatientTEE.surgeryItem(PatientSurgery(name: "Total knee arthroplasty")))
        XCTAssertNil(PatientTEE.surgeryItem(PatientSurgery(name: "EGD with biopsy")), "endoscopy is not surgery")
        XCTAssertNil(PatientTEE.surgeryItem(PatientSurgery(name: "Open appendectomy")))
    }

    func testAbsoluteLineIsMarked() {
        var r = PatientRecord()
        r.surgeries = [PatientSurgery(name: "Ivor Lewis esophagectomy", procedureID: "ivor-lewis")]
        r.teeScreen.set("barretts", true)
        let res = PatientTEE.evaluate(r)
        XCTAssertEqual(res.level, .absolute)
        XCTAssertEqual(res.findings.map(\.item.id), ["esophagectomy", "barretts"], "absolute first")
        let line = PatientTEE.line(r)
        XCTAssertEqual(line?.text, "ABSOLUTE contraindication to the probe: esophagectomy; relative: Barrett's esophagus")
        XCTAssertEqual(line?.marks, ["ABSOLUTE contraindication to the probe: esophagectomy"])
    }

    func testSuggestionsAreNotCounted() {
        var r = PatientRecord()
        r.problems = ["gerd", "cirrhosis"]
        r.labs = ["plt": 82, "inr": 1.9]
        r.systemNotes = ["gi": "Known Barrett's on surveillance; no dysphagia"]
        var res = PatientTEE.evaluate(r)
        XCTAssertEqual(res.level, TEEClass.none, "suggestions never count on their own")
        let ids = res.suggestions.map(\.item.id)
        XCTAssertTrue(ids.contains("hiatal-hernia"))
        XCTAssertTrue(ids.contains("varices"))
        XCTAssertTrue(ids.contains("coagulopathy"))
        XCTAssertTrue(ids.contains("barretts"))
        XCTAssertFalse(ids.contains("dysphagia"), "a negated mention is skipped")
        // Answering takes it off the suggestions; Yes counts it.
        r.teeScreen.set("barretts", true)
        r.teeScreen.set("hiatal-hernia", false)
        res = PatientTEE.evaluate(r)
        XCTAssertEqual(res.findings.map(\.item.id), ["barretts"])
        XCTAssertFalse(res.suggestions.contains { $0.item.id == "barretts" || $0.item.id == "hiatal-hernia" })
        // Recorded varices replace the cirrhosis question.
        r.problems.insert("varices")
        XCTAssertFalse(PatientTEE.evaluate(r).suggestions.contains { $0.item.id == "varices" })
        XCTAssertNotNil(PatientTEE.evaluate(r).finding("varices"))
    }

    func testMention() {
        XCTAssertEqual(PatientTEE.mention("Oesophageal stricture dilated 2022", ["stricture"]), "stricture")
        XCTAssertNil(PatientTEE.mention("Denies dysphagia", ["dysphagia"]))
        XCTAssertNil(PatientTEE.mention("no history of varices", ["varices"]))
        XCTAssertEqual(PatientTEE.mention("No reflux. Dysphagia to solids", ["dysphagia"]), "dysphagia", "a negation in another sentence does not count")
        XCTAssertNil(PatientTEE.mention("Toe amputation", ["tee"]))
    }

    func testPlannedAndPrompt() {
        var r = PatientRecord()
        r.setProcedures(PlannedProcedure.parse("Laparoscopic sigmoid colectomy"))
        XCTAssertFalse(PatientTEE.planned(r))
        XCTAssertTrue(PatientTEE.prompts(r).isEmpty)
        r.setProcedures(PlannedProcedure.parse("TEE"))
        XCTAssertTrue(PatientTEE.planned(r), "a TEE as the procedure")
        r.setProcedures(PlannedProcedure.parse("Aortic valve replacement"))
        XCTAssertTrue(PatientRules.echoFirst(r))
        XCTAssertTrue(PatientTEE.planned(r), "echo-first surgery")
        let p = PatientTEE.prompts(r)
        XCTAssertEqual(p.map(\.id), ["tee"])
        XCTAssertEqual(p.first?.route, "workup:tee")
        XCTAssertNil(p.first?.done)
        r.teeScreen.reviewed = true
        XCTAssertEqual(PatientTEE.prompts(r).first?.done, "TEE screen: no contraindication recorded")
        XCTAssertFalse(PatientRules.prompts(r).contains { $0.id == "tee" }, "the rules' prompts stay reference routes")
    }

    func testCardsAndHandoffs() {
        let r = PatientDemo.cardiac
        let res = PatientTEE.evaluate(r)
        XCTAssertEqual(res.level, .relative, "the demo shows a relative contraindication")
        XCTAssertEqual(Set(res.findings.map(\.item.id)), ["gi-surgery", "dysphagia"])
        XCTAssertTrue(res.suggestions.contains { $0.item.id == "coagulopathy" }, "platelets 96 and INR 1.8 offered to confirm")
        let echo = PatientSummary.intraopPartLines(r, "echo")
        XCTAssertEqual(echo.first?.label, "TEE screen", echo.map(\.text).joined(separator: " | "))
        let full = HandoffWriter.text(r)
        XCTAssertTrue(full.contains("TEE screen: Relative contraindications: previous upper GI surgery, dysphagia"), full)
        let short = HandoffWriter.shortText(r)
        XCTAssertTrue(short.contains("TEE screen: Relative contraindications"), short)
        // Nothing flagged: no line anywhere.
        XCTAssertFalse(HandoffWriter.text(PatientDemo.record).contains("TEE screen"))
        XCTAssertFalse(HandoffWriter.shortText(PatientDemo.record).contains("TEE screen"))
    }

    func testDecoding() throws {
        var r = PatientRecord()
        r.teeScreen = PatientTEEScreen(yes: ["dysphagia"], no: ["stricture"], reviewed: true, notes: "EGD 2025 normal")
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again.teeScreen, r.teeScreen)
        // A record saved before the screen opens with an empty one.
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"procedure":"CABG"}"#.utf8))
        XCTAssertEqual(old.teeScreen, PatientTEEScreen())
        // A malformed screen falls back field by field.
        let odd = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"teeScreen":{"yes":["varices"],"reviewed":"yes"}}"#.utf8))
        XCTAssertEqual(odd.teeScreen.yes, ["varices"])
        XCTAssertFalse(odd.teeScreen.reviewed)
        XCTAssertTrue(PatientRecord().teeScreen.isEmpty)
        XCTAssertTrue(PatientRecord().isEmpty, "an empty screen leaves the record empty")
    }
}
