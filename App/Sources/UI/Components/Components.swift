import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Background

struct AuroraBackground: View {
    @State private var move = false
    var body: some View {
        ZStack {
            Theme.bg
            if #available(iOS 18.0, *) {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
                    let t = Float(ctx.date.timeIntervalSinceReferenceDate * 0.12)
                    let cx: Float = 0.5 + 0.12 * sin(t)
                    let cy: Float = 0.45 + 0.1 * cos(t * 1.3)
                    let pts: [SIMD2<Float>] = [
                        SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
                        SIMD2(0, 0.5), SIMD2(cx, cy), SIMD2(1, 0.5),
                        SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)
                    ]
                    MeshGradient(width: 3, height: 3, points: pts, colors: [
                        Color(hex: 0x0B2A2B), Theme.bg, Color(hex: 0x120E2C),
                        Theme.bg, Color(hex: 0x0A0C18), Theme.bg,
                        Color(hex: 0x0E0B26), Theme.bg, Color(hex: 0x1E0F33)
                    ])
                    .opacity(0.95)
                }
            }
            Circle().fill(Theme.accent.opacity(0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 120)
                .offset(x: move ? -120 : -60, y: move ? -320 : -250)
            Circle().fill(Theme.accent2.opacity(0.2))
                .frame(width: 420, height: 420)
                .blur(radius: 130)
                .offset(x: move ? 140 : 90, y: move ? 330 : 260)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) { move = true }
        }
    }
}

// MARK: - Glass card

struct GlassCard: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 22
    var tint: Color? = nil
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.075), Color.white.opacity(0.03)],
                                         startPoint: .top, endPoint: .bottom))
                    .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial).opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [(tint ?? .white).opacity(tint == nil ? 0.14 : 0.5),
                                                          (tint ?? .white).opacity(tint == nil ? 0.03 : 0.15)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }
}

extension View {
    func glass(_ padding: CGFloat = 16, radius: CGFloat = 22, tint: Color? = nil) -> some View {
        modifier(GlassCard(padding: padding, radius: radius, tint: tint))
    }
}

// MARK: - Buttons

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct PrimaryButton: View {
    var title: String
    var icon: String? = nil
    var loading = false
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button {
            guard enabled, !loading else { return }
            FX.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                if loading {
                    ProgressView().tint(Theme.bg)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 17, weight: .bold))
                }
                Text(title).font(Theme.font(17, .bold))
            }
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Capsule().fill(Theme.gradient))
            .shadow(color: Theme.accent.opacity(enabled ? 0.45 : 0), radius: 18, y: 6)
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(PressScale())
        .disabled(!enabled || loading)
    }
}

struct SecondaryButton: View {
    var title: String
    var icon: String? = nil
    var color: Color = Theme.text
    var action: () -> Void

    var body: some View {
        Button {
            FX.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(Theme.font(16, .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressScale())
    }
}

struct CircleIconButton: View {
    var icon: String
    var size: CGFloat = 42
    var tint: Color = Theme.text
    var action: () -> Void
    var body: some View {
        Button {
            FX.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.surfaceHi))
                .overlay(Circle().strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressScale())
    }
}

// MARK: - Text fields

struct AYNField: View {
    var title: String
    var icon: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var focus: FocusState<AYNFieldID?>.Binding
    var id: AYNFieldID
    var trailing: AnyView? = nil
    var onSubmit: () -> Void = {}

    @State private var reveal = false

    private var focused: Bool { focus.wrappedValue == id }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(focused ? Theme.accent : Theme.sub)
                .frame(width: 24)
            ZStack(alignment: .leading) {
                if secure && !reveal {
                    SecureField(title, text: $text)
                        .focused(focus, equals: id)
                } else {
                    TextField(title, text: $text)
                        .focused(focus, equals: id)
                }
            }
            .font(Theme.font(17, .medium))
            .foregroundStyle(Theme.text)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit(onSubmit)

