import XCTest
import UIKit
import SwiftUI
@testable import PeriopSignal

/// 1.12 follow-up, helper H (Ben, Nov 11): "Vancomycin not recognized in medications and interventions. Is recognized in case
/// timer." One place holds an antibiotic, Case Timers. (1) A drug picked in Case Timers is clearly logged: the button says
/// "Log dose", a line says it is not recorded yet, and leaving with a pick pending asks. (2) The quick-add bar on the
/// Intraoperative tab reads an antibiotic given in the case and logs it in Case Timers, the dose as typed. (3) The
/// Antibiotics page shows how to add one.
final class H112Tests: XCTestCase {

    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 9, minute: 30))! }

    private func at(_ hour: Int, _ minute: Int, day: Int = 11) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func timerData() throws -> CaseTimerData {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        return try XCTUnwrap(ReferenceLoader.decode(try Data(contentsOf: url)).caseTimers, "caseTimers decodes")
    }

    override func setUpWithError() throws {
        CaseAntibiotics.override = try timerData()
    }

    override func tearDown() {
        CaseAntibiotics.override = nil
    }

    private func adult(_ kg: Double = 82) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = kg
        return r
    }

    private func read(_ line: String, record: PatientRecord? = nil, tab: QuickAddTab = .intraop, at when: Date? = nil,
                      handoff: Bool = false) -> QuickAddReading {
        QuickAdd.read(line, record: record ?? adult(), tab: tab, now: when ?? now, handoff: handoff)
    }

    private func doses(_ q: QuickAddReading) -> [IntraopAntibioticDose] {
        q.findings.compactMap { f -> IntraopAntibioticDose? in
            if case .antibioticDose(let d) = f.change { return d }
            return nil
        }
    }

    private func dose(_ line: String, record: PatientRecord? = nil, at when: Date? = nil) throws -> IntraopAntibioticDose {
        let found = doses(read(line, record: record, at: when))
        XCTAssertEqual(found.count, 1, "\(line): \(found)")
        return try XCTUnwrap(found.first)
    }

    private func filed(_ line: String, into record: PatientRecord, at when: Date? = nil) -> PatientRecord {
        var r = record
        let q = read(line, record: record, at: when)
        PatientNote.apply(QuickAdd.changes(QuickAdd.chips(q, record: record)), to: &r)
        return r
    }

    // MARK: 1. Case Timers: a picked antibiotic is clearly logged

    func testTheButtonSaysLogDoseWhenNoPendingDrugHasARedoseInterval() {
        XCTAssertEqual(IntraopAntibiotic.buttonTitle(pending: true, anyInterval: false, onlyChanges: false), "Log dose")
        XCTAssertEqual(IntraopAntibiotic.buttonTitle(pending: true, anyInterval: false, onlyChanges: true), "Log dose",
                       "a pending drug wins over interval changes")
    }

    func testTheButtonSaysLogDoseAndStartTimerWhenAPendingDrugHasAnInterval() {
        XCTAssertEqual(IntraopAntibiotic.buttonTitle(pending: true, anyInterval: true, onlyChanges: false), "Log dose & start timer")
    }

    func testTheButtonKeepsUpdateTimerForIntervalChangesAndStartTimerWhenNothingIsPending() {
        XCTAssertEqual(IntraopAntibiotic.buttonTitle(pending: false, anyInterval: false, onlyChanges: true), "Update timer")
        XCTAssertEqual(IntraopAntibiotic.buttonTitle(pending: false, anyInterval: false, onlyChanges: false), "Start timer")
    }

    func testTheDefaultPickOfEachDrugDecidesTheButton() throws {
        let d = try timerData()
        func title(_ drug: String) throws -> String {
            let def = try XCTUnwrap(d.antibiotic(drug))
            let pick = RecurrencePick(minutes: CaseTimerRecurrence.antibioticDefault(def))
            return IntraopAntibiotic.buttonTitle(pending: true, anyInterval: (pick.minutes ?? 0) > 0, onlyChanges: false)
        }
        // Vancomycin, ceftriaxone, ertapenem, metronidazole, gentamicin, ciprofloxacin and levofloxacin have no routine redose:
        // nothing is selected and the button logs the dose only.
        for drug in ["vancomycin", "ceftriaxone", "ertapenem", "metronidazole", "gentamicin", "ciprofloxacin", "levofloxacin"] {
            XCTAssertEqual(try title(drug), "Log dose", drug)
        }
        for drug in ["cefazolin", "cefoxitin", "clindamycin"] {
            XCTAssertEqual(try title(drug), "Log dose & start timer", drug)
        }
    }

    func testTheAccessibilityHintMatchesTheButton() {
        XCTAssertEqual(IntraopAntibiotic.buttonHint(pending: true, anyInterval: true, onlyChanges: false),
                       "Logs the dose at the start time and starts the redose timer")
        XCTAssertTrue(IntraopAntibiotic.buttonHint(pending: true, anyInterval: false, onlyChanges: false).hasPrefix("Logs the dose at the start time."))
        XCTAssertFalse(IntraopAntibiotic.buttonHint(pending: true, anyInterval: false, onlyChanges: false).contains("starts the redose timer"),
                       "no interval, no timer started")
        XCTAssertEqual(IntraopAntibiotic.buttonHint(pending: false, anyInterval: false, onlyChanges: true), "Saves the new redose intervals")
    }

    func testAPendingDrugHasAQuietLineSayingItIsNotRecordedInTheButtonsWords() {
        XCTAssertEqual(IntraopAntibiotic.pendingNote(buttonTitle: "Log dose"), "Not recorded until you tap Log dose.")
        XCTAssertEqual(IntraopAntibiotic.pendingNote(buttonTitle: "Log dose & start timer"), "Not recorded until you tap Log dose & start timer.")
    }

    func testLeavingWithAPendingDrugAsksWhatItWouldLog() {
        XCTAssertEqual(IntraopAntibiotic.leaveTitle(names: ["Vancomycin"], at: "08:10"), "Log Vancomycin at 08:10?")
        XCTAssertEqual(IntraopAntibiotic.leaveTitle(names: ["Vancomycin", "Cefazolin"], at: "08:10"), "Log Vancomycin and Cefazolin at 08:10?")
        XCTAssertEqual(IntraopAntibiotic.leaveTitle(names: ["Cefazolin", "Vancomycin", "Gentamicin"], at: "08:10"),
                       "Log Cefazolin, Vancomycin and Gentamicin at 08:10?")
        XCTAssertEqual(IntraopAntibiotic.name("piperacillin-tazobactam", in: CaseAntibiotics.current), "Piperacillin–tazobactam")
    }

    func testTheTimerRowShowsATypedDoseOnlyWhereItSaysMoreThanTheComputedOne() {
        let typed = TimedEntry(time: at(8, 10), given: "1 g")
        XCTAssertEqual(IntraopAntibiotic.givenNote(last: typed, computed: "1,230 mg (15 mg/kg × 82 kg)"), "given: 1 g")
        XCTAssertNil(IntraopAntibiotic.givenNote(last: TimedEntry(time: at(8, 10), given: "2 g"), computed: "2 g"), "the same dose")
        XCTAssertNil(IntraopAntibiotic.givenNote(last: TimedEntry(time: at(8, 10), given: "15 MG/KG"), computed: "15 mg/kg"), "the same, in other case")
        XCTAssertNil(IntraopAntibiotic.givenNote(last: TimedEntry(time: at(8, 10)), computed: "2 g"), "a dose logged in Case Timers")
        XCTAssertNil(IntraopAntibiotic.givenNote(last: nil, computed: "2 g"))
        XCTAssertNil(IntraopAntibiotic.givenNote(last: TimedEntry(time: at(8, 10), given: "  "), computed: "2 g"))
    }

    // MARK: Saved records keep opening

    func testADoseSavedBeforeTheTypedDoseExistedStillDecodes() throws {
        let json = """
        {"antibiotics":[{"drug":"cefazolin","doses":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","time":790000000,"ebl":100}],"everyMinutes":240}]}
        """
        let t = try JSONDecoder().decode(CaseTimers.self, from: Data(json.utf8))
        XCTAssertEqual(t.antibiotics.count, 1)
        XCTAssertEqual(t.antibiotics[0].doses.count, 1)
        XCTAssertNil(t.antibiotics[0].doses[0].given)
        XCTAssertEqual(t.antibiotics[0].doses[0].ebl, 100)
        // And a 1.9 record with its one course under "antibiotic".
        let old = """
        {"antibiotic":{"drug":"vancomycin","doses":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","time":790000000}]}}
        """
        XCTAssertEqual(try JSONDecoder().decode(CaseTimers.self, from: Data(old.utf8)).antibiotics.first?.doses.first?.given, nil)
    }

    func testATypedDoseSurvivesTheRecordsRoundTripAndAnUntypedOneWritesNoKey() throws {
        var r = adult()
        r.timers.antibiotics = [AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: at(8, 10), given: "1 g")]),
                                AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: at(8, 0))])]
        let data = try JSONEncoder().encode(r)
        let again = try JSONDecoder().decode(PatientRecord.self, from: data)
        XCTAssertEqual(again.timers.antibiotics[0].doses[0].given, "1 g")
        XCTAssertNil(again.timers.antibiotics[1].doses[0].given)
        let untyped = try JSONEncoder().encode(TimedEntry(time: at(8, 0)))
        XCTAssertFalse(String(decoding: untyped, as: UTF8.self).contains("given"), "nothing written for a dose logged in Case Timers")
    }

    // MARK: 2. The bar reads an antibiotic given in the case

    func testVancAndADoseIsADoseLoggedInCaseTimersAtNow() throws {
        let q = read("vanc 1 g")
        let d = try dose("vanc 1 g")
        XCTAssertEqual(d, IntraopAntibioticDose(drug: "vancomycin", given: "1 g", time: now, redose: false))
        let f = try XCTUnwrap(q.findings.first)
        XCTAssertEqual(f.section, QuickAdd.intraop, "the Intraoperative group of the review")
        XCTAssertEqual(f.label, "Vancomycin 1 g: dose logged in Case Timers at 09:30")
        XCTAssertEqual(QuickAdd.chips(q, record: adult()).first?.text, "Intraop · Vancomycin 1 g: dose logged in Case Timers at 09:30")
        XCTAssertEqual(q.findings.count, 1, "nothing else is read from the line")
        XCTAssertTrue(q.unread.isEmpty, "nothing is left unread: \(q.unread)")
    }

    func testTheTimeIsReadInEveryWayItIsTyped() throws {
        for line in ["vanc 1 g at 0810", "vanc 1 g @ 08:10", "vanc 1 g at 8:10", "vanc 1 g 0810", "vanc 1 g 8:10", "vanc 1 g at 810",
                     "vanc 1 g at 08:10 am", "vanc 1 g @0810", "vancomycin 1 g (at 0810)"] {
            let d = try dose(line)
            XCTAssertEqual(d.time, at(8, 10), line)
            XCTAssertEqual(d.given, "1 g", line)
        }
        XCTAssertEqual(try dose("cefazolin 2 g at 8:10 pm", at: at(21, 0)).time, at(20, 10))
        XCTAssertEqual(try dose("0810 vanc 1 g").time, now, "a time before the name is not read: the dose is now")
    }

    func testAnImpossibleTimeFilesNothingInsteadOfGuessing() {
        for line in ["vanc 1 g at 2575", "vanc 1 g at 0899", "vanc 1 g at 25:00"] {
            XCTAssertTrue(doses(read(line)).isEmpty, line)
        }
    }

    func testATimeMoreThanTwelveHoursAheadWasYesterdayAsCaseTimersResolvesAStartTime() throws {
        // 09:00 now: 21:30 is 12.5 h ahead, so yesterday's.
        XCTAssertEqual(try dose("vanc 1 g at 2130", at: at(9, 0)).time, at(21, 30, day: 10))
        XCTAssertEqual(try dose("vanc 1 g at 0810", at: at(9, 0)).time, at(8, 10))
        XCTAssertEqual(IntraopAntibiotic.moment(hour: 21, minute: 30, now: at(9, 0)), at(21, 30, day: 10))
    }

    func testATypedDoseIsNeverInTheFuture() throws {
        // Late in the evening, this morning's dose is this morning's, not tomorrow's.
        XCTAssertEqual(try dose("vanc 1 g at 0810", at: at(23, 57)).time, at(8, 10))
        XCTAssertEqual(IntraopAntibiotic.moment(hour: 8, minute: 10, now: at(23, 57)), at(8, 10))
        XCTAssertEqual(IntraopAntibiotic.moment(hour: 0, minute: 5, now: at(23, 57)), at(0, 5), "earlier today, almost a day back")
        // A wall clock a little ahead of the phone: still just given.
        XCTAssertEqual(try dose("cefazolin 2 g at 0904", at: at(9, 0)).time, at(9, 4))
        XCTAssertEqual(IntraopAntibiotic.moment(hour: 9, minute: 5, now: at(9, 0)), at(9, 5))
        // Later today is a plan, not a dose given: nothing is filed.
        XCTAssertNil(IntraopAntibiotic.moment(hour: 9, minute: 30, now: at(9, 0)))
        XCTAssertNil(IntraopAntibiotic.moment(hour: 21, minute: 0, now: at(9, 0)), "exactly 12 h ahead is still later today")
        XCTAssertTrue(doses(read("vanc 1 g at 0930", at: at(9, 0))).isEmpty)
        XCTAssertTrue(doses(read("cefazolin 2 g at 1400", at: at(9, 0))).isEmpty)
        // No dose a line files is ever after now plus the grace.
        for h in 0..<24 {
            for now in [at(0, 20), at(9, 0), at(15, 45), at(23, 57)] {
                if let t = IntraopAntibiotic.moment(hour: h, minute: 10, now: now) {
                    XCTAssertLessThanOrEqual(t.timeIntervalSince(now), IntraopAntibiotic.clockGrace, "\(h):10 at \(now)")
                    XCTAssertGreaterThan(t.timeIntervalSince(now), -24 * 3600)
                }
            }
        }
    }

    func testTheNamesAreCaseTimersListAndTheCatalogsBrandsAndShortForms() throws {
        let d = try timerData()
        // Every drug of Case Timers' list by its own name and id.
        for def in d.antibiotics {
            XCTAssertEqual(IntraopAntibiotic.drug(named: def.name, in: d), def.id, def.name)
            XCTAssertEqual(IntraopAntibiotic.drug(named: def.id, in: d), def.id, def.id)
        }
        let known: [(String, String)] = [
            ("ancef", "cefazolin"), ("kefzol", "cefazolin"), ("vanc", "vancomycin"), ("vanco", "vancomycin"), ("vancocin", "vancomycin"),
            ("zosyn", "piperacillin-tazobactam"), ("pip-tazo", "piperacillin-tazobactam"), ("unasyn", "ampicillin-sulbactam"),
            ("flagyl", "metronidazole"), ("cipro", "ciprofloxacin"), ("levaquin", "levofloxacin"), ("cleocin", "clindamycin"),
            ("clinda", "clindamycin"), ("rocephin", "ceftriaxone"), ("invanz", "ertapenem"), ("azactam", "aztreonam"),
            ("gent", "gentamicin"), ("garamycin", "gentamicin"), ("mefoxin", "cefoxitin"), ("cefotan", "cefotetan"), ("zinacef", "cefuroxime"),
        ]
        for (word, drug) in known {
            XCTAssertEqual(try dose("\(word) 1 g").drug, drug, word)
        }
        XCTAssertEqual(try dose("ampicillin sulbactam 3 g").drug, "ampicillin-sulbactam")
        XCTAssertEqual(try dose("ampicillin 2 g").drug, "ampicillin", "the longer name wins only when it is written")
        XCTAssertEqual(try dose("pip tazo 3.375 g").drug, "piperacillin-tazobactam")
    }

    func testOnlyWholeWordsAndUnambiguousNamesAreRead() {
        for line in ["gentle traction 1 g", "amp 1 g", "1 amp", "ampule of bicarb", "gentamicinlike 1 g", "vancouver 1 g", "ancefs 2 g", "levo 0.1",
                     "metro 500", "cef 2 g"] {
            XCTAssertTrue(doses(read(line)).isEmpty, line)
        }
    }

    func testTheDoseIsKeptAsTypedNeverComputedOrConverted() throws {
        for (line, typed) in [("vanc 1 g", "1 g"), ("vanc 2g", "2g"), ("vancomycin 1500 mg", "1500 mg"), ("vancomycin 1,500 mg", "1,500 mg"),
                              ("vanc 15 mg/kg", "15 mg/kg"), ("clinda 900mg", "900mg"), ("vanc 1 gm", "1 gm"), ("ancef 1.5 g", "1.5 g")] {
            XCTAssertEqual(try dose(line).given, typed, line)
        }
        XCTAssertNil(try dose("vanc").given, "no dose typed, none made up")
        XCTAssertNil(try dose("vanc at 0810").given)
        XCTAssertEqual(try dose("2 g cefazolin").given, "2 g", "a dose that opens the clause")
        XCTAssertEqual(try dose("gave vanc 1 g iv").given, "1 g")
    }

    func testRedoseBeforeOrAfterTheNameMeansADoseAtThatTime() throws {
        for line in ["redose cefazolin at 1205", "cefazolin redose at 1205", "cefazolin redosed 1205", "re-dose cefazolin @ 12:05",
                     "cefazolin at 1205 redose", "Redosed cefazolin 2 g at 1205"] {
            let d = try dose(line, at: at(13, 0))
            XCTAssertTrue(d.redose, line)
            XCTAssertEqual(d.time, at(12, 5), line)
            XCTAssertEqual(d.drug, "cefazolin", line)
        }
        XCTAssertFalse(try dose("cefazolin 2 g").redose)
    }

    func testSeveralAntibioticsInOneLineEachKeepTheirOwnDoseAndTime() {
        let found = doses(read("cefazolin 2 g at 0810, vanc 1 g at 0815 and gent 5 mg/kg"))
        XCTAssertEqual(found.map(\.drug), ["cefazolin", "vancomycin", "gentamicin"])
        XCTAssertEqual(found.map(\.given), ["2 g", "1 g", "5 mg/kg"])
        XCTAssertEqual(found.map(\.time), [at(8, 10), at(8, 15), now])
        let two = doses(read("cefazolin 2 g vanc 1 g"))
        XCTAssertEqual(two.map(\.drug), ["cefazolin", "vancomycin"])
        XCTAssertEqual(two.map(\.given), ["2 g", "1 g"], "each dose goes with the name it follows")
    }

    func testTheLineAroundTheAntibioticIsStillRead() throws {
        let q = read("norepi 0.05, vanc 1 g at 0810, PRBC 2, EBL 500")
        XCTAssertEqual(doses(q).count, 1)
        XCTAssertTrue(q.findings.contains { if case .intraopInfusion("norepinephrine", _) = $0.change { return true } else { return false } })
        XCTAssertTrue(q.findings.contains { if case .blood("prbc", 2) = $0.change { return true } else { return false } })
        XCTAssertTrue(q.findings.contains { if case .blood("ebl", 500) = $0.change { return true } else { return false } })
    }

    // MARK: The guards

    func testAnAllergyOrAReactionIsNotADose() {
        for line in ["allergic to vancomycin", "anaphylaxis after cefazolin", "PCN allergy", "vanc allergy", "red man with vanc",
                     "rash after vancomycin", "cefazolin reaction", "hives after ancef", "allergies: vancomycin (rash)"] {
            XCTAssertTrue(doses(read(line)).isEmpty, line)
        }
        // The event reader still has "hypotension after vancomycin": the antibiotic reader leaves it alone.
        let q = read("hypotension after vancomycin")
        XCTAssertTrue(doses(q).isEmpty)
        XCTAssertTrue(q.findings.contains { if case .event = $0.change { return true } else { return false } }, "still an event")
    }

    func testALevelOrALabIsNotADose() {
        for line in ["vanc level 18", "vanc trough 14.2", "vancomycin 18 mcg/mL", "vanc random 20", "vancomycin peak 35", "vanc AUC 450"] {
            XCTAssertTrue(doses(read(line)).isEmpty, line)
        }
    }

    func testAResistanceIsNotADose() {
        for line in ["VRE", "vancomycin-resistant enterococcus", "MRSA", "VRE positive, vancomycin resistant", "MRSA, on vanc"] {
            XCTAssertTrue(doses(read(line)).isEmpty, line)
        }
    }

    func testAHomeOrPreoperativeMedicineIsNotADose() {
        for line in ["on vancomycin for endocarditis", "home meds: cipro", "pt on vanc", "taking cipro", "vancomycin 1 g q12h", "cipro 500 bid",
                     "cefazolin pta", "chronic vancomycin", "preop cefazolin"] {
            XCTAssertTrue(doses(read(line)).isEmpty, line)
        }
        // On the Preprocedure tab and on Summary & Handoff, which read as it does, nothing in the case is filed at all.
        for line in ["on vancomycin for endocarditis", "home meds: cipro", "vanc 1 g", "vanc 1 g at 0810"] {
            XCTAssertTrue(doses(read(line, tab: .preop)).isEmpty, "preop: " + line)
            XCTAssertTrue(doses(read(line, tab: .preop, handoff: true)).isEmpty, "handoff: " + line)
        }
    }

    func testANegationFilesNothing() {
        for line in ["no antibiotics", "vanc held", "cefazolin not given", "no vanc", "vanc withheld", "cefazolin d/c'd", "stopped vanc",
                     "vanc not needed", "without vanc", "cefazolin omitted", "denies vanc"] {
            XCTAssertTrue(doses(read(line)).isEmpty, line)
        }
    }

    func testAPlanFilesNothing() {
        for line in ["will give vanc", "vanc due at 1400", "plan vanc 1 g", "need to redose cefazolin", "cefazolin redose due 1205", "vanc to be given",
                     "going to give cefazolin", "next vanc at 1400", "ask for vanc 1 g", "vanc ordered", "should we give vanc?", "if bleeding redose ancef"] {
            XCTAssertTrue(doses(read(line)).isEmpty, line)
        }
    }

    func testVancAndADoseIsNotADripAndAnInfusionIsNotADose() {
        let drip = read("vanc 1 g")
        XCTAssertFalse(drip.findings.contains { if case .intraopInfusion = $0.change { return true } else { return false } }, "not a drip")
        XCTAssertFalse(drip.findings.contains { if case .infusion = $0.change { return true } else { return false } })
        for line in ["vancomycin infusion running", "vanc gtt", "vancomycin drip at 50", "vanc continuous"] {
            XCTAssertTrue(doses(read(line)).isEmpty, line)
        }
    }

    func testAUseThatIsNotAnIntravenousDoseIsNotOne() {
        for line in ["vancomycin powder 1 g in the wound", "gent irrigation", "vanc paste", "antibiotic cement with gent", "topical vanc"] {
            XCTAssertTrue(doses(read(line)).isEmpty, line)
        }
    }

    // MARK: Filing: what Case Timers' own Start and "Redose given" do

    func testADrugNotInCaseTimersStartsACourseLikeItsOwnStartWithTheDefaultPick() throws {
        var base = adult()
        base.fluids["ebl"] = 300
        let r = filed("vanc 1 g at 0810", into: base)
        let c = try XCTUnwrap(r.timers.course("vancomycin"))
        XCTAssertEqual(r.timers.antibiotics.count, 1)
        XCTAssertNil(c.everyMinutes, "the drug's sourced interval, none for a drug without one")
        XCTAssertEqual(c.doses.count, 1)
        XCTAssertEqual(c.doses[0].time, at(8, 10))
        XCTAssertEqual(c.doses[0].ebl, 300, "the blood loss at the time, for the 1,500 mL rule")
        XCTAssertEqual(c.doses[0].given, "1 g")
    }

    func testADoseOfACourseThatExistsIsAppendedAndTheSnoozesOfItsRemindersAreCleared() throws {
        var base = adult()
        base.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: at(8, 0), ebl: 0)])]
        base.timers.snoozes["antibiotic.cefazolin"] = ReminderSnooze(due: at(12, 0), until: at(12, 30))
        base.timers.snoozes["bloodLoss.cefazolin"] = ReminderSnooze(due: nil, until: .distantFuture)
        base.timers.snoozes["act"] = ReminderSnooze(due: at(12, 0), until: at(12, 30))
        let r = filed("redose cefazolin at 1205", into: base, at: at(12, 6))
        let c = try XCTUnwrap(r.timers.course("cefazolin"))
        XCTAssertEqual(c.doses.map(\.time), [at(8, 0), at(12, 5)])
        XCTAssertNil(c.doses[0].given)
        XCTAssertNil(c.doses[1].given, "no dose typed")
        XCTAssertNil(r.timers.snoozes["antibiotic.cefazolin"])
        XCTAssertNil(r.timers.snoozes["bloodLoss.cefazolin"])
        XCTAssertNotNil(r.timers.snoozes["act"], "only the antibiotic's own reminders")
        XCTAssertEqual(r.timers.antibiotics.count, 1)
    }

    func testTypingTheSameLineTwiceFilesOneDose() throws {
        let first = filed("vanc 1 g at 0810", into: adult())
        XCTAssertEqual(first.timers.course("vancomycin")?.doses.count, 1)
        // The review reads it as already recorded and offers nothing.
        let q = read("vanc 1 g at 0810", record: first)
        let chips = QuickAdd.chips(q, record: first)
        XCTAssertEqual(chips.first?.status, .recorded)
        XCTAssertEqual(chips.first?.statusText, "already recorded")
        XCTAssertTrue(QuickAdd.changes(chips).isEmpty)
        // Without a time, a second line within two minutes is the same dose.
        let a = filed("vanc 1 g", into: adult(), at: now)
        XCTAssertEqual(QuickAdd.chips(read("vanc 1 g", record: a, at: now.addingTimeInterval(90)), record: a).first?.status, .recorded)
        // Applying the same change twice does not double it either.
        var r = a
        PatientNote.apply([.antibioticDose(IntraopAntibioticDose(drug: "vancomycin", given: "1 g", time: now.addingTimeInterval(60), redose: false))], to: &r)
        XCTAssertEqual(r.timers.course("vancomycin")?.doses.count, 1)
    }

    func testADoseMoreThanTwoMinutesAwayIsAnotherDose() throws {
        let a = filed("vanc 1 g at 0810", into: adult())
        XCTAssertEqual(QuickAdd.chips(read("vanc 1 g at 0812", record: a), record: a).first?.status, .recorded, "two minutes is the same dose")
        let q = read("vanc 1 g at 0813", record: a)
        XCTAssertEqual(QuickAdd.chips(q, record: a).first?.status, .new)
        let b = filed("vanc 1 g at 0813", into: a)
        XCTAssertEqual(b.timers.course("vancomycin")?.doses.count, 2)
    }

    func testTheReviewsChipIsTheSameFromOneMinuteToTheNext() throws {
        let a = QuickAdd.chips(read("vanc 1 g", at: at(9, 30)), record: adult())
        let b = QuickAdd.chips(read("vanc 1 g", at: at(9, 31)), record: adult())
        XCTAssertEqual(a.map(\.id), b.map(\.id), "Add re-reads the line a minute later and must find the chip it showed")
        XCTAssertNotEqual(a.map(\.text), b.map(\.text), "but the label says the time it will be filed at")
        let other = QuickAdd.chips(read("vanc 1 g at 0810"), record: adult())
        XCTAssertNotEqual(a.map(\.id), other.map(\.id))
        XCTAssertNotEqual(QuickAdd.chips(read("vanc 1 g"), record: adult()).map(\.id), QuickAdd.chips(read("vanc 1.5 g"), record: adult()).map(\.id))
    }

    @MainActor func testOneUndoStepRemovesExactlyWhatTheLineAdded() throws {
        let store = PatientStore(url: nil)
        store.update(discrete: true, now: Date(timeIntervalSince1970: 1000)) { $0.weightKg = 82; $0.fluids["ebl"] = 100 }
        let before = store.record
        let q = read("vanc 1 g at 0810, cefazolin 2 g at 0805", record: before)
        let chosen = QuickAdd.chips(q, record: before)
        XCTAssertEqual(chosen.count, 2)
        store.update(discrete: true, now: Date(timeIntervalSince1970: 1000.3)) { PatientNote.apply(QuickAdd.changes(chosen), to: &$0) }
        let after = store.record
        XCTAssertEqual(Set(after.timers.antibiotics.map(\.drug)), ["cefazolin", "vancomycin"])
        XCTAssertEqual(after.timers.antibiotics.count, 2)
        XCTAssertTrue(store.isLatestStep(before: before, after: after), "the snackbar offers Undo")
        store.undo()
        XCTAssertEqual(store.record, before, "the record exactly as it was")
        XCTAssertTrue(store.record.timers.antibiotics.isEmpty)
    }

    func testTheBloodLossOnTheSameLineIsTheBloodLossTheDoseIsGivenAt() throws {
        let r = filed("EBL 800, vanc 1 g", into: adult())
        XCTAssertEqual(r.fluids["ebl"], 800)
        XCTAssertEqual(r.timers.course("vancomycin")?.doses.first?.ebl, 800)
    }

    func testTheRemindersRunFromAFiledDose() throws {
        let d = try timerData()
        let r = filed("cefazolin 2 g at 0810, vanc 1 g at 0815", into: adult(), at: at(9, 0))
        let rem = CaseTimerEngine.reminders(r.timers, record: r, data: d)
        XCTAssertEqual(rem.first { $0.id == "antibiotic.cefazolin" }?.due, at(12, 10), "four hours from the dose")
        XCTAssertNil(rem.first { $0.id == "antibiotic.vancomycin" }, "no routine redose")
        XCTAssertEqual(rem.first { $0.id == "longCase.vancomycin" }?.due, at(16, 15), "the long-case reminder, as for a dose logged in Case Timers")
    }

    // MARK: The review's words

    func testTheLabelSaysExactlyWhatWillHappen() throws {
        let d = try timerData()
        XCTAssertEqual(try dose("vanc 1 g at 0810"), IntraopAntibioticDose(drug: "vancomycin", given: "1 g", time: at(8, 10), redose: false))
        XCTAssertEqual(IntraopAntibiotic.label(try dose("vanc 1 g at 0810"), record: adult(), data: d, now: now),
                       "Vancomycin 1 g: dose logged in Case Timers at 08:10")
        // A drug with a sourced redose interval: the next dose is told.
        XCTAssertEqual(IntraopAntibiotic.label(try dose("cefazolin 2 g at 0810"), record: adult(), data: d, now: now),
                       "Cefazolin 2 g: dose logged in Case Timers at 08:10, next due 12:10")
        // A course that exists: a redose, and the interval Case Timers holds for it.
        var with = adult()
        with.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: at(8, 0))])]
        XCTAssertEqual(IntraopAntibiotic.label(try dose("redose cefazolin at 1205", at: at(13, 0)), record: with, data: d, now: at(13, 0)),
                       "Cefazolin: redose logged in Case Timers at 12:05, next due 16:05")
        with.timers.antibiotics[0].everyMinutes = 180
        XCTAssertEqual(IntraopAntibiotic.label(try dose("cefazolin at 1205", at: at(13, 0)), record: with, data: d, now: at(13, 0)),
                       "Cefazolin: redose logged in Case Timers at 12:05, next due 15:05")
        with.timers.antibiotics[0].everyMinutes = 0
        XCTAssertEqual(IntraopAntibiotic.label(try dose("cefazolin at 1205", at: at(13, 0)), record: with, data: d, now: at(13, 0)),
                       "Cefazolin: redose logged in Case Timers at 12:05", "the redose timer was stopped: no next dose")
        // Typed "redose" on a drug not yet in Case Timers is still told as a redose.
        XCTAssertEqual(IntraopAntibiotic.label(try dose("redose vanc 1 g at 0810"), record: adult(), data: d, now: now),
                       "Vancomycin 1 g: redose logged in Case Timers at 08:10")
    }

    func testTheLabelOfAChildsDoseSaysCaseTimersHasNoAntibioticDosesForAChild() throws {
        var child = PatientRecord()
        child.ageYears = 8; child.weightKg = 26
        let q = read("vanc 400 mg", record: child)
        let f = try XCTUnwrap(q.findings.first)
        XCTAssertEqual(f.note, "Adult defaults only: not for children. The dose is logged as typed.")
        XCTAssertNil(try XCTUnwrap(read("vanc 1 g").findings.first).note, "an adult's carries none")
        // And it is still the user's to accept: the chip can be added, as every finding can.
        XCTAssertTrue(QuickAdd.chips(q, record: child).first?.canAdd ?? false)
    }

    // MARK: What the Antibiotics page, the tab's row and the handoff say once it is filed

    func testTheTypedDoseOfTheLastDoseIsTheOneTold() throws {
        let d = try timerData()
        var r = adult()
        r.timers.antibiotics = [AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: at(8, 10), given: "1 g")])]
        let l = CaseAntibiotics.lines(r, data: d, now: at(8, 40))[0]
        XCTAssertEqual(l.dose, "1 g")
        XCTAssertEqual(l.tabText, "Vancomycin 1 g · last 08:10 · no routine redose")
        XCTAssertEqual(l.handoffText, "Vancomycin 1 g, last 08:10, no routine redose")
        // Without one the dose Case Timers computes, as before.
        r.timers.antibiotics = [AntibioticCourse(drug: "vancomycin", doses: [TimedEntry(time: at(8, 10))])]
        XCTAssertEqual(CaseAntibiotics.lines(r, data: d, now: at(8, 40))[0].dose, "1,230 mg (15 mg/kg × 82 kg)")
        // The LAST dose decides: an earlier typed dose is not shown over a later one logged in Case Timers.
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: at(8, 0), given: "1 g"), TimedEntry(time: at(12, 0))])]
        XCTAssertEqual(CaseAntibiotics.lines(r, data: d, now: at(12, 30))[0].dose, "2 g")
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: at(8, 0)), TimedEntry(time: at(12, 0), given: "1.5 g")])]
        XCTAssertEqual(CaseAntibiotics.lines(r, data: d, now: at(12, 30))[0].dose, "1.5 g")
    }

    func testTheRowOnTheTabAndTheHandoffCarryTheTypedDose() throws {
        let d = try timerData()
        var r = filed("vanc 1 g at 0810", into: adult(), at: at(8, 20))
        r.setProcedures(PlannedProcedure.parse("CABG x3"))
        let lines = IntraopNotableMedicationLink.lines(r, antibiotics: CaseAntibiotics.lines(r, data: d, now: at(8, 40)))
        XCTAssertEqual(lines.first?.text, "Vancomycin 1 g · last 08:10 · no routine redose")
        let blocks = PatientBriefs.handoff(r, now: at(8, 40))
        let b = try XCTUnwrap(blocks.first { $0.key == "infusions" })
        XCTAssertTrue(b.lines.contains("Antibiotics: Vancomycin 1 g, last 08:10, no routine redose"), "\(b.lines)")
    }

    // MARK: 3. The page shows how to add one

    func testTheGroupIsAlwaysThereWhileCaseTimersIsAndHiddenWhileEmptyWhenItIsNot() {
        XCTAssertTrue(IntraopAntibiotic.pageShowsGroup(hasAntibiotics: false, caseTimersShown: true))
        XCTAssertTrue(IntraopAntibiotic.pageShowsGroup(hasAntibiotics: true, caseTimersShown: true))
        XCTAssertTrue(IntraopAntibiotic.pageShowsGroup(hasAntibiotics: true, caseTimersShown: false), "what is charted shows either way")
        XCTAssertFalse(IntraopAntibiotic.pageShowsGroup(hasAntibiotics: false, caseTimersShown: false), "hidden while empty, as before")
    }

    func testTheLinkIsInTheAddGrammarAndRespectsTheDraftGate() {
        XCTAssertEqual(IntraopAntibiotic.noneCharted, "None charted")
        XCTAssertEqual(IntraopAntibiotic.pageLink(hasAntibiotics: false, caseTimersShown: true, child: false), "+ Antibiotic")
        XCTAssertEqual(IntraopAntibiotic.pageLink(hasAntibiotics: true, caseTimersShown: true, child: false), "+ Antibiotic or redose")
        XCTAssertNil(IntraopAntibiotic.pageLink(hasAntibiotics: false, caseTimersShown: false, child: false), "Case Timers hidden: no link")
        XCTAssertNil(IntraopAntibiotic.pageLink(hasAntibiotics: true, caseTimersShown: false, child: false))
        XCTAssertNil(IntraopAntibiotic.pageLink(hasAntibiotics: false, caseTimersShown: true, child: true), "a child has no antibiotic card in Case Timers")
    }

    @MainActor func testTheGroupsNoteSaysToTypeItInTheBar() {
        XCTAssertTrue(IntraopMedicationsPage.antibioticsNote.hasSuffix("Change them in Case Timers, or type it in the bar: vanc 1 g at 0810."),
                      IntraopMedicationsPage.antibioticsNote)
        // The example is one the bar reads.
        XCTAssertEqual(doses(read(IntraopAntibiotic.barExample)).first?.drug, "vancomycin")
        XCTAssertEqual(doses(read(IntraopAntibiotic.barExample)).first?.time, at(8, 10))
    }

    @MainActor func testTheLinkOpensCaseTimersAtItsAntibioticCard() {
        let ui = CaseTimersUI.shared
        ui.open = false; ui.target = nil
        ui.openAntibiotic()
        XCTAssertTrue(ui.open)
        XCTAssertEqual(ui.target, "antibiotic.card")
        XCTAssertEqual(CaseTimersView.antibioticCardID, "antibiotic.card")
        ui.open = false; ui.target = nil
    }

    // MARK: Nothing else about the doses changes

    func testNothingAboutCaseTimersDosesIntervalsOrTheBloodLossRuleChanged() throws {
        let d = try timerData()
        let def = try XCTUnwrap(d.antibiotic("cefazolin"))
        XCTAssertEqual(CaseTimerEngine.antibioticDose(def, record: adult(130)).text, "3 g")
        XCTAssertEqual(CaseTimerEngine.antibioticDose(def, record: adult(80)).text, "2 g")
        XCTAssertEqual(CaseTimerRecurrence.redoseMinutes(AntibioticCourse(drug: "cefazolin"), def: def), 240)
        var r = adult()
        r.fluids["ebl"] = 1600
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: at(8, 0), ebl: 0)])]
        XCTAssertNotNil(CaseTimerEngine.reminders(r.timers, record: r, data: d).first { $0.id == "bloodLoss.cefazolin" }, "the 1,500 mL rule")
        // markDone (Given in the running list) still appends a dose, with no typed dose, and clears the snoozes.
        var t = r.timers
        t.snoozes["antibiotic.cefazolin"] = ReminderSnooze(due: at(12, 0), until: at(12, 30))
        let rem = CaseReminder(kind: .antibiotic, title: "Cefazolin redose", detail: "", due: at(12, 0), ref: "cefazolin", snoozed: true)
        XCTAssertTrue(t.markDone(rem, now: at(12, 5), ebl: 1600))
        XCTAssertEqual(t.antibiotics[0].doses.count, 2)
        XCTAssertNil(t.antibiotics[0].doses[1].given)
        XCTAssertNil(t.snoozes["antibiotic.cefazolin"])
    }
}
