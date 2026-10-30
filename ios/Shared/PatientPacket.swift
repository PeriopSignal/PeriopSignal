import Foundation

// MARK: - Sending a patient to a colleague
//
// The record goes as a Periop Signal file (.periop) through the share sheet: AirDrop, including holding two iPhones
// together, or an iMessage attachment. Both travel directly between the phones, end to end encrypted by Apple;
// Periop Signal has no server for patients. The record holds no name, record number or date of birth. The receiving
// app reads the file into memory, deletes the copy iOS handed it, and puts the patient into My Patient only after
// the user agrees.

struct PatientPacket: Codable, Equatable {
    static let identifier = "org.periopsignal.patient"
    static let fileExtension = "periop"
    static let fileName = "Patient handoff.periop"
    /// A record is a few kilobytes; anything far larger is not one.
    static let maxBytes = 1_000_000
    /// The newest format this version reads.
    static let currentFormat = 1

    var kind: String
    var format: Int
    var sent: Date
    var record: PatientRecord

    init(record: PatientRecord, sent: Date = Date()) {
        kind = PatientPacket.identifier
        format = PatientPacket.currentFormat
        self.sent = sent
        self.record = record
    }

    enum Problem: Error, Equatable {
        case tooLarge, notAPatient, newerFormat, unreadable

        var message: String {
            switch self {
            case .tooLarge, .notAPatient: return "This file isn't a patient sent from Periop Signal."
            case .newerFormat: return "This patient was sent from a newer version of Periop Signal. Update the app, then open the file again."
            case .unreadable: return "This patient file couldn't be read. Ask your colleague to send it again."
            }
        }
    }

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    static func decode(_ data: Data) throws -> PatientPacket {
        guard data.count <= maxBytes else { throw Problem.tooLarge }
        guard let p = try? JSONDecoder().decode(PatientPacket.self, from: data) else {
            // Something else with our extension, or a damaged file.
            if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], o["kind"] as? String == identifier {
                throw (o["format"] as? Int ?? 0) > currentFormat ? Problem.newerFormat : Problem.unreadable
            }
            throw Problem.notAPatient
        }
        guard p.kind == identifier else { throw Problem.notAPatient }
        guard p.format <= currentFormat else { throw Problem.newerFormat }
        return p
    }

    /// What the patient file holds, for the screen that asks before opening it ("History, assessment and airway").
    var contents: String {
        let r = record
        var parts: [String] = []
        if !PatientSummary.historyLines(r).isEmpty { parts.append("history") }
        if !PatientSummary.assessmentLines(r).isEmpty { parts.append("assessment") }
        if !PatientSummary.airwayLines(r).isEmpty { parts.append("airway") }
        if !PatientSummary.intraopLines(r).isEmpty { parts.append("intraoperative course") }
        if !PatientSummary.planLines(r).isEmpty { parts.append("plan") }
        guard let first = parts.first else { return "Patient details only" }
        var list = parts
        list[0] = first.prefix(1).uppercased() + first.dropFirst()
        if list.count == 1 { return list[0] }
        return list.dropLast().joined(separator: ", ") + " and " + (list.last ?? "")
    }
}
