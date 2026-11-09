import SwiftUI

/// The SAVER eye — the app's guardian. It reacts to what you do:
/// • typing a new password → looks UP (politely not watching)
/// • typing the confirmation → reads along the password, letter by letter
/// • mismatch → squints (suspicious) → turns red and shakes (angry)
/// • match / success → happy ^ ^ with a little sparkle
/// • Face ID → scans left and right; working → thinking circles
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
    case scanning
    case surprised
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
        case .scanning: return 9
        case .surprised: return 10
        case .peek: return 11
        }
    }
}

/// Eye opening with independently animated upper lid, lower lid and a one-sided squint (tilt).
struct EyeOpening: Shape {
    var top: CGFloat
    var bottom: CGFloat
    var tilt: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(top, bottom), tilt) }
        set {
            top = newValue.first.first
            bottom = newValue.first.second
            tilt = newValue.second
        }
    }

    func path(in r: CGRect) -> Path {
        let midY = r.midY
        let half = r.height / 2
        let t = max(top, 0.012) * half * 1.333
        let b = max(bottom, 0.012) * half * 1.333
        let k = r.width * 0.26
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: midY))
        p.addCurve(to: CGPoint(x: r.maxX, y: midY),
                   control1: CGPoint(x: r.minX + k, y: midY - t * (1 + tilt)),
                   control2: CGPoint(x: r.maxX - k, y: midY - t * (1 - tilt)))
        p.addCurve(to: CGPoint(x: r.minX, y: midY),
                   control1: CGPoint(x: r.maxX - k, y: midY + b),
                   control2: CGPoint(x: r.minX + k, y: midY + b))
        p.closeSubpath()
        return p
    }
}

struct HappyArc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                   control1: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY - rect.height * 0.25),
                   control2: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.minY - rect.height * 0.25))
        return p
    }
}

struct IrisView: View {
    var diameter: CGFloat
    var pupil: CGFloat
    var tint: Color
    var tintStrength: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [Theme.accent, Theme.accent2, Color(hex: 0x4FB8FF), Theme.accent2, Theme.accent],
                                      center: .center, angle: .degrees(25)))
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = size.width / 2
                for i in 0..<84 {
                    let a = Double(i) / 84 * 2 * Double.pi
                    let ca = CGFloat(cos(a)), sa = CGFloat(sin(a))
                    let inner = r * (i % 2 == 0 ? 0.40 : 0.46)
                    let outer = r * (i % 3 == 0 ? 0.96 : 0.86)
                    var path = Path()
                    path.move(to: CGPoint(x: c.x + ca * inner, y: c.y + sa * inner))
                    path.addLine(to: CGPoint(x: c.x + ca * outer, y: c.y + sa * outer))
                    ctx.stroke(path, with: .color(.white.opacity(i % 3 == 0 ? 0.18 : 0.07)), lineWidth: max(0.6, r * 0.016))
                }
            }
            Circle().fill(tint.opacity(tintStrength))
            Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.6)], center: .center,
                                         startRadius: diameter * 0.26, endRadius: diameter * 0.5))
            Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: diameter * 0.035)
            Circle()
                .strokeBorder(tint.opacity(0.45), lineWidth: max(1, diameter * 0.012))
                .frame(width: diameter * pupil * 1.12, height: diameter * pupil * 1.12)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x000000), Color(hex: 0x080A14)], center: .center,
                                     startRadius: 0, endRadius: diameter * pupil / 2))
                .frame(width: diameter * pupil, height: diameter * pupil)
        }
        .frame(width: diameter, height: diameter)
        .compositingGroup()
    }
}

struct EyeView: View {
    var mood: EyeMood
    var size: CGFloat = 150
    var sounds: Bool = false

    @State private var blinking = false
    @State private var breathe = false
    @State private var shake: CGFloat = 0
    @State private var jitter: CGSize = .zero
    @State private var sparkle = false

    private var w: CGFloat { size }
    private var h: CGFloat { size * 0.6 }
    private var irisD: CGFloat { h * 0.9 }

    private var needsClock: Bool { [EyeMood.thinking.kind, EyeMood.scanning.kind, EyeMood.lookUp.kind].contains(mood.kind) }

