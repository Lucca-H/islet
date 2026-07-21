#!/usr/bin/env swift
import AppKit

// Renders the README hero banner to argv[1] (default banner.png), 1440×620.

let W = 1440.0, H = 620.0
let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Background gradient.
let bg = [NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1).cgColor,
          NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.03, alpha: 1).cgColor] as CFArray
if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bg, locations: [0, 1]) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
}

// A mock "notch" at the top center.
let notchW = 360.0, notchH = 42.0
let notch = CGRect(x: (W - notchW) / 2, y: H - notchH, width: notchW, height: notchH)
let notchPath = CGMutablePath()
notchPath.move(to: CGPoint(x: notch.minX - 22, y: notch.maxY))
notchPath.addQuadCurve(to: CGPoint(x: notch.minX, y: notch.maxY - 22), control: CGPoint(x: notch.minX, y: notch.maxY))
notchPath.addLine(to: CGPoint(x: notch.minX, y: notch.minY + 22))
notchPath.addQuadCurve(to: CGPoint(x: notch.minX + 22, y: notch.minY), control: CGPoint(x: notch.minX, y: notch.minY))
notchPath.addLine(to: CGPoint(x: notch.maxX - 22, y: notch.minY))
notchPath.addQuadCurve(to: CGPoint(x: notch.maxX, y: notch.minY + 22), control: CGPoint(x: notch.maxX, y: notch.minY))
notchPath.addLine(to: CGPoint(x: notch.maxX, y: notch.maxY - 22))
notchPath.addQuadCurve(to: CGPoint(x: notch.maxX + 22, y: notch.maxY), control: CGPoint(x: notch.maxX, y: notch.maxY))
notchPath.closeSubpath()
ctx.addPath(notchPath)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()

// Little media dot + bars inside the notch.
ctx.setFillColor(NSColor(calibratedRed: 0.29, green: 0.55, blue: 1, alpha: 1).cgColor)
ctx.fillEllipse(in: CGRect(x: notch.minX + 26, y: notch.midY - 9, width: 18, height: 18))
ctx.setFillColor(NSColor.white.cgColor)
for (i, h) in [10.0, 18.0, 13.0].enumerated() {
    ctx.fill(CGRect(x: notch.maxX - 46 + Double(i) * 9, y: notch.midY - h / 2, width: 5, height: h))
}

func draw(_ text: String, _ font: NSFont, _ color: NSColor, at p: CGPoint) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    NSAttributedString(string: text, attributes: attrs).draw(at: p)
}

// Wordmark + tagline.
draw("Islet", NSFont.systemFont(ofSize: 108, weight: .bold), .white, at: CGPoint(x: 120, y: 300))
draw("Your Mac's notch, reimagined.", NSFont.systemFont(ofSize: 34, weight: .medium),
     NSColor(calibratedWhite: 0.7, alpha: 1), at: CGPoint(x: 126, y: 250))

// Feature chips.
let chips = ["♪  Now Playing", "▤  Drop Shelf", "❏  Clipboard"]
var x = 126.0
for chip in chips {
    let font = NSFont.systemFont(ofSize: 22, weight: .semibold)
    let size = NSAttributedString(string: chip, attributes: [.font: font]).size()
    let rect = CGRect(x: x, y: 150, width: size.width + 44, height: 52)
    let path = CGPath(roundedRect: rect, cornerWidth: 26, cornerHeight: 26, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.08).cgColor)
    ctx.fillPath()
    draw(chip, font, NSColor(calibratedWhite: 0.92, alpha: 1), at: CGPoint(x: x + 22, y: 164))
    x += size.width + 44 + 20
}

image.unlockFocus()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "banner.png"
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
