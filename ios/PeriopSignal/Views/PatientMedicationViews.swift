import SwiftUI

// MARK: - Home medications, allergies and flagged medications (1.9, Ben's Wanted Changes)
//
// Three boxes' contents, for the Preprocedure tab's Current Medications and Demographics & History sections (each goes
// inside a PatientGroup; none draws its own card):
//   CurrentMedicationsBox: a line read into chips as you type ("metoprolol 25 bid lisinopril, Eliquis 5 bid, norepi 0.05"),
//     Add or Return files them as one Undo step; the infusions first with their rates, then the medications (antibiotics,
//     cardiovascular, the rest) with the dose editable in place and × to remove; the list typed before 1.9 above it with
//     "Convert to list". (1.12: it took over the separate Current infusions box.)
//   AllergiesBox: "No known allergies", or the list with + Add (the same kind of line: "PCN - rash, latex anaphylaxis"),
//     each allergy with Mild / Severe / Anaphylaxis and its reaction; the allergies typed before 1.9 with "Convert to list".
//   FlaggedMedicationsChips: PatientCatalog.medFlags as chips bound to the record's medFlags (as before).
// Read by MedicationCatalog and AllergyCatalog; nothing is filled in that was not typed or picked.

/// Current medications and infusions in one box (1.12, Ben's note 16): one type line that takes both ("metoprolol 25 bid,
/// norepi 0.05, heparin 1200 units/h"), the chips for what it read, and the list. A piece the drip reader reads as an infusion
/// (a known drip with a rate, or a drip-only drug: InfusionEntry.isInfusion) goes to the infusions; anything else is a
/// medication, as before. The list is the infusions first (each with its rate field), then the antibiotics, the cardiovascular
/// medications and the rest (MedicationCatalog.ordered), each group in the order entered. Storage is unchanged: `homeMeds` and
/// `homeInfusions`, so a saved record opens as it was.
struct CurrentMedicationsBox: View {
    @Environment(PatientStore.self) private var patient
    @State private var text = ""
    @State private var dropped: Set<Int> = []
    @State private var droppedDrips: Set<String> = []
    @State private var choices: [String: String] = [:]
    @State private var wobbling = false
    @FocusState private var focused: Bool

    static let placeholder = "e.g. metoprolol 25 bid, norepi 0.05"
    /// The box's name, on the Preoperative tab's section title and the Medications & Allergies page.
    static let title = "Current Medications & Infusions"
    static let note = "Medications and drips running before the case. The infusions are listed first, with their rates, then the antibiotics, the cardiovascular medications and the rest, each in the order entered. The drips appear in the intraoperative infusions list tagged \"from preop\"."

    private var mixed: InfusionEntry.MixedLine { InfusionEntry.mixed(text) }

    /// The piece being typed is a medication: the catalog's reading then leaves it out while its name is unfinished (the
    /// type-ahead speaks for it); once a drip follows it, it is finished.
    private var typingMedication: Bool {
        guard let last = InfusionEntry.pieces(text).last else { return true }
        return !InfusionEntry.isInfusion(last)
    }

    private var reading: [MedicationCatalog.ReadItem] {
        typingMedication ? MedicationCatalog.reading(mixed.medications) : MedicationCatalog.read(mixed.medications)
    }

    private var dripReading: InfusionEntry.Reading { InfusionEntry.read(mixed.infusions, choices: choices) }

    private func canAdd(_ m: PatientMed) -> Bool {
        if case .recorded = MedicationCatalog.status(m, in: patient.record.homeMeds) { return false }
        return true
    }

    private func addable(_ items: [MedicationCatalog.ReadItem]) -> [PatientMed] {
        items.enumerated().filter { !dropped.contains($0.offset) && canAdd($0.element.med) }.map(\.element.med)
    }

    private func canAddDrip(_ it: InfusionEntry.Item) -> Bool {
        if case .recorded = InfusionEntry.status(it, in: patient.record.homeInfusions) { return false }
        return true
    }

