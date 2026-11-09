import SwiftUI

struct IntroView: View {
    var onFinish: () -> Void

    @State private var mood: EyeMood = .closed
    @State private var letters = 0
    @State private var showSub = false
    @State private var ring = false
    @State private var ring2 = false
    @State private var finished = false
    private let word = Array("MNLOVO")

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().stroke(Theme.gradient, lineWidth: 2)
                    .frame(width: 240, height: 240)
                    .scaleEffect(ring ? 1.5 : 0.5)
                    .opacity(ring ? 0 : 0.9)
                Circle().stroke(Theme.accent.opacity(0.6), lineWidth: 1)
                    .frame(width: 240, height: 240)
                    .scaleEffect(ring2 ? 1.9 : 0.5)
                    .opacity(ring2 ? 0 : 0.7)
                EyeView(mood: mood, size: 180)
            }
            .frame(height: 220)

            HStack(spacing: 8) {
                ForEach(0..<word.count, id: \.self) { i in
                    Text(String(word[i]))
                        .font(Theme.font(38, .heavy))
                        .foregroundStyle(Theme.gradient)
                        .opacity(i < letters ? 1 : 0)
                        .offset(y: i < letters ? 0 : 16)
                        .blur(radius: i < letters ? 0 : 8)
                }
            }
            .environment(\.layoutDirection, .leftToRight)

            Text("AYN  ·  عين")
                .font(Theme.font(17, .semibold))
                .tracking(5)
                .foregroundStyle(Theme.sub)
                .opacity(showSub ? 1 : 0)
                .offset(y: showSub ? 0 : 8)
            Spacer()
            Text(tr("اضغط للتخطي", "Tap to skip"))
                .font(Theme.font(12))
                .foregroundStyle(Theme.faint)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await run() }
    }

    private func run() async {
        SoundFX.shared.play(.intro, volume: 0.85)
        await pause(0.55)
        withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { mood = .idle }
        Haptics.tap(.heavy)
        withAnimation(.easeOut(duration: 1.3)) { ring = true }
        withAnimation(.easeOut(duration: 1.8).delay(0.15)) { ring2 = true }
        await pause(0.35)
        for i in 1...word.count {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { letters = i }
            Haptics.soft(0.3)
            await pause(0.08)
        }
        withAnimation(.easeOut(duration: 0.5)) { showSub = true }
        await pause(0.35)
        withAnimation { mood = .happy }
        await pause(0.9)
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
                    FX.tap()
                    withAnimation { mood = mood == .happy ? .idle : .happy }
                }
            VStack(spacing: 8) {
                Text("MNLOVO AYN")
                    .font(Theme.font(36, .heavy))
                    .foregroundStyle(Theme.gradient)
                Text(tr("خزنتك الذكية. كل شي مشفّر على جوالك.", "Your smart vault. Everything encrypted on your iPhone."))
                    .font(Theme.font(16, .medium))
                    .foregroundStyle(Theme.sub)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 14) {
                feature("key.fill", tr("حساباتك وكلمات السر ورموز التحقق", "Accounts, passwords & 2FA codes"))
                feature("lock.doc.fill", tr("صور وفيديو وملفات حساسة مشفّرة", "Encrypted photos, videos & files"))
                feature("bell.badge.fill", tr("تذكيرات ذكية ما تخليك تنسى", "Smart reminders that won't let you forget"))
            }
            .glass(18)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 20)

            Spacer()

            VStack(spacing: 12) {
                PrimaryButton(title: tr("إنشاء حساب", "Create account"), icon: "sparkles") { showSignUp = true }
                SecondaryButton(title: tr("استعادة من نسخة احتياطية", "Restore from backup"), icon: "arrow.clockwise.icloud") {
                    showRestore = true
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .onAppear { withAnimation(.spring(response: 0.7).delay(0.2)) { appear = true } }
        .task {
            while !Task.isCancelled {
                await pause(3.5)
                withAnimation { mood = .thinking }
                await pause(1.6)
                withAnimation { mood = .idle }
            }
        }
        .fullScreenCover(isPresented: $showSignUp) { SignUpFlow().environmentObject(state) }
        .sheet(isPresented: $showRestore) { RestoreView().environmentObject(state) }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.accent.opacity(0.12)))
            Text(text).font(Theme.font(15, .semibold)).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
    }
}
