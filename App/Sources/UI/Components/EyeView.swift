import SwiftUI

/// The AYN eye — reacts to what you're doing:
/// • typing a new password → looks UP (politely not watching)
/// • typing the confirmation → reads along the password character by character
/// • mismatch → narrows (suspicious) → red and shakes (angry)
/// • match / success → happy ^ ^
enum EyeMood: Equatable {
    case idle
    case lookUp
    case reading(CGFloat)      // 0…1 progress through the password
    case suspicious(CGFloat)
    case happy
    case angry
    case sleepy
    case closed
    case thinking
    case peek

    var kind: Int {
        switch self {
        case .idle: return 0
        case .lookUp: return 1
        case .reading: return 2
        case .suspicious: return 3
        case .happy: return 4
        case .angry: return 5
        case .sleepy: return 6
        case .closed: return 7
        case .thinking: return 8
        case .peek: return 9
        }
    }
}

struct AlmondShape: Shape {
    var openness: CGFloat
    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        let h = rect.height / 2 * max(openness, 0.015)
        p.move(to: CGPoint(x: rect.minX, y: midY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: midY), control: CGPoint(x: rect.midX, y: midY - h * 2))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: midY), control: CGPoint(x: rect.midX, y: midY + h * 2))
        p.closeSubpath()
        return p
    }
}

struct HappyArc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.7))
        return p
    }
}

struct EyeView: View {
    var mood: EyeMood
    var size: CGFloat = 150
    var sounds: Bool = false

    @State private var blinking = false
    @State private var irisSpin = 0.0
    @State private var breathe = false
    @State private var shake: CGFloat = 0

    private var w: CGFloat { size }
    private var h: CGFloat { size * 0.62 }

    private var isThinking: Bool { mood.kind == EyeMood.thinking.kind }

    private var openness: CGFloat {
        if blinking { return 0.04 }
        switch mood {
        case .idle, .happy: return 1
        case .lookUp: return 0.92
        case .reading: return 0.8
        case .suspicious: return 0.5
        case .angry: return 0.55
        case .sleepy: return 0.32
        case .closed: return 0.015
        case .thinking: return 0.85
        case .peek: return 0.28
        }
    }

    private func pupilOffset(angle: Double) -> CGSize {
        let maxX = w * 0.27, maxY = h * 0.24
        switch mood {
        case .lookUp: return CGSize(width: 0, height: -maxY)
        case .reading(let p), .suspicious(let p):
            let x = (min(max(p, 0), 1) * 2 - 1) * maxX
            return CGSize(width: x, height: maxY * 0.55)
        case .thinking: return CGSize(width: cos(angle) * maxX * 0.6, height: sin(angle) * maxY * 0.6)
        case .sleepy: return CGSize(width: 0, height: maxY * 0.5)
        case .peek: return CGSize(width: maxX * 0.4, height: maxY * 0.4)
        default: return .zero
        }
    }

    private var tint: Color {
        switch mood {
        case .angry: return Theme.danger
        case .suspicious: return Theme.warn
        case .happy: return Theme.ok
        case .reading: return Theme.accent2
        default: return Theme.accent
        }
    }

    private var pupilScale: CGFloat {
        switch mood {
        case .reading: return 0.48
        case .angry: return 0.26
        case .suspicious: return 0.3
        case .lookUp: return 0.4
        case .sleepy: return 0.44
        default: return 0.38
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isThinking)) { ctx in
            let angle = ctx.date.timeIntervalSinceReferenceDate * 4.2
            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [tint.opacity(0.42), tint.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: w * 0.75))
                    .frame(width: w * 1.7, height: h * 1.9)
                    .blur(radius: 18)
                    .scaleEffect(breathe ? 1.06 : 0.94)
                    .opacity(mood == .closed ? 0.35 : 1)

