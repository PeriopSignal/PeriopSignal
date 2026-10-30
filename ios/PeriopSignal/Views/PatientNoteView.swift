import SwiftUI

/// "No patient identifiers": at the top of My Patient and of Fill from a note.
struct NoIdentifiersBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(PS.sys(size: 16, weight: .semibold))
                .foregroundStyle(PS.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("No patient identifiers")
                    .font(PS.sys(size: 14, weight: .bold))
                    .foregroundStyle(PS.fg)
                Text("Don't enter names, record numbers, dates of birth or other identifiers.")
                    .font(PS.sys(size: 12.5))
                    .foregroundStyle(PS.fg2)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PS.accent.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Fill from a note: type or dictate the history and assessment, check what was read, then add it to My Patient.
/// The note is read on this phone by fixed rules (PatientNote) and is not kept; only what is added is saved.
struct PatientNoteSheet: View {
    @Environment(PatientStore.self) private var patient
    @Environment(\.dismiss) private var dismiss
    /// After adding: how many items, and the record as it was (for Undo).
    var onAdded: (Int, PatientRecord) -> Void

    @State private var text = ""
    @State private var reading: PatientNoteReading?
    @State private var chosen: Set<String> = []
    @State private var other = ""
    @State private var previous = ""
    @State private var addOther = true
    @State private var addPrevious = true
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NoIdentifiersBanner()
                    if let reading { review(reading) } else { compose }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FeedBackground())
            .navigationTitle(reading == nil ? "Fill from a note" : "Check before adding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { Keyboard.dismiss() }
                }
            }
        }
        .task { seedForScreenshot() }
    }

    // MARK: Writing the note

    @ViewBuilder private var compose: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("e.g. 68M for elective lap colectomy under GA. HTN, T2DM on insulin, OSA on CPAP. Denies chest pain. Climbs 2 flights. Meds: metoprolol, glargine. NKDA. BP 148/86. Mallampati 3. NPO after midnight.")
                    .font(PS.sys(size: 15))
                    .foregroundStyle(PS.fg3)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .focused($editing)
                .font(PS.sys(size: 15))
                .foregroundStyle(PS.fg)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 230)
        }
        .padding(10)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        VStack(alignment: .leading, spacing: 6) {
            hint("text.alignleft", "Write it the way you'd chart it: age and sex, procedure, history, medications, allergies, vitals, airway and fasting.")
            hint("mic", "To dictate, tap the microphone on the keyboard.")
            hint("lock", "Read on this phone; the note itself isn't kept. You check every item before it's added.")
        }
        .padding(.horizontal, 2)
        Button { read() } label: {
            Label("Read the note", systemImage: "text.magnifyingglass").frame(maxWidth: .infinity)
        }
        .buttonStyle(BigButtonStyle(prominent: true))
        .disabled(blank(text))
        .opacity(blank(text) ? 0.5 : 1)
        HStack {
            Button("Try an example") { text = PatientNote.example }
                .buttonStyle(CapsuleButtonStyle(prominent: false))
            Spacer()
        }
    }

    private func hint(_ icon: String, _ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).font(PS.sys(size: 11.5, weight: .semibold)).foregroundStyle(PS.fg3).frame(width: 16)
            Text(s).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Checking what was read

    @ViewBuilder private func review(_ reading: PatientNoteReading) -> some View {
        let count = changes(reading).count
        VStack(alignment: .leading, spacing: 6) {
            Text(reading.isEmpty ? "Nothing was recognized" : "Found \(reading.findings.count) item\(reading.findings.count == 1 ? "" : "s")")
                .font(PS.serif(size: 22))
                .foregroundStyle(PS.fg)
            Text(reading.isEmpty ? "Try the usual abbreviations (HTN, DM, OSA, NKDA, BP 120/80), or edit the note." : "Untick anything that's wrong. Nothing changes until you tap Add.")
                .font(PS.sys(size: 13.5))
                .foregroundStyle(PS.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !reading.identifiers.isEmpty { identifierWarning(reading.identifiers) }
        ForEach(PatientNote.sections, id: \.self) { s in
            let items = reading.findings.filter { $0.section == s }
            if !items.isEmpty {
                PatientGroup(title: s) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, f in
                        findingRow(f, PatientNote.status(f, in: patient.record))
                        if i < items.count - 1 { Hairline().padding(.leading, 48) }
                    }
                }
            }
        }
        if !reading.other.isEmpty {
            leftover("Other conditions", note: "Parts of the note nothing above was read from. Edit before adding; they go under History, Other conditions.",
                     text: $other, on: $addOther)
        }
        if !reading.previous.isEmpty {
            leftover("Previous surgery and anesthetics", note: "From the surgical or anesthetic history; they go under Anesthesia history details.",
                     text: $previous, on: $addPrevious)
        }
        let missing = PatientNote.missing(preview(reading))
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Still to fill on My Patient").padding(.leading, 2)
                WrapLayout(spacing: 6) {
                    ForEach(missing, id: \.self) { m in
                        Text(m)
                            .font(PS.sys(size: 12.5, weight: .semibold))
                            .foregroundStyle(PS.fg2)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(PS.surface, in: Capsule())
                            .overlay(Capsule().stroke(PS.line2, lineWidth: 1))
                    }
                }
            }
        }
        Button { add(reading) } label: {
            Label(count == 0 ? "Nothing selected" : "Add \(count) item\(count == 1 ? "" : "s")", systemImage: "plus").frame(maxWidth: .infinity)
        }
        .buttonStyle(BigButtonStyle(prominent: true))
        .disabled(count == 0)
        .opacity(count == 0 ? 0.5 : 1)
        Button { withAnimation(.snappy) { self.reading = nil } } label: {
            Label("Edit the note", systemImage: "pencil").frame(maxWidth: .infinity)
        }
        .buttonStyle(BigButtonStyle(prominent: false))
    }

    private func identifierWarning(_ kinds: [String]) -> some View {
        let list = kinds.count == 1 ? kinds[0] : kinds.dropLast().joined(separator: ", ") + " or " + (kinds.last ?? "")
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.accent)
            Text("The note may include \(list). The note isn't kept, but text added below is: take identifiers out first.")
                .font(PS.sys(size: 13)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func findingRow(_ f: PatientNoteFinding, _ status: PatientNoteStatus) -> some View {
        let can = status.canAdd
        let on = can && chosen.contains(f.id)
        return Button {
            Haptics.light()
            if chosen.contains(f.id) { chosen.remove(f.id) } else { chosen.insert(f.id) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: !can ? "minus.circle" : (on ? "checkmark.circle.fill" : "circle"))
                    .font(PS.sys(size: 19, weight: .semibold))
                    .foregroundStyle(on ? PS.green : PS.fg3)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(f.label)
                        .font(PS.sys(size: 14.5, weight: .medium))
                        .foregroundStyle(can ? PS.fg : PS.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let s = statusText(status) {
                        Text(s).font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(statusColor(status)).fixedSize(horizontal: false, vertical: true)
                    }
                    if let n = f.note, can {
                        Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!can)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func statusText(_ s: PatientNoteStatus) -> String? {
        switch s {
        case .new: return nil
        case .recorded: return "Already recorded"
        case .replaces(let old): return "Replaces " + old
        case .conflicts(let why): return why
        }
    }

    private func statusColor(_ s: PatientNoteStatus) -> Color {
        switch s {
        case .new, .recorded: return PS.fg3
        case .replaces: return PS.accent2
        case .conflicts: return PS.accent
        }
    }

    private func leftover(_ title: String, note: String, text: Binding<String>, on: Binding<Bool>) -> some View {
        PatientGroup(title: title, note: note) {
            Button {
                Haptics.light()
                on.wrappedValue.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: on.wrappedValue ? "checkmark.circle.fill" : "circle")
                        .font(PS.sys(size: 19, weight: .semibold))
                        .foregroundStyle(on.wrappedValue ? PS.green : PS.fg3)
                        .frame(width: 22)
                    Text(on.wrappedValue ? "Add this text" : "Leave it out")
                        .font(PS.sys(size: 14.5, weight: .medium))
                        .foregroundStyle(PS.fg)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Hairline().padding(.leading, 14)
            PatientTextField(label: "Text", prompt: "", text: text)
        }
    }

    // MARK: Actions

    private func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func read() {
        Keyboard.dismiss()
        let result = PatientNote.read(text)
        let r = patient.record
        chosen = Set(result.findings.filter { PatientNote.status($0, in: r).onByDefault }.map(\.id))
        other = result.other
        previous = result.previous
        let flagged = !result.identifiers.isEmpty
        addOther = !result.other.isEmpty && !flagged
        addPrevious = !result.previous.isEmpty && !flagged
        withAnimation(.snappy) { reading = result }
    }

    private func changes(_ reading: PatientNoteReading) -> [PatientNoteChange] {
        let r = patient.record
        var out = reading.findings.filter { chosen.contains($0.id) && PatientNote.status($0, in: r).canAdd }.map(\.change)
        if addOther && !blank(other) { out.append(.otherHistory(other)) }
        if addPrevious && !blank(previous) { out.append(.anesthesiaNotes(previous)) }
        return out
    }

    private func preview(_ reading: PatientNoteReading) -> PatientRecord {
        var r = patient.record
        PatientNote.apply(changes(reading), to: &r)
        return r
    }

    private func add(_ reading: PatientNoteReading) {
        let list = changes(reading)
        guard !list.isEmpty else { return }
        let before = patient.record
        patient.update { PatientNote.apply(list, to: &$0) }
        Haptics.success()
        onAdded(list.count, before)
        dismiss()
    }

    /// Screenshot runs: -ps.patient.note example (or the text of a note) reads it on open.
    private func seedForScreenshot() {
        #if DEBUG
        let t = LaunchSeed.string("ps.patient.note")
        guard !t.isEmpty, reading == nil else { return }
        text = t == "example" ? PatientNote.example : t
        read()
        #endif
    }
}

/// A patient a colleague sent: what it holds, and whether to open it in place of the current one.
struct PatientReceiveSheet: View {
    @Environment(PatientStore.self) private var patient
    @Environment(\.dismiss) private var dismiss
    var packet: PatientPacket
    /// After opening it; true when another patient was replaced (Undo can bring it back).
    var onOpened: (Bool) -> Void

    private var r: PatientRecord { packet.record }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "From a colleague", color: PS.accent2)
                        Text(r.person.isEmpty ? "Patient" : r.person)
                            .font(PS.serif(size: 26)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                        if !r.procedure.isEmpty {
                            Text(r.procedure).font(PS.sys(size: 15, weight: .medium)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                        }
                        let size = PatientSummary.bodyLine(r)
                        if !size.isEmpty { Text(size).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true) }
                        Text(packet.contents + " · sent " + PatientSummary.time(packet.sent))
                            .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                    if !patient.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.accent)
                            Text("This replaces the patient on your phone (\(patient.record.person.isEmpty ? "unnamed" : patient.record.person)). Undo brings it back until your next edit.")
                                .font(PS.sys(size: 13)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PS.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Button { open() } label: {
                        Label(patient.isEmpty ? "Open This Patient" : "Replace My Patient", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BigButtonStyle(prominent: true))
                    Button { dismiss() } label: { Text("Discard").frame(maxWidth: .infinity) }
                        .buttonStyle(BigButtonStyle(prominent: false))
                    Text("Check it against the chart. It stays on this phone like any patient you enter, until you clear it; the file you received has been deleted.")
                        .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                }
                .padding(20)
            }
            .background(FeedBackground())
            .navigationTitle("Patient Received")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func open() {
        let replacing = !patient.isEmpty
        patient.receive(packet.record)
        Haptics.success()
        onOpened(replacing)
        dismiss()
    }
}
