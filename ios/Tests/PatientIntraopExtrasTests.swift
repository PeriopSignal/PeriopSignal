import XCTest
@testable import PeriopSignal

/// My Patient: intraoperative labs, blood products, major considerations and code status, on the cards and in both
/// handoffs; and code status read from a note.
final class PatientIntraopExtrasTests: XCTestCase {
    private var demo: PatientRecord { PatientDemo.record }

    // MARK: Saving

    func testOlderRecordsOpenWithTheNewFieldsEmpty() throws {
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data("{\"procedure\":\"Hernia repair\"}".utf8))
        XCTAssertEqual(old.procedure, "Hernia repair")
        XCTAssertTrue(old.intraopLabs.isEmpty)
        XCTAssertTrue(old.considerations.isEmpty)
        XCTAssertEqual(old.considerationsNote, "")
        XCTAssertNil(old.codeStatus)
        XCTAssertNil(old.codeStatusPlan)
        XCTAssertFalse(old.polst)
        let odd = try JSONDecoder().decode(PatientRecord.self, from: Data("{\"codeStatus\":\"zombie\",\"intraopLabs\":[{\"values\":{\"ph\":7.3}}]}".utf8))
        XCTAssertNil(odd.codeStatus, "an unknown value is dropped, not fatal")
        XCTAssertEqual(odd.intraopLabs.first?.values["ph"], 7.3)
        XCTAssertNil(odd.intraopLabs.first?.time)
    }

    func testRoundTrip() throws {
        for r in [PatientDemo.record, PatientDemo.cardiac, PatientDemo.dnr] {
            let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
            XCTAssertEqual(back, r)
        }
        XCTAssertFalse(PatientDemo.record.intraopLabs.isEmpty)
        XCTAssertEqual(PatientDemo.record.codeStatus, .full)
    }

    func testParts() {
        let ids = PatientEditor.intraopParts.map(\.id)
        XCTAssertTrue(ids.contains("labs"))
        XCTAssertEqual(ids.last, "considerations", "the considerations close the tab")
        XCTAssertEqual(PatientEditor.intraopPart("labs").title, "Labs")
    }

    // MARK: Labs

    func testIntraopLabRanges() {
        for k in IntraopLabs.keys { XCTAssertNotNil(PatientLabs.test(k), k) }
        XCTAssertFalse(PatientLabs.tests(.main).contains { $0.key == "ph" }, "the preoperative screen does not list blood gases")
        XCTAssertEqual(PatientLabs.test("ph")?.rangeText(for: nil), "7.38–7.44")
        XCTAssertEqual(PatientLabs.flag("ph", 7.30, sex: nil), .low)
        XCTAssertEqual(PatientLabs.flag("ph", 7.40, sex: nil), .normal)
        XCTAssertEqual(PatientLabs.flag("paco2", 50, sex: nil), .high)
        XCTAssertEqual(PatientLabs.flag("pao2", 400, sex: nil), .normal, "high on oxygen is expected")
        XCTAssertEqual(PatientLabs.flag("pao2", 60, sex: nil), .low)
        XCTAssertEqual(PatientLabs.flag("hco3a", 27, sex: nil), .high, "arterial 23–26")
        XCTAssertEqual(PatientLabs.flag("hco3", 27, sex: nil), .normal, "serum 23–28")
        XCTAssertEqual(PatientLabs.flag("lactate", 1.3, sex: nil), .high, "ABIM: under 1.3")
        XCTAssertEqual(PatientLabs.flag("lactate", 1.2, sex: nil), .normal)
        XCTAssertEqual(PatientLabs.flag("ica", 1.10, sex: nil), .low)
        XCTAssertEqual(PatientLabs.flag("ptt", 40, sex: nil), .high)
        XCTAssertEqual(PatientLabs.flag("hb", 11.6, sex: .male), .low, "reused with its sex ranges")
        XCTAssertEqual(PatientLabs.flag("glucose", 192, sex: nil), .high, "perioperative range reused")
        XCTAssertFalse(PatientLabs.test("be")?.isRated ?? true, "no sourced range")
        XCTAssertFalse(PatientLabs.test("act")?.isRated ?? true, "read against the target")
        XCTAssertEqual(PatientLabs.flag("act", 600, sex: nil), .normal)
    }

    func testLatestSet() {
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date())
        let a = IntraopLabSet(time: day.addingTimeInterval(9 * 3600), values: ["ph": 7.30])
        let b = IntraopLabSet(time: day.addingTimeInterval(11 * 3600), values: ["ph": 7.36])
        let blank = IntraopLabSet(time: day.addingTimeInterval(12 * 3600))
        var r = PatientRecord()
        r.intraopLabs = [b, blank, a]
        XCTAssertEqual(IntraopLabs.latest(r)?.id, b.id, "the latest with anything in it")
        XCTAssertEqual(IntraopLabs.ordered(r.intraopLabs).map(\.id), [b.id, a.id])
        r.intraopLabs = [IntraopLabSet(values: ["k": 4]), IntraopLabSet(values: ["k": 5])]
        XCTAssertEqual(IntraopLabs.latest(r)?.values["k"], 5, "without times, the last added")
        XCTAssertNil(IntraopLabs.latest(PatientRecord()))
    }

    func testLastLabsLine() throws {
        let l = try XCTUnwrap(IntraopLabs.lastLine(demo))
        XCTAssertEqual(l.label, "Last labs")
        XCTAssertTrue(l.text.hasPrefix("10:40 · pH 7.33 L · PaCO₂ 47 H · PaO₂ 212 · HCO₃ 24 · BE -1.5"), l.text)
        XCTAssertEqual(l.marks, ["pH 7.33 L", "PaCO₂ 47 H", "Hb 11.6 L", "iCa 1.14 L", "Glu 192 H"])
        for m in l.marks { XCTAssertTrue(l.text.contains(m), m) }
        let short = try XCTUnwrap(IntraopLabs.lastLine(demo, abnormalOnly: true))
        XCTAssertEqual(short.text, "10:40 · pH 7.33 L · PaCO₂ 47 H · Hb 11.6 L · iCa 1.14 L · Glu 192 H · 6 more not flagged")
        let card = PatientSummary.intraopPartLines(demo, "labs")
        XCTAssertEqual(card.first?.marks.count, 5, "the card keeps the bold red")
        XCTAssertTrue(HandoffWriter.marks(demo).contains("Hb 11.6 L"))
        let cardiac = try XCTUnwrap(IntraopLabs.lastLine(PatientDemo.cardiac))
        XCTAssertTrue(cardiac.text.contains("PTT 52 H"), cardiac.text)
        XCTAssertTrue(cardiac.text.contains("ACT 128"), cardiac.text)
        XCTAssertTrue(cardiac.text.contains("ROTEM/TEG: EXTEM CT 92 s"), cardiac.text)
        XCTAssertTrue(cardiac.text.hasPrefix("13:20"), "the later of the two sets")
    }

    // MARK: Blood products

    func testBloodProducts() {
        XCTAssertEqual(BloodProducts.ids.count, 6)
        for id in BloodProducts.ids { XCTAssertTrue(PatientCatalog.fluids.contains { $0.id == id }, id) }
        var r = demo
        r.fluids = ["crystalloid": 1000, "prbc": 2, "plasma": 1, "cryo": 10, "cellSaver": 450]
        XCTAssertEqual(BloodProducts.text(r), "PRBC 2 units · FFP 1 unit · Cryo 10 units · Cell saver 450 mL")
        let lines = PatientSummary.intraopLines(r)
        XCTAssertEqual(lines.first { $0.label == "In" }?.text, "Crystalloid 1000 mL", "blood is not listed twice")
        XCTAssertTrue(PatientSummary.intraopPartLines(r, "fluids").contains { $0.label == "Blood products" })
        XCTAssertTrue(HandoffWriter.text(r).contains("Blood products: PRBC 2 units · FFP 1 unit"))
        XCTAssertTrue(HandoffWriter.shortText(r).contains("Blood products: PRBC 2 units"))
        XCTAssertNil(BloodProducts.line(demo), "none given in the demo colectomy")
        XCTAssertFalse(HandoffWriter.shortText(demo).contains("Blood products"))
    }

    // MARK: Considerations

    func testConsiderations() throws {
        XCTAssertEqual(IntraopConsiderations.flags.count, 8)
        let t = try XCTUnwrap(IntraopConsiderations.text(demo))
        XCTAssertEqual(t, "Positioning or pressure points; Steep Trendelenburg with arms tucked for 3 h; pressure points padded, eyes taped")
        let full = HandoffWriter.text(demo)
        let key = try XCTUnwrap(full.range(of: "KEY CONSIDERATIONS"))
        let history = try XCTUnwrap(full.range(of: "HISTORY"))
        XCTAssertLessThan(key.lowerBound, history.lowerBound, "near the top")
        XCTAssertTrue(full.contains("Positioning or pressure points; Steep"))
        XCTAssertTrue(HandoffWriter.shortText(demo).contains("Key considerations: Positioning or pressure points"))
        XCTAssertEqual(PatientSummary.intraopPartLines(demo, "considerations").first?.alert, true)
        var other = PatientRecord(); other.considerations = ["other"]
        XCTAssertEqual(IntraopConsiderations.text(other), "Other")
        XCTAssertNil(IntraopConsiderations.text(PatientRecord()))
        var hard = PatientRecord(); hard.intubation = "difficult"
        XCTAssertEqual(IntraopConsiderations.suggested(hard).map(\.id), ["difficult-airway"])
        hard.considerations = ["difficult-airway"]
        XCTAssertTrue(IntraopConsiderations.suggested(hard).isEmpty)
    }

    // MARK: Code status

    func testCodeStatusText() {
        XCTAssertEqual(PatientCodeStatus.text(demo), "Full code")
        XCTAssertEqual(PatientCodeStatus.text(PatientDemo.dnr), "DNR/DNI (POLST on file); modified for the procedure: Accepts intubation and vasopressors for the procedure; no chest compressions or defibrillation. Original orders resume on leaving the PACU")
        var r = PatientRecord(); r.codeStatus = .dnr
        XCTAssertEqual(PatientCodeStatus.text(r), "DNR; perioperative plan not yet discussed")
        XCTAssertEqual(PatientCodeStatus.line(r)?.alert, true)
        XCTAssertEqual(PatientCodeStatus.line(r)?.marks, ["perioperative plan not yet discussed"])
        r.codeStatus = .full; r.codeStatusPlan = .suspended
        XCTAssertEqual(PatientCodeStatus.text(r), "Full code", "no plan for full code")
        XCTAssertEqual(PatientCodeStatus.line(r)?.alert, false)
        r.codeStatus = .limited; r.codeStatusLimits = "no compressions"; r.codeStatusPlan = nil
        XCTAssertEqual(PatientCodeStatus.text(r), "Limited: no compressions; perioperative plan not yet discussed")
        var p = PatientRecord(); p.polst = true
        XCTAssertEqual(PatientCodeStatus.text(p), "POLST on file")
        XCTAssertNil(PatientCodeStatus.text(PatientRecord()))
        XCTAssertTrue(PatientCodeStatus.note.contains("required reconsideration"))
        XCTAssertTrue(PatientCodeStatus.url.hasPrefix("https://www.asahq.org/"))
    }

    func testCodeStatusOnCardAndHandoffs() {
        XCTAssertEqual(PatientSummary.assessmentLines(demo).first { $0.label == "Code status" }?.text, "Full code")
        let dnr = PatientDemo.dnr
        let full = HandoffWriter.text(dnr)
        XCTAssertTrue(full.contains("Code status: DNR/DNI (POLST on file); modified for the procedure"), full)
        XCTAssertEqual(full.components(separatedBy: "Code status:").count, 2, "once, at the top, not again under Assessment")
        let short = HandoffWriter.shortText(dnr)
        XCTAssertTrue(short.contains("Code status: DNR/DNI"), short)
        XCTAssertLessThanOrEqual(HandoffWriter.shortText(demo).components(separatedBy: "\n").count, 14, "still one screen")
    }
}

