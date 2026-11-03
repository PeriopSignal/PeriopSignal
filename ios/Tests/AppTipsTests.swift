import XCTest
@testable import PeriopSignal

/// 1.8.1 wave 2b: My Patient's tips generalized into app-wide tip sets (the first-open tour of the tabs, the Reference
/// home's first visit), one seen-key each, never on an emergency tool, and the Feed's alerts banner waiting for them.
final class AppTipsTests: XCTestCase {

    private func defaults() -> (UserDefaults, String) {
        let name = "AppTipsTests." + UUID().uuidString
        return (UserDefaults(suiteName: name)!, name)
    }

    // MARK: The sets

    func testTheTourPointsAtTheThreeTabs() {
        XCTAssertEqual(TipSet.tour.steps.map(\.target), [TipTarget.feedTab, TipTarget.patientTab, TipTarget.referenceTab])
        XCTAssertEqual(TipSet.tour.steps.map(\.text), [
            "New practice-changing papers land here every morning.",
            "Enter your patient once; the calculators and handoff fill in from it.",
            "Calculators, emergency checklists and echo grading live here.",
        ])
        XCTAssertEqual(TipTarget.tabs.map(\.title), ["Feed", "My Patient", "Reference", "More"], "the tab bar's order and titles")
    }

    func testTheReferenceHomeShowsTheFolderTipOnlyWithoutFavorites() {
        let none = TipSet.referenceHome(hasFavorites: false)
        XCTAssertEqual(none.steps.map(\.target), [TipTarget.referenceSearch, TipTarget.referenceFirstFolder])
        XCTAssertEqual(none.steps[0].text, "Search any drug, score or society, or ask a question if nothing matches.")
        XCTAssertEqual(none.steps[1].text, "Tap ☆ inside any tool to pin it to the top of this page.")
        let some = TipSet.referenceHome(hasFavorites: true)
        XCTAssertEqual(some.steps.map(\.target), [TipTarget.referenceSearch])
        XCTAssertEqual(some.seenKey, none.seenKey, "one seen-key for the set")
    }

    func testEachSetHasItsOwnSeenKey() {
        let keys = [TipSet.tour.seenKey, TipSet.referenceHome(hasFavorites: false).seenKey, TipSet.patient.seenKey]
        XCTAssertEqual(Set(keys).count, 3)
        XCTAssertEqual(TipSet.patient.seenKey, PatientTips.seenKey, "My Patient's key is unchanged")
        XCTAssertEqual(PatientTips.steps.count, 4, "My Patient's wrapper still has its four")
        for set in [TipSet.tour, .referenceHome(hasFavorites: false), .patient] {
            for s in set.steps { XCTAssertLessThan(s.text.count, 160, "short enough for a card: \(s.text)") }
        }
    }

    func testNeverOnAnEmergencyTool() {
        let emergency = RefFolder.emergency.items.map(\.route.key)
        XCTAssertEqual(Set(emergency), TipSet.emergencyRouteKeys, "ACLS, OB, LAST, MH and Difficult Airway")
        for key in emergency { XCTAssertFalse(TipSet.allowed(onRouteKey: key), key) }
        for item in RefItem.all where !emergency.contains(item.route.key) {
            XCTAssertTrue(TipSet.allowed(onRouteKey: item.route.key), item.route.key)
        }
    }

    // MARK: Launch hooks

    func testScreenshotRunsShowASetOnlyWhenAsked() {
        XCTAssertEqual(Tips.launch(for: "tour", args: [:]), .normal, "a person opening the app")
        XCTAssertEqual(Tips.launch(for: "tour", args: ["ps.tab": "reference"]), .screenshot, "any other shot stays uncovered")
        XCTAssertEqual(Tips.launch(for: "tour", args: ["ps.tips": "1", "ps.tips.set": "tour", "ps.tips.step": "2"]), .forced(step: 1))
        XCTAssertEqual(Tips.launch(for: "reference", args: ["ps.tips": "1", "ps.tips.set": "tour"]), .screenshot, "another set's shot")
        // Without -ps.tips.set, -ps.tips 1 is My Patient's, as before (shots 180–183).
        XCTAssertEqual(Tips.launch(for: "patient", args: ["ps.tips": "1", "ps.tips.step": "3"]), .forced(step: 2))
        XCTAssertEqual(Tips.launch(for: "tour", args: ["ps.tips": "1", "ps.tips.step": "3"]), .screenshot)
        XCTAssertEqual(Tips.launch(for: "reference", args: ["ps.tips": "1", "ps.tips.set": "reference"]), .forced(step: 0), "step 1 by default")
    }

    // MARK: One set's state

