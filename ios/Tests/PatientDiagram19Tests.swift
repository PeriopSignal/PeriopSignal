import XCTest
import CoreGraphics
@testable import PeriopSignal

/// The 1.9 line diagram (Ben's Wanted Changes): the new device kinds and sites, the shorthand that reads them, dialysis
/// access, chest tubes and the pacemaker or ICD drawn from the history pages, limb alerts, and the phase labels.
final class PatientDiagram19Tests: XCTestCase {

    // MARK: Helpers

    private func parse(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> DeviceParse {
        try XCTUnwrap(PatientDevices.parse(text), "no parse for \"\(text)\"", file: file, line: line)
    }

    /// The record after one change, with the device fills run as PatientStore.update does (PatientCrossFill.apply calls them).
    private func change(_ r: PatientRecord, _ edit: (inout PatientRecord) -> Void) -> PatientRecord {
        var after = r
        edit(&after)
        PatientDeviceFills.apply(before: r, after: &after)
        return after
    }

    private func devices(_ r: PatientRecord, _ kind: DeviceKind) -> [PatientDevice] { r.devices.filter { $0.kind == kind } }

    // MARK: Kinds and sites

    func testNewKinds() {
        XCTAssertEqual(DeviceKind.epicardialWires.colorRole, .pacing)
        XCTAssertEqual(DeviceKind.cied.colorRole, .pacing)
        XCTAssertEqual(DeviceKind.avFistula.colorRole, .access)
        XCTAssertEqual(DeviceKind.dialysisCatheter.colorRole, .access)
        XCTAssertEqual(DeviceKind.chestTube.colorRole, .drain)
        XCTAssertEqual([DeviceKind.dialysisCatheter, .chestTube].map(\.sizeUnit), ["Fr", "Fr"])
        XCTAssertEqual([DeviceKind.epicardialWires, .cied, .avFistula].map(\.sizeUnit), ["", "", ""])
        XCTAssertTrue(DeviceKind.epicardialWires.isTemporaryPacing)
        XCTAssertFalse(DeviceKind.cied.isTemporaryPacing, "an implanted generator is not temporary pacing")
        XCTAssertTrue(DeviceKind.avFistula.isDialysisAccess)
        XCTAssertTrue(DeviceKind.dialysisCatheter.isDialysisAccess)
        for k in [DeviceKind.epicardialWires, .cied, .avFistula, .dialysisCatheter, .chestTube] {
            XCTAssertTrue(DeviceKind.more.contains(k), "\(k) is under Other")
            XCTAssertTrue(PatientDevice.lineKinds.contains(k), "\(k) is listed with the lines in the handoff")
            XCTAssertFalse(k.fields.isEmpty)
        }
        XCTAssertEqual(DeviceKind.epicardialWires.settingKeys, ["chambers", "mode", "rate", "output"])
        XCTAssertEqual(DeviceKind.cied.fields.first { $0.id == "detail" }?.choices, ["pacemaker", "ICD", "CRT-P", "CRT-D"])
        XCTAssertEqual(DeviceKind.epicardialWires.fields.first { $0.id == "chambers" }?.choices, ["atrial", "ventricular", "both"])
    }

    func testNewSites() throws {
        let exit = try XCTUnwrap(DeviceSite.site(id: "epicardial-exit"))
        XCTAssertNil(exit.side, "midline")
        XCTAssertEqual(exit.anchor.x, 0.5, accuracy: 1e-9)
        XCTAssertGreaterThan(exit.anchor.y, DeviceSite.site(id: "heart")?.anchor.y ?? 1, "below the heart, under the sternum")
        let rPocket = try XCTUnwrap(DeviceSite.site(id: "generator-right"))
        let lPocket = try XCTUnwrap(DeviceSite.site(id: "generator-left"))
        XCTAssertLessThan(rPocket.anchor.x, 0.5)
        XCTAssertGreaterThan(lPocket.anchor.x, 0.5)
        XCTAssertEqual(rPocket.kinds, [.cied])
        let block = try XCTUnwrap(DeviceSite.site(id: "infraclavicular-right"))
        XCTAssertGreaterThan(rPocket.distance(to: block.anchor), 6, "the pocket is its own place, not the block site")
        XCTAssertFalse(block.kinds.contains(.cied))
        XCTAssertEqual(DeviceSite.site(id: "lateral-chest-left")?.kinds, [.chestTube])
        XCTAssertEqual(DeviceSite.site(id: "lateral-chest-right")?.region, "chest")
        // Fistulas at the wrist, forearm, upper arm; catheters at the IJ, subclavian and femoral vein.
        for base in ["wrist", "forearm", "upper-arm"] {
            XCTAssertTrue(DeviceSite.kinds(forBase: base).contains(.avFistula), base)
            XCTAssertEqual(DeviceSite.site(id: base + "-left")?.region, "arm")
        }
        XCTAssertEqual(DeviceSite.site(id: "thigh-right")?.region, "leg")
        for base in ["ij", "subclavian", "femoral-vein"] {
            XCTAssertTrue(DeviceSite.kinds(forBase: base).contains(.dialysisCatheter), base)
        }
        // A tap near the forearm offers a fistula after the IV.
        let forearm = try XCTUnwrap(DeviceSite.site(id: "forearm-right"))
        XCTAssertEqual(DeviceSite.likelyKinds(at: forearm), [.piv, .avFistula, .other])
        XCTAssertTrue(DeviceSite.options(near: forearm.anchor).contains { $0.kind == .avFistula && $0.site.id == "forearm-right" })
    }

    // MARK: Shorthand

    func testShorthand() throws {
        let wires = try parse("epicardial wires A+V")
        XCTAssertEqual(wires.kind, .epicardialWires)
        XCTAssertEqual(wires.site, "epicardial-exit")
        XCTAssertEqual(wires.settings, ["chambers": "both"])
        XCTAssertEqual(wires.confidence, 1, accuracy: 0.001)
        XCTAssertEqual(wires.device().label, "Epicardial pacing wires (atrial + ventricular)")
        XCTAssertEqual(try parse("epicardial pacing wires atrial").settings["chambers"], "atrial")
        XCTAssertEqual(try parse("V wires").settings["chambers"], "ventricular")
        XCTAssertEqual(try parse("temp wires A and V").settings["chambers"], "both")
        let paced = try parse("epicardial wires atrial and ventricular DDD 80 bpm 5 mA")
        XCTAssertEqual(paced.settings, ["chambers": "both", "mode": "DDD", "rate": "80", "output": "5"])
        XCTAssertEqual(paced.device().label, "Epicardial pacing wires (atrial + ventricular, DDD, 80 bpm, 5 mA)")
        XCTAssertEqual(try parse("pacing wires").settings, [:], "the chambers are not guessed")
        XCTAssertEqual(try parse("pacing wires").confidence, 0.85, accuracy: 0.001)

        let avf = try parse("AVF L forearm")
        XCTAssertEqual(avf.kind, .avFistula)
        XCTAssertEqual(avf.site, "forearm-left")
        XCTAssertEqual(avf.device().label, "AV fistula L forearm")
        let bc = try parse("brachiocephalic fistula right")
        XCTAssertEqual(bc.kind, .avFistula)
        XCTAssertEqual(bc.site, "upper-arm-right")
        XCTAssertEqual(bc.detail, "brachiocephalic")
        XCTAssertEqual(try parse("L radiocephalic AVF").site, "wrist-left")
        XCTAssertEqual(try parse("AV graft R upper arm").device().label, "AV graft R upper arm")
        XCTAssertEqual(try parse("AVF LUE").site, "forearm-left", "an arm alone is the forearm, with a lower confidence")
        XCTAssertLessThan(try parse("AVF LUE").confidence, 1)
        let nosid = try parse("AV fistula forearm")
        XCTAssertNil(nosid.site, "no side: ask")
        XCTAssertEqual(nosid.baseSite, "forearm")
        XCTAssertEqual(nosid.alternatives.compactMap(\.site), ["forearm-right", "forearm-left"])

        let hd = try parse("HD cath R IJ")
        XCTAssertEqual(hd.kind, .dialysisCatheter)
        XCTAssertEqual(hd.site, "ij-right")
        XCTAssertEqual(hd.device().label, "HD catheter R IJ")
        let tun = try parse("14.5 Fr tunneled HD catheter left femoral")
        XCTAssertEqual(tun.kind, .dialysisCatheter)
        XCTAssertEqual([tun.size, tun.site ?? "", tun.detail], ["14.5", "femoral-vein-left", "tunneled"])
        XCTAssertEqual(try parse("RIJ permcath").detail, "tunneled")
        XCTAssertEqual(try parse("RIJ permcath").kind, .dialysisCatheter)
        XCTAssertEqual(try parse("L subclavian trialysis").detail, "Trialysis")
        XCTAssertEqual(try parse("RIJ TLC").kind, .cvc, "a triple-lumen central line is still a CVL")

        let ct = try parse("R chest tube 28 Fr")
        XCTAssertEqual(ct.kind, .chestTube)
        XCTAssertEqual([ct.size, ct.site ?? "", ct.side ?? ""], ["28", "lateral-chest-right", "right"])
        XCTAssertEqual(ct.device().label, "R chest tube 28 Fr")
        XCTAssertEqual(try parse("left pigtail chest tube 14 Fr").detail, "pigtail")
        XCTAssertEqual(try parse("chest tube").alternatives.compactMap(\.site), ["lateral-chest-right", "lateral-chest-left"])

        let ppm = try parse("PPM left chest")
        XCTAssertEqual(ppm.kind, .cied)
        XCTAssertEqual([ppm.site ?? "", ppm.detail], ["generator-left", "pacemaker"])
        XCTAssertEqual(ppm.device().label, "Pacemaker L pectoral")
        XCTAssertEqual(try parse("ICD right infraclavicular").site, "generator-right", "infraclavicular means the pocket for a generator")
        XCTAssertEqual(try parse("CRT-D left pectoral").detail, "CRT-D")
        XCTAssertEqual(try parse("biv ICD L chest").kind, .cied)
        XCTAssertEqual(try parse("pacemaker").alternatives.compactMap(\.site), ["generator-left", "generator-right"], "left first for a generator")
        // The infraclavicular block is untouched.
        let block = try parse("R infraclavicular block")
        XCTAssertEqual(block.kind, .block)
        XCTAssertEqual(block.site, "infraclavicular-right")
    }

    func testLabels() {
        func d(_ k: DeviceKind, _ site: String = "", size: String = "", detail: String = "", settings: [String: String] = [:]) -> PatientDevice {
            PatientDevice(kind: k, site: site, size: size, detail: detail, settings: settings)
        }
        XCTAssertEqual(d(.cied, "generator-left", detail: "ICD").label, "ICD L pectoral")
        XCTAssertEqual(d(.cied, "generator-right", detail: "CRT-P", settings: ["model": "dual chamber"]).label, "CRT-P R pectoral (dual chamber)")
        XCTAssertEqual(d(.cied).label, "Pacemaker/ICD")
        XCTAssertEqual(d(.avFistula, "wrist-left", detail: "radiocephalic").label, "AV fistula L wrist (radiocephalic)")
        XCTAssertEqual(d(.avFistula, "upper-arm-right", detail: "AV graft").label, "AV graft R upper arm")
        XCTAssertEqual(d(.avFistula, detail: "forearm").label, "AV fistula (forearm)", "unplaced: the typed words")
        XCTAssertEqual(d(.dialysisCatheter, "ij-right", size: "14", detail: "tunneled").label, "HD catheter 14 Fr R IJ (tunneled)")
        XCTAssertEqual(d(.chestTube, "lateral-chest-left", size: "24").label, "L chest tube 24 Fr")
        XCTAssertEqual(d(.chestTube).label, "Chest tube")
        XCTAssertEqual(d(.epicardialWires, "epicardial-exit", settings: ["chambers": "ventricular", "mode": "VVI", "rate": "70"]).label,
                       "Epicardial pacing wires (ventricular, VVI, 70 bpm)")
        var removed = d(.chestTube, "lateral-chest-left")
        removed.removed = true
        XCTAssertEqual(removed.label, "L chest tube (removed)")
        XCTAssertEqual(PatientDiagramModel.tag(d(.epicardialWires, "epicardial-exit", settings: ["chambers": "both"])), "Epi wires A+V")
        XCTAssertEqual(PatientDiagramModel.tag(d(.cied, "generator-left", detail: "pacemaker")), "PPM")
        XCTAssertEqual(PatientDiagramModel.tag(d(.cied, "generator-left", detail: "CRT-D")), "CRT-D")
        XCTAssertEqual(PatientDiagramModel.tag(d(.avFistula, "wrist-left")), "AVF")
        XCTAssertEqual(PatientDiagramModel.tag(d(.chestTube, "lateral-chest-left", size: "28")), "Chest tube 28Fr")
    }

    func testPhaseLabels() {
        let pre = PatientDevice(kind: .cvc, site: "ij-right", side: "right")
        var intra = PatientDevice(kind: .piv, site: "forearm-left", side: "left", size: "20")
        intra.placedIntraop = true
        XCTAssertEqual(PatientDevices.labelsWithPhase([pre, intra]), ["CVL R IJ (Pre)", "PIV 20 G L forearm (Intra)"])
        var gone = pre
        gone.removed = true
        XCTAssertEqual(PatientDevices.labelsWithPhase([gone, intra]), ["PIV 20 G L forearm (Intra)"])
        XCTAssertEqual(PatientDevices.labelsWithPhase([gone], includeRemoved: true), ["CVL R IJ (removed) (Pre)"])
        // An ECMO circuit is one line.
        let drain = PatientDevice(kind: .ecmoDrainage, site: "femoral-vein-right", size: "25", settings: ["mode": "VV"])
        var back = PatientDevice(kind: .ecmoReturn, site: "ij-right", size: "21")
        XCTAssertEqual(PatientDevices.labelsWithPhase([drain, back]).count, 1)
        XCTAssertTrue(PatientDevices.labelsWithPhase([drain, back]).first?.hasSuffix("(Pre)") ?? false)
        back.placedIntraop = true
        XCTAssertTrue(PatientDevices.labelsWithPhase([drain, back]).first?.hasSuffix("(Pre and Intra)") ?? false)
        XCTAssertEqual(PatientDevices.phaseLabels([pre, intra]).map(\.placedIntraop), [false, true])
    }

    func testTemporaryPacing() {
        let wires = PatientDevice(kind: .epicardialWires, site: "epicardial-exit", settings: ["chambers": "both"])
        var r = PatientRecord()
        XCTAssertFalse(r.hasTemporaryPacingWires)
        r.devices = [PatientDevice(kind: .cied, site: "generator-left", detail: "pacemaker")]
        XCTAssertFalse(r.hasTemporaryPacingWires)
        r.devices.append(wires)
        XCTAssertTrue(r.hasTemporaryPacingWires)
        XCTAssertTrue(PatientDevices.temporaryPacingInPlace(r.devices))
        r.devices[1].removed = true
        XCTAssertFalse(r.hasTemporaryPacingWires, "wires pulled are no longer in place")
    }

    // MARK: Old saved devices

    func testOldDevicesStillLoad() throws {
        let decoder = JSONDecoder()
        // A 1.8 chest tube entered as "other", and a kind this version does not know.
        let old = try decoder.decode(PatientDevice.self, from: Data(#"{"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","kind":"other","site":"","detail":"chest tube","size":"28","placedIntraop":true}"#.utf8))
        XCTAssertEqual(old.kind, .other)
        XCTAssertEqual(old.label, "chest tube 28")
        let unknown = try decoder.decode(PatientDevice.self, from: Data(#"{"kind":"holographicShunt","site":"forearm-left"}"#.utf8))
        XCTAssertEqual(unknown.kind, .other)
        // The new kinds round-trip.
        let fresh = [PatientDevice(kind: .avFistula, site: "wrist-left", side: "left", detail: "radiocephalic"),
                     PatientDevice(kind: .epicardialWires, site: "epicardial-exit", settings: ["chambers": "both", "mode": "DDD"])]
        XCTAssertEqual(try decoder.decode([PatientDevice].self, from: JSONEncoder().encode(fresh)), fresh)
        // A record saved before 1.9 has no limb alerts or fills and opens with none.
        let record = try decoder.decode(PatientRecord.self, from: Data(#"{"devices":[{"kind":"piv","site":"forearm-left","size":"20"}]}"#.utf8))
        XCTAssertEqual(record.devices.count, 1)
        XCTAssertTrue(record.limbAlerts.isEmpty)
        XCTAssertTrue(record.fills.devices.isEmpty)
        XCTAssertNil(PatientDeviceFills.limbAlertText(record))
    }

    // MARK: Typed locations

    func testReadingFistulaLocations() {
        func read(_ text: String) -> PatientDeviceFills.AccessSite { PatientDeviceFills.readAccessSite(text, kind: .avFistula) }
        let table: [(String, String, String?, String)] = [
            ("left forearm", "forearm-left", "left", ""),
            ("Left Forearm", "forearm-left", "left", ""),
            ("LUE", "forearm-left", "left", ""),
            ("RUE", "forearm-right", "right", ""),
            ("L upper arm", "upper-arm-left", "left", ""),
            ("R arm", "forearm-right", "right", ""),
            ("brachiocephalic L", "upper-arm-left", "left", "brachiocephalic"),
            ("brachio-cephalic right", "upper-arm-right", "right", "brachiocephalic"),
            ("brachiobasilic L", "upper-arm-left", "left", "brachiobasilic"),
            ("radiocephalic right", "wrist-right", "right", "radiocephalic"),
            ("radio-cephalic AVF, left", "wrist-left", "left", "radiocephalic"),
            ("left wrist", "wrist-left", "left", ""),
            ("right antecubital", "upper-arm-right", "right", ""),
            ("right thigh graft", "thigh-right", "right", "AV graft"),
            ("LLE", "thigh-left", "left", ""),
            ("left forearm since 2022", "forearm-left", "left", "since, 2022"),
            ("L upper extremity", "forearm-left", "left", ""),
        ]
        for (text, site, side, detail) in table {
            let r = read(text)
            XCTAssertEqual(r.site, site, text)
            XCTAssertEqual(r.side, side, text)
            XCTAssertEqual(r.detail, detail, text)
        }
        // Unreadable: no place on the figure, the typed words kept.
        for text in ["forearm", "AV graft", "somewhere", "R IJ", "tunneled"] {
            let r = read(text)
            XCTAssertEqual(r.site, "", text)
            XCTAssertEqual(r.detail, text, text)
        }
        XCTAssertEqual(read("R IJ").side, "right", "the side is kept when the place is not readable")
        XCTAssertEqual(read(""), PatientDeviceFills.AccessSite(site: "", side: nil, detail: ""))
        XCTAssertEqual(read("  "), PatientDeviceFills.AccessSite(site: "", side: nil, detail: ""))
    }

    func testReadingCatheterLocations() {
        func read(_ text: String) -> PatientDeviceFills.AccessSite { PatientDeviceFills.readAccessSite(text, kind: .dialysisCatheter) }
        let table: [(String, String, String?, String)] = [
            ("right IJ tunneled", "ij-right", "right", "tunneled"),
            ("R internal jugular", "ij-right", "right", ""),
            ("RIJ permcath", "ij-right", "right", "tunneled"),
            ("LIJ", "ij-left", "left", ""),
            ("left IJ non-tunneled", "ij-left", "left", "non-tunneled"),
            ("R femoral", "femoral-vein-right", "right", ""),
            ("temp R groin", "femoral-vein-right", "right", "non-tunneled"),
            ("left subclavian", "subclavian-left", "left", ""),
            ("L SC tunneled", "subclavian-left", "left", "tunneled"),
            ("right IJ tunneled, placed 2024", "ij-right", "right", "tunneled, placed, 2024"),
        ]
        for (text, site, side, detail) in table {
            let r = read(text)
            XCTAssertEqual(r.site, site, text)
            XCTAssertEqual(r.side, side, text)
            XCTAssertEqual(r.detail, detail, text)
        }
        // An arm is no place for a catheter; a vein with no side cannot be drawn.
        XCTAssertEqual(read("left forearm").site, "")
        XCTAssertEqual(read("IJ").site, "")
        XCTAssertEqual(read("IJ").detail, "IJ")
        XCTAssertEqual(read("R chest tunneled"), PatientDeviceFills.AccessSite(site: "", side: "right", detail: "R chest tunneled"))
    }

    // MARK: Fills

    private func renal(_ fistula: String? = nil, catheter: String? = nil) -> PatientRecord {
        var r = PatientRecord()
        r.problems.insert("esrd-dialysis")
        if let fistula { r.hx.dialysisAccess.insert("fistula"); r.hx.fistulaSite = fistula }
        if let catheter { r.hx.dialysisAccess.insert("catheter"); r.hx.dialysisCatheterSite = catheter }
        return r
    }

    func testFistulaAndCatheterAreAdded() {
        let r = change(PatientRecord()) { $0 = renal("left forearm", catheter: "right IJ tunneled") }
        XCTAssertEqual(r.devices.count, 2)
        let f = devices(r, .avFistula)[0]
        XCTAssertEqual([f.site, f.side ?? "", f.detail], ["forearm-left", "left", ""])
        XCTAssertFalse(f.placedIntraop, "an arrival device")
        let c = devices(r, .dialysisCatheter)[0]
        XCTAssertEqual([c.site, c.side ?? "", c.detail], ["ij-right", "right", "tunneled"])
        XCTAssertFalse(c.placedIntraop)
        XCTAssertEqual(r.fills.devices["hd-fistula"], f.id)
        XCTAssertEqual(r.fills.devices["hd-catheter"], c.id)
        // Nothing more on the next, unrelated change.
        let again = change(r) { $0.weightKg = 80 }
        XCTAssertEqual(again.devices, r.devices)
        // The device is on the arrival picture and in the handoff's lines.
        XCTAssertEqual(PatientSummary.arrivalDeviceLines(r).first?.text, "AV fistula L forearm; HD catheter R IJ (tunneled)")
    }

    func testAccessWithoutALocationIsOnTheListNotTheFigure() {
        let none = change(PatientRecord()) { $0 = renal("") }
        let f = devices(none, .avFistula)[0]
        XCTAssertEqual(f.site, "", "no place on the figure yet")
        XCTAssertEqual(f.detail, "")
        let unreadable = change(PatientRecord()) { $0 = renal("somewhere on the arm") }
        let u = devices(unreadable, .avFistula)[0]
        XCTAssertEqual(u.site, "")
        XCTAssertEqual(u.detail, "somewhere on the arm", "the typed words are kept")
        XCTAssertNil(u.position)
        // Typing a readable place later puts it on the figure; its detail follows.
        let fixed = change(unreadable) { $0.hx.fistulaSite = "left wrist" }
        XCTAssertEqual(devices(fixed, .avFistula).count, 1)
        XCTAssertEqual(devices(fixed, .avFistula)[0].id, u.id)
        XCTAssertEqual(devices(fixed, .avFistula)[0].site, "wrist-left")
        XCTAssertEqual(devices(fixed, .avFistula)[0].detail, "")
    }

    func testEditingTheTextMovesTheDevice() {
        var r = change(PatientRecord()) { $0 = renal("left forearm") }
        let id = devices(r, .avFistula)[0].id
        r.devices[0].offset = CGPoint(x: 0.02, y: 0.01)
        r = change(r) { $0.hx.fistulaSite = "right upper arm, brachiocephalic" }
        XCTAssertEqual(devices(r, .avFistula).count, 1)
        let d = devices(r, .avFistula)[0]
        XCTAssertEqual(d.id, id)
        XCTAssertEqual([d.site, d.side ?? "", d.detail], ["upper-arm-right", "right", "brachiocephalic"])
        XCTAssertNil(d.offset, "a new site starts at its anchor")
        XCTAssertEqual(r.fills.devices["hd-fistula"], id)
        // Moved by the user to another site by hand: the text no longer moves it.
        r.devices[0].site = "wrist-right"
        r = change(r) { $0.hx.fistulaSite = "left forearm" }
        XCTAssertEqual(devices(r, .avFistula)[0].site, "wrist-right")
    }

    func testClearingTheSourceTakesTheDeviceOff() {
        var r = change(PatientRecord()) { $0 = renal("left forearm", catheter: "R IJ") }
        r = change(r) { $0.hx.dialysisAccess.remove("fistula") }
        XCTAssertTrue(devices(r, .avFistula).isEmpty)
        XCTAssertNil(r.fills.devices["hd-fistula"])
        XCTAssertEqual(devices(r, .dialysisCatheter).count, 1, "the catheter stays while its source holds")
        // The whole Hemodialysis item cleared (its reset empties the access).
        r = change(r) { $0.problems.remove("esrd-dialysis"); $0.hx.dialysisAccess = []; $0.hx.dialysisCatheterSite = "" }
        XCTAssertTrue(r.devices.isEmpty)
        XCTAssertTrue(r.fills.devices.isEmpty)
        // Back again: added again.
        r = change(r) { $0.hx.dialysisAccess = ["fistula"]; $0.hx.fistulaSite = "left forearm" }
        XCTAssertEqual(devices(r, .avFistula).count, 1)
    }

    func testADeviceTheUserDeletedIsNotAddedBack() {
        var r = change(PatientRecord()) { $0 = renal("left forearm") }
        let id = devices(r, .avFistula)[0].id
        r = change(r) { $0.devices.removeAll() }
        XCTAssertTrue(r.devices.isEmpty)
        XCTAssertEqual(r.fills.devices["hd-fistula"], id, "still remembered, so it is not added again")
        r = change(r) { $0.hx.fistulaSite = "left wrist" }
        XCTAssertTrue(r.devices.isEmpty, "editing the text does not bring it back")
        r = change(r) { $0.weightKg = 70 }
        XCTAssertTrue(r.devices.isEmpty)
        // The source goes and comes back: a device again.
        r = change(r) { $0.hx.dialysisAccess = [] }
        XCTAssertNil(r.fills.devices["hd-fistula"])
        XCTAssertTrue(r.devices.isEmpty)
        r = change(r) { $0.hx.dialysisAccess = ["fistula"] }
        XCTAssertEqual(devices(r, .avFistula).count, 1)
        XCTAssertNotEqual(devices(r, .avFistula)[0].id, id)
    }

    func testADeviceTheUserMadeTheirOwnIsLeftAlone() {
        // Drawn by hand first: the source adds nothing and takes nothing.
        var mine = PatientRecord()
        mine.devices = [PatientDevice(kind: .avFistula, site: "forearm-left", side: "left", size: "")]
        var r = change(mine) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["fistula"]; $0.hx.fistulaSite = "left forearm" }
        XCTAssertEqual(r.devices.count, 1)
        XCTAssertTrue(r.fills.devices.isEmpty)
        r = change(r) { $0.hx.dialysisAccess = [] }
        XCTAssertEqual(r.devices.count, 1, "theirs stays")
        // A fill's device the user then worked on (a size, a note, marked removed) stays when the source goes.
        var f = change(PatientRecord()) { $0 = renal(nil, catheter: "R IJ") }
        f.devices[0].size = "14"
        f = change(f) { $0.hx.dialysisAccess = [] }
        XCTAssertEqual(f.devices.count, 1)
        XCTAssertEqual(f.devices[0].size, "14")
        XCTAssertTrue(f.fills.devices.isEmpty, "now it is theirs")
        // A catheter marked removed stays on the record as removed, and is not added again.
        var g = change(PatientRecord()) { $0 = renal(nil, catheter: "R IJ") }
        g.devices[0].removed = true
        g = change(g) { $0.hx.dialysisCatheterSite = "R IJ tunneled" }
        XCTAssertEqual(g.devices.count, 1)
        XCTAssertTrue(g.devices[0].removed)
    }

    func testChestTubes() {
        var r = PatientRecord()
        r = change(r) { $0.hx.chestTube = true }
        XCTAssertTrue(r.devices.isEmpty, "yes, but no side yet")
        r = change(r) { $0.hx.chestTubeSides = ["left"] }
        XCTAssertEqual(r.devices.map(\.site), ["lateral-chest-left"])
        XCTAssertEqual(r.devices[0].kind, .chestTube)
        XCTAssertFalse(r.devices[0].placedIntraop)
        XCTAssertEqual(r.fills.devices["chest-tube-left"], r.devices[0].id)
        r = change(r) { $0.hx.chestTubeSides = ["left", "right"] }
        XCTAssertEqual(Set(r.devices.map(\.site)), ["lateral-chest-left", "lateral-chest-right"])
        XCTAssertEqual(Set(r.fills.devices.keys), ["chest-tube-left", "chest-tube-right"])
        let leftID = r.fills.devices["chest-tube-left"]
        r = change(r) { $0.hx.chestTubeSides = ["left"] }
        XCTAssertEqual(r.devices.map(\.site), ["lateral-chest-left"])
        XCTAssertEqual(r.devices[0].id, leftID)
        r = change(r) { $0.hx.chestTube = false }
        XCTAssertTrue(r.devices.isEmpty)
        XCTAssertTrue(r.fills.devices.isEmpty)
        // The Pleural item reset.
        r = change(r) { $0.hx.chestTube = true; $0.hx.chestTubeSides = ["right"] }
        r = change(r) { $0.hx.chestTube = nil; $0.hx.chestTubeSides = [] }
        XCTAssertTrue(r.devices.isEmpty)
    }

    func testPacemakerAndICDGenerator() {
        var r = PatientRecord()
        r = change(r) { $0.problems.insert("pacemaker") }
        XCTAssertEqual(r.devices.count, 1)
        XCTAssertEqual(r.devices[0].kind, .cied)
        XCTAssertEqual(r.devices[0].site, "", "no side recorded: listed, not drawn")
        XCTAssertEqual(r.devices[0].detail, "pacemaker")
        XCTAssertFalse(r.devices[0].placedIntraop)
        let id = r.devices[0].id
        XCTAssertEqual(r.fills.devices["cied"], id)
        r = change(r) { $0.hx.ciedSide = "left" }
        XCTAssertEqual(r.devices[0].site, "generator-left")
        XCTAssertEqual(r.devices[0].side, "left")
        XCTAssertEqual(r.devices[0].id, id)
        r = change(r) { $0.problems.insert("icd") }
        XCTAssertEqual(r.devices[0].detail, "ICD")
        r = change(r) { $0.hx.deviceDetails = "CRT-D, pacer dependent" }
        XCTAssertEqual(r.devices[0].detail, "CRT-D")
        r = change(r) { $0.problems.remove("icd"); $0.hx.deviceDetails = "biventricular" }
        XCTAssertEqual(r.devices[0].detail, "CRT-P")
        r = change(r) { $0.hx.ciedSide = "right" }
        XCTAssertEqual(r.devices[0].site, "generator-right")
        XCTAssertEqual(r.devices.count, 1)
        r = change(r) { $0.problems.remove("pacemaker") }
        XCTAssertTrue(r.devices.isEmpty)
        XCTAssertNil(r.fills.devices["cied"])
        // One drawn by hand is not doubled.
        var mine = PatientRecord()
        mine.devices = [PatientDevice(kind: .cied, site: "generator-left", side: "left", detail: "ICD")]
        mine = change(mine) { $0.problems.insert("icd"); $0.hx.ciedSide = "left" }
        XCTAssertEqual(mine.devices.count, 1)
        XCTAssertTrue(mine.fills.devices.isEmpty)
        XCTAssertEqual(PatientDeviceFills.ciedType(change(PatientRecord()) { $0.problems.insert("icd") }), "ICD")
    }

    func testFillsDoNotFireOnOtherChanges() {
        var r = PatientRecord()
        r.problems = ["htn", "dm", "copd"]
        let after = change(r) { $0.problems.insert("cad") }
        XCTAssertTrue(after.devices.isEmpty)
        XCTAssertTrue(after.fills.devices.isEmpty)
    }

    // MARK: Limb alerts

    private func fistula(_ site: String, side: String? = nil, detail: String = "") -> PatientDevice {
        PatientDevice(kind: .avFistula, site: site, side: side, detail: detail)
    }

    func testAutomaticLimbAlert() {
        var r = PatientRecord()
        XCTAssertTrue(PatientDeviceFills.limbAlerts(r).isEmpty)
        r.devices = [fistula("forearm-left", side: "left")]
        let alerts = PatientDeviceFills.limbAlerts(r)
        XCTAssertEqual(alerts.map(\.limb), ["arm-left"])
        XCTAssertEqual(alerts.map(\.reason), ["AV fistula"])
        XCTAssertEqual(alerts.map(\.automatic), [true])
        XCTAssertTrue(r.limbAlerts.isEmpty, "computed, not stored")
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), "L arm — AV fistula")
        // A graft says so; a thigh access is the leg; a second on the same arm says nothing more.
        r.devices = [fistula("upper-arm-right", side: "right", detail: "AV graft"), fistula("thigh-left", side: "left"),
                     fistula("wrist-right", side: "right", detail: "radiocephalic")]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), "R arm — AV graft, AV fistula; L leg — AV fistula")
        // Removed, or no side: no alert. Without a place but with a side it is taken to be the arm.
        var gone = fistula("forearm-left", side: "left")
        gone.removed = true
        r.devices = [gone, fistula("", detail: "somewhere")]
        XCTAssertTrue(PatientDeviceFills.limbAlerts(r).isEmpty)
        r.devices = [fistula("", side: "left", detail: "L")]
        XCTAssertEqual(PatientDeviceFills.limbAlerts(r).map(\.limb), ["arm-left"])
        // A dialysis catheter or any other device does not mark a limb.
        r.devices = [PatientDevice(kind: .dialysisCatheter, site: "ij-right", side: "right"), PatientDevice(kind: .piv, site: "forearm-left", side: "left")]
        XCTAssertTrue(PatientDeviceFills.limbAlerts(r).isEmpty)
        // The arrival picture leaves out one made in the room.
        var made = fistula("forearm-left", side: "left")
        made.placedIntraop = true
        r.devices = [made]
        XCTAssertEqual(PatientDeviceFills.limbAlerts(r).count, 1)
        XCTAssertTrue(PatientDeviceFills.limbAlerts(r, arrivalOnly: true).isEmpty)
    }

    func testUserLimbAlerts() {
        var r = PatientRecord()
        r.devices = [fistula("forearm-left", side: "left")]
        r.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "prior axillary lymph node dissection")]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), "L arm — AV fistula; R arm — prior axillary lymph node dissection",
                       "the limbs with a fistula first, the reason in a sentence")
        // Capital as typed, lower case inside the sentence unless it is an acronym.
        r.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "Prior axillary lymph node dissection"),
                        PatientLimbAlert(limb: "leg-left", reason: "AV graft revision")]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), "L arm — AV fistula; R arm — prior axillary lymph node dissection; L leg — AV graft revision")
        // Two reasons on one limb; blank ones are not alerts.
        r.limbAlerts = [PatientLimbAlert(limb: "arm-left", reason: "Lymphedema"), PatientLimbAlert(limb: "arm-left", reason: "  "),
                        PatientLimbAlert(limb: "arm-left", reason: "lymphedema")]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), "L arm — AV fistula, lymphedema")
        // A limb that is not one of the four is ignored.
        r.limbAlerts = [PatientLimbAlert(limb: "head", reason: "x")]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), "L arm — AV fistula")
        // The groups: names and the mark's place.
        r.limbAlerts = [PatientLimbAlert(limb: "leg-right", reason: "DVT")]
        let groups = PatientDeviceFills.limbAlertGroups(r)
        XCTAssertEqual(groups.map(\.limb), ["arm-left", "leg-right"])
        XCTAssertEqual(groups.map(\.name), ["L arm", "R leg"])
        XCTAssertEqual(PatientDeviceFills.limbWords("leg-right"), "right leg")
        for limb in PatientDeviceFills.limbOrder {
            let at = PatientDeviceFills.limbAnchor(limb)
            XCTAssertNotNil(at, limb)
            XCTAssertEqual(limb.hasSuffix("right"), (at?.x ?? 200) < 100, "the patient's right is on the viewer's left: \(limb)")
        }
    }

    func testLimbAlertDoesNotRepeatTheFistulaOrTheHarvest() {
        var r = PatientRecord()
        r.devices = [fistula("forearm-left", side: "left")]
        // Typed in again by the user: the same arm, the same words.
        r.limbAlerts = [PatientLimbAlert(limb: "arm-left", reason: "AV fistula"), PatientLimbAlert(limb: "arm-left", reason: "Dialysis fistula, do not use"),
                        PatientLimbAlert(limb: "arm-left", reason: "graft")]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), "L arm — AV fistula")
        // On the other arm, "AV fistula" typed by the user is a reason of its own.
        r.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "AV fistula")]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), "L arm — AV fistula; R arm — AV fistula")

        // A planned radial harvest is announced by the Arms line, not again as a limb alert.
        var h = PatientRecord()
        h.radial.harvest = "left"
        h.limbAlerts = [PatientLimbAlert(limb: "arm-left", reason: "Planned radial harvest")]
        XCTAssertTrue(PatientDeviceFills.limbAlerts(h).isEmpty)
        XCTAssertTrue(PatientSummary.limbAlertLines(h).isEmpty)
        let arms = PatientSummary.harvestLines(h)
        XCTAssertFalse(arms.isEmpty, "the Arms line stays")
        XCTAssertEqual(arms.first?.label, "Arms")
        let text = HandoffWriter.text(h)
        XCTAssertFalse(text.contains("Limb alert"), text)
        XCTAssertTrue(text.contains("Arms: "), text)
        // A different reason on the harvest arm is kept, in its own line.
        h.limbAlerts = [PatientLimbAlert(limb: "arm-left", reason: "Lymphedema"), PatientLimbAlert(limb: "arm-right", reason: "Planned radial harvest")]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(h), "R arm — planned radial harvest; L arm — lymphedema",
                       "a harvest is only dropped on the arm that is planned for it")
        XCTAssertEqual(PatientSummary.limbAlertLines(h).count, 1)
    }

    func testLimbAlertInTheHandoffText() {
        var r = PatientRecord()
        r.ageYears = 60; r.sex = .female
        r.devices = [fistula("forearm-left", side: "left")]
        r.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "prior axillary lymph node dissection")]
        let line = "Limb alert: L arm — AV fistula; R arm — prior axillary lymph node dissection"
        let full = HandoffWriter.text(r)
        XCTAssertTrue(full.contains(line), full)
        XCTAssertEqual(full.components(separatedBy: "Limb alert").count, 2, "once")
        XCTAssertTrue(full.contains("LINES & DEVICES"), full)
        XCTAssertTrue(full.contains("Line: AV fistula L forearm"), full)
        XCTAssertTrue(HandoffWriter.shortText(r).contains(line), HandoffWriter.shortText(r))
        // On the Lines card of the intraoperative tab, once.
        let card = PatientSummary.intraopPartLines(r, "lines").map { ($0.label ?? "") + ": " + $0.text }
        XCTAssertEqual(card.filter { $0.hasPrefix("Limb alert") }.count, 1, card.joined(separator: "\n"))
        // Nothing to say: no line.
        XCTAssertFalse(HandoffWriter.text(PatientRecord()).contains("Limb alert"))
        XCTAssertFalse(HandoffWriter.shortText(PatientRecord()).contains("Limb alert"))
    }

    // MARK: The picture

    func testDiagramModelDrawsTheNewDevicesAndAlerts() {
        var r = PatientRecord()
        r.devices = [PatientDevice(kind: .epicardialWires, site: "epicardial-exit", settings: ["chambers": "both"]),
                     PatientDevice(kind: .cied, site: "generator-left", side: "left", detail: "ICD"),
                     fistula("forearm-left", side: "left"),
                     PatientDevice(kind: .dialysisCatheter, site: "ij-right", side: "right", size: "14", detail: "tunneled"),
                     PatientDevice(kind: .chestTube, site: "lateral-chest-right", side: "right", size: "28"),
                     PatientDevice(kind: .avFistula, site: "", detail: "unplaced")]
        r.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "Prior axillary lymph node dissection")]
        let m = PatientDiagramModel.items(r, phase: .all)
        let ids = Set(m.items.map(\.id))
        for d in r.devices where d.position != nil { XCTAssertTrue(ids.contains(d.id.uuidString), d.label) }
        XCTAssertFalse(ids.contains(r.devices[5].id.uuidString), "no place on the figure: not drawn")
        // Both chambers: a second wire to the atrium.
        XCTAssertTrue(ids.contains(r.devices[0].id.uuidString + "-atrial"))
        XCTAssertEqual(m.items.first { $0.id == r.devices[1].id.uuidString }?.marker, .generator)
        // The limb alerts: the fistula's arm and the user's.
        let alerts = m.items.filter { $0.marker == .alert }
        XCTAssertEqual(Set(alerts.map(\.id)), ["limb-alert-arm-left", "limb-alert-arm-right"])
        XCTAssertTrue(alerts.allSatisfy { $0.label.isEmpty }, "the mark has no label in the column")
        XCTAssertEqual(alerts.first { $0.id == "limb-alert-arm-right" }?.spoken, "Limb alert, right arm: prior axillary lymph node dissection")
        XCTAssertLessThan(alerts.first { $0.id == "limb-alert-arm-right" }?.anchor.x ?? 200, 100)
        // Labels fit the column and never repeat the alert text.
        for item in m.items where !item.label.isEmpty { XCTAssertLessThanOrEqual(item.label.count, 15, item.label) }
        // Alerts alone draw a figure (the card and the shared picture show it).
        var only = PatientRecord()
        only.limbAlerts = [PatientLimbAlert(limb: "leg-left", reason: "DVT")]
        XCTAssertEqual(PatientDiagramModel.items(only, phase: .preop).items.map(\.id), ["limb-alert-leg-left"])
        // The arrival picture leaves out a fistula made in the room.
        var made = fistula("forearm-left", side: "left")
        made.placedIntraop = true
        var room = PatientRecord()
        room.devices = [made]
        XCTAssertTrue(PatientDiagramModel.items(room, phase: .preop).items.isEmpty)
        XCTAssertEqual(PatientDiagramModel.items(room, phase: .all).items.filter { $0.marker == .alert }.count, 1)
    }

    private func figure() throws -> RegionalFigure {
        let json = """
        {"figure": {"box": [200, 420], "outline": "M10 10 L190 10 L190 410 L10 410 Z", "head": {"cx": 100, "cy": 30, "rx": 17, "ry": 22}, "landmarks": {},
          "regions": [{"id": "chest", "name": "Anterior chest and breast", "views": {}}]},
         "blocks": [], "map": {"chest": {"blocks": []}}}
        """
        return try JSONDecoder().decode(RegionalData.self, from: Data(json.utf8)).figure
    }

    /// The shared picture is made when only a limb alert is drawn, and is taller with the alerts written under it.
    @MainActor func testSharedPictureCarriesTheAlerts() throws {
        let fig = try figure()
        var r = PatientRecord()
        XCTAssertNil(HandoffShare.diagramImage(r, figure: fig))
        r.devices = [PatientDevice(kind: .piv, site: "forearm-left", side: "left", size: "20")]
        let plain = try XCTUnwrap(HandoffShare.diagramImage(r, figure: fig))
        r.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "Prior axillary lymph node dissection")]
        let marked = try XCTUnwrap(HandoffShare.diagramImage(r, figure: fig))
        XCTAssertGreaterThan(marked.size.height, plain.size.height, "the reason is written under the figure")
        XCTAssertEqual(marked.size.width, plain.size.width, accuracy: 0.5)
        var only = PatientRecord()
        only.limbAlerts = [PatientLimbAlert(limb: "arm-left", reason: "Lymphedema")]
        XCTAssertNotNil(HandoffShare.diagramImage(only, figure: fig), "a limb alert alone is something drawn")
    }
}
