import Foundation
import Observation

/// My Patient's cases, one per room (PatientCases), each kept on this device only until it is cleared or ended.
/// `record` and `update` are the current case's.
///
/// The file sits in Application Support with complete file protection (unreadable while the phone is locked) and is
/// excluded from iCloud and computer backups; nothing is sent anywhere. Clear empties the current case and keeps the
/// cleared record in memory, so Undo can bring it back until the next edit, a change of case or until the app quits;
/// the file is removed once nothing is left in it. Ending a case keeps a summary in the archive (PatientArchive).
///
/// Every change to the current case is also a step that `undo()` steps back through, on any tab or editor
/// (PatientUndoHistory): in memory only, per case, up to 50 steps, a burst of typing as one step and a discrete action
/// (`update(discrete: true)`, or `markDiscrete()` just before a binding is written) as its own. Each case keeps its own
/// steps until the app quits; ending a case drops them.
@MainActor
@Observable
final class PatientStore {
    /// Every case, and which one is current.
    private(set) var book = PatientCaseBook()
    /// The current case's record.
    private(set) var record: PatientRecord {
        get { book.currentRecord }
        set { book.currentRecord = newValue }
    }
    /// Ended cases' summaries, and the saved rooms (hospital data), in their own protected files beside this one.
    let archive: PatientArchive
    let rooms: PatientRoomDirectory
    /// The record just cleared, for Undo.
    private(set) var cleared: PatientRecord?
    /// The record a patient from a colleague just replaced, for Undo.
    private(set) var replaced: PatientRecord?
    /// The file has been read (it cannot be while the phone is locked); edits wait for it so nothing overwrites it.
    private(set) var loaded = false
    /// The current case has a change to undo (the Undo buttons show).
    private(set) var canUndo = false

    private let url: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var history = PatientUndoHistory()
    /// Set by `markDiscrete()`: the next change, if it comes within a second, is a step of its own.
    @ObservationIgnored private var discreteMark: Date?

    /// The app's: the cases kept in Application Support. In a screenshot run with a -ps.patient seed (debug builds),
    /// the seed's made-up cases instead, and the folder is not touched.
    convenience init() {
        #if DEBUG
        if let seed = PatientStore.debugCases() {
            self.init(url: nil, seed: seed)
            return
        }
        #endif
        self.init(url: PatientStore.defaultURL(), seed: nil)
    }

    /// The cases kept at `url`, or in memory only with nil (tests).
    convenience init(url: URL?) {
        self.init(url: url, seed: nil)
    }

    /// With a `seed` (screenshot runs and tests), its cases, archive and rooms, held in memory only: nothing is read
    /// from or written to `url` or the files beside it, so a screenshot that edits the made-up patient leaves nothing
    /// behind for the next launch.
    init(url: URL?, seed: PatientDemo.Seed?) {
        if let seed {
            self.url = nil
            archive = PatientArchive(url: nil, entries: seed.archived)
            rooms = PatientRoomDirectory(url: nil, rooms: seed.rooms)
            book = seed.book
            loaded = true
            return
        }
        self.url = url
        archive = PatientArchive(url: PatientStore.fileURL("archive.json", near: url))
        rooms = PatientRoomDirectory(url: PatientStore.fileURL("rooms.json", near: url))
        reload()
    }

    var isEmpty: Bool { record.isEmpty }
    /// The patient was just cleared (the "Patient cleared" banner); Undo brings it back.
    var canUndoClear: Bool { cleared != nil && record.isEmpty }
    var canUndoReceive: Bool { replaced != nil }

    /// Change the record; it is written to disk shortly after. The change is an Undo step: one with the changes around
    /// it less than a second apart (typing), or its own with `discrete` (an add, a delete, a tap).
    func update(discrete: Bool = false, now: Date = Date(), _ change: (inout PatientRecord) -> Void) {
        if !loaded { reload() }
        var r = record
        change(&r)
        // Fills follow their sources whatever made the change (1.9).
        PatientCrossFill.apply(before: record, after: &r)
        guard r != record else { return }
        history.willChange(record, case: book.currentID, discrete: discrete || takeDiscreteMark(now), now: now)
        r.updated = now
        record = r
        cleared = nil
        replaced = nil
        syncUndo()
        scheduleSave()
    }

    /// The next change is a step of its own: for a chip, toggle or stepper that writes through a binding. It lapses
    /// after a second if no change follows (a control that edits something other than the patient).
    func markDiscrete(now: Date = Date()) {
        discreteMark = now
    }

