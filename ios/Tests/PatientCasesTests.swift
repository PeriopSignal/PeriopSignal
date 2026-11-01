import XCTest
@testable import PeriopSignal

/// Several cases by room, the case archive (date only, no time or room, deleted after the retention period) and the
/// room directory.
final class PatientCasesTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("PatientCasesTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func defaults() -> UserDefaults {
        let name = "PatientCasesTests." + UUID().uuidString
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: Migration

    @MainActor func testOneRecordSavedBy16BecomesTheFirstCase() async throws {
        let url = folder.appendingPathComponent("patient.json")
        var old = PatientDemo.record
        old.updated = date(2026, 10, 30, 7, 15)
        try JSONEncoder().encode(old).write(to: url)   // what 1.6 wrote: one PatientRecord

        let store = PatientStore(url: url)
        XCTAssertEqual(store.cases.count, 1)
        XCTAssertEqual(store.currentCase.room, "", "no room")
        XCTAssertEqual(store.currentCase.label, "Case 1")
        XCTAssertEqual(store.currentCase.created, old.updated)
        XCTAssertEqual(store.record.procedure, old.procedure, "the editors see the same record")
        XCTAssertEqual(store.record.devices.count, old.devices.count)
        XCTAssertEqual(store.ageYears, 67)

        store.update { $0.weightKg = 97 }
        try await Task.sleep(nanoseconds: 900_000_000)
        let data = try Data(contentsOf: url)
        let book = try XCTUnwrap(try? JSONDecoder().decode(PatientCaseBook.self, from: data), "saved as cases from now on")
        XCTAssertEqual(book.cases.count, 1)
        XCTAssertEqual(book.current.record.weightKg, 97)
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true, "not backed up")

        let reopened = PatientStore(url: url)
        XCTAssertEqual(reopened.cases.count, 1)
        XCTAssertEqual(reopened.weightKg, 97)
        XCTAssertEqual(reopened.ageYears, 67)
    }

    func testBookDecoding() throws {
        let migrated = try XCTUnwrap(PatientCaseBook.decode(Data("{\"weightKg\": 70, \"future\": 1}".utf8)))
        XCTAssertEqual(migrated.cases.count, 1)
        XCTAssertEqual(migrated.current.record.weightKg, 70, "an older record still opens")
        XCTAssertTrue(PatientCaseBook.decode(Data("{}".utf8))?.isEmpty ?? false, "an empty 1.6 record is an empty book")
        XCTAssertNil(PatientCaseBook.decode(Data("not json".utf8)))
        XCTAssertNil(PatientCaseBook.decode(Data("{\"kind\": \"something.else\", \"cases\": []}".utf8)), "not taken for an empty patient")

        var first = PatientRecord()
        first.ageYears = 50
        first.procedure = "Laparoscopic cholecystectomy"
        var b = PatientCaseBook(migrating: first)
        b.add(room: "  CVOR 3 ", phone: "216-555-0103")
        let again = try XCTUnwrap(PatientCaseBook.decode(try b.encoded()))
        XCTAssertEqual(again, b)
        XCTAssertEqual(again.current.room, "CVOR 3", "trimmed")
        XCTAssertEqual(again.cases.map(\.label), ["Case 1", "CVOR 3"])
        XCTAssertTrue(PatientCaseBook().isEmpty)
        XCTAssertFalse(b.isEmpty)
    }

    // MARK: Add, switch, end

    @MainActor func testAddSwitchAndEndCases() throws {
        let store = PatientStore(url: nil)
        store.update { $0.ageYears = 50 }
        let first = store.currentCase.id

        store.addCase(room: "OR 12", phone: "216-555-0112")
        XCTAssertEqual(store.cases.count, 2)
        XCTAssertEqual(store.currentCase.label, "OR 12")
        XCTAssertTrue(store.isEmpty, "a new case starts empty")
        store.update { $0.weightKg = 80 }
        let or12 = store.currentCase.id

        store.selectCase(first)
        XCTAssertEqual(store.ageYears, 50)
        XCTAssertNil(store.weightKg, "each case keeps its own record")
        store.selectCase(or12)
        XCTAssertEqual(store.weightKg, 80)

        store.addCase()
        XCTAssertEqual(store.currentCase.label, "Case 3", "numbered as added")
        let case3 = store.currentCase.id

        store.selectCase(or12)
        let entry = try XCTUnwrap(store.endCase())
        XCTAssertEqual(store.cases.map(\.id), [first, case3])
        XCTAssertEqual(store.currentCase.id, case3, "the next case opens")
        XCTAssertEqual(store.archive.entries.first?.id, entry.id)

        XCTAssertNil(store.endCase(), "an empty case keeps no summary")
        XCTAssertEqual(store.cases.map(\.id), [first])
        XCTAssertEqual(store.ageYears, 50)

        store.addCase(room: "EP 2")
        XCTAssertEqual(store.currentCase.label, "EP 2")
        XCTAssertNil(store.endCase(keepSummary: false))
        store.endCase(keepSummary: false)
        XCTAssertEqual(store.cases.count, 1, "a fresh case takes the place of the last")
        XCTAssertEqual(store.currentCase.label, "Case 1")
        XCTAssertTrue(store.isEmpty)
        XCTAssertEqual(store.archive.entries.filter { $0.id == entry.id }.count, 1, "ending without a summary keeps nothing new")
    }

    @MainActor func testUndoStaysWithItsCase() {
        let store = PatientStore(url: nil)
        store.update { $0.ageYears = 30 }
        store.clear()
        XCTAssertTrue(store.canUndo)
        store.addCase(room: "OR 3")
        XCTAssertFalse(store.canUndo, "a change of case ends Undo, so it can't land in another case")
        store.update { $0.ageYears = 61 }
        store.setRoom("OR 4", phone: "")
        XCTAssertEqual(store.currentCase.room, "OR 4")
        store.receive(PatientDemo.record)
        XCTAssertEqual(store.ageYears, 67)
        XCTAssertEqual(store.currentCase.room, "OR 4", "a patient from a colleague opens in the current case")
        store.undoReceive()
        XCTAssertEqual(store.ageYears, 61)
    }

    @MainActor func testClearKeepsTheOtherCasesOnDisk() async throws {
        let url = folder.appendingPathComponent("patient.json")
        let store = PatientStore(url: url)
        store.update { $0.ageYears = 44 }
        store.addCase(room: "OR 1")
        store.update { $0.ageYears = 55 }
        try await Task.sleep(nanoseconds: 900_000_000)
        store.clear()
        let book = try XCTUnwrap(PatientCaseBook.decode(try Data(contentsOf: url)), "written at once")
        XCTAssertEqual(book.cases.count, 2)
        XCTAssertTrue(book.current.record.isEmpty)
        XCTAssertEqual(book.current.room, "OR 1", "the room stays with the case")
        store.endCase(keepSummary: false)
        store.endCase(keepSummary: false)
        try await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "nothing left: the file is removed")
    }

    // MARK: The archive

    func testArchiveKeepsNoRoomAndNoTime() throws {
        var r = PatientDemo.record
        r.todos = "Call OR 12 at (216) 555-0112 by 14:30; or12 has the cell saver; epinephrine 1:10,000 ready"
        r.lastSolids = date(2026, 10, 30, 22, 15)
        r.lastClears = date(2026, 10, 31, 5, 40)
        let c = PatientCase(number: 1, record: r, room: "OR 12", roomPhone: "216-555-0112")
        let now = date(2026, 10, 31, 15, 47)
        let e = PatientArchiveWriter.entry(for: c, now: now)

        XCTAssertEqual(e.day, "2026-10-31", "the date only")
        XCTAssertNotNil(e.day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression))
        XCTAssertTrue(e.procedure.hasPrefix("Laparoscopic sigmoid colectomy"), e.procedure)
        XCTAssertTrue(e.text.hasPrefix("ANESTHESIA HANDOFF"))
        XCTAssertTrue(e.text.contains("Laparoscopic sigmoid colectomy"))
        XCTAssertTrue(e.text.contains("TAP block"), "the full handoff")
        for gone in ["OR 12", "or12", "Or 12", "555-0112", "5550112", "14:30", "15:47", "22:15", "05:40", "08:10", "Last intake", "Prepared with"] {
            XCTAssertFalse(e.text.localizedCaseInsensitiveContains(gone), "\(gone) is left out of the summary")
        }
        XCTAssertTrue(e.text.contains("Call [room] at [room phone] by --:--"), e.text)
        XCTAssertTrue(e.text.contains("Cefazolin 2 g --:--"), "times typed in a note")
        XCTAssertTrue(e.text.contains("epinephrine 1:10,000"), "a ratio is not a time")
        XCTAssertTrue(e.text.hasSuffix("Archived in Periop Signal, 31 Oct 2026. Check against the chart."))

        // What is saved: an id, the day, the procedure line and the text; no room, phone or time stamp.
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["id", "day", "procedure", "text"])
        let raw = String(decoding: try JSONEncoder().encode(e), as: UTF8.self)
        XCTAssertFalse(raw.contains("OR 12"))
        XCTAssertFalse(raw.contains("555-0112"))
    }

    func testScrubLeavesOtherNumbersAlone() {
        XCTAssertEqual(PatientArchiveWriter.scrub("IABP 1:1, I:E 1:2, Hb 12.5, BP 148/86", room: "12", phone: ""), "IABP 1:1, I:E 1:2, Hb 12.5, BP 148/86",
                       "a room that is only a number isn't searched for")
        XCTAssertEqual(PatientArchiveWriter.scrub("Back to CVOR 3 at 7:05 pm", room: "cvor 3", phone: ""), "Back to [room] at --:-- pm")
        XCTAssertEqual(PatientArchiveWriter.scrub("Ext 4512 called", room: "", phone: "4512"), "Ext [room phone] called")
        XCTAssertEqual(PatientArchiveWriter.scrub("Lactate 2.1 at 23:59", room: "", phone: "12"), "Lactate 2.1 at --:--")
    }

    @MainActor func testEndedCaseInTheArchiveHasNoRoom() throws {
        let store = PatientStore(url: folder.appendingPathComponent("patient.json"))
        store.addCase(room: "CVOR 3", phone: "216-555-0103")
        store.update { $0 = PatientDemo.cardiac }
        let e = try XCTUnwrap(store.endCase(now: date(2026, 10, 31, 18, 20)))
        XCTAssertEqual(e.day, "2026-10-31")
        XCTAssertFalse(e.text.contains("CVOR"))
        XCTAssertTrue(e.text.contains("VA ECMO") || e.text.contains("ECMO"), "the cardiac handoff")
        let file = folder.appendingPathComponent("archive.json")
        let raw = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        XCTAssertFalse(raw.contains("CVOR"), "the archive file holds no room")
        XCTAssertFalse(raw.contains("18:20"))
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    @MainActor func testArchiveExpiresAfterTheRetentionPeriod() throws {
        let d = defaults()
        let url = folder.appendingPathComponent("archive.json")
        let archive = PatientArchive(url: url, defaults: d)
        XCTAssertEqual(archive.retentionDays, 7, "7 days unless changed")
        XCTAssertEqual(PatientArchive.retentionChoices, [1, 3, 7, 30])
        XCTAssertEqual(PatientArchive.retentionChoices.map(PatientArchive.retentionLabel), ["24 h", "3 days", "7 days", "30 days"])

        let e = PatientArchiveEntry(day: "2026-10-20", procedure: "Case", text: "ANESTHESIA HANDOFF")
        archive.add(e, now: date(2026, 10, 20, 9))
        archive.prune(now: date(2026, 10, 27, 23, 59))
        XCTAssertEqual(archive.entries.count, 1, "kept at least 7 days")
        archive.prune(now: date(2026, 10, 28, 0, 0))
        XCTAssertTrue(archive.entries.isEmpty, "deleted at the first midnight after")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "an empty archive has no file")

        archive.setRetention(1, now: date(2026, 10, 30, 12))
        archive.add(PatientArchiveEntry(day: "2026-10-30", procedure: "Case", text: "x"), now: date(2026, 10, 30, 23))
        archive.prune(now: date(2026, 10, 31, 23, 59))
        XCTAssertEqual(archive.entries.count, 1, "24 h: still there the next day")
        archive.prune(now: date(2026, 11, 1, 0, 1))
        XCTAssertTrue(archive.entries.isEmpty)

        archive.add(PatientArchiveEntry(day: "not a day", procedure: "Case", text: "x"), now: date(2026, 10, 31))
        XCTAssertTrue(archive.entries.isEmpty, "an entry without a readable date is deleted")

        archive.setRetention(5)
        XCTAssertEqual(archive.retentionDays, 1, "only the offered choices")
        archive.setRetention(30)
        XCTAssertEqual(PatientArchive(url: nil, defaults: d).retentionDays, 30, "the choice is kept")

        let e1 = PatientArchiveEntry(day: "2026-10-29", procedure: "B", text: "b")
        let e2 = PatientArchiveEntry(day: "2026-10-31", procedure: "C", text: "c")
        let e3 = PatientArchiveEntry(day: "2026-10-29", procedure: "A", text: "a")
        for x in [e1, e2, e3] { archive.add(x, now: date(2026, 10, 31)) }
        XCTAssertEqual(archive.byDay.map(\.day), ["2026-10-31", "2026-10-29"], "newest day first")
        archive.delete(e2.id)
        XCTAssertEqual(archive.entries.count, 2)
        archive.deleteAll()
        XCTAssertTrue(archive.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(archive.lockEnabled, "the lock is off by default")
    }

    @MainActor func testArchiveIsKeptOnDiskUntilItExpires() throws {
        let url = folder.appendingPathComponent("archive.json")
        let d = defaults()
        let archive = PatientArchive(url: url, defaults: d)
        let today = PatientArchiveWriter.day(Date())
        archive.add(PatientArchiveEntry(day: today, procedure: "Case", text: "ANESTHESIA HANDOFF"))
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true, "not backed up")
        XCTAssertEqual(PatientArchive(url: url, defaults: d).entries.count, 1, "reopened")
        let old = PatientArchiveEntry(day: "2020-01-01", procedure: "Old", text: "x")
        archive.add(old, now: date(2020, 1, 1))
        XCTAssertEqual(PatientArchive(url: url, defaults: d).entries.map(\.procedure), ["Case"], "pruned when it opens")
    }

    func testLabelsAndKeptThrough() {
        let now = date(2026, 10, 31, 9)
        XCTAssertEqual(PatientArchiveWriter.label("2026-10-31", now: now), "Today")
        XCTAssertEqual(PatientArchiveWriter.label("2026-10-30", now: now), "Yesterday")
        XCTAssertEqual(PatientArchiveWriter.label("2026-10-29", now: now), "Thu 29 Oct")
        XCTAssertEqual(PatientArchiveWriter.label("2025-10-29", now: now), "29 Oct 2025")
        let e = PatientArchiveEntry(day: "2026-10-31", procedure: "Case", text: "x")
        XCTAssertEqual(e.expires(retentionDays: 7), date(2026, 11, 8, 0))
        XCTAssertEqual(PatientArchiveDetail.keptText(e, retentionDays: 7, now: now), "Kept through Sat 7 Nov")
        XCTAssertEqual(PatientArchiveDetail.keptText(PatientArchiveEntry(day: "2026-10-24", procedure: "Case", text: "x"), retentionDays: 7, now: now), "Kept through today")
    }

    // MARK: Rooms

    @MainActor func testRoomDirectory() throws {
        let url = folder.appendingPathComponent("rooms.json")
        let dir = PatientRoomDirectory(url: url)
        XCTAssertTrue(dir.rooms.isEmpty)
        dir.save(name: "OR 12", phone: "216-555-0112")
        dir.save(name: "CVOR 3", phone: "216-555-0103")
        dir.save(name: " or  12 ", phone: "")
        XCTAssertEqual(dir.rooms.count, 2, "one entry per room, whatever the case or spacing")
        XCTAssertEqual(dir.rooms.first?.phone, "216-555-0112", "an empty phone keeps the saved one; last used first")
        XCTAssertEqual(dir.room(named: "Or 12")?.phone, "216-555-0112")
        XCTAssertEqual(dir.matches("cv").map(\.name), ["CVOR 3"])
        XCTAssertEqual(dir.matches("").count, 2)
        dir.save(name: "", phone: "216-555-0199")
        XCTAssertEqual(dir.rooms.count, 2, "a phone needs a room")

        let reopened = PatientRoomDirectory(url: url)
        XCTAssertEqual(reopened.rooms.map { PatientRoom.key($0.name) }, ["or 12", "cvor 3"])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        XCTAssertEqual(Set(json.flatMap(\.keys)), ["id", "name", "phone"], "no dates: a room and a time could point to a patient")
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)

        reopened.remove(reopened.rooms[0].id)
        XCTAssertEqual(PatientRoomDirectory(url: url).rooms.map(\.name), ["CVOR 3"])
        for i in 0..<50 { reopened.save(name: "Room \(i)", phone: "") }
        XCTAssertEqual(reopened.rooms.count, PatientRoomDirectory.maxRooms)
    }

    @MainActor func testSettingARoomRemembersIt() {
        let store = PatientStore(url: nil)
        store.setRoom("EP 2", phone: "216-555-0102", remember: true)
        XCTAssertEqual(store.currentCase.label, "EP 2")
        XCTAssertEqual(store.currentCase.roomPhone, "216-555-0102")
        XCTAssertEqual(store.rooms.room(named: "ep 2")?.phone, "216-555-0102")
        store.addCase()
        store.setRoom("OR 9", phone: "", remember: false)
        XCTAssertNil(store.rooms.room(named: "OR 9"), "kept only when asked")
        XCTAssertFalse(store.currentCase.hasPhone)
    }

    func testPhoneLinks() {
        XCTAssertEqual(PatientPhone.callURL("216-555-0112")?.absoluteString, "tel:2165550112")
        XCTAssertEqual(PatientPhone.textURL("216-555-0112")?.absoluteString, "sms:2165550112")
        XCTAssertEqual(PatientPhone.callURL("+1 (216) 555-0112 ext. 4512")?.absoluteString, "tel:+12165550112,4512")
        XCTAssertEqual(PatientPhone.textURL("+1 (216) 555-0112 ext. 4512")?.absoluteString, "sms:+12165550112")
        XCTAssertEqual(PatientPhone.callURL("4-5512")?.absoluteString, "tel:45512")
        XCTAssertNil(PatientPhone.callURL("12"))
        XCTAssertNil(PatientPhone.callURL(""))
        XCTAssertNil(PatientPhone.textURL("OR 12"))
    }

    // MARK: Screenshots and terms

    func testDemoRoomsAndTerms() throws {
        let seed = PatientDemo.rooms(select: 2)
        XCTAssertEqual(seed.book.cases.map(\.label), ["OR 12", "CVOR 3", "EP 2"])
        XCTAssertEqual(seed.book.current.label, "CVOR 3")
        XCTAssertEqual(seed.archived.count, 1)
        XCTAssertFalse(seed.archived[0].text.contains("OR 7"))
        XCTAssertFalse(seed.archived[0].text.contains("07:55"))
        XCTAssertEqual(seed.book.cases.last?.detail, "Atrial fibrillation ablation")

        let archive = try XCTUnwrap(Terms.sections.first { $0.title == "Case archive and rooms" })
        XCTAssertTrue(archive.body.hasPrefix("No patient identifiers"))
        XCTAssertTrue(archive.body.contains("date only, no time or room"))
        XCTAssertTrue(archive.body.contains("7 days"))
        XCTAssertTrue(Terms.privacy.contains { $0.title == "Case archive & rooms" && $0.body.contains("stay on this phone") })
    }
}