                if mood == .happy {
                    happyEye.transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    openEye(angle: angle).transition(.opacity)
                }
            }
        }
        .frame(width: w * 1.25, height: h * 1.45)
        .offset(x: shake)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: mood.kind)
        .onAppear {
            withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) { irisSpin = 360 }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
        }
        .task { await blinkLoop() }
        .onChange(of: mood) { old, new in react(old, new) }
        .accessibilityHidden(true)
    }

    private func openEye(angle: Double) -> some View {
        let o = openness
        let offset = pupilOffset(angle: angle)
        return ZStack {
            AlmondShape(openness: o)
                .fill(LinearGradient(colors: [Color(hex: 0xF7F9FF), Color(hex: 0xD6DDF0)], startPoint: .top, endPoint: .bottom))
            iris.offset(offset)
            AlmondShape(openness: o)
                .fill(LinearGradient(colors: [Color.black.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
        }
        .frame(width: w, height: h)
        .mask(AlmondShape(openness: o).frame(width: w, height: h))
        .overlay(
            AlmondShape(openness: o)
                .stroke(tint, style: StrokeStyle(lineWidth: max(2, size * 0.026), lineCap: .round, lineJoin: .round))
                .frame(width: w, height: h)
                .shadow(color: tint.opacity(0.9), radius: 8)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: o)
        .animation(isThinking ? nil : Animation.spring(response: 0.45, dampingFraction: 0.72), value: offset)
    }

    private var iris: some View {
        let d = h * 0.92
        return ZStack {
            Circle()
                .fill(AngularGradient(colors: [Theme.accent, Theme.accent2, Theme.accent, Theme.accent2, Theme.accent], center: .center))
                .rotationEffect(.degrees(irisSpin))
            Circle().fill(tint.opacity(mood == .angry || mood.kind == 3 ? 0.35 : 0))
            Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.5)], center: .center,
                                         startRadius: d * 0.22, endRadius: d * 0.5))
            Circle().strokeBorder(tint.opacity(0.65), lineWidth: d * 0.03)
            Circle().fill(Color(hex: 0x05060A))
                .frame(width: d * pupilScale, height: d * pupilScale)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: pupilScale)
            Circle().fill(.white.opacity(0.95)).frame(width: d * 0.17, height: d * 0.17).offset(x: -d * 0.16, y: -d * 0.18)
            Circle().fill(.white.opacity(0.5)).frame(width: d * 0.07, height: d * 0.07).offset(x: d * 0.14, y: d * 0.13)
        }
        .frame(width: d, height: d)
    }

    private var happyEye: some View {
        HappyArc()
            .stroke(LinearGradient(colors: [Theme.ok, Theme.accent], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
            .frame(width: w * 0.78, height: h * 0.5)
            .shadow(color: Theme.ok.opacity(0.8), radius: 12)
    }

    private func blinkLoop() async {
        while !Task.isCancelled {
            let wait = UInt64(Double.random(in: 2.4...5.2) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: wait)
            guard [0, 1, 2, 8].contains(mood.kind) else { continue }
            withAnimation(.easeIn(duration: 0.07)) { blinking = true }
            try? await Task.sleep(nanoseconds: 110_000_000)
            withAnimation(.easeOut(duration: 0.12)) { blinking = false }
        }
    }

    private func react(_ old: EyeMood, _ new: EyeMood) {
        guard old.kind != new.kind else { return }
        switch new {
        case .angry:
            shakeIt()
            if sounds { SoundFX.shared.play(.error) }
            Haptics.error()
        case .happy:
            if sounds { SoundFX.shared.play(.success) }
            Haptics.success()
        case .lookUp:
            if sounds { SoundFX.shared.play(.blink, volume: 0.45) }
            Haptics.soft(0.4)
        case .reading:
            if sounds { SoundFX.shared.play(.eyeOpen, volume: 0.35) }
            Haptics.soft(0.5)
        case .suspicious:
            Haptics.warning()
        case .closed:
            if sounds { SoundFX.shared.play(.blink, volume: 0.5) }
        default:
            break
        }
    }

    private func shakeIt() {
        Task {
            for x in [16, -14, 11, -8, 5, -3, 0] {
                withAnimation(.easeInOut(duration: 0.05)) { shake = CGFloat(x) }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}
