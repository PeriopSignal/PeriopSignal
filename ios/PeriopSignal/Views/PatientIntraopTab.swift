import SwiftUI

// MARK: - The 1.10 Intraoperative tab (Ben, Nov 7)
//
// Ben's five headings, in his order, as headings and not boxes unless he wrote "(link)":
//   1. Airway Course: Mask ventilation; Intubation or LMA (Intubation opens the device chips, the laryngeal view chips
//      and the tube details), inline.
//   2. Lines & Devices: the figure and the lines, opening the lines editor.
//   3. Medications & Infusions: the type-a-drip field with the list (the unit fills in), and "+ Notable medication".
//   4. Fluids & Blood, inline.
//   5. Other Intraoperative Details: the links to the intraoperative echo findings, labs, regional & neuraxial, events &
//      interventions, major considerations, and the case timers.
// The editors keep every part they had (PatientEditor.intraopParts), so a deep link or an older screenshot key still opens.

// MARK: Sections

/// The tab's five headings, and where the older part keys went.
enum IntraopSection: String, CaseIterable {
    case airway, lines, meds, fluids, other

    var title: String {
        switch self {
        case .airway: return "Airway Course"
        case .lines: return "Lines & Devices"
        case .meds: return "Medications & Infusions"
        case .fluids: return "Fluids & Blood"
        case .other: return "Other Intraoperative Details"
        }
    }

    /// The jump bar's chip.
    var jumpTitle: String {
        switch self {
        case .airway: return "Airway"
        case .lines: return "Lines"
        case .meds: return "Meds & Infusions"
        case .fluids: return "Fluids & Blood"
        case .other: return "Other"
        }
    }

    /// The section that holds a part of the older tab (PatientEditor.intraopParts), so -ps.patient.jump intraop:labs and
    /// the other old keys keep working.
    init(part: String) {
        switch part {
        case "airway": self = .airway
        case "lines": self = .lines
        case "infusions", "meds": self = .meds
        case "fluids": self = .fluids
        default: self = .other
        }
    }
}

// MARK: Pieces

