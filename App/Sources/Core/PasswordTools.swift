import SwiftUI
import Security

enum PasswordTools {
    struct Options: Equatable {
        var length = 20
        var upper = true
        var lower = true
        var digits = true
        var symbols = true
    }

    private static let upperSet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    private static let lowerSet = Array("abcdefghijkmnopqrstuvwxyz")
    private static let digitSet = Array("23456789")
    private static let symbolSet = Array("!@#$%^&*-_=+?.")

    private static func randomIndex(_ n: Int) -> Int {
        var r: UInt32 = 0
        _ = SecRandomCopyBytes(kSecRandomDefault, 4, &r)
        return Int(r % UInt32(n))
    }

    static func generate(_ o: Options) -> String {
        var pools: [[Character]] = []
        if o.upper { pools.append(upperSet) }
        if o.lower { pools.append(lowerSet) }
        if o.digits { pools.append(digitSet) }
        if o.symbols { pools.append(symbolSet) }
        if pools.isEmpty { pools.append(lowerSet) }
        let all = pools.flatMap { $0 }
        var chars: [Character] = pools.map { $0[randomIndex($0.count)] }
        while chars.count < max(o.length, pools.count) { chars.append(all[randomIndex(all.count)]) }
        // Fisher–Yates shuffle with secure randomness
        for i in stride(from: chars.count - 1, to: 0, by: -1) {
            chars.swapAt(i, randomIndex(i + 1))
        }
        return String(chars)
    }

    /// Recovery key: 24 characters, no look-alike letters, grouped XXXX-XXXX-…
    static func recoveryKey() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var groups: [String] = []
        for _ in 0..<6 {
            groups.append(String((0..<4).map { _ in alphabet[randomIndex(alphabet.count)] }))
        }
        return groups.joined(separator: "-")
    }

    static func normalizeRecovery(_ s: String) -> String {
        s.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    struct Strength {
        var score: Int        // 0...4
        var label: String
        var color: Color
        var bits: Double
    }

    private static let common: Set<String> = ["password", "123456", "12345678", "qwerty", "abc123", "111111",
                                              "123123", "password1", "iloveyou", "admin", "welcome", "000000",
                                              "1234567890", "qwerty123", "123456789"]

    static func strength(_ p: String) -> Strength {
        if p.isEmpty { return Strength(score: 0, label: tr("فاضية", "Empty"), color: Theme.faint, bits: 0) }
        var pool = 0
        if p.contains(where: { $0.isLowercase }) { pool += 26 }
        if p.contains(where: { $0.isUppercase }) { pool += 26 }
        if p.contains(where: { $0.isNumber }) { pool += 10 }
        if p.contains(where: { !$0.isLetter && !$0.isNumber }) { pool += 32 }
        if p.unicodeScalars.contains(where: { $0.value > 0x7F }) { pool += 40 }
        var bits = Double(p.count) * log2(Double(max(pool, 1)))
        let uniq = Set(p).count
        if uniq <= 2 { bits *= 0.3 } else if Double(uniq) < Double(p.count) * 0.5 { bits *= 0.7 }
        if common.contains(p.lowercased()) { bits = min(bits, 10) }
        if hasSequence(p) { bits *= 0.8 }
        let score: Int
        switch bits {
        case ..<28: score = 0
        case ..<45: score = 1
        case ..<60: score = 2
        case ..<80: score = 3
        default: score = 4
        }
        let labels = [tr("ضعيفة جداً", "Very weak"), tr("ضعيفة", "Weak"), tr("متوسطة", "Fair"),
                      tr("قوية", "Strong"), tr("قوية جداً", "Very strong")]
        let colors = [Theme.danger, Color(hex: 0xFF7A45), Theme.warn, Theme.ok, Theme.accent]
        return Strength(score: score, label: labels[score], color: colors[score], bits: bits)
    }

    private static func hasSequence(_ p: String) -> Bool {
        let s = Array(p.lowercased().unicodeScalars.map { Int($0.value) })
        guard s.count >= 4 else { return false }
        for i in 0..<(s.count - 3) {
            let a = s[i], b = s[i + 1], c = s[i + 2], d = s[i + 3]
            if (b - a == 1 && c - b == 1 && d - c == 1) || (a - b == 1 && b - c == 1 && c - d == 1) { return true }
        }
        return false
    }
}
