import SwiftUI

// MARK: - Currency signs
//
// Written-out codes ("75 AED") read like a spreadsheet. A sign reads like money.
// Most currencies have a sign a system font can draw, but the two that matter most here don't:
// the UAE dirham (U+20C3, Unicode 18.0) and the Saudi riyal (U+20C1, Unicode 17.0) are newer than
// the fonts on the phones this app runs on, so a plain Text would show an empty box. Those two are
// drawn from their official outlines instead, which also means they look right on every iOS version.

enum Money {
    /// Every currency the subscription picker offers, with the sign to print.
    /// The Gulf currencies without a single-character sign use their usual Arabic abbreviation.
    static let signs: [String: String] = [
        "AED": "\u{062F}.\u{0625}", "SAR": "\u{0631}.\u{0633}", "KWD": "\u{062F}.\u{0643}", "QAR": "\u{0631}.\u{0642}",
        "BHD": "\u{062F}.\u{0628}", "OMR": "\u{0631}.\u{0639}", "EGP": "\u{062C}.\u{0645}", "JOD": "\u{062F}.\u{0623}",
        "USD": "$", "EUR": "\u{20AC}", "GBP": "\u{00A3}", "TRY": "\u{20BA}",
    ]

    /// The two signs the app draws itself because no installed font has them yet.
    static func isDrawn(_ code: String) -> Bool { code == "AED" || code == "SAR" }

    /// A sign for places that can only hold text — notifications, widget payloads, Telegram messages.
    static func sign(_ code: String) -> String { signs[code] ?? code }

    /// "75" or "75.5" — the amount on its own, so a view can put the sign beside it.
    static func amount(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// Amount and sign as one string, for those same text-only places.
    static func text(_ v: Double, _ code: String) -> String { "\(amount(v)) \(sign(code))" }
}

/// Draws one currency sign at the given size: the real outline for AED and SAR, the font's own
/// character for everything else.
struct CurrencySign: View {
    let code: String
    var size: CGFloat = 15
    var weight: Font.Weight = .bold

    var body: some View {
        if Money.isDrawn(code) {
            let art = code == "AED" ? CurrencyArt.dirham : CurrencyArt.riyal
            SVGPath(d: art.d, box: art.box)
                .frame(width: size * art.widthRatio, height: size * 0.78)
                // Sits a touch low so it lines up with the digits beside it rather than the cap height.
                .offset(y: size * 0.06)
                .accessibilityLabel(code)
        } else {
            Text(Money.sign(code))
                .font(Theme.font(size, weight))
                .accessibilityLabel(code)
        }
    }
}

/// An amount with its sign: "75 \u{062F}.\u{0625}", but with the sign drawn. Always laid out left-to-right so the
/// digits and the sign keep their order whichever language the app is in.
struct MoneyText: View {
    let value: Double
    let code: String
    var size: CGFloat = 16
    var weight: Font.Weight = .bold

    var body: some View {
        HStack(spacing: size * 0.22) {
            Text(Money.amount(value))
                .font(Theme.mono(size, weight))
                .monospacedDigit()
            CurrencySign(code: code, size: size, weight: weight)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Money.amount(value)) \(code)")
    }
}

/// The official outlines, taken from the published glyphs.
enum CurrencyArt {
    struct Art { let d: String; let box: CGSize; let widthRatio: CGFloat }

    static let dirham = Art(d: dirhamPath, box: CGSize(width: 1000, height: 870), widthRatio: 0.90)
    static let riyal = Art(d: riyalPath, box: CGSize(width: 1256, height: 1256), widthRatio: 0.78)

