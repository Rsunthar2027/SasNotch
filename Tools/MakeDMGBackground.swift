// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Modified for SasNotch by SasNotch contributors, 2026

// Draws the installer window's background: a misty pine forest at dawn, a
// trail of sasquatch footprints from the app to the Applications folder,
// and the sasquatch himself peeking from behind a tree.
//
// The window is 600×400 points, with the two icons centred at (150, 200)
// and (450, 200) from the top-left. Finder draws their labels in dark type
// just below them, so the band around the icons stays light and misty; the
// dark trees frame the edges and the forest floor carries the white text.

import AppKit

let scale: CGFloat = 2
let widthPt: CGFloat = 600, heightPt: CGFloat = 400
let px = Int(widthPt * scale), py = Int(heightPt * scale)

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let markPath = scriptDir.deletingLastPathComponent().appendingPathComponent("Branding/sasquatch-template.svg").path

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
rep.size = NSSize(width: widthPt, height: heightPt)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
ctx.cgContext.scaleBy(x: scale, y: scale)   // draw in points, output at 2×
let full = NSRect(x: 0, y: 0, width: widthPt, height: heightPt)

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

// Coordinates are bottom-up: y = 0 is the window's bottom edge.

// Dawn sky: soft sage at the top, warm mist toward the trees.
NSGradient(colors: [rgb(201, 220, 205), rgb(232, 238, 224), rgb(246, 240, 226)],
           atLocations: [0, 0.55, 1], colorSpace: .sRGB)?.draw(in: full, angle: -90)

// A low sun glowing through the mist, behind the title.
NSGradient(colors: [rgb(255, 236, 196, 0.85), rgb(255, 236, 196, 0)])?
    .draw(fromCenter: NSPoint(x: 300, y: 330), radius: 0, toCenter: NSPoint(x: 300, y: 330), radius: 170, options: [])

/// A pine: a trunk and stacked tiers, widest at the bottom.
func pine(x: CGFloat, base: CGFloat, height: CGFloat, color: NSColor, tiers: Int = 4) {
    color.setFill()
    let width = height * 0.46
    let trunk = NSRect(x: x - width * 0.05, y: base, width: width * 0.1, height: height * 0.12)
    NSBezierPath(rect: trunk).fill()
    for tier in 0..<tiers {
        let t = CGFloat(tier) / CGFloat(tiers)
        let tierBase = base + height * (0.1 + t * 0.62)
        let tierWidth = width * (1 - t * 0.62)
        let tierHeight = height * 0.38
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x - tierWidth / 2, y: tierBase))
        path.line(to: NSPoint(x: x + tierWidth / 2, y: tierBase))
        path.line(to: NSPoint(x: x, y: tierBase + tierHeight))
        path.close()
        path.fill()
    }
}

/// A row of pines across a band, with sizes that vary but repeat exactly.
func treeLine(base: CGFloat, from: CGFloat, to: CGFloat, step: CGFloat, height: CGFloat, color: NSColor, seed: Int) {
    var x = from
    var i = seed
    while x <= to {
        let wobble = CGFloat((i * 37) % 11) / 10      // 0…1, deterministic
        pine(x: x + wobble * step * 0.3, base: base - wobble * 4, height: height * (0.75 + wobble * 0.4),
             color: color, tiers: 3 + i % 2)
        x += step * (0.8 + wobble * 0.4)
        i += 1
    }
}

// Far ridge: faint pines fading into the mist behind the icons.
treeLine(base: 150, from: -10, to: 610, step: 34, height: 90, color: rgb(170, 196, 178, 0.55), seed: 3)
treeLine(base: 120, from: 10, to: 600, step: 40, height: 110, color: rgb(140, 174, 152, 0.55), seed: 7)

// Morning mist over the far trees, keeping the icon band light for Finder's labels.
NSGradient(colors: [rgb(246, 242, 230, 0), rgb(246, 242, 230, 0.9), rgb(246, 242, 230, 0.9), rgb(246, 242, 230, 0)],
           atLocations: [0, 0.3, 0.7, 1], colorSpace: .sRGB)?
    .draw(in: NSRect(x: 0, y: 105, width: widthPt, height: 200), angle: 90)

// Near forest: dark pines framing both edges.
let deep = rgb(31, 58, 46)
let deeper = rgb(22, 42, 34)
pine(x: 18, base: 40, height: 330, color: deep, tiers: 5)
pine(x: 50, base: 30, height: 230, color: deeper, tiers: 5)
pine(x: 584, base: 40, height: 340, color: deep, tiers: 5)
pine(x: 552, base: 34, height: 225, color: deeper, tiers: 5)

// The sasquatch, peeking out from behind the right-hand pines.
if let mark = NSImage(contentsOfFile: markPath) {
    let tinted = NSImage(size: mark.size, flipped: false) { rect in
        mark.draw(in: rect)
        rgb(70, 45, 27).set()
        rect.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: NSRect(x: 500, y: 54, width: 58, height: 56), from: .zero, operation: .sourceOver, fraction: 1)
    // The trunk he hides behind, drawn over him.
    pine(x: 552, base: 34, height: 110, color: deeper, tiers: 2)
}

