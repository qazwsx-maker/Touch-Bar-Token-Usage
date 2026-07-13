import AppKit
import TBTCore
import TBPrivate

extension NSTouchBarItem.Identifier {
    static let tbtPet = NSTouchBarItem.Identifier("com.qazwsxmaker.tbtu.pet")
    static let tbtStats = NSTouchBarItem.Identifier("com.qazwsxmaker.tbtu.stats")
    static let tbtFullBars = NSTouchBarItem.Identifier("com.qazwsxmaker.tbtu.fullbars")
    static let tbtApprovalInfo = NSTouchBarItem.Identifier("com.qazwsxmaker.tbtu.approvalInfo")
    static let tbtAccept = NSTouchBarItem.Identifier("com.qazwsxmaker.tbtu.accept")
    static let tbtDeny = NSTouchBarItem.Identifier("com.qazwsxmaker.tbtu.deny")
    static let tbtPass = NSTouchBarItem.Identifier("com.qazwsxmaker.tbtu.pass")
    static let tbtPrefs = NSTouchBarItem.Identifier("com.qazwsxmaker.tbtu.prefs")
    static let tbtClose = NSTouchBarItem.Identifier("com.qazwsxmaker.tbtu.close")
    static let tbtCollapse = NSTouchBarItem.Identifier("com.qazwsxmaker.tbtu.collapse")
}

