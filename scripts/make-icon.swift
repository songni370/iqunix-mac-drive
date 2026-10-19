// make-icon.swift — render the MQ80 Studio app icon without Xcode/network.
//
// Usage:
//   swiftc scripts/make-icon.swift -o .build-manual/make-icon
//   .build-manual/make-icon dist/AppIcon.iconset
//   iconutil -c icns dist/AppIcon.iconset -o dist/AppIcon.icns
//
// The design is drawn as vectors at every required pixel size (16 … 1024) so
// the result stays crisp in the Dock, Finder and About panel. Deterministic and
// repeatable: running it twice produces identical PNG bytes.
//
// Style: dark rounded-square canvas, a stylised keyboard made of raised
// keycaps, one keycap in the accent teal. No external assets are used.

import AppKit
import CoreGraphics
import Foundation

// MARK: - helpers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("make-icon: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillGradient(_ ctx: CGContext, path: CGPath, from: CGPoint, to: CGPoint, colors: [CGColor]) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil) {
        ctx.drawLinearGradient(gradient, start: from, end: to,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    ctx.restoreGState()
}

// MARK: - design (drawn on a 1024 x 1024 logical grid, y-up)

/// One raised keycap: body gradient, soft drop shadow, top highlight edge.
func drawKeycap(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat,
                base: CGColor, top: CGColor, highlighted: Bool) {
    let path = roundedPath(rect, radius)

    // accent glow / drop shadow
    if highlighted {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 46,
                      color: color(0x2EE6C8, 0.55))
        ctx.addPath(roundedPath(rect.insetBy(dx: 6, dy: 6), radius))
        ctx.setFillColor(color(0x2EE6C8, 0.9))
        ctx.fillPath()
        ctx.restoreGState()
    } else {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16,
                      color: color(0x000000, 0.45))
        ctx.addPath(path)
        ctx.setFillColor(base)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // body
    fillGradient(ctx, path: path,
                 from: CGPoint(x: rect.midX, y: rect.maxY),
                 to: CGPoint(x: rect.midX, y: rect.minY),
                 colors: [top, base])

    // top bevel highlight
    ctx.saveGState()
    let bevel = roundedPath(rect.insetBy(dx: 3, dy: 3), radius - 3)
    ctx.addPath(bevel)
    ctx.setLineWidth(3)
    ctx.setStrokeColor(color(0xFFFFFF, highlighted ? 0.40 : 0.14))
    ctx.strokePath()
    ctx.restoreGState()

    // bottom edge shade, keeps the cap readable on dark backgrounds
    ctx.saveGState()
    let bottomEdge = CGMutablePath()
    let r = radius
    bottomEdge.move(to: CGPoint(x: rect.minX + r, y: rect.minY + 3))
    bottomEdge.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY + 3))
    ctx.addPath(bottomEdge)
    ctx.setLineWidth(3)
    ctx.setStrokeColor(color(0x000000, 0.35))
    ctx.strokePath()
    ctx.restoreGState()
}

