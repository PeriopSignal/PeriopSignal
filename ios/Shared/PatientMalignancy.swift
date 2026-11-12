import Foundation

// MARK: - Malignancy on the Heme & Oncology page (1.12, Ben's note: "reference list of common cancers to problem by
// systems (malignancy -> common list; if multiple)")
//
// One adult item, "Malignancy" ("malignancy"), recorded in one place whatever the organ: the cancers chosen (several can
// be), a cancer not on the list typed as Other, a status (Active or In remission, one of them), Metastatic, and the
// treatment (chemotherapy, radiation). They sit in PatientHistoryDetails (malignancies, malignancyOther,
// malignancyStatus, malignancyMetastatic, malignancyTreatment), beside the problem id.
//
// Prostate is the same fact as the Genitourinary page's "Prostate cancer" ("prostate-cancer"): its chip here reads and
// writes that problem, so it is recorded once and printed once in a summary.
//
// Nothing about a cancer changes a risk score or an alert: "malignancy" and the details carry no RCRI item and no warning.
// The ASA suggestion (1.12, Ben, Nov 12) gives a malignancy, and the prostate cancer that is its Prostate chip, class II when
// the status is In remission and Metastatic is not set, and class III otherwise (PatientRules.asaDefinitionLevel); the two
// are one reason line.

enum PatientMalignancy {
    /// DRAFT FOR BEN TO EDIT. The common cancers, in the order of the chips (the groups are Ben's: head and neck and
    /// thoracic; gastrointestinal; genitourinary and gynecologic; breast and skin; blood; brain and soft tissue). `id` is
    /// what is stored, `label` the chip, `words` what a summary says. Adding, removing or renaming a cancer is a change to
    /// this list only (a typing rule for a new one is in PatientNote, `malignancyRules`).
    static let sites: [(id: String, label: String, words: String)] = [
        ("lung", "Lung", "lung cancer"),
        ("esophageal", "Esophageal", "esophageal cancer"),
        ("head-neck", "Head and neck", "head and neck cancer"),
        ("thyroid", "Thyroid", "thyroid cancer"),
        ("colorectal", "Colorectal", "colorectal cancer"),
        ("gastric", "Gastric", "gastric cancer"),
        ("pancreatic", "Pancreatic", "pancreatic cancer"),
        ("liver", "Liver (HCC)", "hepatocellular carcinoma"),
        ("prostate", "Prostate", "prostate cancer"),
        ("bladder", "Bladder", "bladder cancer"),
        ("kidney", "Kidney", "kidney cancer"),
        ("ovarian", "Ovarian", "ovarian cancer"),
        ("uterine", "Uterine", "uterine cancer"),
        ("cervical", "Cervical", "cervical cancer"),
        ("breast", "Breast", "breast cancer"),
        ("melanoma", "Melanoma", "melanoma"),
        ("lymphoma", "Lymphoma", "lymphoma"),
        ("leukemia", "Leukemia", "leukemia"),
        ("myeloma", "Multiple myeloma", "multiple myeloma"),
        ("brain", "Brain", "brain cancer"),
        ("sarcoma", "Sarcoma", "sarcoma"),
    ]

    /// Status, one of them (or none): the chip, and the summary's words.
    static let statuses: [(id: String, label: String, words: String)] = [
        ("active", "Active", "active"), ("remission", "In remission", "in remission"),
    ]

    /// Treatment, any of them: the chip, and the summary's words.
    static let treatments: [(id: String, label: String, words: String)] = [
        ("chemo", "Chemotherapy", "chemotherapy"), ("radiation", "Radiation", "radiation"),
    ]

    /// The problem the item files; the Genitourinary item the Prostate chip stands for.
    static let problemID = "malignancy"
    static let prostateProblem = "prostate-cancer"
    static let prostateID = "prostate"

    // MARK: Reading and writing the record

    /// The cancers chosen, by site id: the ones stored, and Prostate when the prostate-cancer problem is recorded (from
    /// either page).
    static func selected(_ r: PatientRecord) -> Set<String> {
        var s = r.hx.malignancies
        if r.problems.contains(prostateProblem) { s.insert(prostateID) }
        return s
    }