/// Owns the Control Strip widget and the full-width modal bar.
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let trayItemIdentifier = "com.qazwsxmaker.tbtu.strip"

    private let settings: Settings
    var onDecision: ((UUID, ApprovalDecision) -> Void)?
    var onOpenPreferences: (() -> Void)?

    private(set) var available = false

    private var stripItem: NSCustomTouchBarItem?
    private var stripButton: NSButton?
    private var modalBar: NSTouchBar?
    private var modalPresented = false
    private var presentedAutomatically = false

    private var snapshot = UsageMonitor.Snapshot()
    private var codexSnapshot = CodexMonitor.Snapshot()
    private var approvals: [ApprovalRequest] = []
    private var toast: String?
    private var toastExpiry: Date?

    private var animTimer: Timer?
    private var representTimer: Timer?
    private var frameIndex = 0
    private var alertPhase = false
    private var lastInterval: TimeInterval = 0
    private var appliedModeFull = false

    private var petView: AnimatedPetView?
    private var statsLabel: NSTextField?
    private var fullBarsView: FullBarsView?
    private var approvalLabel: NSTextField?
    private var passItem: NSButtonTouchBarItem?

    init(settings: Settings) {
        self.settings = settings
        super.init()
    }

    // MARK: - Lifecycle

    func setUp() {
        available = TBPIsAvailable()
        guard available else { return }

        let item = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier(Self.trayItemIdentifier))
        let button = NSButton(image: NSImage(size: NSSize(width: 80, height: 30)),
                              target: self,
                              action: #selector(stripTapped))
        button.isBordered = false
        button.imageScaling = .scaleNone
        item.view = button
        stripItem = item
        stripButton = button

        TBPAddSystemTrayItem(item)
        TBPSetControlStripPresence(Self.trayItemIdentifier, settings.showWidget)
        appliedModeFull = settings.widgetModeIsFull
        TBPSetShowsCloseBoxWhenFrontMost(!appliedModeFull)

        restartAnimation()
        redrawStrip()

        if appliedModeFull {
            presentModal(auto: false)
        }
        // Persistent mode: if the system dismisses our modal bar (esc, app
        // takeovers, …), quietly bring it back.
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.available, self.settings.widgetModeIsFull else { return }
            if !(self.modalBar?.isVisible ?? false) {
                self.presentModal(auto: false)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        representTimer = t
    }

    func tearDown() {
        animTimer?.invalidate()
        representTimer?.invalidate()
        guard available, let item = stripItem else { return }
        dismissModal()
        TBPSetControlStripPresence(Self.trayItemIdentifier, false)
        TBPRemoveSystemTrayItem(item)
        stripItem = nil
    }

    func applySettings() {
        guard available else { return }
        TBPSetControlStripPresence(Self.trayItemIdentifier, settings.showWidget)
        refreshSaberState()
        petView?.kind = settings.pet
        petView?.color = PetSprites.tint(for: settings.pet, themeColor: settings.theme.pet)

        let modeFull = settings.widgetModeIsFull
        if modeFull != appliedModeFull {
            appliedModeFull = modeFull
            TBPSetShowsCloseBoxWhenFrontMost(!modeFull)
            if modeFull {
                presentModal(auto: false)
            } else {
                dismissModal()
            }
        }

        if modalPresented {
            refreshModalItems()
        }
        redrawStrip()
    }

    // MARK: - Inputs

    func update(snapshot: UsageMonitor.Snapshot) {
        self.snapshot = snapshot
        refreshSaberState()
        redrawStrip()
        if modalPresented {
            updateModalContent()
        }
    }

    func updateCodex(_ snapshot: CodexMonitor.Snapshot) {
        codexSnapshot = snapshot
        guard settings.providerIncludesCodex else { return }
        refreshSaberState()
        redrawStrip()
        if modalPresented {
            updateModalContent()
        }
    }

    /// Burn rate across the providers currently displayed.
    private var combinedRate: Double {
        var rate = 0.0
        if settings.providerIncludesClaude { rate += snapshot.ratePerMinute }
        if settings.providerIncludesCodex { rate += codexSnapshot.ratePerMinute }
        return rate
    }

    /// In "both" mode the tiny widgets alternate providers every 4s.
    private var showCodexNow: Bool {
        switch settings.provider {
        case "codex": return true
        case "both": return Int(Date().timeIntervalSince1970 / 4) % 2 == 1
        default: return false
        }
    }

    func setApprovals(_ queue: [ApprovalRequest]) {
        let hadPending = !approvals.isEmpty
        let hasNew = queue.contains { req in !approvals.contains { $0.id == req.id } }
        approvals = queue

        if hasNew {
            if settings.playSound {
                NSSound(named: "Tink")?.play()
            }
            if settings.autoPresentOnRequest && available && !modalPresented {
                presentModal(auto: true)
            }
        }
        if approvals.isEmpty && hadPending && modalPresented && presentedAutomatically {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self = self, self.approvals.isEmpty, self.presentedAutomatically else { return }
                self.dismissModal()
            }
        }
        if modalPresented {
            refreshModalItems()
        }
        redrawStrip()
    }

    func showToast(_ text: String) {
        toast = text
        toastExpiry = Date().addingTimeInterval(5)
        redrawStrip()
    }

    // MARK: - Animation

    private var saberEngaged = false

    /// Auto mode uses hysteresis (ignite ≥900 tok/min, extinguish <650) so a
    /// rate hovering near the threshold doesn't strobe between styles.
    private func refreshSaberState() {
        switch settings.barStyle {
        case "saber":
            saberEngaged = true
        case "classic":
            saberEngaged = false
        default:
            let rate = combinedRate
            if saberEngaged {
                if rate < 650 { saberEngaged = false }
            } else if rate >= 900 {
                saberEngaged = true
            }
        }
    }

    private var saberOn: Bool { saberEngaged }

    private var saberIntensity: Double {
        min(1, combinedRate / 3000)
    }

    private var currentFPS: Double {
        let rate = combinedRate
        let base: Double
        if !approvals.isEmpty {
            base = 8
        } else if rate < 30 {
            base = 2
        } else {
            base = min(4 + rate / 800.0, 13)
        }
        var fps = max(1, base * settings.energy.multiplier)
        // Keep the beam shimmering — but only when a beam is actually visible.
        let beamVisible = settings.showLimitBars || (modalPresented && settings.expandedLayoutIsBars)
        if saberOn && beamVisible {
            fps = max(fps, 6)
        }
        return fps
    }

    private func restartAnimation() {
        animTimer?.invalidate()
        let interval = 1.0 / currentFPS
        lastInterval = interval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }

    private func tick() {
        frameIndex &+= 1
        alertPhase.toggle()
        if let expiry = toastExpiry, expiry < Date() {
            toast = nil
            toastExpiry = nil
        }
        redrawStrip()
        petView?.fps = currentFPS
        if modalPresented {
            fullBarsView?.animate(frame: frameIndex, saber: saberOn, intensity: saberIntensity)
            if !approvals.isEmpty {
                updateCountdown()
            }
        }
        let desired = 1.0 / currentFPS
        if abs(desired - lastInterval) > 0.02 {
            restartAnimation()
        }
    }

    // MARK: - Strip widget

    private func redrawStrip() {
        guard available, let button = stripButton else { return }
        let theme = settings.theme
        let isAlert = !approvals.isEmpty

        // Full-width HUD mode: the tray slot only gets ~40pt in the collapsed
        // Control Strip, so show a glanceable micro widget there.
        if settings.widgetModeIsFull {
            let codex = showCodexNow
            button.image = WidgetRenderer.microImage(theme: theme,
                                                     five: codex ? codexSnapshot.fiveHourFraction : snapshot.fiveHourFraction,
                                                     week: codex ? codexSnapshot.weeklyFraction : snapshot.weeklyFraction,
                                                     hasFive: codex ? codexSnapshot.fiveHourHasData : snapshot.fiveHourHasData,
                                                     hasWeek: codex ? codexSnapshot.weeklyHasData : snapshot.weeklyHasData,
                                                     alert: isAlert,
                                                     alertPhase: alertPhase,
                                                     saber: saberOn,
                                                     frame: frameIndex,
                                                     intensity: saberIntensity)
            return
        }

        let running = isAlert || combinedRate >= 30
        // Compact mode: drop the pet from the bars layout — the expanded
        // Control Strip grants only ~76pt (measured on hardware).
        let barsCompact = settings.showLimitBars && !isAlert && toast == nil
        let petImage = barsCompact ? nil : PetSprites.image(kind: settings.pet,
                                                            frame: frameIndex,
                                                            running: running,
                                                            color: isAlert ? .white : PetSprites.tint(for: settings.pet, themeColor: theme.pet),
                                                            cell: 2)
        button.image = WidgetRenderer.stripImage(theme: theme, petImage: petImage, content: stripContent())
    }

    private func stripContent() -> WidgetRenderer.Content {
        if let first = approvals.first {
            let line2 = approvals.count > 1 ? "\(approvals.count) pending · tap" : "tap to review"
            return WidgetRenderer.Content(line1: Fmt.truncate(first.title, max: 24),
                                          line2: line2,
                                          alert: true,
                                          alertPhase: alertPhase,
                                          toast: nil)
        }

        // Bars mode: the compact widget is bars-only (model/token text lives
        // in the expanded bar and the menu bar — the strip is too narrow).
        if settings.showLimitBars, toast == nil {
            let codex = showCodexNow
            let fiveFrac = codex ? codexSnapshot.fiveHourFraction : snapshot.fiveHourFraction
            let fiveHas = codex ? codexSnapshot.fiveHourHasData : snapshot.fiveHourHasData
            let fiveResetAt = codex ? codexSnapshot.fiveHourResetAt : snapshot.fiveHourResetAt
            let weekFrac = codex ? codexSnapshot.weeklyFraction : snapshot.weeklyFraction
            let weekHas = codex ? codexSnapshot.weeklyHasData : snapshot.weeklyHasData

            var fiveLabel = fiveHas ? Fmt.percent(fiveFrac) : "–"
            // The strip has no room for both — alternate % and reset time
            // inside the 5h bar every few seconds.
            if let reset = AppFmt.resetDisplay(resetAt: fiveResetAt,
                                               hasData: fiveHas,
                                               clock: settings.resetStyleIsClock),
               Int(Date().timeIntervalSince1970 / 4) % 2 == 1 {
                fiveLabel = reset
            }
            let both = settings.provider == "both"
            let bars = WidgetRenderer.Bars(
                fiveFraction: fiveFrac,
                fiveLabel: fiveLabel,
                weekFraction: weekFrac,
                weekLabel: weekHas ? Fmt.percent(weekFrac) : "–",
                saber: saberOn,
                frame: frameIndex,
                intensity: saberIntensity,
                fiveTitle: both ? (codex ? "X5" : "C5") : "5h",
                weekTitle: both ? (codex ? "X7" : "C7") : "7d")
            return WidgetRenderer.Content(bars: bars, line1: "", line2: nil,
                                          alert: false, alertPhase: false, toast: nil)
        }

        let today = snapshot.today
        let metricText: String
        switch settings.displayMetric {
        case .totalTokens:
            metricText = Fmt.abbrev(today.totalTokens)
        case .inOut:
            metricText = "↑" + Fmt.abbrev(today.inputTokens + today.cacheCreationTokens)
                + " ↓" + Fmt.abbrev(today.outputTokens)
        case .cost:
            metricText = Fmt.money(today.costUSD)
        case .rate:
            metricText = Fmt.rate(snapshot.ratePerMinute)
        }

        let line1: String
        if settings.showModelOnBar, let model = snapshot.lastModel {
            line1 = Fmt.truncate(Fmt.shortModel(model), max: 14)
        } else {
            line1 = metricText
        }

        var parts: [String] = []
        if settings.showModelOnBar {
            parts.append(metricText)
        }
        if settings.showCostLine && settings.displayMetric != .cost {
            parts.append(Fmt.money(today.costUSD))
        }
        if settings.showRateLine && settings.displayMetric != .rate {
            parts.append(Fmt.rate(snapshot.ratePerMinute))
        }
        let line2 = parts.isEmpty ? nil : parts.joined(separator: " · ")
        return WidgetRenderer.Content(line1: line1, line2: line2,
                                      alert: false, alertPhase: false, toast: toast)
    }

    @objc private func stripTapped() {
        if settings.widgetModeIsFull {
            presentModal(auto: false)
            return
        }
        if modalPresented {
            dismissModal()
        } else {
            presentModal(auto: false)
        }
    }

    // MARK: - Modal bar

    func presentModal(auto: Bool) {
        guard available else { return }
        if modalBar == nil {
            let bar = NSTouchBar()
            bar.delegate = self
            modalBar = bar
        }
        refreshModalItems()
        // Trust the bar's actual visibility, not our flag — the system can
        // dismiss a modal bar behind our back (esc, other takeovers).
        let visible = modalBar?.isVisible ?? false
        if !visible {
            TBPPresentSystemModal(modalBar!, Self.trayItemIdentifier)
            presentedAutomatically = auto
        }
        modalPresented = true
    }

    func dismissModal() {
        guard let bar = modalBar, modalPresented else { return }
        TBPDismissSystemModal(bar)
        modalPresented = false
        presentedAutomatically = false
    }

    private func refreshModalItems() {
        guard let bar = modalBar else { return }
        let trailing: NSTouchBarItem.Identifier = settings.widgetModeIsFull ? .tbtCollapse : .tbtClose
        var ids: [NSTouchBarItem.Identifier]
        if !approvals.isEmpty {
            ids = [.tbtPet, .tbtStats, .flexibleSpace, .tbtApprovalInfo, .tbtDeny, .tbtPass, .tbtAccept, trailing]
        } else if settings.expandedLayoutIsBars {
            // No Settings button here — the provider cards use every point.
            ids = [.tbtPet, .tbtFullBars, trailing]
        } else {
            ids = [.tbtPet, .tbtStats, .flexibleSpace, .tbtPrefs, trailing]
        }
        if bar.defaultItemIdentifiers != ids {
            bar.defaultItemIdentifiers = ids
        }
        updateModalContent()
    }

    private func updateModalContent() {
        let today = snapshot.today
        let clock = settings.resetStyleIsClock
        let includeClaude = settings.providerIncludesClaude
        let includeCodex = settings.providerIncludesCodex

        func resetText(_ resetAt: Date?, _ hasData: Bool) -> String {
            AppFmt.resetDisplay(resetAt: resetAt, hasData: hasData, clock: clock) ?? ""
        }
        func info(_ fraction: Double, _ hasData: Bool, _ reset: String) -> String {
            guard hasData else { return "no data" }
            return reset.isEmpty ? Fmt.percent(fraction) : reset + " · " + Fmt.percent(fraction)
        }

        let cFiveReset = resetText(snapshot.fiveHourResetAt, snapshot.fiveHourHasData)
        let cWeekReset = resetText(snapshot.weeklyResetAt, snapshot.weeklyHasData)
        let xFiveReset = resetText(codexSnapshot.fiveHourResetAt, codexSnapshot.fiveHourHasData)
        let xWeekReset = resetText(codexSnapshot.weeklyResetAt, codexSnapshot.weeklyHasData)

        // Stats text line (approval header + the "stats" expanded layout).
        var text: String
        if approvals.isEmpty {
            var pieces: [String] = []
            if includeClaude {
                let prefix = includeCodex ? "C·" : ""
                if snapshot.fiveHourHasData {
                    pieces.append("\(prefix)5h \(info(snapshot.fiveHourFraction, true, cFiveReset))")
                }
                if snapshot.weeklyHasData {
                    pieces.append("\(prefix)7d \(info(snapshot.weeklyFraction, true, cWeekReset))")
                }
            }
            if includeCodex {
                let prefix = includeClaude ? "X·" : ""
                if codexSnapshot.fiveHourHasData {
                    pieces.append("\(prefix)5h \(info(codexSnapshot.fiveHourFraction, true, xFiveReset))")
                }
                if codexSnapshot.weeklyHasData {
                    pieces.append("\(prefix)7d \(info(codexSnapshot.weeklyFraction, true, xWeekReset))")
                }
            }
            if includeClaude {
                pieces.append("today \(Fmt.abbrev(today.totalTokens)) \(Fmt.money(today.costUSD))")
            } else {
                pieces.append("today \(Fmt.abbrev(codexSnapshot.todayTokens)) tok")
            }
            pieces.append(Fmt.rate(combinedRate))
            if includeClaude, let model = snapshot.lastModel {
                pieces.append(Fmt.shortModel(model))
            } else if !includeClaude, let model = codexSnapshot.lastModel {
                pieces.append(model)
            }
            text = pieces.joined(separator: "  ·  ")
        } else {
            text = "Today \(Fmt.abbrev(today.totalTokens)) · \(Fmt.money(today.costUSD))"
        }
        statsLabel?.stringValue = text

        // Full-width HUD: one provider card per enabled provider.
        func hudRow(_ title: String, _ fraction: Double, _ hasData: Bool) -> FullBarsDisplay.Row {
            let pct = Int((max(0, min(1, fraction)) * 100).rounded())
            return .init(title: title, fraction: fraction, hasData: hasData,
                         usedText: hasData ? "\(pct)%" : "—",
                         leftText: hasData ? "\(max(0, 100 - pct))%L" : "—")
        }
        // First upcoming reset wins: the 5h block if it has one, else weekly.
        func hudReset(_ candidates: [(Date?, Bool)]) -> String {
            for (date, hasData) in candidates {
                if hasData, let date = date, date > Date() {
                    return Fmt.hoursMinutes(date.timeIntervalSinceNow)
                }
            }
            return "—"
        }

        var display = FullBarsDisplay()
        if includeClaude {
            let hasAny = snapshot.fiveHourHasData || snapshot.weeklyHasData
            let live = snapshot.quotaSource == "api"
            display.clusters.append(.init(
                kind: .claude,
                name: "Claude",
                statusText: live ? "Live" : (hasAny ? "Est." : "—"),
                tone: live ? .live : (hasAny ? .estimate : .off),
                rows: [hudRow("5h", snapshot.fiveHourFraction, snapshot.fiveHourHasData),
                       hudRow("Wk", snapshot.weeklyFraction, snapshot.weeklyHasData)],
                resetText: hudReset([(snapshot.fiveHourResetAt, snapshot.fiveHourHasData),
                                     (snapshot.weeklyResetAt, snapshot.weeklyHasData)])))
        }
        if includeCodex {
            let hasAny = codexSnapshot.fiveHourHasData || codexSnapshot.weeklyHasData
            display.clusters.append(.init(
                kind: .codex,
                name: "GPT Codex",
                statusText: hasAny ? "Live" : "—",
                tone: hasAny ? .live : .off,
                rows: [hudRow("5h", codexSnapshot.fiveHourFraction, codexSnapshot.fiveHourHasData),
                       hudRow("Wk", codexSnapshot.weeklyFraction, codexSnapshot.weeklyHasData)],
                resetText: hudReset([(codexSnapshot.fiveHourResetAt, codexSnapshot.fiveHourHasData),
                                     (codexSnapshot.weeklyResetAt, codexSnapshot.weeklyHasData)])))
        }
        fullBarsView?.apply(display: display, theme: settings.theme)

        if let first = approvals.first {
            var info = "🤖 \(first.title): \(first.detail)"
            if approvals.count > 1 {
                info = "(\(approvals.count)) " + info
            }
            approvalLabel?.stringValue = info
        }
        updateCountdown()

        petView?.kind = settings.pet
        petView?.color = PetSprites.tint(for: settings.pet, themeColor: settings.theme.pet)
        petView?.running = !approvals.isEmpty || combinedRate >= 30
        petView?.fps = currentFPS
    }

    private func updateCountdown() {
        guard let first = approvals.first else { return }
        let remaining = max(0, Int(first.deadline.timeIntervalSinceNow.rounded()))
        passItem?.title = "Pass \(remaining)s"
    }

    // MARK: - NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .tbtPet:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let view = AnimatedPetView(frame: NSRect(x: 0, y: 0, width: 44, height: 30))
            view.kind = settings.pet
            view.color = PetSprites.tint(for: settings.pet, themeColor: settings.theme.pet)
            view.fps = currentFPS
            view.start()
            petView = view
            item.view = view
            return item

        case .tbtStats:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            label.textColor = .white
            statsLabel = label
            item.view = label
            updateModalContent()
            return item

        case .tbtFullBars:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let view = FullBarsView(frame: NSRect(x: 0, y: 0, width: 620, height: 30))
            // Let the bar squeeze this view instead of dropping it when the
            // Touch Bar is narrower than our ideal width — and let it stretch
            // to claim whatever width is spare (the cards' bars flex).
            view.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(240), for: .horizontal)
            view.setContentHuggingPriority(NSLayoutConstraint.Priority(240), for: .horizontal)
            fullBarsView = view
            item.view = view
            updateModalContent()
            return item

        case .tbtApprovalInfo:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 430).isActive = true
            approvalLabel = label
            item.view = label
            updateModalContent()
            return item

        case .tbtAccept:
            let item = NSButtonTouchBarItem(identifier: identifier,
                                            title: "✓ Accept",
                                            target: self,
                                            action: #selector(acceptTapped))
            item.bezelColor = .systemGreen
            return item

        case .tbtDeny:
            let item = NSButtonTouchBarItem(identifier: identifier,
                                            title: "✕ Deny",
                                            target: self,
                                            action: #selector(denyTapped))
            item.bezelColor = .systemRed
            return item

        case .tbtPass:
            let item = NSButtonTouchBarItem(identifier: identifier,
                                            title: "Pass",
                                            target: self,
                                            action: #selector(passTapped))
            passItem = item
            updateCountdown()
            return item

        case .tbtPrefs:
            return NSButtonTouchBarItem(identifier: identifier,
                                        title: "⚙ Settings",
                                        target: self,
                                        action: #selector(prefsTapped))

        case .tbtClose:
            return NSButtonTouchBarItem(identifier: identifier,
                                        title: "✕",
                                        target: self,
                                        action: #selector(closeTapped))

        case .tbtCollapse:
            return NSButtonTouchBarItem(identifier: identifier,
                                        title: "−",
                                        target: self,
                                        action: #selector(collapseTapped))

        default:
            return nil
        }
    }

    // MARK: - Actions

    @objc private func acceptTapped() { decideFirst(.allow) }
    @objc private func denyTapped() { decideFirst(.deny) }
    @objc private func passTapped() { decideFirst(.pass) }

    private func decideFirst(_ decision: ApprovalDecision) {
        guard let first = approvals.first else { return }
        onDecision?(first.id, decision)
    }

    @objc private func prefsTapped() {
        dismissModal()
        onOpenPreferences?()
    }

    @objc private func closeTapped() {
        dismissModal()
    }

    @objc private func collapseTapped() {
        // Switch to compact mode; applySettings (via the settings observer)
        // dismisses the persistent bar.
        settings.widgetMode = "compact"
    }
}
