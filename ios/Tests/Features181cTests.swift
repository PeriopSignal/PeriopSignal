import XCTest
import CoreGraphics
@testable import PeriopSignal

/// 1.8.1 My Patient features from Ben: Trivial regurgitation on echo, infusions typed in one line, the Foley among the
/// lines, Bio-Bentall and mechanical Bentall in the procedures, and the lines figure in the handoff.
final class Features181cTests: XCTestCase {
    /// 30 October 2026, 08:00 on the device's clock.
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))! }
    private func note(_ s: String, choices: [String: String] = [:]) -> PatientNoteReading { PatientNote.read(s, now: now, choices: choices) }
    private func ids(_ n: PatientNoteReading) -> Set<String> { Set(n.findings.map(\.id)) }
    private func quick(_ s: String, _ tab: QuickAddTab = .preop, choices: [String: String] = [:]) -> QuickAddReading {
        QuickAdd.read(s, record: PatientRecord(), tab: tab, now: now, choices: choices)
    }
    private func applied(_ q: QuickAddReading) -> PatientRecord {
        var r = PatientRecord()
        PatientNote.apply(q.findings.map(\.change), to: &r)
        return r
    }

    // MARK: 1. Trivial regurgitation

    func testTrivialIsARegurgitationGradeOnly() {
        XCTAssertEqual(EchoGrade.regurgitation, [.normal, .trivial, .mild, .moderate, .severe])
        XCTAssertEqual(EchoGrade.severities, [.normal, .mild, .moderate, .severe], "chamber function and stenosis have no trivial")
        XCTAssertEqual(EchoGrade.trivial.label, "Trivial")
        XCTAssertEqual(PatientEcho.function(.trivial), "normal")
    }

    func testTrivialSummaries() {
        var e = PatientEcho()
        e.mitral.regurgitation = .trivial
        e.tricuspid.regurgitation = .trivial
        e.aortic.regurgitation = .mild
        XCTAssertEqual(e.phrases, ["Trivial MR", "Trivial TR", "Mild AR"])
        e.study = "TEE"
        XCTAssertEqual(e.summary, "TEE: Trivial MR; Trivial TR; Mild AR")
        XCTAssertFalse(e.noValveDisease, "a grade other than none is shown, not folded into no valve disease")
    }

    func testEchoNormalPresetUnchanged() {
        var e = PatientEcho()
        e.mitral.regurgitation = .trivial
        e.applyNormal()
        XCTAssertEqual(e.mitral.regurgitation, .normal, "Echo normal still sets none")
        XCTAssertTrue(e.isNormalPreset)
        e.tricuspid.regurgitation = .trivial
        XCTAssertFalse(e.isNormalPreset)
    }

    func testTrivialSavesAndOldValuesStillOpen() throws {
        var e = PatientEcho()
        e.mitral.regurgitation = .trivial
        let data = try JSONEncoder().encode(e)
        XCTAssertEqual(try JSONDecoder().decode(PatientEcho.self, from: data).mitral.regurgitation, .trivial)
        let old = #"{"mitral":{"regurgitation":"mild","stenosis":"normal"}}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(PatientEcho.self, from: old).mitral.regurgitation, .mild)
    }

    func testNoteReadsTrivialAndTraceAsNotValveDisease() {
        for s in ["Echo: trivial MR", "TTE with trace MR", "trace mitral regurgitation", "trivial mitral regurgitation"] {
            XCTAssertFalse(ids(note(s)).contains("problem:mr"), s)
        }
        XCTAssertTrue(ids(note("mild MR")).contains("problem:mr"))
        XCTAssertTrue(ids(note("moderate mitral regurgitation")).contains("problem:mr"))
        XCTAssertTrue(ids(note("trivial MI")).isDisjoint(with: ["problem:cad", "problem:mi", "problem:cad-recent"]), "MI after trivial is mitral insufficiency")
        XCTAssertFalse(ids(note("TTE: trace TR, trivial PR")).contains("problem:valve-severe"))
    }

    func testTrivialPRIsTheValve() {
        func meaning(_ text: String) -> String? { MedAbbreviations.scan(text).first { $0.token == "PR" }?.meaning?.id }
        XCTAssertEqual(meaning("trivial PR"), "pr-pulmonic")
        XCTAssertEqual(meaning("trace PR"), "pr-pulmonic")
        XCTAssertEqual(meaning("mild PR"), "pr-pulmonic")
        XCTAssertEqual(meaning("PR interval prolonged on ECG"), "pr-interval")
    }

    // MARK: 2. Infusions typed in one line

    private func rates(_ s: String, choices: [String: String] = [:]) -> [String] { InfusionEntry.read(s, choices: choices).items.map(\.label) }

    func testAbbreviationsAndUnitsBySize() {
        XCTAssertEqual(rates("norepi 0.05"), ["Norepinephrine 0.05 mcg/kg/min"])
        XCTAssertEqual(rates("NE 4"), ["Norepinephrine 4 mcg/min"])
        XCTAssertEqual(rates("levophed .08"), ["Norepinephrine 0.08 mcg/kg/min"])
        XCTAssertEqual(rates("epi 0.03"), ["Epinephrine 0.03 mcg/kg/min"])
        XCTAssertEqual(rates("vaso 0.04"), ["Vasopressin 0.04 units/min"])
        XCTAssertEqual(rates("phenyl 50"), ["Phenylephrine 50 mcg/min"])
        XCTAssertEqual(rates("neo 0.5"), ["Phenylephrine 0.5 mcg/kg/min"])
        XCTAssertEqual(rates("milri 0.25"), ["Milrinone 0.25 mcg/kg/min"])
        XCTAssertEqual(rates("dobut 5"), ["Dobutamine 5 mcg/kg/min"])
        XCTAssertEqual(rates("dopa 3"), ["Dopamine 3 mcg/kg/min"])
        XCTAssertEqual(rates("NTG 50"), ["Nitroglycerin 50 mcg/min"])
        XCTAssertEqual(rates("nitro 20"), ["Nitroglycerin 20 mcg/min"])
        XCTAssertEqual(rates("nicardipine 5"), ["Nicardipine 5 mg/h"])
        XCTAssertEqual(rates("nicard 7.5"), ["Nicardipine 7.5 mg/h"])
        XCTAssertEqual(rates("clevidipine 2"), ["Clevidipine 2 mg/h"])
        XCTAssertEqual(rates("esmolol 100"), ["Esmolol 100 mcg/kg/min"])
        XCTAssertEqual(rates("SNP 0.5"), ["Nitroprusside 0.5 mcg/kg/min"])
        XCTAssertEqual(rates("propofol 75"), ["Propofol 75 mcg/kg/min"])
        XCTAssertEqual(rates("prop 50"), ["Propofol 50 mcg/kg/min"])
        XCTAssertEqual(rates("dexmed 0.7"), ["Dexmedetomidine 0.7 mcg/kg/h"])
        XCTAssertEqual(rates("dex 0.5"), ["Dexmedetomidine 0.5 mcg/kg/h"])
        XCTAssertEqual(rates("remi 0.1"), ["Remifentanil 0.1 mcg/kg/min"])
        XCTAssertEqual(rates("angiotensin II 20"), ["Angiotensin II 20 ng/kg/min"], "the catalog's unit")
        XCTAssertEqual(rates("iNO 20"), ["Nitric oxide, inhaled 20 ppm"])
        XCTAssertEqual(InfusionEntry.read("norepi 0.05").items.first?.note, "No unit written: read as mcg/kg/min.")
    }

    func testDrugsWithoutACatalogUnitAsk() {
        for (line, drug) in [("insulin 4", "insulin"), ("ketamine 0.5", "ketamine"), ("sufentanil 0.3", "sufentanil"),
                             ("heparin 1000", "heparin"), ("amio 1", "amiodarone")] {
            let r = InfusionEntry.read(line)
            XCTAssertTrue(r.items.isEmpty, line + ": no unit is made up")
            XCTAssertEqual(r.questions.first?.id.hasPrefix("unit:" + drug), true, line)
            XCTAssertEqual(r.questions.first?.options.last?.id, InfusionEntry.noUnit, line)
        }
        XCTAssertEqual(InfusionEntry.read("amio 1").questions.first?.text, "mg/min or mg/h or no unit")
        XCTAssertEqual(rates("insulin 4", choices: ["unit:insulin:4": "units/h"]), ["Insulin 4 units/h"])
        XCTAssertEqual(rates("insulin 4", choices: ["unit:insulin:4": InfusionEntry.noUnit]), ["Insulin 4"], "as typed, without a unit")
    }

    func testUnitsTypedAreKept() {
        XCTAssertEqual(rates("insulin 4 u/hr"), ["Insulin 4 units/h"])
        XCTAssertEqual(rates("heparin 1,000 units/h"), ["Heparin 1000 units/h"])
        XCTAssertEqual(rates("phenyl 0.5 mcg/kg/min"), ["Phenylephrine 0.5 mcg/kg/min"])
        XCTAssertEqual(rates("norepi 6 mcg/min"), ["Norepinephrine 6 mcg/min"])
        XCTAssertEqual(rates("epi 0.05 ug/kg/min"), ["Epinephrine 0.05 mcg/kg/min"])
        XCTAssertEqual(rates("ketamine 0.25 mg/kg/hr"), ["Ketamine 0.25 mg/kg/h"])
        XCTAssertEqual(rates("NTG gtt 50"), ["Nitroglycerin 50 mcg/min"])
        XCTAssertEqual(rates("vaso @ 0.03"), ["Vasopressin 0.03 units/min"])
        XCTAssertEqual(InfusionEntry.normalizedUnit("mcg/kg/m"), "mcg/kg/min")
        XCTAssertEqual(InfusionEntry.normalizedUnit("U/hr"), "units/h")
        XCTAssertNil(InfusionEntry.normalizedUnit("mcg/day"))
    }

    func testSeveralAtOnce() {
        XCTAssertEqual(rates("norepi 0.05, vaso 0.04"), ["Norepinephrine 0.05 mcg/kg/min", "Vasopressin 0.04 units/min"])
        XCTAssertEqual(rates("milri 0.25; epi 0.03 + NTG 50"), ["Milrinone 0.25 mcg/kg/min", "Epinephrine 0.03 mcg/kg/min", "Nitroglycerin 50 mcg/min"])
        XCTAssertEqual(rates("norepi 0.02-0.1"), ["Norepinephrine 0.02–0.1 mcg/kg/min"], "a range in one unit")
    }

    func testAmbiguousDrugsAndUnitsAsk() {
        let levo = InfusionEntry.read("levo 0.1")
        XCTAssertTrue(levo.items.isEmpty)
        XCTAssertEqual(levo.questions.first?.options.map(\.id), ["norepinephrine", "levosimendan"])
        XCTAssertEqual(rates("levo 0.1", choices: ["drug:levo": "norepinephrine"]), ["Norepinephrine 0.1 mcg/kg/min"])
        let nit = InfusionEntry.read("nit 5")
        XCTAssertEqual(Set(nit.questions.first?.options.map(\.id) ?? []), ["nitroglycerin", "nitroprusside", "ino"])
        let epi = InfusionEntry.read("epi 1")
        XCTAssertTrue(epi.items.isEmpty, "1 could be mcg/min or mcg/kg/min")
        XCTAssertEqual(epi.questions.first?.options.map(\.id), ["mcg/min", "mcg/kg/min", InfusionEntry.noUnit])
        XCTAssertEqual(rates("epi 1", choices: ["unit:epinephrine:1": "mcg/min"]), ["Epinephrine 1 mcg/min"])
    }

    func testNothingInvented() {
        XCTAssertEqual(InfusionEntry.read("norepi").items.map(\.rate), [""], "no rate typed, none added")
        XCTAssertEqual(InfusionEntry.read("xyz 5").unknown, ["xyz"])
        XCTAssertTrue(InfusionEntry.read("xy").isEmpty, "still typing: the typeahead speaks")
        XCTAssertEqual(rates("angiotensin 2"), ["Angiotensin II"], "the drug's name, not a rate of 2")
    }

    func testTypeahead() {
        XCTAssertEqual(InfusionEntry.suggestions("no").first?.id, "norepinephrine")
        XCTAssertTrue(InfusionEntry.suggestions("nor").isEmpty, "read as norepinephrine already: its chip is shown, not a suggestion too")
        XCTAssertEqual(InfusionEntry.suggestions("norepi 0.05, va").first?.id, "vasopressin")
        XCTAssertTrue(InfusionEntry.suggestions("norepi 0.05").isEmpty)
        XCTAssertTrue(InfusionEntry.suggestions("n").isEmpty)
    }

    func testRequestedAbbreviationsAreKnown() {
        let want: [String: String] = [
            "norepi": "norepinephrine", "ne": "norepinephrine", "epi": "epinephrine", "vaso": "vasopressin", "phenyl": "phenylephrine",
            "neo": "phenylephrine", "milri": "milrinone", "dobut": "dobutamine", "dopa": "dopamine", "ntg": "nitroglycerin",
            "nitro": "nitroglycerin", "nicardipine": "nicardipine", "nicard": "nicardipine", "clevidipine": "clevidipine",
            "esmolol": "esmolol", "snp": "nitroprusside", "insulin": "insulin", "propofol": "propofol", "prop": "propofol",
            "dexmed": "dexmedetomidine", "dex": "dexmedetomidine", "ketamine": "ketamine", "remi": "remifentanil",
            "sufentanil": "sufentanil", "heparin": "heparin", "amio": "amiodarone",
        ]
        for (w, id) in want { XCTAssertEqual(InfusionEntry.matches(w).map(\.id), [id], w) }
        XCTAssertEqual(InfusionEntry.matches("levo").map(\.id), ["norepinephrine", "levosimendan"])
        for d in QuickAdd.dripUnits { XCTAssertNotNil(InfusionEntry.drug(id: d.reference), d.reference + " is in the typed list") }
    }

    func testAddingUpdatesTheSameDrug() {
        var list = [PatientInfusion(drug: "Norepinephrine (Levophed)", rate: "0.03 mcg/kg/min"), PatientInfusion(drug: "", rate: "")]
        let r = InfusionEntry.read("norepi 0.05, vaso 0.04")
        XCTAssertEqual(InfusionEntry.status(r.items[0], in: list), .replaces("0.03 mcg/kg/min"))
        XCTAssertEqual(InfusionEntry.status(r.items[1], in: list), .new)
        InfusionEntry.apply(r.items, to: &list)
        XCTAssertEqual(list.map(\.text), ["Norepinephrine (Levophed) at 0.05 mcg/kg/min", "", "Vasopressin at 0.04 units/min"])
        InfusionEntry.apply(InfusionEntry.read("vaso").items, to: &list)
        XCTAssertEqual(list.last?.rate, "0.04 units/min", "a drip typed without a rate keeps its rate")
        XCTAssertEqual(InfusionEntry.status(InfusionEntry.read("vasopressin 0.04").items[0], in: list), .recorded)
        XCTAssertEqual(InfusionEntry.drugID(of: "norepinephrine"), "norepinephrine")
        XCTAssertEqual(InfusionEntry.drugID(of: "Nitric oxide, inhaled (INOmax)"), "ino")
    }

    /// The units the line gives without one typed are the Reference infusion table's (and, for the drips quick add
    /// reads, the quick-add bar's).
    func testUnitsMatchTheCatalog() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        let bundle = try ReferenceLoader.decode(try Data(contentsOf: url))
        let table = (bundle.infusions?.groups ?? []).flatMap(\.drugs)
        for d in InfusionEntry.drugs {
            if let q = QuickAdd.dripUnits.first(where: { $0.reference == d.id }) { XCTAssertEqual(d.unit, q.unit, d.id) }
            guard let unit = d.unit else { continue }
            let ref = try XCTUnwrap(table.first { $0.id == d.id }, d.id + " is in the Reference table")
            let derived: String?
            switch ref.form {
            case .perMin: derived = ref.unit.map { $0 + "/min" }
            case .perKgPerMin: derived = ref.unit.map { $0 + "/kg/min" }
            case .perKgPerHour: derived = ref.unit.map { $0 + "/kg/h" }
            case .perHour: derived = ref.unit.map { $0 + "/h" }
            default: derived = ref.unit
            }
            XCTAssertEqual(unit, derived, d.id)
            XCTAssertTrue(d.units.contains(unit), d.id)
        }
    }

    // MARK: 3. Foley

    func testFoleyKindAndSites() throws {
        XCTAssertEqual(DeviceKind.foley.label, "Foley")
        XCTAssertEqual(DeviceKind.foley.sizeUnit, "Fr")
        XCTAssertTrue(DeviceKind.more.contains(.foley))
        let urethral = try XCTUnwrap(DeviceSite.site(id: "urethral"))
        let suprapubic = try XCTUnwrap(DeviceSite.site(id: "suprapubic"))
        for s in [urethral, suprapubic] {
            XCTAssertEqual(s.kinds, [.foley])
            XCTAssertEqual(s.region, "pelvis")
            XCTAssertNil(s.side)
            XCTAssertEqual(Double(s.anchor.x), 0.5, accuracy: 1e-9, "midline")
        }
        XCTAssertLessThan(suprapubic.anchor.y, urethral.anchor.y, "suprapubic above the symphysis")
        XCTAssertEqual(PatientDevices.defaultSite(for: .foley)?.site, "urethral")
        XCTAssertFalse(PatientStudies.armLineKinds.contains(.foley), "not an arm line")
        XCTAssertTrue(PatientDevice.lineKinds.contains(.foley), "with the handoff's lines")
        XCTAssertFalse(PatientDevice.supportKinds.contains(.foley))
    }

    func testFoleyTyped() throws {
        let p = try XCTUnwrap(PatientDevices.parse("foley 16 Fr"))
        XCTAssertEqual(p.kind, .foley)
        XCTAssertEqual(p.size, "16")
        XCTAssertEqual(p.site, "urethral")
        XCTAssertGreaterThanOrEqual(p.confidence, 0.85)
        XCTAssertEqual(p.device().label, "Foley 16 Fr")
        let spc = try XCTUnwrap(PatientDevices.parse("suprapubic foley 14"))
        XCTAssertEqual(spc.site, "suprapubic")
        XCTAssertEqual(spc.device().label, "Foley 14 Fr suprapubic")
        XCTAssertEqual(PatientDevices.parse("SPC 16")?.site, "suprapubic")
        XCTAssertEqual(PatientDevices.parse("urinary catheter")?.kind, .foley)
        let r = applied(quick("foley 16 Fr", .intraop))
        XCTAssertEqual(r.devices.map(\.kind), [.foley])
        XCTAssertEqual(r.devices.first?.placedIntraop, true)
    }

    func testFoleyInTheHandoffNotOnTheHarvestArm() {
        var r = PatientRecord()
        r.devices = [PatientDevice(kind: .piv, site: "antecubital-left", side: "left", size: "18"),
                     PatientDevice(kind: .foley, site: "urethral", size: "16", placedIntraop: true)]
        XCTAssertTrue(HandoffWriter.shortText(r).contains("Lines: PIV 18 G L AC; Foley 16 Fr"), HandoffWriter.shortText(r))
        XCTAssertTrue(HandoffWriter.text(r).contains("Foley 16 Fr"))
        r.radial.harvest = "left"
        XCTAssertEqual(PatientStudies.linesOnHarvestArm(r).map(\.kind), [.piv], "the Foley is never on the arm")
    }

    // MARK: 4. Bentall

    func testBentallEntries() throws {
        let bio = try XCTUnwrap(ProcedureCatalog.byID("bentall-bio"))
        let mech = try XCTUnwrap(ProcedureCatalog.byID("bentall-mech"))
        let general = try XCTUnwrap(ProcedureCatalog.byID("bentall"))
        XCTAssertEqual(bio.name, "Bio-Bentall (bioprosthetic valved conduit)")
        XCTAssertEqual(mech.name, "Bentall, mechanical valve")
        for p in [bio, mech] {
            XCTAssertEqual(p.specialty, general.specialty)
            XCTAssertEqual(p.cardiac, general.cardiac)
            XCTAssertEqual(p.echoFirst, general.echoFirst)
            XCTAssertEqual(p.highRisk, general.highRisk)
            XCTAssertEqual(p.incision, general.incision)
            XCTAssertEqual(p.duration, general.duration)
            XCTAssertEqual(p.anesthetic, general.anesthetic)
            XCTAssertNil(p.ask)
        }
        for s in ["bio-Bentall", "biobentall", "bio Bentall", "bioprosthetic Bentall", "tissue Bentall"] {
            XCTAssertEqual(ProcedureCatalog.parse(s).map(\.procedure.id), ["bentall-bio"], s)
        }
        for s in ["mechanical Bentall", "mech Bentall", "Bentall with mechanical valve"] {
            XCTAssertEqual(ProcedureCatalog.parse(s).map(\.procedure.id), ["bentall-mech"], s)
        }
    }

    func testBareBentallAsks() throws {
        let found = ProcedureCatalog.search("Bentall").map(\.id)
        XCTAssertTrue(found.contains("bentall-bio") && found.contains("bentall-mech"))
        XCTAssertFalse(found.contains("bentall"), "the picker offers the two, not the general entry")
        for s in ["Bentall", "aortic root replacement", "modified Bentall"] {
            let item = try XCTUnwrap(PlannedProcedure.parse(s).first, s)
            XCTAssertEqual(item.catalogID, "bentall", s)
            XCTAssertEqual(item.ask?.text, "Bentall: bioprosthetic or mechanical valve?", s)
        }
        let item = try XCTUnwrap(PlannedProcedure.parse("redo Bentall").first { $0.catalogID == "bentall" })
        let mech = try XCTUnwrap(item.answering("bentall-mech"))
        XCTAssertEqual(mech.catalogID, "bentall-mech")
        XCTAssertEqual(mech.title, "Bentall, mechanical valve")
        XCTAssertNil(mech.ask)
        XCTAssertNil(item.answering("cabg"))
    }

    func testQuickAddAsksTheValve() throws {
        let q = quick("68M for Bentall")
        let asked = try XCTUnwrap(q.ambiguous.first { $0.id == ProcedureAsk.questionID("bentall") })
        XCTAssertEqual(asked.abbreviation, "Bentall")
        XCTAssertEqual(asked.options.map(\.id), ["bentall-bio", "bentall-mech"])
        XCTAssertEqual(asked.options.map(\.text), ["bioprosthetic", "mechanical valve"])
        XCTAssertEqual(applied(q).procedures.first?.catalogID, "bentall", "unanswered: the general entry, to be asked in the editor")
        let answered = quick("68M for Bentall", choices: [ProcedureAsk.questionID("bentall"): "bentall-bio"])
        XCTAssertEqual(applied(answered).procedures.first?.catalogID, "bentall-bio")
        XCTAssertEqual(quick("68M for mech Bentall").ambiguous.filter { $0.id.hasPrefix("quick:procedure:") }.count, 0)
        XCTAssertNotNil(note("Scheduled for Bentall.").ambiguous.first { $0.id == ProcedureAsk.questionID("bentall") })
    }

    func testSavedBentallStillOpensAndHistoryReadsIt() throws {
        let json = #"{"catalogID":"bentall","name":"Aortic root replacement"}"#.data(using: .utf8)!
        let saved = try JSONDecoder().decode(PlannedProcedure.self, from: json)
        XCTAssertEqual(saved.catalog?.id, "bentall")
        XCTAssertEqual(saved.title, "Aortic root replacement")
        XCTAssertNotNil(saved.ask)
        var r = PatientRecord()
        r.setProcedures([saved])
        XCTAssertTrue(PatientRules.cardiacSurgery(r))
        XCTAssertTrue(ids(note("s/p Bentall 2019")).contains("problem:aortic-repair-open"))
        XCTAssertTrue(ids(note("s/p bio-Bentall 2019")).contains("problem:aortic-repair-open"))
        XCTAssertFalse(ids(note("Scheduled for bioprosthetic Bentall.")).contains { $0.hasPrefix("problem:prosthetic-valve") }, "the planned valve is not one in place")
        XCTAssertTrue(ids(note("s/p Bentall with mechanical valve 2015")).contains { $0.hasPrefix("problem:prosthetic-valve") })
    }

    // MARK: 5. The lines figure in the handoff

    func testHandoffFigureShowsEveryCurrentDevice() {
        var r = PatientRecord()
        let piv = PatientDevice(kind: .piv, site: "antecubital-right", side: "right", size: "18")
        let foley = PatientDevice(kind: .foley, site: "urethral", size: "16", placedIntraop: true)
        let gone = PatientDevice(kind: .cvc, site: "ij-right", side: "right", removed: true)
        r.devices = [piv, foley, gone]
        let current = Set(r.currentDevices().map(\.id.uuidString))
        let drawn = Set(PatientDiagramModel.items(r, phase: .all).items.map(\.id)).intersection(r.devices.map(\.id.uuidString))
        XCTAssertEqual(drawn, current, "the handoff's figure draws what is in place now, on arrival and placed in the room")
        XCTAssertEqual(current, [piv.id.uuidString, foley.id.uuidString])
        let arrival = Set(PatientDiagramModel.items(r, phase: .preop).items.map(\.id)).intersection(r.devices.map(\.id.uuidString))
        XCTAssertEqual(arrival, [piv.id.uuidString], "the arrival picture leaves out what was placed in the room")
    }
}