    private func addableDrips(_ r: InfusionEntry.Reading) -> [InfusionEntry.Item] {
        r.items.filter { !droppedDrips.contains($0.id) && canAddDrip($0) }
    }

    var body: some View {
        let r = patient.record
        let items = reading
        let drips = dripReading
        let add = addable(items)
        let addDrips = addableDrips(drips)
        VStack(alignment: .leading, spacing: 0) {
            let legacy = r.medications.trimmingCharacters(in: .whitespacesAndNewlines)
            if !legacy.isEmpty {
                LegacyListRow(title: "Medications as typed", text: legacy, canConvert: !MedicationCatalog.parse(legacy).isEmpty, action: convert)
                Hairline().padding(.leading, 14)
            }
            VStack(alignment: .leading, spacing: 8) {
                LineFieldRow(placeholder: Self.placeholder, label: "Type medications and infusions", text: $text, focused: $focused,
                             addCount: add.count + addDrips.count, noun: ("item", "items"), onAdd: { file(add, addDrips) }, onClear: clear)
                suggestions
                if !items.isEmpty || !drips.isEmpty {
                    WrapLayout(spacing: 6) {
                        ForEach(drips.questions) { q in InfusionQuestionChip(question: q) { choices[q.id] = $0 } }
                        ForEach(drips.items) { it in
                            InfusionChipView(item: it, status: InfusionEntry.status(it, in: r.homeInfusions), out: droppedDrips.contains(it.id)) {
                                if droppedDrips.contains(it.id) { droppedDrips.remove(it.id) } else { droppedDrips.insert(it.id) }
                            }
                        }
                        ForEach(drips.unknown, id: \.self) { u in
                            InfusionInfoChip(text: u + " · not in the list", icon: "questionmark.circle")
                        }
                        ForEach(Array(items.enumerated()), id: \.offset) { n, it in
                            let status = MedicationCatalog.status(it.med, in: r.homeMeds)
                            LineChip(label: it.med.text, note: note(status, typed: it.typed), out: dropped.contains(n), can: canAdd(it.med), typed: it.typed) {
                                withAnimation(.snappy) { if dropped.contains(n) { dropped.remove(n) } else { dropped.insert(n) } }
                            }
                        }
                    }
                    let notes = drips.items.filter { !droppedDrips.contains($0.id) && $0.note != nil }
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
            // The infusions first, each with its rate field; long-press wobbles the list to delete.
            ForEach(r.homeInfusions) { inf in
                Hairline().padding(.leading, 14)
                InfusionRow(infusion: infusionBinding(inf.id)) { patient.update(discrete: true) { $0.homeInfusions.removeAll { $0.id == inf.id } } }
                    .wobbleDelete($wobbling, label: inf.drug.isEmpty ? "infusion" : inf.drug) { patient.update(discrete: true) { $0.homeInfusions.removeAll { $0.id == inf.id } } }
            }
            // Then the medications: antibiotics, cardiovascular, the rest.
            ForEach(MedicationCatalog.ordered(r.homeMeds)) { m in
                Hairline().padding(.leading, 14)
                HomeMedRow(med: m, dose: doseBinding(m.id)) {
                    Haptics.light()
                    withAnimation(.snappy) { patient.update(discrete: true) { $0.homeMeds.removeAll { $0.id == m.id } } }
                }
            }
            WobbleDoneBar(editing: $wobbling)
        }
        .onChange(of: text) { _, _ in
            if !dropped.isEmpty { dropped = dropped.filter { $0 < reading.count } }
            if !droppedDrips.isEmpty { let ids = Set(dripReading.items.map(\.id)); droppedDrips = droppedDrips.filter { ids.contains($0) } }
        }
        .onAppear(perform: seedForScreenshot)
    }

    /// The names the line offers to finish the piece being typed: the medications from the list, the drips (with the unit their
    /// rate is in) from the drip list; a drug both lists know is offered once, as a medication.
    @ViewBuilder private var suggestions: some View {
        let meds = MedicationCatalog.typeahead(text)
        let medNames = Set(meds.map { InfusionEntry.fold($0.hit.entry.name) })
        let drips = InfusionEntry.suggestions(text).filter { !medNames.contains(InfusionEntry.fold($0.name)) }
        if !meds.isEmpty || !drips.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !drips.isEmpty {
                    InfusionSuggestionChips(drugs: drips) { completeDrip($0) }
                }
                if !meds.isEmpty {
                    SuggestionChips(items: meds.map { s in
                        SuggestionItem(id: s.hit.entry.id, title: s.hit.entry.name, detail: s.hit.matched.map(FreeText.cap))
                    }) { id in
                        guard let s = meds.first(where: { $0.hit.entry.id == id }) else { return }
                        Haptics.light()
                        text = s.completing(text)
                        focused = true
                    }
                }
            }
        } else if let hint = InfusionEntry.unitHint(text) {
            Text(hint).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).padding(.horizontal, 2)
        }
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

