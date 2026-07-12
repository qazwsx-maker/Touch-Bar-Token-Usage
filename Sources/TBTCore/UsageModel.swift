import Foundation

/// Aggregated token usage for some period (a day, a month, ...).
public struct UsageTotals: Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheCreationTokens: Int
    public var cacheReadTokens: Int
    public var costUSD: Double

    public init(inputTokens: Int = 0,
                outputTokens: Int = 0,
                cacheCreationTokens: Int = 0,
                cacheReadTokens: Int = 0,
                costUSD: Double = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
    }

    public static let zero = UsageTotals()

    /// Every token that went through the API, including cache traffic.
    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    /// Tokens excluding cache reads/writes.
    public var directTokens: Int { inputTokens + outputTokens }

    public mutating func add(_ event: UsageEvent, cost: Double) {
        inputTokens += event.inputTokens
        outputTokens += event.outputTokens
        cacheCreationTokens += event.cacheCreationTokens
        cacheReadTokens += event.cacheReadTokens
        costUSD += cost
    }

    public mutating func add(_ other: UsageTotals) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheCreationTokens += other.cacheCreationTokens
        cacheReadTokens += other.cacheReadTokens
        costUSD += other.costUSD
    }
}

/// One usage record parsed out of a Claude Code transcript line.
public struct UsageEvent {
    public let date: Date
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let costUSD: Double?
    public let dedupeKey: String?

    public init(date: Date,
                model: String,
                inputTokens: Int,
                outputTokens: Int,
                cacheCreationTokens: Int,
                cacheReadTokens: Int,
                costUSD: Double?,
                dedupeKey: String?) {
        self.date = date
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
        self.dedupeKey = dedupeKey
    }
}

/// Sliding-window tokens/minute tracker used to animate the pet.
public struct BurnRateTracker {
    private var samples: [(date: Date, tokens: Int)] = []

    public init() {}

    public mutating func add(tokens: Int, at date: Date) {
        samples.append((date, tokens))
        if samples.count > 4096 {
            prune(now: date)
        }
    }

    /// Tokens observed in the last 60 seconds.
    public mutating func ratePerMinute(now: Date = Date()) -> Double {
        prune(now: now)
        let cutoff = now.addingTimeInterval(-60)
        let sum = samples.reduce(0) { $1.date >= cutoff && $1.date <= now ? $0 + $1.tokens : $0 }
        return Double(sum)
    }

    private mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-180)
        samples.removeAll { $0.date < cutoff }
    }
}