            if let trailing { trailing }
            if secure {
                Button {
                    reveal.toggle()
                    FX.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focus.wrappedValue = id }
                } label: {
                    Image(systemName: reveal ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(Theme.sub)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(focused ? Theme.accent.opacity(0.8) : Theme.stroke, lineWidth: focused ? 1.5 : 1)
        )
        .shadow(color: focused ? Theme.accent.opacity(0.25) : .clear, radius: 12)
        .animation(.easeOut(duration: 0.2), value: focused)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = id }
    }
}

enum AYNFieldID: Hashable {
    case username, email, phone, password, confirm, code, recovery, current, new, newConfirm, section, sectionConfirm
    case service, login, url, notes, title, search, secret, sbURL, sbKey, duress, duressConfirm, legacyWill
}

/// Big 6-digit code field (2FA / email code).
struct CodeField: View {
    @Binding var code: String
    var length = 6
    var tint: Color = Theme.accent
    /// Off for 2FA codes: iOS would otherwise offer SMS codes from Messages, which are never the right one.
    var autofill = true
    /// Shows "open my mail" shortcuts (for email codes).
    var mail = false
    @FocusState private var focused: Bool
    @State private var clipHasCode = false
    @State private var glow = false
    @State private var pasted = false
    /// Only reach into the clipboard once per appearance, so iOS never nags.
    @State private var autoGrab = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(autofill ? .oneTimeCode : nil)
                    .focused($focused)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .frame(width: 1, height: 1)
                    .opacity(0.02)
                    .onChange(of: code) { _, v in
                        let clean = String(TOTP.westernDigits(v).filter { $0.isASCII && $0.isNumber }.prefix(length))
                        if clean != v { code = clean }
                        FX.key()
                    }
                HStack(spacing: length > 6 ? 6 : 10) {
                    ForEach(0..<length, id: \.self) { i in
                        let chars = Array(code)
                        let ch = i < chars.count ? String(chars[i]) : ""
                        let active: Bool = (i == chars.count) && focused
                        let border: Color = active ? tint : (ch.isEmpty ? Theme.stroke : tint.opacity(0.5))
                        Text(ch)
                            .font(Theme.mono(length > 6 ? 22 : 26, .bold))
                            .foregroundStyle(Theme.text)
                            .frame(width: length > 6 ? 36 : 46, height: 58)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(border, lineWidth: active ? 2 : 1))
                            .scaleEffect(ch.isEmpty ? 1 : 1.04)
                            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: ch)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
            }

            pasteRow
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
            checkClipboard()
        }
        .onChange(of: scenePhase) { _, p in
            if p == .active {
                autoGrab = true          // coming back from Mail: try once more
                checkClipboard()
            }
        }
    }

    /// Pulls a code out of pasted text: western digits only, trimmed to the field's length.
    /// Reading the string rather than a number keeps a leading zero, which codes often have.
    static func extractCode(_ text: String, max length: Int) -> String {
        let digits = TOTP.westernDigits(text).filter { $0.isASCII && $0.isNumber }
        return String(digits.prefix(length))
    }

    /// A big, friendly paste button that lights up when a code is sitting on the clipboard
    /// (detected without reading it, so iOS doesn't ask for permission).
    private var pasteRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                PasteButton(payloadType: String.self) { items in
                    guard let text = items.first else { return }
                    let found = Self.extractCode(text, max: length)
                    DispatchQueue.main.async {
                        withAnimation(.spring) { code = found }
                        clipHasCode = false
                        Haptics.success()
                    }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                .tint(clipHasCode ? tint : Theme.surfaceHi)
                .controlSize(clipHasCode ? .large : .regular)
                .shadow(color: tint.opacity(clipHasCode && glow ? 0.7 : 0), radius: 14)
                .scaleEffect(clipHasCode && glow ? 1.04 : 1)

                if mail {
                    Menu {
                        Button { open("message://") } label: { Label("Mail", systemImage: "envelope.fill") }
                        Button { open("googlegmail://") } label: { Label("Gmail", systemImage: "envelope.badge.fill") }
                        Button { open("ms-outlook://") } label: { Label("Outlook", systemImage: "envelope.open.fill") }
                        Button { open("ymail://") } label: { Label("Yahoo Mail", systemImage: "envelope") }
                    } label: {
                        Label(tr("افتح البريد", "Open mail"), systemImage: "envelope.open.fill")
                            .font(Theme.font(14, .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(Capsule().fill(Theme.surfaceHi))
                    }
                }
            }
            if pasted {
                Label(tr("لصقناه لك ✓", "Pasted for you ✓"), systemImage: "checkmark.circle.fill")
                    .font(Theme.font(12, .bold)).foregroundStyle(Theme.ok)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if clipHasCode {
                Label(tr("لقينا كود منسوخ — اضغط «لصق»", "A copied code is ready — tap Paste"), systemImage: "sparkles")
                    .font(Theme.font(12, .semibold)).foregroundStyle(tint)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if mail && autofill {
                Text(tr("إذا تستخدم تطبيق «البريد» من Apple، الكود يطلع فوق الكيبورد لحاله.", "With Apple Mail, the code appears above the keyboard by itself."))
                    .font(Theme.font(11)).foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
            }
        }
        .animation(.spring(response: 0.4), value: clipHasCode)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { glow = true } }
    }

    private func open(_ s: String) {
        if let u = URL(string: s) { openURL(u) }
    }

    /// Looks for a copied code and fills it in by itself.
    /// `detectPatterns` is silent, so we only reach for the text when a number really is on the
    /// clipboard — and only once per appearance, so iOS never nags.
    private func checkClipboard() {
        guard code.count < length, UIPasteboard.general.hasStrings else {
            if clipHasCode { clipHasCode = false }
            return
        }
        UIPasteboard.general.detectPatterns(for: [UIPasteboard.DetectionPattern.number]) { result in
            let has = (try? result.get())?.contains(UIPasteboard.DetectionPattern.number) ?? false
            DispatchQueue.main.async {
                withAnimation { clipHasCode = has }
                guard has, autoGrab else { return }
                autoGrab = false
                // Reading the string keeps leading zeros, which a numeric value would drop.
                guard let raw = UIPasteboard.general.string else { return }
                let digits = TOTP.westernDigits(raw).filter { $0.isASCII && $0.isNumber }
                guard digits.count == length, code.count < length else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { code = digits }
                clipHasCode = false
                pasted = true
                Haptics.success()
            }
        }
    }
}

