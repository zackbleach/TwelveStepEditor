// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.
//
// Renders the iOS app icon (default, dark and tinted variants) as 1024x1024 PNGs.
// Usage: swift Tools/app-icon/render-icon.swift <output-dir>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let canvas = CGFloat(size)

// MARK: - Layout (y grows upwards in CoreGraphics)

/// The 12 Step key layout: 8 lower keys and 5 raised keys over the gaps 1-2, 2-3, 4-5, 5-6 and 6-7,
/// like the black keys of a piano octave.
struct Layout {
    static let lowerWidth: CGFloat = 76
    static let gap: CGFloat = 14
    static let lowerHeight: CGFloat = 236
    static let raisedWidth: CGFloat = 64
    static let raisedHeight: CGFloat = 168
    static let rowGap: CGFloat = 26
    static let lowerRadius: CGFloat = 16
    static let raisedRadius: CGFloat = 14
    /// Lower-row index (0-based) drawn in brand cyan.
    static let highlighted = 3
    /// Raised keys sit over the gap after these lower keys (0-based).
    static let raisedAfter = [0, 1, 3, 4, 5]

    static var rowWidth: CGFloat { 8 * lowerWidth + 7 * gap }
    static var totalHeight: CGFloat { lowerHeight + rowGap + raisedHeight }
    static var left: CGFloat { (canvas - rowWidth) / 2 }
    // Optically centred: nudge down slightly because the raised row is lighter.
    static var bottom: CGFloat { (canvas - totalHeight) / 2 - 6 }

    static func lowerKey(_ index: Int) -> CGRect {
        CGRect(x: left + CGFloat(index) * (lowerWidth + gap), y: bottom, width: lowerWidth, height: lowerHeight)
    }

    static func raisedKey(after index: Int) -> CGRect {
        let gapCentre = left + CGFloat(index + 1) * (lowerWidth + gap) - gap / 2
        return CGRect(x: gapCentre - raisedWidth / 2, y: bottom + lowerHeight + rowGap,
                      width: raisedWidth, height: raisedHeight)
    }
}

// MARK: - Palette

struct Palette {
    var background: [(CGFloat, CGFloat, CGFloat)]?  // top, bottom; nil = transparent
    var lower: CGColor
    var raised: CGColor
    var highlight: CGColor
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let gray = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}
let brand = rgb(0, 0.682, 0.929)

let variants: [(name: String, palette: Palette, opaque: Bool)] = [
    ("AppIcon.png", Palette(background: [(0.05, 0.12, 0.2), (0.0, 0.36, 0.55)],
                            lower: rgb(1, 1, 1, 0.9), raised: rgb(1, 1, 1, 0.62), highlight: brand), true),
    // Dark: transparent so iOS supplies its dark backdrop; keys slightly dimmed, cyan kept.
    ("AppIcon-Dark.png", Palette(background: nil,
                                 lower: rgb(0.88, 0.9, 0.92), raised: rgb(0.55, 0.58, 0.62), highlight: brand), false),
    // Tinted: grayscale on transparent; iOS applies the tint. Highlight is pure white.
    ("AppIcon-Tinted.png", Palette(background: nil,
                                   lower: rgb(0.75, 0.75, 0.75), raised: rgb(0.55, 0.55, 0.55), highlight: rgb(1, 1, 1)), false),
]

// MARK: - Drawing

func render(_ palette: Palette, opaque: Bool) -> CGImage {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: info)!
    context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

    if let stops = palette.background {
        let colors = stops.map { rgb($0.0, $0.1, $0.2) } as CFArray
        let gradient = CGGradient(colorsSpace: sRGB, colors: colors, locations: [0, 1])!
        // Full square: iOS applies the corner mask itself.
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas), end: CGPoint(x: 0, y: 0), options: [])
    }

    func key(_ rect: CGRect, radius: CGFloat, color: CGColor) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(color)
        context.fillPath()
    }
    for index in Layout.raisedAfter {
        key(Layout.raisedKey(after: index), radius: Layout.raisedRadius, color: palette.raised)
    }
    for index in 0..<8 {
        key(Layout.lowerKey(index), radius: Layout.lowerRadius,
            color: index == Layout.highlighted ? palette.highlight : palette.lower)
    }
    return context.makeImage()!
}

/// Converts an image to 8-bit grayscale with alpha (for the tinted variant).
func grayscale(_ image: CGImage) -> CGImage {
    // Draw onto a gray+alpha context so the PNG has no colour channels.
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: gray, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let context else { return image }
    context.draw(image, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    return context.makeImage() ?? image
}

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(url.path)") }
}

// MARK: - Main

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift render-icon.swift <output-dir>\n".data(using: .utf8)!)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for variant in variants {
    var image = render(variant.palette, opaque: variant.opaque)
    if variant.name.contains("Tinted") { image = grayscale(image) }
    write(image, to: output.appendingPathComponent(variant.name))
    print("wrote \(output.appendingPathComponent(variant.name).path)")
}
