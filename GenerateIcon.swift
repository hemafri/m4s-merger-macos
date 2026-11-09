import AppKit
import Foundation

// Original vector geometry, rasterized at every macOS app-icon size.
// A playback triangle and a waveform share one screen: picture + sound.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func render(size: Int) throws -> Data {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 184, yRadius: 184)
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 26
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(srgbRed: 0.055, green: 0.30, blue: 0.34, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    let screen = NSBezierPath(roundedRect: NSRect(x: 224, y: 304, width: 576, height: 424), xRadius: 64, yRadius: 64)
    NSColor.white.setStroke()
    screen.lineWidth = 42
    screen.stroke()

    let play = NSBezierPath()
    play.move(to: NSPoint(x: 330, y: 405))
    play.line(to: NSPoint(x: 330, y: 627))
    play.line(to: NSPoint(x: 494, y: 516))
    play.close()
    NSColor.white.setFill()
    play.fill()

    NSColor(srgbRed: 0.50, green: 0.92, blue: 0.77, alpha: 1).setStroke()
    for (x, height) in [(554.0, 108.0), (616.0, 212.0), (678.0, 148.0)] {
        let wave = NSBezierPath()
        wave.move(to: NSPoint(x: x, y: 516 - height / 2))
        wave.line(to: NSPoint(x: x, y: 516 + height / 2))
        wave.lineWidth = 34
        wave.lineCapStyle = .round
        wave.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

for pointSize in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let file = "icon_\(pointSize)x\(pointSize)\(suffix).png"
        try render(size: pointSize * scale).write(to: destination.appendingPathComponent(file))
    }
}
