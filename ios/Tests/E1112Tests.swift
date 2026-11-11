import XCTest
@testable import PeriopSignal

/// 1.12 helper E1: a PA catheter or a SLIC put through an introducer line (note 1), the preprocedure chest X-ray (note 11)
/// and the valve calculator's calculated values (note 9).
final class E1112Tests: XCTestCase {

    // MARK: Note 1: "Through this line"

    private func line(_ detail: String, site: String = "ij-left", side: String? = "left", kind: DeviceKind = .cvc, size: String = "") -> PatientDevice {
        PatientDevice(kind: kind, site: site, side: side, size: size, detail: detail)
    }

    func testOnlyAnIntroducerOrMACLineTakesADeviceThroughIt() {
        XCTAssertTrue(line("MAC introducer").acceptsDevicesThrough)
        XCTAssertTrue(line("introducer").acceptsDevicesThrough)
        XCTAssertTrue(line("MAC").acceptsDevicesThrough)
        XCTAssertTrue(line("Cordis").acceptsDevicesThrough, "a Cordis is an introducer sheath")
        XCTAssertTrue(line("triple lumen, MAC introducer").acceptsDevicesThrough)
        XCTAssertFalse(line("triple lumen").acceptsDevicesThrough)
        XCTAssertFalse(line("SLIC").acceptsDevicesThrough)
        XCTAssertFalse(line("dialysis catheter").acceptsDevicesThrough)
        XCTAssertFalse(line("").acceptsDevicesThrough, "a central line with no type yet")
        XCTAssertFalse(line("MAC introducer", kind: .picc).acceptsDevicesThrough, "only a central venous catheter")
        XCTAssertFalse(line("Macintosh").acceptsDevicesThrough, "a word that only starts with mac")
    }

    func testAPACatheterThroughTheLineIsAPACAtTheLinesSiteAndSide() throws {
        let intro = line("MAC introducer")
        var devices = [intro]
        let added = PatientDevices.toggleThrough(.pac, line: intro, in: &devices, placedIntraop: false)
        XCTAssertTrue(added)
        XCTAssertEqual(devices.count, 2)
        let pac = try XCTUnwrap(devices.first { $0.kind == .pac })
        XCTAssertEqual(pac.site, "ij-left")
        XCTAssertEqual(pac.side, "left")
        XCTAssertEqual(pac.throughLine, intro.id)
        XCTAssertEqual(pac.label, "PAC via L IJ", "as 'PAC via L IJ' is today")
        XCTAssertEqual(PatientDevices.labels(devices), ["CVL L IJ (MAC introducer)", "PAC via L IJ"], "the lines list and the handoff")
    }

    func testASLICThroughTheLineIsTheExistingSLICDevice() throws {
        let intro = line("MAC introducer", site: "ij-right", side: "right")
        var devices = [intro]
        PatientDevices.toggleThrough(.slic, line: intro, in: &devices, placedIntraop: false)
        let slic = try XCTUnwrap(devices.first { $0.isSLIC })
        XCTAssertEqual(slic.kind, .cvc, "the SLIC that already exists as a central line")
        XCTAssertEqual(slic.detail, "SLIC")
        XCTAssertEqual(slic.label, "SLIC via R IJ")
        XCTAssertEqual(PatientDevices.labels(devices).last, "SLIC via R IJ")
        // Typed as before, a SLIC is still a central line with its type in brackets.
        XCTAssertEqual(try XCTUnwrap(PatientDevices.parse("RIJ SLIC")).device().label, "CVL R IJ (SLIC)")
        // A size and another detail stay on the line.
        var sized = slic
        sized.size = "9"
        sized.detail = "SLIC, ultrasound-guided"
        XCTAssertEqual(sized.label, "SLIC 9 Fr via R IJ (ultrasound-guided)")
    }

