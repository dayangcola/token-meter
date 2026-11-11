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
        for (i, height) in [0.26, 0.43, 0.59].enumerated() {
            NSColor(calibratedRed: 0.34, green: 0.86, blue: 0.70, alpha: 0.55 + Double(i) * 0.22).setFill()
            let bar = NSRect(x: p * (0.245 + Double(i) * 0.185), y: p * 0.22, width: p * 0.14, height: p * height)
            NSBezierPath(roundedRect: bar, xRadius: p * 0.045, yRadius: p * 0.045).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let png = bitmap.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}
