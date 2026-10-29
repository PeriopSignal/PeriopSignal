import SwiftUI

/// Renders one condensed reference: eyebrow, title, summary, then its sections (tables, facts,
/// lists, steps, paragraphs), the source and the review line.
struct QuickRefView: View {
    var ref: QuickRef
    var onOpen: (URL) -> Void
    @State private var copied = false
    /// The patient's weight lives only while this card is open.
    @State private var weightText = LaunchSeed.string("ps.la.weight")
    /// Ticked steps per section (emergency cards are checklists).
    @State private var done: [Int: Set<Int>] = [:]
    @FocusState private var focused: Bool

    private var weight: Double? { WeightField.value(weightText) }

    private var checklistSections: [Int] {
        guard ref.isEmergency else { return [] }
        return ref.sections.indices.filter { ref.sections[$0].kind == .steps }
    }
    private var totalSteps: Int { checklistSections.reduce(0) { $0 + (ref.sections[$1].items?.count ?? 0) } }
    private var doneSteps: Int { done.values.reduce(0) { $0 + $1.count } }

    private var tint: Color { ref.isEmergency ? PS.accent : Topics.info(ref.topic ?? "general").fg }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let doses = ref.weightDoses, !doses.isEmpty { weightCard(doses) }
                if totalSteps > 0 {
                    ChecklistProgress(done: doneSteps, total: totalSteps, tint: tint, title: "Emergency Checklist") { done = [:] }
                        .padding(14)
                        .background(PS.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1))
                }
                ForEach(Array(ref.sections.enumerated()), id: \.offset) { i, section in
                    RefSectionView(section: section, tint: tint, done: checklistSections.contains(i) ? Binding(get: { done[i] ?? [] }, set: { done[i] = $0 }) : nil)
                }
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if ref.isEmergency {
                        Button { withAnimation(.snappy) { done = [:] } } label: { Label("Reset the checklist", systemImage: "arrow.counterclockwise") }
                    }
                    if let url = URL(string: ref.source.url) {
                        Button { onOpen(url) } label: { Label("Open the source document", systemImage: "arrow.up.right.square") }
                    }
                    Button {
                        UIPasteboard.general.string = ref.source.citation ?? ref.source.title
                        copied = true
                    } label: { Label("Copy citation", systemImage: "doc.on.doc") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sensoryFeedback(.success, trigger: copied)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if ref.isEmergency { Eyebrow(text: "Emergency checklist", color: PS.accent) }
                Eyebrow(text: [ref.society, ref.year.map { String($0) }].compactMap { $0 }.joined(separator: " · "), color: ref.isEmergency ? PS.fg3 : tint)
            }
            Text(ref.title.titleCased)
                .font(PS.serif(size: 25, weight: .semibold))
                .foregroundStyle(PS.fg)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            Text(ref.summary)
                .font(PS.sys(size: 15))
                .foregroundStyle(PS.fg2)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
            ECGLine().stroke(tint.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)).frame(height: 20).padding(.top, 2)
        }
    }

    /// Weight in, the regimen's doses out (lipid volumes and rates, dantrolene with vial counts…).
    private func weightCard(_ doses: [WeightDose]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Doses for this patient", color: tint)
            WeightField(text: $weightText, focus: $focused, prompt: "Enter the weight: the doses below are per kilogram until you do.")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(doses.enumerated()), id: \.element.id) { i, d in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.label).font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                            if let n = d.note { Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(computed(d))
                                .font(PS.sys(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(weight == nil ? PS.fg3 : PS.fg)
                                .multilineTextAlignment(.trailing)
                            if let v = vials(d) { Text(v).font(PS.sys(size: 11.5)).foregroundStyle(tint) }
                        }
                    }
                    .padding(.vertical, 9)
                    if i < doses.count - 1 { Hairline() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1))
    }

    private func computed(_ d: WeightDose) -> String {
        guard let w = weight else {
            let perKg = PedsCalc.fmt(d.perKg) + (d.perKgHigh.map { "–" + PedsCalc.fmt($0) } ?? "")
            return "\(perKg) \(d.unit)/kg"
        }
        if let above = d.aboveKg, w > above, let text = d.aboveText { return text }
        return PedsCalc.doseText(low: d.perKg, high: d.perKgHigh, unit: d.unit, weightKg: w, max: d.max).text
    }

    private func vials(_ d: WeightDose) -> String? {
        guard let w = weight, let size = d.vialSize, size > 0 else { return nil }
        var mg = d.perKg * w
        if let m = d.max { mg = min(mg, m) }
        let n = Int((mg / size).rounded(.up))
        return "\(n) × \(d.vialName ?? "vial")"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            Eyebrow(text: "Source")
            Text(ref.source.citation ?? ref.source.title)
                .font(PS.sys(size: 13))
                .foregroundStyle(PS.fg2)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: ref.source.url) {
                Button { onOpen(url) } label: { Text("Open the source document ↗") }
                    .buttonStyle(TextButtonStyle(color: PS.accent, size: 13.5))
            }
            Text("Condensed by Periop Signal\(ref.reviewed.map { ", reviewed \(PSDate.monthYear($0))" } ?? ""). A quick reference, not the guideline: confirm against the source document and your own judgement before acting on it.")
                .font(PS.sys(size: 12))
                .foregroundStyle(PS.fg3)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }
}