    func testASecondTapRemovesOnlyTheDeviceTheFirstTapAdded() throws {
        let intro = line("introducer", site: "ij-right", side: "right")
        // A PAC the user added by hand, at the same site, is not the chip's.
        let mine = PatientDevice(kind: .pac, site: "ij-right", side: "right", size: "7.5")
        var devices = [intro, mine]
        XCTAssertTrue(PatientDevices.toggleThrough(.pac, line: intro, in: &devices, placedIntraop: false))
        XCTAssertEqual(devices.filter { $0.kind == .pac }.count, 2)
        XCTAssertTrue(PatientDevices.toggleThrough(.slic, line: intro, in: &devices, placedIntraop: false))
        XCTAssertEqual(devices.count, 4)
        XCTAssertFalse(PatientDevices.toggleThrough(.pac, line: intro, in: &devices, placedIntraop: false), "a second tap removes it")
        XCTAssertEqual(devices.filter { $0.kind == .pac }.map(\.id), [mine.id], "the user's own PAC stays")
        XCTAssertTrue(devices.contains { $0.isThrough(.slic, of: intro.id) }, "the SLIC chip is independent of the PAC chip")
        XCTAssertFalse(PatientDevices.toggleThrough(.slic, line: intro, in: &devices, placedIntraop: false))
        XCTAssertEqual(devices.map(\.id), [intro.id, mine.id])
    }

    func testTheChipsAreIndependentPerLine() {
        let a = line("MAC introducer", site: "ij-right", side: "right")
        let b = line("Cordis")
        var devices = [a, b]
        PatientDevices.toggleThrough(.pac, line: a, in: &devices, placedIntraop: false)
        XCTAssertTrue(devices.contains { $0.isThrough(.pac, of: a.id) })
        XCTAssertFalse(devices.contains { $0.isThrough(.pac, of: b.id) }, "the other line's chip is still off")
        PatientDevices.toggleThrough(.pac, line: b, in: &devices, placedIntraop: false)
        XCTAssertEqual(PatientDevices.labels(devices).filter { $0.hasPrefix("PAC") }, ["PAC via R IJ", "PAC via L IJ"])
    }

    func testADeviceThroughALinePlacedInTheRoomIsPlacedInTheRoom() throws {
        var intro = line("MAC introducer")
        var devices = [intro]
        PatientDevices.toggleThrough(.pac, line: intro, in: &devices, placedIntraop: false)
        XCTAssertFalse(try XCTUnwrap(devices.last).placedIntraop, "added from the preoperative page to an arrival line")
        devices.removeLast()
        PatientDevices.toggleThrough(.pac, line: intro, in: &devices, placedIntraop: true)
        XCTAssertTrue(try XCTUnwrap(devices.last).placedIntraop, "added from the intraoperative page")
        intro.placedIntraop = true
        devices = [intro]
        PatientDevices.toggleThrough(.slic, line: intro, in: &devices, placedIntraop: false)
        XCTAssertTrue(try XCTUnwrap(devices.last).placedIntraop, "through a line that went in in the room")
    }

    func testTheDevicesThroughALineFollowItsSite() throws {
        var intro = line("MAC introducer", site: "ij-right", side: "right")
        var devices = [intro]
        PatientDevices.toggleThrough(.pac, line: intro, in: &devices, placedIntraop: false)
        let other = PatientDevice(kind: .pac, site: "ij-right", side: "right")
        devices.append(other)
        intro.site = "subclavian-left"; intro.side = "left"
        devices[0] = intro
        PatientDevices.followLine(intro.id, in: &devices)
        XCTAssertEqual(devices[1].label, "PAC via L subclavian", "never names the old site")
        XCTAssertEqual(devices[2].site, "ij-right", "a device not put through the line stays")
    }

