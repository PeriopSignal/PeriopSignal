import XCTest
@testable import PeriopSignal

/// 1.8.1: the type-to-fill bar on every tab and editor page of My Patient, filling the whole record from wherever it
/// is: where each bar sits and how it reads, fluids in and out, blood and fluid totals versus "+", the airway, and drips
/// routed by place through the infusion reader. All lines are synthetic; no real patient data.
final class QuickBar181fTests: XCTestCase {
    /// 30 October 2026, 08:00 on the device's clock.
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))! }

    private func read(_ s: String, _ tab: QuickAddTab = .intraop, record: PatientRecord = PatientRecord(),
                      choices: [String: String] = [:]) -> QuickAddReading {
        QuickAdd.read(s, record: record, tab: tab, now: now, choices: choices)
    }
    private func ids(_ q: QuickAddReading) -> Set<String> { Set(q.findings.map(\.id)) }
    private func applied(_ q: QuickAddReading, to base: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = base
        PatientNote.apply(q.findings.map(\.change), to: &r)
        return r
    }
    private func values(_ q: QuickAddReading, record: PatientRecord = PatientRecord()) -> [String] {
        QuickAdd.chips(q, record: record).map(\.value)
    }
    private func record(_ fluids: [String: Double]) -> PatientRecord {
        var r = PatientRecord()
        r.fluids = fluids
        return r
    }

    // MARK: Where the bar is

    /// Every tab has the bar; every editor page has the compact one. The intraoperative pages read as the
    /// Intraoperative tab, the rest (Summary & Handoff included) as the Preoperative tab.
    func testEveryTabAndEditorHasTheBar() {
        XCTAssertEqual(PatientTab.allCases.map(\.quickAddPlace), [.preopTab, .intraopTab, .summaryTab])
        XCTAssertEqual(PatientTab.allCases.map(\.quickAddPlace.tab), [.preop, .intraop, .preop])
        XCTAssertTrue(PatientTab.allCases.allSatisfy { !$0.quickAddPlace.compact }, "the tabs' bar is the full one")

        var preop: [PatientEditor] = [.details, .procedure, .demographics, .history, .medications, .assessment, .airway, .plan,
                                      .devices("preop"), .devices("support")]
        preop += PatientCatalog.allSystems.map { PatientEditor.system($0.id) }
        preop += PatientEditor.workups.map { PatientEditor.workup($0.id) }
        var intraop: [PatientEditor] = [.intraop, .devices("intraop")]
        intraop += PatientEditor.intraopParts.map { PatientEditor.intraopPart($0.id) }
        for e in preop {
            XCTAssertEqual(e.quickAddPlace, .editor(intraop: false), e.title)
            XCTAssertEqual(e.quickAddPlace.tab, .preop, e.title)
            XCTAssertTrue(e.quickAddPlace.compact, e.title)
        }
        for e in intraop {
            XCTAssertEqual(e.quickAddPlace, .editor(intraop: true), e.title)
            XCTAssertEqual(e.quickAddPlace.tab, .intraop, e.title)
            XCTAssertTrue(e.quickAddPlace.compact, e.title)
        }
        XCTAssertTrue(PatientEditor.intraopParts.map(\.id).contains("fluids"))
        XCTAssertTrue(PatientEditor.intraopParts.map(\.id).contains("infusions"))
    }

    func testPlaceholders() {
        XCTAssertEqual(QuickAdd.placeholder(QuickAddPlace.preopTab), "68M for lap chole, HTN, K 5.4, A-line")
        XCTAssertEqual(QuickAdd.placeholder(QuickAddPlace.intraopTab), "norepi 0.05, PRBC 2, EBL 500")
        XCTAssertEqual(QuickAdd.placeholder(QuickAddPlace.summaryTab), "K 5.4, norepi 0.05, A-line")
        XCTAssertEqual(QuickAdd.placeholder(QuickAddPlace.editor(intraop: true)), QuickAdd.placeholder(QuickAddPlace.intraopTab))
        XCTAssertEqual(QuickAdd.placeholder(QuickAddPlace.editor(intraop: false)), QuickAdd.placeholder(QuickAddPlace.preopTab))
        // Each placeholder reads where it is shown, with nothing left unread.
        for place in [QuickAddPlace.preopTab, .intraopTab, .summaryTab] {
            let q = read(QuickAdd.placeholder(place), place.tab)
            XCTAssertFalse(q.findings.isEmpty, QuickAdd.placeholder(place))
            XCTAssertEqual(q.unread, "", QuickAdd.placeholder(place))
        }
        XCTAssertTrue(QuickAdd.isQuestion(QuickAdd.bloodQuestion + "prbc"))
        XCTAssertTrue(QuickAdd.isQuestion("drug:levo"))
        XCTAssertTrue(QuickAdd.isQuestion("unit:amiodarone:1"))
        XCTAssertFalse(QuickAdd.isQuestion("levo@levo-norepinephrine"), "an abbreviation's meaning")
    }

    // MARK: Fluids, blood loss and urine

    func testFluidsInAndOut() {
        let q = read("LR 1.5 L, 5% albumin 500, EBL 500, UOP 300")
        XCTAssertEqual(applied(q).fluids, ["crystalloid": 1500, "colloid": 500, "ebl": 500, "uop": 300])
        XCTAssertEqual(QuickAdd.chips(q, record: PatientRecord()).map(\.text),
                       ["Intraop · Crystalloid: total 1500 mL", "Intraop · Colloid: total 500 mL", "Intraop · EBL: total 500 mL",
                        "Intraop · Urine: total 300 mL"])
        XCTAssertEqual(q.unread, "")
        XCTAssertTrue(q.ambiguous.isEmpty, "\(q.ambiguous.map(\.abbreviation))")

        for (line, key, v) in [("1 L LR", "crystalloid", 1000.0), ("NS 2.5 L", "crystalloid", 2500), ("plasmalyte 1500 mL", "crystalloid", 1500),
                               ("albumin 5% 250 mL", "colloid", 250), ("EBL: 1,200 mL", "ebl", 1200), ("blood loss 300", "ebl", 300),
                               ("300 mL urine", "uop", 300), ("urine output 450", "uop", 450), ("lr 1000", "crystalloid", 1000)] {
            XCTAssertEqual(applied(read(line)).fluids[key], v, line)
        }
        // Not a volume given: a lab, a rate, a plan; and not read on the Preoperative tab.
        XCTAssertNil(applied(read("albumin 3.1")).fluids["colloid"], "albumin's lab value")
        XCTAssertNil(applied(read("urine 0.5 mL/kg/h")).fluids["uop"], "a rate")
        XCTAssertNil(applied(read("will give 1 L LR")).fluids["crystalloid"], "planned")
        XCTAssertNil(applied(read("no EBL")).fluids["ebl"])
        XCTAssertFalse(ids(read("EBL 500, LR 1 L", .preop)).contains { $0.hasPrefix("fluid:") }, "the case's fluids, from the intraoperative places")
    }

    /// A volume is the case total, and the chip says so with what was recorded; "+" adds to it.
    func testFluidTotalsVersusPlus() {
        let was = record(["ebl": 300, "crystalloid": 1000])
        XCTAssertEqual(values(read("EBL 500", record: was), record: was), ["EBL: total 500 mL (was 300)"])
        XCTAssertEqual(applied(read("EBL 500", record: was), to: was).fluids["ebl"], 500, "the total, not 800")
        for line in ["EBL +200", "+200 mL EBL"] {
            let q = read(line, record: was)
            XCTAssertEqual(values(q, record: was), ["EBL +200 mL (total 500 mL)"], line)
            XCTAssertEqual(applied(q, to: was).fluids["ebl"], 500, line)
        }
        let same = read("EBL 300", record: was)
        XCTAssertTrue(same.findings.isEmpty)
        XCTAssertTrue(same.skipped.contains("EBL total 300 mL · already recorded"))
        // A lower total is shown with what it replaces, never added on top.
        XCTAssertEqual(values(read("LR 800", record: was), record: was), ["Crystalloid: total 800 mL (was 1000)"])
        XCTAssertEqual(applied(read("LR 800", record: was), to: was).fluids["crystalloid"], 800)
        // A second volume of the same kind in the line adds to the first.
        XCTAssertEqual(applied(read("LR 1 L, LR 500 mL")).fluids["crystalloid"], 1500)
    }

    /// A small number with no unit could be litres: asked, nothing added until answered.
    func testSmallVolumeWithoutUnitIsAsked() {
        let q = read("LR 2")
        let asked = q.ambiguous.first { $0.id == QuickAdd.fluidQuestion + "crystalloid" }
        XCTAssertEqual(asked?.abbreviation, "LR 2")
        XCTAssertEqual(asked?.options.map(\.text), ["2 L"])
        XCTAssertTrue(applied(q).fluids.isEmpty, "nothing until answered")
        XCTAssertEqual(q.unread, "")
        let litres = read("LR 2", choices: [QuickAdd.fluidQuestion + "crystalloid": QuickAdd.fluidLitres])
        XCTAssertEqual(applied(litres).fluids["crystalloid"], 2000)
        XCTAssertTrue(applied(read("LR 2", choices: [QuickAdd.fluidQuestion + "crystalloid": MedAbbreviations.asWritten])).fluids.isEmpty,
                      "left out")
    }

    // MARK: Blood: the total, or "+"

    func testBloodCountIsTheCaseTotal() {
        let one = record(["prbc": 1])
        XCTAssertEqual(values(read("PRBC 2", record: one), record: one), ["PRBC: total 2 units (was 1)"])
        XCTAssertEqual(applied(read("PRBC 2", record: one), to: one).fluids["prbc"], 2)
        for line in ["+2 PRBC", "PRBC +2"] {
            let q = read(line, record: one)
            XCTAssertEqual(values(q, record: one), ["PRBC +2 (total 3)"], line)
            XCTAssertEqual(applied(q, to: one).fluids["prbc"], 3, line)
        }
        XCTAssertEqual(values(read("plt 2")), ["Platelets: total 2 doses"])
        XCTAssertEqual(values(read("PRBC 1")), ["PRBC: total 1 unit"])
        let saver = record(["cellSaver": 200])
        XCTAssertEqual(values(read("cell saver 450", record: saver), record: saver), ["Cell saver: total 450 mL (was 200)"])
        XCTAssertEqual(applied(read("cell saver +250", record: saver), to: saver).fluids["cellSaver"], 450)
        // Lower than recorded: the chip says so; filing it sets the total.
        let four = record(["prbc": 4])
        XCTAssertEqual(values(read("PRBC 2", record: four), record: four), ["PRBC: total 2 units (was 4)"])
        XCTAssertEqual(applied(read("PRBC 2", record: four), to: four).fluids["prbc"], 2)
        // An ordinal is one more, and a count with its total beside it adds, as before.
        XCTAssertEqual(applied(read("PRBC 3rd unit hanging", record: one), to: one).fluids["prbc"], 2)
        XCTAssertEqual(applied(read("1 PRBC (total 2)", record: one), to: one).fluids["prbc"], 2)
        // Each chip can still be left out, and the running total is what the chips left on make.
        let q = read("PRBC 2, +1 PRBC", record: one)
        let chips = QuickAdd.chips(q, record: one)
        XCTAssertEqual(chips.map(\.value), ["PRBC: total 2 units (was 1)", "PRBC +1 (total 3)"])
        let without = QuickAdd.chips(q, record: one, dropped: [chips[0].id])
        XCTAssertEqual(without.map(\.value), ["PRBC: total 2 units (was 1)", "PRBC +1 (total 2)"])
        var r = one
        PatientNote.apply(QuickAdd.changes(without, dropped: [chips[0].id]), to: &r)
        XCTAssertEqual(r.fluids["prbc"], 2)
    }

    // MARK: The airway

    func testAirwayReading() {
        XCTAssertEqual(applied(read("ETT 7.5 @ 22")).tube, "7.5 ETT, 22 cm")
        let view = applied(read("VL, grade 1 view, 7.0 ETT"))
        XCTAssertEqual(view.airwayDevice, "Video laryngoscope")
        XCTAssertEqual(view.laryngoscopyGrade, "1")

        let lma = applied(read("LMA 4, easy mask"))
        XCTAssertEqual(lma.tube, "LMA 4")
        XCTAssertEqual(lma.airwayDevice, "Supraglottic airway")
        XCTAssertEqual(lma.mask, "easy")
        XCTAssertEqual(applied(read("i-gel size 4")).tube, "i-gel 4")
        XCTAssertNil(applied(read("LMA 4 available")).tube.nilIfEmpty, "a backup, not used")

        // A blade with a video laryngoscope is that laryngoscope's: one device, no question.
        for line in ["Glidescope Mac 3, grade 1", "C-MAC 3, grade 1 view", "VL with Miller 2, grade 1"] {
            let q = read(line)
            XCTAssertNil(q.ambiguous.first { $0.id == QuickAdd.laryngoscopyQuestion }, line)
            XCTAssertEqual(applied(q).airwayDevice, "Video laryngoscope", line)
            XCTAssertEqual(applied(q).laryngoscopyGrade, "1", line)
        }
        XCTAssertEqual(applied(read("DL Mac 3, grade 1")).airwayDevice, "Direct laryngoscope")

        // Grade 2 without a or b: asked.
        let two = read("DL, Cormack-Lehane 2")
        XCTAssertEqual(two.ambiguous.first { $0.id == QuickAdd.grade2Question }?.options.map(\.text), ["2a", "2b"])
        XCTAssertNil(applied(two).laryngoscopyGrade, "nothing until chosen")
        XCTAssertEqual(applied(read("DL, Cormack-Lehane 2", choices: [QuickAdd.grade2Question: "grade-2b"])).laryngoscopyGrade, "2b")
    }

    // MARK: Drips, by place

    func testDripsGoWhereTheBarIs() {
        for place in [QuickAddPlace.intraopTab, .editor(intraop: true)] {
            let r = applied(read("norepi 0.05", place.tab))
            XCTAssertEqual(r.infusions.map(\.text), ["Norepinephrine at 0.05 mcg/kg/min"], "\(place)")
            XCTAssertTrue(r.homeInfusions.isEmpty, "\(place)")
        }
        for place in [QuickAddPlace.preopTab, .summaryTab, .editor(intraop: false)] {
            let r = applied(read("norepi 0.05", place.tab))
            XCTAssertEqual(r.homeInfusions.map(\.text), ["Norepinephrine at 0.05 mcg/kg/min"], "\(place)")
            XCTAssertTrue(r.infusions.isEmpty, "\(place)")
        }
    }

    /// The other drips on the infusion list, written as drips, through the Infusions groups' reader and its questions.
    func testOtherDripsThroughTheInfusionReader() {
        XCTAssertEqual(applied(read("amio gtt 1 mg/min")).infusions.map(\.text), ["Amiodarone at 1 mg/min"])
        XCTAssertEqual(applied(read("amio gtt 1 mg/min", .preop)).homeInfusions.map(\.text), ["Amiodarone at 1 mg/min"])
        XCTAssertEqual(applied(read("iso @ 2")).infusions.map(\.text), ["Isoproterenol at 2 mcg/min"], "the catalog's one unit")

        // No unit, none to read by size: the unit question, nothing added until answered.
        let amio = read("amio gtt 1")
        let unit = amio.ambiguous.first { $0.id == "unit:amiodarone:1" }
        XCTAssertEqual(unit?.options.map(\.id), ["mg/min", "mg/h", InfusionEntry.noUnit])
        XCTAssertTrue(applied(amio).infusions.isEmpty)
        XCTAssertEqual(amio.unread, "")
        XCTAssertEqual(applied(read("amio gtt 1", choices: ["unit:amiodarone:1": "mg/min"])).infusions.map(\.text), ["Amiodarone at 1 mg/min"])

        // A word that names two drugs: the drug question.
        let ami = read("ami gtt 1 mg/min")
        XCTAssertEqual(Set(ami.ambiguous.first { $0.id == "drug:ami" }?.options.map(\.id) ?? []), ["amiodarone", "aminocaproic"])
        XCTAssertTrue(applied(ami).infusions.isEmpty)
        XCTAssertEqual(applied(read("ami gtt 1 mg/min", choices: ["drug:ami": "amiodarone"])).infusions.map(\.text), ["Amiodarone at 1 mg/min"])

        // Not drips: a bolus, a dose by the clock, a drug off; and a drip the bar's own reader keeps (no second reading).
        for line in ["amio 150 bolus @ 10:30", "heparin 5000 units q8h", "off amio gtt", "levo gtt 0.1"] {
            XCTAssertNil(read(line).ambiguous.first { $0.id.hasPrefix("unit:") || $0.id.hasPrefix("drug:") }, line)
        }
        XCTAssertTrue(applied(read("off amio gtt 1 mg/min")).infusions.isEmpty)
    }

    /// A drip typed again updates its row, found by the drug: "norepi" is the row written "Norepinephrine (Levophed)".
    func testDripUpdatesItsRowByTheDrug() {
        var r = PatientRecord()
        r.infusions = [PatientInfusion(drug: "Norepinephrine (Levophed)", rate: "0.03 mcg/kg/min")]
        let q = read("norepi 0.05", record: r)
        XCTAssertEqual(QuickAdd.chips(q, record: r).first?.statusText, "replaces 0.03 mcg/kg/min")
        let after = applied(q, to: r)
        XCTAssertEqual(after.infusions.count, 1)
        XCTAssertEqual(after.infusions.first?.rate, "0.05 mcg/kg/min")
        r.homeInfusions = [PatientInfusion(drug: "Milrinone", rate: "0.25 mcg/kg/min")]
        XCTAssertEqual(QuickAdd.chips(read("milrinone 0.25", .preop, record: r), record: r).first?.statusText, "already recorded")
    }

    // MARK: The screenshot lines

    func testScreenshotLines() {
        let demo = PatientDemo.record
        let intra = read("norepi 0.05, PRBC 2, +1 FFP, LR 2 L, EBL 500, UOP 400", record: demo)
        XCTAssertTrue(ids(intra).isSuperset(of: ["intraop-infusion:norepinephrine", "blood:prbc", "blood:plasma", "fluid:crystalloid", "fluid:ebl", "fluid:uop"]),
                      "\(ids(intra))")
        XCTAssertEqual(intra.unread, "")
        let dark = read("LR 2, amio gtt 1, Cormack-Lehane 2, LMA 4, cell saver +300")
        XCTAssertEqual(Set(dark.ambiguous.map(\.id)).intersection([QuickAdd.fluidQuestion + "crystalloid", "unit:amiodarone:1", QuickAdd.grade2Question]).count, 3)
        XCTAssertEqual(applied(dark).tube, "LMA 4")
        XCTAssertEqual(applied(dark).fluids["cellSaver"], 300)
        XCTAssertEqual(dark.unread, "")
        let fluids = read("+2 PRBC, EBL 900, UOP 450", record: demo)
        XCTAssertEqual(values(fluids, record: demo), ["PRBC +2", "EBL: total 900 mL (was 250)", "Urine: total 450 mL (was 320)"])
        let airway = read("ETT 7.5 @ 22, Glidescope Mac 3, grade 1 view, easy mask")
        XCTAssertEqual(applied(airway).tube, "7.5 ETT, 22 cm")
        XCTAssertEqual(applied(airway).airwayDevice, "Video laryngoscope")
        XCTAssertEqual(read(QuickAdd.placeholder(QuickAddPlace.summaryTab), .preop, record: demo).unread, "")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
