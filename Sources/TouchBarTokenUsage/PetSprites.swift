import AppKit

enum PetKind: String, CaseIterable, Identifiable {
    case penguin
    case dragon
    case ghost
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .penguin: return "Penguin"
        case .dragon: return "Dragon"
        case .ghost: return "Ghost"
        case .none: return "None"
        }
    }

    var emoji: String {
        switch self {
        case .penguin: return "🐧"
        case .dragon: return "🐲"
        case .ghost: return "👻"
        case .none: return "⌁"
        }
    }
}

struct PetSprite {
    let run: [[String]]
    let idle: [[String]]
}

/// Pixel-art pets rendered as single-color silhouettes ('#' = pixel,
/// '.' = transparent — gaps double as eyes).
enum PetSprites {
    static func sprite(for kind: PetKind) -> PetSprite? {
        switch kind {
        case .penguin: return penguin
        case .dragon: return dragon
        case .ghost: return ghost
        case .none: return nil
        }
    }

    // MARK: - Penguin (eye holes at the top)

    private static let penguin = PetSprite(
        run: [
            [
                "....####....",
                "...######...",
                "...#.##.#...",
                "...######...",
                "..########..",
                ".#########..",
                ".#########..",
                "..########..",
                "...######...",
                "..##....##..",
                "..##........",
            ],
            [
                "....####....",
                "...######...",
                "...#.##.#...",
                "...######...",
                "..########..",
                "..#########.",
                "..#########.",
                "..########..",
                "...######...",
                "..##....##..",
                "........##..",
            ],
        ],
        idle: [
            [
                "....####....",
                "...######...",
                "...#.##.#...",
                "...######...",
                "..########..",
                "..########..",
                "..########..",
                "..########..",
                "...######...",
                "..##....##..",
            ],
            [
                "....####....",
                "...######...",
                "...#.##.#...",
                "...######...",
                ".##########.",
                ".##########.",
                "..########..",
                "..########..",
                "...######...",
                "..##....##..",
            ],
        ]
    )

    // MARK: - Dragon

    private static let dragon = PetSprite(
        run: [
            [
                "......##..........",
                ".....####.........",
                "......##......#.#.",
                ".......#.....####.",
                ".#.....#..########",
                "..##..############",
                "...##############.",
                "....###########...",
                ".....##.....##....",
            ],
            [
                "..................",
                "..............#.#.",
                ".....######..####.",
                ".#....############",
                "..##..############",
                "...##############.",
                "....###########...",
                ".....##.....##....",
                "..................",
            ],
            [
                "..............#.#.",
                ".............####.",
                ".#........########",
                "..##..############",
                "...##############.",
                "....###########...",
                "....####...####...",
                ".....##.....##....",
                ".....#.......#....",
            ],
        ],
        idle: [
            [
                "..............#.#.",
                ".............####.",
                "......####..######",
                ".#...#############",
                "..##.#############",
                "...##############.",
                "....###########...",
                ".....##.....##....",
            ],
            [
                "..............#.#.",
                ".............####.",
                "......####..######",
                "..#..#############",
                "..##.#############",
                "...##############.",
                "....###########...",
                ".....##.....##....",
            ],
        ]
    )

    // MARK: - Ghost (eyes are transparent holes)

    private static let ghost = PetSprite(
        run: [
            [
                "....####....",
                "..########..",
                ".##########.",
                ".##.####.##.",
                ".##########.",
                ".##########.",
                ".##########.",
                ".#.##.##.#..",
            ],
            [
                "............",
                "....####....",
                "..########..",
                ".##########.",
                ".##.####.##.",
                ".##########.",
                ".##########.",
                "..#.##.#.##.",
            ],
        ],
        idle: [
            [
                "....####....",
                "..########..",
                ".##########.",
                ".##.####.##.",
                ".##########.",
                ".##########.",
                ".##########.",
                ".#.##.##.#..",
            ],
            [
                "............",
                "....####....",
                "..########..",
                ".##########.",
                ".##.####.##.",
                ".##########.",
                ".##########.",
                "..#.##.#.##.",
            ],
        ]
    )

