import XCTest
@testable import PeriopSignal

/// The 1.9 review of the line diagram's devices: the device fills from the history pages (the order the Renal page asks
/// in, a device the user drew, records saved before 1.9), reading a typed access location, the shorthand, limb alerts
/// with the radial harvest, and the ECG link beside a generator on the diagram.
final class Review19DevicesTests: XCTestCase {

    /// The record after one change, with the device fills run as PatientStore.update does.
    private func change(_ r: PatientRecord, _ edit: (inout PatientRecord) -> Void) -> PatientRecord {
        var after = r
        edit(&after)
        PatientDeviceFills.apply(before: r, after: &after)
        return after
    }

    private func devices(_ r: PatientRecord, _ kind: DeviceKind) -> [PatientDevice] { r.devices.filter { $0.kind == kind } }

    private func parse(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> DeviceParse {
        try XCTUnwrap(PatientDevices.parse(text), "no parse for \"\(text)\"", file: file, line: line)
    }

    private func readFistula(_ text: String) -> PatientDeviceFills.AccessSite { PatientDeviceFills.readAccessSite(text, kind: .avFistula) }
    private func readCatheter(_ text: String) -> PatientDeviceFills.AccessSite { PatientDeviceFills.readAccessSite(text, kind: .dialysisCatheter) }

    // MARK: Fills

    /// A fistula or catheter drawn by hand, then the access chosen on Renal (no location yet), then the location typed:
    /// one device, the user's.
    func testAccessChosenThenTypedBesideAHandDrawnOneIsNotDoubled() {
        var mine = PatientRecord()
        mine.devices = [PatientDevice(kind: .avFistula, site: "forearm-left", side: "left")]
        var r = change(mine) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["fistula"] }
        XCTAssertEqual(devices(r, .avFistula).count, 1, "the chip, with no location yet: the drawn one stands for it")
        r = change(r) { $0.hx.fistulaSite = "left forearm" }
        XCTAssertEqual(devices(r, .avFistula).count, 1)
        XCTAssertEqual(devices(r, .avFistula)[0].id, mine.devices[0].id)
        XCTAssertNil(r.fills.devices["hd-fistula"])
        XCTAssertEqual(PatientSummary.arrivalDeviceLines(r).first?.text, "AV fistula L forearm")

        var cath = PatientRecord()
        cath.devices = [PatientDevice(kind: .dialysisCatheter, site: "ij-right", side: "right")]
        var c = change(cath) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["catheter"] }
        c = change(c) { $0.hx.dialysisCatheterSite = "R IJ" }
        XCTAssertEqual(devices(c, .dialysisCatheter).count, 1)

