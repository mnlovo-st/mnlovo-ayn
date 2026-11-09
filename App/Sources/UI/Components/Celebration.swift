import SwiftUI

struct Celebration: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var subtitle: String
}

/// Confetti burst + happy eye, shown after creating an account or signing in on a new phone.
struct CelebrationOverlay: View {
    var celebration: Celebration
    var onDone: () -> Void

    @State private var appear = false
    @State private var start = Date()

    var body: some View {
        ZStack {
            Color.black.opacity(appear ? 0.55 : 0).ignoresSafeArea()
            ConfettiBurst(start: start)
            VStack(spacing: 14) {
                EyeView(mood: .happy, size: 150)
                    .scaleEffect(appear ? 1 : 0.3)
                Text(celebration.title)
                    .font(Theme.font(28, .black))
                    .foregroundStyle(Theme.brandGradient)
                    .multilineTextAlignment(.center)
                Text(celebration.subtitle)
                    .font(Theme.font(16, .medium))
                    .foregroundStyle(Theme.text.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(30)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 30)
        }
        .allowsHitTesting(true)
        .onTapGesture { onDone() }
        .task {
            start = Date()
            SoundFX.shared.play(.success, volume: 0.6)
            Haptics.success()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { appear = true }
            await pause(2.6)
            withAnimation(.easeInOut(duration: 0.4)) { appear = false }
            await pause(0.4)
            onDone()
        }
    }
}

struct ConfettiBurst: View {
    var start: Date
    private struct Piece {
        var vx: CGFloat, vy: CGFloat, spin: Double, size: CGSize, color: Color, delay: Double, x0: CGFloat
    }
    @State private var pieces: [Piece] = {
        let colors: [Color] = [Theme.accent, Theme.accent2, Theme.accent3, Theme.ok, Theme.warn, .white]
        return (0..<110).map { i in
            Piece(vx: .random(in: -0.55...0.55), vy: .random(in: -1.25 ... -0.55),
                  spin: .random(in: -9...9),
                  size: CGSize(width: .random(in: 5...10), height: .random(in: 8...16)),
                  color: colors[i % colors.count], delay: .random(in: 0...0.25), x0: .random(in: 0.35...0.65))
        }
    }()

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            Canvas { g, size in
                for p in pieces {
                    let tt = t - p.delay
                    guard tt > 0, tt < 3.2 else { continue }
                    let ft = CGFloat(tt)
                    let x = (p.x0 + p.vx * ft) * size.width
                    let y = size.height * 0.42 + (p.vy * ft + 0.9 * ft * ft) * size.height * 0.5
                    var ctxCopy = g
                    ctxCopy.translateBy(x: x, y: y)
                    ctxCopy.rotate(by: .radians(p.spin * tt))
                    let alpha = max(0, 1 - tt / 3.2)
                    let rect = CGRect(x: -p.size.width / 2, y: -p.size.height / 2, width: p.size.width, height: p.size.height)
                    ctxCopy.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(p.color.opacity(alpha)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
