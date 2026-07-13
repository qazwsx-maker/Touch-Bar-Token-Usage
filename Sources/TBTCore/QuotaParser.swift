import Foundation

/// One usage window as reported by Claude's OAuth usage endpoint
/// (the same numbers Claude Code shows in /usage).
public struct QuotaWindow: Equatable {
    /// 0…1 fraction of the limit used.
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct Quota: Equatable {
    public let fiveHour: QuotaWindow?
    public let sevenDay: QuotaWindow?

    public init(fiveHour: QuotaWindow?, sevenDay: QuotaWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

/// Defensive parser for `GET https://api.anthropic.com/api/oauth/usage`.
/// Field names and nesting vary across versions, so it searches the whole
/// JSON tree for the window objects and accepts several spellings plus both
/// 0…1 fractions and 0…100 percentages.
public enum QuotaParser {
    // Keys whose *value object* describes each window. Ordered most- to
    // least-specific so "seven_day_all_models" wins over a bare "seven_day".
    private static let fiveKeys = ["five_hour", "fiveHour", "five_hour_limit",
                                   "session", "5h", "five_hour_utilization"]
    private static let sevenKeys = ["seven_day_all_models", "seven_day_overall",
                                    "seven_day", "sevenDay", "seven_day_limit",
                                    "weekly", "week", "7d", "seven_day_utilization"]

    public static func parse(_ data: Data) -> Quota? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) else { return nil }
        let five = firstWindow(under: fiveKeys, in: root)
        let seven = firstWindow(under: sevenKeys, in: root)
        if five == nil && seven == nil { return nil }
        return Quota(fiveHour: five, sevenDay: seven)
    }

    /// Breadth-first search for the first value reachable under any of `keys`
    /// that parses into a window. Handles arbitrary wrapper nesting
    /// (`usage`, `rate_limits`, `data`, …) without hard-coding it.
    private static func firstWindow(under keys: [String], in root: Any) -> QuotaWindow? {
        for key in keys {
            var queue: [Any] = [root]
            var depth = 0
            while !queue.isEmpty && depth < 6 {
                var next: [Any] = []
                for node in queue {
                    if let dict = node as? [String: Any] {
                        if let hit = dict[key], let w = windowValue(hit) {
                            return w
                        }
                        next.append(contentsOf: dict.values)
                    } else if let array = node as? [Any] {
                        next.append(contentsOf: array)
                    }
                }
                queue = next
                depth += 1
            }
        }
        return nil
    }

    /// A window value is either a dict describing utilization/resets, or a bare
    /// number (`"five_hour": 16`).
    private static func windowValue(_ value: Any) -> QuotaWindow? {
        if let dict = value as? [String: Any] {
            return window(from: dict)
        }
        if let n = numeric(value) {
            return QuotaWindow(utilization: normalize(n), resetsAt: nil)
        }
        return nil
    }

    private static func window(from dict: [String: Any]) -> QuotaWindow? {
        var value: Double?
        for key in ["utilization", "utilization_pct", "used_percent", "used_pct",
                    "percent_used", "percent", "usage", "value", "pct", "fraction"] {
            if let n = numeric(dict[key]) { value = n; break }
        }
        guard let raw = value else { return nil }
        let utilization = normalize(raw)

        var resetsAt: Date?
        for key in ["resets_at", "resetsAt", "reset_at", "resets", "reset",
                    "resets_at_utc", "reset_time"] {
            if let s = dict[key] as? String, let date = TranscriptParser.parseDate(s) {
                resetsAt = date
                break
            }
            if let t = numeric(dict[key]), t > 1_000_000_000 {
                resetsAt = Date(timeIntervalSince1970: t > 4_000_000_000 ? t / 1000 : t)
                break
            }
        }
        // "resets_in_seconds" style relative resets.
        if resetsAt == nil {
            for key in ["resets_in_seconds", "reset_in_seconds", "resets_in", "seconds_until_reset"] {
                if let s = numeric(dict[key]), s > 0 {
                    resetsAt = Date().addingTimeInterval(s)
                    break
                }
            }
        }
        return QuotaWindow(utilization: utilization, resetsAt: resetsAt)
    }

    private static func numeric(_ value: Any?) -> Double? {
        if let v = value as? Double { return v }
        if let v = value as? Int { return Double(v) }
        if let v = value as? NSNumber { return v.doubleValue }
        if let v = value as? String, let d = Double(v) { return d }
        return nil
    }

    /// Accept 0…1 fractions and 0…100 percentages; clamp to 0…1.
    private static func normalize(_ v: Double) -> Double {
        var u = v
        if u > 1.5 { u /= 100 }
        return max(0, min(u, 1))
    }
}
