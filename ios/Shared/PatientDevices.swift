import Foundation
import CoreGraphics

// MARK: - My Patient: lines, airways and devices on the body diagram
//
// Each device is drawn at a site of a front-view body figure. The figure box is 200 × 420, the box of the regional
// figure in reference.json (so its outline can be reused), with the head at the top and the patient's right on the
// viewer's left. Site anchors are fractions of that box (0…1). Back sites (thoracic and lumbar spine, ESP, popliteal)
// are drawn on the front figure as markers at their height (`DeviceSite.back`).
//
// Three ways in: tap the figure (`DeviceSite.sites(near:)`, `likelyKinds(at:)`, `options(near:)`), a type button
// (`DeviceKind.buttons` and `.more`, each kind's `fields`), or typed shorthand (`PatientDevices.parse`). The handoff
// text is `PatientDevices.label` and `labels`; ECMO cannulas group into one circuit with `PatientDevices.ecmoSystem`.
//
// Settings keys by kind (`PatientDevice.settings`, text as typed):
//   ett: depth (cm), depthAt ("lip", "teeth", "nare")             cvc, pac: depth (cm)
//   ecmoDrainage, ecmoReturn: mode ("VV", "VA", "VAV"), flow (L/min), sweep (L/min), fdo2 (%), issues. The circuit's
//     settings may sit on any of its cannulas; ECMOSystem merges them, drainage cannulas first.
//   lvad: rpm, pi, flow (L/min), power (W)                        iabp: ratio ("1:1"), augmentation (mmHg), timing
//   impella: pLevel ("6"), flow (L/min), position                 epidural, spinal: level ("L2-3"); epidural: depth
//     (cm), depthAt ("skin")

/// The color a device is drawn in; the figure maps each role to a color.
enum DeviceColorRole: String, Codable, CaseIterable, Hashable {
    /// Peripheral lines (PIV, arterial line, IO) and anything without a color of its own.
    case line
    /// Central venous catheters and PICCs: dark blue.
    case central
    /// Pulmonary artery catheter: yellow.
    case pac
    /// ECMO drainage cannulas: blue.
    case venousECMO
    /// ECMO return cannulas: red.
    case arterialECMO
    /// LVAD, IABP and Impella: a small pump.
    case pump
    /// Neuraxial and perineural catheters: a thin black line.
    case neuraxial
    /// Spinals and single-shot blocks: a needle icon.
    case needle
    /// ETT, tracheostomy, supraglottic airway.
    case airway
}

/// One thing a type button asks for. "size" and "detail" are the device's own fields; any other id is a key in
/// `PatientDevice.settings`.
struct DeviceField: Hashable, Identifiable {
    var id: String
    var label: String
    var unit: String
    /// Quick picks; the field still takes typed text.
    var choices: [String]
    var numeric: Bool

    init(_ id: String, _ label: String, unit: String = "", choices: [String] = [], numeric: Bool = false) {
        self.id = id; self.label = label; self.unit = unit; self.choices = choices; self.numeric = numeric
    }
}

enum DeviceLimb: String, Codable, CaseIterable, Hashable {
    case upper, lower
}

enum DeviceKind: String, Codable, CaseIterable, Hashable {
    case piv, arterial, cvc, pac, picc, intraosseous
    case ett, trach
    case ecmoDrainage, ecmoReturn, lvad, iabp, impella
    case epidural, spinal, block, perineuralCatheter
    case other

    /// The type buttons, in order; "Other" opens `more`.
    static let buttons: [DeviceKind] = [.piv, .arterial, .cvc, .pac, .ett]
    static let more: [DeviceKind] = [.ecmoDrainage, .ecmoReturn, .trach, .picc, .intraosseous, .lvad, .iabp, .impella,
                                     .epidural, .spinal, .block, .perineuralCatheter, .other]

    /// Short label for buttons, the legend and the handoff.
    var label: String {
        switch self {
        case .piv: return "PIV"
        case .arterial: return "A-line"
        case .cvc: return "CVL"
        case .pac: return "PAC"
        case .picc: return "PICC"
        case .intraosseous: return "IO"
        case .ett: return "ETT"
        case .trach: return "Trach"
        case .ecmoDrainage: return "ECMO drainage"
        case .ecmoReturn: return "ECMO return"
        case .lvad: return "LVAD"
        case .iabp: return "IABP"
        case .impella: return "Impella"
        case .epidural: return "Epidural"
        case .spinal: return "Spinal"
        case .block: return "Block"
        case .perineuralCatheter: return "Catheter"
        case .other: return "Other"
        }
    }

    /// The full name, for pickers and VoiceOver.
    var name: String {
        switch self {
        case .piv: return "Peripheral IV"
        case .arterial: return "Arterial line"
        case .cvc: return "Central venous catheter"
        case .pac: return "Pulmonary artery catheter"
        case .picc: return "PICC"
        case .intraosseous: return "Intraosseous needle"
        case .ett: return "Endotracheal tube"
        case .trach: return "Tracheostomy"
        case .ecmoDrainage: return "ECMO drainage cannula"
        case .ecmoReturn: return "ECMO return cannula"
        case .lvad: return "Left ventricular assist device"
        case .iabp: return "Intra-aortic balloon pump"
        case .impella: return "Impella"
        case .epidural: return "Epidural catheter"
        case .spinal: return "Spinal"
        case .block: return "Single-shot block"
        case .perineuralCatheter: return "Perineural catheter"
        case .other: return "Other"
        }
    }

    var colorRole: DeviceColorRole {
        switch self {
        case .piv, .arterial, .intraosseous, .other: return .line
        case .cvc, .picc: return .central
        case .pac: return .pac
        case .ecmoDrainage: return .venousECMO
        case .ecmoReturn: return .arterialECMO
        case .lvad, .iabp, .impella: return .pump
        case .epidural, .perineuralCatheter: return .neuraxial
        case .spinal, .block: return .needle
        case .ett, .trach: return .airway
        }
    }

    /// "G", "Fr", "mm ID", or "" for devices named by model (LVAD) or not sized (other).
    var sizeUnit: String {
        switch self {
        case .piv, .arterial, .intraosseous, .epidural, .spinal, .block, .perineuralCatheter: return "G"
        case .cvc, .pac, .picc, .ecmoDrainage, .ecmoReturn, .iabp, .impella: return "Fr"
        case .ett, .trach: return "mm ID"
        case .lvad, .other: return ""
        }
    }

    var isECMO: Bool { self == .ecmoDrainage || self == .ecmoReturn }

    /// What the type button asks for, in order.
    var fields: [DeviceField] {
        func size(_ choices: [String]) -> DeviceField { DeviceField("size", "Size", unit: sizeUnit, choices: choices, numeric: true) }
        func detail(_ label: String, _ choices: [String] = []) -> DeviceField { DeviceField("detail", label, choices: choices) }
        let depth = DeviceField("depth", "Depth", unit: "cm", numeric: true)
        let flow = DeviceField("flow", "Flow", unit: "L/min", numeric: true)
        let circuit = [DeviceField("mode", "Mode", choices: ["VV", "VA", "VAV"]), flow,
                       DeviceField("sweep", "Sweep", unit: "L/min", numeric: true),
                       DeviceField("fdo2", "FdO2", unit: "%", numeric: true),
                       DeviceField("issues", "Issues", choices: ["thrombus", "chatter", "hemolysis"])]
        switch self {
        case .piv:
            return [size(["24", "22", "20", "18", "16", "14"]), detail("Notes", ["ultrasound-guided", "midline"])]
        case .arterial:
            return [size(["22", "20", "18"]), detail("Notes", ["ultrasound-guided"])]
        case .cvc:
            return [size(["7", "8.5", "9", "12"]),
                    detail("Type", ["triple lumen", "MAC introducer", "Cordis", "introducer", "dialysis catheter"]), depth]
        case .pac:
            return [size(["7", "7.5", "8"]), depth, detail("Introducer", ["8.5 Fr introducer", "9 Fr introducer", "MAC introducer"])]
        case .picc:
            return [size(["3", "4", "5", "6"]), detail("Lumens", ["single lumen", "double lumen", "triple lumen"])]
        case .intraosseous:
            return [size(["15", "18"]), detail("Needle", ["15 mm", "25 mm", "45 mm"])]
        case .ett:
            return [size(["6.0", "6.5", "7.0", "7.5", "8.0", "8.5"]), depth,
                    DeviceField("depthAt", "Measured at", choices: ["lip", "teeth", "nare"]),
                    detail("Notes", ["cuffed", "uncuffed", "reinforced", "Left DLT", "Right DLT"])]
        case .trach:
            return [size(["6", "7", "8"]), detail("Type", ["cuffed", "uncuffed", "Shiley", "Portex", "Bivona", "fenestrated"])]
        case .ecmoDrainage:
            return [size(["21", "23", "25", "27", "29", "31"])] + circuit + [detail("Notes", ["dual lumen"])]
        case .ecmoReturn:
            return [size(["15", "17", "19", "21", "23"])] + circuit + [detail("Notes")]
        case .lvad:
            return [detail("Device", ["HeartMate 3", "HeartMate II", "HVAD"]),
                    DeviceField("rpm", "Speed", unit: "rpm", numeric: true), DeviceField("pi", "PI", numeric: true), flow,
                    DeviceField("power", "Power", unit: "W", numeric: true)]
        case .iabp:
            return [size(["7.5", "8"]), DeviceField("ratio", "Ratio", choices: ["1:1", "1:2", "1:3"]),
                    DeviceField("augmentation", "Augmentation", unit: "mmHg", numeric: true),
                    DeviceField("timing", "Timing", choices: ["good", "early inflation", "late inflation", "early deflation", "late deflation"])]
        case .impella:
            return [detail("Device", ["2.5", "CP", "5.0", "5.5", "RP Flex"]),
                    DeviceField("pLevel", "P-level", choices: ["2", "3", "4", "5", "6", "7", "8", "9"], numeric: true), flow,
                    DeviceField("position", "Position", choices: ["good", "too deep", "too shallow"])]
        case .epidural:
            return [DeviceField("level", "Level", choices: ["T4-5", "T6-7", "T8-9", "T10-11", "L1-2", "L2-3", "L3-4", "L4-5"]),
                    DeviceField("depth", "Catheter at the skin", unit: "cm", numeric: true), size(["17", "18", "19"]),
                    detail("Notes", ["CSE", "DPE"])]
        case .spinal:
            return [DeviceField("level", "Level", choices: ["L2-3", "L3-4", "L4-5"]), size(["22", "25", "27"]),
                    detail("Notes", ["Whitacre", "Quincke", "intrathecal morphine"])]
        case .block:
            return [detail("Drug and volume")]
        case .perineuralCatheter:
            return [detail("Notes")]
        case .other:
            return [detail("Device", ["LMA", "chest tube", "pacing wires", "NG tube", "Foley"]), DeviceField("size", "Size")]
        }
    }