    private var lids: (top: CGFloat, bottom: CGFloat, tilt: CGFloat) {
        if blinking { return (0.02, 0.05, 0) }
        switch mood {
        case .idle: return (1, 1, 0)
        case .lookUp: return (1.06, 0.82, 0)
        case .reading: return (0.8, 0.92, 0)
        case .suspicious: return (0.5, 0.72, 0.28)
        case .angry: return (0.46, 0.78, 0)
        case .sleepy: return (0.34, 0.95, 0)
        case .closed: return (0.0, 0.0, 0)
        case .thinking: return (0.9, 0.95, 0)
        case .scanning: return (1, 1, 0)
        case .surprised: return (1.16, 1.1, 0)
        case .peek: return (0.3, 0.6, 0)
        case .happy: return (0.0, 0.0, 0)
        }
    }

    private var pupilScale: CGFloat {
        switch mood {
        case .reading: return 0.46
        case .angry: return 0.24
        case .suspicious: return 0.28
        case .surprised: return 0.22
        case .lookUp: return 0.38
        case .sleepy: return 0.42
        case .scanning: return 0.32
        default: return 0.36
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

    private var tintStrength: Double {
        switch mood {
        case .angry: return 0.45
        case .suspicious: return 0.25
        default: return 0
        }
    }

    private func pupilOffset(_ t: Double) -> CGSize {
        let maxX = w * 0.24, maxY = h * 0.2
        switch mood {
        case .lookUp:
            // Looking away "innocently": drifts slowly left and right while you type.
            return CGSize(width: CGFloat(sin(t * 0.9)) * maxX * 0.35, height: -maxY + CGFloat(sin(t * 1.7)) * maxY * 0.1)
        case .reading(let p), .suspicious(let p):
            let x = (min(max(p, 0), 1) * 2 - 1) * maxX
            return CGSize(width: x, height: maxY * 0.35)
        case .thinking: return CGSize(width: CGFloat(cos(t * 4.2)) * maxX * 0.55, height: CGFloat(sin(t * 4.2)) * maxY * 0.55)
        case .scanning: return CGSize(width: CGFloat(sin(t * 3.0)) * maxX * 0.85, height: 0)
        case .sleepy: return CGSize(width: 0, height: maxY * 0.45)
        case .peek: return CGSize(width: maxX * 0.4, height: maxY * 0.3)
        case .idle: return jitter
        default: return .zero
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !needsClock)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                if mood == .happy {
                    happyEye.transition(.scale(scale: 0.7).combined(with: .opacity))
                } else {
                    openEye(offset: pupilOffset(t)).transition(.opacity)
                }
            }
            .frame(width: w, height: h)
        }
        .background(halo)
        .offset(x: shake)
        .environment(\.layoutDirection, .leftToRight)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: mood)
        .animation(.easeInOut(duration: blinking ? 0.07 : 0.12), value: blinking)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { breathe = true }
        }
        .task { await blinkLoop() }
        .task(id: mood.kind) { await saccades() }
        .onChange(of: mood) { old, new in react(old, new) }
        .accessibilityHidden(true)
    }

    private var halo: some View {
        Ellipse()
            .fill(RadialGradient(colors: [tint.opacity(0.38), tint.opacity(0)], center: .center, startRadius: 0, endRadius: w * 0.8))
            .frame(width: w * 1.7, height: h * 2.3)
            .blur(radius: 22)
            .scaleEffect(breathe ? 1.06 : 0.94)
            .opacity(mood == .closed ? 0.3 : 1)
            .allowsHitTesting(false)
    }

    private func openEye(offset: CGSize) -> some View {
        let l = lids
        let shape = EyeOpening(top: l.top, bottom: l.bottom, tilt: l.tilt)
        return ZStack {
            shape.fill(LinearGradient(colors: [Color(hex: 0x1C2042), Color(hex: 0x0B0D1D)], startPoint: .top, endPoint: .bottom))
            Ellipse()
                .fill(RadialGradient(colors: [Color.white.opacity(0.07), .clear], center: .center, startRadius: 0, endRadius: w * 0.4))
                .frame(width: w * 0.8, height: h * 0.6)
            IrisView(diameter: irisD, pupil: pupilScale, tint: tint, tintStrength: tintStrength)
                .offset(offset)
            shape.fill(LinearGradient(colors: [Color.black.opacity(0.5), .clear],
                                      startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.42)))
            // Reflections stay fixed on the eye's surface while the iris moves underneath.
            Circle().fill(.white.opacity(0.92))
                .frame(width: irisD * 0.16, height: irisD * 0.16)
                .blur(radius: 0.6)
                .offset(x: -w * 0.1, y: -h * 0.16)
            Circle().fill(.white.opacity(0.45))
                .frame(width: irisD * 0.06, height: irisD * 0.06)
                .offset(x: w * 0.07, y: h * 0.11)
        }
        .frame(width: w, height: h)
        .mask(shape.frame(width: w, height: h))
        .overlay(
            shape
                .stroke(LinearGradient(colors: [Theme.accent, tint, Theme.accent3], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: max(2, size * 0.024), lineCap: .round, lineJoin: .round))
                .frame(width: w, height: h)
                .shadow(color: tint.opacity(0.85), radius: size * 0.05)
        )
    }

    private static let sparkSizes: [CGFloat] = [0.11, 0.08, 0.07]
    private static let sparkX: [CGFloat] = [0.42, -0.4, 0.3]
    private static let sparkY: [CGFloat] = [-0.42, -0.3, 0.32]

    private var happyEye: some View {
        ZStack {
            HappyArc()
                .stroke(LinearGradient(colors: [Theme.ok, Theme.accent], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                .frame(width: w * 0.72, height: h * 0.42)
                .shadow(color: Theme.ok.opacity(0.75), radius: size * 0.08)
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: size * Self.sparkSizes[i], weight: .bold))
                    .foregroundStyle(i == 1 ? Theme.accent : Theme.ok)
                    .offset(x: w * Self.sparkX[i], y: h * Self.sparkY[i])
                    .scaleEffect(sparkle ? 1 : 0.2)
                    .opacity(sparkle ? 1 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.5).delay(Double(i) * 0.08), value: sparkle)
            }
        }
        .onAppear { sparkle = true }
        .onDisappear { sparkle = false }
    }

    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 2.6...5.5) * 1_000_000_000))
            guard [0, 1, 2, 8, 9].contains(mood.kind) else { continue }
            blinking = true
            try? await Task.sleep(nanoseconds: 95_000_000)
            blinking = false
            if Double.random(in: 0...1) < 0.18 {          // the occasional double blink
                try? await Task.sleep(nanoseconds: 160_000_000)
                blinking = true
                try? await Task.sleep(nanoseconds: 85_000_000)
                blinking = false
            }
        }
    }

    /// Small, natural glances while idle so the eye feels alive.
    private func saccades() async {
        guard mood.kind == EyeMood.idle.kind else {
            if jitter != .zero { jitter = .zero }
            return
        }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.9...2.2) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let next = Double.random(in: 0...1) < 0.25
                ? CGSize.zero
                : CGSize(width: CGFloat.random(in: -0.16...0.16) * w, height: CGFloat.random(in: -0.1...0.1) * h)
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) { jitter = next }
        }
    }

    private func react(_ old: EyeMood, _ new: EyeMood) {
        guard old.kind != new.kind else { return }
        switch new {
        case .angry:
            shakeIt()
            if sounds { SoundFX.shared.play(.error, volume: 0.5) }
            Haptics.error()
        case .happy:
            if sounds { SoundFX.shared.play(.success, volume: 0.5) }
            Haptics.success()
        case .suspicious:
            Haptics.warning()
        case .lookUp, .reading:
            Haptics.soft(0.35)
        case .idle where old.kind == EyeMood.closed.kind:
            if sounds { SoundFX.shared.play(.eyeOpen, volume: 0.4) }
        default:
            break
        }
    }

    private func shakeIt() {
        Task {
            for x in [14, -12, 9, -6, 3, 0] {
                withAnimation(.easeInOut(duration: 0.05)) { shake = CGFloat(x) }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}

/// Small brand mark (eye + keyhole) used in headers and the about section.
struct BrandMark: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            EyeOpening(top: 1, bottom: 1, tilt: 0)
                .stroke(Theme.brandGradient, style: StrokeStyle(lineWidth: size * 0.09, lineJoin: .round))
                .frame(width: size, height: size * 0.6)
            Circle().fill(Theme.gradient).frame(width: size * 0.42, height: size * 0.42)
            VStack(spacing: -size * 0.02) {
                Circle().fill(Theme.bg).frame(width: size * 0.12, height: size * 0.12)
                Capsule().fill(Theme.bg).frame(width: size * 0.06, height: size * 0.11)
            }
        }
        .frame(width: size, height: size * 0.6)
        .environment(\.layoutDirection, .leftToRight)
    }
}
