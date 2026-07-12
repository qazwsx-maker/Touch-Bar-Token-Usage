import Foundation
import TBTCore

/// Watches `~/.claude/projects/**/*.jsonl` (and the XDG variant), tails new
/// lines, aggregates per-day token usage plus 5-hour-block / weekly windows,
/// and publishes snapshots on the main queue every few seconds.
final class UsageMonitor {
    struct Snapshot {
        var today = UsageTotals.zero
        var month = UsageTotals.zero
        var ratePerMinute: Double = 0
        var lastModel: String?
        var lastEventDate: Date?
        var filesTracked: Int = 0
        var dataDirFound: Bool = false

        // 5-hour session block (Claude subscription window).
        var fiveHourTokens = 0
        var fiveHourLimit = 0          // resolved: custom, else learned max (0 = unknown)
        var fiveHourFraction: Double = 0
        var fiveHourResetAt: Date?
        var fiveHourLimitIsAuto = true
        var fiveHourHasData = false

        // Rolling 7-day window.
        var weeklyTokens = 0
        var weeklyLimit = 0
        var weeklyFraction: Double = 0
        var weeklyResetAt: Date?
        var weeklyLimitIsAuto = true
        var weeklyHasData = false

        /// "api" when percentages come straight from Claude's usage endpoint,
        /// "local" when they are estimated from transcripts.
        var quotaSource = "local"
    }

    var onUpdate: ((Snapshot) -> Void)?

    private let queue = DispatchQueue(label: "tbtu.usage-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?

    private struct FileState {
        var offset: UInt64
        var remainder: Data
    }

    private var files: [String: FileState] = [:]
    private var perDay: [String: UsageTotals] = [:]
    private var seenKeys = Set<String>()
    private var burn = BurnRateTracker()
    private var lastModel: String?
    private var lastEventDate: Date?
    private var firstScanDone = false

    /// Events for the last ~8 days used for block/weekly windows.
    /// Tokens counted toward limits: input + output + cache writes
    /// (cache reads are excluded — they would swamp the numbers).
    private var recentEvents: [SessionBlocks.Event] = []
    private var recentEventsDirty = false

    private var customFiveHourLimit = 0
    private var customWeeklyLimit = 0
    private var quota: Quota?

    private static let learnedFiveKey = "learnedMaxFiveHourTokens"
    private static let learnedWeekKey = "learnedMaxWeeklyTokens"

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(300), repeating: .seconds(3))
        t.setEventHandler { [weak self] in
            self?.scan()
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func setCustomLimits(fiveHour: Int, weekly: Int) {
        queue.async { [weak self] in
            self?.customFiveHourLimit = max(0, fiveHour)
            self?.customWeeklyLimit = max(0, weekly)
        }
    }

    /// Real percentages from Claude's usage endpoint (nil = fall back to
    /// local estimates). Triggers an immediate republish.
    func setQuota(_ newQuota: Quota?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.quota = newQuota
            if self.firstScanDone {
                self.publish(dataDirFound: !self.dataRoots().isEmpty)
            }
        }
    }

    private func dataRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects"),
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func scan() {
        let fm = FileManager.default
        let roots = dataRoots()
        var seenPaths = Set<String>()
        let historyCutoff = Date().addingTimeInterval(-35 * 24 * 3600)

        for root in roots {
            guard let enumerator = fm.enumerator(at: root,
                                                 includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                                 options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else { continue }
                let path = url.path
                seenPaths.insert(path)
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let sizeInt = values.fileSize else { continue }
                let size = UInt64(sizeInt)
                let mtime = values.contentModificationDate ?? Date()

                var state: FileState
                if let existing = files[path] {
                    state = existing
                } else if !firstScanDone && mtime < historyCutoff {
                    // Old transcript: skip its history, only follow future appends.
                    files[path] = FileState(offset: size, remainder: Data())
                    continue
                } else {
                    state = FileState(offset: 0, remainder: Data())
                }

                if size < state.offset {
                    // File was truncated/replaced — re-read from the start.
                    state = FileState(offset: 0, remainder: Data())
                }
                if size > state.offset {
                    readNewData(url: url, state: &state)
                }
                files[path] = state
            }
        }

        for key in Array(files.keys) where !seenPaths.contains(key) {
            files.removeValue(forKey: key)
        }
        firstScanDone = true
        prunePerDay()
        pruneRecentEvents()
        publish(dataDirFound: !roots.isEmpty)
    }

    private func readNewData(url: URL, state: inout FileState) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        handle.seek(toFileOffset: state.offset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }
        state.offset += UInt64(data.count)

