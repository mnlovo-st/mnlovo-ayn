import SwiftUI

/// Entry: Face ID ➜ password. Without Face ID (or if it fails): password ➜ 2FA code.
struct LoginView: View {
    @EnvironmentObject var state: AppState

    enum Stage { case face, password, code }

    @State private var stage: Stage = .password
    @State private var password = ""
    @State private var code = ""
    @State private var mood: EyeMood = .closed
    @State private var loading = false
    @State private var error: String?
    @State private var lockedUntil: Date?
    @State private var showRecovery = false
    @State private var started = false
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                BrandMark(size: 30)
                Text(Brand.appName).font(Theme.font(14, .heavy)).foregroundStyle(Theme.sub).tracking(1.5)
                Spacer()
                LanguageToggle()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 6)

            EyeView(mood: mood, size: 168, sounds: true)
                .onTapGesture { if stage == .face { Task { await faceID() } } }

            VStack(spacing: 6) {
                Text(tr("أهلاً \(state.displayName)", "Welcome back, \(state.displayName)"))
                    .font(Theme.font(28, .heavy))
                    .foregroundStyle(Theme.text)
                Text(caption)
                    .font(Theme.font(15)).foregroundStyle(Theme.sub)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 24)

            factors

            Group {
                switch stage {
                case .face:
                    VStack(spacing: 12) {
                        PrimaryButton(title: tr("افتح بـ \(Biometrics.name)", "Unlock with \(Biometrics.name)"), icon: Biometrics.icon,
                                      loading: loading) { Task { await faceID() } }
                        Button {
                            state.resetBiometricStep()
                            withAnimation(.spring) { stage = .password; mood = .idle }
                        } label: {
                            Text(tr("استخدم كلمة السر ورمز التحقق", "Use password + 2FA code instead"))
                                .font(Theme.font(14, .semibold)).foregroundStyle(Theme.sub)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                case .password:
                    VStack(spacing: 14) {
                        AYNField(title: tr("كلمة السر", "Password"), icon: "key.fill", text: $password, secure: true,
                                 contentType: .password, focus: $focus, id: .password) { Task { await submitPassword() } }
                        PrimaryButton(title: tr("دخول", "Unlock"), icon: "lock.open.fill", loading: loading,
                                      enabled: !password.isEmpty && lockedUntil == nil) { Task { await submitPassword() } }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                case .code:
                    VStack(spacing: 16) {
                        CodeField(code: $code)
                            .onChange(of: code) { _, v in if v.count == 6 { submitCode() } }
                        PrimaryButton(title: tr("تحقق", "Verify"), icon: "checkmark.shield.fill", enabled: code.count == 6) { submitCode() }
                        Button {
                            state.cancelPending()
                            withAnimation(.spring) { stage = .password; code = ""; mood = .idle }
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
                    .transition(.opacity)
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
            Text(Brand.copyright).font(Theme.font(11, .medium)).foregroundStyle(Theme.faint).padding(.bottom, 10)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: stage)
        .onChange(of: focus) { _, f in
            guard stage == .password, !loading else { return }
            withAnimation { mood = (f == .password) ? .lookUp : .idle }
        }
        .onAppear(perform: start)
        .sheet(isPresented: $showRecovery) { RecoveryView().environmentObject(state) }
    }

    private var caption: String {
        switch stage {
        case .face: return tr("أول شي وجهك، وبعدها كلمة السر.", "First your face, then your password.")
        case .password:
            return state.bioPassed
                ? tr("تم التحقق من وجهك ✓ بقيت كلمة السر.", "Face verified ✓ Now your password.")
                : tr("اكتب كلمة السر، وبعدها رمز التحقق.", "Enter your password, then your 2FA code.")
        case .code: return tr("اكتب الرمز من تطبيق «كلمات السر».", "Enter the code from the Passwords app.")
        }
    }

    /// Small chips showing which factors are done.
    private var factors: some View {
        HStack(spacing: 8) {
            if state.canUseBiometrics || state.bioPassed {
                chip(Biometrics.icon, Biometrics.name, done: state.bioPassed, active: stage == .face)
            }
            chip("key.fill", tr("كلمة السر", "Password"), done: stage == .code, active: stage == .password)
            if !state.bioPassed {
                chip("lock.rotation", tr("رمز التحقق", "2FA code"), done: false, active: stage == .code)
            }
        }
    }

    private func chip(_ icon: String, _ title: String, done: Bool, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
            Text(title)
        }
        .font(Theme.font(12, .bold))
        .foregroundStyle(done ? Theme.ok : (active ? Theme.text : Theme.faint))
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(done ? Theme.ok.opacity(0.14) : (active ? Theme.surfaceHi : Theme.surface)))
        .overlay(Capsule().strokeBorder(active ? Theme.accent.opacity(0.5) : .clear))
        .animation(.spring(response: 0.35), value: done)
    }

    private func start() {
        lockedUntil = state.lockedUntil
        guard !started else { return }
        started = true
        if state.canUseBiometrics && !state.bioPassed {
            stage = .face
            Task {
                await pause(0.35)
                withAnimation(.spring(response: 0.6)) { mood = .idle }
                await pause(0.25)
                await faceID()
            }
        } else {
            stage = .password
            withAnimation(.easeInOut(duration: 0.8).delay(0.3)) { mood = .idle }
        }
    }

    private func faceID() async {
        guard !loading else { return }
        loading = true
        withAnimation { mood = .scanning }
        let ok = await state.biometricStep()
        loading = false
        if ok {
            withAnimation { mood = .happy }
            await pause(0.55)
            withAnimation(.spring) { stage = .password; mood = .idle }
            await pause(0.15)
            focus = .password
        } else {
            withAnimation { mood = .sleepy }
            if !state.canUseBiometrics { withAnimation(.spring) { stage = .password; mood = .idle } }
        }
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
        case .unlocked:
            withAnimation { mood = .happy }
            password = ""
        case .needs2FA:
            withAnimation(.spring) { mood = .happy }
            await pause(0.45)
            withAnimation(.spring) { stage = .code; mood = .idle }
            password = ""
        case .wrong:
            withAnimation { mood = .angry }
            error = tr("كلمة السر غلط.", "Wrong password.")
            password = ""
            await pause(1.1)
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