/// One section of a quick reference. With `done`, a steps section is a checklist.
struct RefSectionView: View {
    var section: RefSection
    var tint: Color
    var done: Binding<Set<Int>>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let h = section.heading {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(h.titleCased)
                        .font(PS.serif(size: 18))
                        .foregroundStyle(PS.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    if let done, let n = section.items?.count {
                        Text("\(done.wrappedValue.count)/\(n)")
                            .font(PS.mono(size: 11, weight: .semibold))
                            .foregroundStyle(done.wrappedValue.count == n ? PS.green : PS.fg3)
                    }
                }
            }
            content
            if let note = section.note {
                Text(note)
                    .font(PS.sys(size: 12.5))
                    .italic()
                    .foregroundStyle(PS.fg3)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch section.kind {
        case .text:
            Text(section.text ?? "")
                .font(PS.sys(size: 15))
                .foregroundStyle(PS.fg)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        case .list:
            TakeHomeList(items: section.items ?? [], size: 14.5)
        case .steps:
            StepList(items: section.items ?? [], tint: tint, done: done)
        case .facts:
            FactTable(rows: section.rows ?? [])
        case .table:
            RefTable(columns: section.columns ?? [], rows: section.rows ?? [])
        }
    }
}

/// Numbered steps; with `done` each step is a box to tick, like a pilot's checklist.
struct StepList: View {
    var items: [String]
    var tint: Color
    var done: Binding<Set<Int>>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if let done {
                    ChecklistItemRow(number: i + 1, text: item, done: done.wrappedValue.contains(i), tint: tint) {
                        if done.wrappedValue.contains(i) { done.wrappedValue.remove(i) } else { done.wrappedValue.insert(i) }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(i + 1)")
                            .font(PS.mono(size: 11.5))
                            .foregroundStyle(tint)
                            .frame(width: 22, height: 22)
                            .background(tint.opacity(0.12), in: Circle())
                            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
                        Text(item)
                            .font(PS.sys(size: 14.5))
                            .foregroundStyle(PS.fg)
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 9)
                }
                if i < items.count - 1 { Hairline().padding(.leading, done == nil ? 34 : 38) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay {
            if done != nil {
                RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(tint.opacity(0.25), lineWidth: 1)
            }
        }
    }
}

/// Two-column label/value rows.
struct FactTable: View {
    var rows: [[String]]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.first ?? "")
                        .font(PS.sys(size: 13, weight: .semibold))
                        .foregroundStyle(PS.fg2)
                        .frame(width: 118, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.count > 1 ? row[1] : "")
                        .font(PS.sys(size: 14.5))
                        .foregroundStyle(PS.fg)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 9)
                if i < rows.count - 1 { Hairline() }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }
}

/// A table that stays readable on a phone: each row becomes a block headed by its first cell, with
/// the remaining columns as label/value pairs.
struct RefTable: View {
    var columns: [String]
    var rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.first ?? "")
                        .font(PS.sys(size: 14.5, weight: .semibold))
                        .foregroundStyle(PS.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(row.dropFirst().enumerated()), id: \.offset) { j, cell in
                        if !cell.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(columns.count > j + 1 ? columns[j + 1] : "")
                                    .font(PS.mono(size: 10, weight: .semibold))
                                    .textCase(.uppercase)
                                    .kerning(0.6)
                                    .foregroundStyle(PS.fg3)
                                    .frame(width: 104, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(cell)
                                    .font(PS.sys(size: 14))
                                    .foregroundStyle(cell == "—" ? PS.fg3 : PS.fg)
                                    .lineSpacing(1.5)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.vertical, 11)
                if i < rows.count - 1 { Hairline() }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }
}
