// Renders the DMG installer window background to match the product mockup:
// header (app icon + title + blue tagline), concentric glow rings behind the
// drag area, a dotted → glowing arrow, per-icon glow, an install instruction,
// a divider, a 4-column feature strip, and a footer.
//
// The .app and Applications icons themselves are real Finder icons placed on
// top by dmgbuild (see scripts/dmg_settings.py) — this only draws everything
// else. Coordinates here are in TOP-origin points and must stay in sync with
// the icon_locations / window_rect in dmg_settings.py.
//
// Run:  swift render_dmg_background.swift <output.png> <app-icon.png>
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"
let iconPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

// Window is W×H points; render at 2× for crisp retina display.
let W: CGFloat = 720
let H: CGFloat = 564
let scale: CGFloat = 2

// Icon centers (top-origin) — keep in sync with dmg_settings.py.
let appIconCenter = CGPoint(x: 205, y: 250)
let appsIconCenter = CGPoint(x: 515, y: 250)
let ringsCenter = CGPoint(x: 360, y: 250)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.scaleBy(x: scale, y: scale)

// Convert a top-origin y to AppKit's bottom-origin space.
func fy(_ topY: CGFloat) -> CGFloat { H - topY }

let accent = NSColor(srgbRed: 0.29, green: 0.56, blue: 0.98, alpha: 1)
let taglineBlue = NSColor(srgbRed: 0.42, green: 0.66, blue: 1.0, alpha: 1)
let arrowBlue = NSColor(srgbRed: 0.36, green: 0.64, blue: 1.0, alpha: 1)

// ---- Base background: deep navy vignette ----
let base = NSGradient(colors: [
    NSColor(srgbRed: 0.047, green: 0.063, blue: 0.11, alpha: 1),
    NSColor(srgbRed: 0.016, green: 0.024, blue: 0.047, alpha: 1),
])!
base.draw(in: CGRect(x: 0, y: 0, width: W, height: H), angle: -90)

func radialGlow(center: CGPoint, radius: CGFloat, color: NSColor, alpha: CGFloat) {
    ctx.saveGState()
    let colors = [
        color.withAlphaComponent(alpha).cgColor,
        color.withAlphaComponent(0).cgColor,
    ] as CFArray
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        let c = CGPoint(x: center.x, y: fy(center.y))
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
    }
    ctx.restoreGState()
}

// Ambient center glow + a subtle top wash.
radialGlow(center: ringsCenter, radius: 300, color: accent, alpha: 0.16)
radialGlow(center: CGPoint(x: 360, y: 120), radius: 320, color: accent, alpha: 0.07)

// ---- Concentric rings behind the drag area ----
ctx.saveGState()
for r in [96.0, 150.0, 208.0] as [CGFloat] {
    let path = NSBezierPath(ovalIn: CGRect(
        x: ringsCenter.x - r, y: fy(ringsCenter.y) - r, width: r * 2, height: r * 2))
    NSColor.white.withAlphaComponent(0.05).setStroke()
    path.lineWidth = 1
    path.stroke()
}
ctx.restoreGState()

// Soft glow pooled beneath each real icon.
radialGlow(center: CGPoint(x: appIconCenter.x, y: appIconCenter.y + 4), radius: 105, color: accent, alpha: 0.28)
radialGlow(center: CGPoint(x: appsIconCenter.x, y: appsIconCenter.y + 4), radius: 95, color: accent, alpha: 0.14)

// ---- Text helpers ----
func draw(_ text: String, font: NSFont, color: NSColor,
          centerX: CGFloat, centerTopY: CGFloat, tracking: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: tracking]
    let s = NSAttributedString(string: text, attributes: attrs)
    let sz = s.size()
    s.draw(at: CGPoint(x: centerX - sz.width / 2, y: fy(centerTopY) - sz.height / 2))
}

func drawLeft(_ text: String, font: NSFont, color: NSColor,
              leftX: CGFloat, centerTopY: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let s = NSAttributedString(string: text, attributes: attrs)
    let sz = s.size()
    s.draw(at: CGPoint(x: leftX, y: fy(centerTopY) - sz.height / 2))
}

func textWidth(_ text: String, font: NSFont) -> CGFloat {
    NSAttributedString(string: text, attributes: [.font: font]).size().width
}

// ---- Header: app icon + title, centered as a group; tagline beneath ----
let titleFont = NSFont.systemFont(ofSize: 34, weight: .bold)
let titleStr = "iOS Build Manager"
let titleW = textWidth(titleStr, font: titleFont)
let headerIcon: CGFloat = 62
let headerGap: CGFloat = 16
let groupW = headerIcon + headerGap + titleW
let groupStartX = 360 - groupW / 2
let headerCenterY: CGFloat = 78

if let icon = NSImage(contentsOfFile: iconPath) {
    icon.draw(in: CGRect(x: groupStartX, y: fy(headerCenterY) - headerIcon / 2,
                         width: headerIcon, height: headerIcon))
}
drawLeft(titleStr, font: titleFont, color: .white,
         leftX: groupStartX + headerIcon + headerGap, centerTopY: headerCenterY)

draw("Build. Package. Sideload.",
     font: NSFont.systemFont(ofSize: 15, weight: .semibold),
     color: taglineBlue, centerX: 360, centerTopY: 120, tracking: 0.4)

