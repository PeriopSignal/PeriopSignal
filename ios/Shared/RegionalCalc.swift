import Foundation
import SwiftUI

// MARK: - Regional technique finder and the body figure's geometry
//
// The figure's regions carry an id and, for paired regions, a side. A selection is a set of "id:side" keys (side R or
// L for paired regions, M for midline ones). Each region maps to its neuraxial options and peripheral blocks in
// reference.json ("regional"). The website runs the same rules (src/reference-logic.js, R.regional).

enum RegionalCalc {
    static let dermatomes = ["C2", "C3", "C4", "C5", "C6", "C7", "C8", "T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T9", "T10", "T11", "T12",
                             "L1", "L2", "L3", "L4", "L5", "S1", "S2", "S3", "S4", "S5"]

    /// Order of a dermatome, head to foot (C2 = 0); -1 when unknown. "T4–T6" ranks by its first level.
    static func rank(_ level: String?) -> Int {
        guard let level, let r = level.uppercased().range(of: "[CTLS][0-9]{1,2}", options: .regularExpression) else { return -1 }
        return dermatomes.firstIndex(of: String(level.uppercased()[r])) ?? -1
    }

    /// Midline M; paired regions are listed viewer's left first: the patient's right on the front, left on the back.
    static func side(view: String, index: Int, count: Int) -> String {
        guard count >= 2 else { return "M" }
        return (view == "back") == (index == 0) ? "L" : "R"
    }

    /// "Right knee", "Both sides: hip", "Perineum and anus".
    static func label(_ name: String, sides: [String]) -> String {
        let lower = name.prefix(1).lowercased() + name.dropFirst()
        let s = sides.filter { $0 != "M" }
        if s.isEmpty { return name }
        if s.count == 2 { return "Both sides: " + lower }
        return (s[0] == "R" ? "Right " : "Left ") + lower
    }

    struct BlockOption: Hashable, Identifiable {
        var id: String
        var name: String
        var role: String
        var note: String?
    }

    struct Item: Hashable, Identifiable {
        var id: String
        var name: String
        var sides: [String]
        var label: String
        var neuraxial: RegionalNeuraxialOption?
        var blocks: [BlockOption]
        var note: String?
    }

    struct Top: Hashable { var level: String; var region: String }

    static func recommend(_ keys: [String], _ d: RegionalData) -> (items: [Item], top: Top?) {
        let order = d.figure.regions.map(\.id)
        var byId: [String: (name: String, sides: [String])] = [:]
        for k in keys {
            let parts = k.split(separator: ":", maxSplits: 1).map(String.init)
            guard let id = parts.first, let reg = d.figure.regions.first(where: { $0.id == id }) else { continue }
            var e = byId[id] ?? (reg.name, [])
            if parts.count > 1, !e.sides.contains(parts[1]) { e.sides.append(parts[1]) }
            byId[id] = e
        }
        let items: [Item] = byId.keys.sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }.map { id in
            let e = byId[id]!
            let m = d.map?[id]
            let blocks: [BlockOption] = (m?.blocks ?? []).compactMap { b in
                guard let blk = d.blocks.first(where: { $0.id == b.id }) else { return nil }
                return BlockOption(id: b.id, name: blk.name, role: b.role ?? "primary", note: b.note)
            }
            let sides = e.sides.sorted { $0 == "R" && $1 != "R" }
            return Item(id: id, name: e.name, sides: sides, label: label(e.name, sides: sides), neuraxial: m?.neuraxial, blocks: blocks, note: m?.note)
        }
        var top: Top?
        for it in items {
            guard let lv = it.neuraxial?.level, rank(lv) >= 0 else { continue }
            if top == nil || rank(lv) < rank(top!.level) { top = Top(level: lv, region: it.name) }
        }
        return (items, top)
    }

    // MARK: Geometry

    /// Dermatome → height on the figure (front view), for the neuraxial shading.
    static let levelY: [String: Double] = ["T2": 84, "T4": 104, "T5": 114, "T6": 122, "T7": 129, "T8": 136, "T9": 143, "T10": 150, "T11": 160, "T12": 170,
                                           "L1": 186, "L2": 232, "L3": 270, "L4": 300, "L5": 350, "S1": 396]
    static func y(forLevel level: String?) -> Double? {
        guard let level, let r = level.uppercased().range(of: "[CTLS][0-9]{1,2}", options: .regularExpression) else { return nil }
        return levelY[String(level.uppercased()[r])]
    }

    /// SVG path data with absolute M, L, C and Z commands, as the figure's outline is written.
    static func path(svg: String, scale: CGFloat = 1, offset: CGPoint = .zero) -> Path {
        var p = Path()
        var nums: [CGFloat] = []
        var cmd: Character = "M"
        func pt(_ i: Int) -> CGPoint { CGPoint(x: nums[i] * scale + offset.x, y: nums[i + 1] * scale + offset.y) }
        func flush() {
            switch cmd {
            case "M": if nums.count >= 2 { p.move(to: pt(0)); var i = 2; while i + 1 < nums.count { p.addLine(to: pt(i)); i += 2 } }
            case "L": var i = 0; while i + 1 < nums.count { p.addLine(to: pt(i)); i += 2 }
            case "C": var i = 0; while i + 5 < nums.count { p.addCurve(to: pt(i + 4), control1: pt(i), control2: pt(i + 2)); i += 6 }
            default: break
            }
            nums = []
        }
        var token = ""
        func endToken() { if let v = Double(token) { nums.append(CGFloat(v)) }; token = "" }
        for ch in svg {
            if ch.isLetter && ch != "e" {
                endToken(); flush()
                if ch == "Z" || ch == "z" { p.closeSubpath() }
                cmd = Character(ch.uppercased())
            } else if ch == " " || ch == "," || ch == "\n" {
                endToken()
            } else if ch == "-" && !token.isEmpty && token.last != "e" {
                endToken(); token = "-"
            } else { token.append(ch) }
        }
        endToken(); flush()
        return p
    }

    static func polygon(_ pts: [[Double]], scale: CGFloat) -> Path {
        var p = Path()
        guard let f = pts.first, f.count >= 2 else { return p }
        p.move(to: CGPoint(x: f[0] * scale, y: f[1] * scale))
        for q in pts.dropFirst() where q.count >= 2 { p.addLine(to: CGPoint(x: q[0] * scale, y: q[1] * scale)) }
        p.closeSubpath()
        return p
    }
}