// MARK: - Strength meter

struct StrengthMeter: View {
    var password: String
    var body: some View {
        let s = PasswordTools.strength(password)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(i <= s.score && !password.isEmpty ? s.color : Theme.surfaceHi)
                        .frame(height: 6)
                }
            }
            .animation(.spring(response: 0.35), value: s.score)
            HStack {
                Text(s.label).foregroundStyle(password.isEmpty ? Theme.faint : s.color)
                Spacer()
                if !password.isEmpty {
                    Text(tr("\(Int(s.bits)) بت", "\(Int(s.bits)) bits")).foregroundStyle(Theme.faint)
                }
            }
            .font(Theme.font(13, .semibold))
        }
    }
}

// MARK: - Sensitivity

struct SensitivityBadge: View {
    var level: Sensitivity
    var compact = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.icon)
            if !compact { Text(level.title) }
        }
        .font(Theme.font(11, .bold))
        .foregroundStyle(level.color)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(level.color.opacity(0.14)))
    }
}

struct SensitivityPicker: View {
    @Binding var level: Sensitivity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Sensitivity.allCases) { s in
                    Button {
                        withAnimation(.spring(response: 0.3)) { level = s }
                        FX.toggle()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: s.icon).font(.system(size: 20, weight: .semibold))
                            Text(s.title).font(Theme.font(13, .bold))
                        }
                        .foregroundStyle(level == s ? s.color : Theme.sub)
                        .frame(maxWidth: .infinity)
                        .frame(height: 70)
                        .background(RoundedRectangle(cornerRadius: 16).fill(level == s ? s.color.opacity(0.15) : Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(level == s ? s.color.opacity(0.7) : Theme.stroke))
                    }
                    .buttonStyle(PressScale())
                }
            }
            Text(level.subtitle).font(Theme.font(12)).foregroundStyle(Theme.sub)
        }
    }
}

