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
        var saber: Bool = false
        var frame: Int = 0
        var intensity: Double = 0
        var fiveTitle: String = "5h"
        var weekTitle: String = "7d"
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

    // MARK: - Micro layout (~40pt, for the collapsed Control Strip slot)

    /// Two thin stacked bars, no text — glanceable state at icon size.
    static func microImage(theme: Theme, five: Double, week: Double,
                           hasFive: Bool, hasWeek: Bool,
                           alert: Bool, alertPhase: Bool,
                           saber: Bool, frame: Int, intensity: Double,
                           height: CGFloat = 30) -> NSImage {
        let width: CGFloat = 40
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        if alert {
            (alertPhase ? theme.accent : theme.accent.withAlphaComponent(0.65)).setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 1, width: width, height: height - 2),
                         xRadius: 6, yRadius: 6).fill()
            let hand = NSAttributedString(string: "✋", attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.white,
            ])
            hand.draw(at: NSPoint(x: (width - hand.size().width) / 2,
                                  y: (height - hand.size().height) / 2))
            image.unlockFocus()
            return image
        }

        theme.background.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 1, width: width, height: height - 2),
                     xRadius: 6, yRadius: 6).fill()

        func bar(_ fraction: Double, _ hasData: Bool, _ y: CGFloat, _ offset: Int) {
            let rect = NSRect(x: 5, y: y, width: width - 10, height: 4.5)
            theme.text.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2.25, yRadius: 2.25).fill()
            guard hasData else { return }
            let clamped = max(0, min(1, fraction))
            if saber {
                drawSaberBeam(theme: theme, fraction: clamped, in: rect,
                              frame: frame &+ offset, intensity: intensity)
            } else if clamped > 0 {
                fillColor(theme: theme, fraction: clamped).setFill()
                NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY,
                                                 width: max(rect.height, rect.width * CGFloat(clamped)),
                                                 height: rect.height),
                             xRadius: 2.25, yRadius: 2.25).fill()
            }
        }
        bar(five, hasFive, 17, 0)
        bar(week, hasWeek, 8.5, 17)

        image.unlockFocus()
        return image
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
        drawInlineBar(theme: theme, label: bars.fiveTitle, fraction: bars.fiveFraction, pctText: bars.fiveLabel,
                      in: NSRect(x: x, y: 16.5, width: barWidth, height: 8),
                      saber: bars.saber, frame: bars.frame, intensity: bars.intensity)
        drawInlineBar(theme: theme, label: bars.weekTitle, fraction: bars.weekFraction, pctText: bars.weekLabel,
                      in: NSRect(x: x, y: 5, width: barWidth, height: 8),
                      saber: bars.saber, frame: bars.frame &+ 17, intensity: bars.intensity)

        image.unlockFocus()
        return image
    }

    /// A fat rounded bar with its label inside-left and percent inside-right.
    /// Text flips to the background color where it sits on the fill.
    static func drawInlineBar(theme: Theme, label: String, fraction: Double, pctText: String, in rect: NSRect,
                              saber: Bool = false, frame: Int = 0, intensity: Double = 0) {
        theme.text.withAlphaComponent(saber ? 0.12 : 0.18).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()

        let clamped = max(0, min(1, fraction))
        if saber {
            // Draws the hilt even at zero — the saber rests, it doesn't vanish.
            drawSaberBeam(theme: theme, fraction: clamped, in: rect, frame: frame, intensity: intensity)
        } else if clamped > 0 {
            fillColor(theme: theme, fraction: clamped).setFill()
            let fillRect = NSRect(x: rect.minX, y: rect.minY,
                                  width: max(rect.height, rect.width * CGFloat(clamped)),
                                  height: rect.height)
            NSBezierPath(roundedRect: fillRect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        }

        // In saber mode the label sits past the gray hilt so they never blend.
        let labelX = rect.minX + (saber ? 8 : 4)
        let labelOnFill = saber ? clamped > 0 : clamped > 0.14
        let labelColor = labelOnFill ? theme.background.withAlphaComponent(0.95) : theme.secondaryText
        let labelString = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 5.5, weight: .bold),
            .foregroundColor: labelColor,
        ])
        labelString.draw(at: NSPoint(x: labelX,
                                     y: rect.midY - labelString.size().height / 2))

        // The white-hot core reaches further left than a flat fill would, so
        // flip the percent color earlier in saber mode.
        let pctColor = clamped > (saber ? 0.55 : 0.66) ? theme.background : theme.text
        let pctString = NSAttributedString(string: pctText, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .bold),
            .foregroundColor: pctColor,
        ])
        pctString.draw(at: NSPoint(x: rect.maxX - pctString.size().width - 4,
                                   y: rect.midY - pctString.size().height / 2))
    }

    /// Lightsaber fill: gray hilt, glowing beam in the theme's fill color,
    /// bright white core, flicker + a traveling energy pulse. `frame` drives
    /// the animation; `intensity` (0…1, from the burn rate) drives how wild it is.
    static func drawSaberBeam(theme: Theme, fraction: Double, in rect: NSRect, frame: Int, intensity: Double) {
        let hiltWidth: CGFloat = min(6, rect.height * 0.75)
        theme.secondaryText.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY + 0.5,
                                         width: hiltWidth, height: rect.height - 1),
                     xRadius: 1.5, yRadius: 1.5).fill()
        guard fraction > 0 else { return }  // saber at rest: hilt only

        let f = Double(frame)
        let liveliness = 0.35 + 0.65 * max(0, min(1, intensity))
        let maxBeam = rect.width - hiltWidth
        // subtle high-frequency hum, not a hard flicker
        let hum = CGFloat((sin(f * 1.7) * 0.35 + sin(f * 3.9 + 1.4) * 0.25) * liveliness)
        var beamWidth = maxBeam * CGFloat(max(0, min(1, fraction))) + hum
        beamWidth = max(rect.height * 0.9, min(beamWidth, maxBeam))
        let jitterY = CGFloat(sin(f * 5.3) * 0.3 * liveliness)
        // slightly slimmer than the track, so it reads as a beam in a channel
        let beamRect = NSRect(x: rect.minX + hiltWidth,
                              y: rect.minY + 0.5 + jitterY,
                              width: beamWidth,
                              height: rect.height - 1)
        let radius = beamRect.height / 2
        let color = fillColor(theme: theme, fraction: fraction)

        // hairline outer glow — barely spills past the top/bottom edges
        let breathe = CGFloat(0.5 + 0.5 * sin(f * 0.9))
        color.withAlphaComponent(0.16 + 0.10 * breathe).setFill()
        NSBezierPath(roundedRect: beamRect.insetBy(dx: -1, dy: -0.5),
                     xRadius: radius + 0.5, yRadius: radius + 0.5).fill()
        // beam body
        color.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: beamRect, xRadius: radius, yRadius: radius).fill()
        // white-hot core, fat — leaves only a thin colored fringe
        let coreInset = beamRect.height * 0.22
        let coreRect = beamRect.insetBy(dx: 1.5, dy: coreInset)
        if coreRect.width > 2 {
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: coreRect,
                         xRadius: coreRect.height / 2, yRadius: coreRect.height / 2).fill()
        }
        // random energy packets streaming left → right; count, size and
        // brightness reroll every pass (deterministic hash — no RNG state)
        if beamRect.width > rect.height * 2 {
            let clampedIntensity = max(0, min(1, intensity))
            let blobCount = 1 + Int(0.5 + clampedIntensity * 1.6)
            for i in 0..<blobCount {
                let period = 16.0 / (1.0 + 0.30 * Double(i))
                let progress = f / period + Double(i) * 0.37
                let t = CGFloat(progress.truncatingRemainder(dividingBy: 1))
                let cycle = progress.rounded(.down)
                let seed = sin(cycle * 12.9898 + Double(i) * 78.233) * 43758.5453
                let rnd = CGFloat(seed - seed.rounded(.down))
                let pulseWidth = rect.height * (0.55 + 0.7 * rnd)
                let px = beamRect.minX + (beamRect.width - pulseWidth) * t
                let alpha = (0.18 + 0.32 * CGFloat(clampedIntensity)) * (0.5 + 0.5 * rnd)
                NSColor.white.withAlphaComponent(alpha).setFill()
                NSBezierPath(ovalIn: NSRect(x: px, y: beamRect.minY + 0.5,
                                            width: pulseWidth, height: beamRect.height - 1)).fill()
            }
        }
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

