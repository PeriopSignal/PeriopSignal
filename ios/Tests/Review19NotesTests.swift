import XCTest
@testable import PeriopSignal

/// The 1.9 review of the note reader and the quick-add bar: words read for another meaning (an allergy's reaction, a
/// device's "permanent", "fx" as function, a Gleason score, the article "a"), negative results and templated answers, an
/// operation planned today read as a past one, and NKDA or "still missing" ignoring the 1.9 lists. All lines are synthetic.
final class Review19NotesTests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 8))! }

    private func read(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func problems(_ s: String) -> Set<String> { Set(read(s).findings.map(\.id).filter { $0.hasPrefix("problem:") }) }
    private func applied(_ s: String, to start: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = start
        PatientNote.apply(read(s).findings.map(\.change), to: &r)
        return r
    }
    private func meaning(_ token: String, in text: String) -> String? { MedAbbreviations.scan(text).first { $0.token == token }?.meaning?.text }
    private func latex() -> PatientRecord {
        var r = PatientRecord()
        r.allergyList = [PatientAllergy(name: "Latex", severity: "anaphylaxis")]
        return r
    }

    /// An allergy's recorded reaction is not shock today (Shock is ASA IV).
    func testAnaphylacticShockInAnAllergySentenceIsNotShock() {
        let line = "Allergies: penicillin (anaphylactic shock), sulfa (rash)."
        XCTAssertFalse(problems(line).contains("problem:shock"), line)
        let r = applied(line)
        XCTAssertFalse(r.has("shock"))
        XCTAssertTrue(r.hx.shockTypes.isEmpty)
        XCTAssertTrue(problems("in anaphylactic shock after cefazolin, on epinephrine").contains("problem:shock"), "a shock now is still read")
        XCTAssertTrue(problems("septic shock on norepinephrine").contains("problem:shock"))
    }

    /// "Permanent" that begins "permanent pacemaker" is the device's, not the AF type (no automatic ECG fill).
    func testPermanentPacemakerIsNotPermanentAF() {
        let r = applied("PMH: HTN, DM2, AF, permanent pacemaker 2019")
        XCTAssertTrue(r.has("af"))
        XCTAssertNil(r.hx.afType)
        XCTAssertFalse(PatientCrossFill.permanentAF(r))
        XCTAssertNil(applied("AF - permanent PPM").hx.afType)
        XCTAssertEqual(applied("AF, permanent").hx.afType, "permanent")
        XCTAssertEqual(applied("AF (permanent), rate controlled").hx.afType, "permanent")
    }

    /// "non pacer dependent" with a space is not dependent (no automatic paced-rhythm ECG fill).
    func testNonPacerDependentWithASpace() {
        let r = applied("PPM in situ, non pacer dependent, underlying SR 70s")
        XCTAssertTrue(r.has("pacemaker"))
        XCTAssertFalse(r.hx.pacerDependent)
        XCTAssertFalse(PatientCrossFill.pacerDependent(r))
        XCTAssertFalse(applied("PPM, non pacemaker dependent").hx.pacerDependent)
        XCTAssertTrue(applied("PPM, pacer dependent").hx.pacerDependent)
    }

    /// A negative thrombophilia workup files no thrombophilia, nor the obstetric ASA III example for a pregnant patient on
    /// anticoagulation.
    func testNegativeThrombophiliaWorkup() {
        let line = "G2P1 at 20 weeks, on enoxaparin 40 mg daily for prior DVT, thrombophilia workup negative (FVL negative)."
        let found = problems(line)
        XCTAssertTrue(found.isDisjoint(with: ["problem:thrombophilia-heme", "problem:fvl", "problem:thrombophilia"]), found.sorted().joined(separator: ", "))
        XCTAssertTrue(found.contains("problem:pregnant"))
        for neg in ["FVL negative", "factor V Leiden: not detected", "prothrombin gene mutation neg", "negative thrombophilia workup",
                    "thrombophilia workup pending"] {
            let p = problems(neg)
            XCTAssertTrue(p.isDisjoint(with: ["problem:thrombophilia-heme", "problem:fvl"]), neg + " → " + p.sorted().joined(separator: ", "))
        }
        XCTAssertTrue(problems("FVL heterozygous").isSuperset(of: ["problem:fvl", "problem:thrombophilia-heme"]))
        XCTAssertTrue(problems("antiphospholipid syndrome on warfarin").contains("problem:thrombophilia-heme"))
    }

    /// A Gleason score is not weeks of gestation, even with "weeks" elsewhere in the sentence.
    func testGleasonScoreWithWeeksIsNotAGestation() {
        for line in ["PMH: HTN, prostate cancer (Gleason 4+3) diagnosed 6 weeks ago", "prostate adenocarcinoma, Gleason 4+4, RT for 6 weeks"] {
            let r = applied(line)
            XCTAssertFalse(r.has("pregnant"), line)
            XCTAssertNil(r.hx.gestationWeeks, line)
        }
        XCTAssertEqual(applied("G2P1 at 32+4 weeks").hx.gestationWeeks, 32)
        XCTAssertEqual(applied("pregnant, 32+4").hx.gestationWeeks, 32)
    }

    /// The article "a" after a hepatitis, and a vaccine after "Hep A/B", are not hepatitis A.
    func testHepatitisAFromTheArticleOrAVaccine() {
        for line in ["autoimmune hepatitis a few years ago", "alcoholic hepatitis a year ago", "Hep A/B vaccinated", "Hep B/A vaccinated"] {
            XCTAssertFalse(problems(line).contains("problem:hepatitis-viral"), line)
            XCTAssertTrue(applied(line).hx.hepatitisTypes.isEmpty, line)
        }
        XCTAssertEqual(applied("hepatitis A").hx.hepatitisTypes, ["a"])
        XCTAssertEqual(applied("Hepatitis A infection").hx.hepatitisTypes, ["a"])
        XCTAssertEqual(applied("hep a").hx.hepatitisTypes, ["a"])
        XCTAssertEqual(applied("hep C").hx.hepatitisTypes, ["c"])
    }

    /// A templated social history's answer after the item denies it.
    func testTemplatedDrugAnswersAreNegative() {
        for line in ["Illicit drugs: denies.", "Marijuana use: Never.", "Cocaine: never", "Illicit drug use: n/a"] {
            let p = problems(line)
            XCTAssertTrue(p.isDisjoint(with: ["problem:substance", "problem:marijuana", "problem:cocaine"]), line + " → " + p.sorted().joined(separator: ", "))
        }
        XCTAssertTrue(problems("marijuana use daily").isSuperset(of: ["problem:marijuana", "problem:substance"]))
    }

    /// The operation under a procedure heading is the one planned, not a history of it.
    func testPlannedBypassUnderAProcedureHeading() {
        for line in ["Procedure: Laparoscopic Roux-en-Y gastric bypass", "Planned procedure: RYGB", "45F, BMI 44. Procedure: lap RYGB"] {
            XCTAssertFalse(problems(line).contains("problem:gastric-bypass"), line)
        }
        XCTAssertTrue(problems("Prior surgery: RYGB 2015").contains("problem:gastric-bypass"))
        XCTAssertTrue(problems("h/o gastric bypass").contains("problem:gastric-bypass"))
    }

    /// A repaired hiatal hernia is the repair, written before the hernia or after a comma or "s/p".
    func testRepairedHiatalHernia() {
        for line in ["PSH: s/p laparoscopic repair of paraesophageal hernia 2018", "hiatal hernia, repaired 2019", "hiatal hernia s/p Nissen",
                     "hiatal hernia (repaired)"] {
            XCTAssertFalse(problems(line).contains("problem:hiatal-hernia"), line)
        }
        XCTAssertTrue(problems("large hiatal hernia with reflux").contains("problem:hiatal-hernia"))
    }

    /// An AV fistula that is not a dialysis access, or one being made today, is not the Renal page's access.
    func testFistulaNotADialysisAccess() {
        for line in ["Spinal dural AVF s/p embolization 2019", "coronary AV fistula", "Procedure: Left brachiocephalic AV fistula",
                     "72M CKD 5 for left AVF under regional"] {
            let r = applied(line)
            XCTAssertTrue(r.hx.dialysisAccess.isEmpty, line)
            XCTAssertEqual(r.hx.fistulaSite, "", line)
        }
        XCTAssertEqual(applied("ESRD on HD MWF via L arm AVF").hx.fistulaSite, "L arm")
        XCTAssertEqual(applied("Left brachiocephalic AVF, on HD").hx.fistulaSite, "Left brachiocephalic")
    }

    /// "fx" as function is not a fracture.
    func testFxAsFunction() {
        for line in ["Echo: normal LV fx, EF 60%", "Renal fx stable", "normal lung fx on PFTs"] {
            XCTAssertFalse(problems(line).contains("problem:fracture"), line)
        }
        XCTAssertTrue(problems("R hip fx").contains("problem:fracture"))
        XCTAssertTrue(problems("s/p fall with pelvic fx").contains("problem:fracture"))
    }

    /// OCD as osteochondritis dissecans and OA as occiput anterior.
    func testOsteochondritisAndOcciputAnterior() {
        XCTAssertFalse(problems("Procedure: R knee arthroscopy, drilling of OCD lesion").contains("problem:psych"))
        XCTAssertFalse(problems("SVE 6/90/0, vertex OA").contains("problem:oa"))
        XCTAssertTrue(problems("OCD on fluoxetine").contains("problem:psych"))
        XCTAssertTrue(problems("bilateral knee OA").contains("problem:oa"))
    }

    /// The specific hint wins over the generic words: Huntington before hemodialysis, Ehlers-Danlos before fatigue.
    func testSpecificAbbreviationHintsComeFirst() {
        let hd = "Huntington disease (HD) with chorea, PICC catheter in place"
        XCTAssertEqual(meaning("HD", in: hd), "Huntington disease")
        XCTAssertFalse(problems(hd).contains("problem:esrd-dialysis"))
        XCTAssertEqual(meaning("HD", in: "HD MWF via L arm AVF"), "hemodialysis")
        let eds = "EDS (hypermobile type) with chronic fatigue"
        XCTAssertEqual(meaning("EDS", in: eds), "Ehlers-Danlos syndrome")
        XCTAssertTrue(problems(eds).contains("problem:eds"))
        XCTAssertEqual(meaning("EDS", in: "EDS, OSA on CPAP"), "excessive daytime sleepiness")
        XCTAssertEqual(meaning("EDS", in: "EDS with chronic fatigue"), "excessive daytime sleepiness")
    }

    /// Colour blindness is not visual impairment.
    func testColorBlindIsNotVisualImpairment() {
        for line in ["Color blind, wears glasses", "colour blindness", "red-green color-blind"] {
            XCTAssertFalse(problems(line).contains("problem:visual-impairment"), line)
        }
        XCTAssertTrue(problems("legally blind").contains("problem:visual-impairment"))
    }

    /// NKDA never hides an allergy on the 1.9 list, from a note or the quick-add bar.
    func testNKDADoesNotOverrideTheAllergyList() {
        let rec = latex()
        guard let f = read("NKDA").findings.first(where: { $0.id == "nkda" }) else { return XCTFail("NKDA not read") }
        guard case .conflicts(let why) = PatientNote.status(f, in: rec) else { return XCTFail("NKDA over a listed allergy is a conflict") }
        XCTAssertTrue(why.contains("Latex"), why)
        XCTAssertFalse(applied("NKDA", to: rec).nkda)
        var q = rec
        PatientNote.apply(QuickAdd.read("nkda", record: rec, tab: .preop, now: now).findings.map(\.change), to: &q)
        XCTAssertFalse(q.nkda)
        XCTAssertEqual(q.allergyList.map(\.name), ["Latex"])
        XCTAssertEqual(PatientNote.status(f, in: PatientRecord()), .new)
        XCTAssertTrue(applied("NKDA").nkda)
    }

    /// "Still missing" counts the 1.9 medication and allergy lists.
    func testMissingCountsTheLists() {
        var r = latex()
        r.homeMeds = [PatientMed(name: "Amlodipine", dose: "5 daily")]
        let missing = PatientNote.missing(r)
        XCTAssertFalse(missing.contains("medications"), missing.joined(separator: ", "))
        XCTAssertFalse(missing.contains("allergies"), missing.joined(separator: ", "))
        let empty = PatientNote.missing(PatientRecord())
        XCTAssertTrue(empty.contains("medications") && empty.contains("allergies"))
    }
}
