import Foundation

/// Where a key opens on My Patient: an editor by name (details, procedure, demographics, history, medications,
/// assessment, airway, intraop, plan), a page of one (workup:<id>, intraop:<part>, devices:<phase>, system:<id>), the
/// Summary & Handoff tab ("handoff"), the Fill-from-note sheet ("note"), a patient received from a colleague
/// ("receive"), or a reference route such as score:rcri. The screenshot runs' -ps.patient.open uses these names, and
/// the boxes' links fall back to them after the reference routes (open(_:) in PatientView), so a saved link to an
/// editor keeps working whatever the tab looks like.
enum PatientDeepLink: Hashable {
    case editor(PatientEditor)
    case route(RefRoute)
    case summary
    case note
    case receive

    /// The editor names come first: "airway" is the Airway editor here (the reference page is the boxes' own key,
    /// resolved before this).
    static func parse(_ key: String) -> PatientDeepLink? {
        switch key {
        case "details": return .editor(.details)
        case "procedure": return .editor(.procedure)
        case "demographics": return .editor(.demographics)
        case "history": return .editor(.history)
        case "medications": return .editor(.medications)
        case "assessment": return .editor(.assessment)
        case "airway": return .editor(.airway)
        case "intraop": return .editor(.intraop)
        case "plan": return .editor(.plan)
        case "handoff": return .summary
        case "note": return .note
        case "receive": return .receive
        default:
            if let id = after("workup:", in: key) { return .editor(.workup(id)) }
            if let id = after("intraop:", in: key) { return .editor(.intraopPart(id)) }
            if let id = after("devices:", in: key) { return .editor(.devices(id)) }
            if let id = after("system:", in: key) { return .editor(.system(id)) }
            if let route = RefRoute(key: key) { return .route(route) }
            return nil
        }
    }

    /// The editor this link pushes, when it is one (the pages and the reference routes push through the navigation
    /// path too; the tab, the sheet and the received patient do not).
    var editor: PatientEditor? {
        if case .editor(let e) = self { return e }
        return nil
    }

    private static func after(_ prefix: String, in key: String) -> String? {
        guard key.hasPrefix(prefix), key.count > prefix.count else { return nil }
        return String(key.dropFirst(prefix.count))
    }
}