/// A heading of the tab.
struct IntraopSectionTitle: View {
    var text: String
    var body: some View {
        Text(text)
            .font(PS.sys(size: 19, weight: .bold))
            .foregroundStyle(PS.fg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Chips that stay on one line where they fit, at the app's chip size: with the label beside them, then with tighter
/// padding, then under the label on a line of their own, and wrapping only when nothing else fits (a large text size).
/// (Helper C's compact PatientChoice mode, when it lands, can replace this; until then the Intraoperative tab uses
/// this.) `selection` is a closure pair so one chip, or several (Intubation and LMA), can be on.
struct IntraopChoiceLine: View {
    var label: String?
    var options: [(id: String, label: String)]
    var isOn: (String) -> Bool
    var tap: (String) -> Void
    @Environment(PatientStore.self) private var store: PatientStore?

    /// One chosen at a time: a tap on the chosen one clears it.
    init(label: String? = nil, options: [(id: String, label: String)], selection: Binding<String?>) {
        self.label = label
        self.options = options
        self.isOn = { selection.wrappedValue == $0 }
        self.tap = { id in selection.wrappedValue = selection.wrappedValue == id ? nil : id }
    }

    /// Any number on, each its own tap.
    init(label: String? = nil, options: [(id: String, label: String)], isOn: @escaping (String) -> Bool, tap: @escaping (String) -> Void) {
        self.label = label
        self.options = options
        self.isOn = isOn
        self.tap = tap
    }

    /// The chip's weight: bold when chosen only where the row wraps. In a one-line form a chosen chip keeps its width
    /// (its fill shows the choice), so a tap never makes the row jump to another layout, as in ChipSet.
    static func weight(on: Bool, wrapped: Bool) -> Font.Weight { wrapped && on ? .semibold : .medium }

    private func chip(_ o: (id: String, label: String), pad: CGFloat, wrapped: Bool = false) -> some View {
        let on = isOn(o.id)
        return Button {
            Haptics.light()
            store?.markDiscrete()
            tap(o.id)
        } label: {
            Text(o.label)
                .font(PS.sys(size: 13.5, weight: Self.weight(on: on, wrapped: wrapped)))
                .lineLimit(1)
                .foregroundStyle(on ? PS.bg : PS.fg2)
                .padding(.horizontal, pad).padding(.vertical, 7)
                .background(on ? PS.fg : PS.surface2, in: Capsule())
                .overlay(Capsule().stroke(on ? Color.clear : PS.line2, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func chips(pad: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) { ForEach(Array(options.enumerated()), id: \.offset) { _, o in chip(o, pad: pad) } }
    }

    private var title: some View {
        Text(label ?? "").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
    }

    /// Without the row's own padding, for a row that already has it (InfoChipRow).
    var inset = true
    func unpadded() -> IntraopChoiceLine { var c = self; c.inset = false; return c }

    private var wrapped: some View {
        WrapLayout(spacing: 7) { ForEach(Array(options.enumerated()), id: \.offset) { _, o in chip(o, pad: 12, wrapped: true) } }
    }

    @ViewBuilder private var labeled: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { title.fixedSize(); Spacer(minLength: 8); chips(pad: 12, spacing: 7).fixedSize() }
            HStack(spacing: 8) { title.fixedSize(); Spacer(minLength: 4); chips(pad: 8, spacing: 5).fixedSize() }
            VStack(alignment: .leading, spacing: 6) { title; chips(pad: 12, spacing: 7).fixedSize() }
            VStack(alignment: .leading, spacing: 6) { title; chips(pad: 8, spacing: 5).fixedSize() }
            VStack(alignment: .leading, spacing: 6) { title; wrapped }
        }
    }

    @ViewBuilder private var unlabeled: some View {
        ViewThatFits(in: .horizontal) {
            chips(pad: 12, spacing: 7).fixedSize()
            chips(pad: 8, spacing: 5).fixedSize()
            wrapped
        }
    }

    var body: some View {
        Group {
            if label != nil { labeled } else { unlabeled }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, inset ? 14 : 0).padding(.vertical, inset ? 10 : 0)
    }
}

/// An "+ Add" row that opens an editor, with what the editor holds under it once something is recorded.
struct IntraopLinkRow: View {
    var title: String
    var icon: String
    var editor: PatientEditor
    var lines: [PatientSummary.Line]
    /// What it holds, in a few words, while empty.
    var hint: String = ""

    var body: some View {
        NavigationLink(value: editor) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: lines.isEmpty ? "plus.circle" : icon)
                        .font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.accent)
                        .frame(width: 22)
                    Text(title).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                }
                if lines.isEmpty {
                    if !hint.isEmpty {
                        Text(hint).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 32)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in PatientLineText(line: l) }
                    }
                    .padding(.leading, 32)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((lines.isEmpty ? "Add " : "Edit ") + title)
    }
}

// MARK: 1. Airway Course

/// Mask ventilation, then Intubation or LMA. Intubation opens its ease, the device chips, the laryngeal view chips, the
/// attempts and the tube; LMA opens its ease. How the patient leaves (extubated, remains intubated) closes it, as the
/// handoff's airway course does. Used in the tab and in the Airway editor page.
struct IntraopAirwayCourse: View {
    @Environment(PatientStore.self) private var patient
    private var r: PatientRecord { patient.record }

    private func text(_ kp: WritableKeyPath<PatientRecord, String>) -> Binding<String> {
        Binding(get: { patient.record[keyPath: kp] }, set: { v in patient.update { $0[keyPath: kp] = v } })
    }

    private func choice(_ kp: WritableKeyPath<PatientRecord, String?>) -> Binding<String?> {
        Binding(get: { patient.record[keyPath: kp] }, set: { v in patient.update { $0[keyPath: kp] = v } })
    }

    private static let ease: [(id: String, label: String)] = [(id: "easy", label: "Easy"), (id: "difficult", label: "Difficult")]

    /// Easy or difficult, kept apart from "placed" (chosen, no ease recorded).
    private func easeBinding(_ kp: WritableKeyPath<PatientRecord, String?>) -> Binding<String?> {
        Binding(get: { PatientAirway.ease(patient.record[keyPath: kp]) },
                set: { v in patient.update { $0[keyPath: kp] = v ?? PatientAirway.placed } })
    }

