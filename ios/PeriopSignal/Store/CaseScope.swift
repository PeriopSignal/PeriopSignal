import Foundation

// MARK: - Which case a tool was filled for
//
// Ben, Nov 23 ("Yes, fix it now"): "Calculators clear and refill from the new case when the current case changes, and Save or
// Start names the case it writes to."
//
// A calculator reads the current case's weight, age, sex, scores and planned operation once, when it opens. With several
// cases going, the clinician can switch the current case while a tool is still open (or still in the Reference tab's stack),
// and the tool would go on showing, and dosing from, the last patient. Everything that decides that is here, as plain
// functions, so it can be tested without a screen:
//   - `identity`: which patient a tool belongs to. Another case becoming current, a case ended, and a patient cleared or
//     received in place all give another identity. Editing the same case does not: it is the case's id and how often its
//     patient was replaced, never its contents.
//   - `resetsOnCaseChange`: which Reference tools are rebuilt (and so refilled by their own fill-on-open code) on a new identity.
//   - the captions that name the case (its switcher label: the room, or "Case 2"), only while more than one case exists.

/// The patient a tool is for: the current case, and how many times that case's patient was replaced in place.
struct CaseIdentity: Hashable {
    var caseID: UUID
    var patient: Int
}

enum CaseScope {
    static func identity(of book: PatientCaseBook, patientEpoch: Int = 0) -> CaseIdentity {
        CaseIdentity(caseID: book.currentID, patient: patientEpoch)
    }

    // MARK: Which tools reset

    /// Ben, Nov 23: the calculators go back to what opening them fresh for the now-current case would show, typed values
    /// included (a weight typed for the last patient must not dose the next one).
    ///
    /// Left alone on purpose, so a running code or transfusion survives a switch:
    ///   - ACLS (the code timer and its checklists) and the massive transfusion tracker are global to the phone, not to a case;
    ///   - the difficult airway guide is an algorithm in progress, like ACLS, and takes nothing from a case;
    ///   - the regional, block and neuraxial guides take nothing from a case and hold no patient's numbers;
    ///   - the folders are lists.
    /// A quick reference and OB Emergencies keep their checklists and clocks and refill only the weight (`CaseScopeChange`).
    static func resetsOnCaseChange(_ route: RefRoute) -> Bool {
        switch route {
        case .score, .peds, .local, .infusions, .neuraxial, .fasting, .valves, .intervention, .ponv, .chamber, .diastolic,
             .abg, .tee, .mcs, .caseTimers, .prophylaxis:
            return true
        case .quickref, .airway, .acls, .obEmergency, .regionalFinder, .blocks, .neuraxialGuide, .mtp, .folder:
            return false
        }
    }

    // MARK: Captions

    /// More than one case: a caption names the case it is about. With one case the screens read as they always did.
    static func showsName(_ book: PatientCaseBook) -> Bool { book.cases.count > 1 }

    /// The case as the switcher names it: its room, or "Case 2".
    static func name(_ book: PatientCaseBook) -> String { book.current.label }

    /// "From My Patient" (or "From the case") beside prefilled values: with more than one case, "From OR 12".
    static func fromCaption(_ alone: String, in book: PatientCaseBook) -> String {
        showsName(book) ? "From " + name(book) : alone
    }

    /// What the values came from, for VoiceOver ("My Patient", or "OR 12").
    static func source(_ alone: String, in book: PatientCaseBook) -> String {
        showsName(book) ? name(book) : alone
    }

    /// "Saves to OR 12" under a control that writes to a case; nil with one case.
    static func writeCaption(_ lead: String, in book: PatientCaseBook) -> String? {
        showsName(book) ? lead + " " + name(book) : nil
    }

    /// A caption an engine words as "From the case: Penicillin (rash)", naming the case with more than one: "From OR 12: Penicillin
    /// (rash)". Any other text, and every text with one case, is returned as it is.
    static func named(_ caption: String, lead: String, in book: PatientCaseBook) -> String {
        guard showsName(book), caption.hasPrefix(lead) else { return caption }
        return "From " + name(book) + ": " + String(caption.dropFirst(lead.count))
    }

    // MARK: Weight

    /// The weight as a tool's field holds it (what the weight field fills in), empty when the case has none.
    static func weightText(_ kg: Double?) -> String {
        guard let kg, kg > 0 else { return "" }
        return NumText.exact(kg)
    }
}
