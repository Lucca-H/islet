#!/usr/bin/env swift
import AppKit

// Renders the Islet app icon at 1024×1024 to the path given as argv[1].
// A dark rounded tile with a bright "island" pill floating below a notch cutout.

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Background: rounded tile with a vertical gradient.
let tileRect = CGRect(x: 0, y: 0, width: size, height: size)
let tilePath = CGPath(roundedRect: tileRect, cornerWidth: 224, cornerHeight: 224, transform: nil)
ctx.addPath(tilePath)
ctx.clip()

let colors = [NSColor(calibratedWhite: 0.13, alpha: 1).cgColor,
              NSColor(calibratedWhite: 0.02, alpha: 1).cgColor] as CFArray
if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
}

// The "island" pill — the signature shape, centered.
let pillW = size * 0.52
let pillH = size * 0.19
let pillRect = CGRect(x: (size - pillW) / 2, y: (size - pillH) / 2, width: pillW, height: pillH)
let pill = CGPath(roundedRect: pillRect, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil)

// Soft glow.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 60, color: NSColor(calibratedRed: 0.4, green: 0.7, blue: 1, alpha: 0.7).cgColor)
ctx.addPath(pill)
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillPath()
ctx.restoreGState()

// Accent dot on the pill (media indicator motif).
let dotR = pillH * 0.24
let dotRect = CGRect(x: pillRect.maxX - dotR * 2 - pillH * 0.35,
                     y: pillRect.midY - dotR,
                     width: dotR * 2, height: dotR * 2)
ctx.addEllipse(in: dotRect)
ctx.setFillColor(NSColor(calibratedRed: 0.29, green: 0.55, blue: 1, alpha: 1).cgColor)
ctx.fillPath()

image.unlockFocus()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
