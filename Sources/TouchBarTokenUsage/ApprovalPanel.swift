import AppKit
import TBTCore

/// Floating on-screen fallback for approvals — useful on Macs without a
/// Touch Bar and as a safety net while testing.
final class ApprovalPanelController {
    private let settings: Settings
    var onDecision: ((UUID, ApprovalDecision) -> Void)?

    private var panel: NSPanel?
    private var current: ApprovalRequest?
    private var queueCount = 0

    private var titleLabel: NSTextField?
    private var detailLabel: NSTextField?
    private var countLabel: NSTextField?
    private var countdownTimer: Timer?

    init(settings: Settings) {
        self.settings = settings
    }

    func setApprovals(_ queue: [ApprovalRequest]) {
        queueCount = queue.count
        guard settings.showPanel, let first = queue.first else {
            current = nil
            hide()
            return
        }
        current = first
        show(request: first)
    }

    // MARK: - Panel

    private func ensurePanel() -> NSPanel {
        if let existing = panel { return existing }

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 132),
                        styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                        backing: .buffered,
                        defer: false)
        p.level = .floating
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false

        let title = NSTextField(labelWithString: "")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail

        let detail = NSTextField(labelWithString: "")
        detail.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle

        let count = NSTextField(labelWithString: "")
        count.font = NSFont.systemFont(ofSize: 10)
        count.textColor = .tertiaryLabelColor

        let accept = NSButton(title: "✓ Accept", target: self, action: #selector(acceptTapped))
        accept.bezelStyle = .rounded
        accept.contentTintColor = .systemGreen
        let deny = NSButton(title: "✕ Deny", target: self, action: #selector(denyTapped))
        deny.bezelStyle = .rounded
        deny.contentTintColor = .systemRed
        let pass = NSButton(title: "Pass", target: self, action: #selector(passTapped))
        pass.bezelStyle = .rounded

        let buttons = NSStackView(views: [accept, deny, pass])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [title, detail, count, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            title.widthAnchor.constraint(lessThanOrEqualToConstant: 368),
            detail.widthAnchor.constraint(lessThanOrEqualToConstant: 368),
        ])
        p.contentView = content

        titleLabel = title
        detailLabel = detail
        countLabel = count
        panel = p
        return p
    }

    private func show(request: ApprovalRequest) {
        let p = ensurePanel()
        titleLabel?.stringValue = "🤖 Claude asks: \(request.title)"
        detailLabel?.stringValue = request.detail
        updateCountLabel()
        positionTopRight(p)
        p.orderFrontRegardless()
        startCountdown()
    }

    private func hide() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        panel?.orderOut(nil)
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateCountLabel()
        }
        RunLoop.main.add(t, forMode: .common)
        countdownTimer = t
    }

    private func updateCountLabel() {
        guard let request = current else { return }
        let remaining = max(0, Int(request.deadline.timeIntervalSinceNow.rounded()))
        var text = "auto-pass in \(remaining)s"
        if queueCount > 1 {
            text += " · \(queueCount) pending"
        }
        countLabel?.stringValue = text
    }

    private func positionTopRight(_ p: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = p.frame.size
        p.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16,
                                 y: frame.maxY - size.height - 16))
    }

    // MARK: - Actions

    @objc private func acceptTapped() { decide(.allow) }
    @objc private func denyTapped() { decide(.deny) }
    @objc private func passTapped() { decide(.pass) }

    private func decide(_ decision: ApprovalDecision) {
        guard let request = current else { return }
        onDecision?(request.id, decision)
    }
}
