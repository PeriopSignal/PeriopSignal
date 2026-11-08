import SwiftUI

// MARK: - Lines & devices on the patient diagram
//
// PatientDiagramModel turns the record into what PatientDiagramCanvas draws: the airway (from the current airway and
// the intraoperative course), the lines and devices (PatientDevice), the ECMO circuit to its cart, and the blocks and
// neuraxial techniques (read from the Regional list). PatientDevicesEditor adds and edits them: tap a body point,
// type shorthand ("20 rue", "RIJ introducer"), or use the type buttons; hold an item to drag it or to delete it, and Undo steps back.

enum PatientDiagramModel {
    enum Phase: String { case preop, intraop, all }

    /// The id of a limb alert's marker is this and the limb ("limb-alert-arm-left").
    static let limbAlertPrefix = "limb-alert-"

    /// Fractions of the figure box to figure units.
    static func pt(_ f: CGPoint) -> CGPoint { CGPoint(x: f.x * 200, y: f.y * 420) }

    static let svc = CGPoint(x: 100, y: 84)
    static let ivc = CGPoint(x: 101, y: 168)
    static let ra = CGPoint(x: 98, y: 101)
    static let rv = CGPoint(x: 104, y: 108)
    static let pa = CGPoint(x: 107, y: 90)
    static let descendingAorta = CGPoint(x: 103, y: 92)
    static let lv = CGPoint(x: 109, y: 106)
    static let cart = CGPoint(x: 208, y: 330)

    static func color(_ role: DeviceColorRole) -> Color {
        switch role {
        case .line: return DiagramColor.peripheral
        case .central: return DiagramColor.central
        case .pac: return DiagramColor.pac
        case .venousECMO: return DiagramColor.venousECMO
        case .arterialECMO: return DiagramColor.arterialECMO
        case .pump: return DiagramColor.pump
        case .neuraxial: return DiagramColor.neuraxial
        case .needle: return DiagramColor.needle
        case .airway: return DiagramColor.airway
        case .pacing: return DiagramColor.pacing
        case .access: return DiagramColor.access
        case .drain: return DiagramColor.drain
        }
    }

    /// The tiny label: "PIV 20G", "CVL 8.5Fr", "IABP 1:1".
    static func tag(_ d: PatientDevice) -> String {
        let unit = d.kind.sizeUnit == "mm ID" ? "" : d.kind.sizeUnit
        let size = d.size.isEmpty ? "" : " " + d.size + unit
        switch d.kind {
        case .arterial: return "A-line" + size
        case .ecmoDrainage: return "V" + size
        case .ecmoReturn: return "A" + size
        case .iabp: return "IABP" + (d.settings["ratio"].map { " " + $0 } ?? "")
        case .impella: return "Impella" + (d.detail.isEmpty ? "" : " " + d.detail) + (d.settings["pLevel"].map { " " + $0 } ?? "")
        case .lvad: return "LVAD" + (d.settings["rpm"].map { " " + $0 } ?? "")
        case .protekDuo: return "ProtekDuo" + size
        // 1.9: the tags that fit the label column (15 characters).
        case .epicardialWires:
            let c = PatientDevices.chamberWords(d)
            return "Epi wires" + (c.isEmpty ? "" : " " + c.map { $0 == "atrial" ? "A" : "V" }.joined(separator: "+"))
        case .cied:
            let t = d.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "PPM/ICD" : (t.lowercased() == "pacemaker" ? "PPM" : t)
        case .avFistula: return d.detail.range(of: "graft", options: .caseInsensitive) != nil ? "AV graft" : "AVF"
        case .dialysisCatheter: return "HD cath" + size
        case .chestTube: return "Chest tube" + size
        default: return d.kind.label + size
        }
    }

    /// The leads of a pacemaker or ICD (1.9): from the pocket under the clavicle, medial to the vein and down to the
    /// right ventricle.
    private static func generatorLeads(from a: CGPoint) -> [CGPoint] {
        let left = a.x < 100
        // The points are off the hub points, so a lead is not spread with the central lines.
        return [CGPoint(x: left ? 89 : 111, y: 78), CGPoint(x: left ? 98 : 102, y: 90), CGPoint(x: 103, y: 104), CGPoint(x: 106, y: 113)]
    }

    static func items(_ r: PatientRecord, phase: Phase) -> (items: [DiagramItem], cart: DiagramCart?) {
        var out: [DiagramItem] = []
        var perSite: [String: Int] = [:]
        func labelDY(_ key: String) -> CGFloat {
            let n = perSite[key, default: 0]
            perSite[key] = n + 1
            return CGFloat(n) * 7.5
        }

        // The airway: an ETT down the trachea, or a tracheostomy at the stoma.
        let intubatedHere = r.intubation == "easy" || r.intubation == "difficult" || r.intubation == PatientAirway.placed || !r.tube.isEmpty
        let ettNow: Bool = {
            switch phase {
            case .preop: return r.currentAirway == "ett"
            case .intraop, .all: return (r.currentAirway == "ett" || intubatedHere) && r.airwayAtEnd != "extubated"
            }
        }()
        if ettNow {
            var label = "ETT"
            if r.currentAirway == "ett" {
                if !r.ettSize.isEmpty { label += " " + r.ettSize }
                let depth: String = r.ettDepth.split(separator: " ").first.map(String.init) ?? ""
                if !depth.isEmpty { label += " @" + depth }
            } else if PatientAirway.tubeIsLMA(r) {
                // The LMA's size kept in `tube` ("LMA 4"), as typed.
                if let first = r.tube.split(separator: ",").first { label = String(first) }
            } else if !r.tube.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                label = ettLabel(tube: r.tube)
            }
            out.append(DiagramItem(id: "airway-ett", anchor: CGPoint(x: 100, y: 42), course: [CGPoint(x: 100, y: 53), CGPoint(x: 100, y: 74)],
                                   color: DiagramColor.airway, width: 2.2, marker: .dot, label: label, labelLeft: false, movable: false))
        } else if r.currentAirway == "trach" {
            out.append(DiagramItem(id: "airway-trach", anchor: CGPoint(x: 100, y: 62), course: [CGPoint(x: 100, y: 74)],
                                   color: DiagramColor.airway, width: 2.2, marker: .stoma, label: trachLabel(r), labelLeft: false, movable: false))
        }

