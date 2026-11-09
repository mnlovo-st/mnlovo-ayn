import SwiftUI
import UIKit
import AVFoundation

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Theme {
    static let bg = Color(hex: 0x07080D)
    static let bg2 = Color(hex: 0x0E1019)
    static let surface = Color.white.opacity(0.055)
    static let surfaceHi = Color.white.opacity(0.09)
    static let stroke = Color.white.opacity(0.09)
    static let text = Color(hex: 0xEEF1FA)
    static let sub = Color(hex: 0xEEF1FA, alpha: 0.58)
    static let faint = Color(hex: 0xEEF1FA, alpha: 0.32)

    static let accent = Color(hex: 0x39E6C8)   // aurora teal
    static let accent2 = Color(hex: 0x7B6CFF)  // indigo
    static let ok = Color(hex: 0x3BE38A)
    static let warn = Color(hex: 0xFFC048)
    static let danger = Color(hex: 0xFF5A6E)

    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let softGradient = LinearGradient(colors: [accent.opacity(0.25), accent2.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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

enum SFX: String, CaseIterable {
    case intro, tap, type, toggle, success, error, unlock, lock, blink, delete, notify
    case eyeOpen = "eye_open"
}

final class SoundFX {
    static let shared = SoundFX()
    private var players: [SFX: AVAudioPlayer] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for s in SFX.allCases {
            if let url = Bundle.main.url(forResource: s.rawValue, withExtension: "wav"),
               let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay()
                players[s] = p
            }
        }
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: "fx.sound") as? Bool ?? true }

    func play(_ s: SFX, volume: Float = 0.7) {
        guard enabled, let p = players[s] else { return }
        p.volume = volume
        p.currentTime = 0
        p.play()
    }
}

/// Convenience: sound + haptic together.
enum FX {
    static func tap() { SoundFX.shared.play(.tap, volume: 0.5); Haptics.tap() }
    static func toggle() { SoundFX.shared.play(.toggle, volume: 0.5); Haptics.selection() }
    static func success() { SoundFX.shared.play(.success); Haptics.success() }
    static func error() { SoundFX.shared.play(.error); Haptics.error() }
    static func key() { SoundFX.shared.play(.type, volume: 0.35); Haptics.soft(0.35) }
}