    private static let dirhamPath = "m88.3 1c0.4 0.6 2.6 3.3 4.7 5.9 15.3 18.2 26.8 47.8 33 85.1 4.1 24.5 4.3 32.2 4.3 125.6v87h-41.8c-38.2 0-42.6-0.2-50.1-1.7-11.8-2.5-24-9.2-32.2-17.8-6.5-6.9-6.3-7.3-5.9 13.6 0.5 17.3 0.7 19.2 3.2 28.6 4 14.9 9.5 26 17.8 35.9 11.3 13.6 22.8 21.2 39.2 26.3 3.5 1 10.9 1.4 37.1 1.6l32.7 0.5v43.3 43.4l-46.1-0.3-46.3-0.3-8-3.2c-9.5-3.8-13.8-6.6-23.1-14.9l-6.8-6.1 0.4 19.1c0.5 17.7 0.6 19.7 3.1 28.7 8.7 31.8 29.7 54.5 57.4 61.9 6.9 1.9 9.6 2 38.5 2.4l30.9 0.4v89.6c0 54.1-0.3 94-0.8 100.8-0.5 6.2-2.1 17.8-3.5 25.9-6.5 37.3-18.2 65.4-35 83.6l-3.4 3.7h169.1c101.1 0 176.7-0.4 187.8-0.9 19.5-1 63-5.3 72.8-7.4 3.1-0.6 8.9-1.5 12.7-2.1 8.1-1.2 21.5-4 40.8-8.9 27.2-6.8 52-15.3 76.3-26.1 7.6-3.4 29.4-14.5 35.2-18 3.1-1.8 6.8-4 8.2-4.7 3.9-2.1 10.4-6.3 19.9-13.1 4.7-3.4 9.4-6.7 10.4-7.4 4.2-2.8 18.7-14.9 25.3-21 25.1-23.1 46.1-48.8 62.4-76.3 2.3-4 5.3-9 6.6-11.1 3.3-5.6 16.9-33.6 18.2-37.8 0.6-1.9 1.4-3.9 1.8-4.3 2.6-3.4 17.6-50.6 19.4-60.9 0.6-3.3 0.9-3.8 3.4-4.3 1.6-0.3 24.9-0.3 51.8-0.1 53.8 0.4 53.8 0.4 65.7 5.9 6.7 3.1 8.7 4.5 16.1 11.2 9.7 8.7 8.8 10.1 8.2-11.7-0.4-12.8-0.9-20.7-1.8-23.9-3.4-12.3-4.2-14.9-7.2-21.1-9.8-21.4-26.2-36.7-47.2-44l-8.2-3-33.4-0.4-33.3-0.5 0.4-11.7c0.4-15.4 0.4-45.9-0.1-61.6l-0.4-12.6 44.6-0.2c38.2-0.2 45.3 0 49.5 1.1 12.6 3.5 21.1 8.3 31.5 17.8l5.8 5.4v-14.8c0-17.6-0.9-25.4-4.5-37-7.1-23.5-21.1-41-41.1-51.8-13-7-13.8-7.2-58.5-7.5-26.2-0.2-39.9-0.6-40.6-1.2-0.6-0.6-1.1-1.6-1.1-2.4 0-0.8-1.5-7.1-3.5-13.9-23.4-82.7-67.1-148.4-131-197.1-8.7-6.7-30-20.8-38.6-25.6-3.3-1.9-6.9-3.9-7.8-4.5-4.2-2.3-28.3-14.1-34.3-16.6-3.6-1.6-8.3-3.6-10.4-4.4-35.3-15.3-94.5-29.8-139.7-34.3-7.4-0.7-17.2-1.8-21.7-2.2-20.4-2.3-48.7-2.6-209.4-2.6-135.8 0-169.9 0.3-169.4 1zm330.7 43.3c33.8 2 54.6 4.6 78.9 10.5 74.2 17.6 126.4 54.8 164.3 117 3.5 5.8 18.3 36 20.5 42.1 10.5 28.3 15.6 45.1 20.1 67.3 1.1 5.4 2.6 12.6 3.3 16 0.7 3.3 1 6.4 0.7 6.7-0.5 0.4-100.9 0.6-223.3 0.5l-222.5-0.2-0.3-128.5c-0.1-70.6 0-129.3 0.3-130.4l0.4-1.9h71.1c39 0 78 0.4 86.5 0.9zm297.5 350.3c0.7 4.3 0.7 77.3 0 80.9l-0.6 2.7-227.5-0.2-227.4-0.3-0.2-42.4c-0.2-23.3 0-42.7 0.2-43.1 0.3-0.5 97.2-0.8 227.7-0.8h227.2zm-10.2 171.7c0.5 1.5-1.9 13.8-6.8 33.8-5.6 22.5-13.2 45.2-20.9 62-3.8 8.6-13.3 27.2-15.6 30.7-1.1 1.6-4.3 6.7-7.1 11.2-18 28.2-43.7 53.9-73 72.9-10.7 6.8-32.7 18.4-38.6 20.2-1.2 0.3-2.5 0.9-3 1.3-0.7 0.6-9.8 4-20.4 7.8-19.5 6.9-56.6 14.4-86.4 17.5-19.3 1.9-22.4 2-96.7 2h-76.9v-129.7-129.8l220.9-0.4c121.5-0.2 221.6-0.5 222.4-0.7 0.9-0.1 1.8 0.5 2.1 1.2z"

