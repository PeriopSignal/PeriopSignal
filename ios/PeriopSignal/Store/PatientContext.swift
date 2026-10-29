import Foundation
import Observation

/// Patient details live only as long as the tool that holds them: nothing a user types about a
/// patient (weight, age) is written to disk. The one hand-off is a link from one tool to the next
/// (pediatric doses → local anesthetic), which passes the weight and age once and forgets them.
@MainActor
@Observable
final class PatientHandoff {
    private(set) var weightKg: Double?
    private(set) var ageYears: Int?

    func pass(weightKg: Double?, ageYears: Int?) {
        self.weightKg = weightKg
        self.ageYears = ageYears
    }

    /// Returns what was passed and clears it.
    func take() -> (weightKg: Double?, ageYears: Int?) {
        defer { weightKg = nil; ageYears = nil }
        return (weightKg, ageYears)
    }

    /// Keys earlier versions stored with @AppStorage; removed at launch so no patient value lingers.
    static let retiredKeys = ["ps.la.weight", "ps.la.pediatric", "ps.la.years", "ps.la.epi", "ps.peds.weight", "ps.peds.years", "ps.peds.months"]

    static func purgeStoredPatientValues() {
        for key in retiredKeys { UserDefaults.standard.removeObject(forKey: key) }
    }
}

/// Starting values for the CI screenshot run, read only from launch arguments (never from saved
/// settings); empty in release builds.
enum LaunchSeed {
    static func string(_ key: String) -> String {
        #if DEBUG
        let args = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        if let s = args[key] as? String { return s }
        if let n = args[key] as? NSNumber { return n.stringValue }
        #endif
        return ""
    }

    static func int(_ key: String, default value: Int) -> Int {
        Int(string(key)) ?? value
    }

    static func list(_ key: String) -> [String] {
        string(key).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func bool(_ key: String) -> Bool {
        let s = string(key).lowercased()
        return s == "1" || s == "true" || s == "yes"
    }
}
