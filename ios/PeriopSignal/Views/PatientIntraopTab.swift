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

/// A link row that opens an editor, with what the editor holds under it once something is recorded. 1.11 (P1-7, P1-9,
/// P1-10): the row keeps its own icon while empty (grey, not a ⊕), its hint is one short phrase, and a summary line
/// truncates to two lines with "…" on the tab (the page has it all); an alert line is never truncated.
struct IntraopLinkRow: View {
    var title: String
    var icon: String
    var editor: PatientEditor
    var lines: [PatientSummary.Line]
    /// What it holds, in a few words, while empty.
    var hint: String = ""
    /// Its lines are never cut (the echo findings, Ben: a finding must not end at "Sev…").
    var whole = false

    /// The parts of the Intraoperative tab whose lines are shown whole.
    static let wholeParts: Set<String> = ["echo"]

    /// How many lines a summary line may take on the tab; nil (no limit) for an alert, for a line with values marked
    /// abnormal (the last labs: a flagged value is never behind an ellipsis), and for a row shown whole.
    static func lineLimit(_ l: PatientSummary.Line, whole: Bool = false) -> Int? { whole || l.alert || !l.marks.isEmpty ? nil : 2 }

    var body: some View {
        NavigationLink(value: editor) {
            IntraopLinkRowBody(title: title, icon: icon, empty: lines.isEmpty, trailing: "chevron.right") {
                if lines.isEmpty {
                    if !hint.isEmpty {
                        Text(hint).font(PS.sys(size: PreopEmptyHints.hintFontSize)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                            PatientLineText(line: l).lineLimit(Self.lineLimit(l, whole: whole))
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel((lines.isEmpty ? "Add " : "Edit ") + title)
    }
}

/// The look the intraoperative link rows share (the case timers row too): the icon (its own, grey while empty, the
/// accent once filled), the title, a trailing symbol, and what the row holds indented under the title.
struct IntraopLinkRowBody<Content: View>: View {
    var title: String
    var icon: String
    var empty: Bool
    var trailing: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(empty ? PS.fg3 : PS.action)
                    .frame(width: 22)
                Text(title).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                Spacer(minLength: 6)
                Image(systemName: trailing).font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
            }
            content().padding(.leading, 32)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .contentShape(Rectangle())
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
        IntraopChoiceLine(label: "At handoff", options: PatientCatalog.airwayAtEndChoices(r), selection: choice(\.airwayAtEnd))
        if r.airwayAtEnd == "intubated" {
            PatientTextField(label: "Ventilation", prompt: "e.g. VC 450 × 14, PEEP 8, FiO₂ 0.5", text: text(\.ventilation))
        }
    }
}

// MARK: 3. Infusions

/// The drips: typed in a line with the drug list suggesting names and filling in the unit, then the list of what is
/// running. Used in the tab and in the Infusions editor page.
///
/// 1.11 (Ben's note 5, Q6): the drips running before the case are in this list from the start, each with a grey "from
/// preop" caption until its rate or drug is changed in the room (IntraopInfusionList: the first edit writes the case's
/// own copy, tagged through PatientInfusion.fromPreop); 🗑 takes the copy out of this list only, the preop record and the
/// handoff's "running before the case" line keep it. The Carry-over button and the "⊕ Add infusion" row are gone: the
/// type line adds drips. A record saved with both lists is merged by drug on read, so nothing doubles.
struct IntraopInfusionsSection: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    @State private var wobbling = false
    private var r: PatientRecord { patient.record }

    var body: some View {
        PatientGroup(title: "Infusions") {
            // Typed in one line, as the quick-add bar takes them (1.8.1).
            InfusionTypeField(list: \.infusions)
            // A divider above each drip, none under the last: nothing follows it since "Add an infusion" went (1.11).
            ForEach(IntraopInfusionList.rows(r)) { row in
                Hairline().padding(.leading, 14)
                infusionEditor(row)
                    .wobbleDelete($wobbling, label: row.drug.isEmpty ? "infusion" : row.drug) { patient.update(discrete: true) { IntraopInfusionList.remove(row.id, in: &$0) } }
            }
            WobbleDoneBar(editing: $wobbling)
        }
    }

    private func infusionEditor(_ row: IntraopInfusionRow) -> some View {
        let names = (refs.bundle?.infusions?.groups ?? []).flatMap { $0.drugs.map(\.name) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    ForEach(names, id: \.self) { n in
                        Button(n) { patient.update(discrete: true) { IntraopInfusionList.setDrug(row.id, n, in: &$0) } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(row.drug.isEmpty ? "Choose the drug" : row.drug).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(row.drug.isEmpty ? PS.action : PS.fg).multilineTextAlignment(.leading)
                        Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                    }
                }
                if row.fromPreop {
                    Text(IntraopInfusionList.fromPreopCaption).font(PS.sys(size: 11.5, weight: .semibold)).foregroundStyle(PS.fg3)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(PS.surface2, in: Capsule())
                        .accessibilityLabel("Running before the case")
                }
                Spacer()
                Button(role: .destructive) { patient.update(discrete: true) { IntraopInfusionList.remove(row.id, in: &$0) } } label: { Image(systemName: "trash").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(row.preopOnly ? "Take this infusion off the case's list" : "Remove this infusion")
            }
            FocusBox { f in
                TextField("Rate", text: Binding(get: { IntraopInfusionList.rows(patient.record).first { $0.id == row.id }?.rate ?? "" },
                                                set: { v in patient.update { IntraopInfusionList.setRate(row.id, v, in: &$0) } }))
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

    /// Where each line goes on the card (1.10 review): the radial-harvest arm cautions are safety content and open the card
    /// above the figure, as they opened 1.9's Lines card on the first screen; the lines in place and the mechanical support
    /// follow the figure. 1.11 (P1-10): a limb alert is said once, as the figure says it (the red marker on the limb and the
    /// figure's own list of alerts, above the figure as on the Preoperative tab's card), so the red "Limb alert" text lines
    /// are no longer in `aboveFigure`; `lines` (the handoff and the tests) still has them first.
    static func sections(_ r: PatientRecord) -> (aboveFigure: [PatientSummary.Line], belowFigure: [PatientSummary.Line]) {
        let alerts = PatientSummary.harvestLines(r)
        var rest: [PatientSummary.Line] = []
        var placed: [String] = PatientDevices.labels(r.currentDevices().filter { PatientDevice.lineKinds.contains($0.kind) })
        placed += r.lines.map(\.text).filter { !$0.isEmpty }
        if !placed.isEmpty { rest.append(PatientSummary.Line(nil, placed.joined(separator: "; "))) }
        rest += PatientSummary.supportLines(r)
        return (alerts, rest)
    }

    /// Every line the card says, the limb alerts first (the figure's caption carries them on the card itself).
    static func lines(_ r: PatientRecord) -> [PatientSummary.Line] {
        let s = sections(r)
        return PatientSummary.limbAlertLines(r) + s.aboveFigure + s.belowFigure
    }

    /// The card has something to show: a line above or below the figure, or anything drawn on it.
    static func hasContent(_ r: PatientRecord) -> Bool {
        let s = sections(r)
        let figure = PatientDiagramModel.items(r, phase: .all)
        return !(s.aboveFigure.isEmpty && s.belowFigure.isEmpty && figure.items.isEmpty && figure.cart == nil)
    }

    var body: some View {
        // 1.11 (P1-6, said once): the section title above the card already says "Lines & Devices", so the card has no
        // header of its own; its › sits at the top right, and the figure comes first.
        NavigationLink(value: PatientEditor.intraopPart("lines")) {
            VStack(alignment: .leading, spacing: 9) {
                let s = Self.sections(r)
                if !Self.hasContent(r) {
                    Text(PreopEmptyHints.intraopLines)
                        .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 24)
                } else {
                    // The arm cautions first (safety content), then the figure with its limb alerts above it (once: the
                    // marker on the limb and the caption), then the lines in place.
                    ForEach(Array(s.aboveFigure.enumerated()), id: \.offset) { _, l in PatientLineText(line: l).padding(.trailing, 24) }
                    PatientDiagramCard(record: r, phase: .all, height: 260, limbAlertsAbove: true)
                        .padding(.trailing, s.aboveFigure.isEmpty ? 24 : 0)
                    ForEach(Array(s.belowFigure.enumerated()), id: \.offset) { _, l in PatientLineText(line: l) }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3).padding(16)
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lines & Devices")
        .accessibilityHint("Opens the lines page")
    }
}

/// "Antibiotics & Notable Medications" (1.12, Ben's note 2; its page keeps the name Medications & Interventions): the
/// antibiotics charted in Case Timers for the open case with their times (note 3), the notable medications chosen as chips
/// with their doses (note 18), and the free text the page had.
struct IntraopNotableMedicationLink: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs

    static let title = "Antibiotics & Notable Medications"
    /// One short phrase while empty; it fits one line at 375 pt (the tests measure it).
    static let hint = "Antibiotics, TXA, milrinone, reversal"

    /// The row's lines: each charted antibiotic ("Cefazolin 2 g · last 08:12 · next due 12:12", red when its redose is
    /// overdue), the chosen chips with their doses, then the free text. Empty while nothing is recorded. The row shows
    /// them whole: a dose or a redose time is never behind an ellipsis.
    static func lines(_ r: PatientRecord, antibiotics: [CaseAntibiotics.Line]) -> [PatientSummary.Line] {
        var out = antibiotics.map { PatientSummary.Line(nil, $0.tabText, alert: $0.overdue) }
        if !r.notableMeds.isEmpty { out.append(PatientSummary.Line(nil, r.notableMeds.items.joined(separator: "; "))) }
        let free = r.capitalized.medsGiven.trimmingCharacters(in: .whitespacesAndNewlines)
        if !free.isEmpty { out.append(PatientSummary.Line(nil, free)) }
        return out
    }

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let r = patient.record
            IntraopLinkRow(title: Self.title, icon: "pills", editor: .intraopPart("meds"),
                           lines: Self.lines(r, antibiotics: CaseAntibiotics.lines(r, data: refs.caseTimers ?? CaseAntibiotics.current, now: ctx.date)),
                           hint: Self.hint, whole: true)
        }
    }
}

/// The links under Other Intraoperative Details: echo findings, labs, regional & neuraxial, events & interventions,
/// major considerations and the case timers. Each shows what it holds once something is recorded; while empty, its own
/// icon and a one-phrase hint (1.11, P1-7 and P1-9).
struct IntraopOtherDetails: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    private var r: PatientRecord { patient.record }

    private func link(_ part: String, _ title: String, _ icon: String) -> some View {
        IntraopLinkRow(title: title, icon: icon, editor: .intraopPart(part), lines: PatientSummary.intraopPartLines(r, part),
                       hint: PreopEmptyHints.intraop[part] ?? "", whole: IntraopLinkRow.wholeParts.contains(part))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            link("echo", "Intraoperative echo findings", "waveform.path.ecg.rectangle")
            link("labs", "Intraoperative labs", "testtube.2")
            link("regional", "Regional & neuraxial", "figure.flexibility")
            link("events", "Intraoperative events & interventions", "exclamationmark.triangle")
            // Safety content, kept as the last link and shown in full (red) once filled: the top of the handoff reads it.
            link("considerations", "Major considerations", "exclamationmark.bubble")
            if DraftGate.shows("caseTimers") { caseTimerLink }
        }
    }

    /// The case timers row's title: "+ Case timers" while none runs, "Case timers" once some do.
    static func caseTimersTitle(running: Int) -> String { running > 0 ? PreopEmptyHints.caseTimersRunning : PreopEmptyHints.caseTimersNone }

    /// The row's scroll id: the last row of the tab, which a screenshot reaches with -ps.patient.scroll casetimers (shot 816).
    static let caseTimersScrollID = "casetimers"

    /// Opens the case timers, as My Patient's ⋯ menu does: a row like its neighbours, with ⏱ as its icon and › on the
    /// right; "+ Case timers" while none runs, else "Case timers" with the timers that are running under it.
    private var caseTimerLink: some View {
        let reminders = refs.caseTimers.map { CaseTimerEngine.reminders(r.timers, record: r, data: $0) } ?? []
        return Button { Haptics.light(); CaseTimersUI.shared.open = true } label: {
            IntraopLinkRowBody(title: Self.caseTimersTitle(running: reminders.count), icon: "timer", empty: reminders.isEmpty, trailing: "chevron.right") {
                if !reminders.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(reminders.prefix(3)) { rem in
                            Text(rem.title).font(PS.sys(size: 14)).foregroundStyle(PS.fg).lineLimit(1)
                        }
                        if reminders.count > 3 {
                            Text("+ \(reminders.count - 3) more").font(PS.sys(size: PreopEmptyHints.hintFontSize)).foregroundStyle(PS.fg3)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .id(Self.caseTimersScrollID)
        .accessibilityLabel(reminders.isEmpty ? "Add a case timer" : "Case timers, \(reminders.count) running")
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
                        Text(editing ? "Done" : "Change").font(PS.sys(size: Self.fontSize, weight: .semibold)).foregroundStyle(PS.action)
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
                        Text("+ Time").font(PS.sys(size: Self.fontSize, weight: .semibold)).foregroundStyle(PS.action)
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
                    .environment(\.locale, PatientDates.locale24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, Self.verticalPadding)
    }
}
