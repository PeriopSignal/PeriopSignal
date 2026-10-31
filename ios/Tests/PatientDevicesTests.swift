import XCTest
import CoreGraphics
@testable import PeriopSignal

/// My Patient's body diagram: the device model, the site catalog, the shorthand parser and the handoff labels.
final class PatientDevicesTests: XCTestCase {

    private func parse(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> DeviceParse {
        try XCTUnwrap(PatientDevices.parse(text), "no parse for \"\(text)\"", file: file, line: line)
    }

    private func check(_ text: String, _ kind: DeviceKind, size: String = "", site: String?, side: String? = nil,
                       detail: String = "", settings: [String: String] = [:], label: String? = nil, confidence: Double? = nil,
                       file: StaticString = #filePath, line: UInt = #line) throws {
        let p = try parse(text, file: file, line: line)
        XCTAssertEqual(p.kind, kind, "kind of \"\(text)\"", file: file, line: line)
        XCTAssertEqual(p.size, size, "size of \"\(text)\"", file: file, line: line)
        XCTAssertEqual(p.site, site, "site of \"\(text)\"", file: file, line: line)
        XCTAssertEqual(p.side, side, "side of \"\(text)\"", file: file, line: line)
        XCTAssertEqual(p.detail, detail, "detail of \"\(text)\"", file: file, line: line)
        XCTAssertEqual(p.settings, settings, "settings of \"\(text)\"", file: file, line: line)
        if let label { XCTAssertEqual(p.device().label, label, "label of \"\(text)\"", file: file, line: line) }
        if let confidence { XCTAssertEqual(p.confidence, confidence, accuracy: 0.001, "confidence of \"\(text)\"", file: file, line: line) }
    }

    // MARK: Shorthand

    func testBensShorthand() throws {
        try check("20 rue", .piv, size: "20", site: "antecubital-right", side: "right", label: "PIV 20 G R AC", confidence: 0.9)
        try check("16ga lfa", .piv, size: "16", site: "forearm-left", side: "left", label: "PIV 16 G L forearm", confidence: 0.85)
        try check("14 l hand", .piv, size: "14", site: "hand-left", side: "left", label: "PIV 14 G L hand", confidence: 0.9)
        try check("RIJ introducer/mac", .cvc, site: "ij-right", side: "right", detail: "MAC introducer",
                  label: "CVL R IJ (MAC introducer)", confidence: 1)
    }

    func testPeripheralAndArterialLines() throws {
        try check("18g LAC", .piv, size: "18", site: "antecubital-left", side: "left", label: "PIV 18 G L AC", confidence: 0.9)
        try check("18 L AC", .piv, size: "18", site: "antecubital-left", side: "left", label: "PIV 18 G L AC", confidence: 0.9)
        try check("R rad art line 20g", .arterial, size: "20", site: "radial-right", side: "right", label: "A-line 20 G R radial", confidence: 1)
        try check("L radial aline", .arterial, site: "radial-left", side: "left", label: "A-line L radial", confidence: 1)
        try check("R fem art", .arterial, site: "femoral-artery-right", side: "right", label: "A-line R femoral", confidence: 0.9)
        try check("R AC", .piv, site: "antecubital-right", side: "right", label: "PIV R AC")
        try check("16g RLE", .piv, size: "16", site: "saphenous-right", side: "right", label: "PIV 16 G R saphenous")
        try check("RUE PICC", .picc, site: "upper-arm-right", side: "right", label: "PICC R upper arm")
    }

    func testCentralLines() throws {
        try check("LFV cordis 8.5", .cvc, size: "8.5", site: "femoral-vein-left", side: "left", detail: "Cordis",
                  label: "CVL 8.5 Fr L femoral (Cordis)", confidence: 1)
        try check("RIJ TLC", .cvc, site: "ij-right", side: "right", detail: "triple lumen", label: "CVL R IJ (triple lumen)")
        try check("LSC TLC", .cvc, site: "subclavian-left", side: "left", detail: "triple lumen", label: "CVL L subclavian (triple lumen)")
        try check("PAC via RIJ", .pac, site: "ij-right", side: "right", label: "PAC via R IJ", confidence: 1)
        try check("swan RIJ 8.5 Fr introducer", .pac, site: "ij-right", side: "right", detail: "8.5 Fr introducer",
                  label: "PAC via R IJ (8.5 Fr introducer)", confidence: 1)
        try check("R IJ TLC 16 cm difficult", .cvc, site: "ij-right", side: "right", detail: "triple lumen, difficult",
                  settings: ["depth": "16"], label: "CVL R IJ at 16 cm (triple lumen, difficult)", confidence: 0.9)
    }

    func testAirway() throws {
        try check("7.5 ETT 23 cm", .ett, size: "7.5", site: "mouth", settings: ["depth": "23"], label: "ETT 7.5 at 23 cm", confidence: 1)
        try check("ETT 8.0 @ 22 at teeth", .ett, size: "8.0", site: "mouth", settings: ["depth": "22", "depthAt": "teeth"],
                  label: "ETT 8.0 at 22 cm (teeth)", confidence: 1)
        try check("trach 8 shiley", .trach, size: "8", site: "trach", detail: "Shiley", label: "Trach 8 (Shiley)", confidence: 1)
        try check("6 cuffed trach", .trach, size: "6", site: "trach", detail: "cuffed", label: "Trach 6 (cuffed)", confidence: 1)
        try check("nasal ETT 7.0 at 28 cm", .ett, size: "7.0", site: "nose", settings: ["depth": "28"], label: "ETT 7.0 at 28 cm (nasal)")
        try check("37 L DLT 29 cm", .ett, size: "37", site: "mouth", detail: "Left DLT", settings: ["depth": "29"],
                  label: "Left DLT 37 Fr at 29 cm")
        try check("LMA 4", .other, size: "4", site: "mouth", detail: "LMA", label: "LMA 4")
    }

    func testPumps() throws {
        try check("L fem IABP 7.5 Fr", .iabp, size: "7.5", site: "femoral-artery-left", side: "left", label: "IABP 7.5 Fr L femoral", confidence: 1)
        let iabp = try parse("IABP 1:1")
        XCTAssertEqual(iabp.kind, .iabp)
        XCTAssertEqual(iabp.settings, ["ratio": "1:1"])
        XCTAssertNil(iabp.site, "no side given")
        XCTAssertEqual(iabp.baseSite, "femoral-artery", "an IABP goes in the femoral artery by default")
        XCTAssertEqual(iabp.confidence, 0.6, accuracy: 0.001)
        XCTAssertEqual(iabp.alternatives.map(\.site), ["femoral-artery-right", "femoral-artery-left"])
        XCTAssertEqual(iabp.device().label, "IABP 1:1")
        try check("IABP L femoral 1:1", .iabp, site: "femoral-artery-left", side: "left", settings: ["ratio": "1:1"], label: "IABP L femoral 1:1")
        try check("Impella CP RFA", .impella, site: "femoral-artery-right", side: "right", detail: "CP", label: "Impella CP R femoral", confidence: 1)
        try check("Impella 5.5 R axillary", .impella, site: "axillary-artery-right", side: "right", detail: "5.5",
                  label: "Impella 5.5 R axillary", confidence: 1)
        try check("Impella CP R femoral P6, 3.2 L/min", .impella, site: "femoral-artery-right", side: "right", detail: "CP",
                  settings: ["pLevel": "6", "flow": "3.2"], label: "Impella CP R femoral P6, 3.2 L/min")
        try check("Impella RP R femoral", .impella, site: "femoral-vein-right", side: "right", detail: "RP", label: "Impella RP R femoral")
        try check("HM3 LVAD", .lvad, site: "heart", detail: "HeartMate 3", label: "HeartMate 3 LVAD", confidence: 1)
        try check("HeartMate 3 LVAD 5400 rpm, PI 4.1, 4.8 L/min", .lvad, site: "heart", detail: "HeartMate 3",
                  settings: ["rpm": "5400", "pi": "4.1", "flow": "4.8"], label: "HeartMate 3 LVAD 5400 rpm, PI 4.1, 4.8 L/min")
    }

    func testECMOShorthand() throws {
        let vv = try parse("VV ECMO 25 Fr RFV drainage 21 Fr RIJ return")
        XCTAssertEqual(vv.kind, .ecmoDrainage)
        XCTAssertEqual(vv.size, "25")
        XCTAssertEqual(vv.site, "femoral-vein-right")
        XCTAssertEqual(vv.settings, ["mode": "VV"])
        XCTAssertEqual(vv.companions.count, 1)
        XCTAssertEqual(vv.companions.first?.kind, .ecmoReturn)
        XCTAssertEqual(vv.companions.first?.size, "21")
        XCTAssertEqual(vv.companions.first?.site, "ij-right")
        XCTAssertEqual(vv.devices().map(\.label), ["ECMO drainage 25 Fr R femoral vein", "ECMO return 21 Fr R IJ"])
        XCTAssertEqual(vv.confidence, 1, accuracy: 0.001)
        XCTAssertEqual(PatientDevices.ecmoSystem(vv.devices())?.configuration, .vv)

        let va = try parse("VA ECMO 25F LFV / 17F LFA")
        XCTAssertEqual(va.devices().map(\.kind), [.ecmoDrainage, .ecmoReturn])
        XCTAssertEqual(va.devices().map(\.site), ["femoral-vein-left", "femoral-artery-left"], "LFA is the femoral artery in an ECMO entry")
        XCTAssertEqual(va.devices().map(\.size), ["25", "17"])
        XCTAssertEqual(va.settings["mode"], "VA")
        XCTAssertEqual(va.confidence, 1, accuracy: 0.001)
        XCTAssertEqual(PatientDevices.ecmoSystem(va.devices())?.configuration, .vaPeripheral)

        let flows = try parse("VV ECMO 25 Fr RFV drainage 21 Fr RIJ return, flow 4.5 L/min, sweep 3 L/min")
        XCTAssertEqual(flows.settings, ["flow": "4.5", "sweep": "3", "mode": "VV"])
        XCTAssertEqual(PatientDevices.ecmoSystem(flows.devices())?.label,
                       "VV ECMO: drainage 25 Fr R femoral vein, return 21 Fr R IJ; flow 4.5 L/min, sweep 3 L/min")

        let central = try parse("central VA ECMO 24 Fr / 22 Fr")
        XCTAssertEqual(central.devices().map(\.site), ["right-atrium", "aorta"])
        XCTAssertEqual(central.devices().map(\.kind), [.ecmoDrainage, .ecmoReturn])
        XCTAssertEqual(PatientDevices.ecmoSystem(central.devices())?.configuration, .vaCentral)

        let unordered = try parse("VV ECMO 21 Fr RIJ / 25 Fr RFV")
        XCTAssertEqual(unordered.devices().map(\.site), ["femoral-vein-right", "ij-right"], "the larger cannula drains")
        XCTAssertEqual(unordered.devices().map(\.kind), [.ecmoDrainage, .ecmoReturn])
        XCTAssertEqual(unordered.confidence, 0.85, accuracy: 0.001)

        let issues = try parse("VA ECMO 25F LFV / 17F LFA flow 4 sweep 2 fdo2 100% thrombus at the oxygenator")
        XCTAssertEqual(issues.settings, ["flow": "4", "sweep": "2", "fdo2": "100", "issues": "thrombus at the oxygenator", "mode": "VA"])
        XCTAssertEqual(PatientDevices.ecmoSystem(issues.devices())?.label,
                       "Peripheral VA ECMO: drainage 25 Fr L femoral vein, return 17 Fr L femoral artery; flow 4 L/min, sweep 2 L/min, FdO2 100%, thrombus at the oxygenator")

        let dual = try parse("VV ECMO 31 Fr Avalon RIJ")
        XCTAssertEqual(dual.companions.count, 0)
        XCTAssertEqual(dual.site, "ij-right")
        XCTAssertEqual(dual.detail, "Avalon dual lumen")
        XCTAssertEqual(PatientDevices.ecmoSystem(dual.devices())?.configuration, .vv)
    }

    func testNeuraxialAndBlocks() throws {
        try check("L2-3 epidural", .epidural, site: "lumbar-spine", settings: ["level": "L2-3"], label: "Epidural L2-3", confidence: 1)
        try check("T8 epidural cath", .epidural, site: "thoracic-spine", settings: ["level": "T8"], label: "Epidural T8", confidence: 1)
        try check("spinal L3-4", .spinal, site: "lumbar-spine", settings: ["level": "L3-4"], label: "Spinal L3-4", confidence: 1)
        try check("T7/8 epidural", .epidural, site: "thoracic-spine", settings: ["level": "T7-8"], label: "Epidural T7-8")
        try check("L1-2 CSE", .epidural, site: "lumbar-spine", detail: "CSE", settings: ["level": "L1-2"], label: "Epidural L1-2 (CSE)")
        try check("R interscalene", .block, site: "interscalene-right", side: "right", label: "R interscalene block", confidence: 0.9)
        try check("R PIFB", .block, site: "parasternal-right", side: "right", detail: "PIFB", label: "R parasternal block (PIFB)")
        let esp = try parse("B/L ESP catheters")
        XCTAssertEqual(esp.devices().map(\.kind), [.perineuralCatheter, .perineuralCatheter])
        XCTAssertEqual(esp.devices().map(\.site), ["esp-right", "esp-left"])
        XCTAssertEqual(esp.devices().map(\.side), ["right", "left"])
        XCTAssertEqual(esp.devices().map(\.label), ["R ESP catheter", "L ESP catheter"])
        XCTAssertEqual(esp.confidence, 1, accuracy: 0.001)
        XCTAssertTrue(DeviceSite.site(id: "esp-right")?.back ?? false, "a back site, drawn on the front figure")
    }

    func testAmbiguousEntries() throws {
        let fa = try parse("lfa")
        XCTAssertEqual(fa.kind, .piv, "FA alone is the forearm, as in \"16ga lfa\"")
        XCTAssertEqual(fa.site, "forearm-left")
        XCTAssertEqual(fa.confidence, 0.6, accuracy: 0.001)
        XCTAssertEqual(fa.alternatives.map(\.kind), [.arterial])
        XCTAssertEqual(fa.alternatives.map(\.site), ["femoral-artery-left"])
        XCTAssertEqual(fa.alternatives.first?.confidence ?? 0, 0.5, accuracy: 0.001)

        let fem = try parse("R fem")
        XCTAssertEqual(fem.kind, .cvc)
        XCTAssertEqual(fem.site, "femoral-vein-right")
        XCTAssertEqual(fem.alternatives.map(\.site), ["femoral-artery-right", "femoral-block-right"])
        XCTAssertEqual(fem.alternatives.map(\.kind), [.arterial, .block])

        let ax = try parse("R axillary")
        XCTAssertEqual(ax.kind, .block)
        XCTAssertEqual(ax.site, "axillary-block-right")
        XCTAssertEqual(ax.alternatives.map(\.site), ["axillary-artery-right"])

        let aline = try parse("aline 20")
        XCTAssertEqual(aline.kind, .arterial)
        XCTAssertEqual(aline.size, "20")
        XCTAssertNil(aline.site)
        XCTAssertEqual(aline.baseSite, "radial")
        XCTAssertEqual(aline.alternatives.map(\.site), ["radial-right", "radial-left"])
        XCTAssertEqual(aline.confidence, 0.6, accuracy: 0.001)

        let tlc = try parse("TLC")
        XCTAssertEqual(tlc.kind, .cvc)
        XCTAssertEqual(tlc.baseSite, "ij")
        XCTAssertEqual(tlc.detail, "triple lumen")

        XCTAssertNil(PatientDevices.parse(""))
        XCTAssertNil(PatientDevices.parse("   "))
        XCTAssertNil(PatientDevices.parse("hello"))
        XCTAssertEqual(PatientDevices.parse("20")?.kind, .piv)
        XCTAssertLessThan(PatientDevices.parse("20")?.confidence ?? 1, 0.4, "a bare gauge is only a hint")
    }

    func testEveryExampleLandsOnTheFigure() throws {
        let examples = ["20 rue", "16ga lfa", "14 l hand", "RIJ introducer/mac", "18g LAC", "18 L AC", "R rad art line 20g",
                        "L radial aline", "R fem art", "LFV cordis 8.5", "RIJ TLC", "LSC TLC", "PAC via RIJ",
                        "swan RIJ 8.5 Fr introducer", "7.5 ETT 23 cm", "ETT 8.0 @ 22 at teeth", "trach 8 shiley", "6 cuffed trach",
                        "L fem IABP 7.5 Fr", "Impella CP RFA", "Impella 5.5 R axillary", "VV ECMO 25 Fr RFV drainage 21 Fr RIJ return",
                        "VA ECMO 25F LFV / 17F LFA", "HM3 LVAD", "L2-3 epidural", "T8 epidural cath", "spinal L3-4",
                        "R interscalene", "B/L ESP catheters"]
        for e in examples {
            let p = try parse(e)
            XCTAssertGreaterThanOrEqual(p.confidence, 0.85, "\"\(e)\" is said outright")
            for d in p.devices() {
                let site = DeviceSite.site(id: d.site)
                XCTAssertNotNil(site, "\"\(e)\" places its \(d.kind.label) on the figure")
                XCTAssertTrue(site?.kinds.contains(d.kind) ?? false, "\"\(e)\": \(d.kind.label) is a likely kind at \(d.site)")
            }
        }
    }

    // MARK: Labels and ECMO

    func testLabels() {
        func d(_ kind: DeviceKind, _ site: String = "", size: String = "", detail: String = "", settings: [String: String] = [:]) -> PatientDevice {
            PatientDevice(kind: kind, site: site, side: DeviceSite.site(id: site)?.side, size: size, detail: detail, settings: settings)
        }
        XCTAssertEqual(d(.piv, "antecubital-right", size: "20").label, "PIV 20 G R AC")
        XCTAssertEqual(d(.arterial, "radial-left", size: "20").label, "A-line 20 G L radial")
        XCTAssertEqual(d(.cvc, "ij-right", detail: "MAC introducer").label, "CVL R IJ (MAC introducer)")
        XCTAssertEqual(d(.pac, "ij-right").label, "PAC via R IJ")
        XCTAssertEqual(d(.ett, "mouth", size: "7.5", settings: ["depth": "23"]).label, "ETT 7.5 at 23 cm")
        XCTAssertEqual(d(.iabp, "femoral-artery-left", settings: ["ratio": "1:1"]).label, "IABP L femoral 1:1")
        XCTAssertEqual(d(.impella, "femoral-artery-right", detail: "CP", settings: ["pLevel": "6", "flow": "3.2"]).label,
                       "Impella CP R femoral P6, 3.2 L/min")
        XCTAssertEqual(d(.lvad, "heart", detail: "HeartMate 3", settings: ["rpm": "5400", "pi": "4.1", "flow": "4.8"]).label,
                       "HeartMate 3 LVAD 5400 rpm, PI 4.1, 4.8 L/min")
        let vv = [d(.ecmoDrainage, "femoral-vein-right", size: "25", settings: ["mode": "VV", "flow": "4.5", "sweep": "3"]),
                  d(.ecmoReturn, "ij-right", size: "21")]
        XCTAssertEqual(PatientDevices.ecmoSystem(vv)?.label,
                       "VV ECMO: drainage 25 Fr R femoral vein, return 21 Fr R IJ; flow 4.5 L/min, sweep 3 L/min")
        XCTAssertEqual(d(.ecmoReturn, "femoral-artery-left", size: "17").label, "ECMO return 17 Fr L femoral artery",
                       "an ECMO cannula names its vessel")
        XCTAssertEqual(d(.arterial, "femoral-artery-left", size: "20").label, "A-line 20 G L femoral")
        XCTAssertEqual(d(.iabp, "femoral-artery-left", settings: ["ratio": "1:2", "augmentation": "110", "timing": "late deflation"]).label,
                       "IABP L femoral 1:2, augmentation 110 mmHg, timing late deflation")
        XCTAssertEqual(d(.impella, "axillary-artery-right", detail: "5.5", settings: ["pLevel": "P8", "position": "4.5"]).label,
                       "Impella 5.5 R axillary P8, position 4.5 cm")
        XCTAssertEqual(d(.epidural, "thoracic-spine", settings: ["level": "T8", "depth": "10"]).label, "Epidural T8 (10 cm at the skin)")
        XCTAssertEqual(d(.epidural, "lumbar-spine").label, "Epidural lumbar")
        XCTAssertEqual(d(.spinal, "lumbar-spine", size: "25", settings: ["level": "L3-4"]).label, "Spinal L3-4 (25 G)")
        XCTAssertEqual(d(.block, detail: "ropivacaine 0.5% 20 mL").label, "Single-shot block (ropivacaine 0.5% 20 mL)")
        XCTAssertEqual(d(.perineuralCatheter, "adductor-canal-left").label, "L adductor canal catheter")
        XCTAssertEqual(d(.other, detail: "Chest tube", settings: [:]).label, "Chest tube")
        XCTAssertEqual(d(.other).label, "Other")
        XCTAssertEqual(d(.picc, "upper-arm-left", size: "5", detail: "double lumen").label, "PICC 5 Fr L upper arm (double lumen)")
        XCTAssertEqual(d(.intraosseous, "tibial-io-right", size: "15").label, "IO 15 G R tibia")
        XCTAssertEqual(d(.piv, size: "20").label, "PIV 20 G", "not placed yet")
        var ett = d(.ett, "mouth", size: "7.5", settings: ["depth": "23"])
        ett.removed = true
        XCTAssertEqual(ett.label, "ETT 7.5 at 23 cm (extubated)")
        var cvl = d(.cvc, "ij-right", detail: "triple lumen")
        cvl.removed = true
        XCTAssertEqual(cvl.label, "CVL R IJ (triple lumen, removed)")
    }

    func testHandoffList() {
        var ett = PatientDevice(kind: .ett, site: "mouth", size: "7.5", settings: ["depth": "23"])
        ett.removed = true
        let devices = [
            PatientDevice(kind: .piv, site: "antecubital-right", side: "right", size: "20"),
            PatientDevice(kind: .ecmoDrainage, site: "femoral-vein-right", side: "right", size: "25", settings: ["mode": "VV", "flow": "4.5", "sweep": "3"]),
            PatientDevice(kind: .arterial, site: "radial-left", side: "left", size: "20"),
            PatientDevice(kind: .ecmoReturn, site: "ij-right", side: "right", size: "21"),
            ett,
        ]
        XCTAssertEqual(PatientDevices.labels(devices), [
            "PIV 20 G R AC",
            "VV ECMO: drainage 25 Fr R femoral vein, return 21 Fr R IJ; flow 4.5 L/min, sweep 3 L/min",
            "A-line 20 G L radial",
        ])
        XCTAssertEqual(PatientDevices.labels(devices, includeRemoved: true).last, "ETT 7.5 at 23 cm (extubated)")
        XCTAssertEqual(PatientDevices.labels([]), [])
    }

    func testECMOConfigurations() {
        func c(_ kind: DeviceKind, _ site: String, _ size: String = "", detail: String = "", settings: [String: String] = [:]) -> PatientDevice {
            PatientDevice(kind: kind, site: site, size: size, detail: detail, settings: settings)
        }
        XCTAssertNil(PatientDevices.ecmoSystem([]))
        XCTAssertNil(PatientDevices.ecmoSystem([c(.piv, "antecubital-right")]))

        let vv = PatientDevices.ecmoSystem([c(.ecmoDrainage, "femoral-vein-right", "25"), c(.ecmoReturn, "ij-right", "21")])
        XCTAssertEqual(vv?.configuration, .vv)
        XCTAssertEqual(vv?.configuration.name, "VV")
        XCTAssertEqual(vv?.drainage.count, 1)
        XCTAssertEqual(vv?.returns.count, 1)

        let va = PatientDevices.ecmoSystem([c(.ecmoDrainage, "femoral-vein-left", "25"), c(.ecmoReturn, "femoral-artery-left", "17")])
        XCTAssertEqual(va?.configuration, .vaPeripheral)
        XCTAssertEqual(va?.configuration.name, "VA peripheral")
        XCTAssertEqual(va?.label, "Peripheral VA ECMO: drainage 25 Fr L femoral vein, return 17 Fr L femoral artery")

        let central = PatientDevices.ecmoSystem([c(.ecmoDrainage, "right-atrium", "32"), c(.ecmoReturn, "aorta", "22")])
        XCTAssertEqual(central?.configuration, .vaCentral)
        XCTAssertEqual(central?.configuration.name, "VA central")
        XCTAssertEqual(central?.label, "Central VA ECMO: drainage 32 Fr RA, return 22 Fr aorta")

        let vav = PatientDevices.ecmoSystem([c(.ecmoDrainage, "femoral-vein-right", "25"), c(.ecmoReturn, "femoral-artery-left", "17"),
                                             c(.ecmoReturn, "ij-right", "15")])
        XCTAssertEqual(vav?.configuration, .vav)
        XCTAssertEqual(vav?.configuration.name, "VAV")
        XCTAssertEqual(vav?.label, "VAV ECMO: drainage 25 Fr R femoral vein, return 17 Fr L femoral artery and 15 Fr R IJ")

        XCTAssertEqual(PatientDevices.ecmoSystem([c(.ecmoDrainage, "femoral-vein-right"), c(.ecmoReturn, "axillary-artery-right")])?.configuration,
                       .vaPeripheral)

        let dual = PatientDevices.ecmoSystem([c(.ecmoDrainage, "ij-right", "31", detail: "Avalon dual lumen")])
        XCTAssertEqual(dual?.configuration, .vv)
        XCTAssertEqual(dual?.label, "VV ECMO: drainage 31 Fr R IJ (Avalon dual lumen)")

        let modeOnly = PatientDevices.ecmoSystem([c(.ecmoDrainage, "femoral-vein-right", settings: ["mode": "VA"])])
        XCTAssertEqual(modeOnly?.configuration, .vaPeripheral, "with no return cannula placed, the mode decides")

        let unknown = PatientDevices.ecmoSystem([c(.ecmoDrainage, "femoral-vein-right", "25")])
        XCTAssertEqual(unknown?.configuration, .unknown)
        XCTAssertEqual(unknown?.label, "ECMO: drainage 25 Fr R femoral vein")
        XCTAssertEqual(PatientDevices.ecmoSystem([c(.ecmoDrainage, "")])?.label, "ECMO: drainage")

        // Settings merge, drainage first and the first value given winning; removed cannulas are left out.
        var old = c(.ecmoReturn, "femoral-artery-right", "19")
        old.removed = true
        let merged = PatientDevices.ecmoSystem([c(.ecmoReturn, "ij-right", "21", settings: ["flow": "5", "issues": "chatter"]),
                                                c(.ecmoDrainage, "femoral-vein-right", "25", settings: ["flow": "4.5", "sweep": "3"]), old])
        XCTAssertEqual(merged?.settings, ["flow": "4.5", "sweep": "3", "issues": "chatter"])
        XCTAssertEqual(merged?.configuration, .vv, "the removed arterial cannula no longer counts")
        XCTAssertEqual(merged?.returns.count, 1)
        XCTAssertEqual(merged?.label, "VV ECMO: drainage 25 Fr R femoral vein, return 21 Fr R IJ; flow 4.5 L/min, sweep 3 L/min, chatter")
    }

    // MARK: Sites

    func testSiteCatalog() throws {
        let all = DeviceSite.all
        XCTAssertEqual(all.count, 68, "38 sites, 30 of them on both sides")
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "ids are unique")
        for s in all {
            XCTAssertTrue((0...1).contains(s.anchor.x) && (0...1).contains(s.anchor.y), "\(s.id) sits inside the figure box")
            XCTAssertFalse(s.kinds.isEmpty, "\(s.id) has likely kinds")
            XCTAssertEqual(DeviceSite.site(id: s.id), s)
            if let side = s.side {
                let other = try XCTUnwrap(DeviceSite.find(s.base, side: side == "right" ? "left" : "right"))
                XCTAssertEqual(Double(s.anchor.x + other.anchor.x), 1, accuracy: 1e-9, "\(s.id) mirrors its other side")
                XCTAssertEqual(s.anchor.y, other.anchor.y)
                XCTAssertTrue(s.name.hasPrefix(side == "right" ? "Right " : "Left "), s.name)
                XCTAssertTrue(s.short.hasPrefix(side == "right" ? "R " : "L "), s.short)
                XCTAssertEqual(s.id, s.base + "-" + side)
            } else {
                XCTAssertEqual(s.id, s.base)
                XCTAssertFalse(DeviceSite.isPaired(s.base))
            }
        }
        let rAC = try XCTUnwrap(DeviceSite.site(id: "antecubital-right"))
        XCTAssertEqual(rAC.name, "Right antecubital fossa")
        XCTAssertEqual(rAC.short, "R AC")
        XCTAssertEqual(rAC.region, "arm")
        XCTAssertLessThan(rAC.anchor.x, 0.5, "the patient's right is on the viewer's left")
        XCTAssertEqual(DeviceSite.site(id: "femoral-artery-left")?.short, "L femoral artery")
        XCTAssertEqual(DeviceSite.site(id: "femoral-artery-left")?.brief, "L femoral")
        let mouth = try XCTUnwrap(DeviceSite.site(id: "mouth"))
        XCTAssertNil(mouth.side)
        XCTAssertEqual(mouth.name, "Mouth")
        XCTAssertGreaterThan(DeviceSite.site(id: "heart")?.anchor.x ?? 0, 0.5, "the heart is on the patient's left")
        XCTAssertLessThan(mouth.anchor.y, DeviceSite.site(id: "trach")?.anchor.y ?? 0, "head at the top")
        XCTAssertLessThan(DeviceSite.site(id: "radial-right")?.anchor.x ?? 1, DeviceSite.site(id: "wrist-right")?.anchor.x ?? 0,
                          "the radial artery is on the thumb side")
        XCTAssertEqual(Set(all.filter(\.back).map(\.base)), ["esp", "thoracic-spine", "lumbar-spine", "popliteal"])
        XCTAssertEqual(DeviceSite.find("radial", side: "left")?.id, "radial-left")
        XCTAssertNil(DeviceSite.find("radial", side: nil), "a paired site needs its side")
        XCTAssertNil(DeviceSite.find("nowhere", side: nil))
        XCTAssertEqual(DeviceSite.find("mouth", side: "left")?.id, "mouth")
        XCTAssertTrue(DeviceSite.isPaired("ij"))
        XCTAssertFalse(DeviceSite.isPaired("trach"))
        XCTAssertEqual(DeviceSite.kinds(forBase: "radial"), [.arterial])
        XCTAssertEqual(DeviceSite.figureSize, CGSize(width: 200, height: 420))
    }

