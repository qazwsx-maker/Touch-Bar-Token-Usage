import Foundation

/// One 5-hour usage window (Claude subscription limits work in 5-hour
/// blocks that start with the first message after the previous block ends).
public struct SessionBlock: Equatable {
    public let start: Date
    public let end: Date
    public let tokens: Int

    public init(start: Date, end: Date, tokens: Int) {
        self.start = start
        self.end = end
        self.tokens = tokens
    }
}

/// Groups usage events into ccusage-style session blocks:
/// - a block starts at the first event's timestamp floored to the hour,
/// - lasts `hours` (default 5),
/// - an event past the block end, or after a gap of `hours` since the
///   previous event, starts a new block.
public enum SessionBlocks {
    public typealias Event = (date: Date, tokens: Int)

    public static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    public static func blocks(events: [Event], hours: Double = 5) -> [SessionBlock] {
        guard !events.isEmpty else { return [] }
        let duration = hours * 3600
        let sorted = events.sorted { $0.date < $1.date }

        var result: [SessionBlock] = []
        var blockStart: Date?
        var blockTokens = 0
        var lastEventDate: Date?

        for event in sorted {
            if let start = blockStart, let lastDate = lastEventDate,
               event.date.timeIntervalSince(start) >= duration
                || event.date.timeIntervalSince(lastDate) >= duration {
                result.append(SessionBlock(start: start,
                                           end: start.addingTimeInterval(duration),
                                           tokens: blockTokens))
                blockStart = nil
                blockTokens = 0
            }
            if blockStart == nil {
                blockStart = floorToHour(event.date)
            }
            blockTokens += event.tokens
            lastEventDate = event.date
        }
        if let start = blockStart {
            result.append(SessionBlock(start: start,
                                       end: start.addingTimeInterval(duration),
                                       tokens: blockTokens))
        }
        return result
    }

    /// The block covering `now`, or nil when the last block already expired.
    public static func current(events: [Event], now: Date = Date(), hours: Double = 5) -> SessionBlock? {
        guard let last = blocks(events: events, hours: hours).last else { return nil }
        guard now >= last.start, now < last.end else { return nil }
        return last
    }

    /// Highest tokens seen in any single block — used for auto limits.
    public static func maxBlockTokens(events: [Event], hours: Double = 5) -> Int {
        blocks(events: events, hours: hours).map { $0.tokens }.max() ?? 0
    }

    /// Rolling-window sum (e.g. last 7 days) ending at `now`.
    public static func tokens(inLast interval: TimeInterval, events: [Event], now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-interval)
        return events.reduce(0) { $1.date >= cutoff && $1.date <= now ? $0 + $1.tokens : $0 }
    }
}
