import SwiftUI

// MARK: - 1.9 briefs on screen: the fishbone, the lines diagram with its list, the editable blocks, the preprocedure
// summary and Status & Plan. The blocks and their text are in Shared/PatientBriefs.swift.

private extension PatientStore {
    func bound<T>(_ kp: WritableKeyPath<PatientRecord, T>) -> Binding<T> {
        Binding(get: { self.record[keyPath: kp] }, set: { v in self.update { $0[keyPath: kp] = v } })
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
    /// 1.12: the figure a shared picture is drawn with (BriefPages.Context.figure); on screen, the reference store's.
    @Environment(\.briefFigure) private var pictureFigure
    var record: PatientRecord
    var arrivalOnly: Bool
    var lines: [String]
    var marks: [String]

    var body: some View {
        let m = PatientDiagramModel.items(record, phase: arrivalOnly ? .preop : .all)
        if let fig = pictureFigure ?? refs.bundle?.regional?.figure, !m.items.isEmpty {
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
        // 1.12: a mark paints only where it stands alone ("K 5.9" is not the start of "K 5.95").
        a.paintMarks(marks, in: line, font: PS.sys(size: size, weight: .bold))
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
    @Environment(\.briefOnPage) private var onPage

    private var multiline: Bool { block.lines.count > 1 }
    private var isHeader: Bool { block.key == "header" }

    /// The small mark after the words of a block the user edited, the header too (its age, weight or procedure then no
    /// longer follow the record); "" for one that was not.
    static func editedMark(_ b: SummaryBlock) -> String { b.edited ? "  edited" : "" }

    private var labelRow: some View {
        HStack(spacing: 6) {
            if let l = block.label {
                Text(l + ":").font(PS.sys(size: 14.5, weight: .bold)).foregroundStyle(block.alert ? PS.red : PS.fg)
            }
            if block.edited && !onPage {
                Text("edited").font(PS.sys(size: 10, weight: .semibold)).foregroundStyle(PS.fg3)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .overlay(Capsule().stroke(PS.line2, lineWidth: 1))
                    .accessibilityLabel("Edited")
            }
        }
    }

    @ViewBuilder private var readView: some View {
        switch block.figure {
        case .fishbone(let labs)? where !block.edited:
            // 1.12 (Ben's note 8): the Preop and Intraop columns. A block the user edited shows their words instead (the
            // text holds everything the columns show).
            VStack(alignment: .leading, spacing: 6) {
                labelRow
                BriefLabsFigure(labs: labs)
            }
            .id("fishbone")
        case .diagram(let arrivalOnly)?:
            VStack(alignment: .leading, spacing: 6) {
                labelRow
                BriefDiagramList(record: record, arrivalOnly: arrivalOnly, lines: block.lines, marks: block.marks)
            }
            .id(arrivalOnly ? "preopfigure" : "handofffigure")
        case .fishbone?, nil:
            if isHeader {
                (Text(block.text).font(PS.sys(size: 15.5, weight: .semibold)).foregroundColor(PS.fg)
                 + Text(Self.editedMark(block)).font(PS.sys(size: 10, weight: .semibold)).foregroundColor(PS.fg3))
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
                (Text(block.label.map { $0 + ": " } ?? "").font(PS.sys(size: 14.5, weight: .bold)).foregroundColor(block.alert ? PS.red : PS.fg)
                 + Text(briefStyled(block.text, marks: block.marks, labels: false)).font(PS.sys(size: 14.5)).foregroundColor(PS.fg)
                 + Text(Self.editedMark(block)).font(PS.sys(size: 10, weight: .semibold)).foregroundColor(PS.fg3))
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
                        .buttonStyle(CapsuleButtonStyle.patientAction())
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

    private var record: PatientRecord { patient.record }
    private var all: [SummaryBlock] { PatientBriefs.blocks(kind, record) }
    private var shown: [SummaryBlock] {
        guard !startAt.isEmpty, let i = all.firstIndex(where: { ($0.label ?? "").lowercased().hasPrefix(startAt.lowercased()) }) else { return all }
        return Array(all[i...])
    }
    private var title: String { kind == .preop ? "Preprocedure summary" : "Handoff, as it stands" }

    /// The handoff keeps its eyebrow (the Summary & Handoff tab has no section title above it); the preoperative brief
    /// does not (1.11, P1-6).
    static func showsEyebrow(_ kind: PatientBriefs.Kind) -> Bool { kind != .preop }

    /// The preoperative brief's Regenerate sits on its section title's line ("Preprocedure Summary · Regenerate", 1.11,
    /// P1-6: PatientView.summarySection), so the panel draws no header row for it; the handoff keeps its eyebrow and
    /// Regenerate on one row.
    static func regenerateOnTitleLine(_ kind: PatientBriefs.Kind) -> Bool { !showsEyebrow(kind) }

    /// Share (1.12, Ben): the menu offers Image first (the summary as it looks, on white pages at phone width), then PDF and
    /// Text only (the text and its footer, as Share sent before). Copy stays plain text.
    private var shareMenu: some View {
        Menu {
            ForEach(BriefShareFormat.allCases, id: \.self) { f in
                Button { share(f) } label: { Label(f.title, systemImage: f.icon) }
                    .disabled(f != .text && all.isEmpty)
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
                .font(PS.sys(size: 16, weight: .semibold))
                .padding(.vertical, 14)
                .background(PS.action, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(PS.accentFg)
        }
        .accessibilityLabel("Share")
        .accessibilityHint("Choose Image, PDF or Text only")
    }

    /// Draws the summary in the chosen form and opens the share sheet with it (rendering runs on the main actor).
    private func share(_ format: BriefShareFormat) {
        let ctx = BriefPages.Context(record: record, refs: refs, patient: patient, figure: refs.bundle?.regional?.figure)
        switch format {
        case .image:
            let pages = BriefPages.images(all, ctx)
            if !pages.isEmpty { sharing = pages }
        case .pdf:
            if let url = BriefPages.pdfFile(all, ctx) { sharing = [url] }
        case .text:
            sharing = HandoffShare.textOnlyItems(all)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !Self.regenerateOnTitleLine(kind) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow(text: title)
                    Spacer()
                    BriefRegenerateButton(kind: kind)
                }
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
            // 1.12 (Ben, note 14): "+ Add other input data into Handoff" sits directly under the card, above Share and Copy.
            // An extras change reaches the blocks it touches through the record; a block the user edited keeps its edit
            // until Regenerate (PatientBriefs.resolve).
            HandoffExtrasLink()
            Text("Tap any text to edit it. Your edits stay as the record changes; Regenerate brings back the generated text.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
            HStack(spacing: 10) {
                shareMenu
                Button { HandoffShare.copy(blocks: all); copied.toggle() } label: {
                    Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(prominent: false))
            }
            .id("briefshare")
            #if DEBUG
            if !LaunchSeed.string("ps.brief.pages").isEmpty { BriefPagesPreview(blocks: all, mode: LaunchSeed.string("ps.brief.pages")) }
            #endif
        }
        .sensoryFeedback(.success, trigger: copied)
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            ShareSheet(items: sharing ?? []).presentationDetents([.medium, .large])
        }
    }
}

/// A brief's Regenerate: off until the brief has an edit; asks, then clears this brief's edits (Undo brings them back).
/// On the handoff's eyebrow row, and on the Preprocedure Summary title's line.
struct BriefRegenerateButton: View {
    /// How much of the capsule is drawn: icon and word, the word alone, or the icon alone. The narrower forms are for
    /// the Preprocedure Summary title's line on a narrow phone (PreopSectionTitle); all three are spoken the same.
    enum LabelForm: CaseIterable { case full, word, icon }
    static let spokenName = "Regenerate"

    @Environment(PatientStore.self) private var patient
    var kind: PatientBriefs.Kind
    var form: LabelForm = .full
    @State private var confirming = false

    private var edited: Bool { !PatientBriefs.edits(kind, patient.record).isEmpty }

    @ViewBuilder static func label(_ form: LabelForm) -> some View {
        switch form {
        case .full: Label(spokenName, systemImage: "arrow.clockwise")
        case .word: Text(spokenName)
        // At least 18 points of icon, so the capsule (13 points of padding each side) is 44 wide to tap.
        case .icon: Image(systemName: "arrow.clockwise").frame(minWidth: 18)
        }
    }

    var body: some View {
        Button { confirming = true } label: { Self.label(form) }
            .buttonStyle(CapsuleButtonStyle(prominent: false))
            .accessibilityLabel(Self.spokenName)
            .disabled(!edited)
            .opacity(edited ? 1 : 0.45)
            .accessibilityHint("Rebuilds this text from the record and clears your edits")
            .confirmationDialog("Regenerate this text from the record?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Regenerate", role: .destructive) {
                    patient.update(discrete: true) { PatientBriefs.regenerate(&$0, kind) }
                }
                Button("Keep my edits", role: .cancel) {}
            } message: {
                Text("Your edits to this text are cleared. Undo brings them back.")
            }
    }
}

// MARK: Preprocedure summary

/// The Preprocedure tab's last section: "+ Generate preprocedure summary", then the brief (record.preopSummaryOn). Nothing
/// at all until the record has an age or a procedure (1.11, P1-9: no disabled button; the rule, offersSummary, is in
/// PatientPreopViews.swift).
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
        } else if Self.offersSummary(patient.record) {
            Button { Haptics.light(); patient.update(discrete: true) { $0.preopSummaryOn = true } } label: {
                Label("Generate preprocedure summary", systemImage: "plus")
            }
            .buttonStyle(CapsuleButtonStyle.patientAction())
            .id("preopsummary")
        } else {
            // An empty record has nothing to summarize: one phrase, so the section does not read as cut off.
            Text("Appears once something is recorded.")
                .font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
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
    /// Other was tapped (or its box is being typed in): the box stays, and Other stays chosen, while the words typed
    /// begin like a chip's label ("ICU step-down") or are only a space so far.
    @State private var otherOpen = false
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

    /// The chip shown as chosen: Other while its box is open, whatever has been typed so far.
    static func selectedChip(_ saved: String?, otherOpen: Bool) -> String? {
        otherOpen ? "Other" : dispositionChip(saved)
    }

    /// The Other box shows while it is open or the saved value is other words.
    static func showsOtherField(_ saved: String?, otherOpen: Bool) -> Bool {
        otherOpen || dispositionChip(saved) == "Other"
    }

    /// The words in the Other box: while it is open, exactly what was typed (even "ICU" on the way to "ICU step-down").
    static func otherFieldText(_ saved: String?, otherOpen: Bool) -> String {
        guard otherOpen else { return otherText(saved) }
        guard let s = saved, s != "Other" else { return "" }
        return s
    }

    private var airway: Binding<String?> {
        Binding(get: { r.airwayAtEnd }, set: { v in patient.update(discrete: true) { $0.airwayAtEnd = v } })
    }

    private var disposition: Binding<String?> {
        Binding(get: { Self.selectedChip(r.disposition, otherOpen: otherOpen) },
                set: { v in
                    otherOpen = v == "Other"
                    // Other keeps the words already typed for it.
                    if v == "Other", Self.dispositionChip(r.disposition) == "Other" { return }
                    patient.update(discrete: true) { $0.disposition = v }
                })
    }

    private var otherBinding: Binding<String> {
        Binding(get: { Self.otherFieldText(r.disposition, otherOpen: otherOpen) },
                set: { t in
                    otherOpen = true
                    patient.update { $0.disposition = t.isEmpty ? "Other" : t }
                })
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg3)
            content()
        }
    }

    // 1.11 (P1-6): a plain box with the STATUS & PLAN caption, as every other box with controls in place; the card header
    // with an icon and a 16-pt title looked like a card that opens a page, and it opens nothing.
    var body: some View {
        PatientGroup(title: "Status & Plan") { rows.padding(.horizontal, 14).padding(.vertical, 10) }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Airway") { PatientChoice(options: Self.airwayOptions(r.airwayAtEnd), selection: airway) }
            row("Disposition") {
                PatientChoice(options: (Self.dispositionChips + ["Other"]).map { (id: $0, label: $0) }, selection: disposition)
                if Self.showsOtherField(r.disposition, otherOpen: otherOpen) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
