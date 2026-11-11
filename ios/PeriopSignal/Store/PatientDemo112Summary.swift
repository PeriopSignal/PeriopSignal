import Foundation

#if DEBUG
/// Helper B's demo patients for the 1.12 screenshots (-ps.patient <seed>). Start from an existing demo
/// (PatientDemo.record, PatientDemo.cardiac ...) and change what the shot needs.
enum PatientDemo112Summary {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-summary": return summary
        case "demo-112-difficult": return difficult
        case "demo-112-imaging": return imaging
        case "demo-112-long": return long
        default: return nil
        }
    }

    /// The briefs patient (an easy airway, ASA IV, several systems) with the preprocedure summary on, imaging typed and
    /// the CT and the MRI chosen for the summaries.
    static var summary: PatientRecord {
        var r = PatientDemo.briefsOn
        r.imaging.ct = "CT chest 10/2026: ascending aorta 4.8 cm"
        r.imaging.mri = "MRI brain 09/2026: no acute findings"
        r.imaging.other = "Carotid duplex 08/2026: 50-69% left ICA"
        r.handoffExtras = ["imaging:ct", "imaging:mri"]
        r.tube = "8.0 cuffed ETT (23 cm)"
        r.airwayAtEnd = "intubated"
        r.ventilation = "AC/VC 450 × 18, PEEP 8, FiO₂ 60%"
        return r
    }

    /// A difficult airway: the details a receiving team needs stay on the line, in red.
    static var difficult: PatientRecord {
        var r = summary
        r.mask = "difficult"; r.maskNote = "2-person"
        r.intubation = "difficult"; r.airwayDevice = "Video laryngoscope"; r.laryngoscopyGrade = "3"; r.attempts = 2
        r.intubationNote = "Bougie"
        r.tube = "7.5 ETT, 22 cm at the teeth"
        r.airwayAtEnd = "extubated"; r.ventilation = ""
        return r
    }

    /// The Preoperative tab with imaging typed (the collapsed link names CT and MRI) and the preprocedure summary on.
    static var imaging: PatientRecord {
        var r = summary
        r.mask = nil; r.intubation = nil; r.airwayDevice = nil; r.laryngoscopyGrade = nil; r.attempts = nil; r.tube = ""
        r.airwayAtEnd = nil; r.ventilation = ""
        r.imaging.other = ""
        return r
    }

    /// A summary with one block taller than a page, so the image has a page of its own for it.
    static var long: PatientRecord {
        var r = summary
        r.todos = (1...48).map { "To do \($0): recheck labs at \(String(format: "%02d", 8 + $0 / 6)):\(String(format: "%02d", ($0 % 6) * 10)) and call with the result." }
            .joined(separator: " ")
        return r
    }
}
#endif