/// Fill from a note: DNR, DNI, DNR/DNI, full code and POLST, with the perioperative plan when the note gives it.
final class PatientNoteCodeStatusTests: XCTestCase {
    private func change(_ text: String) -> PatientNoteChange? {
        PatientNote.read(text).findings.first { $0.id == "codeStatus" }?.change
    }

    func testPatternsCompile() {
        for p in PatientCodeStatus.patterns { XCTAssertNotNil(p.re, p.pattern) }
    }

    func testReads() {
        XCTAssertEqual(change("DNR/DNI."), .codeStatus(.dnrDni, polst: false, plan: nil))
        XCTAssertEqual(change("Code status: DNR-DNI"), .codeStatus(.dnrDni, polst: false, plan: nil))
        XCTAssertEqual(change("Do not resuscitate, do not intubate"), .codeStatus(.dnrDni, polst: false, plan: nil))
        XCTAssertEqual(change("Patient is DNR"), .codeStatus(.dnr, polst: false, plan: nil))
        XCTAssertEqual(change("Do not resuscitate"), .codeStatus(.dnr, polst: false, plan: nil), "the phrase's own 'not' is no negation")
        XCTAssertEqual(change("DNI"), .codeStatus(.dni, polst: false, plan: nil))
        XCTAssertEqual(change("Full code"), .codeStatus(.full, polst: false, plan: nil))
        XCTAssertEqual(change("Code status: full"), .codeStatus(.full, polst: false, plan: nil))
        XCTAssertEqual(change("POLST on file"), .codeStatus(nil, polst: true, plan: nil))
        XCTAssertEqual(change("Full code, not DNR"), .codeStatus(.full, polst: false, plan: nil))
        XCTAssertNil(change("No DNR on file"))
        XCTAssertNil(change("68 yo M for colectomy"))
    }

