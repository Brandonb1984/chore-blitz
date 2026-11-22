import Foundation
import Network
import CoreGraphics

enum RFBError: LocalizedError {
    case protocolError(String)
    case authFailed(String)
    case closed

    var errorDescription: String? {
        switch self {
        case .protocolError(let s): return s
        case .authFailed(let s): return s.isEmpty ? "The Mac rejected the username or password." : s
        case .closed: return "The connection closed."
        }
    }
}

/// Cursor shape sent by the Mac (Cursor pseudo-encoding).
struct RemoteCursor {
    let image: CGImage
    let hotX: Int
    let hotY: Int
}

/// A VNC / RFB 3.8 client tuned for macOS Screen Sharing.
final class RFBClient {
    struct Credentials { var username: String; var password: String }

    // Callbacks are delivered on the main queue.
    var onConnected: ((_ width: Int, _ height: Int, _ name: String) -> Void)?
    var onResize: ((_ width: Int, _ height: Int) -> Void)?
    var onFrame: (() -> Void)?
    var onCursor: ((RemoteCursor) -> Void)?
    var onClipboard: ((String) -> Void)?
    var onDisconnect: ((Error?) -> Void)?

    let framebuffer = Framebuffer(width: 1, height: 1)
    private let queue = DispatchQueue(label: "rfb.net", qos: .userInteractive)
    private var connection: NWConnection?
    private var buffer: [UInt8] = []
    private var readIndex = 0
    private var zrle = ZRLEDecoder()
    private var task: Task<Void, Never>?
    private var closed = false

    // MARK: Connect

