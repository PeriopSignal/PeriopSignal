import XCTest
import UIKit
@testable import PeriopSignal

/// 1.11, helper A (Ben's note 1, P1-1, Q20): labs typed into the fishbone. The catalog's new entries and their ranges,
/// the slot order Next walks, the hepatic and mineral cells of the fishbone, the slot hints (the app's ranges, not Ben's
/// where they differ), the Type & screen status, the tab card's line, the ABG slash figure, the briefs' fishbone in step,
/// and the demo patients, with a 1.10 record still decoding.
final class A111Tests: XCTestCase {

    // MARK: Catalog

    func testCatalogAdditionsWithTheirRanges() throws {
        let expected: [(key: String, label: String, low: Double, high: Double, unit: String)] = [
            ("ca", "Calcium", 8.6, 10.2, "mg/dL"), ("protein", "Total protein", 5.5, 9.0, "g/dL"),
            ("mg", "Magnesium", 1.6, 2.6, "mg/dL"), ("phos", "Phosphorus", 2.5, 4.5, "mg/dL"),
        ]
        for e in expected {
            let t = try XCTUnwrap(PatientLabs.test(e.key), e.key)
            XCTAssertEqual(t.label, e.label)
            XCTAssertEqual(t.unit, e.unit)
            XCTAssertEqual(t.range, LabRange(e.low, e.high), e.key)
            XCTAssertEqual(t.group, .main, "on the page's figures, so a main lab")
            XCTAssertEqual(PatientLabs.flag(e.key, e.low - 0.1, sex: nil), .low, e.key)
            XCTAssertEqual(PatientLabs.flag(e.key, e.high + 0.1, sex: nil), .high, e.key)
            XCTAssertEqual(PatientLabs.flag(e.key, (e.low + e.high) / 2, sex: nil), .normal, e.key)
        }
        XCTAssertEqual(PatientLabs.test("phos")?.short, "PO₄")
        XCTAssertEqual(PatientLabs.tests(.main).last?.key, "lactate", "lactate still last")
        XCTAssertEqual(PatientLabs.tests(.liver).map(\.key), ["ast", "alt", "alp"], "the hepatic enzymes keep their group")
        // The preoperative aPTT is the intraoperative entry, flagged against ABIM 25–35 s; the PT keeps no flag.
        XCTAssertEqual(PatientLabs.test("ptt")?.range, IntraopLabs.ptt.range)
        XCTAssertEqual(PatientLabs.flag("ptt", 40, sex: nil), .high)
        XCTAssertEqual(PatientLabs.flag("pt", 20, sex: nil), .normal, "the PT is read against the report's own range")
        XCTAssertEqual(PatientLabs.summary(["ca": 8.3, "mg": 1.7], sex: nil).line, "Ca 8.3 L · Mg 1.7")
    }

    /// Q20 (Ben, Nov 9): the app's sourced ranges stay; his drawn ranges are hints only where they agree.
    func testRangesStayTheCatalogsNotTheDrawing() {
        XCTAssertEqual(PatientLabs.test("glucose")?.range, LabRange(70, 180), "not the drawn 70–115")
        XCTAssertEqual(PatientLabs.test("bun")?.range, LabRange(8, 20), "not the drawn 7–18")
        XCTAssertEqual(PatientLabs.test("cl")?.range, LabRange(98, 106), "not the drawn 95–105")
        XCTAssertEqual(PatientLabs.test("na")?.range, LabRange(136, 145))
        XCTAssertEqual(PatientLabs.test("hco3")?.range, LabRange(23, 28))
        XCTAssertEqual(PatientLabs.test("ca")?.range, LabRange(8.6, 10.2), "not the drawn 8.4–10.2")
        // The hint inside an empty slot is the catalog's range for the sex: what the value is flagged against.
        XCTAssertEqual(PatientLabs.slotHint("na", sex: nil), "136–145")
        XCTAssertEqual(PatientLabs.slotHint("glucose", sex: nil), "70–180")
        XCTAssertEqual(PatientLabs.slotHint("hb", sex: .female), "12–16")
        XCTAssertEqual(PatientLabs.slotHint("hb", sex: .male), "14–18")
        XCTAssertEqual(PatientLabs.slotHint("hb", sex: nil), "12–18")
        XCTAssertEqual(PatientLabs.slotHint("k", sex: nil), "3.5–5", "where the drawing agrees it is the same hint")
        XCTAssertEqual(PatientLabs.slotHint("tbili", sex: nil), "1 or less")
        XCTAssertNil(PatientLabs.slotHint("pt", sex: nil), "no range, no hint")
        XCTAssertNil(PatientLabs.slotHint("nonsense", sex: nil))
    }