    func testATapStepsThroughToDoneAndASetOfOneSaysTip() {
        var t = Tips(.tour)
        t.appear(storedSeen: false)
        XCTAssertEqual(t.current?.target, TipTarget.feedTab)
        XCTAssertEqual(t.progress, "1 of 3")
        t.next(); t.next()
        XCTAssertTrue(t.isLast)
        t.next()
        XCTAssertFalse(t.isShowing)
        XCTAssertTrue(t.seen)

        var one = Tips(.referenceHome(hasFavorites: true))
        one.appear(storedSeen: false)
        XCTAssertTrue(one.isLast)
        XCTAssertEqual(one.progress, "", "no \"1 of 1\"")
        var forced = Tips(.referenceHome(hasFavorites: true))
        forced.appear(storedSeen: true, launch: .forced(step: 1))
        XCTAssertEqual(forced.step, 0, "clamped to the set's own steps")
    }

    // MARK: The center

    @MainActor func testTheCenterShowsOneSetAtATimeAndRemembersIt() {
        let (d, name) = defaults()
        defer { d.removePersistentDomain(forName: name) }
        let c = TipCenter(defaults: d, launch: { _ in .normal })
        XCTAssertTrue(c.tourPending)
        XCTAssertTrue(c.holdsBanner, "the alerts banner waits for the tour")
        XCTAssertTrue(c.offer(.tour))
        XCTAssertFalse(c.offer(.referenceHome(hasFavorites: false)), "never two sets at once")
        c.next(); c.next(); c.next()
        XCTAssertFalse(c.isShowing)
        XCTAssertTrue(c.tourSeen)
        XCTAssertTrue(d.bool(forKey: TipSet.tour.seenKey))
        XCTAssertFalse(c.holdsBanner, "then the banner may show")
        XCTAssertFalse(c.offer(.tour), "once per phone")

        XCTAssertTrue(c.offer(.referenceHome(hasFavorites: false)))
        XCTAssertTrue(c.holdsBanner, "and waits again while a tip shows")
        c.skip()
        XCTAssertTrue(d.bool(forKey: TipSet.referenceSeenKey), "Skip counts as seen")
        XCTAssertFalse(c.offer(.referenceHome(hasFavorites: true)))
        XCTAssertFalse(d.bool(forKey: TipSet.patient.seenKey), "each set has its own key")
    }

    @MainActor func testAnEmergencyScreenPutsTheTipsAwayUnseen() {
        let (d, name) = defaults()
        defer { d.removePersistentDomain(forName: name) }
        let c = TipCenter(defaults: d, launch: { _ in .normal })
        XCTAssertTrue(c.offer(.tour))
        c.next()
        c.block("reference:acls")
        XCTAssertFalse(c.isShowing, "never over ACLS")
        XCTAssertFalse(c.tourSeen, "put away, not seen")
        XCTAssertFalse(c.offer(.tour), "nothing starts while it is up")
        c.unblock("reference:acls")
        XCTAssertTrue(c.offer(.tour))
        XCTAssertEqual(c.showing?.step, 0, "from the top again")
    }

    @MainActor func testScreenshotRunsForceASetOncePerLaunchAndNeverHoldTheBanner() {
        let (d, name) = defaults()
        defer { d.removePersistentDomain(forName: name) }
        let shots = TipCenter(defaults: d, launch: { _ in .screenshot })
        XCTAssertFalse(shots.offer(.tour))
        XCTAssertFalse(shots.tourPending, "screenshot runs show the banner as before (shots 07, 14)")
        XCTAssertFalse(shots.holdsBanner)

        let forced = TipCenter(defaults: d, launch: { $0.id == "tour" ? .forced(step: 2) : .screenshot })
        XCTAssertTrue(forced.offer(.tour))
        XCTAssertEqual(forced.showing?.current?.target, TipTarget.referenceTab)
        forced.skip()
        XCTAssertFalse(forced.offer(.tour), "once per launch")
        XCTAssertFalse(forced.offer(.referenceHome(hasFavorites: false)))
    }

    // MARK: The Feed's alerts banner

    @MainActor func testTheAlertsBannerWaits() {
        XCTAssertTrue(NotifyBanner.shows(dismissed: false, launchCount: 2, tipsHold: false, alertsOn: false, denied: false))
        XCTAssertFalse(NotifyBanner.shows(dismissed: false, launchCount: 1, tipsHold: false, alertsOn: false, denied: false), "not in the first session")
        XCTAssertFalse(NotifyBanner.shows(dismissed: false, launchCount: 5, tipsHold: true, alertsOn: false, denied: false), "not with tips")
        XCTAssertFalse(NotifyBanner.shows(dismissed: true, launchCount: 5, tipsHold: false, alertsOn: false, denied: false), "× is for good")
        XCTAssertFalse(NotifyBanner.shows(dismissed: false, launchCount: 5, tipsHold: false, alertsOn: true, denied: false))
        XCTAssertFalse(NotifyBanner.shows(dismissed: false, launchCount: 5, tipsHold: false, alertsOn: false, denied: true))
    }
}
