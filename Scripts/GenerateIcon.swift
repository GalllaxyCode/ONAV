import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func drawIcon(size: Int) -> NSBitmapImageRep {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size) / 1024); transform.concat()
    let rect = CGRect(x: 35, y: 35, width: 954, height: 954)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 213, yRadius: 213)
    NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.21, blue: 0.20, alpha: 1), ending: NSColor(calibratedRed: 0.013, green: 0.024, blue: 0.025, alpha: 1))!.draw(in: shape, angle: 130)
    NSColor(calibratedRed: 0.37, green: 0.48, blue: 0.43, alpha: 0.5).setStroke(); shape.lineWidth = 5; shape.stroke()
    NSGraphicsContext.saveGraphicsState(); shape.addClip()
    for i in 0..<100 {
        NSColor.white.withAlphaComponent(i % 3 == 0 ? 0.027 : 0.009).setFill()
        CGRect(x: 35, y: 45 + i * 10, width: 954, height: 2).fill()
    }
    let amber = NSColor(calibratedRed: 0.91, green: 0.63, blue: 0.30, alpha: 1)
    for i in 0..<4 {
        let ring = NSBezierPath(ovalIn: CGRect(x: 162 + i * 39, y: 148 + i * 39, width: 700 - i * 78, height: 700 - i * 78))
        amber.withAlphaComponent(0.12 + CGFloat(i) * 0.07).setStroke(); ring.lineWidth = 5; ring.stroke()
    }
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.9); shadow.shadowBlurRadius = 50; shadow.shadowOffset = NSSize(width: 20, height: -26); shadow.set()
    let mask = NSBezierPath()
    mask.move(to: CGPoint(x: 380, y: 770))
    mask.curve(to: CGPoint(x: 635, y: 770), controlPoint1: CGPoint(x: 420, y: 830), controlPoint2: CGPoint(x: 590, y: 825))
    mask.curve(to: CGPoint(x: 592, y: 323), controlPoint1: CGPoint(x: 690, y: 650), controlPoint2: CGPoint(x: 633, y: 440))
    mask.line(to: CGPoint(x: 526, y: 254)); mask.line(to: CGPoint(x: 458, y: 310))
    mask.curve(to: CGPoint(x: 380, y: 770), controlPoint1: CGPoint(x: 410, y: 439), controlPoint2: CGPoint(x: 347, y: 664))
    NSGradient(starting: NSColor(calibratedRed: 0.79, green: 0.80, blue: 0.68, alpha: 1), ending: NSColor(calibratedRed: 0.22, green: 0.32, blue: 0.29, alpha: 1))!.draw(in: mask, angle: 0)
    NSShadow().set()
    let slit = NSBezierPath(); slit.move(to: CGPoint(x: 404, y: 642)); slit.line(to: CGPoint(x: 623, y: 626)); slit.line(to: CGPoint(x: 610, y: 604)); slit.line(to: CGPoint(x: 405, y: 617)); slit.close()
    NSColor(calibratedRed: 0.017, green: 0.033, blue: 0.031, alpha: 1).setFill(); slit.fill()
    amber.setFill(); NSBezierPath(ovalIn: CGRect(x: 542, y: 611, width: 10, height: 13)).fill()
    NSColor.black.withAlphaComponent(0.5).setStroke()
    let crack = NSBezierPath(); crack.lineWidth = 5; crack.move(to: CGPoint(x: 484, y: 794)); crack.line(to: CGPoint(x: 469, y: 736)); crack.line(to: CGPoint(x: 498, y: 709)); crack.line(to: CGPoint(x: 483, y: 650)); crack.stroke()
    for i in 0..<4 {
        let stitch = NSBezierPath(); stitch.move(to: CGPoint(x: 492, y: 381 + i * 28)); stitch.line(to: CGPoint(x: 546, y: 389 + i * 28)); stitch.lineWidth = 7; stitch.stroke()
    }
    amber.withAlphaComponent(0.75).setFill(); CGRect(x: 229, y: 140, width: 568, height: 4).fill()
    NSGraphicsContext.restoreGraphicsState()
    image.unlockFocus()
    return NSBitmapImageRep(data: image.tiffRepresentation!)!
}

for size in [16, 32, 128, 256, 512] {
    for retina in [false, true] {
        let pixels = size * (retina ? 2 : 1)
        let rep = drawIcon(size: pixels)
        let name = "icon_\(size)x\(size)\(retina ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
