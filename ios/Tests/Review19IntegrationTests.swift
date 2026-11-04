import XCTest
@testable import PeriopSignal

/// 1.9 review (integration): where two branches' fixes meet. The labs' Anemia and a child's age, the device fills beside
/// a record saved by 1.8.3 and a fistula drawn with no place, the vertebral caution beside a limb alert, a denied
/// anaphylaxis in typed allergies, a current smoker and "No significant medical history", and a Lines & devices block
/// the user emptied.
final class Review19IntegrationTests: XCTestCase {

    /// One change as PatientStore.update makes it: the change, then the fills.
    private func change(_ r: inout PatientRecord, _ body: (inout PatientRecord) -> Void) {
        let before = r
        body(&r)
        PatientCrossFill.apply(before: before, after: &r)
    }

    // MARK: Anemia and a child's age

    /// A lab-filled Anemia, then an age under 15 typed: nothing is checked by itself under 15, so the labs' Anemia is
    /// set aside (and "No significant medical history" given back); correcting the Hb then leaves nothing behind.
    func testALabFilledAnemiaIsNotKeptForAChild() {
        var r = PatientRecord()
        r.sex = .female
        r.noHistory = true
        change(&r) { $0.labs["hb"] = 11 }
        XCTAssertTrue(r.has("anemia"), "below 12 with no age yet")
        XCTAssertFalse(r.noHistory)
        change(&r) { $0.ageYears = 8 }
        XCTAssertFalse(r.has("anemia"), "a child of 8: not checked by itself")
        XCTAssertFalse(r.labProblems.contains("anemia"))
        XCTAssertTrue(r.noHistory, "given back with the Anemia")
        change(&r) { $0.labs["hb"] = 13 }
        XCTAssertFalse(r.has("anemia"))
        XCTAssertTrue(r.noHistory)
        XCTAssertEqual(r.fills, PatientFills())

        // A record already holding the labs' Anemia beside a child's age: a Hb typed again takes it back.
        var old = PatientRecord()
        old.sex = .female; old.ageYears = 8; old.labs["hb"] = 11
        old.problems = ["anemia"]; old.labProblems = ["anemia"]
        change(&old) { $0.labs["hb"] = 13 }
        XCTAssertFalse(old.has("anemia"))

        // An adult age typed digit by digit still keeps the fill's Anemia, and the user's own Anemia is never touched.
        var a = PatientRecord()
        a.sex = .female; a.ageYears = 45; a.problems = ["htn"]
        change(&a) { $0.labs["hb"] = 10.5 }
        for age in [4.0, 46.0] { change(&a) { $0.ageYears = age } }
        XCTAssertTrue(a.has("anemia"))
        XCTAssertTrue(a.labProblems.contains("anemia"))
        XCTAssertFalse(a.fills.anemiaAside)
        var u = PatientRecord()
        u.sex = .female; u.ageYears = 45; u.problems = ["anemia"]
        change(&u) { $0.labs["hb"] = 10.5 }
        change(&u) { $0.ageYears = 8 }
        XCTAssertTrue(u.has("anemia"), "the user's")
        // Set aside for a child, then Anemia recorded by the user: an adult age later does not double or claim it.
        var s = PatientRecord()
        s.sex = .female; s.ageYears = 45; s.problems = ["htn"]
        change(&s) { $0.labs["hb"] = 10.5 }
        change(&s) { $0.ageYears = 8 }
        XCTAssertTrue(s.fills.anemiaAside)
        change(&s) { _ = $0.problems.insert("anemia") }
        XCTAssertFalse(s.fills.anemiaAside)
        change(&s) { $0.ageYears = 46 }
        XCTAssertTrue(s.has("anemia"))
        XCTAssertFalse(s.labProblems.contains("anemia"), "the user's, not the labs'")
    }

    // MARK: Devices

