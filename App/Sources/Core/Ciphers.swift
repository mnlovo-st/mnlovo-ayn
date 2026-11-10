import Foundation
import CryptoKit

/// A small toolbox of reversible text transforms. Some are just for fun/obfuscation (Base64, Morse,
/// the MNLOVO glyphs); the passphrase one is real AES-GCM. All of them can be undone by the decode tool,
/// and `Cipher.decodeAuto` guesses which was used so a pasted blob "just works".
enum Cipher: String, CaseIterable, Identifiable {
    case mnlovo          // custom symbol substitution — the house cipher
    case base64
    case hex
    case binary
    case caesar          // ROT-N over letters (key = shift)
    case atbash          // mirror the alphabet
    case rot47           // shift all visible ASCII
    case reversed        // simply backwards
    case morse
    case emoji           // maps bytes to a fixed emoji alphabet
    case aes             // real encryption with a passphrase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mnlovo: return tr("رموز MNLOVO", "MNLOVO glyphs")
        case .base64: return "Base64"
        case .hex: return tr("ست عشري (Hex)", "Hex")
        case .binary: return tr("ثنائي (0/1)", "Binary")
        case .caesar: return tr("قيصر (إزاحة)", "Caesar shift")
        case .atbash: return tr("أتباش (مرآة)", "Atbash")
        case .rot47: return "ROT47"
        case .reversed: return tr("معكوس", "Reversed")
        case .morse: return tr("مورس", "Morse")
        case .emoji: return tr("إيموجي", "Emoji")
        case .aes: return tr("تشفير بكلمة مرور (AES)", "Password (AES)")
        }
    }

    var icon: String {
        switch self {
        case .mnlovo: return "eye.fill"
        case .base64: return "textformat.abc"
        case .hex: return "number"
        case .binary: return "circle.grid.2x1.fill"
        case .caesar: return "arrow.left.arrow.right"
        case .atbash: return "arrow.left.and.right.righttriangle.left.righttriangle.right.fill"
        case .rot47: return "arrow.triangle.2.circlepath"
        case .reversed: return "arrow.uturn.left"
        case .morse: return "dot.radiowaves.left.and.right"
        case .emoji: return "face.smiling.inverse"
        case .aes: return "lock.shield.fill"
        }
    }

    var blurb: String {
        switch self {
        case .mnlovo: return tr("رموزنا الخاصة — ما يفكها إلا هالتطبيق.", "Our own symbols — only this app reads them.")
        case .base64: return tr("ترميز شائع، سهل وسريع.", "Common, quick encoding.")
        case .hex: return tr("كل حرف يصير رقمين.", "Each byte as two digits.")
        case .binary: return tr("أصفار وواحدات.", "Zeros and ones.")
        case .caesar: return tr("يزيح الحروف برقم تختاره.", "Shifts letters by a number you pick.")
        case .atbash: return tr("يقلب الأبجدية: A↔Z.", "Flips the alphabet: A↔Z.")
        case .rot47: return tr("يزيح كل الرموز المرئية.", "Shifts every visible symbol.")
        case .reversed: return tr("يكتبه من الآخر للأول.", "Writes it back to front.")
        case .morse: return tr("نقاط وشرطات.", "Dots and dashes.")
        case .emoji: return tr("يحوّله لسلسلة إيموجي.", "Turns it into a string of emoji.")
        case .aes: return tr("تشفير حقيقي — يحتاج نفس كلمة المرور لفكه.", "Real encryption — needs the same password to open.")
        }
    }

    /// Needs a key/passphrase field in the UI.
    var needsKey: Bool { self == .caesar || self == .aes }
    var keyIsNumber: Bool { self == .caesar }

    // MARK: Encode

    func encode(_ text: String, key: String = "") -> String {
        switch self {
        case .reversed: return String(text.reversed())
        case .base64: return Data(text.utf8).base64EncodedString()
        case .hex: return Data(text.utf8).map { String(format: "%02x", $0) }.joined()
        case .binary: return Data(text.utf8).map { String(($0 as UInt8), radix: 2).leftPad(8) }.joined(separator: " ")
        case .caesar: return caesarShift(text, by: Int(key) ?? 3)
        case .atbash: return atbash(text)
        case .rot47: return rot47(text)
        case .morse: return Morse.encode(text)
        case .emoji: return Emoji.encode(Data(text.utf8))
        case .mnlovo: return Glyphs.encode(Data(text.utf8))
        case .aes: return (try? AESText.encrypt(text, pass: key)) ?? ""
        }
    }

    // MARK: Decode

    func decode(_ text: String, key: String = "") -> String? {
        switch self {
        case .reversed: return String(text.reversed())
        case .base64:
            guard let d = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return String(data: d, encoding: .utf8)
        case .hex: return Data(hex: text).flatMap { String(data: $0, encoding: .utf8) }
        case .binary:
            let bytes = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { UInt8($0, radix: 2) }
            return bytes.isEmpty ? nil : String(data: Data(bytes), encoding: .utf8)
        case .caesar: return caesarShift(text, by: -(Int(key) ?? 3))
        case .atbash: return atbash(text)
        case .rot47: return rot47(text, decode: true)
        case .morse: return Morse.decode(text)
        case .emoji: return Emoji.decode(text).flatMap { String(data: $0, encoding: .utf8) }
        case .mnlovo: return Glyphs.decode(text).flatMap { String(data: $0, encoding: .utf8) }
        case .aes: return try? AESText.decrypt(text, pass: key)
        }
    }

    /// Best-guess decode of a pasted blob. Returns the cipher it recognised and the plaintext.
    /// AES and Caesar need a key, so they're only tried when `key` is supplied.
    static func decodeAuto(_ raw: String, key: String = "") -> (Cipher, String)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Signature-based first (unambiguous), then reversible fallbacks.
        if text.hasPrefix(AESText.prefix), !key.isEmpty, let p = try? AESText.decrypt(text, pass: key) { return (.aes, p) }
        if Glyphs.looksLike(text), let d = Glyphs.decode(text), let s = String(data: d, encoding: .utf8) { return (.mnlovo, s) }
        if Emoji.looksLike(text), let d = Emoji.decode(text), let s = String(data: d, encoding: .utf8) { return (.emoji, s) }
        if Morse.looksLike(text), let s = Morse.decode(text) { return (.morse, s) }
        if text.allSatisfy({ $0 == "0" || $0 == "1" || $0 == " " || $0 == "\n" }), text.contains("0") || text.contains("1"),
           let bin = Cipher.binary.decode(text), printable(bin) { return (.binary, bin) }
        if text.count % 2 == 0, text.allSatisfy({ $0.isHexDigit }), let h = Cipher.hex.decode(text), printable(h) { return (.hex, h) }
        if isBase64(text), let b = Cipher.base64.decode(text), printable(b) { return (.base64, b) }
        if !key.isEmpty, let shift = Int(key), let c = Cipher.caesar.decode(text, key: "\(shift)") { return (.caesar, c) }
        // Atbash / rot47 / reversed are their own inverse and always "work"; only offer if they look meaningful.
        return nil
    }

    private static func printable(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { $0 == "\n" || $0 == "\t" || $0.value >= 32 }
    }
    private static func isBase64(_ s: String) -> Bool {
        s.count >= 4 && s.count % 4 == 0 && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }
    }

    // MARK: Letter transforms

    private func caesarShift(_ text: String, by n: Int) -> String {
        let shift = ((n % 26) + 26) % 26
        return String(text.unicodeScalars.map { u -> Character in
            if u.value >= 65 && u.value <= 90 { return Character(UnicodeScalar((u.value - 65 + UInt32(shift)) % 26 + 65)!) }
            if u.value >= 97 && u.value <= 122 { return Character(UnicodeScalar((u.value - 97 + UInt32(shift)) % 26 + 97)!) }
            return Character(u)
        })
    }
    private func atbash(_ text: String) -> String {
        String(text.unicodeScalars.map { u -> Character in
            if u.value >= 65 && u.value <= 90 { return Character(UnicodeScalar(90 - (u.value - 65))!) }
            if u.value >= 97 && u.value <= 122 { return Character(UnicodeScalar(122 - (u.value - 97))!) }
            return Character(u)
        })
    }
    private func rot47(_ text: String, decode: Bool = false) -> String {
        String(text.unicodeScalars.map { u -> Character in
            if u.value >= 33 && u.value <= 126 { return Character(UnicodeScalar(33 + (u.value - 33 + 47) % 94)!) }
            return Character(u)
        })
    }
}

