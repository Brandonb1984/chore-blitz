import Foundation
import zlib

/// ZRLE decoder (RFC 6143 §7.7.6). One zlib stream lives for the whole connection.
/// Assumes our pixel format: 32bpp, depth 24, little-endian, so CPIXEL is 3 bytes (B, G, R).
final class ZRLEDecoder {
    private var stream = z_stream()
    private var ready = false
    private var out = [UInt8](repeating: 0, count: 1 << 20)

    init() {
        let r = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        ready = (r == Z_OK)
    }

    deinit { if ready { inflateEnd(&stream) } }

    private func inflate(_ input: [UInt8]) throws -> Int {
        guard ready else { throw RFBError.protocolError("zlib unavailable") }
        var produced = 0
        var input = input
        try input.withUnsafeMutableBufferPointer { inBuf in
            stream.next_in = inBuf.baseAddress
            stream.avail_in = uInt(inBuf.count)
            repeat {
                if out.count - produced < 65536 { out += [UInt8](repeating: 0, count: out.count) }
                let space = out.count - produced
                let r: Int32 = out.withUnsafeMutableBufferPointer { ob in
                    stream.next_out = ob.baseAddress! + produced
                    stream.avail_out = uInt(space)
                    return zlib.inflate(&stream, Z_SYNC_FLUSH)
                }
                produced += space - Int(stream.avail_out)
                if r != Z_OK && r != Z_BUF_ERROR && r != Z_STREAM_END {
                    throw RFBError.protocolError("zlib error \(r)")
                }
                if r == Z_BUF_ERROR && stream.avail_in == 0 { break }
            } while stream.avail_in > 0 || stream.avail_out == 0
        }
        return produced
    }

    func decode(compressed: [UInt8], x rx: Int, y ry: Int, w rw: Int, h rh: Int, into fb: Framebuffer) throws {
        let n = try inflate(compressed)
        try out.withUnsafeBufferPointer { buf in
            let d = buf.baseAddress!
            var i = 0
            @inline(__always) func need(_ k: Int) throws {
                if i + k > n { throw RFBError.protocolError("ZRLE data ran short") }
            }
            @inline(__always) func cpixel() -> UInt32 {
                let v = UInt32(d[i]) | UInt32(d[i + 1]) << 8 | UInt32(d[i + 2]) << 16
                i += 3
                return v | 0xff000000
            }
            let fbw = fb.width
            let px = fb.pixels
            var palette = [UInt32](repeating: 0, count: 128)

            var ty = ry
            while ty < ry + rh {
                let th = min(64, ry + rh - ty)
                var tx = rx
                while tx < rx + rw {
                    let tw = min(64, rx + rw - tx)
                    try need(1)
                    let sub = Int(d[i]); i += 1
                    switch sub {
                    case 0:
                        try need(tw * th * 3)
                        for yy in 0..<th {
                            let row = px + (ty + yy) * fbw + tx
                            for xx in 0..<tw { row[xx] = cpixel() }
                        }
                    case 1:
                        try need(3)
                        fb.fill(x: tx, y: ty, w: tw, h: th, color: cpixel())
                    case 2...16:
                        try need(sub * 3)
                        for k in 0..<sub { palette[k] = cpixel() }
                        let bits = sub == 2 ? 1 : (sub <= 4 ? 2 : 4)
                        let mask = (1 << bits) - 1
                        let rowBytes = (tw * bits + 7) / 8
                        try need(rowBytes * th)
                        for yy in 0..<th {
                            let row = px + (ty + yy) * fbw + tx
                            var byte = 0, left = 0
                            for xx in 0..<tw {
                                if left == 0 { byte = Int(d[i]); i += 1; left = 8 }
                                left -= bits
                                row[xx] = palette[(byte >> left) & mask]
                            }
                        }
                    case 128, 130...255:
                        let usePalette = sub != 128
                        if usePalette {
                            let size = sub - 128
                            try need(size * 3)
                            for k in 0..<size { palette[k] = cpixel() }
                        }
                        var pos = 0
                        let total = tw * th
                        while pos < total {
                            var color: UInt32
                            var run = 1
                            if usePalette {
                                try need(1)
                                let idx = Int(d[i]); i += 1
                                color = palette[idx & 127]
                                if idx & 128 != 0 {
                                    run = 1
                                    while true { try need(1); let b = Int(d[i]); i += 1; run += b; if b != 255 { break } }
                                }
                            } else {
                                try need(3)
                                color = cpixel()
                                run = 1
                                while true { try need(1); let b = Int(d[i]); i += 1; run += b; if b != 255 { break } }
                            }
                            run = min(run, total - pos)
                            while run > 0 {
                                let yy = pos / tw, xx = pos % tw
                                let span = min(run, tw - xx)
                                (px + (ty + yy) * fbw + tx + xx).update(repeating: color, count: span)
                                pos += span; run -= span
                            }
                        }
                    default:
                        throw RFBError.protocolError("Bad ZRLE subencoding \(sub)")
                    }
                    tx += 64
                }
                ty += 64
            }
        }
    }
}