    /// Whether anything is recorded for the item: its problem, the prostate problem, or any detail.
    static func isRecorded(_ r: PatientRecord) -> Bool {
        let d = r.hx
        return r.problems.contains(problemID) || r.problems.contains(prostateProblem) || !d.malignancies.isEmpty
            || !trimmed(d.malignancyOther).isEmpty || d.malignancyStatus != nil || d.malignancyMetastatic || !d.malignancyTreatment.isEmpty
    }

    /// One cancer on or off. Choosing one chooses the item (and takes "No significant medical history" off); Prostate is
    /// the Genitourinary problem, so it is on that page too.
    static func setSite(_ id: String, _ on: Bool, _ r: inout PatientRecord) {
        if id == prostateID {
            if on { r.problems.insert(prostateProblem) } else { r.problems.remove(prostateProblem) }
        } else if on {
            r.hx.malignancies.insert(id)
        } else {
            r.hx.malignancies.remove(id)
        }
        if on {
            r.problems.insert(problemID)
            r.noHistory = false
        }
    }

    /// The set of cancers the chips show, written: each site that differs from the record is turned on or off.
    static func setSites(_ new: Set<String>, _ r: inout PatientRecord) {
        let old = selected(r)
        for s in sites where new.contains(s.id) != old.contains(s.id) { setSite(s.id, new.contains(s.id), &r) }
    }

    /// Status, one of them or nil.
    static func setStatus(_ id: String?, _ r: inout PatientRecord) {
        var kept: String?
        if let id, statuses.contains(where: { $0.id == id }) { kept = id }
        r.hx.malignancyStatus = kept
        if kept != nil { choose(&r) }
    }

    static func setMetastatic(_ on: Bool, _ r: inout PatientRecord) {
        r.hx.malignancyMetastatic = on
        if on { choose(&r) }
    }

    static func setTreatment(_ ids: Set<String>, _ r: inout PatientRecord) {
        let known = Set(treatments.map(\.id))
        r.hx.malignancyTreatment = ids.intersection(known)
        if !r.hx.malignancyTreatment.isEmpty { choose(&r) }
    }

    /// A detail chosen chooses the item.
    private static func choose(_ r: inout PatientRecord) {
        r.problems.insert(problemID)
        r.noHistory = false
    }

    /// Clears the item and everything under it, the Genitourinary prostate problem with it (one fact).
    static func clear(_ r: inout PatientRecord) {
        r.problems.remove(problemID)
        r.problems.remove(prostateProblem)
        r.hx.malignancies = []
        r.hx.malignancyOther = ""
        r.hx.malignancyStatus = nil
        r.hx.malignancyMetastatic = false
        r.hx.malignancyTreatment = []
    }

    // MARK: Words

    private static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The item in one phrase, for the History list, the tile, the box and both summaries:
    /// "lung cancer (active, metastatic; chemotherapy, radiation)", "breast cancer; lymphoma (in remission)",
    /// "malignancy" when it is chosen with nothing else, and what was typed under Other as typed. Nil when nothing is
    /// recorded. The cancers come in the order of the list; a status, Metastatic and the treatment are said once, after
    /// them all.
    static func words(_ r: PatientRecord) -> String? {
        guard isRecorded(r) else { return nil }
        let d = r.hx
        let chosen = selected(r)
        var names = sites.filter { chosen.contains($0.id) }.map(\.words)
        if !trimmed(d.malignancyOther).isEmpty { names.append(trimmed(d.malignancyOther)) }
        var state: [String] = []
        if let s = d.malignancyStatus, let o = statuses.first(where: { $0.id == s }) { state.append(o.words) }
        if d.malignancyMetastatic { state.append("metastatic") }
        let treatment = treatments.filter { d.malignancyTreatment.contains($0.id) }.map(\.words)
        var detail: [String] = []
        if !state.isEmpty { detail.append(state.joined(separator: ", ")) }
        if !treatment.isEmpty { detail.append(treatment.joined(separator: ", ")) }
        let head = names.isEmpty ? "malignancy" : names.joined(separator: "; ")
        return head + (detail.isEmpty ? "" : " (" + detail.joined(separator: "; ") + ")")
    }

    // MARK: Typing (the note reader and the quick-add bar)

