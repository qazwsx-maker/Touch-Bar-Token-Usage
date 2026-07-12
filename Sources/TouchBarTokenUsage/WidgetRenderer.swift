import AppKit
import TBTCore

/// Composes the compact Control Strip widget image.
///
/// The Control Strip only gives tray items ~100pt, so the compact layout is
/// strictly budgeted: [small pet][two fat bars with labels+percent inside].
/// Model/token text lives in the expanded bar and the menu bar instead.
enum WidgetRenderer {
    struct Bars {
        var fiveFraction: Double
        var fiveLabel: String
        var weekFraction: Double
        var weekLabel: String
    }

    struct Content {
        var bars: Bars?
        var line1: String
        var line2: String?
        var alert: Bool
        var alertPhase: Bool
        var toast: String?

        init(bars: Bars? = nil, line1: String, line2: String?, alert: Bool, alertPhase: Bool, toast: String?) {
            self.bars = bars
            self.line1 = line1
            self.line2 = line2
            self.alert = alert
            self.alertPhase = alertPhase
            self.toast = toast
        }
    }

    static func stripImage(theme: Theme, petImage: NSImage?, content: Content, height: CGFloat = 30) -> NSImage {
        if content.alert || content.toast != nil || content.bars == nil {
            return textImage(theme: theme, petImage: petImage, content: content, height: height)
        }
        return barsImage(theme: theme, petImage: petImage, bars: content.bars!, height: height)
    }

    // MARK: - Compact bars layout (fits the Control Strip budget)

    private static func barsImage(theme: Theme, petImage: NSImage?, bars: Bars, height: CGFloat) -> NSImage {
        let petWidth: CGFloat = petImage.map { $0.size.width + 4 } ?? 0
        let barWidth: CGFloat = 64
        let width = 5 + petWidth + barWidth + 5

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        theme.background.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 1, width: width, height: height - 2),
                     xRadius: 6, yRadius: 6).fill()

        if let petImage = petImage {
            petImage.draw(in: NSRect(x: 4,
                                     y: (height - petImage.size.height) / 2,
                                     width: petImage.size.width,
                                     height: petImage.size.height))
        }

        let x = 5 + petWidth
        drawInlineBar(theme: theme, label: "5h", fraction: bars.fiveFraction, pctText: bars.fiveLabel,
                      in: NSRect(x: x, y: 16.5, width: barWidth, height: 8))
        drawInlineBar(theme: theme, label: "7d", fraction: bars.weekFraction, pctText: bars.weekLabel,
                      in: NSRect(x: x, y: 5, width: barWidth, height: 8))

        image.unlockFocus()
        return image
    }

    /// A fat rounded bar with its label inside-left and percent inside-right.
    /// Text flips to the background color where it sits on the fill.
    static func drawInlineBar(theme: Theme, label: String, fraction: Double, pctText: String, in rect: NSRect) {
        theme.text.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()

        let clamped = max(0, min(1, fraction))
        if clamped > 0 {
            fillColor(theme: theme, fraction: clamped).setFill()
            let fillRect = NSRect(x: rect.minX, y: rect.minY,
                                  width: max(rect.height, rect.width * CGFloat(clamped)),
                                  height: rect.height)
            NSBezierPath(roundedRect: fillRect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        }

        let labelColor = clamped > 0.14 ? theme.background.withAlphaComponent(0.95) : theme.secondaryText
        let labelString = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 5.5, weight: .bold),
            .foregroundColor: labelColor,
        ])
        labelString.draw(at: NSPoint(x: rect.minX + 4,
                                     y: rect.midY - labelString.size().height / 2))

        let pctColor = clamped > 0.66 ? theme.background : theme.text
        let pctString = NSAttributedString(string: pctText, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .bold),
            .foregroundColor: pctColor,
        ])
        pctString.draw(at: NSPoint(x: rect.maxX - pctString.size().width - 4,
                                   y: rect.midY - pctString.size().height / 2))
    }

    static func fillColor(theme: Theme, fraction: Double) -> NSColor {
        if fraction >= 0.9 { return theme.bad }
        if fraction >= 0.75 { return .systemOrange }
        return theme.accent
    }

    // MARK: - Text layout (alerts, toasts, bars-off mode)

    private static func textImage(theme: Theme, petImage: NSImage?, content: Content, height: CGFloat) -> NSImage {
        var line1 = content.line1
        var line2 = content.line2
        if let toast = content.toast, !content.alert {
            line1 = toast
            line2 = nil
        }

        let textColor: NSColor = content.alert ? .white : theme.text
        let subColor: NSColor = content.alert ? NSColor.white.withAlphaComponent(0.85) : theme.secondaryText
        let attrs1: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: textColor,
        ]
        let attrs2: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
            .foregroundColor: subColor,
        ]
        let s1 = NSAttributedString(string: line1, attributes: attrs1)
        let s2: NSAttributedString? = line2.map { NSAttributedString(string: $0, attributes: attrs2) }

        let petWidth: CGFloat = petImage.map { $0.size.width + 5 } ?? 0
        let textWidth = max(s1.size().width, s2?.size().width ?? 0)
        let width = max(56, 6 + petWidth + textWidth + 8)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        let background: NSColor
        if content.alert {
            background = content.alertPhase ? theme.accent : theme.accent.withAlphaComponent(0.65)
        } else {
            background = theme.background
        }
        background.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 1, width: width, height: height - 2),
                     xRadius: 6, yRadius: 6).fill()

        if let petImage = petImage {
            petImage.draw(in: NSRect(x: 5,
                                     y: (height - petImage.size.height) / 2,
                                     width: petImage.size.width,
                                     height: petImage.size.height))
        }

        let tx = 6 + petWidth
        if let s2 = s2 {
            s1.draw(at: NSPoint(x: tx, y: 14.5))
            s2.draw(at: NSPoint(x: tx, y: 3))
        } else {
            s1.draw(at: NSPoint(x: tx, y: (height - s1.size().height) / 2))
        }

        image.unlockFocus()
        return image
    }
}

