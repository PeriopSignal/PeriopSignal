import LinkPresentation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Send Patient with the AirDrop link (1.12, opt-in)

/// What the share sheet is given when the "AirDrop opens Periop Signal directly" switch is on: the patient LINK
/// (periopsignal://receive?..., PatientLink) for the AirDrop activity, so the receiving phone opens the app without the
/// Files step, and the FILE (Patient handoff.periop, the same bytes and name as ShareLink sends today) for every other
/// activity, so Messages still gets its attachment. When the link would be longer than PatientLink.maxLinkLength,
/// AirDrop is given the file too.
final class PatientShareItem: NSObject, UIActivityItemSource {
    let packet: PatientPacket
    /// The link, or nil when it would be too long (AirDrop then sends the file as before).
    let link: URL?
    /// The file, written to this phone's tmp folder when the sheet is prepared and removed at the next launch.
    let fileURL: URL

    /// Nil when the file cannot be written.
    init?(packet: PatientPacket) {
        self.packet = packet
        link = PatientLink.url(for: packet)
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

/// The Send Patient button: the share sheet with the AirDrop link when the switch in More is on (the item above), the
/// plain ShareLink with the file otherwise. Both carry the case's name.
struct PatientSendButton: View {
    @Environment(Preferences.self) private var prefs
    var record: PatientRecord
    /// The current case's name, nil when it has none.
    var room: String?
    @State private var sharing: [Any]?
    @State private var failed = false

    var body: some View {
        if prefs.airDropLink {
            Button {
                if let item = PatientShareItem(packet: PatientPacket(record: record, room: room)) {
                    sharing = [item]
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
                Text("Try again, or turn off the AirDrop link in More.")
            }
        } else {
            ShareLink(item: PatientTransfer(record: record, room: room),
                      preview: SharePreview("Patient for handoff", image: Image(systemName: "person.text.rectangle"))) {
                Label("Send Patient", systemImage: "iphone.and.arrow.forward").frame(maxWidth: .infinity)
            }
            .buttonStyle(BigButtonStyle(prominent: false))
        }
    }
}
