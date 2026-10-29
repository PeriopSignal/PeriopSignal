import SwiftUI
import UIKit

// The regional anesthesia tools: the Regional Technique Finder (mark the operative area on a body figure), the
// Peripheral Nerve Blocks reference (original placement and ultrasound schematics, volumes, NYSORA links) and the
// Neuraxial Guide (level, technique and dose by procedure). Content: reference.json "regional"; rules: RegionalCalc.
// The website has the same tools (src/reference-regional.js).

// MARK: - Body figure

struct RegionalFigureView: View {
    var figure: RegionalFigure
    var view: String
    var selected: Set<String> = []
    /// Called with a region key while painting; nil makes the figure static.
    var onPaint: ((String, Bool) -> Void)? = nil
    var probe: RegionalProbe? = nil
    var shadeFrom: Double? = nil
    var saddle = false
    var levels: [(String, Double)] = []
    var showSides = true

    @State private var painting: Bool? = nil   // true: marking, false: clearing

    private static let arms: Set<String> = ["shoulder", "upper-arm", "forearm", "hand"]

    private var bw: Double { figure.box.first ?? 200 }
    private var bh: Double { figure.box.count > 1 ? figure.box[1] : 420 }

    var body: some View {
        GeometryReader { geo in
            let k: Double = min(Double(geo.size.width) / bw, Double(geo.size.height) / bh)
            let ox: Double = (Double(geo.size.width) - bw * k) / 2
            Canvas { ctx, _ in draw(&ctx, k: k, ox: ox) }
                .contentShape(Rectangle())
                .gesture(paint(k: k, ox: ox), including: onPaint == nil ? GestureMask.none : GestureMask.all)
        }
        .aspectRatio(CGFloat(bw / bh), contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(onPaint == nil ? Text("Body figure") : Text("Body figure, \(view) view: drag to mark regions"))
    }

    private func paint(k: Double, ox: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let p = CGPoint(x: (Double(g.location.x) - ox) / k, y: Double(g.location.y) / k)
                guard let key = hit(p) else { return }
                if painting == nil { painting = !selected.contains(key) }
                onPaint?(key, painting ?? true)
            }
            .onEnded { _ in painting = nil }
    }

    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ k: Double) -> CGRect {
        CGRect(x: x * k, y: y * k, width: w * k, height: h * k)
    }

    private func draw(_ ctx: inout GraphicsContext, k: Double, ox: Double) {
        ctx.translateBy(x: CGFloat(ox), y: 0)
        let outline = RegionalCalc.path(svg: figure.outline, scale: CGFloat(k))
        let h = figure.head
        let head = Path(ellipseIn: rect(h.cx - h.rx, h.cy - h.ry, h.rx * 2, h.ry * 2, k))
        var bodyPath = outline
        bodyPath.addPath(head)
        ctx.fill(bodyPath, with: .color(PS.surface2))
        let shade = PS.accent2.opacity(0.42)
        ctx.drawLayer { layer in
            layer.clip(to: bodyPath)
            if let y0 = shadeFrom {
                layer.fill(Path(rect(0, y0, bw, bh - y0, k)), with: .color(shade))
                for r in figure.regions where Self.arms.contains(r.id) {
                    for poly in r.views[view] ?? [] { layer.fill(RegionalCalc.polygon(poly, scale: CGFloat(k)), with: .color(PS.surface2)) }
                }
            }
            if saddle, let per = figure.regions.first(where: { $0.id == "perineum" }) {
                for poly in per.views[view] ?? [] { layer.fill(RegionalCalc.polygon(poly, scale: CGFloat(k)), with: .color(shade)) }
            }
            for r in figure.regions {
                let polys = r.views[view] ?? []
                for (i, poly) in polys.enumerated() {
                    let key = r.id + ":" + RegionalCalc.side(view: view, index: i, count: polys.count)
                    guard selected.contains(key) else { continue }
                    let p = RegionalCalc.polygon(poly, scale: CGFloat(k))
                    layer.fill(p, with: .color(PS.accent.opacity(0.58)))
                    layer.stroke(p, with: .color(PS.accent.opacity(0.85)), lineWidth: 0.6)
                }
            }
        }
        ctx.stroke(outline, with: .color(PS.fg3), lineWidth: 1.1)
        ctx.stroke(head, with: .color(PS.fg3), lineWidth: 1.1)
        for lm in figure.landmarks[view] ?? [] {
            if lm.kind == "dot", let x = lm.x, let y = lm.y {
                ctx.fill(Path(ellipseIn: CGRect(x: x * k - 1.7, y: y * k - 1.7, width: 3.4, height: 3.4)), with: .color(PS.fg3))
            } else if let pts = lm.pts, let f = pts.first, f.count >= 2 {
                var p = Path()
                p.move(to: CGPoint(x: f[0] * k, y: f[1] * k))
                for q in pts.dropFirst() where q.count >= 2 { p.addLine(to: CGPoint(x: q[0] * k, y: q[1] * k)) }
                ctx.stroke(p, with: .color(PS.fg3.opacity(0.8)), style: StrokeStyle(lineWidth: 0.7, dash: [2, 2]))
            }
        }
        let levelFont = Font.system(size: CGFloat(max(8, 7 * k)), weight: .semibold, design: .monospaced)
        for (lv, y) in levels {
            var p = Path()
            p.move(to: CGPoint(x: 62 * k, y: y * k))
            p.addLine(to: CGPoint(x: 138 * k, y: y * k))
            ctx.stroke(p, with: .color(PS.fg2), style: StrokeStyle(lineWidth: 0.6, dash: [1.5, 2]))
            ctx.draw(Text(lv).font(levelFont).foregroundColor(PS.fg2), at: CGPoint(x: 141 * k, y: y * k), anchor: .leading)
        }
        if let pr = probe, pr.view == view {
            let len: Double = (pr.len ?? 26) * k
            var pc = ctx
            pc.translateBy(x: CGFloat(pr.x * k), y: CGFloat(pr.y * k))
            pc.rotate(by: .degrees(pr.angle ?? 0))
            pc.fill(Path(roundedRect: CGRect(x: -len / 2, y: -4 * k, width: len, height: 8 * k), cornerRadius: CGFloat(3 * k)), with: .color(PS.accent))
            let rr: Double = len / 2 + 7 * k
            ctx.stroke(Path(ellipseIn: CGRect(x: pr.x * k - rr, y: pr.y * k - rr, width: rr * 2, height: rr * 2)),
                       with: .color(PS.accent.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }
        if showSides {
            let sideFont = Font.system(size: 11, weight: .bold, design: .monospaced)
            let left = view == "back" ? "L" : "R", right = view == "back" ? "R" : "L"
            ctx.draw(Text(left).font(sideFont).foregroundColor(PS.fg3), at: CGPoint(x: 12 * k, y: 22 * k), anchor: .leading)
            ctx.draw(Text(right).font(sideFont).foregroundColor(PS.fg3), at: CGPoint(x: (bw - 12) * k, y: 22 * k), anchor: .trailing)
        }
    }

    /// The region key under a point in figure coordinates (inside the outline only).
    private func hit(_ p: CGPoint) -> String? {
        let outline = RegionalCalc.path(svg: figure.outline)
        guard outline.contains(p) else { return nil }
        for r in figure.regions {
            let polys = r.views[view] ?? []
            for (i, poly) in polys.enumerated() where RegionalCalc.polygon(poly, scale: 1).contains(p) {
                return r.id + ":" + RegionalCalc.side(view: view, index: i, count: polys.count)
            }
        }
        return nil
    }
}

// MARK: - Ultrasound schematic

struct SonoView: View {
    var spec: SonoSpec

    private static let W = 160.0, H = 100.0

    var body: some View {
        Canvas { ctx, size in draw(&ctx, k: Double(size.width) / Self.W) }
            .aspectRatio(1.6, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Ultrasound schematic"))
    }

    private struct Mark { var at: CGPoint; var text: String; var anchor: UnitPoint }

    private func draw(_ ctx: inout GraphicsContext, k: Double) {
        let W = Self.W, H = Self.H
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * k, y: y * k) }
        func E(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
            Path(ellipseIn: CGRect(x: (cx - rx) * k, y: (cy - ry) * k, width: rx * 2 * k, height: ry * 2 * k))
        }
        func line(_ pts: [[Double]]) -> Path {
            var p = Path()
            guard let f = pts.first, f.count >= 2 else { return p }
            p.move(to: P(f[0], f[1]))
            for q in pts.dropFirst() where q.count >= 2 { p.addLine(to: P(q[0], q[1])) }
            return p
        }
        let curved = spec.kind == "curved"
        let field: Path = curved ? line([[30, 0], [130, 0], [W, H], [0, H], [30, 0]]) : Path(CGRect(x: 0, y: 0, width: W * k, height: H * k))
        ctx.clip(to: field)
        ctx.fill(field, with: .linearGradient(Gradient(colors: [Color(hex: "2B3036"), Color(hex: "121417")]), startPoint: .zero, endPoint: P(0, H)))
        var labels: [Mark] = []
        for it in spec.items {
            let x = it.x ?? 0, y = it.y ?? 0
            switch it.t {
            case "band":
                let hh = it.h ?? 10
                let band = Path(roundedRect: CGRect(x: -2 * k, y: y * k, width: (W + 4) * k, height: hh * k), cornerRadius: CGFloat(3 * k))
                ctx.fill(band, with: .color(Color(hex: "4A5058").opacity(0.85)))
                if let l = it.label, !l.isEmpty { labels.append(Mark(at: P(4, y + hh / 2), text: l, anchor: .leading)) }
            case "muscle":
                let m = E(x, y, it.rx ?? 10, it.ry ?? 6)
                ctx.fill(m, with: .color(Color(hex: "4F565F")))
                ctx.stroke(m, with: .color(Color(hex: "7D858F")), lineWidth: 0.6)
                if let l = it.label, !l.isEmpty { labels.append(Mark(at: P(x, y), text: l, anchor: .center)) }
            case "fascia":
                if let pts = it.pts, let last = pts.last, last.count >= 2 {
                    ctx.stroke(line(pts), with: .color(Color(hex: "C9CED4")), style: StrokeStyle(lineWidth: CGFloat(1.4 * k), lineCap: .round))
                    if let l = it.label, !l.isEmpty { labels.append(Mark(at: P(last[0], last[1] - 4), text: l, anchor: .trailing)) }
                }
            case "bone":
                let x1 = it.x1 ?? 0, x2 = it.x2 ?? W
                ctx.fill(Path(CGRect(x: x1 * k, y: y * k, width: (x2 - x1) * k, height: (H - y) * k)), with: .color(Color(hex: "08090A").opacity(0.9)))
                ctx.stroke(line([[x1, y], [x2, y]]), with: .color(Color(hex: "F1F3F5")), style: StrokeStyle(lineWidth: CGFloat(2.2 * k), lineCap: .round))
                if let l = it.label, !l.isEmpty { labels.append(Mark(at: P((x1 + x2) / 2, y + 8), text: l, anchor: .center)) }
            case "pleura":
                let x1 = it.x1 ?? 0, x2 = it.x2 ?? W
                ctx.stroke(line([[x1, y], [x2, y]]), with: .color(Color(hex: "E7EBEF")), lineWidth: CGFloat(1.6 * k))
                ctx.fill(Path(CGRect(x: x1 * k, y: (y + 2) * k, width: (x2 - x1) * k, height: (H - y) * k)), with: .color(Color(hex: "6B7280").opacity(0.25)))
                if let l = it.label, !l.isEmpty { labels.append(Mark(at: P((x1 + x2) / 2, y + 8), text: l, anchor: .center)) }
            case "artery":
                let r = it.r ?? 6
                ctx.fill(E(x, y, r, r), with: .color(Color(hex: "050506")))
                ctx.stroke(E(x, y, r, r), with: .color(Color(hex: "F2634F")), lineWidth: CGFloat(1.3 * k))
                if let l = it.label, !l.isEmpty { labels.append(Mark(at: P(x, y + r + 6), text: l, anchor: .center)) }
            case "vein":
                let rx = it.rx ?? it.r ?? 6
                let ry = it.ry ?? (it.r ?? 6) * 0.7
                ctx.fill(E(x, y, rx, ry), with: .color(Color(hex: "050506")))
                ctx.stroke(E(x, y, rx, ry), with: .color(Color(hex: "8AB8FF")), lineWidth: CGFloat(1.2 * k))
                if let l = it.label, !l.isEmpty { labels.append(Mark(at: P(x, y + ry + 6), text: l, anchor: .center)) }
            case "nerve":
                let r = it.r ?? 6
                ctx.fill(E(x, y, r, r), with: .color(Color(hex: "25282C")))
                ctx.stroke(E(x, y, r, r), with: .color(Color(hex: "FFD470")), lineWidth: CGFloat(1.3 * k))
                let dots: [[Double]] = r > 5 ? [[-0.35, -0.3], [0.35, -0.3], [0, 0.35], [-0.42, 0.25], [0.42, 0.25]] : [[0, 0]]
                let dr = max(1, r * 0.22)
                for d in dots { ctx.fill(E(x + d[0] * r, y + d[1] * r, dr, dr), with: .color(Color(hex: "0B0C0E"))) }
                if let l = it.label, !l.isEmpty { labels.append(Mark(at: P(x, y - r - 4), text: l, anchor: .center)) }
            case "la":
                ctx.fill(E(x, y, it.rx ?? 10, it.ry ?? 6), with: .color(Color(hex: "43A7FF").opacity(0.32)))
            case "text":
                if let l = it.label, !l.isEmpty {
                    let a: UnitPoint = it.anchor == "start" ? .leading : (it.anchor == "end" ? .trailing : .center)
                    labels.append(Mark(at: P(x, y - 2), text: l, anchor: a))
                }
            default:
                break
            }
        }
        if let n = spec.needle, n.from.count == 2, n.to.count == 2 {
            let x1 = n.from[0], y1 = n.from[1], x2 = n.to[0], y2 = n.to[1]
            let a = atan2(y2 - y1, x2 - x1)
            var p = line([[x1, y1], [x2, y2]])
            p.move(to: P(x2, y2)); p.addLine(to: P(x2 - 6 * cos(a + 0.45), y2 - 6 * sin(a + 0.45)))
            p.move(to: P(x2, y2)); p.addLine(to: P(x2 - 6 * cos(a - 0.45), y2 - 6 * sin(a - 0.45)))
            ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: CGFloat(1.6 * k), lineCap: .round))
        }
        let labelFont = Font.system(size: CGFloat(max(8, 6.5 * k)), weight: .semibold)
        for l in labels {
            ctx.draw(Text(l.text).font(labelFont).foregroundColor(Color(hex: "E9EDF1")), at: l.at, anchor: l.anchor)
        }
        let caption: String = (curved ? "Curvilinear" : "Linear") + " probe · schematic"
        ctx.draw(Text(caption).font(.system(size: CGFloat(max(7, 5.5 * k)))).foregroundColor(Color(hex: "9AA3AD")), at: P(W - 4, H - 4), anchor: .bottomTrailing)
    }
}

