import SwiftUI

/// Drips typed in one line, in the quick-add bar's style (1.8.1): "norepi 0.05, vaso 0.04". As you type, the drug list
/// suggests names; chips show what will be added (tap one to leave it out) and ask when the drug or the unit could be
/// more than one. Add or Return files the chips as one Undo step. Read by InfusionEntry; nothing is filled in that was
/// not typed.
struct InfusionTypeField: View {
    @Environment(PatientStore.self) private var patient
    /// The list the drips go into: the intraoperative infusions or the current infusions before the case.
    var list: WritableKeyPath<PatientRecord, [PatientInfusion]>

    @State private var text = ""
    @State private var choices: [String: String] = [:]
    @State private var dropped: Set<String> = []
    @FocusState private var focused: Bool

    static let placeholder = "Type a drip, e.g. norepi 0.05"

    private var reading: InfusionEntry.Reading { InfusionEntry.read(text, choices: choices) }
    private var addable: [InfusionEntry.Item] { reading.items.filter { !dropped.contains($0.id) && canAdd($0) } }

    private func canAdd(_ it: InfusionEntry.Item) -> Bool {
        if case .recorded = InfusionEntry.status(it, in: patient.record[keyPath: list]) { return false }
        return true
    }

    var body: some View {
        let r = reading
        let suggestions = InfusionEntry.suggestions(text)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "text.badge.plus")
                    .font(PS.sys(size: 15, weight: .semibold))
                    .foregroundStyle(PS.accent2)
                    .accessibilityHidden(true)
                TextField(Self.placeholder, text: $text)
                    .focused($focused)
                    .font(PS.sys(size: 15)).foregroundStyle(PS.fg)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(add)
                    .accessibilityLabel("Type a drip")
                if !addable.isEmpty {
                    Button(action: add) { Text("Add \(addable.count)") }
                        .buttonStyle(CapsuleButtonStyle.patientAction())
                        .accessibilityLabel("Add \(addable.count) infusion\(addable.count == 1 ? "" : "s")")
                } else if !text.isEmpty {
                    Button { withAnimation(.snappy) { clear() } } label: {
                        Image(systemName: "xmark.circle.fill").font(PS.sys(size: 17)).foregroundStyle(PS.fg3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            if !suggestions.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(suggestions) { d in
                        // The drug and, small, the unit its rate is in (1.10: the unit fills in as you type).
                        Button { complete(d) } label: {
                            (Text(d.name) + Text((d.unit ?? d.units.first).map { "  " + $0 } ?? "").font(PS.sys(size: 10.5, weight: .regular)))
                        }
                        .font(PS.sys(size: 13, weight: .semibold))
                        .buttonStyle(CapsuleButtonStyle(prominent: false))
                        .accessibilityLabel(d.name + ((d.unit ?? d.units.first).map { ", " + $0 } ?? ""))
                    }
                }
            } else if let hint = InfusionEntry.unitHint(text) {
                Text(hint).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).padding(.horizontal, 2)
            }
            if !r.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(r.questions) { q in question(q) }
                    ForEach(r.items) { it in chip(it) }
                    ForEach(r.unknown, id: \.self) { u in
                        info(u + " · not in the list", icon: "questionmark.circle")
                    }
                }
                let notes = r.items.filter { !dropped.contains($0.id) && $0.note != nil }
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(notes) { it in
                            (Text(it.drug + ": ").font(PS.sys(size: 11.5, weight: .semibold)) + Text(it.note ?? "").font(PS.sys(size: 11.5)))
                                .foregroundStyle(PS.fg3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .onAppear(perform: seedForScreenshot)
    }

    // MARK: Chips

    private func chip(_ it: InfusionEntry.Item) -> some View {
        let status = InfusionEntry.status(it, in: patient.record[keyPath: list])
        let out = dropped.contains(it.id)
        let can = canAdd(it)
        let off = out || !can
        var note: String?
        switch status {
        case .recorded: note = "already recorded"
        case .replaces(let old): note = "replaces " + old
        default: note = nil
        }
        return Button {
            guard can else { return }
            Haptics.light()
            withAnimation(.snappy) { if out { dropped.remove(it.id) } else { dropped.insert(it.id) } }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(it.label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(off ? PS.fg3 : PS.fg)
                    .strikethrough(out, color: PS.fg3)
                if let note {
                    Text(note).font(PS.sys(size: 11.5, weight: .semibold)).foregroundStyle(can ? PS.action : PS.fg3)
                }
                if can {
                    Image(systemName: out ? "plus" : "xmark").font(PS.sys(size: 9, weight: .bold)).foregroundStyle(PS.fg3)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(off ? PS.surface2 : PS.accent2.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(off ? PS.line2 : PS.accent2.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(it.label + (note.map { ", " + $0 } ?? ""))
        .accessibilityValue(out ? "Left out" : (can ? "Will be added" : "Not added"))
        .accessibilityHint(can ? (out ? "Puts it back" : "Leaves it out") : "")
    }

    /// A drug or unit that could be more than one: a menu, as the quick-add bar's questions; nothing from its drip is
    /// added until it is answered.
    private func question(_ q: InfusionEntry.Question) -> some View {
        Menu {
            ForEach(q.options) { o in
                Button(o.text) { Haptics.light(); choices[q.id] = o.id }
            }
        } label: {
            HStack(spacing: 5) {
                Text(q.label).font(PS.mono(size: 12, weight: .bold)).foregroundStyle(PS.fg)
                Text(q.text + "?").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent2)
                Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 9, weight: .bold)).foregroundStyle(PS.accent2)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PS.accent2.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        }
        .accessibilityLabel(q.label + ", " + q.text + "? Not added until you choose")
    }

    private func info(_ s: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: icon).font(PS.sys(size: 10.5, weight: .semibold))
            Text(s).font(PS.sys(size: 12, weight: .medium))
        }
        .foregroundStyle(PS.fg3)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PS.line2, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    /// The typeahead: the last drip's drug words become the drug's name.
    private func complete(_ d: InfusionEntryDrug) {
        Haptics.light()
        var parts = InfusionEntry.pieces(text)
        if !parts.isEmpty { parts.removeLast() }
        parts.append(d.name.lowercased())
        text = parts.joined(separator: ", ") + " "
        focused = true
    }

    /// Files the chips shown and not left out, as one step in the store's Undo history.
    private func add() {
        let items = addable
        guard !items.isEmpty else { return Haptics.light() }
        patient.update(discrete: true) { InfusionEntry.apply(items, to: &$0[keyPath: list]) }
        Haptics.success()
        withAnimation(.snappy) { clear() }
    }

    private func clear() {
        text = ""
        choices = [:]
        dropped = []
    }

    /// Screenshot runs: -ps.infusion.type "<line>" types a line into the field.
    private func seedForScreenshot() {
        #if DEBUG
        let t = LaunchSeed.string("ps.infusion.type")
        if !t.isEmpty, text.isEmpty { text = t }
        #endif
    }
}