// Forest floor along the bottom, carrying the instruction.
let floor = NSBezierPath()
floor.move(to: NSPoint(x: 0, y: 0))
floor.line(to: NSPoint(x: 0, y: 58))
floor.curve(to: NSPoint(x: 300, y: 50), controlPoint1: NSPoint(x: 90, y: 70), controlPoint2: NSPoint(x: 200, y: 44))
floor.curve(to: NSPoint(x: 600, y: 60), controlPoint1: NSPoint(x: 400, y: 56), controlPoint2: NSPoint(x: 520, y: 70))
floor.line(to: NSPoint(x: 600, y: 0))
floor.close()
deeper.setFill()
floor.fill()
treeLine(base: 46, from: 110, to: 490, step: 26, height: 30, color: deeper, seed: 5)

// Footprints from the app to the Applications folder, left and right in turn.
/// One bare footprint: a sole and five toes, pointing along +x.
func footprint(at center: NSPoint, left: Bool, color: NSColor) {
    color.setFill()
    // A broad sole narrowing toward the heel, the way a big bare foot lands.
    let sole = NSBezierPath()
    sole.move(to: NSPoint(x: center.x - 12, y: center.y))
    sole.curve(to: NSPoint(x: center.x + 7, y: center.y + 6.5),
               controlPoint1: NSPoint(x: center.x - 12, y: center.y + 5), controlPoint2: NSPoint(x: center.x, y: center.y + 7))
    sole.curve(to: NSPoint(x: center.x + 7, y: center.y - 6.5),
               controlPoint1: NSPoint(x: center.x + 12, y: center.y + 5.5), controlPoint2: NSPoint(x: center.x + 12, y: center.y - 5.5))
    sole.curve(to: NSPoint(x: center.x - 12, y: center.y),
               controlPoint1: NSPoint(x: center.x, y: center.y - 7), controlPoint2: NSPoint(x: center.x - 12, y: center.y - 5))
    sole.fill()
    let side: CGFloat = left ? 1 : -1
    // Big toe on the inside, the others curving away from it.
    let toes: [(dx: CGFloat, dy: CGFloat, r: CGFloat)] = [
        (14.5, 4.6, 3.1), (16.2, 0.6, 2.4), (15.6, -2.9, 2.1), (14.0, -5.8, 1.9), (11.6, -8.0, 1.7),
    ]
    for toe in toes {
        let y = center.y + toe.dy * side
        NSBezierPath(ovalIn: NSRect(x: center.x + toe.dx - toe.r, y: y - toe.r, width: toe.r * 2, height: toe.r * 2)).fill()
    }
}
let trailY: CGFloat = 200
let fur = rgb(91, 58, 34)
for (index, x) in stride(from: CGFloat(238), through: 340, by: 34).enumerated() {
    let left = index % 2 == 0
    footprint(at: NSPoint(x: x, y: trailY + (left ? 9 : -9)), left: left,
              color: fur.withAlphaComponent(0.5 + CGFloat(index) * 0.12))
}
// A small chevron where the trail meets the folder.
let chevron = NSBezierPath()
chevron.lineWidth = 4
chevron.lineCapStyle = .round
chevron.lineJoinStyle = .round
chevron.move(to: NSPoint(x: 366, y: trailY + 11))
chevron.line(to: NSPoint(x: 377, y: trailY))
chevron.line(to: NSPoint(x: 366, y: trailY - 11))
fur.withAlphaComponent(0.85).setStroke()
chevron.stroke()

// Title over the sunrise.
let title = "SasNotch"
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 28, weight: .heavy),
    .foregroundColor: fur,
    .kern: 0.5,
]
let titleSize = title.size(withAttributes: titleAttrs)
title.draw(at: NSPoint(x: (widthPt - titleSize.width) / 2, y: heightPt - 74), withAttributes: titleAttrs)
let tagline = "Your notch, with a little more personality"
let taglineAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
    .foregroundColor: fur.withAlphaComponent(0.7),
]
let taglineSize = tagline.size(withAttributes: taglineAttrs)
tagline.draw(at: NSPoint(x: (widthPt - taglineSize.width) / 2, y: heightPt - 94), withAttributes: taglineAttrs)

// The instruction, on the forest floor.
let instruction = "Drag SasNotch into Applications to install"
let instructionAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
    .foregroundColor: rgb(244, 236, 220),
]
let instructionSize = instruction.size(withAttributes: instructionAttrs)
instruction.draw(at: NSPoint(x: (widthPt - instructionSize.width) / 2, y: 18), withAttributes: instructionAttrs)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try data.write(to: URL(fileURLWithPath: out))
    print("dmg background written to \(out)")
} catch {
    print("failed: \(error)")
    exit(1)
}