// MARK: - Shared pieces

private struct RegionalCard<Content: View>: View {
    var tone: Color? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .overlay(alignment: .top) {
                if let tone {
                    UnevenRoundedRectangle(topLeadingRadius: PS.cardRadius, topTrailingRadius: PS.cardRadius)
                        .fill(tone.opacity(0.9)).frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                }
            }
    }
}

private struct SourcesFooter: View {
    var sources: [EchoSource]
    var notes: [String]
    var onOpen: (URL) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            Eyebrow(text: sources.count > 1 ? "Sources" : "Source")
            ForEach(sources) { s in
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.citation).font(PS.sys(size: 13)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    if let u = s.url, let url = URL(string: u) {
                        Button { onOpen(url) } label: { Text("Open ↗") }.buttonStyle(TextButtonStyle(color: PS.accent, size: 13.5))
                    }
                }
            }
            ForEach(notes, id: \.self) { n in
                Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// An eyebrow label that wraps instead of truncating (region names can be long).
private struct WrapEyebrow: View {
    var text: String
    var color: Color = PS.fg3
    var body: some View {
        Text(text)
            .font(PS.mono(size: 11))
            .textCase(.uppercase)
            .kerning(1.3)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The labelled rows that have content.
private func present(_ pairs: [(String, TextList?)]) -> [(String, [String])] {
    var out: [(String, [String])] = []
    for (k, v) in pairs { if let v, !v.items.isEmpty { out.append((k, v.items)) } }
    return out
}

private func factRows(_ rows: [(String, [String])]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(row.0).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2).frame(width: 96, alignment: .leading)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(row.1.enumerated()), id: \.offset) { _, line in
                        Text(line).font(PS.sys(size: 14)).foregroundStyle(PS.fg).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            if i < rows.count - 1 { Hairline() }
        }
    }
}

