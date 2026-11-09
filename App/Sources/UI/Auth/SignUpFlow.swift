import SwiftUI

struct SignUpFlow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var input = NewAccountInput()
    @State private var step = 0
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
    @FocusState private var focus: AYNFieldID?

    private let totalSteps = 6
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

                ScrollView {
                    VStack(spacing: 16) {
                        switch step {
                        case 0: profileStep
                        case 1: passwordStep
                        case 2: emailStep
                        case 3: twoFAStep
                        case 4: recoveryStep
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
                    PrimaryButton(title: nextTitle, icon: step == totalSteps - 1 ? "lock.fill" : "arrow.forward",
                                  loading: loading, enabled: canContinue) { next() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showCloudSetup) { CloudSetupView().environmentObject(state) }
        .onChange(of: step) { _, _ in error = nil }
    }

    private var nextTitle: String {
        switch step {
        case 2 where sb.isConfigured && !input.emailVerified: return tr("تحقق من الكود", "Verify code")
        case 3: return tr("تحقق وكمّل", "Verify & continue")
        case totalSteps - 1: return tr("إنشاء الحساب", "Create account")
        default: return tr("التالي", "Next")
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0:
            return input.username.trimmingCharacters(in: .whitespaces).count >= 2 && isValidEmail(input.email)
                && TOTP.westernDigits(input.phone).filter { $0.isASCII && $0.isNumber }.count >= 7
        case 1: return PasswordCreator.isAcceptable(input.password, confirm)
        case 2: return !sb.isConfigured || input.emailVerified || emailCode.count >= 6
        case 3: return totpCode.count == 6
        case 4: return PasswordTools.normalizeRecovery(recoveryCheck) == String(PasswordTools.normalizeRecovery(input.recoveryKey).suffix(4))
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
            input.totp.account = input.username.trimmingCharacters(in: .whitespaces)
            go(1)
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
            AYNField(title: tr("رقم التلفون", "Phone number"), icon: "phone.fill", text: $input.phone,
                     keyboard: .phonePad, contentType: .telephoneNumber, focus: $focus, id: .phone)
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
            PasswordCreator(password: $input.password, confirm: $confirm, focus: $focus)
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
                           ? tr("أرسلنا كود إلى\n\(input.email)", "We sent a code to\n\(input.email)")
                           : tr("التحقق بالإيميل يحتاج إعداد Supabase المجاني (٥ دقايق).", "Email codes need the free Supabase setup (5 minutes)."))
            if sb.isConfigured {
                if input.emailVerified {
                    Label(tr("تم التحقق ✓", "Verified ✓"), systemImage: "checkmark.seal.fill")
                        .font(Theme.font(18, .bold)).foregroundStyle(Theme.ok)
                } else {
                    CodeField(code: $emailCode, length: 8)
                    Button {
                        Task { await sendEmail() }
                    } label: {
                        Text(resendIn > 0 ? tr("إعادة الإرسال بعد \(resendIn) ث", "Resend in \(resendIn)s") : tr("إعادة إرسال الكود", "Resend code"))
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
            TwoFactorSetupCard(totp: input.totp)
            Text(tr("اكتب الرمز اللي يطلع لك:", "Enter the code it shows:"))
                .font(Theme.font(15, .semibold)).foregroundStyle(Theme.text)
            CodeField(code: $totpCode)
                .onChange(of: totpCode) { _, v in if v.count == 6 { next() } }
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

    private var finalStep: some View {
        VStack(spacing: 14) {
            StepHeader(icon: "checkmark.shield.fill",
                       title: tr("آخر خطوة", "Last step"),
                       subtitle: tr("فعّل اللي تبيه. تقدر تغيّرها بعدين.", "Turn on what you like. You can change these later."))
            toggleRow(icon: Biometrics.icon, title: tr("\(Biometrics.name) + كلمة السر عند الدخول", "\(Biometrics.name) + password to enter"),
                      sub: tr("أقوى حماية. بدونه: كلمة السر + رمز التحقق", "Strongest. Without it: password + 2FA code"),
                      isOn: $input.enableBiometrics)
                .disabled(!Biometrics.isAvailable)
            toggleRow(icon: "bell.badge.fill", title: tr("الإشعارات", "Notifications"),
                      sub: tr("عشان تذكيراتك توصلك", "So your reminders reach you"), isOn: $notifications)
            toggleRow(icon: "camera.metering.spot", title: tr("تصوير المتطفل", "Intruder photo"),
                      sub: tr("بعد ٣ محاولات خاطئة تلتقط الكاميرا الأمامية صورة", "After 3 wrong attempts the front camera takes a photo"),
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

    private func sendEmail() async {
        guard resendIn == 0 else { return }
        do {
            try await sb.sendEmailCode(to: input.email.trimmingCharacters(in: .whitespaces))
            emailSent = true
            state.show(tr("أرسلنا الكود ✉️", "Code sent ✉️"), icon: "envelope.fill")
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
        var n = input
        n.username = n.username.trimmingCharacters(in: .whitespaces)
        n.email = n.email.trimmingCharacters(in: .whitespaces)
        state.busy = tr("نجهّز خزنتك المشفّرة…", "Preparing your encrypted vault…")
        do {
            try await state.createAccount(n)
            state.busy = nil
            state.show(tr("أهلاً \(n.username)! خزنتك جاهزة 🎉", "Welcome \(n.username)! Your vault is ready 🎉"), icon: "sparkles")
        } catch {
            state.busy = nil
            self.error = error.localizedDescription
        }
    }
}
