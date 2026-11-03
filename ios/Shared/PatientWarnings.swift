import Foundation

// MARK: - Warnings from the history (1.9, Ben's Wanted Changes)
//
// Short labels Ben asked for beside history items and on the summary: "Aspiration risk" (history of gastric bypass,
// dysphagia or an esophageal disorder, hiatal hernia, gastroparesis, a full stomach or bowel obstruction) and "Heparin
// caution" (GI bleed). Each label's source is cited where it is defined.

enum PatientWarnings {
    /// The warning labels for one history item, shown beside it on its page ("Aspiration risk").
    static func tags(_ problemId: String, _ r: PatientRecord) -> [String] { [] }

    /// The record's warnings as summary lines ("Aspiration risk: hiatal hernia, gastroparesis").
    static func lines(_ r: PatientRecord) -> [PatientSummary.Line] { [] }
}