        // The fill made first, the user then drawing their own, then the location typed: the fill's is taken back.
        var f = change(PatientRecord()) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["fistula"] }
        XCTAssertEqual(devices(f, .avFistula).count, 1)
        let drawn = PatientDevice(kind: .avFistula, site: "forearm-left", side: "left")
        f = change(f) { $0.devices.append(drawn) }
        f = change(f) { $0.hx.fistulaSite = "left forearm" }
        XCTAssertEqual(devices(f, .avFistula).map(\.id), [drawn.id])
        XCTAssertNil(f.fills.devices["hd-fistula"])
        // Typed somewhere else, the fill's would have been kept: a second fistula.
        var g = change(PatientRecord()) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["fistula"] }
        g = change(g) { $0.devices.append(drawn) }
        g = change(g) { $0.hx.fistulaSite = "right upper arm" }
        XCTAssertEqual(Set(devices(g, .avFistula).map(\.site)), ["forearm-left", "upper-arm-right"])
    }

    /// A hand-drawn device marked removed or deleted while its source holds: nothing is added in its place.
    func testRemovingOrDeletingAHandDrawnDeviceDoesNotBringAFillOne() {
        var mine = PatientRecord()
        mine.devices = [PatientDevice(kind: .dialysisCatheter, site: "ij-right", side: "right")]
        var r = change(mine) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["catheter"]; $0.hx.dialysisCatheterSite = "R IJ" }
        XCTAssertEqual(r.devices.count, 1)
        XCTAssertTrue(r.fills.devices.isEmpty)
        r = change(r) { $0.devices[0].removed = true }
        r = change(r) { $0.weightKg = 80 }
        XCTAssertEqual(r.devices.count, 1, "no fresh catheter on arrival")
        XCTAssertTrue(r.devices[0].removed)
        var d = change(mine) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["catheter"]; $0.hx.dialysisCatheterSite = "R IJ" }
        d = change(d) { $0.devices.removeAll() }
        d = change(d) { $0.weightKg = 80 }
        XCTAssertTrue(d.devices.isEmpty, "deleted: not added again while the source holds")
        // One already marked removed when the source appears is the user's record of it (conservative: nothing added).
        var gone = PatientRecord()
        var old = PatientDevice(kind: .dialysisCatheter, site: "ij-right", side: "right")
        old.removed = true
        gone.devices = [old]
        gone = change(gone) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["catheter"]; $0.hx.dialysisCatheterSite = "R IJ" }
        XCTAssertEqual(gone.devices.count, 1)
    }

    /// A record saved before 1.9 with a pacemaker, a chest tube or a fistula opens and edits unchanged.
    func testARecordSavedBefore19IsNotChangedByAnUnrelatedEdit() {
        var r = PatientRecord()
        r.problems = ["pacemaker", "esrd-dialysis"]
        r.hx.dialysisAccess = ["fistula"]
        r.hx.fistulaSite = "left forearm"
        r.hx.chestTube = true
        r.hx.chestTubeSides = ["left"]
        let after = change(r) { $0.weightKg = 80 }
        XCTAssertTrue(after.devices.isEmpty, after.devices.map(\.label).joined(separator: ", "))
        XCTAssertTrue(after.fills.devices.isEmpty)
        // A source that appears later is still drawn.
        let paced = change(PatientRecord()) { $0.problems.insert("pacemaker") }
        XCTAssertEqual(devices(paced, .cied).count, 1)
    }

    /// The device as a record before 1.9 kept it (a CVL "dialysis catheter", an Other "chest tube") is not doubled.
    func testLegacyDialysisCatheterAndChestTubeAreNotDoubled() {
        var r = PatientRecord()
        r.devices = [PatientDevice(kind: .cvc, site: "ij-right", side: "right", detail: "dialysis catheter")]
        r = change(r) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["catheter"]; $0.hx.dialysisCatheterSite = "R IJ" }
        XCTAssertTrue(devices(r, .dialysisCatheter).isEmpty)
        XCTAssertEqual(r.devices.count, 1)
        // A plain CVL is not a dialysis catheter.
        var cvl = PatientRecord()
        cvl.devices = [PatientDevice(kind: .cvc, site: "ij-right", side: "right", detail: "triple lumen")]
        cvl = change(cvl) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["catheter"]; $0.hx.dialysisCatheterSite = "R IJ" }
        XCTAssertEqual(devices(cvl, .dialysisCatheter).count, 1)

        var t = PatientRecord()
        t.devices = [PatientDevice(kind: .other, detail: "chest tube")]
        t = change(t) { $0.hx.chestTube = true; $0.hx.chestTubeSides = ["left"] }
        XCTAssertTrue(devices(t, .chestTube).isEmpty)
        XCTAssertEqual(t.devices.count, 1)
    }

    // MARK: Reading a typed location

    func testAnExactPlaceOrTypeOutranksTheLimb() {
        XCTAssertEqual(readFistula("LUE brachiocephalic AVF"), PatientDeviceFills.AccessSite(site: "upper-arm-left", side: "left", detail: "brachiocephalic"))
        XCTAssertEqual(readFistula("left arm brachiocephalic").site, "upper-arm-left")
        XCTAssertEqual(readFistula("RUE BBF"), PatientDeviceFills.AccessSite(site: "upper-arm-right", side: "right", detail: "brachiobasilic"))
        XCTAssertEqual(readFistula("left arm radiocephalic").site, "wrist-left")
        XCTAssertEqual(readFistula("LUE forearm").site, "forearm-left")
        // The limb alone is still the forearm (or the thigh).
        XCTAssertEqual(readFistula("LUE").site, "forearm-left")
        XCTAssertEqual(readFistula("R arm").site, "forearm-right")
        XCTAssertEqual(readFistula("LLE").site, "thigh-left")
    }

    func testTheExternalJugularIsNotTheIJ() {
        XCTAssertEqual(readCatheter("right external jugular tunneled"),
                       PatientDeviceFills.AccessSite(site: "", side: "right", detail: "right external jugular tunneled"))
        XCTAssertEqual(readCatheter("R EJ").site, "")
        XCTAssertEqual(readCatheter("R internal jugular").site, "ij-right")
        XCTAssertEqual(readCatheter("right jugular").site, "ij-right")
    }

    func testHyphenatedUpperArm() {
        XCTAssertEqual(readFistula("L upper-arm AVF"), PatientDeviceFills.AccessSite(site: "upper-arm-left", side: "left", detail: ""))
        XCTAssertEqual(readFistula("R upper - arm").site, "upper-arm-right")
    }

    // MARK: Shorthand

    func testAWireThatIsNotEpicardial() throws {
        let tvp = try parse("R IJ transvenous pacing wire")
        XCTAssertNotEqual(tvp.kind, .epicardialWires)
        XCTAssertEqual(tvp.site, "ij-right")
        let swan = try parse("Swan R IJ with pacing wire")
        XCTAssertEqual(swan.kind, .pac)
        XCTAssertEqual(swan.site, "ij-right")
        let cvl = try parse("CVL R IJ over wire")
        XCTAssertEqual(cvl.kind, .cvc)
        XCTAssertEqual(cvl.site, "ij-right")
        XCTAssertNotEqual(PatientDevices.parse("transvenous pacing wire")?.kind, .epicardialWires)
        // Epicardial wires as before.
        XCTAssertEqual(try parse("V wires").kind, .epicardialWires)
        XCTAssertEqual(try parse("temp wires A and V").settings["chambers"], "both")
        XCTAssertEqual(try parse("pacing wires").kind, .epicardialWires)
        XCTAssertEqual(try parse("atrial and ventricular pacing wires DDD 80").settings["chambers"], "both")
        XCTAssertEqual(try parse("epicardial wires A+V").site, "epicardial-exit")
    }

    func testAGroinFistulaIsTheLeg() throws {
        let graft = try parse("L femoral AV graft")
        XCTAssertEqual(graft.kind, .avFistula)
        XCTAssertEqual(graft.site, "thigh-left")
        let fa = try parse("AVF L FA")
        XCTAssertEqual(fa.kind, .avFistula)
        XCTAssertEqual(fa.site, "forearm-left")
        // The femoral sites still mean the vessels for other devices.
        XCTAssertEqual(try parse("CVL L femoral").site, "femoral-vein-left")
        XCTAssertEqual(try parse("art line R FA").site, "femoral-artery-right")
        // A fistula kept at a groin site marks the leg.
        let groin = PatientDevice(kind: .avFistula, site: "femoral-vein-left", side: "left", detail: "AV graft")
        XCTAssertEqual(PatientDeviceFills.limb(of: groin), "leg-left")
        var r = PatientRecord()
        r.devices = [groin]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), "L leg — AV graft")
    }

    // MARK: Limb alerts

    func testAUserReasonThatSaysMoreThanTheFistulaIsKept() {
        var r = PatientRecord()
        r.devices = [PatientDevice(kind: .avFistula, site: "forearm-left", side: "left")]
        r.limbAlerts = [PatientLimbAlert(limb: "arm-left", reason: "Steal syndrome from AV fistula, no BP cuff")]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), "L arm — AV fistula, steal syndrome from AV fistula, no BP cuff")
        r.limbAlerts = [PatientLimbAlert(limb: "arm-left", reason: "Lymphedema after node dissection; old AVF")]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), "L arm — AV fistula, lymphedema after node dissection; old AVF")
        // Only the fistula again: once.
        r.limbAlerts = [PatientLimbAlert(limb: "arm-left", reason: "AV fistula, no BP or IVs")]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(r), "L arm — AV fistula")
        // On the harvest arm, a reason beyond the harvest is kept; the harvest alone is not.
        var h = PatientRecord()
        h.radial.harvest = "left"
        h.limbAlerts = [PatientLimbAlert(limb: "arm-left", reason: "Old harvest scar infection")]
        XCTAssertEqual(PatientDeviceFills.limbAlertText(h), "L arm — old harvest scar infection")
        h.limbAlerts = [PatientLimbAlert(limb: "arm-left", reason: "Planned radial artery harvest, no lines")]
        XCTAssertNil(PatientDeviceFills.limbAlertText(h))
    }

    func testTheHarvestLineDoesNotSendLinesToTheArmToSpare() {
        var r = PatientRecord()
        r.radial.harvest = "left"
        XCTAssertEqual(PatientStudies.harvestReminder(r), "Planned left radial harvest: arterial line, IVs and BP cuff in the right arm.")
        r.devices = [PatientDevice(kind: .avFistula, site: "forearm-right", side: "right")]
        let reminder = PatientStudies.harvestReminder(r)
        XCTAssertEqual(reminder, "Planned left radial harvest: keep lines and the cuff off the left arm; the right arm has a limb alert.")
        let text = HandoffWriter.text(r)
        XCTAssertFalse(text.contains("cuff in the right arm"), text)
        XCTAssertTrue(text.contains("Limb alert: R arm — AV fistula"), text)
        // A typed alert on the other arm, the same.
        var u = PatientRecord()
        u.radial.harvest = "right"
        u.limbAlerts = [PatientLimbAlert(limb: "arm-left", reason: "Prior axillary lymph node dissection")]
        XCTAssertEqual(PatientStudies.harvestReminder(u), "Planned right radial harvest: keep lines and the cuff off the right arm; the left arm has a limb alert.")
        // An alert on the harvest arm itself does not change where the lines go.
        u.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "Lymphedema")]
        XCTAssertEqual(PatientStudies.harvestReminder(u), "Planned right radial harvest: arterial line, IVs and BP cuff in the left arm.")
    }

    // MARK: ECG and chambers

    func testAnICDOnTheDiagramKeepsAPacedECGFromFilingAPacemaker() {
        var r = PatientRecord()
        r.devices = [PatientDevice(kind: .cied, site: "generator-left", side: "left", detail: "ICD")]
        XCTAssertTrue(PatientECGLink.deviceAlready(r))
        PatientECGLink.add("Paced rhythm (ventricular)", to: &r)
        XCTAssertFalse(r.has("pacemaker"))
        var crt = PatientRecord()
        crt.devices = [PatientDevice(kind: .cied, site: "generator-left", side: "left", detail: "CRT-D")]
        PatientECGLink.add("Paced rhythm (AV)", to: &crt)
        XCTAssertFalse(crt.has("pacemaker"))
        // A pacemaker on the diagram, or an ICD marked removed, does not block it.
        var ppm = PatientRecord()
        ppm.devices = [PatientDevice(kind: .cied, site: "generator-left", side: "left", detail: "pacemaker")]
        PatientECGLink.add("Paced rhythm (ventricular)", to: &ppm)
        XCTAssertTrue(ppm.has("pacemaker"))
        var gone = PatientRecord()
        var icd = PatientDevice(kind: .cied, site: "generator-left", side: "left", detail: "ICD")
        icd.removed = true
        gone.devices = [icd]
        XCTAssertFalse(PatientECGLink.deviceAlready(gone))
    }

    func testBiatrialIsTheAtriaOnly() {
        let d = PatientDevice(kind: .epicardialWires, site: "epicardial-exit", settings: ["chambers": "biatrial"])
        XCTAssertEqual(PatientDevices.chamberWords(d), ["atrial"])
        XCTAssertFalse(d.label.contains("ventricular"), d.label)
        let both = PatientDevice(kind: .epicardialWires, site: "epicardial-exit", settings: ["chambers": "both"])
        XCTAssertEqual(PatientDevices.chamberWords(both), ["atrial", "ventricular"])
    }
}
