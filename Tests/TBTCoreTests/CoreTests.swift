import XCTest
@testable import TBTCore

final class CoreTests: XCTestCase {

    // MARK: - Transcript parsing

    private let sampleLine = """
    {"type":"assistant","timestamp":"2026-07-12T03:04:05.123Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-sonnet-5","usage":{"input_tokens":1200,"output_tokens":300,"cache_creation_input_tokens":50,"cache_read_input_tokens":8000}}}
    """

    func testParseAssistantLine() throws {
        let event = try XCTUnwrap(TranscriptParser.parseLine(sampleLine))
        XCTAssertEqual(event.inputTokens, 1200)
        XCTAssertEqual(event.outputTokens, 300)
        XCTAssertEqual(event.cacheCreationTokens, 50)
        XCTAssertEqual(event.cacheReadTokens, 8000)
        XCTAssertEqual(event.model, "claude-sonnet-5")
        XCTAssertEqual(event.dedupeKey, "msg_1:req_1")
        XCTAssertNil(event.costUSD)
    }

    func testParseTimestampWithoutFraction() throws {
        let line = sampleLine.replacingOccurrences(of: "2026-07-12T03:04:05.123Z",
                                                   with: "2026-07-12T03:04:05Z")
        let event = try XCTUnwrap(TranscriptParser.parseLine(line))
        let expected = try XCTUnwrap(TranscriptParser.parseDate("2026-07-12T03:04:05Z"))
        XCTAssertEqual(event.date, expected)
    }

    func testParseRejectsUninterestingLines() {
        XCTAssertNil(TranscriptParser.parseLine("not json"))
        XCTAssertNil(TranscriptParser.parseLine("{\"type\":\"user\",\"message\":{\"usage\":{\"input_tokens\":5}}}"))
        let zero = sampleLine
            .replacingOccurrences(of: "1200", with: "0")
            .replacingOccurrences(of: "300", with: "0")
            .replacingOccurrences(of: "50", with: "0")
            .replacingOccurrences(of: "8000", with: "0")
        XCTAssertNil(TranscriptParser.parseLine(zero))
        let synthetic = sampleLine.replacingOccurrences(of: "claude-sonnet-5", with: "<synthetic>")
        XCTAssertNil(TranscriptParser.parseLine(synthetic))
    }

    // MARK: - Pricing

    func testCostComputationForSonnet() throws {
        let event = try XCTUnwrap(TranscriptParser.parseLine(sampleLine))
        let inputCost: Double = 1200.0 * 3.0
        let outputCost: Double = 300.0 * 15.0
        let cacheWriteCost: Double = 50.0 * 3.75
        let cacheReadCost: Double = 8000.0 * 0.3
        let expected: Double = (inputCost + outputCost + cacheWriteCost + cacheReadCost) / 1_000_000.0
        XCTAssertEqual(Pricing.cost(of: event), expected, accuracy: 1e-9)
    }

    func testCostPrefersEmbeddedCostUSD() throws {
        let line = sampleLine.replacingOccurrences(of: "\"requestId\":\"req_1\",",
                                                   with: "\"requestId\":\"req_1\",\"costUSD\":0.5,")
        let event = try XCTUnwrap(TranscriptParser.parseLine(line))
        XCTAssertEqual(Pricing.cost(of: event), 0.5, accuracy: 1e-9)
    }

    func testRatesLookup() {
        XCTAssertEqual(Pricing.rates(for: "claude-opus-4-5-20251101").inputPerM, 5)
        XCTAssertEqual(Pricing.rates(for: "claude-opus-4-1-20250805").inputPerM, 15)
        XCTAssertEqual(Pricing.rates(for: "claude-3-opus-latest").inputPerM, 15)
        XCTAssertEqual(Pricing.rates(for: "claude-sonnet-5").inputPerM, 3)
        XCTAssertEqual(Pricing.rates(for: "totally-unknown").inputPerM, Pricing.fallback.inputPerM)
    }

    // MARK: - Formatting

    func testAbbrev() {
        XCTAssertEqual(Fmt.abbrev(0), "0")
        XCTAssertEqual(Fmt.abbrev(999), "999")
        XCTAssertEqual(Fmt.abbrev(1000), "1K")
        XCTAssertEqual(Fmt.abbrev(1200), "1.2K")
        XCTAssertEqual(Fmt.abbrev(12800), "12.8K")
        XCTAssertEqual(Fmt.abbrev(1_000_000), "1M")
        XCTAssertEqual(Fmt.abbrev(1_280_000), "1.28M")
    }

