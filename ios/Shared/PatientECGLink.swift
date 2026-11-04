import Foundation

// MARK: - The ECG and the Cardiovascular history, linked (1.8.3, Ben)
//
// "ECG should integrate between pages (systems and assessment)." Rhythm and conduction findings that have a matching
// Cardiovascular history item are linked, with a guard on the way from history to ECG:
//
//   ECG → history, automatic. An ECG finding establishes the diagnosis: adding "Atrial fibrillation" to the ECG adds
//   AF/flutter to the history when it is absent (add(_:to:)). Taking the finding off the ECG never takes the diagnosis off
//   the history. A paced rhythm adds the pacemaker only where it is surely one: not with temporary or epicardial wires, and
//   not beside an ICD or CRT (pacemakerBlocked); there it is a one-tap suggestion (pacemakerSuggested).
//
//   History → ECG, never automatic (decided with the independent review): the ECG editor offers a one-tap suggestion for
//   each history item (suggestions(_:)), and nothing is filed on the ECG until it is tapped. Paroxysmal AF in sinus rhythm,
//   or a pacemaker that is not pacing, must not appear in a handoff as an ECG finding nobody saw, and free text such as
//   "not PPM dependent" is not read. If Ben asks for it fully automatic, the filing goes in one place: suggestions.
//
//   The exception (Ben, Nov 3; 1.9): two structured history answers say what the ECG must show, so they file it, as
//   fills (PatientCrossFill): AF typed as permanent (2023 ACC/AHA/ACCP/HRS AF guideline, Joglar JA, et al. Circulation
//   2024;149:e1–e156: the decision not to pursue sinus rhythm) files "Atrial fibrillation", and "Pacer dependent" on a
//   pacemaker or ICD files "Paced rhythm (ventricular)" (ventricular pacing is present in a dependent patient whether the
//   mode is VVI or DDD). A fill is taken off when its answer goes, only if it is still on the ECG and still the fill's;
//   one the user took off stays off. Paroxysmal, persistent and long-standing persistent AF file nothing (the patient may
//   be in sinus rhythm), and everything else stays a one-tap suggestion below.
//
//   Epicardial pacing wires on the diagram (helper 4's device kind, read by its raw value so this file does not depend
//   on its name) count as temporary pacing, as the words do.
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

    static let pacedFindings = ["Paced rhythm (atrial)", "Paced rhythm (ventricular)", "Paced rhythm (AV)"]

    /// Conduction findings with no Cardiovascular item of their own, so none is filed from them: first-degree AV block,
    /// Mobitz I, bundle branch and fascicular blocks.
    static let notLinked: [String] = ["First-degree AV block", "Mobitz I (Wenckebach)", "Right bundle branch block", "Left bundle branch block",
                                      "Left anterior fascicular block", "Bifascicular block"]

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
        if r.has("pacemaker") { offer("pacemaker", pacedFindings) }
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

    private static let temporaryPacing = NoteRx(#"\b(?:epicardial|temporary|temp\.?\s*(?:pac\w*|wires?)|pacing wires?|pacer wires?|transvenous|external pac\w*|transcutaneous|post-?op(?:erative)? pac\w*)\b"#)
    private static let resynchronizationOrICD = NoteRx(#"\b(?:crt(?:-?[dp])?|biventricular|bi-?v|resynchroni[sz]ation|icd|aicd|defibrillator)\b"#)
    static var patterns: [NoteRx] { [temporaryPacing, resynchronizationOrICD] }

    /// Temporary or epicardial pacing wires are in the record's words (the ECG's notes, device details, the procedure, other
    /// history): a paced rhythm there is not a permanent pacemaker.
    static func temporaryPacingContext(_ r: PatientRecord) -> Bool {
        let texts = [r.ecgNotes, r.hx.deviceDetails, r.procedure, r.otherHistory, r.anesthesiaNotes, r.systemNotes["cv"] ?? ""]
            + r.devices.map { $0.detail + " " + $0.settings.values.joined(separator: " ") }
        return epicardialWires(r) || texts.contains { temporaryPacing.first($0) != nil }
    }

    /// Epicardial pacing wires in place on the diagram (1.9): any device kind whose raw value names them.
    static func epicardialWires(_ r: PatientRecord) -> Bool {
        r.currentDevices().contains { $0.kind.rawValue.lowercased().contains("epicardial") }
    }

    /// An ICD or CRT is in the history already, or on the diagram (a generator in place whose detail says so, 1.9), so a
    /// paced rhythm may be its own.
    static func deviceAlready(_ r: PatientRecord) -> Bool {
        r.has("icd") || resynchronizationOrICD.first(r.hx.deviceDetails) != nil
            || r.currentDevices().contains { $0.kind == .cied && resynchronizationOrICD.first($0.detail) != nil }
    }

    /// A paced rhythm does not add a pacemaker to the history here.
    static func pacemakerBlocked(_ r: PatientRecord) -> Bool { temporaryPacingContext(r) || deviceAlready(r) }

    /// The ECG says paced, the history has no pacemaker, and none was added by itself: offered, one tap
    /// ("From ECG: paced rhythm — add pacemaker to the history?").
    static func pacemakerSuggested(_ r: PatientRecord) -> Bool {
        !r.has("pacemaker") && r.ecg.contains(where: { pacedFindings.contains($0) }) && pacemakerBlocked(r)
    }

    static func addPacemaker(to r: inout PatientRecord) {
        r.noHistory = false
        r.problems.insert("pacemaker")
    }

    /// Adds an ECG finding (PatientECG.adding) and files what it establishes in the Cardiovascular history, whether or not
    /// the history says so already.
    static func add(_ finding: String, to r: inout PatientRecord) {
        let before = r
        r.ecg = PatientECG.adding(finding, to: r.ecg)
        guard let e = establishes[finding] else { return }
        r.noHistory = false
        switch e.problem {
        case "pacemaker":
            if !r.has("pacemaker"), !pacemakerBlocked(before) { r.problems.insert("pacemaker") }
        case "arrhythmia":
            r.problems.insert("arrhythmia")
            let old = r.hx.arrhythmiaType.trimmingCharacters(in: .whitespacesAndNewlines)
            if let type = e.type, !e.aliases.contains(where: { old.lowercased().contains($0) }) {
                r.hx.arrhythmiaType = old.isEmpty ? type : old + ", " + type
            }
        default:
            r.problems.insert(e.problem)
        }
    }
}
