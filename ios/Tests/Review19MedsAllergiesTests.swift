import XCTest
@testable import PeriopSignal

/// 1.9 review, home medications and allergies: the short handoff and the History row read the 1.9 lists; a denied
/// severity or allergen is not recorded; typed allergies with another severity still show; stop, denial and remark words
/// stay with their drug; a combination brand in parentheses raises its flag; Humulin and Novolin alone are insulins;
/// topical and eye-drop steroids raise no steroid flag.
final class Review19MedsAllergiesTests: XCTestCase {
    private func allergies(_ line: String) -> [String] { AllergyCatalog.parse(line).map(\.text) }
    private func meds(_ line: String) -> [String] { MedicationCatalog.parse(line).map(\.text) }
    private func flags(_ line: String) -> Set<String> { MedicationCatalog.flags(for: MedicationCatalog.parse(line)) }

    // MARK: 1. The short handoff gives the 1.9 allergy list

    func testShortHandoffGivesTheAllergyList() {
        var r = PatientRecord()
        r.allergyList = AllergyCatalog.parse("latex anaphylaxis, PCN rash")
        XCTAssertEqual(r.allergyList.map(\.text), ["Latex (anaphylaxis)", "Penicillin (rash)"])
        let s = HandoffWriter.shortText(r)
        XCTAssertTrue(s.contains("Allergies: Latex (anaphylaxis); Penicillin (rash)"), s)
        var none = PatientRecord()
        none.nkda = true
        XCTAssertTrue(HandoffWriter.shortText(none).contains("Allergies: No known drug allergies"))
        var old = PatientRecord()
        old.allergies = "penicillin (rash)"
        XCTAssertTrue(HandoffWriter.shortText(old).contains("Allergies: Penicillin (rash)"), "a record saved before 1.9")
        XCTAssertFalse(HandoffWriter.shortText(PatientRecord()).contains("Allergies"))
    }

    // MARK: 2. A denied severity is not recorded

    func testADeniedSeverityIsNotRecorded() {
        let a = AllergyCatalog.parse("PCN (hives, no anaphylaxis)")
        XCTAssertEqual(a.map(\.name), ["Penicillin"])
        XCTAssertNil(a.first?.severity, "no anaphylaxis is not anaphylaxis")
        XCTAssertEqual(a.first?.reaction, "hives, no anaphylaxis", "the words stay as typed")
        let b = AllergyCatalog.parse("PCN - rash, not anaphylaxis")
        XCTAssertEqual(b.map(\.name), ["Penicillin"], "no typed allergen 'Not'")
        XCTAssertNil(b.first?.severity)
        XCTAssertEqual(b.first?.reaction, "rash, not anaphylaxis")
        XCTAssertEqual(allergies("sulfa - rash, non-anaphylactic"), ["Sulfa drugs (rash, non-anaphylactic)"])
        XCTAssertEqual(allergies("latex anaphylaxis"), ["Latex (anaphylaxis)"], "a severity as written stays")
        XCTAssertEqual(allergies("PCN mild rash, latex severe"), ["Penicillin (mild, rash)", "Latex (severe)"])
    }

    // MARK: 3. A tolerated or denied allergen is not filed

    func testADeniedOrToleratedAllergenIsNotFiled() {
        let a = AllergyCatalog.parse("PCN (hives; tolerated cefazolin)")
        XCTAssertEqual(a.map(\.name), ["Penicillin"], "cefazolin is not an allergy")
        XCTAssertEqual(a.first?.reaction, "hives; tolerated cefazolin")
        let b = AllergyCatalog.parse("PCN rash, no latex allergy")
        XCTAssertEqual(b.map(\.name), ["Penicillin"], "neither 'No' nor latex")
        XCTAssertEqual(b.first?.reaction, "rash, no latex allergy")
        XCTAssertEqual(allergies("sulfa (hives), not allergic to cefazolin"), ["Sulfa drugs (hives, not allergic to cefazolin)"])
        XCTAssertTrue(AllergyCatalog.parse("no latex allergy").isEmpty)
        XCTAssertEqual(allergies("PCN rash, latex allergy"), ["Penicillin (rash)", "Latex"], "an allergen not denied is filed")
    }

    // MARK: 4. Typed allergies with another severity still show

