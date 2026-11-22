import Foundation
import CoreGraphics

/// The Mac's screen as 32-bit BGRX pixels (little-endian 0x00RRGGBB).
/// Written by the network decoder, read by the UI to make CGImages.
final class Framebuffer {
    private(set) var width: Int
    private(set) var height: Int
    private(set) var pixels: UnsafeMutablePointer<UInt32>
    private var context: CGContext?
    let lock = NSLock()

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = .allocate(capacity: max(1, width * height))
        pixels.initialize(repeating: 0xff202020, count: max(1, width * height))
        makeContext()
    }

    deinit { pixels.deallocate() }

    func resize(width w: Int, height h: Int) {
        lock.lock(); defer { lock.unlock() }
        pixels.deallocate()
        width = w; height = h
        pixels = .allocate(capacity: max(1, w * h))
        pixels.initialize(repeating: 0xff202020, count: max(1, w * h))
        makeContext()
    }

    private func makeContext() {
        context = CGContext(data: pixels, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    /// Snapshot for display (copy-on-write under the hood).
    func makeImage() -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        return context?.makeImage()
    }

    @inline(__always) func fill(x: Int, y: Int, w: Int, h: Int, color: UInt32) {
        guard w > 0, h > 0 else { return }
        for row in y..<min(y + h, height) {
            let p = pixels + row * width + x
            p.update(repeating: color, count: min(w, width - x))
        }
    }

    func copyRect(srcX: Int, srcY: Int, x: Int, y: Int, w: Int, h: Int) {
        guard w > 0, h > 0 else { return }
        let rows = Array(0..<h)
        for r in (srcY < y ? rows.reversed() : rows) {
            let src = pixels + (srcY + r) * width + srcX
            let dst = pixels + (y + r) * width + x
            memmove(dst, src, w * 4)
        }
    }
}
