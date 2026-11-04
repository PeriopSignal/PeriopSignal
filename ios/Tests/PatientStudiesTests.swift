import XCTest
@testable import PeriopSignal

/// My Patient 1.8.1: the Studies (carotid and radial artery ultrasound, pulmonary function tests), their cautions, and
/// the aortic disease items in the past history.
final class PatientStudiesTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func note(_ s: String, choices: [String: String] = [:]) -> PatientNoteReading { PatientNote.read(s, now: now, choices: choices) }
    private func ids(_ n: PatientNoteReading) -> Set<String> { Set(n.findings.map(\.id)) }
    private func quick(_ s: String, choices: [String: String] = [:]) -> QuickAddReading {
        QuickAdd.read(s, record: PatientRecord(), tab: .preop, now: now, choices: choices)
    }
    private func ids(_ q: QuickAddReading) -> Set<String> { Set(q.findings.map(\.id)) }

    // MARK: Records

    func testRoundTripAndOlderRecords() throws {
        let r = PatientDemo.cardiac
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
        XCTAssertEqual(back.carotid.left.stenosis, "ge70")
        XCTAssertEqual(back.radial.harvest, "left")
        XCTAssertEqual(back.pft.fev1Pct, 58)
        XCTAssertEqual(back.hx.aneurysms["abdominal"]?.cm, 4.8)

        // A record from before 1.8.1 has none of the fields: it opens with them empty.
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data("{\"ageYears\":70,\"problems\":[\"htn\"]}".utf8))
        XCTAssertTrue(old.carotid.isEmpty)
        XCTAssertTrue(old.radial.isEmpty)
        XCTAssertTrue(old.pft.isEmpty)
        XCTAssertTrue(old.aortaSizes.isEmpty)
        XCTAssertFalse(old.hasStudies)
        XCTAssertTrue(PatientStudies.cautions(old).isEmpty)

        // Malformed or unknown values fall back field by field.
        let odd = try JSONDecoder().decode(PatientRecord.self, from: Data("{\"carotid\":{\"left\":{\"stenosis\":\"ge70\",\"psv\":\"fast\"}},\"pft\":{\"fev1Pct\":\"x\",\"pattern\":\"obstruction\"},\"radial\":7}".utf8))
        XCTAssertEqual(odd.carotid.left.stenosis, "ge70")
        XCTAssertNil(odd.carotid.left.psv)
        XCTAssertEqual(odd.pft.pattern, "obstruction")
        XCTAssertNil(odd.pft.fev1Pct)
        XCTAssertTrue(odd.radial.isEmpty)
    }

    func testWorkupsAndEditors() {
        XCTAssertEqual(PatientEditor.workup("carotid").title, "Carotid Ultrasound")
        XCTAssertEqual(PatientEditor.workup("radial").title, "Radial Artery Ultrasound")
        XCTAssertEqual(PatientEditor.workup("pft").title, "Pulmonary Function Tests")
    }

    // MARK: Summaries

    func testCarotidSummary() {
        var c = PatientCarotid()
        XCTAssertEqual(c.summary, "Carotid US")
        c.right = CarotidSide(stenosis: "50-69", psv: 182, edv: 54)
        c.left = CarotidSide(stenosis: "ge70", vertebral: "reversed")
        c.date = PatientMonthYear(month: 9, year: 2026)
        XCTAssertEqual(c.summary, "Carotid US 09/2026: R ICA 50–69% (PSV 182, EDV 54), L ICA ≥70%; L vertebral reversed")
        c.right = CarotidSide(stenosis: "normal")
        XCTAssertTrue(c.summary.contains("R ICA no stenosis"), c.summary)
        XCTAssertEqual(c.severeSides, ["left"])
    }

    func testRadialSummary() {
        var r = PatientRadial()
        r.harvest = "left"
        r.left = RadialSide(diameter: 2.7, calcified: false, ulnar: "adequate")
        r.right = RadialSide(diameter: 2.3, calcified: true)
        XCTAssertEqual(r.summary, "Radial US: planned left harvest; R 2.3 mm, calcified; L 2.7 mm, not calcified, ulnar compensation adequate")
        r.harvest = "none"
        XCTAssertNil(r.harvestSide)
        XCTAssertTrue(r.summary.contains("no harvest planned"))
    }

    func testPFTSummaryRatioAndGold() {
        var p = PatientPFT()
        p.fev1 = 1.86; p.fev1Pct = 58; p.fvc = 3.21; p.fvcPct = 79; p.ratioTyped = 58
        p.pattern = "obstruction"; p.severity = "moderate"
        XCTAssertEqual(p.ratio ?? 0, 0.58, accuracy: 0.0001, "58 and 0.58 read the same")
        p.ratioTyped = 0.58
        XCTAssertEqual(p.ratio ?? 0, 0.58, accuracy: 0.0001)
        for bad in [140.0, 1.2, 19.9, 0] {
            p.ratioTyped = bad
            XCTAssertNil(p.ratio, "\(bad): neither a ratio nor a percentage")
        }
        p.ratioTyped = 20
        XCTAssertEqual(p.ratio ?? 0, 0.20, accuracy: 0.0001)
        p.ratioTyped = 0.58
        XCTAssertEqual(p.gold, 2)
        // No descriptor; "if COPD" unless COPD is in the history.
        XCTAssertEqual(p.goldText(copd: false), "FEV1 58% predicted (GOLD 2 if COPD)")
        XCTAssertEqual(p.goldText(copd: true), "FEV1 58% predicted (GOLD 2)")
        XCTAssertTrue(p.summary(copd: false).hasPrefix("PFT: obstruction, moderate; FEV1 58% predicted (GOLD 2 if COPD); "), p.summary(copd: false))
        XCTAssertFalse(p.summary(copd: false, gold: false).contains("GOLD"))
        XCTAssertTrue(p.summary(copd: false).contains("FEV1 1.86 L (58%), FVC 3.21 L (79%), FEV1/FVC 0.58"))
        var r = PatientRecord()
        r.pft = p
        XCTAssertTrue(PatientSummary.assessmentLines(r).contains { $0.text.contains("(GOLD 2 if COPD)") })
        r.problems = ["copd"]
        XCTAssertTrue(PatientSummary.assessmentLines(r).contains { $0.text.contains("(GOLD 2)") })
        XCTAssertTrue(HandoffWriter.text(r).contains("FEV1 58% predicted (GOLD 2)"))

        // GOLD only when the lab reads obstruction, FEV1 % predicted is entered and FEV1/FVC is entered and below 0.70.
        for other in ["restriction", "mixed", "normal", "nonspecific"] {
            p.pattern = other
            XCTAssertNil(p.gold, other)
        }
        p.pattern = "obstruction"
        p.ratioTyped = 72
        XCTAssertNil(p.gold, "GOLD needs FEV1/FVC below 0.70")
        p.ratioTyped = 0.70
        XCTAssertNil(p.gold, "0.70 is not below 0.70")
        p.ratioTyped = nil
        XCTAssertNil(p.gold, "nor a ratio left blank")
        p.ratioTyped = 0.58
        p.fev1Pct = nil
        XCTAssertNil(p.gold)

        // Restriction with no TLC is possible restriction; the chip stays Restriction.
        var q = PatientPFT()
        q.pattern = "restriction"
        XCTAssertEqual(q.summary(copd: false), "PFT: possible restriction (no TLC)")
        q.tlcPct = 72
        XCTAssertEqual(q.summary(copd: false), "PFT: restriction; TLC 72%")
        XCTAssertEqual(PatientPFT.patterns.first { $0.id == "restriction" }?.label, "Restriction")
    }

    func testGoldBandEdges() {
        let cases: [(Double, Int)] = [(80, 1), (79, 2), (79.9, 2), (50, 2), (49, 3), (30, 3), (29, 4), (100, 1), (12, 4)]
        for (pct, grade) in cases { XCTAssertEqual(PatientStudies.goldGrade(fev1Pct: pct), grade, "FEV1 \(pct)%") }
    }

    // MARK: Flags

    private func devices(_ ss: [String]) -> [PatientDevice] { ss.flatMap { PatientDevices.parse($0)?.devices(placedIntraop: true) ?? [] } }

    /// A1: a harvest with no steal on the other arm.
    func testHarvestReminderAndArm() throws {
        var r = PatientRecord()
        XCTAssertNil(PatientStudies.harvestReminder(r))
        r.radial.harvest = "none"
        XCTAssertNil(PatientStudies.harvestReminder(r))
        XCTAssertTrue(PatientStudies.cautions(r).isEmpty)

        r.radial.harvest = "left"
        XCTAssertEqual(PatientStudies.harvestReminder(r), "Planned left radial harvest: arterial line, IVs and BP cuff in the right arm.")
        XCTAssertEqual(PatientStudies.cautions(r).map(\.id), ["harvest"])
        // Steal on the harvest side: the reminder stands, and the vertebral caution keeps the right arm for the line.
        r.carotid.left.vertebral = "reversed"
        XCTAssertEqual(PatientStudies.harvestReminder(r), "Planned left radial harvest: arterial line, IVs and BP cuff in the right arm.")
        XCTAssertTrue(PatientStudies.cautions(r).first { $0.id == "vertebral-left" }?.text.contains("use the right arm for the arterial line and cuff") ?? false)
        r.carotid.left.vertebral = nil

        // In the intraoperative Lines card and the handoffs.
        let lines = PatientSummary.intraopPartLines(r, "lines")
        XCTAssertTrue(lines.contains { $0.label == "Arms" && $0.alert && $0.text.hasPrefix("Planned left radial harvest") }, lines.map(\.text).joined(separator: " | "))
        let full = HandoffWriter.text(r)
        XCTAssertTrue(full.contains("Arms: Planned left radial harvest: arterial line, IVs and BP cuff in the right arm."), full)
        let lineSection = try XCTUnwrap(full.range(of: "LINES & DEVICES"))
        let harvest = try XCTUnwrap(full.range(of: "Arms: Planned"))
        XCTAssertLessThan(lineSection.lowerBound, harvest.lowerBound, "told with the lines")
        XCTAssertEqual(full.components(separatedBy: "Planned left radial harvest").count, 2, "once")
        XCTAssertTrue(HandoffWriter.shortText(r).contains("Arms: Planned left radial harvest"))
        XCTAssertTrue(HandoffWriter.marks(r).contains("Planned left radial harvest"))
    }

    /// A2: harvest left, steal on the right only: one caution, femoral access; the vertebral caution offers no arm.
    func testHarvestWithStealOnTheOtherArm() {
        var r = PatientRecord()
        r.radial.harvest = "left"
        for flow in ["reversed", "partial"] {
            r.carotid.right.vertebral = flow
            let c = PatientStudies.cautions(r)
            let h = c.first { $0.id == "harvest" }
            XCTAssertEqual(h?.text, "Planned left radial harvest; the right arm may read low (subclavian steal). Consider femoral arterial access, and keep lines and the cuff off the left arm.", flow)
            XCTAssertEqual(h?.mark, "Consider femoral arterial access")
            XCTAssertFalse(c.contains { $0.id == "harvest-femoral" })
            let v = c.first { $0.id == "vertebral-right" }?.text ?? ""
            XCTAssertFalse(v.contains("arterial line"), "never sends the line to the harvest arm: " + v)
            XCTAssertTrue(v.contains("Tell the surgeon: a right internal mammary graft may have poor inflow."), v)
        }
        r.carotid.right.vertebral = "reversed"
        XCTAssertEqual(PatientStudies.cautions(r).first { $0.id == "vertebral-right" }?.text,
                       "Reversed right vertebral flow: suggests right subclavian or innominate stenosis. Right-arm BP may read low. Tell the surgeon: a right internal mammary graft may have poor inflow.")
        r.carotid.right.vertebral = "partial"
        XCTAssertEqual(PatientStudies.cautions(r).first { $0.id == "vertebral-right" }?.text,
                       "Partial (alternating) right vertebral flow: suggests early steal from a right subclavian or innominate stenosis. Compare arm BPs; right-arm BP may read low. Tell the surgeon: a right internal mammary graft may have poor inflow.")
        XCTAssertTrue(HandoffWriter.marks(r).contains("Consider femoral arterial access"))
    }

    /// A3: steal on both sides, with and without a harvest.
    func testStealOnBothSides() {
        var r = PatientRecord()
        r.carotid.right.vertebral = "reversed"
        r.carotid.left.vertebral = "partial"
        let both = "Vertebral flow reversed or partial on both sides: both arms may read low (subclavian steal). Consider femoral arterial access. Tell the surgeon: internal mammary grafts may have poor inflow."
        XCTAssertEqual(PatientStudies.cautions(r).map(\.text), [both])
        r.radial.harvest = "left"
        let c = PatientStudies.cautions(r)
        XCTAssertEqual(c.map(\.id), ["harvest", "vertebral-both"])
        XCTAssertEqual(c[0].text, "Planned left radial harvest: keep lines and the cuff off the left arm.")
        XCTAssertEqual(c[1].text, both)
        XCTAssertFalse(c.contains { $0.text.contains("arm for the arterial line") }, "no arm offered for the line")
    }

    /// A4: steal on one side, no harvest.
    func testReversedVertebralCaution() {
        var r = PatientRecord()
        r.carotid.right.vertebral = "antegrade"
        XCTAssertTrue(PatientStudies.cautions(r).isEmpty)
        r.carotid.right.vertebral = "absent"
        XCTAssertTrue(PatientStudies.cautions(r).isEmpty)
        r.carotid.right.vertebral = "reversed"
        let c = PatientStudies.cautions(r)
        XCTAssertEqual(c.map(\.id), ["vertebral-right"])
        XCTAssertEqual(c[0].text, "Reversed right vertebral flow: suggests right subclavian or innominate stenosis. Right-arm BP may read low; use the left arm for the arterial line and cuff. Tell the surgeon: a right internal mammary graft may have poor inflow.")
        r.carotid.right.vertebral = nil
        r.carotid.left.vertebral = "reversed"
        XCTAssertEqual(PatientStudies.cautions(r).first?.text, "Reversed left vertebral flow: suggests left subclavian stenosis. Left-arm BP may read low; use the right arm for the arterial line and cuff. Tell the surgeon: a left internal mammary graft may have poor inflow.")
        r.carotid.left.vertebral = "partial"
        XCTAssertEqual(PatientStudies.cautions(r).first?.text, "Partial (alternating) left vertebral flow: suggests early steal from a left subclavian stenosis. Compare arm BPs; left-arm BP may read low. Use the right arm for the arterial line and cuff. Tell the surgeon: a left internal mammary graft may have poor inflow.")
    }

    /// A5: lines on the harvest arm: a radial arterial line, and anything else.
    func testLinesOnTheHarvestArm() throws {
        var r = PatientRecord()
        r.radial.harvest = "left"
        r.devices = devices(["R radial art line 20g"])
        XCTAssertFalse(r.devices.isEmpty)
        XCTAssertTrue(PatientStudies.linesOnHarvestArm(r).isEmpty, "the other arm")
        r.devices += devices(["L radial art line 20g"])
        var c = PatientStudies.cautions(r)
        XCTAssertEqual(c.first { $0.id.hasPrefix("harvest-radial") }?.text, "Radial arterial line in the left (harvest) arm: tell the surgeon; a radial artery that has been catheterized should not be used as a graft.")
        XCTAssertFalse(c.contains { $0.id.hasPrefix("harvest-arm") })
        // Removed, it no longer counts.
        let i = try XCTUnwrap(r.devices.lastIndex { $0.kind == .arterial })
        r.devices[i].removed = true
        XCTAssertTrue(PatientStudies.linesOnHarvestArm(r).isEmpty)
        // A peripheral IV on the harvest arm.
        r.devices = devices(["18g lfa"])
        c = PatientStudies.cautions(r)
        let piv = try XCTUnwrap(c.first { $0.id.hasPrefix("harvest-arm") })
        XCTAssertTrue(piv.text.hasPrefix("On the left (harvest) arm: "), piv.text)
        XCTAssertTrue(piv.text.hasSuffix(". Move it to the other arm if you can."), piv.text)
        XCTAssertFalse(c.contains { $0.id.hasPrefix("harvest-radial") })
        XCTAssertTrue(PatientSummary.intraopPartLines(r, "lines").contains { $0.label == "Arms" && $0.text.hasPrefix("On the left (harvest) arm") })
    }

    func testFemoralAndVertebralSources() {
        XCTAssertTrue(PatientStudies.femoralSource.hasPrefix("With subclavian steal, pressure in that arm may read falsely low"))
        XCTAssertTrue(PatientStudies.vertebralSource.contains("Kilic ID, et al. Herz 2015"))
        for t in [PatientStudies.radialEvidence, PatientStudies.pftEvidence, PatientStudies.goldCaveat] {
            XCTAssertFalse(t.contains("1.5 mm") || t.contains("2.0 mm") || t.contains("GOLD 2025") || t.contains("ATS/ERS 2022"), t)
        }
        XCTAssertTrue(PatientStudies.goldCaveat.contains("GOLD 2026"))
    }

    func testSevereCarotidCaution() {
        var r = PatientRecord()
        for s in ["normal", "lt50", "50-69"] {
            r.carotid.left.stenosis = s
            XCTAssertFalse(PatientStudies.cautions(r).contains { $0.id == "carotid" }, s)
        }
        for s in ["ge70", "near", "occluded"] {
            r.carotid.left.stenosis = s
            XCTAssertTrue(PatientStudies.cautions(r).contains { $0.id == "carotid" }, s)
        }
        r.carotid.left.stenosis = "ge70"
        let lines = PatientSummary.assessmentLines(r)
        XCTAssertTrue(lines.contains { $0.label == "Carotid ultrasound" && $0.alert })
        XCTAssertTrue(lines.contains { $0.label == "Caution" && $0.text == "Severe carotid disease, left (≥70%): higher stroke risk with cardiac surgery." }, lines.map(\.text).joined(separator: " | "))
        r.carotid.right.stenosis = "occluded"
        XCTAssertTrue(PatientStudies.cautions(r).contains { $0.text.hasPrefix("Severe carotid disease, right (occluded) and left (≥70%):") })
        r.carotid.right.stenosis = nil
        XCTAssertTrue(HandoffWriter.text(r).contains("Caution: Severe carotid disease"))
        XCTAssertTrue(HandoffWriter.shortText(r).contains("Cautions: Severe carotid disease"))
        r.carotid.left.stenosis = "50-69"
        XCTAssertFalse(PatientSummary.assessmentLines(r).contains { $0.label == "Carotid ultrasound" && $0.alert })
    }

    func testEveryCautionHasASource() {
        let r = PatientDemo.cardiac
        let ids = Set(PatientStudies.cautions(r).map(\.id))
        XCTAssertEqual(ids, ["harvest", "harvest-arm-left", "carotid", "vertebral-left"], "the demo shows every caution")
        XCTAssertEqual(r.pft.gold, 2, "and a GOLD grade")
        for c in PatientStudies.cautions(r) { XCTAssertFalse(c.source.isEmpty, c.id) }
    }

    // MARK: The aorta

    func testAortaItemsAndSizes() {
        let aortaIDs = ["aaa", "aaa-ruptured", "taa", "taa-ruptured", "taaa", "taaa-ruptured", "dissection-a", "dissection-b", "aortic-repair-open", "evar", "tevar"]
        XCTAssertEqual(aortaIDs.compactMap { PatientCatalog.problem($0)?.label }, [
            "Abdominal aortic aneurysm", "Ruptured abdominal aortic aneurysm", "Thoracic aortic aneurysm", "Ruptured thoracic aortic aneurysm",
            "Thoracoabdominal aortic aneurysm", "Ruptured thoracoabdominal aortic aneurysm", "Aortic dissection, type A", "Aortic dissection, type B",
            "Prior open aortic repair", "Prior EVAR", "Prior TEVAR",
        ])
        var r = PatientRecord()
        r.hx.aneurysms = ["abdominal": PatientAneurysm(cm: 5.2), "thoracic": PatientAneurysm()]
        PatientHistoryDetails.sync(&r)
        XCTAssertEqual(r.problems, ["aaa", "taa"])
        let cvLine = PatientSummary.historyLines(r).first { $0.label == "Cardiovascular" }
        XCTAssertEqual(cvLine?.text, "aortopathy: abdominal aneurysm 5.2 cm, thoracic aneurysm")
        XCTAssertTrue(HandoffWriter.text(r).contains("abdominal aneurysm 5.2 cm"))
        // An aneurysm taken off takes its size with it.
        r.hx.aneurysms["abdominal"] = nil
        PatientHistoryDetails.sync(&r)
        XCTAssertEqual(r.problems, ["taa"])
        XCTAssertFalse(PatientSummary.historyLines(r).contains { $0.text.contains("5.2") })
    }

    func testRupturedAneurysmsAreASAV() {
        var r = PatientRecord()
        r.ageYears = 70
        for id in ["aaa-ruptured", "taa-ruptured", "taaa-ruptured"] {
            r.problems = ["htn", id]
            let s = PatientRules.asaSuggestion(r)
            XCTAssertEqual(s?.level, 5, id)
            XCTAssertTrue(s?.reasons.contains { $0.level == 5 && $0.example == "ruptured abdominal/thoracic aneurysm" } ?? false, id)
        }
        for id in ["aaa", "taa", "taaa", "dissection-a", "dissection-b", "evar", "tevar", "aortic-repair-open"] {
            r.problems = [id]
            XCTAssertNotEqual(PatientRules.asaSuggestion(r)?.level, 5, id)
        }
    }

    // MARK: Quick add and the note reader

    func testAorticAneurysmShorthand() {
        XCTAssertTrue(ids(note("HTN, AAA, CKD")).contains("problem:aaa"))
        XCTAssertFalse(ids(note("HTN, AAA, CKD")).contains("problem:pvd"), "an aneurysm is its own item now")
        XCTAssertTrue(ids(note("PAD with claudication")).contains("problem:pvd"))
        XCTAssertFalse(ids(note("PAD with claudication")).contains("problem:aaa"))
        XCTAssertTrue(ids(note("known abdominal aortic aneurysm")).contains("problem:aaa"))
        XCTAssertTrue(note("TAA").ambiguous.contains { $0.id == PatientNote.taaQuestion }, "bare: asked")
        XCTAssertTrue(ids(note("ascending aortic aneurysm")).contains("problem:taa"))
        XCTAssertTrue(ids(note("aortic root aneurysm")).contains("problem:taa"))
        XCTAssertFalse(ids(note("dilated aortic root")).contains("problem:taa"), "dilation is below aneurysm size")
        // A bare TAA (also a total ankle arthroplasty) is asked about, unless aortic words or a size say which.
        for s in ["HTN, TAA, CKD", "s/p L TAA"] {
            let n = note(s)
            XCTAssertFalse(ids(n).contains("problem:taa"), s)
            XCTAssertTrue(n.ambiguous.contains { $0.id == PatientNote.taaQuestion }, s)
            XCTAssertTrue(ids(note(s, choices: [PatientNote.taaQuestion: "taa"])).contains("problem:taa"), s)
            XCTAssertFalse(ids(note(s, choices: [PatientNote.taaQuestion: "ankle"])).contains("problem:taa"), s)
        }
        XCTAssertTrue(ids(note("TAA 4.6 cm")).contains("problem:taa"))
        XCTAssertTrue(ids(note("ascending aorta, TAA")).contains("problem:taa"))
        let ankle = note("TAA for ankle arthritis")
        XCTAssertFalse(ids(ankle).contains("problem:taa"))
        XCTAssertFalse(ankle.ambiguous.contains { $0.id == PatientNote.taaQuestion })
        XCTAssertTrue(ids(note("Crawford extent II")).contains("problem:taaa"))
        XCTAssertTrue(ids(note("triple A")).contains("problem:aaa"))
        XCTAssertTrue(ids(note("leaking AAA")).contains("problem:aaa-ruptured"))

        let taaa = ids(note("thoracoabdominal aortic aneurysm"))
        XCTAssertTrue(taaa.contains("problem:taaa"))
        XCTAssertFalse(taaa.contains("problem:aaa"), "not read as abdominal")
        let taaa2 = ids(note("TAAA, HTN"))
        XCTAssertTrue(taaa2.contains("problem:taaa"))
        XCTAssertFalse(taaa2.contains("problem:taa"))
        XCTAssertFalse(taaa2.contains("problem:aaa"))

        for s in ["rAAA", "ruptured AAA", "ruptured abdominal aortic aneurysm"] {
            let n = ids(note(s))
            XCTAssertTrue(n.contains("problem:aaa-ruptured"), s)
            XCTAssertFalse(n.contains("problem:aaa"), "the rupture replaces the aneurysm: " + s)
        }
        XCTAssertTrue(ids(note("ruptured TAA")).contains("problem:taa-ruptured"))
        XCTAssertTrue(ids(note("ruptured thoracoabdominal aneurysm")).contains("problem:taaa-ruptured"))
        XCTAssertTrue(ids(note("ruptured aortic aneurysm")).contains("problem:ruptured-aneurysm"), "no site: the general item")
        XCTAssertFalse(ids(note("s/p repair of ruptured AAA in 2015")).contains("problem:aaa-ruptured"), "a past rupture is not one now")
        XCTAssertFalse(ids(note("no AAA")).contains("problem:aaa"))
        XCTAssertFalse(ids(note("AAA screening negative")).contains("problem:aaa-ruptured"))
    }

    func testAneurysmSizes() {
        func size(_ s: String) -> (String, Double)? {
            for f in note(s).findings { if case .aneurysm(_, let cm?, _) = f.change { return (String(f.id.dropFirst("problem:".count)), cm) } }
            return nil
        }
        XCTAssertEqual(size("5.2 cm AAA")?.1, 5.2)
        XCTAssertEqual(size("5.2 cm AAA")?.0, "aaa")
        XCTAssertEqual(size("AAA 52 mm")?.1, 5.2)
        XCTAssertEqual(size("AAA measuring 5.5 cm")?.1, 5.5)
        XCTAssertEqual(size("5.0-cm infrarenal AAA")?.1, 5.0)
        XCTAssertEqual(size("TAA 4.8 cm")?.0, "taa")
        XCTAssertEqual(size("TAAA 6.1 cm")?.0, "taaa")
        XCTAssertNil(size("AAA 5.2"), "no unit: not read")
        XCTAssertNil(size("AAA 2019"), "a year")
        XCTAssertEqual(size("AAA 4.5 x 5.1 cm")?.1, 5.1, "the largest")
        XCTAssertNil(size("AAA 80 cm"), "implausible")
        let f = note("HTN, 5.2 cm AAA, CKD").findings.first { $0.id == "problem:aaa" }
        XCTAssertEqual(f?.label, "Abdominal aortic aneurysm, 5.2 cm")
        XCTAssertFalse(note("HTN, 5.2 cm AAA, CKD").other.contains("5.2"), "the size is read, not left over")

        // Added: the item and its size; again with another size: replaces it.
        var r = PatientRecord()
        let change = PatientNoteChange.aneurysm("abdominal", 5.2, false)
        let finding = PatientNoteFinding(id: "problem:aaa", section: PatientNote.Part.history, label: "", change: change)
        XCTAssertEqual(PatientNote.status(finding, in: r), .new)
        PatientNote.apply([change], to: &r)
        XCTAssertTrue(r.problems.contains("aaa"))
        XCTAssertEqual(r.hx.aneurysms["abdominal"]?.cm, 5.2)
        XCTAssertEqual(PatientNote.status(finding, in: r), .recorded)
        let bigger = PatientNoteFinding(id: "problem:aaa", section: PatientNote.Part.history, label: "", change: .aneurysm("abdominal", 5.8, false))
        XCTAssertEqual(PatientNote.status(bigger, in: r), .replaces("5.2 cm"))
        r.hx.aneurysms["abdominal"]?.ruptured = true
        XCTAssertEqual(PatientNote.status(bigger, in: r), .recorded, "the rupture says more")
    }

    func testDissectionShorthand() {
        for s in ["type A dissection", "ATAAD", "Stanford type A aortic dissection", "aortic dissection, type A", "Stanford A dissection"] {
            XCTAssertTrue(ids(note(s)).contains("problem:dissection-a"), s)
            XCTAssertFalse(ids(note(s)).contains("problem:dissection-b"), s)
        }
        for s in ["type B dissection", "TBAD", "uTBAD", "chronic type B aortic dissection", "DeBakey IIIb"] {
            XCTAssertTrue(ids(note(s)).contains("problem:dissection-b"), s)
        }
        // No type: asked, and read once answered.
        // "TAAD" is thoracic aortic aneurysm and dissection in the 2022 ACC/AHA guideline, not type A: asked too.
        for s in ["HTN, dissection, CKD", "known aortic dissection", "TAAD", "HTN, AoD"] {
            let n = note(s)
            XCTAssertTrue(n.ambiguous.contains { $0.id == PatientNote.dissectionQuestion }, s)
            XCTAssertFalse(ids(n).contains("problem:dissection-a"), s)
            XCTAssertFalse(ids(n).contains("problem:dissection-b"), s)
            let answered = note(s, choices: [PatientNote.dissectionQuestion: "dissection-b"])
            XCTAssertTrue(ids(answered).contains("problem:dissection-b"), s)
        }
        // Not a typed one, a surgical one or a denied one.
        for s in ["type B dissection", "axillary lymph node dissection", "radical neck dissection", "no dissection", "carotid dissection",
                  "type A personality", "influenza type B", "AD on donepezil"] {
            XCTAssertFalse(note(s).ambiguous.contains { $0.id == PatientNote.dissectionQuestion }, s)
        }
    }

    func testRepairsNeedThePast() {
        XCTAssertTrue(ids(note("AAA s/p EVAR")).contains("problem:evar"))
        XCTAssertTrue(ids(note("TEVAR 2019")).contains("problem:tevar"))
        XCTAssertTrue(ids(note("prior TEVAR for type B dissection")).contains("problem:tevar"))
        let open = ids(note("s/p open AAA repair"))
        XCTAssertTrue(open.contains("problem:aortic-repair-open"))
        XCTAssertFalse(open.contains("problem:aaa"), "a repaired aneurysm is the repair")
        XCTAssertTrue(ids(note("history of Bentall")).contains("problem:aortic-repair-open"))
        XCTAssertTrue(ids(note("s/p FEVAR 2021")).contains("problem:evar"))
        XCTAssertTrue(ids(note("prior BEVAR")).contains("problem:evar"))
        XCTAssertFalse(ids(note("s/p TEVAR")).contains("problem:evar"), "TEVAR is its own item")
        // The planned procedure is not past history.
        XCTAssertFalse(ids(note("72 yo M presenting for EVAR")).contains("problem:evar"))
        XCTAssertFalse(ids(note("scheduled for open AAA repair")).contains("problem:aortic-repair-open"))
    }

    func testQuickAddAorta() {
        let q = quick("74M, HTN, 5.2 cm AAA, s/p TEVAR 2019, dissection, TAA 48 mm, CKD")
        let found = ids(q)
        XCTAssertTrue(found.contains("problem:aaa"))
        XCTAssertTrue(found.contains("problem:tevar"))
        XCTAssertTrue(found.contains("problem:taa"))
        XCTAssertFalse(found.contains("procedure"), "no procedure in the line")
        XCTAssertTrue(q.ambiguous.contains { $0.id == PatientNote.dissectionQuestion }, "the dissection is asked about")
        if case .aneurysm(_, let cm, _)? = q.findings.first(where: { $0.id == "problem:taa" })?.change { XCTAssertEqual(cm, 4.8) } else { XCTFail("TAA size") }
        let chips = QuickAdd.chips(q, record: PatientRecord())
        XCTAssertTrue(chips.contains { $0.value == "Abdominal aortic aneurysm, 5.2 cm" }, chips.map(\.text).joined(separator: " | "))

        // An aneurysm opening the line is history, not the planned repair; "AAA repair" opening it is planned.
        let lead = quick("AAA 52 mm, HTN")
        XCTAssertFalse(ids(lead).contains("procedure"), lead.findings.map(\.label).joined(separator: " | "))
        XCTAssertTrue(ids(lead).contains("problem:aaa"))
        XCTAssertTrue(ids(quick("72M for EVAR, AAA 5.8 cm")).contains("procedure"))
        XCTAssertFalse(ids(quick("72M for EVAR, AAA 5.8 cm")).contains("problem:evar"))

        // Answered, the dissection is added.
        let answered = quick("HTN, dissection", choices: [PatientNote.dissectionQuestion: "dissection-a"])
        XCTAssertTrue(ids(answered).contains("problem:dissection-a"))

        // On the Intraoperative tab, history is not filed.
        let intraop = QuickAdd.read("5.2 cm AAA", record: PatientRecord(), tab: .intraop, now: now)
        XCTAssertFalse(ids(intraop).contains("problem:aaa"))
    }

    // MARK: Review fixes (parser)

    func testTAAWrittenOutAndBesideOtherWords() {
        func size(_ s: String) -> Double? {
            for f in note(s).findings where f.id == "problem:taa" { if case .aneurysm(_, let cm, _) = f.change { return cm } }
            return nil
        }
        // Written out: always read, whatever else the sentence holds.
        XCTAssertEqual(size("Ascending aortic aneurysm 5.1 cm and bicuspid AV for AVR and ascending aortic replacement"), 5.1)
        // A bare TAA with a size and no ankle words: read; "orthopnea" is not orthopedic.
        XCTAssertEqual(size("TAA 4.8 cm, orthopnea"), 4.8)
        // Both aortic and ankle words: asked.
        let both = note("TAA 4.8 cm, s/p R ankle arthroplasty")
        XCTAssertFalse(ids(both).contains("problem:taa"))
        XCTAssertTrue(both.ambiguous.contains { $0.id == PatientNote.taaQuestion })
        XCTAssertEqual(PatientNote.read("TAA 4.8 cm, s/p R ankle arthroplasty", now: now, choices: [PatientNote.taaQuestion: "taa"]).findings
            .compactMap { f -> Double? in if case .aneurysm("thoracic", let cm, _) = f.change { return cm }; return nil }, [4.8], "answered: with its size")
        // Ankle words alone: not read and not asked.
        let ankle = note("s/p L TAA by orthopedics")
        XCTAssertFalse(ids(ankle).contains("problem:taa"))
        XCTAssertFalse(ankle.ambiguous.contains { $0.id == PatientNote.taaQuestion })
    }

    func testOpenRepairNeedsTheAorta() {
        XCTAssertFalse(ids(note("s/p open repair of inguinal hernia")).contains("problem:aortic-repair-open"))
        XCTAssertTrue(ids(note("s/p open AAA repair 2015")).contains("problem:aortic-repair-open"))
        XCTAssertTrue(ids(note("AAA, s/p open repair 2015")).contains("problem:aortic-repair-open"))
    }

    func testRupturedAneurysmInTheHead() {
        var r = PatientRecord()
        PatientNote.apply(note("52F, SAH from ruptured aneurysm, for coiling").findings.map(\.change), to: &r)
        XCTAssertTrue(r.problems.isDisjoint(with: Set(PatientCatalog.aortaIDs + ["ruptured-aneurysm"])), r.problems.sorted().joined(separator: ", "))
        XCTAssertNotEqual(PatientRules.asaSuggestion(r)?.level, 5)
        // In another sentence of the same note, too.
        XCTAssertFalse(ids(note("Ruptured aneurysm. Hunt-Hess 3, for clipping.")).contains("problem:ruptured-aneurysm"))
        XCTAssertTrue(ids(note("ruptured aortic aneurysm")).contains("problem:ruptured-aneurysm"))
        XCTAssertTrue(ids(note("ruptured aneurysm, hypotensive")).contains("problem:ruptured-aneurysm"))
        // A left atrial appendage clip is not a head word.
        XCTAssertTrue(ids(note("ruptured aneurysm; LAA clip 2020")).contains("problem:ruptured-aneurysm"))
    }

    func testTAADReadsBothWays() {
        XCTAssertEqual(MedAbbreviations.lookup("TAAD")?.meanings.first?.text, "type A aortic dissection; also thoracic aortic aneurysm and dissection")
        XCTAssertTrue(note("TAAD").ambiguous.contains { $0.id == PatientNote.dissectionQuestion }, "still asked")
    }

    func testRupturedAAAOpeningTheLineIsTonightsRepair() {
        // 1.8.3 (Ben): "AAA" alone is the diagnosis, and a rupture alone says neither open nor EVAR, so the line files
        // the rupture and plans no repair; a repair written out is still tonight's ("ruptured AAA repair").
        for line in ["rAAA, HTN", "ruptured AAA, HTN"] {
            let q = quick(line)
            XCTAssertFalse(ids(q).contains("procedure"), line + ": " + q.findings.map(\.label).joined(separator: " | "))
            XCTAssertTrue(ids(q).contains("problem:aaa-ruptured"), line)
        }
        let repair = quick("ruptured AAA repair, HTN")
        XCTAssertTrue(ids(repair).contains("procedure"), repair.findings.map(\.label).joined(separator: " | "))
        XCTAssertTrue(ids(repair).contains("problem:aaa-ruptured"))
        XCTAssertTrue(ids(quick("78M for rAAA repair")).contains("problem:aaa-ruptured"))
        XCTAssertFalse(ids(quick("AAA 52 mm, HTN")).contains("procedure"), "an unruptured AAA opening the line stays history")
    }

    func testOtherDissectionsAreNotAsked() {
        for s in ["PCI complicated with dissection", "SCAD, dissection", "carotid artery dissection", "vertebral dissection"] {
            XCTAssertFalse(note(s).ambiguous.contains { $0.id == PatientNote.dissectionQuestion }, s)
        }
        XCTAssertTrue(note("HTN, dissection").ambiguous.contains { $0.id == PatientNote.dissectionQuestion })
    }

    // MARK: 181b: both radials, complex EVAR

    func testBothRadialsPlanned() {
        var r = PatientRecord()
        r.radial.harvest = "both"
        XCTAssertNil(r.radial.harvestSide)
        XCTAssertEqual(r.radial.harvestArms, ["right", "left"])
        XCTAssertTrue(r.radial.summary.contains("planned harvest of both radials"), r.radial.summary)
        let both = "Both radials planned for harvest: keep lines and the cuff off both arms; consider femoral arterial access."
        var c = PatientStudies.cautions(r)
        XCTAssertEqual(c.map(\.text), [both])
        XCTAssertEqual(c[0].mark, "Consider femoral arterial access")
        XCTAssertTrue(PatientSummary.intraopPartLines(r, "lines").contains { $0.label == "Arms" && $0.text == both })

        // Steal on one side: no arm offered for the arterial line.
        r.carotid.left.vertebral = "reversed"
        c = PatientStudies.cautions(r)
        XCTAssertEqual(c.first { $0.id == "vertebral-left" }?.text,
                       "Reversed left vertebral flow: suggests left subclavian stenosis. Left-arm BP may read low. Tell the surgeon: a left internal mammary graft may have poor inflow.")
        r.carotid.left.vertebral = "partial"
        XCTAssertFalse(PatientStudies.cautions(r).contains { $0.text.contains("arm for the arterial line") })
        // Steal on both sides: the approved both-sides caution.
        r.carotid.right.vertebral = "reversed"
        c = PatientStudies.cautions(r)
        XCTAssertEqual(c.map(\.id), ["harvest", "vertebral-both"])
        XCTAssertEqual(c[0].text, both)
        XCTAssertFalse(c.contains { $0.text.contains("arm for the arterial line") })
    }

    func testBothRadialsWithLines() {
        var r = PatientRecord()
        r.radial.harvest = "both"
        r.devices = devices(["R radial art line 20g", "L radial art line 20g", "18g lfa"])
        let c = PatientStudies.cautions(r)
        for side in ["right", "left"] {
            XCTAssertTrue(c.contains { $0.text == "Radial arterial line in the " + side + " (harvest) arm: tell the surgeon; a radial artery that has been catheterized should not be used as a graft." }, side)
        }
        let piv = c.first { $0.id == "harvest-arm-left" }
        XCTAssertTrue(piv?.text.hasPrefix("On the left (harvest) arm: ") ?? false, piv?.text ?? "none")
        XCTAssertTrue(piv?.text.hasSuffix(". Move it if you can.") ?? false, piv?.text ?? "none")
        XCTAssertFalse(c.contains { $0.text.contains("to the other arm") })
        XCTAssertEqual(Set(c.map(\.id)).count, c.count, "ids are unique")
    }

    func testComplexEVARGoesToTheNotes() {
        for (line, term) in [("s/p FEVAR 2021", "FEVAR 2021"), ("prior BEVAR", "BEVAR"), ("s/p F/BEVAR (2019)", "F/BEVAR 2019"),
                             ("history of fenestrated endovascular repair", "fenestrated endovascular repair")] {
            let f = note(line).findings.first { $0.id == "problem:evar" }
            guard case .problemNote("evar", let t)? = f?.change else { XCTFail(line); continue }
            XCTAssertEqual(t, term, line)
        }
        // Plain EVAR files as before.
        if case .problem("evar")? = note("s/p EVAR 2018").findings.first(where: { $0.id == "problem:evar" })?.change {} else { XCTFail("plain EVAR") }
        // Added: the chip and the words, once.
        var r = PatientRecord()
        r.systemNotes["cv"] = "On apixaban"
        r.hx.repairDetails = "Bifurcated graft"
        let change = PatientNoteChange.problemNote("evar", "FEVAR 2021")
        let finding = PatientNoteFinding(id: "problem:evar", section: PatientNote.Part.history, label: "", change: change)
        XCTAssertEqual(PatientNote.status(finding, in: r), .new)
        PatientNote.apply([change], to: &r)
        XCTAssertTrue(r.problems.contains("evar"))
        XCTAssertEqual(r.hx.repairDetails, "Bifurcated graft; FEVAR 2021", "to the repair details (1.8.1)")
        XCTAssertEqual(r.systemNotes["cv"], "On apixaban", "Other is untouched")
        XCTAssertEqual(PatientNote.status(finding, in: r), .recorded)
        PatientNote.apply([change], to: &r)
        XCTAssertEqual(r.hx.repairDetails, "Bifurcated graft; FEVAR 2021", "not twice")
        // Quick add: one chip, Prior EVAR.
        let q = quick("74M, HTN, s/p FEVAR 2021")
        XCTAssertTrue(QuickAdd.chips(q, record: PatientRecord()).contains { $0.value == "Prior EVAR" }, q.findings.map(\.label).joined(separator: " | "))
    }

    func testPatternsCompile() {
        for rx in PatientNote.allPatterns { XCTAssertNotNil(rx.re, rx.pattern) }
        for rx in QuickAdd.allPatterns { XCTAssertNotNil(rx.re, rx.pattern) }
    }
}
