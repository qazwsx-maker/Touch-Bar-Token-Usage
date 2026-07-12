import Foundation

public enum Fmt {
    /// 999 -> "999", 1200 -> "1.2K", 1280000 -> "1.28M"
    public static func abbrev(_ n: Int) -> String {
        func trimmed(_ s: String) -> String {
            var s = s
            if s.contains(".") {
                while s.hasSuffix("0") { s.removeLast() }
                if s.hasSuffix(".") { s.removeLast() }
            }
            return s
        }
        let v = Double(n)
        switch abs(n) {
        case 0..<1000:
            return "\(n)"
        case 1000..<1_000_000:
            return trimmed(String(format: "%.1f", v / 1000)) + "K"
        case 1_000_000..<1_000_000_000:
            return trimmed(String(format: "%.2f", v / 1_000_000)) + "M"
        default:
            return trimmed(String(format: "%.2f", v / 1_000_000_000)) + "B"
        }
    }

    public static func money(_ v: Double) -> String {
        if v >= 1000 { return String(format: "$%.0f", v) }
        return String(format: "$%.2f", v)
    }

    public static func rate(_ perMinute: Double) -> String {
        if perMinute < 1 { return "idle" }
        return abbrev(Int(perMinute)) + "/m"
    }

    /// Last `components` path components: "/a/b/c/d.txt" -> "c/d.txt"
    public static func shortPath(_ path: String, components: Int = 2) -> String {
        let parts = path.split(separator: "/").suffix(components)
        if parts.isEmpty { return path }
        return parts.joined(separator: "/")
    }

    public static func truncate(_ s: String, max: Int) -> String {
        guard max > 1, s.count > max else { return s }
        return String(s.prefix(max - 1)) + "…"
    }
}
