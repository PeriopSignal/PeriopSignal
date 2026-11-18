import Foundation

// MARK: - What a cardiopulmonary finding says, how it compares with the record, and what it writes
//
// The chip's words, its status against what the study already holds ("already recorded" for the same value, "replaces ..." for
// a different one: never a silent overwrite) and the write itself, which sets exactly the one field of the existing study and
// nothing else (PatientEcho, PatientLHC, PatientRHC, PatientPFT, PatientChestXray, PatientCarotid, PatientRadial). No stored field
// is added or renamed.

extension CardioText {
    // MARK: Words

    private static func word(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    private static func functionWords(_ v: String) -> String {
        guard let g = EchoGrade(rawValue: v) else { return v }
        return PatientEcho.function(g)
    }

    /// The side a field of a carotid or radial study is on, and the field after it: "right.stenosis" is ("right", "stenosis").
    private static func sided(_ field: String) -> (side: String, name: String) {
        let parts = field.components(separatedBy: ".")
        if parts.count == 2 { return (side: parts[0], name: parts[1]) }
        return (side: "", name: field)
    }

    /// The chip's words for a finding: "EF 35%", "RV function normal", "LAD 90%", "PCWP 18 mmHg", "FEV1 62%", "small left effusion",
    /// "Right ICA ≥70%".
    static func valueText(_ c: CardioFinding) -> String {
        let f = c.field
        let v = c.value
        if f == "date" { return "Date " + v }
        switch c.study {
        case .echo:
            switch f {
            case "study": return v
            case "lvef": return "EF " + v + "%"
            case "lv": return "LV function " + functionWords(v)
            case "rv": return "RV function " + functionWords(v)
            case "lvSize": return "LV size " + v
            case "rvSize": return "RV size " + v
            case "aorta": return "Aorta intact"
            default: return f + " " + v
            }
        case .lhc:
            if f == "dominance" { return v == "codominant" ? "Codominant" : word(v) + " dominant" }
            if f.hasPrefix("stenosis.") {
                let id = String(f.dropFirst("stenosis.".count))
                let label = PatientLHC.vessels.first { $0.id == id }?.label ?? id.uppercased()
                return label + " " + v + "%"
            }
            return f + " " + v
        case .rhc:
            switch f {
            case "ra": return "RA " + v + " mmHg"
            case "pasp": return "PA systolic " + v + " mmHg"
            case "padp": return "PA diastolic " + v + " mmHg"
            case "pam": return "PA mean " + v + " mmHg"
            case "pcwp": return "PCWP " + v + " mmHg"
            case "co": return "CO " + v + " L/min"
            default: return f + " " + v
            }
        case .pft:
            switch f {
            case "fev1": return "FEV1 " + v + " L"
            case "fev1Pct": return "FEV1 " + v + "% predicted"
            case "fvc": return "FVC " + v + " L"
            case "fvcPct": return "FVC " + v + "% predicted"
            case "ratio": return "FEV1/FVC " + v + ((Double(v) ?? 0) > 1 ? "%" : "")
            case "tlcPct": return "TLC " + v + "%"
            case "dlcoPct": return "DLCO " + v + "%"
            case "pattern": return "Pattern " + (PatientPFT.patterns.first { $0.id == v }?.label.lowercased() ?? v)
            case "severity": return "Severity " + v
            default: return f + " " + v
            }
        case .cxr:
            switch f {
            case "result": return "Normal"
            case "effusion":
                let parts = v.components(separatedBy: ",")
                var words: [String] = []
                if parts.count == 2 {
                    if parts[1] != "-" { words.append(parts[1]) }
                    if parts[0] != "-" { words.append(parts[0]) }
                }
                words.append("effusion")
                return words.joined(separator: " ")
            default: return "Findings: " + v
            }
        case .carotid:
            let s = sided(f)
            let side = word(s.side)
            switch s.name {
            case "stenosis": return side + " ICA " + (v == "normal" ? "no stenosis" : (CarotidSide.stenosisLabel(v) ?? v))
            case "vertebral": return side + " vertebral " + (CarotidSide.vertebralLabel(v)?.lowercased() ?? v)
            case "psv": return side + " PSV " + v + " cm/s"
            case "edv": return side + " EDV " + v + " cm/s"
            default: return f + " " + v
            }
        case .radial:
            if f == "harvest" { return v == "none" ? "No harvest planned" : "Planned " + v + " harvest" }
            let s = sided(f)
            let side = word(s.side)
            switch s.name {
            case "diameter": return side + " radial " + v + " mm"
            case "calcified": return side + " radial " + (v == "true" ? "calcified" : "not calcified")
            case "ulnar": return side + " ulnar compensation " + v
            default: return f + " " + v
            }
        }
    }

    // MARK: Status

    private static func sameNumber(_ a: Double, _ b: Double) -> Bool { Swift.abs(a - b) < 0.005 }

    /// New where the field is empty, already recorded for the same value, else what it replaces.
    private static func numberStatus(_ old: Double?, _ new: String, _ shown: (Double) -> String) -> PatientNoteStatus {
        guard let o = old else { return .new }
        guard let n = Double(new) else { return .new }
        return sameNumber(o, n) ? .recorded : .replaces(shown(o))
    }

    private static func textStatus(_ old: String?, _ new: String, _ shown: (String) -> String) -> PatientNoteStatus {
        guard let o = old, !o.isEmpty else { return .new }
        return o == new ? .recorded : .replaces(shown(o))
    }

    /// A date: new where none is recorded; recorded where the typed one is the recorded date or says no more than it does (a year
    /// for a month and year); a fuller date that agrees adds its detail; a date that disagrees replaces the recorded one.
    private static func dateStatus(_ old: PatientMonthYear, _ new: String) -> PatientNoteStatus {
        guard let n = PatientMonthYear.parse(new) else { return .new }
        if old.isEmpty { return .new }
        if PatientMonthYear.compatible(old, n) {
            return PatientMonthYear.fuller(old, n) == old ? .recorded : .new
        }
        return .replaces(old.text)
    }

    static func status(_ c: CardioFinding, in r: PatientRecord) -> PatientNoteStatus {
        let f = c.field
        let v = c.value
        if f == "date" {
            switch c.study {
            case .echo: return dateStatus(r.echoFindings.date, v)
            case .lhc: return dateStatus(r.lhc.date, v)
            case .rhc: return dateStatus(r.rhc.date, v)
            case .pft: return dateStatus(r.pft.date, v)
            case .carotid: return dateStatus(r.carotid.date, v)
            case .radial: return dateStatus(r.radial.date, v)
            case .cxr: return .new
            }
        }
        switch c.study {
        case .echo:
            let e = r.echoFindings
            switch f {
            case "study": return textStatus(e.study, v) { $0 }
            case "lvef": return numberStatus(e.lvef, v) { NumText.short($0) + "%" }
            case "lv": return textStatus(e.lv?.rawValue, v) { functionWords($0) }
            case "rv": return textStatus(e.rv?.rawValue, v) { functionWords($0) }
            case "lvSize": return textStatus(e.lvSize?.rawValue, v) { $0 }
            case "rvSize": return textStatus(e.rvSize?.rawValue, v) { $0 }
            case "aorta":
                guard let o = e.aortaIntact else { return .new }
                return o ? .recorded : .replaces("aorta abnormal")
            default: return .new
            }
        case .lhc:
            if f == "dominance" { return textStatus(r.lhc.dominance, v) { $0 } }
            let id = String(f.dropFirst("stenosis.".count))
            return numberStatus(r.lhc.stenosis[id], v) { NumText.short($0) + "%" }
        case .rhc:
            let x = r.rhc
            let pick: Double?
            switch f {
            case "ra": pick = x.ra
            case "pasp": pick = x.pasp
            case "padp": pick = x.padp
            case "pam": pick = x.pam
            case "pcwp": pick = x.pcwp
            default: pick = x.co
            }
            return numberStatus(pick, v) { NumText.short($0) }
        case .pft:
            let x = r.pft
            switch f {
            case "fev1": return numberStatus(x.fev1, v) { NumText.short($0) + " L" }
            case "fev1Pct": return numberStatus(x.fev1Pct, v) { NumText.short($0) + "%" }
            case "fvc": return numberStatus(x.fvc, v) { NumText.short($0) + " L" }
            case "fvcPct": return numberStatus(x.fvcPct, v) { NumText.short($0) + "%" }
            case "ratio": return numberStatus(x.ratioTyped, v) { NumText.short($0) }
            case "tlcPct": return numberStatus(x.tlcPct, v) { NumText.short($0) + "%" }
            case "dlcoPct": return numberStatus(x.dlcoPct, v) { NumText.short($0) + "%" }
            case "pattern": return textStatus(x.pattern, v) { id in PatientPFT.patterns.first { $0.id == id }?.label.lowercased() ?? id }
            default: return textStatus(x.severity, v) { $0 }
            }
        case .cxr:
            return cxrStatus(f, v, r.chestXray)
        case .carotid:
            let s = sided(f)
            let side = s.side == "right" ? r.carotid.right : r.carotid.left
            switch s.name {
            case "stenosis": return textStatus(side.stenosis, v) { CarotidSide.stenosisLabel($0) ?? $0 }
            case "vertebral": return textStatus(side.vertebral, v) { CarotidSide.vertebralLabel($0)?.lowercased() ?? $0 }
            case "psv": return numberStatus(side.psv, v) { NumText.short($0) + " cm/s" }
            default: return numberStatus(side.edv, v) { NumText.short($0) + " cm/s" }
            }
        case .radial:
            if f == "harvest" { return textStatus(r.radial.harvest, v) { $0 } }
            let s = sided(f)
            let side = s.side == "right" ? r.radial.right : r.radial.left
            switch s.name {
            case "diameter": return numberStatus(side.diameter, v) { NumText.short($0) + " mm" }
            case "calcified":
                guard let o = side.calcified else { return .new }
                return o == (v == "true") ? .recorded : .replaces(o ? "calcified" : "not calcified")
            default: return textStatus(side.ulnar, v) { $0 }
            }
        }
    }

    private static func cxrStatus(_ f: String, _ v: String, _ x: PatientChestXray) -> PatientNoteStatus {
        switch f {
        case "result":
            guard let o = x.result else { return .new }
            if o == .normal { return .recorded }
            return .replaces(x.effusionText ?? "effusion")
        case "effusion":
            let parts = v.components(separatedBy: ",")
            let side = parts.count == 2 && parts[0] != "-" ? parts[0] : nil
            let size = parts.count == 2 && parts[1] != "-" ? parts[1] : nil
            guard let o = x.result else { return .new }
            if o == .normal { return .replaces("normal") }
            let sideClash = side != nil && x.side != nil && x.side?.rawValue != side
            let sizeClash = size != nil && x.size != nil && x.size?.rawValue != size
            if sideClash || sizeClash { return .replaces(x.effusionText ?? "effusion") }
            let addsSide = side != nil && x.side == nil
            let addsSize = size != nil && x.size == nil
            return addsSide || addsSize ? .new : .recorded
        default:
            let old = x.findings.trimmingCharacters(in: .whitespacesAndNewlines)
            if old.isEmpty { return .new }
            return old.localizedCaseInsensitiveContains(v) ? .recorded : .new
        }
    }

    // MARK: Apply

    private static func joined(_ old: String, _ new: String) -> String {
        let n = new.trimmingCharacters(in: .whitespacesAndNewlines)
        let o = old.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || o.localizedCaseInsensitiveContains(n) { return old }
        return o.isEmpty ? n : o + "; " + n
    }

    private static func merged(_ old: PatientMonthYear, _ new: String) -> PatientMonthYear {
        guard let n = PatientMonthYear.parse(new) else { return old }
        if PatientMonthYear.compatible(old, n) { return PatientMonthYear.fuller(old, n) }
        return n
    }

    /// Writes the one field the finding names, and nothing else.
    static func apply(_ c: CardioFinding, to r: inout PatientRecord) {
        let f = c.field
        let v = c.value
        if f == "date" {
            switch c.study {
            case .echo: r.echoFindings.date = merged(r.echoFindings.date, v)
            case .lhc: r.lhc.date = merged(r.lhc.date, v)
            case .rhc: r.rhc.date = merged(r.rhc.date, v)
            case .pft: r.pft.date = merged(r.pft.date, v)
            case .carotid: r.carotid.date = merged(r.carotid.date, v)
            case .radial: r.radial.date = merged(r.radial.date, v)
            case .cxr: break
            }
            return
        }
        let d: Double? = Double(v)
        switch c.study {
        case .echo:
            switch f {
            case "study": r.echoFindings.study = v
            case "lvef": r.echoFindings.lvef = d
            case "lv": r.echoFindings.lv = EchoGrade(rawValue: v)
            case "rv": r.echoFindings.rv = EchoGrade(rawValue: v)
            case "lvSize": r.echoFindings.lvSize = EchoSize(rawValue: v)
            case "rvSize": r.echoFindings.rvSize = EchoSize(rawValue: v)
            case "aorta": r.echoFindings.aortaIntact = true
            default: break
            }
        case .lhc:
            if f == "dominance" {
                r.lhc.dominance = v
            } else if let value = d {
                r.lhc.stenosis[String(f.dropFirst("stenosis.".count))] = value
            }
        case .rhc:
            switch f {
            case "ra": r.rhc.ra = d
            case "pasp": r.rhc.pasp = d
            case "padp": r.rhc.padp = d
            case "pam": r.rhc.pam = d
            case "pcwp": r.rhc.pcwp = d
            default: r.rhc.co = d
            }
        case .pft:
            switch f {
            case "fev1": r.pft.fev1 = d
            case "fev1Pct": r.pft.fev1Pct = d
            case "fvc": r.pft.fvc = d
            case "fvcPct": r.pft.fvcPct = d
            case "ratio": r.pft.ratioTyped = d
            case "tlcPct": r.pft.tlcPct = d
            case "dlcoPct": r.pft.dlcoPct = d
            case "pattern": r.pft.pattern = v
            default: r.pft.severity = v
            }
        case .cxr:
            switch f {
            case "result": r.chestXray.choose(.normal)
            case "effusion":
                let parts = v.components(separatedBy: ",")
                let side: PatientChestXray.Side? = parts.count == 2 ? PatientChestXray.Side(rawValue: parts[0]) : nil
                let size: PatientChestXray.Size? = parts.count == 2 ? PatientChestXray.Size(rawValue: parts[1]) : nil
                let sameKind = r.chestXray.result == .effusion
                r.chestXray.choose(.effusion)
                if let s = side { r.chestXray.side = s } else if !sameKind { r.chestXray.side = nil }
                if let z = size { r.chestXray.size = z } else if !sameKind { r.chestXray.size = nil }
            default: r.chestXray.findings = joined(r.chestXray.findings, v)
            }
        case .carotid:
            let s = sided(f)
            var side = s.side == "right" ? r.carotid.right : r.carotid.left
            switch s.name {
            case "stenosis": side.stenosis = v
            case "vertebral": side.vertebral = v
            case "psv": side.psv = d
            default: side.edv = d
            }
            if s.side == "right" { r.carotid.right = side } else { r.carotid.left = side }
        case .radial:
            if f == "harvest" {
                r.radial.harvest = v
                return
            }
            let s = sided(f)
            var side = s.side == "right" ? r.radial.right : r.radial.left
            switch s.name {
            case "diameter": side.diameter = d
            case "calcified": side.calcified = v == "true"
            default: side.ulnar = v
            }
            if s.side == "right" { r.radial.right = side } else { r.radial.left = side }
        }
    }
}