// MARK: - Morse

private enum Morse {
    static let map: [Character: String] = [
        "a": ".-", "b": "-...", "c": "-.-.", "d": "-..", "e": ".", "f": "..-.", "g": "--.", "h": "....",
        "i": "..", "j": ".---", "k": "-.-", "l": ".-..", "m": "--", "n": "-.", "o": "---", "p": ".--.",
        "q": "--.-", "r": ".-.", "s": "...", "t": "-", "u": "..-", "v": "...-", "w": ".--", "x": "-..-",
        "y": "-.--", "z": "--..", "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.", ".": ".-.-.-", ",": "--..--",
        "?": "..--..", "'": ".----.", "!": "-.-.--", "/": "-..-.", "@": ".--.-.", "-": "-....-", ":": "---..."]
    static let rev: [String: Character] = Dictionary(uniqueKeysWithValues: map.map { ($1, $0) })

    static func encode(_ s: String) -> String {
        s.lowercased().split(separator: " ", omittingEmptySubsequences: false).map { word in
            word.compactMap { map[$0] }.joined(separator: " ")
        }.joined(separator: " / ")
    }
    static func decode(_ s: String) -> String? {
        let words = s.replacingOccurrences(of: "\n", with: " ").components(separatedBy: "/")
        let out = words.map { word in
            word.split(separator: " ").compactMap { rev[String($0)] }.map(String.init).joined()
        }.joined(separator: " ")
        return out.isEmpty ? nil : out
    }
    static func looksLike(_ s: String) -> Bool {
        let set = Set(".-/ \n")
        return s.contains(".") || s.contains("-") ? s.allSatisfy { set.contains($0) } : false
    }
}