        // Lines and devices.
        // What is in place now (PatientRecord.currentDevices): on arrival only for the preoperative picture; for the
        // others, on arrival and placed in the room, the same set as the handoff's Lines and Support.
        let devices = r.currentDevices(arrivalOnly: phase == .preop)
        var ecmo = false
        for d in devices {
            guard let f = d.position else { continue }
            let a = pt(f)
            let left = a.x < 100
            let c = color(d.colorRole)
            let region = d.siteInfo?.region ?? ""
            let fromBelow = region == "groin" || region == "leg" || region == "abdomen"
            var item = DiagramItem(id: d.id.uuidString, anchor: a, color: c, label: tag(d), labelLeft: left)
            item.labelDY = labelDY(d.site)
            switch d.kind {
            case .piv, .foley, .other:
                item.marker = .dot
            case .epicardialWires:
                // From the exit below the sternum to the chambers it paces: the atrial wire on the right atrial wall, the
                // ventricular on the right ventricle (off the hub points, so the lines are not spread with the central ones).
                let chambers = PatientDevices.chamberWords(d)
                let atrialTip = CGPoint(x: 93, y: 103), ventricularTip = CGPoint(x: 107, y: 113)
                item.dashed = true
                item.width = 1.5
                item.course = [CGPoint(x: a.x, y: a.y - 8), chambers.contains("atrial") && !chambers.contains("ventricular") ? atrialTip : ventricularTip]
                if chambers.contains("atrial") && chambers.contains("ventricular") {
                    out.append(DiagramItem(id: d.id.uuidString + "-atrial", anchor: a, course: [CGPoint(x: a.x - 3, y: a.y - 8), atrialTip],
                                           color: c, width: 1.5, dashed: true, marker: .none, label: "", labelLeft: left, movable: false))
                }
            case .cied:
                item.marker = .generator
                item.course = generatorLeads(from: a)
                item.width = 1.2
            case .avFistula:
                // A short bar along the limb the access runs in.
                item.marker = .dot
                let leg = region == "leg"
                item.course = [CGPoint(x: a.x + (leg ? 0 : (left ? 3 : -3)), y: a.y - (leg ? 16 : 14))]
                item.width = 3
            case .chestTube:
                // Into the pleural space: in and down from the chest wall.
                item.marker = .dot
                item.course = [CGPoint(x: a.x + (left ? 12 : -12), y: a.y + 12)]
                item.width = 2.4
            case .arterial:
                item.marker = .dot
            case .intraosseous:
                item.marker = .square
            case .cvc, .picc, .dialysisCatheter:
                item.course = fromBelow ? [CGPoint(x: (a.x + 100) / 2, y: a.y - 6), ivc] : (region == "arm" ? [CGPoint(x: left ? 70 : 130, y: 92), svc] : [svc])
                item.width = 2
            case .pac:
                item.course = (fromBelow ? [ivc] : [svc]) + [ra, rv, pa]
                item.width = 2
            case .ecmoDrainage, .ecmoReturn:
                ecmo = true
                item.course = [CGPoint(x: a.x, y: max(a.y, 300) + 6), CGPoint(x: cart.x - 27, y: cart.y + (d.kind == .ecmoDrainage ? -4 : 4))]
                item.width = 2.8
                // The intravascular part: a drainage cannula's tip in the right atrium, a femoral arterial return in the iliac.
                let tip: CGPoint? = d.kind == .ecmoDrainage ? ra : (region == "neck" ? ra : (region == "chest" ? CGPoint(x: 103, y: 88) : nil))
                if let tip {
                    out.append(DiagramItem(id: d.id.uuidString + "-tip", anchor: a, course: [tip], color: c.opacity(0.75), width: 1.6, dashed: true,
                                           marker: .none, label: "", labelLeft: left, movable: false))
                }
            case .lvad:
                item.marker = .pump
                item.course = [CGPoint(x: a.x + 4, y: 138), CGPoint(x: a.x + 10, y: 150)]
                item.dashed = true
                item.width = 1.2
            case .iabp:
                item.course = [ivc, CGPoint(x: descendingAorta.x, y: 140), descendingAorta]
                item.width = 1.4
                out.append(DiagramItem(id: d.id.uuidString + "-balloon", anchor: CGPoint(x: descendingAorta.x, y: 96), course: [CGPoint(x: descendingAorta.x, y: 132)],
                                       color: c, width: 4.5, marker: .none, label: "", labelLeft: left, movable: false))
            case .impella:
                item.course = (fromBelow ? [ivc, CGPoint(x: descendingAorta.x, y: 120)] : [CGPoint(x: left ? 80 : 120, y: 82)]) + [descendingAorta, CGPoint(x: 104, y: 86), lv]
                item.width = 1.6
                item.pumpAt = CGPoint(x: 106, y: 96)
            case .protekDuo:
                // From the right IJ through the right atrium and ventricle to the pulmonary artery: drainage ports
                // in the atrium, return at the tip.
                item.course = [svc, ra, rv, pa]
                item.width = 2.8
                item.pumpAt = ra
            case .ett, .trach, .epidural, .spinal, .block, .perineuralCatheter:
                item.marker = .dot
            }
            out.append(item)
        }

