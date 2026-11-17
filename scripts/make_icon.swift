// Renders the SipBuddy app icon (a friendly water drop on a soft aqua tile).
// Usage: swift scripts/make_icon.swift <output-dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func drop(in r: CGRect) -> NSBezierPath {
    let p = NSBezierPath()
    let rad = r.width / 2, cy = r.minY + rad, k: CGFloat = 0.5523
    // AppKit is y-up: tip at maxY, round bottom at minY.
    p.move(to: CGPoint(x: r.midX, y: r.maxY))
    p.curve(to: CGPoint(x: r.maxX, y: cy), controlPoint1: CGPoint(x: r.midX + rad * 0.25, y: r.maxY - (r.maxY - cy) * 0.35), controlPoint2: CGPoint(x: r.maxX, y: cy + rad * 0.75))
    p.curve(to: CGPoint(x: r.midX, y: r.minY), controlPoint1: CGPoint(x: r.maxX, y: cy - rad * k), controlPoint2: CGPoint(x: r.midX + rad * k, y: r.minY))
    p.curve(to: CGPoint(x: r.minX, y: cy), controlPoint1: CGPoint(x: r.midX - rad * k, y: r.minY), controlPoint2: CGPoint(x: r.minX, y: cy - rad * k))
    p.curve(to: CGPoint(x: r.midX, y: r.maxY), controlPoint1: CGPoint(x: r.minX, y: cy + rad * 0.75), controlPoint2: CGPoint(x: r.midX - rad * 0.25, y: r.maxY - (r.maxY - cy) * 0.35))
    p.close()
    return p
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824/1024 tile with ~185 corner radius.
    let inset = s * 100 / 1024
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.25); shadow.shadowBlurRadius = s * 0.02; shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSGradient(colors: [NSColor(red: 0.90, green: 0.97, blue: 1.0, alpha: 1), NSColor(red: 0.70, green: 0.88, blue: 0.99, alpha: 1)])!.draw(in: tilePath, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Drop
    let dw = tile.width * 0.50, dh = dw * 1.32
    let dr = CGRect(x: tile.midX - dw / 2, y: tile.midY - dh / 2 - tile.height * 0.02, width: dw, height: dh)
    let dp = drop(in: dr)
    NSGraphicsContext.saveGraphicsState()
    let ds = NSShadow(); ds.shadowColor = NSColor(red: 0.05, green: 0.3, blue: 0.7, alpha: 0.35); ds.shadowBlurRadius = s * 0.03; ds.shadowOffset = NSSize(width: 0, height: -s * 0.015)
    ds.set()
    NSGradient(colors: [NSColor(red: 0.38, green: 0.86, blue: 0.96, alpha: 1), NSColor(red: 0.14, green: 0.48, blue: 0.95, alpha: 1)])!.draw(in: dp, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Highlight
    NSColor.white.withAlphaComponent(0.55).setFill()
    let hl = NSBezierPath(ovalIn: CGRect(x: dr.minX + dw * 0.2, y: dr.minY + dh * 0.42, width: dw * 0.12, height: dh * 0.2))
    hl.fill()

    // Friendly face (only where it's legible)
    if px >= 64 {
        NSColor.white.setFill()
        let eyeW = dw * 0.075, eyeH = dw * 0.11, eyeY = dr.minY + dh * 0.30
        NSBezierPath(ovalIn: CGRect(x: dr.midX - dw * 0.17 - eyeW / 2, y: eyeY, width: eyeW, height: eyeH)).fill()
        NSBezierPath(ovalIn: CGRect(x: dr.midX + dw * 0.17 - eyeW / 2, y: eyeY, width: eyeW, height: eyeH)).fill()
        let smile = NSBezierPath()
        smile.lineWidth = dw * 0.045
        smile.lineCapStyle = .round
        smile.appendArc(withCenter: CGPoint(x: dr.midX, y: dr.minY + dh * 0.27), radius: dw * 0.12, startAngle: 200, endAngle: 340)
        NSColor.white.setStroke()
        smile.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("icon_\(size).png")
    try! render(size).write(to: url)
}
print("Icons written to \(outDir)")
