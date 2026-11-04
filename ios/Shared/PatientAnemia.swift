import Foundation

// MARK: - Anemia from the hemoglobin (1.9, Ben: "should be automatically checked if low on CBC filled from labs")
//
// The cut-offs of the WHO Guideline on haemoglobin cutoffs to define anaemia in individuals and populations (World
// Health Organization, Geneva, 2024), as the 1.9 spec states them (Ben's decisions): anaemia below
//   - 13 g/dL in men 15 years and older,
//   - 12 g/dL in non-pregnant women 15 years and older,
//   - 11 g/dL in pregnancy, first and third trimesters, and 10.5 g/dL in the second (14+0 to 27+6 weeks).
// Under 15 years nothing is checked by itself (the guideline's childhood cut-offs differ by age band). With the sex
// unknown and no pregnancy recorded the lower adult cut-off, 12, is used; pregnant with no gestation recorded, 11.
// The guideline's adjustments for altitude and smoking are not applied. Only the measured Hb (PatientRecord.labs["hb"])
// is read, never the Hct estimate (PatientLabs.estimate).
//
// The fill itself is PatientCrossFill's: Anemia is added when the Hb becomes low, remembered in labProblems as the
// labs' (as LabResults.edit does for a positive result), and taken off when the Hb is no longer low only if it is
// still the labs'.
enum PatientAnemia {
    /// The cut-off (g/dL) for this record, or nil when nothing should be checked by itself (under 15 years).
    static func cutoff(_ r: PatientRecord) -> Double? {
        if let a = r.ageYears, a < 15 { return nil }
        if r.has("pregnant") {
            guard let w = r.hx.gestationWeeks else { return 11 }
            return (14...27).contains(w) ? 10.5 : 11
        }
        return r.sex == .male ? 13 : 12
    }

    /// The measured Hb is below the cut-off.
    static func isLow(_ r: PatientRecord) -> Bool {
        guard let hb = r.labs["hb"], hb.isFinite, PatientLabs.isPlausible("hb", hb), let c = cutoff(r) else { return false }
        return hb < c
    }

    /// "Hb 10.9 g/dL, below 12 (WHO 2024)": the reason shown beside an Anemia the labs added; nil when they did not.
    static func reason(_ r: PatientRecord) -> String? {
        guard r.labProblems.contains("anemia"), isLow(r), let hb = r.labs["hb"], let c = cutoff(r) else { return nil }
        return "Hb " + NumText.short(hb) + " g/dL, below " + NumText.short(c) + " (WHO 2024)"
    }
}
