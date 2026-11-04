import SwiftUI

// MARK: - The patient diagram
//
// A front-view figure (the Regional Technique Finder's outline) with the airway, lines and devices drawn on it, each
// with a tiny colored label. The drawing works in the figure's own 200 × 420 units, widened on both sides for the
// labels and the ECMO cart; PatientDiagramModel turns the record into the items drawn here.

/// One thing drawn on the patient: a marker at its insertion point, an optional course (a central line to the cava,
/// a cannula to the ECMO cart, a balloon up the aorta) and a label.
struct DiagramItem: Identifiable, Hashable {
    /// `generator`: a pacemaker or ICD can in its pocket; `alert`: the "!ⓘ" limb alert (1.9).
    enum Marker: Hashable { case dot, square, pump, needle, stoma, generator, alert, none }

    var id: String
    /// Insertion point in figure units, the user's drag already added.
    var anchor: CGPoint
    /// The course after the anchor, in figure units (empty for a single point).
    var course: [CGPoint] = []
    var color: Color
    var width: CGFloat = 1.6
    var dashed = false
    var marker: Marker = .dot
    var label: String
    /// Where the label sits: left or right of the anchor (left of the figure's midline labels go left).
    var labelLeft: Bool
    /// Can be dragged and deleted in edit mode (the airway from the record cannot).
    var movable = true
    /// Something on the course to draw as a pump or balloon, at this point.
    var pumpAt: CGPoint?
    /// Moves the label down, for several items at one site.
    var labelDY: CGFloat = 0
    /// Where the label is drawn when the layout moved it to a column beside the figure (with a leader line back to
    /// the insertion point), so labels never overlap.
    var labelAt: CGPoint?
    /// What VoiceOver says when the drawn label is not it: the limb alert's limb and reasons (1.9).
    var spoken: String?

    /// The marker's name for VoiceOver.
    var caption: String { spoken ?? label }

    static func == (a: DiagramItem, b: DiagramItem) -> Bool {
        a.id == b.id && a.anchor == b.anchor && a.course == b.course && a.label == b.label && a.marker == b.marker && a.pumpAt == b.pumpAt
            && a.spoken == b.spoken
    }
    func hash(into h: inout Hasher) { h.combine(id); h.combine(label) }
}

/// The ECMO circuit's cart beside the bed, where the cannulas run.
struct DiagramCart: Hashable {
    var at: CGPoint
    var title: String
    var detail: String
}

/// Colors by role, as Ben specified: central lines dark blue, PA catheter yellow, venous ECMO blue, arterial ECMO red,
/// neuraxial catheters black.
enum DiagramColor {
    static let peripheral = Color.dynamic(dark: "6FD39B", light: "1E8E57")
    static let arterial = Color.dynamic(dark: "FF7B7B", light: "D23B3B")
    static let central = Color.dynamic(dark: "6E8BFF", light: "1F3A9E")
    static let pac = Color.dynamic(dark: "FFD54A", light: "C99A00")
    static let venousECMO = Color.dynamic(dark: "5BA8FF", light: "1F6FE0")
    static let arterialECMO = Color.dynamic(dark: "FF5C5C", light: "D21F1F")
    static let pump = Color.dynamic(dark: "C7A6FF", light: "6A3FC2")
    static let neuraxial = Color.dynamic(dark: "E6E9EF", light: "111111")
    static let needle = Color.dynamic(dark: "B5BFCC", light: "4B5666")
    static let airway = Color.dynamic(dark: "4FD1C5", light: "0E8A80")
    /// 1.9: temporary and implanted pacing orange, dialysis access magenta, chest tubes brown, limb alerts amber with ink
    /// that reads on it in light and dark.
    static let pacing = Color.dynamic(dark: "FFA94D", light: "C2410C")
    static let access = Color.dynamic(dark: "F472B6", light: "B1206B")
    static let drain = Color.dynamic(dark: "D2A06B", light: "7A4A1E")
    static let limbAlert = Color.dynamic(dark: "FFC247", light: "B45309")
    static let limbAlertInk = Color.dynamic(dark: "1B1B1F", light: "FFFFFF")
}

