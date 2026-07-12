import Foundation

/// Platform-independent theme description (hex colors).
public struct ThemeSpec: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let background: String
    public let text: String
    public let secondaryText: String
    public let accent: String
    public let good: String
    public let bad: String
    public let pet: String

    public init(id: String, name: String, background: String, text: String,
                secondaryText: String, accent: String, good: String, bad: String, pet: String) {
        self.id = id
        self.name = name
        self.background = background
        self.text = text
        self.secondaryText = secondaryText
        self.accent = accent
        self.good = good
        self.bad = bad
        self.pet = pet
    }

    public static let presets: [ThemeSpec] = [
        ThemeSpec(id: "midnight", name: "Midnight",
                  background: "#101014", text: "#F2F2F7", secondaryText: "#98989D",
                  accent: "#0A84FF", good: "#30D158", bad: "#FF453A", pet: "#64D2FF"),
        ThemeSpec(id: "matrix", name: "Matrix",
                  background: "#050B06", text: "#B7FFC9", secondaryText: "#3FA34D",
                  accent: "#00FF66", good: "#00FF66", bad: "#FF3B30", pet: "#00FF66"),
        ThemeSpec(id: "sunset", name: "Neon Sunset",
                  background: "#1C1023", text: "#FFE3D3", secondaryText: "#C98F9A",
                  accent: "#FF6B9D", good: "#32D74B", bad: "#FF375F", pet: "#FF9F0A"),
        ThemeSpec(id: "ocean", name: "Ocean",
                  background: "#0A1622", text: "#D9F3FF", secondaryText: "#6FA8C7",
                  accent: "#64D2FF", good: "#34C759", bad: "#FF6961", pet: "#5AC8FA"),
        ThemeSpec(id: "mono", name: "Mono",
                  background: "#000000", text: "#FFFFFF", secondaryText: "#8E8E93",
                  accent: "#FFFFFF", good: "#FFFFFF", bad: "#FFFFFF", pet: "#FFFFFF"),
    ]
}

public enum HexColor {
    /// Accepts "#RRGGBB", "RRGGBB", "#RGB", "#RRGGBBAA". Falls back to gray.
    public static func parse(_ hex: String) -> (r: Double, g: Double, b: Double, a: Double) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        guard !s.isEmpty, Scanner(string: s).scanHexInt64(&v) else {
            return (0.5, 0.5, 0.5, 1)
        }
        switch s.count {
        case 8:
            return (Double((v >> 24) & 0xFF) / 255,
                    Double((v >> 16) & 0xFF) / 255,
                    Double((v >> 8) & 0xFF) / 255,
                    Double(v & 0xFF) / 255)
        case 6:
            return (Double((v >> 16) & 0xFF) / 255,
                    Double((v >> 8) & 0xFF) / 255,
                    Double(v & 0xFF) / 255,
                    1)
        case 3:
            let r = Double((v >> 8) & 0xF)
            let g = Double((v >> 4) & 0xF)
            let b = Double(v & 0xF)
            return (r * 17 / 255, g * 17 / 255, b * 17 / 255, 1)
        default:
            return (0.5, 0.5, 0.5, 1)
        }
    }

    public static func format(r: Double, g: Double, b: Double) -> String {
        func clamp(_ x: Double) -> Int { Swift.max(0, Swift.min(255, Int((x * 255).rounded()))) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}