    /// The chosen laryngeal view's definition, for the ⓘ on "Laryngeal view (Cormack–Lehane)".
    private var laryngealGradeNote: String? {
        guard let g = r.laryngoscopyGrade, let d = PatientCatalog.gradeDetail(g) else { return nil }
        return "Grade " + g + ": " + d.lowercased() + (g == "3" || g == "4" ? " (difficult laryngoscopy)." : ".")
    }

    /// The devices that go with an intubation; a saved device outside them (an older record) still shows, chosen.
    private var deviceChoices: [String] {
        var devices = PatientAirway.intubationDevices
        if let current = PatientAirway.deviceName(r.airwayDevice), !devices.contains(current) { devices.append(current) }
        return devices
    }

    var body: some View {
        if r.arrivesWithAirway {
            PatientGroup(title: nil) {
                Text((r.currentAirwayText ?? "Airway secured") + " on arrival: no airway course to record.")
                    .font(PS.sys(size: 14)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                Hairline().padding(.leading, 14)
                atHandoff
            }
        } else {
            PatientGroup(title: nil) {
                maskVentilation
                Hairline().padding(.leading, 14)
                intubationOrLMA
                Hairline().padding(.leading, 14)
                atHandoff
            }
        }
    }

    @ViewBuilder private var maskVentilation: some View {
        IntraopChoiceLine(label: "Mask ventilation",
                          options: [(id: "easy", label: "Easy"), (id: "difficult", label: "Difficult"), (id: "none", label: "Not used")],
                          selection: choice(\.mask))
        if r.mask == "difficult" {
            PatientTextField(label: "What made it difficult", prompt: "Beard, two hands, oral airway, what worked", text: text(\.maskNote))
        }
    }

    @ViewBuilder private var intubationOrLMA: some View {
        IntraopChoiceLine(label: "Intubation or LMA",
                          options: [(id: "intubation", label: "Intubation"), (id: "lma", label: "LMA")],
                          isOn: { $0 == "intubation" ? PatientAirway.intubationChosen(patient.record) : PatientAirway.lmaChosen(patient.record) },
                          tap: { id in
                              withAnimation(.snappy) {
                                  patient.update(discrete: true) { rec in
                                      if id == "intubation" {
                                          let on = PatientAirway.intubationChosen(rec)
                                          PatientAirway.setIntubation(!on, &rec)
                                      } else {
                                          let on = PatientAirway.lmaChosen(rec)
                                          PatientAirway.setLMA(!on, &rec)
                                      }
                                  }
                              }
                          })
        if PatientAirway.intubationChosen(r) { intubationDetails }
        if PatientAirway.lmaChosen(r) { lmaDetails }
    }

    @ViewBuilder private var intubationDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Intubation").font(PS.sys(size: 12, weight: .bold)).foregroundStyle(PS.fg3).textCase(.uppercase)
                .padding(.horizontal, 14).padding(.top, 4)
            IntraopChoiceLine(label: "Ease", options: Self.ease, selection: easeBinding(\.intubation))
            if r.intubation == "difficult" {
                PatientTextField(label: "What made it difficult", prompt: "View, adjuncts, what worked", text: text(\.intubationNote))
            }
            IntraopChoiceLine(label: "Device", options: deviceChoices.map { (id: $0, label: $0) },
                              selection: Binding(get: { PatientAirway.deviceName(patient.record.airwayDevice) },
                                                 set: { v in patient.update { $0.airwayDevice = v } }))
            InfoChipRow(label: "Laryngeal view (Cormack–Lehane)", info: laryngealGradeNote) {
                IntraopChoiceLine(options: PatientCatalog.grades.map { (id: $0, label: $0) }, selection: choice(\.laryngoscopyGrade)).unpadded()
            }
            Stepper(value: Binding(get: { patient.record.attempts ?? 0 }, set: { v in patient.update(discrete: true) { $0.attempts = v > 0 ? v : nil } }), in: 0...9) {
                Text("Attempts: " + (r.attempts.map { String($0) } ?? "not recorded")).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            PatientTextField(label: "Tube", prompt: "e.g. 8.0 cuffed ETT (23 cm)", text: text(\.tube))
        }
        .padding(.leading, 6)
        .overlay(alignment: .leading) { Rectangle().fill(PS.line2).frame(width: 2).padding(.vertical, 6) }
    }