    private static let riyalPath = "M0,0M750,1119 C730,1163,716,1211,711,1262 C711,1262,1136,1172,1136,1172 C1156,1127,1169,1079,1174,1028 C1174,1028,750,1119,750,1119Z M1136,901 C1136,901,1136,901,1136,901 C1156,857,1169,809,1174,758 C1174,758,843,828,843,828 C843,828,843,693,843,693 C843,693,1136,631,1136,631 C1156,587,1169,538,1174,488 C1174,488,843,558,843,558 C843,558,843,72,843,72 C793,100,748,138,711,183 C711,183,711,586,711,586 C711,586,579,614,579,614 C579,614,579,6,579,6 C528,34,483,72,447,117 C447,117,447,642,447,642 C447,642,151,705,151,705 C131,750,117,798,112,849 C112,849,447,777,447,777 C447,777,447,948,447,948 C447,948,88,1024,88,1024 C68,1068,55,1117,50,1167 C50,1167,425,1088,425,1088 C456,1081,482,1063,499,1038 C499,1038,568,936,568,936 C568,936,568,936,568,936 C575,926,579,913,579,899 C579,899,579,749,579,749 C579,749,711,721,711,721 C711,721,711,992,711,992 C711,992,1136,901,1136,901Z"
}

// MARK: - A very small SVG path renderer
//
// Only what these two glyphs use: moveto, lineto, horizontal and vertical lineto, cubic curves and
// close, in both absolute and relative form, with the implicit repeats SVG allows.

struct SVGPath: Shape {
    let d: String
    let box: CGSize

    func path(in rect: CGRect) -> Path {
        // Fit the glyph's own box into the rect, keeping its proportions, and centre what is left over.
        let scale = min(rect.width / box.width, rect.height / box.height)
        let dx = rect.minX + (rect.width - box.width * scale) / 2
        let dy = rect.minY + (rect.height - box.height * scale) / 2
        let map = { (p: CGPoint) in CGPoint(x: dx + p.x * scale, y: dy + p.y * scale) }

        var path = Path()
        var s = Scanner(d)
        var cur = CGPoint.zero          // current point, in glyph units
        var start = CGPoint.zero        // where the open subpath began
        var cmd: Character = "M"

        while true {
            if let c = s.command() { cmd = c }
            else if !s.hasNumber { break }       // an implicit repeat of the last command
            let rel = cmd.isLowercase
            let base = rel ? cur : .zero

            switch Character(cmd.lowercased()) {
            case "m":
                cur = CGPoint(x: base.x + s.number(), y: base.y + s.number())
                start = cur
                path.move(to: map(cur))
                // A second pair after a moveto is a lineto, per SVG.
                cmd = rel ? "l" : "L"
            case "l":
                cur = CGPoint(x: base.x + s.number(), y: base.y + s.number())
                path.addLine(to: map(cur))
            case "h":
                cur = CGPoint(x: base.x + s.number(), y: cur.y)
                path.addLine(to: map(cur))
            case "v":
                cur = CGPoint(x: cur.x, y: base.y + s.number())
                path.addLine(to: map(cur))
            case "c":
                let c1 = CGPoint(x: base.x + s.number(), y: base.y + s.number())
                let c2 = CGPoint(x: base.x + s.number(), y: base.y + s.number())
                let end = CGPoint(x: base.x + s.number(), y: base.y + s.number())
                path.addCurve(to: map(end), control1: map(c1), control2: map(c2))
                cur = end
            case "z":
                path.closeSubpath()
                cur = start
            default:
                return path            // something unsupported: draw what we have rather than nothing
            }
            if !s.hasNumber && s.atEnd { break }
        }
        return path
    }

    /// Walks the path string one command letter or one number at a time.
    private struct Scanner {
        private let c: [Character]
        private var i = 0
        init(_ s: String) { c = Array(s) }

        var atEnd: Bool { i >= c.count }

        mutating func command() -> Character? {
            skip()
            guard i < c.count, c[i].isLetter else { return nil }
            defer { i += 1 }
            return c[i]
        }

        var hasNumber: Bool {
            mutating get {
                skip()
                guard i < c.count else { return false }
                return c[i].isNumber || c[i] == "-" || c[i] == "+" || c[i] == "."
            }
        }

        mutating func number() -> CGFloat {
            skip()
            var out = ""
            if i < c.count, c[i] == "-" || c[i] == "+" { out.append(c[i]); i += 1 }
            var sawDot = false
            while i < c.count {
                if c[i].isNumber { out.append(c[i]); i += 1 }
                else if c[i] == ".", !sawDot { sawDot = true; out.append(c[i]); i += 1 }
                else { break }
            }
            return CGFloat(Double(out) ?? 0)
        }

        private mutating func skip() {
            while i < c.count, c[i] == " " || c[i] == "," || c[i] == "\n" || c[i] == "\t" || c[i] == "\r" { i += 1 }
        }
    }
}
