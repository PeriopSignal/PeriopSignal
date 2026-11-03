import XCTest
@testable import PeriopSignal

/// The Neurologic History page as an expanding page (1.8.2): Stroke or TIA with its timing, Intracranial bleed with mass
/// effect, the ids and scores that read them, the summary words, and what the note and quick-add readers file.
final class PatientNeuro182Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 8))! }

    private func read(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func ids(_ s: String) -> Set<String> { Set(read(s).findings.map(\.id)) }
    private func adult(_ problems: Set<String>) -> PatientRecord {
        var r = PatientRecord(); r.ageYears = 60; r.problems = problems
        return r
    }
    private func child(_ problems: Set<String>) -> PatientRecord {
        var r = PatientRecord(); r.ageYears = 8; r.problems = problems
        return r
    }
    private func applied(_ text: String, to start: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = start
        PatientNote.apply(read(text).findings.map(\.change), to: &r)
        return r
    }
    private func section(_ id: String) throws -> HistorySection { try XCTUnwrap(HistorySections.neuro.first { $0.id == id }, id) }
    private func neuroLine(_ r: PatientRecord) -> String? { PatientSummary.historyLines(r).first { $0.label == "Neurologic" }?.text }

    // MARK: The page

    func testPageOrderAndIds() throws {
        XCTAssertNotNil(HistorySections.sections("neuro"))
        XCTAssertEqual(HistorySections.neuro.map(\.title), [
            "Stroke or TIA", "Intracranial bleed", "Intracranial mass or raised ICP", "Seizure disorder", "Dementia or cognitive impairment",
            "Parkinson disease", "Neuromuscular disease", "Spinal cord injury", "Chronic pain or opioid tolerance", "Other",
        ])
        let neuro = try XCTUnwrap(PatientCatalog.systems.first { $0.id == "neuro" })
        let catalogIDs = Set(neuro.problems.map(\.id))
        let sectionIDs = Set(HistorySections.neuro.flatMap(\.members))
        XCTAssertEqual(catalogIDs, sectionIDs, "every neurologic id sits under one item, and every item's ids are in the catalog")
        for id in ["cva", "cva-recent", "cva-unspec", "ich-mass", "raised-icp", "seizure", "dementia", "parkinson", "neuromuscular", "sci", "chronic-pain"] {
            XCTAssertTrue(catalogIDs.contains(id), id + " keeps its id")
        }
        XCTAssertEqual(PatientCatalog.problem("cva-unspec")?.label, "Stroke or TIA, unspecified")
        XCTAssertEqual(PatientCatalog.problem("ich")?.label, "Intracranial bleed")
        XCTAssertEqual(PatientCatalog.problem("dementia")?.label, "Dementia or cognitive impairment")
        XCTAssertEqual(PatientCatalog.problem("sci")?.label, "Spinal cord injury")
        XCTAssertEqual(PatientCatalog.problem("chronic-pain")?.label, "Chronic pain or opioid tolerance")
        XCTAssertEqual(PatientCatalog.problem("cva-unspec")?.note, "ASA IV if within 3 months.", "the unspecified stroke keeps its note")
    }

    // MARK: Stroke or TIA

    func testStrokeTimingReplacesAndRestoresTheBase() throws {
        let stroke = try section("stroke")
        let timing = ["cva-recent", "cva"]
        var r = PatientRecord()
        HistorySections.select(stroke, &r)
        XCTAssertEqual(r.problems, ["cva-unspec"], "chosen alone: the timing is not recorded")
        XCTAssertEqual(PatientRules.asaSuggestion(adult(r.problems))?.level, 3)
        HistorySections.choose("cva-recent", among: timing, in: stroke, &r)
        XCTAssertEqual(r.problems, ["cva-recent"], "within 3 months replaces the base")
        XCTAssertEqual(PatientRules.asaSuggestion(adult(r.problems))?.level, 4)
        HistorySections.choose("cva", among: timing, in: stroke, &r)
        XCTAssertEqual(r.problems, ["cva"], "over 3 months takes its place")
        XCTAssertEqual(PatientRules.asaSuggestion(adult(r.problems))?.level, 3)
        HistorySections.choose("cva-recent", among: timing, in: stroke, &r)
        HistorySections.choose(nil, among: timing, in: stroke, &r)
        XCTAssertEqual(r.problems, ["cva-unspec"], "clearing the choice brings the base back")
        XCTAssertTrue(HistorySections.isSelected(stroke, system: "neuro", r))
        HistorySections.choose("cva-recent", among: timing, in: stroke, &r)
        HistorySections.clear(stroke, system: "neuro", &r)
        XCTAssertTrue(r.problems.isEmpty, "clearing the item removes all three ids")
        XCTAssertFalse(HistorySections.isSelected(stroke, system: "neuro", r))
        var all = adult(["cva-unspec", "cva", "cva-recent", "seizure"])
        HistorySections.clear(stroke, system: "neuro", &all)
        XCTAssertEqual(all.problems, ["seizure"], "only the stroke ids go")
    }

    func testStrokeStillFeedsTheScores() {
        for id in ["cva", "cva-recent", "cva-unspec"] {
            XCTAssertTrue(PatientRules.prefill("rcri", adult([id])).on.contains("cva"), id)
            XCTAssertTrue(PatientFunctional.ascvdProblems.contains(id), id)
            XCTAssertTrue(PatientFunctional.knownCVD(adult([id])), id)
        }
        XCTAssertTrue(PatientFunctional.riskModifiers(adult(["cva-recent"])).contains("stroke or TIA within 3 months"))
        XCTAssertTrue(PatientFunctional.conditionAdvice(adult(["cva-recent"])).contains { $0.hasPrefix("Stroke or TIA within 3 months") })
        XCTAssertFalse(PatientFunctional.riskModifiers(adult(["cva"])).contains("stroke or TIA within 3 months"))
    }

    // MARK: Intracranial bleed

    func testBleedWithMassEffect() throws {
        let ich = try section("ich")
        var r = PatientRecord()
        HistorySections.select(ich, &r)
        XCTAssertEqual(r.problems, ["ich"])
        XCTAssertNil(PatientRules.asaSuggestion(adult(r.problems)), "a bleed alone suggests no class")
        XCTAssertNil(PatientRules.asaSuggestion(child(r.problems)))
        HistorySections.setOption("ich-mass", true, in: ich, &r)
        XCTAssertEqual(r.problems, ["ich-mass"], "with mass effect replaces the bleed")
        XCTAssertEqual(PatientRules.asaSuggestion(adult(r.problems))?.level, 5)
        XCTAssertEqual(PatientRules.asaSuggestion(adult(r.problems))?.topFindings, ["Intracranial bleed with mass effect"])
        XCTAssertEqual(PatientRules.asaSuggestion(child(r.problems))?.level, 5)
        HistorySections.setOption("ich-mass", false, in: ich, &r)
        XCTAssertEqual(r.problems, ["ich"], "the option off: the bleed stays chosen")
        HistorySections.setOption("ich-mass", true, in: ich, &r)
        HistorySections.clear(ich, system: "neuro", &r)
        XCTAssertTrue(r.problems.isEmpty)
        XCTAssertNil(PatientCatalog.problem("ich")?.asa)
        XCTAssertNil(PatientCatalog.problem("ich")?.peds)
    }

    func testOtherItemsAreSingleChoices() throws {
        for id in ["raised-icp", "seizure", "dementia", "parkinson", "neuromuscular", "sci", "chronic-pain"] {
            let s = try section(id)
            XCTAssertEqual(s.base, id)
            XCTAssertEqual(s.members, [id])
            var r = PatientRecord()
            HistorySections.select(s, &r)
            XCTAssertEqual(r.problems, [id])
            HistorySections.clear(s, system: "neuro", &r)
            XCTAssertTrue(r.problems.isEmpty)
        }
        XCTAssertEqual(PatientRules.asaSuggestion(child(["seizure"]))?.level, 2, "pediatric seizure keeps its class")
        var other = PatientRecord()
        other.systemNotes["neuro"] = "On levetiracetam"
        XCTAssertTrue(HistorySections.isSelected(try section("other"), system: "neuro", other))
        HistorySections.clear(try section("other"), system: "neuro", &other)
        XCTAssertNil(other.systemNotes["neuro"])
    }

    // MARK: Summary words

    func testNeuroItemsWording() {
        XCTAssertEqual(HistorySections.neuroItems(adult(["cva-recent", "ich-mass", "seizure"])).joined(separator: "; "),
                       "stroke or TIA within 3 months; intracranial bleed with mass effect; seizure disorder")
        XCTAssertEqual(HistorySections.neuroItems(adult(["cva-unspec"])), ["stroke or TIA"], "the base alone")
        XCTAssertEqual(HistorySections.neuroItems(adult(["cva"])), ["stroke or TIA over 3 months"])
        XCTAssertEqual(HistorySections.neuroItems(adult(["ich"])), ["intracranial bleed"])
        XCTAssertEqual(HistorySections.neuroItems(adult(["raised-icp", "dementia", "parkinson", "neuromuscular", "sci", "chronic-pain"])),
                       ["intracranial mass or raised ICP", "dementia or cognitive impairment", "Parkinson disease", "neuromuscular disease",
                        "spinal cord injury", "chronic pain or opioid tolerance"])
        XCTAssertTrue(HistorySections.neuroItems(adult([])).isEmpty)
        let neuro = PatientCatalog.systems.first { $0.id == "neuro" }!
        XCTAssertEqual(HistorySections.items(neuro, adult(["cva-recent"])), ["stroke or TIA within 3 months"])
        XCTAssertEqual(neuroLine(adult(["cva-unspec", "ich"])), "stroke or TIA; intracranial bleed")
        var withNote = adult(["seizure"])
        withNote.systemNotes["neuro"] = "On levetiracetam"
        XCTAssertEqual(neuroLine(withNote), "seizure disorder; On levetiracetam", "Other is added by the summary")
    }

    func testDemoRoundTrips() throws {
        let r = PatientDemo.neuro
        XCTAssertEqual(try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r)), r)
        XCTAssertEqual(neuroLine(r), "stroke or TIA within 3 months; intracranial bleed with mass effect; seizure disorder; dementia or cognitive impairment; chronic pain or opioid tolerance; On levetiracetam")
    }

    // MARK: The readers

    func testNoteFilesPlainBleed() {
        for text in ["intracranial hemorrhage", "Subdural hematoma", "subarachnoid haemorrhage", "intracerebral bleed", "intracerebral hemorrhage 2 years ago",
                     "h/o intracranial bleed", "subdural haematoma"] {
            XCTAssertTrue(ids(text).contains("problem:ich"), text + " in " + ids(text).joined(separator: ","))
            XCTAssertFalse(ids(text).contains("problem:ich-mass"), text)
        }
        XCTAssertEqual(applied("intracranial hemorrhage").problems, ["ich"])
    }

    func testNoteBleedWithMassEffectFilesOnlyThat() {
        for text in ["subdural hematoma with midline shift", "intracerebral hemorrhage with mass effect", "subarachnoid hemorrhage with mass effect",
                     "epidural hematoma with midline shift"] {
            let found = ids(text)
            XCTAssertTrue(found.contains("problem:ich-mass"), text)
            XCTAssertFalse(found.contains("problem:ich"), text + ": the plain bleed is replaced")
        }
        XCTAssertEqual(applied("subdural hematoma with midline shift").problems, ["ich-mass"])
        var r = PatientRecord(); r.problems = ["ich"]
        PatientNote.apply([.problem("ich-mass")], to: &r)
        XCTAssertEqual(r.problems, ["ich-mass"], "applied over a plain bleed, it replaces it")
        PatientNote.apply([.problem("ich")], to: &r)
        XCTAssertEqual(r.problems, ["ich-mass"], "a plain bleed does not replace it back")
    }

    func testNoteBleedNegatedOrNotAboutThePatient() {
        for text in ["no intracranial hemorrhage", "denies subdural hematoma", "CT negative for intracranial bleed", "without intracranial hemorrhage",
                     "intracranial hemorrhage risk", "risk of intracranial hemorrhage", "risk of subdural hematoma", "spinal epidural hematoma",
                     "neuraxial epidural hematoma", "father had a subdural hematoma", "epidural bleed", "h/o epidural hematoma after epidural catheter removal"] {
            XCTAssertFalse(ids(text).contains("problem:ich"), text)
            XCTAssertFalse(ids(text).contains("problem:ich-mass"), text)
        }
        XCTAssertTrue(applied("no intracranial hemorrhage").problems.isEmpty)
    }

    func testQuickAddReadsBleed() {
        let q = QuickAdd.read("62M, subdural hematoma with midline shift, seizure, stroke 2 weeks ago", record: PatientRecord(), tab: .preop, now: now)
        let found = Set(q.findings.map(\.id))
        for id in ["problem:ich-mass", "problem:seizure", "problem:cva-recent"] { XCTAssertTrue(found.contains(id), id + " in " + found.joined(separator: ",")) }
        XCTAssertFalse(found.contains("problem:ich"))
        let plain = QuickAdd.read("70F, intracranial hemorrhage", record: PatientRecord(), tab: .preop, now: now)
        XCTAssertTrue(plain.findings.contains { $0.id == "problem:ich" })
    }

    func testStrokeNoteBehaviourIsUnchanged() {
        XCTAssertTrue(ids("h/o stroke").contains("problem:cva-unspec"))
        XCTAssertTrue(ids("stroke 2 weeks ago").contains("problem:cva-recent"))
        XCTAssertFalse(ids("stroke 2 weeks ago").contains("problem:cva-unspec"))
        var u = PatientRecord(); u.problems = ["cva-unspec"]
        PatientNote.apply([.problem("cva-recent")], to: &u)
        XCTAssertEqual(u.problems, ["cva-recent"])
    }

    /// A TIA reads like a stroke: no time is "Stroke or TIA, unspecified", a past time is over 3 months, a recent one within.
    func testTIAReadsLikeStroke() {
        for text in ["h/o TIA", "TIA", "prior transient ischemic attack"] {
            XCTAssertEqual(applied(text).problems, ["cva-unspec"], text)
        }
        for text in ["TIA 2019", "TIA 5 years ago", "TIA in 2015", "2018 TIA"] {
            XCTAssertEqual(applied(text).problems, ["cva"], text)
        }
        XCTAssertEqual(applied("TIA 2 weeks ago").problems, ["cva-recent"])
        XCTAssertEqual(applied("recent TIA").problems, ["cva-recent"])
        XCTAssertTrue(applied("no TIA").problems.isEmpty)
        XCTAssertTrue(applied("daughter Tia at bedside").problems.isEmpty, "a name, not the abbreviation")
    }
}
