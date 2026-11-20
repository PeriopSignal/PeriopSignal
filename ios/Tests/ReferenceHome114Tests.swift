import XCTest
@testable import PeriopSignal

/// The Reference home after the Nov 19 outside review (Ben delegated the decisions, Nov 20): Emergency is always the first row, above
/// the favorites, and its summary names every tool in the folder instead of cutting off at two lines.
final class ReferenceHome114Tests: XCTestCase {

    // MARK: Order

    func testEmergencyIsFirstWhateverIsStarred() {
        XCTAssertEqual(RefHomeSection.order(hasFavorites: false), [.emergency, .folders], "no favorites: Emergency, then the other folders")
        XCTAssertEqual(RefHomeSection.order(hasFavorites: true), [.emergency, .favorites, .folders], "Emergency, then favorites, then the other folders")
        for hasFavorites in [false, true] {
            XCTAssertEqual(RefHomeSection.order(hasFavorites: hasFavorites).first, .emergency, "hasFavorites \(hasFavorites)")
        }
    }

    func testTheOtherFoldersKeepTheirOrderAndLeaveOutEmergency() {
        XCTAssertEqual(RefHomeSection.otherFolders, [.preoperative, .regional, .cardiothoracic, .medications, .pediatrics])
        XCTAssertFalse(RefHomeSection.otherFolders.contains(.emergency))
        // Every folder is on the home exactly once: Emergency's own row plus the others.
        XCTAssertEqual(Set([RefFolder.emergency] + RefHomeSection.otherFolders), Set(RefFolder.allCases))
        XCTAssertEqual(1 + RefHomeSection.otherFolders.count, RefFolder.allCases.count)
    }

    // MARK: Emergency summary

    func testEmergencySummaryNamesEveryToolAndHasNoEllipsis() {
        let summary = RefFolder.emergency.summary
        XCTAssertFalse(RefFolder.emergency.items.isEmpty)
        for item in RefFolder.emergency.items { XCTAssertTrue(summary.contains(item.title), "\(item.title) is in the Emergency summary") }
        XCTAssertEqual(summary, RefFolder.emergency.items.map(\.title).joined(separator: " · "))
        XCTAssertFalse(summary.contains("…"))
        XCTAssertFalse(summary.contains("..."))
        // The five tools that are always listed (Massive Transfusion joins them while its draft gate is open).
        for name in ["ACLS", "OB Emergencies", "Local Anesthetic Toxicity", "Malignant Hyperthermia", "Difficult Airway"] {
            XCTAssertTrue(summary.contains(name), name)
        }
    }

    func testOnlyEmergencyLetsItsSummaryWrap() {
        XCTAssertNil(RefFolder.emergency.summaryLineLimit, "as many lines as the names need")
        for folder in RefFolder.allCases where folder != .emergency {
            XCTAssertEqual(folder.summaryLineLimit, 2, "\(folder.title) keeps its two-line limit")
        }
    }

    func testEmergencyRowStillOpensItsFolderAndIsNotAFavoriteTarget() {
        XCTAssertEqual(RefFolder.emergency.route, .folder(.emergency), "the Emergency folder's own screen is unchanged")
        XCTAssertGreaterThan(RefFolder.emergency.items.count, 1)
        XCTAssertNil(RefItem.item(forKey: RefRoute.folder(.emergency).key), "a folder is never listed among the favorites tiles")
    }
}
