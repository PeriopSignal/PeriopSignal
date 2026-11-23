import Foundation

#if DEBUG
/// The 1.15 demo patients for the Lines & devices screenshots (-ps.patient <seed>), made up for the pictures (Ben, Nov 23: "Add
/// ostomies, peg tube, G-tube to lines and devices. Add other items similar to this I may have missed"). Nothing here is written to
/// disk, and no patient identifiers are kept.
///   demo-115-devices-a   an NG tube, a PEG, a colostomy, a JP drain, a nephrostomy tube, a lumbar drain, an EVD, a port and an insulin
///                        pump, all there on arrival (the figure, the list and the handoff for nine of the new kinds)
///   demo-115-devices-b   a Foley, a chest tube, an ileostomy and a wound vac on the sternum, with a PIV and an arterial line
enum PatientDemo115Devices {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-115-devices-a": return many
        case "demo-115-devices-b": return second
        default: return nil
        }
    }

    /// A 71-year-old man for an exploratory laparotomy with the nine devices of the first set, each built as the type buttons and the
    /// picker build it (type in the detail, the note in the "notes" setting for a kind with types, in the detail for one without).
    private static var many: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 71; r.sex = .male; r.heightCm = 176; r.weightKg = 79
        r.setProcedures(PlannedProcedure.parse("Exploratory laparotomy"))
        r.urgency = .urgent
        r.anesthetic = ["ga"]
        r.devices = [
            PatientDevice(kind: .gastricTube, site: "nose-gastric", size: "16", detail: "NG", settings: ["notes": "to suction", "side": "Right"]),
            PatientDevice(kind: .feedingTube, site: "upper-abdomen-left", side: "left", size: "20", detail: "PEG"),
            PatientDevice(kind: .ostomy, site: "lower-abdomen-left", side: "left", detail: "Colostomy"),
            PatientDevice(kind: .surgicalDrain, site: "lower-abdomen-right", side: "right", detail: "JP", settings: ["notes": "to bulb suction"]),
            PatientDevice(kind: .nephrostomy, site: "flank-left", side: "left", size: "10"),
            PatientDevice(kind: .lumbarDrain, site: "lumbar-spine", detail: "open"),
            PatientDevice(kind: .evd, site: "frontal-right", side: "right", detail: "open at 10"),
            PatientDevice(kind: .port, site: "generator-right", side: "right", detail: "accessed"),
            PatientDevice(kind: .insulinPump, site: "upper-arm-left", side: "left", detail: "Insulin pump"),
        ]
        return r
    }

    /// A 64-year-old man for a sternal wound debridement: a Foley, a chest tube, an ileostomy and a wound vac, with a PIV and an A-line.
    private static var second: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 64; r.sex = .male; r.heightCm = 180; r.weightKg = 92
        r.setProcedures(PlannedProcedure.parse("Sternal wound debridement"))
        r.urgency = .urgent
        r.anesthetic = ["ga"]
        r.devices = ["18g R forearm", "R radial art line 20g"].flatMap { PatientDevices.parse($0)?.devices(placedIntraop: false) ?? [] }
        r.devices += [
            PatientDevice(kind: .foley, site: "urethral", size: "16"),
            PatientDevice(kind: .chestTube, site: "lateral-chest-left", side: "left", size: "28"),
            PatientDevice(kind: .ostomy, site: "lower-abdomen-right", side: "right", detail: "Ileostomy"),
            PatientDevice(kind: .woundVac, site: "sternum", detail: "continuous"),
        ]
        return r
    }
}
#endif
