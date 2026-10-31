import SwiftUI

// MARK: - Lines & devices on the patient diagram
//
// PatientDiagramModel turns the record into what PatientDiagramCanvas draws: the airway (from the current airway and
// the intraoperative course), the lines and devices (PatientDevice), the ECMO circuit to its cart, and the blocks and
// neuraxial techniques (read from the Regional list). PatientDevicesEditor adds and edits them: tap a body point,
// type shorthand ("20 rue", "RIJ introducer"), or use the type buttons; long-press to move or delete.

enum PatientDiagramModel {
    enum Phase: String { case preop, intraop, all }

    /// Fractions of the figure box to figure units.
    static func pt(_ f: CGPoint) -> CGPoint { CGPoint(x: f.x * 200, y: f.y * 420) }

    static let svc = CGPoint(x: 100, y: 84)
    static let ivc = CGPoint(x: 101, y: 168)
    static let ra = CGPoint(x: 98, y: 101)
    static let rv = CGPoint(x: 104, y: 108)
    static let pa = CGPoint(x: 107, y: 90)
    static let descendingAorta = CGPoint(x: 103, y: 92)
    static let lv = CGPoint(x: 109, y: 106)
    static let cart = CGPoint(x: 214, y: 322)

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
        default: return d.kind.label + size
        }
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
        let intubatedHere = r.intubation == "easy" || r.intubation == "difficult" || !r.tube.isEmpty
        let ettNow: Bool = {
            switch phase {
            case .preop: return r.currentAirway == "ett"
            case .intraop, .all: return (r.currentAirway == "ett" || intubatedHere) && r.airwayAtEnd != "extubated"
            }
        }()
        if ettNow {
            let label = r.currentAirway == "ett" ? "ETT" + (r.ettSize.isEmpty ? "" : " " + r.ettSize) + (r.ettDepth.isEmpty ? "" : " @" + (r.ettDepth.split(separator: " ").first.map(String.init) ?? r.ettDepth)) : (r.tube.isEmpty ? "ETT" : r.tube.split(separator: ",").first.map(String.init) ?? "ETT")
            out.append(DiagramItem(id: "airway-ett", anchor: CGPoint(x: 100, y: 42), course: [CGPoint(x: 100, y: 53), CGPoint(x: 100, y: 74)],
                                   color: DiagramColor.airway, width: 2.2, marker: .dot, label: label, labelLeft: false, movable: false))
        } else if r.currentAirway == "trach" {
            out.append(DiagramItem(id: "airway-trach", anchor: CGPoint(x: 100, y: 62), course: [CGPoint(x: 100, y: 74)],
                                   color: DiagramColor.airway, width: 2.2, marker: .stoma, label: "Trach" + (r.trachType.isEmpty ? "" : " " + r.trachType.split(separator: " ").prefix(2).joined(separator: " ")), labelLeft: false, movable: false))
        }

        // Lines and devices.
        let devices = r.devices.filter { !$0.removed && (phase != .preop || !$0.placedIntraop) }
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
            case .piv, .other:
                item.marker = .dot
            case .arterial:
                item.marker = .dot
            case .intraosseous:
                item.marker = .square
            case .cvc, .picc:
                item.course = fromBelow ? [CGPoint(x: (a.x + 100) / 2, y: a.y - 6), ivc] : (region == "arm" ? [CGPoint(x: left ? 70 : 130, y: 92), svc] : [svc])
                item.width = 2
            case .pac:
                item.course = (fromBelow ? [ivc] : [svc]) + [ra, rv, pa]
                item.width = 2
            case .ecmoDrainage, .ecmoReturn:
                ecmo = true
                item.course = [CGPoint(x: a.x, y: max(a.y, 300) + 6), CGPoint(x: cart.x - 22, y: cart.y + (d.kind == .ecmoDrainage ? -4 : 4))]
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
            case .ett, .trach, .epidural, .spinal, .block, .perineuralCatheter:
                item.marker = .dot
            }
            out.append(item)
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
            cartInfo = DiagramCart(at: cart, title: sys.configuration == .unknown ? "ECMO" : sys.configuration.name + " ECMO",
                                   detail: [flow, sweep].filter { !$0.isEmpty }.joined(separator: " · "))
        }
        return (out, cartInfo)
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

    var body: some View {
        if let fig = refs.bundle?.regional?.figure {
            let m = PatientDiagramModel.items(record, phase: phase)
            PatientDiagramCanvas(figure: fig, items: m.items, cart: m.cart)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
        }
    }
}

