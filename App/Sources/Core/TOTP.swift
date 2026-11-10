import Foundation
import CryptoKit
import UIKit
import CoreImage.CIFilterBuiltins

enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encode(_ data: Data) -> String {
        var out = ""
        var buffer: UInt64 = 0
        var bits = 0
        for b in data {
            buffer = (buffer << 8) | UInt64(b)
            bits += 8
            while bits >= 5 {
                out.append(alphabet[Int((buffer >> UInt64(bits - 5)) & 31)])
                bits -= 5
            }
        }
        if bits > 0 { out.append(alphabet[Int((buffer << UInt64(5 - bits)) & 31)]) }
        return out
    }

    static func decode(_ string: String) -> Data? {
        let clean = string.uppercased().filter { !" -=\n\t".contains($0) }
        var lookup: [Character: UInt64] = [:]
        for (i, c) in alphabet.enumerated() { lookup[c] = UInt64(i) }
        var buffer: UInt64 = 0
        var bits = 0
        var out = Data()
        for c in clean {
            guard let v = lookup[c] else { return nil }
            buffer = (buffer << 5) | v
            bits += 5
            if bits >= 8 {
                out.append(UInt8((buffer >> UInt64(bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return out.isEmpty ? nil : out
    }
}

/// RFC 6238 time-based one-time passwords — same codes as Microsoft/Google Authenticator & iOS Passwords.
struct TOTP: Codable, Hashable {
    enum Algorithm: String, Codable { case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512" }

    var secret: Data
    var digits: Int = 6
    var period: Int = 30
    var algorithm: Algorithm = .sha1
    var issuer: String = ""
    var account: String = ""

    func code(at date: Date = Date()) -> String {
        let counter = UInt64(floor(date.timeIntervalSince1970 / Double(period)))
        var be = counter.bigEndian
        let msg = withUnsafeBytes(of: &be) { Data($0) }
        let key = SymmetricKey(data: secret)
        let mac: Data
        switch algorithm {
        case .sha1: mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: msg, using: key))
        case .sha256: mac = Data(HMAC<SHA256>.authenticationCode(for: msg, using: key))
        case .sha512: mac = Data(HMAC<SHA512>.authenticationCode(for: msg, using: key))
        }
        let bytes = [UInt8](mac)
        let offset = Int(bytes[bytes.count - 1] & 0x0f)
        let bin = (UInt32(bytes[offset] & 0x7f) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
        var mod: UInt32 = 1
        for _ in 0..<digits { mod *= 10 }
        let s = String(bin % mod)
        return String(repeating: "0", count: max(0, digits - s.count)) + s
    }

    func verify(_ input: String, window: Int = 3, at date: Date = Date()) -> Bool {
        let clean = input.filter { $0.isNumber }
        let latin = Self.westernDigits(clean)
        guard latin.count == digits else { return false }
        for step in -window...window {
            if code(at: date.addingTimeInterval(Double(step * period))) == latin { return true }
        }
        return false
    }

    func secondsRemaining(at date: Date = Date()) -> Int {
        period - Int(date.timeIntervalSince1970) % period
    }

    var secretBase32: String { Base32.encode(secret) }

    /// Short fingerprint of the secret (shown in the label so duplicate entries can be told apart).
    var fingerprint: String { String(secretBase32.prefix(4)) }

    var url: String {
        let label = issuer.isEmpty ? account : "\(issuer):\(account)"
        var c = URLComponents()
        c.scheme = "otpauth"
        c.host = "totp"
        c.path = "/" + label
        c.queryItems = [
            URLQueryItem(name: "secret", value: secretBase32),
            URLQueryItem(name: "issuer", value: issuer),
            URLQueryItem(name: "algorithm", value: algorithm.rawValue),
            URLQueryItem(name: "digits", value: String(digits)),
            URLQueryItem(name: "period", value: String(period))
        ]
        return c.string ?? ""
    }

    static func generate(issuer: String, account: String) -> TOTP {
        TOTP(secret: AYNCrypto.randomBytes(20), issuer: issuer, account: account)
    }

    /// Parses otpauth://totp/... links or a bare Base32 secret.
    static func parse(_ text: String) -> TOTP? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("otpauth://") {
            guard let c = URLComponents(string: trimmed), c.host?.lowercased() == "totp" else { return nil }
            let q = Dictionary((c.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            guard let sec = q["secret"], let data = Base32.decode(sec) else { return nil }
            var label = c.path
            if label.hasPrefix("/") { label.removeFirst() }
            var issuer = q["issuer"] ?? ""
            var account = label
            if let idx = label.firstIndex(of: ":") {
                if issuer.isEmpty { issuer = String(label[..<idx]) }
                account = String(label[label.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            }
            var t = TOTP(secret: data, issuer: issuer, account: account)
            if let d = Int(q["digits"] ?? ""), (6...8).contains(d) { t.digits = d }
            if let p = Int(q["period"] ?? ""), p > 0 { t.period = p }
            if let a = Algorithm(rawValue: (q["algorithm"] ?? "SHA1").uppercased()) { t.algorithm = a }
            return t
        }
        guard let data = Base32.decode(trimmed), data.count >= 10 else { return nil }
        return TOTP(secret: data)
    }

    /// Converts Arabic-Indic digits (٠١٢…) to 0-9 so codes typed with an Arabic keyboard still work.
    static func westernDigits(_ s: String) -> String {
        let map: [Character: Character] = ["٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
                                           "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
                                           "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
                                           "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"]
        return String(s.map { map[$0] ?? $0 })
    }
}

enum QRCode {
    static func image(_ string: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
