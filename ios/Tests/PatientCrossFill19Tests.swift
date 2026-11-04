import XCTest
@testable import PeriopSignal

/// 1.9 (Ben's Wanted Changes): fills between pages (PatientCrossFill). Each is made when its source appears, taken back
/// only while it is still the fill's, never touches what the user entered, and comes back only when its source goes and
/// returns.
final class PatientCrossFill19Tests: XCTestCase {

    /// One change as PatientStore.update makes it: the change, then the fills.
    private func change(_ r: inout PatientRecord, _ body: (inout PatientRecord) -> Void) {
        let before = r
        body(&r)
        PatientCrossFill.apply(before: before, after: &r)
    }

    private func adult(_ sex: PatientSex? = .male, age: Double = 50) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = age; r.sex = sex
        r.problems = ["htn"]
        return r
    }

    // MARK: Anemia (WHO 2024)

    func testWHOCutoffs() {
        var m = adult(.male)
        XCTAssertEqual(PatientAnemia.cutoff(m), 13)
        m.labs["hb"] = 12.9; XCTAssertTrue(PatientAnemia.isLow(m))
        m.labs["hb"] = 13; XCTAssertFalse(PatientAnemia.isLow(m), "below the cut-off only")
        var f = adult(.female)
        f.labs["hb"] = 11.9; XCTAssertTrue(PatientAnemia.isLow(f))
        f.labs["hb"] = 12; XCTAssertFalse(PatientAnemia.isLow(f))
        var u = adult(nil)
        XCTAssertEqual(PatientAnemia.cutoff(u), 12, "sex unknown, not pregnant")
        u.labs["hb"] = 12.5; XCTAssertFalse(PatientAnemia.isLow(u))
        // Pregnancy by trimester; no gestation recorded: 11.
        var p = adult(.female); p.problems.insert("pregnant")
        XCTAssertEqual(PatientAnemia.cutoff(p), 11)
        for (weeks, cut) in [(8, 11.0), (13, 11.0), (14, 10.5), (20, 10.5), (27, 10.5), (28, 11.0), (39, 11.0)] {
            p.hx.gestationWeeks = weeks
            XCTAssertEqual(PatientAnemia.cutoff(p), cut, "week \(weeks)")
        }
        p.hx.gestationWeeks = 20
        p.labs["hb"] = 10.4; XCTAssertTrue(PatientAnemia.isLow(p))
        p.labs["hb"] = 10.5; XCTAssertFalse(PatientAnemia.isLow(p), "second trimester: 10.5 is not anemia")
        p.hx.gestationWeeks = 10
        p.labs["hb"] = 10.9; XCTAssertTrue(PatientAnemia.isLow(p), "first trimester: below 11")
        // Under 15 years: never by itself.
        var child = adult(.male, age: 14.9)
        child.labs["hb"] = 8
        XCTAssertNil(PatientAnemia.cutoff(child))
        XCTAssertFalse(PatientAnemia.isLow(child))
        child.ageYears = 15
        XCTAssertTrue(PatientAnemia.isLow(child))
        // An implausible value is a typing error.
        var typo = adult(.male); typo.labs["hb"] = 0.5
        XCTAssertFalse(PatientAnemia.isLow(typo))
    }

    func testLowHbAddsAnemiaAsTheLabs() {
        var r = adult(.female)
        change(&r) { $0.labs["hb"] = 10.9 }
        XCTAssertTrue(r.has("anemia"))
        XCTAssertTrue(r.labProblems.contains("anemia"))
        XCTAssertEqual(PatientAnemia.reason(r), "Hb 10.9 g/dL, below 12 (WHO 2024)")
        change(&r) { $0.labs["hb"] = 10.2 }
        XCTAssertTrue(r.has("anemia"))
        change(&r) { $0.labs["hb"] = 12.6 }
        XCTAssertFalse(r.has("anemia"), "the Hb is normal again: the labs' item goes")
        XCTAssertFalse(r.labProblems.contains("anemia"))
        // Taken off by the user while the Hb stays low: stays off, until the Hb goes normal and low again.
        change(&r) { $0.labs["hb"] = 9 }
        change(&r) { $0.problems.remove("anemia") }
        change(&r) { $0.labs["hb"] = 8.6 }
        XCTAssertFalse(r.has("anemia"))
        change(&r) { $0.labs["hb"] = 13 }
        change(&r) { $0.labs["hb"] = 9 }
        XCTAssertTrue(r.has("anemia"), "a new low Hb adds it again")
        // Cleared Hb: the source goes.
        change(&r) { $0.labs["hb"] = nil }
        XCTAssertFalse(r.has("anemia"))
        // Entered by the user: never taken off.
        var u = adult(.male)
        change(&u) { $0.problems.insert("anemia") }
        change(&u) { $0.labs["hb"] = 9 }
        XCTAssertFalse(u.labProblems.contains("anemia"), "already the user's")
        change(&u) { $0.labs["hb"] = 15 }
        XCTAssertTrue(u.has("anemia"))
    }

    func testSexAndPregnancyChangeTheCutoff() {
        var r = adult(nil)
        change(&r) { $0.labs["hb"] = 12.5 }
        XCTAssertFalse(r.has("anemia"))
        change(&r) { $0.sex = .male }
        XCTAssertTrue(r.has("anemia"), "12.5 is below the men's cut-off")
        change(&r) { $0.sex = .female }
        XCTAssertFalse(r.has("anemia"))
        // A fill on a child is never made.
        var c = adult(.male, age: 8)
        change(&c) { $0.labs["hb"] = 9 }
        XCTAssertFalse(c.has("anemia"))
    }

    func testRecordsSavedBeforeFillNothing() throws {
        let json = #"{"ageYears":70,"sex":"male","problems":["htn","insulin","cirrhosis"],"labs":{"hb":9.1},"hx":{"afType":"permanent"}}"#
        var r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.fills, PatientFills())
        change(&r) { $0.weightKg = 80 }
        XCTAssertFalse(r.has("anemia"), "a low Hb already there when the record opens is not a transition")
        XCTAssertTrue(r.medFlags.isEmpty)
        XCTAssertTrue(r.labSections.isEmpty)
        XCTAssertEqual(r.fills, PatientFills())
    }

    // MARK: Medication flags

    func testHistoryItemsFillTheirFlags() {
        let cases: [(String, (inout PatientRecord) -> Void, (inout PatientRecord) -> Void)] = [
            ("insulin", { $0.problems.formUnion(["dm", "insulin"]) }, { $0.problems.remove("insulin") }),
            ("steroid", { $0.problems.insert("adrenal"); $0.hx.adrenalKinds = ["steroids"] }, { $0.hx.adrenalKinds = ["insufficiency"] }),
            ("anticoagulant", { $0.problems.insert("anticoagulation") }, { $0.problems.remove("anticoagulation") }),
        ]
        for (flag, add, remove) in cases {
            var r = adult()
            change(&r, add)
            XCTAssertTrue(r.medFlags.contains(flag), flag)
            XCTAssertTrue(r.fills.medFlags.contains(flag), flag)
            change(&r, remove)
            XCTAssertFalse(r.medFlags.contains(flag), flag + ": the source goes, the fill goes")
            // The user takes the flag off: it stays off while the source stays.
            change(&r, add)
            change(&r) { $0.medFlags.remove(flag) }
            XCTAssertTrue(r.fills.medFlags.isEmpty, flag)
            change(&r) { $0.weightKg = 70 }
            XCTAssertFalse(r.medFlags.contains(flag), flag + " stays off")
            change(&r, remove)
            change(&r, add)
            XCTAssertTrue(r.medFlags.contains(flag), flag + ": back when the source returns")
            // A flag the user ticked first is never taken off.
            var u = adult()
            change(&u) { $0.medFlags.insert(flag) }
            change(&u, add)
            XCTAssertFalse(u.fills.medFlags.contains(flag), flag)
            change(&u, remove)
            XCTAssertTrue(u.medFlags.contains(flag), flag + ": the user's")
        }
    }

    func testAFlagStaysWhileAnySourceWantsIt() {
        // Two sources of Insulin: diabetes on insulin and gestational diabetes on insulin.
        var r = adult(.female)
        change(&r) { $0.problems.formUnion(["dm", "insulin"]) }
        change(&r) { $0.problems.insert("gdm"); $0.hx.gdmInsulin = true }
        change(&r) { $0.problems.remove("insulin") }
        XCTAssertTrue(r.medFlags.contains("insulin"), "gestational diabetes on insulin still wants it")
        change(&r) { $0.hx.gdmInsulin = false }
        XCTAssertFalse(r.medFlags.contains("insulin"), "no source wants it")
        // The medication list as a source (MedicationCatalog), where the catalog knows warfarin.
        let warfarin = PatientMed(name: "Warfarin", catalogID: "warfarin")
        if MedicationCatalog.flags(for: [warfarin]).contains("anticoagulant") {
            var m = adult()
            change(&m) { $0.homeMeds = [warfarin] }
            XCTAssertTrue(m.medFlags.contains("anticoagulant"))
            change(&m) { $0.problems.insert("anticoagulation") }
            change(&m) { $0.problems.remove("anticoagulation") }
            XCTAssertTrue(m.medFlags.contains("anticoagulant"), "the list still wants it")
            change(&m) { $0.homeMeds = [] }
            XCTAssertFalse(m.medFlags.contains("anticoagulant"))
        }
    }

    // MARK: ECG

    func testPermanentAFFilesAFOnTheECG() {
        var r = adult()
        change(&r) { $0.ecg = [PatientECG.nsr] }
        change(&r) { $0.problems.insert("af"); $0.hx.afType = "permanent" }
        XCTAssertEqual(r.ecg, ["Atrial fibrillation"], "a rhythm replaces the rhythm before it")
        XCTAssertEqual(r.fills.ecg, ["Atrial fibrillation"])
        change(&r) { $0.hx.afType = "paroxysmal" }
        XCTAssertTrue(r.ecg.isEmpty, "no longer permanent: the fill goes")
        // Paroxysmal, persistent and long-standing persistent file nothing.
        for t in ["paroxysmal", "persistent", "longstanding", nil] {
            var p = adult()
            change(&p) { $0.problems.insert("af"); $0.hx.afType = t }
            XCTAssertTrue(p.ecg.isEmpty, t ?? "no type")
            XCTAssertEqual(PatientECGLink.suggestions(p).map(\.from), ["AF/flutter"], "still a one-tap suggestion")
        }
        // Taken off the ECG by the user: stays off.
        var u = adult()
        change(&u) { $0.problems.insert("af"); $0.hx.afType = "permanent" }
        change(&u) { $0.ecg.removeAll() }
        change(&u) { $0.ecgNotes = "rate 80" }
        XCTAssertTrue(u.ecg.isEmpty)
        // Seen on the ECG first: the user's, kept when the type changes.
        var s = adult()
        change(&s) { $0.ecg = ["Atrial fibrillation"] }
        change(&s) { $0.problems.insert("af"); $0.hx.afType = "permanent" }
        XCTAssertTrue(s.fills.ecg.isEmpty)
        change(&s) { $0.hx.afType = nil }
        XCTAssertEqual(s.ecg, ["Atrial fibrillation"])
        // The AF item taken off takes the fill with it.
        var g = adult()
        change(&g) { $0.problems.insert("af"); $0.hx.afType = "permanent" }
        change(&g) { $0.problems.remove("af") }
        XCTAssertTrue(g.ecg.isEmpty)
    }

    func testPacerDependenceFilesVentricularPacing() {
        for device in ["pacemaker", "icd"] {
            var r = adult()
            change(&r) { $0.problems.insert(device); $0.hx.pacerDependent = true }
            XCTAssertEqual(r.ecg, ["Paced rhythm (ventricular)"], device)
            XCTAssertFalse(r.has("pacemaker") && device == "icd", "no second device added")
            change(&r) { $0.hx.pacerDependent = false }
            XCTAssertTrue(r.ecg.isEmpty, device)
        }
        // Dependent with no device recorded: nothing.
        var n = adult()
        change(&n) { $0.hx.pacerDependent = true }
        XCTAssertTrue(n.ecg.isEmpty)
        // Beside permanent AF, both are filed.
        var both = adult()
        change(&both) { $0.problems.formUnion(["af", "pacemaker"]); $0.hx.afType = "permanent"; $0.hx.pacerDependent = true }
        XCTAssertEqual(Set(both.ecg), ["Atrial fibrillation", "Paced rhythm (ventricular)"])
        // Only these two history answers file anything: the rest stays a suggestion.
        var rest = adult()
        change(&rest) { $0.problems.formUnion(["pacemaker", "arrhythmia"]); $0.hx.arrhythmiaType = "SVT" }
        XCTAssertTrue(rest.ecg.isEmpty)
        XCTAssertEqual(Set(PatientECGLink.suggestions(rest).map(\.from)), ["pacemaker", "SVT"])
    }

    func testANoteLineWithSourceAndTargetTogetherIsTheUsers() {
        var r = adult()
        change(&r) { $0.problems.formUnion(["af", "insulin", "dm"]); $0.hx.afType = "permanent"; $0.ecg = ["Atrial fibrillation"]; $0.medFlags = ["insulin"] }
        XCTAssertEqual(r.fills, PatientFills())
        change(&r) { $0.hx.afType = nil; $0.problems.remove("insulin") }
        XCTAssertEqual(r.ecg, ["Atrial fibrillation"])
        XCTAssertEqual(r.medFlags, ["insulin"])
    }

    // MARK: Lab groups, dialysis

    func testCirrhosisAndThyroidOpenTheirLabGroups() {
        for (problem, group) in [("cirrhosis", "liver"), ("thyroid", "thyroid")] {
            var r = adult()
            change(&r) { $0.problems.insert(problem) }
            XCTAssertTrue(r.labSections.contains(group), group)
            change(&r) { $0.problems.remove(problem) }
            XCTAssertFalse(r.labSections.contains(group), group + ": closed again, as it was the fill's")
            // Opened by the user first: never closed.
            var u = adult()
            change(&u) { $0.labSections.insert(group) }
            change(&u) { $0.problems.insert(problem) }
            change(&u) { $0.problems.remove(problem) }
            XCTAssertTrue(u.labSections.contains(group), group)
            // Closed by the user while the source stays, then reopened by the user: theirs.
            var c = adult()
            change(&c) { $0.problems.insert(problem) }
            change(&c) { $0.labSections.remove(group) }
            change(&c) { $0.labSections.insert(group) }
            change(&c) { $0.problems.remove(problem) }
            XCTAssertTrue(c.labSections.contains(group), group)
        }
    }

    func testHemodialysisScheduleFillsMELDDialysis() {
        var r = adult()
        change(&r) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisSchedule = "mwf" }
        XCTAssertTrue(r.dialysis)
        change(&r) { $0.hx.dialysisSchedule = "tts" }
        XCTAssertTrue(r.dialysis)
        change(&r) { $0.hx.dialysisSchedule = nil; $0.hx.dialysisScheduleOther = "Twice weekly" }
        XCTAssertFalse(r.dialysis, "a typed schedule is not read")
        // Ticked by the user: kept.
        var u = adult()
        change(&u) { $0.dialysis = true }
        change(&u) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisSchedule = "mwf" }
        change(&u) { $0.problems.remove("esrd-dialysis") }
        XCTAssertTrue(u.dialysis)
        // Unticked by the user: stays unticked.
        var o = adult()
        change(&o) { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisSchedule = "mwf" }
        change(&o) { $0.dialysis = false }
        XCTAssertFalse(o.fills.dialysis)
        change(&o) { $0.hx.dialysisSchedule = "tts" }
        XCTAssertFalse(o.dialysis)
    }

    // MARK: The sepsis antibiotic

    func testSepsisAntibioticFollowsTheTyping() {
        var r = adult()
        change(&r) { $0.problems.insert("sepsis") }
        for t in ["c", "ce", "cefepime"] { change(&r) { $0.hx.sepsisAntibiotic = t } }
        XCTAssertEqual(r.homeMeds.map(\.name), ["cefepime"], "one medication, renamed as typed")
        XCTAssertNotNil(r.fills.meds[PatientCrossFill.sepsisAntibioticKey])
        change(&r) { $0.hx.sepsisAntibiotic = "" }
        XCTAssertTrue(r.homeMeds.isEmpty, "cleared: taken off")
        // Renamed by the user on the list: theirs.
        change(&r) { $0.hx.sepsisAntibiotic = "vanc" }
        change(&r) { $0.homeMeds[0].name = "Vancomycin 1 g q12h" }
        change(&r) { $0.hx.sepsisAntibiotic = "" }
        XCTAssertEqual(r.homeMeds.map(\.name), ["Vancomycin 1 g q12h"])
        // Deleted by the user: not back while the antibiotic stays typed.
        var d = adult()
        change(&d) { $0.problems.insert("sepsis"); $0.hx.sepsisAntibiotic = "Pip-tazo" }
        change(&d) { $0.homeMeds = [] }
        change(&d) { $0.hx.sepsisAntibiotic = "Piperacillin-tazobactam" }
        XCTAssertTrue(d.homeMeds.isEmpty)
        // Already on the list by that name: nothing added; typed to a name already listed: the fill gives way.
        var l = adult()
        change(&l) { $0.homeMeds = [PatientMed(name: "Meropenem")] }
        change(&l) { $0.problems.insert("sepsis"); $0.hx.sepsisAntibiotic = "meropenem" }
        XCTAssertEqual(l.homeMeds.count, 1)
        var t = adult()
        change(&t) { $0.homeMeds = [PatientMed(name: "Cefazolin")] }
        change(&t) { $0.problems.insert("sepsis") }
        for s in ["c", "cef", "cefazolin"] { change(&t) { $0.hx.sepsisAntibiotic = s } }
        XCTAssertEqual(t.homeMeds.map(\.name), ["Cefazolin"])
        // Sepsis taken off: the antibiotic is no longer a source.
        var g = adult()
        change(&g) { $0.problems.insert("sepsis"); $0.hx.sepsisAntibiotic = "Cefepime" }
        change(&g) { $0.problems.remove("sepsis") }
        XCTAssertTrue(g.homeMeds.isEmpty)
    }

    // MARK: The store: one Undo step

    @MainActor func testAFillIsPartOfItsSourcesUndoStep() {
        let store = PatientStore(url: nil)
        store.update(discrete: true) { $0.ageYears = 60; $0.problems = ["dm"] }
        store.update(discrete: true) { $0.problems.insert("insulin") }
        XCTAssertTrue(store.record.medFlags.contains("insulin"))
        store.undo()
        XCTAssertFalse(store.record.has("insulin"))
        XCTAssertFalse(store.record.medFlags.contains("insulin"), "undone together")
        XCTAssertTrue(store.record.fills.medFlags.isEmpty)
    }

    // MARK: Scores are not changed by any fill

    func testNoFillChangesASAOrScores() {
        var base = adult(.male, age: 67)
        base.heightCm = 175; base.weightKg = 95
        base.problems = ["htn", "osa", "dm"]
        base.labs = ["cr": 1.4]
        base.vitals["spo2"] = 94
        let sources: [(String, (inout PatientRecord) -> Void)] = [
            ("anemia", { $0.labs["hb"] = 9.5 }),
            ("insulin", { $0.problems.insert("insulin") }),
            ("steroid", { $0.problems.insert("adrenal"); $0.hx.adrenalKinds = ["steroids"] }),
            ("anticoagulant", { $0.problems.insert("anticoagulation") }),
            ("af", { $0.problems.insert("af"); $0.hx.afType = "permanent" }),
            ("paced", { $0.problems.insert("pacemaker"); $0.hx.pacerDependent = true }),
            ("cirrhosis", { $0.problems.insert("cirrhosis") }),
            ("thyroid", { $0.problems.insert("thyroid") }),
            ("dialysis", { $0.problems.insert("esrd-dialysis"); $0.hx.dialysisSchedule = "mwf" }),
            ("sepsis", { $0.problems.insert("sepsis"); $0.hx.sepsisAntibiotic = "Cefepime" }),
        ]
        for (name, source) in sources {
            var plain = base
            source(&plain)
            var filled = base
            change(&filled, source)
            XCTAssertNotEqual(plain, filled, name + " fills something")
            XCTAssertEqual(PatientRules.asaSuggestion(filled)?.level, PatientRules.asaSuggestion(plain)?.level, name + ": ASA")
            for score in ["rcri", "ariscat", "stopbang"] {
                XCTAssertEqual(PatientRules.prefill(score, filled), PatientRules.prefill(score, plain), name + ": " + score)
            }
            XCTAssertEqual(PatientFunctional.rcri(filled), PatientFunctional.rcri(plain), name)
        }
    }
}
