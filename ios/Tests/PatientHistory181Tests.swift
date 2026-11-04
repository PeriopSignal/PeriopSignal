import XCTest
import UIKit
@testable import PeriopSignal

/// History, problems by system (1.8.1): diabetes as one item, Stroke, unspecified, and the Infectious system; their
/// ASA and RCRI results, the saved-case migration, and what the note and quick-add readers file.
final class PatientHistory181Tests: XCTestCase {
    /// 30 October 2026, 08:00 on the device's clock.
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))! }

    private func ids(_ text: String) -> Set<String> {
        Set(PatientNote.read(text, now: now).findings.map(\.id).filter { $0.hasPrefix("problem:") })
    }
    private func quick(_ line: String) -> QuickAddReading { QuickAdd.read(line, record: PatientRecord(), tab: .preop, now: now) }
    private func adult(_ problems: Set<String>) -> PatientRecord {
        var r = PatientRecord(); r.ageYears = 60; r.problems = problems
        return r
    }

    // MARK: Catalog

    func testDiabetesIsOneItem() throws {
        let endo = try XCTUnwrap(PatientCatalog.systems.first { $0.id == "endo" })
        XCTAssertEqual(endo.problems.map(\.label), ["Diabetes", "Diabetes treated with insulin", "Thyroid disease", "Adrenal insufficiency or chronic steroids"])
        let dm = try XCTUnwrap(PatientCatalog.problem("dm"))
        XCTAssertEqual(dm.asa, 2)
        XCTAssertEqual(dm.asaExample, "well-controlled DM/HTN")
        XCTAssertEqual(dm.peds, 2)
        XCTAssertEqual(dm.note, "ASA III if poorly controlled; change the class by hand.")
        XCTAssertNil(PatientCatalog.problem("dm-poor"), "no longer offered")
        let insulin = try XCTUnwrap(PatientCatalog.problem("insulin"))
        XCTAssertEqual(insulin.label, "Diabetes treated with insulin")
        XCTAssertEqual(insulin.peds, 3)
        XCTAssertEqual(insulin.rcri, "insulin")
        let cv = try XCTUnwrap(PatientCatalog.systems.first { $0.id == "cv" })
        XCTAssertEqual(cv.problems.first { $0.id == "htn" }?.label, "Hypertension", "hypertension has no control qualifier since the cardiovascular redesign")
        XCTAssertNil(PatientCatalog.problem("htn-poor"))
        XCTAssertEqual(PatientCatalog.problem("gdm-diet")?.label, "Gestational diabetes, diet-controlled", "gestational diabetes is untouched")
    }

    func testStrokeUnspecified() throws {
        let neuro = try XCTUnwrap(PatientCatalog.systems.first { $0.id == "neuro" })
        XCTAssertEqual(Array(neuro.problems.prefix(3).map(\.label)), ["Stroke or TIA, over 3 months", "Stroke or TIA within 3 months", "Stroke or TIA, unspecified"])
        let s = try XCTUnwrap(PatientCatalog.problem("cva-unspec"))
        XCTAssertEqual(s.asa, 3)
        XCTAssertEqual(s.asaExample, "history (>3 months) of MI, CVA, TIA, or CAD/stents")
        XCTAssertEqual(s.rcri, "cva")
        XCTAssertEqual(s.note, "ASA IV if within 3 months.")
    }

    func testInfectiousSystem() throws {
        let names = PatientCatalog.systems.map(\.name)
        let heme = try XCTUnwrap(names.firstIndex(of: "Hematologic"))
        XCTAssertEqual(names[heme + 1], "Infectious", "after Hematologic")
        let inf = try XCTUnwrap(PatientCatalog.systems.first { $0.id == "infectious" })
        // 1.9 (Ben's Wanted Changes): Infective endocarditis, Viral hepatitis (A, B or C) and COVID-19 (active or recent,
        // one id) take Ben's labels; the ids are unchanged.
        XCTAssertEqual(inf.problems.map(\.label), ["Active infection", "Infective endocarditis", "HIV", "Viral hepatitis", "MRSA or VRE", "C. difficile",
                                                   "Tuberculosis", "COVID-19", "Isolation precautions"])
        for p in inf.problems {
            XCTAssertNil(p.asa, p.label + ": no ASA example")
            XCTAssertNil(p.peds, p.label)
            XCTAssertNil(p.rcri, p.label)
            XCTAssertNil(p.note, p.label)
        }
        XCTAssertEqual(PatientCatalog.system(of: "sepsis")?.id, "acute", "sepsis stays under Acute illness")
        XCTAssertEqual(PatientCatalog.system(of: "shock")?.id, "acute")
        XCTAssertEqual(PatientCatalog.system(of: "hepatitis-active")?.id, "gi")
        XCTAssertEqual(Set(PatientCatalog.allProblems.map(\.id)).count, PatientCatalog.allProblems.count, "ids are unique")
    }

    /// Every system's icon is an SF Symbol on this SDK.
    func testSystemIconsExist() {
        for s in PatientCatalog.allSystems { XCTAssertNotNil(UIImage(systemName: s.icon), s.name + ": " + s.icon) }
    }

    func testSystemNotes() throws {
        let endo = try XCTUnwrap(PatientCatalog.systems.first { $0.id == "endo" })
        XCTAssertTrue(PatientCatalog.systemNote(endo).hasPrefix("Diabetes: ASA III if poorly controlled; change the class by hand.\n\n"))
        let neuro = try XCTUnwrap(PatientCatalog.systems.first { $0.id == "neuro" })
        XCTAssertTrue(PatientCatalog.systemNote(neuro).hasPrefix("Stroke or TIA, unspecified: ASA IV if within 3 months.\n\n"))
        let resp = try XCTUnwrap(PatientCatalog.systems.first { $0.id == "resp" })
        XCTAssertTrue(PatientCatalog.systemNote(resp).hasPrefix("Problems the ASA's own examples"), "no item lines: only the usual note")
    }

    // MARK: ASA and RCRI

    func testAsaAndRcri() {
        XCTAssertEqual(PatientRules.asaSuggestion(adult(["dm"]))?.level, 2)
        XCTAssertEqual(PatientRules.asaSuggestion(adult(["dm"]))?.reasons.first?.example, "well-controlled DM/HTN")
        var kid = PatientRecord(); kid.ageYears = 8; kid.problems = ["dm"]
        XCTAssertEqual(PatientRules.asaSuggestion(kid)?.level, 2, "pediatric: non-insulin-dependent diabetes")
        XCTAssertEqual(PatientRules.asaSuggestion(adult(["cva-unspec"]))?.level, 3)
        XCTAssertEqual(PatientRules.asaSuggestion(adult(["cva-unspec"]))?.reasons.first?.example, "history (>3 months) of MI, CVA, TIA, or CAD/stents")
        XCTAssertEqual(PatientRules.asaSuggestion(adult(["cva-recent"]))?.level, 4)
        let infectious = Set(PatientCatalog.systems.first { $0.id == "infectious" }!.problems.map(\.id))
        XCTAssertNil(PatientRules.asaSuggestion(adult(infectious)), "no infectious item is an ASA example")
        XCTAssertEqual(PatientRules.asaSuggestion(adult(infectious.union(["sepsis"])))?.level, 4, "sepsis still is")

        XCTAssertTrue(PatientRules.prefill("rcri", adult(["cva-unspec"])).on.contains("cva"))
        XCTAssertFalse(PatientRules.prefill("rcri", adult(["dm"])).on.contains("insulin"))
        var onInsulin = adult(["dm"]); onInsulin.medFlags = ["insulin"]
        XCTAssertTrue(PatientRules.prefill("rcri", onInsulin).on.contains("insulin"))
        XCTAssertTrue(PatientRules.prefill("rcri", adult(["insulin"])).on.contains("insulin"))
        XCTAssertTrue(PatientRules.prefill("rcri", adult(infectious)).on.isEmpty)
        XCTAssertEqual(PatientFunctional.riskFactors(adult(["dm"])), ["diabetes", "over 55"])
        XCTAssertTrue(PatientFunctional.knownCVD(adult(["cva-unspec"])))
        XCTAssertTrue(PatientFunctional.ascvdProblems.contains("cva-unspec"))
    }

    // MARK: Migration

    func testSavedPoorlyControlledDiabetesLoadsAsDiabetes() throws {
        let old = try XCTUnwrap(try? JSONDecoder().decode(PatientRecord.self, from: Data(#"{"problems": ["dm-poor", "htn-poor"]}"#.utf8)))
        XCTAssertEqual(old.problems, ["dm", "htn"])
        let both = try XCTUnwrap(try? JSONDecoder().decode(PatientRecord.self, from: Data(#"{"problems": ["dm", "dm-poor", "insulin"]}"#.utf8)))
        XCTAssertEqual(both.problems, ["dm", "insulin"])
        XCTAssertEqual(PatientCatalog.migratedProblems(["dm-poor"]), ["dm"])
        // 1.9: Endocrine is an expanding page whose summary words are lowercase, as the other pages' are.
        XCTAssertEqual(PatientSummary.historyLines(old).first { $0.label == "Endocrine" }?.text, "diabetes")
        let book = try XCTUnwrap(PatientCaseBook.decode(Data(#"{"problems": ["dm-poor"]}"#.utf8)), "a 1.6 record")
        XCTAssertEqual(book.cases.first?.record.problems, ["dm"])
    }

    // MARK: Note reader: diabetes

    func testDiabetesMentions() {
        for t in ["DM", "DM2", "T2DM", "NIDDM", "type 2 diabetes", "diabetic", "poorly controlled diabetes", "uncontrolled diabetes",
                  "poorly controlled DM", "DM, poorly controlled", "uncontrolled T2DM", "poorly controlled sugars"] {
            XCTAssertEqual(ids(t), ["problem:dm"], t)
        }
        XCTAssertEqual(ids("T2DM on insulin"), ["problem:dm", "problem:insulin"])
        XCTAssertEqual(ids("IDDM"), ["problem:dm", "problem:insulin"])
        XCTAssertEqual(ids("poorly controlled insulin-dependent diabetes"), ["problem:dm", "problem:insulin"])
        // 1.9 (spec): gestational diabetes alone is "gdm"; "gdm-diet" is the ASA's diet-controlled example only.
        XCTAssertEqual(ids("gestational diabetes"), ["problem:gdm"], "its own item")
        XCTAssertEqual(ids("diabetes insipidus"), [])
        XCTAssertEqual(ids("pre-diabetes"), [])
        XCTAssertNil(PatientNote.read("DM2", now: now).findings.first { $0.id == "problem:dm" }?.note, "no well-controlled caution any more")
    }

    // MARK: Note reader: stroke

    func testStrokeTiming() {
        for t in ["h/o stroke", "CVA", "prior stroke", "history of stroke", "stroke 3 months ago"] {
            XCTAssertEqual(ids(t), ["problem:cva-unspec"], t)
        }
        for t in ["CVA 2019", "stroke 5 years ago", "stroke in 2015", "CVA (2019)", "2019 stroke", "stroke 6 months ago"] {
            XCTAssertEqual(ids(t), ["problem:cva"], t)
        }
        for t in ["recent stroke", "CVA 2 weeks ago", "stroke last month", "new CVA"] {
            XCTAssertEqual(ids(t), ["problem:cva-recent"], t)
        }
        let thisYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        XCTAssertEqual(ids("stroke " + String(thisYear)), ["problem:cva-unspec"], "this year may be within 3 months")
        // 1.8.2: a TIA with no time is "Stroke or TIA, unspecified", as a stroke is, not over 3 months with a caution.
        XCTAssertEqual(ids("TIA"), ["problem:cva-unspec"], "TIA reads like a stroke (1.8.2)")
        XCTAssertNil(PatientNote.read("TIA", now: now).findings.first { $0.id == "problem:cva" })
        XCTAssertNil(PatientNote.read("stroke 5 years ago", now: now).findings.first { $0.id == "problem:cva" }?.note, "the time is given")
        for t in ["heat stroke", "stroke volume 60 mL", "on apixaban for stroke prevention", "No history of stroke"] {
            // 1.9 (spec): a named anticoagulant files On anticoagulation (Hematologic); no stroke either way.
            XCTAssertEqual(ids(t).subtracting(["problem:anticoagulation"]), [], t)
        }
    }

    func testStrokeRecordStatus() {
        var r = PatientRecord(); r.problems = ["cva"]
        let f = PatientNoteFinding(id: "problem:cva-unspec", section: PatientNote.Part.history, label: "Stroke, unspecified", change: .problem("cva-unspec"))
        XCTAssertEqual(PatientNote.status(f, in: r), .recorded, "a timed stroke already says more")
        var u = PatientRecord(); u.problems = ["cva-unspec"]
        PatientNote.apply([.problem("cva-recent")], to: &u)
        XCTAssertEqual(u.problems, ["cva-recent"], "the timed item replaces the unspecified one")
    }

    // MARK: Note reader: infectious

    func testInfectiousPositives() {
        let cases: [(String, String)] = [
            ("active infection", "infection-active"), ("bacteremia", "infection-active"),
            ("endocarditis", "endocarditis"), ("s/p MVR for endocarditis", "endocarditis"),
            ("HIV", "hiv"), ("HIV on ART, viral load undetectable", "hiv"),
            ("hep B", "hepatitis-viral"), ("HBV", "hepatitis-viral"), ("hep C", "hepatitis-viral"), ("HCV", "hepatitis-viral"),
            ("hepatitis C", "hepatitis-viral"),
            ("MRSA", "mdro"), ("VRE", "mdro"),
            ("C diff", "c-diff"), ("C. difficile", "c-diff"), ("CDI", "c-diff"),
            ("tuberculosis", "tb"), ("latent TB", "tb"), ("positive PPD", "tb"),
            ("recent COVID", "covid-recent"), ("COVID-19 positive", "covid-recent"), ("SARS-CoV-2 positive", "covid-recent"),
            ("COVID 2 weeks ago", "covid-recent"),
            ("contact precautions", "isolation"), ("droplet precautions", "isolation"), ("airborne precautions", "isolation"),
            ("isolation", "isolation"), ("on contact and droplet precautions", "isolation"),
        ]
        for (t, id) in cases { XCTAssertTrue(ids(t).contains("problem:" + id), t + " → " + id + " (got " + ids(t).sorted().joined(separator: ", ") + ")") }
    }

    func testInfectiousNegatives() {
        for t in ["HIV negative", "HIV-", "HIV-1/2 Ab negative", "MRSA screen negative", "MRSA nares neg", "HCV Ab neg", "HBsAg negative",
                  "no TB", "PPD negative", "TB test negative", "C diff toxin negative", "COVID negative", "COVID test negative",
                  "no recent COVID", "recent COVID-19 vaccine", "COVID 2021", "COVID", "hepatitis B vaccinated", "on PrEP for HIV prevention",
                  "endocarditis prophylaxis", "SBE prophylaxis", "Isolation: none", "lung isolation with a DLT", "s/p pulmonary vein isolation",
                  "no active infection", "TBI", "i.e. stable", "IE", "Hx of IE", "fall precautions", "standard precautions"] {
            XCTAssertEqual(ids(t), [], t)
        }
    }

    /// Active hepatitis stays one item; the virus is the other, and only both words file both.
    func testNoDoubleFiling() {
        XCTAssertEqual(ids("active hepatitis"), ["problem:hepatitis-active"])
        XCTAssertEqual(ids("hep C"), ["problem:hepatitis-viral"])
        XCTAssertEqual(ids("active hepatitis C"), ["problem:hepatitis-active", "problem:hepatitis-viral"])
        XCTAssertEqual(ids("recent COVID"), ["problem:covid-recent"], "not a respiratory infection as well")
        XCTAssertEqual(ids("recent cold"), ["problem:uri"])
        XCTAssertEqual(ids("septic shock"), ["problem:sepsis", "problem:shock"], "sepsis files under Acute illness")
    }

    /// A recent COVID-19 still ticks ARISCAT's respiratory infection, with one chip (Recent COVID-19) in History.
    func testRecentCovidCountsForAriscat() {
        for t in ["COVID last week", "recent COVID"] {
            let found = PatientNote.read(t, now: now).findings
            XCTAssertEqual(Set(found.map(\.id).filter { $0.hasPrefix("problem:") }), ["problem:covid-recent"], t)
            var r = adult([])
            PatientNote.apply(found.map(\.change), to: &r)
            XCTAssertTrue(PatientRules.prefill("ariscat", r).on.contains("infection"), t)
        }
        XCTAssertTrue(PatientRules.prefill("ariscat", adult(["uri"])).on.contains("infection"), "as before")
        XCTAssertFalse(PatientRules.prefill("ariscat", adult(["hiv", "mdro"])).on.contains("infection"))
        XCTAssertFalse(PatientRules.prefill("ariscat", adult([])).on.contains("infection"))
    }

    // MARK: Quick add

    func testQuickAddLine() {
        let q = quick("68M, DM2, h/o stroke, HCV, MRSA, contact precautions")
        let found = Set(q.findings.map(\.id))
        for id in ["age", "sex", "problem:dm", "problem:cva-unspec", "problem:hepatitis-viral", "problem:mdro", "problem:isolation"] {
            XCTAssertTrue(found.contains(id), id)
        }
        XCTAssertFalse(found.contains("problem:cva"))
        var r = PatientRecord()
        PatientNote.apply(q.findings.map(\.change), to: &r)
        XCTAssertEqual(PatientRules.asaSuggestion(r)?.level, 3, "the stroke is the highest example")
        XCTAssertTrue(PatientRules.prefill("rcri", r).on.contains("cva"))
    }
}
