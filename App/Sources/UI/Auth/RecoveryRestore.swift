import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

/// Forgot password: email + phone + birth date + recovery key (+ email code when Supabase is set up).
struct RecoveryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var email = ""
    @State private var phone = ""
    @State private var birth = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var recovery = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var key: SymmetricKey?
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var newRecovery = PasswordTools.recoveryKey()
    @State private var savedCheck = false
    @State private var loading = false
    @State private var error: String?
    @FocusState private var focus: AYNFieldID?

    private let sb = SupabaseClient.shared

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 14) {
                SheetHeader(title: tr("استرجاع الحساب", "Account recovery")) { dismiss() }
                    .padding(.horizontal, 20).padding(.top, 18)
                StepProgress(current: step, total: 4).padding(.horizontal, 20)
                ScrollView {
                    VStack(spacing: 14) {
                        switch step {
                        case 0: identityStep
                        case 1: emailStep
                        case 2: PasswordCreator(password: $newPassword, confirm: $confirm, focus: $focus,
                                                titleFirst: tr("كلمة السر الجديدة", "New password"))
                        default: newKeyStep
                        }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                if let error {
                    Text(error).font(Theme.font(14, .semibold)).foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center).padding(.horizontal, 20)
                }
                PrimaryButton(title: buttonTitle, icon: "arrow.forward", loading: loading, enabled: canContinue) {
                    Task { await next() }
                }
                .padding(.horizontal, 20).padding(.bottom, 12)
            }
        }
        .interactiveDismissDisabled(step > 0)
    }

    private var buttonTitle: String {
        switch step {
        case 0: return tr("تحقق من الهوية", "Verify identity")
        case 1: return tr("تحقق من الكود", "Verify code")
        case 2: return tr("التالي", "Next")
        default: return tr("حفظت المفتاح، افتح الخزنة", "I saved it, open vault")
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0: return isValidEmail(email) && phone.count >= 7 && PasswordTools.normalizeRecovery(recovery).count == 24
        case 1: return code.count >= 6
        case 2: return PasswordCreator.isAcceptable(newPassword, confirm)
        default: return savedCheck
        }
    }

    private var identityStep: some View {
        VStack(spacing: 14) {
            StepHeader(icon: "person.badge.key.fill",
                       title: tr("أثبت إنك صاحب الحساب", "Prove it's your account"),
                       subtitle: tr("لازم كل المعلومات تكون صحيحة. بدونها مستحيل يرجع الحساب.", "Every detail must be correct. Without them the account can't be recovered."))
            AYNField(title: tr("الإيميل", "Email"), icon: "envelope.fill", text: $email, keyboard: .emailAddress,
                     focus: $focus, id: .email) { focus = .phone }
            AYNField(title: tr("رقم الجوال", "Phone"), icon: "phone.fill", text: $phone, keyboard: .phonePad,
                     focus: $focus, id: .phone)
            HStack {
                Image(systemName: "gift.fill").foregroundStyle(Theme.sub).frame(width: 24)
                Text(tr("تاريخ الميلاد", "Date of birth")).font(Theme.font(17, .medium)).foregroundStyle(Theme.sub)
                Spacer()
                DatePicker("", selection: $birth, in: ...Date(), displayedComponents: .date).labelsHidden()
            }
            .padding(.horizontal, 16).frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
            AYNField(title: tr("مفتاح الاسترجاع (٢٤ حرف)", "Recovery key (24 chars)"), icon: "key.horizontal.fill",
                     text: $recovery, focus: $focus, id: .recovery)
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    private var emailStep: some View {
        VStack(spacing: 14) {
            StepHeader(icon: "envelope.badge.shield.half.filled",
                       title: tr("كود الإيميل", "Email code"),
                       subtitle: tr("أرسلنا كود إلى \(email)", "We sent a code to \(email)"))
            CodeField(code: $code, length: 8)
            Button { Task { await sendCode() } } label: {
                Text(tr("إعادة الإرسال", "Resend")).font(Theme.font(14, .semibold)).foregroundStyle(Theme.accent)
            }
        }
        .task { if !codeSent { await sendCode() } }
    }

    private var newKeyStep: some View {
        VStack(spacing: 14) {
            StepHeader(icon: "key.horizontal.fill",
                       title: tr("مفتاح استرجاع جديد", "New recovery key"),
                       subtitle: tr("المفتاح القديم انلغى. احفظ هذا مكانه.", "Your old key no longer works. Save this one instead."))
            RecoveryKeyCard(key: newRecovery)
            Toggle(isOn: $savedCheck) {
                Text(tr("كتبته وحفظته بمكان آمن", "I wrote it down somewhere safe")).font(Theme.font(15, .semibold))
            }
            .tint(Theme.accent).glass(14)
        }
    }

    private func go(_ s: Int) {
        focus = nil
        error = nil
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = s }
    }

    private func sendCode() async {
        do {
            try await sb.sendEmailCode(to: email.trimmingCharacters(in: .whitespaces))
            codeSent = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func next() async {
        loading = true
        defer { loading = false }
        error = nil
        switch step {
        case 0:
            do {
                key = try await state.verifyRecovery(email: email, phone: phone, birth: birth, recoveryKey: recovery)
                FX.success()
                go(sb.isConfigured ? 1 : 2)
            } catch {
                FX.error()
                self.error = error.localizedDescription
            }
        case 1:
            do {
                try await sb.verifyEmailCode(email: email.trimmingCharacters(in: .whitespaces), code: code)
                FX.success()
                go(2)
            } catch {
                FX.error()
                self.error = tr("الكود غلط أو انتهى.", "Wrong or expired code.")
            }
        case 2:
            go(3)
        default:
            guard let key else { return }
            state.busy = tr("نحدّث المفاتيح…", "Updating keys…")
            do {
                try await state.finishRecovery(key: key, newPassword: newPassword, newRecovery: newRecovery)
                state.busy = nil
                state.show(tr("رجع حسابك ✓", "Account recovered ✓"))
            } catch {
                state.busy = nil
                self.error = error.localizedDescription
            }
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
                    PrimaryButton(title: tr("أرسل الكود", "Send code"), icon: "paperplane.fill", loading: loading,
                                  enabled: isValidEmail(email)) { Task { await send() } }
                } else {
                    Text(tr("اكتب الكود اللي وصلك:", "Enter the code you received:")).font(Theme.font(15, .semibold))
                    CodeField(code: $code, length: 8)
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
            state.show(tr("أهلاً من جديد ✓ رجعت بياناتك", "Welcome back ✓ your data is restored"))
            dismiss()
        } catch {
            state.busy = nil
            FX.error()
            self.error = error.localizedDescription
        }
    }
}