    // MARK: The slots

    func testSlotOrderWalksTheFiguresAndCoversEveryMainLab() {
        let order = PatientLabs.slotOrder
        XCTAssertEqual(Array(order.prefix(7)), ["na", "k", "cl", "hco3", "bun", "cr", "glucose"], "the BMP column by column, glucose at the point")
        XCTAssertEqual(Array(order.dropFirst(7).prefix(4)), ["wbc", "hb", "hct", "plt"])
        XCTAssertEqual(Array(order.dropFirst(11).prefix(4)), ["pt", "ptt", "inr", "fibrinogen"], "PT over PTT, INR at the point, fibrinogen beside it")
        XCTAssertEqual(Array(order.dropFirst(15).prefix(7)), PatientLabs.hepaticOrder)
        XCTAssertEqual(PatientLabs.hepaticOrder, ["ca", "protein", "albumin", "ast", "alt", "alp", "tbili"], "down the left, down the right, bilirubin at the point")
        XCTAssertEqual(Array(order.dropFirst(22).prefix(2)), ["mg", "phos"])
        XCTAssertEqual(Array(order.suffix(3)), ["gfr", "a1c", "lactate"], "the main labs without a figure, last")
        XCTAssertEqual(Set(order).count, order.count, "every slot once")
        for k in order { XCTAssertNotNil(PatientLabs.test(k), k + " is in the catalog") }
        let main = Set(PatientLabs.tests(.main).map(\.key) + PatientLabs.tests(.liver).map(\.key))
        XCTAssertEqual(Set(order), main, "every main lab and hepatic enzyme has a slot, and nothing else")
        XCTAssertTrue(PatientLabs.figureKeys.contains("ca"))
        XCTAssertFalse(PatientLabs.figureKeys.contains("bnp"), "the cardiac group stays behind its link")
        // The 1.9 table's order is untouched (the List toggle shows it).
        XCTAssertEqual(Array(PatientLabs.entryOrder(.main).map(\.key).prefix(4)), ["wbc", "hb", "hct", "plt"])
    }

    func testFishboneHepaticAndMineralCells() {
        let s = PatientLabs.summary(["ca": 8.3, "ast": 62, "alt": 30, "alp": 134, "protein": 6.4, "albumin": 3.1, "tbili": 1.6, "mg": 1.7, "phos": 4.8], sex: .male)
        let f = s.fishbone
        XCTAssertTrue(f.hasHepatic)
        XCTAssertTrue(f.hasMinerals)
        XCTAssertFalse(f.hasBMP)
        XCTAssertFalse(f.isEmpty)
        XCTAssertEqual(f.ca?.flag, .low)
        XCTAssertEqual(f.ast?.flag, .high)
        XCTAssertEqual(f.alt?.flag, .normal)
        XCTAssertEqual(f.alp?.flag, .high)
        XCTAssertEqual(f.protein?.text, "6.4")
        XCTAssertEqual(f.albumin?.flag, .low)
        XCTAssertEqual(f.tbili?.flag, .high)
        XCTAssertEqual(f.mg?.text, "1.7")
        XCTAssertEqual(f.phos?.flag, .high)
        XCTAssertEqual(f.hepatic.compactMap { $0?.key }, ["ca", "protein", "albumin", "ast", "alt", "alp", "tbili"])
        XCTAssertEqual(f.minerals.compactMap { $0?.key }, ["mg", "phos"])
        XCTAssertFalse(PatientLabs.summary(["mg": 2.0], sex: nil).fishbone.isEmpty, "a mineral alone is on a figure")
        XCTAssertTrue(PatientLabs.summary([:], sex: nil).fishbone.isEmpty)
        XCTAssertTrue(PatientLabs.summary(["bnp": 40], sex: nil).fishbone.isEmpty, "the cardiac labs are not on a figure")
    }

