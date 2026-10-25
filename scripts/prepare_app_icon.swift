import AppKit

guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 else {
    fputs("usage: prepare_app_icon.swift input.svg output.png [scale]\n", stderr)
    exit(2)
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let scale = CommandLine.arguments.count == 4
    ? CGFloat(Double(CommandLine.arguments[3]) ?? 0)
    : 1

guard scale >= 1, scale <= 1.25 else {
    fputs("scale must be between 1.0 and 1.25\n", stderr)
    exit(2)
}

guard let source = NSImage(contentsOfFile: inputPath) else {
    fputs("cannot read input image\n", stderr)
    exit(3)
}

let dimension = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: dimension,
    pixelsHigh: dimension,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("cannot create output bitmap\n", stderr)
    exit(4)
}

bitmap.size = NSSize(width: dimension, height: dimension)
guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("cannot create graphics context\n", stderr)
    exit(5)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high

let canvas = NSRect(x: 0, y: 0, width: dimension, height: dimension)
NSColor.white.setFill()
canvas.fill()

// Render the square, full-bleed SVG source without baking in a rounded mask.
// macOS applies its own icon mask. The optional scale is used only for the
// 16–64 px variants so the four symbols stay recognizable at Dock/Finder size.
let renderedDimension = CGFloat(dimension) * scale
let artworkRect = NSRect(
    x: (CGFloat(dimension) - renderedDimension) / 2,
    y: (CGFloat(dimension) - renderedDimension) / 2,
    width: renderedDimension,
    height: renderedDimension
)
source.draw(in: artworkRect, from: .zero, operation: .sourceOver, fraction: 1)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("cannot encode output image\n", stderr)
    exit(6)
}

try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
