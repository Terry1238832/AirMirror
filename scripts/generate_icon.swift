import AppKit
import Foundation

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024)
]

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let inset = rect.insetBy(dx: size * 0.04, dy: size * 0.04)
        let background = NSBezierPath(roundedRect: inset, xRadius: size * 0.22, yRadius: size * 0.22)
        NSColor(calibratedRed: 0.18, green: 0.16, blue: 0.46, alpha: 1).setFill()
        background.fill()

        let glow = NSBezierPath(ovalIn: NSRect(
            x: size * 0.18,
            y: size * 0.42,
            width: size * 0.64,
            height: size * 0.42
        ))
        NSColor(calibratedRed: 0.42, green: 0.38, blue: 0.98, alpha: 0.28).setFill()
        glow.fill()

        let screen = NSRect(x: size * 0.18, y: size * 0.38, width: size * 0.64, height: size * 0.40)
        let screenPath = NSBezierPath(roundedRect: screen, xRadius: size * 0.05, yRadius: size * 0.05)
        NSColor.white.withAlphaComponent(0.96).setFill()
        screenPath.fill()

        let display = screen.insetBy(dx: size * 0.035, dy: size * 0.035)
        NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.28, alpha: 1).setFill()
        NSBezierPath(roundedRect: display, xRadius: size * 0.03, yRadius: size * 0.03).fill()

        let stand = NSRect(x: size * 0.44, y: size * 0.30, width: size * 0.12, height: size * 0.09)
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(rect: stand).fill()

        let base = NSRect(x: size * 0.34, y: size * 0.26, width: size * 0.32, height: size * 0.045)
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: base, xRadius: size * 0.02, yRadius: size * 0.02).fill()

        let phone = NSBezierPath(roundedRect: NSRect(
            x: display.midX - size * 0.09,
            y: display.minY + size * 0.05,
            width: size * 0.18,
            height: size * 0.26
        ), xRadius: size * 0.03, yRadius: size * 0.03)
        NSColor(calibratedRed: 0.45, green: 0.78, blue: 1.0, alpha: 1).setFill()
        phone.fill()

        let waveColor = NSColor(calibratedRed: 0.62, green: 0.86, blue: 1.0, alpha: 0.9)
        waveColor.setStroke()
        for index in 0..<2 {
            let pad = CGFloat(index + 1) * size * 0.035
            let wave = NSBezierPath(roundedRect: NSRect(
                x: display.minX + size * 0.06 - pad,
                y: display.minY + size * 0.07 - pad * 0.4,
                width: display.width - size * 0.12 + pad * 2,
                height: display.height - size * 0.12 + pad * 0.8
            ), xRadius: size * 0.04, yRadius: size * 0.04)
            wave.lineWidth = max(1, size * 0.012)
            wave.stroke()
        }

        return true
    }
}

guard CommandLine.arguments.count > 1 else {
    fputs("usage: generate_icon.swift <output-dir>\n", stderr)
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for item in sizes {
    let image = drawIcon(size: CGFloat(item.size))
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        continue
    }
    try png.write(to: output.appendingPathComponent("\(item.name).png"))
}

print("wrote icons to \(output.path)")
