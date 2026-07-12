import Foundation

/// Parses single lines of Claude Code transcript JSONL files
/// (`~/.claude/projects/**/*.jsonl`) into `UsageEvent`s.
public enum TranscriptParser {
    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parseDate(_ string: String) -> Date? {
        isoWithFraction.date(from: string) ?? isoPlain.date(from: string)
    }

    /// Returns nil for lines that carry no billable usage.
    public static func parseLine(_ line: String) -> UsageEvent? {
        guard line.contains("\"usage\"") else { return nil }
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        guard (obj["type"] as? String) == "assistant",
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else {
            return nil
        }
        if (obj["isApiErrorMessage"] as? Bool) == true { return nil }

        func intValue(_ key: String) -> Int {
            if let n = usage[key] as? Int { return n }
            if let n = usage[key] as? NSNumber { return n.intValue }
            return 0
        }

        let input = intValue("input_tokens")
        let output = intValue("output_tokens")
        let cacheCreation = intValue("cache_creation_input_tokens")
        let cacheRead = intValue("cache_read_input_tokens")
        guard input + output + cacheCreation + cacheRead > 0 else { return nil }

        let model = (message["model"] as? String) ?? (obj["model"] as? String) ?? "unknown"
        if model == "<synthetic>" { return nil }

        var date = Date()
        if let ts = obj["timestamp"] as? String, let parsed = parseDate(ts) {
            date = parsed
        }

        var costUSD: Double?
        if let c = obj["costUSD"] as? Double { costUSD = c }
        else if let c = obj["costUSD"] as? NSNumber { costUSD = c.doubleValue }

        var dedupeKey: String?
        if let messageID = message["id"] as? String {
            let requestID = (obj["requestId"] as? String) ?? ""
            dedupeKey = messageID + ":" + requestID
        }

        return UsageEvent(date: date,
                          model: model,
                          inputTokens: input,
                          outputTokens: output,
                          cacheCreationTokens: cacheCreation,
                          cacheReadTokens: cacheRead,
                          costUSD: costUSD,
                          dedupeKey: dedupeKey)
    }
}