    /// A 1.8.3 "dialysis catheter" or "chest tube" line, migrated as placed in the room: the history saying the patient
    /// arrives with one still draws it on arrival, so the preprocedure brief and its diagram show it.
    func testAMigratedLineDoesNotHideTheOnArrivalDevice() throws {
        var r = PatientRecord()
        r.devices = [PatientDevice(kind: .cvc, site: "ij-right", side: "right", detail: "dialysis catheter", placedIntraop: true),
                     PatientDevice(kind: .other, detail: "chest tube", placedIntraop: true)]
        change(&r) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["catheter"]; $0.hx.dialysisCatheterSite = "R IJ" }
        change(&r) { $0.hx.chestTube = true; $0.hx.chestTubeSides = ["left"] }
        let arrival = r.currentDevices(arrivalOnly: true)
        XCTAssertTrue(arrival.contains { $0.kind == .dialysisCatheter && $0.site == "ij-right" }, arrival.map(\.label).joined(separator: ", "))
        XCTAssertTrue(arrival.contains { $0.kind == .chestTube && $0.side == "left" }, arrival.map(\.label).joined(separator: ", "))
        let lines = try XCTUnwrap(PatientBriefs.preop(r).first { $0.key == "lines" })
        XCTAssertTrue(lines.text.localizedCaseInsensitiveContains("catheter"), lines.text)
        // The same form drawn as on arrival (not placed in the room) still stands for it: not doubled.
        var mine = PatientRecord()
        mine.devices = [PatientDevice(kind: .cvc, site: "ij-right", side: "right", detail: "dialysis catheter")]
        change(&mine) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["catheter"]; $0.hx.dialysisCatheterSite = "R IJ" }
        XCTAssertEqual(mine.devices.count, 1)
    }

    /// "AVF" drawn with no place and no side does not stand for the Renal page's left forearm fistula: that one is drawn,
    /// with its limb alert, and the harvest line does not send lines to the left arm.
    func testASidelessFistulaDoesNotAbsorbALocatedOne() {
        var r = PatientRecord()
        r.devices = [PatientDevice(kind: .avFistula)]
        change(&r) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["fistula"] }
        XCTAssertEqual(r.devices.count, 1, "the chip with no location: the drawn one stands for it")
        change(&r) { $0.hx.fistulaSite = "left forearm" }
        XCTAssertTrue(r.devices.contains { $0.kind == .avFistula && $0.site == "forearm-left" })
        XCTAssertTrue(PatientDeviceFills.limbAlerts(r).contains { $0.limb == "arm-left" && $0.automatic })
        r.radial.harvest = "right"
        let reminder = PatientStudies.harvestReminder(r) ?? ""
        XCTAssertFalse(reminder.contains("in the left arm"), reminder)
        XCTAssertTrue(HandoffWriter.text(r).contains("Limb alert: L arm — AV fistula"), HandoffWriter.text(r))

        // The location typed in one go, beside the side-less one: drawn too.
        var once = PatientRecord()
        once.devices = [PatientDevice(kind: .avFistula)]
        change(&once) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["fistula"]; $0.hx.fistulaSite = "left forearm" }
        XCTAssertTrue(PatientDeviceFills.limbAlerts(once).contains { $0.limb == "arm-left" })

        // The fill's first, then the side-less one drawn, then the location retyped: the fill's follows and stays.
        var f = PatientRecord()
        change(&f) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["fistula"]; $0.hx.fistulaSite = "left forearm" }
        change(&f) { $0.devices.append(PatientDevice(kind: .avFistula)) }
        change(&f) { $0.hx.fistulaSite = "left upper arm" }
        XCTAssertTrue(f.devices.contains { $0.site == "upper-arm-left" })
        XCTAssertNotNil(f.fills.devices["hd-fistula"])
        XCTAssertTrue(PatientDeviceFills.limbAlerts(f).contains { $0.limb == "arm-left" })

        // A side-less fistula still stands for a source that names no side either.
        var n = PatientRecord()
        n.devices = [PatientDevice(kind: .avFistula)]
        change(&n) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisAccess = ["fistula"]; $0.hx.fistulaSite = "somewhere" }
        XCTAssertEqual(n.devices.count, 1)
    }

    // MARK: The vertebral caution beside a limb alert

    /// Steal on the harvest side and a fistula in the other arm: neither the harvest line nor the vertebral caution sends
    /// the arterial line and cuff to the fistula arm. Without a harvest, the same.
    func testTheVertebralCautionDoesNotSendLinesToALimbAlertArm() throws {
        var r = PatientRecord()
        r.radial.harvest = "left"
        r.carotid.left.vertebral = "reversed"
        r.devices = [PatientDevice(kind: .avFistula, site: "forearm-right", side: "right")]
        XCTAssertEqual(PatientStudies.harvestReminder(r), "Planned left radial harvest: keep lines and the cuff off the left arm; the right arm has a limb alert.")
        let v = try XCTUnwrap(PatientStudies.cautions(r).first { $0.id == "vertebral-left" }?.text)
        XCTAssertFalse(v.contains("use the right arm"), v)
        XCTAssertFalse(v.contains("Use the right arm"), v)
        XCTAssertTrue(v.contains("Left-arm BP may read low"), v)

        var noHarvest = PatientRecord()
        noHarvest.carotid.left.vertebral = "partial"
        noHarvest.limbAlerts = [PatientLimbAlert(limb: "arm-right", reason: "Prior axillary lymph node dissection")]
        let p = try XCTUnwrap(PatientStudies.cautions(noHarvest).first { $0.id == "vertebral-left" }?.text)
        XCTAssertFalse(p.contains("Use the right arm"), p)

        // No limb alert: the other arm is still offered.
        var plain = PatientRecord()
        plain.carotid.left.vertebral = "reversed"
        let q = try XCTUnwrap(PatientStudies.cautions(plain).first { $0.id == "vertebral-left" }?.text)
        XCTAssertTrue(q.contains("use the right arm for the arterial line and cuff"), q)
        // A limb alert on the steal side itself does not change it.
        plain.limbAlerts = [PatientLimbAlert(limb: "arm-left", reason: "Lymphedema")]
        let w = try XCTUnwrap(PatientStudies.cautions(plain).first { $0.id == "vertebral-left" }?.text)
        XCTAssertTrue(w.contains("use the right arm for the arterial line and cuff"), w)
    }
}
