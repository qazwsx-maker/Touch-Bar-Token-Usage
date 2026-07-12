#!/usr/bin/env swift
// Generates AppIcon.iconset PNGs (dark rounded square + pixel cat).
// Usage: swift scripts/genicon.swift <output.iconset>

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: genicon.swift <output.iconset>")
    exit(1)
}
let outDir = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let cat = [
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
]

func draw(size: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: size,
                                     pixelsHigh: size,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else { return nil }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let s = CGFloat(size)
    let inset = s * 0.04
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.12, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: s * 0.21, yRadius: s * 0.21).fill()

    let rows = cat.count
    let cols = cat.map { $0.count }.max() ?? 1
    let cell = (s * 0.74) / CGFloat(cols)
    let originX = (s - CGFloat(cols) * cell) / 2
    let originY = (s - CGFloat(rows) * cell) / 2
    NSColor(calibratedRed: 0.39, green: 0.82, blue: 1.0, alpha: 1).setFill()
    for (r, row) in cat.enumerated() {
        for (c, ch) in row.enumerated() where ch == "#" {
            NSRect(x: originX + CGFloat(c) * cell,
                   y: originY + CGFloat(rows - 1 - r) * cell,
                   width: cell + 0.6,
                   height: cell + 0.6).fill()
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, px) in sizes {
    guard let rep = draw(size: px),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("failed to render \(name)")
        exit(1)
    }
    do {
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
    } catch {
        print("failed to write \(name): \(error)")
        exit(1)
    }
}
print("iconset written to \(outDir.path)")
