import SwiftUI

/// Dots that fill as digits are typed; shakes on a wrong code.
struct PasscodeDots: View {
    var length: Int
    var filled: Int
    var tint: Color = Theme.accent
    var shakes: Int

    var body: some View {
        HStack(spacing: length > 4 ? 16 : 22) {
            ForEach(0..<length, id: \.self) { i in
                ZStack {
                    Circle().strokeBorder(Theme.sub.opacity(0.6), lineWidth: 1.5)
                    Circle().fill(Theme.gradient)
                        .scaleEffect(i < filled ? 1 : 0.01)
                        .shadow(color: tint.opacity(i < filled ? 0.7 : 0), radius: 6)
                }
                .frame(width: 15, height: 15)
                .animation(.spring(response: 0.25, dampingFraction: 0.55), value: filled)
            }
        }
        .modifier(ShakeEffect(shakes: CGFloat(shakes)))
        .animation(.easeInOut(duration: 0.42), value: shakes)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel(tr("\(filled) من \(length)", "\(filled) of \(length)"))
    }
}

struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(shakes * .pi * 4), y: 0))
    }
}

/// iOS-style number pad.
struct PasscodePad: View {
    @Binding var code: String
    var length: Int
    var biometricIcon: String? = nil
    var onBiometric: () -> Void = {}
    var onComplete: (String) -> Void

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["bio", "0", "del"]]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 22) {
                    ForEach(row, id: \.self) { key in keyView(key) }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private func keyView(_ key: String) -> some View {
        switch key {
        case "bio":
            if let icon = biometricIcon {
                Button { Haptics.tap(); onBiometric() } label: {
                    Image(systemName: icon).font(.system(size: 26, weight: .regular)).foregroundStyle(Theme.accent)
                        .frame(width: 76, height: 76)
                }
                .buttonStyle(PressScale())
            } else {
                Color.clear.frame(width: 76, height: 76)
            }
        case "del":
            Button {
                guard !code.isEmpty else { return }
                Haptics.selection()
                code.removeLast()
            } label: {
                Image(systemName: "delete.backward").font(.system(size: 24, weight: .regular)).foregroundStyle(Theme.text)
                    .frame(width: 76, height: 76)
            }
            .buttonStyle(PressScale())
            .opacity(code.isEmpty ? 0.3 : 1)
        default:
            Button {
                guard code.count < length else { return }
                Haptics.tap(.light)
                code.append(key)
                if code.count == length {
                    let done = code
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { onComplete(done) }
                }
            } label: {
                Text(key)
                    .font(Theme.font(32, .regular))
                    .foregroundStyle(Theme.text)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Theme.surfaceHi))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.06)))
            }
            .buttonStyle(PadPress())
        }
    }
}

struct PadPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Theme.accent.opacity(configuration.isPressed ? 0.35 : 0)))
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// One passcode entry (digits with pad, or text with a field).
struct PasscodeEntry: View {
    var kind: PasscodeKind
    @Binding var code: String
    var shakes: Int
    var biometricIcon: String? = nil
    var onBiometric: () -> Void = {}
    var focus: FocusState<AYNFieldID?>.Binding
    var onComplete: (String) -> Void

    var body: some View {
        VStack(spacing: 22) {
            if let length = kind.length {
                PasscodeDots(length: length, filled: code.count, shakes: shakes)
                    .padding(.vertical, 8)
                PasscodePad(code: $code, length: length, biometricIcon: biometricIcon,
                            onBiometric: onBiometric, onComplete: onComplete)
            } else {
                AYNField(title: tr("كلمة سر القسم", "Section password"), icon: "lock.fill", text: $code, secure: true,
                         focus: focus, id: .section) { if !code.isEmpty { onComplete(code) } }
                    .modifier(ShakeEffect(shakes: CGFloat(shakes)))
                    .animation(.easeInOut(duration: 0.42), value: shakes)
                HStack(spacing: 10) {
                    if let icon = biometricIcon {
                        CircleIconButton(icon: icon, size: 56, tint: Theme.accent, action: onBiometric)
                    }
                    PrimaryButton(title: tr("فتح", "Open"), icon: "lock.open.fill", enabled: !code.isEmpty) { onComplete(code) }
                }
            }
        }
    }
}

/// Create (or change) the section passcode: choose type → enter → confirm, with the eye watching.
struct PasscodeSetupFlow: View {
    var onDone: (String, PasscodeKind) -> Void

    @State private var kind: PasscodeKind = .pin6
    @State private var step = 0           // 0 enter, 1 confirm
    @State private var first = ""
    @State private var code = ""
    @State private var shakes = 0
    @State private var mood: EyeMood = .lookUp
    @State private var error: String?
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        VStack(spacing: 16) {
            EyeView(mood: eyeMood, size: 120, sounds: true)
            Text(step == 0 ? tr("أنشئ رمز الأقسام", "Create a section passcode") : tr("أكّد الرمز", "Confirm the passcode"))
                .font(Theme.font(24, .heavy)).foregroundStyle(Theme.text)
            Text(step == 0
                 ? tr("يحمي «الحسابات» و«الخزنة». خلّه مختلف عن كلمة سر الدخول.", "Protects Accounts and Vault. Keep it different from your main password.")
                 : tr("اكتبه مرة ثانية.", "Type it once more."))
                .font(Theme.font(14)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)

            if step == 0 {
                HStack(spacing: 8) {
                    ForEach(PasscodeKind.allCases) { k in
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.3)) { kind = k; code = "" }
                        } label: {
                            Text(k.title)
                                .font(Theme.font(13, .bold))
                                .foregroundStyle(kind == k ? Theme.bg : Theme.sub)
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(Capsule().fill(kind == k ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surface)))
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
            if let error {
                Text(error).font(Theme.font(13, .semibold)).foregroundStyle(Theme.danger)
            }
            PasscodeEntry(kind: kind, code: $code, shakes: shakes, focus: $focus) { entered in submit(entered) }
        }
        .onChange(of: code) { _, _ in error = nil }
    }

    private var eyeMood: EyeMood {
        if mood == .happy || mood == .angry { return mood }
        if step == 0 { return .lookUp }
        let p = CGFloat(code.count) / CGFloat(max(first.count, 1))
        if !code.isEmpty && !first.hasPrefix(code) { return .suspicious(min(p, 1)) }
        return .reading(p)
    }

    private func submit(_ entered: String) {
        if kind == .text && entered.count < 4 {
            error = tr("٤ أحرف على الأقل", "At least 4 characters")
            return
        }
        if step == 0 {
            first = entered
            code = ""
            withAnimation(.spring) { step = 1 }
            Haptics.soft(0.5)
        } else if entered == first {
            withAnimation { mood = .happy }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onDone(entered, kind) }
        } else {
            withAnimation { mood = .angry }
            shakes += 1
            error = tr("ما تطابق. ابدأ من جديد.", "Didn't match. Start again.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.spring) { step = 0; first = ""; code = ""; mood = .lookUp }
            }
        }
    }
}
