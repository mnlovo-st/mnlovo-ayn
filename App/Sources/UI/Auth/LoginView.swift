import SwiftUI

/// Entry: Face ID ➜ password. The 2FA code is only asked after 3 wrong attempts — and the eye gets angry.
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
    @State private var rage = false
    @State private var shakes = 0
    @State private var useRecoveryKey = false
    @State private var recoveryKey = ""
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

            eyeArea

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

            stageControls
            .padding(.horizontal, 24)

            statusArea

            Spacer()

            footerLinks
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: stage)
        .onChange(of: focus) { _, f in
            guard stage == .password, !loading else { return }
            withAnimation { mood = (f == .password) ? .lookUp : .idle }
        }
        .onAppear(perform: start)
        .sheet(isPresented: $showRecovery) { RecoveryView().environmentObject(state) }
    }

    private var eyeArea: some View {
        ZStack {
            if rage {
                Circle().fill(RadialGradient(colors: [Theme.danger.opacity(0.55), .clear], center: .center, startRadius: 10, endRadius: 150))
                    .frame(width: 300, height: 300)
                    .transition(.scale.combined(with: .opacity))
            }
            EyeView(mood: mood, size: 168, sounds: true)
                .modifier(ShakeEffect(shakes: CGFloat(shakes)))
                .onTapGesture { if stage == .face { Task { await faceID() } } }
        }
        .frame(height: 180)
    }

    private var statusArea: some View {
        VStack(spacing: 12) {
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

            if lockedUntil != nil || state.failCount >= 3 {
                SupportButton(prominent: true).padding(.horizontal, 24)
            }
        }
    }

    private var footerLinks: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button { showRecovery = true } label: {
                    Text(tr("نسيت كلمة المرور؟", "Forgot password?"))
                        .font(Theme.font(15, .semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text("·").foregroundStyle(Theme.faint)
                SupportButton()
            }
            Text(Brand.copyright).font(Theme.font(11, .medium)).foregroundStyle(Theme.faint).padding(.bottom, 10)
        }
    }

    private var stageControls: some View {
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
                        Text(tr("استخدم كلمة السر", "Use your password instead"))
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
                codeStage
            }
        }
    }

    private var codeStage: some View {
        VStack(spacing: 14) {
            Label(tr("تحقق إضافي: \(state.failCount) محاولات غلط", "Extra check: \(state.failCount) wrong attempts"),
                  systemImage: "exclamationmark.shield.fill")
                .font(Theme.font(13, .bold)).foregroundStyle(Theme.danger)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(Theme.danger.opacity(0.14)))
            if useRecoveryKey {
                AYNField(title: tr("مفتاح الاسترجاع (٢٤ حرف)", "Recovery key (24 chars)"), icon: "key.horizontal.fill",
                         text: $recoveryKey, focus: $focus, id: .recovery) { Task { await submitRecovery() } }
                    .environment(\.layoutDirection, .leftToRight)
                PrimaryButton(title: tr("تحقق", "Verify"), icon: "checkmark.shield.fill", loading: loading,
                              enabled: PasswordTools.normalizeRecovery(recoveryKey).count == 24) { Task { await submitRecovery() } }
            } else {
                CodeField(code: $code, tint: Theme.danger, autofill: false)
                    .onChange(of: code) { _, v in if v.count == 6 { submitCode() } }
                PrimaryButton(title: tr("تحقق", "Verify"), icon: "checkmark.shield.fill", enabled: code.count == 6) { submitCode() }
            }
            HStack(spacing: 18) {
                Button {
                    withAnimation(.spring) { useRecoveryKey.toggle(); error = nil }
                } label: {
                    Text(useRecoveryKey ? tr("استخدم رمز التحقق", "Use the 2FA code") : tr("ما عندي الرمز؟", "No code?"))
                        .font(Theme.font(14, .semibold)).foregroundStyle(Theme.accent)
                }
                Button {
                    state.cancelPending()
                    withAnimation(.spring) { stage = .password; code = ""; mood = .suspicious(0.6); rage = false }
                } label: {
                    Text(tr("رجوع", "Back")).font(Theme.font(14, .semibold)).foregroundStyle(Theme.sub)
                }
            }
        }
        .transition(.asymmetric(insertion: .scale(scale: 0.8).combined(with: .opacity), removal: .opacity))
    }

    private var caption: String {
        switch stage {
        case .face: return tr("أول شي وجهك، وبعدها كلمة السر.", "First your face, then your password.")
        case .password:
            if state.needsStrongCheck {
                return tr("👁️ العين شاكّة فيك… بعد كلمة السر بنطلب رمز التحقق.", "👁️ The eye is suspicious… after the password we'll ask for the 2FA code.")
            }
            return state.bioPassed
                ? tr("تم التحقق من وجهك ✓ بقيت كلمة السر.", "Face verified ✓ Now your password.")
                : tr("اكتب كلمة السر.", "Enter your password.")
        case .code:
            return useRecoveryKey
                ? tr("اكتب مفتاح الاسترجاع اللي حفظته وقت إنشاء الحساب.", "Enter the recovery key you saved when creating the account.")
                : tr("أثبت إنك أنت: اكتب الرمز من «كلمات السر» تحت MNLOVO SAVER.", "Prove it's you: enter the code from Passwords under MNLOVO SAVER.")
        }
    }

    /// Small chips showing which factors are done.
    private var factors: some View {
        HStack(spacing: 8) {
            if state.canUseBiometrics || state.bioPassed {
                chip(Biometrics.icon, Biometrics.name, done: state.bioPassed, active: stage == .face)
            }
            chip("key.fill", tr("كلمة السر", "Password"), done: stage == .code, active: stage == .password)
            if state.needsStrongCheck || stage == .code {
                chip("lock.rotation", tr("رمز التحقق", "2FA code"), done: false, active: stage == .code)
                    .transition(.scale.combined(with: .opacity))
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
            withAnimation(.easeInOut(duration: 0.8).delay(0.3)) { mood = state.needsStrongCheck ? .suspicious(0.6) : .idle }
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
            password = ""
            await enrage()
        case .wrong:
            withAnimation { mood = .angry }
            withAnimation(.default) { shakes += 1 }
            let left = max(0, 3 - state.failCount)
            error = left > 0
                ? tr("كلمة السر غلط. باقي \(left) قبل التحقق الإضافي.", "Wrong password. \(left) left before the extra check.")
                : tr("كلمة السر غلط. من الحين بنطلب رمز التحقق كمان.", "Wrong password. From now on we'll also ask for the 2FA code.")
            password = ""
            await pause(1.1)
            withAnimation { mood = state.needsStrongCheck ? .suspicious(0.6) : .idle }
        case .lockedOut(let until):
            withAnimation { mood = .angry }
            lockedUntil = until
            error = tr("محاولات كثيرة. انتظر شوي.", "Too many attempts. Please wait.")
            password = ""
        }
    }

    /// The eye gets angry and holds a grudge: red glow, shaking, then the 2FA code slides in.
    private func enrage() async {
        Haptics.error()
        SoundFX.shared.play(.error, volume: 0.6)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { mood = .angry; rage = true }
        for _ in 0..<3 {
            withAnimation(.default) { shakes += 1 }
            Haptics.tap(.heavy)
            await pause(0.18)
        }
        await pause(0.35)
        withAnimation(.easeInOut(duration: 0.5)) { mood = .suspicious(0.6) }
        error = nil
        await pause(0.25)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { stage = .code }
    }

    private func submitCode() {
        guard code.count == 6 else { return }
        if state.verify2FA(code) {
            withAnimation { mood = .happy; rage = false }
        } else {
            withAnimation { mood = .angry }
            withAnimation(.default) { shakes += 1 }
            error = (state.lastCodeProblem ?? .wrongCode).localizedDescription
            code = ""
            if let until = state.lockedUntil { lockedUntil = until }
            Task {
                await pause(1.0)
                withAnimation { mood = .suspicious(0.6) }
            }
        }
    }

    private func submitRecovery() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        withAnimation { mood = .thinking }
        if await state.verifyPendingRecovery(recoveryKey) {
            withAnimation { mood = .happy; rage = false }
        } else {
            withAnimation { mood = .angry }
            withAnimation(.default) { shakes += 1 }
            error = AppError.wrongRecovery.localizedDescription
            recoveryKey = ""
            if let until = state.lockedUntil { lockedUntil = until }
        }
    }
}
