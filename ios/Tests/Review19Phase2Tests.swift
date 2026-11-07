import XCTest
import UIKit
@testable import PeriopSignal

/// 1.9 review, phase 2 (the Preprocedure tab, the briefs and Status & Plan): one test per confirmed finding.
final class Review19Phase2Tests: XCTestCase {
    private func block(_ blocks: [SummaryBlock], _ key: String, file: StaticString = #filePath, line: UInt = #line) throws -> SummaryBlock {
        try XCTUnwrap(blocks.first { $0.key == key }, "no \(key) block in \(blocks.map(\.key))", file: file, line: line)
    }

    private func has(_ blocks: [SummaryBlock], _ key: String) -> Bool { blocks.contains { $0.key == key } }

    private func devices(_ texts: [String], intraop: Bool) -> [PatientDevice] {
        texts.flatMap { PatientDevices.parse($0)?.devices(placedIntraop: intraop) ?? [] }
    }

    private func fishbone(_ b: SummaryBlock, file: StaticString = #filePath, line: UInt = #line) throws -> BriefLabs {
        guard case .fishbone(let labs)? = b.figure else {
            XCTFail("no fishbone", file: file, line: line)
            return BriefLabs()
        }
        return labs
    }

    // MARK: ASA class with nothing else in the PMH

    func testASAClassIsKeptWhenThePMHHasNothingElse() throws {
        var r = PatientRecord()
        r.ageYears = 50
        r.nkda = true
        r.asaClass = 2
        for blocks in [PatientBriefs.preop(r), PatientBriefs.handoff(r)] {
            let pmh = try block(blocks, "pmh")
            XCTAssertTrue(((pmh.label ?? "") + " " + pmh.text).contains("ASA II"), "\(pmh.label ?? ""): \(pmh.text)")
            XCTAssertTrue(PatientBriefs.plainText(blocks).contains("ASA II"), "the copied text carries the class")
        }
        r.asaClass = 3; r.asaE = true
        XCTAssertTrue(PatientBriefs.plainText(PatientBriefs.handoff(r)).contains("ASA IIIE"), "and its E")
        r.asaClass = nil; r.asaE = nil
        XCTAssertFalse(has(PatientBriefs.preop(r), "pmh"), "no class, nothing to say: no block")
    }

    // MARK: Mechanical support in the preprocedure summary

    func testPreprocedureWorkupListsOnlyTheSupportOnArrivalAndOnlyOnce() throws {
        var r = PatientRecord()
        r.devices = devices(["18g R forearm", "L fem IABP 7.5 Fr 1:1"], intraop: false)
        let pre = PatientBriefs.preop(r)
        let workup = try block(pre, "workup")
        XCTAssertTrue(workup.text.contains("Mechanical support: "), workup.text)
        XCTAssertTrue(workup.text.contains("IABP"), workup.text)
        let lines = try block(pre, "lines")
        XCTAssertFalse(lines.text.contains("IABP"), "listed in the workup, not again in Lines & devices: \(lines.text)")
        XCTAssertEqual(lines.figure, .diagram(arrivalOnly: true), "still drawn")

        // Placed in the room: not preprocedure workup.
        var placed = PatientRecord()
        placed.devices = devices(["18g R forearm"], intraop: false) + devices(["VA ECMO 25F RFV drainage / 17F LFA return flow 4.2 sweep 3"], intraop: true)
        XCTAssertFalse(placed.mechanicalSupport.isEmpty)
        let w = PatientBriefs.preop(placed).first { $0.key == "workup" }?.text ?? ""
        XCTAssertFalse(w.contains("Mechanical support"), w)
        XCTAssertTrue(try block(PatientBriefs.handoff(placed), "lines").text.contains("ECMO"), "the handoff lists it, with (Intra)")
    }

    // MARK: Labs: which intraoperative value is from which time

