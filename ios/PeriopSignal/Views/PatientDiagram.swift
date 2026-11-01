import SwiftUI

// MARK: - The patient diagram
//
// A front-view figure (the Regional Technique Finder's outline) with the airway, lines and devices drawn on it, each
// with a tiny colored label. The drawing works in the figure's own 200 × 420 units, widened on both sides for the
// labels and the ECMO cart; PatientDiagramModel turns the record into the items drawn here.

/// One thing drawn on the patient: a marker at its insertion point, an optional course (a central line to the cava,
/// a cannula to the ECMO cart, a balloon up the aorta) and a label.
struct DiagramItem: Identifiable, Hashable {
    enum Marker: Hashable { case dot, square, pump, needle, stoma, none }

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

    static func == (a: DiagramItem, b: DiagramItem) -> Bool {
        a.id == b.id && a.anchor == b.anchor && a.course == b.course && a.label == b.label && a.marker == b.marker && a.pumpAt == b.pumpAt
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
}

struct PatientDiagramCanvas: View {
    var figure: RegionalFigure
    var items: [DiagramItem]
    var cart: DiagramCart?
    /// Edit mode: the markers jiggle, drag to move, × to delete.
    var editing = false
    var onTapFigure: ((CGPoint) -> Void)? = nil
    var onTapItem: ((String) -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    var onMove: ((String, CGSize) -> Void)? = nil
    var onDelete: ((String) -> Void)? = nil

    /// Figure units of margin on each side for labels and the cart.
    static let margin: CGFloat = 38
    @State private var drag: (id: String, by: CGSize)?
    @State private var wiggle = false

    private var bw: CGFloat { CGFloat(figure.box.first ?? 200) }
    private var bh: CGFloat { CGFloat(figure.box.count > 1 ? figure.box[1] : 420) }

    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width / (bw + 2 * Self.margin), geo.size.height / bh)
            let ox = (geo.size.width - (bw + 2 * Self.margin) * k) / 2 + Self.margin * k
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in draw(&ctx, k: k, ox: ox) }
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { g in
                        guard !editing else { return }
                        onTapFigure?(CGPoint(x: (g.location.x - ox) / k, y: g.location.y / k))
                    }, including: onTapFigure == nil ? .none : .all)
                    .onLongPressGesture(minimumDuration: 0.5) { onLongPress?() }
                ForEach(items.filter(\.movable)) { item in
                    marker(item, k: k, ox: ox)
                }
            }
        }
        .aspectRatio((bw + 2 * Self.margin) / bh, contentMode: .fit)
        .onChange(of: editing) { _, on in wiggle = on }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Patient diagram: " + (items.isEmpty ? "no lines or devices" : items.map(\.label).joined(separator: ", ")))
    }

    // MARK: Markers (the touch targets)

    private func point(_ p: CGPoint, k: CGFloat, ox: CGFloat) -> CGPoint { CGPoint(x: ox + p.x * k, y: p.y * k) }

    private func moved(_ item: DiagramItem) -> CGPoint {
        guard let d = drag, d.id == item.id else { return item.anchor }
        return CGPoint(x: item.anchor.x + d.by.width, y: item.anchor.y + d.by.height)
    }

    private func marker(_ item: DiagramItem, k: CGFloat, ox: CGFloat) -> some View {
        let at = point(moved(item), k: k, ox: ox)
        let size: CGFloat = 30
        return ZStack(alignment: .topTrailing) {
            Circle().fill(Color.clear).frame(width: size, height: size).contentShape(Circle())
            if editing {
                Button { onDelete?(item.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, PS.fg2)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel("Delete \(item.label)")
            }
        }
        .rotationEffect(.degrees(editing ? (wiggle ? 4 : -4) : 0))
        .animation(editing ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true) : .default, value: wiggle)
        .position(at)
        .onTapGesture { if !editing { onTapItem?(item.id) } }
        .onLongPressGesture(minimumDuration: 0.5) { onLongPress?() }
        .gesture(DragGesture(minimumDistance: 2).onChanged { g in
            guard editing else { return }
            drag = (item.id, CGSize(width: g.translation.width / k, height: g.translation.height / k))
        }.onEnded { g in
            guard editing else { return }
            drag = nil
            onMove?(item.id, CGSize(width: g.translation.width / k, height: g.translation.height / k))
        }, including: editing ? .all : .none)
        .accessibilityElement()
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(.isButton)
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
                ctx.stroke(p, with: .color(item.color), style: StrokeStyle(lineWidth: item.width * max(1, k * 0.9), lineCap: .round, lineJoin: .round, dash: item.dashed ? [3, 2.5] : []))
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
            case .none:
                break
            }
            let font = Font.system(size: max(7, 5.6 * k), weight: .semibold)
            if !item.label.isEmpty {
                let lp = CGPoint(x: c.x + (item.labelLeft ? -5 : 5) * k, y: c.y + item.labelDY * k)
                ctx.draw(Text(item.label).font(font).foregroundColor(item.color), at: lp, anchor: item.labelLeft ? .trailing : .leading)
            }
        }
    }
}
