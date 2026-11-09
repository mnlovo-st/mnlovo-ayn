import SwiftUI

struct IntroView: View {
    var onFinish: () -> Void

    @State private var mood: EyeMood = .closed
    @State private var letters = 0
    @State private var showSaver = false
    @State private var showFooter = false
    @State private var ring = false
    @State private var ring2 = false
    @State private var lineWidth: CGFloat = 0
    @State private var finished = false
    private let word = Array("MNLOVO")

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().stroke(Theme.brandGradient, lineWidth: 1.5)
                    .frame(width: 230, height: 230)
                    .scaleEffect(ring ? 1.6 : 0.45)
                    .opacity(ring ? 0 : 0.9)
                Circle().stroke(Theme.accent.opacity(0.5), lineWidth: 1)
                    .frame(width: 230, height: 230)
                    .scaleEffect(ring2 ? 2.0 : 0.45)
                    .opacity(ring2 ? 0 : 0.6)
                EyeView(mood: mood, size: 190)
            }
            .frame(height: 210)

            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(0..<word.count, id: \.self) { i in
                        Text(String(word[i]))
                            .font(Theme.font(40, .black))
                            .foregroundStyle(Theme.brandGradient)
                            .opacity(i < letters ? 1 : 0)
                            .offset(y: i < letters ? 0 : 18)
                            .blur(radius: i < letters ? 0 : 10)
                            .scaleEffect(i < letters ? 1 : 0.85)
                    }
                }
                Capsule()
                    .fill(Theme.brandGradient)
                    .frame(width: lineWidth, height: 2)
                    .shadow(color: Theme.accent.opacity(0.8), radius: 6)
                Text("S A V E R")
                    .font(Theme.font(18, .semibold))
                    .tracking(6)
                    .foregroundStyle(Theme.text.opacity(0.85))
                    .opacity(showSaver ? 1 : 0)
                    .offset(y: showSaver ? 0 : 8)
            }
            .environment(\.layoutDirection, .leftToRight)

            Spacer()
            VStack(spacing: 6) {
                Text(tr("اضغط للتخطي", "Tap to skip")).font(Theme.font(12)).foregroundStyle(Theme.faint)
                Text(Brand.copyright).font(Theme.font(11, .bold)).foregroundStyle(Theme.faint)
            }
            .opacity(showFooter ? 1 : 0)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await run() }
    }

    private func run() async {
        SoundFX.shared.play(.intro, volume: 0.75)
        withAnimation(.easeIn(duration: 0.6)) { showFooter = true }
        await pause(0.5)
        withAnimation(.spring(response: 0.75, dampingFraction: 0.62)) { mood = .surprised }
        Haptics.tap(.heavy)
        withAnimation(.easeOut(duration: 1.4)) { ring = true }
        withAnimation(.easeOut(duration: 1.9).delay(0.15)) { ring2 = true }
        await pause(0.3)
        withAnimation(.spring(response: 0.5)) { mood = .idle }
        for i in 1...word.count {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { letters = i }
            Haptics.soft(0.25)
            await pause(0.085)
        }
        withAnimation(.easeOut(duration: 0.55)) { lineWidth = 150 }
        await pause(0.2)
        withAnimation(.spring(response: 0.6)) { showSaver = true }
        await pause(0.4)
        withAnimation { mood = .happy }
        await pause(0.95)
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
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
