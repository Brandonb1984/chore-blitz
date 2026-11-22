import Foundation
import CommonCrypto
import CryptoKit
import Security

enum RFBAuth {
    /// Apple Remote Desktop auth (security type 30): Diffie-Hellman, then the
    /// macOS username and password encrypted with AES-128-ECB keyed by MD5(shared secret).
    /// Returns (ciphertext 128 bytes, our public key keyLength bytes).
    static func ard(generator: [UInt8], prime: [UInt8], peerKey: [UInt8],
                    username: String, password: String) throws -> (cipher: [UInt8], publicKey: [UInt8]) {
        let keyLength = prime.count
        let p = BigUInt(bytes: prime)
        let g = BigUInt(bytes: generator)
        let peer = BigUInt(bytes: peerKey)

        // 256-bit private exponent is plenty for 1024-bit DH and keeps this fast.
        var privBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, privBytes.count, &privBytes)
        privBytes[0] |= 0x80
        let priv = BigUInt(bytes: privBytes)

        let pub = BigUInt.powMod(g, priv, p).bytes(length: keyLength)
        let secret = BigUInt.powMod(peer, priv, p).bytes(length: keyLength)
        let key = Array(Insecure.MD5.hash(data: Data(secret)))

        var creds = [UInt8](repeating: 0, count: 128)
        _ = SecRandomCopyBytes(kSecRandomDefault, creds.count, &creds)
        func put(_ s: String, at offset: Int) {
            let b = Array(s.utf8.prefix(63))
            for (i, c) in b.enumerated() { creds[offset + i] = c }
            creds[offset + b.count] = 0
        }
        put(username, at: 0)
        put(password, at: 64)

        let cipher = try crypt(algorithm: CCAlgorithm(kCCAlgorithmAES), key: key, input: creds)
        return (cipher, pub)
    }

    /// Classic VNC password auth (security type 2): DES-ECB of the 16-byte challenge,
    /// key = password (max 8 chars) with each byte's bits reversed.
    static func vnc(challenge: [UInt8], password: String) throws -> [UInt8] {
        var key = [UInt8](repeating: 0, count: 8)
        for (i, c) in Array(password.utf8.prefix(8)).enumerated() {
            var r: UInt8 = 0
            for bit in 0..<8 where c & (1 << bit) != 0 { r |= 1 << (7 - bit) }
            key[i] = r
        }
        return try crypt(algorithm: CCAlgorithm(kCCAlgorithmDES), key: key, input: challenge)
    }

    private static func crypt(algorithm: CCAlgorithm, key: [UInt8], input: [UInt8]) throws -> [UInt8] {
        var out = [UInt8](repeating: 0, count: input.count + 32)
        var moved = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), algorithm, CCOptions(kCCOptionECBMode),
                             key, key.count, nil,
                             input, input.count,
                             &out, out.count, &moved)
        guard status == kCCSuccess else { throw RFBError.protocolError("Encryption failed (\(status))") }
        return Array(out.prefix(moved))
    }
}
