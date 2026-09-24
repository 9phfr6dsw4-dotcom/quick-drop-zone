import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dist/AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, size) in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let background = NSBezierPath(roundedRect: bounds.insetBy(dx: size * 0.04, dy: size * 0.04), xRadius: size * 0.22, yRadius: size * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.19, green: 0.42, blue: 0.96, alpha: 1), NSColor(calibratedRed: 0.28, green: 0.22, blue: 0.75, alpha: 1)])?.draw(in: background, angle: -45)
    if let symbol = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil),
       let configured = symbol.withSymbolConfiguration(.init(pointSize: size * 0.48, weight: .semibold)) {
        let symbolSize = min(size * 0.58, configured.size.width)
        configured.draw(in: NSRect(x: (size - symbolSize) / 2, y: (size - symbolSize) / 2, width: symbolSize, height: symbolSize), from: .zero, operation: .sourceOver, fraction: 1)
    }
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not render icon asset")
    }
    try png.write(to: output.appendingPathComponent("\(name).png"))
}
