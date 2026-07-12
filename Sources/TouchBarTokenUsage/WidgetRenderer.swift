import AppKit
import TBTCore

/// Composes the compact Control Strip widget image:
/// [pet] [5h/7d limit bars] [model + info line]  (bars/model optional).
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
        var line1 = content.line1
        var line2 = content.line2
        var bars = content.bars
        if let toast = content.toast, !content.alert {
            line1 = toast
            line2 = nil
            bars = nil
        }
        if content.alert {
            bars = nil
        }

        let textColor: NSColor = content.alert ? .white : theme.text
        let subColor: NSColor = content.alert ? NSColor.white.withAlphaComponent(0.85) : theme.secondaryText
        let attrs1: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: bars == nil ? 11.5 : 9.5, weight: .semibold),
            .foregroundColor: textColor,
        ]
        let attrs2: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
            .foregroundColor: subColor,
        ]
        let s1 = NSAttributedString(string: line1, attributes: attrs1)
        let s2: NSAttributedString? = line2.map { NSAttributedString(string: $0, attributes: attrs2) }

        let petWidth: CGFloat = petImage.map { $0.size.width + 5 } ?? 0
        let barsWidth: CGFloat = bars == nil ? 0 : 72
        let textWidth = max(s1.size().width, s2?.size().width ?? 0)
        let width = max(56, 7 + petWidth + barsWidth + textWidth + 9)

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
            petImage.draw(in: NSRect(x: 6,
                                     y: (height - petImage.size.height) / 2,
                                     width: petImage.size.width,
                                     height: petImage.size.height))
        }

        var x = 7 + petWidth
        if let bars = bars {
            drawBarRow(theme: theme, label: "5h", fraction: bars.fiveFraction, text: bars.fiveLabel,
                       x: x, y: 16.5, width: barsWidth - 6)
            drawBarRow(theme: theme, label: "7d", fraction: bars.weekFraction, text: bars.weekLabel,
                       x: x, y: 5.5, width: barsWidth - 6)
            x += barsWidth
        }

        if let s2 = s2 {
            s1.draw(at: NSPoint(x: x, y: 14.5))
            s2.draw(at: NSPoint(x: x, y: 3))
        } else {
            s1.draw(at: NSPoint(x: x, y: (height - s1.size().height) / 2))
        }

        image.unlockFocus()
        return image
    }

    /// One row: tiny label, progress track, percent text.
    private static func drawBarRow(theme: Theme, label: String, fraction: Double, text: String,
                                   x: CGFloat, y: CGFloat, width: CGFloat) {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 6.5, weight: .semibold),
            .foregroundColor: theme.secondaryText,
        ]
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 6.5, weight: .semibold),
            .foregroundColor: theme.text,
        ]
        let labelString = NSAttributedString(string: label, attributes: labelAttrs)
        let pctString = NSAttributedString(string: text, attributes: pctAttrs)

        let labelWidth: CGFloat = 11
        let pctWidth: CGFloat = 21
        let trackWidth = max(10, width - labelWidth - pctWidth - 4)
        let barHeight: CGFloat = 5

        labelString.draw(at: NSPoint(x: x, y: y - 1.5))

        let trackRect = NSRect(x: x + labelWidth, y: y, width: trackWidth, height: barHeight)
        theme.text.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

        let clamped = max(0, min(1, fraction))
        if clamped > 0 {
            let fillColor: NSColor
            if clamped >= 0.9 {
                fillColor = theme.bad
            } else if clamped >= 0.75 {
                fillColor = .systemOrange
            } else {
                fillColor = theme.accent
            }
            let fillWidth = max(barHeight, trackWidth * CGFloat(clamped))
            let fillRect = NSRect(x: trackRect.minX, y: y, width: fillWidth, height: barHeight)
            fillColor.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        }

        pctString.draw(at: NSPoint(x: trackRect.maxX + 3, y: y - 1.5))
    }
}
