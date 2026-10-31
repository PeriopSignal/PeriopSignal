import Foundation

// MARK: - My Patient workup records
//
// Past operations, echo findings, catheterization, the ECG and the patient's current airway support: what the
// preoperative tab records beyond the problem lists. Every type decodes with a fallback for each field, like
// PatientRecord, so a patient saved by an older version (or sent from one) still opens.

/// Month and year, as a chart gives them ("03/2019", or "2019" alone).
struct PatientMonthYear: Codable, Hashable {
    var month: Int?
    var year: Int?

    init(month: Int? = nil, year: Int? = nil) { self.month = month; self.year = year }

    var isEmpty: Bool { month == nil && year == nil }
    var text: String {
        guard let y = year else { return "" }
        guard let m = month, (1...12).contains(m) else { return String(y) }
        return String(format: "%02d/%d", m, y)
    }

    /// Reads "03/2019", "3/19", "2019" or "Mar 2019".
    static func parse(_ s: String) -> PatientMonthYear? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }
        func year(_ y: Int) -> Int? {
            if y >= 1900 && y <= 2100 { return y }
            if y >= 0 && y < 100 { return y + (y <= (Calendar.current.component(.year, from: Date()) % 100) ? 2000 : 1900) }
            return nil
        }
        let parts = t.split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == " " || $0 == "." }).map(String.init)
        if parts.count == 1, let y = Int(parts[0]).flatMap(year) { return PatientMonthYear(year: y) }
        if parts.count == 2, let y = Int(parts[1]).flatMap(year) {
            if let m = Int(parts[0]), (1...12).contains(m) { return PatientMonthYear(month: m, year: y) }
            let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            if let m = months.firstIndex(where: { parts[0].hasPrefix($0) }) { return PatientMonthYear(month: m + 1, year: y) }
        }
        return nil
    }
}

/// One planned procedure: from the procedure list (with its side when it has one) or typed, plus any details
/// ("×3", "possible open conversion").
struct PlannedProcedure: Codable, Hashable, Identifiable {
    var id = UUID()
    /// The procedure list's id; nil when typed.
    var catalogID: String?
    var name = ""
    /// "left", "right", "bilateral".
    var side: String?
    var detail = ""

    init(catalogID: String? = nil, name: String = "", side: String? = nil, detail: String = "") {
        self.catalogID = catalogID; self.name = name; self.side = side; self.detail = detail
    }

    init(_ p: Procedure, side: String? = nil, detail: String = "") {
        catalogID = p.id; name = p.name; self.side = p.lateral ? side : nil; self.detail = detail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        catalogID = try? c.decodeIfPresent(String.self, forKey: .catalogID)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        side = try? c.decodeIfPresent(String.self, forKey: .side)
        detail = (try? c.decodeIfPresent(String.self, forKey: .detail)) ?? ""
    }

    var catalog: Procedure? { catalogID.flatMap { ProcedureCatalog.byID($0) } }
    /// The procedure has a side and none was picked.
    var needsSide: Bool { catalog?.needsSide(side) ?? false }

    /// "Left total knee arthroplasty", without the details.
    var title: String {
        if let p = catalog { return p.displayName(side: side) }
        guard let side, !side.isEmpty else { return name }
        return side.capitalized + " " + name.lowercasedFirst
    }

    /// "Coronary artery bypass grafting ×3".
    var text: String {
        let d = detail.trimmingCharacters(in: .whitespaces)
        return d.isEmpty ? title : title + " " + d
    }

