import SwiftUI

/// Renders one condensed reference: eyebrow, title, summary, then its sections (tables, facts,
/// lists, steps, paragraphs), the source and the review line.
struct QuickRefView: View {
    var ref: QuickRef
    var onOpen: (URL) -> Void
    @State private var copied = false
    @AppStorage("ps.la.weight") private var weightText = ""
    @State private var resetToken = 0
    @FocusState private var focused: Bool

    private var weight: Double? {
        let v = Double(weightText.replacingOccurrences(of: ",", with: "."))
        return (v ?? 0) > 0 ? v : nil
    }

    private var tint: Color { ref.isEmergency ? PS.accent : Topics.info(ref.topic ?? "general").fg }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let doses = ref.weightDoses, !doses.isEmpty { weightCard(doses) }
                ForEach(Array(ref.sections.enumerated()), id: \.offset) { _, section in
                    RefSectionView(section: section, tint: tint, checkable: ref.isEmergency, resetToken: resetToken)
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
                        Button { withAnimation(.snappy) { resetToken += 1 } } label: { Label("Reset the checklist", systemImage: "arrow.counterclockwise") }
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
            Text(ref.title)
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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Eyebrow(text: "Doses for this patient", color: tint)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("kg", text: $weightText)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .multilineTextAlignment(.trailing)
                        .font(PS.serif(size: 24, weight: .semibold))
                        .foregroundStyle(PS.fg)
                        .frame(width: 72)
                    Text("kg").font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
                }
            }
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

/// One section of a quick reference.
struct RefSectionView: View {
    var section: RefSection
    var tint: Color
    var checkable = false
    var resetToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let h = section.heading {
                Text(h)
                    .font(PS.serif(size: 18))
                    .foregroundStyle(PS.fg)
                    .fixedSize(horizontal: false, vertical: true)
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
            StepList(items: section.items ?? [], tint: tint, checkable: checkable, resetToken: resetToken)
        case .facts:
            FactTable(rows: section.rows ?? [])
        case .table:
            RefTable(columns: section.columns ?? [], rows: section.rows ?? [])
        }
    }
}

/// Numbered steps; on emergency cards each step is a checkbox, like a pilot's checklist.
struct StepList: View {
    var items: [String]
    var tint: Color
    var checkable = false
    var resetToken = 0
    @State private var done: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let isDone = done.contains(i)
                Button {
                    guard checkable else { return }
                    Haptics.light()
                    withAnimation(.snappy) { if isDone { done.remove(i) } else { done.insert(i) } }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        if checkable {
                            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                .font(PS.sys(size: 20))
                                .foregroundStyle(isDone ? PS.green : tint)
                                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 }
                        } else {
                            Text("\(i + 1)")
                                .font(PS.mono(size: 11.5))
                                .foregroundStyle(tint)
                                .frame(width: 22, height: 22)
                                .background(tint.opacity(0.12), in: Circle())
                                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
                        }
                        Text(item)
                            .font(PS.sys(size: 14.5))
                            .foregroundStyle(isDone ? PS.fg3 : PS.fg)
                            .strikethrough(isDone, color: PS.fg3)
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < items.count - 1 { Hairline().padding(.leading, 34) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .onChange(of: resetToken) { _, _ in done = [] }
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
