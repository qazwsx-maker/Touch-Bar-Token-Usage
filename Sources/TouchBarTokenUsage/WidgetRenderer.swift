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

/// Full-width persistent HUD, provider-card style:
///   [✳ Claude ●Live │ 5h 85% ▮▮▮▯ 15%L │ RESET 2h 07m]  [⬡ GPT Codex ●Live │ …]
/// Each provider gets a badge, its used percentages, capsule bars where the
/// spent part is colored and the remainder stays pale (with an "N%L" tokens-
/// left label), and a reset countdown. Width adapts to what the bar grants.
struct FullBarsDisplay {
    enum Kind { case claude, codex }
    enum Tone { case live, estimate, off }
    struct Row {
        var title: String     // "5h" / "Wk"
        var fraction: Double
        var hasData: Bool
        var usedText: String  // "85%" / "—"
        var leftText: String  // "15%L" / "—"
    }
    struct Cluster {
        var kind: Kind
        var name: String
        var statusText: String  // "Live" / "Est." / "—"
        var tone: Tone
        var rows: [Row]
        var resetText: String   // "2h 07m" / "—"
    }
    var clusters: [Cluster] = []
}

final class FullBarsView: NSView {
    private var display = FullBarsDisplay()

    override var intrinsicContentSize: NSSize { NSSize(width: 540, height: 30) }

    func apply(display: FullBarsDisplay, theme: Theme) {
        self.display = display
        needsDisplay = true
    }

    /// Kept for the controller's animation tick; this layout is static.
    func animate(frame: Int, saber: Bool, intensity: Double) {}

