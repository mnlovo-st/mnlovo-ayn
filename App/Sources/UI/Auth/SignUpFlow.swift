import SwiftUI

struct SignUpFlow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var input = NewAccountInput()
    @State private var step = 0
    @State private var wantsLegacy = false
    @State private var confirm = ""
    @State private var emailCode = ""
    @State private var emailSent = false
    @State private var resendIn = 0
    @State private var totpCode = ""
    @State private var totpOK = false
    @State private var recoveryCheck = ""
    @State private var notifications = true
    @State private var intruder = true
    @State private var error: String?
    @State private var loading = false
    @State private var showCloudSetup = false
    @State private var passcodeDone = false
    @State private var duressConfirm = ""
    @State private var phoneHints: [String] = []
    @State private var showPhoneWarning = false
    @FocusState private var focus: AYNFieldID?

    private let totalSteps = 9
    private let sb = SupabaseClient.shared

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    CircleIconButton(icon: step == 0 ? "xmark" : "chevron.backward", size: 38) {
                        if step == 0 { dismiss() } else { go(step - 1) }
                    }
                    StepProgress(current: step, total: totalSteps)
                    Text("\(step + 1)/\(totalSteps)").font(Theme.font(13, .bold)).foregroundStyle(Theme.sub)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                if step == 1 {
                    // Pinned above the form so it stays visible when the keyboard is up.
                    let mood = PasswordCreator.mood(password: input.password, confirm: confirm, focused: focus,
                                                    first: .password, second: .confirm)
                    VStack(spacing: 4) {
                        EyeView(mood: mood, size: 120, sounds: true).frame(height: 96)
                        Text(PasswordCreator.caption(for: mood))
                            .font(Theme.font(14, .semibold)).foregroundStyle(Theme.sub)
                            .contentTransition(.opacity)
                    }
                    .transition(.opacity)
                }

                ScrollView {
                    VStack(spacing: 16) {
                        switch step {
                        case 0: profileStep
                        case 1: passwordStep
                        case 2: emailStep
                        case 3: twoFAStep
                        case 4: passcodeStep
                        case 5: duressStep
                        case 6: recoveryStep
                        case 7: legacyStep
                        default: finalStep
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .scrollDismissesKeyboard(.interactively)

                VStack(spacing: 10) {
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.font(14, .semibold))
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                    if step == 5 && input.duressPassword.isEmpty && duressConfirm.isEmpty {
                        Text(tr("اختياري — تقدر تفعّلها بعدين من الإعدادات", "Optional — you can turn it on later in Settings"))
                            .font(Theme.font(12)).foregroundStyle(Theme.faint)
                    }
                    if step != 4 || passcodeDone {
                        PrimaryButton(title: nextTitle, icon: step == totalSteps - 1 ? "lock.fill" : "arrow.forward",
                                      loading: loading, enabled: canContinue) { next() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showCloudSetup) { CloudSetupView().environmentObject(state) }
        .onChange(of: step) { _, _ in error = nil }
        .confirmationDialog(tr("في حساب ثاني على نفس الرقم", "Another account uses this number"),
                            isPresented: $showPhoneWarning, titleVisibility: .visible) {
            Button(tr("إيه، كمّل", "Yes, continue")) { go(1) }
            Button(tr("لا، رجوع", "No, go back"), role: .cancel) { }
        } message: {
            Text(tr("رقم التلفون هذا مسجّل مع: \(phoneHints.joined(separator: "، ")). تبا تكمّل وتسوي حساب جديد؟",
                    "This number is already linked to: \(phoneHints.joined(separator: ", ")). Continue with a new account?"))
        }
    }

    private var nextTitle: String {
        switch step {
        case 2 where sb.isConfigured && !input.emailVerified: return tr("تحقق من الكود", "Verify code")
        case 3: return tr("تحقق وكمّل", "Verify & continue")
        case 5: return input.duressPassword.isEmpty && duressConfirm.isEmpty ? tr("تخطّي", "Skip") : tr("فعّلها وكمّل", "Turn on & continue")
        case 7: return wantsLegacy ? tr("فعّلها وكمّل", "Turn on & continue") : tr("تخطّي", "Skip")
        case totalSteps - 1: return tr("إنشاء الحساب", "Create account")
        default: return tr("التالي", "Next")
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0:
            return input.username.trimmingCharacters(in: .whitespaces).count >= 2 && isValidEmail(input.email)
                && PhoneNumber.isValid(input.phone)
        case 1: return PasswordCreator.isAcceptable(input.password, confirm)
        case 2: return !sb.isConfigured || input.emailVerified || emailCode.count >= 6
        case 3: return totpCode.count == 6
        case 4: return passcodeDone
        case 5:
            if input.duressPassword.isEmpty && duressConfirm.isEmpty { return true }
            return PasswordCreator.isAcceptable(input.duressPassword, duressConfirm) && input.duressPassword != input.password
        case 6: return PasswordTools.normalizeRecovery(recoveryCheck) == String(PasswordTools.normalizeRecovery(input.recoveryKey).suffix(4))
        default: return true
        }
    }

    private func go(_ s: Int) {
        focus = nil
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = s }
    }

    private func next() {
        error = nil
        switch step {
        case 0:
            // The label carries a short fingerprint so an old entry in Passwords can't be mistaken for this one.
            input.totp.account = "\(input.username.trimmingCharacters(in: .whitespaces)) · \(input.totp.fingerprint)"
            TOTPCarry.save(input.totp)
            Task { await checkRegistry() }
        case 1:
            go(2)
        case 2:
            if sb.isConfigured && !input.emailVerified {
                Task { await verifyEmail() }
            } else {
                go(3)
            }
        case 3:
            if input.totp.verify(totpCode) {
                FX.success()
                totpOK = true
                go(4)
            } else {
                FX.error()
                error = tr("الرمز غلط. تأكد إنك أضفته صح وجرّب الرمز الجديد.", "Wrong code. Make sure it was added correctly and try the new code.")
                totpCode = ""
            }
        case 4:
            go(5)
        case 5:
            go(6)
        case 6:
            go(7)
        case 7:
            go(8)
        default:
            Task { await create() }
        }
    }

    // MARK: Steps

    private var profileStep: some View {
        VStack(spacing: 14) {
            StepHeader(icon: "person.crop.circle.badge.plus",
                       title: tr("خلّنا نتعرف عليك", "Let's get to know you"),
                       subtitle: tr("هذي المعلومات تُستخدم للتحقق منك إذا نسيت كلمة السر.", "Used to verify it's you if you ever forget your password."))
            AYNField(title: tr("اسم المستخدم", "Username"), icon: "person.fill", text: $input.username,
                     contentType: .username, focus: $focus, id: .username) { focus = .email }
            AYNField(title: tr("الإيميل", "Email"), icon: "envelope.fill", text: $input.email,
                     keyboard: .emailAddress, contentType: .emailAddress, focus: $focus, id: .email) { focus = .phone }
            PhoneField(full: $input.phone, focus: $focus)
            HStack {
                Image(systemName: "gift.fill").foregroundStyle(Theme.sub).frame(width: 24)
                Text(tr("تاريخ الميلاد", "Date of birth")).font(Theme.font(17, .medium)).foregroundStyle(Theme.sub)
                Spacer()
                DatePicker("", selection: $input.birthDate, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))

            Label(tr("كل شي يتخزن مشفّر في تلفونك فقط.", "Everything is stored encrypted on your iPhone only."),
                  systemImage: "lock.shield")
                .font(Theme.font(13)).foregroundStyle(Theme.sub)
        }
    }

    private var passwordStep: some View {
        VStack(spacing: 12) {
            Text(tr("أنشئ كلمة السر", "Create your password"))
                .font(Theme.font(26, .heavy)).foregroundStyle(Theme.text)
            PasswordCreator(password: $input.password, confirm: $confirm, focus: $focus, showEye: false)
            Label(tr("ما نقدر نردها لك، بس مفتاح الاسترجاع يقدر.", "We can't recover it for you, only your recovery key can."),
                  systemImage: "info.circle")
                .font(Theme.font(13)).foregroundStyle(Theme.sub)
        }
    }

    private var emailStep: some View {
        VStack(spacing: 16) {
            StepHeader(icon: "envelope.badge.shield.half.filled",
                       title: tr("تأكيد الإيميل", "Verify your email"),
                       subtitle: sb.isConfigured
                           ? tr("طرشنا كود إلى\n\(input.email)", "We sent a code to\n\(input.email)")
                           : tr("التحقق بالإيميل يحتاج إعداد Supabase المجاني (٥ دقايق).", "Email codes need the free Supabase setup (5 minutes)."))
            if sb.isConfigured {
                if input.emailVerified {
                    Label(tr("تم التحقق ✓", "Verified ✓"), systemImage: "checkmark.seal.fill")
                        .font(Theme.font(18, .bold)).foregroundStyle(Theme.ok)
                } else {
                    CodeField(code: $emailCode, length: 8, mail: true)
                    Button {
                        Task { await sendEmail() }
                    } label: {
                        Text(resendIn > 0 ? tr("طرشه مرة ثانية بعد \(resendIn) ث", "Resend in \(resendIn)s") : tr("طرشه مرة ثانية", "Resend code"))
                            .font(Theme.font(14, .semibold))
                            .foregroundStyle(resendIn > 0 ? Theme.faint : Theme.accent)
                    }
                    .disabled(resendIn > 0)
                    Text(tr("الكود يكون ٦ أو ٨ أرقام حسب إعدادك.", "The code is 6 or 8 digits depending on your setup."))
                        .font(Theme.font(12)).foregroundStyle(Theme.faint)
                }
            } else {
                VStack(spacing: 12) {
                    SecondaryButton(title: tr("إعداد Supabase الحين", "Set up Supabase now"), icon: "cloud.fill", color: Theme.accent) {
                        showCloudSetup = true
                    }
                    Text(tr("تقدر تتخطى وتفعّله بعدين من الإعدادات.", "You can skip and enable it later in Settings."))
                        .font(Theme.font(13)).foregroundStyle(Theme.sub)
                }
                .glass()
            }
        }
        .task {
            if sb.isConfigured && !emailSent && !input.emailVerified { await sendEmail() }
        }
    }

    private var twoFAStep: some View {
        VStack(spacing: 16) {
            StepHeader(icon: "lock.rotation",
                       title: tr("التحقق بخطوتين (2FA)", "Two-factor (2FA)"),
                       subtitle: tr("أضف MNLOVO SAVER لتطبيق «كلمات السر» في الآيفون، وكل ٣٠ ثانية يطلع لك رمز جديد", "Add MNLOVO SAVER to the iPhone Passwords app — it will show a new code every 30 seconds."))
            if TOTPCarry.load() != nil {
                Label(tr("إذا أضفت رمز MNLOVO SAVER قبل في «كلمات السر»، استخدم نفس الرمز، ما تحتاج تضيفه مرة ثانية. واحذف أي رمز قديم باسم MNLOVO AYN.",
                         "If you already added MNLOVO SAVER to Passwords, use that same code, no need to add it again. Delete any old MNLOVO AYN entry."),
                      systemImage: "info.circle.fill")
                    .font(Theme.font(13, .medium)).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(12, tint: Theme.accent)
            }
            TwoFactorSetupCard(totp: input.totp)
            Text(tr("اكتب الرمز اللي يطلع لك:", "Enter the code it shows:"))
                .font(Theme.font(15, .semibold)).foregroundStyle(Theme.text)
            CodeField(code: $totpCode)
                .onChange(of: totpCode) { _, v in if v.count == 6 { next() } }
        }
    }

    private var passcodeStep: some View {
        VStack(spacing: 14) {
            if passcodeDone {
                VStack(spacing: 12) {
                    EyeView(mood: .happy, size: 120)
                    Text(tr("رمز الأقسام جاهز ✓", "Section passcode ready ✓")).font(Theme.font(22, .heavy)).foregroundStyle(Theme.text)
                    Text(tr("بيطلبه منك كل ما تفتح «الحسابات» أو «الخزنة».", "You'll enter it whenever you open Accounts or Vault."))
                        .font(Theme.font(14)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
                    Button { withAnimation(.spring) { passcodeDone = false; input.sectionCode = "" } } label: {
                        Text(tr("غيّر الرمز", "Change it")).font(Theme.font(14, .semibold)).foregroundStyle(Theme.accent)
                    }
                }
                .padding(.top, 20)
            } else {
                PasscodeSetupFlow { code, kind in
                    input.sectionCode = code
                    input.sectionKind = kind
                    withAnimation(.spring) { passcodeDone = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { if step == 4 { go(5) } }
                }
            }
        }
    }

    private var duressStep: some View {
        VStack(spacing: 14) {
            StepHeader(icon: "theatermasks.fill",
                       title: tr("كلمة سر الطوارئ", "Duress password"),
                       subtitle: tr("حماية إضافية لو أحد أجبرك تفتح التطبيق.", "Extra protection if someone forces you to open the app."))
            DuressExplainer()
            VStack(alignment: .leading, spacing: 8) {
                Label(tr("بعد Face ID، تكتبها مكان كلمة السر الحقيقية.", "After Face ID, type it instead of your real password."), systemImage: "1.circle.fill")
                Label(tr("تفتح خزنة فاضية تبيّن طبيعية: نفس اسمك ورمز التحقق ورمز الأقسام.", "It opens an empty vault that looks normal: same name, 2FA and section passcode."), systemImage: "2.circle.fill")
                Label(tr("بياناتك الحقيقية ما تبين أبداً، ولا أحد يعرف إن عندك خزنة ثانية.", "Your real data never shows, and nobody can tell a second vault exists."), systemImage: "3.circle.fill")
            }
            .font(Theme.font(13, .medium)).foregroundStyle(Theme.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            PasswordCreator(password: $input.duressPassword, confirm: $duressConfirm, focus: $focus,
                            firstID: .duress, secondID: .duressConfirm,
                            titleFirst: tr("كلمة سر الطوارئ", "Duress password"),
                            titleSecond: tr("أكّدها", "Confirm it"), showEye: false)
            if !input.duressPassword.isEmpty && input.duressPassword == input.password {
                Label(tr("لازم تكون مختلفة عن كلمة السر الأساسية.", "It must differ from your main password."), systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.font(13, .semibold)).foregroundStyle(Theme.danger)
            }
        }
    }

    private var recoveryStep: some View {
        VStack(spacing: 16) {
            StepHeader(icon: "key.horizontal.fill",
                       title: tr("مفتاح الاسترجاع", "Recovery key"),
                       subtitle: tr("اكتبه على ورقة واحفظه بمكان آمن. إذا نسيت كلمة السر تحتاجه مع الإيميل والتلفون وتاريخ الميلاد. بدونه ما يرجع الحساب أبداً.", "Write it on paper and keep it safe. If you forget your password you'll need it with your email, phone and birth date. Without it the account can never be recovered."))
            RecoveryKeyCard(key: input.recoveryKey)
            Text(tr("للتأكيد، اكتب آخر ٤ أحرف (المجموعة ٦):", "To confirm, type the last 4 characters (group 6):"))
                .font(Theme.font(14, .semibold)).foregroundStyle(Theme.text)
            AYNField(title: "XXXX", icon: "checkmark.seal", text: $recoveryCheck, focus: $focus, id: .recovery)
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    /// Introduces the after-death delivery; the actual trustee is picked later, once Telegram is linked.
    private var legacyStep: some View {
        VStack(spacing: 14) {
            StepHeader(icon: "scroll.fill",
                       title: tr("بعد وفاتي", "After I'm gone"),
                       subtitle: tr("لو توفّيت — لا سمح الله — وصيتك وبياناتك ما تضيع. توصل لشخص واحد تختاره أنت، وبعد ما يتأكد التطبيق إنك ما عدت موجود.",
                                    "If you die — God forbid — your will and your data aren't lost. They reach one person you choose, and only after the app has made sure you're gone."))
            LegacyExplainer()
            Toggle(isOn: $wantsLegacy) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("أبيها، ذكّرني أكمّل الإعداد", "I want it — remind me to finish setup"))
                        .font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                    Text(tr("بتختار الأمين والمدة بعد ما تربط تيليجرام.", "You'll pick the trustee and the period after linking Telegram."))
                        .font(Theme.font(12)).foregroundStyle(Theme.sub)
                }
            }
            .tint(Color(hex: 0xFF5FA2))
            .glass(14)
            Text(tr("اختيارية تماماً، وتقدر تشغّلها أو توقفها وقت ما تبا من الإعدادات.",
                    "Completely optional — turn it on or off any time in Settings."))
                .font(Theme.font(12)).foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
        }
    }

    private var finalStep: some View {
        VStack(spacing: 14) {
            StepHeader(icon: "checkmark.shield.fill",
                       title: tr("آخر خطوة", "Last step"),
                       subtitle: tr("فعّل اللي تباه. تقدر تغيّرها بعدين.", "Turn on what you like. You can change these later."))
            toggleRow(icon: Biometrics.icon, title: tr("\(Biometrics.name) + كلمة السر عند الدخول", "\(Biometrics.name) + password to enter"),
                      sub: tr("أقوى حماية. بدونه: كلمة السر + رمز التحقق", "Strongest. Without it: password + 2FA code"),
                      isOn: $input.enableBiometrics)
                .disabled(!Biometrics.isAvailable)
            toggleRow(icon: "bell.badge.fill", title: tr("الإشعارات", "Notifications"),
                      sub: tr("عشان تذكيراتك توصلك", "So your reminders reach you"), isOn: $notifications)
            toggleRow(icon: "camera.metering.spot", title: tr("تصوير المتطفل", "Intruder photo"),
                      sub: tr("من ثاني محاولة خاطئة تلتقط الكاميرا الأمامية صورة", "From the 2nd wrong attempt the front camera takes a photo"),
                      isOn: $intruder)
        }
    }

    private func toggleRow(icon: String, title: String, sub: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.font(16, .semibold)).foregroundStyle(Theme.text)
                Text(sub).font(Theme.font(12)).foregroundStyle(Theme.sub)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.accent)
                .onChange(of: isOn.wrappedValue) { _, _ in FX.toggle() }
        }
        .glass(14)
    }

    // MARK: Actions

    /// One account per email; if the phone already has another account, ask before continuing.
    private func checkRegistry() async {
        loading = true
        let check = await sb.checkSignup(email: input.email.trimmingCharacters(in: .whitespaces), phone: input.phone)
        loading = false
        guard let check else { go(1); return }
        if check.emailTaken {
            FX.error()
            error = tr("هذا الإيميل مسجّل بحساب ثاني. استخدم «عندي حساب، تسجيل دخول» أو إيميل ثاني.",
                       "This email already has an account. Use “I have an account, sign in” or another email.")
            return
        }
        if !check.phoneHints.isEmpty {
            phoneHints = check.phoneHints
            Haptics.warning()
            showPhoneWarning = true
            return
        }
        go(1)
    }

    private func sendEmail() async {
        guard resendIn == 0 else { return }
        do {
            try await sb.sendEmailCode(to: input.email.trimmingCharacters(in: .whitespaces))
            emailSent = true
            state.show(tr("طرشنا الكود ✉️", "Code sent ✉️"), icon: "envelope.fill")
            resendIn = 60
            while resendIn > 0 {
                await pause(1)
                resendIn -= 1
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func verifyEmail() async {
        loading = true
        defer { loading = false }
        do {
            try await sb.verifyEmailCode(email: input.email.trimmingCharacters(in: .whitespaces), code: emailCode)
            input.emailVerified = true
            FX.success()
            await pause(0.4)
            go(3)
        } catch {
            FX.error()
            self.error = tr("الكود غلط أو انتهى.", "Wrong or expired code.") + " " + error.localizedDescription
        }
    }

    private func create() async {
        loading = true
        defer { loading = false }
        if notifications { _ = await ReminderEngine.requestPermission() }
        if intruder { IntruderCam.enabled = await IntruderCam.requestPermission() } else { IntruderCam.enabled = false }
        // The trustee can only be picked once Telegram is linked, so remember the intent.
        UserDefaults.standard.set(wantsLegacy, forKey: "legacy.wanted")
        var n = input
        n.username = n.username.trimmingCharacters(in: .whitespaces)
        n.email = n.email.trimmingCharacters(in: .whitespaces)
        state.busy = tr("نجهّز خزنتك المشفّرة…", "Preparing your encrypted vault…")
        do {
            try await state.createAccount(n)
            state.busy = nil
        } catch {
            state.busy = nil
            self.error = error.localizedDescription
        }
    }
}
