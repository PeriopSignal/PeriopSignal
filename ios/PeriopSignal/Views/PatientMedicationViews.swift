import SwiftUI

// MARK: - Home medications, allergies and flagged medications (1.9, Ben's Wanted Changes)
//
// Three boxes' contents, for the Preprocedure tab's Current Medications and Demographics & History sections (each goes
// inside a PatientGroup; none draws its own card):
//   HomeMedicationsBox: a line read into chips as you type ("metoprolol 25 bid lisinopril, Eliquis 5 bid"), Add or Return
//     files them as one Undo step; the list with the dose editable in place and × to remove; the list typed before 1.9
//     above it with "Convert to list".
//   AllergiesBox: "No known allergies", or the list with + Add (the same kind of line: "PCN - rash, latex anaphylaxis"),
//     each allergy with Mild / Severe / Anaphylaxis and its reaction; the allergies typed before 1.9 with "Convert to list".
//   FlaggedMedicationsChips: PatientCatalog.medFlags as chips bound to the record's medFlags (as before).
// Read by MedicationCatalog and AllergyCatalog; nothing is filled in that was not typed or picked.

/// Home medications: type-ahead, chips, the list.
struct HomeMedicationsBox: View {
    @Environment(PatientStore.self) private var patient
    @State private var text = ""
    @State private var dropped: Set<Int> = []
    @FocusState private var focused: Bool

    static let placeholder = "Type medications, e.g. metoprolol 25 bid lisinopril"

    private var reading: [MedicationCatalog.ReadItem] { MedicationCatalog.reading(text) }

    private func canAdd(_ m: PatientMed) -> Bool {
        if case .recorded = MedicationCatalog.status(m, in: patient.record.homeMeds) { return false }
        return true
    }

    private func addable(_ items: [MedicationCatalog.ReadItem]) -> [PatientMed] {
        items.enumerated().filter { !dropped.contains($0.offset) && canAdd($0.element.med) }.map(\.element.med)
    }

