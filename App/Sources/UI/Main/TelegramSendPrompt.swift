import SwiftUI

/// Shown right after a new account is saved (when "ask each time" is on): send it to Telegram now,
/// plainly or wrapped in a reversible cipher, or skip.
struct TelegramSendPrompt: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let account: AccountItem

    @State private var mode: Mode = .normal
    @State private var cipher: Cipher = .mnlovo
    @State private var key = ""
    @State private var sending = false
    @State private var dontAsk = false
    @FocusState private var keyFocus: AYNFieldID?
    @AppStorage("intro.cipher.seen") private var cipherIntroSeen = false
    @State private var showCipherIntro = false

    enum Mode: Hashable { case normal, cipher }
    private let blue = TelegramService.blue

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 16) {
                    SheetHeader(title: tr("إرسال للتيليجرام؟", "Send to Telegram?")) { finish(send: false) }
                    header
                    modePicker
                    if mode == .cipher {
                        cipherPicker
                        CipherPreview(plain: previewSource, cipher: cipher, key: key)
                    }
                    Toggle(isOn: $dontAsk) {
                        Text(tr("لا تسألني بعدها (أرسل تلقائياً)", "Don't ask again (send automatically)"))
                            .font(Theme.font(13, .semibold))
                    }
                    .tint(Theme.accent).glass(12)
                    HStack(spacing: 12) {
                        SecondaryButton(title: tr("تخطّي", "Skip"), icon: "xmark", color: Theme.sub) { finish(send: false) }
                        PrimaryButton(title: tr("إرسال", "Send"), icon: "paperplane.fill", loading: sending,
                                      enabled: mode == .normal || !cipher.needsKey || !key.isEmpty) {
                            Task { await send() }
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .fullScreenCover(isPresented: $showCipherIntro) {
            CipherIntro {
                cipherIntroSeen = true
                showCipherIntro = false
                // They've just watched why it matters, so start them on the ciphered choice.
                withAnimation(.spring(response: 0.35)) { mode = .cipher }
            }
        }
    }

    /// A short, non-secret stand-in for the live preview: the real password is never rendered here.
    private var previewSource: String {
        var parts = [account.service]
        if !account.login.isEmpty { parts.append(account.login) }
        parts.append(String(repeating: "•", count: max(6, min(12, account.password.count))))
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrandAvatar(name: account.service, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.service).font(Theme.font(17, .heavy)).foregroundStyle(Theme.text)
                Text(account.sensitivity == .secret ? tr("🔴 سري جداً", "🔴 Top-secret")
                     : account.sensitivity == .sensitive ? tr("🟡 حساس", "🟡 Sensitive") : tr("🟢 عادي", "🟢 Normal"))
                    .font(Theme.font(12, .semibold)).foregroundStyle(Theme.sub)
            }
            Spacer()
        }
        .glass(14, tint: blue)
    }

    private var modePicker: some View {
        VStack(spacing: 10) {
            choice(.normal, "paperplane.fill", tr("إرسال عادي", "Send normally"),
                   tr("رسالة مرتّبة ومشوّشة، تنكشف باللمس.", "A tidy message, blurred, revealed on tap."))
            choice(.cipher, "lock.shield.fill", tr("شفّره قبل الإرسال", "Encrypt it first"),
                   tr("يتحوّل لطلاسم، ما يفكها إلا «أداة التشفير» في التطبيق.", "Turns into gibberish only the app's Cipher tool can read."))
            Button {
                Haptics.light()
                showCipherIntro = true
            } label: {
                Label(tr("وش يعني تشفير؟ شوف الشرح", "What does ciphering mean? Watch the walkthrough"),
                      systemImage: "play.circle.fill")
                    .font(Theme.font(12, .bold)).foregroundStyle(Theme.accent3)
            }
            .buttonStyle(PressScale())
        }
        .onAppear {
            // The very first time this prompt appears, explain the idea before asking them to choose.
            if !cipherIntroSeen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showCipherIntro = true }
            }
        }
    }

    private func choice(_ m: Mode, _ icon: String, _ title: String, _ sub: String) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.3)) { mode = m }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(mode == m ? blue : Theme.sub).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                    Text(sub).font(Theme.font(12)).foregroundStyle(Theme.sub)
                }
                Spacer()
                Image(systemName: mode == m ? "largecircle.fill.circle" : "circle").foregroundStyle(mode == m ? blue : Theme.faint)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(mode == m ? blue.opacity(0.12) : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(mode == m ? blue.opacity(0.5) : Theme.stroke))
        }
        .buttonStyle(PressScale())
    }

    private var cipherPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Cipher.allCases) { c in
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.3)) { cipher = c }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: c.icon).font(.system(size: 13, weight: .bold))
                                Text(c.title).font(Theme.font(13, .semibold)).lineLimit(1)
                            }
                            .foregroundStyle(cipher == c ? Theme.bg : Theme.text)
                            .padding(.horizontal, 12).frame(height: 38)
                            .background(Capsule().fill(cipher == c ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surface)))
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
            Text(cipher.blurb).font(Theme.font(12)).foregroundStyle(Theme.faint).id(cipher)
            if cipher.needsKey {
                AYNField(title: cipher.keyIsNumber ? tr("رقم الإزاحة", "Shift number") : tr("كلمة المرور", "Password"),
                         icon: "key.fill", text: $key, secure: !cipher.keyIsNumber,
                         keyboard: cipher.keyIsNumber ? .numberPad : .default, focus: $keyFocus, id: .secret)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            let n = try await TelegramService.shared.sendAccountNow(account, cipher: mode == .cipher ? cipher : nil, key: key)
            Haptics.success()
            state.show(n > 0 ? tr("انرسل ✓", "Sent ✓") : tr("ما وصل لأي محادثة", "Didn't reach any chat"), icon: "paperplane.fill")
        } catch {
            state.show(error.localizedDescription, icon: "exclamationmark.triangle.fill")
        }
        finish(send: true)
    }

    private func finish(send: Bool) {
        if dontAsk {
            var s = TelegramService.shared.settings
            s.askEachTime = false
            TelegramService.shared.settings = s
        }
        dismiss()
    }
}
