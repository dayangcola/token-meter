import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let p = CGFloat(pixels)
        let rect = NSRect(x: p * 0.055, y: p * 0.055, width: p * 0.89, height: p * 0.89)
        NSColor(calibratedRed: 0.065, green: 0.085, blue: 0.11, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: p * 0.20, yRadius: p * 0.20).fill()
        // Four meters in the panel's provider colours: Codex, Claude, Grok, Gemini.
        let tints: [(CGFloat, CGFloat, CGFloat)] = [(0.37, 0.87, 0.72), (0.92, 0.64, 0.46), (0.85, 0.88, 0.94), (0.59, 0.68, 1.0)]
        for (i, level) in [0.78, 0.42, 0.60, 1.0].enumerated() {
            let x = p * (0.215 + Double(i) * 0.155)
            let width = p * 0.105
            NSColor(calibratedWhite: 1, alpha: 0.09).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: p * 0.22, width: width, height: p * 0.56), xRadius: width / 2, yRadius: width / 2).fill()
            NSColor(calibratedRed: tints[i].0, green: tints[i].1, blue: tints[i].2, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: p * 0.22, width: width, height: p * 0.56 * level), xRadius: width / 2, yRadius: width / 2).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let png = bitmap.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}
