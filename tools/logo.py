#!/usr/bin/env python3
"""Periop Signal mark: ECG, arterial line and CVP traces, stacked, three cardiac cycles.

wide_svg(color)  -> inline SVG for the header (viewBox 0 0 120 48, 2.5:1)
square_svg(pad)  -> 512x512 app icon (two cycles per trace); pad = extra safe margin fraction (maskable icons)
"""

def ecg(x0, base, cyc):
    w = cyc / 30.0
    return (f"M{x0:.2f} {base:.2f}"
            f"h{3.5*w:.2f}"
            f"c{0.8*w:.2f} -1.7 {2.2*w:.2f} -1.7 {3*w:.2f} 0"                       # P
            f"h{2.5*w:.2f}"
            f"l{1*w:.2f} 1.3 l{1.5*w:.2f} -9.8 l{1.5*w:.2f} 11.6 l{1*w:.2f} -3.1"      # QRS
            f"h{2.5*w:.2f}"
            f"c{1.2*w:.2f} -3.4 {3.4*w:.2f} -3.4 {4.6*w:.2f} 0"                    # T
            f"h{9*w:.2f}")

def art(x0, base, cyc):
    w = cyc / 30.0
    return (f"M{x0:.2f} {base:.2f}"
            f"c{1.2*w:.2f} 0 {2.6*w:.2f} -9.5 {4.6*w:.2f} -9.5"                    # systolic upstroke to peak
            f"c{1.4*w:.2f} 0 {2.2*w:.2f} 4.8 {3.8*w:.2f} 5.6"                      # decline to dicrotic notch
            f"c{0.5*w:.2f} -0.9 {1.3*w:.2f} -0.9 {1.9*w:.2f} -0.2"                 # dicrotic shoulder
            f"c{3.5*w:.2f} 2.4 {11*w:.2f} 4.1 {19.7*w:.2f} 4.1")                   # diastolic runoff

def cvp(x0, base, cyc):
    w = cyc / 30.0
    return (f"M{x0:.2f} {base:.2f}"
            f"c{1.8*w:.2f} -4.4 {4.2*w:.2f} -4.4 {6*w:.2f} 0"                      # a wave
            f"c{1.2*w:.2f} -1.8 {2.4*w:.2f} -1.8 {3.6*w:.2f} 0"                    # c wave
            f"h{2.4*w:.2f}"                                                        # x descent
            f"c{2*w:.2f} -3.2 {4.4*w:.2f} -3.2 {6.4*w:.2f} 0"                      # v wave
            f"h{11.6*w:.2f}")                                                      # y descent

def traces(width, bases, cycles, pad_x, stroke, color="#fff"):
    cyc = (width - 2 * pad_x) / cycles
    out = []
    for fn, base in zip((ecg, art, cvp), bases):
        d = "".join(fn(pad_x + i * cyc, base, cyc) for i in range(cycles))
        out.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round"/>')
    return "\n".join(out)

def wide_svg(color="#fff"):
    return (f'<svg viewBox="0 0 120 48" aria-hidden="true">\n'
            f'{traces(120, (13.5, 29.5, 42.5), 3, 7, 2.4, color)}\n</svg>')

def square_svg(pad=0.0):
    size = 512
    inner = size * (1 - 2 * pad)
    off = size * pad
    rx = 0 if pad > 0 else 112
    grad = '<defs><linearGradient id="lg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FF7A66"/><stop offset="1" stop-color="#D9472F"/></linearGradient></defs>'
    s = inner / 96.0
    body = traces(96, (26, 56, 82), 2, 11, 4.2)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}">{grad}'
            f'<rect width="{size}" height="{size}" rx="{rx}" fill="url(#lg)"/>'
            f'<g transform="translate({off:.1f} {off:.1f}) scale({s:.4f})">{body}</g></svg>')

if __name__ == "__main__":
    import sys
    kind = sys.argv[1] if len(sys.argv) > 1 else "wide"
    print(wide_svg() if kind == "wide" else square_svg(float(sys.argv[2]) if len(sys.argv) > 2 else 0.0))