        // Limb alerts (1.9): a mark on each limb to spare, from an AV fistula or graft and from the user's list.
        for g in PatientDeviceFills.limbAlertGroups(r, arrivalOnly: phase == .preop) {
            guard let at = PatientDeviceFills.limbAnchor(g.limb) else { continue }
            out.append(DiagramItem(id: PatientDiagramModel.limbAlertPrefix + g.limb, anchor: at, color: DiagramColor.limbAlert, marker: .alert,
                                   label: "", labelLeft: at.x < 100,
                                   spoken: "Limb alert, " + PatientDeviceFills.limbWords(g.limb) + ": " + g.reasons.joined(separator: ", ")))
        }

        // Blocks and neuraxial techniques, from the Regional list (drawn, not dragged).
        for (i, b) in r.regional.enumerated() where !b.technique.isEmpty {
            let text = [b.side, b.technique, b.catheter ? "catheter" : ""].filter { !$0.isEmpty }.joined(separator: " ")
            guard let parse = PatientDevices.parse(text) else { continue }
            for (j, d) in parse.devices().enumerated() {
                let level = b.technique.range(of: #"[CTLS]\d{1,2}(-\d{1,2})?"#, options: .regularExpression).map { String(b.technique[$0]) }
                guard let f = (d.kind == .epidural || d.kind == .spinal) ? (level.flatMap { DeviceSite.spineAnchor(level: $0) } ?? d.position) : d.position else { continue }
                let a = pt(f)
                let catheter = d.kind == .epidural || d.kind == .perineuralCatheter
                var item = DiagramItem(id: "regional-\(i)-\(j)", anchor: a, color: catheter ? DiagramColor.neuraxial : DiagramColor.needle,
                                       width: 1, marker: catheter ? .dot : .needle, label: d.kind == .block || d.kind == .perineuralCatheter ? shortBlock(b.technique) : d.kind.label,
                                       labelLeft: a.x <= 100, movable: false)
                if catheter { item.course = [CGPoint(x: a.x + (a.x < 100 ? -1 : 1) * 4, y: a.y - 16)] }
                item.labelDY = labelDY("regional-" + d.site)
                out.append(item)
            }
        }

        var cartInfo: DiagramCart?
        if ecmo, let sys = PatientDevices.ecmoSystem(devices) {
            let flow = sys.settings["flow"].map { $0 + " L/min" } ?? ""
            let sweep = sys.settings["sweep"].map { "sweep " + $0 } ?? ""
            let title: String
            switch sys.configuration {
            case .vv: title = "VV ECMO"
            case .vaPeripheral: title = "VA ECMO"
            case .vaCentral: title = "Central VA"
            case .vav: title = "VAV ECMO"
            case .unknown: title = "ECMO"
            }
            cartInfo = DiagramCart(at: cart, title: title, detail: [flow, sweep].filter { !$0.isEmpty }.joined(separator: " · "))
        }
        fanOut(&out)
        layoutLabels(&out, cart: cartInfo?.at)
        return (out, cartInfo)
    }

    // MARK: Layout: lines side by side, labels in columns

    /// The points inside the chest that several lines run to (the SVC, IVC, heart chambers, PA and aorta).
    private static let hubs: [CGPoint] = [svc, ivc, ra, rv, pa, descendingAorta, lv]

    /// Lines that run to the same vessels are spread side by side, 2.6 figure units apart, so each stays visible
    /// instead of drawing over the others; the insertion points stay where they are.
    static func fanOut(_ items: inout [DiagramItem]) {
        func isHub(_ p: CGPoint) -> Bool { hubs.contains { abs($0.x - p.x) < 0.5 && abs($0.y - p.y) < 0.5 } }
        let central = items.indices.filter { i in items[i].course.contains(where: isHub) }
        guard central.count > 1 else { return }
        // Stable order: from the patient's right to left by insertion point, then by id.
        let order = central.sorted { (items[$0].anchor.x, items[$0].id) < (items[$1].anchor.x, items[$1].id) }
        let n = CGFloat(order.count)
        for (slot, i) in order.enumerated() {
            let dx = (CGFloat(slot) - (n - 1) / 2) * 2.6
            items[i].course = items[i].course.map { isHub($0) ? CGPoint(x: $0.x + dx, y: $0.y) : $0 }
            if let pump = items[i].pumpAt { items[i].pumpAt = CGPoint(x: pump.x + dx, y: pump.y) }
        }
    }

    /// Every label goes in a column beside the figure on its side, at the height of its insertion point, then the
    /// labels in each column are pushed apart so none overlap (and kept clear of the ECMO cart); a leader line joins
    /// each label to its line.
    static func layoutLabels(_ items: inout [DiagramItem], cart: CGPoint?) {
        let gap: CGFloat = 8.5
        let top: CGFloat = 6, bottom: CGFloat = 414
        for left in [true, false] {
            let idx = items.indices.filter { !items[$0].label.isEmpty && items[$0].labelLeft == left }
                .sorted { (items[$0].anchor.y, items[$0].anchor.x) < (items[$1].anchor.y, items[$1].anchor.x) }
            guard !idx.isEmpty else { continue }
            // The cart blocks part of the right column.
            let blocked: ClosedRange<CGFloat>? = (!left && cart != nil) ? (cart!.y - 17)...(cart!.y + 17) : nil
            var ys: [CGFloat] = []
            for i in idx {
                var y = max(items[i].anchor.y, (ys.last.map { $0 + gap }) ?? top)
                if let b = blocked, b.contains(y) { y = b.upperBound + gap / 2 }
                ys.append(y)
            }
            // Pull back up from the bottom if the column ran past the figure.
            if var last = ys.last, last > bottom {
                last = bottom
                ys[ys.count - 1] = last
                for j in stride(from: ys.count - 2, through: 0, by: -1) {
                    var y = min(ys[j], ys[j + 1] - gap)
                    if let b = blocked, b.contains(y) { y = b.lowerBound - gap / 2 }
                    ys[j] = max(top, y)
                }
            }
            for (j, i) in idx.enumerated() {
                items[i].labelAt = CGPoint(x: left ? -2 : 202, y: ys[j])
                items[i].labelDY = 0
                // Short enough for the column.
                if items[i].label.count > 15 { items[i].label = String(items[i].label.prefix(14)) + "…" }
            }
        }
    }

