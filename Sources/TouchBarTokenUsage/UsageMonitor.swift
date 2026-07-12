import Foundation
import TBTCore

/// Watches `~/.claude/projects/**/*.jsonl` (and the XDG variant), tails new
/// lines, aggregates per-day token usage and publishes snapshots on the main
/// queue every few seconds.
final class UsageMonitor {
    struct Snapshot {
        var today = UsageTotals.zero
        var month = UsageTotals.zero
        var ratePerMinute: Double = 0
        var lastModel: String?
        var lastEventDate: Date?
        var filesTracked: Int = 0
        var dataDirFound: Bool = false
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
    }

    private func prunePerDay() {
        guard perDay.count > 70 else { return }
        let sortedKeys = perDay.keys.sorted()
        for key in sortedKeys.prefix(perDay.count - 62) {
            perDay.removeValue(forKey: key)
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

        let result = snapshot
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(result)
        }
    }
}
