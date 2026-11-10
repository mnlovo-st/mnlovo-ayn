import SwiftUI

/// Entry: Face ID opens the vault; the password is asked every few minutes (or every time without Face ID).
/// After 3 wrong attempts the eye loses its temper and the 2FA code is required too.
struct LoginView: View {
    @EnvironmentObject var state: AppState

    enum Stage { case face, password, code }

    @State private var stage: Stage = .password
    @State private var password = ""
    @State private var code = ""
    @State private var mood: EyeMood = .closed
    @State private var loading = false
    @State private var error: String?
    @State private var note: String?
    @State private var lockedUntil: Date?
    @State private var showRecovery = false
    @State private var started = false
    @State private var rage: CGFloat = 0          // 0…1 red vignette
    @State private var shakes = 0
    @State private var useRecoveryKey = false
    @State private var recoveryKey = ""
    @State private var appear = false
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        ZStack {
            rageVignette
            VStack(spacing: 14) {
                header
                Spacer(minLength: 4)
                eyeArea
                greeting
                FactorSteps(stage: stage, bio: state.canUseBiometrics || state.bioPassed, bioDone: state.bioPassed,
                            needsCode: state.needsStrongCheck || stage == .code)
                stageControls
                    .padding(.horizontal, 22)
                statusArea
                Spacer(minLength: 4)
                footerLinks
            }
            .modifier(ShakeEffect(shakes: CGFloat(shakes)))
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 14)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: stage)
        .onChange(of: focus) { _, f in
            guard stage == .password, !loading, rage == 0 else { return }
            withAnimation { mood = (f == .password) ? .lookUp : (state.needsStrongCheck ? .glare : .idle) }
        }
        .onAppear(perform: start)
        .sheet(isPresented: $showRecovery) { RecoveryView().environmentObject(state) }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 8) {
            BrandMark(size: 28)
            Text(Brand.appName).font(Theme.font(13, .heavy)).foregroundStyle(Theme.sub).tracking(1.5)
            Spacer()
            LanguageToggle()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var eyeArea: some View {
        EyeView(mood: mood, size: 170, sounds: true)
            .onTapGesture { if stage == .face { Task { await faceID() } } }
            .frame(height: 200)
    }

    private var greeting: some View {
        VStack(spacing: 6) {
            Text(timeGreeting + (state.displayName.isEmpty ? "" : tr("، ", ", ") + state.displayName))
                .font(Theme.font(27, .heavy))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text(caption)
                .font(Theme.font(15)).foregroundStyle(rage > 0 ? Theme.danger : Theme.sub)
                .multilineTextAlignment(.center)
                .id(caption)
                .transition(.opacity)
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.3), value: caption)
    }

    private var timeGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return tr("صباح الخير", "Good morning")
        case 12..<18: return tr("هلا والله", "Hey there")
        default: return tr("مساء الخير", "Good evening")
        }
    }

    private var caption: String {
        if rage > 0 && stage != .code { return tr("😠 ٣ محاولات غلط… العين ما صارت تثق فيك", "😠 3 wrong tries… the eye doesn't trust you anymore") }
        switch stage {
        case .face: return tr("بس وجهك، وتدخل.", "Just your face, and you're in.")
        case .password:
            if let note { return note }
            if state.needsStrongCheck {
                return tr("👁️ العين شاكّة فيك… بعد كلمة المرور بنطلب رمز التحقق.", "👁️ The eye is suspicious… after the password we'll ask for the 2FA code.")
            }
            return state.bioPassed ? tr("تم التحقق من وجهك ✓ بقيت كلمة المرور.", "Face verified ✓ Now your password.")
                                   : tr("اكتب كلمة المرور.", "Enter your password.")
        case .code:
            return useRecoveryKey
                ? tr("اكتب مفتاح الاسترجاع اللي حفظته وقت إنشاء الحساب.", "Enter the recovery key you saved when creating the account.")
                : tr("أثبت إنك أنت: الرمز من «كلمات السر» تحت MNLOVO SAVER.", "Prove it's you: the code from Passwords under MNLOVO SAVER.")
        }
    }

    private var stageControls: some View {
        Group {
            switch stage {
            case .face: faceStage
            case .password: passwordStage
            case .code: codeStage
            }
        }
    }

    private var faceStage: some View {
        VStack(spacing: 14) {
            Button { Task { await faceID() } } label: { faceButton }
                .buttonStyle(PressScale())
            Text(tr("افتح بـ \(Biometrics.name)", "Unlock with \(Biometrics.name)"))
                .font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
            Button {
                state.resetBiometricStep()
                withAnimation(.spring) { stage = .password; mood = .idle }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focus = .password }
            } label: {
                Text(tr("استخدم كلمة المرور", "Use your password"))
                    .font(Theme.font(14, .semibold)).foregroundStyle(Theme.sub)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    /// One clean glyph in a soft ring; while scanning a light sweeps across it.
    private var faceButton: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.04)],
                                     center: .center, startRadius: 2, endRadius: 52))
            Circle()
                .strokeBorder(LinearGradient(colors: [Theme.accent.opacity(0.9), Theme.accent2.opacity(0.5)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
            Image(systemName: Biometrics.icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.pulse, isActive: loading)
            if loading {
                TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    LinearGradient(colors: [.clear, Theme.accent.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 2)
                        .offset(y: CGFloat(sin(t * 2.4)) * 30)
                }
                .clipShape(Circle())
            }
        }
        .frame(width: 96, height: 96)
        .shadow(color: Theme.accent.opacity(loading ? 0.5 : 0.28), radius: 20)
    }

    private var passwordStage: some View {
        VStack(spacing: 12) {
            AYNField(title: tr("كلمة المرور", "Password"), icon: "key.fill", text: $password, secure: true,
                     contentType: .password, focus: $focus, id: .password) { Task { await submitPassword() } }
            PrimaryButton(title: tr("دخول", "Unlock"), icon: "lock.open.fill", loading: loading,
                          enabled: !password.isEmpty && lockedUntil == nil) { Task { await submitPassword() } }
        }
        .padding(14)
        .glass(0, radius: 26)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var codeStage: some View {
        VStack(spacing: 12) {
            Label(tr("تحقق إضافي بعد \(state.failCount) محاولات غلط", "Extra check after \(state.failCount) wrong attempts"),
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
                    withAnimation(.spring) { stage = .password; code = ""; mood = .glare; rage = 0 }
                } label: {
                    Text(tr("رجوع", "Back")).font(Theme.font(14, .semibold)).foregroundStyle(Theme.sub)
                }
            }
        }
        .padding(14)
        .glass(0, radius: 26, tint: Theme.danger)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
    }

    private var statusArea: some View {
        VStack(spacing: 10) {
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
                    Label(tr("مقفل مؤقتاً: \(left) ث", "Locked: \(left)s"), systemImage: "hourglass")
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
            HStack(spacing: 14) {
                Button { showRecovery = true } label: {
                    Text(tr("نسيت كلمة المرور؟", "Forgot password?"))
                        .font(Theme.font(14, .semibold)).foregroundStyle(Theme.accent)
                }
                Capsule().fill(Theme.stroke).frame(width: 1, height: 14)
                SupportButton()
            }
            .padding(.horizontal, 16).frame(height: 38)
            .background(Capsule().fill(Theme.surface))
            Text(Brand.copyright).font(Theme.font(11, .medium)).foregroundStyle(Theme.faint).padding(.bottom, 8)
        }
    }

    /// Red edges that pulse while the eye is furious.
    private var rageVignette: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: rage == 0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let beat = 0.65 + 0.35 * max(0, sin(t * 7.5))
            RadialGradient(colors: [.clear, Theme.danger.opacity(0.55 * Double(rage) * beat)],
                           center: .center, startRadius: 160, endRadius: 560)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    // MARK: Flow

    private func start() {
        lockedUntil = state.lockedUntil
        withAnimation(.spring(response: 0.7).delay(0.1)) { appear = true }
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
            withAnimation(.easeInOut(duration: 0.8).delay(0.3)) { mood = state.needsStrongCheck ? .glare : .idle }
        }
    }

    private func faceID() async {
        guard !loading else { return }
        loading = true
        withAnimation { mood = .scanning }
        let ok = await state.biometricStep()
        loading = false
        if ok {
            if state.unlockWithFace() {
                withAnimation { mood = .happy }
                return
            }
            withAnimation { mood = .happy }
            await pause(0.5)
            note = state.needsStrongCheck ? nil
                : (state.passwordEvery == 0
                    ? tr("تم التحقق من وجهك ✓ وإعداداتك تطلب كلمة المرور كل مرة.", "Face verified ✓ Your settings ask for the password every time.")
                    : tr("تم التحقق من وجهك ✓ مرّ وقت من آخر مرة، اكتب كلمة المرور.", "Face verified ✓ It's been a while — enter your password."))
            withAnimation(.spring) { stage = .password; mood = state.needsStrongCheck ? .glare : .idle }
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
            FX.error(.password)
            withAnimation { mood = .angry }
            withAnimation(.default) { shakes += 1 }
            let left = max(0, 3 - state.failCount)
            error = left > 0
                ? tr("كلمة المرور غلط. باقي \(left) قبل التحقق الإضافي.", "Wrong password. \(left) left before the extra check.")
                : tr("كلمة المرور غلط. من الحين بنطلب رمز التحقق بعد.", "Wrong password. From now on we'll also ask for the 2FA code.")
            password = ""
            await pause(1.1)
            withAnimation { mood = state.needsStrongCheck ? .glare : .idle }
        case .lockedOut(let until):
            FX.error(.lockout)
            withAnimation { mood = .dizzy }
            lockedUntil = until
            error = tr("محاولات كثيرة. انتظر شوي.", "Too many attempts. Please wait.")
            password = ""
        }
    }

    /// The eye loses its temper: a startled pop, then fury with a heartbeat and red edges,
    /// and finally a cold glare while the 2FA code slides in.
    private func enrage() async {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { mood = .surprised }
        Haptics.tap(.rigid)
        await pause(0.32)
        SoundFX.shared.playError(.anger)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { mood = .furious; rage = 1; error = nil }
        // heartbeat haptics in time with the sound (thump-thump … thump-thump)
        for d in [0.0, 0.24, 0.58, 0.24] {
            await pause(d)
            Haptics.tap(.heavy)
            if d == 0 || d == 0.58 { withAnimation(.default) { shakes += 1 } }
        }
        await pause(0.7)
        withAnimation(.easeInOut(duration: 0.6)) { mood = .glare; rage = 0.45 }
        await pause(0.3)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { stage = .code }
        await pause(1.2)
        withAnimation(.easeOut(duration: 1.2)) { rage = 0.25 }
    }

    private func submitCode() {
        guard code.count == 6 else { return }
        if state.verify2FA(code) {
            withAnimation { mood = .happy; rage = 0 }
        } else {
            FX.error(.code)
            withAnimation { mood = .furious }
            withAnimation(.default) { shakes += 1 }
            error = (state.lastCodeProblem ?? .wrongCode).localizedDescription
            code = ""
            if let until = state.lockedUntil { lockedUntil = until }
            Task {
                await pause(1.0)
                withAnimation { mood = .glare }
            }
        }
    }

    private func submitRecovery() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        withAnimation { mood = .thinking }
        if await state.verifyPendingRecovery(recoveryKey) {
            withAnimation { mood = .happy; rage = 0 }
        } else {
            FX.error(.code)
            withAnimation { mood = .furious }
            withAnimation(.default) { shakes += 1 }
            error = AppError.wrongRecovery.localizedDescription
            recoveryKey = ""
            if let until = state.lockedUntil { lockedUntil = until }
        }
    }
}

