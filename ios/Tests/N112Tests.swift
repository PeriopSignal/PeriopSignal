import XCTest
import CoreGraphics
@testable import PeriopSignal

/// 1.12 helper N (Ben, Nov 12): five new monitors and adjuncts under Lines & Devices (cerebral oximetry, TEE probe, defibrillator
/// pads, BIS/SedLine, bronchial blocker), listed and marked simply on the diagram, and a type picker whose Other list is grouped
/// under short headings, where the double-lumen tube and the epicardial pacing wires are easy to find.
final class N112Tests: XCTestCase {

    // MARK: Helpers

    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))! }

    private func parse(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> DeviceParse {
        try XCTUnwrap(PatientDevices.parse(text), "no parse for \"\(text)\"", file: file, line: line)
    }

    private func device(_ text: String, intra: Bool = false) throws -> PatientDevice {
        try parse(text).device(placedIntraop: intra)
    }

    /// The device findings (their handoff text) the note reader files for a sentence.
    private func labels(_ text: String) -> [String] {
        PatientNote.read(text, now: now).findings.filter { $0.id.hasPrefix("device:") }.map(\.label)
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return dist(p, a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return dist(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    private let five: [DeviceKind] = [.cerebralOximetry, .teeProbe, .defibPads, .processedEEG, .bronchialBlocker]

    /// A cardiac patient with an ETT, a central line, an arterial line and epicardial wires, and all five new items.
    private func cardiacRecord(intraop: Bool = true) throws -> PatientRecord {
        var r = PatientRecord()
        r.intubation = "easy"
        r.tube = "8.0 cuffed ETT (23 cm)"
        for text in ["RIJ introducer 9 Fr", "R radial art line 20g", "epicardial wires A and V", "cerebral oximetry", "BIS", "TEE probe in",
                     "Zoll pads on", "bronchial blocker left"] {
            r.devices += try parse(text).devices(placedIntraop: intraop)
        }
        return r
    }

    // MARK: Kinds

    func testTheFiveKindsHaveLabelsNamesColoursAndFields() {
        XCTAssertEqual(five.map(\.label), ["Cerebral oximetry", "TEE probe", "Defib pads", "BIS/SedLine", "Bronchial blocker"])
        XCTAssertEqual(DeviceKind.defibPads.name, "External defibrillator pads")
        XCTAssertEqual(DeviceKind.cerebralOximetry.name, "Cerebral oximetry")
        XCTAssertEqual(DeviceKind.teeProbe.name, "TEE probe")
        XCTAssertEqual(DeviceKind.bronchialBlocker.name, "Bronchial blocker")
        // Neutral olive for the monitors; the blocker is an airway device, drawn in the airway's colour; none is red.
        XCTAssertEqual([DeviceKind.cerebralOximetry, .teeProbe, .defibPads, .processedEEG].map(\.colorRole), Array(repeating: .monitor, count: 4))
        XCTAssertEqual(DeviceKind.bronchialBlocker.colorRole, .airway)
        let existing: Set<DeviceColorRole> = [.line, .central, .pac, .venousECMO, .arterialECMO, .pump, .neuraxial, .needle, .airway, .pacing, .access, .drain]
        XCTAssertEqual(Set(DeviceColorRole.allCases).subtracting(existing), [.monitor], "one new role, a colour of its own")
        for k in five {
            XCTAssertEqual(k.sizeUnit, "", "\(k) has no size")
            XCTAssertNotNil(k.fields.first { $0.id == "detail" }, "\(k) takes an optional free-text detail")
            XCTAssertTrue(PatientDevice.lineKinds.contains(k), "\(k) is listed with the lines and devices")
            XCTAssertFalse(PatientDevice.supportKinds.contains(k), "\(k) is not mechanical support")
            XCTAssertFalse(PatientStudies.armLineKinds.contains(k), "\(k) is not an arm line")
            XCTAssertTrue(PatientDevice(kind: k).isMonitorOrAdjunct)
        }
        XCTAssertFalse(PatientDevice(kind: .piv).isMonitorOrAdjunct)
        // The fields: the oximeter's side, the EEG's type quick picks, the blocker's side and nothing else.
        let ox = DeviceKind.cerebralOximetry.fields.first { $0.id == "side" }
        XCTAssertEqual(ox?.choices, ["Bilateral", "Left", "Right"])
        XCTAssertEqual(DeviceKind.cerebralOximetry.settingKeys, ["side"])
        XCTAssertEqual(DeviceKind.processedEEG.fields.first { $0.id == "detail" }?.choices, ["BIS", "SedLine"])
        XCTAssertEqual(DeviceKind.processedEEG.settingKeys, [])
        XCTAssertEqual(DeviceKind.bronchialBlocker.fields.first { $0.id == "side" }?.choices, ["Left", "Right"])
        XCTAssertEqual(DeviceKind.bronchialBlocker.fields.first { $0.id == "detail" }?.choices, [], "no product list")
        XCTAssertEqual(DeviceKind.teeProbe.settingKeys, [])
        XCTAssertEqual(DeviceKind.defibPads.settingKeys, [])
        // No numeric values, no alarms: no field of the five is numeric.
        for k in five { XCTAssertFalse(k.fields.contains { $0.numeric }, "\(k) records that it is on, no number") }
        // A cerebral oximeter starts bilateral; nothing else has a default.
        XCTAssertEqual(DeviceKind.cerebralOximetry.defaultSettings, ["side": "Bilateral"])
        XCTAssertEqual(DeviceKind.bronchialBlocker.defaultSettings, [:])
    }

    // MARK: The text in the list, the handoff and the summary

    func testTheListText() {
        func d(_ k: DeviceKind, _ site: String, detail: String = "", settings: [String: String] = [:], removed: Bool = false) -> PatientDevice {
            PatientDevice(kind: k, site: site, detail: detail, settings: settings, removed: removed)
        }
        XCTAssertEqual(d(.cerebralOximetry, "forehead", settings: ["side": "Bilateral"]).label, "Cerebral oximetry (bilateral)")
        XCTAssertEqual(d(.cerebralOximetry, "forehead", settings: ["side": "Left"]).label, "Cerebral oximetry (left)")
        XCTAssertEqual(d(.cerebralOximetry, "forehead", settings: ["side": "Right"]).label, "Cerebral oximetry (right)")
        XCTAssertEqual(d(.cerebralOximetry, "forehead").label, "Cerebral oximetry (bilateral)", "the default side")
        XCTAssertEqual(d(.cerebralOximetry, "forehead", detail: "INVOS", settings: ["side": "Bilateral"]).label, "Cerebral oximetry (bilateral, INVOS)")
        XCTAssertEqual(d(.cerebralOximetry, "forehead", removed: true).label, "Cerebral oximetry (bilateral, removed)")
        XCTAssertEqual(d(.teeProbe, "mouth-tee").label, "TEE probe")
        XCTAssertEqual(d(.teeProbe, "mouth-tee", detail: "midesophageal").label, "TEE probe (midesophageal)")
        XCTAssertEqual(d(.teeProbe, "mouth-tee", removed: true).label, "TEE probe (removed)")
        XCTAssertEqual(d(.defibPads, "defib-pads").label, "Defib pads")
        XCTAssertEqual(d(.processedEEG, "forehead-eeg").label, "BIS/SedLine", "no type chosen writes both")
        XCTAssertEqual(d(.processedEEG, "forehead-eeg", detail: "BIS").label, "BIS")
        XCTAssertEqual(d(.processedEEG, "forehead-eeg", detail: "SedLine").label, "SedLine")
        XCTAssertEqual(d(.processedEEG, "forehead-eeg", detail: "left forehead").label, "BIS/SedLine (left forehead)")
        XCTAssertEqual(d(.bronchialBlocker, "mouth-blocker").label, "Bronchial blocker")
        XCTAssertEqual(d(.bronchialBlocker, "mouth-blocker", detail: "Arndt", settings: ["side": "Left"]).label, "Bronchial blocker (left, Arndt)")
        XCTAssertEqual(d(.bronchialBlocker, "mouth-blocker", settings: ["side": "Right"]).label, "Bronchial blocker (right)")
    }

    func testTheDiagramTagsAreShort() {
        func tag(_ d: PatientDevice) -> String { PatientDiagramModel.tag(d) }
        XCTAssertEqual(tag(PatientDevice(kind: .cerebralOximetry, site: "forehead")), "NIRS")
        XCTAssertEqual(tag(PatientDevice(kind: .teeProbe, site: "mouth-tee")), "TEE probe")
        XCTAssertEqual(tag(PatientDevice(kind: .defibPads, site: "defib-pads")), "Defib pads")
        XCTAssertEqual(tag(PatientDevice(kind: .processedEEG, site: "forehead-eeg")), "BIS/SedLine")
        XCTAssertEqual(tag(PatientDevice(kind: .processedEEG, site: "forehead-eeg", detail: "BIS")), "BIS")
        XCTAssertEqual(tag(PatientDevice(kind: .processedEEG, site: "forehead-eeg", detail: "SedLine")), "SedLine")
        XCTAssertEqual(tag(PatientDevice(kind: .bronchialBlocker, site: "mouth-blocker")), "Blocker")
        XCTAssertEqual(tag(PatientDevice(kind: .bronchialBlocker, site: "mouth-blocker", settings: ["side": "Left"])), "Blocker L")
        XCTAssertEqual(tag(PatientDevice(kind: .bronchialBlocker, site: "mouth-blocker", settings: ["side": "Right"])), "Blocker R")
        for k in five { XCTAssertLessThanOrEqual(tag(PatientDevice(kind: k, site: "x")).count, 15, "fits the label column") }
    }

    func testTheHandoffAndTheSummaryListThemWithWhenTheyWentIn() throws {
        var r = PatientRecord()
        r.devices = [try device("Zoll pads on", intra: false), try device("NIRS", intra: true), try device("SedLine", intra: true),
                     try device("TEE probe in", intra: true), try device("Arndt blocker left", intra: true)]
        let handoff = try XCTUnwrap(PatientBriefs.handoff(r).first { $0.key == "lines" })
        for line in ["Defib pads (Pre)", "Cerebral oximetry (bilateral) (Intra)", "SedLine (Intra)", "TEE probe (Intra)", "Bronchial blocker (left, Arndt) (Intra)"] {
            XCTAssertTrue(handoff.text.contains(line), "the handoff says \(line): \(handoff.text)")
        }
        XCTAssertNotNil(handoff.figure, "drawn")
        // The Preprocedure Summary lists what the patient arrives with.
        let pre = try XCTUnwrap(PatientBriefs.preop(r).first { $0.key == "lines" })
        XCTAssertTrue(pre.text.contains("Defib pads"), pre.text)
        for gone in ["Cerebral oximetry", "SedLine", "TEE probe", "Bronchial blocker"] {
            XCTAssertFalse(pre.text.contains(gone), "\(gone) went in in the room: \(pre.text)")
        }
        // The same split as phase labels.
        let phases = PatientDevices.phaseLabels(r.devices)
        XCTAssertEqual(phases.map(\.phase), ["Pre", "Intra", "Intra", "Intra", "Intra"])
        XCTAssertEqual(phases.first?.lineText, "Defib pads (Pre)")
        XCTAssertEqual(r.currentDevices(arrivalOnly: true).map(\.kind), [.defibPads])
        // One taken out is not listed.
        r.devices[1].removed = true
        XCTAssertFalse(PatientDevices.labels(r.currentDevices()).contains { $0.contains("Cerebral oximetry") })
    }

    // MARK: Not vascular, not the airway

    func testTheFiveAreNotIVAccessALimbAlertOrAnArmLine() throws {
        var r = try cardiacRecord()
        r.radial.harvest = "both"
        XCTAssertTrue(PatientDeviceFills.limbAlerts(r).isEmpty)
        XCTAssertTrue(PatientDeviceFills.limbAlertGroups(r).isEmpty)
        XCTAssertNil(PatientDeviceFills.limbAlertText(r))
        for d in r.devices where five.contains(d.kind) { XCTAssertNil(PatientDeviceFills.limb(of: d), "\(d.kind)") }
        let items = PatientDiagramModel.items(r, phase: .all).items
        XCTAssertFalse(items.contains { $0.id.hasPrefix(PatientDiagramModel.limbAlertPrefix) }, "no limb alert marker")
        // None is on the harvest arm or counted among the lines in the arm.
        XCTAssertFalse(PatientStudies.linesOnHarvestArm(r).contains { five.contains($0.kind) })
        let access: Set<DeviceKind> = [.piv, .cvc, .picc, .intraosseous, .arterial, .dialysisCatheter]
        XCTAssertTrue(Set(five).isDisjoint(with: access))
        // A note that names them files no PIV or central line.
        let q = PatientNote.read("NIRS, BIS, TEE probe in, Zoll pads on", now: now)
        var rec = PatientRecord()
        PatientNote.apply(q.findings.map(\.change), to: &rec)
        XCTAssertFalse(rec.devices.contains { access.contains($0.kind) })
    }

    func testTheAirwayCourseTextIsTheSameWithAndWithoutThem() throws {
        var bare = PatientRecord()
        bare.mask = "easy"; bare.intubation = "easy"; bare.tube = "8.0 cuffed ETT (23 cm)"; bare.airwayAtEnd = "intubated"
        var withDevices = bare
        withDevices.devices = [try device("bronchial blocker left", intra: true), try device("TEE probe in", intra: true), try device("NIRS", intra: true)]
        let a = try XCTUnwrap(PatientSummary.airwayCourse(bare))
        let b = try XCTUnwrap(PatientSummary.airwayCourse(withDevices))
        XCTAssertEqual(a.text, b.text)
        XCTAssertEqual(PatientAirwayCourse.clauses(bare).clauses, PatientAirwayCourse.clauses(withDevices).clauses)
        // The ETT is still the airway; the blocker is listed with the lines.
        XCTAssertTrue(PatientDevices.labels(withDevices.currentDevices()).contains("Bronchial blocker (left)"))
    }

    // MARK: Sites and the diagram

    func testTheSitesAreInTheRightRegions() throws {
        func site(_ id: String) throws -> DeviceSite { try XCTUnwrap(DeviceSite.site(id: id), id) }
        XCTAssertEqual(try site("forehead").region, "head")
        XCTAssertEqual(try site("forehead-eeg").region, "head")
        XCTAssertEqual(try site("mouth-tee").region, "head")
        XCTAssertEqual(try site("mouth-blocker").region, "head")
        XCTAssertEqual(try site("defib-pads").region, "chest")
        XCTAssertEqual(try site("forehead").kinds, [.cerebralOximetry])
        XCTAssertEqual(try site("forehead-eeg").kinds, [.processedEEG])
        XCTAssertEqual(try site("mouth-tee").kinds, [.teeProbe])
        XCTAssertEqual(try site("mouth-blocker").kinds, [.bronchialBlocker])
        XCTAssertEqual(try site("defib-pads").kinds, [.defibPads])
        // Forehead above the mouth, the mouth above the chest; the BIS below the oximetry sensors.
        XCTAssertLessThan(try site("forehead").anchor.y, try site("forehead-eeg").anchor.y)
        XCTAssertLessThan(try site("forehead-eeg").anchor.y, try site("mouth").anchor.y)
        XCTAssertLessThan(try site("mouth-tee").anchor.y, try site("defib-pads").anchor.y)
        // Each kind's default site is its own.
        XCTAssertEqual(PatientDevices.defaultSite(for: .cerebralOximetry)?.site, "forehead")
        XCTAssertEqual(PatientDevices.defaultSite(for: .processedEEG)?.site, "forehead-eeg")
        XCTAssertEqual(PatientDevices.defaultSite(for: .teeProbe)?.site, "mouth-tee")
        XCTAssertEqual(PatientDevices.defaultSite(for: .bronchialBlocker)?.site, "mouth-blocker")
        XCTAssertEqual(PatientDevices.defaultSite(for: .defibPads)?.site, "defib-pads")
        for k in five { XCTAssertEqual(PatientDevices.defaultSite(for: k)?.sure, true) }
    }

    func testTheMarkersAreWhereTheySayAndOnNothingElse() throws {
        let r = try cardiacRecord()
        let items = PatientDiagramModel.items(r, phase: .all).items
        func item(_ kind: DeviceKind) throws -> DiagramItem {
            let d = try XCTUnwrap(r.devices.first { $0.kind == kind })
            return try XCTUnwrap(items.first { $0.id == d.id.uuidString }, "\(kind) is drawn")
        }
        // Forehead: the oximetry sensors, one either side of the midline (bilateral); the BIS below them, on the midline.
        let ox = try item(.cerebralOximetry)
        let oxId = try XCTUnwrap(r.devices.first { $0.kind == .cerebralOximetry }).id.uuidString
        let oxLeft = try XCTUnwrap(items.first { $0.id == oxId + "-left" })
        XCTAssertEqual(ox.anchor.x, 91, accuracy: 0.05)
        XCTAssertEqual(oxLeft.anchor.x, 109, accuracy: 0.05)
        XCTAssertEqual(ox.anchor.y, 13, accuracy: 0.05)
        XCTAssertEqual(ox.label, "NIRS")
        XCTAssertEqual(oxLeft.label, "", "one label for the two sensors")
        let eeg = try item(.processedEEG)
        XCTAssertEqual(eeg.anchor.x, 100, accuracy: 0.05)
        XCTAssertGreaterThan(eeg.anchor.y, ox.anchor.y + 5)
        XCTAssertEqual(eeg.label, "BIS")
        // The mouth: the TEE probe and the blocker either side of the tube's marker (100, 42).
        let tee = try item(.teeProbe), blocker = try item(.bronchialBlocker)
        XCTAssertLessThan(tee.anchor.x, 100)
        XCTAssertGreaterThan(blocker.anchor.x, 100)
        XCTAssertTrue((40...50).contains(tee.anchor.y) && (40...50).contains(blocker.anchor.y))
        XCTAssertEqual(tee.label, "TEE probe")
        XCTAssertEqual(blocker.label, "Blocker L")
        // The chest: the pads, one below the right clavicle and one at the apex.
        let pads = try item(.defibPads)
        let padsId = try XCTUnwrap(r.devices.first { $0.kind == .defibPads }).id.uuidString
        let apex = try XCTUnwrap(items.first { $0.id == padsId + "-apex" })
        XCTAssertTrue((85...115).contains(pads.anchor.y) && (85...115).contains(apex.anchor.y))
        XCTAssertLessThan(pads.anchor.x, 100)
        XCTAssertGreaterThan(apex.anchor.x, 100)
        XCTAssertEqual(pads.label, "Defib pads")
        // The ETT's own marker is drawn, with the A-line and the central line.
        XCTAssertNotNil(items.first { $0.id == "airway-ett" })

        // No marker is on another, and none is on a line drawn there (a marker is 5.2 across, a line about 2).
        let marked = items.filter { $0.marker != .none && !$0.id.hasPrefix(PatientDiagramModel.limbAlertPrefix) }
        XCTAssertGreaterThanOrEqual(marked.count, 10)
        for i in marked.indices {
            for j in marked.indices where j > i {
                XCTAssertGreaterThan(dist(marked[i].anchor, marked[j].anchor), 5.3, "\(marked[i].label) and \(marked[j].label) are apart")
            }
        }
        let ownIds = Set(r.devices.filter { five.contains($0.kind) }.map(\.id.uuidString))
        let newMarkers = items.filter { m in ownIds.contains { m.id == $0 || m.id.hasPrefix($0 + "-") } }
        XCTAssertEqual(newMarkers.count, 7, "the oximeter's two sensors, the EEG, the TEE probe, the blocker and the pads' two")
        for m in newMarkers {
            for o in items where o.id != m.id && !ownIds.contains(where: { o.id == $0 || o.id.hasPrefix($0 + "-") }) {
                let pts = [o.anchor] + o.course
                for k in 0..<max(0, pts.count - 1) {
                    XCTAssertGreaterThan(segmentDistance(m.anchor, pts[k], pts[k + 1]), 3.4, "\(m.label) is clear of \(o.label)'s line")
                }
            }
        }
    }

    func testOneSensorForLeftOrRightAndMovingTheDeviceMovesAllItsMarkers() throws {
        func record(_ ds: [PatientDevice]) -> PatientRecord {
            var r = PatientRecord()
            r.devices = ds
            return r
        }
        var left = try device("NIRS left")
        var items = PatientDiagramModel.items(record([left]), phase: .all).items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].anchor.x, 109, accuracy: 0.05, "the patient's left is on the viewer's right")
        left.settings["side"] = "Right"
        items = PatientDiagramModel.items(record([left]), phase: .all).items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].anchor.x, 91, accuracy: 0.05)
        // A drag moves the sensors with the device.
        var both = try device("cerebral oximetry")
        both.offset = CGPoint(x: 0.05, y: 0.02)
        let dragged = PatientDiagramModel.items(record([both]), phase: .all).items
        XCTAssertEqual(dragged.count, 2)
        let xs = dragged.map { $0.anchor.x }.sorted()
        XCTAssertEqual(xs[0], 101, accuracy: 0.05)
        XCTAssertEqual(xs[1], 119, accuracy: 0.05)
    }

    func testThePreoperativePictureDrawsOnlyWhatIsThereOnArrival() throws {
        var r = PatientRecord()
        r.devices = [try device("Zoll pads on", intra: false), try device("NIRS", intra: true)]
        let pre = PatientDiagramModel.items(r, phase: .preop).items
        XCTAssertEqual(pre.filter { $0.label == "Defib pads" }.count, 1)
        XCTAssertTrue(pre.filter { $0.label == "NIRS" }.isEmpty, "placed in the room")
        let all = PatientDiagramModel.items(r, phase: .all).items
        XCTAssertEqual(all.filter { $0.label == "NIRS" }.count, 1)
    }

    // MARK: Typing in the device field

    func testCerebralOximetryIsTyped() throws {
        for text in ["cerebral oximetry", "cerebral ox", "NIRS", "INVOS", "ForeSight", "Cerebral Oximeter"] {
            let p = try parse(text)
            XCTAssertEqual(p.kind, .cerebralOximetry, text)
            XCTAssertEqual(p.settings, ["side": "Bilateral"], text + ": bilateral when typed without a side")
            XCTAssertEqual(p.site, "forehead", text)
            XCTAssertEqual(p.confidence, 1, accuracy: 0.001, text)
        }
        XCTAssertEqual(try parse("NIRS left").settings, ["side": "Left"])
        XCTAssertEqual(try parse("cerebral oximetry R").settings, ["side": "Right"])
        XCTAssertEqual(try parse("NIRS bilateral").settings, ["side": "Bilateral"])
        XCTAssertEqual(try parse("NIRS L and R").settings, ["side": "Bilateral"])
        XCTAssertEqual(try parse("right NIRS").settings, ["side": "Right"])
        // A value typed beside it is not kept: the device only.
        let valued = try parse("NIRS 65")
        XCTAssertEqual(valued.settings, ["side": "Bilateral"])
        XCTAssertEqual(valued.detail, "")
        XCTAssertEqual(valued.device().label, "Cerebral oximetry (bilateral)")
    }

    func testTheTEEProbeIsTypedAndTEEFindingsAreNot() throws {
        for text in ["TEE probe", "TEE probe in", "TEE in place", "tee probe in place"] {
            let p = try parse(text)
            XCTAssertEqual(p.kind, .teeProbe, text)
            XCTAssertEqual(p.site, "mouth-tee", text)
            XCTAssertEqual(p.settings, [:], text)
            XCTAssertEqual(p.device().label, "TEE probe", text)
        }
        for text in ["TEE", "TEE:", "for TEE", "TEE showed severe AS", "preop TEE", "TEE: EF 55%"] {
            XCTAssertNotEqual(PatientDevices.parse(text)?.kind, .teeProbe, text + " is an echo, not the probe")
            XCTAssertNil(PatientDevices.parseMonitor(text), text)
        }
    }

    func testDefibPadsAreTypedAndAnICDIsNot() throws {
        for text in ["Zoll pads", "defib pads", "defibrillator pads", "pads on", "R2 pads", "external pads", "Zoll pads on", "external defibrillator pads"] {
            let p = try parse(text)
            XCTAssertEqual(p.kind, .defibPads, text)
            XCTAssertEqual(p.site, "defib-pads", text)
            XCTAssertEqual(p.device().label, "Defib pads", text)
        }
        XCTAssertEqual(try parse("ICD").kind, .cied, "the implanted device")
        XCTAssertEqual(try parse("defibrillator").kind, .cied)
        XCTAssertNotEqual(PatientDevices.parse("pads")?.kind, .defibPads, "pads alone are knee pads or lap pads")
        XCTAssertNotEqual(PatientDevices.parse("knee pads")?.kind, .defibPads)
    }

    func testBISAndSedLineAreTypedWithTheirTypeAndNoNumber() throws {
        XCTAssertEqual(try parse("BIS").detail, "BIS")
        XCTAssertEqual(try parse("BIS monitor").detail, "BIS")
        XCTAssertEqual(try parse("SedLine").detail, "SedLine")
        XCTAssertEqual(try parse("sed line").detail, "SedLine")
        XCTAssertEqual(try parse("processed EEG").detail, "")
        for text in ["BIS", "BIS monitor", "SedLine", "processed EEG"] {
            XCTAssertEqual(try parse(text).kind, .processedEEG, text)
            XCTAssertEqual(try parse(text).site, "forehead-eeg", text)
        }
        XCTAssertEqual(try parse("processed EEG").device().label, "BIS/SedLine", "none chosen writes both")
        let valued = try parse("BIS 45")
        XCTAssertEqual(valued.kind, .processedEEG)
        XCTAssertEqual(valued.detail, "BIS", "BIS 45 does not record the 45")
        XCTAssertEqual(valued.settings, [:])
        XCTAssertEqual(valued.device().label, "BIS")
        XCTAssertFalse(valued.device().label.contains("45"))
    }

    func testTheBronchialBlockerIsTypedWithASideAndItsProductName() throws {
        for text in ["bronchial blocker", "blocker", "Arndt", "EZ-blocker", "Cohen blocker", "Uniblocker"] {
            let p = try parse(text)
            XCTAssertEqual(p.kind, .bronchialBlocker, text)
            XCTAssertEqual(p.site, "mouth-blocker", text)
        }
        XCTAssertEqual(try parse("bronchial blocker").settings, [:], "no side unless one is typed")
        XCTAssertEqual(try parse("bronchial blocker").detail, "")
        XCTAssertEqual(try parse("left bronchial blocker").settings, ["side": "Left"])
        XCTAssertEqual(try parse("bronchial blocker R").settings, ["side": "Right"])
        XCTAssertEqual(try parse("blocker left").settings, ["side": "Left"])
        // The product name typed stays in the detail.
        XCTAssertEqual(try parse("Arndt").detail, "Arndt")
        XCTAssertEqual(try parse("EZ-blocker").detail, "EZ-Blocker")
        XCTAssertEqual(try parse("Cohen blocker").detail, "Cohen")
        XCTAssertEqual(try parse("Uniblocker").detail, "Uniblocker")
        let arndt = try parse("Arndt blocker left")
        XCTAssertEqual(arndt.detail, "Arndt")
        XCTAssertEqual(arndt.settings, ["side": "Left"])
        XCTAssertEqual(arndt.device().label, "Bronchial blocker (left, Arndt)")
    }

    func testAnotherDeviceInTheEntryIsStillThatDevice() throws {
        XCTAssertEqual(try parse("A-line NIRS").kind, .arterial, "read as before")
        XCTAssertEqual(try parse("RIJ CVL with BIS").kind, .cvc)
        // Other words typed are kept in the detail, with less confidence.
        let extra = try parse("TEE probe midesophageal")
        XCTAssertEqual(extra.kind, .teeProbe)
        XCTAssertEqual(extra.detail, "midesophageal")
        XCTAssertLessThan(extra.confidence, 1)
    }

    // MARK: Typing in the bar and the note reader

    func testTheNoteReaderFilesEachPhrase() {
        let cases: [(String, String)] = [
            ("cerebral oximetry", "Cerebral oximetry (bilateral)"), ("cerebral ox", "Cerebral oximetry (bilateral)"),
            ("NIRS", "Cerebral oximetry (bilateral)"), ("INVOS", "Cerebral oximetry (bilateral)"), ("ForeSight", "Cerebral oximetry (bilateral)"),
            ("NIRS left", "Cerebral oximetry (left)"),
            ("TEE probe", "TEE probe"), ("TEE probe in", "TEE probe"), ("TEE in place", "TEE probe"),
            ("Zoll pads", "Defib pads"), ("defib pads", "Defib pads"), ("defibrillator pads", "Defib pads"), ("pads on", "Defib pads"),
            ("R2 pads", "Defib pads"), ("external pads", "Defib pads"), ("Zoll pads on", "Defib pads"),
            ("BIS", "BIS"), ("BIS monitor", "BIS"), ("SedLine", "SedLine"), ("processed EEG", "BIS/SedLine"), ("BIS 45", "BIS"),
            ("bronchial blocker", "Bronchial blocker"), ("bronchial blocker left", "Bronchial blocker (left)"),
            ("blocker", "Bronchial blocker"), ("Arndt", "Bronchial blocker (Arndt)"), ("Arndt blocker", "Bronchial blocker (Arndt)"),
            ("EZ-blocker", "Bronchial blocker (EZ-Blocker)"), ("Cohen blocker", "Bronchial blocker (Cohen)"),
            ("Uniblocker", "Bronchial blocker (Uniblocker)"), ("blocker L", "Bronchial blocker (left)"),
        ]
        for (text, label) in cases {
            XCTAssertEqual(labels(text), [label], text)
        }
    }

    func testTheNoteReaderFilesNothingForNegationsAndPlans() {
        for text in ["no TEE probe", "no Zoll pads", "no bronchial blocker", "no NIRS", "will place a bronchial blocker",
                     "plan NIRS", "plan for BIS", "TEE probe planned", "will place a blocker for OLV"] {
            XCTAssertEqual(labels(text), [], text)
        }
    }

    func testTheNoteReaderLeavesTEEFindingsAndDrugsAlone() {
        for text in ["TEE: EF 55%, no MR", "for TEE", "TEE showed severe AS", "preop TEE", "TEE tomorrow"] {
            XCTAssertEqual(labels(text), [], text)
        }
        // A beta blocker is a drug, even in a sentence about the airway.
        XCTAssertFalse(labels("on beta blocker, intubated with ETT 8.0").contains { $0.contains("blocker") })
        XCTAssertFalse(labels("takes a calcium channel blocker, ETT 7.5").contains { $0.contains("blocker") })
        XCTAssertEqual(labels("Dr. Arndt saw the patient"), [])
        // An implanted ICD is not pads, and pads are not an ICD in the history.
        XCTAssertFalse(labels("ICD in place").contains { $0.contains("pads") })
        let pads = PatientNote.read("defibrillator pads on", now: now)
        XCTAssertFalse(pads.findings.contains { $0.id == "problem:icd" }, "external pads are not an implanted ICD")
        XCTAssertTrue(PatientNote.read("has an ICD", now: now).findings.contains { $0.id == "problem:icd" })
    }

    func testABlockerWithTheTubeItGoesThrough() {
        XCTAssertTrue(labels("ETT 8.0 with bronchial blocker").contains("Bronchial blocker"))
        XCTAssertTrue(labels("ETT 8.0 with blocker").contains("Bronchial blocker"), "an airway word beside the bare word")
        XCTAssertTrue(labels("bronchial blocker through single lumen ETT").contains("Bronchial blocker"))
        XCTAssertTrue(labels("Arndt blocker left via ETT").contains("Bronchial blocker (left, Arndt)"))
        let r = PatientNote.read("bronchial blocker through single lumen ETT", now: now)
        XCTAssertTrue(r.findings.contains { $0.id == "airway" || $0.id.hasPrefix("airway") }, "the tube is still the airway")
    }

    func testTheBarReadsTheFourItemsAndPlacesThemByTab() {
        let line = "NIRS, BIS, TEE probe in, Zoll pads on"
        let pre = QuickAdd.read(line, record: PatientRecord(), tab: .preop, now: now, choices: [:])
        var rec = PatientRecord()
        PatientNote.apply(pre.findings.map(\.change), to: &rec)
        XCTAssertEqual(Set(rec.devices.map(\.kind)), [.cerebralOximetry, .processedEEG, .teeProbe, .defibPads])
        XCTAssertEqual(rec.devices.count, 4)
        XCTAssertTrue(rec.devices.allSatisfy { !$0.placedIntraop }, "on arrival from the Preoperative tab")
        XCTAssertEqual(rec.devices.first { $0.kind == .cerebralOximetry }?.settings["side"], "Bilateral")
        XCTAssertEqual(rec.devices.first { $0.kind == .processedEEG }?.detail, "BIS")

        let intra = QuickAdd.read(line, record: PatientRecord(), tab: .intraop, now: now, choices: [:])
        var room = PatientRecord()
        PatientNote.apply(intra.findings.map(\.change), to: &room)
        XCTAssertEqual(room.devices.count, 4)
        XCTAssertTrue(room.devices.allSatisfy(\.placedIntraop), "placed in the room from the Intraoperative tab")

        // Said again, they are not added twice.
        let again = QuickAdd.read(line, record: rec, tab: .preop, now: now, choices: [:])
        PatientNote.apply(again.findings.map(\.change), to: &rec)
        XCTAssertEqual(rec.devices.count, 4)
    }

    func testTheNewAbbreviationsAreNotAskedAbout() {
        for t in ["NIRS", "BIS", "INVOS"] { XCTAssertNil(MedAbbreviations.candidate(t), t + " is known") }
    }

    // MARK: Saved records

    func testRecordsWithoutThemStillOpenAndTheNewKindsRoundTrip() throws {
        let old = #"{"devices":[{"kind":"piv","site":"antecubital-right","size":"20"},{"kind":"epicardialWires","site":"epicardial-exit","settings":{"chambers":"both"}}]}"#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(old.utf8))
        XCTAssertEqual(r.devices.map(\.kind), [.piv, .epicardialWires])
        XCTAssertEqual(r.devices.last?.label, "Epicardial pacing wires (atrial + ventricular)")

        let cardiac = try cardiacRecord()
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(cardiac))
        XCTAssertEqual(back.devices, cardiac.devices)
        XCTAssertEqual(Set(back.devices.map(\.kind)).intersection(five), Set(five))
        for k in five {
            let d = PatientDevice(kind: k, site: DeviceSite.all.first { $0.kinds.contains(k) }?.id ?? "")
            XCTAssertEqual(try JSONDecoder().decode(PatientDevice.self, from: JSONEncoder().encode(d)), d)
        }
    }

    /// What an older build does with a record that holds one of the five: its DeviceKind does not know the raw value, and an
    /// unknown kind is read as Other (it lists "Other", does not draw it because the site is unknown to it, and does not crash).
    func testAKindThisBuildDoesNotKnowIsOther() throws {
        for raw in ["futureMonitor", "cerebralOximetry2"] {
            let json = #"{"kind":"\#(raw)","site":"forehead","settings":{"side":"Left"}}"#
            let d = try JSONDecoder().decode(PatientDevice.self, from: Data(json.utf8))
            XCTAssertEqual(d.kind, .other)
            XCTAssertEqual(d.settings["side"], "Left", "its settings are kept")
        }
    }

    // MARK: The grouped picker

    func testThePickerGroupsTheOtherList() {
        let groups = DeviceKind.pickerGroups
        XCTAssertEqual(groups.map(\.title), ["Airway", "Monitors", "Pacing & pads", "Support", "Regional", "Access & drains", "Other"])
        XCTAssertEqual(groups[0].entries.map(\.title), ["Tracheostomy", "Double-lumen tube", "Bronchial blocker"])
        XCTAssertEqual(groups[1].entries.map(\.title), ["TEE probe", "Cerebral oximetry", "BIS/SedLine"])
        XCTAssertEqual(groups[2].entries.map(\.title), ["Epicardial pacing wires", "Pacemaker/ICD", "Defib pads"])
        XCTAssertEqual(groups[3].entries.map(\.kind), [.ecmoDrainage, .ecmoReturn, .lvad, .iabp, .impella, .protekDuo])
        XCTAssertEqual(groups[4].entries.map(\.kind), [.epidural, .spinal, .block, .perineuralCatheter])
        XCTAssertEqual(groups[5].entries.map(\.kind), [.picc, .intraosseous, .dialysisCatheter, .avFistula, .foley, .chestTube])
        XCTAssertEqual(groups[6].entries.map(\.kind), [.other])
        for g in groups { XCTAssertFalse(g.entries.isEmpty, g.title) }
    }

    func testEveryKindIsOfferedExactlyOnceAndNothingOfferedBeforeIsMissing() {
        let entries = DeviceKind.pickerGroups.flatMap(\.entries)
        let kinds = entries.filter { $0.detail.isEmpty }.map(\.kind)
        XCTAssertEqual(kinds.count, Set(kinds).count, "no kind twice")
        XCTAssertEqual(kinds, DeviceKind.more, "the flat list is the grouped one in order")
        XCTAssertEqual(Set(kinds + DeviceKind.buttons), Set(DeviceKind.allCases), "every kind, the five new ones included")
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count, "unique rows")
        // What the Other list offered in 1.11.
        let before: [DeviceKind] = [.ecmoDrainage, .ecmoReturn, .trach, .picc, .intraosseous, .lvad, .iabp, .impella, .protekDuo, .epidural, .spinal,
                                    .block, .perineuralCatheter, .foley, .epicardialWires, .cied, .avFistula, .dialysisCatheter, .chestTube, .other]
        for k in before { XCTAssertTrue(kinds.contains(k), "\(k) is still offered") }
        for k in five { XCTAssertTrue(kinds.contains(k), "\(k) is offered") }
        XCTAssertEqual(DeviceKind.buttons, [.piv, .arterial, .cvc, .pac, .ett], "the five buttons are as they were")
        // The double-lumen tube is the one row that is not a kind of its own: an ETT with the DLT detail.
        let extra = entries.filter { !$0.detail.isEmpty }
        XCTAssertEqual(extra.count, 1)
        XCTAssertEqual(extra.first?.title, "Double-lumen tube")
        XCTAssertEqual(extra.first?.kind, .ett)
        XCTAssertEqual(extra.first?.detail, "DLT")
        XCTAssertFalse(DeviceKind.more.contains(.ett), "ETT stays a button")
    }

    func testTheDoubleLumenTubeAddsAnETTWithTheDLTDetail() throws {
        // The same device typing "DLT" reads.
        let typed = try parse("DLT")
        XCTAssertEqual(typed.kind, .ett)
        XCTAssertEqual(typed.detail, "DLT")
        let entry = try XCTUnwrap(DeviceKind.pickerGroups.flatMap(\.entries).first { $0.title == "Double-lumen tube" })
        XCTAssertEqual(entry.detail, typed.detail)
        // Its fields are the tube's: the side as Left/Right DLT, the size (in Fr for a DLT) and the depth.
        XCTAssertTrue(DeviceKind.ett.fields.contains { $0.id == "detail" && $0.choices.contains("Left DLT") && $0.choices.contains("Right DLT") })
        XCTAssertTrue(DeviceKind.ett.fields.contains { $0.id == "depth" })

        var tube = PatientDevice(kind: .ett, site: "mouth", size: "37", detail: "Left DLT", placedIntraop: false)
        tube.settings["depth"] = "29"
        XCTAssertEqual(tube.label, "Left DLT 37 Fr at 29 cm")
        // On arrival: the current airway is an ETT that keeps its DLT words and its size in Fr.
        var pre = PatientRecord()
        PatientDevices.setTube(tube, in: &pre, preop: true)
        XCTAssertEqual(pre.currentAirway, "ett")
        XCTAssertEqual(pre.ettSize, "Left DLT 37 Fr")
        XCTAssertEqual(pre.ettDepth, "29 cm")
        XCTAssertEqual(pre.currentAirwayText, "ETT Left DLT 37 Fr at 29 cm")
        XCTAssertEqual(PatientDiagramModel.items(pre, phase: .preop).items.first { $0.id == "airway-ett" }?.label, "DLT 37 @29")
        // In the room: the Tube field says it as it is written.
        var room = PatientRecord()
        PatientDevices.setTube(tube, in: &room, preop: false)
        XCTAssertEqual(room.tube, "Left DLT 37 Fr at 29 cm")
        XCTAssertEqual(PatientDiagramModel.items(room, phase: .all).items.first { $0.id == "airway-ett" }?.label, "DLT 37 @29")
        // No side and no size yet: just the DLT.
        var bare = PatientRecord()
        PatientDevices.setTube(PatientDevice(kind: .ett, site: "mouth", detail: "DLT"), in: &bare, preop: true)
        XCTAssertEqual(bare.currentAirway, "ett")
        XCTAssertEqual(bare.ettSize, "DLT")
    }

    func testAnETTWithoutTheDLTDetailIsSetAsBefore() {
        let ett = PatientDevice(kind: .ett, site: "mouth", size: "7.5", settings: ["depth": "23"])
        var pre = PatientRecord()
        PatientDevices.setTube(ett, in: &pre, preop: true)
        XCTAssertEqual([pre.currentAirway, pre.ettSize, pre.ettDepth], ["ett", "7.5", "23 cm"])
        var room = PatientRecord()
        PatientDevices.setTube(ett, in: &room, preop: false)
        XCTAssertEqual(room.tube, "7.5 ETT, 23 cm")
        var none = PatientRecord()
        PatientDevices.setTube(PatientDevice(kind: .ett, site: "mouth"), in: &none, preop: false)
        XCTAssertEqual(none.tube, "ETT")
    }

    func testEpicardialWiresByTypingAndByThePicker() throws {
        // Typed.
        XCTAssertEqual(try parse("epicardial wires A and V").settings["chambers"], "both")
        XCTAssertEqual(try parse("atrial wires").settings["chambers"], "atrial")
        XCTAssertEqual(try parse("V wires").settings["chambers"], "ventricular")
        XCTAssertEqual(try parse("pacing wires").kind, .epicardialWires)
        XCTAssertEqual(try parse("pacing wires").settings, [:], "the chambers are not guessed")
        XCTAssertEqual(try parse("epicardial wires A and V").site, "epicardial-exit")
        // By the picker: the existing kind, its chambers field first (Atrial, Ventricular or Both).
        let entry = try XCTUnwrap(DeviceKind.pickerGroups.flatMap(\.entries).first { $0.title == "Epicardial pacing wires" })
        XCTAssertEqual(entry.kind, .epicardialWires)
        XCTAssertEqual(entry.detail, "")
        let first = try XCTUnwrap(DeviceKind.epicardialWires.fields.first)
        XCTAssertEqual(first.id, "chambers")
        XCTAssertEqual(first.choices, ["atrial", "ventricular", "both"])
        var wires = PatientDevice(kind: .epicardialWires, site: "epicardial-exit")
        XCTAssertEqual(wires.label, "Epicardial pacing wires")
        wires.setValue("both", for: "chambers")
        XCTAssertEqual(wires.label, "Epicardial pacing wires (atrial + ventricular)")
        wires.setValue("atrial", for: "chambers")
        XCTAssertEqual(wires.label, "Epicardial pacing wires (atrial)")
        XCTAssertTrue(DeviceKind.epicardialWires.isTemporaryPacing, "still temporary pacing for the ECG link")
        XCTAssertFalse(DeviceKind.defibPads.isTemporaryPacing, "external pads are not epicardial wires")
    }
}
