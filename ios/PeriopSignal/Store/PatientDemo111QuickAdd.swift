import Foundation

// Made-up patients for the 1.11 quick-add screenshots (helper D, P1-12; -ps.patient demo-quickadd111 and
// demo-quickadd111-end, shots 820–829): the 1.10 intraoperative demo (the airway course of Ben's notes-img2, two drips,
// blood and fluids) at two points of the case, so the Intraoperative bar's example rotates (QuickAdd.intraopExample):
// mid-case, with nothing said yet of the end ("extubated, to PACU"), and at handoff, with the airway at handoff, the
// disposition and an event recorded ("hypotension after induction, EBL 500").

extension PatientDemo {
    /// Mid-case: the airway course, drips, blood and fluids, no airway at handoff and no disposition yet.
    static var quickAdd111: PatientRecord {
        var r = PatientDemo.intraop110
        r.airwayAtEnd = nil
        r.disposition = nil
        r.events = ""
        r.noEvents = false
        r.airwayFollowUp = []
        // The ECG and the stress test are still to be typed ("ECG NSR LBBB", "DSE negative 2024").
        r.ecg = []
        r.ecgNotes = ""
        r.stressTest = PatientStressTest()
        r.cardiacSymptomsAnswer = nil
        r.activeCardiacAnswer = nil
        return r
    }

    /// At handoff: extubated, to the ICU, with one event, as the bar files them.
    static var quickAdd111End: PatientRecord {
        var r = quickAdd111
        r.airwayAtEnd = "extubated"
        r.disposition = "ICU"
        r.events = "Hypotension after induction"
        return r
    }
}