// MARK: - Login decorations

/// Small stepper showing which factors are needed and done.
struct FactorSteps: View {
    var stage: LoginView.Stage
    var bio: Bool
    var bioDone: Bool
    var needsCode: Bool

    var body: some View {
        HStack(spacing: 6) {
            if bio {
                step(Biometrics.icon, Biometrics.name, done: bioDone, active: stage == .face)
                connector(done: bioDone)
            }
            step("key.fill", tr("كلمة المرور", "Password"), done: stage == .code, active: stage == .password)
            if needsCode {
                connector(done: stage == .code)
                step("lock.rotation", tr("رمز التحقق", "2FA code"), done: false, active: stage == .code, danger: true)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4), value: needsCode)
        .animation(.spring(response: 0.4), value: stage)
    }

    private func connector(done: Bool) -> some View {
        Capsule().fill(done ? Theme.ok : Theme.stroke).frame(width: 16, height: 2)
    }

    private func step(_ icon: String, _ title: String, done: Bool, active: Bool, danger: Bool = false) -> some View {
        let color: Color = done ? Theme.ok : (active ? (danger ? Theme.danger : Theme.text) : Theme.faint)
        let fill: Color = done ? Theme.ok.opacity(0.14) : (active ? (danger ? Theme.danger.opacity(0.14) : Theme.surfaceHi) : Theme.surface)
        let border: Color = active ? (danger ? Theme.danger.opacity(0.6) : Theme.accent.opacity(0.5)) : .clear
        return HStack(spacing: 5) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
            Text(title)
        }
        .font(Theme.font(12, .bold))
        .foregroundStyle(color)
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(border))
    }
}
