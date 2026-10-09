// Draws Cranny's app icon. Usage: swift Tools/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Body: the standard macOS icon grid (824pt squircle centred on a 1024 canvas).
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
bodyPath.fill()
ctx.restoreGState()

ctx.saveGState()
bodyPath.addClip()
let background = NSGradient(colors: [
    NSColor(srgbRed: 0.33, green: 0.30, blue: 0.95, alpha: 1),
    NSColor(srgbRed: 0.17, green: 0.12, blue: 0.45, alpha: 1),
    NSColor(srgbRed: 0.05, green: 0.04, blue: 0.12, alpha: 1),
])!
background.draw(in: body, angle: -90)

// Soft glow under the notch.
let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
glow.draw(fromCenter: NSPoint(x: 512, y: 700), radius: 0, toCenter: NSPoint(x: 512, y: 700), radius: 420, options: [])

// The expanded notch ("nook") hanging from the top edge.
let nookRect = CGRect(x: 190, y: 430, width: 644, height: 494)
let ear: CGFloat = 34, corner: CGFloat = 92
let nook = NSBezierPath()
nook.move(to: NSPoint(x: nookRect.minX, y: nookRect.maxY))
nook.curve(to: NSPoint(x: nookRect.minX + ear, y: nookRect.maxY - ear),
           controlPoint1: NSPoint(x: nookRect.minX + ear * 0.6, y: nookRect.maxY),
           controlPoint2: NSPoint(x: nookRect.minX + ear, y: nookRect.maxY - ear * 0.4))
nook.line(to: NSPoint(x: nookRect.minX + ear, y: nookRect.minY + corner))
nook.curve(to: NSPoint(x: nookRect.minX + ear + corner, y: nookRect.minY),
           controlPoint1: NSPoint(x: nookRect.minX + ear, y: nookRect.minY + corner * 0.45),
           controlPoint2: NSPoint(x: nookRect.minX + ear + corner * 0.45, y: nookRect.minY))
nook.line(to: NSPoint(x: nookRect.maxX - ear - corner, y: nookRect.minY))
nook.curve(to: NSPoint(x: nookRect.maxX - ear, y: nookRect.minY + corner),
           controlPoint1: NSPoint(x: nookRect.maxX - ear - corner * 0.45, y: nookRect.minY),
           controlPoint2: NSPoint(x: nookRect.maxX - ear, y: nookRect.minY + corner * 0.45))
nook.line(to: NSPoint(x: nookRect.maxX - ear, y: nookRect.maxY - ear))
nook.curve(to: NSPoint(x: nookRect.maxX, y: nookRect.maxY),
           controlPoint1: NSPoint(x: nookRect.maxX - ear, y: nookRect.maxY - ear * 0.4),
           controlPoint2: NSPoint(x: nookRect.maxX - ear * 0.6, y: nookRect.maxY))
nook.close()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: NSColor.black.withAlphaComponent(0.55).cgColor)
NSColor.black.setFill()
nook.fill()
ctx.restoreGState()

// Camera dot.
NSColor(white: 0.16, alpha: 1).setFill()
NSBezierPath(ovalIn: CGRect(x: 498, y: 872, width: 28, height: 28)).fill()
NSColor(srgbRed: 0.25, green: 0.3, blue: 0.55, alpha: 1).setFill()
NSBezierPath(ovalIn: CGRect(x: 506, y: 880, width: 12, height: 12)).fill()

// Album art tile.
let art = CGRect(x: 270, y: 520, width: 230, height: 230)
let artPath = NSBezierPath(roundedRect: art, xRadius: 46, yRadius: 46)
ctx.saveGState()
artPath.addClip()
NSGradient(colors: [
    NSColor(srgbRed: 1.0, green: 0.42, blue: 0.48, alpha: 1),
    NSColor(srgbRed: 1.0, green: 0.68, blue: 0.30, alpha: 1),
])!.draw(in: art, angle: -45)
NSColor.white.withAlphaComponent(0.9).setFill()
let note = NSBezierPath()
note.appendOval(in: CGRect(x: 330, y: 568, width: 62, height: 48))
note.appendRect(CGRect(x: 380, y: 590, width: 14, height: 118))
note.appendRect(CGRect(x: 380, y: 680, width: 64, height: 28))
note.fill()
ctx.restoreGState()

// Spectrograph bars.
let barColors = [
    NSColor(srgbRed: 1.0, green: 0.55, blue: 0.45, alpha: 1),
    NSColor(srgbRed: 1.0, green: 0.62, blue: 0.40, alpha: 1),
    NSColor(srgbRed: 1.0, green: 0.70, blue: 0.36, alpha: 1),
    NSColor(srgbRed: 1.0, green: 0.78, blue: 0.34, alpha: 1),
]
let heights: [CGFloat] = [120, 200, 150, 230]
for (i, h) in heights.enumerated() {
    let x = 560 + CGFloat(i) * 54
    let rect = CGRect(x: x, y: 635 - h / 2, width: 30, height: h)
    barColors[i].setFill()
    NSBezierPath(roundedRect: rect, xRadius: 15, yRadius: 15).fill()
}
ctx.restoreGState()

// Subtle rim light.
NSColor.white.withAlphaComponent(0.12).setStroke()
bodyPath.lineWidth = 4
bodyPath.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
