import AppKit
import TBTCore

/// Composes the compact Control Strip widget image (pet + two text lines).
enum WidgetRenderer {
    struct Content {
        var line1: String
        var line2: String?
        var alert: Bool
        var alertPhase: Bool
        var toast: String?

        init(line1: String, line2: String?, alert: Bool, alertPhase: Bool, toast: String?) {
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
        if let toast = content.toast, !content.alert {
            line1 = toast
            line2 = nil
        }

        let textColor: NSColor = content.alert ? .white : theme.text
        let subColor: NSColor = content.alert ? NSColor.white.withAlphaComponent(0.85) : theme.secondaryText
        let attrs1: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
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
        let width = max(56, 7 + petWidth + textWidth + 9)

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

        let tx = 7 + petWidth
        if let s2 = s2 {
            s1.draw(at: NSPoint(x: tx, y: 14))
            s2.draw(at: NSPoint(x: tx, y: 3))
        } else {
            s1.draw(at: NSPoint(x: tx, y: (height - s1.size().height) / 2))
        }

        image.unlockFocus()
        return image
    }
}
