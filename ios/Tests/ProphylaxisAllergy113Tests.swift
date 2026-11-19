import XCTest
@testable import PeriopSignal

/// 1.13 (Ben, Nov 19, after the GPT-6 review): the β-lactam allergy control of the Surgical Antibiotic Prophylaxis calculator.
/// Any penicillin on a case's allergy list used to prefill "β-lactam allergy: Yes", which swaps the result to clindamycin or
/// vancomycin. The 2013 guideline says a cephalosporin can be used when the penicillin reaction was not IgE-mediated or
/// exfoliative, and that the patient should be asked. So a penicillin-only history with no severe or IgE-type reaction on record
/// is ASKED: neither No nor Yes is chosen and the result says "Check the allergy first" until the user answers.
final class ProphylaxisAllergy113Tests: XCTestCase {

    private var bundleFile: ReferenceBundle!
    private var d: ProphylaxisData { bundleFile.prophylaxis! }
    private var t: CaseTimerData { bundleFile.caseTimers! }

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        bundleFile = try ReferenceLoader.decode(try Data(contentsOf: url))
        XCTAssertNotNil(bundleFile.prophylaxis)
        XCTAssertNotNil(bundleFile.caseTimers)
    }

    private func adult() -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = 90
        return r
    }

    /// A case with these allergies on the list, exactly as written.
    private func record(_ list: [PatientAllergy]) -> PatientRecord {
        var r = adult()
        r.allergyList = list
        return r
    }

    /// A case whose allergies were typed and read by the Allergies reader ("PCN - rash").
    private func typed(_ text: String) -> PatientRecord {
        var r = adult()
        r.allergyList = AllergyCatalog.parse(text)
        return r
    }

    private func prefill(_ r: PatientRecord) -> ProphylaxisPrefill {
        ProphylaxisEngine.prefill(record: r, data: d)
    }

    private func input(_ g: String, _ p: String, _ v: String? = nil, unanswered: Bool = false, yes: Bool = false, mrsa: Bool = false) -> ProphylaxisInput {
        var i = ProphylaxisInput()
        i.chooseGroup(g, data: d)
        i.chooseProcedure(p, data: d)
        if let v { i.chooseVariant(v, data: d) }
        i.betaLactamAllergy = yes
        i.allergyUnanswered = unanswered
        i.mrsa = mrsa
        return i
    }

    private func answer(_ i: ProphylaxisInput, record: PatientRecord? = nil) -> ProphylaxisAnswer {
        ProphylaxisEngine.answer(i, record: record ?? adult(), data: d, timers: t)
    }

    // MARK: - The prefill asks

    func testABarePenicillinAMildPenicillinAndPCNRashAreAsked() {
        let cases: [(String, PatientRecord)] = [
            ("bare penicillin", record([PatientAllergy(name: "Penicillin")])),
            ("Penicillin (mild)", record([PatientAllergy(name: "Penicillin", severity: "mild")])),
            ("PCN - rash", typed("PCN - rash")),
            ("penicillin typed", typed("penicillin")),
        ]
        for (label, r) in cases {
            let p = prefill(r)
            XCTAssertTrue(p.allergyAsk, label)
            XCTAssertFalse(p.betaLactamAllergy, "\(label): not answered for the user")
            XCTAssertFalse(p.isEmpty, label)
            XCTAssertTrue(p.allergyCaption?.hasPrefix("From the case: ") == true, label)
            XCTAssertTrue(p.allergyCaption?.hasSuffix(". Not selected for you: choose.") == true, label)
        }
        XCTAssertEqual(prefill(record([PatientAllergy(name: "Penicillin", severity: "mild")])).allergyCaption,
                       "From the case: Penicillin (mild). Not selected for you: choose.")
        XCTAssertEqual(prefill(typed("PCN - rash")).allergyCaption, "From the case: Penicillin (rash). Not selected for you: choose.")
    }

    func testEveryPenicillinOfTheClassIsAsked() {
        for name in ["Amoxicillin", "Penicillin", "Nafcillin", "Piperacillin", "Oxacillin", "Penicillin G"] {
            let a = PatientAllergy(name: name, reaction: "rash")
            XCTAssertTrue(ProphylaxisAllergy.isBetaLactam(a), name)
            XCTAssertTrue(ProphylaxisAllergy.isPenicillinClass(a), name)
            XCTAssertTrue(prefill(record([a])).allergyAsk, name)
        }
        for name in ["Cefazolin", "Cephalosporins", "Meropenem", "Carbapenems", "Cefoxitin", "Ceftriaxone"] {
            XCTAssertFalse(ProphylaxisAllergy.isPenicillinClass(PatientAllergy(name: name)), name)
        }
    }

    // MARK: - The prefill stays Yes

    func testASevereOrIgEReactionStaysYes() {
        let cases: [(String, PatientRecord)] = [
            ("PCN anaphylaxis", typed("PCN anaphylaxis")),
            ("amoxicillin hives", typed("amoxicillin hives")),
            ("ceftriaxone rash", typed("ceftriaxone rash")),
            ("top severity", record([PatientAllergy(name: "Penicillin", severity: "anaphylaxis")])),
            ("cefazolin alone", record([PatientAllergy(name: "Cefazolin")])),
            ("meropenem alone", record([PatientAllergy(name: "Meropenem", reaction: "rash")])),
        ]
        for (label, r) in cases {
            let p = prefill(r)
            XCTAssertTrue(p.betaLactamAllergy, label)
            XCTAssertFalse(p.allergyAsk, label)
            XCTAssertTrue(p.allergyCaption?.hasPrefix("From the case: ") == true, label)
            XCTAssertFalse(p.allergyCaption?.contains("Not selected for you") == true, label)
        }
        XCTAssertEqual(prefill(typed("amoxicillin hives")).allergyCaption, "From the case: Amoxicillin (hives)")
    }

    func testEachSeverityWordInTheReactionTextStaysYesAndOrdinaryWordsAreAsked() {
        let severe = ["anaphylactic reaction", "Hives", "urticaria", "angioedema", "facial swelling", "lips swollen", "bronchospasm", "wheezing",
                      "throat tightness", "hypotension", "shock", "SJS", "Stevens-Johnson syndrome", "TEN", "toxic epidermal necrolysis", "DRESS",
                      "exfoliative dermatitis", "blistering", "desquamation", "rash with HIVES"]
        for reaction in severe {
            let a = PatientAllergy(name: "Penicillin", reaction: reaction)
            XCTAssertTrue(ProphylaxisAllergy.isSevereOrIgE(a), reaction)
            XCTAssertTrue(prefill(record([a])).betaLactamAllergy, reaction)
        }
        // "ten" is not "tender" and "dress" is not "address": only whole words for the short ones.
        let ordinary = ["rash", "mild rash", "GI upset", "nausea", "itching", "tender arm", "wrote the address", "gotten better", "unknown"]
        for reaction in ordinary {
            let a = PatientAllergy(name: "Penicillin", reaction: reaction)
            XCTAssertFalse(ProphylaxisAllergy.isSevereOrIgE(a), reaction)
            XCTAssertTrue(prefill(record([a])).allergyAsk, reaction)
        }
        // Only the top severity counts by itself: "severe" with no reaction named is asked.
        XCTAssertFalse(ProphylaxisAllergy.isSevereOrIgE(PatientAllergy(name: "Penicillin", severity: "severe")))
        XCTAssertTrue(ProphylaxisAllergy.isSevereOrIgE(PatientAllergy(name: "Penicillin", severity: "anaphylaxis")))
    }

    func testAPenicillinWithACephalosporinOrCarbapenemOnTheSameListStaysYes() {
        let cases: [(String, PatientRecord)] = [
            ("PCN rash and cefazolin", typed("PCN rash, cefazolin")),
            ("PCN and ceftriaxone rash", typed("PCN, ceftriaxone rash")),
            ("mild penicillin and meropenem", record([PatientAllergy(name: "Penicillin", severity: "mild"), PatientAllergy(name: "Meropenem")])),
        ]
        for (label, r) in cases {
            let p = prefill(r)
            XCTAssertTrue(p.betaLactamAllergy, label)
            XCTAssertFalse(p.allergyAsk, label)
        }
        // Several penicillins with nothing severe are still asked, each in the caption.
        let two = prefill(record([PatientAllergy(name: "Penicillin", reaction: "rash"), PatientAllergy(name: "Amoxicillin")]))
        XCTAssertTrue(two.allergyAsk)
        XCTAssertEqual(two.allergyCaption, "From the case: Penicillin (rash); Amoxicillin. Not selected for you: choose.")
    }

    func testATolerationAndNoBetaLactamPrefillNothingForTheAllergy() {
        for r in [typed("cefazolin tolerated"), typed("sulfa"), adult()] {
            let p = prefill(r)
            XCTAssertFalse(p.allergyAsk)
            XCTAssertFalse(p.betaLactamAllergy)
            XCTAssertNil(p.allergyCaption)
        }
        // A penicillin listed with a tolerated cefazolin is only the penicillin: asked when it has no severe reaction.
        XCTAssertTrue(prefill(typed("PCN - rash, cefazolin tolerated")).allergyAsk)
    }

    // MARK: - The input state

    func testApplyingTheAskingPrefillLeavesTheAllergyUnansweredUntilTheUserAnswers() {
        var i = ProphylaxisInput()
        XCTAssertFalse(i.allergyUnanswered, "off by default")
        i.apply(prefill(typed("PCN - rash")), data: d)
        XCTAssertTrue(i.allergyUnanswered)
        XCTAssertFalse(i.betaLactamAllergy)
        i.setAllergy(false)
        XCTAssertFalse(i.allergyUnanswered)
        XCTAssertFalse(i.betaLactamAllergy)

        var j = ProphylaxisInput()
        j.apply(prefill(typed("PCN - rash")), data: d)
        j.setAllergy(true)
        XCTAssertFalse(j.allergyUnanswered)
        XCTAssertTrue(j.betaLactamAllergy)

        var k = ProphylaxisInput()
        k.apply(prefill(typed("PCN anaphylaxis")), data: d)
        XCTAssertFalse(k.allergyUnanswered, "a severe reaction is answered Yes, not asked")
        XCTAssertTrue(k.betaLactamAllergy)

        var none = ProphylaxisInput()
        none.apply(prefill(adult()), data: d)
        XCTAssertFalse(none.allergyUnanswered)
    }

    // MARK: - The result while the allergy is unanswered

    func testACardiacProcedureWithTheAllergyUnansweredIsTheQuestionCardAndNothingElse() {
        // MRSA is on too: the card still shows no agent, no MRSA block, no dose and nothing to Start.
        let a = answer(input("cardiac", "cabg", unanswered: true, mrsa: true))
        XCTAssertEqual(a.state, .allergyQuestion)
        XCTAssertEqual(a.title, "Check the allergy first")
        XCTAssertEqual(a.body, "Penicillin is on the allergy list. The guideline allows a cephalosporin unless the reaction was IgE-mediated (anaphylaxis, urticaria, bronchospasm) or exfoliative (Stevens-Johnson syndrome, toxic epidermal necrolysis). Choose No or Yes above.")
        XCTAssertTrue(a.regimens.isEmpty)
        XCTAssertTrue(a.allLines.isEmpty)
        XCTAssertNil(a.mrsa)
        XCTAssertNil(a.mrsaNote)
        XCTAssertNil(a.timing)
        XCTAssertNil(a.allergyHint)
        XCTAssertNil(a.evidence)
        XCTAssertFalse(a.alternative)
        // Start is offered for no line of it.
        XCTAssertTrue(a.allLines.filter { ProphylaxisEngine.startState($0.agent, record: adult(), timers: t) == .available }.isEmpty)
    }

    func testTheQuestionNeedsAProcedureAndTheProcedureQuestionAnsweredFirst() {
        XCTAssertEqual(answer(ProphylaxisInput(allergyUnanswered: true)).state, .noProcedure)
        // A procedure that asks its own question: that question comes first, as before.
        XCTAssertEqual(answer(input("lowergi", "appendectomy", unanswered: true)).state, .question)
        XCTAssertEqual(answer(input("lowergi", "appendectomy", "uncomplicated", unanswered: true)).state, .allergyQuestion)
    }

    func testAResultThatDoesNotDependOnTheAllergyIsAnsweredAsToday() {
        // No prophylaxis recommended, either way.
        let none = answer(input("biliary", "lap", "low", unanswered: true))
        XCTAssertEqual(none.state, .none)
        XCTAssertEqual(none.body, "No prophylaxis recommended")
        XCTAssertEqual(none, answer(input("biliary", "lap", "low")))
        // The table has no row.
        let outside = answer(input("cardiac", "cath-tee", unanswered: true))
        XCTAssertEqual(outside.state, .outside)
        XCTAssertEqual(outside.title, "Not in the guideline's table")
        XCTAssertEqual(outside, answer(input("cardiac", "cath-tee")))
        // Text only (the table's cell as it is).
        let text = answer(input("ophthalmic", "ophthalmic", unanswered: true))
        XCTAssertEqual(text.state, .text)
        XCTAssertEqual(text, answer(input("ophthalmic", "ophthalmic")))
    }

    func testEveryRowAsksExactlyWhenNoAndYesAreDifferentAndNeverOtherwise() {
        var asked = 0
        var passed = 0
        for g in d.groups {
            for p in g.procedures {
                for v in p.variants {
                    let variant: String? = p.variants.count > 1 ? v.id : nil
                    let plain = answer(input(g.id, p.id, variant))
                    let yes = answer(input(g.id, p.id, variant, yes: true))
                    let unanswered = answer(input(g.id, p.id, variant, unanswered: true))
                    let label = "\(g.id)/\(p.id)/\(v.id)"
                    if plain.state == .regimens || yes.state == .regimens {
                        XCTAssertEqual(unanswered.state, .allergyQuestion, label)
                        asked += 1
                    } else {
                        XCTAssertEqual(unanswered, plain, label)
                        passed += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(asked, 40, "most rows have agents")
        XCTAssertGreaterThan(passed, 5, "the none, outside and text rows answer as today")
    }

    // MARK: - Answering

    func testAnsweringNoShowsCefazolinAndAnsweringYesShowsTheAlternativeWithTheHint() throws {
        var i = input("cardiac", "cabg", unanswered: true)
        XCTAssertEqual(answer(i).state, .allergyQuestion)

        i.setAllergy(false)
        let no = answer(i)
        XCTAssertEqual(no.state, .regimens)
        XCTAssertEqual(no.title, "Recommended")
        XCTAssertFalse(no.alternative)
        XCTAssertNil(no.allergyHint, "the hint is for the alternative only")
        XCTAssertTrue(no.allLines.contains { $0.agent == "cefazolin" })

        i = input("cardiac", "cabg", unanswered: true)
        i.setAllergy(true)
        let yes = answer(i)
        XCTAssertEqual(yes.state, .regimens)
        XCTAssertEqual(yes.title, "Alternative for β-lactam allergy")
        XCTAssertTrue(yes.alternative)
        XCTAssertFalse(yes.allLines.isEmpty)
        XCTAssertFalse(yes.allLines.contains { $0.agent == "cefazolin" }, "the alternative hides cefazolin")
        XCTAssertEqual(yes.allergyHint, "Penicillin allergy only? The guideline allows a cephalosporin unless the reaction was IgE-mediated or exfoliative.")
        XCTAssertEqual(ProphylaxisEngine.allergyHint, yes.allergyHint)
    }

    func testTheAlternativeCardKeepsItsHintWhenYesWasSetInTheStandaloneToolToo() {
        let yes = answer(input("cardiac", "cabg", yes: true))
        XCTAssertEqual(yes.allergyHint, ProphylaxisEngine.allergyHint)
        // A result with no agents (the ophthalmic cell) has nothing for the hint to sit above.
        XCTAssertNil(answer(input("ophthalmic", "ophthalmic", yes: true)).allergyHint)
    }

    // MARK: - The standalone tool

    func testTheStandaloneToolIsUnchanged() {
        // No case: no prefill, so the allergy is never unanswered and No is selected as before.
        let i = input("cardiac", "cabg")
        XCTAssertFalse(i.allergyUnanswered)
        XCTAssertFalse(i.betaLactamAllergy)
        let a = answer(i)
        XCTAssertEqual(a.state, .regimens)
        XCTAssertEqual(a.title, "Recommended")
        XCTAssertNil(a.allergyHint)
        // Opened from the Reference tab: nothing applies a prefill.
        var blank = ProphylaxisInput()
        blank.chooseGroup("cardiac", data: d)
        blank.chooseProcedure("cabg", data: d)
        XCTAssertEqual(blank, i)
        XCTAssertEqual(ProphylaxisInput().allergyUnanswered, false)
    }
}
