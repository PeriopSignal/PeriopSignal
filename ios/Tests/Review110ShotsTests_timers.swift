import XCTest
import SwiftUI
import UIKit
@testable import PeriopSignal

/// 1.10 screenshot review, Case Timers group: the TEE practice ACT answer matches the 480 s bypass default; the Heparin
/// & ACT ⓘ captions name i-STAT once; the protamine card calls only 1 mg per 100 U a cap and quotes EACTS 2024 as
/// "below 1.0"; a chosen Other interval keeps the chip short (one line at 375 pt); the idle Start timer is legible.
final class Review110ShotsTimersTests: XCTestCase {
    private func bundle() throws -> ReferenceBundle {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        return try ReferenceLoader.decode(try Data(contentsOf: url))
    }

    // MARK: TEE practice (481)

    func testTeePracticeACTAnswerMatchesTheBypassDefault() throws {
        let b = try bundle()
        let goal = try XCTUnwrap(b.caseTimers?.purpose("bypass")?.goal, "bypass has a preset goal")
        XCTAssertEqual(goal, 480)
        let practice = try XCTUnwrap(b.tee?.practice)
        let item = try XCTUnwrap(practice.first { $0.q.contains("ACT on bypass") })
        XCTAssertFalse(item.a.contains("450"), "the 1.9 default is retired: \(item.a)")
        XCTAssertTrue(item.a.contains("default"), item.a)
        XCTAssertEqual(item.a.components(separatedBy: "480 s").count - 1, 2, "STS's 480 s and the app's 480 s default: \(item.a)")
    }

    // MARK: Heparin & ACT ⓘ (511)

    func testHeparinCaptionsNameIStatOnce() throws {
        let d = try XCTUnwrap(try bundle().caseTimers)
        let device = d.heparinRules.actDevice ?? "i-STAT"
        // What the two ⓘ show with -ps.evidence.open: the section header's (CaseTimersView.heparinSection) and the
        // ACT goal's (Ben's answer 4).
        let header = d.heparinRules.clottingTest + " " + d.heparinRules.deviceNote
        let goalInfo = CaseTimerEngine.actGoalInfo(device: device)
        XCTAssertEqual(goalInfo, "ACT goals assume i-STAT values.")
        let both = header + " " + goalInfo
        XCTAssertEqual(both.components(separatedBy: "i-STAT").count - 1, 1, both)
        XCTAssertTrue(d.heparinRules.deviceNote.contains("557 vs 618 s"), "the device-variability fact stays")
    }

    // MARK: Protamine (512, 513, 515)

    func testProtamineCardCallsOnlyTheOneMgCapACap() throws {
        let pr = try XCTUnwrap(try bundle().caseTimers?.protamine)
        // Ben's numbers stay: 0.8–1 mg per 100 U of the initial dose, capped at 1; STS 2.6 still blocks.
        XCTAssertEqual(pr.ratioLow, 0.8); XCTAssertEqual(pr.ratioHigh, 1.0); XCTAssertEqual(pr.blockAbove, 2.6)
        // The STS 2.6 figure is not called a cap next to "cap 260 mg".
        XCTAssertFalse(pr.ceilingNote.lowercased().contains("cap is a ceiling"), pr.ceilingNote)
        XCTAssertFalse(pr.ceilingNote.contains("2.6 cap"), pr.ceilingNote)
        XCTAssertTrue(pr.ceilingNote.contains("2.6 mg per 100 U"), pr.ceilingNote)
        // EACTS 2024 §9.3.2 quoted as written ("should be kept below 1.0"), with the 1:1 cap as a limit, not a target,
        // so the range ending at 1 mg per 100 U no longer reads as breaking the line under it.
        XCTAssertFalse(pr.ratioNote.contains("under 1:1"), pr.ratioNote)
        XCTAssertTrue(pr.ratioNote.contains("should be kept below 1.0"), pr.ratioNote)
        XCTAssertTrue(pr.ratioNote.contains("not the target"), pr.ratioNote)
    }

    // MARK: Other chip (506)

    func testOtherChipStaysShortOnceAValueIsChosen() {
        XCTAssertEqual(CaseTimerRecurrence.otherChipLabel(RecurrencePick()), "Other")
        XCTAssertEqual(CaseTimerRecurrence.otherChipLabel(RecurrencePick(minutes: 60)), "Other", "a chip pick leaves Other plain")
        XCTAssertEqual(CaseTimerRecurrence.otherChipLabel(RecurrencePick(minutes: 45, other: true)), "45 min")
        XCTAssertEqual(CaseTimerRecurrence.otherChipLabel(RecurrencePick(minutes: 120, other: true)), "2 h")
        XCTAssertEqual(CaseTimerRecurrence.otherChipLabel(RecurrencePick(minutes: 105, other: true)), "1h 45m")
        XCTAssertEqual(CaseTimerRecurrence.otherChipA11y(RecurrencePick(minutes: 105, other: true)), "Other interval, 1 h 45 min")
        // No longer than "30 min" + a digit, for every value the wheel offers ("Other · 45 min" wrapped the lab row).
        for v in CaseTimerRecurrence.otherValues(maxMinutes: CaseTimerRecurrence.antibioticMax) {
            let label = CaseTimerRecurrence.otherChipLabel(RecurrencePick(minutes: v, other: true))
            XCTAssertLessThanOrEqual(label.count, 7, label)
        }
    }

    // MARK: Idle Start timer (502, 503, 505, 507–509)

    private func rgb(_ c: Color, _ style: UIUserInterfaceStyle) -> [Double] {
        let ui = UIColor(c).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(ui.getRed(&r, green: &g, blue: &b, alpha: &a))
        return [Double(r), Double(g), Double(b)]
    }

    private func over(_ top: [Double], _ under: [Double], _ alpha: Double) -> [Double] {
        zip(top, under).map { $0 * alpha + $1 * (1 - alpha) }
    }

    private func luminance(_ c: [Double]) -> Double {
        let l = c.map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
    }

    private func contrast(_ a: [Double], _ b: [Double]) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testIdleStartTimerLabelIsLegibleInBothAppearances() {
        let idle = TimerStartButtonStyle.look(active: false)
        let active = TimerStartButtonStyle.look(active: true)
        for style in [UIUserInterfaceStyle.dark, .light] {
            let card = rgb(PS.surface, style)
            let fill = over(rgb(idle.fill, style), card, idle.opacity)
            let text = over(rgb(idle.text, style), card, idle.opacity)
            let ratio = contrast(text, fill)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "idle Start timer label in \(style == .dark ? "dark" : "light"): \(ratio):1")
            // Still reads as inactive: it does not wear the accent fill of a live Start timer.
            XCTAssertNotEqual(rgb(idle.fill, style), rgb(active.fill, style))
        }
    }
}
