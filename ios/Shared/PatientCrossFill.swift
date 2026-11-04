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

// The fills (1.9), each made on a transition of its source, never on its mere presence:
//
//   source appears (absent before the change, present after it) → the target is added, unless it is there already
//     (then it is the user's, or a note's, and stays theirs), and remembered as the fill's;
//   source goes → the target is taken off, but only if it is still there and still the fill's.
//
// So an item the user takes off while its source stays does not come back until the source goes and returns; an item
// the user (or a quick-add or note line that sets the source and the target together) entered is never touched; and a
// record saved before 1.9 opens unchanged (its sources were there before any change, its fills are empty). Undo needs
// nothing of its own: apply runs inside the one PatientStore.update, so a fill is part of the same step as its source,
// and Undo puts the record back whole, fills included.
//
// What a target's own didSet in PatientRecord does not see (a lab group closed, MELD's dialysis unticked, a filled
// medication edited or deleted) is read here from `before` and `after`, before the fills are made.
//
// Fills:
//   - Anemia from a low hemoglobin (PatientAnemia: the WHO 2024 cut-offs), kept in labProblems as the labs' are.
//   - Medication flags: "On insulin" (the "insulin" problem, or gestational diabetes on insulin) → Insulin; Chronic
//     steroids (Adrenal insufficiency or chronic steroids, kind "steroids") → Chronic steroids; On anticoagulation →
//     Anticoagulant; and the medication list's own flags (MedicationCatalog.flags). A flag follows the union of its
//     sources: added when the union first wants it, taken off when no source wants it any more (if still the fill's).
//   - ECG (Ben, Nov 3; PatientECGLink): permanent AF → "Atrial fibrillation"; pacer dependent on a pacemaker or ICD →
//     "Paced rhythm (ventricular)". Paroxysmal, persistent and long-standing persistent AF file nothing.
//   - Lab groups: Cirrhosis opens Liver (MELD & CTP), Thyroid disease opens Thyroid. A group the user opened is never
//     closed.
//   - MELD's dialysis (twice or more in the past week) from a hemodialysis schedule of Mon/Wed/Fri or Tue/Thu/Sat.
//   - The sepsis antibiotic as typed → a medication on the list, renamed as it is typed, taken off when cleared.
//   - Devices on the diagram: PatientDeviceFills.
enum PatientCrossFill {
    /// Keeps every fill in step with its source after a change: `before` is the record as it was, `after` as changed.
    /// Runs on every change (every keystroke), so it only compares a few values.
    static func apply(before: PatientRecord, after r: inout PatientRecord) {
        // Anemia, as the labs' (LabResults.edit's bookkeeping).
        let lowBefore = PatientAnemia.isLow(before), lowNow = PatientAnemia.isLow(r)
        if !lowBefore && lowNow && !r.has("anemia") {
            r.noHistory = false
            r.problems.insert("anemia")
            r.labProblems.insert("anemia")
        } else if lowBefore && !lowNow && r.labProblems.contains("anemia") {
            r.problems.remove("anemia")
            r.labProblems.remove("anemia")
        }

        // ECG.
        ecg("Atrial fibrillation", was: permanentAF(before), now: permanentAF(r), &r)
        ecg("Paced rhythm (ventricular)", was: pacerDependent(before), now: pacerDependent(r), &r)

        // Lab groups.
        section("liver", was: before.has("cirrhosis"), now: r.has("cirrhosis"), before: before, &r)
        section("thyroid", was: before.has("thyroid"), now: r.has("thyroid"), before: before, &r)

        // MELD's dialysis.
        if before.dialysis && !r.dialysis { r.fills.dialysis = false }
        let dialysisBefore = scheduledDialysis(before), dialysisNow = scheduledDialysis(r)
        if !dialysisBefore && dialysisNow && !r.dialysis {
            r.dialysis = true
            r.fills.dialysis = true
        } else if dialysisBefore && !dialysisNow && r.fills.dialysis {
            if r.dialysis { r.dialysis = false }
            r.fills.dialysis = false
        }

        sepsisAntibiotic(before: before, &r)

        // Medication flags, after the medication list's own fill: wanted by any source (the history items and the
        // medication list), so a flag one source still wants is never taken off by the other.
        let wantedBefore = wantedFlags(before), wantedNow = wantedFlags(r)
        for f in wantedNow.subtracting(wantedBefore) where !r.medFlags.contains(f) {
            r.medFlags.insert(f)
            r.fills.medFlags.insert(f)
        }
        // The flag's didSet drops the bookkeeping with it.
        for f in wantedBefore.subtracting(wantedNow) where r.fills.medFlags.contains(f) { r.medFlags.remove(f) }

        PatientDeviceFills.apply(before: before, after: &r)
    }