/// The "!ⓘ" of a limb alert, for lists and captions (the figure draws the same mark itself).
struct LimbAlertBadge: View {
    var body: some View {
        HStack(spacing: 1.5) {
            Text("!").font(.system(size: 12, weight: .heavy))
            Image(systemName: "info.circle").font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(DiagramColor.limbAlertInk)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(DiagramColor.limbAlert, in: Capsule())
        .accessibilityHidden(true)
    }
}

/// The limb alerts under a figure: the mark, then "L arm — AV fistula" for each limb (1.9).
struct LimbAlertCaption: View {
    var groups: [PatientDeviceFills.LimbAlertGroup]
    var body: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(groups) { g in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        LimbAlertBadge()
                        Text(g.text).font(PS.sys(size: 13, weight: .medium)).foregroundStyle(PS.fg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Limb alert: " + groups.map(\.text).joined(separator: "; "))
        }
    }
}

/// The figure's long press (the editor's edit mode), only where there is one: a read-only figure has no gesture.
private struct DiagramLongPress: ViewModifier {
    var action: (() -> Void)?
    func body(content: Content) -> some View {
        if let action { content.onLongPressGesture(minimumDuration: 0.4, perform: action) } else { content }
    }
}

struct PatientDiagramCanvas: View {
    var figure: RegionalFigure
    var items: [DiagramItem]
    var cart: DiagramCart?
    /// Edit mode: the markers jiggle, drag at once to move, × to delete.
    var editing = false
    var onTapFigure: ((CGPoint) -> Void)? = nil
    var onTapItem: ((String) -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    var onMove: ((String, CGSize) -> Void)? = nil
    var onDelete: ((String) -> Void)? = nil
    /// An item held and let go without moving: the editor offers its actions (details, delete).
    var onHold: ((String) -> Void)? = nil
    /// The read-only cards (1.8.1): the drawing takes the card's whole width at its height, so the labels beside a
    /// small figure have room instead of being cut off at the figure's own margins.
    var fillsWidth = false

    /// No handler given: a picture only, with no touch targets or gestures at all (the handoff, the tab cards, the
    /// shared image).
    private var readOnly: Bool {
        onTapFigure == nil && onTapItem == nil && onLongPress == nil && onMove == nil && onDelete == nil && onHold == nil
    }

    /// Figure units of margin on each side for labels and the cart: enough for the usual short labels ("CVL", "A-line
    /// 20G"); a side with a longer one ("Epi wires A+V", "Chest tube 28", 1.9) is widened to fit it (`margins`).
    static let margin: CGFloat = 48
    /// Points of air after a label, so its last glyph is never on the edge of the drawing.
    static let labelAir: CGFloat = 3
    @State private var drag: (id: String, by: CGSize)?
    @State private var wiggle = false
    /// The item being held: it lifts (larger, ringed) until let go.
    @State private var lifted: String?

    private var bw: CGFloat { CGFloat(figure.box.first ?? 200) }
    private var bh: CGFloat { CGFloat(figure.box.count > 1 ? figure.box[1] : 420) }

    var body: some View {
        Group {
            if fillsWidth { drawing } else { drawing.aspectRatio(aspect, contentMode: .fit) }
        }
        .onChange(of: editing) { _, on in wiggle = on }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Patient diagram: " + (items.isEmpty ? "no lines or devices" : items.map(\.caption).filter { !$0.isEmpty }.joined(separator: ", ")))
    }

    /// Width over height of the whole drawing, margins included; the margins are taken at scale 1 (the labels' smallest
    /// font), close enough for the frame, and the drawing centers whatever is left.
    private var aspect: CGFloat {
        let m = Self.margins(items, figureWidth: bw, k: 1)
        return (bw + m.left + m.right) / bh
    }

    /// The label font at scale k: the figure's 5.6 units, never under 7 points.
    static func fontSize(_ k: CGFloat) -> CGFloat { max(7, 5.6 * k) }

    /// How wide a label is drawn at scale k, in points.
    static func labelWidth(_ label: String, k: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize(k), weight: .semibold)
        return ceil((label as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The margin each side of the figure, in points, at scale k: the fixed margin, or more where a label in that
    /// column (which starts 2 units outside the figure) or beside its marker would otherwise run off the drawing and be
    /// cut mid-glyph. The left margin counts labels drawn to the left, the right the others.
    static func margins(_ items: [DiagramItem], figureWidth bw: CGFloat, k: CGFloat) -> (left: CGFloat, right: CGFloat) {
        var m = (left: margin * k, right: margin * k)
        for item in items where !item.label.isEmpty {
            let w = labelWidth(item.label, k: k) + labelAir
            // Points from the figure's edge to where the text starts.
            let start: CGFloat
            if let la = item.labelAt {
                start = (item.labelLeft ? -la.x : la.x - bw) * k
            } else {
                start = (item.labelLeft ? 5 - item.anchor.x : item.anchor.x + 5 - bw) * k
            }
            if item.labelLeft { m.left = max(m.left, start + w) } else { m.right = max(m.right, start + w) }
        }
        return m
    }

    /// The scale and the figure's left edge in a drawing of this size: the figure as large as fits with its margins,
    /// centered. The margins depend on the scale (the font has a floor), so a few rounds settle both.
    static func layout(_ items: [DiagramItem], figureWidth bw: CGFloat, figureHeight bh: CGFloat, in size: CGSize) -> (k: CGFloat, ox: CGFloat) {
        var k = max(0.01, min(size.width / (bw + 2 * margin), size.height / bh))
        var m = margins(items, figureWidth: bw, k: k)
        for _ in 0..<8 {
            let next = max(0.01, min((size.width - m.left - m.right) / bw, size.height / bh))
            if abs(next - k) < 0.0005 { break }
            k = next
            m = margins(items, figureWidth: bw, k: k)
        }
        return (k, (size.width - (bw * k + m.left + m.right)) / 2 + m.left)
    }

    private var drawing: some View {
        GeometryReader { geo in
            let (k, ox) = Self.layout(items, figureWidth: bw, figureHeight: bh, in: geo.size)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in draw(&ctx, k: k, ox: ox) }
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { g in
                        guard !editing else { return }
                        onTapFigure?(CGPoint(x: (g.location.x - ox) / k, y: g.location.y / k))
                    }, including: onTapFigure == nil ? .none : .all)
                    .modifier(DiagramLongPress(action: onLongPress))
                if !readOnly {
                    ForEach(items.filter(\.movable)) { item in
                        marker(item, k: k, ox: ox)
                    }
                }
            }
        }
    }