    /// The airway's tag from the typed Tube field, in the form of the ETT branch above: "8.0 cuffed ETT (23 cm)" and
    /// "7.5 ETT, 23 cm at the lip" read "ETT 8.0 @23", so the depth is kept and the tag fits the 15-character label column
    /// (review 1.10: the field's own prompt has no comma, and the whole entry was cut to "8.0 cuffed ETT…"). A double-lumen
    /// tube keeps its name ("DLT 37 Fr L" reads "DLT 37"). With no size to read, the text before the first comma or
    /// parenthesis, as typed.
    static func ettLabel(tube: String) -> String {
        let t = tube.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = t as NSString
        let number = "([0-9]+(?:\\.[0-9]+)?)"
        func first(_ pattern: String) -> NSTextCheckingResult? {
            (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?.firstMatch(in: t, range: NSRange(location: 0, length: ns.length))
        }
        // The depth: the number written before "cm"; the size: the first other number.
        let depthRange = first(number + "\\s*cm\\b")?.range(at: 1)
        let depth = depthRange.map { " @" + ns.substring(with: $0) } ?? ""
        var size: String?
        if let re = try? NSRegularExpression(pattern: number) {
            for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) where m.range != depthRange {
                size = ns.substring(with: m.range); break
            }
        }
        let dlt = first("\\b(DLT|double[- ]lumen)\\b") != nil
        let kind = dlt ? "DLT" : "ETT"
        if let size { return kind + " " + size + depth }
        // No size: the depth alone ("ETT @23"), else the words as typed.
        if !depth.isEmpty { return kind + depth }
        let head = t.split(whereSeparator: { $0 == "," || $0 == "(" }).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return head.isEmpty ? kind : head
    }

    private static func trachLabel(_ r: PatientRecord) -> String {
        let words: [Substring] = Array(r.trachType.split(separator: " ").prefix(2))
        return words.isEmpty ? "Trach" : "Trach " + words.joined(separator: " ")
    }

    /// "TAP", "Interscalene", "ESP": the block's name without the word "block".
    private static func shortBlock(_ t: String) -> String {
        let s = t.replacingOccurrences(of: " blocks", with: "").replacingOccurrences(of: " block", with: "")
        return s.count > 16 ? String(s.prefix(15)) + "…" : s
    }
}

/// The diagram as a card: read-only, for the tabs and the handoff.
struct PatientDiagramCard: View {
    @Environment(ReferenceStore.self) private var refs
    var record: PatientRecord
    var phase: PatientDiagramModel.Phase
    var height: CGFloat = 300
    /// The limb alerts listed under the figure (1.9); the handoff leaves them to its own text.
    var listsLimbAlerts = true
    /// The limb alerts above the figure rather than under it (1.10 review): on a card, safety content opens it, on the
    /// first screen, instead of after a 260-pt figure.
    var limbAlertsAbove = false

    enum Part: Hashable { case limbAlerts, figure }
    /// The card's parts, top to bottom.
    var parts: [Part] {
        guard listsLimbAlerts else { return [.figure] }
        return limbAlertsAbove ? [.limbAlerts, .figure] : [.figure, .limbAlerts]
    }

    /// The Preoperative tab's Lines & Devices card: the limb alerts first, then the figure of what the patient arrives with.
    static func preopCard(_ r: PatientRecord) -> PatientDiagramCard {
        PatientDiagramCard(record: r, phase: .preop, height: 260, limbAlertsAbove: true)
    }

    var body: some View {
        let order = parts
        VStack(alignment: .leading, spacing: 8) {
            if order.first == .limbAlerts { caption }
            if let fig = refs.bundle?.regional?.figure {
                let m = PatientDiagramModel.items(record, phase: phase)
                PatientDiagramCanvas(figure: fig, items: m.items, cart: m.cart, fillsWidth: true)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
            }
            if order.count > 1 && order.last == .limbAlerts { caption }
        }
    }

    private var caption: some View {
        LimbAlertCaption(groups: PatientDeviceFills.limbAlertGroups(record, arrivalOnly: phase == .preop))
    }
}