// MARK: - Misc

struct SectionTitle: View {
    var text: String
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(Theme.font(13, .bold))
        .foregroundStyle(Theme.sub)
        .textCase(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

struct StepProgress: View {
    var current: Int
    var total: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surfaceHi))
                    .frame(height: 5)
            }
        }
        .animation(.spring(response: 0.4), value: current)
    }
}

struct LanguageToggle: View {
    @AppStorage(AppLanguage.storageKey) private var lang: String = AppLanguage.systemDefault.rawValue
    var body: some View {
        Button {
            FX.toggle()
            lang = (lang == "ar") ? "en" : "ar"
            WidgetBridge.update()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(lang == "ar" ? "English" : "العربية")
            }
            .font(Theme.font(14, .semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(Theme.surfaceHi))
            .overlay(Capsule().strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressScale())
    }
}

struct ToastHost: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack {
            if let t = state.toast {
                HStack(spacing: 10) {
                    Image(systemName: t.icon).foregroundStyle(t.color)
                    Text(t.text).font(Theme.font(14, .semibold)).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(t.color.opacity(0.4)))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { withAnimation { state.toast = nil } }
                .task(id: t.id) {
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    withAnimation(.easeInOut) { if state.toast?.id == t.id { state.toast = nil } }
                }
            }
            Spacer()
        }
        .padding(.top, 6)
    }
}

enum Clipboard {
    /// Copies only to this iPhone (not to your Mac/iPad via Universal Clipboard).
    static func copy(_ text: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: text]], options: [.localOnly: true])
        Haptics.success()
    }
}

/// Brand-coloured monogram (no network requests → nothing leaks about which services you use).
struct BrandAvatar: View {
    var name: String
    var size: CGFloat = 46

    private static let brands: [String: (UInt32, UInt32, String?)] = [
        "instagram": (0xF58529, 0xDD2A7B, "camera.fill"), "انستقرام": (0xF58529, 0xDD2A7B, "camera.fill"),
        "snapchat": (0xFFFC00, 0xFFD000, "bolt.fill"), "سناب": (0xFFFC00, 0xFFD000, "bolt.fill"),
        "tiktok": (0x25F4EE, 0xFE2C55, "music.note"), "تيك توك": (0x25F4EE, 0xFE2C55, "music.note"),
        "x": (0x111111, 0x444444, nil), "twitter": (0x1DA1F2, 0x0C7ABF, nil),
        "facebook": (0x1877F2, 0x0E5BC0, nil), "whatsapp": (0x25D366, 0x128C7E, "phone.fill"),
        "telegram": (0x2AABEE, 0x229ED9, "paperplane.fill"), "discord": (0x5865F2, 0x404EED, "gamecontroller.fill"),
        "steam": (0x1B2838, 0x2A475E, "gamecontroller.fill"), "epic": (0x2F2F2F, 0x111111, "gamecontroller.fill"),
        "playstation": (0x003791, 0x0070D1, "gamecontroller.fill"), "xbox": (0x107C10, 0x0E6A0E, "gamecontroller.fill"),
        "google": (0x4285F4, 0x34A853, nil), "gmail": (0xEA4335, 0xC5221F, "envelope.fill"),
        "apple": (0x555555, 0x1C1C1E, "apple.logo"), "icloud": (0x3693F3, 0x1A6FD8, "icloud.fill"),
        "microsoft": (0x00A4EF, 0x7FBA00, nil), "outlook": (0x0078D4, 0x0A5FB4, "envelope.fill"),
        "netflix": (0xE50914, 0x8B0000, "play.tv.fill"), "spotify": (0x1DB954, 0x14833B, "music.note"),
        "youtube": (0xFF0000, 0xB80000, "play.rectangle.fill"), "amazon": (0xFF9900, 0x232F3E, "cart.fill"),
        "linkedin": (0x0A66C2, 0x004182, nil), "github": (0x24292E, 0x171515, "chevron.left.forwardslash.chevron.right"),
        "reddit": (0xFF4500, 0xCC3700, nil), "twitch": (0x9146FF, 0x6441A5, "gamecontroller.fill"),
        "paypal": (0x003087, 0x009CDE, "creditcard.fill"), "bank": (0x0B6E4F, 0x08503A, "building.columns.fill"),
        "بنك": (0x0B6E4F, 0x08503A, "building.columns.fill"), "aurak": (0x7A1F2B, 0x4A0F18, "graduationcap.fill"),
        "unreal": (0x0E0E0E, 0x2C2C2C, "cube.fill"), "epic games": (0x2F2F2F, 0x111111, "gamecontroller.fill"),
        "chatgpt": (0x10A37F, 0x0B7A5F, "sparkles"), "claude": (0xD97757, 0xB85C3F, "sparkles")
    ]

