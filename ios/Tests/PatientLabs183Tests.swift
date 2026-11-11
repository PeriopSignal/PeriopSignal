import XCTest
@testable import PeriopSignal

/// 1.8.3 labs (Ben, Nov 3): lactate in the preoperative labs, type and screen, infectious results and their links to the
/// Infectious history, creatinine to two decimals and INR to one, "Hbg" read as hemoglobin, and the hemoglobin ↔
/// hematocrit estimate.
final class PatientLabs183Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 8))! }

    private func quick(_ s: String, _ tab: QuickAddTab = .preop, record: PatientRecord = PatientRecord()) -> QuickAddReading {
        QuickAdd.read(s, record: record, tab: tab, now: now)
    }
    private func note(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func change(_ f: [PatientNoteFinding], _ id: String) -> PatientNoteChange? { f.first { $0.id == id }?.change }
    private func applied(_ f: [PatientNoteFinding], to base: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = base
        PatientNote.apply(f.map(\.change), to: &r)
        return r
    }
    private func ts(_ f: [PatientNoteFinding]) -> PatientTypeScreen? {
        if case .typeScreen(let t)? = change(f, "typeScreen") { return t }
        return nil
    }

    func testPatternsCompile() {
        for p in LabResults.patterns { XCTAssertNotNil(p.re, p.pattern) }
    }

    // MARK: Lactate

    func testPreopLactate() {
        let t = PatientLabs.test("lactate")
        XCTAssertEqual(t?.label, "Lactate", "a preoperative sample may be venous")
        XCTAssertEqual(t?.unit, IntraopLabs.lactate.unit)
        XCTAssertEqual(t?.range, IntraopLabs.lactate.range)
        XCTAssertEqual(t?.note, IntraopLabs.lactate.note)
        XCTAssertEqual(IntraopLabs.tests(["lactate"]).first?.label, "Lactate, arterial", "the gas keeps its own name")
        XCTAssertEqual(PatientLabs.tests(.main).last?.key, "lactate")
        XCTAssertEqual(PatientLabs.flag("lactate", 2.1, sex: nil), .high)

        for line in ["lactate 1.4", "lac 1.4", "Lactate: 1.4"] {
            let q = quick(line)
            XCTAssertEqual(change(q.findings, "lab:lactate"), .lab("lactate", 1.4), line)
            XCTAssertTrue(applied(q.findings).intraopLabs.isEmpty, line)
        }
        let i = quick("lac 1.4", .intraop)
        let r = applied(i.findings)
        XCTAssertEqual(r.intraopLabs.first?.values["lactate"], 1.4, "the intraoperative bar still fills the blood gas")
        XCTAssertNil(r.labs["lactate"])

        var rec = PatientRecord()
        rec.labs = ["hb": 15, "hct": 45, "lactate": 1.4]
        rec.typeScreen = PatientTypeScreen(type: "A-", screen: .negative)
        rec.infections.results["staph"] = .negative
        XCTAssertEqual(PatientSummary.labsLine(rec)?.text, "Hb 15 · Hct 45 · Lactate 1.4 · T&S A−, screen neg · Staph screen neg",
                       "lactate after the other labs, then T&S, then infectious results")
    }

    // MARK: Type and screen

    func testTypeScreenText() {
        var t = PatientTypeScreen(type: "A-", screen: .negative)
        XCTAssertEqual(t.parts, ["T&S A−, screen neg"])
        t.crossmatched = 2
        XCTAssertEqual(t.parts, ["T&S A−, screen neg", "2 u crossmatched"])
        t.screen = .positive; t.antibody = "anti-K"
        XCTAssertEqual(t.head, "T&S A−, screen pos (anti-K)")
        var r = PatientRecord()
        r.typeScreen = t
        let l = PatientSummary.labsLine(r)
        XCTAssertEqual(l?.text, "T&S A−, screen pos (anti-K) · 2 u crossmatched")
        XCTAssertEqual(l?.marks, ["T&S A−, screen pos (anti-K)"], "a positive screen is marked")
    }

    func testTypeScreenReading() {
        let cases: [(String, PatientTypeScreen)] = [
            ("T&S A-/-", PatientTypeScreen(type: "A-", screen: .negative)),
            ("T&S A neg, screen neg", PatientTypeScreen(type: "A-", screen: .negative)),
            ("type and screen O pos, antibody screen negative", PatientTypeScreen(type: "O+", screen: .negative)),
            ("T&S AB+/+ anti-K", PatientTypeScreen(type: "AB+", screen: .positive, antibody: "anti-K")),
            ("2 units crossmatched", PatientTypeScreen(crossmatched: 2)),
            ("2u xm", PatientTypeScreen(crossmatched: 2)),
            ("T&S B neg, screen pending, 4 units crossmatched", PatientTypeScreen(type: "B-", screen: .pending, crossmatched: 4)),
        ]
        for (line, want) in cases {
            XCTAssertEqual(ts(note(line).findings), want, "note: " + line)
            XCTAssertEqual(ts(quick(line).findings), want, "bar: " + line)
            XCTAssertEqual(applied(quick(line).findings).typeScreen, want, "filed: " + line)
        }
        // Ben's own line: the staph screen and the T&S.
        let ben = quick("Staph negative, T&S A-/-")
        let r = applied(ben.findings)
        XCTAssertEqual(r.typeScreen, PatientTypeScreen(type: "A-", screen: .negative))
        XCTAssertEqual(r.infections.results, ["staph": .negative])
        XCTAssertTrue(r.problems.isEmpty)
        // An MRSA screen beside a T&S is not the antibody screen.
        XCTAssertEqual(ts(note("T&S O pos, MRSA screen negative").findings), PatientTypeScreen(type: "O+"))
        // A bare "screen negative" without a T&S says nothing of blood.
        XCTAssertNil(ts(note("screen negative").findings))
        // Parts typed later add to what is there.
        var base = PatientRecord()
        base.typeScreen = PatientTypeScreen(type: "A-", screen: .negative)
        let more = applied(quick("2u xm").findings, to: base)
        XCTAssertEqual(more.typeScreen, PatientTypeScreen(type: "A-", screen: .negative, crossmatched: 2))
        XCTAssertEqual(PatientNote.status(LabResults.typeScreenFinding(PatientTypeScreen(type: "A-")), in: base), .recorded)
        XCTAssertEqual(PatientNote.status(LabResults.typeScreenFinding(PatientTypeScreen(type: "O+")), in: base), .replaces("T&S A−, screen neg"))
    }

    // MARK: Infectious results

    func testInfectiousReading() {
        let cases: [(String, String, String, LabResult)] = [
            ("staph neg", "staph", "", .negative),
            ("MRSA screen negative", "mrsa", "", .negative),
            ("covid negative", "covid", "", .negative),
            ("C diff pending", "cdiff", "", .pending),
            ("VRE positive", "other", "VRE", .positive),
            ("MRSA nares +", "mrsa", "", .positive),
            ("COVID-19 PCR not detected", "covid", "", .negative),
        ]
        for (line, id, name, v) in cases {
            let fid = "infectious:" + (id == "other" ? "other:" + name.lowercased() : id)
            XCTAssertEqual(change(quick(line).findings, fid), .infectious(id, name, v), "bar: " + line)
            XCTAssertEqual(change(note(line).findings, fid), .infectious(id, name, v), "note: " + line)
        }
        let both = applied(quick("MRSA/VRE neg").findings)
        XCTAssertEqual(both.infections.results["mrsa"], .negative)
        XCTAssertEqual(both.infections.other.map(\.name), ["VRE"])
    }

    /// Negative or pending adds no history problem, by the bar, the note reader or the screen.
    func testNegativeAndPendingAddNoHistory() {
        for line in ["staph neg", "MRSA screen negative", "covid negative", "C diff pending", "VRE pending", "MRSA pending", "COVID test pending"] {
            let q = quick(line)
            XCTAssertFalse(q.findings.contains { $0.id.hasPrefix("problem:") }, line)
            XCTAssertTrue(applied(q.findings).problems.isEmpty, line)
            XCTAssertFalse(note(line).findings.contains { $0.id.hasPrefix("problem:") }, "note: " + line)
        }
        var r = PatientRecord()
        for id in ["staph", "mrsa", "covid", "cdiff"] {
            for v in [LabResult.negative, .pending] { LabResults.set(id, v, in: &r) }
        }
        LabResults.set("other", name: "VRE", .pending, in: &r)
        XCTAssertTrue(r.problems.isEmpty)
        XCTAssertTrue(r.labProblems.isEmpty)
    }

    func testInfectiousText() {
        var r = PatientRecord()
        r.infections = PatientInfections(results: ["staph": .negative, "mrsa": .negative, "covid": .negative, "cdiff": .negative])
        XCTAssertEqual(PatientSummary.labsLine(r)?.text, "Staph screen neg · MRSA neg · COVID neg · C. diff neg")
        XCTAssertFalse(HandoffWriter.shortText(r).contains("Infectious results"), "the short handoff leaves out negatives")
        r.infections.results["cdiff"] = .pending
        LabResults.set("other", name: "VRE", .positive, in: &r)
        XCTAssertTrue(HandoffWriter.text(r).contains("Labs: Staph screen neg · MRSA neg · COVID neg · C. diff pending · VRE pos"), HandoffWriter.text(r))
        XCTAssertTrue(HandoffWriter.shortText(r).contains("Infectious results: C. diff pending · VRE pos"), HandoffWriter.shortText(r))
        XCTAssertTrue(PatientSummary.labsLine(r)?.marks.contains("VRE pos") ?? false)
    }

    // MARK: Links to the Infectious history

    func testPositiveResultsLink() {
        let links: [(String, String, String)] = [("mrsa", "", "mdro"), ("covid", "", "covid-recent"), ("cdiff", "", "c-diff"), ("other", "VRE", "mdro"),
                                                 ("other", "vancomycin-resistant enterococcus", "mdro")]
        for (id, name, problem) in links {
            var r = PatientRecord()
            LabResults.set(id, name: name, .positive, in: &r)
            XCTAssertEqual(r.problems, [problem], id + " " + name)
            XCTAssertEqual(r.labProblems, [problem], id + " " + name)
        }
        for (id, name) in [("staph", ""), ("other", "ESBL"), ("other", "GBS")] {
            var r = PatientRecord()
            LabResults.set(id, name: name, .positive, in: &r)
            XCTAssertTrue(r.problems.isEmpty, id + " " + name + ": no link")
        }
        // Through the readers too.
        XCTAssertTrue(applied(quick("MRSA screen positive").findings).problems.contains("mdro"))
        XCTAssertTrue(applied(quick("staph aureus screen positive").findings).problems.isEmpty, "S. aureus colonization is not an MDRO")
    }

    func testUnlinkOnlyWhatTheLabsAdded() {
        // Added by the result: taken off when it is no longer positive.
        var r = PatientRecord()
        LabResults.set("mrsa", .positive, in: &r)
        LabResults.set("mrsa", .negative, in: &r)
        XCTAssertFalse(r.problems.contains("mdro"))
        XCTAssertTrue(r.labProblems.isEmpty)
        LabResults.set("covid", .positive, in: &r)
        LabResults.set("covid", nil, in: &r)
        XCTAssertFalse(r.problems.contains("covid-recent"), "cleared")

        // Entered by the user first: stays.
        var u = PatientRecord()
        u.problems = ["mdro"]
        LabResults.set("mrsa", .positive, in: &u)
        XCTAssertTrue(u.labProblems.isEmpty, "not the labs' item")
        LabResults.set("mrsa", .negative, in: &u)
        XCTAssertEqual(u.problems, ["mdro"])

        // Two results on one item: it goes only when neither is positive.
        var two = PatientRecord()
        LabResults.set("mrsa", .positive, in: &two)
        LabResults.set("other", name: "VRE", .positive, in: &two)
        LabResults.set("mrsa", .negative, in: &two)
        XCTAssertTrue(two.problems.contains("mdro"), "VRE still positive")
        LabResults.set("other", name: "VRE", .negative, in: &two)
        XCTAssertFalse(two.problems.contains("mdro"))

        // Renaming a positive Other result away from VRE unlinks it.
        var named = PatientRecord()
        LabResults.set("other", name: "VRE", .positive, in: &named)
        LabResults.edit(&named) { $0.other[0].name = "ESBL" }
        XCTAssertFalse(named.problems.contains("mdro"))

        // The user takes the item off and puts it back: it is theirs, and stays.
        var back = PatientRecord()
        LabResults.set("cdiff", .positive, in: &back)
        back.problems.remove("c-diff")
        XCTAssertTrue(back.labProblems.isEmpty)
        back.problems.insert("c-diff")
        LabResults.set("cdiff", .negative, in: &back)
        XCTAssertTrue(back.problems.contains("c-diff"))

        // A history finding from a note makes the item the user's.
        var n = PatientRecord()
        LabResults.set("mrsa", .positive, in: &n)
        PatientNote.apply([.problem("mdro")], to: &n)
        LabResults.set("mrsa", .negative, in: &n)
        XCTAssertTrue(n.problems.contains("mdro"))
    }

    /// "MRSA positive" files the history item as before, and the result too; filing both leaves one item, the user's.
    func testNoteReaderStaysConsistent() {
        let q = quick("MRSA positive")
        XCTAssertTrue(q.findings.contains { $0.id == "problem:mdro" }, "as before 1.8.3")
        XCTAssertEqual(change(q.findings, "infectious:mrsa"), .infectious("mrsa", "", .positive))
        let r = applied(q.findings)
        XCTAssertEqual(r.problems, ["mdro"])
        XCTAssertTrue(r.labProblems.isEmpty, "the note's history finding stands on its own")
        XCTAssertTrue(note("COVID-19 positive").findings.contains { $0.id == "problem:covid-recent" })
        XCTAssertTrue(note("hx MRSA").findings.allSatisfy { !$0.id.hasPrefix("infectious:") }, "a history mention is not a result")
    }

    func testRecordDecodes() throws {
        var r = PatientRecord()
        r.typeScreen = PatientTypeScreen(type: "O-", screen: .positive, antibody: "anti-E", crossmatched: 3)
        LabResults.set("covid", .positive, in: &r)
        LabResults.set("other", name: "VRE", .pending, in: &r)
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"version":1,"labs":{"cr":1}}"#.utf8))
        XCTAssertTrue(old.typeScreen.isEmpty)
        XCTAssertTrue(old.infections.isEmpty)
    }

    // MARK: Creatinine and INR

    func testCreatinineAndINRDecimals() {
        let cr = PatientLabs.test("cr")
        XCTAssertEqual(cr?.format(1), "1.00")
        XCTAssertEqual(cr?.format(1.1), "1.10")
        XCTAssertEqual(cr?.format(1.42), "1.42")
        XCTAssertEqual(cr?.format(1.234), "1.234", "typed precision kept")
        let inr = PatientLabs.test("inr")
        XCTAssertEqual(inr?.format(1), "1.0")
        XCTAssertEqual(inr?.format(1.15), "1.15")
        XCTAssertEqual(PatientLabs.test("k")?.format(4), "4", "other tests unchanged")
        XCTAssertEqual(NumText.padded("1", 2), "1.00")
        XCTAssertEqual(NumText.padded("-1.5", 2), "-1.50")

        var r = PatientRecord()
        r.labs = ["cr": 1, "inr": 1]
        let s = PatientLabs.summary(r)
        XCTAssertEqual(s.fishbone.cr?.text, "1.00")
        XCTAssertEqual(s.fishbone.inr?.text, "1.0")
        XCTAssertEqual(PatientSummary.labsLine(r)?.text, "INR 1.0 · Cr 1.00")
        XCTAssertTrue(HandoffWriter.text(r).contains("Labs: INR 1.0 · Cr 1.00"), HandoffWriter.text(r))
        XCTAssertEqual(QuickAdd.labText("cr", 1, sex: nil), "Cr 1.00")
        XCTAssertEqual(PatientNote.labLabel("cr", 1), "Creatinine 1.00 mg/dL")
    }

    // MARK: Hbg

    func testHbgReadsAsHemoglobin() {
        for line in ["Hb 12.1", "Hgb: 12.1", "Hbg 12.1"] {
            XCTAssertEqual(change(quick(line).findings, "lab:hb"), .lab("hb", 12.1), "bar: " + line)
            XCTAssertEqual(change(note(line).findings, "lab:hb"), .lab("hb", 12.1), "note: " + line)
            XCTAssertEqual(change(quick(line, .intraop).findings, "intraop-lab:hb").map { c -> Double? in
                if case .intraopLabs(let s) = c { return s.values["hb"] }
                return nil
            } ?? nil, 12.1, "intraop bar: " + line)
        }
        XCTAssertTrue(MedAbbreviations.scan("Hbg 12.1").contains { $0.token == "Hbg" }, "a known abbreviation, not an unknown one")
    }

    // MARK: Hb ↔ Hct estimate

    func testHematocritEstimate() {
        var r = PatientRecord()
        r.labs = ["hb": 15]
        let s = PatientLabs.summary(r)
        XCTAssertEqual(s.estimate?.key, "hct")
        XCTAssertEqual(s.estimate?.text, "45")
        XCTAssertEqual(s.estimate?.estimated, true)
        XCTAssertEqual(s.fishbone.estimate?.key, "hct")
        XCTAssertNil(s.fishbone.hct, "the measured cell stays empty")
        XCTAssertEqual(s.items.map(\.key), ["hb"], "not an item")
        XCTAssertEqual(s.line, "Hb 15 · Hct ~45 (est.)")
        XCTAssertTrue(HandoffWriter.text(r).contains("Labs: Hb 15 · Hct ~45 (est.)"))
        XCTAssertNil(r.labs["hct"], "never saved")

        r.labs = ["hct": 30]
        XCTAssertEqual(PatientLabs.summary(r).line, "Hb ~10 (est.) · Hct 30")
        r.labs = ["hct": 31]
        XCTAssertEqual(PatientLabs.estimate(r.labs)?.text, "10.3", "Hb to 0.1")
        r.labs = ["hb": 9.8]
        XCTAssertEqual(PatientLabs.estimate(r.labs)?.text, "29", "Hct to the whole %")

        // Never over a measured value.
        r.labs = ["hb": 15, "hct": 40]
        XCTAssertNil(PatientLabs.summary(r).estimate)
        XCTAssertEqual(PatientLabs.summary(r).line, "Hb 15 · Hct 40")
    }

    func testEstimateNotUsedByRules() {
        // Hct 27 would estimate Hb 9, under the anemia rule's 10; the rule reads only the measured Hb.
        var r = PatientRecord()
        r.ageYears = 60
        r.labs = ["hct": 27]
        XCTAssertEqual(PatientLabs.estimate(r.labs)?.value, 9)
        XCTAssertFalse(PatientRules.prefill("ariscat", r).on.contains("anemia"))
        r.labs = ["hb": 9]
        XCTAssertTrue(PatientRules.prefill("ariscat", r).on.contains("anemia"), "the measured value still counts")
        // An estimate is not flagged or marked.
        r.labs = ["hct": 18]
        XCTAssertEqual(PatientLabs.summary(r).estimate?.flag, .normal)
        XCTAssertFalse(PatientSummary.labsLine(r)?.marks.contains { $0.hasPrefix("Hb") } ?? true)
    }

    // MARK: 1.8.3 review fixes

    /// The antibody screen is the blood bank's only with a T&S, type-and-screen or blood-bank lead, or an ABO/Rh type in
    /// the clause, and never a screen named for something else.
    /// 1.8.3 re-check: a hepatitis serology, a beta blocker ("BB") or "Group B" is not the blood bank's.
    func testHepatitisBetaBlockerAndGroupBAreNotTheBloodBank() {
        for line in ["Hep B neg, Hep C Ab screen negative", "Hepatitis B negative, hepatitis C antibody screen negative",
                     "HepB neg, antibody screen negative", "BB: metoprolol, antibody screen negative", "Group B neg, antibody screen negative"] {
            XCTAssertNil(ts(note(line).findings)?.screen, "note: " + line)
            XCTAssertNil(ts(quick(line).findings)?.screen, "bar: " + line)
        }
        XCTAssertEqual(ts(note("T&S: O neg, antibody screen negative").findings)?.screen, .negative, "a T&S lead still reads it")
        XCTAssertEqual(ts(note("Blood bank: antibody screen negative").findings)?.screen, .negative)
    }

    func testAntibodyScreenOnlyForTheBloodBank() {
        for line in ["HIT antibody screen positive", "HCV Ab screen neg", "HLA antibody screen positive", "antibody screen negative",
                     "T&S A neg, HIT antibody screen positive", "T&S O pos, drug/tox screen positive", "T&S O pos, HCV Ab screen neg",
                     "T&S B+, HLA antibody screen positive", "T&S A neg, urine drug screen positive", "T&S A neg, PF4 antibody screen positive",
                     "T&S O pos, heparin antibody screen positive", "T&S O pos, ANA screen positive", "T&S O pos, PRA screen positive"] {
            XCTAssertNil(ts(note(line).findings)?.screen, "note: " + line)
            XCTAssertNil(ts(quick(line).findings)?.screen, "bar: " + line)
            XCTAssertNil(applied(quick(line).findings).typeScreen.screen, "filed: " + line)
        }
        XCTAssertEqual(ts(note("Blood bank: antibody screen negative").findings)?.screen, .negative, "a blood-bank lead")
        XCTAssertEqual(ts(note("O neg, antibody screen positive, anti-E").findings), PatientTypeScreen(screen: .positive, antibody: "anti-E"),
                       "an ABO/Rh type in the clause")
        XCTAssertEqual(ts(quick("T&S A neg, HIT antibody screen positive").findings), PatientTypeScreen(type: "A-"), "the type is still read")
    }

    /// Only red-cell alloantibody names, and a name never makes the screen positive.
    func testOnlyRedCellAntibodies() {
        for line in ["T&S A neg, on heparin, anti-Xa 0.4", "T&S A neg, anti-PF4 positive", "T&S O pos, anti-coagulated", "T&S O pos, on anticoagulants",
                     "T&S O pos, anti-coagulant held"] {
            let t = ts(note(line).findings)
            XCTAssertEqual(t?.antibody ?? "", "", "note: " + line)
            XCTAssertNil(t?.screen, "note: " + line)
            XCTAssertEqual(applied(quick(line).findings).typeScreen.antibody, "", "bar: " + line)
            XCTAssertNil(applied(quick(line).findings).typeScreen.screen, "bar: " + line)
        }
        XCTAssertEqual(ts(note("T&S O neg, screen pos, anti-K").findings), PatientTypeScreen(type: "O-", screen: .positive, antibody: "anti-K"))
        XCTAssertEqual(ts(quick("T&S A pos, antibody screen positive (anti-Fya and anti-Jkb)").findings)?.antibody, "anti-Fya, anti-Jkb")
        XCTAssertEqual(ts(note("T&S A pos, anti-K").findings), PatientTypeScreen(type: "A+", antibody: "anti-K"), "the screen is not inferred")
    }

    /// One vocabulary for "not positive": what the lab reader reads as negative or pending, the history never files.
    func testNotPositiveWordsAgreeOnBothPaths() {
        let cases: [(line: String, id: String, name: String, problem: String, result: LabResult)] = [
            ("MRSA PCR not detected", "mrsa", "", "mdro", .negative),
            ("MRSA nasal swab PCR not detected", "mrsa", "", "mdro", .negative),
            ("MRSA swab non-detected", "mrsa", "", "mdro", .negative),
            ("MRSA nondetected", "mrsa", "", "mdro", .negative),
            ("MRSA −", "mrsa", "", "mdro", .negative),
            ("MRSA screen -", "mrsa", "", "mdro", .negative),
            ("C diff toxin undetected", "cdiff", "", "c-diff", .negative),
            ("C diff in process", "cdiff", "", "c-diff", .pending),
            ("C diff toxin in progress", "cdiff", "", "c-diff", .pending),
            ("VRE not detected", "other", "VRE", "mdro", .negative),
            ("COVID PCR not detected", "covid", "", "covid-recent", .negative),
            ("COVID rapid antigen in process", "covid", "", "covid-recent", .pending),
        ]
        for x in cases {
            let fid = "infectious:" + (x.id == "other" ? "other:" + x.name.lowercased() : x.id)
            let n = note(x.line).findings
            let q = quick(x.line).findings
            XCTAssertEqual(change(n, fid), .infectious(x.id, x.name, x.result), "note result: " + x.line)
            XCTAssertEqual(change(q, fid), .infectious(x.id, x.name, x.result), "bar result: " + x.line)
            XCTAssertFalse(n.contains { $0.id == "problem:" + x.problem }, "note history: " + x.line)
            XCTAssertFalse(q.contains { $0.id == "problem:" + x.problem }, "bar history: " + x.line)
            XCTAssertTrue(applied(q).problems.isEmpty, "filed: " + x.line)
        }
        // A spaced dash before more words is a separator, not a result: the history item is filed as before.
        let sep = quick("MRSA - on contact precautions")
        XCTAssertTrue(sep.findings.contains { $0.id == "problem:mdro" })
        XCTAssertNil(change(sep.findings, "infectious:mrsa"))
        XCTAssertTrue(note("MRSA positive").findings.contains { $0.id == "problem:mdro" }, "a positive still files it")
    }

    /// A positive COVID-19 is read only where Recent COVID-19 would be filed: not old, not an exposure.
    func testCovidPositiveOnlyWhenRecent() {
        for line in ["COVID+ 2021", "exposure to COVID positive coworker", "COVID positive in 2020", "COVID positive 6 months ago",
                     "2019 COVID positive", "close contact with COVID+ family member"] {
            let n = note(line).findings
            let q = quick(line).findings
            XCTAssertFalse(n.contains { $0.id == "problem:covid-recent" }, "note history: " + line)
            XCTAssertNil(change(n, "infectious:covid"), "note result: " + line)
            XCTAssertNil(change(q, "infectious:covid"), "bar result: " + line)
            let r = applied(q)
            XCTAssertFalse(r.problems.contains("covid-recent"), "filed: " + line)
            XCTAssertFalse(PatientRules.prefill("ariscat", r).on.contains("infection"), "ARISCAT: " + line)
        }
        for line in ["COVID positive", "COVID-19 PCR detected", "COVID+ last week"] {
            let q = quick(line).findings
            XCTAssertEqual(change(q, "infectious:covid"), .infectious("covid", "", .positive), line)
            XCTAssertTrue(q.contains { $0.id == "problem:covid-recent" }, line)
            XCTAssertTrue(PatientRules.prefill("ariscat", applied(q)).on.contains("infection"), line)
        }
    }

    func testEstimateCaption() {
        let c = PatientLabs.estimateCaption
        XCTAssertTrue(c.contains("Hct ÷ Hb = 100 ÷ MCHC"), c)
        XCTAssertTrue(c.contains("pooled malaria cohort (Lee SJ et al., Malar J 2008)"), c)
        XCTAssertTrue(c.hasSuffix("Only measured values are saved."), c)
    }
}