    private func takeDiscreteMark(_ now: Date) -> Bool {
        defer { discreteMark = nil }
        guard let m = discreteMark else { return false }
        let gap = now.timeIntervalSince(m)
        return gap >= 0 && gap < 1
    }

    /// Steps back one change in the current case.
    func undo() {
        if !loaded { reload() }
        guard let previous = history.pop(book.currentID) else { syncUndo(); return }
        record = previous
        cleared = nil
        replaced = nil
        syncUndo()
        scheduleSave(immediately: true)
    }

    /// The last step of the current case is the change from `before` to `after`, and nothing has changed since: what
    /// the quick-add and note banners check before offering their Undo.
    func isLatestStep(before: PatientRecord, after: PatientRecord) -> Bool {
        record == after && history.top(book.currentID) == before
    }

    private func syncUndo() {
        let can = history.canUndo(book.currentID)
        if can != canUndo { canUndo = can }
    }

    /// Opens a patient a colleague sent in place of the current one, which Undo can bring back until the next edit.
    func receive(_ incoming: PatientRecord) {
        if !loaded { reload() }
        var r = incoming
        r.updated = Date()
        history.willChange(record, case: book.currentID, discrete: true)
        replaced = record.isEmpty ? nil : record
        cleared = nil
        record = r
        syncUndo()
        scheduleSave(immediately: true)
    }

    func undoReceive() {
        guard let p = replaced else { return }
        if history.top(book.currentID) == p { _ = history.pop(book.currentID) }
        record = p
        replaced = nil
        syncUndo()
        scheduleSave(immediately: true)
    }

    func clear() {
        guard !record.isEmpty else { return }
        saveTask?.cancel()
        history.willChange(record, case: book.currentID, discrete: true)
        cleared = record
        replaced = nil
        record = PatientRecord()
        syncUndo()
        dirty = true
        write()
    }

    func undoClear() {
        guard let c = cleared else { return }
        if history.top(book.currentID) == c { _ = history.pop(book.currentID) }
        record = c
        cleared = nil
        syncUndo()
        scheduleSave(immediately: true)
    }

    /// Changes the cases (add, switch, room, end); written to disk shortly after. A change of case ends the Clear and
    /// Receive banners; each case keeps its own Undo steps, and those of a case ended or removed are dropped.
    func updateBook(immediately: Bool = false, _ change: (inout PatientCaseBook) -> Void) {
        if !loaded { reload() }
        var b = book
        change(&b)
        guard b != book else { return }
        if b.currentID != book.currentID {
            cleared = nil
            replaced = nil
        }
        history.keep(only: Set(b.cases.map(\.id)))
        book = b
        syncUndo()
        scheduleSave(immediately: immediately)
    }

    /// Reads the file if it has not been read yet (call when the app becomes active), writes pending edits, and
    /// deletes archived summaries past their retention period.
    func refresh() {
        if !loaded { reload() }
        if dirty { scheduleSave(immediately: true) }
        archive.prune()
        rooms.refresh()
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
        if let b = PatientCaseBook.decode(data) { book = b }   // a 1.6 record becomes the first case
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
        if book.isEmpty {
            try? FileManager.default.removeItem(at: url)
            dirty = false
            return
        }
        guard let data = try? book.encoded() else { return }
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
    static func debugSeed(_ seed: String = LaunchSeed.string("ps.patient")) -> PatientRecord? {
        switch seed {
        case "demo": return PatientDemo.record
        case "demo-cardiac": return PatientDemo.cardiac
        case "demo-dnr": return PatientDemo.dnr
        case "demo-history": return PatientDemo.history
        case "demo-cardio": return PatientDemo.cardio
        case "demo-neuro": return PatientDemo.neuro
        case "demo-typed": return PatientDemo.typed
        case "demo-labs": return PatientDemo.labs
        case "demo-meds": return PatientDemo.meds
        default: return nil
        }
    }
    #endif
}

/// A made-up patient for screenshots and previews.
enum PatientDemo {
    /// The demo patient with the 1.8.1 History items: plain Diabetes, Stroke, unspecified, and Infectious problems.
    static var history: PatientRecord {
        var r = record
        r.problems = ["htn", "dm", "cva-unspec", "copd", "hepatitis-viral", "mdro", "isolation"]
        r.medFlags.remove("insulin")
        r.asaClass = nil
        return r
    }

