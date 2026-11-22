import Foundation

/// Minimal unsigned big integer, just enough for the Diffie-Hellman step of
/// Apple Remote Desktop authentication (modular exponentiation, ~1024-bit).
/// Little-endian 32-bit limbs.
struct BigUInt: Equatable {
    var limbs: [UInt32]

    init(limbs: [UInt32]) {
        self.limbs = limbs
        trim()
    }

    init(_ v: UInt32) { self.init(limbs: [v]) }

    /// Big-endian bytes, as sent on the wire.
    init(bytes: [UInt8]) {
        var l: [UInt32] = []
        var i = bytes.count
        while i > 0 {
            var v: UInt32 = 0
            let start = max(0, i - 4)
            for j in start..<i { v = (v << 8) | UInt32(bytes[j]) }
            l.append(v)
            i = start
        }
        self.init(limbs: l.isEmpty ? [0] : l)
    }

    /// Big-endian bytes, left-padded with zeros to `length`.
    func bytes(length: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: length)
        var idx = length - 1
        for limb in limbs {
            var v = limb
            for _ in 0..<4 {
                if idx < 0 { break }
                out[idx] = UInt8(v & 0xff)
                v >>= 8
                idx -= 1
            }
        }
        return out
    }

    mutating func trim() {
        while limbs.count > 1 && limbs.last == 0 { limbs.removeLast() }
        if limbs.isEmpty { limbs = [0] }
    }

    var bitWidth: Int {
        guard let top = limbs.last, top != 0 else { return 0 }
        return (limbs.count - 1) * 32 + (32 - top.leadingZeroBitCount)
    }

    func bit(_ i: Int) -> Bool {
        let li = i / 32
        guard li < limbs.count else { return false }
        return (limbs[li] >> UInt32(i % 32)) & 1 == 1
    }

    static func compare(_ a: [UInt32], _ b: [UInt32]) -> Int {
        let n = max(a.count, b.count)
        var i = n - 1
        while i >= 0 {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y ? -1 : 1 }
            i -= 1
        }
        return 0
    }

    /// a = a - b, assuming a >= b. Both sized n.
    static func subInPlace(_ a: inout [UInt32], _ b: [UInt32]) {
        var borrow: Int64 = 0
        for i in 0..<a.count {
            var d = Int64(a[i]) - Int64(i < b.count ? b[i] : 0) - borrow
            if d < 0 { d += 1 << 32; borrow = 1 } else { borrow = 0 }
            a[i] = UInt32(truncatingIfNeeded: d)
        }
    }

    /// (a * b) mod m using shift-and-add. a, b must already be < m.
    static func mulMod(_ a: BigUInt, _ b: BigUInt, _ m: BigUInt) -> BigUInt {
        let n = m.limbs.count + 1
        var r = [UInt32](repeating: 0, count: n)
        var bb = b.limbs; bb += [UInt32](repeating: 0, count: n - bb.count)
        let mm = m.limbs + [UInt32](repeating: 0, count: n - m.limbs.count)
        var i = a.bitWidth - 1
        while i >= 0 {
            // r = 2r mod m
            var carry: UInt32 = 0
            for k in 0..<n {
                let v = r[k]
                r[k] = (v << 1) | carry
                carry = v >> 31
            }
            if compare(r, mm) >= 0 { subInPlace(&r, mm) }
            if a.bit(i) {
                // r = r + b mod m
                var c: UInt64 = 0
                for k in 0..<n {
                    let s = UInt64(r[k]) + UInt64(bb[k]) + c
                    r[k] = UInt32(truncatingIfNeeded: s)
                    c = s >> 32
                }
                if compare(r, mm) >= 0 { subInPlace(&r, mm) }
            }
            i -= 1
        }
        return BigUInt(limbs: r)
    }

    /// Reduce x mod m (slow path, only used once on inputs).
    static func mod(_ x: BigUInt, _ m: BigUInt) -> BigUInt {
        if compare(x.limbs, m.limbs) < 0 { return x }
        return mulMod(x, BigUInt(1), m)
    }

    static func powMod(_ base: BigUInt, _ exp: BigUInt, _ m: BigUInt) -> BigUInt {
        let b = mod(base, m)
        var result = mod(BigUInt(1), m)
        var i = exp.bitWidth - 1
        while i >= 0 {
            result = mulMod(result, result, m)
            if exp.bit(i) { result = mulMod(result, b, m) }
            i -= 1
        }
        return result
    }
}
