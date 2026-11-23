import XCTest
import CoreGraphics
@testable import PeriopSignal

/// 1.15 (Ben, Nov 23): "Add ostomies, peg tube, G-tube to lines and devices. Add other items similar to this I may have missed". He chose
/// all four families (feeding and gastric tubes; urinary tubes and stomas; surgical drains; neuro and implanted devices) and "Draw them" on
/// the body diagram. Sixteen new kinds, their sites, the picker's new groups, the handoff words and the typed vocabulary.
final class Devices115Tests: XCTestCase {

    // MARK: Helpers

    private let added = DeviceKind.added115

    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 8))! }

    private func parse(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> DeviceParse {
        try XCTUnwrap(PatientDevices.parse(text), "no parse for \"\(text)\"", file: file, line: line)
    }

    /// The handoff text of the device a typed entry makes.
    private func typed(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        try parse(text, file: file, line: line).device().label
    }

    /// The device findings (their handoff text) the note reader files for a sentence.
    private func noted(_ text: String) -> [String] {
        PatientNote.read(text, now: now).findings.filter { $0.id.hasPrefix("device:") }.map(\.label)
    }

    private func d(_ kind: DeviceKind, _ site: String = "", side: String? = nil, size: String = "", detail: String = "",
                   settings: [String: String] = [:], removed: Bool = false) -> PatientDevice {
        PatientDevice(kind: kind, site: site, side: side, size: size, detail: detail, settings: settings, removed: removed)
    }

    // MARK: The sixteen kinds

    func testTheSixteenKindsAreCompleteAndNamedAsBriefed() {
        XCTAssertEqual(added.map(\.rawValue), ["gastricTube", "feedingTube", "ostomy", "rectalTube", "nephrostomy", "ureteralStent", "surgicalDrain",
                                                "woundVac", "pdCatheter", "evd", "lumbarDrain", "vpShunt", "port", "intrathecalPump", "neurostimulator",
                                                "insulinPump"])
        XCTAssertEqual(added.map(\.label), ["NG/OG tube", "PEG/G-tube", "Ostomy", "Rectal tube", "Nephrostomy tube", "Ureteral stent", "Drain",
                                             "Wound vac", "PD catheter", "EVD", "Lumbar drain", "VP shunt", "Port", "Intrathecal pump", "Nerve stimulator",
                                             "Insulin pump/CGM"])
        XCTAssertEqual(Set(added).count, 16)
        for k in added {
            XCTAssertTrue(DeviceKind.allCases.contains(k))
            XCTAssertFalse(k.label.isEmpty, "\(k) has a label")
            XCTAssertFalse(k.name.isEmpty, "\(k) has a name")
            XCTAssertFalse(k.fields.isEmpty, "\(k) asks for something")
            XCTAssertEqual(DeviceKind(rawValue: k.rawValue), k)
            XCTAssertTrue(DeviceKind.more.contains(k), "\(k) is in the picker")
        }
    }

    func testColourRolesReuseTheExistingOnes() {
        // Tubes, drains, stomas, the wound vac, the EVD and the lumbar drain: the drain role; a port: central; the implanted devices that are not
        // lines, and the ureteral stent: the monitors' role. No role was added.
        for k in [DeviceKind.gastricTube, .feedingTube, .ostomy, .rectalTube, .nephrostomy, .surgicalDrain, .woundVac, .pdCatheter, .evd, .lumbarDrain] {
            XCTAssertEqual(k.colorRole, .drain, "\(k)")
        }
        XCTAssertEqual(DeviceKind.port.colorRole, .central)
        for k in [DeviceKind.vpShunt, .intrathecalPump, .neurostimulator, .insulinPump, .ureteralStent] { XCTAssertEqual(k.colorRole, .monitor, "\(k)") }
        XCTAssertEqual(DeviceColorRole.allCases.count, 13, "no colour was added")
    }

    func testSizesAndFields() {
        XCTAssertEqual([DeviceKind.gastricTube, .feedingTube, .nephrostomy, .surgicalDrain].map(\.sizeUnit), ["Fr", "Fr", "Fr", "Fr"])
        for k in added where ![.gastricTube, .feedingTube, .nephrostomy, .surgicalDrain].contains(k) { XCTAssertEqual(k.sizeUnit, "", "\(k) has no size") }
        func choices(_ k: DeviceKind, _ id: String) -> [String]? { k.fields.first { $0.id == id }?.choices }
        XCTAssertEqual(choices(.gastricTube, "size"), ["10", "12", "14", "16", "18"])
        XCTAssertEqual(choices(.gastricTube, "detail"), ["NG", "OG", "Dobhoff"])
        XCTAssertEqual(choices(.gastricTube, "notes"), ["to suction", "clamped", "feeds"])
        XCTAssertEqual(choices(.feedingTube, "size"), ["14", "16", "18", "20", "24"])
        XCTAssertEqual(choices(.feedingTube, "detail"), ["PEG", "G-tube", "GJ-tube", "J-tube"])
        XCTAssertEqual(choices(.ostomy, "detail"), ["Colostomy", "Ileostomy", "Urostomy", "Mucous fistula"])
        XCTAssertNil(choices(.ostomy, "size"))
        XCTAssertNil(choices(.rectalTube, "size"))
        XCTAssertEqual(choices(.rectalTube, "detail"), [], "no types: the detail is its note")
        XCTAssertEqual(choices(.nephrostomy, "size"), ["8", "10", "12"])
        XCTAssertEqual(choices(.surgicalDrain, "size"), ["10", "15", "19"])
        XCTAssertEqual(choices(.surgicalDrain, "detail"), ["JP", "Blake", "Penrose", "Hemovac", "Biliary (T-tube)", "Percutaneous"])
        XCTAssertEqual(choices(.surgicalDrain, "notes"), ["to bulb suction", "to gravity"])
        XCTAssertEqual(choices(.evd, "detail"), ["open", "clamped"])
        XCTAssertEqual(choices(.lumbarDrain, "detail"), ["open", "clamped"])
        XCTAssertEqual(choices(.vpShunt, "detail"), ["programmable"])
        XCTAssertEqual(choices(.port, "detail"), ["accessed", "not accessed"])
        XCTAssertEqual(choices(.intrathecalPump, "detail"), ["baclofen", "opioid"])
        XCTAssertEqual(choices(.neurostimulator, "detail"), ["Spinal cord stimulator", "Deep brain stimulator", "Vagal nerve stimulator", "Sacral nerve stimulator"])
        XCTAssertEqual(choices(.insulinPump, "detail"), ["Insulin pump", "Glucose sensor"])
        // The types are the kind's typeChoices, and the others have none.
        XCTAssertEqual(DeviceKind.gastricTube.typeChoices, ["NG", "OG", "Dobhoff"])
        for k in [DeviceKind.rectalTube, .nephrostomy, .ureteralStent, .woundVac, .pdCatheter, .evd, .lumbarDrain, .vpShunt, .port, .intrathecalPump] {
            XCTAssertTrue(k.typeChoices.isEmpty, "\(k) has no types")
        }
    }

    // MARK: The picker

    func testThePickerGroupsAfterRegionalAndEveryNewKindIsInExactlyOne() {
        let groups = DeviceKind.pickerGroups
        XCTAssertEqual(groups.map(\.title), ["Airway", "Monitors", "Pacing & pads", "Support", "Regional", "Access", "GI", "Urinary", "Drains", "Neuro", "Other"])
        XCTAssertEqual(groups[5].entries.map(\.title), ["PICC", "Intraosseous (IO)", "HD catheter", "AV fistula or graft", "Port"])
        XCTAssertEqual(groups[6].entries.map(\.title), ["NG/OG tube", "PEG/G-tube", "J-tube", "Ostomy", "Rectal tube"])
        XCTAssertEqual(groups[7].entries.map(\.title), ["Foley", "Nephrostomy tube", "Ureteral stent"])
        XCTAssertEqual(groups[8].entries.map(\.title), ["Chest tube", "Surgical drain", "Wound vac", "PD catheter"])
        XCTAssertEqual(groups[9].entries.map(\.title), ["EVD", "Lumbar drain", "VP shunt", "Intrathecal pump", "Nerve stimulator"])
        XCTAssertEqual(groups[10].entries.map(\.title), ["Insulin pump/CGM", "Other"])
        // The old group is gone, and the page's five type buttons are as they were.
        XCTAssertFalse(groups.contains { $0.title == "Access & drains" })
        XCTAssertEqual(DeviceKind.buttons, [.piv, .arterial, .cvc, .pac, .ett])
        for k in added {
            let inGroups = groups.filter { g in g.entries.contains { $0.kind == k && $0.detail.isEmpty } }
            XCTAssertEqual(inGroups.count, 1, "\(k) is in exactly one group")
            XCTAssertEqual(DeviceKind.more.filter { $0 == k }.count, 1, "\(k) is in the flat list once")
        }
    }

    func testTheJTubeRowAddsAFeedingTubeWithTheJTubeType() throws {
        let row = try XCTUnwrap(DeviceKind.pickerGroups.flatMap(\.entries).first { $0.title == "J-tube" })
        XCTAssertEqual(row.kind, .feedingTube)
        XCTAssertEqual(row.detail, "J-tube")
        XCTAssertEqual(row.id, "feedingTube:J-tube")
        // The same device typing "J-tube" makes, and it prints as the type.
        let typed = try parse("J-tube")
        XCTAssertEqual(typed.kind, .feedingTube)
        XCTAssertEqual(typed.detail, row.detail)
        XCTAssertEqual(d(.feedingTube, "upper-abdomen-left", side: "left", detail: row.detail).label, "J-tube LUQ")
    }

    // MARK: Sites

    func testTheNewSitesAreOnTheBodyAndApart() throws {
        let new: Set<String> = ["nose-gastric", "mouth-og", "frontal", "neck", "sternum", "upper-abdomen", "abdomen", "lower-abdomen", "flank", "groin", "perineum"]
        let all = DeviceSite.all
        XCTAssertEqual(Set(all.filter { new.contains($0.base) }.map(\.base)), new)
        XCTAssertEqual(all.filter { new.contains($0.base) }.count, 17, "five single sites and six pairs")
        for s in all {
            XCTAssertTrue((0...1).contains(s.anchor.x) && (0...1).contains(s.anchor.y), "\(s.id) is inside the figure")
        }
        // No two sites in the same view share an anchor, and each new site is at least 6 figure units from every other.
        for (i, a) in all.enumerated() {
            for b in all[(i + 1)...] {
                if a.back == b.back { XCTAssertNotEqual(a.anchor, b.anchor, "\(a.id) and \(b.id) are in one place") }
                if new.contains(a.base) || new.contains(b.base) {
                    XCTAssertGreaterThanOrEqual(Double(a.distance(to: b.anchor)), 5.99, "\(a.id) and \(b.id) are apart")
                }
            }
        }
        // The abdomen: the quadrants print as the abbreviations, the right on the viewer's left.
        for (id, short) in [("upper-abdomen-right", "RUQ"), ("upper-abdomen-left", "LUQ"), ("lower-abdomen-right", "RLQ"), ("lower-abdomen-left", "LLQ")] {
            let s = try XCTUnwrap(DeviceSite.site(id: id), id)
            XCTAssertEqual(s.short, short)
            XCTAssertEqual(s.brief, short)
            XCTAssertEqual(s.region, "abdomen")
        }
        XCTAssertLessThan(try XCTUnwrap(DeviceSite.site(id: "upper-abdomen-right")).anchor.x, 0.5)
        XCTAssertLessThan(try XCTUnwrap(DeviceSite.site(id: "upper-abdomen-right")).anchor.y, try XCTUnwrap(DeviceSite.site(id: "lower-abdomen-right")).anchor.y)
        XCTAssertEqual(DeviceSite.site(id: "upper-abdomen-left")?.name, "Left upper abdomen")
        XCTAssertNil(DeviceSite.site(id: "abdomen")?.side, "the midline abdomen")
        XCTAssertNil(DeviceSite.site(id: "sternum")?.side)
        // The perineum is midline and below the urethral site; the flank is on the back view, as the lumbar spine is.
        XCTAssertGreaterThan(try XCTUnwrap(DeviceSite.site(id: "perineum")).anchor.y, try XCTUnwrap(DeviceSite.site(id: "urethral")).anchor.y)
        XCTAssertEqual(DeviceSite.site(id: "perineum")?.anchor.x ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(DeviceSite.site(id: "flank-right")?.back, true)
        XCTAssertEqual(DeviceSite.site(id: "flank-left")?.back, true)
        XCTAssertEqual(DeviceSite.site(id: "lumbar-spine")?.back, true)
        XCTAssertEqual(DeviceSite.site(id: "upper-abdomen-right")?.back, false)
        // The frontal scalp is a pair of its own, not the scalp vein's; the NG and OG sites do not sit on the ETT's.
        XCTAssertEqual(DeviceSite.site(id: "frontal-left")?.kinds, [.evd, .vpShunt])
        XCTAssertFalse(DeviceSite.site(id: "scalp-right")?.kinds.contains(.evd) ?? true)
        for id in ["nose-gastric", "mouth-og"] {
            let s = try XCTUnwrap(DeviceSite.site(id: id))
            XCTAssertEqual(s.kinds, [.gastricTube])
            for ett in ["nose", "mouth"] { XCTAssertGreaterThanOrEqual(Double(s.distance(to: try XCTUnwrap(DeviceSite.site(id: ett)).anchor)), 6, "\(id) and \(ett)") }
        }
    }

    func testEachKindsSitesAreTheBriefedOnes() {
        func sites(_ k: DeviceKind) -> Set<String> { Set(DeviceSite.all.filter { $0.kinds.contains(k) }.map(\.id)) }
        let quadrants: Set<String> = ["upper-abdomen-right", "upper-abdomen-left", "lower-abdomen-right", "lower-abdomen-left"]
        XCTAssertEqual(sites(.gastricTube), ["nose-gastric", "mouth-og"])
        XCTAssertEqual(sites(.feedingTube), quadrants.union(["abdomen"]))
        XCTAssertEqual(sites(.ostomy), quadrants.union(["abdomen"]))
        XCTAssertEqual(sites(.rectalTube), ["perineum"])
        XCTAssertEqual(sites(.nephrostomy), ["flank-right", "flank-left"])
        XCTAssertEqual(sites(.ureteralStent), ["flank-right", "flank-left"])
        XCTAssertEqual(sites(.surgicalDrain), quadrants.union(["neck-right", "neck-left", "lateral-chest-right", "lateral-chest-left", "groin-right", "groin-left"]))
        XCTAssertEqual(sites(.woundVac), quadrants.union(["sternum", "abdomen", "groin-right", "groin-left", "thigh-right", "thigh-left"]))
        XCTAssertEqual(sites(.pdCatheter), ["lower-abdomen-right", "lower-abdomen-left"])
        XCTAssertEqual(sites(.evd), ["frontal-right", "frontal-left"])
        XCTAssertEqual(sites(.vpShunt), ["frontal-right", "frontal-left"])
        XCTAssertEqual(sites(.lumbarDrain), ["lumbar-spine"])
        XCTAssertEqual(sites(.port), ["generator-right", "generator-left"])
        XCTAssertEqual(sites(.intrathecalPump), ["lower-abdomen-right", "lower-abdomen-left"])
        XCTAssertEqual(sites(.neurostimulator), ["generator-right", "generator-left", "lower-abdomen-right", "lower-abdomen-left", "flank-right", "flank-left"])
        XCTAssertEqual(sites(.insulinPump), ["lower-abdomen-right", "lower-abdomen-left", "upper-arm-right", "upper-arm-left"])
    }

    func testEveryNewKindHasADefaultSiteThatExistsAndAllowsIt() throws {
        for k in added {
            let def = try XCTUnwrap(PatientDevices.defaultSite(for: k), "\(k) has a default site")
            XCTAssertTrue(DeviceSite.kinds(forBase: def.site).contains(k), "\(k)'s default \(def.site) allows it")
            let site = DeviceSite.find(def.site, side: DeviceSite.isPaired(def.site) ? "right" : nil)
            XCTAssertNotNil(site, "\(k)'s default \(def.site) exists")
            XCTAssertTrue(site?.kinds.contains(k) ?? false)
        }
        // By type: an OG tube by the mouth, the others by the nose; a feeding tube left upper, a colostomy left lower, an ileostomy or urostomy right lower.
        XCTAssertEqual(PatientDevices.defaultSite(for: .gastricTube, type: "OG")?.site, "mouth-og")
        XCTAssertEqual(PatientDevices.defaultSite(for: .gastricTube, type: "NG")?.site, "nose-gastric")
        XCTAssertEqual(PatientDevices.defaultSite(for: .gastricTube, type: "Dobhoff")?.site, "nose-gastric")
        XCTAssertEqual(PatientDevices.defaultSite(for: .feedingTube)?.site, "upper-abdomen")
        XCTAssertEqual(PatientDevices.defaultSide(for: .feedingTube), "left")
        XCTAssertEqual(PatientDevices.defaultSite(for: .ostomy, type: "Colostomy")?.site, "lower-abdomen")
        XCTAssertEqual(PatientDevices.defaultSide(for: .ostomy, type: "Colostomy"), "left")
        XCTAssertEqual(PatientDevices.defaultSide(for: .ostomy, type: "Ileostomy"), "right")
        XCTAssertEqual(PatientDevices.defaultSide(for: .ostomy, type: "Urostomy"), "right")
        XCTAssertNil(PatientDevices.defaultSide(for: .ostomy, type: "Mucous fistula"))
        XCTAssertNil(PatientDevices.defaultSide(for: .ostomy))
        XCTAssertNil(PatientDevices.defaultSide(for: .piv))
        XCTAssertEqual(PatientDevices.defaultSite(for: .lumbarDrain)?.site, "lumbar-spine")
        XCTAssertEqual(PatientDevices.defaultSite(for: .rectalTube)?.site, "perineum")
    }

    // MARK: The handoff text

    func testTheHandoffWordsAreAsBriefed() {
        XCTAssertEqual(d(.gastricTube, "nose-gastric", size: "16", detail: "NG", settings: ["notes": "to suction"]).label, "NG tube 16 Fr (to suction)")
        XCTAssertEqual(d(.gastricTube, "nose-gastric", size: "16", detail: "NG", settings: ["notes": "to suction", "side": "Left"]).label, "NG tube 16 Fr L nare (to suction)",
                       "the nare, when one is recorded")
        XCTAssertEqual(d(.gastricTube, "mouth-og", size: "14", detail: "OG", settings: ["notes": "clamped"]).label, "OG tube 14 Fr (clamped)")
        XCTAssertEqual(d(.gastricTube, "nose-gastric", size: "10", detail: "Dobhoff").label, "Dobhoff 10 Fr")
        XCTAssertEqual(d(.gastricTube, "nose-gastric").label, "NG/OG tube", "no type chosen yet")
        XCTAssertEqual(d(.feedingTube, "upper-abdomen-left", side: "left", size: "20", detail: "PEG").label, "PEG 20 Fr LUQ")
        XCTAssertEqual(d(.feedingTube, "upper-abdomen-left", side: "left", size: "24", detail: "G-tube").label, "G-tube 24 Fr LUQ")
        XCTAssertEqual(d(.feedingTube, "upper-abdomen-left", side: "left", detail: "GJ-tube").label, "GJ-tube LUQ")
        XCTAssertEqual(d(.feedingTube, "upper-abdomen-left", side: "left").label, "PEG/G-tube LUQ")
        XCTAssertEqual(d(.ostomy, "lower-abdomen-left", side: "left", detail: "Colostomy").label, "Colostomy LLQ")
        XCTAssertEqual(d(.ostomy, "lower-abdomen-right", side: "right", detail: "Ileostomy").label, "Ileostomy RLQ")
        XCTAssertEqual(d(.ostomy, "lower-abdomen-right", side: "right", detail: "Urostomy").label, "Urostomy RLQ")
        XCTAssertEqual(d(.ostomy, "lower-abdomen-left", side: "left", detail: "Mucous fistula").label, "Mucous fistula LLQ")
        XCTAssertEqual(d(.ostomy, "lower-abdomen-left", side: "left").label, "Ostomy LLQ")
        XCTAssertEqual(d(.rectalTube, "perineum").label, "Rectal tube")
        XCTAssertEqual(d(.nephrostomy, "flank-left", side: "left", size: "10").label, "Nephrostomy tube 10 Fr L flank")
        XCTAssertEqual(d(.ureteralStent, "flank-right", side: "right").label, "Ureteral stent R flank")
        XCTAssertEqual(d(.surgicalDrain, "lower-abdomen-right", side: "right", detail: "JP", settings: ["notes": "to bulb suction"]).label, "JP drain RLQ (to bulb suction)")
        for (type, printed) in [("JP", "JP drain"), ("Blake", "Blake drain"), ("Penrose", "Penrose drain"), ("Hemovac", "Hemovac drain"),
                                ("Biliary (T-tube)", "Biliary drain"), ("Percutaneous", "Percutaneous drain"), ("", "Drain")] {
            XCTAssertEqual(d(.surgicalDrain, "lower-abdomen-left", side: "left", detail: type).label, printed + " LLQ")
        }
        XCTAssertEqual(d(.surgicalDrain, "neck-right", side: "right", size: "15", detail: "Blake").label, "Blake drain 15 Fr R neck")
        XCTAssertEqual(d(.woundVac, "sternum").label, "Wound vac sternum")
        XCTAssertEqual(d(.pdCatheter, "lower-abdomen-right", side: "right").label, "PD catheter RLQ")
        XCTAssertEqual(d(.evd, "frontal-right", side: "right", detail: "open at 10").label, "EVD R frontal (open at 10)")
        XCTAssertEqual(d(.lumbarDrain, "lumbar-spine", detail: "open").label, "Lumbar drain (open)")
        XCTAssertEqual(d(.vpShunt, "frontal-right", side: "right", detail: "programmable").label, "VP shunt R frontal (programmable)")
        XCTAssertEqual(d(.port, "generator-right", side: "right", detail: "accessed").label, "Port R chest (accessed)")
        XCTAssertEqual(d(.port, "generator-left", side: "left", detail: "not accessed").label, "Port L chest (not accessed)")
        XCTAssertEqual(d(.intrathecalPump, "lower-abdomen-left", side: "left", detail: "baclofen").label, "Intrathecal pump LLQ (baclofen)")
        XCTAssertEqual(d(.neurostimulator, detail: "Spinal cord stimulator").label, "Spinal cord stimulator")
        XCTAssertEqual(d(.neurostimulator, "generator-left", side: "left", detail: "Vagal nerve stimulator").label, "Vagal nerve stimulator L chest")
        XCTAssertEqual(d(.neurostimulator, "flank-right", side: "right", detail: "Spinal cord stimulator").label, "Spinal cord stimulator R flank")
        XCTAssertEqual(d(.insulinPump, detail: "Insulin pump").label, "Insulin pump")
        XCTAssertEqual(d(.insulinPump, "upper-arm-left", side: "left", detail: "Glucose sensor").label, "Glucose sensor L upper arm")
        XCTAssertEqual(d(.insulinPump).label, "Insulin pump/CGM")
        // Removed is said as it is for any line; a detail that is none of the types is shown beside the note.
        XCTAssertEqual(d(.ostomy, "lower-abdomen-left", side: "left", detail: "Colostomy", removed: true).label, "Colostomy LLQ (removed)")
        XCTAssertEqual(d(.feedingTube, "upper-abdomen-left", side: "left", size: "20", detail: "Mic-Key", settings: ["notes": "feeds"]).label, "PEG/G-tube 20 Fr LUQ (feeds, Mic-Key)")
    }

    func testTheHandoffListsThemWithTheLines() {
        var r = PatientRecord()
        r.devices = [d(.piv, "forearm-right", side: "right", size: "18"), d(.ostomy, "lower-abdomen-left", side: "left", detail: "Colostomy"),
                     d(.feedingTube, "upper-abdomen-left", side: "left", size: "20", detail: "PEG"), d(.insulinPump, detail: "Insulin pump")]
        let lines = PatientDevices.labels(r.currentDevices().filter { PatientDevice.lineKinds.contains($0.kind) })
        XCTAssertEqual(lines, ["PIV 18 G R forearm", "Colostomy LLQ", "PEG 20 Fr LUQ", "Insulin pump"])
        let phased = PatientDevices.labelsWithPhase(r.currentDevices())
        XCTAssertEqual(phased.last, "Insulin pump (Pre)")
        for k in added { XCTAssertTrue(PatientDevice.lineKinds.contains(k), "\(k) is listed with the lines") }
    }

    func testNoneOfThemIsIVAccessALimbAlertAMonitorOrSupport() {
        let ivAccess: Set<DeviceKind> = [.piv, .arterial, .cvc, .pac, .picc, .intraosseous]
        XCTAssertTrue(Set(added).isDisjoint(with: ivAccess))
        XCTAssertTrue(Set(added).isDisjoint(with: PatientDevice.supportKinds))
        XCTAssertTrue(Set(added).isDisjoint(with: PatientStudies.armLineKinds))
        XCTAssertTrue(Set(added).isDisjoint(with: PatientDevice.monitorKinds))
        for k in added {
            XCTAssertFalse(PatientDevice(kind: k).isMonitorOrAdjunct, "\(k)")
            XCTAssertFalse(k.isECMO)
            XCTAssertFalse(k.isTemporaryPacing)
            XCTAssertFalse(k.isDialysisAccess)
        }
        // A record with all sixteen in place: no limb alert, no support, no temporary pacing, no ECMO circuit, no arm line on a harvest arm.
        var r = PatientRecord()
        r.radial.harvest = "left"
        for k in added {
            let def = PatientDevices.defaultSite(for: k)
            let site = def.flatMap { DeviceSite.find($0.site, side: DeviceSite.isPaired($0.site) ? "left" : nil) }
            r.devices.append(PatientDevice(kind: k, site: site?.id ?? "", side: site?.side))
        }
        r.devices.append(d(.insulinPump, "upper-arm-left", side: "left"))
        XCTAssertTrue(PatientDeviceFills.limbAlerts(r).isEmpty)
        XCTAssertTrue(r.mechanicalSupport.isEmpty)
        XCTAssertFalse(PatientDevices.temporaryPacingInPlace(r.devices))
        XCTAssertNil(PatientDevices.ecmoSystem(r.devices))
        XCTAssertTrue(PatientStudies.linesOnHarvestArm(r).isEmpty, "a pump on the upper arm is not a line on the harvest arm")
    }

    // MARK: Saved records

    func testEveryNewKindRoundTripsAndAnUnknownKindIsStillOther() throws {
        for k in added {
            let def = PatientDevices.defaultSite(for: k)
            let site = def.flatMap { DeviceSite.find($0.site, side: DeviceSite.isPaired($0.site) ? "right" : nil) }
            let device = PatientDevice(kind: k, site: site?.id ?? "", side: site?.side, size: k.sizeUnit.isEmpty ? "" : "16", detail: k.typeChoices.first ?? "open",
                                       settings: ["notes": "to suction"], placedIntraop: true)
            XCTAssertEqual(try JSONDecoder().decode(PatientDevice.self, from: JSONEncoder().encode(device)), device, "\(k)")
        }
        // A kind this build does not know is read as Other, with its settings kept (an older build reads these sixteen so).
        for raw in ["gastricTube2", "futureDrain", "insulinPumpX"] {
            let json = #"{"kind":"\#(raw)","site":"lower-abdomen-left","detail":"Colostomy","settings":{"notes":"x"}}"#
            let device = try JSONDecoder().decode(PatientDevice.self, from: Data(json.utf8))
            XCTAssertEqual(device.kind, .other, raw)
            XCTAssertEqual(device.settings["notes"], "x")
        }
        // Records saved before 1.15 open as they did.
        let old = #"{"devices":[{"kind":"foley","site":"urethral","size":"16"},{"kind":"chestTube","site":"lateral-chest-left","side":"left","size":"28"},{"kind":"other","detail":"NG tube","site":"nose"}]}"#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(old.utf8))
        XCTAssertEqual(r.devices.map(\.kind), [.foley, .chestTube, .other])
        XCTAssertEqual(r.devices.map(\.label), ["Foley 16 Fr", "L chest tube 28 Fr", "NG tube"])
        // And a record with the new kinds round-trips whole.
        var withNew = PatientRecord()
        withNew.devices = [d(.ostomy, "lower-abdomen-left", side: "left", detail: "Colostomy"), d(.evd, "frontal-right", side: "right", detail: "open")]
        XCTAssertEqual(try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(withNew)).devices, withNew.devices)
    }

    // MARK: Typed text

    func testTypedPhrasesGiveTheirKindAndType() throws {
        let table: [(String, DeviceKind, String)] = [
            ("ng tube", .gastricTube, "NG"), ("ngt", .gastricTube, "NG"), ("nasogastric tube", .gastricTube, "NG"), ("salem sump", .gastricTube, "NG"),
            ("og tube", .gastricTube, "OG"), ("ogt", .gastricTube, "OG"), ("orogastric tube", .gastricTube, "OG"),
            ("dobhoff", .gastricTube, "Dobhoff"), ("dobbhoff", .gastricTube, "Dobhoff"), ("nasoenteric tube", .gastricTube, "Dobhoff"),
            ("nj tube", .gastricTube, "Dobhoff"), ("keofeed", .gastricTube, "Dobhoff"),
            ("peg", .feedingTube, "PEG"), ("peg tube", .feedingTube, "PEG"),
            ("g-tube", .feedingTube, "G-tube"), ("g tube", .feedingTube, "G-tube"), ("gtube", .feedingTube, "G-tube"),
            ("gastrostomy tube", .feedingTube, "G-tube"), ("mic-key", .feedingTube, "G-tube"),
            ("gj tube", .feedingTube, "GJ-tube"), ("gj-tube", .feedingTube, "GJ-tube"), ("peg-j", .feedingTube, "GJ-tube"),
            ("j-tube", .feedingTube, "J-tube"), ("j tube", .feedingTube, "J-tube"), ("jtube", .feedingTube, "J-tube"),
            ("jejunostomy tube", .feedingTube, "J-tube"), ("feeding tube", .feedingTube, ""),
            ("colostomy", .ostomy, "Colostomy"), ("ileostomy", .ostomy, "Ileostomy"), ("urostomy", .ostomy, "Urostomy"),
            ("ileal conduit", .ostomy, "Urostomy"), ("mucous fistula", .ostomy, "Mucous fistula"), ("ostomy", .ostomy, ""),
            ("rectal tube", .rectalTube, ""), ("flexi-seal", .rectalTube, ""), ("flexiseal", .rectalTube, ""), ("fecal management system", .rectalTube, ""),
            ("nephrostomy tube", .nephrostomy, ""), ("nephrostomy", .nephrostomy, ""), ("pcn", .nephrostomy, ""), ("neph tube", .nephrostomy, ""),
            ("ureteral stent", .ureteralStent, ""), ("jj stent", .ureteralStent, ""), ("double j stent", .ureteralStent, ""), ("double-j stent", .ureteralStent, ""),
            ("jp drain", .surgicalDrain, "JP"), ("jp", .surgicalDrain, "JP"), ("jackson-pratt", .surgicalDrain, "JP"),
            ("blake drain", .surgicalDrain, "Blake"), ("blake", .surgicalDrain, "Blake"), ("penrose", .surgicalDrain, "Penrose"),
            ("hemovac", .surgicalDrain, "Hemovac"), ("t-tube", .surgicalDrain, "Biliary (T-tube)"), ("biliary drain", .surgicalDrain, "Biliary (T-tube)"),
            ("ptc drain", .surgicalDrain, "Biliary (T-tube)"), ("percutaneous drain", .surgicalDrain, "Percutaneous"),
            ("perc drain", .surgicalDrain, "Percutaneous"), ("surgical drain", .surgicalDrain, ""),
            ("wound vac", .woundVac, ""), ("woundvac", .woundVac, ""), ("npwt", .woundVac, ""), ("negative pressure dressing", .woundVac, ""),
            ("pd catheter", .pdCatheter, ""), ("peritoneal dialysis catheter", .pdCatheter, ""), ("tenckhoff", .pdCatheter, ""),
            ("evd", .evd, ""), ("external ventricular drain", .evd, ""), ("ventriculostomy", .evd, ""),
            ("lumbar drain", .lumbarDrain, ""), ("spinal drain", .lumbarDrain, ""), ("csf drain", .lumbarDrain, ""),
            ("vp shunt", .vpShunt, ""), ("ventriculoperitoneal shunt", .vpShunt, ""),
            ("port-a-cath", .port, ""), ("portacath", .port, ""), ("mediport", .port, ""), ("chemo port", .port, ""), ("implanted port", .port, ""),
            ("power port", .port, ""), ("chest port", .port, ""),
            ("intrathecal pump", .intrathecalPump, ""), ("baclofen pump", .intrathecalPump, "baclofen"), ("pain pump", .intrathecalPump, ""),
            ("spinal cord stimulator", .neurostimulator, "Spinal cord stimulator"), ("scs", .neurostimulator, "Spinal cord stimulator"),
            ("deep brain stimulator", .neurostimulator, "Deep brain stimulator"), ("dbs", .neurostimulator, "Deep brain stimulator"),
            ("vagal nerve stimulator", .neurostimulator, "Vagal nerve stimulator"), ("vns", .neurostimulator, "Vagal nerve stimulator"),
            ("sacral nerve stimulator", .neurostimulator, "Sacral nerve stimulator"), ("interstim", .neurostimulator, "Sacral nerve stimulator"),
            ("insulin pump", .insulinPump, "Insulin pump"), ("omnipod", .insulinPump, "Insulin pump"),
            ("cgm", .insulinPump, "Glucose sensor"), ("glucose sensor", .insulinPump, "Glucose sensor"), ("dexcom", .insulinPump, "Glucose sensor"),
            ("libre", .insulinPump, "Glucose sensor"),
        ]
        for (text, kind, type) in table {
            let p = try parse(text)
            XCTAssertEqual(p.kind, kind, "\"\(text)\" is a \(kind)")
            XCTAssertEqual(p.detail, type, "\"\(text)\" has the type \"\(type)\"")
        }
        XCTAssertEqual(try parse("Flexi-Seal").kind, .rectalTube, "capitals and a hyphen read as typed")
    }

    func testTypedSitesAndSizes() throws {
        XCTAssertEqual(try typed("PEG 20 Fr LUQ"), "PEG 20 Fr LUQ")
        XCTAssertEqual(try parse("PEG 20 Fr LUQ").site, "upper-abdomen-left")
        XCTAssertEqual(try parse("PEG 20 Fr LUQ").size, "20")
        XCTAssertEqual(try typed("peg"), "PEG LUQ", "a feeding tube starts in the left upper abdomen")
        XCTAssertEqual(try typed("colostomy"), "Colostomy LLQ")
        XCTAssertEqual(try typed("ileostomy"), "Ileostomy RLQ")
        XCTAssertEqual(try typed("urostomy"), "Urostomy RLQ")
        XCTAssertEqual(try typed("ileal conduit"), "Urostomy RLQ")
        XCTAssertEqual(try typed("ileostomy LLQ"), "Ileostomy LLQ", "a site typed wins over the type's")
        XCTAssertEqual(try typed("colostomy right lower quadrant"), "Colostomy RLQ")
        XCTAssertEqual(try typed("feeding tube RUQ 18 fr"), "PEG/G-tube 18 Fr RUQ")
        XCTAssertEqual(try typed("colostomy 2019"), "Colostomy LLQ", "a year beside an ostomy is not a size")
        XCTAssertEqual(try typed("NG tube 16 fr to suction"), "NG tube 16 Fr (to suction)")
        XCTAssertEqual(try parse("NG tube 16 fr to suction").site, "nose-gastric")
        XCTAssertEqual(try parse("NG tube 16 fr to suction").settings["notes"], "to suction")
        XCTAssertEqual(try parse("og tube").site, "mouth-og")
        XCTAssertEqual(try typed("Dobhoff 10 fr L nare"), "Dobhoff 10 Fr L nare")
        XCTAssertEqual(try typed("nephrostomy tube 10 fr L flank"), "Nephrostomy tube 10 Fr L flank")
        XCTAssertEqual(try parse("R flank nephrostomy").site, "flank-right")
        XCTAssertEqual(try typed("JP drain RLQ"), "JP drain RLQ")
        XCTAssertEqual(try typed("jp drain left groin"), "JP drain L groin")
        XCTAssertEqual(try typed("blake drain right neck"), "Blake drain R neck")
        XCTAssertEqual(try typed("jp drain right chest"), "JP drain R lateral chest")
        XCTAssertEqual(try typed("wound vac sternum"), "Wound vac sternum")
        XCTAssertEqual(try typed("wound vac chest"), "Wound vac sternum")
        XCTAssertEqual(try typed("wound vac abdomen"), "Wound vac abdomen")
        XCTAssertEqual(try typed("EVD R frontal open at 10"), "EVD R frontal (open at 10)")
        XCTAssertEqual(try typed("EVD scalp left"), "EVD L frontal", "the scalp vein's word means the frontal scalp for an EVD")
        XCTAssertEqual(try typed("lumbar drain open"), "Lumbar drain (open)")
        XCTAssertEqual(try parse("lumbar drain").site, "lumbar-spine")
        XCTAssertEqual(try typed("mediport R chest accessed"), "Port R chest (accessed)")
        XCTAssertNotEqual(PatientDevices.parse("port R chest")?.kind, .port, "a bare \"port\" is not a port")
        XCTAssertEqual(try typed("port-a-cath left chest"), "Port L chest")
        XCTAssertEqual(try typed("intrathecal baclofen pump LLQ"), "Intrathecal pump LLQ (baclofen)")
        XCTAssertEqual(try typed("spinal cord stimulator"), "Spinal cord stimulator", "no site given: it is not placed until a side is chosen")
        XCTAssertEqual(try typed("insulin pump L upper arm"), "Insulin pump L upper arm")
        XCTAssertEqual(try parse("rectal tube").site, "perineum")
        // A site that is not sided gives the two sides to choose from; a bilateral stent is one on each side.
        XCTAssertEqual(try parse("jp drain").alternatives.compactMap(\.site), ["lower-abdomen-right", "lower-abdomen-left"])
        let both = try parse("bilateral ureteral stent").devices()
        XCTAssertEqual(both.map(\.site), ["flank-right", "flank-left"])
        XCTAssertEqual(both.map(\.kind), [.ureteralStent, .ureteralStent])
    }

    func testTheWordsThatMustKeepTheirOldMeaning() throws {
        // "drain" is the ECMO drainage role: a typed JP drain is a surgical drain, an ECMO drainage cannula is still one.
        XCTAssertEqual(try parse("JP drain RLQ").kind, .surgicalDrain)
        XCTAssertEqual(try parse("Blake drain").kind, .surgicalDrain)
        XCTAssertEqual(try parse("hemovac drain").kind, .surgicalDrain)
        XCTAssertEqual(try parse("Dobhoff tube").kind, .gastricTube, "\"tube\" beside a new word is part of its name, not an ETT")
        let ecmo = try parse("ECMO drainage R femoral vein")
        XCTAssertEqual(ecmo.kind, .ecmoDrainage)
        XCTAssertEqual(ecmo.site, "femoral-vein-right")
        XCTAssertEqual(try parse("ECMO drain cannula R fem").kind, .ecmoDrainage)
        XCTAssertEqual(try parse("VA ECMO 25F RFV drainage / 17F LFA return").kind, .ecmoDrainage)
        XCTAssertEqual(try parse("pigtail drain").kind, .chestTube)
        XCTAssertEqual(try parse("chest drain").kind, .chestTube)
        XCTAssertEqual(try parse("chest tube").kind, .chestTube)
        // A bare "drain" is the ECMO role still; a bare "port", "shunt" or "stent" is nothing.
        XCTAssertFalse(added.contains(try parse("drain").kind))
        XCTAssertNil(PatientDevices.parse("port"))
        XCTAssertNil(PatientDevices.parse("shunt"))
        XCTAssertNil(PatientDevices.parse("stent"))
        // "peg" does not fire inside other words; "port" inside "portex" is still the tracheostomy's detail.
        XCTAssertNil(PatientDevices.parse("pegylated"))
        XCTAssertNil(PatientDevices.parse("pegfilgrastim"))
        let portex = try parse("8 portex trach")
        XCTAssertEqual(portex.kind, .trach)
        XCTAssertTrue(portex.detail.contains("Portex"))
        // Another device's entry keeps the site words it always had: the new site words mean a site only for a device that goes there.
        let cvl = try parse("RIJ TLC neck")
        XCTAssertEqual(cvl.kind, .cvc)
        XCTAssertEqual(cvl.site, "ij-right")
        XCTAssertTrue(cvl.detail.contains("neck"))
        XCTAssertEqual(try parse("20 rue").site, "antecubital-right")
        XCTAssertEqual(try parse("foley 16 fr").kind, .foley)
        XCTAssertEqual(try parse("epidural T8").kind, .epidural)
        XCTAssertEqual(try parse("IABP L femoral 1:1").kind, .iabp)
    }

    func testTheNoteReaderReadsTheNewWordsAndKeepsHistoryAndAllergiesOut() {
        XCTAssertTrue(noted("NG tube 16 Fr").contains("NG tube 16 Fr"), "\(noted("NG tube 16 Fr"))")
        XCTAssertTrue(noted("Colostomy LLQ").contains("Colostomy LLQ"), "\(noted("Colostomy LLQ"))")
        XCTAssertTrue(noted("PEG tube 20 Fr LUQ").contains("PEG 20 Fr LUQ"), "\(noted("PEG tube 20 Fr LUQ"))")
        // Surgical history is not a device in place, and the other meanings of the words are not devices.
        XCTAssertTrue(noted("s/p colostomy 2019").isEmpty, "\(noted("s/p colostomy 2019"))")
        XCTAssertTrue(noted("history of PEG").isEmpty)
        XCTAssertTrue(noted("colostomy reversed").isEmpty)
        XCTAssertTrue(noted("ileostomy closure").isEmpty, "an operation on the stoma")
        XCTAssertTrue(noted("PEG 3350 bowel prep").isEmpty, "PEG is also polyethylene glycol")
        XCTAssertTrue(noted("PCN allergy").isEmpty, "PCN here is penicillin")
        XCTAssertTrue(noted("Allergies: PCN, sulfa").isEmpty)
        XCTAssertTrue(noted("pegylated interferon").isEmpty)
        XCTAssertTrue(noted("on a high-flow port").isEmpty, "a bare port is no device")
        // The words keep their pattern checks.
        XCTAssertNotNil(PatientNote.deviceCue.first("NG tube"))
        XCTAssertNotNil(PatientNote.deviceCue.first("PEG 20 Fr"))
        XCTAssertNil(PatientNote.deviceCue.first("peg"), "a lower-case peg alone is nothing")
        XCTAssertNil(PatientNote.deviceCue.first("PEG 3350"))
        XCTAssertNil(PatientNote.deviceCue.first("PEG insertion"))
        XCTAssertNil(PatientNote.deviceCue.first("Ileostomy closure"))
        XCTAssertNil(PatientNote.deviceCue.first("pcn"))
        XCTAssertNil(PatientNote.deviceCue.first("shunt"))
        XCTAssertNil(PatientNote.deviceCue.first("stent"))
        XCTAssertNotNil(PatientNote.deviceCue.first("portacath"))
        // 28f PEG: a French size beside a device word, as with "28f chest tube", and not a 28-year-old woman.
        XCTAssertNotNil(PatientNote.lowerDeviceAfter.first("PEG"))
        XCTAssertNotNil(PatientNote.lowerDeviceBefore.first("PEG "))
        // The allergy reader is its own: it is not given the device words.
        for rx in PatientNote.allPatterns { XCTAssertNotNil(rx.re, rx.pattern) }
    }

    // MARK: The diagram

    func testEachNewKindIsDrawnAtItsSiteInItsColour() throws {
        var r = PatientRecord()
        for k in added {
            let def = try XCTUnwrap(PatientDevices.defaultSite(for: k))
            let site = try XCTUnwrap(DeviceSite.find(def.site, side: DeviceSite.isPaired(def.site) ? "right" : nil))
            r.devices.append(PatientDevice(kind: k, site: site.id, side: site.side, size: k.sizeUnit.isEmpty ? "" : "24", detail: k.typeChoices.first ?? ""))
        }
        let drawn = PatientDiagramModel.items(r, phase: .all).items
        for dev in r.devices {
            let item = try XCTUnwrap(drawn.first { $0.id == dev.id.uuidString }, "\(dev.kind) is drawn")
            XCTAssertEqual(item.anchor, PatientDiagramModel.pt(try XCTUnwrap(dev.position)), "\(dev.kind) is at its site")
            XCTAssertEqual(item.color, PatientDiagramModel.color(dev.kind.colorRole), "\(dev.kind) is in its role's colour")
            XCTAssertFalse(item.label.isEmpty, "\(dev.kind) has a label")
            XCTAssertLessThanOrEqual(PatientDiagramModel.tag(dev).count, 15, "\(dev.kind)'s tag fits the label column")
        }
        // The back view's flank and lumbar marks are drawn (on the figure, at their height, as the ESP site is).
        var back = PatientRecord()
        back.devices = [d(.nephrostomy, "flank-left", side: "left", size: "10"), d(.lumbarDrain, "lumbar-spine", detail: "open")]
        let marks = PatientDiagramModel.items(back, phase: .all).items
        XCTAssertEqual(marks.count, 2)
        XCTAssertEqual(Set(marks.map(\.label)), ["Neph tube 10Fr", "Lumbar drain"])
        // The tags.
        XCTAssertEqual(PatientDiagramModel.tag(d(.gastricTube, "nose-gastric", size: "16", detail: "NG")), "NG tube 16Fr")
        XCTAssertEqual(PatientDiagramModel.tag(d(.feedingTube, "upper-abdomen-left", size: "20", detail: "PEG")), "PEG 20Fr")
        XCTAssertEqual(PatientDiagramModel.tag(d(.ostomy, "lower-abdomen-left", detail: "Colostomy")), "Colostomy")
        XCTAssertEqual(PatientDiagramModel.tag(d(.surgicalDrain, "lower-abdomen-right", detail: "JP")), "JP drain")
        XCTAssertEqual(PatientDiagramModel.tag(d(.neurostimulator, "generator-left", detail: "Vagal nerve stimulator")), "VNS")
        XCTAssertEqual(PatientDiagramModel.tag(d(.port, "generator-right")), "Port")
    }

    // MARK: The demo patients

    #if DEBUG
    func testTheDemoPatientsHaveTheBriefedDevices() throws {
        let a = try XCTUnwrap(PatientDemo115Devices.record("demo-115-devices-a"))
        XCTAssertEqual(PatientDevices.labels(a.currentDevices()), [
            "NG tube 16 Fr R nare (to suction)", "PEG 20 Fr LUQ", "Colostomy LLQ", "JP drain RLQ (to bulb suction)", "Nephrostomy tube 10 Fr L flank",
            "Lumbar drain (open)", "EVD R frontal (open at 10)", "Port R chest (accessed)", "Insulin pump L upper arm",
        ])
        let b = try XCTUnwrap(PatientDemo115Devices.record("demo-115-devices-b"))
        let labels = PatientDevices.labels(b.currentDevices())
        for want in ["Foley 16 Fr", "L chest tube 28 Fr", "Ileostomy RLQ", "Wound vac sternum (continuous)"] { XCTAssertTrue(labels.contains(want), want) }
        XCTAssertNil(PatientDemo115Devices.record("demo-115-nothing"))
        // Every device of both is drawn (each has a place on the figure).
        for r in [a, b] {
            let drawn = Set(PatientDiagramModel.items(r, phase: .preop).items.map(\.id))
            for dev in r.devices { XCTAssertTrue(drawn.contains(dev.id.uuidString), dev.label) }
        }
    }
    #endif
}
