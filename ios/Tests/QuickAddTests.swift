import XCTest
@testable import PeriopSignal

/// The quick-add bar's reader (QuickAdd): the one-line shorthand around the note reader, the routing on each tab,
/// plausibility, negation, ambiguous abbreviations, identifiers, the chips, and the note changes it adds.
final class QuickAddTests: XCTestCase {
    /// 30 October 2026, 08:00 on the device's clock.
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))! }

    private func read(_ s: String, _ tab: QuickAddTab = .preop, record: PatientRecord = PatientRecord(),
                      choices: [String: String] = [:]) -> QuickAddReading {
        QuickAdd.read(s, record: record, tab: tab, now: now, choices: choices)
    }
    private func ids(_ q: QuickAddReading) -> Set<String> { Set(q.findings.map(\.id)) }
    private func change(_ q: QuickAddReading, _ id: String) -> PatientNoteChange? { q.findings.first { $0.id == id }?.change }
    private func applied(_ q: QuickAddReading, to base: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = base
        PatientNote.apply(q.findings.map(\.change), to: &r)
        return r
    }
    /// The values of the one intraoperative set the line adds.
    private func setValues(_ q: QuickAddReading) -> [String: Double] { applied(q).intraopLabs.first?.values ?? [:] }

    func testPatternsCompile() {
        for p in QuickAdd.allPatterns { XCTAssertNotNil(p.re, p.pattern) }
        for p in PatientNote.allPatterns { XCTAssertNotNil(p.re, p.pattern) }
    }

    // MARK: Vital signs

    func testVitalsInARow() {
        let q = read("148/86 72 95% RA 16")
        XCTAssertEqual(change(q, "vital:sbp"), .vital("sbp", 148))
        XCTAssertEqual(change(q, "vital:dbp"), .vital("dbp", 86))
        XCTAssertEqual(change(q, "vital:hr"), .vital("hr", 72))
        XCTAssertEqual(change(q, "vital:spo2"), .vital("spo2", 95))
        XCTAssertEqual(change(q, "vital:rr"), .vital("rr", 16))
        XCTAssertNil(q.findings.first { $0.id == "vital:spo2" }?.note, "room air was written")
        XCTAssertFalse(ids(q).contains("oxygen"), "RA qualifies the saturation")
        XCTAssertFalse(ids(q).contains("airway"), "no airway inferred")
        XCTAssertTrue(q.ambiguous.isEmpty, "RA after a saturation is room air, from the context")
        XCTAssertEqual(q.unread, "")
    }

    func testVitalsWithLabels() {
        let q = read("BP 148/86 HR 72 SpO2 95% RR 16 T 36.8")
        XCTAssertEqual(change(q, "vital:sbp"), .vital("sbp", 148))
        XCTAssertEqual(change(q, "vital:hr"), .vital("hr", 72))
        XCTAssertEqual(change(q, "vital:rr"), .vital("rr", 16))
        XCTAssertEqual(change(q, "vital:temp"), .vital("temp", 36.8))
        XCTAssertNil(change(q, "vital:spo2"), "room air not written: asked, not filed")
        XCTAssertEqual(q.ambiguous.map(\.id), [QuickAdd.roomAirQuestion])

        let p = read("bp 148/86, p 72")
        XCTAssertEqual(change(p, "vital:dbp"), .vital("dbp", 86))
        XCTAssertEqual(change(p, "vital:hr"), .vital("hr", 72), "p is the pulse after a blood pressure")

        XCTAssertEqual(change(read("120/80 70 98.6"), "vital:temp"), .vital("temp", 37), "98.6 is °F")
    }

    func testBarePairNeedsAHeartRate() {
        XCTAssertNil(change(read("148/86"), "vital:sbp"), "a pair alone could be anything")
        XCTAssertNil(change(read("148/86 300"), "vital:sbp"), "300 is no heart rate")
        XCTAssertNil(change(read("86/148 72"), "vital:sbp"), "systolic below diastolic")
        XCTAssertNil(change(read("PA 60/30 72"), "vital:sbp"), "a PA pressure")
        XCTAssertNil(change(read("148/86 72 18G PIV"), "vital:rr"), "18G is a gauge, not a rate")
    }

    func testSaturationOnOxygenIsNotRoomAir() {
        let q = read("120/80 70 94% on 4L NC")
        XCTAssertEqual(change(q, "vital:hr"), .vital("hr", 70))
        XCTAssertNil(change(q, "vital:spo2"), "the field is SpO₂ on room air")
        XCTAssertTrue(q.skipped.contains { $0.hasPrefix("SpO₂ 94%") })
        XCTAssertEqual(change(q, "oxygen"), .oxygen(PatientOxygen(device: "nc", flow: 4)), "the oxygen itself is read")
        XCTAssertFalse(ids(q).contains("airway"), "own airway is inferred, not written")
    }

    func testSaturationWithoutRoomAirIsAsked() {
        let line = "148/86 72 95% 16"
        let q = read(line)
        XCTAssertNil(change(q, "vital:spo2"), "not filed until room air is chosen")
        XCTAssertEqual(change(q, "vital:rr"), .vital("rr", 16), "the rest of the row is read")
        let ask = q.ambiguous.first { $0.id == QuickAdd.roomAirQuestion }
        XCTAssertEqual(ask?.abbreviation, "SpO₂ 95%")
        XCTAssertEqual(ask?.options.map(\.text), ["room air", "on oxygen"])
        XCTAssertEqual(ask?.chosen?.text, "room air", "shown as “room air?” until chosen")
        XCTAssertFalse(QuickAdd.chips(q, record: PatientRecord()).contains { $0.value.hasPrefix("SpO₂") }, "no chip until answered")

        let air = read(line, choices: [QuickAdd.roomAirQuestion: QuickAdd.roomAirAnswer])
        XCTAssertEqual(change(air, "vital:spo2"), .vital("spo2", 95), "room air chosen")
        XCTAssertTrue(QuickAdd.chips(air, record: PatientRecord()).contains { $0.text == "Vitals · SpO₂ 95%" })

        let o2 = read(line, choices: [QuickAdd.roomAirQuestion: QuickAdd.oxygenAnswer])
        XCTAssertNil(change(o2, "vital:spo2"), "on oxygen: the field is SpO₂ on room air")
        XCTAssertTrue(o2.skipped.contains { $0.hasPrefix("SpO₂ 95% on oxygen") })

        let out = read(line, choices: [QuickAdd.roomAirQuestion: MedAbbreviations.asWritten])
        XCTAssertNil(change(out, "vital:spo2"), "left out")
        XCTAssertNil(out.ambiguous.first { $0.id == QuickAdd.roomAirQuestion }?.chosen)

        // A saturation the note reader reads is asked the same way.
        let sats = read("SpO2 96%")
        XCTAssertNil(change(sats, "vital:spo2"))
        XCTAssertEqual(sats.ambiguous.map(\.id), [QuickAdd.roomAirQuestion])
        XCTAssertEqual(change(read("SpO2 96%", choices: [QuickAdd.roomAirQuestion: QuickAdd.roomAirAnswer]), "vital:spo2"), .vital("spo2", 96))
        let written = read("SpO2 96% on room air")
        XCTAssertEqual(change(written, "vital:spo2"), .vital("spo2", 96), "room air written: filed, nothing asked")
        XCTAssertFalse(written.ambiguous.contains { $0.id == QuickAdd.roomAirQuestion })
        XCTAssertTrue(read(line, .intraop).ambiguous.isEmpty, "no vital signs on the Intraoperative tab, so nothing to ask")
        XCTAssertFalse(read("120/80 70 94% on 4L NC").ambiguous.contains { $0.id == QuickAdd.roomAirQuestion }, "oxygen written: the notice")
    }

    // MARK: Labs

    func testLabsByName() {
        let q = read("Na 138 K 4.1 Cl 102 HCO3 24 BUN 18 Cr 1.1 Glu 162")
        XCTAssertEqual(change(q, "lab:na"), .lab("na", 138))
        XCTAssertEqual(change(q, "lab:k"), .lab("k", 4.1))
        XCTAssertEqual(change(q, "lab:cl"), .lab("cl", 102))
        XCTAssertEqual(change(q, "lab:hco3"), .lab("hco3", 24))
        XCTAssertEqual(change(q, "lab:bun"), .lab("bun", 18))
        XCTAssertEqual(change(q, "lab:cr"), .lab("cr", 1.1))
        XCTAssertEqual(change(q, "lab:glucose"), .lab("glucose", 162))
        XCTAssertEqual(q.unread, "")

        let c = read("Hb 9.1 Plt 96 INR 1.8 fib 180")
        XCTAssertEqual(change(c, "lab:hb"), .lab("hb", 9.1))
        XCTAssertEqual(change(c, "lab:plt"), .lab("plt", 96))
        XCTAssertEqual(change(c, "lab:inr"), .lab("inr", 1.8))
        XCTAssertEqual(change(c, "lab:fibrinogen"), .lab("fibrinogen", 180))
        XCTAssertEqual(applied(c).labs["fibrinogen"], 180)
    }

    func testFishbones() {
        for line in ["138/4.1/102/24/18/1.1/162", "138|4.1|102|24|18|1.1<162"] {
            let q = read(line)
            XCTAssertEqual(applied(q).labs, ["na": 138, "k": 4.1, "cl": 102, "hco3": 24, "bun": 18, "cr": 1.1, "glucose": 162], line)
        }
        XCTAssertTrue(read("138/4.1/102/24/18/1.1").findings.isEmpty, "six values are not the BMP")
        XCTAssertTrue(read("138/41/102/24/18/1.1/162").findings.isEmpty, "K 41 is not a potassium")
        XCTAssertTrue(read("138/4.1/24/102/18/1.1/162").findings.isEmpty, "out of order: chloride below the bicarbonate's place")

        let cbc = read("7.2>12.1/36<210")
        XCTAssertEqual(applied(cbc).labs, ["wbc": 7.2, "hb": 12.1, "hct": 36, "plt": 210])
        XCTAssertTrue(read("7.2>36/12.1<210").findings.isEmpty, "hemoglobin and hematocrit swapped")
    }

    func testPlausibility() {
        XCTAssertNil(change(read("K 41"), "lab:k"))
        XCTAssertNil(change(read("Na 13.8"), "lab:na"))
        XCTAssertNil(change(read("Hb 91"), "lab:hb"))
        XCTAssertNil(change(read("K 20 mEq"), "lab:k"), "a dose, not a level")
        XCTAssertNil(change(read("vitamin K 10"), "lab:k"))
        XCTAssertNil(change(read("K <3"), "lab:k"), "an inequality is not a value")
        XCTAssertEqual(change(read("plt 96k"), "lab:plt"), .lab("plt", 96))
        XCTAssertEqual(change(read("plt 96,000"), "lab:plt"), .lab("plt", 96))
        XCTAssertEqual(change(read("HbA1c 7.4%"), "lab:a1c"), .lab("a1c", 7.4))
        XCTAssertNil(change(read("a fib 180"), "lab:fibrinogen"), "atrial fibrillation")
    }

    func testLabsOnTheIntraoperativeTab() {
        let q = read("Hb 9.1 K 5.6 iCa 1.02 lactate 4.2 Cr 1.6", .intraop)
        let r = applied(q)
        XCTAssertEqual(r.intraopLabs.count, 1, "one new set")
        XCTAssertEqual(r.intraopLabs.first?.values, ["hb": 9.1, "k": 5.6, "ica": 1.02, "lactate": 4.2])
        XCTAssertEqual(r.intraopLabs.first?.time, now, "stamped now")
        XCTAssertTrue(r.labs.isEmpty, "the preoperative labs are left alone")
        XCTAssertTrue(q.skipped.contains { $0.hasPrefix("Cr 1.6") }, "creatinine has no intraoperative field")
        XCTAssertTrue(q.findings.allSatisfy { $0.section == QuickAdd.intraop })

        // An intraoperative-only test on the Preoperative tab is shown, not filed.
        let pre = read("lactate 4.2")
        XCTAssertTrue(pre.findings.isEmpty)
        XCTAssertTrue(pre.skipped.contains { $0.hasPrefix("Lactate 4.2") })
    }

    func testBloodGas() {
        let q = read("7.29/41/168", .intraop)
        XCTAssertEqual(setValues(q), ["ph": 7.29, "paco2": 41, "pao2": 168])
        XCTAssertEqual(setValues(read("ABG 7.29/41/168/19/-6", .intraop)), ["ph": 7.29, "paco2": 41, "pao2": 168, "hco3a": 19, "be": -6])
        XCTAssertTrue(read("7.29/41/168").findings.isEmpty, "on the Preoperative tab only when ABG or gas is written")
        let pre = read("ABG 7.29/41/168")
        XCTAssertTrue(pre.findings.isEmpty)
        XCTAssertTrue(pre.skipped.contains { $0.hasPrefix("Blood gas") })
        XCTAssertTrue(read("7.29/168/41", .intraop).findings.isEmpty, "PaO₂ where the PaCO₂ goes: not a gas")
        XCTAssertTrue(read("7.29/41/168/30", .intraop).findings.isEmpty, "a bicarbonate that disagrees with the pH and PaCO₂")
        XCTAssertFalse(ids(read("VBG 7.31/48/40", .intraop)).contains("intraop-lab:pao2"), "a venous PO₂ is not a PaO₂")
    }

    // MARK: Blood, drips, lines and the airway in the OR

    func testBloodProducts() {
        let q = read("2 PRBC, +2 FFP, cryo 10, 1 pool cryo, plt 1, cell saver 450", .intraop)
        let r = applied(q)
        XCTAssertEqual(r.fluids["prbc"], 2)
        XCTAssertEqual(r.fluids["plasma"], 2)
        XCTAssertEqual(r.fluids["cryo"], 15, "10 units and a pool of 5")
        XCTAssertEqual(r.fluids["platelets"], 1)
        XCTAssertEqual(r.fluids["cellSaver"], 450)
        XCTAssertTrue(r.labs.isEmpty && r.intraopLabs.isEmpty, "plt 1 is a dose, not a count")

        var given = PatientRecord()
        given.fluids["prbc"] = 2
        XCTAssertEqual(applied(read("2 PRBC", .intraop, record: given), to: given).fluids["prbc"], 4, "added to the total")

        XCTAssertFalse(ids(read("2 PRBC")).contains("blood:prbc"), "not on the Preoperative tab")
        let ordered = read("2 PRBC available", .intraop)
        XCTAssertFalse(ids(ordered).contains("blood:prbc"), "available is not given")
        XCTAssertEqual(ordered.unread, "", "recognized and left out, not unread")
        let cryo = read("cryo 2", .intraop)
        XCTAssertFalse(ids(cryo).contains("blood:cryo"), "2 units or 2 pools: not read")
        XCTAssertTrue(cryo.skipped.contains { $0.hasPrefix("Cryo 2") })
        XCTAssertEqual(cryo.unread, "")
        let neg = read("no PRBC, 2 FFP", .intraop)
        XCTAssertFalse(ids(neg).contains("blood:prbc"))
        XCTAssertEqual(applied(neg).fluids["plasma"], 2)
    }

    func testEachBloodMentionIsItsOwnChip() {
        let q = read("cryo 10, 1 pool cryo", .intraop)
        XCTAssertEqual(q.findings.map(\.id), ["blood:cryo", "blood:cryo:2"])
        let chips = QuickAdd.chips(q, record: PatientRecord())
        XCTAssertEqual(chips.map(\.text), ["Intraop · Cryo +10", "Intraop · Cryo +5 (1 pool) (total 15)"], "the running total on the last")
        XCTAssertEqual(QuickAdd.changes(chips), [.blood("cryo", 10), .blood("cryo", 5)])

        // Either can be left out, and the total is what the chips left on add.
        let first = QuickAdd.chips(q, record: PatientRecord(), dropped: [chips[0].id])
        XCTAssertEqual(first.map(\.id), chips.map(\.id), "a chip keeps its id when another is left out")
        XCTAssertEqual(first.map(\.value), ["Cryo +10", "Cryo +5 (1 pool)"])
        XCTAssertEqual(QuickAdd.changes(first, dropped: [chips[0].id]), [.blood("cryo", 5)])
        let second = QuickAdd.chips(q, record: PatientRecord(), dropped: [chips[1].id])
        XCTAssertEqual(QuickAdd.changes(second, dropped: [chips[1].id]), [.blood("cryo", 10)])

        var given = PatientRecord()
        given.fluids["cryo"] = 10
        let more = QuickAdd.chips(read("cryo 10, 1 pool cryo", .intraop, record: given), record: given, dropped: [chips[1].id])
        XCTAssertEqual(more.map(\.value), ["Cryo +10 (total 20)", "Cryo +5 (1 pool)"], "on the last chip left on")
        var r = given
        PatientNote.apply(QuickAdd.changes(more, dropped: [chips[1].id]), to: &r)
        XCTAssertEqual(r.fluids["cryo"], 20, "what is filed is the total shown")

        let twice = QuickAdd.chips(read("2 PRBC, 2 PRBC", .intraop), record: PatientRecord())
        XCTAssertEqual(twice.map(\.value), ["PRBC +2", "PRBC +2 (total 4)"], "the same amount twice is two chips")
        XCTAssertEqual(Set(twice.map(\.id)).count, 2)
    }

    func testDrips() {
        let q = read("epi 0.05", .intraop)
        let r = applied(q)
        XCTAssertEqual(r.infusions.map(\.drug), ["Epinephrine"])
        XCTAssertEqual(r.infusions.first?.rate, "0.05")
        XCTAssertTrue(r.homeInfusions.isEmpty, "a drip in the OR is the case's")
        XCTAssertEqual(q.findings.first?.note, QuickAdd.noUnitNote)
        XCTAssertEqual(applied(read("epi 0.05")).homeInfusions.map(\.drug), ["Epinephrine"], "on the Preoperative tab: running on arrival")

        let ne = applied(read("norepinephrine 0.1 mcg/kg/min", .intraop))
        XCTAssertEqual(ne.infusions.first?.rate, "0.1 mcg/kg/min", "the note reader's drip, routed to the case")
        XCTAssertTrue(ne.homeInfusions.isEmpty)

        XCTAssertTrue(applied(read("neo 100", .intraop)).infusions.isEmpty, "a bolus or a rate: not read")
        XCTAssertTrue(applied(read("epi 10", .intraop)).infusions.isEmpty, "not a rate written bare")
        XCTAssertTrue(applied(read("off epi 0.05", .intraop)).infusions.isEmpty)
        XCTAssertTrue(applied(read("epi 0.05 off", .intraop)).infusions.isEmpty)
    }

    func testAmbiguousAbbreviations() {
        let q = read("epi 0.05", .intraop)
        XCTAssertEqual(q.ambiguous.map(\.abbreviation), ["epi"], "its usual meaning, to confirm")
        let epidural = read("epi 0.05", .intraop, choices: ["epi@epi-epinephrine": "epi-epidural"])
        XCTAssertTrue(applied(epidural).infusions.isEmpty, "chosen as epidural: no drip")

        let levo = read("levo 0.1", .intraop)
        XCTAssertTrue(applied(levo).infusions.isEmpty, "levothyroxine 0.1 mg is a dose: not read on the usual meaning")
        XCTAssertEqual(levo.ambiguous.map(\.abbreviation), ["levo"])
        XCTAssertEqual(levo.unread, "levo 0.1", "not read: shown as typed, not as the meaning it might have")
        let chosen = read("levo 0.1", .intraop, choices: ["levo@levo-norepinephrine": "levo-norepinephrine"])
        XCTAssertEqual(applied(chosen).infusions.map(\.drug), ["Norepinephrine"])
        XCTAssertEqual(chosen.unread, "")
    }

    func testDevicesRouteByTab() {
        let intra = applied(read("A-line L radial 20G", .intraop))
        XCTAssertEqual(intra.devices.count, 1)
        XCTAssertEqual(intra.devices.first?.kind, .arterial)
        XCTAssertEqual(intra.devices.first?.site, "radial-left")
        XCTAssertEqual(intra.devices.first?.size, "20")
        XCTAssertEqual(intra.devices.first?.placedIntraop, true, "placed in the OR")
        XCTAssertEqual(applied(read("A-line L radial 20G")).devices.first?.placedIntraop, false, "on arrival")
        XCTAssertTrue(applied(read("no A-line")).devices.isEmpty)
        XCTAssertTrue(applied(read("A-line L radial 20G pre-induction")).devices.isEmpty, "preoperatively: still to come")
        XCTAssertEqual(applied(read("A-line L radial 20G pre-induction", .intraop)).devices.count, 1, "in the OR: when it went in")
    }

    func testIntraoperativeAirway() {
        let q = read("VL grade 1, 7.5 ETT 23 cm, easy mask", .intraop)
        let r = applied(q)
        XCTAssertEqual(r.airwayDevice, "Video laryngoscope")
        XCTAssertEqual(r.laryngoscopyGrade, "1")
        XCTAssertEqual(r.tube, "7.5 ETT, 23 cm")
        XCTAssertEqual(r.mask, "easy")
        XCTAssertNil(r.intubation, "not written")
        XCTAssertNil(r.currentAirway, "the airway course, not the airway on arrival")
        XCTAssertTrue(q.ambiguous.isEmpty, "7.5 ETT is a tube")

        let pre = read("VL grade 1, 7.5 ETT 23 cm, easy mask")
        XCTAssertFalse(ids(pre).contains { $0.hasPrefix("intraop-airway:") })
        if case .currentAirway(let id, _, _)? = change(pre, "airway") { XCTAssertEqual(id, "ett") } else { XCTFail("arrives intubated") }

        var tubed = PatientRecord()
        tubed.currentAirway = "ett"
        let arrived = read("VL grade 1", .intraop, record: tubed)
        XCTAssertTrue(arrived.findings.isEmpty, "no airway course for a patient who arrives intubated")

        let two = read("DL grade 2", .intraop)
        XCTAssertEqual(change(two, "intraop-airway:device"), .intraopAirway("device", "Direct laryngoscope"))
        XCTAssertNil(change(two, "intraop-airway:grade"), "2a or 2b is not written")
        XCTAssertTrue(two.skipped.contains { $0.hasPrefix("View grade 2") })
        XCTAssertEqual(applied(read("ETT 8.0 @ 22 at the teeth, 1 attempt", .intraop)).tube, "8.0 ETT, 22 cm at the teeth")
    }

    // MARK: Procedures

    func testProcedures() {
        let q = read("68M for lap chole, HTN")
        XCTAssertEqual(change(q, "procedure"), .procedure("lap chole"))
        XCTAssertEqual(change(q, "age"), .age(68))
        XCTAssertEqual(change(q, "sex"), .sex(.male))
        XCTAssertTrue(ids(q).contains("problem:htn"))
        let r = applied(q)
        XCTAssertEqual(r.procedures.first?.catalogID, "lap-chole")
        XCTAssertTrue(r.highRiskSurgery, "the risk inputs fill from the procedure list")

        let knee = applied(read("L TKA"))
        XCTAssertEqual(knee.procedures.first?.catalogID, "tka")
        XCTAssertEqual(knee.procedures.first?.side, "left")

        let heart = read("CABG x3 + AVR, EF 35%")
        XCTAssertEqual(applied(heart).procedures.map(\.catalogID), ["cabg", "avr"])
        XCTAssertEqual(applied(heart).procedures.first?.detail, "×3")
        XCTAssertFalse(ids(heart).contains("problem:cabg"), "a planned CABG is not a past one")

        XCTAssertEqual(change(read("planned lap chole"), "procedure"), .procedure("lap chole"))
        XCTAssertEqual(change(read("for lap chole HTN DM2"), "procedure"), .procedure("lap chole"), "kept to the procedure")

        let past = read("HTN, CABG 2015")
        XCTAssertNil(change(past, "procedure"), "not at the start, and in the past")
        XCTAssertTrue(ids(past).contains("problem:cabg"))
        XCTAssertNil(change(read("VA ECMO 25F RFV"), "procedure"), "a device, not a planned cannulation")
        XCTAssertNil(change(read("on heparin for DVT"), "procedure"))
    }

    func testPlannedAnestheticFromTheProcedure() {
        let q = read("68M for lap chole")
        XCTAssertEqual(change(q, QuickAdd.planPrefix + "ga"), .anesthetic("ga"), "as the Procedure editor fills it")
        XCTAssertEqual(applied(q).anesthetic, ["ga"])
        let chips = QuickAdd.chips(q, record: PatientRecord())
        guard let plan = chips.first(where: { $0.destination == "Anesthetic" }),
              let procedure = chips.first(where: { $0.destination == "Procedure" }) else { return XCTFail("a chip each") }
        XCTAssertEqual(plan.value, "General (usual plan)")
        XCTAssertEqual(plan.status, .new)

        // Its own chip: left out, the procedure still goes in.
        let without = QuickAdd.changes(chips, dropped: [plan.id])
        XCTAssertTrue(without.contains(.procedure("lap chole")))
        XCTAssertFalse(without.contains(.anesthetic("ga")))
        // Never without its procedure.
        let alone = QuickAdd.chips(q, record: PatientRecord(), dropped: [procedure.id])
        XCTAssertEqual(alone.first { $0.destination == "Anesthetic" }?.canAdd, false)
        XCTAssertFalse(QuickAdd.changes(alone, dropped: [procedure.id]).contains(.anesthetic("ga")))

        // A plan already set is never replaced, and nothing is shown.
        var planned = PatientRecord()
        planned.anesthetic = ["mac"]
        let kept = read("68M for lap chole", record: planned)
        XCTAssertFalse(kept.findings.contains { $0.id.hasPrefix(QuickAdd.planPrefix) })
        XCTAssertFalse(QuickAdd.chips(kept, record: planned).contains { $0.destination == "Anesthetic" })
        var r = planned
        PatientNote.apply(QuickAdd.changes(QuickAdd.chips(kept, record: planned)), to: &r)
        XCTAssertEqual(r.anesthetic, ["mac"])

        XCTAssertFalse(read("68M for lap chole, spinal").findings.contains { $0.id.hasPrefix(QuickAdd.planPrefix) }, "a technique written")
        XCTAssertFalse(read("68M for frobnication").findings.contains { $0.id.hasPrefix(QuickAdd.planPrefix) }, "not on the list")
        var same = PatientRecord()
        same.setProcedures(PlannedProcedure.parse("lap chole"), fillAnesthetic: false)
        XCTAssertFalse(read("68M for lap chole", record: same).findings.contains { $0.id.hasPrefix(QuickAdd.planPrefix) },
                       "the procedure is already recorded, so the bar adds neither")
    }

    // MARK: Negation and identifiers

    func testNegations() {
        XCTAssertFalse(ids(read("No HTN")).contains("problem:htn"))
        XCTAssertFalse(ids(read("denies chest pain")).contains("symptom:chest-pain"))
        XCTAssertTrue(applied(read("no central line")).devices.isEmpty)
    }

    func testNothingFiledFromIdentifiers() {
        let q = read("MRN 1234567 72M for CABG x3 + AVR")
        XCTAssertEqual(q.identifiers, ["a record number"])
        XCTAssertFalse(q.findings.contains { $0.label.contains("1234567") })
        XCTAssertFalse(q.unread.contains("1234567"))
        XCTAssertEqual(change(q, "age"), .age(72), "the rest is still read")
        XCTAssertNotNil(change(q, "procedure"))

        let name = read("Mr Smith 68M HTN")
        XCTAssertEqual(name.identifiers, ["a name"])
        XCTAssertFalse(name.findings.contains { $0.label.contains("Smith") })
        XCTAssertFalse(name.unread.contains("Smith"))
        XCTAssertTrue(ids(name).contains("problem:htn"))

        let called = read("pt name John Smith, K 5.4")
        XCTAssertEqual(called.identifiers, ["a name"])
        XCTAssertFalse(called.unread.contains("John"))
        XCTAssertFalse(called.findings.contains { $0.label.contains("John") || $0.label.contains("Smith") })
        XCTAssertEqual(change(called, "lab:k"), .lab("k", 5.4))
    }

    // MARK: Chips, adding and Undo

    func testChips() {
        var r = PatientRecord()
        r.labs["cr"] = 1.1
        let labs = QuickAdd.chips(read("K 5.4 Cr 1.6", record: r), record: r)
        XCTAssertEqual(labs.map(\.text), ["Labs · K 5.4 H", "Labs · Cr 1.6 H"])
        XCTAssertEqual(labs.last?.statusText, "replaces 1.1")
        XCTAssertNil(labs.first?.statusText)
        XCTAssertEqual(QuickAdd.changes(labs, dropped: [labs[0].id]), [.lab("cr", 1.6)], "a dropped chip is not filed")

        let bp = QuickAdd.chips(read("148/86 72"), record: PatientRecord())
        XCTAssertEqual(bp.map(\.text), ["Vitals · BP 148/86", "Vitals · HR 72"], "a blood pressure is one chip")
        XCTAssertEqual(bp.first?.findings.count, 2)

        var given = PatientRecord()
        given.fluids["prbc"] = 2
        XCTAssertEqual(QuickAdd.chips(read("2 PRBC", .intraop, record: given), record: given).first?.text, "Intraop · PRBC +2 (total 4)")
        XCTAssertEqual(QuickAdd.chips(read("68M for lap chole"), record: PatientRecord()).first { $0.destination == "Procedure" }?.value,
                       "Laparoscopic cholecystectomy")
        XCTAssertTrue(QuickAdd.chips(read("A-line L radial 20G"), record: PatientRecord()).contains { $0.text.hasPrefix("Lines · A-line 20 G") })
        XCTAssertEqual(QuickAdd.chips(read("epi 0.05", .intraop), record: PatientRecord()).first?.text, "Intraop · Epinephrine 0.05 (no unit)")

        // What is already recorded is shown but not filed.
        var known = PatientRecord()
        known.problems = ["htn"]
        let again = QuickAdd.chips(read("HTN", record: known), record: known)
        XCTAssertEqual(again.first?.status, .recorded)
        XCTAssertTrue(QuickAdd.changes(again).isEmpty)
    }

    func testUndoRestoresTheRecordExactly() {
        var book = PatientCaseBook()
        var rec = PatientRecord()
        rec.labs["k"] = 4.0
        rec.updated = Date(timeIntervalSince1970: 1000)
        book.currentRecord = rec
        let before = book.currentRecord
        var after = before
        PatientNote.apply(QuickAdd.changes(QuickAdd.chips(read("K 5.4, 2 PRBC", .preop, record: before), record: before)), to: &after)
        after.updated = Date(timeIntervalSince1970: 2000)
        book.currentRecord = after
        XCTAssertEqual(book.currentRecord.labs["k"], 5.4)
        book.currentRecord = before
        XCTAssertEqual(book.currentRecord, before, "the snapshot, its time stamp included")
    }

    func testLongTextGoesToTheFullNote() {
        XCTAssertTrue(QuickAdd.isLong(String(repeating: "HTN ", count: 51)))
        XCTAssertTrue(QuickAdd.isLong("HTN\nDM2"))
        XCTAssertFalse(QuickAdd.isLong("68M for lap chole, HTN DM2 on insulin, K 5.4"))
    }

    func testScreenshotLines() {
        let pre = read("68M for lap chole, HTN DM2 on insulin, K 5.4 Cr 1.6, A-line L radial 20G")
        for id in ["age", "sex", "procedure", "problem:htn", "problem:dm", "problem:insulin", "lab:k", "lab:cr"] {
            XCTAssertTrue(ids(pre).contains(id), id)
        }
        XCTAssertTrue(pre.findings.contains { $0.id.hasPrefix("device:") })
        XCTAssertTrue(pre.identifiers.isEmpty)
        XCTAssertTrue(pre.ambiguous.isEmpty)

        let intra = read("2 PRBC, ABG 7.29/41/168, epi 0.05", .intraop)
        XCTAssertEqual(ids(intra), ["blood:prbc", "intraop-lab:ph", "intraop-lab:paco2", "intraop-lab:pao2", "intraop-infusion:epinephrine"])
        XCTAssertEqual(intra.ambiguous.map(\.abbreviation), ["epi"])
        XCTAssertEqual(intra.unread, "")

        let vitals = read("148/86 72 95% 16 36.8, 138/4.1/102/24/18/1.1/162, 7.2>12.1/36<210")
        XCTAssertEqual(vitals.ambiguous.map(\.abbreviation), ["SpO₂ 95%"], "the room-air question")
        XCTAssertFalse(ids(vitals).contains("vital:spo2"))
        XCTAssertTrue(ids(vitals).isSuperset(of: ["vital:sbp", "vital:hr", "vital:rr", "vital:temp", "lab:na", "lab:k", "lab:plt"]))

        let heart = read("MRN 1234567 72M for CABG x3 + AVR, EF 35%, no A-line, POEC")
        XCTAssertEqual(change(heart, QuickAdd.planPrefix + "ga"), .anesthetic("ga"))
    }

    // MARK: The new note changes

    func testNewChangesStatusAndApply() {
        var r = PatientRecord()
        let blood = PatientNoteFinding(id: "blood:prbc", section: QuickAdd.intraop, label: "", change: .blood("prbc", 2))
        XCTAssertEqual(PatientNote.status(blood, in: r), .new, "blood adds to the total")

        r.infusions = [PatientInfusion(drug: "Epinephrine", rate: "0.05")]
        let same = PatientNoteFinding(id: "i", section: QuickAdd.intraop, label: "", change: .intraopInfusion("epinephrine", "0.05"))
        XCTAssertEqual(PatientNote.status(same, in: r), .recorded)
        let faster = PatientNoteFinding(id: "i", section: QuickAdd.intraop, label: "", change: .intraopInfusion("epinephrine", "0.1"))
        XCTAssertEqual(PatientNote.status(faster, in: r), .replaces("0.05"))
        PatientNote.apply([faster.change], to: &r)
        XCTAssertEqual(r.infusions.map(\.rate), ["0.1"])

        r.mask = "easy"
        let mask = PatientNoteFinding(id: "m", section: QuickAdd.intraop, label: "", change: .intraopAirway("mask", "difficult"))
        XCTAssertEqual(PatientNote.status(mask, in: r), .replaces("easy"))
        let grade = PatientNoteFinding(id: "g", section: QuickAdd.intraop, label: "", change: .intraopAirway("grade", "1"))
        XCTAssertEqual(PatientNote.status(grade, in: r), .new)
        r.tube = "7.5 ETT, 23 cm at the lip"
        let tube = PatientNoteFinding(id: "t", section: QuickAdd.intraop, label: "", change: .intraopAirway("tube", "7.5 ETT, 23 cm"))
        XCTAssertEqual(PatientNote.status(tube, in: r), .recorded, "less than the record says is already there")
        let other = PatientNoteFinding(id: "t", section: QuickAdd.intraop, label: "", change: .intraopAirway("tube", "8.0 ETT"))
        XCTAssertEqual(PatientNote.status(other, in: r), .replaces("7.5 ETT, 23 cm at the lip"))

        let q = read("K 5.6 Hb 8.4", .intraop)
        let labs = applied(q)
        for f in q.findings { XCTAssertEqual(PatientNote.status(f, in: labs), .recorded, f.label) }
        var set = labs.intraopLabs[0]
        set.values = ["k": 6.1]
        let higher = PatientNoteFinding(id: "intraop-lab:k", section: QuickAdd.intraop, label: "", change: .intraopLabs(set))
        XCTAssertEqual(PatientNote.status(higher, in: labs), .replaces("K 5.6"))
        var twice = labs
        PatientNote.apply([higher.change], to: &twice)
        XCTAssertEqual(twice.intraopLabs.count, 1, "the same set")
        XCTAssertEqual(twice.intraopLabs[0].values["k"], 6.1)
        XCTAssertEqual(twice.intraopLabs[0].values["hb"], 8.4)
    }
}