func drawIcon(in ctx: CGContext) {
    // ---- background: dark rounded square (macOS-style squircle-ish radius) ----
    let canvasRect = CGRect(x: 84, y: 84, width: 856, height: 856)
    let canvas = roundedPath(canvasRect, 192)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34,
                  color: color(0x000000, 0.40))
    ctx.addPath(canvas)
    ctx.setFillColor(color(0x11161B))
    ctx.fillPath()
    ctx.restoreGState()

    fillGradient(ctx, path: canvas,
                 from: CGPoint(x: canvasRect.midX, y: canvasRect.maxY),
                 to: CGPoint(x: canvasRect.midX, y: canvasRect.minY),
                 colors: [color(0x232F3A), color(0x0D1116)])

    // soft inner vignette so the plate reads as inset
    ctx.saveGState()
    ctx.addPath(canvas)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    if let vignette = CGGradient(colorsSpace: space,
                                 colors: [color(0xFFFFFF, 0.06), color(0xFFFFFF, 0.0)] as CFArray,
                                 locations: [0.0, 0.55]) {
        ctx.drawRadialGradient(vignette,
                               startCenter: CGPoint(x: 512, y: 780), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 780), endRadius: 760,
                               options: [.drawsAfterEndLocation])
    }
    // faint teal atmosphere behind the keyboard
    if let glow = CGGradient(colorsSpace: space,
                             colors: [color(0x2EE6C8, 0.22), color(0x2EE6C8, 0.0)] as CFArray,
                             locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(glow,
                               startCenter: CGPoint(x: 560, y: 600), startRadius: 10,
                               endCenter: CGPoint(x: 560, y: 600), endRadius: 470,
                               options: [.drawsAfterEndLocation])
    }
    // 1px inner border highlight
    ctx.addPath(roundedPath(canvasRect.insetBy(dx: 2, dy: 2), 190))
    ctx.setLineWidth(3)
    ctx.setStrokeColor(color(0xFFFFFF, 0.10))
    ctx.strokePath()
    ctx.restoreGState()

    // ---- keyboard plate ----
    let plateRect = CGRect(x: 178, y: 286, width: 668, height: 468)
    let plate = roundedPath(plateRect, 66)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 26, color: color(0x000000, 0.50))
    ctx.addPath(plate)
    ctx.setFillColor(color(0x0A0E12, 0.55))
    ctx.fillPath()
    ctx.restoreGState()

    fillGradient(ctx, path: plate,
                 from: CGPoint(x: plateRect.midX, y: plateRect.maxY),
                 to: CGPoint(x: plateRect.midX, y: plateRect.minY),
                 colors: [color(0x1A222A), color(0x080B0F)])
    ctx.saveGState()
    ctx.addPath(roundedPath(plateRect.insetBy(dx: 2, dy: 2), 64))
    ctx.setLineWidth(3)
    ctx.setStrokeColor(color(0xFFFFFF, 0.06))
    ctx.strokePath()
    ctx.restoreGState()

    // ---- keycaps: 4 columns x 3 rows, bottom row with a wide space bar ----
    let keyW: CGFloat = 140
    let keyH: CGFloat = 124
    let gap: CGFloat = 18
    let colX: [CGFloat] = [205, 363, 521, 679]        // 205 + i * (keyW + gap)
    let rowY: [CGFloat] = [304, 452, 600]             // bottom, middle, top

    // shadowed resting keys
    for (row, y) in rowY.enumerated() {
        for (col, x) in colX.enumerated() {
            if row == 0 && col == 0 { continue }       // space bar covers cols 0-1
            if row == 1 && col == 3 { continue }       // accent key drawn later
            drawKeycap(ctx, CGRect(x: x, y: y, width: keyW, height: keyH), radius: 22,
                       base: color(0x2B3742), top: color(0x3D4C59), highlighted: false)
        }
    }
    // space bar
    drawKeycap(ctx, CGRect(x: colX[0], y: rowY[0], width: keyW * 2 + gap, height: keyH), radius: 22,
               base: color(0x2B3742), top: color(0x3D4C59), highlighted: false)

    // accent key
    let accent = CGRect(x: colX[3], y: rowY[1], width: keyW, height: keyH)
    drawKeycap(ctx, accent, radius: 22,
               base: color(0x14B79E), top: color(0x3BF2D3), highlighted: true)

    // tiny keycap glyph marks on some keys: three fading dots on the accent key
    ctx.saveGState()
    ctx.addPath(roundedPath(accent, 22))
    ctx.clip()
    let dotY = accent.midY
    for (i, alpha) in [0.95, 0.65, 0.35].enumerated() {
        let cx = accent.minX + 38 + CGFloat(i) * 32
        ctx.setFillColor(color(0x043B33, CGFloat(alpha)))
        ctx.fillEllipse(in: CGRect(x: cx - 9, y: dotY - 9, width: 18, height: 18))
    }
    ctx.restoreGState()

    // teal underline "activity" bar under the plate
    ctx.saveGState()
    ctx.setFillColor(color(0x2EE6C8, 0.85))
    ctx.addPath(roundedPath(CGRect(x: 452, y: 252, width: 120, height: 12), 6))
    ctx.fillPath()
    ctx.restoreGState()
}

// MARK: - render

let uniqueSizes = [16, 32, 64, 128, 256, 512, 1024]
let fileMap: [(Int, [String])] = [
    (16, ["icon_16x16.png"]),
    (32, ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64, ["icon_32x32@2x.png"]),
    (128, ["icon_128x128.png"]),
    (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024, ["icon_512x512@2x.png"]),
]

func renderPNG(pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixelSize, pixelsHigh: pixelSize,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.scaleBy(x: CGFloat(pixelSize) / 1024.0, y: CGFloat(pixelSize) / 1024.0)
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)
    drawIcon(in: cg)
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let args = CommandLine.arguments
guard args.count == 2 else {
    fail("usage: make-icon <output.iconset directory>")
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
} catch {
    fail("cannot create \(outDir.path): \(error)")
}

for (pixelSize, names) in fileMap {
    guard let png = renderPNG(pixelSize: pixelSize) else {
        fail("failed to render \(pixelSize)x\(pixelSize)")
    }
    for name in names {
        let url = outDir.appendingPathComponent(name)
        do {
            try png.write(to: url)
        } catch {
            fail("cannot write \(url.path): \(error)")
        }
    }
}

print("make-icon: wrote \(fileMap.reduce(0) { $0 + $1.1.count }) PNGs to \(outDir.path)")
