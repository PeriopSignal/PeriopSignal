import Foundation

// MARK: - The ECG and the Cardiovascular history, linked (1.8.3, Ben)
//
// "ECG should integrate between pages (systems and assessment)." Rhythm and conduction findings that have a matching
// Cardiovascular history item fill both ways, with a guard on the way from history to ECG:
//
//   ECG → history, always. An ECG finding establishes the diagnosis: adding "Atrial fibrillation" to the ECG adds AF/flutter
//   to the history when it is absent (add(_:to:)). Taking the finding off the ECG never takes the diagnosis off the history.
//
//   History → ECG, only when the history says the rhythm is happening now (ongoing(_:)): a pacemaker-dependent patient is
//   paced. That finding is filed on the ECG by itself and remembered as the history's (ecgFromHistory), so taking the
//   history off takes only that finding off. Every other history item is a one-tap suggestion in the ECG editor
//   (suggestions(_:)), never filed: paroxysmal AF in sinus rhythm, or a pacemaker that is not pacing, must not appear in a
//   handoff as an ECG finding nobody saw.
//
// The guard is in `ongoing` alone. If Ben asks for it fully automatic, the suggestions move there.
enum PatientECGLink {
    // MARK: The mapping

    /// What an ECG finding establishes in the history: the Cardiovascular item (PatientCatalog's ids) and, for "Other
    /// arrhythmia", the type to write.
    struct Established: Equatable {
        var problem: String
        var type: String? = nil
        /// Words that mean the type is written already.
        var aliases: [String] = []
    }

    static let establishes: [String: Established] = [
        "Atrial fibrillation": Established(problem: "af"),
        "Atrial flutter": Established(problem: "af"),
        "Paced rhythm (atrial)": Established(problem: "pacemaker"),
        "Paced rhythm (ventricular)": Established(problem: "pacemaker"),
        "Paced rhythm (AV)": Established(problem: "pacemaker"),
        "SVT": Established(problem: "arrhythmia", type: "SVT", aliases: ["svt", "supraventricular"]),
        "Mobitz II": Established(problem: "arrhythmia", type: "Mobitz II", aliases: ["mobitz ii", "mobitz 2", "type ii", "second-degree", "second degree"]),
        "Complete heart block": Established(problem: "arrhythmia", type: "complete heart block", aliases: ["complete heart block", "third-degree", "third degree", "3rd degree", "chb"]),
    ]

    /// Conduction findings with no Cardiovascular item of their own, so none is filed from them: first-degree AV block,
    /// Mobitz I, bundle branch and fascicular blocks.
    static let notLinked: [String] = ["First-degree AV block", "Mobitz I (Wenckebach)", "Right bundle branch block", "Left bundle branch block",
                                      "Left anterior fascicular block", "Bifascicular block"]

    // MARK: The guard: history → ECG

    private static let notDependent = NoteRx(#"\b(?:not|non-?|no|never|in)\s*(?:pacemaker\s*|pacer\s*|pacing\s*)?-?\s*dependent"#)
    private static let dependentWord = NoteRx(#"\bdependent\b"#)

    /// The details of the pacemaker say the patient depends on it ("dependent", not "not dependent").
    static func dependent(_ details: String) -> Bool {
        var t = details.lowercased()
        for m in notDependent.all(t).reversed() { t = (t as NSString).replacingCharacters(in: m.range, with: " ") }
        return dependentWord.first(t) != nil
    }

    /// The ECG findings the history says are present now. Only these are filed on the ECG by themselves.
    static func ongoing(_ r: PatientRecord) -> [String] {
        var out: [String] = []
        // Pacemaker dependence is paced rhythm all the time; dependence is on ventricular pacing.
        if r.has("pacemaker"), dependent(r.hx.deviceDetails) { out.append("Paced rhythm (ventricular)") }
        return out
    }

    /// Keeps the ECG in step with the history: a finding the history newly implies is added (and remembered as the
    /// history's), and one it implied and no longer does is taken off when the history put it there. An ECG finding taken
    /// off by hand stays off while the history stays as it is.
    static func sync(_ r: inout PatientRecord) {
        let seen = r.ecg
        r.ecgFromHistory.removeAll { !seen.contains($0) }
        let now = ongoing(r)
        let before = r.ecgHistoryImplied
        guard now != before else { return }
        for f in now where !before.contains(f) && !r.ecg.contains(f) {
            r.ecg = PatientECG.adding(f, to: r.ecg)
            r.ecgFromHistory.append(f)
        }
        for f in before where !now.contains(f) && r.ecgFromHistory.contains(f) {
            r.ecg.removeAll { $0 == f }
            r.ecgFromHistory.removeAll { $0 == f }
        }
        r.ecgHistoryImplied = now
    }

    // MARK: Suggestions: history → ECG, one tap

    struct Suggestion: Identifiable, Equatable {
        /// The history item, as the Cardiovascular page names it.
        var from: String
        /// The ECG findings it could add; one is chosen.
        var findings: [String]
        var id: String { from }
        /// "From history: AF/flutter — add?"
        var prompt: String { "From history: " + from + " — add?" }
    }

    /// What the history could add to the ECG that the ECG does not say, for the ECG editor. Nothing here is stored.
    static func suggestions(_ r: PatientRecord) -> [Suggestion] {
        var out: [Suggestion] = []
        func offer(_ from: String, _ findings: [String]) {
            guard !findings.contains(where: { r.ecg.contains($0) }) else { return }
            out.append(Suggestion(from: from, findings: findings))
        }
        if r.has("af") { offer("AF/flutter", ["Atrial fibrillation", "Atrial flutter"]) }
        if r.has("pacemaker") { offer("pacemaker", ["Paced rhythm (atrial)", "Paced rhythm (ventricular)", "Paced rhythm (AV)"]) }
        if r.has("arrhythmia") {
            // The type typed under Other arrhythmia, where a finding of the ECG list is named in it.
            let type = r.hx.arrhythmiaType.lowercased()
            for finding in ["SVT", "Mobitz II", "Complete heart block"] {
                guard let e = establishes[finding], e.aliases.contains(where: { type.contains($0) }) else { continue }
                offer(e.type ?? finding, [finding])
            }
        }
        return out
    }

    // MARK: ECG → history

    /// Adds an ECG finding (PatientECG.adding) and files what it establishes in the Cardiovascular history, whether or not
    /// the history says so already. A pacemaker is not added to a patient with an ICD.
    static func add(_ finding: String, to r: inout PatientRecord) {
        r.ecg = PatientECG.adding(finding, to: r.ecg)
        // Someone saw it now, whatever suggested it.
        r.ecgFromHistory.removeAll { $0 == finding }
        guard let e = establishes[finding] else { return }
        r.noHistory = false
        switch e.problem {
        case "pacemaker":
            if !r.has("pacemaker"), !r.has("icd") { r.problems.insert("pacemaker") }
        case "arrhythmia":
            r.problems.insert("arrhythmia")
            let old = r.hx.arrhythmiaType.trimmingCharacters(in: .whitespacesAndNewlines)
            if let type = e.type, !e.aliases.contains(where: { old.lowercased().contains($0) }) {
                r.hx.arrhythmiaType = old.isEmpty ? type : old + ", " + type
            }
        default:
            r.problems.insert(e.problem)
        }
        sync(&r)
    }
}
