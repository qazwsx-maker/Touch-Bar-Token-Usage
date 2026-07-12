import AppKit

enum PetKind: String, CaseIterable, Identifiable {
    case cat
    case dog
    case dragon
    case penguin
    case ghost
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cat: return "Cat"
        case .dog: return "Dog"
        case .dragon: return "Dragon"
        case .penguin: return "Penguin"
        case .ghost: return "Ghost"
        case .none: return "None"
        }
    }

    var emoji: String {
        switch self {
        case .cat: return "🐱"
        case .dog: return "🐶"
        case .dragon: return "🐲"
        case .penguin: return "🐧"
        case .ghost: return "👻"
        case .none: return "⌁"
        }
    }
}

struct PetSprite {
    let run: [[String]]
    let idle: [[String]]
}

/// Pixel-art pets rendered as single-color silhouettes ('#' = pixel).
/// Rows are top-to-bottom; ragged row widths are fine.
enum PetSprites {
    static func sprite(for kind: PetKind) -> PetSprite? {
        switch kind {
        case .cat: return cat
        case .dog: return dog
        case .dragon: return dragon
        case .penguin: return penguin
        case .ghost: return ghost
        case .none: return nil
        }
    }

    // MARK: - Cat

    private static let cat = PetSprite(
        run: [
            [
                "..............#.#.",
                ".#............###.",
                ".#...........####.",
                "..#..#############",
                "...###############",
                "....#############.",
                "....############..",
                "....##.......##...",
                "...#..#.....#..#..",
                "..#....#...#....#.",
            ],
            [
                "..............#.#.",
                "..#...........###.",
                "..#..........####.",
                "...#.#############",
                "....##############",
                "....#############.",
                ".....###########..",
                "......##...##.....",
                "......#.....#.....",
                ".....#.......#....",
            ],
            [
                "..............#.#.",
                "...#..........###.",
                "..#...........####",
                "..#..#############",
                "...###############",
                "....#############.",
                "....############..",
                ".....#.....##.....",
                "....#......#.#....",
                "...#......#...#...",
            ],
            [
                "..............#.#.",
                "..#...........###.",
                "...#..........####",
                "...#.#############",
                "....##############",
                "....#############.",
                ".....###########..",
                ".....##.....##....",
                "....#..#...#..#...",
                "...#....#.#....#..",
            ],
        ],
        idle: [
            [
                "..........#.#.....",
                "..........###.....",
                ".........#####....",
                "..........###.....",
                ".........####.....",
                "........######....",
                ".#.....#######....",
                "..#...########....",
                "...#..########....",
                "....##########....",
                "....##..##..##....",
            ],
            [
                "..........#.#.....",
                "..........###.....",
                ".........#####....",
                "..........###.....",
                ".........####.....",
                "........######....",
                "..#....#######....",
                "..#...########....",
                "...#..########....",
                "....##########....",
                "....##..##..##....",
            ],
        ]
    )

    // MARK: - Dog

    private static let dog = PetSprite(
        run: [
            [
                ".#.............###",
                ".#............####",
                "..#..#############",
                "...###############",
                "....##############",
                "....#############.",
                "....##.......##...",
                "...#..#.....#..#..",
                "..#....#...#....#.",
            ],
            [
                "..#............###",
                "..#...........####",
                "...#.#############",
                "....##############",
                "....##############",
                ".....############.",
                "......##...##.....",
                "......#.....#.....",
                ".....#.......#....",
            ],
            [
                ".#.............###",
                "..#............####",
                "..#..#############",
                "...###############",
                "....##############",
                "....#############.",
                ".....#.....##.....",
                "....#......#.#....",
                "...#......#...#...",
            ],
            [
                "..#............###",
                "...#...........####",
                "...#.#############",
                "....##############",
                "....##############",
                ".....############.",
                ".....##.....##....",
                "....#..#...#..#...",
                "...#....#.#....#..",
            ],
        ],
        idle: [
            [
                "..........###.....",
                "..........####....",
                ".........#####....",
                "..........###.....",
                ".........####.....",
                "........######....",
                ".#.....#######....",
                ".##...########....",
                "...#..########....",
                "....##########....",
                "....##..##..##....",
            ],
            [
                "..........###.....",
                "..........####....",
                ".........#####....",
                "..........###.....",
                ".........####.....",
                "........######....",
                "..#....#######....",
                ".##...########....",
                "...#..########....",
                "....##########....",
                "....##..##..##....",
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

    // MARK: - Penguin

    private static let penguin = PetSprite(
        run: [
            [
                "....####....",
                "...######...",
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
                "...######...",
                "..########..",
                ".##########.",
                ".##########.",
                "..########..",
                "...######...",
                "..##....##..",
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
    var kind: PetKind = .cat { didSet { needsDisplay = true } }
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