    // MARK: Sources

    /// Diabetes on insulin (the "insulin" item beside "dm", or the RCRI's "Diabetes treated with insulin" saved before
    /// 1.9), or gestational diabetes on insulin.
    static func onInsulin(_ r: PatientRecord) -> Bool {
        r.has("insulin") || (r.hx.gdmInsulin && !r.problems.isDisjoint(with: ["gdm", "gdm-diet", "gdm-complex"]))
    }

    static func chronicSteroids(_ r: PatientRecord) -> Bool { r.has("adrenal") && r.hx.adrenalKinds.contains("steroids") }

    /// Permanent AF only (2023 ACC/AHA/ACCP/HRS: the decision not to restore sinus rhythm), so the ECG can be expected to
    /// show it; paroxysmal or persistent AF may be in sinus rhythm today.
    static func permanentAF(_ r: PatientRecord) -> Bool { r.has("af") && r.hx.afType == "permanent" }

    /// Pacer dependent on a pacemaker or ICD: ventricular pacing is present in a dependent patient whatever the mode
    /// (VVI or DDD), so the fill is "Paced rhythm (ventricular)" (a choice of the 1.9 spec).
    static func pacerDependent(_ r: PatientRecord) -> Bool { r.hx.pacerDependent && (r.has("pacemaker") || r.has("icd")) }

    /// Hemodialysis on a thrice-weekly schedule: at least twice in any past week, MELD's dialysis criterion.
    static func scheduledDialysis(_ r: PatientRecord) -> Bool {
        r.has("esrd-dialysis") && ["mwf", "tts"].contains(r.hx.dialysisSchedule ?? "")
    }

    // MARK: Targets

    /// The medication flags the record's sources want: On insulin, Chronic steroids and On anticoagulation in the
    /// history, and whatever the medication list raises (MedicationCatalog.flags).
    static func wantedFlags(_ r: PatientRecord) -> Set<String> {
        var out = MedicationCatalog.flags(for: r.homeMeds)
        if onInsulin(r) { out.insert("insulin") }
        if chronicSteroids(r) { out.insert("steroid") }
        if r.has("anticoagulation") { out.insert("anticoagulant") }
        return out
    }

    private static func ecg(_ f: String, was: Bool, now: Bool, _ r: inout PatientRecord) {
        if !was && now && !r.ecg.contains(f) {
            // A rhythm replaces the rhythm recorded before it (PatientECG.adding).
            r.ecg = PatientECG.adding(f, to: r.ecg)
            r.fills.ecg.insert(f)
        } else if was && !now && r.fills.ecg.contains(f) {
            r.ecg.removeAll { $0 == f }
        }
    }

    private static func section(_ id: String, was: Bool, now: Bool, before: PatientRecord, _ r: inout PatientRecord) {
        // Closed in this change: no longer the fill's.
        if before.labSections.contains(id) && !r.labSections.contains(id) { r.fills.labSections.remove(id) }
        if !was && now && !r.labSections.contains(id) {
            r.labSections.insert(id)
            r.fills.labSections.insert(id)
        } else if was && !now && r.fills.labSections.contains(id) {
            r.labSections.remove(id)
            r.fills.labSections.remove(id)
        }
    }

    static let sepsisAntibioticKey = "sepsis-antibiotic"