    @MainActor func testMainFieldOrderFollowsTheSlotsOrTheList() {
        let key = PreopLabsFigures.listKey
        let before = UserDefaults.standard.object(forKey: key)
        defer { if let before { UserDefaults.standard.set(before, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        guard !UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory else { return }
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(PreopLabsFigures.listMode())
        XCTAssertEqual(PreopLabsFigures.mainFieldOrder(), PatientLabs.slotOrder, "Next walks the figures")
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(PreopLabsFigures.listMode())
        XCTAssertEqual(PreopLabsFigures.mainFieldOrder(), PatientLabs.entryOrder(.main).map(\.key) + ["ast", "alt", "alp"], "the table, then the hepatic enzymes under it")
        XCTAssertEqual(Set(PreopLabsFigures.mainFieldOrder()), Set(PatientLabs.slotOrder), "the same fields either way")
    }

    @MainActor func testFocusRequestIsTakenOnce() {
        LabSlotFocusRequest.pending = nil
        XCTAssertNil(LabSlotFocusRequest.take())
        LabSlotFocusRequest.pending = "main.k"
        XCTAssertEqual(LabSlotFocusRequest.take(), "main.k")
        XCTAssertNil(LabSlotFocusRequest.take(), "taken once")
    }

    func testSlotAccessibilityText() throws {
        let na = try XCTUnwrap(PatientLabs.test("na"))
        XCTAssertEqual(LabSlot.accessibilityText(na, value: 138, sex: nil), "Sodium, 138, range 136 to 145 mmol/L")
        XCTAssertEqual(LabSlot.accessibilityText(na, value: 131, sex: nil, flag: .low), "Sodium, 131, low, range 136 to 145 mmol/L")
        XCTAssertEqual(LabSlot.accessibilityText(na, value: nil, sex: nil), "Sodium, empty, range 136 to 145 mmol/L")
        let hb = try XCTUnwrap(PatientLabs.test("hb"))
        XCTAssertEqual(LabSlot.accessibilityText(hb, value: nil, sex: .female), "Hemoglobin, empty, range 12 to 16 g/dL")
        let hct = try XCTUnwrap(PatientLabs.test("hct"))
        let est = try XCTUnwrap(PatientLabs.estimate(["hb": 12.8]))
        XCTAssertEqual(LabSlot.accessibilityText(hct, value: nil, sex: .male, estimate: est), "Hematocrit, estimated 38, range 42 to 50 %")
        let pt = try XCTUnwrap(PatientLabs.test("pt"))
        XCTAssertEqual(LabSlot.accessibilityText(pt, value: 12.4, sex: nil), "Prothrombin time, 12.4", "no range to read")
        let inr = try XCTUnwrap(PatientLabs.test("inr"))
        XCTAssertEqual(LabSlot.accessibilityText(inr, value: 1, sex: nil), "INR, 1.0, range 0.8 to 1.1", "no unit")
    }

    // MARK: Type & screen status

    func testTypeScreenStatus() {
        var ts = PatientTypeScreen()
        XCTAssertNil(ts.effectiveStatus)
        XCTAssertNil(ts.head)
        XCTAssertTrue(ts.isEmpty)
        ts.setStatus(.sent)
        XCTAssertEqual(ts.effectiveStatus, .sent)
        XCTAssertEqual(ts.head, "T&S sent, result pending")
        XCTAssertEqual(ts.parts, ["T&S sent, result pending"])
        XCTAssertFalse(ts.isEmpty)
        ts.setStatus(.notSent)
        XCTAssertEqual(ts.head, "T&S not sent")
        ts.setStatus(.resulted)
        XCTAssertEqual(ts.effectiveStatus, .resulted)
        XCTAssertNil(ts.head, "resulted without a result yet says nothing on the line")
        // A result recorded reads as resulted whatever was tapped, and the same chip again (nil) never hides it.
        ts.type = "A-"; ts.screen = .negative; ts.crossmatched = 2
        ts.setStatus(nil)
        XCTAssertEqual(ts.effectiveStatus, .resulted)
        XCTAssertEqual(ts.head, "T&S A−, screen neg")
        // Not sent or Sent on a recorded result: the user says there is none; the type and screen go, the units typed stay.
        ts.antibody = "anti-K"
        ts.setStatus(.notSent)
        XCTAssertNil(ts.type)
        XCTAssertNil(ts.screen)
        XCTAssertEqual(ts.antibody, "")
        XCTAssertEqual(ts.crossmatched, 2)
        XCTAssertEqual(ts.parts, ["T&S not sent", "2 u crossmatched"])
        XCTAssertEqual(TypeScreenStatus.allCases.map(\.label), ["Not sent", "Sent", "Resulted"])

        var r = PatientRecord()
        r.labs = ["hb": 15, "hct": 45]
        r.typeScreen = PatientTypeScreen(status: .sent)
        XCTAssertEqual(PatientSummary.labsLine(r)?.text, "Hb 15 · Hct 45 · T&S sent, result pending")
        XCTAssertEqual(PreopLabsCard.otherLine(r)?.text, "T&S sent, result pending")
        // A note's reading keeps a status the record holds, and carries one it says.
        let fromNote = PatientTypeScreen(type: "O+")
        XCTAssertEqual(fromNote.merged(over: PatientTypeScreen(status: .sent)).status, .sent)
        XCTAssertEqual(fromNote.merged(over: PatientTypeScreen(status: .sent)).effectiveStatus, .resulted)
        XCTAssertEqual(PatientTypeScreen(status: .notSent).merged(over: PatientTypeScreen(status: .sent)).status, .notSent)
    }

    func testTypeScreenStatusDecodesAndFallsBack() throws {
        var r = PatientRecord()
        r.typeScreen = PatientTypeScreen(status: .sent)
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.typeScreen.status, .sent)
        XCTAssertEqual(back, r)
        // A 1.10 record: no status, and its recorded result still reads as resulted.
        let old = try JSONDecoder().decode(PatientTypeScreen.self, from: Data(#"{"type":"A-","screen":"neg","crossmatched":2}"#.utf8))
        XCTAssertNil(old.status)
        XCTAssertEqual(old.effectiveStatus, .resulted)
        XCTAssertEqual(old.head, "T&S A−, screen neg")
        let junk = try JSONDecoder().decode(PatientTypeScreen.self, from: Data(#"{"status":"mailed"}"#.utf8))
        XCTAssertNil(junk.status, "an unknown status reads as none")
    }

    // MARK: A 1.10 record

    /// A record as 1.10 saved it (labs by key, a liver section open, type and screen, no status, no 1.11 keys): it
    /// decodes, its values land in the figures, and the card's line and the brief read them.
    func testRecordSavedBy110StillReadsIntoTheFigures() throws {
        let json = #"""
        {"version":1,"sex":"male","labs":{"hb":12.8,"plt":210,"k":4.3,"cr":1.1,"glucose":162,"ast":62,"albumin":3.1,"tbili":1.6,"inr":1.4,"pt":14.2,"ptt":38},
         "labSections":["liver"],"typeScreen":{"type":"A-","screen":"neg","crossmatched":2},"labNotes":"TSH pending"}
        """#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.labs["ast"], 62)
        XCTAssertEqual(r.labs.count, 11, "every saved key kept")
        XCTAssertTrue(r.labSections.contains("liver"))
        XCTAssertNil(r.typeScreen.status)
        let s = PatientLabs.summary(r)
        XCTAssertTrue(s.fishbone.hasHepatic)
        XCTAssertEqual(s.fishbone.ast?.flag, .high)
        XCTAssertEqual(s.fishbone.hb?.flag, .low)
        XCTAssertEqual(s.fishbone.ptt?.flag, .high)
        XCTAssertEqual(s.fishbone.estimate?.key, "hct")
        XCTAssertNil(s.fishbone.ca, "a slot with nothing saved stays empty")
        XCTAssertFalse(PreopLabsCard.isEmpty(r))
        let line = try XCTUnwrap(PreopLabsCard.otherLine(r))
        XCTAssertEqual(line.text, "Alb 3.1 L · T bili 1.6 H · AST 62 H · T&S A−, screen neg · 2 u crossmatched · TSH pending")
        XCTAssertEqual(line.marks, ["Alb 3.1 L", "T bili 1.6 H", "AST 62 H"])
        XCTAssertFalse(line.text.contains("Hb"), "the figure's own values are not repeated on the line")
    }

    // MARK: The tab card

    func testCardLineAndEmptyState() {
        XCTAssertTrue(PreopLabsCard.isEmpty(PatientRecord()))
        XCTAssertNil(PreopLabsCard.otherLine(PatientRecord()))
        var r = PatientRecord()
        r.labs = ["na": 139, "k": 4.8, "hb": 15, "inr": 1, "pt": 12.4]
        XCTAssertFalse(PreopLabsCard.isEmpty(r))
        XCTAssertNil(PreopLabsCard.otherLine(r), "everything is on the three figures")
        r.labs["mg"] = 1.4
        r.labs["gfr"] = 55
        XCTAssertEqual(PreopLabsCard.otherLine(r)?.text, "GFR 55 L · Mg 1.4 L")
        XCTAssertEqual(PreopLabsCard.otherLine(r)?.marks, ["GFR 55 L", "Mg 1.4 L"])
        var notes = PatientRecord()
        notes.labNotes = "lipids pending"
        XCTAssertFalse(PreopLabsCard.isEmpty(notes), "a note alone is something to show")
        var sent = PatientRecord()
        sent.typeScreen = PatientTypeScreen(status: .sent)
        XCTAssertFalse(PreopLabsCard.isEmpty(sent))
        XCTAssertEqual(PreopLabsCard.otherLine(PatientDemo.labs111)?.text,
                       "GFR 72 · HbA1c 6.1 H · Alb 3.1 L · T bili 1.6 H · Ca 8.3 L · Prot 6.4 · Mg 1.7 · PO₄ 3.2 · AST 62 H · ALT 48 H · Alk phos 134 H · Lactate 1.4 · T&S A−, screen neg · 2 u crossmatched · Staph screen neg · MRSA neg · COVID neg · C. diff pending")
    }

    // MARK: The intraoperative gas

    @MainActor func testABGSlashFigureKeepsTheGasOrder() {
        XCTAssertEqual(IntraopLabs.abgSlash, ["ph", "paco2", "pao2", "hco3a"])
        XCTAssertEqual(IntraopLabs.abgSlash + IntraopLabs.abgRest, IntraopLabs.abg, "the slots and the rows together are the gas, in its order")
        XCTAssertEqual(IntraopLabs.abgRest.first, "be")
        for k in IntraopLabs.abgSlash { XCTAssertNotNil(IntraopLabs.tests([k]).first, k) }
        var r = PatientRecord()
        r.intraopLabs = [IntraopLabSet(time: Date())]
        XCTAssertEqual(Array(IntraopLabsEditor.fieldOrder(r).prefix(5)), ["iop.ph", "iop.paco2", "iop.pao2", "iop.hco3a", "iop.be"], "Next walks the slash figure, then the rows")
        XCTAssertEqual(PatientLabs.slotHint("ph", sex: nil), "7.38–7.44", "the gas slots hint the ABIM ranges too")
        XCTAssertEqual(PatientLabs.slotHint("pao2", sex: nil), "75 or more")
    }

    // MARK: The briefs

    func testBriefFishboneStaysInStep() throws {
        let r = PatientDemo.labs111
        let made = BriefLabs.make(r, withIntraop: false)
        XCTAssertEqual(BriefLabs.fishboneKeys, Set(BriefLabs.bmpKeys + BriefLabs.cbcKeys + BriefLabs.coagKeys), "the brief's figure keeps the BMP, CBC and coagulation groups")
        XCTAssertTrue(made.labs.hasBMP && made.labs.hasCBC && made.labs.hasCoags)
        XCTAssertEqual(made.labs.cells["pt"]?.text, "12.4")
        XCTAssertEqual(made.labs.cells["ptt"]?.text, "31")
        XCTAssertEqual(FishboneFigure.coagParts(made.labs), ["ptinr", "ptt"], "no fibrinogen entered, so no fibrinogen cell")
        XCTAssertTrue(made.side.contains { $0.key == "ast" && $0.abnormal }, "the hepatic values are listed beside the figure")
        XCTAssertTrue(made.side.contains { $0.key == "mg" })
        XCTAssertFalse(made.labs.cells.keys.contains("ast"), "and not drawn on it")
        let block = try XCTUnwrap(PatientBriefs.handoff(r).first { $0.key == "labs" })
        guard case .fishbone(let labs)? = block.figure else { return XCTFail("no fishbone") }
        XCTAssertEqual(labs.cells["na"]?.text, "139")
        XCTAssertTrue(block.text.contains("Ca 8.3 L"))
        XCTAssertTrue(block.marks.contains("Ca 8.3 L"))
    }

    // MARK: Demo patients

    @MainActor func testDemoPatientsForTheShots() {
        let r = PatientDemo.labs111
        for k in PatientLabs.slotOrder where k != "hct" && k != "fibrinogen" {
            XCTAssertNotNil(r.labs[k], k + " is filled")
        }
        XCTAssertNil(r.labs["hct"], "left out, so the slot shows the estimate")
        XCTAssertNotNil(r.labsDrawn)
        XCTAssertEqual(r.typeScreen.effectiveStatus, .resulted)
        XCTAssertEqual(PatientDemo.labs111Sent.typeScreen.head, "T&S sent, result pending")
        XCTAssertNil(PatientDemo.labs111Sent.typeScreen.type)
        XCTAssertNotNil(PatientStore.debugSeed("demo-labs111"))
        XCTAssertNotNil(PatientStore.debugSeed("demo-labs111-sent"))
        let back = try? JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r, "the demo round-trips")
    }
}
