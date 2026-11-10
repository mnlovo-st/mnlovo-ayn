import SwiftUI
import UIKit
import AVFoundation
import CoreText

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Brand {
    static let appName = "MNLOVO SAVER"
    static let copyright = "© MNLOVO 2026"
    static let issuer = "MNLOVO SAVER"
}

enum Theme {
    static let bg = Color(hex: 0x06070C)
    static let bg2 = Color(hex: 0x0D0F1A)
    static let surface = Color.white.opacity(0.05)
    static let surfaceHi = Color.white.opacity(0.085)
    static let stroke = Color.white.opacity(0.08)
    static let text = Color(hex: 0xEEF1FA)
    static let sub = Color(hex: 0xEEF1FA, alpha: 0.6)
    static let faint = Color(hex: 0xEEF1FA, alpha: 0.34)

    static let accent = Color(hex: 0x39E6C8)   // aurora teal
    static let accent2 = Color(hex: 0x7B6CFF)  // indigo
    static let accent3 = Color(hex: 0xC45CFF)  // violet
    static let ok = Color(hex: 0x3BE38A)
    static let warn = Color(hex: 0xFFC048)
    static let danger = Color(hex: 0xFF5A6E)

    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let brandGradient = LinearGradient(colors: [accent, accent2, accent3], startPoint: .leading, endPoint: .trailing)
    static let softGradient = LinearGradient(colors: [accent.opacity(0.22), accent2.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Somar Sans when its files are bundled (App/Resources/Fonts), otherwise the system rounded font.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let name = FontBook.name(for: weight) { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: weight, design: .rounded)
    }

    /// Codes and passwords: same family with fixed-width digits so they never jump around.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        font(size, weight).monospacedDigit()
    }
}

// MARK: - Fonts (Somar)

/// Registers the bundled Somar Sans files (App/Resources/Fonts) at launch.
enum FontBook {
    private static let names: [String: String] = [
        "light": "SomarSans-Light", "regular": "SomarSans-Regular", "medium": "SomarSans-Medium",
        "semibold": "SomarSans-SemiBold", "bold": "SomarSans-Bold", "heavy": "SomarSans-ExtraBold",
        "black": "SomarSans-Black"
    ]
    private static var available: Set<String> = []
    private static var registered = false

    static func registerAll() {
        guard !registered else { return }
        registered = true
        var urls: [URL] = []
        for ext in ["otf", "ttf"] {
            urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
            urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Fonts") ?? []
        }
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        for n in names.values where UIFont(name: n, size: 12) != nil { available.insert(n) }
        if let n = name(for: .semibold), let f = UIFont(name: n, size: 13) {
            UISegmentedControl.appearance().setTitleTextAttributes([.font: f], for: .normal)
        }
    }

    static var isAvailable: Bool { !available.isEmpty }

    static func name(for weight: Font.Weight) -> String? {
        guard !available.isEmpty else { return nil }
        let key: String
        switch weight {
        case .ultraLight, .thin, .light: key = "light"
        case .medium: key = "medium"
        case .semibold: key = "semibold"
        case .bold: key = "bold"
        case .heavy: key = "heavy"
        case .black: key = "black"
        default: key = "regular"
        }
        if let n = names[key], available.contains(n) { return n }
        return names["regular"].flatMap { available.contains($0) ? $0 : nil }
    }
}

// MARK: - Haptics

enum Haptics {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "fx.haptics") as? Bool ?? true }

    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func soft(_ intensity: CGFloat = 0.5) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: intensity)
    }
    static func selection() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func error() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// MARK: - Sound effects
// Sounds play only for meaningful moments (intro, unlock, lock, success, error, the eye waking,
// deleting). Taps, typing and toggles are silent — they get a light haptic instead.

enum SFX: String, CaseIterable {
    case intro, unlock, lock, success, error, delete, notify, anger, lockout
    case eyeOpen = "eye_open"
    case errSoft = "err_soft", errPassword = "err_password", errCode = "err_code"

    var isError: Bool { [.error, .errSoft, .errPassword, .errCode, .anger, .lockout].contains(self) }
}

/// Where an error happened — each place has its own sound.
enum ErrorKind { case general, passcode, password, code, anger, lockout }

final class SoundFX {
    static let shared = SoundFX()
    private var players: [SFX: AVAudioPlayer] = [:]
    private var lastPlayed: [SFX: Date] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for s in SFX.allCases {
            if let url = Bundle.main.url(forResource: s.rawValue, withExtension: "wav"),
               let p = try? AVAudioPlayer(contentsOf: url) {
                p.enableRate = true
                p.prepareToPlay()
                players[s] = p
            }
        }
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: "fx.sound") as? Bool ?? true }

    private var lastError = Date.distantPast

    func play(_ s: SFX, volume: Float = 0.55) {
        guard enabled, let p = players[s] else { return }
        // Never stack the same sound within 0.4 s, and never two error sounds on top of each other.
        if let last = lastPlayed[s], Date().timeIntervalSince(last) < 0.4 { return }
        if s.isError {
            if Date().timeIntervalSince(lastError) < 0.5 { return }
            lastError = Date()
        }
        lastPlayed[s] = Date()
        p.volume = volume
        // A touch of pitch variation so repeated errors never sound identical.
        p.rate = s.isError && s != .anger ? Float.random(in: 0.94...1.06) : 1
        p.currentTime = 0
        p.play()
    }

    func playError(_ kind: ErrorKind) {
        switch kind {
        case .general: play(.error, volume: 0.5)
        case .passcode: play(.errSoft, volume: 0.6)
        case .password: play(.errPassword, volume: 0.55)
        case .code: play(.errCode, volume: 0.55)
        case .anger: play(.anger, volume: 0.7)
        case .lockout: play(.lockout, volume: 0.6)
        }
    }
}

/// Feedback helpers: taps/toggles/keys are haptic-only; success/error add a sound.
enum FX {
    static func tap() { Haptics.tap() }
    static func toggle() { Haptics.selection() }
    static func key() { }
    static func success() { SoundFX.shared.play(.success); Haptics.success() }
    static func error(_ kind: ErrorKind = .general) { SoundFX.shared.playError(kind); Haptics.error() }
}