/// The block the finder asks the block reference to open.
@MainActor final class RegionalFocus {
    static var block: String?
}

// MARK: - Regional Technique Finder

struct RegionalFinderView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void
    var onOpenBlocks: () -> Void

    @State private var view = LaunchSeed.string("ps.rg.view").isEmpty ? "front" : LaunchSeed.string("ps.rg.view")
    @State private var selected: Set<String> = Set(LaunchSeed.list("ps.rg.sel"))

    private var data: RegionalData? { refs.bundle?.regional }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let d = data {
                    let rec = RegionalCalc.recommend(Array(selected), d)
                    RegionalCard {
                        Text("Tap or drag across the figure to mark the incision or operative area; tap again to clear it. Switch to the back view for the spine, buttocks and the backs of the limbs.")
                            .font(PS.sys(size: 13)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Picker("View", selection: $view) { Text("Front").tag("front"); Text("Back").tag("back") }
                                .pickerStyle(.segmented).frame(width: 180)
                            Spacer()
                            if !selected.isEmpty { Button("Clear") { selected.removeAll() }.buttonStyle(GhostButtonStyle()) }
                        }
                        RegionalFigureView(figure: d.figure, view: view, selected: selected, onPaint: { key, add in
                            if add { selected.insert(key) } else { selected.remove(key) }
                        })
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                        if !rec.items.isEmpty {
                            FlowChips(items: rec.items) { id in selected = selected.filter { !$0.hasPrefix(id + ":") } }
                        }
                    }
                    if rec.items.isEmpty {
                        RegionalCard {
                            Text("Nothing marked yet. The options for each marked area appear here: neuraxial technique and level, and the peripheral blocks NYSORA describes for it.")
                                .font(PS.sys(size: 14)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        if rec.items.count > 1, let top = rec.top {
                            RegionalCard(tone: PS.accent2) {
                                WrapEyebrow(text: "Neuraxial height for everything marked", color: PS.accent2)
                                Text(top.level).font(PS.serif(size: 23, weight: .semibold)).foregroundStyle(PS.fg)
                                Text("The highest level any marked area needs (\(top.region.lowercased())). A spinal or epidural planned for all of them has to reach it.")
                                    .font(PS.sys(size: 14)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        ForEach(rec.items) { it in itemCard(it) }
                    }
                    SourcesFooter(sources: d.sources ?? [], notes: d.finderNotes ?? [], onOpen: onOpen)
                } else {
                    Text("Loading…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                }
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Regional Technique Finder")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func itemCard(_ it: RegionalCalc.Item) -> some View {
        RegionalCard {
            WrapEyebrow(text: it.label)
            if let n = it.neuraxial {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(n.technique ?? "Neuraxial").font(PS.sys(size: 16, weight: .bold)).foregroundStyle(PS.fg)
                    if let lv = n.level { Text("to " + lv).font(PS.mono(size: 14, weight: .semibold)).foregroundStyle(PS.accent2) }
                }
                if let t = n.text { Text(t).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true) }
            } else {
                Text("No neuraxial technique: " + (it.blocks.isEmpty ? "general anesthesia or local infiltration." : "use the blocks below or general anesthesia."))
                    .font(PS.sys(size: 14)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            }
            let prim = it.blocks.filter { $0.role != "alternative" }
            let alt = it.blocks.filter { $0.role == "alternative" }
            if !prim.isEmpty { blockList("Peripheral blocks", prim) }
            if !alt.isEmpty { blockList("Alternatives", alt) }
            if let n = it.note { Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func blockList(_ title: String, _ blocks: [RegionalCalc.BlockOption]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(PS.sys(size: 11, weight: .bold)).kerning(0.6).foregroundStyle(PS.fg3)
            VStack(spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { i, b in
                    Button {
                        RegionalFocus.block = b.id
                        onOpenBlocks()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.name).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                                if let n = b.note { Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < blocks.count - 1 { Hairline().padding(.leading, 12) }
                }
            }
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Removable chips that wrap onto several lines.
private struct FlowChips: View {
    var items: [RegionalCalc.Item]
    var onRemove: (String) -> Void
    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(items) { it in
                HStack(spacing: 4) {
                    Text(it.label).font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg)
                    Button { onRemove(it.id) } label: { Image(systemName: "xmark").font(PS.sys(size: 10, weight: .bold)).foregroundStyle(PS.fg2).frame(width: 20, height: 20) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(it.label)")
                }
                .padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 3)
                .background(PS.accent.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(PS.accent.opacity(0.4), lineWidth: 1))
            }
        }
    }
}

/// A simple wrapping layout for chips.
private struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxW), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Peripheral Nerve Blocks

struct BlocksView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void

    @State private var group = LaunchSeed.string("ps.blk.group")
    @State private var open: String? = LaunchSeed.string("ps.blk.open").isEmpty ? nil : LaunchSeed.string("ps.blk.open")

    private var data: RegionalData? { refs.bundle?.regional }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let d = data {
                        let groups = d.blockGroups ?? []
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(groups) { g in
                                    Button { withAnimation(.snappy) { group = g.id; open = nil } } label: {
                                        Text(g.name).font(PS.sys(size: 14, weight: .semibold))
                                            .foregroundStyle(currentGroup(d) == g.id ? PS.bg : PS.fg2)
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(currentGroup(d) == g.id ? PS.fg : PS.surface, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        VStack(spacing: 0) {
                            let list = d.blocks.filter { $0.group == currentGroup(d) }
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, b in
                                blockRow(d, b).id(b.id)
                                if i < list.count - 1 { Hairline().padding(.leading, 14) }
                            }
                        }
                        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                        SourcesFooter(sources: d.sources ?? [], notes: d.blockNotes ?? [], onOpen: onOpen)
                    } else {
                        Text("Loading…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 30)
            }
            .onAppear {
                if let f = RegionalFocus.block, let b = data?.blocks.first(where: { $0.id == f }) {
                    group = b.group; open = b.id; RegionalFocus.block = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { withAnimation { proxy.scrollTo(b.id, anchor: .top) } }
                }
            }
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Peripheral Nerve Blocks")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func currentGroup(_ d: RegionalData) -> String {
        let groups = d.blockGroups ?? []
        return groups.contains(where: { $0.id == group }) ? group : (groups.first?.id ?? "")
    }

    @ViewBuilder private func blockRow(_ d: RegionalData, _ b: RegionalBlock) -> some View {
        let isOpen = open == b.id
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.snappy) { open = isOpen ? nil : b.id } } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.name).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg).multilineTextAlignment(.leading)
                        if let s = b.summary { Text(s).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true) }
                    }
                    Spacer()
                    Image(systemName: isOpen ? "minus" : "plus").font(PS.sys(size: 13, weight: .bold)).foregroundStyle(PS.fg3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Collapses the block" : "Shows the technique")
            if isOpen {
                if let art = b.art {
                    HStack(alignment: .center, spacing: 10) {
                        if let pr = art.probe {
                            RegionalFigureView(figure: d.figure, view: pr.view, probe: pr, showSides: false).frame(width: 96)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            if let sono = art.sono { SonoView(spec: sono) }
                            if let c = art.caption { Text(c).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                }
                factRows(present([("Indications", b.indications), ("Coverage", b.coverage), ("Position", b.position), ("Probe and needle", b.equipment),
                                  ("Technique", b.target), ("Volume and dose", b.volume), ("Onset and duration", b.onset), ("Cautions", b.cautions), ("Tips", b.tips)]))
                if let u = b.url, let url = URL(string: u) {
                    Button { onOpen(url) } label: { Text("NYSORA technique page ↗") }.buttonStyle(TextButtonStyle(color: PS.accent, size: 13.5))
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

// MARK: - Neuraxial Guide

struct NeuraxialGuideView: View {
    @Environment(ReferenceStore.self) private var refs
    var onOpen: (URL) -> Void

    @State private var proc = LaunchSeed.string("ps.nx.proc")

    private var data: RegionalData? { refs.bundle?.regional }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let d = data, let n = d.neuraxial {
                    let p = n.procedures.first(where: { $0.id == proc }) ?? n.procedures.first
                    RegionalCard {
                        Menu {
                            ForEach(n.procedures) { x in
                                Button { proc = x.id } label: { if x.id == p?.id { Label(x.name, systemImage: "checkmark") } else { Text(x.name) } }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Eyebrow(text: "Procedure")
                                    Text(p?.name ?? "").font(PS.serif(size: 18)).foregroundStyle(PS.fg).multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg3)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    if let p {
                        let y = RegionalCalc.y(forLevel: p.level)
                        let saddle = (p.level ?? "").uppercased().hasPrefix("S")
                        let marks: [(String, Double)] = (n.dermatomes ?? []).compactMap { x in
                            guard x.level != "S1", let yy = RegionalCalc.y(forLevel: x.level) else { return nil }
                            return (x.level, yy)
                        }
                        RegionalCard(tone: PS.accent2) {
                            Eyebrow(text: "Target sensory level", color: PS.accent2)
                            Text(p.level ?? "—").font(PS.serif(size: 26, weight: .semibold)).foregroundStyle(PS.fg)
                            if let t = p.levelText { Text(t).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true) }
                            RegionalFigureView(figure: d.figure, view: "front", shadeFrom: saddle ? nil : y, saddle: saddle, levels: marks, showSides: false)
                                .frame(maxWidth: 190).frame(maxWidth: .infinity)
                            factRows(present([("Technique", p.technique), ("Insertion", p.insertion), ("Spinal", p.spinal), ("Epidural", p.epidural), ("Adjuvants", p.adjuvants), ("Notes", p.notes)]))
                        }
                    }
                    ForEach(Array((n.tables ?? []).enumerated()), id: \.offset) { _, t in
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: t.title).padding(.leading, 2)
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(t.rows.enumerated()), id: \.offset) { i, row in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(row.first ?? "").font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                                        ForEach(Array(row.dropFirst().enumerated()), id: \.offset) { j, cell in
                                            if !cell.isEmpty {
                                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                    Text(t.columns.count > j + 1 ? t.columns[j + 1] : "").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3).frame(width: 90, alignment: .leading)
                                                    Text(cell).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    if i < t.rows.count - 1 { Hairline().padding(.leading, 14) }
                                }
                            }
                            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                            ForEach(t.notes ?? [], id: \.self) { x in Text(x).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                    SourcesFooter(sources: n.sources ?? d.sources ?? [], notes: n.notes ?? [], onOpen: onOpen)
                } else {
                    Text("Loading…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                }
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Neuraxial Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}
