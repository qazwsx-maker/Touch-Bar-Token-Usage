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
/// Field names vary a little across versions, so it accepts several spellings
/// and both 0…1 fractions and 0…100 percentages.
public enum QuotaParser {
    public static func parse(_ data: Data) -> Quota? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let root = (object["usage"] as? [String: Any]) ?? object

        let five = window(in: root, keys: ["five_hour", "fiveHour", "session"])
        let seven = window(in: root, keys: ["seven_day", "sevenDay", "seven_day_overall",
                                            "seven_day_all_models", "weekly"])
        if five == nil && seven == nil { return nil }
        return Quota(fiveHour: five, sevenDay: seven)
    }

    private static func window(in root: [String: Any], keys: [String]) -> QuotaWindow? {
        for key in keys {
            if let dict = root[key] as? [String: Any], let w = window(from: dict) {
                return w
            }
        }
        return nil
    }

    private static func window(from dict: [String: Any]) -> QuotaWindow? {
        var value: Double?
        for key in ["utilization", "utilization_pct", "percent", "used_pct"] {
            if let v = dict[key] as? Double { value = v; break }
            if let v = dict[key] as? Int { value = Double(v); break }
            if let v = dict[key] as? NSNumber { value = v.doubleValue; break }
        }
        guard var utilization = value else { return nil }
        if utilization > 1.5 { utilization /= 100 }
        utilization = max(0, min(utilization, 1))

        var resetsAt: Date?
        for key in ["resets_at", "resetsAt", "reset_at"] {
            if let s = dict[key] as? String, let date = TranscriptParser.parseDate(s) {
                resetsAt = date
                break
            }
            if let t = dict[key] as? Double, t > 1_000_000_000 {
                // epoch seconds or millis
                resetsAt = Date(timeIntervalSince1970: t > 4_000_000_000 ? t / 1000 : t)
                break
            }
        }
        return QuotaWindow(utilization: utilization, resetsAt: resetsAt)
    }
}
