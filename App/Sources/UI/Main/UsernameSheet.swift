import SwiftUI

/// Change the username: a code goes to the account's email first, and once it's changed the name
/// stays put for 90 days. The server enforces both (supabase/username.sql), the app just explains.
struct UsernameSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    private let sb = SupabaseClient.shared

    private enum Step { case name, code }

    @State private var step: Step = .name
    @State private var newName = ""
    @State private var code = ""
    @State private var lockedUntil: Date?
    @State private var checking = true
    @State private var loading = false
    @State private var error: String?
    @State private var resendIn = 0
    @FocusState private var focus: AYNFieldID?

    private var email: String { state.profile?.email ?? "" }
    private var current: String { state.profile?.username ?? "" }
    private var trimmed: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameOK: Bool { trimmed.count >= 2 && trimmed.count <= 32 && trimmed != current }

    var body: some View {
        SheetScaffold(title: tr("اسم المستخدم", "Username")) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("اسمك الحين", "Your name now")).font(Theme.font(12, .semibold)).foregroundStyle(Theme.faint)
                Text(current).font(Theme.font(22, .heavy)).foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(14)

            if checking {
                ProgressView().tint(Theme.accent).padding(.top, 20)
            } else if let until = lockedUntil {
                lockedCard(until)
            } else if step == .name {
                nameStep
            } else {
                codeStep
            }

            if let error {
                Text(error).font(Theme.font(14, .semibold)).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await checkLock() }
    }

    // MARK: Steps

    private var nameStep: some View {
        VStack(spacing: 14) {
            AYNField(title: tr("الاسم الجديد", "New name"), icon: "person.fill", text: $newName,
                     contentType: .username, focus: $focus, id: .username) { if nameOK { Task { await sendCode() } } }
            Label(tr("بعد ما تغيّره، ما تقدر تغيّره مرة ثانية إلا بعد ٩٠ يوم.",
                     "Once changed, you can't change it again for 90 days."),
                  systemImage: "clock.badge.exclamationmark")
                .font(Theme.font(13)).foregroundStyle(Theme.warn)
                .frame(maxWidth: .infinity, alignment: .leading)
            PrimaryButton(title: tr("طرش كود لإيميلي", "Email me a code"), icon: "envelope.fill",
                          loading: loading, enabled: nameOK && sb.isConfigured) {
                Task { await sendCode() }
            }
        }
    }

    private var codeStep: some View {
        VStack(spacing: 14) {
            StepHeader(icon: "envelope.badge.shield.half.filled",
                       title: tr("تأكيد الإيميل", "Verify your email"),
                       subtitle: tr("طرشنا كود إلى\n\(email)", "We sent a code to\n\(email)"))
            CodeField(code: $code, length: 8, mail: true)
            Button {
                Task { await sendCode() }
            } label: {
                Text(resendIn > 0 ? tr("طرشه مرة ثانية بعد \(resendIn) ث", "Resend in \(resendIn)s") : tr("طرشه مرة ثانية", "Resend code"))
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(resendIn > 0 ? Theme.faint : Theme.accent)
            }
            .disabled(resendIn > 0 || loading)
            PrimaryButton(title: tr("غيّر اسمي إلى «\(trimmed)»", "Change my name to “\(trimmed)”"), icon: "checkmark.seal.fill",
                          loading: loading, enabled: code.filter(\.isNumber).count >= 6) {
                Task { await confirm() }
            }
            Button(tr("رجوع", "Back")) { step = .name; code = ""; error = nil }
                .font(Theme.font(14, .semibold)).foregroundStyle(Theme.sub)
        }
    }

    private func lockedCard(_ until: Date) -> some View {
        let days = max(1, Int(ceil(until.timeIntervalSinceNow / 86400)))
        return VStack(spacing: 10) {
            Image(systemName: "lock.badge.clock.fill")
                .font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.gradient)
            Text(tr("غيّرت اسمك قبل شوي", "You changed your name recently"))
                .font(Theme.font(17, .heavy)).foregroundStyle(Theme.text)
            Text(tr("تقدر تغيّره مرة ثانية بعد \(days) يوم\n(\(Fmt.date(until, time: false)))",
                    "You can change it again in \(days) days\n(\(Fmt.date(until, time: false)))"))
                .font(Theme.font(14)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .glass(18, tint: Theme.accent2)
    }

    // MARK: Actions

    private func checkLock() async {
        var until: Date?
        if let last = state.profile?.usernameChangedAt {
            let next = last.addingTimeInterval(90 * 86400)
            if next > Date() { until = next }
        }
        if let server = await sb.usernameUnlockDate(), server > (until ?? .distantPast) { until = server }
        lockedUntil = until
        checking = false
        if until == nil { focus = .username }
    }

    private func sendCode() async {
        guard nameOK else { return }
        loading = true
        defer { loading = false }
        error = nil
        do {
            try await sb.sendEmailCode(to: email)
            step = .code
            startResendTimer()
        } catch {
            self.error = error.localizedDescription
            FX.error()
        }
    }

    private func confirm() async {
        loading = true
        defer { loading = false }
        error = nil
        do {
            try await sb.verifyEmailCode(email: email, code: code)
        } catch {
            self.error = tr("الكود غلط أو انتهى، طرش واحد جديد.", "Wrong or expired code, send a new one.")
            FX.error()
            return
        }
        switch await sb.changeUsername(trimmed) {
        case .ok:
            state.applyNewUsername(trimmed)
            state.show(tr("صار اسمك «\(trimmed)» ✓", "You're now “\(trimmed)” ✓"))
            Haptics.success()
            dismiss()
        case .locked(let until):
            lockedUntil = until
        case .needsCode:
            error = tr("لازم تأكيد جديد من الإيميل، طرش الكود مرة ثانية.", "A fresh email code is needed, send it again.")
            FX.error()
        case .tooShort:
            error = tr("الاسم لازم يكون من ٢ لين ٣٢ حرف.", "The name must be 2 to 32 characters.")
            FX.error()
        case .same:
            error = tr("هذا نفس اسمك الحين.", "That's already your name.")
            FX.error()
        case .failed(let msg):
            error = msg.isEmpty ? tr("ما قدرنا نغيّره الحين، جرّب بعد شوي.", "Couldn't change it right now, try again shortly.") : msg
            FX.error()
        }
    }

    private func startResendTimer() {
        resendIn = 60
        Task {
            while resendIn > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                resendIn -= 1
            }
        }
    }
}
