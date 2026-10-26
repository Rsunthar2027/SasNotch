// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Modified for SasNotch by SasNotch contributors, 2026

// Generates every icon asset from the SVG masters in Branding/:
// - Branding/sasquatch-icon.svg     → the app iconset, AppIcon.icns and,
//   with --appiconset <dir>, an asset-catalog AppIcon.appiconset
// - Branding/sasquatch-template.svg → the menu bar template glyph and the
//   BrandMark the app tints for its headers, onboarding and About
// AppKit reads SVG natively, so the Command Line Tools are enough.
import AppKit

// Current macOS misreads PNG payloads in the legacy small chunks. It downsamples
// ic07 for 1x and uses the explicit ic11/ic12 representations on Retina displays.
let iconSizes: [(name: String, px: Int, icnsType: String?)] = [
    ("icon_16x16", 16, nil), ("icon_16x16@2x", 32, "ic11"),
    ("icon_32x32", 32, nil), ("icon_32x32@2x", 64, "ic12"),
    ("icon_128x128", 128, "ic07"), ("icon_128x128@2x", 256, "ic13"),
    ("icon_256x256", 256, "ic08"), ("icon_256x256@2x", 512, "ic14"),
    ("icon_512x512", 512, "ic09"), ("icon_512x512@2x", 1024, "ic10"),
]

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()

func loadSVG(_ name: String) -> NSImage {
    let path = projectDir.appendingPathComponent("Branding/\(name)").path
    guard let image = NSImage(contentsOfFile: path) else {
        print("could not load \(path)")
        exit(1)
    }
    return image
}

let appIconMaster = loadSVG("sasquatch-icon.svg")
let markMaster = loadSVG("sasquatch-template.svg")

func bitmapCanvas(_ px: Int, _ py: Int) -> NSBitmapImageRep? {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py,
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
}

/// Draws `image` into `rep`, keeping its aspect ratio and centering it in `target`.
func render(_ image: NSImage, into rep: NSBitmapImageRep, target: CGRect) {
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    let scale = min(target.width / image.size.width, target.height / image.size.height)
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let rect = CGRect(x: target.midX - size.width / 2, y: target.midY - size.height / 2,
                      width: size.width, height: size.height)
    image.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
}

func renderAppIcon(px: Int) -> Data? {
    guard let rep = bitmapCanvas(px, px) else { return nil }
    rep.size = NSSize(width: px, height: px)
    render(appIconMaster, into: rep, target: CGRect(x: 0, y: 0, width: px, height: px))
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Menu bar glyph (template)

// Keep in sync with BlackHoleGlyph.pointSize in
// Sources/SasNotch/App/StatusItemController.swift; `--selftest` enforces it.
let menuBarCanvas = (width: 22, height: 20)
/// The head-and-shoulders mark is nearly square, so its height sets the size.
let menuBarGlyphHeight: CGFloat = 16

func renderMenuBarIcon(scale: Int) -> Data? {
    let width = menuBarCanvas.width * scale, height = menuBarCanvas.height * scale
    guard let rep = bitmapCanvas(width, height) else { return nil }
    // The rep's size is in points, so the context draws in points too.
    rep.size = NSSize(width: menuBarCanvas.width, height: menuBarCanvas.height)
    let canvasHeight = CGFloat(menuBarCanvas.height)
    render(markMaster, into: rep,
           target: CGRect(x: 0, y: (canvasHeight - menuBarGlyphHeight) / 2,
                          width: CGFloat(menuBarCanvas.width), height: menuBarGlyphHeight))
    return rep.representation(using: .png, properties: [:])
}

func appendFourCC(_ value: String, to data: inout Data) {
    data.append(contentsOf: value.utf8)
}

func appendUInt32BE(_ value: Int, to data: inout Data) {
    let clamped = UInt32(value)
    data.append(UInt8((clamped >> 24) & 0xff))
    data.append(UInt8((clamped >> 16) & 0xff))
    data.append(UInt8((clamped >> 8) & 0xff))
    data.append(UInt8(clamped & 0xff))
}

func writeICNS(entries: [(type: String, data: Data)], to url: URL) throws {
    let totalLength = 8 + entries.reduce(0) { $0 + 8 + $1.data.count }
    var icns = Data()
    appendFourCC("icns", to: &icns)
    appendUInt32BE(totalLength, to: &icns)
    for entry in entries {
        appendFourCC(entry.type, to: &icns)
        appendUInt32BE(8 + entry.data.count, to: &icns)
        icns.append(entry.data)
    }
    try icns.write(to: url)
}

/// Writes an asset-catalog icon set with every macOS size, for Xcode users and
/// for actool when a full Xcode is present.
func writeAppIconSet(to dir: String) throws {
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for (name, px, _) in iconSizes {
        guard let data = renderAppIcon(px: px) else { throw CocoaError(.fileWriteUnknown) }
        let file = "\(name).png"
        try data.write(to: URL(fileURLWithPath: "\(dir)/\(file)"))
        let points = name.hasSuffix("@2x") ? px / 2 : px
        images.append(["idiom": "mac", "size": "\(points)x\(points)",
                       "scale": name.hasSuffix("@2x") ? "2x" : "1x", "filename": file])
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: URL(fileURLWithPath: "\(dir)/Contents.json"))
    print("appiconset written to \(dir)")
}

if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--appiconset" {
    try writeAppIconSet(to: CommandLine.arguments[2])
    exit(0)
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var icnsEntries: [(type: String, data: Data)] = []
for (name, px, icnsType) in iconSizes {
    guard let data = renderAppIcon(px: px) else {
        print("failed to render \(name)")
        exit(1)
    }
    try data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    if let icnsType {
        icnsEntries.append((type: icnsType, data: data))
    }
}
try writeICNS(entries: icnsEntries, to: URL(fileURLWithPath: "\(outDir)/../AppIcon.icns"))

for scale in [1, 2] {
    guard let data = renderMenuBarIcon(scale: scale) else {
        print("failed to render menu bar icon @\(scale)x")
        exit(1)
    }
    let suffix = scale == 1 ? "" : "@2x"
    try data.write(to: URL(fileURLWithPath: "\(outDir)/../MenuBarIcon\(suffix).png"))
}

// Monochrome mark for in-app use (panel header, onboarding, About), tinted at runtime.
let markWidth = 640
let markHeight = Int(CGFloat(markWidth) * markMaster.size.height / markMaster.size.width)
if let rep = bitmapCanvas(markWidth, markHeight) {
    rep.size = NSSize(width: markWidth, height: markHeight)
    render(markMaster, into: rep, target: CGRect(x: 0, y: 0, width: markWidth, height: markHeight))
    if let data = rep.representation(using: .png, properties: [:]) {
        try data.write(to: URL(fileURLWithPath: "\(outDir)/../BrandMark.png"))
    }
}
print("iconset written to \(outDir)")
