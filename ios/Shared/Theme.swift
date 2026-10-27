import SwiftUI
import UIKit

extension Color {
    /// Hex colour ("#RRGGBB" or "RRGGBB"), optional alpha.
    init(hex: String, alpha: Double = 1) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// A colour that follows the interface style: dark value first, light second.
    static func dynamic(dark: String, light: String) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

/// The site's design tokens (dark-first, with the light theme as the alternate).
enum PS {
    static let bg = Color.dynamic(dark: "0A0E14", light: "F3F5F9")
    static let surface = Color.dynamic(dark: "111722", light: "FFFFFF")
    static let surface2 = Color.dynamic(dark: "18202D", light: "EEF1F6")
    static let surface3 = Color.dynamic(dark: "212B3A", light: "E2E7EF")
    static let fg = Color.dynamic(dark: "ECF0F6", light: "131A24")
    static let fg2 = Color.dynamic(dark: "A9B3C2", light: "4B5666")
    static let fg3 = Color.dynamic(dark: "717D8F", light: "7B8696")
    static let line = Color.dynamic(dark: "1D2634", light: "E1E6ED")
    static let line2 = Color.dynamic(dark: "2C3748", light: "CCD4DE")
    static let accent = Color.dynamic(dark: "F2634F", light: "D9472F")
    static let accentFg = Color.dynamic(dark: "1C0906", light: "FFFFFF")
    static let accent2 = Color.dynamic(dark: "8AB8FF", light: "2460CC")
    static let green = Color.dynamic(dark: "43D68E", light: "1E9D5A")
    static let coral = Color(hex: "F2634F")
    static let coralDeep = Color(hex: "D9472F")
    static let coralLight = Color(hex: "FF7A66")
    static let blueGlow = Color(hex: "7AAAFF")

    static let logoGradient = LinearGradient(colors: [coralLight, coralDeep], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// In-app text size multiplier (More › Text size). The widget never changes it, so it stays 1.
    nonisolated(unsafe) static var textScale: CGFloat = 1

    /// System font at a design size, scaled by the in-app text size. App views use this instead of
    /// `.system(size:)` so one setting resizes everything.
    static func sys(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: (size * textScale).rounded(toPlaces: 1), weight: weight, design: design)
    }
}

extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let p = pow(10, CGFloat(places))
        return (self * p).rounded() / p
    }
}

struct TopicInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let fg: Color
    let bg: Color
}

enum Topics {
    static let all: [TopicInfo] = [
        .init(id: "cardiac", name: "Cardiac", fg: Color.dynamic(dark: "FF9A95", light: "B4262A"), bg: Color.dynamic(dark: "3A1C1E", light: "FBE4E4")),
        .init(id: "cardiacSurgery", name: "Cardiac surgery", fg: Color.dynamic(dark: "F79AC0", light: "A8215A"), bg: Color.dynamic(dark: "3A192A", light: "FBE2EC")),
        .init(id: "mcs", name: "MCS · LVAD · ECMO", fg: Color.dynamic(dark: "FFAE82", light: "B8430E"), bg: Color.dynamic(dark: "3A2417", light: "FDE6DA")),
        .init(id: "echo", name: "Echo · TEE", fg: Color.dynamic(dark: "99BFFF", light: "1C5BC9"), bg: Color.dynamic(dark: "172842", light: "E1EAFB")),
        .init(id: "thoracic", name: "Thoracic", fg: Color.dynamic(dark: "74DCE6", light: "0E7580"), bg: Color.dynamic(dark: "113236", light: "DBF2F4")),
        .init(id: "regional", name: "Regional", fg: Color.dynamic(dark: "98E49C", light: "2B7A30"), bg: Color.dynamic(dark: "17331D", light: "E0F2E1")),
        .init(id: "ob", name: "OB", fg: Color.dynamic(dark: "F3AEEA", light: "9B2489"), bg: Color.dynamic(dark: "381536", light: "F7E1F4")),
        .init(id: "trauma", name: "Trauma", fg: Color.dynamic(dark: "FFD470", light: "8F5F00"), bg: Color.dynamic(dark: "362C10", light: "FAEDCB")),
        .init(id: "pediatric", name: "Pediatric", fg: Color.dynamic(dark: "CDE87A", light: "55820A"), bg: Color.dynamic(dark: "253312", light: "EAF4D6")),
        .init(id: "pedsCardiac", name: "Peds cardiac", fg: Color.dynamic(dark: "CDB4FF", light: "6537C8"), bg: Color.dynamic(dark: "271A46", light: "ECE5FA")),
        .init(id: "liver", name: "Liver transplant", fg: Color.dynamic(dark: "E8BC8E", light: "85542A"), bg: Color.dynamic(dark: "362416", light: "F4E8DC")),
        .init(id: "criticalCare", name: "Critical care", fg: Color.dynamic(dark: "ACB4FF", light: "3B4DB0"), bg: Color.dynamic(dark: "1D2145", light: "E4E7F7")),
        .init(id: "general", name: "General", fg: Color.dynamic(dark: "BCC6D3", light: "4A5667"), bg: Color.dynamic(dark: "2A333F", light: "E7EBF0")),
    ]
    static let byID: [String: TopicInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static func info(_ id: String) -> TopicInfo { byID[id] ?? byID["general"]! }
    static func name(_ id: String) -> String { byID[id]?.name ?? id }
}
