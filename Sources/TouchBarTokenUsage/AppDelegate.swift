import AppKit
import Combine
import TBTCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let version = "0.6.10"

    let settings = Settings.shared
    private let hookInstaller = HookInstaller()

    private var monitor: UsageMonitor!
    private var codexMonitor: CodexMonitor!
    private var quotaFetcher: QuotaFetcher!
    private var server: ApprovalServer!
    private var touchBarController: TouchBarController!
    private var statusController: StatusItemController!
    private var panelController: ApprovalPanelController!
    private var prefsController: PreferencesWindowController?

    private var cancellable: AnyCancellable?
    private var appliedPort = 0
    private var latestServerStatus = "starting…"
    private var lastSnapshot = UsageMonitor.Snapshot()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Upgrading over a running copy: take over from the old instance.
        terminateOtherInstances()

        let token = hookInstaller.ensureRuntimeFiles(port: settings.port)
        appliedPort = settings.port

        touchBarController = TouchBarController(settings: settings)
        panelController = ApprovalPanelController(settings: settings)
        statusController = StatusItemController(settings: settings)
        monitor = UsageMonitor()
        server = ApprovalServer(config: ApprovalServer.Config(
            port: UInt16(settings.port),
            token: token,
            enabled: settings.approvalsEnabled,
            timeout: settings.approvalTimeout,
            toolPattern: settings.toolMatcher,
            autoPassPrefixes: Self.parsePrefixes(settings.autoPassPrefixes),
            notifyOnStop: settings.notifyOnStop))

        touchBarController.onDecision = { [weak self] id, decision in
            self?.server.decide(id, decision)
        }
        touchBarController.onOpenPreferences = { [weak self] in
            self?.openPreferences()
        }
        panelController.onDecision = { [weak self] id, decision in
            self?.server.decide(id, decision)
        }

        statusController.onOpenPreferences = { [weak self] in self?.openPreferences() }
        statusController.onInstallHook = { [weak self] in
            guard let self = self else { return }
            let result = self.installHookAction(matcher: self.settings.toolMatcher,
                                                extras: self.settings.notifyOnStop)
            self.touchBarController.showToast(result.hasPrefix("✓") ? "✓ Hook installed" : "⚠️ Hook install failed")
        }
        statusController.onTestApproval = { [weak self] in self?.server.injectTest() }
        statusController.onPresentBar = { [weak self] in self?.touchBarController.presentModal(auto: false) }
        statusController.hookInstalled = { [weak self] in self?.hookInstaller.isInstalled() ?? false }

        monitor.onUpdate = { [weak self] snapshot in
            guard let self = self else { return }
            self.lastSnapshot = snapshot
            self.touchBarController.update(snapshot: snapshot)
            self.statusController.update(snapshot: snapshot)
        }
        codexMonitor = CodexMonitor()
        codexMonitor.onUpdate = { [weak self] snapshot in
            self?.touchBarController.updateCodex(snapshot)
            self?.statusController.updateCodex(snapshot)
        }
        server.onQueueChanged = { [weak self] queue in
            guard let self = self else { return }
            self.touchBarController.setApprovals(queue)
            self.panelController.setApprovals(queue)
            self.statusController.setApprovalCount(queue.count)
        }
        server.onToast = { [weak self] text in
            self?.touchBarController.showToast(text)
        }
        server.onServerState = { [weak self] status in
            self?.latestServerStatus = status
            self?.statusController.serverStatus = status
        }

        quotaFetcher = QuotaFetcher()
        quotaFetcher.onUpdate = { [weak self] quota, status in
            self?.monitor.setQuota(quota)
            self?.statusController.quotaStatus = status
        }
        statusController.onRefreshQuota = { [weak self] in self?.quotaFetcher.retryNow() }

        touchBarController.setUp()
        statusController.touchBarAvailable = touchBarController.available
        server.start()
        monitor.setCustomLimits(fiveHour: settings.fiveHourLimitTokens, weekly: settings.weeklyLimitTokens)
        monitor.start()
        codexMonitor.start()
        quotaFetcher.start()

        cancellable = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.applySettingsChange()
                }
            }

        // Show the window on the first launch of every new version. The app
        // lives in the menu bar only, so a silent launch after an upgrade
        // looks like nothing happened.
        let lastRunVersion = UserDefaults.standard.string(forKey: "lastRunVersion")
        if lastRunVersion != Self.version {
            UserDefaults.standard.set(Self.version, forKey: "lastRunVersion")
            openPreferences()
        }
    }

    /// Double-clicking the app in Finder/Dock while it's already running
    /// should always surface the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPreferences()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBarController?.tearDown()
        server?.stop()
        monitor?.stop()
        codexMonitor?.stop()
        quotaFetcher?.stop()
    }

    private func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        for app in others {
            app.terminate()
        }
    }

    // MARK: - Settings propagation

    private static func parsePrefixes(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func applySettingsChange() {
        server.config.enabled = settings.approvalsEnabled
        server.config.timeout = settings.approvalTimeout
        server.config.toolPattern = settings.toolMatcher
        server.config.autoPassPrefixes = Self.parsePrefixes(settings.autoPassPrefixes)
        server.config.notifyOnStop = settings.notifyOnStop

        if settings.port != appliedPort, settings.port > 0, settings.port <= 65535 {
            appliedPort = settings.port
            server.config.port = UInt16(settings.port)
            server.config.token = hookInstaller.ensureRuntimeFiles(port: settings.port)
            server.start()
        }

        monitor.setCustomLimits(fiveHour: settings.fiveHourLimitTokens, weekly: settings.weeklyLimitTokens)
        touchBarController.applySettings()
        statusController.settingsChanged()
    }

    // MARK: - Preferences & hook

    private func openPreferences() {
        if prefsController == nil {
            let deps = PrefsDeps(
                installHook: { [weak self] matcher, extras in
                    self?.installHookAction(matcher: matcher, extras: extras) ?? "App not ready"
                },
                removeHook: { [weak self] in
                    self?.removeHookAction() ?? "App not ready"
                },
                hookInstalled: { [weak self] in
                    self?.hookInstaller.isInstalled() ?? false
                },
                testApproval: { [weak self] in
                    self?.server.injectTest()
                },
                serverStatus: { [weak self] in
                    self?.latestServerStatus ?? "unknown"
                },
                touchBarAvailable: { [weak self] in
                    self?.touchBarController.available ?? false
                },
                dataDirFound: { [weak self] in
                    self?.lastSnapshot.dataDirFound ?? false
                }
            )
            prefsController = PreferencesWindowController(settings: settings, deps: deps)
        }
        prefsController?.show()
    }

    private func installHookAction(matcher: String, extras: Bool) -> String {
        _ = hookInstaller.ensureRuntimeFiles(port: settings.port)
        do {
            try hookInstaller.install(matcher: matcher, includeExtraEvents: extras)
            return "✓ Hook installed — new Claude Code sessions will ask on the Touch Bar."
        } catch {
            return "Install failed: \(error.localizedDescription)"
        }
    }

    private func removeHookAction() -> String {
        do {
            try hookInstaller.remove()
            return "Hook removed from ~/.claude/settings.json."
        } catch {
            return "Remove failed: \(error.localizedDescription)"
        }
    }
}