    func testTypedAllergyWithAnotherSeverityStillShows() {
        var r = PatientRecord()
        r.allergyList = [PatientAllergy(name: "Penicillin", severity: "mild")]
        r.allergies = "PCN - anaphylaxis"
        XCTAssertFalse(AllergyCatalog.covers(r.allergyList, legacy: r.allergies))
        let l = PatientAllergyText.line(r)
        XCTAssertEqual(l?.text, "Penicillin (mild); PCN - anaphylaxis")
        XCTAssertEqual(l?.marks, ["PCN - anaphylaxis"], "the typed anaphylaxis in red")
        XCTAssertTrue(PatientAllergyText.items(r).contains { $0.legacy && $0.anaphylaxis })
        XCTAssertTrue(HandoffWriter.shortText(r).contains("Allergies: Penicillin (mild); PCN - anaphylaxis"))
        // The same allergy as listed is not shown twice.
        r.allergies = "penicillin mild"
        XCTAssertTrue(AllergyCatalog.covers(r.allergyList, legacy: r.allergies))
        XCTAssertEqual(PatientAllergyText.line(r)?.text, "Penicillin (mild)")
        r.allergies = "penicillin"
        XCTAssertEqual(PatientAllergyText.line(r)?.text, "Penicillin (mild)", "nothing more typed")
    }

    // MARK: 5. Stopped, held and denied drugs

    func testStoppedHeldAndDeniedDrugs() {
        // A stop stays with its drug. The flag stays too: a P2Y12 inhibitor or an anticoagulant stopped or held
        // before surgery is still the alert's subject (when the last dose was).
        XCTAssertEqual(meds("Stopped Plavix 5 days ago, aspirin 81"), ["Clopidogrel Stopped 5 days ago", "Aspirin 81"])
        XCTAssertEqual(meds("Holding Eliquis since Monday"), ["Apixaban Holding since Monday"])
        XCTAssertEqual(meds("metoprolol 25 stopped Plavix 5 days ago"), ["Metoprolol 25", "Clopidogrel stopped 5 days ago"])
        // A denial is kept as typed and raises no flag.
        let denied = MedicationCatalog.parse("Denies opioids")
        XCTAssertEqual(denied.map(\.text), ["Denies opioids"])
        XCTAssertNil(denied.first?.catalogID)
        XCTAssertEqual(MedicationCatalog.flags(for: denied), [])
        XCTAssertEqual(meds("no opioids"), ["No opioids"])
        XCTAssertEqual(flags("no opioids"), [])
        XCTAssertEqual(meds("metoprolol 25, denies opioids or insulin"), ["Metoprolol 25", "Denies opioids or insulin"])
        XCTAssertEqual(flags("metoprolol 25, denies opioids or insulin"), ["betablocker"])
        XCTAssertEqual(meds("metoprolol 25 no aspirin"), ["Metoprolol 25", "No aspirin"])
        XCTAssertEqual(flags("metoprolol 25 no aspirin"), ["betablocker"])
        // Not denied: the drug and its flag.
        XCTAssertEqual(meds("oxycodone 5 mg prn"), ["Oxycodone 5 mg prn"])
        XCTAssertEqual(flags("oxycodone 5 mg prn"), ["opioid"])
        XCTAssertEqual(meds("apixaban 5 mg BID (held 3 days), metoprolol"), ["Apixaban 5 mg BID (held 3 days)", "Metoprolol"])
    }

    // MARK: 6. A combination brand in parentheses

    func testACombinationBrandInParenthesesRaisesItsFlag() {
        XCTAssertEqual(meds("Metformin (Synjardy) 12.5/1000 bid"), ["Empagliflozin/metformin 12.5/1000 bid"])
        XCTAssertEqual(flags("Metformin (Synjardy) 12.5/1000 bid"), ["sglt2"])
        XCTAssertEqual(MedicationCatalog.parse("linagliptin (Glyxambi) 10/5").map(\.catalogID), ["empagliflozin-linagliptin"])
        XCTAssertEqual(flags("metformin (Xigduo XR) 10/1000 daily"), ["sglt2"])
        // As before: the brand of the same drug, and a generic after its brand.
        XCTAssertEqual(meds("metoprolol (Toprol XL) 50 mg daily"), ["Metoprolol succinate 50 mg daily"])
        XCTAssertEqual(meds("Toprol XL (metoprolol) 50 mg"), ["Metoprolol succinate 50 mg"])
        XCTAssertEqual(meds("Synjardy (metformin) 12.5/1000"), ["Empagliflozin/metformin 12.5/1000"])
    }

    // MARK: 7. Humulin and Novolin alone

