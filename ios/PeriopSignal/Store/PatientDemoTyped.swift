import Foundation

extension PatientDemo {
    /// Made-up entries typed in lower case, as an older save holds them, for the free-text capitalization screenshots
    /// (1.8.3): the summaries and the chips read them with a capital.
    static var typed: PatientRecord {
        var r = record
        r.problems = ["htn", "seizure", "osa"]
        r.systemNotes = ["neuro": "on levetiracetam", "cv": "followed by cardiology"]
        r.otherHistory = "hereditary angioedema"
        r.allergies = "adhesive tape (rash); latex"
        r.medications = "amlodipine, metoprolol, aspirin"
        r.ecg = ["Normal sinus rhythm", "left axis, borderline voltage", "rate controlled"]
        r.ecgNotes = ""
        r.events = "transient hypotension after induction, treated with phenylephrine"
        r.medsGiven = "cefazolin 2 g 08:10; dexamethasone 4 mg"
        r.todos = "check glucose on arrival"
        r.noEvents = false
        return r
    }
}
