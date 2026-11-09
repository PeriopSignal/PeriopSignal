import SwiftUI

// MARK: - The Laboratory Studies card on the Preoperative tab (1.11, P1-1)
//
// The card shows the BMP, CBC and coagulation fishbones small, as the brief does, with one line of the other results
// beneath (hepatic and mineral values, GFR, HbA1c, lactate, type and screen, infectious results, the lab notes) and the
// liver scores; a tap on a slot opens the Labs page with the keyboard already on that slot (LabSlotFocusRequest); the
// title row opens the page as before. Empty, it is one quiet "+ Add labs" line. The figures come from the same geometry
// as the page's slots and the brief's figure (FishboneGeometry.small).

struct PreopLabsCard: View {
    @Environment(PatientStore.self) private var patient

    private var r: PatientRecord { patient.record }

    /// Nothing on the labs side of the record: the card is the "+ Add labs" line.
    static func isEmpty(_ r: PatientRecord) -> Bool {
        PatientSummary.labsLine(r.capitalized) == nil && PatientSummary.liverLine(r) == nil
    }

    /// The values without a place on the card's three figures (the hepatic figure, Mg and PO₄, GFR, HbA1c, lactate,
    /// the cardiac and thyroid groups), then type and screen, the infectious results and the lab notes, as one line;
    /// abnormal values and positive results marked for bold red. Nil when there is nothing beyond the figures.
    static func otherLine(_ r: PatientRecord) -> PatientSummary.Line? {
        let c = r.capitalized
        let sum = PatientLabs.summary(c)
        let figure = Set(BriefLabs.bmpKeys + BriefLabs.cbcKeys + BriefLabs.coagKeys)
        let rest = sum.items.filter { !figure.contains($0.key) }
        let more = LabResults.lineParts(c)
        let note = c.labNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = rest.map(\.compact) + more.parts + (note.isEmpty ? [] : [note])
        guard !parts.isEmpty else { return nil }
        return PatientSummary.Line(nil, parts.joined(separator: " · "), marks: rest.filter { $0.flag.isAbnormal }.map(\.compact) + more.marks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            NavigationLink(value: PatientEditor.workup("labs")) {
                HStack(spacing: 8) {
                    Image(systemName: "testtube.2").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.action)
                    Text("Laboratory Studies").font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
                    Spacer()
                    Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the Labs page")
            if Self.isEmpty(r) {
                NavigationLink(value: PatientEditor.workup("labs")) {
                    HStack(spacing: 5) {
                        Text("+").font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.action)
                        Text("Add labs").font(PS.sys(size: 13.5, weight: .medium)).foregroundStyle(PS.fg2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add labs")
            } else {
                let sum = PatientLabs.summary(r)
                let g = FishboneGeometry.small
                VStack(alignment: .leading, spacing: 8) {
                    FishboneBMP(g: g) { cell($0, sum) }
                    FishboneCBC(g: g) { cell($0, sum) }
                    FishboneCoags(g: g, fibrinogen: r.labs["fibrinogen"] != nil) { cell($0, sum) }
                }
                if let line = Self.otherLine(r) { PatientLineText(line: line) }
                if let liver = PatientSummary.liverLine(r) { PatientLineText(line: liver) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    /// One small cell: the value (or "—"), its name beneath, abnormal in bold red, an estimate in italic with "~". A tap
    /// opens the page on this slot: the request is noted as the link fires.
    @ViewBuilder private func cell(_ key: String, _ sum: LabSummary) -> some View {
        let v = sum.items.first { $0.key == key }
        let est = v == nil && sum.estimate?.key == key ? sum.estimate : nil
        let shown = v ?? est
        let name = PatientLabs.test(key)?.short ?? key
        NavigationLink(value: PatientEditor.workup("labs")) {
            VStack(spacing: 0) {
                Text(shown.map { ($0.estimated ? "~" : "") + $0.text } ?? "—")
                    .font(PS.sys(size: 12.5, weight: v?.flag.isAbnormal == true ? .heavy : .semibold, design: .monospaced))
                    .italic(est != nil)
                    .foregroundStyle(shown == nil || est != nil ? PS.fg3 : (v?.flag.isAbnormal == true ? PS.red : PS.fg))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(est != nil ? name + " est." : name).font(PS.sys(size: 8)).foregroundStyle(PS.fg3).lineLimit(1)
            }
            .frame(width: FishboneGeometry.small.cellWidth, height: FishboneGeometry.small.cellHeight)
            // A 44-pt hit area around a 30-pt cell.
            .contentShape(Rectangle().inset(by: -7))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { LabSlotFocusRequest.pending = "main." + key })
        .accessibilityLabel(PatientLabs.test(key).map { LabSlot.accessibilityText($0, value: v?.value, sex: r.sex, flag: v?.flag ?? .normal, estimate: est) } ?? name)
        .accessibilityHint("Opens the Labs page on this value")
    }
}
