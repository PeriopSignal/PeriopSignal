import XCTest
@testable import PeriopSignal

/// Ben, Nov 23: "Have ability to change bypass start time. And add total bypass time to handoff (have ability to add new bypass run too)".
/// The bypass and the aortic cross-clamp are lists of runs (BypassRuns.swift): each has a start and, once ended, an end; a case saved
/// with the old two times reads as one run; the legacy keys are still written; the handoff gets one line each with the total.
final class Bypass115Tests: XCTestCase {

    private let cal = Calendar.current

    /// Today (a fixed day) at this clock time, so the clock text does not depend on the machine's time zone.
    private func at(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: h, minute: m, second: s)) ?? Date()
    }

    private func course() -> HeparinCourse { HeparinCourse(purpose: "bypass", goal: 480, actEvery: 30) }

    private func decode(_ json: String) throws -> HeparinCourse {
        try JSONDecoder().decode(HeparinCourse.self, from: Data(json.utf8))
    }

    private func keys(_ h: HeparinCourse) throws -> [String: Any] {
        let data = try JSONEncoder().encode(h)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func block(_ blocks: [SummaryBlock], _ key: String) throws -> SummaryBlock {
        try XCTUnwrap(blocks.first { $0.key == key }, "block \(key) in \(blocks.map(\.key))")
    }

    /// Two ended bypass runs: 08:40-10:12 (1 h 32 min) and 10:35-10:55 (20 min).
    private func twoRuns() -> HeparinCourse {
        var h = course()
        h.bypassRuns = [BypassRun(start: at(8, 40), end: at(10, 12)), BypassRun(start: at(10, 35), end: at(10, 55))]
        return h
    }

    // MARK: A case saved before runs

    func testAnOlderRecordWithOnAndOffReadsAsOneRun() throws {
        let h = try decode(#"{"purpose":"bypass","bypassOn":1000,"bypassOff":4600}"#)
        XCTAssertEqual(h.bypassRuns.count, 1)
        XCTAssertEqual(h.bypassRuns[0].start, Date(timeIntervalSinceReferenceDate: 1000))
        XCTAssertEqual(h.bypassRuns[0].end, Date(timeIntervalSinceReferenceDate: 4600), "its end is kept when it is not before its start")
        XCTAssertFalse(h.onBypass)
        XCTAssertTrue(h.clampRuns.isEmpty)
    }

    func testAnOlderRecordWithOffBeforeOnReadsAsAnOpenRun() throws {
        // The old "Bypass on" pressed again cleared the off time; a record whose off is earlier than its on had a new run started.
        let h = try decode(#"{"purpose":"bypass","bypassOn":5000,"bypassOff":1000}"#)
        XCTAssertEqual(h.bypassRuns.count, 1)
        XCTAssertNil(h.bypassRuns[0].end, "the run is still open")
        XCTAssertTrue(h.onBypass)
        let on = try decode(#"{"purpose":"bypass","bypassOn":5000}"#)
        XCTAssertTrue(on.onBypass)
        XCTAssertEqual(on.bypassRuns.count, 1)
    }

    func testAnOlderRecordWithNoBypassHasNoRunsAndAnOffAloneMakesNone() throws {
        XCTAssertTrue(try decode(#"{"purpose":"bypass"}"#).bypassRuns.isEmpty)
        let offOnly = try decode(#"{"purpose":"bypass","bypassOff":1000}"#)
        XCTAssertTrue(offOnly.bypassRuns.isEmpty)
        XCTAssertFalse(offOnly.onBypass)
    }

    func testTheLegacyKeysAreWrittenAsTheLatestRun() throws {
        var h = twoRuns()
        var k = try keys(h)
        XCTAssertEqual(k["bypassOn"] as? Double, at(10, 35).timeIntervalSinceReferenceDate, "the latest run's start")
        XCTAssertEqual(k["bypassOff"] as? Double, at(10, 55).timeIntervalSinceReferenceDate, "and its end")
        XCTAssertNotNil(k["bypassRuns"], "the runs themselves")
        // An open latest run: a build before this one reads on bypass (an on and no off).
        h.bypassRuns[1].end = nil
        k = try keys(h)
        XCTAssertEqual(k["bypassOn"] as? Double, at(10, 35).timeIntervalSinceReferenceDate)
        XCTAssertNil(k["bypassOff"])
        // No runs: neither key, and no list.
        k = try keys(course())
        XCTAssertNil(k["bypassOn"]); XCTAssertNil(k["bypassOff"]); XCTAssertNil(k["bypassRuns"]); XCTAssertNil(k["clampRuns"])
    }

    func testRunsSurviveAnEncodeAndDecodeAndKeepTheirOrderAndIds() throws {
        var h = twoRuns()
        h.clampRuns = [BypassRun(start: at(9, 5), end: at(10, 0))]
        let back = try JSONDecoder().decode(HeparinCourse.self, from: try JSONEncoder().encode(h))
        XCTAssertEqual(back, h)
        XCTAssertEqual(back.bypassRuns.map(\.id), h.bypassRuns.map(\.id))
        // A list saved out of order reads back in start order.
        let shuffled = try decode(#"{"purpose":"bypass","bypassRuns":[{"id":"00000000-0000-0000-0000-000000000002","start":200,"end":300},{"id":"00000000-0000-0000-0000-000000000001","start":10,"end":20}]}"#)
        XCTAssertEqual(shuffled.bypassRuns.map(\.start.timeIntervalSinceReferenceDate), [10, 200])
        // Runs win over the legacy keys when both are there.
        let both = try decode(#"{"purpose":"bypass","bypassOn":999,"bypassRuns":[{"id":"00000000-0000-0000-0000-000000000001","start":10,"end":20}]}"#)
        XCTAssertEqual(both.bypassRuns.count, 1)
        XCTAssertEqual(both.bypassRuns[0].start.timeIntervalSinceReferenceDate, 10)
    }

    // MARK: Starting and ending

    func testBypassOnTwiceWithAnOffBetweenKeepsBothRuns() {
        var h = course()
        XCTAssertTrue(h.startRun(.bypass, at: at(8, 40)))
        XCTAssertTrue(h.onBypass)
        XCTAssertFalse(h.startRun(.bypass, at: at(8, 41)), "no second run while one is open")
        XCTAssertEqual(h.bypassRuns.count, 1)
        XCTAssertTrue(h.endRun(.bypass, at: at(10, 12)))
        XCTAssertFalse(h.onBypass)
        XCTAssertFalse(h.endRun(.bypass, at: at(10, 13)), "nothing open to end")
        XCTAssertTrue(h.startRun(.bypass, at: at(10, 35)))
        XCTAssertEqual(h.bypassRuns.count, 2, "the first run is kept")
        XCTAssertEqual(h.bypassRuns[0].end, at(10, 12))
        XCTAssertEqual(h.bypassRuns[1].start, at(10, 35))
        XCTAssertTrue(h.onBypass)
    }

    func testEndingARunNeverGivesAnEndBeforeItsStart() {
        var h = course()
        h.startRun(.bypass, at: at(8, 40))
        h.endRun(.bypass, at: at(8, 39))
        XCTAssertEqual(h.bypassRuns[0].end, at(8, 40))
    }

    // MARK: Totals

    func testTheTotalWithOneTwoAndAnOpenRun() {
        var h = course()
        h.bypassRuns = [BypassRun(start: at(8, 40), end: at(10, 12))]
        XCTAssertEqual(h.totalSeconds(.bypass, at: at(12, 0)), 92 * 60)
        h = twoRuns()
        XCTAssertEqual(h.totalSeconds(.bypass, at: at(12, 0)), 112 * 60, "92 + 20 min")
        h.bypassRuns.append(BypassRun(start: at(11, 0)))
        XCTAssertEqual(h.totalSeconds(.bypass, at: at(11, 12)), (112 + 12) * 60, "an open run counts up to the time given")
        XCTAssertEqual(h.totalSeconds(.bypass, at: at(11, 30)), (112 + 30) * 60)
        XCTAssertEqual(course().totalSeconds(.bypass, at: at(12, 0)), 0)
    }

    func testChangingAStartTimeChangesTheTotal() {
        var h = twoRuns()
        let id = h.bypassRuns[0].id
        XCTAssertNil(h.changeRun(.bypass, id: id, start: at(8, 30), end: at(10, 12), now: at(12, 0)))
        XCTAssertEqual(h.totalSeconds(.bypass, at: at(12, 0)), 122 * 60, "ten minutes longer")
        XCTAssertEqual(h.bypassRuns[0].start, at(8, 30))
    }

    func testAnEditedRunMovesToItsPlaceInTheList() {
        var h = twoRuns()
        let first = h.bypassRuns[0].id
        // Move the first run after the second (to 11:00-11:20): the list stays in start order.
        XCTAssertNil(h.changeRun(.bypass, id: first, start: at(11, 0), end: at(11, 20), now: at(12, 0)))
        XCTAssertEqual(h.bypassRuns.last?.id, first)
        XCTAssertEqual(h.bypassRuns.map(\.start), [at(10, 35), at(11, 0)])
    }

    // MARK: The refusals

    func testAnEndBeforeItsStartIsRefusedAndNothingChanges() {
        var h = twoRuns()
        let before = h
        let reason = h.changeRun(.bypass, id: h.bypassRuns[0].id, start: at(9, 0), end: at(8, 59), now: at(12, 0))
        XCTAssertEqual(reason, BypassRunText.endBeforeStart)
        XCTAssertEqual(h, before)
        XCTAssertNil(h.changeRun(.bypass, id: h.bypassRuns[0].id, start: at(9, 0), end: at(9, 0), now: at(12, 0)), "an end equal to the start is not before it")
    }

    func testARunThatOverlapsAnotherRunIsRefused() {
        var h = twoRuns()
        let before = h
        // The second run starting inside the first (10:00), and the first ending inside the second (10:40).
        XCTAssertEqual(h.changeRun(.bypass, id: h.bypassRuns[1].id, start: at(10, 0), end: at(10, 55), now: at(12, 0)), BypassRunText.overlap)
        XCTAssertEqual(h.changeRun(.bypass, id: h.bypassRuns[0].id, start: at(8, 40), end: at(10, 40), now: at(12, 0)), BypassRunText.overlap)
        // One run swallowing the other.
        XCTAssertEqual(h.changeRun(.bypass, id: h.bypassRuns[0].id, start: at(8, 0), end: at(11, 30), now: at(12, 0)), BypassRunText.overlap)
        XCTAssertEqual(h, before)
        // Touching is not overlapping: the first ending at the moment the second starts.
        XCTAssertNil(h.changeRun(.bypass, id: h.bypassRuns[0].id, start: at(8, 40), end: at(10, 35), now: at(12, 0)))
        // An open run overlaps whatever starts after it.
        var open = course()
        open.bypassRuns = [BypassRun(start: at(8, 40))]
        let other = BypassRun(start: at(9, 0), end: at(9, 30))
        open.bypassRuns.append(other)
        XCTAssertEqual(open.runIssue(.bypass, id: other.id, start: at(9, 0), end: at(9, 30), now: at(12, 0)), BypassRunText.overlap)
    }

    func testATimeInTheFutureIsRefusedWithAMinuteOfSlack() {
        var h = twoRuns()
        let before = h
        let now = at(12, 0)
        XCTAssertEqual(h.changeRun(.bypass, id: h.bypassRuns[1].id, start: at(10, 35), end: at(12, 5), now: now), HeparinTimeline.futureText)
        XCTAssertEqual(h.changeRun(.bypass, id: h.bypassRuns[1].id, start: at(12, 5), end: nil, now: now), HeparinTimeline.futureText)
        XCTAssertEqual(h, before)
        XCTAssertNil(h.changeRun(.bypass, id: h.bypassRuns[1].id, start: at(10, 35), end: at(12, 0, 59), now: now), "59 seconds ahead is clock slack")
        XCTAssertEqual(h.changeRun(.bypass, id: h.bypassRuns[1].id, start: at(10, 35), end: at(12, 1, 1), now: now), HeparinTimeline.futureText)
    }

    func testARunNotInTheListChangesNothing() {
        var h = twoRuns()
        let before = h
        XCTAssertNil(h.changeRun(.bypass, id: UUID(), start: at(7, 0), end: at(7, 30), now: at(12, 0)))
        XCTAssertEqual(h, before)
    }

    // MARK: Deleting

    func testDeletingARunKeepsTheOthersAndTheTotal() {
        var h = twoRuns()
        h.deleteRun(.bypass, id: h.bypassRuns[0].id)
        XCTAssertEqual(h.bypassRuns.count, 1)
        XCTAssertEqual(h.totalSeconds(.bypass, at: at(12, 0)), 20 * 60)
        h.deleteRun(.bypass, id: h.bypassRuns[0].id)
        XCTAssertTrue(h.bypassRuns.isEmpty)
        XCTAssertFalse(h.onBypass)
        // The open run deleted: no longer on bypass.
        var open = course()
        open.startRun(.bypass, at: at(8, 40))
        open.deleteRun(.bypass, id: open.bypassRuns[0].id)
        XCTAssertFalse(open.onBypass)
    }

    // MARK: onBypass and isRecordOnly

    func testOnBypassIsTheLatestRunHavingNoEnd() {
        var h = course()
        XCTAssertFalse(h.onBypass)
        h.bypassRuns = [BypassRun(start: at(8, 40), end: at(9, 0))]
        XCTAssertFalse(h.onBypass)
        h.bypassRuns.append(BypassRun(start: at(9, 30)))
        XCTAssertTrue(h.onBypass)
        // A cross-clamp running is not bypass.
        var clampOnly = course()
        clampOnly.startRun(.clamp, at: at(9, 0))
        XCTAssertFalse(clampOnly.onBypass)
        XCTAssertTrue(clampOnly.isRunning(.clamp))
    }

    func testIsRecordOnlyKeepsItsMeaning() {
        var h = course()
        h.doses = [TimedEntry(time: at(8, 0), value: 26000)]
        h.actOff = true
        XCTAssertTrue(h.isRecordOnly, "doses only")
        var withBypass = h
        withBypass.startRun(.bypass, at: at(8, 40))
        XCTAssertFalse(withBypass.isRecordOnly, "a bypass run is more than doses")
        var withClamp = h
        withClamp.startRun(.clamp, at: at(8, 55))
        XCTAssertFalse(withClamp.isRecordOnly, "so is a cross-clamp run")
        // A case saved with only bypassOn, before runs, reads the same.
        XCTAssertFalse((try? decode(#"{"purpose":"bypass","bypassOn":1000,"doses":[{"id":"00000000-0000-0000-0000-000000000001","time":500,"value":26000}],"actOff":true}"#))?.isRecordOnly ?? true)
    }

    func testTheBypassCheckInProtamineStillReadsOnBypass() throws {
        // The protamine check asks h.onBypass: a run open is "bypass still running", every run ended is not.
        var h = course()
        h.startRun(.bypass, at: at(8, 40))
        XCTAssertTrue(h.onBypass)
        h.endRun(.bypass, at: at(10, 0))
        XCTAssertFalse(h.onBypass)
    }

    // MARK: The cross-clamp

    func testTheCrossClampIsItsOwnListWithTheSameRules() {
        var h = course()
        XCTAssertTrue(h.startRun(.clamp, at: at(8, 55)))
        XCTAssertTrue(h.isRunning(.clamp))
        XCTAssertTrue(h.endRun(.clamp, at: at(10, 3)))
        XCTAssertEqual(h.totalSeconds(.clamp, at: at(12, 0)), 68 * 60)
        XCTAssertTrue(h.startRun(.clamp, at: at(10, 30)))
        XCTAssertEqual(h.clampRuns.count, 2)
        XCTAssertTrue(h.bypassRuns.isEmpty, "the lists are separate")
        // Refusals as for bypass.
        let id = h.clampRuns[1].id
        XCTAssertEqual(h.changeRun(.clamp, id: id, start: at(10, 0), end: nil, now: at(12, 0)), BypassRunText.overlap)
        XCTAssertEqual(h.changeRun(.clamp, id: h.clampRuns[0].id, start: at(9, 0), end: at(8, 0), now: at(12, 0)), BypassRunText.endBeforeStart)
        XCTAssertEqual(h.changeRun(.clamp, id: id, start: at(12, 30), end: nil, now: at(12, 0)), HeparinTimeline.futureText)
        h.deleteRun(.clamp, id: id)
        XCTAssertEqual(h.clampRuns.count, 1)
    }

    func testAClampNeedNotSitInsideABypassRunAndNothingElseIsChecked() {
        var h = twoRuns()
        // Clamp 07:00-11:30 covers both bypass runs and a gap: nothing validates it against them.
        h.clampRuns = [BypassRun(start: at(7, 0), end: at(11, 30))]
        XCTAssertNil(h.runIssue(.clamp, id: h.clampRuns[0].id, start: at(7, 0), end: at(11, 30), now: at(12, 0)))
        XCTAssertNil(h.changeRun(.clamp, id: h.clampRuns[0].id, start: at(9, 0), end: at(11, 0), now: at(12, 0)))
    }

    func testTheClampRunsAreWrittenOnlyUnderTheirOwnKey() throws {
        var h = course()
        h.clampRuns = [BypassRun(start: at(8, 55), end: at(10, 3))]
        let k = try keys(h)
        XCTAssertNotNil(k["clampRuns"])
        XCTAssertNil(k["bypassOn"], "a clamp is not written as the legacy bypass times")
    }

    // MARK: The words

    func testDurationText() {
        XCTAssertEqual(BypassRunText.duration(52 * 60), "52 min")
        XCTAssertEqual(BypassRunText.duration(68 * 60), "1 h 08 min")
        XCTAssertEqual(BypassRunText.duration(120 * 60), "2 h 00 min")
        XCTAssertEqual(BypassRunText.duration(112 * 60), "1 h 52 min")
        XCTAssertEqual(BypassRunText.duration(0), "0 min")
        XCTAssertEqual(BypassRunText.duration(29), "0 min", "rounded to the nearest minute")
        XCTAssertEqual(BypassRunText.duration(30), "1 min")
        XCTAssertEqual(BypassRunText.duration(52 * 60 + 29), "52 min")
        XCTAssertEqual(BypassRunText.duration(52 * 60 + 31), "53 min")
        XCTAssertEqual(BypassRunText.duration(59 * 60 + 40), "1 h 00 min", "rounds across the hour")
        XCTAssertEqual(BypassRunText.duration(-5), "0 min")
    }

    func testTheRunLines() {
        let now = at(11, 0)
        let time: (Date) -> String = { PatientSummary.time($0, now: now) }
        XCTAssertEqual(BypassRunText.runLine(1, BypassRun(start: at(8, 40), end: at(10, 12)), now: now, time: time), "Run 1 · 08:40–10:12 · 1 h 32 min")
        XCTAssertEqual(BypassRunText.runLine(2, BypassRun(start: at(10, 35)), now: at(10, 47), time: time), "Run 2 · 10:35– · 12 min")
        XCTAssertEqual(BypassRunText.runLine(2, BypassRun(start: at(10, 35)), now: at(10, 59), time: time), "Run 2 · 10:35– · 24 min", "it counts with the clock")
    }

    func testTheButtonsAndRowWords() {
        XCTAssertEqual(BypassRunKind.bypass.onTitle, "Bypass on")
        XCTAssertEqual(BypassRunKind.bypass.offTitle, "Bypass off")
        XCTAssertEqual(BypassRunKind.bypass.openText(since: "08:40"), "On bypass since 08:40")
        XCTAssertEqual(BypassRunKind.bypass.totalText("1 h 32 min"), "Bypass 1 h 32 min")
        XCTAssertEqual(BypassRunKind.clamp.onTitle, "Cross-clamp on")
        XCTAssertEqual(BypassRunKind.clamp.offTitle, "Cross-clamp off")
        XCTAssertEqual(BypassRunKind.clamp.openText(since: "08:55"), "Cross-clamp on since 08:55")
        XCTAssertEqual(BypassRunKind.clamp.totalText("1 h 08 min"), "Cross-clamp 1 h 08 min")
    }

    // MARK: The handoff

    private func record(_ h: HeparinCourse?) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male
        r.setProcedures(PlannedProcedure.parse("CABG x3"))
        r.echo = "No new wall motion abnormality"
        r.timers.heparin = h
        return r
    }

    func testTheHandoffLinesForARunThatEndedAndForTwo() throws {
        let now = at(12, 0)
        var h = course()
        h.bypassRuns = [BypassRun(start: at(8, 40), end: at(10, 12))]
        h.clampRuns = [BypassRun(start: at(8, 55), end: at(10, 3))]
        var blocks = PatientBriefs.handoff(record(h), now: now)
        XCTAssertEqual(try block(blocks, "bypass").label, "Bypass time")
        XCTAssertEqual(try block(blocks, "bypass").text, "1 h 32 min")
        XCTAssertEqual(try block(blocks, "clamp").label, "Cross-clamp time")
        XCTAssertEqual(try block(blocks, "clamp").text, "1 h 08 min")
        // Two bypass runs: the sum and the count.
        h = twoRuns()
        h.bypassRuns[1].end = at(10, 55)
        h.clampRuns = [BypassRun(start: at(8, 55), end: at(10, 3))]
        blocks = PatientBriefs.handoff(record(h), now: now)
        XCTAssertEqual(try block(blocks, "bypass").text, "1 h 52 min (2 runs)")
        let plain = PatientBriefs.plainText(blocks)
        XCTAssertTrue(plain.contains("Bypass time: 1 h 52 min (2 runs)"), plain)
        XCTAssertTrue(plain.contains("Cross-clamp time: 1 h 08 min"), plain)
        XCTAssertFalse(plain.contains("1 run)"), "(N runs) only when there is more than one")
    }

    func testTheHandoffLinesForARunStillOpen() throws {
        var h = course()
        h.bypassRuns = [BypassRun(start: at(8, 40))]
        h.clampRuns = [BypassRun(start: at(8, 55))]
        var blocks = PatientBriefs.handoff(record(h), now: at(9, 32))
        XCTAssertEqual(try block(blocks, "bypass").text, "52 min so far, on bypass since 08:40")
        XCTAssertEqual(try block(blocks, "clamp").text, "37 min so far, still on since 08:55")
        // The time so far moves with the clock.
        blocks = PatientBriefs.handoff(record(h), now: at(10, 3))
        XCTAssertEqual(try block(blocks, "clamp").text, "1 h 08 min so far, still on since 08:55")
        // An earlier run ended and a new one open: the total so far, the count, and when this one started.
        var again = twoRuns()
        again.bypassRuns[1].end = nil
        blocks = PatientBriefs.handoff(record(again), now: at(10, 55))
        XCTAssertEqual(try block(blocks, "bypass").text, "1 h 52 min so far (2 runs), on bypass since 10:35")
    }

    func testTheHandoffHasNoLineWithoutARun() {
        XCTAssertFalse(PatientBriefs.handoff(record(nil), now: at(12, 0)).contains { $0.key == "bypass" || $0.key == "clamp" })
        var h = course()
        h.doses = [TimedEntry(time: at(8, 0), value: 26000)]
        let blocks = PatientBriefs.handoff(record(h), now: at(12, 0))
        XCTAssertFalse(blocks.contains { $0.key == "bypass" || $0.key == "clamp" }, "heparin alone adds nothing")
        // Only a clamp: its line alone.
        h.clampRuns = [BypassRun(start: at(8, 55), end: at(10, 3))]
        let keys = PatientBriefs.handoff(record(h), now: at(12, 0)).map(\.key)
        XCTAssertFalse(keys.contains("bypass"))
        XCTAssertTrue(keys.contains("clamp"))
    }

    func testTheLinesComeRightAfterTheTEEBlockAndBeforeTheLabs() throws {
        let slots = PatientBriefs.slots(.handoff, record(twoRuns())).map(\.key)
        let tee = try XCTUnwrap(slots.firstIndex(of: "tee"))
        XCTAssertEqual(slots.firstIndex(of: "bypass"), tee + 1)
        XCTAssertEqual(slots.firstIndex(of: "clamp"), tee + 2)
        XCTAssertEqual(slots.firstIndex(of: "labs"), tee + 3)
        // And in the blocks that show, with the TEE block there.
        var h = twoRuns()
        h.clampRuns = [BypassRun(start: at(8, 55), end: at(10, 3))]
        let shown = PatientBriefs.handoff(record(h), now: at(12, 0)).map(\.key)
        let i = try XCTUnwrap(shown.firstIndex(of: "tee"))
        XCTAssertEqual(Array(shown[(i + 1)...].prefix(2)), ["bypass", "clamp"])
    }

    func testThePreprocedureSummaryIsUnchanged() {
        var h = twoRuns()
        h.clampRuns = [BypassRun(start: at(8, 55), end: at(10, 3))]
        let now = at(12, 0)
        XCTAssertFalse(PatientBriefs.slots(.preop, record(h), now: now).contains { $0.key == "bypass" || $0.key == "clamp" })
        XCTAssertEqual(PatientBriefs.preop(record(h), now: now).map(\.key), PatientBriefs.preop(record(nil), now: now).map(\.key))
        XCTAssertEqual(PatientBriefs.plainText(PatientBriefs.preop(record(h), now: now)),
                       PatientBriefs.plainText(PatientBriefs.preop(record(nil), now: now)))
    }

    func testNothingAboutHeparinActsOrProtamineIsAddedToTheHandoff() {
        var h = twoRuns()
        h.doses = [TimedEntry(time: at(8, 0), value: 26000)]
        h.acts = [TimedEntry(time: at(8, 10), value: 512)]
        h.protamine = [TimedEntry(time: at(11, 0), value: 200)]
        let text = PatientBriefs.plainText(PatientBriefs.handoff(record(h), now: at(12, 0)))
        XCTAssertFalse(text.lowercased().contains("heparin"))
        XCTAssertFalse(text.lowercased().contains("protamine"))
        XCTAssertFalse(text.contains("512"))
    }

    func testAnEditedLineStaysUntilRegenerated() throws {
        var r = record(twoRuns())
        let now = at(12, 0)
        PatientBriefs.setEdit(&r, .handoff, key: "bypass", text: "112 min on bypass", now: now)
        XCTAssertEqual(try block(PatientBriefs.handoff(r, now: now), "bypass").text, "112 min on bypass")
        PatientBriefs.regenerate(&r, .handoff)
        XCTAssertEqual(try block(PatientBriefs.handoff(r, now: now), "bypass").text, "1 h 52 min (2 runs)")
    }
}