    func connect(host: String, port: UInt16 = 5900, credentials: Credentials) {
        connect(endpoint: .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!),
                credentials: credentials)
    }

    func connect(endpoint: NWEndpoint, credentials: Credentials) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 10
        let params = NWParameters(tls: nil, tcp: tcp)
        let conn = NWConnection(to: endpoint, using: params)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.task = Task.detached(priority: .userInitiated) { [weak self] in
                    await self?.run(credentials)
                }
            case .failed(let err):
                self.finish(err)
            case .waiting(let err):
                self.finish(err)
            default: break
            }
        }
        conn.start(queue: queue)
    }

    func disconnect() {
        finish(nil)
    }

    private func finish(_ error: Error?) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            self.closed = true
            self.task?.cancel()
            self.connection?.cancel()
            DispatchQueue.main.async { self.onDisconnect?(error) }
        }
    }

    // MARK: Reading

    private func receiveChunk() async throws -> [UInt8] {
        guard let conn = connection else { throw RFBError.closed }
        return try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, isComplete, error in
                if let error { cont.resume(throwing: error); return }
                if let data, !data.isEmpty { cont.resume(returning: [UInt8](data)); return }
                if isComplete { cont.resume(throwing: RFBError.closed); return }
                cont.resume(returning: [])
            }
        }
    }

    private func read(_ n: Int) async throws -> [UInt8] {
        while buffer.count - readIndex < n {
            if readIndex > 0 && readIndex > buffer.count / 2 {
                buffer.removeFirst(readIndex); readIndex = 0
            }
            buffer += try await receiveChunk()
        }
        let out = Array(buffer[readIndex..<(readIndex + n)])
        readIndex += n
        return out
    }

    private func u8() async throws -> Int { Int(try await read(1)[0]) }
    private func u16() async throws -> Int { let b = try await read(2); return Int(b[0]) << 8 | Int(b[1]) }
    private func u32() async throws -> Int {
        let b = try await read(4)
        return Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
    }
    private func s32() async throws -> Int32 { Int32(bitPattern: UInt32(try await u32())) }
    private func string() async throws -> String {
        let len = try await u32()
        return String(decoding: try await read(min(len, 1 << 20)), as: UTF8.self)
    }

    // MARK: Writing

    private func send(_ bytes: [UInt8]) {
        connection?.send(content: Data(bytes), completion: .contentProcessed { [weak self] err in
            if let err { self?.finish(err) }
        })
    }

    private static func be16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
    private static func be32(_ v: Int) -> [UInt8] {
        [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
    }

    func sendKey(_ keysym: UInt32, down: Bool) {
        queue.async { [weak self] in
            self?.send([4, down ? 1 : 0, 0, 0] + Self.be32(Int(keysym)))
        }
    }

    /// buttons: bit0 left, bit1 middle, bit2 right, bit3/4 wheel up/down, bit5/6 wheel left/right.
    func sendPointer(x: Int, y: Int, buttons: UInt8) {
        let fx = max(0, min(framebuffer.width - 1, x))
        let fy = max(0, min(framebuffer.height - 1, y))
        queue.async { [weak self] in
            self?.send([5, buttons] + Self.be16(fx) + Self.be16(fy))
        }
    }

    func sendClipboard(_ text: String) {
        let bytes = Array(text.utf8)
        queue.async { [weak self] in
            self?.send([6, 0, 0, 0] + Self.be32(bytes.count) + bytes)
        }
    }

    private func requestUpdate(incremental: Bool) {
        let w = framebuffer.width, h = framebuffer.height
        queue.async { [weak self] in
            self?.send([3, incremental ? 1 : 0] + Self.be16(0) + Self.be16(0) + Self.be16(w) + Self.be16(h))
        }
    }

    // MARK: Protocol

    private func run(_ creds: Credentials) async {
        do {
            try await handshake(creds)
            while !Task.isCancelled {
                try await readServerMessage()
            }
        } catch {
            finish(error)
        }
    }

    private func handshake(_ creds: Credentials) async throws {
        let version = String(decoding: try await read(12), as: UTF8.self)
        guard version.hasPrefix("RFB ") else { throw RFBError.protocolError("Not a Screen Sharing server") }
        send(Array("RFB 003.008\n".utf8))

        let count = try await u8()
        if count == 0 { throw RFBError.protocolError(try await string()) }
        let types = try await read(count).map(Int.init)

        let chosen: Int
        if types.contains(30) && !creds.username.isEmpty { chosen = 30 }
        else if types.contains(2) { chosen = 2 }
        else if types.contains(1) { chosen = 1 }
        else if types.contains(30) { chosen = 30 }
        else { throw RFBError.protocolError("No supported sign-in method (Mac offered \(types))") }
        send([UInt8(chosen)])

        switch chosen {
        case 30:
            let gen = try await read(2)
            let keyLen = try await u16()
            let prime = try await read(keyLen)
            let peer = try await read(keyLen)
            let (cipher, pub) = try RFBAuth.ard(generator: gen, prime: prime, peerKey: peer,
                                                username: creds.username, password: creds.password)
            send(cipher + pub)
        case 2:
            let challenge = try await read(16)
            send(try RFBAuth.vnc(challenge: challenge, password: creds.password))
        default: break
        }

        let result = try await u32()
        if result != 0 {
            let reason = (try? await string()) ?? ""
            throw RFBError.authFailed(reason)
        }

        send([1]) // ClientInit: shared session, don't kick others off
        let w = try await u16(), h = try await u16()
        _ = try await read(16) // server pixel format; we set our own below
        let name = try await string()

        framebuffer.resize(width: w, height: h)

        // 32bpp, depth 24, little-endian, true colour, R<<16 G<<8 B
        let pf: [UInt8] = [32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0]
        send([0, 0, 0, 0] + pf)

        let encodings: [Int32] = [16 /* ZRLE */, 1 /* CopyRect */, 0 /* Raw */,
                                  -223 /* DesktopSize */, -239 /* Cursor */]
        var msg: [UInt8] = [2, 0] + Self.be16(encodings.count)
        for e in encodings { msg += Self.be32(Int(UInt32(bitPattern: e))) }
        send(msg)

        await MainActor.run { self.onConnected?(w, h, name) }
        requestUpdate(incremental: false)
    }

    private func readServerMessage() async throws {
        let type = try await u8()
        switch type {
        case 0:
            _ = try await read(1)
            let rects = try await u16()
            var resized = false
            for _ in 0..<rects {
                let x = try await u16(), y = try await u16(), w = try await u16(), h = try await u16()
                let enc = try await s32()
                if try await handleRect(x: x, y: y, w: w, h: h, encoding: enc) { resized = true }
            }
            if resized {
                let fw = framebuffer.width, fh = framebuffer.height
                await MainActor.run { self.onResize?(fw, fh) }
                requestUpdate(incremental: false)
            } else {
                requestUpdate(incremental: true)
            }
            await MainActor.run { self.onFrame?() }
        case 1:
            _ = try await read(3)
            let n = try await u16()
            _ = try await read(n * 6)
        case 2:
            break // bell
        case 3:
            _ = try await read(3)
            let len = try await u32()
            let bytes = try await read(min(len, 1 << 22))
            let text = String(decoding: bytes, as: UTF8.self)
            await MainActor.run { self.onClipboard?(text) }
        default:
            throw RFBError.protocolError("Unexpected message \(type) from the Mac")
        }
    }

    /// Returns true when the framebuffer was resized.
    private func handleRect(x: Int, y: Int, w: Int, h: Int, encoding: Int32) async throws -> Bool {
        let fb = framebuffer
        let inBounds = x + w <= fb.width && y + h <= fb.height
        switch encoding {
        case 0:
            let data = try await read(w * h * 4)
            guard inBounds else { return false }
            fb.lock.lock(); defer { fb.lock.unlock() }
            data.withUnsafeBytes { raw in
                for row in 0..<h {
                    memcpy(fb.pixels + (y + row) * fb.width + x, raw.baseAddress! + row * w * 4, w * 4)
                }
            }
        case 1:
            let sx = try await u16(), sy = try await u16()
            guard inBounds, sx + w <= fb.width, sy + h <= fb.height else { return false }
            fb.lock.lock(); defer { fb.lock.unlock() }
            fb.copyRect(srcX: sx, srcY: sy, x: x, y: y, w: w, h: h)
        case 16:
            let len = try await u32()
            let data = try await read(len)
            guard inBounds else { return false }
            fb.lock.lock(); defer { fb.lock.unlock() }
            try zrle.decode(compressed: data, x: x, y: y, w: w, h: h, into: fb)
        case -223:
            fb.resize(width: w, height: h)
            return true
        case -239:
            let pixels = try await read(w * h * 4)
            let mask = try await read(((w + 7) / 8) * h)
            if let cursor = Self.makeCursor(w: w, h: h, hotX: x, hotY: y, pixels: pixels, mask: mask) {
                await MainActor.run { self.onCursor?(cursor) }
            }
        default:
            throw RFBError.protocolError("The Mac sent an unsupported encoding (\(encoding))")
        }
        return false
    }

    private static func makeCursor(w: Int, h: Int, hotX: Int, hotY: Int, pixels: [UInt8], mask: [UInt8]) -> RemoteCursor? {
        guard w > 0, h > 0 else { return nil }
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let rowMask = (w + 7) / 8
        for yy in 0..<h {
            for xx in 0..<w {
                let s = (yy * w + xx) * 4
                let visible = mask[yy * rowMask + xx / 8] & (0x80 >> UInt8(xx % 8)) != 0
                // our pixel bytes are B, G, R, X
                rgba[s] = visible ? pixels[s + 2] : 0
                rgba[s + 1] = visible ? pixels[s + 1] : 0
                rgba[s + 2] = visible ? pixels[s] : 0
                rgba[s + 3] = visible ? 255 : 0
            }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return RemoteCursor(image: img, hotX: hotX, hotY: hotY)
    }
}
