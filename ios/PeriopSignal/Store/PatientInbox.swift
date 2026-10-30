import CoreTransferable
import Foundation
import Observation
import UniformTypeIdentifiers

extension UTType {
    /// A patient sent from Periop Signal (exported in Info.plist, extension .periop).
    static let periopPatient = UTType(exportedAs: PatientPacket.identifier)
}

/// The patient to send, as a Periop Signal file for the share sheet (AirDrop or Messages).
struct PatientTransfer: Transferable {
    var record: PatientRecord

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .periopPatient) { item in
            try PatientPacket(record: item.record).encoded()
        }
        .suggestedFileName(PatientPacket.fileName)
    }
}

/// Patients received from colleagues. iOS copies a received file into the app's Documents/Inbox and opens the app
/// with it; the file is read into memory and deleted at once, and the patient waits here until the user opens or
/// discards it. Nothing is kept unless the user opens it.
@MainActor
@Observable
final class PatientInbox {
    /// A received patient waiting for the user's answer.
    var pending: PatientPacket?
    /// Why the last file could not be opened, for an alert.
    var problem: String?

    /// True when the URL is a patient file this inbox should take.
    nonisolated static func handles(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.lowercased() == PatientPacket.fileExtension
    }

    func receive(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            PatientInbox.deleteIfOurs(url)
        }
        do {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= PatientPacket.maxBytes else { throw PatientPacket.Problem.tooLarge }
            let data = try Data(contentsOf: url)
            pending = try PatientPacket.decode(data)
            problem = nil
        } catch let p as PatientPacket.Problem {
            problem = p.message
        } catch {
            problem = PatientPacket.Problem.unreadable.message
        }
    }

    /// Removes a received file when it sits in this app's own container (never a file opened in place elsewhere).
    nonisolated static func deleteIfOurs(_ url: URL) {
        let fm = FileManager.default
        guard let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        // Compare real paths: /var is a link to /private/var.
        let base = docs.deletingLastPathComponent().resolvingSymlinksInPath().path
        if url.resolvingSymlinksInPath().path.hasPrefix(base) { try? fm.removeItem(at: url) }
    }

    /// Deletes any patient files left where iOS puts received files (Documents/Inbox, or an Inbox folder in tmp): a
    /// launch after a file arrived but before it was read.
    nonisolated static func purgeLeftovers() {
        let fm = FileManager.default
        var folders: [URL] = []
        if let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            folders.append(docs.appendingPathComponent("Inbox", isDirectory: true))
        }
        if let tmp = try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil) {
            folders += tmp.filter { $0.lastPathComponent.hasSuffix("Inbox") }
        }
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for item in items where item.pathExtension.lowercased() == PatientPacket.fileExtension { try? fm.removeItem(at: item) }
        }
    }
}
