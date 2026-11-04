import SwiftUI

// MARK: - 1.9 briefs on screen: the fishbone, the lines diagram with its list, the editable blocks, the preprocedure
// summary and Status & Plan. The blocks and their text are in Shared/PatientBriefs.swift.

private extension PatientStore {
    func bound<T>(_ kp: WritableKeyPath<PatientRecord, T>) -> Binding<T> {
        Binding(get: { self.record[keyPath: kp] }, set: { v in self.update { $0[keyPath: kp] = v } })
    }
}

// MARK: Fishbone

/// A small "<" or ">" for the fishbone: a wedge whose point is on the left or the right.
private struct FishboneWedge: Shape {
    var pointsLeft: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if pointsLeft {
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        return p
    }
}

/// The labs as the fishbone: BMP (Na, Cl, BUN over K, HCO₃, Cr, with the glucose at the point), CBC (WBC, Hb over Hct,
/// Plt) and the coagulation values (PT over INR, PTT, fibrinogen). A value not entered is a dash in a group that has
/// something; abnormal values bold red, as the Labs screen marks them; values from the case end in *. Small, and
/// legible in light and dark.
struct FishboneFigure: View {
    var labs: BriefLabs

    private let cellWidth: CGFloat = 40
    private let rowHeight: CGFloat = 30

    private func cell(_ key: String, _ name: String) -> some View {
        let c = labs.cells[key]
        let color: Color = c == nil || c?.estimated == true ? PS.fg3 : (c?.abnormal == true ? PS.red : PS.fg)
        return VStack(spacing: 0) {
            Text(c.map { ($0.estimated ? "~" : "") + $0.text + ($0.intraop ? "*" : "") } ?? "—")
                .font(PS.sys(size: 12.5, weight: c?.abnormal == true ? .heavy : .semibold, design: .monospaced))
                .italic(c?.estimated == true)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(name).font(PS.sys(size: 8)).foregroundStyle(PS.fg3)
        }
        .frame(width: cellWidth, height: rowHeight)
    }

    private func vRule() -> some View { Rectangle().fill(PS.line2).frame(width: 1, height: rowHeight - 6) }
    private func hRule(_ width: CGFloat) -> some View { Rectangle().fill(PS.line2).frame(width: width, height: 1) }

    private var bmp: some View {
        HStack(spacing: 3) {
            VStack(spacing: 0) {
                HStack(spacing: 0) { cell("na", "Na"); vRule(); cell("cl", "Cl"); vRule(); cell("bun", "BUN") }
                hRule(cellWidth * 3 + 2)
                HStack(spacing: 0) { cell("k", "K"); vRule(); cell("hco3", "HCO₃"); vRule(); cell("cr", "Cr") }
            }
            FishboneWedge(pointsLeft: true).stroke(PS.line2, lineWidth: 1).frame(width: 12, height: 26)
            cell("glucose", "Glu")
        }
    }

    private var cbc: some View {
        HStack(spacing: 0) {
            cell("wbc", "WBC")
            FishboneWedge(pointsLeft: false).stroke(PS.line2, lineWidth: 1).frame(width: 12, height: 26)
            VStack(spacing: 0) {
                cell("hb", "Hb")
                hRule(cellWidth)
                cell("hct", "Hct")
            }
            FishboneWedge(pointsLeft: true).stroke(PS.line2, lineWidth: 1).frame(width: 12, height: 26)
            cell("plt", "Plt")
        }
    }

