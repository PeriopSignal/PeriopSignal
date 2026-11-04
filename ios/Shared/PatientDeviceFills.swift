import Foundation
import CoreGraphics

// MARK: - The history on the diagram (1.9)
//
// Entries on the system pages that are devices or access in the patient: a dialysis fistula or catheter with its typed
// location (Renal), a chest tube in place (Respiratory), an implanted pacemaker or ICD (Cardiovascular). Each is
// drawn on the diagram while its source holds, as a fill (PatientCrossFill): added once, remembered by its source's
// key in PatientRecord.fills.devices, and taken off only if it is still there when the source goes.
//
// The rules, per source key ("hd-fistula", "hd-catheter", "chest-tube-left", "chest-tube-right", "cied"):
//   - the source appears: a device is added (placed on arrival, not in the room) and remembered; a matching device the
//     user already drew is theirs, so nothing is added and nothing is remembered;
//   - the source's text changes (the fistula's location, the generator's side): the device follows it, its site and its
//     detail, unless the user changed that part themselves;
//   - the user deletes the device: it is not added again while the source holds;
//   - the source goes: the device is taken off if it is still the fill's, as the fill made it (the user having added a
//     size, settings, moved it or marked it removed makes it theirs), and the key is forgotten, so the source coming
//     back adds a device again.
// Every fill is a function of the record, not of one step, so a note, a quick-add line or an Undo that changes the source
// is followed the same way.

enum PatientDeviceFills {
    /// The source keys, in the order they are applied.
    static let keys = ["hd-fistula", "hd-catheter", "chest-tube-left", "chest-tube-right", "cied"]

    /// What a source asks the diagram to hold.
    struct Want: Equatable {
        var kind: DeviceKind
        /// A DeviceSite id, or "" when the text does not say where on the figure.
        var site: String
        var side: String?
        var detail: String
    }

    static func apply(before: PatientRecord, after r: inout PatientRecord) {
        let old = wants(before), new = wants(r)
        for key in keys {
            let want = new[key], was = old[key]
            if let want {
                if let id = r.fills.devices[key] {
                    // The user deleted it: leave it deleted until the source goes and comes back.
                    guard let i = r.devices.firstIndex(where: { $0.id == id }) else { continue }
                    if let was, was != want { follow(&r.devices[i], was: was, now: want) }
                } else if !alreadyDrawn(want, in: r.devices) {
                    let d = PatientDevice(kind: want.kind, site: want.site, side: want.side, detail: want.detail, placedIntraop: false)
                    r.devices.append(d)
                    r.fills.devices[key] = d.id
                }
            } else if let id = r.fills.devices[key] {
                r.fills.devices[key] = nil
                if let i = r.devices.firstIndex(where: { $0.id == id }), asFilled(r.devices[i], was: was) {
                    r.devices.remove(at: i)
                }
            }
        }
    }

    /// The device follows its source's new text: the site (and side) while it is still where the fill put it, the detail
    /// while it is still the fill's words.
    private static func follow(_ d: inout PatientDevice, was: Want, now: Want) {
        if d.site == was.site && d.side == was.side {
            if d.site != now.site { d.offset = nil }
            d.site = now.site
            d.side = now.side
        }
        if d.detail == was.detail { d.detail = now.detail }
    }

    /// The device is as the fill made it: nothing added by the user, and (when the fill's earlier wording is known) the
    /// site and detail still its own.
    private static func asFilled(_ d: PatientDevice, was: Want?) -> Bool {
        guard !d.removed, !d.placedIntraop, d.size.isEmpty, d.settings.isEmpty, d.offset == nil else { return false }
        guard let was else { return true }
        return d.site == was.site && d.side == was.side && d.detail == was.detail
    }

    /// The user already drew this (same kind, same place): theirs. A generator counts whatever its site.
    private static func alreadyDrawn(_ w: Want, in devices: [PatientDevice]) -> Bool {
        devices.contains { d in
            guard d.kind == w.kind, !d.removed else { return false }
            return w.kind == .cied || (d.site == w.site && d.side == w.side)
        }
    }

    // MARK: The sources

    static func wants(_ r: PatientRecord) -> [String: Want] {
        var out: [String: Want] = [:]
        let access = r.hx.dialysisAccess
        if access.contains("fistula") { out["hd-fistula"] = accessWant(.avFistula, r.hx.fistulaSite) }
        if access.contains("catheter") { out["hd-catheter"] = accessWant(.dialysisCatheter, r.hx.dialysisCatheterSite) }
        if r.hx.chestTube == true {
            for side in ["left", "right"] where r.hx.chestTubeSides.contains(side) {
                out["chest-tube-" + side] = Want(kind: .chestTube, site: DeviceSite.find("lateral-chest", side: side)?.id ?? "", side: side, detail: "")
            }
        }
        if r.problems.contains("pacemaker") || r.problems.contains("icd") {
            let side = r.hx.ciedSide.flatMap { $0 == "left" || $0 == "right" ? $0 : nil }
            out["cied"] = Want(kind: .cied, site: side.flatMap { DeviceSite.find("generator", side: $0)?.id } ?? "", side: side, detail: ciedType(r))
        }
        return out
    }

