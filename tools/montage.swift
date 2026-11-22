import AppKit
// montage out.png cols cellW file...
let a = CommandLine.arguments
let out = a[1], cols = Int(a[2])!, cellW = CGFloat(Double(a[3])!)
let files = Array(a.dropFirst(4))
let imgs = files.map { NSImage(contentsOfFile: $0)! }
let ratio = imgs[0].size.height / imgs[0].size.width
let cellH = cellW * ratio + 30
let rows = (imgs.count + cols - 1) / cols
let W = Int(cellW) * cols, H = Int(cellH) * rows
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.gray.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
for (i, img) in imgs.enumerated() {
    let c = i % cols, r = i / cols
    let x = CGFloat(c) * cellW, y = CGFloat(H) - CGFloat(r + 1) * cellH
    img.draw(in: NSRect(x: x + 4, y: y + 4, width: cellW - 8, height: (cellW - 8) * ratio))
    let name = (files[i] as NSString).lastPathComponent
    (name as NSString).draw(at: NSPoint(x: x + 6, y: y + cellH - 24), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 16), .foregroundColor: NSColor.white])
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
