import SwiftUI
import UIKit

func pause(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

let emailPattern = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
func isValidEmail(_ s: String) -> Bool {
    s.trimmingCharacters(in: .whitespaces).range(of: emailPattern, options: .regularExpression) != nil
}

// MARK: - Password + confirmation with the watching eye

struct PasswordCreator: View {
    @Binding var password: String
    @Binding var confirm: String
    var focus: FocusState<AYNFieldID?>.Binding
    var firstID: AYNFieldID = .password
    var secondID: AYNFieldID = .confirm
    var eyeSize: CGFloat = 150
    var titleFirst = tr("كلمة السر", "Password")
    var titleSecond = tr("أكّد كلمة السر", "Confirm password")
    var showEye = true

    static func mood(password: String, confirm: String, focused: AYNFieldID?, first: AYNFieldID, second: AYNFieldID) -> EyeMood {
        let progress = CGFloat(confirm.count) / CGFloat(max(password.count, 1))
        if focused == second || (!confirm.isEmpty && focused != first) {
            if confirm.isEmpty { return .reading(0) }
            if !password.hasPrefix(confirm) {
                return confirm.count >= password.count ? .angry : .suspicious(min(progress, 1))
            }
            if confirm == password { return .happy }
            return .reading(progress)
        }
        if focused == first { return .lookUp }
        return .idle
    }

    private var mood: EyeMood {
        Self.mood(password: password, confirm: confirm, focused: focus.wrappedValue, first: firstID, second: secondID)
    }

    private var caption: String { Self.caption(for: mood) }

    static func caption(for mood: EyeMood) -> String {
        switch mood {
        case .lookUp: return tr("ما أطالع 🙈 اكتب براحتك", "Not looking 🙈 type away")
        case .reading: return tr("قاعد أتحقق منها حرف حرف…", "Checking it letter by letter…")
        case .suspicious: return tr("امم… في شي مب متطابق 🤨", "Hmm… something doesn't match 🤨")
        case .angry: return tr("ما تتطابق! جرّب مرة ثانية", "They don't match! Try again")
        case .happy: return tr("متطابقة ✓ ممتاز", "They match ✓ nice")
        default: return tr("اختر كلمة سر قوية. هي مفتاح كل شي.", "Pick a strong password. It unlocks everything.")
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            if showEye {
                EyeView(mood: mood, size: eyeSize, sounds: true)
                    .frame(height: eyeSize * 0.9)
                Text(caption)
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.sub)
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: caption)
            }

            AYNField(title: titleFirst, icon: "key.fill", text: $password, secure: true,
                     contentType: .newPassword, focus: focus, id: firstID) { focus.wrappedValue = secondID }
            StrengthMeter(password: password)
            requirements
            AYNField(title: titleSecond, icon: "checkmark.shield.fill", text: $confirm, secure: true,
                     contentType: .newPassword, focus: focus, id: secondID) { focus.wrappedValue = nil }
        }
        .onChange(of: password) { _, _ in FX.key() }
        .onChange(of: confirm) { _, _ in FX.key() }
    }

    private var requirements: some View {
        let items: [(String, Bool)] = [
            (tr("٦ أحرف أو أكثر (مطلوب)", "6+ characters (required)"), password.count >= 6),
            (tr("حرف كبير وصغير (يقوّيها)", "Upper & lower (stronger)"), password.contains(where: { $0.isUppercase }) && password.contains(where: { $0.isLowercase })),
            (tr("رقم (يقوّيها)", "A number (stronger)"), password.contains(where: { $0.isNumber })),
            (tr("رمز (يقوّيها)", "A symbol (stronger)"), password.contains(where: { !$0.isLetter && !$0.isNumber }))
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.1 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.1 ? Theme.ok : Theme.faint)
                    Text(item.0).foregroundStyle(item.1 ? Theme.text : Theme.sub)
                }
                .font(Theme.font(13, .medium))
                .animation(.spring(response: 0.3), value: item.1)
            }
        }
    }

    /// Only rule: at least 6 characters and both fields match. Strength is shown, not enforced.
    static func isAcceptable(_ p: String, _ c: String) -> Bool {
        p.count >= 6 && p == c
    }
}

// MARK: - Recovery key card

struct RecoveryKeyCard: View {
    var key: String
    var body: some View {
        VStack(spacing: 14) {
            let groups = key.split(separator: "-").map(String.init)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                    VStack(spacing: 2) {
                        Text("\(i + 1)").font(Theme.font(10, .bold)).foregroundStyle(Theme.faint)
                        Text(g).font(Theme.mono(20, .bold)).foregroundStyle(Theme.text)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceHi))
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            Button {
                Clipboard.copy(key)
            } label: {
                Label(tr("نسخ المفتاح", "Copy key"), systemImage: "doc.on.doc.fill")
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .glass(16, tint: Theme.warn)
    }
}

// MARK: - 2FA setup card (QR + add to iOS Passwords)

struct TwoFactorSetupCard: View {
    var totp: TOTP
    @State private var showSecret = false
    @State private var openFailed = false

    var body: some View {
        VStack(spacing: 14) {
            if let img = QRCode.image(totp.url) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.white))
                    .shadow(color: Theme.accent.opacity(0.35), radius: 20)
            }
            PrimaryButton(title: tr("أضف إلى تطبيق كلمات السر", "Add to iPhone Passwords"), icon: "key.viewfinder") {
                guard let url = URL(string: totp.url) else { return }
                UIApplication.shared.open(url) { ok in if !ok { openFailed = true; showSecret = true } }
            }
            Button {
                withAnimation(.spring) { showSecret.toggle() }
            } label: {
                Text(showSecret ? tr("إخفاء مفتاح الإعداد", "Hide setup key") : tr("أو أدخل مفتاح الإعداد يدوياً", "Or enter the setup key manually"))
                    .font(Theme.font(14, .semibold)).foregroundStyle(Theme.accent)
            }
            if showSecret {
                VStack(spacing: 8) {
                    Text(spaced(totp.secretBase32))
                        .font(Theme.mono(15, .bold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                        .environment(\.layoutDirection, .leftToRight)
                    Button { Clipboard.copy(totp.secretBase32) } label: {
                        Label(tr("نسخ", "Copy"), systemImage: "doc.on.doc").font(Theme.font(13, .semibold))
                    }
                    Text(tr("الإعدادات ← كلمات السر ← اختر الحساب أو أنشئه ← «إعداد رمز التحقق» ← «إدخال مفتاح الإعداد».",
                            "Passwords app → choose/create the entry → “Set Up Verification Code” → “Enter Setup Key”."))
                        .font(Theme.font(12)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .glass(18)
    }

    private func spaced(_ s: String) -> String {
        stride(from: 0, to: s.count, by: 4).map { i -> String in
            let start = s.index(s.startIndex, offsetBy: i)
            let end = s.index(start, offsetBy: min(4, s.count - i))
            return String(s[start..<end])
        }.joined(separator: " ")
    }
}

struct StepHeader: View {
    var icon: String
    var title: String
    var subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.gradient)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Theme.surfaceHi))
            Text(title).font(Theme.font(26, .heavy)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }
}
