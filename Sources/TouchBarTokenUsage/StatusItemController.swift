import AppKit
import TBTCore

/// Menu bar item: live usage summary + quick actions. Works on every Mac,
/// Touch Bar or not.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let settings: Settings
    private let statusItem: NSStatusItem

    private var snapshot = UsageMonitor.Snapshot()
    private var codexSnapshot = CodexMonitor.Snapshot()
    private var approvalCount = 0

    var onOpenPreferences: (() -> Void)?
    var onInstallHook: (() -> Void)?
    var onTestApproval: (() -> Void)?
    var onPresentBar: (() -> Void)?
    var hookInstalled: (() -> Bool)?
    var serverStatus = "starting…"
    var quotaStatus = "starting…"
    var touchBarAvailable = false

    init(settings: Settings) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.image = Self.icon(for: settings.pet)
        statusItem.button?.imagePosition = .imageLeft
        refreshTitle()
    }

    /// Menu bar icon follows the selected pet; robot when pets are off.
    static func icon(for pet: PetKind) -> NSImage {
        PetSprites.templateIcon(for: pet) ?? robotImage()
    }

    /// Little template robot: antenna, head with punched-out eyes, chin bar.
    static func robotImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.black.setFill()
        // antenna stem + tip
        NSRect(x: 8.3, y: 13.0, width: 1.4, height: 2.6).fill()
        NSBezierPath(ovalIn: NSRect(x: 7.8, y: 15.2, width: 2.4, height: 2.4)).fill()
        // head with even-odd eye holes
        let head = NSBezierPath(roundedRect: NSRect(x: 2.2, y: 4.4, width: 13.6, height: 8.8),
                                xRadius: 2.6, yRadius: 2.6)
        head.append(NSBezierPath(ovalIn: NSRect(x: 5.3, y: 7.4, width: 2.9, height: 2.9)))
        head.append(NSBezierPath(ovalIn: NSRect(x: 9.8, y: 7.4, width: 2.9, height: 2.9)))
        head.windingRule = .evenOdd
        head.fill()
        // chin bar
        NSBezierPath(roundedRect: NSRect(x: 5.2, y: 1.4, width: 7.6, height: 2.2),
                     xRadius: 1.1, yRadius: 1.1).fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    func update(snapshot: UsageMonitor.Snapshot) {
        self.snapshot = snapshot
        refreshTitle()
    }

    func updateCodex(_ snapshot: CodexMonitor.Snapshot) {
        codexSnapshot = snapshot
        refreshTitle()
    }

    func setApprovalCount(_ count: Int) {
        approvalCount = count
        refreshTitle()
    }

    func settingsChanged() {
        statusItem.button?.image = Self.icon(for: settings.pet)
        refreshTitle()
    }

    private func refreshTitle() {
        guard let button = statusItem.button else { return }
        if approvalCount > 0 {
            button.title = " ✋\(approvalCount)"
        } else if settings.menuBarShowsTokens {
            // "63%/60%" = 5-hour window / weekly window. In "both" mode the
            // title alternates providers every few seconds (C … / X …).
            let showCodex = settings.provider == "codex"
                || (settings.provider == "both" && Int(Date().timeIntervalSince1970 / 4) % 2 == 1)
            let fiveHas = showCodex ? codexSnapshot.fiveHourHasData : snapshot.fiveHourHasData
            let weekHas = showCodex ? codexSnapshot.weeklyHasData : snapshot.weeklyHasData
            if fiveHas || weekHas {
                let five = fiveHas ? Fmt.percent(showCodex ? codexSnapshot.fiveHourFraction : snapshot.fiveHourFraction) : "–"
                let week = weekHas ? Fmt.percent(showCodex ? codexSnapshot.weeklyFraction : snapshot.weeklyFraction) : "–"
                let prefix = settings.provider == "both" ? (showCodex ? "X " : "C ") : ""
                button.title = " \(prefix)\(five)/\(week)"
            } else {
                button.title = " " + Fmt.abbrev(snapshot.today.totalTokens)
            }
        } else {
            button.title = ""
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        func info(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        func action(_ title: String, _ selector: Selector, key: String = "", enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.target = self
            item.isEnabled = enabled
            menu.addItem(item)
        }

        info("Touch Bar Token Usage v\(AppDelegate.version)")
        menu.addItem(.separator())

        let today = snapshot.today
        info("Today: \(Fmt.abbrev(today.totalTokens)) tokens · \(Fmt.money(today.costUSD))")
        info("   ↑ in \(Fmt.abbrev(today.inputTokens)) · ↓ out \(Fmt.abbrev(today.outputTokens))")
        info("   cache write \(Fmt.abbrev(today.cacheCreationTokens)) · read \(Fmt.abbrev(today.cacheReadTokens))")
        let month = snapshot.month
        info("This month: \(Fmt.abbrev(month.totalTokens)) tokens · \(Fmt.money(month.costUSD))")
        info("Burn rate: \(Fmt.rate(snapshot.ratePerMinute))")
        let fiveReset = AppFmt.resetDisplay(resetAt: snapshot.fiveHourResetAt,
                                            hasData: snapshot.fiveHourHasData,
                                            clock: settings.resetStyleIsClock)
        let weekReset = AppFmt.resetDisplay(resetAt: snapshot.weeklyResetAt,
                                            hasData: snapshot.weeklyHasData,
                                            clock: settings.resetStyleIsClock)
        if snapshot.quotaSource == "api" {
            if snapshot.fiveHourHasData {
                info("5-hour limit: \(Fmt.percent(snapshot.fiveHourFraction))"
                    + (fiveReset.map { " · \($0)" } ?? ""))
            }
            if snapshot.weeklyHasData {
                info("Weekly (all models): \(Fmt.percent(snapshot.weeklyFraction))"
                    + (weekReset.map { " · \($0)" } ?? ""))
            }
            info("Quota: live from Claude API ✓")
        } else {
            if snapshot.fiveHourHasData {
                var line = "5-hour block: \(Fmt.abbrev(snapshot.fiveHourTokens)) / \(Fmt.abbrev(snapshot.fiveHourLimit))"
                    + " (\(Fmt.percent(snapshot.fiveHourFraction))\(snapshot.fiveHourLimitIsAuto ? " of your max" : ""))"
                if let reset = fiveReset {
                    line += " · \(reset)"
                }
                info(line)
            } else {
                info("5-hour block: \(Fmt.abbrev(snapshot.fiveHourTokens)) (no history yet)")
            }
            if snapshot.weeklyHasData {
                info("Weekly (7d): \(Fmt.abbrev(snapshot.weeklyTokens)) / \(Fmt.abbrev(snapshot.weeklyLimit))"
                    + " (\(Fmt.percent(snapshot.weeklyFraction))\(snapshot.weeklyLimitIsAuto ? " of your max" : ""))")
            }
            info("Quota: \(quotaStatus)")
        }
        if let model = snapshot.lastModel {
            info("Model: \(model)")
        }
        if !snapshot.dataDirFound {
            info("⚠️ ~/.claude/projects not found — run Claude Code once")
        }
        if settings.providerIncludesCodex {
            menu.addItem(.separator())
            if codexSnapshot.dataDirFound {
                let fiveReset = AppFmt.resetDisplay(resetAt: codexSnapshot.fiveHourResetAt,
                                                    hasData: codexSnapshot.fiveHourHasData,
                                                    clock: settings.resetStyleIsClock)
                let weekReset = AppFmt.resetDisplay(resetAt: codexSnapshot.weeklyResetAt,
                                                    hasData: codexSnapshot.weeklyHasData,
                                                    clock: settings.resetStyleIsClock)
                info("Codex 5h: \(codexSnapshot.fiveHourHasData ? Fmt.percent(codexSnapshot.fiveHourFraction) : "no data")"
                    + (fiveReset.map { " · \($0)" } ?? ""))
                info("Codex weekly: \(codexSnapshot.weeklyHasData ? Fmt.percent(codexSnapshot.weeklyFraction) : "no data")"
                    + (weekReset.map { " · \($0)" } ?? ""))
                var todayLine = "Codex today: \(Fmt.abbrev(codexSnapshot.todayTokens)) tokens"
                if let model = codexSnapshot.lastModel {
                    todayLine += " · \(model)"
                }
                info(todayLine)
            } else {
                info("Codex: ~/.codex/sessions not found — run Codex CLI once")
            }
        }
        menu.addItem(.separator())

        let widgetItem = NSMenuItem(title: touchBarAvailable ? "Show Touch Bar Widget" : "Show Touch Bar Widget (no Touch Bar)",
                                    action: #selector(toggleWidget),
                                    keyEquivalent: "")
        widgetItem.target = self
        widgetItem.state = settings.showWidget ? .on : .off
        widgetItem.isEnabled = touchBarAvailable
        menu.addItem(widgetItem)
        action("Open Panel on Touch Bar", #selector(presentBar), enabled: touchBarAvailable)
        menu.addItem(.separator())

        info("Approval server: \(serverStatus)")
        info("Claude hook: \((hookInstalled?() ?? false) ? "installed ✓" : "not installed")")
        action("Send Test Approval Request", #selector(testApproval))
        action("Install / Update Claude Hook", #selector(installHook))
        menu.addItem(.separator())

        action("Preferences…", #selector(openPrefs), key: ",")
        action("Open GitHub Page", #selector(openGitHub))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Touch Bar Token Usage",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.isEnabled = true
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func toggleWidget() { settings.showWidget.toggle() }
    @objc private func presentBar() { onPresentBar?() }
    @objc private func testApproval() { onTestApproval?() }
    @objc private func installHook() { onInstallHook?() }
    @objc private func openPrefs() { onOpenPreferences?() }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/qazwsx-maker/Touch-Bar-Token-Usage") {
            NSWorkspace.shared.open(url)
        }
    }
}
