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
    case furious          // boiling over: red, slanted lids, trembling, heartbeat glow
    case glare            // holds a grudge: narrow, locked on you, the odd twitch
    case love             // heart-shaped pupil, warm pink (celebrations)
    case dizzy            // spiral eyes (lots of mistakes / overload)

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
        case .furious: return 12
        case .glare: return 13
        case .love: return 14
        case .dizzy: return 15
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
    @State private var since = Date()
    @State private var squash: CGFloat = 1

    private var w: CGFloat { size }
    private var h: CGFloat { size * 0.6 }
    private var irisD: CGFloat { h * 0.9 }

    // MARK: Shape of the lids — every mood moves differently over time

    private func lids(_ t: Double, _ age: Double) -> (top: CGFloat, bottom: CGFloat, tilt: CGFloat) {
        if blinking { return (0.02, 0.05, 0) }
        let st = CGFloat(sin(t))
        switch mood {
        case .idle: return (1, 1, 0)
        case .lookUp:      // innocent whistle: lids flutter a little
            return (1.06 + 0.03 * CGFloat(sin(t * 7)), 0.8, 0)
        case .reading:     // focused, slight squint that follows the letters
            return (0.78 + 0.04 * CGFloat(sin(t * 3)), 0.9, 0)
        case .suspicious:  // sizing you up: tilts one side, then the other
            return (0.5, 0.72, 0.28 * CGFloat(sin(t * 1.3)) + 0.08)
        case .angry:       // flash of anger: slanted, small tremble
            return (0.46 + 0.03 * CGFloat(sin(t * 38)), 0.78, -0.35)
        case .furious:     // boiling: deep slant, strong tremble, lids clench with each heartbeat
            let beat = CGFloat(max(0, sin(t * 7.5))) * 0.1
            return (0.36 - beat + 0.03 * CGFloat(sin(t * 47)), 0.66 - beat * 0.5, -0.55)
        case .glare:       // grudge: narrow and steady, a twitch every few seconds
            let twitch = fmod(t, 3.4) < 0.14 ? CGFloat(0.12) : 0
            return (0.4 - twitch, 0.6, -0.32 + 0.04 * st)
        case .sleepy:      // nodding off, then catching itself
            let cycle = fmod(age, 4.2)
            let droop = cycle < 3.2 ? CGFloat(cycle / 3.2) : CGFloat(1 - (cycle - 3.2))
            return (0.42 - 0.34 * droop, 0.95, 0)
        case .closed: return (0, 0, 0)
        case .thinking:    // looks up and away while thinking
            return (0.92, 0.9 + 0.04 * CGFloat(sin(t * 2)), 0.06 * st)
        case .scanning: return (1, 1, 0)
        case .surprised:   // pops wide, settles slightly
            let pop = CGFloat(max(0, 1 - age * 2.5)) * 0.14
            return (1.16 + pop, 1.1 + pop, 0)
        case .peek: return (0.3 + 0.06 * CGFloat(sin(t * 2.2)), 0.6, 0.1)
        case .happy, .love: return (0, 0, 0)
        case .dizzy: return (1, 1, 0)
        }
    }

    private func pupilScale(_ t: Double, _ age: Double) -> CGFloat {
        switch mood {
        case .reading: return 0.46
        case .angry: return 0.24
        case .furious: return 0.18 + 0.02 * CGFloat(sin(t * 30))
        case .glare: return 0.22
        case .suspicious: return 0.28
        case .surprised: return 0.18 + CGFloat(min(1, age * 2)) * 0.06   // snaps tiny, then opens a little
        case .lookUp: return 0.38
        case .sleepy: return 0.44
        case .scanning: return 0.32
        case .thinking: return 0.34 + 0.03 * CGFloat(sin(t * 1.5))
        case .idle: return 0.36 + 0.025 * CGFloat(sin(t * 0.7))           // breathes with the light
        default: return 0.36
        }
    }

    private var tint: Color {
        switch mood {
        case .angry, .furious: return Theme.danger
        case .glare: return Color(hex: 0xFF7A45)
        case .suspicious: return Theme.warn
        case .happy: return Theme.ok
        case .love: return Color(hex: 0xFF5FA2)
        case .reading: return Theme.accent2
        case .dizzy: return Theme.accent3
        default: return Theme.accent
        }
    }

    private func tintStrength(_ t: Double) -> Double {
        switch mood {
        case .angry: return 0.45
        case .furious: return 0.5 + 0.15 * sin(t * 7.5)
        case .glare: return 0.32
        case .suspicious: return 0.25
        case .dizzy: return 0.2
        default: return 0
        }
    }

    private func pupilOffset(_ t: Double, _ age: Double) -> CGSize {
        let maxX = w * 0.24, maxY = h * 0.2
        switch mood {
        case .lookUp:
            // Looking away "innocently"; every few seconds sneaks a quick peek down, then back up.
            let peek = fmod(t, 4.5) < 0.35 ? maxY * 1.3 : 0
            return CGSize(width: CGFloat(sin(t * 0.9)) * maxX * 0.35, height: -maxY + peek + CGFloat(sin(t * 1.7)) * maxY * 0.1)
        case .reading(let p):
            let x = (min(max(p, 0), 1) * 2 - 1) * maxX
            return CGSize(width: x, height: maxY * 0.35 + CGFloat(sin(t * 9)) * maxY * 0.05)
        case .suspicious(let p):
            let x = (min(max(p, 0), 1) * 2 - 1) * maxX * 0.6 + CGFloat(sin(t * 1.3)) * maxX * 0.25
            return CGSize(width: x, height: maxY * 0.15)
        case .thinking: return CGSize(width: CGFloat(cos(t * 3.2)) * maxX * 0.5 + maxX * 0.3, height: -maxY * 0.5 + CGFloat(sin(t * 3.2)) * maxY * 0.4)
        case .scanning: return CGSize(width: CGFloat(sin(t * 3.0)) * maxX * 0.85, height: CGFloat(sin(t * 1.1)) * maxY * 0.15)
        case .sleepy: return CGSize(width: CGFloat(sin(t * 0.6)) * maxX * 0.1, height: maxY * 0.5)
        case .peek: return CGSize(width: maxX * 0.5 * CGFloat(sin(t * 0.8)), height: maxY * 0.3)
        case .furious: return CGSize(width: CGFloat(sin(t * 53)) * 1.6, height: CGFloat(cos(t * 47)) * 1.2)
        case .glare: return CGSize(width: CGFloat(sin(t * 0.5)) * maxX * 0.08, height: 0)
        case .surprised: return CGSize(width: 0, height: -maxY * 0.15)
        case .idle: return jitter
        default: return .zero
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: mood == .closed)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let age = ctx.date.timeIntervalSince(since)
            ZStack {
                switch mood {
                case .happy: happyEye(t).transition(.scale(scale: 0.7).combined(with: .opacity))
                case .love: loveEye(t).transition(.scale(scale: 0.6).combined(with: .opacity))
                case .dizzy: dizzyEye(t).transition(.opacity)
                default: openEye(t, age).transition(.opacity)
                }
                overlays(t, age)
            }
            .frame(width: w, height: h)
            .scaleEffect(bodyScale(t, age))
            .rotationEffect(.degrees(bodyRotation(t)))
            .background(halo(t))
        }
        .scaleEffect(x: 1, y: squash)
        .offset(x: shake)
        .environment(\.layoutDirection, .leftToRight)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: mood)
        .animation(.easeInOut(duration: blinking ? 0.07 : 0.12), value: blinking)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { breathe = true }
        }
        .task { await blinkLoop() }
        .task(id: mood.kind) { await saccades() }
        .onChange(of: mood) { old, new in
            if old.kind != new.kind { since = Date() }
            react(old, new)
        }
        .accessibilityHidden(true)
    }

    private func bodyScale(_ t: Double, _ age: Double) -> CGFloat {
        switch mood {
        case .happy: return 1 + 0.035 * CGFloat(sin(t * 6))
        case .love: return 1 + 0.06 * CGFloat(max(0, sin(t * 5)))                 // heartbeat
        case .furious: return 1 + 0.035 * CGFloat(max(0, sin(t * 7.5)))
        case .surprised: return 1 + CGFloat(max(0, 0.12 - age * 0.3))
        case .idle: return 1 + 0.008 * CGFloat(sin(t * 0.9))
        default: return 1
        }
    }

    private func bodyRotation(_ t: Double) -> Double {
        switch mood {
        case .happy: return 3 * sin(t * 3)
        case .thinking: return 4 * sin(t * 0.8)
        case .dizzy: return 5 * sin(t * 2.4)
        case .sleepy: return 2 * sin(t * 0.7)
        case .suspicious: return -3
        default: return 0
        }
    }

    private func halo(_ t: Double) -> some View {
        let pulse: CGFloat = {
            switch mood {
            case .furious: return 1 + 0.18 * CGFloat(max(0, sin(t * 7.5)))
            case .love: return 1 + 0.12 * CGFloat(max(0, sin(t * 5)))
            default: return breathe ? 1.06 : 0.94
            }
        }()
        return Ellipse()
            .fill(RadialGradient(colors: [tint.opacity(mood == .furious ? 0.6 : 0.38), tint.opacity(0)], center: .center, startRadius: 0, endRadius: w * 0.8))
            .frame(width: w * 1.7, height: h * 2.3)
            .blur(radius: 22)
            .scaleEffect(pulse)
            .opacity(mood == .closed ? 0.3 : 1)
            .allowsHitTesting(false)
    }

    // MARK: Extra touches per mood

    @ViewBuilder
    private func overlays(_ t: Double, _ age: Double) -> some View {
        switch mood {
        case .sleepy:
            ForEach(0..<3, id: \.self) { i in
                let p = fmod(t * 0.45 + Double(i) / 3, 1)
                Text("z")
                    .font(.system(size: size * (0.09 + 0.05 * CGFloat(p)), weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.accent2.opacity(1 - p))
                    .offset(x: w * (0.42 + 0.12 * CGFloat(p)), y: -h * (0.3 + 0.6 * CGFloat(p)))
            }
        case .thinking:
            HStack(spacing: size * 0.03) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Theme.accent.opacity(0.9))
                        .frame(width: size * 0.045, height: size * 0.045)
                        .offset(y: -CGFloat(max(0, sin(t * 5 - Double(i) * 0.7))) * size * 0.04)
                }
            }
            .offset(x: w * 0.42, y: -h * 0.62)
        case .scanning:
            // A soft light beam sweeps up and down, like Face ID.
            let y = CGFloat(sin(t * 2.2)) * h * 0.42
            LinearGradient(colors: [.clear, Theme.accent.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: w * 0.9, height: max(1.5, size * 0.012))
                .shadow(color: Theme.accent, radius: 6)
                .offset(y: y)
                .mask(EyeOpening(top: 1, bottom: 1, tilt: 0).frame(width: w, height: h))
        case .furious:
            angerMark(t).offset(x: w * 0.44, y: -h * 0.6)
        case .glare:
            angerMark(t).scaleEffect(0.6).opacity(0.55).offset(x: w * 0.46, y: -h * 0.58)
        case .surprised:
            if age < 0.6 {
                ForEach(0..<6, id: \.self) { i in
                    let a = Double(i) / 6 * 2 * .pi - .pi / 2
                    Capsule().fill(Theme.accent)
                        .frame(width: size * 0.02, height: size * 0.07)
                        .offset(y: -h * 0.75 - CGFloat(age) * size * 0.15)
                        .rotationEffect(.radians(a))
                        .opacity(1 - age / 0.6)
                }
            }
        default:
            EmptyView()
        }
    }

    /// The little "💢" mark, drawn with four curved strokes that throb.
    private func angerMark(_ t: Double) -> some View {
        let s = size * 0.16
        return ZStack {
            ForEach(0..<4, id: \.self) { i in
                Path { p in
                    p.move(to: CGPoint(x: s * 0.12, y: s * 0.45))
                    p.addQuadCurve(to: CGPoint(x: s * 0.45, y: s * 0.12), control: CGPoint(x: s * 0.42, y: s * 0.42))
                }
                .stroke(Theme.danger, style: StrokeStyle(lineWidth: max(1.5, s * 0.13), lineCap: .round))
                .frame(width: s, height: s)
                .rotationEffect(.degrees(Double(i) * 90))
            }
        }
        .frame(width: s, height: s)
        .scaleEffect(1 + 0.18 * CGFloat(max(0, sin(t * 7.5))))
        .shadow(color: Theme.danger.opacity(0.8), radius: 4)
    }

    private func openEye(_ t: Double, _ age: Double) -> some View {
        let l = lids(t, age)
        let shape = EyeOpening(top: l.top, bottom: l.bottom, tilt: l.tilt)
        return ZStack {
            shape.fill(LinearGradient(colors: [Color(hex: 0x1C2042), Color(hex: 0x0B0D1D)], startPoint: .top, endPoint: .bottom))
            Ellipse()
                .fill(RadialGradient(colors: [Color.white.opacity(0.07), .clear], center: .center, startRadius: 0, endRadius: w * 0.4))
                .frame(width: w * 0.8, height: h * 0.6)
            IrisView(diameter: irisD, pupil: pupilScale(t, age), tint: tint, tintStrength: tintStrength(t))
                .rotationEffect(.degrees(mood == .thinking ? t * 20 : 0))
                .offset(pupilOffset(t, age))
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

    private func happyEye(_ t: Double) -> some View {
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
                    .scaleEffect(sparkle ? 0.75 + 0.35 * CGFloat(max(0, sin(t * 4 + Double(i) * 2))) : 0.2)
                    .rotationEffect(.degrees(t * 40 + Double(i) * 30))
                    .opacity(sparkle ? 1 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.5).delay(Double(i) * 0.08), value: sparkle)
            }
        }
        .onAppear { sparkle = true }
        .onDisappear { sparkle = false }
    }

    private func loveEye(_ t: Double) -> some View {
        let pink = Color(hex: 0xFF5FA2)
        return ZStack {
            EyeOpening(top: 1, bottom: 1, tilt: 0)
                .fill(LinearGradient(colors: [Color(hex: 0x2A1838), Color(hex: 0x120A1C)], startPoint: .top, endPoint: .bottom))
            Image(systemName: "heart.fill")
                .font(.system(size: irisD * 0.62))
                .foregroundStyle(LinearGradient(colors: [pink, Theme.accent3], startPoint: .top, endPoint: .bottom))
                .shadow(color: pink.opacity(0.8), radius: 8)
                .scaleEffect(1 + 0.1 * CGFloat(max(0, sin(t * 5))))
            ForEach(0..<3, id: \.self) { i in
                let p = fmod(t * 0.5 + Double(i) / 3, 1)
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.07))
                    .foregroundStyle(pink.opacity(1 - p))
                    .offset(x: w * (CGFloat(i) - 1) * 0.35, y: -h * (0.4 + 0.5 * CGFloat(p)))
            }
        }
        .frame(width: w, height: h)
        .overlay(EyeOpening(top: 1, bottom: 1, tilt: 0)
            .stroke(LinearGradient(colors: [pink, Theme.accent3], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: max(2, size * 0.024), lineJoin: .round))
            .shadow(color: pink.opacity(0.8), radius: size * 0.05))
    }

    private func dizzyEye(_ t: Double) -> some View {
        ZStack {
            EyeOpening(top: 1, bottom: 1, tilt: 0)
                .fill(LinearGradient(colors: [Color(hex: 0x1C2042), Color(hex: 0x0B0D1D)], startPoint: .top, endPoint: .bottom))
            Path { p in
                let c = CGPoint(x: irisD / 2, y: irisD / 2)
                var first = true
                for k in 0..<180 {
                    let a = Double(k) / 180 * 6 * .pi
                    let r = CGFloat(k) / 180 * irisD * 0.46
                    let pt = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
                    if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                }
            }
            .stroke(Theme.accent3, style: StrokeStyle(lineWidth: max(1.5, size * 0.02), lineCap: .round))
            .frame(width: irisD, height: irisD)
            .rotationEffect(.degrees(t * 240))
        }
        .frame(width: w, height: h)
        .overlay(EyeOpening(top: 1, bottom: 1, tilt: 0)
            .stroke(Theme.brandGradient, style: StrokeStyle(lineWidth: max(2, size * 0.024), lineJoin: .round)))
    }

    // MARK: Life

    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 2.6...5.5) * 1_000_000_000))
            guard [0, 1, 2, 8, 9, 13].contains(mood.kind) else { continue }
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

    /// Natural glances while idle: small saccades, and now and then a slow look around the room.
    private func saccades() async {
        guard mood.kind == EyeMood.idle.kind else {
            if jitter != .zero { jitter = .zero }
            return
        }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.9...2.2) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if Double.random(in: 0...1) < 0.12 {
                // look around: left … right … back
                for x in [-0.2, 0.2, 0.0] {
                    withAnimation(.easeInOut(duration: 0.45)) { jitter = CGSize(width: CGFloat(x) * w, height: -0.04 * h) }
                    try? await Task.sleep(nanoseconds: 520_000_000)
                }
                continue
            }
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
            shakeIt([14, -12, 9, -6, 3, 0])
            if sounds { SoundFX.shared.playError(.general) }
            Haptics.error()
        case .furious:
            shakeIt([18, -16, 14, -12, 10, -8, 6, -4, 2, 0])
            squashIt()
        case .glare:
            Haptics.warning()
        case .happy, .love:
            squashIt()
            if sounds { SoundFX.shared.play(.success, volume: 0.5) }
            Haptics.success()
        case .surprised:
            Haptics.tap(.rigid)
        case .suspicious:
            Haptics.warning()
        case .dizzy:
            Haptics.warning()
        case .lookUp, .reading:
            Haptics.soft(0.35)
        case .idle where old.kind == EyeMood.closed.kind:
            if sounds { SoundFX.shared.play(.eyeOpen, volume: 0.4) }
        default:
            break
        }
    }

    private func shakeIt(_ steps: [CGFloat]) {
        Task {
            for x in steps {
                withAnimation(.easeInOut(duration: 0.045)) { shake = x * size / 150 }
                try? await Task.sleep(nanoseconds: 45_000_000)
            }
        }
    }

    /// A springy squash-and-stretch, like the eye jumps.
    private func squashIt() {
        Task {
            withAnimation(.easeOut(duration: 0.08)) { squash = 0.82 }
            try? await Task.sleep(nanoseconds: 90_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { squash = 1 }
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

/// The app's name as a small badge, built to sit opposite the language button: same height, same
/// capsule, so the top of the screen reads as one balanced row instead of a loose caption.
struct BrandBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Theme.bg.opacity(0.7))
                Circle().strokeBorder(Theme.brandGradient, lineWidth: 1)
                BrandMark(size: 17)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: -1) {
                Text("MNLOVO")
                    .font(Theme.font(12.5, .black))
                    .foregroundStyle(Theme.brandGradient)
                Text("SAVER")
                    .font(Theme.font(8, .heavy))
                    .tracking(3.2)
                    .foregroundStyle(Theme.sub)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 13)
        .frame(height: 36)
        .background(Capsule().fill(Theme.surfaceHi))
        .overlay(Capsule().strokeBorder(Theme.stroke))
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Brand.appName)
    }
}
