import XCTest
@testable import PeriopSignal

/// Fill from a note (PatientNote), sending a patient to a colleague (PatientPacket) and the midnight fasting default.
final class PatientNoteTests: XCTestCase {
    /// 30 October 2026, 08:00 on the device's clock.
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))! }

    private func read(_ text: String) -> PatientNoteReading { PatientNote.read(text, now: now) }
    private func ids(_ text: String) -> Set<String> { Set(read(text).findings.map(\.id)) }
    private func change(_ r: PatientNoteReading, _ id: String) -> PatientNoteChange? { r.findings.first { $0.id == id }?.change }

    func testPatternsCompile() {
        for p in PatientNote.allPatterns { XCTAssertNotNil(p.re, p.pattern) }
    }

    func testClauses() {
        XCTAssertEqual(PatientNote.clauses("65 y.o. male. HTN; DM\nNKDA"), ["65 y.o. male", "HTN", "DM", "NKDA"])
    }

    func testExample() {
        let r = read(PatientNote.example)
        let found = Set(r.findings.map(\.id))
        for id in ["age", "sex", "procedure", "urgency", "anesthetic:ga", "problem:htn", "problem:dm", "problem:insulin", "problem:osa",
                   "problem:cpap", "problem:cad", "problem:pci", "flag:betablocker", "flag:acei", "flag:insulin", "flag:aspirin",
                   "flag:p2y12", "meds", "allergies:penicillin (rash)", "smoking", "height", "weight", "vital:sbp", "vital:dbp", "vital:hr",
                   "vital:spo2", "lab:hb", "lab:cr", "lab:k", "mallampati", "sign:thick-neck", "intake:solids", "intake:clears", "mets"] {
            XCTAssertTrue(found.contains(id), id)
        }
        XCTAssertFalse(found.contains("symptom:chest-pain"), "denied")
        XCTAssertFalse(found.contains("symptom:dyspnea"), "denied")
        XCTAssertEqual(change(r, "procedure"), .procedure("laparoscopic right hemicolectomy"))
        XCTAssertEqual(change(r, "age"), .age(68))
        XCTAssertEqual(change(r, "sex"), .sex(.male))
        XCTAssertEqual(change(r, "mets"), .mets("ge4"))
        XCTAssertEqual(change(r, "intake:solids"), .lastSolids(Calendar.current.startOfDay(for: now)))
        XCTAssertEqual(r.other, "hereditary angioedema", "what nothing was read from goes to Other conditions")
        XCTAssertEqual(r.previous, "appendectomy 2010 under GA; uneventful")
        XCTAssertTrue(r.identifiers.isEmpty)
        let order = r.findings.compactMap { PatientNote.sections.firstIndex(of: $0.section) }
        XCTAssertEqual(order, order.sorted(), "grouped in the order the editors ask")

        var rec = PatientRecord()
        PatientNote.apply(r.findings.map(\.change), to: &rec)
        XCTAssertEqual(PatientNote.missing(rec), [], "the example covers everything the tab asks first")
        XCTAssertEqual(rec.medications, "metoprolol, lisinopril, glargine, aspirin, clopidogrel")
        XCTAssertEqual(rec.allergies, "penicillin (rash)")
        XCTAssertEqual(rec.vitals["sbp"], 148)
        XCTAssertEqual(rec.labs["k"], 4.3)
        XCTAssertEqual(PatientNote.missing(PatientRecord()).first, "age")
    }

    func testNegationFamilyAndHistory() {
        let a = ids("No history of stroke. Father had an MI at 50. Denies chest pain, has HTN.")
        XCTAssertTrue(a.contains("problem:htn"))
        XCTAssertTrue(a.contains("problem:fh-cad"))
        XCTAssertFalse(a.contains("problem:cva"))
        XCTAssertFalse(a.contains("problem:cad"), "the father's MI")
        XCTAssertFalse(a.contains("symptom:chest-pain"))
        XCTAssertEqual(ids("Denies chest pain, SOB, palpitations, syncope or orthopnea. No CAD, has DM."), ["problem:dm"])
        XCTAssertEqual(ids("FHx: CAD, DM, HTN, stroke. Mother with diabetes, has HTN"), ["problem:fh-cad", "problem:htn"])
        let d = read("History of ACS in 2019. Admitted with ACS. Recent NSTEMI 3 weeks ago")
        XCTAssertEqual(Set(d.findings.map(\.id)), ["acute:acs", "problem:cad-recent"], "a past ACS is history; the recent MI replaces the general CAD")
        XCTAssertEqual(d.other, "")
    }

    func testPatientSizeAndUnits() {
        let r = read("5'10\", 180 lbs, 45 y/o female. T 98.6F")
        XCTAssertEqual(change(r, "age"), .age(45))
        XCTAssertEqual(change(r, "sex"), .sex(.female))
        XCTAssertEqual(change(r, "height"), .height(177.8))
        XCTAssertEqual(change(r, "weight"), .weight(81.6))
        XCTAssertEqual(change(r, "vital:temp"), .vital("temp", 37))
        XCTAssertEqual(change(read("Lost 10 kg over 2 months, weighs 70 kg"), "weight"), .weight(70), "a weight change is not the weight")
        let child = read("pt is a 6 month old boy for inguinal hernia repair. no known drug allergies")
        XCTAssertEqual(change(child, "age"), .age(0.5))
        XCTAssertEqual(change(child, "procedure"), .procedure("inguinal hernia repair"))
        XCTAssertEqual(change(child, "nkda"), .nkda)
    }

    func testProcedureTimingAndAnesthetic() {
        let a = read("Scheduled for urgent ORIF left hip tomorrow.")
        XCTAssertEqual(change(a, "procedure"), .procedure("ORIF left hip"))
        XCTAssertEqual(change(a, "urgency"), .urgency(.urgent))
        let b = read("G2P1 at 39 weeks gestation for repeat c-section under spinal.")
        XCTAssertEqual(change(b, "procedure"), .procedure("repeat c-section"))
        XCTAssertNotNil(change(b, "anesthetic:neuraxial"))
        XCTAssertNotNil(change(b, "problem:pregnant"))
        let c = read("72F with severe AS and CKD stage 3 for TAVR under MAC.")
        XCTAssertEqual(change(c, "procedure"), .procedure("TAVR"))
        XCTAssertNil(change(c, "problem:prosthetic-valve"), "a planned TAVR is not a prosthetic valve yet")
        XCTAssertNotNil(change(c, "problem:valve-severe"))
        XCTAssertNotNil(change(c, "anesthetic:mac"))
        let d = read("Healthy 30 yo M for knee arthroscopy. PSH: tonsillectomy as child, no anesthetic complications.")
        XCTAssertEqual(change(d, "procedure"), .procedure("knee arthroscopy"))
        XCTAssertEqual(change(d, "sex"), .sex(.male))
        XCTAssertNotNil(change(d, "nohistory"))
        XCTAssertEqual(d.previous, "tonsillectomy as child; no anesthetic complications")
        let e = read("ASA 3E. ESRD, not on dialysis. EF 25-30%. AF with RVR.")
        XCTAssertEqual(change(e, "asa"), .asa(3, true))
        XCTAssertNotNil(change(e, "problem:aki"), "ESRD not on scheduled dialysis")
        XCTAssertNil(change(e, "problem:ckd"))
        XCTAssertNotNil(change(e, "problem:ef-severe"))
        XCTAssertNotNil(change(e, "acute:arrhythmia"))
    }

    func testMedicinesAndAllergies() {
        let a = read("Allergic to aspirin. Takes apixaban.")
        XCTAssertNotNil(change(a, "allergies:aspirin"))
        XCTAssertNil(change(a, "flag:aspirin"), "a drug named as an allergy is not a medicine")
        XCTAssertNotNil(change(a, "flag:anticoagulant"))
        XCTAssertEqual(change(a, "meds"), .medications("apixaban"))
        let b = read("NKDA. Latex allergy.")
        XCTAssertNil(change(b, "nkda"), "NKDA beside a named allergy keeps the allergy")
        XCTAssertEqual(change(b, "allergies:latex"), .allergies("Latex"))
        let c = read("Meds metoprolol lisinopril and Ozempic last dose Sunday. Sats 92% on 2L NC")
        XCTAssertEqual(change(c, "meds"), .medications("metoprolol lisinopril and Ozempic last dose Sunday"))
        XCTAssertNotNil(change(c, "flag:glp1"))
        XCTAssertNotNil(c.findings.first { $0.id == "vital:spo2" }?.note, "on oxygen, not room air")
        let d = read("70-year-old man for hip replacement history of high blood pressure diabetes sleep apnea uses cpap no chest pain can climb two flights of stairs allergic to penicillin last ate at 8 pm")
        XCTAssertEqual(change(d, "allergies:penicillin"), .allergies("penicillin"))
        XCTAssertEqual(change(d, "procedure"), .procedure("hip replacement"))
        XCTAssertEqual(change(d, "mets"), .mets("ge4"), "a new verb ends the denial")
        XCTAssertNil(change(d, "symptom:chest-pain"))
        XCTAssertNotNil(change(d, "problem:osa"))
    }

    func testIntakeTimes() {
        let cal = Calendar.current
        let r = read("Last ate at 7pm, last clears 0530.")
        XCTAssertEqual(change(r, "intake:solids"), .lastSolids(cal.date(byAdding: .hour, value: -13, to: now)!), "7 pm yesterday")
        XCTAssertEqual(change(r, "intake:clears"), .lastClears(cal.date(bySettingHour: 5, minute: 30, second: 0, of: now)!))
        XCTAssertEqual(PatientNote.clock("6", nil, nil, now: now), cal.date(bySettingHour: 6, minute: 0, second: 0, of: now))
        XCTAssertEqual(PatientNote.clock("10", nil, nil, now: now), cal.date(byAdding: .hour, value: -10, to: now), "10 with no am or pm, at 8 am: 10 pm yesterday")
        XCTAssertEqual(PatientRecord.npoMidnight(now), cal.startOfDay(for: now), "Set time starts at midnight")
    }

    func testStatusAndApply() {
        var rec = PatientRecord()
        rec.problems = ["htn"]
        rec.weightKg = 80
        let poor = PatientNoteFinding(id: "problem:htn-poor", section: PatientNote.Part.history, label: "", change: .problem("htn-poor"))
        XCTAssertEqual(PatientNote.status(poor, in: rec), .replaces("Hypertension, well controlled"))
        PatientNote.apply([poor.change], to: &rec)
        XCTAssertEqual(rec.problems, ["htn-poor"], "the specific form replaces the general one")
        let plain = PatientNoteFinding(id: "problem:htn", section: PatientNote.Part.history, label: "", change: .problem("htn"))
        XCTAssertEqual(PatientNote.status(plain, in: rec), .recorded)
        PatientNote.apply([plain.change], to: &rec)
        XCTAssertEqual(rec.problems, ["htn-poor"])
        let w = PatientNoteFinding(id: "weight", section: PatientNote.Part.patient, label: "", change: .weight(82))
        XCTAssertEqual(PatientNote.status(w, in: rec), .replaces("80 kg"))
        rec.allergies = "latex"
        let nkda = PatientNoteFinding(id: "nkda", section: PatientNote.Part.meds, label: "", change: .nkda)
        XCTAssertFalse(PatientNote.status(nkda, in: rec).canAdd, "NKDA never hides a recorded allergy")
        PatientNote.apply([.nkda], to: &rec)
        XCTAssertFalse(rec.nkda)
        PatientNote.apply([.otherHistory("hereditary angioedema"), .otherHistory("Hereditary angioedema")], to: &rec)
        XCTAssertEqual(rec.otherHistory, "hereditary angioedema", "text already there is not added twice")
    }

    func testIdentifierWarning() {
        XCTAssertEqual(PatientNote.identifiers("DOB 03/14/1958, MRN 1234567, seen by Mr. Smith"), ["a record number", "a date", "a name"])
        XCTAssertEqual(PatientNote.identifiers(PatientNote.example), [])
    }

    // MARK: Sending a patient

    func testPatientPacketRoundTrip() throws {
        let demo = PatientDemo.record
        let packet = PatientPacket(record: demo, sent: Date(timeIntervalSince1970: 1_793_354_400))
        let data = try packet.encoded()
        let back = try PatientPacket.decode(data)
        XCTAssertEqual(back, packet)
        XCTAssertEqual(back.record, demo, "everything entered goes across")
        XCTAssertEqual(back.contents, "History, assessment, airway, intraoperative course and plan")
        XCTAssertThrowsError(try PatientPacket.decode(Data("{\"hello\":1}".utf8))) { XCTAssertEqual($0 as? PatientPacket.Problem, .notAPatient) }
        var newer = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        newer["format"] = 2
        let newerData = try JSONSerialization.data(withJSONObject: newer)
        XCTAssertThrowsError(try PatientPacket.decode(newerData)) { XCTAssertEqual($0 as? PatientPacket.Problem, .newerFormat) }
        XCTAssertThrowsError(try PatientPacket.decode(Data(count: PatientPacket.maxBytes + 1))) { XCTAssertEqual($0 as? PatientPacket.Problem, .tooLarge) }
        XCTAssertTrue(PatientInbox.handles(URL(fileURLWithPath: "/tmp/Patient handoff.periop")))
        XCTAssertFalse(PatientInbox.handles(URL(string: "periopsignal://patient")!))
    }

    @MainActor func testStoreReceiveAndUndo() {
        let store = PatientStore(url: nil)
        store.update { $0.ageYears = 40 }
        store.receive(PatientDemo.record)
        XCTAssertEqual(store.ageYears, 67)
        XCTAssertTrue(store.canUndoReceive)
        store.undoReceive()
        XCTAssertEqual(store.ageYears, 40)
        XCTAssertFalse(store.canUndoReceive)
        let empty = PatientStore(url: nil)
        empty.receive(PatientDemo.record)
        XCTAssertFalse(empty.canUndoReceive, "nothing was replaced")
        empty.update { $0.weightKg = 90 }
        XCTAssertEqual(empty.weightKg, 90)
    }
}