    func testMoneyAndRate() {
        XCTAssertEqual(Fmt.money(4.321), "$4.32")
        XCTAssertEqual(Fmt.money(1234.6), "$1235")
        XCTAssertEqual(Fmt.rate(0.2), "idle")
        XCTAssertEqual(Fmt.rate(8100), "8.1K/m")
    }

    // MARK: - Burn rate

    func testBurnRateWindow() {
        var tracker = BurnRateTracker()
        let now = Date()
        tracker.add(tokens: 500, at: now.addingTimeInterval(-90))
        tracker.add(tokens: 200, at: now.addingTimeInterval(-30))
        tracker.add(tokens: 100, at: now)
        XCTAssertEqual(tracker.ratePerMinute(now: now), 300, accuracy: 0.001)
    }

    // MARK: - Approval helpers

    func testHookResponseJSON() throws {
        let json = try XCTUnwrap(HookResponse.preToolUseJSON(decision: .allow, reason: "ok"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let output = try XCTUnwrap(obj["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(output["permissionDecision"] as? String, "allow")
        XCTAssertEqual(output["permissionDecisionReason"] as? String, "ok")
        XCTAssertNil(HookResponse.preToolUseJSON(decision: .pass, reason: "x"))
    }

    func testSummarizer() {
        let summary = ApprovalSummarizer.summarize(
            toolName: "Bash",
            toolInput: ["command": "git push origin main\necho done"],
            cwd: "/Users/dev/my-project")
        XCTAssertEqual(summary.title, "Bash · my-project")
        XCTAssertEqual(summary.detail, "git push origin main")

        let edit = ApprovalSummarizer.summarize(
            toolName: "Edit",
            toolInput: ["file_path": "/Users/dev/proj/Sources/App/main.swift"],
            cwd: nil)
        XCTAssertEqual(edit.title, "Edit")
        XCTAssertEqual(edit.detail, "App/main.swift")
    }

    func testToolMatches() {
        XCTAssertTrue(ApprovalSummarizer.toolMatches("Bash", pattern: "Bash|Edit"))
        XCTAssertTrue(ApprovalSummarizer.toolMatches("Edit", pattern: "Bash|Edit"))
        XCTAssertFalse(ApprovalSummarizer.toolMatches("Bashful", pattern: "Bash|Edit"))
        XCTAssertTrue(ApprovalSummarizer.toolMatches("Anything", pattern: ""))
        XCTAssertTrue(ApprovalSummarizer.toolMatches("Anything", pattern: "*"))
        XCTAssertTrue(ApprovalSummarizer.toolMatches("mcp__github__create_pr", pattern: "mcp__.*"))
    }

    // MARK: - Hook settings merger

    func testMergerInstallsPreservingExistingContent() throws {
        let existing = """
        {"model":"opus","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/other-hook.sh"}]}]}}
        """
        let merged = try HookSettingsMerger.merged(existingJSON: Data(existing.utf8),
                                                   hookCommand: "/Users/x/.claude/touchbar-usage/hook.sh",
                                                   preToolUseMatcher: "Bash|Edit",
                                                   includeExtraEvents: true)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: merged) as? [String: Any])
        XCTAssertEqual(obj["model"] as? String, "opus")
        let hooks = try XCTUnwrap(obj["hooks"] as? [String: Any])
        let pre = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(pre.count, 2)
        XCTAssertNotNil(hooks["Stop"])
        XCTAssertNotNil(hooks["Notification"])
        XCTAssertTrue(HookSettingsMerger.isInstalled(existingJSON: merged))
    }

    func testMergerIsIdempotent() throws {
        let once = try HookSettingsMerger.merged(existingJSON: nil,
                                                 hookCommand: "/Users/x/.claude/touchbar-usage/hook.sh",
                                                 preToolUseMatcher: "Bash",
                                                 includeExtraEvents: true)
        let twice = try HookSettingsMerger.merged(existingJSON: once,
                                                  hookCommand: "/Users/x/.claude/touchbar-usage/hook.sh",
                                                  preToolUseMatcher: "Bash",
                                                  includeExtraEvents: true)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: twice) as? [String: Any])
        let hooks = try XCTUnwrap(obj["hooks"] as? [String: Any])
        let pre = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(pre.count, 1)
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 1)
    }

    func testMergerRemoveRestoresOtherHooks() throws {
        let existing = """
        {"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/other-hook.sh"}]}]}}
        """
        let merged = try HookSettingsMerger.merged(existingJSON: Data(existing.utf8),
                                                   hookCommand: "/Users/x/.claude/touchbar-usage/hook.sh",
                                                   preToolUseMatcher: "Bash|Edit",
                                                   includeExtraEvents: true)
        let removed = try HookSettingsMerger.removed(existingJSON: merged)
        XCTAssertFalse(HookSettingsMerger.isInstalled(existingJSON: removed))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: removed) as? [String: Any])
        let hooks = try XCTUnwrap(obj["hooks"] as? [String: Any])
        let pre = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(pre.count, 1)
        XCTAssertNil(hooks["Stop"])
    }

    // MARK: - Hex colors

    func testHexParsing() {
        let c = HexColor.parse("#FF8000")
        XCTAssertEqual(c.r, 1.0, accuracy: 0.001)
        XCTAssertEqual(c.g, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.b, 0.0, accuracy: 0.001)
        XCTAssertEqual(c.a, 1.0, accuracy: 0.001)

        let short = HexColor.parse("0F0")
        XCTAssertEqual(short.g, 1.0, accuracy: 0.001)
        XCTAssertEqual(HexColor.format(r: 1, g: 128.0 / 255.0, b: 0), "#FF8000")
    }

    func testThemePresetsExist() {
        XCTAssertGreaterThanOrEqual(ThemeSpec.presets.count, 5)
        XCTAssertEqual(ThemeSpec.presets.first?.id, "midnight")
    }

    // MARK: - Session blocks & windows

    private func date(_ hoursFromBase: Double) -> Date {
        // Base: 2026-07-10 00:00:00 UTC
        Date(timeIntervalSince1970: 1_783_987_200 + hoursFromBase * 3600)
    }

    func testSessionBlockGrouping() {
        let events: [SessionBlocks.Event] = [
            (date(10.25), 100),   // block 1 starts at 10:00
            (date(12.0), 200),    // same block (within 5h, gap < 5h)
            (date(16.0), 50),     // past block end (15:00) -> new block at 16:00
        ]
        let blocks = SessionBlocks.blocks(events: events)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].start, date(10))
        XCTAssertEqual(blocks[0].end, date(15))
        XCTAssertEqual(blocks[0].tokens, 300)
        XCTAssertEqual(blocks[1].start, date(16))
        XCTAssertEqual(blocks[1].tokens, 50)
        XCTAssertEqual(SessionBlocks.maxBlockTokens(events: events), 300)
    }

    func testSessionBlockGapStartsNewBlock() {
        // Two events within the same 5h-from-floored-start range but with a
        // >= 5h gap between them must split into two blocks.
        let events: [SessionBlocks.Event] = [
            (date(0.9), 10),
            (date(5.95), 20),  // 5.05h after previous event
        ]
        let blocks = SessionBlocks.blocks(events: events)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1].start, date(5))
    }

    func testCurrentBlockAndExpiry() {
        let events: [SessionBlocks.Event] = [(date(10.25), 100), (date(11), 50)]
        let active = SessionBlocks.current(events: events, now: date(12))
        XCTAssertNotNil(active)
        XCTAssertEqual(active?.tokens, 150)
        XCTAssertEqual(active?.end, date(15))
        XCTAssertNil(SessionBlocks.current(events: events, now: date(15.01)))
        XCTAssertNil(SessionBlocks.current(events: [], now: date(12)))
    }

    func testRollingWindowTokens() {
        let events: [SessionBlocks.Event] = [
            (date(-24 * 8), 999),  // 8 days ago — outside window
            (date(-24 * 3), 100),
            (date(-1), 50),
        ]
        XCTAssertEqual(SessionBlocks.tokens(inLast: 7 * 24 * 3600, events: events, now: date(0)), 150)
    }

    func testRemainingFormat() {
        XCTAssertEqual(Fmt.remaining(6120), "1:42")
        XCTAssertEqual(Fmt.remaining(45 * 60), "0:45")
        XCTAssertEqual(Fmt.remaining(5 * 3600), "5:00")
        XCTAssertEqual(Fmt.remaining(29), "0:00")
        XCTAssertEqual(Fmt.remaining(-10), "0:00")
    }

    func testPercentAndShortModel() {
        XCTAssertEqual(Fmt.percent(0.623), "62%")
        XCTAssertEqual(Fmt.percent(0), "0%")
        XCTAssertEqual(Fmt.percent(1.5), "150%")
        XCTAssertEqual(Fmt.shortModel("claude-sonnet-5-20250929"), "sonnet-5")
        XCTAssertEqual(Fmt.shortModel("claude-opus-4-5-20251101"), "opus-4-5")
        XCTAssertEqual(Fmt.shortModel("claude-sonnet-5"), "sonnet-5")
    }

    // MARK: - Hook script

    func testHookScriptContent() {
        let script = HookScript.content(defaultPort: 43917)
        XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(script.contains("43917"))
        XCTAssertTrue(script.contains("/v1/hook"))
        XCTAssertTrue(script.contains("X-TBT-Token"))
    }
}