    func testCaptionNamesTheValuesOfEachIntraoperativeTime() throws {
        var r = PatientRecord()
        r.labs = ["na": 138, "inr": 1.0]
        r.intraopLabs = [IntraopLabSet(time: PatientDemo.today(9, 15), values: ["inr": 1.9]),
                         IntraopLabSet(time: PatientDemo.today(10, 40), values: ["k": 4.9])]
        let labs = try fishbone(try block(PatientBriefs.handoff(r), "labs"))
        XCTAssertEqual(labs.caption, "* Intraop 10:40 (K) / 09:15 (INR); other values preop")
        // One set: its time alone says it.
        var one = PatientRecord()
        one.labs = ["na": 138]
        one.intraopLabs = [IntraopLabSet(time: PatientDemo.today(10, 40), values: ["k": 4.9, "hco3a": 21])]
        let o = try fishbone(try block(PatientBriefs.handoff(one), "labs"))
        XCTAssertEqual(o.caption, "* Intraop 10:40; other values preop")
        // The copied caption has plain digits.
        var two = r
        two.intraopLabs.append(IntraopLabSet(time: PatientDemo.today(11, 5), values: ["hco3a": 20]))
        let text = PatientBriefs.plainText(PatientBriefs.handoff(two))
        XCTAssertTrue(text.contains("11:05 (HCO3)"), text)
    }

    // MARK: Estimated Hct from an intraoperative Hb

    func testAnEstimateFromAnIntraoperativeValueIsMarkedAsIntraoperative() throws {
        var r = PatientRecord()
        r.labs = ["hb": 13.0, "na": 138]
        r.intraopLabs = [IntraopLabSet(time: PatientDemo.today(10, 40), values: ["hb": 7.3])]
        let labs = try fishbone(try block(PatientBriefs.handoff(r), "labs"))
        let hct = try XCTUnwrap(labs.cells["hct"])
        XCTAssertTrue(hct.estimated)
        XCTAssertEqual(hct.text, "22")
        XCTAssertTrue(hct.intraop, "worked out from the 10:40 Hb")
        XCTAssertEqual(labs.caption, "* Intraop 10:40; other values preop")
        XCTAssertTrue(PatientBriefs.plainText(PatientBriefs.handoff(r)).contains("Hct ~22 (est.)*"))
        // Before the case it is the preoperative Hb's estimate.
        let pre = try fishbone(try block(PatientBriefs.preop(r), "labs"))
        XCTAssertEqual(pre.cells["hct"]?.intraop, false)
        XCTAssertEqual(pre.cells["hct"]?.text, "39")
        // With two times the estimate is named under its Hb's.
        r.intraopLabs.append(IntraopLabSet(time: PatientDemo.today(11, 30), values: ["k": 4.2]))
        let two = try fishbone(try block(PatientBriefs.handoff(r), "labs"))
        XCTAssertEqual(two.caption, "* Intraop 11:30 (K) / 10:40 (Hb, Hct est.); other values preop")
    }

    // MARK: Infusions running before the case and in it