    /// The planned procedures read from free text ("CABG x3 + AVR", "lap chole, possible open", "L TKA"). Words
    /// between procedures become the details of the one before ("×3", "possible open"); a procedure the patient is
    /// on or has had ("on VA ECMO", "s/p CABG") is kept as words, not planned. Words before the first procedure
    /// become a typed procedure of their own, and text the list does not know at all stays as typed.
    static func parse(_ text: String) -> [PlannedProcedure] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        let matches = ProcedureCatalog.parse(t)
            .filter { $0.range.upperBound <= t.endIndex }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
        var items: [PlannedProcedure] = []
        var lead: [String] = []
        var cursor = t.startIndex
        func attach(_ ws: [String]) {
            guard !ws.isEmpty else { return }
            if items.isEmpty { lead += ws; return }
            let d = items[items.count - 1].detail
            items[items.count - 1].detail = ((d.isEmpty ? [] : [d]) + ws).joined(separator: " ")
        }
        for m in matches where m.range.lowerBound >= cursor {
            let gap = words(t[cursor..<m.range.lowerBound])
            if let last = gap.last?.lowercased(), contextWords.contains(last) {
                attach(gap + [String(t[m.range])])
            } else {
                attach(gap)
                items.append(PlannedProcedure(m.procedure, side: m.side))
            }
            cursor = m.range.upperBound
        }
        attach(words(t[cursor...]))
        if items.isEmpty { return [PlannedProcedure(name: t)] }
        let typed = lead.joined(separator: " ")
        if typed.filter(\.isLetter).count >= 3 { items.insert(PlannedProcedure(name: typed), at: 0) }
        return items
    }

    /// A procedure after one of these is one the patient is on or has had.
    private static let contextWords: Set<String> = ["on", "s/p", "sp", "post", "h/o", "hx", "after", "prior", "previous"]
    /// Joining words and the urgency (recorded on its own) are dropped.
    private static let fillerWords: Set<String> = ["and", "with", "w/", "w", "plus", "then", "&", "+", "/", "-",
        "emergency", "emergent", "urgent", "elective", "stat", "planned", "scheduled", "for"]

    /// The words of a gap, without joining words, with a count written "×3".
    private static func words(_ s: Substring) -> [String] {
        let trim = CharacterSet(charactersIn: ",;:+&()").union(.whitespaces)
        var out: [String] = []
        for raw in s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            let w = String(raw).trimmingCharacters(in: trim)
            guard !w.isEmpty, !fillerWords.contains(w.lowercased()) else { continue }
            if let n = count(w) { out.append("×" + n) } else { out.append(w) }
        }
        // A "×" written apart from its number ("× 3").
        var merged: [String] = []
        for w in out {
            if let prev = merged.last, prev == "×" || prev == "x", w.allSatisfy(\.isNumber) { merged[merged.count - 1] = "×" + w } else { merged.append(w) }
        }
        return merged
    }

    /// "x3", "X3", "×3" → "3".
    private static func count(_ w: String) -> String? {
        guard let f = w.first, f == "x" || f == "X" || f == "×" else { return nil }
        let n = w.dropFirst()
        return !n.isEmpty && n.allSatisfy(\.isNumber) ? String(n) : nil
    }
}

extension PatientRecord {
    /// Replaces the planned procedures, keeps `procedure` (the joined text) in step and, when the recognized
    /// procedures or their sides change, fills the risk-score inputs from them. Typed procedures add nothing.
    mutating func setProcedures(_ list: [PlannedProcedure], fillAnesthetic: Bool = true) {
        func key(_ l: [PlannedProcedure]) -> [String] { l.compactMap { p in p.catalogID.map { $0 + "|" + (p.side ?? "") } } }
        let changed = key(procedures) != key(list) || procedures.isEmpty
        procedures = list
        procedure = list.map(\.text).filter { !$0.isEmpty }.joined(separator: " + ")
        // Typing a detail or a typed procedure's name keeps any input the clinician changed.
        let picked = list.compactMap { p in p.catalog.map { (procedure: $0, side: p.side) } }
        guard changed, !picked.isEmpty else { return }
        let risk = ProcedureCatalog.risk(picked: picked)
        if fillAnesthetic {
            risk.apply(to: &self)
        } else {
            highRiskSurgery = risk.highRisk
            incision = risk.incision
            duration = risk.duration
        }
    }

    /// The planned procedures the list recognizes: from the items, or read from the text in an older save.
    var recognizedProcedures: [Procedure] {
        procedures.isEmpty ? ProcedureCatalog.parse(procedure).map(\.procedure) : procedures.compactMap(\.catalog)
    }
}

