import Foundation
import TBTCore

/// Tails Codex CLI rollout logs (`~/.codex/sessions/**/*.jsonl`) for token
/// usage and the ChatGPT-plan rate-limit snapshots Codex writes with every
/// turn. Publishes on the main queue. Freshness == the last Codex turn.
final class CodexMonitor {
    struct Snapshot {
        var todayTokens = 0
        var ratePerMinute: Double = 0
        var fiveHourFraction: Double = 0
        var fiveHourResetAt: Date?
        var fiveHourHasData = false
        var weeklyFraction: Double = 0
        var weeklyResetAt: Date?
        var weeklyHasData = false
        var lastModel: String?
        var dataDirFound = false
    }

    var onUpdate: ((Snapshot) -> Void)?

    private let queue = DispatchQueue(label: "tbtu.codex-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?

    private struct FileState {
        var offset: UInt64
        var remainder: Data
    }

    private var files: [String: FileState] = [:]
    private var perDay: [String: Int] = [:]
    private var burn = BurnRateTracker()
    private var lastModel: String?
    private var fiveWindow: (window: CodexRateWindow, seen: Date)?
    private var weekWindow: (window: CodexRateWindow, seen: Date)?
    private var firstScanDone = false

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(700), repeating: .seconds(5))
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

    private var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    }

    private func scan() {
        let fm = FileManager.default
        let rootExists = fm.fileExists(atPath: root.path)
        if rootExists {
            let historyCutoff = Date().addingTimeInterval(-35 * 24 * 3600)
            var seenPaths = Set<String>()
            if let enumerator = fm.enumerator(at: root,
                                              includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                              options: [.skipsHiddenFiles]) {
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
                        files[path] = FileState(offset: size, remainder: Data())
                        continue
                    } else {
                        state = FileState(offset: 0, remainder: Data())
                    }
                    if size < state.offset {
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
        }
        firstScanDone = true
        if perDay.count > 70 {
            for key in perDay.keys.sorted().prefix(perDay.count - 62) {
                perDay.removeValue(forKey: key)
            }
        }
        publish(dataDirFound: rootExists)
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
        guard let parsed = CodexParser.parseLine(line) else { return }
        let date = parsed.date ?? Date()

        if let tokens = parsed.turnTokens, tokens > 0 {
            let day = dayFormatter.string(from: date)
            perDay[day] = (perDay[day] ?? 0) + tokens
            if date > Date().addingTimeInterval(-600) {
                burn.add(tokens: tokens, at: date)
            }
        }
        if let model = parsed.model {
            lastModel = model
        }
        store(parsed.primary, seen: date)
        store(parsed.secondary, seen: date)
    }

    /// Route a window into the 5h/weekly slot by its length, keeping the
    /// freshest snapshot per slot.
    private func store(_ window: CodexRateWindow?, seen: Date) {
        guard let window = window else { return }
        let isWeekly: Bool
        if let minutes = window.windowMinutes {
            isWeekly = minutes > 24 * 60
        } else {
            isWeekly = (window.resetsAt?.timeIntervalSince(seen) ?? 0) > 24 * 3600
        }
        if isWeekly {
            if weekWindow == nil || seen >= weekWindow!.seen {
                weekWindow = (window, seen)
            }
        } else {
            if fiveWindow == nil || seen >= fiveWindow!.seen {
                fiveWindow = (window, seen)
            }
        }
    }

    private func publish(dataDirFound: Bool) {
        var snapshot = Snapshot()
        let now = Date()
        snapshot.todayTokens = perDay[dayFormatter.string(from: now)] ?? 0
        snapshot.ratePerMinute = burn.ratePerMinute(now: now)
        snapshot.lastModel = lastModel
        snapshot.dataDirFound = dataDirFound

        if let five = fiveWindow {
            let expired = five.window.resetsAt.map { $0 < now } ?? (five.seen < now.addingTimeInterval(-6 * 3600))
            if !expired {
                snapshot.fiveHourFraction = five.window.usedPercent / 100
                snapshot.fiveHourResetAt = five.window.resetsAt
                snapshot.fiveHourHasData = true
            }
        }
        if let week = weekWindow {
            let expired = week.window.resetsAt.map { $0 < now } ?? (week.seen < now.addingTimeInterval(-8 * 24 * 3600))
            if !expired {
                snapshot.weeklyFraction = week.window.usedPercent / 100
                snapshot.weeklyResetAt = week.window.resetsAt
                snapshot.weeklyHasData = true
            }
        }

        let result = snapshot
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(result)
        }
    }
}
