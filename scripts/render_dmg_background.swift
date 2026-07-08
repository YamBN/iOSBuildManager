// Renders the DMG installer window background: dark navy gradient (matching
// the app's own Theme.swift AppBackground), app name header, a drag arrow
// between where Finder will place the two icons, and an install instruction.
// Run:  swift scripts/render_dmg_background.swift <output.png>
import AppKit

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "background.png"

// Must match the window bounds set in make-dmg.sh's AppleScript step.
let width = 660
let height = 420

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let canvas = CGRect(x: 0, y: 0, width: width, height: height)

// Base gradient: same navy tones as the in-app dark background.
let base = NSGradient(colors: [
    NSColor(calibratedRed: 0.043, green: 0.055, blue: 0.09, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.027, blue: 0.047, alpha: 1),
])!
base.draw(in: canvas, angle: -90)

// Soft accent glow, top-leading, echoing AppBackground's radial highlight.
ctx.saveGState()
if let glow = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) {
    let colors = [
        CGColor(red: 0.29, green: 0.56, blue: 0.98, alpha: 0.35),
        CGColor(red: 0.29, green: 0.56, blue: 0.98, alpha: 0.0),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        glow.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: width / 5, y: height - height / 6), startRadius: 0,
            endCenter: CGPoint(x: width / 5, y: height - height / 6), endRadius: CGFloat(width) * 0.55,
            options: []
        )
    }
    if let image = glow.makeImage() {
        ctx.draw(image, in: canvas)
    }
}
ctx.restoreGState()

// Hairline divider under the header band.
ctx.saveGState()
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
ctx.setLineWidth(1)
ctx.move(to: CGPoint(x: 0, y: CGFloat(height) - 74))
ctx.addLine(to: CGPoint(x: CGFloat(width), y: CGFloat(height) - 74))
ctx.strokePath()
ctx.restoreGState()

func draw(_ text: String, font: NSFont, color: NSColor, centerX: CGFloat, y: CGFloat, tracking: CGFloat = 0) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: tracking,
    ]
    let attributed = NSAttributedString(string: text, attributes: attrs)
    let size = attributed.size()
    attributed.draw(at: CGPoint(x: centerX - size.width / 2, y: y))
}

// Header: app name + tagline.
draw(
    "iOS Build Manager",
    font: NSFont.systemFont(ofSize: 22, weight: .bold),
    color: .white,
    centerX: CGFloat(width) / 2, y: CGFloat(height) - 56
)
draw(
    "Build. Package. Sideload.",
    font: NSFont.systemFont(ofSize: 12, weight: .medium),
    color: NSColor(white: 1, alpha: 0.55),
    centerX: CGFloat(width) / 2, y: CGFloat(height) - 78, tracking: 0.6
)

// Drag arrow between the two icon slots (Finder places icons at
// {180, arrowY} and {480, arrowY} in make-dmg.sh — keep in sync).
let arrowY = CGFloat(height) - 235
let arrowPath = NSBezierPath()
let shaftY = arrowY
arrowPath.move(to: CGPoint(x: 260, y: shaftY))
arrowPath.line(to: CGPoint(x: 385, y: shaftY))
arrowPath.move(to: CGPoint(x: 365, y: shaftY + 14))
arrowPath.line(to: CGPoint(x: 390, y: shaftY))
arrowPath.line(to: CGPoint(x: 365, y: shaftY - 14))
arrowPath.lineWidth = 3
arrowPath.lineCapStyle = .round
arrowPath.lineJoinStyle = .round
NSColor(calibratedRed: 0.35, green: 0.62, blue: 1.0, alpha: 0.9).setStroke()
arrowPath.stroke()

// Install instruction near the bottom.
draw(
    "Drag iOS Build Manager into Applications to install",
    font: NSFont.systemFont(ofSize: 13, weight: .medium),
    color: NSColor(white: 1, alpha: 0.75),
    centerX: CGFloat(width) / 2, y: 46
)
draw(
    "Free Apple ID • Local-only • No analytics",
    font: NSFont.systemFont(ofSize: 11, weight: .regular),
    color: NSColor(white: 1, alpha: 0.4),
    centerX: CGFloat(width) / 2, y: 26
)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8))
    exit(1)
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(width)x\(height))")
