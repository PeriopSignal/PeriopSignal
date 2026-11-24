import XCTest
@testable import PeriopSignal

/// Ben, Nov 23 ("Yes, fix it now"): "Calculators clear and refill from the new case when the current case changes, and Save or Start
/// names the case it writes to." The rules are plain functions in CaseScope: which case and patient a tool is for (so another case,
/// an ended case, a cleared or received patient rebuild it and an edit of the same case does not), which tools are rebuilt, what the
/// fills give for two different cases and for an empty one, the captions that name the case with more than one case and say
/// nothing with one, and that a write goes to the case current at the tap. What only a screenshot shows: the tool on screen
/// before and after the switch (shots 1470-1489).
final class CaseSwitch115Tests: XCTestCase {
    private var bundleFile: ReferenceBundle!
    private var d: ProphylaxisData { bundleFile.prophylaxis! }

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        bundleFile = try ReferenceLoader.decode(try Data(contentsOf: url))
    }

    // MARK: Made-up cases

    /// A 67-year-old man, 92 kg, heart disease, CABG planned, a penicillin rash and a positive MRSA screen.
    private func heartCase() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = 92
        r.setProcedures(PlannedProcedure.parse("CABG x3"))
        r.problems = ["htn", "cad"]
        r.allergyList = AllergyCatalog.parse("PCN - rash")
        r.infections.results["mrsa"] = .positive
        return r
    }

    /// A 52-year-old woman, 64 kg, nothing else recorded: another weight, sex, age and no problems.
    private func womanCase() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 52; r.sex = .female; r.heightCm = 165; r.weightKg = 64
        r.smoking = "never"
        return r
    }

    /// An 8-year-old girl, 28 kg.
    private func childCase() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 8; r.sex = .female; r.heightCm = 128; r.weightKg = 28
        return r
    }

    @MainActor private func store(rooms: [String]) -> PatientStore {
        let s = PatientStore(url: nil)
        for (i, room) in rooms.enumerated() {
            if i == 0 { s.setRoom(room, phone: "") } else { s.addCase(room: room) }
        }
        return s
    }

    @MainActor private func identity(_ s: PatientStore) -> CaseIdentity {
        CaseScope.identity(of: s.book, patientEpoch: s.patientEpoch)
    }

    // MARK: Identity: the case, not its contents

    @MainActor func testEditingTheSameCaseDoesNotChangeItsIdentity() {
        let s = store(rooms: ["OR 4", "OR 9"])
        s.selectCase(s.cases[0].id)
        let before = identity(s)
        s.update { $0.weightKg = 95 }
        s.update(discrete: true) { $0.problems = ["htn"] }
        s.setRoom("OR 4A", phone: "")
        XCTAssertEqual(identity(s), before, "a weight, a problem or the room edited elsewhere does not reset an open tool")
        s.undo()
        XCTAssertEqual(identity(s), before, "nor does Undo of an edit")
    }

    @MainActor func testAnotherCaseBecomingCurrentChangesTheIdentity() {
        let s = store(rooms: ["OR 4", "OR 9"])
        s.selectCase(s.cases[0].id)
        let first = identity(s)
        s.selectCase(s.cases[1].id)
        let second = identity(s)
        XCTAssertNotEqual(first, second)
        s.selectCase(s.cases[0].id)
        XCTAssertEqual(identity(s), first, "the same case is the same identity")
    }

    @MainActor func testAddingACaseOpensItAndChangesTheIdentity() {
        let s = store(rooms: ["OR 4"])
        let before = identity(s)
        s.addCase(room: "OR 9")
        XCTAssertNotEqual(identity(s), before, "a new case becomes current")
    }

    @MainActor func testEndingTheCurrentCaseChangesTheIdentity() {
        let s = store(rooms: ["OR 4", "OR 9"])
        let before = identity(s)
        s.endCase(keepSummary: false)
        XCTAssertNotEqual(identity(s), before, "the next case becomes current")

        let alone = store(rooms: ["OR 4"])
        let only = identity(alone)
        alone.endCase(keepSummary: false)
        XCTAssertNotEqual(identity(alone), only, "ending the only case leaves a fresh Case 1: another patient")

        let next = store(rooms: ["OR 4", "OR 9"])
        let room = identity(next)
        next.endCase(keepSummary: false, nextInRoom: true)
        XCTAssertNotEqual(identity(next), room, "the next patient in the room")
    }

    @MainActor func testClearingOrReceivingAPatientChangesTheIdentityInPlace() {
        let s = store(rooms: ["OR 4"])
        s.update { $0 = self.heartCase() }
        let filled = identity(s)
        s.clear()
        let cleared = identity(s)
        XCTAssertNotEqual(cleared, filled, "a weight typed for the cleared patient must not dose the next one")
        XCTAssertEqual(cleared.caseID, filled.caseID, "the same case slot")
        s.undoClear()
        XCTAssertNotEqual(identity(s), cleared, "Undo brings the patient back: the tool fills for it again")

        let before = identity(s)
        s.receive(womanCase())
        XCTAssertNotEqual(identity(s), before, "a patient from a colleague replaces the patient")
        s.undoReceive()
        XCTAssertNotEqual(identity(s), before, "and so does the Undo")
    }

    // MARK: Which tools are rebuilt

    func testCalculatorsAreRebuiltAndRunningToolsAreNot() {
        let rebuilt: [RefRoute] = [.score("rcri"), .score("apfel"), .peds, .local, .infusions, .neuraxial, .fasting, .valves, .intervention,
                                   .ponv, .chamber, .diastolic, .abg, .tee, .mcs, .caseTimers, .prophylaxis]
        for r in rebuilt { XCTAssertTrue(CaseScope.resetsOnCaseChange(r), r.key) }
        // Ben, Nov 23: a running code or transfusion count must survive a switch.
        let kept: [RefRoute] = [.acls, .mtp, .airway, .obEmergency, .regionalFinder, .blocks, .neuraxialGuide, .quickref("asra-last"),
                                .folder(RefFolder.allCases[0])]
        for r in kept { XCTAssertFalse(CaseScope.resetsOnCaseChange(r), r.key) }
    }

    // MARK: Captions

    @MainActor func testOneCaseSaysNothingNew() {
        let s = store(rooms: ["OR 4"])
        XCTAssertFalse(CaseScope.showsName(s.book))
        XCTAssertEqual(CaseScope.fromCaption("From My Patient", in: s.book), "From My Patient", "the screens read as they always did")
        XCTAssertEqual(CaseScope.fromCaption("From the case", in: s.book), "From the case")
        XCTAssertNil(CaseScope.writeCaption("Saves to", in: s.book), "no caption with one case")
        XCTAssertEqual(CaseScope.source("My Patient", in: s.book), "My Patient")
        let engine = ProphylaxisEngine.captionLead + "Penicillin (rash)"
        XCTAssertEqual(CaseScope.named(engine, lead: ProphylaxisEngine.captionLead, in: s.book), engine)
    }

    @MainActor func testTwoCasesNameTheCurrentOneAsTheSwitcherDoes() {
        let s = store(rooms: ["OR 4", "OR 9"])
        s.selectCase(s.cases[0].id)
        XCTAssertTrue(CaseScope.showsName(s.book))
        XCTAssertEqual(CaseScope.name(s.book), "OR 4")
        XCTAssertEqual(CaseScope.fromCaption("From My Patient", in: s.book), "From OR 4")
        XCTAssertEqual(CaseScope.writeCaption("Saves to", in: s.book), "Saves to OR 4")
        XCTAssertEqual(CaseScope.writeCaption("Adds to", in: s.book), "Adds to OR 4")
        XCTAssertEqual(CaseScope.source("My Patient", in: s.book), "OR 4")

        s.selectCase(s.cases[1].id)
        XCTAssertEqual(CaseScope.writeCaption("Saves to", in: s.book), "Saves to OR 9", "the case current now")
        XCTAssertEqual(CaseScope.name(s.book), s.currentCase.label, "the same name the switcher's chip shows")
    }

    @MainActor func testACaseWithNoRoomIsNamedByItsNumber() {
        let s = store(rooms: ["OR 4"])
        s.addCase()   // no room: "Case 2"
        XCTAssertEqual(CaseScope.name(s.book), "Case 2")
        XCTAssertEqual(CaseScope.writeCaption("Saves to", in: s.book), "Saves to Case 2")
    }

    @MainActor func testTheProphylaxisCaptionsNameTheCaseOnlyAmongSeveral() {
        let s = store(rooms: ["OR 4", "OR 9"])
        s.selectCase(s.cases[0].id)
        let lead = ProphylaxisEngine.captionLead
        XCTAssertEqual(CaseScope.named(lead + "Penicillin (rash)", lead: lead, in: s.book), "From OR 4: Penicillin (rash)")
        XCTAssertEqual(CaseScope.named(lead + "Coronary artery bypass grafting", lead: lead, in: s.book), "From OR 4: Coronary artery bypass grafting")
        XCTAssertEqual(CaseScope.named("Doses show as the drug's written rule until the case has a weight.", lead: lead, in: s.book),
                       "Doses show as the drug's written rule until the case has a weight.", "other captions are left alone")
    }

    // MARK: Fills: two cases differ, an empty one fills nothing

    func testTheScoreFillsFollowTheRecord() {
        let heart = PatientRules.prefill("rcri", heartCase())
        XCTAssertTrue(heart.on.contains("ihd"))
        XCTAssertTrue(PatientRules.prefill("rcri", womanCase()).isEmpty, "another case: nothing carried over")
        XCTAssertTrue(PatientRules.prefill("rcri", PatientRecord()).isEmpty, "an empty case fills nothing")

        XCTAssertEqual(PatientRules.prefill("ariscat", heartCase()).choices["age"], "51–80")
        XCTAssertEqual(PatientRules.prefill("ariscat", womanCase()).choices["age"], "51–80")
        var older = womanCase(); older.ageYears = 30
        XCTAssertEqual(PatientRules.prefill("ariscat", older).choices["age"], "≤ 50", "a different record, a different fill")
        XCTAssertTrue(PatientRules.prefill("ariscat", PatientRecord()).isEmpty)

        XCTAssertTrue(PatientRules.prefill("stopbang", heartCase()).on.contains("gender"))
        XCTAssertFalse(PatientRules.prefill("stopbang", womanCase()).on.contains("gender"))
        XCTAssertTrue(PatientRules.prefill("stopbang", PatientRecord()).isEmpty)

        XCTAssertTrue(PatientRules.prefill("apfel", womanCase()).on.contains("female"))
        XCTAssertTrue(PatientRules.prefill("apfel", heartCase()).isEmpty)
        XCTAssertTrue(PatientRules.prefill("apfel", PatientRecord()).isEmpty)
    }

    func testTheWeightFillsFollowTheRecord() {
        // The text a weight field is filled with (Reference quick cards, OB Emergencies).
        XCTAssertEqual(CaseScope.weightText(92), "92")
        XCTAssertEqual(CaseScope.weightText(64.5), "64.5")
        XCTAssertEqual(CaseScope.weightText(nil), "", "a case with no weight leaves the field empty")
        XCTAssertEqual(CaseScope.weightText(0), "")
        // Infusions fill the adult's weight, never a child's.
        XCTAssertEqual(InfusionsView.patientWeight(for: heartCase()), 92)
        XCTAssertEqual(InfusionsView.patientWeight(for: womanCase()), 64)
        XCTAssertNil(InfusionsView.patientWeight(for: childCase()))
        XCTAssertNil(InfusionsView.patientWeight(for: PatientRecord()))
        // The pediatric calculator fills a child's weight (PedsCalculatorView: isChild ? weightKg : nil).
        XCTAssertTrue(childCase().isChild)
        XCTAssertFalse(heartCase().isChild)
        XCTAssertNil(PatientRecord().weightKg, "an empty case has no weight to fill")
    }

    func testTheValveGraderContextFollowsTheRecord() {
        let a = ValveGrading.Context(heartCase())
        let b = ValveGrading.Context(womanCase())
        XCTAssertNotNil(a.bsa)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(ValveGrading.Context(PatientRecord()), ValveGrading.Context(), "an empty case: no BSA and no LVEF")
    }

    func testTheProphylaxisFillFollowsTheCase() throws {
        let heart = ProphylaxisEngine.prefill(record: heartCase(), data: d)
        XCTAssertNotNil(heart.group)
        XCTAssertTrue(heart.mrsa)
        XCTAssertTrue(heart.betaLactamAllergy || heart.allergyAsk, "the penicillin rash")

        var knee = womanCase()
        knee.setProcedures([PlannedProcedure(try XCTUnwrap(ProcedureCatalog.byID("revision-tka"), "revision-tka"))])
        let other = ProphylaxisEngine.prefill(record: knee, data: d)
        XCTAssertNotEqual(other.group, heart.group, "another case, another operation")
        XCTAssertFalse(other.mrsa, "nothing carried over from the last patient")
        XCTAssertFalse(other.betaLactamAllergy)
        XCTAssertFalse(other.allergyAsk)
        XCTAssertNil(other.allergyCaption)
        XCTAssertNil(other.mrsaCaption)

        let empty = ProphylaxisEngine.prefill(record: PatientRecord(), data: d)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty, ProphylaxisPrefill(), "an empty case fills nothing at all")
    }

    // MARK: The write target

    @MainActor func testASaveGoesToTheCaseCurrentAtTheTap() {
        let s = store(rooms: ["OR 4", "OR 9"])
        s.selectCase(s.cases[0].id)
        let first = s.cases[0].id
        let second = s.cases[1].id
        // The clinician switches while a score is open; the tool is rebuilt for the second case, and its Save writes there.
        s.selectCase(second)
        let entry = PatientScore(points: 1, max: 6, label: "Class II", detail: nil, answers: ["Ischemic heart disease"], on: ["ihd"], choices: [:], date: Date())
        s.update(discrete: true) { $0.scores["rcri"] = entry }
        XCTAssertEqual(s.cases.first { $0.id == second }?.record.scores["rcri"], entry)
        XCTAssertNil(s.cases.first { $0.id == first }?.record.scores["rcri"], "the case the tool was opened for is untouched")
        XCTAssertEqual(CaseScope.writeCaption("Saves to", in: s.book), "Saves to OR 9", "and the caption said so")
    }

    #if DEBUG
    // MARK: The screenshot cases

    @MainActor func testTheDemoCasesDifferInWhatTheToolsFill() {
        let a = PatientDemo.caseSwitch("demo-switch", select: 1)
        XCTAssertEqual(a.book.cases.map(\.label), ["OR 4", "OR 9"])
        XCTAssertEqual(a.book.current.label, "OR 4")
        XCTAssertEqual(a.book.cases[0].record.weightKg, 92)
        XCTAssertEqual(a.book.cases[1].record.weightKg, 80)
        XCTAssertEqual(PatientDemo.caseSwitch("demo-switch", select: 2).book.current.label, "OR 9")
        let kids = PatientDemo.caseSwitch("demo-switch-peds", select: 1)
        XCTAssertTrue(kids.book.cases.allSatisfy { $0.record.isChild })
        XCTAssertNotEqual(kids.book.cases[0].record.weightKg, kids.book.cases[1].record.weightKg)
        XCTAssertNotEqual(PatientRules.prefill("rcri", a.book.cases[0].record), PatientRules.prefill("rcri", a.book.cases[1].record))
        // The seed is what -ps.patient demo-switch opens.
        XCTAssertEqual(PatientStore.debugCases("demo-switch", select: 2)?.book.current.label, "OR 9")
    }
    #endif
}
