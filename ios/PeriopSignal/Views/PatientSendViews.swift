import LinkPresentation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Send Patient: one share sheet, with the AirDrop link on by default (1.12)

/// What the share sheet is given for Send Patient, whichever way the "AirDrop opens Periop Signal directly" switch is set.
/// The FILE (Patient handoff.periop, a file URL of the exported type org.periopsignal.patient: the long-standing way to
/// AirDrop a document) goes to every activity. With the switch on, the AirDrop activity is given the patient LINK
/// (periopsignal://receive?..., PatientLink) instead, so the receiving phone opens the app without the Files step. When the
/// link would be longer than PatientLink.maxLinkLength, or with the switch off, AirDrop is given the file too.
final class PatientShareItem: NSObject, UIActivityItemSource {
    let packet: PatientPacket
    /// The link AirDrop is given, or nil when the switch is off or the link would be too long (AirDrop then sends the file).
    let link: URL?
    /// The file, written to this phone's tmp folder when the sheet is prepared and removed at the next launch.
    let fileURL: URL

    /// Nil when the file cannot be written. `airDropLink` is the switch in More (on unless the user turned it off).
    init?(packet: PatientPacket, airDropLink: Bool = true) {
        self.packet = packet
        link = airDropLink ? PatientLink.url(for: packet) : nil
        guard let data = try? packet.encoded() else { return nil }
        PatientSendFiles.purge(olderThan: 600)
        let folder = PatientSendFiles.folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent(PatientPacket.fileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic])
        } catch {
            return nil
        }
        fileURL = file
        super.init()
    }

    /// True for the AirDrop activity.
    static func isAirDrop(_ type: UIActivity.ActivityType?) -> Bool {
        guard let type else { return false }
        return type == .airDrop
    }

    /// AirDrop gets the link when there is one.
    func usesLink(_ type: UIActivity.ActivityType?) -> Bool {
        link != nil && PatientShareItem.isAirDrop(type)
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { fileURL }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        if usesLink(activityType), let link { return link }
        return fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        usesLink(activityType) ? UTType.url.identifier : PatientPacket.identifier
    }

    /// The sheet's header: a plain title and icon, not the (long) link.
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let m = LPLinkMetadata()
        m.title = "Patient for handoff"
        m.originalURL = fileURL
        m.url = fileURL
        if let image = UIImage(systemName: "person.text.rectangle") { m.iconProvider = NSItemProvider(object: image) }
        return m
    }
}

/// The Send Patient button: always the same share sheet (UIActivityViewController, the app's ShareSheet) with a
/// PatientShareItem; the switch in More only decides what AirDrop is given (the link, or the file). The case's name goes
/// with the patient either way.
struct PatientSendButton: View {
    @Environment(Preferences.self) private var prefs
    var record: PatientRecord
    /// The current case's name, nil when it has none.
    var room: String?
    @State private var sharing: [Any]?
    @State private var failed = false

    /// The items the sheet is opened with, nil when the file cannot be written.
    static func items(record: PatientRecord, room: String?, airDropLink: Bool) -> [Any]? {
        guard let item = PatientShareItem(packet: PatientPacket(record: record, room: room), airDropLink: airDropLink) else { return nil }
        return [item]
    }

    var body: some View {
        Button {
            if let items = Self.items(record: record, room: room, airDropLink: prefs.airDropLink) {
                sharing = items
            } else {
                failed = true
            }
        } label: {
            Label("Send Patient", systemImage: "iphone.and.arrow.forward").frame(maxWidth: .infinity)
        }
        .buttonStyle(BigButtonStyle(prominent: false))
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            ShareSheet(items: sharing ?? []).presentationDetents([.medium, .large])
        }
        .alert("Couldn't prepare the patient", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again.")
        }
    }
}
