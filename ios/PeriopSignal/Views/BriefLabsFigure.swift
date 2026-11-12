import SwiftUI

// MARK: - The Labs block of the summaries (1.12, Ben's note 8)
//
// No fishbone figures: two columns, "Preop" and "Intraop" (the Preprocedure Summary has the Preop column alone, full
// width). Each group is a short paragraph, its name in bold ("CMP: Na 138, K 4.1, …"); the Intraop column starts with
// the newest blood gas drawn as the slash figure (pH / PCO₂ / PO₂ / HCO₃) labelled with its type and time, then its
// lactate. Abnormal values are bold red with no H or L beside them (1.12). The small caption under the block carries
// the times. At the larger text sizes the columns stack. The values and their order are BriefLabs (PatientBriefLabs.swift).

struct BriefLabsFigure: View {
    var labs: BriefLabs
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Two columns while the text is at its usual size; stacked at the larger ones. Both text sizes count: the system's
    /// Dynamic Type and the app's own (More > Text size, PS.textScale, which the Large and Extra large choices raise above 1).
    static func sideBySide(hasPreop: Bool, hasIntraop: Bool, typeSize: DynamicTypeSize, textScale: CGFloat) -> Bool {
        hasPreop && hasIntraop && typeSize <= .large && textScale <= 1.0
    }

    private var sideBySide: Bool {
        Self.sideBySide(hasPreop: labs.hasPreop, hasIntraop: labs.hasIntraop, typeSize: typeSize, textScale: PS.textScale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sideBySide {
                HStack(alignment: .top, spacing: 12) {
                    column("Preop", labs.preop).frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(PS.line2).frame(width: 1)
                    column("Intraop", labs.intraop).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                if labs.hasPreop { column("Preop", labs.preop) }
                if labs.hasIntraop { column("Intraop", labs.intraop) }
            }
            if let c = labs.caption {
                Text(c).font(PS.sys(size: 9)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
            }
            #if DEBUG
            // Screenshot runs: -ps.handoff.extras.preview 1 shows "+ Add other input data into Handoff" under the labs, for
            // the shots of its chips (the link's real place, under the handoff card, is helper B's).
            if LaunchSeed.bool("ps.handoff.extras.preview") { HandoffExtrasLink().padding(.top, 6) }
            #endif
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Labs. " + labs.spokenParagraphs.map { PatientBriefs.ascii($0) }.joined(separator: ". ") + (labs.caption.map { ". " + PatientBriefs.ascii($0) } ?? ""))
    }

    private func column(_ title: String, _ groups: [BriefLabGroup]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: title, color: PS.fg3, size: 10)
            ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                if g.isGas, let gas = labs.gas {
                    BriefGasFigure(gas: gas, group: g)
                } else {
                    Text(briefStyled(g.text, marks: g.marks, labels: true, size: 13))
                        .font(PS.sys(size: 13)).foregroundStyle(PS.fg)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Kept for the share code that draws the labs as a picture (HandoffShare.fishboneImage); the figure is no fishbone now.
typealias FishboneFigure = BriefLabsFigure

/// The blood gas as the slash figure: "ABG · 10:40", then pH / PCO₂ / PO₂ / HCO₃ with a slash between, then the lactate (and,
/// for an ScvO₂ or SvO₂ sample, the saturation first). Where even the tightest figure does not fit its column the values are written as
/// text instead.
private struct BriefGasFigure: View {
    var gas: BriefGas
    var group: BriefLabGroup

    private static let names = ["pH", "PCO₂", "PO₂", "HCO₃"]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(gas.figureLabel).font(PS.sys(size: 13, weight: .bold)).foregroundStyle(PS.fg)
            if let s = gas.saturation { line(s) }
            if gas.hasSlash {
                ViewThatFits(in: .horizontal) {
                    slash(cellWidth: 38, gap: 9)
                    slash(cellWidth: 32, gap: 5)
                    // The half column of a 375-pt phone is about 137 pt: these two keep the figure a figure there.
                    slash(cellWidth: 30, gap: 3)
                    slash(cellWidth: 27, gap: 3)
                    if let item = group.items.first(where: { $0.key == "gas" }) {
                        Text(briefStyled(item.text, marks: item.marks, labels: false, size: 13))
                            .font(PS.sys(size: 13)).foregroundStyle(PS.fg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let l = gas.lactate { line(l) }
        }
    }

    private func line(_ c: BriefLabCell) -> some View {
        Text(briefStyled(c.compact, marks: c.marks, labels: false, size: 13))
            .font(PS.sys(size: 13)).foregroundStyle(PS.fg)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func slash(cellWidth: CGFloat, gap: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(gas.slash.enumerated()), id: \.offset) { i, c in
                if i > 0 { FishboneSlash().stroke(PS.fg3, lineWidth: 1).frame(width: gap, height: 22) }
                cell(c, label: Self.names[i], width: cellWidth)
            }
        }
    }

    /// One value under its name; an abnormal one is bold red, with no H or L after it (1.12).
    private func value(_ c: BriefLabCell?) -> Text {
        guard let c else { return Text("—").font(PS.sys(size: 12, design: .monospaced)).foregroundColor(PS.fg3) }
        return Text(c.text).font(PS.sys(size: 12, weight: c.abnormal ? .heavy : .semibold, design: .monospaced))
            .foregroundColor(c.abnormal ? PS.red : PS.fg)
    }

    private func cell(_ c: BriefLabCell?, label: String, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            value(c).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(PS.sys(size: 8)).foregroundStyle(PS.fg3)
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c.map { label + " " + $0.text + ($0.flag.word.isEmpty ? "" : ", " + $0.flag.word) } ?? label + " not recorded")
    }
}
