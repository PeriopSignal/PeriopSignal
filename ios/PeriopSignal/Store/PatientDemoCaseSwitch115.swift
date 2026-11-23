import Foundation

#if DEBUG
/// Two made-up cases, for the screenshots of calculators that refill when another case becomes current (CaseScope; shots 1470-1489).
///   -ps.patient demo-switch        OR 4: a 67-year-old man, 92 kg, CABG x3, a penicillin rash, MRSA positive, heart disease and
///                                  high blood pressure; OR 9: a 67-year-old man, 80 kg, a revision total knee, no problems.
///   -ps.patient demo-switch-peds   OR 4: an 8-year-old girl, 28 kg, a laparoscopic appendectomy; OR 9: a 3-year-old boy, 14 kg,
///                                  a tonsillectomy.
/// -ps.patient.case 1|2 picks the case that starts as current. A tool opens for it (-ps.ref peds, -ps.ref score:rcri,
/// -ps.patient.open prophylaxis ...), and
///   -ps.case.switchAfter 12 -ps.case.switchTo 2
/// makes the second case current 12 seconds after launch, with the tool already on screen: the tool's refill is what the picture
/// shows. Nothing here is written to disk.
extension PatientDemo {
    static func caseSwitch(_ seed: String, select n: Int, now: Date = Date()) -> Seed {
        let first: PatientRecord
        let second: PatientRecord
        if seed == "demo-switch-peds" {
            first = PatientDemo112Prophylaxis.record("demo-112-proph-child") ?? PatientRecord()
            var boy = PatientRecord()
            boy.ageYears = 3; boy.sex = .male; boy.heightCm = 95; boy.weightKg = 14
            boy.setProcedures(PlannedProcedure.parse("Tonsillectomy"))
            boy.urgency = .elective
            boy.anesthetic = ["ga"]
            second = boy
        } else {
            first = PatientDemo112Prophylaxis.record("demo-112-proph-cabg") ?? PatientRecord()
            var knee = PatientDemo112Prophylaxis.record("demo-112-proph-notlisted") ?? PatientRecord()
            knee.problems = []
            second = knee
        }
        let list = [PatientCase(number: 1, record: first, room: "OR 4", now: now),
                    PatientCase(number: 2, record: second, room: "OR 9", now: now)]
        let pick = list[max(0, min(list.count - 1, n - 1))].id
        return Seed(book: PatientCaseBook(cases: list, current: pick), archived: [], rooms: [])
    }
}

extension PatientStore {
    /// Screenshot runs: -ps.case.switchAfter <seconds> -ps.case.switchTo <case number> selects that case after the delay.
    func scheduleDebugCaseSwitch() {
        let after = Double(LaunchSeed.string("ps.case.switchAfter")) ?? 0
        let number = LaunchSeed.int("ps.case.switchTo", default: 0)
        guard after > 0, number >= 1 else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(after * 1_000_000_000))
            guard let self, number <= self.cases.count else { return }
            self.selectCase(self.cases[number - 1].id)
        }
    }
}
#endif