    // MARK: Markers (the touch targets)

    private func point(_ p: CGPoint, k: CGFloat, ox: CGFloat) -> CGPoint { CGPoint(x: ox + p.x * k, y: p.y * k) }

    private func moved(_ item: DiagramItem) -> CGPoint {
        guard let d = drag, d.id == item.id else { return item.anchor }
        return CGPoint(x: item.anchor.x + d.by.width, y: item.anchor.y + d.by.height)
    }

    private func marker(_ item: DiagramItem, k: CGFloat, ox: CGFloat) -> some View {
        let at = point(moved(item), k: k, ox: ox)
        let size: CGFloat = 44
        let held = lifted == item.id
        // A limb alert is only tapped (it shows its reasons): no drag, no hold, no delete (1.9).
        let isAlert = item.marker == .alert
        let interactive = (onMove != nil || onHold != nil) && !isAlert
        // Hold briefly, then drag to move; let go without moving for the item's actions. In edit mode a drag moves at once.
        let hold = LongPressGesture(minimumDuration: editing ? 0.01 : 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let d) = value else { return }
                if lifted != item.id {
                    lifted = item.id
                    Haptics.light()
                }
                if let d { drag = (item.id, CGSize(width: d.translation.width / k, height: d.translation.height / k)) }
            }
            .onEnded { value in
                defer { lifted = nil; drag = nil }
                guard case .second(true, let d) = value else { return }
                let by = CGSize(width: (d?.translation.width ?? 0) / k, height: (d?.translation.height ?? 0) / k)
                if abs(by.width) + abs(by.height) < 2 {
                    if !editing { onHold?(item.id) }
                } else {
                    onMove?(item.id, by)
                }
            }
        return ZStack(alignment: .topTrailing) {
            Circle().fill(held ? item.color.opacity(0.16) : Color.clear)
                .overlay(Circle().stroke(held ? item.color : Color.clear, lineWidth: 2))
                .frame(width: size, height: size).contentShape(Circle())
            if editing && !isAlert {
                Button { onDelete?(item.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, PS.red)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: 10, y: -10)
                .accessibilityLabel("Delete \(item.label)")
            }
        }
        .scaleEffect(held ? 1.18 : 1)
        .animation(.snappy(duration: 0.15), value: held)
        .rotationEffect(.degrees(editing && !held && !isAlert ? (wiggle ? 4 : -4) : 0))
        .animation(editing ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true) : .default, value: wiggle)
        .position(at)
        .onTapGesture { if !editing { onTapItem?(item.id) } }
        .gesture(hold, including: interactive ? .all : .none)
        .accessibilityElement()
        .accessibilityLabel(item.caption)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Delete") { if !isAlert { onDelete?(item.id) } }
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext, k: CGFloat, ox: CGFloat) {
        // The body: outline and head.
        var body = RegionalCalc.path(svg: figure.outline, scale: k)
        let h = figure.head
        let head = Path(ellipseIn: CGRect(x: CGFloat(h.cx - h.rx) * k, y: CGFloat(h.cy - h.ry) * k, width: CGFloat(h.rx * 2) * k, height: CGFloat(h.ry * 2) * k))
        body.addPath(head)
        ctx.translateBy(x: ox, y: 0)
        ctx.fill(body, with: .color(PS.surface2))
        ctx.stroke(body, with: .color(PS.fg3.opacity(0.9)), lineWidth: 1)

        // The ECMO cart and its tubing first, so the cannula markers sit on top.
        if let c = cart {
            let r = CGRect(x: (c.at.x - 27) * k, y: (c.at.y - 12) * k, width: 54 * k, height: 24 * k)
            ctx.fill(Path(roundedRect: r, cornerRadius: 4 * k), with: .color(PS.surface))
            ctx.stroke(Path(roundedRect: r, cornerRadius: 4 * k), with: .color(PS.fg2), lineWidth: 1)
            ctx.draw(Text(c.title).font(.system(size: max(6.5, 6 * k), weight: .bold)).foregroundColor(PS.fg), at: CGPoint(x: c.at.x * k, y: (c.at.y - 4) * k))
            if !c.detail.isEmpty {
                ctx.draw(Text(c.detail).font(.system(size: max(5.5, 4.6 * k), weight: .medium)).foregroundColor(PS.fg2), at: CGPoint(x: c.at.x * k, y: (c.at.y + 5) * k))
            }
        }

        for item in items {
            let a = moved(item)
            let pts = [a] + item.course
            if pts.count > 1 {
                var p = Path()
                p.move(to: CGPoint(x: pts[0].x * k, y: pts[0].y * k))
                for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.x * k, y: q.y * k)) }
                let w = item.width * max(1, k * 0.9)
                // A thin halo in the page color under each line, so lines that cross or run side by side stay apart.
                ctx.stroke(p, with: .color(PS.surface), style: StrokeStyle(lineWidth: w + 1.8, lineCap: .round, lineJoin: .round))
                ctx.stroke(p, with: .color(item.color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round, dash: item.dashed ? [3, 2.5] : []))
            }
            if let pump = item.pumpAt {
                let r = CGRect(x: (pump.x - 4.2) * k, y: (pump.y - 4.2) * k, width: 8.4 * k, height: 8.4 * k)
                ctx.fill(Path(ellipseIn: r), with: .color(item.color))
                ctx.stroke(Path(ellipseIn: r), with: .color(PS.surface), lineWidth: 1)
            }
            let c = CGPoint(x: a.x * k, y: a.y * k)
            switch item.marker {
            case .dot:
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.6 * k, y: c.y - 2.6 * k, width: 5.2 * k, height: 5.2 * k)), with: .color(item.color))
            case .square:
                ctx.fill(Path(CGRect(x: c.x - 2.6 * k, y: c.y - 2.6 * k, width: 5.2 * k, height: 5.2 * k)), with: .color(item.color))
            case .pump:
                let r = CGRect(x: c.x - 4.5 * k, y: c.y - 4.5 * k, width: 9 * k, height: 9 * k)
                ctx.fill(Path(ellipseIn: r), with: .color(item.color))
                ctx.stroke(Path(ellipseIn: r.insetBy(dx: 2 * k, dy: 2 * k)), with: .color(PS.surface), lineWidth: 0.8)
            case .needle:
                var n = Path()
                n.move(to: CGPoint(x: c.x, y: c.y))
                n.addLine(to: CGPoint(x: c.x + 6 * k, y: c.y - 6 * k))
                ctx.stroke(n, with: .color(item.color), style: StrokeStyle(lineWidth: 1.1 * max(1, k * 0.8), lineCap: .round))
                ctx.fill(Path(roundedRect: CGRect(x: c.x + 5 * k, y: c.y - 9 * k, width: 4 * k, height: 4 * k), cornerRadius: 1), with: .color(item.color))
            case .stoma:
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 3.5 * k, y: c.y - 2.2 * k, width: 7 * k, height: 4.4 * k)), with: .color(item.color), lineWidth: 1.4)
            case .generator:
                // The can of a pacemaker or ICD in its pocket.
                let can = CGRect(x: c.x - 4.4 * k, y: c.y - 3 * k, width: 8.8 * k, height: 6 * k)
                ctx.fill(Path(roundedRect: can, cornerRadius: 1.8 * k), with: .color(item.color))
                ctx.stroke(Path(roundedRect: can, cornerRadius: 1.8 * k), with: .color(PS.surface), lineWidth: 0.8)
                ctx.stroke(Path(roundedRect: can.insetBy(dx: 1.5 * k, dy: 1.4 * k), cornerRadius: 0.8 * k), with: .color(PS.surface), lineWidth: 0.7)
            case .alert:
                // "!" and a circled i on an amber pill, on the limb (1.9).
                let w = 21 * k, h = 11.5 * k
                let pill = Path(roundedRect: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), cornerRadius: h / 2)
                ctx.fill(pill, with: .color(item.color))
                ctx.stroke(pill, with: .color(PS.surface), lineWidth: 1.2)
                ctx.draw(Text("!").font(.system(size: max(8, 8.4 * k), weight: .heavy)).foregroundColor(DiagramColor.limbAlertInk),
                         at: CGPoint(x: c.x - 5 * k, y: c.y))
                var info = ctx.resolve(Image(systemName: "info.circle"))
                info.shading = .color(DiagramColor.limbAlertInk)
                let d = max(6.4, 7.2 * k)
                ctx.draw(info, in: CGRect(x: c.x + 1.4 * k, y: c.y - d / 2, width: d, height: d))
            case .none:
                break
            }
            let font = Font.system(size: Self.fontSize(k), weight: .semibold)
            if !item.label.isEmpty {
                if let la = item.labelAt {
                    // A leader from the insertion point to the label in its column.
                    let end = CGPoint(x: la.x * k + (item.labelLeft ? 1.5 : -1.5) * k, y: la.y * k)
                    var leader = Path()
                    leader.move(to: c)
                    leader.addLine(to: CGPoint(x: (item.labelLeft ? min(c.x, end.x + 6 * k) : max(c.x, end.x - 6 * k)), y: end.y))
                    leader.addLine(to: end)
                    ctx.stroke(leader, with: .color(item.color.opacity(0.55)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round, lineJoin: .round))
                    ctx.draw(Text(item.label).font(font).foregroundColor(item.color), at: CGPoint(x: la.x * k, y: la.y * k), anchor: item.labelLeft ? .trailing : .leading)
                } else {
                    let lp = CGPoint(x: c.x + (item.labelLeft ? -5 : 5) * k, y: c.y + item.labelDY * k)
                    ctx.draw(Text(item.label).font(font).foregroundColor(item.color), at: lp, anchor: item.labelLeft ? .trailing : .leading)
                }
            }
        }
    }
}