    // Fixed HUD palette (the Touch Bar is always black glass).
    private static let claudeBrand = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)   // #D97757
    private static let yellow = NSColor(red: 1.00, green: 0.84, blue: 0.04, alpha: 1)        // #FFD60A
    private static let orange = NSColor(red: 1.00, green: 0.62, blue: 0.04, alpha: 1)        // #FF9F0A
    private static let green = NSColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1)         // #30D158
    private static let red = NSColor(red: 1.00, green: 0.27, blue: 0.23, alpha: 1)           // #FF453A
    private static let remainder = NSColor(red: 0.72, green: 0.78, blue: 0.87, alpha: 0.85)  // pale capsule
    private static let secondary = NSColor.white.withAlphaComponent(0.55)

    private func fillColor(kind: FullBarsDisplay.Kind, rowIndex: Int, fraction: Double) -> NSColor {
        if fraction >= 0.9 { return Self.red }
        switch kind {
        case .claude: return rowIndex == 0 ? Self.yellow : Self.orange
        case .codex: return Self.green
        }
    }

    private func toneColor(_ tone: FullBarsDisplay.Tone) -> NSColor {
        switch tone {
        case .live: return Self.green
        case .estimate: return Self.yellow
        case .off: return NSColor.white.withAlphaComponent(0.35)
        }
    }

    private func str(_ text: String, size: CGFloat, weight: NSFont.Weight,
                     color: NSColor, mono: Bool = false) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                        : NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ])
    }

    // Per-cluster measured column widths.
    private struct Columns {
        var name: CGFloat
        var pct: CGFloat
        var left: CGFloat
        var reset: CGFloat
        var fixed: CGFloat  // everything except the flexible bars
    }

    private func measure(_ cluster: FullBarsDisplay.Cluster) -> Columns {
        let nameW = max(str(cluster.name, size: 10.5, weight: .bold, color: .white).size().width,
                        10 + str(cluster.statusText, size: 7.5, weight: .semibold, color: .white).size().width)
        var pctW: CGFloat = 0
        var leftW: CGFloat = 0
        for row in cluster.rows {
            let used = str(row.usedText, size: 10.5, weight: .bold, color: .white, mono: true).size().width
            pctW = max(pctW, 16 + used)
            leftW = max(leftW, str(row.leftText, size: 7.5, weight: .medium, color: .white, mono: true).size().width)
        }
        let resetW = max(str("RESET", size: 6.5, weight: .bold, color: .white).size().width,
                         str(cluster.resetText, size: 11, weight: .bold, color: .white, mono: true).size().width)
        // badge 20 + 5 | name | 8 sep 8 | pct | 6 bars 4 | left | 8 sep 8 | reset
        let fixed = 20 + 5 + nameW + 8 + 1 + 8 + pctW + 6 + 4 + leftW + 8 + 1 + 8 + resetW
        return Columns(name: nameW, pct: pctW, left: leftW, reset: resetW, fixed: fixed)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !display.clusters.isEmpty else { return }
        let clusterGap: CGFloat = 16
        let columns = display.clusters.map(measure)
        let fixedTotal = columns.reduce(0) { $0 + $1.fixed }
        let count = CGFloat(display.clusters.count)
        let barsWidth = max(36, (bounds.width - fixedTotal - clusterGap * (count - 1) - 2) / count)

        var x: CGFloat = 0
        for (cluster, cols) in zip(display.clusters, columns) {
            x = drawCluster(cluster, cols: cols, barsWidth: barsWidth, at: x)
            x += clusterGap
        }
    }

    /// Draws one provider card, returns the x just past its right edge.
    private func drawCluster(_ cluster: FullBarsDisplay.Cluster, cols: Columns,
                             barsWidth: CGFloat, at x0: CGFloat) -> CGFloat {
        var x = x0

        let badgeRect = NSRect(x: x, y: 5, width: 20, height: 20)
        switch cluster.kind {
        case .claude: drawClaudeBadge(in: badgeRect)
        case .codex: drawCodexBadge(in: badgeRect)
        }
        x += 25

        // Name over "● Live".
        str(cluster.name, size: 10.5, weight: .bold, color: .white)
            .draw(at: NSPoint(x: x, y: 15.5))
        let dotColor = toneColor(cluster.tone)
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: x + 1, y: 6, width: 5, height: 5)).fill()
        str(cluster.statusText, size: 7.5, weight: .semibold, color: Self.secondary)
            .draw(at: NSPoint(x: x + 10, y: 4))
        x += cols.name + 8

        drawSeparator(at: x)
        x += 9

        // Two rows: titles + bold used percents.
        let rowTextY: [(title: CGFloat, used: CGFloat)] = [(17.3, 15.7), (3.8, 2.2)]
        for (index, row) in cluster.rows.prefix(2).enumerated() {
            str(row.title, size: 8, weight: .semibold, color: Self.secondary)
                .draw(at: NSPoint(x: x, y: rowTextY[index].title))
            str(row.usedText, size: 10.5, weight: .bold, color: .white, mono: true)
                .draw(at: NSPoint(x: x + 16, y: rowTextY[index].used))
        }
        x += cols.pct + 6

        // Capsule bars + "%L" left labels.
        let trackY: [CGFloat] = [19.5, 6]
        for (index, row) in cluster.rows.prefix(2).enumerated() {
            let track = NSRect(x: x, y: trackY[index], width: barsWidth, height: 5)
            drawCapsuleBar(row: row, kind: cluster.kind, rowIndex: index, in: track)
            str(row.leftText, size: 7.5, weight: .medium, color: Self.secondary, mono: true)
                .draw(at: NSPoint(x: x + barsWidth + 4, y: trackY[index] - 2))
        }
        x += barsWidth + 4 + cols.left + 8

        drawSeparator(at: x)
        x += 9

        str("RESET", size: 6.5, weight: .bold, color: Self.secondary)
            .draw(at: NSPoint(x: x, y: 18.5))
        str(cluster.resetText, size: 11, weight: .bold, color: .white, mono: true)
            .draw(at: NSPoint(x: x, y: 3.5))
        x += cols.reset

        return x
    }

    private func drawSeparator(at x: CGFloat) {
        NSColor.white.withAlphaComponent(0.14).setFill()
        NSRect(x: x, y: 4, width: 1, height: 22).fill()
    }

    /// Used part in the row color, remainder as a pale capsule with a small gap.
    private func drawCapsuleBar(row: FullBarsDisplay.Row, kind: FullBarsDisplay.Kind,
                                rowIndex: Int, in rect: NSRect) {
        let radius = rect.height / 2
        guard row.hasData else {
            NSColor.white.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return
        }
        let fraction = max(0, min(1, row.fraction))
        let usedWidth: CGFloat = fraction > 0 ? max(rect.height, rect.width * CGFloat(fraction)) : 0
        if usedWidth > 0 {
            fillColor(kind: kind, rowIndex: rowIndex, fraction: fraction).setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY,
                                             width: usedWidth, height: rect.height),
                         xRadius: radius, yRadius: radius).fill()
        }
        let remainderX = rect.minX + usedWidth + (usedWidth > 0 ? 2 : 0)
        if rect.maxX - remainderX > 3 {
            Self.remainder.setFill()
            NSBezierPath(roundedRect: NSRect(x: remainderX, y: rect.minY,
                                             width: rect.maxX - remainderX, height: rect.height),
                         xRadius: radius, yRadius: radius).fill()
        }
    }

    /// Claude: terracotta rounded square with a white starburst.
    private func drawClaudeBadge(in rect: NSRect) {
        Self.claudeBrand.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.30
        NSColor.white.setStroke()
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 4
            let ray = NSBezierPath()
            ray.lineWidth = 1.8
            ray.lineCapStyle = .round
            ray.move(to: NSPoint(x: center.x - cos(angle) * radius, y: center.y - sin(angle) * radius))
            ray.line(to: NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            ray.stroke()
        }
    }

    /// Codex: white rounded square with a black knot-style hexagon ring.
    private func drawCodexBadge(in rect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.28
        let hex = NSBezierPath()
        hex.lineWidth = 2.0
        hex.lineJoinStyle = .round
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3 + .pi / 6
            let point = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if i == 0 { hex.move(to: point) } else { hex.line(to: point) }
        }
        hex.close()
        NSColor.black.setStroke()
        hex.stroke()
    }
}