    /// The `settings` keys this kind's fields use.
    var settingKeys: [String] { fields.map(\.id).filter { $0 != "size" && $0 != "detail" } }
}

// MARK: - A device

struct PatientDevice: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: DeviceKind = .other
    /// A DeviceSite id ("antecubital-right", "mouth"), or "" when it has no place on the figure yet.
    var site = ""
    /// "left", "right", or nil (a midline site, or not known).
    var side: String?
    /// As typed, in the kind's unit ("20", "8.5", "7.5").
    var size = ""
    /// Free text: type, model or anything else ("MAC introducer", "triple lumen", "HeartMate 3", "cuffed").
    var detail = ""
    /// Device parameters, keyed per kind (see the list at the top of this file, and DeviceKind.fields).
    var settings: [String: String] = [:]
    /// Placed during this anesthetic; false when it was there on arrival.
    var placedIntraop = false
    /// The user's drag away from the site's anchor, as a fraction of the figure box.
    var offset: CGPoint?
    /// Taken out (extubated, decannulated, pulled); kept for the record.
    var removed = false

    init(id: UUID = UUID(), kind: DeviceKind = .other, site: String = "", side: String? = nil, size: String = "",
         detail: String = "", settings: [String: String] = [:], placedIntraop: Bool = false, offset: CGPoint? = nil,
         removed: Bool = false) {
        self.id = id; self.kind = kind; self.site = site; self.side = side; self.size = size; self.detail = detail
        self.settings = settings; self.placedIntraop = placedIntraop; self.offset = offset; self.removed = removed
    }

    /// Every field read with a fallback, so a device saved by another version still opens: a missing or malformed
    /// field takes its default, a kind this version does not know becomes `other`, and numbers saved where text is
    /// expected are kept as text.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        func text(_ key: CodingKeys) -> String? {
            if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
            if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return NumText.exact(d) }
            return nil
        }
        id = v(.id, UUID())
        kind = v(.kind, DeviceKind.other)
        site = text(.site) ?? ""
        side = text(.side)
        size = text(.size) ?? ""
        detail = text(.detail) ?? ""
        placedIntraop = v(.placedIntraop, false)
        offset = try? c.decodeIfPresent(CGPoint.self, forKey: .offset)
        removed = v(.removed, false)
        var s: [String: String] = [:]
        if let raw = try? c.nestedContainer(keyedBy: DeviceAnyKey.self, forKey: .settings) {
            for k in raw.allKeys {
                if let t = try? raw.decode(String.self, forKey: k) { s[k.stringValue] = t }
                else if let d = try? raw.decode(Double.self, forKey: k) { s[k.stringValue] = NumText.exact(d) }
                else if let b = try? raw.decode(Bool.self, forKey: k) { s[k.stringValue] = b ? "true" : "false" }
            }
        }
        settings = s
    }

    // CGPoint is Equatable but not Hashable, so the hash is written out; == is synthesized.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id); hasher.combine(kind); hasher.combine(site); hasher.combine(side); hasher.combine(size)
        hasher.combine(detail); hasher.combine(settings); hasher.combine(placedIntraop)
        hasher.combine(offset?.x); hasher.combine(offset?.y); hasher.combine(removed)
    }
}

/// Dictionary keys read one by one (the tolerant settings decode).
private struct DeviceAnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension PatientDevice {
    var siteInfo: DeviceSite? { DeviceSite.site(id: site) }

    /// Where to draw it: the site's anchor plus the user's drag, as fractions of the figure box.
    var position: CGPoint? {
        guard let a = siteInfo?.anchor else { return nil }
        return CGPoint(x: a.x + (offset?.x ?? 0), y: a.y + (offset?.y ?? 0))
    }

    /// The kind's color role; an "other" device at the mouth, nose or stoma (an LMA) is drawn as an airway.
    var colorRole: DeviceColorRole {
        if kind == .other, let b = siteInfo?.base, ["mouth", "nose", "trach"].contains(b) { return .airway }
        return kind.colorRole
    }

    /// The compact handoff text ("PIV 20 G R AC").
    var label: String { PatientDevices.label(self) }

    /// A field's value: "size" and "detail" are the device's own; any other key comes from `settings`.
    func value(_ key: String) -> String {
        switch key {
        case "size": return size
        case "detail": return detail
        default: return settings[key] ?? ""
        }
    }

    /// Sets a field's value, trimmed; an empty value clears a setting.
    mutating func setValue(_ value: String, for key: String) {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "size": size = t
        case "detail": detail = t
        default: settings[key] = t.isEmpty ? nil : t
        }
    }

    /// A line saved by an earlier version (kind, site and size as text) as a device. The site text is read like typed
    /// shorthand; text that names no site is kept in `detail`.
    init(line: PatientLine) {
        let kinds: [String: DeviceKind] = ["Peripheral IV": .piv, "Arterial line": .arterial, "Central line": .cvc,
                                           "PICC": .picc, "Intraosseous": .intraosseous, "PA catheter": .pac]
        let kind = kinds[line.kind] ?? .other
        self.init(id: line.id, kind: kind, size: line.size.trimmingCharacters(in: .whitespacesAndNewlines))
        var notes: [String] = []
        if kind == .other, line.kind != "Other", !line.kind.isEmpty { notes.append(line.kind) }
        let text = line.site.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let probe = (kind == .other ? "" : kind.label + " ") + text
            if let p = PatientDevices.parse(probe), let s = p.site, p.kind == kind {
                site = s
                side = p.side
                if size.isEmpty { size = p.size }
                if !p.detail.isEmpty { notes.append(p.detail) }
            } else {
                notes.append(text)
            }
        }
        detail = notes.joined(separator: ", ")
    }
}

// MARK: - Sites on the figure

