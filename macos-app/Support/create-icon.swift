import AppKit

guard CommandLine.arguments.count == 3 else {
    fputs("usage: create-icon <source.png> <output.png>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let character = NSImage(contentsOf: sourceURL) else {
    fputs("could not open source image\n", stderr)
    exit(3)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let fullRect = NSRect(origin: .zero, size: size)
NSColor(calibratedRed: 0.95, green: 0.91, blue: 0.78, alpha: 1).setFill()
fullRect.fill()

let outerRect = NSRect(x: 54, y: 54, width: 916, height: 916)
let outer = NSBezierPath(roundedRect: outerRect, xRadius: 205, yRadius: 205)
NSColor(calibratedRed: 0.07, green: 0.24, blue: 0.18, alpha: 1).setFill()
outer.fill()

let innerRect = NSRect(x: 91, y: 91, width: 842, height: 842)
let inner = NSBezierPath(roundedRect: innerRect, xRadius: 172, yRadius: 172)
NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.89, alpha: 1).setFill()
inner.fill()

let sun = NSBezierPath(ovalIn: NSRect(x: 155, y: 610, width: 320, height: 320))
NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.24, alpha: 0.92).setFill()
sun.fill()

let noteRect = NSRect(x: 150, y: 175, width: 335, height: 360)
let note = NSBezierPath(roundedRect: noteRect, xRadius: 42, yRadius: 42)
NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.34, alpha: 1).setFill()
note.fill()

NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.19, alpha: 0.82).setStroke()
for index in 0..<3 {
    let y = 420 - CGFloat(index * 82)
    let line = NSBezierPath()
    line.lineWidth = 15
    line.lineCapStyle = .round
    line.move(to: NSPoint(x: 225, y: y))
    line.line(to: NSPoint(x: 415, y: y))
    line.stroke()
}

character.draw(
    in: NSRect(x: 300, y: 74, width: 670, height: 670),
    from: NSRect(origin: .zero, size: character.size),
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("could not render icon\n", stderr)
    exit(4)
}

try png.write(to: outputURL)
