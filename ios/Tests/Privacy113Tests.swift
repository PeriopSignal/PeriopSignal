import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import PeriopSignal

/// 1.13, Ben, Nov 19 (after the GPT-6 review): the files made to share a patient are written protected and kept out of
/// backups, are removed with their folders, the pasteboard holds patient text for ten minutes on this phone only, and the
/// app-switcher cover is drawn only for a patient on screen. The cover itself and the share sheet's dismissal need a screen;
/// these tests cover the rules and the files.
final class Privacy113Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        PatientSendFiles.purge()
    }

    override func tearDown() {
        PatientSendFiles.purge()
        super.tearDown()
    }

    private func attributes(_ url: URL) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: url.path)
    }

    /// The simulator may not report a protection class at all; when it does, it must be the complete one.
    private func assertComplete(_ url: URL, _ what: String, file: StaticString = #filePath, line: UInt = #line) throws {
        if let protection = try attributes(url)[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(protection, .complete, what, file: file, line: line)
        }
    }

    // MARK: 1. The temporary files

    func testTheSendFileIsWrittenProtectedAndOutOfBackups() throws {
        let data = Data("patient".utf8)
        let url = try XCTUnwrap(PatientSendFiles.write(data, named: PatientPacket.fileName))
        XCTAssertEqual(url.lastPathComponent, "Patient handoff.periop", "the visible name is kept")
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent, "PatientSend")
        XCTAssertNotNil(UUID(uuidString: url.deletingLastPathComponent().lastPathComponent), "a folder of its own")
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true, "file not backed up")
        XCTAssertEqual(try url.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true, "folder not backed up")
        try assertComplete(url, "file")
        try assertComplete(url.deletingLastPathComponent(), "its folder")
        try assertComplete(PatientSendFiles.folder, "the send folder")
    }

    func testThePatientShareItemWritesThroughTheProtectedWriter() throws {
        let item = try XCTUnwrap(PatientShareItem(packet: PatientPacket(record: PatientDemo112Summary.summary)))
        XCTAssertEqual(item.fileURL.lastPathComponent, "Patient handoff.periop")
        XCTAssertEqual(try item.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        try assertComplete(item.fileURL, "file")
        try assertComplete(item.fileURL.deletingLastPathComponent(), "its folder")
    }

    @MainActor func testTheSummaryPDFLivesInASendFolderWithItsVisibleName() throws {
        let record = PatientDemo112Summary.summary
        let ctx = BriefPages.Context(record: record, refs: ReferenceStore(), patient: PatientStore(url: nil))
        let blocks = PatientBriefs.handoff(record)
        let url = try XCTUnwrap(BriefPages.pdfFile(blocks, ctx))
        XCTAssertEqual(url.lastPathComponent, "Periop Signal summary.pdf")
        XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent().path, PatientSendFiles.folder.path,
                       "in a folder under tmp/PatientSend, not loose in tmp")
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        try assertComplete(url, "pdf")
        try assertComplete(url.deletingLastPathComponent(), "its folder")
    }

    @MainActor func testPurgeRemovesTheHandoffFolderAndThePDFFolder() throws {
        let item = try XCTUnwrap(PatientShareItem(packet: PatientPacket(record: PatientDemo112Summary.summary)))
        let record = PatientDemo112Summary.summary
        let ctx = BriefPages.Context(record: record, refs: ReferenceStore(), patient: PatientStore(url: nil))
        let pdf = try XCTUnwrap(BriefPages.pdfFile(PatientBriefs.handoff(record), ctx))
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: item.fileURL.path))
        XCTAssertTrue(fm.fileExists(atPath: pdf.path))
        // What the share sheet's completion runs: a fresh pair stays for the ten-minute clean-up, and goes with the other.
        PatientSendFiles.purge(olderThan: 600)
        XCTAssertTrue(fm.fileExists(atPath: item.fileURL.path))
        XCTAssertTrue(fm.fileExists(atPath: pdf.path))
        PatientSendFiles.purge()
        XCTAssertFalse(fm.fileExists(atPath: item.fileURL.path))
        XCTAssertFalse(fm.fileExists(atPath: item.fileURL.deletingLastPathComponent().path), "the .periop folder goes")
        XCTAssertFalse(fm.fileExists(atPath: pdf.path))
        XCTAssertFalse(fm.fileExists(atPath: pdf.deletingLastPathComponent().path), "the PDF folder goes")
    }

    @MainActor func testTheShareSheetPurgesOnCompletionOnlyForAPatientShare() {
        let patient = ShareSheet.controller(items: [], purgesPatientFiles: true)
        XCTAssertNotNil(patient.completionWithItemsHandler)
        let other = ShareSheet.controller(items: [], purgesPatientFiles: false)
        XCTAssertNil(other.completionWithItemsHandler, "a post's share sheet touches no patient files")
    }

    // MARK: 2. The pasteboard

    func testPatientTextIsCopiedLocalOnlyWithATenMinuteExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_793_354_400)
        let options = HandoffShare.patientPasteboardOptions(now: now)
        XCTAssertEqual(options[.localOnly] as? Bool, true)
        let expires = try XCTUnwrap(options[.expirationDate] as? Date)
        XCTAssertEqual(expires.timeIntervalSince(now), 600, accuracy: 0.001)
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(HandoffShare.pasteboardLifetime, 600)
    }

    // MARK: 3. The app-switcher cover

    func testTheCoverIsDrawnOnlyWhenNotActiveAndAPatientIsOnScreen() {
        for phase in [ScenePhase.inactive, .background] {
            XCTAssertTrue(PrivacyCover.covers(phase: phase, tab: .patient, patientScreenOpen: false), "My Patient tab, \(phase)")
            XCTAssertTrue(PrivacyCover.covers(phase: phase, tab: .reference, patientScreenOpen: true), "a patient screen open, \(phase)")
            XCTAssertFalse(PrivacyCover.covers(phase: phase, tab: .feed, patientScreenOpen: false), "Feed, \(phase)")
            XCTAssertFalse(PrivacyCover.covers(phase: phase, tab: .more, patientScreenOpen: false), "More, \(phase)")
        }
        // Never while the app is active, so a screenshot or a share sheet never meets it.
        for tab in [Router.Tab.feed, .patient, .reference, .more] {
            XCTAssertFalse(PrivacyCover.covers(phase: .active, tab: tab, patientScreenOpen: true), "\(tab)")
        }
    }

    func testTheCoverTakesTheAppsAppearance() {
        XCTAssertEqual(PrivacyCover.style(for: .dark), .dark)
        XCTAssertEqual(PrivacyCover.style(for: .light), .light)
        XCTAssertEqual(PrivacyCover.style(for: .system), .unspecified)
    }

    @MainActor func testHidingACoverThatIsNotShownIsHarmless() {
        let cover = PrivacyCoverWindow.shared
        cover.hide()
        XCTAssertFalse(cover.isShown)
        cover.hide()
        XCTAssertFalse(cover.isShown, "hiding twice is harmless")
    }
}
