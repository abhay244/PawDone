// Frames the raw simulator screenshots in raw/ with a caption, for the App Store.
// Run from this folder: swift make-screenshots.swift
// Output: screenshots/, 1320x2868 (the 6.9" iPhone size App Store Connect asks for).
// To retake the raw screenshots, see "Screenshots" in docs/APP_STORE.md.

import AppKit

struct Shot {
    let raw: String
    let title: String
    let subtitle: String
}

// App Store order: the first three show in search results.
let shots = [
    Shot(raw: "today", title: "Your pet's whole day\nin one list",
         subtitle: "Walks, meals and meds, and who did each one"),
    Shot(raw: "family", title: "Share the care with\nfamily and helpers",
         subtitle: "Invite up to 2 people with Premium"),
    Shot(raw: "reports", title: "See what was done\nand what was missed",
         subtitle: "Every day of the month, task by task"),
    Shot(raw: "task", title: "Reminders that keep\neveryone on time",
         subtitle: "Add instructions so helpers get it right"),
    Shot(raw: "premium", title: "Photo proof and\ndone notifications",
         subtitle: "Everyone sees it the moment it's done"),
    Shot(raw: "schedule", title: "Set the routine once",
         subtitle: "Every day, or only on the days you pick"),
]

let canvas = CGSize(width: 1320, height: 2868)
let topColor = NSColor(srgbRed: 0.957, green: 0.357, blue: 0.310, alpha: 1)    // #F45B4F
let bottomColor = NSColor(srgbRed: 1.0, green: 0.541, blue: 0.396, alpha: 1)   // #FF8A65

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    guard let rounded = font.fontDescriptor.withDesign(.rounded) else { return font }
    return NSFont(descriptor: rounded, size: size) ?? font
}

func centeredText(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineHeightMultiple = 1.05
    return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}

let textWidth = canvas.width - 160

func height(of text: NSAttributedString) -> CGFloat {
    ceil(text.boundingRect(with: CGSize(width: textWidth, height: 1000), options: .usesLineFragmentOrigin).height)
}

/// Draws text with its top at `top`, measured from the top of the canvas.
func draw(_ text: NSAttributedString, top: CGFloat) {
    let height = height(of: text)
    text.draw(with: CGRect(x: 80, y: canvas.height - top - height, width: textWidth, height: height),
              options: .usesLineFragmentOrigin)
}

func render(_ shot: Shot) throws {
    guard let screenshot = NSImage(contentsOfFile: "raw/\(shot.raw).png") else {
        throw NSError(domain: "make-screenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing raw/\(shot.raw).png"])
    }
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = canvas  // one point per pixel

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    NSGradient(starting: bottomColor, ending: topColor)!.draw(in: CGRect(origin: .zero, size: canvas), angle: 90)

    // The screenshot in a dark bezel, like a phone, with the caption centred above it.
    let scale: CGFloat = 0.74
    let screen = CGSize(width: canvas.width * scale, height: canvas.height * scale)
    let bezel: CGFloat = 16
    let screenTop: CGFloat = 690

    let title = centeredText(shot.title, font: roundedFont(size: 100, weight: .bold), color: .white)
    let subtitle = centeredText(shot.subtitle, font: roundedFont(size: 48, weight: .medium),
                                color: NSColor.white.withAlphaComponent(0.9))
    let gap: CGFloat = 28
    let captionTop = (screenTop - bezel - (height(of: title) + gap + height(of: subtitle))) / 2 + 20
    draw(title, top: captionTop)
    draw(subtitle, top: captionTop + height(of: title) + gap)
    let screenRect = CGRect(x: (canvas.width - screen.width) / 2, y: canvas.height - screenTop - screen.height,
                            width: screen.width, height: screen.height)
    let bezelRect = screenRect.insetBy(dx: -bezel, dy: -bezel)
    let radius: CGFloat = 130

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 60
    shadow.shadowOffset = CGSize(width: 0, height: -24)
    shadow.set()
    NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).setFill()
    NSBezierPath(roundedRect: bezelRect, xRadius: radius + bezel, yRadius: radius + bezel).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screenRect, xRadius: radius, yRadius: radius).addClip()
    screenshot.draw(in: screenRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    let index = shots.firstIndex { $0.raw == shot.raw }! + 1
    let output = "screenshots/\(index)-\(shot.raw).jpg"
    // App Store Connect rejects screenshots with transparency, so save as JPEG.
    let flattened = NSBitmapImageRep(cgImage: rep.cgImage!.copy(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!)
    guard let data = flattened.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
        throw NSError(domain: "make-screenshots", code: 2)
    }
    try data.write(to: URL(fileURLWithPath: output))
    print("Wrote \(output)")
}

for shot in shots {
    try render(shot)
}
