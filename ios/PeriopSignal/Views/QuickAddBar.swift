import SwiftUI

/// Quick add: one line at the top of the Preoperative and Intraoperative tabs, typed or pasted the way you'd present
/// the patient ("68M for lap chole, HTN DM2 on insulin, K 5.4"). As you type, chips show what was read and where each
/// piece goes; tap one to leave it out. Return or Add files the rest (QuickAdd, then PatientNote.apply) as one Undo
/// step in the store's history, and the snackbar's Undo steps back exactly that, the record as it was. A long paste opens the full note review instead, and the pencil opens it for
/// dictation. Read on this phone by fixed rules; the line itself is not kept.
struct QuickAddBar: View {
    @Environment(PatientStore.self) private var patient
    var tab: QuickAddTab

    @State private var text = ""
    @State private var reading: QuickAddReading?
    /// The text `reading` was read from: only what was shown is ever filed.
    @State private var readText = ""
    /// Chips left out, by chip id.
    @State private var dropped: Set<String> = []
    /// Meanings chosen for ambiguous abbreviations, by AmbiguousAbbreviation.id (for this line only).
    @State private var choices: [String: String] = [:]
    /// The user's own abbreviations, on this phone only (the full note's list).
    @State private var abbreviations = AbbreviationStore()
    @State private var added: Added?
    @State private var sheet: SheetSeed?
    @FocusState private var focused: Bool

    /// What was just filed, for the snackbar and its Undo: the record before and right after (the store's step), in
    /// which case.
    private struct Added: Equatable {
        var count: Int
        var before: PatientRecord
        var after: PatientRecord
        var caseID: UUID
        var stamp = Date()
    }

    private struct SheetSeed: Identifiable {
        var id = UUID()
        var text: String
    }