/// One past operation: from the procedure list or typed, with the side and the month and year.
struct PatientSurgery: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = ""
    /// The procedure list's id when picked from it.
    var procedureID: String?
    /// "left", "right", "bilateral".
    var side: String?
    var date = PatientMonthYear()
    /// A cardiac or thoracic operation (a previous sternotomy or thoracotomy), for the cardiac evaluation.
    var intrathoracic = false

    init(name: String = "", procedureID: String? = nil, side: String? = nil, date: PatientMonthYear = PatientMonthYear(), intrathoracic: Bool = false) {
        self.name = name; self.procedureID = procedureID; self.side = side; self.date = date; self.intrathoracic = intrathoracic
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        procedureID = try? c.decodeIfPresent(String.self, forKey: .procedureID)
        side = try? c.decodeIfPresent(String.self, forKey: .side)
        date = (try? c.decodeIfPresent(PatientMonthYear.self, forKey: .date)) ?? PatientMonthYear()
        intrathoracic = (try? c.decodeIfPresent(Bool.self, forKey: .intrathoracic)) ?? false
    }

    /// "Left total knee arthroplasty (03/2019)".
    var text: String {
        let sided = side.map { s in (s == "bilateral" ? "Bilateral " : s.prefix(1).uppercased() + s.dropFirst() + " ") + name.lowercasedFirst } ?? name
        return date.isEmpty ? sided : sided + " (" + date.text + ")"
    }
}

extension String {
    /// "Total knee" → "total knee", keeping acronyms ("CABG", "TAVR") as written.
    var lowercasedFirst: String {
        guard let f = first else { return self }
        let second = dropFirst().first
        if let s = second, s.isUppercase { return self }
        return f.lowercased() + dropFirst()
    }
}

/// Grades for chamber function and valve lesions, as the ASE tools name them.
enum EchoGrade: String, Codable, CaseIterable, Hashable {
    case normal, mild, moderate, severe
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// One valve: regurgitation and stenosis grades (nil = not recorded; .normal = none) and any prosthesis or repair.
struct EchoValve: Codable, Hashable {
    var regurgitation: EchoGrade?
    var stenosis: EchoGrade?
    /// "Mechanical", "Bioprosthetic", "Repair or ring", "Transcatheter" (TAVR or TEER), or free text.
    var prosthesis = ""

    init(regurgitation: EchoGrade? = nil, stenosis: EchoGrade? = nil, prosthesis: String = "") {
        self.regurgitation = regurgitation; self.stenosis = stenosis; self.prosthesis = prosthesis
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        regurgitation = try? c.decodeIfPresent(EchoGrade.self, forKey: .regurgitation)
        stenosis = try? c.decodeIfPresent(EchoGrade.self, forKey: .stenosis)
        prosthesis = (try? c.decodeIfPresent(String.self, forKey: .prosthesis)) ?? ""
    }
    var isEmpty: Bool { regurgitation == nil && stenosis == nil && prosthesis.isEmpty }

    static let prostheses = ["Mechanical", "Bioprosthetic", "Repair or ring", "Transcatheter"]
}

/// Echo findings in the order of a report: LV, RV, mitral, tricuspid, aortic valve, aorta, other.
struct PatientEcho: Codable, Hashable {
    var lv: EchoGrade?
    var lvef: Double?
    var rv: EchoGrade?
    var mitral = EchoValve()
    var tricuspid = EchoValve()
    var aortic = EchoValve()
    /// true: intact; false: see `aorta`.
    var aortaIntact: Bool?
    var aorta = ""
    var other = ""
    /// "TTE" or "TEE".
    var study: String?
    var date = PatientMonthYear()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lv = try? c.decodeIfPresent(EchoGrade.self, forKey: .lv)
        lvef = try? c.decodeIfPresent(Double.self, forKey: .lvef)
        rv = try? c.decodeIfPresent(EchoGrade.self, forKey: .rv)
        mitral = (try? c.decodeIfPresent(EchoValve.self, forKey: .mitral)) ?? EchoValve()
        tricuspid = (try? c.decodeIfPresent(EchoValve.self, forKey: .tricuspid)) ?? EchoValve()
        aortic = (try? c.decodeIfPresent(EchoValve.self, forKey: .aortic)) ?? EchoValve()
        aortaIntact = try? c.decodeIfPresent(Bool.self, forKey: .aortaIntact)
        aorta = (try? c.decodeIfPresent(String.self, forKey: .aorta)) ?? ""
        other = (try? c.decodeIfPresent(String.self, forKey: .other)) ?? ""
        study = try? c.decodeIfPresent(String.self, forKey: .study)
        date = (try? c.decodeIfPresent(PatientMonthYear.self, forKey: .date)) ?? PatientMonthYear()
    }