/// The lines and devices editor: the diagram, shorthand, type buttons and the list.
struct PatientDevicesEditor: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    var phase: PatientDiagramModel.Phase

    @State private var editing = false
    @State private var typed = ""
    @State private var tapOptions: [DeviceOption] = []
    @State private var showTapMenu = false
    @State private var editingID: UUID?
    @FocusState private var typing: Bool

    private var r: PatientRecord { patient.record }
    private var placedIntraop: Bool { phase == .intraop }
    private var shown: [PatientDevice] { r.devices.filter { phase != .preop || !$0.placedIntraop } }
    private var parse: DeviceParse? { typed.trimmingCharacters(in: .whitespaces).count >= 2 ? PatientDevices.parse(typed) : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let fig = refs.bundle?.regional?.figure {
                let m = PatientDiagramModel.items(r, phase: phase == .preop ? .preop : .all)
                VStack(spacing: 6) {
                    HStack {
                        Text(editing ? "Drag to move · × to delete" : "Tap the body to add · long-press to move or delete")
                            .font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                        Spacer()
                        if editing {
                            Button("Done") { withAnimation(.snappy) { editing = false } }
                                .buttonStyle(CapsuleButtonStyle())
                        }
                    }
                    PatientDiagramCanvas(figure: fig, items: m.items, cart: m.cart, editing: editing,
                                         onTapFigure: { p in
                                             let f = CGPoint(x: p.x / 200, y: p.y / 420)
                                             tapOptions = DeviceSite.options(near: f, limit: 8, within: 36)
                                             if !tapOptions.isEmpty { showTapMenu = true }
                                         },
                                         onTapItem: { id in editingID = UUID(uuidString: id) },
                                         onLongPress: { Haptics.light(); withAnimation(.snappy) { editing = true } },
                                         onMove: { id, by in move(id, by) },
                                         onDelete: { id in delete(id) })
                        .frame(height: 430)
                }
                .padding(12)
                .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                .confirmationDialog("Add at this spot", isPresented: $showTapMenu, titleVisibility: .visible) {
                    ForEach(tapOptions) { o in
                        Button(o.label) { add([PatientDevice(kind: o.kind, site: o.site.id, side: o.site.side, placedIntraop: placedIntraop)], open: true) }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
            shorthand
            typeButtons
            list
        }
        .sheet(item: Binding(get: { editingID.map { IDBox(id: $0) } }, set: { editingID = $0?.id })) { box in
            DeviceDetailSheet(deviceID: box.id)
                .environment(patient)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private struct IDBox: Identifiable { var id: UUID }

    // MARK: Typed shorthand

    private var shorthand: some View {
        PatientGroup(title: "Type a line or device") {
            HStack(spacing: 8) {
                TextField("20 rue · RIJ introducer · VA ECMO 25F RFV / 17F LFA", text: $typed)
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

    private func addKind(_ k: DeviceKind) {
        let site = PatientDevices.defaultSite(for: k).flatMap { def in DeviceSite.find(def.site, side: DeviceSite.isPaired(def.site) ? "right" : nil) }
        add([PatientDevice(kind: k, site: site?.id ?? "", side: site?.side, placedIntraop: placedIntraop)], open: true)
    }

    // MARK: List

    @ViewBuilder private var list: some View {
        if !shown.isEmpty || !r.regional.isEmpty || r.currentAirwayText != nil {
            PatientGroup(title: phase == .preop ? "On arrival" : "Lines & devices") {
                ForEach(shown) { d in
                    Button { editingID = d.id } label: {
                        HStack(spacing: 10) {
                            Circle().fill(PatientDiagramModel.color(d.colorRole)).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(d.removed ? PS.fg3 : PS.fg)
                                    .strikethrough(d.removed)
                                Text(d.placedIntraop ? "Placed in the room" : "On arrival").font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline().padding(.leading, 33)
                }
                if !r.regional.isEmpty {
                    Text("Blocks and neuraxial techniques come from Regional & Neuraxial.")
                        .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).padding(14)
                }
            }
        }
    }

    // MARK: Changes

    private func add(_ ds: [PatientDevice], open: Bool) {
        guard !ds.isEmpty else { return }
        Haptics.light()
        var added: [UUID] = []
        patient.update { r in
            for d in ds {
                // The airway is the record's own: an ETT or tracheostomy sets it instead of adding a device.
                switch d.kind {
                case .ett:
                    if phase == .preop { r.currentAirway = "ett"; r.ettSize = d.size; r.ettDepth = d.settings["depth"].map { $0 + " cm" } ?? r.ettDepth }
                    else { r.tube = ["\(d.size.isEmpty ? "" : d.size + " ")ETT", d.settings["depth"].map { $0 + " cm" }].compactMap { $0 }.joined(separator: ", ") }
                case .trach:
                    r.currentAirway = "trach"; r.trachType = [d.size, d.detail].filter { !$0.isEmpty }.joined(separator: " ")
                case .epidural, .spinal, .block, .perineuralCatheter:
                    let side = d.side.map { $0 == "left" ? "Left" : "Right" } ?? ""
                    r.regional.append(PatientRegional(technique: d.kind == .block || d.kind == .perineuralCatheter ? (d.siteInfo?.name.capitalizedFirstLetter ?? d.kind.name) + " block" : d.kind.name + (d.settings["level"].map { " " + $0 } ?? ""),
                                                      side: side, drug: "", catheter: d.kind == .epidural || d.kind == .perineuralCatheter))
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
        patient.update { r in
            guard let i = r.devices.firstIndex(where: { $0.id == uuid }) else { return }
            let o = r.devices[i].offset ?? .zero
            r.devices[i].offset = CGPoint(x: o.x + by.width / 200, y: o.y + by.height / 420)
        }
    }

    private func delete(_ id: String) {
        guard let uuid = UUID(uuidString: id) else { return }
        Haptics.light()
        withAnimation(.snappy) { patient.update { $0.devices.removeAll { $0.id == uuid } } }
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

    private func update(_ f: (inout PatientDevice) -> Void) {
        patient.update { r in if let i = r.devices.firstIndex(where: { $0.id == deviceID }) { f(&r.devices[i]) } }
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
                                        Button(k.name) { update { $0.kind = k } }
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
                                        Button(s.name.prefix(1).uppercased() + s.name.dropFirst()) { update { $0.site = s.id; $0.side = s.side; $0.offset = nil } }
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
                            Toggle(isOn: Binding(get: { device?.placedIntraop ?? false }, set: { v in update { $0.placedIntraop = v } })) {
                                Text("Placed in the room (not there on arrival)").font(PS.sys(size: 14.5)).foregroundStyle(PS.fg)
                            }
                            .tint(PS.accent).padding(.horizontal, 14).padding(.vertical, 9)
                            Hairline().padding(.leading, 14)
                            Toggle(isOn: Binding(get: { device?.removed ?? false }, set: { v in update { $0.removed = v } })) {
                                Text("Removed").font(PS.sys(size: 14.5)).foregroundStyle(PS.fg)
                            }
                            .tint(PS.accent).padding(.horizontal, 14).padding(.vertical, 9)
                        }
                        Text(d.label).font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(PS.fg2)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(PS.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Button(role: .destructive) {
                            patient.update { $0.devices.removeAll { $0.id == deviceID } }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(field.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                Spacer()
                TextField(field.unit.isEmpty ? "—" : field.unit, text: $value)
                    .keyboardType(field.numeric ? .decimalPad : .default)
                    .multilineTextAlignment(.trailing)
                    .font(PS.sys(size: 15, design: field.numeric ? .monospaced : .default))
                    .frame(maxWidth: 170)
                if field.numeric && !field.unit.isEmpty {
                    Text(field.unit).font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                }
            }
            if !field.choices.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(field.choices, id: \.self) { c in
                        Button(c) { value = c }
                            .font(PS.sys(size: 12.5, weight: .semibold))
                            .foregroundStyle(value == c ? PS.accentFg : PS.fg2)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(value == c ? PS.accent : PS.surface2, in: Capsule())
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
