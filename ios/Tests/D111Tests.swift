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
        // A rhythm the history reads too is the ECG's only in the ECG's own piece.
        let mixed = read("AF on apixaban, ECG: NSR, LBBB")
        XCTAssertNil(change(mixed, "ecg:Atrial fibrillation"), "the history's AF, not today's rhythm")
        XCTAssertTrue(ids(mixed).contains("problem:af"))
        XCTAssertEqual(applied(mixed).ecg, ["Normal sinus rhythm", "Left bundle branch block"])
        XCTAssertEqual(change(read("EKG shows SVT"), "ecg:SVT"), .ecg("SVT"))
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
        XCTAssertNil(change(read("chest tube out", .intraop), "airway-end"), "a chest tube, not the airway")
        XCTAssertNil(change(read("arrives intubated", .intraop), "airway-end"), "the airway on arrival")
        XCTAssertEqual(change(read("ETT out", .intraop), "airway-end"), .airwayAtEnd("extubated"))
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

    /// Fast track is one of Status & Plan's own disposition chips, stored as its label.
    func testFastTrack() {
        let q = read("fast track", .intraop)
        XCTAssertEqual(change(q, "disposition"), .disposition("Fast track"))
        XCTAssertNil(finding(q, "disposition")?.note)
        XCTAssertEqual(StatusPlanCard.dispositionChip(applied(q).disposition), "Fast track", "shows as its own chip")
        XCTAssertEqual(change(read("fast-tracked", .intraop), "disposition"), .disposition("Fast track"))
        XCTAssertEqual(change(summary("fast track"), "disposition"), .disposition("Fast track"))
        XCTAssertEqual(change(read("extubated, fast track", .intraop), "airway-end"), .airwayAtEnd("extubated"))
        XCTAssertEqual(StatusPlanCard.dispositionChip(applied(read("to the floor", .intraop)).disposition), "Other", "Ward shows as Other with its text")
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
        XCTAssertEqual(chipTexts(dse), ["Workup · DSE negative"])
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
        XCTAssertEqual(chipTexts(ex), ["Workup · Exercise stress positive"])

        let lex = read("Lexiscan 03/2025 equivocal")
        XCTAssertEqual(stress(lex)?.kind, .other)
        XCTAssertEqual(stress(lex)?.result, .equivocal)
        XCTAssertEqual(stress(lex)?.date, PatientMonthYear(month: 3, year: 2025))
        XCTAssertEqual(chipTexts(lex), ["Workup · Stress test equivocal (03/2025)"])
        XCTAssertEqual(stress(read("DSE 2024 negative"))?.date, PatientMonthYear(year: 2024))
        XCTAssertEqual(stress(read("nuclear stress test normal"))?.result, .negative)
        XCTAssertEqual(stress(read("stress echo: inferior ischemia"))?.result, .positive)
    }

    /// "Normal" said of something else is not the result, and a positive finding is never read as a negative test.
    func testAStressResultIsNotTakenFromANormalSaidOfSomethingElse() {
        for line in ["DSE positive for ischemia with normal EF", "stress echo with inducible ischemia and normal LV function",
                     "stress test not normal", "nuclear stress abnormal with normal BP response"] {
            XCTAssertEqual(stress(read(line))?.result, .positive, line)
        }
        XCTAssertEqual(stress(read("DSE no evidence of ischemia"))?.result, .negative)
        // Nothing said of the test itself: the kind is filed, the result is left to the user.
        let ef = read("DSE normal EF")
        XCTAssertEqual(stress(ef)?.kind, .dobutamine)
        XCTAssertNil(stress(ef)?.result, "normal EF is not a negative test")
        XCTAssertNil(stress(read("DSE not negative"))?.result)
        // An outright negative beside a positive finding of its own: the two disagree, so neither is filed.
        XCTAssertNil(stress(read("DSE negative for ischemia but abnormal wall motion"))?.result)
        XCTAssertNil(change(read("stress test normal sinus rhythm"), "stress"), "no kind, no result: nothing filed")
    }

    func testStressTestIsNotReadFromOtherWords() {
        XCTAssertNil(change(read("stress dose steroids"), "stress"), "stress-dose steroids")
        XCTAssertNil(change(read("dobutamine 5 mcg/kg/min"), "stress"), "a drip")
        XCTAssertNil(change(read("walks on the treadmill daily"), "stress"), "exercise, not the test")
        XCTAssertNil(change(read("on aspirin and dipyridamole"), "stress"), "the antiplatelet drug")
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
        XCTAssertFalse(ids(read("ischemic cardiomyopathy", .intraop)).contains { $0.hasPrefix("event:") }, "history, not an event")
        XCTAssertFalse(ids(read("pulmonary hypertension", .intraop)).contains { $0.hasPrefix("event:") })
        XCTAssertTrue(ids(read("ischemia on TEE after bypass", .intraop)).contains { $0.hasPrefix("event:ischemia") })
        XCTAssertFalse(ids(read("norepi 0.05, PRBC 2, EBL 500", .intraop)).contains { $0.hasPrefix("event:") })
    }

    /// The events reader never shadows the history and allergy readers (1.11 review). Summary & Handoff read as the
    /// Preoperative tab in 1.10, so "hypertension" typed there is still the problem; a word both readers read
    /// (hypertension, AF, seizure, a bleeding disorder, anaphylaxis) is an event only where its piece says when or how
    /// it happened in the case, on either tab.
    func testEventsLeaveHistoryAndAllergiesToTheirReaders() {
        let htn = summary("hypertension, diabetes")
        XCTAssertTrue(ids(htn).contains("problem:htn"), "\(ids(htn))")
        XCTAssertTrue(ids(htn).contains("problem:dm"), "\(ids(htn))")
        XCTAssertFalse(ids(htn).contains { $0.hasPrefix("event:") })
        XCTAssertTrue(ids(summary("hypertension")).contains("problem:htn"))
        let af = summary("afib on apixaban")
        XCTAssertTrue(ids(af).contains("problem:af"), "\(ids(af))")
        XCTAssertFalse(ids(af).contains { $0.hasPrefix("event:") })
        XCTAssertTrue(ids(summary("seizure disorder on keppra")).contains("problem:seizure"))
        let bleeding = summary("bleeding disorder")
        XCTAssertTrue(ids(bleeding).contains("problem:bleeding"), "\(ids(bleeding))")
        XCTAssertFalse(ids(bleeding).contains { $0.hasPrefix("event:") })
        let allergy = read("allergies: PCN (anaphylaxis)", .intraop)
        XCTAssertTrue(ids(allergy).contains { $0.hasPrefix("allergies:") }, "\(ids(allergy))")
        XCTAssertFalse(ids(allergy).contains { $0.hasPrefix("event:") })
        XCTAssertTrue(ids(summary("allergies: PCN (anaphylaxis)")).contains { $0.hasPrefix("allergies:") })

        // On Summary & Handoff every event says when or how it happened: "hypotension" alone is not one there (1.10).
        XCTAssertFalse(ids(summary("hypotension")).contains { $0.hasPrefix("event:") })
        XCTAssertTrue(ids(summary("hypotension after induction")).contains("event:hypotension after induction"))
        let newAF = summary("new AF after bypass")
        XCTAssertTrue(ids(newAF).contains("event:new af after bypass"), "\(ids(newAF))")
        XCTAssertFalse(ids(newAF).contains("problem:af"))
        XCTAssertTrue(ids(summary("remains intubated to CVICU, bradycardia on emergence")).contains("event:bradycardia on emergence"))

        // On the Intraoperative tab a shared word needs its context; one the history never reads does not.
        XCTAssertFalse(ids(read("hypertension", .intraop)).contains { $0.hasPrefix("event:") })
        XCTAssertTrue(ids(read("hypertension with incision", .intraop)).contains("event:hypertension with incision"))
        XCTAssertTrue(ids(read("anaphylaxis after cefazolin", .intraop)).contains("event:anaphylaxis after cefazolin"))
        XCTAssertFalse(ids(read("afib", .intraop)).contains { $0.hasPrefix("event:") })
        XCTAssertTrue(ids(read("seizure on emergence", .intraop)).contains("event:seizure on emergence"))
        XCTAssertTrue(ids(read("hypotension", .intraop)).contains("event:hypotension"), "not a history word: the event, as before")
        XCTAssertFalse(ids(read("MH susceptible", .intraop)).contains { $0.hasPrefix("event:") }, "the history's MH")
    }

    // MARK: Events against history, allergies and past cases (1.11 review)

    private func events(_ q: QuickAddReading) -> [String] { ids(q).filter { $0.hasPrefix("event:") } }
    /// The two places that read events: Summary & Handoff and the Intraoperative tab.
    private func bothPlaces(_ s: String) -> [(place: String, q: QuickAddReading)] {
        [("Summary & Handoff", summary(s)), ("Intraoperative", read(s, .intraop))]
    }
    private func assertNoEvent(_ lines: [String], file: StaticString = #filePath, line: UInt = #line) {
        for s in lines {
            for (place, q) in bothPlaces(s) { XCTAssertEqual(events(q), [], "\(s) on \(place)", file: file, line: line) }
        }
    }

    /// How a problem is treated or how it went ("treated with", "resolved", "requiring", "new onset", "episodes of") is
    /// not the case: a word the history reads is an event only with a point of the case, on either place.
    func testTreatmentWordsDoNotMakeAnEventOfHistory() {
        assertNoEvent(["hypertension treated with lisinopril", "seizures resolved", "seizures treated with keppra", "hypertension requiring 3 agents",
                       "SVT treated with adenosine 2020", "arrhythmia resolved after ablation", "new onset AF last month on apixaban",
                       "paroxysmal AF with episodes of RVR", "episodes of hypoglycemia on insulin", "hypoxemia requiring home O2",
                       "GERD with aspiration requiring PPI", "AF with RVR 2022", "HTN on 3 agents", "new AF", "hypertension x 5 years"])

        let htn = summary("hypertension treated with lisinopril")
        XCTAssertTrue(ids(htn).contains("problem:htn"), "\(ids(htn))")
        XCTAssertEqual(applied(htn).events, "")
        let htnIntraop = read("hypertension treated with lisinopril", .intraop)
        XCTAssertTrue(htnIntraop.skipped.contains(QuickAdd.historyElsewhere), "set aside for the Preop tab, as in 1.10")
        XCTAssertEqual(applied(htnIntraop).events, "")
        let seizures = summary("seizures resolved")
        XCTAssertTrue(ids(seizures).contains("problem:seizure"), "\(ids(seizures))")
        XCTAssertTrue(read("seizures resolved", .intraop).skipped.contains(QuickAdd.historyElsewhere))
        XCTAssertTrue(ids(summary("seizures treated with keppra")).contains("problem:seizure"))
        XCTAssertTrue(ids(summary("hypertension requiring 3 agents")).contains("problem:htn"))

        // The same words still tell an event of a word the history does not read, on Summary & Handoff too.
        XCTAssertTrue(events(summary("hypotension requiring phenylephrine")).contains { $0.hasPrefix("event:hypotension requiring") })
        XCTAssertTrue(events(summary("tachycardia treated with beta blocker")).contains { $0.hasPrefix("event:tachycardia treated with") })
        XCTAssertEqual(events(summary("transient hypotension")), ["event:transient hypotension"])
        XCTAssertTrue(QuickAdd.isEvent("hypotension requiring phenylephrine", lead: "", strict: true))
        XCTAssertFalse(QuickAdd.isEvent("hypertension requiring 3 agents", lead: "", strict: true))
        XCTAssertFalse(QuickAdd.isEvent("hypertension treated with lisinopril", lead: "", strict: false))
        // "new", "resolved" and "episodes of" say nothing of the case: no event there without a point of the case.
        for piece in ["new stridor", "new onset laryngospasm", "bronchospasm resolved", "episodes of bronchospasm"] {
            XCTAssertFalse(QuickAdd.isEvent(piece, lead: "", strict: true), piece)
            XCTAssertEqual(events(summary(piece)), [], piece)
        }
        XCTAssertEqual(events(summary("new stridor after extubation")), ["event:new stridor after extubation"])
    }

    /// A piece with an allergy cue is the allergy reader's, reaction and all, as in 1.10.
    func testAnAllergyIsNeverAnEvent() {
        assertNoEvent(["allergic to rocuronium (anaphylaxis)", "allergic to latex (anaphylaxis)", "PCN allergy (anaphylaxis to cefazolin too)",
                       "allergies: rocuronium - anaphylaxis with induction 2019", "allergies: PCN, latex (anaphylaxis)"])
        for (place, q) in bothPlaces("allergic to rocuronium (anaphylaxis)") {
            XCTAssertTrue(ids(q).contains { $0.hasPrefix("allergies:rocuronium") && $0.contains("anaphylaxis") }, "\(place): \(ids(q))")
            XCTAssertEqual(applied(q).events, "", place)
        }
        for s in ["allergic to latex (anaphylaxis)", "PCN allergy (anaphylaxis to cefazolin too)", "allergies: rocuronium - anaphylaxis with induction 2019"] {
            for (place, q) in bothPlaces(s) { XCTAssertTrue(ids(q).contains { $0.hasPrefix("allergies:") }, "\(s) on \(place): \(ids(q))") }
        }
        XCTAssertFalse(QuickAdd.isEvent("allergic to rocuronium (anaphylaxis)", lead: "", strict: false))
        // "PCN allergy" opening the line is penicillin, not the nephrostomy the procedure list knows as PCN; the
        // procedure opening a line is still read.
        for q in [read("PCN allergy"), summary("PCN allergy (anaphylaxis to cefazolin too)")] {
            XCTAssertNil(finding(q, "procedure"), "\(ids(q))")
            XCTAssertTrue(ids(q).contains("allergies:pcn"), "\(ids(q))")
        }
        XCTAssertNotNil(finding(read("PCN, HTN"), "procedure"), "\(ids(read("PCN, HTN")))")
        XCTAssertFalse(QuickAdd.isEvent("anaphylaxis", lead: "allergies: PCN", strict: false), "the reaction later in an allergy list")

        // An event beside an allergy is still the event, and the allergy is still the allergy.
        for (place, q) in bothPlaces("allergic to PCN, hypotension after induction") {
            XCTAssertEqual(events(q), ["event:hypotension after induction"], place)
            XCTAssertTrue(ids(q).contains { $0.hasPrefix("allergies:") }, "\(place): \(ids(q))")
        }
        XCTAssertEqual(events(read("NKDA, hypotension after induction", .intraop)), ["event:hypotension after induction"])
        // Anaphylaxis in the case: with what it followed on either place, "to" a drug on the Intraoperative tab only.
        XCTAssertEqual(events(read("anaphylaxis after cefazolin", .intraop)), ["event:anaphylaxis after cefazolin"])
        XCTAssertEqual(events(read("anaphylaxis to rocuronium", .intraop)), ["event:anaphylaxis to rocuronium"])
        XCTAssertEqual(events(summary("anaphylaxis to rocuronium")), [], "on Summary & Handoff it may be the history's")
    }

    /// A piece that says it is history (hx, h/o, family history, a past year, a home medicine, "orthostatic") is never an
    /// event, on the Intraoperative tab either: it is set aside for the Preop tab as it was in 1.10.
    func testHistoryMarkersAreNeverEvents() {
        assertNoEvent(["hx MH", "family history of MH", "bleeding on warfarin", "h/o GI bleeding 2020", "hx of cardiac arrest 2019",
                       "pulmonary embolism 2019 on apixaban", "orthostatic hypotension", "bradycardia on metoprolol", "HTN, DM, AF on apixaban",
                       "seizure 2019", "PONV, aspiration risk", "ischemia on stress test", "bronchospasm last case",
                       "hypotension after induction in pt with known AF"])

        for s in ["hx MH", "family history of MH"] {
            let q = summary(s)
            XCTAssertEqual(change(q, "anesthesia:mh"), .anesthesiaHistory("mh"), "\(s): \(ids(q))")
            let intraop = read(s, .intraop)
            XCTAssertTrue(intraop.skipped.contains(QuickAdd.historyElsewhere), s)
            XCTAssertEqual(applied(intraop).events, "", s)
        }
        let warfarin = summary("bleeding on warfarin")
        XCTAssertNotNil(applied(warfarin).hx.anticoagulants["warfarin"], "\(ids(warfarin))")
        XCTAssertEqual(applied(warfarin).events, "")
        XCTAssertTrue(read("bleeding on warfarin", .intraop).skipped.contains(QuickAdd.historyElsewhere))
        let gi = summary("h/o GI bleeding 2020")
        XCTAssertTrue(ids(gi).contains("problem:gi-bleed"), "\(ids(gi))")
        XCTAssertTrue(read("h/o GI bleeding 2020", .intraop).skipped.contains(QuickAdd.historyElsewhere))
        let list = summary("HTN, DM, AF on apixaban")
        for id in ["problem:htn", "problem:dm", "problem:af"] { XCTAssertTrue(ids(list).contains(id), "\(id): \(ids(list))") }
        XCTAssertTrue(ids(summary("seizure 2019")).contains("problem:seizure"))

        XCTAssertFalse(QuickAdd.isEvent("hx MH", lead: "", strict: false))
        XCTAssertFalse(QuickAdd.isEvent("bradycardia on metoprolol", lead: "", strict: false), "a medicine the patient takes")
        XCTAssertFalse(QuickAdd.isEvent("orthostatic hypotension", lead: "", strict: false))
        XCTAssertFalse(QuickAdd.isEvent("bleeding 2000", lead: "", strict: false), "a year")
        XCTAssertTrue(QuickAdd.isEvent("bleeding EBL 2000", lead: "", strict: false), "a volume, not a year")

        // History and an event on one line: each to its reader, across a comma, a full stop or a line break.
        let mixed = summary("hx seizures, bradycardia on emergence")
        XCTAssertEqual(events(mixed), ["event:bradycardia on emergence"])
        XCTAssertTrue(ids(mixed).contains("problem:seizure"), "\(ids(mixed))")
        let sentences = summary("hx MH. Hypotension after induction")
        XCTAssertEqual(events(sentences), ["event:hypotension after induction"], "\(ids(sentences))")
        XCTAssertTrue(ids(sentences).contains("anesthesia:mh"), "\(ids(sentences))")
        XCTAssertEqual(events(read("hx MH. Hypotension after induction", .intraop)), ["event:hypotension after induction"])
        let lines = summary("HTN\nhypotension after induction")
        XCTAssertEqual(events(lines), ["event:hypotension after induction"], "\(ids(lines))")
        XCTAssertTrue(ids(lines).contains("problem:htn"), "\(ids(lines))")
        XCTAssertEqual(events(read("no hypotension. Bronchospasm on emergence", .intraop)), ["event:bronchospasm on emergence"], "the negation ends with its sentence")
    }

    /// A point of the case with a past year, or in a clinic, is a past case or a visit: left to the history.
    func testAPastCaseIsNotThisCase() {
        assertNoEvent(["laryngospasm after extubation in 2015", "MH after induction 1998", "bronchospasm with intubation 2018",
                       "hypertension on arrival to clinic"])
        for (place, q) in bothPlaces("laryngospasm after extubation in 2015") {
            XCTAssertNil(finding(q, "airway-end"), "\(place): nor is the airway at handoff")
            XCTAssertEqual(applied(q).events, "", place)
        }
        XCTAssertEqual(change(summary("MH after induction 1998"), "anesthesia:mh"), .anesthesiaHistory("mh"))
        XCTAssertTrue(ids(summary("hypertension on arrival to clinic")).contains("problem:htn"))
        XCTAssertFalse(QuickAdd.isEvent("laryngospasm after extubation in 2015", lead: "", strict: false))

        // Without the year it is this case, worded as typed though the airway reader takes "extubation" for itself.
        for (place, q) in bothPlaces("laryngospasm after extubation") {
            XCTAssertEqual(events(q), ["event:laryngospasm after extubation"], place)
            XCTAssertEqual(change(q, "airway-end"), .airwayAtEnd("extubated"), place)
        }
        for (place, q) in bothPlaces("hypotensive on arrival") { XCTAssertEqual(events(q), ["event:hypotensive on arrival"], place) }
        for (place, q) in bothPlaces("hypotension prior to induction") { XCTAssertEqual(events(q), ["event:hypotension prior to induction"], place) }
        for (place, q) in bothPlaces("hypotension at 14:30") { XCTAssertTrue(events(q).contains { $0.hasPrefix("event:hypotension") }, place) }
        for (place, q) in bothPlaces("hypotension after induction, 2 units PRBC") { XCTAssertEqual(events(q), ["event:hypotension after induction"], place) }
    }

    /// A tracing's report is the ECG reader's ("ECG sinus brady"); a change at a point of the case is an event.
    func testATracingReportIsNotAnEvent() {
        assertNoEvent(["ECG sinus brady"])
        XCTAssertFalse(QuickAdd.isEvent("ECG sinus brady", lead: "", strict: false))
        XCTAssertTrue(QuickAdd.isEvent("ECG ST depression after induction", lead: "", strict: true))
        let q = read("ECG ST depression after induction", .intraop)
        XCTAssertTrue(events(q).contains { $0.hasSuffix("st depression after induction") }, "\(ids(q))")
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
        XCTAssertEqual(ids(q), ["ecg:Normal sinus rhythm", "ecg:Left bundle branch block", "cardiac:symptoms", "cardiac:acute", "stress"],
                       "in the order the line tells them")
        XCTAssertEqual(chipTexts(q), ["ECG · Normal sinus rhythm", "ECG · Left bundle branch block", "Cardiac · No symptoms", "Cardiac · No acute conditions",
                                      "Workup · DSE negative (2024)"], "each chip short enough for one line at 375 pt")
        XCTAssertEqual(q.unread, "")
        let r = applied(q)
        XCTAssertEqual(r.ecg, ["Normal sinus rhythm", "Left bundle branch block"])
        XCTAssertEqual(r.cardiacSymptomsAnswer, false)
        XCTAssertEqual(r.activeCardiacAnswer, false)
        XCTAssertEqual(r.stressTest.result, .negative)
        XCTAssertEqual(r.stressTest.date, PatientMonthYear(year: 2024))
        XCTAssertEqual(r.stressTest.summary, "Dobutamine stress test (2024): negative, no ischemia", "the record keeps its own wording; only the chip is short")
        XCTAssertEqual(PatientSummary.ecgText(r), "Normal sinus rhythm; Left bundle branch block")
    }

    // MARK: Review of the merged branch (1.11): one test per confirmed finding

    private func ecgs(_ q: QuickAddReading) -> Set<String> { Set(ids(q).filter { $0.hasPrefix("ecg:") }) }

    /// A negation or a drug said before the extubation in the same piece is not about the extubation.
    func testExtubatedAfterOtherWordsInItsPiece() {
        for line in ["weaned off norepi and extubated, to ICU", "sevo off and extubated awake", "No events. Extubated to PACU", "no issues extubated, to PACU"] {
            XCTAssertEqual(change(read(line, .intraop), "airway-end"), .airwayAtEnd("extubated"), line)
        }
        XCTAssertEqual(change(read("weaned off norepi and extubated, to ICU", .intraop), "disposition"), .disposition("ICU"))
        XCTAssertEqual(change(read("not extubated, to ICU", .intraop), "airway-end"), .airwayAtEnd("intubated"), "its own negation still counts")
    }

    /// An extubation that is planned, deferred or delayed has not happened: nothing is filed as extubated.
    func testAPlannedOrDeferredExtubationIsNotExtubated() {
        for line in ["plan extubation in ICU", "extubation deferred, to ICU intubated", "extubation criteria not met, to ICU", "delayed extubation, to ICU on propofol"] {
            XCTAssertNotEqual(change(read(line, .intraop), "airway-end"), .airwayAtEnd("extubated"), line)
            XCTAssertNotEqual(change(summary(line), "airway-end"), .airwayAtEnd("extubated"), line)
        }
        XCTAssertEqual(change(read("extubation criteria not met, to ICU", .intraop), "disposition"), .disposition("ICU"))
    }

    /// "Not reintubated" and a failed extubation told as history do not make the patient intubated; an origin is not
    /// the end of the case.
    func testReintubationDeniedAndIntubatedOrigins() {
        for line in ["laryngospasm after extubation, not reintubated", "extubated, did not need to be reintubated", "hx failed extubation 2019, extubated awake"] {
            XCTAssertEqual(change(read(line, .intraop), "airway-end"), .airwayAtEnd("extubated"), line)
        }
        XCTAssertNil(change(read("transferred intubated from OSH", .intraop), "airway-end"))
        XCTAssertNil(change(read("intubated on arrival", .intraop), "airway-end"))
        XCTAssertEqual(change(read("failed extubation, reintubated", .intraop), "airway-end"), .airwayAtEnd("intubated"))
    }

    /// "Intubated to ICU" is the airway at handoff and the disposition.
    func testIntubatedToICU() {
        let q = read("intubated to ICU on propofol", .intraop)
        XCTAssertEqual(change(q, "airway-end"), .airwayAtEnd("intubated"), "\(ids(q))")
        XCTAssertEqual(change(q, "disposition"), .disposition("ICU"))
        let s = summary("left intubated to ICU")
        XCTAssertEqual(change(s, "airway-end"), .airwayAtEnd("intubated"))
        XCTAssertEqual(change(s, "disposition"), .disposition("ICU"))
        XCTAssertEqual(s.unread, "")
    }

    /// A place the patient is not going to is not the disposition; on the Preoperative bar a place is one only with a
    /// planning word, so where the patient was admitted is not where they go after the case.
    func testDispositionDeniedAndWhereThePatientCameFrom() {
        XCTAssertEqual(change(read("not going to ICU, to floor", .intraop), "disposition"), .disposition("Ward"))
        XCTAssertEqual(change(read("did not go to ICU, to PACU", .intraop), "disposition"), .disposition("PACU"))
        XCTAssertEqual(change(read("to PACU overnight", .intraop), "disposition"), .disposition("PACU"))
        for line in ["admitted to ICU with septic shock, for ex lap", "admitted to floor with SBO", "transferred from OSH to ICU"] {
            XCTAssertNil(change(read(line), "disposition"), line)
        }
        XCTAssertEqual(change(read("plan ICU postop"), "disposition"), .disposition("ICU"), "a plan on the Preoperative bar")
    }

    /// DDD, RAD, LVH and a bare "sinus" are ECG findings only in the ECG's own run of findings.
    func testAmbiguousLettersNeedTheECGRun() {
        XCTAssertEqual(ecgs(read("62F for L4-5 fusion, DDD, HTN, EKG NSR")), ["ecg:Normal sinus rhythm"], "degenerative disc disease is not a pacing mode")
        XCTAssertEqual(ecgs(read("ECG NSR, RAD on albuterol")), ["ecg:Normal sinus rhythm"], "reactive airway disease")
        XCTAssertEqual(ecgs(read("EKG NSR, echo LVH EF 55%")), ["ecg:Normal sinus rhythm"], "the echo's LVH")
        XCTAssertEqual(ecgs(read("ECG LBBB, for excision of pilonidal sinus")), ["ecg:Left bundle branch block"])
        XCTAssertEqual(ecgs(read("EKG LVH on echo")), [])
        XCTAssertEqual(ecgs(read("EKG: NSR, rate 72, LVH")), ["ecg:Normal sinus rhythm", "ecg:Left ventricular hypertrophy"], "still read in the run")
        XCTAssertEqual(ecgs(read("ECG: AF, RAD")), ["ecg:Atrial fibrillation", "ecg:Right axis deviation"])
        XCTAssertEqual(ecgs(read("ECG DDD paced")), ["ecg:Paced rhythm (AV)"], "one pacing finding, not two")
    }

    /// A negation in the sentence before the ECG does not deny its findings.
    func testANegationBeforeTheECGIsNotTheECGs() {
        for line in ["No CP or SOB. ECG NSR LBBB", "denies chest pain ECG NSR LBBB"] {
            XCTAssertEqual(ecgs(read(line)), ["ecg:Normal sinus rhythm", "ecg:Left bundle branch block"], line)
        }
    }

    /// A scan that is not of the heart is not a stress test.
    func testOtherScansAreNotStressTests() {
        for line in ["sestamibi scan positive for R inferior parathyroid adenoma", "V/Q perfusion scan negative for PE", "quantitative perfusion scan R 40%"] {
            XCTAssertNil(change(read(line), "stress"), line)
        }
        XCTAssertEqual(stress(read("sestamibi stress test negative"))?.result, .negative)
        XCTAssertEqual(stress(read("myocardial perfusion scan negative"))?.kind, .other)
    }

    /// A negation or a plan beside the test is not "no stress test" or "not done".
    func testAStressTestBesideOtherNegationsAndPlans() {
        for line in ["denies CP/SOB. DSE negative 2024", "DSE negative prior to planned AAA repair", "DSE negative cardiology recommends proceeding",
                     "DSE negative (unable to do treadmill)"] {
            XCTAssertEqual(stress(read(line))?.kind, .dobutamine, line)
            XCTAssertEqual(stress(read(line))?.result, .negative, line)
        }
        XCTAssertEqual(stress(read("denies CP/SOB. DSE negative 2024"))?.date, PatientMonthYear(year: 2024))
        XCTAssertEqual(stress(read("no CP and stress test negative 2023"))?.result, .negative)
        XCTAssertEqual(stress(read("no ischemia on stress test 2023"))?.result, .negative)
        XCTAssertEqual(stress(read("no ischemia on stress test 2023"))?.date, PatientMonthYear(year: 2023))
    }

    /// The test takes its own date, not the date of the operation told before it.
    func testAStressTestTakesItsOwnDate() {
        let cabg = read("CABG 2015 DSE 2023 negative")
        XCTAssertEqual(stress(cabg)?.date, PatientMonthYear(year: 2023))
        XCTAssertEqual(stress(cabg)?.result, .negative)
        let pci = read("PCI 2019 stress test 2024 negative")
        XCTAssertEqual(stress(pci)?.date, PatientMonthYear(year: 2024))
        XCTAssertEqual(stress(pci)?.result, .negative)
    }

    /// A different test typed over a recorded one replaces it whole: the old findings are not kept under the new result.
    func testADifferentStressTestReplacesTheOldOne() {
        var r = PatientRecord()
        r.stressTest = PatientStressTest(kind: .exercise, result: .positive, findings: "2 mm ST depression at stage 3")
        r.stressTest.date = PatientMonthYear(year: 2019)
        let after = applied(read("DSE negative 03/2025"), to: r)
        XCTAssertEqual(after.stressTest.kind, .dobutamine)
        XCTAssertEqual(after.stressTest.result, .negative)
        XCTAssertEqual(after.stressTest.date, PatientMonthYear(month: 3, year: 2025))
        XCTAssertEqual(after.stressTest.findings, "", "the 2019 findings are not the 2025 test's")
    }

    /// "No new cardiac symptoms" says there are old ones: no answer is filed.
    func testNoNewCardiacSymptomsIsNotNone() {
        for line in ["stable angina, no new cardiac symptoms", "CHF, no further cardiac symptoms since diuresis"] {
            XCTAssertNil(change(read(line), "cardiac:symptoms"), line)
        }
        XCTAssertEqual(change(read("no active cardiac symptoms"), "cardiac:symptoms"), .cardiacAnswer("symptoms", false))
    }

    /// The patient's usual state and an event word after a diagnosis are history, on both places; the event's text
    /// never stops at "requiring".
    func testBaselineDiagnosisFirstAndEventWording() {
        XCTAssertTrue(QuickAdd.saidOfBaseline("baseline bradycardia"))
        XCTAssertTrue(QuickAdd.saidOfBaseline("baseline sinus brady"))
        XCTAssertFalse(QuickAdd.saidOfBaseline("hypotension 30% below baseline"))
        XCTAssertTrue(QuickAdd.leadsWithDiagnosis("asthma with bronchospasm"))
        XCTAssertFalse(QuickAdd.leadsWithDiagnosis("bronchospasm on emergence"))
        XCTAssertFalse(QuickAdd.leadsWithDiagnosis("transient hypotension"))
        assertNoEvent(["baseline bradycardia", "asthma with bronchospasm", "CKD with hyperkalemia", "tachy-brady syndrome",
                       "hypertensive urgency last month", "hypotension on midodrine", "bleeding ulcer"])
        XCTAssertEqual(events(read("bronchospasm on emergence", .intraop)), ["event:bronchospasm on emergence"], "still an event")
        XCTAssertTrue(events(read("asthma, bronchospasm after intubation", .intraop)).contains { $0.hasPrefix("event:bronchospasm after") }, "a diagnosis in another piece")

        XCTAssertEqual(QuickAdd.eventWording(seen: "hypotension requiring" + String(repeating: " ", count: 12), typed: "hypotension requiring norepi 0.05"),
                       "hypotension requiring norepi 0.05", "what another reader took after the connector is put back")
        XCTAssertEqual(QuickAdd.eventWording(seen: "hypotension requiring", typed: "hypotension requiring"), "hypotension")
        XCTAssertEqual(QuickAdd.eventWording(seen: "hypotension and then", typed: "hypotension and then"), "hypotension")
        XCTAssertEqual(QuickAdd.eventWording(seen: "bronchospasm on emergence", typed: "bronchospasm on emergence"), "bronchospasm on emergence")
        let q = read("hypotension requiring norepi 0.05", .intraop)
        XCTAssertFalse(events(q).contains { $0.hasSuffix("requiring") }, "\(events(q))")
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