    /// The demo patient with the 1.8.3 labs: Ben's screenshot's values (Hct left out, so it shows as an estimate), the
    /// creatinine and INR typed as whole numbers, a lactate, type and screen, and the infectious results.
    static var labs: PatientRecord {
        var r = record
        r.labs = ["hb": 15, "wbc": 6.8, "plt": 175, "inr": 1, "na": 139, "k": 4.8, "cl": 103, "hco3": 26, "bun": 16, "cr": 1,
                  "glucose": 78, "lactate": 1.4]
        r.typeScreen = PatientTypeScreen(type: "A-", screen: .negative, crossmatched: 2)
        r.infections = PatientInfections(results: ["staph": .negative, "mrsa": .negative, "covid": .negative, "cdiff": .pending])
        r.asaClass = nil
        // A shorter history, so the handoff's labs line shows on the first screen of the handoff shot.
        r.surgeries = []
        r.considerations = []
        r.considerationsNote = ""
        r.anesthesiaHistory = []
        r.anesthesiaNotes = ""
        return r
    }

    /// The demo patient with the 1.8.2 Neurologic page filled in: a stroke within 3 months, an intracranial bleed with mass
    /// effect, and a few other items.
    static var neuro: PatientRecord {
        var r = record
        r.problems = ["htn", "dm", "cva-recent", "ich-mass", "seizure", "dementia", "chronic-pain"]
        r.medFlags.remove("insulin")
        r.systemNotes = ["neuro": "On levetiracetam"]
        r.asaClass = nil
        return r
    }

    /// The demo patient with the 1.8.1 Cardiovascular and Respiratory sections filled in: each option, detail and
    /// study row shows (Ben's summary example).
    static var cardio: PatientRecord {
        var r = record
        r.problems = ["htn", "hyperlipidemia", "cad-recent", "cabg", "hf-decomp", "ef-severe", "af", "pacemaker", "pulm-htn", "dissection-b", "tevar",
                      "dm", "copd", "osa", "cpap", "pneumonia", "home-o2"]
        r.hx.valves = ["aortic": PatientValve(stenosis: true, stenosisGrade: "severe"), "mitral": PatientValve(prosthetic: true, prosthesis: "mechanical 27 mm")]
        r.hx.deviceDetails = "dependent"
        r.hx.pulmHtnSeverity = "moderate"
        r.hx.aneurysms = ["root": PatientAneurysm(cm: 4.8)]
        r.hx.repairDetails = "2021"
        r.hx.cpapSettings = "BiPAP 14/8"
        r.hx.homeO2Flow = 2
        r.systemNotes = ["cv": "Followed by cardiology"]
        PatientHistoryDetails.setCardiacSurgery("CABG ×3 2019", &r)
        PatientHistoryDetails.sync(&r)
        r.ecg = ["Atrial fibrillation"]
        var echo = PatientEcho()
        echo.study = "TTE"; echo.lv = .severe; echo.lvef = 25
        r.echoFindings = echo
        r.medFlags.insert("anticoagulant")
        r.asaClass = nil
        return r
    }

