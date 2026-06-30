import AppKit

// Renders the app icon to a 1024×1024 PNG.
let px = 1024
let size = CGFloat(px)
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(deviceRed: r/255, green: g/255, blue: b/255, alpha: a)
}

// Squircle background with a diagonal gradient.
let margin: CGFloat = 86
let bgRect = NSRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 196, yRadius: 196)
let gradient = NSGradient(colors: [
    color(99, 102, 241),   // indigo
    color(124, 77, 255),   // violet
    color(56, 189, 248)    // cyan
], atLocations: [0.0, 0.5, 1.0], colorSpace: .deviceRGB)!
gradient.draw(in: bgPath, angle: -55)

// Soft top highlight for depth.
bgPath.addClip()
let glow = NSGradient(colors: [
    NSColor(white: 1, alpha: 0.22),
    NSColor(white: 1, alpha: 0.0)
])!
glow.draw(in: NSRect(x: margin, y: size * 0.52, width: size - margin * 2, height: size * 0.46 - margin), angle: -90)

// Three "server entry" cards with toggle pills — the app's actual function.
let cardX: CGFloat = 250
let cardW: CGFloat = 524
let cardH: CGFloat = 132
let gap: CGFloat = 56
let totalH = cardH * 3 + gap * 2
var y = (size - totalH) / 2 + totalH - cardH   // top card first (top-down)

let toggleStates = [true, true, false]
for on in toggleStates {
    let card = NSRect(x: cardX, y: y, width: cardW, height: cardH)
    let cardPath = NSBezierPath(roundedRect: card, xRadius: 34, yRadius: 34)
    NSColor(white: 1, alpha: 0.94).setFill()
    cardPath.fill()

    // Status dot on the left.
    let dotD: CGFloat = 40
    let dot = NSRect(x: cardX + 34, y: y + (cardH - dotD)/2, width: dotD, height: dotD)
    (on ? color(52, 199, 89) : color(174, 178, 188)).setFill()
    NSBezierPath(ovalIn: dot).fill()

    // Toggle pill on the right.
    let pillW: CGFloat = 124, pillH: CGFloat = 64
    let pill = NSRect(x: card.maxX - pillW - 34, y: y + (cardH - pillH)/2, width: pillW, height: pillH)
    let pillPath = NSBezierPath(roundedRect: pill, xRadius: pillH/2, yRadius: pillH/2)
    (on ? color(52, 199, 89) : color(199, 202, 209)).setFill()
    pillPath.fill()
    let knobD = pillH - 16
    let knobX = on ? pill.maxX - knobD - 8 : pill.minX + 8
    let knob = NSRect(x: knobX, y: pill.minY + 8, width: knobD, height: knobD)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: knob).fill()

    y -= (cardH + gap)
}

NSGraphicsContext.restoreGraphicsState()

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let data = rep.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
