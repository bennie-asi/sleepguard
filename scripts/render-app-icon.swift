import AppKit

// Vector artwork, rendered at every macOS icon size without external packages.
@main enum AppIconRenderer {
    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
                (transform as NSAffineTransform).concat()
                let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 196, yRadius: 196)
                NSGradient(starting: NSColor(calibratedRed: 0.07, green: 0.25, blue: 0.65, alpha: 1),
                           ending: NSColor(calibratedRed: 0.18, green: 0.57, blue: 0.99, alpha: 1))!.draw(in: tile, angle: 50)
                let moon = NSBezierPath()
                moon.windingRule = .evenOdd
                moon.appendOval(in: NSRect(x: 220, y: 296, width: 476, height: 476))
                moon.appendOval(in: NSRect(x: 350, y: 420, width: 456, height: 456))
                NSColor.white.setFill()
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(ovalIn: NSRect(x: 220, y: 296, width: 476, height: 476)).addClip()
                moon.fill()
                NSGraphicsContext.restoreGraphicsState()
                let star = NSBezierPath()
                star.move(to: NSPoint(x: 738, y: 812)); star.line(to: NSPoint(x: 764, y: 746))
                star.line(to: NSPoint(x: 830, y: 720)); star.line(to: NSPoint(x: 764, y: 694))
                star.line(to: NSPoint(x: 738, y: 628)); star.line(to: NSPoint(x: 712, y: 694))
                star.line(to: NSPoint(x: 646, y: 720)); star.line(to: NSPoint(x: 712, y: 746)); star.close(); star.fill()
                let shield = NSBezierPath()
                shield.move(to: NSPoint(x: 720, y: 492)); shield.line(to: NSPoint(x: 828, y: 446))
                shield.line(to: NSPoint(x: 828, y: 340)); shield.curve(to: NSPoint(x: 720, y: 238), controlPoint1: NSPoint(x: 828, y: 285), controlPoint2: NSPoint(x: 765, y: 250))
                shield.curve(to: NSPoint(x: 612, y: 340), controlPoint1: NSPoint(x: 675, y: 250), controlPoint2: NSPoint(x: 612, y: 285))
                shield.line(to: NSPoint(x: 612, y: 446)); shield.close(); shield.fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: 666, y: 368)); check.line(to: NSPoint(x: 706, y: 330)); check.line(to: NSPoint(x: 775, y: 405))
                check.lineWidth = 24; check.lineCapStyle = .round; check.lineJoinStyle = .round
                NSColor(calibratedRed: 0.09, green: 0.37, blue: 0.78, alpha: 1).setStroke(); check.stroke()
                NSGraphicsContext.restoreGraphicsState()
                let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
                try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
            }
        }
    }
}
