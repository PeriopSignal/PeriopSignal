import SwiftUI

/// The Periop Signal mark: ECG, arterial line and CVP traces, two cardiac cycles,
/// on a coral gradient tile. A port of tools/logo.py so the app matches the site.
struct TraceShape: Shape {
    enum Kind { case ecg, art, cvp }
    var kind: Kind
    /// Design-space geometry (viewBox 0 0 72 60, as in the site header).
    static let design = CGSize(width: 72, height: 60)
    static let cycles = 2
    static let padX: CGFloat = 6
    static let bases: [Kind: CGFloat] = [.ecg: 16.5, .art: 36, .cvp: 51]

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / Self.design.width, sy = rect.height / Self.design.height
        let cyc = (Self.design.width - 2 * Self.padX) / CGFloat(Self.cycles)
        let base = Self.bases[kind]!
        var p = Path()
        var cur = CGPoint.zero
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        func move(_ x: CGFloat, _ y: CGFloat) { cur = CGPoint(x: x, y: y); p.move(to: pt(x, y)) }
        func h(_ dx: CGFloat) { cur.x += dx; p.addLine(to: pt(cur.x, cur.y)) }
        func l(_ dx: CGFloat, _ dy: CGFloat) { cur.x += dx; cur.y += dy; p.addLine(to: pt(cur.x, cur.y)) }
        func c(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
            let c1 = pt(cur.x + x1, cur.y + y1), c2 = pt(cur.x + x2, cur.y + y2)
            cur.x += x; cur.y += y
            p.addCurve(to: pt(cur.x, cur.y), control1: c1, control2: c2)
        }
        for i in 0..<Self.cycles {
            let x0 = Self.padX + CGFloat(i) * cyc
            let w = cyc / 30.0
            switch kind {
            case .ecg:
                move(x0, base)
                h(3.5 * w)
                c(0.8 * w, -1.7, 2.2 * w, -1.7, 3 * w, 0)                       // P
                h(2.5 * w)
                l(1 * w, 1.3); l(1.5 * w, -9.8); l(1.5 * w, 11.6); l(1 * w, -3.1) // QRS
                h(2.5 * w)
                c(1.2 * w, -3.4, 3.4 * w, -3.4, 4.6 * w, 0)                     // T
                h(9 * w)
            case .art:
                move(x0, base)
                c(1.2 * w, 0, 2.6 * w, -9.5, 4.6 * w, -9.5)                     // upstroke
                c(1.4 * w, 0, 2.2 * w, 4.8, 3.8 * w, 5.6)                       // to dicrotic notch
                c(0.5 * w, -0.9, 1.3 * w, -0.9, 1.9 * w, -0.2)                  // shoulder
                c(3.5 * w, 2.4, 11 * w, 4.1, 19.7 * w, 4.1)                     // runoff
            case .cvp:
                move(x0, base)
                c(1.8 * w, -4.4, 4.2 * w, -4.4, 6 * w, 0)                       // a
                c(1.2 * w, -1.8, 2.4 * w, -1.8, 3.6 * w, 0)                     // c
                h(2.4 * w)                                                      // x
                c(2 * w, -3.2, 4.4 * w, -3.2, 6.4 * w, 0)                       // v
                h(11.6 * w)                                                     // y
            }
        }
        return p
    }
}

struct LogoMark: View {
    var size: CGFloat = 44
    var cornerRadius: CGFloat? = nil
    var body: some View {
        let r = cornerRadius ?? size * 0.22
        ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous).fill(PS.logoGradient)
            traces
                .padding(size * 0.05)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Periop Signal")
    }
    private var traces: some View {
        let stroke = StrokeStyle(lineWidth: max(1.2, size * 0.036), lineCap: .round, lineJoin: .round)
        return ZStack {
            TraceShape(kind: .ecg).stroke(Color.white, style: stroke)
            TraceShape(kind: .art).stroke(Color.white, style: stroke)
            TraceShape(kind: .cvp).stroke(Color.white, style: stroke)
        }
        .aspectRatio(72.0 / 60.0, contentMode: .fit)
    }
}

/// "Periop" in the foreground colour and "Signal" in coral, heavy rounded type.
struct Wordmark: View {
    var size: CGFloat = 22
    var body: some View {
        HStack(spacing: size * 0.22) {
            Text("Periop").foregroundStyle(PS.fg)
            Text("Signal").foregroundStyle(PS.accent)
        }
        .font(.system(size: size, weight: .heavy, design: .rounded))
        .kerning(-0.5)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

#Preview("Logo") {
    VStack(spacing: 20) {
        LogoMark(size: 44)
        LogoMark(size: 96)
        Wordmark(size: 26)
    }
    .padding()
    .background(PS.bg)
}