    /// The antibiotic under Sepsis, while Sepsis is recorded.
    static func antibiotic(_ r: PatientRecord) -> String {
        r.has("sepsis") ? r.hx.sepsisAntibiotic.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    /// The medication a typed antibiotic put on the list: renamed as the antibiotic is typed, taken off when it is
    /// cleared, while it is still the fill's (on the list, under the name the fill gave it). A medication of the same
    /// name the user listed stands for it.
    private static func sepsisAntibiotic(before: PatientRecord, _ r: inout PatientRecord) {
        let key = sepsisAntibioticKey
        let was = antibiotic(before), now = antibiotic(r)
        // Deleted, or renamed by the user: theirs now.
        if let id = r.fills.meds[key] {
            if let m = r.homeMeds.first(where: { $0.id == id }), same(m.name, was) {} else { r.fills.meds[key] = nil }
        }
        guard was != now else { return }
        if let id = r.fills.meds[key], let i = r.homeMeds.firstIndex(where: { $0.id == id }) {
            if now.isEmpty || r.homeMeds.contains(where: { $0.id != id && same($0.name, now) }) {
                r.homeMeds.remove(at: i)
                r.fills.meds[key] = nil
            } else {
                r.homeMeds[i].name = now
            }
        } else if was.isEmpty, !now.isEmpty, !r.homeMeds.contains(where: { same($0.name, now) }) {
            let m = PatientMed(name: now)
            r.homeMeds.append(m)
            r.fills.meds[key] = m.id
        }
    }
}

// MARK: Suggestions the pages show (helper APIs; nothing here is stored)

extension PatientCrossFill {
    // Read against the lab catalog's TSH and free T4 reference ranges (PatientLabs: ABIM ranges), one tap, never filed by
    // itself (1.9 spec). A high TSH reads as hypothyroid and a low one as hyperthyroid; a free T4 that agrees (low with a
    // high TSH, high with a low one, or normal, as in subclinical disease) keeps that type, and one that disagrees leaves
    // the type for the user. A free T4 out of range with a normal or missing TSH is offered without a type: a low free
    // T4 with a normal TSH can be central hypothyroidism.

    /// What the TSH and free T4 say, when either is out of range: the values in words and the type they point to ("hypo",
    /// "hyper") or nil.
    static func thyroidReading(_ r: PatientRecord) -> (parts: [String], type: String?)? {
        func read(_ key: String) -> (text: String, flag: LabFlag)? {
            guard let v = r.labs[key], v.isFinite, PatientLabs.isPlausible(key, v), let t = PatientLabs.test(key) else { return nil }
            let f = PatientLabs.flag(key, v, sex: r.sex)
            return (t.short + " " + t.format(v) + " " + t.unit + (f == .normal ? "" : (f == .high ? ", high" : ", low")), f)
        }
        let tsh = read("tsh"), ft4 = read("ft4")
        guard tsh?.flag.isAbnormal == true || ft4?.flag.isAbnormal == true else { return nil }
        var type: String?
        if let t = tsh, t.flag.isAbnormal {
            type = t.flag == .high ? "hypo" : "hyper"
            if let f = ft4, f.flag == t.flag { type = nil }
        }
        return ([tsh, ft4].compactMap { $0?.text }, type)
    }

    /// An abnormal TSH (or free T4) with no Thyroid disease recorded: the line to offer ("TSH 8.2 mIU/L, high: add
    /// thyroid disease (hypothyroid)?"), or nil.
    static func thyroidSuggestion(_ r: PatientRecord) -> String? {
        guard !r.has("thyroid"), let x = thyroidReading(r) else { return nil }
        let type = x.type.map { $0 == "hypo" ? " (hypothyroid)" : " (hyperthyroid)" } ?? ""
        return x.parts.joined(separator: "; ") + ": add thyroid disease" + type + "?"
    }

    /// Accepting it: Thyroid disease, hypo- or hyperthyroid as the TSH reads (a type already chosen stays). The Thyroid
    /// lab group opens by the Thyroid disease fill, as for any other way it is added.
    static func acceptThyroidSuggestion(_ r: inout PatientRecord) {
        guard let x = thyroidReading(r) else { return }
        r.noHistory = false
        r.problems.insert("thyroid")
        if r.hx.thyroidType == nil { r.hx.thyroidType = x.type }
    }
}