        var buffer = state.remainder
        buffer.append(data)
        var start = buffer.startIndex
        while start < buffer.endIndex, let nl = buffer[start...].firstIndex(of: 0x0A) {
            let lineData = buffer[start..<nl]
            start = buffer.index(after: nl)
            guard !lineData.isEmpty else { continue }
            if let line = String(data: lineData, encoding: .utf8) {
                process(line: line)
            }
        }
        state.remainder = Data(buffer[start...])
        if state.remainder.count > 8_000_000 {
            state.remainder = Data()
        }
    }

    private func process(line: String) {
        guard let event = TranscriptParser.parseLine(line) else { return }
        if let key = event.dedupeKey {
            if seenKeys.contains(key) { return }
            seenKeys.insert(key)
            if seenKeys.count > 500_000 { seenKeys.removeAll() }
        }
        let cost = Pricing.cost(of: event)
        let day = dayFormatter.string(from: event.date)
        var totals = perDay[day] ?? .zero
        totals.add(event, cost: cost)
        perDay[day] = totals

        if lastEventDate == nil || event.date > lastEventDate! {
            lastEventDate = event.date
            lastModel = event.model
        }
        if event.date > Date().addingTimeInterval(-600) {
            burn.add(tokens: event.inputTokens + event.outputTokens, at: event.date)
        }
        let limitTokens = event.inputTokens + event.outputTokens + event.cacheCreationTokens
        if limitTokens > 0, event.date > Date().addingTimeInterval(-8 * 24 * 3600) {
            recentEvents.append((date: event.date, tokens: limitTokens))
            recentEventsDirty = true
        }
    }

    private func prunePerDay() {
        guard perDay.count > 70 else { return }
        let sortedKeys = perDay.keys.sorted()
        for key in sortedKeys.prefix(perDay.count - 62) {
            perDay.removeValue(forKey: key)
        }
    }

    private func pruneRecentEvents() {
        let cutoff = Date().addingTimeInterval(-8 * 24 * 3600)
        if recentEvents.contains(where: { $0.date < cutoff }) {
            recentEvents.removeAll { $0.date < cutoff }
        }
    }

    private func publish(dataDirFound: Bool) {
        var snapshot = Snapshot()
        let now = Date()
        let todayKey = dayFormatter.string(from: now)
        let monthPrefix = String(todayKey.prefix(7))
        snapshot.today = perDay[todayKey] ?? .zero
        for (key, totals) in perDay where key.hasPrefix(monthPrefix) {
            snapshot.month.add(totals)
        }
        snapshot.ratePerMinute = burn.ratePerMinute(now: now)
        snapshot.lastModel = lastModel
        snapshot.lastEventDate = lastEventDate
        snapshot.filesTracked = files.count
        snapshot.dataDirFound = dataDirFound

        if recentEventsDirty {
            recentEvents.sort { $0.date < $1.date }
            recentEventsDirty = false
        }

        // 5-hour block window
        let defaults = UserDefaults.standard
        let currentBlock = SessionBlocks.current(events: recentEvents, now: now)
        snapshot.fiveHourTokens = currentBlock?.tokens ?? 0
        snapshot.fiveHourResetAt = currentBlock?.end

        var learnedFive = defaults.integer(forKey: Self.learnedFiveKey)
        let windowMaxFive = SessionBlocks.maxBlockTokens(events: recentEvents)
        if windowMaxFive > learnedFive {
            learnedFive = windowMaxFive
            defaults.set(learnedFive, forKey: Self.learnedFiveKey)
        }
        snapshot.fiveHourLimitIsAuto = customFiveHourLimit <= 0
        snapshot.fiveHourLimit = customFiveHourLimit > 0 ? customFiveHourLimit : learnedFive
        if snapshot.fiveHourLimit > 0 {
            snapshot.fiveHourFraction = min(1, Double(snapshot.fiveHourTokens) / Double(snapshot.fiveHourLimit))
        }

        // Rolling 7-day window
        snapshot.weeklyTokens = SessionBlocks.tokens(inLast: 7 * 24 * 3600, events: recentEvents, now: now)
        var learnedWeek = defaults.integer(forKey: Self.learnedWeekKey)
        if snapshot.weeklyTokens > learnedWeek {
            learnedWeek = snapshot.weeklyTokens
            defaults.set(learnedWeek, forKey: Self.learnedWeekKey)
        }
        snapshot.weeklyLimitIsAuto = customWeeklyLimit <= 0
        snapshot.weeklyLimit = customWeeklyLimit > 0 ? customWeeklyLimit : learnedWeek
        if snapshot.weeklyLimit > 0 {
            snapshot.weeklyFraction = min(1, Double(snapshot.weeklyTokens) / Double(snapshot.weeklyLimit))
        }
        snapshot.fiveHourHasData = snapshot.fiveHourLimit > 0
        snapshot.weeklyHasData = snapshot.weeklyLimit > 0

        // Real quota from the API wins over local estimates.
        if let quota = quota {
            if let five = quota.fiveHour {
                snapshot.fiveHourFraction = five.utilization
                snapshot.fiveHourResetAt = five.resetsAt ?? snapshot.fiveHourResetAt
                snapshot.fiveHourHasData = true
                snapshot.quotaSource = "api"
            }
            if let seven = quota.sevenDay {
                snapshot.weeklyFraction = seven.utilization
                snapshot.weeklyResetAt = seven.resetsAt
                snapshot.weeklyHasData = true
                snapshot.quotaSource = "api"
            }
        }

        let result = snapshot
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(result)
        }
    }
}