    func testAPreCaseDripIsNotRepeatedWhenTheCaseHasTheSameOne() throws {
        var r = PatientRecord()
        r.homeInfusions = [PatientInfusion(drug: "Norepinephrine", rate: "0.05 mcg/kg/min")]
        r.infusions = [PatientInfusion(drug: "Norepinephrine", rate: "0.05 mcg/kg/min")]
        let t = try block(PatientBriefs.handoff(r), "infusions")
        XCTAssertEqual(t.lines, ["Infusions: Norepinephrine at 0.05 mcg/kg/min"])
        // Another rate (or another drug) before the case is still told.
        r.homeInfusions = [PatientInfusion(drug: "Norepinephrine", rate: "0.1 mcg/kg/min")]
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "infusions").lines.count, 2)
    }

    // MARK: Medication flags beside the infusions

    func testAnActionFlagStaysRedWithInfusionsBesideIt() throws {
        let label = try XCTUnwrap(PatientCatalog.medFlags.first { $0.id == "anticoagulant" }?.label)
        var r = PatientRecord()
        r.medFlags = ["anticoagulant"]
        let alone = try block(PatientBriefs.preop(r), "meds")
        XCTAssertTrue(alone.marks.contains(label))
        r.homeInfusions = [PatientInfusion(drug: "Heparin", rate: "1000 units/h")]
        let meds = try block(PatientBriefs.preop(r), "meds")
        XCTAssertTrue(meds.text.contains("Home: " + label), meds.text)
        XCTAssertTrue(meds.marks.contains(label), "the flag is red with the infusions too: \(meds.marks)")
        XCTAssertTrue(meds.alert)
    }

    // MARK: Copy and Share close with the footer

    @MainActor func testSharedAndCopiedTextCarryThePreparedTimeAndTheReminder() throws {
        let r = PatientDemo.briefs
        let blocks = PatientBriefs.handoff(r)
        let now = try XCTUnwrap(PatientDemo.today(14, 5))
        let shared = PatientBriefs.sharedText(blocks, now: now)
        XCTAssertTrue(shared.hasPrefix(PatientBriefs.plainText(blocks) + "\n\n"))
        XCTAssertTrue(shared.hasSuffix("Check against the chart."), shared)
        XCTAssertTrue(shared.contains("Prepared with Periop Signal, "))
        XCTAssertTrue(shared.contains("14:05"), "when it was prepared")
        let item = try XCTUnwrap(HandoffShare.briefItems(blocks, record: r, figure: nil, now: now).first as? HandoffShare.TextItem)
        XCTAssertEqual(item.plain, shared)
        XCTAssertEqual(item.rich.string, shared, "the same words in the rich text")
        XCTAssertFalse(PatientBriefs.plainText(blocks).contains("Prepared with"), "the brief on screen has no footer")
    }

    // MARK: The edited header

    func testAnEditedHeaderCarriesTheEditedMark() throws {
        var r = PatientRecord()
        r.ageYears = 76; r.sex = .male; r.weightKg = 80; r.heightCm = 180; r.procedure = "laparoscopic cholecystectomy"
        PatientBriefs.setEdit(&r, .handoff, key: "header", text: "76 yo M (80 kg, 180 cm) had Lap chole")
        r.weightKg = 60
        let header = try block(PatientBriefs.handoff(r), "header")
        XCTAssertTrue(header.edited)
        XCTAssertEqual(header.text, "76 yo M (80 kg, 180 cm) had Lap chole", "the edit sticks")
        XCTAssertEqual(BriefBlockView.editedMark(header), "  edited", "the header shows the mark too")
        XCTAssertEqual(BriefBlockView.editedMark(try block(PatientBriefs.preop(r), "header")), "")
    }

    // MARK: Bold labels of blocks of several lines in the shared text

    func testTheLabelOfABlockOfSeveralLinesIsBoldInTheRichText() throws {
        let blocks = PatientBriefs.handoff(PatientDemo.briefs)
        let plain = PatientBriefs.plainText(blocks)
        let rich = HandoffShare.richText(blocks)
        XCTAssertEqual(rich.string, plain)
        func bold(_ needle: String) throws -> Bool {
            let r = try XCTUnwrap(plain.range(of: needle), needle)
            let a = rich.attributes(at: NSRange(r, in: plain).location, effectiveRange: nil)
            let font = try XCTUnwrap(a[.font] as? UIFont)
            return font.fontDescriptor.symbolicTraits.contains(.traitBold)
        }
        for label in ["Concerns/Considerations:", "Current infusions & intraop medications:"] {
            XCTAssertTrue(plain.components(separatedBy: "\n").contains(label), "on its own line: \(label)")
            XCTAssertTrue(try bold(label), label)
        }
        XCTAssertTrue(try bold("Allergies:"))
        XCTAssertFalse(try bold("Penicillin"))
    }

    // MARK: Coagulation dividers

    func testCoagulationDividersGoOnlyBetweenTwoParts() {
        var labs = BriefLabs()
        labs.cells["inr"] = BriefLabCell(key: "inr", label: "INR", text: "1.2")
        XCTAssertEqual(FishboneFigure.coagParts(labs), ["ptinr"], "PT/INR alone: no divider")
        labs.cells["fibrinogen"] = BriefLabCell(key: "fibrinogen", label: "Fib", text: "250")
        XCTAssertEqual(FishboneFigure.coagParts(labs), ["ptinr", "fibrinogen"], "no PTT: one divider, not two")
        labs.cells["ptt"] = BriefLabCell(key: "ptt", label: "PTT", text: "30")
        XCTAssertEqual(FishboneFigure.coagParts(labs), ["ptinr", "ptt", "fibrinogen"])
        var fibOnly = BriefLabs()
        fibOnly.cells["fibrinogen"] = BriefLabCell(key: "fibrinogen", label: "Fib", text: "250")
        XCTAssertEqual(FishboneFigure.coagParts(fibOnly), ["fibrinogen"])
    }

    // MARK: Carotid and vertebral cautions on the tab

    func testCarotidCautionsShowOnTheTabsWorkupRow() throws {
        let r = PatientDemo.cardiac
        let expected = PatientStudies.cautions(r).filter { !$0.id.hasPrefix("harvest") }.map(\.text)
        XCTAssertFalse(expected.isEmpty, "the cardiac demo has a carotid or vertebral caution")
        let carotid = try XCTUnwrap(PatientPreop.workup(r).first { $0.id == "carotid" })
        XCTAssertTrue(carotid.alert)
        let caution = try XCTUnwrap(carotid.caution)
        for t in expected { XCTAssertTrue(caution.contains(t), t) }
        XCTAssertNil(PatientPreop.workup(PatientRecord()).first { $0.id == "carotid" }?.caution)
    }

    // MARK: Previous cardiac surgery

    func testPreviousCardiacSurgeryListsOnlyCardiacOperations() {
        var r = PatientRecord()
        r.surgeries = [PatientSurgery(name: "CABG ×3", intrathoracic: true), PatientSurgery(name: "Appendectomy")]
        r.intrathoracic = [PatientSurgery(name: "Right VATS wedge", intrathoracic: true)]
        XCTAssertEqual(PatientPreop.previousCardiacSurgery(r).map(\.name), ["CABG ×3"])
        var thoracicOnly = PatientRecord()
        thoracicOnly.intrathoracic = [PatientSurgery(name: "Left upper lobectomy", intrathoracic: true)]
        XCTAssertTrue(PatientPreop.previousCardiacSurgery(thoracicOnly).isEmpty)
        // The CV page's own entry counts, whatever its words.
        var own = PatientRecord()
        PatientHistoryDetails.setCardiacSurgery("Redo sternotomy", &own)
        XCTAssertEqual(PatientPreop.previousCardiacSurgery(own).count, 1)
    }

    // MARK: Jump ids

    func testSectionsAndBoxesHaveDifferentScrollIDs() {
        let boxes = ["demographics", "allergies", "problems", "chips", "asa", "cardio", "airway", "labs", "devices", "homemeds", "infusions", "flagged"]
        for s in PreopSection.allCases {
            for b in boxes { XCTAssertNotEqual(PatientJumpID(section: s), PatientJumpID(anchor: b), "\(s.rawValue) and the \(b) box") }
        }
    }

    // MARK: Other conditions

    func testOtherConditionsFieldStaysOpenOnceShown() {
        XCTAssertTrue(PreopProblemsBox.showsOther(open: false, text: "Hereditary angioedema"))
        XCTAssertTrue(PreopProblemsBox.showsOther(open: true, text: ""), "opened, kept while it is emptied to retype")
        XCTAssertFalse(PreopProblemsBox.showsOther(open: false, text: ""))
    }

    // MARK: Code status link

    func testTheCodeStatusPageIsReachableForEveryStatus() {
        var r = PatientRecord()
        XCTAssertEqual(PatientPreop.codeStatusLink(r).text, "Plan details & POLST")
        r.codeStatus = .full
        r.polst = true
        XCTAssertEqual(PatientPreop.codeStatusLink(r).text, "POLST on file")
        XCTAssertFalse(PatientPreop.codeStatusLink(r).alert)
        r.codeStatus = .dnrDni
        XCTAssertEqual(PatientPreop.codeStatusLink(r).text, "Perioperative plan not yet discussed")
        XCTAssertTrue(PatientPreop.codeStatusLink(r).alert)
        r.codeStatusPlan = .modified
        XCTAssertTrue(PatientPreop.codeStatusLink(r).text.hasPrefix("Plan: "))
    }

    // MARK: Disposition: Other while typing

    func testOtherDispositionBoxKeepsWhatIsTyped() {
        // Open, the typed words stay in the box even when they spell a chip's label on the way.
        XCTAssertEqual(StatusPlanCard.selectedChip("ICU", otherOpen: true), "Other")
        XCTAssertEqual(StatusPlanCard.otherFieldText("ICU", otherOpen: true), "ICU")
        XCTAssertTrue(StatusPlanCard.showsOtherField("ICU", otherOpen: true))
        XCTAssertTrue(StatusPlanCard.showsOtherField(" ", otherOpen: true), "a leading space does not close it")
        XCTAssertEqual(StatusPlanCard.otherFieldText("Other", otherOpen: true), "")
        XCTAssertEqual(StatusPlanCard.otherFieldText("ICU step-down", otherOpen: true), "ICU step-down")
        // Closed, the saved value picks the chip, as before.
        XCTAssertEqual(StatusPlanCard.selectedChip("ICU", otherOpen: false), "ICU")
        XCTAssertFalse(StatusPlanCard.showsOtherField("ICU", otherOpen: false))
        XCTAssertTrue(StatusPlanCard.showsOtherField("Ward", otherOpen: false))
        XCTAssertEqual(StatusPlanCard.otherFieldText("Ward", otherOpen: false), "Ward")
    }

    // MARK: The archive keeps the handoff as handed over

    func testArchivedSummaryIsTheHandoffWithItsEdits() {
        var r = PatientDemo.record
        PatientBriefs.setEdit(&r, .handoff, key: "events", text: "Brief bradycardia at insufflation, resolved")
        let c = PatientCase(number: 1, record: r, room: "OR 12", roomPhone: "")
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 15, minute: 47))!
        let e = PatientArchiveWriter.entry(for: c, now: now)
        XCTAssertTrue(e.text.contains("Intraoperative events: Brief bradycardia at insufflation, resolved"), e.text)
        XCTAssertTrue(e.text.hasPrefix(PatientBriefs.handoff(r, now: now).first?.text ?? "-"), "the 1.9 handoff, header first")
        XCTAssertTrue(e.text.hasSuffix("Archived in Periop Signal, 10/31/26. Check against the chart."))
    }

    // MARK: Mechanical support alone keeps the lines diagram before the case

    func testPreprocedureSupportAloneKeepsTheLinesDiagram() throws {
        for text in ["HeartMate 3 LVAD 5400 rpm, PI 4.1, 4.8 L/min", "L fem IABP 7.5 Fr 1:1", "Impella CP"] {
            var r = PatientRecord()
            r.devices = devices([text], intraop: false)
            XCTAssertFalse(r.devices.isEmpty, text)
            let pre = PatientBriefs.preop(r)
            XCTAssertTrue(try block(pre, "workup").text.contains("Mechanical support: "), "\(text): told in the workup")
            let lines = try block(pre, "lines")
            XCTAssertEqual(lines.figure, .diagram(arrivalOnly: true), "\(text): the diagram is kept with nothing else entered")
            XCTAssertTrue(lines.lines.isEmpty, "\(text): not listed twice: \(lines.text)")
            if r.devices.allSatisfy({ $0.position != nil }) {
                XCTAssertFalse(PatientDiagramModel.items(r, phase: .preop).items.isEmpty, "\(text): drawn on it")
            }
            XCTAssertEqual(PatientBriefs.plainText(pre).components(separatedBy: "Mechanical support").count, 2,
                           "\(text): once in the copied text")
        }
        // Nothing on the diagram: still no block.
        var none = PatientRecord()
        none.ageYears = 50
        XCTAssertFalse(has(PatientBriefs.preop(none), "lines"))
    }

    // MARK: The archive list's one-liner

    func testArchiveOneLinerIsTheHeaderOfA19EntryAndTheLineAfterTheOldHeading() {
        var r = PatientDemo.record
        r.handoffEdits = [:]
        let c = PatientCase(number: 1, record: r, room: "OR 12", roomPhone: "")
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 15, minute: 47))!
        let e = PatientArchiveWriter.entry(for: c, now: now)
        XCTAssertTrue(e.oneLiner.hasPrefix("67 yo M (96 kg, 178 cm) had "), "1.9: the header: \(e.oneLiner)")
        XCTAssertEqual(e.oneLiner, e.text.components(separatedBy: "\n").first)

        // An entry saved before 1.9: the line after its heading.
        let old = PatientArchiveEntry(day: "2026-10-20", procedure: "Case",
                                      text: "ANESTHESIA HANDOFF\n67-year-old man · 96 kg · 178 cm\nLaparoscopic sigmoid colectomy · Elective")
        XCTAssertEqual(old.oneLiner, "67-year-old man · 96 kg · 178 cm")
        XCTAssertEqual(PatientArchiveEntry(day: "2026-10-20", procedure: "Case", text: "ANESTHESIA HANDOFF").oneLiner, "")

        // A 1.9 entry with no header starts with a block: no one-liner rather than the wrong line.
        for text in ["Allergies: NKDA\nPMH: HTN", "Code status: DNR\nCase: Urgent", "PMH (ASA II): HTN", "Concerns/Considerations:\n  Difficult airway"] {
            XCTAssertEqual(PatientArchiveEntry(day: "2026-10-20", procedure: "Case", text: text).oneLiner, "", text)
        }
        XCTAssertEqual(PatientArchiveEntry(day: "2026-10-20", procedure: "Case", text: "").oneLiner, "")
    }
}
