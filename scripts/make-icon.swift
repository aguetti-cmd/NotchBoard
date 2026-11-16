// Draws the NotchBoard app icon and writes Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift   (from the repo root)
//
// Design: a dark squircle on Apple's icon grid (824 pt body in a 1024 canvas),
// a black notch at the top flowing into a frosted panel, with a teal
// waveform and two small card blocks. Teal is the Draft & Focus #54CBBB.

import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
let body: CGFloat = 824
let inset = (canvas - body) / 2
let teal = CGColor(red: 0x54 / 255, green: 0xCB / 255, blue: 0xBB / 255, alpha: 1)

/// Continuous-corner rounded rect, close to Apple's squircle.
func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func draw(in ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // Flip so y grows downward, like the design reads.
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)

    let iconRect = CGRect(x: inset, y: inset, width: body, height: body)
    let iconPath = squircle(iconRect, radius: body * 0.225)

    // Soft drop shadow under the squircle.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(iconPath)
    ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient.
    ctx.saveGState()
    ctx.addPath(iconPath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.20, green: 0.25, blue: 0.27, alpha: 1),
        CGColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: canvas / 2, y: inset),
                           end: CGPoint(x: canvas / 2, y: inset + body), options: [])

    // Teal glow behind the panel.
    let glow = CGGradient(colorsSpace: space, colors: [
        teal.copy(alpha: 0.45)!, teal.copy(alpha: 0)!,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: canvas / 2, y: 470), startRadius: 0,
                           endCenter: CGPoint(x: canvas / 2, y: 470), endRadius: 380, options: [])

    // Frosted panel hanging from the top edge.
    // Starts above the squircle so its top corners are clipped away.
    let panel = CGRect(x: inset + 92, y: inset - 140, width: body - 184, height: 620)
    let panelPath = squircle(panel, radius: 92)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: CGColor(gray: 0, alpha: 0.5))
    ctx.addPath(panelPath)
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.13))
    ctx.fillPath()
    ctx.restoreGState()
    // Glass highlight along the panel's lower edge.
    ctx.addPath(panelPath)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.28))
    ctx.setLineWidth(4)
    ctx.strokePath()

    // The notch.
    let notchWidth: CGFloat = 250
    let notch = CGRect(x: canvas / 2 - notchWidth / 2, y: inset - 40, width: notchWidth, height: 128)
    ctx.addPath(squircle(notch, radius: 44))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()

    // Waveform in teal, centred in the panel.
    let bars: [CGFloat] = [0.35, 0.7, 1.0, 0.55, 0.85, 0.45, 0.65]
    let barWidth: CGFloat = 26
    let gap: CGFloat = 18
    let total = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
    var x = canvas / 2 - total / 2
    let midY: CGFloat = 300
    for h in bars {
        let height = 150 * h
        let bar = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
        ctx.addPath(squircle(bar, radius: barWidth / 2))
        ctx.setFillColor(teal)
        ctx.fillPath()
        x += barWidth + gap
    }

    // Two small cards below the waveform.
    let cardWidth: CGFloat = 250
    let cardY: CGFloat = 400
    for (i, alpha) in [0.30, 0.18].enumerated() {
        let cx = canvas / 2 - cardWidth - 12 + CGFloat(i) * (cardWidth + 24)
        ctx.addPath(squircle(CGRect(x: cx, y: cardY, width: cardWidth, height: 46), radius: 23))
        ctx.setFillColor(CGColor(gray: 1, alpha: alpha))
        ctx.fillPath()
    }
    ctx.restoreGState()

    // Fine rim light on the squircle.
    ctx.addPath(iconPath)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
    ctx.setLineWidth(3)
    ctx.strokePath()
}

func png(size: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    draw(in: ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try png(size: 1024).write(to: URL(fileURLWithPath: "build/AppIcon-1024.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