    private func infusionBinding(_ id: UUID) -> Binding<PatientInfusion> {
        Binding(get: { patient.record.homeInfusions.first { $0.id == id } ?? PatientInfusion() },
                set: { v in patient.update { r in if let i = r.homeInfusions.firstIndex(where: { $0.id == id }) { r.homeInfusions[i] = v } } })
    }

    /// The typeahead for a drip: the last piece's drug words become the drug's name.
    private func completeDrip(_ d: InfusionEntryDrug) {
        Haptics.light()
        var parts = InfusionEntry.pieces(text)
        if !parts.isEmpty { parts.removeLast() }
        parts.append(d.name.lowercased())
        text = parts.joined(separator: ", ") + " "
        focused = true
    }

    /// Files the chips shown and not left out, medications and infusions, as one step in the store's Undo history.
    private func file(_ meds: [PatientMed], _ drips: [InfusionEntry.Item]) {
        guard !meds.isEmpty || !drips.isEmpty else { return Haptics.light() }
        patient.update(discrete: true) { r in
            MedicationCatalog.apply(meds, to: &r.homeMeds)
            InfusionEntry.apply(drips, to: &r.homeInfusions)
        }
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
        droppedDrips = []
        choices = [:]
    }

    /// Screenshot runs: -ps.meds.type "<line>" (or -ps.infusion.type) types a line into the field.
    private func seedForScreenshot() {
        #if DEBUG
        var t = LaunchSeed.string("ps.meds.type")
        if t.isEmpty { t = LaunchSeed.string("ps.infusion.type") }
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
                    .buttonStyle(CapsuleButtonStyle.patientAction())
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

// MARK: - The Medications & Interventions page (1.12, Ben's notes 3 and 18)

/// The Intraoperative tab's "Antibiotics & Notable Medications" page. At the top, read-only, the antibiotics charted in Case
/// Timers for the open case with their times ("Cefazolin 2 g · last 08:12 · next due 12:12"; an overdue redose in red);
/// then the notable medications as chips, each with an optional dose typed beside it once chosen; then the free text the
/// page had before 1.12 (antibiotic and time for a case that does not use Case Timers, steroids, reversal, positioning),
/// which both show side by side, never merged.
struct IntraopMedicationsPage: View {
    @Environment(PatientStore.self) private var patient
    @Environment(ReferenceStore.self) private var refs
    /// Opens Case Timers at a card (its scroll id: the antibiotic card, the Heparin & ACT section). The editor pages push it as a page
    /// of My Patient's stack (the sheet is presented from the tab under them); without one the sheet opens.
    var openCaseTimers: ((String) -> Void)? = nil
    /// Opens a reference route by its key ("quickref:ashp-surgical-prophylaxis") as a page of My Patient's stack. Without one the
    /// "Which antibiotic?" link is left out: this host cannot push a reference page.
    var openRoute: ((String) -> Void)? = nil

    @State private var abxOpen = LaunchSeed.bool("ps.meds.abx")
    @State private var hepOpen = LaunchSeed.bool("ps.meds.hep")

    static let notableTitle = "Notable medications"
    static let notableNote = "Choose a medication to record it; a dose is printed only if you type one, and none is suggested. A milrinone bolus or inhaled milrinone is not an infusion: type a drip under Infusions."
    static let otherLabel = "Other medications & interventions"
    static let otherPrompt = "Antibiotic and time, steroids, reversal, positioning"
    static let antibioticsTitle = "Antibiotics"
    static let antibioticsNote = "Record a dose here, or type it in the bar: \(IntraopAntibiotic.barExample). No timer runs unless you turn the redose reminder on; an antibiotic started in Case Timers shows here too, with its next redose."

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TimelineView(.everyMinute) { ctx in antibiotics(now: ctx.date) }
            TimelineView(.everyMinute) { ctx in heparin(now: ctx.date) }
            notable
            PatientGroup(title: nil) {
                PatientTextField(label: Self.otherLabel, prompt: Self.otherPrompt,
                                 text: Binding(get: { PatientNotableMeds.pageState(patient.record).text },
                                               set: { v in patient.update { r in PatientNotableMeds.migrateLegacy(&r); r.medsGiven = v } }))
            }
        }
    }