    private struct ReadKey: Hashable {
        var text: String
        var choices: [String: String]
        var tab: QuickAddTab
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var chips: [QuickAddChip] { reading.map { QuickAdd.chips($0, record: patient.record, dropped: dropped) } ?? [] }
    private var addable: [QuickAddChip] { chips.filter { $0.canAdd && !dropped.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            field
            if let added {
                snackbar(added)
            } else if let reading, !reading.isEmpty, !trimmed.isEmpty {
                preview(reading)
            }
        }
        .task(id: ReadKey(text: text, choices: choices, tab: tab)) {
            // Read about a quarter second after the typing stops.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            recompute()
        }
        .task(id: added?.stamp) {
            guard let stamp = added?.stamp else { return }
            #if DEBUG
            // The screenshot of the snackbar keeps it on screen.
            if LaunchSeed.bool("ps.quickadd.add") { return }
            #endif
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, added?.stamp == stamp else { return }
            withAnimation(.snappy) { added = nil }
        }
        .onChange(of: text) { old, new in handle(old, new) }
        .sheet(item: $sheet) { seed in
            PatientNoteSheet(initialText: seed.text, tab: tab) { n, before in
                withAnimation(.snappy) {
                    added = Added(count: n, before: before, after: patient.record, caseID: patient.currentCase.id)
                    clear()
                }
            }
            .environment(patient)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear { seedForScreenshot() }
    }

    // MARK: The field

    private var field: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "text.badge.plus")
                .font(PS.sys(size: 15, weight: .semibold))
                .foregroundStyle(PS.accent2)
                .accessibilityHidden(true)
            TextField(QuickAdd.placeholder(tab), text: $text, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .font(PS.sys(size: 15))
                .foregroundStyle(PS.fg)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { add() }
                .accessibilityLabel("Quick add")
                .accessibilityHint("Type the patient in one line. Check the chips below, then press Return to add them.")
            if !addable.isEmpty {
                Button { add() } label: { Text("Add \(addable.count)") }
                    .buttonStyle(CapsuleButtonStyle())
                    .accessibilityLabel("Add \(addable.count) item\(addable.count == 1 ? "" : "s")")
            } else if !text.isEmpty {
                Button { withAnimation(.snappy) { clear() } } label: {
                    Image(systemName: "xmark.circle.fill").font(PS.sys(size: 17)).foregroundStyle(PS.fg3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
            Button { openSheet(trimmed) } label: {
                Image(systemName: "square.and.pencil")
                    .font(PS.sys(size: 14.5, weight: .semibold))
                    .foregroundStyle(PS.accent2)
                    .frame(width: 34, height: 34)
                    .background(PS.accent2.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fill from a note")
            .accessibilityHint("Opens the full note, for long text and dictation")
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(focused ? PS.accent2.opacity(0.55) : Color.clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .onTapGesture { focused = true }
    }

    // MARK: The preview

    @ViewBuilder private func preview(_ q: QuickAddReading) -> some View {
        let shown = chips
        VStack(alignment: .leading, spacing: 7) {
            ChipFlow(spacing: 6) {
                ForEach(q.identifiers, id: \.self) { kind in identifierChip(kind) }
                // The reader's own questions first: nothing is added from them until answered.
                ForEach(q.ambiguous.filter { $0.id.hasPrefix("quick:") }) { a in ambiguousChip(a) }
                ForEach(shown) { c in chipView(c) }
                ForEach(q.ambiguous.filter { !$0.id.hasPrefix("quick:") }) { a in ambiguousChip(a) }
                ForEach(q.unknown) { u in
                    Button { openSheet(trimmed) } label: { infoChip(u.token + " · not in the list", icon: "questionmark.circle") }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the full note, where you can add what it means")
                }
                ForEach(q.skipped, id: \.self) { s in infoChip(s, icon: "arrow.uturn.right") }
                if !q.unread.isEmpty { infoChip("Not read: " + q.unread, icon: "text.badge.xmark") }
            }
            let notes = shown.filter { $0.canAdd && !dropped.contains($0.id) && $0.note != nil }
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(notes) { c in
                        (Text(c.value + ": ").font(PS.sys(size: 11.5, weight: .semibold)) + Text(c.note ?? "").font(PS.sys(size: 11.5)))
                            .foregroundStyle(PS.fg3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 2)
        .transition(.opacity)
    }

    private func chipView(_ c: QuickAddChip) -> some View {
        let out = dropped.contains(c.id)
        let off = out || !c.canAdd
        return Button {
            guard c.canAdd else { return }
            Haptics.light()
            withAnimation(.snappy) { if out { dropped.remove(c.id) } else { dropped.insert(c.id) } }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(c.destination).font(PS.sys(size: 11.5, weight: .semibold)).foregroundStyle(off ? PS.fg3 : PS.accent2)
                Text(c.value).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(off ? PS.fg3 : PS.fg)
                    .strikethrough(out, color: PS.fg3)
                if let s = c.statusText {
                    Text(s).font(PS.sys(size: 11.5, weight: .semibold)).foregroundStyle(statusColor(c.status))
                }
                if c.canAdd {
                    Image(systemName: out ? "plus" : "xmark").font(PS.sys(size: 9, weight: .bold)).foregroundStyle(PS.fg3)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(off ? PS.surface2 : PS.accent2.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(off ? PS.line2 : PS.accent2.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.text + (c.statusText.map { ", " + $0 } ?? ""))
        .accessibilityValue(out ? "Left out" : (c.canAdd ? "Will be added" : "Not added"))
        .accessibilityHint(c.canAdd ? (out ? "Puts it back" : "Leaves it out") : "")
        .accessibilityAddTraits(c.canAdd && !out ? .isSelected : [])
    }

    private func statusColor(_ s: PatientNoteStatus) -> Color {
        switch s {
        case .new, .recorded: return PS.fg3
        case .replaces: return PS.accent
        case .conflicts: return PS.accent
        }
    }

    /// An ambiguous abbreviation, read as the meaning shown: a menu to choose another (the line is read again). A
    /// question the reader asks ("SpO₂ 95% · room air?", "iCa 3.9 · mg/dL?", which laryngoscopy) uses the same menu;
    /// nothing is added from it until answered.
    private func ambiguousChip(_ a: AmbiguousAbbreviation) -> some View {
        let question = a.id.hasPrefix("quick:")
        // Answered for this value: a question says so itself; an abbreviation's choice holds unless made for another value.
        let tied = choices[a.id + "@value"]
        let picked = question ? a.fromContext : choices[a.id] != nil && (a.valueKey.isEmpty || tied == nil || tied == a.valueKey)
        let leave = question ? "Leave it out" : "Leave “\(a.abbreviation)” as written"
        let usual = a.options.first { $0.id == (question ? a.defaultID : a.chosenID) }?.text
        let shown = picked ? (a.chosen?.text ?? (question ? "left out" : "as written")) : (usual ?? (question ? "left out" : "as written"))
        let spoken: String
        if question {
            spoken = a.abbreviation + ", " + shown + (picked ? "" : "? Not added until you choose")
        } else {
            spoken = a.abbreviation + " read as " + (a.chosen?.text ?? "written")
        }
        return Menu {
            ForEach(a.options) { o in
                Button { choose(a, o.id) } label: {
                    if (picked || !question) && o.id == a.chosenID { Label(o.text, systemImage: "checkmark") } else { Text(o.text) }
                }
            }
            Divider()
            Button { choose(a, MedAbbreviations.asWritten) } label: {
                if (picked || !question) && a.chosenID == MedAbbreviations.asWritten { Label(leave, systemImage: "checkmark") } else { Text(leave) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(a.abbreviation).font(PS.mono(size: 12, weight: .bold)).foregroundStyle(PS.fg)
                Text(shown + (picked ? "" : "?"))
                    .font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent2)
                Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 9, weight: .bold)).foregroundStyle(PS.accent2)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PS.accent2.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        }
        .accessibilityLabel(spoken)
        .accessibilityHint(question ? "Choose an answer, or leave it out" : "Choose what it means here")
    }

    private func identifierChip(_ kind: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.shield.fill").font(PS.sys(size: 11, weight: .bold))
            Text("Not added: " + kind).font(PS.sys(size: 12.5, weight: .semibold))
        }
        .foregroundStyle(PS.red)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(PS.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PS.red.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Looks like " + kind + ". It is not added; take it out of the line.")
    }

    /// Shown, never filed: what was not read, or not filed from this tab.
    private func infoChip(_ s: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: icon).font(PS.sys(size: 10.5, weight: .semibold))
            Text(s).font(PS.sys(size: 12, weight: .medium))
        }
        .foregroundStyle(PS.fg3)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PS.line2, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .accessibilityElement(children: .combine)
    }

    private func snackbar(_ a: Added) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.green)
            Text("Added \(a.count)").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer(minLength: 6)
            if canUndo(a) {
                Button("Undo") { undo(a) }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
            }
            Button { withAnimation(.snappy) { added = nil } } label: {
                Image(systemName: "xmark").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.fg3).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PS.line2, lineWidth: 1))
        .transition(.opacity)
        .accessibilityElement(children: .contain)
    }

    // MARK: Actions

    private func recompute() {
        let t = trimmed
        guard !t.isEmpty else {
            reading = nil
            readText = ""
            dropped = []
            return
        }
        let q = QuickAdd.read(t, record: patient.record, tab: tab, now: Date(), abbreviations: abbreviations.items, choices: choices)
        withAnimation(.snappy) {
            reading = q
            readText = t
        }
    }

    private func handle(_ old: String, _ new: String) {
        if !new.isEmpty, added != nil { withAnimation(.snappy) { added = nil } }
        // A paste of more than a line goes to the full review, where it can be read in parts.
        if new.count - old.count > 1, QuickAdd.isLong(new) {
            text = ""
            reading = nil
            openSheet(new)
            return
        }
        // Return files the chips.
        if new.contains(where: { $0.isNewline }) {
            text = new.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            add()
        }
    }

    /// Files the chips shown and not left out. The line is read again so intraoperative labs carry the time of adding,
    /// but only chips that were on the screen go in: a line still being read is read first, not filed.
    private func add() {
        let t = trimmed
        guard !t.isEmpty else { return }
        guard let shown = reading, readText == t else { return recompute() }
        let before = patient.record
        let seen = Set(QuickAdd.chips(shown, record: before).map(\.id))
        let q = QuickAdd.read(t, record: before, tab: tab, now: Date(), abbreviations: abbreviations.items, choices: choices)
        let chosen = QuickAdd.chips(q, record: before, dropped: dropped).filter { seen.contains($0.id) && $0.canAdd && !dropped.contains($0.id) }
        guard !chosen.isEmpty else { return Haptics.light() }
        // One discrete step in the store's Undo history, whatever was typed just before.
        patient.update(discrete: true) { PatientNote.apply(QuickAdd.changes(chosen), to: &$0) }
        Haptics.success()
        withAnimation(.snappy) {
            added = Added(count: chosen.count, before: before, after: patient.record, caseID: patient.currentCase.id)
            clear()
        }
    }

    /// Undo only while the add is still the latest step of the case on screen (nothing changed since).
    private func canUndo(_ a: Added) -> Bool {
        patient.currentCase.id == a.caseID && patient.isLatestStep(before: a.before, after: a.after)
    }

    /// The store's Undo: the record exactly as it was before the add, its time stamp included.
    private func undo(_ a: Added) {
        guard canUndo(a) else { return }
        patient.undo()
        Haptics.light()
        withAnimation(.snappy) { added = nil }
    }

    private func clear() {
        text = ""
        reading = nil
        readText = ""
        dropped = []
        choices = [:]
    }

    /// Keeps the choice with the value it was made for, when the reader gives one: a changed value is asked again.
    private func choose(_ a: AmbiguousAbbreviation, _ id: String) {
        Haptics.light()
        choices[a.id] = id
        choices[a.id + "@value"] = a.valueKey.isEmpty ? nil : a.valueKey
        recompute()
    }

    private func openSheet(_ seed: String) {
        focused = false
        sheet = SheetSeed(text: seed.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Screenshot runs: -ps.quickadd "<line>" types a line into the bar; -ps.quickadd.add 1 then adds it.
    private func seedForScreenshot() {
        #if DEBUG
        let t = LaunchSeed.string("ps.quickadd")
        guard !t.isEmpty, text.isEmpty, added == nil else { return }
        text = t
        recompute()
        if LaunchSeed.bool("ps.quickadd.add") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { add() }
        }
        #endif
    }
}

/// Chips in rows; a chip wider than the row wraps its text instead of running off the screen.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
            if x > 0 && x + sz.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + sz.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
