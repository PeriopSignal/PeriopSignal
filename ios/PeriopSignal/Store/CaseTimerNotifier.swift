import Foundation
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Turns the case timers of every open case into local notifications (they fire with the app closed and show on the lock
/// screen) and one Live Activity counting down to the next. A notification carries the reminder and the room or case
/// number ("OR 12 · Cefazolin redose due"), never a patient detail. Called whenever the case book changes; it does
/// nothing when the timers' content is a draft in a release build, or in a screenshot run.
@MainActor
final class CaseTimerNotifier {
    static let shared = CaseTimerNotifier()
    static let prefix = "ps.timer."

    private var signature = ""
    private var asked = false

    /// The first time a timer starts: ask for notifications if the reader hasn't been asked yet.
    func requestPermissionIfNeeded() {
        guard !asked, PatientTips.launch == .normal else { return }
        asked = true
        Task {
            let c = UNUserNotificationCenter.current()
            if await c.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await c.requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
    }

    func sync(book: PatientCaseBook, data: CaseTimerData?, now: Date = Date()) {
        guard PatientTips.launch == .normal else { return }
        var items: [CaseTimerItem] = []
        if let data, DraftGate.shows("caseTimers") {
            items = CaseTimerSchedule.items(book.cases.map { (id: $0.id, label: $0.label, record: $0.record) }, data: data)
        }
        let sig = items.map { "\($0.id)|\($0.reminder.title)|\($0.reminder.due?.timeIntervalSince1970 ?? 0)" }.joined(separator: ";")
        guard sig != signature else { return }
        signature = sig
        let timed = items.filter { $0.reminder.due != nil }
        Task { await schedule(timed, now: now) }
        updateActivity(timed)
    }

    private func schedule(_ items: [CaseTimerItem], now: Date) async {
        let c = UNUserNotificationCenter.current()
        let old = await c.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        c.removePendingNotificationRequests(withIdentifiers: old)
        for item in items {
            guard let due = item.reminder.due, due.timeIntervalSince(now) > 5 else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.caseLabel + " · " + item.reminder.title + " due"
            content.body = item.reminder.detail
            content.sound = .default
            content.threadIdentifier = "ps.timers"
            content.userInfo = ["tab": "patient"]
            // Time Sensitive (breaking through Focus) needs that capability on the App ID; until it is added, .active.
            content.interruptionLevel = .active
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: due.timeIntervalSince(now), repeats: false)
            try? await c.add(UNNotificationRequest(identifier: Self.prefix + item.id, content: content, trigger: trigger))
        }
    }

    private func updateActivity(_ items: [CaseTimerItem]) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let running = Activity<CaseTimerActivityAttributes>.activities
        guard let next = items.first, let due = next.reminder.due else {
            Task { for a in running { await a.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let state = CaseTimerActivityAttributes.ContentState(title: next.reminder.title, caseLabel: next.caseLabel, due: due,
                                                             more: max(0, items.count - 1))
        let content = ActivityContent(state: state, staleDate: nil)
        if let a = running.first {
            Task { await a.update(content) }
        } else {
            _ = try? Activity.request(attributes: CaseTimerActivityAttributes(), content: content)
        }
        #endif
    }
}
