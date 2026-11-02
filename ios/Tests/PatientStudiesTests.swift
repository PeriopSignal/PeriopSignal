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
        XCTAssertEqual(back.aortaSizes["aaa"], 4.8)

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
        XCTAssertEqual(p.ratio ?? 0, 0.58, accuracy: 0.0001, "55 and 0.55 read the same")
        p.ratioTyped = 0.58
        XCTAssertEqual(p.ratio ?? 0, 0.58, accuracy: 0.0001)
        p.ratioTyped = 140
        XCTAssertNil(p.ratio, "neither a ratio nor a percentage")
        p.ratioTyped = 0.58
        XCTAssertEqual(p.gold, 2)
        XCTAssertTrue(p.summary.hasPrefix("PFT: obstruction, moderate (GOLD 2 if post-bronchodilator)"), p.summary)
        XCTAssertTrue(p.summary.contains("FEV1 1.86 L (58%), FVC 3.21 L (79%), FEV1/FVC 0.58"), p.summary)

        // GOLD only when the lab reads obstruction (or mixed), with FEV1 % predicted.
        p.pattern = "restriction"
        XCTAssertNil(p.gold)
        p.pattern = "mixed"
        XCTAssertEqual(p.gold, 2)
        p.ratioTyped = 72
        XCTAssertNil(p.gold, "GOLD needs FEV1/FVC below 0.70")
        p.ratioTyped = nil
        XCTAssertEqual(p.gold, 2, "or the ratio not entered")
        p.fev1Pct = nil
        XCTAssertNil(p.gold)
    }

    func testGoldBandEdges() {
        let cases: [(Double, Int)] = [(80, 1), (79, 2), (79.9, 2), (50, 2), (49, 3), (30, 3), (29, 4), (100, 1), (12, 4)]
        for (pct, grade) in cases { XCTAssertEqual(PatientStudies.goldGrade(fev1Pct: pct), grade, "FEV1 \(pct)%") }
    }

    // MARK: Flags

    func testHarvestReminderAndArm() throws {
        var r = PatientRecord()
        XCTAssertNil(PatientStudies.harvestReminder(r))
        r.radial.harvest = "none"
        XCTAssertNil(PatientStudies.harvestReminder(r))
        XCTAssertTrue(PatientStudies.cautions(r).isEmpty)

        r.radial.harvest = "left"
        XCTAssertEqual(PatientStudies.harvestReminder(r), "Planned left radial harvest: arterial line, IVs and BP cuff in the right arm.")
        XCTAssertTrue(PatientStudies.linesOnHarvestArm(r).isEmpty)
        // Steal on the other arm: neither radial is right for the arterial line.
        var steal = r
        steal.carotid.right.vertebral = "reversed"
        XCTAssertTrue(PatientStudies.harvestReminder(steal)?.contains("consider a femoral arterial line") ?? false)
        steal.carotid.right.vertebral = nil
        steal.carotid.left.vertebral = "reversed"
        XCTAssertEqual(PatientStudies.harvestReminder(steal), "Planned left radial harvest: arterial line, IVs and BP cuff in the right arm.", "steal on the harvest side")
        // An arterial line on the other arm: no caution; on the harvest arm: one.
        r.devices = ["R radial art line 20g"].flatMap { PatientDevices.parse($0)?.devices(placedIntraop: true) ?? [] }
        XCTAssertFalse(r.devices.isEmpty)
        XCTAssertTrue(PatientStudies.linesOnHarvestArm(r).isEmpty)
        r.devices += ["L radial art line 20g"].flatMap { PatientDevices.parse($0)?.devices(placedIntraop: true) ?? [] }
        XCTAssertEqual(PatientStudies.linesOnHarvestArm(r).count, 1)
        XCTAssertTrue(PatientStudies.cautions(r).contains { $0.id == "harvest-arm" })
        // Removed, it no longer counts.
        let i = try XCTUnwrap(r.devices.lastIndex { $0.kind == .arterial })
        r.devices[i].removed = true
        XCTAssertTrue(PatientStudies.linesOnHarvestArm(r).isEmpty)

        // In the intraoperative Lines card and the handoffs.
        r.devices[i].removed = false
        let lines = PatientSummary.intraopPartLines(r, "lines")
        XCTAssertTrue(lines.contains { $0.label == "Radial harvest" && $0.alert }, lines.map(\.text).joined(separator: " | "))
        XCTAssertTrue(lines.contains { $0.label == "Harvest arm" })
        let full = HandoffWriter.text(r)
        XCTAssertTrue(full.contains("Radial harvest: Planned left radial harvest: arterial line, IVs and BP cuff in the right arm."), full)
        let lineSection = try XCTUnwrap(full.range(of: "LINES & DEVICES"))
        let harvest = try XCTUnwrap(full.range(of: "Radial harvest:"))
        XCTAssertLessThan(lineSection.lowerBound, harvest.lowerBound, "told with the lines")
        XCTAssertEqual(full.components(separatedBy: "Radial harvest:").count, 2, "once")
        XCTAssertTrue(HandoffWriter.shortText(r).contains("Radial harvest: Planned left radial harvest"))
        XCTAssertTrue(HandoffWriter.marks(r).contains("Planned left radial harvest"))
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
        XCTAssertTrue(lines.contains { $0.label == "Caution" && $0.text.hasPrefix("Severe carotid disease: left ICA ≥70%") }, lines.map(\.text).joined(separator: " | "))
        XCTAssertTrue(HandoffWriter.text(r).contains("Caution: Severe carotid disease"))
        XCTAssertTrue(HandoffWriter.shortText(r).contains("Cautions: Severe carotid disease"))
        r.carotid.left.stenosis = "50-69"
        XCTAssertFalse(PatientSummary.assessmentLines(r).contains { $0.label == "Carotid ultrasound" && $0.alert })
    }

    func testReversedVertebralCaution() {
        var r = PatientRecord()
        r.carotid.right.vertebral = "antegrade"
        XCTAssertTrue(PatientStudies.cautions(r).isEmpty)
        r.carotid.right.vertebral = "absent"
        XCTAssertTrue(PatientStudies.cautions(r).isEmpty)
        r.carotid.right.vertebral = "reversed"
        let c = PatientStudies.cautions(r)
        XCTAssertEqual(c.map(\.id), ["vertebral-right"])
        XCTAssertTrue(c[0].text.contains("right arm may read low"), c[0].text)
        XCTAssertTrue(c[0].text.contains("innominate"), c[0].text)
        XCTAssertTrue(c[0].text.contains("internal mammary"), c[0].text)
        r.carotid.right.vertebral = "partial"
        XCTAssertEqual(PatientStudies.cautions(r).isEmpty, !PatientStudies.stealFlows.contains("partial"))
    }

    func testEveryCautionHasASource() {
        let r = PatientDemo.cardiac
        let ids = Set(PatientStudies.cautions(r).map(\.id))
        XCTAssertEqual(ids, ["harvest", "harvest-arm", "carotid", "vertebral-left"], "the demo shows every caution")
        XCTAssertEqual(r.pft.gold, 2, "and a GOLD grade")
        for c in PatientStudies.cautions(r) { XCTAssertFalse(c.source.isEmpty, c.id) }
    }

    // MARK: The aorta

    func testAortaItemsAndSizes() {
        let cv = PatientCatalog.systems.first { $0.id == "cv" }
        XCTAssertEqual(cv?.problems.filter { PatientCatalog.aortaIDs.contains($0.id) }.map(\.id), PatientCatalog.aortaIDs, "in the Aorta group's order")
        XCTAssertEqual(PatientCatalog.aortaIDs.compactMap { PatientCatalog.problem($0)?.label }, [
            "Abdominal aortic aneurysm", "Ruptured abdominal aortic aneurysm", "Thoracic aortic aneurysm", "Ruptured thoracic aortic aneurysm",
            "Thoracoabdominal aortic aneurysm", "Ruptured thoracoabdominal aortic aneurysm", "Aortic dissection, type A", "Aortic dissection, type B",
            "Prior open aortic repair", "Prior EVAR", "Prior TEVAR",
        ])
        var r = PatientRecord()
        r.problems = ["aaa", "taa"]
        r.aortaSizes = ["aaa": 5.2]
        let cvLine = PatientSummary.historyLines(r).first { $0.label == "Cardiovascular" }
        XCTAssertEqual(cvLine?.text, "Abdominal aortic aneurysm, 5.2 cm; Thoracic aortic aneurysm")
        XCTAssertTrue(HandoffWriter.text(r).contains("Abdominal aortic aneurysm, 5.2 cm"))
        // A size kept for an item no longer ticked is not shown.
        r.problems = ["taa"]
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
        XCTAssertTrue(ids(note("TAA")).contains("problem:taa"))
        XCTAssertTrue(ids(note("ascending aortic aneurysm")).contains("problem:taa"))
        XCTAssertTrue(ids(note("aortic root aneurysm")).contains("problem:taa"))
        XCTAssertFalse(ids(note("dilated aortic root")).contains("problem:taa"), "dilation is below aneurysm size")
        XCTAssertFalse(ids(note("s/p L TAA")).contains("problem:taa"), "a total ankle arthroplasty")
        XCTAssertFalse(ids(note("TAA for ankle arthritis")).contains("problem:taa"))
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
            for f in note(s).findings { if case .aortaSize(let id, let cm) = f.change { return (id, cm) } }
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
        let change = PatientNoteChange.aortaSize("aaa", 5.2)
        let finding = PatientNoteFinding(id: "problem:aaa", section: PatientNote.Part.history, label: "", change: change)
        XCTAssertEqual(PatientNote.status(finding, in: r), .new)
        PatientNote.apply([change], to: &r)
        XCTAssertTrue(r.problems.contains("aaa"))
        XCTAssertEqual(r.aortaSizes["aaa"], 5.2)
        XCTAssertEqual(PatientNote.status(finding, in: r), .recorded)
        let bigger = PatientNoteFinding(id: "problem:aaa", section: PatientNote.Part.history, label: "", change: .aortaSize("aaa", 5.8))
        XCTAssertEqual(PatientNote.status(bigger, in: r), .replaces("5.2 cm"))
        r.problems.insert("aaa-ruptured")
        XCTAssertEqual(PatientNote.status(bigger, in: r), .recorded, "the rupture says more")
    }

    func testDissectionShorthand() {
        for s in ["type A dissection", "ATAAD", "Stanford type A aortic dissection", "aortic dissection, type A", "Stanford A"] {
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
        if case .aortaSize(_, let cm)? = q.findings.first(where: { $0.id == "problem:taa" })?.change { XCTAssertEqual(cm, 4.8) } else { XCTFail("TAA size") }
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

    func testPatternsCompile() {
        for rx in PatientNote.allPatterns { XCTAssertNotNil(rx.re, rx.pattern) }
        for rx in QuickAdd.allPatterns { XCTAssertNotNil(rx.re, rx.pattern) }
    }
}