    @ViewBuilder private var lmaDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LMA").font(PS.sys(size: 12, weight: .bold)).foregroundStyle(PS.fg3).textCase(.uppercase)
                .padding(.horizontal, 14).padding(.top, 4)
            IntraopChoiceLine(label: "Ease", options: Self.ease, selection: easeBinding(\.sga))
            // The LMA's size, where the quick-add bar filed it ("LMA 4"): seen and corrected here.
            if PatientAirway.tubeIsLMA(r) {
                PatientTextField(label: "Device and size", prompt: "e.g. LMA 4", text: text(\.tube))
            }
            if r.sga == "difficult" {
                PatientTextField(label: "What made it difficult", prompt: "Device and size, leak, attempts, what worked", text: text(\.sgaNote))
            }
        }
        .padding(.leading, 6)
        .overlay(alignment: .leading) { Rectangle().fill(PS.line2).frame(width: 2).padding(.vertical, 6) }
    }

    /// How the airway is left: the handoff's course ends with it ("Remains intubated").
    @ViewBuilder private var atHandoff: some View {
        IntraopChoiceLine(label: "At handoff", options: PatientCatalog.airwayAtEnd, selection: choice(\.airwayAtEnd))
        if r.airwayAtEnd == "intubated" {
            PatientTextField(label: "Ventilation", prompt: "e.g. VC 450 × 14, PEEP 8, FiO₂ 0.5", text: text(\.ventilation))
        }
    }
}

// MARK: 3. Infusions

