import Foundation
import Observation
import SwiftUI

/// Settings that shape the feed, alerts and reading experience. Stored in UserDefaults; the topic
/// list also mirrors to iCloud so a second device starts personalised.
@MainActor
@Observable
final class Preferences {
    private let defaults = UserDefaults.standard
    private let kv = NSUbiquitousKeyValueStore.default

    /// Topics the reader follows. Empty means "everything".
    var myTopics: Set<String> {
        didSet {
            let list = Array(myTopics).sorted()
            defaults.set(list, forKey: "ps.myTopics")
            kv.set(list, forKey: "ps.myTopics")
            if myTopics.isEmpty { forYou = false }
        }
    }

    /// Feed filter: only posts in the reader's topics. Reset to on whenever topics are chosen.
    var forYou: Bool { didSet { defaults.set(forYou, forKey: "ps.forYou") } }

    var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "ps.onboardingDone") } }
    /// Also show the question of the day at the top of the feed (it always lives under More).
    var showDailyQuestion: Bool { didSet { defaults.set(showDailyQuestion, forKey: "ps.showDailyQuestion") } }
    var personalizePromptDismissed: Bool { didSet { defaults.set(personalizePromptDismissed, forKey: "ps.personalizePromptDismissed") } }

    /// Earliest time of day for the morning alert (local notifications are held until then).
    var alertHour: Int { didSet { defaults.set(alertHour, forKey: "ps.alertHour") } }
    var alertMinute: Int { didSet { defaults.set(alertMinute, forKey: "ps.alertMinute") } }
    var quietWeekends: Bool { didSet { defaults.set(quietWeekends, forKey: "ps.quietWeekends") } }
    var weeklyDigest: Bool { didSet { defaults.set(weeklyDigest, forKey: "ps.weeklyDigest") } }

    /// 0.9 … 1.25; applied through PS.sys.
    var textScale: Double {
        didSet {
            defaults.set(textScale, forKey: "ps.textScale")
            PS.textScale = CGFloat(textScale)
        }
    }

    /// AVSpeechUtterance rate (0.0–1.0; 0.5 is the system default).
    var speechRate: Double { didSet { defaults.set(speechRate, forKey: "ps.speechRate") } }

    init() {
        let d = UserDefaults.standard
        let local = d.stringArray(forKey: "ps.myTopics")
        let cloud = NSUbiquitousKeyValueStore.default.array(forKey: "ps.myTopics") as? [String]
        myTopics = Set(local ?? cloud ?? [])
        forYou = d.object(forKey: "ps.forYou") as? Bool ?? !(local ?? cloud ?? []).isEmpty
        onboardingDone = d.bool(forKey: "ps.onboardingDone")
        showDailyQuestion = d.object(forKey: "ps.showDailyQuestion") as? Bool ?? false
        personalizePromptDismissed = d.bool(forKey: "ps.personalizePromptDismissed")
        alertHour = d.object(forKey: "ps.alertHour") as? Int ?? 6
        alertMinute = d.object(forKey: "ps.alertMinute") as? Int ?? 30
        quietWeekends = d.bool(forKey: "ps.quietWeekends")
        weeklyDigest = d.object(forKey: "ps.weeklyDigest") as? Bool ?? true
        textScale = d.object(forKey: "ps.textScale") as? Double ?? 1.0
        speechRate = d.object(forKey: "ps.speechRate") as? Double ?? 0.5
        PS.textScale = CGFloat(textScale)
        if d.object(forKey: "ps.firstLaunch") == nil {
            d.set(Date().timeIntervalSince1970, forKey: "ps.firstLaunch")
        }
    }

    var firstLaunch: Date {
        Date(timeIntervalSince1970: defaults.double(forKey: "ps.firstLaunch"))
    }

    /// Days since the app was first opened.
    var daysSinceFirstLaunch: Int {
        Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
    }

    var launchCount: Int { defaults.integer(forKey: "ps.launchCount") }

    /// Show the "personalize" reminder a few days in, when the reader has not picked topics.
    var shouldPromptToPersonalize: Bool {
        myTopics.isEmpty && !personalizePromptDismissed && launchCount >= 4 && daysSinceFirstLaunch >= 3
    }

    var alertTime: DateComponents { DateComponents(hour: alertHour, minute: alertMinute) }

    var alertTimeText: String {
        var comps = DateComponents(); comps.hour = alertHour; comps.minute = alertMinute
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    func toggleTopic(_ id: String) {
        if myTopics.contains(id) { myTopics.remove(id) } else { myTopics.insert(id) }
    }

    /// Topics chosen in onboarding or settings turn the "For you" filter on.
    func setTopics(_ topics: Set<String>) {
        myTopics = topics
        forYou = !topics.isEmpty
    }
}

enum TextScale: Double, CaseIterable, Identifiable {
    case small = 0.9, standard = 1.0, large = 1.12, extraLarge = 1.25
    var id: Double { rawValue }
    var label: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Default"
        case .large: return "Large"
        case .extraLarge: return "Extra large"
        }
    }
    static func nearest(_ v: Double) -> TextScale {
        allCases.min { abs($0.rawValue - v) < abs($1.rawValue - v) } ?? .standard
    }
}
