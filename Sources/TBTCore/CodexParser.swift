import Foundation

/// One rate-limit window from Codex CLI rollout logs (`~/.codex/sessions`).
/// Codex snapshots its ChatGPT-plan limits into `token_count` events:
/// primary ≈ the 5-hour window, secondary ≈ the weekly window.
public struct CodexRateWindow: Equatable {
    public let usedPercent: Double        // 0…100
    public let resetsAt: Date?
    public let windowMinutes: Int?

    public init(usedPercent: Double, resetsAt: Date?, windowMinutes: Int?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
    }
}

public struct CodexParsed {
    public let date: Date?
    public let turnTokens: Int?           // tokens spent by the last turn
    public let model: String?
    public let primary: CodexRateWindow?
    public let secondary: CodexRateWindow?

    public init(date: Date?, turnTokens: Int?, model: String?,
                primary: CodexRateWindow?, secondary: CodexRateWindow?) {
        self.date = date
        self.turnTokens = turnTokens
        self.model = model
        self.primary = primary
        self.secondary = secondary
    }
}

/// Defensive parser for Codex CLI rollout JSONL lines. Field layouts have
/// shifted between Codex versions, so several shapes are accepted.
public enum CodexParser {
    public static func parseLine(_ line: String) -> CodexParsed? {
        guard line.contains("token_count") || line.contains("turn_context")
            || line.contains("rate_limits") || line.contains("session_meta") else {
            return nil
        }
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        var date: Date?
        if let ts = object["timestamp"] as? String {
            date = TranscriptParser.parseDate(ts)
        }

        let payload = (object["payload"] as? [String: Any]) ?? object
        let type = (payload["type"] as? String) ?? (object["type"] as? String) ?? ""

        var turnTokens: Int?
        var model: String?
        var primary: CodexRateWindow?
        var secondary: CodexRateWindow?

        if let m = payload["model"] as? String, !m.isEmpty {
            model = m
        }

        if type == "token_count" {
            let info = (payload["info"] as? [String: Any]) ?? payload
            if let last = info["last_token_usage"] as? [String: Any] {
                turnTokens = tokenSum(last)
            } else if info["input_tokens"] != nil {
                turnTokens = tokenSum(info)
            }
            let rateLimits = (payload["rate_limits"] as? [String: Any])
                ?? (info["rate_limits"] as? [String: Any])
                ?? (object["rate_limits"] as? [String: Any])
            if let limits = rateLimits {
                primary = window(limits["primary"], flat: limits, prefix: "primary", eventDate: date)
                secondary = window(limits["secondary"], flat: limits, prefix: "secondary", eventDate: date)
            }
        }

        if turnTokens == nil && model == nil && primary == nil && secondary == nil {
            return nil
        }
        return CodexParsed(date: date, turnTokens: turnTokens, model: model,
                           primary: primary, secondary: secondary)
    }

    private static func tokenSum(_ usage: [String: Any]) -> Int {
        func value(_ key: String) -> Int {
            if let n = usage[key] as? Int { return n }
            if let n = usage[key] as? NSNumber { return n.intValue }
            return 0
        }
        return value("input_tokens") + value("output_tokens")
    }

    private static func window(_ nested: Any?, flat: [String: Any], prefix: String,
                               eventDate: Date?) -> CodexRateWindow? {
        var dict = nested as? [String: Any]
        if dict == nil {
            // Flat variant: {"primary_used_percent": …, "primary_to_reset_seconds"? …}
            var flattened: [String: Any] = [:]
            for (key, value) in flat where key.hasPrefix(prefix + "_") {
                flattened[String(key.dropFirst(prefix.count + 1))] = value
            }
            dict = flattened.isEmpty ? nil : flattened
        }
        guard let window = dict else { return nil }

        var percent: Double?
        for key in ["used_percent", "usedPercent", "percent_used", "used_pct"] {
            if let v = window[key] as? Double { percent = v; break }
            if let v = window[key] as? Int { percent = Double(v); break }
            if let v = window[key] as? NSNumber { percent = v.doubleValue; break }
        }
        guard let used = percent else { return nil }

        var resetsAt: Date?
        for key in ["resets_in_seconds", "resetsInSeconds", "to_reset_seconds", "reset_in_seconds"] {
            if let seconds = (window[key] as? Double) ?? (window[key] as? NSNumber)?.doubleValue,
               seconds >= 0 {
                resetsAt = (eventDate ?? Date()).addingTimeInterval(seconds)
                break
            }
        }
        if resetsAt == nil, let s = window["resets_at"] as? String {
            resetsAt = TranscriptParser.parseDate(s)
        }

        var windowMinutes: Int?
        if let m = (window["window_minutes"] as? Int) ?? (window["window_minutes"] as? NSNumber)?.intValue {
            windowMinutes = m
        }

        return CodexRateWindow(usedPercent: max(0, min(used, 100)),
                               resetsAt: resetsAt,
                               windowMinutes: windowMinutes)
    }
}
