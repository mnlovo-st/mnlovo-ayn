import SwiftUI

struct LoginView: View {
    @EnvironmentObject var state: AppState
    @State private var password = ""
    @State private var code = ""
    @State private var stage = 0          // 0 = password, 1 = 2FA code
    @State private var mood: EyeMood = .sleepy
    @State private var loading = false
    @State private var error: String?
    @State private var lockedUntil: Date?
    @State private var showRecovery = false
    @State private var triedBiometrics = false
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                LanguageToggle()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 10)

            EyeView(mood: mood, size: 170, sounds: true)
                .onTapGesture { if state.canUseBiometrics { Task { await biometrics() } } }

            VStack(spacing: 6) {
                Text(tr("أهلاً \(state.displayName)", "Welcome back, \(state.displayName)"))
                    .font(Theme.font(28, .heavy))
                    .foregroundStyle(Theme.text)
                Text(stage == 0
                     ? tr("خزنتك مقفلة. افتحها بكلمة السر.", "Your vault is locked. Unlock with your password.")
                     : tr("اكتب رمز التحقق من تطبيق «كلمات السر».", "Enter the code from the Passwords app."))
                    .font(Theme.font(15)).foregroundStyle(Theme.sub)
                    .multilineTextAlignment(.center)
            }

            Group {
                if stage == 0 {
                    VStack(spacing: 14) {
                        AYNField(title: tr("كلمة السر", "Password"), icon: "key.fill", text: $password, secure: true,
                                 contentType: .password, focus: $focus, id: .password) { Task { await submitPassword() } }
                        PrimaryButton(title: tr("دخول", "Unlock"), icon: "lock.open.fill", loading: loading,
                                      enabled: !password.isEmpty && lockedUntil == nil) { Task { await submitPassword() } }
                        if state.canUseBiometrics {
                            SecondaryButton(title: tr("الدخول بـ \(Biometrics.name)", "Use \(Biometrics.name)"), icon: Biometrics.icon) {
                                Task { await biometrics() }
                            }
                        } else if state.biometricsOn && state.fullLoginExpired {
                            Text(tr("للأمان، نطلب كلمة السر ورمز التحقق كل \(state.fullLoginDays) يوم.",
                                    "For safety, password + 2FA are required every \(state.fullLoginDays) days."))
                                .font(Theme.font(12)).foregroundStyle(Theme.faint).multilineTextAlignment(.center)
                        }
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    VStack(spacing: 16) {
                        CodeField(code: $code)
                            .onChange(of: code) { _, v in if v.count == 6 { submitCode() } }
                        PrimaryButton(title: tr("تحقق", "Verify"), icon: "checkmark.shield.fill", enabled: code.count == 6) { submitCode() }
                        Button {
                            withAnimation(.spring) { stage = 0; code = ""; mood = .idle }
                            state.cancelPending()
                        } label: {
                            Text(tr("رجوع", "Back")).font(Theme.font(15, .semibold)).foregroundStyle(Theme.sub)
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
            }

            if let until = lockedUntil {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, Int(until.timeIntervalSince(ctx.date)))
                    Text(tr("مقفل مؤقتاً: \(left) ث", "Locked: \(left)s"))
                        .font(Theme.mono(15, .bold)).foregroundStyle(Theme.warn)
                        .onChange(of: left) { _, v in if v == 0 { lockedUntil = nil; error = nil } }
                }
            }

            Spacer()

            Button { showRecovery = true } label: {
                Text(tr("نسيت كلمة السر؟", "Forgot password?"))
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.bottom, 18)
        }
        .onChange(of: focus) { _, f in
            guard stage == 0, !loading else { return }
            withAnimation { mood = (f == .password) ? .lookUp : .idle }
        }
        .onChange(of: password) { _, _ in FX.key() }
        .onAppear {
            lockedUntil = state.lockedUntil
            withAnimation(.easeInOut(duration: 0.8).delay(0.3)) { mood = .idle }
            if !triedBiometrics && state.canUseBiometrics {
                triedBiometrics = true
                Task { await pause(0.5); await biometrics() }
            }
        }
        .sheet(isPresented: $showRecovery) { RecoveryView().environmentObject(state) }
    }

    private func biometrics() async {
        withAnimation { mood = .thinking }
        let ok = await state.unlockWithBiometrics()
        if !ok { withAnimation { mood = .idle } }
    }

    private func submitPassword() async {
        guard !password.isEmpty, !loading else { return }
        focus = nil
        loading = true
        error = nil
        withAnimation { mood = .thinking }
        let result = await state.unlock(password: password)
        loading = false
        switch result {
        case .needs2FA:
            withAnimation(.spring) { mood = .happy }
            await pause(0.5)
            withAnimation(.spring) { stage = 1; mood = .idle }
            password = ""
        case .wrong:
            withAnimation { mood = .angry }
            error = tr("كلمة السر غلط.", "Wrong password.")
            password = ""
            await pause(1.2)
            withAnimation { mood = .idle }
        case .lockedOut(let until):
            withAnimation { mood = .angry }
            lockedUntil = until
            error = tr("محاولات كثيرة. انتظر شوي.", "Too many attempts. Please wait.")
            password = ""
        }
    }

    private func submitCode() {
        guard code.count == 6 else { return }
        if state.verify2FA(code) {
            withAnimation { mood = .happy }
        } else {
            withAnimation { mood = .angry }
            error = tr("رمز التحقق غلط.", "Wrong verification code.")
            code = ""
            Task {
                await pause(1.0)
                withAnimation { mood = .idle }
            }
        }
    }
}
