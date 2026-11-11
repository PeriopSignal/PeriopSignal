import Foundation

#if DEBUG
/// Helper C's demo patients for the 1.12 screenshots (-ps.patient <seed>). Start from an existing demo
/// (PatientDemo.record, PatientDemo.cardiac ...) and change what the shot needs.
enum PatientDemo112Layout {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-layout": return layout
        default: return nil
        }
    }

    /// Every box that folds holds a value, and the alerts show when they fold: a latex anaphylaxis, a heparin drip, a chest pain
    /// symptom, a difficult mask ventilation and a difficult intubation.
    static var layout: PatientRecord {
        var r = PatientDemo.record
        r.allergies = ""
        r.nkda = false
        r.allergyList = [PatientAllergy(name: "Latex", severity: "anaphylaxis"), PatientAllergy(name: "Penicillin", severity: "mild", reaction: "rash")]
        r.medications = ""
        r.homeMeds = [PatientMed(name: "Metoprolol", dose: "25 mg twice daily"), PatientMed(name: "Lisinopril", dose: "10 mg daily"),
                      PatientMed(name: "Atorvastatin", dose: "40 mg at night"), PatientMed(name: "Insulin glargine", dose: "30 units at night")]
        r.homeInfusions = [PatientInfusion(drug: "Heparin", rate: "1200 units/h")]
        r.cardiacSymptomsAnswer = true
        r.cardiacSymptoms = ["chest-pain"]
        r.mask = "difficult"
        r.maskNote = "Beard, two hands"
        r.intubation = "difficult"
        r.intubationNote = "Anterior larynx; bougie"
        r.laryngoscopyGrade = "3"
        r.attempts = 2
        r.airwayAtEnd = "intubated"
        r.ventilation = "VC 450 × 14, PEEP 8, FiO₂ 0.5"
        r.fluids["prbc"] = 2
        return r
    }
}
#endif
