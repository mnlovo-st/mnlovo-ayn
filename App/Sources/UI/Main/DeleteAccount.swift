import SwiftUI

/// Deleting the account takes six deliberate steps so it can't happen by accident or under pressure in a hurry.
struct DeleteAccountSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var countdown = 6
    @State private var phrase = ""
    @State private var password = ""
    @State private var code = ""
    @State private var useRecovery = false
    @State private var recovery = ""
    @State private var includeCloud = true
    @State private var hold: CGFloat = 0
    @State private var holding = false
    @State private var busy = false
    @State private var error: String?
    @State private var mood: EyeMood = .surprised
    @State private var shakes = 0
    @FocusState private var focus: AYNFieldID?

    private let total = 6
    private var expected: String { tr("احذف حسابي نهائياً", "DELETE MY ACCOUNT") }

    var body: some View {
        ZStack {
            AuroraBackground()
            LinearGradient(colors: [Theme.danger.opacity(0.22), .clear], startPoint: .top, endPoint: .center).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    SheetHeader(title: tr("حذف الحساب", "Delete account")) { dismiss() }
                    StepProgress(current: step, total: total)
                    EyeView(mood: mood, size: 110, sounds: true)
                        .modifier(ShakeEffect(shakes: CGFloat(shakes)))
                    Group {
                        switch step {
                        case 0: warning
                        case 1: phraseStep
                        case 2: passwordStep
                        case 3: codeStep
                        case 4: faceStep
                        default: holdStep
                        }
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.font(14, .semibold)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
                    }
                    SupportButton()
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .interactiveDismissDisabled(step > 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
    }

    // MARK: Steps

    private var warning: some View {
        VStack(spacing: 14) {
            Text(tr("متأكد؟ هذا قرار ما ينرد", "Are you sure? There's no undo"))
                .font(Theme.font(24, .black)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                bullet("key.horizontal.fill", tr("كل حساباتك وكلمات السر", "All your accounts and passwords"))
                bullet("photo.stack.fill", tr("كل الصور والفيديو والملفات المشفّرة", "All encrypted photos, videos and files"))
                bullet("bell.slash.fill", tr("كل التذكيرات والملاحظات", "All reminders and notes"))
                bullet("icloud.slash.fill", tr("نسختك في السحابة (إذا اخترت)", "Your cloud copy (if you choose)"))
                bullet("paperplane", tr("ربط تيليجرام", "Telegram links"))
            }
            .glass(14, tint: Theme.danger)
            Text(tr("حتى الدعم الفني ما يقدر يرجّعها لك بعدين.", "Not even support can bring it back afterwards."))
                .font(Theme.font(14, .bold)).foregroundStyle(Theme.text)
            dangerButton(countdown > 0 ? tr("انتظر \(countdown)…", "Wait \(countdown)…") : tr("فاهم، كمّل", "I understand, continue"),
                         enabled: countdown == 0) { go(1) }
        }
        .task {
            countdown = 6
            while countdown > 0 { await pause(1); countdown -= 1 }
        }
    }

    private var phraseStep: some View {
        VStack(spacing: 14) {
            Text(tr("اكتب الجملة هذي بالضبط:", "Type this exactly:")).font(Theme.font(16, .bold)).foregroundStyle(Theme.text)
            Text(expected).font(Theme.font(22, .black)).foregroundStyle(Theme.danger)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.danger.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            AYNField(title: tr("اكتبها هنا", "Type it here"), icon: "character.cursor.ibeam", text: $phrase, focus: $focus, id: .title)
            dangerButton(tr("التالي", "Next"), enabled: normalized(phrase) == normalized(expected)) { go(2) }
        }
        .onChange(of: phrase) { _, v in withAnimation { mood = normalized(v) == normalized(expected) ? .angry : .suspicious(0.6) } }
    }

    private var passwordStep: some View {
        VStack(spacing: 14) {
            Text(tr("كلمة سر الحساب", "Account password")).font(Theme.font(18, .heavy)).foregroundStyle(Theme.text)
            AYNField(title: tr("كلمة السر", "Password"), icon: "key.fill", text: $password, secure: true,
                     contentType: .password, focus: $focus, id: .password) { Task { await checkPassword() } }
            dangerButton(tr("تحقق", "Verify"), enabled: !password.isEmpty, loading: busy) { Task { await checkPassword() } }
        }
        .onChange(of: focus) { _, f in withAnimation { mood = f == .password ? .lookUp : .suspicious(0.6) } }
    }

    private var codeStep: some View {
        VStack(spacing: 14) {
            Text(useRecovery ? tr("مفتاح الاسترجاع", "Recovery key") : tr("رمز التحقق المتغير", "2FA code"))
                .font(Theme.font(18, .heavy)).foregroundStyle(Theme.text)
            if useRecovery {
                AYNField(title: tr("مفتاح الاسترجاع (٢٤ حرف)", "Recovery key (24 chars)"), icon: "key.horizontal.fill",
                         text: $recovery, focus: $focus, id: .recovery)
                    .environment(\.layoutDirection, .leftToRight)
                dangerButton(tr("تحقق", "Verify"), enabled: PasswordTools.normalizeRecovery(recovery).count == 24, loading: busy) {
                    Task { await checkRecovery() }
                }
            } else {
                Text(tr("من تطبيق «كلمات السر» تحت اسم MNLOVO SAVER", "From the Passwords app under MNLOVO SAVER"))
                    .font(Theme.font(13)).foregroundStyle(Theme.sub)
                CodeField(code: $code, tint: Theme.danger)
                    .onChange(of: code) { _, v in if v.count == 6 { checkCode() } }
            }
            Button(useRecovery ? tr("استخدم رمز التحقق", "Use the 2FA code") : tr("ما عندي الرمز؟ استخدم مفتاح الاسترجاع", "No code? Use the recovery key")) {
                withAnimation { useRecovery.toggle(); error = nil }
            }
            .font(Theme.font(14, .semibold)).foregroundStyle(Theme.accent)
        }
    }

    private var faceStep: some View {
        VStack(spacing: 14) {
            Text(tr("وأخيراً… وجهك", "Finally… your face")).font(Theme.font(18, .heavy)).foregroundStyle(Theme.text)
            dangerButton(tr("تحقق بـ \(Biometrics.name)", "Verify with \(Biometrics.name)"), enabled: true, loading: busy) { Task { await face() } }
        }
        .task { await face() }
    }

    private var holdStep: some View {
        VStack(spacing: 16) {
            Toggle(isOn: $includeCloud) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("احذف نسختي من السحابة بعد", "Also delete my cloud copy")).font(Theme.font(15, .semibold))
                    Text(tr("والإيميل وروابط تيليجرام من السيرفر", "Plus the email and Telegram links on the server")).font(Theme.font(12)).foregroundStyle(Theme.sub)
                }
            }
            .tint(Theme.danger).glass(14)
            Text(tr("اضغط مطوّلاً ٣ ثواني عشان تحذف", "Press and hold for 3 seconds to delete"))
                .font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
            ZStack {
                Circle().stroke(Theme.surfaceHi, lineWidth: 10)
                Circle().trim(from: 0, to: hold)
                    .stroke(Theme.danger, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.danger.opacity(0.8), radius: holding ? 14 : 0)
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill").font(.system(size: 30, weight: .bold))
                    Text(tr("حذف", "Delete")).font(Theme.font(15, .heavy))
                }
                .foregroundStyle(Theme.danger)
            }
            .frame(width: 150, height: 150)
            .scaleEffect(holding ? 0.94 : 1)
            .onLongPressGesture(minimumDuration: 3, maximumDistance: 40) {
                Task { await finish() }
            } onPressingChanged: { pressing in
                holding = pressing
                if pressing {
                    Haptics.tap(.heavy)
                    withAnimation(.linear(duration: 3)) { hold = 1 }
                    withAnimation { mood = .angry }
                } else if hold < 1 {
                    withAnimation(.spring) { hold = 0; mood = .sleepy }
                }
            }
        }
    }

    // MARK: Helpers

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.danger).frame(width: 24)
            Text(text).font(Theme.font(14, .semibold)).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
    }

    private func dangerButton(_ title: String, enabled: Bool, loading: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            guard enabled, !loading else { return }
            Haptics.tap(.medium)
            action()
        } label: {
            HStack(spacing: 8) {
                if loading { ProgressView().tint(.white) }
                Text(title).font(Theme.font(17, .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(Capsule().fill(Theme.danger))
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(PressScale())
        .disabled(!enabled || loading)
    }

    private func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "أ", with: "ا").replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "ً", with: "")
    }

    private func go(_ s: Int) {
        focus = nil
        error = nil
        withAnimation { step = s; mood = s == 5 ? .sleepy : .suspicious(0.6) }
    }

    private func fail(_ msg: String) {
        error = msg
        withAnimation(.default) { shakes += 1 }
        FX.error()
        withAnimation { mood = .angry }
    }

    private func checkPassword() async {
        busy = true; defer { busy = false }
        withAnimation { mood = .thinking }
        if await state.verifyMainPassword(password) { go(3) } else { password = ""; fail(AppError.wrongPassword.localizedDescription) }
    }

    private func checkCode() {
        if state.checkCodeNow(code) { go(4) } else {
            code = ""
            fail((state.lastCodeProblem ?? .wrongCode).localizedDescription)
        }
    }

    private func checkRecovery() async {
        busy = true; defer { busy = false }
        do {
            try await state.verifyForSectionReset(password: password, code: nil, recoveryKey: recovery)
            go(4)
        } catch { fail(error.localizedDescription) }
    }

    private func face() async {
        guard step == 4 else { return }
        guard Biometrics.isAvailable else { go(5); return }
        busy = true; defer { busy = false }
        withAnimation { mood = .scanning }
        if await Biometrics.authenticate(reason: tr("تأكيد حذف الحساب", "Confirm account deletion")) != nil { go(5) }
        else { fail(AppError.faceFailed.localizedDescription) }
    }

    private func finish() async {
        Haptics.error()
        SoundFX.shared.play(.delete, volume: 0.7)
        await state.deleteAccount(includeCloud: includeCloud)
        dismiss()
    }
}
