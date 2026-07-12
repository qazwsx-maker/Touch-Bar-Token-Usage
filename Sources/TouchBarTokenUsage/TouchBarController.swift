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
    private var approvals: [ApprovalRequest] = []
    private var toast: String?
    private var toastExpiry: Date?

    private var animTimer: Timer?
    private var frameIndex = 0
    private var alertPhase = false
    private var lastInterval: TimeInterval = 0

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
        TBPSetShowsCloseBoxWhenFrontMost(true)

        restartAnimation()
        redrawStrip()
    }

    func tearDown() {
        animTimer?.invalidate()
        guard available, let item = stripItem else { return }
        dismissModal()
        TBPSetControlStripPresence(Self.trayItemIdentifier, false)
        TBPRemoveSystemTrayItem(item)
        stripItem = nil
    }

    func applySettings() {
        guard available else { return }
        TBPSetControlStripPresence(Self.trayItemIdentifier, settings.showWidget)
        petView?.kind = settings.pet
        petView?.color = settings.theme.pet
        if modalPresented {
            refreshModalItems()
        }
        redrawStrip()
    }

    // MARK: - Inputs

    func update(snapshot: UsageMonitor.Snapshot) {
        self.snapshot = snapshot
        redrawStrip()
        if modalPresented {
            updateModalContent()
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

    private var currentFPS: Double {
        let rate = snapshot.ratePerMinute
        let base: Double
        if !approvals.isEmpty {
            base = 8
        } else if rate < 30 {
            base = 2
        } else {
            base = min(4 + rate / 800.0, 13)
        }
        return max(1, base * settings.energy.multiplier)
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
        if modalPresented, !approvals.isEmpty {
            updateCountdown()
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
        let running = isAlert || snapshot.ratePerMinute >= 30
        // The Control Strip budget is ~100pt: shrink the pet when bars are on.
        let petCell: CGFloat = (settings.showLimitBars && !isAlert && toast == nil) ? 1.6 : 2
        let petImage = PetSprites.image(kind: settings.pet,
                                        frame: frameIndex,
                                        running: running,
                                        color: isAlert ? .white : theme.pet,
                                        cell: petCell)
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
            var fiveLabel = snapshot.fiveHourLimit > 0 ? Fmt.percent(snapshot.fiveHourFraction) : "–"
            // The strip has no room for both — alternate % and reset time
            // inside the 5h bar every few seconds.
            if let reset = AppFmt.resetDisplay(resetAt: snapshot.fiveHourResetAt,
                                               limit: snapshot.fiveHourLimit,
                                               clock: settings.resetStyleIsClock),
               Int(Date().timeIntervalSince1970 / 4) % 2 == 1 {
                fiveLabel = reset
            }
            let bars = WidgetRenderer.Bars(
                fiveFraction: snapshot.fiveHourFraction,
                fiveLabel: fiveLabel,
                weekFraction: snapshot.weeklyFraction,
                weekLabel: snapshot.weeklyLimit > 0 ? Fmt.percent(snapshot.weeklyFraction) : "–")
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
        if !modalPresented {
            TBPPresentSystemModal(modalBar!, Self.trayItemIdentifier)
            modalPresented = true
            presentedAutomatically = auto
        }
    }

    func dismissModal() {
        guard let bar = modalBar, modalPresented else { return }
        TBPDismissSystemModal(bar)
        modalPresented = false
        presentedAutomatically = false
    }

    private func refreshModalItems() {
        guard let bar = modalBar else { return }
        var ids: [NSTouchBarItem.Identifier]
        if !approvals.isEmpty {
            ids = [.tbtPet, .tbtStats, .flexibleSpace, .tbtApprovalInfo, .tbtDeny, .tbtPass, .tbtAccept, .tbtClose]
        } else if settings.expandedLayoutIsBars {
            ids = [.tbtPet, .tbtFullBars, .tbtPrefs, .tbtClose]
        } else {
            ids = [.tbtPet, .tbtStats, .flexibleSpace, .tbtPrefs, .tbtClose]
        }
        if bar.defaultItemIdentifiers != ids {
            bar.defaultItemIdentifiers = ids
        }
        updateModalContent()
    }

    private func updateModalContent() {
        let today = snapshot.today
        var text: String
        if approvals.isEmpty {
            var pieces: [String] = []
            if snapshot.fiveHourLimit > 0 {
                var five = "5h \(Fmt.percent(snapshot.fiveHourFraction))"
                if let reset = AppFmt.resetDisplay(resetAt: snapshot.fiveHourResetAt,
                                                   limit: snapshot.fiveHourLimit,
                                                   clock: settings.resetStyleIsClock) {
                    five += " " + reset
                }
                pieces.append(five)
            }
            if snapshot.weeklyLimit > 0 {
                pieces.append("7d \(Fmt.percent(snapshot.weeklyFraction))")
            }
            pieces.append("today \(Fmt.abbrev(today.totalTokens)) \(Fmt.money(today.costUSD))")
            pieces.append(Fmt.rate(snapshot.ratePerMinute))
            if let model = snapshot.lastModel {
                pieces.append(Fmt.shortModel(model))
            }
            text = pieces.joined(separator: "  ·  ")
        } else {
            text = "Today \(Fmt.abbrev(today.totalTokens)) · \(Fmt.money(today.costUSD))"
        }
        statsLabel?.stringValue = text
        let resetDisplay = AppFmt.resetDisplay(resetAt: snapshot.fiveHourResetAt,
                                               limit: snapshot.fiveHourLimit,
                                               clock: settings.resetStyleIsClock) ?? ""
        fullBarsView?.apply(snapshot: snapshot, theme: settings.theme, resetDisplay: resetDisplay)

        if let first = approvals.first {
            var info = "🤖 \(first.title): \(first.detail)"
            if approvals.count > 1 {
                info = "(\(approvals.count)) " + info
            }
            approvalLabel?.stringValue = info
        }
        updateCountdown()

        petView?.kind = settings.pet
        petView?.color = settings.theme.pet
        petView?.running = !approvals.isEmpty || snapshot.ratePerMinute >= 30
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
            view.color = settings.theme.pet
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
            let view = FullBarsView(frame: NSRect(x: 0, y: 0, width: 720, height: 30))
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
}
