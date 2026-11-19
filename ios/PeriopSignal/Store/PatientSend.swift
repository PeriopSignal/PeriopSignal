import Foundation

// MARK: - Sending and receiving a patient with the case's name (1.12, Ben)
//
// The case's name ("OR 12"; PatientCase.room, shown as its label) travels with the patient. The room's phone does not.
// The receiving phone names a new case with it; a case that is replaced keeps its own name and takes the sent one only
// when it has none; the archive and the summaries leave the room out, as before.

extension PatientPacket {
    /// A packet for a case: its record and its name (nil when it has none). The room's phone is not part of a packet.
    init(of c: PatientCase, sent: Date = Date()) {
        self.init(record: c.record, sent: sent, room: c.hasRoom ? c.room : nil)
    }
}

/// What the receiving sheet and the store do with a sent case name.
enum PatientReceiveRule {
    /// The name a case ends with when a patient is opened in it: its own when it has one, else the sent one.
    static func nameAfterOpeningInPlace(own: String, sent: String?) -> String {
        let mine = own.trimmingCharacters(in: .whitespacesAndNewlines)
        return mine.isEmpty ? (sent ?? "") : mine
    }

    /// One short clause for the "Patient Received" sheet saying what happens to the name, or nil when there is nothing
    /// to say (no sent name, or the case already has exactly that name and no new case is offered).
    /// - hasPatient: the phone holds a patient now (so the button reads "Replace <case>", else "Open This Patient").
    static func note(sent: String?, own: String, hasPatient: Bool, canAddCase: Bool) -> String? {
        guard let sent = PatientPacket.cleanRoom(sent) else { return nil }
        let mine = own.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if hasPatient && canAddCase { parts.append("A new case is named \(sent).") }
        if mine.isEmpty {
            parts.append(hasPatient ? "Replace names this case \(sent)." : "This case will be named \(sent).")
        } else if mine != sent {
            parts.append(hasPatient ? "Replace keeps your case name, \(mine)." : "This case keeps its name, \(mine).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

extension PatientStore {
    /// Opens a received patient: as a new case (named with the sent name when there is one) or in place of the current
    /// one, which keeps its own name and takes the sent one only when it has none.
    func openReceived(_ packet: PatientPacket, asNewCase: Bool) {
        let name = packet.caseName
        if asNewCase {
            addCase(room: name ?? "")
            receive(packet.record)
        } else {
            receive(packet.record)
            let c = currentCase
            let named = PatientReceiveRule.nameAfterOpeningInPlace(own: c.room, sent: name)
            if named != c.room.trimmingCharacters(in: .whitespacesAndNewlines) {
                updateBook { $0.setRoom(named, phone: c.roomPhone) }
            }
        }
    }
}

/// Where a URL the app is opened with goes (onOpenURL). A patient link holds the patient, so it is taken first: it selects
/// My Patient, is read into the inbox (which only waits for the user's answer), and is never passed to the router, logged,
/// indexed or kept. A patient file (AirDrop to Files, Messages) is read the same way. Everything else, including the tab
/// link periopsignal://patient, is the router's.
@MainActor
enum IncomingURL {
    static func handle(_ url: URL, inbox: PatientInbox, router: Router) {
        if PatientLink.isPatientLink(url) {
            inbox.receiveLink(url)
            router.selectedTab = .patient
        } else if PatientInbox.handles(url) {
            inbox.receive(url)
            router.selectedTab = .patient
        } else {
            router.handle(url)
        }
    }
}

/// The words under Send in My Patient's handoff.
enum PatientSendText {
    static let approved = "Send only to the colleague taking over, through channels your institution approves; Messages keeps a copy in the conversation."

    /// The note under the Send button. With the AirDrop link on, it says AirDrop opens the app; a named case adds that
    /// its name is sent too.
    static func note(airDropLink: Bool, caseNamed: Bool) -> String {
        var t = airDropLink ? "By AirDrop it opens straight in their Periop Signal. " : ""
        t += "In Messages, they tap the file, then Share, then Periop Signal. " + approved
        if caseNamed { t += " The case's name is sent with it." }
        return t
    }
}

/// The files made for a send (the patient file, or the summary PDF), kept in this phone's tmp folder, one folder each.
/// Ben, Nov 19 (after an outside review): they hold the patient, so they are written like the stored records: complete
/// file protection on the file and on its folders, and left out of backups. They are removed when the share sheet is
/// dismissed (ShareSheet), at the next launch, and any older than ten minutes when another is made.
enum PatientSendFiles {
    static var folder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("PatientSend", isDirectory: true) }

    /// The attributes every folder here is made with.
    static let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]

    /// Writes `data` as `name` in a new folder of its own (tmp/PatientSend/<UUID>/<name>), protected and out of backups;
    /// the file keeps `name` so the receiving app and the share sheet show it. Nil when it cannot be written.
    static func write(_ data: Data, named name: String) -> URL? {
        purge(olderThan: 600)
        let fm = FileManager.default
        var parent = folder
        var dir = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = dir.appendingPathComponent(name)
        do {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: protection)
            // A folder an earlier build made has no protection yet.
            try? fm.setAttributes(protection, ofItemAtPath: parent.path)
            try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: protection)
        } catch {
            return nil
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? parent.setResourceValues(values)
        try? dir.setResourceValues(values)
        guard PatientFiles.write(data, to: file) else {
            try? fm.removeItem(at: dir)
            return nil
        }
        return file
    }

    /// Removes the files made for earlier sends (all, or only those older than the given seconds).
    static func purge(olderThan seconds: TimeInterval = 0) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for item in items {
            let made = (try? item.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            if seconds <= 0 || Date().timeIntervalSince(made) > seconds { try? fm.removeItem(at: item) }
        }
    }
}