// MARK: - Emoji alphabet (base-32 over a fixed emoji set)

private enum Emoji {
    static let glyphs = Array("😀😁😂🤣😊😍😎😭😡🤔🙈🦊🐱🐶🦅🌙⭐️🔥💧🌈🍎🍊🍋🍇🍓🎈🎁🔑🔒🛡️⚡️✨")
    static let index: [Character: Int] = Dictionary(uniqueKeysWithValues: glyphs.enumerated().map { ($1, $0) })

    // 5 bits per emoji.
    static func encode(_ data: Data) -> String {
        var bits = ""
        for b in data { bits += String(b, radix: 2).leftPad(8) }
        while bits.count % 5 != 0 { bits += "0" }
        var out = ""
        var i = bits.startIndex
        while i < bits.endIndex {
            let j = bits.index(i, offsetBy: 5)
            if let n = Int(bits[i..<j], radix: 2) { out.append(glyphs[n]) }
            i = j
        }
        return out
    }
    static func decode(_ s: String) -> Data? {
        var bits = ""
        for ch in s where index[ch] != nil { bits += String(index[ch]!, radix: 2).leftPad(5) }
        var bytes = [UInt8]()
        var i = bits.startIndex
        while let j = bits.index(i, offsetBy: 8, limitedBy: bits.endIndex), j <= bits.endIndex {
            if let n = UInt8(bits[i..<j], radix: 2) { bytes.append(n) }
            i = j
        }
        return bytes.isEmpty ? nil : Data(bytes)
    }
    static func looksLike(_ s: String) -> Bool {
        let t = s.filter { !$0.isWhitespace }
        return !t.isEmpty && t.allSatisfy { index[$0] != nil }
    }
}

// MARK: - MNLOVO glyphs (the house cipher: base-16 over private symbols)

private enum Glyphs {
    static let glyphs = Array("◈◇◆◉○●◐◑◒◓▲△▼▽◢◣")
    static let index: [Character: Int] = Dictionary(uniqueKeysWithValues: glyphs.enumerated().map { ($1, $0) })

    static func encode(_ data: Data) -> String {
        data.map { "\(glyphs[Int($0 >> 4)])\(glyphs[Int($0 & 0xF)])" }.joined()
    }
    static func decode(_ s: String) -> Data? {
        let chars = s.filter { index[$0] != nil }
        guard chars.count % 2 == 0, !chars.isEmpty else { return nil }
        var bytes = [UInt8]()
        var it = chars.makeIterator()
        while let hi = it.next(), let lo = it.next(), let h = index[hi], let l = index[lo] {
            bytes.append(UInt8(h << 4 | l))
        }
        return Data(bytes)
    }
    static func looksLike(_ s: String) -> Bool {
        let t = s.filter { !$0.isWhitespace }
        return !t.isEmpty && t.allSatisfy { index[$0] != nil }
    }
}

// MARK: - AES text (real, passphrase-based)

enum AESText {
    static let prefix = "MNLV1:"
    enum Err: Error { case badKey, badData }

    private static func key(_ pass: String) -> SymmetricKey {
        let salt = Data("mnlovo.saver.cipher".utf8)
        let h = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(pass.utf8)),
                                       salt: salt, info: Data("aes-text".utf8), outputByteCount: 32)
        return h
    }
    static func encrypt(_ text: String, pass: String) throws -> String {
        guard !pass.isEmpty else { throw Err.badKey }
        let box = try AES.GCM.seal(Data(text.utf8), using: key(pass))
        guard let combined = box.combined else { throw Err.badData }
        return prefix + combined.base64EncodedString()
    }
    static func decrypt(_ blob: String, pass: String) throws -> String {
        guard !pass.isEmpty else { throw Err.badKey }
        var s = blob.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        guard let data = Data(base64Encoded: s) else { throw Err.badData }
        let box = try AES.GCM.SealedBox(combined: data)
        let out = try AES.GCM.open(box, using: key(pass))
        guard let text = String(data: out, encoding: .utf8) else { throw Err.badData }
        return text
    }
}

private extension String {
    func leftPad(_ n: Int) -> String { count >= n ? self : String(repeating: "0", count: n - count) + self }
}
private extension Data {
    init?(hex: String) {
        let clean = hex.filter { $0.isHexDigit }
        guard clean.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var i = clean.startIndex
        while i < clean.endIndex {
            let j = clean.index(i, offsetBy: 2)
            guard let b = UInt8(clean[i..<j], radix: 16) else { return nil }
            bytes.append(b); i = j
        }
        self = Data(bytes)
    }
}