    func testTheLinkSurvivesSavingAndAnOldDeviceOpens() throws {
        let intro = line("MAC introducer")
        var devices = [intro]
        PatientDevices.toggleThrough(.pac, line: intro, in: &devices, placedIntraop: false)
        let pac = try XCTUnwrap(devices.last)
        let again = try JSONDecoder().decode(PatientDevice.self, from: JSONEncoder().encode(pac))
        XCTAssertEqual(again, pac)
        XCTAssertEqual(again.throughLine, intro.id)
        // A device saved by 1.11 has no link.
        let old = try JSONDecoder().decode(PatientDevice.self, from: Data(#"{"kind":"pac","site":"ij-left","side":"left"}"#.utf8))
        XCTAssertNil(old.throughLine)
        XCTAssertEqual(old.label, "PAC via L IJ")
        // The link is not a field the details page asks for.
        XCTAssertFalse(DeviceKind.pac.settingKeys.contains(PatientDevice.throughKey))
        XCTAssertFalse(DeviceKind.cvc.settingKeys.contains(PatientDevice.throughKey))
    }

    func testTheDiagramLabelsThePACAndTheSLICAndTheLabelsDoNotOverlap() throws {
        let r = try XCTUnwrap(PatientDemo112Devices.record("demo-112-lines"))
        let items = PatientDiagramModel.items(r, phase: .all).items
        let labels = items.map(\.label)
        XCTAssertTrue(labels.contains("PAC"), "\(labels)")
        XCTAssertTrue(labels.contains("SLIC"), "\(labels)")
        XCTAssertTrue(labels.contains("CVL 9Fr"), "the introducer's own label stays: \(labels)")
        let drawn = items.filter { !$0.label.isEmpty }
        XCTAssertTrue(drawn.allSatisfy { $0.labelAt != nil }, "every label is placed in a column")
        for left in [true, false] {
            let ys = drawn.filter { $0.labelLeft == left }.compactMap { $0.labelAt?.y }.sorted()
            for (a, b) in zip(ys, ys.dropFirst()) {
                XCTAssertGreaterThanOrEqual(b - a, PatientDiagramModel.labelGap - 0.001, "labels in the \(left ? "left" : "right") column do not overlap: \(ys)")
            }
        }
        // The PAC is drawn as the catheter it is, to the pulmonary artery.
        let pac = try XCTUnwrap(items.first { $0.label == "PAC" })
        XCTAssertGreaterThan(pac.course.count, 2)
    }

    func testTheDemoLinesReadAsPACViaAndSLICVia() throws {
        let r = try XCTUnwrap(PatientDemo112Devices.record("demo-112-lines"))
        let labels = PatientDevices.labels(r.devices)
        XCTAssertTrue(labels.contains("PAC via R IJ"), "\(labels)")
        XCTAssertTrue(labels.contains("SLIC via L IJ"), "\(labels)")
        let bare = try XCTUnwrap(PatientDemo112Devices.record("demo-112-lines-bare"))
        XCTAssertFalse(PatientDevices.labels(bare.devices).contains { $0.hasPrefix("PAC") || $0.hasPrefix("SLIC") })
        XCTAssertEqual(bare.devices.filter(\.acceptsDevicesThrough).count, 2)
    }

    func testTheHandoffAndThePreprocedureSummaryListThemAsPACViaAndSLICVia() throws {
        let r = try XCTUnwrap(PatientDemo112Devices.record("demo-112-lines"))
        let handoff = try XCTUnwrap(PatientBriefs.handoff(r).first { $0.key == "lines" })
        let lines = handoff.text.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("PAC via R IJ (Pre)"), handoff.text)
        XCTAssertTrue(lines.contains("SLIC via L IJ (Pre)"), handoff.text)
        XCTAssertTrue(lines.contains("CVL 9 Fr R IJ (MAC introducer) (Pre)"), "the introducer itself stays listed: \(handoff.text)")
        let preop = try XCTUnwrap(PatientBriefs.preop(r).first { $0.key == "lines" })
        let preopLines = preop.text.components(separatedBy: "\n")
        XCTAssertTrue(preopLines.contains("PAC via R IJ"), preop.text)
        XCTAssertTrue(preopLines.contains("SLIC via L IJ"), preop.text)
    }

    // MARK: Note 11: Chest X-ray

    private func chole() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 61; r.sex = .female
        r.setProcedures(PlannedProcedure.parse("Laparoscopic cholecystectomy"))
        return r
    }