    func testHumulinAndNovolinAloneAreInsulin() {
        XCTAssertEqual(meds("Humulin 20 units qam"), ["Humulin 20 units qam"])
        XCTAssertEqual(flags("Humulin 20 units qam"), ["insulin"])
        XCTAssertEqual(meds("Novolin 10 units bid"), ["Novolin 10 units bid"])
        XCTAssertEqual(flags("Novolin 10 units bid"), ["insulin"])
        XCTAssertEqual(MedicationCatalog.flags(forName: "Humulin"), ["insulin"])
        XCTAssertEqual(meds("Humulin N 10 units"), ["Insulin NPH 10 units"], "the type still reads when written")
        XCTAssertEqual(meds("Novolin 70/30 20 units"), ["Insulin NPH/regular 70/30 20 units"])
    }

    // MARK: 8. Topical and eye-drop steroids

    func testTopicalAndEyeDropSteroidsRaiseNoSteroidFlag() {
        let cream = MedicationCatalog.parse("hydrocortisone 1% cream bid")
        XCTAssertEqual(cream.map(\.text), ["Hydrocortisone 1% cream bid"])
        XCTAssertEqual(cream.map(\.catalogID), ["hydrocortisone-topical"])
        XCTAssertEqual(MedicationCatalog.flags(for: cream), [])
        let drops = MedicationCatalog.parse("prednisolone 1% eye drops qid")
        XCTAssertEqual(drops.map(\.text), ["Prednisolone 1% eye drops qid"])
        XCTAssertEqual(drops.map(\.catalogID), ["prednisolone-ophthalmic"])
        XCTAssertEqual(MedicationCatalog.flags(for: drops), [])
        XCTAssertEqual(flags("Pred Forte 1 gtt OU qid"), [])
        XCTAssertEqual(flags("dexamethasone 0.1% drops OS"), [])
        // Systemic: flagged as before.
        XCTAssertEqual(flags("hydrocortisone 20 mg qam"), ["steroid"])
        XCTAssertEqual(flags("prednisolone 5 mg daily"), ["steroid"])
        XCTAssertEqual(flags("prednisone 10 mg daily"), ["steroid"])
        XCTAssertEqual(flags("dexamethasone 4 mg po"), ["steroid"])
        var r = PatientRecord()
        r.homeMeds = cream + drops
        r.medFlags = MedicationCatalog.flags(for: r.homeMeds)
        XCTAssertFalse(PatientSummary.historyLines(r).contains { $0.label == "Medication alerts" }, "no Chronic steroids alert")
    }

    // MARK: 9. The History row reads the lists

    func testHistoryRowReadsTheLists() {
        var r = PatientRecord()
        r.homeMeds = MedicationCatalog.parse("metoprolol 25 bid")
        r.allergyList = AllergyCatalog.parse("latex anaphylaxis")
        XCTAssertEqual(PatientHistoryRows.medsSummary(r), "Allergies: Latex (anaphylaxis) · Metoprolol 25 bid")
        var n = PatientRecord()
        n.nkda = true
        n.homeMeds = MedicationCatalog.parse("metoprolol 25 bid")
        XCTAssertEqual(PatientHistoryRows.medsSummary(n), "NKDA · Metoprolol 25 bid", "the medications are not hidden")
        var none = PatientRecord()
        none.nkda = true
        XCTAssertEqual(PatientHistoryRows.medsSummary(none), "No known drug allergies")
        XCTAssertEqual(PatientHistoryRows.medsSummary(PatientRecord()), "None recorded")
        var old = PatientRecord()
        old.allergies = "penicillin"
        old.medications = "amlodipine"
        XCTAssertEqual(PatientHistoryRows.medsSummary(old), "Allergies: Penicillin · Amlodipine", "a record saved before 1.9")
    }

    // MARK: 10. Ordinary words at the start of an item

    func testRemarksAreNotMedications() {
        XCTAssertEqual(meds("Eliquis 5 mg BID, last dose Sunday, metoprolol 25 bid"), ["Apixaban 5 mg BID, last dose Sunday", "Metoprolol 25 bid"])
        XCTAssertEqual(meds("metoprolol 25, last taken this morning"), ["Metoprolol 25, last taken this morning"])
        XCTAssertTrue(meds("patient reports compliance").isEmpty)
        XCTAssertEqual(meds("metoprolol 25, patient reports compliance"), ["Metoprolol 25"])
        XCTAssertEqual(meds("Eliquis 5 bid, held since Monday"), ["Apixaban 5 bid, held since Monday"])
        // A word the list does not know still reads at the start of an item.
        XCTAssertEqual(meds("metoprolol 25, foobarazine 10"), ["Metoprolol 25", "Foobarazine 10"])
    }

