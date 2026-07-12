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

    /// 6120s -> "1:42" (h:mm until reset). Negative intervals clamp to "0:00".
    public static func remaining(_ interval: TimeInterval) -> String {
        let total = Swift.max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }

    /// 0.623 -> "62%". Values above 9.99 are capped at "999%".
    public static func percent(_ fraction: Double) -> String {
        let pct = Swift.max(0, Swift.min(fraction, 9.99)) * 100
        return String(format: "%.0f%%", pct)
    }

    /// "claude-sonnet-5-20250929" -> "sonnet-5"
    public static func shortModel(_ model: String) -> String {
        var m = model.replacingOccurrences(of: "claude-", with: "")
        let parts = m.split(separator: "-")
        if let last = parts.last, last.count == 8, Int(last) != nil {
            m = parts.dropLast().joined(separator: "-")
        }
        return m
    }
}