/// Full-width 5h/weekly bars for the expanded (tap-to-open) touch bar:
/// [pet]  5h [==============      ] 63%   —   Wk [======    ] 60%
final class FullBarsView: NSView {
    private var theme: Theme?
    private var fiveFraction: Double = 0
    private var weekFraction: Double = 0
    private var fiveText = "–"
    private var weekText = "–"
    private var fiveDetail = ""

    override var intrinsicContentSize: NSSize { NSSize(width: 720, height: 30) }

    func apply(snapshot: UsageMonitor.Snapshot, theme: Theme, resetDisplay: String) {
        self.theme = theme
        fiveFraction = snapshot.fiveHourFraction
        weekFraction = snapshot.weeklyFraction
        fiveText = snapshot.fiveHourLimit > 0 ? Fmt.percent(snapshot.fiveHourFraction) : "–"
        weekText = snapshot.weeklyLimit > 0 ? Fmt.percent(snapshot.weeklyFraction) : "–"
        fiveDetail = resetDisplay
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let theme = theme else { return }
        let gap: CGFloat = 26
        let segWidth = (bounds.width - gap) / 2
        drawSegment(label: "5h", fraction: fiveFraction, pctText: fiveText, detail: fiveDetail,
                    in: NSRect(x: 0, y: 0, width: segWidth, height: bounds.height), theme: theme)
        theme.secondaryText.withAlphaComponent(0.45).setFill()
        NSRect(x: segWidth + gap / 2 - 4, y: bounds.midY - 1, width: 8, height: 2).fill()
        drawSegment(label: "Wk", fraction: weekFraction, pctText: weekText, detail: "",
                    in: NSRect(x: segWidth + gap, y: 0, width: segWidth, height: bounds.height), theme: theme)
    }

    private func drawSegment(label: String, fraction: Double, pctText: String, detail: String,
                             in rect: NSRect, theme: Theme) {
        let labelString = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: theme.secondaryText,
        ])
        var pctDisplay = pctText
        if !detail.isEmpty {
            pctDisplay += " " + detail
        }
        let pctString = NSAttributedString(string: pctDisplay, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: theme.text,
        ])

        let labelWidth: CGFloat = 27
        let pctWidth = pctString.size().width + 8
        let trackX = rect.minX + labelWidth
        let trackWidth = max(40, rect.width - labelWidth - pctWidth)
        let barHeight: CGFloat = 12
        let barY = rect.midY - barHeight / 2

        labelString.draw(at: NSPoint(x: rect.minX,
                                     y: rect.midY - labelString.size().height / 2))

        theme.text.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: NSRect(x: trackX, y: barY, width: trackWidth, height: barHeight),
                     xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

        let clamped = max(0, min(1, fraction))
        if clamped > 0 {
            WidgetRenderer.fillColor(theme: theme, fraction: clamped).setFill()
            NSBezierPath(roundedRect: NSRect(x: trackX, y: barY,
                                             width: max(barHeight, trackWidth * CGFloat(clamped)),
                                             height: barHeight),
                         xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        }

        pctString.draw(at: NSPoint(x: trackX + trackWidth + 8,
                                   y: rect.midY - pctString.size().height / 2))
    }
}
