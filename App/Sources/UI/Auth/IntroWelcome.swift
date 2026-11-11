import SwiftUI

struct IntroView: View {
    var onFinish: () -> Void

    @State private var drawn: CGFloat = 0
    @State private var showEye = false
    @State private var mood: EyeMood = .closed
    @State private var flash = false
    @State private var rings = false
    @State private var letters = 0
    @State private var shimmer: CGFloat = -1.2
    @State private var showSaver = false
    @State private var saverTracking: CGFloat = 2
    @State private var dust = false
    @State private var zoom = false
    @State private var finished = false
    @State private var proud = false
    private let word = Array("MNLOVO")

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color.clear, Color.black.opacity(0.65)], center: .center, startRadius: 120, endRadius: 520)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            StarDust().opacity(dust ? 1 : 0)

            VStack(spacing: 26) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.9), Theme.accent.opacity(0.4), .clear],
                                             center: .center, startRadius: 0, endRadius: 160))
                        .frame(width: 320, height: 320)
                        .scaleEffect(flash ? 1.3 : 0.2)
                        .opacity(flash ? 0 : 0.95)
                    ForEach(0..<3, id: \.self) { i in
                        Circle().stroke(i == 1 ? AnyShapeStyle(Theme.accent.opacity(0.6)) : AnyShapeStyle(Theme.brandGradient), lineWidth: 1.2)
                            .frame(width: 220, height: 220)
                            .scaleEffect(rings ? 1.5 + CGFloat(i) * 0.35 : 0.4)
                            .opacity(rings ? 0 : 0.9)
                            .animation(.easeOut(duration: 1.4 + Double(i) * 0.25).delay(Double(i) * 0.12), value: rings)
                    }
                    EyeOpening(top: 1, bottom: 1, tilt: 0)
                        .trim(from: 0, to: drawn)
                        .stroke(Theme.brandGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 210, height: 126)
                        .shadow(color: Theme.accent.opacity(0.9), radius: 10)
                        .opacity(showEye ? 0 : 1)
                    EyeView(mood: mood, size: 210)
                        .opacity(showEye ? 1 : 0)
                        .scaleEffect(showEye ? 1 : 0.92)
                }
                .frame(height: 210)

                VStack(spacing: 12) {
                    wordmark
                        .overlay {
                            GeometryReader { g in
                                LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: g.size.width * 0.35)
                                    .offset(x: shimmer * g.size.width)
                            }
                            .mask(wordmark)
                            .allowsHitTesting(false)
                        }
                    Text("SAVER")
                        .font(Theme.font(17, .semibold))
                        .tracking(saverTracking)
                        .foregroundStyle(Theme.text.opacity(0.85))
                        .opacity(showSaver ? 1 : 0)
                        .blur(radius: showSaver ? 0 : 6)
                }
                .environment(\.layoutDirection, .leftToRight)

                Spacer()
                Spacer().frame(height: 150)   // room for the footer below
            }
            .scaleEffect(zoom ? 5 : 1)
            .opacity(zoom ? 0 : 1)
            .blur(radius: zoom ? 12 : 0)

            // The footer stays put while the eye flies forward, the way UAE government apps keep
            // the "فخورين بالإمارات" mark steady at the foot of their opening screen.
            VStack(spacing: 14) {
                Spacer()
                Image("ProudUAE")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96)
                    .opacity(proud ? 1 : 0)
                    .offset(y: proud ? 0 : 14)
                    .accessibilityLabel(tr("فخورين بالإمارات", "Proud of UAE"))
                VStack(spacing: 4) {
                    Text(tr("اضغط للتخطي", "Tap to skip")).font(Theme.font(11)).foregroundStyle(Theme.faint)
                    Text(Brand.copyright).font(Theme.font(10, .bold)).foregroundStyle(Theme.faint.opacity(0.8))
                }
                .opacity(dust ? 1 : 0)
            }
            .padding(.bottom, 18)
            .opacity(zoom ? 0 : 1)
            .animation(.easeOut(duration: 0.35), value: zoom)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await run() }
    }

    private var wordmark: some View {
        HStack(spacing: 6) {
            ForEach(0..<word.count, id: \.self) { i in
                Text(String(word[i]))
                    .font(Theme.font(42, .black))
                    .foregroundStyle(Theme.brandGradient)
                    .opacity(i < letters ? 1 : 0)
                    .offset(y: i < letters ? 0 : 20)
                    .blur(radius: i < letters ? 0 : 10)
                    .scaleEffect(i < letters ? 1 : 0.7)
            }
        }
    }

    // Timed to the intro sound: the eye blooms open on the low hit, letters land on the plucks.
    private func run() async {
        SoundFX.shared.play(.intro, volume: 0.75)
        withAnimation(.easeIn(duration: 0.8)) { dust = true }
        withAnimation(.easeInOut(duration: 0.5)) { drawn = 1 }
        await pause(0.5)
        Haptics.tap(.heavy)
        withAnimation(.easeOut(duration: 0.9)) { flash = true }
        rings = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { showEye = true; mood = .surprised }
        await pause(0.22)
        for i in 1...word.count {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.68)) { letters = i }
            if i == 2 { withAnimation(.spring(response: 0.5)) { mood = .idle } }
            Haptics.soft(0.25)
            await pause(0.085)
        }
        withAnimation(.easeInOut(duration: 0.9)) { shimmer = 1.2 }
        withAnimation(.easeOut(duration: 0.9)) { showSaver = true; saverTracking = 10 }
        withAnimation(.easeOut(duration: 0.8).delay(0.2)) { proud = true }
        await pause(0.5)
        withAnimation { mood = .happy }
        await pause(1.15)
        withAnimation(.easeIn(duration: 0.45)) { zoom = true }
        await pause(0.4)
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