// ---- Arrow between the icons: three dots then a glowing arrow ----
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 8, color: arrowBlue.withAlphaComponent(0.8).cgColor)
let arrowY = fy(250)
for (i, x) in [289.0, 304.0, 319.0].enumerated() {
    let d: CGFloat = 4 + CGFloat(i)
    let dot = NSBezierPath(ovalIn: CGRect(x: CGFloat(x) - d / 2, y: arrowY - d / 2, width: d, height: d))
    arrowBlue.setFill()
    dot.fill()
}
let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 335, y: arrowY))
arrow.line(to: CGPoint(x: 425, y: arrowY))
arrow.move(to: CGPoint(x: 405, y: arrowY + 13))
arrow.line(to: CGPoint(x: 430, y: arrowY))
arrow.line(to: CGPoint(x: 405, y: arrowY - 13))
arrow.lineWidth = 3.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrowBlue.setStroke()
arrow.stroke()
ctx.restoreGState()

// ---- Readability chips behind the icon labels ----
// Finder draws item labels on top of this background using the system
// appearance's color (dark text in Light Mode → low contrast on this dark
// background). We can't recolor Finder's labels, so we lay a soft rounded chip
// behind each so they read clearly in both Light and Dark Mode.
func labelChip(centerX: CGFloat, centerTopY: CGFloat, text: String) {
    let f = NSFont.systemFont(ofSize: 13)
    let w = textWidth(text, font: f) + 24
    let h: CGFloat = 23
    let rect = CGRect(x: centerX - w / 2, y: fy(centerTopY) - h / 2, width: w, height: h)
    let chip = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
    NSColor.white.withAlphaComponent(0.18).setFill()
    chip.fill()
    NSColor.white.withAlphaComponent(0.16).setStroke()
    chip.lineWidth = 1
    chip.stroke()
}
labelChip(centerX: appIconCenter.x, centerTopY: 333, text: "iOSBuildManager")
labelChip(centerX: appsIconCenter.x, centerTopY: 333, text: "Applications")

// ---- Install instruction ----
draw("Drag iOS Build Manager to Applications to install",
     font: NSFont.systemFont(ofSize: 15, weight: .medium),
     color: NSColor.white.withAlphaComponent(0.62), centerX: 360, centerTopY: 372)

// ---- Divider ----
ctx.saveGState()
NSColor.white.withAlphaComponent(0.09).setStroke()
let divider = NSBezierPath()
divider.move(to: CGPoint(x: 48, y: fy(408)))
divider.line(to: CGPoint(x: W - 48, y: fy(408)))
divider.lineWidth = 1
divider.stroke()
ctx.restoreGState()

// ---- Feature strip ----
func drawSymbol(_ name: String, in rect: CGRect, color: NSColor) {
    let cfg = NSImage.SymbolConfiguration(pointSize: rect.width, weight: .semibold)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else { return }
    let tinted = NSImage(size: base.size)
    tinted.lockFocus()
    color.set()
    let r = CGRect(origin: .zero, size: base.size)
    base.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()
    let s = min(rect.width, rect.height)
    tinted.draw(in: CGRect(x: rect.midX - s / 2, y: rect.midY - s / 2, width: s, height: s))
}

struct Feature { let symbol: String; let title: String; let line1: String; let line2: String }
let features = [
    Feature(symbol: "bolt.fill", title: "Fast & Native", line1: "Built for macOS", line2: "performance"),
    Feature(symbol: "checkmark.shield.fill", title: "Secure", line1: "Your data stays", line2: "on your Mac"),
    Feature(symbol: "shippingbox.fill", title: "All-in-One", line1: "Build, package", line2: "and distribute"),
    Feature(symbol: "chevron.left.forwardslash.chevron.right", title: "Open Source", line1: "Made for developers,", line2: "by developers"),
]

let blockStartX: [CGFloat] = [52, 218, 384, 552]
let iconDiameter: CGFloat = 36
let featureCenterY: CGFloat = 460

for (i, f) in features.enumerated() {
    let bx = blockStartX[i]
    let iconCenter = CGPoint(x: bx + iconDiameter / 2, y: featureCenterY)

    // Faint circular chip behind the glyph.
    ctx.saveGState()
    let chip = NSBezierPath(ovalIn: CGRect(
        x: iconCenter.x - iconDiameter / 2, y: fy(iconCenter.y) - iconDiameter / 2,
        width: iconDiameter, height: iconDiameter))
    accent.withAlphaComponent(0.14).setFill()
    chip.fill()
    accent.withAlphaComponent(0.30).setStroke()
    chip.lineWidth = 1
    chip.stroke()
    ctx.restoreGState()

    drawSymbol(f.symbol, in: CGRect(
        x: iconCenter.x - 9, y: fy(iconCenter.y) - 9, width: 18, height: 18), color: accent)

    let textX = bx + iconDiameter + 12
    drawLeft(f.title, font: NSFont.systemFont(ofSize: 13, weight: .semibold),
             color: .white, leftX: textX, centerTopY: featureCenterY - 8)
    drawLeft(f.line1, font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
             color: NSColor.white.withAlphaComponent(0.5), leftX: textX, centerTopY: featureCenterY + 7)
    drawLeft(f.line2, font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
             color: NSColor.white.withAlphaComponent(0.5), leftX: textX, centerTopY: featureCenterY + 20)
}

// ---- Footer ----
draw("Free. Open Source. Always. 💙",
     font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
     color: NSColor.white.withAlphaComponent(0.4), centerX: 360, centerTopY: 538)

NSGraphicsContext.restoreGraphicsState()

// Tag the bitmap as W×H points backed by 2× pixels so the PNG carries a 144-DPI
// pHYs chunk. Finder reads that and displays the image at point size inside the
// window (retina-crisp) instead of showing it 1:1 in pixels (zoomed-in quarter).
rep.size = NSSize(width: W, height: H)

guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8)); exit(1)
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(Int(W))x\(Int(H)) @\(Int(scale))x)")
