import Foundation
import Observation

/// My Patient's record: one patient at a time, kept on this device only until the user clears it.
///
/// The file sits in Application Support with complete file protection (unreadable while the phone is locked) and is
/// excluded from iCloud and computer backups; nothing is sent anywhere. Clear removes the file and keeps the cleared
/// record in memory, so Undo can bring it back until the next edit or until the app quits.
@MainActor
@Observable
final class PatientStore {
    private(set) var record = PatientRecord()
    /// The record just cleared, for Undo.
    private(set) var cleared: PatientRecord?
    /// The file has been read (it cannot be while the phone is locked); edits wait for it so nothing overwrites it.
    private(set) var loaded = false

    private let url: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false

    init(url: URL? = PatientStore.defaultURL()) {
        self.url = url
        #if DEBUG
        if let demo = PatientStore.debugSeed() {
            record = demo
            loaded = true
            return
        }
        #endif
        reload()
    }

    var isEmpty: Bool { record.isEmpty }
    var canUndo: Bool { cleared != nil && record.isEmpty }

    /// Change the record; it is written to disk shortly after.
    func update(_ change: (inout PatientRecord) -> Void) {
        if !loaded { reload() }
        var r = record
        change(&r)
        guard r != record else { return }
        r.updated = Date()
        record = r
        cleared = nil
        scheduleSave()
    }

    func clear() {
        guard !record.isEmpty else { return }
        saveTask?.cancel()
        cleared = record
        record = PatientRecord()
        dirty = false
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    func undoClear() {
        guard let c = cleared else { return }
        record = c
        cleared = nil
        scheduleSave(immediately: true)
    }

    /// Reads the file if it has not been read yet (call when the app becomes active), and writes pending edits.
    func refresh() {
        if !loaded { reload() }
        if dirty { scheduleSave(immediately: true) }
    }

    // MARK: Values the tools use

    var weightKg: Double? { record.weightKg }
    var ageYears: Double? { record.ageYears }
    var sex: PatientSex? { record.sex }
    var heightCm: Double? { record.heightCm }

    // MARK: Storage

    private func reload() {
        guard let url else { loaded = true; return }
        if !FileManager.default.fileExists(atPath: url.path) { loaded = true; return }
        guard let data = try? Data(contentsOf: url) else { return }   // locked: try again when active
        if let r = try? JSONDecoder().decode(PatientRecord.self, from: data) { record = r }
        loaded = true
    }

    private func scheduleSave(immediately: Bool = false) {
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(nanoseconds: 400_000_000) }
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    private func write() {
        guard let url else { dirty = false; return }
        if record.isEmpty {
            try? FileManager.default.removeItem(at: url)
            dirty = false
            return
        }
        guard let data = try? JSONEncoder().encode(record) else { return }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var u = url
            try? u.setResourceValues(values)
            dirty = false
        } catch {
            // Locked or out of space: keep it dirty and try again when the app is next active.
        }
    }

    nonisolated static func defaultURL() -> URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        var folder = base.appendingPathComponent("MyPatient", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        return folder.appendingPathComponent("patient.json")
    }

    #if DEBUG
    /// Screenshot runs: -ps.patient demo fills a made-up patient (never written to disk).
    static func debugSeed() -> PatientRecord? {
        guard LaunchSeed.string("ps.patient") == "demo" else { return nil }
        return PatientDemo.record
    }
    #endif
}

/// A made-up patient for screenshots and previews.
enum PatientDemo {
    static var record: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = 96
        r.procedure = "Laparoscopic sigmoid colectomy"
        r.urgency = .elective
        r.anesthetic = ["ga", "regional"]
        r.highRiskSurgery = true
        r.incision = "Upper abdominal"; r.duration = "> 3 h"
        r.vitals = ["sbp": 148, "dbp": 86, "hr": 72, "spo2": 95]
        r.problems = ["htn", "cad", "pci", "dm", "insulin", "osa", "cpap", "snoring", "copd"]
        r.systemNotes = ["cv": "DES to LAD 2023; on aspirin"]
        r.smoking = "former"
        r.allergies = "Penicillin (rash)"
        r.medications = "Metoprolol, lisinopril, atorvastatin, insulin glargine, aspirin"
        r.medFlags = ["betablocker", "acei", "insulin", "aspirin"]
        r.anesthesiaHistory = ["ponv"]
        r.labs = ["hb": 12.8, "plt": 210, "k": 4.3, "cr": 1.1, "glucose": 162]
        r.mets = "ge4"
        r.asaClass = 3
        r.mallampati = 3
        r.airwaySigns = ["neck40", "thick-neck"]
        r.dentition = "Upper partial denture, removed"
        r.mask = "easy"; r.intubation = "easy"; r.airwayDevice = "Video laryngoscope"; r.laryngoscopyGrade = "1"; r.attempts = 1
        r.tube = "7.5 ETT, 23 cm at the lip"
        r.lines = [PatientLine(kind: "Peripheral IV", site: "left forearm", size: "18 G"), PatientLine(kind: "Arterial line", site: "right radial", size: "20 G")]
        r.regional = [PatientRegional(technique: "TAP block", side: "Bilateral", drug: "ropivacaine 0.25% 20 mL each side")]
        r.infusions = [PatientInfusion(drug: "Phenylephrine", rate: "0.3 mcg/kg/min")]
        r.fluids = ["crystalloid": 1800, "ebl": 250, "uop": 320]
        r.medsGiven = "Cefazolin 2 g 08:10; dexamethasone 4 mg; ondansetron 4 mg"
        r.noEvents = true
        r.disposition = "PACU"
        r.painPlan = "TAP blocks; acetaminophen; hydromorphone PCA if needed"
        r.callIf = "SBP under 90 or over 170; SpO₂ under 92%"
        r.todos = "Resume CPAP in PACU; check glucose on arrival"
        r.scores["rcri"] = PatientScore(points: 3, max: 6, label: "Class IV · 3 or more", detail: "15.0% (11.1–20.0)", answers: ["High-risk surgery", "Ischemic heart disease", "Insulin therapy for diabetes"], date: Date())
        return r
    }
}
