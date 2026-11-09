import SwiftUI

/// Animated, looping explanation of the duress password (3 short scenes).
struct DuressExplainer: View {
    @State private var scene = 0
    @State private var dots = 0
    @State private var doorOpen = false
    @State private var realHidden = false

    private var captions: [String] {
        [tr("لو أحد أجبرك تفتح التطبيق…", "If someone forces you to open the app…"),
         tr("تكتب كلمة الطوارئ بدل كلمة السر الحقيقية", "you type the duress password instead of your real one"),
         tr("تنفتح خزنة وهمية فاضية، وخزنتك الحقيقية تبقى مخفية تماماً", "an empty decoy vault opens, and your real vault stays completely hidden")]
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                sceneThreat.opacity(scene == 0 ? 1 : 0).scaleEffect(scene == 0 ? 1 : 0.9)
                sceneTyping.opacity(scene == 1 ? 1 : 0).scaleEffect(scene == 1 ? 1 : 0.9)
                sceneVaults.opacity(scene == 2 ? 1 : 0).scaleEffect(scene == 2 ? 1 : 0.9)
            }
            .frame(height: 150)
            .animation(.spring(response: 0.55, dampingFraction: 0.8), value: scene)

            Text(captions[scene])
                .font(Theme.font(16, .bold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .frame(minHeight: 46)
                .id(scene)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeInOut(duration: 0.35), value: scene)

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i == scene ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surfaceHi))
                        .frame(width: i == scene ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.35), value: scene)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .glass(0, radius: 24, tint: Theme.accent2)
        .task { await loop() }
    }

    private var sceneThreat: some View {
        HStack(spacing: 18) {
            Image(systemName: "figure.stand")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(Theme.danger.opacity(0.9))
            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.faint)
                .environment(\.layoutDirection, .leftToRight)
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Theme.surfaceHi).frame(width: 74, height: 130)
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.stroke))
                EyeView(mood: .surprised, size: 54)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private var sceneTyping: some View {
        VStack(spacing: 14) {
            Image(systemName: "theatermasks.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.gradient)
                .symbolEffect(.bounce, value: scene == 1)
            HStack(spacing: 10) {
                Image(systemName: "key.fill").foregroundStyle(Theme.accent2)
                HStack(spacing: 7) {
                    ForEach(0..<8, id: \.self) { i in
                        Circle().fill(Theme.text).frame(width: 9, height: 9)
                            .scaleEffect(i < dots ? 1 : 0.01)
                            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: dots)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(width: 240, height: 50)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.accent2.opacity(0.7), lineWidth: 1.5))
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    private var sceneVaults: some View {
        HStack(spacing: 22) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Theme.surfaceHi).frame(width: 96, height: 96)
                    Image(systemName: "tray").font(.system(size: 30)).foregroundStyle(Theme.faint)
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [Theme.accent2.opacity(0.9), Theme.accent.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 96, height: 96)
                        .overlay(Image(systemName: "circle.circle").font(.system(size: 30)).foregroundStyle(.white.opacity(0.8)))
                        .rotation3DEffect(.degrees(doorOpen ? -75 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.6)
                }
                Text(tr("الوهمية", "Decoy")).font(Theme.font(12, .bold)).foregroundStyle(Theme.sub)
            }
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Theme.surface).frame(width: 96, height: 96)
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.ok.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    Image(systemName: realHidden ? "eye.slash.fill" : "lock.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.ok)
                        .contentTransition(.symbolEffect(.replace))
                }
                .opacity(realHidden ? 0.45 : 1)
                Text(tr("الحقيقية (مخفية)", "Real (hidden)")).font(Theme.font(12, .bold)).foregroundStyle(Theme.sub)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func loop() async {
        while !Task.isCancelled {
            withAnimation { scene = 0; dots = 0; doorOpen = false; realHidden = false }
            await pause(2.6)
            withAnimation { scene = 1 }
            for i in 1...8 {
                await pause(0.16)
                dots = i
            }
            await pause(1.1)
            withAnimation { scene = 2 }
            await pause(0.4)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { doorOpen = true }
            await pause(0.5)
            withAnimation(.easeInOut(duration: 0.5)) { realHidden = true }
            await pause(2.6)
        }
    }
}