    /// What a typed line says about the item: the cancers (site ids, never Prostate, which is its own problem), a cancer not
    /// on the list as typed, a status, Metastatic, the treatment. Kept in a finding as a string (`encode`).
    struct Typed: Equatable {
        var sites: [String] = []
        var other = ""
        var status: String?
        var metastatic = false
        var treatment: [String] = []

        var isEmpty: Bool { sites.isEmpty && other.isEmpty && status == nil && !metastatic && treatment.isEmpty }
    }

    static func encode(_ t: Typed) -> String {
        [t.sites.joined(separator: ","), t.other.replacingOccurrences(of: "|", with: "/"), t.status ?? "", t.metastatic ? "1" : "",
         t.treatment.joined(separator: ",")].joined(separator: "|")
    }

    static func decode(_ s: String) -> Typed {
        let p = s.components(separatedBy: "|")
        func part(_ i: Int) -> String { i < p.count ? p[i] : "" }
        func list(_ s: String) -> [String] { s.split(separator: ",").map(String.init) }
        var t = Typed()
        let siteIDs = Set(sites.map(\.id)), treatmentIDs = Set(treatments.map(\.id))
        t.sites = list(part(0)).filter { siteIDs.contains($0) }
        t.other = part(1)
        t.status = part(2).isEmpty ? nil : part(2)
        t.metastatic = part(3) == "1"
        t.treatment = list(part(4)).filter { treatmentIDs.contains($0) }
        return t
    }

    /// A typed record in words, for a finding's label and the review: the cancers, then the state and treatment, as the
    /// summary says them.
    static func words(_ t: Typed) -> String {
        var names = sites.filter { t.sites.contains($0.id) }.map(\.words)
        if !t.other.isEmpty { names.append(t.other) }
        var state: [String] = []
        if let s = t.status, let o = statuses.first(where: { $0.id == s }) { state.append(o.words) }
        if t.metastatic { state.append("metastatic") }
        let treatment = treatments.filter { t.treatment.contains($0.id) }.map(\.words)
        var detail: [String] = []
        if !state.isEmpty { detail.append(state.joined(separator: ", ")) }
        if !treatment.isEmpty { detail.append(treatment.joined(separator: ", ")) }
        let head = names.joined(separator: "; ")
        if detail.isEmpty { return head }
        return head.isEmpty ? detail.joined(separator: "; ") : head + " (" + detail.joined(separator: "; ") + ")"
    }

    /// Writes a typed record into the record: the cancers join those there, a status replaces the one there, Metastatic and
    /// the treatment are added (never taken off by a line that does not say them).
    static func apply(_ t: Typed, to r: inout PatientRecord) {
        r.problems.insert(problemID)
        r.noHistory = false
        for id in t.sites { r.hx.malignancies.insert(id) }
        if !t.other.isEmpty {
            let have = trimmed(r.hx.malignancyOther)
            if !have.lowercased().contains(t.other.lowercased()) { r.hx.malignancyOther = have.isEmpty ? t.other : have + "; " + t.other }
        }
        if let s = t.status { r.hx.malignancyStatus = s }
        if t.metastatic { r.hx.malignancyMetastatic = true }
        for id in t.treatment { r.hx.malignancyTreatment.insert(id) }
    }

    /// Whether a typed record says nothing the record does not already: the review marks such a finding as recorded.
    static func isRecorded(_ t: Typed, in r: PatientRecord) -> Bool {
        guard r.problems.contains(problemID) else { return false }
        let d = r.hx
        if !t.sites.allSatisfy({ d.malignancies.contains($0) }) { return false }
        if !t.other.isEmpty, !trimmed(d.malignancyOther).lowercased().contains(t.other.lowercased()) { return false }
        if let s = t.status, d.malignancyStatus != s { return false }
        if t.metastatic, !d.malignancyMetastatic { return false }
        return t.treatment.allSatisfy { d.malignancyTreatment.contains($0) }
    }

    /// The state a typed record would change, for "replaces" in the review ("in remission" over "active"); nil if none.
    static func replaced(_ t: Typed, in r: PatientRecord) -> String? {
        guard let s = t.status, let old = r.hx.malignancyStatus, old != s else { return nil }
        return statuses.first { $0.id == old }?.words
    }
}
