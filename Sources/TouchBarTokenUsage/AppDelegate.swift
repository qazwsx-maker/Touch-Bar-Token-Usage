import AppKit
import Combine
import TBTCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let version = "0.2.0"

    let settings = Settings.shared
    private let hookInstaller = HookInstaller()

    private var monitor: UsageMonitor!
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

        touchBarController.setUp()
        statusController.touchBarAvailable = touchBarController.available
        server.start()
        monitor.setCustomLimits(fiveHour: settings.fiveHourLimitTokens, weekly: settings.weeklyLimitTokens)
        monitor.start()

        cancellable = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.applySettingsChange()
                }
            }

        if !UserDefaults.standard.bool(forKey: "didFirstRun") {
            UserDefaults.standard.set(true, forKey: "didFirstRun")
            openPreferences()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBarController?.tearDown()
        server?.stop()
        monitor?.stop()
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