    func testPlanAndMerging() {
        XCTAssertEqual(change("DNR suspended for the procedure"), .codeStatus(.dnr, polst: false, plan: .suspended))
        XCTAssertEqual(change("DNR, full code for surgery"), .codeStatus(.dnr, polst: false, plan: .suspended))
        XCTAssertEqual(change("DNR/DNI maintained during the procedure"), .codeStatus(.dnrDni, polst: false, plan: .maintained))
        XCTAssertEqual(change("DNI, modified for the OR: okay to intubate"), .codeStatus(.dni, polst: false, plan: .modified))
        XCTAssertEqual(change("DNR/DNI, POLST on file; DNR suspended for the procedure"), .codeStatus(.dnrDni, polst: true, plan: .suspended),
                       "two sentences put together")
        XCTAssertEqual(change("DNR. Full code for the OR."), .codeStatus(.dnr, polst: false, plan: .suspended))
        let reading = PatientNote.read("DNR/DNI, POLST on file")
        XCTAssertEqual(reading.findings.first { $0.id == "codeStatus" }?.section, PatientNote.Part.assessment)
        XCTAssertFalse(reading.other.contains("DNR"), "read, not left over: " + reading.other)
        XCTAssertFalse(reading.other.contains("POLST"), reading.other)
    }

