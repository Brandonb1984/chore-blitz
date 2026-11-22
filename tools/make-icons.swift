// Generates the Chore Blitz app icons: a yellow bolt on navy.
// Usage: swift tools/make-icons.swift <repo root>
// Writes the iPhone AppIcon and the tvOS "App Icon & Top Shelf Image" brand assets.
import AppKit

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let navyTop = color(0x1E2B5C), navyBottom = color(0x0C111E)
let yellow = color(0xFFC83D), yellowLight = color(0xFFE14D), shadow = color(0x8A5A00)

/// The bolt in a unit square (y down).
let boltPoints: [CGPoint] = [
    CGPoint(x: 0.60, y: 0.04), CGPoint(x: 0.24, y: 0.56), CGPoint(x: 0.47, y: 0.56),
    CGPoint(x: 0.38, y: 0.96), CGPoint(x: 0.77, y: 0.41), CGPoint(x: 0.54, y: 0.41), CGPoint(x: 0.67, y: 0.04),
]

func render(_ w: Int, _ h: Int, _ draw: (CGContext, CGFloat, CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    // Flip to y-down so the bolt points read naturally.
    cg.translateBy(x: 0, y: CGFloat(h)); cg.scaleBy(x: 1, y: -1)
    draw(cg, CGFloat(w), CGFloat(h))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func background(_ cg: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [navyTop.cgColor, navyBottom.cgColor] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h), options: [])
    // Soft glow behind where the bolt sits.
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(0x3B5BDB, 0.45).cgColor, color(0x3B5BDB, 0).cgColor] as CFArray,
                          locations: [0, 1])!
    let c = CGPoint(x: w / 2, y: h / 2)
    cg.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: min(w, h) * 0.55, options: [])
}

/// Bolt filling a `side` square centred at `center`, with a hard drop shadow.
func bolt(_ cg: CGContext, center: CGPoint, side: CGFloat) {
    func path(offset: CGPoint) -> CGPath {
        let p = CGMutablePath()
        for (i, pt) in boltPoints.enumerated() {
            let q = CGPoint(x: center.x - side / 2 + pt.x * side + offset.x, y: center.y - side / 2 + pt.y * side + offset.y)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }
    cg.addPath(path(offset: CGPoint(x: side * 0.035, y: side * 0.045)))
    cg.setFillColor(shadow.withAlphaComponent(0.85).cgColor); cg.fillPath()
    cg.addPath(path(offset: .zero))
    cg.saveGState(); cg.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [yellowLight.cgColor, yellow.cgColor] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(g, start: CGPoint(x: center.x, y: center.y - side / 2), end: CGPoint(x: center.x, y: center.y + side / 2), options: [])
    cg.restoreGState()
}

func write(_ data: Data, _ path: String) {
    try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try! data.write(to: URL(fileURLWithPath: path))
}
func json(_ s: String, _ path: String) { write(s.data(using: .utf8)!, path) }

// iPhone: 1024 single-size icon (no transparency).
write(render(1024, 1024) { cg, w, h in background(cg, w, h); bolt(cg, center: CGPoint(x: w / 2, y: h / 2), side: w * 0.72) },
      "\(root)/iOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

// tvOS brand assets.
let tv = "\(root)/tvOS/Assets.xcassets"
json(#"{ "info" : { "author" : "xcode", "version" : 1 } }"#, "\(tv)/Contents.json")
let brand = "\(tv)/App Icon & Top Shelf Image.brandassets"
json("""
{
  "assets" : [
    { "filename" : "App Icon - App Store.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" },
    { "filename" : "App Icon.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" },
    { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" },
    { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
""", "\(brand)/Contents.json")

/// A two-layer image stack (navy back, bolt front) for the TV's parallax icon.
func imageStack(_ name: String, sizes: [(scale: String, w: Int, h: Int)]) {
    let dir = "\(brand)/\(name).imagestack"
    json("""
    { "info" : { "author" : "xcode", "version" : 1 },
      "layers" : [ { "filename" : "Front.imagestacklayer" }, { "filename" : "Back.imagestacklayer" } ] }
    """, "\(dir)/Contents.json")
    for layer in ["Front", "Back"] {
        let ldir = "\(dir)/\(layer).imagestacklayer"
        json(#"{ "info" : { "author" : "xcode", "version" : 1 } }"#, "\(ldir)/Contents.json")
        var images: [String] = []
        for s in sizes {
            let file = "\(layer.lowercased())-\(s.w)x\(s.h).png"
            let data = render(s.w, s.h) { cg, w, h in
                if layer == "Back" { background(cg, w, h) }
                else { bolt(cg, center: CGPoint(x: w / 2, y: h / 2), side: h * 0.78) }
            }
            write(data, "\(ldir)/Content.imageset/\(file)")
            images.append(#"{ "filename" : "\#(file)", "idiom" : "tv", "scale" : "\#(s.scale)" }"#)
        }
        json(#"{ "images" : [ \#(images.joined(separator: ", ")) ], "info" : { "author" : "xcode", "version" : 1 } }"#,
             "\(ldir)/Content.imageset/Contents.json")
    }
}
imageStack("App Icon", sizes: [("1x", 400, 240), ("2x", 800, 480)])
imageStack("App Icon - App Store", sizes: [("1x", 1280, 768)])

/// Top Shelf: navy banner with the bolt and the name.
func topShelf(_ name: String, sizes: [(scale: String, w: Int, h: Int)]) {
    let dir = "\(brand)/\(name).imageset"
    var images: [String] = []
    for s in sizes {
        let file = "topshelf-\(s.w)x\(s.h).png"
        let data = render(s.w, s.h) { cg, w, h in
            background(cg, w, h)
            let side = h * 0.5
            let titleFont = NSFont.systemFont(ofSize: h * 0.2, weight: .heavy)
            let title = NSAttributedString(string: "Chore Blitz", attributes: [.font: titleFont, .foregroundColor: NSColor.white])
            let tw = title.size().width
            let total = side * 0.8 + tw
            let x0 = (w - total) / 2
            bolt(cg, center: CGPoint(x: x0 + side * 0.35, y: h / 2), side: side)
            // Text draws in AppKit's y-up space; flip back locally.
            cg.saveGState(); cg.translateBy(x: 0, y: h); cg.scaleBy(x: 1, y: -1)
            title.draw(at: CGPoint(x: x0 + side * 0.8, y: (h - title.size().height) / 2))
            cg.restoreGState()
        }
        write(data, "\(dir)/\(file)")
        images.append(#"{ "filename" : "\#(file)", "idiom" : "tv", "scale" : "\#(s.scale)" }"#)
    }
    json(#"{ "images" : [ \#(images.joined(separator: ", ")) ], "info" : { "author" : "xcode", "version" : 1 } }"#, "\(dir)/Contents.json")
}
topShelf("Top Shelf Image", sizes: [("1x", 1920, 720), ("2x", 3840, 1440)])
topShelf("Top Shelf Image Wide", sizes: [("1x", 2320, 720), ("2x", 4640, 1440)])
print("icons written")