    // MARK: - Rendering

    private static var cache: [String: NSImage] = [:]
    private static var iconCache: [String: NSImage] = [:]

    /// 18×18 template (menu-bar) icon of the pet's idle pose.
    static func templateIcon(for kind: PetKind) -> NSImage? {
        guard let sprite = sprite(for: kind) else { return nil }
        if let cached = iconCache[kind.rawValue] { return cached }
        let frames = sprite.idle.isEmpty ? sprite.run : sprite.idle
        guard let map = frames.first else { return nil }
        let rows = map.count
        let cols = map.map { $0.count }.max() ?? 1
        let cell = min(18 / CGFloat(cols), 16 / CGFloat(rows))
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.black.setFill()
        let originX = (18 - CGFloat(cols) * cell) / 2
        let originY = (18 - CGFloat(rows) * cell) / 2
        for (r, rowString) in map.enumerated() {
            for (c, ch) in rowString.enumerated() where ch == "#" {
                NSRect(x: originX + CGFloat(c) * cell,
                       y: originY + CGFloat(rows - 1 - r) * cell,
                       width: cell,
                       height: cell).fill()
            }
        }
        image.unlockFocus()
        image.isTemplate = true
        iconCache[kind.rawValue] = image
        return image
    }

    /// Renders one frame as a tinted pixel image. Returns nil for `.none`.
    static func image(kind: PetKind, frame: Int, running: Bool, color: NSColor, cell: CGFloat = 2) -> NSImage? {
        guard let sprite = sprite(for: kind) else { return nil }
        let frames = running ? sprite.run : sprite.idle
        guard !frames.isEmpty else { return nil }
        let index = ((frame % frames.count) + frames.count) % frames.count
        let key = "\(kind.rawValue)|\(index)|\(running)|\(color.hexString)|\(cell)"
        if let cached = cache[key] { return cached }

        let map = frames[index]
        let rows = map.count
        let cols = map.map { $0.count }.max() ?? 1
        let size = NSSize(width: CGFloat(cols) * cell, height: CGFloat(rows) * cell)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        for (r, rowString) in map.enumerated() {
            for (c, ch) in rowString.enumerated() where ch == "#" {
                let rect = NSRect(x: CGFloat(c) * cell,
                                  y: CGFloat(rows - 1 - r) * cell,
                                  width: cell,
                                  height: cell)
                rect.fill()
            }
        }
        image.unlockFocus()
        if cache.count > 512 { cache.removeAll() }
        cache[key] = image
        return image
    }
}

/// Small self-animating pet view used in the modal touch bar and previews.
final class AnimatedPetView: NSView {
    var kind: PetKind = .penguin { didSet { needsDisplay = true } }
    var color: NSColor = .white { didSet { needsDisplay = true } }
    var running = true { didSet { needsDisplay = true } }
    var fps: Double = 6 {
        didSet {
            if abs(fps - oldValue) > 0.01, timer != nil {
                startTimer()
            }
        }
    }

    private var frameIndex = 0
    private var timer: Timer?

    override var intrinsicContentSize: NSSize { NSSize(width: 44, height: 30) }

    func start() {
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        timer?.invalidate()
        let interval = 1.0 / max(0.5, min(fps, 20))
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.frameIndex &+= 1
            self.needsDisplay = true
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image = PetSprites.image(kind: kind, frame: frameIndex, running: running, color: color) else { return }
        let x = (bounds.width - image.size.width) / 2
        let y = (bounds.height - image.size.height) / 2
        image.draw(in: NSRect(x: x, y: y, width: image.size.width, height: image.size.height))
    }

    deinit {
        timer?.invalidate()
    }
}
