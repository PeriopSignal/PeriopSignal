import XCTest
@testable import PeriopSignal

/// 1.9 review (history and cross-fill): peripartum cardiomyopathy as known heart disease, the Social page and the
/// Anemia fill leaving "No significant medical history" alone, a 1.8.3 "aki" keeping its wording, an Anemia the user took
/// off staying off while the age is typed, and the sepsis antibiotic's medication against the user's own entries.
final class Review19HistoryCrossfillTests: XCTestCase {

    /// One change as PatientStore.update makes it: the change, then the fills.
    private func change(_ r: inout PatientRecord, _ body: (inout PatientRecord) -> Void) {
        let before = r
        body(&r)
        PatientCrossFill.apply(before: before, after: &r)
    }

    private func section(_ system: String, _ id: String) throws -> HistorySection {
        try XCTUnwrap(HistorySections.sections(system)?.first { $0.id == id }, system + "." + id)
    }

    private func healthy() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 40; r.sex = .female; r.heightCm = 165; r.weightKg = 65
        r.noHistory = true
        return r
    }

    // MARK: Peripartum cardiomyopathy

    /// "ppcm" (LVEF < 45%, or no EF typed) is a cardiomyopathy: known heart disease (§4.1), as "peripartum-cm" is.
    func testPPCMIsKnownHeartDisease() {
        var r = PatientRecord()
        r.ageYears = 30; r.sex = .female; r.heightCm = 165; r.weightKg = 68; r.smoking = "never"
        r.problems = ["pregnant"]
        XCTAssertTrue(PatientFunctional.noCardiacRisk(r), "nothing recorded yet")
        for ef in [nil, 42.0] as [Double?] {
            var p = r
            HistorySections.setPPCMEF(ef, &p)
            XCTAssertTrue(p.has("ppcm"))
            XCTAssertTrue(PatientFunctional.knownCVD(p), "LVEF " + (ef.map { String($0) } ?? "not typed"))
            XCTAssertFalse(PatientFunctional.noCardiacRisk(p))
        }
        var low = r
        HistorySections.setPPCMEF(30, &low)
        XCTAssertTrue(PatientFunctional.knownCVD(low))
    }

    // MARK: No significant medical history

    /// Never smoked and no alcohol are ASA I's "healthy, non-smoking, no or minimal alcohol use": recording them keeps
    /// the toggle and the ASA I suggestion. An alcohol answer that files a problem still clears it.
    func testSocialAnswersKeepNoSignificantHistory() throws {
        var r = healthy()
        XCTAssertEqual(PatientRules.asaSuggestion(r)?.level, 1)
        HistorySections.select(try section("social", "smoking"), &r)
        HistorySections.setSmoking("never", &r)
        HistorySections.select(try section("social", "alcohol"), &r)
        HistorySections.setAlcohol("none", &r)
        XCTAssertTrue(r.noHistory)
        XCTAssertEqual(PatientRules.asaSuggestion(r)?.level, 1)
        XCTAssertTrue(PatientSummary.historyLines(r).contains { $0.text == "No significant medical history" })
        // A problem does clear it.
        HistorySections.setAlcohol("current", &r)
        XCTAssertFalse(r.noHistory)
        var d = healthy()
        HistorySections.select(try section("social", "drugs"), &d)
        XCTAssertFalse(d.noHistory, "illicit drug use is a problem")
    }

    /// A Hb typed digit by digit passes through a low "1": the Anemia it adds for that keystroke goes on the next, and
    /// "No significant medical history" comes back with it.
    func testTypingANormalHbKeepsNoSignificantHistory() {
        var r = healthy()
        for t in [1.0, 14.0, 14.2] { change(&r) { $0.labs["hb"] = t } }
        XCTAssertFalse(r.has("anemia"))
        XCTAssertTrue(r.noHistory, "given back with the Anemia the fill took back")
        XCTAssertEqual(PatientRules.asaSuggestion(r)?.level, 1)
        XCTAssertEqual(r.fills, PatientFills())
        // A low Hb that stays: Anemia, and the toggle off.
        var low = healthy()
        for t in [1.0, 10.0, 10.5] { change(&low) { $0.labs["hb"] = t } }
        XCTAssertTrue(low.has("anemia"))
        XCTAssertFalse(low.noHistory)
        // Another problem recorded meanwhile: the toggle is not the fill's to give back.
        var other = healthy()
        change(&other) { $0.labs["hb"] = 1 }
        change(&other) { _ = $0.problems.insert("htn") }
        change(&other) { $0.labs["hb"] = 14 }
        XCTAssertFalse(other.noHistory)
        XCTAssertEqual(other.problems, ["htn"])
    }

    // MARK: Anemia and the age

    /// An Anemia the user took off stays off while the age is typed: every adult age passes through one digit (under 15,
    /// no cut-off) on its way, which is not the low reading going and coming back.
    func testAnemiaTakenOffStaysOffWhileTheAgeIsTyped() {
        var r = PatientRecord()
        r.sex = .female; r.problems = ["htn"]
        change(&r) { $0.labs["hb"] = 10.5 }
        XCTAssertTrue(r.has("anemia"))
        change(&r) { _ = $0.problems.remove("anemia") }
        for a in [6.0, 67.0] { change(&r) { $0.ageYears = a } }
        XCTAssertFalse(r.has("anemia"), "typed 6, then 67")
        for a in [6.0, 68.0] { change(&r) { $0.ageYears = a } }
        XCTAssertFalse(r.has("anemia"), "edited 67 to 68")
        // The fill's own Anemia is kept through the same typing.
        var f = PatientRecord()
        f.sex = .female; f.ageYears = 45; f.problems = ["htn"]
        change(&f) { $0.labs["hb"] = 10.5 }
        for a in [4.0, 46.0] { change(&f) { $0.ageYears = a } }
        XCTAssertTrue(f.has("anemia"))
        XCTAssertTrue(f.labProblems.contains("anemia"))
        // The Hb itself still decides.
        change(&f) { $0.labs["hb"] = 13 }
        XCTAssertFalse(f.has("anemia"))
    }

    // MARK: "aki" saved before 1.9

    func testAKISavedBefore19KeepsItsWording() throws {
        let old = #"{"ageYears": 60, "problems": ["aki"]}"#
        var r = try JSONDecoder().decode(PatientRecord.self, from: Data(old.utf8))
        XCTAssertTrue(r.hx.akiBefore19)
        XCTAssertEqual(HistorySections.renalItems(r), ["AKI or ESRD not on scheduled dialysis"])
        let reason = try XCTUnwrap(PatientRules.asaSuggestion(r)?.reasons.first)
        XCTAssertEqual(reason.finding, "Acute kidney injury, or ESRD not on scheduled dialysis")
        XCTAssertEqual(reason.level, 4, "the class is kept")
        // Saved and opened again by 1.9: still the old wording.
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertTrue(again.hx.akiBefore19)
        // Taken off and chosen again: 1.9's Acute kidney injury.
        change(&r) { _ = $0.problems.remove("aki") }
        XCTAssertFalse(r.hx.akiBefore19)
        change(&r) { _ = $0.problems.insert("aki") }
        XCTAssertEqual(HistorySections.renalItems(r), ["AKI"])
        // An AKI recorded by 1.9.
        var n = PatientRecord(); n.ageYears = 60; n.problems = ["aki"]
        let saved = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(n))
        XCTAssertFalse(saved.hx.akiBefore19)
        XCTAssertEqual(HistorySections.renalItems(saved), ["AKI"])
        XCTAssertEqual(PatientRules.asaSuggestion(saved)?.reasons.first?.finding, "Acute kidney injury")
    }

    // MARK: The sepsis antibiotic

    /// The same drug added by the user (from the list or a note) merges into the fill's medication: it is theirs then,
    /// and clearing the antibiotic leaves it.
    func testAntibioticMergedIntoByTheUserIsKept() {
        var r = PatientRecord(); r.ageYears = 50
        change(&r) { $0.problems.insert("sepsis"); $0.hx.sepsisAntibiotic = "Vancomycin" }
        XCTAssertEqual(r.homeMeds.map(\.name), ["Vancomycin"])
        change(&r) { MedicationCatalog.apply(MedicationCatalog.parse("Vancomycin 1.25 g q12h"), to: &$0.homeMeds) }
        XCTAssertEqual(r.homeMeds.count, 1)
        XCTAssertFalse(r.homeMeds[0].dose.isEmpty, "merged into the fill's medication")
        change(&r) { $0.hx.sepsisAntibiotic = "" }
        XCTAssertEqual(r.homeMeds.count, 1, "the user's entry stays")
        XCTAssertEqual(r.homeMeds.first?.catalogID, "vancomycin")
        // A dose typed on the fill's medication: theirs too.
        var d = PatientRecord(); d.ageYears = 50
        change(&d) { $0.problems.insert("sepsis"); $0.hx.sepsisAntibiotic = "Cefepime" }
        change(&d) { $0.homeMeds[0].dose = "2 g q8h" }
        change(&d) { _ = $0.problems.remove("sepsis") }
        XCTAssertEqual(d.homeMeds.map(\.text), ["Cefepime 2 g q8h"])
        // Untouched: still taken off.
        var u = PatientRecord(); u.ageYears = 50
        change(&u) { $0.problems.insert("sepsis"); $0.hx.sepsisAntibiotic = "Cefepime" }
        change(&u) { $0.hx.sepsisAntibiotic = "" }
        XCTAssertTrue(u.homeMeds.isEmpty)
    }

    /// A listed drug typed by brand or abbreviation is the same drug: no second entry.
    func testAntibioticByBrandOrAbbreviationIsNotListedTwice() {
        for (listed, typed) in [("Vancomycin", "vanc"), ("Piperacillin-tazobactam", "Zosyn")] {
            var r = PatientRecord(); r.ageYears = 50
            change(&r) { $0.homeMeds = [PatientMed(name: listed)] }
            change(&r) { $0.problems.insert("sepsis"); $0.hx.sepsisAntibiotic = typed }
            XCTAssertEqual(r.homeMeds.map(\.name), [listed], typed)
            // Typed key by key: the fill gives way once the name is the listed drug.
            var k = PatientRecord(); k.ageYears = 50
            change(&k) { $0.homeMeds = [PatientMed(name: listed)] }
            change(&k) { _ = $0.problems.insert("sepsis") }
            for n in 1...typed.count { change(&k) { $0.hx.sepsisAntibiotic = String(typed.prefix(n)) } }
            XCTAssertEqual(k.homeMeds.map(\.name), [listed], typed + " typed key by key")
        }
    }
}
