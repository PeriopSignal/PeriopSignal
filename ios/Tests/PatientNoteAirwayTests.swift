import XCTest
@testable import PeriopSignal

/// Fill from a note into the 1.6 record: the current airway, the ventilator, oxygen, and lines and mechanical support on
/// arrival (PatientNote with PatientDevices.parse).
final class PatientNoteAirwayTests: XCTestCase {
    /// 30 October 2026, 08:00 on the device's clock.
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))! }

    private func read(_ text: String) -> PatientNoteReading { PatientNote.read(text, now: now) }
    private func finding(_ r: PatientNoteReading, _ id: String) -> PatientNoteFinding? { r.findings.first { $0.id == id } }
    private func record(_ r: PatientNoteReading, from base: PatientRecord = PatientRecord()) -> PatientRecord {
        var rec = base
        PatientNote.apply(r.findings.map(\.change), to: &rec)
        return rec
    }
    private func vent(_ r: PatientNoteReading) -> PatientVent? {
        if case .vent(let v)? = finding(r, "vent")?.change { return v }
        return nil
    }
    private func oxygen(_ r: PatientNoteReading) -> PatientOxygen? {
        if case .oxygen(let o)? = finding(r, "oxygen")?.change { return o }
        return nil
    }
    /// Every device the note's device findings would add.
    private func devices(_ r: PatientNoteReading) -> [PatientDevice] {
        r.findings.flatMap { f -> [PatientDevice] in
            if case .devices(let ds) = f.change { return ds }
            return []
        }
    }

    func testSectionsInTheEditorsOrder() {
        XCTAssertEqual(Array(PatientNote.sections.suffix(3)), [PatientNote.Part.airway, PatientNote.Part.devices, PatientNote.Part.support])
    }

    func testIntubatedWithTubeAndVentilator() {
        let r = read("Intubated, ETT 8.0 @ 22 at teeth. AC/VC 450 x 16, PEEP 5, FiO2 40%.")
        XCTAssertEqual(finding(r, "airway")?.change, .currentAirway("ett", "8.0", "22 cm at the teeth"))
        XCTAssertEqual(finding(r, "airway")?.section, PatientNote.Part.airway)
        let v = vent(r)
        XCTAssertEqual(v?.mode, "AC/VC")
        XCTAssertEqual(v?.vt, 450)
        XCTAssertEqual(v?.rr, 16)
        XCTAssertEqual(v?.peep, 5)
        XCTAssertEqual(v?.fio2, 40)
        XCTAssertNil(oxygen(r))
        XCTAssertEqual(r.other, "", "nothing about the tube or the settings is left over")

        let rec = record(r)
        XCTAssertEqual(rec.currentAirway, "ett")
        XCTAssertEqual(rec.ettSize, "8.0")
        XCTAssertEqual(rec.ettDepth, "22 cm at the teeth")
        XCTAssertEqual(rec.vent.peep, 5)
        for f in r.findings where f.section == PatientNote.Part.airway {
            XCTAssertEqual(PatientNote.status(f, in: rec), .recorded, f.label)
        }
    }

    func testVentilatorSettingsAndModes() {
        let r = read("On vent: AC/PRVC/PS 10, PEEP 5, FiO2 60%")
        let v = vent(r)
        XCTAssertEqual(v?.mode, "PRVC", "the more specific mode")
        XCTAssertEqual(v?.ps, 10)
        XCTAssertEqual(v?.peep, 5)
        XCTAssertEqual(v?.fio2, 60)
        if case .currentAirway(let id, _, _)? = finding(r, "airway")?.change { XCTAssertEqual(id, "ett") } else { XCTFail("on the vent: intubated") }

        let ps = vent(read("Mechanically ventilated, SIMV, PS 10/5, FiO2 0.5"))
        XCTAssertEqual(ps?.mode, "SIMV")
        XCTAssertEqual(ps?.ps, 10)
        XCTAssertEqual(ps?.peep, 5, "PS 10/5 is a pressure support of 10 over a PEEP of 5")
        XCTAssertEqual(ps?.fio2, 50)

        var rec = PatientRecord()
        rec.vent.peep = 8
        let changed = PatientNoteFinding(id: "vent", section: PatientNote.Part.airway, label: "", change: .vent({ var x = PatientVent(); x.peep = 5; return x }()))
        XCTAssertEqual(PatientNote.status(changed, in: rec), .replaces("PEEP 8"))
        let more = PatientNoteFinding(id: "vent", section: PatientNote.Part.airway, label: "", change: .vent({ var x = PatientVent(); x.fio2 = 40; return x }()))
        XCTAssertEqual(PatientNote.status(more, in: rec), .new, "adds a setting, keeps the PEEP")
        PatientNote.apply([more.change], to: &rec)
        XCTAssertEqual(rec.vent.peep, 8)
        XCTAssertEqual(rec.vent.fio2, 40)
    }

    func testOxygen() {
        let nc = read("SpO2 94% on 2L NC")
        XCTAssertEqual(oxygen(nc), PatientOxygen(device: "nc", flow: 2))
        XCTAssertEqual(finding(nc, "oxygen")?.label, "Oxygen: Nasal cannula 2 L/min")
        XCTAssertEqual(finding(nc, "airway")?.change, .currentAirway("natural", "", ""), "breathing on their own")

        XCTAssertEqual(oxygen(read("HFNC 40 L/60%")), PatientOxygen(device: "hfnc", flow: 40, fio2: 60))
        XCTAssertEqual(oxygen(read("On NRB at 15 L")), PatientOxygen(device: "nrb", flow: 15))
        XCTAssertEqual(oxygen(read("On BiPAP 12/5, FiO2 50%")), PatientOxygen(device: "niv", fio2: 50))
        XCTAssertNil(oxygen(read("OSA on CPAP")), "CPAP for sleep apnea is not the oxygen on arrival")
        XCTAssertNil(oxygen(read("Uses BiPAP at night")))

        let ra = read("SpO2 97% on RA")
        XCTAssertEqual(oxygen(ra), PatientOxygen(device: "ra"))
        XCTAssertEqual(finding(ra, "airway")?.change, .currentAirway("natural", "", ""))
        let rec = record(ra)
        XCTAssertEqual(rec.currentAirway, "natural")
        XCTAssertEqual(rec.oxygen.device, "ra")
        XCTAssertEqual(rec.oxygen.text, "Room air")

        var onNC = PatientRecord()
        onNC.oxygen = PatientOxygen(device: "nc", flow: 4)
        XCTAssertEqual(PatientNote.status(PatientNoteFinding(id: "oxygen", section: PatientNote.Part.airway, label: "", change: .oxygen(PatientOxygen(device: "ra"))), in: onNC),
                       .replaces("Nasal cannula 4 L/min"))
    }

    func testTracheostomy() {
        let r = read("s/p trach, on trach collar 35%")
        if case .currentAirway(let id, _, _)? = finding(r, "airway")?.change { XCTAssertEqual(id, "trach") } else { XCTFail("a tracheostomy") }
        XCTAssertEqual(oxygen(r)?.device, "trachCollar")
        XCTAssertEqual(oxygen(r)?.fio2, 35)
        XCTAssertNil(finding(r, "vent"))
        XCTAssertNil(finding(read("Scheduled for tracheostomy"), "airway"), "a planned tracheostomy is not one yet")
        XCTAssertNil(finding(read("ETT negative for ischemia"), "airway"), "an exercise treadmill test")
    }

    func testLinesAndDevices() {
        let r = read("Lines: PIV x2 18G, R rad art line 20g, RIJ TLC, PAC via RIJ, RUE PICC.")
        let ds = devices(r)
        XCTAssertEqual(ds.filter { $0.kind == .piv }.count, 2, "PIV x2")
        XCTAssertEqual(ds.filter { $0.kind == .piv }.map(\.size), ["18", "18"])
        XCTAssertTrue(ds.contains { $0.kind == .arterial && $0.site == "radial-right" && $0.size == "20" })
        XCTAssertTrue(ds.contains { $0.kind == .cvc && $0.site == "ij-right" && $0.detail == "triple lumen" })
        XCTAssertTrue(ds.contains { $0.kind == .pac && $0.site == "ij-right" })
        XCTAssertTrue(ds.contains { $0.kind == .picc && $0.site == "upper-arm-right" })
        XCTAssertFalse(ds.contains { $0.placedIntraop }, "there on arrival")
        XCTAssertTrue(r.findings.filter { $0.id.hasPrefix("device:") }.allSatisfy { $0.section == PatientNote.Part.devices })
        XCTAssertEqual(r.findings.first { $0.id.hasPrefix("device:") && $0.label.contains("PIV") }?.label, "PIV 18 G ×2")
        XCTAssertEqual(r.other, "")

        let rec = record(r)
        XCTAssertEqual(rec.currentDevices().count, 6)
        for f in r.findings where f.id.hasPrefix("device:") {
            XCTAssertEqual(PatientNote.status(f, in: rec), .recorded, "not added twice: " + f.label)
        }
        var again = rec
        PatientNote.apply(r.findings.map(\.change), to: &again)
        XCTAssertEqual(again.devices.count, 6, "a device the record already has is not added again")
        XCTAssertTrue(devices(read("Occasional PACs on tele")).isEmpty, "premature atrial contractions")
        XCTAssertTrue(devices(read("Will place R radial A-line pre-induction")).isEmpty, "not there yet")
        XCTAssertTrue(devices(read("Given 1 L IV fluids")).isEmpty)
        XCTAssertTrue(devices(read("No central line")).isEmpty)
    }

    func testMechanicalSupport() {
        let r = read("IABP L femoral 1:1. Impella CP RFA. HM3 LVAD. VA ECMO 25F LFV / 17F LFA.")
        let ds = devices(r)
        XCTAssertTrue(ds.contains { $0.kind == .iabp && $0.site == "femoral-artery-left" && $0.settings["ratio"] == "1:1" })
        XCTAssertTrue(ds.contains { $0.kind == .impella && $0.detail == "CP" && $0.site == "femoral-artery-right" })
        XCTAssertTrue(ds.contains { $0.kind == .lvad && $0.detail == "HeartMate 3" })
        XCTAssertEqual(ds.filter { $0.kind == .ecmoDrainage }.map(\.site), ["femoral-vein-left"])
        XCTAssertEqual(ds.filter { $0.kind == .ecmoReturn }.map(\.site), ["femoral-artery-left"])
        XCTAssertTrue(r.findings.filter { $0.id.hasPrefix("device:") }.allSatisfy { $0.section == PatientNote.Part.support })
        XCTAssertNil(finding(r, "symptom:chest-pain"), "Impella CP is not chest pain")
        XCTAssertTrue(r.unknown.isEmpty)
        let rec = record(r)
        XCTAssertEqual(rec.mechanicalSupport.count, 5)
        XCTAssertEqual(PatientDevices.ecmoSystem(rec.devices)?.configuration, .vaPeripheral)
    }

    func testExistingDeviceIsRecorded() {
        var rec = PatientRecord()
        rec.devices = [PatientDevice(kind: .arterial, site: "radial-right", side: "right", size: "20")]
        let r = read("R rad art line 20g")
        guard let f = r.findings.first(where: { $0.id.hasPrefix("device:") }) else { return XCTFail("an arterial line") }
        XCTAssertEqual(PatientNote.status(f, in: rec), .recorded)
        var removed = rec
        removed.devices[0].removed = true
        XCTAssertEqual(PatientNote.status(f, in: removed), .new, "a line taken out does not count")
    }

    func testCodeStatusIsOnlyRecognized() {
        XCTAssertEqual(MedAbbreviations.lookup("DNR")?.meanings.first?.text, "do not resuscitate")
        let r = read("DNR/DNI")
        XCTAssertTrue(r.unknown.isEmpty)
        XCTAssertTrue(r.findings.isEmpty, "no field holds the code status yet")
    }
}