    var isEmpty: Bool { self == PatientEcho() }

    /// Function words for a chamber grade: "normal", "mildly reduced"…
    static func function(_ g: EchoGrade) -> String {
        switch g {
        case .normal: return "normal"
        case .mild: return "mildly reduced"
        case .moderate: return "moderately reduced"
        case .severe: return "severely reduced"
        }
    }

    /// The findings as short phrases, in report order: "LV EF 35%, moderately reduced", "Severe AS", "Mitral repair".
    var phrases: [String] {
        var out: [String] = []
        if lv != nil || lvef != nil {
            var s = "LV"
            if let ef = lvef { s += " EF " + NumText.short(ef) + "%" }
            if let g = lv { s += (lvef == nil ? " function " : ", ") + PatientEcho.function(g) }
            out.append(s)
        }
        if let g = rv { out.append("RV function " + PatientEcho.function(g)) }
        func valve(_ v: EchoValve, _ letter: String, _ name: String) {
            if let g = v.stenosis, g != .normal { out.append(g.label + " " + letter + "S") }
            if let g = v.regurgitation, g != .normal { out.append(g.label + " " + letter + "R") }
            if !v.prosthesis.isEmpty { out.append(name + " " + v.prosthesis.lowercasedFirst) }
        }
        valve(mitral, "M", "Mitral")
        valve(tricuspid, "T", "Tricuspid")
        valve(aortic, "A", "Aortic")
        if aortaIntact == true { out.append("Aorta intact") }
        if aortaIntact == false || !aorta.isEmpty { out.append(aorta.isEmpty ? "Aorta abnormal" : "Aorta: " + aorta) }
        if !other.isEmpty { out.append(other) }
        return out
    }

    /// "TTE 03/2026: LV EF 55%, normal; moderate MR".
    var summary: String {
        let head = [study, date.isEmpty ? nil : date.text].compactMap { $0 }.joined(separator: " ")
        let body = phrases.joined(separator: "; ")
        if body.isEmpty { return head }
        return head.isEmpty ? body : head + ": " + body
    }
}

/// Left heart catheterization: dominance and the worst stenosis in each vessel.
struct PatientLHC: Codable, Hashable {
    /// "right", "left", "codominant".
    var dominance: String?
    /// Percent stenosis by vessel id ("lm", "lad", "lcx", "rca", "pda").
    var stenosis: [String: Double] = [:]
    var notes = ""
    var date = PatientMonthYear()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dominance = try? c.decodeIfPresent(String.self, forKey: .dominance)
        stenosis = (try? c.decodeIfPresent([String: Double].self, forKey: .stenosis)) ?? [:]
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        date = (try? c.decodeIfPresent(PatientMonthYear.self, forKey: .date)) ?? PatientMonthYear()
    }

    static let vessels: [(id: String, label: String)] = [("lm", "LM"), ("lad", "LAD"), ("lcx", "LCx"), ("rca", "RCA"), ("pda", "PDA")]

    var isEmpty: Bool { self == PatientLHC() }

    /// "LHC 05/2026, right dominant: LAD 90%, RCA 70%; LM, LCx, PDA no significant disease".
    var summary: String {
        var head = "LHC"
        if !date.isEmpty { head += " " + date.text }
        if let d = dominance { head += ", " + (d == "codominant" ? "codominant" : d + " dominant") }
        let named = PatientLHC.vessels.filter { stenosis[$0.id] != nil }
        let severe = named.filter { (stenosis[$0.id] ?? 0) >= 50 }.map { "\($0.label) \(NumText.short(stenosis[$0.id] ?? 0))%" }
        let mild = named.filter { (stenosis[$0.id] ?? 0) < 50 }
        var parts: [String] = []
        if !severe.isEmpty { parts.append(severe.joined(separator: ", ")) }
        if !mild.isEmpty { parts.append(mild.map { "\($0.label) \(NumText.short(stenosis[$0.id] ?? 0))%" }.joined(separator: ", ")) }
        if !notes.isEmpty { parts.append(notes) }
        return parts.isEmpty ? head : head + ": " + parts.joined(separator: "; ")
    }
}

