import Foundation

#if DEBUG
/// Helper E2's demo patients for the 1.12 screenshots (-ps.patient <seed>). Start from an existing demo
/// (PatientDemo.record, PatientDemo.cardiac ...) and change what the shot needs.
enum PatientDemo112Valves {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-valves": return valves
        default: return nil
        }
    }

    /// A patient with two prosthetic valves in the History (the aortic one with nothing typed yet, so the Library shows beside an
    /// empty field; the mitral one typed) and an echo whose aortic prosthesis is a bioprosthetic with no details yet (the
    /// Library beside its details field) and whose mitral valve is a repair with its ring typed.
    static var valves: PatientRecord {
        var r = PatientDemo.cardio
        r.hx.valves = [
            "aortic": PatientValve(prosthetic: true),
            "mitral": PatientValve(prosthetic: true, prosthesis: "mechanical 27 mm"),
        ]
        PatientHistoryDetails.sync(&r)
        var echo = PatientEcho()
        echo.study = "TTE"
        echo.date = PatientMonthYear(month: 10, year: 2026)
        echo.lv = .normal; echo.lvef = 55; echo.rv = .normal
        echo.aortic = EchoValve(regurgitation: .normal, stenosis: .normal, prosthesis: "Bioprosthetic")
        echo.mitral = EchoValve(regurgitation: .mild, stenosis: .normal, prosthesis: "Repair or ring", prosthesisDetail: "28 mm Physio II ring")
        echo.tricuspid = EchoValve(regurgitation: .trivial, stenosis: .normal)
        r.echoFindings = echo
        return r
    }
}
#endif
