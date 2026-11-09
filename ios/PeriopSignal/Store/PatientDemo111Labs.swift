import Foundation

// Made-up patients for the 1.11 labs screenshots (helper A, shots 740–759): the 1.8.3 labs demo with the hepatic figure,
// the minerals and the coagulation figure filled in, a few values out of range so the slots show the bold red marks (a
// mildly cholestatic picture with a low calcium and albumin), the hematocrit left out so it shows as an estimate, and
// the time the labs were drawn.

extension PatientDemo {
    /// -ps.patient demo-labs111: every figure on the Labs page has values.
    static var labs111: PatientRecord {
        var r = labs
        r.labs["pt"] = 12.4
        r.labs["ptt"] = 31
        r.labs["ca"] = 8.3
        r.labs["protein"] = 6.4
        r.labs["albumin"] = 3.1
        r.labs["ast"] = 62
        r.labs["alt"] = 48
        r.labs["alp"] = 134
        r.labs["tbili"] = 1.6
        r.labs["mg"] = 1.7
        r.labs["phos"] = 3.2
        r.labs["gfr"] = 72
        r.labs["a1c"] = 6.1
        r.labsDrawn = Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: Date())
        return r
    }

    /// -ps.patient demo-labs111-sent: the same labs, the type and screen sent and awaited (no result yet).
    static var labs111Sent: PatientRecord {
        var r = labs111
        r.typeScreen = PatientTypeScreen(status: .sent)
        return r
    }
}