/// Slowly drifting specks of light behind the intro.
struct StarDust: View {
    private struct Speck { var x: CGFloat; var y: CGFloat; var r: CGFloat; var speed: CGFloat; var phase: Double }
    @State private var specks: [Speck] = (0..<46).map { _ in
        Speck(x: .random(in: 0...1), y: .random(in: 0...1), r: .random(in: 0.6...2.2),
              speed: .random(in: 0.004...0.016), phase: .random(in: 0...6.28))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                for s in specks {
                    let y = (s.y - CGFloat(t) * s.speed).truncatingRemainder(dividingBy: 1)
                    let yy = (y < 0 ? y + 1 : y) * size.height
                    let xx = s.x * size.width + CGFloat(sin(t * 0.4 + s.phase)) * 8
                    let a = 0.25 + 0.45 * (0.5 + 0.5 * sin(t * 1.3 + s.phase))
                    let rect = CGRect(x: xx - s.r, y: yy - s.r, width: s.r * 2, height: s.r * 2)
                    g.fill(Path(ellipseIn: rect), with: .color(Theme.accent.opacity(a)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct WelcomeView: View {
    @EnvironmentObject var state: AppState
    @State private var showSignUp = false
    @State private var showRestore = false
    @State private var mood: EyeMood = .idle
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                LanguageToggle()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()
            EyeView(mood: mood, size: 170, sounds: false)
                .onTapGesture {
                    Haptics.tap()
                    withAnimation { mood = mood == .happy ? .idle : .happy }
                }
            VStack(spacing: 8) {
                Text(Brand.appName)
                    .font(Theme.font(36, .black))
                    .foregroundStyle(Theme.brandGradient)
                Text(tr("خزنتك الذكية، كل شي مشفّر في تلفونك.", "Your smart vault. Everything encrypted on your iPhone."))
                    .font(Theme.font(16, .medium))
                    .foregroundStyle(Theme.sub)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 14) {
                feature("key.horizontal.fill", tr("حساباتك وكلمات السر ورموز التحقق", "Accounts, passwords & 2FA codes"))
                feature("lock.doc.fill", tr("صور وفيديو وملفات حساسة مشفّرة", "Encrypted photos, videos & files"))
                feature("bell.badge.fill", tr("تذكيرات ذكية ما تخليك تنسى", "Smart reminders that won't let you forget"))
                feature("icloud.fill", tr("نسخ احتياطي تلقائي ومشفّر", "Automatic encrypted backup"))
            }
            .glass(18)
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 20)

            Spacer()

            VStack(spacing: 12) {
                PrimaryButton(title: tr("إنشاء حساب", "Create account"), icon: "sparkles") { showSignUp = true }
                SecondaryButton(title: tr("عندي حساب، تسجيل دخول", "I have an account, sign in"), icon: "person.crop.circle.badge.checkmark") {
                    showRestore = true
                }
                Text(Brand.copyright).font(Theme.font(11, .bold)).foregroundStyle(Theme.faint).padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .onAppear { withAnimation(.spring(response: 0.7).delay(0.2)) { appear = true } }
        .task {
            while !Task.isCancelled {
                await pause(4.0)
                withAnimation { mood = .thinking }
                await pause(1.4)
                withAnimation { mood = .idle }
            }
        }
        .fullScreenCover(isPresented: $showSignUp) { SignUpFlow().environmentObject(state) }
        .sheet(isPresented: $showRestore) { RestoreView().environmentObject(state) }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.12)))
            Text(text).font(Theme.font(15, .semibold)).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
    }
}