/// Right heart catheterization: the measured pressures (mmHg) and cardiac output (L/min).
struct PatientRHC: Codable, Hashable {
    var ra: Double?
    var pasp: Double?
    var padp: Double?
    /// Measured mean PA pressure, when given; otherwise it is estimated.
    var pam: Double?
    var pcwp: Double?
    var co: Double?
    var date = PatientMonthYear()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ra = try? c.decodeIfPresent(Double.self, forKey: .ra)
        pasp = try? c.decodeIfPresent(Double.self, forKey: .pasp)
        padp = try? c.decodeIfPresent(Double.self, forKey: .padp)
        pam = try? c.decodeIfPresent(Double.self, forKey: .pam)
        pcwp = try? c.decodeIfPresent(Double.self, forKey: .pcwp)
        co = try? c.decodeIfPresent(Double.self, forKey: .co)
        date = (try? c.decodeIfPresent(PatientMonthYear.self, forKey: .date)) ?? PatientMonthYear()
    }

    var isEmpty: Bool { self == PatientRHC() }
}

/// Ventilator settings, for a patient who arrives intubated or on a tracheostomy.
struct PatientVent: Codable, Hashable {
    /// "AC/VC", "AC/PC", "PRVC", "SIMV", "PSV", "APRV", or free text.
    var mode = ""
    var vt: Double?
    var rr: Double?
    var peep: Double?
    var fio2: Double?
    var ps: Double?

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? ""
        vt = try? c.decodeIfPresent(Double.self, forKey: .vt)
        rr = try? c.decodeIfPresent(Double.self, forKey: .rr)
        peep = try? c.decodeIfPresent(Double.self, forKey: .peep)
        fio2 = try? c.decodeIfPresent(Double.self, forKey: .fio2)
        ps = try? c.decodeIfPresent(Double.self, forKey: .ps)
    }

    var isEmpty: Bool { self == PatientVent() }
    static let modes = ["AC/VC", "AC/PC", "PRVC", "SIMV", "PSV", "APRV"]

    /// "AC/VC 450 × 16, PEEP 8, FiO₂ 40%".
    var text: String {
        var parts: [String] = []
        var head = mode
        if let v = vt { head += (head.isEmpty ? "" : " ") + NumText.short(v) + (rr.map { " × " + NumText.short($0) } ?? "") }
        else if let r = rr { head += (head.isEmpty ? "" : " ") + "rate " + NumText.short(r) }
        if !head.isEmpty { parts.append(head) }
        if let p = ps { parts.append("PS " + NumText.short(p)) }
        if let p = peep { parts.append("PEEP " + NumText.short(p)) }
        if let f = fio2 { parts.append("FiO₂ " + NumText.short(f) + "%") }
        return parts.joined(separator: ", ")
    }
}

/// Supplemental oxygen for a patient breathing on their own (or on a trach collar).
struct PatientOxygen: Codable, Hashable {
    /// "ra" room air, "nc" nasal cannula, "mask", "venturi", "nrb" non-rebreather, "hfnc" high-flow, "niv" CPAP or
    /// BiPAP, "trachCollar".
    var device: String?
    var flow: Double?
    var fio2: Double?