    static var record: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 67; r.sex = .male; r.heightCm = 178; r.weightKg = 96
        r.setProcedures(PlannedProcedure.parse("Laparoscopic sigmoid colectomy"))
        r.urgency = .elective
        r.anesthetic = ["ga", "regional"]
        r.highRiskSurgery = true
        r.incision = "Upper abdominal"; r.duration = "> 3 h"
        r.vitals = ["sbp": 148, "dbp": 86, "hr": 72, "spo2": 95]
        r.problems = ["htn", "pci", "dm", "insulin", "osa", "cpap", "copd"]
        r.hx.cpapSettings = "CPAP 10"
        r.systemNotes = ["cv": "DES to LAD 2023; on aspirin"]
        r.smoking = "former"
        r.allergies = "Penicillin (rash)"
        r.medications = "Metoprolol, lisinopril, atorvastatin, insulin glargine, aspirin"
        r.medFlags = ["betablocker", "acei", "insulin", "aspirin", "statin"]
        r.anesthesiaHistory = ["ponv"]
        r.labs = ["hb": 12.8, "plt": 210, "k": 4.3, "cr": 1.1, "glucose": 162]
        r.mets = "ge4"
        r.asaClass = 3
        r.mallampati = 3
        r.airwaySigns = ["neck40", "thick-neck"]
        r.dentition = "Upper partial denture, removed"
        r.mask = "easy"; r.intubation = "easy"; r.airwayDevice = "Video laryngoscope"; r.laryngoscopyGrade = "1"; r.attempts = 1
        r.tube = "7.5 ETT, 23 cm at the lip"
        r.airwayAtEnd = "extubated"
        r.devices = ["18g lfa", "20g R radial art line"].compactMap { PatientDevices.parse($0)?.device(placedIntraop: true) }
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
        r.surgeries = [PatientSurgery(name: "Total knee arthroplasty", side: "right", date: PatientMonthYear(month: 3, year: 2019)),
                       PatientSurgery(procedures: PlannedProcedure.parse("lap chole + umbilical hernia repair"), date: PatientMonthYear(year: 2015))]
        r.cardiacSymptomsAnswer = false
        r.activeCardiacAnswer = false
        r.ecg = ["Normal sinus rhythm", "Q waves (old infarct)"]
        var echo = PatientEcho()
        echo.study = "TTE"; echo.date = PatientMonthYear(month: 6, year: 2026)
        echo.lv = .mild; echo.lvef = 50; echo.rv = .normal
        echo.mitral = EchoValve(regurgitation: .mild); echo.aortaIntact = true
        r.echoFindings = echo
        var lhc = PatientLHC()
        lhc.dominance = "right"; lhc.stenosis = ["lad": 90, "rca": 40]; lhc.notes = "DES to proximal LAD"; lhc.date = PatientMonthYear(month: 5, year: 2023)
        r.lhc = lhc
        r.currentAirway = "natural"
        r.oxygen = PatientOxygen(device: "ra")
        // Intraoperative labs with the pneumoperitoneum, the considerations for the handoff and the code status.
        r.intraopLabs = [IntraopLabSet(time: PatientDemo.today(10, 40), values: ["ph": 7.33, "paco2": 47, "pao2": 212, "hco3a": 24, "be": -1.5,
                                                                              "lactate": 1.1, "hb": 11.6, "k": 4.1, "na": 139, "ica": 1.14, "glucose": 192])]
        r.considerations = ["positioning"]
        r.considerationsNote = "Steep Trendelenburg with arms tucked for 3 h; pressure points padded, eyes taped"
        r.codeStatus = .full
        return r
    }

    /// The demo patient with DNR/DNI orders modified for the procedure, for the code-status screenshots.
    static var dnr: PatientRecord {
        var r = record
        r.codeStatus = .dnrDni
        r.polst = true
        r.codeStatusPlan = .modified
        r.codeStatusPlanNote = "Accepts intubation and vasopressors for the procedure; no chest compressions or defibrillation. Original orders resume on leaving the PACU"
        return r
    }

    /// Today at this time on the device's clock.
    static func today(_ hour: Int, _ minute: Int) -> Date? {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
    }

