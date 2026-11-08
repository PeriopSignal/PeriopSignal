import XCTest
@testable import PeriopSignal

/// 1.10 (Ben, Nov 7), helper B: Past Surgical History's bar never touches the planned procedure (notes-img1); previous
/// cardiac surgery is one entry of Past surgical history wherever it is entered; echo LV and RV size and prosthesis details;
/// the intraoperative TEE's pre-bypass and post-bypass exams (notes-img3).
final class Clinical110Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 8))! }

    private func psh(_ line: String, record: PatientRecord = PatientRecord()) -> QuickAddReading {
        QuickAdd.read(line, record: record, tab: .preop, now: now, surgicalHistory: true)
    }

    private func applied(_ q: QuickAddReading, to record: PatientRecord = PatientRecord()) -> PatientRecord {
        var r = record
        PatientNote.apply(QuickAdd.changes(QuickAdd.chips(q, record: record)), to: &r)
        return r
    }

    private func isProcedure(_ f: PatientNoteFinding) -> Bool {
        if case .procedure = f.change { return true }
        return false
    }

    /// The case in Ben's notes-img1: AVR with supracoronary ascending aorta replacement planned.
    private var avrPlanned: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 71; r.sex = .male
        r.setProcedures(PlannedProcedure.parse("AVR with supracoronary ascending aorta replacement"))
        return r
    }

    // MARK: 1. Past Surgical History's bar (notes-img1)

    func testThePastSurgicalHistoryBarHasItsOwnPlace() {
        XCTAssertEqual(PatientEditor.workup("surgeries").quickAddPlace, .pastSurgery)
        XCTAssertTrue(QuickAddPlace.pastSurgery.surgicalHistory)
        XCTAssertFalse(QuickAddPlace.editor(intraop: false).surgicalHistory)
        XCTAssertEqual(QuickAddPlace.pastSurgery.tab, .preop)
        XCTAssertTrue(QuickAddPlace.pastSurgery.compact)
        XCTAssertEqual(QuickAdd.placeholder(.pastSurgery), QuickAdd.pastSurgeryPlaceholder)
        // Other editors keep the Preoperative tab's reading.
        XCTAssertEqual(PatientEditor.workup("echo").quickAddPlace, .editor(intraop: false))
        XCTAssertEqual(PatientEditor.workup("intrathoracic").quickAddPlace, .pastSurgery, "its operations are Past surgical history entries")
    }

    func testAnOperationTypedThereIsAPastOperationNeverTheProcedure() {
        let r = avrPlanned
        let before = r.procedures
        // The root cause: the editors' bar read a line as the Preoperative tab does, where an operation opening the line is
        // the planned procedure.
        XCTAssertTrue(QuickAdd.read("tonsillectomy", record: r, tab: .preop, now: now).findings.contains(where: isProcedure),
                      "the Preoperative tab's reading (unchanged there)")
        let q = psh("tonsillectomy", record: r)
        XCTAssertFalse(q.findings.contains(where: isProcedure), "no Procedure chip")
        XCTAssertFalse(q.findings.contains { $0.id.hasPrefix(QuickAdd.planPrefix) }, "no planned anesthetic")
        XCTAssertEqual(q.findings.count, 1)
        guard case .pastSurgery(let text, _)? = q.findings.first?.change else { return XCTFail("a past operation") }
        XCTAssertEqual(text, "tonsillectomy")
        XCTAssertEqual(q.unread, "")
        let after = applied(q, to: r)
        XCTAssertEqual(after.procedures, before, "the planned procedure is untouched")
        XCTAssertEqual(after.procedure, r.procedure)
        XCTAssertEqual(after.surgeries.map(\.text), ["Tonsillectomy"])
        XCTAssertFalse(after.surgeries[0].intrathoracic, "not intrathoracic")
        XCTAssertNil(after.hx.cardiacSurgeryID)
    }

    func testSeveralOperationsWithDates() {
        let r = avrPlanned
        // The bar's example before it was shortened to fit one line at 375 pt: three operations, one not in the list.
        let line = "CABG ×3 2015, appendectomy, R TKA 06/2019"
        let q = psh(line, record: r)
        XCTAssertFalse(q.findings.contains(where: isProcedure))
        // Three operations, and the history the CABG implies ("Prior CABG", RCRI ischemic heart disease), as 1.9 and the
        // note reader's "PSH:" lines file it (review 1.10: restored; never a second Past surgical history entry).
        XCTAssertEqual(q.findings.count, 4, q.findings.map(\.label).joined(separator: "; "))
        XCTAssertEqual(q.findings.filter { if case .pastSurgery = $0.change { return true }; return false }.count, 3)
        XCTAssertTrue(q.findings.contains { $0.change == .problem("cabg") })
        let after = applied(q, to: r)
        XCTAssertEqual(after.procedures, r.procedures)
        XCTAssertEqual(after.surgeries.count, 3)
        let found = Set(after.surgeries.compactMap { $0.procedures.first?.catalogID })
        XCTAssertTrue(found.isSuperset(of: ["cabg", "tka"]), "\(found)")
        XCTAssertTrue(after.surgeries.contains { $0.name.lowercased().contains("appendectomy") })
        let cabg = after.surgeries.first { $0.procedures.first?.catalogID == "cabg" }
        XCTAssertEqual(cabg?.date, PatientMonthYear(year: 2015))
        XCTAssertTrue(cabg?.intrathoracic ?? false, "a sternotomy: Previous intrathoracic surgery")
        XCTAssertEqual(after.hx.cardiacSurgeryID, cabg?.id, "and the cardiovascular page's Previous cardiac surgery")
        let tka = after.surgeries.first { $0.procedures.first?.catalogID == "tka" }
        XCTAssertEqual(tka?.date, PatientMonthYear(month: 6, year: 2019))
        XCTAssertEqual(tka?.procedures.first?.side, "right")
        XCTAssertFalse(tka?.intrathoracic ?? true)
        // Added again: nothing doubles.
        XCTAssertEqual(applied(psh(line, record: after), to: after).surgeries.count, 3)
    }

    /// The bar's example, short enough for the one-line bar at 375 pt, still reads in full as two dated operations.
    func testThePlaceholderReadsAsTwoDatedOperations() {
        let r = avrPlanned
        let q = psh(QuickAdd.pastSurgeryPlaceholder, record: r)
        XCTAssertFalse(q.findings.contains(where: isProcedure))
        XCTAssertEqual(q.findings.count, 2, q.findings.map(\.label).joined(separator: "; "))
        let after = applied(q, to: r)
        XCTAssertEqual(after.procedures, r.procedures)
        XCTAssertEqual(after.surgeries.count, 2)
        XCTAssertEqual(after.surgeries.first { $0.procedures.first?.catalogID == "cabg" }?.date, PatientMonthYear(year: 2015))
        let tka = after.surgeries.first { $0.procedures.first?.catalogID == "tka" }
        XCTAssertEqual(tka?.date, PatientMonthYear(month: 6, year: 2019))
        XCTAssertEqual(tka?.procedures.first?.side, "right")
        XCTAssertLessThanOrEqual(QuickAdd.pastSurgeryPlaceholder.count, 30, "fits the compact bar at 375 pt")
    }

    func testPlanningWordsAndDiagnosesAreNotFiledThere() {
        let r = avrPlanned
        for line in ["for TKA", "scheduled for lap chole", "Procedure: tonsillectomy"] {
            let q = psh(line, record: r)
            XCTAssertFalse(q.findings.contains(where: isProcedure), line)
            XCTAssertEqual(applied(q, to: r).procedures, r.procedures, line)
        }
        XCTAssertTrue(applied(psh("AAA 4.8 cm")).surgeries.isEmpty, "a diagnosis is not an operation")
        XCTAssertTrue(applied(psh("HTN")).surgeries.isEmpty)
        // A transcatheter procedure: past, not intrathoracic, not cardiac surgery.
        let teer = applied(psh("MitraClip 2022"))
        XCTAssertEqual(teer.surgeries.first?.procedures.first?.catalogID, "teer-mitral")
        XCTAssertEqual(teer.surgeries.first?.date, PatientMonthYear(year: 2022))
        XCTAssertFalse(teer.surgeries.first?.intrathoracic ?? true)
        XCTAssertNil(teer.hx.cardiacSurgeryID)
        // A thoracic operation is intrathoracic, not cardiac.
        let vats = applied(psh("VATS lobectomy 2018"))
        XCTAssertTrue(vats.surgeries.first?.intrathoracic ?? false)
        XCTAssertNil(vats.hx.cardiacSurgeryID)
    }

    // MARK: 2. Previous cardiac surgery is one entry (Ben: "but not double post if entered twice")

    func testCardiovascularPageFirstThenTheEvaluation() {
        var r = PatientRecord()
        PatientHistoryDetails.setCardiacSurgery("CABG ×3 2019", &r)
        XCTAssertEqual(r.surgeries.count, 1, "in Past surgical history")
        XCTAssertTrue(r.surgeries[0].intrathoracic, "and under Previous intrathoracic surgery")
        XCTAssertEqual(PatientPreop.previousCardiacSurgery(r).count, 1)
        // The evaluation's "+ Previous cardiac surgery": the same operation added there merges into the entry.
        let id = PatientHistoryDetails.addIntrathoracic(&r)
        XCTAssertEqual(r.surgeries.count, 2, "a blank row while it is typed")
        var s = try! XCTUnwrap(r.surgeries.first { $0.id == id })
        s.setProcedures(PlannedProcedure.parse("CABG"))
        PatientHistoryDetails.editSurgery(s, &r)
        XCTAssertEqual(r.surgeries.count, 1, "no double post")
        XCTAssertEqual(PatientHistoryDetails.cardiacSurgeryText(r), "CABG ×3 2019", "the cardiovascular page's entry stays")
        // Editing it on the cardiovascular page edits the same entry.
        PatientHistoryDetails.setCardiacSurgery("CABG ×4 2019", &r)
        XCTAssertEqual(r.surgeries.map(\.name), ["CABG ×4 2019"])
        // Clearing it there takes its entry away (the existing rule).
        PatientHistoryDetails.setCardiacSurgery("", &r)
        XCTAssertTrue(r.surgeries.isEmpty)
        XCTAssertTrue(PatientPreop.previousCardiacSurgery(r).isEmpty)
    }

    func testTheEvaluationFirstThenTheCardiovascularPage() {
        var r = PatientRecord()
        let id = PatientHistoryDetails.addIntrathoracic(&r)
        var s = try! XCTUnwrap(r.surgeries.first { $0.id == id })
        s.setProcedures(PlannedProcedure.parse("AVR"))
        s.date = PatientMonthYear(month: 6, year: 2015)
        PatientHistoryDetails.editSurgery(s, &r)
        XCTAssertEqual(r.surgeries.count, 1)
        XCTAssertEqual(r.surgeries[0].text, "Aortic valve replacement (06/2015)", "in Past surgical history")
        XCTAssertEqual(r.hx.cardiacSurgeryID, id, "the cardiovascular page's Previous cardiac surgery")
        XCTAssertEqual(PatientHistoryDetails.cardiacSurgeryText(r), "Aortic valve replacement")
        XCTAssertEqual(PatientPreop.previousCardiacSurgery(r).map(\.id), [id])
        // Typed on the cardiovascular page: the same entry, renamed; its date stays.
        PatientHistoryDetails.setCardiacSurgery("Mechanical AVR", &r)
        XCTAssertEqual(r.surgeries.count, 1)
        XCTAssertEqual(r.surgeries[0].id, id)
        XCTAssertEqual(r.surgeries[0].text, "Mechanical AVR (06/2015)")
        // Entered a second time, in Past Surgical History's bar or a note: still one.
        PatientNote.apply([.pastSurgery("AVR", PatientMonthYear(month: 6, year: 2015))], to: &r)
        XCTAssertEqual(r.surgeries.count, 1)
        PatientNote.apply([.cardiacSurgery("AVR 2015")], to: &r)
        XCTAssertEqual(r.surgeries.count, 1)
    }

    func testAPastSurgicalHistoryEntryIsTheCardiovascularPagesToo() {
        var r = PatientRecord()
        r.surgeries.append(PatientSurgery())
        var s = r.surgeries[0]
        s.setProcedures(PlannedProcedure.parse("CABG x3"))
        PatientHistoryDetails.editSurgery(s, &r)
        XCTAssertEqual(r.hx.cardiacSurgeryID, s.id, "picked in Past Surgical History: the cardiovascular page shows it")
        // A second CABG entry with no date is the same operation.
        r.surgeries.append(PatientSurgery())
        var t = r.surgeries[1]
        t.setProcedures(PlannedProcedure.parse("CABG"))
        PatientHistoryDetails.editSurgery(t, &r)
        XCTAssertEqual(r.surgeries.count, 1)
        // Two different operations stay two.
        r.surgeries.append(PatientSurgery())
        var u = r.surgeries[1]
        u.setProcedures(PlannedProcedure.parse("appendectomy"))
        PatientHistoryDetails.editSurgery(u, &r)
        XCTAssertEqual(r.surgeries.count, 2)
        XCTAssertEqual(r.hx.cardiacSurgeryID, s.id)
    }

    /// A record saved before 1.10 kept the evaluation's operations in their own list: they open in Past surgical history.
    func testASavedIntrathoracicListOpensInPastSurgicalHistory() throws {
        var old = PatientRecord()
        old.surgeries = [PatientSurgery(name: "Appendectomy", date: PatientMonthYear(year: 1998)),
                         PatientSurgery(name: "Right VATS wedge", date: PatientMonthYear(year: 2020), intrathoracic: true)]
        old.intrathoracic = [PatientSurgery(name: "CABG ×3", date: PatientMonthYear(year: 2015), intrathoracic: true),
                             PatientSurgery(name: "Right VATS wedge", intrathoracic: true),
                             PatientSurgery(intrathoracic: true)]
        let r = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(old))
        XCTAssertTrue(r.intrathoracic.isEmpty)
        XCTAssertEqual(r.surgeries.map(\.text), ["Appendectomy (1998)", "Right VATS wedge (2020)", "CABG ×3 (2015)"],
                       "each once; a blank row is dropped")
        XCTAssertEqual(r.allIntrathoracic.map(\.name), ["Right VATS wedge", "CABG ×3"])
        XCTAssertEqual(PatientHistoryDetails.cardiacSurgeryText(r), "CABG ×3", "the cardiovascular page shows the cardiac one")
        XCTAssertEqual(PatientPreop.previousCardiacSurgery(r).map(\.name), ["CABG ×3"])
        // Read again: unchanged.
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again.surgeries, r.surgeries)
        XCTAssertEqual(again.hx.cardiacSurgeryID, r.hx.cardiacSurgeryID)
    }

    // MARK: 3. Echo: LV and RV size, prosthesis details, free text

    func testSizesProsthesisDetailsAndNotesInTheSummary() {
        var e = PatientEcho()
        e.lvSize = .dilated
        XCTAssertEqual(e.summary, "LV dilated")
        e.lv = .moderate; e.lvef = 35
        XCTAssertEqual(e.phrases.first, "LV EF 35%, moderately reduced, dilated")
        e.rvSize = .normal
        XCTAssertTrue(e.phrases.contains("RV size normal"))
        e.rv = .mild; e.rvSize = .dilated
        XCTAssertTrue(e.phrases.contains("RV function mildly reduced, dilated"))
        e.aortic = EchoValve(stenosis: .normal, prosthesis: "Bioprosthetic", prosthesisDetail: "29 Magna")
        XCTAssertTrue(e.phrases.contains("AVR bioprosthetic: 29 Magna"))
        e.mitral = EchoValve(prosthesis: "Mechanical")
        XCTAssertTrue(e.phrases.contains("MVR mechanical"))
        e.tricuspid = EchoValve(prosthesis: "Repair or ring", prosthesisDetail: "28 mm ring")
        XCTAssertTrue(e.phrases.contains("Tricuspid repair or ring: 28 mm ring"))
        e.mitral.notes = "Well seated, no paravalvular leak"
        e.lvNotes = "New inferior hypokinesis"
        XCTAssertTrue(e.phrases.contains("Mitral: Well seated, no paravalvular leak"))
        XCTAssertTrue(e.phrases.contains("LV: New inferior hypokinesis"))
        // Report order: LV, its notes, RV, the valves (mitral, tricuspid, aortic).
        let p = e.phrases
        XCTAssertLessThan(p.firstIndex(of: "LV: New inferior hypokinesis")!, p.firstIndex(of: "RV function mildly reduced, dilated")!)
        XCTAssertLessThan(p.firstIndex(of: "MVR mechanical")!, p.firstIndex(of: "AVR bioprosthetic: 29 Magna")!)
        // Notes or a detail alone count as findings.
        var n = PatientEcho()
        n.aortic.notes = "x"
        XCTAssertFalse(n.isEmpty)
        XCTAssertFalse(EchoValve(prosthesisDetail: "29 Magna").isEmpty)
        // The detail box shows for every prosthesis or repair chip (Ben: mechanical, bioprosthetic, repair or ring).
        for k in EchoValve.prostheses { XCTAssertTrue(EchoValve.takesDetail(k), k) }
        XCTAssertFalse(EchoValve.takesDetail(""))
        // Echo normal still sets function and valves only.
        var normal = PatientEcho()
        normal.applyNormal()
        XCTAssertNil(normal.lvSize)
        XCTAssertNil(normal.rvSize)
    }

    func testEchoSavedBefore110StillOpens() throws {
        let json = #"{"lv":"mild","lvef":45,"aortic":{"stenosis":"severe","prosthesis":"Bioprosthetic"},"study":"TTE"}"#
        let e = try JSONDecoder().decode(PatientEcho.self, from: Data(json.utf8))
        XCTAssertNil(e.lvSize)
        XCTAssertNil(e.rvSize)
        XCTAssertEqual(e.lvNotes, "")
        XCTAssertEqual(e.aortic.prosthesisDetail, "")
        XCTAssertEqual(e.aortic.notes, "")
        XCTAssertEqual(e.summary, "TTE: LV EF 45%, mildly reduced; Severe AS; AVR bioprosthetic")
        var f = e
        f.lvSize = .dilated; f.rvNotes = "TAPSE 14 mm"; f.mitral.notes = "Eccentric jet"; f.aortic.prosthesisDetail = "23 mm"
        XCTAssertEqual(try JSONDecoder().decode(PatientEcho.self, from: JSONEncoder().encode(f)), f)
    }

    func testFreeTextIsCapitalizedForTheBriefs() {
        var r = PatientRecord()
        r.intraopEchoPost.aortic.notes = "well seated"
        r.intraopEchoPost.lvNotes = "hyperdynamic"
        r.echoFindings.aortic = EchoValve(prosthesis: "Bioprosthetic", prosthesisDetail: "magna ease 23")
        let c = r.capitalized
        XCTAssertEqual(c.intraopEchoPost.aortic.notes, "Well seated")
        XCTAssertEqual(c.intraopEchoPost.lvNotes, "Hyperdynamic")
        XCTAssertEqual(c.echoFindings.aortic.prosthesisDetail, "Magna ease 23")
    }

    // MARK: 4. Intraoperative TEE: pre-bypass and post-bypass (notes-img3)

    private var bypassCase: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 71; r.sex = .male
        r.setProcedures(PlannedProcedure.parse("AVR"))
        var pre = PatientEcho()
        pre.study = "TEE"
        pre.lv = .normal; pre.lvef = 60
        pre.rv = .normal
        pre.mitral = EchoValve(regurgitation: .mild, stenosis: .normal)
        pre.tricuspid = EchoValve(regurgitation: .trivial, stenosis: .normal)
        pre.aortic = EchoValve(regurgitation: .moderate, stenosis: .severe)
        pre.aorta = "Sinus 4.0 cm, Ascending 4.5 cm"
        r.intraopEcho = pre
        return r
    }

    func testTheHandoffShowsPreAndPost() throws {
        var r = bypassCase
        // The pre-bypass exam alone (and every 1.9 save): its findings, as before 1.10.
        var tee = try XCTUnwrap(PatientBriefs.handoff(r, now: now).first { $0.key == "tee" })
        XCTAssertEqual(tee.text, "LV EF 60%, normal; RV function normal; Mild MR; Trivial TR; Severe AS; Moderate AR; Aorta: Sinus 4.0 cm, Ascending 4.5 cm")
        // With the post-bypass exam: a Pre line and a Post line.
        var post = r.intraopEcho.copiedForPostBypass()
        post.aortic = EchoValve(regurgitation: .normal, stenosis: .normal, prosthesis: "Bioprosthetic", prosthesisDetail: "29 Magna")
        post.aorta = ""
        r.intraopEchoPost = post
        tee = try XCTUnwrap(PatientBriefs.handoff(r, now: now).first { $0.key == "tee" })
        XCTAssertEqual(tee.label, "Intraoperative TEE")
        XCTAssertEqual(tee.text.components(separatedBy: "\n"), [
            "Pre: LV EF 60%, normal; RV function normal; Mild MR; Trivial TR; Severe AS; Moderate AR; Aorta: Sinus 4.0 cm, Ascending 4.5 cm",
            "Post: LV EF 60%, normal; RV function normal; Mild MR; Trivial TR; AVR bioprosthetic: 29 Magna",
        ])
        XCTAssertEqual(HandoffStyle.labelRange(Substring("Post: LV EF 60%")).map { String("Post: LV EF 60%"[$0]) }, "Post:", "the labels are bold")
        // The echo notes typed under them follow.
        r.echo = "No new wall motion abnormality"
        tee = try XCTUnwrap(PatientBriefs.handoff(r, now: now).first { $0.key == "tee" })
        XCTAssertEqual(tee.text.components(separatedBy: "\n").last, "No new wall motion abnormality")
        // Only what is entered: a post-bypass exam alone reads as Post.
        var postOnly = r
        postOnly.intraopEcho = PatientEcho()
        postOnly.echo = ""
        tee = try XCTUnwrap(PatientBriefs.handoff(postOnly, now: now).first { $0.key == "tee" })
        XCTAssertTrue(tee.text.hasPrefix("Post: LV EF 60%"))
        XCTAssertFalse(tee.text.contains("Pre:"))
        // Nothing entered: no block.
        var none = r
        none.intraopEcho = PatientEcho(); none.intraopEchoPost = PatientEcho(); none.echo = ""
        XCTAssertNil(PatientBriefs.handoff(none, now: now).first { $0.key == "tee" })
    }

    func testIntraopPartsAndTheIntraoperativeLines() {
        let pre = bypassCase.intraopEcho
        XCTAssertTrue(PatientEcho.intraopParts(pre: PatientEcho(), post: PatientEcho()).isEmpty)
        XCTAssertEqual(PatientEcho.intraopParts(pre: pre, post: PatientEcho()).map(\.label), [nil])
        XCTAssertFalse(PatientEcho.intraopParts(pre: pre, post: PatientEcho())[0].text.hasPrefix("TEE"), "the study word is the label's")
        var post = PatientEcho()
        post.lvef = 55
        XCTAssertEqual(PatientEcho.intraopParts(pre: pre, post: post).map(\.label), ["Pre", "Post"])
        XCTAssertEqual(PatientEcho.intraopParts(pre: PatientEcho(), post: post).map(\.label), ["Post"])
        // Starting the post-bypass exam from the pre-bypass one copies the findings, not the study.
        let copy = pre.copiedForPostBypass()
        XCTAssertNil(copy.study)
        XCTAssertEqual(copy.aortic, pre.aortic)
        XCTAssertEqual(copy.lvef, pre.lvef)
        // A 1.9 save's intraoperative echo opens as the pre-bypass exam; the post-bypass one is empty.
        var r = bypassCase
        r.intraopEchoPost = post
        let saved = try! JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(saved.intraopEchoPost, post)
        XCTAssertEqual(saved.intraopEcho, r.intraopEcho)
        var older = bypassCase
        older.intraopEchoPost = PatientEcho()
        var json = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(older)) as! [String: Any]
        json.removeValue(forKey: "intraopEchoPost")
        let opened = try! JSONDecoder().decode(PatientRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(opened.intraopEcho, bypassCase.intraopEcho)
        XCTAssertTrue(opened.intraopEchoPost.isEmpty)
    }
}