    private static func accessWant(_ kind: DeviceKind, _ text: String) -> Want {
        let read = readAccessSite(text, kind: kind)
        return Want(kind: kind, site: read.site, side: read.side, detail: read.detail)
    }

    /// "pacemaker", "ICD", "CRT-P" or "CRT-D": resynchronization read from the details the page keeps (hx.deviceDetails),
    /// an ICD with it being CRT-D and a pacemaker CRT-P; otherwise the ICD (which paces too) over the pacemaker.
    static func ciedType(_ r: PatientRecord) -> String {
        let icd = r.problems.contains("icd")
        let words = r.hx.deviceDetails.lowercased()
        let crtD = words.range(of: #"\bcrt-?d\b"#, options: .regularExpression) != nil
        let crtP = words.range(of: #"\bcrt-?p\b"#, options: .regularExpression) != nil
        let crt = words.range(of: #"\b(?:crt|biventricular|bi-?v|resynchroni[sz]ation)\b"#, options: .regularExpression) != nil
        if crtD { return "CRT-D" }
        if crtP { return "CRT-P" }
        if crt { return icd ? "CRT-D" : "CRT-P" }
        return icd ? "ICD" : "pacemaker"
    }

    // MARK: Reading a typed location

    /// Where a typed access location is: a DeviceSite id ("" when the words do not say), its side, and the rest of the
    /// words as the device's detail.
    struct AccessSite: Equatable {
        var site: String
        var side: String?
        var detail: String
    }

    /// Reads "left forearm", "LUE", "L upper arm", "R arm", "brachiocephalic L", "radiocephalic right", "left wrist",
    /// "right IJ tunneled", "R femoral", "left subclavian", "RIJ permcath".
    ///
    /// - Fistula or graft (`.avFistula`): wrist (also "hand", "snuffbox"), forearm, upper arm (also "elbow",
    ///   "antecubital", "brachial", "axillary") or thigh; the access types name their place: radiocephalic is the wrist,
    ///   brachiocephalic and brachiobasilic the upper arm. "Arm", "LUE" and "upper extremity" alone mean the forearm,
    ///   where most are made, and "leg", "LE" and "groin" the thigh. The type goes to the detail ("radiocephalic",
    ///   "AV graft").
    /// - Catheter (`.dialysisCatheter`): IJ (also "jugular", "neck"), subclavian, femoral (also "groin"). Tunneling goes
    ///   to the detail ("tunneled" for tunneled, permcath and permacath; "non-tunneled" for temporary).
    /// - Words not understood join the detail. When no place can be drawn (no place named, or a place with no side), the
    ///   site is "" (the model's "no place on the figure yet") and the whole typed text is the detail.
    static func readAccessSite(_ text: String, kind: DeviceKind) -> AccessSite {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return AccessSite(site: "", side: nil, detail: "") }
        var s = typed.lowercased().replacingOccurrences(of: "tunnelled", with: "tunneled")
        s = s.replacingOccurrences(of: #"\b(brachio|radio|non)[ \-]+(?=[a-z])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b(upper|lower) (arm|extremity|limb)\b"#, with: "$1$2", options: .regularExpression)
        let words = s.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)

        var side: String?
        var base: String?
        var details: [String] = []
        var rest: [String] = []
        func setSide(_ x: String) { if side == nil { side = x } }
        func setBase(_ b: String) { if base == nil { base = b } }
        func addDetail(_ d: String) { if !details.contains(d) { details.append(d) } }
        let ignored: Set<String> = ["in", "the", "of", "a", "an", "and", "at", "on", "side", "site", "vein", "av", "arteriovenous", "access",
                                    "fistula", "avf", "catheter", "cath", "line", "hd", "dialysis", "hemodialysis", "permanent"]
        let fistula = kind == .avFistula
        for w in words {
            switch w {
            case "left", "l", "lt": setSide("left")
            case "right", "r", "rt": setSide("right")
            // A side run into its place: RIJ, LSC, RFV, LUE.
            case "rij", "rijv": setSide("right"); setBase("ij")
            case "lij", "lijv": setSide("left"); setBase("ij")
            case "rsc", "rscv": setSide("right"); setBase("subclavian")
            case "lsc", "lscv": setSide("left"); setBase("subclavian")
            case "rfv": setSide("right"); setBase("femoral-vein")
            case "lfv": setSide("left"); setBase("femoral-vein")
            case "rue": setSide("right"); setBase("arm")
            case "lue": setSide("left"); setBase("arm")
            case "rle": setSide("right"); setBase("leg")
            case "lle": setSide("left"); setBase("leg")
            case "rfa": if fistula { setSide("right"); setBase("forearm") } else { rest.append(w) }
            case "lfa": if fistula { setSide("left"); setBase("forearm") } else { rest.append(w) }
            case "wrist", "hand", "snuffbox": setBase("wrist")
            case "forearm", "fa": setBase("forearm")
            case "upperarm", "elbow", "antecubital", "ac", "acf", "brachial", "axillary", "axilla": setBase("upper-arm")
            case "arm", "ue", "upperextremity", "upperlimb": setBase("arm")
            case "thigh": setBase("thigh")
            case "leg", "le", "lowerextremity", "lowerlimb", "lowerarm": setBase(w == "lowerarm" ? "forearm" : "leg")
            case "groin": setBase("groin")
            case "femoral", "fem", "fv": setBase("femoral")
            case "ij", "ijv", "jugular", "neck": setBase("ij")
            case "internal": break
            case "subclavian", "subclav", "sc", "scv": setBase("subclavian")
            case "radiocephalic", "rcf", "brescia": setBase("wrist"); addDetail("radiocephalic")
            case "brachiocephalic", "bcf": setBase("upper-arm"); addDetail("brachiocephalic")
            case "brachiobasilic", "bbf", "basilic", "bvt": setBase("upper-arm"); addDetail("brachiobasilic")
            case "graft", "avg": addDetail("AV graft")
            case "tunneled", "perm", "permcath", "permacath": addDetail("tunneled")
            case "nontunneled", "temporary", "temp", "acute": addDetail("non-tunneled")
            case "trialysis": addDetail("Trialysis")
            case "quinton": addDetail("Quinton")
            case "mahurkar": addDetail("Mahurkar")
            case "vascath": addDetail("Vascath")
            default:
                if !ignored.contains(w) { rest.append(w) }
            }
        }
        // The place for this kind: arms and thigh for a fistula, the three veins for a catheter.
        var site: String?
        if let b = base {
            switch (fistula, b) {
            case (true, "upper-arm"), (true, "forearm"), (true, "wrist"), (true, "thigh"): site = b
            case (true, "arm"): site = "forearm"
            case (true, "leg"), (true, "groin"), (true, "femoral"): site = "thigh"
            case (false, "ij"), (false, "subclavian"), (false, "femoral-vein"): site = b
            case (false, "femoral"), (false, "groin"): site = "femoral-vein"
            default: site = nil
            }
        }
        if let b = site, let found = DeviceSite.find(b, side: side) {
            return AccessSite(site: found.id, side: found.side, detail: (details + rest).joined(separator: ", "))
        }
        return AccessSite(site: "", side: side, detail: typed)
    }

    // MARK: Limb alerts

    /// "arm-right", "arm-left", "leg-right", "leg-left" in the order they are listed.
    static let limbOrder: [String] = PatientLimbAlert.limbs.map { $0.id }

    /// A limb to spare and why, from an AV fistula or graft on the diagram (`automatic`) or from the user's list.
    struct LimbAlertItem: Hashable, Identifiable {
        var id: String
        var limb: String
        var reason: String
        var automatic: Bool
    }

    /// One limb with every reason it is to be spared.
    struct LimbAlertGroup: Hashable, Identifiable {
        var limb: String
        var reasons: [String]
        /// Some reason comes from a fistula or graft on the diagram.
        var automatic: Bool
        var id: String { limb }
        /// "L arm".
        var name: String { PatientDeviceFills.limbName(limb) }
        /// "L arm — AV fistula, prior axillary lymph node dissection".
        var text: String { name + " — " + reasons.joined(separator: ", ") }
    }

    /// "L arm", "R leg".
    static func limbName(_ limb: String) -> String {
        let parts = limb.split(separator: "-").map(String.init)
        guard parts.count == 2 else { return limb }
        return (parts[1] == "left" ? "L " : "R ") + parts[0]
    }

    /// "left arm", "right leg", for a sentence.
    static func limbWords(_ limb: String) -> String {
        let parts = limb.split(separator: "-").map(String.init)
        return parts.count == 2 ? parts[1] + " " + parts[0] : limb
    }

    /// The limb an AV fistula or graft puts a limb alert on, from its site's side and region (an arm, or a leg for the
    /// thigh); a fistula kept without a place but with a side is taken to be in the arm. nil with no side, for another
    /// kind, or removed.
    static func limb(of d: PatientDevice) -> String? {
        guard d.kind == .avFistula, !d.removed else { return nil }
        let info = d.siteInfo
        guard let side = info?.side ?? d.side, side == "left" || side == "right" else { return nil }
        return ((info?.region ?? "arm") == "leg" ? "leg-" : "arm-") + side
    }

    /// Every alert, computed from the record (the fistulas on the diagram first, then the user's, in the order typed):
    /// nothing is stored for the fistula's (`arrivalOnly`: the ones there on arrival, for the preoperative picture). A typed reason that says what a fistula already says for that limb (AV
    /// fistula, graft, AVF), or the same reason twice, is listed once; so is a reason that only says the arm is planned for
    /// the radial harvest, which the Arms line announces (PatientStudies.harvestReminder).
    static func limbAlerts(_ r: PatientRecord, arrivalOnly: Bool = false) -> [LimbAlertItem] {
        var out: [LimbAlertItem] = []
        for d in r.devices where !arrivalOnly || !d.placedIntraop {
            guard let limb = limb(of: d) else { continue }
            let reason = d.detail.range(of: "graft", options: .caseInsensitive) != nil ? "AV graft" : "AV fistula"
            if !out.contains(where: { $0.limb == limb && $0.reason == reason }) {
                out.append(LimbAlertItem(id: "auto-" + limb + "-" + reason, limb: limb, reason: reason, automatic: true))
            }
        }
        let harvestArms = Set(r.radial.harvestArms.map { "arm-" + $0 })
        for a in r.limbAlerts {
            let reason = a.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reason.isEmpty, limbOrder.contains(a.limb) else { continue }
            let key = reason.lowercased()
            if out.contains(where: { $0.limb == a.limb && $0.reason.lowercased() == key }) { continue }
            if out.contains(where: { $0.limb == a.limb && $0.automatic }), says(key, accessWords) { continue }
            if harvestArms.contains(a.limb), says(key, harvestWords) { continue }
            out.append(LimbAlertItem(id: a.id.uuidString, limb: a.limb, reason: reason, automatic: false))
        }
        return out
    }

    private static let accessWords = #"\b(?:av[fg]?|fistula|graft|dialysis access|hemodialysis access)\b"#
    private static let harvestWords = #"\b(?:radial (?:artery )?harvest|harvest(?:ing)?|radial artery graft)\b"#
    private static func says(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }

    /// The alerts by limb: the limbs with a fistula first, each group in the order of `limbOrder`.
    static func limbAlertGroups(_ r: PatientRecord, arrivalOnly: Bool = false) -> [LimbAlertGroup] {
        let items = limbAlerts(r, arrivalOnly: arrivalOnly)
        var groups: [LimbAlertGroup] = []
        for limb in limbOrder {
            let mine = items.filter { $0.limb == limb }
            guard !mine.isEmpty else { continue }
            groups.append(LimbAlertGroup(limb: limb, reasons: mine.map(\.reason).map(sentenceForm), automatic: mine.contains { $0.automatic }))
        }
        return groups.filter(\.automatic) + groups.filter { !$0.automatic }
    }

    /// A typed reason inside a sentence: its first letter lower-cased unless the word is an acronym ("AV graft revision"),
    /// as the user's capital (FreeText.cap) was added only for a list.
    static func sentenceForm(_ reason: String) -> String {
        guard let f = reason.first, f.isUppercase else { return reason }
        let second = reason.dropFirst().first
        if let second, second.isUppercase { return reason }
        return f.lowercased() + reason.dropFirst()
    }

    /// The handoff line: "L arm — AV fistula; R arm — prior axillary lymph node dissection", or nil with none.
    static func limbAlertText(_ r: PatientRecord) -> String? {
        let groups = limbAlertGroups(r)
        return groups.isEmpty ? nil : groups.map(\.text).joined(separator: "; ")
    }

    /// Where the marker for a limb sits on the figure, in figure units (the 200 × 420 box): the upper arm, and the calf for a
    /// leg, clear of the sites the lines go in.
    static func limbAnchor(_ limb: String) -> CGPoint? {
        switch limb {
        case "arm-right": return CGPoint(x: 49, y: 140)
        case "arm-left": return CGPoint(x: 151, y: 140)
        case "leg-right": return CGPoint(x: 83.5, y: 352)
        case "leg-left": return CGPoint(x: 116.5, y: 352)
        default: return nil
        }
    }
}

extension PatientRecord {
    /// Epicardial pacing wires are in place (1.9): temporary pacing, for the ECG link.
    var hasTemporaryPacingWires: Bool { PatientDevices.temporaryPacingInPlace(devices) }
}