/// The lines and devices editor: the diagram, shorthand, type buttons and the list.
struct PatientDevicesEditor: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    var phase: PatientDiagramModel.Phase
    /// Mechanical support only: its add buttons and every setting on the page, without the lines.
    var supportOnly = false

    @State private var editing = false
    @State private var typed = ""
    @State private var tapOptions: [DeviceOption] = []
    @State private var showTapMenu = false
    @State private var editingID: UUID?
    @FocusState private var typing: Bool
    /// The item held on the diagram, for its actions.
    @State private var heldID: UUID?
    @State private var showHeldMenu = false
    /// The limb alert being added (1.9) and the one whose reasons are shown.
    @State private var alertLimb = "arm-left"
    @State private var alertReason = ""
    @State private var shownAlertLimb: String?

    private var r: PatientRecord { patient.record }
    private var placedIntraop: Bool { phase == .intraop }
    private var shown: [PatientDevice] { r.devices.filter { phase != .preop || !$0.placedIntraop } }
    private var parse: DeviceParse? { typed.trimmingCharacters(in: .whitespaces).count >= 2 ? PatientDevices.parse(typed) : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let fig = refs.bundle?.regional?.figure {
                let m = PatientDiagramModel.items(r, phase: phase == .preop ? .preop : .all)
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text(editing ? "Drag to move · tap × or − to delete" : "Tap to add · hold an item to drag it, or let go for Delete")
                            .font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button(action: undo) { Label("Undo", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(CapsuleButtonStyle(prominent: false))
                            .disabled(!patient.canUndo)
                            .opacity(patient.canUndo ? 1 : 0.4)
                            .accessibilityHint("Undoes the last change to this patient")
                        Button(editing ? "Done" : "Edit") { Haptics.light(); withAnimation(.snappy) { editing.toggle() } }
                            .buttonStyle(CapsuleButtonStyle(prominent: editing))
                    }
                    PatientDiagramCanvas(figure: fig, items: m.items, cart: m.cart, editing: editing,
                                         onTapFigure: { p in
                                             let f = CGPoint(x: p.x / 200, y: p.y / 420)
                                             tapOptions = DeviceSite.options(near: f, limit: 8, within: 36)
                                             if !tapOptions.isEmpty { showTapMenu = true }
                                         },
                                         onTapItem: { id in
                                             if id.hasPrefix(PatientDiagramModel.limbAlertPrefix) { shownAlertLimb = String(id.dropFirst(PatientDiagramModel.limbAlertPrefix.count)) }
                                             else { editingID = UUID(uuidString: id) }
                                         },
                                         onLongPress: { Haptics.light(); withAnimation(.snappy) { editing = true } },
                                         onMove: { id, by in move(id, by) },
                                         onDelete: { id in delete(id) },
                                         onHold: { id in
                                             guard let u = UUID(uuidString: id), r.devices.contains(where: { $0.id == u }) else { return }
                                             heldID = u
                                             showHeldMenu = true
                                         })
                        .frame(height: 430)
                        .confirmationDialog(heldID.flatMap { id in r.devices.first { $0.id == id }?.label } ?? "Device",
                                            isPresented: $showHeldMenu, titleVisibility: .visible) {
                            Button("Details") { editingID = heldID }
                            Button("Delete", role: .destructive) { if let id = heldID { delete(id.uuidString) } }
                            Button("Cancel", role: .cancel) {}
                        }
                }
                .padding(12)
                .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                .alert(shownAlertLimb.map { "Limb alert: " + PatientDeviceFills.limbName($0) } ?? "Limb alert",
                       isPresented: Binding(get: { shownAlertLimb != nil }, set: { if !$0 { shownAlertLimb = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(PatientDeviceFills.limbAlertGroups(r).first { $0.limb == shownAlertLimb }.map { $0.reasons.joined(separator: "\n") } ?? "")
                }
                .confirmationDialog("Add at this spot", isPresented: $showTapMenu, titleVisibility: .visible) {
                    ForEach(tapOptions) { o in
                        Button(o.label) { add([PatientDevice(kind: o.kind, site: o.site.id, side: o.site.side, placedIntraop: placedIntraop)], open: true) }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
            if supportOnly {
                supportButtons
                supportSettings
                shorthand
            } else {
                shorthand
                typeButtons
                list
                limbAlertsGroup
            }
        }
        .onAppear {
            #if DEBUG
            // Screenshot runs: -ps.devices.type "<shorthand>" types it into the field (1.8.1).
            let t = LaunchSeed.string("ps.devices.type")
            if !t.isEmpty, typed.isEmpty, !supportOnly { typed = t }
            #endif
        }
        .sheet(item: Binding(get: { editingID.map { IDBox(id: $0) } }, set: { editingID = $0?.id })) { box in
            DeviceDetailSheet(deviceID: box.id)
                .environment(patient)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private struct IDBox: Identifiable { var id: UUID }

    // MARK: Undo

    /// The store's Undo (PatientUndoHistory), as in the navigation bar: a tap, drag or delete is one step; typing
    /// within a second of the last change joins that step.
    private func undo() {
        guard patient.canUndo else { return }
        Haptics.light()
        withAnimation(.snappy) { patient.undo() }
    }

    // MARK: Typed shorthand

    /// What the shorthand field reads, as examples behind the title's ⓘ: on Mechanical Support, the examples the empty
    /// state used to give; elsewhere, the field's old placeholder.
    private var shorthandExamples: String {
        supportOnly
            ? "\u{201C}VA ECMO 25F RFV / 17F LFA flow 4 sweep 3\u{201D}, \u{201C}IABP 1:1\u{201D}"
            : "20 rue · RIJ introducer · VA ECMO 25F RFV / 17F LFA"
    }

    private var shorthand: some View {
        // Short placeholder (1.8.1); the shorthand examples sit behind the title's ⓘ.
        PatientGroup(title: "Type a line or device", note: shorthandExamples) {
            HStack(spacing: 8) {
                TextField("Type a line or device", text: $typed)
                    .focused($typing)
                    .font(PS.sys(size: 15))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit { addTyped() }
                if parse != nil {
                    Button { addTyped() } label: { Image(systemName: "plus.circle.fill").font(PS.sys(size: 20)).foregroundStyle(PS.accent) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            if let p = parse {
                let ds = p.devices(placedIntraop: placedIntraop)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(ds.enumerated()), id: \.offset) { _, d in
                        HStack(spacing: 6) {
                            Circle().fill(PatientDiagramModel.color(d.colorRole)).frame(width: 7, height: 7)
                            Text(d.site.isEmpty && d.kind != .ett && d.kind != .trach ? d.label + " — pick a side below" : d.label)
                                .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2)
                        }
                    }
                    if p.site == nil && !p.alternatives.isEmpty {
                        WrapLayout(spacing: 6) {
                            ForEach(Array(p.alternatives.prefix(4).enumerated()), id: \.offset) { _, alt in
                                Button(alt.device().label) { add(alt.devices(placedIntraop: placedIntraop), open: false); typed = "" }
                                    .font(PS.sys(size: 13, weight: .semibold))
                                    .buttonStyle(CapsuleButtonStyle(prominent: false))
                            }
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
        .id("devicetype")
    }

    private func addTyped() {
        guard let p = parse else { return }
        add(p.devices(placedIntraop: placedIntraop), open: false)
        typed = ""
    }

    // MARK: Type buttons

    private var typeButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DeviceKind.buttons, id: \.self) { k in
                    Button { addKind(k) } label: { Label(k.label, systemImage: "plus") }
                        .buttonStyle(CapsuleButtonStyle(prominent: false))
                }
                Menu {
                    ForEach(DeviceKind.more, id: \.self) { k in
                        Button(k.name) { addKind(k) }
                    }
                } label: { Label("Other", systemImage: "ellipsis.circle") }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
            }
        }
        .scrollClipDisabled()
    }

    private func addKind(_ k: DeviceKind, open: Bool = true) {
        // A generator is most often on the left (1.9); the side of anything else is a guess the clinician moves.
        let site = PatientDevices.defaultSite(for: k).flatMap { def in
            DeviceSite.find(def.site, side: DeviceSite.isPaired(def.site) ? (k == .cied ? "left" : "right") : nil)
        }
        add([PatientDevice(kind: k, site: site?.id ?? "", side: site?.side, placedIntraop: placedIntraop)], open: open)
    }

    // MARK: Mechanical support

    private var support: [PatientDevice] { r.devices.filter { PatientDevice.supportKinds.contains($0.kind) && !$0.removed } }
    private var cannulas: [PatientDevice] { support.filter(\.kind.isECMO) }

    private var supportButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if cannulas.isEmpty {
                    Button { addECMO("VA") } label: { Label("VA ECMO", systemImage: "plus") }
                        .buttonStyle(CapsuleButtonStyle(prominent: false))
                    Button { addECMO("VV") } label: { Label("VV ECMO", systemImage: "plus") }
                        .buttonStyle(CapsuleButtonStyle(prominent: false))
                }
                ForEach([DeviceKind.iabp, .impella, .lvad, .protekDuo], id: \.self) { k in
                    Button { addKind(k, open: false) } label: { Label(k.label, systemImage: "plus") }
                        .buttonStyle(CapsuleButtonStyle(prominent: false))
                }
                Menu {
                    Button("ECMO drainage cannula") { addKind(.ecmoDrainage, open: true) }
                    Button("ECMO return cannula") { addKind(.ecmoReturn, open: true) }
                } label: { Label("Cannula", systemImage: "ellipsis.circle") }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
            }
        }
        .scrollClipDisabled()
    }

    /// A drainage cannula in the right femoral vein and a return cannula in the left femoral artery (VA) or right IJ
    /// (VV), with no sizes: the clinician adds them and moves the cannulas if they sit elsewhere.
    private func addECMO(_ mode: String) {
        func cannula(_ k: DeviceKind, _ base: String, _ side: String) -> PatientDevice {
            let site = DeviceSite.find(base, side: side)
            var d = PatientDevice(kind: k, site: site?.id ?? "", side: site?.side, placedIntraop: placedIntraop)
            if k == .ecmoDrainage { d.setValue(mode, for: "mode") }
            return d
        }
        add([cannula(.ecmoDrainage, "femoral-vein", "right"),
             mode == "VA" ? cannula(.ecmoReturn, "femoral-artery", "left") : cannula(.ecmoReturn, "ij", "right")], open: false)
    }

    @ViewBuilder private var supportSettings: some View {
        if support.isEmpty {
            Text("None recorded.")
                .font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
                .padding(.horizontal, 4)
        }
        if let first = cannulas.first {
            let system = PatientDevices.ecmoSystem(r.devices)
            PatientGroup(title: system?.configuration.title ?? "ECMO", note: "Circuit settings are kept once for the circuit.") {
                ForEach(first.kind.fields.filter { circuitKeys.contains($0.id) }) { f in
                    DeviceFieldRow(field: f, value: circuitBinding(f.id))
                    Hairline().padding(.leading, 14)
                }
                ForEach(cannulas) { c in deviceRow(c) }
            }
        }
        ForEach(support.filter { !$0.kind.isECMO }) { d in
            PatientGroup(title: d.kind.name) {
                ForEach(d.kind.fields) { f in
                    DeviceFieldRow(field: f, value: valueBinding(d.id, f.id))
                    Hairline().padding(.leading, 14)
                }
                deviceRow(d, caption: "Site and placement")
            }
        }
    }

    private let circuitKeys: Set<String> = ["mode", "flow", "sweep", "fdo2", "issues"]

    /// A circuit setting: read across the cannulas as the summary reads it, written to the first drainage cannula
    /// (or the first cannula) and cleared from the others so they never disagree.
    private func circuitBinding(_ key: String) -> Binding<String> {
        Binding(get: { PatientDevices.ecmoSystem(patient.record.devices)?.settings[key] ?? "" },
                set: { v in patient.update { r in
                    let ids = r.devices.indices.filter { r.devices[$0].kind.isECMO && !r.devices[$0].removed }
                    guard let target = ids.first(where: { r.devices[$0].kind == .ecmoDrainage }) ?? ids.first else { return }
                    for i in ids { r.devices[i].setValue(i == target ? v : "", for: key) }
                } })
    }

    private func valueBinding(_ id: UUID, _ key: String) -> Binding<String> {
        Binding(get: { patient.record.devices.first { $0.id == id }?.value(key) ?? "" },
                set: { v in patient.update { r in if let i = r.devices.firstIndex(where: { $0.id == id }) { r.devices[i].setValue(v, for: key) } } })
    }

    private func deviceRow(_ d: PatientDevice, caption: String? = nil) -> some View {
        Button { if !editing { editingID = d.id } } label: {
            HStack(spacing: 10) {
                Circle().fill(PatientDiagramModel.color(d.colorRole)).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                    if let caption { Text(caption).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .wobbleDelete($editing, label: d.label) { delete(d.id.uuidString) }
    }

    // MARK: List

    @ViewBuilder private var list: some View {
        if !shown.isEmpty || !r.regional.isEmpty || r.currentAirwayText != nil {
            PatientGroup(title: phase == .preop ? "On arrival" : "Lines & devices") {
                ForEach(shown) { d in
                    Button { if !editing { editingID = d.id } } label: {
                        HStack(spacing: 10) {
                            Circle().fill(PatientDiagramModel.color(d.colorRole)).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(d.removed ? PS.fg3 : PS.fg)
                                    .strikethrough(d.removed)
                                Text((d.placedIntraop ? "Placed in the room" : "On arrival") + (d.position == nil && d.kind != .other ? " · not on the figure yet: tap to choose the site" : ""))
                                    .font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .wobbleDelete($editing, label: d.label) { delete(d.id.uuidString) }
                    Hairline().padding(.leading, 33)
                }
                if !r.regional.isEmpty {
                    Text("Blocks and neuraxial techniques come from Regional & Neuraxial.")
                        .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).padding(14)
                }
            }
        }
    }

    // MARK: Limb alerts (1.9)

    /// The limbs to spare: an arm or leg with an AV fistula or graft on the figure (by itself, from the device), and the
    /// ones added here with a reason. Each is marked "!ⓘ" on the figure.
    @ViewBuilder private var limbAlertsGroup: some View {
        let auto = PatientDeviceFills.limbAlerts(r).filter(\.automatic)
        PatientGroup(title: "Limb alerts", note: "Marks a limb to spare on the diagram: an arm or leg with an AV fistula or graft is marked by itself; add another with the reason, such as a prior axillary lymph node dissection.") {
            ForEach(auto) { a in
                HStack(spacing: 10) {
                    LimbAlertBadge()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(PatientDeviceFills.limbName(a.limb) + " — " + a.reason).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                        Text("From the device on the figure").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                Hairline().padding(.leading, 14)
            }
            ForEach(r.limbAlerts) { a in
                HStack(spacing: 10) {
                    LimbAlertBadge()
                    Text(PatientDeviceFills.limbName(a.limb) + " — " + (a.reason.isEmpty ? "No reason given" : a.reason))
                        .font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(a.reason.isEmpty ? PS.fg3 : PS.fg)
                    Spacer()
                    Button { removeLimbAlert(a.id) } label: { Image(systemName: "trash").font(PS.sys(size: 14)).foregroundStyle(PS.red) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete the limb alert for " + PatientDeviceFills.limbWords(a.limb))
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                Hairline().padding(.leading, 14)
            }
            HStack {
                Text("Limb").font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                Spacer()
                Menu {
                    ForEach(Array(PatientLimbAlert.limbs.enumerated()), id: \.offset) { _, l in Button(l.label) { alertLimb = l.id } }
                } label: {
                    HStack(spacing: 4) {
                        Text(PatientLimbAlert.limbs.first { $0.id == alertLimb }?.label ?? "Choose").font(PS.sys(size: 14.5, weight: .semibold))
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 11, weight: .semibold))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Hairline().padding(.leading, 14)
            HStack(spacing: 8) {
                TextField("Reason, e.g. prior axillary lymph node dissection", text: $alertReason)
                    .font(PS.sys(size: 15))
                    .submitLabel(.done)
                    .onSubmit { addLimbAlert() }
                Button { addLimbAlert() } label: { Image(systemName: "plus.circle.fill").font(PS.sys(size: 20)).foregroundStyle(PS.accent) }
                    .buttonStyle(.plain)
                    .disabled(alertReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add the limb alert")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .id("limbalerts")
    }

    private func addLimbAlert() {
        let reason = alertReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }
        Haptics.light()
        patient.update(discrete: true) { $0.limbAlerts.append(PatientLimbAlert(limb: alertLimb, reason: reason)) }
        alertReason = ""
    }

    private func removeLimbAlert(_ id: UUID) {
        Haptics.light()
        withAnimation(.snappy) { patient.update(discrete: true) { $0.limbAlerts.removeAll { $0.id == id } } }
    }

    // MARK: Changes

    private func add(_ ds: [PatientDevice], open: Bool) {
        guard !ds.isEmpty else { return }
        Haptics.light()
        var added: [UUID] = []
        patient.update(discrete: true) { r in
            for d in ds {
                // The airway is the record's own: an ETT or tracheostomy sets it instead of adding a device.
                switch d.kind {
                case .ett:
                    if phase == .preop { r.currentAirway = "ett"; r.ettSize = d.size; r.ettDepth = d.settings["depth"].map { $0 + " cm" } ?? r.ettDepth }
                    else { r.tube = ["\(d.size.isEmpty ? "" : d.size + " ")ETT", d.settings["depth"].map { $0 + " cm" }].compactMap { $0 }.joined(separator: ", ") }
                case .trach:
                    r.currentAirway = "trach"; r.trachType = [d.size, d.detail].filter { !$0.isEmpty }.joined(separator: " ")
                case .epidural, .spinal, .block, .perineuralCatheter:
                    let side: String = d.side == "left" ? "Left" : (d.side == "right" ? "Right" : "")
                    let isBlock = d.kind == .block || d.kind == .perineuralCatheter
                    var technique: String = d.kind.name
                    if isBlock {
                        let site: String = d.siteInfo?.name.capitalizedFirstLetter ?? d.kind.name
                        technique = site + " block"
                    } else if let level = d.settings["level"] {
                        technique += " " + level
                    }
                    let catheter = d.kind == .epidural || d.kind == .perineuralCatheter
                    r.regional.append(PatientRegional(technique: technique, side: side, drug: "", catheter: catheter))
                default:
                    r.devices.append(d)
                    added.append(d.id)
                }
            }
        }
        if open, let first = added.first { editingID = first }
    }

    private func move(_ id: String, _ by: CGSize) {
        guard let uuid = UUID(uuidString: id) else { return }
        patient.update(discrete: true) { r in
            guard let i = r.devices.firstIndex(where: { $0.id == uuid }) else { return }
            let o = r.devices[i].offset ?? .zero
            r.devices[i].offset = CGPoint(x: o.x + by.width / 200, y: o.y + by.height / 420)
        }
    }

    private func delete(_ id: String) {
        guard let uuid = UUID(uuidString: id) else { return }
        Haptics.light()
        withAnimation(.snappy) { patient.update(discrete: true) { $0.devices.removeAll { $0.id == uuid } } }
    }
}

private extension String {
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}

/// One device: its kind and site, the fields its kind asks for, and whether it was placed in the room or removed.
struct DeviceDetailSheet: View {
    @Environment(PatientStore.self) private var patient
    @Environment(\.dismiss) private var dismiss
    var deviceID: UUID

    private var index: Int? { patient.record.devices.firstIndex { $0.id == deviceID } }
    private var device: PatientDevice? { index.map { patient.record.devices[$0] } }

    /// A typed detail joins the burst it is part of; a menu pick, toggle or chip (`discrete`) is an Undo step of its own.
    private func update(discrete: Bool = false, _ f: (inout PatientDevice) -> Void) {
        patient.update(discrete: discrete) { r in if let i = r.devices.firstIndex(where: { $0.id == deviceID }) { f(&r.devices[i]) } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let d = device {
                    VStack(alignment: .leading, spacing: 16) {
                        PatientGroup(title: "Device") {
                            HStack {
                                Text("Type").font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                                Spacer()
                                Menu {
                                    ForEach(DeviceKind.allCases.filter { ![.ett, .trach, .epidural, .spinal, .block, .perineuralCatheter].contains($0) }, id: \.self) { k in
                                        Button(k.name) { update(discrete: true) { $0.kind = k } }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(d.kind.name).font(PS.sys(size: 14.5, weight: .semibold))
                                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 11, weight: .semibold))
                                    }
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            Hairline().padding(.leading, 14)
                            HStack {
                                Text("Site").font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                                Spacer()
                                Menu {
                                    ForEach(DeviceSite.all.filter { $0.kinds.contains(d.kind) || d.kind == .other }) { s in
                                        Button(s.name.prefix(1).uppercased() + s.name.dropFirst()) { update(discrete: true) { $0.site = s.id; $0.side = s.side; $0.offset = nil } }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(d.siteInfo.map { $0.name.prefix(1).uppercased() + $0.name.dropFirst() } ?? "Choose").font(PS.sys(size: 14.5, weight: .semibold))
                                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 11, weight: .semibold))
                                    }
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                        PatientGroup(title: "Details") {
                            ForEach(d.kind.fields) { f in
                                DeviceFieldRow(field: f, value: Binding(get: { device?.value(f.id) ?? "" }, set: { v in update { $0.setValue(v, for: f.id) } }))
                                Hairline().padding(.leading, 14)
                            }
                        }
                        PatientGroup(title: nil) {
                            Toggle(isOn: Binding(get: { device?.placedIntraop ?? false }, set: { v in update(discrete: true) { $0.placedIntraop = v } })) {
                                Text("Placed in the room (not there on arrival)").font(PS.sys(size: 14.5)).foregroundStyle(PS.fg)
                            }
                            .tint(PS.accent).padding(.horizontal, 14).padding(.vertical, 9)
                            Hairline().padding(.leading, 14)
                            Toggle(isOn: Binding(get: { device?.removed ?? false }, set: { v in update(discrete: true) { $0.removed = v } })) {
                                Text("Removed").font(PS.sys(size: 14.5)).foregroundStyle(PS.fg)
                            }
                            .tint(PS.accent).padding(.horizontal, 14).padding(.vertical, 9)
                        }
                        Text(d.label).font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(PS.fg2)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(PS.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Button(role: .destructive) {
                            patient.update(discrete: true) { $0.devices.removeAll { $0.id == deviceID } }
                            dismiss()
                        } label: { Label("Delete", systemImage: "trash").frame(maxWidth: .infinity) }
                            .buttonStyle(BigButtonStyle(prominent: false))
                    }
                    .padding(20)
                }
            }
            .background(FeedBackground())
            .navigationTitle(device?.kind.name ?? "Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

/// A field a device kind asks for: typed, with quick picks underneath.
struct DeviceFieldRow: View {
    var field: DeviceField
    @Binding var value: String
    @Environment(PatientStore.self) private var store: PatientStore?

    var body: some View {
        Group {
            if field.choices.isEmpty {
                HStack {
                    title
                    Spacer()
                    entry(maxWidth: 170)
                }
            } else {
                // The choices on the title's line when they fit (with a small box for another value); otherwise
                // under it.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        title.fixedSize()
                        Spacer(minLength: 6)
                        HStack(spacing: 6) { chips }.fixedSize()
                        // A box for another value: always for numbers, and for text only when it holds one.
                        if field.numeric || (!value.isEmpty && !field.choices.contains(value)) {
                            entry(maxWidth: 58).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            title
                            Spacer()
                            entry(maxWidth: 170)
                        }
                        WrapLayout(spacing: 6) { chips }
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var title: some View {
        Text(field.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
    }

    @ViewBuilder private func entry(maxWidth: CGFloat) -> some View {
        HStack(spacing: 4) {
            TextField(field.unit.isEmpty ? "—" : field.unit, text: $value)
                .keyboardType(field.numeric ? .decimalPad : .default)
                .multilineTextAlignment(.trailing)
                .font(PS.sys(size: 15, design: field.numeric ? .monospaced : .default))
                .frame(width: maxWidth < 100 ? maxWidth : nil)
                .frame(maxWidth: maxWidth)
            if field.numeric && !field.unit.isEmpty {
                Text(field.unit).font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
            }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(field.choices, id: \.self) { c in
            Button(c) { store?.markDiscrete(); value = value == c ? "" : c }
                .font(PS.sys(size: 12.5, weight: .semibold))
                .foregroundStyle(value == c ? PS.accentFg : PS.fg2)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(value == c ? PS.accent : PS.surface2, in: Capsule())
                .buttonStyle(.plain)
        }
    }
}
