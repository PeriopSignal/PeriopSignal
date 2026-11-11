import Foundation

#if DEBUG
/// Helper E1's demo patients for the 1.12 screenshots (-ps.patient <seed>): the lines that go through an introducer, the
/// chest X-ray and the valve calculator's calculated values. Nothing here is written to disk.
///   demo-112-lines       a MAC introducer in the right IJ with a PA catheter put through it, and an introducer in the left
///                        IJ with a SLIC through it (the diagram labels "PAC" and "SLIC", the lines list and the handoff read
///                        "PAC via R IJ" and "SLIC via L IJ")
///   demo-112-lines-bare  the same two introducer lines with nothing put through them yet (the chips unchosen)
///   demo-112-cxr         a moderate left effusion with a finding, among a positive stress test and other workup
///   demo-112-cxr-normal  a normal chest X-ray
///   demo-112-valvecalc   height and weight (so a BSA) and a recorded echo with an LVEF, for the calculator's calculated values
enum PatientDemo112Devices {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-lines": return lines(through: true)
        case "demo-112-lines-bare": return lines(through: false)
        case "demo-112-cxr": return cxr(PatientChestXray(result: .effusion, side: .left, size: .moderate, findings: "blunting of the left costophrenic angle; no pneumothorax"))
        case "demo-112-cxr-normal": return cxr(PatientChestXray(result: .normal))
        case "demo-112-valvecalc": return valveCalc()
        default: return nil
        }
    }

    /// A 66-year-old man for an aortic valve replacement with an arterial line and two introducer central lines.
    private static func lines(through: Bool) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 66; r.sex = .male; r.heightCm = 178; r.weightKg = 84
        r.setProcedures(PlannedProcedure.parse("Aortic valve replacement"))
        r.urgency = .elective
        r.anesthetic = ["ga"]
        r.problems = ["htn", "cad"]
        r.devices = ["18g R forearm", "R radial art line 20g"].flatMap { PatientDevices.parse($0)?.devices(placedIntraop: false) ?? [] }
        r.devices.append(PatientDevice(kind: .cvc, site: "ij-right", side: "right", size: "9", detail: "MAC introducer"))
        r.devices.append(PatientDevice(kind: .cvc, site: "ij-left", side: "left", size: "8.5", detail: "introducer"))
        if through {
            if let mac = r.devices.first(where: { $0.acceptsDevicesThrough && $0.side == "right" }) {
                PatientDevices.toggleThrough(.pac, line: mac, in: &r.devices, placedIntraop: false)
            }
            if let intro = r.devices.first(where: { $0.acceptsDevicesThrough && $0.side == "left" }) {
                PatientDevices.toggleThrough(.slic, line: intro, in: &r.devices, placedIntraop: false)
            }
        }
        return r
    }

    /// A 72-year-old man for a CABG (the 1.11 cardiac demo) with a chest X-ray recorded.
    private static func cxr(_ x: PatientChestXray) -> PatientRecord {
        var r = PatientDemo.cardio111
        r.chestXray = x
        return r
    }

    /// A 79-year-old woman for a TAVR: a 160 cm, 62 kg body (BSA about 1.6 m²) and an echo with an LVEF of 55%.
    private static func valveCalc() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 79; r.sex = .female; r.heightCm = 160; r.weightKg = 62
        r.setProcedures(PlannedProcedure.parse("TAVR"))
        r.urgency = .elective
        r.anesthetic = ["mac"]
        var echo = PatientEcho()
        echo.study = "TTE"; echo.lvef = 55
        r.echoFindings = echo
        return r
    }
}
#endif