/// The drips: typed in a line with the drug list suggesting names and filling in the unit, then the list of what is
/// running. Used in the tab and in the Infusions editor page.
struct IntraopInfusionsSection: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    @State private var wobbling = false
    private var r: PatientRecord { patient.record }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !r.homeInfusions.isEmpty && r.infusions.isEmpty {
                Button { patient.update(discrete: true) { $0.infusions = $0.homeInfusions.map { PatientInfusion(drug: $0.drug, rate: $0.rate) } } } label: {
                    Label("Carry over the current infusions (" + r.homeInfusions.map(\.drug).filter { !$0.isEmpty }.joined(separator: ", ") + ")", systemImage: "arrow.down.circle")
                        // Wraps, unlike GhostButtonStyle's one line: two drug names ran the page wider than the screen (1.8.1).
                        .font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 15).padding(.vertical, 9)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PS.line2, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            PatientGroup(title: "Infusions") {
                // Typed in one line, as the quick-add bar takes them (1.8.1).
                InfusionTypeField(list: \.infusions)
                Hairline().padding(.leading, 14)
                ForEach(r.infusions) { inf in
                    infusionEditor(inf)
                        .wobbleDelete($wobbling, label: inf.drug.isEmpty ? "infusion" : inf.drug) { patient.update(discrete: true) { $0.infusions.removeAll { $0.id == inf.id } } }
                    Hairline().padding(.leading, 14)
                }
                WobbleDoneBar(editing: $wobbling)
                Button { patient.update(discrete: true) { $0.infusions.append(PatientInfusion()) } } label: { Label("Add infusion", systemImage: "plus.circle") }
                    .font(PS.sys(size: 14, weight: .semibold)).buttonStyle(.borderless).tint(PS.accent)
                    .padding(14)
            }
        }
    }

    private func infusionEditor(_ inf: PatientInfusion) -> some View {
        let idx = r.infusions.firstIndex { $0.id == inf.id }
        let names = (refs.bundle?.infusions?.groups ?? []).flatMap { $0.drugs.map(\.name) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    ForEach(names, id: \.self) { n in
                        Button(n) { if let i = idx { patient.update(discrete: true) { $0.infusions[i].drug = n } } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(inf.drug.isEmpty ? "Choose the drug" : inf.drug).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(inf.drug.isEmpty ? PS.accent : PS.fg).multilineTextAlignment(.leading)
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                    }
                }
                Spacer()
                Button(role: .destructive) { if let i = idx { patient.update(discrete: true) { $0.infusions.remove(at: i) } } } label: { Image(systemName: "trash").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this infusion")
            }
            FocusBox { f in
                TextField("Rate", text: Binding(get: { idx.map { patient.record.infusions[$0].rate } ?? "" }, set: { v in if let i = idx { patient.update { $0.infusions[i].rate = v } } }))
                    .focused(f)
                    .font(PS.sys(size: 14))
                    .padding(8).background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: 4. Fluids & Blood

/// Blood products and fluids, inline: blood products have their own + and − (BloodProductsGroup); crystalloid (a 1000 mL
/// bag a tap) and colloid (a 250 mL bottle) too, BloodProducts.fluidSteps. Blood loss and urine are typed.
struct IntraopFluidsSection: View {
    @Environment(PatientStore.self) private var patient

    private func entry(_ id: String) -> Binding<Double?> {
        Binding(get: { patient.record.fluids[id] }, set: { v in patient.update { $0.fluids[id] = v } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BloodProductsGroup()
            let typed = PatientCatalog.fluids.filter { !BloodProducts.ids.contains($0.id) }
            PatientGroup(title: "Fluids & output") {
                ForEach(Array(typed.enumerated()), id: \.element.id) { i, fl in
                    if let step = BloodProducts.fluidSteps[fl.id] {
                        BloodStepperRow(label: fl.label, unit: fl.unit, step: step, limit: BloodProducts.fluidLimit, value: entry(fl.id))
                    } else {
                        PatientNumberField(label: fl.label, unit: fl.unit, value: entry(fl.id))
                    }
                    if i < typed.count - 1 { Hairline().padding(.leading, 14) }
                }
                PatientTextField(label: "Factor concentrates & other products", prompt: "e.g. fibrinogen concentrate 2 g; PCC",
                                 text: Binding(get: { patient.record.factors }, set: { v in patient.update { $0.factors = v } }))
            }
            .id("fluidsOutput")
        }
    }
}

// MARK: 2. Lines & Devices, 5. Other Intraoperative Details

/// The lines and devices on the figure, with their list; a tap opens the lines editor.
struct IntraopDevicesCard: View {
    @Environment(PatientStore.self) private var patient
    private var r: PatientRecord { patient.record }

    /// The limb alerts and the arm to spare, the lines in place (on arrival or placed in the room, as the handoff lists
    /// them) on one line, and the mechanical support.
    static func lines(_ r: PatientRecord) -> [PatientSummary.Line] {
        var out: [PatientSummary.Line] = PatientSummary.limbAlertLines(r)
        out += PatientSummary.harvestLines(r)
        var placed: [String] = PatientDevices.labels(r.currentDevices().filter { PatientDevice.lineKinds.contains($0.kind) })
        placed += r.lines.map(\.text).filter { !$0.isEmpty }
        if !placed.isEmpty { out.append(PatientSummary.Line(nil, placed.joined(separator: "; "))) }
        out += PatientSummary.supportLines(r)
        return out
    }

    var body: some View {
        NavigationLink(value: PatientEditor.intraopPart("lines")) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.stand").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent)
                    Text("Lines & Devices").font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
                    Spacer()
                    Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                }
                // Every line and device in place now, on arrival or placed in the room, as the handoff lists them.
                let lines = Self.lines(r)
                let figure = PatientDiagramModel.items(r, phase: .all)
                if lines.isEmpty && figure.items.isEmpty && figure.cart == nil {
                    Text("Tap to draw the lines and devices: peripheral, arterial and central lines, the airway and mechanical support.")
                        .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                } else {
                    PatientDiagramCard(record: r, phase: .all, height: 260)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in PatientLineText(line: l) }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "+ Notable medication" (TXA, steroids… in the Medications & Interventions editor).
struct IntraopNotableMedicationLink: View {
    @Environment(PatientStore.self) private var patient

    var body: some View {
        IntraopLinkRow(title: "Notable medication", icon: "pills", editor: .intraopPart("meds"),
                       lines: PatientSummary.intraopPartLines(patient.record, "meds"),
                       hint: "TXA, steroids, antibiotic and time, reversal, positioning")
    }
}

/// The links under Other Intraoperative Details: echo findings, labs, regional & neuraxial, events & interventions,
/// major considerations and the case timers. Each shows what it holds once something is recorded.
struct IntraopOtherDetails: View {
    @Environment(PatientStore.self) private var patient
    private var r: PatientRecord { patient.record }

    private func link(_ part: String, _ title: String, _ icon: String, _ hint: String) -> some View {
        IntraopLinkRow(title: title, icon: icon, editor: .intraopPart(part), lines: PatientSummary.intraopPartLines(r, part), hint: hint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            link("echo", "Intraoperative echo findings", "waveform.path.ecg.rectangle", "Pre- and post-bypass TEE: LV and RV function, valves, aorta")
            link("labs", "Intraoperative labs", "testtube.2", "Blood gas and coagulation sets, each with its time")
            link("regional", "Regional & neuraxial", "figure.flexibility", "Blocks and neuraxial techniques, drugs and catheters")
            link("events", "Intraoperative events & interventions", "exclamationmark.triangle", "What happened, and whether the patient leaves intubated or extubated")
            // Safety content, kept as the last link and shown in full (red) once filled: the top of the handoff reads it.
            link("considerations", "Major considerations", "exclamationmark.bubble", "Difficult airway, massive transfusion, pressors, TEE findings, for the top of the handoff")
            if DraftGate.shows("caseTimers") { caseTimerLink }
        }
    }

    /// Opens the case timers, as My Patient's ⋯ menu does.
    private var caseTimerLink: some View {
        Button { Haptics.light(); CaseTimersUI.shared.open = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle").font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.accent).frame(width: 22)
                Text("Case timer").font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                Spacer(minLength: 6)
                Image(systemName: "timer").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg3)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a case timer")
        .accessibilityHint("Opens Case Timers for this patient")
    }
}

// MARK: Preoperative labs: when they were drawn

/// "Drawn" on the labs editor: when the preoperative labs were taken, which the summary and the handoff note, very small,
/// under the fishbone (PatientBriefs, 1.10). Optional and kept small (Ben's evening answer 1, Nov 7): one compact row in
/// the caption size, "Drawn (optional) · + Time" until a time is set, then "Drawn 06:30 · Change" with a clear button; the
/// date and time picker opens under it only while changing.
struct LabsDrawnRow: View {
    @Environment(PatientStore.self) private var patient
    @State private var editing = false

    /// The row's text size and vertical padding: a caption line, well under a lab row's height.
    static let fontSize: CGFloat = 12
    static let verticalPadding: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "clock").font(PS.sys(size: Self.fontSize - 1, weight: .semibold)).foregroundStyle(PS.fg3)
                    .accessibilityHidden(true)
                if let d = patient.record.labsDrawn {
                    // The summary's own time: "06:30" today, "11/06/26 06:30" another day.
                    Text("Drawn " + PatientSummary.time(d)).font(PS.sys(size: Self.fontSize)).foregroundStyle(PS.fg2)
                    Button { withAnimation(.snappy) { editing.toggle() } } label: {
                        Text(editing ? "Done" : "Change").font(PS.sys(size: Self.fontSize, weight: .semibold)).foregroundStyle(PS.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(editing ? "Done" : "Change the time the labs were drawn")
                    Spacer(minLength: 6)
                    Button { editing = false; patient.update(discrete: true) { $0.labsDrawn = nil } } label: {
                        Image(systemName: "xmark.circle.fill").font(PS.sys(size: Self.fontSize + 1)).foregroundStyle(PS.fg3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the time the labs were drawn")
                } else {
                    Text("Drawn (optional)").font(PS.sys(size: Self.fontSize)).foregroundStyle(PS.fg3)
                    Button { patient.update(discrete: true) { $0.labsDrawn = Date() } } label: {
                        Text("+ Time").font(PS.sys(size: Self.fontSize, weight: .semibold)).foregroundStyle(PS.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add the time the labs were drawn")
                    .accessibilityHint("Optional")
                    Spacer(minLength: 0)
                }
            }
            if editing, let d = patient.record.labsDrawn {
                DatePicker("Labs drawn", selection: Binding(get: { d }, set: { v in patient.update { $0.labsDrawn = v } }), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, Self.verticalPadding)
    }
}