    var body: some View {
        let r = patient.record
        let items = reading
        let add = addable(items)
        VStack(alignment: .leading, spacing: 0) {
            let legacy = r.medications.trimmingCharacters(in: .whitespacesAndNewlines)
            if !legacy.isEmpty {
                LegacyListRow(title: "Medications as typed", text: legacy, canConvert: !MedicationCatalog.parse(legacy).isEmpty, action: convert)
                Hairline().padding(.leading, 14)
            }
            VStack(alignment: .leading, spacing: 8) {
                LineFieldRow(placeholder: Self.placeholder, label: "Type medications", text: $text, focused: $focused,
                             addCount: add.count, noun: ("medication", "medications"), onAdd: { file(add) }, onClear: clear)
                let suggestions = MedicationCatalog.typeahead(text)
                if !suggestions.isEmpty {
                    SuggestionChips(items: suggestions.map { s in
                        SuggestionItem(id: s.hit.entry.id, title: s.hit.entry.name, detail: s.hit.matched.map(FreeText.cap))
                    }) { id in
                        guard let s = suggestions.first(where: { $0.hit.entry.id == id }) else { return }
                        Haptics.light()
                        text = s.completing(text)
                        focused = true
                    }
                }
                if !items.isEmpty {
                    WrapLayout(spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { n, it in
                            let status = MedicationCatalog.status(it.med, in: r.homeMeds)
                            LineChip(label: it.med.text, note: note(status, typed: it.typed), out: dropped.contains(n), can: canAdd(it.med), typed: it.typed) {
                                withAnimation(.snappy) { if dropped.contains(n) { dropped.remove(n) } else { dropped.insert(n) } }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            ForEach(r.homeMeds) { m in
                Hairline().padding(.leading, 14)
                HomeMedRow(med: m, dose: doseBinding(m.id)) {
                    Haptics.light()
                    withAnimation(.snappy) { patient.update(discrete: true) { $0.homeMeds.removeAll { $0.id == m.id } } }
                }
            }
        }
        .onChange(of: text) { _, _ in if !dropped.isEmpty { dropped = dropped.filter { $0 < reading.count } } }
        .onAppear(perform: seedForScreenshot)
    }

    private func note(_ s: PatientNoteStatus, typed: Bool) -> String? {
        switch s {
        case .recorded: return "already listed"
        case .replaces(let old): return "dose was " + old
        default: return typed ? "not in the list" : nil
        }
    }

    private func doseBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { patient.record.homeMeds.first { $0.id == id }?.dose ?? "" },
                set: { v in patient.update { r in if let i = r.homeMeds.firstIndex(where: { $0.id == id }) { r.homeMeds[i].dose = v } } })
    }

    /// Files the chips shown and not left out, as one step in the store's Undo history.
    private func file(_ items: [PatientMed]) {
        guard !items.isEmpty else { return Haptics.light() }
        patient.update(discrete: true) { MedicationCatalog.apply(items, to: &$0.homeMeds) }
        Haptics.success()
        withAnimation(.snappy) { clear() }
    }

    /// The list typed before 1.9 read into items, and the typed text cleared: one Undo step.
    private func convert() {
        Haptics.success()
        withAnimation(.snappy) {
            patient.update(discrete: true) { r in
                MedicationCatalog.apply(MedicationCatalog.parse(r.medications), to: &r.homeMeds)
                r.medications = ""
            }
        }
    }

    private func clear() {
        text = ""
        dropped = []
    }

    /// Screenshot runs: -ps.meds.type "<line>" types a line into the field.
    private func seedForScreenshot() {
        #if DEBUG
        let t = LaunchSeed.string("ps.meds.type")
        if !t.isEmpty, text.isEmpty { text = t }
        #endif
    }
}

/// The medication rows' short flag words (1.11, P1-10: one-line rows), by flag id; the full label is read by VoiceOver
/// and shown in the row's context menu. A flag without a short word keeps its label.
enum HomeMedRowStyle {
    static let shortFlags: [String: String] = [
        "anticoagulant": "Anticoag", "p2y12": "P2Y12", "glp1": "GLP-1", "sglt2": "SGLT2", "betablocker": "β-blocker",
        "acei": "ACEi/ARB", "steroid": "Steroid", "opioid": "Opioid", "maoi": "MAOI",
    ]
    static func shortFlag(_ f: PatientFlag) -> String { shortFlags[f.id] ?? f.label }
    /// The dose field's width: narrower than 1.9's 128 pt so the name and a flag pill share the line. The pill keeps its
    /// words and the dose its field, and the name is never shrunk or truncated (the formulation, succinate or tartrate,
    /// is part of it): a name too long for one line beside them puts its pill under itself (HomeMedRow).
    static let doseWidth: CGFloat = 104
    /// The dose's text size: a little under the row's, so "7.5 mg weekly" fits the field.
    static let doseFontSize: CGFloat = 13.5
}

/// One medication on the list, on one line (1.11, P1-10): its name, its flag pill, the dose typed in place, ×. The class
/// is in the row's detail: a long press shows it, and VoiceOver reads it. The name keeps every letter: when it is too long
/// to share the line with its pill, the dose field and × (375 pt: "Metoprolol succinate" with "β-blocker"), the pill
/// goes under the name and the dose field and × stay in their column, so the row is as tall as its name needs.
private struct HomeMedRow: View {
    var med: PatientMed
    @Binding var dose: String
    var onRemove: () -> Void

    var body: some View {
        let entry = MedicationCatalog.resolve(med)
        let flags = PatientCatalog.medFlags.filter { entry?.flags.contains($0.id) == true }
        let drugClass = entry?.drugClass ?? "Typed, not in the list"
        ViewThatFits(in: .horizontal) {
            // One line: the name whole, its pill, the dose, ×.
            HStack(alignment: .center, spacing: 8) {
                name.lineLimit(1).fixedSize()
                pill(flags)
                Spacer(minLength: 0)
                doseField
                removeButton
            }
            // The name over its pill, the dose and × beside both.
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    name.fixedSize(horizontal: false, vertical: true)
                    pill(flags)
                }
                Spacer(minLength: 0)
                doseField
                removeButton
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contextMenu {
            Text(drugClass)
            if !flags.isEmpty { Text(flags.map(\.label).joined(separator: ", ")) }
            Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(FreeText.cap(med.name) + ", " + drugClass)
    }

    private var name: some View {
        Text(FreeText.cap(med.name)).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
    }

    @ViewBuilder private func pill(_ flags: [PatientFlag]) -> some View {
        if let f = flags.first {
            Text(HomeMedRowStyle.shortFlag(f) + (flags.count > 1 ? " +\(flags.count - 1)" : ""))
                .font(PS.sys(size: 10.5, weight: .semibold)).foregroundStyle(PS.action)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(PS.action.opacity(0.12), in: Capsule())
                .accessibilityLabel(flags.map(\.label).joined(separator: ", "))
        }
    }

    private var doseField: some View {
        TextField("Dose", text: $dose)
            .font(PS.sys(size: HomeMedRowStyle.doseFontSize)).foregroundStyle(PS.fg)
            .multilineTextAlignment(.trailing)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(width: HomeMedRowStyle.doseWidth)
            .accessibilityLabel("Dose of " + med.name)
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.fg3)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove " + med.name)
    }
}

// MARK: - Allergies

/// Allergies: No known allergies, with the type line always there (1.11, P1-7: no [+ Add] capsule, so the first allergy is
/// one tap and typing), then the list.
struct AllergiesBox: View {
    @Environment(PatientStore.self) private var patient
    @State private var text = ""
    @State private var dropped: Set<Int> = []
    @FocusState private var focused: Bool

    static let placeholder = "e.g. PCN - rash, latex anaphylaxis"

    private var reading: [AllergyCatalog.ReadItem] { AllergyCatalog.reading(text) }

    private func canAdd(_ a: PatientAllergy) -> Bool {
        if case .recorded = AllergyCatalog.status(a, in: patient.record.allergyList) { return false }
        return true
    }

    private func addable(_ items: [AllergyCatalog.ReadItem]) -> [PatientAllergy] {
        items.enumerated().filter { !dropped.contains($0.offset) && canAdd($0.element.allergy) }.map(\.element.allergy)
    }

    var body: some View {
        let r = patient.record
        let legacy = r.allergies.trimmingCharacters(in: .whitespacesAndNewlines)
        let empty = r.allergyList.isEmpty && legacy.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            if !legacy.isEmpty {
                LegacyListRow(title: "Allergies as typed", text: legacy, canConvert: !AllergyCatalog.parse(legacy).isEmpty, action: convert)
                Hairline().padding(.leading, 14)
            }
            if empty || r.nkda {
                HStack(spacing: 8) {
                    PatientChips(options: [PatientFlag("nkda", "No known allergies")],
                                 selection: Binding(get: { patient.record.nkda ? ["nkda"] : [] },
                                                    set: { v in patient.update { $0.nkda = v.contains("nkda") } }),
                                 tint: PS.action)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                Hairline().padding(.leading, 14)
            }
            // The type line is always there (an allergy typed takes No known allergies off).
            field(r)
            ForEach(r.allergyList) { a in
                Hairline().padding(.leading, 14)
                AllergyRow(allergy: a, severity: severityBinding(a.id), reaction: reactionBinding(a.id)) {
                    Haptics.light()
                    withAnimation(.snappy) { patient.update(discrete: true) { $0.allergyList.removeAll { $0.id == a.id } } }
                }
            }
        }
        .onChange(of: text) { _, _ in if !dropped.isEmpty { dropped = dropped.filter { $0 < reading.count } } }
        .onAppear(perform: seedForScreenshot)
    }

    private func field(_ r: PatientRecord) -> some View {
        let items = reading
        let add = addable(items)
        let none = AllergyCatalog.isNone(text)
        return VStack(alignment: .leading, spacing: 8) {
            LineFieldRow(placeholder: Self.placeholder, label: "Add allergies", text: $text, focused: $focused,
                         addCount: none ? 1 : add.count, noun: ("allergy", "allergies"), addTitle: none ? "No known allergies" : nil,
                         onAdd: { none ? fileNone() : file(add) }, onClear: clear)
            let suggestions = AllergyCatalog.typeahead(text)
            if !suggestions.isEmpty {
                SuggestionChips(items: suggestions.map { s in SuggestionItem(id: s.hit.entry.id, title: s.hit.entry.name, detail: s.hit.matched.map(FreeText.cap)) }) { id in
                    guard let s = suggestions.first(where: { $0.hit.entry.id == id }) else { return }
                    Haptics.light()
                    text = s.completing(text)
                    focused = true
                }
            }
            if !items.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { n, it in
                        LineChip(label: it.allergy.text, note: note(AllergyCatalog.status(it.allergy, in: r.allergyList), typed: it.typed), out: dropped.contains(n), can: canAdd(it.allergy), typed: it.typed,
                                 alert: it.allergy.severity == "anaphylaxis") {
                            withAnimation(.snappy) { if dropped.contains(n) { dropped.remove(n) } else { dropped.insert(n) } }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func note(_ s: PatientNoteStatus, typed: Bool) -> String? {
        switch s {
        case .recorded: return "already listed"
        case .replaces(let old): return "was " + old
        default: return typed ? "not in the list" : nil
        }
    }

    private func severityBinding(_ id: UUID) -> Binding<String?> {
        Binding(get: { patient.record.allergyList.first { $0.id == id }?.severity },
                set: { v in patient.update { r in if let i = r.allergyList.firstIndex(where: { $0.id == id }) { r.allergyList[i].severity = v } } })
    }

    private func reactionBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { patient.record.allergyList.first { $0.id == id }?.reaction ?? "" },
                set: { v in patient.update { r in if let i = r.allergyList.firstIndex(where: { $0.id == id }) { r.allergyList[i].reaction = v } } })
    }

    /// Files the chips as one Undo step; an allergy added clears No known allergies.
    private func file(_ items: [PatientAllergy]) {
        guard !items.isEmpty else { return Haptics.light() }
        patient.update(discrete: true) { r in
            AllergyCatalog.apply(items, to: &r.allergyList)
            r.nkda = false
        }
        Haptics.success()
        withAnimation(.snappy) { clear() }
    }

    /// "NKDA" typed: No known allergies, when nothing is listed.
    private func fileNone() {
        guard patient.record.allergyList.isEmpty else { return Haptics.light() }
        patient.update(discrete: true) { $0.nkda = true }
        Haptics.success()
        withAnimation(.snappy) { clear() }
    }

    private func convert() {
        Haptics.success()
        withAnimation(.snappy) {
            patient.update(discrete: true) { r in
                AllergyCatalog.apply(AllergyCatalog.parse(r.allergies), to: &r.allergyList)
                r.allergies = ""
                if !r.allergyList.isEmpty { r.nkda = false }
            }
        }
    }

    private func clear() {
        text = ""
        dropped = []
    }

    /// Screenshot runs: -ps.allergy.type "<line>" types a line into the field.
    private func seedForScreenshot() {
        #if DEBUG
        let t = LaunchSeed.string("ps.allergy.type")
        if !t.isEmpty, text.isEmpty { text = t }
        #endif
    }
}

/// One allergy: its name (red for anaphylaxis), the severity chips, the reaction typed in place, ×.
private struct AllergyRow: View {
    var allergy: PatientAllergy
    @Binding var severity: String?
    @Binding var reaction: String
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(FreeText.cap(allergy.name))
                    .font(PS.sys(size: 14.5, weight: .semibold))
                    .foregroundStyle(severity == "anaphylaxis" ? PS.red : PS.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.fg3)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove " + allergy.name)
            }
            PatientChoice(options: PatientAllergy.severities, selection: $severity)
            TextField("Reaction, e.g. hives", text: $reaction)
                .font(PS.sys(size: 14)).foregroundStyle(PS.fg)
                .autocorrectionDisabled()
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Reaction to " + allergy.name)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contextMenu { Button("Remove", systemImage: "trash", role: .destructive, action: onRemove) }
    }
}

// MARK: - Flagged medications

/// The medication flags as chips (as before 1.9), bound to the record's medFlags. Each tap is its own Undo step. Toggles
/// in the action tint (1.11, P1-8), the same as the active flags' chips they open beside (PreopFlaggedBox).
struct FlaggedMedicationsChips: View {
    @Environment(PatientStore.self) private var patient

    var body: some View {
        PatientChipRow(label: nil) {
            PatientChips(options: PatientCatalog.medFlags,
                         selection: Binding(get: { patient.record.medFlags }, set: { v in patient.update { $0.medFlags = v } }),
                         tint: PS.action)
        }
    }
}

// MARK: - Pieces the boxes share

/// The line being typed, with Add N (or the clear button) beside it.
private struct LineFieldRow: View {
    var placeholder: String
    var label: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var addCount: Int
    /// "allergy", "allergies".
    var noun: (one: String, many: String)
    var addTitle: String? = nil
    var onAdd: () -> Void
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.badge.plus")
                .font(PS.sys(size: 15, weight: .semibold))
                .foregroundStyle(PS.accent2)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .focused(focused)
                .font(PS.sys(size: 15)).foregroundStyle(PS.fg)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(onAdd)
                .accessibilityLabel(label)
            if addCount > 0 {
                Button(action: onAdd) { Text(addTitle ?? "Add \(addCount)") }
                    .buttonStyle(CapsuleButtonStyle())
                    .accessibilityLabel(addTitle ?? "Add \(addCount) " + (addCount == 1 ? noun.one : noun.many))
            } else if !text.isEmpty {
                Button { withAnimation(.snappy) { onClear() } } label: {
                    Image(systemName: "xmark.circle.fill").font(PS.sys(size: 17)).foregroundStyle(PS.fg3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
    }
}

/// A name the type-ahead offers, with the brand or abbreviation that found it.
private struct SuggestionItem: Identifiable {
    var id: String
    var title: String
    var detail: String?
}

/// The type-ahead: names to complete the words being typed.
private struct SuggestionChips: View {
    var items: [SuggestionItem]
    var pick: (String) -> Void

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(items) { s in
                Button { pick(s.id) } label: {
                    HStack(spacing: 4) {
                        Text(s.title).font(PS.sys(size: 13, weight: .semibold))
                        if let d = s.detail { Text(d).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3) }
                    }
                }
                .buttonStyle(CapsuleButtonStyle(prominent: false))
                .accessibilityLabel(s.title + (s.detail.map { ", " + $0 } ?? ""))
            }
        }
    }
}

/// One item read from the line: tap to leave it out or put it back.
private struct LineChip: View {
    var label: String
    var note: String?
    var out: Bool
    var can: Bool
    var typed: Bool
    var alert = false
    var toggle: () -> Void

    var body: some View {
        let off = out || !can
        Button {
            guard can else { return }
            Haptics.light()
            toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(label).font(PS.sys(size: 13, weight: .semibold))
                    .foregroundStyle(off ? PS.fg3 : (alert ? PS.red : PS.fg))
                    .strikethrough(out, color: PS.fg3)
                if let note {
                    Text(note).font(PS.sys(size: 11.5, weight: .semibold)).foregroundStyle(can && !typed ? PS.action : PS.fg3)
                }
                if can {
                    Image(systemName: out ? "plus" : "xmark").font(PS.sys(size: 9, weight: .bold)).foregroundStyle(PS.fg3)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(off ? PS.surface2 : PS.accent2.opacity(typed ? 0.07 : 0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(off ? PS.line2 : PS.accent2.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: typed ? [3, 2] : [])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label + (note.map { ", " + $0 } ?? ""))
        .accessibilityValue(out ? "Left out" : (can ? "Will be added" : "Not added"))
        .accessibilityHint(can ? (out ? "Puts it back" : "Leaves it out") : "")
    }
}

/// The list as typed before 1.9, shown as it is, with Convert to list (one Undo step).
private struct LegacyListRow: View {
    var title: String
    var text: String
    var canConvert: Bool
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg3)
            Text(FreeText.capItems(text)).font(PS.sys(size: 14.5)).foregroundStyle(PS.fg)
                .fixedSize(horizontal: false, vertical: true)
            if canConvert {
                Button(action: action) { Label("Convert to list", systemImage: "list.bullet") }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