    // MARK: 11. An intolerance is filed

    func testAnIntoleranceIsFiled() {
        // A word that reverses "tolerate" makes an intolerance: the allergen is filed, with no junk allergen before it.
        XCTAssertEqual(allergies("unable to tolerate sulfa"), ["Sulfa drugs"])
        XCTAssertEqual(allergies("cannot tolerate morphine - itching"), ["Morphine (itching)"])
        XCTAssertEqual(allergies("can't tolerate morphine"), ["Morphine"])
        XCTAssertEqual(allergies("does not tolerate codeine"), ["Codeine"])
        XCTAssertEqual(allergies("poorly tolerated codeine"), ["Codeine"])
        XCTAssertEqual(allergies("PCN rash, does not tolerate codeine"), ["Penicillin (rash)", "Codeine"])
        XCTAssertEqual(allergies("codeine - nausea, poorly tolerated"), ["Codeine (nausea, poorly tolerated)"])
        // "Tolerated" alone still denies.
        XCTAssertEqual(AllergyCatalog.parse("PCN (hives; tolerated cefazolin)").map(\.name), ["Penicillin"])
        XCTAssertEqual(AllergyCatalog.parse("PCN rash, tolerates cefazolin").map(\.name), ["Penicillin"])
    }

    // MARK: 12. A negative reaction is a reaction

    func testANegativeReactionIsAReaction() {
        XCTAssertEqual(allergies("Negative reaction to penicillin"), ["Penicillin"])
        XCTAssertEqual(allergies("latex anaphylaxis, negative reaction to PCN"), ["Latex (anaphylaxis)", "Penicillin"])
        XCTAssertEqual(allergies("adverse reaction to codeine"), ["Codeine"])
        XCTAssertTrue(AllergyCatalog.parse("no reaction to latex").isEmpty, "a denial still denies")
    }

    // MARK: 13. A denied stop is the drug still taken

    func testADeniedStopKeepsTheDrugAndItsFlag() {
        XCTAssertEqual(meds("Not holding Eliquis"), ["Apixaban Not holding"])
        XCTAssertEqual(flags("Not holding Eliquis"), ["anticoagulant"])
        XCTAssertEqual(meds("Did not stop Plavix"), ["Clopidogrel Did not stop"])
        XCTAssertEqual(flags("Did not stop Plavix"), ["p2y12"])
        XCTAssertEqual(meds("Has not held apixaban"), ["Apixaban Has not held"])
        XCTAssertEqual(flags("Has not held apixaban"), ["anticoagulant"])
        XCTAssertEqual(meds("never stopped aspirin"), ["Aspirin never stopped"])
        XCTAssertEqual(flags("never stopped aspirin"), ["aspirin"])
        // A denial alone still raises no flag.
        XCTAssertEqual(flags("doesn't take Eliquis"), [])
        XCTAssertEqual(flags("not on Plavix"), [])
    }

    // MARK: 14. A denial carries on only over "or", and not to a drug with a dose

    func testADenialDoesNotCarryOverAndOrADose() {
        XCTAssertEqual(meds("No aspirin and Eliquis 5 mg bid"), ["No aspirin", "Apixaban 5 mg bid"])
        XCTAssertEqual(flags("No aspirin and Eliquis 5 mg bid"), ["anticoagulant"])
        XCTAssertEqual(meds("no aspirin or Eliquis 5 mg"), ["No aspirin", "Apixaban 5 mg"])
        XCTAssertEqual(flags("No aspirin and Eliquis"), ["anticoagulant"], "and does not carry the denial")
        XCTAssertEqual(flags("no aspirin with Eliquis"), ["anticoagulant"])
        // As before: "or" carries it on.
        XCTAssertEqual(meds("denies opioids or insulin"), ["Denies opioids or insulin"])
        XCTAssertEqual(flags("denies opioids or insulin"), [])
    }

    // MARK: 15. "No longer taking" is a stop

    func testNoLongerTakingIsAStop() {
        XCTAssertEqual(meds("no longer taking Plavix"), ["Clopidogrel no longer taking"])
        XCTAssertEqual(flags("no longer taking Plavix"), ["p2y12"])
        XCTAssertEqual(meds("stopped taking Plavix"), ["Clopidogrel stopped taking"])
        XCTAssertEqual(flags("stopped Plavix"), ["p2y12"])
    }
}