    func testSitesNear() {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / 200, y: y / 420) }
        XCTAssertEqual(DeviceSite.sites(near: at(46, 157), limit: 3).map(\.id), ["antecubital-right", "brachial-right", "forearm-right"])
        XCTAssertEqual(DeviceSite.sites(near: at(95, 60), limit: 4).map(\.id), ["ij-right", "ej-right", "trach", "interscalene-right"])
        XCTAssertEqual(DeviceSite.sites(near: at(120, 200), limit: 3).map(\.id), ["femoral-artery-left", "femoral-vein-left", "femoral-block-left"])
        XCTAssertEqual(DeviceSite.sites(near: at(166, 208), limit: 2).map(\.id), ["radial-left", "wrist-left"])
        XCTAssertEqual(DeviceSite.sites(near: at(100, 182), limit: 1).map(\.id), ["lumbar-spine"])
        XCTAssertEqual(DeviceSite.sites(near: at(46, 157), limit: 3, kind: .piv).map(\.id), ["antecubital-right", "forearm-right", "upper-arm-right"])
        XCTAssertEqual(DeviceSite.sites(near: at(95, 60), limit: 1, kind: .cvc).map(\.id), ["ij-right"])
        XCTAssertTrue(DeviceSite.sites(near: CGPoint(x: 0.02, y: 0.98), limit: 5, within: 10).isEmpty, "nothing within 10 points of the corner")
        XCTAssertEqual(DeviceSite.sites(near: at(46, 157), limit: 0).count, 0)
        let ac = DeviceSite.site(id: "antecubital-right")!
        XCTAssertEqual(Double(ac.distance(to: at(46, 160))), 3, accuracy: 1e-9, "distances are in figure points")
    }

    func testLikelyKindsAndOptions() throws {
        let ac = try XCTUnwrap(DeviceSite.site(id: "antecubital-right"))
        XCTAssertEqual(DeviceSite.likelyKinds(at: ac), [.piv, .picc, .other])
        XCTAssertEqual(DeviceSite.likelyKinds(at: try XCTUnwrap(DeviceSite.site(id: "femoral-artery-left"))),
                       [.arterial, .iabp, .impella, .ecmoReturn, .other])
        XCTAssertEqual(DeviceSite.likelyKinds(at: try XCTUnwrap(DeviceSite.site(id: "ij-right"))).first, .cvc)
        XCTAssertEqual(DeviceSite.likelyKinds(at: try XCTUnwrap(DeviceSite.site(id: "lumbar-spine"))), [.epidural, .spinal, .other])
        XCTAssertEqual(DeviceSite.likelyKinds(at: try XCTUnwrap(DeviceSite.site(id: "heart"))), [.lvad, .other])
        let options = DeviceSite.options(near: ac.anchor)
        XCTAssertEqual(options.first?.kind, .piv)
        XCTAssertEqual(options.first?.site.id, "antecubital-right")
        XCTAssertEqual(options.first?.label, "PIV · R AC")
        XCTAssertEqual(Array(options.map(\.id).prefix(3)), ["antecubital-right:piv", "antecubital-right:picc", "brachial-right:arterial"])
        XCTAssertFalse(options.contains { $0.kind == .other })
        XCTAssertLessThanOrEqual(options.count, 8)
    }

    func testSpineAnchor() throws {
        let t8 = try XCTUnwrap(DeviceSite.spineAnchor(level: "T8"))
        XCTAssertEqual(Double(t8.x), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Double(t8.y * 420), 66 + 7 * 84 / 11, accuracy: 0.01)
        let l34 = try XCTUnwrap(DeviceSite.spineAnchor(level: "L3-4"))
        XCTAssertEqual(Double(l34.y * 420), 180.5, accuracy: 0.01)
        XCTAssertLessThan(t8.y, l34.y, "thoracic above lumbar")
        XCTAssertEqual(Double((DeviceSite.spineAnchor(level: "l2-3")?.y ?? 0) * 420), 171.5, accuracy: 0.01)
        XCTAssertNil(DeviceSite.spineAnchor(level: "X9"))
        XCTAssertNil(DeviceSite.spineAnchor(level: "T13"))
        XCTAssertNil(DeviceSite.spineAnchor(level: ""))
        XCTAssertEqual(Double((DeviceSite.site(id: "lumbar-spine")?.anchor.y ?? 0) * 420), 180, accuracy: 0.01)
    }

    // MARK: Model

    func testKinds() {
        XCTAssertEqual(DeviceKind.allCases.count, 18)
        XCTAssertEqual(DeviceKind.allCases.map(\.label), ["PIV", "A-line", "CVL", "PAC", "PICC", "IO", "ETT", "Trach", "ECMO drainage",
                                                          "ECMO return", "LVAD", "IABP", "Impella", "Epidural", "Spinal", "Block",
                                                          "Catheter", "Other"])
        XCTAssertEqual(DeviceKind.piv.colorRole, .line)
        XCTAssertEqual(DeviceKind.cvc.colorRole, .central)
        XCTAssertEqual(DeviceKind.picc.colorRole, .central)
        XCTAssertEqual(DeviceKind.pac.colorRole, .pac)
        XCTAssertEqual(DeviceKind.ecmoDrainage.colorRole, .venousECMO)
        XCTAssertEqual(DeviceKind.ecmoReturn.colorRole, .arterialECMO)
        XCTAssertEqual(DeviceKind.epidural.colorRole, .neuraxial)
        XCTAssertEqual(DeviceKind.spinal.colorRole, .needle)
        XCTAssertEqual(DeviceKind.block.colorRole, .needle)
        XCTAssertEqual([DeviceKind.lvad, .iabp, .impella].map(\.colorRole), [.pump, .pump, .pump])
        XCTAssertEqual([DeviceKind.ett, .trach].map(\.colorRole), [.airway, .airway])
        XCTAssertEqual([DeviceKind.piv, .arterial, .intraosseous].map(\.sizeUnit), ["G", "G", "G"])
        XCTAssertEqual([DeviceKind.cvc, .pac, .picc, .ecmoDrainage, .ecmoReturn, .iabp, .impella].map(\.sizeUnit), Array(repeating: "Fr", count: 7))
        XCTAssertEqual([DeviceKind.ett, .trach].map(\.sizeUnit), ["mm ID", "mm ID"])
        XCTAssertEqual(DeviceKind.ett.settingKeys, ["depth", "depthAt"])
        XCTAssertEqual(DeviceKind.lvad.settingKeys, ["rpm", "pi", "flow", "power"])
        XCTAssertEqual(DeviceKind.iabp.settingKeys, ["ratio", "augmentation", "timing"])
        XCTAssertEqual(DeviceKind.impella.settingKeys, ["pLevel", "flow", "position"])
        XCTAssertEqual(DeviceKind.ecmoDrainage.settingKeys, ["mode", "flow", "sweep", "fdo2", "issues"])
        XCTAssertEqual(DeviceKind.ecmoReturn.settingKeys, ["mode", "flow", "sweep", "fdo2", "issues"])
        XCTAssertEqual(DeviceKind.buttons, [.piv, .arterial, .cvc, .pac, .ett])
        XCTAssertEqual(Set(DeviceKind.buttons + DeviceKind.more), Set(DeviceKind.allCases), "every kind has a button")
        XCTAssertEqual(DeviceKind.buttons.count + DeviceKind.more.count, DeviceKind.allCases.count)
        for k in DeviceKind.allCases {
            XCTAssertFalse(k.fields.isEmpty, "\(k) asks for something")
            XCTAssertFalse(k.name.isEmpty)
        }
        XCTAssertEqual(DeviceKind.piv.fields.first?.id, "size")
        XCTAssertEqual(DeviceKind.piv.fields.first?.unit, "G")
        XCTAssertTrue(DeviceKind.piv.fields.first?.choices.contains("20") ?? false)
        XCTAssertEqual(DeviceKind.cvc.fields.first { $0.id == "detail" }?.label, "Type")
        XCTAssertTrue(DeviceKind.ecmoReturn.isECMO)
        XCTAssertFalse(DeviceKind.iabp.isECMO)
    }

    func testDeviceHelpers() throws {
        var d = PatientDevice(kind: .piv, site: "antecubital-right", side: "right", size: "20")
        let a = try XCTUnwrap(DeviceSite.site(id: "antecubital-right")).anchor
        XCTAssertEqual(d.position, a)
        d.offset = CGPoint(x: 0.01, y: -0.02)
        XCTAssertEqual(Double(d.position?.x ?? 0), Double(a.x) + 0.01, accuracy: 1e-9)
        XCTAssertEqual(Double(d.position?.y ?? 0), Double(a.y) - 0.02, accuracy: 1e-9)
        XCTAssertEqual(d.siteInfo?.id, "antecubital-right")
        XCTAssertNil(PatientDevice(kind: .piv).position, "not placed yet")
        XCTAssertEqual(PatientDevice(kind: .other, site: "mouth", detail: "LMA").colorRole, .airway)
        XCTAssertEqual(PatientDevice(kind: .other, site: "antecubital-left").colorRole, .line)
        XCTAssertEqual(PatientDevice(kind: .pac, site: "ij-right").colorRole, .pac)
        d.setValue(" 18 ", for: "size")
        d.setValue("ultrasound-guided", for: "detail")
        d.setValue("4", for: "depth")
        XCTAssertEqual(d.size, "18")
        XCTAssertEqual(d.value("size"), "18")
        XCTAssertEqual(d.value("detail"), "ultrasound-guided")
        XCTAssertEqual(d.value("depth"), "4")
        XCTAssertEqual(d.value("rpm"), "")
        d.setValue("", for: "depth")
        XCTAssertNil(d.settings["depth"])
        XCTAssertEqual(d.label, "PIV 18 G R AC (ultrasound-guided)")
        let parsed = try parse("20 rue").device(placedIntraop: true)
        XCTAssertTrue(parsed.placedIntraop)
        XCTAssertEqual(parsed.side, "right")
        XCTAssertFalse(try parse("20 rue").device().placedIntraop, "present on arrival unless said otherwise")
    }

    func testCodableRoundTrip() throws {
        let devices = [
            PatientDevice(kind: .piv, site: "antecubital-right", side: "right", size: "20", placedIntraop: true, offset: CGPoint(x: 0.01, y: -0.02)),
            PatientDevice(kind: .ecmoDrainage, site: "femoral-vein-right", side: "right", size: "25", settings: ["mode": "VV", "flow": "4.5"]),
            PatientDevice(kind: .ett, site: "mouth", size: "7.5", detail: "cuffed", settings: ["depth": "23"], removed: true),
        ]
        let back = try JSONDecoder().decode([PatientDevice].self, from: JSONEncoder().encode(devices))
        XCTAssertEqual(back, devices)
        XCTAssertEqual(back.first?.offset, CGPoint(x: 0.01, y: -0.02))
        XCTAssertEqual(Set(back).count, 3)
        XCTAssertEqual(Set(back + devices).count, 3, "equal devices hash alike")
        for k in DeviceKind.allCases {
            let d = PatientDevice(kind: k, site: "mouth")
            XCTAssertEqual(try JSONDecoder().decode(PatientDevice.self, from: JSONEncoder().encode(d)), d)
        }
    }

    func testTolerantDecoding() throws {
        let decoder = JSONDecoder()
        let json = #"{"kind":"arterial","site":"radial-left","size":20,"settings":{"depth":23,"note":"x","on":true,"bad":[1]},"offset":"no","removed":"yes","extra":1}"#
        let d = try decoder.decode(PatientDevice.self, from: Data(json.utf8))
        XCTAssertEqual(d.kind, .arterial)
        XCTAssertEqual(d.site, "radial-left")
        XCTAssertEqual(d.size, "20", "a number where text belongs is kept as text")
        XCTAssertEqual(d.settings, ["depth": "23", "note": "x", "on": "true"])
        XCTAssertNil(d.offset)
        XCTAssertFalse(d.removed)
        XCTAssertNil(d.side)
        XCTAssertFalse(d.placedIntraop)

        let future = try decoder.decode(PatientDevice.self, from: Data(#"{"kind":"hyperloop","site":"mouth"}"#.utf8))
        XCTAssertEqual(future.kind, .other, "a kind from a newer version")
        XCTAssertEqual(future.site, "mouth")

        let empty = try decoder.decode(PatientDevice.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.kind, .other)
        XCTAssertEqual(empty.site, "")
        XCTAssertEqual(empty.size, "")
        XCTAssertEqual(empty.settings, [:])
        XCTAssertNil(empty.offset)

        let list = try decoder.decode([PatientDevice].self, from: Data(#"[{"kind":"piv"},{"kind":"cvc","settings":"none"}]"#.utf8))
        XCTAssertEqual(list.map(\.kind), [.piv, .cvc])
        XCTAssertEqual(list[1].settings, [:])

        let id = UUID()
        let kept = try decoder.decode(PatientDevice.self, from: Data(#"{"id":"\#(id.uuidString)","kind":"pac","offset":[0.1,0.2]}"#.utf8))
        XCTAssertEqual(kept.id, id)
        XCTAssertEqual(kept.offset, CGPoint(x: 0.1, y: 0.2))
    }

    func testDefaultSites() {
        XCTAssertEqual(PatientDevices.defaultSite(for: .piv, limb: .upper)?.site, "antecubital", "\"20 rue\": the antecubital fossa")
        XCTAssertEqual(PatientDevices.defaultSite(for: .piv, limb: .upper)?.sure, true)
        XCTAssertEqual(PatientDevices.defaultSite(for: .piv, limb: .lower)?.site, "saphenous")
        XCTAssertNil(PatientDevices.defaultSite(for: .piv))
        XCTAssertEqual(PatientDevices.defaultSite(for: .arterial)?.site, "radial")
        XCTAssertEqual(PatientDevices.defaultSite(for: .arterial)?.sure, false)
        XCTAssertEqual(PatientDevices.defaultSite(for: .arterial, limb: .lower)?.site, "femoral-artery")
        XCTAssertEqual(PatientDevices.defaultSite(for: .ett)?.site, "mouth")
        XCTAssertEqual(PatientDevices.defaultSite(for: .ett)?.sure, true)
        XCTAssertEqual(PatientDevices.defaultSite(for: .epidural, level: "T8")?.site, "thoracic-spine")
        XCTAssertEqual(PatientDevices.defaultSite(for: .epidural, level: "L3-4")?.site, "lumbar-spine")
        XCTAssertEqual(PatientDevices.defaultSite(for: .epidural)?.sure, false)
        XCTAssertEqual(PatientDevices.defaultSite(for: .iabp)?.site, "femoral-artery")
        XCTAssertEqual(PatientDevices.defaultSite(for: .intraosseous, limb: .upper)?.site, "humeral-io")
        XCTAssertNil(PatientDevices.defaultSite(for: .block))
        for k in DeviceKind.allCases {
            for limb in [nil, DeviceLimb.upper, .lower] {
                if let s = PatientDevices.defaultSite(for: k, limb: limb)?.site {
                    XCTAssertTrue(DeviceSite.kinds(forBase: s).contains(k), "\(k)'s default \(s) is a catalog site where it is likely")
                }
            }
        }
    }

    func testLegacyLines() {
        let piv = PatientDevice(line: PatientLine(kind: "Peripheral IV", site: "R AC", size: "20"))
        XCTAssertEqual(piv.kind, .piv)
        XCTAssertEqual(piv.site, "antecubital-right")
        XCTAssertEqual(piv.side, "right")
        XCTAssertEqual(piv.size, "20")
        XCTAssertEqual(piv.detail, "")
        XCTAssertEqual(piv.label, "PIV 20 G R AC")
        XCTAssertEqual(PatientDevice(line: PatientLine(kind: "Arterial line", site: "left radial", size: "20")).site, "radial-left")
        let cvl = PatientDevice(line: PatientLine(kind: "Central line", site: "RIJ TLC"))
        XCTAssertEqual(cvl.site, "ij-right")
        XCTAssertEqual(cvl.detail, "triple lumen")
        let vague = PatientDevice(line: PatientLine(kind: "Peripheral IV", site: "somewhere", size: "18"))
        XCTAssertEqual(vague.site, "")
        XCTAssertEqual(vague.detail, "somewhere")
        let other = PatientDevice(line: PatientLine(kind: "Chest tube", site: "", size: "28"))
        XCTAssertEqual(other.kind, .other)
        XCTAssertEqual(other.detail, "Chest tube")
        let line = PatientLine(kind: "PA catheter", site: "R IJ")
        XCTAssertEqual(PatientDevice(line: line).id, line.id)
        XCTAssertEqual(PatientDevice(line: line).label, "PAC via R IJ")
    }
}