    static func match(_ name: String) -> (UInt32, UInt32, String?)? {
        let n = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let exact = brands[n] { return exact }
        return brands.first(where: { n.contains($0.key) && $0.key.count > 2 })?.value
    }

    static var knownNames: [String] {
        ["Instagram", "Snapchat", "TikTok", "X", "Facebook", "WhatsApp", "Telegram", "Discord", "Steam",
         "Epic Games", "PlayStation", "Xbox", "Google", "Gmail", "Apple", "iCloud", "Microsoft", "Outlook",
         "Netflix", "Spotify", "YouTube", "Amazon", "LinkedIn", "GitHub", "Reddit", "Twitch", "PayPal", "AURAK"]
    }

    var body: some View {
        let m = Self.match(name)
        let c1 = m.map { Color(hex: $0.0) } ?? Theme.accent.opacity(0.8)
        let c2 = m.map { Color(hex: $0.1) } ?? Theme.accent2
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let icon = m?.2 {
                Image(systemName: icon).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
            } else {
                Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(Theme.font(size * 0.45, .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: c2.opacity(0.4), radius: 8, y: 3)
    }
}

/// Live countdown ring for 2FA codes.
struct TOTPBadge: View {
    var totp: TOTP
    var big = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = totp.secondsRemaining(at: ctx.date)
            let code = totp.code(at: ctx.date)
            let pretty = code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code
            HStack(spacing: 10) {
                Text(pretty)
                    .font(Theme.mono(big ? 34 : 17, .bold))
                    .foregroundStyle(left <= 5 ? Theme.warn : Theme.accent)
                    .contentTransition(.numericText())
                ZStack {
                    Circle().stroke(Theme.surfaceHi, lineWidth: big ? 4 : 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(left) / CGFloat(totp.period))
                        .stroke(left <= 5 ? Theme.warn : Theme.accent, style: StrokeStyle(lineWidth: big ? 4 : 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: left)
                    Text("\(left)").font(Theme.font(big ? 12 : 9, .bold)).foregroundStyle(Theme.sub)
                }
                .frame(width: big ? 34 : 22, height: big ? 34 : 22)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}

struct EmptyStateView: View {
    var mood: EyeMood = .sleepy
    var title: String
    var subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            EyeView(mood: mood, size: 90)
            Text(title).font(Theme.font(18, .bold)).foregroundStyle(Theme.text)
            Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

struct SheetHeader: View {
    var title: String
    var onClose: () -> Void
    var body: some View {
        HStack {
            Text(title).font(Theme.font(22, .heavy)).foregroundStyle(Theme.text)
            Spacer()
            CircleIconButton(icon: "xmark", size: 36, action: onClose)
        }
    }
}