    // MARK: Case Timers' antibiotics, read-only

    @ViewBuilder private func antibiotics(now: Date) -> some View {
        let lines = CaseAntibiotics.lines(patient.record, data: refs.caseTimers ?? CaseAntibiotics.current, now: now)
        let shown = DraftGate.shows("caseTimers")
        // 1.12 follow-up: the group is always here while Case Timers is, so an empty one says how to add (a link that opens
        // Case Timers at its antibiotic card, or the bar); with Case Timers hidden it stays hidden while empty, as before.
        if IntraopAntibiotic.pageShowsGroup(hasAntibiotics: !lines.isEmpty, caseTimersShown: shown) {
            PatientGroup(title: Self.antibioticsTitle, note: Self.antibioticsNote) {
                if lines.isEmpty {
                    Text(IntraopAntibiotic.noneCharted)
                        .font(PS.sys(size: 14.5)).foregroundStyle(PS.fg3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
                ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                    Text(l.tabText)
                        .font(PS.sys(size: 14.5, weight: l.overdue ? .semibold : .regular))
                        .foregroundStyle(l.overdue ? PS.red : PS.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .accessibilityLabel(l.tabText + (l.overdue ? ", redose overdue" : ""))
                    if i < lines.count - 1 { Hairline().padding(.leading, 14) }
                }
                if let link = IntraopAntibiotic.pageLink(hasAntibiotics: !lines.isEmpty, caseTimersShown: shown) {
                    Hairline().padding(.leading, 14)
                    quietLink(link, open: abxOpen, hint: "Opens the entry here") { withAnimation(.snappy) { abxOpen.toggle() } }
                        .accessibilityLabel(lines.isEmpty ? "Add an antibiotic" : "Add an antibiotic or a redose")
                    if abxOpen {
                        AbxEntryRow(onDone: { withAnimation(.snappy) { abxOpen = false } })
                            .padding(.horizontal, 14).padding(.bottom, 10)
                    }
                }
                // The card of recommended agents by surgery (Reference), where this host can push a reference page.
                if let openRoute {
                    Hairline().padding(.leading, 14)
                    Button {
                        Haptics.light()
                        openRoute("quickref:" + IntraopAntibiotic.referenceID)
                    } label: {
                        ReferenceLinkLabel(title: IntraopAntibiotic.referenceLink).padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the surgical prophylaxis reference")
                }
                if shown {
                    Hairline().padding(.leading, 14)
                    quietLink(IntraopAntibiotic.openCaseTimersLink, open: nil, hint: "Opens Case Timers at the antibiotic card") {
                        Haptics.light()
                        if let openCaseTimers { openCaseTimers(CaseTimersView.antibioticCardID) } else { CaseTimersUI.shared.openAntibiotic() }
                    }
                }
            }
        }
    }

    /// A quiet action link in a group: the words in the action colour (a "+ Name" link says Open to VoiceOver while its entry is open).
    private func quietLink(_ title: String, open: Bool?, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.action)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(open == true ? "Open" : "")
        .accessibilityHint(hint)
    }

    // MARK: Heparin, from Case Timers' one Heparin & ACT log

    @ViewBuilder private func heparin(now: Date) -> some View {
        let text = CaseHeparin.text(patient.record, now: now)
        let shown = DraftGate.shows("caseTimers")
        if text != nil || shown {
            PatientGroup(title: IntraopHeparin.groupTitle, note: IntraopHeparin.groupNote) {
                Text(text ?? IntraopAntibiotic.noneCharted)
                    .font(PS.sys(size: 14.5)).foregroundStyle(text == nil ? PS.fg3 : PS.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                if shown, refs.caseTimers != nil {
                    Hairline().padding(.leading, 14)
                    quietLink(IntraopHeparin.addLink, open: hepOpen, hint: "Opens the entry here") { withAnimation(.snappy) { hepOpen.toggle() } }
                        .accessibilityLabel("Add a heparin dose")
                    if hepOpen {
                        HeparinEntryRow(onDone: { withAnimation(.snappy) { hepOpen = false } })
                            .padding(.horizontal, 14).padding(.bottom, 10)
                    }
                    Hairline().padding(.leading, 14)
                    quietLink(IntraopHeparin.openLink, open: nil, hint: "Opens Case Timers at Heparin & ACT") {
                        Haptics.light()
                        if let openCaseTimers { openCaseTimers(CaseTimersView.heparinCardID) } else { CaseTimersUI.shared.openHeparin() }
                    }
                }
            }
        }
    }

    // MARK: The chips and their doses

    /// The chips as the page shows them: the record's, and a TXA typed in the free text before 1.12 as the TXA chip.
    private var shown: PatientNotableMeds {
        var m = PatientNotableMeds()
        m.entries = PatientNotableMeds.pageState(patient.record).entries
        return m
    }

    private var notable: some View {
        let m = shown
        return PatientGroup(title: Self.notableTitle, note: Self.notableNote) {
            VStack(alignment: .leading, spacing: 0) {
                ChipSet(options: PatientNotableMeds.options.map { ChipChoice($0.id, $0.label) }, style: .toggle, tint: PS.action,
                        hints: Dictionary(PatientNotableMeds.options.filter { $0.full != $0.label }.map { ($0.id, $0.full) }, uniquingKeysWith: { a, _ in a }),
                        isOn: { m.has($0) },
                        tap: { id in withAnimation(.snappy) { patient.update(discrete: true) { r in PatientNotableMeds.migrateLegacy(&r); r.notableMeds.toggle(id) } } })
                    .padding(14)
                ForEach(m.ordered) { e in
                    Hairline().padding(.leading, 14)
                    doseRow(e)
                }
            }
        }
    }

    private func doseRow(_ e: PatientNotableMeds.Entry) -> some View {
        let name = PatientNotableMeds.option(e.id)?.label ?? e.id
        let full = PatientNotableMeds.option(e.id)?.full ?? name
        return HStack(spacing: 10) {
            Text(name).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            TextField("Dose (optional)", text: Binding(
                get: { PatientNotableMeds.pageState(patient.record).entries.first { $0.id == e.id }?.dose ?? "" },
                set: { v in patient.update { r in PatientNotableMeds.migrateLegacy(&r); r.notableMeds.setDose(e.id, v) } }))
                .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(width: 170)
                .accessibilityLabel("Dose of " + full)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}
