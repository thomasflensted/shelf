import AppKit
// Renders the app icon: a stack of book spines on a warm rounded square.
let out = CommandLine.arguments[1]
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
    let inset = r.insetBy(dx: 100, dy: 100)
    let bg = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1), NSColor(red: 0.88, green: 0.82, blue: 0.70, alpha: 1)])!.draw(in: bg, angle: -90)
    let colors: [NSColor] = [.init(red: 0.62, green: 0.20, blue: 0.18, alpha: 1), .init(red: 0.17, green: 0.32, blue: 0.45, alpha: 1),
                             .init(red: 0.85, green: 0.62, blue: 0.24, alpha: 1), .init(red: 0.23, green: 0.42, blue: 0.30, alpha: 1)]
    let widths: [CGFloat] = [120, 95, 140, 105], heights: [CGFloat] = [520, 460, 560, 420]
    var x: CGFloat = 245; let base: CGFloat = 250
    for i in 0..<4 {
        let rect = NSRect(x: x, y: base, width: widths[i], height: heights[i])
        let p = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        if i == 3 { NSGraphicsContext.current?.saveGraphicsState(); let t = NSAffineTransform(); t.translateX(by: rect.minX, yBy: rect.minY); t.rotate(byDegrees: 12); t.translateX(by: -rect.minX, yBy: -rect.minY); t.concat() }
        colors[i].setFill(); p.fill()
        NSColor.white.withAlphaComponent(0.35).setFill()
        NSBezierPath(rect: NSRect(x: rect.minX + 18, y: rect.maxY - 90, width: rect.width - 36, height: 14)).fill()
        NSBezierPath(rect: NSRect(x: rect.minX + 18, y: rect.minY + 60, width: rect.width - 36, height: 14)).fill()
        if i == 3 { NSGraphicsContext.current?.restoreGraphicsState() }
        x += widths[i] + 10
    }
    NSColor(red: 0.42, green: 0.30, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 200, y: 215, width: 624, height: 38), xRadius: 8, yRadius: 8).fill()
    return true
}
let set = out + "/Shelf.iconset"
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = s * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(s)x\(s).png" : "icon_\(s)x\(s)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(set)/\(name)"))
    }
}
