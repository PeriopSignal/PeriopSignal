import SwiftUI

/// Renders one condensed reference: eyebrow, title, summary, then its sections (tables, facts,
/// lists, steps, paragraphs), the source and the review line.
struct QuickRefView: View {
    var ref: QuickRef
    var onOpen: (URL) -> Void
    @State private var copied = false

    private var tint: Color { ref.isEmergency ? PS.accent : Topics.info(ref.topic ?? "general").fg }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                ForEach(Array(ref.sections.enumerated()), id: \.offset) { _, section in
                    RefSectionView(section: section, tint: tint)
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
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
            StepList(items: section.items ?? [], tint: tint)
        case .facts:
            FactTable(rows: section.rows ?? [])
        case .table:
            RefTable(columns: section.columns ?? [], rows: section.rows ?? [])
        }
    }
}

/// Numbered steps (emergency checklists).
struct StepList: View {
    var items: [String]
    var tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
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
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 9)
                if i < items.count - 1 { Hairline().padding(.leading, 34) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
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
