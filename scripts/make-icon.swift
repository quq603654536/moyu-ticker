import AppKit

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let bounds = NSRect(x: 40, y: 40, width: 944, height: 944)
let base = NSBezierPath(roundedRect: bounds, xRadius: 218, yRadius: 218)
NSGradient(starting: NSColor(calibratedRed: 1, green: 0.18, blue: 0.18, alpha: 1), ending: NSColor(calibratedRed: 0.88, green: 0, blue: 0.06, alpha: 1))!.draw(in: base, angle: -60)
let grid = NSBezierPath()
for y in [330, 490, 650] {
    grid.move(to: NSPoint(x: 208, y: y)); grid.line(to: NSPoint(x: 820, y: y))
}
NSColor.white.withAlphaComponent(0.12).setStroke(); grid.lineWidth = 3; grid.stroke()
let chart = NSBezierPath()
let points: [NSPoint] = [.init(x: 208, y: 320), .init(x: 340, y: 510), .init(x: 448, y: 425), .init(x: 580, y: 655), .init(x: 682, y: 555), .init(x: 814, y: 744)]
chart.move(to: points[0]); for p in points.dropFirst() { chart.line(to: p) }
chart.lineWidth = 40; chart.lineJoinStyle = .round; chart.lineCapStyle = .round
NSColor.white.setStroke(); chart.stroke()
let dot = NSBezierPath(ovalIn: NSRect(x: 782, y: 712, width: 64, height: 64))
NSColor.white.setFill(); dot.fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("icon.png"))