    /// A made-up cardiac ICU patient on support, for the diagram screenshots.
    static var cardiac: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 58; r.sex = .male; r.heightCm = 180; r.weightKg = 88
        r.setProcedures(PlannedProcedure.parse("Emergency CABG ×3 on VA ECMO"))
        r.urgency = .emergency
        r.anesthetic = ["ga"]
        r.problems = ["htn", "cad", "hf"]
        r.currentAirway = "ett"; r.ettSize = "8.0"; r.ettDepth = "23 cm at the lip"
        r.vent.mode = "AC/VC"; r.vent.vt = 450; r.vent.rr = 18; r.vent.peep = 8; r.vent.fio2 = 60
        r.homeInfusions = [PatientInfusion(drug: "Epinephrine", rate: "0.05 mcg/kg/min"), PatientInfusion(drug: "Norepinephrine", rate: "0.1 mcg/kg/min")]
        r.devices = ["20 lue", "R radial art line 20g", "swan RIJ 8.5 Fr introducer", "VA ECMO 25F RFV drainage / 17F LFA return flow 4.2 sweep 3", "L fem IABP 7.5 Fr 1:1", "foley 16 Fr"]
            .flatMap { PatientDevices.parse($0)?.devices(placedIntraop: false) ?? [] }
        var echo = PatientEcho()
        echo.study = "TEE"; echo.lv = .severe; echo.lvef = 15; echo.rv = .moderate
        echo.mitral = EchoValve(regurgitation: .moderate)
        r.echoFindings = echo
        var rhc = PatientRHC()
        rhc.ra = 16; rhc.pasp = 48; rhc.padp = 24; rhc.pcwp = 26; rhc.co = 3.1
        r.rhc = rhc
        r.labs = ["hb": 9.1, "plt": 96, "inr": 1.8, "fibrinogen": 180, "na": 131, "k": 4.9, "cr": 1.9, "bun": 38,
                  "albumin": 2.9, "tbili": 2.4, "troponin": 4200, "troponin99": 14, "glucose": 188]
        r.labSections = ["cardiac", "liver"]
        r.dialysis = false
        // The TEE screen: an earlier fundoplication (relative, from the surgical history), dysphagia answered on the
        // checklist, and the platelets and INR offered to confirm.
        r.surgeries = [PatientSurgery(name: "Laparoscopic Nissen fundoplication", procedureID: "nissen", date: PatientMonthYear(year: 2018))]
        r.teeScreen.set("dysphagia", true)
        r.teeScreen.set("stricture", false)
        r.fluids = ["crystalloid": 1500, "prbc": 4, "plasma": 4, "platelets": 2, "cryo": 10, "cellSaver": 750, "ebl": 2200, "uop": 400]
        r.factors = "PCC 1500 units"
        r.intraopLabs = [
            IntraopLabSet(time: PatientDemo.today(9, 15), values: ["ph": 7.35, "paco2": 40, "pao2": 245, "hco3a": 22, "be": -3, "lactate": 2.6,
                                                                  "hb": 9.4, "k": 4.6, "na": 134, "ica": 1.12, "glucose": 176, "act": 132]),
            IntraopLabSet(time: PatientDemo.today(13, 20), values: ["ph": 7.29, "paco2": 41, "pao2": 168, "hco3a": 19, "be": -6.5, "lactate": 4.2,
                                                                   "hb": 7.9, "k": 5.4, "na": 133, "ica": 1.02, "glucose": 214,
                                                                   "inr": 1.9, "ptt": 52, "fibrinogen": 142, "plt": 74, "act": 128],
                          viscoelastic: "EXTEM CT 92 s, A10 34 mm; FIBTEM A10 6 mm"),
        ]
        // Studies (1.8.1): a planned left radial artery graft, severe left carotid disease with reversed left vertebral
        // flow, obstructive PFTs, and an abdominal aortic aneurysm, so the screenshots show every caution.
        r.hx.aneurysms = ["abdominal": PatientAneurysm(cm: 4.8)]
        PatientHistoryDetails.sync(&r)
        r.carotid.right = CarotidSide(stenosis: "50-69", vertebral: "antegrade", psv: 182, edv: 54)
        r.carotid.left = CarotidSide(stenosis: "ge70", vertebral: "reversed", psv: 268, edv: 112)
        r.carotid.date = PatientMonthYear(month: 9, year: 2026)
        r.radial.right = RadialSide(diameter: 2.3, calcified: false, ulnar: "adequate")
        r.radial.left = RadialSide(diameter: 2.7, calcified: false, ulnar: "adequate")
        r.radial.harvest = "left"
        r.radial.date = PatientMonthYear(month: 9, year: 2026)
        r.pft.fev1 = 1.86; r.pft.fev1Pct = 58; r.pft.fvc = 3.21; r.pft.fvcPct = 79; r.pft.ratioTyped = 0.58
        r.pft.tlcPct = 104; r.pft.dlcoPct = 62
        r.pft.pattern = "obstruction"; r.pft.severity = "moderate"
        r.pft.date = PatientMonthYear(month: 8, year: 2026)
        r.considerations = ["pressors", "tee", "surgical"]
        r.considerationsNote = "Epinephrine and norepinephrine rising after bypass; severe LV dysfunction on TEE; diffuse coagulopathy, chest may stay open"
        r.codeStatus = .full
        return r
    }
}

// MARK: - 1.9 medication and allergy lists (the demo for their screenshots)

extension PatientDemo {
    /// The demo patient with the medications and allergies as items (1.9): brands typed and read as generics, a dose on
    /// each, a GLP-1 agonist and an anticoagulant flagged, and three allergies with their severity.
    static var meds: PatientRecord {
        var r = record
        r.medications = ""
        r.allergies = ""
        r.homeMeds = MedicationCatalog.parse("Toprol XL 50 mg daily, lisinopril 20 mg daily, atorvastatin 40 mg qhs, Lantus 30 units qhs, "
                                             + "Eliquis 5 mg bid, Mounjaro 7.5 mg weekly, sertraline 100 mg")
        r.medFlags = MedicationCatalog.flags(for: r.homeMeds)
        r.allergyList = AllergyCatalog.parse("PCN mild rash, sulfa (hives), latex anaphylaxis")
        return r
    }
}
