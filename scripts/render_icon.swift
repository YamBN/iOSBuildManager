// Renders the master 1024×1024 app icon: a blue gradient rounded-square
// ("squircle") with a white shipping-box glyph, matching the in-app IconBadge.
// Run:  swift scripts/render_icon.swift <output.png>
import AppKit

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon_1024.png"

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: content inset inside the 1024 canvas, superellipse-ish corners.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
let cornerRadius = rect.width * 0.2237
let squircle = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

// Blue gradient fill (top-leading lighter → bottom-trailing deeper), matching
// the accent/blue IconBadge in the app.
ctx.saveGState()
squircle.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.29, green: 0.56, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.90, alpha: 1),
])!
gradient.draw(in: rect, angle: -60)

// Soft top highlight for depth.
let highlight = NSGradient(colors: [
    NSColor(white: 1, alpha: 0.22),
    NSColor(white: 1, alpha: 0.0),
])!
highlight.draw(in: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
ctx.restoreGState()

// White shipping-box glyph, centered, ~48% of the icon.
let glyphConfig = NSImage.SymbolConfiguration(pointSize: rect.width * 0.48, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(glyphConfig) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    NSColor.white.set()
    let r = CGRect(origin: .zero, size: symbol.size)
    symbol.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()

    let gw = symbol.size.width
    let gh = symbol.size.height
    let gx = rect.midX - gw / 2
    let gy = rect.midY - gh / 2
    tinted.draw(in: CGRect(x: gx, y: gy, width: gw, height: gh))
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8))
    exit(1)
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