    init(device: String? = nil, flow: Double? = nil, fio2: Double? = nil) { self.device = device; self.flow = flow; self.fio2 = fio2 }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        device = try? c.decodeIfPresent(String.self, forKey: .device)
        flow = try? c.decodeIfPresent(Double.self, forKey: .flow)
        fio2 = try? c.decodeIfPresent(Double.self, forKey: .fio2)
    }

    static let devices: [(id: String, label: String)] = [("ra", "Room air"), ("nc", "Nasal cannula"), ("mask", "Face mask"), ("venturi", "Venturi"),
                                                         ("nrb", "Non-rebreather"), ("hfnc", "High-flow nasal"), ("niv", "CPAP or BiPAP"), ("trachCollar", "Trach collar")]
    /// Devices that take a flow, and those that take an FiO₂.
    static let flowDevices: Set<String> = ["nc", "mask", "nrb", "hfnc", "trachCollar", "venturi"]
    static let fio2Devices: Set<String> = ["venturi", "hfnc", "niv", "trachCollar"]

    var isEmpty: Bool { device == nil && flow == nil && fio2 == nil }

    /// "Nasal cannula 2 L/min", "High-flow nasal 40 L/min, FiO₂ 50%", "Room air".
    var text: String {
        guard let d = device else { return "" }
        let name = PatientOxygen.devices.first { $0.id == d }?.label ?? d
        var parts = [name + (flow.map { " " + NumText.short($0) + " L/min" } ?? "")]
        if let f = fio2 { parts.append("FiO₂ " + NumText.short(f) + "%") }
        return parts.joined(separator: ", ")
    }
}

/// ECG findings offered on the typeable list; anything else is typed in.
enum PatientECG {
    static let findings = [
        "Normal sinus rhythm", "Sinus bradycardia", "Sinus tachycardia", "Atrial fibrillation", "Atrial flutter", "SVT",
        "Paced rhythm (atrial)", "Paced rhythm (ventricular)", "Paced rhythm (AV)", "First-degree AV block", "Mobitz I (Wenckebach)",
        "Mobitz II", "Complete heart block", "Right bundle branch block", "Left bundle branch block", "Left anterior fascicular block",
        "Bifascicular block", "Left ventricular hypertrophy", "Right ventricular hypertrophy", "Q waves (old infarct)",
        "ST depression", "ST elevation", "T-wave inversion", "Prolonged QTc", "Short PR (pre-excitation)", "PVCs", "PACs",
        "Nonspecific ST-T changes", "Low voltage", "Right axis deviation", "Left axis deviation",
    ]
}

// MARK: - From the ASE tools

extension EchoGrade {
    init(_ g: ValveGrade) {
        switch g {
        case .mild: self = .mild
        case .moderate: self = .moderate
        case .severe: self = .severe
        }
    }

    /// The chamber tool's grade (EchoCalc.grade): -1 and 0 normal, 1–3 mild to severe; nil for "abnormal" with one
    /// cutoff, which names no severity.
    init?(chamber g: Int) {
        switch g {
        case -1, 0: self = .normal
        case 1: self = .mild
        case 2: self = .moderate
        case 3: self = .severe
        default: return nil
        }
    }
}

extension PatientEcho {
    /// A grade from the ASE valve severity tool, written into the matching valve.
    mutating func apply(_ lesion: ValveLesion, _ grade: ValveGrade) {
        let g = EchoGrade(grade)
        switch lesion {
        case .as_: aortic.stenosis = g
        case .ar: aortic.regurgitation = g
        case .mr: mitral.regurgitation = g
        case .ms: mitral.stenosis = g
        case .tr: tricuspid.regurgitation = g
        }
    }

    func grade(for lesion: ValveLesion) -> EchoGrade? {
        switch lesion {
        case .as_: return aortic.stenosis
        case .ar: return aortic.regurgitation
        case .mr: return mitral.regurgitation
        case .ms: return mitral.stenosis
        case .tr: return tricuspid.regurgitation
        }
    }
}

// MARK: - Device groups

extension PatientDevice {
    static let lineKinds: Set<DeviceKind> = [.piv, .arterial, .cvc, .pac, .picc, .intraosseous, .other]
    static let supportKinds: Set<DeviceKind> = [.ecmoDrainage, .ecmoReturn, .lvad, .iabp, .impella]
}