    func testAnOldRecordHasNoChestXray() throws {
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"procedure":"Lap chole","stressTest":{"kind":"exercise"}}"#.utf8))
        XCTAssertTrue(old.chestXray.isEmpty)
        XCTAssertNil(old.chestXray.text)
        XCTAssertNil(old.chestXray.summary)
        XCTAssertNil(PatientChestXray.line(old))
        XCTAssertNil(PatientPreop.workup(old).first { $0.id == "cxr" }?.summary)
    }

    func testNormalAndEffusionExcludeEachOther() {
        var x = PatientChestXray()
        x.choose(.effusion)
        x.side = .left; x.size = .moderate
        x.choose(.normal)
        XCTAssertEqual(x.result, .normal)
        XCTAssertNil(x.side, "a side means nothing without an effusion")
        XCTAssertNil(x.size)
        XCTAssertEqual(x.text, "Normal")
        x.choose(.effusion)
        XCTAssertEqual(x.result, .effusion)
        XCTAssertNotEqual(x.text, "Normal", "an effusion replaces Normal")
        x.side = .right
        x.choose(nil)
        XCTAssertNil(x.result, "the same chip again clears it")
        XCTAssertNil(x.side)
        XCTAssertTrue(x.isEmpty)
    }

    func testTheChestXrayReadsAsAReportWouldSayIt() {
        XCTAssertEqual(PatientChestXray(result: .normal).summary, "Chest X-ray: Normal")
        XCTAssertEqual(PatientChestXray(result: .effusion, side: .left, size: .moderate, findings: "blunted costophrenic angle").summary,
                       "Chest X-ray: moderate left effusion; blunted costophrenic angle")
        XCTAssertEqual(PatientChestXray(result: .effusion, side: .bilateral, size: .small).text, "small bilateral effusion")
        XCTAssertEqual(PatientChestXray(result: .effusion, side: .right).text, "right effusion", "no size recorded, none said")
        XCTAssertEqual(PatientChestXray(result: .effusion, size: .large).text, "large effusion")
        XCTAssertEqual(PatientChestXray(result: .effusion).text, "effusion")
        XCTAssertEqual(PatientChestXray(findings: "  cardiomegaly ").text, "cardiomegaly", "findings alone, trimmed")
        XCTAssertEqual(PatientChestXray(result: .normal, findings: "old healed rib fractures").text, "Normal; old healed rib fractures")
        XCTAssertNil(PatientChestXray().text)
        XCTAssertNil(PatientChestXray(findings: "   ").summary)
    }

    func testTheChestXrayRoundTripsAndToleratesWhatItDoesNotKnow() throws {
        var r = chole()
        r.chestXray = PatientChestXray(result: .effusion, side: .left, size: .large, findings: "x")
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again.chestXray, r.chestXray)
        XCTAssertFalse(again.isEmpty)
        let odd = try JSONDecoder().decode(PatientChestXray.self, from: Data(#"{"result":"normal","side":"left","size":"huge","findings":3}"#.utf8))
        XCTAssertEqual(odd.result, .normal)
        XCTAssertNil(odd.side, "dropped with a normal result")
        XCTAssertNil(odd.size)
        XCTAssertEqual(odd.findings, "", "a malformed field takes its default")
        let unknown = try JSONDecoder().decode(PatientChestXray.self, from: Data(#"{"result":"pneumothorax"}"#.utf8))
        XCTAssertNil(unknown.result)
    }

    func testTheWorkupHasAChestXrayChipBesideTheECGEchoAndStressTest() {
        let r = chole()
        let items = PatientPreop.workup(r)
        XCTAssertEqual(items.prefix(4).map(\.id), ["ecg", "echo", "stress", "cxr"])
        let empty = items.first { $0.id == "cxr" }
        XCTAssertEqual(empty?.title, "Chest X-ray")
        XCTAssertEqual(empty?.key, "workup:cxr")
        XCTAssertFalse(empty?.filled ?? true, "+ Chest X-ray while nothing is recorded")
        XCTAssertEqual(PatientEditor(preopKey: "workup:cxr"), .workup("cxr"))
        XCTAssertEqual(PatientEditor.workup("cxr").title, "Chest X-ray")
        XCTAssertEqual(PatientDeepLink.parse("workup:cxr"), .editor(.workup("cxr")))

        var normal = r
        normal.chestXray = PatientChestXray(result: .normal)
        let n = PatientPreop.workup(normal).first { $0.id == "cxr" }
        XCTAssertEqual(n?.summary, "Normal", "the row's own title says Chest X-ray")
        XCTAssertFalse(n?.alert ?? true)
        XCTAssertTrue(PatientPreop.workupHasData(normal))

        var eff = r
        eff.chestXray = PatientChestXray(result: .effusion, side: .left, size: .moderate, findings: "blunted angle")
        let e = PatientPreop.workup(eff).first { $0.id == "cxr" }
        XCTAssertEqual(e?.summary, "moderate left effusion; blunted angle")
        XCTAssertTrue(e?.alert ?? false, "an effusion is marked for attention")
    }

    func testTheChestXrayLineIsInThePreprocedureSummaryAndTheHandoff() {
        var r = chole()
        r.ecg = ["Normal sinus rhythm"]
        r.stressTest = PatientStressTest(kind: .exercise, result: .negative)
        r.lhc.dominance = "right"; r.lhc.result = "non-obstructive"
        r.chestXray = PatientChestXray(result: .effusion, side: .left, size: .moderate, findings: "blunted angle")
        for blocks in [PatientBriefs.preop(r), PatientBriefs.handoff(r)] {
            let w = blocks.first { $0.key == "workup" }
            XCTAssertNotNil(w)
            let lines = w?.text.components(separatedBy: "\n") ?? []
            let cxr = lines.firstIndex { $0 == "Chest X-ray: moderate left effusion; Blunted angle" }
            let stress = lines.firstIndex { $0.hasPrefix("Stress test:") }
            let cor = lines.firstIndex { $0.hasPrefix("Coronaries:") }
            XCTAssertNotNil(cxr, w?.text ?? "")
            XCTAssertNotNil(stress); XCTAssertNotNil(cor)
            XCTAssertTrue(stress! < cxr! && cxr! < cor!, "after the stress test, before the catheterizations: \(lines)")
            XCTAssertTrue(w?.alert ?? false, "an effusion marks the block")
            XCTAssertTrue(w?.marks.contains("moderate left effusion") ?? false, "its words are the bold red ones")
        }
        // Normal: the same line, nothing red.
        r.chestXray = PatientChestXray(result: .normal)
        r.stressTest = PatientStressTest()
        let n = PatientBriefs.preop(r).first { $0.key == "workup" }
        XCTAssertTrue(n?.text.components(separatedBy: "\n").contains("Chest X-ray: Normal") ?? false, n?.text ?? "")
        XCTAssertFalse(n?.marks.contains("Normal") ?? true)
        // Nothing recorded: no line.
        let none = PatientBriefs.preop(chole()).first { $0.key == "workup" }
        XCTAssertFalse(none?.text.contains("Chest X-ray") ?? false)
    }

    func testTheChestXrayChipRowsFitOneLineAt375() {
        let width: CGFloat = 375 - 40 - 28
        XCTAssertNotNil(ChipMetrics.lineFit(PatientEditorView.chestXrayResults, choice: true, in: width), "Normal · Effusion")
        XCTAssertNotNil(ChipMetrics.lineFit(PatientEditorView.chestXraySides, choice: true, in: width), "Left · Right · Bilateral")
        XCTAssertNotNil(ChipMetrics.lineFit(PatientEditorView.chestXraySizes, choice: true, in: width), "Small · Moderate · Large")
        XCTAssertEqual(PatientEditorView.chestXrayResults.map(\.label), ["Normal", "Effusion"])
    }

    func testTheChestXrayDemosCarryTheirFinding() throws {
        XCTAssertEqual(try XCTUnwrap(PatientDemo112Devices.record("demo-112-cxr")).chestXray.result, .effusion)
        XCTAssertEqual(try XCTUnwrap(PatientDemo112Devices.record("demo-112-cxr-normal")).chestXray.result, .normal)
    }

    // MARK: Note 9: the valve calculator

    private let bsa17 = ValveGrading.Context(bsa: 1.7, lvef: nil)

    private func calc(_ typed: [String: Double], occupied: Set<String> = [], context: ValveGrading.Context = ValveGrading.Context()) -> ValveGrading.Calculation {
        ValveGrading.calculate(.as_, typed: typed, occupied: occupied, context: context)
    }

    func testAorticStenosisAsksForTheFourOptionalInputs() {
        let ids = ValveGrading.params(for: .as_).map(\.id)
        XCTAssertEqual(Array(ids.suffix(4)), ["lvotd", "lvotv", "lvotvti", "avvti"])
        let byID = Dictionary(uniqueKeysWithValues: ValveGrading.params(for: .as_).map { ($0.id, $0) })
        XCTAssertEqual(byID["lvotd"]?.unit, "cm")
        XCTAssertEqual(byID["lvotv"]?.unit, "m/s")
        XCTAssertEqual(byID["lvotvti"]?.unit, "cm")
        XCTAssertEqual(byID["avvti"]?.unit, "cm")
        for id in ["lvotd", "lvotv", "lvotvti", "avvti"] {
            XCTAssertNil(byID[id]?.grade(2), "an input, never graded on its own")
        }
        // The other lesions get no new input.
        for l in ValveLesion.allCases where l != .as_ {
            XCTAssertTrue(Set(ValveGrading.params(for: l).map(\.id)).isDisjoint(with: ValveGrading.calculationInputs), "\(l)")
        }
        XCTAssertEqual(ValveGrading.params(for: .ms).map(\.id), ["mva", "pht", "mg", "pasp"])
    }

    func testTheVelocityRatioIsTheLVOTVelocityOverThePeakVelocity() {
        let c = calc(["lvotv": 0.9, "vmax": 3.0])
        XCTAssertEqual(c.values["ratio"]?.value, 0.3)
        XCTAssertEqual(c.values["ratio"]?.caption, "calculated · LVOT velocity ÷ peak velocity")
        // The velocities win over the integrals when both are there.
        XCTAssertEqual(calc(["lvotv": 0.9, "vmax": 3.0, "lvotvti": 20, "avvti": 100]).values["ratio"]?.value, 0.3)
    }

    func testTheVelocityRatioFallsBackToTheVTIsWhenAVelocityIsMissing() {
        let c = calc(["lvotvti": 22, "avvti": 58])
        XCTAssertEqual(c.values["ratio"]?.value, 0.38, "22 ÷ 58")
        XCTAssertEqual(c.values["ratio"]?.caption, "calculated · LVOT VTI ÷ aortic VTI")
        XCTAssertEqual(calc(["lvotv": 0.9, "lvotvti": 22, "avvti": 58]).values["ratio"]?.value, 0.38, "the peak velocity is missing")
        XCTAssertNil(calc(["lvotv": 0.9]).values["ratio"], "one velocity alone calculates nothing")
        XCTAssertNil(calc(["lvotvti": 22]).values["ratio"])
    }

    func testTheValveAreaIsTheContinuityEquation() throws {
        // π × (2.0 ÷ 2)² × 20 ÷ 60 = 1.047, shown (and graded) as 1.0.
        let c = calc(["lvotd": 2.0, "lvotvti": 20, "avvti": 60])
        XCTAssertEqual(try XCTUnwrap(c.values["ava"]).value, 1.0)
        XCTAssertEqual(c.values["ava"]?.text, "1")
        // π × (2.0 ÷ 2)² × 18 ÷ 80 = 0.707.
        XCTAssertEqual(calc(["lvotd": 2.0, "lvotvti": 18, "avvti": 80]).values["ava"]?.value, 0.71)
        XCTAssertNil(calc(["lvotd": 2.0, "lvotvti": 20]).values["ava"], "needs the aortic VTI")
        XCTAssertNil(calc(["lvotvti": 20, "avvti": 60]).values["ava"], "needs the diameter")
    }

    func testTheStrokeVolumeIndexAndTheIndexedAreaNeedTheBSA() {
        // Stroke volume π × 1² × 22 = 69.1 mL; ÷ 1.7 = 40.7 → 41. Area π × 22 ÷ 58 = 1.19 → 1.2; ÷ 1.7 = 0.71.
        let typed: [String: Double] = ["lvotd": 2.0, "lvotvti": 22, "avvti": 58]
        let c = calc(typed, context: bsa17)
        XCTAssertEqual(c.values["svi"]?.value, 41)
        XCTAssertEqual(c.values["svi"]?.caption, "calculated · stroke volume ÷ BSA")
        XCTAssertEqual(c.values["ava"]?.value, 1.2)
        XCTAssertEqual(c.values["avai"]?.value, 0.71)
        XCTAssertEqual(c.values["avai"]?.caption, "calculated · valve area ÷ BSA")
        // Without a body size the area and the ratio are still calculated, the indexed values are not.
        let noBSA = calc(typed)
        XCTAssertNotNil(noBSA.values["ava"]); XCTAssertNotNil(noBSA.values["ratio"])
        XCTAssertNil(noBSA.values["svi"]); XCTAssertNil(noBSA.values["avai"])
        XCTAssertNil(calc(typed, context: ValveGrading.Context(bsa: 0, lvef: nil)).values["svi"], "a zero BSA divides nothing")
    }

    func testTheIndexedAreaUsesATypedAreaOverTheCalculatedOne() {
        let c = calc(["lvotd": 2.0, "lvotvti": 22, "avvti": 58, "ava": 0.85], context: bsa17)
        XCTAssertNil(c.values["ava"], "a typed field is never replaced")
        XCTAssertEqual(c.values["avai"]?.value, 0.5, "0.85 ÷ 1.7, from the typed area")
        // Only an AVA is typed: the index still follows it.
        XCTAssertEqual(calc(["ava": 1.19], context: bsa17).values["avai"]?.value, 0.7)
    }

    func testATypedValueIsNeverReplacedAndClearingBringsTheCalculatedOneBack() {
        let inputs: [String: Double] = ["lvotd": 2.0, "lvotvti": 22, "avvti": 58, "lvotv": 1.0, "vmax": 3.0]
        XCTAssertNotNil(calc(inputs, context: bsa17).values["ratio"])
        for id in ["ratio", "ava", "avai", "svi"] {
            var typed = inputs
            typed[id] = 0.77
            XCTAssertNil(calc(typed, context: bsa17).values[id], "\(id) typed: the field keeps what was typed")
            XCTAssertNotNil(calc(typed, context: bsa17).values.first { $0.key != id }, "…and the others are still calculated")
        }
        // A field holding text that is not a number yet is not empty.
        XCTAssertNil(calc(inputs, occupied: ["ava"], context: bsa17).values["ava"])
        // Cleared: back to the calculated value.
        XCTAssertEqual(calc(inputs, occupied: [], context: bsa17).values["ava"]?.value, 1.2)
    }

    func testTheMeanGradientIsNeverDerivedFromThePeakVelocity() {
        for v in [2.5, 3.3, 4.0, 5.0] {
            XCTAssertNil(calc(["vmax": v], context: bsa17).values["mg"])
            XCTAssertNil(calc(["vmax": v, "lvotv": 1, "lvotd": 2, "lvotvti": 20, "avvti": 60], context: bsa17).values["mg"])
        }
    }

    func testTheLVEFComesFromThePatientsRecordedEchoAndIsNeverRounded() {
        var r = PatientRecord()
        r.heightCm = 160; r.weightKg = 62
        var echo = PatientEcho()
        echo.lvef = 49.6
        r.echoFindings = echo
        let ctx = ValveGrading.Context(r)
        XCTAssertEqual(ctx.lvef, 49.6)
        XCTAssertEqual(ctx.bsa, r.bsa)
        XCTAssertNotNil(ctx.bsa)
        let c = calc([:], context: ctx)
        XCTAssertEqual(c.values["lvef"]?.value, 49.6, "49.6 stays below 50: rounding would change the pathway")
        XCTAssertEqual(c.values["lvef"]?.text, "49.6")
        XCTAssertEqual(c.values["lvef"]?.caption, "from My Patient's echo")
        XCTAssertNil(calc(["lvef": 60], context: ctx).values["lvef"], "a typed LVEF stays")
        XCTAssertNil(calc([:], context: ValveGrading.Context(PatientRecord())).values["lvef"], "no echo recorded")
        XCTAssertNil(ValveGrading.Context(PatientRecord()).bsa, "no height and weight")
    }

    func testADiameterNotInCentimetersIsNotUsed() {
        let c = calc(["lvotd": 20, "lvotvti": 22, "avvti": 58], context: bsa17)
        XCTAssertNil(c.values["ava"], "20 is millimeters")
        XCTAssertNil(c.values["svi"])
        XCTAssertNotNil(c.values["ratio"], "the integrals still give the ratio")
        XCTAssertEqual(c.notes.count, 1)
        XCTAssertTrue(c.notes[0].contains("cm"))
        XCTAssertTrue(calc(["lvotd": 2.0, "lvotvti": 22, "avvti": 58]).notes.isEmpty)
    }

    func testTheOtherLesionsCalculateNothing() {
        for l in ValveLesion.allCases where l != .as_ {
            XCTAssertTrue(ValveGrading.calculate(l, typed: ["lvotd": 2.0, "lvotvti": 22, "avvti": 58, "vc": 0.5, "eroa": 0.3, "mva": 1.2, "pht": 200],
                                                  context: bsa17).values.isEmpty, "\(l)")
        }
    }

    func testGradingUsesTheValueShownTypedOrCalculated() {
        // Typed: a peak velocity of 3.3 and the LVOT and integrals; calculated: the area 0.71, SVi 33, ratio 0.23.
        var typed = ValveInput()
        typed.numbers = ["vmax": 3.3, "lvotd": 2.0, "lvotvti": 18, "avvti": 80]
        let ctx = ValveGrading.Context(bsa: 1.7, lvef: 55)
        let calculation = ValveGrading.calculate(.as_, typed: typed.numbers, context: ctx)
        let graded = ValveGrading.graded(typed, with: calculation)
        XCTAssertEqual(graded.numbers["ava"], 0.71)
        XCTAssertEqual(graded.numbers["svi"], 33)
        XCTAssertEqual(graded.numbers["lvef"], 55)
        XCTAssertEqual(graded.calculated, ["ratio", "ava", "avai", "svi", "lvef"])
        XCTAssertEqual(graded.numbers["vmax"], 3.3, "typed values are untouched")

        let reading = ValveGrading.read(.as_, graded)
        XCTAssertTrue(reading.headline.contains("Paradoxical"), "a small area, low flow and a preserved EF: \(reading.headline)")
        // Without the calculation the same entries read as a moderate gradient only.
        XCTAssertEqual(ValveGrading.read(.as_, typed).headline, "Moderate AS")
        // The pills say which values were calculated, and the inputs are not readings of their own.
        XCTAssertTrue(reading.lines.first { $0.id == "ava" }?.text.contains("calculated") ?? false)
        XCTAssertFalse(reading.lines.first { $0.id == "vmax" }?.text.contains("calculated") ?? true)
        for id in ["lvotd", "lvotv", "lvotvti", "avvti"] { XCTAssertNil(reading.lines.first { $0.id == id }, id) }
    }

    func testATypedAreaIsGradedInsteadOfTheCalculatedOne() {
        var typed = ValveInput()
        typed.numbers = ["vmax": 3.3, "ava": 1.3, "lvotd": 2.0, "lvotvti": 18, "avvti": 80]
        let graded = ValveGrading.graded(typed, with: ValveGrading.calculate(.as_, typed: typed.numbers))
        XCTAssertEqual(graded.numbers["ava"], 1.3)
        XCTAssertFalse(graded.calculated.contains("ava"))
        XCTAssertEqual(ValveGrading.read(.as_, graded).headline, "Moderate AS")
    }

    func testTheLVEFAloneStillAsksForMeasurements() {
        var typed = ValveInput()
        let calculation = ValveGrading.calculate(.as_, typed: [:], context: ValveGrading.Context(bsa: 1.7, lvef: 55))
        typed = ValveGrading.graded(typed, with: calculation)
        XCTAssertEqual(ValveGrading.read(.as_, typed).headline.titleCased, "Enter Measurements")
        XCTAssertNil(ValveGrading.read(.as_, typed).overall)
    }

    func testTheCalculatorSaysWhereTheBSAAndLVEFCameFrom() {
        let ctx = ValveGrading.Context(bsa: 1.7, lvef: 55)
        let c = calc(["lvotd": 2.0, "lvotvti": 22, "avvti": 58], context: ctx)
        XCTAssertEqual(ValveGraderView.patientLine(c, context: ctx), "BSA 1.70 m² and LVEF 55% from My Patient.")
        XCTAssertNil(ValveGraderView.patientLine(calc(["lvotd": 2.0, "lvotvti": 22, "avvti": 58]), context: ValveGrading.Context()))
        XCTAssertEqual(ValveGraderView.patientLine(calc([:], context: ValveGrading.Context(bsa: nil, lvef: 55)), context: ValveGrading.Context(bsa: nil, lvef: 55)),
                       "LVEF 55% from My Patient.")
    }

    func testTheValveDemoHasABodyAndAnEcho() throws {
        let r = try XCTUnwrap(PatientDemo112Devices.record("demo-112-valvecalc"))
        let ctx = ValveGrading.Context(r)
        XCTAssertNotNil(ctx.bsa)
        XCTAssertEqual(ctx.lvef, 55)
    }
}
