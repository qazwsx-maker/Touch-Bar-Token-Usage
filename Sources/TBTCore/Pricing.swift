import Foundation

/// USD per million tokens.
public struct ModelRates {
    public let inputPerM: Double
    public let outputPerM: Double
    public let cacheWritePerM: Double
    public let cacheReadPerM: Double

    public init(_ inputPerM: Double, _ outputPerM: Double, _ cacheWritePerM: Double, _ cacheReadPerM: Double) {
        self.inputPerM = inputPerM
        self.outputPerM = outputPerM
        self.cacheWritePerM = cacheWritePerM
        self.cacheReadPerM = cacheReadPerM
    }
}

/// Best-effort cost estimation. When a transcript line carries its own
/// `costUSD` (older Claude Code versions), that value wins.
public enum Pricing {
    /// Ordered: first substring match wins, so put specific ids before generic ones.
    static let table: [(needle: String, rates: ModelRates)] = [
        ("opus-4-5", ModelRates(5, 25, 6.25, 0.5)),
        ("opus-4-1", ModelRates(15, 75, 18.75, 1.5)),
        ("opus", ModelRates(15, 75, 18.75, 1.5)),
        ("sonnet", ModelRates(3, 15, 3.75, 0.3)),
        ("haiku-4", ModelRates(1, 5, 1.25, 0.1)),
        ("haiku-3-5", ModelRates(0.8, 4, 1, 0.08)),
        ("haiku", ModelRates(0.25, 1.25, 0.3, 0.03)),
        ("fable", ModelRates(5, 25, 6.25, 0.5)),
        ("mythos", ModelRates(5, 25, 6.25, 0.5)),
    ]

    public static let fallback = ModelRates(3, 15, 3.75, 0.3)

    public static func rates(for model: String) -> ModelRates {
        let m = model.lowercased()
        for row in table where m.contains(row.needle) {
            return row.rates
        }
        return fallback
    }

    public static func cost(of event: UsageEvent) -> Double {
        if let c = event.costUSD { return c }
        let r = rates(for: event.model)
        return (Double(event.inputTokens) * r.inputPerM
            + Double(event.outputTokens) * r.outputPerM
            + Double(event.cacheCreationTokens) * r.cacheWritePerM
            + Double(event.cacheReadTokens) * r.cacheReadPerM) / 1_000_000
    }
}