    private var coags: some View {
        HStack(spacing: 0) {
            if labs.cells["pt"] != nil || labs.cells["inr"] != nil {
                VStack(spacing: 0) {
                    cell("pt", "PT")
                    hRule(cellWidth)
                    cell("inr", "INR")
                }
                vRule()
            }
            if labs.cells["ptt"] != nil { cell("ptt", "PTT") }
            if labs.cells["fibrinogen"] != nil {
                if labs.cells["ptt"] != nil || labs.cells["pt"] != nil || labs.cells["inr"] != nil { vRule() }
                cell("fibrinogen", "Fib")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if labs.hasBMP { bmp }
            if labs.hasCBC { cbc }
            if labs.hasCoags { coags }
            if let c = labs.caption {
                Text(c).font(PS.sys(size: 10.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Labs: " + labs.plainFishbone() + (labs.caption.map { ". " + $0 } ?? ""))
    }
}

// MARK: Lines diagram with its list

/// The diagram on the left and the block's lines on the right (lines and devices, each with "(Pre)" or "(Intra)" in the
/// handoff). Drawn at the size its labels need, then scaled to fit the left column; the list is the legible text.
struct BriefDiagramLayout: View {
    var figure: RegionalFigure
    var items: [DiagramItem]
    var cart: DiagramCart?
    var lines: [String]
    var marks: [String]
    /// Scale of the drawing (1 is the legible size, 350 points high).
    var scale: CGFloat = 0.78
    var listFont: CGFloat = 12.5

    static let natural = CGSize(width: 246, height: 350)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PatientDiagramCanvas(figure: figure, items: items, cart: cart)
                .frame(width: Self.natural.width, height: Self.natural.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: Self.natural.width * scale, height: Self.natural.height * scale, alignment: .topLeading)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    Text(briefStyled(l, marks: marks, labels: true, size: listFont))
                        .font(PS.sys(size: listFont)).foregroundStyle(PS.fg)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The lines block's figure from the environment (the regional figure and the record's devices).
struct BriefDiagramList: View {
    @Environment(ReferenceStore.self) private var refs
    var record: PatientRecord
    var arrivalOnly: Bool
    var lines: [String]
    var marks: [String]

    var body: some View {
        let m = PatientDiagramModel.items(record, phase: arrivalOnly ? .preop : .all)
        if let fig = refs.bundle?.regional?.figure, !m.items.isEmpty {
            BriefDiagramLayout(figure: fig, items: m.items, cart: m.cart, lines: lines, marks: marks)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    Text(briefStyled(l, marks: marks, labels: true, size: 14)).font(PS.sys(size: 14)).foregroundStyle(PS.fg)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: Styled text

/// The text of a block: each line's label up to its first ": " bold when `labels`, and the marked parts (abnormal values,
/// the orders that limit resuscitation) in bold red.
func briefStyled(_ text: String, marks: [String], labels: Bool, size: CGFloat = 14.5) -> AttributedString {
    var out = AttributedString()
    let lines = text.components(separatedBy: "\n")
    for (i, line) in lines.enumerated() {
        var a = AttributedString(line)
        if labels {
            let sub = Substring(line)
            if let r = HandoffStyle.labelRange(sub) {
                let lo = a.startIndex
                let hi = a.index(lo, offsetByCharacters: line.distance(from: line.startIndex, to: r.upperBound))
                a[lo..<hi].font = PS.sys(size: size, weight: .bold)
            }
        }
        for m in marks where !m.isEmpty {
            var from = a.startIndex
            while from < a.endIndex, let r = a[from...].range(of: m) {
                a[r].foregroundColor = PS.red
                a[r].font = PS.sys(size: size, weight: .bold)
                from = r.upperBound
            }
        }
        out.append(a)
        if i < lines.count - 1 { out.append(AttributedString("\n")) }
    }
    return out
}

// MARK: One block

/// A block: its label and text (tap to edit in place), with the figure for the labs and the lines. An edited block carries
/// a small "edited" mark.
struct BriefBlockView: View {
    var record: PatientRecord
    var block: SummaryBlock
    var onCommit: (String, String) -> Void
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private var multiline: Bool { block.lines.count > 1 }
    private var isHeader: Bool { block.key == "header" }

    private var labelRow: some View {
        HStack(spacing: 6) {
            if let l = block.label {
                Text(l + ":").font(PS.sys(size: 14.5, weight: .bold)).foregroundStyle(block.alert ? PS.accent : PS.fg)
            }
            if block.edited {
                Text("edited").font(PS.sys(size: 10, weight: .semibold)).foregroundStyle(PS.fg3)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .overlay(Capsule().stroke(PS.line2, lineWidth: 1))
                    .accessibilityLabel("Edited")
            }
        }
    }

    @ViewBuilder private var readView: some View {
        switch block.figure {
        case .fishbone(let labs)?:
            VStack(alignment: .leading, spacing: 6) {
                labelRow
                let wide = typeSize > .large || block.text.count > 150
                if wide {
                    VStack(alignment: .leading, spacing: 8) { FishboneFigure(labs: labs); sideText }
                } else {
                    HStack(alignment: .top, spacing: 12) { FishboneFigure(labs: labs); sideText }
                }
            }
        case .diagram(let arrivalOnly)?:
            VStack(alignment: .leading, spacing: 6) {
                labelRow
                BriefDiagramList(record: record, arrivalOnly: arrivalOnly, lines: block.lines, marks: block.marks)
            }
            .id(arrivalOnly ? "preopfigure" : "handofffigure")
        case nil:
            if isHeader {
                Text(block.text).font(PS.sys(size: 15.5, weight: .semibold)).foregroundStyle(PS.fg)
                    .fixedSize(horizontal: false, vertical: true)
            } else if multiline {
                VStack(alignment: .leading, spacing: 3) {
                    labelRow
                    Text(briefStyled(block.text, marks: block.marks, labels: true))
                        .font(PS.sys(size: 14.5)).foregroundStyle(PS.fg).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 12)
                }
            } else {
                // The label and the words on one line, so the paragraph wraps under both.
                (Text(block.label.map { $0 + ": " } ?? "").font(PS.sys(size: 14.5, weight: .bold)).foregroundColor(block.alert ? PS.accent : PS.fg)
                 + Text(briefStyled(block.text, marks: block.marks, labels: false)).font(PS.sys(size: 14.5)).foregroundColor(PS.fg)
                 + Text(block.edited ? "  edited" : "").font(PS.sys(size: 10, weight: .semibold)).foregroundColor(PS.fg3))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sideText: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(block.lines.enumerated()), id: \.offset) { _, l in
                Text(briefStyled(l, marks: block.marks, labels: false, size: 13)).font(PS.sys(size: 13)).foregroundStyle(PS.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editing {
                VStack(alignment: .leading, spacing: 6) {
                    labelRow
                    TextEditor(text: $draft)
                        .font(PS.sys(size: 14.5))
                        .foregroundStyle(PS.fg)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                        .frame(minHeight: 84)
                        .padding(6)
                        .background(PS.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("Edit " + (block.label ?? "header"))
                    HStack(spacing: 8) {
                        Button("Done") {
                            onCommit(block.key, draft)
                            editing = false
                        }
                        .buttonStyle(CapsuleButtonStyle(prominent: true))
                        Button("Cancel") { editing = false }
                            .buttonStyle(CapsuleButtonStyle(prominent: false))
                        Spacer(minLength: 0)
                    }
                }
            } else {
                readView
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        draft = block.text
                        editing = true
                        focused = true
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Edit this text")
            }
        }
    }
}

// MARK: The brief

/// A brief on screen: its blocks (tap a block's text to edit), Share, Copy, and Regenerate. An edit is kept in the record
/// (PatientStore.update, so Undo steps it back) and stays through changes to the record; Regenerate asks, then clears this
/// brief's edits.
struct BriefPanel: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    var kind: PatientBriefs.Kind
    /// Screenshot runs: start at the block whose label begins with this (-ps.handoff.from).
    var startAt: String = ""
    @State private var sharing: [Any]?
    @State private var copied = false
    @State private var confirming = false

    private var record: PatientRecord { patient.record }
    private var all: [SummaryBlock] { PatientBriefs.blocks(kind, record) }
    private var shown: [SummaryBlock] {
        guard !startAt.isEmpty, let i = all.firstIndex(where: { ($0.label ?? "").lowercased().hasPrefix(startAt.lowercased()) }) else { return all }
        return Array(all[i...])
    }
    private var edited: Bool { !PatientBriefs.edits(kind, record).isEmpty }

    private var title: String { kind == .preop ? "Preprocedure summary" : "Handoff, as it stands" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: title)
                Spacer()
                Button { confirming = true } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
                    .disabled(!edited)
                    .opacity(edited ? 1 : 0.45)
                    .accessibilityHint("Rebuilds this text from the record and clears your edits")
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(shown) { b in
                    BriefBlockView(record: record, block: b) { key, text in
                        patient.update(discrete: true) { PatientBriefs.setEdit(&$0, kind, key: key, text: text) }
                    }
                }
                if shown.isEmpty {
                    Text("Nothing to summarize yet.").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            Text("Tap any text to edit it. Your edits stay as the record changes; Regenerate brings back the generated text.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
            HStack(spacing: 10) {
                Button { sharing = HandoffShare.briefItems(all, record: record, figure: refs.bundle?.regional?.figure) } label: {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(prominent: true))
                Button { HandoffShare.copy(blocks: all); copied.toggle() } label: {
                    Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(prominent: false))
            }
        }
        .sensoryFeedback(.success, trigger: copied)
        .confirmationDialog("Regenerate this text from the record?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Regenerate", role: .destructive) {
                patient.update(discrete: true) { PatientBriefs.regenerate(&$0, kind) }
            }
            Button("Keep my edits", role: .cancel) {}
        } message: {
            Text("Your edits to this text are cleared. Undo brings them back.")
        }
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            ShareSheet(items: sharing ?? []).presentationDetents([.medium, .large])
        }
    }
}

// MARK: Preprocedure summary

/// The Preprocedure tab's last section: "+ Generate preprocedure summary", then the brief (record.preopSummaryOn). A record
/// with nothing in it has nothing to summarize: the button is off.
struct PreprocedureSummaryView: View {
    @Environment(PatientStore.self) private var patient

    var body: some View {
        if patient.record.preopSummaryOn {
            VStack(alignment: .leading, spacing: 10) {
                BriefPanel(kind: .preop)
                Button { patient.update(discrete: true) { $0.preopSummaryOn = false } } label: { Text("Hide summary") }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
            }
            .id("preopsummary")
        } else {
            Button { Haptics.light(); patient.update(discrete: true) { $0.preopSummaryOn = true } } label: {
                Label("Generate preprocedure summary", systemImage: "plus")
            }
            .buttonStyle(CapsuleButtonStyle(prominent: true))
            .disabled(patient.isEmpty)
            .opacity(patient.isEmpty ? 0.45 : 1)
            .id("preopsummary")
        }
    }
}

// MARK: Status & Plan

/// Status & Plan on the Summary & Handoff tab (Ben): short chips, no folder. Airway (intubated or extubated), Disposition
/// (fast track, PACU, ICU, or other with its text) and To do & Concerns. The disposition stores the chip's label or the
/// typed text; a saved "Ward" or "Same-day discharge" shows as Other with that text, and a saved "sga" or "natural"
/// airway shows as its own chip until changed. The pain plan and call-if typed before 1.9 show only when they hold text.
struct StatusPlanCard: View {
    @Environment(PatientStore.self) private var patient
    private var r: PatientRecord { patient.record }

    static let dispositionChips = ["Fast track", "PACU", "ICU"]

    /// The airway chips: the two Ben asked for, and a saved other value as its own chip.
    static func airwayOptions(_ saved: String?) -> [(id: String, label: String)] {
        var out: [(id: String, label: String)] = [("intubated", "Intubated"), ("extubated", "Extubated")]
        if let s = saved, !["intubated", "extubated"].contains(s) {
            out.append((s, PatientCatalog.airwayAtEnd.first { $0.id == s }?.label ?? s))
        }
        return out
    }

    /// The selected disposition chip for the saved value.
    static func dispositionChip(_ saved: String?) -> String? {
        guard let s = saved, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return dispositionChips.contains(s) ? s : "Other"
    }

    /// The text beside "Other": the saved value unless it is the bare word.
    static func otherText(_ saved: String?) -> String {
        guard let s = saved, dispositionChip(s) == "Other", s != "Other" else { return "" }
        return s
    }

    private var airway: Binding<String?> {
        Binding(get: { r.airwayAtEnd }, set: { v in patient.update(discrete: true) { $0.airwayAtEnd = v } })
    }

    private var disposition: Binding<String?> {
        Binding(get: { Self.dispositionChip(r.disposition) },
                set: { v in patient.update(discrete: true) { $0.disposition = v } })
    }

    private var otherBinding: Binding<String> {
        Binding(get: { Self.otherText(r.disposition) },
                set: { t in patient.update { $0.disposition = t.isEmpty ? "Other" : t } })
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg3)
            content()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent)
                Text("Status & Plan").font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
            }
            row("Airway") { PatientChoice(options: Self.airwayOptions(r.airwayAtEnd), selection: airway) }
            row("Disposition") {
                PatientChoice(options: (Self.dispositionChips + ["Other"]).map { (id: $0, label: $0) }, selection: disposition)
                if Self.dispositionChip(r.disposition) == "Other" {
                    PlanField(prompt: "Where the patient goes, e.g. Ward", text: otherBinding)
                }
            }
            row("To do & Concerns") {
                PlanField(prompt: "For the next team: labs, antibiotic redosing, when to call, pain plan", text: patient.bound(\.todos))
            }
            if !r.painPlan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                row("Pain plan") { PlanField(prompt: "Pain plan", text: patient.bound(\.painPlan)) }
            }
            if !r.callIf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                row("Call if") { PlanField(prompt: "When to call", text: patient.bound(\.callIf)) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }
}

/// A free-text box of Status & Plan: grows with what is typed and starts with a capital once left (FreeText.cap).
private struct PlanField: View {
    var prompt: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $text, axis: .vertical)
            .lineLimit(1...8)
            .focused($focused)
            .onChange(of: focused) { _, now in if !now { let c = FreeText.cap(text); if c != text { text = c } } }
            .font(PS.sys(size: 15))
            .foregroundStyle(PS.fg)
            .padding(10)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