    func testStatusAndApply() throws {
        let f = try XCTUnwrap(PatientNote.read("DNR/DNI, POLST on file; DNR suspended for the procedure").findings.first { $0.id == "codeStatus" })
        XCTAssertEqual(f.label, "Code status: DNR/DNI · POLST on file · suspended for the procedure")
        var r = PatientRecord()
        XCTAssertEqual(PatientNote.status(f, in: r), .new)
        PatientNote.apply([f.change], to: &r)
        XCTAssertEqual(r.codeStatus, .dnrDni)
        XCTAssertTrue(r.polst)
        XCTAssertEqual(r.codeStatusPlan, .suspended)
        XCTAssertEqual(PatientNote.status(f, in: r), .recorded)
        r.codeStatusPlan = .maintained
        XCTAssertEqual(PatientNote.status(f, in: r), .replaces("maintained as is"))
        var full = PatientRecord(); full.codeStatus = .full
        XCTAssertEqual(PatientNote.status(f, in: full), .replaces("Full code"))
        var unknown = PatientRecord(); unknown.codeStatus = .notDiscussed
        XCTAssertEqual(PatientNote.status(f, in: unknown), .replaces("not discussed"))
        var polstOnly = PatientRecord()
        let p = PatientCodeStatus.finding(nil, polst: true, plan: nil)
        XCTAssertEqual(PatientNote.status(p, in: polstOnly), .new)
        PatientNote.apply([p.change], to: &polstOnly)
        XCTAssertTrue(polstOnly.polst)
        XCTAssertNil(polstOnly.codeStatus, "a POLST alone does not say which orders")
        var plain = PatientRecord()
        PatientNote.apply([.codeStatus(.full, polst: false, plan: .suspended)], to: &plain)
        XCTAssertEqual(plain.codeStatus, .full)
        XCTAssertNil(plain.codeStatusPlan, "no plan for full code")
    }
}