struct DeviceSite: Hashable, Identifiable {
    /// "antecubital-right", "mouth".
    var id: String
    /// The site without its side ("antecubital").
    var base: String
    /// "Right antecubital fossa".
    var name: String
    /// Handoff form, naming the vessel where two share a place: "R AC", "R femoral vein", "R femoral artery".
    var short: String
    /// Handoff form when the device already says which vessel: "R femoral" for an A-line, IABP or Impella.
    var brief: String
    /// "head", "neck", "chest", "arm", "abdomen", "back", "groin" or "leg".
    var region: String
    /// "right", "left", or nil for a midline site.
    var side: String?
    /// On the front figure, as fractions of the 200 × 420 box.
    var anchor: CGPoint
    /// A back site, drawn on the front figure as a marker at its height.
    var back: Bool
    /// The likely device kinds here, most likely first.
    var kinds: [DeviceKind]

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Distance from a point given as fractions of the figure box, in figure points (so across and down weigh the same).
    func distance(to point: CGPoint) -> CGFloat {
        let dx = (anchor.x - point.x) * 200, dy = (anchor.y - point.y) * 420
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// One entry of the dropdown for a tap: a kind at a site.
struct DeviceOption: Hashable, Identifiable {
    var site: DeviceSite
    var kind: DeviceKind
    var id: String { site.id + ":" + kind.rawValue }
    /// "PIV · R AC".
    var label: String { kind.label + " · " + site.short }
}

extension DeviceSite {
    /// The figure box the anchors are fractions of (the regional figure's box in reference.json).
    static let figureSize = CGSize(width: 200, height: 420)

    private struct Spec {
        let base: String, name: String, short: String, brief: String?, region: String
        let x: Double, y: Double, paired: Bool, back: Bool, kinds: [DeviceKind]
        init(_ base: String, _ name: String, _ short: String, _ brief: String?, _ region: String, _ x: Double, _ y: Double,
             _ paired: Bool, _ back: Bool, _ kinds: [DeviceKind]) {
            self.base = base; self.name = name; self.short = short; self.brief = brief; self.region = region
            self.x = x; self.y = y; self.paired = paired; self.back = back; self.kinds = kinds
        }
    }

    // Anchors in figure points (200 × 420), right side; the left side mirrors them (x → 200 − x). Placed on the
    // regional figure's outline: neck 91–109 wide at y 52–64, clavicles y 70–72, axilla (66, 108), elbow y about 156,
    // wrist about 208, inguinal ligament (68, 182)–(94, 204), knee y 300, ankle about 390, sole y 412.
    private static let specs: [Spec] = [
        Spec("scalp", "scalp vein", "scalp", nil, "head", 88, 20, true, false, [.piv]),
        Spec("nose", "nose", "nasal", nil, "head", 100, 33, false, false, [.ett]),
        Spec("mouth", "mouth", "oral", nil, "head", 100, 42, false, false, [.ett]),
        Spec("interscalene", "interscalene", "interscalene", nil, "neck", 92, 54, true, false, [.block, .perineuralCatheter]),
        Spec("ej", "external jugular vein", "EJ", nil, "neck", 92.5, 57, true, false, [.piv, .cvc]),
        Spec("ij", "internal jugular vein", "IJ", nil, "neck", 95.5, 61, true, false, [.cvc, .pac, .ecmoReturn, .ecmoDrainage]),
        Spec("trach", "tracheostomy stoma", "stoma", nil, "neck", 100, 62, false, false, [.trach]),
        Spec("supraclavicular", "supraclavicular", "supraclavicular", nil, "chest", 84, 68.5, true, false, [.block, .perineuralCatheter]),
        Spec("subclavian", "subclavian vein", "subclavian", nil, "chest", 88, 76, true, false, [.cvc, .pac]),
        Spec("infraclavicular", "infraclavicular", "infraclavicular", nil, "chest", 76, 80, true, false, [.block, .perineuralCatheter]),
        Spec("aorta", "ascending aorta (central)", "aorta", nil, "chest", 101, 86, false, false, [.ecmoReturn]),
        Spec("parasternal", "parasternal (PIFB)", "parasternal", nil, "chest", 94, 90, true, false, [.block, .perineuralCatheter]),
        Spec("pecs", "PECS/serratus plane", "PECS", nil, "chest", 73, 100, true, false, [.block, .perineuralCatheter]),
        Spec("right-atrium", "right atrium (central)", "RA", nil, "chest", 95, 104, false, false, [.ecmoDrainage]),
        Spec("heart", "heart (LV apex)", "LV apex", nil, "chest", 112, 114, false, false, [.lvad]),
        Spec("humeral-io", "proximal humerus (IO)", "humerus", nil, "arm", 53, 92, true, false, [.intraosseous]),
        Spec("axillary-artery", "axillary artery", "axillary artery", "axillary", "arm", 64, 98, true, false, [.arterial, .impella, .ecmoReturn, .iabp]),
        Spec("axillary-block", "axillary brachial plexus", "axillary", nil, "arm", 57, 114, true, false, [.block, .perineuralCatheter]),
        Spec("upper-arm", "upper arm", "upper arm", nil, "arm", 55, 128, true, false, [.picc, .piv]),
        Spec("brachial", "brachial artery", "brachial", nil, "arm", 51, 150, true, false, [.arterial]),
        Spec("antecubital", "antecubital fossa", "AC", nil, "arm", 46, 157, true, false, [.piv, .picc]),
        Spec("forearm", "forearm", "forearm", nil, "arm", 42, 182, true, false, [.piv]),
        Spec("wrist", "wrist", "wrist", nil, "arm", 40, 205, true, false, [.piv]),
        Spec("radial", "radial artery", "radial", nil, "arm", 32.5, 208, true, false, [.arterial]),
        Spec("hand", "hand (dorsum)", "hand", nil, "arm", 35, 229, true, false, [.piv]),
        Spec("tap", "transversus abdominis plane", "TAP", nil, "abdomen", 72, 162, true, false, [.block, .perineuralCatheter]),
        Spec("esp", "erector spinae plane (back)", "ESP", nil, "back", 94, 112, true, true, [.block, .perineuralCatheter]),
        Spec("thoracic-spine", "thoracic spine (back)", "thoracic", nil, "back", 100, 118, false, true, [.epidural]),
        Spec("lumbar-spine", "lumbar spine (back)", "lumbar", nil, "back", 100, 180, false, true, [.epidural, .spinal]),
        Spec("femoral-block", "femoral nerve", "femoral", nil, "groin", 73.5, 194, true, false, [.block, .perineuralCatheter]),
        Spec("femoral-artery", "femoral artery", "femoral artery", "femoral", "groin", 79, 199, true, false, [.arterial, .iabp, .impella, .ecmoReturn]),
        Spec("femoral-vein", "femoral vein", "femoral vein", "femoral", "groin", 84, 202, true, false, [.cvc, .ecmoDrainage, .pac, .impella]),
        Spec("adductor-canal", "adductor canal", "adductor canal", nil, "leg", 90, 262, true, false, [.block, .perineuralCatheter]),
        Spec("popliteal", "popliteal (back of the knee)", "popliteal", nil, "leg", 73, 293, true, true, [.block, .perineuralCatheter]),
        Spec("tibial-io", "proximal tibia (IO)", "tibia", nil, "leg", 86, 321, true, false, [.intraosseous]),
        Spec("saphenous", "great saphenous vein (ankle)", "saphenous", nil, "leg", 92, 388, true, false, [.piv]),
        Spec("dorsalis-pedis", "dorsalis pedis artery", "DP", nil, "leg", 88, 400, true, false, [.arterial]),
        Spec("foot", "foot (dorsum)", "foot", nil, "leg", 79, 404, true, false, [.piv]),
    ]

    private static func make(_ sp: Spec, _ side: String?) -> DeviceSite {
        let right = side == "right", left = side == "left"
        let pre = right ? "R " : (left ? "L " : "")
        let name: String
        if right { name = "Right " + sp.name } else if left { name = "Left " + sp.name } else { name = sp.name.prefix(1).uppercased() + sp.name.dropFirst() }
        let x = left ? 200 - sp.x : sp.x
        return DeviceSite(id: side.map { sp.base + "-" + $0 } ?? sp.base, base: sp.base, name: name, short: pre + sp.short,
                          brief: pre + (sp.brief ?? sp.short), region: sp.region, side: side,
                          anchor: CGPoint(x: x / 200, y: sp.y / 420), back: sp.back, kinds: sp.kinds)
    }

    /// Every site, head to foot; paired sites right then left.
    static let all: [DeviceSite] = specs.flatMap { sp -> [DeviceSite] in
        sp.paired ? [DeviceSite.make(sp, "right"), DeviceSite.make(sp, "left")] : [DeviceSite.make(sp, nil)]
    }
    private static let byId: [String: DeviceSite] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    private static let pairedBases: Set<String> = Set(specs.filter { $0.paired }.map { $0.base })
    private static let baseKinds: [String: [DeviceKind]] = Dictionary(specs.map { ($0.base, $0.kinds) }, uniquingKeysWith: { a, _ in a })

    static func site(id: String) -> DeviceSite? { byId[id] }

    /// The site for a side-less id and a side ("radial", "left" → "radial-left"); midline sites ignore the side.
    static func find(_ base: String, side: String?) -> DeviceSite? {
        if pairedBases.contains(base) {
            guard let side, side == "right" || side == "left" else { return nil }
            return byId[base + "-" + side]
        }
        return byId[base]
    }

    static func isPaired(_ base: String) -> Bool { pairedBases.contains(base) }

    /// The likely kinds at a side-less site ("radial" → [.arterial]).
    static func kinds(forBase base: String) -> [DeviceKind] { baseKinds[base] ?? [] }

    /// The sites closest to a point (fractions of the figure box), nearest first; only those where `kind` is likely
    /// when one is given, and only within `radius` figure points when one is given.
    static func sites(near point: CGPoint, limit: Int = 4, kind: DeviceKind? = nil, within radius: CGFloat? = nil) -> [DeviceSite] {
        var scored: [(site: DeviceSite, d: CGFloat, i: Int)] = []
        for (i, s) in all.enumerated() {
            if let kind, !s.kinds.contains(kind) { continue }
            let d = s.distance(to: point)
            if let radius, d > radius { continue }
            scored.append((s, d, i))
        }
        scored.sort { $0.d != $1.d ? $0.d < $1.d : $0.i < $1.i }
        return scored.prefix(max(0, limit)).map { $0.site }
    }

    /// The dropdown for a site: its likely kinds, most likely first, then Other.
    static func likelyKinds(at site: DeviceSite) -> [DeviceKind] {
        site.kinds.contains(.other) ? site.kinds : site.kinds + [.other]
    }

    /// One dropdown for a tap: the likely kinds of the sites around it, ranked by distance plus 8 points for each step
    /// down a site's list (Other is left for the UI to add).
    static func options(near point: CGPoint, limit: Int = 8, within radius: CGFloat = 40) -> [DeviceOption] {
        var out: [(option: DeviceOption, score: CGFloat, i: Int)] = []
        for s in sites(near: point, limit: 6, within: radius) {
            let d = s.distance(to: point)
            for (rank, k) in s.kinds.enumerated() where k != .other {
                out.append((DeviceOption(site: s, kind: k), d + CGFloat(rank) * 8, out.count))
            }
        }
        out.sort { $0.score != $1.score ? $0.score < $1.score : $0.i < $1.i }
        return out.prefix(max(0, limit)).map { $0.option }
    }

    /// The midline point for a vertebral level ("T8"; "L3-4" sits between L3 and L4), so a neuraxial marker can be
    /// drawn at its height on the front figure. nil when the level is not understood.
    static func spineAnchor(level: String) -> CGPoint? {
        let parts = level.uppercased().split(separator: "-").map(String.init)
        guard let first = parts.first, let y1 = vertebraY(first, letter: nil) else { return nil }
        var y = y1
        if parts.count > 1, let y2 = vertebraY(parts[1], letter: first.first) { y = (y1 + y2) / 2 }
        return CGPoint(x: 0.5, y: y / 420)
    }

    private static func vertebraY(_ s: String, letter: Character?) -> Double? {
        var digits = s
        var region = letter
        if let c = digits.first, c.isLetter { region = c; digits.removeFirst() }
        guard let r = region, let n = Int(digits) else { return nil }
        switch r {
        case "C" where (1...7).contains(n): return 62 - Double(7 - n) * 4
        case "T" where (1...12).contains(n): return 66 + Double(n - 1) * 84 / 11
        case "L" where (1...5).contains(n): return 158 + Double(n - 1) * 9
        case "S" where (1...5).contains(n): return 200 + Double(n - 1) * 6
        default: return nil
        }
    }
}

// MARK: - A parse of typed shorthand

struct DeviceParse: Hashable {
    var kind: DeviceKind
    var size = ""
    /// A DeviceSite id; nil when no site was found, or when a paired site's side is missing (see `baseSite`).
    var site: String?
    /// "right", "left" or nil.
    var side: String?
    /// The site without its side ("antecubital"), known even when the side is not.
    var baseSite: String?
    var detail = ""
    var settings: [String: String] = [:]
    /// 0…1. About 0.85 and up: Ben's own shorthand and anything said outright, safe to add as is. Around 0.6: a site
    /// or side guessed (show it to confirm). Under about 0.4: ask.
    var confidence = 1.0
    /// Other readings of an ambiguous entry, most likely first: each side when the side is missing, the other vessel
    /// or block for "fem", "FA" or "ax" alone.
    var alternatives: [DeviceParse] = []
    /// More devices the same entry describes: the other ECMO cannula(s), the left side of a bilateral entry.
    var companions: [DeviceParse] = []

    init(kind: DeviceKind) { self.kind = kind }

    func device(placedIntraop: Bool = false) -> PatientDevice {
        PatientDevice(kind: kind, site: site ?? "", side: side == "both" ? nil : side, size: size, detail: detail,
                      settings: settings, placedIntraop: placedIntraop)
    }

    /// This device and its companions.
    func devices(placedIntraop: Bool = false) -> [PatientDevice] {
        [device(placedIntraop: placedIntraop)] + companions.map { $0.device(placedIntraop: placedIntraop) }
    }
}

// MARK: - An ECMO circuit

struct ECMOSystem: Hashable {
    enum Configuration: String, CaseIterable, Hashable {
        case vv, vaPeripheral, vaCentral, vav, unknown

        /// "VV", "VA peripheral", "VA central", "VAV".
        var name: String {
            switch self {
            case .vv: return "VV"
            case .vaPeripheral: return "VA peripheral"
            case .vaCentral: return "VA central"
            case .vav: return "VAV"
            case .unknown: return "Unknown"
            }
        }

        /// The opening of the handoff line.
        var title: String {
            switch self {
            case .vv: return "VV ECMO"
            case .vaPeripheral: return "Peripheral VA ECMO"
            case .vaCentral: return "Central VA ECMO"
            case .vav: return "VAV ECMO"
            case .unknown: return "ECMO"
            }
        }
    }

    var drainage: [PatientDevice]
    var returns: [PatientDevice]
    var configuration: Configuration
    /// The circuit's settings merged from its cannulas (drainage first; the first value given wins).
    var settings: [String: String]
    /// "VV ECMO: drainage 25 Fr R femoral vein, return 21 Fr R IJ; flow 4.5 L/min, sweep 3 L/min".
    var label: String
}

// MARK: - Labels, ECMO grouping and default sites

enum PatientDevices {
    /// Where a device goes when the entry names only a limb, or no site at all. All the default-site rules live here.
    ///
    /// - A limb: PIV → antecubital fossa in the arm ("20 rue" = right antecubital fossa) and the great saphenous vein
    ///   at the ankle in the leg; A-line → radial (arm) or femoral (leg); IO → humerus (arm) or tibia (leg); PICC →
    ///   upper arm.
    /// - No site: ETT → mouth, trach → stoma, LVAD → heart, epidural → thoracic spine for a C or T level and lumbar
    ///   otherwise, spinal → lumbar spine. These are sure.
    /// - No site, a guess (lowers the confidence, and the side stays unknown): A-line → radial, CVL and PAC → IJ,
    ///   PICC → upper arm, IO → tibia, IABP and Impella → femoral artery, ECMO drainage → femoral vein.
    ///
    /// Returns the side-less site and whether the default is sure.
    static func defaultSite(for kind: DeviceKind, limb: DeviceLimb? = nil, level: String? = nil) -> (site: String, sure: Bool)? {
        switch limb {
        case .upper?:
            switch kind {
            case .piv: return ("antecubital", true)
            case .arterial: return ("radial", true)
            case .intraosseous: return ("humeral-io", true)
            case .picc: return ("upper-arm", true)
            default: return nil
            }
        case .lower?:
            switch kind {
            case .piv: return ("saphenous", true)
            case .arterial: return ("femoral-artery", true)
            case .intraosseous: return ("tibial-io", true)
            default: return nil
            }
        case nil:
            break
        }
        switch kind {
        case .ett: return ("mouth", true)
        case .trach: return ("trach", true)
        case .lvad: return ("heart", true)
        case .epidural, .spinal:
            if let l = level?.uppercased().first, l == "C" || l == "T" { return ("thoracic-spine", true) }
            return ("lumbar-spine", level != nil || kind == .spinal)
        case .arterial: return ("radial", false)
        case .cvc, .pac: return ("ij", false)
        case .picc: return ("upper-arm", false)
        case .intraosseous: return ("tibial-io", false)
        case .iabp, .impella: return ("femoral-artery", false)
        case .ecmoDrainage: return ("femoral-vein", false)
        default: return nil
        }
    }

    /// Compact handoff text: "PIV 20 G R AC", "A-line 20 G L radial", "CVL R IJ (MAC introducer)", "PAC via R IJ",
    /// "ETT 7.5 at 23 cm", "IABP L femoral 1:1", "Impella CP R femoral P6, 3.2 L/min",
    /// "HeartMate 3 LVAD 5400 rpm, PI 4.1, 4.8 L/min", "R interscalene block", "Epidural T8". An ECMO cannula reads
    /// "ECMO drainage 25 Fr R femoral vein"; the circuit's line is `ecmoSystem(_:)?.label`.
    static func label(_ d: PatientDevice) -> String {
        let site = DeviceSite.site(id: d.site)
        let brief = site?.brief ?? "", short = site?.short ?? ""
        func val(_ key: String) -> String { (d.settings[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let size = d.size.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = d.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let gone = d.removed ? (d.kind == .ett ? "extubated" : "removed") : ""
        let unit = d.kind.sizeUnit
        let sized = size.isEmpty || unit.isEmpty ? size : size + " " + unit
        let depth = val("depth").isEmpty ? "" : "at " + val("depth") + " cm"
        switch d.kind {
        case .piv, .arterial, .cvc, .picc, .intraosseous:
            return spaced(d.kind.label, sized, brief, depth) + paren(detail, gone)
        case .pac:
            return spaced("PAC", sized, brief.isEmpty ? "" : "via " + brief, depth) + paren(detail, gone)
        case .ett:
            let dlt = detail.range(of: "DLT", options: .caseInsensitive) != nil
            let nasal = site?.base == "nose" && detail.range(of: "nasal", options: .caseInsensitive) == nil
            let tube = dlt ? (size.isEmpty ? "" : size + " Fr") : size
            return spaced(dlt ? detail : "ETT", tube, depth) + paren(val("depthAt"), nasal ? "nasal" : "", dlt ? "" : detail, gone)
        case .trach:
            return spaced("Trach", size) + paren(detail, gone)
        case .ecmoDrainage, .ecmoReturn:
            return spaced(d.kind.label, sized, short) + paren(detail, gone)
        case .lvad:
            var s: [String] = []
            if !val("rpm").isEmpty { s.append(val("rpm") + " rpm") }
            if !val("pi").isEmpty { s.append("PI " + val("pi")) }
            if !val("flow").isEmpty { s.append(val("flow") + " L/min") }
            if !val("power").isEmpty { s.append(val("power") + " W") }
            return spaced(detail, "LVAD", s.joined(separator: ", ")) + paren(gone)
        case .iabp:
            var s: [String] = []
            if !val("ratio").isEmpty { s.append(val("ratio")) }
            if !val("augmentation").isEmpty { s.append("augmentation " + val("augmentation") + " mmHg") }
            if !val("timing").isEmpty { s.append("timing " + val("timing")) }
            return spaced("IABP", sized, brief, s.joined(separator: ", ")) + paren(detail, gone)
        case .impella:
            var s: [String] = []
            let pl = val("pLevel")
            if !pl.isEmpty { s.append(pl.uppercased().hasPrefix("P") ? pl : "P" + pl) }
            if !val("flow").isEmpty { s.append(val("flow") + " L/min") }
            let pos = val("position")
            if !pos.isEmpty { s.append("position " + pos + (Double(pos) != nil ? " cm" : "")) }
            return spaced("Impella", detail, sized, brief, s.joined(separator: ", ")) + paren(gone)
        case .epidural, .spinal:
            let level = val("level")
            let at = val("depthAt").isEmpty ? "skin" : val("depthAt")
            let dep = val("depth").isEmpty ? "" : val("depth") + " cm at the " + at
            return spaced(d.kind.label, level.isEmpty ? (site?.short ?? "") : level) + paren(sized, dep, detail, gone)
        case .block, .perineuralCatheter:
            let word = d.kind == .block ? "block" : "catheter"
            return (brief.isEmpty ? d.kind.name : brief + " " + word) + paren(detail, gone)
        case .other:
            let airway = ["mouth", "nose", "trach"].contains(site?.base ?? "")
            return spaced(detail.isEmpty ? "Other" : detail, size, airway ? "" : brief) + paren(gone)
        }
    }

    /// Handoff lines for a patient's devices in order, the ECMO cannulas as one circuit line where the first cannula
    /// is. Removed devices are left out unless asked for.
    static func labels(_ devices: [PatientDevice], includeRemoved: Bool = false) -> [String] {
        var out: [String] = []
        var circuitDone = false
        for d in devices where includeRemoved || !d.removed {
            if d.kind.isECMO && !d.removed {
                if !circuitDone, let sys = ecmoSystem(devices) { out.append(sys.label) }
                circuitDone = true
                continue
            }
            out.append(label(d))
        }
        return out
    }

    /// The ECMO circuit made by the devices' cannulas (removed ones left out), named from where the return cannulas
    /// sit: all venous → VV; arterial → VA, central when the arterial return is in the aorta; both → VAV. A single
    /// dual-lumen drainage cannula is VV. When no return cannula has a known site, the circuit's "mode" setting
    /// decides. nil without cannulas.
    static func ecmoSystem(_ devices: [PatientDevice]) -> ECMOSystem? {
        let cannulas = devices.filter { $0.kind.isECMO && !$0.removed }
        guard !cannulas.isEmpty else { return nil }
        let drainage = cannulas.filter { $0.kind == .ecmoDrainage }
        let returns = cannulas.filter { $0.kind == .ecmoReturn }
        var settings: [String: String] = [:]
        for d in drainage + returns {
            for (k, v) in d.settings where settings[k] == nil {
                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { settings[k] = t }
            }
        }
        func base(_ d: PatientDevice) -> String? { DeviceSite.site(id: d.site)?.base }
        let arterial = returns.filter { ecmoVessel(base($0)) == "arterial" }
        let venous = returns.filter { ecmoVessel(base($0)) == "venous" }
        let mode = (settings["mode"] ?? "").uppercased()
        let dualLumen = returns.isEmpty && drainage.count == 1
            && ["dual", "double lumen", "avalon", "crescent"].contains { drainage[0].detail.lowercased().contains($0) }
        let config: ECMOSystem.Configuration
        if !arterial.isEmpty && !venous.isEmpty {
            config = .vav
        } else if !arterial.isEmpty {
            config = arterial.contains { base($0) == "aorta" } ? .vaCentral : .vaPeripheral
        } else if !venous.isEmpty || dualLumen || mode == "VV" {
            config = .vv
        } else if mode == "VA" {
            config = cannulas.contains { ["right-atrium", "aorta"].contains(base($0) ?? "") } ? .vaCentral : .vaPeripheral
        } else if mode == "VAV" || mode == "V-AV" {
            config = .vav
        } else {
            config = .unknown
        }
        func phrase(_ d: PatientDevice) -> String {
            let size = d.size.trimmingCharacters(in: .whitespacesAndNewlines)
            let where_ = DeviceSite.site(id: d.site)?.short ?? ""
            return spaced(size.isEmpty ? "" : size + " Fr", where_) + paren(d.detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var parts: [String] = []
        for (role, group) in [("drainage", drainage), ("return", returns)] where !group.isEmpty {
            let ph = group.map(phrase).filter { !$0.isEmpty }
            parts.append(ph.isEmpty ? role : role + " " + ph.joined(separator: " and "))
        }
        var s: [String] = []
        if let f = settings["flow"] { s.append("flow " + f + " L/min") }
        if let w = settings["sweep"] { s.append("sweep " + w + " L/min") }
        if let o = settings["fdo2"] { s.append("FdO2 " + o + "%") }
        if let i = settings["issues"] { s.append(i) }
        var label = config.title
        if !parts.isEmpty { label += ": " + parts.joined(separator: ", ") }
        if !s.isEmpty { label += "; " + s.joined(separator: ", ") }
        return ECMOSystem(drainage: drainage, returns: returns, configuration: config, settings: settings, label: label)
    }

    /// "arterial", "venous" or nil, for a side-less site as an ECMO cannula sees it.
    private static func ecmoVessel(_ base: String?) -> String? {
        switch base {
        case "femoral-artery"?, "axillary-artery"?, "aorta"?, "fa"?, "axillary"?: return "arterial"
        case "femoral-vein"?, "ij"?, "subclavian"?, "ej"?, "right-atrium"?: return "venous"
        default: return nil
        }
    }

    private static func spaced(_ parts: String...) -> String { parts.filter { !$0.isEmpty }.joined(separator: " ") }

    private static func paren(_ parts: String...) -> String {
        let p = parts.filter { !$0.isEmpty }
        return p.isEmpty ? "" : " (" + p.joined(separator: ", ") + ")"
    }
}

// MARK: - Shorthand parser

extension PatientDevices {
    /// Reads typed shorthand into a device: kind, size, site, side, detail and settings, with a confidence and, when
    /// the entry is ambiguous, alternatives. nil when the text names no device, site or size.
    ///
    /// Ben's examples: "20 rue" = PIV 20 G right antecubital fossa; "16ga lfa" = PIV 16 G left forearm; "14 l hand" =
    /// PIV 14 G left hand; "RIJ introducer/mac" = CVL right IJ, MAC introducer.
    ///
    /// - Words: sides R, L, B (rt, lt, bilat, B/L); limbs UE, LE, RUE, LUE, RLE, LLE; sites AC, FA, IJ, SC/subclav,
    ///   EJ, FV, fem, rad, brach, ax, DP, tib, hum and the block names, also run together with a side (RIJ, LSC, RFV,
    ///   LAC, RFA); devices PIV, aline/art line, CVL, TLC, MAC, cordis, introducer, swan/PAC, HD cath/trialysis, PICC,
    ///   IO, ETT, DLT, trach, LMA, LVAD/HM3, IABP, Impella (and its model), ECMO with VV/VA/VAV and drainage/return,
    ///   epidural, spinal, block, catheter; units ga/g/G, Fr/F, cm, L/min, rpm, W, mmHg, %; levels (L2-3, T8),
    ///   ratios (1:1) and P-levels (P6).
    /// - Numbers: one after a setting word (flow, sweep, FdO2, PI, power, rpm/speed, aug, P) or before a setting unit
    ///   (rpm, L/min, W, mmHg, %, cm) is that setting; "@ 22" or "at 22" is a depth. The first number left is the size;
    ///   for an ETT a second one of 10 or more is the depth; for a PAC a size next to "introducer" (or cordis, MAC,
    ///   sheath) is the introducer's.
    /// - Kind: the device word when there is one (a PAC wins over its introducer, an Impella or IABP over "art");
    ///   otherwise a block name means a block (a catheter with "cath"), and a site means its most likely kind refined
    ///   by the unit (G: PIV or A-line; Fr: a central device); a limb alone means a PIV.
    /// - Ambiguous sites: FA is the forearm for a PIV or a gauge size, and the femoral artery for an arterial device,
    ///   a French size or in an ECMO entry ("17F LFA"); fem is the artery for an A-line, IABP or Impella (the vein for
    ///   an Impella RP), the vein for a CVL, PAC or drainage cannula, the femoral nerve with "block"; ax is the
    ///   axillary artery for an arterial device and the axillary block otherwise. Left unresolved, the guess comes
    ///   with the other readings as alternatives.
    /// - No site, or only a limb: `defaultSite(for:limb:level:)`.
    /// - Bilateral entries become two devices, right then left; an ECMO entry becomes one device per cannula, with the
    ///   circuit's settings and mode on the first (drainage) cannula. ECMO roles left out are read from the site (an
    ///   artery returns), the mode (VA: venous cannulas drain) or, for VV, the larger or femoral cannula draining.
    /// - Words not understood are kept in `detail` and lower the confidence.
    static func parse(_ text: String) -> DeviceParse? {
        let w = lex(text)
        guard !w.isEmpty else { return nil }
        let t = classify(w)
        let ecmo = t.contains { tok in
            switch tok.tok {
            case .ecmo, .mode, .role, .kind(.ecmoDrainage, _), .kind(.ecmoReturn, _): return true
            default: return false
            }
        }
        return ecmo ? parseECMO(t) : parseSingle(t)
    }

    private static let gauges: Set<String> = ["14", "16", "18", "20", "22", "24"]
    private static let introducers: Set<String> = ["introducer", "MAC introducer", "Cordis", "sheath"]
    private static let arterialKinds: Set<DeviceKind> = [.arterial, .iabp, .impella, .ecmoReturn]
    private static let venousKinds: Set<DeviceKind> = [.cvc, .pac, .picc, .ecmoDrainage]
    private static let priority: [DeviceKind] = [.pac, .impella, .iabp, .lvad, .ett, .trach, .epidural, .spinal, .picc,
                                                 .intraosseous, .cvc, .arterial, .piv, .ecmoDrainage, .ecmoReturn, .other]
    private static let textSettings: Set<String> = ["timing", "issues", "position"]
    private static let unitSettings: [String: String] = ["rpm": "rpm", "L/min": "flow", "W": "power", "mmHg": "augmentation",
                                                         "%": "fdo2", "cm": "depth"]

    private static func score(_ x: Double) -> Double { max(0.05, min(1, (x * 100).rounded() / 100)) }

    // MARK: Words

    private static func lex(_ text: String) -> [String] {
        var s = text
        for ch in ["\u{2013}", "\u{2014}", "\u{2011}", "\u{2212}"] { s = s.replacingOccurrences(of: ch, with: "-") }
        s = s.replacingOccurrences(of: "@", with: " at ")
        for ch in [",", ";", "(", ")", "+", "|"] { s = s.replacingOccurrences(of: ch, with: " / ") }
        var out: [String] = []
        for w in s.split(whereSeparator: { $0.isWhitespace }) { out += splitWord(String(w)) }
        return out
    }

    private static func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }

    private static func isNumber(_ s: String) -> Bool {
        guard !s.isEmpty, !s.hasPrefix("."), !s.hasSuffix(".") else { return false }
        var dot = false
        for c in s {
            if c == "." {
                if dot { return false }
                dot = true
            } else if !isDigit(c) {
                return false
            }
        }
        return true
    }

    /// "t8", "l2-3", "t12-l1" (lowercased).
    private static func isLevel(_ s: String) -> Bool {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        func vertebra(_ v: String, needsLetter: Bool) -> Bool {
            var t = v
            if let c = t.first, "ctls".contains(c) { t.removeFirst() } else if needsLetter { return false }
            return (1...2).contains(t.count) && t.allSatisfy { isDigit($0) }
        }
        switch parts.count {
        case 1: return vertebra(parts[0], needsLetter: true)
        case 2: return vertebra(parts[0], needsLetter: true) && vertebra(parts[1], needsLetter: false)
        default: return false
        }
    }

    /// "l2-3" → "L2-3", "t7-t8" → "T7-8".
    private static func levelText(_ s: String) -> String {
        let u = s.uppercased()
        let parts = u.split(separator: "-").map(String.init)
        if parts.count == 2, let a = parts[0].first, let b = parts[1].first, a == b, b.isLetter {
            return parts[0] + "-" + String(parts[1].dropFirst())
        }
        return u
    }

    private static func isRatio(_ s: String) -> Bool {
        let a = Array(s)
        return a.count == 3 && isDigit(a[0]) && a[1] == ":" && isDigit(a[2])
    }

    private static func isPLevel(_ s: String) -> Bool {
        let a = Array(s)
        return a.count == 2 && a[0] == "p" && isDigit(a[1])
    }

    private static func splitWord(_ word: String) -> [String] {
        var w = word
        while w.count > 1, let last = w.last, last == "." || last == ":" { w.removeLast() }
        let low = w.lowercased()
        if ["b/l", "bil", "bilat"].contains(low) { return ["bilat"] }
        if ["l/min", "l/m", "lpm"].contains(low) { return ["lpm"] }
        if low.hasSuffix("l/min"), isNumber(String(low.dropLast(5))) { return [String(low.dropLast(5)), "lpm"] }
        if low.contains("/") {
            let parts = low.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2, isLevel(parts[0]), (1...2).contains(parts[1].count), parts[1].allSatisfy({ isDigit($0) }) {
                return [parts[0] + "-" + parts[1]]
            }
            var out: [String] = []
            for (i, p) in w.split(separator: "/", omittingEmptySubsequences: false).enumerated() {
                if i > 0 { out.append("/") }
                if !p.isEmpty { out += splitWord(String(p)) }
            }
            return out
        }
        if low.contains("-"), !isLevel(low) {
            let joined = low.replacingOccurrences(of: "-", with: "")
            if Lexicon.joinable.contains(joined) || isPLevel(joined) { return [joined] }
            var out: [String] = []
            for p in w.split(separator: "-") where !p.isEmpty { out += splitWord(String(p)) }
            return out
        }
        // A number run into its unit: 16ga, 25f, 23cm, 5400rpm, 100%.
        let lead = low.prefix { isDigit($0) || $0 == "." }.count
        if lead > 0, lead < low.count, isNumber(String(low.prefix(lead))),
           low.dropFirst(lead).allSatisfy({ $0.isLetter || $0 == "%" }) {
            return [String(w.prefix(lead)), String(w.dropFirst(lead))]
        }
        return [w]
    }

    private static func classify(_ words: [String]) -> [DeviceToken] {
        var out: [DeviceToken] = []
        let lows = words.map { $0.lowercased() }
        let n = words.count
        var i = 0
        outer: while i < n {
            for len in [3, 2] where i + len <= n {
                if let toks = Lexicon.phrases[lows[i..<(i + len)].joined(separator: " ")] {
                    let raw = words[i..<(i + len)].joined(separator: " ")
                    out += toks.map { DeviceToken(tok: $0, raw: raw) }
                    i += len
                    continue outer
                }
            }
            let w = words[i], low = lows[i]
            if low == "impella" {
                out.append(DeviceToken(tok: .kind(.impella, nil), raw: w))
                if i + 1 < n, var m = Lexicon.impellaModels[lows[i + 1]] {
                    var step = 2
                    if m == "RP", i + 2 < n, lows[i + 2] == "flex" { m = "RP Flex"; step = 3 }
                    out.append(DeviceToken(tok: .model(m), raw: words[i + 1]))
                    i += step
                } else {
                    i += 1
                }
                continue
            }
            if low == "heartmate" || low == "hm" {
                out.append(DeviceToken(tok: .kind(.lvad, nil), raw: w))
                let next = i + 1 < n ? lows[i + 1] : ""
                var model: String?
                if next == "3" || next == "iii" { model = "HeartMate 3" } else if next == "2" || next == "ii" { model = "HeartMate II" }
                if let model {
                    out.append(DeviceToken(tok: .model(model), raw: words[i + 1]))
                    i += 2
                } else {
                    i += 1
                }
                continue
            }
            if let toks = Lexicon.words[low] {
                out += toks.map { DeviceToken(tok: $0, raw: w) }
            } else if low.count >= 3, let f = low.first, f == "r" || f == "l", let base = Lexicon.compounds[String(low.dropFirst())] {
                out.append(DeviceToken(tok: .site(base, f == "r" ? "right" : "left"), raw: w))
            } else if isLevel(low) {
                out.append(DeviceToken(tok: .level(levelText(low)), raw: w))
            } else if isRatio(low) {
                out.append(DeviceToken(tok: .ratio(low), raw: w))
            } else if isPLevel(low) {
                out.append(DeviceToken(tok: .pLevel(String(low.dropFirst())), raw: w))
            } else if isNumber(low), let v = Double(low) {
                out.append(DeviceToken(tok: .number(v, w), raw: w))
            } else {
                out.append(DeviceToken(tok: .word, raw: w))
            }
            i += 1
        }
        return out
    }

    // MARK: Settings

    private static func readSettings(_ t: [DeviceToken], _ used: inout [Bool], _ settings: inout [String: String]) {
        let n = t.count
        func isSep(_ j: Int) -> Bool {
            if case .sep = t[j].tok { return true }
            return false
        }
        func number(_ j: Int) -> String? {
            if j < n, case .number(_, let s) = t[j].tok { return s }
            return nil
        }
        func unit(_ j: Int) -> String? {
            if j < n, case .unit(let u) = t[j].tok { return u }
            return nil
        }
        func addIssue(_ s: String) {
            if let old = settings["issues"] { settings["issues"] = old + "; " + s } else { settings["issues"] = s }
        }
        /// The words up to the next separator, from j.
        func rest(from j: Int) -> (text: String, end: Int) {
            var k = j
            var parts: [String] = []
            while k < n, !isSep(k) {
                if !used[k] { parts.append(t[k].raw); used[k] = true }
                k += 1
            }
            return (parts.joined(separator: " "), k)
        }
        var i = 0
        while i < n {
            if used[i] { i += 1; continue }
            switch t[i].tok {
            case .setting(let key):
                used[i] = true
                if textSettings.contains(key) {
                    let r = rest(from: i + 1)
                    if !r.text.isEmpty {
                        if key == "issues" { addIssue(r.text) } else { settings[key] = r.text }
                    }
                    i = r.end
                    continue
                }
                if let v = number(i + 1) {
                    settings[key] = v
                    used[i + 1] = true
                    if let u = unit(i + 2), u != "G", u != "Fr" { used[i + 2] = true }
                    i += 2
                    continue
                }
            case .number(_, let s):
                if let u = unit(i + 1), let key = unitSettings[u] {
                    if settings[key] == nil { settings[key] = s }
                    used[i] = true
                    used[i + 1] = true
                    i += 2
                    continue
                }
            case .at:
                if let v = number(i + 1) {
                    if settings["depth"] == nil { settings["depth"] = v }
                    used[i] = true
                    used[i + 1] = true
                    if unit(i + 2) == "cm" { used[i + 2] = true }
                    i += 2
                    continue
                }
            case .ratio(let r):
                settings["ratio"] = r
                used[i] = true
            case .pLevel(let p):
                settings["pLevel"] = p
                used[i] = true
            case .level(let l):
                settings["level"] = l
                used[i] = true
            case .depthAt(let a):
                settings["depthAt"] = a
                used[i] = true
            case .issue:
                let r = rest(from: i)
                addIssue(r.text)
                i = r.end
                continue
            default:
                break
            }
            i += 1
        }
    }

    // MARK: One device

    /// The site an ambiguous word means for this device: (site, 2 said outright, 1 read from the device or the unit,
    /// 0 a guess).
    private static func resolve(_ base: String, kind: DeviceKind?, unit: String?, art: Bool, block: Bool, model: String?) -> (String, Int) {
        let arterialDevice = art || (kind.map { arterialKinds.contains($0) } ?? false)
        let blockDevice = block || kind == .block || kind == .perineuralCatheter
        switch base {
        case "fa":
            if arterialDevice { return ("femoral-artery", 1) }
            if kind == .piv || unit == "G" { return ("forearm", 1) }
            if unit == "Fr" { return ("femoral-artery", 1) }
            if kind != nil { return ("femoral-artery", 0) }
            return ("forearm", 0)
        case "femoral":
            if blockDevice { return ("femoral-block", 1) }
            if kind == .impella, model?.hasPrefix("RP") == true { return ("femoral-vein", 1) }
            if arterialDevice { return ("femoral-artery", 1) }
            if let k = kind, venousKinds.contains(k) { return ("femoral-vein", 1) }
            if unit == "Fr" { return ("femoral-vein", 1) }
            if unit == "G" { return ("femoral-artery", 1) }
            return ("femoral-vein", 0)
        case "axillary":
            if arterialDevice { return ("axillary-artery", 1) }
            if blockDevice { return ("axillary-block", 1) }
            if unit != nil || kind != nil { return ("axillary-artery", 0) }
            return ("axillary-block", 0)
        default:
            return (base, 2)
        }
    }

    private static func place(_ p: inout DeviceParse, _ base: String?, _ side: String?) {
        p.baseSite = base
        guard let base else { p.site = nil; p.side = nil; return }
        if !DeviceSite.isPaired(base) {
            p.site = DeviceSite.site(id: base) == nil ? nil : base
            p.side = nil
            return
        }
        if let s = side, s == "right" || s == "left" {
            p.site = base + "-" + s
            p.side = s
        } else {
            p.site = nil
            p.side = side == "both" ? "both" : nil
        }
    }

    private static func parseSingle(_ t: [DeviceToken]) -> DeviceParse? {
        let n = t.count
        var used = Array(repeating: false, count: n)
        var settings: [String: String] = [:]
        readSettings(t, &used, &settings)

        var kinds: [(kind: DeviceKind, detail: String?, at: Int)] = []
        var sites: [(base: String, side: String?, at: Int)] = []
        var limbs: [(limb: DeviceLimb, side: String?, at: Int)] = []
        var sides: [(side: String, at: Int)] = []
        var models: [String] = []
        var hasBlock = false, hasCath = false
        for (i, token) in t.enumerated() {
            switch token.tok {
            case .kind(let k, let d): kinds.append((k, d, i))
            case .site(let b, let s): sites.append((b, s, i))
            case .limb(let l, let s): limbs.append((l, s, i))
            case .side(let s): sides.append((s, i))
            case .model(let m): models.append(m)
            case .blockWord: hasBlock = true
            case .cathWord: hasCath = true
            default: break
            }
        }
        let kindNames = kinds.map { $0.kind }
        let art = kindNames.contains(.arterial)
        let model = models.first
        var penalty = 0.0

        // Size: the first number left over, with the unit right after it.
        var size = ""
        var unit: String?
        var sizeAt: Int?
        for i in 0..<n where !used[i] {
            if case .number(_, let s) = t[i].tok {
                size = s
                sizeAt = i
                used[i] = true
                if i + 1 < n, !used[i + 1], case .unit(let u) = t[i + 1].tok, ["G", "Fr", "mm"].contains(u) {
                    unit = u
                    used[i + 1] = true
                }
                break
            }
        }

        // Kind: the device word, by priority.
        var found = priority.first { kindNames.contains($0) }
        let explicit = found != nil
        if let k = found {
            let clash = kindNames.contains { $0 != k && !($0 == .cvc && k == .pac) && !($0 == .arterial && arterialKinds.contains(k)) }
            if clash { penalty += 0.2 }
        }
        let first = sites.first
        let blockSite = first.map { DeviceSite.kinds(forBase: $0.base).first == .block } ?? false
        let blockWordSite = hasBlock && (first.map { $0.base == "femoral" || $0.base == "axillary" } ?? false)
        if found == nil, blockSite || blockWordSite {
            found = hasCath ? .perineuralCatheter : .block
            if !hasBlock && !hasCath { penalty += 0.1 }
        }

        // Site.
        var base: String?
        var how = 2
        if let f = first {
            let r = resolve(f.base, kind: found, unit: unit, art: art, block: hasBlock, model: model)
            base = r.0
            how = r.1
            if how == 1 && !explicit { penalty += 0.05 }
            if how == 0 { penalty += 0.3 }
        }
        if found == nil {
            if let b = base {
                let cands = DeviceSite.kinds(forBase: b)
                var k = cands.first ?? .other
                if unit == "G", let g = cands.first(where: { $0 == .piv || $0 == .arterial || $0 == .intraosseous }) {
                    k = g
                } else if unit == "Fr", let f = cands.first(where: { $0.sizeUnit == "Fr" }) {
                    k = f
                }
                found = k
                penalty += 0.1
            } else if !limbs.isEmpty {
                found = .piv
                penalty += 0.1
            } else if settings["level"] != nil {
                found = .epidural
                penalty += 0.3
            } else if gauges.contains(size), unit == nil || unit == "G" {
                found = .piv
                penalty += 0.6
            }
        }
        guard let kind = found else { return nil }

        // Side: the site's own, else the nearest side word (before it first), else the limb's.
        var side = first?.side
        if side == nil, !sides.isEmpty {
            let ref = first?.at ?? limbs.first?.at ?? n
            if let b = sides.last(where: { $0.at < ref }) { side = b.side } else if let a = sides.first(where: { $0.at > ref }) { side = a.side }
        }
        if side == nil { side = limbs.first?.side }
        for i in 0..<n {
            switch t[i].tok {
            case .side, .limb, .site, .kind, .model, .blockWord, .cathWord, .via, .at, .filler, .unit, .sep: used[i] = true
            default: break
            }
        }
        if base == nil {
            if let d = defaultSite(for: kind, limb: limbs.first?.limb, level: settings["level"]) {
                base = d.site
                if !d.sure { penalty += 0.15 }
            } else if kind != .other {
                penalty += 0.3
            }
        }
        var p = DeviceParse(kind: kind)
        place(&p, base, side)
        let sideMissing = base.map { DeviceSite.isPaired($0) } == true && side != "right" && side != "left" && side != "both"
        if sideMissing { penalty += 0.25 }

        // Detail: the model, the device words' types, detail words, then anything not understood.
        var details: [String] = []
        if let model { details.append(model) }
        var kindDetails = kinds.compactMap { $0.detail }
        if kind == .pac {
            let intro = kindDetails.filter { introducers.contains($0) }
            if !intro.isEmpty {
                var name = intro.contains("MAC introducer") ? "MAC introducer" : (intro.last { $0 != "introducer" } ?? "introducer")
                let introAt = kinds.filter { k in k.detail.map { introducers.contains($0) } ?? false }.map { $0.at }
                if !size.isEmpty, unit == nil || unit == "Fr", let at = sizeAt, introAt.contains(where: { abs($0 - at) <= 2 }) {
                    name = size + " Fr " + name
                    size = ""
                    unit = nil
                }
                details.append(name)
            }
            kindDetails.removeAll { introducers.contains($0) }
        }
        if kindDetails.contains("MAC introducer") { kindDetails.removeAll { $0 == "introducer" } }
        for d in kindDetails where !details.contains(d) { details.append(d) }
        for i in 0..<n where !used[i] {
            if case .detail(let d) = t[i].tok {
                if !details.contains(d) { details.append(d) }
                used[i] = true
            }
        }
        if kind == .ett {
            if let i = details.firstIndex(of: "double lumen") {
                details.remove(at: i)
                if !details.contains("DLT") { details.append("DLT") }
            }
            if let i = details.firstIndex(of: "DLT"), let s = side, s == "left" || s == "right" {
                details[i] = (s == "left" ? "Left" : "Right") + " DLT"
            }
            if settings["depth"] == nil {
                for i in 0..<n where !used[i] {
                    if case .number(let v, let s) = t[i].tok, v >= 10 {
                        settings["depth"] = s
                        used[i] = true
                        break
                    }
                }
            }
        }
        if let issues = settings["issues"] {
            details.append(issues)
            settings["issues"] = nil
        }
        var unknown: [String] = []
        for i in 0..<n where !used[i] {
            switch t[i].tok {
            case .word, .number, .issue: unknown.append(t[i].raw)
            default: break
            }
        }
        if !unknown.isEmpty {
            details.append(unknown.joined(separator: " "))
            penalty += min(0.3, 0.1 * Double(unknown.count))
        }
        p.detail = details.joined(separator: ", ")
        p.size = size
        p.settings = settings
        p.confidence = score(1 - penalty)

        // Alternatives: the other readings of an ambiguous site word, then each side when the side is missing.
        if let f = first, how == 0 {
            let others: [String]
            switch f.base {
            case "fa": others = ["femoral-artery", "forearm"]
            case "femoral": others = ["femoral-vein", "femoral-artery", "femoral-block"]
            default: others = ["axillary-block", "axillary-artery"]
            }
            for b in others where b != base {
                var a = p
                a.alternatives = []
                a.companions = []
                a.kind = DeviceSite.kinds(forBase: b).first ?? kind
                place(&a, b, side)
                a.confidence = score(p.confidence - 0.1)
                p.alternatives.append(a)
            }
        }
        if sideMissing, let b = base {
            for s in ["right", "left"] {
                var a = p
                a.alternatives = []
                a.companions = []
                place(&a, b, s)
                p.alternatives.append(a)
            }
        }
        if p.side == "both", let b = base {
            var left = p
            left.alternatives = []
            place(&p, b, "right")
            place(&left, b, "left")
            p.companions = [left]
        }
        return p
    }

    // MARK: ECMO

    private struct Chunk {
        var size = ""
        var base: String?
        var side: String?
        var role: String?
        var details: [String] = []
        var isEmpty: Bool { size.isEmpty && base == nil && role == nil && details.isEmpty }
    }

    private static func parseECMO(_ t: [DeviceToken]) -> DeviceParse {
        let n = t.count
        var used = Array(repeating: false, count: n)
        var settings: [String: String] = [:]
        readSettings(t, &used, &settings)
        var mode: String?
        var central = false
        var chunks: [Chunk] = []
        var cur = Chunk()
        var unknown: [String] = []
        var pendingSide: String?
        func close() {
            if !cur.isEmpty { chunks.append(cur) }
            cur = Chunk()
        }
        func setRole(_ r: String) {
            if cur.role != nil { close() }
            cur.role = r
        }
        func setSite(_ b: String, _ s: String?) {
            if cur.base != nil { close() }
            cur.base = b
            cur.side = s ?? pendingSide
            pendingSide = nil
        }
        // A cannula is a run of size, site, role and details; a separator, or a second size, site or role, starts the next.
        for i in 0..<n where !used[i] {
            used[i] = true
            switch t[i].tok {
            case .mode(let m): mode = m
            case .kind(.ecmoDrainage, _): setRole("drainage")
            case .kind(.ecmoReturn, _), .kind(.arterial, _): setRole("return")
            case .kind(.cvc, .none): central = true
            case .role(let r): setRole(r)
            case .sep: close()
            case .number(_, let s):
                if !cur.size.isEmpty { close() }
                cur.size = s
                if i + 1 < n, case .unit = t[i + 1].tok { used[i + 1] = true }
            case .site(let b, let s): setSite(b, s)
            case .side(let s): pendingSide = s
            case .detail(let d): cur.details.append(d)
            case .word:
                if t[i].raw.lowercased() == "ra" { setSite("right-atrium", nil) } else { unknown.append(t[i].raw) }
            default: break
            }
        }
        close()

        var penalty = 0.0
        for k in chunks.indices where chunks[k].role == nil && ecmoVessel(chunks[k].base) == "arterial" { chunks[k].role = "return" }
        let unroled = chunks.indices.filter { chunks[$0].role == nil }
        if !unroled.isEmpty {
            let hasDrainage = chunks.contains { $0.role == "drainage" }
            let hasReturn = chunks.contains { $0.role == "return" }
            let arterialReturn = chunks.contains { $0.role == "return" && ecmoVessel($0.base) == "arterial" }
            if mode == "VAV", unroled.count >= 2, !hasDrainage {
                for (j, k) in unroled.enumerated() { chunks[k].role = j == 0 ? "drainage" : "return" }
            } else if mode == "VA" || mode == "VAV" || arterialReturn {
                for k in unroled {
                    if ecmoVessel(chunks[k].base) == "venous" || !chunks.contains(where: { $0.role == "drainage" }) {
                        chunks[k].role = "drainage"
                    } else if !chunks.contains(where: { $0.role == "return" }) {
                        chunks[k].role = "return"
                    } else {
                        chunks[k].role = "drainage"
                    }
                }
            } else if !hasDrainage, !hasReturn, unroled.count >= 2 {
                // VV with no roles given: the larger cannula drains, then the femoral one, then the first listed.
                func rank(_ c: Chunk) -> (Double, Int) { (Double(c.size) ?? 0, c.base == "femoral-vein" || c.base == "femoral" ? 1 : 0) }
                var best = unroled[0]
                for k in unroled where rank(chunks[k]) > rank(chunks[best]) { best = k }
                for k in unroled { chunks[k].role = k == best ? "drainage" : "return" }
                penalty += 0.15
            } else if !hasDrainage {
                for (j, k) in unroled.enumerated() { chunks[k].role = j == 0 ? "drainage" : "return" }
                if unroled.count > 1 { penalty += 0.15 }
            } else {
                for k in unroled { chunks[k].role = hasReturn ? "drainage" : "return" }
            }
        }
        if chunks.isEmpty {
            var p = DeviceParse(kind: .ecmoDrainage)
            p.settings = settings
            if let mode { p.settings["mode"] = mode }
            p.confidence = 0.4
            return p
        }
        var parses: [DeviceParse] = []
        for c in chunks {
            let kind: DeviceKind = c.role == "drainage" ? .ecmoDrainage : .ecmoReturn
            var base = c.base
            switch base {
            case "fa"?: base = "femoral-artery"
            case "femoral"?: base = kind == .ecmoReturn && mode != "VV" ? "femoral-artery" : "femoral-vein"
            case "axillary"?: base = "axillary-artery"
            default: break
            }
            if base == nil, central { base = kind == .ecmoDrainage ? "right-atrium" : "aorta" }
            var q = DeviceParse(kind: kind)
            q.size = c.size
            q.detail = c.details.joined(separator: ", ")
            if let b = base {
                place(&q, b, c.side)
                if DeviceSite.isPaired(b), c.side != "right", c.side != "left" { penalty += 0.1 }
            } else {
                if kind == .ecmoDrainage {
                    q.baseSite = "femoral-vein"
                } else if mode == "VV" {
                    q.baseSite = "ij"
                } else if mode != nil {
                    q.baseSite = "femoral-artery"
                }
                penalty += 0.1
            }
            if q.size.isEmpty { penalty += 0.05 }
            parses.append(q)
        }
        let ordered = parses.filter { $0.kind == .ecmoDrainage } + parses.filter { $0.kind == .ecmoReturn }
        var p = ordered[0]
        p.companions = Array(ordered.dropFirst())
        p.settings = settings
        if let mode { p.settings["mode"] = mode }
        if !unknown.isEmpty {
            penalty += min(0.3, 0.1 * Double(unknown.count))
            p.detail = [p.detail, unknown.joined(separator: " ")].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        let c = score(1 - penalty)
        p.confidence = c
        for k in p.companions.indices { p.companions[k].confidence = c }
        return p
    }
}

// MARK: - Vocabulary

private enum DeviceTok: Equatable {
    case side(String)
    case limb(DeviceLimb, String?)
    case site(String, String?)
    case kind(DeviceKind, String?)
    case model(String)
    case blockWord, cathWord
    case number(Double, String)
    case unit(String)
    case setting(String)
    case pLevel(String)
    case ratio(String)
    case level(String)
    case ecmo
    case mode(String)
    case role(String)
    case depthAt(String)
    case detail(String)
    case at, via, sep, filler, issue, word
}

private struct DeviceToken {
    var tok: DeviceTok
    /// The word(s) as typed.
    var raw: String
}

private enum Lexicon {
    /// Single words, lowercased. Site words with no side ("fa", "femoral", "axillary") are resolved by the parser.
    static let words: [String: [DeviceTok]] = {
        var d: [String: [DeviceTok]] = [:]
        func v(_ keys: String, _ toks: DeviceTok...) { for k in keys.split(separator: "|") { d[String(k)] = toks } }
        v("r|rt|right", .side("right"))
        v("l|lt|left", .side("left"))
        v("b|bilat|bilateral|bl|both", .side("both"))
        v("ue|arm", .limb(.upper, nil))
        v("le|leg", .limb(.lower, nil))
        v("rue", .limb(.upper, "right"))
        v("lue", .limb(.upper, "left"))
        v("rle", .limb(.lower, "right"))
        v("lle", .limb(.lower, "left"))
        v("ac|acf|antecubital", .site("antecubital", nil))
        v("fa", .site("fa", nil))
        v("forearm", .site("forearm", nil))
        v("hand|dorsum", .site("hand", nil))
        v("wrist", .site("wrist", nil))
        v("foot|pedal", .site("foot", nil))
        v("saph|saphenous", .site("saphenous", nil))
        v("scalp", .site("scalp", nil))
        v("ij|ijv|jugular", .site("ij", nil))
        v("sc|subclav|subclavian|scv", .site("subclavian", nil))
        v("ej|ejv", .site("ej", nil))
        v("fv", .site("femoral-vein", nil))
        v("fem|femoral", .site("femoral", nil))
        v("rad|radial", .site("radial", nil))
        v("brach|brachial", .site("brachial", nil))
        v("ax|axillary|axilla", .site("axillary", nil))
        v("dp", .site("dorsalis-pedis", nil))
        v("tib|tibia|tibial", .site("tibial-io", nil))
        v("hum|humerus|humeral", .site("humeral-io", nil))
        v("mouth|oral|orotracheal", .site("mouth", nil))
        v("nose|nasal|nasotracheal", .site("nose", nil))
        v("stoma", .site("trach", nil))
        v("heart|apex|apical", .site("heart", nil))
        v("atrium|atrial", .site("right-atrium", nil))
        v("aorta|aortic|ao", .site("aorta", nil))
        v("thoracic", .site("thoracic-spine", nil))
        v("lumbar", .site("lumbar-spine", nil))
        v("interscalene|isb", .site("interscalene", nil))
        v("supraclavicular|supraclav", .site("supraclavicular", nil))
        v("infraclavicular|infraclav", .site("infraclavicular", nil))
        v("fnb", .site("femoral-block", nil), .blockWord)
        v("acb|adductor", .site("adductor-canal", nil))
        v("popliteal|pop|sciatic", .site("popliteal", nil))
        v("tap", .site("tap", nil))
        v("esp", .site("esp", nil))
        v("pecs", .site("pecs", nil))
        v("pecs1|pecsi", .site("pecs", nil), .detail("PECS I"))
        v("pecs2|pecsii", .site("pecs", nil), .detail("PECS II"))
        v("serratus|sap", .site("pecs", nil), .detail("serratus"))
        v("pifb", .site("parasternal", nil), .detail("PIFB"))
        v("parasternal", .site("parasternal", nil))
        v("pvb|paravertebral", .site("esp", nil), .detail("paravertebral"))
        v("ql|qlb", .site("tap", nil), .detail("quadratus lumborum"))
        v("piv|pivs|iv|ivs|pivc|peripheral", .kind(.piv, nil))
        v("midline", .kind(.piv, "midline"))
        v("aline|art|arterial", .kind(.arterial, nil))
        v("cvc|cvl|central", .kind(.cvc, nil))
        v("tlc", .kind(.cvc, "triple lumen"))
        v("mac", .kind(.cvc, "MAC introducer"))
        v("introducer|intro", .kind(.cvc, "introducer"))
        v("cordis", .kind(.cvc, "Cordis"))
        v("sheath", .kind(.cvc, "sheath"))
        v("trialysis", .kind(.cvc, "Trialysis"))
        v("hd|dialysis|quinton|vascath|mahurkar", .kind(.cvc, "dialysis catheter"))
        v("swan|pac|swanganz", .kind(.pac, nil))
        v("picc", .kind(.picc, nil))
        v("io|ezio|intraosseous", .kind(.intraosseous, nil))
        v("ett|et|tube|ettube", .kind(.ett, nil))
        v("dlt", .kind(.ett, "DLT"))
        v("trach|tracheostomy|tracheotomy|trache", .kind(.trach, nil))
        v("lma", .kind(.other, "LMA"), .site("mouth", nil))
        v("sga", .kind(.other, "SGA"), .site("mouth", nil))
        v("igel", .kind(.other, "i-gel"), .site("mouth", nil))
        v("lvad|vad", .kind(.lvad, nil))
        v("hm3|hmiii", .kind(.lvad, nil), .model("HeartMate 3"))
        v("hm2|hmii", .kind(.lvad, nil), .model("HeartMate II"))
        v("hvad", .kind(.lvad, nil), .model("HVAD"))
        v("iabp|balloon", .kind(.iabp, nil))
        v("epidural|epi", .kind(.epidural, nil))
        v("tea|tec", .kind(.epidural, nil), .site("thoracic-spine", nil))
        v("cse", .kind(.epidural, "CSE"))
        v("dpe", .kind(.epidural, "DPE"))
        v("spinal|sab", .kind(.spinal, nil))
        v("itm", .kind(.spinal, "intrathecal morphine"))
        v("block|blocks|nerve", .blockWord)
        v("catheter|catheters|cath|caths|continuous", .cathWord)
        v("ecmo|ecls|cannula|cannulas|cannulae", .ecmo)
        v("vv", .mode("VV"))
        v("va|vva", .mode("VA"))
        v("vav", .mode("VAV"))
        v("drainage|drain|draining|inflow|venous", .role("drainage"))
        v("return|returning|reinfusion|outflow", .role("return"))
        v("avalon", .detail("Avalon dual lumen"))
        v("crescent", .detail("Crescent dual lumen"))
        v("g|ga|gauge", .unit("G"))
        v("f|fr|french", .unit("Fr"))
        v("cm", .unit("cm"))
        v("mm", .unit("mm"))
        v("lpm", .unit("L/min"))
        v("rpm", .unit("rpm"))
        v("w|watts|watt", .unit("W"))
        v("%", .unit("%"))
        v("mmhg", .unit("mmHg"))
        v("flow", .setting("flow"))
        v("sweep", .setting("sweep"))
        v("fdo2|fio2", .setting("fdo2"))
        v("pi", .setting("pi"))
        v("power|pwr", .setting("power"))
        v("speed", .setting("rpm"))
        v("aug|augmentation|augmenting", .setting("augmentation"))
        v("timing", .setting("timing"))
        v("p|plevel", .setting("pLevel"))
        v("position|pos", .setting("position"))
        v("depth", .setting("depth"))
        v("issue|issues", .setting("issues"))
        v("thrombus|clot|clots|fibrin|chatter|chattering|hemolysis|kink|kinked", .issue)
        v("at", .at)
        v("via|thru|through", .via)
        v("cuffed", .detail("cuffed"))
        v("uncuffed", .detail("uncuffed"))
        v("fenestrated", .detail("fenestrated"))
        v("shiley", .detail("Shiley"))
        v("portex", .detail("Portex"))
        v("bivona", .detail("Bivona"))
        v("teeth", .depthAt("teeth"))
        v("lip|lips", .depthAt("lip"))
        v("gums|gum", .depthAt("gums"))
        v("nare|naris", .depthAt("nare"))
        v("skin", .depthAt("skin"))
        v("/", .sep)
        v("in|the|of|and|with|x|placed|new|old|existing|on|to|a|an|line|lines|is|for|site|ganz|flex|single|shot|vein|v|artery|cannulation", .filler)
        return d
    }()

    /// Two- and three-word phrases, lowercased; they win over their single words.
    static let phrases: [String: [DeviceTok]] = {
        var d: [String: [DeviceTok]] = [:]
        func v(_ keys: String, _ toks: DeviceTok...) { for k in keys.split(separator: "|") { d[String(k)] = toks } }
        v("central venous catheter|central venous line|central venous", .kind(.cvc, nil))
        v("pulmonary artery catheter|pa catheter|pa cath|pa line|swan ganz", .kind(.pac, nil))
        v("double lumen tube", .kind(.ett, "DLT"))
        v("at the teeth", .depthAt("teeth"))
        v("at the lip|at the lips", .depthAt("lip"))
        v("art line|arterial line|a line|art cath|arterial catheter", .kind(.arterial, nil))
        v("central line", .kind(.cvc, nil))
        v("triple lumen|3 lumen", .kind(.cvc, "triple lumen"))
        v("quad lumen", .kind(.cvc, "quad lumen"))
        v("double lumen|dual lumen", .detail("double lumen"))
        v("hd cath|hd catheter|hd line|dialysis cath|dialysis catheter|dialysis line", .kind(.cvc, "dialysis catheter"))
        v("fem art|femoral art|femoral artery|fem artery", .site("femoral-artery", nil))
        v("fem vein|femoral vein|fem v", .site("femoral-vein", nil))
        v("internal jugular", .site("ij", nil))
        v("external jugular", .site("ej", nil))
        v("upper arm", .site("upper-arm", nil))
        v("dorsalis pedis", .site("dorsalis-pedis", nil))
        v("radial artery|radial art|rad art", .site("radial", nil), .kind(.arterial, nil))
        v("brachial artery|brachial art", .site("brachial", nil), .kind(.arterial, nil))
        v("axillary artery|axillary art|ax art", .site("axillary-artery", nil))
        v("subclavian vein", .site("subclavian", nil))
        v("adductor canal", .site("adductor-canal", nil))
        v("erector spinae", .site("esp", nil))
        v("serratus anterior", .site("pecs", nil), .detail("serratus"))
        v("single shot", .blockWord)
        v("balloon pump", .kind(.iabp, nil))
        v("v ecmo", .kind(.ecmoDrainage, nil))
        v("a ecmo", .kind(.ecmoReturn, nil))
        v("at teeth", .depthAt("teeth"))
        v("at lip|at lips", .depthAt("lip"))
        v("chest tube", .kind(.other, "chest tube"))
        v("on arrival")
        v("right atrium", .site("right-atrium", nil))
        return d
    }()

    /// Site words that run together with a side: "rij", "lsc", "rfv", "lac", "rfa".
    static let compounds: [String: String] = ["ij": "ij", "ijv": "ij", "sc": "subclavian", "scv": "subclavian", "ej": "ej",
                                              "fv": "femoral-vein", "fa": "fa", "ac": "antecubital", "fem": "femoral",
                                              "rad": "radial", "dp": "dorsalis-pedis", "ax": "axillary", "brach": "brachial"]

    static let impellaModels: [String: String] = ["cp": "CP", "2.5": "2.5", "5.0": "5.0", "5": "5.0", "5.5": "5.5", "rp": "RP",
                                                  "ecp": "ECP", "rpflex": "RP Flex"]

    /// Hyphenated words read joined up ("a-line", "v-v", "i-gel", "hm-3"); other hyphens split words.
    static let joinable: Set<String> = ["aline", "vv", "va", "vav", "vva", "igel", "hm3", "hmii", "hmiii", "hm2", "pecsii",
                                        "pecsi", "pecs1", "pecs2", "ezio", "rpflex", "swanganz"]
}