/// Full-width persistent bar, styled after a status-line HUD:
///   5H ▁▁▁▁▁▁  ↻1:42 · 100%   7D ▁▁▁  ↻Sat 05:59 · 13%   TODAY 1.28M·$4.32   MODEL sonnet-5
/// Thin 3.5pt tracks with the info line above; width adapts to what the
/// Touch Bar actually grants (low compression resistance, no hard 720pt).
struct FullBarsDisplay {
    struct Segment {
        var label: String
        var info: String
        var fraction: Double
    }
    struct Stack {
        var title: String
        var value: String
    }
    var segments: [Segment] = []
    var stacks: [Stack] = []
}

final class FullBarsView: NSView {
    private var theme: Theme?
    private var display = FullBarsDisplay()
    private var saber = false
    private var animFrame = 0
    private var intensity: Double = 0

    override var intrinsicContentSize: NSSize { NSSize(width: 620, height: 30) }

    func apply(display: FullBarsDisplay, theme: Theme) {
        self.display = display
        self.theme = theme
        needsDisplay = true
    }

    /// Called on every animation tick so the saber beam shimmers.
    func animate(frame: Int, saber: Bool, intensity: Double) {
        let wasSaber = self.saber
        animFrame = frame
        self.saber = saber
        self.intensity = intensity
        if saber || wasSaber {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let theme = theme, !display.segments.isEmpty else { return }
        let gap: CGFloat = 14
        let stackWidth: CGFloat = 112
        let stacksTotal = CGFloat(display.stacks.count) * (stackWidth + 6)
        let segCount = CGFloat(display.segments.count)
        let segWidth = max(90, (bounds.width - stacksTotal - gap * (segCount - 1)
            - (display.stacks.isEmpty ? 0 : gap)) / segCount)

        var x: CGFloat = 0
        for (index, segment) in display.segments.enumerated() {
            drawThinSegment(label: segment.label, info: segment.info, fraction: segment.fraction,
                            x: x, width: segWidth, theme: theme, frameOffset: index * 17)
            x += segWidth + gap
        }
        if !display.stacks.isEmpty {
            for stack in display.stacks {
                drawStack(title: stack.title, value: stack.value, x: x, width: stackWidth, theme: theme)
                x += stackWidth + 6
            }
        }
    }

    private func drawThinSegment(label: String, info: String, fraction: Double,
                                 x: CGFloat, width: CGFloat, theme: Theme, frameOffset: Int) {
        let labelString = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .bold),
            .foregroundColor: theme.secondaryText,
        ])
        labelString.draw(at: NSPoint(x: x, y: 11))
        let labelWidth = labelString.size().width + 6

        let infoString = NSAttributedString(string: info, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: theme.text,
        ])
        infoString.draw(at: NSPoint(x: x + labelWidth, y: 16))

        let trackRect = NSRect(x: x + labelWidth, y: 6, width: max(30, width - labelWidth), height: 3.5)
        theme.text.withAlphaComponent(saber ? 0.12 : 0.18).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 1.75, yRadius: 1.75).fill()

        let clamped = max(0, min(1, fraction))
        if saber {
            WidgetRenderer.drawSaberBeam(theme: theme, fraction: clamped, in: trackRect,
                                         frame: animFrame &+ frameOffset, intensity: intensity)
        } else if clamped > 0 {
            WidgetRenderer.fillColor(theme: theme, fraction: clamped).setFill()
            NSBezierPath(roundedRect: NSRect(x: trackRect.minX, y: trackRect.minY,
                                             width: max(trackRect.height, trackRect.width * CGFloat(clamped)),
                                             height: trackRect.height),
                         xRadius: 1.75, yRadius: 1.75).fill()
        }
    }

    private func drawStack(title: String, value: String, x: CGFloat, width: CGFloat, theme: Theme) {
        let titleString = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 6.5, weight: .bold),
            .foregroundColor: theme.secondaryText,
        ])
        titleString.draw(at: NSPoint(x: x, y: 19))

        let valueString = NSAttributedString(string: Fmt.truncate(value, max: 24), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: theme.text,
        ])
        valueString.draw(at: NSPoint(x: x, y: 5))
    }
}
