import XCTest
@testable import PeriopSignal

/// 1.11 helper D (P1-12): the quick-add rules for what still forced a page. ECG findings behind an ECG cue; the airway at
/// handoff and the disposition on the Intraoperative tab and Summary & Handoff; the two cardiac No answers; the stress
/// test; intraoperative events; the Intraoperative example rotating with the case. Each rule has what it reads and what
/// it must not.
final class D111Tests: XCTestCase {
    /// 9 November 2026, 08:00 on the device's clock.
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8))! }

    private func read(_ s: String, _ tab: QuickAddTab = .preop, record: PatientRecord = PatientRecord(), handoff: Bool = false,
                      choices: [String: String] = [:]) -> QuickAddReading {
        QuickAdd.read(s, record: record, tab: tab, now: now, choices: choices, handoff: handoff)
    }
    /// The Summary & Handoff tab: read as the Preoperative tab is, with the end of the case.
    private func summary(_ s: String, record: PatientRecord = PatientRecord()) -> QuickAddReading { read(s, .preop, record: record, handoff: true) }
    private func ids(_ q: QuickAddReading) -> [String] { q.findings.map(\.id) }
    private func change(_ q: QuickAddReading, _ id: String) -> PatientNoteChange? { q.findings.first { $0.id == id }?.change }
    private func finding(_ q: QuickAddReading, _ id: String) -> PatientNoteFinding? { q.findings.first { $0.id == id } }
    private func applied(_ q: QuickAddReading, to base: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = base
        PatientNote.apply(q.findings.map(\.change), to: &r)
        return r
    }
    private func chipTexts(_ q: QuickAddReading, record: PatientRecord = PatientRecord()) -> [String] {
        QuickAdd.chips(q, record: record).map(\.text)
    }
    private func status(_ q: QuickAddReading, _ id: String, in r: PatientRecord) -> PatientNoteStatus? {
        finding(q, id).map { PatientNote.status($0, in: r) }
    }
    private var intubated: PatientRecord {
        var r = PatientRecord()
        r.intubation = "easy"
        r.tube = "7.5 ETT"
        return r
    }

    func testPatternsCompile() {
        for p in QuickAdd.patterns111 { XCTAssertNotNil(p.re, p.pattern) }
        for p in QuickAdd.allPatterns { XCTAssertNotNil(p.re, p.pattern) }
    }

    // MARK: Places

    func testHandoffPlaces() {
        XCTAssertTrue(QuickAddPlace.intraopTab.handoff)
        XCTAssertTrue(QuickAddPlace.summaryTab.handoff)
        XCTAssertTrue(QuickAddPlace.editor(intraop: true).handoff)
        XCTAssertFalse(QuickAddPlace.preopTab.handoff)
        XCTAssertFalse(QuickAddPlace.editor(intraop: false).handoff)
        XCTAssertFalse(QuickAddPlace.pastSurgery.handoff)
    }

    // MARK: ECG findings

    func testECGFindingsBehindACue() {
        let q = read("ECG NSR LBBB")
        XCTAssertEqual(change(q, "ecg:Normal sinus rhythm"), .ecg("Normal sinus rhythm"))
        XCTAssertEqual(change(q, "ecg:Left bundle branch block"), .ecg("Left bundle branch block"))
        XCTAssertEqual(applied(q).ecg, ["Normal sinus rhythm", "Left bundle branch block"])
        XCTAssertEqual(q.unread, "", "the cue and the findings are all read")
        XCTAssertEqual(chipTexts(q), ["ECG · Normal sinus rhythm", "ECG · Left bundle branch block"])

        let e = read("EKG: sinus, Q waves")
        XCTAssertEqual(change(e, "ecg:Normal sinus rhythm"), .ecg("Normal sinus rhythm"), "a bare sinus behind the cue")
        XCTAssertEqual(change(e, "ecg:Q waves (old infarct)"), .ecg("Q waves (old infarct)"))
        XCTAssertEqual(e.unread, "")

        XCTAssertEqual(change(read("paced"), "ecg:Paced rhythm (ventricular)"), .ecg("Paced rhythm (ventricular)"), "paced is its own cue")
        XCTAssertEqual(change(read("ECG A-paced"), "ecg:Paced rhythm (atrial)"), .ecg("Paced rhythm (atrial)"))
        XCTAssertNil(change(read("ECG A-paced"), "ecg:Paced rhythm (ventricular)"), "A-paced is not also ventricular pacing")
        XCTAssertEqual(change(read("ECG AV paced"), "ecg:Paced rhythm (AV)"), .ecg("Paced rhythm (AV)"))
        XCTAssertEqual(change(read("ECG: sinus tach, RBBB"), "ecg:Sinus tachycardia"), .ecg("Sinus tachycardia"))
        XCTAssertFalse(ids(read("ECG: sinus tach, RBBB")).contains("symptom:tachycardia"), "sinus tachycardia on the ECG is not the cardiac symptom")
        XCTAssertEqual(change(read("12-lead: 1st degree AV block, LAFB"), "ecg:First-degree AV block"), .ecg("First-degree AV block"))
        XCTAssertEqual(change(read("12-lead: 1st degree AV block, LAFB"), "ecg:Left anterior fascicular block"), .ecg("Left anterior fascicular block"))
        XCTAssertEqual(change(read("ECG CHB"), "ecg:Complete heart block"), .ecg("Complete heart block"))
        XCTAssertEqual(change(read("ECG: LVH, ST depression, TWI"), "ecg:Left ventricular hypertrophy"), .ecg("Left ventricular hypertrophy"))
        XCTAssertEqual(change(read("ECG: LVH, ST depression, TWI"), "ecg:ST depression"), .ecg("ST depression"))
        XCTAssertEqual(change(read("ECG: LVH, ST depression, TWI"), "ecg:T-wave inversion"), .ecg("T-wave inversion"))
    }

    func testECGNeedsItsCue() {
        let af = read("AF on apixaban")
        XCTAssertFalse(ids(af).contains { $0.hasPrefix("ecg:") }, "AF alone stays history")
        XCTAssertTrue(ids(af).contains("problem:af"))
        XCTAssertFalse(ids(read("68M for sinus surgery")).contains { $0.hasPrefix("ecg:") }, "sinus surgery files nothing")
        XCTAssertFalse(ids(read("sinus surgery, HTN")).contains { $0.hasPrefix("ecg:") })
        XCTAssertFalse(ids(read("LVH on echo")).contains { $0.hasPrefix("ecg:") }, "no ECG cue")
        XCTAssertFalse(ids(read("ECG LBBB", .intraop)).contains { $0.hasPrefix("ecg:") }, "the preoperative ECG is not read on the Intraoperative tab")
    }

    func testECGNegationAndQualifiers() {
        let q = read("ECG: NSR, no Q waves")
        XCTAssertEqual(change(q, "ecg:Normal sinus rhythm"), .ecg("Normal sinus rhythm"))
        XCTAssertNil(change(q, "ecg:Q waves (old infarct)"), "negated")
        XCTAssertEqual(q.unread, "", "the negated words are not history either")
        XCTAssertNil(change(read("ECG: incomplete RBBB"), "ecg:Right bundle branch block"), "incomplete RBBB is not the block")
        XCTAssertNil(change(read("ECG without LBBB"), "ecg:Left bundle branch block"))
    }

    func testNormalECGIsSinusRhythm() {
        let q = read("normal ECG")
        let f = finding(q, "ecg:Normal sinus rhythm")
        XCTAssertEqual(f?.change, .ecg("Normal sinus rhythm"))
        XCTAssertEqual(f?.note, "From a normal ECG.")
        XCTAssertEqual(change(read("ECG unremarkable"), "ecg:Normal sinus rhythm"), .ecg("Normal sinus rhythm"))
    }

    func testECGAtrialFibrillationFilesTheHistoryAsThePageDoes() {
        let q = read("ECG: AF")
        let f = finding(q, "ecg:Atrial fibrillation")
        XCTAssertEqual(f?.change, .ecg("Atrial fibrillation"))
        XCTAssertTrue(f?.note?.contains("history") == true, "\(String(describing: f?.note))")
        XCTAssertFalse(ids(q).contains("problem:af"), "one chip: the ECG finding files the history item itself")
        let r = applied(q)
        XCTAssertEqual(r.ecg, ["Atrial fibrillation"])
        XCTAssertTrue(r.has("af"))
    }

    func testECGStatus() {
        var r = PatientRecord()
        r.ecg = ["Atrial fibrillation", "Left bundle branch block"]
        XCTAssertEqual(status(read("ECG NSR"), "ecg:Normal sinus rhythm", in: r), .replaces("Atrial fibrillation"), "a rhythm replaces the rhythm before it")
        XCTAssertEqual(status(read("ECG LBBB"), "ecg:Left bundle branch block", in: r), .recorded)
        XCTAssertEqual(status(read("ECG RBBB"), "ecg:Right bundle branch block", in: r), .new)
        XCTAssertEqual(applied(read("ECG NSR"), to: r).ecg, ["Normal sinus rhythm", "Left bundle branch block"])
        r.ecg = ["Normal sinus rhythm"]
        XCTAssertEqual(status(read("ECG CHB"), "ecg:Complete heart block", in: r), .replaces("Normal sinus rhythm"))
    }

    // MARK: The airway at handoff

    func testExtubatedAndRemainsIntubatedOnTheIntraoperativeTab() {
        let e = read("extubated", .intraop, record: intubated)
        XCTAssertEqual(change(e, "airway-end"), .airwayAtEnd("extubated"))
        XCTAssertNil(finding(e, "airway-end")?.note, "an intubation is recorded")
        XCTAssertEqual(applied(e, to: intubated).airwayAtEnd, "extubated")
        XCTAssertEqual(e.unread, "")
        XCTAssertEqual(chipTexts(e, record: intubated), ["Handoff · Extubated"])

        XCTAssertEqual(change(read("remains intubated", .intraop), "airway-end"), .airwayAtEnd("intubated"))
        XCTAssertEqual(chipTexts(read("remains intubated", .intraop)), ["Handoff · Remains intubated"])
        let icu = read("left intubated to ICU", .intraop)
        XCTAssertEqual(change(icu, "airway-end"), .airwayAtEnd("intubated"))
        XCTAssertEqual(change(icu, "disposition"), .disposition("ICU"))
        XCTAssertEqual(icu.unread, "")
        XCTAssertEqual(change(read("LMA out", .intraop), "airway-end"), .airwayAtEnd("extubated"))
        XCTAssertFalse(ids(read("LMA out", .intraop)).contains("intraop-airway:device"), "LMA out is not the device placed")
        XCTAssertEqual(change(read("not extubated", .intraop), "airway-end"), .airwayAtEnd("intubated"), "negated")
        XCTAssertEqual(change(read("reintubated", .intraop), "airway-end"), .airwayAtEnd("intubated"))
        XCTAssertEqual(change(read("extubated in OR, then reintubated", .intraop), "airway-end"), .airwayAtEnd("intubated"), "the later state")
        XCTAssertEqual(change(read("no complications, extubated", .intraop), "airway-end"), .airwayAtEnd("extubated"), "a negation in another piece")
        XCTAssertEqual(finding(read("extubated", .intraop), "airway-end")?.note, "The airway course has no intubation or LMA yet.")
        XCTAssertFalse(ids(read("extubated", .intraop)).contains("airway"), "not the airway on arrival")
    }

    func testAirwayAtEndOnSummaryAndNotOnPreop() {
        XCTAssertEqual(change(summary("extubated"), "airway-end"), .airwayAtEnd("extubated"), "Summary & Handoff reads the end of the case")
        XCTAssertEqual(change(summary("remains intubated"), "airway-end"), .airwayAtEnd("intubated"))
        XCTAssertFalse(ids(summary("remains intubated")).contains("airway"), "not the ETT on arrival")
        XCTAssertNil(change(read("extubated"), "airway-end"), "not on the Preoperative tab")
        XCTAssertNil(change(read("extubated POD1 last year"), "airway-end"))
        XCTAssertNil(change(read("remains intubated", .preop), "airway-end"))
        XCTAssertNil(change(read("extubated POD1", .intraop), "airway-end"), "told as past")
        XCTAssertNil(change(read("extubated 2019", .intraop), "airway-end"))
    }

    func testAirwayAtEndStatus() {
        var r = intubated
        r.airwayAtEnd = "intubated"
        XCTAssertEqual(status(read("extubated", .intraop, record: r), "airway-end", in: r), .replaces("remains intubated"))
        XCTAssertEqual(status(read("remains intubated", .intraop, record: r), "airway-end", in: r), .recorded)
        r.airwayAtEnd = "extubated"
        XCTAssertEqual(status(read("remains intubated", .intraop, record: r), "airway-end", in: r), .replaces("extubated"))
        XCTAssertEqual(status(read("extubated", .intraop, record: r), "airway-end", in: r), .recorded)
    }

    // MARK: The disposition

    func testDispositionWords() {
        XCTAssertEqual(change(read("to ICU", .intraop), "disposition"), .disposition("ICU"))
        XCTAssertEqual(chipTexts(read("to ICU", .intraop)), ["Disposition · ICU"])
        XCTAssertEqual(change(read("to PACU", .intraop), "disposition"), .disposition("PACU"))
        XCTAssertEqual(change(read("to the floor", .intraop), "disposition"), .disposition("Ward"))
        XCTAssertEqual(change(read("to CVICU", .intraop), "disposition"), .disposition("ICU"))
        XCTAssertEqual(change(read("→ PACU", .intraop), "disposition"), .disposition("PACU"))
        XCTAssertEqual(change(read("dispo: ICU", .intraop), "disposition"), .disposition("ICU"))
        XCTAssertEqual(change(read("to PACU then home", .intraop), "disposition"), .disposition("PACU"), "the first place said")
        XCTAssertEqual(change(read("then home", .intraop), "disposition"), .disposition("Same-day discharge"))
        XCTAssertEqual(change(read("planned ICU postop"), "disposition"), .disposition("ICU"), "from the Preoperative tab too")
        XCTAssertEqual(change(summary("to ICU"), "disposition"), .disposition("ICU"))
        XCTAssertEqual(applied(read("to ICU", .intraop)).disposition, "ICU")
        XCTAssertEqual(read("to ICU", .intraop).unread, "")
    }

    func testDispositionIsNotAnOriginOrAPastStay() {
        XCTAssertNil(change(read("from ICU", .intraop), "disposition"), "an origin")
        XCTAssertNil(change(read("68M from the ICU for trach"), "disposition"))
        XCTAssertNil(change(read("ICU", .intraop), "disposition"), "a bare ICU says nothing")
        XCTAssertNil(change(read("admitted to ICU 2 days ago"), "disposition"), "a stay that was")
        XCTAssertNil(change(read("was transferred to the floor"), "disposition"))
        XCTAssertNil(change(read("to OR", .intraop), "disposition"))
    }

    func testFastTrack() {
        let q = read("fast track", .intraop)
        XCTAssertEqual(change(q, "disposition"), .disposition("PACU"))
        XCTAssertEqual(finding(q, "disposition")?.note, "Fast track read as PACU; choose ICU if that is the plan.")
        var cabg = PatientRecord()
        cabg.setProcedures(PlannedProcedure.parse("CABG x3"))
        let c = read("fast track", .intraop, record: cabg)
        XCTAssertNil(change(c, "disposition"), "after cardiac surgery fast track is early extubation, not a destination")
        XCTAssertTrue(c.skipped.contains { $0.hasPrefix("Fast track") }, "\(c.skipped)")
        XCTAssertEqual(change(read("fast track to ICU", .intraop, record: cabg), "disposition"), .disposition("ICU"), "the place said wins")
    }

    func testDispositionStatus() {
        var r = PatientRecord()
        r.disposition = "PACU"
        XCTAssertEqual(status(read("to ICU", .intraop), "disposition", in: r), .replaces("PACU"))
        XCTAssertEqual(status(read("to PACU", .intraop), "disposition", in: r), .recorded)
        XCTAssertEqual(status(read("to ICU", .intraop), "disposition", in: PatientRecord()), .new)
    }

    // MARK: The cardiac answers

    func testNoCardiacSymptomsAndNoAcuteConditionsAreSeparate() {
        let s = read("no cardiac symptoms")
        XCTAssertEqual(change(s, "cardiac:symptoms"), .cardiacAnswer("symptoms", false))
        XCTAssertNil(change(s, "cardiac:acute"), "the other answer is not asserted")
        XCTAssertEqual(chipTexts(s), ["Cardiac · No symptoms"])
        let r = applied(s)
        XCTAssertEqual(r.cardiacSymptomsAnswer, false)
        XCTAssertNil(r.activeCardiacAnswer)
        XCTAssertEqual(s.unread, "")

        let a = read("no acute cardiac conditions")
        XCTAssertEqual(change(a, "cardiac:acute"), .cardiacAnswer("acute", false))
        XCTAssertNil(change(a, "cardiac:symptoms"))
        XCTAssertEqual(chipTexts(a), ["Cardiac · No acute conditions"])
        XCTAssertEqual(applied(a).activeCardiacAnswer, false)
        XCTAssertNil(applied(a).cardiacSymptomsAnswer)

        let both = read("asymptomatic from a cardiac standpoint, no acute cardiac conditions")
        XCTAssertEqual(change(both, "cardiac:symptoms"), .cardiacAnswer("symptoms", false))
        XCTAssertEqual(change(both, "cardiac:acute"), .cardiacAnswer("acute", false))
        XCTAssertEqual(both.unread, "")
        XCTAssertEqual(change(read("denies cardiac sx"), "cardiac:symptoms"), .cardiacAnswer("symptoms", false))
        XCTAssertEqual(change(read("cardiac symptoms: none"), "cardiac:symptoms"), .cardiacAnswer("symptoms", false))
        XCTAssertEqual(change(read("no active cardiac issues"), "cardiac:acute"), .cardiacAnswer("acute", false))
    }

    func testCardiacAnswersAreNotReadFromOtherWords() {
        let q = read("denies chest pain, SOB")
        XCTAssertNil(change(q, "cardiac:symptoms"), "one symptom denied is not all of them")
        XCTAssertFalse(ids(q).contains("symptom:chest-pain"))
        XCTAssertNil(change(read("cardiac symptoms: chest pain"), "cardiac:symptoms"))
        XCTAssertEqual(change(read("cardiac symptoms: chest pain"), "symptom:chest-pain"), .symptom("chest-pain"))
        let intraop = read("no cardiac symptoms", .intraop)
        XCTAssertNil(change(intraop, "cardiac:symptoms"), "the preoperative evaluation is not filed from the OR")
        XCTAssertTrue(intraop.skipped.contains(QuickAdd.historyElsewhere))
    }

    func testCardiacAnswerStatus() {
        var r = PatientRecord()
        r.cardiacSymptoms = ["chest-pain"]
        if case .conflicts(let why)? = status(read("no cardiac symptoms"), "cardiac:symptoms", in: r) {
            XCTAssertTrue(why.contains("chest pain"), why)
        } else {
            XCTFail("a recorded symptom is never hidden by a No")
        }
        r.cardiacSymptoms = []
        r.cardiacSymptomsAnswer = false
        XCTAssertEqual(status(read("no cardiac symptoms"), "cardiac:symptoms", in: r), .recorded)
        r.cardiacSymptomsAnswer = true
        XCTAssertEqual(status(read("no cardiac symptoms"), "cardiac:symptoms", in: r), .replaces("Yes"))
        var a = PatientRecord()
        a.activeCardiac = ["acs"]
        if case .conflicts? = status(read("no acute cardiac conditions"), "cardiac:acute", in: a) {} else { XCTFail("a recorded acute condition is never hidden") }
        XCTAssertEqual(status(read("no acute cardiac conditions"), "cardiac:acute", in: PatientRecord()), .new)
    }

    // MARK: The stress test

    private func stress(_ q: QuickAddReading) -> PatientStressTest? {
        if case .stressTest(let t)? = change(q, "stress") { return t }
        return nil
    }

    func testStressTestWording() {
        let dse = read("DSE negative")
        XCTAssertEqual(stress(dse)?.kind, .dobutamine)
        XCTAssertEqual(stress(dse)?.result, .negative)
        XCTAssertEqual(chipTexts(dse), ["Workup · Dobutamine stress test negative"])
        XCTAssertEqual(dse.unread, "")
        let r = applied(dse)
        XCTAssertEqual(r.stressTest.kind, .dobutamine)
        XCTAssertEqual(r.stressTest.result, .negative)
        XCTAssertEqual(r.stressTest.summary, "Dobutamine stress test: negative, no ischemia")

        let none = read("stress test: no ischemia")
        XCTAssertNil(stress(none)?.kind)
        XCTAssertEqual(stress(none)?.result, .negative, "no ischemia is negative, not the ischemia")
        XCTAssertFalse(ids(none).contains("problem:ischemia"))
        XCTAssertEqual(chipTexts(none), ["Workup · Stress test negative"])
        XCTAssertEqual(none.unread, "")

        let ex = read("exercise stress positive")
        XCTAssertEqual(stress(ex)?.kind, .exercise)
        XCTAssertEqual(stress(ex)?.result, .positive)
        XCTAssertEqual(chipTexts(ex), ["Workup · Exercise stress test positive"])

        let lex = read("Lexiscan 03/2025 equivocal")
        XCTAssertEqual(stress(lex)?.kind, .other)
        XCTAssertEqual(stress(lex)?.result, .equivocal)
        XCTAssertEqual(stress(lex)?.date, PatientMonthYear(month: 3, year: 2025))
        XCTAssertEqual(chipTexts(lex), ["Workup · Stress test equivocal (03/2025)"])
        XCTAssertEqual(stress(read("DSE 2024 negative"))?.date, PatientMonthYear(year: 2024))
        XCTAssertEqual(stress(read("nuclear stress test normal"))?.result, .negative)
        XCTAssertEqual(stress(read("stress echo: inferior ischemia"))?.result, .positive)
    }

    func testStressTestIsNotReadFromOtherWords() {
        XCTAssertNil(change(read("stress dose steroids"), "stress"), "stress-dose steroids")
        XCTAssertNil(change(read("no stress test"), "stress"))
        XCTAssertNil(change(read("stress test pending"), "stress"))
        XCTAssertNil(change(read("stress test recommended"), "stress"))
        XCTAssertNil(change(read("stress test"), "stress"), "nothing said of it")
        XCTAssertNil(change(read("7.5 ETT, extubated", .intraop), "stress"), "the tube, not the treadmill")
        let intraop = read("DSE negative", .intraop)
        XCTAssertNil(change(intraop, "stress"), "the preoperative workup is not filed from the OR")
        XCTAssertTrue(intraop.skipped.contains(QuickAdd.historyElsewhere))
    }

    func testTreadmillETTByContext() {
        let q = read("ETT negative for ischemia")
        XCTAssertEqual(stress(q)?.kind, .exercise, "\(q.findings.map(\.label)) \(q.ambiguous.map(\.id))")
        XCTAssertEqual(stress(q)?.result, .negative)
    }

    func testStressTestStatusAndMerge() {
        var r = PatientRecord()
        r.stressTest = PatientStressTest(kind: .dobutamine, result: .negative, findings: "no wall-motion abnormality at peak")
        XCTAssertEqual(status(read("DSE negative"), "stress", in: r), .recorded)
        XCTAssertEqual(status(read("stress test negative"), "stress", in: r), .recorded, "a kind not said is not a change")
        if case .replaces(let old)? = status(read("DSE positive"), "stress", in: r) {
            XCTAssertTrue(old.hasPrefix("Dobutamine stress test"), old)
        } else {
            XCTFail("a different result replaces")
        }
        XCTAssertEqual(status(read("DSE 2024"), "stress", in: r), .new, "a date added")
        let merged = applied(read("DSE 2024"), to: r)
        XCTAssertEqual(merged.stressTest.date, PatientMonthYear(year: 2024))
        XCTAssertEqual(merged.stressTest.result, .negative, "kept")
        XCTAssertEqual(merged.stressTest.findings, "no wall-motion abnormality at peak", "never cleared")
        XCTAssertEqual(status(read("DSE negative"), "stress", in: PatientRecord()), .new)
    }

    // MARK: Events

    func testIntraoperativeEvents() {
        let q = read("hypotension after induction", .intraop)
        XCTAssertEqual(change(q, "event:hypotension after induction"), .event("hypotension after induction"), "\(q.findings.map(\.id))")
        XCTAssertEqual(chipTexts(q), ["Event · Hypotension after induction"])
        let r = applied(q)
        XCTAssertEqual(r.events, "hypotension after induction")
        XCTAssertFalse(r.noEvents)
        XCTAssertEqual(q.unread, "")

        let two = read("hypotension after induction, bronchospasm on emergence", .intraop)
        XCTAssertEqual(ids(two).filter { $0.hasPrefix("event:") }, ["event:hypotension after induction", "event:bronchospasm on emergence"])
        XCTAssertEqual(applied(two).events, "hypotension after induction; bronchospasm on emergence")

        let bleed = read("bleeding EBL 1200", .intraop)
        XCTAssertEqual(change(bleed, "event:bleeding"), .event("bleeding"), "\(bleed.findings.map(\.id))")
        XCTAssertEqual(applied(bleed).fluids["ebl"], 1200, "the blood loss is still read")

        let af = read("new AF w RVR after bypass, amio 150", .intraop)
        XCTAssertTrue(ids(af).contains { $0.hasPrefix("event:new af") }, "\(af.findings.map(\.id))")
        XCTAssertFalse(ids(af).contains("problem:af"))
        XCTAssertTrue(ids(read("tachycardic to 140s, esmolol 20", .intraop)).contains { $0.hasPrefix("event:tachycardic") })
        XCTAssertTrue(ids(summary("bradycardia on emergence")).contains("event:bradycardia on emergence"), "Summary & Handoff too")
        XCTAssertFalse(ids(summary("bradycardia on emergence")).contains { $0.hasPrefix("symptom:") })
    }

    func testEventsAreNotReadWhereTheyAreNotEvents() {
        XCTAssertFalse(ids(read("no hypotension", .intraop)).contains { $0.hasPrefix("event:") }, "negated")
        XCTAssertFalse(ids(read("hypotension after induction")).contains { $0.hasPrefix("event:") }, "not on the Preoperative tab")
        XCTAssertFalse(ids(read("VT 450", .intraop)).contains { $0.hasPrefix("event:") }, "a tidal volume")
        XCTAssertFalse(ids(read("mh", .intraop)).contains { $0.hasPrefix("event:") }, "MH in capitals only")
        XCTAssertTrue(ids(read("MH", .intraop)).contains("event:mh"))
        XCTAssertFalse(ids(read("norepi 0.05, PRBC 2, EBL 500", .intraop)).contains { $0.hasPrefix("event:") })
    }

    func testEventStatus() {
        var r = PatientRecord()
        r.events = "Hypotension after induction"
        XCTAssertEqual(status(read("hypotension after induction", .intraop), "event:hypotension after induction", in: r), .recorded)
        XCTAssertEqual(status(read("bronchospasm", .intraop), "event:bronchospasm", in: r), .new)
        XCTAssertEqual(applied(read("bronchospasm", .intraop), to: r).events, "Hypotension after induction; bronchospasm")
    }

    // MARK: The Intraoperative example

    func testIntraopPlaceholderRotatesWithTheCase() {
        XCTAssertEqual(QuickAdd.placeholder(.intraopTab), QuickAdd.intraopPlaceholders[0], "without a record, as before")
        XCTAssertEqual(QuickAdd.intraopPlaceholders[1], "extubated, to PACU")
        var r = PatientRecord()
        XCTAssertEqual(QuickAdd.intraopExample(r), 0)
        XCTAssertEqual(QuickAdd.placeholder(.intraopTab, record: r), QuickAdd.intraopPlaceholders[0])
        r.infusions = [PatientInfusion(drug: "Norepinephrine", rate: "0.05 mcg/kg/min")]
        XCTAssertEqual(QuickAdd.intraopExample(r), 1, "the case has started")
        XCTAssertEqual(QuickAdd.placeholder(.intraopTab, record: r), "extubated, to PACU")
        XCTAssertEqual(QuickAdd.placeholder(.editor(intraop: true), record: r), "extubated, to PACU")
        r.airwayAtEnd = "extubated"
        XCTAssertEqual(QuickAdd.intraopExample(r), 2, "the end is told")
        XCTAssertEqual(QuickAdd.placeholder(.intraopTab, record: r), QuickAdd.intraopPlaceholders[2])
        var d = PatientRecord()
        d.disposition = "ICU"
        d.fluids = ["ebl": 200]
        XCTAssertEqual(QuickAdd.intraopExample(d), 2)
        XCTAssertEqual(QuickAdd.placeholder(.preopTab, record: r), QuickAdd.placeholder(.preopTab), "the other places keep their example")
        XCTAssertEqual(QuickAdd.placeholder(.summaryTab, record: r), QuickAdd.placeholder(.summaryTab))
        XCTAssertEqual(QuickAdd.intraopExample(PatientDemo.quickAdd111), 1)
        XCTAssertEqual(QuickAdd.intraopExample(PatientDemo.quickAdd111End), 2)
    }

    func testEachIntraopPlaceholderReads() {
        for p in QuickAdd.intraopPlaceholders {
            let q = read(p, .intraop)
            XCTAssertFalse(q.findings.isEmpty, p)
            XCTAssertEqual(q.unread, "", p)
        }
        let end = read("extubated, to PACU", .intraop)
        XCTAssertEqual(change(end, "airway-end"), .airwayAtEnd("extubated"))
        XCTAssertEqual(change(end, "disposition"), .disposition("PACU"))
    }

    // MARK: A whole line, and saved records

    func testAHandoffLine() {
        let q = read("extubated, to ICU, hypotension after induction", .intraop, record: intubated)
        XCTAssertEqual(ids(q), ["airway-end", "disposition", "event:hypotension after induction"])
        XCTAssertEqual(chipTexts(q, record: intubated), ["Handoff · Extubated", "Disposition · ICU", "Event · Hypotension after induction"])
        XCTAssertEqual(q.unread, "")
        let r = applied(q, to: intubated)
        XCTAssertEqual(r.airwayAtEnd, "extubated")
        XCTAssertEqual(r.disposition, "ICU")
        XCTAssertEqual(r.events, "hypotension after induction")
        let lines = PatientSummary.planLines(r)
        XCTAssertTrue(lines.contains { $0.label == "Disposition" && $0.text == "ICU" })
    }

    func testAPreopWorkupLine() {
        let q = read("ECG NSR LBBB, no cardiac symptoms, no acute cardiac conditions, DSE negative 2024")
        XCTAssertEqual(Set(ids(q)), ["ecg:Normal sinus rhythm", "ecg:Left bundle branch block", "cardiac:symptoms", "cardiac:acute", "stress"])
        XCTAssertEqual(q.unread, "")
        let r = applied(q)
        XCTAssertEqual(r.ecg, ["Normal sinus rhythm", "Left bundle branch block"])
        XCTAssertEqual(r.cardiacSymptomsAnswer, false)
        XCTAssertEqual(r.activeCardiacAnswer, false)
        XCTAssertEqual(r.stressTest.result, .negative)
        XCTAssertEqual(r.stressTest.date, PatientMonthYear(year: 2024))
        XCTAssertEqual(PatientSummary.ecgText(r), "Normal sinus rhythm; Left bundle branch block")
    }

    /// A record saved by 1.10 (no stress test, the fields the rules write as they were) still opens, and one the rules
    /// wrote round-trips.
    func testSavedRecordsKeepDecoding() throws {
        let json = #"{"events":"Hypotension after induction","airwayAtEnd":"intubated","disposition":"ICU","ecg":["Normal sinus rhythm"],"cardiacSymptomsAnswer":false,"noEvents":false}"#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.events, "Hypotension after induction")
        XCTAssertEqual(r.airwayAtEnd, "intubated")
        XCTAssertEqual(r.disposition, "ICU")
        XCTAssertEqual(r.ecg, ["Normal sinus rhythm"])
        XCTAssertEqual(r.cardiacSymptomsAnswer, false)
        XCTAssertNil(r.activeCardiacAnswer)
        XCTAssertTrue(r.stressTest.isEmpty, "no stress test in a 1.10 record")
        XCTAssertNoThrow(try JSONDecoder().decode(PatientRecord.self, from: Data("{}".utf8)))

        let written = applied(read("ECG NSR LBBB, DSE negative 2024, no cardiac symptoms"), to: r)
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(written))
        XCTAssertEqual(again.stressTest, written.stressTest)
        XCTAssertEqual(again.ecg, written.ecg)
        XCTAssertEqual(again.cardiacSymptomsAnswer, false)
    }

    func testDemoPatientsForTheScreenshots() {
        let mid = PatientDemo.quickAdd111
        XCTAssertNil(mid.airwayAtEnd)
        XCTAssertNil(mid.disposition)
        XCTAssertTrue(mid.ecg.isEmpty)
        XCTAssertTrue(mid.stressTest.isEmpty)
        XCTAssertFalse(mid.infusions.isEmpty)
        let end = PatientDemo.quickAdd111End
        XCTAssertEqual(end.airwayAtEnd, "extubated")
        XCTAssertEqual(end.disposition, "ICU")
        XCTAssertEqual(end.events, "Hypotension after induction")
    }
}
