import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

/// Forgot password, in logical order:
/// 1) email + phone + birth date  2) email code  3) 2FA code + Face ID — or the recovery key  4) new password.
struct RecoveryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    enum Step: Int { case identity, email, factor, password, newKey }
    enum Method { case code, key }

    @State private var step: Step = .identity
    @State private var email = ""
    @State private var phone = ""
    @State private var birth = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var emailCode = ""
    @State private var codeSent = false
    @State private var method: Method = .code
    @State private var totp = ""
    @State private var recovery = ""
    @State private var key: SymmetricKey?
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var newRecovery = PasswordTools.recoveryKey()
    @State private var savedCheck = false
    @State private var loading = false
    @State private var error: String?
    @State private var mood: EyeMood = .idle
    @State private var needsEmailProof = false
    @FocusState private var focus: AYNFieldID?

    private let sb = SupabaseClient.shared
    private var faceAvailable: Bool { SecureEnclaveVault.isEnrolled(.real) && Biometrics.isAvailable }
    private var steps: [Step] {
        var s: [Step] = [.identity]
        if sb.isConfigured { s.append(.email) }
        s += [.factor, .password]
        if method == .key { s.append(.newKey) }
        return s
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 14) {
                SheetHeader(title: tr("نسيت كلمة المرور", "Forgot password")) { dismiss() }
                    .padding(.horizontal, 20).padding(.top, 18)
                StepProgress(current: steps.firstIndex(of: step) ?? 0, total: steps.count).padding(.horizontal, 20)
                ScrollView {
                    VStack(spacing: 14) {
                        EyeView(mood: mood, size: 90, sounds: true)
                        switch step {
                        case .identity: identityStep
                        case .email: emailStep
                        case .factor: factorStep
                        case .password:
                            PasswordCreator(password: $newPassword, confirm: $confirm, focus: $focus,
                                            titleFirst: tr("كلمة المرور الجديدة", "New password"))
                        case .newKey: newKeyStep
                        }
                        if let error {
                            Text(error).font(Theme.font(14, .semibold)).foregroundStyle(Theme.danger)
                                .multilineTextAlignment(.center)
                            SupportButton(prominent: true)
                        }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                PrimaryButton(title: buttonTitle, icon: step == .factor && method == .code ? Biometrics.icon : "arrow.forward",
                              loading: loading, enabled: canContinue) {
                    Task { await next() }
                }
                .padding(.horizontal, 20)
                HStack {
                    Spacer()
                    SupportButton()
                    Spacer()
                }
                .padding(.bottom, 10)
            }
        }
        .interactiveDismissDisabled(step != .identity)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
    }

    private var buttonTitle: String {
        switch step {
        case .identity: return tr("تحقق من الهوية", "Verify identity")
        case .email: return tr("تحقق من الكود", "Verify code")
        case .factor: return method == .code ? tr("تحقق بـ \(Biometrics.name) والرمز", "Verify with \(Biometrics.name) + code") : tr("تحقق من المفتاح", "Verify key")
        case .password: return method == .key ? tr("التالي", "Next") : tr("احفظ وافتح الخزنة", "Save & open vault")
        case .newKey: return tr("حفظت المفتاح، افتح الخزنة", "I saved it, open vault")
        }
    }

    private var canContinue: Bool {
        switch step {
        case .identity: return isValidEmail(email) && PhoneNumber.isValid(phone)
        case .email: return emailCode.count >= 6
        case .factor: return method == .code ? totp.count == 6 : PasswordTools.normalizeRecovery(recovery).count == 24
        case .password: return PasswordCreator.isAcceptable(newPassword, confirm)
        case .newKey: return savedCheck
        }
    }

    private var identityStep: some View {
        VStack(spacing: 14) {
            StepHeader(icon: "person.badge.key.fill",
                       title: tr("أثبت إنك صاحب الحساب", "Prove it's your account"),
                       subtitle: tr("نفس المعلومات اللي سجّلت فيها: الإيميل ورقم الهاتف وتاريخ الميلاد.", "The same details you signed up with: email, phone number and birth date."))
            AYNField(title: tr("الإيميل", "Email"), icon: "envelope.fill", text: $email, keyboard: .emailAddress,
                     contentType: .emailAddress, focus: $focus, id: .email) { focus = .phone }
            PhoneField(full: $phone, focus: $focus)
            HStack {
                Image(systemName: "gift.fill").foregroundStyle(Theme.sub).frame(width: 24)
                Text(tr("تاريخ الميلاد", "Date of birth")).font(Theme.font(17, .medium)).foregroundStyle(Theme.sub)
                Spacer()
                DatePicker("", selection: $birth, in: ...Date(), displayedComponents: .date).labelsHidden()
            }
            .padding(.horizontal, 16).frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
        }
    }

    private var emailStep: some View {
        VStack(spacing: 14) {
            StepHeader(icon: "envelope.badge.shield.half.filled",
                       title: tr("كود الإيميل", "Email code"),
                       subtitle: tr("طرشنا كود إلى \(email)", "We sent a code to \(email)"))
            CodeField(code: $emailCode, length: 8, mail: true)
            Button { Task { await sendCode() } } label: {
                Text(tr("طرشه مرة ثانية", "Resend")).font(Theme.font(14, .semibold)).foregroundStyle(Theme.accent)
            }
        }
        .task { if !codeSent { await sendCode() } }
    }

    private var factorStep: some View {
        VStack(spacing: 14) {
            StepHeader(icon: "lock.rotation",
                       title: tr("الخطوة الأخيرة", "Last step"),
                       subtitle: tr("اختر الطريقة اللي عندك:", "Choose what you have:"))
            methodCard(.code, icon: "lock.rotation", title: tr("رمز التحقق المتغير", "2FA code"),
                       sub: faceAvailable ? tr("من «كلمات السر» + \(Biometrics.name)", "From Passwords + \(Biometrics.name)")
                                          : tr("يحتاج \(Biometrics.name) مفعّل على هالجوال", "Needs \(Biometrics.name) on this iPhone"),
                       enabled: faceAvailable)
            methodCard(.key, icon: "key.horizontal.fill", title: tr("مفتاح الاسترجاع", "Recovery key"),
                       sub: tr("الـ ٦ مجموعات اللي حفظتها وقت إنشاء الحساب", "The 6 groups you saved when you created the account"),
                       enabled: true)
            if method == .code {
                CodeField(code: $totp)
                Text(tr("بعد الرمز بنطلب وجهك عشان نفتح مفتاح الخزنة.", "After the code we'll ask for your face to open the vault key."))
                    .font(Theme.font(12)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
            } else {
                AYNField(title: "XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", icon: "key.horizontal.fill", text: $recovery, focus: $focus, id: .recovery)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .onAppear { if !faceAvailable { method = .key } }
    }

    private func methodCard(_ m: Method, icon: String, title: String, sub: String, enabled: Bool) -> some View {
        Button {
            guard enabled else { return }
            Haptics.selection()
            withAnimation(.spring) { method = m; error = nil }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40).background(Circle().fill(Theme.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                    Text(sub).font(Theme.font(12)).foregroundStyle(Theme.sub)
                }
                Spacer()
                Image(systemName: method == m ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(method == m ? Theme.accent : Theme.faint)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(method == m ? Theme.accent.opacity(0.1) : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(method == m ? Theme.accent.opacity(0.5) : Theme.stroke))
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(PressScale())
    }

    private var newKeyStep: some View {
        VStack(spacing: 14) {
            StepHeader(icon: "key.horizontal.fill",
                       title: tr("مفتاح استرجاع جديد", "New recovery key"),
                       subtitle: tr("استخدمت المفتاح القديم، فسوّينا لك واحد جديد. احفظه مكانه.", "You used your old key, so here's a new one. Save it instead."))
            RecoveryKeyCard(key: newRecovery)
            Toggle(isOn: $savedCheck) {
                Text(tr("كتبته وحفظته بمكان آمن", "I wrote it down somewhere safe")).font(Theme.font(15, .semibold))
            }
            .tint(Theme.accent).glass(14)
        }
    }

    private func go(_ s: Step) {
        focus = nil
        error = nil
        withAnimation { step = s; mood = .idle }
    }

    private func failed(_ e: Error) {
        FX.error()
        error = e.localizedDescription
        withAnimation { mood = .angry }
    }

    private func sendCode() async {
        do {
            try await sb.sendEmailCode(to: email.trimmingCharacters(in: .whitespaces))
            codeSent = true
        } catch { self.error = error.localizedDescription }
    }

    private func next() async {
        loading = true
        defer { loading = false }
        error = nil
        withAnimation { mood = .thinking }
        switch step {
        case .identity:
            do {
                needsEmailProof = try await state.verifyIdentity(email: email, phone: phone, birth: birth)
                FX.success()
                go(sb.isConfigured ? .email : .factor)
            } catch { failed(error) }
        case .email:
            do {
                let session = try await sb.verifyEmailCode(email: email.trimmingCharacters(in: .whitespaces), code: emailCode)
                // Email changed by support: it must be the same cloud account as this vault.
                if needsEmailProof && session.userID != UserDefaults.standard.string(forKey: "cloud.userID") {
                    failed(AppError.identityMismatch)
                    return
                }
                FX.success()
                go(.factor)
            } catch {
                failed(SupabaseClient.SBError.server(tr("الكود غلط أو انتهى.", "Wrong or expired code.")))
            }
        case .factor:
            do {
                key = method == .code ? try await state.recoverWithFaceAndCode(totp) : try await state.recoverWithKey(recovery)
                FX.success()
                withAnimation { mood = .happy }
                go(.password)
            } catch {
                totp = ""
                failed(error)
            }
        case .password:
            if method == .key { go(.newKey) } else { await finish(newKey: nil) }
        case .newKey:
            await finish(newKey: newRecovery)
        }
    }

    private func finish(newKey: String?) async {
        guard let key else { return }
        state.busy = tr("نحدّث المفاتيح…", "Updating keys…")
        do {
            try await state.finishRecovery(key: key, newPassword: newPassword, newRecovery: newKey)
            state.busy = nil
            state.show(tr("رجع حسابك ✓ وتغيّرت كلمة المرور", "Account recovered ✓ Password changed"))
        } catch {
            state.busy = nil
            failed(error)
        }
    }
}

/// Restore a backup from Supabase or from a file (new phone / reinstall).
struct RestoreView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var source = 0     // 0 cloud, 1 file
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var backup: Data?
    @State private var secret = ""
    @State private var loading = false
    @State private var error: String?
    @State private var importing = false
    @State private var showCloudSetup = false
    @FocusState private var focus: AYNFieldID?

    private let sb = SupabaseClient.shared

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 16) {
                    SheetHeader(title: tr("تسجيل الدخول", "Sign in")) { dismiss() }
                    if backup == nil { chooser } else { unlockBackup }
                    if let error {
                        Text(error).font(Theme.font(14, .semibold)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
            if case .success(let url) = result {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let d = try? Data(contentsOf: url) { withAnimation { backup = d } }
                else { error = tr("ما قدرت أقرأ الملف.", "Couldn't read the file.") }
            }
        }
        .sheet(isPresented: $showCloudSetup) { CloudSetupView().environmentObject(state) }
    }

    private var chooser: some View {
        VStack(spacing: 14) {
            Picker("", selection: $source) {
                Text(tr("بإيميلي (السحابة)", "With my email (cloud)")).tag(0)
                Text(tr("من ملف نسخة", "From a backup file")).tag(1)
            }
            .pickerStyle(.segmented)

            if source == 0 {
                if !sb.isConfigured {
                    SecondaryButton(title: tr("إعداد Supabase أولاً", "Set up Supabase first"), icon: "cloud.fill", color: Theme.accent) {
                        showCloudSetup = true
                    }
                } else if !codeSent {
                    AYNField(title: tr("إيميل الحساب", "Account email"), icon: "envelope.fill", text: $email,
                             keyboard: .emailAddress, focus: $focus, id: .email)
                    PrimaryButton(title: tr("طرش الكود", "Send code"), icon: "paperplane.fill", loading: loading,
                                  enabled: isValidEmail(email)) { Task { await send() } }
                } else {
                    Text(tr("اكتب الكود اللي وصلك:", "Enter the code you received:")).font(Theme.font(15, .semibold))
                    CodeField(code: $code, length: 8, mail: true)
                    PrimaryButton(title: tr("تحقق ونزّل بياناتي", "Verify & get my data"), icon: "icloud.and.arrow.down.fill",
                                  loading: loading, enabled: code.count >= 6) { Task { await download() } }
                }
            } else {
                PrimaryButton(title: tr("اختر ملف النسخة (.saver)", "Choose backup file (.saver)"), icon: "folder.fill") { importing = true }
            }
        }
    }

    private var unlockBackup: some View {
        VStack(spacing: 14) {
            EyeView(mood: focus == .password ? .lookUp : .idle, size: 120, sounds: true)
            Text(tr("لقينا بياناتك ✓ اكتب كلمة السر (أو مفتاح الاسترجاع).",
                    "Found your data ✓ Enter your password (or recovery key)."))
                .font(Theme.font(15, .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            AYNField(title: tr("كلمة السر أو مفتاح الاسترجاع", "Password or recovery key"), icon: "key.fill",
                     text: $secret, secure: true, focus: $focus, id: .password)
            if state.hasAccount {
                Label(tr("تنبيه: هذا يستبدل البيانات الموجودة على هذا التلفون.", "Note: this replaces the data on this phone."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.font(13, .semibold)).foregroundStyle(Theme.warn)
            }
            PrimaryButton(title: tr("دخول", "Sign in"), icon: "lock.open.fill", loading: loading, enabled: !secret.isEmpty) {
                Task { await restore() }
            }
        }
    }

    private func send() async {
        loading = true
        defer { loading = false }
        do {
            try await sb.sendEmailCode(to: email.trimmingCharacters(in: .whitespaces))
            withAnimation { codeSent = true }
        } catch { self.error = error.localizedDescription }
    }

    private func download() async {
        loading = true
        defer { loading = false }
        do {
            try await sb.verifyEmailCode(email: email.trimmingCharacters(in: .whitespaces), code: code)
            let d = try await sb.downloadBackup()
            withAnimation { backup = d }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func restore() async {
        guard let backup else { return }
        loading = true
        defer { loading = false }
        state.busy = tr("نفك تشفير النسخة…", "Decrypting backup…")
        do {
            try await state.restore(backup, secret: secret)
            state.busy = nil
            dismiss()
        } catch {
            state.busy = nil
            FX.error()
            self.error = error.localizedDescription
        }
    }
}
