import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// The lock-screen and Dynamic Island countdown for the next case timer (CaseTimerNotifier starts and updates it; the
/// widget extension draws it). It carries the reminder's title and the room or case number only: no patient details.
struct CaseTimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "Cefazolin redose", "ACT check".
        var title: String
        /// "OR 12" or "Case 2".
        var caseLabel: String
        var due: Date
        /// Other timers running, in any case.
        var more: Int
    }
}
#endif
