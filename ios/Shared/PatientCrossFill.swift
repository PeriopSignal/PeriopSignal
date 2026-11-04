import Foundation

// MARK: - One entry, every page it belongs on (1.9, Ben's Wanted Changes)
//
// "Any info added … should cross reference and cross-fill one another." Two kinds of link:
//
//   Shared items: one problem id shown on two pages (Sepsis on Infectious and Acute illness; endocarditis on
//   Infectious and Cardiovascular; URI and pneumonia on Respiratory and Infectious; the dissections on Cardiovascular
//   and Acute illness; the unstable cervical spine on Musculoskeletal and Neurologic; Thrombophilia on Hematologic and
//   Obstetric). Nothing is copied: HistorySections lists the same id on both pages.
//
//   Fills: an entry in one place adds an entry in another (a low hemoglobin adds Anemia; permanent AF files atrial
//   fibrillation on the ECG; a chest tube is drawn on the diagram). As with the lab results (LabResults.edit), a fill is
//   made when its source appears, remembered in PatientRecord.fills (or labProblems, for the labs), and taken back only
//   if it is still the fill's own when the source goes: an entry the user made, or one the user took off, is never
//   touched again. Suggestions (the isolation precautions, a thyroid disease from the TSH) are offered, never filed.
//
// `apply(before:after:)` runs on every change to the record (PatientStore.update), with the record before and after
// the change, so a fill follows its source whichever page, quick-add line or note made the change.

/// What a link added, so only that is taken back.
struct PatientFills: Codable, Hashable {
    /// Problem ids a link added (the labs' are PatientRecord.labProblems).
    var problems: Set<String> = []
    /// Medication flags a link added ("insulin", "steroid", "anticoagulant").
    var medFlags: Set<String> = []
    /// ECG findings a link added ("Atrial fibrillation", "Paced rhythm (ventricular)").
    var ecg: Set<String> = []
    /// Devices a link added to the diagram, by the source's key ("hd-fistula", "hd-catheter", "chest-tube-left",
    /// "cied").
    var devices: [String: UUID] = [:]
    /// Medication list entries a link added, by the source's key ("sepsis-antibiotic").
    var meds: [String: UUID] = [:]
    /// Lab groups a link opened ("liver" from cirrhosis, "thyroid" from thyroid disease).
    var labSections: Set<String> = []
    /// MELD's "dialysis at least twice in the past week" set from a hemodialysis schedule.
    var dialysis = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        problems = v(.problems, [])
        medFlags = v(.medFlags, [])
        ecg = v(.ecg, [])
        devices = v(.devices, [:])
        meds = v(.meds, [:])
        labSections = v(.labSections, [])
        dialysis = v(.dialysis, false)
    }
}

/// One medication on the list (1.9): its name as picked or typed, and the dose as typed.
struct PatientMed: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = ""
    /// "5 mg daily", "40 units at night".
    var dose = ""
    /// The MedicationCatalog entry it was picked or read as; nil when typed and not recognized.
    var catalogID: String?

    init(id: UUID = UUID(), name: String = "", dose: String = "", catalogID: String? = nil) {
        self.id = id; self.name = name; self.dose = dose; self.catalogID = catalogID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        dose = (try? c.decodeIfPresent(String.self, forKey: .dose)) ?? ""
        catalogID = try? c.decodeIfPresent(String.self, forKey: .catalogID)
    }

    var text: String { [name, dose].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ") }
}

/// A limb to spare, typed by the user (1.9): which limb, and why.
struct PatientLimbAlert: Codable, Hashable, Identifiable {
    var id = UUID()
    /// "arm-right", "arm-left", "leg-right", "leg-left".
    var limb = "arm-left"
    /// "Prior axillary lymph node dissection".
    var reason = ""

    init(id: UUID = UUID(), limb: String = "arm-left", reason: String = "") { self.id = id; self.limb = limb; self.reason = reason }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        limb = (try? c.decodeIfPresent(String.self, forKey: .limb)) ?? "arm-left"
        reason = (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? ""
    }

    static let limbs: [(id: String, label: String)] = [("arm-right", "Right arm"), ("arm-left", "Left arm"), ("leg-right", "Right leg"), ("leg-left", "Left leg")]
}

enum PatientCrossFill {
    /// Keeps every fill in step with its source after a change: `before` is the record as it was, `after` as changed.
    static func apply(before: PatientRecord, after r: inout PatientRecord) {
        PatientDeviceFills.apply(before: before, after: &r)
    }
}

// MARK: Suggestions the pages show (helper APIs; nothing here is stored)

extension PatientCrossFill {
    /// An abnormal TSH (or free T4) with no Thyroid disease recorded: the line to offer ("TSH 8.2 mIU/L, high: add thyroid
    /// disease?"), or nil.
    static func thyroidSuggestion(_ r: PatientRecord) -> String? { nil }

    /// Accepting it: Thyroid disease, hypo- or hyperthyroid as the TSH reads.
    static func acceptThyroidSuggestion(_ r: inout PatientRecord) {}
}
