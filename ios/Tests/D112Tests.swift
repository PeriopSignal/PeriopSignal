import XCTest
@testable import PeriopSignal

/// 1.12, helper D (medications): note 16 (one Current Medications & Infusions box, listed infusions, antibiotics,
/// cardiovascular, the rest; the handoff drops a drip deleted in the room), note 2 (the row's new title), note 3 (the
/// antibiotics charted in Case Timers, read-only, with times), note 18 (notable medications as chips with doses).
final class D112Tests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func timerData() throws -> CaseTimerData {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        return try XCTUnwrap(ReferenceLoader.decode(try Data(contentsOf: url)).caseTimers, "caseTimers decodes")
    }

    private func block(_ blocks: [SummaryBlock], _ key: String) throws -> SummaryBlock {
        try XCTUnwrap(blocks.first { $0.key == key }, "block \(key) in \(blocks.map(\.key))")
    }

    private func meds(_ line: String) -> [PatientMed] { MedicationCatalog.parse(line) }

    // MARK: Note 16: the groups

    func testTheCatalogsClassesTellAntibioticsFromCardiovascularFromTheRest() {
        for c in ["Cephalosporin (first generation, IV)", "Penicillin antibiotic", "Penicillin + beta-lactamase inhibitor", "Macrolide antibiotic",
                  "Glycopeptide antibiotic", "Urinary antibacterial", "Carbapenem antibiotic"] {
            XCTAssertEqual(MedicationCatalog.group(drugClass: c), .antibiotics, c)
        }
        for c in ["Beta-blocker (beta-1 selective)", "ACE inhibitor", "Angiotensin II receptor blocker (ARB)", "ARB + thiazide diuretic",
                  "Calcium channel blocker (dihydropyridine)", "Loop diuretic", "Nitrate", "Antiarrhythmic (class III)", "Cardiac glycoside",
                  "Direct oral anticoagulant", "Low-molecular-weight heparin", "P2Y12 inhibitor (antiplatelet)", "Statin (HMG-CoA reductase inhibitor)",
                  "Central alpha-2 agonist"] {
            XCTAssertEqual(MedicationCatalog.group(drugClass: c), .cardiovascular, c)
        }
        // Letters inside another word are not a class: "carbonic" holds "arb", "somatostatin" holds "statin"; eye drops, the
        // bladder and a muscle relaxant of the same name are not cardiovascular; an antituberculosis agent is not an antibiotic here.
        for c in ["Carbonic anhydrase inhibitor", "Somatostatin analog", "Beta-blocker eye drops (glaucoma)", "Bladder protectant (weak anticoagulant effect on its label)",
                  "Central alpha-2 agonist (muscle relaxant)", "SSRI", "Thyroid hormone (T4)", "Antituberculosis agent", "Azole antifungal", "Alpha-1 blocker (BPH)"] {
            XCTAssertEqual(MedicationCatalog.group(drugClass: c), .other, c)
        }
    }

    func testAMedicationTheCatalogDoesNotClassIsOther() {
        XCTAssertEqual(MedicationCatalog.group(of: PatientMed(name: "Zorblax")), .other)
        XCTAssertEqual(MedicationCatalog.group(of: PatientMed(name: "Cefazolin")), .antibiotics, "found by its name")
        XCTAssertEqual(MedicationCatalog.group(of: PatientMed(name: "Metoprolol")), .cardiovascular)
        XCTAssertEqual(MedicationCatalog.group(of: PatientMed(name: "Sertraline")), .other)
    }

    func testTheListIsAntibioticsThenCardiovascularThenTheRestEachInTheOrderEntered() {
        let list = meds("sertraline 50, metoprolol 25 bid, cefazolin, levothyroxine 75, lisinopril 10, amoxicillin")
        XCTAssertEqual(list.count, 6, list.map(\.text).joined(separator: " | "))
        let ordered = MedicationCatalog.ordered(list)
        XCTAssertEqual(ordered.map { MedicationCatalog.group(of: $0) }, [.antibiotics, .antibiotics, .cardiovascular, .cardiovascular, .other, .other])
        let names = ordered.map { $0.name.lowercased() }
        XCTAssertTrue(names[0].hasPrefix("cefazolin") && names[1].hasPrefix("amoxicillin"), "antibiotics in the order entered: \(names)")
        XCTAssertTrue(names[2].hasPrefix("metoprolol") && names[3].hasPrefix("lisinopril"), "cardiovascular in the order entered: \(names)")
        XCTAssertTrue(names[4].hasPrefix("sertraline") && names[5].hasPrefix("levothyroxine"), "the rest in the order entered: \(names)")
        XCTAssertEqual(Set(ordered.map(\.id)), Set(list.map(\.id)), "nothing lost or doubled")
    }

    // MARK: Note 16: one type line

    func testTheLineSplitsIntoMedicationsAndInfusions() {
        let m = InfusionEntry.mixed("metoprolol 25 bid, norepi 0.05, heparin 1200 units/h")
        XCTAssertEqual(m.medications, "metoprolol 25 bid")
        XCTAssertEqual(m.infusions, "norepi 0.05, heparin 1200 units/h")
        let read = InfusionEntry.read(m.infusions)
        XCTAssertEqual(read.items.map(\.drug), ["Norepinephrine", "Heparin"])
        XCTAssertEqual(read.items[1].rate, "1200 units/h")
        XCTAssertTrue(read.questions.isEmpty)
        XCTAssertEqual(MedicationCatalog.parse(m.medications).count, 1)
        // Drips run together without a comma still split ("norepi 0.05 vaso 0.04").
        XCTAssertEqual(InfusionEntry.mixed("norepi 0.05 vaso 0.04").infusions, "norepi 0.05, vaso 0.04")
        XCTAssertEqual(InfusionEntry.mixed("").medications + InfusionEntry.mixed("").infusions, "")
    }

    func testAKnownDripWithARateOrADripOnlyDrugIsAnInfusion() {
        for piece in ["norepi 0.05", "norepinephrine", "propofol", "epi 0.05", "phenylephrine 40 mcg/min", "heparin 1200 units/h", "insulin 4 units/h",
                      "nitroglycerin 0.5 mcg/kg/min", "furosemide 5 mg/h", "levo 0.05 mcg/kg/min", "vaso 0.04", "milrinone 0.25", "nitric oxide 20 ppm"] {
            XCTAssertTrue(InfusionEntry.isInfusion(piece), piece)
        }
    }

    func testAnythingElseIsAMedicationAsBefore() {
        for piece in ["metoprolol 25 bid", "lisinopril 10", "furosemide 40 mg", "furosemide", "heparin", "heparin 5000 units sq tid", "insulin glargine 20 units",
                      "insulin", "nitroglycerin 5", "levo 0.05", "dex 4 mg", "txa 1 g", "norepi 0.05 mg", "apixaban 5 bid", "xyzolol 10", "Eliquis"] {
            XCTAssertFalse(InfusionEntry.isInfusion(piece), piece)
        }
    }

    func testEveryPieceTypedIsReadAsOneOrTheOther() {
        let line = "metoprolol 25 bid, norepi 0.05, furosemide 40 mg, heparin 1200 units/h, sertraline 50, insulin 4 units/h"
        let pieces = InfusionEntry.pieces(line)
        let m = InfusionEntry.mixed(line)
        XCTAssertEqual(pieces.count, 6)
        XCTAssertEqual(InfusionEntry.pieces(m.medications).count + InfusionEntry.pieces(m.infusions).count, 6, "nothing dropped")
        XCTAssertEqual(InfusionEntry.pieces(m.infusions).count, 3)
    }

    func testFilingTheLineWritesTheTwoListsStorageUnchanged() throws {
        var r = PatientRecord()
        let m = InfusionEntry.mixed("metoprolol 25 bid, norepi 0.05, heparin 1200 units/h, cefazolin")
        MedicationCatalog.apply(MedicationCatalog.parse(m.medications), to: &r.homeMeds)
        InfusionEntry.apply(InfusionEntry.read(m.infusions).items, to: &r.homeInfusions)
        XCTAssertEqual(r.homeMeds.count, 2)
        XCTAssertEqual(r.homeInfusions.map(\.drug), ["Norepinephrine", "Heparin"])
        XCTAssertEqual(r.homeInfusions[1].rate, "1200 units/h")
        // The same JSON keys as before, so a saved record opens as it was.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        XCTAssertEqual((json["homeMeds"] as? [Any])?.count, 2)
        XCTAssertEqual((json["homeInfusions"] as? [Any])?.count, 2)
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.homeMeds, r.homeMeds)
        XCTAssertEqual(back.homeInfusions, r.homeInfusions)
    }

    @MainActor func testTheBoxAndTheSectionAreNamedForBoth() {
        XCTAssertEqual(CurrentMedicationsBox.title, "Current Medications & Infusions")
        XCTAssertEqual(PreopSection.medications.sectionTitle, "Current Medications & Infusions")
        XCTAssertEqual(PatientEditor.medications.title, "Medications & Allergies", "the page keeps its name")
    }

    // MARK: Note 16: the summaries follow the same order

    func testThePreprocedureSummaryTellsTheInfusionsThenTheMedicationsInTheBoxOrder() throws {
        var r = PatientRecord()
        r.homeMeds = meds("sertraline 50, metoprolol 25 bid, cefazolin")
        r.homeInfusions = [PatientInfusion(drug: "Norepinephrine", rate: "0.1 mcg/kg/min")]
        let b = try block(PatientBriefs.preop(r), "meds")
        XCTAssertEqual(b.lines.count, 2, b.text)
        XCTAssertEqual(b.lines[0], "Infusions: Norepinephrine at 0.1 mcg/kg/min")
        let home = b.lines[1]
        XCTAssertTrue(home.hasPrefix("Home: Cefazolin"), home)
        let c = try XCTUnwrap(home.range(of: "Cefazolin")?.lowerBound), m = try XCTUnwrap(home.range(of: "Metoprolol")?.lowerBound),
            s = try XCTUnwrap(home.range(of: "Sertraline")?.lowerBound)
        XCTAssertTrue(c < m && m < s, "antibiotics, cardiovascular, the rest: \(home)")
        XCTAssertTrue(b.alert, "the infusions stay an alert")
    }

    func testTheHandoffsMedicationLineFollowsTheSameOrder() throws {
        var r = PatientRecord()
        r.homeMeds = meds("sertraline 50, metoprolol 25 bid, cefazolin")
        let text = try block(PatientBriefs.handoff(r), "meds").text
        let c = try XCTUnwrap(text.range(of: "Cefazolin")?.lowerBound), m = try XCTUnwrap(text.range(of: "Metoprolol")?.lowerBound),
            s = try XCTUnwrap(text.range(of: "Sertraline")?.lowerBound)
        XCTAssertTrue(c < m && m < s, text)
    }

    func testAMedicationLineWithNoListStaysAsItWas() throws {
        var r = PatientRecord()
        r.medFlags = ["anticoagulant"]
        let flags = try XCTUnwrap(PatientCatalog.medFlags.first { $0.id == "anticoagulant" }?.label)
        let b = try block(PatientBriefs.preop(r), "meds")
        XCTAssertEqual(b.text, flags)
        XCTAssertTrue(b.marks.contains(flags))
    }

    func testADripDeletedInTheRoomIsNotACurrentInfusionInTheHandoffButStaysInThePreopSummary() throws {
        var r = PatientRecord()
        r.homeInfusions = [PatientInfusion(drug: "Epinephrine", rate: "0.05 mcg/kg/min"), PatientInfusion(drug: "Norepinephrine", rate: "0.1 mcg/kg/min")]
        IntraopInfusionList.remove(r.homeInfusions[0].id, in: &r)
        XCTAssertEqual(IntraopInfusionList.takenOff(r), [r.homeInfusions[0].id])
        let hand = try block(PatientBriefs.handoff(r), "infusions").text
        XCTAssertFalse(hand.contains("Epinephrine at 0.05"), hand)
        XCTAssertTrue(hand.contains("Norepinephrine at 0.1 mcg/kg/min"), hand)
        // The Preprocedure Summary describes the patient on arrival, and so does the preop box.
        let pre = try block(PatientBriefs.preop(r), "meds").text
        XCTAssertTrue(pre.contains("Epinephrine at 0.05 mcg/kg/min"), pre)
        XCTAssertTrue(pre.contains("Norepinephrine at 0.1 mcg/kg/min"), pre)
        XCTAssertEqual(r.homeInfusions.map(\.drug), ["Epinephrine", "Norepinephrine"])
        // Taking the last one off leaves the handoff with no infusion line at all.
        IntraopInfusionList.remove(r.homeInfusions[1].id, in: &r)
        XCTAssertFalse(PatientBriefs.handoff(r).contains { $0.key == "infusions" })
        // A drip left alone is still told as before.
        var s = PatientRecord()
        s.homeInfusions = [PatientInfusion(drug: "Heparin", rate: "1200 units/h")]
        XCTAssertTrue(try block(PatientBriefs.handoff(s), "infusions").text.contains("Heparin at 1200 units/h"))
    }

    // MARK: Note 2: the row's title

    @MainActor func testTheRowIsTitledAntibioticsAndNotableMedicationsAndItsPageKeepsItsName() {
        XCTAssertEqual(IntraopNotableMedicationLink.title, "Antibiotics & Notable Medications")
        XCTAssertEqual(PatientEditor.intraopPart("meds").title, "Medications & Interventions")
    }

    @MainActor func testTheEmptyRowsHintFitsOneLineOnA375PointPhone() {
        let width = (IntraopNotableMedicationLink.hint as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: PreopEmptyHints.hintFontSize)]).width
        XCTAssertLessThanOrEqual(width, PreopEmptyHints.hintRoomAt375)
    }

    // MARK: Note 3: the antibiotics charted in Case Timers

    private func adult(_ kg: Double = 80) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 60; r.sex = .male; r.heightCm = 178; r.weightKg = kg
        return r
    }

    func testAnAntibioticIsToldWithItsDoseTheLastDoseAndTheNextRedose() throws {
        let d = try timerData()
        var r = adult()
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0)])]
        let now = t0.addingTimeInterval(1800)
        let lines = CaseAntibiotics.lines(r, data: d, now: now)
        XCTAssertEqual(lines.count, 1)
        let l = lines[0]
        let last = PatientSummary.time(t0, now: now), next = PatientSummary.time(t0.addingTimeInterval(4 * 3600), now: now)
        XCTAssertEqual(l.tabText, "Cefazolin 2 g · last \(last) · next due \(next)")
        XCTAssertEqual(l.handoffText, "Cefazolin 2 g, last \(last), next due \(next)")
        XCTAssertEqual(l.next, t0.addingTimeInterval(4 * 3600))
        XCTAssertFalse(l.overdue)
    }

    func testTheDoseIsTheOneCaseTimersHolds() throws {
        let d = try timerData()
        var r = adult(130)
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0)])]
        XCTAssertTrue(CaseAntibiotics.lines(r, data: d, now: t0)[0].tabText.hasPrefix("Cefazolin 3 g"), "3 g from 120 kg, as Case Timers says")
    }

    func testADrugWithNoRoutineRedoseSaysSo() throws {
        let d = try timerData()
        var r = adult()
        r.timers.antibiotics = [AntibioticCourse(drug: "ceftriaxone", doses: [TimedEntry(time: t0)])]
        let l = CaseAntibiotics.lines(r, data: d, now: t0.addingTimeInterval(600))[0]
        XCTAssertNil(l.next)
        XCTAssertTrue(l.tabText.hasSuffix(" · no routine redose"), l.tabText)
        XCTAssertTrue(l.handoffText.hasSuffix(", no routine redose"), l.handoffText)
        XCTAssertFalse(l.overdue)
        // A redose timer stopped in Case Timers (interval 0) has none either; one set to another interval uses it.
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0)], everyMinutes: 0)]
        XCTAssertNil(CaseAntibiotics.lines(r, data: d, now: t0)[0].next)
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0)], everyMinutes: 180)]
        XCTAssertEqual(CaseAntibiotics.lines(r, data: d, now: t0)[0].next, t0.addingTimeInterval(3 * 3600))
    }

    @MainActor func testAnOverdueRedoseIsRedFiveMinutesAfterItsTimeAsCaseTimersCountsIt() throws {
        let d = try timerData()
        var r = adult()
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0)])]
        XCTAssertFalse(CaseAntibiotics.lines(r, data: d, now: t0.addingTimeInterval(4 * 3600 - 60))[0].overdue, "not yet due")
        XCTAssertFalse(CaseAntibiotics.lines(r, data: d, now: t0.addingTimeInterval(4 * 3600 + 120))[0].overdue, "due, not yet overdue")
        XCTAssertTrue(CaseAntibiotics.lines(r, data: d, now: t0.addingTimeInterval(4 * 3600 + 600))[0].overdue)
        // The row on the tab draws it as an alert line (red); the others are not.
        let row = IntraopNotableMedicationLink.lines(r, antibiotics: CaseAntibiotics.lines(r, data: d, now: t0.addingTimeInterval(4 * 3600 + 600)))
        XCTAssertTrue(row[0].alert)
        let ontime = IntraopNotableMedicationLink.lines(r, antibiotics: CaseAntibiotics.lines(r, data: d, now: t0.addingTimeInterval(600)))
        XCTAssertFalse(ontime[0].alert)
    }

    func testTheLastDoseGivenIsTheOneToldAndACourseWithNoDoseIsLeftOut() throws {
        let d = try timerData()
        var r = adult()
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0), TimedEntry(time: t0.addingTimeInterval(4 * 3600))]),
                                AntibioticCourse(drug: "vancomycin", doses: [])]
        let lines = CaseAntibiotics.lines(r, data: d, now: t0.addingTimeInterval(5 * 3600))
        XCTAssertEqual(lines.map(\.id), ["cefazolin"])
        XCTAssertEqual(lines[0].next, t0.addingTimeInterval(8 * 3600), "the redose runs from the last dose")
        XCTAssertTrue(CaseAntibiotics.lines(adult(), data: d, now: t0).isEmpty)
    }

    func testSeveralAntibioticsEachHaveTheirOwnLine() throws {
        let d = try timerData()
        var r = adult()
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0)]),
                                AntibioticCourse(drug: "metronidazole", doses: [TimedEntry(time: t0.addingTimeInterval(300))])]
        let lines = CaseAntibiotics.lines(r, data: d, now: t0.addingTimeInterval(900))
        XCTAssertEqual(lines.map(\.name), ["Cefazolin", "Metronidazole"])
        XCTAssertEqual(lines[1].dose, "500 mg")
    }

    func testTheHandoffsMedicationBlockCarriesTheAntibioticsAlongsideTheTypedFreeText() throws {
        let d = try timerData()
        CaseAntibiotics.override = d
        defer { CaseAntibiotics.override = nil }
        var r = adult()
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0)])]
        r.medsGiven = "Cefazolin 2 g at 08:10 (before Case Timers)"
        r.infusions = [PatientInfusion(drug: "Phenylephrine", rate: "0.3 mcg/kg/min")]
        let now = t0.addingTimeInterval(1800)
        let b = try block(PatientBriefs.handoff(r, now: now), "infusions")
        let last = PatientSummary.time(t0, now: now), next = PatientSummary.time(t0.addingTimeInterval(4 * 3600), now: now)
        XCTAssertEqual(b.lines, ["Infusions: Phenylephrine at 0.3 mcg/kg/min",
                                 "Antibiotics: Cefazolin 2 g, last \(last), next due \(next)",
                                 "Intraop medications: Cefazolin 2 g at 08:10 (before Case Timers)"], "both shown, not merged")
        XCTAssertTrue(b.marks.isEmpty, "on time")
        // Overdue: the line is marked red.
        let late = try block(PatientBriefs.handoff(r, now: t0.addingTimeInterval(4 * 3600 + 900)), "infusions")
        XCTAssertEqual(late.marks.count, 1)
        XCTAssertTrue(late.text.contains(late.marks[0]), "the marked words are in the text")
        XCTAssertTrue(late.marks[0].hasPrefix("Cefazolin 2 g, last "))
        // And it is in the copied text.
        XCTAssertTrue(PatientBriefs.plainText([b]).contains("Antibiotics: Cefazolin 2 g, last"))
    }

    @MainActor func testTheTabsRowListsTheAntibioticsTheChipsAndTheFreeText() throws {
        let d = try timerData()
        var r = adult()
        r.timers.antibiotics = [AntibioticCourse(drug: "cefazolin", doses: [TimedEntry(time: t0)])]
        r.notableMeds.toggle("txa"); r.notableMeds.setDose("txa", "1 g")
        r.notableMeds.toggle("milrinoneBolus")
        r.medsGiven = "dexamethasone 4 mg"
        let lines = IntraopNotableMedicationLink.lines(r, antibiotics: CaseAntibiotics.lines(r, data: d, now: t0.addingTimeInterval(600)))
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].text.hasPrefix("Cefazolin 2 g · last "))
        XCTAssertEqual(lines[1].text, "Milrinone bolus; TXA 1 g", "Ben's order, not the order chosen in")
        XCTAssertEqual(lines[2].text, "Dexamethasone 4 mg")
        XCTAssertTrue(IntraopNotableMedicationLink.lines(adult(), antibiotics: []).isEmpty, "empty while nothing is recorded: the hint shows")
    }

    // MARK: Note 18: notable medications as chips with doses

    func testTheChipsAreBensNineInHisOrder() {
        XCTAssertEqual(PatientNotableMeds.options.map(\.label),
                       ["Milrinone bolus", "Inhaled milrinone", "TXA", "Amicar", "PCC", "Fibrinogen concentrate", "Factor VIIa", "Cyanokit", "Methylene blue"])
        XCTAssertEqual(Array(PatientNotableMeds.options.map(\.full)[3...7]), ["Amicar (aminocaproic acid)", "PCC (Kcentra)", "Fibrinogen concentrate",
                                                                      "Factor VIIa (NovoSeven)", "Cyanokit (hydroxocobalamin)"])
        XCTAssertEqual(Set(PatientNotableMeds.options.map(\.id)).count, 9, "unique ids")
        XCTAssertFalse(PatientNotableMeds.options.contains { $0.id.lowercased().contains("dobut") || $0.label.lowercased().contains("dobut") }, "dobutamine is an infusion only")
        XCTAssertNotNil(InfusionEntry.drug(id: "dobutamine"))
    }

    func testAChipIsChosenWithNoDoseAndASecondTapClearsItWithItsDose() {
        var m = PatientNotableMeds()
        XCTAssertTrue(m.isEmpty)
        m.toggle("txa")
        XCTAssertTrue(m.has("txa"))
        XCTAssertEqual(m.dose("txa"), "", "no default dose")
        XCTAssertEqual(m.items, ["TXA"])
        m.setDose("txa", "1 g")
        XCTAssertEqual(m.items, ["TXA 1 g"])
        m.setDose("pcc", "1500 units")
        XCTAssertFalse(m.has("pcc"), "a dose is only typed beside a chosen chip")
        m.toggle("txa")
        XCTAssertTrue(m.isEmpty)
        m.toggle("txa")
        XCTAssertEqual(m.dose("txa"), "", "chosen again: the old dose is gone")
    }

    func testTheChosenChipsAreToldInBensOrderWhateverOrderTheyWereChosenIn() {
        var m = PatientNotableMeds()
        for id in ["methyleneBlue", "txa", "milrinoneBolus", "pcc"] { m.toggle(id) }
        m.setDose("pcc", "25 units/kg")
        XCTAssertEqual(m.items, ["Milrinone bolus", "TXA", "PCC 25 units/kg", "Methylene blue"])
    }

    @MainActor func testNoDoseIsPrintedOrSuggestedAnywhereOnThePage() {
        let words = PatientNotableMeds.options.flatMap { [$0.label, $0.full] } + [IntraopMedicationsPage.notableNote, IntraopNotableMedicationLink.hint]
        for w in words {
            XCTAssertNil(w.range(of: #"\d\s*(?:mg|mcg|g|units)\b"#, options: .regularExpression), "no dose in: \(w)")
        }
        var m = PatientNotableMeds()
        for o in PatientNotableMeds.options { m.toggle(o.id) }
        XCTAssertTrue(m.entries.allSatisfy { $0.dose.isEmpty })
    }

    func testAMilrinoneBolusOrInhaledMilrinoneIsNotAnInfusion() throws {
        var r = PatientRecord()
        r.notableMeds.toggle("milrinoneBolus"); r.notableMeds.toggle("milrinoneInhaled")
        XCTAssertTrue(r.infusions.isEmpty)
        XCTAssertTrue(r.homeInfusions.isEmpty)
        XCTAssertTrue(IntraopInfusionList.rows(r).isEmpty)
        let b = try block(PatientBriefs.handoff(r), "infusions")
        XCTAssertEqual(b.text, "Intraop medications: Milrinone bolus; Inhaled milrinone")
        XCTAssertFalse(b.text.contains("Infusions:"))
    }

    func testTheHandoffListsTheChosenChipsWithTheirDosesBeforeTheFreeTextAndTheFactors() throws {
        var r = PatientRecord()
        r.notableMeds.toggle("txa"); r.notableMeds.setDose("txa", "1 g")
        r.notableMeds.toggle("amicar")
        r.medsGiven = "Dexamethasone 4 mg"
        r.factors = "Fibrinogen 2 g"
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "infusions").text, "Intraop medications: TXA 1 g; Amicar; Dexamethasone 4 mg; Fibrinogen 2 g")
    }

    func testARecordRoundTripsAndAOneElevenRecordOpensWithNoChips() throws {
        var r = PatientRecord()
        r.notableMeds.toggle("txa"); r.notableMeds.setDose("txa", "1 g")
        r.notableMeds.toggle("cyanokit")
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.notableMeds, r.notableMeds)
        XCTAssertEqual(back.notableMeds.items, ["TXA 1 g", "Cyanokit"])
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"procedure":"CABG","medsGiven":"TXA 1 g; steroids"}"#.utf8))
        XCTAssertTrue(old.notableMeds.isEmpty)
        XCTAssertEqual(old.medsGiven, "TXA 1 g; steroids", "the text a 1.11 record holds is unchanged")
        // A damaged entry does not stop the record opening: the good ones are kept, an empty or repeated id is dropped.
        let odd = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"notableMeds":{"entries":[{"id":"txa","dose":"1 g"},{"id":""},{"dose":"x"},{"id":"txa","dose":"2 g"},{"id":"pcc"}]}}"#.utf8))
        XCTAssertEqual(odd.notableMeds.entries.map(\.id), ["txa", "pcc"])
        XCTAssertEqual(odd.notableMeds.dose("txa"), "1 g")
        let none = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"notableMeds":{}}"#.utf8))
        XCTAssertTrue(none.notableMeds.isEmpty)
    }

    // MARK: Note 18: what the page already recorded keeps working

    func testATXAEnteredInTheFreeTextBefore112ShowsAsTheChosenChipWithItsDose() throws {
        var r = PatientRecord()
        r.medsGiven = "Tranexamic acid 1 g load then 400 mg/h; methylprednisolone 500 mg"
        let s = PatientNotableMeds.pageState(r)
        XCTAssertEqual(s.entries.map(\.id), ["txa"])
        XCTAssertEqual(s.entries[0].dose, "1 g load then 400 mg/h")
        XCTAssertEqual(s.text, "methylprednisolone 500 mg", "the free text without that entry")
        // Until the page is changed the record and the summaries say what they always said.
        XCTAssertEqual(r.medsGiven, "Tranexamic acid 1 g load then 400 mg/h; methylprednisolone 500 mg")
        XCTAssertTrue(r.notableMeds.isEmpty)
        XCTAssertTrue(try block(PatientBriefs.handoff(r), "infusions").text.contains("Tranexamic acid 1 g load then 400 mg/h"))
        // The first change moves it into the chip.
        PatientNotableMeds.migrateLegacy(&r)
        XCTAssertEqual(r.notableMeds.items, ["TXA 1 g load then 400 mg/h"])
        XCTAssertEqual(r.medsGiven, "methylprednisolone 500 mg")
        let again = r
        PatientNotableMeds.migrateLegacy(&r)
        XCTAssertEqual(r, again, "moved once")
        XCTAssertEqual(PatientNotableMeds.lines(r), ["TXA 1 g load then 400 mg/h", "methylprednisolone 500 mg"])
    }

    func testTheLegacyTXAReadingIsNarrow() {
        XCTAssertEqual(PatientNotableMeds.legacyTXA(in: "TXA 1 g")?.dose, "1 g")
        XCTAssertEqual(PatientNotableMeds.legacyTXA(in: "txa: 1 g\nsteroids")?.rest, "steroids")
        XCTAssertEqual(PatientNotableMeds.legacyTXA(in: "Cefazolin; TXA")?.dose, "")
        XCTAssertEqual(PatientNotableMeds.legacyTXA(in: "Cefazolin; TXA")?.rest, "Cefazolin")
        XCTAssertNil(PatientNotableMeds.legacyTXA(in: "no TXA given"), "only an entry that starts with the drug")
        XCTAssertNil(PatientNotableMeds.legacyTXA(in: "TXAB 5"))
        XCTAssertNil(PatientNotableMeds.legacyTXA(in: ""))
        // A TXA chip already chosen keeps the text as it is.
        var r = PatientRecord()
        r.notableMeds.toggle("txa")
        r.medsGiven = "TXA 1 g"
        XCTAssertEqual(PatientNotableMeds.pageState(r).text, "TXA 1 g")
        PatientNotableMeds.migrateLegacy(&r)
        XCTAssertEqual(r.medsGiven, "TXA 1 g")
    }

    @MainActor func testTheFreeTextKeepsWorkingAndASavedElevenRecordShowsTheSameText() throws {
        var r = PatientRecord()
        r.medsGiven = "Dexamethasone 4 mg; reversal with sugammadex"
        XCTAssertEqual(PatientNotableMeds.pageState(r).text, r.medsGiven)
        XCTAssertTrue(PatientNotableMeds.pageState(r).entries.isEmpty)
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "infusions").text, "Intraop medications: " + r.capitalized.medsGiven)
        XCTAssertEqual(IntraopNotableMedicationLink.lines(r, antibiotics: []).map(\.text), [r.capitalized.medsGiven])
    }
}
